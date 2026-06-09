# MCP Firebird Server — Milestone 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the MVP of the Firebird MCP server — connection, version/capability detection, schema introspection, Markdown documentation, query PLAN analysis, index advisor (suggest/drop), and the deterministic `fb_evaluate_goal` tool — exposed over stdio and validated against real Firebird 2.5/3.0/4.0/5.0 zip-kits.

**Architecture:** An MCP-agnostic `Firebird.*` analysis core (plain Object Pascal + FireDAC, never imports an `MVCFramework.MCP.*` unit) wrapped by thin `[MCPTool]`/`[MCPPrompt]`/`[MCPResource]` providers from the `mcp-server-delphi` library. The core is unit-tested with DUnitX against a freshly seeded database; the MCP layer gets contract + Python compliance tests. A PowerShell harness starts/stops each Firebird zip-kit and the test client loads that kit's matching `fbclient.dll`.

**Tech Stack:** Delphi 11+ (Win64), FireDAC (FB driver, `fbclient.dll`), DMVCFramework 3.5.x, `mcp-server-delphi` library (`C:\DEV\mcp-server-delphi\sources`), DUnitX, Python 3 (compliance), PowerShell (kit harness).

---

## Conventions for every task

- **Search paths** (set once in each `.dproj`, see Task 1): `C:\DEV\mcp-server-delphi\sources`, the DMVCFramework `sources` folders, this repo's `sources`, `providers`.
- **Target platform:** Win64 Debug for building/running; tests run Win64.
- **Default test engine:** Firebird **5.0** on port **3055** unless a task says otherwise. The full version matrix runs in Task 18.
- **Naming:** `T`-classes, `F`-fields, `I`-interfaces. MCP tools are `snake_case` with the `fb_` prefix.
- **Commit** after each task with the message shown in its final step.
- The core **must not** `uses` any `MVCFramework.MCP.*` or `MVCFramework.*` unit (dotEnv lives in the app layer). A grep check enforces this in Task 17.

## Shared type vocabulary (defined in the tasks that own them — referenced everywhere)

| Type | Owner unit | Shape |
|---|---|---|
| `TFirebirdConnectionConfig` | `Firebird.Connection` | record: `Host, Database, User, Password, Charset, ClientLib: string; Port: Integer; AllowDDL: Boolean` |
| `TFirebirdConnection` | `Firebird.Connection` | class wrapping `TFDConnection` + `TFDPhysFBDriverLink` |
| `TFirebirdCapabilities` | `Firebird.Capabilities` | record: `EngineVersion: string; Major, Minor, Ordinal: Integer; HasMonTables, HasExplainedPlan, HasBooleanType, HasIdentityCols, HasInt128, HasTimezones, HasParallelWorkers, HasRdbConfig: Boolean` |
| `TColumnInfo` | `Firebird.Introspection` | record: `FieldName, DataType: string; Position: Integer; Nullable: Boolean` |
| `TIndexInfo` | `Firebird.Introspection` | record: `IndexName: string; Columns: TArray<string>; Unique, Inactive, IsSystem: Boolean; Selectivity: Double; ConstraintType: string` |
| `TForeignKeyInfo` | `Firebird.Introspection` | record: `ConstraintName, RefTable, IndexName: string; Columns, RefColumns: TArray<string>` |
| `TPlanResult` | `Firebird.PlanAnalyzer` | record: `RawPlan, ExplainedPlan, EngineVersion: string; HasNaturalScan: Boolean; NaturalTables: TArray<string>` |
| `TAdvisory` | `Firebird.Advisory` | record: `Finding, SQLText, Verify, Severity: string` |
| `TGoalResult` | `Firebird.Goal` | record: `GoalType, Target: string; Measured, Threshold: Double; Met: Boolean; Gap: Double; Hint, EngineVersion, DetailsJSON: string` |

---

## Task 1: Project skeleton + slim stdio entry point

**Files:**
- Create: `app/MCPFirebird.dpr`
- Create: `app/BootConfigU.pas`
- Create: `app/EngineConfigU.pas`
- Create: `app/bin/.env.example`
- Create: `app/bin/loggerpro.stdio.json`
- Create: `sources/.keep`, `providers/.keep`
- Create: `app/MCPFirebird.dproj` (via Delphi IDE; see step)

- [ ] **Step 1: Create folders and the `.env.example`**

`app/bin/.env.example`:
```bash
# --- Firebird connection (single configured DB) ---
firebird.host=localhost
firebird.port=3055
firebird.database=C:\DEV\mcp-firebird\tests\seed\TESTDB.FDB
firebird.user=SYSDBA
firebird.password=masterkey
firebird.charset=UTF8
firebird.client_lib=C:\DEV\mcp-firebird\fb_versions\Firebird-5.0.4.1812-0-windows-x64\fbclient.dll

# --- Safety: write tools disabled by default ---
firebird.allow_ddl=false

# --- Logging (file only; stdout stays pure JSON-RPC for stdio) ---
logger.config.file=loggerpro.stdio.json
```

- [ ] **Step 2: Create the file-only logger config**

`app/bin/loggerpro.stdio.json`:
```json
{
  "appenders": [
    { "class": "TLoggerProFileAppender",
      "params": { "max_file_count": 5, "log_folder": "logs", "log_file_name_format": "{module}.{number}.{tag}.log" } }
  ],
  "loglevel": "debug"
}
```

- [ ] **Step 3: Write `BootConfigU.pas`** (dotEnv + file logger; reused pattern from the library)

```pascal
unit BootConfigU;
interface
procedure Boot;
implementation
uses
  System.SysUtils, System.IOUtils, LoggerPro.Config, LoggerPro,
  MVCFramework.DotEnv, MVCFramework.Commons, MVCFramework.Logger;

procedure ConfigDotEnv;
begin
  dotEnvConfigure(
    function: IMVCDotEnv
    begin
      Result := NewDotEnv.UseStrategy(TMVCDotEnvPriority.FileThenEnv).Build(AppPath);
    end);
end;

procedure ConfigLogger;
var
  lConfigFile: string;
begin
  lConfigFile := dotEnv.Env('logger.config.file', 'loggerpro.stdio.json');
  if not TPath.IsPathRooted(lConfigFile) then
    lConfigFile := TPath.Combine(AppPath, lConfigFile);
  SetDefaultLogger(TLoggerProConfig.BuilderFromJSONFile(lConfigFile).Build);
end;

procedure Boot;
begin
  ConfigDotEnv;
  ConfigLogger;
end;
end.
```

- [ ] **Step 4: Write `EngineConfigU.pas`** (server identity; providers added in later tasks)

```pascal
unit EngineConfigU;
interface
procedure ConfigureServerIdentity;
implementation
uses MVCFramework.MCP.Server;
procedure ConfigureServerIdentity;
begin
  TMCPServer.Instance.ServerName := 'mcp-firebird';
  TMCPServer.Instance.ServerVersion := '0.1.0';
end;
end.
```

- [ ] **Step 5: Write the slim stdio `.dpr`**

`app/MCPFirebird.dpr`:
```pascal
program MCPFirebird;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  MVCFramework.MCP.Server,
  MVCFramework.MCP.Stdio,
  MVCFramework.MCP.StdioOnly,
  BootConfigU in 'BootConfigU.pas',
  EngineConfigU in 'EngineConfigU.pas';
var
  LTransport: TMCPStdioTransport;
begin
  Boot;
  ConfigureServerIdentity;
  LTransport := TMCPStdioTransport.Create(TMCPServer.Instance);
  try
    try
      LTransport.Run;
    except
      on E: Exception do
        System.Write(ErrOutput, E.ClassName + ': ' + E.Message + sLineBreak);
    end;
  finally
    LTransport.Free;
  end;
end.
```

- [ ] **Step 6: Create the `.dproj` and set Win64 + search paths**

