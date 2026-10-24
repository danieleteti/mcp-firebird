// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit Firebird.PlanAnalyzer;
// Plan retrieval: a prepare through FireDAC's IB wrapper (sql_get_plan / sql_explain_plan); nothing runs.
interface
uses Firebird.Connection;
type
  { An alias the engine itself printed, which beats reading the FROM clause with a regex.
    Only the explained plan carries it, so on 2.5 this array stays empty. }
  TPlanAlias = record Alias, Table: string; end;

  { How much of an index the query actually agreed with. Firebird prints "(full match)" when
    every segment took part and a fraction — "partial match: 1/2", "lower bound: 2/2" — when
    only some did. SegmentsUsed is the best of the fractions printed for that index: a range
    scan quotes one fraction per bound, and the wider bound is the one that describes the seek. }
  TPlanIndexUse = record IndexName: string; SegmentsUsed, SegmentsTotal: Integer; end;

  TPlanResult = record
    RawPlan, ExplainedPlan, EngineVersion: string;
    HasNaturalScan, HasExternalSort: Boolean;
    { Whatever the legacy PLAN line named — an alias where the query used one. }
    NaturalTables: TArray<string>;
    { Real table names of every relation the explained plan reports as a full scan (3.0+). }
    ScannedTables: TArray<string>;
    Aliases: TArray<TPlanAlias>;
    IndexUse: TArray<TPlanIndexUse>;
    { A join whose sides are both scanned has no usable index on the join key; the count is what
      distinguishes that from a scan of a single table. }
    FullScans: Integer;
    HasJoin: Boolean;
  end;

  TFirebirdPlanAnalyzer = class
  private
    FConn: TFirebirdConnection;
    FEngineVersion: string;
    FWantExplained: Boolean;
    function GetPlanOutput(const ASQL: string; out AExplained: string): string;
  public
    constructor Create(AConn: TFirebirdConnection; const AEngineVersion: string);
    function Analyze(const ASQL: string): TPlanResult;
  end;
implementation
uses
  System.SysUtils, System.Math, System.RegularExpressions, FireDAC.Comp.Client,
  FireDAC.Phys.IBBase, FireDAC.Phys.IBWrapper, Firebird.Capabilities;

constructor TFirebirdPlanAnalyzer.Create(AConn: TFirebirdConnection; const AEngineVersion: string);
begin
  inherited Create;
  FConn := AConn;
  FEngineVersion := AEngineVersion;
  // isc_info_sql_explain_plan is a 3.0 item; below that only the legacy plan is asked for.
  FWantExplained := TFirebirdCapabilities.Parse(AEngineVersion).HasExplainedPlan;
end;

function TFirebirdPlanAnalyzer.GetPlanOutput(const ASQL: string; out AExplained: string): string;
var LStmt: string; Q: TFDQuery; Stmt: TIBStatement;
begin
  AExplained := '';
  LStmt := ASQL.Trim;
  while LStmt.EndsWith(';') do LStmt := LStmt.Substring(0, LStmt.Length - 1).TrimRight;
  // One statement only: a prepare takes a single one, and a plan for the first half of
  // "a; b" would describe a query nobody asked about.
  if StripLiterals(LStmt).Contains(';') then
    raise Exception.Create('Plan retrieval takes a single statement; remove the inner ";".');
  { Both plans from one prepare, nothing executed: the legacy PLAN line the whole codebase
    already reads and (3.0+) the explained tree with the index names, the match quality and the
    aliases. They are the same two items isql prints, asked of fbclient directly. }
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConn.FDConnection;
    Q.ResourceOptions.MacroExpand := False;
    Q.ResourceOptions.EscapeExpand := False;
    Q.SQL.Text := LStmt;
    Q.Prepare;
    Stmt := (Q.Command.CommandIntf as TFDPhysIBCommandBase).IBStatement;
    Result := Stmt.sql_get_plan.Trim;
    if FWantExplained then AExplained := Stmt.sql_explain_plan.Trim;
  finally Q.Free; end;
  // An empty plan reads as "no NATURAL scan" to every caller: an all-clear on a statement
  // Firebird gave no plan for (DDL, EXECUTE PROCEDURE).
  if Result = '' then
    raise Exception.Create('Firebird produced no plan for this statement.');
