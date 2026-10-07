@echo off
REM dev-install.bat - dev workflow: tests + install. Regular users run
REM install.bat at the repo root, which skips tests entirely. Run this
REM from anywhere with tests\dev-install.bat or the dev alias below.

setlocal
cd /d "%~dp0"

echo  ============================================================
echo    SteamAuto  ::  DEV install (tests + daemon)
echo  ============================================================
echo.

REM Requirements check.
echo [..]  Checking environment ...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$PSVer = $PSVersionTable.PSVersion.Major; if ($PSVer -lt 5) { Write-Host ('[ERROR] PowerShell 5+ required, found ' + $PSVer); exit 2 } Write-Host ('[OK]   PowerShell ' + $PSVer)"
if errorlevel 1 (
    echo [ERROR] PowerShell 5 or later is required.
    pause
    exit /b 2
)
echo.

REM Full test suite.
echo [..]  Running full test suite ...
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-all.ps1
if errorlevel 1 (
    echo.
    echo [ERROR] Tests failed - install aborted.
    echo         See tests\test-results.log.
    pause
    exit /b 1
)
echo [OK]   All tests passed.
echo.

REM Hand off to the root installer.
echo [..]  Handing off to install.bat ...
call ..\install.bat
endlocal