unit EngineConfigU;
interface
procedure ConfigureServerIdentity;
implementation
uses MVCFramework.MCP.Server;
procedure ConfigureServerIdentity;
begin
  TMCPServer.Instance.ServerName := 'mcp-firebird';
  TMCPServer.Instance.ServerVersion := '0.1.0';
end;
end.
