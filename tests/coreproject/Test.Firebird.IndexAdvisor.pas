unit Test.Firebird.IndexAdvisor;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TIndexAdvisorTests = class
  public
    [Test] procedure SuggestIndexes_ForCityQuery_ProposesCityIndex;
  end;
implementation
uses System.SysUtils, Firebird.Connection, Firebird.Capabilities, Firebird.IndexAdvisor, Firebird.Advisory, TestFixtureU;

procedure TIndexAdvisorTests.SuggestIndexes_ForCityQuery_ProposesCityIndex;
var Conn: TFirebirdConnection; A: TFirebirdIndexAdvisor; Advs: TArray<TAdvisory>; X: TAdvisory; Found: Boolean;
begin
  Conn := NewTestConnection;
  try
    A := TFirebirdIndexAdvisor.Create(Conn, TFirebirdCapabilities.Detect(Conn));
    try
      Advs := A.SuggestForQuery('SELECT * FROM CUSTOMERS WHERE CITY = ''Rome''');
      Found := False;
      for X in Advs do
        if X.SQLText.ToUpper.Contains('ON CUSTOMERS') and X.SQLText.ToUpper.Contains('CITY') then Found := True;
      Assert.IsTrue(Found, 'proposes CREATE INDEX ... ON CUSTOMERS (CITY)');
    finally A.Free; end;
  finally Conn.Free; end;
end;
end.
