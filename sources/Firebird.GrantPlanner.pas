// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit Firebird.GrantPlanner;

{ "Give APP read access to the TBL_* tables, and nothing else" — as statements.

  The statements are the easy half. Anything can write `GRANT SELECT ON X TO Y`; what makes the
  answer right or wrong is everything around it:

  - **The object list comes from the catalogue.** A name that is not in RDB$RELATIONS is not a
    table, it is a guess, and a plan built out of guesses fails halfway through with three of
    nine statements already committed.
  - **Identifiers are quoted when they need to be and not when they do not.** Firebird folds an
    unquoted name to upper case; a table created as "tbl_Mixed" is unreachable by TBL_MIXED, and
    quoting everything makes the plan unreadable to a DBA who has to check it.
  - **"And nothing else" is a claim about the grants that already exist.** A plan that grants APP
    exactly the TBL_* tables gives it the whole database anyway if PUBLIC holds SELECT on the
    rest. That check is the reason this is a tool and not a sentence in a prompt.
  - **Privileges go to a role, and the role to the account.** One place to look, one place to
    revoke, and the next account that needs the same access is one statement, not nine.

  What it cannot do is see accounts: whether APP already exists lives in the security database,
  which an ordinary SQL connection does not attach to. So the CREATE USER is offered as a
  conditional, and the plan says why. }

interface

uses Firebird.Connection, Firebird.Advisory;

type
  TGrantTarget = record
    Name: string;
    Kind: string;   // 'table' | 'view' | 'procedure'
  end;

  TGrantPlan = record
    UserName: string;
    RoleName: string;
    { The LIKE pattern actually applied, after the glob was translated. }
    Pattern: string;
    { The pattern subtracted from it, empty when nothing was excluded. }
    ExcludePattern: string;
    Access: string;   // 'read' | 'readwrite'
    Targets: TArray<TGrantTarget>;
    { The plan, in the order it must be run. }
    Statements: TArray<string>;
    { Grants that already exist and defeat the word "only": PUBLIC on an object outside the
      pattern, or a grant this same account already holds elsewhere. Each carries the REVOKE
      that closes it. }
    Conflicts: TArray<TAdvisory>;
    { What the plan assumes, and what this server could not check. }
    Notes: TArray<string>;
    { True when the role already exists, so the plan skips creating it. }
    RoleExists: Boolean;
  end;

const
  ACCESS_READ = 'read';
  ACCESS_READWRITE = 'readwrite';
  { Never a usable password. A plan that a DBA can run without reading it is a plan that puts a
    known password on a new account. }
  PASSWORD_PLACEHOLDER = 'change-this-before-running';
  { A plan longer than this is not read, it is pasted. The cap is announced in the notes: a
    silent truncation would read as "these are all the objects that matched". }
  MAX_PLAN_TARGETS = 200;

{ Translates a caller's pattern into a Firebird LIKE pattern with `\` as the escape character.

  `*` and `%` both mean "any sequence" — people who think in globs and people who think in SQL
  both get what they meant — `?` means one character, and `_` is a literal underscore rather
  than the wildcard SQL would make of it, because somebody asking for `tbl_*` is naming a
  prefix, not asking for TBLX. A pattern in double quotes keeps its case; anything else is
  folded to upper case, the way Firebird folds an unquoted identifier. }
function TranslatePattern(const APattern: string): string;

{ Wraps AName in double quotes only if Firebird could not otherwise find the object under that
  name: a lower-case letter, a space, anything outside A-Z 0-9 _ $, or a leading digit. }
function QuoteIfNeeded(const AName: string): string;

{ Builds the plan. AExcludePattern, when given, is subtracted from the match — "everything the
  application uses except the audit log" is a rule people really have, and expressing it as a
  pattern they have to write in the negative is how an audit log ends up granted.

  Raises nothing for an empty match: a pattern that matches no object is an answer, and the plan
  says so in Notes. }
function PlanGrants(AConn: TFirebirdConnection;
  const AUserName, APattern, AAccess, ARoleName, AExcludePattern: string): TGrantPlan;

implementation

uses System.SysUtils, System.StrUtils, System.Generics.Collections,
  FireDAC.Comp.Client, Firebird.Capabilities, Firebird.Introspection, Firebird.SecurityAudit;

const
  READ_PRIVILEGES = 'SELECT';
  WRITE_PRIVILEGES = 'SELECT, INSERT, UPDATE, DELETE';

function TranslatePattern(const APattern: string): string;
var
  lSource: string;
  lCh: Char;
  SB: TStringBuilder;
