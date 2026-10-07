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

function Test-IpAddressV4 {
    param([string]$Address)
    if ([string]::IsNullOrEmpty($Address)) { return $false }
    return ($Address -as [System.Net.IPAddress]) -and ($Address -notmatch ':')
}

function Test-IpAddressV6 {
    param([string]$Address)
    if ([string]::IsNullOrEmpty($Address)) { return $false }
    return ($Address -as [System.Net.IPAddress]) -and ($Address -match ':')
}

function Set-ProfileDns {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Profile)

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw 'Set-ProfileDns requires Administrator privileges. Re-run from an elevated PowerShell session.'
    }

    # Validate the profile object before touching the network stack. A
    # malformed profile (missing IPv4, IPv4 with IPv6 strings) would set
    # bogus DNS and we might not notice until Steam stops resolving.
    if ($null -eq $Profile) { throw 'Set-ProfileDns: $Profile is null' }
    if ($null -eq $Profile.Name) { throw 'Set-ProfileDns: profile is missing Name' }
    if (-not $Profile.IPv4 -or @($Profile.IPv4).Count -eq 0) {
        throw "Set-ProfileDns: profile '$($Profile.Name)' has no IPv4 servers"
    }
    foreach ($ip in $Profile.IPv4) {
        if (-not (Test-IpAddressV4 $ip)) {
            throw "Set-ProfileDns: profile '$($Profile.Name)' IPv4 list contains non-IPv4 value '$ip'"
        }
    }
    if ($Profile.IPv6) {
        foreach ($ip in $Profile.IPv6) {
            if (-not (Test-IpAddressV6 $ip)) {
                throw "Set-ProfileDns: profile '$($Profile.Name)' IPv6 list contains non-IPv6 value '$ip'"
            }
        }
    }
    if ($Profile.DoH -and [string]::IsNullOrEmpty($Profile.DohTemplate)) {
        throw "Set-ProfileDns: profile '$($Profile.Name)' has DoH=$true but no DohTemplate"
    }

    $adapters = Get-ActiveAdapters
    if (-not $adapters) { throw 'No active physical adapter found' }

    $failures = @()

    foreach ($adapter in $adapters) {
        # IPv4 - Set-DnsClientServerAddress has no -AddressFamily switch on
        # Windows PowerShell 5.1; it filters by IP format, so passing only
        # IPv4 addresses sets only IPv4.
        try {
            Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex `
                -ServerAddresses $Profile.IPv4 -ErrorAction Stop
        } catch {
            $failures += "$($adapter.Name)/v4"
            Write-Log -Level Warn -Message "Failed to apply v4 on $($adapter.Name): $($_.Exception.Message)"
        }

        # IPv6 - separate call. If profile has no IPv6, reset (DHCP).
        if ($Profile.IPv6 -and $Profile.IPv6.Count -gt 0) {
            try {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex `
                    -ServerAddresses $Profile.IPv6 -ErrorAction Stop
            } catch {
                $failures += "$($adapter.Name)/v6"
                Write-Log -Level Warn -Message "Failed to apply v6 on $($adapter.Name): $($_.Exception.Message)"
            }
        } else {
            Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex `
                -ResetServerAddresses -ErrorAction SilentlyContinue
        }

        Write-Log -Level Info -Message "Applied $($Profile.Name) to adapter $($adapter.Name)"

        # DoH (only IPv4 DoH is supported by Windows built-in client)
        if ($Profile.DoH -and -not [string]::IsNullOrEmpty($Profile.DohTemplate)) {
            foreach ($ip in $Profile.IPv4) {
                try {
                    Set-DnsClientDohServerAddress -ServerAddress $ip `
                        -DohTemplate $Profile.DohTemplate -ErrorAction Stop
                } catch {
                    Write-Log -Level Warn -Message "DoH setup failed for $ip on $($adapter.Name): $($_.Exception.Message)"
                }
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

    ipconfig /flushdns | Out-Null

    if ($failures.Count -gt 0) {
        throw "Set-ProfileDns failed on: $($failures -join ', ')"
    }
}

function Snapshot-CurrentDns {
    # Capture the current DNS state so Rollback.ps1 can restore it.
    # Stores IPv4 and IPv6 separately so we can tell DHCP from a configured
    # list on each family. Nulls in the captured arrays are filtered out
    # so Restore-DnsFromSnapshot does not try to set "null" as a server.
    $snapshot = [pscustomobject]@{
        CapturedAt   = (Get-Date).ToString('o')
        Adapters     = @()
    }

    foreach ($adapter in (Get-ActiveAdapters)) {
        $v4raw = Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        $v6raw = Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue
        $v4 = @(($v4raw.ServerAddresses | Where-Object { $_ }) )
        $v6 = @(($v6raw.ServerAddresses | Where-Object { $_ }) )
        $snapshot.Adapters += [pscustomobject]@{
            Name            = $adapter.Name
            IfIndex         = $adapter.ifIndex
            IPv4            = $v4
            IPv6            = $v6
            ServerAddresses = $v4   # legacy field, kept for backward compatibility
        }
    }
    return $snapshot
}

function Restore-DnsFromSnapshot {
    param([Parameter(Mandatory)]$Snapshot)

    foreach ($entry in $Snapshot.Adapters) {
        # IPv4 - prefer the explicit IPv4 field, fall back to legacy
        # ServerAddresses when reading snapshots saved before we split
        # the two address families. PSObject.Properties check handles both
        # shapes without throwing on missing fields.
        if ($entry.PSObject.Properties['IPv4'] -and $entry.IPv4 -and $entry.IPv4.Count -gt 0) {
            Set-DnsClientServerAddress -InterfaceIndex $entry.IfIndex `
                -ServerAddresses $entry.IPv4 -ErrorAction SilentlyContinue
        } elseif ($entry.PSObject.Properties['ServerAddresses'] -and $entry.ServerAddresses -and $entry.ServerAddresses.Count -gt 0) {
            Set-DnsClientServerAddress -InterfaceIndex $entry.IfIndex `
                -ServerAddresses $entry.ServerAddresses -ErrorAction SilentlyContinue
        } else {
            Set-DnsClientServerAddress -InterfaceIndex $entry.IfIndex `
                -ResetServerAddresses -ErrorAction SilentlyContinue
        }
        # IPv6 - same defensive fallback. Legacy entries had no IPv6 field at
        # all, so default to DHCP.
        if ($entry.PSObject.Properties['IPv6'] -and $entry.IPv6 -and $entry.IPv6.Count -gt 0) {
            Set-DnsClientServerAddress -InterfaceIndex $entry.IfIndex `
                -ServerAddresses $entry.IPv6 -ErrorAction SilentlyContinue
        } else {
            Set-DnsClientServerAddress -InterfaceIndex $entry.IfIndex `
                -ResetServerAddresses -ErrorAction SilentlyContinue
        }
    }
    ipconfig /flushdns | Out-Null
}

# Set-ProfileDns is intentionally defined here in Applier.ps1. The
# orchestrator dot-sources Applier.ps1 AFTER Prober.ps1, so the forward
# declaration `function Set-ProfileDns { throw ... }` in Prober.ps1 is
# shadowed by this real definition before Invoke-ProfileProbe runs.