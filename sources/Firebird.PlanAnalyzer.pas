unit Firebird.PlanAnalyzer;
// Plan retrieval per Task 10 spike (docs/plan-retrieval-decision.md): isql + SET PLANONLY ON.
interface
uses Firebird.Connection, Firebird.Capabilities;
type
  TPlanResult = record
    RawPlan, ExplainedPlan, EngineVersion: string;
    HasNaturalScan, HasExternalSort: Boolean;
    NaturalTables: TArray<string>;
  end;
  TFirebirdPlanAnalyzer = class
  private
    FConn: TFirebirdConnection;
    FCaps: TFirebirdCapabilities;
    function GetRawPlan(const ASQL: string): string;
  public
    constructor Create(AConn: TFirebirdConnection; const ACaps: TFirebirdCapabilities);
    function Analyze(const ASQL: string): TPlanResult;
  end;
implementation
uses
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils,
  System.RegularExpressions;

constructor TFirebirdPlanAnalyzer.Create(AConn: TFirebirdConnection; const ACaps: TFirebirdCapabilities);
begin inherited Create; FConn := AConn; FCaps := ACaps; end;

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

function TFirebirdPlanAnalyzer.GetRawPlan(const ASQL: string): string;
var
  LIsql, LDir, LIn, LOut, LConn, LCmd, LScript, LOutput, Line: string;
  SL: TStringList; PlanLines: TStringBuilder;
begin
  LDir := ExtractFilePath(FConn.Config.ClientLib);
  if LDir <> '' then LIsql := IncludeTrailingPathDelimiter(LDir) + 'isql.exe' else LIsql := 'isql.exe';
  if not FileExists(LIsql) then LIsql := 'isql.exe';
  LIn  := TPath.GetTempFileName;
  LOut := TPath.GetTempFileName;
  try
    LScript := 'SET PLANONLY ON;' + sLineBreak + ASQL.Trim;
    if not LScript.TrimRight.EndsWith(';') then LScript := LScript + ';';
    LScript := LScript + sLineBreak;
    TFile.WriteAllBytes(LIn, TEncoding.UTF8.GetBytes(LScript)); // no BOM
    LConn := Format('%s/%d:%s', [FConn.Config.Host, FConn.Config.Port, FConn.Config.Database]);
    // -m merges stderr into stdout; -m2 redirects diagnostics (where the PLAN
    // line is emitted under SET PLANONLY ON) into the -o output file.
    LCmd := Format('"%s" -q -m -m2 -ch UTF8 -i "%s" -o "%s" -user %s -password %s "%s"',
      [LIsql, LIn, LOut, FConn.Config.User, FConn.Config.Password, LConn]);
    RunAndWait(LCmd);
    LOutput := TFile.ReadAllText(LOut);
    PlanLines := TStringBuilder.Create;
    SL := TStringList.Create;
    try
      SL.Text := LOutput;
      for Line in SL do
        if Line.TrimLeft.StartsWith('PLAN', True) then
          PlanLines.AppendLine(Line.Trim);
      Result := PlanLines.ToString.Trim;
    finally SL.Free; PlanLines.Free; end;
  finally
    if FileExists(LIn) then System.SysUtils.DeleteFile(LIn);
    if FileExists(LOut) then System.SysUtils.DeleteFile(LOut);
  end;
end;

function TFirebirdPlanAnalyzer.Analyze(const ASQL: string): TPlanResult;
var M: TMatch;
begin
  Result := Default(TPlanResult);
  Result.EngineVersion := FCaps.EngineVersion;
  Result.RawPlan := GetRawPlan(ASQL);
  Result.HasNaturalScan := Result.RawPlan.ToUpper.Contains('NATURAL');
  Result.HasExternalSort := Result.RawPlan.ToUpper.Contains('SORT');
  for M in TRegEx.Matches(Result.RawPlan, '(\w+)\s+NATURAL', [roIgnoreCase]) do
    Result.NaturalTables := Result.NaturalTables + [M.Groups[1].Value];
end;
end.
