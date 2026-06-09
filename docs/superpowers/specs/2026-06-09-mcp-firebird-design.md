# MCP Firebird Server — Design Spec

- **Date:** 2026-06-09
- **Status:** Approved (design); pending implementation plan
- **Author:** Daniele Teti (with Claude)
- **Base library:** `C:\DEV\mcp-server-delphi` (MCP Server for DMVCFramework) — consumed on the search path, **not forked**

## 1. Purpose

A Model Context Protocol (MCP) server for **Firebird**, written in Delphi, that is a genuine assistant for DBAs and developers who need to **document, optimize, and troubleshoot** Firebird databases. It must:

- Use the **official Firebird client** (FireDAC + `fbclient.dll`) — never a Node.js driver (this is the explicit reason the existing `PuroDelphi/mcpFirebird` project was rejected).
- Be **MCP-compliant** (protocol 2025-03-26), reusing the proven `mcp-server-delphi` library.
- Work across **Firebird 2.5 → 5.0** via runtime version/capability detection and graceful degradation.
- Exploit advanced Firebird features (MON$ tables, explained plans, Services/Trace API, index statistics) **where the engine supports them**.
- Deliver a full **test battery** that exercises every feature.

### Design principles (non-negotiable)

1. **Simple to use** — the user does one thing (point the MCP at a DB; optionally pick a prompt). No multi-step setup, no per-call connection strings.
2. **Useful to the DBA** — output is plain-language findings with the *why*, not raw dumps.
3. **Directly applicable** — every suggestion ships ready-to-run, version-correct SQL the DBA can paste and execute.

## 2. Decisions (locked)

| Topic | Decision |
|---|---|
| Execution model | **Read-only by default, opt-in write tools** gated by `firebird.allow_ddl=true` |
| Transport | **stdio only** (no TaurusTLS; launched locally by the AI client) |
| DB targeting | **Single configured DB** from `.env` / config file |
| FB connection mode | **Server/client only** via `fbclient.dll` |
| Perf data sources | **All four:** prepare+PLAN/EXPLAIN, MON$ live snapshot, Trace API, read existing trace/firebird.log |
| Build scope | **Phased** — M1 (foundation/docs/query-opt/index-advisor), M2 (monitoring/config), M3 (trace/write) |
| Architecture | **Layered:** Firebird analysis core (MCP-agnostic) + thin MCP provider wrappers |
| Target platform | **Win64** (`fbclient.dll` is 64-bit) |

## 3. Architecture

### 3.1 Layered shape — the core boundary is the whole design

The `Firebird.*` analysis core **never imports an `MVCFramework.MCP.*` unit**. It is plain, directly testable Object Pascal. MCP providers are thin wrappers that call the core and format results. This is what makes "test every feature" achievable: the analysis logic is unit-tested against a real DB without any MCP plumbing.

```
C:\DEV\mcp-firebird\
├── sources\                         # Firebird analysis core (NO MCP dependency)
│   ├── Firebird.Connection.pas      # FireDAC wrapper; single configured DB from .env
│   ├── Firebird.Capabilities.pas    # detect ENGINE_VERSION → feature flags
│   ├── Firebird.Introspection.pas   # tables, columns, PK/FK, indices, procs, triggers, views, domains
│   ├── Firebird.PlanAnalyzer.pas    # prepare query → PLAN (2.5) / explained plan (3+); flag NATURAL scans
│   ├── Firebird.IndexAdvisor.pas    # suggest new indexes; suggest drops
│   ├── Firebird.Monitoring.pas      # MON$ snapshot: running stmts, long tx, OAT/OIT gap, hot tables
│   ├── Firebird.Trace.pas           # Services-API trace session + trace/firebird.log parser
│   ├── Firebird.ConfigAdvisor.pas   # firebird.conf / DB header advice
│   ├── Firebird.DocGen.pas          # schema → Markdown documentation
│   └── Firebird.Goal.pas            # goal evaluation engine (measurable stop conditions)
│
├── providers\                       # Thin MCP layer (wraps core, no logic)
│   ├── FirebirdToolsU.pas           # [MCPTool] read-only analysis tools
│   ├── FirebirdWriteToolsU.pas      # [MCPTool] opt-in write tools (gated)
│   ├── FirebirdResourcesU.pas       # [MCPResource] firebird://schema, firebird://doc/{table}, firebird://config
│   └── FirebirdPromptsU.pas         # [MCPPrompt] optimization_goal, audit_indexes, document_database, health_check
│
├── app\
│   ├── MCPFirebird.dpr              # slim stdio entry point
│   ├── BootConfigU.pas              # dotEnv + LoggerPro (file-only; stdout stays pure JSON-RPC)
│   ├── EngineConfigU.pas            # provider registration
│   └── bin\.env                     # connection + flags (see §6)
│
└── tests\
    ├── coreproject\                 # DUnitX: analysis core vs seeded real FB DB (version matrix)
    │   └── seed.sql                 # known scenarios (unindexed FK, redundant index, NATURAL scan…)
    ├── mcpproject\                  # DUnitX: MCP tool-level contract tests
    ├── fbkit.ps1                    # start/stop FB zip-kit (per version, own port + fbclient)
    └── test_mcp_firebird_stdio.py   # Python MCP compliance (reuses library harness)
```

