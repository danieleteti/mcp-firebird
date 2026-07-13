// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit Firebird.IndexAdvisor;
interface
uses Firebird.Connection, Firebird.Advisory;
type
  TFirebirdIndexAdvisor = class
  private
    FConn: TFirebirdConnection;
    FEngineVersion: string;
  public
    constructor Create(AConn: TFirebirdConnection; const AEngineVersion: string);
    function SuggestForQuery(const ASQL: string): TArray<TAdvisory>;
    function SuggestDropsForTable(const ATable: string): TArray<TAdvisory>;
  end;
implementation
uses
  System.SysUtils, System.Classes, System.StrUtils, System.Generics.Collections,
  System.RegularExpressions, Firebird.PlanAnalyzer, Firebird.Introspection;

constructor TFirebirdIndexAdvisor.Create(AConn: TFirebirdConnection; const AEngineVersion: string);
begin inherited Create; FConn := AConn; FEngineVersion := AEngineVersion; end;

{ Alias -> table, read from the FROM/JOIN clauses, plus every table mapped to itself.

  Firebird prints the ALIAS in the plan ("PLAN JOIN (C NATURAL, O INDEX (...))"), so without this
  the suggested DDL says CREATE INDEX ... ON C, and there is no table C. }
function AliasMap(const ASQL: string): TDictionary<string, string>;
const
  // A word that follows the table name but is not an alias.
  KEYWORDS = 'ON,WHERE,JOIN,INNER,LEFT,RIGHT,FULL,OUTER,CROSS,NATURAL,GROUP,ORDER,HAVING,' +
             'UNION,PLAN,FOR,SET,RETURNING,WITH,AS';
var M: TMatch; Table, Alias: string;
begin
  Result := TDictionary<string, string>.Create;
  for M in TRegEx.Matches(ASQL, '\b(?:FROM|JOIN)\s+(\w+)(?:\s+(?:AS\s+)?(\w+))?', [roIgnoreCase]) do
  begin
    Table := M.Groups[1].Value.ToUpper;
    Result.AddOrSetValue(Table, Table);
    Alias := M.Groups[2].Value.ToUpper;
    if (Alias <> '') and (IndexStr(Alias, KEYWORDS.Split([','])) < 0) then
      Result.AddOrSetValue(Alias, Table);
  end;
end;

function TFirebirdIndexAdvisor.SuggestForQuery(const ASQL: string): TArray<TAdvisory>;
var
  PA: TFirebirdPlanAnalyzer; R: TPlanResult; Advs: TList<TAdvisory>;
  Aliases: TDictionary<string, string>; Intro: TFirebirdIntrospection;
  Scanned, T, Qual, Col, Idx: string; M: TMatch; C: TColumnInfo; X: TIndexInfo;
  Cols, Indexed, Dormant, Seen: TStringList;

  function Resolve(const AName: string): string;
  begin
    if not Aliases.TryGetValue(AName.ToUpper, Result) then Result := AName.ToUpper;
  end;

begin
  Advs := TList<TAdvisory>.Create;
  Aliases := AliasMap(ASQL);
  Intro := TFirebirdIntrospection.Create(FConn);
  try
    PA := TFirebirdPlanAnalyzer.Create(FConn, FEngineVersion);
    try R := PA.Analyze(ASQL); finally PA.Free; end;
    if not R.HasNaturalScan then Exit(nil);

    for Scanned in R.NaturalTables do
    begin
      T := Resolve(Scanned);
      Cols := TStringList.Create; Indexed := TStringList.Create; Seen := TStringList.Create;
      Dormant := TStringList.Create;
      try
        Cols.CaseSensitive := False; Indexed.CaseSensitive := False; Seen.CaseSensitive := False;
        Dormant.CaseSensitive := False;
        for C in Intro.GetColumns(T) do Cols.Add(C.FieldName);
        // An INACTIVE index cannot serve a read, so it does not make its column indexed -- but it
        // exists, and the fix is to switch it back on, not to build a second one beside it. Told
        // only "no index on CITY", a caller creates IDX_CUSTOMERS_CITY next to the sleeping
        // IDX_CUST_CITY: two indexes over one column, both written on every INSERT, one of them
        // dead. Remember the name, so the advice can be the real one.
        for X in Intro.GetIndexes(T) do
          if Length(X.Columns) > 0 then
            if X.Inactive then
              Dormant.AddPair(X.Columns[0], X.IndexName)
            else
              Indexed.Add(X.Columns[0]);

        for M in TRegEx.Matches(ASQL,
          '(?:(\w+)\s*\.\s*)?(\w+)\s*(>=|<=|=|>|<|\b(?:LIKE|BETWEEN|IN)\b)', [roIgnoreCase]) do
        begin
          Qual := M.Groups[1].Value;
          Col := M.Groups[2].Value;
          // A qualified column belongs to the table its qualifier names, and to no other.
          if (Qual <> '') and not SameText(Resolve(Qual), T) then Continue;
          // Unqualified, it belongs to this table only if this table has such a column — the
          // regex also matches the right-hand side of a join predicate and plain literals.
          if Cols.IndexOf(Col) < 0 then Continue;
          // Already the leading column of an index: the optimizer can seek it, and chose not to.
          // Suggesting it again (a join key on its own primary key, typically) is noise.
          if Indexed.IndexOf(Col) >= 0 then Continue;
          if Seen.IndexOf(Col) >= 0 then Continue;
          Seen.Add(Col);

          // The index the query wants is already there, switched off. Reactivating it rebuilds it
          // from the current data; creating another one duplicates it forever.
          Idx := Dormant.Values[Col];
          if Idx <> '' then
          begin
            Advs.Add(TAdvisory.Make(
              Format('Table %s is scanned NATURAL when filtered by %s, and index %s (%s) already covers that column — but it is INACTIVE, so the optimizer cannot use it. Do not create a second index: reactivate this one.',
                [T, Col, Idx, Col]),
              Format('ALTER INDEX %s ACTIVE;', [Idx]),
              Format('Re-run fb_analyze_query on this query; the plan should use %s and no longer show "%s NATURAL". ALTER INDEX ACTIVE rebuilds the index, so its statistics are current; run SET STATISTICS INDEX %s; later if the data shifts.', [Idx, T, Idx]),
              'warning'));
            Continue;
          end;

          Idx := Format('IDX_%s_%s', [T, Col]).ToUpper;
          Advs.Add(TAdvisory.Make(
            Format('Table %s is scanned NATURAL when filtered by %s. An index lets the optimizer seek instead of scanning every row.', [T, Col]),
            Format('CREATE INDEX %s ON %s (%s);', [Idx, T, Col]),
            Format('Re-run fb_analyze_query on this query; the plan should use %s and no longer show "%s NATURAL". Then run SET STATISTICS INDEX %s; to refresh selectivity.', [Idx, T, Idx]),
            'warning'));
        end;
      finally
        Cols.Free;
        Indexed.Free;
        Dormant.Free;
        Seen.Free;
      end;
    end;
    Result := Advs.ToArray;
  finally Advs.Free; Aliases.Free; Intro.Free; end;
