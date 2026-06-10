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
  // Anchor all relative paths (notably the logger's "logs" folder) to the
  // executable / .env directory, NOT the launcher's working directory. An MCP
  // client (Claude Desktop, etc.) starts the server with an arbitrary CWD, so
  // without this the log files would land somewhere invisible to the user.
  SetCurrentDir(AppPath);
  ConfigDotEnv;
  ConfigLogger;
end;
end.
