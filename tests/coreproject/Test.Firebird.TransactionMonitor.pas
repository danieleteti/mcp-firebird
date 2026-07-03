unit Test.Firebird.TransactionMonitor;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TTransactionMonitorTests = class
  public
    [Test] procedure Snapshot_Returns_Sane_OIT_OAT_Next;
    [Test] procedure Analyze_Is_Clean_When_No_Long_Running_Transaction;
    [Test] procedure Flags_Long_Running_Transaction_As_Blocking;
  end;
implementation
uses System.SysUtils, FireDAC.Comp.Client, Firebird.Connection, Firebird.Capabilities,
  Firebird.Advisory, Firebird.TransactionMonitor, TestFixtureU;

function Mentions(const Advs: TArray<TAdvisory>; const ANeedle: string): Boolean;
var X: TAdvisory;
begin
  Result := False;
  for X in Advs do
    if X.Finding.ToUpper.Contains(ANeedle.ToUpper) or X.SQLText.ToUpper.Contains(ANeedle.ToUpper) then Exit(True);
end;

procedure TTransactionMonitorTests.Snapshot_Returns_Sane_OIT_OAT_Next;
var Conn: TFirebirdConnection; M: TFirebirdTransactionMonitor; S: TTransactionSnapshot;
begin
  Conn := NewTestConnection;
  try
    M := TFirebirdTransactionMonitor.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try
      S := M.Snapshot;
      Assert.IsTrue(S.NextTransaction > 0, 'MON$NEXT_TRANSACTION should be positive');
      Assert.IsTrue(S.NextTransaction >= S.OIT, 'Next transaction must not precede OIT');
      Assert.IsTrue(S.Gap >= 0, 'Gap must not be negative');
    finally M.Free; end;
  finally Conn.Free; end;
end;

procedure TTransactionMonitorTests.Analyze_Is_Clean_When_No_Long_Running_Transaction;
var Conn: TFirebirdConnection; M: TFirebirdTransactionMonitor;
begin
  Conn := NewTestConnection;
  try
    M := TFirebirdTransactionMonitor.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try
      // Default 5-minute threshold: a fresh test connection's own transaction must not self-flag.
      Assert.IsFalse(Mentions(M.Analyze(5), 'pins OAT'));
    finally M.Free; end;
  finally Conn.Free; end;
end;

procedure TTransactionMonitorTests.Flags_Long_Running_Transaction_As_Blocking;
var Holder, Conn: TFirebirdConnection; M: TFirebirdTransactionMonitor; Advs: TArray<TAdvisory>;
    HolderQuery: TFDQuery;
begin
  // Holder opens (and never commits) a transaction, oldest by construction since it
  // starts before the monitoring connection below. The query is left open (not freed)
  // so its statement is still visible in MON$STATEMENTS when Analyze() runs.
  Holder := TFirebirdConnection.Create(TestConfig);
  Holder.Connect;
  Holder.FDConnection.TxOptions.AutoCommit := False;
  try
    HolderQuery := Holder.OpenQuery('SELECT * FROM CUSTOMERS');
    try
      Conn := NewTestConnection;
      try
        M := TFirebirdTransactionMonitor.Create(Conn, TFirebirdCapabilities.Detect(Conn));
        try
          // stale_minutes=0 forces the age check to trip regardless of wall-clock timing.
          Advs := M.Analyze(0);
          Assert.IsTrue(Mentions(Advs, 'pins OAT'), 'The held-open transaction should be reported as blocking GC');
          Assert.IsTrue(Mentions(Advs, 'CUSTOMERS'), 'The blocking transaction''s last SQL statement should be captured');
        finally M.Free; end;
      finally Conn.Free; end;
    finally HolderQuery.Free; end;
  finally Holder.Free; // disconnect rolls back the never-committed transaction
  end;
end;

end.
