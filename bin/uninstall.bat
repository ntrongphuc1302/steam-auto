@echo off
REM uninstall.bat - reverse of install.bat. Restores DNS, removes the
REM scheduled task, optionally wipes runtime state.

setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

echo.
echo  ============================================================
echo    SteamAuto  ::  uninstaller
echo  ============================================================
echo    Restoring DNS and removing the daemon ...
echo.

REM 1. Restore DNS to whatever it was before install.
echo [..]  Restoring pre-install DNS ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0steam-auto.ps1" -Uninstall
if errorlevel 1 (
    echo [WARN] DNS restore reported a problem, please verify manually
)

REM 2. Belt-and-suspenders: force the task gone even if PowerShell failed.
echo [..]  Removing scheduled task ...
schtasks /delete /tn "SteamAuto" /f >nul 2>&1
echo [OK]   daemon removed

REM 3. Optional state/log cleanup. We only auto-delete logs older than
REM    7 days; state is small so we leave it in place for inspection.
echo [..]  Pruning logs older than 7 days ...
forfiles /p "%~dp0..\logs" /m *.log /d -7 /c "cmd /c del @path" 2>nul
echo [OK]   done

echo.
echo  ============================================================
echo    SteamAuto daemon gone.  DNS should match pre-install.
echo    Reboot to flush any leaked PowerShell instance.
echo  ============================================================
echo.
pause