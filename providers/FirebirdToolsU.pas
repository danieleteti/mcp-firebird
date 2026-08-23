// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit FirebirdToolsU;
interface
uses MVCFramework.MCP.ToolProvider, MVCFramework.MCP.Attributes;
type
  TFirebirdTools = class(TMCPToolProvider)
  public
    [MCPTool('fb_info', 'Engine version, dialect, charset and detected capabilities of the configured Firebird database')]
    function FbInfo: TMCPToolResult;
    [MCPTool('fb_list_tables', 'Lists user tables (and views) in the configured database')]
    function FbListTables: TMCPToolResult;
    [MCPTool('fb_generate_documentation', 'Markdown documentation for one table (columns, primary key, indexes, triggers with the event they fire on), or for the whole database when table_name is empty — which also lists stored procedures with their parameters, functions and packages (3.0+)')]
    function FbGenerateDocumentation([MCPParam('Table name; leave empty for the whole database', TMCPParamPresence.Optional)] const table_name: string): TMCPToolResult;
    [MCPTool('fb_query', 'Runs a read-only SELECT and returns the rows as a Markdown table. Capped at max_rows (default 100, ceiling 1000); anything that is not a plain SELECT is refused, and so is a statement with unbound placeholders')]
    function FbQuery([MCPParam('The SELECT to run')] const sql: string;
      [MCPParam('Maximum rows to return (default 100, ceiling 1000)', TMCPParamPresence.Optional)] const max_rows: Integer): TMCPToolResult;
    [MCPTool('fb_analyze_query', 'Access plan of a SQL query (flags NATURAL scans and external sorts) plus its measured cost: a plain SELECT is executed once and the records and pages it actually touched are reported')]
    function FbAnalyzeQuery([MCPParam('The SQL query to analyze')] const sql: string): TMCPToolResult;
    [MCPTool('fb_suggest_indexes', 'Index advice for one query, as ready-to-run DDL: plain B-tree, expression (COMPUTED BY) or partial (5.0+), whichever the predicate calls for — and no index at all when the scan is the correct plan. Refreshes stale statistics before proposing anything structural. Executes the query once to measure what the scan reads against what it returns, so on a large table this costs a full scan')]
    function FbSuggestIndexes([MCPParam('The SQL query to optimize')] const sql: string): TMCPToolResult;
    [MCPTool('fb_suggest_index_drops', 'Suggests droppable indexes for a table (duplicate/redundant/inactive/low-selectivity)')]
    function FbSuggestIndexDrops([MCPParam('Table name')] const table_name: string): TMCPToolResult;
    [MCPTool('fb_audit_table', 'Schema-health audit of a table: missing PK, over-indexing, stale statistics')]
    function FbAuditTable([MCPParam('Table name')] const table_name: string): TMCPToolResult;
    [MCPTool('fb_audit_security', 'Who holds which privileges inside this database, and which grant is a mistake: privileges held by PUBLIC, delegation via WITH GRANT OPTION, roles nobody is a member of. Given user_name it answers the other question instead — everything that one account can reach, and how: directly, through PUBLIC, or through a role it belongs to')]
    function FbAuditSecurity(
      [MCPParam('Report what this one account can reach, instead of auditing the whole database', TMCPParamPresence.Optional)] const user_name: string): TMCPToolResult;
    [MCPTool('fb_suggest_grants', 'Builds the statements that give one account access to the objects matching a pattern and nothing else: a conditional CREATE USER, a role, the GRANTs generated from the catalogue, and the role granted to the account in the form this engine version needs. Then checks the claim: PUBLIC grants and grants the account already holds outside the plan are reported with the REVOKE that closes them')]
    function FbSuggestGrants(
      [MCPParam('The account the access is for, e.g. APP')] const user_name: string;
      [MCPParam('Which objects: a glob or LIKE pattern such as TBL_* (* and % both mean any sequence, _ is literal). Default: every user object', TMCPParamPresence.Optional)] const object_pattern: string;
      [MCPParam('read (SELECT) or readwrite (SELECT/INSERT/UPDATE/DELETE). Default read', TMCPParamPresence.Optional)] const access: string;
      [MCPParam('Role that carries the privileges. Default <USER>_ROLE', TMCPParamPresence.Optional)] const role_name: string;
      [MCPParam('Objects to subtract from the match, same pattern syntax — the audit log inside the application prefix, for instance', TMCPParamPresence.Optional)] const exclude_pattern: string;
      [MCPParam('Where the privileges land: role (a role, granted to the account) or user (straight on the account). Default: role on 4.0+, where a DEFAULT role needs nothing from the application; user below 4.0, where a role is inactive unless the connection names it', TMCPParamPresence.Optional)] const grant_to: string): TMCPToolResult;
    [MCPTool('fb_evaluate_goal', 'Deterministically measures an optimization goal and returns whether it is met')]
    function FbEvaluateGoal(
      [MCPParam('Goal type: query_no_natural_scan | query_time_ms | no_redundant_indexes | no_stale_index_statistics')] const goal_type: string;
      [MCPParam('Target: a SQL query or a table name')] const target: string;
      [MCPParam('Threshold (ms for query_time_ms; ignored otherwise)', TMCPParamPresence.Optional)] const threshold: Double): TMCPToolResult;
    [MCPTool('fb_monitor_transactions', 'Transaction/sweep health at this instant: OIT/OAT/Next gap and any blocking long-running transaction')]
    function FbMonitorTransactions(
      [MCPParam('Minutes an active transaction must run before being flagged as blocking (default 5)', TMCPParamPresence.Optional)] const stale_minutes: Integer): TMCPToolResult;
    [MCPTool('fb_sample_activity', 'Reads the MON$ counters twice over a window and reports the difference: records read sequentially and by index, pages moved, record versions collected, and whether the transaction horizon advanced. Use this when the question is what is changing over time rather than what is true right now')]
    function FbSampleActivity(
      [MCPParam('Length of the observation window in seconds (default 5, 1-60)', TMCPParamPresence.Optional)] const seconds: Integer): TMCPToolResult;
    [MCPTool('fb_monitor_attachments', 'Who is attached right now, from where, and what each attachment is running: idle connections and long-running statements')]
    function FbMonitorAttachments(
      [MCPParam('Minutes an attachment must be idle before it is counted as stale (default 30)', TMCPParamPresence.Optional)] const idle_minutes: Integer;
      [MCPParam('Seconds a statement must run before being flagged (default 60)', TMCPParamPresence.Optional)] const long_statement_seconds: Integer): TMCPToolResult;
    [MCPTool('fb_backup_start', 'Starts a gbak backup of the configured database into firebird.backup_dir and returns at once. The backup is then restored into a scratch database to prove it can be restored. Poll fb_backup_status')]
    function FbBackupStart: TMCPToolResult;
    [MCPTool('fb_backup_status', 'Reports the running or last backup: phase, size, how long each stage took, and whether the backup was proved restorable')]
    function FbBackupStatus: TMCPToolResult;
  end;
