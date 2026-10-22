# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An MCP (Model Context Protocol) **server** for Firebird 2.5–5.0, written in Delphi against the
official `fbclient` driver + FireDAC. It talks JSON-RPC 2.0 over stdio. Given a configured
database, it documents schemas, analyzes query plans, helps the DBA and advises on indexes — strictly
read-only: no tool runs DDL or write SQL (write tools are M3, still unimplemented, and will ship
behind an explicit opt-in setting). Full user-facing docs, tool reference and worked examples live in `README.md` and `docs/` (setup, usage, tools, editions) —
read it for anything about *using* the server; this file is about *building* it.

## Prerequisites

- Windows x64, **Delphi 13 Athens** (RAD Studio 37.0) with FireDAC.
- **DMVCFramework** and **`mcp-server-delphi`** checked out locally as sibling projects — the
  `.dproj` search paths assume:
  ```
  C:\DEV\mcp-server-delphi\sources
  <DMVCFramework>\sources   (every subfolder DMVC needs)
  C:\DEV\mcp-firebird\sources
  C:\DEV\mcp-firebird\providers
  ```
- A `fbclient.dll` (a 5.0 client connects fine to 2.5–5.0 servers).
- For the test matrix: Firebird zip-kits under `fb_versions/` and Python 3 + `pytest`
  (`python -m pip install pytest invoke`).

## Build

```powershell
cmd /c _build_app.bat     # -> bin\MCPFirebird.exe (Win64 Debug)
cmd /c _build_core.bat    # -> tests\coreproject\MCPFirebirdCoreTests.exe (DUnitX core suite)
```

Both batch files call `rsvars.bat` then `msbuild ... /t:Clean;Build /p:Config=Debug /p:Platform=Win64`.
Or via the `tasks.py` PyInvoke wrapper (thin orchestration over the same scripts):

```powershell
invoke build          # build_core + build_app
invoke build-app
invoke build-core
```

## Running manually / configuring

