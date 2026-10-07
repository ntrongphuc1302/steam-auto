# tests/test-06-watchdog-interval.ps1
# Verifies Get-NextInterval grows and resets correctly.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'src/Watchdog.ps1')

$expected = @{
    0 = 60
    1 = 300
    2 = 900
    3 = 1800
    4 = 3600
    10 = 3600
}

$failed = 0
foreach ($k in $expected.Keys) {
    $got = Get-NextInterval -ConsecutiveOk $k
    $ok  = $got -eq $expected[$k]
    Write-Host "  consecutive=$($k) -> ${got}s (expected $($expected[$k])s)" -ForegroundColor $(if ($ok) {'Green'} else {'Red'})
    if (-not $ok) { $failed++ }
}

if ($failed -gt 0) { exit 1 }
Write-Host "`nWatchdog interval test passed."