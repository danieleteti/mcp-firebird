unit Test.Firebird.SecurityAudit;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TSecurityAuditTests = class
  public
    [Test] procedure Grants_Merge_The_Privileges_Of_One_Grantee_On_One_Object;
    [Test] procedure Grants_Leave_Out_The_System_Tables;
    [Test] procedure Grants_Leave_Out_What_An_Owner_Holds_On_Its_Own_Objects;
    [Test] procedure Flags_A_Read_Grant_To_PUBLIC_As_A_Warning;
    [Test] procedure Flags_A_Write_Grant_To_PUBLIC_As_Critical;
    [Test] procedure Flags_A_Grant_Option_As_Delegation;
    [Test] procedure Flags_A_Role_Nobody_Is_A_Member_Of;
    [Test] procedure Every_Advisory_Carries_A_Remedy_And_A_Verify;
    [Test] procedure A_Role_With_Members_Is_Left_Alone;
    [Test] procedure Every_Remedy_Is_A_Statement_That_Parses;
    [Test] procedure Effective_Privileges_Name_How_Each_One_Is_Reached;
    [Test] procedure Effective_Privileges_Mark_A_Role_Row_As_Conditional;
    [Test] procedure An_Account_Nobody_Granted_Anything_Still_Reaches_What_PUBLIC_Holds;
  end;
implementation
uses System.SysUtils, Firebird.Connection, Firebird.Advisory, Firebird.SecurityAudit, TestFixtureU;

function FindGrant(const AGrants: TArray<TGrantSummary>; const AGrantee, AObject: string;
  out AGrant: TGrantSummary): Boolean;
var G: TGrantSummary;
begin
  for G in AGrants do
    if (G.Grantee = AGrantee) and (G.ObjectName = AObject) then
    begin
      AGrant := G;
      Exit(True);
    end;
  Result := False;
end;

function Mentions(const Advs: TArray<TAdvisory>; const ANeedle: string): Boolean;
var X: TAdvisory;
begin
  Result := False;
  for X in Advs do
    if X.Finding.ToUpper.Contains(ANeedle.ToUpper) then Exit(True);
end;

function SeverityOf(const Advs: TArray<TAdvisory>; const ANeedle: string): string;
var X: TAdvisory;
begin
  Result := '';
  for X in Advs do
    if X.Finding.ToUpper.Contains(ANeedle.ToUpper) then Exit(X.Severity);
end;

{ problems.sql grants INSERT and UPDATE on NOPK_LOG to PUBLIC in one statement. The engine
  records one row per privilege letter; the report is one line per grantee and object. }
procedure TSecurityAuditTests.Grants_Merge_The_Privileges_Of_One_Grantee_On_One_Object;
var Conn: TFirebirdConnection; A: TFirebirdSecurityAudit; G: TGrantSummary;
begin
  Conn := NewTestConnection;
  try
    A := TFirebirdSecurityAudit.Create(Conn);
    try
      Assert.IsTrue(FindGrant(A.Grants, 'PUBLIC', 'NOPK_LOG', G), 'PUBLIC/NOPK_LOG not reported');
      Assert.Contains(G.Privileges, 'INSERT');
      Assert.Contains(G.Privileges, 'UPDATE');
      Assert.IsTrue(G.Writes, 'INSERT and UPDATE are writes');
      Assert.AreEqual('table', G.ObjectKind);
    finally A.Free; end;
  finally Conn.Free; end;
end;

{ PUBLIC holds SELECT on most of RDB$: reporting those would bury the two grants somebody
  actually made under forty the engine made. }
procedure TSecurityAuditTests.Grants_Leave_Out_The_System_Tables;
var Conn: TFirebirdConnection; A: TFirebirdSecurityAudit; G: TGrantSummary;
begin
  Conn := NewTestConnection;
  try
    A := TFirebirdSecurityAudit.Create(Conn);
    try
      Assert.IsFalse(FindGrant(A.Grants, 'PUBLIC', 'RDB$RELATIONS', G),
        'system objects must not appear in the grant report');
    finally A.Free; end;
  finally Conn.Free; end;
end;

{ Every object in the seed was created by SYSDBA, so the engine recorded SYSDBA granting
  itself everything on each of them. Reporting those is one line per table saying the owner
  owns it, and the two grants somebody actually made would be lost in them. }
