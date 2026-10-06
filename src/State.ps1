# State.ps1
# Persists runtime state atomically: current DNS snapshot, last known
# good profile, probe history. Writes to a temp file then renames so a
# crash mid-write cannot corrupt state.

Set-StrictMode -Version Latest

$script:StateDir  = $null
$script:StateFile = $null

function Initialize-State {
    param([string]$RepoRoot)

    $script:StateDir  = Join-Path $RepoRoot 'state'
    $script:StateFile = Join-Path $script:StateDir 'state.json'

    if (-not (Test-Path $script:StateDir)) {
        New-Item -ItemType Directory -Path $script:StateDir -Force | Out-Null
    }
}

function Read-State {
    if (Test-Path $script:StateFile) {
        try {
            return Get-Content $script:StateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            return $null
        }
    }
    return $null
}

function Save-State {
    param([Parameter(Mandatory)]$State)

    # Atomic write: temp file + rename. A crash mid-write leaves the
    # previous good file untouched.
    $tmp = "$($script:StateFile).tmp"
    $json = $State | ConvertTo-Json -Depth 10
    Set-Content -Path $tmp -Value $json -Encoding UTF8 -Force
    Move-Item -Path $tmp -Destination $script:StateFile -Force
}

function Update-State {
    param(
        [string]$CurrentProfile = $null,
        [string]$PreviousProfile = $null,
        [object]$DnsSnapshot = $null,
        [string]$ConsecutiveOkProfile = $null,
        [int]$ConsecutiveOkCount = 0
    )

    $state = Read-State
    if (-not $state) {
        $state = [pscustomobject]@{
            CurrentProfile        = $null
            PreviousProfile        = $null
            DnsSnapshot           = $null
            ConsecutiveOkProfile  = $null
            ConsecutiveOkCount    = 0
            LastUpdated           = $null
            TotalApplies          = 0
        }
    }

    if ($PSBoundParameters.ContainsKey('CurrentProfile') -and $CurrentProfile) {
        if ($state.CurrentProfile -ne $CurrentProfile) {
            $state.PreviousProfile = $state.CurrentProfile
            $state.TotalApplies   += 1
        }
        $state.CurrentProfile = $CurrentProfile
    }
    if ($PSBoundParameters.ContainsKey('DnsSnapshot') -and $DnsSnapshot) {
        $state.DnsSnapshot = $DnsSnapshot
    }
    if ($PSBoundParameters.ContainsKey('ConsecutiveOkProfile')) {
        $state.ConsecutiveOkProfile = $ConsecutiveOkProfile
    }
    if ($PSBoundParameters.ContainsKey('ConsecutiveOkCount')) {
        $state.ConsecutiveOkCount = $ConsecutiveOkCount
    }

    $state.LastUpdated = (Get-Date).ToString('o')
    Save-State $state
    return $state
}