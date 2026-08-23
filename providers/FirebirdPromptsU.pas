// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
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

    [MCPPrompt('app_user_plan', 'Work out what privileges an application account should have, by asking what the application actually does — for the very common case of an application that connects as SYSDBA')]
    [MCPPromptArg('application', 'What the application is and what it does, in your words', TMCPParamPresence.Optional)]
    [MCPPromptArg('user_name', 'The account you want it to use (default APP)', TMCPParamPresence.Optional)]
    function AppUserPlan(const Arguments: TJDOJsonObject): TMCPPromptResult;

    [MCPPrompt('classify_problem', 'Classify a performance symptom before investigating it: which kind of problem this is, which reasoning converges on it, and which of these tools can and cannot answer it')]
    [MCPPromptArg('symptom', 'What the users actually observe, in their words', TMCPParamPresence.Required)]
    function ClassifyProblem(const Arguments: TJDOJsonObject): TMCPPromptResult;
  end;
implementation
uses System.SysUtils, System.StrUtils, MVCFramework.MCP.Server;

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
        'fb_suggest_index_drops (for table goals). Present the suggested SQL and ask the user to ' +
        'run it — this server is read-only and cannot apply it.' + sLineBreak +
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
        { A health review that never asks who may read the data is a review of half the database.
          One call, whatever the schema size: the grants are one report, not one per table. }
        '4. Call fb_audit_security once and collect the grant findings.' + sLineBreak +
        '5. Summarize in two parts: redundant/duplicate/inactive indexes with the ready-to-run ' +
        'SQL grouped by table, then the grant findings, criticals first. Say plainly that the ' +
        'grant half stops at the database: accounts, admin roles and authentication live in the ' +
        'security database, which this server does not attach to.')
    ]);
end;

{ The one prompt here that starts from a decision nobody has made yet.

  A Firebird application that connects as SYSDBA is not a database with a privilege problem. It
  is a database where privileges do not apply: SYSDBA is not subject to them, so nothing anybody
  grants or revokes changes what that application can do. There is no analysis to run and no
  finding to report — the work is deciding what the application actually needs, and that is a
  set of questions, not a query.

  So the prompt asks. It looks first (the engine version decides how a role is activated, the
  table names suggest the bundles, the existing PUBLIC grants can void the whole plan), then
  asks only what the catalogue cannot answer, and only questions whose answers change the SQL.
  The fallback matters as much as the interview: somebody who cannot classify their own schema
  still gets a real improvement, because an account with DML on every table is a different thing
  from SYSDBA. }
function TFirebirdPrompts.AppUserPlan(const Arguments: TJDOJsonObject): TMCPPromptResult;
var
  lApplication, lUser: string;
