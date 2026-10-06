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
            Write-Warning "Config.psd1 is invalid, falling back to defaults: $_"
            return $script:Defaults
        }
        # Merge user settings on top of defaults (shallow merge for scalar fields,
        # full replace for arrays/objects).
        $merged = $script:Defaults.PSObject.Copy()
        foreach ($prop in $user.PSObject.Properties) {
            $merged.$($prop.Name) = $prop.Value
        }
        return $merged
    }
    return $script:Defaults
}

function Get-RepoRoot { $script:RepoRoot }