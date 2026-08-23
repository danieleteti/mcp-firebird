# Tool reference

[← back to the README](../README.md)

The full catalogue: what every tool does, how the index advisor decides, the prompts and the
resource, plus the raw `tools/call` shapes if you drive the server yourself.

## The tools (16 free, plus 9 Enterprise announced in `tools/list`)

| Tool | Arguments | Purpose |
|---|---|---|
| `fb_info` | *(none)* | Engine version + detected capabilities (JSON) |
| `fb_list_tables` | *(none)* | List user tables |
| `fb_generate_documentation` | `table_name?` | Markdown docs for one table — columns (with the **domain** each is built on), PK, indexes, **CHECK constraints**, triggers with the event they fire on — or for the whole database, which also lists **views with their SELECT**, stored procedures with their parameters, functions and packages (3.0+). Given a view's name it documents the view |
| `fb_query` | `sql`, `max_rows?` | Runs a read-only SELECT and returns the rows as a Markdown table, capped at `max_rows` (default 100, ceiling 1000) **and at ~20 000 characters**, because a row cap bounds rows and not width. Anything that is not a plain SELECT is refused, and so is a statement with unbound placeholders |
| `fb_analyze_query` | `sql` | Access-plan analysis (NATURAL-scan + external-SORT detection), the engine's **explained plan** on 3.0+ (index names, match quality, join strategy) **and measured cost**: a plain SELECT is executed once and the records and pages it really touched are reported |
| `fb_suggest_indexes` | `sql` | Index advice for one query: plain B-tree, **expression** (`COMPUTED BY`), **partial** (5.0+) or an index for the **sort** — and **no index at all** when the scan is the correct plan. Refreshes stale statistics before proposing anything structural |
| `fb_suggest_index_drops` | `table_name` | Flags duplicate / redundant-prefix / inactive / low-selectivity indexes |
| `fb_audit_table` | `table_name` | Schema-health audit: missing PK, over-indexing, stale statistics |
| `fb_suggest_grants` | `user_name`, `object_pattern?`, `access?`, `role_name?`, `exclude_pattern?` | The statements that give one account access to the objects matching a pattern **and nothing else**: a conditional `CREATE USER`, a role, the `GRANT`s generated from the catalogue with identifiers quoted only where Firebird needs it, and the role granted in the form this version supports (`GRANT DEFAULT` on 4.0+; below that, a note that the connection must pass the role or the grants are inert). Then it checks the claim: PUBLIC grants and grants the account already holds outside the plan come back as findings with the `REVOKE` that closes them |
| `fb_audit_security` | *(none)* | Every grant recorded in the database, one line per grantee and object, plus the three findings that are usually mistakes: privileges held by **PUBLIC** (critical when they include writes), delegation via **WITH GRANT OPTION**, and roles nobody is a member of |
| `fb_evaluate_goal` | `goal_type`, `target`, `threshold` | Deterministic goal check (drives the optimization loop) |
| `fb_monitor_transactions` | `stale_minutes?` | Transaction/sweep health **at this instant**: OIT/OAT/Next gap, blocking long-running transactions (with their last SQL statement) |
| `fb_sample_activity` | `seconds?` | Reads the MON$ counters twice over a window and reports the difference: records read sequentially and by index, pages moved, versions collected, and whether the transaction horizon advanced |
| `fb_monitor_attachments` | `idle_minutes?`, `long_statement_seconds?` | Who is attached right now, from where and what each one is running; flags attachments idle beyond `idle_minutes` (default 30) and statements running beyond `long_statement_seconds` (default 60). It cannot see contention: MON$ counts work performed, never time spent waiting to perform it |
| `fb_backup_start` | *(none)* | Starts a `gbak` backup into `firebird.backup_dir` and **returns before the backup does**. The job then restores what it wrote into a scratch database and deletes it again |
| `fb_backup_status` | *(none)* | The running or last backup: phase, size, how long each stage took, and whether the backup was proved restorable |

### What the backup needs, and what it proves

A backup nobody has restored is a file, not a backup. So the job does not stop at writing the
`.fbk`: it restores it into a scratch database with `gbak -c` (which creates, and refuses an
existing file), checks the database arrived, and throws it away. `fb_backup_status` says
*"this backup restores"*, not *"a file exists"*.

Three things it needs, all of them yours to arrange:

- **`firebird.backup_dir`** in the `.env`. The destination is declared once, there, and is never
  taken from the caller — the tools take instructions from whatever is talking to the server.
