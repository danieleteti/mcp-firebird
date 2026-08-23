// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit Firebird.SecurityAudit;

{ Who may do what inside this database, and which of those answers is a mistake.

  Everything here is read from RDB$USER_PRIVILEGES and RDB$ROLES — the grants the database
  itself records, which is the whole of what an ordinary SQL connection can see. The security
  database is a different attach: the user list, the admin roles and the authentication settings
  are not here, and a report that stayed silent about that would read as "your security is
  fine" when it means "this is the half I can see". Analyze says so.

  It answers with grants, not with a verdict on people: an account that should not exist is
  invisible from in here, and PUBLIC is the one grantee whose membership needs no account at
  all — which is why it is the finding that leads. }

interface

uses Firebird.Connection, Firebird.Advisory;

type
  { Every privilege one grantee holds on one object, merged into a single line. The system
    stores one row per privilege letter; nobody reads a schema one letter at a time. }
  TGrantSummary = record
    Grantee: string;
    { Firebird records what kind of thing the grantee is; a grant to a role spreads to everyone
      who can assume it, which is not the same risk as a grant to one user. }
    GranteeIsRole: Boolean;
    ObjectName: string;
    ObjectKind: string;   // 'table', 'view', 'procedure', 'role'
    Privileges: string;   // 'SELECT, INSERT'
    { True when the privileges include one that changes data. }
    Writes: Boolean;
    { The holder can grant this on to somebody else, with no DBA involved. }
    WithGrantOption: Boolean;
    Grantor: string;
  end;

  TRoleInfo = record
    RoleName: string;
    Owner: string;
    Members: TArray<string>;
  end;

  TFirebirdSecurityAudit = class
  private
    FConn: TFirebirdConnection;
  public
    constructor Create(AConn: TFirebirdConnection);
    { Grants on user objects, one row per (grantee, object).

      Two kinds of row are left out, for the same reason: nobody granted them, and listing them
      buries the ones somebody did. The privileges on RDB$ and MON$ are the engine's own; and
      every object's owner holds everything on it by definition, recorded as a grant from the
      owner to the owner. On a schema of two hundred tables those two rules are the difference
      between a report and a dump. }
    function Grants: TArray<TGrantSummary>;
    { User-defined roles and who is a member of each. }
    function Roles: TArray<TRoleInfo>;
    function Analyze: TArray<TAdvisory>;
  end;

implementation

uses System.SysUtils, System.StrUtils, System.Generics.Collections, FireDAC.Comp.Client;

{ RDB$OBJECT_TYPE: 0 is a relation (table or view), 5 a stored procedure, 13 a role. Later
  engines number more kinds; the three below are the ones that exist unchanged from 2.5 on, and
  an unknown kind is skipped rather than mislabelled. }
const
  OBJ_RELATION = 0;
  OBJ_PROCEDURE = 5;
  OBJ_ROLE = 13;

{ RDB$USER_TYPE 13 is a role, 8 a user. }
const USER_TYPE_ROLE = 13;

function PrivilegeName(const ALetter: string): string;
begin
  if ALetter = 'S' then Result := 'SELECT'
  else if ALetter = 'I' then Result := 'INSERT'
  else if ALetter = 'U' then Result := 'UPDATE'
  else if ALetter = 'D' then Result := 'DELETE'
  else if ALetter = 'R' then Result := 'REFERENCES'
  else if ALetter = 'X' then Result := 'EXECUTE'
  else if ALetter = 'M' then Result := 'MEMBER OF'
  { 3.0 added DDL privileges (ALTER ANY, CREATE, DROP) and 4.0 more. An unmapped letter is
    reported as itself: a privilege nobody here recognises still says a grant exists. }
  else Result := ALetter;
end;

{ Appends APriv to a comma-separated list unless it is already a whole item of it. Substring
  matching would be wrong here: a DDL privilege reported as its bare letter, 'A', is a substring
  of UPDATE, and the grant would silently vanish from the report. }
procedure AddPrivilege(var AList: string; const APriv: string);
begin
  if AList = '' then
    AList := APriv
  else if not (', ' + AList + ', ').Contains(', ' + APriv + ', ') then
    AList := AList + ', ' + APriv;
end;

function IsSystemObject(const AName: string): Boolean;
begin
  Result := AName.StartsWith('RDB$') or AName.StartsWith('MON$') or AName.StartsWith('SEC$');
end;

