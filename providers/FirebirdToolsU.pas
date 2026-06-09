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
    [MCPTool('fb_evaluate_goal', 'Deterministically measures an optimization goal and returns whether it is met')]
    function FbEvaluateGoal(
      [MCPParam('Goal type: query_no_natural_scan | query_time_ms | no_redundant_indexes')] const goal_type: string;
      [MCPParam('Target: a SQL query or a table name')] const target: string;
      [MCPParam('Threshold (ms for query_time_ms; ignored otherwise)', TMCPParamPresence.Optional)] const threshold: Double): TMCPToolResult;
  end;
implementation
uses
  System.SysUtils, System.Classes, JsonDataObjects,
  Firebird.Connection, Firebird.Capabilities, Firebird.Introspection,
  Firebird.DocGen, Firebird.PlanAnalyzer, Firebird.IndexAdvisor, Firebird.Advisory,
  Firebird.Goal, FirebirdConfigU, MVCFramework.MCP.Server;

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
end;

function TFirebirdTools.FbListTables: TMCPToolResult;
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
end;

function TFirebirdTools.FbDescribeTable(const table_name: string): TMCPToolResult;
var Conn: TFirebirdConnection; D: TFirebirdDocGen;
begin
  Conn := NewConfiguredConnection;
  try
    D := TFirebirdDocGen.Create(TFirebirdIntrospection.Create(Conn));
    try Result := TMCPToolResult.Text(D.TableMarkdown(table_name.ToUpper)); finally D.Free; end;
  finally Conn.Free; end;
end;

function TFirebirdTools.FbGenerateDocumentation(const table_name: string): TMCPToolResult;
var Conn: TFirebirdConnection; D: TFirebirdDocGen;
begin
  Conn := NewConfiguredConnection;
  try
    D := TFirebirdDocGen.Create(TFirebirdIntrospection.Create(Conn));
    try
      if table_name.Trim.IsEmpty then Result := TMCPToolResult.Text(D.DatabaseMarkdown)
      else Result := TMCPToolResult.Text(D.TableMarkdown(table_name.ToUpper));
    finally D.Free; end;
  finally Conn.Free; end;
end;

function TFirebirdTools.FbAnalyzeQuery(const sql: string): TMCPToolResult;
var Conn: TFirebirdConnection; PA: TFirebirdPlanAnalyzer; R: TPlanResult; SB: TStringBuilder;
begin
  Conn := NewConfiguredConnection;
  try
    PA := TFirebirdPlanAnalyzer.Create(Conn, TFirebirdCapabilities.Detect(Conn)); SB := TStringBuilder.Create;
    try
      R := PA.Analyze(sql);
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
end;

function TFirebirdTools.FbSuggestIndexes(const sql: string): TMCPToolResult;
var Conn: TFirebirdConnection; A: TFirebirdIndexAdvisor;
begin
  Conn := NewConfiguredConnection;
  try
    A := TFirebirdIndexAdvisor.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try Result := TMCPToolResult.Text(AdvisoriesToText(A.SuggestForQuery(sql), 'No new index suggested: the query has no NATURAL scan.'));
    finally A.Free; end;
  finally Conn.Free; end;
end;

function TFirebirdTools.FbSuggestIndexDrops(const table_name: string): TMCPToolResult;
var Conn: TFirebirdConnection; A: TFirebirdIndexAdvisor;
begin
  Conn := NewConfiguredConnection;
  try
    A := TFirebirdIndexAdvisor.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try Result := TMCPToolResult.Text(AdvisoriesToText(A.SuggestDropsForTable(table_name.ToUpper), 'No droppable indexes found on ' + table_name + '.'));
    finally A.Free; end;
  finally Conn.Free; end;
end;

function TFirebirdTools.FbEvaluateGoal(const goal_type, target: string; const threshold: Double): TMCPToolResult;
var Conn: TFirebirdConnection; G: TFirebirdGoal; R: TGoalResult; J: TJDOJsonObject;
begin
  Conn := NewConfiguredConnection;
  try
    G := TFirebirdGoal.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try
      R := G.Evaluate(goal_type, target, threshold);
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
end;

initialization
  TMCPServer.Instance.RegisterToolProvider(TFirebirdTools);
end.
