// SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
unit FirebirdBackupJobU;

{ A backup takes minutes; an MCP call must not. So fb_backup_start hands the work
  to a thread and returns at once, and fb_backup_status reports on it — the same
  start/poll shape the Enterprise fb_trace_* tools use, for the same reason.

  One slot, no job ids: two concurrent backups of one database is disk contention
  wearing the costume of a feature. }

interface

uses System.SysUtils, Firebird.Connection;

type
  TBackupPhase = (bpNever, bpBackingUp, bpVerifying, bpDone, bpFailed);

  TBackupJobState = record
    Phase: TBackupPhase;
    StartedAt: TDateTime;
    FinishedAt: TDateTime;
    BackupFile: string;
    BackupBytes: Int64;      // final size; while running, ask the file itself
    BackupSeconds: Double;
    VerifySeconds: Double;
    Detail: string;          // the failure, or the verification's complaint
    GbakLog: string;
    function Running: Boolean;
  end;

{ False when a backup is already running — the caller should poll instead of starting another. }
function StartBackupJob(const AConfig: TFirebirdConnectionConfig; const ADestDir: string): Boolean;
function BackupJobState: TBackupJobState;

implementation

uses
  System.Classes, System.IOUtils, System.SyncObjs, Firebird.Backup, MVCFramework.Logger;

var
  GLock: TCriticalSection;
  GState: TBackupJobState;

function TBackupJobState.Running: Boolean;
begin
  Result := Phase in [bpBackingUp, bpVerifying];
end;

function StartBackupJob(const AConfig: TFirebirdConnectionConfig; const ADestDir: string): Boolean;
var
  lConfig: TFirebirdConnectionConfig;
  lDir: string;
begin
  GLock.Enter;
  try
    if GState.Running then
      Exit(False);
    GState := Default(TBackupJobState);
    GState.Phase := bpBackingUp;
    GState.StartedAt := Now;
    Result := True;
  finally
    GLock.Leave;
  end;

  { Captured by value: the thread must share nothing with the request that started it. }
  lConfig := AConfig;
  lDir := ADestDir;

  TThread.CreateAnonymousThread(
    procedure
    var
      B: TFirebirdBackup;
      O: TBackupOutcome;
      V: TVerifyOutcome;
      lFile: string;
    begin
      B := TFirebirdBackup.Create(lConfig);
      try
        try
          { Publish the destination BEFORE the long phase starts, so
            BackupJobState can report the file growing while it runs. }
          lFile := TFirebirdBackup.ProposeBackupFile(lConfig.Database, lDir);
          GLock.Enter;
          try
            GState.BackupFile := lFile;
          finally
            GLock.Leave;
          end;

          O := B.Backup(lFile);
          GLock.Enter;
          try
            GState.BackupBytes := O.BackupBytes;
            GState.BackupSeconds := O.BackupSeconds;
            GState.GbakLog := O.GbakLog;
            GState.Phase := bpVerifying;
          finally
            GLock.Leave;
          end;
          LogI(Format('backup written %s (%d bytes)', [O.BackupFile, O.BackupBytes]), 'mcp');

          V := B.VerifyRestore(O.BackupFile, lDir);
          GLock.Enter;
          try
            GState.VerifySeconds := V.Seconds;
            GState.Detail := V.Detail;
            if V.Restored then
              GState.Phase := bpDone
            else
              GState.Phase := bpFailed;
            GState.FinishedAt := Now;
          finally
            GLock.Leave;
          end;
        except
          on E: Exception do
          begin
            GLock.Enter;
            try
              GState.Phase := bpFailed;
              GState.Detail := E.ClassName + ': ' + E.Message;
              GState.FinishedAt := Now;
            finally
              GLock.Leave;
            end;
            LogException(E, 'backup job failed');
          end;
        end;
      finally
        B.Free;
      end;
    end).Start;
end;

function BackupJobState: TBackupJobState;
begin
  GLock.Enter;
  try
    Result := GState;
  finally
    GLock.Leave;
  end;
  { While the backup is running the file on disk is the honest progress counter,
    and reading its size costs nothing. No shared counter to keep in step. }
  if (Result.Phase = bpBackingUp) and (Result.BackupFile <> '') and TFile.Exists(Result.BackupFile) then
    Result.BackupBytes := TFile.GetSize(Result.BackupFile);
end;

initialization

GLock := TCriticalSection.Create;
GState := Default(TBackupJobState);

finalization

GLock.Free;

end.
