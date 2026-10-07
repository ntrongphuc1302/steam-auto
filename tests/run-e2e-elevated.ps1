# tests/run-e2e-elevated.ps1
# Run test-08-e2e-rollback.ps1 in a new elevated PowerShell window.
# Use this from a regular PowerShell. A UAC prompt will appear.

$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'test-08-e2e-rollback.ps1'

if (-not (Test-Path $script)) {
    throw "Test script not found: $script"
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    Write-Host "Already elevated. Running directly..."
    & $script
    exit $LASTEXITCODE
}

Write-Host "Re-launching elevated (UAC prompt will appear)..."
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName         = 'powershell.exe'
$psi.Arguments        = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $script)
$psi.WorkingDirectory = $PSScriptRoot
$psi.UseShellExecute  = $true
$psi.Verb             = 'runas'
$p = [System.Diagnostics.Process]::Start($psi)
$p.WaitForExit()
Write-Host "Test exit code: $($p.ExitCode)"
exit $p.ExitCode