implementation
uses
  System.SysUtils, System.Classes, System.Diagnostics, System.StrUtils, System.DateUtils,
  JsonDataObjects,
  Firebird.Connection, Firebird.Capabilities, Firebird.Introspection,
  Firebird.DocGen, Firebird.PlanAnalyzer, Firebird.IndexAdvisor, Firebird.Advisory,
  Firebird.SchemaAudit, Firebird.Goal, Firebird.TransactionMonitor, Firebird.Activity,
  Firebird.Attachments, Firebird.Query, Firebird.SecurityAudit, Firebird.GrantPlanner,
  FirebirdToolRuntimeU, FirebirdConfigU, FirebirdBackupJobU,
  MVCFramework.MCP.Server, MVCFramework.Logger;

{ Enough rows to see the shape of who holds what. Past this the table is not read, it is
  scrolled, and the findings underneath it are what matters anyway. }
const GRANT_ROWS_SHOWN = 200;
const DEFAULT_STALE_MINUTES = 5;
const DEFAULT_SAMPLE_SECONDS = 5;
const DEFAULT_IDLE_MINUTES = 30;
const DEFAULT_LONG_STATEMENT_SECONDS = 60;

function EngineVersion(AConn: TFirebirdConnection): string;
begin
  Result := TFirebirdCapabilities.Detect(AConn).EngineVersion;
end;

function TFirebirdTools.FbInfo: TMCPToolResult;
begin
  Result := Guard('fb_info', '',
    function(Conn: TFirebirdConnection): TMCPToolResult
    var C: TFirebirdCapabilities; J: TJDOJsonObject;
    begin
      C := TFirebirdCapabilities.Detect(Conn);
      J := TJDOJsonObject.Create;
      try
        J.S['engine_version'] := C.EngineVersion;
        J.I['major'] := C.Major; J.I['minor'] := C.Minor;
        J.B['has_explained_plan'] := C.HasExplainedPlan;
        J.B['has_boolean_type'] := C.HasBooleanType;
        J.B['has_parallel_workers'] := C.HasParallelWorkers;
        J.S['database'] := Conn.Config.Database;
        Result := TMCPToolResult.JSON(J);
      finally J.Free; end;
    end);
end;

