unit Test.Firebird.PlanAnalyzer;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TPlanAnalyzerTests = class
  public
    [Test] procedure NaturalScan_On_City_Filter_IsDetected;
    [Test] procedure Pk_Lookup_HasNoNaturalScan;
  end;
implementation
uses System.SysUtils, Firebird.Connection, Firebird.Capabilities, Firebird.PlanAnalyzer, TestFixtureU;

procedure TPlanAnalyzerTests.NaturalScan_On_City_Filter_IsDetected;
var Conn: TFirebirdConnection; PA: TFirebirdPlanAnalyzer; R: TPlanResult;
begin
  Conn := NewTestConnection;
  try
    PA := TFirebirdPlanAnalyzer.Create(Conn, TFirebirdCapabilities.Detect(Conn));
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
    PA := TFirebirdPlanAnalyzer.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try
      R := PA.Analyze('SELECT * FROM CUSTOMERS WHERE CUSTOMER_ID = 1');
      Assert.IsFalse(R.HasNaturalScan, 'PK lookup uses the primary index. Got plan: ' + R.RawPlan);
    finally PA.Free; end;
  finally Conn.Free; end;
end;
end.
