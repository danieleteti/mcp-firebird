// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit Firebird.Introspection;
interface
uses System.Generics.Collections, Firebird.Connection, Firebird.Capabilities;
type
  TColumnInfo = record
    FieldName, DataType: string;
    Position: Integer;
    Nullable: Boolean;
    { The named domain the column is built on, empty when the column carries its own type.
      A schema whose columns come from domains says something a resolved type does not: that
      the same rule holds everywhere the domain is used, and that changing it is one statement. }
    Domain: string;
  end;
  TIndexInfo = record
    IndexName: string; Columns: TArray<string>;
    Unique, Inactive, IsSystem: Boolean; Selectivity: Double; ConstraintType: string;
    { RDB$INDEX_TYPE = 1. A descending index is a different index from its ascending twin: only
      it serves ORDER BY col DESC and MAX(col) without a sort. }
    Descending: Boolean;
  end;
  TForeignKeyInfo = record
    ConstraintName, RefTable, IndexName: string;
    Columns, RefColumns: TArray<string>;
  end;

  TRoutineParam = record
    ParamName: string;
    DataType: string;
    Position: Integer;
    IsOutput: Boolean;
  end;

  TProcedureInfo = record
    ProcName: string;
    PackageName: string;
    Params: TArray<TRoutineParam>;
  end;

  TTriggerInfo = record
    TriggerName: string;
    TableName: string;
    Event: string;      // 'BEFORE INSERT', 'AFTER UPDATE OR DELETE', ...
    Position: Integer;
    Inactive: Boolean;
  end;

  TFunctionInfo = record
    FuncName: string;
    PackageName: string;
    ReturnType: string;
  end;

  TPackageInfo = record
    PackageName: string;
    HasBody: Boolean;
  end;

  { A CHECK constraint, with the source text the engine kept — `CHECK (...)`, verbatim. }
  TCheckInfo = record
    ConstraintName: string;
    Source: string;
  end;

  TFirebirdIntrospection = class
  private
    FConn: TFirebirdConnection;
    FCaps: TFirebirdCapabilities;
    function IndexColumns(const AIndexName: string): TArray<string>;
    function RoutineParams(const ARoutine, APackage: string): TArray<TRoutineParam>;
  public
    constructor Create(AConn: TFirebirdConnection);
    function ListTables(AIncludeViews: Boolean = True): TArray<string>;
    { Views only — the complement of ListTables(False), so a caller can document both without
      guessing which relation is which. }
    function ListViews: TArray<string>;
    { The SELECT a view stands for, empty for a table. A plan that reads three tables for a
      query that names one is explained here and nowhere else. }
    function GetViewSource(const AView: string): string;
    { CHECK constraints on ATable. Firebird implements each one as a pair of triggers; those
      triggers are hidden from ListTriggers, and the rule is reported here instead. }
    function GetChecks(const ATable: string): TArray<TCheckInfo>;
    function GetColumns(const ATable: string): TArray<TColumnInfo>;
    function GetPrimaryKey(const ATable: string): TArray<string>;
    function GetIndexes(const ATable: string): TArray<TIndexInfo>;
    function GetForeignKeys(const ATable: string): TArray<TForeignKeyInfo>;
    function ListProcedures: TArray<TProcedureInfo>;
    function ListTriggers(const ATable: string = ''): TArray<TTriggerInfo>;
    { Empty below Firebird 3.0: PSQL functions and packages do not exist there,
      and the 2.5 RDB$FUNCTIONS holds external UDF declarations only. }
    function ListFunctions: TArray<TFunctionInfo>;
    function ListPackages: TArray<TPackageInfo>;
  end;

{ Wraps an identifier in double quotes for use in SQL text. }
function QuoteIdent(const S: string): string;

implementation
uses System.SysUtils, System.Classes, Data.DB, FireDAC.Comp.Client;

function QuoteIdent(const S: string): string;
begin Result := '"' + S.Replace('"', '""') + '"'; end;

{ ALen is a length in characters, never in bytes: RDB$FIELD_LENGTH counts bytes, so under a
  UTF8 database every VARCHAR(n) would be documented as VARCHAR(n*4) — a column four times the
  size of the one that is really there. Every caller passes
  COALESCE(RDB$CHARACTER_LENGTH, RDB$FIELD_LENGTH), which is the character count where the
  engine keeps one and the byte count where the two are the same thing. }
