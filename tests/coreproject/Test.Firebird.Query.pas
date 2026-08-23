unit Test.Firebird.Query;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TQueryTests = class
  public
    [Test] procedure Returns_The_Columns_And_The_Rows;
    [Test] procedure Caps_The_Rows_And_Says_So;
    [Test] procedure Under_The_Cap_Is_Not_Reported_As_Truncated;
    [Test] procedure Refuses_Anything_That_Is_Not_A_Select;
    [Test] procedure Refuses_Unbound_Placeholders;
    [Test] procedure Clamps_An_Absurd_Cap_To_The_Ceiling;
    [Test] procedure Renders_Null_As_Null;
    [Test] procedure Markdown_Has_A_Header_And_A_Row_Count;
    [Test] procedure A_Pipe_In_The_Data_Does_Not_Break_The_Table;
    [Test] procedure A_Wide_Result_Stops_On_Size_Before_It_Stops_On_Rows;
    [Test] procedure A_Narrow_Result_Is_Never_Stopped_By_Size;
  end;
implementation
uses System.SysUtils, Firebird.Connection, Firebird.Query, TestFixtureU;

procedure TQueryTests.Returns_The_Columns_And_The_Rows;
var Conn: TFirebirdConnection; R: TQueryResult;
begin
  Conn := NewTestConnection;
  try
    R := RunSelect(Conn, 'SELECT CUSTOMER_ID, NAME FROM CUSTOMERS WHERE CUSTOMER_ID = 1', 0);
    Assert.IsTrue(R.Executed, R.SkipReason);
    Assert.AreEqual(2, Integer(Length(R.Columns)));
    Assert.AreEqual('CUSTOMER_ID', R.Columns[0]);
    Assert.AreEqual(1, Integer(Length(R.Rows)));
    Assert.AreEqual('1', R.Rows[0][0]);
    Assert.AreEqual('CUST_1', R.Rows[0][1]);
  finally Conn.Free; end;
end;

