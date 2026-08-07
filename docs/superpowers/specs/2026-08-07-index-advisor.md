# Index Advisor — Design Spec (0.4.0)

- **Date:** 2026-08-07
- **Status:** **Implemented in 0.4.0.** Slices 0–5 all shipped in one release rather than
  separately. Three things were measured during implementation and came out differently from
  what this document assumed — they are recorded in §12 rather than edited into the text above,
  so the reasoning and the correction stay legible side by side.
- **Author:** Daniele Teti (with Claude)
- **Scope:** free edition only — ordinary SQL over an ordinary connection, no Services Manager, no file on the server
- **Touches:** `Firebird.IndexAdvisor`, `Firebird.PlanAnalyzer`, `Firebird.SchemaAudit`, `Firebird.Goal`, `Firebird.Capabilities`, `providers/FirebirdToolsU`

## 1. What is wrong with the advisor we ship today

`fb_suggest_indexes` finds `NATURAL` in the plan, extracts the predicate columns from the SQL with
a regex, and proposes `CREATE INDEX` for every one of them that has no index. It is right often
enough to be useful and wrong in four ways that a DBA notices immediately:

1. **It treats every NATURAL scan as a defect.** A scan that returns most of what it reads *is* the
   correct plan; an index there adds write cost on every INSERT and changes nothing.
2. **It never questions the statistics.** Firebird does not recalculate index selectivity by
   itself. An index that exists and is ignored may be ignored because the optimizer is reasoning
   about last year's data — and the advisor answers by building a second index beside it.
3. **It only knows one shape of index.** A predicate wrapped in a function (`UPPER(NAME) = ?`)
   cannot use a plain index at all, and a predicate narrowed by a constant (`STATUS = 'ACTIVE'`)
   is what partial indexes exist for.
4. **It says what to do, never why that shape.** "Create an index" is advice; "create this shape
   of index because your predicate looks like this, and here is what it will not cover" is help.

## 2. What the plan can and cannot tell us

Measured on Firebird 5.0.4 with `SET EXPLAIN ON` against the seeded test database:

| Query | Explained plan |
|---|---|
| `WHERE CITY = 'Rome'` | `Select Expression → Filter → Table "CUSTOMERS" Full Scan` |
| `WHERE UPPER(NAME) = 'CUST_1'` | `Select Expression → Filter → Table "CUSTOMERS" Full Scan` |

**Identical.** The `Filter` node never carries the predicate. The plan cannot tell us which column
was filtered, whether the predicate was wrapped in a function, or what constant it compared
against. Any design that hoped to read the candidate column out of the plan is dead on arrival.

What the explained plan *does* carry, and we currently throw away:

| Signal | Example | What it unlocks |
|---|---|---|
| Index name + match quality | `Index "IDX_CUST_NAME_CITY" Range Scan (full match)` | a composite index agreed on only its first segment (`partial match: 1/2`) is a finding we cannot make today |
| Join strategy | `Hash Join (inner)` over two `Full Scan`s | a join with no usable index, which the WHERE-column analysis misses entirely |
| Alias → table | `Table "ORDERS" as "O" Full Scan` | authoritative, replacing the hand-maintained `AliasMap` regex |

**Decision:** the plan says what the engine *did*; the SQL text says what the user *asked for*.
Two sources, each used only for what it actually knows. `TPlanResult.ExplainedPlan` — declared
since M1 and never filled — gets populated on 3.0+ (`SET EXPLAIN ON`), with the legacy plan as the
2.5 fallback.

`SET EXPLAIN ON` does not exist in 2.5's isql, and an unknown `SET` aborts the script that carries
it. `Firebird.PlanAnalyzer` therefore emits the line **only when `Ordinal >= 300`**, and the 2.5
path stays exactly what it is today. The table above was measured on 5.0.4; 3.0 and 4.0 print the
same tree in a slightly different dialect, which is why the parser must match on node keywords
(`Full Scan`, `Range Scan`, `full match`, `partial match`) and treat an unrecognised line as
unknown rather than as absence.

