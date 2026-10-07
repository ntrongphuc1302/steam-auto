# steam-auto.ps1
# Orchestrator. Imports the small library of helpers in src/, runs
# one tick (detect -> probe -> pick -> apply -> verify -> rollback if
# needed), and is also the script the watchdog loops on.

[CmdletBinding()]
param(
    [switch]$Watchdog,
    [switch]$Once,
    [switch]$Uninstall,
    [switch]$Install
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$src      = Join-Path $repoRoot 'src'

# Import libraries in dependency order.
. (Join-Path $src 'Logger.ps1')
. (Join-Path $src 'State.ps1')
. (Join-Path $src 'Config.ps1')
. (Join-Path $src 'Profiles.ps1')
. (Join-Path $src 'Detect.ps1')
. (Join-Path $src 'Prober.ps1')
. (Join-Path $src 'Applier.ps1')
. (Join-Path $src 'Rollback.ps1')
. (Join-Path $src 'Cache.ps1')
. (Join-Path $src 'Watchdog.ps1')

$config = Get-Config
Initialize-Log -RepoRoot $repoRoot -Verbose:$config.LogVerbose
Initialize-State -RepoRoot $repoRoot

# ----- CLI sub-commands -----
if ($Uninstall) {
    Write-Log -Level WARN "Uninstall requested"
    $rb = Restore-DnsSnapshot -RepoRoot $repoRoot
    Write-Log -Level OK "DNS restored from: $($rb.Source)"
    schtasks /delete /tn 'SteamAuto' /f 2>$null
    Write-Log -Level OK 'Scheduled task removed'
    exit 0
}

if ($Install) {
    Write-Log -Level INFO 'Recording pre-install DNS snapshot'
    Save-PreInstallSnapshot -RepoRoot $repoRoot
    Write-Log -Level OK 'Snapshot saved to state\pre-install-dns.json'
    exit 0
}

# ----- Core orchestration -----

function Invoke-OneTick {
    # Returns $true if Steam is reachable after the tick, $false otherwise.
    if (Test-SteamReachable) {
        return $true
    }

    $kind = Get-BlockKind
    Write-Log -Level WARN "Steam unreachable, block-kind=$kind"

    # Probe all profiles in user's preferred order.
    $order = $config.ProfilesOrder
    $results = @()

    # Save original DNS so we can revert after probing.
    $original = Snapshot-CurrentDns

    try {
        foreach ($name in $order) {
            $profile = Get-ProfileByName -Name $name
            if (-not $profile) { continue }

            # Skip profiles that obviously cannot help.
            if ($kind -eq 'ip' -and -not $profile.DoH) { continue }

            $r = Invoke-ProfileProbe -Profile $profile -SpeedTestBytes $config.SpeedTestBytes -Weights $config.ScoreWeights
            $results += $r
            Write-Log -Level INFO ("probed {0,-14} latency={1,5}ms tcp={2} https={3,3} score={4,3}" -f $r.Profile, $r.LatencyMs, $r.TcpOk, $r.HttpsCode, $r.Score)
        }
    } finally {
        # Always restore the user's original DNS before applying winner.
        Restore-DnsFromSnapshot -Snapshot $original
    }

    if ($results.Count -eq 0) {
        Write-Log -Level ERROR 'No profiles produced a result'
        return $false
    }

    $winner = $results | Sort-Object Score -Descending | Select-Object -First 1
    if ($winner.Score -le 0) {
        Write-Log -Level ERROR 'Best profile scored 0, leaving DNS unchanged'
        return $false
    }

    Write-Log -Level OK "Winner: $($winner.Profile) score=$($winner.Score)"
    $winningProfile = Get-ProfileByName -Name $winner.Profile
    if (-not $winningProfile) {
        Write-Log -Level ERROR "Winner '$($winner.Profile)' not in profile table, cannot apply"
        return $false
    }
    Set-ProfileDns -Profile $winningProfile
    Update-State -CurrentProfile $winningProfile.Name -DnsSnapshot $original

    # Pre-warm cache for the new resolver. We pass -RepoRoot for future
    # use; current implementation does not need it, but keeps the call
    # site consistent with the rest of the codebase.
    Invoke-DnsWarmup -RepoRoot $repoRoot

    # Wait then verify.
    Start-Sleep -Seconds $config.VerifyAfterApplySec
    if (Test-SteamReachable) {
        Write-Log -Level OK "Steam reachable after applying $($winner.Profile)"
        return $true
    }

    # Verify failed -> rollback to pre-tick DNS.
    Write-Log -Level WARN "Verification failed, rolling back to pre-tick DNS"
    Restore-DnsFromSnapshot -Snapshot $original
    return $false
}

if ($Watchdog) {
    Start-Watchdog -SelfRestartHours $config.SelfRestartHours -OnTick { Invoke-OneTick }
    exit 0
}

# Default mode (called by install.bat once after registering the task):
# single tick + warmup.
Invoke-DnsWarmup -RepoRoot $repoRoot
$ok = Invoke-OneTick
exit $(if ($ok) { 0 } else { 1 })