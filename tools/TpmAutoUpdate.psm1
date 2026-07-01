Set-StrictMode -Version 2.0

function Set-TpmUpdaterTls12 {
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }
}

function Write-TpmUpdaterInfo {
    param([string]$Message)
    Write-Host "[TPM updater] $Message"
}

function Get-LocalTpmVersion {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "TeknoParrot Manager script not found: $Path"
    }

    $match = Select-String -LiteralPath $Path -Pattern '^\s*\$ScriptVersion\s*=\s*"(?<version>[^"]+)"' -ErrorAction Stop | Select-Object -First 1
    if (-not $match) {
        throw "Could not find `$ScriptVersion in $Path"
    }

    return $match.Matches[0].Groups['version'].Value
}

function ConvertTo-TpmVersionObject {
    param([string]$VersionText)

    $normalized = ($VersionText -replace '^v', '').Trim()
    try {
        return [version]$normalized
    } catch {
        throw "Version '$VersionText' is not a valid System.Version value after normalization."
    }
}

function Invoke-TpmGitHubJsonRequest {
    param([string]$Uri)

    Set-TpmUpdaterTls12
    $headers = @{ 'User-Agent' = 'TeknoParrot-Manager-Updater' }
    return Invoke-RestMethod -Uri $Uri -Headers $headers -UseBasicParsing
}

function Get-LatestTpmRelease {
    param([string]$Owner, [string]$Repository)

    $uri = "https://api.github.com/repos/$Owner/$Repository/releases/latest"
    return Invoke-TpmGitHubJsonRequest -Uri $uri
}

function Test-TpmReleaseAssetUrl {
    param([string]$Url, [string]$Owner, [string]$Repository)

    try {
        $uri = [uri]$Url
    } catch {
        return $false
    }

    if ($uri.Scheme -ne 'https') { return $false }
    if ($uri.Host -ne 'github.com') { return $false }

    $expectedPrefix = "/$Owner/$Repository/releases/download/"
    return $uri.AbsolutePath.StartsWith($expectedPrefix, [System.StringComparison]::Ordinal)
}

function Select-TpmUpdateAsset {
    param($Release, [string]$Pattern, [string]$Owner, [string]$Repository)

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
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "TeknoParrot Manager script not found: $Path"
    }

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
    param($Asset)

    Set-TpmUpdaterTls12
    $extension = [System.IO.Path]::GetExtension($Asset.name)
    if (-not $extension) { $extension = '.download' }

    $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-update-" + [guid]::NewGuid().ToString('N') + $extension)
    Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $tempPath -UseBasicParsing

    $downloaded = Get-Item -LiteralPath $tempPath -ErrorAction Stop
    if ($downloaded.Length -le 0) {
        throw "Downloaded update asset is empty: $tempPath"
    }

    return $tempPath
}

function Test-TpmUpdateScriptContent {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }

    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file.Length -le 0) { return $false }

    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0x50 -and $bytes[1] -eq 0x4B) {
        return $false
    }

    $content = Get-Content -LiteralPath $file.FullName -Raw
    if ($content -notmatch 'TeknoParrot Manager') { return $false }
    if ($content -notmatch '\$ScriptVersion\s*=\s*"[^"]+"') { return $false }

    return $true
}

