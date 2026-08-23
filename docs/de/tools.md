# Tool-Referenz

[← zurück zur README](../../README-DE.md)

Der vollständige Katalog: was jedes Tool tut, wie der Index-Berater entscheidet, die
Prompts und die Ressource, dazu die rohen `tools/call`-Aufrufe.

## Die Tools (15 kostenlose, dazu 9 Enterprise-Tools, die in `tools/list` angekündigt werden)

| Tool | Argumente | Zweck |
|---|---|---|
| `fb_info` | *(keine)* | Engine-Version + erkannte Fähigkeiten (JSON) |
| `fb_list_tables` | *(keine)* | Listet die Benutzertabellen auf |
| `fb_generate_documentation` | `table_name?` | Markdown-Doku für eine Tabelle — Spalten (mit der **Domäne**, auf der sie beruhen), PK, Indizes, **CHECK-Constraints**, Trigger samt auslösendem Ereignis — oder für die ganze Datenbank, die zusätzlich **Views mit ihrem SELECT**, Stored Procedures mit ihren Parametern, Funktionen und Packages (3.0+) auflistet. Bei einem View-Namen dokumentiert es den View |
| `fb_query` | `sql`, `max_rows?` | Führt ein nur lesendes SELECT aus und gibt die Zeilen als Markdown-Tabelle zurück, gedeckelt auf `max_rows` (Standard 100, Obergrenze 1000) **und auf ~20 000 Zeichen**, denn ein Zeilendeckel begrenzt Zeilen und nicht Breite. Alles, was kein reines SELECT ist, wird abgewiesen, ebenso ein Statement mit ungebundenen Platzhaltern |
| `fb_analyze_query` | `sql` | Analyse des Zugriffsplans (NATURAL-Scans und externe SORTs), der **erklärte Plan** der Engine ab 3.0 (Indexnamen, wie viel vom Index die Abfrage genutzt hat, Join-Strategie) **und gemessene Kosten**: ein reines SELECT wird einmal ausgeführt, berichtet werden die Datensätze und Seiten, die es tatsächlich angefasst hat |
| `fb_suggest_indexes` | `sql` | Indexrat für eine Abfrage: gewöhnlicher B-Baum, **Ausdrucksindex** (`COMPUTED BY`), **partieller Index** (ab 5.0) oder ein Index für die **Sortierung** — und **gar kein Index**, wenn der Scan der richtige Plan ist. Vor jedem strukturellen Vorschlag werden veraltete Statistiken aufgefrischt |
| `fb_suggest_index_drops` | `table_name` | Meldet doppelte, präfix-redundante, inaktive und wenig selektive Indizes |
| `fb_audit_table` | `table_name` | Prüfung der Schema-Gesundheit: fehlender PK, zu viele Indizes, veraltete Statistiken |
| `fb_audit_security` | *(keine)* | Jede in der Datenbank verzeichnete Berechtigung, eine Zeile je Empfänger und Objekt, dazu die drei Befunde, die meist ein Fehler sind: Rechte in der Hand von **PUBLIC** (critical, wenn sie Schreibrechte enthalten), Delegation über **WITH GRANT OPTION** und Rollen ohne Mitglieder |
| `fb_evaluate_goal` | `goal_type`, `target`, `threshold` | Deterministische Zielprüfung (treibt die Optimierungsschleife an) |
| `fb_monitor_transactions` | `stale_minutes?` | Zustand von Transaktionen und Sweep **in diesem Augenblick**: Abstand zwischen OIT/OAT/Next, blockierende Langläufer (samt ihrem letzten SQL-Statement) |
| `fb_sample_activity` | `seconds?` | Liest die MON$-Zähler zweimal über ein Zeitfenster und berichtet die Differenz: sequenziell und über Index gelesene Datensätze, bewegte Seiten, eingesammelte Versionen, und ob der Transaktionshorizont vorangekommen ist |
| `fb_monitor_attachments` | `idle_minutes?`, `long_statement_seconds?` | Wer gerade verbunden ist, von wo, und was jede Verbindung ausführt; meldet Verbindungen, die länger als `idle_minutes` (Standard 30) untätig sind, und Statements, die länger als `long_statement_seconds` (Standard 60) laufen. Konkurrenz sieht es nicht: MON$ zählt geleistete Arbeit, nie die Wartezeit auf die Erlaubnis dazu |
| `fb_backup_start` | *(keine)* | Startet ein `gbak`-Backup in `firebird.backup_dir` und **kehrt zurück, bevor das Backup fertig ist**. Danach stellt der Job das Geschriebene in eine Wegwerf-Datenbank zurück und löscht sie wieder |
| `fb_backup_status` | *(keine)* | Das laufende oder letzte Backup: Phase, Größe, Dauer je Schritt, und ob das Backup nachweislich zurückspielbar ist |

