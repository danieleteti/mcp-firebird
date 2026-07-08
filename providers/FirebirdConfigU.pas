// SPDX-License-Identifier: Apache-2.0
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
  Result.AllowDDL  := dotEnv.Env('firebird.allow_ddl', False);
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
end.