In the Delphi IDE: File → New → Console Application, save as `app/MCPFirebird.dpr` (overwrite with the file above). Project → Add the Win64 platform and make it active. In Project → Options → Building → Delphi Compiler → Search path (All configurations, Win64), add:
```
C:\DEV\mcp-server-delphi\sources
$(DMVC)\sources
C:\DEV\mcp-firebird\sources
C:\DEV\mcp-firebird\providers
```
(Replace `$(DMVC)` with the DMVCFramework root, e.g. `C:\DEV\delphimvcframework`. Add every `sources` subfolder DMVC needs, matching the `mcp-server-delphi` sample's search path.)

- [ ] **Step 7: Build and run — confirm it starts and waits on stdin**

Run from `app/bin`:
```cmd
MCPFirebird.exe
```
Expected: no stdout output; the process blocks waiting for JSON-RPC on stdin. Press Ctrl+C to exit. (A logs/ file appears under `app/bin/logs`.)

- [ ] **Step 8: Commit**

```bash
git add app .gitignore
git commit -m "feat(app): slim stdio entry point + boot/engine config skeleton"
```

---

## Task 2: Firebird zip-kit start/stop harness

**Files:**
- Create: `tests/fbkit.ps1`
- Create: `tests/fbkit.versions.psd1`

- [ ] **Step 1: Write the version registry**

`tests/fbkit.versions.psd1`:
```powershell
@{
  '2.5' = @{ Dir = 'Firebird-2.5.9.27139-0_x64';        Exe = 'bin\fbserver.exe'; ExeArgs = '-a'; Conf = 'firebird.conf';     Client = 'bin\fbclient.dll'; Port = 3050 }
  '3.0' = @{ Dir = 'Firebird-3.0.14.33856-0-x64';        Exe = 'firebird.exe';     ExeArgs = '-a'; Conf = 'firebird.conf';     Client = 'fbclient.dll';     Port = 3053 }
  '4.0' = @{ Dir = 'Firebird-4.0.7.3271-0-x64';          Exe = 'firebird.exe';     ExeArgs = '-a'; Conf = 'firebird.conf';     Client = 'fbclient.dll';     Port = 3054 }
  '5.0' = @{ Dir = 'Firebird-5.0.4.1812-0-windows-x64';  Exe = 'firebird.exe';     ExeArgs = '-a'; Conf = 'firebird.conf';     Client = 'fbclient.dll';     Port = 3055 }
}
```

- [ ] **Step 2: Write the harness**

`tests/fbkit.ps1`:
```powershell
param(
  [Parameter(Mandatory)][ValidateSet('start','stop','client','port')] [string]$Action,
  [Parameter(Mandatory)][ValidateSet('2.5','3.0','4.0','5.0')]        [string]$Version
)
$ErrorActionPreference = 'Stop'
$root = 'C:\DEV\mcp-firebird\fb_versions'
$reg  = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'fbkit.versions.psd1')
$v    = $reg[$Version]
$base = Join-Path $root $v.Dir
$exe  = Join-Path $base $v.Exe
$conf = Join-Path $base $v.Conf

function Set-Port {
  # Ensure RemoteServicePort is set in this kit's firebird.conf
  $content = Get-Content $conf -Raw
  if ($content -match '(?m)^\s*#?\s*RemoteServicePort\s*=.*$') {
    $content = $content -replace '(?m)^\s*#?\s*RemoteServicePort\s*=.*$', "RemoteServicePort = $($v.Port)"
  } else {
    $content += "`r`nRemoteServicePort = $($v.Port)`r`n"
  }
  Set-Content -Path $conf -Value $content -Encoding ASCII
}

switch ($Action) {
  'port'   { $v.Port; break }
  'client' { Join-Path $base $v.Client; break }
  'start'  {
    Set-Port
    $p = Start-Process -FilePath $exe -ArgumentList $v.ExeArgs -WorkingDirectory $base -PassThru
    Start-Sleep -Seconds 2   # let the listener bind
    Write-Host "Started FB $Version (PID $($p.Id)) on port $($v.Port)"
    $p.Id
    break
  }
  'stop'   {
    # Kill the engine process of THIS kit only (match the exe path)
    Get-CimInstance Win32_Process -Filter "Name='$(Split-Path $exe -Leaf)'" |
      Where-Object { $_.ExecutablePath -eq $exe } |
      ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    Write-Host "Stopped FB $Version"
    break
  }
}
```

- [ ] **Step 3: Smoke-test start/stop on FB 5.0**

```powershell
pwsh tests/fbkit.ps1 -Action start -Version 5.0
pwsh tests/fbkit.ps1 -Action port  -Version 5.0   # prints 3055
pwsh tests/fbkit.ps1 -Action stop  -Version 5.0
```
Expected: "Started FB 5.0 ... on port 3055", then "Stopped FB 5.0". No errors.

- [ ] **Step 4: Commit**

```bash
git add tests/fbkit.ps1 tests/fbkit.versions.psd1
git commit -m "test(harness): start/stop Firebird zip-kits with per-version port"
```

---

## Task 3: Cross-version seed database script

**Files:**
- Create: `tests/seed/seed.sql`
- Create: `tests/seed/make_seed.ps1`

- [ ] **Step 1: Write `seed.sql`** — pure SQL valid on FB 2.5 → 5 (no BOOLEAN, no IDENTITY, explicit ids)

```sql
SET SQL DIALECT 3;
/* Customers: PK auto-indexed by system */
CREATE TABLE CUSTOMERS (
  CUSTOMER_ID  INTEGER NOT NULL PRIMARY KEY,
  NAME         VARCHAR(100) NOT NULL,
  CITY         VARCHAR(60),          /* filtered but NOT indexed -> NATURAL scan target */
  STATUS       CHAR(1)               /* low-selectivity index target */
);

/* Orders: FK to CUSTOMERS auto-creates a system index on CUSTOMER_ID */
CREATE TABLE ORDERS (
  ORDER_ID     INTEGER NOT NULL PRIMARY KEY,
  CUSTOMER_ID  INTEGER NOT NULL,
  TOTAL        NUMERIC(12,2),
  CONSTRAINT FK_ORDERS_CUSTOMER FOREIGN KEY (CUSTOMER_ID) REFERENCES CUSTOMERS (CUSTOMER_ID)
);

/* DUPLICATE of the system FK index -> fb_suggest_index_drops must flag it */
CREATE INDEX IDX_ORDERS_CUSTOMER_DUP ON ORDERS (CUSTOMER_ID);

/* Composite + its redundant left-prefix -> drop the prefix */
CREATE INDEX IDX_CUST_NAME_CITY ON CUSTOMERS (NAME, CITY);
CREATE INDEX IDX_CUST_NAME      ON CUSTOMERS (NAME);   /* redundant left-prefix of the above */

/* Low-selectivity index on a 1-2 value column */
CREATE INDEX IDX_CUST_STATUS ON CUSTOMERS (STATUS);

/* Inactive index -> drop candidate */
CREATE INDEX IDX_CUST_CITY ON CUSTOMERS (CITY);
ALTER INDEX IDX_CUST_CITY INACTIVE;
COMMIT;

/* Populate enough rows to make a NATURAL scan meaningful and STATUS low-selectivity */
SET TERM ^ ;
EXECUTE BLOCK AS DECLARE I INTEGER = 0; BEGIN
  WHILE (I < 5000) DO BEGIN
    INSERT INTO CUSTOMERS (CUSTOMER_ID, NAME, CITY, STATUS)
      VALUES (:I, 'CUST_' || :I, CASE MOD(:I,4) WHEN 0 THEN 'Rome' WHEN 1 THEN 'Milan' WHEN 2 THEN 'Turin' ELSE 'Naples' END,
              CASE WHEN MOD(:I,2)=0 THEN 'A' ELSE 'B' END);
    INSERT INTO ORDERS (ORDER_ID, CUSTOMER_ID, TOTAL) VALUES (:I, :I, :I * 1.5);
    I = I + 1;
  END
END^
SET TERM ; ^
COMMIT;
```

- [ ] **Step 2: Write `make_seed.ps1`** — drops + recreates the seed DB on a given version using that kit's `isql`

```powershell
param([Parameter(Mandatory)][ValidateSet('2.5','3.0','4.0','5.0')] [string]$Version)
$ErrorActionPreference = 'Stop'
$reg  = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'fbkit.versions.psd1')
$v    = $reg[$Version]
$base = Join-Path 'C:\DEV\mcp-firebird\fb_versions' $v.Dir
$isql = Join-Path $base (Join-Path (Split-Path $v.Exe -Parent) 'isql.exe')
if (-not (Test-Path $isql)) { $isql = Join-Path $base 'isql.exe' }   # 2.5 has isql in bin
$port = $v.Port
$db   = "localhost/$port:C:\DEV\mcp-firebird\tests\seed\TESTDB.FDB"
$seed = Join-Path $PSScriptRoot 'seed\seed.sql'
if (Test-Path 'C:\DEV\mcp-firebird\tests\seed\TESTDB.FDB') { Remove-Item 'C:\DEV\mcp-firebird\tests\seed\TESTDB.FDB' -Force }
# create the database, then run the seed script
@"
CREATE DATABASE '$db' USER 'SYSDBA' PASSWORD 'masterkey' DEFAULT CHARACTER SET UTF8;
INPUT '$seed';
"@ | & $isql -q
Write-Host "Seed DB created for FB $Version at $db"
```

- [ ] **Step 3: Run it against FB 5.0 and confirm**

```powershell
pwsh tests/fbkit.ps1 -Action start -Version 5.0
pwsh tests/seed/make_seed.ps1 -Version 5.0
pwsh tests/fbkit.ps1 -Action stop -Version 5.0
```
Expected: "Seed DB created for FB 5.0 ...", file `tests/seed/TESTDB.FDB` exists.

- [ ] **Step 4: Commit**

```bash
git add tests/seed/seed.sql tests/seed/make_seed.ps1
git commit -m "test(seed): cross-version seed DB with known index/scan scenarios"
```

---

## Task 4: Core test project + connection fixture

**Files:**
- Create: `tests/coreproject/MCPFirebirdCoreTests.dpr`
- Create: `tests/coreproject/TestFixtureU.pas`
- Create: `tests/coreproject/MCPFirebirdCoreTests.dproj` (via IDE)

- [ ] **Step 1: Write a DUnitX console runner**

`tests/coreproject/MCPFirebirdCoreTests.dpr`:
```pascal
program MCPFirebirdCoreTests;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  TestFixtureU in 'TestFixtureU.pas';
var
  LRunner: ITestRunner;
  LResults: IRunResults;
begin
  LRunner := TDUnitX.CreateRunner;
  LRunner.AddLogger(TDUnitXConsoleLogger.Create(True));
  LRunner.AddLogger(TDUnitXXMLNUnitFileLogger.Create('core-tests.xml'));
  LResults := LRunner.Execute;
  if not LResults.AllPassed then
    ExitCode := 1;
end.
```

- [ ] **Step 2: Write the shared fixture helper** — builds a config from environment vars set by the test runner script

`tests/coreproject/TestFixtureU.pas`:
```pascal
unit TestFixtureU;
interface
uses Firebird.Connection;
/// Reads FBTEST_* environment variables (set by run_core.ps1) into a config.
function TestConfig: TFirebirdConnectionConfig;
function NewTestConnection: TFirebirdConnection;
implementation
uses System.SysUtils;

function TestConfig: TFirebirdConnectionConfig;
begin
  Result := Default(TFirebirdConnectionConfig);
  Result.Host      := 'localhost';
  Result.Port      := StrToIntDef(GetEnvironmentVariable('FBTEST_PORT'), 3055);
  Result.Database  := GetEnvironmentVariable('FBTEST_DB');       // full path to TESTDB.FDB
  Result.User      := 'SYSDBA';
  Result.Password  := 'masterkey';
  Result.Charset   := 'UTF8';
  Result.ClientLib := GetEnvironmentVariable('FBTEST_CLIENTLIB');
  Result.AllowDDL  := True;  // core tests need DDL to mutate the seed
end;

function NewTestConnection: TFirebirdConnection;
begin
  Result := TFirebirdConnection.Create(TestConfig);
  Result.Connect;
end;
end.
```

- [ ] **Step 3: Create the `.dproj`** (IDE: Console app, Win64, same search paths as Task 1 step 6 plus the DUnitX path). Build will fail until Task 5 creates `Firebird.Connection` — that is expected and is the next task.

- [ ] **Step 4: Commit**

```bash
git add tests/coreproject/MCPFirebirdCoreTests.dpr tests/coreproject/TestFixtureU.pas
git commit -m "test(core): DUnitX runner + connection fixture (env-driven config)"
```

---

## Task 5: `Firebird.Connection` — connect and run queries (TDD)

**Files:**
- Create: `sources/Firebird.Connection.pas`
- Create: `tests/coreproject/Test.Firebird.Connection.pas`

- [ ] **Step 1: Write the failing test**

`tests/coreproject/Test.Firebird.Connection.pas`:
```pascal
unit Test.Firebird.Connection;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TConnectionTests = class
  public
    [Test] procedure Connects_To_Seed_DB;
    [Test] procedure ScalarStr_Returns_Engine_Version;
  end;
implementation
uses System.SysUtils, Firebird.Connection, TestFixtureU;

procedure TConnectionTests.Connects_To_Seed_DB;
var C: TFirebirdConnection;
begin
  C := NewTestConnection;
  try
    Assert.IsTrue(C.IsConnected, 'should be connected');
  finally C.Free; end;
end;

procedure TConnectionTests.ScalarStr_Returns_Engine_Version;
var C: TFirebirdConnection; V: string;
begin
  C := NewTestConnection;
  try
    V := C.ScalarStr('SELECT rdb$get_context(''SYSTEM'',''ENGINE_VERSION'') FROM rdb$database');
    Assert.IsMatch('^\d+\.\d+\.\d+', V, 'engine version like 5.0.4');
  finally C.Free; end;
end;
end.
```
Register the unit in the `.dpr` `uses` clause: `Test.Firebird.Connection in 'Test.Firebird.Connection.pas',`.

- [ ] **Step 2: Run to verify it fails**

```powershell
pwsh tests/fbkit.ps1 -Action start -Version 5.0
pwsh tests/seed/make_seed.ps1 -Version 5.0
$env:FBTEST_PORT='3055'; $env:FBTEST_DB='C:\DEV\mcp-firebird\tests\seed\TESTDB.FDB'
$env:FBTEST_CLIENTLIB=(pwsh tests/fbkit.ps1 -Action client -Version 5.0)
.\tests\coreproject\Win64\Debug\MCPFirebirdCoreTests.exe
```
Expected: compile error (unit `Firebird.Connection` not found) — this is the failing state.

- [ ] **Step 3: Implement `Firebird.Connection`**

`sources/Firebird.Connection.pas`:
```pascal
unit Firebird.Connection;
interface
uses
  FireDAC.Comp.Client, FireDAC.Phys.FB, FireDAC.Phys.FBDef, FireDAC.Stan.Def,
  FireDAC.Stan.Async, FireDAC.DApt, FireDAC.Stan.Param, Data.DB;
type
  TFirebirdConnectionConfig = record
    Host: string;
    Port: Integer;
    Database: string;
    User: string;
    Password: string;
    Charset: string;
    ClientLib: string;
    AllowDDL: Boolean;
  end;

  TFirebirdConnection = class
  private
    FConn: TFDConnection;
    FDriverLink: TFDPhysFBDriverLink;
    FConfig: TFirebirdConnectionConfig;
  public
    constructor Create(const AConfig: TFirebirdConnectionConfig);
    destructor Destroy; override;
    procedure Connect;
    function IsConnected: Boolean;
    function OpenQuery(const ASQL: string): TFDQuery; overload;
    function OpenQuery(const ASQL: string; const AParams: array of Variant): TFDQuery; overload;
    function ExecSQL(const ASQL: string): Integer;
    function ScalarStr(const ASQL: string): string;
    property Config: TFirebirdConnectionConfig read FConfig;
    property FDConnection: TFDConnection read FConn;
  end;
implementation
uses System.SysUtils;

constructor TFirebirdConnection.Create(const AConfig: TFirebirdConnectionConfig);
begin
  inherited Create;
  FConfig := AConfig;
  FDriverLink := TFDPhysFBDriverLink.Create(nil);
  if AConfig.ClientLib <> '' then
    FDriverLink.VendorLib := AConfig.ClientLib;
  FConn := TFDConnection.Create(nil);
  FConn.LoginPrompt := False;
  FConn.DriverName := 'FB';
  FConn.Params.Values['Server']       := AConfig.Host;
  FConn.Params.Values['Port']         := AConfig.Port.ToString;
  FConn.Params.Values['Database']     := AConfig.Database;
  FConn.Params.Values['User_Name']    := AConfig.User;
  FConn.Params.Values['Password']     := AConfig.Password;
  FConn.Params.Values['CharacterSet'] := AConfig.Charset;
  FConn.Params.Values['Protocol']     := 'TCPIP';
end;

destructor TFirebirdConnection.Destroy;
begin
  FConn.Free;
  FDriverLink.Free;
  inherited;
end;

procedure TFirebirdConnection.Connect;
begin
  FConn.Connected := True;
end;

function TFirebirdConnection.IsConnected: Boolean;
begin
  Result := FConn.Connected;
end;

function TFirebirdConnection.OpenQuery(const ASQL: string): TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  try
    Result.Connection := FConn;
    Result.Open(ASQL);
  except
    Result.Free; raise;
  end;
end;

function TFirebirdConnection.OpenQuery(const ASQL: string; const AParams: array of Variant): TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  try
    Result.Connection := FConn;
    Result.Open(ASQL, AParams);
  except
    Result.Free; raise;
  end;
end;

function TFirebirdConnection.ExecSQL(const ASQL: string): Integer;
begin
  Result := FConn.ExecSQL(ASQL);
end;

function TFirebirdConnection.ScalarStr(const ASQL: string): string;
var Q: TFDQuery;
begin
  Q := OpenQuery(ASQL);
  try
    if Q.Eof then Result := '' else Result := Q.Fields[0].AsString;
  finally Q.Free; end;
end;
end.
```

- [ ] **Step 4: Run to verify it passes**

```powershell
.\tests\coreproject\Win64\Debug\MCPFirebirdCoreTests.exe
```
Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add sources/Firebird.Connection.pas tests/coreproject/Test.Firebird.Connection.pas tests/coreproject/MCPFirebirdCoreTests.dpr
git commit -m "feat(core): TFirebirdConnection over FireDAC + fbclient (TDD)"
```

---

## Task 6: `Firebird.Capabilities` — version → feature flags (TDD)

**Files:**
- Create: `sources/Firebird.Capabilities.pas`
- Create: `tests/coreproject/Test.Firebird.Capabilities.pas`

- [ ] **Step 1: Write the failing test** — pure `Parse` (no DB) + DB-backed `Detect`

```pascal
unit Test.Firebird.Capabilities;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TCapabilitiesTests = class
  public
    [Test] procedure Parse_25_HasNoExplainedPlan;
    [Test] procedure Parse_30_HasExplainedPlanAndBoolean;
    [Test] procedure Parse_50_HasParallelWorkers;
    [Test] procedure Detect_FromSeedDB_MatchesParse;
  end;
implementation
uses System.SysUtils, Firebird.Capabilities, Firebird.Connection, TestFixtureU;

procedure TCapabilitiesTests.Parse_25_HasNoExplainedPlan;
var C: TFirebirdCapabilities;
begin
  C := TFirebirdCapabilities.Parse('2.5.9');
  Assert.AreEqual(2, C.Major); Assert.AreEqual(5, C.Minor);
  Assert.IsFalse(C.HasExplainedPlan); Assert.IsFalse(C.HasBooleanType);
  Assert.IsTrue(C.HasMonTables);
end;

procedure TCapabilitiesTests.Parse_30_HasExplainedPlanAndBoolean;
var C: TFirebirdCapabilities;
begin
  C := TFirebirdCapabilities.Parse('3.0.14');
  Assert.IsTrue(C.HasExplainedPlan); Assert.IsTrue(C.HasBooleanType);
  Assert.IsFalse(C.HasInt128); Assert.IsFalse(C.HasParallelWorkers);
end;

procedure TCapabilitiesTests.Parse_50_HasParallelWorkers;
var C: TFirebirdCapabilities;
begin
  C := TFirebirdCapabilities.Parse('5.0.4');
  Assert.IsTrue(C.HasParallelWorkers); Assert.IsTrue(C.HasInt128); Assert.IsTrue(C.HasTimezones);
end;

procedure TCapabilitiesTests.Detect_FromSeedDB_MatchesParse;
var Conn: TFirebirdConnection; C: TFirebirdCapabilities;
begin
  Conn := NewTestConnection;
  try
    C := TFirebirdCapabilities.Detect(Conn);
    Assert.IsTrue(C.Major >= 2, 'major detected');
    Assert.IsMatch('^\d+\.\d+', C.EngineVersion);
  finally Conn.Free; end;
end;
end.
```
Add the unit to the `.dpr` `uses`.

- [ ] **Step 2: Run to verify it fails**

Run the core exe (env vars from Task 5 step 2). Expected: compile error — `Firebird.Capabilities` not found.

- [ ] **Step 3: Implement `Firebird.Capabilities`**

```pascal
unit Firebird.Capabilities;
interface
uses Firebird.Connection;
type
  TFirebirdCapabilities = record
    EngineVersion: string;
    Major, Minor, Ordinal: Integer;
    HasMonTables, HasExplainedPlan, HasBooleanType, HasIdentityCols: Boolean;
    HasInt128, HasTimezones, HasParallelWorkers, HasRdbConfig: Boolean;
    class function Parse(const AVersion: string): TFirebirdCapabilities; static;
    class function Detect(AConn: TFirebirdConnection): TFirebirdCapabilities; static;
  end;
implementation
uses System.SysUtils, System.Classes;

class function TFirebirdCapabilities.Parse(const AVersion: string): TFirebirdCapabilities;
var Parts: TArray<string>;
begin
  Result := Default(TFirebirdCapabilities);
  Result.EngineVersion := AVersion;
  Parts := AVersion.Split(['.']);
  if Length(Parts) > 0 then Result.Major := StrToIntDef(Parts[0], 0);
  if Length(Parts) > 1 then Result.Minor := StrToIntDef(Parts[1], 0);
  Result.Ordinal := Result.Major * 100 + Result.Minor;
  Result.HasMonTables       := Result.Ordinal >= 201;  // 2.1+
  Result.HasExplainedPlan   := Result.Ordinal >= 300;  // 3.0+
  Result.HasBooleanType     := Result.Ordinal >= 300;
  Result.HasIdentityCols    := Result.Ordinal >= 300;
  Result.HasInt128          := Result.Ordinal >= 400;  // 4.0+
  Result.HasTimezones       := Result.Ordinal >= 400;
  Result.HasRdbConfig       := Result.Ordinal >= 400;
  Result.HasParallelWorkers := Result.Ordinal >= 500;  // 5.0+
end;

class function TFirebirdCapabilities.Detect(AConn: TFirebirdConnection): TFirebirdCapabilities;
var V: string;
begin
  V := AConn.ScalarStr('SELECT rdb$get_context(''SYSTEM'',''ENGINE_VERSION'') FROM rdb$database');
  Result := Parse(V);
end;
end.
```

- [ ] **Step 4: Run to verify it passes**

Run the core exe. Expected: 4 capability tests pass.

- [ ] **Step 5: Commit**

```bash
git add sources/Firebird.Capabilities.pas tests/coreproject/Test.Firebird.Capabilities.pas tests/coreproject/MCPFirebirdCoreTests.dpr
git commit -m "feat(core): engine version detection + feature flags (TDD)"
```

---

## Task 7: `Firebird.Introspection` — tables, columns, PK (TDD)

**Files:**
- Create: `sources/Firebird.Introspection.pas`
- Create: `tests/coreproject/Test.Firebird.Introspection.pas`

- [ ] **Step 1: Write the failing test**

```pascal
unit Test.Firebird.Introspection;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TIntrospectionTests = class
  public
    [Test] procedure ListTables_IncludesSeedTables;
    [Test] procedure ListTables_ExcludesSystemTables;
    [Test] procedure GetColumns_Customers_HasCityColumn;
    [Test] procedure GetPrimaryKey_Customers_IsCustomerId;
  end;
implementation
uses System.SysUtils, System.Generics.Collections, Firebird.Connection,
  Firebird.Introspection, TestFixtureU;

function Has(const A: TArray<string>; const S: string): Boolean;
var X: string; begin Result := False; for X in A do if SameText(X, S) then Exit(True); end;

procedure TIntrospectionTests.ListTables_IncludesSeedTables;
var Conn: TFirebirdConnection; I: TFirebirdIntrospection;
begin
  Conn := NewTestConnection;
  try
    I := TFirebirdIntrospection.Create(Conn);
    try
      Assert.IsTrue(Has(I.ListTables, 'CUSTOMERS'));
      Assert.IsTrue(Has(I.ListTables, 'ORDERS'));
    finally I.Free; end;
  finally Conn.Free; end;
end;

procedure TIntrospectionTests.ListTables_ExcludesSystemTables;
var Conn: TFirebirdConnection; I: TFirebirdIntrospection;
begin
  Conn := NewTestConnection;
  try
    I := TFirebirdIntrospection.Create(Conn);
    try
      Assert.IsFalse(Has(I.ListTables, 'RDB$RELATIONS'));
    finally I.Free; end;
  finally Conn.Free; end;
end;

procedure TIntrospectionTests.GetColumns_Customers_HasCityColumn;
var Conn: TFirebirdConnection; I: TFirebirdIntrospection; Cols: TArray<TColumnInfo>; C: TColumnInfo; Found: Boolean;
begin
  Conn := NewTestConnection;
  try
    I := TFirebirdIntrospection.Create(Conn);
    try
      Cols := I.GetColumns('CUSTOMERS'); Found := False;
      for C in Cols do if SameText(C.FieldName, 'CITY') then Found := True;
      Assert.IsTrue(Found, 'CITY column present');
    finally I.Free; end;
  finally Conn.Free; end;
end;

procedure TIntrospectionTests.GetPrimaryKey_Customers_IsCustomerId;
var Conn: TFirebirdConnection; I: TFirebirdIntrospection; PK: TArray<string>;
begin
  Conn := NewTestConnection;
  try
    I := TFirebirdIntrospection.Create(Conn);
    try
      PK := I.GetPrimaryKey('CUSTOMERS');
      Assert.AreEqual(1, Length(PK));
      Assert.AreEqual('CUSTOMER_ID', PK[0]);
    finally I.Free; end;
  finally Conn.Free; end;
end;
end.
```
Add unit to `.dpr` `uses`.

- [ ] **Step 2: Run to verify it fails** — compile error `Firebird.Introspection` not found.

- [ ] **Step 3: Implement the unit** (indices/FKs added in Task 8; this task ships tables/columns/PK/RowCount)

```pascal
unit Firebird.Introspection;
interface
uses System.Generics.Collections, Firebird.Connection;
type
  TColumnInfo = record FieldName, DataType: string; Position: Integer; Nullable: Boolean; end;
  TIndexInfo = record
    IndexName: string; Columns: TArray<string>;
    Unique, Inactive, IsSystem: Boolean; Selectivity: Double; ConstraintType: string;
  end;
  TForeignKeyInfo = record
    ConstraintName, RefTable, IndexName: string;
    Columns, RefColumns: TArray<string>;
  end;

  TFirebirdIntrospection = class
  private
    FConn: TFirebirdConnection;
    function IndexColumns(const AIndexName: string): TArray<string>;
  public
    constructor Create(AConn: TFirebirdConnection);
    function ListTables(AIncludeViews: Boolean = True): TArray<string>;
    function GetColumns(const ATable: string): TArray<TColumnInfo>;
    function GetPrimaryKey(const ATable: string): TArray<string>;
    function GetIndexes(const ATable: string): TArray<TIndexInfo>;      // Task 8
    function GetForeignKeys(const ATable: string): TArray<TForeignKeyInfo>; // Task 8
    function RowCount(const ATable: string): Int64;
  end;
implementation
uses System.SysUtils, Data.DB, FireDAC.Comp.Client;

constructor TFirebirdIntrospection.Create(AConn: TFirebirdConnection);
begin inherited Create; FConn := AConn; end;

function TFirebirdIntrospection.ListTables(AIncludeViews: Boolean): TArray<string>;
var Q: TFDQuery; L: TList<string>; SQL: string;
begin
  SQL := 'SELECT TRIM(rdb$relation_name) FROM rdb$relations ' +
         'WHERE (rdb$system_flag IS NULL OR rdb$system_flag = 0)';
  if not AIncludeViews then SQL := SQL + ' AND rdb$view_blr IS NULL';
  SQL := SQL + ' ORDER BY 1';
  L := TList<string>.Create;
  try
    Q := FConn.OpenQuery(SQL);
    try
      while not Q.Eof do begin L.Add(Q.Fields[0].AsString); Q.Next; end;
    finally Q.Free; end;
    Result := L.ToArray;
  finally L.Free; end;
end;

function TFirebirdIntrospection.GetColumns(const ATable: string): TArray<TColumnInfo>;
var Q: TFDQuery; L: TList<TColumnInfo>; Rec: TColumnInfo;
begin
  // rf.rdb$null_flag = 1 => NOT NULL. f.rdb$field_type maps to a base type.
  L := TList<TColumnInfo>.Create;
  try
    Q := FConn.OpenQuery(
      'SELECT TRIM(rf.rdb$field_name), rf.rdb$field_position, ' +
      '       COALESCE(rf.rdb$null_flag,0), f.rdb$field_type, f.rdb$field_length, f.rdb$field_scale ' +
      'FROM rdb$relation_fields rf ' +
      'JOIN rdb$fields f ON f.rdb$field_name = rf.rdb$field_source ' +
      'WHERE rf.rdb$relation_name = ' + QuotedStr(ATable) +
      ' ORDER BY rf.rdb$field_position', []);
    try
      while not Q.Eof do begin
        Rec := Default(TColumnInfo);
        Rec.FieldName := Q.Fields[0].AsString;
        Rec.Position  := Q.Fields[1].AsInteger;
        Rec.Nullable  := Q.Fields[2].AsInteger = 0;
        Rec.DataType  := MapFieldType(Q.Fields[3].AsInteger, Q.Fields[4].AsInteger, Q.Fields[5].AsInteger);
        L.Add(Rec); Q.Next;
      end;
    finally Q.Free; end;
    Result := L.ToArray;
  finally L.Free; end;
end;

function TFirebirdIntrospection.GetPrimaryKey(const ATable: string): TArray<string>;
var Q: TFDQuery; L: TList<string>;
begin
  L := TList<string>.Create;
  try
    Q := FConn.OpenQuery(
      'SELECT TRIM(s.rdb$field_name) FROM rdb$relation_constraints rc ' +
      'JOIN rdb$index_segments s ON s.rdb$index_name = rc.rdb$index_name ' +
      'WHERE rc.rdb$constraint_type = ''PRIMARY KEY'' AND rc.rdb$relation_name = ' + QuotedStr(ATable) +
      ' ORDER BY s.rdb$field_position', []);
    try
      while not Q.Eof do begin L.Add(Q.Fields[0].AsString); Q.Next; end;
    finally Q.Free; end;
    Result := L.ToArray;
  finally L.Free; end;
end;

function TFirebirdIntrospection.RowCount(const ATable: string): Int64;
begin
  Result := StrToInt64Def(FConn.ScalarStr('SELECT COUNT(*) FROM ' + ATable), 0);
end;

function TFirebirdIntrospection.IndexColumns(const AIndexName: string): TArray<string>;
var Q: TFDQuery; L: TList<string>;
begin
  L := TList<string>.Create;
  try
    Q := FConn.OpenQuery(
      'SELECT TRIM(rdb$field_name) FROM rdb$index_segments ' +
      'WHERE rdb$index_name = ' + QuotedStr(AIndexName) + ' ORDER BY rdb$field_position', []);
    try
      while not Q.Eof do begin L.Add(Q.Fields[0].AsString); Q.Next; end;
    finally Q.Free; end;
    Result := L.ToArray;
  finally L.Free; end;
end;

function TFirebirdIntrospection.GetIndexes(const ATable: string): TArray<TIndexInfo>;
begin Result := []; end;       // implemented in Task 8

function TFirebirdIntrospection.GetForeignKeys(const ATable: string): TArray<TForeignKeyInfo>;
begin Result := []; end;       // implemented in Task 8
end.
```

Add this private helper `MapFieldType` at the top of the implementation (a `function MapFieldType(AType, ALen, AScale: Integer): string;`):
```pascal
function MapFieldType(AType, ALen, AScale: Integer): string;
begin
  case AType of
    7:  if AScale < 0 then Result := 'NUMERIC' else Result := 'SMALLINT';
    8:  if AScale < 0 then Result := 'NUMERIC' else Result := 'INTEGER';
    16: if AScale < 0 then Result := 'NUMERIC' else Result := 'BIGINT';
    10: Result := 'FLOAT';
    27: Result := 'DOUBLE PRECISION';
    12: Result := 'DATE';
    13: Result := 'TIME';
    35: Result := 'TIMESTAMP';
    14: Result := 'CHAR(' + ALen.ToString + ')';
    37: Result := 'VARCHAR(' + ALen.ToString + ')';
    261: Result := 'BLOB';
  else  Result := 'TYPE#' + AType.ToString;
  end;
end;
```
Declare `MapFieldType` before `GetColumns` in the implementation section.

- [ ] **Step 4: Run to verify it passes** — 4 introspection tests pass.

- [ ] **Step 5: Commit**

```bash
git add sources/Firebird.Introspection.pas tests/coreproject/Test.Firebird.Introspection.pas tests/coreproject/MCPFirebirdCoreTests.dpr
git commit -m "feat(core): introspection — tables, columns, PK, row count (TDD)"
```

---

## Task 8: `Firebird.Introspection` — indexes + foreign keys (TDD)

**Files:**
- Modify: `sources/Firebird.Introspection.pas` (fill `GetIndexes`, `GetForeignKeys`)
- Create: `tests/coreproject/Test.Firebird.Indexes.pas`

- [ ] **Step 1: Write the failing test** (against the seed scenarios)

```pascal
unit Test.Firebird.Indexes;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TIndexIntrospectionTests = class
  public
    [Test] procedure Orders_Has_System_FK_Index_And_User_Dup;
    [Test] procedure Customers_CityIndex_IsInactive;
    [Test] procedure Orders_ForeignKey_References_Customers;
  end;
implementation
uses System.SysUtils, Firebird.Connection, Firebird.Introspection, TestFixtureU;

procedure TIndexIntrospectionTests.Orders_Has_System_FK_Index_And_User_Dup;
var Conn: TFirebirdConnection; I: TFirebirdIntrospection; Idx: TArray<TIndexInfo>; X: TIndexInfo;
    SysCount, DupCount: Integer;
begin
  Conn := NewTestConnection;
  try
    I := TFirebirdIntrospection.Create(Conn);
    try
      Idx := I.GetIndexes('ORDERS'); SysCount := 0; DupCount := 0;
      for X in Idx do begin
        if X.IsSystem and (Length(X.Columns)=1) and SameText(X.Columns[0],'CUSTOMER_ID') then Inc(SysCount);
        if SameText(X.IndexName,'IDX_ORDERS_CUSTOMER_DUP') then Inc(DupCount);
      end;
      Assert.IsTrue(SysCount >= 1, 'system FK index on CUSTOMER_ID exists');
      Assert.AreEqual(1, DupCount, 'user duplicate index present');
    finally I.Free; end;
  finally Conn.Free; end;
end;

procedure TIndexIntrospectionTests.Customers_CityIndex_IsInactive;
var Conn: TFirebirdConnection; I: TFirebirdIntrospection; X: TIndexInfo; Found: Boolean;
begin
  Conn := NewTestConnection;
  try
    I := TFirebirdIntrospection.Create(Conn);
    try
      Found := False;
      for X in I.GetIndexes('CUSTOMERS') do
        if SameText(X.IndexName,'IDX_CUST_CITY') then begin Found := True; Assert.IsTrue(X.Inactive); end;
      Assert.IsTrue(Found, 'IDX_CUST_CITY present');
    finally I.Free; end;
  finally Conn.Free; end;
end;

procedure TIndexIntrospectionTests.Orders_ForeignKey_References_Customers;
var Conn: TFirebirdConnection; I: TFirebirdIntrospection; FKs: TArray<TForeignKeyInfo>;
begin
  Conn := NewTestConnection;
  try
    I := TFirebirdIntrospection.Create(Conn);
    try
      FKs := I.GetForeignKeys('ORDERS');
      Assert.AreEqual(1, Length(FKs));
      Assert.AreEqual('CUSTOMERS', FKs[0].RefTable);
      Assert.AreEqual('CUSTOMER_ID', FKs[0].Columns[0]);
    finally I.Free; end;
  finally Conn.Free; end;
end;
end.
```
Add unit to `.dpr` `uses`.

- [ ] **Step 2: Run to verify it fails** — `GetIndexes` returns `[]`, assertions fail.

- [ ] **Step 3: Implement `GetIndexes` and `GetForeignKeys`**

Replace the two stub bodies:
```pascal
function TFirebirdIntrospection.GetIndexes(const ATable: string): TArray<TIndexInfo>;
var Q: TFDQuery; L: TList<TIndexInfo>; Rec: TIndexInfo; CT: string;
begin
  L := TList<TIndexInfo>.Create;
  try
    Q := FConn.OpenQuery(
      'SELECT TRIM(i.rdb$index_name), COALESCE(i.rdb$unique_flag,0), ' +
      '       COALESCE(i.rdb$index_inactive,0), COALESCE(i.rdb$system_flag,0), ' +
      '       i.rdb$statistics ' +
      'FROM rdb$indices i WHERE i.rdb$relation_name = ' + QuotedStr(ATable) + ' ORDER BY 1', []);
    try
      while not Q.Eof do begin
        Rec := Default(TIndexInfo);
        Rec.IndexName := Q.Fields[0].AsString;
        Rec.Unique    := Q.Fields[1].AsInteger = 1;
        Rec.Inactive  := Q.Fields[2].AsInteger = 1;
        Rec.Selectivity := Q.Fields[4].AsFloat;
        Rec.Columns   := IndexColumns(Rec.IndexName);
        // Constraint type (PRIMARY KEY / FOREIGN KEY / UNIQUE) if this index backs one
        CT := FConn.ScalarStr(
          'SELECT TRIM(rc.rdb$constraint_type) FROM rdb$relation_constraints rc ' +
          'WHERE rc.rdb$index_name = ' + QuotedStr(Rec.IndexName));
        Rec.ConstraintType := CT;
        // System index: backs a constraint OR name begins with RDB$
        Rec.IsSystem := (CT <> '') or Rec.IndexName.StartsWith('RDB$');
        L.Add(Rec); Q.Next;
      end;
    finally Q.Free; end;
    Result := L.ToArray;
  finally L.Free; end;
end;

function TFirebirdIntrospection.GetForeignKeys(const ATable: string): TArray<TForeignKeyInfo>;
var Q: TFDQuery; L: TList<TForeignKeyInfo>; Rec: TForeignKeyInfo;
begin
  L := TList<TForeignKeyInfo>.Create;
  try
    // rc (FK) -> ref_constraints -> rc2 (the referenced UNIQUE/PK constraint)
    Q := FConn.OpenQuery(
      'SELECT TRIM(rc.rdb$constraint_name), TRIM(rc.rdb$index_name), ' +
      '       TRIM(rc2.rdb$relation_name) ' +
      'FROM rdb$relation_constraints rc ' +
      'JOIN rdb$ref_constraints ref ON ref.rdb$constraint_name = rc.rdb$constraint_name ' +
      'JOIN rdb$relation_constraints rc2 ON rc2.rdb$constraint_name = ref.rdb$const_name_uq ' +
      'WHERE rc.rdb$constraint_type = ''FOREIGN KEY'' AND rc.rdb$relation_name = ' + QuotedStr(ATable), []);
    try
      while not Q.Eof do begin
        Rec := Default(TForeignKeyInfo);
        Rec.ConstraintName := Q.Fields[0].AsString;
        Rec.IndexName      := Q.Fields[1].AsString;
        Rec.RefTable       := Q.Fields[2].AsString;
        Rec.Columns        := IndexColumns(Rec.IndexName);
        L.Add(Rec); Q.Next;
      end;
    finally Q.Free; end;
    Result := L.ToArray;
  finally L.Free; end;
end;
```

- [ ] **Step 4: Run to verify it passes** — 3 index/FK tests pass.

- [ ] **Step 5: Commit**

```bash
git add sources/Firebird.Introspection.pas tests/coreproject/Test.Firebird.Indexes.pas tests/coreproject/MCPFirebirdCoreTests.dpr
git commit -m "feat(core): introspection — indexes + foreign keys (TDD)"
```

---

## Task 9: `Firebird.Advisory` record + `Firebird.DocGen` Markdown (TDD)

**Files:**
- Create: `sources/Firebird.Advisory.pas`
- Create: `sources/Firebird.DocGen.pas`
- Create: `tests/coreproject/Test.Firebird.DocGen.pas`

- [ ] **Step 1: Define the advisory record** (no test needed; consumed by later tasks)

`sources/Firebird.Advisory.pas`:
```pascal
unit Firebird.Advisory;
interface
type
  TAdvisory = record
    Finding: string;   // plain-language what & why
    SQLText: string;   // ready-to-run, version-correct
    Verify: string;    // how to confirm it worked
    Severity: string;  // 'info' | 'warning' | 'critical'
    class function Make(const AFinding, ASQL, AVerify, ASeverity: string): TAdvisory; static;
  end;
implementation
class function TAdvisory.Make(const AFinding, ASQL, AVerify, ASeverity: string): TAdvisory;
begin
  Result.Finding := AFinding; Result.SQLText := ASQL; Result.Verify := AVerify; Result.Severity := ASeverity;
end;
end.
```

- [ ] **Step 2: Write the failing DocGen test**

```pascal
unit Test.Firebird.DocGen;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TDocGenTests = class
  public
    [Test] procedure TableDoc_Customers_HasHeadingAndColumns;
    [Test] procedure DatabaseDoc_ListsBothTables;
  end;
implementation
uses System.SysUtils, Firebird.Connection, Firebird.Introspection, Firebird.DocGen, TestFixtureU;

procedure TDocGenTests.TableDoc_Customers_HasHeadingAndColumns;
var Conn: TFirebirdConnection; D: TFirebirdDocGen; MD: string;
begin
  Conn := NewTestConnection;
  try
    D := TFirebirdDocGen.Create(TFirebirdIntrospection.Create(Conn));
    try
      MD := D.TableMarkdown('CUSTOMERS');
      Assert.Contains(MD, '## CUSTOMERS');
      Assert.Contains(MD, 'CITY');
      Assert.Contains(MD, 'CUSTOMER_ID');
    finally D.Free; end;
  finally Conn.Free; end;
end;

procedure TDocGenTests.DatabaseDoc_ListsBothTables;
var Conn: TFirebirdConnection; D: TFirebirdDocGen; MD: string;
begin
  Conn := NewTestConnection;
  try
    D := TFirebirdDocGen.Create(TFirebirdIntrospection.Create(Conn));
    try
      MD := D.DatabaseMarkdown;
      Assert.Contains(MD, 'CUSTOMERS');
      Assert.Contains(MD, 'ORDERS');
    finally D.Free; end;
  finally Conn.Free; end;
end;
end.
```
Add unit to `.dpr` `uses`.

- [ ] **Step 3: Run to verify it fails** — `Firebird.DocGen` not found.

- [ ] **Step 4: Implement `Firebird.DocGen`** (owns the introspection instance it is given)

```pascal
unit Firebird.DocGen;
interface
uses Firebird.Introspection;
type
  TFirebirdDocGen = class
  private
    FIntro: TFirebirdIntrospection;
  public
    constructor Create(AIntro: TFirebirdIntrospection);  // takes ownership
    destructor Destroy; override;
    function TableMarkdown(const ATable: string): string;
    function DatabaseMarkdown: string;
  end;
implementation
uses System.SysUtils, System.Classes;

constructor TFirebirdDocGen.Create(AIntro: TFirebirdIntrospection);
begin inherited Create; FIntro := AIntro; end;
destructor TFirebirdDocGen.Destroy; begin FIntro.Free; inherited; end;

function TFirebirdDocGen.TableMarkdown(const ATable: string): string;
var SB: TStringBuilder; C: TColumnInfo; X: TIndexInfo; PK: TArray<string>; S: string;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('## ' + ATable).AppendLine;
    PK := FIntro.GetPrimaryKey(ATable);
    SB.AppendLine('**Primary key:** ' + string.Join(', ', PK)).AppendLine;
    SB.AppendLine('| Column | Type | Nullable |');
    SB.AppendLine('|---|---|---|');
    for C in FIntro.GetColumns(ATable) do
      SB.AppendLine(Format('| %s | %s | %s |', [C.FieldName, C.DataType, BoolToStr(C.Nullable, True)]));
    SB.AppendLine;
    SB.AppendLine('**Indexes:**');
    for X in FIntro.GetIndexes(ATable) do
    begin
      S := Format('- `%s` (%s)%s', [X.IndexName, string.Join(', ', X.Columns),
        IfThen(X.Inactive, ' — INACTIVE', '')]);
      if X.ConstraintType <> '' then S := S + ' [' + X.ConstraintType + ']';
      SB.AppendLine(S);
    end;
    SB.AppendLine;
    Result := SB.ToString;
  finally SB.Free; end;
end;

function TFirebirdDocGen.DatabaseMarkdown: string;
var SB: TStringBuilder; T: string;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Database documentation').AppendLine;
    for T in FIntro.ListTables(False) do
      SB.AppendLine(TableMarkdown(T));
    Result := SB.ToString;
  finally SB.Free; end;
end;
end.
```
Add `System.StrUtils` to the `uses` for `IfThen`.

- [ ] **Step 5: Run to verify it passes** — 2 DocGen tests pass.

- [ ] **Step 6: Commit**

```bash
git add sources/Firebird.Advisory.pas sources/Firebird.DocGen.pas tests/coreproject/Test.Firebird.DocGen.pas tests/coreproject/MCPFirebirdCoreTests.dpr
git commit -m "feat(core): advisory record + Markdown documentation generator (TDD)"
```

---

## Task 10: SPIKE — verify access-plan retrieval across FB 2.5 and 5.0

> This is the one integration we are not yet certain about: how to obtain a prepared statement's **access plan** without executing it, across FB 2.5 → 5. We resolve it with a throwaway probe before committing to the `PlanAnalyzer` design. No production code is written here.

**Files:**
- Create (throwaway): `spikes/planprobe/PlanProbe.dpr`

- [ ] **Step 1: Probe approach A — FireDAC prepared command + `RowsAffected`/native plan**

Write a tiny console program that connects with FireDAC (same params as `TFirebirdConnection`) and tries, in order, to obtain a plan:
```pascal
program PlanProbe;
{$APPTYPE CONSOLE}
uses System.SysUtils, FireDAC.Comp.Client, FireDAC.Phys.FB, FireDAC.Stan.Def,
  FireDAC.Stan.Async, FireDAC.DApt, Data.DB;
var Conn: TFDConnection; Lnk: TFDPhysFBDriverLink; Q: TFDQuery;
begin
  Lnk := TFDPhysFBDriverLink.Create(nil);
  Lnk.VendorLib := ParamStr(1);           // fbclient.dll path
  Conn := TFDConnection.Create(nil);
  Conn.DriverName := 'FB'; Conn.LoginPrompt := False;
  Conn.Params.Values['Server'] := 'localhost';
  Conn.Params.Values['Port'] := ParamStr(2);
  Conn.Params.Values['Database'] := ParamStr(3);
  Conn.Params.Values['User_Name'] := 'SYSDBA';
  Conn.Params.Values['Password'] := 'masterkey';
  Conn.Params.Values['CharacterSet'] := 'UTF8';
  Conn.Connected := True;
  Q := TFDQuery.Create(nil);
  Q.Connection := Conn;
  Q.SQL.Text := 'SELECT * FROM CUSTOMERS WHERE CITY = ''Rome''';
  Q.Prepare;
  // Probe: does FireDAC expose the plan anywhere?
  Writeln('--- Trying FDQuery.Command.GetServerOutput / Plan ---');
  try Writeln(Q.Command.Options.ResourceOptions.MacroCreate.ToString); except end;
  // Probe B: ask the engine directly via MON$ is not it; try isc API via fbclient (see step 2).
  Writeln('Prepared OK. Now test direct fbclient plan API in step 2.');
end.
```
Run on FB 5.0 and FB 2.5. Record whether FireDAC surfaces the plan at all.

- [ ] **Step 2: Probe approach B — direct fbclient `isc_dsql_sql_info` with `isc_info_sql_get_plan`**

If approach A does not yield a plan, validate the classic low-level path: a separate `isc_attach_database` using the same `fbclient.dll`, `isc_dsql_prepare`, then `isc_dsql_sql_info` with item `isc_info_sql_get_plan` (= 22) into a buffer; the result is `[isc_info_sql_get_plan][len:2][plan text]`. For explained plan on FB 3+, use `isc_info_sql_explain_plan` (= 168). Confirm the returned string starts with `PLAN ` on 2.5 and that 168 returns the detailed tree on 5.0.

- [ ] **Step 3: Decide and record**

Write the chosen mechanism (A or B) as a 5-line note at the top of `sources/Firebird.PlanAnalyzer.pas` (created in Task 11). Delete the `spikes/` folder.

```bash
git add -A && git commit -m "chore(spike): determine FB access-plan retrieval mechanism (notes only)"
```

> **Default assumption for Task 11 if the spike is inconclusive at planning time:** use approach B (direct fbclient), because it is version-spanning and does not depend on FireDAC internals. Task 11 is written against that interface but only the *body* of `GetRawPlan`/`GetExplainedPlan` changes if the spike picks A.

---

## Task 11: `Firebird.PlanAnalyzer` — plan + NATURAL-scan detection (TDD)

**Files:**
- Create: `sources/Firebird.PlanAnalyzer.pas`
- Create: `tests/coreproject/Test.Firebird.PlanAnalyzer.pas`

- [ ] **Step 1: Write the failing test**

```pascal
unit Test.Firebird.PlanAnalyzer;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TPlanAnalyzerTests = class
  public
    [Test] procedure NaturalScan_On_City_Filter_IsDetected;
    [Test] procedure Pk_Lookup_HasNoNaturalScan;
  end;
implementation
uses System.SysUtils, Firebird.Connection, Firebird.Capabilities, Firebird.PlanAnalyzer, TestFixtureU;

procedure TPlanAnalyzerTests.NaturalScan_On_City_Filter_IsDetected;
var Conn: TFirebirdConnection; PA: TFirebirdPlanAnalyzer; R: TPlanResult;
begin
  Conn := NewTestConnection;
  try
    PA := TFirebirdPlanAnalyzer.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try
      R := PA.Analyze('SELECT * FROM CUSTOMERS WHERE CITY = ''Rome''');
      Assert.IsTrue(R.HasNaturalScan, 'filtering CITY (no active index) -> NATURAL');
      Assert.IsTrue(R.RawPlan.ToUpper.Contains('NATURAL'));
    finally PA.Free; end;
  finally Conn.Free; end;
end;

procedure TPlanAnalyzerTests.Pk_Lookup_HasNoNaturalScan;
var Conn: TFirebirdConnection; PA: TFirebirdPlanAnalyzer; R: TPlanResult;
begin
  Conn := NewTestConnection;
  try
    PA := TFirebirdPlanAnalyzer.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try
      R := PA.Analyze('SELECT * FROM CUSTOMERS WHERE CUSTOMER_ID = 1');
      Assert.IsFalse(R.HasNaturalScan, 'PK lookup uses the primary index');
    finally PA.Free; end;
  finally Conn.Free; end;
end;
end.
```
Add unit to `.dpr` `uses`.

- [ ] **Step 2: Run to verify it fails** — `Firebird.PlanAnalyzer` not found.

- [ ] **Step 3: Implement `Firebird.PlanAnalyzer`** (interface stable; plan-fetch body per Task 10 decision)

```pascal
unit Firebird.PlanAnalyzer;
// PLAN RETRIEVAL: per the Task 10 spike. Default = direct fbclient isc_dsql_sql_info
// (isc_info_sql_get_plan=22; isc_info_sql_explain_plan=168 on FB 3+). If the spike
// selected FireDAC's native plan exposure, only GetRawPlan/GetExplainedPlan bodies change.
interface
uses Firebird.Connection, Firebird.Capabilities;
type
  TPlanResult = record
    RawPlan, ExplainedPlan, EngineVersion: string;
    HasNaturalScan: Boolean;
    NaturalTables: TArray<string>;
  end;
  TFirebirdPlanAnalyzer = class
  private
    FConn: TFirebirdConnection;
    FCaps: TFirebirdCapabilities;
    function GetRawPlan(const ASQL: string): string;
    function GetExplainedPlan(const ASQL: string): string;
  public
    constructor Create(AConn: TFirebirdConnection; const ACaps: TFirebirdCapabilities);
    function Analyze(const ASQL: string): TPlanResult;
  end;
implementation
uses System.SysUtils, System.Classes, System.RegularExpressions;

constructor TFirebirdPlanAnalyzer.Create(AConn: TFirebirdConnection; const ACaps: TFirebirdCapabilities);
begin inherited Create; FConn := AConn; FCaps := ACaps; end;

function TFirebirdPlanAnalyzer.GetRawPlan(const ASQL: string): string;
begin
  // Implemented per Task 10 decision. With the direct-fbclient path this attaches via
  // FConn.Config (same fbclient), prepares ASQL under a read-only tx, requests
  // isc_info_sql_get_plan, and returns the trimmed plan string (begins with "PLAN ").
  Result := FConn.PlanFor(ASQL);   // see note below
end;

function TFirebirdPlanAnalyzer.GetExplainedPlan(const ASQL: string): string;
begin
  if FCaps.HasExplainedPlan then
    Result := FConn.ExplainedPlanFor(ASQL)
  else
    Result := '';
end;

function TFirebirdPlanAnalyzer.Analyze(const ASQL: string): TPlanResult;
var M: TMatch;
begin
  Result := Default(TPlanResult);
  Result.EngineVersion := FCaps.EngineVersion;
  Result.RawPlan       := GetRawPlan(ASQL);
  Result.ExplainedPlan := GetExplainedPlan(ASQL);
  Result.HasNaturalScan := Result.RawPlan.ToUpper.Contains('NATURAL');
  // Extract "PLAN (TABLE NATURAL)" table names
  for M in TRegEx.Matches(Result.RawPlan, '(\w+)\s+NATURAL', [roIgnoreCase]) do
    Result.NaturalTables := Result.NaturalTables + [M.Groups[1].Value];
end;
end.
```

> **Note:** `FConn.PlanFor` / `FConn.ExplainedPlanFor` are added to `Firebird.Connection` in this task as the concrete plan-retrieval implementation chosen in Task 10. Add their declarations to `TFirebirdConnection` and implement the body that the spike validated. (If the spike selected approach B, the implementation opens a direct `isc_*` attachment using `FConfig`; the parsing returns the plan substring after the 3-byte cluster header.)

- [ ] **Step 4: Run to verify it passes** — 2 plan tests pass on FB 5.0.

- [ ] **Step 5: Commit**

```bash
git add sources/Firebird.PlanAnalyzer.pas sources/Firebird.Connection.pas tests/coreproject/Test.Firebird.PlanAnalyzer.pas tests/coreproject/MCPFirebirdCoreTests.dpr
git commit -m "feat(core): access-plan analysis + NATURAL-scan detection (TDD)"
```

---

## Task 12: `Firebird.IndexAdvisor` — suggest new indexes (TDD)

**Files:**
- Create: `sources/Firebird.IndexAdvisor.pas`
- Create: `tests/coreproject/Test.Firebird.IndexAdvisor.pas`

- [ ] **Step 1: Write the failing test**

```pascal
unit Test.Firebird.IndexAdvisor;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TIndexAdvisorTests = class
  public
    [Test] procedure SuggestIndexes_ForCityQuery_ProposesCityIndex;
  end;
implementation
uses System.SysUtils, Firebird.Connection, Firebird.Capabilities, Firebird.PlanAnalyzer,
  Firebird.IndexAdvisor, Firebird.Advisory, TestFixtureU;

procedure TIndexAdvisorTests.SuggestIndexes_ForCityQuery_ProposesCityIndex;
var Conn: TFirebirdConnection; A: TFirebirdIndexAdvisor; Advs: TArray<TAdvisory>; X: TAdvisory; Found: Boolean;
begin
  Conn := NewTestConnection;
  try
    A := TFirebirdIndexAdvisor.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try
      // IDX_CUST_CITY is INACTIVE, so CITY filter goes NATURAL -> advisor proposes an index on CITY
      Advs := A.SuggestForQuery('SELECT * FROM CUSTOMERS WHERE CITY = ''Rome''');
      Found := False;
      for X in Advs do
        if X.SQLText.ToUpper.Contains('ON CUSTOMERS') and X.SQLText.ToUpper.Contains('CITY') then Found := True;
      Assert.IsTrue(Found, 'proposes CREATE INDEX ... ON CUSTOMERS (CITY)');
    finally A.Free; end;
  finally Conn.Free; end;
end;
end.
```
Add unit to `.dpr` `uses`.

- [ ] **Step 2: Run to verify it fails** — `Firebird.IndexAdvisor` not found.

- [ ] **Step 3: Implement `SuggestForQuery`** — parse predicate columns from the query for the NATURAL-scanned tables

```pascal
unit Firebird.IndexAdvisor;
interface
uses Firebird.Connection, Firebird.Capabilities, Firebird.Advisory;
type
  TFirebirdIndexAdvisor = class
  private
    FConn: TFirebirdConnection;
    FCaps: TFirebirdCapabilities;
  public
    constructor Create(AConn: TFirebirdConnection; const ACaps: TFirebirdCapabilities);
    function SuggestForQuery(const ASQL: string): TArray<TAdvisory>;   // this task
    function SuggestDropsForTable(const ATable: string): TArray<TAdvisory>; // Task 13
  end;
implementation
uses System.SysUtils, System.Classes, System.RegularExpressions,
  Firebird.PlanAnalyzer, Firebird.Introspection;

constructor TFirebirdIndexAdvisor.Create(AConn: TFirebirdConnection; const ACaps: TFirebirdCapabilities);
begin inherited Create; FConn := AConn; FCaps := ACaps; end;

function TFirebirdIndexAdvisor.SuggestForQuery(const ASQL: string): TArray<TAdvisory>;
var PA: TFirebirdPlanAnalyzer; R: TPlanResult; T, Col, Idx: string; M: TMatch;
    Advs: TList<TAdvisory>;
begin
  Advs := TList<TAdvisory>.Create;
  try
    PA := TFirebirdPlanAnalyzer.Create(FConn, FCaps);
    try R := PA.Analyze(ASQL); finally PA.Free; end;
    if not R.HasNaturalScan then Exit([]);
    // For each NATURAL-scanned table, find predicate columns "<col> <op>" in WHERE/JOIN.
    for T in R.NaturalTables do
      for M in TRegEx.Matches(ASQL, '(\w+)\s*(=|>|<|>=|<=|LIKE|BETWEEN|IN)\b', [roIgnoreCase]) do
      begin
        Col := M.Groups[1].Value;
        if SameText(Col, T) then Continue;
        Idx := Format('IDX_%s_%s', [T, Col]).ToUpper;
        Advs.Add(TAdvisory.Make(
          Format('Table %s is scanned NATURAL when filtered by %s. An index lets the optimizer seek instead of scanning every row.', [T, Col]),
          Format('CREATE INDEX %s ON %s (%s);', [Idx, T, Col]),
          Format('Re-run fb_analyze_query on this query; the plan should use %s and no longer show "%s NATURAL". Then run SET STATISTICS INDEX %s; to refresh selectivity.', [Idx, T, Idx]),
          'warning'));
      end;
    Result := Advs.ToArray;
  finally Advs.Free; end;
end;

function TFirebirdIndexAdvisor.SuggestDropsForTable(const ATable: string): TArray<TAdvisory>;
begin Result := []; end;  // Task 13
end.
```

- [ ] **Step 4: Run to verify it passes** — index-advisor test passes.

- [ ] **Step 5: Commit**

```bash
git add sources/Firebird.IndexAdvisor.pas tests/coreproject/Test.Firebird.IndexAdvisor.pas tests/coreproject/MCPFirebirdCoreTests.dpr
git commit -m "feat(core): index advisor — suggest new indexes from NATURAL scans (TDD)"
```

---

## Task 13: `Firebird.IndexAdvisor` — suggest drops (TDD)

**Files:**
- Modify: `sources/Firebird.IndexAdvisor.pas` (fill `SuggestDropsForTable`)
- Create: `tests/coreproject/Test.Firebird.IndexDrops.pas`

- [ ] **Step 1: Write the failing test**

```pascal
unit Test.Firebird.IndexDrops;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TIndexDropTests = class
  public
    [Test] procedure Flags_DuplicateOfSystemFkIndex;
    [Test] procedure Flags_RedundantLeftPrefix;
    [Test] procedure Flags_InactiveIndex;
  end;
implementation
uses System.SysUtils, Firebird.Connection, Firebird.Capabilities, Firebird.IndexAdvisor,
  Firebird.Advisory, TestFixtureU;

function AnyDropMentions(const Advs: TArray<TAdvisory>; const AName: string): Boolean;
var X: TAdvisory;
begin
  Result := False;
  for X in Advs do
    if X.SQLText.ToUpper.Contains('DROP INDEX ' + AName.ToUpper) or
       X.SQLText.ToUpper.Contains(AName.ToUpper) then Exit(True);
end;

procedure TIndexDropTests.Flags_DuplicateOfSystemFkIndex;
var Conn: TFirebirdConnection; A: TFirebirdIndexAdvisor;
begin
  Conn := NewTestConnection;
  try
    A := TFirebirdIndexAdvisor.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try
      Assert.IsTrue(AnyDropMentions(A.SuggestDropsForTable('ORDERS'), 'IDX_ORDERS_CUSTOMER_DUP'),
        'duplicate of system FK index flagged');
    finally A.Free; end;
  finally Conn.Free; end;
end;

procedure TIndexDropTests.Flags_RedundantLeftPrefix;
var Conn: TFirebirdConnection; A: TFirebirdIndexAdvisor;
begin
  Conn := NewTestConnection;
  try
    A := TFirebirdIndexAdvisor.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try
      Assert.IsTrue(AnyDropMentions(A.SuggestDropsForTable('CUSTOMERS'), 'IDX_CUST_NAME'),
        'left-prefix IDX_CUST_NAME redundant vs IDX_CUST_NAME_CITY');
    finally A.Free; end;
  finally Conn.Free; end;
end;

procedure TIndexDropTests.Flags_InactiveIndex;
var Conn: TFirebirdConnection; A: TFirebirdIndexAdvisor;
begin
  Conn := NewTestConnection;
  try
    A := TFirebirdIndexAdvisor.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try
      Assert.IsTrue(AnyDropMentions(A.SuggestDropsForTable('CUSTOMERS'), 'IDX_CUST_CITY'),
        'inactive index flagged');
    finally A.Free; end;
  finally Conn.Free; end;
end;
end.
```
Add unit to `.dpr` `uses`.

- [ ] **Step 2: Run to verify it fails** — `SuggestDropsForTable` returns `[]`.

- [ ] **Step 3: Implement `SuggestDropsForTable`**

Replace the stub:
```pascal
function TFirebirdIndexAdvisor.SuggestDropsForTable(const ATable: string): TArray<TAdvisory>;
var Intro: TFirebirdIntrospection; Idx: TArray<TIndexInfo>; I, J: Integer;
    Advs: TList<TAdvisory>;
  function SameCols(const A, B: TArray<string>): Boolean;
  var K: Integer;
  begin
    Result := Length(A) = Length(B);
    if Result then for K := 0 to High(A) do if not SameText(A[K], B[K]) then Exit(False);
  end;
  function IsLeftPrefixOf(const A, B: TArray<string>): Boolean; // A prefix of B, A shorter
  var K: Integer;
  begin
    Result := (Length(A) > 0) and (Length(A) < Length(B));
    if Result then for K := 0 to High(A) do if not SameText(A[K], B[K]) then Exit(False);
  end;
begin
  Advs := TList<TAdvisory>.Create;
  Intro := TFirebirdIntrospection.Create(FConn);
  try
    Idx := Intro.GetIndexes(ATable);
    for I := 0 to High(Idx) do
    begin
      // (a) inactive
      if Idx[I].Inactive then
        Advs.Add(TAdvisory.Make(
          Format('Index %s on %s is INACTIVE: it is maintained on writes-when-reactivated expectations but currently unused for reads.', [Idx[I].IndexName, ATable]),
          Format('DROP INDEX %s;  -- or ALTER INDEX %s ACTIVE; if you intend to use it', [Idx[I].IndexName, Idx[I].IndexName]),
          'Confirm no query relies on it, then drop. fb_describe_table should no longer list it.',
          'warning'));
      // (b) user index duplicating / redundant vs another index on the same table
      if not Idx[I].IsSystem then
        for J := 0 to High(Idx) do
        begin
          if I = J then Continue;
          if SameCols(Idx[I].Columns, Idx[J].Columns) and (Idx[J].IsSystem or (J < I)) then
            Advs.Add(TAdvisory.Make(
              Format('Index %s duplicates %s (same columns %s). Firebird already maintains the other index%s; the duplicate only adds write cost.',
                [Idx[I].IndexName, Idx[J].IndexName, string.Join(', ', Idx[I].Columns), IfThen(Idx[J].IsSystem, ' (a system constraint index)', '')]),
              Format('DROP INDEX %s;', [Idx[I].IndexName]),
              'fb_describe_table should list one index on these columns afterwards.',
              'warning'))
          else if IsLeftPrefixOf(Idx[I].Columns, Idx[J].Columns) and not Idx[I].Unique then
            Advs.Add(TAdvisory.Make(
              Format('Index %s (%s) is a left-prefix of %s (%s); the wider index already serves prefix lookups.',
                [Idx[I].IndexName, string.Join(', ', Idx[I].Columns), Idx[J].IndexName, string.Join(', ', Idx[J].Columns)]),
              Format('DROP INDEX %s;', [Idx[I].IndexName]),
              'Verify queries still use the wider index via fb_analyze_query.',
              'info'));
        end;
      // (c) low selectivity (RDB$STATISTICS near 1 means few distinct values)
      if (not Idx[I].IsSystem) and (Idx[I].Selectivity > 0.5) then
        Advs.Add(TAdvisory.Make(
          Format('Index %s has poor selectivity (%.3f, 1.0 = all rows identical). It rarely helps the optimizer.', [Idx[I].IndexName, Idx[I].Selectivity]),
          Format('-- Review usage before dropping:%sDROP INDEX %s;', [sLineBreak, Idx[I].IndexName]),
          'Run SET STATISTICS INDEX ' + Idx[I].IndexName + '; first to refresh; if still > 0.5 it is a drop candidate.',
          'info'));
    end;
    Result := Advs.ToArray;
  finally
    Intro.Free; Advs.Free;
  end;
end;
```
Add `System.StrUtils` (for `IfThen`) and `System.Generics.Collections` to the implementation `uses`.

- [ ] **Step 4: Run to verify it passes** — 3 drop tests pass.

- [ ] **Step 5: Commit**

```bash
git add sources/Firebird.IndexAdvisor.pas tests/coreproject/Test.Firebird.IndexDrops.pas tests/coreproject/MCPFirebirdCoreTests.dpr
git commit -m "feat(core): index advisor — duplicate/redundant/inactive/low-selectivity drops (TDD)"
```

---

## Task 14: `Firebird.Goal` — deterministic goal evaluation (TDD)

**Files:**
- Create: `sources/Firebird.Goal.pas`
- Create: `tests/coreproject/Test.Firebird.Goal.pas`

- [ ] **Step 1: Write the failing test**

```pascal
unit Test.Firebird.Goal;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TGoalTests = class
  public
    [Test] procedure NoNaturalScan_NotMet_When_Index_Missing_Then_Met_After_Create;
    [Test] procedure NoRedundantIndexes_NotMet_On_Seed;
  end;
implementation
uses System.SysUtils, Firebird.Connection, Firebird.Capabilities, Firebird.Goal, TestFixtureU;

procedure TGoalTests.NoNaturalScan_NotMet_When_Index_Missing_Then_Met_After_Create;
var Conn: TFirebirdConnection; G: TFirebirdGoal; R: TGoalResult;
begin
  Conn := NewTestConnection;
  try
    G := TFirebirdGoal.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try
      R := G.Evaluate('query_no_natural_scan', 'SELECT * FROM CUSTOMERS WHERE CITY = ''Rome''', 0);
      Assert.IsFalse(R.Met, 'baseline: NATURAL scan present');
      Conn.ExecSQL('CREATE INDEX IDX_GOAL_CITY ON CUSTOMERS (CITY)');
      try
        R := G.Evaluate('query_no_natural_scan', 'SELECT * FROM CUSTOMERS WHERE CITY = ''Rome''', 0);
        Assert.IsTrue(R.Met, 'after index: no NATURAL scan');
      finally
        Conn.ExecSQL('DROP INDEX IDX_GOAL_CITY');
      end;
    finally G.Free; end;
  finally Conn.Free; end;
end;

procedure TGoalTests.NoRedundantIndexes_NotMet_On_Seed;
var Conn: TFirebirdConnection; G: TFirebirdGoal; R: TGoalResult;
begin
  Conn := NewTestConnection;
  try
    G := TFirebirdGoal.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try
      R := G.Evaluate('no_redundant_indexes', 'ORDERS', 0);
      Assert.IsFalse(R.Met, 'ORDERS has the duplicate FK index');
    finally G.Free; end;
  finally Conn.Free; end;
end;
end.
```
Add unit to `.dpr` `uses`.

- [ ] **Step 2: Run to verify it fails** — `Firebird.Goal` not found.

- [ ] **Step 3: Implement `Firebird.Goal`** (M1 goal types: `query_no_natural_scan`, `query_time_ms`, `query_max_reads`, `no_redundant_indexes`)

```pascal
unit Firebird.Goal;
interface
uses Firebird.Connection, Firebird.Capabilities;
type
  TGoalResult = record
    GoalType, Target: string;
    Measured, Threshold, Gap: Double;
    Met: Boolean;
    Hint, EngineVersion, DetailsJSON: string;
  end;
  TFirebirdGoal = class
  private
    FConn: TFirebirdConnection;
    FCaps: TFirebirdCapabilities;
    function EvalNoNaturalScan(const ASQL: string): TGoalResult;
    function EvalQueryTimeMs(const ASQL: string; AThreshold: Double): TGoalResult;
    function EvalNoRedundantIndexes(const ATable: string): TGoalResult;
  public
    constructor Create(AConn: TFirebirdConnection; const ACaps: TFirebirdCapabilities);
    function Evaluate(const AGoalType, ATarget: string; AThreshold: Double): TGoalResult;
  end;
implementation
uses System.SysUtils, System.Diagnostics, FireDAC.Comp.Client,
  Firebird.PlanAnalyzer, Firebird.IndexAdvisor;

constructor TFirebirdGoal.Create(AConn: TFirebirdConnection; const ACaps: TFirebirdCapabilities);
begin inherited Create; FConn := AConn; FCaps := ACaps; end;

function TFirebirdGoal.EvalNoNaturalScan(const ASQL: string): TGoalResult;
var PA: TFirebirdPlanAnalyzer; R: TPlanResult;
begin
  Result := Default(TGoalResult);
  Result.GoalType := 'query_no_natural_scan'; Result.Target := ASQL; Result.EngineVersion := FCaps.EngineVersion;
  PA := TFirebirdPlanAnalyzer.Create(FConn, FCaps);
  try R := PA.Analyze(ASQL); finally PA.Free; end;
  Result.Measured := Ord(R.HasNaturalScan);
  Result.Met := not R.HasNaturalScan;
  Result.Hint := 'plan: ' + R.RawPlan;
end;

function TFirebirdGoal.EvalQueryTimeMs(const ASQL: string; AThreshold: Double): TGoalResult;
var SW: TStopwatch; Q: TFDQuery;
begin
  Result := Default(TGoalResult);
  Result.GoalType := 'query_time_ms'; Result.Target := ASQL; Result.Threshold := AThreshold; Result.EngineVersion := FCaps.EngineVersion;
  SW := TStopwatch.StartNew;
  Q := FConn.OpenQuery(ASQL);
  try while not Q.Eof do Q.Next; finally Q.Free; end;
  Result.Measured := SW.Elapsed.TotalMilliseconds;
  Result.Gap := Result.Measured - AThreshold;
  Result.Met := Result.Measured <= AThreshold;
end;

function TFirebirdGoal.EvalNoRedundantIndexes(const ATable: string): TGoalResult;
var A: TFirebirdIndexAdvisor; Drops: Integer;
begin
  Result := Default(TGoalResult);
  Result.GoalType := 'no_redundant_indexes'; Result.Target := ATable; Result.EngineVersion := FCaps.EngineVersion;
  A := TFirebirdIndexAdvisor.Create(FConn, FCaps);
  try Drops := Length(A.SuggestDropsForTable(ATable)); finally A.Free; end;
  Result.Measured := Drops;
  Result.Met := Drops = 0;
  Result.Hint := Format('%d index drop suggestion(s) outstanding', [Drops]);
end;

function TFirebirdGoal.Evaluate(const AGoalType, ATarget: string; AThreshold: Double): TGoalResult;
begin
  if SameText(AGoalType, 'query_no_natural_scan') then Result := EvalNoNaturalScan(ATarget)
  else if SameText(AGoalType, 'query_time_ms')     then Result := EvalQueryTimeMs(ATarget, AThreshold)
  else if SameText(AGoalType, 'no_redundant_indexes') then Result := EvalNoRedundantIndexes(ATarget)
  else raise Exception.CreateFmt('Unknown goal_type: %s', [AGoalType]);
end;
end.
```

> `query_max_reads` and `oat_gap` are deferred to M2 (they need MON$ I/O stats); `Evaluate` raises a clear error for them, which the MCP layer surfaces as a normal tool error. This is intentional, not a gap.

- [ ] **Step 4: Run to verify it passes** — 2 goal tests pass.

- [ ] **Step 5: Commit**

```bash
git add sources/Firebird.Goal.pas tests/coreproject/Test.Firebird.Goal.pas tests/coreproject/MCPFirebirdCoreTests.dpr
git commit -m "feat(core): deterministic goal evaluation engine (TDD)"
```

---

## Task 15: MCP tool provider — wrap the core (`fb_*` tools)

**Files:**
- Create: `providers/FirebirdConfigU.pas` (build config from dotEnv — app-side, keeps core pure)
- Create: `providers/FirebirdToolsU.pas`

- [ ] **Step 1: Write the dotEnv→config loader (app layer)**

`providers/FirebirdConfigU.pas`:
```pascal
unit FirebirdConfigU;
interface
uses Firebird.Connection;
function LoadFirebirdConfig: TFirebirdConnectionConfig;
function NewConfiguredConnection: TFirebirdConnection;  // connected
implementation
uses System.SysUtils, MVCFramework.DotEnv, MVCFramework.Commons;

function LoadFirebirdConfig: TFirebirdConnectionConfig;
begin
  Result := Default(TFirebirdConnectionConfig);
  Result.Host      := dotEnv.Env('firebird.host', 'localhost');
  Result.Port      := dotEnv.Env('firebird.port', 3050);
  Result.Database  := dotEnv.Env('firebird.database', '');
  Result.User      := dotEnv.Env('firebird.user', 'SYSDBA');
  Result.Password  := dotEnv.Env('firebird.password', 'masterkey');
  Result.Charset   := dotEnv.Env('firebird.charset', 'UTF8');
  Result.ClientLib := dotEnv.Env('firebird.client_lib', '');
  Result.AllowDDL  := dotEnv.Env('firebird.allow_ddl', False);
end;

function NewConfiguredConnection: TFirebirdConnection;
begin
  Result := TFirebirdConnection.Create(LoadFirebirdConfig);
  Result.Connect;
end;
end.
```

- [ ] **Step 2: Write the tool provider** (each tool opens a short-lived connection, calls the core, formats Finding/SQL/Verify)

`providers/FirebirdToolsU.pas`:
```pascal
unit FirebirdToolsU;
interface
uses MVCFramework.MCP.ToolProvider, MVCFramework.MCP.Attributes;
type
  TFirebirdTools = class(TMCPToolProvider)
  public
    [MCPTool('fb_info', 'Engine version, dialect, charset and detected capabilities of the configured Firebird database')]
    function FbInfo: TMCPToolResult;

    [MCPTool('fb_list_tables', 'Lists user tables (and views) in the configured database')]
    function FbListTables: TMCPToolResult;

    [MCPTool('fb_describe_table', 'Columns, primary key, indexes and foreign keys of a table')]
    function FbDescribeTable([MCPParam('Table name')] const table_name: string): TMCPToolResult;

    [MCPTool('fb_generate_documentation', 'Markdown documentation for one table, or the whole database when table_name is empty')]
    function FbGenerateDocumentation(
      [MCPParam('Table name; leave empty for the whole database', TMCPParamPresence.Optional)] const table_name: string): TMCPToolResult;

    [MCPTool('fb_analyze_query', 'Returns and analyzes the access plan of a SQL query (flags NATURAL scans)')]
    function FbAnalyzeQuery([MCPParam('The SQL query to analyze')] const sql: string): TMCPToolResult;

    [MCPTool('fb_suggest_indexes', 'Suggests new indexes for the NATURAL-scanned columns of a query (ready-to-run DDL)')]
    function FbSuggestIndexes([MCPParam('The SQL query to optimize')] const sql: string): TMCPToolResult;

    [MCPTool('fb_suggest_index_drops', 'Suggests droppable indexes for a table (duplicate/redundant/inactive/low-selectivity)')]
    function FbSuggestIndexDrops([MCPParam('Table name')] const table_name: string): TMCPToolResult;

    [MCPTool('fb_evaluate_goal', 'Deterministically measures an optimization goal and returns whether it is met')]
    function FbEvaluateGoal(
      [MCPParam('Goal type: query_no_natural_scan | query_time_ms | no_redundant_indexes')] const goal_type: string;
      [MCPParam('Target: a SQL query or a table name')] const target: string;
      [MCPParam('Threshold (ms for query_time_ms; ignored otherwise)', TMCPParamPresence.Optional)] const threshold: Double): TMCPToolResult;
  end;
implementation
uses
  System.SysUtils, System.Classes, JsonDataObjects,
  Firebird.Connection, Firebird.Capabilities, Firebird.Introspection,
  Firebird.DocGen, Firebird.PlanAnalyzer, Firebird.IndexAdvisor, Firebird.Advisory,
  Firebird.Goal, FirebirdConfigU, MVCFramework.MCP.Server;

function AdvisoriesToText(const Advs: TArray<TAdvisory>; const AEmptyMsg: string): string;
var SB: TStringBuilder; X: TAdvisory;
begin
  if Length(Advs) = 0 then Exit(AEmptyMsg);
  SB := TStringBuilder.Create;
  try
    for X in Advs do
      SB.AppendLine('### ' + X.Severity).AppendLine('**Finding:** ' + X.Finding)
        .AppendLine.AppendLine('```sql').AppendLine(X.SQLText).AppendLine('```')
        .AppendLine('**Verify:** ' + X.Verify).AppendLine;
    Result := SB.ToString;
  finally SB.Free; end;
end;

function TFirebirdTools.FbInfo: TMCPToolResult;
var Conn: TFirebirdConnection; C: TFirebirdCapabilities; J: TJDOJsonObject;
begin
  Conn := NewConfiguredConnection;
  try
    C := TFirebirdCapabilities.Detect(Conn);
    J := TJDOJsonObject.Create;
    try
      J.S['engine_version'] := C.EngineVersion;
      J.I['major'] := C.Major; J.I['minor'] := C.Minor;
      J.B['has_explained_plan'] := C.HasExplainedPlan;
      J.B['has_boolean_type'] := C.HasBooleanType;
      J.B['has_parallel_workers'] := C.HasParallelWorkers;
      J.S['database'] := Conn.Config.Database;
      Result := TMCPToolResult.JSON(J);
    finally J.Free; end;
  finally Conn.Free; end;
end;

function TFirebirdTools.FbListTables: TMCPToolResult;
var Conn: TFirebirdConnection; I: TFirebirdIntrospection; T: string; SB: TStringBuilder;
begin
  Conn := NewConfiguredConnection;
  try
    I := TFirebirdIntrospection.Create(Conn);
    SB := TStringBuilder.Create;
    try
      for T in I.ListTables do SB.AppendLine('- ' + T);
      Result := TMCPToolResult.Text(SB.ToString);
    finally SB.Free; I.Free; end;
  finally Conn.Free; end;
end;

function TFirebirdTools.FbDescribeTable(const table_name: string): TMCPToolResult;
var Conn: TFirebirdConnection; D: TFirebirdDocGen;
begin
  Conn := NewConfiguredConnection;
  try
    D := TFirebirdDocGen.Create(TFirebirdIntrospection.Create(Conn));
    try Result := TMCPToolResult.Text(D.TableMarkdown(table_name.ToUpper));
    finally D.Free; end;
  finally Conn.Free; end;
end;

function TFirebirdTools.FbGenerateDocumentation(const table_name: string): TMCPToolResult;
var Conn: TFirebirdConnection; D: TFirebirdDocGen;
begin
  Conn := NewConfiguredConnection;
  try
    D := TFirebirdDocGen.Create(TFirebirdIntrospection.Create(Conn));
    try
      if table_name.Trim.IsEmpty then Result := TMCPToolResult.Text(D.DatabaseMarkdown)
      else Result := TMCPToolResult.Text(D.TableMarkdown(table_name.ToUpper));
    finally D.Free; end;
  finally Conn.Free; end;
end;

function TFirebirdTools.FbAnalyzeQuery(const sql: string): TMCPToolResult;
var Conn: TFirebirdConnection; PA: TFirebirdPlanAnalyzer; R: TPlanResult; SB: TStringBuilder;
begin
  Conn := NewConfiguredConnection;
  try
    PA := TFirebirdPlanAnalyzer.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    SB := TStringBuilder.Create;
    try
      R := PA.Analyze(sql);
      SB.AppendLine('**Engine:** ' + R.EngineVersion).AppendLine;
      SB.AppendLine('**PLAN:**').AppendLine('```').AppendLine(R.RawPlan).AppendLine('```');
      if R.ExplainedPlan <> '' then
        SB.AppendLine('**Explained plan:**').AppendLine('```').AppendLine(R.ExplainedPlan).AppendLine('```');
      if R.HasNaturalScan then
        SB.AppendLine('⚠️ **NATURAL scan** on: ' + string.Join(', ', R.NaturalTables) +
          '. Run fb_suggest_indexes on this query for ready-to-run DDL.')
      else
        SB.AppendLine('✅ No NATURAL scan: every table is accessed via an index.');
      Result := TMCPToolResult.Text(SB.ToString);
    finally SB.Free; PA.Free; end;
  finally Conn.Free; end;
end;

function TFirebirdTools.FbSuggestIndexes(const sql: string): TMCPToolResult;
var Conn: TFirebirdConnection; A: TFirebirdIndexAdvisor;
begin
  Conn := NewConfiguredConnection;
  try
    A := TFirebirdIndexAdvisor.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try Result := TMCPToolResult.Text(AdvisoriesToText(A.SuggestForQuery(sql),
      'No new index suggested: the query has no NATURAL scan.'));
    finally A.Free; end;
  finally Conn.Free; end;
end;

function TFirebirdTools.FbSuggestIndexDrops(const table_name: string): TMCPToolResult;
var Conn: TFirebirdConnection; A: TFirebirdIndexAdvisor;
begin
  Conn := NewConfiguredConnection;
  try
    A := TFirebirdIndexAdvisor.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try Result := TMCPToolResult.Text(AdvisoriesToText(A.SuggestDropsForTable(table_name.ToUpper),
      'No droppable indexes found on ' + table_name + '.'));
    finally A.Free; end;
  finally Conn.Free; end;
end;

function TFirebirdTools.FbEvaluateGoal(const goal_type, target: string; const threshold: Double): TMCPToolResult;
var Conn: TFirebirdConnection; G: TFirebirdGoal; R: TGoalResult; J: TJDOJsonObject;
begin
  Conn := NewConfiguredConnection;
  try
    G := TFirebirdGoal.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try
      R := G.Evaluate(goal_type, target, threshold);
      J := TJDOJsonObject.Create;
      try
        J.S['goal_type'] := R.GoalType; J.S['target'] := R.Target;
        J.F['measured'] := R.Measured; J.F['threshold'] := R.Threshold;
        J.B['met'] := R.Met; J.F['gap'] := R.Gap;
        J.S['iteration_hint'] := R.Hint; J.S['engine_version'] := R.EngineVersion;
        Result := TMCPToolResult.JSON(J);
      finally J.Free; end;
    finally G.Free; end;
  finally Conn.Free; end;
end;

initialization
  TMCPServer.Instance.RegisterToolProvider(TFirebirdTools);
end.
```

- [ ] **Step 3: Build the app with providers wired** (done in Task 17). No standalone test here — covered by Tasks 16–18.

- [ ] **Step 4: Commit**

```bash
git add providers/FirebirdConfigU.pas providers/FirebirdToolsU.pas
git commit -m "feat(mcp): fb_* tool provider wrapping the Firebird analysis core"
```

---

## Task 16: MCP prompt + resource providers

**Files:**
- Create: `providers/FirebirdPromptsU.pas`
- Create: `providers/FirebirdResourcesU.pas`

- [ ] **Step 1: Write the `optimization_goal` prompt (the goal loop)**

`providers/FirebirdPromptsU.pas`:
```pascal
unit FirebirdPromptsU;
interface
uses JsonDataObjects, MVCFramework.MCP.PromptProvider, MVCFramework.MCP.Attributes;
type
  TFirebirdPrompts = class(TMCPPromptProvider)
  public
    [MCPPrompt('optimization_goal', 'Iteratively optimize a query or table until a measurable goal is met')]
    [MCPPromptArg('goal_type', 'query_no_natural_scan | query_time_ms | no_redundant_indexes', TMCPParamPresence.Required)]
    [MCPPromptArg('target', 'A SQL query or a table name', TMCPParamPresence.Required)]
    [MCPPromptArg('threshold', 'Numeric threshold (ms for query_time_ms)', TMCPParamPresence.Optional)]
    [MCPPromptArg('max_iterations', 'Safety cap (default 5)', TMCPParamPresence.Optional)]
    function OptimizationGoal(const Arguments: TJDOJsonObject): TMCPPromptResult;

    [MCPPrompt('health_check', 'Run a read-only health review of the configured Firebird database')]
    function HealthCheck(const Arguments: TJDOJsonObject): TMCPPromptResult;
  end;
implementation
uses System.SysUtils, MVCFramework.MCP.Server;

function TFirebirdPrompts.OptimizationGoal(const Arguments: TJDOJsonObject): TMCPPromptResult;
var GT, Target, Thr, MaxIt: string;
begin
  GT := Arguments.S['goal_type']; Target := Arguments.S['target'];
  Thr := Arguments.S['threshold']; MaxIt := Arguments.S['max_iterations'];
  if MaxIt.IsEmpty then MaxIt := '5';
  Result := TMCPPromptResult.Create(
    'Goal-driven Firebird optimization',
    [
      PromptMessage('user',
        'You are optimizing a Firebird database toward a measurable goal.' + sLineBreak +
        'goal_type = ' + GT + sLineBreak +
        'target = ' + Target + sLineBreak +
        'threshold = ' + Thr + sLineBreak +
        'max_iterations = ' + MaxIt + sLineBreak + sLineBreak +
        'Protocol — follow it exactly:' + sLineBreak +
        '1. Call fb_evaluate_goal(goal_type, target, threshold) to establish the baseline.' + sLineBreak +
        '2. If met=true, STOP and report the result.' + sLineBreak +
        '3. Otherwise call fb_analyze_query and fb_suggest_indexes (for query goals) or ' +
        'fb_suggest_index_drops (for table goals). Present the suggested SQL. If the user has ' +
        'enabled writes (firebird.allow_ddl=true) you may apply it with the write tools; otherwise ' +
        'ask the user to run the SQL.' + sLineBreak +
        '4. Call fb_evaluate_goal again and compare "measured" to the previous iteration.' + sLineBreak +
        '5. Repeat until met=true, OR max_iterations is reached, OR there is no improvement for 2 ' +
        'consecutive iterations. In the last two cases, report the best result found and explain ' +
        'why the goal appears unreachable.' + sLineBreak + sLineBreak +
        'Always show the engine_version from fb_evaluate_goal so the advice is version-correct.'),
      PromptMessage('assistant',
        'Understood. I will start by measuring the baseline with fb_evaluate_goal, then iterate ' +
        'with analysis and index suggestions, stopping as soon as the goal is met or cannot improve.')
    ]);
end;

function TFirebirdPrompts.HealthCheck(const Arguments: TJDOJsonObject): TMCPPromptResult;
begin
  Result := TMCPPromptResult.Create(
    'Firebird health check',
    [
      PromptMessage('user',
        'Perform a read-only health review of the configured Firebird database. Steps:' + sLineBreak +
        '1. Call fb_info and report the engine version and capabilities.' + sLineBreak +
        '2. Call fb_list_tables.' + sLineBreak +
        '3. For each table, call fb_suggest_index_drops and collect the findings.' + sLineBreak +
        '4. Summarize: redundant/duplicate/inactive indexes, with the ready-to-run SQL grouped by table.')
    ]);
end;

initialization
  TMCPServer.Instance.RegisterPromptProvider(TFirebirdPrompts);
end.
```

- [ ] **Step 2: Write the schema resource**

`providers/FirebirdResourcesU.pas`:
```pascal
unit FirebirdResourcesU;
interface
uses MVCFramework.MCP.ResourceProvider, MVCFramework.MCP.Attributes;
type
  TFirebirdResources = class(TMCPResourceProvider)
  public
    [MCPResource('firebird://schema', 'Database schema', 'Full Markdown schema of the configured database', 'text/markdown')]
    function Schema(const URI: string): TMCPResourceResult;
  end;
implementation
uses
  Firebird.Connection, Firebird.Introspection, Firebird.DocGen, FirebirdConfigU,
  MVCFramework.MCP.Server;

function TFirebirdResources.Schema(const URI: string): TMCPResourceResult;
var Conn: TFirebirdConnection; D: TFirebirdDocGen;
begin
  Conn := NewConfiguredConnection;
  try
    D := TFirebirdDocGen.Create(TFirebirdIntrospection.Create(Conn));
    try Result := TMCPResourceResult.Text(URI, D.DatabaseMarkdown, 'text/markdown');
    finally D.Free; end;
  finally Conn.Free; end;
end;

initialization
  TMCPServer.Instance.RegisterResourceProvider(TFirebirdResources);
end.
```

> Verify `TMCPResourceResult.Text` and `RegisterResourceProvider` signatures against `MVCFramework.MCP.ResourceProvider.pas` / `MVCFramework.MCP.Server.pas`; adjust the factory call if the library names differ (e.g. `TMCPResourceResult.Create`).

- [ ] **Step 3: Commit**

```bash
git add providers/FirebirdPromptsU.pas providers/FirebirdResourcesU.pas
git commit -m "feat(mcp): optimization_goal + health_check prompts and schema resource"
```

---

## Task 17: Wire providers into the app + enforce the core boundary

**Files:**
- Modify: `app/MCPFirebird.dpr`
- Create: `tests/check_core_boundary.ps1`

- [ ] **Step 1: Add providers to the `.dpr` `uses`**

```pascal
uses
  System.SysUtils,
  MVCFramework.MCP.Server,
  MVCFramework.MCP.Stdio,
  MVCFramework.MCP.StdioOnly,
  BootConfigU in 'BootConfigU.pas',
  EngineConfigU in 'EngineConfigU.pas',
  FirebirdConfigU in '..\providers\FirebirdConfigU.pas',
  FirebirdToolsU in '..\providers\FirebirdToolsU.pas',
  FirebirdPromptsU in '..\providers\FirebirdPromptsU.pas',
  FirebirdResourcesU in '..\providers\FirebirdResourcesU.pas';
```
(Add the `sources/` Firebird units to the project search path; they are pulled in transitively.)

- [ ] **Step 2: Write the boundary check** — the core must not import MCP/DMVC

`tests/check_core_boundary.ps1`:
```powershell
$ErrorActionPreference = 'Stop'
$bad = Select-String -Path 'C:\DEV\mcp-firebird\sources\*.pas' -Pattern 'MVCFramework' -SimpleMatch
if ($bad) { $bad | ForEach-Object { Write-Host $_.Path ':' $_.Line }; throw 'Core unit imports MVCFramework — boundary violated' }
Write-Host 'Core boundary OK: no MVCFramework imports in sources/'
```

- [ ] **Step 3: Build the app and run the boundary check**

```powershell
pwsh tests/check_core_boundary.ps1
```
Expected: "Core boundary OK". Build `app/MCPFirebird.dproj` (Win64) — links cleanly with all providers.

- [ ] **Step 4: Smoke-test the running server via a hand-written initialize**

Start FB 5.0 + seed (Task 5 steps), point `app/bin/.env` at it (copy from `.env.example`), then:
```powershell
'{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"probe","version":"1"}}}' | .\app\bin\MCPFirebird.exe
```
Expected: a single JSON-RPC result line on stdout naming `mcp-firebird`. (Full coverage in Task 18.)

- [ ] **Step 5: Commit**

```bash
git add app/MCPFirebird.dpr tests/check_core_boundary.ps1
git commit -m "feat(app): register fb providers + enforce MCP-free core boundary"
```

---

## Task 18: Python MCP compliance suite (stdio)

**Files:**
- Create: `tests/test_mcp_firebird_stdio.py`
- Create: `tests/conftest.py`

- [ ] **Step 1: Write the stdio client + fixtures**

`tests/conftest.py`:
```python
import json, os, subprocess, pytest

EXE = os.environ.get("MCP_FB_EXE", r"C:\DEV\mcp-firebird\app\bin\MCPFirebird.exe")

class StdioClient:
    def __init__(self, proc): self.proc = proc; self._id = 0
    def call(self, method, params=None):
        self._id += 1
        msg = {"jsonrpc": "2.0", "id": self._id, "method": method, "params": params or {}}
        self.proc.stdin.write((json.dumps(msg) + "\n").encode()); self.proc.stdin.flush()
        line = self.proc.stdout.readline()
        return json.loads(line)

@pytest.fixture
def client():
    proc = subprocess.Popen([EXE], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    c = StdioClient(proc)
    c.call("initialize", {"protocolVersion": "2025-03-26", "capabilities": {},
                          "clientInfo": {"name": "pytest", "version": "1"}})
    yield c
    proc.stdin.close(); proc.terminate()
```

- [ ] **Step 2: Write the compliance tests**

`tests/test_mcp_firebird_stdio.py`:
```python
def test_initialize_reports_server_name(client):
    r = client.call("ping")
    assert "result" in r

def test_tools_list_contains_fb_tools(client):
    r = client.call("tools/list")
    names = {t["name"] for t in r["result"]["tools"]}
    for expected in {"fb_info", "fb_list_tables", "fb_describe_table",
                     "fb_analyze_query", "fb_suggest_indexes",
                     "fb_suggest_index_drops", "fb_evaluate_goal"}:
        assert expected in names

def test_fb_info_returns_engine_version(client):
    r = client.call("tools/call", {"name": "fb_info", "arguments": {}})
    text = r["result"]["content"][0]["text"]
    assert "engine_version" in text

def test_fb_analyze_query_flags_natural_scan(client):
    r = client.call("tools/call", {"name": "fb_analyze_query",
        "arguments": {"sql": "SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'"}})
    text = r["result"]["content"][0]["text"]
    assert "NATURAL" in text.upper()

def test_fb_evaluate_goal_no_natural_scan_not_met(client):
    r = client.call("tools/call", {"name": "fb_evaluate_goal",
        "arguments": {"goal_type": "query_no_natural_scan",
                      "target": "SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'",
                      "threshold": 0}})
    text = r["result"]["content"][0]["text"]
    assert '"met"' in text and ("false" in text.lower())

def test_optimization_goal_prompt_present(client):
    r = client.call("prompts/list")
    names = {p["name"] for p in r["result"]["prompts"]}
    assert "optimization_goal" in names
```

- [ ] **Step 3: Run the suite** (FB 5.0 running, seed created, `.env` pointing at it)

```powershell
pwsh tests/fbkit.ps1 -Action start -Version 5.0
pwsh tests/seed/make_seed.ps1 -Version 5.0
python -m pytest tests/test_mcp_firebird_stdio.py -v
pwsh tests/fbkit.ps1 -Action stop -Version 5.0
```
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add tests/test_mcp_firebird_stdio.py tests/conftest.py
git commit -m "test(mcp): Python stdio compliance suite for fb_* tools and prompts"
```

---

## Task 19: One-command runner + full version matrix

**Files:**
- Create: `tests/run_all.ps1`

- [ ] **Step 1: Write the orchestrator** — for each available version: start kit → seed → set core env → run core exe → stop kit; then build app + run Python once on 5.0

`tests/run_all.ps1`:
```powershell
$ErrorActionPreference = 'Stop'
$versions = @('2.5','3.0','4.0','5.0')
$coreExe  = 'C:\DEV\mcp-firebird\tests\coreproject\Win64\Debug\MCPFirebirdCoreTests.exe'
$db       = 'C:\DEV\mcp-firebird\tests\seed\TESTDB.FDB'
$failed   = $false

# Core suite across the whole version matrix
foreach ($v in $versions) {
  $dir = (Import-PowerShellDataFile "$PSScriptRoot\fbkit.versions.psd1")[$v].Dir
  if (-not (Test-Path "C:\DEV\mcp-firebird\fb_versions\$dir")) { Write-Host "SKIP FB $v (kit not present)"; continue }
  Write-Host "==== Core suite on FB $v ===="
  & "$PSScriptRoot\fbkit.ps1" -Action start -Version $v | Out-Null
  try {
    & "$PSScriptRoot\seed\make_seed.ps1" -Version $v | Out-Null
    $env:FBTEST_PORT       = (& "$PSScriptRoot\fbkit.ps1" -Action port   -Version $v)
    $env:FBTEST_CLIENTLIB  = (& "$PSScriptRoot\fbkit.ps1" -Action client -Version $v)
    $env:FBTEST_DB         = $db
    & $coreExe
    if ($LASTEXITCODE -ne 0) { $failed = $true; Write-Host "FB $v core tests FAILED" }
  } finally {
    & "$PSScriptRoot\fbkit.ps1" -Action stop -Version $v | Out-Null
  }
}

# MCP compliance once (on 5.0)
Write-Host "==== Python MCP compliance on FB 5.0 ===="
& "$PSScriptRoot\fbkit.ps1" -Action start -Version 5.0 | Out-Null
try {
  & "$PSScriptRoot\seed\make_seed.ps1" -Version 5.0 | Out-Null
  pwsh "$PSScriptRoot\check_core_boundary.ps1"
  python -m pytest "$PSScriptRoot\test_mcp_firebird_stdio.py" -v
  if ($LASTEXITCODE -ne 0) { $failed = $true }
} finally {
  & "$PSScriptRoot\fbkit.ps1" -Action stop -Version 5.0 | Out-Null
}

if ($failed) { throw 'One or more suites FAILED' } else { Write-Host 'ALL SUITES PASSED' }
```

- [ ] **Step 2: Run the full matrix**

```powershell
pwsh tests/run_all.ps1
```
Expected: core suite passes on every present version (capabilities differ but assertions hold), boundary check passes, Python suite passes, final line "ALL SUITES PASSED".

- [ ] **Step 3: Commit**

```bash
git add tests/run_all.ps1
git commit -m "test: one-command runner across the full Firebird version matrix"
```

---

## Task 20: README + Claude Desktop wiring

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write the README** (quick start, .env, tool list, Claude config, test command)

```markdown
# MCP Firebird

A Model Context Protocol server for Firebird (2.5–5.0), written in Delphi with the
official `fbclient` driver. Documents schemas, analyzes query plans, advises on
indexes, and drives goal-based optimization — read-only by default.

## Quick start
1. Build `app/MCPFirebird.dproj` (Win64) in Delphi. Search paths: `C:\DEV\mcp-server-delphi\sources`, DMVCFramework `sources`, this repo's `sources` + `providers`.
2. Copy `app/bin/.env.example` to `app/bin/.env` and set `firebird.*`.
3. Register with Claude Desktop (`%APPDATA%\Claude\claude_desktop_config.json`):
   ```json
   { "mcpServers": { "firebird": { "command": "C:\\DEV\\mcp-firebird\\app\\bin\\MCPFirebird.exe" } } }
   ```

## Tools (M1)
`fb_info`, `fb_list_tables`, `fb_describe_table`, `fb_generate_documentation`,
`fb_analyze_query`, `fb_suggest_indexes`, `fb_suggest_index_drops`, `fb_evaluate_goal`.

## Prompts
`optimization_goal` (goal-driven loop), `health_check`.

## Safety
Read-only by default. Write tools (M3) require `firebird.allow_ddl=true`.

## Tests
```
pwsh tests/run_all.ps1
```
Runs the DUnitX core suite across FB 2.5/3.0/4.0/5.0 zip-kits plus the Python MCP compliance suite.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: project README with quick start, tools, and test command"
```

---

## Task 21: Schema-audit detectors + known-problem fixtures (TDD)

> Adds four high-value, cheap detectors for the most common Firebird problems and the fixtures that prove them: **missing PRIMARY KEY**, **stale statistics**, **over-indexing**, and **external SORT** in a plan.

**Files:**
- Create: `tests/seed/problems.sql`
- Modify: `tests/seed/make_seed.ps1` (also load `problems.sql`)
- Create: `sources/Firebird.SchemaAudit.pas`
- Modify: `sources/Firebird.PlanAnalyzer.pas` (add `HasExternalSort`)
- Modify: `providers/FirebirdToolsU.pas` (surface external sort in `fb_analyze_query`; add `fb_audit_table` tool)
- Create: `tests/coreproject/Test.Firebird.SchemaAudit.pas`

- [ ] **Step 1: Add the problem fixtures** — `tests/seed/problems.sql` (cross-version, appended to the seed DB)

```sql
SET SQL DIALECT 3;
/* (6) Table with NO primary key */
CREATE TABLE NOPK_LOG (
  LOG_TS    TIMESTAMP,
  MESSAGE   VARCHAR(200)
);

/* (8) Over-indexed write-heavy table: 6 single-column indexes */
CREATE TABLE OVERIDX (
  ID    INTEGER NOT NULL PRIMARY KEY,
  A INTEGER, B INTEGER, C INTEGER, D INTEGER, E INTEGER, F INTEGER
);
CREATE INDEX IDX_OVERIDX_A ON OVERIDX (A);
CREATE INDEX IDX_OVERIDX_B ON OVERIDX (B);
CREATE INDEX IDX_OVERIDX_C ON OVERIDX (C);
CREATE INDEX IDX_OVERIDX_D ON OVERIDX (D);
CREATE INDEX IDX_OVERIDX_E ON OVERIDX (E);
CREATE INDEX IDX_OVERIDX_F ON OVERIDX (F);

/* (7) Stale statistics: index created on the EMPTY table, rows inserted afterwards,
       statistics never refreshed -> stored selectivity is wrong. */
CREATE TABLE STALE_T (
  ID   INTEGER NOT NULL PRIMARY KEY,
  CODE INTEGER
);
CREATE INDEX IDX_STALE_CODE ON STALE_T (CODE);   /* computed on 0 rows */
COMMIT;

SET TERM ^ ;
EXECUTE BLOCK AS DECLARE I INTEGER = 0; BEGIN
  WHILE (I < 4000) DO BEGIN
    INSERT INTO STALE_T (ID, CODE) VALUES (:I, :I);   /* now highly selective, but stats say otherwise */
    INSERT INTO OVERIDX (ID, A, B, C, D, E, F) VALUES (:I, MOD(:I,2), MOD(:I,3), :I, :I, :I, :I);
    I = I + 1;
  END
END^
SET TERM ; ^
COMMIT;
```

- [ ] **Step 2: Make the seed loader also run `problems.sql`** — in `tests/seed/make_seed.ps1`, after the `INPUT '$seed';` line, add a second input. Replace the here-string block with:

```powershell
$problems = Join-Path $PSScriptRoot 'seed\problems.sql'
@"
CREATE DATABASE '$db' USER 'SYSDBA' PASSWORD 'masterkey' DEFAULT CHARACTER SET UTF8;
INPUT '$seed';
INPUT '$problems';
"@ | & $isql -q
```

- [ ] **Step 3: Write the failing tests**

`tests/coreproject/Test.Firebird.SchemaAudit.pas`:
```pascal
unit Test.Firebird.SchemaAudit;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TSchemaAuditTests = class
  public
    [Test] procedure Flags_Table_Without_PrimaryKey;
    [Test] procedure Flags_OverIndexed_Table;
    [Test] procedure Flags_Stale_Statistics;
    [Test] procedure Detects_External_Sort_In_Plan;
  end;
implementation
uses System.SysUtils, Firebird.Connection, Firebird.Capabilities, Firebird.Advisory,
  Firebird.SchemaAudit, Firebird.PlanAnalyzer, TestFixtureU;

function Mentions(const Advs: TArray<TAdvisory>; const ANeedle: string): Boolean;
var X: TAdvisory;
begin
  Result := False;
  for X in Advs do
    if X.Finding.ToUpper.Contains(ANeedle.ToUpper) or X.SQLText.ToUpper.Contains(ANeedle.ToUpper) then Exit(True);
end;

procedure TSchemaAuditTests.Flags_Table_Without_PrimaryKey;
var Conn: TFirebirdConnection; A: TFirebirdSchemaAudit;
begin
  Conn := NewTestConnection;
  try
    A := TFirebirdSchemaAudit.Create(Conn);
    try Assert.IsTrue(Mentions(A.AuditTable('NOPK_LOG'), 'PRIMARY KEY'), 'missing PK flagged');
    finally A.Free; end;
  finally Conn.Free; end;
end;

procedure TSchemaAuditTests.Flags_OverIndexed_Table;
var Conn: TFirebirdConnection; A: TFirebirdSchemaAudit;
begin
  Conn := NewTestConnection;
  try
    A := TFirebirdSchemaAudit.Create(Conn);
    try Assert.IsTrue(Mentions(A.AuditTable('OVERIDX'), 'INDEX'), 'over-indexing flagged');
    finally A.Free; end;
  finally Conn.Free; end;
end;

procedure TSchemaAuditTests.Flags_Stale_Statistics;
var Conn: TFirebirdConnection; A: TFirebirdSchemaAudit;
begin
  Conn := NewTestConnection;
  try
    A := TFirebirdSchemaAudit.Create(Conn);
    try Assert.IsTrue(Mentions(A.AuditTable('STALE_T'), 'STATISTICS'), 'stale stats flagged with SET STATISTICS fix');
    finally A.Free; end;
  finally Conn.Free; end;
end;

procedure TSchemaAuditTests.Detects_External_Sort_In_Plan;
var Conn: TFirebirdConnection; PA: TFirebirdPlanAnalyzer; R: TPlanResult;
begin
  Conn := NewTestConnection;
  try
    PA := TFirebirdPlanAnalyzer.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try
      R := PA.Analyze('SELECT * FROM CUSTOMERS ORDER BY CITY');  // CITY not actively indexed -> SORT
      Assert.IsTrue(R.HasExternalSort, 'ORDER BY on non-indexed column -> external SORT in plan');
    finally PA.Free; end;
  finally Conn.Free; end;
end;
end.
```
Add the unit to the `.dpr` `uses`.

- [ ] **Step 4: Run to verify it fails** — `Firebird.SchemaAudit` not found; `HasExternalSort` undefined.

- [ ] **Step 5: Add `HasExternalSort` to `TPlanResult` and `Analyze`** (in `Firebird.PlanAnalyzer.pas`)

In the record add the field:
```pascal
    HasNaturalScan, HasExternalSort: Boolean;
```
At the end of `Analyze`, before assigning `NaturalTables`, add:
```pascal
  Result.HasExternalSort := Result.RawPlan.ToUpper.Contains('SORT');
```

- [ ] **Step 6: Implement `Firebird.SchemaAudit`**

`sources/Firebird.SchemaAudit.pas`:
```pascal
unit Firebird.SchemaAudit;
interface
uses Firebird.Connection, Firebird.Advisory;
type
  TFirebirdSchemaAudit = class
  private
    FConn: TFirebirdConnection;
    function ActualSelectivity(const ATable, AColumn: string): Double;
  public
    constructor Create(AConn: TFirebirdConnection);
    function AuditTable(const ATable: string): TArray<TAdvisory>;
  end;
implementation
uses System.SysUtils, System.Generics.Collections, Firebird.Introspection;

const OVER_INDEX_THRESHOLD = 5;   // user indexes beyond this = over-indexing (info)

constructor TFirebirdSchemaAudit.Create(AConn: TFirebirdConnection);
begin inherited Create; FConn := AConn; end;

function TFirebirdSchemaAudit.ActualSelectivity(const ATable, AColumn: string): Double;
var Distinct, Total: Int64;
begin
  Total    := StrToInt64Def(FConn.ScalarStr('SELECT COUNT(*) FROM ' + ATable), 0);
  Distinct := StrToInt64Def(FConn.ScalarStr(Format('SELECT COUNT(DISTINCT %s) FROM %s', [AColumn, ATable])), 0);
  if (Total = 0) or (Distinct = 0) then Exit(0);
  Result := 1.0 / Distinct;   // Firebird selectivity convention: 1/distinct
end;

function TFirebirdSchemaAudit.AuditTable(const ATable: string): TArray<TAdvisory>;
var Intro: TFirebirdIntrospection; PK: TArray<string>; Idx: TArray<TIndexInfo>;
    UserIdx: Integer; X: TIndexInfo; Actual: Double; Advs: TList<TAdvisory>;
begin
  Advs := TList<TAdvisory>.Create;
  Intro := TFirebirdIntrospection.Create(FConn);
  try
    // (6) Missing primary key
    PK := Intro.GetPrimaryKey(ATable);
    if Length(PK) = 0 then
      Advs.Add(TAdvisory.Make(
        Format('Table %s has no PRIMARY KEY. Rows cannot be addressed uniquely; replication, ' +
               'updates and joins all suffer, and there is no clustering anchor.', [ATable]),
        Format('ALTER TABLE %s ADD CONSTRAINT PK_%s PRIMARY KEY (/* choose a unique column */);', [ATable, ATable]),
        'fb_describe_table should then list a PRIMARY KEY constraint.',
        'critical'));

    Idx := Intro.GetIndexes(ATable);

    // (8) Over-indexing
    UserIdx := 0;
    for X in Idx do if not X.IsSystem then Inc(UserIdx);
    if UserIdx > OVER_INDEX_THRESHOLD then
      Advs.Add(TAdvisory.Make(
        Format('Table %s carries %d user indexes. Every INSERT/UPDATE/DELETE must maintain all of ' +
               'them; on a write-heavy table this is a major cost. Keep only indexes that queries use.', [ATable, UserIdx]),
        Format('-- Review with fb_suggest_index_drops %s and drop the unused ones.', [ATable]),
        'Re-run fb_audit_table after dropping; the count should fall.',
        'warning'));

    // (7) Stale statistics — stored selectivity far from the real one (single-column user indexes)
    for X in Idx do
      if (not X.IsSystem) and (Length(X.Columns) = 1) then
      begin
        Actual := ActualSelectivity(ATable, X.Columns[0]);
        if (Actual > 0) and (Abs(X.Selectivity - Actual) > (Actual * 0.5)) then
          Advs.Add(TAdvisory.Make(
            Format('Index %s has stale statistics: stored selectivity %.6f vs actual %.6f. ' +
                   'The optimizer may pick a bad plan from outdated numbers (common after bulk loads).',
                   [X.IndexName, X.Selectivity, Actual]),
            Format('SET STATISTICS INDEX %s;', [X.IndexName]),
            'Re-run fb_audit_table; stored and actual selectivity should match.',
            'warning'));
      end;

    Result := Advs.ToArray;
  finally
    Intro.Free; Advs.Free;
  end;
end;
end.
```

- [ ] **Step 7: Surface the new signals in the MCP layer** (in `providers/FirebirdToolsU.pas`)

In `FbAnalyzeQuery`, after the NATURAL-scan block, add:
```pascal
      if R.HasExternalSort then
        SB.AppendLine('⚠️ **External SORT** in the plan: the result is sorted without a usable index ' +
          '(ORDER BY / GROUP BY / DISTINCT). Consider an index on the sort columns.');
```
Add a new tool to the class declaration and implementation:
```pascal
    [MCPTool('fb_audit_table', 'Schema-health audit of a table: missing PK, over-indexing, stale statistics')]
    function FbAuditTable([MCPParam('Table name')] const table_name: string): TMCPToolResult;
```
```pascal
function TFirebirdTools.FbAuditTable(const table_name: string): TMCPToolResult;
var Conn: TFirebirdConnection; A: TFirebirdSchemaAudit;
begin
  Conn := NewConfiguredConnection;
  try
    A := TFirebirdSchemaAudit.Create(Conn);
    try Result := TMCPToolResult.Text(AdvisoriesToText(A.AuditTable(table_name.ToUpper),
      'No schema-health issues found on ' + table_name + '.'));
    finally A.Free; end;
  finally Conn.Free; end;
end;
```
Add `Firebird.SchemaAudit` to the implementation `uses`.

- [ ] **Step 8: Run to verify it passes** — 4 audit tests pass. Re-run `tests/test_mcp_firebird_stdio.py` after rebuilding the app and add `fb_audit_table` to the expected-tools set in `test_tools_list_contains_fb_tools`.

- [ ] **Step 9: Commit**

```bash
git add tests/seed/problems.sql tests/seed/make_seed.ps1 sources/Firebird.SchemaAudit.pas sources/Firebird.PlanAnalyzer.pas providers/FirebirdToolsU.pas tests/coreproject/Test.Firebird.SchemaAudit.pas tests/coreproject/MCPFirebirdCoreTests.dpr tests/test_mcp_firebird_stdio.py
git commit -m "feat(core): schema-audit detectors (missing PK, stale stats, over-index, external sort) + fixtures (TDD)"
```

---

## Task 22: Known-problem catalog + M2-pending fixtures (living backlog)

> Documents the full common-problem catalog and ships fixtures for the three problems whose **detection is deferred to M2** (non-sargable predicate, implicit conversion, oversized index key). Their tests are written but marked `[Ignore]` so the suite records them as known-not-yet-covered — no silent gap, ready to un-ignore in M2.

**Files:**
- Create: `docs/firebird-problem-catalog.md`
- Modify: `tests/seed/problems.sql` (add the three M2 fixtures)
- Create: `tests/coreproject/Test.Firebird.PendingDetectors.pas`

- [ ] **Step 1: Write the catalog doc** — `docs/firebird-problem-catalog.md`

```markdown
# Firebird common-problem catalog

Each row is a known Firebird problem, the fixture that provokes it, the tool that
detects it, and the milestone the detection lands in. Fixtures live in
`tests/seed/seed.sql` and `tests/seed/problems.sql`.

| # | Problem | Fixture object | Detected by | Milestone |
|---|---|---|---|---|
| 1 | NATURAL scan on filtered column | CUSTOMERS.CITY | fb_analyze_query | M1 |
| 2 | Duplicate of system FK index | IDX_ORDERS_CUSTOMER_DUP | fb_suggest_index_drops | M1 |
| 3 | Redundant left-prefix index | IDX_CUST_NAME | fb_suggest_index_drops | M1 |
| 4 | Inactive index | IDX_CUST_CITY | fb_suggest_index_drops | M1 |
| 5 | Low-selectivity index | IDX_CUST_STATUS | fb_suggest_index_drops | M1 |
| 6 | Missing PRIMARY KEY | NOPK_LOG | fb_audit_table | M1 |
| 7 | Stale statistics | IDX_STALE_CODE | fb_audit_table | M1 |
| 8 | Over-indexing | OVERIDX | fb_audit_table | M1 |
| 9 | External SORT (no usable index) | CUSTOMERS ORDER BY CITY | fb_analyze_query | M1 |
| 10 | Non-sargable predicate (LIKE '%x', <>, NOT IN, fn(col)) | NSARG_T | fb_analyze_query (heuristic) | **M2** |
| 11 | Implicit type conversion in WHERE | CONV_T.CODE (INT vs '5') | fb_analyze_query (heuristic) | **M2** |
| 12 | Oversized / near-limit index key | BIGKEY_T (VARCHAR(800)) | fb_audit_table (key-size check) | **M2** |
```

- [ ] **Step 2: Add the three M2 fixtures to `tests/seed/problems.sql`** (append)

```sql
/* (10) Non-sargable: query will use LIKE '%foo' / fn(col); table just needs data */
CREATE TABLE NSARG_T (ID INTEGER NOT NULL PRIMARY KEY, NAME VARCHAR(100));
CREATE INDEX IDX_NSARG_NAME ON NSARG_T (NAME);

/* (11) Implicit conversion: INTEGER column queried with a string literal */
CREATE TABLE CONV_T (ID INTEGER NOT NULL PRIMARY KEY, CODE INTEGER);
CREATE INDEX IDX_CONV_CODE ON CONV_T (CODE);

/* (12) Oversized index key: long VARCHAR indexed (key-size pressure on small page sizes) */
CREATE TABLE BIGKEY_T (ID INTEGER NOT NULL PRIMARY KEY, LABEL VARCHAR(800));
CREATE INDEX IDX_BIGKEY_LABEL ON BIGKEY_T (LABEL);
COMMIT;
```

- [ ] **Step 3: Write the pending-detector tests, marked `[Ignore]`**

`tests/coreproject/Test.Firebird.PendingDetectors.pas`:
```pascal
unit Test.Firebird.PendingDetectors;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TPendingDetectorTests = class
  public
    [Test][Ignore('M2: non-sargable predicate detection not implemented yet')]
    procedure Detects_NonSargable_LeadingWildcard;
    [Test][Ignore('M2: implicit conversion detection not implemented yet')]
    procedure Detects_ImplicitConversion;
    [Test][Ignore('M2: oversized index key check not implemented yet')]
    procedure Flags_Oversized_IndexKey;
  end;
implementation
procedure TPendingDetectorTests.Detects_NonSargable_LeadingWildcard; begin end;
procedure TPendingDetectorTests.Detects_ImplicitConversion; begin end;
procedure TPendingDetectorTests.Flags_Oversized_IndexKey; begin end;
end.
```
Add the unit to the `.dpr` `uses`. These appear in the runner output as **ignored** (visible backlog), not as passes.

- [ ] **Step 4: Run the suite and confirm the 3 are reported Ignored, everything else passes**

```powershell
.\tests\coreproject\Win64\Debug\MCPFirebirdCoreTests.exe
```
Expected: all active tests pass; 3 tests reported as Ignored with their M2 reason.

- [ ] **Step 5: Commit**

```bash
git add docs/firebird-problem-catalog.md tests/seed/problems.sql tests/coreproject/Test.Firebird.PendingDetectors.pas tests/coreproject/MCPFirebirdCoreTests.dpr
git commit -m "test+docs: known-problem catalog + M2-pending fixtures (ignored tests as backlog)"
```

---

## Self-review notes (addressed)

- **Spec coverage:** connection (T5), capabilities/version-matrix (T6, T19), introspection+docs (T7–T9), PLAN analysis (T10–T11), index advisor suggest/drop (T12–T13), schema-audit detectors + known-problem catalog (T21–T22), `fb_evaluate_goal`+`optimization_goal` (T14, T16), stdio MCP server (T1, T17), 4-layer tests (core T4–T14/T21, mcp/python T18, matrix T19, boundary T17). M2/M3 tools (`fb_whats_running`, trace, write tools, `query_max_reads`/`oat_gap` goals, and the 3 deferred detectors in T22) are intentionally **out of M1** and called out where deferred.
- **Known-problem coverage:** 9 of the 12 most common Firebird problems are detected and asserted in M1 (NATURAL scan, duplicate/redundant/inactive/low-selectivity indexes, missing PK, stale stats, over-indexing, external sort); the remaining 3 (non-sargable, implicit conversion, oversized key) ship as fixtures with `[Ignore]`d tests so the backlog is visible, not hidden.
- **Type consistency:** record/method names match across tasks (`TFirebirdCapabilities.Detect`/`Parse`, `TFirebirdIntrospection.GetIndexes`, `TPlanResult.HasNaturalScan`, `TAdvisory.Make`, `TGoalResult.Met`, `SuggestForQuery`/`SuggestDropsForTable`, `Evaluate`).
- **Known verification points** (flagged inline, not placeholders): the access-plan retrieval mechanism (resolved by the Task 10 spike before Task 11), and the exact `TMCPResourceResult` factory name (verify against the library in Task 16). Both have a concrete default and a one-line fallback.
```
