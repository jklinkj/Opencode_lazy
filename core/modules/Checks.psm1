Set-StrictMode -Version 3.0

function Get-TotalPhysicalMemoryBytes {
    if (-not ('NativeMemoryStatus' -as [type])) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeMemoryStatus {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct MEMORYSTATUSEX {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);
}
"@
    }

    $memoryStatus = New-Object NativeMemoryStatus+MEMORYSTATUSEX
    $memoryStatus.dwLength = [System.Runtime.InteropServices.Marshal]::SizeOf([type]'NativeMemoryStatus+MEMORYSTATUSEX')
    $ok = [NativeMemoryStatus]::GlobalMemoryStatusEx([ref]$memoryStatus)
    if (-not $ok) {
        return 0
    }

    return [uint64]$memoryStatus.ullTotalPhys
}

function Get-OsRegistryInfo {
    $path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $item = Get-ItemProperty -Path $path -ErrorAction Stop
    return [pscustomobject]@{
        productName    = $item.ProductName
        currentBuild   = [int]$item.CurrentBuild
        displayVersion = $item.DisplayVersion
        releaseId      = $item.ReleaseId
    }
}

function Get-DependencyState {
    param(
        [Parameter(Mandatory)]
        [string]$DependencyId,
        [Parameter(Mandatory)]
        [object]$Definition,
        [Parameter(Mandatory)]
        [object]$Profile
    )

    $commandCandidates = @()
    if ($Definition.PSObject.Properties.Name -contains 'commandCandidates') {
        $commandCandidates = @($Definition.commandCandidates)
    }

    $pathCandidates = @()
    if ($Definition.PSObject.Properties.Name -contains 'runtimeCandidates') {
        $pathCandidates = @($Definition.runtimeCandidates)
    }

    $commandPath = Get-FirstAvailableCommand -CommandCandidates $commandCandidates -PathCandidates $pathCandidates -Root $Profile.rootPath
    $version = $null
    $versionOutput = @()

    if ($commandPath) {
        try {
            $versionArgs = @()
            if ($Definition.PSObject.Properties.Name -contains 'versionArgs') {
                $versionArgs = @($Definition.versionArgs)
            }

            $result = Invoke-ExternalCommand -CommandPath $commandPath -Arguments $versionArgs
            $versionOutput = $result.output
            if (($Definition.PSObject.Properties.Name -contains 'versionRegex') -and $Definition.versionRegex) {
                $combined = ($versionOutput -join ' ')
                if ($combined -match $Definition.versionRegex) {
                    $version = $Matches.version
                }
            }
        }
        catch {
            $versionOutput = @($_.Exception.Message)
        }
    }

    $repairId = if (($Definition.PSObject.Properties.Name -contains 'repairDependencyId') -and $Definition.repairDependencyId) { $Definition.repairDependencyId } else { $DependencyId }
    $repairDefinition = if ($Profile.dependencies.PSObject.Properties.Name -contains $repairId) {
        $Profile.dependencies.PSObject.Properties[$repairId].Value
    }
    else {
        $null
    }

    $canRepair = $false
    if ($repairDefinition -and ($repairDefinition.PSObject.Properties.Name -contains 'installers') -and $repairDefinition.installers) {
        $canRepair = (@($repairDefinition.installers).Count -gt 0)
    }

    $meetsVersion = $false
    if ($commandPath -and (($Definition.PSObject.Properties.Name -contains 'minVersion') -and $Definition.minVersion)) {
        $meetsVersion = Test-VersionAtLeast -Actual $version -Minimum $Definition.minVersion
    }
    elseif ($commandPath) {
        $meetsVersion = $true
    }

    return [pscustomobject]@{
        id            = $DependencyId
        displayName   = $(if ($Definition.PSObject.Properties.Name -contains 'displayName') { $Definition.displayName } else { $DependencyId })
        commandPath   = $commandPath
        installed     = [bool]$commandPath
        version       = $version
        versionOutput = $versionOutput
        minVersion    = $(if ($Definition.PSObject.Properties.Name -contains 'minVersion') { $Definition.minVersion } else { $null })
        meetsVersion  = $meetsVersion
        required      = [bool]$(if ($Definition.PSObject.Properties.Name -contains 'required') { $Definition.required } else { $false })
        repairId      = $repairId
        canRepair     = $canRepair
    }
}

