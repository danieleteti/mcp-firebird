// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit FirebirdToolRuntimeU;

{ The two things every fb_* tool body needs, in both editions.

  They lived in FirebirdToolsU's implementation section until the Enterprise edition needed
  them too. Copying them across the repository boundary would have been the first crack in
  the rule that the Enterprise edition extends this one and never restates it. }

interface

uses System.SysUtils, MVCFramework.MCP.ToolProvider, Firebird.Connection, Firebird.Advisory;

{ Opens the configured connection, passes it to the tool body, frees it. Traces
  every tool invocation to the log and turns any exception (a misrouted .env, a
  database connection / communication failure, a malformed query) into a tool
  result with isError=true, so the message is returned to the MCP client and
  shown to the user — instead of bubbling up as a generic JSON-RPC -32603 that
  clients render as an opaque "Failed to call tool".

  Log trail per call (all under the 'mcp' tag):
    [INFO ] >> fb_xxx  <args>            (invocation, with the arguments received)
    [INFO ] << fb_xxx  ok|isError  NNms  (completion + elapsed time)
    [ERROR] !! fb_xxx failed - <message> (only on exception)

  Protocol errors (unknown tool, missing required param) are still raised by the
  request handler and remain JSON-RPC errors. }
function Guard(const AToolName, AArgs: string;
  const AAction: TFunc<TFirebirdConnection, TMCPToolResult>): TMCPToolResult;

{ Renders the TAdvisory shape every detector returns. New detectors that follow the
  shape need no special-casing here. }
function AdvisoriesToText(const Advs: TArray<TAdvisory>; const AEmptyMsg: string): string;

implementation

uses System.Classes, System.Diagnostics, System.StrUtils,
  FirebirdConfigU, MVCFramework.Logger;

function Guard(const AToolName, AArgs: string;
  const AAction: TFunc<TFirebirdConnection, TMCPToolResult>): TMCPToolResult;
var SW: TStopwatch; Conn: TFirebirdConnection;
begin
  LogI(Format('>> %s  %s', [AToolName, AArgs]), 'mcp');
  SW := TStopwatch.StartNew;
  try
    Conn := NewConfiguredConnection;
    try
      Result := AAction(Conn);
    finally Conn.Free; end;
    LogI(Format('<< %s  %s  %dms',
      [AToolName, IfThen(Result.IsError, 'isError', 'ok'), SW.ElapsedMilliseconds]), 'mcp');
  except
    on E: Exception do
    begin
      LogException(E, Format('!! %s failed after %dms', [AToolName, SW.ElapsedMilliseconds]));
      Result := TMCPToolResult.Error('Firebird error (' + E.ClassName + '): ' + E.Message);
    end;
  end;
end;

function AdvisoriesToText(const Advs: TArray<TAdvisory>; const AEmptyMsg: string): string;
var SB: TStringBuilder; X: TAdvisory;
begin
  if Length(Advs) = 0 then Exit(AEmptyMsg);
  SB := TStringBuilder.Create;
  try
    for X in Advs do
    begin
      SB.AppendLine('### ' + X.Severity).AppendLine('**Finding:** ' + X.Finding).AppendLine;
      // Not every finding has a runnable remedy. fb_analyze_host's do not: the answer to "your
      // page cache commits more RAM than this machine has" is a configuration change and a
      // restart, not a statement. An empty ```sql fence promises a command and delivers a blank
      // box, which reads as a tool that meant to say something and failed to.
      if Trim(X.SQLText) <> '' then
        SB.AppendLine('```sql').AppendLine(X.SQLText).AppendLine('```');
      SB.AppendLine('**Verify:** ' + X.Verify).AppendLine;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