function TFirebirdTools.FbListTables: TMCPToolResult;
begin
  Result := Guard('fb_list_tables', '',
    function(Conn: TFirebirdConnection): TMCPToolResult
    var I: TFirebirdIntrospection; T: string; SB: TStringBuilder;
    begin
      I := TFirebirdIntrospection.Create(Conn); SB := TStringBuilder.Create;
      try
        for T in I.ListTables do SB.AppendLine('- ' + T);
        Result := TMCPToolResult.Text(SB.ToString);
      finally SB.Free; I.Free; end;
    end);
end;

function TFirebirdTools.FbGenerateDocumentation(const table_name: string): TMCPToolResult;
var LTable: string;
begin
  LTable := table_name;
  Result := Guard('fb_generate_documentation', 'table_name=' + LTable,
    function(Conn: TFirebirdConnection): TMCPToolResult
    var D: TFirebirdDocGen;
    begin
      D := TFirebirdDocGen.Create(TFirebirdIntrospection.Create(Conn));
      try
        if LTable.Trim.IsEmpty then Result := TMCPToolResult.Text(D.DatabaseMarkdown)
        else Result := TMCPToolResult.Text(D.TableMarkdown(LTable.ToUpper));
      finally D.Free; end;
    end);
end;

function TFirebirdTools.FbQuery(const sql: string; const max_rows: Integer): TMCPToolResult;
var LSql: string; LMaxRows: Integer;
begin
  LSql := sql;
  // Same optional-Integer caveat as fb_monitor_transactions: 0 means "not passed", and
  // Firebird.Query turns it into the documented default.
  LMaxRows := max_rows;
  Result := Guard('fb_query', Format('sql=%s max_rows=%d', [LSql, LMaxRows]),
    function(Conn: TFirebirdConnection): TMCPToolResult
    begin
      Result := TMCPToolResult.Text(
        WithLimits(RunSelect(Conn, LSql, LMaxRows).ToMarkdown, 'fb_query'));
    end);
end;

{ "What can APP actually reach?" — the question a privilege list does not answer, because the
  answer is spread across grants to the account, grants to PUBLIC and grants to every role the
  account belongs to. Firebird will not tell you whether a role is automatic for that account
  (a DEFAULT role is recorded in the security database, not here), so a role row says what the
  account may reach and says why it is conditional. }
function EffectivePrivilegesReport(const AUser: string): TMCPToolResult;
begin
  Result := Guard('fb_audit_security', 'user_name=' + AUser,
    function(Conn: TFirebirdConnection): TMCPToolResult
    var
      A: TFirebirdSecurityAudit;
      E: TEffectiveGrant;
      lRows: TArray<TEffectiveGrant>;
      lRoles: TArray<string>;
      lOwned: Integer;
      lConditional: Boolean;
      SB: TStringBuilder;
    begin
      A := TFirebirdSecurityAudit.Create(Conn);
      SB := TStringBuilder.Create;
      try
        lRows := A.EffectivePrivileges(AUser);
        lRoles := A.RolesOf(AUser);
        lOwned := A.OwnedObjectCount(AUser);

        SB.AppendLine(Format('**What %s can reach.**', [AUser])).AppendLine;
        if AUser = 'SYSDBA' then
          SB.AppendLine('SYSDBA is not subject to privileges. It reaches everything in this ' +
            'database whatever the table below says, and so does the owner of an object on its ' +
            'own objects. Granting SYSDBA less does not restrict it; giving the application its ' +
            'own account does.').AppendLine;
        if lOwned > 0 then
          SB.AppendLine(Format('%s owns %d user object(s), and an owner is not subject to the ' +
            'privileges on what it owns: it reaches those whether or not they appear below.',
            [AUser, lOwned])).AppendLine;

        if Length(lRows) = 0 then
          SB.AppendLine('No privilege reaches this account: nothing granted to it, nothing held ' +
            'by PUBLIC, and no role it belongs to carries anything.').AppendLine
        else
        begin
          SB.AppendLine('| Object | Privileges | Reached through |');
          SB.AppendLine('|---|---|---|');
          lConditional := False;
          for E in lRows do
          begin
            if E.Conditional then
              lConditional := True;
            SB.AppendLine(Format('| %s%s | %s | %s%s |',
              [E.ObjectName, IfThen(E.ObjectKind = 'table', '', ' *(' + E.ObjectKind + ')*'),
               E.Privileges, E.Via, IfThen(E.Conditional, ' *(only when active)*', '')]));
          end;
          SB.AppendLine;
          if lConditional then
            SB.AppendLine('A row marked *(only when active)* comes through a role, and a ' +
              'Firebird role is inactive unless the connection names it — or unless it was ' +
              'granted to this account as a DEFAULT role (4.0+). Which of the two applies is ' +
              'recorded in the security database, which this server does not attach to, so it ' +
              'cannot be read from here: check the connection string, or grant the privileges ' +
              'to the account directly (fb_suggest_grants with grant_to=user).').AppendLine;
        end;

        if Length(lRoles) > 0 then
          SB.AppendLine(Format('**Member of:** %s', [string.Join(', ', lRoles)])).AppendLine
        else
          SB.AppendLine('**Member of:** no roles.').AppendLine;

        Result := TMCPToolResult.Text(WithLimits(SB.ToString, 'fb_audit_security'));
      finally
        SB.Free;
        A.Free;
      end;
    end);
