# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- **PSQL objects in the generated documentation.** `fb_generate_documentation` stops pretending
  a database is only tables: stored procedures with their parameters, triggers with the event
  they fire on (2.5+), and PSQL functions and packages on the engines that have them (3.0+).
- **`fb_backup_start` / `fb_backup_status`: a backup that proves itself.** A backup nobody has
  restored is a file, not a backup — so the job writes the `.fbk` with `gbak`, restores it into
  a scratch database, checks it arrived, and deletes it again. `fb_backup_start` returns at once
  and the work runs on a thread, because a backup takes minutes and an MCP call must not; poll
  `fb_backup_status` for the phase, the size, and the verdict.
  Needs `firebird.backup_dir` in the `.env` — declared once there, never accepted from the
  caller — plus `gbak.exe` beside your `fbclient.dll` and room for a second copy of the
  database while the restore runs. One backup at a time.

  Still inside the free edition's line: a *local* client tool driven through temp files, the
  same sanctioned exception `Firebird.PlanAnalyzer` has always had for `isql.exe`. No Services
  Manager, no file on the server.

## [0.4.0] - 2026-08-07

`fb_suggest_indexes` used to find `NATURAL` in a plan, pull the predicate columns out of the SQL
with a regex, and propose `CREATE INDEX` for every one of them that had no index. It was right
often enough to be useful and wrong in four ways a DBA notices immediately: it treated every scan
as a defect, it never questioned the statistics the optimizer had decided on, it knew exactly one
shape of index, and it said what to do without ever saying why *that* shape.

This release is that tool rewritten around one idea: **an index is not free — it is written on
every INSERT, UPDATE and DELETE for as long as it exists — so propose the cheapest remedy that
explains what the plan did, and be willing to propose nothing.** The design, the measurements it
rests on and the thresholds with their reasoning are in
[`docs/superpowers/specs/2026-08-07-index-advisor.md`](docs/superpowers/specs/2026-08-07-index-advisor.md).

Still inside the free edition's line: ordinary SQL over an ordinary connection, no service
attach, no file on the server.

### Added
- **The scan that is the right plan.** The query is executed once and what it read is compared
  with what it returned. A scan that keeps most of what it reads *is* the correct plan, and so is
  a scan of a table small enough to be a handful of pages: both come back as a finding carrying
  the numbers and **no SQL to run**. An index there would be maintained on every write and save
  nothing.
- **Statistics before structure.** Firebird stores an index's selectivity when the index is built
  and never recalculates it, so an index that exists and is ignored may be ignored because the
  optimizer is costing it against last year's data. The advisor now answers that with
  `SET STATISTICS INDEX` — which reads the index, is safe under concurrent load and leaves
  nothing behind — instead of a second index the database pays for forever. **No advisory says
  "the index is not used, and that is correct" until the stored figure has been compared with the
  real one**, and both figures are printed.
- **Expression indexes.** `UPPER(NAME) = ?` cannot use a plain index at all: the index stores the
  column, the query asks for the result of the function. It now gets `COMPUTED BY (UPPER(NAME))`,
  with the expression emitted **exactly as written** — Firebird matches an expression index only
  on an exact match, and `UPPER(NAME)` is not `UPPER(TRIM(NAME))`. The extractor knows which side
  the function was on: `NAME = UPPER('x')` still gets a plain index. `SUBSTRING(NAME FROM 1 FOR 3)`
  is captured whole, by balanced parentheses, or refused.
- **Partial indexes on 5.0+.** `STATE = 'ACTIVE' AND TAG = ?` gets an index on what it seeks by,
  plus the partial form that indexes only the population the query looks at. The column that
  merely narrows the population no longer gets an index of its own. Below 5.0 the same query gets
  the plain B-tree plus one line saying what 5.0 would allow. The advisory states the trap: the
  optimizer uses a partial index only when the statement carries the same boolean expression —
  implication is not enough.
