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
        Compare-TpmVersions -VersionTextA 'v1.0-RC8' -VersionTextB 'v1.0-RC9' | Should -Be -1
        Compare-TpmVersions -VersionTextA 'v1.0-RC7' -VersionTextB 'v1.0-RC9' | Should -Be -1
        Compare-TpmVersions -VersionTextA 'v1.0-RC9' -VersionTextB 'v1.0-RC10' | Should -Be -1
        Compare-TpmVersions -VersionTextA 'v1.0-RC8' -VersionTextB 'v1.0' | Should -Be -1
        Compare-TpmVersions -VersionTextA 'v1.0' -VersionTextB 'v1.0-RC8' | Should -Be 1
    }

    It 'orders the whole release line: RC7 < RC8 < RC8.1 < RC9 < RC9.1 < RC9.2 < 1.0 < 1.0.1 < 1.1' {
        $line = @('v1.0-RC7', 'v1.0-RC8', 'v1.0-RC8.1', 'v1.0-RC8.2', 'v1.0-RC8.10', 'v1.0-RC9', 'v1.0-RC9.1', 'v1.0-RC9.2', 'v1.0', 'v1.0.1', 'v1.1')
        for ($i = 0; $i -lt $line.Count; $i++) {
            for ($j = 0; $j -lt $line.Count; $j++) {
                $expected = [Math]::Sign($i - $j)
                Compare-TpmVersions -VersionTextA $line[$i] -VersionTextB $line[$j] | Should -Be $expected -Because ('{0} versus {1}' -f $line[$i], $line[$j])
            }
        }
        Compare-TpmVersions -VersionTextA 'v1.0-RC8.1' -VersionTextB '1.0-RC8.1' | Should -Be 0
    }

    It 'rejects a dotted label with nothing after the dot' {
        { Compare-TpmVersions -VersionTextA 'v1.0-RC8.' -VersionTextB 'v1.0' } | Should -Throw
        { Compare-TpmVersions -VersionTextA 'v1.0-RC8.x' -VersionTextB 'v1.0' } | Should -Throw
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
    It '[UVO-08] rejects wrapped version and label targets, including sole, duplicate, scoped, and nested assignments' {
        $tempScript = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-version-wrapped-" + [guid]::NewGuid().ToString('N') + '.ps1')
        $invalidContents = @(
            '[string]$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            '$ScriptVersion = "1.0"' + "`n" + '[string]$ReleaseCandidateLabel = "RC8"'
            '[string]($ScriptVersion) = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            '$ScriptVersion = "1.0"' + "`n" + '[string]($ReleaseCandidateLabel) = "RC8"'
            '([string]$ScriptVersion) = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            '$ScriptVersion = "1.0"' + "`n" + '([string]$ReleaseCandidateLabel) = "RC8"'
            '$ScriptVersion = "1.0"' + "`n" + '[string]$ScriptVersion = "1.1"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            '$ScriptVersion = "1.0"' + "`n" + '[string]$script:ScriptVersion = "1.1"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            '$ScriptVersion = "1.0"' + "`n" + '($script:ScriptVersion) = "1.1"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            '$ScriptVersion = "1.0"' + "`n" + '[string]($script:ScriptVersion) = "1.1"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            '$ScriptVersion = "1.0"' + "`n" + 'function Set-Version { [string]$ScriptVersion = "0.99" }' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            '$ScriptVersion = "1.0"' + "`n" + '([string]($script:ScriptVersion)) = "1.1"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"' + "`n" + '[string]$script:ReleaseCandidateLabel = "RC7"'
            '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"' + "`n" + '[string]($script:ReleaseCandidateLabel) = "RC7"'
            '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"' + "`n" + '($script:ReleaseCandidateLabel) = "RC7"'
            '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"' + "`n" + 'function Set-Label { [string]$ReleaseCandidateLabel = "RC7" }',
            '[ValidateNotNull()]$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            '$ScriptVersion = "1.0"' + "`n" + '[ValidateNotNull()]$ReleaseCandidateLabel = "RC8"'
            '$ScriptVersion = "1.0"' + "`n" + '[ValidateNotNull()]$script:ScriptVersion = "1.1"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            '$ScriptVersion = "1.0"' + "`n" + '([ValidateNotNull()]$script:ScriptVersion) = "1.1"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            '$ScriptVersion = "1.0"' + "`n" + '[string]([ValidateNotNull()]$script:ScriptVersion) = "1.1"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            '$ScriptVersion = "1.0"' + "`n" + '(([string]([ValidateNotNull()]$script:ScriptVersion))) = "1.1"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"' + "`n" + '([ValidateNotNull()]$script:ReleaseCandidateLabel) = "RC7"'
            '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"' + "`n" + '[ValidateNotNull()]$script:ReleaseCandidateLabel = "RC7"'
            '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"' + "`n" + '$script:ScriptVersion++'
            '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"' + "`n" + '++$script:ScriptVersion'
            '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"' + "`n" + '$script:ScriptVersion--'
            '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"' + "`n" + '--$script:ScriptVersion'
            '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"' + "`n" + '($script:ScriptVersion)++'
            '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"' + "`n" + '--($script:ReleaseCandidateLabel)'
            '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"' + "`n" + 'foreach ($script:ScriptVersion in @("1.1")) { }'
            '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"' + "`n" + 'foreach ($ReleaseCandidateLabel in @("RC7")) { }'
            'param($ScriptVersion, $ReleaseCandidateLabel)' + "`n" + '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            'data ScriptVersion { "1.1" }' + "`n" + '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"' + "`n" + 'data ReleaseCandidateLabel { "RC7" }'
            '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"' + "`n" + '$script:ScriptVersion[0] = "x"'
            '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"' + "`n" + '($script:ScriptVersion).Length = 1'
            '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"' + "`n" + '$script:ScriptVersion[0].Length = 1'
            '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"' + "`n" + '$script:ReleaseCandidateLabel[0] = "x"'
            '$ScriptVersion, $other = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            '$ScriptVersion = "1.0"' + "`n" + '($ScriptVersion, $other) = "1.1"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            '$ScriptVersion = "1.0"' + "`n" + '(($ScriptVersion, $other)) = "1.1"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            '$ScriptVersion = "1.0"' + "`n" + '(($ScriptVersion), $other) = "1.1"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
            '$ReleaseCandidateLabel = "RC8"' + "`n" + '$other, $ScriptVersion = "1.0"'
            '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"' + "`n" + '$global:ScriptVersion += "1"'
        )
        try {
            foreach ($invalidContent in $invalidContents) {
                $tokens = $null
                $parseErrors = $null
                [System.Management.Automation.Language.Parser]::ParseInput(
                    $invalidContent,
                    [ref]$tokens,
                    [ref]$parseErrors
                ) | Out-Null
                @($parseErrors).Count | Should -Be 0
                Set-Content -LiteralPath $tempScript -Value $invalidContent -Encoding ascii
                { Get-TpmLocalVersion -Path $tempScript } | Should -Throw
            }
        } finally {
            Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
        }
    }
    It '[UVO-08] permits local function parameters and unrelated member/index reads' {
        $content = '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"' + "`n" +
            'function Get-ManagerVersionIdentity { param([string]$ScriptVersion, [string]$ReleaseCandidateLabel) }' + "`n" +
            '& { param([string]$ScriptVersion, [string]$ReleaseCandidateLabel) }' + "`n" +
            '$text = ''$ScriptVersion = "99"''' + "`n" +
            '$other[$ScriptVersion] = "x"'
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$parseErrors) | Out-Null
        @($parseErrors).Count | Should -Be 0
        $tempScript = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-local-identity-near-miss-" + [guid]::NewGuid().ToString('N') + '.ps1')
        try {
            Set-Content -LiteralPath $tempScript -Value $content -Encoding ascii
            Get-TpmLocalVersion -Path $tempScript | Should -Be '1.0-RC8'
        } finally {
            Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
        }
    }

    It '[UVO-08] reads the current manager identity from source without executing it' {
        $managerScriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
        Get-TpmLocalVersion -Path $managerScriptPath | Should -Be '1.0-RC9.4'
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

        # Stringify the Write-Host records first: Windows PowerShell 5.1
        # Out-String wraps InformationRecords at the console width (120 on
        # the test PC), which splits the 125-character Check-only line.
        $runnerOutput = & $runnerPath -CheckOnly -ScriptPath $localScript 6>&1 | ForEach-Object { [string]$_ } | Out-String

        $runnerOutput | Should -Match 'Update available: 1.0-RC7 -> v1.0-RC8'
        $runnerOutput | Should -Match 'Check only\. -Apply replaces only TeknoParrot-Manager\.ps1 and refuses release packages that contain other files\.'
        $runnerOutput | Should -Not -Match 'Re-run with -Apply to update'
    }

    It 'does not offer RC8 again when the local script is RC8' {
        $runnerPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\tools\Invoke-TpmAutoUpdate.ps1')).ProviderPath
        $localScript = Join-Path $TestDrive 'runner-rc8.ps1'
        Set-Content -LiteralPath $localScript -Value ('$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"') -Encoding ascii

        Mock Get-LatestRelease {
            New-TpmTestRelease -TagName 'v1.0-RC8' -AssetNames @('TeknoParrot.Manager.v1.0.RC8.zip')
        }

        $runnerOutput = & $runnerPath -CheckOnly -ScriptPath $localScript 6>&1 | ForEach-Object { [string]$_ } | Out-String

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

    It 'accepts the ZIP names of the interim and later releases' -ForEach @(
        @{ Tag = 'v1.0-RC8.1'; Asset = 'TeknoParrot.Manager.v1.0.RC8.1.zip' }
        @{ Tag = 'v1.0-RC9'; Asset = 'TeknoParrot.Manager.v1.0.RC9.zip' }
        @{ Tag = 'v1.0-RC9.1'; Asset = 'TeknoParrot.Manager.v1.0.RC9.1.zip' }
        @{ Tag = 'v1.0-RC9.2'; Asset = 'TeknoParrot.Manager.v1.0.RC9.2.zip' }
        @{ Tag = 'v1.0.1'; Asset = 'TeknoParrot.Manager.v1.0.1.zip' }
        @{ Tag = 'v1.1'; Asset = 'TeknoParrot.Manager.v1.1.zip' }
    ) {
        $release = New-TpmTestRelease -TagName $Tag -AssetNames @($Asset, 'unrelated-file.txt')
        $selected = Select-TpmUpdateAsset -Release $release -Pattern '^TeknoParrot\.Manager\.v.*\.zip$' -Owner 'Jumpstile' -Repository 'teknoparrot-manager'
        $selected.name | Should -Be $Asset
        Compare-TpmVersions -VersionTextA '1.0-RC7' -VersionTextB $release.tag_name | Should -Be -1
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

Describe 'Save-TpmReleaseAsset failed download' {
    It 'shows the digest error, not a cleanup error, when a scanner still holds the rejected file' {
        InModuleScope TpmAutoUpdate.Core {
            Mock Invoke-TpmDownload {
                [System.IO.File]::WriteAllBytes($DestinationPath, [byte[]](1, 2, 3, 4))
                $script:heldDownload = [System.IO.File]::Open($DestinationPath, 'Open', 'Read', 'Read')
                return $true
            }
            $asset = [pscustomobject]@{
                digest               = 'sha256:' + ('a' * 64)
                browser_download_url = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/TeknoParrot.Manager.v0.99.99.BETA.zip'
                size                 = 4
            }
            $heldPath = $null
            try {
                { Save-TpmReleaseAsset -Asset $asset } | Should -Throw '*Update digest mismatch*Download the complete ZIP manually*'
            } finally {
                if ($script:heldDownload) { $heldPath = $script:heldDownload.Name; $script:heldDownload.Dispose(); $script:heldDownload = $null }
                if ($heldPath -and (Test-Path -LiteralPath $heldPath)) { Remove-Item -LiteralPath $heldPath -Force -ErrorAction SilentlyContinue }
            }
        }
    }
}

# FIX21A: the HttpClient tier bounds every body read with the module's
# no-progress window. A loopback TCP peer sends response headers and 4 of the
# 64 declared body bytes, then stops sending; the window is shortened to 1 s
# through the module-scope seam $script:TpmDownloadNoProgressTimeoutSeconds.
Describe 'Invoke-TpmDownloadHttpClient body-stall guard' {
    It 'abandons a stalled response body with the no-progress error on every HttpClient attempt and leaves no partial file' {
        $serverScript = @'
param($Listener, [int]$Connections, [int]$HoldMilliseconds, [int]$DeadlineMilliseconds)
$served = 0
$deadline = [DateTime]::UtcNow.AddMilliseconds($DeadlineMilliseconds)
$head = [System.Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: application/octet-stream`r`nContent-Length: 64`r`nConnection: close`r`n`r`n")
$partial = [byte[]](0x50, 0x4B, 0x03, 0x04)
while ($served -lt $Connections -and [DateTime]::UtcNow -lt $deadline) {
    if (-not $Listener.Pending()) {
        Start-Sleep -Milliseconds 20
        continue
    }
    $client = $Listener.AcceptTcpClient()
    try {
        $stream = $client.GetStream()
        $stream.ReadTimeout = 5000
        $buffer = New-Object byte[] 4096
        $request = ''
        while ($request.IndexOf("`r`n`r`n") -lt 0) {
            $read = $stream.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) { break }
            $request += [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read)
        }
        $stream.Write($head, 0, $head.Length)
        $stream.Write($partial, 0, $partial.Length)
        $stream.Flush()
        # Stall: keep the connection open without sending the rest of the body.
        Start-Sleep -Milliseconds $HoldMilliseconds
    } catch {
    } finally {
        $client.Close()
    }
    $served++
}
$served
'@
        $listener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
        $listener.Start()
        $server = $null
        $savedTemp = $env:TEMP
        try {
            $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
            $server = [powershell]::Create()
            [void]$server.AddScript($serverScript).AddArgument($listener).AddArgument(3).AddArgument(2500).AddArgument(60000)
            $serverHandle = $server.BeginInvoke()

            # Invoke-TpmDownload places its partial file under $env:TEMP.
            $partialDir = Join-Path $TestDrive 'stall-partial'
            New-Item -ItemType Directory -Path $partialDir -Force | Out-Null
            $env:TEMP = $partialDir
            $destination = Join-Path $TestDrive 'stall-out\p.zip'

            $outcome = InModuleScope TpmAutoUpdate.Core -Parameters @{ Url = "http://127.0.0.1:$port/p.zip"; Destination = $destination } {
                param($Url, $Destination)
                $savedTimeout = $script:TpmDownloadNoProgressTimeoutSeconds
                $script:TpmDownloadNoProgressTimeoutSeconds = 1
                try {
                    Mock Test-TpmDownloadBitsAvailable { $false }
                    Mock Start-Sleep {}
                    Mock Write-TpmDownloadProgress {}
                    Mock Invoke-TpmDownloadWebRequest { throw 'stall test: emergency tier disabled' }

                    $verbose = New-Object System.Collections.Generic.List[string]
                    $caught = $null
                    $watch = [System.Diagnostics.Stopwatch]::StartNew()
                    try {
                        Invoke-TpmDownload -DownloadUrl $Url -DestinationPath $Destination -Label 'stall-test' -Verbose 4>&1 |
                            ForEach-Object { if ($_ -is [System.Management.Automation.VerboseRecord]) { $verbose.Add([string]$_.Message) } }
                    } catch {
                        $caught = $_
                    }
                    $watch.Stop()

                    Should -Invoke Invoke-TpmDownloadWebRequest -Times 3 -Exactly
                    [pscustomobject]@{
                        Error          = if ($caught) { [string]$caught.Exception.Message } else { $null }
                        Verbose        = $verbose.ToArray()
                        ElapsedSeconds = $watch.Elapsed.TotalSeconds
                    }
                } finally {
                    $script:TpmDownloadNoProgressTimeoutSeconds = $savedTimeout
                }
            }

            $outcome.Error | Should -BeExactly 'stall test: emergency tier disabled'
            foreach ($attempt in 1..3) {
                $expectedLine = 'stall-test: HttpClient attempt {0} failed: HttpClient download made no progress for 1 seconds.' -f $attempt
                @($outcome.Verbose | Where-Object { $_ -ceq $expectedLine }).Count | Should -Be 1
            }
            # Three stalled attempts under the default 120 s window would take at least 360 s.
            $outcome.ElapsedSeconds | Should -BeLessThan 60
            Test-Path -LiteralPath $destination | Should -BeFalse
            @(Get-ChildItem -LiteralPath $partialDir -Force).Count | Should -Be 0
            $serverHandle.AsyncWaitHandle.WaitOne(30000) | Should -BeTrue
            [int](@($server.EndInvoke($serverHandle))[-1]) | Should -Be 3
            InModuleScope TpmAutoUpdate.Core { $script:TpmDownloadNoProgressTimeoutSeconds | Should -Be 120 }
        } finally {
            $env:TEMP = $savedTemp
            $listener.Stop()
            if ($server) { $server.Dispose() }
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
    It '[UVO-08] rejects extracted candidates with a cast-parenthesized scoped version overwrite' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-cast-parenthesized-scoped-rc-" + [guid]::NewGuid().ToString('N') + '.ps1')
        $content = "# TeknoParrot Manager`n" + '$ScriptVersion = "1.0"' + "`n" +
            '[string]($script:ScriptVersion) = "1.1"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
        Set-Content -LiteralPath $path -Value $content -Encoding ascii
        try {
            { Test-TpmExtractedScript -Path $path -ExpectedVersion 'v1.0-RC8' } | Should -Throw
        } finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
    It '[UVO-08] rejects an attributed scoped version overwrite in an extracted candidate' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-attributed-scoped-rc-" + [guid]::NewGuid().ToString('N') + '.ps1')
        $content = "# TeknoParrot Manager`n" + '$ScriptVersion = "1.0"' + "`n" +
            '[ValidateNotNull()]$script:ScriptVersion = "1.1"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$parseErrors) | Out-Null
        @($parseErrors).Count | Should -Be 0
        Set-Content -LiteralPath $path -Value $content -Encoding ascii
        try {
            { Test-TpmExtractedScript -Path $path -ExpectedVersion 'v1.0-RC8' } | Should -Throw
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
            # Script-visible mocks (no -ModuleName): the orchestrator calls Get-LatestRelease from its own script scope, where a module-scoped mock does not apply and the real release lookup would reach the network.
            Mock Get-LatestRelease { New-TpmTestRelease }
            Mock Save-TpmReleaseAsset { throw 'download should not be called during -WhatIf' }

            & $orchestratorPath -Apply -WhatIf -ScriptPath $scriptPath -Owner 'Jumpstile' -Repository 'teknoparrot-manager' *> $null
            # Mutation: a module-scoped mock again -> the script-visible lookup is never called and this count is 0 (the real lookup would run).
            Should -Invoke Get-LatestRelease -Times 1 -Exactly
            Should -Invoke Save-TpmReleaseAsset -Times 0 -Exactly

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
    It '[UVO-08] does not replace the installed script when a cast-parenthesized identity target is present' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-apply-cast-parenthesized-target-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        $scriptPath = Join-Path $tempRoot 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $scriptPath -Value '$ScriptVersion = "0.99.99"' -Encoding ascii
        $originalContent = Get-Content -LiteralPath $scriptPath -Raw
        $candidateZipPath = Join-Path $tempRoot 'candidate.zip'
        $candidateContent = "# TeknoParrot Manager`n" + '$ScriptVersion = "1.0"' + "`n" +
            '[string]($script:ScriptVersion) = "1.1"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
        New-TpmFixtureZip -DestinationPath $candidateZipPath -EntryContent $candidateContent | Out-Null
        $orchestratorPath = Join-Path $PSScriptRoot '..\tools\Invoke-TpmAutoUpdate.ps1'
        $saveAssetMock = { return $candidateZipPath }.GetNewClosure()

        try {
            Mock Get-LatestRelease { New-TpmTestRelease -TagName 'v1.0-RC8' -AssetNames @('TeknoParrot.Manager.v1.0.RC8.zip') }
            Mock Save-TpmReleaseAsset $saveAssetMock

            { & $orchestratorPath -Apply -Confirm:$false -ScriptPath $scriptPath -Owner 'Jumpstile' -Repository 'teknoparrot-manager' 6>&1 | Out-Null } | Should -Throw
            Should -Invoke Get-LatestRelease -Times 1
            Should -Invoke Save-TpmReleaseAsset -Times 1
            (Get-Content -LiteralPath $scriptPath -Raw) | Should -Be $originalContent
        } finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It '[UVO-08] does not replace the installed script when an attributed identity target is present' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-apply-attributed-target-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        $scriptPath = Join-Path $tempRoot 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $scriptPath -Value '$ScriptVersion = "0.99.99"' -Encoding ascii
        $originalContent = Get-Content -LiteralPath $scriptPath -Raw
        $candidateZipPath = Join-Path $tempRoot 'candidate.zip'
        $candidateContent = "# TeknoParrot Manager`n" + '$ScriptVersion = "1.0"' + "`n" +
            '[ValidateNotNull()]$script:ScriptVersion = "1.1"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseInput($candidateContent, [ref]$tokens, [ref]$parseErrors) | Out-Null
        @($parseErrors).Count | Should -Be 0
        New-TpmFixtureZip -DestinationPath $candidateZipPath -EntryName 'TeknoParrot-Manager.ps1' -EntryContent $candidateContent | Out-Null
        $orchestratorPath = Join-Path $PSScriptRoot '..\tools\Invoke-TpmAutoUpdate.ps1'
        $saveAssetMock = { return $candidateZipPath }.GetNewClosure()

        try {
            Mock Get-LatestRelease { New-TpmTestRelease -TagName 'v1.0-RC8' -AssetNames @('TeknoParrot.Manager.v1.0.RC8.zip') }
            Mock Save-TpmReleaseAsset $saveAssetMock
            Mock Move-Item { throw 'Replacement must not run for an invalid candidate identity.' }

            { & $orchestratorPath -Apply -Confirm:$false -ScriptPath $scriptPath -Owner 'Jumpstile' -Repository 'teknoparrot-manager' 6>&1 | Out-Null } | Should -Throw
            Should -Invoke Get-LatestRelease -Times 1
            Should -Invoke Save-TpmReleaseAsset -Times 1
            Should -Invoke Move-Item -Times 0 -Exactly
            (Get-Content -LiteralPath $scriptPath -Raw) | Should -Be $originalContent
        } finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

}
