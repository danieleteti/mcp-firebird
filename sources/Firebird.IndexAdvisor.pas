// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit Firebird.IndexAdvisor;

{ What to build, what to refresh, and when to build nothing at all.

  Two sources of evidence, each used only for what it actually knows. The plan says what the
  engine did: which table it scanned, which index it used and how much of that index the query
  agreed with. It never says what was filtered — `WHERE CITY = 'Rome'` and
  `WHERE UPPER(NAME) = 'CUST_1'` produce byte-identical trees — so the predicate can only come
  from the SQL text. And neither source says whether an index would pay: that comes from
  executing the query once and comparing what it read with what it kept.

  The order of the remedies matters more than any of them. Firebird never recalculates index
  selectivity on its own, so an index that exists and is ignored may be ignored because the
  optimizer is reasoning about last year's data. SET STATISTICS costs a read of the index and
  leaves nothing behind; CREATE INDEX costs every INSERT into that table, forever. This unit
  always proposes the lowest rung that can explain what the plan did. }

interface
uses Firebird.Connection, Firebird.Advisory, Firebird.Capabilities;

type
  { One comparison the query makes, as written. Either a bare column (CITY = 'Rome') or one
    function around a column (UPPER(NAME) = 'X'); nothing deeper is parsed, and anything deeper
    is dropped rather than guessed at. }
  TPredicate = record
    Qualifier: string;    // the alias or table written before the dot; '' when unqualified
    Expression: string;   // the function call verbatim, '' for a bare column
    Op: string;
    Literal: string;      // the constant compared against; '' for a parameter or anything else
    { Every identifier the left-hand side mentions. The caller keeps the first one that is a
      column of the table it is asking about, which is also how EXTRACT(YEAR FROM D) resolves
      to D and not to YEAR. }
    Idents: TArray<string>;
    { The right-hand side is another column — a join predicate, not a filter. It says nothing
      about how selective anything is, so it never triggers a check that costs a scan. }
    RightIsColumn: Boolean;
    function IsExpression: Boolean;
    function IsLiteralEquality: Boolean;
  end;

  { One term of an ORDER BY. Direction is part of it: Firebird cannot walk an ascending index
    backwards, so ORDER BY x DESC needs a DESCENDING index and not the one you already have. }
  TSortKey = record
    Qualifier, Column, Expression: string;
    Descending, Understood: Boolean;
  end;

  TFirebirdIndexAdvisor = class
  private
    FConn: TFirebirdConnection;
    FEngineVersion: string;
    FCaps: TFirebirdCapabilities;
  public
    constructor Create(AConn: TFirebirdConnection; const AEngineVersion: string);
    function SuggestForQuery(const ASQL: string): TArray<TAdvisory>;
    function SuggestDropsForTable(const ATable: string): TArray<TAdvisory>;
  end;

{ Text-level extraction. Public because it is the part of this unit that is pure text, and the
  part most likely to be wrong: it is worth testing without a database in the way. }
function ExtractPredicates(const ASQL: string): TArray<TPredicate>;
function ExtractOrderBy(const ASQL: string): TArray<TSortKey>;
{ A query whose result set is an aggregate returns one row out of thousands by design, so its
  yield says nothing about whether an index would help. }
function IsAggregateQuery(const ASQL: string): Boolean;
{ FIRST / ROWS / FETCH FIRST: the case where removing a sort pays most, because the sort being
  removed is a sort of the whole result set in order to return a screenful. }
function HasRowLimit(const ASQL: string): Boolean;

const
  { Above this, the scan keeps at least a fifth of everything it reads, and walking a B-tree to
    fetch the same rows is unlikely to pay for the write cost it adds to every INSERT. }
  YIELD_FLOOR = 0.20;
  { Below this many records read, the whole table is a handful of pages: an index changes
    nothing measurable and still costs every write. }
  SCAN_FLOOR = 5000;
  { Above this, COUNT(DISTINCT) is a scan nobody asked for. The advisory reports an honest
    unknown instead of buying an expensive certainty. }
  BIG_TABLE_READS = 1000000;
  { Firebird 3.0 and earlier cap an identifier at 31 characters. }
  MAX_IDENT_LEN = 31;

implementation
uses
  System.SysUtils, System.Classes, System.StrUtils, System.Math,
  System.Generics.Collections, System.RegularExpressions,
  Firebird.PlanAnalyzer, Firebird.Introspection, Firebird.SchemaAudit, Firebird.Activity;

const
  { Sargable comparisons only. <> and != are matched so that they can be discarded: an
    alternation that stops at '<' reads `A <> 5` as a range predicate and prescribes an index
    for it. }
  PRED_OPS = '(<>|!=|>=|<=|=|>|<|\bNOT\s+LIKE\b|\bLIKE\b|\bBETWEEN\b|\bNOT\s+IN\b|\bIN\b|' +
             '\bSTARTING\s+WITH\b|\bSTARTING\b)';
  { Functions whose result is a property of the group, not of the row: an index cannot serve
    them and HAVING COUNT(*) > 5 is not a predicate on a column. }
  AGGREGATES = 'COUNT,SUM,AVG,MIN,MAX,LIST';
  NON_FUNCTIONS = 'IN,NOT,AND,OR,EXISTS,ANY,ALL,SOME,VALUES,SELECT,ON,WHERE,HAVING,BY,RETURNING';

function TPredicate.IsExpression: Boolean;
begin Result := Expression <> ''; end;

function TPredicate.IsLiteralEquality: Boolean;
begin Result := (Op = '=') and (Literal <> '') and (not IsExpression); end;

function IsUselessOp(const AOp: string): Boolean;
begin Result := (AOp = '<>') or (AOp = '!=') or AOp.ToUpper.StartsWith('NOT'); end;

{ Parenthesis depth at a given offset, quoted text excluded. Used to tell an ORDER BY that
  belongs to the statement from one inside a window function or a subquery. }