## 3. Evidence available, and what it costs

| Evidence | Source | Cost |
|---|---|---|
| Access path, index usage, match quality | `isql` + `SET PLANONLY ON` / `SET EXPLAIN ON` | one prepare, no execution |
| Records read vs rows returned | `Firebird.Activity.Measure` (0.3.0) | executes the SELECT once |
| Stored selectivity | `RDB$INDICES.RDB$STATISTICS` | metadata read |
| Actual selectivity | `SELECT COUNT(DISTINCT col)` — `Firebird.SchemaAudit.ActualSelectivity` | **a full scan of the column** |
| Predicate shape (column, function, constant) | the SQL text | free, and the only source |

The last two matter for the design. Actual selectivity is not free: it is a scan per column, so it
is computed **only for the one index that is a candidate for the query being analyzed**, never for
every index on the table.

**Two consequences that are behaviour changes, not refinements.**

`fb_suggest_indexes` does not execute anything today — it prepares the query for its plan and
reads metadata. Under this spec it executes the SELECT (through `Firebird.Activity.Measure`, so
`IsReadOnlySelect` and the read-only transaction both apply) and may additionally run one
`COUNT(DISTINCT)`. On a large table that turns a metadata call into two full scans. The tool
description must say so, the way `fb_analyze_query`'s already does.

The measurement pays for the guard: the records read by the query are also the cheapest available
estimate of how big this table is. When that number is large, the `COUNT(DISTINCT)` is skipped and
the advisory says *"the statistics may be stale; confirming costs a full scan of the column, so
run `SET STATISTICS INDEX x` if this table has seen a bulk load"* — an honest unknown instead of
an expensive certainty nobody asked for.

## 4. The remedy ladder

The single most important decision in this spec. Ordered by what the remedy leaves behind:

| | Remedy | Cost to run | What it leaves behind |
|---|---|---|---|
| 1 | `SET STATISTICS INDEX x` | reads the index; safe under concurrent load; no rebuild | a refreshed number, nothing structural |
| 2 | `ALTER INDEX x ACTIVE` — **only for an index that is INACTIVE** | rebuilds the index, and stores fresh statistics, so it includes rung 1 | the index that already existed |
| 3 | `CREATE INDEX …` | builds a new structure | **write cost on every INSERT/UPDATE/DELETE, forever** |

Rung 2 is not a general-purpose rebuild. Rebuilding an index that is already `ACTIVE` takes
`ALTER INDEX x INACTIVE;` followed by `ALTER INDEX x ACTIVE;`, and **between those two statements
the index does not exist for the optimizer** — every query that relied on it scans. That is a
production risk the advisor must never prescribe casually: for an active index with stale numbers
the remedy is rung 1, which is exactly what rung 1 is for.

The advisor must always propose the lowest rung that can explain the symptom. Today it starts at
rung 3. A stale-statistics problem "solved" at rung 3 leaves the database paying for writes
forever because a number needed refreshing.

**Rule:** no advisory may say *"the index is not used and that is correct"*, and no advisory may
say *"the NATURAL scan is the right plan"*, until the stored selectivity of the candidate index
has been compared against the actual one. Both conclusions are otherwise unproven — the optimizer
decides on the stored number.

### 4.1 Which index is the candidate, and which number is compared

An index can serve an equality predicate only when the column is its **leading segment**. The
existing detectors already work this way (`X.Columns[0]` in `Firebird.IndexAdvisor`,
`Length(X.Columns) = 1` in `Firebird.SchemaAudit`), and the spec keeps the rule explicit because
the stale-statistics comparison depends on it:

- `RDB$INDICES.RDB$STATISTICS` is the selectivity of the **whole key**. Comparing it against
  `1 / COUNT(DISTINCT leading_column)` is comparing two different quantities as soon as the index
  has more than one segment.
