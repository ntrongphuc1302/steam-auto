# tests/test-02-config.ps1
# Verifies Get-Config returns sensible defaults.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'src/Config.ps1')

$cfg = Get-Config

$tests = @(
    @{ Name='ProfilesOrder is array';      Pass = ($cfg.ProfilesOrder -is [array]) -and ($cfg.ProfilesOrder.Count -ge 3) }
    @{ Name='SelfRestartHours = 6';         Pass = $cfg.SelfRestartHours -eq 6 }
    @{ Name='VerifyAfterApplySec > 0';      Pass = $cfg.VerifyAfterApplySec -gt 0 }
    @{ Name='SpeedTestBytes > 0';           Pass = $cfg.SpeedTestBytes -gt 0 }
    @{ Name='LogVerbose is bool';           Pass = ($cfg.LogVerbose -is [bool]) }
    @{ Name='Weights sum = 100';            Pass = (
        $cfg.ScoreWeights.Latency + $cfg.ScoreWeights.Tcp +
        $cfg.ScoreWeights.Https + $cfg.ScoreWeights.Speed +
        $cfg.ScoreWeights.Clean) -eq 100 }
)

$failed = 0
foreach ($t in $tests) {
    if ($t.Pass) {
        Write-Host "  [OK]   $($t.Name)" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $($t.Name)" -ForegroundColor Red
        $failed++
    }
}

if ($failed -gt 0) { exit 1 }
Write-Host "`nConfig test passed."