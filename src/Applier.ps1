# Applier.ps1
# Applies a profile (DNS + optional DoH) to all active physical
# adapters. Also exports a Set-ProfileDns function that Prober.ps1
# consumes so the probe loop can swap profiles quickly.

Set-StrictMode -Version Latest

function Get-ActiveAdapters {
    Get-NetAdapter | Where-Object {
        $_.Status -eq 'Up' -and $_.HardwareInterface -eq $true
    }
}

function Set-ProfileDns {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Profile)

    $adapters = Get-ActiveAdapters
    if (-not $adapters) { throw 'No active physical adapter found' }

    $servers = $Profile.IPv4 + $Profile.IPv6

    foreach ($adapter in $adapters) {
        Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex `
            -ServerAddresses $servers -ErrorAction SilentlyContinue

        if ($Profile.DoH -and $Profile.DohTemplate) {
            foreach ($ip in $Profile.IPv4) {
                try {
                    Set-DnsClientDohServerAddress -ServerAddress $ip `
                        -DohTemplate $Profile.DohTemplate -ErrorAction SilentlyContinue
                } catch { }
            }
        } else {
            # Profile without DoH: clear any previously-set DoH mapping
            # for these servers (best-effort; ignore failures).
            foreach ($ip in $Profile.IPv4) {
                try {
                    Remove-DnsClientDohServerAddress -ServerAddress $ip -ErrorAction SilentlyContinue
                } catch { }
            }
        }
    }
}

function Snapshot-CurrentDns {
    # Capture the current DNS state so Rollback.ps1 can restore it.
    $snapshot = [pscustomobject]@{
        CapturedAt   = (Get-Date).ToString('o')
        Adapters     = @()
    }

    foreach ($adapter in (Get-ActiveAdapters)) {
        $servers = (Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue).ServerAddresses
        $snapshot.Adapters += [pscustomobject]@{
            Name         = $adapter.Name
            IfIndex      = $adapter.ifIndex
            ServerAddresses = @($servers)
        }
    }
    return $snapshot
}

function Restore-DnsFromSnapshot {
    param([Parameter(Mandatory)]$Snapshot)

    foreach ($entry in $Snapshot.Adapters) {
        if ($entry.ServerAddresses.Count -eq 0) {
            # Original was DHCP.
            Set-DnsClientServerAddress -InterfaceIndex $entry.IfIndex -ResetServerAddresses `
                -ErrorAction SilentlyContinue
        } else {
            Set-DnsClientServerAddress -InterfaceIndex $entry.IfIndex `
                -ServerAddresses $entry.ServerAddresses -ErrorAction SilentlyContinue
        }
    }
    ipconfig /flushdns | Out-Null
}

# Make Set-ProfileDns available to Prober.ps1 (it forward-declares it).
# This is loaded after Prober.ps1 in the orchestrator, so the function
# is set up correctly when probe runs.
if ($global:Prober) {
    # no-op; the real override happens in steam-auto.ps1 by re-importing
    # this file after Prober.ps1.
}