- Per-segment selectivity lives in `RDB$INDEX_SEGMENTS.RDB$STATISTICS` (2.0+). For a composite
  index the comparison uses the segment row for the leading column; for a single-segment index
  either source is the same number.
- `Firebird.SchemaAudit.ActualSelectivity` today computes `1 / COUNT(DISTINCT col)` and skips
  composites entirely. Extending it to read `RDB$INDEX_SEGMENTS` is part of slice 1; until it is
  done the advisor must **stay silent about composites** rather than compare the wrong pair.
- `COUNT(DISTINCT col)` ignores NULLs while the index does not. On a mostly-NULL column the two
  numbers disagree for a reason that is not staleness, so a column whose NULL fraction is high is
  reported as "not comparable", not as stale.

## 5. Decision tree

For each table the plan reports as fully scanned, and each predicate the SQL applies to it:

"Covers the column" always means **the column is the index's leading segment** (§4.1).

```
predicate on a table the plan scans
├── an index covers the column, INACTIVE          → rung 2: ALTER INDEX ACTIVE   (rebuilds + refreshes stats)
├── an index covers the column, ACTIVE but unused
│   ├── selectivity not comparable                → info: composite, or a mostly-NULL column, or the
│   │   (composite / NULL-heavy / table too big)     check would cost a full scan — say so, suggest rung 1
│   ├── stored selectivity far from actual        → rung 1: SET STATISTICS INDEX, then re-measure
│   └── statistics are current                    → info: the optimizer weighed it and declined; here is what it read
├── no index covers the column
│   ├── the scan returns most of what it reads    → info, no SQL: the scan is the correct plan
│   ├── predicate is an expression, F(col) = …    → rung 3, expression index: CREATE INDEX … COMPUTED BY (F(col))
│   ├── predicate is narrowed by a literal equality, and the engine is 5.0+
│   │                                             → rung 3, partial index, offered beside the plain one
│   └── otherwise                                 → rung 3, plain B-tree
└── anything the extractor cannot read confidently → silence
```

"Far from actual" reuses the threshold the stale-statistics detector already ships:
`Abs(stored − actual) > actual × 0.5`. One constant, one meaning, two callers — it moves to a named
constant shared by `Firebird.SchemaAudit` and the advisor rather than being written twice.

### 5.1 When the yield rule must not fire

"The scan returns most of what it reads, so the scan is right" is the only rule in this spec that
**silences** an advisory, which makes it the one that has to be attacked hardest. It is unsound in
five situations, and in each the advisor falls back to today's behaviour rather than staying quiet:

1. **The statement has unbound parameters.** Measured against the shipped 0.3.0 build:
   `SELECT * FROM CUSTOMERS WHERE CITY = ?` reports `Measured: 0 row(s)` over 5004 sequential
   reads, because FireDAC binds an unset parameter as NULL and `CITY = NULL` matches nothing. The
   plan is honest — a prepare needs no values — but the measurement describes a query nobody runs,
   and a yield of 0/5004 would read as the strongest possible case for an index. **A statement
   carrying parameters is not measured at all**, and the report says why. *(This is a defect in
   0.3.0's `fb_analyze_query`, not only a rule for this spec: it currently prints that 0 as though
   it meant something. It ships as a fix before slice 1.)*
2. **The plan contains an external SORT.** There the index earns its place by removing the sort,
   not by reading fewer records, and yield is 100% by construction.
3. **More than one table is fully scanned.** `Firebird.Activity.Measure` counts records for the
   whole statement; with a hash join over two scans, the reads cannot be attributed to either
   table. No attribution, no silence. (Firebird 5.0's profiler reports rows per record source and
   would settle it — a later milestone, named here so the limit is not mistaken for an oversight.)
