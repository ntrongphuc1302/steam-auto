@echo off
REM uninstall.bat - reverse of install.bat. Restores DNS, removes the
REM scheduled task, optionally wipes runtime state.

setlocal
cd /d "%~dp0"

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

echo === SteamAuto uninstaller ===

REM 1. Restore DNS to whatever it was before install.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0steam-auto.ps1" -Uninstall
if errorlevel 1 (
    echo [WARN] DNS restore reported a problem, please verify manually
)

REM 2. Belt-and-suspenders: force the task gone even if PowerShell failed.
schtasks /delete /tn "SteamAuto" /f >nul 2>&1
echo [OK] Scheduled task removed

REM 3. Optional state/log cleanup. We only auto-delete logs older than
REM    7 days; state is small so we leave it in place for inspection.
forfiles /p "%~dp0..\logs" /m *.log /d -7 /c "cmd /c del @path" 2>nul
echo [OK] Cleaned old logs (kept last 7 days)

echo.
echo SteamAuto has been removed. Your DNS should now match what it
echo was before installing. Reboot to make sure no background instance
echo is still running.
pause