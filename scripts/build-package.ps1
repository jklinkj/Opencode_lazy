[CmdletBinding()]
param(
    [string]$OutputRoot,
    [string]$PackageName = 'Lingnan-OpenCode-Online-V1',
    [switch]$CreateZip
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

function Ensure-DirectoryPath {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

$projectRoot = Split-Path -Path $PSScriptRoot -Parent
$workspaceRoot = Split-Path -Path $projectRoot -Parent
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path -Path $projectRoot -ChildPath 'dist'
}

Ensure-DirectoryPath -Path $OutputRoot

$packageRoot = Join-Path -Path $OutputRoot -ChildPath $PackageName
$zipPath = Join-Path -Path $OutputRoot -ChildPath ('{0}.zip' -f $PackageName)

if (Test-Path -LiteralPath $packageRoot) {
    Remove-Item -LiteralPath $packageRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null

$items = @('README.md', 'docs', 'launcher', 'scripts', 'profiles', 'assets', 'manifests')
foreach ($item in $items) {
    Copy-Item -Path (Join-Path -Path $projectRoot -ChildPath $item) -Destination $packageRoot -Recurse -Force
}
Copy-Item -Path (Join-Path -Path $workspaceRoot -ChildPath 'core') -Destination (Join-Path -Path $packageRoot -ChildPath 'core') -Recurse -Force

Write-Host ('Package directory created: {0}' -f $packageRoot)

if ($CreateZip) {
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }

    Compress-Archive -Path $packageRoot -DestinationPath $zipPath -CompressionLevel Optimal
    Write-Host ('Package zip created: {0}' -f $zipPath)
}