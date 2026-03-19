Set-StrictMode -Version 3.0

function Get-CoreModulesPath {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    $projectLocal = Join-Path -Path $ProjectRoot -ChildPath 'core\modules'
    if (Test-Path -LiteralPath $projectLocal -PathType Container) {
        return $projectLocal
    }

    $workspacePath = Join-Path -Path (Split-Path -Path $ProjectRoot -Parent) -ChildPath 'core\modules'
    if (Test-Path -LiteralPath $workspacePath -PathType Container) {
        return $workspacePath
    }

    throw 'Shared core\\modules directory was not found.'
}

function Import-CoreModules {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        [Parameter(Mandatory)]
        [string[]]$Names
    )

    $coreModulesPath = Get-CoreModulesPath -ProjectRoot $ProjectRoot
    foreach ($name in $Names) {
        Import-Module (Join-Path -Path $coreModulesPath -ChildPath ('{0}.psm1' -f $name)) -Force -DisableNameChecking
    }

    return $coreModulesPath
}