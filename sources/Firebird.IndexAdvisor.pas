unit Firebird.IndexAdvisor;
interface
uses Firebird.Connection, Firebird.Capabilities, Firebird.Advisory;
type
  TFirebirdIndexAdvisor = class
  private
    FConn: TFirebirdConnection;
    FCaps: TFirebirdCapabilities;
  public
    constructor Create(AConn: TFirebirdConnection; const ACaps: TFirebirdCapabilities);
    function SuggestForQuery(const ASQL: string): TArray<TAdvisory>;
    function SuggestDropsForTable(const ATable: string): TArray<TAdvisory>;
  end;
implementation
uses
  System.SysUtils, System.Classes, System.StrUtils, System.Generics.Collections,
  System.RegularExpressions, Firebird.PlanAnalyzer, Firebird.Introspection;

constructor TFirebirdIndexAdvisor.Create(AConn: TFirebirdConnection; const ACaps: TFirebirdCapabilities);
begin inherited Create; FConn := AConn; FCaps := ACaps; end;

function TFirebirdIndexAdvisor.SuggestForQuery(const ASQL: string): TArray<TAdvisory>;
var PA: TFirebirdPlanAnalyzer; R: TPlanResult; T, Col, Idx: string; M: TMatch; Advs: TList<TAdvisory>;
begin
  Advs := TList<TAdvisory>.Create;
  try
    PA := TFirebirdPlanAnalyzer.Create(FConn, FCaps);
    try R := PA.Analyze(ASQL); finally PA.Free; end;
    if not R.HasNaturalScan then Exit(nil);
    for T in R.NaturalTables do
      for M in TRegEx.Matches(ASQL, '(\w+)\s*(>=|<=|=|>|<|\b(?:LIKE|BETWEEN|IN)\b)', [roIgnoreCase]) do
      begin
        Col := M.Groups[1].Value;
        if SameText(Col, T) then Continue;
        Idx := Format('IDX_%s_%s', [T, Col]).ToUpper;
        Advs.Add(TAdvisory.Make(
          Format('Table %s is scanned NATURAL when filtered by %s. An index lets the optimizer seek instead of scanning every row.', [T, Col]),
          Format('CREATE INDEX %s ON %s (%s);', [Idx, T, Col]),
          Format('Re-run fb_analyze_query on this query; the plan should use %s and no longer show "%s NATURAL". Then run SET STATISTICS INDEX %s; to refresh selectivity.', [Idx, T, Idx]),
          'warning'));
      end;
    Result := Advs.ToArray;
  finally Advs.Free; end;
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
          'Confirm no query relies on it, then drop. fb_describe_table should no longer list it.',
          'warning'));
      if not Idx[I].IsSystem then
        for J := 0 to High(Idx) do
        begin
          if I = J then Continue;
          if SameCols(Idx[I].Columns, Idx[J].Columns) and (Idx[J].IsSystem or (J < I)) then
            Advs.Add(TAdvisory.Make(
              Format('Index %s duplicates %s (same columns %s). Firebird already maintains the other index%s; the duplicate only adds write cost.',
                [Idx[I].IndexName, Idx[J].IndexName, string.Join(', ', Idx[I].Columns), IfThen(Idx[J].IsSystem, ' (a system constraint index)', '')]),
              Format('DROP INDEX %s;', [Idx[I].IndexName]),
              'fb_describe_table should list one index on these columns afterwards.',
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
          Format('Index %s has poor selectivity (%.3f, 1.0 = all rows identical). It rarely helps the optimizer.', [Idx[I].IndexName, Idx[I].Selectivity]),
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
