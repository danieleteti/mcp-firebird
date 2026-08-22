unit Test.Firebird.Backup;

interface

uses DUnitX.TestFramework;

type
  [TestFixture]
  TBackupTests = class
  public
    [Test] procedure Backup_Writes_A_File;
    [Test] procedure VerifyRestore_Accepts_A_Backup_It_Just_Made;
    [Test] procedure Backup_Rejects_A_Destination_That_Does_Not_Exist;
  end;

implementation

uses System.SysUtils, System.IOUtils, Firebird.Connection, Firebird.Backup, TestFixtureU;

function NewTempDir: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'mcpfb_backup_' + TGUID.NewGuid.ToString.Trim(['{', '}']));
  TDirectory.CreateDirectory(Result);
end;

procedure TBackupTests.Backup_Writes_A_File;
var
  B: TFirebirdBackup;
  lDir: string;
  lOutcome: TBackupOutcome;
begin
  lDir := NewTempDir;
  try
    B := TFirebirdBackup.Create(TestConfig);
    try
      lOutcome := B.Backup(TFirebirdBackup.ProposeBackupFile(TestConfig.Database, lDir));
      Assert.IsTrue(TFile.Exists(lOutcome.BackupFile), 'backup file not written');
      Assert.IsTrue(lOutcome.BackupBytes > 0, 'backup file is empty');
    finally
      B.Free;
    end;
  finally
    TDirectory.Delete(lDir, True);
  end;
end;

procedure TBackupTests.VerifyRestore_Accepts_A_Backup_It_Just_Made;
var
  B: TFirebirdBackup;
  lDir: string;
  lOutcome: TBackupOutcome;
  lVerify: TVerifyOutcome;
begin
  lDir := NewTempDir;
  try
    B := TFirebirdBackup.Create(TestConfig);
    try
      lOutcome := B.Backup(TFirebirdBackup.ProposeBackupFile(TestConfig.Database, lDir));
      lVerify := B.VerifyRestore(lOutcome.BackupFile, lDir);
      Assert.IsTrue(lVerify.Restored, 'backup did not restore: ' + lVerify.Detail);
      Assert.AreEqual(0, Integer(Length(TDirectory.GetFiles(lDir, '*.scratch.fdb'))),
        'the scratch database was left behind');
    finally
      B.Free;
    end;
  finally
    TDirectory.Delete(lDir, True);
  end;
end;

procedure TBackupTests.Backup_Rejects_A_Destination_That_Does_Not_Exist;
var
  B: TFirebirdBackup;
begin
  B := TFirebirdBackup.Create(TestConfig);
  try
    Assert.WillRaise(
      procedure
      begin
        B.Backup(TPath.Combine(TPath.GetTempPath, 'mcpfb_no_such_dir_12345', 'x.fbk'));
      end, Exception, 'a backup into a folder that does not exist must be refused');
  finally
    B.Free;
  end;
end;

end.
