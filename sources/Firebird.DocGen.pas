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
    function ColumnTable(const ATable: string): string;
    function TriggerList(const ARelation: string): string;
  public
    constructor Create(AIntro: TFirebirdIntrospection);
    destructor Destroy; override;
    { Documents a table — or, when the name turns out to be a view, the view and the SELECT
      behind it. A caller asking about a name should not have to know which it is. }
    function TableMarkdown(const ATable: string): string;
    function ViewMarkdown(const AView, ASource: string): string;
    function DatabaseMarkdown: string;
    function RoutinesMarkdown: string;
  end;
implementation
uses System.SysUtils, System.Classes, System.StrUtils;

constructor TFirebirdDocGen.Create(AIntro: TFirebirdIntrospection);
begin inherited Create; FIntro := AIntro; end;
destructor TFirebirdDocGen.Destroy; begin FIntro.Free; inherited; end;

function TFirebirdDocGen.ColumnTable(const ATable: string): string;
var SB: TStringBuilder; C: TColumnInfo;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('| Column | Type | Nullable |');
    SB.AppendLine('|---|---|---|');
    for C in FIntro.GetColumns(ATable) do
      SB.AppendLine(Format('| %s | %s%s | %s |',
        [C.FieldName, C.DataType,
         { The domain is the answer to "why is this VARCHAR(11) everywhere": it is one rule with
           a name, and the name is what a reader can go and look up. }
         IfThen(C.Domain = '', '', Format(' *(domain %s)*', [C.Domain])),
         BoolToStr(C.Nullable, True)]));
    Result := SB.ToString;
  finally SB.Free; end;
end;

function TFirebirdDocGen.TriggerList(const ARelation: string): string;
var SB: TStringBuilder; lTriggers: TArray<TTriggerInfo>;
begin
  Result := '';
  lTriggers := FIntro.ListTriggers(ARelation);
  if Length(lTriggers) = 0 then
    Exit;
  SB := TStringBuilder.Create;
  try
    SB.AppendLine.AppendLine('### Triggers').AppendLine;
    for var T in lTriggers do
      SB.AppendLine(Format('- `%s` — %s, position %d%s',
        [T.TriggerName, T.Event, T.Position, IfThen(T.Inactive, ' *(inactive)*', '')]));
    Result := SB.ToString;
  finally SB.Free; end;
end;

function TFirebirdDocGen.ViewMarkdown(const AView, ASource: string): string;
var SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('## ' + AView + ' *(view)*').AppendLine;
    SB.Append(ColumnTable(AView));
    SB.AppendLine;
    { A view is the only schema object whose cost is invisible from its own definition: three
      joins and a sort can hide behind one name, and the plan for a query that mentions only
      that name is otherwise unreadable. }
    SB.AppendLine('**View source:**').AppendLine('```sql').AppendLine(ASource).AppendLine('```');
    { An updatable view accepts a write only through a trigger, so on a view this section is not
      decoration: it is where the write goes. }
    SB.Append(TriggerList(AView));
    Result := SB.ToString;
  finally SB.Free; end;
end;

function TFirebirdDocGen.TableMarkdown(const ATable: string): string;
var
  SB: TStringBuilder; X: TIndexInfo; PK: TArray<string>; S: string;
  lChecks: TArray<TCheckInfo>;
  lViewSource: string;
begin
  lViewSource := FIntro.GetViewSource(ATable);
  if lViewSource <> '' then
    Exit(ViewMarkdown(ATable, lViewSource));
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('## ' + ATable).AppendLine;
    PK := FIntro.GetPrimaryKey(ATable);
    SB.AppendLine('**Primary key:** ' + string.Join(', ', PK)).AppendLine;
    SB.Append(ColumnTable(ATable));
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

    lChecks := FIntro.GetChecks(ATable);
    if Length(lChecks) > 0 then
    begin
      SB.AppendLine.AppendLine('### Check constraints').AppendLine;
      for var K in lChecks do
        SB.AppendLine(Format('- `%s` — %s', [K.ConstraintName, K.Source]));
    end;

    SB.Append(TriggerList(ATable));

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
var SB: TStringBuilder; T: string; lViews: TArray<string>;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Database documentation').AppendLine;
    for T in FIntro.ListTables(False) do
      SB.AppendLine(TableMarkdown(T));
    lViews := FIntro.ListViews;
    if Length(lViews) > 0 then
    begin
      SB.AppendLine.AppendLine('# Views').AppendLine;
      for T in lViews do
        SB.AppendLine(ViewMarkdown(T, FIntro.GetViewSource(T)));
    end;
    SB.Append(RoutinesMarkdown);
    Result := SB.ToString;
  finally SB.Free; end;
end;
end.