### 3.2 Version / capability handling (FB 2.5 → 5.0)

One detection at connect time drives every subsequent query:

```pascal
LCaps := TFirebirdCapabilities.Detect(Conn);
//  SELECT rdb$get_context('SYSTEM','ENGINE_VERSION')  → "2.5.9" / "3.0.x" / "4.0.x" / "5.0.x"
//  flags: HasExplainedPlan (3+), HasBooleanType (3+), HasIdentityCols (3+),
//         HasMonTables (2.1+), HasIndexStatistics, SupportsInt128 (4+),
//         HasTimezones (4+), HasParallelWorkers (5+), HasRDB$CONFIG (4+)
```

Rules:
- Every introspection query has a **2.5-baseline form**; enriched columns are gated by a flag, never assumed.
- `PlanAnalyzer` returns legacy `PLAN` on 2.5; adds the explained-plan tree on 3+.
- Each tool's output **states the detected engine version** so the DBA knows the basis of the advice.

### 3.3 "Directly applicable" output contract

Every advisory tool returns three blocks:

1. **Finding** — plain language, what & why, with magnitudes (`Table ORDERS scanned NATURAL when filtered by CUSTOMER_ID; ~1.2M rows`).
2. **Ready-to-run SQL** — copy-paste, version-correct, fully qualified, with the trade-off noted (`CREATE INDEX IDX_ORDERS_CUSTOMER_ID ON ORDERS (CUSTOMER_ID); -- good selectivity; adds write cost`).
3. **Verification step** — how to confirm it worked (`re-run analyze_query; expect the plan to use IDX_ORDERS_CUSTOMER_ID`).

Write tools execute that **exact** SQL, so "suggest" and "apply" share one code path. With `allow_ddl=false` (default), the SQL is returned as text only.

## 4. Goal-driven optimization mechanism

### 4.1 The constraint and the solution

An MCP server is **client-driven**: it cannot loop the agent or force a stop. The solution is to make the goal **machine-checkable**. The server provides (a) a prompt template defining the iterative protocol and (b) a deterministic evaluation tool that returns `met: true/false`. The agent (Claude) runs the loop; the server supplies the crisp stop condition.

### 4.2 `[MCPPrompt('optimization_goal')]`

Arguments:

| Arg | Meaning |
|---|---|
| `goal_type` | `query_time_ms` \| `query_no_natural_scan` \| `query_max_reads` \| `oat_gap` \| `no_redundant_indexes` |
| `target` | query text, table name, or `'database'` |
| `threshold` | numeric (ms / reads / OAT gap); ignored for boolean goals |
| `max_iterations` | safety cap, default 5 |

The returned protocol instructs the agent:

1. Call `fb_evaluate_goal` → establish **baseline**.
2. If `met=true` → **STOP**, report.
3. Otherwise call advisors (`fb_analyze_query`, `fb_suggest_indexes`…), propose/apply a fix.
4. Call `fb_evaluate_goal` again → compare to previous iteration.
5. Repeat until `met=true`, **or** `max_iterations` reached, **or** **no improvement for 2 rounds** (anti-loop) → report best result found and why the goal is unreachable.

### 4.3 `[MCPTool('fb_evaluate_goal')]`

