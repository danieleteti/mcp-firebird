# MCP Firebird

A Model Context Protocol server for Firebird (2.5–5.0), written in Delphi with the
official `fbclient` driver. Documents schemas, analyzes query plans, advises on
indexes, audits schema health, and drives goal-based optimization — read-only by default.

## Quick start

1. Build `app/MCPFirebird.dproj` (Win64) in Delphi. Search paths: `C:\DEV\mcp-server-delphi\sources`, DMVCFramework `sources`, this repo's `sources` + `providers`.
2. Copy `app/bin/.env.example` to `app/bin/.env` and set `firebird.*`:
   ```bash
   firebird.host=localhost
   firebird.port=3055
   firebird.database=C:\path\to\YOURDB.FDB
   firebird.user=SYSDBA
   firebird.password=masterkey
   firebird.charset=UTF8
   firebird.client_lib=C:\path\to\fbclient.dll
   firebird.allow_ddl=false
   ```
3. Register with Claude Desktop (`%APPDATA%\Claude\claude_desktop_config.json`):
   ```json
   { "mcpServers": { "firebird": { "command": "C:\\DEV\\mcp-firebird\\app\\bin\\MCPFirebird.exe" } } }
   ```

## Tools (M1)

| Tool | Purpose |
|---|---|
| `fb_info` | Engine version + detected capabilities |
| `fb_list_tables` | List user tables |
| `fb_describe_table` | Columns, PK, indexes, foreign keys |
| `fb_generate_documentation` | Markdown docs for a table or the whole database |
| `fb_analyze_query` | Access-plan analysis: NATURAL scan + external SORT detection |
| `fb_suggest_indexes` | Suggest new indexes from NATURAL-scanned predicates |
| `fb_suggest_index_drops` | Flag duplicate / redundant-prefix / inactive / low-selectivity indexes |
| `fb_audit_table` | Schema-health audit: missing PK, over-indexing, stale statistics |
| `fb_evaluate_goal` | Deterministic goal check (drives the `optimization_goal` loop) |

## Prompts

- `optimization_goal` — goal-driven loop: set an objective, iterate `fb_*` tools until `fb_evaluate_goal` reports `met: true`.
- `health_check` — guided database health review.

## Resources

- `firebird://schema` — live database schema.

## Safety

Read-only by default. Write tools (M3) require `firebird.allow_ddl=true`.

## Compatibility

Validated against Firebird 2.5, 3.0, 4.0, and 5.0 zip-kits. Capability detection
adapts feature use (MON$ tables, explained plans, BOOLEAN, INT128, timezones,
parallel workers) to the connected engine version.

## Tests

```powershell
pwsh tests/run_all.ps1
```

Runs the DUnitX core suite across the FB 2.5/3.0/4.0/5.0 zip-kits, the core-boundary
check, and the Python MCP stdio compliance suite. See
[`docs/firebird-problem-catalog.md`](docs/firebird-problem-catalog.md) for the
catalog of detected problems and their fixtures.
