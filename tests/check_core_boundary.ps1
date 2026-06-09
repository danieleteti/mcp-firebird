$ErrorActionPreference = 'Stop'
$bad = Select-String -Path 'C:\DEV\mcp-firebird\sources\*.pas' -Pattern 'MVCFramework' -SimpleMatch
if ($bad) { $bad | ForEach-Object { Write-Host $_.Path ':' $_.Line }; throw 'Core unit imports MVCFramework - boundary violated' }
Write-Host 'Core boundary OK: no MVCFramework imports in sources/'
