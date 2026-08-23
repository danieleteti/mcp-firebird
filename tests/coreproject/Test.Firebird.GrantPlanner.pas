unit Test.Firebird.GrantPlanner;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TGrantPlannerTests = class
  public
    [Test] procedure Pattern_Underscore_Is_Literal_Not_A_Wildcard;
    [Test] procedure Pattern_In_Quotes_Keeps_Its_Case;
    [Test] procedure Quoting_Only_Where_Firebird_Needs_It;
    [Test] procedure Plans_Read_Access_To_One_Prefix;
    [Test] procedure Leaves_Out_The_Table_The_Underscore_Would_Have_Matched;
    [Test] procedure ReadWrite_Grants_The_Write_Privileges;
    [Test] procedure A_Procedure_Is_Granted_EXECUTE_With_The_Keyword;
    [Test] procedure A_Mixed_Case_Object_Is_Quoted;
    [Test] procedure The_Role_Is_Activated_The_Way_This_Engine_Allows;
    [Test] procedure An_Existing_Role_Is_Not_Created_Again;
    [Test] procedure A_PUBLIC_Grant_Outside_The_Plan_Is_A_Conflict;
    [Test] procedure A_Grant_The_Account_Already_Holds_Is_A_Conflict;
    [Test] procedure An_Exclusion_Removes_An_Object_From_The_Plan;
    [Test] procedure A_Pattern_That_Matches_Nothing_Says_So_And_Grants_Nothing;
    [Test] procedure A_Plan_For_SYSDBA_Says_It_Changes_Nothing;
    [Test] procedure An_Access_Level_Nobody_Understands_Is_Not_Silently_Downgraded;
  end;
implementation
uses System.SysUtils, Firebird.Connection, Firebird.Capabilities, Firebird.Advisory,
  Firebird.GrantPlanner, TestFixtureU;

function AllStatements(const APlan: TGrantPlan): string;
var S: string;
begin
  Result := '';
  for S in APlan.Statements do
    Result := Result + S + sLineBreak;
end;

function AllNotes(const APlan: TGrantPlan): string;
var S: string;
begin
  Result := '';
  for S in APlan.Notes do
    Result := Result + S + sLineBreak;
end;

function ConflictsMention(const APlan: TGrantPlan; const ANeedle: string): Boolean;
var X: TAdvisory;
begin
  Result := False;
  for X in APlan.Conflicts do
    if X.Finding.ToUpper.Contains(ANeedle.ToUpper) or X.SQLText.ToUpper.Contains(ANeedle.ToUpper) then
      Exit(True);
end;

function Plan(AConn: TFirebirdConnection; const APattern: string;
  const AAccess: string = 'read'; const AUser: string = 'APP';
  const ARole: string = ''; const AExclude: string = ''): TGrantPlan;
begin
  Result := PlanGrants(AConn, AUser, APattern, AAccess, ARole, AExclude);
end;