### Was das Backup braucht, und was es beweist

Ein Backup, das nie zurückgespielt wurde, ist eine Datei und kein Backup. Deshalb hört der Job nicht
beim Schreiben der `.fbk` auf: er spielt sie mit `gbak -c` in eine Wegwerf-Datenbank zurück (das
*erzeugt* und verweigert eine vorhandene Datei), prüft, dass die Datenbank angekommen ist, und wirft
sie weg. `fb_backup_status` sagt *„dieses Backup lässt sich zurückspielen“*, nicht *„eine Datei
existiert“*.

Drei Dinge braucht es, und die stellst du:

- **`firebird.backup_dir`** in der `.env`. Das Ziel wird dort einmal deklariert und kommt nie vom
  Aufrufer — die Tools nehmen Anweisungen von jedem entgegen, der mit dem Server spricht.
- **`gbak.exe` neben deiner `fbclient.dll`.** Der Server steuert ein *lokales* Client-Werkzeug,
  genau wie die Plan-Analyse ein lokales `isql.exe` steuert. Nie über den Services Manager.
- **Platz für eine zweite Kopie der Datenbank** auf dieser Platte, solange die Prüf-Rücksicherung
  läuft.

Ein Backup zur Zeit: `fb_backup_start` lehnt ab, solange eines läuft, und verweist aufs Pollen. Und
was es nicht sagen kann: ob das Backup **von dieser Maschine weg** ist. Ein nachweislich
zurückspielbares Backup auf derselben Platte wie die Datenbank, aus der es stammt, überlebt eine
defekte Seite, aber nicht den Verlust der Platte.

Jeder Befund kommt mit einem **Finding**, direkt ausführbarem **SQL** und einem
**Verify**-Schritt. Jedes Analyse-Tool schließt außerdem damit, **was es nicht ausgeschlossen
hat**: ein Plan sieht keine Konkurrenz, eine Momentaufnahme sieht keine Anhäufung, und eine
saubere Antwort auf eine enge Frage ist kein Gesundheitszeugnis.

## Was `fb_suggest_indexes` entscheidet, und in welcher Reihenfolge

Ein Index ist nicht umsonst: Er wird bei jedem INSERT, UPDATE und DELETE auf dieser Tabelle
mitgeschrieben, solange es ihn gibt. Deshalb schlägt der Berater **das billigste Mittel vor, das
erklärt, was der Plan getan hat** — und er ist bereit, gar nichts vorzuschlagen.

1. **Auffrischen statt bauen.** Firebird speichert die Selektivität eines Index beim Anlegen und
   berechnet sie nie neu. Ein Index, den es gibt und den die Engine ignoriert, wird womöglich
   ignoriert, weil der Optimizer ihn gegen die Daten des letzten Jahres bewertet — und darauf mit
   einem zweiten Index zu antworten lässt die Datenbank für immer Schreiblast zahlen, weil eine
   Zahl aufgefrischt werden musste. Hier sagt niemand *"der Index wird nicht genutzt, und das ist
   richtig so"*, bevor der gespeicherte Wert mit dem tatsächlichen verglichen wurde.
2. **Wecken statt verdoppeln.** Ein `INACTIVE`-Index auf der gefilterten Spalte ist
   `ALTER INDEX … ACTIVE`, nie ein zweiter Index neben dem schlafenden.
3. **Sagen, wann der Scan richtig ist.** Die Abfrage wird einmal ausgeführt, und die gelesenen
   Datensätze werden mit den zurückgegebenen Zeilen verglichen. Ein Scan, der fast alles behält,
   was er liest, *ist* der richtige Plan — und der Scan einer Tabelle, die nur eine Handvoll
   Seiten groß ist, ebenfalls: Beides kommt als Befund mit den Zahlen zurück und **ohne SQL zum
   Ausführen**.
4. **Und dann die richtige Form.** `UPPER(NAME) = ?` kann gar keinen gewöhnlichen Index nutzen und
   bekommt einen Ausdrucksindex, mit dem Ausdruck exakt so, wie er dastand — Firebird nutzt ihn
   nur bei exakter Übereinstimmung. `STATUS = 'AKTIV' AND TAG = ?` bekommt den Index auf der
   Spalte, nach der gesucht wird, dazu ab 5.0 die partielle Form, die nur die Population
   indiziert, die die Abfrage überhaupt ansieht. Ein `ORDER BY` auf einer nicht indizierten Spalte
   bekommt einen Index, dessen Segmente der Sortierung **in ihrer eigenen Richtung** entsprechen —
   und die klare Feststellung, dass kein einzelner Index `ORDER BY a ASC, b DESC` bedienen kann,
   statt eines Vorschlags, der nie benutzt würde.

