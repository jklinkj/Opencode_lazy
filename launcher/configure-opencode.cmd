@echo off
setlocal
chcp 65001 >nul
set "ROOT=%~dp0.."
if "%~1"=="" (
  echo [Lingnan OpenCode] Missing configuration arguments.
  echo.
  echo Usage examples:
  echo   launcher\configure-opencode.cmd -ProviderId openai -ModelId gpt-4.1
  echo   launcher\configure-opencode.cmd -ProviderId openai -ModelId gpt-4.1 -ConfigScope global
  echo   launcher\configure-opencode.cmd -ProviderId lingnan-gateway -ProviderBaseUrl https://gateway.example/v1 -ModelId lingnan-default
  echo.
  exit /b 1
)
echo [Lingnan OpenCode] Writing shared OpenCode configuration...
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\configure-opencode.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"
if not %EXIT_CODE%==0 (
  echo Configuration failed with exit code: %EXIT_CODE%
  pause
)
exit /b %EXIT_CODE%