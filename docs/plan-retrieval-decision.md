# Access-Plan Retrieval Decision (Task 10 spike)

**Chosen mechanism: B — shell out to `isql.exe` with `SET PLANONLY ON`.**

Why B over A: Mechanism A (legacy `isc_dsql_sql_info` / `isc_info_sql_get_plan=22` via `fbclient.dll`)
*did* return the correct plan for the CITY query, proving the concept. But a per-statement
`EAccessViolation` inside the client runtime (page-boundary over-read) appeared on the PK query and
needed more binding/buffer work than the spike budget allowed. B is correct, simple, and proven on
both required versions.

## Command (works identically on FB 2.5 and FB 5.0)
- `isql.exe` lives next to `fbclient.dll`; derive its path from the configured `client_lib` directory
  (FB5: `<clientdir>\isql.exe`; FB2.5: `<clientdir>\isql.exe`, where clientdir = the `bin` folder).
- Invoke: `isql -q -user SYSDBA -password masterkey "host/port:DBPATH"` and feed via **stdin**:
  ```
  SET PLANONLY ON;
  <the SQL statement>;
  ```
- `SET PLANONLY ON` prepares but does NOT execute; isql prints only the `PLAN (...)` line(s).

## Parsing
- Read stdout; ignore the `Database: ...`, `SQL>` prompt and blank lines.
- Keep line(s) starting with `PLAN ` (a complex query may emit several / nested `PLAN`).
- `HasNaturalScan := Pos('NATURAL', UpperCase(rawPlan)) > 0`.

## Observed plans (identical text on FB 2.5 port 3070 and FB 5.0 port 3055)
- `SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'`        -> `PLAN (CUSTOMERS NATURAL)`            (NATURAL)
- `SELECT * FROM CUSTOMERS WHERE CUSTOMER_ID = 1`      -> `PLAN (CUSTOMERS INDEX (RDB$PRIMARY1))` (no NATURAL)

## 2.5 vs 5.0 differences
None for this purpose. `SET PLANONLY ON` exists since FB 2.5 and the legacy `PLAN (...)` text format is
identical. (FB3+ detailed/explain plan is NOT needed to detect NATURAL.)

## Task 11 signature
```pascal
function GetRawPlan(const AConfig: TFirebirdConfig; const ASQL: string): string;
// 1. isqlPath := IncludeTrailingPathDelimiter(ExtractFileDir(AConfig.ClientLib)) + 'isql.exe';
// 2. connStr  := Format('%s/%d:%s', [AConfig.Host, AConfig.Port, AConfig.Database]);
// 3. stdin    := 'SET PLANONLY ON;'#13#10 + ASQL + ';'#13#10;
// 4. run isql -q -user <u> -password <p> "<connStr>", capture stdout (with timeout);
// 5. Result   := concatenated lines beginning with 'PLAN ' (trimmed).
// HasNaturalScan computed by caller: Pos('NATURAL', UpperCase(Result)) > 0.
```
Note: if a future requirement forbids spawning a process, revisit Mechanism A — it is viable once the
`isc_dsql_sql_info` buffer binding is hardened (use a heap buffer, treat handles as `FB_API_HANDLE`/
`Cardinal`, pass buffer_length as a value < 32KB).
