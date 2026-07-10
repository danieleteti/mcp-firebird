// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit FirebirdResourcesU;
interface
uses MVCFramework.MCP.ResourceProvider, MVCFramework.MCP.Attributes;
type
  TFirebirdResources = class(TMCPResourceProvider)
  public
    [MCPResource('firebird://schema', 'Database schema', 'Full Markdown schema of the configured database', 'text/markdown')]
    function Schema(const URI: string): TMCPResourceResult;
  end;
implementation
uses
  Firebird.Connection, Firebird.Introspection, Firebird.DocGen, FirebirdConfigU,
  MVCFramework.MCP.Server;

function TFirebirdResources.Schema(const URI: string): TMCPResourceResult;
var Conn: TFirebirdConnection; D: TFirebirdDocGen;
begin
  Conn := NewConfiguredConnection;
  try
    D := TFirebirdDocGen.Create(TFirebirdIntrospection.Create(Conn));
    try Result := TMCPResourceResult.Text(URI, D.DatabaseMarkdown, 'text/markdown');
    finally D.Free; end;
  finally Conn.Free; end;
end;

initialization
  TMCPServer.Instance.RegisterResourceProvider(TFirebirdResources);
end.