- **An index for the sort.** `fb_analyze_query` has flagged external `SORT`s since M1 and
  `fb_suggest_indexes` had never once suggested an index for one — its extractor only ever looked
  at comparison operators, so `ORDER BY` was invisible to it. It now proposes an index whose
  segments match the ordering **in its own direction** (Firebird cannot walk an ascending index
  backwards), says plainly that no single index serves `ORDER BY a ASC, b DESC`, names `FIRST n`
  as the case where the win is largest, and warns when reading most of a table through an index
  would cost more than the sort it removes.
- **The engine's explained plan** (3.0+) is captured and shown by `fb_analyze_query`: index names,
  how much of each index the query agreed with, the join strategy, and which alias is which table
  — stated by Firebird instead of inferred from the FROM clause with a regex. Two findings come
  from it that could not be written before: an index whose trailing segments this query never
  reaches, and a join whose two sides are both scanned. On 2.5, where `SET EXPLAIN ON` does not
  exist and an unknown `SET` would abort the script carrying the statement, nothing changed.
- **`no_stale_index_statistics`**, a fourth `fb_evaluate_goal` goal type: the number of indexes on
  a table whose stored selectivity no longer describes the data, met when zero. Every other goal
  asks the optimization loop to change the schema; this one gives it a first move that writes
  nothing structural.

### Fixed
- **A measurement of a query nobody runs.** `fb_analyze_query` on
  `SELECT * FROM CUSTOMERS WHERE CITY = ?` reported `Measured: 0 row(s)` over 5004 sequential
  reads. FireDAC binds an unset parameter as NULL, `CITY = NULL` matches nothing, and the number
  was real — about a statement that never executes in production. Worse, a yield of 0 out of 5004
  reads as the strongest possible case for an index. A statement carrying unbound parameters is
  now **not executed at all**, by `fb_analyze_query`, by `fb_suggest_indexes` and by
  `fb_evaluate_goal`'s `query_time_ms`, and the report says why instead of quoting a zero.
- **`A <> 5` was read as a range predicate.** The operator alternation stopped at `<`, so a
  comparison no index can serve came back as an index to create. `<>`, `!=`, `NOT IN` and
  `NOT LIKE` are now recognised in order to be discarded.
- **Stale statistics were only ever checked on single-column indexes**, and against the wrong
  number if they had been checked at all: `RDB$INDICES.RDB$STATISTICS` is the selectivity of the
  whole key, which is not comparable with the distinct count of one column. The comparison now
  reads the per-segment figure from `RDB$INDEX_SEGMENTS`, so composite indexes are covered, and a
  column that is mostly NULL is reported as **not comparable** rather than as stale —
  `COUNT(DISTINCT)` ignores NULLs and the index does not.
- **`fb_suggest_index_drops` called an index unselective on a number nobody had checked.** It read
  the stored selectivity, found it poor, and proposed a drop; if that figure was simply out of
  date the advice was to delete a working index. It now compares stored against actual first and
  answers `SET STATISTICS` when the two disagree.
- Reading a column's statistics no longer costs three scans: row count, non-null count and
  distinct count come from one pass, and the whole check is skipped with an honest "not verified,
  and here is what it would cost" on a table large enough for it to matter.

### Changed
- **`fb_suggest_indexes` now executes the query it is asked about** — once, inside the read-only
  transaction, and only when the plan actually shows a scan or a sort. It used to prepare the
  statement and read metadata. On a large table this turns a metadata call into a full scan, and
  it may additionally run one `COUNT(DISTINCT)` for a candidate column. Anyone calling it in a
  script will feel the difference; it is what the "the scan is the right plan" verdict rests on.
- Generated index names are sanitised and capped at 31 characters, so a long table and a long
  column no longer produce DDL Firebird refuses.

## [0.3.0] - 2026-08-06

Until this release every tool here answered a structural question: what the schema says, what
index exists, which access path the optimizer picked. That evidence constrains an explanation and
rarely confirms one, and a server that only ever answers structurally will answer confidently
about a problem that is not structural at all. The taxonomy behind this release is the one in
Cisar & Reeves, *Practical Firebird Performance Diagnostics* (IBPhoenix, 2026): classify the
problem first, then choose the reasoning, then choose the instrument.

Everything below stays inside the free edition's line — ordinary SQL over `MON$`, no service
attach, no file on the server.