constructor TFirebirdSecurityAudit.Create(AConn: TFirebirdConnection);
begin
  inherited Create;
  FConn := AConn;
end;

function TFirebirdSecurityAudit.Grants: TArray<TGrantSummary>;
var
  Q: TFDQuery;
  lByKey: TDictionary<string, Integer>;
  lList: TList<TGrantSummary>;
  lRec: TGrantSummary;
  lKey, lPriv, lObj: string;
  lIdx: Integer;
  lType: Integer;
begin
  lList := TList<TGrantSummary>.Create;
  lByKey := TDictionary<string, Integer>.Create;
  try
    Q := FConn.OpenQuery(Format(
      'SELECT TRIM(p.rdb$user), COALESCE(p.rdb$user_type, 0), TRIM(p.rdb$relation_name), ' +
      '       p.rdb$object_type, TRIM(p.rdb$privilege), COALESCE(p.rdb$grant_option, 0), ' +
      '       TRIM(COALESCE(p.rdb$grantor, '''')), ' +
      { A view and a table are the same object type to the privilege system and two different
        things to whoever reads the report: granting SELECT on a view is how you replace a
        grant on the table underneath it. }
      '       IIF(r.rdb$view_blr IS NULL, 0, 1) ' +
      'FROM rdb$user_privileges p ' +
      'LEFT JOIN rdb$relations r ON r.rdb$relation_name = p.rdb$relation_name ' +
      'WHERE p.rdb$object_type IN (%d, %d, %d) ' +
      { Creating a table grants its owner everything on it, from itself to itself. That is not
        a decision anybody made about access. }
      '  AND TRIM(p.rdb$user) <> TRIM(COALESCE(p.rdb$grantor, '''')) ' +
      'ORDER BY 1, 3', [OBJ_RELATION, OBJ_PROCEDURE, OBJ_ROLE]));
    try
      while not Q.Eof do
      begin
        lObj := Q.Fields[2].AsString;
        lType := Q.Fields[3].AsInteger;
        if IsSystemObject(lObj) then
        begin
          Q.Next;
          Continue;
        end;
        lKey := Q.Fields[0].AsString + '|' + lObj;
        lPriv := PrivilegeName(Q.Fields[4].AsString);
        if lByKey.TryGetValue(lKey, lIdx) then
        begin
          lRec := lList[lIdx];
          AddPrivilege(lRec.Privileges, lPriv);
        end
        else
        begin
          lRec := Default(TGrantSummary);
          lRec.Grantee := Q.Fields[0].AsString;
          lRec.GranteeIsRole := Q.Fields[1].AsInteger = USER_TYPE_ROLE;
          lRec.ObjectName := lObj;
          case lType of
            OBJ_PROCEDURE: lRec.ObjectKind := 'procedure';
            OBJ_ROLE: lRec.ObjectKind := 'role';
          else
            if Q.Fields[7].AsInteger = 1 then
              lRec.ObjectKind := 'view'
            else
              lRec.ObjectKind := 'table';
          end;
          lRec.Privileges := lPriv;
          lRec.Grantor := Q.Fields[6].AsString;
          lIdx := lList.Add(lRec);
          lByKey.Add(lKey, lIdx);
        end;
        lRec.Writes := lRec.Writes or (lPriv = 'INSERT') or (lPriv = 'UPDATE') or (lPriv = 'DELETE');
        lRec.WithGrantOption := lRec.WithGrantOption or (Q.Fields[5].AsInteger <> 0);
        lList[lIdx] := lRec;
        Q.Next;
      end;
    finally
      Q.Free;
    end;
    Result := lList.ToArray;
  finally
    lByKey.Free;
    lList.Free;
  end;
end;

function TFirebirdSecurityAudit.Roles: TArray<TRoleInfo>;
var
  Q: TFDQuery;
  lList: TList<TRoleInfo>;
  lRec: TRoleInfo;
  lIdx: Integer;
