// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit Firebird.Activity;

{ Behavioural evidence, over a window instead of at an instant.

  Every other detector in this server reads structure: the schema, the indexes, a plan. That
  evidence constrains explanations; it rarely confirms one. A MON$ snapshot is not much better —
  it says what the counters read at the moment you looked, and a moment is exactly where
  accumulation, drift and workload phase hide.

  This unit reads the same counters twice, with a wait in between, and reports the difference:
  how many records were read sequentially and by index, how many pages moved, how many record
  versions were backed out or purged, how far the transaction horizon travelled. A delta answers
  "what is changing that should be stable?" — the question a snapshot cannot.

  Everything here is ordinary SQL over MON$. No service attach, no file on the server. }

interface

uses Firebird.Connection, Firebird.Capabilities, Firebird.Advisory;

type
  { One reading of the counters. Database-wide (MON$STAT_GROUP 0) or for a single
    attachment (group 1), depending on which reader filled it in. }
  TActivityCounters = record
    // MON$IO_STATS
    PageReads, PageWrites, PageFetches, PageMarks: Int64;
    // MON$RECORD_STATS
    SeqReads, IdxReads, Inserts, Updates, Deletes: Int64;
    Backouts, Purges, Expunges: Int64;
    { MON$BACKVERSION_READS exists from Firebird 3.0. -1 means "this engine cannot tell you",
      which is a different statement from 0 and must not be rendered as one. }
    BackversionReads: Int64;
    // MON$DATABASE + population counts; only the database-wide reader fills these
    OIT, OAT, OST, NextTransaction: Int64;
    Attachments, ActiveTransactions: Int64;
    function GarbageWork: Int64;   // backouts + purges + expunges
    function RecordReads: Int64;   // sequential + indexed
  end;

  { Two readings and the wall clock between them. Delta is what the window actually shows. }
  TActivitySample = record
    Before, After, Delta: TActivityCounters;
    ElapsedMs: Int64;
    function PerSecond(const ACount: Int64): Double;
  end;

  { What a single statement cost, measured rather than predicted. A plan says which access
    path the optimizer chose; this says how many records that choice actually touched. }
  TStatementCost = record
    Executed: Boolean;
    SkipReason: string;
    ElapsedMs: Int64;
    Rows: Int64;
    Delta: TActivityCounters;  // this attachment only, across the execution
  end;

  TFirebirdActivity = class
  private
    FConn: TFirebirdConnection;
    FCaps: TFirebirdCapabilities;
    function ReadCounters(const AAttachmentOnly: Boolean): TActivityCounters;
  public
    constructor Create(AConn: TFirebirdConnection; const ACaps: TFirebirdCapabilities);
    { Reads the database-wide counters, waits ASeconds, reads them again. }
    function Sample(const ASeconds: Integer): TActivitySample;
    { Runs ASQL to completion on this attachment and reports what it cost. Refuses anything
      that is not a plain SELECT — see Firebird.Connection.IsReadOnlySelect. }
    function Measure(const ASQL: string): TStatementCost;
    { Findings a window can support, and only those. }
    function Analyze(const ASample: TActivitySample): TArray<TAdvisory>;
  end;

const
  MIN_SAMPLE_SECONDS = 1;
  MAX_SAMPLE_SECONDS = 60;

implementation

uses System.SysUtils, System.Classes, System.Diagnostics, System.Generics.Collections,
  FireDAC.Comp.Client;

{ Below these, a window says nothing worth a finding. A handful of sequential reads is a lookup
  on a small table, not a scan; a handful of purged versions is the engine keeping house. }
const
  SEQ_READ_FLOOR = 10000;
  GARBAGE_FLOOR = 1000;
  { A gap this wide with a horizon that never moved is the shape of blocked garbage collection.
    Same floor Firebird.TransactionMonitor uses for the idle case, for the same reason. }
  FROZEN_GAP_FLOOR = 20000;

function TActivityCounters.GarbageWork: Int64;
begin
  Result := Backouts + Purges + Expunges;
end;

function TActivityCounters.RecordReads: Int64;
begin
  Result := SeqReads + IdxReads;
end;

