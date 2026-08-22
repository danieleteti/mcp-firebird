unit Test.Firebird.Attachments;

interface

uses DUnitX.TestFramework;

type
  [TestFixture]
  TAttachmentsTests = class
  public
    [Test] procedure List_Includes_This_Very_Connection;
    [Test] procedure List_Reports_The_Connected_User;
    [Test] procedure Analyze_Is_Quiet_On_A_Healthy_Server;
  end;

implementation

uses
  System.SysUtils, Firebird.Connection, Firebird.Capabilities, Firebird.Advisory,
  Firebird.Attachments, TestFixtureU;

function NewAttachments(AConn: TFirebirdConnection): TFirebirdAttachments;
begin
  Result := TFirebirdAttachments.Create(AConn, TFirebirdCapabilities.Detect(AConn));
end;

procedure TAttachmentsTests.List_Includes_This_Very_Connection;
var
  Conn: TFirebirdConnection;
  A: TFirebirdAttachments;
  T: TAttachmentInfo;
  lSelf: Int64;
  lFound: Boolean;
begin
  Conn := NewTestConnection;
  try
    lSelf := StrToInt64(Conn.ScalarStr('SELECT CURRENT_CONNECTION FROM RDB$DATABASE'));
    A := NewAttachments(Conn);
    try
      lFound := False;
      for T in A.List do
        if T.AttachmentID = lSelf then
          lFound := True;
      Assert.IsTrue(lFound, Format('attachment %d (this connection) not listed', [lSelf]));
    finally
      A.Free;
    end;
  finally
    Conn.Free;
  end;
end;

procedure TAttachmentsTests.List_Reports_The_Connected_User;
var
  Conn: TFirebirdConnection;
  A: TFirebirdAttachments;
  T: TAttachmentInfo;
  lSelf: Int64;
  lUser: string;
begin
  Conn := NewTestConnection;
  try
    lSelf := StrToInt64(Conn.ScalarStr('SELECT CURRENT_CONNECTION FROM RDB$DATABASE'));
    A := NewAttachments(Conn);
    try
      lUser := '';
      for T in A.List do
        if T.AttachmentID = lSelf then
          lUser := T.UserName;
      Assert.AreEqual('SYSDBA', lUser.ToUpper);
    finally
      A.Free;
    end;
  finally
    Conn.Free;
  end;
end;

procedure TAttachmentsTests.Analyze_Is_Quiet_On_A_Healthy_Server;
var
  Conn: TFirebirdConnection;
  A: TFirebirdAttachments;
begin
  { The suite's own connection is seconds old and running nothing long, so with
    generous thresholds there is nothing to report. A detector that fires here
    would fire on every healthy server. }
  Conn := NewTestConnection;
  try
    A := NewAttachments(Conn);
    try
      Assert.AreEqual(0, Integer(Length(A.Analyze(60, 3600))));
    finally
      A.Free;
    end;
  finally
    Conn.Free;
  end;
end;

end.