The app reads `bin\.env` by default (or a folder passed via `--env <dir>`; see `docs/setup.md` for the
full `--env` contract, per-client MCP JSON snippets, and the `.env` key reference). Smoke-test by
piping framed JSON-RPC lines into the exe — the exact commands are in
[docs/setup.md § Run & verify manually](docs/setup.md#run--verify-manually).

## Testing

```powershell
pwsh tests/run_all.ps1     # everything: core matrix (2.5-5.0) + boundary check + Python compliance
invoke --list               # see all pyinvoke tasks
invoke matrix                # DUnitX core suite across every FB version present in fb_versions/
invoke core --version 5.0    # DUnitX core suite against one version (start/seed/test/stop)
invoke boundary               # enforce sources/ <-> MVCFramework isolation (see Architecture)
invoke compliance              # Python stdio MCP protocol-compliance suite (pytest, on FB 5.0)
```

**One-time per Firebird zip-kit** (needed for 3.0/4.0/5.0 kits; 2.5 works out of the box): the
kits ship without a usable `SYSDBA`. With the server stopped, create it in embedded mode:
```
<kit>\isql.exe -user SYSDBA "<kit>\security<N>.fdb"
  CREATE USER SYSDBA PASSWORD 'masterkey';
  COMMIT; QUIT;
```
See README's Troubleshooting section for details if this trips you up.

Ports per version (`tests/fbkit.versions.psd1`): 2.5→3070, 3.0→3053, 4.0→3054, 5.0→3055.
`tests/fbkit.ps1 -Action <start|stop|client|port> -Version <X.Y>` drives a single kit;
`tests/seed/make_seed.ps1 -Version <X.Y>` (re)builds the seeded `tests/seed/TESTDB.FDB` used by
both the DUnitX core suite and the Python suite. The seed data — including deliberately broken
fixtures (missing PK, over-indexing, stale stats, duplicate indexes) — is defined in
`tests/seed/seed.sql` and `tests/seed/problems.sql`; see `docs/firebird-problem-catalog.md` for
which fixture provokes which detector and which milestone it lands in.

### Running a single DUnitX test

The core suite is a normal DUnitX console exe; environment variables select the target DB:
```powershell
pwsh tests/fbkit.ps1 -Action start -Version 5.0
pwsh tests/seed/make_seed.ps1 -Version 5.0
$env:FBTEST_PORT = (pwsh tests/fbkit.ps1 -Action port -Version 5.0)
$env:FBTEST_DB = 'C:\DEV\mcp-firebird\tests\seed\TESTDB.FDB'
$env:FBTEST_CLIENTLIB = (pwsh tests/fbkit.ps1 -Action client -Version 5.0)
& 'C:\DEV\mcp-firebird\tests\coreproject\MCPFirebirdCoreTests.exe' --filter='Test.Firebird.PlanAnalyzer'
pwsh tests/fbkit.ps1 -Action stop -Version 5.0
```
(DUnitX supports the standard `--filter`/`--list` console flags for narrowing to one fixture/test.)

### Python compliance suite only

```powershell
pwsh tests/fbkit.ps1 -Action start -Version 5.0
pwsh tests/seed/make_seed.ps1 -Version 5.0
python -m pytest tests/test_mcp_firebird_stdio.py tests/test_mcp_firebird_full.py -v
pwsh tests/fbkit.ps1 -Action stop -Version 5.0
```

## Architecture

Three layers, strictly separated, enforced by `invoke boundary` /
`tests/check_core_boundary.ps1` (fails the build if any `sources/*.pas` unit imports
`MVCFramework.*`):

```
sources/       Firebird.*        -- pure Delphi/FireDAC domain logic. NO MCP or DMVCFramework
                                     imports allowed. Testable standalone (that's what the DUnitX
                                     core suite exercises via tests/coreproject/).
providers/     Firebird*U        -- the MCP-facing adapter layer. Wraps sources/ units as
                                     TMCPToolProvider / prompts / resources using DMVCFramework's
                                     MCP attributes ([MCPTool], [MCPParam]).
app/           MCPFirebird.dpr   -- the executable: boot/config (.env, --env, logger) + wires the
               BootConfigU        providers into TMCPStdioTransport and runs the JSON-RPC loop.
               EngineConfigU
```

Why the split: `sources/` has to stay engine-agnostic and swappable/testable in isolation from
the MCP protocol plumbing; `providers/` is the only place that knows about DMVCFramework's MCP
attribute system. Never add an MVCFramework import to a `sources/*.pas` unit — add a new
`providers/*` adapter instead, or extend an existing one.

Key `sources/` units and what they own:
- `Firebird.Connection` — `TFirebirdConnection` / `TFirebirdConnectionConfig`: the FireDAC wrapper
  (host/port/db/user/pass/charset/client_lib), `OpenQuery`/`ExecSQL`/`ScalarStr`.
- `Firebird.Capabilities` — runtime feature detection (MON$ tables, explained plans, BOOLEAN,
  INT128, timezones, parallel workers) keyed off engine version, so behavior adapts across 2.5-5.0
  instead of hardcoding one engine's SQL dialect.
- `Firebird.Introspection` — schema reads: tables, columns, PK, indexes, FKs.
- `Firebird.PlanAnalyzer` — drives a local `isql` for the plan. One script, two prepares: the
  legacy `PLAN` line under `SET PLANONLY ON`, then (3.0+ only, `SET EXPLAIN ON`) the explained
  tree, parsed for index names, per-index segment match quality, join strategy and the engine's
  own alias→table map. 2.5 never sees the `SET EXPLAIN` line — an unknown `SET` aborts the script
  carrying the statement.
- `Firebird.IndexAdvisor` — the remedy ladder: `SET STATISTICS` (refresh, leaves nothing behind)
  → `ALTER INDEX ACTIVE` (an index that already exists) → `CREATE INDEX` (paid for on every
  write, forever), always the lowest rung that explains the plan. Executes the query once through
  `Firebird.Activity.Measure` to compare records read with rows returned, and stays **silent with
  the numbers** when the scan is the right plan. Shapes: plain B-tree, `COMPUTED BY` expression,
  partial (`HasPartialIndexes`, 5.0+), and an index for the `ORDER BY` in its own direction. The
  text-level extraction (`ExtractPredicates` / `ExtractOrderBy`) is exported so it can be tested
  without a database. Also flags droppable indexes (duplicate / redundant-prefix / inactive /
  low-selectivity — the last one only after comparing stored selectivity with actual).
- `Firebird.SchemaAudit` — table-level health audit (missing PK, over-indexing, stale statistics),
  plus the shared statistics primitives the advisor uses: `ColumnStats` (rows / non-null /
  distinct in one scan), `StoredSelectivity` (per-segment, from `RDB$INDEX_SEGMENTS`) and
  `StaleIndexes`. `STALE_FACTOR` lives here — one threshold, one meaning, two callers.
- `Firebird.Goal` — deterministic goal evaluation (`query_no_natural_scan`, `query_time_ms`,
  `no_redundant_indexes`, `no_stale_index_statistics`) that backs the `optimization_goal`
  iterate-until-met prompt loop.
- `Firebird.DocGen` — Markdown doc generation for one table or the whole DB.
- `Firebird.TransactionMonitor` — OIT/OAT/OST/Next gap from `MON$DATABASE` + the oldest active
  transaction from `MON$TRANSACTIONS`/`MON$ATTACHMENTS`; flags one pinning garbage collection.
- `Firebird.Activity` — the only unit that measures *change* rather than state: reads
  `MON$IO_STATS`/`MON$RECORD_STATS` twice across a window (`Sample`) or across one statement's
  execution (`Measure`) and reports the delta. `MON$` freezes its snapshot per transaction, so
  both call `TFirebirdConnection.NewMonitoringSnapshot` between readings — without it every delta
  is zero and the database looks idle under any load. `Measure` executes the SQL it is given, so
  it goes through `IsReadOnlySelect` first (as does `Firebird.Goal`'s `query_time_ms`).
- `Firebird.Attachments` — who is attached, from where, and the statement each one is running
  now, from `MON$ATTACHMENTS` + `MON$STATEMENTS` in one query that works unchanged on 2.5-5.0
  (only the `HasMonTables` guard). Flags idle attachments and long-running statements. It reports
  state, never waiting: an attachment blocked on a lock looks exactly like a busy one.
- `Firebird.Backup` — drives a **local** `gbak.exe` through temp files, the second sanctioned
  exception to the no-process-spawning rule. `Backup` writes the `.fbk`; `VerifyRestore` restores
  it into a scratch database with `gbak -c` (creates, refuses an existing file) and deletes it,
  because a backup nobody has restored is a file. Takes the connection config **by value**: it
  issues no SQL and runs on a thread that outlives the tool call.
- `Firebird.Advisory` — the shared `TAdvisory` record (Severity/Finding/SQLText/Verify) that every
  advisory-producing unit returns, rendered uniformly by `providers/FirebirdToolsU.AdvisoriesToText`.

`providers/` layer:
- `FirebirdConfigU` — reads `firebird.*` keys from dotEnv into `TFirebirdConnectionConfig`
  (`LoadFirebirdConfig`), validates them with speaking errors (`NewConfiguredConnection`).
- `FirebirdToolsU` — the 13 `fb_*` MCPTool methods (`TFirebirdTools`); every tool body runs through
  `Guard()`, which opens/frees the configured connection and hands it to the body, logs
  `>> tool args` / `<< tool ok|isError Nms` to the `mcp` log tag and converts
  any exception into an `isError` `TMCPToolResult` instead of an opaque JSON-RPC -32603 — keep new
  tools inside `Guard` so failures surface to the MCP client instead of just crashing the request.
- `FirebirdBackupJobU` — the one-slot backup job: `StartBackupJob` hands `Firebird.Backup` to an
  anonymous thread and returns at once (False when one is already running), `BackupJobState`
  reports the phase. Lives in `providers/` because the asynchrony is a protocol concern — MCP
  cannot stream progress — and `sources/` stays synchronous and directly testable.
- `FirebirdPromptsU` — the `optimization_goal`, `health_check` and `classify_problem` prompts.
- `FirebirdResourcesU` — the `firebird://schema` resource.

`app/` layer:
- `BootConfigU.Boot` — parses `--env <dir>`/`--env=<dir>`, resolves and validates it's a folder
  (not a `.env` file — raises `EBootConfig` with a speaking fix otherwise), configures dotEnv
  (`FileThenEnv` priority) and the file logger. `EnvDir`/`EnvFile` expose the resolved paths for
  other units' error messages (see `FirebirdConfigU`'s `EnvHint`).
- `EngineConfigU.ConfigureServerIdentity` — sets `TMCPServer.Instance.ServerName/-Version`.
- `MCPFirebird.dpr` — catches `EBootConfig` and writes the fix to stderr (`Halt(2)`) before the
  transport ever starts, since MCP clients surface stderr as server logs; otherwise wires
  `TMCPStdioTransport` to `TMCPServer.Instance` and runs it.

Logging: stdout is reserved for pure JSON-RPC; all logging goes to `bin\logs\` via LoggerPro,
configured by `logger.config.file` (default `loggerpro.stdio.json`). Never write to stdout outside
the MCP transport itself.

## Conventions

- Every advisory-producing function returns `TAdvisory` (Severity/Finding/SQLText/Verify) — new
  detectors should follow this shape so `AdvisoriesToText` can render them without special-casing.
- Read-only, and enforced by the engine: `FirebirdConfigU.LoadFirebirdConfig` sets
  `TFirebirdConnectionConfig.ReadOnly`, so every transaction the server opens carries the
  read-only TPB and Firebird refuses a write whatever SQL reaches it. `IsReadOnlySelect` in front
  of the three tools that execute caller-supplied SQL (`fb_analyze_query`'s measurement,
  `fb_suggest_indexes`'s measurement and `fb_evaluate_goal`'s `query_time_ms`) is the polite
  refusal, not the guarantee; `HasParameters` beside it refuses to *measure* a statement whose
  placeholders nobody bound, because FireDAC binds them as NULL and the number would describe a
  query nobody runs. The test
  connections deliberately leave `ReadOnly` false — the suite creates and drops indexes. The first
  write tool must introduce an explicit opt-in setting, enforce it, and only then relax the TPB,
  consistent with the M1-M2 read-only scope described in README's Safety section.
- `docs/firebird-problem-catalog.md` is the source of truth mapping each detected problem to its
  seed fixture and milestone (M1/M2/M3) — check it before adding a new detector or fixture.
- **Editions.** This repo is source-available (PolyForm Internal Use 1.0.0), not open source; new
  production sources carry the `LicenseRef-PolyForm-Internal-Use-1.0.0` SPDX header. The free
  edition uses an **ordinary SQL connection and nothing more**. Two things belong to the paid
  Enterprise edition in the separate private repo: the server's own configuration and hardware
  (`firebird.conf`, RAM/CPU), and anything needing an **administrative attach to the Services
  Manager** (`firebird.log`, the Trace API, the storage report — note these stream back over the
  wire and touch no file, so a filesystem-only rule would miss them). `invoke boundary` fails the
  build on both: file reads / process spawning in `sources/` (`Firebird.PlanAnalyzer`, which drives
  a local `isql`, and `Firebird.Backup`, which drives a local `gbak`, are the two sanctioned
  exceptions — the allowlist in `tests/check_core_boundary.ps1`), and any `isc_service_*` / `TFDPhysFBService` /
  `service_mgr` reference. The nine locked tools in `providers/FirebirdStubsU.pas` announce the
  Enterprise edition; their names are a contract — the Python compliance suite is shared with the
  Enterprise repo, which runs it with `MCP_FB_EDITION=enterprise`.

## Testi per esseri umani

Ogni testo destinato a un lettore (articoli, README, documentazione, release notes: tutto tranne
il codice) va ripulito con lo skill `clean-user-facing-text`
([watermarks-remover](https://github.com/guillaumemeyer/watermarks-remover)) prima di essere
consegnato o pubblicato:

```bash
S="C:/Users/dteti/.claude/skills/clean-user-facing-text/scripts"
py "$S/inspect_text.py" --json FILE     # suspicious_total deve essere 0
```

Trova in modo deterministico gli Unicode invisibili (zero-width, bidi, tag characters, spazi
omoglifi). Non rileva i watermark statistici, che si attenuano solo riscrivendo: per quelli
restano `humanizer` e `stop-slop`.
