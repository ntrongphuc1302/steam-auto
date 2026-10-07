# tests/test-08b-applier-non-admin.ps1
# Verifies that Set-ProfileDns throws a clear error when run without
# administrator privileges, instead of silently failing. This is the
# non-admin counterpart of test-08-e2e-rollback.ps1 - both can pass
# in any environment.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'src/Logger.ps1')
. (Join-Path $repoRoot 'src/Profiles.ps1')
. (Join-Path $repoRoot 'src/Applier.ps1')
. (Join-Path $repoRoot 'src/State.ps1')

Initialize-Log -RepoRoot $repoRoot -Verbose $true

Write-Host "=== Applier: non-admin must throw, not silently fail ===" -ForegroundColor Cyan

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    Write-Host "  [SKIP] Already elevated - this test only verifies the non-admin code path." -ForegroundColor Yellow
    Write-Host "         Run from a normal PowerShell to verify the guard." -ForegroundColor Yellow
    exit 0
}

# Capture baseline DNS so we can prove nothing was changed.
$baseline = (Get-DnsClientServerAddress -InterfaceAlias 'Ethernet' -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
Write-Host "Baseline DNS: $($baseline -join ',')"

$threw = $false
$msg = ''
try {
    $cf = Get-ProfileByName -Name 'Cloudflare'
    Set-ProfileDns -Profile $cf -ErrorAction Stop
} catch {
    $threw = $true
    $msg = $_.Exception.Message
}

Start-Sleep -Seconds 2
$after = (Get-DnsClientServerAddress -InterfaceAlias 'Ethernet' -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
Write-Host "After:        $($after -join ',')"

$failures = @()
if (-not $threw) {
    Write-Host "  [FAIL] Set-ProfileDns did not throw without admin (silent change risk)" -ForegroundColor Red
    $failures += 'no-throw'
} else {
    Write-Host "  [OK] Set-ProfileDns threw: $msg" -ForegroundColor Green
}

$sameDns = ($baseline -join ',') -eq ($after -join ',')
if ($sameDns) {
    Write-Host "  [OK] DNS unchanged (no silent modification)" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] DNS changed without admin: $($baseline -join ',') -> $($after -join ',')" -ForegroundColor Red
    $failures += 'dns-changed'
}

if ($failures.Count -gt 0) {
    exit 1
}
Write-Host "`nNon-admin guard test passed." -ForegroundColor Green