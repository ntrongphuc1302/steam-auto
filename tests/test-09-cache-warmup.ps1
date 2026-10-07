# test-09-cache-warmup.ps1
# Cache.ps1 must be importable and Invoke-DnsWarmup must complete without
# throwing. We don't assert that specific entries landed in the OS cache
# (would be flaky); we only assert the function ran and was idempotent.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$root = Split-Path -Parent $here

# dot-source dependencies, then the module under test
. (Join-Path $root 'src\Logger.ps1')

. (Join-Path $root 'src\Cache.ps1')

$failures = @()

# 1. Module exposes the function the orchestrator will call.
if (-not (Get-Command Invoke-DnsWarmup -ErrorAction SilentlyContinue)) {
    $failures += 'Invoke-DnsWarmup not exported'
}

# 2. WarmupHosts is non-empty.
if (-not $script:WarmupHosts -or $script:WarmupHosts.Count -lt 3) {
    $failures += "WarmupHosts missing or too small (count=$($script:WarmupHosts.Count))"
}

# 3. Invoke twice; the second call must not throw and must return quickly.
try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-DnsWarmup -RepoRoot $root
    $sw.Stop()
    if ($sw.ElapsedMilliseconds -gt 15000) {
        $failures += "Warmup took too long on first call ($($sw.ElapsedMilliseconds)ms)"
    }
} catch {
    $failures += "First Invoke-DnsWarmup threw: $($_.Exception.Message)"
}

try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-DnsWarmup -RepoRoot $root
    $sw.Stop()
    if ($sw.ElapsedMilliseconds -gt 15000) {
        $failures += "Warmup took too long on second call ($($sw.ElapsedMilliseconds)ms)"
    }
} catch {
    $failures += "Second Invoke-DnsWarmup threw: $($_.Exception.Message)"
}

if ($failures.Count -gt 0) {
    Write-Host "  [FAIL] $($failures -join '; ')" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] Cache.ps1 exports Invoke-DnsWarmup"
Write-Host "  [OK] WarmupHosts has $($script:WarmupHosts.Count) entries"
Write-Host "  [OK] Two consecutive warmups completed without throwing"
Write-Host "Cache warmup test passed."
exit 0