end;

function TFirebirdIndexAdvisor.SuggestDropsForTable(const ATable: string): TArray<TAdvisory>;
var Intro: TFirebirdIntrospection; Idx: TArray<TIndexInfo>; I, J: Integer; Advs: TList<TAdvisory>;
  function SameCols(const A, B: TArray<string>): Boolean;
  var K: Integer;
  begin
    Result := Length(A) = Length(B);
    if Result then for K := 0 to High(A) do if not SameText(A[K], B[K]) then Exit(False);
  end;
  function IsLeftPrefixOf(const A, B: TArray<string>): Boolean;
  var K: Integer;
  begin
    Result := (Length(A) > 0) and (Length(A) < Length(B));
    if Result then for K := 0 to High(A) do if not SameText(A[K], B[K]) then Exit(False);
  end;
begin
  Advs := TList<TAdvisory>.Create;
  Intro := TFirebirdIntrospection.Create(FConn);
  try
    Idx := Intro.GetIndexes(ATable);
    for I := 0 to High(Idx) do
    begin
      if Idx[I].Inactive then
        Advs.Add(TAdvisory.Make(
          Format('Index %s on %s is INACTIVE: it is not used for reads but still must be maintained if reactivated.', [Idx[I].IndexName, ATable]),
          Format('DROP INDEX %s;  -- or ALTER INDEX %s ACTIVE; if you intend to use it', [Idx[I].IndexName, Idx[I].IndexName]),
          'Confirm no query relies on it, then drop. fb_generate_documentation should no longer list it.',
          'warning'));
      if not Idx[I].IsSystem then
        for J := 0 to High(Idx) do
        begin
          if I = J then Continue;
          // Direction is part of the index's identity: a DESCENDING index over the same columns
          // is the only one that serves ORDER BY ... DESC and MAX() without a sort, so it
          // duplicates nothing. Dropping it is the one suggestion here that would make a healthy
          // database slower.
          if Idx[I].Descending <> Idx[J].Descending then Continue;
          if SameCols(Idx[I].Columns, Idx[J].Columns) and (Idx[J].IsSystem or (J < I)) then
            Advs.Add(TAdvisory.Make(
              Format('Index %s duplicates %s (same columns %s). Firebird already maintains the other index%s; the duplicate only adds write cost.',
                [Idx[I].IndexName, Idx[J].IndexName, string.Join(', ', Idx[I].Columns), IfThen(Idx[J].IsSystem, ' (a system constraint index)', '')]),
              Format('DROP INDEX %s;', [Idx[I].IndexName]),
              'fb_generate_documentation should list one index on these columns afterwards.',
              'warning'))
          else if IsLeftPrefixOf(Idx[I].Columns, Idx[J].Columns) and not Idx[I].Unique then
            Advs.Add(TAdvisory.Make(
              Format('Index %s (%s) is a left-prefix of %s (%s); the wider index already serves prefix lookups.',
                [Idx[I].IndexName, string.Join(', ', Idx[I].Columns), Idx[J].IndexName, string.Join(', ', Idx[J].Columns)]),
              Format('DROP INDEX %s;', [Idx[I].IndexName]),
              'Verify queries still use the wider index via fb_analyze_query.',
              'info'));
        end;
      if (not Idx[I].IsSystem) and (Idx[I].Selectivity > 0.5) then
        Advs.Add(TAdvisory.Make(
          Format('Index %s has poor selectivity (%.3f, 1.0 = all rows identical). It rarely helps the optimizer.',
            [Idx[I].IndexName, Idx[I].Selectivity], TFormatSettings.Invariant),
          Format('-- Review usage before dropping:%sDROP INDEX %s;', [sLineBreak, Idx[I].IndexName]),
          'Run SET STATISTICS INDEX ' + Idx[I].IndexName + '; first to refresh; if still > 0.5 it is a drop candidate.',
          'info'));
    end;
    Result := Advs.ToArray;
  finally
    Intro.Free; Advs.Free;
  end;
end;
end.