end;

{ Reads the tree Firebird prints under SET EXPLAIN ON. Node keywords, not line positions: 3.0
  and 5.0 print the same vocabulary in slightly different arrangements, and a line this parser
  does not recognise is left alone rather than counted as an absence. }
procedure ParseExplained(var R: TPlanResult);
var M, Frac: TMatch; Alias: TPlanAlias; Use: TPlanIndexUse; I: Integer; Found: Boolean;
begin
  for M in TRegEx.Matches(R.ExplainedPlan, 'Table\s+"([^"]+)"(?:\s+as\s+"([^"]+)")?([^\r\n]*)',
    [roIgnoreCase]) do
  begin
    if M.Groups[2].Value <> '' then
    begin
      Alias.Alias := M.Groups[2].Value.ToUpper;
      Alias.Table := M.Groups[1].Value.ToUpper;
      R.Aliases := R.Aliases + [Alias];
    end;
    if M.Groups[3].Value.ToUpper.Contains('FULL SCAN') then
    begin
      Inc(R.FullScans);
      R.ScannedTables := R.ScannedTables + [M.Groups[1].Value.ToUpper];
    end;
  end;

  // The tail is captured whole rather than as an optional group: Delphi's TRegEx drops a
  // trailing group that did not participate, and reading it back is an index out of bounds on
  // every plan line that has no parenthetical at all.
  for M in TRegEx.Matches(R.ExplainedPlan, 'Index\s+"([^"]+)"([^\r\n]*)', [roIgnoreCase]) do
  begin
    Use := Default(TPlanIndexUse);
    Use.IndexName := M.Groups[1].Value.ToUpper;
    // "full match" carries no fraction and means every segment took part; the fractions
    // ("partial match: 1/2", "lower bound: 2/2") are read for the widest one printed.
    for Frac in TRegEx.Matches(M.Groups[2].Value, '(\d+)\s*/\s*(\d+)') do
    begin
      Use.SegmentsUsed := Max(Use.SegmentsUsed, StrToIntDef(Frac.Groups[1].Value, 0));
      Use.SegmentsTotal := Max(Use.SegmentsTotal, StrToIntDef(Frac.Groups[2].Value, 0));
    end;
    Found := False;
    for I := 0 to High(R.IndexUse) do
      if R.IndexUse[I].IndexName = Use.IndexName then
      begin
        // Same index, quoted twice in one plan: keep the reading that used the most of it.
        R.IndexUse[I].SegmentsUsed := Max(R.IndexUse[I].SegmentsUsed, Use.SegmentsUsed);
        R.IndexUse[I].SegmentsTotal := Max(R.IndexUse[I].SegmentsTotal, Use.SegmentsTotal);
        Found := True;
        Break;
      end;
    if not Found then R.IndexUse := R.IndexUse + [Use];
  end;

  R.HasJoin := TRegEx.IsMatch(R.ExplainedPlan, '\bJoin\b', [roIgnoreCase]);
end;

function TFirebirdPlanAnalyzer.Analyze(const ASQL: string): TPlanResult;
var M: TMatch; LExplained: string;
begin
  Result := Default(TPlanResult);
  Result.EngineVersion := FEngineVersion;
  Result.RawPlan := GetPlanOutput(ASQL, LExplained);
  Result.ExplainedPlan := LExplained;
  Result.HasNaturalScan := Result.RawPlan.ToUpper.Contains('NATURAL');
  Result.HasExternalSort := Result.RawPlan.ToUpper.Contains('SORT');
  for M in TRegEx.Matches(Result.RawPlan, '(\w+)\s+NATURAL', [roIgnoreCase]) do
    Result.NaturalTables := Result.NaturalTables + [M.Groups[1].Value];
  if Result.ExplainedPlan <> '' then ParseExplained(Result);
end;
end.
