// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
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
    function RoutinesMarkdown: string;
  end;
implementation
uses System.SysUtils, System.Classes, System.StrUtils;

constructor TFirebirdDocGen.Create(AIntro: TFirebirdIntrospection);
begin inherited Create; FIntro := AIntro; end;
destructor TFirebirdDocGen.Destroy; begin FIntro.Free; inherited; end;

function TFirebirdDocGen.TableMarkdown(const ATable: string): string;
var
  SB: TStringBuilder; C: TColumnInfo; X: TIndexInfo; PK: TArray<string>; S: string;
  lTriggers: TArray<TTriggerInfo>;
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

    lTriggers := FIntro.ListTriggers(ATable);
    if Length(lTriggers) > 0 then
    begin
      SB.AppendLine.AppendLine('### Triggers').AppendLine;
      for var T in lTriggers do
        SB.AppendLine(Format('- `%s` — %s, position %d%s',
          [T.TriggerName, T.Event, T.Position,
           IfThen(T.Inactive, ' *(inactive)*', '')]));
    end;

    Result := SB.ToString;
  finally SB.Free; end;
end;

function TFirebirdDocGen.RoutinesMarkdown: string;
var
  SB: TStringBuilder;
  lProcs: TArray<TProcedureInfo>;
  lFuncs: TArray<TFunctionInfo>;
  lPkgs: TArray<TPackageInfo>;
  lSig: string;
begin
  SB := TStringBuilder.Create;
  try
    lProcs := FIntro.ListProcedures;
    if Length(lProcs) > 0 then
    begin
      SB.AppendLine.AppendLine('## Stored procedures').AppendLine;
      for var P in lProcs do
      begin
        lSig := '';
        for var R in P.Params do
        begin
          if lSig <> '' then
            lSig := lSig + ', ';
          lSig := lSig + Format('%s %s %s',
            [IfThen(R.IsOutput, 'out', 'in'), R.ParamName, R.DataType]);
        end;
        if P.PackageName = '' then
          SB.AppendLine(Format('- `%s(%s)`', [P.ProcName, lSig]))
        else
          SB.AppendLine(Format('- `%s.%s(%s)`', [P.PackageName, P.ProcName, lSig]));
      end;
    end;

    lFuncs := FIntro.ListFunctions;
    if Length(lFuncs) > 0 then
    begin
      SB.AppendLine.AppendLine('## Functions').AppendLine;
      for var F in lFuncs do
        if F.PackageName = '' then
          SB.AppendLine(Format('- `%s` returns %s', [F.FuncName, F.ReturnType]))
        else
          SB.AppendLine(Format('- `%s.%s` returns %s',
            [F.PackageName, F.FuncName, F.ReturnType]));
    end;

    lPkgs := FIntro.ListPackages;
    if Length(lPkgs) > 0 then
    begin
      SB.AppendLine.AppendLine('## Packages').AppendLine;
      for var K in lPkgs do
        SB.AppendLine(Format('- `%s`%s',
          [K.PackageName, IfThen(K.HasBody, '', ' *(header only, no body)*')]));
    end;

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TFirebirdDocGen.DatabaseMarkdown: string;
var SB: TStringBuilder; T: string;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Database documentation').AppendLine;
    for T in FIntro.ListTables(False) do
      SB.AppendLine(TableMarkdown(T));
    SB.Append(RoutinesMarkdown);
    Result := SB.ToString;
  finally SB.Free; end;
end;
end.
