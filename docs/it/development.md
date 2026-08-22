# Build e test

[← torna al README](../../README-IT.md)

Per chi lavora *su* MCP Firebird. Se ti serve solo usarlo, non ti serve niente di
questo: scarica una release e leggi [Installazione](setup.md).

## Build

Per compilare dai sorgenti servono in più **Delphi 13 Athens** (RAD Studio 37.0) con **FireDAC**,
**DMVCFramework** e la libreria **`mcp-server-delphi`**, entrambe presenti in locale. Per la matrice
di test servono gli zip-kit Firebird sotto `fb_versions/` e Python 3 con `pytest`.

Percorsi di ricerca che il progetto si aspetta (si impostano una volta in `app/MCPFirebird.dproj`):

```
C:\DEV\mcp-server-delphi\sources
<DMVCFramework>\sources   (every sources subfolder DMVC needs)
C:\DEV\mcp-firebird\sources
C:\DEV\mcp-firebird\providers
```

Compila l'app Win64 Debug dalla radice del repository:

```powershell
cmd /c _build_app.bat
```

`_build_app.bat` chiama `rsvars.bat` e poi `msbuild app\MCPFirebird.dproj /t:Clean;Build /p:Config=Debug /p:Platform=Win64`.
L'eseguibile finisce in **`bin\MCPFirebird.exe`**.

(Per il progetto di test DUnitX c'è il gemello `_build_core.bat`.)

## Test del progetto

La suite fa girare i **test core DUnitX contro server Firebird veri** (dal 2.5 al 5.0), più una
**suite di conformità stdio in Python** e un **controllo sul confine del core**.

### Cosa serve per la matrice di test

- Gli zip-kit Firebird sotto `fb_versions/` (percorsi e porte in `tests/fbkit.versions.psd1`).
  Porte: **2.5 → 3070**, 3.0 → 3053, 4.0 → 3054, 5.0 → 3055.
- **Una volta per kit:** gli zip-kit non hanno un `SYSDBA` utilizzabile. A server fermo, crealo in
  modalità embedded (serve per 3.0/4.0/5.0; il 2.5 funziona così com'è):
  ```
  <kit>\isql.exe -user SYSDBA "<kit>\security<N>.fdb"
    CREATE USER SYSDBA PASSWORD 'masterkey';
    COMMIT; QUIT;
  ```
  (`security3.fdb` / `security4.fdb` / `security5.fdb`).
- Python 3 con `pytest` (`python -m pip install pytest`).

### Far girare tutto (un comando)

```powershell
pwsh tests/run_all.ps1
```

#### Oppure con PyInvoke (`tasks.py`)

Un `tasks.py` incapsula build e test dall'inizio alla fine (`python -m pip install invoke`):

```powershell
invoke --list                 # show all tasks
invoke build                  # build the core test project + the MCP app
invoke core --version 5.0     # core suite against one FB version (start/seed/test/stop)
invoke matrix                 # core suite across every present FB version
invoke compliance             # Python stdio MCP compliance suite (on FB 5.0)
invoke boundary               # enforce the core/MVCFramework boundary
invoke all                    # full run_all.ps1 (matrix + boundary + compliance)
```

Per ogni kit presente: avvia il server, semina un `TESTDB.FDB` nuovo, lancia l'exe del core, ferma
il server. Poi esegue il controllo sul confine e la suite Python su 5.0. In coda ti aspetti:

```
==== Core suite on FB 2.5 ====   ... 27 passed / 3 ignored
==== Core suite on FB 3.0 ====   ... 27 passed / 3 ignored
==== Core suite on FB 4.0 ====   ... 27 passed / 3 ignored
==== Core suite on FB 5.0 ====   ... 27 passed / 3 ignored
Core boundary OK: no MVCFramework imports in sources/
7 passed
ALL SUITES PASSED
```

(I 3 test *ignored* sono rilevatori in attesa di M2: restano visibili come backlog.)

### Su una versione sola

```powershell
pwsh tests/fbkit.ps1   -Action start  -Version 5.0
pwsh tests/seed/make_seed.ps1          -Version 5.0
$env:FBTEST_PORT='3055'
$env:FBTEST_DB='C:\DEV\mcp-firebird\tests\seed\TESTDB.FDB'
$env:FBTEST_CLIENTLIB=(pwsh tests/fbkit.ps1 -Action client -Version 5.0)
& 'C:\DEV\mcp-firebird\tests\coreproject\MCPFirebirdCoreTests.exe'
pwsh tests/fbkit.ps1   -Action stop   -Version 5.0
```

### Solo la conformità Python

```powershell
pwsh tests/fbkit.ps1 -Action start -Version 5.0
pwsh tests/seed/make_seed.ps1 -Version 5.0
python -m pytest tests/test_mcp_firebird_stdio.py -v
pwsh tests/fbkit.ps1 -Action stop -Version 5.0
```

## Come usa mcp-server-delphi

Ogni tool è un normale metodo Delphi con qualche attributo di
[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi). Il framework fa il resto:
trasforma la classe in un tool provider MCP, ricava lo schema JSON-RPC dagli attributi e lo collega
al trasporto stdio. In questo repository non c'è una riga di codice di protocollo. Da
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

Prompt (`providers/FirebirdPromptsU.pas`) e risorse (`providers/FirebirdResourcesU.pas`) funzionano
allo stesso modo, sempre con gli attributi. Per l'elenco completo vedi il repository
[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi).