function TActivitySample.PerSecond(const ACount: Int64): Double;
begin
  if ElapsedMs <= 0 then Exit(0);
  Result := ACount * 1000 / ElapsedMs;
end;

function Subtract(const AAfter, ABefore: TActivityCounters): TActivityCounters;
begin
  Result := Default(TActivityCounters);
  Result.PageReads := AAfter.PageReads - ABefore.PageReads;
  Result.PageWrites := AAfter.PageWrites - ABefore.PageWrites;
  Result.PageFetches := AAfter.PageFetches - ABefore.PageFetches;
  Result.PageMarks := AAfter.PageMarks - ABefore.PageMarks;
  Result.SeqReads := AAfter.SeqReads - ABefore.SeqReads;
  Result.IdxReads := AAfter.IdxReads - ABefore.IdxReads;
  Result.Inserts := AAfter.Inserts - ABefore.Inserts;
  Result.Updates := AAfter.Updates - ABefore.Updates;
  Result.Deletes := AAfter.Deletes - ABefore.Deletes;
  Result.Backouts := AAfter.Backouts - ABefore.Backouts;
  Result.Purges := AAfter.Purges - ABefore.Purges;
  Result.Expunges := AAfter.Expunges - ABefore.Expunges;
  // -1 is "unknown", and unknown minus unknown is still unknown, not zero.
  if (AAfter.BackversionReads < 0) or (ABefore.BackversionReads < 0) then
    Result.BackversionReads := -1
  else
    Result.BackversionReads := AAfter.BackversionReads - ABefore.BackversionReads;
  Result.OIT := AAfter.OIT - ABefore.OIT;
  Result.OAT := AAfter.OAT - ABefore.OAT;
  Result.OST := AAfter.OST - ABefore.OST;
  Result.NextTransaction := AAfter.NextTransaction - ABefore.NextTransaction;
  Result.Attachments := AAfter.Attachments - ABefore.Attachments;
  Result.ActiveTransactions := AAfter.ActiveTransactions - ABefore.ActiveTransactions;
end;

constructor TFirebirdActivity.Create(AConn: TFirebirdConnection; const ACaps: TFirebirdCapabilities);
begin
  inherited Create;
  FConn := AConn;
  FCaps := ACaps;
end;

