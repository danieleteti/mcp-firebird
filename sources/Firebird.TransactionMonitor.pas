// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit Firebird.TransactionMonitor;
interface
uses Firebird.Connection, Firebird.Capabilities, Firebird.Advisory;
type
  TActiveTransactionInfo = record
    HasTransaction: Boolean;
    TransactionID: Int64;
    AttachmentID: Int64;
    AgeSeconds: Int64;
    IsolationMode: string;
    UserName: string;
    RemoteAddress: string;
    LastSQL: string;  // most recent MON$STATEMENTS.MON$SQL_TEXT for this transaction, '' if none
  end;

  TTransactionSnapshot = record
    OIT, OAT, OST, NextTransaction: Int64;
    Gap: Int64;              // NextTransaction - OIT
    SweepInterval: Int64;    // MON$DATABASE.MON$SWEEP_INTERVAL; 0 = auto-sweep disabled
    OldestActive: TActiveTransactionInfo;
  end;

  TFirebirdTransactionMonitor = class
  private
    FConn: TFirebirdConnection;
    FCaps: TFirebirdCapabilities;
    function OldestActiveTransaction: TActiveTransactionInfo;
    function LastStatementSQL(const ATransactionID: Int64): string;
  public
    constructor Create(AConn: TFirebirdConnection; const ACaps: TFirebirdCapabilities);
    function Snapshot: TTransactionSnapshot;
    function Analyze(const AStaleMinutes: Integer = 5): TArray<TAdvisory>;
  end;
implementation
uses System.SysUtils, System.Generics.Collections, FireDAC.Comp.Client;

// Below this, an idle transaction gap is normal churn; above it (with auto-sweep
// disabled) nobody is reclaiming space and bloat accrues silently.
const SWEEP_GAP_FLOOR = 20000;
const SQL_SNIPPET_LEN = 300;