end;

function TFirebirdTools.FbAuditSecurity(const user_name: string): TMCPToolResult;
var
  LUser: string;
begin
  LUser := user_name.Trim.ToUpper;
  if LUser <> '' then
    Exit(EffectivePrivilegesReport(LUser));
  Result := Guard('fb_audit_security', '',
    function(Conn: TFirebirdConnection): TMCPToolResult
    var
      A: TFirebirdSecurityAudit;
      G: TGrantSummary;
      R: TRoleInfo;
      lGrants: TArray<TGrantSummary>;
      lRoles: TArray<TRoleInfo>;
      SB: TStringBuilder;
    begin
      A := TFirebirdSecurityAudit.Create(Conn);
      SB := TStringBuilder.Create;
      try
        lGrants := A.Grants;
        lRoles := A.Roles;
        if Length(lGrants) = 0 then
          SB.AppendLine('**No grants on user objects.** Every object is reachable only by its ' +
            'owner and by SYSDBA.').AppendLine
        else
        begin
          SB.AppendLine(Format('**%d grant(s) on user objects.** Owners are not listed: every ' +
            'object''s owner holds everything on it by definition.',
            [Length(lGrants)])).AppendLine;
          SB.AppendLine('| Grantee | Object | Privileges | Grant option | Granted by |');
          SB.AppendLine('|---|---|---|---|---|');
          for var lRow := 0 to High(lGrants) do
          begin
            if lRow >= GRANT_ROWS_SHOWN then
            begin
              SB.AppendLine(Format('| … | *and %d more, not listed* | | | |',
                [Length(lGrants) - GRANT_ROWS_SHOWN]));
              Break;
            end;
            G := lGrants[lRow];
            SB.AppendLine(Format('| %s%s | %s%s | %s | %s | %s |',
              [G.Grantee, IfThen(G.GranteeIsRole, ' *(role)*', ''),
               G.ObjectName, IfThen(G.ObjectKind = 'table', '', ' *(' + G.ObjectKind + ')*'),
               G.Privileges, IfThen(G.WithGrantOption, 'yes', 'no'),
               IfThen(G.Grantor = '', '—', G.Grantor)]));
          end;
          SB.AppendLine;
          { The listing is capped; the findings below it are not. Whatever was left out of the
            table, anything wrong with it is still reported. }
        end;

        SB.AppendLine(Format('**%d user-defined role(s).**', [Length(lRoles)]));
        for R in lRoles do
          SB.AppendLine(Format('- `%s` (owner %s) — %s', [R.RoleName,
            IfThen(R.Owner = '', 'unknown', R.Owner),
            IfThen(Length(R.Members) = 0, 'no members', string.Join(', ', R.Members))]));
        SB.AppendLine;

        SB.Append(AdvisoriesToText(A.Analyze,
          'No grant issues found: nothing is held by PUBLIC, nothing carries a grant option, ' +
          'and every role has members.'));
        Result := TMCPToolResult.Text(WithLimits(SB.ToString, 'fb_audit_security'));
      finally
        SB.Free;
        A.Free;
      end;
    end);
end;