function TFirebirdActivity.ReadCounters(const AAttachmentOnly: Boolean): TActivityCounters;
var Q: TFDQuery; LSQL, LBackversion, LAnchor: string;
begin
  Result := Default(TActivityCounters);
  Result.BackversionReads := -1;
  if not FCaps.HasMonTables then Exit;

  // MON$BACKVERSION_READS is the one column here that Firebird 2.5 does not have, and asking
  // for it there fails the whole statement rather than returning null.
  if FCaps.Ordinal >= 300 then
    LBackversion := 'rs.MON$BACKVERSION_READS'
  else
    LBackversion := 'CAST(-1 AS BIGINT)';

  { The counters hang off a MON$STAT_ID, and which row owns that id is the whole difference
    between "the database is doing this" and "I am doing this". }
  if AAttachmentOnly then
    LAnchor := '(SELECT a.MON$STAT_ID FROM MON$ATTACHMENTS a ' +
               'WHERE a.MON$ATTACHMENT_ID = CURRENT_CONNECTION)'
  else
    LAnchor := '(SELECT d.MON$STAT_ID FROM MON$DATABASE d)';

  LSQL :=
    'SELECT io.MON$PAGE_READS, io.MON$PAGE_WRITES, io.MON$PAGE_FETCHES, io.MON$PAGE_MARKS, ' +
    'rs.MON$RECORD_SEQ_READS, rs.MON$RECORD_IDX_READS, rs.MON$RECORD_INSERTS, ' +
    'rs.MON$RECORD_UPDATES, rs.MON$RECORD_DELETES, rs.MON$RECORD_BACKOUTS, ' +
    'rs.MON$RECORD_PURGES, rs.MON$RECORD_EXPUNGES, ' + LBackversion + ' AS BACKVERSION_READS ' +
    'FROM RDB$DATABASE ' +
    'LEFT JOIN MON$IO_STATS io ON io.MON$STAT_ID = ' + LAnchor + ' ' +
    'LEFT JOIN MON$RECORD_STATS rs ON rs.MON$STAT_ID = ' + LAnchor;

  Q := FConn.OpenQuery(LSQL);
  try
    if not Q.Eof then
    begin
      Result.PageReads := Q.FieldByName('MON$PAGE_READS').AsLargeInt;
      Result.PageWrites := Q.FieldByName('MON$PAGE_WRITES').AsLargeInt;
      Result.PageFetches := Q.FieldByName('MON$PAGE_FETCHES').AsLargeInt;
      Result.PageMarks := Q.FieldByName('MON$PAGE_MARKS').AsLargeInt;
      Result.SeqReads := Q.FieldByName('MON$RECORD_SEQ_READS').AsLargeInt;
      Result.IdxReads := Q.FieldByName('MON$RECORD_IDX_READS').AsLargeInt;
      Result.Inserts := Q.FieldByName('MON$RECORD_INSERTS').AsLargeInt;
      Result.Updates := Q.FieldByName('MON$RECORD_UPDATES').AsLargeInt;
      Result.Deletes := Q.FieldByName('MON$RECORD_DELETES').AsLargeInt;
      Result.Backouts := Q.FieldByName('MON$RECORD_BACKOUTS').AsLargeInt;
      Result.Purges := Q.FieldByName('MON$RECORD_PURGES').AsLargeInt;
      Result.Expunges := Q.FieldByName('MON$RECORD_EXPUNGES').AsLargeInt;
      Result.BackversionReads := Q.FieldByName('BACKVERSION_READS').AsLargeInt;
    end;
  finally Q.Free; end;

  if AAttachmentOnly then Exit;

  Q := FConn.OpenQuery(
    'SELECT d.MON$OLDEST_TRANSACTION, d.MON$OLDEST_ACTIVE, d.MON$OLDEST_SNAPSHOT, ' +
    'd.MON$NEXT_TRANSACTION, ' +
    '(SELECT COUNT(*) FROM MON$ATTACHMENTS) AS ATTACHMENTS, ' +
    '(SELECT COUNT(*) FROM MON$TRANSACTIONS) AS TRANSACTIONS ' +
    'FROM MON$DATABASE d');
  try
    if not Q.Eof then
    begin
      Result.OIT := Q.FieldByName('MON$OLDEST_TRANSACTION').AsLargeInt;
      Result.OAT := Q.FieldByName('MON$OLDEST_ACTIVE').AsLargeInt;
      Result.OST := Q.FieldByName('MON$OLDEST_SNAPSHOT').AsLargeInt;
      Result.NextTransaction := Q.FieldByName('MON$NEXT_TRANSACTION').AsLargeInt;
      Result.Attachments := Q.FieldByName('ATTACHMENTS').AsLargeInt;
      Result.ActiveTransactions := Q.FieldByName('TRANSACTIONS').AsLargeInt;
    end;
  finally Q.Free; end;
end;

function TFirebirdActivity.Sample(const ASeconds: Integer): TActivitySample;
var LSeconds: Integer; SW: TStopwatch;
begin
  LSeconds := ASeconds;
  if LSeconds < MIN_SAMPLE_SECONDS then LSeconds := MIN_SAMPLE_SECONDS;
  if LSeconds > MAX_SAMPLE_SECONDS then LSeconds := MAX_SAMPLE_SECONDS;

  Result := Default(TActivitySample);
  FConn.NewMonitoringSnapshot;
  Result.Before := ReadCounters(False);
  SW := TStopwatch.StartNew;
  TThread.Sleep(LSeconds * 1000);
  // Without this the second read is served from the snapshot the first one froze, and every
  // delta comes out zero: a window that reports perfect calm because it never looked twice.
  FConn.NewMonitoringSnapshot;
  Result.After := ReadCounters(False);
  Result.ElapsedMs := SW.ElapsedMilliseconds;
  Result.Delta := Subtract(Result.After, Result.Before);
end;

