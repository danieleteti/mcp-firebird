// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit EngineConfigU;
interface
procedure ConfigureServerIdentity;
implementation
uses
  MVCFramework.MCP.Server;
procedure ConfigureServerIdentity;
begin
  TMCPServer.Instance.ServerName := 'mcp-firebird';
  TMCPServer.Instance.ServerVersion := '0.7.0';
  { Sent once in the initialize reply; the client decides whether the model sees it. Facts about
    the server, not orders to the model: text that reads like a command is what clients learn to
    filter, and it is the shape a hostile server's description would take. }
  TMCPServer.Instance.ServerInstructions :=
    'Firebird 2.5-5.0 DBA assistant, read-only: no tool runs DDL or write SQL, and the statements ' +
    'it prints as advice are never executed. For a slow query the usual path is fb_analyze_query ' +
    '(plan and measured cost), then fb_suggest_indexes, then fb_evaluate_goal to confirm the ' +
    'result. fb_query returns real rows from the database, so they are sensitive data. Statements ' +
    'a caller supplies are executed only if they are a plain SELECT, and the engine cancels them ' +
    'after 60 seconds (Firebird 4.0 and up). A clean plan or audit is evidence about structure, ' +
    'not proof that a query is fast or a system healthy; each tool says what it cannot see.';
end;
end.
