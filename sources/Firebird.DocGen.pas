// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit Firebird.DocGen;
interface
uses Firebird.Introspection;
type
  TFirebirdDocGen = class
  private
    FIntro: TFirebirdIntrospection;
  public
    constructor Create(AIntro: TFirebirdIntrospection);
    destructor Destroy; override;
    function TableMarkdown(const ATable: string): string;
    function DatabaseMarkdown: string;
  end;
implementation
uses System.SysUtils, System.Classes, System.StrUtils;

constructor TFirebirdDocGen.Create(AIntro: TFirebirdIntrospection);
begin inherited Create; FIntro := AIntro; end;
destructor TFirebirdDocGen.Destroy; begin FIntro.Free; inherited; end;

function TFirebirdDocGen.TableMarkdown(const ATable: string): string;
var SB: TStringBuilder; C: TColumnInfo; X: TIndexInfo; PK: TArray<string>; S: string;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('## ' + ATable).AppendLine;
    PK := FIntro.GetPrimaryKey(ATable);
    SB.AppendLine('**Primary key:** ' + string.Join(', ', PK)).AppendLine;
    SB.AppendLine('| Column | Type | Nullable |');
    SB.AppendLine('|---|---|---|');
    for C in FIntro.GetColumns(ATable) do
      SB.AppendLine(Format('| %s | %s | %s |', [C.FieldName, C.DataType, BoolToStr(C.Nullable, True)]));
    SB.AppendLine;
    SB.AppendLine('**Indexes:**');
    for X in FIntro.GetIndexes(ATable) do
    begin
      S := Format('- `%s` (%s)%s', [X.IndexName, string.Join(', ', X.Columns),
        IfThen(X.Inactive, ' — INACTIVE', '')]);
      if X.ConstraintType <> '' then S := S + ' [' + X.ConstraintType + ']';
      SB.AppendLine(S);
    end;
    SB.AppendLine;
    Result := SB.ToString;
  finally SB.Free; end;
end;

function TFirebirdDocGen.DatabaseMarkdown: string;
var SB: TStringBuilder; T: string;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Database documentation').AppendLine;
    for T in FIntro.ListTables(False) do
      SB.AppendLine(TableMarkdown(T));
    Result := SB.ToString;
  finally SB.Free; end;
end;
end.
