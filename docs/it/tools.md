# I tool in dettaglio

[← torna al README](../../README-IT.md)

Il catalogo completo: cosa fa ogni tool, come decide l'advisor degli indici, i prompt e la
risorsa, più le chiamate `tools/call` grezze se piloti il server da solo.

## I tool (15 free, più i 9 Enterprise annunciati in `tools/list`)

| Tool | Argomenti | A cosa serve |
|---|---|---|
| `fb_info` | *(nessuno)* | Versione del motore e funzionalità rilevate (JSON) |
| `fb_list_tables` | *(nessuno)* | Elenca le tabelle utente |
| `fb_generate_documentation` | `table_name?` | Documentazione Markdown di una tabella — colonne (con il **dominio** su cui poggiano), PK, indici, **vincoli CHECK**, trigger con l'evento su cui scattano — o dell'intero database, che elenca anche le **view con la loro SELECT**, le stored procedure con i parametri, le funzioni e i package (3.0+). Se il nome è quello di una view, documenta la view |
| `fb_query` | `sql`, `max_rows?` | Esegue una SELECT in sola lettura e restituisce le righe come tabella Markdown, con un tetto a `max_rows` (default 100, massimo 1000) **e a ~20 000 caratteri**, perché un tetto sulle righe limita le righe e non la larghezza. Tutto ciò che non è una SELECT semplice viene rifiutato, e così uno statement con placeholder non valorizzati |
| `fb_analyze_query` | `sql` | Analisi del piano di accesso (scansioni NATURAL e SORT esterni), il **piano esteso** del motore su 3.0+ (nomi degli indici, quanta parte dell'indice la query ha usato, strategia di join) **e costo misurato**: una SELECT viene eseguita una volta e si riportano i record e le pagine che ha davvero toccato |
| `fb_suggest_indexes` | `sql` | Consiglia l'indice per una query: B-tree normale, **su espressione** (`COMPUTED BY`), **parziale** (5.0+) oppure un indice per l'**ordinamento** — e **nessun indice** quando la scansione è il piano giusto. Prima di proporre qualcosa di strutturale aggiorna le statistiche vecchie |
| `fb_suggest_index_drops` | `table_name` | Segnala indici duplicati, con prefisso ridondante, inattivi o poco selettivi |
| `fb_audit_table` | `table_name` | Stato di salute dello schema: PK assente, troppi indici, statistiche vecchie |
| `fb_audit_security` | *(nessuno)* | Tutti i grant registrati nel database, una riga per beneficiario e oggetto, più i tre rilievi che di solito sono errori: privilegi in mano a **PUBLIC** (critical se comprendono la scrittura), delega tramite **WITH GRANT OPTION**, e ruoli di cui non è membro nessuno |
| `fb_evaluate_goal` | `goal_type`, `target`, `threshold` | Verifica deterministica dell'obiettivo (è il motore del ciclo di ottimizzazione) |
| `fb_monitor_transactions` | `stale_minutes?` | Salute di transazioni e sweep **in questo istante**: distanza fra OIT/OAT/Next, transazioni lunghe che bloccano (con il loro ultimo statement SQL) |
| `fb_sample_activity` | `seconds?` | Legge i contatori MON$ due volte su una finestra e riporta la differenza: record letti in sequenza e per indice, pagine movimentate, versioni raccolte, e se l'orizzonte delle transazioni è avanzato |
| `fb_monitor_attachments` | `idle_minutes?`, `long_statement_seconds?` | Chi è attaccato adesso, da dove e cosa sta eseguendo; segnala le connessioni ferme da più di `idle_minutes` (default 30) e le statement in esecuzione da più di `long_statement_seconds` (default 60). Non vede la contesa: MON$ conta il lavoro svolto, mai il tempo passato ad aspettare il permesso di svolgerlo |
| `fb_backup_start` | *(nessuno)* | Avvia un backup `gbak` dentro `firebird.backup_dir` e **torna prima che il backup finisca**. Poi il job ripristina quello che ha scritto in un database usa-e-getta e lo cancella |
| `fb_backup_status` | *(nessuno)* | Il backup in corso o l'ultimo fatto: fase, dimensione, quanto è durata ogni parte, e se il backup è stato dimostrato ripristinabile |

### Cosa serve al backup, e cosa dimostra

Un backup che nessuno ha mai ripristinato è un file, non un backup. Per questo il job non si ferma
quando ha scritto il `.fbk`: lo ripristina in un database usa-e-getta con `gbak -c` (che *crea*, e
rifiuta un file già esistente), controlla che il database sia arrivato, e lo butta via.
`fb_backup_status` dice *«questo backup si ripristina»*, non *«esiste un file»*.

Gli servono tre cose, tutte a carico tuo:

- **`firebird.backup_dir`** nel `.env`. La destinazione si dichiara una volta sola, lì, e non arriva
  mai dal chiamante — i tool prendono istruzioni da chiunque stia parlando col server.
- **`gbak.exe` accanto al tuo `fbclient.dll`.** Il server pilota un tool client *locale*, come
  l'analisi dei piani pilota un `isql.exe` locale. Non si attacca mai al Services Manager.
- **Spazio per una seconda copia del database** su quel disco, per tutta la durata del ripristino
  di verifica.

Un backup per volta: `fb_backup_start` rifiuta mentre uno è in corso e ti dice di fare polling. E
quello che non può dirti: se il backup è **fuori da questa macchina**. Un backup dimostrato
ripristinabile, ma appoggiato sullo stesso disco del database da cui viene, sopravvive a una pagina
corrotta, non alla perdita del disco.

Ogni indicazione arriva con un **Finding**, l'**SQL** già pronto e una **Verify**. Ogni tool
di analisi chiude anche dichiarando **che cosa non ha escluso**: un piano non vede la contesa,
uno snapshot non vede l'accumulo, e una risposta pulita a una domanda stretta non è un
certificato di buona salute.

## Come decide `fb_suggest_indexes`, e in che ordine

Un indice non è gratis: viene scritto a ogni INSERT, UPDATE e DELETE su quella tabella, per
tutto il tempo in cui esiste. Per questo il consigliere propone **il rimedio più economico che
spiega ciò che il piano ha fatto**, ed è disposto a non proporre nulla.

1. **Aggiorna, non costruire.** Firebird memorizza la selettività di un indice quando l'indice
   viene creato e non la ricalcola mai. Un indice che esiste e viene ignorato può esserlo perché
   l'ottimizzatore lo sta valutando sui dati dell'anno scorso — e rispondere con un secondo
   indice lascia il database a pagare scritture per sempre solo perché un numero andava
   rinfrescato. Qui nessuno dice *"l'indice non viene usato, ed è giusto così"* finché il valore
   memorizzato non è stato confrontato con quello reale.
2. **Risveglia, non duplicare.** Un indice `INACTIVE` sulla colonna filtrata è
   `ALTER INDEX … ACTIVE`, mai un secondo indice accanto a quello che dorme.
3. **Dì quando la scansione è giusta.** La query viene eseguita una volta e i record letti
   vengono confrontati con le righe restituite. Una scansione che tiene quasi tutto quello che
   legge *è* il piano corretto, e lo è anche la scansione di una tabella grande quanto una
   manciata di pagine: entrambe tornano come Finding con i numeri e **senza SQL da eseguire**.
4. **Poi, la forma giusta.** `UPPER(NOME) = ?` non può usare nessun indice normale e ottiene un
   indice su espressione, con l'espressione riportata esattamente com'era scritta — Firebird lo
   usa solo su corrispondenza esatta. `STATO = 'ATTIVO' AND TAG = ?` ottiene l'indice sulla
   colonna con cui si cerca, più la forma parziale su 5.0+, che indicizza solo la popolazione che
   la query guarda davvero. Un `ORDER BY` su colonna non indicizzata ottiene un indice i cui
   segmenti corrispondono all'ordinamento **nella sua direzione** — e la constatazione, invece di
   un indice inutilizzabile, che nessun indice singolo serve `ORDER BY a ASC, b DESC`.

Ogni Finding porta con sé i numeri su cui la regola è stata applicata, così un DBA che non è
d'accordo con una soglia può discutere della soglia e non dello strumento. Il progetto e le
misure su cui si basa sono in
[`docs/superpowers/specs/2026-08-07-index-advisor.md`](../superpowers/specs/2026-08-07-index-advisor.md).

> **Nota:** per misurare, questo tool **esegue la query** su cui viene interrogato — una volta,
> dentro la transazione read-only, e soltanto quando il piano mostra davvero una scansione o un
> ordinamento. Su una tabella grande è una scansione completa. Non esegue mai nulla che non sia
> una SELECT semplice, e non esegue affatto uno statement con parametri non valorizzati: quelli
> arrivano al motore come NULL, non corrispondono a niente e produrrebbero la misura di una query
> che nessuno esegue.

## Cosa vede `fb_audit_security`, e cosa non può vedere

I grant stanno nel database: `RDB$USER_PRIVILEGES` e `RDB$ROLES`, leggibili da una normale
connessione SQL — che è esattamente ciò che è l'edizione free. Quindi il report è completo sui
*grant*, e muto su tutto ciò che un grant non è. Due categorie di riga restano fuori, perché
nessuno le ha concesse e elencarle seppellisce quelle che qualcuno ha concesso davvero: i
privilegi del motore su `RDB$`/`MON$` e quelli che ogni owner ha sui propri oggetti.

Non vede l'**elenco degli account**, i **ruoli amministrativi**, la policy delle password né chi
riesce ad arrivare alla porta: stanno nel security database e nella configurazione del server, e
leggerli richiede un attach amministrativo che questa edizione non fa. Un database con tutti i
grant a posto può comunque essere raggiungibile da un account che nessuno ricorda di aver creato.

Tre rilievi, nell'ordine in cui contano:

1. **PUBLIC.** Non è un gruppo a cui qualcuno è stato aggiunto: è chiunque riesca a
   connettersi, compresi gli account creati dopo il grant. `critical` se i privilegi comprendono
   INSERT, UPDATE o DELETE, `warning` altrimenti.
2. **WITH GRANT OPTION.** Chi lo detiene può allargare gli accessi senza che nessun DBA lo veda,
   e il grant che ne esce è indistinguibile da uno fatto da un amministratore.
3. **Un ruolo senza membri.** O i privilegi che porta non servono, o gli account che dovrebbero
   averli stanno usando grant diretti.

## Prompt (3)

- **`optimization_goal`**: il ciclo guidato da un obiettivo. Lo fissi, l'assistente itera sui tool
  `fb_*` e richiama `fb_evaluate_goal` finché non ottiene `met: true`. Si ferma da solo dopo troppe
  iterazioni o se smette di fare progressi.
- **`health_check`**: esame guidato della salute dell'intero database — gli indici tabella per
  tabella, poi i grant in una sola passata, dicendo dove la parte sui grant si ferma.
- **`classify_problem`**: si parte dal sintomo, non da un tool. Colloca il problema su sei
  assi (forma temporale, volume contro concorrenza, località, coordinamento contro esecuzione,
  sensibilità all'osservazione, ambiente), nomina la classe dominante fra le sette e dice
  quale ragionamento converge — compreso quando la risposta è che una connessione SQL non può
  chiudere la questione. Segue la tassonomia di Cisar & Reeves, *Practical Firebird
  Performance Diagnostics* (IBPhoenix, 2026).

## Risorse (1)

- **`firebird://schema`**: lo schema del database, live, come singola risorsa.

## Chiamare i tool direttamente

Qualche esempio di chiamata (gli `arguments` di `tools/call` MCP):

```jsonc
// Describe a table (omit table_name for the whole database)
{ "name": "fb_generate_documentation", "arguments": { "table_name": "CUSTOMERS" } }

// Analyze a query's plan (flags NATURAL scans and external SORTs)
{ "name": "fb_analyze_query", "arguments": { "sql": "SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'" } }

// Suggest indexes for a slow query
{ "name": "fb_suggest_indexes", "arguments": { "sql": "SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'" } }

// Which indexes to drop on a table
{ "name": "fb_suggest_index_drops", "arguments": { "table_name": "ORDERS" } }

// Schema-health audit
{ "name": "fb_audit_table", "arguments": { "table_name": "NOPK_LOG" } }

// Che cosa è cambiato negli ultimi 10 secondi (una finestra, non un istante)
{ "name": "fb_sample_activity", "arguments": { "seconds": 10 } }

// Goal check: "this query must no longer do a NATURAL scan"
{ "name": "fb_evaluate_goal",
  "arguments": { "goal_type": "query_no_natural_scan",
                 "target": "SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'",
                 "threshold": 0 } }
```

I `goal_type` che `fb_evaluate_goal` accetta: `query_no_natural_scan`, `query_time_ms`,
`no_redundant_indexes` e `no_stale_index_statistics` — l'unico la cui prima mossa non scrive
niente di strutturale: conta gli indici di una tabella la cui selettività memorizzata non descrive
più i dati, così il ciclo può dire la verità all'ottimizzatore prima di chiedere al database di
portarsi dietro un altro indice. In
[`docs/firebird-problem-catalog.md`](../firebird-problem-catalog.md) trovi ogni problema che i
tool sanno rilevare, la fixture che lo provoca e la milestone in cui arriva.

## I tool Enterprise

Questi nove compaiono in `tools/list` anche qui, così il tuo assistente sa che esistono e sa
dirti cosa ci farebbe. Se li chiami in questa edizione rispondono con un `isError` che spiega come
averli. Sono implementati nell'[edizione Enterprise](editions.md#edizione-enterprise), che si attacca al
Services Manager da amministratore e legge configurazione e hardware del server: privilegi che
questa edizione non chiede mai.

| Tool | Argomenti | Cosa fa |
|---|---|---|
| `fb_diagnose` | *(nessuno)* | Parti da qui quando qualcosa non va e non sai perché: cosa si sa già, cosa chiedere, e il percorso da seguire |
| `fb_analyze_config` | *(nessuno)* | Legge `firebird.conf` e `databases.conf` e passa in rassegna ogni impostazione che conta (page buffers, `TempCacheLimit`, `LockHashSlots`, `MaxUnflushedWrites`, `GCPolicy`, worker paralleli), misurandola su *questa* versione del motore e su *questa* architettura del server, visto che i default, e perfino l'esistenza di un parametro, cambiano con entrambe |
| `fb_analyze_storage` | `table_name?` | Il quadro fisico che nessuna `SELECT` ti fa vedere: profondità degli indici, riempimento delle pagine, lunghezza delle catene di versioni dei record, distribuzione delle pagine |
| `fb_parse_log` | *(nessuno)* | Ti riporta `firebird.log` via Services API e separa il rumore da quello che conta: bugcheck, pagine corrotte, errori di I/O, sweep che sono partiti, o che non sono mai partiti |
| `fb_capture_trace` | *(nessuno)* | Apre una sessione limitata di Trace API, campiona il carico vero e mette in fila gli statement che costano davvero, come distribuzione delle latenze e non come media |
| `fb_trace_start` | `duration_seconds?` | Apre la finestra lunga: fino a due ore di cattura via Trace API, drenate su disco in background mentre la chiamata torna subito |
| `fb_trace_status` | *(nessuno)* | Riporta la cattura in corso: tempo trascorso contro durata, byte catturati, e se la sessione sta ancora osservando |
| `fb_trace_stop` | *(nessuno)* | Ferma la cattura, o recupera una già finita, e restituisce lo stesso report ordinato di `fb_capture_trace`, su ore invece che su secondi |
| `fb_analyze_host` | `config_dir?` | Il motore contro il suo hardware: la RAM contro la memoria che la configurazione impegna davvero, i core contro `MaxParallelWorkers` e `CpuAffinityMask`, lo spazio libero contro la dimensione del database, e se le pagine che mancano costano un seek |

E poi la parte che ne fa un prodotto e non un referto: **baseline ed esperimenti.** Misuri sotto
carico vero, cambi un parametro, rimisuri, e ottieni un verdetto su quanto si è mossa la coda della
distribuzione, con il rollback se non si è mossa.

Per la maggior parte di questi parametri la documentazione di Firebird non indica un valore
ottimale, e non lo facciamo nemmeno noi. Quello che l'edizione Enterprise ti dà è la mappa che porta
dal sintomo al parametro che lo spiega, e il banco di prova che dimostra che la modifica ha
funzionato sul tuo database.
