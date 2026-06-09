unit Firebird.Connection;
interface
uses
  FireDAC.Comp.Client, FireDAC.Phys.FB, FireDAC.Phys.FBDef, FireDAC.Stan.Def,
  FireDAC.Stan.Async, FireDAC.DApt, FireDAC.Stan.Param, Data.DB;
type
  TFirebirdConnectionConfig = record
    Host: string;
    Port: Integer;
    Database: string;
    User: string;
    Password: string;
    Charset: string;
    ClientLib: string;
    AllowDDL: Boolean;
  end;

  TFirebirdConnection = class
  private
    FConn: TFDConnection;
    FDriverLink: TFDPhysFBDriverLink;
    FConfig: TFirebirdConnectionConfig;
  public
    constructor Create(const AConfig: TFirebirdConnectionConfig);
    destructor Destroy; override;
    procedure Connect;
    function IsConnected: Boolean;
    function OpenQuery(const ASQL: string): TFDQuery; overload;
    function OpenQuery(const ASQL: string; const AParams: array of Variant): TFDQuery; overload;
    function ExecSQL(const ASQL: string): Integer;
    function ScalarStr(const ASQL: string): string;
    property Config: TFirebirdConnectionConfig read FConfig;
    property FDConnection: TFDConnection read FConn;
  end;
implementation
uses System.SysUtils;

constructor TFirebirdConnection.Create(const AConfig: TFirebirdConnectionConfig);
begin
  inherited Create;
  FConfig := AConfig;
  FDriverLink := TFDPhysFBDriverLink.Create(nil);
  if AConfig.ClientLib <> '' then
    FDriverLink.VendorLib := AConfig.ClientLib;
  FConn := TFDConnection.Create(nil);
  FConn.LoginPrompt := False;
  FConn.DriverName := 'FB';
  FConn.Params.Values['Server']       := AConfig.Host;
  FConn.Params.Values['Port']         := AConfig.Port.ToString;
  FConn.Params.Values['Database']     := AConfig.Database;
  FConn.Params.Values['User_Name']    := AConfig.User;
  FConn.Params.Values['Password']     := AConfig.Password;
  FConn.Params.Values['CharacterSet'] := AConfig.Charset;
  FConn.Params.Values['Protocol']     := 'TCPIP';
end;

destructor TFirebirdConnection.Destroy;
begin
  FConn.Free;
  FDriverLink.Free;
  inherited;
end;

procedure TFirebirdConnection.Connect;
begin
  FConn.Connected := True;
end;

function TFirebirdConnection.IsConnected: Boolean;
begin
  Result := FConn.Connected;
end;

function TFirebirdConnection.OpenQuery(const ASQL: string): TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  try
    Result.Connection := FConn;
    Result.Open(ASQL);
  except
    Result.Free; raise;
  end;
end;

function TFirebirdConnection.OpenQuery(const ASQL: string; const AParams: array of Variant): TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  try
    Result.Connection := FConn;
    Result.Open(ASQL, AParams);
  except
    Result.Free; raise;
  end;
end;

function TFirebirdConnection.ExecSQL(const ASQL: string): Integer;
begin
  Result := FConn.ExecSQL(ASQL);
end;

function TFirebirdConnection.ScalarStr(const ASQL: string): string;
var Q: TFDQuery;
begin
  Q := OpenQuery(ASQL);
  try
    if Q.Eof then Result := '' else Result := Q.Fields[0].AsString;
  finally Q.Free; end;
end;
end.