{ The cap is the whole point of the tool: without it a SELECT * on the seeded CUSTOMERS puts
  five thousand rows into somebody's context window. }
procedure TQueryTests.Caps_The_Rows_And_Says_So;
var Conn: TFirebirdConnection; R: TQueryResult;
begin
  Conn := NewTestConnection;
  try
    R := RunSelect(Conn, 'SELECT * FROM CUSTOMERS', 10);
    Assert.IsTrue(R.Executed, R.SkipReason);
    Assert.AreEqual(10, Integer(Length(R.Rows)));
    Assert.IsTrue(R.Truncated, 'the seed has 5000 customers: this must report as truncated');
    Assert.Contains(R.ToMarkdown, 'stopped at the cap');
  finally Conn.Free; end;
end;

{ Truncated is read as "there is more"; a result that happens to be exactly the size of the
  cap, or smaller, must not claim there is. }
procedure TQueryTests.Under_The_Cap_Is_Not_Reported_As_Truncated;
var Conn: TFirebirdConnection; R: TQueryResult;
begin
  Conn := NewTestConnection;
  try
    R := RunSelect(Conn, 'SELECT * FROM CUSTOMERS WHERE CUSTOMER_ID < 5', 100);
    Assert.IsTrue(R.Executed, R.SkipReason);
    Assert.AreEqual(5, Integer(Length(R.Rows)));
    Assert.IsFalse(R.Truncated);
    Assert.Contains(R.ToMarkdown, '5 row(s)');
  finally Conn.Free; end;
end;

procedure TQueryTests.Refuses_Anything_That_Is_Not_A_Select;
var Conn: TFirebirdConnection; R: TQueryResult;
begin
  Conn := NewTestConnection;
  try
    R := RunSelect(Conn, 'DELETE FROM CUSTOMERS', 0);
    Assert.IsFalse(R.Executed, 'a DELETE must never reach the engine from here');
    Assert.IsNotEmpty(R.SkipReason);
    Assert.Contains(R.ToMarkdown, 'Not executed');
  finally Conn.Free; end;
end;

procedure TQueryTests.Refuses_Unbound_Placeholders;
var Conn: TFirebirdConnection; R: TQueryResult;
begin
  Conn := NewTestConnection;
  try
    R := RunSelect(Conn, 'SELECT * FROM CUSTOMERS WHERE CITY = ?', 0);
    Assert.IsFalse(R.Executed);
    Assert.Contains(R.SkipReason.ToLower, 'placeholder');
  finally Conn.Free; end;
end;

procedure TQueryTests.Clamps_An_Absurd_Cap_To_The_Ceiling;
var Conn: TFirebirdConnection; R: TQueryResult;
begin
  Conn := NewTestConnection;
  try
    { One narrow column on purpose: with SELECT * the character budget would stop this long
      before the row ceiling, and the test would be measuring the wrong limit. }
    R := RunSelect(Conn, 'SELECT CUSTOMER_ID FROM CUSTOMERS', 100000);
    Assert.AreEqual(ROW_CEILING, R.MaxRows);
    Assert.AreEqual(ROW_CEILING, Integer(Length(R.Rows)));
    Assert.IsFalse(R.TruncatedBySize);
  finally Conn.Free; end;
end;

procedure TQueryTests.Renders_Null_As_Null;
var Conn: TFirebirdConnection; R: TQueryResult;
begin
  Conn := NewTestConnection;
  try
    R := RunSelect(Conn, 'SELECT CAST(NULL AS INTEGER) FROM RDB$DATABASE', 0);
    Assert.IsTrue(R.Executed, R.SkipReason);
    Assert.AreEqual('NULL', R.Rows[0][0], 'an empty cell and a NULL cell must not look alike');
  finally Conn.Free; end;
end;

procedure TQueryTests.Markdown_Has_A_Header_And_A_Row_Count;
var Conn: TFirebirdConnection; MD: string;
begin
  Conn := NewTestConnection;
  try
    MD := RunSelect(Conn, 'SELECT CUSTOMER_ID FROM CUSTOMERS WHERE CUSTOMER_ID < 3', 0).ToMarkdown;
    Assert.Contains(MD, '| CUSTOMER_ID |');
    Assert.Contains(MD, '|---|');
    Assert.Contains(MD, '3 row(s)');
  finally Conn.Free; end;
end;

{ A pipe in a value is content; unescaped it is a column separator, and every row after it
  reads as one column wider than the header. }
procedure TQueryTests.A_Pipe_In_The_Data_Does_Not_Break_The_Table;
var Conn: TFirebirdConnection; R: TQueryResult;
begin
  Conn := NewTestConnection;
  try
    R := RunSelect(Conn, 'SELECT ''a|b'' FROM RDB$DATABASE', 0);
    Assert.IsTrue(R.Executed, R.SkipReason);
    Assert.AreEqual('a\|b', R.Rows[0][0]);
  finally Conn.Free; end;
end;

{ The row cap bounds rows; nothing in it bounds width. A hundred rows of a wide table is a
  hundred rows and half a megabyte of Markdown, which is not an answer any more. }
procedure TQueryTests.A_Wide_Result_Stops_On_Size_Before_It_Stops_On_Rows;
var Conn: TFirebirdConnection; R: TQueryResult;
begin
  Conn := NewTestConnection;
  try
    { Eight hundred characters per row against a budget of twenty thousand: this stops long
      before the hundred rows the cap would have allowed. }
    R := RunSelect(Conn,
      'SELECT LPAD('''', 200, ''x''), LPAD('''', 200, ''x''), LPAD('''', 200, ''x''), ' +
      '       LPAD('''', 200, ''x'') FROM CUSTOMERS', 100);
    Assert.IsTrue(R.Executed, R.SkipReason);
    Assert.IsTrue(R.TruncatedBySize, 'a wide result must stop on size');
    Assert.IsTrue(Length(R.Rows) < 100, 'it must stop before the row cap');
    Assert.Contains(R.ToMarkdown, 'too wide');
  finally Conn.Free; end;
end;

procedure TQueryTests.A_Narrow_Result_Is_Never_Stopped_By_Size;
var Conn: TFirebirdConnection; R: TQueryResult;
begin
  Conn := NewTestConnection;
  try
    R := RunSelect(Conn, 'SELECT CUSTOMER_ID FROM CUSTOMERS', 100);
    Assert.IsTrue(R.Executed, R.SkipReason);
    Assert.AreEqual(100, Integer(Length(R.Rows)));
    Assert.IsFalse(R.TruncatedBySize, 'one integer column cannot exhaust the budget');
  finally Conn.Free; end;
end;

end.
