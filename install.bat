@echo off
REM install.bat - one-shot installer for SteamAuto.
REM Double-click this file after cloning the repo. It will:
REM   1. Self-elevate to Administrator.
REM   2. Call bin\install.bat to install the scheduled task + record
REM      pre-install DNS snapshot, then run a single tick so the user
REM      immediately sees results.
REM
REM Exit codes:
REM   0  install OK
REM   2  requirement check failed (PowerShell / PS version)

setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

echo.
echo  ============================================================
echo    SteamAuto  ::  v1.0  ::  silent Steam unblocker daemon
echo  ============================================================
echo    Forging DNS routes. Overwriting any existing install.
echo.

REM ----- 1. Self-elevate to Administrator. -----
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [..]  Requesting Administrator privileges ...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

REM ----- 2. Requirements check. -----
echo [..]  Checking environment ...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$PSVer = $PSVersionTable.PSVersion.Major; if ($PSVer -lt 5) { Write-Host ('[ERROR] PowerShell 5+ required, found ' + $PSVer); exit 2 } Write-Host ('[OK]   PowerShell ' + $PSVer)"
if errorlevel 1 (
    echo [ERROR] PowerShell 5 or later is required.
    pause
    exit /b 2
)
echo.

REM ----- 3. Install (snapshot DNS, register scheduled task, run once). -----
echo [..]  Installing daemon ...
call bin\install.bat
if errorlevel 1 (
    echo [ERROR] bin\install.bat reported a failure.
    pause
    exit /b 1
)

echo.
echo  ============================================================
echo    SteamAuto daemon online.  Background mode: ON.
echo    Survives reboot.  Watchdog keeps DNS optimal 24/7.
echo  ============================================================
echo.
echo    To uninstall, run run uninstall.bat
echo.
endlocal
exit /b 0