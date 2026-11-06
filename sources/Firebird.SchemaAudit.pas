// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit Firebird.SchemaAudit;
interface
uses Firebird.Connection, Firebird.Advisory;
type
  { What one column really contains, read in a single pass.

    Selectivity is what the optimizer reasons with, and the engine never recomputes it on its
    own: the stored figure is whatever the data looked like the last time somebody said so.
    Comparing the two is the only way to tell "the optimizer weighed this index and declined"
    from "the optimizer is reasoning about last year's table". }
  TColumnStats = record
    Rows, NonNull, Distinct: Int64;
    { False when the two numbers cannot honestly be compared, with the reason in NotComparable.
      COUNT(DISTINCT) ignores NULLs and the index does not, so on a mostly-empty column the two
      figures disagree for a reason that is not staleness. }
    Comparable: Boolean;
    NotComparable: string;
    function Selectivity: Double;
    function NullFraction: Double;
  end;

  { One column of the table, as fb_column_stats reports it. IndexName is the first active index
    that leads on the column ('' when there is none); Stored is the selectivity that index holds,
    negative when the engine holds none. }
  TColumnStatsRow = record
    Column: string;
    Stats: TColumnStats;
    IndexName: string;
    Stored: Double;
  end;

  TStaleIndexInfo = record
    IndexName, Column: string;
    Stored, Actual: Double;
  end;

  TFirebirdSchemaAudit = class
  private
    FConn: TFirebirdConnection;
  public
    constructor Create(AConn: TFirebirdConnection);
    function AuditTable(const ATable: string): TArray<TAdvisory>;
    { One scan of the column: row count, non-null count and distinct count together. }
    function ColumnStats(const ATable, AColumn: string): TColumnStats;
    { ColumnStats for several columns of one table in a single scan. If the engine refuses the
      combined statement (one column of a type COUNT(DISTINCT) cannot take), falls back to one
      scan per column, where each refusal is reported against its own column. Column names are
      matched against the catalogue, so only a real column ever reaches the SQL. }
    function TableStats(const ATable: string; const AColumns: TArray<string>): TArray<TColumnStatsRow>;
    { The selectivity the optimizer holds for AColumn as part of AIndex.

      RDB$INDICES.RDB$STATISTICS is the selectivity of the whole key, so on a composite index it
      is not the number to compare a single column against; RDB$INDEX_SEGMENTS carries the
      per-segment figure (2.0+) and that is the one used, with the whole-key value as the
      fallback a single-segment index makes identical anyway. Negative means the engine holds no
      figure at all. }
    function StoredSelectivity(const AIndexName, AColumn: string): Double;
    { Indexes on ATable whose stored selectivity no longer describes the data. Backs both the
      fb_audit_table finding and the no_stale_index_statistics goal, so the two can never
      disagree about what "stale" means. }
    function StaleIndexes(const ATable: string): TArray<TStaleIndexInfo>;
  end;

{ The one definition of "stale": stored differs from actual by more than STALE_FACTOR of actual.
  Shared by the audit and by fb_column_stats, so they cannot disagree. }
function IsStale(AStored, AActual: Double): Boolean;

const
  { Stored differs from actual by more than half of actual: the optimizer is costing this index
    against data that is no longer there. Shared with Firebird.IndexAdvisor — one threshold, one
    meaning, and every advisory that applies it prints the two numbers it applied it to. }
  STALE_FACTOR = 0.5;
  { Above this fraction of NULLs the stored and actual figures are measuring different
    populations, and their disagreement says nothing about staleness. }
  NULL_HEAVY_FRACTION = 0.5;

implementation
uses System.SysUtils, System.Generics.Collections, FireDAC.Comp.Client, Firebird.Introspection;

const OVER_INDEX_THRESHOLD = 5;

function IsStale(AStored, AActual: Double): Boolean;
begin
  Result := Abs(AStored - AActual) > (AActual * STALE_FACTOR);
end;

{ Decides whether the three counts can be compared with a stored selectivity, and why not. }
procedure Judge(var AStats: TColumnStats);
begin
  if AStats.Rows = 0 then
    AStats.NotComparable := 'the table is empty'
  else if AStats.Distinct = 0 then
    AStats.NotComparable := 'every row is NULL in this column'
  else if AStats.NullFraction > NULL_HEAVY_FRACTION then
    AStats.NotComparable := Format('%.0f%% of the rows are NULL in this column, and the stored ' +
      'selectivity counts them while COUNT(DISTINCT) does not',
      [AStats.NullFraction * 100], TFormatSettings.Invariant)
  else
    AStats.Comparable := True;
end;

