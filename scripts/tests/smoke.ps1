[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

$rootPath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$installScript = Join-Path -Path $rootPath -ChildPath 'scripts\install.ps1'
$powershellExe = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'

Write-Host '运行 scan-only 烟测...'
& $powershellExe -NoProfile -ExecutionPolicy Bypass -File $installScript -Mode scan-only
$exitCode = $LASTEXITCODE

if ($exitCode -notin @(0, 10, 20, 30)) {
    throw ('scan-only 返回了异常退出码: {0}' -f $exitCode)
}

$reportsRoot = Join-Path -Path $rootPath -ChildPath 'reports'
$latestReport = Get-ChildItem -Path $reportsRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $latestReport) {
    throw '未找到 reports 输出目录。'
}

$summaryPath = Join-Path -Path $latestReport.FullName -ChildPath 'summary.txt'
$resultPath = Join-Path -Path $latestReport.FullName -ChildPath 'result.json'
$logPath = Join-Path -Path $latestReport.FullName -ChildPath 'events.log'

foreach ($path in @($summaryPath, $resultPath, $logPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw ('烟测失败，缺少文件: {0}' -f $path)
    }
}

$result = Get-Content -Path $resultPath -Raw -Encoding utf8 | ConvertFrom-Json
if (-not $result.policyVersion) {
    throw 'result.json 缺少 policyVersion。'
}

Write-Host ('烟测通过，最新报告目录: {0}' -f $latestReport.FullName)