function TFirebirdActivity.Measure(const ASQL: string): TStatementCost;
var Q: TFDQuery; SW: TStopwatch; LBefore, LAfter: TActivityCounters;
begin
  Result := Default(TStatementCost);
  if not FCaps.HasMonTables then
  begin
    Result.SkipReason := 'this engine has no MON$ monitoring tables, so execution cost cannot be measured';
    Exit;
  end;
  if not IsReadOnlySelect(ASQL) then
  begin
    Result.SkipReason := 'only a plain SELECT is executed; this statement was analyzed, not run';
    Exit;
  end;

  FConn.NewMonitoringSnapshot;
  LBefore := ReadCounters(True);
  SW := TStopwatch.StartNew;
  Q := FConn.OpenQuery(ASQL);
  try
    // Fetch everything: a dataset that stops at the first page measures the first page.
    while not Q.Eof do
    begin
      Inc(Result.Rows);
      Q.Next;
    end;
  finally Q.Free; end;
  Result.ElapsedMs := SW.ElapsedMilliseconds;
  FConn.NewMonitoringSnapshot;
  LAfter := ReadCounters(True);
  Result.Delta := Subtract(LAfter, LBefore);
  Result.Executed := True;
end;

function TFirebirdActivity.Analyze(const ASample: TActivitySample): TArray<TAdvisory>;
var Advs: TList<TAdvisory>; D: TActivityCounters; LGap: Int64;
begin
  Advs := TList<TAdvisory>.Create;
  try
    if not FCaps.HasMonTables then
    begin
      Advs.Add(TAdvisory.Make(
        'Monitoring tables (MON$*) are not available on this engine version.', '', '-- n/a', 'info'));
      Exit(Advs.ToArray);
    end;

    D := ASample.Delta;
    LGap := ASample.After.NextTransaction - ASample.After.OIT;

    { Transactions kept starting and finishing, and the horizon behind them did not move.
      That is the accumulation shape: nothing is being reclaimed while the work continues. }
    if (D.NextTransaction > 0) and (D.OIT = 0) and (LGap > FROZEN_GAP_FLOOR) then
      Advs.Add(TAdvisory.Make(
        Format('%d transactions started during this %d s window, but the oldest interesting ' +
               'transaction (OIT %d) did not move and the gap stands at %d. Garbage collection ' +
               'is making no progress while the workload continues.',
          [D.NextTransaction, ASample.ElapsedMs div 1000, ASample.After.OIT, LGap]),
        '', 'Run fb_monitor_transactions to name the transaction pinning the horizon, then sample ' +
            'again: once it ends, OIT moves between two windows.', 'warning'));

    { Sequential reads are not a fault in themselves — a report scans, and that is its job. They
      matter when they dominate, because that is the workload the plans are actually running. }
    if (D.SeqReads > SEQ_READ_FLOOR) and (D.SeqReads > D.IdxReads) then
      Advs.Add(TAdvisory.Make(
        // Invariant, like every other rendered number here: this text is read by a machine in
        // whatever locale the server happens to run under, and "1,0" is not one point zero there.
        Format('The workload read %d records sequentially against %d by index in %d ms ' +
               '(%.0f sequential records/s). Whatever is running is dominated by scans.',
          [D.SeqReads, D.IdxReads, ASample.ElapsedMs, ASample.PerSecond(D.SeqReads)],
          TFormatSettings.Invariant),
        '', 'Capture the statements running in this window (MON$STATEMENTS) and put the ones that ' +
            'scan through fb_analyze_query; sample again afterwards and compare the ratio.', 'info'));

    { Version churn: the engine spending the window undoing and cleaning up rather than reading. }
    if D.GarbageWork > GARBAGE_FLOOR then
      Advs.Add(TAdvisory.Make(
        Format('%d record versions were backed out, purged or expunged in this window ' +
               '(backouts %d, purges %d, expunges %d). The engine is spending the window on ' +
               'garbage rather than on work.',
          [D.GarbageWork, D.Backouts, D.Purges, D.Expunges]),
        '', 'Sample again after the update-heavy job ends. If the churn persists with no such job ' +
            'running, look for a transaction held open across it (fb_monitor_transactions).', 'info'));

    Result := Advs.ToArray;
  finally Advs.Free; end;
end;

end.
