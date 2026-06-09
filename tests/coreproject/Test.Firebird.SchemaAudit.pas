unit Test.Firebird.SchemaAudit;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TSchemaAuditTests = class
  public
    [Test] procedure Flags_Table_Without_PrimaryKey;
    [Test] procedure Flags_OverIndexed_Table;
    [Test] procedure Flags_Stale_Statistics;
    [Test] procedure Detects_External_Sort_In_Plan;
  end;
implementation
uses System.SysUtils, Firebird.Connection, Firebird.Capabilities, Firebird.Advisory,
  Firebird.SchemaAudit, Firebird.PlanAnalyzer, TestFixtureU;

function Mentions(const Advs: TArray<TAdvisory>; const ANeedle: string): Boolean;
var X: TAdvisory;
begin
  Result := False;
  for X in Advs do
    if X.Finding.ToUpper.Contains(ANeedle.ToUpper) or X.SQLText.ToUpper.Contains(ANeedle.ToUpper) then Exit(True);
end;

procedure TSchemaAuditTests.Flags_Table_Without_PrimaryKey;
var Conn: TFirebirdConnection; A: TFirebirdSchemaAudit;
begin
  Conn := NewTestConnection;
  try A := TFirebirdSchemaAudit.Create(Conn);
    try Assert.IsTrue(Mentions(A.AuditTable('NOPK_LOG'), 'PRIMARY KEY')); finally A.Free; end;
  finally Conn.Free; end;
end;

procedure TSchemaAuditTests.Flags_OverIndexed_Table;
var Conn: TFirebirdConnection; A: TFirebirdSchemaAudit;
begin
  Conn := NewTestConnection;
  try A := TFirebirdSchemaAudit.Create(Conn);
    try Assert.IsTrue(Mentions(A.AuditTable('OVERIDX'), 'INDEX')); finally A.Free; end;
  finally Conn.Free; end;
end;

procedure TSchemaAuditTests.Flags_Stale_Statistics;
var Conn: TFirebirdConnection; A: TFirebirdSchemaAudit;
begin
  Conn := NewTestConnection;
  try A := TFirebirdSchemaAudit.Create(Conn);
    try Assert.IsTrue(Mentions(A.AuditTable('STALE_T'), 'STATISTICS')); finally A.Free; end;
  finally Conn.Free; end;
end;

procedure TSchemaAuditTests.Detects_External_Sort_In_Plan;
var Conn: TFirebirdConnection; PA: TFirebirdPlanAnalyzer; R: TPlanResult;
begin
  Conn := NewTestConnection;
  try
    PA := TFirebirdPlanAnalyzer.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try
      R := PA.Analyze('SELECT * FROM CUSTOMERS ORDER BY CITY');
      Assert.IsTrue(R.HasExternalSort, 'ORDER BY on non-indexed column -> external SORT. plan=' + R.RawPlan);
    finally PA.Free; end;
  finally Conn.Free; end;
end;
end.
