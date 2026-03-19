Set-StrictMode -Version 3.0

function Invoke-OfflineExpandInstaller {
    param(
        [Parameter(Mandatory)]
        [object]$Method,
        [Parameter(Mandatory)]
        [object]$Profile
    )

    $source = Resolve-InstallerPath -Root $Profile.rootPath -Path $Method.source
    $destination = Resolve-InstallerPath -Root $Profile.rootPath -Path $Method.destination

    if (-not (Test-Path -LiteralPath $source)) {
        return [pscustomobject]@{
            attempted = $false
            success   = $false
            summary   = ('离线包不存在: {0}' -f $source)
            detail    = @{ source = $source; destination = $destination }
        }
    }

    Ensure-Directory -Path (Split-Path -Path $destination -Parent) | Out-Null
    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
    }

    if ((Get-Item -LiteralPath $source).PSIsContainer) {
        Copy-Item -Path $source -Destination $destination -Recurse -Force
    }
    elseif ([IO.Path]::GetExtension($source) -eq '.zip') {
        Expand-Archive -Path $source -DestinationPath $destination -Force
    }
    else {
        return [pscustomobject]@{
            attempted = $true
            success   = $false
            summary   = ('不支持的离线包格式: {0}' -f $source)
            detail    = @{ source = $source; destination = $destination }
        }
    }

    $expected = if (($Method.PSObject.Properties.Name -contains 'expectedFile') -and $Method.expectedFile) { Find-FileUnderRoot -Root $destination -FileName $Method.expectedFile } else { $destination }
    return [pscustomobject]@{
        attempted = $true
        success   = [bool]$expected
        summary   = ('离线内容已部署到 {0}' -f $destination)
        detail    = @{ source = $source; destination = $destination; expectedFile = $expected }
    }
}

function Invoke-CommandInstaller {
    param(
        [Parameter(Mandatory)]
        [object]$Method,
        [Parameter(Mandatory)]
        [object]$Profile
    )

    if (($Method.PSObject.Properties.Name -contains 'requires') -and $Method.requires -and -not (Get-Command -Name $Method.requires -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{
            attempted = $false
            success   = $false
            summary   = ('缺少前置命令: {0}' -f $Method.requires)
            detail    = $null
        }
    }

    $tokens = Get-InstallerTokens -Profile $Profile
    $commandName = Expand-TemplateString -Value $Method.command -Tokens $tokens
    $command = Get-Command -Name $commandName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) {
        return [pscustomobject]@{
            attempted = $false
            success   = $false
            summary   = ('未找到命令: {0}' -f $commandName)
            detail    = $null
        }
    }

    $arguments = Expand-TemplateArray -Values $Method.args -Tokens $tokens
    $result = Invoke-ExternalCommand -CommandPath $command.Source -Arguments $arguments
    if (($Method.PSObject.Properties.Name -contains 'refreshPath') -and $Method.refreshPath) {
        Sync-ProcessPathFromSystem
        Add-ProcessPathEntries -Entries (Get-RuntimePathEntries -Profile $Profile)
    }

    return [pscustomobject]@{
        attempted = $true
        success   = $result.success
        summary   = ('执行命令安装: {0} {1}' -f $commandName, ($arguments -join ' '))
        detail    = $result
    }
}

function Invoke-NpmPackageInstaller {
    param(
        [Parameter(Mandatory)]
        [object]$Method,
        [Parameter(Mandatory)]
        [object]$Profile
    )

    $npmDefinition = $Profile.dependencies.PSObject.Properties['npm'].Value
    $npmState = Get-DependencyState -DependencyId 'npm' -Definition $npmDefinition -Profile $Profile
    if (-not $npmState.installed) {
        return [pscustomobject]@{
            attempted = $false
            success   = $false
            summary   = 'npm 不可用，无法安装 OpenCode'
            detail    = $null
        }
    }

    $packageSpec = $null
    if (($Method.PSObject.Properties.Name -contains 'source') -and $Method.source) {
        $sourcePath = Resolve-InstallerPath -Root $Profile.rootPath -Path $Method.source
        if (Test-Path -LiteralPath $sourcePath) {
            $packageSpec = $sourcePath
        }
    }

    if (-not $packageSpec) {
        $packageSpec = $(if ($Method.PSObject.Properties.Name -contains 'fallbackPackage') { $Method.fallbackPackage } else { $null })
    }

    Ensure-Directory -Path $Profile.resolvedPaths.npmGlobalRoot | Out-Null
    $arguments = @('install', '-g', $packageSpec, '--prefix', $Profile.resolvedPaths.npmGlobalRoot, '--no-fund', '--no-audit')
    $result = Invoke-ExternalCommand -CommandPath $npmState.commandPath -Arguments $arguments

    return [pscustomobject]@{
        attempted = $true
        success   = $result.success
        summary   = ('通过 npm 安装 {0}' -f $packageSpec)
        detail    = $result
    }
}

