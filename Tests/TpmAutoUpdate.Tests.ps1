#Requires -Module Pester

BeforeAll {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $RepoRoot 'tools\TpmAutoUpdate.psm1') -Force

    function New-TestTpmScript {
        param(
            [string]$Path,
            [string]$Version = '1.2.3',
            [string]$Extra = ''
        )

        @"
# TeknoParrot Manager
`$ScriptVersion = "$Version"
$Extra
"@ | Set-Content -LiteralPath $Path -Encoding UTF8
    }
}

Describe 'TpmAutoUpdate version parsing' {
    It 'normalizes a leading v' {
        (ConvertTo-TpmVersionObject 'v1.2.3').ToString() | Should -Be '1.2.3'
    }

    It 'accepts plain System.Version text' {
        (ConvertTo-TpmVersionObject '1.2.3').ToString() | Should -Be '1.2.3'
    }

    It 'rejects non-System.Version text' {
        { ConvertTo-TpmVersionObject 'v1.2.3-beta' } | Should -Throw '*not a valid System.Version*'
    }
}

Describe 'TpmAutoUpdate asset selection and URL validation' {
    It 'selects the real TPM beta zip asset shape' {
        $release = [pscustomobject]@{
            tag_name = 'v0.99.38'
            assets = @(
                [pscustomobject]@{
                    name = 'TeknoParrot.Manager.v0.99.38.BETA.zip'
                    browser_download_url = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.38/TeknoParrot.Manager.v0.99.38.BETA.zip'
                }
            )
        }

        $asset = Select-TpmUpdateAsset -Release $release -Pattern '^TeknoParrot\.Manager\.v?\d+\.\d+\.\d+\.BETA\.zip$' -Owner 'Jumpstile' -Repository 'teknoparrot-manager'
        $asset.name | Should -Be 'TeknoParrot.Manager.v0.99.38.BETA.zip'
    }

    It 'rejects a non-GitHub release URL even when the name matches' {
        $release = [pscustomobject]@{
            tag_name = 'v0.99.38'
            assets = @(
                [pscustomobject]@{
                    name = 'TeknoParrot.Manager.v0.99.38.BETA.zip'
                    browser_download_url = 'https://example.invalid/TeknoParrot.Manager.v0.99.38.BETA.zip'
                }
            )
        }

        { Select-TpmUpdateAsset -Release $release -Pattern '^TeknoParrot\.Manager\.v?\d+\.\d+\.\d+\.BETA\.zip$' -Owner 'Jumpstile' -Repository 'teknoparrot-manager' } |
            Should -Throw '*Refusing non-release GitHub asset URL*'
    }

    It 'validates URL components with URI parsing' {
        Test-TpmReleaseAssetUrl -Url 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v1.2.3/file.zip' -Owner 'Jumpstile' -Repository 'teknoparrot-manager' | Should -BeTrue
        Test-TpmReleaseAssetUrl -Url 'http://github.com/Jumpstile/teknoparrot-manager/releases/download/v1.2.3/file.zip' -Owner 'Jumpstile' -Repository 'teknoparrot-manager' | Should -BeFalse
        Test-TpmReleaseAssetUrl -Url 'https://example.invalid/Jumpstile/teknoparrot-manager/releases/download/v1.2.3/file.zip' -Owner 'Jumpstile' -Repository 'teknoparrot-manager' | Should -BeFalse
    }
}

Describe 'TpmAutoUpdate backups and script validation' {
    It 'creates a backup copy before replacement' {
        $root = Join-Path $TestDrive 'backup'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $scriptPath = Join-Path $root 'TeknoParrot-Manager.ps1'
        New-TestTpmScript -Path $scriptPath -Version '0.1.0'

        $backupPath = New-TpmUpdateBackup -Path $scriptPath

        Test-Path -LiteralPath $backupPath | Should -BeTrue
        Get-Content -LiteralPath $backupPath -Raw | Should -Match '\$ScriptVersion = "0.1.0"'
    }

    It 'validates a good extracted script' {
        $scriptPath = Join-Path $TestDrive 'TeknoParrot-Manager.ps1'
        New-TestTpmScript -Path $scriptPath

        Test-TpmUpdateScriptContent -Path $scriptPath | Should -BeTrue
    }

    It 'rejects raw zip bytes masquerading as a script' {
        $scriptPath = Join-Path $TestDrive 'TeknoParrot-Manager.ps1'
        [System.IO.File]::WriteAllBytes($scriptPath, [byte[]](0x50, 0x4B, 0x03, 0x04))

        Test-TpmUpdateScriptContent -Path $scriptPath | Should -BeFalse
    }

    It 'rejects scripts without a ScriptVersion assignment' {
        $scriptPath = Join-Path $TestDrive 'TeknoParrot-Manager.ps1'
        '# TeknoParrot Manager' | Set-Content -LiteralPath $scriptPath -Encoding UTF8

        Test-TpmUpdateScriptContent -Path $scriptPath | Should -BeFalse
    }
}

Describe 'TpmAutoUpdate zip extraction' {
    It 'extracts and validates TeknoParrot-Manager.ps1 from a beta release zip' {
        $source = Join-Path $TestDrive 'zip-source'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        New-TestTpmScript -Path (Join-Path $source 'TeknoParrot-Manager.ps1') -Version '9.9.9'
        'sidecar' | Set-Content -LiteralPath (Join-Path $source 'README.txt')
        $zip = Join-Path $TestDrive 'TeknoParrot.Manager.v9.9.9.BETA.zip'
        Compress-Archive -Path (Join-Path $source '*') -DestinationPath $zip

        $extracted = Expand-TpmUpdateScriptFromZip -ZipPath $zip

        Test-Path -LiteralPath $extracted | Should -BeTrue
        Get-Content -LiteralPath $extracted -Raw | Should -Match '\$ScriptVersion = "9.9.9"'
    }

    It 'fails when the zip only contains an invalid script' {
        $source = Join-Path $TestDrive 'bad-zip-source'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        '# no version here' | Set-Content -LiteralPath (Join-Path $source 'TeknoParrot-Manager.ps1') -Encoding UTF8
        $zip = Join-Path $TestDrive 'bad.zip'
        Compress-Archive -Path (Join-Path $source '*') -DestinationPath $zip

        { Expand-TpmUpdateScriptFromZip -ZipPath $zip } | Should -Throw '*failed validation*'
    }
}

Describe 'TpmAutoUpdate WhatIf behavior' {
    It 'does not create a backup when ShouldProcess declines work' {
        $root = Join-Path $TestDrive 'whatif'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $scriptPath = Join-Path $root 'TeknoParrot-Manager.ps1'
        New-TestTpmScript -Path $scriptPath -Version '0.1.0'

        Mock Get-LatestTpmRelease -ModuleName TpmAutoUpdate {
            [pscustomobject]@{
                tag_name = 'v9.9.9'
                assets = @(
                    [pscustomobject]@{
                        name = 'TeknoParrot.Manager.v9.9.9.BETA.zip'
                        browser_download_url = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v9.9.9/TeknoParrot.Manager.v9.9.9.BETA.zip'
                    }
                )
            }
        }
        Mock New-TpmUpdateBackup -ModuleName TpmAutoUpdate { throw 'backup should not run during WhatIf' }
        Mock Save-TpmReleaseAsset -ModuleName TpmAutoUpdate { throw 'download should not run during WhatIf' }

        Invoke-TpmAutoUpdate `
            -ScriptPath $scriptPath `
            -Owner 'Jumpstile' `
            -Repository 'teknoparrot-manager' `
            -AssetNamePattern '^TeknoParrot\.Manager\.v?\d+\.\d+\.\d+\.BETA\.zip$' `
            -Apply `
            -WhatIf

        Test-Path -LiteralPath (Join-Path $root 'UpdateBackups') | Should -BeFalse
        Should -Invoke New-TpmUpdateBackup -ModuleName TpmAutoUpdate -Times 0
        Should -Invoke Save-TpmReleaseAsset -ModuleName TpmAutoUpdate -Times 0
    }
}
