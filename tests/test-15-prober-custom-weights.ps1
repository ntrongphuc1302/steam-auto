# test-15-prober-custom-weights.ps1
# Compute-ProfileScore must honour user-supplied weights from
# config\config.psd1 (e.g. user values speed over latency when
# they have a fast CDN but the resolver is slow).
#
# We do NOT call Invoke-ProfileProbe (requires admin + network).
# We only drive Compute-ProfileScore with various weight sets and
# confirm the totals add up to the configured budget.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$root = Split-Path -Parent $here

. (Join-Path $root 'src\Logger.ps1')
Initialize-Log -RepoRoot $root -Verbose:$false | Out-Null
. (Join-Path $root 'src\Prober.ps1')

# Set-ProfileDns is forward-declared in Prober.ps1; override so we
# never trip the "must be defined by Applier.ps1" throw.
function Set-ProfileDns { return }

$failures = @()

# 1. Default weights: budget = 30 + 25 + 15 + 20 + 10 = 100.
$perfect = [pscustomobject]@{ LatencyMs = 10; TcpOk = $true; HttpsCode = 200; SpeedKbps = 12000; Clean = $true }
$score = Compute-ProfileScore -Result $perfect -SpeedTestBytes 262144
if ($score -ne 100) { $failures += "Default weights, perfect result: expected 100, got $score" }

# 2. Custom weights: emphasise speed (40) and clean (20), de-emphasise
#    latency (5) and tcp (10). Budget = 5+10+15+40+20 = 90.
$weights = [pscustomobject]@{
    Latency = 5; Tcp = 10; Https = 15; Speed = 40; Clean = 20
}
$score = Compute-ProfileScore -Result $perfect -SpeedTestBytes 262144 -Weights $weights
if ($score -ne 90) { $failures += "Custom weights, perfect result: expected 90, got $score" }

# 3. Custom weights with all-true components should equal the budget.
$slow   = [pscustomobject]@{ LatencyMs = 10; TcpOk = $true; HttpsCode = 200; SpeedKbps = 12000; Clean = $true }
$score  = Compute-ProfileScore -Result $slow   -SpeedTestBytes 262144 -Weights $weights
if ($score -ne 90) { $failures += "Custom weights, all-true result: expected 90, got $score" }

# 4. HTTPS 4xx gives partial credit proportional to weights (1/3 of wHttp).
$fourOhFour = [pscustomobject]@{ LatencyMs = 10; TcpOk = $true; HttpsCode = 404; SpeedKbps = 0; Clean = $false }
$score = Compute-ProfileScore -Result $fourOhFour -SpeedTestBytes 262144 -Weights $weights
# 5 (lat) + 10 (tcp) + 5 (https 1/3 of 15) + 0 (speed) + 0 (clean) = 20
if ($score -ne 20) { $failures += "HTTPS 4xx with custom weights: expected 20, got $score" }

# 5. Latency > 500ms -> 0 latency points even with custom weights.
$laggy = [pscustomobject]@{ LatencyMs = 800; TcpOk = $true; HttpsCode = 200; SpeedKbps = 12000; Clean = $true }
$score = Compute-ProfileScore -Result $laggy -SpeedTestBytes 262144 -Weights $weights
# 0 (lat) + 10 (tcp) + 15 (https) + 40 (speed) + 20 (clean) = 85
if ($score -ne 85) { $failures += "Laggy with custom weights: expected 85, got $score" }

# 6. Weights with missing fields fall back to defaults.
$partial = [pscustomobject]@{ Latency = 50; Tcp = 50 }   # only 2 of 5
$score = Compute-ProfileScore -Result $perfect -SpeedTestBytes 262144 -Weights $partial
# Latency=50, Tcp=50, Https=15 (default), Speed=20 (default), Clean=10 (default)
# perfect -> 50 + 50 + 15 + 20 + 10 = 145
if ($score -ne 145) { $failures += "Partial weights fallback: expected 145, got $score" }

if ($failures.Count -gt 0) {
    Write-Host "  [FAIL] $($failures -join '; ')" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] Default weights give score=100 for perfect"
Write-Host "  [OK] Custom weights (5/10/15/40/20) honoured"
Write-Host "  [OK] HTTPS 4xx gives 1/3 of wHttp"
Write-Host "  [OK] Latency > 500ms gives 0"
Write-Host "  [OK] Partial weights fall back to defaults"
Write-Host "Prober weights test passed."
exit 0