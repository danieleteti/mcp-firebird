$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$patterns = @('sources/*.pas', 'providers/*.pas', 'app/*.pas', 'app/*.dpr')
$expected = 'SPDX-License-Identifier: Apache-2.0'
$missing = @()
foreach ($p in $patterns) {
    Get-ChildItem -Path (Join-Path $root $p) -File | ForEach-Object {
        $first = Get-Content -LiteralPath $_.FullName -TotalCount 1
        if ($first -notmatch [regex]::Escape($expected)) { $missing += $_.FullName }
    }
}
if ($missing.Count -gt 0) {
    Write-Host "Missing SPDX header in:"
    $missing | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host "SPDX OK: all production sources carry the Apache-2.0 header."
