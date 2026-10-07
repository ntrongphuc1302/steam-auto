# Rollback.ps1
# If a freshly-applied profile doesn't actually unblock Steam, we
# revert to whatever was configured before install.bat ran (or DHCP
# if no snapshot exists).

Set-StrictMode -Version Latest

function Restore-DnsSnapshot {
    param([string]$RepoRoot)

    $path = Join-Path $RepoRoot 'state\pre-install-dns.json'
    if (Test-Path $path) {
        try {
            $snapshot = Get-Content $path -Raw | ConvertFrom-Json
            Restore-DnsFromSnapshot -Snapshot $snapshot
            return @{ Restored = $true; Source = 'snapshot' }
        } catch {
            return @{ Restored = $false; Source = 'snapshot-error'; Error = $_.Exception.Message }
        }
    }

    # No snapshot: fall back to DHCP. Set-DnsClientServerAddress has no
    # -AddressFamily switch on Windows PowerShell 5.1; calling
    # -ResetServerAddresses twice routes by IP format and clears both
    # families.
    foreach ($adapter in (Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.HardwareInterface -eq $true })) {
        try {
            Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses `
                -ErrorAction SilentlyContinue
            Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses `
                -ErrorAction SilentlyContinue
        } catch { }
    }
    ipconfig /flushdns | Out-Null
    return @{ Restored = $true; Source = 'dhcp-fallback' }
}

function Save-PreInstallSnapshot {
    param([string]$RepoRoot)

    $stateDir = Join-Path $RepoRoot 'state'
    if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }

    $path = Join-Path $stateDir 'pre-install-dns.json'
    $snap = Snapshot-CurrentDns
    $snap | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding UTF8
}