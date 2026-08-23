# Esempi pratici

[← torna al README](../../README-IT.md)

Come si svolge davvero la conversazione una volta registrato il server, da «quali tabelle
ho» fino a un giro completo di ottimizzazione su `employee.fdb`.

## Usarlo da Claude

Registrato il server, gli parli normalmente: sceglie lui il tool `fb_*` giusto, lo esegue sul
database che hai configurato, e ti restituisce SQL già pronto. Gli scambi qui sotto girano sul
database demo; al posto di tabelle e colonne metti le tue.

> In **Claude Desktop** i tool compaiono da soli e i tre prompt li trovi fra i comandi (menu 🔌 /
> "+"). In **Claude Code** usa `/mcp` per ispezionare il server, e i prompt sono slash command. E
> puoi sempre forzargli la mano: *"usa i tool firebird"*.

### 1. Farsi un'idea

> **Tu:** A che versione di Firebird sono collegato, e cosa ho a disposizione?

Claude chiama **`fb_info`** e riporta versione del motore, dialetto, charset e funzionalità
rilevate (tabelle MON$, piani con explain, BOOLEAN, INT128, fusi orari, worker paralleli).

> **Tu:** Elencami le tabelle del database.

→ **`fb_list_tables`** → `CUSTOMERS`, `ORDERS`, `NOPK_LOG`, `OVERIDX`, `STALE_T`, …

### 2. Documentare uno schema

> **Tu:** Documenta la tabella CUSTOMERS.

→ **`fb_generate_documentation`** → colonne, la chiave primaria `CUSTOMER_ID` e gli indici.

> **Tu:** Genera la documentazione Markdown di tutto il database e mettila in un file.

→ ancora **`fb_generate_documentation`**, senza tabella: prende l'intero DB. Claude ti restituisce
il Markdown; se lo vuoi su disco chiedigli di salvarlo in `docs/schema.md`.

### 3. Capire perché una query è lenta, e sistemarla

> **Tu:** Questa query è lenta, perché?
> `SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'`

→ **`fb_analyze_query`** → *"⚠️ scansione NATURAL su CUSTOMERS: la colonna filtrata `CITY` non ha
un indice utile."*

> **Tu:** Suggeriscimi un indice che risolva.

→ **`fb_suggest_indexes`** → uno statement già pronto, e come verificarlo:

```sql
CREATE INDEX IDX_CUSTOMERS_CITY ON CUSTOMERS (CITY);
-- Verify: re-run fb_analyze_query; the NATURAL scan on CUSTOMERS should be gone.
```

> **Tu:** E questa? `SELECT * FROM CUSTOMERS ORDER BY CITY`

→ **`fb_analyze_query`** segnala un **SORT esterno**: per quell'ordinamento non c'è un indice
utilizzabile.

### 4. Fare pulizia fra gli indici

> **Tu:** Quali indici su ORDERS posso togliere tranquillamente?

→ **`fb_suggest_index_drops`** → segnala `IDX_ORDERS_CUSTOMER_DUP`, doppione dell'indice di sistema
della foreign key, con il `DROP INDEX` e il passo di verifica.

> **Tu:** Fai lo stesso su CUSTOMERS.

→ segnala il prefisso sinistro ridondante (`IDX_CUST_NAME`), l'indice inattivo (`IDX_CUST_CITY`) e
quello poco selettivo (`IDX_CUST_STATUS`).

### 5. Controllare la salute dello schema

> **Tu:** Fai l'audit della tabella NOPK_LOG.

→ **`fb_audit_table`** → *"🛑 critico. La tabella NOPK_LOG non ha PRIMARY KEY …"*, con l'
`ALTER TABLE … ADD CONSTRAINT` che rimedia. Su `OVERIDX` segnala che gli indici sono troppi; su
`STALE_T` che le statistiche sono vecchie, e ti dà il `SET STATISTICS INDEX …`.

> **Tu:** Fammi un health check completo del database.

→ Claude usa il prompt **`health_check`**: `fb_info` → `fb_list_tables` → `fb_suggest_index_drops`
su ogni tabella → `fb_audit_security` una volta → un riepilogo in due parti: l'SQL degli indici
raggruppato per tabella, poi i rilievi sui grant, prima i critical.

### 6. Ottimizzare per obiettivo (finché non è raggiunto)

Il prompt **`optimization_goal`** manda Claude in un ciclo: misura, propone, rimisura, e si ferma
appena l'obiettivo è raggiunto, o quando non riesce più a migliorarlo.

> **Tu:** Usa il prompt optimization_goal. Continua a ottimizzare finché questa query non smette di
> fare una scansione NATURAL:
> `SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'`