function Test-DnsTarget {
    param(
        [Parameter(Mandatory)]
        [string]$Host
    )

    try {
        $addresses = [System.Net.Dns]::GetHostAddresses($Host)
        return [pscustomobject]@{
            success   = ($addresses.Count -gt 0)
            addresses = @($addresses | ForEach-Object { $_.IPAddressToString })
            error     = $null
        }
    }
    catch {
        return [pscustomobject]@{
            success   = $false
            addresses = @()
            error     = $_.Exception.Message
        }
    }
}

function Test-HttpsTarget {
    param(
        [Parameter(Mandatory)]
        [string]$Url
    )

    try {
        $request = [System.Net.WebRequest]::Create($Url)
        $request.Method = 'HEAD'
        $request.Timeout = 5000
        $response = $request.GetResponse()
        $statusCode = [int]([System.Net.HttpWebResponse]$response).StatusCode
        $response.Close()

        return [pscustomobject]@{
            success    = $true
            statusCode = $statusCode
            error      = $null
        }
    }
    catch [System.Net.WebException] {
        if ($_.Exception.Response) {
            $statusCode = [int]([System.Net.HttpWebResponse]$_.Exception.Response).StatusCode
            $_.Exception.Response.Close()
            return [pscustomobject]@{
                success    = $true
                statusCode = $statusCode
                error      = $null
            }
        }

        return [pscustomobject]@{
            success    = $false
            statusCode = $null
            error      = $_.Exception.Message
        }
    }
    catch {
        return [pscustomobject]@{
            success    = $false
            statusCode = $null
            error      = $_.Exception.Message
        }
    }
}

function Get-DefaultBrowserEvidence {
    $userChoicePath = 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice'
    try {
        $entry = Get-ItemProperty -Path $userChoicePath -ErrorAction Stop
        return [pscustomobject]@{
            detected = $true
            progId   = $entry.ProgId
        }
    }
    catch {
        return [pscustomobject]@{
            detected = $false
            progId   = $null
        }
    }
}

function Get-ExistingPaths {
    param(
        [string[]]$Paths,
        [string]$Root
    )

    $existing = @()
    foreach ($path in ($Paths | Where-Object { $_ })) {
        $resolved = Resolve-InstallerPath -Root $Root -Path $path
        if (Test-Path -LiteralPath $resolved) {
            $existing += $resolved
        }
    }

    return ,$existing
}

