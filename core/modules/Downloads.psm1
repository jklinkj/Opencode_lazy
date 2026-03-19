Set-StrictMode -Version 3.0

function Write-DownloadTrace {
    param(
        [string]$Message,
        [object]$Data
    )

    if (Get-Command -Name Write-InstallerLog -ErrorAction SilentlyContinue) {
        Write-InstallerLog -Level INFO -Message $Message -Data $Data
    }
}

function Get-DownloadManifest {
    param(
        [Parameter(Mandatory)]
        [object]$Profile
    )

    if (-not $Profile.resolvedPaths.downloadManifestFile) {
        return $null
    }

    if (-not (Test-Path -LiteralPath $Profile.resolvedPaths.downloadManifestFile -PathType Leaf)) {
        throw ('Download manifest not found: {0}' -f $Profile.resolvedPaths.downloadManifestFile)
    }

    $manifest = ConvertFrom-JsonCFile -Path $Profile.resolvedPaths.downloadManifestFile
    $manifest | Add-Member -NotePropertyName manifestPath -NotePropertyValue $Profile.resolvedPaths.downloadManifestFile -Force
    return $manifest
}

function Get-ArtifactDefinition {
    param(
        [Parameter(Mandatory)]
        [object]$Manifest,
        [Parameter(Mandatory)]
        [string]$ArtifactId
    )

    if (-not (($Manifest.PSObject.Properties.Name -contains 'artifacts') -and $Manifest.artifacts)) {
        throw 'Download manifest does not define any artifacts.'
    }

    $artifactProperty = $Manifest.artifacts.PSObject.Properties[$ArtifactId]
    if (-not $artifactProperty) {
        throw ('Download manifest does not define artifact: {0}' -f $ArtifactId)
    }

    $artifact = $artifactProperty.Value
    $artifact | Add-Member -NotePropertyName id -NotePropertyValue $ArtifactId -Force
    return $artifact
}

function Test-FileSha256 {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [string]$ExpectedHash
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($ExpectedHash)) {
        return $true
    }

    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    return ($actual -eq $ExpectedHash.ToUpperInvariant())
}

function Invoke-WebDownload {
    param(
        [Parameter(Mandatory)]
        [string]$Url,
        [Parameter(Mandatory)]
        [string]$Destination
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'

    try {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
    }
    catch {
        $client = New-Object System.Net.WebClient
        try {
            $client.DownloadFile($Url, $Destination)
        }
        finally {
            $client.Dispose()
        }
    }
}

function Get-ArtifactSources {
    param(
        [Parameter(Mandatory)]
        [object]$Artifact,
        [Parameter(Mandatory)]
        [object]$Profile
    )

    $tokens = Get-InstallerTokens -Profile $Profile
    $sources = @()
    foreach ($source in @($Artifact.sources)) {
        $enabled = $true
        if (($source.PSObject.Properties.Name -contains 'enabled') -and $null -ne $source.enabled) {
            $enabled = [bool]$source.enabled
        }

        if (-not $enabled) {
            continue
        }

        $priority = if (($source.PSObject.Properties.Name -contains 'priority') -and $null -ne $source.priority) { [int]$source.priority } else { 100 }
        $url = Expand-TemplateString -Value $source.url -Tokens $tokens
        $sources += [pscustomobject]@{
            id       = $(if (($source.PSObject.Properties.Name -contains 'id') -and $source.id) { $source.id } else { 'source' })
            kind     = $(if (($source.PSObject.Properties.Name -contains 'kind') -and $source.kind) { $source.kind } else { 'mirror' })
            url      = $url
            priority = $priority
        }
    }

    return @($sources | Sort-Object priority, id)
}

function Invoke-ArtifactAcquire {
    param(
        [Parameter(Mandatory)]
        [object]$Profile,
        [Parameter(Mandatory)]
        [string]$ArtifactId,
        [switch]$Force
    )

    if (-not $Profile.resolvedPaths.downloadCacheRoot) {
        return [pscustomobject]@{
            success    = $false
            localPath  = $null
            artifactId = $ArtifactId
            sourceId   = $null
            summary    = 'No download cache root is configured.'
            attempts   = @()
        }
    }

    $manifest = Get-DownloadManifest -Profile $Profile
    if (-not $manifest) {
        return [pscustomobject]@{
            success    = $false
            localPath  = $null
            artifactId = $ArtifactId
            sourceId   = $null
            summary    = 'No download manifest is configured.'
            attempts   = @()
        }
    }

    $artifact = Get-ArtifactDefinition -Manifest $manifest -ArtifactId $ArtifactId
    Ensure-Directory -Path $Profile.resolvedPaths.downloadCacheRoot | Out-Null

    $fileName = if (($artifact.PSObject.Properties.Name -contains 'fileName') -and $artifact.fileName) { $artifact.fileName } else { $ArtifactId }
    $cachePath = Join-Path -Path $Profile.resolvedPaths.downloadCacheRoot -ChildPath $fileName

    if (-not $Force -and (Test-FileSha256 -Path $cachePath -ExpectedHash $artifact.sha256)) {
        return [pscustomobject]@{
            success    = $true
            localPath  = $cachePath
            artifactId = $ArtifactId
            sourceId   = 'cache'
            summary    = ('Reusing verified cache file: {0}' -f $cachePath)
            attempts   = @()
        }
    }

    if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
        Remove-Item -LiteralPath $cachePath -Force
    }

    $attempts = New-Object System.Collections.Generic.List[object]
    foreach ($source in (Get-ArtifactSources -Artifact $artifact -Profile $Profile)) {
        $tempPath = '{0}.partial' -f $cachePath
        if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
            Remove-Item -LiteralPath $tempPath -Force
        }

        Write-DownloadTrace -Message ('Attempting artifact download: {0}' -f $ArtifactId) -Data @{ source = $source }

        try {
            Invoke-WebDownload -Url $source.url -Destination $tempPath
            if (-not (Test-FileSha256 -Path $tempPath -ExpectedHash $artifact.sha256)) {
                $attempts.Add([pscustomobject]@{
                    sourceId = $source.id
                    url      = $source.url
                    success  = $false
                    error    = 'SHA256 validation failed'
                })
                Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
                continue
            }

            Move-Item -LiteralPath $tempPath -Destination $cachePath -Force
            return [pscustomobject]@{
                success    = $true
                localPath  = $cachePath
                artifactId = $ArtifactId
                sourceId   = $source.id
                summary    = ('Downloaded {0} to {1}' -f $ArtifactId, $cachePath)
                attempts   = [object[]]$attempts.ToArray()
            }
        }
        catch {
            $attempts.Add([pscustomobject]@{
                sourceId = $source.id
                url      = $source.url
                success  = $false
                error    = $_.Exception.Message
            })
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }

    return [pscustomobject]@{
        success    = $false
        localPath  = $null
        artifactId = $ArtifactId
        sourceId   = $null
        summary    = ('Failed to download artifact: {0}' -f $ArtifactId)
        attempts   = [object[]]$attempts.ToArray()
    }
}

function Get-ArtifactDownloadPath {
    param(
        [Parameter(Mandatory)]
        [object]$Profile,
        [Parameter(Mandatory)]
        [string]$ArtifactId
    )

    return Invoke-ArtifactAcquire -Profile $Profile -ArtifactId $ArtifactId
}

Export-ModuleMember -Function *