begin
  lList := TList<TRoleInfo>.Create;
  try
    Q := FConn.OpenQuery(
      'SELECT TRIM(r.rdb$role_name), TRIM(COALESCE(r.rdb$owner_name, '''')) ' +
      'FROM rdb$roles r WHERE COALESCE(r.rdb$system_flag, 0) = 0 ORDER BY 1');
    try
      while not Q.Eof do
      begin
        lRec := Default(TRoleInfo);
        lRec.RoleName := Q.Fields[0].AsString;
        lRec.Owner := Q.Fields[1].AsString;
        if not IsSystemObject(lRec.RoleName) then
          lList.Add(lRec);
        Q.Next;
      end;
    finally
      Q.Free;
    end;
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
  { Membership after the cursor is closed: one open query at a time, the same rule the rest of
    the introspection follows so every engine in the matrix behaves the same. }
  for lIdx := 0 to High(Result) do
  begin
    Q := FConn.OpenQuery(Format(
      'SELECT TRIM(p.rdb$user) FROM rdb$user_privileges p ' +
      'WHERE p.rdb$object_type = %d AND TRIM(p.rdb$relation_name) = %s ORDER BY 1',
      [OBJ_ROLE, QuotedStr(Result[lIdx].RoleName)]));
    try
      while not Q.Eof do
      begin
        Result[lIdx].Members := Result[lIdx].Members + [Q.Fields[0].AsString];
        Q.Next;
      end;
    finally
      Q.Free;
    end;
  end;
end;

function TFirebirdSecurityAudit.Analyze: TArray<TAdvisory>;
var
  Advs: TList<TAdvisory>;
  G: TGrantSummary;
  R: TRoleInfo;
  lObjectRef: string;
  lIsMembership: Boolean;
begin
  Advs := TList<TAdvisory>.Create;
  try
    for G in Grants do
    begin
      if G.ObjectKind = 'procedure' then
        lObjectRef := 'PROCEDURE ' + G.ObjectName
      else
        lObjectRef := G.ObjectName;
      { Role membership is not granted ON anything: `REVOKE MEMBER OF ON X FROM Y` is not a
        statement. Every remedy below is meant to be run as printed, so the one case that needs
        different syntax gets it. }
      lIsMembership := G.ObjectKind = 'role';

      { PUBLIC is not a group somebody was added to. It is everyone who can open a connection,
        including every account created after the grant was made. }
      if G.Grantee = 'PUBLIC' then
        Advs.Add(TAdvisory.Make(
          Format('PUBLIC holds %s on %s. That is every account that can attach to this database, ' +
            'including the ones created after this grant%s.',
            [G.Privileges, G.ObjectName,
             IfThen(G.Writes, ', and it includes changing the data', '')]),
          IfThen(lIsMembership,
            Format('REVOKE %s FROM PUBLIC;', [G.ObjectName]),
            Format('REVOKE %s ON %s FROM PUBLIC;', [G.Privileges, lObjectRef])),
          'Re-run fb_audit_security; PUBLIC should no longer appear for this object. ' +
          'Grant the same privileges to a role first, and the role to the accounts that need it.',
          IfThen(G.Writes, 'critical', 'warning')));

      { A grant option is delegation: the holder can widen access without a DBA ever seeing it,
        and the grant that results looks exactly like one an administrator made. }
      if G.WithGrantOption and (G.Grantee <> 'SYSDBA') and (G.Grantee <> G.Grantor) then
        Advs.Add(TAdvisory.Make(
          Format('%s holds %s on %s WITH GRANT OPTION, granted by %s: it can pass these ' +
            'privileges on to anyone, and nothing here will record that it did.',
            [G.Grantee, G.Privileges, G.ObjectName, IfThen(G.Grantor = '', 'an unnamed grantor', G.Grantor)]),
          IfThen(lIsMembership,
            Format('REVOKE ADMIN OPTION FOR %s FROM %s;', [G.ObjectName, G.Grantee]),
            Format('REVOKE GRANT OPTION FOR %s ON %s FROM %s;',
              [G.Privileges, lObjectRef, G.Grantee])),
          'Re-run fb_audit_security; the grant should remain, without the grant option.',
          'warning'));
    end;

    for R in Roles do
      if Length(R.Members) = 0 then
        Advs.Add(TAdvisory.Make(
          Format('Role %s has no members. Either the privileges it carries are unused, or the ' +
            'accounts that were supposed to hold them are holding direct grants instead.',
            [R.RoleName]),
          Format('-- Grant it to the accounts that need it, or drop it:' + sLineBreak +
                 '-- GRANT %0:s TO <user>;' + sLineBreak + 'DROP ROLE %0:s;', [R.RoleName]),
          'Re-run fb_audit_security; the role should either have members or be gone.',
          'info'));

    Result := Advs.ToArray;
  finally
    Advs.Free;
  end;
end;

end.
