// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit Firebird.Introspection;
interface
uses System.Generics.Collections, Firebird.Connection, Firebird.Capabilities;
type
  TColumnInfo = record FieldName, DataType: string; Position: Integer; Nullable: Boolean; end;
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

  TFirebirdIntrospection = class
  private
    FConn: TFirebirdConnection;
    FCaps: TFirebirdCapabilities;
    function IndexColumns(const AIndexName: string): TArray<string>;
    function RoutineParams(const ARoutine, APackage: string): TArray<TRoutineParam>;
  public
    constructor Create(AConn: TFirebirdConnection);
    function ListTables(AIncludeViews: Boolean = True): TArray<string>;
    function GetColumns(const ATable: string): TArray<TColumnInfo>;
    function GetPrimaryKey(const ATable: string): TArray<string>;
    function GetIndexes(const ATable: string): TArray<TIndexInfo>;
    function GetForeignKeys(const ATable: string): TArray<TForeignKeyInfo>;
    function ListProcedures: TArray<TProcedureInfo>;
    function ListTriggers(const ATable: string = ''): TArray<TTriggerInfo>;
  end;

{ Wraps an identifier in double quotes for use in SQL text. }
function QuoteIdent(const S: string): string;

implementation
uses System.SysUtils, Data.DB, FireDAC.Comp.Client;

function QuoteIdent(const S: string): string;
begin Result := '"' + S.Replace('"', '""') + '"'; end;

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
var Q: TFDQuery; L: TList<TColumnInfo>; Rec: TColumnInfo;
begin
  L := TList<TColumnInfo>.Create;
  try
    Q := FConn.OpenQuery(
      'SELECT TRIM(rf.rdb$field_name), rf.rdb$field_position, ' +
      '       COALESCE(rf.rdb$null_flag,0), f.rdb$field_type, f.rdb$field_length, f.rdb$field_scale ' +
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
        L.Add(Rec); Q.Next;
      end;
    finally Q.Free; end;
    Result := L.ToArray;
  finally L.Free; end;
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
    '       f.RDB$FIELD_LENGTH AS FLEN, f.RDB$FIELD_SCALE AS FSCALE ' +
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
    'SELECT TRIM(RDB$TRIGGER_NAME) AS TNAME, COALESCE(TRIM(RDB$RELATION_NAME), '''') AS TBL, ' +
    '       RDB$TRIGGER_TYPE AS TTYPE, COALESCE(RDB$TRIGGER_SEQUENCE, 0) AS TSEQ, ' +
    '       COALESCE(RDB$TRIGGER_INACTIVE, 0) AS TINACT ' +
    'FROM RDB$TRIGGERS WHERE COALESCE(RDB$SYSTEM_FLAG, 0) = 0';
  if ATable <> '' then
    lSQL := lSQL + ' AND RDB$RELATION_NAME = ' + QuotedStr(ATable);
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
end.
