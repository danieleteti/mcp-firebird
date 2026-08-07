unit Test.Firebird.IndexAdvisor;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TIndexAdvisorTests = class
  public
    [Test] procedure SuggestIndexes_ForCityQuery_ReactivatesDormantIndex;
    [Test] procedure AScanThatKeepsMostOfWhatItReads_IsTheRightPlan;
    [Test] procedure AScanThatKeepsAlmostNothing_GetsAnIndex;
    [Test] procedure AFunctionAroundTheColumn_GetsAnExpressionIndex;
    [Test] procedure AFunctionAroundTheConstant_GetsAPlainIndex;
    [Test] procedure ALiteralNarrowedQuery_IndexesWhatItSeeksBy;
    [Test] procedure AnUnboundParameter_IsNotMeasured;
    [Test] procedure AnExternalSort_GetsAnIndexInItsOwnDirection;
    [Test] procedure MixedSortDirections_AreRefusedWithTheReason;
    [Test] procedure AnIndexedColumnThePlanScans_GetsStatisticsBeforeAnyNewIndex;
    [Test] procedure AJoinKeyThatIsAlreadyIndexed_IsNotAdvisedOn;
    // Pure text, no database: the part of the advisor most likely to be quietly wrong.
    [Test] procedure Extractor_KeepsTheExpressionVerbatimAndBalanced;
    [Test] procedure Extractor_IgnoresNonSargableComparisons;
    [Test] procedure Extractor_ReadsOrderByDirectionAndRefusesOrdinals;
  end;
implementation
uses
  System.SysUtils, System.StrUtils, Firebird.Connection, Firebird.Capabilities,
  Firebird.IndexAdvisor, Firebird.Advisory, TestFixtureU;

function Advise(const ASQL: string): TArray<TAdvisory>;
var Conn: TFirebirdConnection; A: TFirebirdIndexAdvisor;
begin
  Conn := NewTestConnection;
  try
    A := TFirebirdIndexAdvisor.Create(Conn, TFirebirdCapabilities.Detect(Conn).EngineVersion);
    try Result := A.SuggestForQuery(ASQL); finally A.Free; end;
  finally Conn.Free; end;
end;

function EngineOrdinal: Integer;
var Conn: TFirebirdConnection;
begin
  Conn := NewTestConnection;
  try Result := TFirebirdCapabilities.Detect(Conn).Ordinal; finally Conn.Free; end;
end;

function AnySQL(const Advs: TArray<TAdvisory>; const ANeedle: string): Boolean;
var X: TAdvisory;
begin
  Result := False;
  for X in Advs do
    if X.SQLText.ToUpper.Contains(ANeedle.ToUpper) then Exit(True);
end;

function AnyText(const Advs: TArray<TAdvisory>; const ANeedle: string): Boolean;
var X: TAdvisory;
begin
  Result := False;
  for X in Advs do
    if X.Finding.ToUpper.Contains(ANeedle.ToUpper) or X.Verify.ToUpper.Contains(ANeedle.ToUpper) then
      Exit(True);
end;

function Dump(const Advs: TArray<TAdvisory>): string;
var X: TAdvisory;
begin
  Result := '';
  for X in Advs do Result := Result + sLineBreak + '[' + X.Severity + '] ' + X.Finding +
    sLineBreak + '   SQL: ' + X.SQLText;
  if Result = '' then Result := ' (no advisories)';
end;

procedure TIndexAdvisorTests.SuggestIndexes_ForCityQuery_ReactivatesDormantIndex;
var Advs: TArray<TAdvisory>;
begin
  // The seed leaves IDX_CUST_CITY INACTIVE on purpose: the right answer is to wake it,
  // not to prescribe a second index over the same column.
  Advs := Advise('SELECT * FROM CUSTOMERS WHERE CITY = ''Rome''');
  Assert.IsTrue(AnySQL(Advs, 'ALTER INDEX IDX_CUST_CITY ACTIVE'),
    'proposes ALTER INDEX IDX_CUST_CITY ACTIVE.' + Dump(Advs));
  Assert.IsFalse(AnySQL(Advs, 'CREATE INDEX'),
    'does not prescribe a second index over CITY.' + Dump(Advs));
end;

