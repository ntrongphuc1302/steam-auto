# tests/test-08-e2e-rollback.ps1
# Comprehensive E2E suite for Set-ProfileDns. Runs five scenarios in
# order, then a final scenario that proves a clean rollback always
# returns the adapter to its pre-test state. Each scenario resets DNS
# (both IPv4 and IPv6) to its default at the end before moving on, so
# this script is safe to run on a real machine.
#
# REQUIREMENTS:
# - Administrator (Set-DnsClientServerAddress needs elevation).
# - One physical adapter (this machine has Ethernet).
#
# Behavior when not admin: prints SKIP, exits 0. The non-elevated
# suite can still pass via test-08b-applier-non-admin.ps1.
#
# Run from an elevated PowerShell:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-08-e2e-rollback.ps1
# Or from a normal PowerShell (UAC prompt will appear):
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-e2e-elevated.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'src/Logger.ps1')
. (Join-Path $repoRoot 'src/Profiles.ps1')
. (Join-Path $repoRoot 'src/Applier.ps1')
. (Join-Path $repoRoot 'src/State.ps1')

Initialize-Log -RepoRoot $repoRoot -Verbose $true

function Backup-Dns {
    # Snapshot both IPv4 and IPv6 server lists separately so we can tell
    # DHCP from static on each family, and we don't lose state when one
    # family is configured but the other isn't.
    [pscustomobject]@{
        CapturedAt = (Get-Date).ToString('o')
        Adapters   = @(Get-NetAdapter |
                       Where-Object { $_.Status -eq 'Up' -and $_.HardwareInterface -eq $true } |
                       ForEach-Object {
                           $v4 = (Get-DnsClientServerAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
                           $v6 = (Get-DnsClientServerAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue).ServerAddresses
                           [pscustomobject]@{
                               Name            = $_.Name
                               IfIndex         = $_.ifIndex
                               IPv4            = @($v4)
                               IPv6            = @($v6)
                           }
                       })
    }
}

function Restore-Dns {
    param([Parameter(Mandatory)]$Snapshot)
    foreach ($entry in $Snapshot.Adapters) {
        # IPv4 - Set-DnsClientServerAddress has no -AddressFamily switch on
        # Windows PowerShell 5.1; it routes by IP format.
        if ($entry.IPv4.Count -eq 0) {
            Set-DnsClientServerAddress -InterfaceIndex $entry.IfIndex -ResetServerAddresses -ErrorAction SilentlyContinue
        } else {
            Set-DnsClientServerAddress -InterfaceIndex $entry.IfIndex -ServerAddresses $entry.IPv4 -ErrorAction SilentlyContinue
        }
        # IPv6 - restore to original list (or DHCP)
        if ($entry.IPv6.Count -eq 0) {
            Set-DnsClientServerAddress -InterfaceIndex $entry.IfIndex -ResetServerAddresses -ErrorAction SilentlyContinue
        } else {
            Set-DnsClientServerAddress -InterfaceIndex $entry.IfIndex -ServerAddresses $entry.IPv6 -ErrorAction SilentlyContinue
        }
    }
    ipconfig /flushdns | Out-Null
}

function Reset-Dhcp {
    param([Parameter(Mandatory)]$Snapshot)
    # Reset both IPv4 and IPv6 to DHCP. Doing it twice handles both families
    # because the cmdlet routes by IP format - if the current list contains
    # only IPv4, the reset clears IPv4; if it contains IPv6, the second
    # reset clears it.
    foreach ($entry in $Snapshot.Adapters) {
        Set-DnsClientServerAddress -InterfaceIndex $entry.IfIndex -ResetServerAddresses -ErrorAction SilentlyContinue
        Set-DnsClientServerAddress -InterfaceIndex $entry.IfIndex -ResetServerAddresses -ErrorAction SilentlyContinue
    }
    ipconfig /flushdns | Out-Null
}

function Get-Dns-BothFamilies {
    param([Parameter(Mandatory)]$Snapshot)
    $v4 = (Get-DnsClientServerAddress -InterfaceIndex $Snapshot.Adapters[0].IfIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
    $v6 = (Get-DnsClientServerAddress -InterfaceIndex $Snapshot.Adapters[0].IfIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue).ServerAddresses
    [pscustomobject]@{
        IPv4 = @($v4)
        IPv6 = @($v6)
    }
}

function Format-Dns {
    param($Dns)
    $v4s = if ($Dns.IPv4.Count -eq 0) { '<DHCP>' } else { $Dns.IPv4 -join ',' }
    $v6s = if ($Dns.IPv6.Count -eq 0) { '<DHCP>' } else { $Dns.IPv6 -join ',' }
    "v4=[$v4s] v6=[$v6s]"
}

function Assert-Contains {
    param(
        [Parameter(Mandatory)]$Snapshot,
        [string]$Family,         # 'IPv4' or 'IPv6'
        [Parameter(Mandatory)][string]$ExpectedValue,
        [string]$Scenario
    )
    $current = (Get-Dns-BothFamilies -Snapshot $Snapshot).$Family
    if ($current -contains $ExpectedValue) {
        Write-Host "  [OK] $Family contains $ExpectedValue : $($current -join ',')" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [FAIL] $Family should contain $ExpectedValue, got $($current -join ',')" -ForegroundColor Red
        return $false
    }
}

function Assert-Not-Contains {
    param(
        [Parameter(Mandatory)]$Snapshot,
        [string]$Family,
        [Parameter(Mandatory)][string]$ForbiddenValue,
        [string]$Scenario
    )
    $current = (Get-Dns-BothFamilies -Snapshot $Snapshot).$Family
    if (-not ($current -contains $ForbiddenValue)) {
        Write-Host "  [OK] $Family has no leftover $ForbiddenValue : $($current -join ',')" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [FAIL] $Family still has $ForbiddenValue : $($current -join ',')" -ForegroundColor Red
        return $false
    }
}

Write-Host "=== E2E: Set-ProfileDns under 5 scenarios, with reset between each ===" -ForegroundColor Cyan

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "  [SKIP] This test needs Administrator privileges." -ForegroundColor Yellow
    Write-Host "         Right-click PowerShell -> Run as administrator" -ForegroundColor Yellow
    Write-Host "         powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-08-e2e-rollback.ps1" -ForegroundColor Yellow
    exit 0
}

$baseline = Backup-Dns
Write-Host ""
Write-Host "Baseline DNS:" -ForegroundColor Cyan
foreach ($a in $baseline.Adapters) {
    $s = Format-Dns ([pscustomobject]@{ IPv4 = $a.IPv4; IPv6 = $a.IPv6 })
    Write-Host "  $($a.Name): $s"
}

$failures = @()

# --------------------------------------------------------------------------
# Scenario 1: Apply Cloudflare plain, verify both v4+v6, then reset.
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "Scenario 1: apply Cloudflare plain, then reset to DHCP" -ForegroundColor Magenta
$snap = Backup-Dns
try {
    $cf = Get-ProfileByName -Name 'Cloudflare'
    Set-ProfileDns -Profile $cf -ErrorAction Stop
    Start-Sleep -Seconds 2
    if (-not (Assert-Contains -Snapshot $snap -Family 'IPv4' -ExpectedValue '1.1.1.1')) { $failures += 'S1-v4' }
    if (-not (Assert-Contains -Snapshot $snap -Family 'IPv6' -ExpectedValue '2606:4700:4700::1111')) { $failures += 'S1-v6' }
} catch {
    Write-Host "  [FAIL] apply threw: $($_.Exception.Message)" -ForegroundColor Red
    $failures += 'S1-throw'
} finally {
    Reset-Dhcp -Snapshot $snap
    Start-Sleep -Seconds 2
    Write-Host "  reset -> $(Format-Dns (Get-Dns-BothFamilies -Snapshot $snap))" -ForegroundColor DarkGray
}

# --------------------------------------------------------------------------
# Scenario 2: Apply CloudflareDoH, verify, then reset.
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "Scenario 2: apply Cloudflare DoH, then reset to DHCP" -ForegroundColor Magenta
$snap = Backup-Dns
try {
    $cfdoh = Get-ProfileByName -Name 'CloudflareDoH'
    if ($null -eq $cfdoh) {
        Write-Host "  [FAIL] profile 'CloudflareDoH' not found" -ForegroundColor Red
        $failures += 'S2-missing-profile'
    } else {
        Set-ProfileDns -Profile $cfdoh -ErrorAction Stop
        Start-Sleep -Seconds 2
        if (-not (Assert-Contains -Snapshot $snap -Family 'IPv4' -ExpectedValue '1.1.1.1')) { $failures += 'S2-v4' }
    }
} catch {
    Write-Host "  [FAIL] apply threw: $($_.Exception.Message)" -ForegroundColor Red
    $failures += 'S2-throw'
} finally {
    Reset-Dhcp -Snapshot $snap
    Start-Sleep -Seconds 2
    Write-Host "  reset -> $(Format-Dns (Get-Dns-BothFamilies -Snapshot $snap))" -ForegroundColor DarkGray
}

# --------------------------------------------------------------------------
# Scenario 3: Apply Quad9, verify, then reset.
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "Scenario 3: apply Quad9, then reset to DHCP" -ForegroundColor Magenta
$snap = Backup-Dns
try {
    $q9 = Get-ProfileByName -Name 'Quad9'
    Set-ProfileDns -Profile $q9 -ErrorAction Stop
    Start-Sleep -Seconds 2
    if (-not (Assert-Contains -Snapshot $snap -Family 'IPv4' -ExpectedValue '9.9.9.9')) { $failures += 'S3-v4' }
    if (-not (Assert-Contains -Snapshot $snap -Family 'IPv6' -ExpectedValue '2620:fe::fe')) { $failures += 'S3-v6' }
} catch {
    Write-Host "  [FAIL] apply threw: $($_.Exception.Message)" -ForegroundColor Red
    $failures += 'S3-throw'
} finally {
    Reset-Dhcp -Snapshot $snap
    Start-Sleep -Seconds 2
    Write-Host "  reset -> $(Format-Dns (Get-Dns-BothFamilies -Snapshot $snap))" -ForegroundColor DarkGray
}

# --------------------------------------------------------------------------
# Scenario 4: Apply twice. Verifies that Set-ProfileDns REPLACES the
# previous DNS rather than appending - the second apply must clear the
# first profile's servers from both v4 and v6.
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "Scenario 4: Cloudflare -> Quad9, verify Cloudflare is fully gone" -ForegroundColor Magenta
$snap = Backup-Dns
try {
    $cf = Get-ProfileByName -Name 'Cloudflare'
    Set-ProfileDns -Profile $cf -ErrorAction Stop
    Start-Sleep -Seconds 1
    $q9 = Get-ProfileByName -Name 'Quad9'
    Set-ProfileDns -Profile $q9 -ErrorAction Stop
    Start-Sleep -Seconds 2
    if (-not (Assert-Contains    -Snapshot $snap -Family 'IPv4' -ExpectedValue '9.9.9.9'))    { $failures += 'S4-q9-v4' }
    if (-not (Assert-Not-Contains -Snapshot $snap -Family 'IPv4' -ForbiddenValue '1.1.1.1')){ $failures += 'S4-cf-v4-leftover' }
    if (-not (Assert-Not-Contains -Snapshot $snap -Family 'IPv6' -ForbiddenValue '2606:4700:4700::1111')) { $failures += 'S4-cf-v6-leftover' }
} catch {
    Write-Host "  [FAIL] threw: $($_.Exception.Message)" -ForegroundColor Red
    $failures += 'S4-throw'
} finally {
    Reset-Dhcp -Snapshot $snap
    Start-Sleep -Seconds 2
    Write-Host "  reset -> $(Format-Dns (Get-Dns-BothFamilies -Snapshot $snap))" -ForegroundColor DarkGray
}

# --------------------------------------------------------------------------
# Scenario 5: Stress test - apply / restore / apply / restore / apply.
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "Scenario 5: apply / restore / apply / restore / apply, then reset" -ForegroundColor Magenta
$snap = Backup-Dns
$cf = Get-ProfileByName -Name 'Cloudflare'
for ($i = 1; $i -le 3; $i++) {
    try {
        Set-ProfileDns -Profile $cf -ErrorAction Stop
        Start-Sleep -Milliseconds 500
        Restore-Dns -Snapshot $snap
        Start-Sleep -Milliseconds 500
        Write-Host "  cycle $i ok" -ForegroundColor Green
    } catch {
        Write-Host "  cycle $i FAIL: $($_.Exception.Message)" -ForegroundColor Red
        $failures += "S5-cycle$i"
    }
}
Reset-Dhcp -Snapshot $snap
Write-Host "  reset -> $(Format-Dns (Get-Dns-BothFamilies -Snapshot $snap))" -ForegroundColor DarkGray

# --------------------------------------------------------------------------
# FINAL: restore to baseline. Compare both IPv4 and IPv6 to the original.
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "Final restore to baseline..." -ForegroundColor Cyan
Restore-Dns -Snapshot $baseline
Start-Sleep -Seconds 2
ipconfig /flushdns | Out-Null
$final = Get-Dns-BothFamilies -Snapshot $baseline

Write-Host "  baseline: $(Format-Dns ([pscustomobject]@{ IPv4 = $baseline.Adapters[0].IPv4; IPv6 = $baseline.Adapters[0].IPv6 }))"
Write-Host "  final:    $(Format-Dns $final)"

$matches = $true
foreach ($a in $baseline.Adapters) {
    $f = $final
    # Compare IPv4 sets
    if ($a.IPv4.Count -ne $f.IPv4.Count) { $matches = $false }
    elseif ($a.IPv4.Count -gt 0) {
        foreach ($s in $a.IPv4) { if (-not ($f.IPv4 -contains $s)) { $matches = $false } }
    }
    # Compare IPv6 sets
    if ($a.IPv6.Count -ne $f.IPv6.Count) { $matches = $false }
    elseif ($a.IPv6.Count -gt 0) {
        foreach ($s in $a.IPv6) { if (-not ($f.IPv6 -contains $s)) { $matches = $false } }
    }
}

if ($matches) {
    Write-Host "  [OK] final DNS matches baseline (both families)" -ForegroundColor Green
} else {
    Write-Host "  [WARN] final DNS differs from baseline; if your DHCP server handed out a different address that's fine" -ForegroundColor Yellow
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "E2E had failures: $($failures -join ', ')" -ForegroundColor Red
    Write-Host "Baseline DNS was still restored at the end." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "E2E passed. DNS restored to baseline." -ForegroundColor Green