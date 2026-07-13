// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit Firebird.SchemaAudit;
interface
uses Firebird.Connection, Firebird.Advisory;
type
  TFirebirdSchemaAudit = class
  private
    FConn: TFirebirdConnection;
    function ActualSelectivity(const ATable, AColumn: string): Double;
  public
    constructor Create(AConn: TFirebirdConnection);
    function AuditTable(const ATable: string): TArray<TAdvisory>;
  end;
implementation
uses System.SysUtils, System.Generics.Collections, Firebird.Introspection;

const OVER_INDEX_THRESHOLD = 5;

constructor TFirebirdSchemaAudit.Create(AConn: TFirebirdConnection);
begin inherited Create; FConn := AConn; end;

function TFirebirdSchemaAudit.ActualSelectivity(const ATable, AColumn: string): Double;
var Distinct: Int64;
begin
  Distinct := StrToInt64Def(FConn.ScalarStr(Format('SELECT COUNT(DISTINCT %s) FROM %s', [QuoteIdent(AColumn), QuoteIdent(ATable)])), 0);
  if Distinct = 0 then Exit(0);
  Result := 1.0 / Distinct;
end;

function TFirebirdSchemaAudit.AuditTable(const ATable: string): TArray<TAdvisory>;
var Intro: TFirebirdIntrospection; PK: TArray<string>; Idx: TArray<TIndexInfo>;
    UserIdx: Integer; X: TIndexInfo; Actual: Double; Advs: TList<TAdvisory>;
begin
  Advs := TList<TAdvisory>.Create;
  Intro := TFirebirdIntrospection.Create(FConn);
  try
    PK := Intro.GetPrimaryKey(ATable);
    if Length(PK) = 0 then
      Advs.Add(TAdvisory.Make(
        Format('Table %s has no PRIMARY KEY. Rows cannot be addressed uniquely; replication, updates and joins all suffer.', [ATable]),
        Format('ALTER TABLE %s ADD CONSTRAINT PK_%s PRIMARY KEY (/* choose a unique column */);', [ATable, ATable]),
        'fb_generate_documentation should then list a PRIMARY KEY constraint.',
        'critical'));

    Idx := Intro.GetIndexes(ATable);

    UserIdx := 0;
    for X in Idx do if not X.IsSystem then Inc(UserIdx);
    if UserIdx > OVER_INDEX_THRESHOLD then
      Advs.Add(TAdvisory.Make(
        Format('Table %s carries %d user indexes. Every INSERT/UPDATE/DELETE must maintain all of them; on a write-heavy table this is a major cost.', [ATable, UserIdx]),
        Format('-- Review with fb_suggest_index_drops %s and drop the unused ones.', [ATable]),
        'Re-run fb_audit_table after dropping; the count should fall.',
        'warning'));

    for X in Idx do
      // An INACTIVE index has no statistics to be stale: RDB$STATISTICS is NULL, the optimizer
      // cannot use it for reads, and the remedy is fb_suggest_index_drops, not SET STATISTICS.
      if (not X.IsSystem) and (not X.Inactive) and (Length(X.Columns) = 1) then
      begin
        Actual := ActualSelectivity(ATable, X.Columns[0]);
        if (Actual > 0) and (Abs(X.Selectivity - Actual) > (Actual * 0.5)) then
          Advs.Add(TAdvisory.Make(
            // %g, not %f: on a table of twenty million rows the real selectivity is ~5e-8, and
            // six decimals render both figures as "0.000000". Invariant settings, because these
            // numbers are read by a machine and a decimal comma is not a number to it.
            Format('Index %s has stale statistics: stored selectivity %g vs actual %g. The optimizer may pick a bad plan from outdated numbers (common after bulk loads).',
                   [X.IndexName, X.Selectivity, Actual], TFormatSettings.Invariant),
            Format('SET STATISTICS INDEX %s;', [X.IndexName]),
            'Re-run fb_audit_table; stored and actual selectivity should match.',
            'warning'));
      end;

    Result := Advs.ToArray;
  finally
    Intro.Free; Advs.Free;
  end;
end;
end.