function TColumnStats.Selectivity: Double;
begin
  if Distinct = 0 then Exit(0);
  Result := 1.0 / Distinct;
end;

function TColumnStats.NullFraction: Double;
begin
  if Rows = 0 then Exit(0);
  Result := (Rows - NonNull) / Rows;
end;

constructor TFirebirdSchemaAudit.Create(AConn: TFirebirdConnection);
begin inherited Create; FConn := AConn; end;

function TFirebirdSchemaAudit.ColumnStats(const ATable, AColumn: string): TColumnStats;
var Q: TFDQuery;
begin
  Result := Default(TColumnStats);
  try
    Q := FConn.OpenQuery(Format('SELECT COUNT(*), COUNT(%0:s), COUNT(DISTINCT %0:s) FROM %1:s',
      [QuoteIdent(AColumn), QuoteIdent(ATable)]));
    try
      if not Q.Eof then
      begin
        Result.Rows := Q.Fields[0].AsLargeInt;
        Result.NonNull := Q.Fields[1].AsLargeInt;
        Result.Distinct := Q.Fields[2].AsLargeInt;
      end;
    finally Q.Free; end;
  except
    // COUNT(DISTINCT) is not defined for every column type a table can carry (a BLOB, most
    // obviously). An unanswerable question is reported as unanswered, not as a finding.
    on E: Exception do
    begin
      Result.NotComparable := 'the engine refused to count distinct values of this column (' + E.Message + ')';
      Exit;
    end;
  end;
  Judge(Result);
end;

function TFirebirdSchemaAudit.TableStats(const ATable: string;
  const AColumns: TArray<string>): TArray<TColumnStatsRow>;
var
  Intro: TFirebirdIntrospection;
  lCatalogue: TArray<TColumnInfo>;
  lIndexes: TArray<TIndexInfo>;
  lSQL: string;
  Q: TFDQuery;
  C: TColumnInfo;
  X: TIndexInfo;
  lName: string;
  lRow: TColumnStatsRow;
  lFound: Boolean;
begin
  Intro := TFirebirdIntrospection.Create(FConn);
  try
    lCatalogue := Intro.GetColumns(ATable);
    lIndexes := Intro.GetIndexes(ATable);
  finally
    Intro.Free;
  end;
  if Length(lCatalogue) = 0 then
    raise Exception.CreateFmt('Table %s was not found (or has no columns).', [ATable]);

  Result := [];
  for lName in AColumns do
  begin
    lFound := False;
    for C in lCatalogue do
      if SameText(C.FieldName, lName) then
      begin
        lFound := True;
        lRow := Default(TColumnStatsRow);
        lRow.Column := C.FieldName;
        lRow.Stored := -1;
        for X in lIndexes do
          if (not X.Inactive) and (Length(X.Columns) > 0) and SameText(X.Columns[0], C.FieldName) then
          begin
            lRow.IndexName := X.IndexName;
            lRow.Stored := StoredSelectivity(X.IndexName, C.FieldName);
            if lRow.Stored < 0 then
              lRow.Stored := X.Selectivity;
            Break;
          end;
        Result := Result + [lRow];
        Break;
      end;
    if not lFound then
      raise Exception.CreateFmt('Table %s has no column %s.', [ATable, lName]);
  end;
  if Length(Result) = 0 then
    Exit;

  lSQL := 'SELECT COUNT(*)';
  for lRow in Result do
    lSQL := lSQL + Format(', COUNT(%0:s), COUNT(DISTINCT %0:s)', [QuoteIdent(lRow.Column)]);
  lSQL := lSQL + ' FROM ' + QuoteIdent(ATable);
  try
    Q := FConn.OpenQuery(lSQL);
    try
      for var I := 0 to High(Result) do
      begin
        Result[I].Stats.Rows := Q.Fields[0].AsLargeInt;
        Result[I].Stats.NonNull := Q.Fields[1 + I * 2].AsLargeInt;
        Result[I].Stats.Distinct := Q.Fields[2 + I * 2].AsLargeInt;
        Judge(Result[I].Stats);
      end;
    finally
      Q.Free;
    end;
  except
    for var I := 0 to High(Result) do
      Result[I].Stats := ColumnStats(ATable, Result[I].Column);
  end;
end;

