$ErrorActionPreference = 'Stop'
$versions = @('2.5','3.0','4.0','5.0')
$root     = Split-Path -Parent $PSScriptRoot
$coreExe  = Join-Path $PSScriptRoot 'coreproject\MCPFirebirdCoreTests.exe'
$db       = Join-Path $PSScriptRoot 'seed\TESTDB.FDB'
$failed   = $false

# Build what is about to be tested. A stale exe passes stale tests: the run proves nothing
# about the sources sitting in the working tree.
Write-Host "==== Building the core tests and the app ===="
& (Join-Path $root '_build_core.bat') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Core test build FAILED' }
$compDir = Join-Path $root 'build\compliance'
New-Item -ItemType Directory -Force $compDir | Out-Null
& (Join-Path $root '_build_app.bat') $compDir | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'App build FAILED' }

# Core suite across the whole version matrix
foreach ($v in $versions) {
  $dir = (Import-PowerShellDataFile "$PSScriptRoot\fbkit.versions.psd1")[$v].Dir
  if (-not (Test-Path (Join-Path $root "fb_versions\$dir"))) { Write-Host "SKIP FB $v (kit not present)"; continue }
  Write-Host "==== Core suite on FB $v ===="
  & "$PSScriptRoot\fbkit.ps1" -Action start -Version $v | Out-Null
  try {
    & "$PSScriptRoot\seed\make_seed.ps1" -Version $v | Out-Null
    $env:FBTEST_PORT       = (& "$PSScriptRoot\fbkit.ps1" -Action port   -Version $v)
    $env:FBTEST_CLIENTLIB  = (& "$PSScriptRoot\fbkit.ps1" -Action client -Version $v)
    $env:FBTEST_DB         = $db
    & $coreExe
    if ($LASTEXITCODE -ne 0) { $failed = $true; Write-Host "FB $v core tests FAILED" }
  } finally {
    & "$PSScriptRoot\fbkit.ps1" -Action stop -Version $v | Out-Null
  }
}

# MCP compliance once (on 5.0), against the exe built above with its own .env.
# Never against bin\: the exe there may be stale, and bin\.env is the maintainer's own
# database and password, so failures read as regressions when they are neither.
Write-Host "==== Python MCP compliance on FB 5.0 ===="
& "$PSScriptRoot\fbkit.ps1" -Action start -Version 5.0 | Out-Null
try {
  & "$PSScriptRoot\seed\make_seed.ps1" -Version 5.0 | Out-Null
  $port   = (& "$PSScriptRoot\fbkit.ps1" -Action port   -Version 5.0)
  $client = (& "$PSScriptRoot\fbkit.ps1" -Action client -Version 5.0)
  Copy-Item (Join-Path $root 'bin\loggerpro.stdio.json') $compDir -Force
  @(
    'firebird.host=localhost'
    "firebird.port=$port"
    "firebird.database=$db"
    'firebird.user=SYSDBA'
    'firebird.password=masterkey'
    'firebird.charset=UTF8'
    "firebird.client_lib=$client"
    'logger.config.file=loggerpro.stdio.json'
  ) | Set-Content (Join-Path $compDir '.env')
  pwsh "$PSScriptRoot\check_core_boundary.ps1"
  $env:MCP_FB_EXE = Join-Path $compDir 'MCPFirebird.exe'
  try {
    python -m pytest "$PSScriptRoot\test_mcp_firebird_stdio.py" "$PSScriptRoot\test_mcp_firebird_full.py" -v
    if ($LASTEXITCODE -ne 0) { $failed = $true }
  } finally {
    Remove-Item Env:MCP_FB_EXE -ErrorAction SilentlyContinue
  }
} finally {
  & "$PSScriptRoot\fbkit.ps1" -Action stop -Version 5.0 | Out-Null
}

if ($failed) { throw 'One or more suites FAILED' } else { Write-Host 'ALL SUITES PASSED' }
