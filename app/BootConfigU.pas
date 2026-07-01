unit BootConfigU;
interface
uses System.SysUtils;
type
  { Raised by Boot when the startup arguments are wrong (e.g. --env points at a
    .env file instead of the folder that contains it). The message explains the
    fix so the mistake is obvious instead of degrading into an empty config. }
  EBootConfig = class(Exception);
procedure Boot;
{ Folder the .env was actually loaded from (resolved from --env or the exe folder).
  Empty until Boot has run. Used to build speaking config-error messages. }
function EnvDir: string;
{ Full path of the .env file Boot looked for (whether or not it exists). }
function EnvFile: string;
implementation
uses
  System.IOUtils,
  LoggerPro.Config, LoggerPro,
  MVCFramework.DotEnv, MVCFramework.Commons, MVCFramework.Logger;

var
  GEnvDir: string = '';

function EnvDir: string;
begin
  Result := GEnvDir;
end;

function EnvFile: string;
begin
  Result := TPath.Combine(GEnvDir, '.env');
end;

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

{ Resolve the --env argument to the folder that holds the .env file. --env must
  name the FOLDER, not the .env file: if it points at a file (or a path whose leaf
  is ".env") we stop with a speaking error instead of silently guessing, since a
  wrong path here otherwise surfaces later as a cryptic empty-config failure. }
function ResolveEnvDir(const AArg: string): string;
var
  lPath, lLeaf: string;
begin
  lPath := ExcludeTrailingPathDelimiter(ExpandFileName(AArg));
  lLeaf := ExtractFileName(lPath);

  if TFile.Exists(lPath) or SameText(lLeaf, '.env') then
    raise EBootConfig.CreateFmt(
      '--env must point at the FOLDER that contains the .env file, not at the file itself.'
      + sLineBreak + '  got:      %s'
      + sLineBreak + '  use this: %s',
      [AArg, ExtractFileDir(lPath)]);

  Result := lPath;
end;

procedure Boot;
var
  lArg, lEnvDir: string;
begin
  // --env <dir> selects the folder that contains the .env file (relative paths
  // resolve against the current working directory). Pointing --env directly at a
  // .env file also works. Without the argument the .env is read from the
  // executable's own folder.
  lArg := GetEnvDirArg;
  if lArg <> '' then
    lEnvDir := ResolveEnvDir(lArg)
  else
    lEnvDir := ExcludeTrailingPathDelimiter(AppPath);
  GEnvDir := lEnvDir;

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