- **`gbak.exe` beside your `fbclient.dll`.** The server drives a *local* client tool, the same
  way plan analysis drives a local `isql.exe`. It never attaches to the Services Manager.
- **Room for a second copy of the database** on that disk, for as long as the verification
  restore runs.

One backup at a time: `fb_backup_start` refuses while one is running, and tells you to poll
instead. And what it cannot tell you: whether the backup is *off this machine*. A backup proved
restorable, sitting on the same disk as the database it came from, survives a corrupt page and
not a lost disk.

Every advisory comes with a **Finding**, ready-to-run **SQL**, and a **Verify** step. Every
analysis tool also closes with **what it does not rule out**: a plan cannot see contention, a
snapshot cannot see accumulation, and a clean answer to a narrow question is not a clean bill
of health.

## What `fb_suggest_indexes` decides, and in what order

An index is not free: it is written on every INSERT, UPDATE and DELETE into that table, for as
long as it exists. So the advisor proposes the **cheapest remedy that explains what the plan
did**, and it is willing to propose nothing at all.

1. **Refresh, don't build.** Firebird stores an index's selectivity when the index is created
   and never recalculates it. An index that exists and is ignored may be ignored because the
   optimizer is costing it against last year's data — and answering that with a second index
   leaves the database paying for writes forever because a number needed refreshing. Nothing
   here says *"the index is not used, and that is correct"* until the stored figure has been
   compared with the real one.
2. **Wake, don't duplicate.** An `INACTIVE` index over the column the query filters by is
   `ALTER INDEX … ACTIVE`, never a second index beside the sleeping one.
3. **Say when the scan is right.** The query is executed once and the records it read are
   compared with the rows it returned. A scan that keeps most of what it reads *is* the correct
   plan, and so is a scan of a table small enough to be a handful of pages: both come back as a
   finding with the numbers and **no SQL to run**.
4. **Then, the right shape.** `UPPER(NAME) = ?` cannot use a plain index at all and gets an
   expression index, with the expression emitted exactly as written — Firebird matches it only
   on an exact match. `STATE = 'ACTIVE' AND TAG = ?` gets an index on what it seeks by, plus the
   partial form on 5.0+, which indexes only the population the query looks at. `ORDER BY` on an
   unindexed column gets an index whose segments match it **in its own direction** — and a plain
   statement that no single index serves `ORDER BY a ASC, b DESC`, rather than one that would
   never be used.

Every finding carries the numbers the rule was applied to, so a DBA who disagrees with a
threshold can disagree with the threshold rather than with the tool. The design and the
measurements behind it are in
[`docs/superpowers/specs/2026-08-07-index-advisor.md`](superpowers/specs/2026-08-07-index-advisor.md).

> **Note:** to measure, this tool **executes the query** it is asked about — once, inside the
> read-only transaction, and only when the plan actually shows a scan or a sort. On a large
> table that is a full scan. It never executes anything that is not a plain SELECT, and it does
> not execute a statement with unbound parameters at all: those bind as NULL, match nothing, and
> would produce a measurement of a query nobody runs.

## What `fb_audit_security` sees, and what it cannot

Grants live in the database: `RDB$USER_PRIVILEGES` and `RDB$ROLES`, readable over an ordinary
SQL connection, which is exactly what the free edition is. So the report is complete about
*grants* — and silent about everything a grant is not. Two kinds of row are left out, because
nobody granted them and listing them buries the ones somebody did: the engine's own privileges
on `RDB$`/`MON$`, and what every object's owner holds on its own objects.

It cannot see the **account list**, the **admin roles**, the password policy or who can reach the
port at all: those live in the security database and in the server configuration, and reading
them means an administrative attach this edition does not make. A database whose every grant is
correct can still be reachable by an account nobody remembers creating.

Three findings, in the order they matter:

1. **PUBLIC.** Not a group somebody was added to: everyone who can attach, including accounts
   created after the grant was made. `critical` when the privileges include INSERT, UPDATE or
   DELETE, `warning` otherwise.
2. **WITH GRANT OPTION.** The holder can widen access with no DBA involved, and the grant that
   results is indistinguishable from one an administrator made.
3. **A role with no members.** Either the privileges it carries are unused, or the accounts that
   should hold them are holding direct grants instead.

## Prompts (4)

- **`optimization_goal`**, the goal-driven loop: set an objective, the assistant iterates the
  `fb_*` tools and re-checks `fb_evaluate_goal` until it reports `met: true` (with a
  max-iterations / no-progress safety stop).