4. **The query is an aggregate.** `SELECT COUNT(*) … WHERE CITY = 'Rome'` returns one row from
   thousands: a yield near zero that says nothing about whether an index helps. The rule is applied
   **per candidate predicate**, never to the shape of the result set, and a query with no candidate
   predicate produces no verdict at all — not even the reassuring one.
5. **The measurement did not happen.** Non-SELECT statements, engines without MON$, a refused
   execution: absence of a measurement is not evidence of a healthy plan.

### 5.2 Index shapes and when each is right

| Predicate in the query | Shape | Why |
|---|---|---|
| `CITY = ?` | plain B-tree | — |
| `UPPER(NAME) = ?`, `EXTRACT(YEAR FROM D) = ?` | `COMPUTED BY (expr)` | the index stores the value; the query asks for the result of the function. A plain index on `NAME` can never serve it |
| `STATUS = 'ACTIVE' AND EMAIL = ?` | `ON (EMAIL) WHERE STATUS = 'ACTIVE'` | indexes only the population that is actually queried: smaller, cheaper to maintain |
| scan returns most of what it reads | none | an index adds write cost and changes nothing |

**Recognising each shape from the text, without becoming a parser.**

- *Expression.* The function must wrap the **column**, not the constant: `UPPER(NAME) = 'X'` needs
  an expression index, `NAME = UPPER('x')` needs a plain one, and a regex that does not care which
  side it matched will prescribe the wrong index with full confidence. The expression is captured
  by scanning from the function name to its **balanced** closing parenthesis — `SUBSTRING(NAME FROM
  1 FOR 3)` and `EXTRACT(YEAR FROM D)` are not `f(a, b)` and a comma-counting matcher mangles both.
  If the parentheses do not balance, or the expression contains a subquery, the advisor is silent.
  The captured text is emitted **verbatim**: normalising it produces an index the optimizer will
  not match.
- *Partial.* The filter predicate is the one comparing a column to a **literal**; the seek column is
  another predicate on the same table. The advisor offers a partial index only when there is
  **exactly one** literal-equality predicate and at least one other predicate: with two literals it
  cannot tell which one narrows the population without measuring cardinality, and guessing wrong
  produces an index that indexes nearly the whole table while pretending to be selective. Ambiguous
  means silent.
- *Neither.* A column with a case-insensitive collation makes `UPPER(col)` redundant, and we cannot
  see that cheaply. The expression index we suggest there is not wrong, only unnecessary — worth a
  line in the Finding, not a detector.

### 5.3 Version gating

| Feature | Available from | Capability flag |
|---|---|---|
| Expression index (`COMPUTED BY`) | **2.0** — the whole supported matrix, no gate needed | `HasExpressionIndexes` (declared for clarity, always true here) |
| Partial index (`WHERE`) | **5.0** | `HasPartialIndexes := Ordinal >= 500` |
| Explained plan | 3.0 | `HasExplainedPlan` (exists) |

On 2.5–4.0 a predicate that would justify a partial index gets the plain B-tree, plus one line
saying 5.0 would allow a partial one. That line is honest advice and a migration argument.

## 6. What every advisory must state

Beyond the existing `TAdvisory` contract (Finding / SQL / Verify / Severity):

- **The measured justification.** "Reads 5004 records to return 1250" is the reason; "the plan says
  NATURAL" is only the symptom.
- **The shape, and why that shape.** Requested explicitly: partial or plain B-tree is not a detail
  the reader should have to infer from the SQL we emit.
