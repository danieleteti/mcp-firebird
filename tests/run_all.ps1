$ErrorActionPreference = 'Stop'
$versions = @('2.5','3.0','4.0','5.0')
$root     = Split-Path -Parent $PSScriptRoot
$coreExe  = Join-Path $PSScriptRoot 'coreproject\MCPFirebirdCoreTests.exe'
$db       = Join-Path $PSScriptRoot 'seed\TESTDB.FDB'
$failed   = $false

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

# MCP compliance once (on 5.0)
Write-Host "==== Python MCP compliance on FB 5.0 ===="
& "$PSScriptRoot\fbkit.ps1" -Action start -Version 5.0 | Out-Null
try {
  & "$PSScriptRoot\seed\make_seed.ps1" -Version 5.0 | Out-Null
  pwsh "$PSScriptRoot\check_core_boundary.ps1"
  python -m pytest "$PSScriptRoot\test_mcp_firebird_stdio.py" "$PSScriptRoot\test_mcp_firebird_full.py" -v
  if ($LASTEXITCODE -ne 0) { $failed = $true }
} finally {
  & "$PSScriptRoot\fbkit.ps1" -Action stop -Version 5.0 | Out-Null
}

if ($failed) { throw 'One or more suites FAILED' } else { Write-Host 'ALL SUITES PASSED' }
