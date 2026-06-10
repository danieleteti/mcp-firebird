@echo off
call "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"
msbuild "C:\DEV\mcp-firebird\tests\coreproject\MCPFirebirdCoreTests.dproj" /t:Clean;Build /p:Config=Debug /p:Platform=Win64
