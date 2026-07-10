// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit FirebirdStubsU;

{ The Enterprise tools, announced but not implemented in this edition.

  The free edition uses an ordinary SQL connection, and nothing more. Everything here needs a
  privilege the free edition never asks for: an administrative attach to the Services Manager
  (to stream firebird.log, to drive the Trace API, to read the storage report), or the server's
  own configuration files and hardware. That is a different product, a different risk profile
  and a different licence. See README § Editions & licensing.

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
    [MCPTool('fb_analyze_storage', 'ENTERPRISE — Physical storage report: index depth, page fill ratios, record-version chains, page distribution')]
    function FbAnalyzeStorage: TMCPToolResult;
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
    'This edition asks the database about itself over an ordinary SQL connection. The Enterprise ' +
    'edition also administers the server: firebird.conf and databases.conf, firebird.log, the ' +
    'Trace API, the physical storage report, and how the engine is sized against its hardware.' + sLineBreak +
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

function TFirebirdEnterpriseStubs.FbAnalyzeStorage: TMCPToolResult;
begin
  Result := Locked('fb_analyze_storage');
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
