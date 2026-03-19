@echo off
setlocal
chcp 65001 >nul
set "ROOT=%~dp0.."
echo [Lingnan OpenCode] Starting browser entry...
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\open-opencode.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"
if not %EXIT_CODE%==0 (
  echo Launch failed with exit code: %EXIT_CODE%
  pause
)
exit /b %EXIT_CODE%
