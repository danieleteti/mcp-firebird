# MCP Firebird

A [Model Context Protocol](https://modelcontextprotocol.io) server for **Firebird 2.5 – 5.0**,
written in Delphi with the official `fbclient` driver. It lets an AI assistant document
schemas, analyze query plans, advise on indexes (which to add **and** which to drop), audit
schema health, and drive goal-based optimization — **read-only by default**.

- **Transport:** stdio (JSON-RPC 2.0, MCP protocol `2025-03-26`)
- **Server identity:** `mcp-firebird` v`0.1.0`
- **Engine support:** Firebird 2.5, 3.0, 4.0, 5.0 (capability-detected at runtime)
- **Safety:** read-only analysis; DDL/write is gated behind `firebird.allow_ddl=true`

---

## Table of contents

1. [What it does](#what-it-does)
2. [Prerequisites](#prerequisites)
3. [Build](#build)
4. [Configuration (`.env`)](#configuration-env)
5. [Run & verify manually](#run--verify-manually)
6. [Connect it to an MCP client](#connect-it-to-an-mcp-client) — Claude Desktop · Claude Code · Gemini CLI · OpenCode · Cursor / VS Code · generic
7. [Using it from Claude](#using-it-from-claude) — worked examples
8. [Tool reference](#tool-reference)
9. [Testing the project](#testing-the-project)
10. [Troubleshooting](#troubleshooting)

---

## What it does

### Tools (9)

| Tool | Arguments | Purpose |
|---|---|---|
| `fb_info` | — | Engine version + detected capabilities (JSON) |
| `fb_list_tables` | — | List user tables |
| `fb_describe_table` | `table_name` | Columns, PK, indexes, foreign keys |
| `fb_generate_documentation` | `table_name?` | Markdown docs for one table or the whole database |
| `fb_analyze_query` | `sql` | Access-plan analysis: NATURAL-scan + external-SORT detection |
| `fb_suggest_indexes` | `sql` | New-index suggestions from NATURAL-scanned predicates (ready-to-run DDL) |
| `fb_suggest_index_drops` | `table_name` | Flags duplicate / redundant-prefix / inactive / low-selectivity indexes |
| `fb_audit_table` | `table_name` | Schema-health audit: missing PK, over-indexing, stale statistics |
| `fb_evaluate_goal` | `goal_type`, `target`, `threshold` | Deterministic goal check (drives the optimization loop) |

Every advisory comes with a **Finding**, ready-to-run **SQL**, and a **Verify** step.

### Prompts (2)

- **`optimization_goal`** — the goal-driven loop: set an objective, the assistant iterates the
  `fb_*` tools and re-checks `fb_evaluate_goal` until it reports `met: true` (with a
  max-iterations / no-progress safety stop).
- **`health_check`** — guided whole-database health review.

### Resources (1)

- **`firebird://schema`** — the live database schema as a single resource.

---

## Prerequisites

- **Windows x64** (the server is a native Win64 console app).
- **Delphi 12 Athens** (RAD Studio 23.0) to build, with **FireDAC**. Earlier Delphi 11+ should work.
- **DMVCFramework** and the **`mcp-server-delphi`** library checked out locally (search paths below).
- A **Firebird client library** (`fbclient.dll`) matching — or newer than — your target server.
  A 5.0 `fbclient.dll` connects fine to 2.5–5.0 servers.
- A reachable **Firebird database** to point at.

> For running the **test matrix** you also need the Firebird zip-kits under `fb_versions/` and
> Python 3 with `pytest`. See [Testing the project](#testing-the-project).

---

## Build

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

## Configuration (`.env`)

By default the server reads its configuration from a **`.env` file in the same folder as the
executable** (`bin\.env`). Copy the template and edit it:

```powershell
Copy-Item bin\.env.example bin\.env
```

### Choosing a different config folder: `--env <dir>`

Pass `--env <dir>` to read the `.env` from another folder instead of the executable's:

```powershell
MCPFirebird.exe --env C:\configs\prod        # reads C:\configs\prod\.env
MCPFirebird.exe --env=..\shared              # relative paths resolve against the working dir
```

The argument is a **directory** (the folder that contains the `.env`), not the file itself.
Without `--env`, the executable's own folder is used. This lets one build serve several
databases — give each MCP client a different `--env` folder. Logs are written to a `logs\`
subfolder next to the executable.

| Key | Default | Meaning |
|---|---|---|
| `firebird.host` | `localhost` | Server host (TCP). Use the real host/IP for remote DBs |
| `firebird.port` | `3050` | Server port |
| `firebird.database` | *(empty)* | Full path (or alias) of the database on the server |
| `firebird.user` | `SYSDBA` | Login user |
| `firebird.password` | `masterkey` | Login password |
| `firebird.charset` | `UTF8` | Connection character set |
| `firebird.client_lib` | *(empty)* | Full path to `fbclient.dll` to load |
| `firebird.allow_ddl` | `false` | **Safety gate** for write/DDL tools (M1 tools are read-only) |
| `logger.config.file` | `loggerpro.stdio.json` | File-logger config (logs go to file only; stdout stays pure JSON-RPC) |

Example `bin\.env`:

```ini
firebird.host=localhost
firebird.port=3050
firebird.database=C:\data\MYAPP.FDB
firebird.user=SYSDBA
firebird.password=masterkey
firebird.charset=UTF8
firebird.client_lib=C:\Program Files\Firebird\Firebird_5_0\fbclient.dll
firebird.allow_ddl=false
logger.config.file=loggerpro.stdio.json
```

> **Why a file and not client-passed env vars?** The dotEnv strategy is *file-then-env*: the
> `.env` file takes priority, OS environment variables are the fallback. Configuring via
> `bin\.env` works identically across every MCP client because it is read relative to the
> `.exe`, regardless of the client's working directory. Keep this file out of version control
> (it is already `.gitignore`d) — it holds credentials.

---

## Run & verify manually

The server speaks JSON-RPC over stdin/stdout. You can smoke-test it without any MCP client by
piping framed JSON lines into it. From PowerShell:

```powershell
$msgs = @(
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"manual","version":"1"}}}'
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"fb_info","arguments":{}}}'
) -join "`n"
$msgs | & .\bin\MCPFirebird.exe
```

Expected: an `initialize` result naming `mcp-firebird`, a `tools/list` with the 9 `fb_*` tools,
and `fb_info` returning the live `engine_version`. (Logs appear under `bin\logs\`; stdout is
pure JSON-RPC.)

---

## Connect it to an MCP client

All clients launch the **same command** — the absolute path to `MCPFirebird.exe` — and the server
picks up its database connection from `bin\.env`. Adjust the path to where you built it.

### Claude Desktop

Edit `%APPDATA%\Claude\claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "firebird": {
      "command": "C:\\DEV\\mcp-firebird\\app\\bin\\MCPFirebird.exe"
    }
  }
}
```

Restart Claude Desktop. The `fb_*` tools, the `optimization_goal` / `health_check` prompts, and
the `firebird://schema` resource appear in the client.

### Claude Code (CLI)

Add it with one command (local stdio server):

```powershell
claude mcp add firebird -- "C:\DEV\mcp-firebird\bin\MCPFirebird.exe"
```

Or commit a project-scoped `.mcp.json` at the repo root so teammates inherit it:

```json
{
  "mcpServers": {
    "firebird": {
      "command": "C:\\DEV\\mcp-firebird\\app\\bin\\MCPFirebird.exe",
      "args": [],
      "env": {}
    }
  }
}
```

Verify with `claude mcp list` (or `/mcp` inside a session).

### Gemini CLI

Edit `~/.gemini/settings.json` (or a project-level `.gemini/settings.json`):

```json
{
  "mcpServers": {
    "firebird": {
      "command": "C:\\DEV\\mcp-firebird\\app\\bin\\MCPFirebird.exe",
      "args": [],
      "cwd": "C:\\DEV\\mcp-firebird\\app\\bin",
      "timeout": 30000,
      "trust": false
    }
  }
}
```

Then `/mcp` inside Gemini CLI lists the server and its tools. Setting `cwd` to the `bin` folder
keeps the `logs\` directory tidy (the `.env` is found via the exe path regardless).

### OpenCode

Edit `opencode.json` (global `~/.config/opencode/opencode.json` or per-project) and register a
**local** MCP server — `command` is an argv array:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "firebird": {
      "type": "local",
      "command": ["C:\\DEV\\mcp-firebird\\app\\bin\\MCPFirebird.exe"],
      "enabled": true
    }
  }
}
```

### Cursor / VS Code

Cursor reads `.cursor/mcp.json`; VS Code (and MCP-aware extensions) read `.vscode/mcp.json`.
Both use the same shape:

```json
{
  "mcpServers": {
    "firebird": {
      "command": "C:\\DEV\\mcp-firebird\\app\\bin\\MCPFirebird.exe"
    }
  }
}
```

### Any other MCP client

The server is a standard **stdio** MCP server. Whatever the client's config format, give it:

- **command:** `C:\DEV\mcp-firebird\bin\MCPFirebird.exe`
- **args:** *(none)* — or `["--env", "C:\\configs\\prod"]` to use a `.env` from another folder
- **transport:** stdio
- **env:** *(none required)* — connection comes from the `.env`

> **Tip:** to point different clients at different databases, give each one a different
> `--env <dir>` (a folder with its own `.env`) — no need to copy the whole `bin\` folder. For
> example, in a Claude Code `.mcp.json`:
> ```json
> { "mcpServers": { "firebird": {
>     "command": "C:\\DEV\\mcp-firebird\\bin\\MCPFirebird.exe",
>     "args": ["--env", "C:\\configs\\prod"] } } }
> ```

---

## Using it from Claude

Once the server is registered, you talk to Claude in plain language — it picks the right `fb_*`
tool, runs it against your configured database, and turns the result into ready-to-run SQL. The
exchanges below assume the seeded demo database; swap in your own table and column names.

> In **Claude Desktop** the tools appear automatically and the two prompts show up as commands
> (the 🔌 / "+" menu). In **Claude Code** run `/mcp` to inspect the server, and the prompts are
> available as slash commands. You can always nudge it explicitly: *"use the firebird tools"*.

### 1. Get your bearings

> **You:** What Firebird version am I connected to, and which features are available?

Claude calls **`fb_info`** and reports the engine version, dialect, charset and detected
capabilities (MON$ tables, explained plans, BOOLEAN, INT128, timezones, parallel workers).

> **You:** List the tables in the database.

→ **`fb_list_tables`** → `CUSTOMERS`, `ORDERS`, `NOPK_LOG`, `OVERIDX`, `STALE_T`, …

### 2. Document a schema

> **You:** Document the CUSTOMERS table.

→ **`fb_describe_table`** → columns, the `CUSTOMER_ID` primary key, indexes and foreign keys.

> **You:** Generate full Markdown documentation for the whole database and put it in a file.

→ **`fb_generate_documentation`** (no table = whole DB). Claude returns the Markdown; ask it to
save the text to `docs/schema.md` if you want it on disk.

### 3. Diagnose a slow query and fix it

> **You:** This query is slow, why?
> `SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'`

→ **`fb_analyze_query`** → *"⚠️ NATURAL scan on CUSTOMERS — the filtered column `CITY` is not
usefully indexed."*

> **You:** Suggest an index that fixes it.

→ **`fb_suggest_indexes`** → a ready-to-run statement plus how to verify:

```sql
CREATE INDEX IDX_CUSTOMERS_CITY ON CUSTOMERS (CITY);
-- Verify: re-run fb_analyze_query; the NATURAL scan on CUSTOMERS should be gone.
```

> **You:** And this one? `SELECT * FROM CUSTOMERS ORDER BY CITY`

→ **`fb_analyze_query`** flags an **external SORT** (no usable index for the ordering).

### 4. Clean up redundant indexes

> **You:** Which indexes on ORDERS can I safely drop?

→ **`fb_suggest_index_drops`** → flags `IDX_ORDERS_CUSTOMER_DUP` as a duplicate of the
system foreign-key index, with the `DROP INDEX` statement and a verify step.

> **You:** Do the same for CUSTOMERS.

→ flags the redundant left-prefix (`IDX_CUST_NAME`), the inactive index (`IDX_CUST_CITY`) and
the low-selectivity index (`IDX_CUST_STATUS`).

### 5. Audit schema health

> **You:** Audit the NOPK_LOG table.

→ **`fb_audit_table`** → *"🛑 critical — Table NOPK_LOG has no PRIMARY KEY …"* with the
`ALTER TABLE … ADD CONSTRAINT` fix. On `OVERIDX` it reports over-indexing; on `STALE_T` it
reports stale statistics with the `SET STATISTICS INDEX …` fix.

> **You:** Run a full health check on the database.

→ Claude uses the **`health_check`** prompt: `fb_info` → `fb_list_tables` → `fb_suggest_index_drops`
per table → a single summary grouped by table with all the ready-to-run SQL.

### 6. Goal-driven optimization (iterate until met)

The **`optimization_goal`** prompt makes Claude loop: measure → suggest → re-measure, stopping as
soon as the goal is met (or it can't improve).

> **You:** Use the optimization_goal prompt — keep optimizing until this query no longer does a
> natural scan:
> `SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'`

Claude:
1. Calls **`fb_evaluate_goal`** (`goal_type=query_no_natural_scan`) → `met: false` (baseline).
2. Calls `fb_analyze_query` + `fb_suggest_indexes`, presents `CREATE INDEX IDX_CUSTOMERS_CITY …`.
3. You run the SQL (writes are off by default — see [Safety](#safety--compatibility)).
4. Calls `fb_evaluate_goal` again → `met: true`, and stops with the result.

You can also state the goal numerically, e.g. *"get this query under 50 ms"*
(`goal_type=query_time_ms`, `threshold=50`).

---

## Tool reference

A few call examples (MCP `tools/call` `arguments`):

```jsonc
// Describe a table
{ "name": "fb_describe_table", "arguments": { "table_name": "CUSTOMERS" } }

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

`fb_evaluate_goal` `goal_type` values supported in M1: `query_no_natural_scan`,
`query_time_ms`, `no_redundant_indexes`. See
[`docs/firebird-problem-catalog.md`](docs/firebird-problem-catalog.md) for every problem the
tools detect, the fixture that provokes it, and the milestone it lands in.

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

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| Client shows the server but **no tools** | `bin\.env` missing or DB unreachable — the server starts but tools fail on connect. Test with the [manual smoke test](#run--verify-manually). |
| `Your user name and password are not defined` (SQLSTATE 28000) | Wrong credentials, or a zip-kit without `SYSDBA` — see the one-time init above. |
| Analysis tools return empty / no NATURAL scan on a **remote** DB | Ensure `firebird.host` is the real host (the plan analyzer uses the configured host). |
| `fbclient.dll` not found / wrong bitness | Set `firebird.client_lib` to a **Win64** `fbclient.dll`; a 5.0 client works against 2.5–5.0. |
| stdout has non-JSON noise | Logging must go to file only — keep `logger.config.file=loggerpro.stdio.json`. |
| Port 3050 already in use by another Firebird | Use a distinct port (the test harness puts FB 2.5 on **3070** for this reason). |

---

## Safety & compatibility

- **Read-only by default.** Write/DDL tools (planned for M3) require `firebird.allow_ddl=true`.
- **Cross-version.** Capability detection adapts feature use (MON$ tables, explained plans,
  BOOLEAN, INT128, timezones, parallel workers) to the connected engine; validated on FB
  2.5 / 3.0 / 4.0 / 5.0.
- **Single configured database** per server instance (run multiple instances for multiple DBs).
