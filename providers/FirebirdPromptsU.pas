unit FirebirdPromptsU;
interface
uses JsonDataObjects, MVCFramework.MCP.PromptProvider, MVCFramework.MCP.Attributes;
type
  TFirebirdPrompts = class(TMCPPromptProvider)
  public
    [MCPPrompt('optimization_goal', 'Iteratively optimize a query or table until a measurable goal is met')]
    [MCPPromptArg('goal_type', 'query_no_natural_scan | query_time_ms | no_redundant_indexes', TMCPParamPresence.Required)]
    [MCPPromptArg('target', 'A SQL query or a table name', TMCPParamPresence.Required)]
    [MCPPromptArg('threshold', 'Numeric threshold (ms for query_time_ms)', TMCPParamPresence.Optional)]
    [MCPPromptArg('max_iterations', 'Safety cap (default 5)', TMCPParamPresence.Optional)]
    function OptimizationGoal(const Arguments: TJDOJsonObject): TMCPPromptResult;

    [MCPPrompt('health_check', 'Run a read-only health review of the configured Firebird database')]
    function HealthCheck(const Arguments: TJDOJsonObject): TMCPPromptResult;
  end;
implementation
uses System.SysUtils, MVCFramework.MCP.Server;

function TFirebirdPrompts.OptimizationGoal(const Arguments: TJDOJsonObject): TMCPPromptResult;
var GT, Target, Thr, MaxIt: string;
begin
  GT := Arguments.S['goal_type']; Target := Arguments.S['target'];
  Thr := Arguments.S['threshold']; MaxIt := Arguments.S['max_iterations'];
  if MaxIt.IsEmpty then MaxIt := '5';
  Result := TMCPPromptResult.Create(
    'Goal-driven Firebird optimization',
    [
      PromptMessage('user',
        'You are optimizing a Firebird database toward a measurable goal.' + sLineBreak +
        'goal_type = ' + GT + sLineBreak +
        'target = ' + Target + sLineBreak +
        'threshold = ' + Thr + sLineBreak +
        'max_iterations = ' + MaxIt + sLineBreak + sLineBreak +
        'Protocol - follow it exactly:' + sLineBreak +
        '1. Call fb_evaluate_goal(goal_type, target, threshold) to establish the baseline.' + sLineBreak +
        '2. If met=true, STOP and report the result.' + sLineBreak +
        '3. Otherwise call fb_analyze_query and fb_suggest_indexes (for query goals) or ' +
        'fb_suggest_index_drops (for table goals). Present the suggested SQL. If the user has ' +
        'enabled writes (firebird.allow_ddl=true) you may apply it with the write tools; otherwise ' +
        'ask the user to run the SQL.' + sLineBreak +
        '4. Call fb_evaluate_goal again and compare "measured" to the previous iteration.' + sLineBreak +
        '5. Repeat until met=true, OR max_iterations is reached, OR there is no improvement for 2 ' +
        'consecutive iterations. In the last two cases, report the best result found and explain ' +
        'why the goal appears unreachable.' + sLineBreak + sLineBreak +
        'Always show the engine_version from fb_evaluate_goal so the advice is version-correct.'),
      PromptMessage('assistant',
        'Understood. I will start by measuring the baseline with fb_evaluate_goal, then iterate ' +
        'with analysis and index suggestions, stopping as soon as the goal is met or cannot improve.')
    ]);
end;

function TFirebirdPrompts.HealthCheck(const Arguments: TJDOJsonObject): TMCPPromptResult;
begin
  Result := TMCPPromptResult.Create(
    'Firebird health check',
    [
      PromptMessage('user',
        'Perform a read-only health review of the configured Firebird database. Steps:' + sLineBreak +
        '1. Call fb_info and report the engine version and capabilities.' + sLineBreak +
        '2. Call fb_list_tables.' + sLineBreak +
        '3. For each table, call fb_suggest_index_drops and collect the findings.' + sLineBreak +
        '4. Summarize: redundant/duplicate/inactive indexes, with the ready-to-run SQL grouped by table.')
    ]);
end;

initialization
  TMCPServer.Instance.RegisterPromptProvider(TFirebirdPrompts);
end.
