Set-StrictMode -Version 3.0

function Invoke-Deployment {
    param(
        [Parameter(Mandatory)]
        [object]$Profile,
        [Parameter(Mandatory)]
        [object]$Facts
    )

    Ensure-Directory -Path $Profile.resolvedPaths.runtimeRoot | Out-Null
    Ensure-Directory -Path $Profile.resolvedPaths.nodeRoot | Out-Null
    Ensure-Directory -Path $Profile.resolvedPaths.npmGlobalRoot | Out-Null
    Ensure-Directory -Path $Profile.resolvedPaths.gitRoot | Out-Null
    Ensure-Directory -Path $Profile.resolvedPaths.runtimeConfigRoot | Out-Null
    Ensure-Directory -Path $Profile.resolvedPaths.globalConfigRoot | Out-Null
    if ($Profile.resolvedPaths.downloadCacheRoot) {
        Ensure-Directory -Path $Profile.resolvedPaths.downloadCacheRoot | Out-Null
    }

    $deploymentStatePath = Join-Path -Path $Profile.resolvedPaths.runtimeRoot -ChildPath 'deployment-state.json'
    $state = [ordered]@{
        policyVersion       = $Profile.policyVersion
        generatedAt         = (Get-Date).ToString('o')
        runtimeConfigRoot   = $Profile.resolvedPaths.runtimeConfigRoot
        runtimeConfigFile   = $Profile.resolvedPaths.runtimeConfigFile
        globalConfigRoot    = $Profile.resolvedPaths.globalConfigRoot
        globalConfigFile    = $Profile.resolvedPaths.globalConfigFile
        downloadCacheRoot   = $Profile.resolvedPaths.downloadCacheRoot
        downloadManifestFile = $Profile.resolvedPaths.downloadManifestFile
        desktopInstallerFile = $Profile.resolvedPaths.desktopInstallerFile
        academyConfigFile   = $Profile.resolvedPaths.academyConfigFile
        academyConfigDir    = $Profile.resolvedPaths.academyConfigDir
        packageRoot         = $Profile.rootPath
        machine             = $Facts.machine
    }
    $state | ConvertTo-Json -Depth 8 | Set-Content -Path $deploymentStatePath -Encoding utf8

    $checks = New-Object System.Collections.Generic.List[object]
    $checks.Add((New-InstallerCheck -Id 'deploy.state' -Title '部署状态文件已生成' -Category 'deployment' -Status 'pass' -Class 'A' -Evidence @{ path = $deploymentStatePath }))
    $checks.Add((New-InstallerCheck -Id 'deploy.runtime-config-root' -Title '运行时配置目录已准备' -Category 'deployment' -Status 'pass' -Class 'A' -Evidence @{ path = $Profile.resolvedPaths.runtimeConfigRoot }))
    $checks.Add((New-InstallerCheck -Id 'deploy.global-config-root' -Title '全局配置目录已准备' -Category 'deployment' -Status 'pass' -Class 'A' -Evidence @{ path = $Profile.resolvedPaths.globalConfigRoot }))
    if ($Profile.resolvedPaths.downloadCacheRoot) {
        $checks.Add((New-InstallerCheck -Id 'deploy.download-cache-root' -Title '下载缓存目录已准备' -Category 'deployment' -Status 'pass' -Class 'A' -Evidence @{ path = $Profile.resolvedPaths.downloadCacheRoot }))
    }
    if ($Profile.resolvedPaths.downloadManifestFile) {
        $manifestExists = Test-Path -LiteralPath $Profile.resolvedPaths.downloadManifestFile
        $checks.Add((New-InstallerCheck -Id 'deploy.download-manifest' -Title '下载清单存在' -Category 'deployment' -Status $(if ($manifestExists) { 'pass' } else { 'fail' }) -Class $(if ($manifestExists) { 'A' } else { 'C' }) -Evidence @{ path = $Profile.resolvedPaths.downloadManifestFile } -RecommendedAction '在线项目缺少下载清单，请重新构建发布包。'))
    }

    $configTemplateExists = Test-Path -LiteralPath $Profile.resolvedPaths.academyConfigFile
    $checks.Add((New-InstallerCheck -Id 'deploy.config-template' -Title '包内配置模板存在' -Category 'deployment' -Status $(if ($configTemplateExists) { 'pass' } else { 'warn' }) -Class 'A' -Evidence @{ path = $Profile.resolvedPaths.academyConfigFile } -RecommendedAction '如需预置 provider/model，可补齐或更新包内配置模板。'))

    $configDirExists = Test-Path -LiteralPath $Profile.resolvedPaths.academyConfigDir
    $checks.Add((New-InstallerCheck -Id 'deploy.config-dir' -Title '学院扩展目录存在' -Category 'deployment' -Status $(if ($configDirExists) { 'pass' } else { 'warn' }) -Class 'A' -Evidence @{ path = $Profile.resolvedPaths.academyConfigDir } -RecommendedAction '如需统一下发 instructions 或 commands，可补齐学院扩展目录。'))

    $desktopInstallerExists = Test-Path -LiteralPath $Profile.resolvedPaths.desktopInstallerFile
    $desktopArtifactId = if (($Profile.PSObject.Properties.Name -contains 'desktop') -and ($Profile.desktop.PSObject.Properties.Name -contains 'artifactId') -and $Profile.desktop.artifactId) { $Profile.desktop.artifactId } else { $null }
    if ($desktopInstallerExists) {
        $checks.Add((New-InstallerCheck -Id 'deploy.desktop-installer' -Title 'Desktop Beta 安装器已就绪' -Category 'deployment' -Status 'pass' -Class 'A' -Evidence @{ path = $Profile.resolvedPaths.desktopInstallerFile }))
    }
    elseif ($desktopArtifactId) {
        $checks.Add((New-InstallerCheck -Id 'deploy.desktop-installer' -Title 'Desktop Beta 安装器支持按需下载' -Category 'deployment' -Status 'pass' -Class 'A' -Evidence @{ artifactId = $desktopArtifactId; cachePath = $Profile.resolvedPaths.desktopInstallerFile }))
    }
    else {
        $checks.Add((New-InstallerCheck -Id 'deploy.desktop-installer' -Title 'Desktop Beta 安装器检查' -Category 'deployment' -Status 'warn' -Class 'A' -Evidence @{ path = $Profile.resolvedPaths.desktopInstallerFile } -RecommendedAction '如需额外安装官方 Desktop Beta，请补齐安装器。'))
    }

    foreach ($launcherFile in $Profile.deployment.launcherFiles) {
        $resolvedLauncher = Resolve-InstallerPath -Root $Profile.rootPath -Path $launcherFile
        $exists = Test-Path -LiteralPath $resolvedLauncher
        $checks.Add((New-InstallerCheck -Id ('deploy.{0}' -f ([IO.Path]::GetFileNameWithoutExtension($launcherFile))) -Title ('启动器文件存在: {0}' -f $launcherFile) -Category 'deployment' -Status $(if ($exists) { 'pass' } else { 'fail' }) -Class $(if ($exists) { 'A' } else { 'C' }) -Evidence @{ path = $resolvedLauncher } -RecommendedAction '包内缺少启动器文件，请重新构建发布包。'))
    }

    $nextSteps = @(
        '如需预置 provider/model，请运行 launcher/configure-opencode.cmd；默认会同时写入全局配置和运行时配置。',
        '如需浏览器入口，请双击 launcher/open-opencode-web.cmd。',
        '如需额外安装官方 Desktop Beta，请双击 launcher/install-desktop.cmd。',
        '如果尚未完成个人认证，请在 OpenCode 中按提示完成首次连接。'
    )

    return [pscustomobject]@{
        checks    = [object[]]$checks.ToArray()
        nextSteps = $nextSteps
    }
}

Export-ModuleMember -Function *
