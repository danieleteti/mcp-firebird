unit Test.Firebird.DocGen;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TDocGenTests = class
  public
    [Test] procedure TableDoc_Customers_HasHeadingAndColumns;
    [Test] procedure DatabaseDoc_ListsBothTables;
  end;
implementation
uses System.SysUtils, Firebird.Connection, Firebird.Introspection, Firebird.DocGen, TestFixtureU;

procedure TDocGenTests.TableDoc_Customers_HasHeadingAndColumns;
var Conn: TFirebirdConnection; D: TFirebirdDocGen; MD: string;
begin
  Conn := NewTestConnection;
  try
    D := TFirebirdDocGen.Create(TFirebirdIntrospection.Create(Conn));
    try
      MD := D.TableMarkdown('CUSTOMERS');
      Assert.Contains(MD, '## CUSTOMERS');
      Assert.Contains(MD, 'CITY');
      Assert.Contains(MD, 'CUSTOMER_ID');
    finally D.Free; end;
  finally Conn.Free; end;
end;

procedure TDocGenTests.DatabaseDoc_ListsBothTables;
var Conn: TFirebirdConnection; D: TFirebirdDocGen; MD: string;
begin
  Conn := NewTestConnection;
  try
    D := TFirebirdDocGen.Create(TFirebirdIntrospection.Create(Conn));
    try
      MD := D.DatabaseMarkdown;
      Assert.Contains(MD, 'CUSTOMERS');
      Assert.Contains(MD, 'ORDERS');
    finally D.Free; end;
  finally Conn.Free; end;
end;
end.
