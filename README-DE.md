**[English](README.md) · [Italiano](README-IT.md) · [Español](README-ES.md) · [Deutsch](README-DE.md)**

<p align="center">
  <img src="docs/logo.png" alt="MCP Firebird" width="360">
</p>

<p align="center">
  <a href="LICENSE"><img alt="License: PolyForm Internal Use 1.0.0" src="https://img.shields.io/badge/License-PolyForm_Internal_Use-blue.svg"></a>
  <img alt="MCP protocol 2025-03-26" src="https://img.shields.io/badge/MCP-2025--03--26-brightgreen.svg">
  <a href="https://github.com/danieleteti/mcp-server-delphi"><img alt="powered by mcp-server-delphi" src="https://img.shields.io/badge/powered%20by-mcp--server--delphi-orange.svg"></a>
  <a href="https://github.com/danieleteti/mcp-firebird/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/danieleteti/mcp-firebird/actions/workflows/ci.yml/badge.svg"></a>
</p>

# MCP Firebird

**Frag deinen KI-Assistenten, warum eine Query langsam ist, und bekomm eine Antwort, mit der sich etwas anfangen lässt.**

Ein [Model-Context-Protocol](https://modelcontextprotocol.io)-Server für **Firebird 2.5 bis 5.0**,
in Delphi gegen den offiziellen `fbclient`-Treiber geschrieben. Verbinde ihn mit einer Datenbank,
und ein Assistent liest deine Zugriffspläne, sagt dir, welcher Index fehlt und welcher nur Ballast
ist, prüft die Gesundheit einer Tabelle und findet die offen gebliebenen Transaktionen, die die
Garbage Collection blockieren.

Du kannst ihm auch ein Ziel vorgeben, *"diese Query darf nicht mehr NATURAL scannen"*, *"sie muss
unter 200 ms bleiben"*, und ihn arbeiten lassen: er ändert etwas, misst erneut auf der Datenbank
und versucht es wieder, falls es nicht gereicht hat. Über die Zielerreichung entscheidet die
Messung, nicht der Assistent.

Das sind nicht die allgemeinen Index-Tipps aus irgendeinem Artikel. Die Antworten kommen aus
*deiner* Datenbank: der Server holt sich von Firebird den Ausführungsplan der Query
(`SET PLANONLY`), fragt die Monitoring-Tabellen (`MON$`) ab und zählt nach, wie viele verschiedene
Werte eine Spalte tatsächlich enthält, bevor er behauptet, ein Index darauf lohne sich.

Jede Antwort besteht aus drei Teilen. **Finding**: was gefunden wurde und warum es ein Problem ist.
**SQL**: das Statement, das es behebt, bereits fertig formuliert. **Verify**: wie du prüfst, dass die
Korrektur wirklich gegriffen hat. Kein Tool schreibt in die Datenbank. Der Server liest, und das SQL,
das er dir gibt, führst du selbst aus, wann und ob du willst.

> Gebaut mit **[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi)**, das
> seinerseits auf **[DelphiMVCFramework](https://github.com/danieleteti/delphimvcframework)**
> aufsetzt. Dieser Server ist ein vollständiges, praxistaugliches Beispiel dafür, was sich damit
> bauen lässt.

- **Transport:** stdio (JSON-RPC 2.0, MCP-Protokoll `2025-03-26`)
- **Server-Identität:** `mcp-firebird` v`0.2.4`
- **Unterstützte Engines:** Firebird 2.5, 3.0, 4.0, 5.0 (Fähigkeiten werden zur Laufzeit erkannt)
- **Sicherheit:** rein lesende Analyse; kein Tool führt DDL oder schreibendes SQL aus
- **Kostenlos** für deine eigenen Datenbanken, in jeder Größenordnung, ohne Key und ohne Ablaufdatum.
  Eine Lizenz brauchst du erst, wenn du die Software aus der Hand gibst: sie in einem eigenen Produkt
  weiterverkaufen, sie beim Kunden installiert zurücklassen, sie als Dienst anbieten
  ([Lizenzdetails](#editionen--lizenzierung))
- **[Enterprise Edition](#enterprise-edition)**, separat erhältlich: sie untersucht den
  Firebird-*Server*, nicht nur die Datenbank. Sie liest `firebird.conf`, RAM und CPUs der Maschine,
  `firebird.log` und die Trace API. Du brauchst sie, wenn das Schema in Ordnung ist und die Datenbank
  trotzdem langsam bleibt

---

## Inhaltsverzeichnis

1. [Was es tut](#was-es-tut)
2. [Editionen & Lizenzierung](#editionen--lizenzierung)
3. [Enterprise Edition](#enterprise-edition)
4. [Wie es mcp-server-delphi nutzt](#wie-es-mcp-server-delphi-nutzt)  <!-- release:drop -->
5. [Voraussetzungen](#voraussetzungen)
6. [Build](#build)  <!-- release:drop -->
7. [Konfiguration (`.env`)](#konfiguration-env)
8. [Manuell starten & prüfen](#manuell-starten--prüfen)
9. [In deinen KI-Agenten einbauen](#in-deinen-ki-agenten-einbauen-claude-gemini-cursor-): Claude Desktop · Claude Code · Gemini CLI · OpenCode · Cursor / VS Code · generisch
10. [Aus Claude heraus nutzen](#aus-claude-heraus-nutzen): durchgespielte Beispiele
11. [Tool-Referenz](#tool-referenz)
12. [Das Projekt testen](#das-projekt-testen)  <!-- release:drop -->
13. [Fehlersuche](#fehlersuche)

---

## Was es tut

### Tools (9 kostenlose, dazu 5 Enterprise-Tools, die in `tools/list` angekündigt werden)

| Tool | Argumente | Zweck |
|---|---|---|
| `fb_info` | *(keine)* | Engine-Version + erkannte Fähigkeiten (JSON) |
| `fb_list_tables` | *(keine)* | Listet die Benutzertabellen auf |
| `fb_generate_documentation` | `table_name?` | Markdown-Doku (Spalten, PK, Indizes) für eine Tabelle oder für die ganze Datenbank |
| `fb_analyze_query` | `sql` | Analyse des Zugriffsplans: erkennt NATURAL-Scans und externe SORTs |
| `fb_suggest_indexes` | `sql` | Vorschläge für neue Indizes aus den NATURAL gescannten Prädikaten (direkt ausführbares DDL) |
| `fb_suggest_index_drops` | `table_name` | Meldet doppelte, präfix-redundante, inaktive und wenig selektive Indizes |
| `fb_audit_table` | `table_name` | Prüfung der Schema-Gesundheit: fehlender PK, zu viele Indizes, veraltete Statistiken |
| `fb_evaluate_goal` | `goal_type`, `target`, `threshold` | Deterministische Zielprüfung (treibt die Optimierungsschleife an) |
| `fb_monitor_transactions` | `stale_minutes?` | Zustand von Transaktionen und Sweep: Abstand zwischen OIT/OAT/Next, blockierende Langläufer (samt ihrem letzten SQL-Statement) |

Jeder Befund kommt mit einem **Finding**, direkt ausführbarem **SQL** und einem **Verify**-Schritt.

### Prompts (2)

- **`optimization_goal`**, die zielgetriebene Schleife: du setzt ein Ziel, der Assistent iteriert über
  die `fb_*`-Tools und prüft `fb_evaluate_goal` erneut, bis dort `met: true` steht (mit Notbremse bei
  zu vielen Iterationen oder ausbleibendem Fortschritt).
- **`health_check`**: geführte Gesundheitsprüfung der gesamten Datenbank.

### Ressourcen (1)

- **`firebird://schema`**: das aktuelle Datenbankschema als eine einzige Ressource.

---

## Editionen & Lizenzierung

Kurzfassung: **wenn du es auf deinen eigenen Datenbanken einsetzt, ist es kostenlos, und das bleibt
so.** Keine Testphase, kein Ablaufdatum, kein Lizenzschlüssel, keine Nutzerzählung, keine Grenze für
Tabellen oder Datenbanken. Installier es, setz es in Produktion ein, benutz es täglich. Nichts
telefoniert nach Hause.

Das Einzige, was du nicht darfst: es jemand anderem in die Hand geben.

MCP Firebird ist **source-available, nicht Open Source** im Sinne der Definition der Open Source
Initiative. Das klar zu sagen ist wichtiger als ein Badge: ab **v0.2.0** gilt die
[PolyForm Internal Use License 1.0.0](LICENSE). Alle Versionen bis einschließlich **v0.1.0 erschienen
unter Apache-2.0 und bleiben es** für jeden, der sie erhalten hat. Eine einmal erteilte Lizenz lässt
sich nicht widerrufen, und dieses Projekt tut auch nicht so.

### Was du kostenlos darfst

- Es gegen jede beliebige Datenbank laufen lassen: deine, die deines Arbeitgebers, die deines Kunden.
  Entwicklung, Staging, Produktion, alle.
- Es in jeder Größenordnung einsetzen. Hundert Tabellen oder zehntausend, eine Datenbank oder fünfzig.
- **Es in deiner Beratungstätigkeit einsetzen.** Diagnostiziere, tune, prüfe und betreue damit die
  Firebird-Datenbanken deiner Kunden, und stell ihnen deine Zeit in Rechnung. Es ist dein Werkzeug,
  behalt es.
- Den Quellcode lesen. Den ganzen. Lern daraus, und nutz, was du gelernt hast.
- Es ändern. Einen Bug beheben, einen Detektor ergänzen, eine Meldung umformulieren. Deinen eigenen
  Build laufen lassen.
- Es in einem Unternehmen jeder Größe einsetzen, kommerziell oder nicht, gewinnorientiert oder nicht,
  ohne Gebühr und ohne Registrierung.

### Wofür eine Lizenz nötig ist

Ein Gedanke in drei Formen: **die Software aus der Hand geben.**

- **Weitergabe.** Einen Fork veröffentlichen, einen Build hochladen, ihn auf eine CD packen, die
  Binärdatei an einen Kunden schicken, sie nach Projektende auf dem Server des Kunden liegen lassen.
- **Einbau in ein Produkt, das du verkaufst.** Ausliefern in deinem ERP, deinem Installer, deinem
  Docker-Image, deiner Appliance, als Quellcode oder als Binärdatei, verändert oder nicht.
- **Angebot als Dienst.** Betrieb hinter einer API oder einem gehosteten Agenten, den Leute außerhalb
  deiner Organisation erreichen können.

Wo die Software läuft und wessen Datenbank sie untersucht, ist deine Sache. Wo Kopien davon landen,
ist unsere.

Trifft einer dieser Fälle auf dich zu, dann gibt es die Lizenz, und gemessen an dem, was du damit
baust, ist sie nicht teuer. Schreib an **d.teti@bittime.it**.

### Wann du eine Lizenz kaufen musst: durchgespielte Fälle

| Deine Situation | Lizenz nötig? |
|---|---|
| Dein DBA lässt es jeden Morgen gegen das Firebird-Produktivsystem der Firma laufen | **Nein.** |
| Deine vierzig Entwickler lassen es jeweils lokal laufen | **Nein.** Keine Nutzerzählung, keine Registrierung. |
| Du bist Berater und lässt es von deinem Laptop aus gegen die Datenbank deines Kunden laufen | **Nein.** Es ist dein Werkzeug und bleibt dein Werkzeug. Berechne dafür, was du willst. |
| Dasselbe, aber du sitzt beim Kunden und lässt es auf dessen Server laufen | **Nein.** Nimm es mit, wenn du gehst. |
| Du lässt beim Weggehen eine Kopie auf dem Server deines Kunden installiert zurück | **Ja.** Die Software hat deine Hand verlassen. |
| Du bist Hosting-Anbieter und lässt es gegen die Datenbanken laufen, die du hostest | **Nein.** |
| ...und du gibst deinen Kunden einen Button, der es für sie ausführt | **Ja.** Das ist ein Angebot als Dienst. |
| Du lieferst es in deinem Delphi-ERP mit, damit deine Kunden "KI-Datenbanktuning" bekommen | **Ja.** Einbau in ein Produkt, das du lieferst. |
| Du veröffentlichst einen Fork mit deinen Verbesserungen auf GitHub | **Ja.** Sprich vorher mit uns: wir würden ihn lieber mergen. |
| Du schreibst einen Blogartikel, einen Vortrag oder einen Universitätskurs darüber | **Nein.** Lies es, zitier es, unterrichte es. |
| Du bist auf `v0.1.0`, das du unter Apache-2.0 erhalten hast | **Nein.** Diese Version bleibt für dich für immer Apache-2.0. |

Die Regel hinter der Tabelle, falls du lieber denkst als nachschlägst: **frag, wo die Software landet,
nie, was du damit gemacht hast.** Solange jede Kopie von MCP Firebird in deiner Hand bleibt, schuldest
du nichts: nicht für die Größenordnung, in der du sie einsetzt, nicht für das Geld, das sie dir
einbringt, nicht dafür, auf wessen Datenbank du sie ansetzt. In dem Moment, in dem eine Kopie dich
verlässt, sollten wir reden.

Daneben gibt es die kostenpflichtige **[Enterprise Edition](#enterprise-edition)**, ein eigenes
Produkt und keine beschnittene Gratisstufe. Alles, was im Rest dieser README beschrieben wird, steckt
in der freien Edition.

---

## Enterprise Edition

### Wo die freie Edition endet

Die freie Edition ist keine Demo, und sie ist auch nicht die Enterprise Edition ohne die guten Teile.
Sie erledigt eine Aufgabe vollständig und ordentlich: **sie bringt die Datenbank dazu, für sich selbst
Rechenschaft abzulegen.**

Sie liest dein Schema. Sie erklärt deine Pläne. Sie findet den Index, der dir fehlt, und die vier, die
du nicht brauchst. Sie erwischt den fehlenden Primärschlüssel, die veralteten Statistiken, die
Transaktion, die seit Dienstag die Garbage Collection festhält. Bei den meisten Datenbanken liegt das
Problem meistens genau dort, und dort wird es auch behoben. Viele werden sie jahrelang benutzen und nie
etwas anderes brauchen, und niemand wird je einen Cent von ihnen verlangen.

Und dann kommt der Tag, an dem sie dir die Wahrheit sagt: *dein Schema ist in Ordnung. Deine Indizes
sind in Ordnung. Keine NATURAL-Scans, keine externen Sorts, Statistiken frisch.* Und die Datenbank ist
immer noch langsam.

**Das ist die Grenze.** Die freie Edition hat ihre Frage ehrlich und vollständig beantwortet, und die
Antwort lautet: das Problem liegt nicht in der Datenbank. Es liegt in der Maschine darunter, und kein
`SELECT` wird dir das je zeigen. Nicht weil das Tool etwas zurückhielte, sondern weil SQL nicht über
seinen eigenen Prozess hinaussehen kann.

### Wo die Enterprise Edition beginnt

Es sind 2 GB Page Buffers auf einem Host mit 8 GB RAM. Es sind die Forced Writes, vor zwei Jahren für
einen Batch-Load abgeschaltet und nie wieder eingeschaltet. Es sind `LockHashSlots`, immer noch auf dem
Standardwert von 2010, bei vierhundert Verbindungen, ein vier Ebenen tiefer Index, ein Bugcheck, der
jeden Dienstag um 03:00 ins `firebird.log` geschrieben wird und den niemand liest.

Die freie Edition verbindet sich mit Firebird genau wie deine Anwendung: eine gewöhnliche
SQL-Verbindung mit gewöhnlichen Rechten. **Die Enterprise Edition verlangt mehr.** Sie hängt sich als
Administrator an den Services Manager (so streamt sie `firebird.log` zurück, steuert die Trace API und
liest den physischen Storage-Report), und sie liest die Konfiguration und die Hardware des Servers
selbst. Das ist ein anderes Privileg, ein anderer Schadensradius und ein anderes Gespräch mit dem, dem
der Server gehört. Deshalb ein anderes Produkt.

Und sie bleibt nicht dabei stehen, dir zu sagen, was falsch ist. **Sie führt das Experiment durch.**
Eine Baseline unter echter Last aufnehmen, genau einen Parameter ändern, erneut messen, die
Verteilungen vergleichen (p95 und p99, niemals den Mittelwert) und die Änderung behalten oder
zurücknehmen. Niemand verkauft dir eine Zahl. Die Zahl nennt dir die Datenbank.

| | Free | Enterprise |
|---|---|---|
| Schema, Doku, Pläne, Index-Beratung, Schema-Audit | ✅ | ✅ |
| Zustand von Transaktionen und Sweep (`MON$`) | ✅ | ✅ |
| `fb_diagnose`: der Einstiegspunkt, was schon bekannt ist und die geordnete Route, die als Nächstes zu gehen ist | ✗ | ✅ |
| `fb_analyze_config`: `firebird.conf` / `databases.conf`, gelesen gegen diese Engine, diese Architektur, diese Last | ✗ | ✅ |
| `fb_analyze_storage`: Indextiefe, Füllgrad der Seiten, Satzversionsketten, Seitenverteilung | ✗ | ✅ |
| `fb_parse_log` (`firebird.log`): Fehler, Sweeps, Bugchecks, Abstürze | ✗ | ✅ |
| `fb_capture_trace` (Trace API): die echte Last, und was sie wirklich kostet | ✗ | ✅ |
| `fb_trace_start` / `fb_trace_status` / `fb_trace_stop`: das lange Fenster, bis zu zwei Stunden Trace, im Hintergrund abgeleitet | ✗ | ✅ |
| `fb_analyze_host`: RAM gegen Page Buffers, CPU gegen parallele Worker, Storage-Klasse | ✗ | ✅ |
| Baselines, Verteilungen, Vorher/Nachher-Vergleich: das Experiment | ✗ | ✅ |

Beachte, was *nicht* in dieser Tabelle steht: nichts wurde aus der freien Edition herausgenommen, um
die kostenpflichtige zu bauen. Jedes freie Tool bleibt frei, und die noch ungeschriebenen bleiben auf
der Seite der Grenze, auf die sie gehören. Die Grenze ist keine Paywall quer durch eine Featureliste.
Sie verläuft zwischen dem Abfragen einer Datenbank und dem Administrieren eines Servers, und die freie
Edition stand immer auf der einen Seite davon.

Das Schwierige war nie, `firebird.conf` zu parsen; eine INI-Datei kann jeder parsen. Und niemand kann
dir ehrlichen Gewissens den richtigen Wert für `LockHashSlots` nennen: **Firebirds eigene Dokumentation
gibt dafür kein Optimum an**, auch nicht für den Page Cache und nicht für den Sort Cache. Was Erfahrung
dir kauft, ist das Wissen, *welchen* Parameter dein Symptom belastet: bricht der Durchsatz unter
Nebenläufigkeit ein, während die CPU ruhig bleibt, dann deutet das auf die Lock-Tabelle und nie auf den
Page Cache. Diese Landkarte ist das Produkt. Der Wert am Ende des Wegs wird nicht behauptet. Er wird
gemessen, auf deiner Datenbank, unter deiner Last.

Du wirst merken, wann du sie brauchst, denn die freie Edition wird es dir gesagt haben.

Die neun Tools oben erscheinen schon in der freien Edition in `tools/list`, dein Assistent sieht sie
also und kann sagen, was er mit ihnen täte. Rufst du eines auf, erklärt es dir, wie du es bekommst.

**Enterprise-Lizenzen, kommerzielle Lizenzen und Support-Abos:** d.teti@bittime.it


<!-- release:drop -->
## Wie es mcp-server-delphi nutzt

Jedes Tool ist eine ganz normale Delphi-Methode, dekoriert mit Attributen aus
[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi). Das Framework macht aus der
Klasse einen MCP-Tool-Provider, erzeugt das JSON-RPC-Schema aus den Attributen und verdrahtet es mit
dem stdio-Transport. Protokollcode gibt es in diesem Repository nicht. Aus
`providers/FirebirdToolsU.pas`:

```pascal
TFirebirdTools = class(TMCPToolProvider)
public
  [MCPTool('fb_info', 'Engine version, dialect, charset and detected capabilities of the configured Firebird database')]
  function FbInfo: TMCPToolResult;

  [MCPTool('fb_generate_documentation', 'Markdown documentation — columns, primary key, indexes — for one table, or for the whole database when table_name is empty')]
  function FbGenerateDocumentation([MCPParam('Table name; leave empty for the whole database', TMCPParamPresence.Optional)] const table_name: string): TMCPToolResult;

  [MCPTool('fb_analyze_query', 'Returns and analyzes the access plan of a SQL query (flags NATURAL scans and external sorts)')]
  function FbAnalyzeQuery([MCPParam('The SQL query to analyze')] const sql: string): TMCPToolResult;
end;
```

Prompts (`providers/FirebirdPromptsU.pas`) und Ressourcen (`providers/FirebirdResourcesU.pas`)
folgen demselben Attributprinzip. Die vollständige Attributreferenz steht im Repository von
[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi).

---

## Voraussetzungen

- **Windows x64** (der Server ist eine native Win64-Konsolenanwendung).
- Eine **Firebird-Client-Bibliothek** (`fbclient.dll`), passend zu deinem Zielserver oder neuer. Eine
  `fbclient.dll` aus 5.0 verbindet sich problemlos mit Servern von 2.5 bis 5.0.
- Eine erreichbare **Firebird-Datenbank**.

Der Download enthält absichtlich keine `fbclient.dll`: die richtige ist die deines Servers, und ein
unpassender Client ist schlimmer als gar keiner. Zeig mit `firebird.client_lib` darauf (siehe unten).

---

<!-- release:drop -->
## Build

Zum Bauen aus dem Quellcode brauchst du zusätzlich **Delphi 13 Athens** (RAD Studio 37.0) mit
**FireDAC** sowie **DMVCFramework** und die Bibliothek **`mcp-server-delphi`**, beide lokal
ausgecheckt. Für die Testmatrix außerdem die Firebird-Zip-Kits unter `fb_versions/` und Python 3 mit
`pytest`.

Suchpfade, die das Projekt erwartet (einmalig in `app/MCPFirebird.dproj` gesetzt):

```
C:\DEV\mcp-server-delphi\sources
<DMVCFramework>\sources   (every sources subfolder DMVC needs)
C:\DEV\mcp-firebird\sources
C:\DEV\mcp-firebird\providers
```

Die Win64-Debug-Anwendung im Wurzelverzeichnis des Repositorys bauen:

```powershell
cmd /c _build_app.bat
```

`_build_app.bat` ruft `rsvars.bat` auf und danach
`msbuild app\MCPFirebird.dproj /t:Clean;Build /p:Config=Debug /p:Platform=Win64`.
Die ausführbare Datei landet unter **`bin\MCPFirebird.exe`**.

(Für das DUnitX-Testprojekt gibt es das passende Gegenstück `_build_core.bat`.)

---

## Konfiguration (`.env`)

Standardmäßig liest der Server seine Konfiguration aus einer **`.env`-Datei im selben Ordner wie die
ausführbare Datei**. Wo dieser Ordner liegt, hängt davon ab, woher du die Exe hast:

| | Exe | Vorlage kopieren mit |
|---|---|---|
| heruntergeladenes Release | `MCPFirebird.exe` (der entpackte Ordner) | `Copy-Item .env.example .env` |
| selbst gebaut | `bin\MCPFirebird.exe` | `Copy-Item bin\.env.example bin\.env` |

Danach bearbeitest du sie. (`.env.example` beginnt mit einem Punkt: `ls` und der Explorer blenden sie
aus, solange du nicht ausdrücklich versteckte Dateien anzeigen lässt. Im ZIP ist sie enthalten.)

### Einen anderen Konfigurationsordner wählen: `--env <dir>`

Standardmäßig wird die `.env` aus dem Ordner der ausführbaren Datei gelesen. Mit **`--env <dir>`** liest
der Server sie stattdessen aus einem anderen Ordner. Das Argument ist ein **Verzeichnis** (der Ordner,
der die `.env` *enthält*), nicht die Datei selbst:

```powershell
MCPFirebird.exe --env C:\configs\prod      # reads C:\configs\prod\.env
MCPFirebird.exe --env=C:\configs\prod      # the --env=<dir> form also works
MCPFirebird.exe --env ..\shared            # relative paths resolve against the working directory
MCPFirebird.exe                            # no argument -> reads <exe folder>\.env
MCPFirebird.exe --env C:\configs\prod\.env # WRONG -> stops with an error (see below)
```

> **`--env` ist ein Ordner, niemals die `.env`-Datei.** Zeigst du damit auf die Datei (etwa
> `...\prod\.env`), verweigert der Server den Start und schreibt die Lösung nach stderr (MCP-Clients
> zeigen das in ihren Server-Logs an), statt stillschweigend mit leerer Konfiguration zu starten:
>
> ```
> MCPFirebird: --env must point at the FOLDER that contains the .env file, not at the file itself.
>   got:      C:\configs\prod\.env
>   use this: C:\configs\prod
> ```

**Wie das Argument beim Server ankommt.** MCP-Clients gehen nicht über eine Shell. Sie starten die
ausführbare Datei direkt, mit einem `command` und einem `args`-**Array**, in dem jedes Element zu genau
einem Argument wird. Um Shell-Quoting musst du dich also nicht kümmern (Pfade mit Leerzeichen sind kein
Problem), und das Verzeichnis schreibst du als eigenes Array-Element. Zwei gleichwertige Formen:

| Form | Wert von `args` |
|---|---|
| getrennt | `["--env", "C:\\configs\\prod"]` |
| zusammengefasst | `["--env=C:\\configs\\prod"]` |

**Zu Pfaden unter Windows:** in JSON müssen Backslashes **verdoppelt** werden
(`"C:\\configs\\prod"`); alternativ nimmst du Schrägstriche, die Windows akzeptiert und die kein
Escaping brauchen (`"C:/configs/prod"`). Verwende in MCP-Clients einen **absoluten** Pfad: das
Arbeitsverzeichnis, mit dem sie starten, ist unvorhersehbar, relative Pfade sind dort also
unzuverlässig. Jeder Start protokolliert den aufgelösten Ordner nach `logs\MCPFirebird.NN.mcp.log`:

```
Boot: .env directory "C:\configs\prod" (.env exists=True)
```

> **Hinweis:** Logs landen immer in einem Unterordner `logs\` neben der **ausführbaren Datei** (`logs\`
> direkt neben der Exe), unabhängig von `--env`.

#### `--env` aus den einzelnen MCP-Clients übergeben

**Claude Desktop** (`%APPDATA%\Claude\claude_desktop_config.json`), **Claude Code** (`.mcp.json`),
**Cursor** (`.cursor/mcp.json`) und **VS Code** (`.vscode/mcp.json`) verwenden alle dieselbe Form, ein
`command` plus ein `args`-Array:

```json
{
  "mcpServers": {
    "firebird": {
      "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe",
      "args": ["--env", "C:\\configs\\prod"]
    }
  }
}
```

Claude Code kann es auch über die CLI hinzufügen:

```powershell
claude mcp add firebird -- "C:\Tools\MCPFirebird\MCPFirebird.exe" --env "C:\configs\prod"
```

**Gemini CLI** (`~/.gemini/settings.json`), dieselbe `mcpServers`-Form:

```json
{
  "mcpServers": {
    "firebird": {
      "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe",
      "args": ["--env", "C:\\configs\\prod"]
    }
  }
}
```

**OpenCode** (`opencode.json`). Achtung, hier ist es anders: `command` ist ein **einziges Array**, das
die Argumente bereits enthält (ein eigenes `args`-Feld gibt es nicht):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "firebird": {
      "type": "local",
      "command": ["C:\\Tools\\MCPFirebird\\MCPFirebird.exe", "--env", "C:\\configs\\prod"],
      "enabled": true
    }
  }
}
```

#### Mehrere Datenbanken aus einem Build bedienen

Registriere **dieselbe ausführbare Datei** mehrfach, mit verschiedenen `--env`-Ordnern. Jeder Ordner
hat seine eigene `.env`:

```json
{
  "mcpServers": {
    "firebird-prod": {
      "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe",
      "args": ["--env", "C:\\configs\\prod"]
    },
    "firebird-test": {
      "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe",
      "args": ["--env", "C:\\configs\\test"]
    }
  }
}
```

```
C:\configs\prod\.env      <- production host/port/database
C:\configs\test\.env      <- test host/port/database
```

Der Client zeigt dann zwei unabhängige Server (`firebird-prod`, `firebird-test`), jeder mit seiner
eigenen Datenbank verbunden.

| Key | Standard | Bedeutung |
|---|---|---|
| `firebird.host` | `localhost` | Server-Host (TCP). Für entfernte DBs den echten Host bzw. die IP eintragen |
| `firebird.port` | `3050` | Server-Port |
| `firebird.database` | *(leer)* | Vollständiger Pfad (oder Alias) der Datenbank auf dem Server |
| `firebird.user` | `SYSDBA` | Benutzer für die Anmeldung |
| `firebird.password` | `masterkey` | Passwort für die Anmeldung |
| `firebird.charset` | `UTF8` | Zeichensatz der Verbindung |
| `firebird.client_lib` | *(leer)* | Vollständiger Pfad zur `fbclient.dll`, die geladen werden soll |
| `logger.config.file` | `loggerpro.stdio.json` | Konfiguration des Datei-Loggers (Logs gehen nur in Dateien; stdout bleibt reines JSON-RPC) |

Beispiel für eine `.env`:

```ini
firebird.host=localhost
firebird.port=3050
firebird.database=C:\data\MYAPP.FDB
firebird.user=SYSDBA
firebird.password=masterkey
firebird.charset=UTF8
firebird.client_lib=C:\Program Files\Firebird\Firebird_5_0\fbclient.dll
logger.config.file=loggerpro.stdio.json
```

> **Warum eine Datei und keine vom Client übergebenen Umgebungsvariablen?** Die dotEnv-Strategie lautet
> *erst Datei, dann Umgebung*: die `.env`-Datei hat Vorrang, die Umgebungsvariablen des Betriebssystems
> sind der Rückfall. Die Konfiguration über `.env` verhält sich in jedem MCP-Client gleich, weil sie
> relativ zur `.exe` gelesen wird, ganz unabhängig vom Arbeitsverzeichnis des Clients. Halte diese Datei
> aus der Versionskontrolle heraus (sie steht bereits in `.gitignore`): sie enthält Zugangsdaten.

---

## Manuell starten & prüfen

Der Server spricht JSON-RPC über stdin/stdout. Du kannst ihn ohne jeden MCP-Client testen, indem du ihm
zeilenweise gerahmtes JSON hineinpipest. Aus PowerShell:

```powershell
$msgs = @(
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"manual","version":"1"}}}'
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"fb_info","arguments":{}}}'
) -join "`n"
$msgs | & .\MCPFirebird.exe
```

Erwartet wird: ein `initialize`-Ergebnis, das `mcp-firebird` nennt, ein `tools/list` mit den 10
`fb_*`-Tools und ein `fb_info` mit der tatsächlichen `engine_version`. (Die Logs liegen unter `logs\`,
stdout ist reines JSON-RPC.)

---

## In deinen KI-Agenten einbauen (Claude, Gemini, Cursor, …)

So kommt der Server vor einen KI-Agenten: du **registrierst ihn** in dessen Konfiguration, und von da
an kann der Agent während der Antwort seine Tools aufrufen. Nichts läuft als Dienst, nichts lauscht an
einem Port. Der Agent **startet die ausführbare Datei selbst**, als Kindprozess, und spricht mit ihr
über stdin/stdout (MCP nennt das einen *stdio-Server*). Schließt du den Agenten, ist der Server mit
verschwunden.

Die ganze Installation besteht also darin, dem Agenten **einen Befehl** zu nennen (den absoluten Pfad
zu `MCPFirebird.exe`), in der Datei oder der CLI, die sein Hersteller dafür vorsieht. Es folgen Rezepte
für die gängigen Agenten; alle sind derselbe Befehl in anderer Syntax. Die Datenbankverbindung gehört
nicht dazu: die liest der Server aus der `.env` neben der ausführbaren Datei (siehe oben) oder aus
`--env <dir>`.

### Claude Desktop

Bearbeite `%APPDATA%\Claude\claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "firebird": {
      "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe"
    }
  }
}
```

Starte Claude Desktop neu. Die `fb_*`-Tools, die Prompts `optimization_goal` und `health_check` sowie
die Ressource `firebird://schema` erscheinen im Client.

### Claude Code (CLI)

Mit einem Befehl hinzufügen (lokaler stdio-Server):

```powershell
claude mcp add firebird -- "C:\Tools\MCPFirebird\MCPFirebird.exe"
```

Oder committe eine projektweite `.mcp.json` im Wurzelverzeichnis des Repositorys, damit deine Kollegen
sie erben:

```json
{
  "mcpServers": {
    "firebird": {
      "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe",
      "args": [],
      "env": {}
    }
  }
}
```

Prüfen mit `claude mcp list` (oder mit `/mcp` innerhalb einer Sitzung).

### Gemini CLI

Bearbeite `~/.gemini/settings.json` (oder eine projektbezogene `.gemini/settings.json`):

```json
{
  "mcpServers": {
    "firebird": {
      "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe",
      "args": [],
      "cwd": "C:\\Tools\\MCPFirebird",
      "timeout": 30000,
      "trust": false
    }
  }
}
```

`/mcp` in der Gemini CLI listet danach den Server und seine Tools auf. Setzt du `cwd` auf den Ordner
der Exe, bleibt das Verzeichnis `logs\` aufgeräumt (die `.env` wird ohnehin über den Pfad der Exe
gefunden).

### OpenCode

Bearbeite `opencode.json` (global unter `~/.config/opencode/opencode.json` oder pro Projekt) und
registriere einen **lokalen** MCP-Server (`command` ist ein argv-Array):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "firebird": {
      "type": "local",
      "command": ["C:\\Tools\\MCPFirebird\\MCPFirebird.exe"],
      "enabled": true
    }
  }
}
```

### Cursor / VS Code

Cursor liest `.cursor/mcp.json`, VS Code (und MCP-fähige Erweiterungen) lesen `.vscode/mcp.json`. Beide
verwenden dieselbe Form:

```json
{
  "mcpServers": {
    "firebird": {
      "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe"
    }
  }
}
```

### Jeder andere MCP-Client

Der Server ist ein gewöhnlicher **stdio**-MCP-Server. Egal welches Konfigurationsformat der Client hat,
gib ihm:

- **command:** `C:\Tools\MCPFirebird\MCPFirebird.exe`
- **args:** *(keine)*, oder `["--env", "C:\\configs\\prod"]`, um eine `.env` aus einem anderen Ordner zu verwenden
- **transport:** stdio
- **env:** *(nichts nötig)*, die Verbindung kommt aus der `.env`

> **Tipp:** Willst du verschiedene Clients auf verschiedene Datenbanken richten, gib jedem ein eigenes
> `--env <dir>` (einen Ordner mit eigener `.env`). Den ganzen Installationsordner zu kopieren ist
> unnötig. Beispiel für eine `.mcp.json` in Claude Code:
> ```json
> { "mcpServers": { "firebird": {
>     "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe",
>     "args": ["--env", "C:\\configs\\prod"] } } }
> ```

---

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
3. Du führst das SQL aus (Schreibzugriffe sind standardmäßig aus, siehe [Sicherheit](#sicherheit--kompatibilität)).
4. Ruft `fb_evaluate_goal` erneut auf → `met: true`, und hört mit dem Ergebnis auf.

Du kannst das Ziel auch als Zahl formulieren, etwa *"bring diese Query unter 50 ms"*
(`goal_type=query_time_ms`, `threshold=50`).

---

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

---

## Tool-Referenz

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

// Goal check: "this query must no longer do a NATURAL scan"
{ "name": "fb_evaluate_goal",
  "arguments": { "goal_type": "query_no_natural_scan",
                 "target": "SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'",
                 "threshold": 0 } }
```

Werte für `goal_type` in `fb_evaluate_goal`, die M1 unterstützt: `query_no_natural_scan`,
`query_time_ms`, `no_redundant_indexes`. In
[`docs/firebird-problem-catalog.md`](docs/firebird-problem-catalog.md) steht jedes Problem, das die
Tools erkennen, die Fixture, die es provoziert, und der Meilenstein, in dem es landet.

### Enterprise-Tools

Diese neun erscheinen auch hier in `tools/list`, dein Assistent weiß also von ihnen und kann dir sagen,
was er mit ihnen täte. Rufst du sie in dieser Edition auf, kommt ein `isError`-Ergebnis zurück, das
erklärt, wie du sie bekommst. Implementiert sind sie in der [Enterprise Edition](#enterprise-edition),
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

---

<!-- release:drop -->
## Das Projekt testen

Die Suite führt die **DUnitX-Core-Tests gegen echte Firebird-Server** aus (2.5 → 5.0), dazu eine
**Python-Compliance-Suite über stdio** und eine **Core-Boundary-Prüfung**.

### Voraussetzungen für die Testmatrix

- Firebird-Zip-Kits unter `fb_versions/` (Pfade und Ports in `tests/fbkit.versions.psd1`).
  Ports: **2.5 → 3070**, 3.0 → 3053, 4.0 → 3054, 5.0 → 3055.
- **Einmalig** pro Kit: die Zip-Kits kommen ohne brauchbaren `SYSDBA`. Leg ihn bei gestopptem Server im
  Embedded-Modus an (nötig für 3.0/4.0/5.0; 2.5 funktioniert ohne das):
  ```
  <kit>\isql.exe -user SYSDBA "<kit>\security<N>.fdb"
    CREATE USER SYSDBA PASSWORD 'masterkey';
    COMMIT; QUIT;
  ```
  (`security3.fdb` / `security4.fdb` / `security5.fdb`).
- Python 3 mit `pytest` (`python -m pip install pytest`).

### Alles ausführen (ein Befehl)

```powershell
pwsh tests/run_all.ps1
```

#### Oder über PyInvoke (`tasks.py`)

Eine `tasks.py` kapselt den kompletten Build- und Testablauf (`python -m pip install invoke`):

```powershell
invoke --list                 # show all tasks
invoke build                  # build the core test project + the MCP app
invoke core --version 5.0     # core suite against one FB version (start/seed/test/stop)
invoke matrix                 # core suite across every present FB version
invoke compliance             # Python stdio MCP compliance suite (on FB 5.0)
invoke boundary               # enforce the core/MVCFramework boundary
invoke all                    # full run_all.ps1 (matrix + boundary + compliance)
```

Für jedes vorhandene Kit gilt: Server starten → eine frische `TESTDB.FDB` seeden → die Core-Exe laufen
lassen → Server stoppen. Danach folgen die Boundary-Prüfung und die Python-Suite auf 5.0. Erwartetes
Ende der Ausgabe:

```
==== Core suite on FB 2.5 ====   ... 27 passed / 3 ignored
==== Core suite on FB 3.0 ====   ... 27 passed / 3 ignored
==== Core suite on FB 4.0 ====   ... 27 passed / 3 ignored
==== Core suite on FB 5.0 ====   ... 27 passed / 3 ignored
Core boundary OK: no MVCFramework imports in sources/
7 passed
ALL SUITES PASSED
```

(Die 3 *ignorierten* Tests sind Detektoren, die noch auf M2 warten, und bleiben als Backlog sichtbar.)

### Gegen eine einzelne Version ausführen

```powershell
pwsh tests/fbkit.ps1   -Action start  -Version 5.0
pwsh tests/seed/make_seed.ps1          -Version 5.0
$env:FBTEST_PORT='3055'
$env:FBTEST_DB='C:\DEV\mcp-firebird\tests\seed\TESTDB.FDB'
$env:FBTEST_CLIENTLIB=(pwsh tests/fbkit.ps1 -Action client -Version 5.0)
& 'C:\DEV\mcp-firebird\tests\coreproject\MCPFirebirdCoreTests.exe'
pwsh tests/fbkit.ps1   -Action stop   -Version 5.0
```

### Nur die Python-Compliance

```powershell
pwsh tests/fbkit.ps1 -Action start -Version 5.0
pwsh tests/seed/make_seed.ps1 -Version 5.0
python -m pytest tests/test_mcp_firebird_stdio.py -v
pwsh tests/fbkit.ps1 -Action stop -Version 5.0
```

---

## Fehlersuche

| Symptom | Wahrscheinliche Ursache / Abhilfe |
|---|---|
| Der Client zeigt den Server, aber **keine Tools** | `.env` fehlt oder die DB ist nicht erreichbar: der Server startet, die Tools scheitern beim Verbinden. Prüf es mit dem [manuellen Rauchtest](#manuell-starten--prüfen). |
| `Your user name and password are not defined` (SQLSTATE 28000) | Falsche Zugangsdaten oder ein Zip-Kit ohne `SYSDBA`. Siehe die einmalige Initialisierung oben. |
| Die Analyse-Tools liefern nichts, kein NATURAL-Scan auf einer **entfernten** DB | Stell sicher, dass `firebird.host` der echte Host ist (die Plananalyse benutzt den konfigurierten Host). |
| `fbclient.dll` nicht gefunden / falsche Bitness | Setz `firebird.client_lib` auf eine **Win64**-`fbclient.dll`; ein 5.0-Client funktioniert gegen 2.5 bis 5.0. |
| stdout enthält Rauschen, das kein JSON ist | Das Logging darf nur in Dateien gehen: `logger.config.file=loggerpro.stdio.json` beibehalten. |
| Port 3050 ist schon von einem anderen Firebird belegt | Nimm einen anderen Port (genau deshalb legt das Test-Harness FB 2.5 auf **3070**). |

---

## Sicherheit & Kompatibilität

- **Nur lesend.** Kein Tool führt DDL oder schreibendes SQL aus. Das SQL, das ein Befund dir gibt,
  führst du selbst aus, wann und ob du willst. Tools, die eine Änderung selbst anwenden, sind geplant;
  wenn sie kommen, sind sie aus, bis du sie einschaltest.
- **Versionsübergreifend.** Die Fähigkeitserkennung passt die Nutzung der Features (MON$-Tabellen,
  erklärte Pläne, BOOLEAN, INT128, Zeitzonen, parallele Worker) an die verbundene Engine an; validiert
  auf FB 2.5 / 3.0 / 4.0 / 5.0.
- **Eine konfigurierte Datenbank** pro Serverinstanz (für mehrere DBs mehrere Instanzen starten).

---

## Lizenz

Seit **v0.2.0** gilt die **[PolyForm Internal Use License 1.0.0](LICENSE)**: kostenlos auf deinen
eigenen Datenbanken, in jedem Umfang, und eine Lizenz brauchst du nur, um die Software an jemand
anderen weiterzugeben. Was das praktisch bedeutet, steht unter
[Editionen & Lizenzierung](#editionen--lizenzierung); siehe auch [`NOTICE`](NOTICE).

**v0.1.0 und älter erschienen unter Apache-2.0 und bleiben es** für alle, die sie erhalten haben.

MCP Firebird ist ein Schaufenster für
[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi). Wenn du deinen eigenen
MCP-Server in Delphi baust, fang dort an.