procedure TSecurityAuditTests.Grants_Leave_Out_What_An_Owner_Holds_On_Its_Own_Objects;
var Conn: TFirebirdConnection; A: TFirebirdSecurityAudit; G: TGrantSummary;
begin
  Conn := NewTestConnection;
  try
    A := TFirebirdSecurityAudit.Create(Conn);
    try
      Assert.IsFalse(FindGrant(A.Grants, 'SYSDBA', 'CUSTOMERS', G),
        'the owner''s own privileges are not a grant anybody made');
      Assert.IsTrue(FindGrant(A.Grants, 'PUBLIC', 'CUSTOMERS', G),
        'and the grant somebody did make must still be there');
    finally A.Free; end;
  finally Conn.Free; end;
end;

procedure TSecurityAuditTests.Flags_A_Read_Grant_To_PUBLIC_As_A_Warning;
var Conn: TFirebirdConnection; A: TFirebirdSecurityAudit;
begin
  Conn := NewTestConnection;
  try
    A := TFirebirdSecurityAudit.Create(Conn);
    try
      Assert.IsTrue(Mentions(A.Analyze, 'CUSTOMERS'), 'the PUBLIC SELECT on CUSTOMERS is not flagged');
      Assert.AreEqual('warning', SeverityOf(A.Analyze, 'CUSTOMERS'));
    finally A.Free; end;
  finally Conn.Free; end;
end;

procedure TSecurityAuditTests.Flags_A_Write_Grant_To_PUBLIC_As_Critical;
var Conn: TFirebirdConnection; A: TFirebirdSecurityAudit;
begin
  Conn := NewTestConnection;
  try
    A := TFirebirdSecurityAudit.Create(Conn);
    try
      Assert.AreEqual('critical', SeverityOf(A.Analyze, 'NOPK_LOG'),
        'a grant that lets everyone write is not the same finding as one that lets them read');
    finally A.Free; end;
  finally Conn.Free; end;
end;

procedure TSecurityAuditTests.Flags_A_Grant_Option_As_Delegation;
var Conn: TFirebirdConnection; A: TFirebirdSecurityAudit;
begin
  Conn := NewTestConnection;
  try
    A := TFirebirdSecurityAudit.Create(Conn);
    try
      Assert.IsTrue(Mentions(A.Analyze, 'REPORT_USER'), 'the WITH GRANT OPTION holder is not flagged');
      Assert.IsTrue(Mentions(A.Analyze, 'GRANT OPTION'), 'the finding does not say what it found');
    finally A.Free; end;
  finally Conn.Free; end;
end;

procedure TSecurityAuditTests.Flags_A_Role_Nobody_Is_A_Member_Of;
var Conn: TFirebirdConnection; A: TFirebirdSecurityAudit; R: TRoleInfo; lFound: Boolean;
begin
  Conn := NewTestConnection;
  try
    A := TFirebirdSecurityAudit.Create(Conn);
    try
      lFound := False;
      for R in A.Roles do
        if R.RoleName = 'DEAD_ROLE' then
        begin
          lFound := True;
          Assert.AreEqual(0, Integer(Length(R.Members)));
        end;
      Assert.IsTrue(lFound, 'DEAD_ROLE missing from the role list');
      Assert.IsTrue(Mentions(A.Analyze, 'DEAD_ROLE'), 'a role with no members is not flagged');
      Assert.AreEqual('info', SeverityOf(A.Analyze, 'DEAD_ROLE'));
    finally A.Free; end;
  finally Conn.Free; end;
end;

{ The house rule for every advisory-producing unit: a finding nobody can act on is a
  complaint, so each one carries the statement that fixes it and the way to check. }
procedure TSecurityAuditTests.Every_Advisory_Carries_A_Remedy_And_A_Verify;
var Conn: TFirebirdConnection; A: TFirebirdSecurityAudit; X: TAdvisory; lAdvs: TArray<TAdvisory>;
begin
  Conn := NewTestConnection;
  try
    A := TFirebirdSecurityAudit.Create(Conn);
    try
      lAdvs := A.Analyze;
      Assert.IsTrue(Length(lAdvs) > 0, 'problems.sql seeds three security fixtures');
      for X in lAdvs do
      begin
        Assert.IsNotEmpty(X.Finding);
        Assert.IsNotEmpty(X.SQLText, 'advisory without a remedy: ' + X.Finding);
        Assert.IsNotEmpty(X.Verify, 'advisory without a verification: ' + X.Finding);
        Assert.IsNotEmpty(X.Severity);
      end;
    finally A.Free; end;
  finally Conn.Free; end;
end;

{ REPORT_ROLE is granted to REPORT_USER in problems.sql. A role in use is not a finding, and a
  detector that cannot tell it from a dead one reports every role in the database. }