- **How the shape can fail to be used.**
  - *Expression:* Firebird uses the index only when the expression in `WHERE` / `ORDER BY` /
    `GROUP BY` **exactly matches** the index definition. `UPPER(NAME)` and `UPPER(TRIM(NAME))` are
    different indexes. The expression is therefore emitted **verbatim from the query**, never
    normalised. Multi-segment expression indexes do not exist: one expression per index (it may
    involve several columns).
  - *Partial:* the optimizer requires the statement's `WHERE` to contain the same boolean
    expression — implication is not enough. The language reference names exactly three usable
    cases: the same boolean expression appears in the statement; the index condition is a set of
    `OR`ed expressions and one of them appears explicitly; or the index condition is `IS NOT NULL`
    and the statement carries an expression on that field that excludes NULLs. Anything else,
    however obviously implied, does not use the index. An application that also queries
    `STATUS = 'CLOSED'` gets no help from this index for those queries.
  - *Partial + expression together:* the language reference documents `WHERE` with a column list
    and `COMPUTED BY` separately, and never the two combined. The advisor **does not emit that
    combination** until it has been tested against a real 5.0 engine; if the test shows it works,
    it becomes a separate slice.
  - *SET STATISTICS:* not a permanent fix. Under concurrent load the fresh statistics can be
    outdated as soon as the statement finishes; on a churning table the answer is a scheduled job,
    not a one-off. It also requires administrator, table owner, or `ALTER ANY TABLE` — if the
    configured user is none of those, the statement will fail.

## 7. The goal loop

`fb_evaluate_goal` and the `optimization_goal` prompt currently iterate measure → suggest index →
re-measure. Two changes:

1. When `query_no_natural_scan` is not met and a candidate index exists with stale statistics, the
   `iteration_hint` names rung 1 first. The loop must make the non-destructive move before the
   permanent one.
2. A new goal type **`no_stale_index_statistics`** for a table, mirroring `no_redundant_indexes`:
   measured = the number of indexes whose stored selectivity differs materially from actual;
   met when zero. It gives the loop a first move that writes nothing structural.

`query_no_natural_scan` stays literal — it is a goal about the plan, and redefining it would break
a published contract — but its hint carries the yield, so the loop can stop honestly with "the scan
is the right plan here" instead of iterating toward an unreachable state.

## 8. Thresholds, and why they are printed

Every threshold here is a heuristic, so the Finding always carries **the numbers it was applied
to**. A DBA who disagrees with 20% can then disagree with the threshold instead of with the tool.

| Constant | Value | Reasoning |
|---|---|---|
| `YIELD_FLOOR` | 0.20 | above it, the scan keeps at least a fifth of what it reads, and a B-tree walk to fetch the same rows is unlikely to pay for the write cost it adds |
| `SCAN_FLOOR` | 5 000 records read | below it the whole table is a handful of pages: an index changes nothing measurable and costs every INSERT |
| `STALE_FACTOR` | 0.5 | already shipped in the stale-statistics detector; reused, not re-invented |
| `BIG_TABLE_READS` | 1 000 000 records read | above it, `COUNT(DISTINCT)` is refused and the advisory reports an honest unknown (§3) |

## 9. Slices and acceptance

Each is independently releasable and independently green on all four engines.

| # | Slice | Depends on | Done when |
|---|---|---|---|
| 0 | Parameterised statements are not measured (§5.1) | — | `fb_analyze_query` on `… WHERE CITY = ?` reports the plan and *"not measured: unbound parameters"*, and never a row count |
| 1 | Yield-aware silence + statistics check before any "this is correct" verdict | 0 | on the same engine, a low-yield query still yields `CREATE INDEX`, a high-yield one yields `info` with no SQL, and an existing-but-ignored index with stale numbers yields `SET STATISTICS` **before** any `CREATE` |
| 2 | Expression indexes | 0 | `WHERE UPPER(NAME) = 'X'` yields `COMPUTED BY (UPPER(NAME))` verbatim; `WHERE NAME = UPPER('x')` yields a plain index; `SUBSTRING(NAME FROM 1 FOR 3)` is captured whole or refused |
| 3 | Partial indexes + `HasPartialIndexes` | 2 | on 5.0 the skewed fixture yields the partial form and re-planning shows the engine using it; on 2.5–4.0 the same fixture yields the plain B-tree plus the 5.0 note |
| 4 | Explained plan: match quality, join strategy, alias map from the engine | — | a composite index agreed on one segment of two is reported; the two-scan hash join is reported; `AliasMap`'s regex is deleted, not merely bypassed |
| 5 | An index for the **SORT** (§9.1) | 2, 4 | `ORDER BY` on an unindexed column with an external sort in the plan yields an index whose segments match the ORDER BY, in its direction; a `FIRST n` query says why the win is largest there; mixed directions are refused with the reason |

