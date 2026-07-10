// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit FirebirdStubsU;

{ The Enterprise tools, announced but not implemented in this edition.

  The free edition only ever asks the database about itself, over FireDAC. Everything here
  needs to read the machine that hosts the engine — its configuration files, its log, its
  Trace API, its memory and CPU — which is a different product, a different risk profile and
  a different licence. See README § Editions & licensing.

  They are registered so they appear in tools/list: a user should be able to discover what
  the Enterprise edition does without reading the website. Calling one returns isError with
  the message below, which is the whole of their behaviour. No heuristic, no threshold and
  no parsing lives in this unit — that is the point of it.

  The Enterprise executable omits this unit from its .dpr and registers the real
  implementations under the same tool names. }

interface

uses MVCFramework.MCP.ToolProvider, MVCFramework.MCP.Attributes;

type
  TFirebirdEnterpriseStubs = class(TMCPToolProvider)
  public
    [MCPTool('fb_analyze_config', 'ENTERPRISE — Deep tuning of firebird.conf and databases.conf against the engine version and the observed workload')]
    function FbAnalyzeConfig: TMCPToolResult;
    [MCPTool('fb_analyze_db_header', 'ENTERPRISE — Database header analysis: page size, sweep interval, forced writes, ODS version')]
    function FbAnalyzeDbHeader: TMCPToolResult;
    [MCPTool('fb_parse_log', 'ENTERPRISE — Parses firebird.log: errors, sweeps, bugchecks, crashes')]
    function FbParseLog: TMCPToolResult;
    [MCPTool('fb_capture_trace', 'ENTERPRISE — Captures the real workload through the Firebird Trace API and ranks the queries that actually cost you')]
    function FbCaptureTrace: TMCPToolResult;
    [MCPTool('fb_analyze_host', 'ENTERPRISE — Host sizing: RAM against page buffers, CPU count against parallel workers, storage class')]
    function FbAnalyzeHost: TMCPToolResult;
  end;

implementation

uses System.SysUtils, MVCFramework.MCP.Server, MVCFramework.Logger;

const
  UPGRADE_MESSAGE =
    '%s belongs to the MCP Firebird Enterprise edition, which is not installed.' + sLineBreak +
    sLineBreak +
    'This edition analyzes what the database knows about itself. The Enterprise edition also ' +
    'reads the machine hosting it — firebird.conf and databases.conf, the database header, ' +
    'firebird.log, the Trace API, and how the engine is sized against the hardware.' + sLineBreak +
    sLineBreak +
    'Enterprise, commercial licences and support: d.teti@bittime.it' + sLineBreak +
    'https://github.com/danieleteti/mcp-firebird#editions--licensing';

function Locked(const AToolName: string): TMCPToolResult;
begin
  LogI(Format('>> %s  (enterprise stub)', [AToolName]), 'mcp');
  Result := TMCPToolResult.Error(Format(UPGRADE_MESSAGE, [AToolName]));
end;

function TFirebirdEnterpriseStubs.FbAnalyzeConfig: TMCPToolResult;
begin
  Result := Locked('fb_analyze_config');
end;

function TFirebirdEnterpriseStubs.FbAnalyzeDbHeader: TMCPToolResult;
begin
  Result := Locked('fb_analyze_db_header');
end;

function TFirebirdEnterpriseStubs.FbParseLog: TMCPToolResult;
begin
  Result := Locked('fb_parse_log');
end;

function TFirebirdEnterpriseStubs.FbCaptureTrace: TMCPToolResult;
begin
  Result := Locked('fb_capture_trace');
end;

function TFirebirdEnterpriseStubs.FbAnalyzeHost: TMCPToolResult;
begin
  Result := Locked('fb_analyze_host');
end;

initialization
  TMCPServer.Instance.RegisterToolProvider(TFirebirdEnterpriseStubs);

end.