function TFirebirdTools.FbAnalyzeQuery(const sql: string): TMCPToolResult;
var LSql: string;
begin
  LSql := sql;
  Result := Guard('fb_analyze_query', 'sql=' + LSql,
    function(Conn: TFirebirdConnection): TMCPToolResult
    var PA: TFirebirdPlanAnalyzer; R: TPlanResult; SB: TStringBuilder;
        Caps: TFirebirdCapabilities; Act: TFirebirdActivity; Cost: TStatementCost;
    begin
      Caps := TFirebirdCapabilities.Detect(Conn);
      PA := TFirebirdPlanAnalyzer.Create(Conn, Caps.EngineVersion); SB := TStringBuilder.Create;
      try
        R := PA.Analyze(LSql);
        SB.AppendLine('**Engine:** ' + R.EngineVersion).AppendLine;
        SB.AppendLine('**PLAN:**').AppendLine('```').AppendLine(R.RawPlan).AppendLine('```');
        { The legacy line says which access path; the tree says how much of each index the query
          agreed with, which join strategy was chosen and which alias is which table. Firebird
          prints it from 3.0 on. }
        if R.ExplainedPlan <> '' then
          SB.AppendLine('**Explained plan:**').AppendLine('```').AppendLine(R.ExplainedPlan).AppendLine('```');
        if R.HasNaturalScan then
          SB.AppendLine('NATURAL scan on: ' + string.Join(', ', R.NaturalTables) + '. Run fb_suggest_indexes on this query for ready-to-run DDL.')
        else
          SB.AppendLine('No NATURAL scan: every table is accessed via an index.');
        if R.HasExternalSort then
          SB.AppendLine('External SORT in the plan (ORDER BY / GROUP BY / DISTINCT without a usable index). Consider an index on the sort columns.');

        { The plan is what the optimizer decided; this is what the decision cost. Without it,
          "the plan uses an index" and "the query reads 400 000 records through that index" are
          the same report. }
        Act := TFirebirdActivity.Create(Conn, Caps);
        try Cost := Act.Measure(LSql); finally Act.Free; end;
        SB.AppendLine;
        if Cost.Executed then
        begin
          SB.AppendLine(Format('**Measured:** %d row(s) in %d ms.', [Cost.Rows, Cost.ElapsedMs]));
          SB.AppendLine(Format('- records read: %d sequential, %d by index', [Cost.Delta.SeqReads, Cost.Delta.IdxReads]));
          SB.AppendLine(Format('- pages: %d read, %d fetched', [Cost.Delta.PageReads, Cost.Delta.PageFetches]));
          if Cost.Delta.BackversionReads > 0 then
            SB.AppendLine(Format('- back-version reads: %d (old row versions walked to reach the current one)',
              [Cost.Delta.BackversionReads]));
          if (Cost.Rows > 0) and (Cost.Delta.RecordReads > Cost.Rows * 10) then
            SB.AppendLine(Format('- the engine read %d records to return %d: the access path is ' +
              'reading far more than the query keeps.', [Cost.Delta.RecordReads, Cost.Rows]));
        end
        else
          SB.AppendLine('**Not measured:** ' + Cost.SkipReason + '.');

        Result := TMCPToolResult.Text(WithLimits(SB.ToString, 'fb_analyze_query'));
      finally SB.Free; PA.Free; end;
    end);
end;

function TFirebirdTools.FbSuggestIndexes(const sql: string): TMCPToolResult;
var LSql: string;
begin
  LSql := sql;
  Result := Guard('fb_suggest_indexes', 'sql=' + LSql,
    function(Conn: TFirebirdConnection): TMCPToolResult
    var A: TFirebirdIndexAdvisor;
    begin
      A := TFirebirdIndexAdvisor.Create(Conn, EngineVersion(Conn));
      try Result := TMCPToolResult.Text(WithLimits(
        AdvisoriesToText(A.SuggestForQuery(LSql),
          'No index suggested: the plan contains neither a NATURAL scan nor an external sort, so ' +
          'every table in this query is already reached through an index and nothing is ordered ' +
          'after the fact.'),
        'fb_suggest_indexes'));
      finally A.Free; end;
    end);
end;

function TFirebirdTools.FbSuggestIndexDrops(const table_name: string): TMCPToolResult;
var LTable: string;
begin
  LTable := table_name;
  Result := Guard('fb_suggest_index_drops', 'table_name=' + LTable,
    function(Conn: TFirebirdConnection): TMCPToolResult
    var A: TFirebirdIndexAdvisor;
    begin
      A := TFirebirdIndexAdvisor.Create(Conn, EngineVersion(Conn));
      try Result := TMCPToolResult.Text(WithLimits(
        AdvisoriesToText(A.SuggestDropsForTable(LTable.ToUpper), 'No droppable indexes found on ' + LTable + '.'),
        'fb_suggest_index_drops'));
      finally A.Free; end;
    end);
end;

function TFirebirdTools.FbAuditTable(const table_name: string): TMCPToolResult;
var LTable: string;
begin
  LTable := table_name;
  Result := Guard('fb_audit_table', 'table_name=' + LTable,
    function(Conn: TFirebirdConnection): TMCPToolResult
    var A: TFirebirdSchemaAudit;
    begin
      A := TFirebirdSchemaAudit.Create(Conn);
      try Result := TMCPToolResult.Text(WithLimits(AdvisoriesToText(A.AuditTable(LTable.ToUpper),
        'No schema-health issues found on ' + LTable + '.'), 'fb_audit_table'));
      finally A.Free; end;
    end);
end;

function TFirebirdTools.FbSuggestGrants(const user_name, object_pattern, access, role_name,
  exclude_pattern, grant_to: string): TMCPToolResult;
var
  LUser, LPattern, LAccess, LRole, LExclude, LGrantTo: string;
