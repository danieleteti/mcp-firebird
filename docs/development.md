# Building & testing

[← back to the README](../README.md)

For people working *on* MCP Firebird. If you only want to use it, you need none of this — grab a
release and read [Setup](setup.md).

## Build

To build from source you also need **Delphi 13 Athens** (RAD Studio 37.0) with **FireDAC**, and
**DMVCFramework** plus the **`mcp-server-delphi`** library checked out locally. For the test matrix,
the Firebird zip-kits under `fb_versions/` and Python 3 with `pytest`.

Search paths the project expects (set once in `app/MCPFirebird.dproj`):

```
C:\DEV\mcp-server-delphi\sources
<DMVCFramework>\sources   (every sources subfolder DMVC needs)
C:\DEV\mcp-firebird\sources
C:\DEV\mcp-firebird\providers
```

Build the Win64 Debug app from the repo root:

```powershell
cmd /c _build_app.bat
```

`_build_app.bat` calls `rsvars.bat` then `msbuild app\MCPFirebird.dproj /t:Clean;Build /p:Config=Debug /p:Platform=Win64`.
The executable lands at **`bin\MCPFirebird.exe`**.

(There is a matching `_build_core.bat` for the DUnitX test project.)

---
## Testing the project

The suite runs the **DUnitX core tests against real Firebird servers** (2.5 → 5.0) plus a
**Python stdio compliance suite** and a **core-boundary check**.

### Prerequisites for the test matrix

- Firebird zip-kits present under `fb_versions/` (paths/ports in `tests/fbkit.versions.psd1`).
  Ports: **2.5 → 3070**, 3.0 → 3053, 4.0 → 3054, 5.0 → 3055.
- **One-time** per kit: the zip-kits ship without a usable `SYSDBA`. With the server stopped,
  create it in embedded mode (needed for 3.0/4.0/5.0; 2.5 works out of the box):
  ```
  <kit>\isql.exe -user SYSDBA "<kit>\security<N>.fdb"
    CREATE USER SYSDBA PASSWORD 'masterkey';
    COMMIT; QUIT;
  ```
  (`security3.fdb` / `security4.fdb` / `security5.fdb`).
- Python 3 with `pytest` (`python -m pip install pytest`).

### Run everything (one command)

```powershell
pwsh tests/run_all.ps1
```

#### Or via PyInvoke (`tasks.py`)

A `tasks.py` wraps the whole build + test workflow (`python -m pip install invoke`):

```powershell
invoke --list                 # show all tasks
invoke build                  # build the core test project + the MCP app
invoke core --version 5.0     # core suite against one FB version (start/seed/test/stop)
invoke matrix                 # core suite across every present FB version
invoke compliance             # Python stdio MCP compliance suite (on FB 5.0)
invoke boundary               # enforce the core/MVCFramework boundary
invoke all                    # full run_all.ps1 (matrix + boundary + compliance)
```

For each present kit it: starts the server → seeds a fresh `TESTDB.FDB` → runs the core exe →
stops the server; then runs the boundary check and the Python suite on 5.0. Expected tail:

```
==== Core suite on FB 2.5 ====   ... 27 passed / 3 ignored
==== Core suite on FB 3.0 ====   ... 27 passed / 3 ignored
==== Core suite on FB 4.0 ====   ... 27 passed / 3 ignored
==== Core suite on FB 5.0 ====   ... 27 passed / 3 ignored
Core boundary OK: no MVCFramework imports in sources/
7 passed
ALL SUITES PASSED
```

(The 3 *ignored* tests are M2-pending detectors, kept visible as backlog.)

### Run against a single version

```powershell
pwsh tests/fbkit.ps1   -Action start  -Version 5.0
pwsh tests/seed/make_seed.ps1          -Version 5.0
$env:FBTEST_PORT='3055'
$env:FBTEST_DB='C:\DEV\mcp-firebird\tests\seed\TESTDB.FDB'
$env:FBTEST_CLIENTLIB=(pwsh tests/fbkit.ps1 -Action client -Version 5.0)
& 'C:\DEV\mcp-firebird\tests\coreproject\MCPFirebirdCoreTests.exe'
pwsh tests/fbkit.ps1   -Action stop   -Version 5.0
```

### Python compliance only

```powershell
pwsh tests/fbkit.ps1 -Action start -Version 5.0
pwsh tests/seed/make_seed.ps1 -Version 5.0
python -m pytest tests/test_mcp_firebird_stdio.py -v
pwsh tests/fbkit.ps1 -Action stop -Version 5.0
```

---

## How it uses mcp-server-delphi

Every tool is a plain Delphi method decorated with attributes from
[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi). The framework turns the
class into an MCP tool provider, generates the JSON-RPC schema from the attributes, and wires it
to the stdio transport: no protocol code in this repo. From `providers/FirebirdToolsU.pas`:

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

Prompts (`providers/FirebirdPromptsU.pas`) and resources (`providers/FirebirdResourcesU.pas`) use
the same attribute approach. See the [mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi)
repository for the full attribute reference.
