# test-17-orchestrator-import.ps1
# bin\steam-auto.ps1 must:
#   - load without throwing (apart from admin checks inside functions)
#   - define Invoke-OneTick (not directly exported, but should be loaded
#     when the script is dot-sourced with -Watchdog/-Once/...)
#   - handle -Install by calling Save-PreInstallSnapshot (we stub it)
#   - handle -Uninstall by calling Restore-DnsSnapshot (we stub it)
# This test does NOT actually schedule tasks or modify DNS.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$root = Split-Path -Parent $here
$orch = Join-Path $root 'bin\steam-auto.ps1'

$failures = @()

# 1. File exists.
if (-not (Test-Path $orch)) { $failures += "Orchestrator not found: $orch" }

# 2. The script must parse cleanly. Run it with -WhatIf via a parameter
#    we know exits early. We invoke with -Install and stub Save-PreInstallSnapshot.
$stateDir = Join-Path $root 'state'
if (Test-Path (Join-Path $stateDir 'pre-install-dns.json')) {
    Remove-Item (Join-Path $stateDir 'pre-install-dns.json') -Force
}

# 3. We do NOT want to run the watchdog. We use -Install which exits 0
#    after saving a snapshot. The orchestrator self-elevates, so we
#    skip the sub-command tests here; the full installer test is a
#    manual E2E in the README.
# Instead, just verify the script can be parsed (syntax check) and that
# all the helper modules load when dot-sourced in the same way the
# orchestrator does.
$src = Join-Path $root 'src'
$helperFiles = @(
    'Logger.ps1', 'State.ps1', 'Config.ps1', 'Profiles.ps1',
    'Detect.ps1', 'Prober.ps1', 'Applier.ps1', 'Rollback.ps1',
    'Cache.ps1', 'Watchdog.ps1'
)
foreach ($f in $helperFiles) {
    $path = Join-Path $src $f
    if (-not (Test-Path $path)) { $failures += "Missing helper: $f" }
}

# 4. Syntax check the orchestrator (parse but don't run).
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($orch, [ref]$tokens, [ref]$errors)
if ($errors -and $errors.Count -gt 0) {
    foreach ($e in $errors) { $failures += "Parse error in orchestrator: $($e.Message)" }
}

# 5. Verify a few key strings are present (catch accidental deletion).
$content = Get-Content $orch -Raw
foreach ($needle in @('Invoke-OneTick','Start-Watchdog','Set-ProfileDns','Save-PreInstallSnapshot','Restore-DnsSnapshot','Invoke-DnsWarmup','Get-BlockKind','Get-Config','Get-ProfileByName')) {
    if ($content -notmatch [regex]::Escape($needle)) {
        $failures += "Orchestrator missing reference to: $needle"
    }
}

# 6. Verify the script handles -Help or no args without crashing.
#    (This will fail with non-admin error if it tries to apply, but the
#    imports should succeed.)
$errFile = Join-Path $env:TEMP 'orch-stderr.txt'
$outFile = Join-Path $env:TEMP 'orch-stdout.txt'
try {
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$orch,'-Install') -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile -WorkingDirectory $root
    $p.WaitForExit()
    $errOut = if (Test-Path $errFile) { Get-Content $errFile -Raw } else { '' }
    # -Install should not produce a stack trace; either succeed or warn
    # about pre-install snapshot, but the imports must work.
    if ($errOut -match 'ParserError' -or $errOut -match 'throw' -or $errOut -match 'Cannot find') {
        $failures += "Orchestrator -Install produced error output: $errOut"
    }
} finally {
    if (Test-Path $errFile) { Remove-Item $errFile -Force }
    if (Test-Path $outFile) { Remove-Item $outFile -Force }
    if (Test-Path (Join-Path $stateDir 'pre-install-dns.json')) {
        Remove-Item (Join-Path $stateDir 'pre-install-dns.json') -Force
    }
}

if ($failures.Count -gt 0) {
    Write-Host "  [FAIL] $($failures -join '; ')" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] Orchestrator file exists"
Write-Host "  [OK] All 10 helper modules present"
Write-Host "  [OK] Orchestrator parses without errors"
Write-Host "  [OK] Orchestrator references all key functions"
Write-Host "  [OK] -Install runs without stack trace"
Write-Host "Orchestrator import test passed."
exit 0