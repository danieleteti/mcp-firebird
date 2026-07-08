// SPDX-License-Identifier: Apache-2.0
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
    [MCPTool('fb_describe_table', 'Columns, primary key, indexes and foreign keys of a table')]
    function FbDescribeTable([MCPParam('Table name')] const table_name: string): TMCPToolResult;
    [MCPTool('fb_generate_documentation', 'Markdown documentation for one table, or the whole database when table_name is empty')]
    function FbGenerateDocumentation([MCPParam('Table name; leave empty for the whole database', TMCPParamPresence.Optional)] const table_name: string): TMCPToolResult;
    [MCPTool('fb_analyze_query', 'Returns and analyzes the access plan of a SQL query (flags NATURAL scans and external sorts)')]
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
    [MCPTool('fb_monitor_transactions', 'Transaction/sweep health: OIT/OAT/Next gap and any blocking long-running transaction')]
    function FbMonitorTransactions(
      [MCPParam('Minutes an active transaction must run before being flagged as blocking (default 5)', TMCPParamPresence.Optional)] const stale_minutes: Integer): TMCPToolResult;
  end;
implementation
uses
  System.SysUtils, System.Classes, System.Diagnostics, System.StrUtils, JsonDataObjects,
  Firebird.Connection, Firebird.Capabilities, Firebird.Introspection,
  Firebird.DocGen, Firebird.PlanAnalyzer, Firebird.IndexAdvisor, Firebird.Advisory,
  Firebird.SchemaAudit, Firebird.Goal, Firebird.TransactionMonitor, FirebirdConfigU,
  MVCFramework.MCP.Server, MVCFramework.Logger;

const DEFAULT_STALE_MINUTES = 5;

{ Traces every tool invocation to the log and turns any exception (most commonly
  a database connection / communication failure) into a tool result with
  isError=true, so the message is returned to the MCP client and shown to the
  user — instead of bubbling up as a generic JSON-RPC -32603 that clients render
  as an opaque "Failed to call tool".

  Log trail per call (all under the 'mcp' tag):
    [INFO ] >> fb_xxx  <args>            (invocation, with the arguments received)
    [INFO ] << fb_xxx  ok|isError  NNms  (completion + elapsed time)
    [ERROR] !! fb_xxx failed - <message> (only on exception)

  Protocol errors (unknown tool, missing required param) are still raised by the
  request handler and remain JSON-RPC errors. }
function Guard(const AToolName, AArgs: string; const AAction: TFunc<TMCPToolResult>): TMCPToolResult;
var SW: TStopwatch;
begin
  LogI(Format('>> %s  %s', [AToolName, AArgs]), 'mcp');
  SW := TStopwatch.StartNew;
  try
    Result := AAction();
    LogI(Format('<< %s  %s  %dms',
      [AToolName, IfThen(Result.IsError, 'isError', 'ok'), SW.ElapsedMilliseconds]), 'mcp');
  except
    on E: Exception do
    begin
      LogException(E, Format('!! %s failed after %dms', [AToolName, SW.ElapsedMilliseconds]));
      Result := TMCPToolResult.Error('Firebird error (' + E.ClassName + '): ' + E.Message);
    end;
  end;
end;

function AdvisoriesToText(const Advs: TArray<TAdvisory>; const AEmptyMsg: string): string;
var SB: TStringBuilder; X: TAdvisory;
begin
  if Length(Advs) = 0 then Exit(AEmptyMsg);
  SB := TStringBuilder.Create;
  try
    for X in Advs do
      SB.AppendLine('### ' + X.Severity).AppendLine('**Finding:** ' + X.Finding)
        .AppendLine.AppendLine('```sql').AppendLine(X.SQLText).AppendLine('```')
        .AppendLine('**Verify:** ' + X.Verify).AppendLine;
    Result := SB.ToString;
  finally SB.Free; end;
end;

function TFirebirdTools.FbInfo: TMCPToolResult;
begin
  Result := Guard('fb_info', '',
    function: TMCPToolResult
    var Conn: TFirebirdConnection; C: TFirebirdCapabilities; J: TJDOJsonObject;
    begin
      Conn := NewConfiguredConnection;
      try
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
      finally Conn.Free; end;
    end);
end;

function TFirebirdTools.FbListTables: TMCPToolResult;
begin
  Result := Guard('fb_list_tables', '',
    function: TMCPToolResult
    var Conn: TFirebirdConnection; I: TFirebirdIntrospection; T: string; SB: TStringBuilder;
    begin
      Conn := NewConfiguredConnection;
      try
        I := TFirebirdIntrospection.Create(Conn); SB := TStringBuilder.Create;
        try
          for T in I.ListTables do SB.AppendLine('- ' + T);
          Result := TMCPToolResult.Text(SB.ToString);
        finally SB.Free; I.Free; end;
      finally Conn.Free; end;
    end);
end;

function TFirebirdTools.FbDescribeTable(const table_name: string): TMCPToolResult;
var LTable: string;
begin
  LTable := table_name;
  Result := Guard('fb_describe_table', 'table_name=' + LTable,
    function: TMCPToolResult
    var Conn: TFirebirdConnection; D: TFirebirdDocGen;
    begin
      Conn := NewConfiguredConnection;
      try
        D := TFirebirdDocGen.Create(TFirebirdIntrospection.Create(Conn));
        try Result := TMCPToolResult.Text(D.TableMarkdown(LTable.ToUpper)); finally D.Free; end;
      finally Conn.Free; end;
    end);
end;