function Invoke-InstallerChecks {
    param(
        [Parameter(Mandatory)]
        [object]$Profile,
        [string]$Phase = 'precheck'
    )

    $checks = New-Object System.Collections.Generic.List[object]
    $os = Get-OsRegistryInfo
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $systemDrive = Get-PSDrive -Name ([IO.Path]::GetPathRoot($env:SystemRoot).TrimEnd('\\').TrimEnd(':')) -ErrorAction SilentlyContinue
    $diskFreeGB = if ($systemDrive) { [math]::Round($systemDrive.Free / 1GB, 2) } else { $null }
    $memoryGB = [math]::Round((Get-TotalPhysicalMemoryBytes) / 1GB, 2)
    $buildNumber = [int]$os.currentBuild
    $arch = if ([Environment]::Is64BitOperatingSystem) { '64-bit' } else { '32-bit' }
    $browser = Get-DefaultBrowserEvidence
    $packageManagers = [ordered]@{
        winget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
        scoop  = [bool](Get-Command scoop -ErrorAction SilentlyContinue)
        choco  = [bool](Get-Command choco -ErrorAction SilentlyContinue)
        npm    = [bool](Get-Command npm -ErrorAction SilentlyContinue)
    }

    $machineEvidence = [ordered]@{
        computerName   = $env:COMPUTERNAME
        userName       = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        buildNumber    = $buildNumber
        osCaption      = $os.productName
        displayVersion = $os.displayVersion
        architecture   = $arch
        isAdmin        = $isAdmin
        powerShell     = $PSVersionTable.PSVersion.ToString()
        diskFreeGB     = $diskFreeGB
        memoryGB       = $memoryGB
    }

    if ($buildNumber -ge [int]$Profile.supportedOs.minBuild) {
        $checks.Add((New-InstallerCheck -Id 'os.build' -Title 'Windows 版本满足学院基线' -Category 'system' -Status 'pass' -Class 'A' -Evidence $machineEvidence))
    }
    else {
        $checks.Add((New-InstallerCheck -Id 'os.build' -Title 'Windows 版本满足学院基线' -Category 'system' -Status 'fail' -Class 'D' -Evidence $machineEvidence -RecommendedAction '当前 Windows 版本低于学院 V1 支持范围，需升级系统后再部署。'))
    }

    if ($Profile.supportedOs.architectures -contains $arch) {
        $checks.Add((New-InstallerCheck -Id 'os.architecture' -Title '系统架构符合要求' -Category 'system' -Status 'pass' -Class 'A' -Evidence @{ architecture = $arch }))
    }
    else {
        $checks.Add((New-InstallerCheck -Id 'os.architecture' -Title '系统架构符合要求' -Category 'system' -Status 'fail' -Class 'D' -Evidence @{ architecture = $arch } -RecommendedAction '当前系统不是受支持的 64 位 Windows。'))
    }

    $diskStatus = if ($diskFreeGB -ge [double]$Profile.thresholds.minDiskGB) { 'pass' } else { 'fail' }
    $diskClass = if ($diskStatus -eq 'pass') { 'A' } else { 'C' }
    $checks.Add((New-InstallerCheck -Id 'system.disk' -Title '系统盘剩余空间满足要求' -Category 'system' -Status $diskStatus -Class $diskClass -Evidence @{ freeGB = $diskFreeGB; minimumGB = $Profile.thresholds.minDiskGB } -RecommendedAction '请先清理磁盘空间或更换部署位置。'))

    $memoryStatus = if ($memoryGB -ge [double]$Profile.thresholds.minMemoryGB) { 'pass' } else { 'warn' }
    $checks.Add((New-InstallerCheck -Id 'system.memory' -Title '内存满足建议值' -Category 'system' -Status $memoryStatus -Class 'A' -Evidence @{ memoryGB = $memoryGB; minimumGB = $Profile.thresholds.minMemoryGB } -RecommendedAction '内存低于建议值，运行体验可能受影响。'))

    $executionPolicies = Get-ExecutionPolicy -List | Select-Object Scope, ExecutionPolicy
    $machinePolicy = ($executionPolicies | Where-Object Scope -eq 'MachinePolicy' | Select-Object -ExpandProperty ExecutionPolicy)
    $userPolicy = ($executionPolicies | Where-Object Scope -eq 'UserPolicy' | Select-Object -ExpandProperty ExecutionPolicy)
    $blockingPolicies = @(@($machinePolicy, $userPolicy) | Where-Object { $_ -and $_ -ne 'Undefined' -and ($Profile.policy.blockingExecutionPolicies -contains $_) })
    if ($blockingPolicies.Count -gt 0) {
        $checks.Add((New-InstallerCheck -Id 'policy.execution' -Title '脚本执行策略未被组织策略阻断' -Category 'policy' -Status 'fail' -Class 'C' -Evidence @{ policies = $executionPolicies; blocking = $blockingPolicies } -RecommendedAction '检测到组策略级脚本执行限制，请转 IT 处理白名单或执行策略。'))
    }
    else {
        $checks.Add((New-InstallerCheck -Id 'policy.execution' -Title '脚本执行策略未被组织策略阻断' -Category 'policy' -Status 'pass' -Class 'A' -Evidence @{ policies = $executionPolicies }))
    }

    $homeWritable = Test-WritablePath -Path $HOME
    $checks.Add((New-InstallerCheck -Id 'fs.home' -Title '用户主目录可写' -Category 'filesystem' -Status $(if ($homeWritable) { 'pass' } else { 'fail' }) -Class $(if ($homeWritable) { 'A' } else { 'C' }) -Evidence @{ path = $HOME; writable = $homeWritable } -RecommendedAction '用户目录不可写，无法完成用户级安装和认证。'))

    $tempWritable = Test-WritablePath -Path $env:TEMP
    $checks.Add((New-InstallerCheck -Id 'fs.temp' -Title '临时目录可写' -Category 'filesystem' -Status $(if ($tempWritable) { 'pass' } else { 'fail' }) -Class $(if ($tempWritable) { 'A' } else { 'C' }) -Evidence @{ path = $env:TEMP; writable = $tempWritable } -RecommendedAction '临时目录不可写，安装过程中可能失败。'))

    $oneDriveDetected = -not [string]::IsNullOrWhiteSpace($env:OneDrive)
    $checks.Add((New-InstallerCheck -Id 'fs.onedrive' -Title 'OneDrive 重定向检查' -Category 'filesystem' -Status $(if ($oneDriveDetected) { 'warn' } else { 'pass' }) -Class 'A' -Evidence @{ oneDrive = $env:OneDrive } -RecommendedAction '检测到 OneDrive，建议不要把长期工作区直接放在同步目录。'))

    $browserStatus = if ($browser.detected) { 'pass' } else { 'fail' }
    $browserClass = if ($browser.detected) { 'A' } else { 'C' }
    $checks.Add((New-InstallerCheck -Id 'browser.default' -Title '默认浏览器已配置' -Category 'ui' -Status $browserStatus -Class $browserClass -Evidence $browser -RecommendedAction '当前未检测到默认浏览器，无法稳定拉起 OpenCode Web。'))

    $listener = $null
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $listener.Start()
        $localPort = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
        $listener.Stop()
        $checks.Add((New-InstallerCheck -Id 'localhost.bind' -Title '本机回环端口可用' -Category 'network' -Status 'pass' -Class 'A' -Evidence @{ port = $localPort }))
    }
    catch {
        if ($listener) {
            $listener.Stop()
        }

        $checks.Add((New-InstallerCheck -Id 'localhost.bind' -Title '本机回环端口可用' -Category 'network' -Status 'fail' -Class 'C' -Evidence @{ error = $_.Exception.Message } -RecommendedAction '无法在本机回环地址上打开端口，请转 IT 排查本地策略和防火墙。'))
    }

    $checks.Add((New-InstallerCheck -Id 'pm.available' -Title '可用的包管理器检测' -Category 'install-source' -Status 'pass' -Class 'A' -Evidence $packageManagers))

    $dependencies = [ordered]@{}
    foreach ($property in $Profile.dependencies.PSObject.Properties) {
        $definition = $property.Value
        $dependencyState = Get-DependencyState -DependencyId $property.Name -Definition $definition -Profile $Profile
        $dependencies[$property.Name] = $dependencyState

        if ($dependencyState.installed -and $dependencyState.meetsVersion) {
            $checks.Add((New-InstallerCheck -Id ('dependency.{0}' -f $property.Name) -Title ('{0} 已安装且版本符合要求' -f $definition.displayName) -Category 'dependency' -Status 'pass' -Class 'A' -Evidence $dependencyState))
            continue
        }

        if ($dependencyState.installed -and -not $dependencyState.meetsVersion) {
            $class = if ($dependencyState.canRepair) { 'B' } else { 'C' }
            $checks.Add((New-InstallerCheck -Id ('dependency.{0}' -f $property.Name) -Title ('{0} 版本满足最低要求' -f $definition.displayName) -Category 'dependency' -Status 'fail' -Class $class -Evidence $dependencyState -RecommendedAction ('{0} 版本过低，请更新到 {1} 或更高。' -f $definition.displayName, $definition.minVersion) -AutoFixable $dependencyState.canRepair -RepairId $dependencyState.repairId))
            continue
        }

        if ($definition.required) {
            $class = if ($dependencyState.canRepair) { 'B' } else { 'C' }
            $checks.Add((New-InstallerCheck -Id ('dependency.{0}' -f $property.Name) -Title ('{0} 已安装' -f $definition.displayName) -Category 'dependency' -Status 'fail' -Class $class -Evidence $dependencyState -RecommendedAction ('缺少 {0}，请允许工具自动安装或转 IT 处理。' -f $definition.displayName) -AutoFixable $dependencyState.canRepair -RepairId $dependencyState.repairId))
        }
        else {
            $checks.Add((New-InstallerCheck -Id ('dependency.{0}' -f $property.Name) -Title ('{0} 已安装' -f $definition.displayName) -Category 'dependency' -Status 'warn' -Class 'A' -Evidence $dependencyState -RecommendedAction ('建议补齐 {0}。' -f $definition.displayName)))
        }
    }

    $globalConfigs = Get-ExistingPaths -Paths $Profile.checks.globalConfigPaths -Root $Profile.rootPath
    $checks.Add((New-InstallerCheck -Id 'opencode.global-config' -Title '现有全局配置检查' -Category 'opencode' -Status $(if (@($globalConfigs).Count -gt 0) { 'warn' } else { 'pass' }) -Class 'A' -Evidence @{ paths = $globalConfigs } -RecommendedAction '检测到现有全局配置，OpenCode 会进行多层合并，建议 IT 后续核对最终生效配置。'))

    $authFiles = Get-ExistingPaths -Paths $Profile.checks.authPaths -Root $Profile.rootPath
    $checks.Add((New-InstallerCheck -Id 'opencode.auth' -Title '个人认证状态检查' -Category 'opencode' -Status $(if (@($authFiles).Count -gt 0) { 'pass' } else { 'warn' }) -Class 'A' -Evidence @{ paths = $authFiles } -RecommendedAction '尚未检测到个人认证文件，安装后请通过浏览器入口完成首次连接。'))

    $appLockerService = Get-Service -Name AppIDSvc -ErrorAction SilentlyContinue
    $checks.Add((New-InstallerCheck -Id 'policy.applocker' -Title 'AppLocker 服务状态记录' -Category 'policy' -Status 'warn' -Class 'A' -Evidence @{ service = if ($appLockerService) { $appLockerService.Status } else { 'Unavailable' } } -RecommendedAction '如安装器被策略拦截，请将报告交给 IT 排查 AppLocker 或 EDR。'))

    $networkResults = New-Object System.Collections.Generic.List[object]
    foreach ($target in $Profile.networkTargets) {
        if ($target.type -eq 'dns') {
            $result = Test-DnsTarget -Host $target.host
            $networkResults.Add([pscustomobject]@{ id = $target.id; type = $target.type; success = $result.success; detail = $result })
            $checks.Add((New-InstallerCheck -Id ('network.{0}' -f $target.id) -Title $target.description -Category 'network' -Status $(if ($result.success) { 'pass' } else { $(if ($target.required) { 'fail' } else { 'warn' }) }) -Class $(if ($result.success) { 'A' } else { $target.failureClass }) -Evidence $result -RecommendedAction ('网络检测失败：{0}' -f $target.description)))
            continue
        }

        if ($target.type -eq 'https') {
            $result = Test-HttpsTarget -Url $target.url
            $networkResults.Add([pscustomobject]@{ id = $target.id; type = $target.type; success = $result.success; detail = $result })
            $checks.Add((New-InstallerCheck -Id ('network.{0}' -f $target.id) -Title $target.description -Category 'network' -Status $(if ($result.success) { 'pass' } else { $(if ($target.required) { 'fail' } else { 'warn' }) }) -Class $(if ($result.success) { 'A' } else { $target.failureClass }) -Evidence $result -RecommendedAction ('网络检测失败：{0}' -f $target.description)))
        }
    }


    $facts = @{
        phase           = $Phase
        machine         = $machineEvidence
        packageManagers = $packageManagers
        dependencies    = $dependencies
        browser         = $browser
        oneDrive        = $env:OneDrive
        network         = [object[]]$networkResults.ToArray()
    }

    $checkArray = [object[]]$checks.ToArray()
    return @{
        facts  = $facts
        checks = $checkArray
    }
}

Export-ModuleMember -Function *