begin
  LUser := user_name; LPattern := object_pattern; LAccess := access;
  LRole := role_name; LExclude := exclude_pattern; LGrantTo := grant_to;
  Result := Guard('fb_suggest_grants',
    Format('user_name=%s object_pattern=%s access=%s role_name=%s exclude_pattern=%s grant_to=%s',
      [LUser, LPattern, LAccess, LRole, LExclude, LGrantTo]),
    function(Conn: TFirebirdConnection): TMCPToolResult
    var
      P: TGrantPlan;
      SB: TStringBuilder;
      T: TGrantTarget;
      S: string;
    begin
      P := PlanGrants(Conn, LUser, LPattern, LAccess, LRole, LExclude, LGrantTo);
      SB := TStringBuilder.Create;
      try
        if P.RoleName = '' then
          SB.AppendLine(Format('**%s access for %s**, granted straight to the account.',
            [P.Access, P.UserName])).AppendLine
        else
          SB.AppendLine(Format('**%s access for %s**, through role %s.',
            [P.Access, P.UserName, P.RoleName])).AppendLine;

        if Length(P.Statements) > 0 then
        begin
          SB.AppendLine('```sql');
          for S in P.Statements do
            SB.AppendLine(S);
          SB.AppendLine('```').AppendLine;
        end;

        if Length(P.Targets) > 0 then
        begin
          SB.AppendLine(Format('**%d object(s) in the plan:**', [Length(P.Targets)]));
          for T in P.Targets do
            SB.AppendLine(Format('- `%s` *(%s)*', [T.Name, T.Kind]));
          SB.AppendLine;
        end;

        for S in P.Notes do
          SB.AppendLine('- ' + S);
        SB.AppendLine;

        { The conflicts are the half that makes "and nothing else" true or false, so they are
          rendered as findings rather than prose: severity, statement, verification. }
        SB.AppendLine('### Does the plan hold?').AppendLine;
        SB.Append(AdvisoriesToText(P.Conflicts,
          Format('Nothing outside this plan is reachable by %s through an existing grant: no ' +
            'PUBLIC privileges on other objects, and no grants this account already holds ' +
            'elsewhere.', [P.UserName])));
        Result := TMCPToolResult.Text(WithLimits(SB.ToString, 'fb_suggest_grants'));
      finally
        SB.Free;
      end;
    end);
end;

function TFirebirdTools.FbEvaluateGoal(const goal_type, target: string; const threshold: Double): TMCPToolResult;
var LGoalType, LTarget: string; LThreshold: Double;
begin
  LGoalType := goal_type; LTarget := target; LThreshold := threshold;
  Result := Guard('fb_evaluate_goal',
    Format('goal_type=%s target=%s threshold=%g', [LGoalType, LTarget, LThreshold]),
    function(Conn: TFirebirdConnection): TMCPToolResult
    var G: TFirebirdGoal; R: TGoalResult; J: TJDOJsonObject;
    begin
      G := TFirebirdGoal.Create(Conn, EngineVersion(Conn));
      try
        R := G.Evaluate(LGoalType, LTarget, LThreshold);
        J := TJDOJsonObject.Create;
        try
          J.S['goal_type'] := R.GoalType; J.S['target'] := R.Target;
          J.F['measured'] := R.Measured; J.F['threshold'] := R.Threshold;
          J.B['met'] := R.Met; J.F['gap'] := R.Gap;
          J.S['iteration_hint'] := R.Hint; J.S['engine_version'] := R.EngineVersion;
          Result := TMCPToolResult.JSON(J);
        finally J.Free; end;
      finally G.Free; end;
    end);
end;

function TFirebirdTools.FbMonitorTransactions(const stale_minutes: Integer): TMCPToolResult;
var LStaleMinutes: Integer;
begin
  // The MCP framework cannot distinguish "param omitted" from "param passed as 0"
  // for an optional Integer, so 0-or-less falls back to the documented default here
  // rather than in Firebird.TransactionMonitor (which keeps 0 meaning "any age" for tests).
  LStaleMinutes := stale_minutes;
  if LStaleMinutes <= 0 then LStaleMinutes := DEFAULT_STALE_MINUTES;
  Result := Guard('fb_monitor_transactions', Format('stale_minutes=%d', [LStaleMinutes]),
    function(Conn: TFirebirdConnection): TMCPToolResult
    var M: TFirebirdTransactionMonitor; S: TTransactionSnapshot; SB: TStringBuilder;
    begin
      M := TFirebirdTransactionMonitor.Create(Conn, TFirebirdCapabilities.Detect(Conn));
      SB := TStringBuilder.Create;
      try
        S := M.Snapshot;
        SB.AppendLine(Format('**OIT:** %d  **OAT:** %d  **OST:** %d  **Next:** %d  **Gap:** %d',
          [S.OIT, S.OAT, S.OST, S.NextTransaction, S.Gap])).AppendLine;
        SB.Append(AdvisoriesToText(M.Analyze(LStaleMinutes), 'No transaction/sweep issues found.'));
        Result := TMCPToolResult.Text(WithLimits(SB.ToString, 'fb_monitor_transactions'));
      finally SB.Free; M.Free; end;
    end);