begin
  lSource := APattern.Trim;
  if lSource = '' then
    lSource := '*';
  if lSource.StartsWith('"') and lSource.EndsWith('"') and (lSource.Length >= 2) then
    lSource := lSource.Substring(1, lSource.Length - 2)
  else
    lSource := lSource.ToUpper;

  SB := TStringBuilder.Create;
  try
    for lCh in lSource do
      case lCh of
        '*', '%': SB.Append('%');
        '?': SB.Append('_');
        '_': SB.Append('\_');
        '\': SB.Append('\\');
      else
        SB.Append(lCh);
      end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function QuoteIfNeeded(const AName: string): string;
var
  lIdx: Integer;
  lPlain: Boolean;
begin
  lPlain := AName <> '';
  for lIdx := 1 to AName.Length do
    if not (CharInSet(AName[lIdx], ['A' .. 'Z', '0' .. '9', '_', '$'])) then
      lPlain := False;
  if lPlain and CharInSet(AName[1], ['0' .. '9', '$']) then
    lPlain := False;
  if lPlain then
    Result := AName
  else
    Result := QuoteIdent(AName);
end;

{ The object as it is written in a GRANT: a procedure needs the keyword, a table and a view do
  not, and every name goes through the quoting rule. }
function GrantRef(const ATarget: TGrantTarget): string;
begin
  if ATarget.Kind = 'procedure' then
    Result := 'PROCEDURE ' + QuoteIfNeeded(ATarget.Name)
  else
    Result := QuoteIfNeeded(ATarget.Name);
end;

function MatchTargets(AConn: TFirebirdConnection; const ALikePattern: string): TArray<TGrantTarget>;
var
  Q: TFDQuery;
  L: TList<TGrantTarget>;
  R: TGrantTarget;
begin
  L := TList<TGrantTarget>.Create;
  try
    { TRIM before LIKE: these columns are CHAR, and a pattern that does not end in a wildcard
      would never match the padding. }
    Q := AConn.OpenQuery(Format(
      'SELECT TRIM(r.rdb$relation_name), IIF(r.rdb$view_blr IS NULL, ''table'', ''view'') ' +
      'FROM rdb$relations r ' +
      'WHERE COALESCE(r.rdb$system_flag, 0) = 0 ' +
      '  AND TRIM(r.rdb$relation_name) LIKE %0:s ESCAPE ''\'' ' +
      'UNION ALL ' +
      'SELECT TRIM(p.rdb$procedure_name), ''procedure'' ' +
      'FROM rdb$procedures p ' +
      'WHERE COALESCE(p.rdb$system_flag, 0) = 0 ' +
      { A packaged procedure is not granted on its own — the package is the unit of privilege —
        and RDB$PACKAGE_NAME does not exist before 3.0, so the clause is added only where the
        column is. }
      IfThen(TFirebirdCapabilities.Detect(AConn).HasPackages,
             '  AND p.rdb$package_name IS NULL ', '') +
      '  AND TRIM(p.rdb$procedure_name) LIKE %0:s ESCAPE ''\'' ' +
      'ORDER BY 1', [QuotedStr(ALikePattern)]));
    try
      while not Q.Eof do
      begin
        R := Default(TGrantTarget);
        R.Name := Q.Fields[0].AsString;
        R.Kind := Q.Fields[1].AsString;
        L.Add(R);
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

{ ATargets minus AExcluded, by name. }
function Subtract(const ATargets, AExcluded: TArray<TGrantTarget>): TArray<TGrantTarget>;
var L: TList<TGrantTarget>; T, X: TGrantTarget; lDrop: Boolean;
begin
  L := TList<TGrantTarget>.Create;
  try
    for T in ATargets do
    begin
      lDrop := False;
      for X in AExcluded do
        if SameText(T.Name, X.Name) then
        begin
          lDrop := True;
          Break;
        end;
      if not lDrop then
        L.Add(T);
    end;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

{ Exact comparison, not SameText: a quoted identifier is case-sensitive, so "tbl_Mixed" and
  TBL_MIXED are two different objects and only one of them is in the plan. }
function IsTarget(const ATargets: TArray<TGrantTarget>; const AName: string): Boolean;
var T: TGrantTarget;
begin
  for T in ATargets do
    if T.Name = AName then
      Exit(True);
  Result := False;
end;

function RoleAlreadyExists(AConn: TFirebirdConnection; const ARole: string): Boolean;
begin
  Result := AConn.ScalarStr(
    'SELECT TRIM(rdb$role_name) FROM rdb$roles WHERE TRIM(rdb$role_name) = ' +
    QuotedStr(ARole)) <> '';
end;

function PlanGrants(AConn: TFirebirdConnection;
  const AUserName, APattern, AAccess, ARoleName, AExcludePattern: string): TGrantPlan;