Claude:
1. Chiama **`fb_evaluate_goal`** (`goal_type=query_no_natural_scan`) → `met: false`, è la baseline.
2. Chiama `fb_analyze_query` e `fb_suggest_indexes`, e ti presenta `CREATE INDEX IDX_CUSTOMERS_CITY …`.
3. L'SQL lo esegui tu, perché di base le scritture sono spente (vedi
   [Innocuo per il database](../../README-IT.md#innocuo-per-il-database-e-compatibile)).
4. Richiama `fb_evaluate_goal` → `met: true`, e si ferma lì.

L'obiettivo puoi anche darlo in numeri, per esempio *"portami questa query sotto i 50 ms"*
(`goal_type=query_time_ms`, `threshold=50`).

---

### 7. "Sta peggiorando, o è sempre stato così?"

Certi problemi non stanno in nessuna query. Si accumulano.

> **Tu:** La schermata degli ordini rallenta ogni pomeriggio e nessuno ha toccato niente. Usa il
> prompt classify_problem.

→ **`classify_problem`** colloca il sintomo su sei assi prima di toccare un tool: cresce nell'arco
di ore o compare all'istante sotto carico, segue il volume o la concorrenza, si concentra su poche
tabelle, il tempo se ne va lavorando o aspettando. Poi nomina la classe dominante fra le sette e il
ragionamento che converge. "Alle 9 va, alle 16 è inusabile, domani va di nuovo" è accumulo
temporale, e nessuna analisi di piano lo spiegherà mai.

> **Tu:** Campiona il database per 30 secondi adesso, e di nuovo dopo pranzo.

→ **`fb_sample_activity`** legge i contatori MON$ due volte lungo la finestra e riporta la
differenza: record letti in sequenza e per indice, pagine movimentate, versioni raccolte,
transazioni avviate, e se l'orizzonte delle transazioni si è mosso. Un orizzonte fermo mentre le
transazioni continuano a partire è la garbage collection che non va da nessuna parte: invisibile in
un singolo snapshot, evidente fra due.

Ogni tool chiude anche dichiarando **che cosa non ha escluso**. Un piano pulito non è una query
veloce, e una finestra tranquilla non è un sistema sano: MON$ conta il lavoro fatto, mai il tempo
passato ad aspettare il permesso di farlo.

## Una sessione vera: ottimizzare una query su `employee.fdb`

Un giro completo sul database di esempio **`employee`** che Firebird si porta dietro
(`examples/empbuild/employee.fdb`). Gli output qui sotto sono i risultati veri dei tool.

> **Tu:** Analizza questa query Firebird e suggerisci come migliorarla:
> ```sql
> SELECT emp_no, first_name, last_name, salary
> FROM employee
> WHERE salary > 60000
> ```

**1. Baseline.** `fb_analyze_query` risponde (motore `3.0.12`):

```
PLAN (EMPLOYEE NATURAL)
```
> Scansione NATURAL su: EMPLOYEE. Lancia `fb_suggest_indexes` su questa query per avere il DDL già
> pronto.

`NATURAL` vuol dire che Firebird legge **tutte** le righe di `EMPLOYEE` e butta via quelle con
`salary <= 60000`: su `SALARY` non c'è un indice su cui fare seek.

**2. Conferma del problema.** `fb_evaluate_goal` (`goal_type=query_no_natural_scan`):

```json
{ "goal_type": "query_no_natural_scan", "measured": 1.0, "met": false,
  "iteration_hint": "plan: PLAN (EMPLOYEE NATURAL)", "engine_version": "3.0.12" }
```

**3. La soluzione.** `fb_suggest_indexes`:

```sql
CREATE INDEX IDX_EMPLOYEE_SALARY ON EMPLOYEE (salary);
```
> **Verify:** rilancia `fb_analyze_query`; il piano deve usare `IDX_EMPLOYEE_SALARY` e non mostrare
> più `EMPLOYEE NATURAL`. Poi esegui `SET STATISTICS INDEX IDX_EMPLOYEE_SALARY;` per aggiornare la
> selettività.

**4. Applicala** (il server è in sola lettura, il DDL lo lanci tu) e **rianalizza**: il piano
diventa `PLAN (EMPLOYEE INDEX (IDX_EMPLOYEE_SALARY))` e `fb_evaluate_goal` risponde `met: true`.

**Quando l'indice *non* va aggiunto.** Il guadagno c'è perché `salary > 60000` è **selettivo**:
poche righe. Se il predicato prendesse quasi tutta la tabella (`salary > 0`, per dire), il piano più
economico sarebbe proprio la scansione NATURAL, e l'indice aggiungerebbe solo peso in scrittura. Non
tutte le scansioni NATURAL sono un bug.
