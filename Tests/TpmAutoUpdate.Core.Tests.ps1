#Requires -Module Pester

# Regression suite for tools/TpmAutoUpdate.Core.psm1. Unlike
# TeknoParrot-Manager.ps1, this is a real module with no top-level side
# effects, so it can be imported directly without AST surgery.
#
# Run with: Invoke-Pester -Path .\Tests\TpmAutoUpdate.Core.Tests.ps1

BeforeAll {
    $modulePath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\tools\TpmAutoUpdate.Core.psm1')).ProviderPath
    Get-Module TpmAutoUpdate.Core -All | Remove-Module -Force
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

AfterAll {
    Get-Module TpmAutoUpdate.Core -All | Remove-Module -Force
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

    # Issue #105: [version] cannot hold the "-RC1" suffix. This helper parses
    # the numeric base only; Compare-TpmVersions owns ordering and preserves
    # the candidate suffix as a separate identity.
    It 'strips a release-candidate suffix and parses the numeric base' {
        ConvertTo-TpmVersion -VersionText 'v1.0-RC1' | Should -Be ([version]'1.0')
        ConvertTo-TpmVersion -VersionText 'v1.0-RC2' | Should -Be ([version]'1.0')
    }

}
Describe 'Compare-TpmVersions' {
    It 'orders numeric base versions before release-candidate labels' {
        Compare-TpmVersions -VersionTextA '0.99.99' -VersionTextB 'v1.0-RC1' | Should -Be -1
    }

    It 'orders release candidates numerically and before the final release' {
        Compare-TpmVersions -VersionTextA 'v1.0-RC7' -VersionTextB 'v1.0-RC8' | Should -Be -1
        Compare-TpmVersions -VersionTextA 'v1.0-RC9' -VersionTextB 'v1.0-RC10' | Should -Be -1
        Compare-TpmVersions -VersionTextA 'v1.0-RC8' -VersionTextB 'v1.0' | Should -Be -1
        Compare-TpmVersions -VersionTextA 'v1.0' -VersionTextB 'v1.0-RC8' | Should -Be 1
    }

    It 'treats equivalent full identities as equal and malformed labels as invalid' {
        Compare-TpmVersions -VersionTextA 'v1.0-RC8' -VersionTextB '1.0-RC8' | Should -Be 0
        { Compare-TpmVersions -VersionTextA '1.0-BETA' -VersionTextB '1.0' } | Should -Throw
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

    It 'includes the release-candidate label in the local version identity' {
        $tempScript = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-version-rc-" + [guid]::NewGuid().ToString('N') + '.ps1')
        Set-Content -LiteralPath $tempScript -Value ('$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"') -Encoding ascii
        try {
            Get-TpmLocalVersion -Path $tempScript | Should -Be '1.0-RC8'
        } finally {
            Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
        }
    }

    It 'reads the executable identity rather than here-string assignment lookalikes' {
        $tempScript = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-version-here-string-" + [guid]::NewGuid().ToString('N') + '.ps1')
        $content = @'
$decoy = @"
$ScriptVersion = "1.0"
$ReleaseCandidateLabel = "RC8"
"@
$ScriptVersion = "1.0"
$ReleaseCandidateLabel = "RC7"
'@
        Set-Content -LiteralPath $tempScript -Value $content -Encoding ascii
        try {
            Get-TpmLocalVersion -Path $tempScript | Should -Be '1.0-RC7'
        } finally {
            Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
        }
    }

    It 'accepts single-quoted local version declarations' {
        $tempScript = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-version-single-quoted-" + [guid]::NewGuid().ToString('N') + '.ps1')
        Set-Content -LiteralPath $tempScript -Value ('$ScriptVersion = ''1.0''' + "`n" + '$ReleaseCandidateLabel = ''RC8''') -Encoding ascii
        try {
            Get-TpmLocalVersion -Path $tempScript | Should -Be '1.0-RC8'
        } finally {
            Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects duplicate, scoped, nested, compound, nonliteral, and malformed local identity assignments' {
        $tempScript = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-version-invalid-" + [guid]::NewGuid().ToString('N') + '.ps1')
        $invalidContents = @(
            '$ScriptVersion = "1.0"' + "`n" + '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            '$ScriptVersion = "1.0"' + "`n" + '$script:ScriptVersion = "1.1"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            '$ScriptVersion = "1.0"' + "`n" + 'function Set-Version { $ScriptVersion = "0.99" }' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            '$ScriptVersion = "1.0"' + "`n" + '$ScriptVersion += "1"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            '$ScriptVersion = (Get-VersionBase)' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = Get-CandidateLabel'
            '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "$env:TPM_LABEL"'
            '$ScriptVersion = "1.0"' + "`n" + 'if ('
        )
        try {
            foreach ($invalidContent in $invalidContents) {
                Set-Content -LiteralPath $tempScript -Value $invalidContent -Encoding ascii
                { Get-TpmLocalVersion -Path $tempScript } | Should -Throw
            }
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

Describe 'Invoke-TpmAutoUpdate.ps1 version ordering' {
    It 'offers RC8 when the local script is RC7' {
        $runnerPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\tools\Invoke-TpmAutoUpdate.ps1')).ProviderPath
        $localScript = Join-Path $TestDrive 'runner-rc7.ps1'
        Set-Content -LiteralPath $localScript -Value ('$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC7"') -Encoding ascii

        Mock Get-LatestRelease {
            New-TpmTestRelease -TagName 'v1.0-RC8' -AssetNames @('TeknoParrot.Manager.v1.0.RC8.zip')
        }

        $runnerOutput = & $runnerPath -CheckOnly -ScriptPath $localScript 6>&1 | Out-String

        $runnerOutput | Should -Match 'Update available: 1.0-RC7 -> v1.0-RC8'
        $runnerOutput | Should -Match 'Check only. Re-run with -Apply to update.'
    }

    It 'does not offer RC8 again when the local script is RC8' {
        $runnerPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\tools\Invoke-TpmAutoUpdate.ps1')).ProviderPath
        $localScript = Join-Path $TestDrive 'runner-rc8.ps1'
        Set-Content -LiteralPath $localScript -Value ('$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"') -Encoding ascii

        Mock Get-LatestRelease {
            New-TpmTestRelease -TagName 'v1.0-RC8' -AssetNames @('TeknoParrot.Manager.v1.0.RC8.zip')
        }

        $runnerOutput = & $runnerPath -CheckOnly -ScriptPath $localScript 6>&1 | Out-String

        $runnerOutput | Should -Match 'Already current. No update needed.'
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

Describe 'Invoke-TpmDownload module-local retry behavior' {
    It 'keeps TransientError in the BITS polling state list' {
        $moduleSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\tools\TpmAutoUpdate.Core.psm1') -Raw
        $moduleSource | Should -Match "'Connecting',\s*'Transferring',\s*'Queued',\s*'TransientError'"
    }

    It 'retries transient HttpClient failures before the emergency fallback' {
        InModuleScope TpmAutoUpdate.Core {
            Mock Test-TpmDownloadBitsAvailable { $false }
            Mock Start-Sleep {}
            Mock Invoke-TpmDownloadWebRequest { throw 'Invoke-WebRequest should not run when HttpClient eventually succeeds' }
            $script:httpAttempt = 0
            Mock Invoke-TpmDownloadHttpClient {
                $script:httpAttempt++
                if ($script:httpAttempt -lt 2) { throw 'transient network error' }
                Set-Content -LiteralPath $TempPath -Value 'zip content' -NoNewline
            }

            $path = Join-Path $TestDrive 'http-retry.zip'
            Invoke-TpmDownload -DownloadUrl 'https://example.com/file.zip' -DestinationPath $path | Should -BeTrue

            $script:httpAttempt | Should -Be 2
            Should -Invoke Invoke-TpmDownloadWebRequest -Times 0
        }
    }

    It 'retries transient emergency fallback failures before succeeding' {
        InModuleScope TpmAutoUpdate.Core {
            Mock Test-TpmDownloadBitsAvailable { $false }
            Mock Start-Sleep {}
            Mock Invoke-TpmDownloadHttpClient { throw 'transient http failure' }
            $script:webAttempt = 0
            Mock Invoke-TpmDownloadWebRequest {
                $script:webAttempt++
                if ($script:webAttempt -lt 2) { throw 'transient web failure' }
                Set-Content -LiteralPath $TempPath -Value 'zip content' -NoNewline
            }

            $path = Join-Path $TestDrive 'web-retry.zip'
            Invoke-TpmDownload -DownloadUrl 'https://example.com/file.zip' -DestinationPath $path | Should -BeTrue

            $script:webAttempt | Should -Be 2
        }
    }

    It 'does not retry a definitive HttpClient 404 before the emergency fallback' {
        InModuleScope TpmAutoUpdate.Core {
            Mock Test-TpmDownloadBitsAvailable { $false }
            Mock Start-Sleep {}
            Mock Invoke-TpmDownloadHttpClient { throw 'Response status code does not indicate success: 404 (Not Found).' }
            Mock Invoke-TpmDownloadWebRequest { Set-Content -LiteralPath $TempPath -Value 'zip content' -NoNewline }

            $path = Join-Path $TestDrive 'http-404.zip'
            Invoke-TpmDownload -DownloadUrl 'https://example.com/missing.zip' -DestinationPath $path | Should -BeTrue

            Should -Invoke Invoke-TpmDownloadHttpClient -Times 1
            Should -Invoke Invoke-TpmDownloadWebRequest -Times 1
        }
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
            Test-TpmExtractedScript -Path $path -ExpectedVersion 'v0.99.99' | Should -BeTrue
        } finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'accepts an RC candidate whose literal identity matches the release tag' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-valid-rc-" + [guid]::NewGuid().ToString('N') + '.ps1')
        $content = "# TeknoParrot Manager`n" + '$ScriptVersion = ''1.0''' + "`n" + '$ReleaseCandidateLabel = ''RC8'''
        Set-Content -LiteralPath $path -Value $content -Encoding ascii
        try {
            Test-TpmExtractedScript -Path $path -ExpectedVersion 'v1.0-RC8' | Should -BeTrue
        } finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects candidate identity that differs from the release tag' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-mismatched-rc-" + [guid]::NewGuid().ToString('N') + '.ps1')
        Set-Content -LiteralPath $path -Value "# TeknoParrot Manager`n`$ScriptVersion = `"1.0`"`n`$ReleaseCandidateLabel = `"RC7`"" -Encoding ascii
        try {
            { Test-TpmExtractedScript -Path $path -ExpectedVersion 'v1.0-RC8' } | Should -Throw '*does not match release tag*'
        } finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'ignores here-string assignment lookalikes when validating the candidate identity' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-string-spoof-" + [guid]::NewGuid().ToString('N') + '.ps1')
        $content = @'
# TeknoParrot Manager
$decoy = @"
$ScriptVersion = "1.0"
$ReleaseCandidateLabel = "RC8"
"@
'@
        Set-Content -LiteralPath $path -Value $content -Encoding ascii
        try {
            { Test-TpmExtractedScript -Path $path -ExpectedVersion 'v1.0-RC8' } | Should -Throw '*ScriptVersion*'
        } finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
    It 'rejects extracted scripts containing non-ASCII bytes before identity parsing' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-non-ascii-" + [guid]::NewGuid().ToString('N') + '.ps1')
        $prefixText = '# TeknoParrot Manager' + "`n" + '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"' + "`n" + '$decoy = "'
        $prefix = [System.Text.Encoding]::ASCII.GetBytes($prefixText)
        $suffix = [System.Text.Encoding]::ASCII.GetBytes('"' + "`n")
        $validUtf8NonAscii = [System.Text.UTF8Encoding]::new($false).GetBytes([string][char]0x2014)
        $testCases = @(
            [pscustomobject]@{ Bytes = [byte[]]($prefix + $validUtf8NonAscii + $suffix) }
            [pscustomobject]@{ Bytes = [byte[]]($prefix + [byte[]](0xFF) + $suffix) }
        )
        try {
            foreach ($testCase in $testCases) {
                [System.IO.File]::WriteAllBytes($path, $testCase.Bytes)
                { Test-TpmExtractedScript -Path $path -ExpectedVersion 'v1.0-RC8' } | Should -Throw '*non-ASCII bytes*'
            }
        } finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }


    It 'throws when the file does not exist' {
        { Test-TpmExtractedScript -Path (Join-Path ([System.IO.Path]::GetTempPath()) 'nope.ps1') -ExpectedVersion 'v0.99.99' } | Should -Throw
    }

    It 'throws when the file is empty' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-empty-" + [guid]::NewGuid().ToString('N') + '.ps1')
        New-Item -ItemType File -Path $path -Force | Out-Null
        try {
            { Test-TpmExtractedScript -Path $path -ExpectedVersion 'v0.99.99' } | Should -Throw
        } finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'throws when the file begins with raw zip (PK) bytes' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-zipbytes-" + [guid]::NewGuid().ToString('N') + '.ps1')
        [System.IO.File]::WriteAllBytes($path, [byte[]](0x50, 0x4B, 0x03, 0x04, 0x00, 0x00))
        try {
            { Test-TpmExtractedScript -Path $path -ExpectedVersion 'v0.99.99' } | Should -Throw '*zip signature*'
        } finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'throws when the file does not contain the TeknoParrot Manager marker' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-nomarker-" + [guid]::NewGuid().ToString('N') + '.ps1')
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.99.99"' -Encoding ascii
        try {
            { Test-TpmExtractedScript -Path $path -ExpectedVersion 'v0.99.99' } | Should -Throw '*TeknoParrot Manager*'
        } finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'throws when the file has no $ScriptVersion assignment' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-noscriptversion-" + [guid]::NewGuid().ToString('N') + '.ps1')
        Set-Content -LiteralPath $path -Value '# TeknoParrot Manager' -Encoding ascii
        try {
            { Test-TpmExtractedScript -Path $path -ExpectedVersion 'v0.99.99' } | Should -Throw '*ScriptVersion*'
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
            Mock -ModuleName TpmAutoUpdate.Core Invoke-TpmDownload { throw 'download should not be called during -WhatIf' }

            & $orchestratorPath -Apply -WhatIf -ScriptPath $scriptPath -Owner 'Jumpstile' -Repository 'teknoparrot-manager' *> $null

            Test-Path -LiteralPath (Join-Path $tempRoot 'UpdateBackups') | Should -BeFalse
            (Get-Content -LiteralPath $scriptPath -Raw) | Should -Match '0\.0\.1'
        } finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'does not install a candidate whose only apparent version is inside a here-string' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-apply-spoof-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        $scriptPath = Join-Path $tempRoot 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $scriptPath -Value '$ScriptVersion = "0.99.99"' -Encoding ascii
        $originalContent = Get-Content -LiteralPath $scriptPath -Raw
        $candidateZipPath = Join-Path $tempRoot 'candidate.zip'
        $candidateContent = @'
# TeknoParrot Manager
$decoy = @"
$ScriptVersion = "1.0"
$ReleaseCandidateLabel = "RC8"
"@
'@
        New-TpmFixtureZip -DestinationPath $candidateZipPath -EntryContent $candidateContent | Out-Null
        $orchestratorPath = Join-Path $PSScriptRoot '..\tools\Invoke-TpmAutoUpdate.ps1'
        $saveAssetMock = { return $candidateZipPath }.GetNewClosure()

        try {
            Mock Get-LatestRelease { New-TpmTestRelease -TagName 'v1.0-RC8' -AssetNames @('TeknoParrot.Manager.v1.0.RC8.zip') }
            Mock Save-TpmReleaseAsset $saveAssetMock

            { & $orchestratorPath -Apply -Confirm:$false -ScriptPath $scriptPath -Owner 'Jumpstile' -Repository 'teknoparrot-manager' 6>&1 | Out-Null } | Should -Throw '*ScriptVersion*'
            Should -Invoke Get-LatestRelease -Times 1
            Should -Invoke Save-TpmReleaseAsset -Times 1

            (Get-Content -LiteralPath $scriptPath -Raw) | Should -Be $originalContent
        } finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'does not install a candidate whose literal identity differs from the release tag' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-apply-mismatch-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        $scriptPath = Join-Path $tempRoot 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $scriptPath -Value '$ScriptVersion = "0.99.99"' -Encoding ascii
        $originalContent = Get-Content -LiteralPath $scriptPath -Raw
        $candidateZipPath = Join-Path $tempRoot 'candidate.zip'
        $candidateContent = "# TeknoParrot Manager`n" + '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC7"'
        New-TpmFixtureZip -DestinationPath $candidateZipPath -EntryContent $candidateContent | Out-Null
        $orchestratorPath = Join-Path $PSScriptRoot '..\tools\Invoke-TpmAutoUpdate.ps1'
        $saveAssetMock = { return $candidateZipPath }.GetNewClosure()

        try {
            Mock Get-LatestRelease { New-TpmTestRelease -TagName 'v1.0-RC8' -AssetNames @('TeknoParrot.Manager.v1.0.RC8.zip') }
            Mock Save-TpmReleaseAsset $saveAssetMock

            { & $orchestratorPath -Apply -Confirm:$false -ScriptPath $scriptPath -Owner 'Jumpstile' -Repository 'teknoparrot-manager' 6>&1 | Out-Null } | Should -Throw '*does not match release tag*'
            Should -Invoke Get-LatestRelease -Times 1
            Should -Invoke Save-TpmReleaseAsset -Times 1
            (Get-Content -LiteralPath $scriptPath -Raw) | Should -Be $originalContent
        } finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

}
