unit Test.Firebird.DocGen;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TDocGenTests = class
  public
    [Test] procedure TableDoc_Customers_HasHeadingAndColumns;
    [Test] procedure DatabaseDoc_ListsBothTables;
    [Test] procedure TableMarkdown_Lists_The_Tables_Triggers;
    [Test] procedure DatabaseMarkdown_Has_A_Procedures_Section;
    [Test] procedure DatabaseMarkdown_Names_The_Package_And_Its_Function;
  end;
implementation
uses System.SysUtils, Firebird.Connection, Firebird.Introspection, Firebird.DocGen,
  Firebird.Capabilities, TestFixtureU;

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

procedure TDocGenTests.TableMarkdown_Lists_The_Tables_Triggers;
var
  Conn: TFirebirdConnection;
  G: TFirebirdDocGen;
  lMd: string;
begin
  Conn := NewTestConnection;
  try
    G := TFirebirdDocGen.Create(TFirebirdIntrospection.Create(Conn));
    try
      lMd := G.TableMarkdown('ORDERS');
      Assert.IsTrue(lMd.Contains('TR_ORDERS_BI'), 'trigger name missing');
      Assert.IsTrue(lMd.Contains('BEFORE INSERT'), 'trigger event missing');
    finally
      G.Free;
    end;
  finally
    Conn.Free;
  end;
end;

procedure TDocGenTests.DatabaseMarkdown_Has_A_Procedures_Section;
var
  Conn: TFirebirdConnection;
  G: TFirebirdDocGen;
  lMd: string;
begin
  Conn := NewTestConnection;
  try
    G := TFirebirdDocGen.Create(TFirebirdIntrospection.Create(Conn));
    try
      lMd := G.DatabaseMarkdown;
      Assert.IsTrue(lMd.Contains('## Stored procedures'), 'procedures heading missing');
      Assert.IsTrue(lMd.Contains('SP_CUSTOMER_TOTAL'), 'procedure name missing');
      Assert.IsTrue(lMd.Contains('TOTAL_SPENT'), 'output parameter missing');
    finally
      G.Free;
    end;
  finally
    Conn.Free;
  end;
end;

{ Nothing asserts the package-qualified path yet: seed_fb3.sql seeds PKG_ORDERS.TOTAL_FOR
  precisely so the RDB$PACKAGE_NAME join in ListFunctions has something to get wrong, and
  until now only the free-standing FN_ORDER_NET was checked. Below 3.0 the seed has neither,
  and the sections are correctly absent. }
procedure TDocGenTests.DatabaseMarkdown_Names_The_Package_And_Its_Function;
var
  Conn: TFirebirdConnection;
  G: TFirebirdDocGen;
  C: TFirebirdCapabilities;
  lMd: string;
begin
  Conn := NewTestConnection;
  try
    C := TFirebirdCapabilities.Detect(Conn);
    G := TFirebirdDocGen.Create(TFirebirdIntrospection.Create(Conn));
    try
      lMd := G.DatabaseMarkdown;
      if C.HasPackages then
      begin
        Assert.IsTrue(lMd.Contains('## Functions'), 'functions heading missing');
        Assert.IsTrue(lMd.Contains('FN_ORDER_NET'), 'standalone function missing');
        Assert.IsTrue(lMd.Contains('PKG_ORDERS.TOTAL_FOR'),
          'package-qualified function missing — the RDB$PACKAGE_NAME join is what this checks');
        Assert.IsTrue(lMd.Contains('## Packages'), 'packages heading missing');
      end
      else
      begin
        Assert.IsFalse(lMd.Contains('## Packages'),
          'packages section must not appear on ' + C.EngineVersion);
        Assert.IsFalse(lMd.Contains('## Functions'),
          'functions section must not appear on ' + C.EngineVersion);
      end;
    finally
      G.Free;
    end;
  finally
    Conn.Free;
  end;
end;
end.
