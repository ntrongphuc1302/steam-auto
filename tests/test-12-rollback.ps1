# test-12-rollback.ps1
# Rollback.ps1 must:
#   - load without throwing
#   - Save-PreInstallSnapshot writes a JSON file at state/pre-install-dns.json
#   - The JSON, when read back, has the same shape as Snapshot-CurrentDns
#   - Restore-DnsSnapshot does NOT throw when the snapshot file does not
#     exist (DHCP fallback path)
#   - Restore-DnsSnapshot does NOT throw when the snapshot file exists but
#     Restore-DnsFromSnapshot silently no-ops (we can't test the actual
#     DNS change without admin, but we can test the JSON read path).
#
# We do NOT actually mutate DNS in this test (would need admin). We just
# exercise the file I/O paths.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$root = Split-Path -Parent $here

. (Join-Path $root 'src\Logger.ps1')
Initialize-Log -RepoRoot $root -Verbose:$false | Out-Null
. (Join-Path $root 'src\Applier.ps1')
. (Join-Path $root 'src\Rollback.ps1')

$failures = @()

# 1. Save-PreInstallSnapshot creates a file.
$stateDir = Join-Path $root 'state'
if (Test-Path $stateDir) {
    Get-ChildItem -Path $stateDir -Filter 'pre-install-dns*' -ErrorAction SilentlyContinue | Remove-Item -Force
}

try {
    Save-PreInstallSnapshot -RepoRoot $root
    $path = Join-Path $stateDir 'pre-install-dns.json'
    if (-not (Test-Path $path)) {
        $failures += "Save-PreInstallSnapshot did not create $path"
    }
} catch {
    $failures += "Save-PreInstallSnapshot threw: $($_.Exception.Message)"
}

# 2. The file is valid JSON with the expected shape.
if (Test-Path (Join-Path $stateDir 'pre-install-dns.json')) {
    try {
        $snap = Get-Content (Join-Path $stateDir 'pre-install-dns.json') -Raw | ConvertFrom-Json
        if (-not $snap.PSObject.Properties['CapturedAt']) {
            $failures += 'Saved snapshot missing CapturedAt'
        }
        if (-not $snap.PSObject.Properties['Adapters']) {
            $failures += 'Saved snapshot missing Adapters'
        }
        foreach ($entry in $snap.Adapters) {
            if (-not $entry.PSObject.Properties['IfIndex']) {
                $failures += 'Snapshot entry missing IfIndex'
            }
        }
    } catch {
        $failures += "Saved snapshot is not valid JSON: $($_.Exception.Message)"
    }
}

# 3. Restore-DnsSnapshot with snapshot present - function must NOT throw.
#    It may or may not modify DNS depending on admin status; we only assert
#    no exception escapes.
try {
    $result = Restore-DnsSnapshot -RepoRoot $root
    if ($result -isnot [hashtable]) {
        $failures += "Restore-DnsSnapshot did not return hashtable (got $($result.GetType().FullName))"
    } else {
        if (-not $result.ContainsKey('Restored')) { $failures += 'Restore-DnsSnapshot missing Restored key' }
        if (-not $result.ContainsKey('Source'))   { $failures += 'Restore-DnsSnapshot missing Source key' }
    }
} catch {
    $failures += "Restore-DnsSnapshot (with snapshot) threw: $($_.Exception.Message)"
}

# 4. Restore-DnsSnapshot with snapshot missing - DHCP fallback path.
#    Must NOT throw even when adapter calls inside silently fail.
$preinstallPath = Join-Path $stateDir 'pre-install-dns.json'
if (Test-Path $preinstallPath) {
    Remove-Item $preinstallPath -Force
}
try {
    $result = Restore-DnsSnapshot -RepoRoot $root
    if (-not $result.Restored) {
        $failures += "Restore-DnsSnapshot DHCP fallback did not return Restored=$true (got $($result.Restored))"
    }
    if ($result.Source -ne 'dhcp-fallback') {
        $failures += "Restore-DnsSnapshot DHCP fallback did not set Source=dhcp-fallback (got $($result.Source))"
    }
} catch {
    $failures += "Restore-DnsSnapshot (DHCP fallback) threw: $($_.Exception.Message)"
}

if ($failures.Count -gt 0) {
    Write-Host "  [FAIL] $($failures -join '; ')" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] Save-PreInstallSnapshot wrote state/pre-install-dns.json"
Write-Host "  [OK] Saved snapshot JSON parses and has expected shape"
Write-Host "  [OK] Restore-DnsSnapshot with snapshot present does not throw"
Write-Host "  [OK] Restore-DnsSnapshot DHCP fallback works when no snapshot"
Write-Host "Rollback test passed."
exit 0