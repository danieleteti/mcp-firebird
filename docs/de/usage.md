# Durchgespielte Beispiele

[← zurück zur README](../../README-DE.md)

Wie das Gespräch tatsächlich aussieht, sobald der Server registriert ist — von „welche
Tabellen habe ich“ bis zu einer kompletten Optimierungsrunde auf `employee.fdb`.

## Aus Claude heraus nutzen

Ist der Server registriert, redest du mit Claude in normaler Sprache. Claude wählt das passende
`fb_*`-Tool, führt es gegen deine konfigurierte Datenbank aus und macht aus dem Ergebnis direkt
ausführbares SQL. Die folgenden Dialoge setzen die vorbereitete Demo-Datenbank voraus; setz deine
eigenen Tabellen- und Spaltennamen ein.

> In **Claude Desktop** erscheinen die Tools automatisch, und die beiden Prompts tauchen als Befehle auf
> (Menü 🔌 bzw. "+"). In **Claude Code** inspizierst du den Server mit `/mcp`, dort stehen die Prompts
> als Slash-Befehle bereit. Du kannst jederzeit explizit nachhelfen: *"nutz die Firebird-Tools"*.

### 1. Orientierung verschaffen

> **Du:** Mit welcher Firebird-Version bin ich verbunden, und welche Features sind verfügbar?

Claude ruft **`fb_info`** auf und meldet Engine-Version, Dialekt, Zeichensatz und die erkannten
Fähigkeiten (MON$-Tabellen, erklärte Pläne, BOOLEAN, INT128, Zeitzonen, parallele Worker).

> **Du:** Liste die Tabellen der Datenbank auf.

→ **`fb_list_tables`** → `CUSTOMERS`, `ORDERS`, `NOPK_LOG`, `OVERIDX`, `STALE_T`, …

### 2. Ein Schema dokumentieren

> **Du:** Dokumentiere die Tabelle CUSTOMERS.

→ **`fb_generate_documentation`** → Spalten, der Primärschlüssel `CUSTOMER_ID` und die Indizes.

> **Du:** Erzeuge die vollständige Markdown-Dokumentation der ganzen Datenbank und leg sie in einer
> Datei ab.

→ noch einmal **`fb_generate_documentation`** (keine Tabelle = ganze DB). Claude gibt das Markdown
zurück; bitte es, den Text nach `docs/schema.md` zu speichern, wenn du ihn auf der Platte haben willst.

### 3. Eine langsame Query diagnostizieren und beheben

> **Du:** Diese Query ist langsam, warum?
> `SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'`

→ **`fb_analyze_query`** → *"⚠️ NATURAL-Scan auf CUSTOMERS: die gefilterte Spalte `CITY` ist nicht
brauchbar indiziert."*

> **Du:** Schlag einen Index vor, der das behebt.

→ **`fb_suggest_indexes`** → ein direkt ausführbares Statement, dazu die Prüfung:

```sql
CREATE INDEX IDX_CUSTOMERS_CITY ON CUSTOMERS (CITY);
-- Verify: re-run fb_analyze_query; the NATURAL scan on CUSTOMERS should be gone.
```

> **Du:** Und diese hier? `SELECT * FROM CUSTOMERS ORDER BY CITY`

→ **`fb_analyze_query`** meldet einen **externen SORT** (kein brauchbarer Index für die Sortierung).

### 4. Überflüssige Indizes aufräumen

> **Du:** Welche Indizes auf ORDERS kann ich gefahrlos löschen?

→ **`fb_suggest_index_drops`** → meldet `IDX_ORDERS_CUSTOMER_DUP` als Duplikat des systemeigenen
Fremdschlüssel-Index, mit dem `DROP INDEX`-Statement und einem Prüfschritt.

> **Du:** Mach dasselbe für CUSTOMERS.

→ meldet das redundante Linkspräfix (`IDX_CUST_NAME`), den inaktiven Index (`IDX_CUST_CITY`) und den
wenig selektiven Index (`IDX_CUST_STATUS`).

### 5. Die Schema-Gesundheit prüfen

> **Du:** Prüfe die Tabelle NOPK_LOG.

→ **`fb_audit_table`** → *"🛑 kritisch: Tabelle NOPK_LOG hat keinen PRIMARY KEY …"*, mit der Korrektur
per `ALTER TABLE … ADD CONSTRAINT`. Bei `OVERIDX` meldet es zu viele Indizes, bei `STALE_T` veraltete
Statistiken samt der Korrektur `SET STATISTICS INDEX …`.

> **Du:** Führ einen vollständigen Health-Check der Datenbank durch.

→ Claude nutzt den Prompt **`health_check`**: `fb_info` → `fb_list_tables` → `fb_suggest_index_drops`
pro Tabelle → eine einzige, nach Tabellen gruppierte Zusammenfassung mit allem direkt ausführbaren SQL.

### 6. Zielgetriebene Optimierung (iterieren, bis das Ziel erreicht ist)

Der Prompt **`optimization_goal`** bringt Claude zum Schleifen: messen → vorschlagen → neu messen, und
Schluss, sobald das Ziel erreicht ist (oder keine Verbesserung mehr gelingt).

> **Du:** Nutz den Prompt optimization_goal. Optimiere weiter, bis diese Query keinen NATURAL-Scan mehr
> macht:
> `SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'`