procedure TSecurityAuditTests.A_Role_With_Members_Is_Left_Alone;
var Conn: TFirebirdConnection; A: TFirebirdSecurityAudit; R: TRoleInfo; lFound: Boolean;
begin
  Conn := NewTestConnection;
  try
    A := TFirebirdSecurityAudit.Create(Conn);
    try
      lFound := False;
      for R in A.Roles do
        if R.RoleName = 'REPORT_ROLE' then
        begin
          lFound := True;
          Assert.AreEqual(1, Integer(Length(R.Members)));
          Assert.AreEqual('REPORT_USER', R.Members[0]);
        end;
      Assert.IsTrue(lFound, 'REPORT_ROLE missing from the role list');
      Assert.IsFalse(Mentions(A.Analyze, 'REPORT_ROLE'), 'a role in use must not be flagged');
    finally A.Free; end;
  finally Conn.Free; end;
end;

{ Every remedy is printed for somebody to run as it stands. Role membership is not granted ON
  anything, so the general form — REVOKE <privs> ON <object> — is not a statement for it. }
procedure TSecurityAuditTests.Every_Remedy_Is_A_Statement_That_Parses;
var Conn: TFirebirdConnection; A: TFirebirdSecurityAudit; X: TAdvisory;
begin
  Conn := NewTestConnection;
  try
    A := TFirebirdSecurityAudit.Create(Conn);
    try
      for X in A.Analyze do
        Assert.IsFalse(X.SQLText.ToUpper.Contains('MEMBER OF ON'),
          'not valid SQL: ' + X.SQLText);
    finally A.Free; end;
  finally Conn.Free; end;
end;
function Reached(const ARows: TArray<TEffectiveGrant>; const AObject: string;
  out ARow: TEffectiveGrant): Boolean;
var E: TEffectiveGrant;
begin
  for E in ARows do
    if E.ObjectName = AObject then
    begin
      ARow := E;
      Exit(True);
    end;
  Result := False;
end;

{ A privilege list answers "who was granted what". This answers "what can this account reach",
  which is a different question the moment PUBLIC or a role is involved. }
procedure TSecurityAuditTests.Effective_Privileges_Name_How_Each_One_Is_Reached;
var Conn: TFirebirdConnection; A: TFirebirdSecurityAudit; lRows: TArray<TEffectiveGrant>; E: TEffectiveGrant;
begin
  Conn := NewTestConnection;
  try
    A := TFirebirdSecurityAudit.Create(Conn);
    try
      lRows := A.EffectivePrivileges('REPORT_USER');
      Assert.IsTrue(Reached(lRows, 'ORDERS', E), 'the direct grant is missing');
      Assert.AreEqual('direct', E.Via);
      Assert.IsTrue(Reached(lRows, 'CUSTOMERS', E), 'what PUBLIC holds is reached by everyone');
      Assert.AreEqual('PUBLIC', E.Via);
      Assert.IsTrue(Reached(lRows, 'BRANCHES', E), 'the grant on REPORT_ROLE is missing');
      Assert.AreEqual('role REPORT_ROLE', E.Via);
    finally A.Free; end;
  finally Conn.Free; end;
end;

{ Firebird will not say whether a role is automatic for an account — a DEFAULT role lives in the
  security database — so a role row is what the account *may* reach, and it has to say so. }
procedure TSecurityAuditTests.Effective_Privileges_Mark_A_Role_Row_As_Conditional;
var Conn: TFirebirdConnection; A: TFirebirdSecurityAudit; E: TEffectiveGrant;
begin
  Conn := NewTestConnection;
  try
    A := TFirebirdSecurityAudit.Create(Conn);
    try
      Assert.IsTrue(Reached(A.EffectivePrivileges('REPORT_USER'), 'BRANCHES', E));
      Assert.IsTrue(E.Conditional, 'a role row is conditional on the role being active');
      Assert.IsTrue(Reached(A.EffectivePrivileges('REPORT_USER'), 'ORDERS', E));
      Assert.IsFalse(E.Conditional, 'a direct grant is not conditional on anything');
    finally A.Free; end;
  finally Conn.Free; end;
end;

procedure TSecurityAuditTests.An_Account_Nobody_Granted_Anything_Still_Reaches_What_PUBLIC_Holds;
var Conn: TFirebirdConnection; A: TFirebirdSecurityAudit; E: TEffectiveGrant;
begin
  Conn := NewTestConnection;
  try
    A := TFirebirdSecurityAudit.Create(Conn);
    try
      Assert.IsTrue(Reached(A.EffectivePrivileges('NOBODY_IN_PARTICULAR'), 'CUSTOMERS', E),
        'PUBLIC needs no membership: an account nobody granted anything still reads this');
      Assert.AreEqual('PUBLIC', E.Via);
    finally A.Free; end;
  finally Conn.Free; end;
end;

end.
