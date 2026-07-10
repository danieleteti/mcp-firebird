unit Test.Firebird.Goal;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TGoalTests = class
  public
    [Test] procedure NoNaturalScan_NotMet_When_Index_Missing_Then_Met_After_Create;
    [Test] procedure NoRedundantIndexes_NotMet_On_Seed;
  end;
implementation
uses System.SysUtils, Firebird.Connection, Firebird.Capabilities, Firebird.Goal, TestFixtureU;

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
