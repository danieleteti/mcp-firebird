$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$core = Join-Path $root 'sources/*.pas'

# 1. Architectural boundary: sources/ stays engine-agnostic, MCP plumbing lives in providers/.
$bad = Select-String -Path $core -Pattern 'MVCFramework' -SimpleMatch
if ($bad) { $bad | ForEach-Object { Write-Host $_.Path ':' $_.Line }; throw 'Core unit imports MVCFramework - boundary violated' }

# 2. Edition boundary: the free edition uses an ordinary SQL connection and nothing more.
#
# Two ways a unit can cross into Enterprise territory, and both must fail the build:
#   a) reading the server's files or spawning processes (firebird.conf, gstat, gfix);
#   b) attaching to the SERVICES MANAGER, which is an administrative privilege, not a query.
#      This is the one that is easy to miss: the Services API streams firebird.log and the
#      Trace API back over the wire, so it touches no file and spawns no process - and would
#      have slipped straight through a filesystem-only check.
#
# Firebird.PlanAnalyzer is the one sanctioned exception to (a): it drives a LOCAL isql.exe
# through temp files on the client machine. It never touches the server's own files.
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

$servicesApi = 'isc_service_|isc_spb_|isc_action_svc_|TFDPhysFBService|service_mgr'
$bad = Select-String -Path $core -Pattern $servicesApi
if ($bad) {
    $bad | ForEach-Object { Write-Host $_.Path ':' $_.Line }
    throw 'Core unit attaches to the Services Manager - that is an admin privilege, and Enterprise territory'
}

Write-Host 'Core boundary OK: no MVCFramework imports, no host access, no Services Manager in sources/'
