// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit Firebird.Capabilities;
interface
uses Firebird.Connection;
type
  TFirebirdCapabilities = record
    EngineVersion: string;
    Major, Minor, Ordinal: Integer;
    HasMonTables, HasExplainedPlan, HasBooleanType, HasIdentityCols: Boolean;
    HasInt128, HasTimezones, HasParallelWorkers, HasRdbConfig: Boolean;
    { RDB$PACKAGE_NAME (RDB$PROCEDURE_PARAMETERS/RDB$PROCEDURES/RDB$FUNCTIONS) does not exist
      before 3.0 — selecting it on 2.5 fails with "Column unknown". }
    HasPackages: Boolean;
    { Index shapes the advisor is allowed to prescribe. An expression index (COMPUTED BY) has
      existed since 2.0, so the flag is always true across the supported matrix and is declared
      only so the advisor asks the same question of both shapes. A partial index (CREATE INDEX
      ... WHERE) arrived in 5.0; below it the advice is the plain B-tree plus a line saying what
      5.0 would allow. }
    HasExpressionIndexes, HasPartialIndexes: Boolean;
    class function Parse(const AVersion: string): TFirebirdCapabilities; static;
    class function Detect(AConn: TFirebirdConnection): TFirebirdCapabilities; static;
  end;
implementation
uses System.SysUtils;

class function TFirebirdCapabilities.Parse(const AVersion: string): TFirebirdCapabilities;
var Parts: TArray<string>;
begin
  Result := Default(TFirebirdCapabilities);
  Result.EngineVersion := AVersion;
  Parts := AVersion.Split(['.']);
  if Length(Parts) > 0 then Result.Major := StrToIntDef(Parts[0], 0);
  if Length(Parts) > 1 then Result.Minor := StrToIntDef(Parts[1], 0);
  Result.Ordinal := Result.Major * 100 + Result.Minor;
  Result.HasMonTables       := Result.Ordinal >= 201;
  Result.HasExplainedPlan   := Result.Ordinal >= 300;
  Result.HasBooleanType     := Result.Ordinal >= 300;
  Result.HasIdentityCols    := Result.Ordinal >= 300;
  Result.HasPackages        := Result.Ordinal >= 300;
  Result.HasInt128          := Result.Ordinal >= 400;
  Result.HasTimezones       := Result.Ordinal >= 400;
  Result.HasRdbConfig       := Result.Ordinal >= 400;
  Result.HasParallelWorkers := Result.Ordinal >= 500;
  Result.HasExpressionIndexes := Result.Ordinal >= 200;
  Result.HasPartialIndexes    := Result.Ordinal >= 500;
end;

class function TFirebirdCapabilities.Detect(AConn: TFirebirdConnection): TFirebirdCapabilities;
var V: string;
begin
  V := AConn.ScalarStr('SELECT rdb$get_context(''SYSTEM'',''ENGINE_VERSION'') FROM rdb$database');
  Result := Parse(V);
end;
end.
