$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$patterns = @('sources/*.pas', 'providers/*.pas', 'app/*.pas', 'app/*.dpr')
$expected = 'SPDX-License-Identifier: LicenseRef-PolyForm-Internal-Use-1.0.0'
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
Write-Host "SPDX OK: all production sources carry the PolyForm Internal Use header."
