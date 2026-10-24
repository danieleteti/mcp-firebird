// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit Firebird.Connection;
interface
uses
  FireDAC.Comp.Client, FireDAC.Phys.FB, FireDAC.Phys.FBDef, FireDAC.Stan.Def,
  FireDAC.Stan.Async, FireDAC.DApt, FireDAC.Stan.Param, Data.DB;
type
  TFirebirdConnectionConfig = record
    Host: string;
    Port: Integer;
    Database: string;
    User: string;
    Password: string;
    Charset: string;
    ClientLib: string;
    { Opens every transaction on this connection with the read-only TPB, so the engine itself
      refuses an INSERT/UPDATE/DELETE/DDL instead of trusting us to never send one. Off by
      default because the test suite creates and drops indexes through this same class; the
      server sets it (see FirebirdConfigU.NewConfiguredConnection) and nothing turns it back off. }
    ReadOnly: Boolean;
  end;

  TFirebirdConnection = class
  private
    FConn: TFDConnection;
    FDriverLink: TFDPhysFBDriverLink;
    FConfig: TFirebirdConnectionConfig;
  public
    constructor Create(const AConfig: TFirebirdConnectionConfig);
    destructor Destroy; override;
    procedure Connect;
    function OpenQuery(const ASQL: string): TFDQuery; overload;
    function OpenQuery(const ASQL: string; const AParams: array of Variant): TFDQuery; overload;
    { OpenQuery for SQL a caller wrote: the engine cancels it after ATimeoutMs (0 = no limit).
      Only meaningful on 4.0+ (HasStatementTimeout); the caller decides, so a 3.0 server behind a
      newer client is never asked for something it cannot do. }
    function OpenQueryLimited(const ASQL: string; ATimeoutMs: Cardinal): TFDQuery;
    function ExecSQL(const ASQL: string): Integer;
    function ScalarStr(const ASQL: string): string;
    { The MON$ tables are a snapshot, frozen when the current transaction first reads them, so
      the same transaction asked twice answers twice with the same numbers. Anything measuring
      change over time has to end the transaction between readings. }
    procedure NewMonitoringSnapshot;
    property Config: TFirebirdConnectionConfig read FConfig;
    property FDConnection: TFDConnection read FConn;
  end;

{ True only for a statement that reads. This server is read-only, but "read-only" is a property
  of the tools, not of the SQL a caller hands them: a tool that executes whatever text it is
  given to measure it would run a DELETE just as willingly as a SELECT. Everything that executes
  user-supplied SQL goes through here first. }
function IsReadOnlySelect(const ASQL: string): Boolean;

{ True when the statement carries placeholders nobody has bound.

  A prepare needs no values, so the plan for `WHERE CITY = ?` is honest. An execution is not:
  FireDAC binds an unset parameter as NULL, `CITY = NULL` matches nothing, and the measurement
  comes back as "0 rows out of 5004 records read" — which reads as the strongest possible case
  for an index, about a query nobody runs. Everything that executes caller-supplied SQL to
  measure it asks this first and reports why it did not measure. }
function HasParameters(const ASQL: string): Boolean;

{ The statement with every quoted literal replaced by one blank, so that a scan for operators,
  keywords or placeholders cannot trip over their contents. Handles the doubled quote that
  escapes a quote inside a literal. }
function StripLiterals(const ASQL: string): string;

const
  { How long the engine lets a caller's SELECT run before cancelling it. A measurement or a
    fb_query that never ends holds this single-threaded server, and the database, for as long as
    it likes; a minute is generous for a diagnosis and short for an accident. }
  STATEMENT_TIMEOUT_MS = 60000;

