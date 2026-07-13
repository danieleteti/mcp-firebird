# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-07-13

### Fixed
- `fb_analyze_query` reported a statement the engine had **refused** as a clean plan. The plan
  comes from `isql` under `SET PLANONLY ON`, whose diagnostics share the same output; only the
  `PLAN` lines were kept, so "Table unknown" became an empty plan and the reassuring "No NATURAL
  scan: every table is accessed via an index." A statement that produces no plan is now an error
  carrying the engine's own message — in `fb_suggest_indexes` and `fb_evaluate_goal` too.
- `fb_suggest_indexes` wrote the **table alias** from the plan into its DDL: `CREATE INDEX
  IDX_C_CITY ON C (CITY)`, against a table `C` that does not exist. It also pinned every
  `column operator` match in the statement on every scanned table, so a join key already carrying
  the primary-key index came back as an index to create. Aliases are now resolved from the
  FROM/JOIN clauses, a column is attributed to the table it belongs to, and a column already
  served by an active index is not suggested.
- `fb_audit_table` called an **INACTIVE** index's missing statistics "stale" and prescribed
  `SET STATISTICS` on an index the optimizer cannot use for reads. The remedy for it is the drop
  `fb_suggest_index_drops` already recommends.
- Selectivity figures were unreadable and unparseable: `%.6f` printed both sides as `0.000000` on
  a large table (where the real value is ~5e-8), and `Format` without invariant settings took the
  decimal separator from the host locale, yielding `0,250000` on an Italian Windows box.

### Changed
- **Breaking: licence.** From the next release the project is licensed under the
  [PolyForm Internal Use License 1.0.0](LICENSE) — source-available, **not open source**.
  Free for the internal business operations of you and your company, at any scale; a
  commercial licence is required to distribute it, embed it in a shipped product, or offer
  it as a service. `v0.1.0` was released under Apache-2.0 and **remains Apache-2.0 forever**
  for everyone who received it: a granted licence cannot be revoked.
- Contributor terms in `CONTRIBUTING.md`: code contributions now carry a sublicensable
  grant, so that accepted contributions can also ship in the paid Enterprise edition. Issues
  and documentation fixes still require no rights grant.

### Added
- An Enterprise edition, sold separately, covering what only the host machine knows:
  `firebird.conf`/`databases.conf` tuning, database-header analysis, `firebird.log` parsing,
  Trace API capture, host sizing. The free edition keeps everything the database knows about
  itself, including the M3 write tools.

### Removed
- **Breaking:** tool `fb_describe_table`. It returned exactly what
  `fb_generate_documentation` returns for a named table — use that instead.
- The `firebird.allow_ddl` setting. It gated nothing: no write/DDL tool exists yet. The gate
  returns together with the write tools (M3).

### Changed
- `fb_generate_documentation`'s description now states it documents columns, primary key and
  indexes, since it is the only introspection tool left.

## [0.1.0] - 2026-07-08

First public release.

### Added
- MCP server for Firebird 2.5–5.0 over stdio (JSON-RPC 2.0, protocol `2025-03-26`), built with
  [mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi).
- Tools: `fb_info`, `fb_list_tables`, `fb_describe_table`, `fb_generate_documentation`,
  `fb_analyze_query`, `fb_suggest_indexes`, `fb_suggest_index_drops`, `fb_audit_table`,
  `fb_evaluate_goal`, `fb_monitor_transactions`.
- `optimization_goal` and `health_check` prompts; `firebird://schema` resource.
- Runtime capability detection across engine versions; access-plan analysis; index add/drop
  advice; schema-health audit; transaction/sweep monitoring.
- Read-only by default (DDL/write gated behind `firebird.allow_ddl`).
- `--env <dir>` configuration, per-invocation tool tracing to the log.

### Notes
- Source-only release; requires Delphi 13 Athens to build.