function TFirebirdTools.FbGenerateDocumentation(const table_name: string): TMCPToolResult;
var LTable: string;
begin
  LTable := table_name;
  Result := Guard('fb_generate_documentation', 'table_name=' + LTable,
    function: TMCPToolResult
    var Conn: TFirebirdConnection; D: TFirebirdDocGen;
    begin
      Conn := NewConfiguredConnection;
      try
        D := TFirebirdDocGen.Create(TFirebirdIntrospection.Create(Conn));
        try
          if LTable.Trim.IsEmpty then Result := TMCPToolResult.Text(D.DatabaseMarkdown)
          else Result := TMCPToolResult.Text(D.TableMarkdown(LTable.ToUpper));
        finally D.Free; end;
      finally Conn.Free; end;
    end);
end;

function TFirebirdTools.FbAnalyzeQuery(const sql: string): TMCPToolResult;
var LSql: string;
begin
  LSql := sql;
  Result := Guard('fb_analyze_query', 'sql=' + LSql,
    function: TMCPToolResult
    var Conn: TFirebirdConnection; PA: TFirebirdPlanAnalyzer; R: TPlanResult; SB: TStringBuilder;
    begin
      Conn := NewConfiguredConnection;
      try
        PA := TFirebirdPlanAnalyzer.Create(Conn, TFirebirdCapabilities.Detect(Conn)); SB := TStringBuilder.Create;
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
          Result := TMCPToolResult.Text(SB.ToString);
        finally SB.Free; PA.Free; end;
      finally Conn.Free; end;
    end);
end;

function TFirebirdTools.FbSuggestIndexes(const sql: string): TMCPToolResult;
var LSql: string;
begin
  LSql := sql;
  Result := Guard('fb_suggest_indexes', 'sql=' + LSql,
    function: TMCPToolResult
    var Conn: TFirebirdConnection; A: TFirebirdIndexAdvisor;
    begin
      Conn := NewConfiguredConnection;
      try
        A := TFirebirdIndexAdvisor.Create(Conn, TFirebirdCapabilities.Detect(Conn));
        try Result := TMCPToolResult.Text(AdvisoriesToText(A.SuggestForQuery(LSql), 'No new index suggested: the query has no NATURAL scan.'));
        finally A.Free; end;
      finally Conn.Free; end;
    end);
end;

function TFirebirdTools.FbSuggestIndexDrops(const table_name: string): TMCPToolResult;
var LTable: string;
begin
  LTable := table_name;
  Result := Guard('fb_suggest_index_drops', 'table_name=' + LTable,
    function: TMCPToolResult
    var Conn: TFirebirdConnection; A: TFirebirdIndexAdvisor;
    begin
      Conn := NewConfiguredConnection;
      try
        A := TFirebirdIndexAdvisor.Create(Conn, TFirebirdCapabilities.Detect(Conn));
        try Result := TMCPToolResult.Text(AdvisoriesToText(A.SuggestDropsForTable(LTable.ToUpper), 'No droppable indexes found on ' + LTable + '.'));
        finally A.Free; end;
      finally Conn.Free; end;
    end);
end;

function TFirebirdTools.FbAuditTable(const table_name: string): TMCPToolResult;
var LTable: string;
begin
  LTable := table_name;
  Result := Guard('fb_audit_table', 'table_name=' + LTable,
    function: TMCPToolResult
    var Conn: TFirebirdConnection; A: TFirebirdSchemaAudit;
    begin
      Conn := NewConfiguredConnection;
      try
        A := TFirebirdSchemaAudit.Create(Conn);
        try Result := TMCPToolResult.Text(AdvisoriesToText(A.AuditTable(LTable.ToUpper),
          'No schema-health issues found on ' + LTable + '.'));
        finally A.Free; end;
      finally Conn.Free; end;
    end);
end;

function TFirebirdTools.FbEvaluateGoal(const goal_type, target: string; const threshold: Double): TMCPToolResult;
var LGoalType, LTarget: string; LThreshold: Double;
begin
  LGoalType := goal_type; LTarget := target; LThreshold := threshold;
  Result := Guard('fb_evaluate_goal',
    Format('goal_type=%s target=%s threshold=%g', [LGoalType, LTarget, LThreshold]),
    function: TMCPToolResult
    var Conn: TFirebirdConnection; G: TFirebirdGoal; R: TGoalResult; J: TJDOJsonObject;
    begin
      Conn := NewConfiguredConnection;
      try
        G := TFirebirdGoal.Create(Conn, TFirebirdCapabilities.Detect(Conn));
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
      finally Conn.Free; end;
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
    function: TMCPToolResult
    var Conn: TFirebirdConnection; M: TFirebirdTransactionMonitor; S: TTransactionSnapshot; SB: TStringBuilder;
    begin
      Conn := NewConfiguredConnection;
      try
        M := TFirebirdTransactionMonitor.Create(Conn, TFirebirdCapabilities.Detect(Conn));
        SB := TStringBuilder.Create;
        try
          S := M.Snapshot;
          SB.AppendLine(Format('**OIT:** %d  **OAT:** %d  **OST:** %d  **Next:** %d  **Gap:** %d',
            [S.OIT, S.OAT, S.OST, S.NextTransaction, S.Gap])).AppendLine;
          SB.Append(AdvisoriesToText(M.Analyze(LStaleMinutes), 'No transaction/sweep issues found.'));
          Result := TMCPToolResult.Text(SB.ToString);
        finally SB.Free; M.Free; end;
      finally Conn.Free; end;
    end);
end;

initialization
  TMCPServer.Instance.RegisterToolProvider(TFirebirdTools);
end.
