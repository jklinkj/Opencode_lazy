[CmdletBinding()]
param(
    [ValidateSet('smart', 'scan-only')]
    [string]$Mode = 'smart',
    [string]$ProfilePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8

$rootPath = Split-Path -Path $PSScriptRoot -Parent
. (Join-Path -Path $PSScriptRoot -ChildPath 'Load-CoreModules.ps1')
$coreModulesPath = Import-CoreModules -ProjectRoot $rootPath -Names @('Common', 'Logging', 'Profile', 'Checks', 'Classification', 'Downloads', 'Repairs', 'Deployment', 'Reports')
if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
    $ProfilePath = Join-Path -Path $rootPath -ChildPath 'profiles\lingnan-admin-v1.jsonc'
}

$startedAt = (Get-Date).ToString('o')
$runContext = $null

try {
    $resolvedProfilePath = Resolve-InstallerPath -Root $rootPath -Path $ProfilePath
    $profile = Get-InstallerProfile -ProfilePath $resolvedProfilePath -Root $rootPath
    $runContext = New-RunContext -Profile $profile -Mode $Mode
    Initialize-InstallerLog -Path $runContext.logPath

    Write-Host ('[Lingnan OpenCode] mode: {0}' -f $Mode)
    Write-InstallerLog -Level INFO -Message 'Installer started' -Data @{ mode = $Mode; profile = $resolvedProfilePath; coreModulesPath = $coreModulesPath }

    Sync-ProcessPathFromSystem
    Add-ProcessPathEntries -Entries (Get-RuntimePathEntries -Profile $profile)

    Write-Host '1/4 Running precheck...'
    $precheck = Invoke-InstallerChecks -Profile $profile -Phase 'precheck'
    $precheckClassification = Get-ChecksClassification -Checks $precheck.checks
    Write-InstallerLog -Level INFO -Message 'Precheck finished' -Data @{ classification = $precheckClassification }

    $repairActions = @()
    $postcheck = $null
    $postcheckClassification = $null
    $deployment = $null
    $finalChecks = @($precheck.checks)
    $finalFacts = $precheck.facts

    if ($Mode -eq 'smart' -and $precheckClassification -in @('A', 'B')) {
        Write-Host '2/4 Repairing auto-fixable issues...'
        $repairPlan = Invoke-RepairPlan -Profile $profile -Checks $precheck.checks
        $repairActions = @($repairPlan.actions)
        Write-InstallerLog -Level INFO -Message 'Repair stage finished' -Data @{ actions = $repairActions.Count }

        Sync-ProcessPathFromSystem
        Add-ProcessPathEntries -Entries (Get-RuntimePathEntries -Profile $profile)

        Write-Host '3/4 Running postcheck...'
        $postcheck = Invoke-InstallerChecks -Profile $profile -Phase 'postcheck'
        $postcheckClassification = Get-ChecksClassification -Checks $postcheck.checks
        $finalChecks = @($postcheck.checks)
        $finalFacts = $postcheck.facts
        Write-InstallerLog -Level INFO -Message 'Postcheck finished' -Data @{ classification = $postcheckClassification }

        if ($postcheckClassification -in @('A', 'B')) {
            Write-Host '4/4 Writing deployment state...'
            $deployment = Invoke-Deployment -Profile $profile -Facts $postcheck.facts
            $finalChecks = @($postcheck.checks + $deployment.checks)
            Write-InstallerLog -Level INFO -Message 'Deployment stage finished' -Data @{ checks = $deployment.checks.Count }
        }
    }

    $finalClassification = Get-ChecksClassification -Checks $finalChecks
    $exitCode = Convert-ClassificationToExitCode -Classification $finalClassification

    $nextSteps = New-Object System.Collections.Generic.List[string]
    if ($deployment -and $deployment.nextSteps) {
        foreach ($step in $deployment.nextSteps) {
            $nextSteps.Add($step)
        }
    }

    if ($Mode -eq 'scan-only') {
        $nextSteps.Add('Scan-only mode did not make any changes.')
        $nextSteps.Add('Run launcher/start.cmd for automatic installation.')
    }
    elseif ($finalClassification -eq 'B') {
        $nextSteps.Add('Some repairable issues remain. Check local payloads or download sources.')
    }
    elseif ($finalClassification -eq 'C') {
        $nextSteps.Add('A manual or IT-owned blocker remains. Submit the full reports directory.')
    }
    elseif ($finalClassification -eq 'D') {
        $nextSteps.Add('This machine is outside the supported V1 scope.')
    }

    $result = [ordered]@{
        reportVersion           = '1'
        mode                    = $Mode
        policyVersion           = $profile.policyVersion
        startedAt               = $startedAt
        finishedAt              = (Get-Date).ToString('o')
        machine                 = $finalFacts.machine
        profilePath             = $resolvedProfilePath
        precheckClassification  = $precheckClassification
        postcheckClassification = $postcheckClassification
        finalClassification     = $finalClassification
        exitCode                = $exitCode
        precheckFacts           = $precheck.facts
        postcheckFacts          = if ($postcheck) { $postcheck.facts } else { $null }
        precheckChecks          = @($precheck.checks)
        postcheckChecks         = if ($postcheck) { @($postcheck.checks) } else { @() }
        deploymentChecks        = if ($deployment) { @($deployment.checks) } else { @() }
        finalChecks             = @($finalChecks)
        repairActions           = @($repairActions)
        nextSteps               = @($nextSteps)
        reportDirectory         = $runContext.root
    }

    Write-InstallerReports -RunContext $runContext -Result $result
    Write-InstallerLog -Level INFO -Message 'Reports written' -Data @{ reportRoot = $runContext.root; finalClassification = $finalClassification }

    Write-Host ('Finished. Final classification: {0}' -f $finalClassification)
    Write-Host ('Report directory: {0}' -f $runContext.root)
    exit $exitCode
}
catch {
    $message = $_.Exception.Message
    Write-Host $message
    if ($runContext) {
        Write-InstallerLog -Level ERROR -Message 'Unhandled installer exception' -Data @{ error = $message }
        $result = [ordered]@{
            reportVersion           = '1'
            mode                    = $Mode
            policyVersion           = $null
            startedAt               = $startedAt
            finishedAt              = (Get-Date).ToString('o')
            machine                 = @{ computerName = $env:COMPUTERNAME; userName = [Security.Principal.WindowsIdentity]::GetCurrent().Name }
            profilePath             = $ProfilePath
            precheckClassification  = $null
            postcheckClassification = $null
            finalClassification     = 'C'
            exitCode                = 99
            precheckFacts           = $null
            postcheckFacts          = $null
            precheckChecks          = @()
            postcheckChecks         = @()
            deploymentChecks        = @()
            finalChecks             = @()
            repairActions           = @()
            nextSteps               = @('The installer hit an internal error. Submit the reports directory to the maintainer.')
            error                   = $message
            reportDirectory         = $runContext.root
        }
        Write-InstallerReports -RunContext $runContext -Result $result
    }

    exit 99
}