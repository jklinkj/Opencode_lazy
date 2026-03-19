Set-StrictMode -Version 3.0

function New-RunContext {
    param(
        [Parameter(Mandatory)]
        [object]$Profile,
        [Parameter(Mandatory)]
        [string]$Mode
    )

    Ensure-Directory -Path $Profile.resolvedPaths.reportRoot | Out-Null
    $runRoot = $null

    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        $name = '{0}-{1}-{2}-{3}' -f (Get-Date).ToString('yyyyMMdd-HHmmssfff'), $env:COMPUTERNAME, $PID, ([Guid]::NewGuid().ToString('N').Substring(0, 8))
        $candidate = Join-Path -Path $Profile.resolvedPaths.reportRoot -ChildPath $name

        try {
            New-Item -ItemType Directory -Path $candidate -ErrorAction Stop | Out-Null
            $runRoot = $candidate
            break
        }
        catch [System.IO.IOException] {
            continue
        }
    }

    if (-not $runRoot) {
        throw '无法创建唯一的报告目录。'
    }

    return [pscustomobject]@{
        mode        = $Mode
        root        = $runRoot
        summaryPath = Join-Path -Path $runRoot -ChildPath 'summary.txt'
        resultPath  = Join-Path -Path $runRoot -ChildPath 'result.json'
        logPath     = Join-Path -Path $runRoot -ChildPath 'events.log'
    }
}

function Write-InstallerReports {
    param(
        [Parameter(Mandatory)]
        [object]$RunContext,
        [Parameter(Mandatory)]
        [object]$Result
    )

    $summaryLines = New-Object System.Collections.Generic.List[string]
    $summaryLines.Add('岭南学院 OpenCode 一体化体检安装结果')
    $summaryLines.Add(('模式: {0}' -f $Result.mode))
    $summaryLines.Add(('策略版本: {0}' -f $Result.policyVersion))
    $summaryLines.Add(('机器: {0}' -f $Result.machine.computerName))
    $summaryLines.Add(('用户: {0}' -f $Result.machine.userName))
    $summaryLines.Add(('预检分型: {0}' -f $Result.precheckClassification))
    if ($Result.postcheckClassification) {
        $summaryLines.Add(('复检分型: {0}' -f $Result.postcheckClassification))
    }
    $summaryLines.Add(('最终分型: {0}' -f $Result.finalClassification))
    $summaryLines.Add(('退出码: {0}' -f $Result.exitCode))
    $summaryLines.Add('')

    if ($Result.repairActions.Count -gt 0) {
        $summaryLines.Add('自动处理动作:')
        foreach ($action in $Result.repairActions) {
            $summaryLines.Add(('- [{0}] {1}' -f $(if ($action.success) { '成功' } else { '失败' }), $action.summary))
        }
        $summaryLines.Add('')
    }

    $failedChecks = @($Result.finalChecks | Where-Object { $_.status -eq 'fail' })
    if ($failedChecks.Count -gt 0) {
        $summaryLines.Add('仍需处理的问题:')
        foreach ($check in $failedChecks) {
            $summaryLines.Add(('- [{0}] {1}: {2}' -f $check.classification, $check.title, $check.recommendedAction))
        }
        $summaryLines.Add('')
    }

    if ($Result.nextSteps.Count -gt 0) {
        $summaryLines.Add('下一步建议:')
        foreach ($step in $Result.nextSteps) {
            $summaryLines.Add(('- {0}' -f $step))
        }
        $summaryLines.Add('')
    }

    Set-Content -Path $RunContext.summaryPath -Value $summaryLines -Encoding utf8
    $Result | ConvertTo-Json -Depth 15 | Set-Content -Path $RunContext.resultPath -Encoding utf8
}

Export-ModuleMember -Function *
