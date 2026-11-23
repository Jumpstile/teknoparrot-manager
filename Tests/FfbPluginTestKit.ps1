# Shared fixtures for the force feedback plugin tests. Dot-source it from a BeforeAll.
# A fake release ZIP (one folder per game, like the real plugin release) and the fake "download" that returns it.
# No network and no real plugin files are used.

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# A tiny file that reads as a 32-bit or 64-bit Windows program (the real header fields only).
function New-FfbTestPe {
    param([string]$Arch = 'x64')
    $bytes = New-Object byte[] 256
    $bytes[0] = 0x4D; $bytes[1] = 0x5A; $bytes[0x3C] = 0x80
    $bytes[0x80] = 0x50; $bytes[0x81] = 0x45
    $machine = if ($Arch -eq 'x86') { 0x014C } else { 0x8664 }
    $bytes[0x84] = ($machine -band 255); $bytes[0x85] = ($machine -shr 8)
    return , $bytes
}

# Writes a release-shaped ZIP. $Games is name -> anything (the folder names). Each folder gets dinput8.dll, SDL2.dll and
# FFBPlugin.ini unless left out. $IniText is the settings text every game gets (it names the game so ZIPs differ per game).
function New-FfbTestZip {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Games,
        [string[]]$OmitIniFor = @(), [string[]]$OmitDllFor = @(), [string[]]$OmitSdlFor = @(),
        [string[]]$ExtraEntryNames = @(), [string]$Arch = 'x64', [string]$IniText = '', [string[]]$ExtraGames = @()
    )
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path))
    $archive = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $add = {
            param([string]$Name, [byte[]]$Bytes)
            $entry = $archive.CreateEntry($Name)
            $stream = $entry.Open()
            try { $stream.Write($Bytes, 0, $Bytes.Length) } finally { $stream.Dispose() }
        }
        foreach ($game in (@($Games.Keys) + @($ExtraGames))) {
            if ($OmitDllFor -notcontains $game) { & $add ($game + '/dinput8.dll') (New-FfbTestPe -Arch $Arch) }
            if ($OmitSdlFor -notcontains $game) { & $add ($game + '/SDL2.dll') ([System.Text.Encoding]::ASCII.GetBytes('sdl2-' + $game)) }
            if ($OmitIniFor -notcontains $game) {
                $text = if ($IniText) { $IniText } else { "[Settings]`r`nGameId=7`r`nDeviceGUID=`r`nGame=$game`r`n" }
                & $add ($game + '/FFBPlugin.ini') ([System.Text.Encoding]::ASCII.GetBytes($text))
            }
        }
        foreach ($name in $ExtraEntryNames) { & $add $name ([System.Text.Encoding]::ASCII.GetBytes('x')) }
    } finally { $archive.Dispose() }
}

# A release as Get-FFBPluginLatestRelease returns it.
function New-FfbTestRelease {
    param([string]$Tag = 'v.9.9.9.9', [string]$Sha256 = '')
    return [pscustomobject]@{
        Revision = $Tag; Repository = 'fixture/FFBArcadePlugin'; ManifestUrl = 'https://api.github.com/repos/fixture/FFBArcadePlugin/releases/latest'
        Trust = $(if ($Sha256) { 'ReleaseDigestVerified' } else { 'ReleaseNoDigest' })
        AssetName = 'FFB.Arcade.Plugin.test.zip'
        AssetUrl = 'https://github.com/mightymikem/FFBArcadePlugin/releases/download/test/FFB.Arcade.Plugin.test.zip'
        Sha256 = $(if ($Sha256) { $Sha256 } else { $null }); Bytes = 0; FromCache = $false
    }
}

# What Invoke-FFBPluginDownload returns, with a ZIP that has a folder for every game in the (mocked) support table.
function New-FFBDownloadFixtureResult {
    param([string]$destDir, [object]$Release, [hashtable]$ZipOptions = @{})
    [void][System.IO.Directory]::CreateDirectory($destDir)
    $map = Get-FFBPluginGameMap -SourceRevision ([string]$Release.Revision)
    $zip = Join-Path $destDir ('TPM-FFB-Plugin-Release.{0}.zip' -f [guid]::NewGuid().ToString('N'))
    New-FfbTestZip -Path $zip -Games $map @ZipOptions
    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    return [pscustomobject]@{
        Succeeded = $true; ZipPath = $zip; Staged = $true; Sha256 = $hash
        Evidence = @([pscustomobject]@{ FileName = 'FFB.Arcade.Plugin.test.zip'; SourceUrl = 'https://x'; SourceRevision = [string]$Release.Revision; Sha256 = $hash; Trust = 'ReleaseDigestVerified'; DigestChecked = $true; DownloadPath = $zip })
        ResiduePaths = @(); Reason = $null
    }
}