function Expand-TpmUpdateScriptFromZip {
    param([string]$ZipPath)

    $extractPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-extract-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

    try {
        Expand-Archive -LiteralPath $ZipPath -DestinationPath $extractPath -Force
        $candidate = @(Get-ChildItem -LiteralPath $extractPath -Recurse -File -Filter 'TeknoParrot-Manager.ps1' | Select-Object -First 1)
        if (-not $candidate) {
            throw "Downloaded update zip does not contain TeknoParrot-Manager.ps1"
        }

        if (-not (Test-TpmUpdateScriptContent -Path $candidate.FullName)) {
            throw "Extracted TeknoParrot-Manager.ps1 failed validation."
        }

        $scriptPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-update-script-" + [guid]::NewGuid().ToString('N') + '.ps1')
        Copy-Item -LiteralPath $candidate.FullName -Destination $scriptPath -Force
        return $scriptPath
    } finally {
        if (Test-Path -LiteralPath $extractPath) {
            Remove-Item -LiteralPath $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-TpmValidatedUpdateScript {
    param([string]$DownloadedPath)

    $extension = [System.IO.Path]::GetExtension($DownloadedPath)
    if ($extension -ieq '.zip') {
        return Expand-TpmUpdateScriptFromZip -ZipPath $DownloadedPath
    }

    if ($extension -ieq '.ps1') {
        if (-not (Test-TpmUpdateScriptContent -Path $DownloadedPath)) {
            throw "Downloaded TeknoParrot-Manager.ps1 failed validation."
        }
        return $DownloadedPath
    }

    throw "Unsupported update asset extension: $extension"
}

function Install-TpmDownloadedUpdate {
    param([string]$UpdateScriptPath, [string]$TargetPath)

    $targetDir = Split-Path -Parent $TargetPath
    if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
        throw "Target directory does not exist: $targetDir"
    }

    if (-not (Test-TpmUpdateScriptContent -Path $UpdateScriptPath)) {
        throw "Update script failed validation before replacement."
    }

    Move-Item -LiteralPath $UpdateScriptPath -Destination $TargetPath -Force
}

function Invoke-TpmAutoUpdate {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$CheckOnly,
        [switch]$Apply,
        [string]$ScriptPath,
        [string]$Owner,
        [string]$Repository,
        [string]$AssetNamePattern
    )

    if (-not $CheckOnly -and -not $Apply) {
        $CheckOnly = $true
    }

    $localVersionText = Get-LocalTpmVersion -Path $ScriptPath
    $localVersion = ConvertTo-TpmVersionObject -VersionText $localVersionText
    $release = Get-LatestTpmRelease -Owner $Owner -Repository $Repository
    $latestVersionText = ($release.tag_name -replace '^v', '').Trim()
    $latestVersion = ConvertTo-TpmVersionObject -VersionText $latestVersionText

    Write-TpmUpdaterInfo "Local version : $localVersionText"
    Write-TpmUpdaterInfo "Latest release: $($release.tag_name)"

    if ($latestVersion -le $localVersion) {
        Write-TpmUpdaterInfo 'Already current. No update needed.'
        return
    }

    $asset = Select-TpmUpdateAsset -Release $release -Pattern $AssetNamePattern -Owner $Owner -Repository $Repository
    Write-TpmUpdaterInfo "Update available: $localVersionText -> $($release.tag_name)"
    Write-TpmUpdaterInfo "Selected asset  : $($asset.name)"

    if ($CheckOnly -and -not $Apply) {
        Write-TpmUpdaterInfo 'Check only. Re-run with -Apply to update.'
        return
    }

    if ($Apply) {
        if (-not $PSCmdlet.ShouldProcess($ScriptPath, "replace with $($release.tag_name)")) {
            return
        }

        $downloadedPath = $null
        $validatedScriptPath = $null
        try {
            $backupPath = New-TpmUpdateBackup -Path $ScriptPath
            Write-TpmUpdaterInfo "Backup created : $backupPath"

            $downloadedPath = Save-TpmReleaseAsset -Asset $asset
            Write-TpmUpdaterInfo "Downloaded     : $downloadedPath"

            $validatedScriptPath = Get-TpmValidatedUpdateScript -DownloadedPath $downloadedPath
            Install-TpmDownloadedUpdate -UpdateScriptPath $validatedScriptPath -TargetPath $ScriptPath
            $validatedScriptPath = $null

            Write-TpmUpdaterInfo 'Update installed successfully.'
            Write-TpmUpdaterInfo 'Restart TeknoParrot Manager to run the new version.'
        } finally {
            if ($downloadedPath -and (Test-Path -LiteralPath $downloadedPath -PathType Leaf)) {
                Remove-Item -LiteralPath $downloadedPath -Force -ErrorAction SilentlyContinue
            }
            if ($validatedScriptPath -and (Test-Path -LiteralPath $validatedScriptPath -PathType Leaf)) {
                Remove-Item -LiteralPath $validatedScriptPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Export-ModuleMember -Function @(
    'Set-TpmUpdaterTls12',
    'Write-TpmUpdaterInfo',
    'Get-LocalTpmVersion',
    'ConvertTo-TpmVersionObject',
    'Invoke-TpmGitHubJsonRequest',
    'Get-LatestTpmRelease',
    'Test-TpmReleaseAssetUrl',
    'Select-TpmUpdateAsset',
    'New-TpmUpdateBackup',
    'Save-TpmReleaseAsset',
    'Test-TpmUpdateScriptContent',
    'Expand-TpmUpdateScriptFromZip',
    'Get-TpmValidatedUpdateScript',
    'Install-TpmDownloadedUpdate',
    'Invoke-TpmAutoUpdate'
)
