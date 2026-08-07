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

# A .pas file that is UTF-8 without a byte order mark is read by dcc64 in the machine's ANSI
# code page: an em dash inside a string literal is already three garbage characters at compile
# time, long before anything reaches a client. That shipped once (0.3.0 fixed sixteen files) and
# every editor that rewrites a file whole can bring it back silently, so it is checked here
# rather than remembered.
$noBom = @()
foreach ($p in @('sources/*.pas', 'providers/*.pas', 'app/*.pas', 'app/*.dpr',
                 'tests/coreproject/*.pas', 'tests/coreproject/*.dpr')) {
    Get-ChildItem -Path (Join-Path $root $p) -File | ForEach-Object {
        $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $nonAscii = $false
        foreach ($b in $bytes) { if ($b -gt 127) { $nonAscii = $true; break } }
        if ($nonAscii -and -not $hasBom) { $noBom += $_.FullName }
    }
}
if ($noBom.Count -gt 0) {
    Write-Host "Non-ASCII source without a UTF-8 BOM (dcc64 will read it as ANSI):"
    $noBom | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host "Encoding OK: every non-ASCII Delphi source carries a UTF-8 BOM."
