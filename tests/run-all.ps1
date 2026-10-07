# tests/run-all.ps1
# Runs every test-*.ps1 in this directory. Stops at the first failure.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$tests = Get-ChildItem -Path $here -Filter 'test-*.ps1' | Sort-Object Name

$pass = 0
$fail = 0

foreach ($t in $tests) {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  $($t.Name)" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    & powershell -NoProfile -ExecutionPolicy Bypass -File $t.FullName
    if ($LASTEXITCODE -eq 0) {
        $pass++
    } else {
        $fail++
        Write-Host "STOPPING - first failure" -ForegroundColor Red
        break
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Result: $pass passed, $fail failed" -ForegroundColor $(if ($fail -eq 0) {'Green'} else {'Red'})
Write-Host "============================================" -ForegroundColor Cyan

exit $fail