Jeder Befund führt die Zahlen mit, auf die die Regel angewendet wurde, damit eine DBA, die einen
Schwellwert für falsch hält, über den Schwellwert streiten kann und nicht über das Werkzeug.
Entwurf und Messungen dahinter stehen in
[`docs/superpowers/specs/2026-08-07-index-advisor.md`](../superpowers/specs/2026-08-07-index-advisor.md).

> **Hinweis:** Zum Messen **führt dieses Tool die Abfrage aus**, nach der es gefragt wird — einmal,
> innerhalb der Nur-Lese-Transaktion, und nur dann, wenn der Plan tatsächlich einen Scan oder eine
> Sortierung zeigt. Auf einer großen Tabelle ist das ein vollständiger Scan. Es führt nie etwas
> aus, das kein reines SELECT ist, und ein Statement mit ungebundenen Parametern führt es
> überhaupt nicht aus: Die kommen als NULL bei der Engine an, treffen auf nichts und ergäben die
> Messung einer Abfrage, die niemand ausführt.

## Was `fb_audit_security` sieht — und was nicht

Berechtigungen stehen in der Datenbank: `RDB$USER_PRIVILEGES` und `RDB$ROLES`, lesbar über eine
gewöhnliche SQL-Verbindung — genau das ist die kostenlose Edition. Der Bericht ist also
vollständig, was *Berechtigungen* angeht, und schweigt zu allem, was keine ist. Zwei Arten von
Zeilen bleiben draußen, weil niemand sie vergeben hat und sie die vergebenen zudecken würden:
die eigenen Rechte der Engine auf `RDB$`/`MON$` und das, was jeder Eigentümer auf seinen eigenen
Objekten hält.

Er sieht weder die **Kontenliste** noch die **Admin-Rollen**, die Passwortregeln oder wer den Port
überhaupt erreicht: Das liegt in der Sicherheitsdatenbank und in der Serverkonfiguration, und
dafür braucht es einen administrativen Attach, den diese Edition nicht macht. Eine Datenbank, in
der jede Berechtigung stimmt, kann trotzdem von einem Konto erreichbar sein, an dessen Anlage sich
niemand erinnert.

Drei Befunde, in der Reihenfolge ihrer Bedeutung:

1. **PUBLIC.** Keine Gruppe, der jemand beigetreten ist: jeder, der sich verbinden kann,
   einschließlich der Konten, die nach der Vergabe angelegt wurden. `critical`, wenn INSERT,
   UPDATE oder DELETE dabei sind, sonst `warning`.
2. **WITH GRANT OPTION.** Wer sie hält, kann den Zugriff ausweiten, ohne dass ein DBA es sieht,
   und die entstehende Berechtigung ist von einer administrativen nicht zu unterscheiden.
3. **Eine Rolle ohne Mitglieder.** Entweder werden ihre Rechte nicht gebraucht, oder die Konten,
   die sie halten sollten, arbeiten mit direkten Berechtigungen.

## Prompts (3)

- **`optimization_goal`**, die zielgetriebene Schleife: du setzt ein Ziel, der Assistent iteriert über
  die `fb_*`-Tools und prüft `fb_evaluate_goal` erneut, bis dort `met: true` steht (mit Notbremse bei
  zu vielen Iterationen oder ausbleibendem Fortschritt).
- **`health_check`**: geführte Gesundheitsprüfung der gesamten Datenbank — Indizes Tabelle für
  Tabelle, dann die Berechtigungen in einem Durchgang, und sie sagt, wo dieser Teil endet.
- **`classify_problem`**: beginnt beim Symptom, nicht beim Werkzeug. Ordnet das Problem auf
  sechs Achsen ein (zeitliche Form, Volumen gegen Nebenläufigkeit, Lokalität, Koordination
  gegen Ausführung, Empfindlichkeit gegenüber Beobachtung, Umgebung), benennt die dominante
  der sieben Klassen und sagt, welche Argumentation dort konvergiert — auch dann, wenn die
  Antwort lautet, dass eine SQL-Verbindung das nicht klären kann. Folgt der Taxonomie von
  Cisar & Reeves, *Practical Firebird Performance Diagnostics* (IBPhoenix, 2026).

## Ressourcen (1)

- **`firebird://schema`**: das aktuelle Datenbankschema als eine einzige Ressource.

## Die Tools direkt aufrufen

Ein paar Aufrufbeispiele (MCP `tools/call`, Feld `arguments`):

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

// Was sich in den letzten 10 Sekunden geändert hat (ein Fenster, kein Augenblick)
{ "name": "fb_sample_activity", "arguments": { "seconds": 10 } }

