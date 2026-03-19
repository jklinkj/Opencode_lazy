Set-StrictMode -Version 3.0

function Get-InstallerProfile {
    param(
        [Parameter(Mandatory)]
        [string]$ProfilePath,
        [Parameter(Mandatory)]
        [string]$Root
    )

    $profile = ConvertFrom-JsonCFile -Path $ProfilePath
    $profile | Add-Member -NotePropertyName rootPath -NotePropertyValue $Root -Force
    $profile | Add-Member -NotePropertyName profilePath -NotePropertyValue $ProfilePath -Force

    $runtimeConfigRoot = if (($profile.runtime.PSObject.Properties.Name -contains 'runtimeConfigRoot') -and $profile.runtime.runtimeConfigRoot) {
        $profile.runtime.runtimeConfigRoot
    }
    else {
        'runtime/config'
    }

    $runtimeConfigFile = if (($profile.runtime.PSObject.Properties.Name -contains 'runtimeConfigFile') -and $profile.runtime.runtimeConfigFile) {
        $profile.runtime.runtimeConfigFile
    }
    else {
        'runtime/config/opencode.jsonc'
    }

    $globalConfigRoot = if (($profile.runtime.PSObject.Properties.Name -contains 'globalConfigRoot') -and $profile.runtime.globalConfigRoot) {
        $profile.runtime.globalConfigRoot
    }
    else {
        '~/.config/opencode'
    }

    $globalConfigFile = if (($profile.runtime.PSObject.Properties.Name -contains 'globalConfigFile') -and $profile.runtime.globalConfigFile) {
        $profile.runtime.globalConfigFile
    }
    else {
        '~/.config/opencode/opencode.json'
    }

    $downloadCacheRoot = $null
    $downloadManifestFile = $null
    $downloadStrategy = 'official-first'
    if (($profile.PSObject.Properties.Name -contains 'downloads') -and $profile.downloads) {
        if (($profile.downloads.PSObject.Properties.Name -contains 'cacheRoot') -and $profile.downloads.cacheRoot) {
            $downloadCacheRoot = $profile.downloads.cacheRoot
        }

        if (($profile.downloads.PSObject.Properties.Name -contains 'manifestFile') -and $profile.downloads.manifestFile) {
            $downloadManifestFile = $profile.downloads.manifestFile
        }

        if (($profile.downloads.PSObject.Properties.Name -contains 'strategy') -and $profile.downloads.strategy) {
            $downloadStrategy = $profile.downloads.strategy
        }
    }

    $desktopInstallerFile = if (($profile.PSObject.Properties.Name -contains 'desktop') -and ($profile.desktop.PSObject.Properties.Name -contains 'offlineInstaller') -and $profile.desktop.offlineInstaller) {
        $profile.desktop.offlineInstaller
    }
    else {
        'assets/payload/opencode-desktop-windows-x64.exe'
    }

    $resolved = [ordered]@{
        reportRoot          = Resolve-InstallerPath -Root $Root -Path $profile.runtime.reportRoot
        runtimeRoot         = Resolve-InstallerPath -Root $Root -Path $profile.runtime.runtimeRoot
        nodeRoot            = Resolve-InstallerPath -Root $Root -Path $profile.runtime.nodeRoot
        npmGlobalRoot       = Resolve-InstallerPath -Root $Root -Path $profile.runtime.npmGlobalRoot
        gitRoot             = Resolve-InstallerPath -Root $Root -Path $profile.runtime.gitRoot
        runtimeConfigRoot   = Resolve-InstallerPath -Root $Root -Path $runtimeConfigRoot
        runtimeConfigFile   = Resolve-InstallerPath -Root $Root -Path $runtimeConfigFile
        globalConfigRoot    = Resolve-InstallerPath -Root $Root -Path $globalConfigRoot
        globalConfigFile    = Resolve-InstallerPath -Root $Root -Path $globalConfigFile
        downloadCacheRoot   = if ($downloadCacheRoot) { Resolve-InstallerPath -Root $Root -Path $downloadCacheRoot } else { $null }
        downloadManifestFile = if ($downloadManifestFile) { Resolve-InstallerPath -Root $Root -Path $downloadManifestFile } else { $null }
        desktopInstallerFile = Resolve-InstallerPath -Root $Root -Path $desktopInstallerFile
        academyConfigFile   = Resolve-InstallerPath -Root $Root -Path $profile.deployment.academyConfigFile
        academyConfigDir    = Resolve-InstallerPath -Root $Root -Path $profile.deployment.academyConfigDir
    }

    $profile | Add-Member -NotePropertyName resolvedPaths -NotePropertyValue ([pscustomobject]$resolved) -Force
    $profile | Add-Member -NotePropertyName downloadStrategy -NotePropertyValue $downloadStrategy -Force
    return $profile
}

function Get-InstallerTokens {
    param(
        [Parameter(Mandatory)]
        [object]$Profile
    )

    return @{
        package_root          = $Profile.rootPath
        runtime_root          = $Profile.resolvedPaths.runtimeRoot
        node_root             = $Profile.resolvedPaths.nodeRoot
        npm_global_root       = $Profile.resolvedPaths.npmGlobalRoot
        git_root              = $Profile.resolvedPaths.gitRoot
        runtime_config_root   = $Profile.resolvedPaths.runtimeConfigRoot
        runtime_config_file   = $Profile.resolvedPaths.runtimeConfigFile
        global_config_root    = $Profile.resolvedPaths.globalConfigRoot
        global_config_file    = $Profile.resolvedPaths.globalConfigFile
        download_cache_root   = $Profile.resolvedPaths.downloadCacheRoot
        download_manifest_file = $Profile.resolvedPaths.downloadManifestFile
        desktop_installer_file = $Profile.resolvedPaths.desktopInstallerFile
        academy_config_file   = $Profile.resolvedPaths.academyConfigFile
        academy_config_dir    = $Profile.resolvedPaths.academyConfigDir
        reports_root          = $Profile.resolvedPaths.reportRoot
    }
}

function Get-RuntimePathEntries {
    param(
        [Parameter(Mandatory)]
        [object]$Profile
    )

    return @(
        $Profile.resolvedPaths.nodeRoot
        $Profile.resolvedPaths.npmGlobalRoot
        (Join-Path -Path $Profile.resolvedPaths.gitRoot -ChildPath 'cmd')
        (Join-Path -Path $Profile.resolvedPaths.gitRoot -ChildPath 'bin')
    )
}

Export-ModuleMember -Function *
