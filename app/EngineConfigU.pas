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
  TMCPServer.Instance.ServerVersion := '0.2.2';
end;
end.
