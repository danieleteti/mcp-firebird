program MCPFirebird;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  MVCFramework.MCP.Server,
  MVCFramework.MCP.Stdio,
  MVCFramework.MCP.StdioOnly,
  BootConfigU in 'BootConfigU.pas',
  EngineConfigU in 'EngineConfigU.pas';
var
  LTransport: TMCPStdioTransport;
begin
  Boot;
  ConfigureServerIdentity;
  LTransport := TMCPStdioTransport.Create(TMCPServer.Instance);
  try
    try
      LTransport.Run;
    except
      on E: Exception do
        System.Write(ErrOutput, E.ClassName + ': ' + E.Message + sLineBreak);
    end;
  finally
    LTransport.Free;
  end;
end.
