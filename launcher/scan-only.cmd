@echo off
setlocal
chcp 65001 >nul
set "ROOT=%~dp0.."
echo [Lingnan OpenCode] Running scan-only check...
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\install.ps1" -Mode scan-only %*
set "EXIT_CODE=%ERRORLEVEL%"
echo.
echo Scan finished. Exit code: %EXIT_CODE%
pause
exit /b %EXIT_CODE%