// Goal check: "this query must no longer do a NATURAL scan"
{ "name": "fb_evaluate_goal",
  "arguments": { "goal_type": "query_no_natural_scan",
                 "target": "SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'",
                 "threshold": 0 } }
```

Werte für `goal_type` in `fb_evaluate_goal`, die M1 unterstützt: `query_no_natural_scan`,
`query_time_ms`, `no_redundant_indexes` und `no_stale_index_statistics` — das einzige, dessen
erster Zug nichts Strukturelles schreibt: Es zählt die Indizes einer Tabelle, deren gespeicherte
Selektivität die Daten nicht mehr beschreibt, damit die Schleife dem Optimizer die Wahrheit sagen
kann, bevor sie die Datenbank bittet, noch einen Index mitzuschleppen. In
[`docs/firebird-problem-catalog.md`](../firebird-problem-catalog.md) steht jedes Problem, das die
Tools erkennen, die Fixture, die es provoziert, und der Meilenstein, in dem es landet.

## Enterprise-Tools

Diese neun erscheinen auch hier in `tools/list`, dein Assistent weiß also von ihnen und kann dir sagen,
was er mit ihnen täte. Rufst du sie in dieser Edition auf, kommt ein `isError`-Ergebnis zurück, das
erklärt, wie du sie bekommst. Implementiert sind sie in der [Enterprise Edition](editions.md#enterprise-edition),
die sich als Administrator an den Services Manager hängt und Konfiguration und Hardware des Servers
liest: Privilegien, um die diese Edition nie bittet.

| Tool | Argumente | Was es tut |
|---|---|---|
| `fb_diagnose` | *(keine)* | Fang hier an, wenn etwas nicht stimmt und du nicht weißt, warum: was schon bekannt ist, was zu fragen ist, und die Route, der zu folgen ist |
| `fb_analyze_config` | *(keine)* | Liest `firebird.conf` und `databases.conf` und meldet jede Einstellung, auf die es ankommt (Page Buffers, `TempCacheLimit`, `LockHashSlots`, `MaxUnflushedWrites`, `GCPolicy`, parallele Worker), gemessen an *dieser* Engine-Version und *dieser* Server-Architektur, denn mit beiden ändern sich die Standardwerte und sogar die Existenz eines Parameters |
| `fb_analyze_storage` | `table_name?` | Das physische Bild, das kein `SELECT` zeigen kann: Indextiefe, Füllgrad der Seiten, Länge der Satzversionsketten, Seitenverteilung |
| `fb_parse_log` | *(keine)* | Streamt `firebird.log` über die Services API zurück und trennt das Rauschen von dem, was zählt: Bugchecks, Seitenkorruption, I/O-Fehler, gelaufene Sweeps und solche, die nie liefen |
| `fb_capture_trace` | *(keine)* | Öffnet eine zeitlich begrenzte Trace-API-Sitzung, sampelt die echte Last und sortiert die Statements danach, was sie wirklich kosten, als Latenzverteilung, nicht als Mittelwert |
| `fb_trace_start` | `duration_seconds?` | Öffnet das lange Fenster: bis zu zwei Stunden Trace-API-Capture, im Hintergrund auf Platte abgeleitet, während der Aufruf sofort zurückkehrt |
| `fb_trace_status` | *(keine)* | Meldet das laufende Capture: verstrichene Zeit gegen Dauer, erfasste Bytes, und ob die Sitzung noch beobachtet |
| `fb_trace_stop` | *(keine)* | Stoppt das Capture, oder holt ein beendetes ab, und liefert denselben sortierten Bericht wie `fb_capture_trace`, über Stunden statt Sekunden |
| `fb_analyze_host` | `config_dir?` | Die Engine gegen ihre Hardware: RAM gegen den Speicher, den die Konfiguration tatsächlich belegt, Kernzahl gegen `MaxParallelWorkers` und `CpuAffinityMask`, freier Platz gegen die Größe der Datenbank, und ob die Seiten, die sie verfehlt, einen Seek kosten |

Dazu kommt der Teil, der daraus ein Produkt statt eines Berichts macht: **Baselines und Experimente.**
Eine Messung unter echter Last nehmen, einen Parameter ändern, noch einmal messen und ein Urteil
darüber bekommen, ob sich der Tail bewegt hat, mit Rollback, falls nicht.

Firebirds Dokumentation nennt für die meisten dieser Parameter keinen optimalen Wert, und wir tun das
auch nicht. Was die Enterprise Edition mitbringt, ist die Landkarte vom Symptom zu dem Parameter, der es
erklärt, und ein Prüfstand, der beweist, dass die Änderung auf deiner Datenbank gewirkt hat.