{ Index of the quote that closes the literal opened at AOpen (a ' or a "), or Length + 1 when it
  never closes. The doubled quote that escapes a quote inside a literal is skipped. }
function SkipLiteral(const ASQL: string; AOpen: Integer): Integer;

implementation
uses System.SysUtils, System.Classes, System.RegularExpressions;

function IsReadOnlySelect(const ASQL: string): Boolean;
var S: string;
begin
  // Deliberately narrow: SELECT and WITH, nothing else. EXECUTE BLOCK and EXECUTE PROCEDURE can
  // write; a leading comment is not unwrapped here, so a commented query is refused rather than
  // parsed — the wrong answer in that direction costs a measurement, not a table.
  S := ASQL.Trim.ToUpper;
  Result := S.StartsWith('SELECT') or S.StartsWith('WITH');
  // A generator is not transactional: the read-only TPB does not stop a SELECT from moving one.
  if Result then
    Result := not TRegEx.IsMatch(StripLiterals(S), '\bGEN_ID\s*\(|\bNEXT\s+VALUE\s+FOR\b');
end;

function SkipLiteral(const ASQL: string; AOpen: Integer): Integer;
var Quote: Char;
begin
  Quote := ASQL[AOpen];
  Result := AOpen + 1;
  while Result <= Length(ASQL) do
    if ASQL[Result] <> Quote then Inc(Result)
    else if (Result < Length(ASQL)) and (ASQL[Result + 1] = Quote) then Inc(Result, 2)
    else Exit;
end;

function StripLiterals(const ASQL: string): string;
var SB: TStringBuilder; I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    I := 1;
    while I <= Length(ASQL) do
      if CharInSet(ASQL[I], ['''', '"']) then
      begin
        I := SkipLiteral(ASQL, I) + 1;
        // One blank, not nothing: 'a' 'b' must not be spliced into a single token.
        SB.Append(' ');
      end
      else
      begin
        SB.Append(ASQL[I]);
        Inc(I);
      end;
    Result := SB.ToString;
  finally SB.Free; end;
end;

function HasParameters(const ASQL: string): Boolean;
var S: string;
begin
  // Literals first: a question mark inside a string is text, not a placeholder.
  S := StripLiterals(ASQL);
  Result := S.Contains('?') or TRegEx.IsMatch(S, ':\w');
end;

constructor TFirebirdConnection.Create(const AConfig: TFirebirdConnectionConfig);
begin
  inherited Create;
  FConfig := AConfig;
  FDriverLink := TFDPhysFBDriverLink.Create(nil);
  if AConfig.ClientLib <> '' then
    FDriverLink.VendorLib := AConfig.ClientLib;
  FConn := TFDConnection.Create(nil);
  FConn.LoginPrompt := False;
  FConn.DriverName := 'FB';
  FConn.Params.Values['Server']       := AConfig.Host;
  FConn.Params.Values['Port']         := AConfig.Port.ToString;
  FConn.Params.Values['Database']     := AConfig.Database;
  FConn.Params.Values['User_Name']    := AConfig.User;
  FConn.Params.Values['Password']     := AConfig.Password;
  FConn.Params.Values['CharacterSet'] := AConfig.Charset;
  FConn.Params.Values['Protocol']     := 'TCPIP';
  { A read-only transaction is also cheaper to leave open: under read committed the engine does
    not have to keep it in the way of garbage collection, which matters for a server that holds
    a connection open across a sampling window. }
  FConn.TxOptions.ReadOnly := AConfig.ReadOnly;
end;

destructor TFirebirdConnection.Destroy;
begin
  FConn.Free;
  FDriverLink.Free;
  inherited;
end;

procedure TFirebirdConnection.Connect;
begin
  FConn.Connected := True;
end;

function TFirebirdConnection.OpenQuery(const ASQL: string): TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  try
    Result.Connection := FConn;
    Result.Open(ASQL);
  except
    Result.Free; raise;
  end;
end;

function TFirebirdConnection.OpenQuery(const ASQL: string; const AParams: array of Variant): TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  try
    Result.Connection := FConn;
    Result.Open(ASQL, AParams);
  except
    Result.Free; raise;
  end;
end;

function TFirebirdConnection.OpenQueryLimited(const ASQL: string; ATimeoutMs: Cardinal): TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  try
    Result.Connection := FConn;
    if ATimeoutMs > 0 then Result.ResourceOptions.CmdExecTimeout := ATimeoutMs;
    Result.Open(ASQL);
  except
    Result.Free; raise;
  end;
end;

function TFirebirdConnection.ExecSQL(const ASQL: string): Integer;
begin
  Result := FConn.ExecSQL(ASQL);
end;

procedure TFirebirdConnection.NewMonitoringSnapshot;
begin
  if FConn.InTransaction then FConn.Commit;
end;

function TFirebirdConnection.ScalarStr(const ASQL: string): string;
var Q: TFDQuery;
begin
  Q := OpenQuery(ASQL);
  try
    if Q.Eof then Result := '' else Result := Q.Fields[0].AsString;
  finally Q.Free; end;
end;
end.
