# Firebird common-problem catalog

Each row is a known Firebird problem, the fixture that provokes it, the tool that
detects it, and the milestone the detection lands in. Fixtures live in
`tests/seed/seed.sql` and `tests/seed/problems.sql`.

**Every problem below is detected by the free edition.** All twenty are visible from inside
the database, and that is exactly what defines the free edition (see `README.md` § Editions &
licensing). The Enterprise problems — a misconfigured `firebird.conf`, a page size fighting the
hardware, a sweep that never runs, a bugcheck buried in `firebird.log` — are not in this catalog:
they need a fixture on the host, not in the schema, and they live in the private repository.

| # | Problem | Fixture object | Detected by | Milestone |
|---|---|---|---|---|
| 1 | NATURAL scan on filtered column | CUSTOMERS.CITY | fb_analyze_query | M1 |
| 2 | Duplicate of system FK index | IDX_ORDERS_CUSTOMER_DUP | fb_suggest_index_drops | M1 |
| 3 | Redundant left-prefix index | IDX_CUST_NAME | fb_suggest_index_drops | M1 |
| 4 | Inactive index | IDX_CUST_CITY | fb_suggest_index_drops | M1 |
| 5 | Low-selectivity index | IDX_CUST_STATUS | fb_suggest_index_drops | M1 |
| 6 | Missing PRIMARY KEY | NOPK_LOG | fb_audit_table | M1 |
| 7 | Stale statistics | IDX_STALE_CODE | fb_audit_table | M1 |
| 8 | Over-indexing | OVERIDX | fb_audit_table | M1 |
| 9 | External SORT (no usable index) | CUSTOMERS ORDER BY CITY | fb_analyze_query | M1 |
| 10 | Non-sargable predicate (LIKE '%x', <>, NOT IN, fn(col)) | NSARG_T | fb_analyze_query (heuristic) | **M2** |
| 11 | Implicit type conversion in WHERE | CONV_T.CODE (INT vs '5') | fb_analyze_query (heuristic) | **M2** |
| 12 | Oversized / near-limit index key | BIGKEY_T (VARCHAR(800)) | fb_audit_table (key-size check) | **M2** |
| 13 | Long-running transaction blocking garbage collection (OIT/OAT/Next gap) | live held-open transaction (2nd connection; not a static fixture — see `Test.Firebird.TransactionMonitor`) | fb_monitor_transactions | **M2** |
| 14 | An index proposed for a scan that is the correct plan | SKEWED.STATE (90% one value) | fb_suggest_indexes (yield rule) | **M2** |
| 15 | Predicate wrapped in a function — no plain index can serve it | SKEWED.LABEL via `UPPER()` | fb_suggest_indexes (expression index) | **M2** |
| 16 | Query narrowed to one population, index over the whole table | SKEWED.STATE + SKEWED.TAG | fb_suggest_indexes (partial index, 5.0+) | **M2** |
| 17 | Optimizer costing an index against statistics from before the load | IDX_STALEIDX_K | fb_audit_table, fb_evaluate_goal `no_stale_index_statistics` | **M2** |
| 18 | External SORT with no index proposed for it | SKEWED ORDER BY TAG | fb_suggest_indexes (sort index) | **M2** |
| 19 | Composite index the query can only seek part of | *(no static fixture — read from the explained plan, 3.0+)* | fb_suggest_indexes (segment match) | **M2** |
| 20 | Join with no usable index on either side | CUSTOMERS ⋈ ORDERS with CITY inactive | fb_suggest_indexes (two-scan join) | **M2** |
