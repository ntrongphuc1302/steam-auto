@echo off
REM run-all-non-admin.bat - skip the E2E DNS-mutating test, run the rest.

setlocal
cd /d "%~dp0"

set "LOG=%~dp0test-results.log"
set "EXITFILE=%~dp0test-exit.txt"

echo === steam-auto (non-admin) test run started %date% %time% > "%LOG%"
echo === Skipping E2E test (requires Administrator). >> "%LOG%"
echo. >> "%LOG%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-all-non-admin.ps1" >> "%LOG%" 2>&1
set "RC=%errorlevel%"

echo. >> "%LOG%"
echo === test run finished %date% %time% >> "%LOG%"
echo === exit code: %RC% >> "%LOG%"
echo %RC%> "%EXITFILE%"

echo.
if %RC% equ 0 (echo All non-admin tests passed.) else (echo Some tests failed.)
echo Log: %LOG%
start "" "%LOG%"

exit /b %RC%