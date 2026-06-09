unit BootConfigU;
interface
procedure Boot;
implementation
uses
  System.SysUtils, System.IOUtils, LoggerPro.Config, LoggerPro,
  MVCFramework.DotEnv, MVCFramework.Commons, MVCFramework.Logger;

procedure ConfigDotEnv;
begin
  dotEnvConfigure(
    function: IMVCDotEnv
    begin
      Result := NewDotEnv.UseStrategy(TMVCDotEnvPriority.FileThenEnv).Build(AppPath);
    end);
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
begin
  ConfigDotEnv;
  ConfigLogger;
end;
end.