procedure TIndexAdvisorTests.AScanThatKeepsMostOfWhatItReads_IsTheRightPlan;
var Advs: TArray<TAdvisory>;
begin
  { 90% of SKEWED is 'CLOSED'. The scan reads the table and keeps nearly all of it, which is
    what a scan is for: an index here would be written on every INSERT and would change
    nothing. This is the one rule in the advisor that stays silent, so it is the one that has
    to be tested from both sides. }
  Advs := Advise('SELECT * FROM SKEWED WHERE STATE = ''CLOSED''');
  Assert.IsFalse(AnySQL(Advs, 'CREATE INDEX'),
    'a scan that returns most of what it reads must not be answered with an index.' + Dump(Advs));
  Assert.IsTrue(AnyText(Advs, 'right plan'),
    'and it must say so, with the numbers it said it about.' + Dump(Advs));
end;

procedure TIndexAdvisorTests.AScanThatKeepsAlmostNothing_GetsAnIndex;
var Advs: TArray<TAdvisory>;
begin
  // The same table, the other side of the rule: TAG holds 200 values over 20 000 rows.
  Advs := Advise('SELECT * FROM SKEWED WHERE TAG = ''T42''');
  Assert.IsTrue(AnySQL(Advs, 'CREATE INDEX') and AnySQL(Advs, '(TAG)'),
    'a scan that throws away 99% of what it reads earns an index.' + Dump(Advs));
end;

procedure TIndexAdvisorTests.AFunctionAroundTheColumn_GetsAnExpressionIndex;
var Advs: TArray<TAdvisory>;
begin
  // A plain index on LABEL can never serve UPPER(LABEL): the index stores the column, the
  // query asks for the result of the function.
  Advs := Advise('SELECT * FROM SKEWED WHERE UPPER(LABEL) = ''LABEL_1''');
  Assert.IsTrue(AnySQL(Advs, 'COMPUTED BY (UPPER(LABEL))'),
    'expression predicate -> expression index, with the expression verbatim.' + Dump(Advs));
end;

procedure TIndexAdvisorTests.AFunctionAroundTheConstant_GetsAPlainIndex;
var Advs: TArray<TAdvisory>;
begin
  // The mirror image, and the reason the extractor has to care which side it matched.
  Advs := Advise('SELECT * FROM SKEWED WHERE LABEL = UPPER(''label_1'')');
  Assert.IsTrue(AnySQL(Advs, 'CREATE INDEX') and AnySQL(Advs, '(LABEL)'),
    'a function around the constant leaves the column plain.' + Dump(Advs));
  Assert.IsFalse(AnySQL(Advs, 'COMPUTED BY'),
    'and must not prescribe an expression index for it.' + Dump(Advs));
end;

procedure TIndexAdvisorTests.ALiteralNarrowedQuery_IndexesWhatItSeeksBy;
var Advs: TArray<TAdvisory>;
begin
  { STATE = 'ACTIVE' pins the query to a tenth of the table; TAG is what it then seeks by. The
    index goes on TAG. STATE does not get one of its own: an index over the population is not
    the same as seeking within it. From 5.0 the two can be one index. }
  Advs := Advise('SELECT * FROM SKEWED WHERE STATE = ''ACTIVE'' AND TAG = ?');
  Assert.IsTrue(AnySQL(Advs, '(TAG)'), 'indexes the column it seeks by.' + Dump(Advs));
  Assert.IsFalse(AnySQL(Advs, 'ON SKEWED (STATE)'),
    'and not the one that only narrows the population.' + Dump(Advs));
  if EngineOrdinal >= 500 then
    Assert.IsTrue(AnySQL(Advs, 'WHERE STATE = ''ACTIVE'''),
      '5.0 can narrow the index itself, and should offer it.' + Dump(Advs))
  else
  begin
    Assert.IsFalse(AnySQL(Advs, 'CREATE INDEX IDX_SKEWED_TAG_STATE'),
      'below 5.0 a partial index does not exist and must not be prescribed.' + Dump(Advs));
    Assert.IsTrue(AnyText(Advs, 'Firebird 5.0'),
      'but the reader deserves to know what 5.0 would allow.' + Dump(Advs));
  end;
end;

