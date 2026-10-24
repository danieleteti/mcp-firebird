unit Test.Firebird.PlanAnalyzer;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TPlanAnalyzerTests = class
  public
    [Test] procedure NaturalScan_On_City_Filter_IsDetected;
    [Test] procedure Pk_Lookup_HasNoNaturalScan;
    [Test] procedure ExplainedPlan_Names_The_Table_The_Alias_And_The_Index;
    [Test] procedure Inner_Semicolon_Is_Refused;
  end;
implementation
uses System.SysUtils, Firebird.Connection, Firebird.Capabilities, Firebird.PlanAnalyzer, TestFixtureU;

procedure TPlanAnalyzerTests.NaturalScan_On_City_Filter_IsDetected;
var Conn: TFirebirdConnection; PA: TFirebirdPlanAnalyzer; R: TPlanResult;
begin
  Conn := NewTestConnection;
  try
    PA := TFirebirdPlanAnalyzer.Create(Conn, TFirebirdCapabilities.Detect(Conn).EngineVersion);
    try
      R := PA.Analyze('SELECT * FROM CUSTOMERS WHERE CITY = ''Rome''');
      Assert.IsTrue(R.HasNaturalScan, 'filtering CITY (no active index) -> NATURAL. Got plan: ' + R.RawPlan);
      Assert.IsTrue(R.RawPlan.ToUpper.Contains('NATURAL'));
    finally PA.Free; end;
  finally Conn.Free; end;
end;

procedure TPlanAnalyzerTests.Pk_Lookup_HasNoNaturalScan;
var Conn: TFirebirdConnection; PA: TFirebirdPlanAnalyzer; R: TPlanResult;
begin
  Conn := NewTestConnection;
  try
    PA := TFirebirdPlanAnalyzer.Create(Conn, TFirebirdCapabilities.Detect(Conn).EngineVersion);
    try
      R := PA.Analyze('SELECT * FROM CUSTOMERS WHERE CUSTOMER_ID = 1');
      Assert.IsFalse(R.HasNaturalScan, 'PK lookup uses the primary index. Got plan: ' + R.RawPlan);
    finally PA.Free; end;
  finally Conn.Free; end;
end;

procedure TPlanAnalyzerTests.ExplainedPlan_Names_The_Table_The_Alias_And_The_Index;
var Conn: TFirebirdConnection; PA: TFirebirdPlanAnalyzer; R: TPlanResult;
    Caps: TFirebirdCapabilities; A: TPlanAlias; Found: Boolean;
begin
  { The legacy PLAN line prints the alias and no index detail; the explained tree prints the
    real table name, the pairing, the index and how much of it the query agreed with. It exists
    from 3.0, and SET EXPLAIN ON does not exist in 2.5's isql at all — where an unknown SET
    would abort the script carrying the statement we came for. }
  Conn := NewTestConnection;
  try
    Caps := TFirebirdCapabilities.Detect(Conn);
    PA := TFirebirdPlanAnalyzer.Create(Conn, Caps.EngineVersion);
    try
      R := PA.Analyze('SELECT C.NAME, O.TOTAL FROM CUSTOMERS C JOIN ORDERS O ' +
                      'ON O.CUSTOMER_ID = C.CUSTOMER_ID WHERE C.STATUS = ''A''');
      if not Caps.HasExplainedPlan then
      begin
        Assert.AreEqual('', R.ExplainedPlan, '2.5 is never asked for an explained plan');
        Assert.IsTrue(R.RawPlan <> '', 'and still returns the legacy plan it always did');
        Exit;
      end;
      Assert.IsTrue(R.ExplainedPlan <> '', 'the tree is captured. RawPlan=' + R.RawPlan);
      Found := False;
      for A in R.Aliases do
        if (A.Alias = 'O') and (A.Table = 'ORDERS') then Found := True;
      Assert.IsTrue(Found, 'the engine states which table an alias is: ' + R.ExplainedPlan);
      Assert.IsTrue(R.FullScans >= 1, 'ORDERS is scanned: ' + R.ExplainedPlan);
      Assert.IsTrue(R.HasJoin, 'and the tree says it is a join: ' + R.ExplainedPlan);
    finally PA.Free; end;
  finally Conn.Free; end;
end;
procedure TPlanAnalyzerTests.Inner_Semicolon_Is_Refused;
var Conn: TFirebirdConnection; PA: TFirebirdPlanAnalyzer;
begin
  Conn := NewTestConnection;
  try
    PA := TFirebirdPlanAnalyzer.Create(Conn, TFirebirdCapabilities.Detect(Conn).EngineVersion);
    try
      Assert.WillRaise(procedure begin PA.Analyze('SELECT 1 FROM RDB$DATABASE; SELECT 2 FROM RDB$DATABASE'); end);
      // a trailing ";" and a ";" inside a literal are both fine
      PA.Analyze('SELECT * FROM CUSTOMERS WHERE CITY = ''a;b'';');
    finally PA.Free; end;
  finally Conn.Free; end;
end;

end.
