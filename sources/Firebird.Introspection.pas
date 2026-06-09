unit Firebird.Introspection;
interface
uses System.Generics.Collections, Firebird.Connection;
type
  TColumnInfo = record FieldName, DataType: string; Position: Integer; Nullable: Boolean; end;
  TIndexInfo = record
    IndexName: string; Columns: TArray<string>;
    Unique, Inactive, IsSystem: Boolean; Selectivity: Double; ConstraintType: string;
  end;
  TForeignKeyInfo = record
    ConstraintName, RefTable, IndexName: string;
    Columns, RefColumns: TArray<string>;
  end;

  TFirebirdIntrospection = class
  private
    FConn: TFirebirdConnection;
    function IndexColumns(const AIndexName: string): TArray<string>;
  public
    constructor Create(AConn: TFirebirdConnection);
    function ListTables(AIncludeViews: Boolean = True): TArray<string>;
    function GetColumns(const ATable: string): TArray<TColumnInfo>;
    function GetPrimaryKey(const ATable: string): TArray<string>;
    function GetIndexes(const ATable: string): TArray<TIndexInfo>;
    function GetForeignKeys(const ATable: string): TArray<TForeignKeyInfo>;
    function RowCount(const ATable: string): Int64;
  end;
implementation
uses System.SysUtils, Data.DB, FireDAC.Comp.Client;

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
begin inherited Create; FConn := AConn; end;

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

function TFirebirdIntrospection.RowCount(const ATable: string): Int64;
begin
  Result := StrToInt64Def(FConn.ScalarStr('SELECT COUNT(*) FROM ' + ATable), 0);
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
      '       i.rdb$statistics ' +
      'FROM rdb$indices i WHERE i.rdb$relation_name = ' + QuotedStr(ATable) + ' ORDER BY 1', []);
    try
      while not Q.Eof do begin
        Rec := Default(TIndexInfo);
        Rec.IndexName := Q.Fields[0].AsString;
        Rec.Unique    := Q.Fields[1].AsInteger = 1;
        Rec.Inactive  := Q.Fields[2].AsInteger = 1;
        Rec.Selectivity := Q.Fields[4].AsFloat;
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
end.
