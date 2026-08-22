// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit Firebird.Attachments;

{ Who is attached, from where, and what each one is running right now.

  This is a snapshot of state, not of waiting: MON$ counts work performed and has
  no column for time spent waiting for permission to perform it. An attachment
  blocked on another one's lock looks exactly like an attachment that is busy. }

interface

uses Firebird.Connection, Firebird.Capabilities, Firebird.Advisory;

type
  TAttachmentInfo = record
    AttachmentID: Int64;
    UserName: string;
    RemoteAddress: string;
    RemoteProcess: string;
    Active: Boolean;
    ConnectedSeconds: Int64;
    CurrentSQL: string;       // '' when the attachment is running nothing
    StatementSeconds: Int64;  // age of that statement, 0 when there is none
  end;

  TFirebirdAttachments = class
  private
    FConn: TFirebirdConnection;
    FCaps: TFirebirdCapabilities;
  public
    constructor Create(AConn: TFirebirdConnection; const ACaps: TFirebirdCapabilities);
    function List: TArray<TAttachmentInfo>;
    function Analyze(AIdleMinutes, ALongStatementSeconds: Integer): TArray<TAdvisory>;
  end;

implementation

uses System.SysUtils, System.Generics.Collections, FireDAC.Comp.Client;

const
  SQL_TEXT_LIMIT = 300;

{ '' is not a useful thing to print for an attachment that came in over XNET. }
function IfEmpty(const AValue, AFallback: string): string;
begin
  if AValue = '' then
    Result := AFallback
  else
    Result := AValue;
end;

constructor TFirebirdAttachments.Create(AConn: TFirebirdConnection;
  const ACaps: TFirebirdCapabilities);
begin
  inherited Create;
  FConn := AConn;
  FCaps := ACaps;
end;

function TFirebirdAttachments.List: TArray<TAttachmentInfo>;
var
  Q: TFDQuery;
  L: TList<TAttachmentInfo>;
  T: TAttachmentInfo;
begin
  Result := [];
  if not FCaps.HasMonTables then
    Exit;
  L := TList<TAttachmentInfo>.Create;
  try
    { The newest statement per attachment: MON$STATEMENTS keeps finished ones too,
      so ordering by timestamp and taking the first is what "running now" means here. }
    Q := FConn.OpenQuery(
      'SELECT a.MON$ATTACHMENT_ID AS AID, TRIM(a.MON$USER) AS AUSER, ' +
      '       COALESCE(TRIM(a.MON$REMOTE_ADDRESS), '''') AS ADDR, ' +
      '       COALESCE(TRIM(a.MON$REMOTE_PROCESS), '''') AS PROC, ' +
      '       COALESCE(a.MON$STATE, 0) AS ASTATE, ' +
      '       DATEDIFF(SECOND, a.MON$TIMESTAMP, CURRENT_TIMESTAMP) AS AGE_S, ' +
      '       (SELECT FIRST 1 s.MON$SQL_TEXT FROM MON$STATEMENTS s ' +
      '         WHERE s.MON$ATTACHMENT_ID = a.MON$ATTACHMENT_ID AND s.MON$STATE = 1 ' +
      '         ORDER BY s.MON$TIMESTAMP DESC) AS CUR_SQL, ' +
      '       (SELECT FIRST 1 DATEDIFF(SECOND, s.MON$TIMESTAMP, CURRENT_TIMESTAMP) ' +
      '          FROM MON$STATEMENTS s ' +
      '         WHERE s.MON$ATTACHMENT_ID = a.MON$ATTACHMENT_ID AND s.MON$STATE = 1 ' +
      '         ORDER BY s.MON$TIMESTAMP DESC) AS SQL_AGE_S ' +
      'FROM MON$ATTACHMENTS a ORDER BY a.MON$ATTACHMENT_ID');
    try
      while not Q.Eof do
      begin
        T := Default(TAttachmentInfo);
        T.AttachmentID := Q.FieldByName('AID').AsLargeInt;
        T.UserName := Q.FieldByName('AUSER').AsString;
        T.RemoteAddress := Q.FieldByName('ADDR').AsString;
        T.RemoteProcess := Q.FieldByName('PROC').AsString;
        T.Active := Q.FieldByName('ASTATE').AsInteger = 1;
        T.ConnectedSeconds := Q.FieldByName('AGE_S').AsLargeInt;
        T.CurrentSQL := Q.FieldByName('CUR_SQL').AsString.Trim;
        if T.CurrentSQL.Length > SQL_TEXT_LIMIT then
          T.CurrentSQL := T.CurrentSQL.Substring(0, SQL_TEXT_LIMIT) + '...';
        if not Q.FieldByName('SQL_AGE_S').IsNull then
          T.StatementSeconds := Q.FieldByName('SQL_AGE_S').AsLargeInt;
        L.Add(T);
        Q.Next;
      end;
    finally
      Q.Free;
    end;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function TFirebirdAttachments.Analyze(AIdleMinutes, ALongStatementSeconds: Integer): TArray<TAdvisory>;
var
  L: TList<TAdvisory>;
  T: TAttachmentInfo;
  lAll: TArray<TAttachmentInfo>;
  lIdle: Integer;
begin
  L := TList<TAdvisory>.Create;
  try
    if not FCaps.HasMonTables then
    begin
      L.Add(TAdvisory.Make(
        'Monitoring tables (MON$*) are not available on this engine version.',
        '-- n/a', '-- n/a', 'info'));
      Exit(L.ToArray);
    end;

    lAll := List;
    lIdle := 0;
    for T in lAll do
    begin
      if (not T.Active) and (T.ConnectedSeconds > AIdleMinutes * 60) then
        Inc(lIdle);
      if T.StatementSeconds > ALongStatementSeconds then
        L.Add(TAdvisory.Make(
          Format('Attachment %d (%s from %s) has been running one statement for %d seconds: %s',
            [T.AttachmentID, T.UserName,
             IfEmpty(T.RemoteAddress, 'local'), T.StatementSeconds, T.CurrentSQL]),
          '',
          'Re-run fb_monitor_attachments: a statement that is finished will no longer appear.',
          'warning'));
    end;

    if lIdle > 1 then
      L.Add(TAdvisory.Make(
        Format('%d attachments have been connected and idle for more than %d minutes. ' +
          'Idle attachments each hold a connection slot and memory; a pool that never ' +
          'shrinks and an application that never disconnects look the same from here.',
          [lIdle, AIdleMinutes]),
        '',
        'Re-run fb_monitor_attachments after the application has been quiet: a healthy ' +
        'pool keeps the count steady, a leak grows it.',
        'info'));

    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

end.
