unit Test.Firebird.Indexes;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TIndexIntrospectionTests = class
  public
    [Test] procedure Orders_Has_System_FK_Index_And_User_Dup;
    [Test] procedure Customers_CityIndex_IsInactive;
    [Test] procedure Orders_ForeignKey_References_Customers;
  end;
implementation
uses System.SysUtils, Firebird.Connection, Firebird.Introspection, TestFixtureU;

procedure TIndexIntrospectionTests.Orders_Has_System_FK_Index_And_User_Dup;
var Conn: TFirebirdConnection; I: TFirebirdIntrospection; X: TIndexInfo; SysCount, DupCount: Integer;
begin
  Conn := NewTestConnection;
  try I := TFirebirdIntrospection.Create(Conn);
    try
      SysCount := 0; DupCount := 0;
      for X in I.GetIndexes('ORDERS') do begin
        if X.IsSystem and (Length(X.Columns)=1) and SameText(X.Columns[0],'CUSTOMER_ID') then Inc(SysCount);
        if SameText(X.IndexName,'IDX_ORDERS_CUSTOMER_DUP') then Inc(DupCount);
      end;
      Assert.IsTrue(SysCount >= 1, 'system FK index on CUSTOMER_ID exists');
      Assert.AreEqual(1, DupCount, 'user duplicate index present');
    finally I.Free; end;
  finally Conn.Free; end;
end;

procedure TIndexIntrospectionTests.Customers_CityIndex_IsInactive;
var Conn: TFirebirdConnection; I: TFirebirdIntrospection; X: TIndexInfo; Found: Boolean;
begin
  Conn := NewTestConnection;
  try I := TFirebirdIntrospection.Create(Conn);
    try Found := False;
      for X in I.GetIndexes('CUSTOMERS') do
        if SameText(X.IndexName,'IDX_CUST_CITY') then begin Found := True; Assert.IsTrue(X.Inactive); end;
      Assert.IsTrue(Found, 'IDX_CUST_CITY present');
    finally I.Free; end;
  finally Conn.Free; end;
end;

procedure TIndexIntrospectionTests.Orders_ForeignKey_References_Customers;
var Conn: TFirebirdConnection; I: TFirebirdIntrospection; FKs: TArray<TForeignKeyInfo>;
begin
  Conn := NewTestConnection;
  try I := TFirebirdIntrospection.Create(Conn);
    try FKs := I.GetForeignKeys('ORDERS');
      Assert.AreEqual(1, Integer(Length(FKs)));
      Assert.AreEqual('CUSTOMERS', FKs[0].RefTable);
      Assert.AreEqual('CUSTOMER_ID', FKs[0].Columns[0]);
    finally I.Free; end;
  finally Conn.Free; end;
end;
end.
