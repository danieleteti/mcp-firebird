@echo off
rem Usage: _build_app.bat [output_dir]
rem   no argument  -> Clean+Build into bin\ (the normal build)
rem   output_dir   -> Build the exe into output_dir instead, leaving bin\ alone.
rem                   Used by `invoke compliance`, so a running MCP client holding
rem                   bin\MCPFirebird.exe open cannot block the build.
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
if "%~1"=="" (
  msbuild "C:\DEV\mcp-firebird\app\MCPFirebird.dproj" /t:Clean;Build /p:Config=Debug /p:Platform=Win64
) else (
  msbuild "C:\DEV\mcp-firebird\app\MCPFirebird.dproj" /t:Build /p:Config=Debug /p:Platform=Win64 /p:DCC_ExeOutput="%~1" /p:DCC_DcuOutput="%~1"
)
