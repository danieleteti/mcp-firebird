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
    [Test] procedure A_Read_Only_Select_Can_Still_Move_A_Generator;
    [Test] procedure IsReadOnlySelect_Refuses_What_Moves_A_Generator_And_Nothing_Else;
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

procedure TConnectionTests.A_Read_Only_Select_Can_Still_Move_A_Generator;
var C, Admin: TFirebirdConnection; Before, After: string;
begin
  { The reason IsReadOnlySelect looks inside the statement: a generator is not transactional, so
    the read-only TPB that stops every write leaves this one open. If a future engine closes it,
    this test fails and the extra check can go. }
  Admin := NewTestConnection;   // a test connection is not read-only: it may create the generator
  try
    Admin.ExecSQL('CREATE GENERATOR G_MCPFB_READONLY_PROBE');
    try
      C := NewReadOnlyConnection;
      try
        Before := C.ScalarStr('SELECT GEN_ID(G_MCPFB_READONLY_PROBE, 0) FROM RDB$DATABASE');
        C.ScalarStr('SELECT GEN_ID(G_MCPFB_READONLY_PROBE, 7) FROM RDB$DATABASE');
        After := C.ScalarStr('SELECT GEN_ID(G_MCPFB_READONLY_PROBE, 0) FROM RDB$DATABASE');
        Assert.AreEqual('0', Before);
        Assert.AreEqual('7', After, 'the engine let a read-only SELECT advance a generator');
      finally C.Free; end;
    finally
      Admin.ExecSQL('DROP GENERATOR G_MCPFB_READONLY_PROBE');
    end;
  finally Admin.Free; end;
end;

procedure TConnectionTests.IsReadOnlySelect_Refuses_What_Moves_A_Generator_And_Nothing_Else;
begin
  Assert.IsFalse(IsReadOnlySelect('SELECT GEN_ID(G, 1) FROM RDB$DATABASE'));
  Assert.IsFalse(IsReadOnlySelect('select gen_id (g, 1) from rdb$database'));
  Assert.IsFalse(IsReadOnlySelect('SELECT NEXT VALUE FOR G FROM RDB$DATABASE'));
  Assert.IsFalse(IsReadOnlySelect('WITH X AS (SELECT GEN_ID(G, 1) AS V FROM RDB$DATABASE) SELECT V FROM X'));
  // Text that only mentions the words, or a column that merely contains them, is not a call.
  Assert.IsTrue(IsReadOnlySelect('SELECT * FROM T WHERE NOTE = ''GEN_ID(G, 1)'''));
  Assert.IsTrue(IsReadOnlySelect('SELECT "GEN_ID(", NAME FROM T'));
  Assert.IsTrue(IsReadOnlySelect('SELECT MY_GEN_IDENTITY FROM T'));
  Assert.IsTrue(IsReadOnlySelect('SELECT GEN_ID_COUNT FROM T'));
  Assert.IsTrue(IsReadOnlySelect('WITH X AS (SELECT 1 AS V FROM RDB$DATABASE) SELECT V FROM X'));
  // Still not a SELECT.
  Assert.IsFalse(IsReadOnlySelect('DELETE FROM T'));
  Assert.IsFalse(IsReadOnlySelect('EXECUTE BLOCK AS BEGIN END'));
  Assert.IsFalse(IsReadOnlySelect('-- hi' + sLineBreak + 'SELECT 1 FROM RDB$DATABASE'));
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
