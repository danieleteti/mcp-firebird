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
  Test.Firebird.Connection in 'Test.Firebird.Connection.pas';
var
  LRunner: ITestRunner;
  LResults: IRunResults;
begin
  TDUnitX.RegisterTestFixture(Test.Firebird.Connection.TConnectionTests);
  LRunner := TDUnitX.CreateRunner;
  LRunner.AddLogger(TDUnitXConsoleLogger.Create(True));
  LRunner.AddLogger(TDUnitXXMLNUnitFileLogger.Create(
    IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'core-tests.xml'));
  LResults := LRunner.Execute;
  if not LResults.AllPassed then
    ExitCode := 1;
end.
