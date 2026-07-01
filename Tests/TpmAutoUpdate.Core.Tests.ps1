#Requires -Module Pester

# Regression suite for tools/TpmAutoUpdate.Core.psm1. Unlike
# TeknoParrot-Manager.ps1, this is a real module with no top-level side
# effects, so it can be imported directly without AST surgery.
#
# Run with: Invoke-Pester -Path .\Tests\TpmAutoUpdate.Core.Tests.ps1

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\tools\TpmAutoUpdate.Core.psm1'
    Import-Module $modulePath -Force

    function New-TpmTestRelease {
        param(
            [string]$TagName = 'v0.99.99',
            [string[]]$AssetNames = @('TeknoParrot.Manager.v0.99.99.BETA.zip'),
            [string]$Owner = 'Jumpstile',
            [string]$Repository = 'teknoparrot-manager'
        )

        $assets = foreach ($name in $AssetNames) {
            [pscustomobject]@{
                name                = $name
                browser_download_url = "https://github.com/$Owner/$Repository/releases/download/$TagName/$name"
            }
        }

        [pscustomobject]@{
            tag_name = $TagName
            assets   = @($assets)
        }
    }

    function New-TpmFixtureZip {
        param(
            [Parameter(Mandatory)][string]$DestinationPath,
            [string]$EntryName = 'TeknoParrot-Manager.ps1',
            [string]$EntryContent = "# TeknoParrot Manager`n`$ScriptVersion = `"0.99.99`"`n"
        )

        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $DestinationPath) {
            Remove-Item -LiteralPath $DestinationPath -Force
        }

        $stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-fixture-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
        try {
            $entryPath = Join-Path $stagingDir $EntryName
            Set-Content -LiteralPath $entryPath -Value $EntryContent -Encoding ascii -NoNewline
            [System.IO.Compression.ZipFile]::CreateFromDirectory($stagingDir, $DestinationPath)
        } finally {
            Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        return $DestinationPath
    }
}

Describe 'ConvertTo-TpmVersion' {
    It 'strips a leading v and parses a normal version' {
        ConvertTo-TpmVersion -VersionText 'v0.99.38' | Should -Be ([version]'0.99.38')
    }

    It 'parses a version with no leading v' {
        ConvertTo-TpmVersion -VersionText '0.99.38' | Should -Be ([version]'0.99.38')
    }

    It 'throws on a non-numeric version string' {
        { ConvertTo-TpmVersion -VersionText 'latest' } | Should -Throw
    }

    It 'throws on an empty string' {
        { ConvertTo-TpmVersion -VersionText '' } | Should -Throw
    }
}