procedure TIndexAdvisorTests.AnUnboundParameter_IsNotMeasured;
var Advs: TArray<TAdvisory>;
begin
  { FireDAC binds an unset parameter as NULL, so executing this statement compares every row
    against NULL and returns none: a yield of zero over a full table, which reads as the
    strongest possible case for an index and describes a query nobody runs. }
  Advs := Advise('SELECT * FROM SKEWED WHERE TAG = ?');
  Assert.IsTrue(AnyText(Advs, 'not measured'),
    'the advisory must say the numbers are missing, not invent them.' + Dump(Advs));
  Assert.IsFalse(AnyText(Advs, 'to return 0'),
    'and must never quote a row count taken from an unbound execution.' + Dump(Advs));
end;

procedure TIndexAdvisorTests.AnExternalSort_GetsAnIndexInItsOwnDirection;
var Advs: TArray<TAdvisory>;
begin
  { fb_suggest_indexes has flagged external sorts since M1 and never once suggested an index
    for one: its extractor only ever looked at comparison operators. }
  Advs := Advise('SELECT * FROM SKEWED ORDER BY TAG');
  Assert.IsTrue(AnySQL(Advs, 'CREATE INDEX') and AnySQL(Advs, '(TAG)'),
    'an external sort on an unindexed column earns an index.' + Dump(Advs));

  { Direction is part of the index: Firebird cannot walk an ascending index backwards. }
  Advs := Advise('SELECT * FROM SKEWED ORDER BY TAG DESC');
  Assert.IsTrue(AnySQL(Advs, 'CREATE DESCENDING INDEX'),
    'ORDER BY ... DESC needs a DESCENDING index, not the ascending one.' + Dump(Advs));
end;

procedure TIndexAdvisorTests.MixedSortDirections_AreRefusedWithTheReason;
var Advs: TArray<TAdvisory>;
begin
  // No single Firebird index serves ORDER BY a ASC, b DESC. Saying so beats prescribing one
  // that the optimizer will not use.
  Advs := Advise('SELECT * FROM SKEWED ORDER BY TAG ASC, LABEL DESC');
  Assert.IsFalse(AnySQL(Advs, 'CREATE'),
    'no index can serve a mixed-direction sort, so none is prescribed.' + Dump(Advs));
  Assert.IsTrue(AnyText(Advs, 'descending'),
    'and the reason is stated.' + Dump(Advs));
end;

procedure TIndexAdvisorTests.AnIndexedColumnThePlanScans_GetsStatisticsBeforeAnyNewIndex;
var Advs: TArray<TAdvisory>;
begin
  { A leading wildcard cannot be seeked, so the plan scans CUSTOMERS even though NAME carries
    IDX_CUST_NAME. Nothing may conclude "the index is not used, and that is correct" before the
    number the optimizer decided on has been compared with the real one — Firebird never
    refreshes selectivity by itself, and the seed builds its indexes before it loads its rows.
    The answer is SET STATISTICS, which leaves nothing behind; never a second index over a
    column that already has one, which is paid for on every INSERT forever. }
  Advs := Advise('SELECT * FROM CUSTOMERS WHERE NAME LIKE ''%CUST_1''');
  Assert.IsTrue(AnySQL(Advs, 'SET STATISTICS INDEX IDX_CUST_NAME'),
    'the lowest rung that explains the plan comes first.' + Dump(Advs));
  Assert.IsFalse(AnySQL(Advs, 'CREATE INDEX'),
    'and never a second index over an already-indexed column.' + Dump(Advs));
end;

procedure TIndexAdvisorTests.AJoinKeyThatIsAlreadyIndexed_IsNotAdvisedOn;
var Advs: TArray<TAdvisory>;
begin
  { The hash join scans ORDERS, whose join key already carries an index: that is the optimizer
    choosing a driving order, not an index being ignored. There is nothing to say about it, and
    no reason to pay a COUNT(DISTINCT) scan to find that out. }
  Advs := Advise('SELECT C.NAME, O.TOTAL FROM CUSTOMERS C JOIN ORDERS O ' +
                 'ON O.CUSTOMER_ID = C.CUSTOMER_ID WHERE C.STATUS = ''A''');
  Assert.IsFalse(AnySQL(Advs, 'ON ORDERS'),
    'an indexed join key on the scanned side is not a finding.' + Dump(Advs));
