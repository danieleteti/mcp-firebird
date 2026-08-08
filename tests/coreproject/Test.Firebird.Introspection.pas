unit Test.Firebird.Introspection;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TIntrospectionTests = class
  public
    [Test] procedure ListTables_IncludesSeedTables;
    [Test] procedure ListTables_ExcludesSystemTables;
    [Test] procedure GetColumns_Customers_HasCityColumn;
    [Test] procedure GetPrimaryKey_Customers_IsCustomerId;
    [Test] procedure ListProcedures_Finds_The_Seeded_Procedure;
    [Test] procedure ListProcedures_Reports_In_And_Out_Parameters;
    [Test] procedure ListTriggers_Decodes_Before_Insert;
  end;
implementation
uses System.SysUtils, Firebird.Connection, Firebird.Introspection, TestFixtureU;

function Has(const A: TArray<string>; const S: string): Boolean;
var X: string; begin Result := False; for X in A do if SameText(X, S) then Exit(True); end;

procedure TIntrospectionTests.ListTables_IncludesSeedTables;
var Conn: TFirebirdConnection; I: TFirebirdIntrospection;
begin
  Conn := NewTestConnection;
  try I := TFirebirdIntrospection.Create(Conn);
    try Assert.IsTrue(Has(I.ListTables, 'CUSTOMERS')); Assert.IsTrue(Has(I.ListTables, 'ORDERS'));
    finally I.Free; end;
  finally Conn.Free; end;
end;

procedure TIntrospectionTests.ListTables_ExcludesSystemTables;
var Conn: TFirebirdConnection; I: TFirebirdIntrospection;
begin
  Conn := NewTestConnection;
  try I := TFirebirdIntrospection.Create(Conn);
    try Assert.IsFalse(Has(I.ListTables, 'RDB$RELATIONS')); finally I.Free; end;
  finally Conn.Free; end;
end;

procedure TIntrospectionTests.GetColumns_Customers_HasCityColumn;
var Conn: TFirebirdConnection; I: TFirebirdIntrospection; C: TColumnInfo; Found: Boolean;
begin
  Conn := NewTestConnection;
  try I := TFirebirdIntrospection.Create(Conn);
    try
      Found := False;
      for C in I.GetColumns('CUSTOMERS') do if SameText(C.FieldName, 'CITY') then Found := True;
      Assert.IsTrue(Found, 'CITY column present');
    finally I.Free; end;
  finally Conn.Free; end;
end;

procedure TIntrospectionTests.GetPrimaryKey_Customers_IsCustomerId;
var Conn: TFirebirdConnection; I: TFirebirdIntrospection; PK: TArray<string>;
begin
  Conn := NewTestConnection;
  try I := TFirebirdIntrospection.Create(Conn);
    try PK := I.GetPrimaryKey('CUSTOMERS');
      Assert.AreEqual(1, Integer(Length(PK))); Assert.AreEqual('CUSTOMER_ID', PK[0]);
    finally I.Free; end;
  finally Conn.Free; end;
end;

procedure TIntrospectionTests.ListProcedures_Finds_The_Seeded_Procedure;
var
  Conn: TFirebirdConnection;
  I: TFirebirdIntrospection;
  P: TProcedureInfo;
  lFound: Boolean;
begin
  Conn := NewTestConnection;
  try
    I := TFirebirdIntrospection.Create(Conn);
    try
      lFound := False;
      for P in I.ListProcedures do
        if P.ProcName = 'SP_CUSTOMER_TOTAL' then
          lFound := True;
      Assert.IsTrue(lFound, 'SP_CUSTOMER_TOTAL not listed');
    finally
      I.Free;
    end;
  finally
    Conn.Free;
  end;
end;

procedure TIntrospectionTests.ListProcedures_Reports_In_And_Out_Parameters;
var
  Conn: TFirebirdConnection;
  I: TFirebirdIntrospection;
  P: TProcedureInfo;
  R: TRoutineParam;
  lIn, lOut: string;
begin
  Conn := NewTestConnection;
  try
    I := TFirebirdIntrospection.Create(Conn);
    try
      lIn := ''; lOut := '';
      for P in I.ListProcedures do
        if P.ProcName = 'SP_CUSTOMER_TOTAL' then
          for R in P.Params do
            if R.IsOutput then lOut := R.ParamName else lIn := R.ParamName;
      Assert.AreEqual('A_CUSTOMER_ID', lIn, 'input parameter');
      Assert.AreEqual('TOTAL_SPENT', lOut, 'output parameter');
    finally
      I.Free;
    end;
  finally
    Conn.Free;
  end;
end;

procedure TIntrospectionTests.ListTriggers_Decodes_Before_Insert;
var
  Conn: TFirebirdConnection;
  I: TFirebirdIntrospection;
  T: TTriggerInfo;
  lEvent: string;
begin
  Conn := NewTestConnection;
  try
    I := TFirebirdIntrospection.Create(Conn);
    try
      lEvent := '';
      for T in I.ListTriggers('ORDERS') do
        if T.TriggerName = 'TR_ORDERS_BI' then
          lEvent := T.Event;
      Assert.AreEqual('BEFORE INSERT', lEvent);
    finally
      I.Free;
    end;
  finally
    Conn.Free;
  end;
end;
end.
