// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit Firebird.PlanAnalyzer;
// Plan retrieval per Task 10 spike (docs/plan-retrieval-decision.md): isql + SET PLANONLY ON.
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
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils, System.Math,
  System.RegularExpressions, Firebird.Capabilities;

constructor TFirebirdPlanAnalyzer.Create(AConn: TFirebirdConnection; const AEngineVersion: string);
begin
  inherited Create;
  FConn := AConn;
  FEngineVersion := AEngineVersion;
  // SET EXPLAIN does not exist in 2.5's isql, and an unknown SET aborts the script that carries
  // it — including the statement whose plan we came for. Below 3.0 the script stays what it was.
  FWantExplained := TFirebirdCapabilities.Parse(AEngineVersion).HasExplainedPlan;
end;

procedure RunAndWait(const ACmd: string);
var SI: TStartupInfo; PI: TProcessInformation; LCmd: string;
begin
  FillChar(SI, SizeOf(SI), 0); SI.cb := SizeOf(SI);
  SI.dwFlags := STARTF_USESHOWWINDOW; SI.wShowWindow := SW_HIDE;
  LCmd := ACmd; UniqueString(LCmd);
  if not CreateProcess(nil, PChar(LCmd), nil, nil, False, CREATE_NO_WINDOW, nil, nil, SI, PI) then
    RaiseLastOSError;
  try
    if WaitForSingleObject(PI.hProcess, 30000) = WAIT_TIMEOUT then
    begin
      TerminateProcess(PI.hProcess, 1);
      raise Exception.Create('isql plan retrieval timed out after 30 seconds');
    end;
  finally
    CloseHandle(PI.hThread); CloseHandle(PI.hProcess);
  end;
end;

function TFirebirdPlanAnalyzer.GetPlanOutput(const ASQL: string; out AExplained: string): string;
var
  LIsql, LDir, LIn, LOut, LConn, LCmd, LScript, LOutput, LStmt, Line: string;
  SL: TStringList; PlanLines, TreeLines: TStringBuilder; InTree: Boolean;
begin
  AExplained := '';
  LDir := ExtractFilePath(FConn.Config.ClientLib);
  if LDir <> '' then LIsql := IncludeTrailingPathDelimiter(LDir) + 'isql.exe' else LIsql := 'isql.exe';
  if not FileExists(LIsql) then LIsql := 'isql.exe';
  LIn  := TPath.GetTempFileName;
  LOut := TPath.GetTempFileName;
  try
    LStmt := ASQL.Trim;
    if not LStmt.TrimRight.EndsWith(';') then LStmt := LStmt + ';';
    { Both plans, one isql, two prepares and no execution. SET EXPLAIN ON replaces the legacy
      PLAN line rather than adding to it, so the statement is prepared once before it is turned
      on and once after: the terse line the whole codebase already reads, and the tree that
      carries the index names, the match quality and the aliases. }
    LScript := 'SET PLANONLY ON;' + sLineBreak + LStmt + sLineBreak;
    if FWantExplained then
      LScript := LScript + 'SET EXPLAIN ON;' + sLineBreak + LStmt + sLineBreak;
    TFile.WriteAllBytes(LIn, TEncoding.UTF8.GetBytes(LScript)); // no BOM
    LConn := Format('%s/%d:%s', [FConn.Config.Host, FConn.Config.Port, FConn.Config.Database]);
    // -m merges stderr into stdout; -m2 redirects diagnostics (where the PLAN
    // line is emitted under SET PLANONLY ON) into the -o output file.
    LCmd := Format('"%s" -q -m -m2 -ch UTF8 -i "%s" -o "%s" -user %s -password %s "%s"',
      [LIsql, LIn, LOut, FConn.Config.User, FConn.Config.Password, LConn]);
    RunAndWait(LCmd);
    LOutput := TFile.ReadAllText(LOut);
    PlanLines := TStringBuilder.Create;
    TreeLines := TStringBuilder.Create;
    SL := TStringList.Create;
    try
      SL.Text := LOutput;
      InTree := False;
      for Line in SL do
        if Line.TrimLeft.StartsWith('PLAN', True) then
          PlanLines.AppendLine(Line.Trim)
        else if Line.TrimLeft.StartsWith('Select Expression', True) then
        begin
          InTree := True;
          TreeLines.AppendLine(Line.TrimRight);
        end
        else if InTree and (Line.Trim <> '') then
          TreeLines.AppendLine(Line.TrimRight);
      Result := PlanLines.ToString.Trim;
      AExplained := TreeLines.ToString.Trim;
      // isql prints "Statement failed, SQLSTATE = ..." into this same output when the engine
      // refuses the statement. Harvesting only the PLAN lines would leave an empty plan, which
      // every caller reads as "no NATURAL scan" — an all-clear on a query that never ran.
      if Result = '' then
        raise Exception.Create('Firebird produced no plan for this statement:' + sLineBreak +
          LOutput.Trim);
    finally SL.Free; TreeLines.Free; PlanLines.Free; end;
  finally
    if FileExists(LIn) then System.SysUtils.DeleteFile(LIn);
    if FileExists(LOut) then System.SysUtils.DeleteFile(LOut);
  end;
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
