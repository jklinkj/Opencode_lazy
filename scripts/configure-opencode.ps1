[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProviderId,
    [Parameter(Mandatory)]
    [string]$ModelId,
    [string]$SmallModelId,
    [string[]]$EnabledProviders,
    [string]$ProviderBaseUrl,
    [string]$ProviderPackage,
    [string]$ProviderName,
    [string]$ServerHostname = '127.0.0.1',
    [ValidateSet('global', 'runtime', 'both')]
    [string]$ConfigScope = 'both',
    [switch]$SkipAcademyOverlay,
    [string]$ProfilePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8

function Write-OpenCodeConfig {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [object]$Config
    )

    Ensure-Directory -Path (Split-Path -Path $Path -Parent) | Out-Null
    $Config | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding utf8
}

function Sync-DirectoryContents {
    param(
        [Parameter(Mandatory)]
        [string]$Source,
        [Parameter(Mandatory)]
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        return $false
    }

    Ensure-Directory -Path $Destination | Out-Null
    foreach ($item in (Get-ChildItem -LiteralPath $Source -Force)) {
        Copy-Item -LiteralPath $item.FullName -Destination $Destination -Recurse -Force
    }

    return $true
}

$rootPath = Split-Path -Path $PSScriptRoot -Parent
. (Join-Path -Path $PSScriptRoot -ChildPath 'Load-CoreModules.ps1')
Import-CoreModules -ProjectRoot $rootPath -Names @('Common', 'Profile') | Out-Null
if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
    $ProfilePath = Join-Path -Path $rootPath -ChildPath 'profiles\lingnan-admin-v1.jsonc'
}

$resolvedProfilePath = Resolve-InstallerPath -Root $rootPath -Path $ProfilePath
$profile = Get-InstallerProfile -ProfilePath $resolvedProfilePath -Root $rootPath

if ([string]::IsNullOrWhiteSpace($SmallModelId)) {
    $SmallModelId = $ModelId
}

$customProviderRequested = @(@($ProviderBaseUrl, $ProviderPackage, $ProviderName) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0
if ($customProviderRequested -and [string]::IsNullOrWhiteSpace($ProviderBaseUrl)) {
    throw 'When using custom provider settings, -ProviderBaseUrl is required.'
}

$enabled = @()
if ($EnabledProviders) {
    $enabled = @($EnabledProviders | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}
if ($enabled.Count -eq 0) {
    $enabled = @($ProviderId)
}
elseif ($enabled -notcontains $ProviderId) {
    $enabled = @($enabled + $ProviderId)
}

$config = [ordered]@{
    '$schema' = 'https://opencode.ai/config.json'
    autoupdate = $false
    share = 'manual'
    permission = [ordered]@{
        edit = 'ask'
        bash = 'ask'
    }
    enabled_providers = @($enabled)
    model = ('{0}/{1}' -f $ProviderId, $ModelId)
    small_model = ('{0}/{1}' -f $ProviderId, $SmallModelId)
    server = [ordered]@{
        hostname = $ServerHostname
    }
}

if ($customProviderRequested) {
    if ([string]::IsNullOrWhiteSpace($ProviderPackage)) {
        $ProviderPackage = '@ai-sdk/openai-compatible'
    }
    if ([string]::IsNullOrWhiteSpace($ProviderName)) {
        $ProviderName = $ProviderId
    }

    $models = [ordered]@{}
    $models[$ModelId] = [ordered]@{ name = $ModelId }
    if ($SmallModelId -ne $ModelId) {
        $models[$SmallModelId] = [ordered]@{ name = $SmallModelId }
    }

    $provider = [ordered]@{}
    $provider[$ProviderId] = [ordered]@{
        npm = $ProviderPackage
        name = $ProviderName
        options = [ordered]@{
            baseURL = $ProviderBaseUrl
        }
        models = $models
    }

    $config['provider'] = $provider
}

$targets = New-Object System.Collections.Generic.List[string]
switch ($ConfigScope) {
    'global' {
        $targets.Add($profile.resolvedPaths.globalConfigFile)
    }
    'runtime' {
        $targets.Add($profile.resolvedPaths.runtimeConfigFile)
    }
    'both' {
        $targets.Add($profile.resolvedPaths.globalConfigFile)
        $targets.Add($profile.resolvedPaths.runtimeConfigFile)
    }
}

foreach ($target in $targets) {
    Write-OpenCodeConfig -Path $target -Config $config
}

$overlaySynced = $false
if ($ConfigScope -in @('global', 'both') -and -not $SkipAcademyOverlay) {
    $overlaySynced = Sync-DirectoryContents -Source $profile.resolvedPaths.academyConfigDir -Destination $profile.resolvedPaths.globalConfigRoot
}

Write-Host ('Config scope: {0}' -f $ConfigScope)
foreach ($target in $targets) {
    Write-Host ('Wrote config: {0}' -f $target)
}
Write-Host ('Default provider: {0}' -f $ProviderId)
Write-Host ('Default model: {0}' -f $ModelId)
Write-Host ('small_model: {0}' -f $SmallModelId)
if ($ConfigScope -in @('global', 'both')) {
    if ($overlaySynced) {
        Write-Host ('Synced academy overlay to: {0}' -f $profile.resolvedPaths.globalConfigRoot)
    }
    elseif (Test-Path -LiteralPath $profile.resolvedPaths.academyConfigDir -PathType Container) {
        Write-Host 'Skipped academy overlay sync.'
    }
}
Write-Host 'Run launcher/open-opencode-web.cmd to open the browser flow.'
Write-Host 'Desktop Beta will read the global config automatically.'