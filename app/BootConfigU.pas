unit BootConfigU;
interface
procedure Boot;
implementation
uses
  System.SysUtils, System.IOUtils,
  LoggerPro.Config, LoggerPro,
  MVCFramework.DotEnv, MVCFramework.Commons, MVCFramework.Logger;

{ Directory passed via "--env <dir>" / "--env=<dir>" that holds the .env file.
  Returns '' when the argument is not provided. }
function GetEnvDirArg: string;
var
  I: Integer;
  P: string;
begin
  Result := '';
  for I := 1 to ParamCount do
  begin
    P := ParamStr(I);
    if SameText(P, '--env') and (I < ParamCount) then
      Exit(ParamStr(I + 1));
    if P.StartsWith('--env=', True) then
      Exit(P.Substring(Length('--env=')));
  end;
end;

procedure ConfigLogger;
var
  lConfigFile: string;
begin
  lConfigFile := dotEnv.Env('logger.config.file', 'loggerpro.stdio.json');
  if not TPath.IsPathRooted(lConfigFile) then
    lConfigFile := TPath.Combine(AppPath, lConfigFile);
  SetDefaultLogger(TLoggerProConfig.BuilderFromJSONFile(lConfigFile).Build);
end;

procedure Boot;
var
  lArg, lEnvDir: string;
begin
  // --env <dir> selects the folder that contains the .env file (relative paths
  // resolve against the current working directory). Without the argument the
  // .env is read from the executable's own folder.
  lArg := GetEnvDirArg;
  if lArg <> '' then
    lEnvDir := ExpandFileName(lArg)
  else
    lEnvDir := ExcludeTrailingPathDelimiter(AppPath);

  dotEnvConfigure(
    function: IMVCDotEnv
    begin
      Result := NewDotEnv.UseStrategy(TMVCDotEnvPriority.FileThenEnv).Build(lEnvDir);
    end);

  ConfigLogger;

  LogI('Boot: .env directory "' + lEnvDir + '" (.env exists=' +
    BoolToStr(TFile.Exists(TPath.Combine(lEnvDir, '.env')), True) + ')', 'mcp');
end;
end.
