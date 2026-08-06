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
    [MCPTool('fb_generate_documentation', 'Markdown documentation — columns, primary key, indexes — for one table, or for the whole database when table_name is empty')]
    function FbGenerateDocumentation([MCPParam('Table name; leave empty for the whole database', TMCPParamPresence.Optional)] const table_name: string): TMCPToolResult;
    [MCPTool('fb_analyze_query', 'Access plan of a SQL query (flags NATURAL scans and external sorts) plus its measured cost: a plain SELECT is executed once and the records and pages it actually touched are reported')]
    function FbAnalyzeQuery([MCPParam('The SQL query to analyze')] const sql: string): TMCPToolResult;
    [MCPTool('fb_suggest_indexes', 'Suggests new indexes for the NATURAL-scanned columns of a query (ready-to-run DDL)')]
    function FbSuggestIndexes([MCPParam('The SQL query to optimize')] const sql: string): TMCPToolResult;
    [MCPTool('fb_suggest_index_drops', 'Suggests droppable indexes for a table (duplicate/redundant/inactive/low-selectivity)')]
    function FbSuggestIndexDrops([MCPParam('Table name')] const table_name: string): TMCPToolResult;
    [MCPTool('fb_audit_table', 'Schema-health audit of a table: missing PK, over-indexing, stale statistics')]
    function FbAuditTable([MCPParam('Table name')] const table_name: string): TMCPToolResult;
    [MCPTool('fb_evaluate_goal', 'Deterministically measures an optimization goal and returns whether it is met')]
    function FbEvaluateGoal(
      [MCPParam('Goal type: query_no_natural_scan | query_time_ms | no_redundant_indexes')] const goal_type: string;
      [MCPParam('Target: a SQL query or a table name')] const target: string;
      [MCPParam('Threshold (ms for query_time_ms; ignored otherwise)', TMCPParamPresence.Optional)] const threshold: Double): TMCPToolResult;
    [MCPTool('fb_monitor_transactions', 'Transaction/sweep health at this instant: OIT/OAT/Next gap and any blocking long-running transaction')]
    function FbMonitorTransactions(
      [MCPParam('Minutes an active transaction must run before being flagged as blocking (default 5)', TMCPParamPresence.Optional)] const stale_minutes: Integer): TMCPToolResult;
    [MCPTool('fb_sample_activity', 'Reads the MON$ counters twice over a window and reports the difference: records read sequentially and by index, pages moved, record versions collected, and whether the transaction horizon advanced. Use this when the question is what is changing over time rather than what is true right now')]
    function FbSampleActivity(
      [MCPParam('Length of the observation window in seconds (default 5, 1-60)', TMCPParamPresence.Optional)] const seconds: Integer): TMCPToolResult;
  end;
implementation
uses
  System.SysUtils, System.Classes, System.Diagnostics, System.StrUtils, JsonDataObjects,
  Firebird.Connection, Firebird.Capabilities, Firebird.Introspection,
  Firebird.DocGen, Firebird.PlanAnalyzer, Firebird.IndexAdvisor, Firebird.Advisory,
  Firebird.SchemaAudit, Firebird.Goal, Firebird.TransactionMonitor, Firebird.Activity,
  FirebirdToolRuntimeU, MVCFramework.MCP.Server, MVCFramework.Logger;

const DEFAULT_STALE_MINUTES = 5;
const DEFAULT_SAMPLE_SECONDS = 5;

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
        AdvisoriesToText(A.SuggestForQuery(LSql), 'No new index suggested: the query has no NATURAL scan.'),
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

initialization
  TMCPServer.Instance.RegisterToolProvider(TFirebirdTools);
end.