### Added
- **`fb_sample_activity`** reads the `MON$` counters twice across a window and reports the
  difference: records read sequentially and by index, pages read/written/fetched/marked, record
  versions backed out, purged and expunged, back-version reads (3.0+), transactions started, and
  whether the transaction horizon moved at all. A snapshot cannot show accumulation, drift or
  workload phase; those live in the difference between two readings. Findings it can support and
  only those: a horizon that never moves while transactions keep starting, a window dominated by
  sequential reads, and version churn. An idle window says so instead of implying health.
- **`classify_problem`** prompt: starts from the symptom rather than from a tool. Places the
  problem on six axes (temporal shape, volume vs concurrency, locality, coordination vs execution,
  sensitivity to observation, environment), names the dominant class of the seven, maps it to the
  reasoning that converges on it, and says plainly when the dominant class is one an SQL
  connection cannot settle.
- **`fb_analyze_query` now measures what it analyzed.** A plain SELECT is executed once and the
  report adds the records the engine actually read (sequential and indexed), the pages it moved,
  its back-version reads, and a note when it read far more records than the query returned. "The
  plan uses an index" and "the query reads 400 000 records through that index" used to be the
  same report.
- **Every advisory tool now states what it does not rule out.** A clean answer to a narrow
  question reads as a clean bill of health to whoever relays it, and an assistant relaying it has
  no way to know the tool was blind. A plan cannot see contention; a schema audit cannot see where
  the concurrent work converges; one snapshot cannot see accumulation; `MON$` counts work
  performed and never time spent waiting for permission to perform it.

- Two regression tests for the encoding fixes below, since both defects were invisible to an
  all-ASCII suite: one round-trips an em dash out and `CITTÀ_UTENTI_€_日本` in, the other fails if
  any tool description ever shows the `â€` signature of a mis-decoded source again.

### Fixed
- **A statement that could write is no longer executed to measure it.** `fb_evaluate_goal`'s
  `query_time_ms` ran whatever SQL text it was handed in order to time it — including a `DELETE`.
  Read-only was a property of the tools, not of the SQL arriving from the caller. Both this goal
  and the new measurement in `fb_analyze_query` now refuse anything that is not a plain SELECT.
- **The server now attaches read-only, so the promise is Firebird's and not ours.** Inspecting the
  SQL before running it is a guess about what the engine will do with that text; every transaction
  the server opens carries the read-only TPB, and a write is refused by the engine no matter what
  got past the inspection. It also stops the server's own connection from standing in the way of
  garbage collection while it holds a sampling window open. The tools' own refusal stays, because
  a clear "this was not measured, and why" beats an engine error relayed to the user.
- **Every em dash this server writes reached you as `â€"`.** The `.pas` sources are UTF-8 without
  a byte order mark, and the Delphi compiler reads such a file in the machine's ANSI code page:
  the em dash was already three garbage characters at compile time, before anything was sent. It
  was in the description of all nine Enterprise tools and of `fb_generate_documentation` — the
  first thing an LLM reads about this server — in the `optimization_goal` prompt, in the
  transaction-monitor advisories, and beside every INACTIVE index in generated documentation.
  The sixteen affected sources now carry a BOM. Nothing else about them changed.
- Rebuilt against **mcp-server-delphi 0.8.2**, which forces UTF-8 on stdin/stdout and frames each
  message with a single LF. Before it, the transport wrote stdout in the console code page, so
  even a correctly compiled non-ASCII byte left as Windows-1252 and the client's UTF-8 decode
  rejected it. Accented table names, identifiers and comments now survive the wire intact.

### Changed
- The tool tables in all four READMEs said five Enterprise tools; there have been nine since
  0.2.4.

## [0.2.4] - 2026-07-17

### Added
- `fb_diagnose` and the long-window trace trio (`fb_trace_start`, `fb_trace_status`,
  `fb_trace_stop`) join the Enterprise stubs: nine Enterprise tools now appear in `tools/list`,
  each answering with how to get it rather than pretending to do nothing. The comparison tables
  in all four READMEs list all nine.

### Fixed
- A finding with no runnable remedy shipped an **empty SQL fence**. Not every advisory has a
  command behind it: the answer to "your page cache commits more RAM than this machine has" is a
  configuration change and a restart, not a statement. The fence now appears only when there is
  something runnable inside it.
