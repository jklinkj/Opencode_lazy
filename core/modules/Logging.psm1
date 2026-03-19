Set-StrictMode -Version 3.0

$script:InstallerLogPath = $null

function Initialize-InstallerLog {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $script:InstallerLogPath = $Path
    Set-Content -Path $script:InstallerLogPath -Value '' -Encoding utf8
}

function Write-InstallerLog {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level,
        [Parameter(Mandatory)]
        [string]$Message,
        [object]$Data
    )

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = '[{0}] [{1}] {2}' -f $timestamp, $Level, $Message

    if ($null -ne $Data) {
        try {
            $json = $Data | ConvertTo-Json -Depth 10 -Compress
            $line = '{0} | {1}' -f $line, $json
        }
        catch {
            $line = '{0} | {1}' -f $line, $Data.ToString()
        }
    }

    if ($script:InstallerLogPath) {
        Add-Content -Path $script:InstallerLogPath -Value $line -Encoding utf8
    }
}

function Get-InstallerLogPath {
    return $script:InstallerLogPath
}

Export-ModuleMember -Function *
