param([Parameter(Mandatory)][ValidateSet('2.5','3.0','4.0','5.0')] [string]$Version)
$ErrorActionPreference = 'Stop'
$reg  = Import-PowerShellDataFile (Join-Path $PSScriptRoot '..\fbkit.versions.psd1')
$v    = $reg[$Version]
$base = Join-Path 'C:\DEV\mcp-firebird\fb_versions' $v.Dir
$exeDir = Split-Path $v.Exe -Parent
if ([string]::IsNullOrEmpty($exeDir)) { $isql = Join-Path $base 'isql.exe' }
else { $isql = Join-Path $base (Join-Path $exeDir 'isql.exe') }
if (-not (Test-Path $isql)) { $isql = Join-Path $base 'isql.exe' }
$port = $v.Port
$db   = "localhost/$port`:C:\DEV\mcp-firebird\tests\seed\TESTDB.FDB"
$seed = Join-Path $PSScriptRoot 'seed.sql'
$problems = Join-Path $PSScriptRoot 'problems.sql'
if (Test-Path 'C:\DEV\mcp-firebird\tests\seed\TESTDB.FDB') { Remove-Item 'C:\DEV\mcp-firebird\tests\seed\TESTDB.FDB' -Force }
@"
CREATE DATABASE '$db' USER 'SYSDBA' PASSWORD 'masterkey' DEFAULT CHARACTER SET UTF8;
INPUT '$seed';
INPUT '$problems';
"@ | & $isql -q
Write-Host "Seed DB created for FB $Version at $db"
