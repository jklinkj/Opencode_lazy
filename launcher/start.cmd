@echo off
setlocal
chcp 65001 >nul
set "ROOT=%~dp0.."
echo [Lingnan OpenCode] Starting smart install...
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\install.ps1" -Mode smart %*
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if %EXIT_CODE%==0 (
  echo Install and deployment completed.
) else (
  echo Process finished with exit code: %EXIT_CODE%
)
pause
exit /b %EXIT_CODE%
