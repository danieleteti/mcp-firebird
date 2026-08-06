unit Test.Firebird.Connection;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TConnectionTests = class
  public
    [Test] procedure Connects_To_Seed_DB;
    [Test] procedure ScalarStr_Returns_Engine_Version;
    [Test] procedure ReadOnly_Connection_Is_Refused_By_The_Engine_Not_By_Us;
    [Test] procedure ReadOnly_Connection_Still_Reads;
  end;
implementation
uses System.SysUtils, FireDAC.Comp.Client, Firebird.Connection, TestFixtureU;

function NewReadOnlyConnection: TFirebirdConnection;
var Cfg: TFirebirdConnectionConfig;
begin
  Cfg := TestConfig;
  Cfg.ReadOnly := True;   // what FirebirdConfigU hands every tool
  Result := TFirebirdConnection.Create(Cfg);
  Result.Connect;
end;

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

procedure TConnectionTests.ReadOnly_Connection_Is_Refused_By_The_Engine_Not_By_Us;
var C, Checker: TFirebirdConnection; Q: TFDQuery; Rows: Int64;
begin
  { The tools inspect the SQL they are given before running it, but that check is a guess about
    what Firebird will do with the text. This is the guarantee underneath it: on the connection
    the server actually uses, a write is refused by the engine, whatever got past us. }
  C := NewReadOnlyConnection;
  try
    Assert.WillRaise(
      procedure begin C.ExecSQL('DELETE FROM CUSTOMERS') end,
      nil, 'a read-only transaction must refuse a DELETE');
    Assert.WillRaise(
      procedure begin C.ExecSQL('CREATE TABLE SHOULD_NOT_EXIST (ID INTEGER)') end,
      nil, 'a read-only transaction must refuse DDL');   // FireDAC wraps it in EIBNativeException
  finally C.Free; end;

  Checker := NewTestConnection;
  try
    Q := Checker.OpenQuery('SELECT COUNT(*) FROM CUSTOMERS');
    try Rows := Q.Fields[0].AsLargeInt; finally Q.Free; end;
    Assert.AreEqual(Int64(5000), Rows, 'the refused DELETE must have changed nothing');
  finally Checker.Free; end;
end;

procedure TConnectionTests.ReadOnly_Connection_Still_Reads;
var C: TFirebirdConnection; Q: TFDQuery;
begin
  // Including MON$, which is where most of this server's evidence comes from.
  C := NewReadOnlyConnection;
  try
    Q := C.OpenQuery('SELECT MON$NEXT_TRANSACTION FROM MON$DATABASE');
    try
      Assert.IsFalse(Q.Eof, 'a read-only transaction must still read MON$');
      Assert.IsTrue(Q.Fields[0].AsLargeInt > 0);
    finally Q.Free; end;
    C.NewMonitoringSnapshot;   // the commit path the sampler relies on
    Assert.AreEqual('5000', C.ScalarStr('SELECT COUNT(*) FROM CUSTOMERS'));
  finally C.Free; end;
end;
end.