Describe 'Get-TpmLocalVersion' {
    It 'reads $ScriptVersion from a script file' {
        $tempScript = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-version-" + [guid]::NewGuid().ToString('N') + '.ps1')
        Set-Content -LiteralPath $tempScript -Value '$ScriptVersion = "0.99.38"' -Encoding ascii
        try {
            Get-TpmLocalVersion -Path $tempScript | Should -Be '0.99.38'
        } finally {
            Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
        }
    }

    It 'throws when the file does not exist' {
        { Get-TpmLocalVersion -Path (Join-Path ([System.IO.Path]::GetTempPath()) 'does-not-exist.ps1') } | Should -Throw
    }

    It 'throws when $ScriptVersion is missing' {
        $tempScript = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-noversion-" + [guid]::NewGuid().ToString('N') + '.ps1')
        Set-Content -LiteralPath $tempScript -Value '# no version here' -Encoding ascii
        try {
            { Get-TpmLocalVersion -Path $tempScript } | Should -Throw
        } finally {
            Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Test-TpmReleaseAssetUrl' {
    It 'accepts a well-formed GitHub release download URL' {
        Test-TpmReleaseAssetUrl -Url 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.38/TeknoParrot.Manager.v0.99.38.BETA.zip' -Owner 'Jumpstile' -Repository 'teknoparrot-manager' | Should -BeTrue
    }

    It 'rejects a non-GitHub host' {
        Test-TpmReleaseAssetUrl -Url 'https://evil.example.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.38/x.zip' -Owner 'Jumpstile' -Repository 'teknoparrot-manager' | Should -BeFalse
    }

    It 'rejects a lookalike host with github.com as a subdomain prefix' {
        Test-TpmReleaseAssetUrl -Url 'https://github.com.evil.example.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.38/x.zip' -Owner 'Jumpstile' -Repository 'teknoparrot-manager' | Should -BeFalse
    }

    It 'rejects embedded userinfo credentials' {
        Test-TpmReleaseAssetUrl -Url 'https://github.com@evil.example.com/releases/download/v0.99.38/x.zip' -Owner 'Jumpstile' -Repository 'teknoparrot-manager' | Should -BeFalse
    }

    It 'rejects http (non-https)' {
        Test-TpmReleaseAssetUrl -Url 'http://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.38/x.zip' -Owner 'Jumpstile' -Repository 'teknoparrot-manager' | Should -BeFalse
    }

    It 'rejects a GitHub URL outside the expected owner/repo/releases/download prefix' {
        Test-TpmReleaseAssetUrl -Url 'https://github.com/SomeoneElse/other-repo/releases/download/v1.0.0/x.zip' -Owner 'Jumpstile' -Repository 'teknoparrot-manager' | Should -BeFalse
    }

    It 'rejects a malformed URL' {
        Test-TpmReleaseAssetUrl -Url 'not a url' -Owner 'Jumpstile' -Repository 'teknoparrot-manager' | Should -BeFalse
    }
}

Describe 'Select-TpmUpdateAsset' {
    It 'selects the asset matching the pattern' {
        $release = New-TpmTestRelease -AssetNames @('TeknoParrot.Manager.v0.99.99.BETA.zip', 'unrelated-file.txt')
        $asset = Select-TpmUpdateAsset -Release $release -Pattern '^TeknoParrot\.Manager\.v.*\.zip$' -Owner 'Jumpstile' -Repository 'teknoparrot-manager'
        $asset.name | Should -Be 'TeknoParrot.Manager.v0.99.99.BETA.zip'
    }

    It 'throws when no asset matches the pattern' {
        $release = New-TpmTestRelease -AssetNames @('unrelated-file.txt')
        { Select-TpmUpdateAsset -Release $release -Pattern '^TeknoParrot\.Manager\.v.*\.zip$' -Owner 'Jumpstile' -Repository 'teknoparrot-manager' } | Should -Throw
    }

    It 'throws when the matching asset URL is not a real GitHub release URL' {
        $release = [pscustomobject]@{
            tag_name = 'v0.99.99'
            assets   = @([pscustomobject]@{
                name                 = 'TeknoParrot.Manager.v0.99.99.BETA.zip'
                browser_download_url = 'https://evil.example.com/TeknoParrot.Manager.v0.99.99.BETA.zip'
            })
        }
        { Select-TpmUpdateAsset -Release $release -Pattern '^TeknoParrot\.Manager\.v.*\.zip$' -Owner 'Jumpstile' -Repository 'teknoparrot-manager' } | Should -Throw
    }
}

Describe 'Get-TpmTrustedAssetDigest' {
    It 'returns the lowercase hex hash from a well-formed digest' {
        $asset = [pscustomobject]@{ name = 'x.zip'; digest = ('sha256:' + ('AB' * 32)) }
        Get-TpmTrustedAssetDigest -Asset $asset | Should -Be ('ab' * 32)
    }

    It 'throws when the digest field is missing' {
        $asset = [pscustomobject]@{ name = 'x.zip'; digest = $null }
        { Get-TpmTrustedAssetDigest -Asset $asset } | Should -Throw '*no GitHub-provided checksum*'
    }

    It 'throws when the digest field is empty' {
        $asset = [pscustomobject]@{ name = 'x.zip'; digest = '' }
        { Get-TpmTrustedAssetDigest -Asset $asset } | Should -Throw '*no GitHub-provided checksum*'
    }

    It 'throws when the digest is not sha256' {
        $asset = [pscustomobject]@{ name = 'x.zip'; digest = 'md5:d41d8cd98f00b204e9800998ecf8427e' }
        { Get-TpmTrustedAssetDigest -Asset $asset } | Should -Throw '*malformed checksum*'
    }

    It 'throws when the digest hex portion is the wrong length' {
        $asset = [pscustomobject]@{ name = 'x.zip'; digest = 'sha256:abcd' }
        { Get-TpmTrustedAssetDigest -Asset $asset } | Should -Throw '*malformed checksum*'
    }

    It 'throws when the digest contains non-hex characters' {
        $asset = [pscustomobject]@{ name = 'x.zip'; digest = ('sha256:' + ('g' * 64)) }
        { Get-TpmTrustedAssetDigest -Asset $asset } | Should -Throw '*malformed checksum*'
    }
}

Describe 'Assert-TpmDownloadIntegrity' {
    It 'does not throw when the computed hash matches' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-hash-ok-" + [guid]::NewGuid().ToString('N') + '.bin')
        Set-Content -LiteralPath $path -Value 'known content' -NoNewline -Encoding ascii
        try {
            $expected = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            { Assert-TpmDownloadIntegrity -Path $path -ExpectedHash $expected } | Should -Not -Throw
        } finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'is case-insensitive when comparing hashes' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-hash-case-" + [guid]::NewGuid().ToString('N') + '.bin')
        Set-Content -LiteralPath $path -Value 'known content' -NoNewline -Encoding ascii
        try {
            $expected = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
            { Assert-TpmDownloadIntegrity -Path $path -ExpectedHash $expected } | Should -Not -Throw
        } finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'throws a specific checksum-mismatch error when the hash does not match' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-hash-bad-" + [guid]::NewGuid().ToString('N') + '.bin')
        Set-Content -LiteralPath $path -Value 'tampered or corrupted content' -NoNewline -Encoding ascii
        try {
            { Assert-TpmDownloadIntegrity -Path $path -ExpectedHash ('0' * 64) } | Should -Throw '*Checksum verification failed*'
        } finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'throws when the file to verify does not exist' {
        { Assert-TpmDownloadIntegrity -Path (Join-Path ([System.IO.Path]::GetTempPath()) 'does-not-exist.zip') -ExpectedHash ('0' * 64) } | Should -Throw
    }
}

Describe 'Assert-TpmWritableTarget' {
    It 'throws a clear, actionable error when the target is read-only' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-ro-" + [guid]::NewGuid().ToString('N') + '.ps1')
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.99.38"' -Encoding ascii
        Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $true
        try {
            { Assert-TpmWritableTarget -Path $path } | Should -Throw '*read-only*'
            { Assert-TpmWritableTarget -Path $path } | Should -Throw "*$path*"
        } finally {
            Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'does not throw when the target is writable' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-rw-" + [guid]::NewGuid().ToString('N') + '.ps1')
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.99.38"' -Encoding ascii
        try {
            { Assert-TpmWritableTarget -Path $path } | Should -Not -Throw
        } finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'does not throw when the target does not exist yet' {
        { Assert-TpmWritableTarget -Path (Join-Path ([System.IO.Path]::GetTempPath()) 'does-not-exist.ps1') } | Should -Not -Throw
    }
}

Describe 'New-TpmUpdateBackup' {
    It 'creates a timestamped backup of the target file' {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-backup-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        $scriptPath = Join-Path $tempDir 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $scriptPath -Value '$ScriptVersion = "0.99.38"' -Encoding ascii
        try {
            $backupPath = New-TpmUpdateBackup -Path $scriptPath
            Test-Path -LiteralPath $backupPath -PathType Leaf | Should -BeTrue
            (Get-Content -LiteralPath $backupPath -Raw) | Should -Match 'ScriptVersion'
        } finally {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'throws if the backup file cannot be verified after copy' {
        { New-TpmUpdateBackup -Path (Join-Path ([System.IO.Path]::GetTempPath()) 'does-not-exist.ps1') } | Should -Throw
    }
}

Describe 'Expand-TpmReleaseZipEntry' {
    It 'extracts the named entry to the destination path' {
        $zipPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-zip-" + [guid]::NewGuid().ToString('N') + '.zip')
        $destPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-extracted-" + [guid]::NewGuid().ToString('N') + '.ps1')
        New-TpmFixtureZip -DestinationPath $zipPath | Out-Null
        try {
            Expand-TpmReleaseZipEntry -ZipPath $zipPath -EntryName 'TeknoParrot-Manager.ps1' -DestinationPath $destPath
            Test-Path -LiteralPath $destPath -PathType Leaf | Should -BeTrue
            (Get-Content -LiteralPath $destPath -Raw) | Should -Match 'ScriptVersion'
        } finally {
            Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $destPath -Force -ErrorAction SilentlyContinue
        }
    }

    It 'throws when the zip does not contain the expected entry' {
        $zipPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-zip-" + [guid]::NewGuid().ToString('N') + '.zip')
        $destPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-extracted-" + [guid]::NewGuid().ToString('N') + '.ps1')
        New-TpmFixtureZip -DestinationPath $zipPath -EntryName 'SomethingElse.ps1' | Out-Null
        try {
            { Expand-TpmReleaseZipEntry -ZipPath $zipPath -EntryName 'TeknoParrot-Manager.ps1' -DestinationPath $destPath } | Should -Throw
        } finally {
            Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Test-TpmExtractedScript' {
    It 'passes a valid extracted script' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-valid-" + [guid]::NewGuid().ToString('N') + '.ps1')
        Set-Content -LiteralPath $path -Value "# TeknoParrot Manager`n`$ScriptVersion = `"0.99.99`"" -Encoding ascii
        try {
            Test-TpmExtractedScript -Path $path | Should -BeTrue
        } finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'throws when the file does not exist' {
        { Test-TpmExtractedScript -Path (Join-Path ([System.IO.Path]::GetTempPath()) 'nope.ps1') } | Should -Throw
    }

    It 'throws when the file is empty' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-empty-" + [guid]::NewGuid().ToString('N') + '.ps1')
        New-Item -ItemType File -Path $path -Force | Out-Null
        try {
            { Test-TpmExtractedScript -Path $path } | Should -Throw
        } finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'throws when the file begins with raw zip (PK) bytes' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-zipbytes-" + [guid]::NewGuid().ToString('N') + '.ps1')
        [System.IO.File]::WriteAllBytes($path, [byte[]](0x50, 0x4B, 0x03, 0x04, 0x00, 0x00))
        try {
            { Test-TpmExtractedScript -Path $path } | Should -Throw '*zip signature*'
        } finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'throws when the file does not contain the TeknoParrot Manager marker' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-nomarker-" + [guid]::NewGuid().ToString('N') + '.ps1')
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.99.99"' -Encoding ascii
        try {
            { Test-TpmExtractedScript -Path $path } | Should -Throw '*TeknoParrot Manager*'
        } finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'throws when the file has no $ScriptVersion assignment' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-noscriptversion-" + [guid]::NewGuid().ToString('N') + '.ps1')
        Set-Content -LiteralPath $path -Value '# TeknoParrot Manager' -Encoding ascii
        try {
            { Test-TpmExtractedScript -Path $path } | Should -Throw '*ScriptVersion*'
        } finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Invoke-TpmAutoUpdate -Apply -WhatIf' {
    It 'makes no backup, download, or replacement when -WhatIf is passed' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-whatif-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        $scriptPath = Join-Path $tempRoot 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $scriptPath -Value '$ScriptVersion = "0.0.1"' -Encoding ascii
        $orchestratorPath = Join-Path $PSScriptRoot '..\tools\Invoke-TpmAutoUpdate.ps1'

        try {
            Mock -ModuleName TpmAutoUpdate.Core Get-LatestRelease {
                return [pscustomobject]@{
                    tag_name = 'v0.99.99'
                    assets   = @([pscustomobject]@{
                        name                 = 'TeknoParrot.Manager.v0.99.99.BETA.zip'
                        browser_download_url = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/TeknoParrot.Manager.v0.99.99.BETA.zip'
                    })
                }
            }
            Mock -ModuleName TpmAutoUpdate.Core Invoke-WebRequest { throw 'Invoke-WebRequest should not be called during -WhatIf' }

            & $orchestratorPath -Apply -WhatIf -ScriptPath $scriptPath -Owner 'Jumpstile' -Repository 'teknoparrot-manager' *> $null

            Test-Path -LiteralPath (Join-Path $tempRoot 'UpdateBackups') | Should -BeFalse
            (Get-Content -LiteralPath $scriptPath -Raw) | Should -Match '0\.0\.1'
        } finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
