program MCPFirebird;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  MVCFramework.MCP.Server,
  MVCFramework.MCP.Stdio,
  MVCFramework.MCP.StdioOnly,
  BootConfigU in 'BootConfigU.pas',
  EngineConfigU in 'EngineConfigU.pas',
  FirebirdConfigU in '..\providers\FirebirdConfigU.pas',
  FirebirdToolsU in '..\providers\FirebirdToolsU.pas',
  FirebirdPromptsU in '..\providers\FirebirdPromptsU.pas',
  FirebirdResourcesU in '..\providers\FirebirdResourcesU.pas';
var
  LTransport: TMCPStdioTransport;
begin
  try
    Boot;
  except
    on E: EBootConfig do
    begin
      // Startup misconfiguration (e.g. --env pointing at a file): explain it on
      // stderr — where MCP clients surface server logs — and exit right away.
      System.Write(ErrOutput, 'MCPFirebird: ' + E.Message + sLineBreak);
      Halt(2);
    end;
  end;
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