function TFirebirdSchemaAudit.StoredSelectivity(const AIndexName, AColumn: string): Double;
var Q: TFDQuery;
begin
  // Read as a float, never through a string: rendering a Firebird DOUBLE into text goes through
  // the host locale, and "0,25" parsed back under invariant settings is not a quarter.
  Result := -1;
  Q := FConn.OpenQuery(
    'SELECT rdb$statistics FROM rdb$index_segments WHERE rdb$index_name = ' + QuotedStr(AIndexName) +
    ' AND TRIM(rdb$field_name) = ' + QuotedStr(AColumn));
  try
    // The segment column is populated from 2.0 on, but a NULL there (an index never analyzed)
    // has to stay distinguishable from a genuine zero.
    if (not Q.Eof) and (not Q.Fields[0].IsNull) then Result := Q.Fields[0].AsFloat;
  finally Q.Free; end;
end;

function TFirebirdSchemaAudit.StaleIndexes(const ATable: string): TArray<TStaleIndexInfo>;
var Intro: TFirebirdIntrospection; X: TIndexInfo; Stats: TColumnStats; Info: TStaleIndexInfo;
    Stored: Double; L: TList<TStaleIndexInfo>;
begin
  L := TList<TStaleIndexInfo>.Create;
  Intro := TFirebirdIntrospection.Create(FConn);
  try
    for X in Intro.GetIndexes(ATable) do
    begin
      // An INACTIVE index has no statistics to be stale: RDB$STATISTICS is NULL, the optimizer
      // cannot use it for reads, and the remedy is fb_suggest_index_drops, not SET STATISTICS.
      if X.IsSystem or X.Inactive or (Length(X.Columns) = 0) then Continue;
      // The leading segment is the only one an equality predicate can seek on, and the only one
      // whose distinct count is comparable with a stored figure.
      Stored := StoredSelectivity(X.IndexName, X.Columns[0]);
      if Stored < 0 then Stored := X.Selectivity;
      if Stored < 0 then Continue;
      Stats := ColumnStats(ATable, X.Columns[0]);
      if not Stats.Comparable then Continue;
      if IsStale(Stored, Stats.Selectivity) then
      begin
        Info.IndexName := X.IndexName;
        Info.Column := X.Columns[0];
        Info.Stored := Stored;
        Info.Actual := Stats.Selectivity;
        L.Add(Info);
      end;
    end;
    Result := L.ToArray;
  finally Intro.Free; L.Free; end;
end;

function TFirebirdSchemaAudit.AuditTable(const ATable: string): TArray<TAdvisory>;
var Intro: TFirebirdIntrospection; PK: TArray<string>; Idx: TArray<TIndexInfo>;
    UserIdx: Integer; X: TIndexInfo; S: TStaleIndexInfo; Advs: TList<TAdvisory>;
begin
  Advs := TList<TAdvisory>.Create;
  Intro := TFirebirdIntrospection.Create(FConn);
  try
    PK := Intro.GetPrimaryKey(ATable);
    if Length(PK) = 0 then
      Advs.Add(TAdvisory.Make(
        Format('Table %s has no PRIMARY KEY. Rows cannot be addressed uniquely; replication, updates and joins all suffer.', [ATable]),
        Format('ALTER TABLE %s ADD CONSTRAINT PK_%s PRIMARY KEY (/* choose a unique column */);', [ATable, ATable]),
        'fb_generate_documentation should then list a PRIMARY KEY constraint.',
        'critical'));

    Idx := Intro.GetIndexes(ATable);

    UserIdx := 0;
    for X in Idx do if not X.IsSystem then Inc(UserIdx);
    if UserIdx > OVER_INDEX_THRESHOLD then
      Advs.Add(TAdvisory.Make(
        Format('Table %s carries %d user indexes. Every INSERT/UPDATE/DELETE must maintain all of them; on a write-heavy table this is a major cost.', [ATable, UserIdx]),
        Format('-- Review with fb_suggest_index_drops %s and drop the unused ones.', [ATable]),
        'Re-run fb_audit_table after dropping; the count should fall.',
        'warning'));

    for S in StaleIndexes(ATable) do
      Advs.Add(TAdvisory.Make(
        // %g, not %f: on a table of twenty million rows the real selectivity is ~5e-8, and
        // six decimals render both figures as "0.000000". Invariant settings, because these
        // numbers are read by a machine and a decimal comma is not a number to it.
        Format('Index %s has stale statistics: stored selectivity %g vs actual %g on its leading ' +
               'column %s. The optimizer may pick a bad plan from outdated numbers (common after bulk loads).',
               [S.IndexName, S.Stored, S.Actual, S.Column], TFormatSettings.Invariant),
        Format('SET STATISTICS INDEX %s;', [S.IndexName]),
        'Re-run fb_audit_table; stored and actual selectivity should match.',
        'warning'));

    Result := Advs.ToArray;
  finally
    Intro.Free; Advs.Free;
  end;
end;
end.
