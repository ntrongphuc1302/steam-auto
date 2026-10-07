@echo off
REM uninstall.bat - reverse of install.bat. Calls bin\uninstall.bat
REM after self-elevating.

setlocal EnableExtensions
cd /d "%~dp0"

echo ===== SteamAuto uninstaller =====

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

call bin\uninstall.bat
exit /b %errorlevel%