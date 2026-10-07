# tests/test-05-state.ps1
# Verifies atomic state read/write doesn't corrupt on partial write.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'src/State.ps1')

Initialize-State -RepoRoot $repoRoot

# Clean any pre-existing test state.
$sf = Join-Path $repoRoot 'state\state.json'
if (Test-Path $sf) { Remove-Item $sf -Force }

# 1. Empty state = null.
$s1 = Read-State
if ($s1 -ne $null) {
    Write-Host "[FAIL] Initial Read-State should be null" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] Initial state = null" -ForegroundColor Green

# 2. Write + read roundtrip.
Update-State -CurrentProfile 'Cloudflare'
$s2 = Read-State
if ($s2.CurrentProfile -ne 'Cloudflare') {
    Write-Host "[FAIL] Roundtrip: expected Cloudflare, got $($s2.CurrentProfile)" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] Roundtrip Cloudflare" -ForegroundColor Green

# 3. Profile change increments TotalApplies.
Update-State -CurrentProfile 'Google'
$s3 = Read-State
if ($s3.TotalApplies -lt 2) {
    Write-Host "[FAIL] TotalApplies should be >= 2 after second apply, got $($s3.TotalApplies)" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] TotalApplies = $($s3.TotalApplies) after 2 applies" -ForegroundColor Green

# 4. Simulate crash mid-write: create a leftover .tmp, confirm Read still works.
$tmp = "$sf.tmp"
Set-Content -Path $tmp -Value '{broken json' -Force
$s4 = Read-State
if ($s4.CurrentProfile -ne 'Google') {
    Write-Host "[FAIL] Read with leftover .tmp returned garbage" -ForegroundColor Red
    exit 1
}
Remove-Item $tmp -Force
Write-Host "  [OK] Leftover .tmp doesn't corrupt Read" -ForegroundColor Green

# Cleanup test data so uninstall is clean.
Remove-Item $sf -Force -ErrorAction SilentlyContinue

Write-Host "`nState test passed."