begin
  lApplication := Arguments.S['application'];
  lUser := Arguments.S['user_name'];
  if lUser.IsEmpty then
    lUser := 'APP';
  Result := TMCPPromptResult.Create(
    'Privileges for an application account',
    [
      PromptMessage('user',
        'Design the privileges for an application account on this Firebird database, and produce ' +
        'the SQL that establishes them.' + sLineBreak +
        'application = ' + IfThen(lApplication = '', '(not described yet — ask)', lApplication) + sLineBreak +
        'user_name = ' + lUser + sLineBreak + sLineBreak +

        'Start from what is true of most Firebird installations: the application connects as ' +
        'SYSDBA. Say this plainly, once, before anything else — SYSDBA is not subject to ' +
        'privilege checks, and neither is the owner of an object. While the application connects ' +
        'as either, no GRANT or REVOKE changes anything it can do. The work is not tightening ' +
        'grants; it is moving the application onto an account that grants apply to.' + sLineBreak + sLineBreak +

        'STEP 1 — look, so you do not ask what you can see.' + sLineBreak +
        '- fb_info: the engine version decides how the role is activated (4.0+ can make it ' +
        'DEFAULT; below that the application must pass the role at connect time or it gets ' +
        'nothing).' + sLineBreak +
        '- fb_list_tables: read the names and propose the groupings you can see — a common ' +
        'prefix, an obvious log or audit table, tables that look like reference data.' + sLineBreak +
        '- fb_audit_security: whatever PUBLIC already holds is held by every account, including ' +
        'the new one. A plan that ignores it is not a plan.' + sLineBreak +
        '- fb_audit_security(user_name) once you have a name: it answers what that one account ' +
        'can reach today and how — directly, through PUBLIC, or through a role — which is also ' +
        'how you check the plan afterwards.' + sLineBreak + sLineBreak +

        'STEP 2 — ask. Few questions, in this order, and skip any you have already answered from ' +
        'STEP 1. Ask two or three at a time, not as a form. Each one changes the statements:' + sLineBreak +
        '1. Which objects belong to this application? Offer the prefixes you found; "all of ' +
        'them" is a valid answer and you must accept it without pushing back.' + sLineBreak +
        '2. Does it write to all of them, or only read some? Reference and lookup tables it only ' +
        'reads are a separate, read-only bundle.' + sLineBreak +
        '3. Is there anything it must never touch — an audit trail, payroll, another tenant''s ' +
        'tables? That becomes an exclusion, not a promise.' + sLineBreak +
        '4. Does it call stored procedures that live outside those names?' + sLineBreak +
        '5. Does it create or alter objects while it runs — migrations at startup, a table built ' +
        'on first use? If yes, that is the one requirement that needs DDL rights, and it belongs ' +
        'to a separate account a person runs deliberately, not to the account the application ' +
        'uses all day.' + sLineBreak +
        '6. Can the application''s connection string be changed? Ask this only if fb_info says ' +
        'the engine is below 4.0. There a role is inactive unless the connection names it, so ' +
        'privileges on a role do nothing until the application sends RoleName=... — if that ' +
        'string cannot be touched, the privileges have to go straight on the account ' +
        '(grant_to=user, which is what fb_suggest_grants defaults to below 4.0).' + sLineBreak +
        '7. Does anything else connect with the same account — reports, a nightly job, an ' +
        'integration? Each of those is its own account and its own role, otherwise the ' +
        'privileges of the application become the union of every job that shares its password.' + sLineBreak +
        '8. Who creates the objects? If this account creates them it owns them, and an owner can ' +
        'drop what it owns whatever you granted. Schema ownership stays with SYSDBA or a ' +
        'dedicated owner account.' + sLineBreak + sLineBreak +

        'STEP 3 — generate. Call fb_suggest_grants once per bundle, passing the same role_name ' +
        'every time so the role is created once and the privileges accumulate on it: ' +
        'fb_suggest_grants(user_name, object_pattern, access, role_name, exclude_pattern). ' +
        'Do not write GRANT statements yourself — the tool reads the catalogue, quotes ' +
        'identifiers the way this engine needs them, and emits the role grant in the form this ' +
        'version supports. Show its SQL verbatim.' + sLineBreak + sLineBreak +

        'STEP 4 — hand it over honestly. Along with the SQL, say:' + sLineBreak +
        '- What has to change outside the database: the connection string moves to ' + lUser +
        ', and below 4.0 it must also carry the role name or every grant above is inert.' + sLineBreak +
        '- What to test before switching production: the application against a restored copy, ' +
        'not against the live database. A privilege change breaks whatever quietly depended on ' +
        'being SYSDBA — reading MON$ tables, running utilities, creating something at startup.' + sLineBreak +
        '- What this does not do: SYSDBA still exists and is still needed for backups and ' +
        'administration. The point is that it stops being what the application uses.' + sLineBreak +
        '- If the application only reads, its connection can also open read-only transactions, ' +
        'which is a second, independent guarantee.' + sLineBreak + sLineBreak +

        'Two rules for the whole exchange. Never claim the application will still work — you ' +
        'cannot know that, and say so. And if the answers do not arrive or the user does not ' +
        'know their own schema, do not stall: propose the fallback, which is a real improvement ' +
        'and not a compromise. An account with SELECT, INSERT, UPDATE and DELETE on every user ' +
        'table still cannot drop a table, alter the schema, read the security database, create ' +
        'accounts or shut the server down. Offer it, name what it does not solve, and produce it.'),
      PromptMessage('assistant',
        'Understood. I will check the engine version, the object names and what PUBLIC already ' +
        'holds first, then ask only what those cannot tell me, and produce the statements with ' +
        'fb_suggest_grants rather than writing GRANTs by hand. I will start by saying what ' +
        'connecting as SYSDBA means for privileges.')
    ]);
end;

{ Every other entry point here starts from a tool. This one starts from the symptom, because
  reaching for a tool first is how an investigation ends up with a stack of correct answers to
  questions nobody asked. The taxonomy is the one in Cisar & Reeves, "Practical Firebird
  Performance Diagnostics" (IBPhoenix, 2026): classify, then choose the reasoning, then choose
  the instrument.

  The uncomfortable half of this prompt is the last section. Four of the seven classes cannot be
  settled with an ordinary SQL connection, and this server has nothing but an ordinary SQL
  connection. Saying so is worth more than a confident answer built out of the evidence that
  happened to be reachable. }
