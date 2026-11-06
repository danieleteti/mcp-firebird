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
    [Test] procedure IsStale_Uses_The_Shared_Factor;
    [Test] procedure TableStats_Counts_Rows_Nulls_And_Distinct_In_One_Pass;
    [Test] procedure TableStats_Reports_The_Index_That_Leads_On_The_Column;
    [Test] procedure TableStats_Refuses_A_Column_That_Is_Not_In_The_Table;
    [Test] procedure TableStats_Refuses_A_Table_That_Does_Not_Exist;
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
procedure TSchemaAuditTests.IsStale_Uses_The_Shared_Factor;
begin
  Assert.IsFalse(IsStale(0.10, 0.10), 'equal');
  Assert.IsFalse(IsStale(0.14, 0.10), 'within half of actual');
  Assert.IsTrue(IsStale(0.20, 0.10), 'off by more than half of actual');
end;

procedure TSchemaAuditTests.TableStats_Counts_Rows_Nulls_And_Distinct_In_One_Pass;
var Conn: TFirebirdConnection; A: TFirebirdSchemaAudit; R: TArray<TColumnStatsRow>;
begin
  Conn := NewTestConnection;
  try A := TFirebirdSchemaAudit.Create(Conn);
    try
      R := A.TableStats('CUSTOMERS', ['CITY', 'STATUS']);
      Assert.AreEqual(2, Integer(Length(R)));
      Assert.AreEqual('CITY', R[0].Column);
      Assert.AreEqual(Int64(5000), R[0].Stats.Rows);
      Assert.AreEqual(Int64(4), R[0].Stats.Distinct, 'Rome, Milan, Turin, Naples');
      Assert.AreEqual(Int64(2), R[1].Stats.Distinct, 'A and B');
    finally A.Free; end;
  finally Conn.Free; end;
end;

procedure TSchemaAuditTests.TableStats_Reports_The_Index_That_Leads_On_The_Column;
var Conn: TFirebirdConnection; A: TFirebirdSchemaAudit; R: TArray<TColumnStatsRow>;
begin
  Conn := NewTestConnection;
  try A := TFirebirdSchemaAudit.Create(Conn);
    try
      R := A.TableStats('CUSTOMERS', ['STATUS', 'CITY']);
      Assert.AreEqual('IDX_CUST_STATUS', R[0].IndexName);
      Assert.IsTrue(R[0].Stored >= 0, 'an active index holds a figure');
      { IDX_CUST_CITY is INACTIVE in the seed, so it is no index for this purpose. }
      Assert.AreEqual('', R[1].IndexName);
      Assert.IsTrue(R[1].Stored < 0);
    finally A.Free; end;
  finally Conn.Free; end;
end;

procedure TSchemaAuditTests.TableStats_Refuses_A_Column_That_Is_Not_In_The_Table;
var Conn: TFirebirdConnection; A: TFirebirdSchemaAudit; lRaised: Boolean;
begin
  Conn := NewTestConnection;
  try A := TFirebirdSchemaAudit.Create(Conn);
    try
      lRaised := False;
      try A.TableStats('CUSTOMERS', ['CITY"; DROP TABLE CUSTOMERS; --']);
      except on Exception do lRaised := True; end;
      Assert.IsTrue(lRaised, 'the name never reaches the SQL unless the catalogue knows it');
    finally A.Free; end;
  finally Conn.Free; end;
end;

procedure TSchemaAuditTests.TableStats_Refuses_A_Table_That_Does_Not_Exist;
var Conn: TFirebirdConnection; A: TFirebirdSchemaAudit; lRaised: Boolean;
begin
  Conn := NewTestConnection;
  try A := TFirebirdSchemaAudit.Create(Conn);
    try
      lRaised := False;
      try A.TableStats('NO_SUCH_TABLE', ['X']);
      except on Exception do lRaised := True; end;
      Assert.IsTrue(lRaised);
    finally A.Free; end;
  finally Conn.Free; end;
end;

end.