- **`app_user_plan`**: the one prompt that starts from a decision nobody has made yet. Most
  Firebird applications connect as SYSDBA, and that is not a privilege problem — it is a database
  where privileges do not apply, because SYSDBA is not subject to them and neither is the owner
  of an object. So the prompt looks first (engine version, object names, what PUBLIC already
  holds), asks only what the catalogue cannot answer, and ends in `fb_suggest_grants` rather than
  in GRANTs an assistant made up. If the answers do not come, it offers the fallback instead of
  stalling: an account with DML on every table still cannot drop a table, alter the schema, read
  the security database, create accounts or shut the server down.
- **`health_check`**: guided whole-database health review — indexes table by table, then the
  grants in one pass, and it says where the grant half stops.
- **`classify_problem`**: starts from the symptom, not from a tool. Places the problem on six
  axes (temporal shape, volume vs concurrency, locality, coordination vs execution,
  sensitivity to observation, environment), names the dominant class of the seven, and says
  which reasoning converges on it — including when the answer is that an SQL connection
  cannot settle it. Follows the taxonomy in Cisar & Reeves, *Practical Firebird Performance
  Diagnostics* (IBPhoenix, 2026).

## Resources (1)

- **`firebird://schema`**: the live database schema as a single resource.

---

## Calling the tools directly

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

// What changed over the last 10 seconds (a window, not an instant)
{ "name": "fb_sample_activity", "arguments": { "seconds": 10 } }

// Goal check: "this query must no longer do a NATURAL scan"
{ "name": "fb_evaluate_goal",
  "arguments": { "goal_type": "query_no_natural_scan",
                 "target": "SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'",
                 "threshold": 0 } }
```

`fb_evaluate_goal` `goal_type` values: `query_no_natural_scan`, `query_time_ms`,
`no_redundant_indexes`, and `no_stale_index_statistics` — the one whose first move writes
nothing structural: it counts the indexes on a table whose stored selectivity no longer
describes the data, so the loop can tell the optimizer the truth before it asks the database to
carry another index. See
[`docs/firebird-problem-catalog.md`](firebird-problem-catalog.md) for every problem the
tools detect, the fixture that provokes it, and the milestone it lands in.

### Enterprise tools

These nine appear in `tools/list` here too, so your assistant knows they exist and can tell you
what it would do with one. Calling them in this edition returns an `isError` result explaining
how to get them. They are implemented in the [Enterprise edition](editions.md#enterprise-edition), which
attaches to the Services Manager as an administrator and reads the server's configuration and
hardware: privileges this edition never asks for.

| Tool | Arguments | What it does |
|---|---|---|
| `fb_diagnose` | *(none)* | Start here when something is wrong and you do not know why: what is already known, what to ask, and the route to follow |
| `fb_analyze_config` | *(none)* | Reads `firebird.conf` and `databases.conf` and reports every setting that matters (page buffers, `TempCacheLimit`, `LockHashSlots`, `MaxUnflushedWrites`, `GCPolicy`, parallel workers) against *this* engine version and *this* server architecture, since the defaults and even the existence of a parameter change across both |
| `fb_analyze_storage` | `table_name?` | The physical picture no `SELECT` can show: index depth, page fill ratios, record-version chain length, page distribution |
| `fb_parse_log` | *(none)* | Streams `firebird.log` back over the Services API and separates the noise from what matters: bugchecks, page corruption, I/O errors, sweeps that ran, or never did |
| `fb_capture_trace` | *(none)* | Opens a bounded Trace API session, samples the real workload, and ranks the statements that actually cost, as a latency distribution, not an average |
| `fb_trace_start` | `duration_seconds?` | Opens the long window: up to two hours of Trace API capture, drained to disk in the background while the call returns at once |
| `fb_trace_status` | *(none)* | Reports the running capture: elapsed against duration, bytes captured, and whether the session is still watching |
| `fb_trace_stop` | *(none)* | Stops the capture, or retrieves a finished one, and returns the same ranked report as `fb_capture_trace`, over hours instead of seconds |
| `fb_analyze_host` | `config_dir?` | The engine against its hardware: RAM versus the memory the configuration actually commits, core count versus `MaxParallelWorkers` and `CpuAffinityMask`, free space versus the size of the database, and whether the pages it misses cost a seek |

Plus the part that makes them a product rather than a report: **baselines and experiments.** Take a
measurement under real load, change one parameter, take another, and get a verdict on whether the
tail moved, with a rollback if it did not.

Firebird's documentation states no optimal value for most of these parameters, and neither will we.
What the Enterprise edition brings is the map from a symptom to the parameter that explains it, and
a harness that proves the change worked on your database.