### 9.1 The sort nobody advises on

`fb_analyze_query` has flagged external `SORT` since M1, and `fb_suggest_indexes` has never once
suggested an index for one: its extractor only looks at comparison operators, so `ORDER BY`,
`GROUP BY` and `DISTINCT` are invisible to it. The spec's own yield rule (§5.1) already leans on
this gap — it refuses to silence a query whose plan sorts, precisely because an index there earns
its place by removing the sort rather than by reading fewer records. Nothing then offers that
index.

What makes this its own slice rather than a variation of the others:

- **Direction is part of the index.** Firebird cannot walk an ASC index backwards to serve
  `ORDER BY x DESC`; that needs a `DESCENDING` index. And `ORDER BY a ASC, b DESC` cannot be served
  by any single index — the advisor states that instead of prescribing one that will not be used.
- **The segments must match the ORDER BY, in order.** The same leading-segment rule as §4.1, but
  applied to a list rather than to one column.
- **Removing a sort is not automatically a win.** A navigational plan fetches rows in index order,
  which is random page access; on a query that returns most of the table, scan-then-sort beats it.
  The yield reasoning of §5.1 applies here inverted, and the Finding must say so rather than
  presenting the index as free.
- **`FIRST n` / pagination is where it pays most**, because the sort it removes is a sort of the
  whole result set to return twenty rows. Worth naming in the Finding: it is the case where a DBA
  recognises their own screen.
- **Expression indexes serve sorts too.** The language reference puts `ORDER BY` and `GROUP BY`
  beside `WHERE` in the exact-match rule, so `ORDER BY UPPER(NAME)` wants
  `COMPUTED BY (UPPER(NAME))` — which is why this slice comes after slice 2.

Slice 0 is a bug fix and ships on its own. Slices 1 and 2 are the value; 3 is the 5.0 headline;
4 unlocks detectors that cannot be written today.

**Two-repo obligation.** No slice adds an `fb_*` tool, so `FREE_TOOLS` is unchanged — but slice 1
adds the `no_stale_index_statistics` goal type and changes what `fb_suggest_indexes` returns. Any
assertion that lands in `tests/test_mcp_firebird_full.py` is executed verbatim by the Enterprise
repository against its own binary. **New fixtures are therefore asserted in the DUnitX core suite
only**; the shared Python suite gains, at most, assertions that hold against the seed both
repositories already have.

## 10. Fixtures

The existing seed cannot express any of this: every column of `CUSTOMERS` is already indexed one
way or another, so there is no unindexed column to scan and no honest high-yield case.
`tests/seed/problems.sql` gains one table, built so that each new rule has both a positive and a
negative case:

```sql
CREATE TABLE SKEWED (
  ID       INTEGER NOT NULL PRIMARY KEY,
  STATE    VARCHAR(10),   -- 90% 'CLOSED', 10% 'ACTIVE'; no index
  TAG      VARCHAR(20),   -- ~1% per distinct value; no index
  LABEL    VARCHAR(40)    -- queried through UPPER(); no index
);
```

| Rule under test | Positive case | Negative case |
|---|---|---|
| yield silence | `WHERE STATE = 'CLOSED'` → 90% yield → `info`, no SQL | `WHERE TAG = 'T42'` → ~1% yield → `CREATE INDEX` |
| expression index | `WHERE UPPER(LABEL) = 'X'` → `COMPUTED BY` | `WHERE LABEL = UPPER('x')` → plain index |
| partial index (5.0) | `WHERE STATE = 'ACTIVE' AND TAG = ?` → partial on `(TAG)` | same query on 2.5–4.0 → plain index + the 5.0 note |
| stale statistics | bulk insert after `SET STATISTICS`, then a query whose index is ignored → `SET STATISTICS` first | freshly rebuilt index → `info`, the optimizer declined on current numbers |

