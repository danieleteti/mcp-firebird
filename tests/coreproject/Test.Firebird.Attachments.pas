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
    [Test] procedure Wire_Encryption_Is_Reported_Only_Where_The_Engine_Can_Say;
    [Test] procedure WireAdvisories_Fire_Exactly_When_A_Remote_Attachment_Is_In_Clear;
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

procedure TAttachmentsTests.Wire_Encryption_Is_Reported_Only_Where_The_Engine_Can_Say;
var
  Conn: TFirebirdConnection;
  A: TFirebirdAttachments;
  T: TAttachmentInfo;
  lCaps: TFirebirdCapabilities;
begin
  Conn := NewTestConnection;
  try
    lCaps := TFirebirdCapabilities.Detect(Conn);
    A := NewAttachments(Conn);
    try
      for T in A.List do
        Assert.IsTrue(lCaps.HasWireEncryptionMon = T.WireKnown,
          'WireKnown must follow MON$WIRE_ENCRYPTED, which exists from 4.0');
    finally
      A.Free;
    end;
  finally
    Conn.Free;
  end;
end;

procedure TAttachmentsTests.WireAdvisories_Fire_Exactly_When_A_Remote_Attachment_Is_In_Clear;
var
  Conn: TFirebirdConnection;
  A: TFirebirdAttachments;
  T: TAttachmentInfo;
  lRemoteClear: Boolean;
begin
  Conn := NewTestConnection;
  try
    A := NewAttachments(Conn);
    try
      lRemoteClear := False;
      for T in A.List do
        if T.WireKnown and (not T.Encrypted) and (T.RemoteAddress <> '') then
          lRemoteClear := True;
      Assert.AreEqual(Integer(Ord(lRemoteClear)), Integer(Length(A.WireAdvisories)),
        'one advisory exactly when some remote attachment is in clear');
    finally
      A.Free;
    end;
  finally
    Conn.Free;
  end;
end;

end.
