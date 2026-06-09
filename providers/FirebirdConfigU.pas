unit FirebirdConfigU;
interface
uses Firebird.Connection;
function LoadFirebirdConfig: TFirebirdConnectionConfig;
function NewConfiguredConnection: TFirebirdConnection;
implementation
uses System.SysUtils, MVCFramework.DotEnv, MVCFramework.Commons;

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

function NewConfiguredConnection: TFirebirdConnection;
begin
  Result := TFirebirdConnection.Create(LoadFirebirdConfig);
  Result.Connect;
end;
end.
