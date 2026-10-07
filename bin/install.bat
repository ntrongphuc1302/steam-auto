@echo off
REM install.bat - register SteamAuto as a Windows Task that runs at
REM every boot, plus a one-shot run so the user sees results immediately.

setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

REM Self-elevate to Administrator.
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

echo.
echo  ============================================================
echo    SteamAuto  ::  v1.0  ::  silent Steam unblocker daemon
echo  ============================================================
echo    Snapshot pre-install state... overwriting any existing task.
echo.

REM 1. Snapshot the DNS state so uninstall can restore it.
echo [..]  Snapshotting pre-install DNS ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0steam-auto.ps1" -Install
if errorlevel 1 (
    echo [WARN] Failed to record pre-install DNS snapshot
)

REM 2. Register the watchdog task in Task Scheduler. /f = idempotent:
REM    if a previous install left a task behind it gets overwritten.
echo [..]  Registering scheduled task (overwriting if needed) ...
set "PS_PATH=%~dp0steam-auto.ps1"
schtasks /create ^
    /tn "SteamAuto" ^
    /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%PS_PATH%\" -Watchdog" ^
    /sc onstart ^
    /ru SYSTEM ^
    /rl HIGHEST ^
    /f

if errorlevel 1 (
    echo [ERROR] Failed to install SteamAuto daemon
    exit /b 1
)
echo [OK]   daemon installed: SYSTEM -Watchdog on OnStart

REM 3. Run once now so the user immediately sees if Steam is reachable.
echo.
echo [..]  First probe - probing upstream DNS ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_PATH%"
echo.
echo  ============================================================
echo    SteamAuto daemon online.  Background mode: ON.
echo    Survives reboot.  Watchdog keeps DNS optimal 24/7.
echo  ============================================================
echo.
echo    To uninstall, run bin\uninstall.bat
echo.
pause