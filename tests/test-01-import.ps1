# tests/test-01-import.ps1
# Smoke test: all modules import without errors.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$src      = Join-Path $repoRoot 'src'

$modules = @(
    'Logger.ps1','State.ps1','Config.ps1','Profiles.ps1',
    'Detect.ps1','Prober.ps1','Applier.ps1','Rollback.ps1',
    'Cache.ps1','Watchdog.ps1'
)

$failed = 0
foreach ($m in $modules) {
    try {
        . (Join-Path $src $m)
        Write-Host "  [OK] $m" -ForegroundColor Green
    } catch {
        Write-Host "  [FAIL] $m - $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }
}

if ($failed -gt 0) {
    Write-Host "`n$failed module(s) failed" -ForegroundColor Red
    exit 1
}
Write-Host "`nAll 10 modules imported." -ForegroundColor Green