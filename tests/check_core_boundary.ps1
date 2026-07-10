$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$core = Join-Path $root 'sources/*.pas'

# 1. Architectural boundary: sources/ stays engine-agnostic, MCP plumbing lives in providers/.
$bad = Select-String -Path $core -Pattern 'MVCFramework' -SimpleMatch
if ($bad) { $bad | ForEach-Object { Write-Host $_.Path ':' $_.Line }; throw 'Core unit imports MVCFramework - boundary violated' }

# 2. Edition boundary: the free edition only ever asks the database about itself. A unit that
# reads files or spawns processes is how the Enterprise tools (firebird.conf, firebird.log,
# Trace API, gstat) would look, so the core may not do either.
#
# Firebird.PlanAnalyzer is the one sanctioned exception: it drives a LOCAL isql.exe through
# temp files on the client machine. It never touches the server's own files.
#
# Naming server-side tooling inside advisory TEXT is fine and expected - TransactionMonitor
# suggests `gfix -sweep` to the DBA. Only reaching for it in code is a violation.
$hostAccess = 'System\.IOUtils|TFile\.|TDirectory\.|CreateProcess|ShellExecute'
$allowed = 'Firebird.PlanAnalyzer.pas'
$bad = Select-String -Path $core -Pattern $hostAccess |
    Where-Object { (Split-Path $_.Path -Leaf) -ne $allowed }
if ($bad) {
    $bad | ForEach-Object { Write-Host $_.Path ':' $_.Line }
    throw "Core unit reads files or spawns processes - that is Enterprise territory (only $allowed may)"
}

Write-Host 'Core boundary OK: no MVCFramework imports, no host access in sources/'
