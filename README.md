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

A [Model Context Protocol](https://modelcontextprotocol.io) server for **Firebird 2.5 – 5.0**,
written in Delphi with the official `fbclient` driver. It lets an AI assistant document
schemas, analyze query plans, advise on indexes (which to add **and** which to drop), audit
schema health, and drive goal-based optimization — **read-only by default**.

> Built with **[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi)** — this
> server is a complete, real-world example of what you can build with the framework.

- **Transport:** stdio (JSON-RPC 2.0, MCP protocol `2025-03-26`)
- **Server identity:** `mcp-firebird` v`0.1.0`
- **Engine support:** Firebird 2.5, 3.0, 4.0, 5.0 (capability-detected at runtime)
- **Safety:** read-only analysis; no tool runs DDL or write SQL
- **Licence:** source-available, **not open source** — see [Editions & licensing](#editions--licensing)

---

## Table of contents

1. [Editions & licensing](#editions--licensing)
2. [What it does](#what-it-does)
3. [How it uses mcp-server-delphi](#how-it-uses-mcp-server-delphi)
4. [Prerequisites](#prerequisites)
5. [Build](#build)
6. [Configuration (`.env`)](#configuration-env)
7. [Run & verify manually](#run--verify-manually)
8. [Connect it to an MCP client](#connect-it-to-an-mcp-client) — Claude Desktop · Claude Code · Gemini CLI · OpenCode · Cursor / VS Code · generic
9. [Using it from Claude](#using-it-from-claude) — worked examples
10. [Tool reference](#tool-reference)
11. [Testing the project](#testing-the-project)
12. [Troubleshooting](#troubleshooting)

---

## Editions & licensing

Short version: **if you are using it on your own databases, it is free — and it stays free.**
No trial, no expiry, no licence key, no seat count, no limit on how many tables or databases
you point it at. Install it, use it in production, use it every day. Nothing phones home.

The one thing you cannot do is hand it to somebody else.

MCP Firebird is **source-available, not open source** as the Open Source Initiative defines the
term. Saying that plainly matters more than a badge: from **v0.2.0** it is licensed under the
[PolyForm Internal Use License 1.0.0](LICENSE). Versions up to and including **v0.1.0 were
released under Apache-2.0 and remain so** for everyone who received them — a licence already
granted cannot be revoked, and this project does not pretend otherwise.

### What you may do, free of charge

- Run it against any database you like — yours, your employer's, your client's. Development,
  staging, production, all of them.
- Run it at any scale. A hundred tables or ten thousand; one database or fifty.
- **Use it in your consulting practice.** Diagnose, tune, audit and support your clients'
  Firebird databases with it, and charge them for your time. It is your tool; keep it.
- Read the source. All of it. Learn from it, and use what you learn.
- Modify it. Fix a bug, add a detector, change a message. Run your modified build.
- Use it in a company of any size, commercial or not, for-profit or not, with no fee and no
  registration.

### What requires a licence

One idea, expressed three ways: **letting the software out of your hands.**

- **Redistributing it.** Publishing a fork, uploading a build, putting it on a CD, sending the
  binary to a customer, leaving it installed on a client's server when the engagement ends.
- **Embedding it in a product you sell.** Shipping it inside your ERP, your installer, your
  Docker image, your appliance — in source or binary form, modified or not.
- **Offering it as a service.** Standing it up behind an API or a hosted agent that people
  outside your organisation can reach.

Where the software runs, and whose database it examines, is your business. Where copies of it end
up is ours.

If your case is one of these, the licence exists and it is not expensive relative to what you are
building with it. Write to **d.teti@bittime.it**.

### When you need to buy a licence — worked cases

| Your situation | Licence needed? |
|---|---|
| Your DBA runs it against the company's production Firebird every morning | **No.** |
| Your team of forty developers each run it locally | **No.** No seat count, no registration. |
| You are a consultant, and you run it from your laptop against your client's database | **No.** It is your tool and it stays your tool. Charge them what you like. |
| Same, but you are sitting at the client's desk, running it on their server | **No.** Take it with you when you leave. |
| You leave a copy of it installed on your client's server when you go | **Yes.** The software left your hands. |
| You are a hosting provider, and you run it against the databases you host | **No.** |
| ...and you give your customers a button that runs it for them | **Yes.** That is offering it as a service. |
| You ship it inside your Delphi ERP so your customers get "AI database tuning" | **Yes.** Embedding in a product you supply. |
| You publish a fork on GitHub with your improvements | **Yes.** Talk to us first — we would rather merge it. |
| You are writing a blog post, a talk, or a university course about it | **No.** Read it, quote it, teach it. |
| You are on `v0.1.0`, which you obtained under Apache-2.0 | **No.** That version stays Apache-2.0 for you forever. |

The rule behind the table, if you would rather reason than look things up: **ask where the
software ends up, never what you did with it.** As long as every copy of MCP Firebird stays in
your hands, you owe nothing — not for the scale you run it at, not for the money it makes you,
not for whose database you point it at. The moment a copy leaves, we should talk.

### What you get in each edition

The line is simple: **whatever the database knows about itself is free; whatever only its
host machine knows is paid.** Everything in the free edition talks to Firebird over
FireDAC — it never reads a file on the server.

| | Free | Enterprise |
|---|---|---|
| Schema, docs, plans, index advice, schema audit | ✅ | ✅ |
| Transaction & sweep health (`MON$`) | ✅ | ✅ |
| Apply suggested DDL (opt-in, `firebird.allow_ddl`) | ✅ | ✅ |
| `firebird.conf` / `databases.conf` deep tuning | — | ✅ |
| Database header analysis (page size, sweep interval, forced writes) | — | ✅ |
| `firebird.log` parsing (errors, sweeps, bugchecks) | — | ✅ |
| Trace API capture — real workload, real hot queries | — | ✅ |
| Host sizing (RAM vs page buffers, CPU vs parallel workers) | — | ✅ |

The Enterprise tools appear in `tools/list` in this edition too, and tell you so when
called. **Enterprise, commercial licences, and support subscriptions:** d.teti@bittime.it

---

## What it does

### Tools (9 free, plus 5 Enterprise announced in `tools/list`)

| Tool | Arguments | Purpose |
|---|---|---|
| `fb_info` | — | Engine version + detected capabilities (JSON) |
| `fb_list_tables` | — | List user tables |
| `fb_generate_documentation` | `table_name?` | Markdown docs — columns, PK, indexes — for one table, or the whole database |
| `fb_analyze_query` | `sql` | Access-plan analysis: NATURAL-scan + external-SORT detection |
| `fb_suggest_indexes` | `sql` | New-index suggestions from NATURAL-scanned predicates (ready-to-run DDL) |
| `fb_suggest_index_drops` | `table_name` | Flags duplicate / redundant-prefix / inactive / low-selectivity indexes |
| `fb_audit_table` | `table_name` | Schema-health audit: missing PK, over-indexing, stale statistics |
| `fb_evaluate_goal` | `goal_type`, `target`, `threshold` | Deterministic goal check (drives the optimization loop) |
| `fb_monitor_transactions` | `stale_minutes?` | Transaction/sweep health: OIT/OAT/Next gap, blocking long-running transactions (with their last SQL statement) |

Every advisory comes with a **Finding**, ready-to-run **SQL**, and a **Verify** step.

### Prompts (2)

- **`optimization_goal`** — the goal-driven loop: set an objective, the assistant iterates the
  `fb_*` tools and re-checks `fb_evaluate_goal` until it reports `met: true` (with a
  max-iterations / no-progress safety stop).
- **`health_check`** — guided whole-database health review.

### Resources (1)

- **`firebird://schema`** — the live database schema as a single resource.

---

## How it uses mcp-server-delphi

Every tool is a plain Delphi method decorated with attributes from
[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi). The framework turns the
class into an MCP tool provider, generates the JSON-RPC schema from the attributes, and wires it
to the stdio transport — no protocol code in this repo. From `providers/FirebirdToolsU.pas`:

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

---

## Prerequisites

- **Windows x64** (the server is a native Win64 console app).
- **Delphi 13 Athens** (RAD Studio 37.0) to build, with **FireDAC**.
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

By default the `.env` is read from the executable's own folder. Pass **`--env <dir>`** to read it
from another folder instead — the argument is a **directory** (the folder that *contains* the
`.env`), not the file itself:

```powershell
MCPFirebird.exe --env C:\configs\prod      # reads C:\configs\prod\.env
MCPFirebird.exe --env=C:\configs\prod      # the --env=<dir> form also works
MCPFirebird.exe --env ..\shared            # relative paths resolve against the working directory
MCPFirebird.exe                            # no argument -> reads <exe folder>\.env
MCPFirebird.exe --env C:\configs\prod\.env # WRONG -> stops with an error (see below)
```

> **`--env` is a folder, never the `.env` file.** If you point it at the file (e.g.
> `...\prod\.env`) the server refuses to start and prints the fix on stderr — which MCP clients
> surface in their server logs — instead of silently starting with an empty config:
>
> ```
> MCPFirebird: --env must point at the FOLDER that contains the .env file, not at the file itself.
>   got:      C:\configs\prod\.env
>   use this: C:\configs\prod
> ```

**How the argument reaches the server.** MCP clients don't go through a shell — they spawn the
executable directly with a `command` plus an `args` **array**, where each array element becomes one
separate argument. So there is no shell quoting to worry about (paths with spaces are fine), and you
write the directory as its own array element. Two equivalent forms:

| Form | `args` value |
|---|---|
| separate | `["--env", "C:\\configs\\prod"]` |
| joined | `["--env=C:\\configs\\prod"]` |

**Path notes (Windows):** in JSON, backslashes must be **doubled** (`"C:\\configs\\prod"`) — or use
forward slashes, which Windows accepts and don't need escaping (`"C:/configs/prod"`). Prefer an
**absolute** path in MCP clients: the working directory they launch with is unpredictable, so
relative paths are unreliable there. Every startup logs the resolved folder to
`bin\logs\MCPFirebird.NN.mcp.log`:

```
Boot: .env directory "C:\configs\prod" (.env exists=True)
```

> **Note:** logs are always written to a `logs\` subfolder next to the **executable** (`bin\logs\`),
> regardless of `--env`.

#### Passing `--env` from each MCP client

**Claude Desktop** (`%APPDATA%\Claude\claude_desktop_config.json`), **Claude Code** (`.mcp.json`),
**Cursor** (`.cursor/mcp.json`) and **VS Code** (`.vscode/mcp.json`) all use the same shape — a
`command` plus an `args` array:

```json
{
  "mcpServers": {
    "firebird": {
      "command": "C:\\DEV\\mcp-firebird\\bin\\MCPFirebird.exe",
      "args": ["--env", "C:\\configs\\prod"]
    }
  }
}
```

Claude Code can also add it from the CLI:

```powershell
claude mcp add firebird -- "C:\DEV\mcp-firebird\bin\MCPFirebird.exe" --env "C:\configs\prod"
```

**Gemini CLI** (`~/.gemini/settings.json`) — same `mcpServers` shape:

```json
{
  "mcpServers": {
    "firebird": {
      "command": "C:\\DEV\\mcp-firebird\\bin\\MCPFirebird.exe",
      "args": ["--env", "C:\\configs\\prod"]
    }
  }
}
```

**OpenCode** (`opencode.json`) — note the difference: `command` is a **single array** that already
includes the arguments (there is no separate `args` field):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "firebird": {
      "type": "local",
      "command": ["C:\\DEV\\mcp-firebird\\bin\\MCPFirebird.exe", "--env", "C:\\configs\\prod"],
      "enabled": true
    }
  }
}
```

#### Serving several databases from one build

Register the **same executable** more than once with different `--env` folders — each folder holds
its own `.env`:

```json
{
  "mcpServers": {
    "firebird-prod": {
      "command": "C:\\DEV\\mcp-firebird\\bin\\MCPFirebird.exe",
      "args": ["--env", "C:\\configs\\prod"]
    },
    "firebird-test": {
      "command": "C:\\DEV\\mcp-firebird\\bin\\MCPFirebird.exe",
      "args": ["--env", "C:\\configs\\test"]
    }
  }
}
```

```
C:\configs\prod\.env      <- production host/port/database
C:\configs\test\.env      <- test host/port/database
```

The client then shows two independent servers (`firebird-prod`, `firebird-test`), each connected to
its own database.

| Key | Default | Meaning |
|---|---|---|
| `firebird.host` | `localhost` | Server host (TCP). Use the real host/IP for remote DBs |
| `firebird.port` | `3050` | Server port |
| `firebird.database` | *(empty)* | Full path (or alias) of the database on the server |
| `firebird.user` | `SYSDBA` | Login user |
| `firebird.password` | `masterkey` | Login password |
| `firebird.charset` | `UTF8` | Connection character set |
| `firebird.client_lib` | *(empty)* | Full path to `fbclient.dll` to load |
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

Expected: an `initialize` result naming `mcp-firebird`, a `tools/list` with the 10 `fb_*` tools,
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

→ **`fb_generate_documentation`** → columns, the `CUSTOMER_ID` primary key and the indexes.

> **You:** Generate full Markdown documentation for the whole database and put it in a file.

→ **`fb_generate_documentation`** again (no table = whole DB). Claude returns the Markdown; ask it to
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

## Worked session: optimizing a query on `employee.fdb`

A full round-trip against the stock **`employee`** sample database that ships with Firebird
(`examples/empbuild/employee.fdb`). The outputs below are verbatim tool results.

> **You:** Analyze this Firebird query and suggest improvements:
> ```sql
> SELECT emp_no, first_name, last_name, salary
> FROM employee
> WHERE salary > 60000
> ```

**1. Baseline — `fb_analyze_query`** returns (engine `3.0.12`):

```
PLAN (EMPLOYEE NATURAL)
```
> NATURAL scan on: EMPLOYEE. Run `fb_suggest_indexes` on this query for ready-to-run DDL.

`NATURAL` means Firebird reads **every** row of `EMPLOYEE` and throws away those with
`salary <= 60000` — there is no index on `SALARY` to seek with.

**2. Confirm the problem — `fb_evaluate_goal` (`goal_type=query_no_natural_scan`):**

```json
{ "goal_type": "query_no_natural_scan", "measured": 1.0, "met": false,
  "iteration_hint": "plan: PLAN (EMPLOYEE NATURAL)", "engine_version": "3.0.12" }
```

**3. Get the fix — `fb_suggest_indexes`:**

```sql
CREATE INDEX IDX_EMPLOYEE_SALARY ON EMPLOYEE (salary);
```
> **Verify:** re-run `fb_analyze_query`; the plan should use `IDX_EMPLOYEE_SALARY` and no longer show
> `EMPLOYEE NATURAL`. Then run `SET STATISTICS INDEX IDX_EMPLOYEE_SALARY;` to refresh selectivity.

**4. Apply it** (the server is read-only — run the DDL yourself), then **re-analyze**: the plan becomes `PLAN (EMPLOYEE INDEX (IDX_EMPLOYEE_SALARY))` and
`fb_evaluate_goal` returns `met: true`.

**When *not* to add the index.** The win comes from `salary > 60000` being **selective** (few rows).
If the predicate matched most of the table (e.g. `salary > 0`), the NATURAL scan is actually the
cheaper plan and the index would just add write overhead — not every NATURAL scan is a bug.

---

## Tool reference

A few call examples (MCP `tools/call` `arguments`):

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

- **Read-only.** No tool runs DDL or write SQL; write tools are planned for M3 and will ship
  behind an explicit opt-in setting.
- **Cross-version.** Capability detection adapts feature use (MON$ tables, explained plans,
  BOOLEAN, INT128, timezones, parallel workers) to the connected engine; validated on FB
  2.5 / 3.0 / 4.0 / 5.0.
- **Single configured database** per server instance (run multiple instances for multiple DBs).

---

## License

Licensed under the **Apache License 2.0** — see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

MCP Firebird is a showcase for
[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi). If you build your own MCP
server in Delphi, start there.
