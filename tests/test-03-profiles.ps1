# tests/test-03-profiles.ps1
# Verifies Get-AllProfiles returns 5 profiles, all required fields present.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'src/Profiles.ps1')

$profiles = Get-AllProfiles
if ($profiles.Count -ne 5) {
    Write-Host "[FAIL] Expected 5 profiles, got $($profiles.Count)" -ForegroundColor Red
    exit 1
}

$requiredFields = @('Name','DoH','IPv4','IPv6','DohTemplate','Description')
$failed = 0

foreach ($p in $profiles) {
    foreach ($f in $requiredFields) {
        if ($null -eq $p.$f) {
            Write-Host "  [FAIL] $($p.Name) missing field $f" -ForegroundColor Red
            $failed++
            continue
        }
    }
    if ($p.IPv4.Count -lt 2) {
        Write-Host "  [FAIL] $($p.Name) has < 2 IPv4 servers" -ForegroundColor Red
        $failed++
    }
    if ($p.DoH -and [string]::IsNullOrEmpty($p.DohTemplate)) {
        Write-Host "  [FAIL] $($p.Name) DoH=true but no template" -ForegroundColor Red
        $failed++
    }
    Write-Host "  [OK] $($p.Name) DoH=$($p.DoH) IPv4=$($p.IPv4 -join ',')" -ForegroundColor Green
}

if ($failed -gt 0) { exit 1 }
Write-Host "`nProfiles test passed."