Claude:
1. Ruft **`fb_evaluate_goal`** auf (`goal_type=query_no_natural_scan`) → `met: false` (Baseline).
2. Ruft `fb_analyze_query` + `fb_suggest_indexes` auf und legt `CREATE INDEX IDX_CUSTOMERS_CITY …` vor.
3. Du führst das SQL aus (Schreibzugriffe sind standardmäßig aus, siehe [Sicherheit](../../README-DE.md#sicherheit--kompatibilität)).
4. Ruft `fb_evaluate_goal` erneut auf → `met: true`, und hört mit dem Ergebnis auf.

Du kannst das Ziel auch als Zahl formulieren, etwa *"bring diese Query unter 50 ms"*
(`goal_type=query_time_ms`, `threshold=50`).

---

### 7. "Wird es schlimmer, oder war das immer schon so?"

Manche Probleme stecken in keiner einzelnen Abfrage. Sie sammeln sich an.

> **Du:** Die Auftragsmaske kriecht jeden Nachmittag, und niemand hat etwas geändert. Nutze den
> Prompt classify_problem.

→ **`classify_problem`** ordnet das Symptom auf sechs Achsen ein, bevor überhaupt ein Tool angefasst
wird: wächst es über Stunden oder tritt es sofort unter Last auf, folgt es dem Volumen oder der
Nebenläufigkeit, konzentriert es sich auf wenige Tabellen, vergeht die Zeit mit Arbeiten oder mit
Warten. Danach benennt es die dominante der sieben Klassen und die Argumentation, die dort
konvergiert. "Um 9 geht es, um 16 Uhr unbenutzbar, morgen wieder gut" ist zeitliche Anhäufung, und
keine Plananalyse wird das je erklären.

> **Du:** Miss die Datenbank jetzt 30 Sekunden lang, und nach der Mittagspause noch einmal.

→ **`fb_sample_activity`** liest die MON$-Zähler zweimal über das Fenster und berichtet die
Differenz: sequenziell und über Index gelesene Datensätze, bewegte Seiten, eingesammelte Versionen,
gestartete Transaktionen, und ob der Transaktionshorizont überhaupt vorangekommen ist. Ein Horizont,
der stillsteht, während laufend Transaktionen starten, ist Garbage Collection, die nicht
vorankommt: in einer einzelnen Momentaufnahme unsichtbar, zwischen zweien offensichtlich.

Jedes Tool schließt außerdem damit, **was es nicht ausgeschlossen hat**. Ein sauberer Plan ist keine
schnelle Query, und ein ruhiges Fenster ist kein gesundes System: MON$ zählt geleistete Arbeit, nie
die Zeit, die auf die Erlaubnis dazu gewartet wurde.

## Durchgespielte Sitzung: eine Query auf `employee.fdb` optimieren

Ein kompletter Durchlauf gegen die Beispieldatenbank **`employee`**, die Firebird mitliefert
(`examples/empbuild/employee.fdb`). Die Ausgaben unten sind wörtliche Tool-Ergebnisse.

> **Du:** Analysiere diese Firebird-Query und schlag Verbesserungen vor:
> ```sql
> SELECT emp_no, first_name, last_name, salary
> FROM employee
> WHERE salary > 60000
> ```

**1. Baseline.** `fb_analyze_query` liefert (Engine `3.0.12`):

```
PLAN (EMPLOYEE NATURAL)
```
> NATURAL-Scan auf: EMPLOYEE. Führ `fb_suggest_indexes` auf dieser Query aus, um direkt ausführbares
> DDL zu bekommen.

`NATURAL` heißt: Firebird liest **jede** Zeile von `EMPLOYEE` und wirft die mit `salary <= 60000`
wieder weg. Es gibt keinen Index auf `SALARY`, über den es suchen könnte.

**2. Das Problem bestätigen.** `fb_evaluate_goal` (`goal_type=query_no_natural_scan`):

```json
{ "goal_type": "query_no_natural_scan", "measured": 1.0, "met": false,
  "iteration_hint": "plan: PLAN (EMPLOYEE NATURAL)", "engine_version": "3.0.12" }
```

**3. Die Korrektur holen.** `fb_suggest_indexes`:

```sql
CREATE INDEX IDX_EMPLOYEE_SALARY ON EMPLOYEE (salary);
```
> **Verify:** `fb_analyze_query` erneut ausführen; der Plan sollte `IDX_EMPLOYEE_SALARY` verwenden und
> `EMPLOYEE NATURAL` nicht mehr zeigen. Danach `SET STATISTICS INDEX IDX_EMPLOYEE_SALARY;` ausführen, um
> die Selektivität aufzufrischen.

**4. Anwenden** (der Server liest nur, das DDL führst du selbst aus), dann **erneut analysieren**: der Plan wird zu `PLAN (EMPLOYEE INDEX (IDX_EMPLOYEE_SALARY))`, und
`fb_evaluate_goal` liefert `met: true`.

**Wann du den Index *nicht* anlegen solltest.** Der Gewinn entsteht daraus, dass `salary > 60000`
**selektiv** ist, also wenige Zeilen trifft. Träfe das Prädikat den größten Teil der Tabelle (etwa bei
`salary > 0`), wäre der NATURAL-Scan tatsächlich der günstigere Plan, und der Index brächte nur
zusätzlichen Schreibaufwand. Nicht jeder NATURAL-Scan ist ein Fehler.
