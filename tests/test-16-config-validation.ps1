# test-16-config-validation.ps1
# Config.ps1 must:
#   - return defaults when config.psd1 is missing
#   - reject configs with bad ProfilesOrder (not array, empty, non-string)
#   - reject configs with non-positive numeric fields
#   - reject configs with non-boolean LogVerbose
#   - reject configs with non-numeric ScoreWeights
#   - accept well-formed overrides
#   - fall back to defaults (not throw) when validation fails
#
# We do NOT modify the real config\config.psd1 in this test - we
# override $script:ConfigPath to point at a temp file at the top level
# of the test script (not inside a helper) so the script-scope write
# is visible to Get-Config.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$root = Split-Path -Parent $here

. (Join-Path $root 'src\Logger.ps1')
Initialize-Log -RepoRoot $root -Verbose:$false | Out-Null
. (Join-Path $root 'src\Config.ps1')

$failures = @()

# Use the original ConfigPath as a baseline so we can restore it at end.
$origConfigPath = $script:ConfigPath

# Helper: write a temp file and return the path. We set $script:ConfigPath
# in the caller's scope via $script: so it's visible to the dot-sourced
# Get-Config in the same script.
function New-TempConfigPath {
    $tmp = Join-Path $env:TEMP "steam-auto-cfg-$([guid]::NewGuid()).psd1"
    return $tmp
}

# 1. Missing file -> defaults.
$script:ConfigPath = Join-Path $env:TEMP 'steam-auto-cfg-missing-psd1.psd1'
if (Test-Path $script:ConfigPath) { Remove-Item $script:ConfigPath -Force }
$cfg = Get-Config
if ($cfg.ProfilesOrder.Count -ne 5) { $failures += "Defaults: expected 5 profiles, got $($cfg.ProfilesOrder.Count)" }

# 2. Bad ProfilesOrder (string instead of array) -> fallback to defaults.
$script:ConfigPath = New-TempConfigPath
Set-Content -Path $script:ConfigPath -Value "@{ ProfilesOrder = 'CloudflareDoH' }" -Encoding UTF8
$cfg = Get-Config
Remove-Item $script:ConfigPath -Force
if ($cfg.ProfilesOrder.Count -ne 5) { $failures += "Bad ProfilesOrder (string): should fall back, got $($cfg.ProfilesOrder.Count) profiles" }

# 3. Bad ProfilesOrder (empty array) -> fallback.
$script:ConfigPath = New-TempConfigPath
Set-Content -Path $script:ConfigPath -Value "@{ ProfilesOrder = @() }" -Encoding UTF8
$cfg = Get-Config
Remove-Item $script:ConfigPath -Force
if ($cfg.ProfilesOrder.Count -ne 5) { $failures += "Bad ProfilesOrder (empty): should fall back" }

# 4. Bad ProfilesOrder (non-string element) -> fallback.
$script:ConfigPath = New-TempConfigPath
Set-Content -Path $script:ConfigPath -Value "@{ ProfilesOrder = @('Cloudflare', 42) }" -Encoding UTF8
$cfg = Get-Config
Remove-Item $script:ConfigPath -Force
if ($cfg.ProfilesOrder.Count -ne 5) { $failures += "Bad ProfilesOrder (non-string): should fall back" }

# 5. Non-positive numeric -> fallback.
$script:ConfigPath = New-TempConfigPath
Set-Content -Path $script:ConfigPath -Value "@{ SelfRestartHours = 0 }" -Encoding UTF8
$cfg = Get-Config
Remove-Item $script:ConfigPath -Force
if ($cfg.SelfRestartHours -ne 6) { $failures += "SelfRestartHours=0: should fall back to 6, got $($cfg.SelfRestartHours)" }

# 6. Non-numeric field -> fallback.
$script:ConfigPath = New-TempConfigPath
Set-Content -Path $script:ConfigPath -Value "@{ SpeedTestBytes = 'lots' }" -Encoding UTF8
$cfg = Get-Config
Remove-Item $script:ConfigPath -Force
if ($cfg.SpeedTestBytes -ne 262144) { $failures += "SpeedTestBytes='lots': should fall back to 262144, got $($cfg.SpeedTestBytes)" }

# 7. Non-boolean LogVerbose -> fallback.
$script:ConfigPath = New-TempConfigPath
Set-Content -Path $script:ConfigPath -Value "@{ LogVerbose = 'yes' }" -Encoding UTF8
$cfg = Get-Config
Remove-Item $script:ConfigPath -Force
if ($cfg.LogVerbose -ne $false) { $failures += "LogVerbose='yes': should fall back to false, got $($cfg.LogVerbose)" }

# 8. Well-formed override is accepted.
# We build the content programmatically because PS 5.1 here-strings have
# known quirks when piped through helper functions. String concatenation
# is more predictable here.
$cfgContent = "@{`n"
$cfgContent += "    ProfilesOrder       = @('Quad9', 'CloudflareDoH')`n"
$cfgContent += "    SelfRestartHours    = 12`n"
$cfgContent += "    ScoreWeights = @{ Latency = 50; Tcp = 50; Https = 0; Speed = 0; Clean = 0 }`n"
$cfgContent += "    LogVerbose          = `$true`n"
$cfgContent += "}`n"
$script:ConfigPath = New-TempConfigPath
[System.IO.File]::WriteAllText($script:ConfigPath, $cfgContent, [System.Text.UTF8Encoding]::new($false))
$cfg = Get-Config
Remove-Item $script:ConfigPath -Force
if ($cfg.ProfilesOrder[0] -ne 'Quad9') { $failures += "ProfilesOrder override: expected Quad9 first, got $($cfg.ProfilesOrder[0])" }
if ($cfg.SelfRestartHours -ne 12)     { $failures += "SelfRestartHours override: expected 12, got $($cfg.SelfRestartHours)" }
if ($cfg.ScoreWeights.Latency -ne 50) { $failures += "ScoreWeights.Latency: expected 50, got $($cfg.ScoreWeights.Latency)" }
if ($cfg.LogVerbose -ne $true)        { $failures += "LogVerbose: expected true, got $($cfg.LogVerbose)" }

# 9. Invalid PS syntax in psd1 -> fallback, not throw.
$script:ConfigPath = New-TempConfigPath
Set-Content -Path $script:ConfigPath -Value "this is not a hashtable" -Encoding UTF8
$cfg = Get-Config
Remove-Item $script:ConfigPath -Force
if ($cfg.ProfilesOrder.Count -ne 5) { $failures += "Invalid PS syntax: should fall back" }

# 10. Get-RepoRoot returns the right path.
$rr = Get-RepoRoot
if ($rr -ne $root) { $failures += "Get-RepoRoot: expected $root, got $rr" }

# Restore original config path so subsequent test scripts in the same
# session aren't affected.
$script:ConfigPath = $origConfigPath

if ($failures.Count -gt 0) {
    Write-Host "  [FAIL] $($failures -join '; ')" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] Missing config returns defaults"
Write-Host "  [OK] Bad ProfilesOrder falls back"
Write-Host "  [OK] Bad numeric falls back"
Write-Host "  [OK] Bad LogVerbose falls back"
Write-Host "  [OK] Well-formed override is accepted"
Write-Host "  [OK] Invalid PS syntax falls back"
Write-Host "  [OK] Get-RepoRoot returns correct path"
Write-Host "Config validation test passed."
exit 0