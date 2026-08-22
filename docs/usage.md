# Worked examples

[← back to the README](../README.md)

What the conversation actually looks like once the server is registered, from "which tables do I
have" to a full optimization round-trip on the stock `employee.fdb`.

## Using it from Claude

Once the server is registered, you talk to Claude in plain language. It picks the right `fb_*`
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

→ **`fb_analyze_query`** → *"⚠️ NATURAL scan on CUSTOMERS: the filtered column `CITY` is not
usefully indexed."*

> **You:** Suggest an index that fixes it.

→ **`fb_suggest_indexes`** → a ready-to-run statement plus how to verify:

```sql
CREATE INDEX IDX_CUSTOMERS_CITY ON CUSTOMERS (CITY);
-- Verify: re-run fb_analyze_query; the NATURAL scan on CUSTOMERS should be gone.
```

> **You:** And this one? `SELECT * FROM ORDERS WHERE TOTAL > 100`

→ **`fb_suggest_indexes`** → *"Table ORDERS is scanned when filtered by TOTAL, and that is the
right plan: the scan returns 93% of what it reads (4650 of 5004 records)."* No SQL, because
there is nothing worth running: an index here would be maintained on every INSERT and would
save nothing.

> **You:** And this one? `SELECT * FROM CUSTOMERS WHERE UPPER(NAME) = 'ACME'`

→ **`fb_suggest_indexes`** → *"a plain index on `NAME` can never serve it: the index stores the
column, the query asks for the result of the function"*, and

```sql
CREATE INDEX IDX_CUSTOMERS_UPPER_NAME ON CUSTOMERS COMPUTED BY (UPPER(NAME));
```

> **You:** And this one? `SELECT * FROM CUSTOMERS ORDER BY CITY`

→ **`fb_analyze_query`** flags an **external SORT** (no usable index for the ordering), and
**`fb_suggest_indexes`** now answers it: an index on `(CITY)` in the direction the query asks
for, with a warning when reading most of a table through an index would cost more than the sort
it removes.

### 4. Clean up redundant indexes

> **You:** Which indexes on ORDERS can I safely drop?

→ **`fb_suggest_index_drops`** → flags `IDX_ORDERS_CUSTOMER_DUP` as a duplicate of the
system foreign-key index, with the `DROP INDEX` statement and a verify step.

> **You:** Do the same for CUSTOMERS.

→ flags the redundant left-prefix (`IDX_CUST_NAME`), the inactive index (`IDX_CUST_CITY`) and
the low-selectivity index (`IDX_CUST_STATUS`).

### 5. Audit schema health

> **You:** Audit the NOPK_LOG table.

→ **`fb_audit_table`** → *"🛑 critical: Table NOPK_LOG has no PRIMARY KEY …"* with the
`ALTER TABLE … ADD CONSTRAINT` fix. On `OVERIDX` it reports over-indexing; on `STALE_T` it
reports stale statistics with the `SET STATISTICS INDEX …` fix.

> **You:** Run a full health check on the database.

→ Claude uses the **`health_check`** prompt: `fb_info` → `fb_list_tables` → `fb_suggest_index_drops`
per table → a single summary grouped by table with all the ready-to-run SQL.

### 6. Goal-driven optimization (iterate until met)

The **`optimization_goal`** prompt makes Claude loop: measure → suggest → re-measure, stopping as
soon as the goal is met (or it can't improve).

> **You:** Use the optimization_goal prompt. Keep optimizing until this query no longer does a
> natural scan:
> `SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'`

Claude:
1. Calls **`fb_evaluate_goal`** (`goal_type=query_no_natural_scan`) → `met: false` (baseline).
2. Calls `fb_analyze_query` + `fb_suggest_indexes`, presents `CREATE INDEX IDX_CUSTOMERS_CITY …`.
3. You run the SQL (writes are off by default, see [Safety](../README.md#safety--compatibility)).
4. Calls `fb_evaluate_goal` again → `met: true`, and stops with the result.

You can also state the goal numerically, e.g. *"get this query under 50 ms"*
(`goal_type=query_time_ms`, `threshold=50`).

---

### 7. "Is it getting worse, or was it always like this?"

Some problems are not in any one query. They build up.

> **You:** The order screen crawls every afternoon and nobody changed anything. Use the
> classify_problem prompt.

→ **`classify_problem`** places the symptom on six axes before touching a tool — does it grow over
hours or appear instantly under load, does it track volume or concurrency, is it concentrated on a
few tables, is time spent working or waiting — then names the dominant class of the seven and the
reasoning that converges on it. "Fine at 9am, unusable at 4pm, fine again tomorrow" is temporal
accumulation, and no plan analysis will ever explain it.

> **You:** Sample the database for 30 seconds now, and again after lunch.

→ **`fb_sample_activity`** reads the MON$ counters twice across the window and reports the
difference: records read sequentially and by index, pages moved, versions collected, transactions
started, and whether the transaction horizon advanced at all. A horizon that never moves while
transactions keep starting is garbage collection getting nowhere — invisible in any single
snapshot, obvious across two.

Each tool also closes with **what it does not rule out**. A clean plan is not a fast query, and a
quiet window is not a healthy system: MON$ counts work performed, never time spent waiting for
permission to perform it.

## Worked session: optimizing a query on `employee.fdb`

A full round-trip against the stock **`employee`** sample database that ships with Firebird
(`examples/empbuild/employee.fdb`). The outputs below are verbatim tool results.

> **You:** Analyze this Firebird query and suggest improvements:
> ```sql
> SELECT emp_no, first_name, last_name, salary
> FROM employee
> WHERE salary > 60000
> ```

**1. Baseline.** `fb_analyze_query` returns (engine `3.0.12`):

```
PLAN (EMPLOYEE NATURAL)
```
> NATURAL scan on: EMPLOYEE. Run `fb_suggest_indexes` on this query for ready-to-run DDL.

`NATURAL` means Firebird reads **every** row of `EMPLOYEE` and throws away those with
`salary <= 60000`: there is no index on `SALARY` to seek with.

**2. Confirm the problem.** `fb_evaluate_goal` (`goal_type=query_no_natural_scan`):

```json
{ "goal_type": "query_no_natural_scan", "measured": 1.0, "met": false,
  "iteration_hint": "plan: PLAN (EMPLOYEE NATURAL)", "engine_version": "3.0.12" }
```

**3. Get the fix.** `fb_suggest_indexes`:

```sql
CREATE INDEX IDX_EMPLOYEE_SALARY ON EMPLOYEE (salary);
```
> **Verify:** re-run `fb_analyze_query`; the plan should use `IDX_EMPLOYEE_SALARY` and no longer show
> `EMPLOYEE NATURAL`. Then run `SET STATISTICS INDEX IDX_EMPLOYEE_SALARY;` to refresh selectivity.

**4. Apply it** (the server is read-only: run the DDL yourself), then **re-analyze**: the plan becomes `PLAN (EMPLOYEE INDEX (IDX_EMPLOYEE_SALARY))` and
`fb_evaluate_goal` returns `met: true`.

**When *not* to add the index.** The win comes from `salary > 60000` being **selective** (few rows).
If the predicate matched most of the table (e.g. `salary > 0`), the NATURAL scan is actually the
cheaper plan and the index would just add write overhead. Not every NATURAL scan is a bug.
