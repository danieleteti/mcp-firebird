unit Test.Firebird.IndexAdvisor;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TIndexAdvisorTests = class
  public
    [Test] procedure SuggestIndexes_ForCityQuery_ReactivatesDormantIndex;
  end;
implementation
uses System.SysUtils, Firebird.Connection, Firebird.Capabilities, Firebird.IndexAdvisor, Firebird.Advisory, TestFixtureU;

procedure TIndexAdvisorTests.SuggestIndexes_ForCityQuery_ReactivatesDormantIndex;
var Conn: TFirebirdConnection; A: TFirebirdIndexAdvisor; Advs: TArray<TAdvisory>; X: TAdvisory; FoundAlter, FoundCreate: Boolean;
begin
  // The seed leaves IDX_CUST_CITY INACTIVE on purpose: the right answer is to wake it,
  // not to prescribe a second index over the same column.
  Conn := NewTestConnection;
  try
    A := TFirebirdIndexAdvisor.Create(Conn, TFirebirdCapabilities.Detect(Conn).EngineVersion);
    try
      Advs := A.SuggestForQuery('SELECT * FROM CUSTOMERS WHERE CITY = ''Rome''');
      FoundAlter := False;
      FoundCreate := False;
      for X in Advs do
      begin
        if X.SQLText.ToUpper.Contains('ALTER INDEX IDX_CUST_CITY ACTIVE') then FoundAlter := True;
        if X.SQLText.ToUpper.Contains('CREATE INDEX') and X.SQLText.ToUpper.Contains('ON CUSTOMERS') and X.SQLText.ToUpper.Contains('CITY') then FoundCreate := True;
      end;
      Assert.IsTrue(FoundAlter, 'proposes ALTER INDEX IDX_CUST_CITY ACTIVE');
      Assert.IsFalse(FoundCreate, 'does not prescribe a second index over CITY');
    finally
      A.Free;
    end;
  finally
    Conn.Free;
  end;
end;
end.
