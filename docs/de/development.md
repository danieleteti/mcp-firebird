# Bauen und testen

[← zurück zur README](../../README-DE.md)

Für alle, die *an* MCP Firebird arbeiten. Wer es nur benutzen will, braucht nichts
davon: ein Release herunterladen und [Installation](setup.md) lesen.

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