function TFirebirdPrompts.ClassifyProblem(const Arguments: TJDOJsonObject): TMCPPromptResult;
var Symptom: string;
begin
  Symptom := Arguments.S['symptom'];
  Result := TMCPPromptResult.Create(
    'Classify a Firebird performance problem',
    [
      PromptMessage('user',
        'A Firebird system is behaving badly. Reported symptom:' + sLineBreak +
        '  ' + Symptom + sLineBreak + sLineBreak +
        'Classify the problem BEFORE running any tool. A check answers the question it was ' +
        'built for; it does not explain a symptom, and a pile of correct checks does not become ' +
        'an explanation. Work in this order and do not skip ahead.' + sLineBreak + sLineBreak +

        'STEP 1 — Place the symptom on these six axes. Ask the user only what you cannot infer, ' +
        'and say explicitly which answers you are missing.' + sLineBreak +
        '1. Temporal shape: instant under load, or growing over hours/days? Does a restart or an ' +
        'idle period reset it?' + sLineBreak +
        '2. Load sensitivity: does it track the AMOUNT of work (volume) or the NUMBER of things ' +
        'happening at once (concurrency)? These fail by different mechanisms.' + sLineBreak +
        '3. Locality: is the pain spread across the schema, or does it converge on a few tables, ' +
        'indexes or rows?' + sLineBreak +
        '4. Coordination vs execution: is time spent working, or waiting for permission to work? ' +
        'Idle CPU with collapsed throughput is the signature of the second.' + sLineBreak +
        '5. Stability under observation: does the symptom change or vanish when monitoring or ' +
        'tracing is switched on?' + sLineBreak +
        '6. Environment: did the same logic behave differently after a migration, a hardware ' +
        'change or a move to a VM?' + sLineBreak + sLineBreak +

        'STEP 2 — Name the ONE dominant class. Classes overlap; pick the shape that decides how ' +
        'to proceed.' + sLineBreak +
        '- local inefficiency: degrades in proportion to work; a unit of work costs too much.' + sLineBreak +
        '- capacity exhaustion: efficient work, but a resource is the ceiling.' + sLineBreak +
        '- coordination and contention: collapses with concurrency while nothing looks saturated.' + sLineBreak +
        '- locality collapse: logically balanced, physically concentrated on a hot structure.' + sLineBreak +
        '- temporal accumulation: fine at first, worse over time, resets on restart.' + sLineBreak +
        '- observation-sensitive: the act of measuring changes the behaviour.' + sLineBreak +
        '- environment-amplified: identical logic, different environment, different behaviour.' + sLineBreak + sLineBreak +

        'STEP 3 — Apply the strategy that class demands, using the tools this server has:' + sLineBreak +
        '- local inefficiency → REDUCTION. Narrow until the expensive unit is unmistakable: ' +
        'fb_analyze_query (plan AND measured cost), fb_suggest_indexes, fb_audit_table, then ' +
        'fb_evaluate_goal to prove the change. This server converges here.' + sLineBreak +
        '- temporal accumulation → LIFECYCLE. Snapshots lie; compare windows. fb_sample_activity ' +
        'repeatedly over the working day, plus fb_monitor_transactions to name what pins the ' +
        'transaction horizon. This server can carry the investigation, not close it.' + sLineBreak +
        '- capacity exhaustion → CONFIRMATION. fb_sample_activity gives page and record rates, ' +
        'but CPU, storage latency and memory pressure live outside the database connection and ' +
        'this server cannot see them. Confirm from the host.' + sLineBreak +
        '- coordination and contention → INTERACTION-FOCUSED EXPANSION. Do not narrow. MON$ ' +
        'counts work performed, never time spent waiting for permission, so calm counters here ' +
        'are NOT evidence of absence. Vary concurrency deliberately and watch the inflection.' + sLineBreak +
        '- locality collapse → CONCENTRATION DISCOVERY. Needs the physical picture (page fill, ' +
        'index depth, version chains) that only gstat gives. Repeated fb_sample_activity plus ' +
        'per-table fb_analyze_query is a proxy, and a weak one.' + sLineBreak +
        '- observation-sensitive → MINIMAL DISTURBANCE. Note that fb_analyze_query executes the ' +
        'SELECT it measures and fb_sample_activity holds a window open; keep both short and ' +
        'compare observed against unobserved behaviour.' + sLineBreak +
        '- environment-amplified → CONTROLLED COMPARISON. Run fb_info and the same measured ' +
        'query on both environments and contrast; introspection alone will not show it.' + sLineBreak + sLineBreak +

        'RULES. State the class and the reasoning that led to it before touching a tool. Report ' +
        'a clean result as what it is — one question answered — and repeat what it does not rule ' +
        'out. If tools keep coming back clean while the symptom persists, that is evidence the ' +
        'class is wrong: reclassify instead of checking harder. If the dominant class is one ' +
        'this server cannot settle, say so plainly and name what would settle it.'),
      PromptMessage('assistant',
        'Understood. I will classify along the six axes first, name the dominant class and my ' +
        'reasoning, and only then choose tools — reporting for each what it cannot rule out, and ' +
        'saying so if the class is beyond what an SQL connection can settle.')
    ]);
end;

initialization
  TMCPServer.Instance.RegisterPromptProvider(TFirebirdPrompts);
end.
