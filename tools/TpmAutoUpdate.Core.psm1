# =============================================================================
# TeknoParrot Manager updater helper functions
# =============================================================================
# Pure/testable logic for tools/Invoke-TpmAutoUpdate.ps1, split out so Pester
# can import and exercise it without triggering the orchestrator's top-level
# network calls. Importing this module has no side effects.

# A module's $ErrorActionPreference is snapshotted from the caller's scope at
# *import* time, not read live from the current caller on every call. If this
# module is already loaded (e.g. by a test harness, or a future long-running
# host) with a looser preference, a plain `Import-Module` (without -Force, as
# the orchestrator intentionally uses -- see its own comment) is a no-op and
# never re-snapshots it. Cmdlet calls in this module (Copy-Item, New-Item,
# etc.) must fail closed on error regardless of that history, so set it
# explicitly here rather than depending on inheritance. (Found via destructive
# -path testing on the ChannelForge sibling module: a locked destination file
# during a Copy-Item call silently produced a non-terminating error and
# reported "success" until this was added there; applied here defensively for
# the same reason, since New-TpmUpdateBackup's Copy-Item has the same shape.)
$ErrorActionPreference = 'Stop'

function Get-TpmLocalVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "TeknoParrot Manager script not found: $Path"
    }

    $match = Select-String -LiteralPath $Path -Pattern '^\s*\$ScriptVersion\s*=\s*"(?<version>[^"]+)"' -ErrorAction Stop | Select-Object -First 1
    if (-not $match) {
        throw "Could not find `$ScriptVersion in $Path"
    }

    return $match.Matches[0].Groups['version'].Value
}

function ConvertTo-TpmVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VersionText
    )

    $normalized = ($VersionText -replace '^v', '').Trim()
    try {
        return [version]$normalized
    } catch {
        throw "Version '$VersionText' is not a valid System.Version value after normalization."
    }
}

function Test-TpmReleaseAssetUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$Owner,

        [Parameter(Mandatory)]
        [string]$Repository
    )

    # URI-parsed validation (not string -like/prefix matching) so the host
    # check inspects the actual parsed authority, not a substring of the raw
    # URL text. Rejects userinfo tricks (https://github.com@evil.com/...) and
    # lookalike hosts (https://github.com.evil.com/...) that a naive -like
    # prefix check could be fooled by.
    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $false
    }

    $parsedUri = $null
    if (-not [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$parsedUri)) {
        return $false
    }

    if ($parsedUri.Scheme -ne 'https') {
        return $false
    }

    if ($parsedUri.Host -ne 'github.com') {
        return $false
    }

    if (-not [string]::IsNullOrEmpty($parsedUri.UserInfo)) {
        return $false
    }

    $expectedPrefix = "/$Owner/$Repository/releases/download/"
    return $parsedUri.AbsolutePath.StartsWith($expectedPrefix, [System.StringComparison]::Ordinal)
}

function Invoke-GitHubJsonRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri
    )

    $headers = @{ 'User-Agent' = 'TeknoParrot-Manager-Updater' }
    return Invoke-RestMethod -Uri $Uri -Headers $headers -UseBasicParsing
}

function Get-LatestRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Owner,

        [Parameter(Mandatory)]
        [string]$Repository
    )

    $uri = "https://api.github.com/repos/$Owner/$Repository/releases/latest"
    return Invoke-GitHubJsonRequest -Uri $uri
}

function Select-TpmUpdateAsset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Release,

        [Parameter(Mandatory)]
        [string]$Pattern,

        [Parameter(Mandatory)]
        [string]$Owner,

        [Parameter(Mandatory)]
        [string]$Repository
    )

    $asset = @($Release.assets | Where-Object { $_.name -match $Pattern } | Select-Object -First 1)
    if (-not $asset) {
        throw "Latest release '$($Release.tag_name)' does not contain an asset matching $Pattern"
    }

    if (-not (Test-TpmReleaseAssetUrl -Url $asset.browser_download_url -Owner $Owner -Repository $Repository)) {
        throw "Refusing non-release GitHub asset URL: $($asset.browser_download_url)"
    }

    return $asset
}

function New-TpmUpdateBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $repoRoot = Split-Path -Parent $Path
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupDir = Join-Path (Join-Path $repoRoot 'UpdateBackups') $stamp
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

    $backupPath = Join-Path $backupDir (Split-Path -Leaf $Path)
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force

    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        throw "Backup creation failed: $backupPath"
    }

    return $backupPath
}

function Save-TpmReleaseAsset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Asset
    )

    $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-update-" + [guid]::NewGuid().ToString('N') + '.zip')
    Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $tempPath -UseBasicParsing

    $downloaded = Get-Item -LiteralPath $tempPath -ErrorAction Stop
    if ($downloaded.Length -le 0) {
        throw "Downloaded update asset is empty: $tempPath"
    }

    return $tempPath
}

function Expand-TpmReleaseZipEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ZipPath,

        [Parameter(Mandatory)]
        [string]$EntryName,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
        throw "Downloaded release asset not found: $ZipPath"
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -eq $EntryName } | Select-Object -First 1
        if (-not $entry) {
            throw "Release asset '$ZipPath' does not contain expected entry '$EntryName'."
        }

        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $DestinationPath, $true)
    } finally {
        $zip.Dispose()
    }

    return $DestinationPath
}

function Test-TpmExtractedScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    # Defense-in-depth before the extracted file ever replaces the live
    # script: verify it exists, is non-empty, is not the raw zip container
    # (a bug that would move zip bytes over the .ps1 if extraction were ever
    # skipped or broken upstream), and looks like TeknoParrot-Manager.ps1
    # rather than an unrelated or truncated file.
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Extracted script not found: $Path"
    }

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -eq 0) {
        throw "Extracted script is empty: $Path"
    }

    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0x50 -and $bytes[1] -eq 0x4B) {
        throw "Extracted script begins with a zip signature (PK) -- refusing to install: $Path"
    }

    $content = [System.Text.Encoding]::UTF8.GetString($bytes)

    if ($content -notmatch 'TeknoParrot Manager') {
        throw "Extracted script does not contain the expected 'TeknoParrot Manager' marker: $Path"
    }

    if ($content -notmatch '\$ScriptVersion\s*=\s*"[^"]+"') {
        throw "Extracted script does not contain a `$ScriptVersion assignment: $Path"
    }

    return $true
}

function Enable-TpmTls12 {
    [CmdletBinding()]
    param()

    # Windows PowerShell 5.1 on older .NET Framework builds does not always
    # default to TLS 1.2, which causes GitHub API/download calls to fail with
    # "Could not create SSL/TLS secure channel." Only Windows PowerShell needs
    # this; PowerShell 6+ already defaults to modern TLS.
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        return
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {
        Write-Warning "Could not enable TLS 1.2: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function @(
    'Get-TpmLocalVersion',
    'ConvertTo-TpmVersion',
    'Test-TpmReleaseAssetUrl',
    'Invoke-GitHubJsonRequest',
    'Get-LatestRelease',
    'Select-TpmUpdateAsset',
    'New-TpmUpdateBackup',
    'Save-TpmReleaseAsset',
    'Expand-TpmReleaseZipEntry',
    'Test-TpmExtractedScript',
    'Enable-TpmTls12'
)
