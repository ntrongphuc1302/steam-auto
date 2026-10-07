@echo off
REM run-all.bat - run every test-*.ps1 in this folder.
REM Self-elevates to Administrator so the E2E test (test-08-e2e-rollback.ps1)
REM can actually touch DNS. Writes full output to tests\test-results.log
REM so you can review it after the run finishes.

setlocal
cd /d "%~dp0"

REM ----- Self-elevate -----
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

echo Running as Administrator.
echo.

REM ----- Run the suite with full logging -----
set "LOG=%~dp0test-results.log"
set "EXITFILE=%~dp0test-exit.txt"

echo === steam-auto test run started %date% %time% > "%LOG%"
echo === Log file: %LOG% >> "%LOG%"
echo. >> "%LOG%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-all.ps1" >> "%LOG%" 2>&1
set "RC=%errorlevel%"

echo. >> "%LOG%"
echo === test run finished %date% %time% >> "%LOG%"
echo === exit code: %RC% >> "%LOG%"

REM Persist the exit code in its own file so scripts can grep it.
echo %RC%> "%EXITFILE%"

echo.
echo ============================================
if %RC% equ 0 (
    echo  All tests passed. Exit code: %RC%
) else (
    echo  Tests failed.     Exit code: %RC%
)
echo ============================================
echo.
echo Full log:  %LOG%
echo Exit code: %EXITFILE%

REM Auto-open the log so you can review it immediately.
start "" "%LOG%"

exit /b %RC%