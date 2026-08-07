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
    [Test] procedure StaleIndexes_Names_The_Index_And_Both_Numbers;
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

procedure TSchemaAuditTests.StaleIndexes_Names_The_Index_And_Both_Numbers;
var Conn: TFirebirdConnection; A: TFirebirdSchemaAudit; S: TArray<TStaleIndexInfo>;
    Found: Boolean; X: TStaleIndexInfo;
begin
  { IDX_STALEIDX_K was analyzed while K held two distinct values and then loaded with 19 000
    more, unique ones. The optimizer still costs it at one value in two. This is the number the
    whole remedy ladder turns on, so it is read directly and not through a rendered string. }
  Conn := NewTestConnection;
  try
    A := TFirebirdSchemaAudit.Create(Conn);
    try
      S := A.StaleIndexes('STALEIDX');
      Found := False;
      for X in S do
        if SameText(X.IndexName, 'IDX_STALEIDX_K') then
        begin
          Found := True;
          Assert.IsTrue(X.Stored > X.Actual * 100,
            Format('stored %g should be far above actual %g', [X.Stored, X.Actual]));
          Assert.AreEqual('K', X.Column, 'the leading segment is what is compared');
        end;
      Assert.IsTrue(Found, 'IDX_STALEIDX_K holds statistics from before the load');

      // A table whose only index is the system primary key has nothing a user can refresh.
      Assert.IsTrue(Length(A.StaleIndexes('NOPK_LOG')) = 0, 'no user indexes, nothing stale');
    finally A.Free; end;
  finally Conn.Free; end;
end;

procedure TSchemaAuditTests.Detects_External_Sort_In_Plan;
var Conn: TFirebirdConnection; PA: TFirebirdPlanAnalyzer; R: TPlanResult;
begin
  Conn := NewTestConnection;
  try
    PA := TFirebirdPlanAnalyzer.Create(Conn, TFirebirdCapabilities.Detect(Conn).EngineVersion);
    try
      R := PA.Analyze('SELECT * FROM CUSTOMERS ORDER BY CITY');
      Assert.IsTrue(R.HasExternalSort, 'ORDER BY on non-indexed column -> external SORT. plan=' + R.RawPlan);
    finally PA.Free; end;
  finally Conn.Free; end;
end;
end.
