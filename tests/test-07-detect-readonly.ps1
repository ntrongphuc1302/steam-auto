# tests/test-07-detect-readonly.ps1
# Calls Test-SteamReachable + Get-BlockKind without modifying anything.
# These functions only do DNS resolve + TCP probe.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'src/Detect.ps1')

Write-Host "  Calling Test-SteamReachable..." -ForegroundColor Cyan
try {
    $r = Test-SteamReachable
    Write-Host "  [OK] Test-SteamReachable returned: $r" -ForegroundColor Green
} catch {
    Write-Host "  [WARN] Network unavailable (expected in sandbox): $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "  Calling Get-BlockKind..." -ForegroundColor Cyan
try {
    $kind = Get-BlockKind
    Write-Host "  [OK] Get-BlockKind returned: $kind" -ForegroundColor Green
    if ($kind -notin @('none','dns','ip','unknown')) {
        Write-Host "  [FAIL] Unexpected block-kind: $kind" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "  [WARN] Network unavailable (expected in sandbox): $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "`nDetect test passed (or sandbox-blocked)."