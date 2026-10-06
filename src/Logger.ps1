# Logger.ps1
# Smart logging: writes to file always, but only echoes to console when
# something noteworthy happens (fail, profile change, rollback, install).

Set-StrictMode -Version Latest

$script:LogDir        = $null
$script:LogFile       = $null
$script:VerboseLog    = $false
$script:ConsoleMinLevel = 'INFO'

function Initialize-Log {
    param([string]$RepoRoot, [bool]$Verbose)

    $script:LogDir     = Join-Path $RepoRoot 'logs'
    $script:VerboseLog = $Verbose

    if (-not (Test-Path $script:LogDir)) {
        New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
    }
    # New file per day for easy rotation.
    $today = Get-Date -Format 'yyyy-MM-dd'
    $script:LogFile = Join-Path $script:LogDir "steam-auto-$today.log"

    # Silently truncate if file grows over 5 MB.
    if ((Test-Path $script:LogFile) -and (Get-Item $script:LogFile).Length -gt 5MB) {
        $archive = $script:LogFile -replace '\.log$', "-$(Get-Date -Format 'HHmmss').log"
        Move-Item $script:LogFile $archive -Force
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory)][ValidateSet('DEBUG','INFO','WARN','ERROR','OK')][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )

    $ts    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$ts] [$Level] $Message"

    # Always write to file (unless DEBUG and VerboseLog is off).
    if ($Level -ne 'DEBUG' -or $script:VerboseLog) {
        Add-Content -Path $script:LogFile -Value $entry -Encoding UTF8
    }

    # Console: only WARN/ERROR/OK or when verbose mode is enabled.
    $emitToConsole = $false
    switch ($Level) {
        'DEBUG' { if ($script:VerboseLog) { $emitToConsole = $true } }
        'INFO'  { if ($script:VerboseLog) { $emitToConsole = $true } }
        'WARN'  { $emitToConsole = $true }
        'ERROR' { $emitToConsole = $true }
        'OK'    { $emitToConsole = $true }
    }
    if ($emitToConsole) {
        $color = switch ($Level) {
            'WARN'  { 'Yellow' }
            'ERROR' { 'Red' }
            'OK'    { 'Green' }
            default { 'Gray' }
        }
        Write-Host $entry -ForegroundColor $color
    }
}