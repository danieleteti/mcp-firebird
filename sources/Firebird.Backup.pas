// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit Firebird.Backup;

{ Drives a LOCAL gbak.exe, the way Firebird.PlanAnalyzer drives a local isql.exe:
  a client tool on this machine, through temp files, never the server's own files
  and never the Services Manager. That is what keeps it inside the free edition.

  A backup nobody has restored is a file, not a backup. VerifyRestore therefore
  restores what Backup just wrote into a scratch database and throws it away — with
  gbak -c, which CREATES and refuses an existing file, so a bug here cannot land on
  the live database however wrong the path turns out to be. }

interface

uses Firebird.Connection;

type
  TBackupOutcome = record
    BackupFile: string;
    BackupBytes: Int64;
    BackupSeconds: Double;
    GbakLog: string;        // tail of gbak's own output, for the report
  end;

  TVerifyOutcome = record
    Restored: Boolean;
    Seconds: Double;
    Detail: string;         // how it failed, when it did
  end;

  TFirebirdBackup = class
  private
    FConfig: TFirebirdConnectionConfig;
    function GbakPath: string;
    function ConnectString: string;
    procedure RunAndWait(const ACmd: string; ATimeoutMs: Cardinal; const AWhat: string);
  public
    { Takes the connection parameters by value, not a connection: this runs on a
      worker thread that outlives the tool call, and it issues no SQL. }
    constructor Create(const AConfig: TFirebirdConnectionConfig);
    { The name the next backup would get. Public so the caller can publish the
      destination before the backup starts, and report the file growing. }
    class function ProposeBackupFile(const ADatabase, ADestDir: string): string; static;
    { ABackupFile's folder must exist and the file must not. Raises on any failure. }
    function Backup(const ABackupFile: string): TBackupOutcome;
    { Restores ABackupFile into a scratch database under AScratchDir and deletes it
      again. Never raises: a restore that cannot run is the answer, not an accident. }
    function VerifyRestore(const ABackupFile, AScratchDir: string): TVerifyOutcome;
  end;

implementation

uses
  Winapi.Windows, System.SysUtils, System.IOUtils, System.Diagnostics;

const
  BACKUP_TIMEOUT_MS = 30 * 60 * 1000;   // half an hour; a real database is not an isql plan
  LOG_TAIL_CHARS = 2000;

{ The end of gbak's own output. gbak -v narrates every table it writes, so the useful
  part -- the summary, or the error it stopped on -- is always at the bottom. }
function Tail(const AText: string): string;
begin
  if AText.Length > LOG_TAIL_CHARS then
    Result := '...' + AText.Substring(AText.Length - LOG_TAIL_CHARS)
  else
    Result := AText;
end;

{ gbak -y refuses a file that already exists, and GetTempFileName creates the one it
  names. So we keep the unique name and hand gbak the empty slot, not the empty file. }
function NewGbakLogName: string;
begin
  Result := TPath.GetTempFileName;
  if TFile.Exists(Result) then
    TFile.Delete(Result);
end;

constructor TFirebirdBackup.Create(const AConfig: TFirebirdConnectionConfig);
begin
  inherited Create;
  FConfig := AConfig;
end;

function TFirebirdBackup.GbakPath: string;
var
  lDir: string;
begin
  lDir := ExtractFilePath(FConfig.ClientLib);
  if lDir <> '' then
    Result := IncludeTrailingPathDelimiter(lDir) + 'gbak.exe'
  else
    Result := 'gbak.exe';
  if not FileExists(Result) then
    Result := 'gbak.exe';
end;

function TFirebirdBackup.ConnectString: string;
begin
  Result := Format('%s/%d:%s', [FConfig.Host, FConfig.Port, FConfig.Database]);
end;

procedure TFirebirdBackup.RunAndWait(const ACmd: string; ATimeoutMs: Cardinal; const AWhat: string);
var
  SI: TStartupInfo;
  PI: TProcessInformation;
  lCmd: string;
  lExit: Cardinal;
begin
  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  SI.dwFlags := STARTF_USESHOWWINDOW;
  SI.wShowWindow := SW_HIDE;
  lCmd := ACmd;
  UniqueString(lCmd);
  if not CreateProcess(nil, PChar(lCmd), nil, nil, False, CREATE_NO_WINDOW, nil, nil, SI, PI) then
    RaiseLastOSError;
  try
    if WaitForSingleObject(PI.hProcess, ATimeoutMs) = WAIT_TIMEOUT then
    begin
      TerminateProcess(PI.hProcess, 1);
      raise Exception.CreateFmt('%s timed out after %d minutes', [AWhat, ATimeoutMs div 60000]);
    end;
    if not GetExitCodeProcess(PI.hProcess, lExit) then
      RaiseLastOSError;
    if lExit <> 0 then
      raise Exception.CreateFmt('%s failed (gbak exit code %d)', [AWhat, lExit]);
  finally
    CloseHandle(PI.hThread);
    CloseHandle(PI.hProcess);
  end;
end;

class function TFirebirdBackup.ProposeBackupFile(const ADatabase, ADestDir: string): string;
begin
  Result := IncludeTrailingPathDelimiter(ADestDir) +
    Format('%s-%s.fbk', [ChangeFileExt(ExtractFileName(ADatabase), ''),
                         FormatDateTime('yyyymmdd-hhnnss', Now)]);
end;

function TFirebirdBackup.Backup(const ABackupFile: string): TBackupOutcome;
var
  lLogFile: string;
  SW: TStopwatch;
begin
  Result := Default(TBackupOutcome);
  if not TDirectory.Exists(ExtractFileDir(ABackupFile)) then
    raise Exception.CreateFmt('Backup destination does not exist: %s',
      [ExtractFileDir(ABackupFile)]);
  if TFile.Exists(ABackupFile) then
    raise Exception.CreateFmt('Refusing to overwrite an existing backup: %s', [ABackupFile]);
  Result.BackupFile := ABackupFile;

  lLogFile := NewGbakLogName;
  try
    SW := TStopwatch.StartNew;
    try
      RunAndWait(Format('"%s" -b -v -y "%s" -user %s -password %s "%s" "%s"',
        [GbakPath, lLogFile, FConfig.User, FConfig.Password,
         ConnectString, Result.BackupFile]), BACKUP_TIMEOUT_MS, 'Backup');
    except
      on E: Exception do
      begin
        { "gbak exit code 1" is not a diagnosis. gbak wrote why in the log we are
          about to delete, so it leaves with the exception rather than with the file. }
        if TFile.Exists(lLogFile) then
          E.Message := E.Message + sLineBreak + Tail(TFile.ReadAllText(lLogFile));
        raise;
      end;
    end;
    Result.BackupSeconds := SW.Elapsed.TotalSeconds;

    if not TFile.Exists(Result.BackupFile) then
      raise Exception.CreateFmt('gbak reported success but wrote no file: %s', [Result.BackupFile]);
    Result.BackupBytes := TFile.GetSize(Result.BackupFile);
    if TFile.Exists(lLogFile) then
      Result.GbakLog := Tail(TFile.ReadAllText(lLogFile));
  finally
    if TFile.Exists(lLogFile) then
      TFile.Delete(lLogFile);
  end;
end;

function TFirebirdBackup.VerifyRestore(const ABackupFile, AScratchDir: string): TVerifyOutcome;
var
  lLogFile, lScratch: string;
  SW: TStopwatch;
begin
  Result := Default(TVerifyOutcome);
  { -c CREATES and refuses an existing file. Combined with a name nothing else uses,
    a bug here cannot land on the live database however wrong the path turns out. }
  lScratch := IncludeTrailingPathDelimiter(AScratchDir) +
    Format('verify-%s.scratch.fdb', [FormatDateTime('yyyymmdd-hhnnsszzz', Now)]);
  lLogFile := NewGbakLogName;
  SW := TStopwatch.StartNew;
  try
    try
      RunAndWait(Format('"%s" -c -v -y "%s" -user %s -password %s "%s" "%s"',
        [GbakPath, lLogFile, FConfig.User, FConfig.Password,
         ABackupFile, lScratch]), BACKUP_TIMEOUT_MS, 'Verification restore');
      Result.Restored := TFile.Exists(lScratch) and (TFile.GetSize(lScratch) > 0);
      if not Result.Restored then
        Result.Detail := 'The restore reported success but produced no database.';
    except
      on E: Exception do
      begin
        Result.Restored := False;
        Result.Detail := E.Message;
        if TFile.Exists(lLogFile) then
          Result.Detail := Result.Detail + sLineBreak + Tail(TFile.ReadAllText(lLogFile));
      end;
    end;
    Result.Seconds := SW.Elapsed.TotalSeconds;
  finally
    if TFile.Exists(lLogFile) then
      TFile.Delete(lLogFile);
    if TFile.Exists(lScratch) then
      TFile.Delete(lScratch);
  end;
end;

end.
