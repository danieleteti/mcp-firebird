unit Test.Firebird.Connection;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TConnectionTests = class
  public
    [Test] procedure Connects_To_Seed_DB;
    [Test] procedure ScalarStr_Returns_Engine_Version;
  end;
implementation
uses System.SysUtils, Firebird.Connection, TestFixtureU;

procedure TConnectionTests.Connects_To_Seed_DB;
var C: TFirebirdConnection;
begin
  C := NewTestConnection;
  try
    Assert.IsTrue(C.FDConnection.Connected, 'should be connected');
  finally C.Free; end;
end;

procedure TConnectionTests.ScalarStr_Returns_Engine_Version;
var C: TFirebirdConnection; V: string;
begin
  C := NewTestConnection;
  try
    V := C.ScalarStr('SELECT rdb$get_context(''SYSTEM'',''ENGINE_VERSION'') FROM rdb$database');
    Assert.IsMatch('^\d+\.\d+\.\d+', V, 'engine version like 5.0.4');
  finally C.Free; end;
end;
end.
