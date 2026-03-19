[CmdletBinding()]
param(
    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8

function Resolve-ProjectDirectory {
    param(
        [string]$InputPath
    )

    if ([string]::IsNullOrWhiteSpace($InputPath)) {
        return $null
    }

    $candidate = if ([IO.Path]::IsPathRooted($InputPath)) {
        $InputPath
    }
    else {
        Join-Path -Path (Get-Location) -ChildPath $InputPath
    }

    $resolved = [IO.Path]::GetFullPath($candidate)
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        throw ('The selected project directory does not exist: {0}' -f $resolved)
    }

    return $resolved
}

function Select-ProjectDirectory {
    param(
        [string]$InitialPath
    )

    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Select a project folder to open in OpenCode Web'
    $dialog.ShowNewFolderButton = $false
    if (-not [string]::IsNullOrWhiteSpace($InitialPath) -and (Test-Path -LiteralPath $InitialPath -PathType Container)) {
        $dialog.SelectedPath = $InitialPath
    }

    $result = $dialog.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK -and -not [string]::IsNullOrWhiteSpace($dialog.SelectedPath)) {
        return $dialog.SelectedPath
    }

    return $null
}

$rootPath = Split-Path -Path $PSScriptRoot -Parent
$profilePath = Join-Path -Path $rootPath -ChildPath 'profiles\lingnan-admin-v1.jsonc'
. (Join-Path -Path $PSScriptRoot -ChildPath 'Load-CoreModules.ps1')
Import-CoreModules -ProjectRoot $rootPath -Names @('Common', 'Profile', 'Checks') | Out-Null

$profile = Get-InstallerProfile -ProfilePath $profilePath -Root $rootPath
Sync-ProcessPathFromSystem
Add-ProcessPathEntries -Entries (Get-RuntimePathEntries -Profile $profile)

$state = Get-DependencyState -DependencyId 'opencode' -Definition $profile.dependencies.PSObject.Properties['opencode'].Value -Profile $profile
if (-not $state.installed) {
    Write-Host 'OpenCode was not detected. Run launcher/start.cmd first.'
    exit 20
}

if (Test-Path -LiteralPath $profile.resolvedPaths.globalConfigFile) {
    Remove-Item Env:OPENCODE_CONFIG -ErrorAction SilentlyContinue
    Remove-Item Env:OPENCODE_CONFIG_DIR -ErrorAction SilentlyContinue
    Write-Host ('Using global config: {0}' -f $profile.resolvedPaths.globalConfigFile)
}
elseif (Test-Path -LiteralPath $profile.resolvedPaths.runtimeConfigFile) {
    $env:OPENCODE_CONFIG = $profile.resolvedPaths.runtimeConfigFile
    Remove-Item Env:OPENCODE_CONFIG_DIR -ErrorAction SilentlyContinue
    Write-Host ('Using runtime config fallback: {0}' -f $profile.resolvedPaths.runtimeConfigFile)
}
else {
    Remove-Item Env:OPENCODE_CONFIG -ErrorAction SilentlyContinue
    Remove-Item Env:OPENCODE_CONFIG_DIR -ErrorAction SilentlyContinue
    Write-Host 'No config file detected. OpenCode defaults will be used.'
}

try {
    $resolvedProjectPath = Resolve-ProjectDirectory -InputPath $ProjectPath
}
catch {
    Write-Host $_.Exception.Message
    exit 20
}

if (-not $resolvedProjectPath) {
    $defaultBrowseRoot = if (Test-Path -LiteralPath (Join-Path -Path $HOME -ChildPath 'Desktop') -PathType Container) {
        Join-Path -Path $HOME -ChildPath 'Desktop'
    }
    elseif (Test-Path -LiteralPath $HOME -PathType Container) {
        $HOME
    }
    else {
        (Get-Location).Path
    }

    try {
        $resolvedProjectPath = Select-ProjectDirectory -InitialPath $defaultBrowseRoot
    }
    catch {
        Write-Host 'Failed to open the folder picker. Pass the project path on the command line instead.'
        exit 20
    }

    if (-not $resolvedProjectPath) {
        Write-Host 'Folder selection was cancelled. OpenCode Web was not started.'
        exit 0
    }
}

Write-Host ('Project directory: {0}' -f $resolvedProjectPath)
Write-Host '[Lingnan OpenCode] Starting OpenCode Web...'

Push-Location -LiteralPath $resolvedProjectPath
try {
    & $state.commandPath 'web'
    if ($LASTEXITCODE) {
        exit $LASTEXITCODE
    }
}
finally {
    Pop-Location
}

exit 0