function SqlSnippet(const ASQL: string): string;
var Flat: string;
begin
  if ASQL.Trim.IsEmpty then Exit('(none — transaction is idle, not currently executing)');
  Flat := ASQL.Replace(#13#10, ' ').Replace(#10, ' ').Replace(#13, ' ').Trim;
  if Flat.Length > SQL_SNIPPET_LEN then
    Result := Flat.Substring(0, SQL_SNIPPET_LEN) + '...'
  else
    Result := Flat;
end;

function IsolationModeName(const AValue: Integer): string;
begin
  case AValue of
    0: Result := 'consistency';
    1: Result := 'snapshot';
    2: Result := 'read committed (record version)';
    3: Result := 'read committed (no record version)';
  else
    Result := 'mode ' + IntToStr(AValue);
  end;
end;

constructor TFirebirdTransactionMonitor.Create(AConn: TFirebirdConnection; const ACaps: TFirebirdCapabilities);
begin
  inherited Create;
  FConn := AConn;
  FCaps := ACaps;
end;

function TFirebirdTransactionMonitor.LastStatementSQL(const ATransactionID: Int64): string;
var Q: TFDQuery;
begin
  Result := '';
  Q := FConn.OpenQuery(
    'SELECT FIRST 1 s.MON$SQL_TEXT FROM MON$STATEMENTS s ' +
    'WHERE s.MON$TRANSACTION_ID = ? ORDER BY s.MON$TIMESTAMP DESC',
    [ATransactionID]);
  try
    if not Q.Eof then
      Result := Q.FieldByName('MON$SQL_TEXT').AsString.Trim;
  finally Q.Free; end;
end;

function TFirebirdTransactionMonitor.OldestActiveTransaction: TActiveTransactionInfo;
var Q: TFDQuery;
begin
  Result := Default(TActiveTransactionInfo);
  Q := FConn.OpenQuery(
    'SELECT FIRST 1 t.MON$TRANSACTION_ID, t.MON$ATTACHMENT_ID, ' +
    'DATEDIFF(SECOND, t.MON$TIMESTAMP, CURRENT_TIMESTAMP) AS AGE_S, ' +
    't.MON$ISOLATION_MODE, a.MON$USER, a.MON$REMOTE_ADDRESS ' +
    'FROM MON$TRANSACTIONS t ' +
    'LEFT JOIN MON$ATTACHMENTS a ON a.MON$ATTACHMENT_ID = t.MON$ATTACHMENT_ID ' +
    'ORDER BY t.MON$TRANSACTION_ID ASC');
  try
    if not Q.Eof then
    begin
      Result.HasTransaction := True;
      Result.TransactionID := Q.FieldByName('MON$TRANSACTION_ID').AsLargeInt;
      Result.AttachmentID := Q.FieldByName('MON$ATTACHMENT_ID').AsLargeInt;
      Result.AgeSeconds := Q.FieldByName('AGE_S').AsLargeInt;
      Result.IsolationMode := IsolationModeName(Q.FieldByName('MON$ISOLATION_MODE').AsInteger);
      Result.UserName := Q.FieldByName('MON$USER').AsString;
      Result.RemoteAddress := Q.FieldByName('MON$REMOTE_ADDRESS').AsString;
      Result.LastSQL := LastStatementSQL(Result.TransactionID);
    end;
  finally Q.Free; end;
end;

function TFirebirdTransactionMonitor.Snapshot: TTransactionSnapshot;
var Q: TFDQuery;
begin
  Result := Default(TTransactionSnapshot);
  if not FCaps.HasMonTables then Exit;
  Q := FConn.OpenQuery('SELECT MON$OLDEST_TRANSACTION, MON$OLDEST_ACTIVE, MON$OLDEST_SNAPSHOT, MON$NEXT_TRANSACTION, MON$SWEEP_INTERVAL FROM MON$DATABASE');
  try
    if not Q.Eof then
    begin
      Result.OIT := Q.FieldByName('MON$OLDEST_TRANSACTION').AsLargeInt;
      Result.OAT := Q.FieldByName('MON$OLDEST_ACTIVE').AsLargeInt;
      Result.OST := Q.FieldByName('MON$OLDEST_SNAPSHOT').AsLargeInt;
      Result.NextTransaction := Q.FieldByName('MON$NEXT_TRANSACTION').AsLargeInt;
      Result.SweepInterval := Q.FieldByName('MON$SWEEP_INTERVAL').AsLargeInt;
      Result.Gap := Result.NextTransaction - Result.OIT;
    end;
  finally Q.Free; end;
  Result.OldestActive := OldestActiveTransaction;
end;

function TFirebirdTransactionMonitor.Analyze(const AStaleMinutes: Integer): TArray<TAdvisory>;
var S: TTransactionSnapshot; Advs: TList<TAdvisory>; StaleSeconds: Int64;
begin
  Advs := TList<TAdvisory>.Create;
  try
    if not FCaps.HasMonTables then
    begin
      Advs.Add(TAdvisory.Make(
        'Monitoring tables (MON$*) are not available on this engine version.',
        '-- n/a', '-- n/a', 'info'));
      Exit(Advs.ToArray);
    end;

    S := Snapshot;
    StaleSeconds := AStaleMinutes * 60;

    if S.OldestActive.HasTransaction and (S.OldestActive.AgeSeconds >= StaleSeconds) then
      Advs.Add(TAdvisory.Make(
        Format('Transaction %d (user %s @ %s, %s) has been active for %d min and pins OAT/OIT — no row version older than it can be garbage-collected. Last statement: %s',
          [S.OldestActive.TransactionID, S.OldestActive.UserName, S.OldestActive.RemoteAddress,
           S.OldestActive.IsolationMode, S.OldestActive.AgeSeconds div 60, SqlSnippet(S.OldestActive.LastSQL)]),
        Format('-- Ask the owning application to COMMIT/ROLLBACK, or force-disconnect: DELETE FROM MON$ATTACHMENTS WHERE MON$ATTACHMENT_ID = %d;', [S.OldestActive.AttachmentID]),
        'Re-run fb_monitor_transactions; the OIT/OAT gap should shrink once the transaction ends.',
        'critical'));

    if S.SweepInterval > 0 then
    begin
      if S.Gap > S.SweepInterval then
        Advs.Add(TAdvisory.Make(
          Format('Transaction gap (Next %d - OIT %d = %d) exceeds the configured sweep interval (%d). Auto-sweep is about to trigger and will stall the database.',
            [S.NextTransaction, S.OIT, S.Gap, S.SweepInterval]),
          '-- Schedule a manual sweep off-peak: gfix -sweep <database>',
          'Re-run fb_monitor_transactions after the sweep; the gap should drop close to zero.',
          'warning'));
    end
    else if S.Gap > SWEEP_GAP_FLOOR then
      Advs.Add(TAdvisory.Make(
        Format('Auto-sweep is disabled (MON$SWEEP_INTERVAL=0) and the transaction gap has grown to %d. Nothing is reclaiming old record versions automatically.', [S.Gap]),
        '-- Schedule a manual sweep off-peak: gfix -sweep <database>',
        'Re-run fb_monitor_transactions after the sweep; the gap should drop.',
        'info'));

    Result := Advs.ToArray;
  finally Advs.Free; end;
end;
end.