function DepthAt(const ASQL: string; APos: Integer): Integer;
var I: Integer;
begin
  Result := 0;
  I := 1;
  while (I < APos) and (I <= Length(ASQL)) do
  begin
    if CharInSet(ASQL[I], ['''', '"']) then
      I := SkipLiteral(ASQL, I)
    else if ASQL[I] = '(' then Inc(Result)
    else if ASQL[I] = ')' then Dec(Result);
    Inc(I);
  end;
end;

{ Scans from an opening parenthesis to the one that closes it. Returns 0 when they do not
  balance, which is the signal to stay silent: SUBSTRING(NAME FROM 1 FOR 3) is not f(a, b), and
  a matcher that counts commas mangles it. }
function MatchingParen(const ASQL: string; AOpen: Integer): Integer;
var I, Depth: Integer;
begin
  Depth := 0;
  I := AOpen;
  while I <= Length(ASQL) do
  begin
    if CharInSet(ASQL[I], ['''', '"']) then
      I := SkipLiteral(ASQL, I)
    else if ASQL[I] = '(' then Inc(Depth)
    else if ASQL[I] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then Exit(I);
    end;
    Inc(I);
  end;
  Result := 0;
end;

{ The constant on the right of an operator, or '' when there is not one. A parameter is not a
  constant, and neither is another column: both mean this predicate cannot tell us which
  population an index should be narrowed to. }
function CaptureLiteral(const ASQL: string; AFrom: Integer): string;
var M: TMatch;
begin
  M := TRegEx.Match(Copy(ASQL, AFrom, 120), '^\s*(''(?:[^'']|'''')*''|-?\d+(?:\.\d+)?)');
  if M.Success then Result := M.Groups[1].Value else Result := '';
end;

{ True when what follows the operator is a column reference rather than a constant, a parameter
  or a function call. NULL and the datetime literals are spelled like identifiers and are not. }
function RightHandIsColumn(const ASQL: string; AFrom: Integer): Boolean;
const NOT_COLUMNS = 'NULL,TRUE,FALSE,UNKNOWN,CURRENT_DATE,CURRENT_TIME,CURRENT_TIMESTAMP,' +
                    'CURRENT_USER,CURRENT_ROLE,CURRENT_CONNECTION,CURRENT_TRANSACTION,USER';
var M: TMatch;
begin
  M := TRegEx.Match(Copy(ASQL, AFrom, 120), '^\s*(?:[A-Za-z_]\w*\s*\.\s*)?([A-Za-z_]\w*)\s*(\(?)');
  Result := M.Success and (M.Groups[2].Value = '') and
            (IndexStr(M.Groups[1].Value.ToUpper, NOT_COLUMNS.Split([','])) < 0);
end;

function IdentifiersIn(const AText: string): TArray<string>;
var M: TMatch;
begin
  Result := nil;
  // An identifier followed by '(' is a function name, not a column.
  for M in TRegEx.Matches(AText, '\b([A-Za-z_]\w*)\b(?!\s*\()') do
    Result := Result + [M.Groups[1].Value.ToUpper];
end;

function ExtractPredicates(const ASQL: string): TArray<TPredicate>;
var
  M, OpM: TMatch; P: TPredicate; LClose, LAfter: Integer; LFunc, LExpr: string;
  Spans: TList<TPair<Integer, Integer>>; Span: TPair<Integer, Integer>; Inside: Boolean;
begin
  Result := nil;
  Spans := TList<TPair<Integer, Integer>>.Create;
  try
    { One function around a column: UPPER(NAME) = 'X' wants an expression index, and a plain
      index on NAME can never serve it. }
    for M in TRegEx.Matches(ASQL, '\b([A-Za-z_]\w*)\s*\(') do
    begin
      LFunc := M.Groups[1].Value.ToUpper;
      if (IndexStr(LFunc, AGGREGATES.Split([','])) >= 0) or
         (IndexStr(LFunc, NON_FUNCTIONS.Split([','])) >= 0) then Continue;
      LClose := MatchingParen(ASQL, M.Index + M.Length - 1);
      if LClose = 0 then Continue;
      LExpr := Copy(ASQL, M.Index, LClose - M.Index + 1);
      // A subquery is not an expression an index can store, and neither is COUNT(*)'s star.
      if TRegEx.IsMatch(LExpr, '\bSELECT\b', [roIgnoreCase]) or LExpr.Contains('*') then Continue;
      OpM := TRegEx.Match(Copy(ASQL, LClose + 1, 40), '^\s*' + PRED_OPS, [roIgnoreCase]);
      if not OpM.Success then Continue;
      if IsUselessOp(OpM.Groups[1].Value.ToUpper) then Continue;
      P := Default(TPredicate);
      // Verbatim, never normalised: Firebird matches an expression index only against the exact
      // expression it was defined with, and UPPER(NAME) is not UPPER(TRIM(NAME)).
      P.Expression := LExpr;
      P.Op := OpM.Groups[1].Value.ToUpper;
      LAfter := LClose + 1 + OpM.Length;
      P.Literal := CaptureLiteral(ASQL, LAfter);
      P.RightIsColumn := RightHandIsColumn(ASQL, LAfter);
      P.Idents := IdentifiersIn(Copy(LExpr, Length(LFunc) + 1, MaxInt));
      if Length(P.Idents) = 0 then Continue;
      Result := Result + [P];
      Spans.Add(TPair<Integer, Integer>.Create(M.Index, LClose));
    end;

    { A bare column. The qualifier decides which table it belongs to; unqualified, the caller
      decides by asking whether the table has such a column. }
    for M in TRegEx.Matches(ASQL, '(?:([A-Za-z_]\w*)\s*\.\s*)?\b([A-Za-z_]\w*)\s*' + PRED_OPS,
      [roIgnoreCase]) do
    begin
      Inside := False;
      for Span in Spans do
        if (M.Index >= Span.Key) and (M.Index <= Span.Value) then Inside := True;
      if Inside then Continue;
      if IsUselessOp(M.Groups[3].Value.ToUpper) then Continue;
      P := Default(TPredicate);
      P.Qualifier := M.Groups[1].Value.ToUpper;
      P.Op := M.Groups[3].Value.ToUpper;
      P.Idents := [M.Groups[2].Value.ToUpper];
      P.Literal := CaptureLiteral(ASQL, M.Index + M.Length);
      P.RightIsColumn := RightHandIsColumn(ASQL, M.Index + M.Length);
      Result := Result + [P];
    end;
  finally Spans.Free; end;
end;

function ExtractOrderBy(const ASQL: string): TArray<TSortKey>;
var
  M: TMatch; LTail, LTerm: string; I, Depth, Start: Integer; Terms: TStringList; K: TSortKey;
begin
  Result := nil;
  LTail := '';
  // The last top-level ORDER BY, so that one inside OVER (...) or a subquery is not mistaken
  // for the statement's own.
  for M in TRegEx.Matches(ASQL, '\bORDER\s+BY\b', [roIgnoreCase]) do
    if DepthAt(ASQL, M.Index) = 0 then
      LTail := Copy(ASQL, M.Index + M.Length, MaxInt);
  if LTail.Trim = '' then Exit;
  M := TRegEx.Match(LTail, '\b(ROWS|OFFSET|FETCH|FOR\s+UPDATE|INTO|UNION|PLAN)\b', [roIgnoreCase]);
  if M.Success then LTail := Copy(LTail, 1, M.Index - 1);
  LTail := LTail.Trim.TrimRight([';']);

  Terms := TStringList.Create;
  try
    Depth := 0; Start := 1;
    for I := 1 to Length(LTail) do
    begin
      if LTail[I] = '(' then Inc(Depth)
      else if LTail[I] = ')' then Dec(Depth)
      else if (LTail[I] = ',') and (Depth = 0) then
      begin
        Terms.Add(Copy(LTail, Start, I - Start));
        Start := I + 1;
      end;
    end;
    Terms.Add(Copy(LTail, Start, MaxInt));

    for I := 0 to Terms.Count - 1 do
    begin
      K := Default(TSortKey);
      LTerm := Terms[I].Trim;
      LTerm := TRegEx.Replace(LTerm, '\s+NULLS\s+(FIRST|LAST)\s*$', '', [roIgnoreCase]).Trim;
      M := TRegEx.Match(LTerm, '\s+(ASC|ASCENDING|DESC|DESCENDING)\s*$', [roIgnoreCase]);
      if M.Success then
      begin
        K.Descending := M.Groups[1].Value.ToUpper.StartsWith('DESC');
        LTerm := Copy(LTerm, 1, M.Index - 1).Trim;
      end;
      if TRegEx.IsMatch(LTerm, '^([A-Za-z_]\w*)\s*\.\s*([A-Za-z_]\w*)$') then
      begin
        K.Qualifier := Copy(LTerm, 1, Pos('.', LTerm) - 1).Trim.ToUpper;
        K.Column := Copy(LTerm, Pos('.', LTerm) + 1, MaxInt).Trim.ToUpper;
        K.Understood := True;
      end
      else if TRegEx.IsMatch(LTerm, '^[A-Za-z_]\w*$') then
      begin
        K.Column := LTerm.ToUpper;
        K.Understood := True;
      end
      else if TRegEx.IsMatch(LTerm, '^[A-Za-z_]\w*\s*\(') and
              (MatchingParen(LTerm, Pos('(', LTerm)) = Length(LTerm)) then
      begin
        // ORDER BY UPPER(NAME) is served by an expression index, by the same exact-match rule
        // that governs WHERE.
        K.Expression := LTerm;
        K.Understood := True;
      end;
      // Anything else — an ordinal (ORDER BY 2), an arithmetic term, a CASE — is recorded as
      // not understood, so the advisor refuses instead of prescribing the wrong index.
      Result := Result + [K];
    end;
  finally Terms.Free; end;
end;

function IsAggregateQuery(const ASQL: string): Boolean;
var S: string;
begin
  S := StripLiterals(ASQL);
  Result := TRegEx.IsMatch(S, '\b(' + AGGREGATES.Replace(',', '|') + ')\s*\(', [roIgnoreCase]) or
            TRegEx.IsMatch(S, '\bGROUP\s+BY\b', [roIgnoreCase]);
end;

function HasRowLimit(const ASQL: string): Boolean;
begin
  Result := TRegEx.IsMatch(StripLiterals(ASQL),
    '\b(FIRST\s+\d+|ROWS\s+\d+|FETCH\s+(FIRST|NEXT))\b', [roIgnoreCase]);
end;

{ An identifier Firebird will accept: the generated name has to survive a table and a column
  that are already long, and a function name that is not made of word characters. }
function MakeIndexName(const AParts: array of string): string;
var S, Part: string;
begin
  S := 'IDX';
  for Part in AParts do S := S + '_' + Part;
  S := TRegEx.Replace(S.ToUpper, '[^A-Z0-9_]+', '_');
  S := TRegEx.Replace(S, '_+', '_');
  if Length(S) > MAX_IDENT_LEN then S := Copy(S, 1, MAX_IDENT_LEN);
  Result := S.TrimRight(['_']);
end;

constructor TFirebirdIndexAdvisor.Create(AConn: TFirebirdConnection; const AEngineVersion: string);
begin
  inherited Create;
  FConn := AConn;
  FEngineVersion := AEngineVersion;
  FCaps := TFirebirdCapabilities.Parse(AEngineVersion);
end;

{ Alias -> table, read from the FROM/JOIN clauses, plus every table mapped to itself.

  Firebird prints the ALIAS in the legacy plan ("PLAN JOIN (C NATURAL, O INDEX (...))"), so
  without this the suggested DDL says CREATE INDEX ... ON C, and there is no table C. From 3.0
  the explained plan states the pairing itself and overrides this; on 2.5 it is all there is. }
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
    // Delphi's TRegEx drops a trailing group that did not participate, so "FROM CUSTOMERS" with
    // nothing after it has no group 2 at all.
    if M.Groups.Count > 2 then Alias := M.Groups[2].Value.ToUpper else Alias := '';
    if (Alias <> '') and (IndexStr(Alias, KEYWORDS.Split([','])) < 0) then
      Result.AddOrSetValue(Alias, Table);
  end;
end;

function TFirebirdIndexAdvisor.SuggestForQuery(const ASQL: string): TArray<TAdvisory>;
var
  PA: TFirebirdPlanAnalyzer; R: TPlanResult; Advs: TList<TAdvisory>;
  Aliases: TDictionary<string, string>; Intro: TFirebirdIntrospection;
  Audit: TFirebirdSchemaAudit; Act: TFirebirdActivity; Cost: TStatementCost;
  Preds: TArray<TPredicate>; Tables, Emitted: TStringList;
  Attributable, Measured: Boolean; Yield: Double; Reads: Int64;
  PA2: TPlanAlias; T, S: string;

  function Resolve(const AName: string): string;
  begin
    if not Aliases.TryGetValue(AName.ToUpper, Result) then Result := AName.ToUpper;
  end;

  { The measured justification every advisory carries. "The plan says NATURAL" is the symptom;
    this is the reason, and it is also what a reader needs in order to disagree with it. }
  function Evidence: string;
  begin
    if not Cost.Executed then
      Result := 'not measured (' + Cost.SkipReason + ')'
    else if not Attributable then
      Result := Format('the statement read %d records and returned %d, but those reads cannot be ' +
        'attributed to one table', [Reads, Cost.Rows])
    else
      // %.3g, not %.0f: a query that keeps one record in twenty thousand is the strongest case
      // there is for an index, and rounding it to "0%" is the one number it must not print.
      Result := Format('it read %d records to return %d (%.3g%% of what it read)',
        [Reads, Cost.Rows, Yield * 100], TFormatSettings.Invariant);
  end;

  { The one rule here that silences an advisory, so the one that has to be attacked hardest.
    It applies only where it can be attributed, only to a query whose result set is not an
    aggregate, only when nothing else in the plan (a sort, a second scan) explains the reads,
    and never to a measurement that did not happen. }
  function ScanIsRight(out AWhy: string): Boolean;
  begin
    Result := False;
    AWhy := '';
    if not Attributable then Exit;
    if Reads < SCAN_FLOOR then
    begin
      AWhy := Format('the whole table is %d records — a handful of pages. An index would change ' +
        'nothing measurable here and would still be written on every INSERT.', [Reads]);
      Exit(True);
    end;
    if Yield >= YIELD_FLOOR then
    begin
      AWhy := Format('the scan returns %.3g%% of what it reads (%d of %d records). Below roughly ' +
        '%.0f%% an index pays for itself; above it, walking the B-tree to fetch most of the table ' +
        'costs more than reading it in order — and the index still has to be maintained on every write.',
        [Yield * 100, Cost.Rows, Reads, YIELD_FLOOR * 100], TFormatSettings.Invariant);
      Exit(True);
    end;
  end;

  { An index exists over this column and the optimizer scanned anyway. Before agreeing with it,
    check the number it decided on: Firebird never refreshes selectivity by itself. }
  procedure AdviseExistingIndex(const ATable: string; const AIdx: TIndexInfo; const ACol: string);
  var Stored: Double; Stats: TColumnStats;
  begin
    Stored := Audit.StoredSelectivity(AIdx.IndexName, ACol);
    if Stored < 0 then Stored := AIdx.Selectivity;
    if Attributable and (Reads > BIG_TABLE_READS) then
    begin
      Advs.Add(TAdvisory.Make(
        Format('Index %s covers %s.%s and the optimizer scanned the table anyway (%s). Whether ' +
          'its statistics still describe the data was not verified: this table is large enough ' +
          'that counting distinct values would cost another full scan.',
          [AIdx.IndexName, ATable, ACol, Evidence]),
        Format('SET STATISTICS INDEX %s;', [AIdx.IndexName]),
        'Refreshing costs a read of the index and leaves nothing behind. Re-run fb_analyze_query ' +
        'afterwards: if the plan still scans, the optimizer is declining on current numbers.',
        'info'));
      Exit;
    end;
    Stats := Audit.ColumnStats(ATable, ACol);
    if not Stats.Comparable then
    begin
      Advs.Add(TAdvisory.Make(
        Format('Index %s covers %s.%s and the optimizer scanned the table anyway (%s). Its stored ' +
          'selectivity (%g) could not be compared with the real one: %s.',
          [AIdx.IndexName, ATable, ACol, Evidence, Stored, Stats.NotComparable],
          TFormatSettings.Invariant),
        Format('SET STATISTICS INDEX %s;', [AIdx.IndexName]),
        'Re-run fb_analyze_query afterwards and compare the plan.',
        'info'));
      Exit;
    end;
    if Abs(Stored - Stats.Selectivity) > (Stats.Selectivity * STALE_FACTOR) then
      Advs.Add(TAdvisory.Make(
        Format('Index %s covers %s.%s, but the optimizer is costing it against statistics that no ' +
          'longer describe the data: stored selectivity %g, actual %g over %d distinct values. ' +
          'Refresh the number before building anything — %s.',
          [AIdx.IndexName, ATable, ACol, Stored, Stats.Selectivity, Stats.Distinct, Evidence],
          TFormatSettings.Invariant),
        Format('SET STATISTICS INDEX %s;', [AIdx.IndexName]),
        Format('Re-run fb_analyze_query on this query. If %s is now used, nothing had to be built. ' +
          'SET STATISTICS reads the index, does not rebuild it and is safe under concurrent load — ' +
          'but it is not permanent: on a churning table it belongs in a scheduled job. It requires ' +
          'administrator, table owner or ALTER ANY TABLE.', [AIdx.IndexName]),
        'warning'))
    else
      Advs.Add(TAdvisory.Make(
        Format('Index %s covers %s.%s and its statistics are current (stored %g, actual %g). The ' +
          'optimizer weighed it on today''s numbers and chose the scan anyway — %s. This is a ' +
          'verdict about this query, not about the index.',
          [AIdx.IndexName, ATable, ACol, Stored, Stats.Selectivity, Evidence],
          TFormatSettings.Invariant),
        '',
        'Nothing to run. If you believe the index should have been used, compare the column type ' +
        'in the predicate with the column type in the table: a comparison that needs a conversion ' +
        'cannot seek.',
        'info'));
  end;

  { No index covers this column. What shape, and whether any shape is worth it. }
  procedure AdviseNewIndex(const ATable: string; const P: TPredicate; const ACol: string;
    const AFilter: TPredicate; AHasFilter: Boolean);
  var Why, Name, Extra: string;
  begin
    if ScanIsRight(Why) then
    begin
      Advs.Add(TAdvisory.Make(
        Format('Table %s is scanned when filtered by %s, and that is the right plan: %s',
          [ATable, IfThen(P.IsExpression, P.Expression, ACol), Why]),
        '',
        'Nothing to run. Re-measure with fb_analyze_query if the data distribution changes — this ' +
        'verdict is about the rows that are in the table today.',
        'info'));
      Exit;
    end;

    if P.IsExpression then
    begin
      Name := MakeIndexName([ATable, P.Expression]);
      Advs.Add(TAdvisory.Make(
        Format('Table %s is scanned when filtered by %s — %s. The predicate wraps the column in a ' +
          'function, so a plain index on %s can never serve it: the index stores the column, the ' +
          'query asks for the result of the function. This needs an expression index (Firebird 2.0+).',
          [ATable, P.Expression, Evidence, ACol]),
        Format('CREATE INDEX %s ON %s COMPUTED BY (%s);', [Name, ATable, P.Expression]),
        Format('Re-run fb_analyze_query; the plan should use %s. Firebird matches an expression ' +
          'index only when the expression in WHERE, ORDER BY or GROUP BY is *exactly* the one the ' +
          'index was defined with — %s and UPPER(TRIM(...)) are different indexes, and there is no ' +
          'multi-segment form. If the column already has a case-insensitive collation, the function ' +
          'is redundant and so is this index. Then run SET STATISTICS INDEX %s;.',
          [Name, P.Expression, Name]),
        'warning'));
      Exit;
    end;

    Name := MakeIndexName([ATable, ACol]);
    Extra := '';
    if AHasFilter then
      if FCaps.HasPartialIndexes then
        Extra := Format(' A partial index is also possible here, and is offered below: %s narrows ' +
          'the query to one population and only that population needs indexing.',
          [AFilter.Idents[0] + ' = ' + AFilter.Literal])
      else
        Extra := Format(' From Firebird 5.0 this index could be narrowed to the rows the query ' +
          'actually looks at (WHERE %s = %s), which this engine (%s) does not support.',
          [AFilter.Idents[0], AFilter.Literal, FEngineVersion]);
    Advs.Add(TAdvisory.Make(
      Format('Table %s is scanned when filtered by %s — %s. A plain B-tree index lets the ' +
        'optimizer seek instead of reading every row.%s', [ATable, ACol, Evidence, Extra]),
      Format('CREATE INDEX %s ON %s (%s);', [Name, ATable, ACol]),
      Format('Re-run fb_analyze_query on this query; the plan should use %s and no longer show ' +
        '"%s NATURAL". Then run SET STATISTICS INDEX %s; to store its selectivity — CREATE INDEX ' +
        'stores it once, and Firebird never refreshes it afterwards.', [Name, ATable, Name]),
      'warning'));

    if AHasFilter and FCaps.HasPartialIndexes then
    begin
      Name := MakeIndexName([ATable, ACol, AFilter.Idents[0]]);
      Advs.Add(TAdvisory.Make(
        Format('The same query filters %s by %s = %s. A partial index over %s indexes only those ' +
          'rows: smaller to walk, and cheaper to maintain because rows outside that population ' +
          'are never written into it.',
          [ATable, AFilter.Idents[0], AFilter.Literal, ACol]),
        Format('CREATE INDEX %s ON %s (%s) WHERE %s = %s;',
          [Name, ATable, ACol, AFilter.Idents[0], AFilter.Literal]),
        Format('Re-run fb_analyze_query; the plan should use %s. The optimizer uses a partial ' +
          'index only when the statement''s WHERE contains the same boolean expression — ' +
          'implication is not enough, so a query for a different %s value gets no help from it and ' +
          'still needs the plain index above. Build one of the two, not both, unless the other ' +
          'population is queried as often.', [Name, AFilter.Idents[0]]),
        'info'));
    end;
  end;

  procedure AdviseForTable(const ATable: string);
  var
    Cols: TStringList; Indexed, Dormant: TDictionary<string, TIndexInfo>;
    X: TIndexInfo; P, Filter: TPredicate; Col, Ident: string;
    Mine: TList<TPredicate>; Seen: TStringList; I, LiteralEqs, FilterIdx: Integer;

    function ColumnOf(const AP: TPredicate): string;
    var LId: string;
    begin
      Result := '';
      for LId in AP.Idents do
        if Cols.IndexOf(LId) >= 0 then Exit(LId);
    end;

  begin
    Filter := Default(TPredicate);
    Cols := TStringList.Create;
    Seen := TStringList.Create;
    Mine := TList<TPredicate>.Create;
    Indexed := TDictionary<string, TIndexInfo>.Create;
    Dormant := TDictionary<string, TIndexInfo>.Create;
    try
      Cols.CaseSensitive := False; Seen.CaseSensitive := False;
      for var C in Intro.GetColumns(ATable) do Cols.Add(C.FieldName);
      { An INACTIVE index cannot serve a read, so it does not make its column indexed — but it
        exists, and the fix is to switch it back on, not to build a second one beside it. Told
        only "no index on CITY", a caller creates IDX_CUSTOMERS_CITY next to the sleeping
        IDX_CUST_CITY: two indexes over one column, both written on every INSERT, one of them
        dead. Remember the name, so the advice can be the real one. }
      for X in Intro.GetIndexes(ATable) do
        if Length(X.Columns) > 0 then
          if X.Inactive then Dormant.AddOrSetValue(X.Columns[0].ToUpper, X)
          else if not Indexed.ContainsKey(X.Columns[0].ToUpper) then
            Indexed.AddOrSetValue(X.Columns[0].ToUpper, X);

      for P in Preds do
      begin
        // A qualified column belongs to the table its qualifier names, and to no other.
        if (P.Qualifier <> '') and not SameText(Resolve(P.Qualifier), ATable) then Continue;
        // Unqualified, it belongs to this table only if this table has such a column — the
        // extractor also sees the right-hand side of a join predicate and plain literals.
        if ColumnOf(P) = '' then Continue;
        Mine.Add(P);
      end;

      { The partial-index shape: one predicate pins the query to a population (STATUS =
        'ACTIVE'), another is what it then seeks by. With two literal equalities the advisor
        cannot tell which one narrows the table without measuring both, and guessing wrong
        produces an index over nearly every row that claims to be selective. Ambiguous is
        silent. }
      LiteralEqs := 0; FilterIdx := -1;
      for I := 0 to Mine.Count - 1 do
        if Mine[I].IsLiteralEquality then
        begin
          Inc(LiteralEqs);
          FilterIdx := I;
        end;
      if (LiteralEqs <> 1) or (Mine.Count < 2) then FilterIdx := -1;
      if FilterIdx >= 0 then
      begin
        Filter := Mine[FilterIdx];
        // The filter column is named in the seek column's advisory; it does not also get an
        // index of its own, which would index the population instead of seeking within it.
        Mine[FilterIdx] := Default(TPredicate);
      end;

      for I := 0 to Mine.Count - 1 do
      begin
        P := Mine[I];
        if Length(P.Idents) = 0 then Continue;
        Col := ColumnOf(P);
        if Col = '' then Continue;
        Ident := IfThen(P.IsExpression, P.Expression.ToUpper, Col);
        if Seen.IndexOf(Ident) >= 0 then Continue;
        Seen.Add(Ident);

        { The index the query wants is already there, switched off. Reactivating it rebuilds it
          from the current data — statistics included — while creating another one duplicates
          it forever. This is the lowest rung that can explain the plan, so it comes first. }
        if (not P.IsExpression) and Dormant.ContainsKey(Col) then
        begin
          X := Dormant[Col];
          Advs.Add(TAdvisory.Make(
            Format('Table %s is scanned NATURAL when filtered by %s, and index %s (%s) already covers that column — but it is INACTIVE, so the optimizer cannot use it. Do not create a second index: reactivate this one.',
              [ATable, Col, X.IndexName, Col]),
            Format('ALTER INDEX %s ACTIVE;', [X.IndexName]),
            Format('Re-run fb_analyze_query on this query; the plan should use %s and no longer show "%s NATURAL". ALTER INDEX ACTIVE rebuilds the index, so its statistics are current; run SET STATISTICS INDEX %s; later if the data shifts.', [X.IndexName, ATable, X.IndexName]),
            'warning'));
          Continue;
        end;

        if (not P.IsExpression) and Indexed.ContainsKey(Col) then
        begin
          { A join predicate over an indexed column is the optimizer choosing a driving order,
            not an index being ignored: there is nothing to say about its selectivity and no
            reason to pay a scan to find out. Only a predicate that actually filters is
            questioned. }
          if not P.RightIsColumn then AdviseExistingIndex(ATable, Indexed[Col], Col);
          Continue;
        end;

        AdviseNewIndex(ATable, P, Col, Filter, FilterIdx >= 0);
      end;
    finally
      Indexed.Free; Dormant.Free; Mine.Free; Seen.Free; Cols.Free;
    end;
  end;

  { An index for the sort, which nothing here has ever suggested: the predicate extractor only
    ever looked at comparison operators, so ORDER BY was invisible to it. }
  procedure AdviseForSort;
  var
    Keys: TArray<TSortKey>; K: TSortKey; LTable, LCols, Name, LWarn: string;
    Descending, Mixed: Boolean; Cols: TStringList; X: TIndexInfo; I: Integer;
  begin
    Keys := ExtractOrderBy(ASQL);
    if Length(Keys) = 0 then Exit;
    for K in Keys do
      if not K.Understood then
      begin
        Advs.Add(TAdvisory.Make(
          'The plan sorts, but the ORDER BY could not be read as a list of columns (an ordinal ' +
          'position, an arithmetic term or a CASE). No index is suggested for it rather than one ' +
          'that would not be used.', '',
          'Rewrite the ORDER BY naming the columns and re-run fb_suggest_indexes.', 'info'));
        Exit;
      end;

    { Direction is part of the index. Firebird cannot walk an ascending index backwards, and no
      single index serves ORDER BY a ASC, b DESC — the advisor says so instead of prescribing
      one that will not be used. }
    Descending := Keys[0].Descending;
    Mixed := False;
    for K in Keys do if K.Descending <> Descending then Mixed := True;
    if Mixed then
    begin
      Advs.Add(TAdvisory.Make(
        'The plan sorts, and the ORDER BY mixes ascending and descending directions. One Firebird ' +
        'index is entirely ASCENDING or entirely DESCENDING and the engine cannot read either one ' +
        'backwards, so no single index can serve this sort. The sort stays.', '',
        'If this query matters, the alternatives are to make the directions agree, or to store a ' +
        'computed column that inverts one of them and index that.', 'info'));
      Exit;
    end;

    { Which table the sort belongs to. Qualified, the alias says so; unqualified, only a
      single-table query can answer without guessing — and a query that sorts need not scan, so
      the FROM clause has to answer when the plan reports no scan at all. }
    LTable := '';
    for K in Keys do
      if K.Qualifier <> '' then LTable := Resolve(K.Qualifier);
    if (LTable = '') and (Tables.Count = 1) then LTable := Tables[0];
    if LTable = '' then
    begin
      for var Pair in Aliases do
        if LTable = '' then LTable := Pair.Value
        else if not SameText(LTable, Pair.Value) then Exit;  // more than one table: no guessing
    end;
    if LTable = '' then Exit;

    Cols := TStringList.Create;
    try
      Cols.CaseSensitive := False;
      for var C in Intro.GetColumns(LTable) do Cols.Add(C.FieldName);

      if (Length(Keys) = 1) and (Keys[0].Expression <> '') then
      begin
        Name := MakeIndexName([LTable, Keys[0].Expression]);
        Advs.Add(TAdvisory.Make(
          Format('The plan sorts %s externally for ORDER BY %s. Firebird applies the same ' +
            'exact-match rule to ORDER BY as to WHERE, so an expression index on that exact ' +
            'expression can remove the sort.', [LTable, Keys[0].Expression]),
          Format('CREATE %sINDEX %s ON %s COMPUTED BY (%s);',
            [IfThen(Descending, 'DESCENDING ', ''), Name, LTable, Keys[0].Expression]),
          'Re-run fb_analyze_query; the plan should no longer contain SORT. The expression must ' +
          'appear in the query exactly as written here.', 'info'));
        Exit;
      end;

      LCols := '';
      for K in Keys do
      begin
        if K.Column = '' then Exit;               // an expression among several keys: refuse
        if Cols.IndexOf(K.Column) < 0 then Exit;  // not this table's sort after all
        if LCols <> '' then LCols := LCols + ', ';
        LCols := LCols + K.Column;
      end;

      // An index whose leading segments already are these columns, in this direction, would
      // have been used; if one exists, the sort has another cause and no advice is honest.
      for X in Intro.GetIndexes(LTable) do
        if (not X.Inactive) and (X.Descending = Descending) and (Length(X.Columns) >= Length(Keys)) then
        begin
          I := 0;
          while (I < Length(Keys)) and SameText(X.Columns[I], Keys[I].Column) do Inc(I);
          if I = Length(Keys) then Exit;
        end;

      { Removing a sort is not automatically a win: a navigational plan fetches rows in index
        order, which is random page access, and on a query that returns most of the table
        scan-then-sort beats it. The yield reasoning of the WHERE rules, inverted. }
      LWarn := '';
      if HasRowLimit(ASQL) then
        LWarn := ' This query returns only the first rows, which is where the win is largest: ' +
          'without an index the engine sorts the entire result set to hand back a screenful.'
      else if Measured and (Yield >= YIELD_FLOOR) then
        LWarn := Format(' Weigh it first: this query keeps %.3g%% of what it reads, and reading ' +
          'most of a table through an index means random page access. Scan-then-sort can be the ' +
          'faster plan even though it says SORT.', [Yield * 100], TFormatSettings.Invariant);

      Name := MakeIndexName([LTable, LCols, IfThen(Descending, 'DESC', '')]);
      Advs.Add(TAdvisory.Make(
        Format('The plan sorts %s externally for ORDER BY %s%s. An index whose segments are those ' +
          'columns in that order, in that direction, lets the engine walk the data already ' +
          'ordered and removes the sort.%s',
          [LTable, LCols, IfThen(Descending, ' DESC', ''), LWarn]),
        Format('CREATE %sINDEX %s ON %s (%s);',
          [IfThen(Descending, 'DESCENDING ', ''), Name, LTable, LCols]),
        'Re-run fb_analyze_query; the plan should no longer contain SORT. Compare the measured ' +
        'time before and after — an index that removes a sort is not automatically faster.',
        'info'));
    finally Cols.Free; end;
  end;

  { What the explained plan knows and the SQL text cannot: how much of an index the query
    actually agreed with, and whether a join had any usable index at all. }
  procedure AdviseFromExplainedPlan;
  begin
    for var Use in R.IndexUse do
      if (Use.SegmentsTotal > 1) and (Use.SegmentsUsed > 0) and (Use.SegmentsUsed < Use.SegmentsTotal) then
        Advs.Add(TAdvisory.Make(
          Format('The query uses %d of the %d segments of index %s. The remaining segments are ' +
            'maintained on every write and contribute nothing to this query: a composite index ' +
            'can only be seeked from its leading segments inwards, and this one stops early.',
            [Use.SegmentsUsed, Use.SegmentsTotal, Use.IndexName]),
          '',
          Format('If this query is why %s is composite, fb_suggest_index_drops on the table will ' +
            'say whether a narrower index would serve every other query too. Check the predicate ' +
            'on the segment that stopped it: a range, a function or a type conversion there ends ' +
            'the seek.', [Use.IndexName]),
          'info'));

    if R.HasJoin and (R.FullScans >= 2) then
      Advs.Add(TAdvisory.Make(
        Format('The plan joins %d fully scanned tables (%s). Neither side of the join could be ' +
          'reached through an index, so the engine reads both in full and matches them in memory. ' +
          'On small tables that is the right plan; it is also exactly how a join degrades as the ' +
          'tables grow.', [R.FullScans, string.Join(', ', R.ScannedTables)]),
        '',
        'Index the join key on the side that is filtered least, then re-run fb_analyze_query: the ' +
        'plan should reach that table through the index instead of scanning it.',
        'info'));
  end;

begin
  Advs := TList<TAdvisory>.Create;
  Aliases := AliasMap(ASQL);
  Tables := TStringList.Create;
  Emitted := TStringList.Create;
  Intro := TFirebirdIntrospection.Create(FConn);
  Audit := TFirebirdSchemaAudit.Create(FConn);
  try
    Tables.CaseSensitive := False;
    Emitted.CaseSensitive := False;
    PA := TFirebirdPlanAnalyzer.Create(FConn, FEngineVersion);
    try R := PA.Analyze(ASQL); finally PA.Free; end;
    if not (R.HasNaturalScan or R.HasExternalSort) then Exit(nil);

    // The engine's own alias map, where there is one, over the regex reading of the FROM clause.
    for PA2 in R.Aliases do Aliases.AddOrSetValue(PA2.Alias, PA2.Table);

    { The explained plan names the tables it scanned; the legacy plan names whatever the query
      called them. Prefer the first, fall back to the second — which is all 2.5 has. }
    if Length(R.ScannedTables) > 0 then
      for S in R.ScannedTables do
      begin
        if Tables.IndexOf(S) < 0 then Tables.Add(S);
      end
    else
      for S in R.NaturalTables do
      begin
        T := Resolve(S);
        if Tables.IndexOf(T) < 0 then Tables.Add(T);
      end;

    Preds := ExtractPredicates(ASQL);

    { Executing the query is what turns "the plan scans" into "the scan is worth fixing". It
      happens only once there is something to advise on, and it goes through Measure, so the
      read-only transaction and the refusal to run anything that is not a plain SELECT both
      apply — as does the refusal to measure a statement whose parameters nobody bound. }
    Act := TFirebirdActivity.Create(FConn, FCaps);
    try Cost := Act.Measure(ASQL); finally Act.Free; end;
    Reads := Cost.Delta.RecordReads;
    { Attribution, not measurement, is what the yield rule needs. Measure counts the records of
      the whole statement: with two scanned tables the reads belong to neither, with a sort the
      index earns its place by removing the sort rather than by reading less, and an aggregate
      returns one row out of thousands by construction. }
    Measured := Cost.Executed and (Tables.Count = 1) and (Reads > 0) and (not IsAggregateQuery(ASQL));
    Attributable := Measured and (not R.HasExternalSort);
    if Reads > 0 then Yield := Cost.Rows / Reads else Yield := 0;

    if R.ExplainedPlan <> '' then AdviseFromExplainedPlan;
    if R.HasNaturalScan then
      for T in Tables do AdviseForTable(T);
    if R.HasExternalSort then AdviseForSort;

    { One index can be the answer to two questions — a query that filters and orders by the same
      column reaches the same CREATE INDEX from the predicate rules and from the sort rules. Two
      identical statements read as two indexes to build. }
    for var Adv in Advs do
      if (Adv.SQLText = '') or (Emitted.IndexOf(Adv.SQLText) < 0) then
      begin
        if Adv.SQLText <> '' then Emitted.Add(Adv.SQLText);
        Result := Result + [Adv];
      end;
  finally Advs.Free; Aliases.Free; Tables.Free; Emitted.Free; Intro.Free; Audit.Free; end;
end;

function TFirebirdIndexAdvisor.SuggestDropsForTable(const ATable: string): TArray<TAdvisory>;
var Intro: TFirebirdIntrospection; Audit: TFirebirdSchemaAudit; Idx: TArray<TIndexInfo>;
    I, J: Integer; Advs: TList<TAdvisory>; Stats: TColumnStats;
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
  Audit := TFirebirdSchemaAudit.Create(FConn);
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
      { A poor selectivity that was never refreshed is not a poor index — it is an unanswered
        question, and the answer to it costs a read of the index instead of a permanent
        structural change. No index is called useless on a number nobody has checked. }
      if (not Idx[I].IsSystem) and (not Idx[I].Inactive) and (Idx[I].Selectivity > 0.5) and
         (Length(Idx[I].Columns) > 0) then
      begin
        Stats := Audit.ColumnStats(ATable, Idx[I].Columns[0]);
        if Stats.Comparable and (Stats.Selectivity <= 0.5) then
          Advs.Add(TAdvisory.Make(
            Format('Index %s looks unselective (stored %.3f), but its statistics are stale: the ' +
              'column really holds %d distinct values (selectivity %g). Refresh the number before ' +
              'judging the index — the optimizer is also using the stale one.',
              [Idx[I].IndexName, Idx[I].Selectivity, Stats.Distinct, Stats.Selectivity],
              TFormatSettings.Invariant),
            Format('SET STATISTICS INDEX %s;', [Idx[I].IndexName]),
            'Re-run fb_suggest_index_drops afterwards; this finding should be gone.',
            'warning'))
        else
          Advs.Add(TAdvisory.Make(
            Format('Index %s has poor selectivity (stored %.3f, actual %g, 1.0 = all rows identical). It rarely helps the optimizer.',
              [Idx[I].IndexName, Idx[I].Selectivity, Stats.Selectivity], TFormatSettings.Invariant),
            Format('-- Review usage before dropping:%sDROP INDEX %s;', [sLineBreak, Idx[I].IndexName]),
            'Confirm no query relies on it — a low-selectivity index can still be the cheapest way to reach a rare value.',
            'info'));
      end;
    end;
    Result := Advs.ToArray;
  finally
    Intro.Free; Audit.Free; Advs.Free;
  end;
end;
end.
