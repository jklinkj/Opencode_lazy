[CmdletBinding()]
param(
    [string]$InstallerPath,
    [string]$ProfilePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8

$rootPath = Split-Path -Path $PSScriptRoot -Parent
. (Join-Path -Path $PSScriptRoot -ChildPath 'Load-CoreModules.ps1')
Import-CoreModules -ProjectRoot $rootPath -Names @('Common', 'Profile', 'Downloads') | Out-Null
if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
    $ProfilePath = Join-Path -Path $rootPath -ChildPath 'profiles\lingnan-admin-v1.jsonc'
}

$resolvedProfilePath = Resolve-InstallerPath -Root $rootPath -Path $ProfilePath
$profile = Get-InstallerProfile -ProfilePath $resolvedProfilePath -Root $rootPath

if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
    $InstallerPath = $profile.resolvedPaths.desktopInstallerFile
}
else {
    $InstallerPath = Resolve-InstallerPath -Root $rootPath -Path $InstallerPath
}

if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) {
    $artifactId = if (($profile.PSObject.Properties.Name -contains 'desktop') -and ($profile.desktop.PSObject.Properties.Name -contains 'artifactId') -and $profile.desktop.artifactId) { $profile.desktop.artifactId } else { $null }
    if ($artifactId) {
        Write-Host ('Local Desktop installer not found. Trying online acquisition: {0}' -f $artifactId)
        $download = Get-ArtifactDownloadPath -Profile $profile -ArtifactId $artifactId
        if ($download.success) {
            $InstallerPath = $download.localPath
        }
        else {
            Write-Host $download.summary
            foreach ($attempt in @($download.attempts)) {
                Write-Host ('- {0}: {1}' -f $attempt.sourceId, $attempt.error)
            }
            exit 20
        }
    }
}

if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) {
    Write-Host ('Desktop installer not found: {0}' -f $InstallerPath)
    if (($profile.PSObject.Properties.Name -contains 'desktop') -and ($profile.desktop.PSObject.Properties.Name -contains 'downloadPage') -and $profile.desktop.downloadPage) {
        Write-Host ('Download page: {0}' -f $profile.desktop.downloadPage)
    }
    exit 20
}

Write-Host ('Launching Desktop installer: {0}' -f $InstallerPath)
Write-Host 'Configure provider/model first if you want preconfigured settings.'

$process = Start-Process -FilePath $InstallerPath -WorkingDirectory (Split-Path -Path $InstallerPath -Parent) -PassThru -Wait
$exitCode = if ($process) { $process.ExitCode } else { 0 }
if ($exitCode -ne 0) {
    Write-Host ('Desktop installer returned a non-zero exit code: {0}' -f $exitCode)
    exit $exitCode
}

if (Test-Path -LiteralPath $profile.resolvedPaths.globalConfigFile) {
    Write-Host ('Detected global OpenCode config: {0}' -f $profile.resolvedPaths.globalConfigFile)
}
else {
    Write-Host 'Global OpenCode config not found; run launcher/configure-opencode.cmd if needed.'
}

Write-Host 'Desktop installation finished. Start OpenCode Desktop from the Start menu.'
exit 0