Deterministic, pure, idempotent. Args: `goal_type`, `target`, `threshold`. Returns:

```json
{ "goal_type":"query_time_ms", "measured": 145, "threshold": 200,
  "met": true, "gap": -55, "iteration_hint": "plan now uses IDX_ORDERS_CUSTOMER_ID",
  "engine_version":"4.0.4", "details": { "plan":"…", "reads": 312 } }
```

Measurements use the core: timed execution, `reads`/`fetches` from MON$ stats, presence of `NATURAL` in the plan, OAT/OIT gap, unindexed FKs, redundant indexes.

**Simple to use:** the user only picks the `optimization_goal` prompt and writes the goal. No server-side state; the goal travels in arguments; safety limits live in the prompt.

## 5. Tool catalog (phased)

### M1 — Foundation + documentation + query optimization + index advisor (read-only)

| Tool | What it does | Source |
|---|---|---|
| `fb_info` | Engine version, dialect, charset, ODS, capabilities, DB size | `rdb$get_context`, header |
| `fb_list_tables` | Tables/views with estimated row count, PK, index count | introspection |
| `fb_describe_table` | Columns, types, domains, PK/FK, indices, triggers, checks, computed | introspection |
| `fb_generate_documentation` | Full or per-table Markdown docs (incl. `RDB$DESCRIPTION` comments) | DocGen |
| `fb_analyze_query` | Prepare → PLAN (2.5) / explained plan (3+); flag NATURAL scans, external sorts, join order; Finding+SQL+Verify | PlanAnalyzer |
| `fb_suggest_indexes` | New indexes for columns hit by NATURAL scans in an analyzed query (WHERE/JOIN/ORDER BY predicates); ready DDL + post-create `SET STATISTICS` reminder. (Note: FK constraints already auto-index in Firebird, so this is driven by plan analysis, not missing FK indexes.) | IndexAdvisor + PlanAnalyzer |
| `fb_suggest_index_drops` | User index **duplicating** a system PK/FK index, redundant (left-prefix of another), low-selectivity (`RDB$STATISTICS`→1), inactive (`RDB$INDEX_INACTIVE=1`), exact duplicate; ready DROP / ALTER INDEX INACTIVE | IndexAdvisor |
| `fb_evaluate_goal` | Measure state vs threshold, `met:true/false` | Goal (cross-cutting) |

### M2 — Live monitoring + config advisor (read-only)

| Tool | What it does | Source |
|---|---|---|
| `fb_whats_running` | Active statements now, duration, attachment, I/O | `MON$STATEMENTS`/`MON$IO_STATS` |
| `fb_transaction_health` | OAT/OIT/Next gap, oldest active tx, garbage risk | `MON$TRANSACTIONS` |
| `fb_hot_tables` | Tables with most reads/writes/record versions in real time | `MON$RECORD_STATS` |
| `fb_analyze_config` | firebird.conf + DB header (page size, buffers, sweep interval, forced writes); version-specific advice | ConfigAdvisor |
| `fb_database_health` | Aggregate report: suspect indexes + tx + stale statistics (`SET STATISTICS` advised) | aggregator |

### M3 — Trace + write tools

| Tool | What it does | Gate |
|---|---|---|
| `fb_start_trace` / `fb_stop_trace` / `fb_read_trace` | Trace session via Services API + log parser; historically slow statements | read-only |
| `fb_parse_log_file` | Analyze trace/firebird.log path from config | read-only |
| `fb_apply_sql` | Execute DDL/DML (e.g. the suggested CREATE INDEX); transactional, dry-run option | **write** |
| `fb_set_statistics` | Recompute index selectivity (`SET STATISTICS INDEX`) | **write** |
| `fb_rebuild_index` | `ALTER INDEX INACTIVE` + `ACTIVE` | **write** |

Every write tool checks the flag; if off, returns a `TMCPToolResult.Error` explaining how to enable it.

### Resources & Prompts

- **Resources:** `firebird://schema` (full schema JSON), `firebird://doc/{table}` (on-demand doc), `firebird://config` (current config).
- **Prompts:** `optimization_goal` (§4), `audit_indexes`, `document_database`, `health_check`.

## 6. Configuration (`app/bin/.env`)