function MapFieldType(AType, ALen, AScale: Integer): string;
begin
  case AType of
    7:  if AScale < 0 then Result := 'NUMERIC' else Result := 'SMALLINT';
    8:  if AScale < 0 then Result := 'NUMERIC' else Result := 'INTEGER';
    16: if AScale < 0 then Result := 'NUMERIC' else Result := 'BIGINT';
    10: Result := 'FLOAT';
    27: Result := 'DOUBLE PRECISION';
    12: Result := 'DATE';
    13: Result := 'TIME';
    35: Result := 'TIMESTAMP';
    14: Result := 'CHAR(' + ALen.ToString + ')';
    37: Result := 'VARCHAR(' + ALen.ToString + ')';
    261: Result := 'BLOB';
  else  Result := 'TYPE#' + AType.ToString;
  end;
end;

constructor TFirebirdIntrospection.Create(AConn: TFirebirdConnection);
begin
  inherited Create;
  FConn := AConn;
  FCaps := TFirebirdCapabilities.Detect(AConn);
end;

{ RDB$TRIGGER_TYPE packs up to three actions into 2-bit slots above bit 0, which
  is 1 for BEFORE and 0 for AFTER (type 1 = BEFORE INSERT, type 2 = AFTER INSERT).
  Values above 113 are database-level triggers (ON CONNECT and friends), which
  carry no action slots at all. }
function DecodeTriggerType(AType: Int64): string;
const
  ACTIONS: array[1..3] of string = ('INSERT', 'UPDATE', 'DELETE');
var
  lSlot, lAction: Integer;
  lParts: TArray<string>;
begin
  if AType > 113 then
    Exit('ON ' + IntToStr(AType) + ' (database-level)');
  lParts := [];
  for lSlot := 0 to 2 do
  begin
    lAction := ((AType + 1) shr (1 + 2 * lSlot)) and 3;
    if lAction in [1 .. 3] then
      lParts := lParts + [ACTIONS[lAction]];
  end;
  if Length(lParts) = 0 then
    Exit('UNKNOWN');
  if (AType and 1) = 1 then
    Result := 'BEFORE '
  else
    Result := 'AFTER ';
  Result := Result + string.Join(' OR ', lParts);
end;

function TFirebirdIntrospection.ListTables(AIncludeViews: Boolean): TArray<string>;
var Q: TFDQuery; L: TList<string>; SQL: string;
begin
  SQL := 'SELECT TRIM(rdb$relation_name) FROM rdb$relations ' +
         'WHERE (rdb$system_flag IS NULL OR rdb$system_flag = 0)';
  if not AIncludeViews then SQL := SQL + ' AND rdb$view_blr IS NULL';
  SQL := SQL + ' ORDER BY 1';
  L := TList<string>.Create;
  try
    Q := FConn.OpenQuery(SQL);
    try while not Q.Eof do begin L.Add(Q.Fields[0].AsString); Q.Next; end; finally Q.Free; end;
    Result := L.ToArray;
  finally L.Free; end;
end;

function TFirebirdIntrospection.GetColumns(const ATable: string): TArray<TColumnInfo>;
var Q: TFDQuery; L: TList<TColumnInfo>; Rec: TColumnInfo; lSource: string;
begin
  L := TList<TColumnInfo>.Create;
  try
    Q := FConn.OpenQuery(
      'SELECT TRIM(rf.rdb$field_name), rf.rdb$field_position, ' +
      '       COALESCE(rf.rdb$null_flag,0), f.rdb$field_type, ' +
      '       COALESCE(f.rdb$character_length, f.rdb$field_length), f.rdb$field_scale, ' +
      '       TRIM(rf.rdb$field_source) ' +
      'FROM rdb$relation_fields rf ' +
      'JOIN rdb$fields f ON f.rdb$field_name = rf.rdb$field_source ' +
      'WHERE rf.rdb$relation_name = ' + QuotedStr(ATable) +
      ' ORDER BY rf.rdb$field_position', []);
    try
      while not Q.Eof do begin
        Rec := Default(TColumnInfo);
        Rec.FieldName := Q.Fields[0].AsString;
        Rec.Position  := Q.Fields[1].AsInteger;
        Rec.Nullable  := Q.Fields[2].AsInteger = 0;
        Rec.DataType  := MapFieldType(Q.Fields[3].AsInteger, Q.Fields[4].AsInteger, Q.Fields[5].AsInteger);
        { Every column has a field source. A column declared inline gets a generated one named
          RDB$<n>, which is an implementation detail; only a name somebody chose is a domain. }
        lSource := Q.Fields[6].AsString;
        if not lSource.StartsWith('RDB$') then
          Rec.Domain := lSource;
        L.Add(Rec); Q.Next;
      end;
    finally Q.Free; end;
    Result := L.ToArray;
  finally L.Free; end;
