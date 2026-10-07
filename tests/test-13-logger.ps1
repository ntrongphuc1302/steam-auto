# test-13-logger.ps1
# Logger.ps1 must:
#   - Initialize-Log create logs/ directory
#   - Write-Log not throw before Initialize-Log (used by tests that
#     just dot-source the module) - or fail loudly so the test catches it
#   - Write-Log create log file after Initialize-Log
#   - The file content matches the level and message
#   - Different log levels create entries with the right prefix

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$root = Split-Path -Parent $here

. (Join-Path $root 'src\Logger.ps1')

$failures = @()

# 1. Initialize-Log creates logs/ directory and a log file path.
$logDir = Join-Path $root 'logs'
if (Test-Path $logDir) { Get-ChildItem $logDir -Filter '*.log' -ErrorAction SilentlyContinue | Remove-Item -Force }
Initialize-Log -RepoRoot $root -Verbose:$true
if (-not (Test-Path $logDir)) { $failures += 'Initialize-Log did not create logs/ directory' }
if ($null -eq $script:LogFile) { $failures += 'Initialize-Log did not set $script:LogFile' }

# 2. Write-Log at each level must produce a file with the right prefix.
# Use a side-channel path so we don't pollute the actual log file.
$testLogDir = Join-Path $root 'logs-test'
if (Test-Path $testLogDir) { Remove-Item $testLogDir -Recurse -Force }
$testRoot = $testLogDir  # treat as fake repo root

Initialize-Log -RepoRoot $testRoot -Verbose:$true
Write-Log -Level INFO -Message 'hello-info'
Write-Log -Level WARN -Message 'hello-warn'
Write-Log -Level ERROR -Message 'hello-error'

$today = Get-Date -Format 'yyyy-MM-dd'
$testLogFile = Join-Path (Join-Path $testRoot 'logs') "steam-auto-$today.log"
if (-not (Test-Path $testLogFile)) {
    $failures += 'Write-Log did not create log file under fake root'
} else {
    $content = Get-Content $testLogFile -Raw
    if ($content -notmatch '\[INFO\] hello-info')  { $failures += 'INFO entry not found in log file' }
    if ($content -notmatch '\[WARN\] hello-warn')  { $failures += 'WARN entry not found in log file' }
    if ($content -notmatch '\[ERROR\] hello-error') { $failures += 'ERROR entry not found in log file' }
}

# Cleanup
if (Test-Path $testLogDir) { Remove-Item $testLogDir -Recurse -Force }

if ($failures.Count -gt 0) {
    Write-Host "  [FAIL] $($failures -join '; ')" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] Initialize-Log creates logs/ and log file"
Write-Host "  [OK] Write-Log writes INFO/WARN/ERROR with correct prefix"
Write-Host "Logger test passed."
exit 0