end;

function TFirebirdTools.FbSampleActivity(const seconds: Integer): TMCPToolResult;
var LSeconds: Integer;
begin
  // Same optional-Integer caveat as fb_monitor_transactions: 0 means "not passed" here.
  LSeconds := seconds;
  if LSeconds <= 0 then LSeconds := DEFAULT_SAMPLE_SECONDS;
  Result := Guard('fb_sample_activity', Format('seconds=%d', [LSeconds]),
    function(Conn: TFirebirdConnection): TMCPToolResult
    var A: TFirebirdActivity; S: TActivitySample; D: TActivityCounters; SB: TStringBuilder;
    begin
      A := TFirebirdActivity.Create(Conn, TFirebirdCapabilities.Detect(Conn));
      SB := TStringBuilder.Create;
      try
        S := A.Sample(LSeconds);
        D := S.Delta;
        SB.AppendLine(Format('**Window:** %d ms, database-wide.', [S.ElapsedMs])).AppendLine;
        SB.AppendLine('| Counter | Change over the window | Per second |');
        SB.AppendLine('|---|---:|---:|');
        // Invariant format settings for every rate below: under an Italian locale %.1f renders
        // one point zero as "1,0", and this table is read by a machine that will not ask.
        SB.AppendLine(Format('| records read sequentially | %d | %.1f |', [D.SeqReads, S.PerSecond(D.SeqReads)], TFormatSettings.Invariant));
        SB.AppendLine(Format('| records read by index | %d | %.1f |', [D.IdxReads, S.PerSecond(D.IdxReads)], TFormatSettings.Invariant));
        SB.AppendLine(Format('| records inserted/updated/deleted | %d / %d / %d | |', [D.Inserts, D.Updates, D.Deletes]));
        SB.AppendLine(Format('| versions backed out/purged/expunged | %d / %d / %d | |', [D.Backouts, D.Purges, D.Expunges]));
        if D.BackversionReads >= 0 then
          SB.AppendLine(Format('| back-version reads | %d | %.1f |', [D.BackversionReads, S.PerSecond(D.BackversionReads)], TFormatSettings.Invariant));
        SB.AppendLine(Format('| pages read/written | %d / %d | |', [D.PageReads, D.PageWrites]));
        SB.AppendLine(Format('| pages fetched/marked | %d / %d | |', [D.PageFetches, D.PageMarks]));
        SB.AppendLine(Format('| transactions started (Next) | %d | %.1f |', [D.NextTransaction, S.PerSecond(D.NextTransaction)], TFormatSettings.Invariant));
        SB.AppendLine(Format('| horizon moved (OIT / OAT) | %d / %d | |', [D.OIT, D.OAT]));
        SB.AppendLine(Format('| attachments | %d → %d | |', [S.Before.Attachments, S.After.Attachments]));
        SB.AppendLine;
        SB.Append(AdvisoriesToText(A.Analyze(S),
          'Nothing in this window crossed a reporting threshold. That is a statement about these ' +
          'seconds and this database, not about the workload: if the problem is intermittent, ' +
          'sample again while it is happening.'));
        Result := TMCPToolResult.Text(WithLimits(SB.ToString, 'fb_sample_activity'));
      finally SB.Free; A.Free; end;
    end);
end;

function TFirebirdTools.FbMonitorAttachments(const idle_minutes, long_statement_seconds: Integer): TMCPToolResult;
var
  LIdle, LLong: Integer;