end;

function TFirebirdIntrospection.ListViews: TArray<string>;
var Q: TFDQuery; L: TList<string>;
begin
  L := TList<string>.Create;
  try
    Q := FConn.OpenQuery(
      'SELECT TRIM(rdb$relation_name) FROM rdb$relations ' +
      'WHERE (rdb$system_flag IS NULL OR rdb$system_flag = 0) AND rdb$view_blr IS NOT NULL ' +
      'ORDER BY 1');
    try while not Q.Eof do begin L.Add(Q.Fields[0].AsString); Q.Next; end; finally Q.Free; end;
    Result := L.ToArray;
  finally L.Free; end;
end;

function TFirebirdIntrospection.GetViewSource(const AView: string): string;
begin
  Result := FConn.ScalarStr(
    'SELECT rdb$view_source FROM rdb$relations WHERE rdb$relation_name = ' + QuotedStr(AView)).Trim;
end;

function TFirebirdIntrospection.GetChecks(const ATable: string): TArray<TCheckInfo>;
var Q: TFDQuery; L: TList<TCheckInfo>; Rec: TCheckInfo; lSeen: TStringList;
begin
  L := TList<TCheckInfo>.Create;
  lSeen := TStringList.Create;
  try
    lSeen.Sorted := True;
    lSeen.Duplicates := dupIgnore;
    { One CHECK is two triggers (before insert, before update) carrying the same source, so the
      constraint would be reported twice. SELECT DISTINCT cannot do the deduplication here:
      RDB$TRIGGER_SOURCE is a BLOB and Firebird refuses to compare one. }
    Q := FConn.OpenQuery(
      'SELECT TRIM(rc.rdb$constraint_name), t.rdb$trigger_source ' +
      'FROM rdb$relation_constraints rc ' +
      'JOIN rdb$check_constraints cc ON cc.rdb$constraint_name = rc.rdb$constraint_name ' +
      'JOIN rdb$triggers t ON t.rdb$trigger_name = cc.rdb$trigger_name ' +
      'WHERE rc.rdb$constraint_type = ''CHECK'' AND rc.rdb$relation_name = ' + QuotedStr(ATable) +
      ' ORDER BY 1', []);
    try
      while not Q.Eof do
      begin
        Rec := Default(TCheckInfo);
        Rec.ConstraintName := Q.Fields[0].AsString;
        Rec.Source := Q.Fields[1].AsString.Trim;
        if lSeen.IndexOf(Rec.ConstraintName) < 0 then
        begin
          lSeen.Add(Rec.ConstraintName);
          L.Add(Rec);
        end;
        Q.Next;
      end;
    finally Q.Free; end;
    Result := L.ToArray;
  finally L.Free; lSeen.Free; end;
end;

function TFirebirdIntrospection.GetPrimaryKey(const ATable: string): TArray<string>;
var Q: TFDQuery; L: TList<string>;
begin
  L := TList<string>.Create;
  try
    Q := FConn.OpenQuery(
      'SELECT TRIM(s.rdb$field_name) FROM rdb$relation_constraints rc ' +
      'JOIN rdb$index_segments s ON s.rdb$index_name = rc.rdb$index_name ' +
      'WHERE rc.rdb$constraint_type = ''PRIMARY KEY'' AND rc.rdb$relation_name = ' + QuotedStr(ATable) +
      ' ORDER BY s.rdb$field_position', []);
    try while not Q.Eof do begin L.Add(Q.Fields[0].AsString); Q.Next; end; finally Q.Free; end;
    Result := L.ToArray;
  finally L.Free; end;
end;

