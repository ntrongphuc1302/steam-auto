# Config.ps1
# Loads user configuration from config\config.psd1 and provides
# sensible defaults so the tool works out of the box.

Set-StrictMode -Version Latest

# Resolve repo root (the folder that contains 'config\config.psd1').
$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:ConfigPath = Join-Path $script:RepoRoot 'config\config.psd1'

# ----- Defaults (used when config.psd1 is missing or incomplete) -----
$script:Defaults = [pscustomobject]@{
    ProfilesOrder         = @('CloudflareDoH', 'GoogleDoH', 'Cloudflare', 'Google', 'Quad9')
    InitialProbeSeconds   = 60          # Watchdog fast probe when failing
    SteadyProbeSeconds    = 300         # 5 min
    StableProbeSeconds    = 900         # 15 min
    RockSolidProbeSeconds = 1800        # 30 min
    SleepProbeSeconds     = 3600        # 1 h
    SelfRestartHours      = 6           # Exit cleanly every 6h to avoid leaks
    VerifyAfterApplySec   = 30          # Wait before re-checking after apply
    SpeedTestBytes        = 256KB       # Small CDN file size for speed scoring
    LogVerbose            = $false      # Set true to log every probe
    ScoreWeights = [pscustomobject]@{
        Latency = 30
        Tcp     = 25
        Https   = 15
        Speed   = 20
        Clean   = 10
    }
}

function Get-Config {
    if (Test-Path $script:ConfigPath) {
        try {
            $user = Import-PowerShellDataFile -Path $script:ConfigPath -ErrorAction Stop
        } catch {
            try { Write-Log -Level WARN "Config.psd1 is invalid, falling back to defaults: $_" } catch { Write-Warning "Config.psd1 is invalid: $_" }
            return $script:Defaults
        }
        # Merge user settings on top of defaults. We use PSObject.Properties
        # to update existing fields because direct assignment
        # ($merged.$name = $value) silently fails under Set-StrictMode in
        # Windows PowerShell 5.1 - the property keeps its default value.
        $merged = $script:Defaults.PSObject.Copy()
        # Merge user settings on top of defaults. We iterate the hashtable's
        # own keys (NOT $user.PSObject.Properties - that would also walk the
        # Hashtable's IDictionary properties like IsReadOnly/Count and
        # produce gibberish like `merged.IsReadOnly = True`).
        foreach ($key in $user.Keys) {
            $existing = $merged.PSObject.Properties[$key]
            if ($null -ne $existing) {
                $existing.Value = $user[$key]
            } else {
                $merged | Add-Member -NotePropertyName $key -NotePropertyValue $user[$key]
            }
        }
        # Sanity-check the merged result. If the user broke the schema we
        # fall back to defaults rather than crashing the watchdog loop.
        # Sanity-check the merged result. If the user broke the schema we
        # fall back to defaults rather than crashing the watchdog loop.
        if (Test-ConfigValid -Config $merged) {
            return $merged
        } else {
            try { Write-Log -Level WARN "Config.psd1 failed validation, falling back to defaults" } catch { Write-Warning 'Config.psd1 failed validation' }
            return $script:Defaults
        }
    }
    return $script:Defaults
}

function Test-ConfigValid {
    param($Config)

    if ($null -eq $Config) { return $false }
    # ProfilesOrder must be a non-empty array of strings naming known
    # profiles (we don't import Profiles.ps1 here to avoid the cycle; the
    # orchestrator will skip unknown names).
    $po = $Config.ProfilesOrder
    if ($null -eq $po) { return $false }
    if ($po -isnot [System.Array]) { return $false }
    if ($po.Count -eq 0) { return $false }
    foreach ($p in $po) {
        if ($p -isnot [string]) { return $false }
    }
    # Numeric fields must be positive integers.
    foreach ($field in 'InitialProbeSeconds','SteadyProbeSeconds','StableProbeSeconds','RockSolidProbeSeconds','SleepProbeSeconds','SelfRestartHours','VerifyAfterApplySec','SpeedTestBytes') {
        $v = $Config.$field
        if ($null -eq $v) { return $false }
        if ($v -isnot [int] -and $v -isnot [long]) { return $false }
        if ($v -le 0) { return $false }
    }
    # LogVerbose must be a bool.
    if ($null -ne $Config.LogVerbose -and $Config.LogVerbose -isnot [bool]) { return $false }
    # ScoreWeights: each field must be a non-negative number; sum is
    # informational only (test-04 caps the score at 100 anyway).
    if ($null -ne $Config.ScoreWeights) {
        $w = $Config.ScoreWeights
        foreach ($k in 'Latency','Tcp','Https','Speed','Clean') {
            $v = $w.$k
            if ($null -ne $v -and ($v -isnot [int] -and $v -isnot [long] -and $v -isnot [double])) {
                return $false
            }
        }
    }
    return $true
}

function Get-RepoRoot {
    if ($script:RepoRoot -and (Test-Path $script:RepoRoot)) {
        return $script:RepoRoot
    }
    throw "RepoRoot is not set or does not exist: $($script:RepoRoot)"
}