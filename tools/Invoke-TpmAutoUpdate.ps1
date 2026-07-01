# =============================================================================
# TeknoParrot Manager backup-first updater helper
# =============================================================================
# This helper intentionally stays separate from TeknoParrot-Manager.ps1 for the
# first implementation pass so it can be reviewed and tested before being wired
# into the main menu. It never runs silently and never updates without -Apply.
#
# Orchestration only -- the testable logic lives in TpmAutoUpdate.Core.psm1.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$CheckOnly,
    [switch]$Apply,
    [string]$ScriptPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'TeknoParrot-Manager.ps1'),
    [string]$Owner = 'Jumpstile',
    [string]$Repository = 'teknoparrot-manager',
    [string]$AssetNamePattern = '^TeknoParrot\.Manager\.v.*\.zip$',
    [string]$ScriptEntryName = 'TeknoParrot-Manager.ps1'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'TpmAutoUpdate.Core.psm1') -Force

function Write-UpdaterInfo {
    param([string]$Message)
    Write-Host "[TPM updater] $Message"
}

Enable-TpmTls12

if (-not $CheckOnly -and -not $Apply) {
    $CheckOnly = $true
}

$localVersionText = Get-TpmLocalVersion -Path $ScriptPath
$localVersion = ConvertTo-TpmVersion -VersionText $localVersionText
$release = Get-LatestRelease -Owner $Owner -Repository $Repository
$latestVersionText = ($release.tag_name -replace '^v', '').Trim()
$latestVersion = ConvertTo-TpmVersion -VersionText $latestVersionText

Write-UpdaterInfo "Local version : $localVersionText"
Write-UpdaterInfo "Latest release: $($release.tag_name)"

if ($latestVersion -le $localVersion) {
    Write-UpdaterInfo 'Already current. No update needed.'
    return
}

$asset = Select-TpmUpdateAsset -Release $release -Pattern $AssetNamePattern -Owner $Owner -Repository $Repository
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

    $downloadedZipPath = $null
    $extractedScriptPath = $null
    try {
        $backupPath = New-TpmUpdateBackup -Path $ScriptPath
        Write-UpdaterInfo "Backup created : $backupPath"

        $downloadedZipPath = Save-TpmReleaseAsset -Asset $asset
        Write-UpdaterInfo "Downloaded     : $downloadedZipPath"

        $extractedScriptPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-update-extracted-" + [guid]::NewGuid().ToString('N') + '.ps1')
        Expand-TpmReleaseZipEntry -ZipPath $downloadedZipPath -EntryName $ScriptEntryName -DestinationPath $extractedScriptPath | Out-Null
        Write-UpdaterInfo "Extracted      : $extractedScriptPath"

        Test-TpmExtractedScript -Path $extractedScriptPath | Out-Null
        Write-UpdaterInfo 'Extracted script passed content validation.'

        Move-Item -LiteralPath $extractedScriptPath -Destination $ScriptPath -Force
        $extractedScriptPath = $null

        Write-UpdaterInfo 'Update installed successfully.'
        Write-UpdaterInfo 'Restart TeknoParrot Manager to run the new version.'
    } finally {
        if ($downloadedZipPath -and (Test-Path -LiteralPath $downloadedZipPath -PathType Leaf)) {
            Remove-Item -LiteralPath $downloadedZipPath -Force -ErrorAction SilentlyContinue
        }
        if ($extractedScriptPath -and (Test-Path -LiteralPath $extractedScriptPath -PathType Leaf)) {
            Remove-Item -LiteralPath $extractedScriptPath -Force -ErrorAction SilentlyContinue
        }
    }
}
