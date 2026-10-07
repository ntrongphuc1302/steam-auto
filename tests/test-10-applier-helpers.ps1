# test-10-applier-helpers.ps1
# Unit-test Applier.ps1 helper functions that don't require admin:
#   - Get-ActiveAdapters (must not throw, returns array)
#   - Snapshot-CurrentDns (must not throw, structure is correct)
# The non-admin Set-ProfileDns is covered by test-08b; the E2E
# happy path is covered by test-08.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$root = Split-Path -Parent $here

. (Join-Path $root 'src\Logger.ps1')
. (Join-Path $root 'src\Applier.ps1')

$failures = @()

# 1. Get-ActiveAdapters returns something (possibly empty) and never throws.
try {
    $adapters = @(Get-ActiveAdapters)
} catch {
    $failures += "Get-ActiveAdapters threw: $($_.Exception.Message)"
}

# 2. Snapshot-CurrentDns returns object with expected shape.
try {
    $snap = Snapshot-CurrentDns
    if ($null -eq $snap) { $failures += 'Snapshot-CurrentDns returned null' }
    elseif (-not ($snap.PSObject.Properties['CapturedAt'])) { $failures += 'Snapshot missing CapturedAt' }
    elseif (-not ($snap.PSObject.Properties['Adapters']))  { $failures += 'Snapshot missing Adapters' }
    elseif ($snap.Adapters.Count -ne $adapters.Count) {
        $failures += "Snapshot has $($snap.Adapters.Count) adapters, expected $($adapters.Count)"
    } else {
        # Each adapter entry must have Name, IfIndex, IPv4, IPv6, ServerAddresses.
        foreach ($entry in $snap.Adapters) {
            foreach ($field in @('Name','IfIndex','IPv4','IPv6','ServerAddresses')) {
                if (-not $entry.PSObject.Properties[$field]) {
                    $failures += "Snapshot entry missing field $field"
                }
            }
        }
    }
} catch {
    $failures += "Snapshot-CurrentDns threw: $($_.Exception.Message)"
}

# 3. Restore-DnsFromSnapshot must NOT throw even on a synthetic empty snapshot
#    (worst-case: caller passes something with no adapters - should be a no-op).
try {
    $empty = [pscustomobject]@{ Adapters = @() }
    Restore-DnsFromSnapshot -Snapshot $empty
} catch {
    $failures += "Restore-DnsFromSnapshot threw on empty snapshot: $($_.Exception.Message)"
}

# 4. Restore-DnsFromSnapshot must be tolerant of legacy snapshots that only
#    have ServerAddresses (no IPv4/IPv6 fields). We pass a fake entry so the
#    function exercises the fallback path; since we're not admin we can't
#    really run it, but we can verify the function does not throw on
#    obvious bad shapes either.
try {
    $legacy = [pscustomobject]@{
        Adapters = @(
            [pscustomobject]@{
                IfIndex         = 99999   # non-existent index
                ServerAddresses = @('1.1.1.1')
            }
        )
    }
    Restore-DnsFromSnapshot -Snapshot $legacy
} catch {
    $failures += "Restore-DnsFromSnapshot threw on legacy shape: $($_.Exception.Message)"
}

if ($failures.Count -gt 0) {
    Write-Host "  [FAIL] $($failures -join '; ')" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] Get-ActiveAdapters returns $($adapters.Count) adapter(s)"
Write-Host "  [OK] Snapshot-CurrentDns returns well-formed object"
Write-Host "  [OK] Restore-DnsFromSnapshot handles empty snapshot"
Write-Host "  [OK] Restore-DnsFromSnapshot handles legacy shape"
Write-Host "Applier helpers test passed."
exit 0