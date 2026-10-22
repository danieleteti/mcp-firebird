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
    [Test] procedure TableMarkdown_Names_The_Domain_Behind_A_Column;
    [Test] procedure TableMarkdown_Lists_The_Check_Constraint;
    [Test] procedure TableMarkdown_Does_Not_List_The_Check_Constraints_Triggers;
    [Test] procedure TableMarkdown_Of_A_View_Shows_Its_Source;
    [Test] procedure DatabaseMarkdown_Has_A_Views_Section;
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
{ A column built on a domain reads as its resolved type — VARCHAR(60) — and the fact that the
  rule has a name, and one place to change it, is lost unless the name is printed. }
procedure TDocGenTests.TableMarkdown_Names_The_Domain_Behind_A_Column;
var Conn: TFirebirdConnection; G: TFirebirdDocGen; lMd: string;
begin
  Conn := NewTestConnection;
  try
    G := TFirebirdDocGen.Create(TFirebirdIntrospection.Create(Conn));
    try
      lMd := G.TableMarkdown('BRANCHES');
      Assert.IsTrue(lMd.Contains('D_CITY'), 'domain name missing');
      Assert.IsTrue(lMd.Contains('VARCHAR(60)'), 'the resolved type must still be there');
      { The PK's own index is called RDB$PRIMARY<n> and belongs in the index list. What must
        never appear is a *domain* named RDB$<n>: that is the field source Firebird generates
        for a column declared inline, and reporting it as a domain would invent one. }
      Assert.IsFalse(lMd.Contains('(domain RDB$'),
        'a generated field source is not a domain');
    finally G.Free; end;
  finally Conn.Free; end;
end;

procedure TDocGenTests.TableMarkdown_Lists_The_Check_Constraint;
var Conn: TFirebirdConnection; G: TFirebirdDocGen; lMd: string;
begin
  Conn := NewTestConnection;
  try
    G := TFirebirdDocGen.Create(TFirebirdIntrospection.Create(Conn));
    try
      lMd := G.TableMarkdown('BRANCHES');
      Assert.IsTrue(lMd.Contains('### Check constraints'), 'check section missing');
      Assert.IsTrue(lMd.Contains('CHK_BRANCH_STAFF'), 'constraint name missing');
      Assert.IsTrue(lMd.ToUpper.Contains('STAFF >= 0'), 'the rule itself is what a reader needs');
    finally G.Free; end;
  finally Conn.Free; end;
end;

{ Firebird enforces one CHECK with two triggers the user never wrote. Listing them reports an
  implementation detail as a schema object, twice. }
procedure TDocGenTests.TableMarkdown_Does_Not_List_The_Check_Constraints_Triggers;
var Conn: TFirebirdConnection; I: TFirebirdIntrospection; T: TTriggerInfo;
begin
  Conn := NewTestConnection;
  try
    I := TFirebirdIntrospection.Create(Conn);
    try
      for T in I.ListTriggers('BRANCHES') do
        Assert.Fail('CHECK trigger leaked into the trigger list: ' + T.TriggerName);
    finally I.Free; end;
  finally Conn.Free; end;
end;

procedure TDocGenTests.TableMarkdown_Of_A_View_Shows_Its_Source;
var Conn: TFirebirdConnection; G: TFirebirdDocGen; lMd: string;
begin
  Conn := NewTestConnection;
  try
    G := TFirebirdDocGen.Create(TFirebirdIntrospection.Create(Conn));
    try
      { Asked about a name, not about a kind: the caller should not have to know which it is. }
      lMd := G.TableMarkdown('V_CUSTOMER_ORDERS');
      Assert.IsTrue(lMd.Contains('*(view)*'), 'a view must not be documented as a table');
      Assert.IsTrue(lMd.Contains('**View source:**'), 'view source section missing');
      Assert.IsTrue(lMd.ToUpper.Contains('JOIN ORDERS'),
        'the SELECT behind the view is the only place its cost is visible');
    finally G.Free; end;
  finally Conn.Free; end;
end;

procedure TDocGenTests.DatabaseMarkdown_Has_A_Views_Section;
var Conn: TFirebirdConnection; G: TFirebirdDocGen; lMd: string;
begin
  Conn := NewTestConnection;
  try
    G := TFirebirdDocGen.Create(TFirebirdIntrospection.Create(Conn));
    try
      lMd := G.DatabaseMarkdown;
      Assert.IsTrue(lMd.Contains('# Views'), 'views heading missing');
      Assert.IsTrue(lMd.Contains('V_CUSTOMER_ORDERS'), 'view missing from the whole-database doc');
    finally G.Free; end;
  finally Conn.Free; end;
end;
end.