var
  lStatements: TList<string>;
  lNotes: TList<string>;
  lConflicts: TList<TAdvisory>;
  lPrivileges: string;
  T: TGrantTarget;
  lAudit: TFirebirdSecurityAudit;
  G: TGrantSummary;
  lTables, lViews, lProcs, lMatched: Integer;
  lAccessWasUnderstood: Boolean;
  lExcluded: TArray<TGrantTarget>;
  lCaps: TFirebirdCapabilities;
begin
  Result := Default(TGrantPlan);
  Result.UserName := AUserName.Trim.ToUpper;
  if Result.UserName = '' then
    raise Exception.Create('A grant plan needs an account name: pass user_name.');
  Result.Access := IfThen(SameText(AAccess.Trim, ACCESS_READWRITE), ACCESS_READWRITE, ACCESS_READ);
  lAccessWasUnderstood := (AAccess.Trim = '') or SameText(AAccess.Trim, ACCESS_READ) or
    SameText(AAccess.Trim, ACCESS_READWRITE);
  Result.RoleName := ARoleName.Trim.ToUpper;
  if Result.RoleName = '' then
    Result.RoleName := Result.UserName + '_ROLE';
  Result.Pattern := TranslatePattern(APattern);
  Result.Targets := MatchTargets(AConn, Result.Pattern);
  if AExcludePattern.Trim <> '' then
  begin
    Result.ExcludePattern := TranslatePattern(AExcludePattern);
    lExcluded := MatchTargets(AConn, Result.ExcludePattern);
    Result.Targets := Subtract(Result.Targets, lExcluded);
  end;
  lMatched := Length(Result.Targets);
  if lMatched > MAX_PLAN_TARGETS then
    SetLength(Result.Targets, MAX_PLAN_TARGETS);
  Result.RoleExists := RoleAlreadyExists(AConn, Result.RoleName);
  lCaps := TFirebirdCapabilities.Detect(AConn);

  if Result.Access = ACCESS_READWRITE then
    lPrivileges := WRITE_PRIVILEGES
  else
    lPrivileges := READ_PRIVILEGES;

  lStatements := TList<string>.Create;
  lNotes := TList<string>.Create;
  lConflicts := TList<TAdvisory>.Create;
  try
    if Length(Result.Targets) = 0 then
    begin
      lNotes.Add(Format('No table, view or procedure matches %s, so there is nothing to grant. ' +
        'Check the pattern against fb_list_tables — Firebird folds unquoted names to upper case, ' +
        'and a name created in mixed case has to be given in double quotes.', [Result.Pattern]));
      Result.Notes := lNotes.ToArray;
      Exit;
    end;

    { The account first, because everything after it refers to the account. Conditional, not
      because it is optional but because this server cannot see whether it is needed — and
      skipped entirely for the one account that certainly exists and cannot be constrained. }
    if Result.UserName = 'SYSDBA' then
      lNotes.Add('SYSDBA is not subject to privileges. Every statement below is accepted and ' +
        'none of them changes what SYSDBA can do — it already can do everything, and so can the ' +
        'owner of an object. If the aim is to limit an application, the plan is to give it its ' +
        'own account and move the connection onto it, not to grant SYSDBA less.')
    else
    begin
      lStatements.Add(Format('-- Only if %s does not exist yet (this server cannot see the account list):',
        [Result.UserName]));
      lStatements.Add(Format('CREATE USER %s PASSWORD ''%s'';',
        [QuoteIfNeeded(Result.UserName), PASSWORD_PLACEHOLDER]));
    end;
    if Result.RoleExists then
      lStatements.Add(Format('-- Role %s already exists; the grants below add to it.', [Result.RoleName]))
    else
      lStatements.Add(Format('CREATE ROLE %s;', [QuoteIfNeeded(Result.RoleName)]));

    lTables := 0; lViews := 0; lProcs := 0;
    for T in Result.Targets do
    begin
      if T.Kind = 'procedure' then
      begin
        Inc(lProcs);
        lStatements.Add(Format('GRANT EXECUTE ON %s TO %s;',
          [GrantRef(T), QuoteIfNeeded(Result.RoleName)]));
      end
      else
      begin
        if T.Kind = 'view' then Inc(lViews) else Inc(lTables);
        lStatements.Add(Format('GRANT %s ON %s TO %s;',
          [lPrivileges, GrantRef(T), QuoteIfNeeded(Result.RoleName)]));
      end;
    end;

    { The statement that decides whether any of the above has an effect. A Firebird role is
      inactive unless the connection asks for it by name, so on 3.0 and below the application's
      connection string has to carry it; 4.0 added DEFAULT roles, which is the same intent
      expressed where it cannot be forgotten. }
    if lCaps.HasDefaultRoles then
      lStatements.Add(Format('GRANT DEFAULT %s TO USER %s;',
        [QuoteIfNeeded(Result.RoleName), QuoteIfNeeded(Result.UserName)]))
    else
      lStatements.Add(Format('GRANT %s TO %s;',
        [QuoteIfNeeded(Result.RoleName), QuoteIfNeeded(Result.UserName)]));

    lNotes.Add(Format('%d table(s), %d view(s) and %d procedure(s) matched %s%s.',
      [lTables, lViews, lProcs, Result.Pattern,
       IfThen(Result.ExcludePattern = '', '',
              Format(', after subtracting %s', [Result.ExcludePattern]))]));
    if lMatched > MAX_PLAN_TARGETS then
      lNotes.Add(Format('%d objects matched and only the first %d are in the plan. A pattern ' +
        'this wide is not an access rule, it is the whole schema: narrow it, or decide that ' +
        'this account really does get everything and say so deliberately.',
        [lMatched, MAX_PLAN_TARGETS]));
    lNotes.Add('Run these as SYSDBA or as the owner of the objects; CREATE USER needs an ' +
      'administrator whatever database you are attached to.');
    if lCaps.HasDefaultRoles then
      lNotes.Add(Format('%0:s is granted as a DEFAULT role (%1:s), so it is active on every ' +
        'connection %2:s makes without the application asking for it. If you would rather the ' +
        'application ask, use GRANT %0:s TO %2:s instead and pass the role at connect time.',
        [Result.RoleName, lCaps.EngineVersion, Result.UserName]))
    else
      lNotes.Add(Format('On %s a role is active only when the connection asks for it: the ' +
        'application must pass %s as its role (FireDAC: add RoleName=%s to the connection ' +
        'parameters; isql: -role %s). Without it %s connects with no privileges at all and ' +
        'every statement above has no effect. DEFAULT roles, which remove this step, arrived ' +
        'in 4.0.',
        [lCaps.EngineVersion, Result.RoleName, Result.RoleName, Result.RoleName, Result.UserName]));
    if Result.UserName <> 'SYSDBA' then
      lNotes.Add(Format('The password above is a placeholder, not a suggestion. Replace it ' +
        'before you run the statement, and if %s already exists, drop that line instead.',
        [Result.UserName]));
    if not lAccessWasUnderstood then
      lNotes.Add(Format('access was given as "%s", which is not a value this understands: the ' +
        'plan above is %s. The two it takes are read and readwrite.', [AAccess.Trim, Result.Access]));
    if Result.Access = ACCESS_READWRITE then
      lNotes.Add('The write privileges are granted on views as well as tables. A view takes a ' +
        'write only if it is naturally updatable or has triggers that do it; the grant is ' +
        'accepted either way, and a view that cannot take one will refuse at run time.');

    { "And nothing else." Everything above decides what the account can reach *through this
      plan*; only the grants already in the database decide what it can reach at all. }
    lAudit := TFirebirdSecurityAudit.Create(AConn);
    try
      for G in lAudit.Grants do
      begin
        if G.ObjectKind = 'role' then
          Continue;
        if IsTarget(Result.Targets, G.ObjectName) then
          Continue;
        if G.Grantee = 'PUBLIC' then
          lConflicts.Add(TAdvisory.Make(
            Format('%s will also reach %s, which is outside this plan: PUBLIC holds %s on it, ' +
              'and %s is a member of PUBLIC like every other account.',
              [Result.UserName, G.ObjectName, G.Privileges, Result.UserName]),
            Format('REVOKE %s ON %s FROM PUBLIC;',
              [G.Privileges, IfThen(G.ObjectKind = 'procedure', 'PROCEDURE ', '') + QuoteIfNeeded(G.ObjectName)]),
            Format('Re-run fb_suggest_grants for %s; this object should no longer be listed as ' +
              'reachable outside the plan.', [Result.UserName]),
            IfThen(G.Writes, 'critical', 'warning')))
        else if SameText(G.Grantee, Result.UserName) or SameText(G.Grantee, Result.RoleName) then
          lConflicts.Add(TAdvisory.Make(
            Format('%s already holds %s on %s, which is outside this plan.',
              [G.Grantee, G.Privileges, G.ObjectName]),
            Format('REVOKE %s ON %s FROM %s;',
              [G.Privileges,
               IfThen(G.ObjectKind = 'procedure', 'PROCEDURE ', '') + QuoteIfNeeded(G.ObjectName),
               QuoteIfNeeded(G.Grantee)]),
            'Re-run fb_suggest_grants; the grant should be gone.',
            'warning'));
      end;
    finally
      lAudit.Free;
    end;

    Result.Statements := lStatements.ToArray;
    Result.Notes := lNotes.ToArray;
    Result.Conflicts := lConflicts.ToArray;
  finally
    lStatements.Free;
    lNotes.Free;
    lConflicts.Free;
  end;
end;

end.