function TFirebirdIntrospection.IndexColumns(const AIndexName: string): TArray<string>;
var Q: TFDQuery; L: TList<string>;
begin
  L := TList<string>.Create;
  try
    Q := FConn.OpenQuery(
      'SELECT TRIM(rdb$field_name) FROM rdb$index_segments ' +
      'WHERE rdb$index_name = ' + QuotedStr(AIndexName) + ' ORDER BY rdb$field_position', []);
    try while not Q.Eof do begin L.Add(Q.Fields[0].AsString); Q.Next; end; finally Q.Free; end;
    Result := L.ToArray;
  finally L.Free; end;
end;

function TFirebirdIntrospection.GetIndexes(const ATable: string): TArray<TIndexInfo>;
var Q: TFDQuery; L: TList<TIndexInfo>; Rec: TIndexInfo; CT: string;
begin
  L := TList<TIndexInfo>.Create;
  try
    Q := FConn.OpenQuery(
      'SELECT TRIM(i.rdb$index_name), COALESCE(i.rdb$unique_flag,0), ' +
      '       COALESCE(i.rdb$index_inactive,0), COALESCE(i.rdb$system_flag,0), ' +
      '       i.rdb$statistics, COALESCE(i.rdb$index_type,0) ' +
      'FROM rdb$indices i WHERE i.rdb$relation_name = ' + QuotedStr(ATable) + ' ORDER BY 1', []);
    try
      while not Q.Eof do begin
        Rec := Default(TIndexInfo);
        Rec.IndexName := Q.Fields[0].AsString;
        Rec.Unique    := Q.Fields[1].AsInteger = 1;
        Rec.Inactive  := Q.Fields[2].AsInteger = 1;
        Rec.Selectivity := Q.Fields[4].AsFloat;
        Rec.Descending := Q.Fields[5].AsInteger = 1;
        Rec.Columns   := IndexColumns(Rec.IndexName);
        CT := FConn.ScalarStr(
          'SELECT TRIM(rc.rdb$constraint_type) FROM rdb$relation_constraints rc ' +
          'WHERE rc.rdb$index_name = ' + QuotedStr(Rec.IndexName));
        Rec.ConstraintType := CT;
        Rec.IsSystem := (CT <> '') or Rec.IndexName.StartsWith('RDB$');
        L.Add(Rec); Q.Next;
      end;
    finally Q.Free; end;
    Result := L.ToArray;
  finally L.Free; end;
end;

function TFirebirdIntrospection.GetForeignKeys(const ATable: string): TArray<TForeignKeyInfo>;
var Q: TFDQuery; L: TList<TForeignKeyInfo>; Rec: TForeignKeyInfo;
begin
  L := TList<TForeignKeyInfo>.Create;
  try
    Q := FConn.OpenQuery(
      'SELECT TRIM(rc.rdb$constraint_name), TRIM(rc.rdb$index_name), ' +
      '       TRIM(rc2.rdb$relation_name) ' +
      'FROM rdb$relation_constraints rc ' +
      'JOIN rdb$ref_constraints ref ON ref.rdb$constraint_name = rc.rdb$constraint_name ' +
      'JOIN rdb$relation_constraints rc2 ON rc2.rdb$constraint_name = ref.rdb$const_name_uq ' +
      'WHERE rc.rdb$constraint_type = ''FOREIGN KEY'' AND rc.rdb$relation_name = ' + QuotedStr(ATable), []);
    try
      while not Q.Eof do begin
        Rec := Default(TForeignKeyInfo);
        Rec.ConstraintName := Q.Fields[0].AsString;
        Rec.IndexName      := Q.Fields[1].AsString;
        Rec.RefTable       := Q.Fields[2].AsString;
        Rec.Columns        := IndexColumns(Rec.IndexName);
        L.Add(Rec); Q.Next;
      end;
    finally Q.Free; end;
    Result := L.ToArray;
  finally L.Free; end;
end;

function TFirebirdIntrospection.RoutineParams(const ARoutine, APackage: string): TArray<TRoutineParam>;
var
  Q: TFDQuery;
  L: TList<TRoutineParam>;
  R: TRoutineParam;
  lSQL: string;