function Invoke-DownloadExpandInstaller {
    param(
        [Parameter(Mandatory)]
        [object]$Method,
        [Parameter(Mandatory)]
        [object]$Profile
    )

    $download = Invoke-ArtifactAcquire -Profile $Profile -ArtifactId $Method.artifactId
    if (-not $download.success) {
        return [pscustomobject]@{
            attempted = $true
            success   = $false
            summary   = $download.summary
            detail    = $download
        }
    }

    $proxyMethod = [pscustomobject]@{
        source       = $download.localPath
        destination  = $Method.destination
        expectedFile = $(if (($Method.PSObject.Properties.Name -contains 'expectedFile') -and $Method.expectedFile) { $Method.expectedFile } else { $null })
    }

    $result = Invoke-OfflineExpandInstaller -Method $proxyMethod -Profile $Profile
    return [pscustomobject]@{
        attempted = $true
        success   = $result.success
        summary   = $result.summary
        detail    = @{
            download = $download
            install  = $result
        }
    }
}

function Invoke-DownloadNpmPackageInstaller {
    param(
        [Parameter(Mandatory)]
        [object]$Method,
        [Parameter(Mandatory)]
        [object]$Profile
    )

    $download = Invoke-ArtifactAcquire -Profile $Profile -ArtifactId $Method.artifactId
    if (-not $download.success) {
        return [pscustomobject]@{
            attempted = $true
            success   = $false
            summary   = $download.summary
            detail    = $download
        }
    }

    $proxyMethod = [pscustomobject]@{
        source = $download.localPath
    }

    $result = Invoke-NpmPackageInstaller -Method $proxyMethod -Profile $Profile
    return [pscustomobject]@{
        attempted = $true
        success   = $result.success
        summary   = $result.summary
        detail    = @{
            download = $download
            install  = $result
        }
    }
}

function Invoke-DependencyRepair {
    param(
        [Parameter(Mandatory)]
        [string]$DependencyId,
        [Parameter(Mandatory)]
        [object]$Profile
    )

    $definition = $Profile.dependencies.PSObject.Properties[$DependencyId].Value
    $state = Get-DependencyState -DependencyId $DependencyId -Definition $definition -Profile $Profile
    if ($state.installed -and $state.meetsVersion) {
        return [pscustomobject]@{
            dependencyId = $DependencyId
            success      = $true
            changed      = $false
            summary      = ('{0} 已满足要求，无需处理。' -f $definition.displayName)
            attempts     = @()
        }
    }

    if (-not (($definition.PSObject.Properties.Name -contains 'installers') -and $definition.installers) -or @($definition.installers).Count -eq 0) {
        return [pscustomobject]@{
            dependencyId = $DependencyId
            success      = $false
            changed      = $false
            summary      = ('{0} 缺少可执行的自动修复策略。' -f $definition.displayName)
            attempts     = @()
        }
    }

    $attempts = New-Object System.Collections.Generic.List[object]
    foreach ($method in $definition.installers) {
        Write-InstallerLog -Level INFO -Message ('尝试修复依赖: {0}' -f $DependencyId) -Data $method
        switch ($method.type) {
            'offline-expand' { $attempt = Invoke-OfflineExpandInstaller -Method $method -Profile $Profile }
            'command' { $attempt = Invoke-CommandInstaller -Method $method -Profile $Profile }
            'npm-package' { $attempt = Invoke-NpmPackageInstaller -Method $method -Profile $Profile }
            'download-expand' { $attempt = Invoke-DownloadExpandInstaller -Method $method -Profile $Profile }
            'download-npm-package' { $attempt = Invoke-DownloadNpmPackageInstaller -Method $method -Profile $Profile }
            default {
                $attempt = [pscustomobject]@{
                    attempted = $false
                    success   = $false
                    summary   = ('未知安装方式: {0}' -f $method.type)
                    detail    = $method
                }
            }
        }

        $attempts.Add($attempt)
        Write-InstallerLog -Level INFO -Message ('修复动作结果: {0}' -f $DependencyId) -Data $attempt

        Sync-ProcessPathFromSystem
        Add-ProcessPathEntries -Entries (Get-RuntimePathEntries -Profile $Profile)

        $validated = Get-DependencyState -DependencyId $DependencyId -Definition $definition -Profile $Profile
        if ($validated.installed -and $validated.meetsVersion) {
            return [pscustomobject]@{
                dependencyId = $DependencyId
                success      = $true
                changed      = $true
                summary      = ('{0} 已自动修复或安装完成。' -f $definition.displayName)
                attempts     = [object[]]$attempts.ToArray()
            }
        }
    }

    return [pscustomobject]@{
        dependencyId = $DependencyId
        success      = $false
        changed      = $true
        summary      = ('{0} 自动处理后仍未满足要求。' -f $definition.displayName)
        attempts     = [object[]]$attempts.ToArray()
    }
}

function Invoke-RepairPlan {
    param(
        [Parameter(Mandatory)]
        [object]$Profile,
        [Parameter(Mandatory)]
        [object[]]$Checks
    )

    $orderedIds = @('git', 'node', 'opencode')
    $targetIds = New-Object System.Collections.Generic.List[string]

    foreach ($check in ($Checks | Where-Object { $_.status -eq 'fail' -and $_.autoFixable -and $_.repairId })) {
        if (-not $targetIds.Contains($check.repairId)) {
            $targetIds.Add($check.repairId)
        }
    }

    $actions = New-Object System.Collections.Generic.List[object]
    foreach ($dependencyId in $orderedIds) {
        if (-not $targetIds.Contains($dependencyId)) {
            continue
        }

        $action = Invoke-DependencyRepair -DependencyId $dependencyId -Profile $Profile
        $actions.Add($action)
    }

    return [pscustomobject]@{
        actions = [object[]]$actions.ToArray()
    }
}

Export-ModuleMember -Function *