```bash
# Connection (single configured DB)
firebird.host=localhost
firebird.port=3050
firebird.database=C:\data\MYDB.FDB
firebird.user=SYSDBA
firebird.password=masterkey
firebird.charset=UTF8
firebird.client_lib=C:\firebird\fbclient.dll   # optional explicit fbclient path

# Safety
firebird.allow_ddl=false                        # write tools disabled by default

# Trace / logs (M3)
firebird.trace.log_path=C:\firebird\trace.log   # optional, for parse_log_file

# Logging (file-only so stdout stays pure JSON-RPC)
logger.config.file.stdio=loggerpro.stdio.json
```

## 7. Test plan — every feature covered

### Layer 1 — Core (DUnitX, `tests/coreproject`) — the real value

Runs against a **seeded Firebird DB** recreated each run with known scenarios (`seed.sql`):
- Tables with a **user index duplicating the system FK index**, **redundant left-prefix** indexes, **low-selectivity** indexes, an **inactive** index, a large table forcing a NATURAL scan when filtered on a non-indexed column, stale statistics.
- Deterministic assertions: `fb_analyze_query` *must* detect the NATURAL scan on the non-indexed filter column; `fb_suggest_indexes` *must* propose an index on that column; `fb_suggest_index_drops` *must* flag the duplicate/redundant/inactive indexes; `fb_evaluate_goal` (`query_no_natural_scan`) *must* return `met=true` once the suggested index exists.
- **Version matrix:** the same suite runs against **FB 2.5.9 / 3.0.14 / 4.0.7 / 5.0.4** — all 64-bit **zip-kit** installs already present under `C:\DEV\mcp-firebird\fb_versions\`. Capabilities must diverge correctly (e.g. explained plan only on 3+). Versions not available locally are skipped with a logged notice (no silent pass).

**Zip-kit start/stop harness** (`tests/fbkit.ps1` or a Pascal helper):
- Each version runs as a **foreground process**, started before its test pass and **terminated after**:
  - FB 2.5 → `bin\fbserver.exe -a` (client lib: `bin\fbclient.dll`)
  - FB 3.0 / 4.0 / 5.0 → `firebird.exe -a` (client lib: `fbclient.dll` in the kit root)
- Each kit listens on its **own port** (set via that kit's `firebird.conf` `RemoteServicePort`): 2.5→3050, 3.0→3053, 4.0→3054, 5.0→3055. Kits can therefore coexist or run one-at-a-time.
- The test client loads the **matching `fbclient.dll` per version** via FireDAC `TFDPhysFBDriverLink.VendorLib` (same mechanism as `firebird.client_lib` in §6), so each pass exercises the real client of that engine.
- The seed DB is **created fresh** per version (SYSDBA/masterkey from the kit's security DB) and dropped after.

### Layer 2 — MCP tool (DUnitX, `tests/mcpproject`)

Providers honor the contract (Finding/SQL/Verify), write-gating on/off behaves correctly, schema JSON is valid.

### Layer 3 — MCP compliance (Python, reuses library harness)

`test_mcp_firebird_stdio.py`: handshake, `tools/list`, `tools/call`, `prompts/get` of `optimization_goal`, **stdout purity** (only JSON-RPC), error envelope.

### Layer 4 — Goal loop (DUnitX)

Simulates the cycle: baseline `met=false` → apply index → `fb_evaluate_goal` `met=true`; verifies stop on `max_iterations` and on no-progress.

`run_all.bat`: recreate seed → core (per available FB version) → mcp → python. Non-zero exit on any failure.

## 8. Out of scope (YAGNI)

- HTTP transport / TaurusTLS / auth (stdio only).
- Multi-database or AI-supplied connection strings (single configured DB).
- Embedded Firebird mode (server/client only).
- Backup/restore/gbak orchestration, replication management, user administration.
- Automatic application of changes without the `allow_ddl` opt-in.

## 9. Requirements

- Delphi 11+ (Alexandria) or later; **Win64 build target**.
- DMVCFramework 3.5.x + `mcp-server-delphi` sources on the search path.
- Firebird client `fbclient.dll` (64-bit) reachable (path optionally pinned via `firebird.client_lib`).
- Integration tests use the local zip-kits under `C:\DEV\mcp-firebird\fb_versions\` (FB 2.5.9 / 3.0.14 / 4.0.7 / 5.0.4), started/stopped by the test harness.
