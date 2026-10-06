@echo off
REM steam-auto.bat - manual launcher. Runs the orchestrator once.
REM Useful for testing or running without installing the service.

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0steam-auto.ps1" %*
pause