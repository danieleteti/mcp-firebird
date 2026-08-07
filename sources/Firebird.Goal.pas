// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit Firebird.Goal;
interface
uses Firebird.Connection;
type
  TGoalResult = record
    GoalType, Target: string;
    Measured, Threshold, Gap: Double;
    Met: Boolean;
    Hint, EngineVersion, DetailsJSON: string;
  end;
  TFirebirdGoal = class
  private
    FConn: TFirebirdConnection;
    FEngineVersion: string;
    function EvalNoNaturalScan(const ASQL: string): TGoalResult;
    function EvalQueryTimeMs(const ASQL: string; AThreshold: Double): TGoalResult;
    function EvalNoRedundantIndexes(const ATable: string): TGoalResult;
    function EvalNoStaleIndexStatistics(const ATable: string): TGoalResult;
  public
    constructor Create(AConn: TFirebirdConnection; const AEngineVersion: string);
    function Evaluate(const AGoalType, ATarget: string; AThreshold: Double): TGoalResult;
  end;

const
  GOAL_TYPES = 'query_no_natural_scan | query_time_ms | no_redundant_indexes | ' +
               'no_stale_index_statistics';

implementation
uses System.SysUtils, System.Diagnostics, FireDAC.Comp.Client,
  Firebird.PlanAnalyzer, Firebird.IndexAdvisor, Firebird.SchemaAudit,
  Firebird.Capabilities, Firebird.Activity;

constructor TFirebirdGoal.Create(AConn: TFirebirdConnection; const AEngineVersion: string);
begin inherited Create; FConn := AConn; FEngineVersion := AEngineVersion; end;

function TFirebirdGoal.EvalNoNaturalScan(const ASQL: string): TGoalResult;
var PA: TFirebirdPlanAnalyzer; R: TPlanResult; Act: TFirebirdActivity; Cost: TStatementCost;
begin
  Result := Default(TGoalResult);
  Result.GoalType := 'query_no_natural_scan'; Result.Target := ASQL; Result.EngineVersion := FEngineVersion;
  PA := TFirebirdPlanAnalyzer.Create(FConn, FEngineVersion);
  try R := PA.Analyze(ASQL); finally PA.Free; end;
  Result.Measured := Ord(R.HasNaturalScan);
  Result.Met := not R.HasNaturalScan;
  Result.Hint := 'plan: ' + R.RawPlan;
  if Result.Met then Exit;

  { The goal stays literal — it is a goal about the plan, and redefining it would break a
    published contract. But a loop that iterates toward "no NATURAL scan" needs to be able to
    stop honestly when the scan is the right plan, so the hint carries what the scan actually
    cost. }
  Act := TFirebirdActivity.Create(FConn, TFirebirdCapabilities.Parse(FEngineVersion));
  try Cost := Act.Measure(ASQL); finally Act.Free; end;
  if not Cost.Executed then
    Result.Hint := Result.Hint + sLineBreak + 'not measured: ' + Cost.SkipReason
  else if Cost.Delta.RecordReads > 0 then
    Result.Hint := Result.Hint + sLineBreak +
      Format('measured: %d records read to return %d (%.0f%% kept). Run fb_suggest_indexes on ' +
        'this query for the next move — it proposes refreshing statistics before building ' +
        'anything, and says so when the scan is the correct plan and this goal cannot be met ' +
        'without making the query slower.',
        [Cost.Delta.RecordReads, Cost.Rows, Cost.Rows / Cost.Delta.RecordReads * 100],
        TFormatSettings.Invariant);
end;