`docs/firebird-problem-catalog.md` gains one row per new detector, mapping it to the fixture and
the milestone, as the conventions require.

**Test determinism.** Record counts are not identical across engines — a scan of the 5000-row seed
measures 5004 sequential reads on 5.0.4, and the surrounding numbers differ again on 2.5. Every
assertion is therefore a relation or a range (`reads > rows * 3`, `advisory mentions SET
STATISTICS`), never an exact count. The one exception is row counts returned by a query, which are
a property of the data and not of the engine.

**What CI cannot prove.** That fresh statistics stay fresh under concurrent load (their own
documentation says they may not), and that a partial index helps a real workload rather than the
one query we re-plan. Both are stated in the advisories rather than tested.

## 11. Limits, stated deliberately

- The predicate extractor handles a column, or one function around a column, compared to a literal
  or a parameter. Nested expressions, `CASE`, correlated subqueries and `OR` trees are **not**
  parsed: the advisor stays silent rather than emitting a confident wrong index. This is not a SQL
  parser and must not grow into one.
- Actual selectivity costs a full scan of the column; it is computed for candidates only.
- Everything here reasons about one query at a time. An index that serves this query and hurts
  three others is invisible to this design — the workload-level view belongs to a later milestone.
- `fb_suggest_indexes` becomes a tool that **executes** the query it is asked about. Anyone calling
  it on a large table in a script will feel the difference, so it belongs under **Changed** in the
  changelog, not buried in a feature bullet.
- The advisor still answers about the query it was handed, and a DBA rarely has just one. The
  honest framing in every Finding stays the one 0.3.0 introduced: this is what the check saw, and
  this is what it could not see.

## 12. What the implementation measured, and where this document was wrong

Three corrections, all found by running the thing against real engines rather than by re-reading
the plan.

**Firebird prints match quality in three dialects, not one.** §2 quotes `partial match: 1/2`.
Measured on 5.0.4, the same tree also prints `full match`, `lower bound: 1/1` and
`lower bound: 2/2, upper bound: 1/2` — a range scan quotes one fraction per bound, and reading
only the first one reports a fully used index as half used. The parser therefore takes the
**widest** fraction printed for an index and compares it with the total, which makes all three
dialects agree.

**The optimizer almost never declines an available index on a single table.** §5's branch for "an
index covers the column, ACTIVE but unused" was expected to be the common stale-statistics case.
It is not: with a sargable equality and stored selectivity forced to 1.0 (every row identical, the
worst possible figure), 5.0 still chose `PLAN (PROBE1 INDEX (IDX_PROBE1_K))` over the scan. The
branch is reachable and correct — a leading-wildcard `LIKE` or a hash join gets there, and that is
what the core suite exercises — but the statistics check earns its place mainly through
`fb_audit_table` and the new goal, not through this branch. Worth knowing before anyone tunes the
thresholds around it.

**`AliasMap`'s regex could not be deleted.** Slice 4's acceptance says the hand-maintained alias
regex goes away, replaced by the engine's own pairing. On 2.5 there is no explained plan and the
legacy `PLAN` line prints aliases with nothing to resolve them against, so the regex is the only
alias map that engine has. It stays as the 2.5 path and is **overridden** by the engine's map from
3.0 up. The acceptance criterion was written without checking what deleting it would cost the
oldest supported engine.

One deliberate deviation, decided rather than discovered: §3 says `fb_suggest_indexes` executes
the query it is asked about. It does — **but only when the plan actually shows a scan or a sort**.
A query whose every table is already reached through an index costs what it always cost: one
prepare and some metadata reads. There is no advice to give, so there is nothing to measure.
