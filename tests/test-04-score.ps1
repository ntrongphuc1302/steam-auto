# tests/test-04-score.ps1
# Verifies Compute-ProfileScore handles all branches.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'src/Profiles.ps1')
. (Join-Path $repoRoot 'src/Prober.ps1')

# Override Set-ProfileDns so Prober doesn't actually touch DNS.
function Set-ProfileDns { return }

# Build cases dynamically to avoid PowerShell @() literal/..range parsing quirks.
$cases = New-Object System.Collections.Generic.List[object]

$cases.Add(@{
    Name   = 'perfect'
    Result = [pscustomobject]@{ LatencyMs = 10; TcpOk = $true; HttpsCode = 200; SpeedKbps = 12000; Clean = $true }
    ExpectMin = 100
    ExpectMax = 100
})

$cases.Add(@{
    Name   = 'tcp_blocked'
    Result = [pscustomobject]@{ LatencyMs = 800; TcpOk = $false; HttpsCode = 0; SpeedKbps = 0; Clean = $false }
    ExpectMin = 0
    ExpectMax = 5
})

$cases.Add(@{
    Name   = 'slow_but_works'
    Result = [pscustomobject]@{ LatencyMs = 400; TcpOk = $true; HttpsCode = 200; SpeedKbps = 2000; Clean = $true }
    ExpectMin = 40
    ExpectMax = 75
})

$cases.Add(@{
    Name   = 'captive_portal'
    Result = [pscustomobject]@{ LatencyMs = 30; TcpOk = $true; HttpsCode = 302; SpeedKbps = 5000; Clean = $true }
    ExpectMin = 70
    ExpectMax = 100
})

$failed = 0
foreach ($c in $cases) {
    $score = Compute-ProfileScore -Result $c.Result -SpeedTestBytes 262144
    $ok = ($score -ge $c.ExpectMin) -and ($score -le $c.ExpectMax)
    $color = if ($ok) {'Green'} else {'Red'}
    Write-Host "  $($c.Name): score=$score (expected $($c.ExpectMin)..$($c.ExpectMax))" -ForegroundColor $color
    if (-not $ok) { $failed++ }
}

if ($failed -gt 0) { exit 1 }
Write-Host "`nScore test passed."