function TFirebirdGoal.EvalQueryTimeMs(const ASQL: string; AThreshold: Double): TGoalResult;
var SW: TStopwatch; Q: TFDQuery;
begin
  Result := Default(TGoalResult);
  Result.GoalType := 'query_time_ms'; Result.Target := ASQL; Result.Threshold := AThreshold; Result.EngineVersion := FEngineVersion;
  // This goal is the one place in the server that runs the caller's SQL to time it. Timing a
  // DELETE would execute it, and the tool advertises itself as read-only.
  if not IsReadOnlySelect(ASQL) then
    raise Exception.Create('query_time_ms times a plain SELECT; this statement is not one, and ' +
      'this server does not execute statements that could write.');
  // An unbound parameter executes as NULL and matches nothing, so the number this goal would
  // report is the time it takes to return no rows — met, always, and about nothing.
  if HasParameters(ASQL) then
    raise Exception.Create('query_time_ms cannot time a statement with unbound parameters: they ' +
      'execute as NULL, match nothing, and the measurement would describe a query nobody runs. ' +
      'Substitute representative literal values.');
  SW := TStopwatch.StartNew;
  Q := FConn.OpenQuery(ASQL);
  try while not Q.Eof do Q.Next; finally Q.Free; end;
  Result.Measured := SW.Elapsed.TotalMilliseconds;
  Result.Gap := Result.Measured - AThreshold;
  Result.Met := Result.Measured <= AThreshold;
end;

function TFirebirdGoal.EvalNoRedundantIndexes(const ATable: string): TGoalResult;
var A: TFirebirdIndexAdvisor; Drops: Integer;
begin
  Result := Default(TGoalResult);
  Result.GoalType := 'no_redundant_indexes'; Result.Target := ATable; Result.EngineVersion := FEngineVersion;
  A := TFirebirdIndexAdvisor.Create(FConn, FEngineVersion);
  try Drops := Length(A.SuggestDropsForTable(ATable)); finally A.Free; end;
  Result.Measured := Drops;
  Result.Met := Drops = 0;
  Result.Hint := Format('%d index drop suggestion(s) outstanding', [Drops]);
end;

{ The first move the loop can make that writes nothing structural.

  Firebird stores an index's selectivity when the index is built and never recalculates it, so
  a database that has been loaded since is optimized against numbers from before the load. Every
  other goal here asks the loop to change the schema; this one asks it to tell the optimizer the
  truth first. }
function TFirebirdGoal.EvalNoStaleIndexStatistics(const ATable: string): TGoalResult;
var Audit: TFirebirdSchemaAudit; Stale: TArray<TStaleIndexInfo>; S: TStaleIndexInfo; H: string;
begin
  Result := Default(TGoalResult);
  Result.GoalType := 'no_stale_index_statistics'; Result.Target := ATable;
  Result.EngineVersion := FEngineVersion;
  Audit := TFirebirdSchemaAudit.Create(FConn);
  try Stale := Audit.StaleIndexes(ATable); finally Audit.Free; end;
  Result.Measured := Length(Stale);
  Result.Met := Length(Stale) = 0;
  if Result.Met then
    Result.Hint := Format('every index on %s is costed against current statistics', [ATable])
  else
  begin
    for S in Stale do
      H := H + Format('%s (stored %g, actual %g); ', [S.IndexName, S.Stored, S.Actual],
        TFormatSettings.Invariant);
    Result.Hint := Format('%d index(es) on %s hold statistics that no longer describe the data: %s' +
      'Run SET STATISTICS INDEX on each, then evaluate again.', [Length(Stale), ATable, H]);
  end;
end;

function TFirebirdGoal.Evaluate(const AGoalType, ATarget: string; AThreshold: Double): TGoalResult;
begin
  if SameText(AGoalType, 'query_no_natural_scan') then Result := EvalNoNaturalScan(ATarget)
  else if SameText(AGoalType, 'query_time_ms')     then Result := EvalQueryTimeMs(ATarget, AThreshold)
  else if SameText(AGoalType, 'no_redundant_indexes') then Result := EvalNoRedundantIndexes(ATarget)
  else if SameText(AGoalType, 'no_stale_index_statistics') then Result := EvalNoStaleIndexStatistics(ATarget)
  else raise Exception.CreateFmt('Unknown goal_type: %s. Known types: %s', [AGoalType, GOAL_TYPES]);
end;
end.
