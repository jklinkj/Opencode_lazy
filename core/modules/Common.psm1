Set-StrictMode -Version 3.0

function Remove-JsonCComments {
    param(
        [Parameter(Mandatory)]
        [string]$Content
    )

    $builder = New-Object System.Text.StringBuilder
    $inString = $false
    $escape = $false
    $lineComment = $false
    $blockComment = $false

    for ($i = 0; $i -lt $Content.Length; $i++) {
        $char = $Content[$i]
        $next = if ($i + 1 -lt $Content.Length) { $Content[$i + 1] } else { [char]0 }

        if ($lineComment) {
            if ($char -eq "`n") {
                $lineComment = $false
                [void]$builder.Append($char)
            }

            continue
        }

        if ($blockComment) {
            if ($char -eq '*' -and $next -eq '/') {
                $blockComment = $false
                $i++
            }

            continue
        }

        if ($inString) {
            [void]$builder.Append($char)

            if ($escape) {
                $escape = $false
                continue
            }

            if ($char -eq '\') {
                $escape = $true
                continue
            }

            if ($char -eq '"') {
                $inString = $false
            }

            continue
        }

        if ($char -eq '/' -and $next -eq '/') {
            $lineComment = $true
            $i++
            continue
        }

        if ($char -eq '/' -and $next -eq '*') {
            $blockComment = $true
            $i++
            continue
        }

        if ($char -eq '"') {
            $inString = $true
        }

        [void]$builder.Append($char)
    }

    return $builder.ToString()
}

function ConvertFrom-JsonCFile {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $raw = Get-Content -Path $Path -Raw -Encoding utf8
    $clean = Remove-JsonCComments -Content $raw
    return $clean | ConvertFrom-Json
}

function Resolve-InstallerPath {
    param(
        [Parameter(Mandatory)]
        [string]$Root,
        [Parameter(Mandatory)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    if ($Path.StartsWith('~/')) {
        $homeRelative = $Path.Substring(2).Replace('/', [IO.Path]::DirectorySeparatorChar)
        return Join-Path -Path $HOME -ChildPath $homeRelative
    }

    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }

    $normalized = $Path.Replace('/', [IO.Path]::DirectorySeparatorChar)
    return [IO.Path]::GetFullPath((Join-Path -Path $Root -ChildPath $normalized))
}

function Ensure-Directory {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    return $Path
}

function Get-TimestampString {
    return (Get-Date).ToString('yyyyMMdd-HHmmss')
}

function Test-WritablePath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        Ensure-Directory -Path $Path | Out-Null
        $probePath = Join-Path -Path $Path -ChildPath (".probe-{0}.tmp" -f ([Guid]::NewGuid().ToString('N')))
        Set-Content -Path $probePath -Value 'probe' -Encoding utf8
        Remove-Item -Path $probePath -Force
        return $true
    }
    catch {
        return $false
    }
}

function New-InstallerCheck {
    param(
        [Parameter(Mandatory)]
        [string]$Id,
        [Parameter(Mandatory)]
        [string]$Title,
        [Parameter(Mandatory)]
        [string]$Category,
        [Parameter(Mandatory)]
        [ValidateSet('pass', 'warn', 'fail')]
        [string]$Status,
        [Parameter(Mandatory)]
        [ValidateSet('A', 'B', 'C', 'D')]
        [string]$Class,
        [Parameter(Mandatory)]
        [object]$Evidence,
        [string]$RecommendedAction = '',
        [bool]$AutoFixable = $false,
        [string]$RepairId = ''
    )

    return [pscustomobject]@{
        id                = $Id
        title             = $Title
        category          = $Category
        status            = $Status
        classification    = $Class
        evidence          = $Evidence
        recommendedAction = $RecommendedAction
        autoFixable       = $AutoFixable
        repairId          = $RepairId
    }
}

function ConvertTo-NormalizedVersion {
    param(
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    try {
        return [version]$Value.TrimStart('v')
    }
    catch {
        return $null
    }
}

function Test-VersionAtLeast {
    param(
        [string]$Actual,
        [string]$Minimum
    )

    $actualVersion = ConvertTo-NormalizedVersion -Value $Actual
    $minimumVersion = ConvertTo-NormalizedVersion -Value $Minimum

    if ($null -eq $actualVersion -or $null -eq $minimumVersion) {
        return $false
    }

    return ($actualVersion -ge $minimumVersion)
}

function Get-FirstAvailableCommand {
    param(
        [string[]]$CommandCandidates,
        [string[]]$PathCandidates,
        [string]$Root
    )

    foreach ($pathCandidate in ($PathCandidates | Where-Object { $_ })) {
        $resolved = Resolve-InstallerPath -Root $Root -Path $pathCandidate
        if (Test-Path -LiteralPath $resolved) {
            return $resolved
        }
    }

    foreach ($commandCandidate in ($CommandCandidates | Where-Object { $_ })) {
        $command = Get-Command -Name $commandCandidate -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command) {
            return $command.Source
        }
    }

    return $null
}

function Find-FileUnderRoot {
    param(
        [Parameter(Mandatory)]
        [string]$Root,
        [Parameter(Mandatory)]
        [string]$FileName
    )

    if (-not (Test-Path -LiteralPath $Root)) {
        return $null
    }

    $match = Get-ChildItem -Path $Root -Recurse -File -Filter $FileName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $match) {
        return $match.FullName
    }

    return $null
}

function Expand-TemplateString {
    param(
        [Parameter(Mandatory)]
        [string]$Value,
        [Parameter(Mandatory)]
        [hashtable]$Tokens
    )

    $expanded = $Value
    foreach ($key in $Tokens.Keys) {
        $expanded = $expanded.Replace(('{' + $key + '}'), [string]$Tokens[$key])
    }

    return $expanded
}

function Expand-TemplateArray {
    param(
        [string[]]$Values,
        [hashtable]$Tokens
    )

    $result = @()
    foreach ($value in ($Values | Where-Object { $_ })) {
        $result += Expand-TemplateString -Value $value -Tokens $Tokens
    }

    return ,$result
}

function Sync-ProcessPathFromSystem {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @($machinePath, $userPath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $env:Path = ($parts -join ';')
}

function Add-ProcessPathEntries {
    param(
        [string[]]$Entries
    )

    $existing = @($env:Path -split ';' | Where-Object { $_ })
    $merged = New-Object System.Collections.Generic.List[string]

    foreach ($entry in ($Entries | Where-Object { $_ })) {
        if ((Test-Path -LiteralPath $entry) -and -not ($existing -contains $entry) -and -not ($merged -contains $entry)) {
            $merged.Add($entry)
        }
    }

    $env:Path = (($merged + $existing) -join ';')
}

function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory)]
        [string]$CommandPath,
        [string[]]$Arguments
    )

    $output = @()
    $script:LASTEXITCODE = 0
    $output = & $CommandPath @Arguments 2>&1 | ForEach-Object { $_.ToString() }
    $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }

    return [pscustomobject]@{
        command  = $CommandPath
        arguments = $Arguments
        output   = $output
        exitCode = $exitCode
        success  = ($exitCode -eq 0)
    }
}

Export-ModuleMember -Function *