begin
  lSQL :=
    'SELECT TRIM(p.RDB$PARAMETER_NAME) AS PNAME, p.RDB$PARAMETER_NUMBER AS PNUM, ' +
    '       p.RDB$PARAMETER_TYPE AS PTYPE, f.RDB$FIELD_TYPE AS FTYPE, ' +
    '       COALESCE(f.RDB$CHARACTER_LENGTH, f.RDB$FIELD_LENGTH) AS FLEN, f.RDB$FIELD_SCALE AS FSCALE ' +
    'FROM RDB$PROCEDURE_PARAMETERS p ' +
    'JOIN RDB$FIELDS f ON f.RDB$FIELD_NAME = p.RDB$FIELD_SOURCE ' +
    'WHERE p.RDB$PROCEDURE_NAME = ' + QuotedStr(ARoutine);
  if FCaps.HasPackages then
    if APackage = '' then
      lSQL := lSQL + ' AND p.RDB$PACKAGE_NAME IS NULL'
    else
      lSQL := lSQL + ' AND p.RDB$PACKAGE_NAME = ' + QuotedStr(APackage);
  lSQL := lSQL + ' ORDER BY p.RDB$PARAMETER_TYPE, p.RDB$PARAMETER_NUMBER';

  L := TList<TRoutineParam>.Create;
  try
    Q := FConn.OpenQuery(lSQL);
    try
      while not Q.Eof do
      begin
        R := Default(TRoutineParam);
        R.ParamName := Q.FieldByName('PNAME').AsString;
        R.Position := Q.FieldByName('PNUM').AsInteger;
        R.IsOutput := Q.FieldByName('PTYPE').AsInteger = 1;
        R.DataType := MapFieldType(Q.FieldByName('FTYPE').AsInteger,
          Q.FieldByName('FLEN').AsInteger, Q.FieldByName('FSCALE').AsInteger);
        L.Add(R);
        Q.Next;
      end;
    finally
      Q.Free;
    end;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function TFirebirdIntrospection.ListProcedures: TArray<TProcedureInfo>;
var
  Q: TFDQuery;
  L: TList<TProcedureInfo>;
  P: TProcedureInfo;
  lSQL: string;
begin
  if FCaps.HasPackages then
    lSQL := 'SELECT TRIM(RDB$PROCEDURE_NAME) AS PNAME, ' +
            '       COALESCE(TRIM(RDB$PACKAGE_NAME), '''') AS PKG ' +
            'FROM RDB$PROCEDURES ' +
            'WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0 ORDER BY 2, 1'
  else
    lSQL := 'SELECT TRIM(RDB$PROCEDURE_NAME) AS PNAME, '''' AS PKG ' +
            'FROM RDB$PROCEDURES ' +
            'WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0 ORDER BY 1';

  L := TList<TProcedureInfo>.Create;
  try
    Q := FConn.OpenQuery(lSQL);
    try
      while not Q.Eof do
      begin
        P := Default(TProcedureInfo);
        P.ProcName := Q.FieldByName('PNAME').AsString;
        P.PackageName := Q.FieldByName('PKG').AsString;
        L.Add(P);
        Q.Next;
      end;
    finally
      Q.Free;
    end;
    Result := L.ToArray;
  finally
    L.Free;
  end;
  { Parameters are fetched after the cursor is closed: one open query at a time
    keeps this working on every engine in the matrix. }
  for var lIdx := 0 to High(Result) do
    Result[lIdx].Params := RoutineParams(Result[lIdx].ProcName, Result[lIdx].PackageName);
end;

function TFirebirdIntrospection.ListTriggers(const ATable: string = ''): TArray<TTriggerInfo>;
var
  Q: TFDQuery;
  L: TList<TTriggerInfo>;
  T: TTriggerInfo;
  lSQL: string;
