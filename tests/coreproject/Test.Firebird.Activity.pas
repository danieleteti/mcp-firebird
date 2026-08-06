unit Test.Firebird.Activity;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TActivityTests = class
  public
    [Test] procedure Sample_Sees_Work_That_Happens_Inside_The_Window;
    [Test] procedure Sample_On_A_Quiet_Database_Reports_Nothing_And_Does_Not_Crash;
    [Test] procedure Measure_Reports_The_Records_The_Query_Actually_Read;
    [Test] procedure Measure_Refuses_To_Execute_Anything_But_A_Select;
    [Test] procedure IsReadOnlySelect_Accepts_Select_And_With_Only;
  end;
implementation
uses System.SysUtils, System.Classes, FireDAC.Comp.Client,
  Firebird.Connection, Firebird.Capabilities, Firebird.Advisory, Firebird.Activity, TestFixtureU;

procedure TActivityTests.Sample_Sees_Work_That_Happens_Inside_The_Window;
var Conn: TFirebirdConnection; A: TFirebirdActivity; S: TActivitySample;
    Worker: TThread; Stop: Boolean;
begin
  { The bug this guards is invisible and total: MON$ is a snapshot frozen by the reading
    transaction, so a sampler that reads twice inside one transaction gets the same numbers
    twice and reports a perfectly calm database under any load whatsoever. A window that sees
    a scan running through it is the only proof the second read was a second read. }
  Stop := False;
  Worker := TThread.CreateAnonymousThread(
    procedure
    var W: TFirebirdConnection; Q: TFDQuery;
    begin
      W := TFirebirdConnection.Create(TestConfig);
      try
        W.Connect;
        while not Stop do
        begin
          Q := W.OpenQuery('SELECT COUNT(*) FROM CUSTOMERS');
          Q.Free;
        end;
      finally W.Free; end;
    end);
  Worker.FreeOnTerminate := False;
  Worker.Start;
  Conn := NewTestConnection;
  try
    A := TFirebirdActivity.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try
      S := A.Sample(2);
      Assert.IsTrue(S.ElapsedMs >= 2000, 'the window must last as long as it claims');
      Assert.IsTrue(S.Delta.SeqReads > 0,
        'a full scan ran for the whole window and the sample reported no sequential reads: ' +
        'the second reading came from the first reading''s snapshot');
      Assert.IsTrue(S.After.NextTransaction >= S.Before.NextTransaction,
        'the transaction counter cannot run backwards');
    finally A.Free; end;
  finally
    Stop := True;
    Worker.WaitFor;
    Worker.Free;
    Conn.Free;
  end;
end;

procedure TActivityTests.Sample_On_A_Quiet_Database_Reports_Nothing_And_Does_Not_Crash;
var Conn: TFirebirdConnection; A: TFirebirdActivity; S: TActivitySample; Advs: TArray<TAdvisory>;
begin
  // The seeded database with nobody working on it: every threshold must stay below the floor.
  // An advisory here would mean the detectors fire on the engine's own housekeeping.
  Conn := NewTestConnection;
  try
    A := TFirebirdActivity.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try
      S := A.Sample(1);
      Advs := A.Analyze(S);
      Assert.IsTrue(Length(Advs) = 0, 'an idle window must not manufacture findings');
    finally A.Free; end;
  finally Conn.Free; end;
end;

procedure TActivityTests.Measure_Reports_The_Records_The_Query_Actually_Read;
var Conn: TFirebirdConnection; A: TFirebirdActivity; C: TStatementCost;
begin
  // The seed holds 5000 customers and the query has no usable predicate, so the engine must
  // read all of them sequentially to return all of them.
  Conn := NewTestConnection;
  try
    A := TFirebirdActivity.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try
      C := A.Measure('SELECT * FROM CUSTOMERS');
      Assert.IsTrue(C.Executed, 'a plain SELECT must be measured');
      Assert.AreEqual(Int64(5000), C.Rows, 'every seeded row should have been fetched');
      Assert.IsTrue(C.Delta.SeqReads >= 5000,
        Format('expected at least 5000 sequential record reads, measured %d', [C.Delta.SeqReads]));
    finally A.Free; end;
  finally Conn.Free; end;
end;

procedure TActivityTests.Measure_Refuses_To_Execute_Anything_But_A_Select;
var Conn: TFirebirdConnection; A: TFirebirdActivity; C: TStatementCost; Q: TFDQuery; Rows: Int64;
begin
  { Measuring means executing, and the tools take their SQL from whoever is talking to the
    server. "Read-only" has to be enforced on the statement, not assumed of the caller: this
    test passes only if the DELETE was refused AND the rows are still there. }
  Conn := NewTestConnection;
  try
    A := TFirebirdActivity.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try
      C := A.Measure('DELETE FROM CUSTOMERS');
      Assert.IsFalse(C.Executed, 'a DELETE must never be executed to measure it');
      Assert.IsTrue(C.SkipReason.ToUpper.Contains('SELECT'), 'the refusal must say why');
    finally A.Free; end;
    Q := Conn.OpenQuery('SELECT COUNT(*) FROM CUSTOMERS');
    try Rows := Q.Fields[0].AsLargeInt; finally Q.Free; end;
    Assert.AreEqual(Int64(5000), Rows, 'the refused statement must have changed nothing');
  finally Conn.Free; end;
end;

procedure TActivityTests.IsReadOnlySelect_Accepts_Select_And_With_Only;
begin
  Assert.IsTrue(IsReadOnlySelect('SELECT 1 FROM RDB$DATABASE'));
  Assert.IsTrue(IsReadOnlySelect('  with x as (select 1 from rdb$database) select * from x'));
  Assert.IsFalse(IsReadOnlySelect('DELETE FROM CUSTOMERS'));
  Assert.IsFalse(IsReadOnlySelect('UPDATE CUSTOMERS SET CITY = ''X'''));
  Assert.IsFalse(IsReadOnlySelect('EXECUTE BLOCK AS BEGIN DELETE FROM CUSTOMERS; END'));
  Assert.IsFalse(IsReadOnlySelect(''));
end;

end.
