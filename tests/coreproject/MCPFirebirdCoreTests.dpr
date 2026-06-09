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
  Test.Firebird.Connection in 'Test.Firebird.Connection.pas',
  Test.Firebird.Capabilities in 'Test.Firebird.Capabilities.pas',
  Test.Firebird.Introspection in 'Test.Firebird.Introspection.pas',
  Test.Firebird.Indexes in 'Test.Firebird.Indexes.pas';
var
  LRunner: ITestRunner;
  LResults: IRunResults;
begin
  TDUnitX.RegisterTestFixture(Test.Firebird.Connection.TConnectionTests);
  TDUnitX.RegisterTestFixture(Test.Firebird.Capabilities.TCapabilitiesTests);
  TDUnitX.RegisterTestFixture(Test.Firebird.Introspection.TIntrospectionTests);
  TDUnitX.RegisterTestFixture(Test.Firebird.Indexes.TIndexIntrospectionTests);
  LRunner := TDUnitX.CreateRunner;
  LRunner.AddLogger(TDUnitXConsoleLogger.Create(True));
  LRunner.AddLogger(TDUnitXXMLNUnitFileLogger.Create(
    IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'core-tests.xml'));
  LResults := LRunner.Execute;
  if not LResults.AllPassed then
    ExitCode := 1;
end.
