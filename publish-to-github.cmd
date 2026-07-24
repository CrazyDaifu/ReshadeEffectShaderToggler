@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\publish-github.ps1"
set "exit_code=%errorlevel%"
echo.
if not "%exit_code%"=="0" echo Upload failed with exit code %exit_code%.
if "%exit_code%"=="0" echo Upload completed successfully.
pause
exit /b %exit_code%
