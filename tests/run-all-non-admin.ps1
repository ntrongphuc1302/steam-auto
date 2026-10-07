# tests/run-all-non-admin.ps1
# Like run-all.ps1 but skips tests that require Administrator
# (currently only test-08-e2e-rollback.ps1).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$skip = @('test-08-e2e-rollback.ps1')
$tests = Get-ChildItem -Path $here -Filter 'test-*.ps1' |
    Where-Object { $skip -notcontains $_.Name } |
    Sort-Object Name

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
Write-Host "  Result: $pass passed, $fail failed (E2E skipped)" -ForegroundColor $(if ($fail -eq 0) {'Green'} else {'Red'})
Write-Host "============================================" -ForegroundColor Cyan

exit $fail