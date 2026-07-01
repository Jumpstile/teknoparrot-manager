# =============================================================================
# TeknoParrot Manager backup-first updater helper
# =============================================================================
# This helper intentionally stays separate from TeknoParrot-Manager.ps1 for the
# first implementation pass so it can be reviewed and tested before being wired
# into the main menu. It never runs silently and never updates without -Apply.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$CheckOnly,
    [switch]$Apply,
    [string]$ScriptPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'TeknoParrot-Manager.ps1'),
    [string]$Owner = 'Jumpstile',
    [string]$Repository = 'teknoparrot-manager',
    [string]$AssetNamePattern = '^TeknoParrot-Manager\.ps1$'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-UpdaterInfo {
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

function ConvertTo-VersionObject {
    param([string]$VersionText)

    $normalized = ($VersionText -replace '^v', '').Trim()
    try {
        return [version]$normalized
    } catch {
        throw "Version '$VersionText' is not a valid System.Version value after normalization."
    }
}

function Invoke-GitHubJsonRequest {
    param([string]$Uri)

    $headers = @{ 'User-Agent' = 'TeknoParrot-Manager-Updater' }
    return Invoke-RestMethod -Uri $Uri -Headers $headers -UseBasicParsing
}

function Get-LatestRelease {
    param([string]$Owner, [string]$Repository)

    $uri = "https://api.github.com/repos/$Owner/$Repository/releases/latest"
    return Invoke-GitHubJsonRequest -Uri $uri
}

function Select-UpdateAsset {
    param($Release, [string]$Pattern, [string]$Owner, [string]$Repository)

    $asset = @($Release.assets | Where-Object { $_.name -match $Pattern } | Select-Object -First 1)
    if (-not $asset) {
        throw "Latest release '$($Release.tag_name)' does not contain an asset matching $Pattern"
    }

    $safePrefix = "https://github.com/$Owner/$Repository/releases/download/"
    if ($asset.browser_download_url -notlike "$safePrefix*") {
        throw "Refusing non-release GitHub asset URL: $($asset.browser_download_url)"
    }

    return $asset
}

function New-UpdateBackup {
    param([string]$Path)

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

function Save-ReleaseAsset {
    param($Asset)

    $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-update-" + [guid]::NewGuid().ToString('N') + '.ps1')
    Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $tempPath -UseBasicParsing

    $downloaded = Get-Item -LiteralPath $tempPath -ErrorAction Stop
    if ($downloaded.Length -le 0) {
        throw "Downloaded update asset is empty: $tempPath"
    }

    return $tempPath
}

function Install-DownloadedUpdate {
    param([string]$DownloadedPath, [string]$TargetPath)

    $targetDir = Split-Path -Parent $TargetPath
    if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
        throw "Target directory does not exist: $targetDir"
    }

    Move-Item -LiteralPath $DownloadedPath -Destination $TargetPath -Force
}

if (-not $CheckOnly -and -not $Apply) {
    $CheckOnly = $true
}

$localVersionText = Get-LocalTpmVersion -Path $ScriptPath
$localVersion = ConvertTo-VersionObject -VersionText $localVersionText
$release = Get-LatestRelease -Owner $Owner -Repository $Repository
$latestVersionText = ($release.tag_name -replace '^v', '').Trim()
$latestVersion = ConvertTo-VersionObject -VersionText $latestVersionText

Write-UpdaterInfo "Local version : $localVersionText"
Write-UpdaterInfo "Latest release: $($release.tag_name)"

if ($latestVersion -le $localVersion) {
    Write-UpdaterInfo 'Already current. No update needed.'
    return
}

$asset = Select-UpdateAsset -Release $release -Pattern $AssetNamePattern -Owner $Owner -Repository $Repository
Write-UpdaterInfo "Update available: $localVersionText -> $($release.tag_name)"
Write-UpdaterInfo "Selected asset  : $($asset.name)"

if ($CheckOnly -and -not $Apply) {
    Write-UpdaterInfo 'Check only. Re-run with -Apply to update.'
    return
}

if ($Apply) {
    if (-not $PSCmdlet.ShouldProcess($ScriptPath, "replace with $($release.tag_name)")) {
        return
    }

    $downloadedPath = $null
    try {
        $backupPath = New-UpdateBackup -Path $ScriptPath
        Write-UpdaterInfo "Backup created : $backupPath"

        $downloadedPath = Save-ReleaseAsset -Asset $asset
        Write-UpdaterInfo "Downloaded     : $downloadedPath"

        Install-DownloadedUpdate -DownloadedPath $downloadedPath -TargetPath $ScriptPath
        $downloadedPath = $null

        Write-UpdaterInfo 'Update installed successfully.'
        Write-UpdaterInfo 'Restart TeknoParrot Manager to run the new version.'
    } finally {
        if ($downloadedPath -and (Test-Path -LiteralPath $downloadedPath -PathType Leaf)) {
            Remove-Item -LiteralPath $downloadedPath -Force -ErrorAction SilentlyContinue
        }
    }
}
