# test-11-watchdog-tick.ps1
# Watchdog.ps1 must:
#   - export Get-NextInterval (already covered by test-06)
#   - export Invoke-WatchdogTick which calls the OnTick scriptblock and
#     returns its boolean result, swallowing exceptions so the loop can
#     continue.
# This does NOT exercise the infinite Start-Watchdog loop because that
# would never return in a test. We just verify the per-tick logic.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$root = Split-Path -Parent $here

. (Join-Path $root 'src\Logger.ps1')
Initialize-Log -RepoRoot $root -Verbose:$false | Out-Null
. (Join-Path $root 'src\Watchdog.ps1')

$failures = @()

# 1. Get-NextInterval boundaries - already covered by test-06 but recheck.
$cases = @(
    @{ in=0;  expected=60   },
    @{ in=1;  expected=300  },
    @{ in=2;  expected=900  },
    @{ in=3;  expected=1800 },
    @{ in=4;  expected=3600 },
    @{ in=99; expected=3600 }
)
foreach ($c in $cases) {
    $got = Get-NextInterval -ConsecutiveOk $c['in']
    if ($got -ne $c['expected']) {
        $failures += "Get-NextInterval($($c['in'])) returned $got, expected $($c['expected'])"
    }
}

# 2. Invoke-WatchdogTick returns the scriptblock's value when it succeeds.
$script:counter = 0
$tick = {
    $script:counter++
    return $true
}
$script:counter = 0
$result = Invoke-WatchdogTick -OnTick $tick
if (-not $result) { $failures += 'Invoke-WatchdogTick did not return $true when OnTick returned $true' }
if ($script:counter -ne 1) { $failures += "OnTick was called $script:counter time(s), expected 1" }

$tick = {
    $script:counter++
    return $false
}
$script:counter = 0
$result = Invoke-WatchdogTick -OnTick $tick
if ($result) { $failures += 'Invoke-WatchdogTick did not return $false when OnTick returned $false' }

# 3. Invoke-WatchdogTick swallows exceptions and returns $false so the
#    outer Start-Watchdog loop does not crash.
$tick = { throw 'synthetic boom' }
$result = Invoke-WatchdogTick -OnTick $tick
if ($result) { $failures += 'Invoke-WatchdogTick should return $false when OnTick throws' }

if ($failures.Count -gt 0) {
    Write-Host "  [FAIL] $($failures -join '; ')" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] Get-NextInterval boundaries match"
Write-Host "  [OK] Invoke-WatchdogTick returns OnTick's boolean"
Write-Host "  [OK] Invoke-WatchdogTick swallows exceptions"
Write-Host "Watchdog tick test passed."
exit 0