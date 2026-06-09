unit Test.Firebird.Capabilities;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TCapabilitiesTests = class
  public
    [Test] procedure Parse_25_HasNoExplainedPlan;
    [Test] procedure Parse_30_HasExplainedPlanAndBoolean;
    [Test] procedure Parse_50_HasParallelWorkers;
    [Test] procedure Detect_FromSeedDB_MatchesParse;
  end;
implementation
uses System.SysUtils, Firebird.Capabilities, Firebird.Connection, TestFixtureU;

procedure TCapabilitiesTests.Parse_25_HasNoExplainedPlan;
var C: TFirebirdCapabilities;
begin
  C := TFirebirdCapabilities.Parse('2.5.9');
  Assert.AreEqual(2, C.Major); Assert.AreEqual(5, C.Minor);
  Assert.IsFalse(C.HasExplainedPlan); Assert.IsFalse(C.HasBooleanType);
  Assert.IsTrue(C.HasMonTables);
end;

procedure TCapabilitiesTests.Parse_30_HasExplainedPlanAndBoolean;
var C: TFirebirdCapabilities;
begin
  C := TFirebirdCapabilities.Parse('3.0.14');
  Assert.IsTrue(C.HasExplainedPlan); Assert.IsTrue(C.HasBooleanType);
  Assert.IsFalse(C.HasInt128); Assert.IsFalse(C.HasParallelWorkers);
end;

procedure TCapabilitiesTests.Parse_50_HasParallelWorkers;
var C: TFirebirdCapabilities;
begin
  C := TFirebirdCapabilities.Parse('5.0.4');
  Assert.IsTrue(C.HasParallelWorkers); Assert.IsTrue(C.HasInt128); Assert.IsTrue(C.HasTimezones);
end;

procedure TCapabilitiesTests.Detect_FromSeedDB_MatchesParse;
var Conn: TFirebirdConnection; C: TFirebirdCapabilities;
begin
  Conn := NewTestConnection;
  try
    C := TFirebirdCapabilities.Detect(Conn);
    Assert.IsTrue(C.Major >= 2, 'major detected');
    Assert.IsMatch('^\d+\.\d+', C.EngineVersion);
  finally Conn.Free; end;
end;
end.