begin
  LIdle := idle_minutes;
  if LIdle <= 0 then
    LIdle := DEFAULT_IDLE_MINUTES;
  LLong := long_statement_seconds;
  if LLong <= 0 then
    LLong := DEFAULT_LONG_STATEMENT_SECONDS;
  Result := Guard('fb_monitor_attachments',
    Format('idle_minutes=%d long_statement_seconds=%d', [LIdle, LLong]),
    function(Conn: TFirebirdConnection): TMCPToolResult
    var
      A: TFirebirdAttachments;
      T: TAttachmentInfo;
      lAll: TArray<TAttachmentInfo>;
      SB: TStringBuilder;
    begin
      A := TFirebirdAttachments.Create(Conn, TFirebirdCapabilities.Detect(Conn));
      SB := TStringBuilder.Create;
      try
        lAll := A.List;
        SB.AppendLine(Format('**%d attachment(s) connected.**', [Length(lAll)])).AppendLine;
        for T in lAll do
        begin
          SB.AppendLine(Format('- **%d** %s from %s%s — connected %ds, %s',
            [T.AttachmentID, T.UserName,
             IfThen(T.RemoteAddress = '', 'local', T.RemoteAddress),
             IfThen(T.RemoteProcess = '', '', ' (' + T.RemoteProcess + ')'),
             T.ConnectedSeconds,
             IfThen(T.Active, 'active', 'idle')]));
          if T.CurrentSQL <> '' then
            SB.AppendLine(Format('  running %ds: `%s`', [T.StatementSeconds, T.CurrentSQL]));
        end;
        SB.AppendLine;
        SB.Append(AdvisoriesToText(A.Analyze(LIdle, LLong),
          'No idle-connection or long-statement issues found.'));
        Result := TMCPToolResult.Text(WithLimits(SB.ToString, 'fb_monitor_attachments'));
      finally
        SB.Free;
        A.Free;
      end;
    end);
end;

function TFirebirdTools.FbBackupStart: TMCPToolResult;
begin
  Result := Guard('fb_backup_start', '',
    function(Conn: TFirebirdConnection): TMCPToolResult
    var
      LDir: string;
    begin
      { Inside Guard, so a missing firebird.backup_dir comes back as an isError
        carrying EFirebirdConfig's speaking message instead of an opaque -32603.
        The connection Guard opened is used for exactly one thing: proving the
        credentials work before a thread goes off with them. }
      LDir := LoadBackupDir;
      if not StartBackupJob(Conn.Config, LDir) then
        Exit(TMCPToolResult.Error(
          'A backup is already running. Call fb_backup_status; starting a second one ' +
          'would have both writing to the same folder at once.'));
      Result := TMCPToolResult.Text(Format(
        'Backup started into `%s`. It runs in the background — this call did not wait for it.' +
        sLineBreak + sLineBreak +
        'Call **fb_backup_status** to see how it is going. When the backup itself is done ' +
        'the job restores it into a scratch database and deletes that again, so the answer ' +
        'is not "a file exists" but "this backup restores".', [LDir]));
    end);
end;

function TFirebirdTools.FbBackupStatus: TMCPToolResult;
var
  S: TBackupJobState;
  SB: TStringBuilder;
begin
  { No Guard: this touches no database at all, and opening a connection to report
    on a thread would be the only thing that could make it fail. }
  LogI('>> fb_backup_status', 'mcp');
  S := BackupJobState;
  SB := TStringBuilder.Create;
  try
    case S.Phase of
      bpNever:
        SB.AppendLine('No backup has been started since this server started. Use fb_backup_start.');
      bpBackingUp:
        SB.AppendLine(Format('**Backing up** — still running, %d seconds so far, %.1f MB written to `%s`.',
          [SecondsBetween(Now, S.StartedAt), S.BackupBytes / 1024 / 1024, S.BackupFile],
          TFormatSettings.Invariant));
      bpVerifying:
        SB.AppendLine(Format(
          '**Verifying** — still running. The backup finished in %.1fs (%.1f MB) and is now ' +
          'being restored into a scratch database.',
          [S.BackupSeconds, S.BackupBytes / 1024 / 1024], TFormatSettings.Invariant));
      bpDone:
        begin
          SB.AppendLine(Format('**Done.** `%s`', [S.BackupFile]));
          SB.AppendLine(Format('**Size:** %.1f MB  **Backup:** %.1fs  **Verify:** %.1fs',
            [S.BackupBytes / 1024 / 1024, S.BackupSeconds, S.VerifySeconds],
            TFormatSettings.Invariant));
          SB.AppendLine;
          SB.AppendLine('The backup was restored into a scratch database and then deleted. ' +
            'It is a backup, not just a file.');
        end;
      bpFailed:
        begin
          SB.AppendLine('**Failed.** ' + S.Detail);
          if S.BackupFile <> '' then
            SB.AppendLine(Format('The backup file itself is at `%s`.', [S.BackupFile]));
          { gbak -v narrates every table it writes. On the way out that is a wall of
            "writing privilege for user SYSDBA" around the one line that matters, and
            the size and the two timings above already say what went right. It earns
            its space only when something went wrong. }
          if S.GbakLog <> '' then
            SB.AppendLine.AppendLine('```').AppendLine(S.GbakLog.Trim).AppendLine('```');
        end;
    end;
    Result := TMCPToolResult.Text(WithLimits(SB.ToString, 'fb_backup_status'));
  finally
    SB.Free;
  end;
end;

initialization
  TMCPServer.Instance.RegisterToolProvider(TFirebirdTools);
end.
