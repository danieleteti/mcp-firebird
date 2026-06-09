param(
  [Parameter(Mandatory)][ValidateSet('start','stop','client','port')] [string]$Action,
  [Parameter(Mandatory)][ValidateSet('2.5','3.0','4.0','5.0')]        [string]$Version
)
$ErrorActionPreference = 'Stop'
$root = 'C:\DEV\mcp-firebird\fb_versions'
$reg  = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'fbkit.versions.psd1')
$v    = $reg[$Version]
$base = Join-Path $root $v.Dir
$exe  = Join-Path $base $v.Exe
$conf = Join-Path $base $v.Conf

function Set-Port {
  $content = Get-Content $conf -Raw
  if ($content -match '(?m)^\s*#?\s*RemoteServicePort\s*=.*$') {
    $content = $content -replace '(?m)^\s*#?\s*RemoteServicePort\s*=.*$', "RemoteServicePort = $($v.Port)"
  } else {
    $content += "`r`nRemoteServicePort = $($v.Port)`r`n"
  }
  Set-Content -Path $conf -Value $content -Encoding ASCII
}

switch ($Action) {
  'port'   { $v.Port; break }
  'client' { Join-Path $base $v.Client; break }
  'start'  {
    Set-Port
    $p = Start-Process -FilePath $exe -ArgumentList $v.ExeArgs -WorkingDirectory $base -PassThru
    Start-Sleep -Seconds 2
    Write-Host "Started FB $Version (PID $($p.Id)) on port $($v.Port)"
    $p.Id
    break
  }
  'stop'   {
    Get-CimInstance Win32_Process -Filter "Name='$(Split-Path $exe -Leaf)'" |
      Where-Object { $_.ExecutablePath -eq $exe } |
      ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    Write-Host "Stopped FB $Version"
    break
  }
}
