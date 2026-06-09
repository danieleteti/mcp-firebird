unit Test.Firebird.IndexDrops;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TIndexDropTests = class
  public
    [Test] procedure Flags_DuplicateOfSystemFkIndex;
    [Test] procedure Flags_RedundantLeftPrefix;
    [Test] procedure Flags_InactiveIndex;
  end;
implementation
uses System.SysUtils, Firebird.Connection, Firebird.Capabilities, Firebird.IndexAdvisor, Firebird.Advisory, TestFixtureU;

function AnyMentions(const Advs: TArray<TAdvisory>; const AName: string): Boolean;
var X: TAdvisory;
begin
  Result := False;
  for X in Advs do
    if X.SQLText.ToUpper.Contains(AName.ToUpper) or X.Finding.ToUpper.Contains(AName.ToUpper) then Exit(True);
end;

function DropsExactly(const Advs: TArray<TAdvisory>; const AName: string): Boolean;
var X: TAdvisory;
begin
  Result := False;
  for X in Advs do
    if X.SQLText.ToUpper.Contains('DROP INDEX ' + AName.ToUpper + ';') then Exit(True);
end;

procedure TIndexDropTests.Flags_DuplicateOfSystemFkIndex;
var Conn: TFirebirdConnection; A: TFirebirdIndexAdvisor;
begin
  Conn := NewTestConnection;
  try A := TFirebirdIndexAdvisor.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try Assert.IsTrue(AnyMentions(A.SuggestDropsForTable('ORDERS'), 'IDX_ORDERS_CUSTOMER_DUP'));
    finally A.Free; end;
  finally Conn.Free; end;
end;

procedure TIndexDropTests.Flags_RedundantLeftPrefix;
var Conn: TFirebirdConnection; A: TFirebirdIndexAdvisor;
begin
  Conn := NewTestConnection;
  try A := TFirebirdIndexAdvisor.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try Assert.IsTrue(DropsExactly(A.SuggestDropsForTable('CUSTOMERS'), 'IDX_CUST_NAME'),
          'flags IDX_CUST_NAME as redundant left-prefix of IDX_CUST_NAME_CITY');
    finally A.Free; end;
  finally Conn.Free; end;
end;

procedure TIndexDropTests.Flags_InactiveIndex;
var Conn: TFirebirdConnection; A: TFirebirdIndexAdvisor;
begin
  Conn := NewTestConnection;
  try A := TFirebirdIndexAdvisor.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try Assert.IsTrue(AnyMentions(A.SuggestDropsForTable('CUSTOMERS'), 'IDX_CUST_CITY'));
    finally A.Free; end;
  finally Conn.Free; end;
end;
end.
