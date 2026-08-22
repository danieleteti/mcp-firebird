# Compilar y probar

[← volver al README](../../README-ES.md)

Para quien trabaja *en* MCP Firebird. Si solo quieres usarlo, no necesitas nada de
esto: descarga una release y lee [Instalación](setup.md).

## Compilación

Para compilar desde el código fuente hacen falta además **Delphi 13 Athens** (RAD Studio 37.0) con
**FireDAC**, y **DMVCFramework** más la biblioteca **`mcp-server-delphi`** clonados en local. Para la
matriz de pruebas, los zip-kits de Firebird que hay bajo `fb_versions/` y Python 3 con `pytest`.

Rutas de búsqueda que el proyecto espera (se configuran una vez en `app/MCPFirebird.dproj`):

```
C:\DEV\mcp-server-delphi\sources
<DMVCFramework>\sources   (every sources subfolder DMVC needs)
C:\DEV\mcp-firebird\sources
C:\DEV\mcp-firebird\providers
```

Compila la aplicación Win64 Debug desde la raíz del repositorio:

```powershell
cmd /c _build_app.bat
```

`_build_app.bat` llama a `rsvars.bat` y luego a `msbuild app\MCPFirebird.dproj /t:Clean;Build /p:Config=Debug /p:Platform=Win64`.
El ejecutable aparece en **`bin\MCPFirebird.exe`**.

(Hay un `_build_core.bat` equivalente para el proyecto de pruebas DUnitX.)

## Probar el proyecto

La batería ejecuta las **pruebas de núcleo DUnitX contra servidores Firebird reales** (de 2.5 a 5.0),
más una **batería de conformidad stdio en Python** y una **comprobación de la frontera del núcleo**.

### Requisitos de la matriz de pruebas

- Los zip-kits de Firebird presentes en `fb_versions/` (rutas y puertos en
  `tests/fbkit.versions.psd1`). Puertos: **2.5 → 3070**, 3.0 → 3053, 4.0 → 3054, 5.0 → 3055.
- **Una sola vez** por kit: los zip-kits vienen sin un `SYSDBA` utilizable. Con el servidor parado,
  créalo en modo embebido (hace falta en 3.0/4.0/5.0; 2.5 funciona tal cual):
  ```
  <kit>\isql.exe -user SYSDBA "<kit>\security<N>.fdb"
    CREATE USER SYSDBA PASSWORD 'masterkey';
    COMMIT; QUIT;
  ```
  (`security3.fdb` / `security4.fdb` / `security5.fdb`).
- Python 3 con `pytest` (`python -m pip install pytest`).

### Ejecutarlo todo (un solo comando)

```powershell
pwsh tests/run_all.ps1
```

#### O con PyInvoke (`tasks.py`)

Un `tasks.py` envuelve todo el flujo de compilación y pruebas (`python -m pip install invoke`):

```powershell
invoke --list                 # show all tasks
invoke build                  # build the core test project + the MCP app
invoke core --version 5.0     # core suite against one FB version (start/seed/test/stop)
invoke matrix                 # core suite across every present FB version
invoke compliance             # Python stdio MCP compliance suite (on FB 5.0)
invoke boundary               # enforce the core/MVCFramework boundary
invoke all                    # full run_all.ps1 (matrix + boundary + compliance)
```

Para cada kit presente: arranca el servidor → siembra un `TESTDB.FDB` nuevo → ejecuta el exe de núcleo
→ para el servidor; luego lanza la comprobación de frontera y la batería de Python sobre 5.0. Final
esperado:

```
==== Core suite on FB 2.5 ====   ... 27 passed / 3 ignored
==== Core suite on FB 3.0 ====   ... 27 passed / 3 ignored
==== Core suite on FB 4.0 ====   ... 27 passed / 3 ignored
==== Core suite on FB 5.0 ====   ... 27 passed / 3 ignored
Core boundary OK: no MVCFramework imports in sources/
7 passed
ALL SUITES PASSED
```

(Las 3 pruebas *ignored* son detectores pendientes de M2, que se dejan a la vista como backlog.)

### Ejecutar contra una sola versión

```powershell
pwsh tests/fbkit.ps1   -Action start  -Version 5.0
pwsh tests/seed/make_seed.ps1          -Version 5.0
$env:FBTEST_PORT='3055'
$env:FBTEST_DB='C:\DEV\mcp-firebird\tests\seed\TESTDB.FDB'
$env:FBTEST_CLIENTLIB=(pwsh tests/fbkit.ps1 -Action client -Version 5.0)
& 'C:\DEV\mcp-firebird\tests\coreproject\MCPFirebirdCoreTests.exe'
pwsh tests/fbkit.ps1   -Action stop   -Version 5.0
```

### Solo la conformidad en Python

```powershell
pwsh tests/fbkit.ps1 -Action start -Version 5.0
pwsh tests/seed/make_seed.ps1 -Version 5.0
python -m pytest tests/test_mcp_firebird_stdio.py -v
pwsh tests/fbkit.ps1 -Action stop -Version 5.0
```

## Cómo usa mcp-server-delphi

Cada herramienta es un método Delphi normal decorado con atributos de
[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi). El framework convierte la
clase en un proveedor de herramientas MCP, genera el esquema JSON-RPC a partir de los atributos y lo
conecta al transporte stdio: en este repositorio no hay código de protocolo. De
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

Los prompts (`providers/FirebirdPromptsU.pas`) y los recursos (`providers/FirebirdResourcesU.pas`)
siguen el mismo enfoque de atributos. La referencia completa de atributos está en el repositorio de
[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi).
