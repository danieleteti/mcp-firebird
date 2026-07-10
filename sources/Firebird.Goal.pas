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
  public
    constructor Create(AConn: TFirebirdConnection; const AEngineVersion: string);
    function Evaluate(const AGoalType, ATarget: string; AThreshold: Double): TGoalResult;
  end;
implementation
uses System.SysUtils, System.Diagnostics, FireDAC.Comp.Client,
  Firebird.PlanAnalyzer, Firebird.IndexAdvisor;

constructor TFirebirdGoal.Create(AConn: TFirebirdConnection; const AEngineVersion: string);
begin inherited Create; FConn := AConn; FEngineVersion := AEngineVersion; end;

function TFirebirdGoal.EvalNoNaturalScan(const ASQL: string): TGoalResult;
var PA: TFirebirdPlanAnalyzer; R: TPlanResult;
begin
  Result := Default(TGoalResult);
  Result.GoalType := 'query_no_natural_scan'; Result.Target := ASQL; Result.EngineVersion := FEngineVersion;
  PA := TFirebirdPlanAnalyzer.Create(FConn, FEngineVersion);
  try R := PA.Analyze(ASQL); finally PA.Free; end;
  Result.Measured := Ord(R.HasNaturalScan);
  Result.Met := not R.HasNaturalScan;
  Result.Hint := 'plan: ' + R.RawPlan;
end;

function TFirebirdGoal.EvalQueryTimeMs(const ASQL: string; AThreshold: Double): TGoalResult;
var SW: TStopwatch; Q: TFDQuery;
begin
  Result := Default(TGoalResult);
  Result.GoalType := 'query_time_ms'; Result.Target := ASQL; Result.Threshold := AThreshold; Result.EngineVersion := FEngineVersion;
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

function TFirebirdGoal.Evaluate(const AGoalType, ATarget: string; AThreshold: Double): TGoalResult;
begin
  if SameText(AGoalType, 'query_no_natural_scan') then Result := EvalNoNaturalScan(ATarget)
  else if SameText(AGoalType, 'query_time_ms')     then Result := EvalQueryTimeMs(ATarget, AThreshold)
  else if SameText(AGoalType, 'no_redundant_indexes') then Result := EvalNoRedundantIndexes(ATarget)
  else raise Exception.CreateFmt('Unknown goal_type: %s', [AGoalType]);
end;
end.
