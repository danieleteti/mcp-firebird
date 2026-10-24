**[English](README.md) · [Italiano](README-IT.md) · [Español](README-ES.md) · [Deutsch](README-DE.md)**

<p align="center">
  <img src="https://raw.githubusercontent.com/danieleteti/mcp-firebird/master/docs/logo.png" alt="MCP Firebird" width="360">
</p>

<p align="center">
  <a href="https://github.com/danieleteti/mcp-firebird/blob/master/LICENSE"><img alt="Lizenz: PolyForm Internal Use 1.0.0" src="https://img.shields.io/badge/License-PolyForm_Internal_Use-blue.svg"></a>
  <img alt="MCP-Protokoll 2025-03-26" src="https://img.shields.io/badge/MCP-2025--03--26-brightgreen.svg">
  <a href="https://github.com/danieleteti/mcp-server-delphi"><img alt="powered by mcp-server-delphi" src="https://img.shields.io/badge/powered%20by-mcp--server--delphi-orange.svg"></a>
  <a href="https://github.com/danieleteti/mcp-firebird/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/danieleteti/mcp-firebird/actions/workflows/ci.yml/badge.svg"></a>
</p>

# MCP Firebird

**Frag deinen KI-Assistenten, warum eine Query langsam ist — und bekomm eine Antwort, mit der du
etwas anfangen kannst.**