end;

procedure TIndexAdvisorTests.Extractor_KeepsTheExpressionVerbatimAndBalanced;
var P: TArray<TPredicate>;
begin
  { SUBSTRING(NAME FROM 1 FOR 3) is not f(a, b): a matcher that counts commas mangles it, and
    an expression index Firebird will not match is worse than no advice. }
  P := ExtractPredicates('SELECT * FROM T WHERE SUBSTRING(NAME FROM 1 FOR 3) = ''ABC''');
  Assert.IsTrue(Length(P) = 1, 'one predicate, got ' + Length(P).ToString);
  Assert.AreEqual('SUBSTRING(NAME FROM 1 FOR 3)', P[0].Expression, 'captured whole and verbatim');
  Assert.AreEqual('''ABC''', P[0].Literal);

  // The function is around the constant here, so the column is plain.
  P := ExtractPredicates('SELECT * FROM T WHERE NAME = UPPER(''x'')');
  Assert.IsTrue(Length(P) = 1, 'one predicate, got ' + Length(P).ToString);
  Assert.AreEqual('', P[0].Expression, 'a function on the right does not make an expression predicate');
  Assert.AreEqual('NAME', P[0].Idents[0]);

  // An aggregate is a property of the group, and a subquery is not an expression to index.
  P := ExtractPredicates('SELECT X FROM T GROUP BY X HAVING COUNT(*) > 5');
  Assert.IsTrue(Length(P) = 0, 'HAVING COUNT(*) is not an indexable predicate');
end;

procedure TIndexAdvisorTests.Extractor_IgnoresNonSargableComparisons;
var P: TArray<TPredicate>;
begin
  // An alternation that stops at '<' reads `A <> 5` as a range predicate and prescribes an
  // index for a comparison no index can serve.
  P := ExtractPredicates('SELECT * FROM T WHERE A <> 5 AND B != 6 AND C NOT IN (1,2)');
  Assert.IsTrue(Length(P) = 0, 'nothing here can be seeked. Got ' + Length(P).ToString);

  P := ExtractPredicates('SELECT * FROM T WHERE C.CITY = ''Rome''');
  Assert.IsTrue(Length(P) = 1, 'one predicate, got ' + Length(P).ToString);
  Assert.AreEqual('C', P[0].Qualifier);
  Assert.AreEqual('CITY', P[0].Idents[0]);
  Assert.IsTrue(P[0].IsLiteralEquality, 'a column compared with a constant');

  P := ExtractPredicates('SELECT * FROM A JOIN B ON B.AID = A.ID');
  Assert.IsTrue(Length(P) = 1, 'one predicate, got ' + Length(P).ToString);
  Assert.IsTrue(P[0].RightIsColumn, 'a join predicate is not a filter');
end;

procedure TIndexAdvisorTests.Extractor_ReadsOrderByDirectionAndRefusesOrdinals;
var K: TArray<TSortKey>;
begin
  K := ExtractOrderBy('SELECT * FROM T ORDER BY A, B DESC');
  Assert.IsTrue(Length(K) = 2, 'two sort keys, got ' + Length(K).ToString);
  Assert.AreEqual('A', K[0].Column);
  Assert.IsFalse(K[0].Descending);
  Assert.IsTrue(K[1].Descending, 'DESC belongs to the key it follows');

  K := ExtractOrderBy('SELECT * FROM T ORDER BY 2 DESC');
  Assert.IsTrue(Length(K) = 1, 'one sort key, got ' + Length(K).ToString);
  Assert.IsFalse(K[0].Understood, 'an ordinal position names no column to index');

  K := ExtractOrderBy('SELECT * FROM T ORDER BY UPPER(NAME) NULLS LAST');
  Assert.IsTrue(Length(K) = 1, 'one sort key, got ' + Length(K).ToString);
  Assert.AreEqual('UPPER(NAME)', K[0].Expression, 'ORDER BY takes expression indexes too');

  // ORDER BY inside a window function is not the statement's own.
  K := ExtractOrderBy('SELECT ROW_NUMBER() OVER (ORDER BY A) FROM T');
  Assert.IsTrue(Length(K) = 0, 'a windowed ORDER BY is not the statement''s sort');
end;
end.
