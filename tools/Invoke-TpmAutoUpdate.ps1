# =============================================================================
# TeknoParrot Manager backup-first updater helper
# =============================================================================
# This helper intentionally stays separate from TeknoParrot-Manager.ps1 for the
# first implementation pass so it can be reviewed and tested before being wired
# into the main menu. It never runs silently and never updates without -Apply.
#
# Orchestration only -- the testable logic lives in TpmAutoUpdate.Core.psm1.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Console updater helper intentionally writes concise status lines to the interactive host.')]
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

# No -Force: this must not clobber an already-loaded instance of the module.
# A future caller (e.g. the main menu, once this is wired in) may import the
# module once for a long-running session; reloading it here on every
# invocation would also defeat that caller's ability to mock or otherwise
# control it (observed directly: an earlier version of this line broke
# Pester's -ModuleName mocking of the destructive-path test suite).
$modulePath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'TpmAutoUpdate.Core.psm1')).ProviderPath
$loadedModule = Get-Module TpmAutoUpdate.Core -All |
    Where-Object { $_.Path -eq $modulePath } |
    Select-Object -First 1
if (-not $loadedModule) {
    Import-Module $modulePath
}

function Write-UpdaterInfo {
    param([string]$Message)
    Write-Host "[TeknoParrot Manager updater] $Message"
}

Enable-TpmTls12

if (-not $CheckOnly -and -not $Apply) {
    $CheckOnly = $true
}

$localVersionText = Get-TpmLocalVersion -Path $ScriptPath
$release = Get-LatestRelease -Owner $Owner -Repository $Repository
$latestVersionText = [string]$release.tag_name
$versionComparison = Compare-TpmVersions -VersionTextA $localVersionText -VersionTextB $latestVersionText

Write-UpdaterInfo "Installed TeknoParrot Manager version: $localVersionText"
Write-UpdaterInfo "Latest TeknoParrot Manager release   : $($release.tag_name)"

if ($versionComparison -ge 0) {
    Write-UpdaterInfo 'Already current. No update needed.'
    return
}

$asset = Select-TpmUpdateAsset -Release $release -Pattern $AssetNamePattern -Owner $Owner -Repository $Repository
Write-UpdaterInfo "Update available: $localVersionText -> $($release.tag_name)"
Write-UpdaterInfo "Selected asset  : $($asset.name)"

if ($CheckOnly -and -not $Apply) {
    Write-UpdaterInfo 'Check only. -Apply replaces only TeknoParrot-Manager.ps1 and refuses release packages that contain other files.'
    Write-UpdaterInfo 'To install a complete release, start TeknoParrot Manager and choose 16 (Check for Updates). It installs the whole release with a backup.'
    return
}

if ($Apply) {
    if (-not $PSCmdlet.ShouldProcess($ScriptPath, "replace with $($release.tag_name)")) {
        return
    }

    $downloadedZipPath = $null
    $extractedScriptPath = $null
    try {
        $downloadedZipPath = Save-TpmReleaseAsset -Asset $asset
        Write-UpdaterInfo "Downloaded     : $downloadedZipPath"

        # The in-place updater can only replace the main script. Refuse a
        # multi-file release package before anything is probed, backed up,
        # extracted or replaced, so a refusal changes nothing on disk.
        $packageCheck = Test-TpmUpdatePackageIsSingleScript -ZipPath $downloadedZipPath -EntryName $ScriptEntryName
        if (-not $packageCheck.SingleScript -and $packageCheck.ExtraEntryCount -eq 0) {
            $emptyMessage = "This release does not contain $ScriptEntryName, so nothing was installed. Try again later, or see https://github.com/$Owner/$Repository/releases."
            Write-UpdaterInfo $emptyMessage
            throw $emptyMessage
        }
        if (-not $packageCheck.SingleScript) {
            $refusalMessage = "This release is a multi-file package. This tool replaces only TeknoParrot-Manager.ps1, so nothing was installed. To install the whole release safely, start TeknoParrot Manager and choose 16 (Check for Updates), or answer Y to the update question when it starts. It backs up every file it replaces and puts everything back if anything goes wrong. Release page: https://github.com/$Owner/$Repository/releases"
            Write-UpdaterInfo $refusalMessage
            Write-UpdaterInfo ("Package contains {0} other file(s), for example: {1}" -f $packageCheck.ExtraEntryCount, (@($packageCheck.ExtraEntrySample) -join ', '))
            throw $refusalMessage
        }

        Assert-TpmWritableTarget -Path $ScriptPath
        $backupPath = New-TpmUpdateBackup -Path $ScriptPath
        Write-UpdaterInfo "Backup created : $backupPath"

        # Stage beside the script (same volume) so the final Move-Item is one rename, never a copy-then-delete.
        # Resolve against the PowerShell location: .NET GetFullPath would use the process folder, which Set-Location does not change.
        $scriptFolder = Split-Path -Parent (Resolve-Path -LiteralPath $ScriptPath).ProviderPath
        $extractedScriptPath = Join-Path $scriptFolder ("tpm-update-extracted-" + [guid]::NewGuid().ToString('N') + '.ps1')
        Expand-TpmReleaseZipEntry -ZipPath $downloadedZipPath -EntryName $ScriptEntryName -DestinationPath $extractedScriptPath | Out-Null
        Write-UpdaterInfo "Extracted      : $extractedScriptPath"

        Test-TpmExtractedScript -Path $extractedScriptPath -ExpectedVersion $latestVersionText | Out-Null
        Write-UpdaterInfo 'Extracted script passed content and release-version validation.'

        $expectedHash = (Get-FileHash -LiteralPath $extractedScriptPath -Algorithm SHA256 -ErrorAction Stop).Hash
        Move-Item -LiteralPath $extractedScriptPath -Destination $ScriptPath -Force -ErrorAction Stop
        $installedHash = if (Test-Path -LiteralPath $ScriptPath -PathType Leaf) { (Get-FileHash -LiteralPath $ScriptPath -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash } else { $null }
        if ($installedHash -cne $expectedHash) {
            # The old file is still there or the copy is incomplete: put the backup back, check it, and say what really happened.
            $restored = $false
            try {
                Copy-Item -LiteralPath $backupPath -Destination $ScriptPath -Force -ErrorAction Stop
                $restored = ((Get-FileHash -LiteralPath $ScriptPath -Algorithm SHA256 -ErrorAction Stop).Hash -ceq (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256 -ErrorAction Stop).Hash)
            } catch { $restored = $false }
            if ($restored) { throw "Update replacement did not complete: $ScriptPath does not match the downloaded release. The previous version was restored from $backupPath." }
            throw "Update replacement did not complete: $ScriptPath does not match the downloaded release, and the previous version could not be put back. Copy $backupPath over $ScriptPath to get it back."
        }
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
