unit TestFixtureU;
interface
uses Firebird.Connection;
function TestConfig: TFirebirdConnectionConfig;
function NewTestConnection: TFirebirdConnection;
implementation
uses System.SysUtils;

function TestConfig: TFirebirdConnectionConfig;
begin
  Result := Default(TFirebirdConnectionConfig);
  Result.Host      := 'localhost';
  Result.Port      := StrToIntDef(GetEnvironmentVariable('FBTEST_PORT'), 3055);
  Result.Database  := GetEnvironmentVariable('FBTEST_DB');
  Result.User      := 'SYSDBA';
  Result.Password  := 'masterkey';
  Result.Charset   := 'UTF8';
  Result.ClientLib := GetEnvironmentVariable('FBTEST_CLIENTLIB');
  Result.AllowDDL  := True;
end;

function NewTestConnection: TFirebirdConnection;
begin
  Result := TFirebirdConnection.Create(TestConfig);
  Result.Connect;
end;
end.