Ein [Model-Context-Protocol](https://modelcontextprotocol.io)-Server für **Firebird 2.5 bis 5.0**.
Richte ihn auf eine Datenbank, und dein Assistent liest die echten Zugriffspläne, sagt dir, welcher
Index fehlt und welche vier totes Gewicht sind, prüft den Zustand einer Tabelle und findet die
Transaktion, die seit Dienstag die Garbage Collection aufhält.

Die Antworten kommen aus *deiner* Datenbank, nicht aus einem Artikel: der Server holt den Plan bei
Firebird (`SET PLANONLY`), liest die Monitoring-Tabellen (`MON$`) und zählt, wie viele verschiedene
Werte eine Spalte wirklich hat, bevor er behauptet, ein Index darauf lohne sich. Jede Antwort kommt
als **Finding** (was nicht stimmt), **SQL** (das Statement, das es behebt) und **Verify** (wie du
prüfst, dass es gewirkt hat). In deine Datenbank wird nichts geschrieben: der Server verbindet sich
nur lesend, und das SQL, das er dir gibt, führst du selbst aus — wenn du willst.

- **Transport:** stdio (JSON-RPC 2.0, MCP `2025-03-26`) · **Server-Identität:** `mcp-firebird` v`0.6.1`
- **Engines:** Firebird 2.5, 3.0, 4.0, 5.0 — zur Laufzeit erkannt
- **Kostenlos** auf deinen eigenen Datenbanken, in jeder Größe, ohne Schlüssel und ohne Ablauf. Eine
  Lizenz brauchst du erst, wenn die Software deine Hände verlässt
  ([Details](https://github.com/danieleteti/mcp-firebird/blob/master/docs/de/editions.md))

---

## Schnellstart

Fünf Minuten, vier Schritte. Windows x64.

**1. Server holen.** Lade das [neueste Release](https://github.com/danieleteti/mcp-firebird/releases)
herunter und entpacke es, etwa nach `C:\Tools\MCPFirebird`.
Lieber selbst bauen: [Bauen und testen](https://github.com/danieleteti/mcp-firebird/blob/master/docs/de/development.md).  <!-- release:drop -->

**2. Sag ihm, welche Datenbank.** Kopiere `.env.example` neben die exe als `.env` und füll vier
Zeilen aus:

```ini
firebird.database=C:\data\MYAPP.FDB
firebird.user=SYSDBA
firebird.password=masterkey
firebird.client_lib=C:\Program Files\Firebird\Firebird_5_0\fbclient.dll
```

Das Zip enthält absichtlich keine `fbclient.dll`: die richtige ist die Client-Bibliothek deines
eigenen Servers.

**3. Im KI-Agenten registrieren.** Es ist ein stdio-Server — die exe startet der Agent selbst, die
ganze Installation ist also ein Kommando. Claude Code:

```powershell
claude mcp add firebird -- "C:\Tools\MCPFirebird\MCPFirebird.exe"
```

Claude Desktop (`%APPDATA%\Claude\claude_desktop_config.json`), Cursor (`.cursor/mcp.json`) und
VS Code (`.vscode/mcp.json`) nutzen dieselbe Form:

```json
{ "mcpServers": { "firebird": { "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe" } } }
```

Gemini CLI und OpenCode weichen leicht ab — die Snippets für jeden Client stehen in
[Installation](https://github.com/danieleteti/mcp-firebird/blob/master/docs/de/setup.md#in-deinen-ki-agenten-einbauen-claude-gemini-cursor-).

**4. Frag ihn etwas.**

> **Du:** Mit welcher Firebird-Version bin ich verbunden, und welche Tabellen hat die Datenbank?
>
> **Du:** Diese Query ist langsam, warum? `SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'`
>
> **Du:** Schlag mir einen Index vor, der das behebt.

Mehr ist die Installation nicht. Zeigt der Client den Server, aber keine Tools, siehe
**Fehlersuche** am Ende dieser Seite.

---

## Was du ihn fragen kannst

| Frage | Was passiert |
|---|---|
| *„Dokumentiere die Tabelle CUSTOMERS“* | Markdown-Doku: Spalten, PK, Indizes, Trigger. Ohne Tabellennamen bekommst du die ganze Datenbank, inklusive Prozeduren und Packages |
| *„Warum ist diese Query langsam?“* | Der Zugriffsplan, die NATURAL-Scans und externen SORTs darin, der von der Engine erklärte Plan ab 3.0, **und** was die Query bei einer echten Ausführung gekostet hat |
| *„Schlag einen Index vor“* | Das billigste Mittel, das den Plan erklärt — alte Statistiken auffrischen, einen inaktiven Index wecken oder einen anlegen — und **„kein Index, hier ist der Scan richtig“** samt Zahlen, wenn das die Antwort ist |
| *„Welche Indizes kann ich löschen?“* | Duplikate, redundante Präfixe, inaktive und wenig selektive Indizes, mit `DROP INDEX` und Prüfschritt |
| *„Prüf diese Tabelle“* | Fehlender Primärschlüssel, zu viele Indizes, veraltete Statistiken |
| *„Optimiere weiter, bis diese Query keinen NATURAL-Scan mehr macht“* | Die Ziel-Schleife: ändern, auf der Datenbank neu messen, und aufhören, wenn die Messung es sagt — nicht wenn der Assistent es meint |
| *„Jeden Nachmittag kriecht es, und niemand hat etwas geändert“* | Ordnet das Symptom ein, bevor ein Tool angefasst wird, und misst dann `MON$` über ein Fenster, um zu zeigen, was sich anhäuft |
| *„Wer ist verbunden, und was läuft dort?“* | Jede Verbindung mit Benutzer, Adresse und Prozess, dem Statement, das gerade läuft, und seit wann |
| *„Zeig mir die Zeilen, die wirklich drinstehen“* | `fb_query` führt das SELECT aus und gibt die Zeilen zurück, gedeckelt, damit eine Antwort eine Antwort bleibt. Sonst kommt nichts durch: kein UPDATE, kein DELETE, kein DDL |
| *„Unsere Anwendung verbindet sich als SYSDBA. Was soll sie stattdessen nehmen?“* | `app_user_plan` fragt, was die Anwendung wirklich tut — wenige Fragen, von denen jede die Statements ändert — und `fb_suggest_grants` schreibt sie aus dem Katalog: das Konto, eine Rolle, die Rechte, und die Rolle so aktiviert, wie es diese Engine-Version verlangt |
| *„Wer darf diese Tabelle lesen?“* | Jede in der Datenbank verzeichnete Berechtigung, und die drei, die meist ein Fehler sind: PUBLIC, `WITH GRANT OPTION` und Rollen ohne Mitglieder |
| *„Mach ein Backup der Datenbank“* | Führt `gbak` im Hintergrund aus und **spielt das Geschriebene in eine Wegwerf-Datenbank zurück**: die Antwort ist nicht „eine Datei existiert“, sondern „dieses Backup lässt sich zurückspielen“ |

Jede Analyse schließt außerdem damit, **was sie nicht ausschließt**: ein Plan sieht keine Konkurrenz,
und eine Momentaufnahme sieht keine Anhäufung.

**[→ Durchgespielte Beispiele, wörtliche Tool-Ausgaben, eine komplette Runde auf `employee.fdb`](https://github.com/danieleteti/mcp-firebird/blob/master/docs/de/usage.md)**

---

## Die Tools

Sechzehn Tools, vier Prompts, eine Ressource. Vollständige Referenz — Argumente, was jedes
entscheidet, die rohen `tools/call`-Aufrufe — in
**[docs/de/tools.md](https://github.com/danieleteti/mcp-firebird/blob/master/docs/de/tools.md)**.

`fb_info` · `fb_list_tables` · `fb_generate_documentation` · `fb_query` · `fb_analyze_query` ·
`fb_suggest_indexes` · `fb_suggest_index_drops` · `fb_audit_table` · `fb_audit_security` ·
`fb_suggest_grants` · `fb_evaluate_goal` · `fb_monitor_transactions` · `fb_sample_activity` ·
`fb_monitor_attachments` · `fb_backup_start` · `fb_backup_status`

`fb_backup_start` kehrt zurück, bevor das Backup fertig ist — danach `fb_backup_status` pollen. Es
braucht `firebird.backup_dir` in der `.env`, `gbak.exe` neben deiner `fbclient.dll` und Platz auf
dieser Platte für eine zweite Kopie der Datenbank, solange die Prüf-Rücksicherung läuft.

Prompts: `optimization_goal` (iteriert bis erreicht) · `health_check` · `classify_problem`.
Ressource: `firebird://schema`.

Neun weitere Tools erscheinen in `tools/list` und gehören zur
[Enterprise Edition](https://github.com/danieleteti/mcp-firebird/blob/master/docs/de/editions.md#enterprise-edition):
dein Assistent sieht sie und kann sagen, was er damit täte.

---

## Editionen

**Auf deinen eigenen Datenbanken ist es kostenlos, und bleibt es.** Keine Testphase, kein Ablauf,
kein Lizenzschlüssel, keine Platzzählung. Beratung: es ist dein Werkzeug, benutz es auf den
Datenbanken deiner Kunden und stell deine Zeit in Rechnung. Eine Lizenz braucht nur, **eine Kopie aus
der Hand zu geben** — sie weiterzuverteilen, sie in ein Produkt einzubauen, das du verkaufst, oder
sie als Dienst anzubieten.

Die kostenpflichtige **Enterprise Edition** setzt dort an, wo eine SQL-Verbindung endet:
`firebird.conf`, RAM und CPUs der Maschine, `firebird.log`, die Trace-API, der physische
Speicherbericht. Du willst sie, wenn das Schema in Ordnung ist und die Datenbank trotzdem langsam.

**[→ Editionen, Lizenzierung und die durchgerechneten Fälle](https://github.com/danieleteti/mcp-firebird/blob/master/docs/de/editions.md)** · d.teti@bittime.it

---

## Dokumentation

| | |
|---|---|
| [Installation](https://github.com/danieleteti/mcp-firebird/blob/master/docs/de/setup.md) | Voraussetzungen, `.env`-Referenz, `--env <dir>`, mehrere Datenbanken aus einer Installation, Snippets je Client, manueller Test |
| [Beispiele](https://github.com/danieleteti/mcp-firebird/blob/master/docs/de/usage.md) | Die Gespräche, wörtliche Tool-Ausgaben, eine komplette Optimierungsrunde |
| [Tool-Referenz](https://github.com/danieleteti/mcp-firebird/blob/master/docs/de/tools.md) | Alle fünfzehn Tools, wie der Index-Berater entscheidet, Prompts, Ressourcen, Enterprise |
| [Editionen & Lizenzierung](https://github.com/danieleteti/mcp-firebird/blob/master/docs/de/editions.md) | Was kostenlos ist, was eine Lizenz braucht, was Enterprise dazugibt |
| [Bauen und testen](https://github.com/danieleteti/mcp-firebird/blob/master/docs/de/development.md) | Delphi-Build, die Testmatrix 2.5→5.0, wie es mcp-server-delphi nutzt |  <!-- release:drop -->
| [Problemkatalog](https://github.com/danieleteti/mcp-firebird/blob/master/docs/firebird-problem-catalog.md) | Jedes erkannte Problem, die Fixture, die es auslöst, der Meilenstein (auf Englisch) |

---

## Fehlersuche

| Symptom | Wahrscheinliche Ursache / Abhilfe |
|---|---|
| Der Client zeigt den Server, aber **keine Tools** | `.env` fehlt oder die DB ist nicht erreichbar: der Server startet, die Tools scheitern beim Verbinden. Prüf es mit dem [manuellen Rauchtest](https://github.com/danieleteti/mcp-firebird/blob/master/docs/de/setup.md#manuell-starten--prüfen). |
| `Your user name and password are not defined` (SQLSTATE 28000) | Falsche Zugangsdaten oder ein Firebird-Zip-Kit ohne benutzbaren `SYSDBA` (siehe [Bauen und testen](https://github.com/danieleteti/mcp-firebird/blob/master/docs/de/development.md)). |
| Die Analyse-Tools liefern nichts, kein NATURAL-Scan auf einer **entfernten** DB | Stell sicher, dass `firebird.host` der echte Host ist (die Plananalyse benutzt den konfigurierten Host). |
| `fbclient.dll` nicht gefunden / falsche Bitness | Setz `firebird.client_lib` auf eine **Win64**-`fbclient.dll`; ein 5.0-Client funktioniert gegen 2.5 bis 5.0. |
| stdout enthält Rauschen, das kein JSON ist | Das Logging darf nur in Dateien gehen: `logger.config.file=loggerpro.stdio.json` beibehalten. |
| Port 3050 ist schon von einem anderen Firebird belegt | Nimm einen anderen Port (genau deshalb legt das Test-Harness FB 2.5 auf **3070**). |

---

## Sicherheit & Kompatibilität

- **Nur lesend, und nicht auf Treu und Glauben.** Der Server öffnet seine Transaktionen nur
  lesend: ein INSERT, UPDATE, DELETE oder DDL weist Firebird ab, nicht eine Prüfung von uns,
  die sich darüber irren könnte, was ein Statement tut. Das zählt, weil vier Tools SQL
  ausführen, das als Text vom Aufrufer kommt: `fb_query` gibt dessen Zeilen zurück,
  `fb_analyze_query` misst das SELECT, das es analysiert, `fb_suggest_indexes` misst jenes, zu
  dem es rät, und `fb_evaluate_goal` stoppt eines. Alle vier weisen alles zurück, was kein reines
  SELECT ist, bevor sie es ausführen, und sie führen ein Statement mit ungebundenen Parametern
  gar nicht erst aus; die nur lesende Transaktion ist das, was hält, falls eine Zurückweisung
  einmal danebenliegt.

  Diese Reihenfolge zählt, und sie ist das Gegenteil einer Schlüsselwort-Blockliste. Eine Liste
  verbotener Wörter — kein `INSERT`, kein `DROP` — ist eine Vermutung über Text: sie weiß nicht,
  dass `EXECUTE PROCEDURE` schreiben kann, dass ein Statement so zusammengesetzt sein kann, dass
  es keines dieser Wörter enthält, und auch nicht, dass die nächste Version ein Schlüsselwort
  hinzufügt, das niemand in die Liste eingetragen hat. Das nur lesende TPB ist keine Vermutung.
  Welcher Text auch ankommt und was er auch bedeutet: die Transaktion, in der er läuft, kann
  nicht schreiben, und das sagt die Engine. Das SQL, das ein Befund dir gibt, führst du selbst
  aus, wann und ob du willst. Tools, die eine Änderung selbst anwenden, sind geplant; wenn sie
  kommen, sind sie aus, bis du sie einschaltest.
- **Versionsübergreifend.** Die Fähigkeitserkennung passt die Nutzung der Features (MON$-Tabellen,
  erklärte Pläne, BOOLEAN, INT128, Zeitzonen, parallele Worker) an die verbundene Engine an; validiert
  auf FB 2.5 / 3.0 / 4.0 / 5.0.
- **Eine konfigurierte Datenbank** pro Serverinstanz (für mehrere DBs mehrere Instanzen starten).

---

## Lizenz

Seit **v0.2.0** gilt die
**[PolyForm Internal Use License 1.0.0](https://github.com/danieleteti/mcp-firebird/blob/master/LICENSE)**: kostenlos auf deinen eigenen Datenbanken,
in jeder Größe, und eine Lizenz brauchst du nur, um die Software an jemand anderen weiterzugeben.
**v0.1.0 und älter erschienen unter Apache-2.0 und bleiben es** für alle, die sie erhalten haben.
Was das praktisch heißt: [Editionen & Lizenzierung](https://github.com/danieleteti/mcp-firebird/blob/master/docs/de/editions.md) und
[`NOTICE`](https://github.com/danieleteti/mcp-firebird/blob/master/NOTICE).

Gebaut mit **[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi)**, das wiederum
auf **[DelphiMVCFramework](https://github.com/danieleteti/delphimvcframework)** steht. Dieser Server
ist ein vollständiges, echtes Beispiel dafür, was man damit bauen kann: wer selbst einen MCP-Server
in Delphi schreibt, fängt dort an.
