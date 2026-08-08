// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit FirebirdConfigU;
interface
uses System.SysUtils, Firebird.Connection;
type
  { Raised when the loaded .env is missing values needed to reach the database.
    The message names the offending key and the exact .env file, so a misrouted
    --env (the classic cause) is obvious instead of surfacing as a cryptic
    FireDAC "I/O error ... for file localhost/3050:". }
  EFirebirdConfig = class(Exception);
function LoadFirebirdConfig: TFirebirdConnectionConfig;
function NewConfiguredConnection: TFirebirdConnection;
function LoadBackupDir: string;
implementation
uses System.IOUtils, MVCFramework.DotEnv, MVCFramework.Commons, BootConfigU;

function LoadFirebirdConfig: TFirebirdConnectionConfig;
begin
  Result := Default(TFirebirdConnectionConfig);
  Result.Host      := dotEnv.Env('firebird.host', 'localhost');
  Result.Port      := dotEnv.Env('firebird.port', 3050);
  Result.Database  := dotEnv.Env('firebird.database', '');
  Result.User      := dotEnv.Env('firebird.user', 'SYSDBA');
  Result.Password  := dotEnv.Env('firebird.password', 'masterkey');
  Result.Charset   := dotEnv.Env('firebird.charset', 'UTF8');
  Result.ClientLib := dotEnv.Env('firebird.client_lib', '');
  { Not a setting. Every tool in this edition reads, and the engine is a better keeper of that
    promise than we are: the tools take SQL as text from whoever is talking to the server, and a
    string check on that text is a guess about what Firebird will do with it. With the read-only
    TPB it is Firebird that refuses. When the M3 write tools arrive they will bring their own
    opt-in and their own connection; this one stays read-only. }
  Result.ReadOnly := True;
end;

{ Fail fast with a message that points at the real problem, before FireDAC turns
  an empty/wrong path into an opaque OS I/O error. No silent defaults for values
  that must come from the .env. }
procedure ValidateFirebirdConfig(const AConfig: TFirebirdConnectionConfig);

  function EnvHint: string;
  begin
    if TFile.Exists(EnvFile) then
      Result := Format('Check "firebird.database" in %s.', [EnvFile])
    else
      Result := Format('No .env was loaded: expected "%s" but it does not exist. '
        + 'Point --env at the FOLDER that contains the .env (not at the file itself), '
        + 'or drop a .env next to the executable.', [EnvFile]);
  end;

begin
  if Trim(AConfig.Database) = '' then
    raise EFirebirdConfig.Create('Firebird database path is empty. ' + EnvHint);

  if (AConfig.ClientLib <> '') and not TFile.Exists(AConfig.ClientLib) then
    raise EFirebirdConfig.CreateFmt(
      'Firebird client library not found: "%s" (firebird.client_lib in %s).',
      [AConfig.ClientLib, EnvFile]);
end;

function NewConfiguredConnection: TFirebirdConnection;
var
  lConfig: TFirebirdConnectionConfig;
begin
  lConfig := LoadFirebirdConfig;
  ValidateFirebirdConfig(lConfig);
  Result := TFirebirdConnection.Create(lConfig);
  Result.Connect;
end;

{ The backup destination is declared once, in the .env, and never comes from the
  caller: the tools take instructions from whatever is talking to the server, and
  a path taken from there is a path this process would write to on its word. }
function LoadBackupDir: string;
begin
  Result := Trim(dotEnv.Env('firebird.backup_dir', ''));
  if Result = '' then
    raise EFirebirdConfig.CreateFmt(
      'No backup destination is configured. Set "firebird.backup_dir" in %s to a folder ' +
      'this server may write backups into.', [EnvFile]);
  if not TDirectory.Exists(Result) then
    raise EFirebirdConfig.CreateFmt(
      'Backup destination "%s" does not exist or is not a folder (firebird.backup_dir in %s).',
      [Result, EnvFile]);
  Result := IncludeTrailingPathDelimiter(Result);
end;

end.
