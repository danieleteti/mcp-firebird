program MCPFirebirdCoreTests;
{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}
uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  TestFixtureU in 'TestFixtureU.pas',
  Firebird.Connection in '..\..\sources\Firebird.Connection.pas',
  Firebird.Capabilities in '..\..\sources\Firebird.Capabilities.pas',
  Firebird.Introspection in '..\..\sources\Firebird.Introspection.pas',
  Firebird.Advisory in '..\..\sources\Firebird.Advisory.pas',
  Firebird.DocGen in '..\..\sources\Firebird.DocGen.pas',
  Firebird.PlanAnalyzer in '..\..\sources\Firebird.PlanAnalyzer.pas',
  Firebird.IndexAdvisor in '..\..\sources\Firebird.IndexAdvisor.pas',
  Firebird.Goal in '..\..\sources\Firebird.Goal.pas',
  Firebird.SchemaAudit in '..\..\sources\Firebird.SchemaAudit.pas',
  Firebird.TransactionMonitor in '..\..\sources\Firebird.TransactionMonitor.pas',
  Firebird.Activity in '..\..\sources\Firebird.Activity.pas',
  Firebird.Attachments in '..\..\sources\Firebird.Attachments.pas',
  Firebird.Backup in '..\..\sources\Firebird.Backup.pas',
  Firebird.Query in '..\..\sources\Firebird.Query.pas',
  Firebird.SecurityAudit in '..\..\sources\Firebird.SecurityAudit.pas',
  Firebird.GrantPlanner in '..\..\sources\Firebird.GrantPlanner.pas',
  Test.Firebird.Connection in 'Test.Firebird.Connection.pas',
  Test.Firebird.Capabilities in 'Test.Firebird.Capabilities.pas',
  Test.Firebird.Introspection in 'Test.Firebird.Introspection.pas',
  Test.Firebird.Indexes in 'Test.Firebird.Indexes.pas',
  Test.Firebird.DocGen in 'Test.Firebird.DocGen.pas',
  Test.Firebird.PlanAnalyzer in 'Test.Firebird.PlanAnalyzer.pas',
  Test.Firebird.IndexAdvisor in 'Test.Firebird.IndexAdvisor.pas',
  Test.Firebird.IndexDrops in 'Test.Firebird.IndexDrops.pas',
  Test.Firebird.Goal in 'Test.Firebird.Goal.pas',
  Test.Firebird.SchemaAudit in 'Test.Firebird.SchemaAudit.pas',
  Test.Firebird.TransactionMonitor in 'Test.Firebird.TransactionMonitor.pas',
  Test.Firebird.Activity in 'Test.Firebird.Activity.pas',
  Test.Firebird.Backup in 'Test.Firebird.Backup.pas',
  Test.Firebird.Attachments in 'Test.Firebird.Attachments.pas',
  Test.Firebird.Query in 'Test.Firebird.Query.pas',
  Test.Firebird.SecurityAudit in 'Test.Firebird.SecurityAudit.pas',
  Test.Firebird.GrantPlanner in 'Test.Firebird.GrantPlanner.pas';
var
  LRunner: ITestRunner;
  LResults: IRunResults;
begin
  TDUnitX.RegisterTestFixture(Test.Firebird.Connection.TConnectionTests);
  TDUnitX.RegisterTestFixture(Test.Firebird.Capabilities.TCapabilitiesTests);
  TDUnitX.RegisterTestFixture(Test.Firebird.Introspection.TIntrospectionTests);
  TDUnitX.RegisterTestFixture(Test.Firebird.Indexes.TIndexIntrospectionTests);
  TDUnitX.RegisterTestFixture(Test.Firebird.DocGen.TDocGenTests);
  TDUnitX.RegisterTestFixture(Test.Firebird.PlanAnalyzer.TPlanAnalyzerTests);
  TDUnitX.RegisterTestFixture(Test.Firebird.IndexAdvisor.TIndexAdvisorTests);
  TDUnitX.RegisterTestFixture(Test.Firebird.IndexDrops.TIndexDropTests);
  TDUnitX.RegisterTestFixture(Test.Firebird.Goal.TGoalTests);
  TDUnitX.RegisterTestFixture(Test.Firebird.SchemaAudit.TSchemaAuditTests);
  TDUnitX.RegisterTestFixture(Test.Firebird.TransactionMonitor.TTransactionMonitorTests);
  TDUnitX.RegisterTestFixture(Test.Firebird.Activity.TActivityTests);
  TDUnitX.RegisterTestFixture(Test.Firebird.Backup.TBackupTests);
  TDUnitX.RegisterTestFixture(Test.Firebird.Attachments.TAttachmentsTests);
  TDUnitX.RegisterTestFixture(Test.Firebird.Query.TQueryTests);
  TDUnitX.RegisterTestFixture(Test.Firebird.SecurityAudit.TSecurityAuditTests);
  TDUnitX.RegisterTestFixture(Test.Firebird.GrantPlanner.TGrantPlannerTests);
  LRunner := TDUnitX.CreateRunner;
  LRunner.AddLogger(TDUnitXConsoleLogger.Create(True));
  LRunner.AddLogger(TDUnitXXMLNUnitFileLogger.Create(
    IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'core-tests.xml'));
  LResults := LRunner.Execute;
  if not LResults.AllPassed then
    ExitCode := 1;
end.
