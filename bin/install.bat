@echo off
REM install.bat - register SteamAuto as a Windows Task that runs at
REM every boot, plus a one-shot run so the user sees results immediately.

setlocal
cd /d "%~dp0"

REM Self-elevate to Administrator.
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

echo === SteamAuto installer ===

REM 1. Snapshot the DNS state so uninstall can restore it.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0steam-auto.ps1" -Install
if errorlevel 1 (
    echo [WARN] Failed to record pre-install DNS snapshot
)

REM 2. Register the watchdog task in Task Scheduler.
set "PS_PATH=%~dp0steam-auto.ps1"
schtasks /create ^
    /tn "SteamAuto" ^
    /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%PS_PATH%\" -Watchdog" ^
    /sc onstart ^
    /ru SYSTEM ^
    /rl HIGHEST ^
    /f

if errorlevel 1 (
    echo [ERROR] Failed to register scheduled task
    exit /b 1
)
echo [OK] Registered scheduled task: SteamAuto

REM 3. Run once now so the user immediately sees if Steam is reachable.
echo === First run ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_PATH%"
echo === Done ===
echo.
echo SteamAuto is installed. Your machine will auto-unblock Steam at
echo every boot, and keep a background watchdog on it 24/7.
echo.
echo To uninstall, run bin\uninstall.bat
pause