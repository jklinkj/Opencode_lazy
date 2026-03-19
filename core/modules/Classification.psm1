Set-StrictMode -Version 3.0

function Get-ClassificationRank {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('A', 'B', 'C', 'D')]
        [string]$Classification
    )

    switch ($Classification) {
        'A' { return 0 }
        'B' { return 1 }
        'C' { return 2 }
        'D' { return 3 }
    }
}

function Get-ChecksClassification {
    param(
        [object[]]$Checks
    )

    if ($null -eq $Checks -or $Checks.Count -eq 0) {
        return 'A'
    }

    $worst = 'A'
    foreach ($check in $Checks) {
        if ($check.status -ne 'fail') {
            continue
        }

        if ((Get-ClassificationRank -Classification $check.classification) -gt (Get-ClassificationRank -Classification $worst)) {
            $worst = $check.classification
        }
    }

    return $worst
}

function Convert-ClassificationToExitCode {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('A', 'B', 'C', 'D')]
        [string]$Classification
    )

    switch ($Classification) {
        'A' { return 0 }
        'B' { return 10 }
        'C' { return 20 }
        'D' { return 30 }
    }
}

Export-ModuleMember -Function *