{ Somebody who asks for TBL_* is naming a prefix. SQL would read the underscore as "any single
  character" and hand them TBLX_OTHER as well — a table from another application. }
procedure TGrantPlannerTests.Pattern_Underscore_Is_Literal_Not_A_Wildcard;
begin
  Assert.AreEqual('TBL\_%', TranslatePattern('tbl_*'));
  Assert.AreEqual('TBL\_%', TranslatePattern('TBL_%'));
  Assert.AreEqual('CUSTOMER_', TranslatePattern('customer?'));
end;

procedure TGrantPlannerTests.Pattern_In_Quotes_Keeps_Its_Case;
begin
  Assert.AreEqual('tbl\_%', TranslatePattern('"tbl_*"'));
  Assert.AreEqual('%', TranslatePattern(''), 'an empty pattern means everything');
end;

procedure TGrantPlannerTests.Quoting_Only_Where_Firebird_Needs_It;
begin
  Assert.AreEqual('TBL_ORDERS', QuoteIfNeeded('TBL_ORDERS'), 'a plain upper-case name is not quoted');
  Assert.AreEqual('"tbl_Mixed"', QuoteIfNeeded('tbl_Mixed'));
  Assert.AreEqual('"WITH SPACE"', QuoteIfNeeded('WITH SPACE'));
end;

procedure TGrantPlannerTests.Plans_Read_Access_To_One_Prefix;
var Conn: TFirebirdConnection; P: TGrantPlan; SQL: string;
begin
  Conn := NewTestConnection;
  try
    P := Plan(Conn, 'TBL_*');
    SQL := AllStatements(P);
    Assert.IsTrue(SQL.Contains('GRANT SELECT ON TBL_ORDERS TO APP_ROLE;'), SQL);
    Assert.IsTrue(SQL.Contains('GRANT SELECT ON TBL_ITEMS TO APP_ROLE;'), SQL);
    Assert.IsTrue(SQL.Contains('CREATE ROLE APP_ROLE;'), SQL);
    Assert.IsTrue(SQL.Contains('CREATE USER APP PASSWORD'), 'the account has to exist first');
    Assert.IsFalse(SQL.Contains('CUSTOMERS'), 'nothing outside the prefix may be granted');
  finally Conn.Free; end;
end;

procedure TGrantPlannerTests.Leaves_Out_The_Table_The_Underscore_Would_Have_Matched;
var Conn: TFirebirdConnection; SQL: string;
begin
  Conn := NewTestConnection;
  try
    SQL := AllStatements(Plan(Conn, 'TBL_*'));
    Assert.IsFalse(SQL.Contains('TBLX_OTHER'),
      'TBL_% as a raw LIKE pattern would have matched TBLX_OTHER: ' + SQL);
  finally Conn.Free; end;
end;

procedure TGrantPlannerTests.ReadWrite_Grants_The_Write_Privileges;
var Conn: TFirebirdConnection; SQL: string;
begin
  Conn := NewTestConnection;
  try
    SQL := AllStatements(Plan(Conn, 'TBL_*', 'readwrite'));
    Assert.IsTrue(SQL.Contains('GRANT SELECT, INSERT, UPDATE, DELETE ON TBL_ORDERS TO APP_ROLE;'), SQL);
  finally Conn.Free; end;
end;

procedure TGrantPlannerTests.A_Procedure_Is_Granted_EXECUTE_With_The_Keyword;
var Conn: TFirebirdConnection; SQL: string;
begin
  Conn := NewTestConnection;
  try
    SQL := AllStatements(Plan(Conn, 'TBL_*'));
    Assert.IsTrue(SQL.Contains('GRANT EXECUTE ON PROCEDURE TBL_SP_COUNT TO APP_ROLE;'), SQL);
    Assert.IsFalse(SQL.Contains('GRANT SELECT ON TBL_SP_COUNT'),
      'a procedure is executed, not selected from');
  finally Conn.Free; end;
end;

{ A table created as "tbl_Mixed" cannot be reached by TBL_MIXED: Firebird folds the unquoted
  name and then does not find it. }
procedure TGrantPlannerTests.A_Mixed_Case_Object_Is_Quoted;
var Conn: TFirebirdConnection; SQL: string;
begin
  Conn := NewTestConnection;
  try
    SQL := AllStatements(Plan(Conn, '"tbl_*"'));
    Assert.IsTrue(SQL.Contains('GRANT SELECT ON "tbl_Mixed" TO APP_ROLE;'), SQL);
  finally Conn.Free; end;
end;

{ The statement everything else depends on. Below 4.0 a role is inactive unless the connection
  asks for it, and the plan has to say so rather than emit DEFAULT syntax the parser refuses. }
procedure TGrantPlannerTests.The_Role_Is_Activated_The_Way_This_Engine_Allows;
var Conn: TFirebirdConnection; P: TGrantPlan; SQL: string; C: TFirebirdCapabilities;
begin
  Conn := NewTestConnection;
  try
    C := TFirebirdCapabilities.Detect(Conn);
    P := Plan(Conn, 'TBL_*');
    SQL := AllStatements(P);
    if C.HasDefaultRoles then
    begin
      Assert.IsTrue(SQL.Contains('GRANT DEFAULT APP_ROLE TO USER APP;'), SQL);
      Assert.IsTrue(AllNotes(P).Contains('DEFAULT role'), AllNotes(P));
    end
    else
    begin
      Assert.IsTrue(SQL.Contains('GRANT APP_ROLE TO APP;'), SQL);
      Assert.IsFalse(SQL.Contains('GRANT DEFAULT'),
        'DEFAULT roles are 4.0+; on ' + C.EngineVersion + ' the parser stops at DEFAULT');
      Assert.IsTrue(AllNotes(P).ToUpper.Contains('ROLENAME'),
        'below 4.0 the plan must say the application has to pass the role: ' + AllNotes(P));
    end;
  finally Conn.Free; end;
end;

procedure TGrantPlannerTests.An_Existing_Role_Is_Not_Created_Again;
var Conn: TFirebirdConnection; P: TGrantPlan;
begin
  Conn := NewTestConnection;
  try
    { REPORT_ROLE is seeded by problems.sql. }
    P := Plan(Conn, 'TBL_*', 'read', 'APP', 'REPORT_ROLE');
    Assert.IsTrue(P.RoleExists);
    Assert.IsFalse(AllStatements(P).Contains('CREATE ROLE REPORT_ROLE;'), AllStatements(P));
    Assert.IsTrue(AllStatements(P).Contains('GRANT SELECT ON TBL_ORDERS TO REPORT_ROLE;'));
  finally Conn.Free; end;
end;

{ The half that makes "and nothing else" true or false. problems.sql grants SELECT on CUSTOMERS
  to PUBLIC, and APP is a member of PUBLIC like everybody else. }
procedure TGrantPlannerTests.A_PUBLIC_Grant_Outside_The_Plan_Is_A_Conflict;
var Conn: TFirebirdConnection; P: TGrantPlan;
begin
  Conn := NewTestConnection;
  try
    P := Plan(Conn, 'TBL_*');
    Assert.IsTrue(ConflictsMention(P, 'CUSTOMERS'),
      'the PUBLIC grant on CUSTOMERS makes the plan untrue and must be reported');
    Assert.IsTrue(ConflictsMention(P, 'REVOKE'), 'a conflict without a remedy is a complaint');
  finally Conn.Free; end;
end;

procedure TGrantPlannerTests.A_Grant_The_Account_Already_Holds_Is_A_Conflict;
var Conn: TFirebirdConnection; P: TGrantPlan;
begin
  Conn := NewTestConnection;
  try
    { REPORT_USER already holds SELECT on ORDERS, which is outside TBL_*. }
    P := Plan(Conn, 'TBL_*', 'read', 'REPORT_USER');
    Assert.IsTrue(ConflictsMention(P, 'ORDERS'), 'an existing grant of this account is a conflict');
  finally Conn.Free; end;
end;

procedure TGrantPlannerTests.An_Exclusion_Removes_An_Object_From_The_Plan;
var Conn: TFirebirdConnection; SQL: string;
begin
  Conn := NewTestConnection;
  try
    SQL := AllStatements(Plan(Conn, 'TBL_*', 'read', 'APP', '', 'TBL_ITEMS'));
    Assert.IsTrue(SQL.Contains('TBL_ORDERS'), SQL);
    Assert.IsFalse(SQL.Contains('TBL_ITEMS'), 'the excluded table must not be granted: ' + SQL);
  finally Conn.Free; end;
end;

procedure TGrantPlannerTests.A_Pattern_That_Matches_Nothing_Says_So_And_Grants_Nothing;
var Conn: TFirebirdConnection; P: TGrantPlan;
begin
  Conn := NewTestConnection;
  try
    P := Plan(Conn, 'NO_SUCH_PREFIX_*');
    Assert.AreEqual(0, Integer(Length(P.Statements)),
      'an empty match must not produce a CREATE USER and a role nobody can use');
    Assert.IsTrue(AllNotes(P).Contains('nothing to grant'), AllNotes(P));
  finally Conn.Free; end;
end;

{ The account the whole tool exists to replace. Granting it less is not a smaller SYSDBA, it is
  a no-op, and a plan that printed CREATE USER SYSDBA would be worse than useless. }
procedure TGrantPlannerTests.A_Plan_For_SYSDBA_Says_It_Changes_Nothing;
var Conn: TFirebirdConnection; P: TGrantPlan;
begin
  Conn := NewTestConnection;
  try
    P := Plan(Conn, 'TBL_*', 'read', 'SYSDBA');
    Assert.IsFalse(AllStatements(P).Contains('CREATE USER SYSDBA'), AllStatements(P));
    Assert.IsTrue(AllNotes(P).Contains('not subject to privileges'), AllNotes(P));
  finally Conn.Free; end;
end;

procedure TGrantPlannerTests.An_Access_Level_Nobody_Understands_Is_Not_Silently_Downgraded;
var Conn: TFirebirdConnection; P: TGrantPlan;
begin
  Conn := NewTestConnection;
  try
    P := Plan(Conn, 'TBL_*', 'full');
    Assert.AreEqual('read', P.Access, 'the safe reading is the one to fall back to');
    Assert.IsTrue(AllNotes(P).Contains('not a value this understands'),
      'falling back quietly would hand somebody read access they think is write access: ' + AllNotes(P));
  finally Conn.Free; end;
end;

end.
