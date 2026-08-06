unit Test.Firebird.Goal;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TGoalTests = class
  public
    [Test] procedure NoNaturalScan_NotMet_When_Index_Missing_Then_Met_After_Create;
    [Test] procedure NoRedundantIndexes_NotMet_On_Seed;
    [Test] procedure QueryTimeMs_Refuses_To_Time_A_Statement_That_Could_Write;
  end;
implementation
uses System.SysUtils, FireDAC.Comp.Client,
  Firebird.Connection, Firebird.Capabilities, Firebird.Goal, TestFixtureU;

procedure TGoalTests.QueryTimeMs_Refuses_To_Time_A_Statement_That_Could_Write;
var Conn: TFirebirdConnection; G: TFirebirdGoal; Q: TFDQuery; Rows: Int64;
begin
  { Timing a statement means running it, and the target arrives as text from whoever is talking
    to the server. This goal used to run whatever it was handed. }
  Conn := NewTestConnection;
  try
    G := TFirebirdGoal.Create(Conn, TFirebirdCapabilities.Detect(Conn).EngineVersion);
    try
      Assert.WillRaise(
        procedure begin G.Evaluate('query_time_ms', 'DELETE FROM CUSTOMERS', 1000) end,
        Exception, 'a DELETE must be refused, not timed');
    finally G.Free; end;
    Q := Conn.OpenQuery('SELECT COUNT(*) FROM CUSTOMERS');
    try Rows := Q.Fields[0].AsLargeInt; finally Q.Free; end;
    Assert.AreEqual(Int64(5000), Rows, 'the refused statement must have changed nothing');
  finally Conn.Free; end;
end;

procedure TGoalTests.NoNaturalScan_NotMet_When_Index_Missing_Then_Met_After_Create;
var Conn: TFirebirdConnection; G: TFirebirdGoal; R: TGoalResult;
begin
  Conn := NewTestConnection;
  try
    G := TFirebirdGoal.Create(Conn, TFirebirdCapabilities.Detect(Conn).EngineVersion);
    try
      R := G.Evaluate('query_no_natural_scan', 'SELECT * FROM CUSTOMERS WHERE CITY = ''Rome''', 0);
      Assert.IsFalse(R.Met, 'baseline: NATURAL scan present. plan=' + R.Hint);
      Conn.ExecSQL('CREATE INDEX IDX_GOAL_CITY ON CUSTOMERS (CITY)');
      try
        R := G.Evaluate('query_no_natural_scan', 'SELECT * FROM CUSTOMERS WHERE CITY = ''Rome''', 0);
        Assert.IsTrue(R.Met, 'after index: no NATURAL scan. plan=' + R.Hint);
      finally
        Conn.ExecSQL('DROP INDEX IDX_GOAL_CITY');
      end;
    finally G.Free; end;
  finally Conn.Free; end;
end;

procedure TGoalTests.NoRedundantIndexes_NotMet_On_Seed;
var Conn: TFirebirdConnection; G: TFirebirdGoal; R: TGoalResult;
begin
  Conn := NewTestConnection;
  try
    G := TFirebirdGoal.Create(Conn, TFirebirdCapabilities.Detect(Conn).EngineVersion);
    try
      R := G.Evaluate('no_redundant_indexes', 'ORDERS', 0);
      Assert.IsFalse(R.Met, 'ORDERS has the duplicate FK index');
    finally G.Free; end;
  finally Conn.Free; end;
end;
end.