begin
  lSQL :=
    'SELECT TRIM(t.RDB$TRIGGER_NAME) AS TNAME, COALESCE(TRIM(t.RDB$RELATION_NAME), '''') AS TBL, ' +
    '       t.RDB$TRIGGER_TYPE AS TTYPE, COALESCE(t.RDB$TRIGGER_SEQUENCE, 0) AS TSEQ, ' +
    '       COALESCE(t.RDB$TRIGGER_INACTIVE, 0) AS TINACT ' +
    'FROM RDB$TRIGGERS t WHERE COALESCE(t.RDB$SYSTEM_FLAG, 0) = 0 ' +
    { A CHECK constraint is enforced by two triggers the user never wrote and cannot alter.
      Listing them as triggers reports an implementation detail as a schema object, twice per
      constraint; GetChecks reports the constraint itself instead. }
    '  AND NOT EXISTS (SELECT 1 FROM RDB$CHECK_CONSTRAINTS cc ' +
    '                  WHERE cc.RDB$TRIGGER_NAME = t.RDB$TRIGGER_NAME)';
  if ATable <> '' then
    lSQL := lSQL + ' AND t.RDB$RELATION_NAME = ' + QuotedStr(ATable);
  lSQL := lSQL + ' ORDER BY 2, 4, 1';

  L := TList<TTriggerInfo>.Create;
  try
    Q := FConn.OpenQuery(lSQL);
    try
      while not Q.Eof do
      begin
        T := Default(TTriggerInfo);
        T.TriggerName := Q.FieldByName('TNAME').AsString;
        T.TableName := Q.FieldByName('TBL').AsString;
        T.Event := DecodeTriggerType(Q.FieldByName('TTYPE').AsLargeInt);
        T.Position := Q.FieldByName('TSEQ').AsInteger;
        T.Inactive := Q.FieldByName('TINACT').AsInteger <> 0;
        L.Add(T);
        Q.Next;
      end;
    finally
      Q.Free;
    end;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function TFirebirdIntrospection.ListFunctions: TArray<TFunctionInfo>;
var
  Q: TFDQuery;
  L: TList<TFunctionInfo>;
  F: TFunctionInfo;
begin
  Result := [];
  if not FCaps.HasPackages then
    Exit;
  L := TList<TFunctionInfo>.Create;
  try
    Q := FConn.OpenQuery(
      'SELECT TRIM(f.RDB$FUNCTION_NAME) AS FNAME, ' +
      '       COALESCE(TRIM(f.RDB$PACKAGE_NAME), '''') AS PKG, ' +
      '       fl.RDB$FIELD_TYPE AS FTYPE, ' +
      '       COALESCE(fl.RDB$CHARACTER_LENGTH, fl.RDB$FIELD_LENGTH) AS FLEN, ' +
      '       fl.RDB$FIELD_SCALE AS FSCALE ' +
      'FROM RDB$FUNCTIONS f ' +
      'LEFT JOIN RDB$FUNCTION_ARGUMENTS a ' +
      '  ON a.RDB$FUNCTION_NAME = f.RDB$FUNCTION_NAME ' +
      ' AND a.RDB$ARGUMENT_POSITION = f.RDB$RETURN_ARGUMENT ' +
      ' AND COALESCE(a.RDB$PACKAGE_NAME, '''') = COALESCE(f.RDB$PACKAGE_NAME, '''') ' +
      'LEFT JOIN RDB$FIELDS fl ON fl.RDB$FIELD_NAME = a.RDB$FIELD_SOURCE ' +
      'WHERE COALESCE(f.RDB$SYSTEM_FLAG, 0) = 0 ORDER BY 2, 1');
    try
      while not Q.Eof do
      begin
        F := Default(TFunctionInfo);
        F.FuncName := Q.FieldByName('FNAME').AsString;
        F.PackageName := Q.FieldByName('PKG').AsString;
        if Q.FieldByName('FTYPE').IsNull then
          F.ReturnType := 'UNKNOWN'
        else
          F.ReturnType := MapFieldType(Q.FieldByName('FTYPE').AsInteger,
            Q.FieldByName('FLEN').AsInteger, Q.FieldByName('FSCALE').AsInteger);
        L.Add(F);
        Q.Next;
      end;
    finally
      Q.Free;
    end;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function TFirebirdIntrospection.ListPackages: TArray<TPackageInfo>;
var
  Q: TFDQuery;
  L: TList<TPackageInfo>;
  P: TPackageInfo;
begin
  Result := [];
  if not FCaps.HasPackages then
    Exit;
  L := TList<TPackageInfo>.Create;
  try
    Q := FConn.OpenQuery(
      'SELECT TRIM(RDB$PACKAGE_NAME) AS PKG, ' +
      '       IIF(RDB$PACKAGE_BODY_SOURCE IS NULL, 0, 1) AS HAS_BODY ' +
      'FROM RDB$PACKAGES WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0 ORDER BY 1');
    try
      while not Q.Eof do
      begin
        P := Default(TPackageInfo);
        P.PackageName := Q.FieldByName('PKG').AsString;
        P.HasBody := Q.FieldByName('HAS_BODY').AsInteger = 1;
        L.Add(P);
        Q.Next;
      end;
    finally
      Q.Free;
    end;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;
end.