- The server identity line at the top of all four READMEs still said **v0.1.0**, stale since
  0.2.0. It now states the version you actually downloaded.
- `.env.example` carried the maintainer's own port and file paths; copying it pointed the server
  at folders that exist on exactly one machine. It now shows the default port 3050 and
  placeholders that are obviously yours to fill in.
- The DUnitX core test for `fb_suggest_indexes` still asserted the pre-0.2.3 behaviour
  (`CREATE INDEX` over a column whose index is merely INACTIVE): it encoded the bug 0.2.3 fixed
  and failed on every engine. It now asserts the reactivation and that no second index is
  prescribed.

## [0.2.3] - 2026-07-13

### Fixed
- `fb_suggest_indexes` prescribed `CREATE INDEX` on a column that already had an index, when that
  index was **INACTIVE**. The plan says `CUSTOMERS NATURAL`, the advisor correctly refused to count
  a disabled index as usable, and then forgot the index existed: the advice was to build a second
  one beside the sleeping one. Two indexes over the same column, both written on every INSERT, one
  of them dead, and the one-statement fix never named. It now prescribes
  `ALTER INDEX IDX_CUST_CITY ACTIVE;` and says why the existing index is being ignored.
- The `## License` section claimed **Apache License 2.0**, contradicting the badge, the licensing
  chapter and the `LICENSE` file itself, all of which say PolyForm Internal Use 1.0.0 from v0.2.0.
  A reader who scrolled to the bottom was told the software may be redistributed. It may not.
- The comparison table advertised "Apply suggested DDL (opt-in, `firebird.allow_ddl`)" as shipping
  in both editions. No such tool and no such setting exist: all nine tools are read-only.
- The README named the milestone `M3` twice, as if the reader knew what it was.

### Added
- Italian, Spanish and German READMEs (`README-IT.md`, `README-ES.md`, `README-DE.md`), each linked
  from a language bar at the top of all four. Written as documents in their own language, not
  translated sentence by sentence.
- The release packages all four READMEs, each stripped of the build and test chapters at packaging
  time (marked in the source with `<!-- release:drop -->`, so the strip is language-independent).

## [0.2.2] - 2026-07-13

Documentation only — the code is 0.2.1. The 0.2.1 download shipped a README that could not be
followed, so it is withdrawn and replaced by this one.

### Fixed
- The README told the reader to `Copy-Item bin\.env.example bin\.env`, a path that exists only in
  a source checkout. In the download the exe and its `.env.example` sit in the folder you unzipped,
  with no `bin\` anywhere. Both layouts are now stated, and so is the fact that `.env.example` is a
  dotfile that Explorer and `ls` hide — it *is* in the zip.
- Half the MCP client recipes pointed at `...\app\bin\MCPFirebird.exe`. The exe is built to
  `bin\MCPFirebird.exe`; the `app\bin\` path never existed, so those examples registered a server
  the client could not start.
- "Connect it to an MCP client" said nothing about what connecting *is*. It is now "Install it into
  your AI agent", and explains that the agent spawns the executable itself and speaks to it over
  stdin/stdout — no service, no port.
- The download no longer carries the sections that only someone building from source can use (how
  to compile it, how to run a test suite whose fixtures are not in the zip). One README remains in
  the repository; the release strips those sections at packaging time.

## [0.2.1] - 2026-07-13

### Fixed
- `fb_suggest_index_drops` advised dropping a **DESCENDING** index as a duplicate of the ascending
  index over the same column — typically the primary key. Only the descending index serves
  `ORDER BY col DESC` and `MAX(col)` without a sort, so the advice took a working index away and
  turned the hottest query of a queue-shaped table into a scan and a sort. Index direction
  (`RDB$INDEX_TYPE`) is now read, and it is part of the identity a duplicate is judged by.
- `fb_monitor_transactions` contradicted itself inside one report — a header quoting one
  transaction gap over a finding quoting another. It read `MON$DATABASE` twice, and reading it
  costs transactions, so `MON$NEXT_TRANSACTION` moved between the two reads. The monitor now takes
  one snapshot and reports it.

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
