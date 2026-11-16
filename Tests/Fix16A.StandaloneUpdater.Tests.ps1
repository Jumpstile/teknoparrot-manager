#Requires -Module Pester

# FIX16A regressions for the standalone updater (tools/TpmAutoUpdate.Core.psm1
# and tools/Invoke-TpmAutoUpdate.ps1): multi-file package refusal, unique
# never-reused backup directories, the BITS no-progress guard, and the
# null-safe Content-Length read.
#
# Run with: Invoke-Pester -Path .\Tests\Fix16A.StandaloneUpdater.Tests.ps1

BeforeAll {
    $modulePath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\tools\TpmAutoUpdate.Core.psm1')).ProviderPath
    Get-Module TpmAutoUpdate.Core -All | Remove-Module -Force
    Import-Module $modulePath -Force

    function New-F16Zip {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string[]]$Entries,
            [string]$ScriptContent = '# TeknoParrot Manager'
        )

        Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $archive = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($name in $Entries) {
                $entry = $archive.CreateEntry($name)
                if ($name.EndsWith('/')) {
                    continue
                }
                $writer = New-Object System.IO.StreamWriter($entry.Open())
                try {
                    $writer.Write($ScriptContent)
                } finally {
                    $writer.Dispose()
                }
            }
        } finally {
            $archive.Dispose()
        }
        return $Path
    }

    # Like New-F16Zip, but each entry carries its own content and the exact
    # FullName given (duplicates allowed), in the given order.
    function New-F21CoreZip {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][object[]]$Entries
        )

        Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $archive = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($item in $Entries) {
                $entry = $archive.CreateEntry([string]$item.Name)
                $stream = $entry.Open()
                try {
                    $bytes = [System.Text.Encoding]::ASCII.GetBytes([string]$item.Text)
                    $stream.Write($bytes, 0, $bytes.Length)
                } finally {
                    $stream.Dispose()
                }
            }
        } finally {
            $archive.Dispose()
        }
        return $Path
    }
}

AfterAll {
    Get-Module TpmAutoUpdate.Core -All | Remove-Module -Force
}

Describe 'Test-TpmUpdatePackageIsSingleScript' {
    It 'is exported by the module' {
        Get-Command Test-TpmUpdatePackageIsSingleScript -Module TpmAutoUpdate.Core -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'reports a multi-file release ZIP as not single-script' {
        $zip = New-F16Zip -Path (Join-Path $TestDrive 'm.zip') -Entries @('TeknoParrot-Manager.ps1', 'scripts/TpmProgress.psm1', 'tools/Invoke-TpmAutoUpdate.ps1')
        $result = Test-TpmUpdatePackageIsSingleScript -ZipPath $zip
        $result.SingleScript | Should -BeFalse
        $result.ExtraEntryCount | Should -Be 2
        @($result.ExtraEntrySample) | Should -Contain 'scripts/TpmProgress.psm1'
        @($result.ExtraEntrySample) | Should -Contain 'tools/Invoke-TpmAutoUpdate.ps1'
    }

    It 'reports a ZIP containing only the root script as single-script' {
        $zip = New-F16Zip -Path (Join-Path $TestDrive 's.zip') -Entries @('TeknoParrot-Manager.ps1')
        $result = Test-TpmUpdatePackageIsSingleScript -ZipPath $zip
        $result.SingleScript | Should -BeTrue
        $result.ExtraEntryCount | Should -Be 0
        @($result.ExtraEntrySample).Count | Should -Be 0
    }

    It 'ignores directory entries' {
        $zip = New-F16Zip -Path (Join-Path $TestDrive 'd.zip') -Entries @('docs/', 'scripts/', 'TeknoParrot-Manager.ps1')
        $result = Test-TpmUpdatePackageIsSingleScript -ZipPath $zip
        $result.SingleScript | Should -BeTrue
        $result.ExtraEntryCount | Should -Be 0
    }

    It 'does not call a ZIP with no TeknoParrot-Manager.ps1 a single-script package' {
        $zip = New-F16Zip -Path (Join-Path $TestDrive 'empty.zip') -Entries @('docs/')
        $result = Test-TpmUpdatePackageIsSingleScript -ZipPath $zip
        $result.SingleScript | Should -BeFalse
        $result.ExtraEntryCount | Should -Be 0
    }

    It 'counts a nested copy of the script as an extra entry' {
        $zip = New-F16Zip -Path (Join-Path $TestDrive 'n.zip') -Entries @('x/TeknoParrot-Manager.ps1')
        $result = Test-TpmUpdatePackageIsSingleScript -ZipPath $zip
        $result.SingleScript | Should -BeFalse
        $result.ExtraEntryCount | Should -Be 1
        @($result.ExtraEntrySample) | Should -Be @('x/TeknoParrot-Manager.ps1')
    }

    It 'limits the extra-entry sample to the first five entries' {
        $zip = New-F16Zip -Path (Join-Path $TestDrive 'f.zip') -Entries @('TeknoParrot-Manager.ps1', 'a1', 'a2', 'a3', 'a4', 'a5', 'a6', 'a7')
        $result = Test-TpmUpdatePackageIsSingleScript -ZipPath $zip
        $result.SingleScript | Should -BeFalse
        $result.ExtraEntryCount | Should -Be 7
        @($result.ExtraEntrySample).Count | Should -Be 5
    }

    It 'throws when the file cannot be opened as a ZIP' {
        $bad = Join-Path $TestDrive 'b.zip'
        [System.IO.File]::WriteAllBytes($bad, [byte[]](1, 2, 3, 4, 5, 6, 7, 8))
        { Test-TpmUpdatePackageIsSingleScript -ZipPath $bad } | Should -Throw '*could not be opened*'
    }

    It 'throws when the ZIP does not exist' {
        { Test-TpmUpdatePackageIsSingleScript -ZipPath (Join-Path $TestDrive 'none.zip') } | Should -Throw
    }

    It 'counts the alias entry <Extra> next to the exact root script as an extra entry' -TestCases @(
        @{ Extra = './TeknoParrot-Manager.ps1' }
        @{ Extra = '.\TeknoParrot-Manager.ps1' }
        @{ Extra = 'teknoparrot-manager.ps1' }
    ) {
        $zip = New-F16Zip -Path (Join-Path $TestDrive ('alias-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.zip')) -Entries @('TeknoParrot-Manager.ps1', $Extra)
        $result = Test-TpmUpdatePackageIsSingleScript -ZipPath $zip
        $result.SingleScript | Should -BeFalse
        $result.ExtraEntryCount | Should -Be 1
        (@($result.ExtraEntrySample) -join '|') | Should -BeExactly $Extra
    }

    It 'counts a second exact-name root script entry as an extra entry' {
        $zip = New-F16Zip -Path (Join-Path $TestDrive 'dup.zip') -Entries @('TeknoParrot-Manager.ps1', 'TeknoParrot-Manager.ps1')
        $result = Test-TpmUpdatePackageIsSingleScript -ZipPath $zip
        $result.SingleScript | Should -BeFalse
        $result.ExtraEntryCount | Should -Be 1
        (@($result.ExtraEntrySample) -join '|') | Should -BeExactly 'TeknoParrot-Manager.ps1'
        @($result.ExtraEntrySample).Count | Should -Be 1
    }
}

Describe 'Invoke-TpmAutoUpdate.ps1 -Apply multi-file refusal' {
    It 'refuses a multi-file release package, never reports success, and leaves the installed script untouched' {
        $root = Join-Path $TestDrive 'o1'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $scriptPath = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $scriptPath -Value '$ScriptVersion = "0.99.99"' -Encoding ascii
        $originalHash = (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash
        $candidateContent = "# TeknoParrot Manager`n" + '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
        $zipPath = New-F16Zip -Path (Join-Path $root 'c.zip') -Entries @('TeknoParrot-Manager.ps1', 'scripts/TpmProgress.psm1') -ScriptContent $candidateContent
        $orchestratorPath = Join-Path $PSScriptRoot '..\tools\Invoke-TpmAutoUpdate.ps1'
        $saveAssetMock = { return $zipPath }.GetNewClosure()

        Mock Get-LatestRelease {
            [pscustomobject]@{
                tag_name = 'v1.0-RC8'
                assets   = @([pscustomobject]@{
                        name                 = 'TeknoParrot.Manager.v1.0.RC8.zip'
                        browser_download_url = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v1.0-RC8/TeknoParrot.Manager.v1.0.RC8.zip'
                    })
            }
        }
        Mock Save-TpmReleaseAsset $saveAssetMock
        Mock Expand-TpmReleaseZipEntry { throw 'Extraction must not run for a multi-file package.' }
        Mock Move-Item { throw 'Replacement must not run for a multi-file package.' }

        $captured = New-Object System.Collections.Generic.List[string]
        $caught = $null
        try {
            & $orchestratorPath -Apply -Confirm:$false -ScriptPath $scriptPath -Owner 'Jumpstile' -Repository 'teknoparrot-manager' 6>&1 |
                ForEach-Object { $captured.Add([string]$_) }
        } catch {
            $caught = $_
        }

        $caught | Should -Not -BeNullOrEmpty
        $caught.Exception.Message | Should -BeLike '*This release is a multi-file package.*nothing was installed*'
        $caught.Exception.Message | Should -BeLike '*https://github.com/Jumpstile/teknoparrot-manager/releases*'
        $output = $captured -join "`n"
        $output | Should -Match 'This release is a multi-file package\.'
        $output | Should -Not -Match 'Update installed successfully'
        Should -Invoke Save-TpmReleaseAsset -Times 1 -Exactly
        Should -Invoke Expand-TpmReleaseZipEntry -Times 0 -Exactly
        Should -Invoke Move-Item -Times 0 -Exactly
        (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash | Should -Be $originalHash
    }

    It 'refuses the exact entry plus <Extra>, never extracts or replaces, and leaves the installed script untouched' -TestCases @(
        @{ Extra = './TeknoParrot-Manager.ps1' }
        @{ Extra = '.\TeknoParrot-Manager.ps1' }
        @{ Extra = 'teknoparrot-manager.ps1' }
        @{ Extra = 'x/TeknoParrot-Manager.ps1' }
    ) {
        $root = Join-Path $TestDrive ('oa' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $scriptPath = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $scriptPath -Value '$ScriptVersion = "0.99.99"' -Encoding ascii
        $originalHash = (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash
        $candidateContent = "# TeknoParrot Manager`r`n" + '$ScriptVersion = "1.0"' + "`r`n" + '$ReleaseCandidateLabel = "RC8"' + "`r`n"
        $zipPath = New-F21CoreZip -Path (Join-Path $root 'c.zip') -Entries @(
            [pscustomobject]@{ Name = 'TeknoParrot-Manager.ps1'; Text = $candidateContent }
            [pscustomobject]@{ Name = $Extra; Text = $candidateContent }
        )
        $orchestratorPath = Join-Path $PSScriptRoot '..\tools\Invoke-TpmAutoUpdate.ps1'
        $saveAssetMock = { return $zipPath }.GetNewClosure()

        Mock Get-LatestRelease {
            [pscustomobject]@{
                tag_name = 'v1.0-RC8'
                assets   = @([pscustomobject]@{
                        name                 = 'TeknoParrot.Manager.v1.0.RC8.zip'
                        browser_download_url = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v1.0-RC8/TeknoParrot.Manager.v1.0.RC8.zip'
                    })
            }
        }
        Mock Save-TpmReleaseAsset $saveAssetMock
        Mock Expand-TpmReleaseZipEntry { throw 'Extraction must not run for a refused package.' }
        Mock Move-Item { throw 'Replacement must not run for a refused package.' }

        $captured = New-Object System.Collections.Generic.List[string]
        $caught = $null
        try {
            & $orchestratorPath -Apply -Confirm:$false -ScriptPath $scriptPath -Owner 'Jumpstile' -Repository 'teknoparrot-manager' 6>&1 |
                ForEach-Object { $captured.Add([string]$_) }
        } catch {
            $caught = $_
        }

        $caught | Should -Not -BeNullOrEmpty
        $caught.Exception.Message | Should -BeLike 'This release is a multi-file package.*nothing was installed*'
        @($captured | Where-Object { $_ -ceq ('[TeknoParrot Manager updater] Package contains 1 other file(s), for example: ' + $Extra) }).Count | Should -Be 1
        $captured -join "`n" | Should -Not -Match 'Update installed successfully'
        Should -Invoke Save-TpmReleaseAsset -Times 1 -Exactly
        Should -Invoke Expand-TpmReleaseZipEntry -Times 0 -Exactly
        Should -Invoke Move-Item -Times 0 -Exactly
        (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash | Should -Be $originalHash
    }

    It 'refuses two exact-name root script entries, never extracts or replaces, and leaves the installed script untouched' {
        $root = Join-Path $TestDrive ('od' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $scriptPath = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $scriptPath -Value '$ScriptVersion = "0.99.99"' -Encoding ascii
        $originalHash = (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash
        $candidateContent = "# TeknoParrot Manager`r`n" + '$ScriptVersion = "1.0"' + "`r`n" + '$ReleaseCandidateLabel = "RC8"' + "`r`n"
        $zipPath = New-F21CoreZip -Path (Join-Path $root 'c.zip') -Entries @(
            [pscustomobject]@{ Name = 'TeknoParrot-Manager.ps1'; Text = $candidateContent + "# duplicate entry: first`r`n" }
            [pscustomobject]@{ Name = 'TeknoParrot-Manager.ps1'; Text = $candidateContent + "# duplicate entry: second`r`n" }
        )
        $orchestratorPath = Join-Path $PSScriptRoot '..\tools\Invoke-TpmAutoUpdate.ps1'
        $saveAssetMock = { return $zipPath }.GetNewClosure()

        Mock Get-LatestRelease {
            [pscustomobject]@{
                tag_name = 'v1.0-RC8'
                assets   = @([pscustomobject]@{
                        name                 = 'TeknoParrot.Manager.v1.0.RC8.zip'
                        browser_download_url = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v1.0-RC8/TeknoParrot.Manager.v1.0.RC8.zip'
                    })
            }
        }
        Mock Save-TpmReleaseAsset $saveAssetMock
        Mock Expand-TpmReleaseZipEntry { throw 'Extraction must not run for a refused package.' }
        Mock Move-Item { throw 'Replacement must not run for a refused package.' }

        $captured = New-Object System.Collections.Generic.List[string]
        $caught = $null
        try {
            & $orchestratorPath -Apply -Confirm:$false -ScriptPath $scriptPath -Owner 'Jumpstile' -Repository 'teknoparrot-manager' 6>&1 |
                ForEach-Object { $captured.Add([string]$_) }
        } catch {
            $caught = $_
        }

        $caught | Should -Not -BeNullOrEmpty
        $caught.Exception.Message | Should -BeLike 'This release is a multi-file package.*nothing was installed*'
        @($captured | Where-Object { $_ -ceq '[TeknoParrot Manager updater] Package contains 1 other file(s), for example: TeknoParrot-Manager.ps1' }).Count | Should -Be 1
        $captured -join "`n" | Should -Not -Match 'Update installed successfully'
        Should -Invoke Save-TpmReleaseAsset -Times 1 -Exactly
        Should -Invoke Expand-TpmReleaseZipEntry -Times 0 -Exactly
        Should -Invoke Move-Item -Times 0 -Exactly
        (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash | Should -Be $originalHash
    }
}

Describe 'Invoke-TpmAutoUpdate.ps1 -Apply stages beside the script (FIXM2B)' {
    It 'extracts into the script folder and deletes the staged file when validation fails' {
        # Mutation: stage in the TEMP folder again -> the final replace can be a cross-volume copy-then-delete.
        $root = Join-Path $TestDrive ('st' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $scriptPath = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $scriptPath -Value '$ScriptVersion = "0.99.99"' -Encoding ascii
        $zipPath = New-F16Zip -Path (Join-Path $root 'c.zip') -Entries @('TeknoParrot-Manager.ps1')
        $orchestratorPath = Join-Path $PSScriptRoot '..\tools\Invoke-TpmAutoUpdate.ps1'
        $saveAssetMock = { return $zipPath }.GetNewClosure()
        $global:f16StagedPath = $null

        Mock Get-LatestRelease {
            [pscustomobject]@{
                tag_name = 'v1.0-RC8'
                assets   = @([pscustomobject]@{
                        name                 = 'TeknoParrot.Manager.v1.0.RC8.zip'
                        browser_download_url = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v1.0-RC8/TeknoParrot.Manager.v1.0.RC8.zip'
                    })
            }
        }
        Mock Save-TpmReleaseAsset $saveAssetMock
        Mock Expand-TpmReleaseZipEntry { $global:f16StagedPath = $DestinationPath; Set-Content -LiteralPath $DestinationPath -Value 'staged' }
        Mock Test-TpmExtractedScript { throw 'forced validation failure' }

        $caught = $null
        try {
            & $orchestratorPath -Apply -Confirm:$false -ScriptPath $scriptPath -Owner 'Jumpstile' -Repository 'teknoparrot-manager' 6>&1 | Out-Null
        } catch {
            $caught = $_
        }

        $caught | Should -Not -BeNullOrEmpty
        $global:f16StagedPath | Should -Not -BeNullOrEmpty
        [System.IO.Path]::GetDirectoryName($global:f16StagedPath) | Should -BeExactly $root
        Test-Path -LiteralPath $global:f16StagedPath | Should -BeFalse
    }
}

Describe 'New-TpmUpdateBackup unique backup directories' {
    It 'creates distinct directories for two backups in the same second and keeps both copies intact' {
        $root = Join-Path $TestDrive 'b1'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $scriptPath = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $scriptPath -Value '$ScriptVersion = "0.99.38"' -Encoding ascii
        $sourceHash = (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash

        Mock -ModuleName TpmAutoUpdate.Core Get-Date { '20260101-000000' }

        $first = New-TpmUpdateBackup -Path $scriptPath
        $second = New-TpmUpdateBackup -Path $scriptPath

        $firstDir = Split-Path -Parent $first
        $secondDir = Split-Path -Parent $second
        $firstDir | Should -Not -Be $secondDir
        (Split-Path -Leaf $firstDir) | Should -Match '^20260101-000000_[0-9a-f]{32}$'
        (Split-Path -Leaf $secondDir) | Should -Match '^20260101-000000_[0-9a-f]{32}$'
        (Get-FileHash -LiteralPath $first -Algorithm SHA256).Hash | Should -Be $sourceHash
        (Get-FileHash -LiteralPath $second -Algorithm SHA256).Hash | Should -Be $sourceHash
        @(Get-ChildItem -LiteralPath (Join-Path $root 'UpdateBackups') -Directory).Count | Should -Be 2
    }

    It 'refuses to reuse an existing backup directory and leaves its contents untouched' {
        $root = Join-Path $TestDrive 'b2'
        $existingDir = Join-Path (Join-Path $root 'UpdateBackups') 'fixed'
        New-Item -ItemType Directory -Path $existingDir -Force | Out-Null
        $scriptPath = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $scriptPath -Value '$ScriptVersion = "0.99.38"' -Encoding ascii
        $existingBackup = Join-Path $existingDir 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $existingBackup -Value 'earlier backup sentinel' -Encoding ascii
        $existingHash = (Get-FileHash -LiteralPath $existingBackup -Algorithm SHA256).Hash

        Mock -ModuleName TpmAutoUpdate.Core New-TpmUpdateBackupDirectoryName { 'fixed' }

        { New-TpmUpdateBackup -Path $scriptPath } | Should -Throw '*already exists*'
        (Get-FileHash -LiteralPath $existingBackup -Algorithm SHA256).Hash | Should -Be $existingHash
        @(Get-ChildItem -LiteralPath $existingDir -Force).Count | Should -Be 1
        @(Get-ChildItem -LiteralPath (Join-Path $root 'UpdateBackups') -Directory).Count | Should -Be 1
    }

    It 'throws before creating anything when the source file does not exist' {
        $root = Join-Path $TestDrive 'b3'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        { New-TpmUpdateBackup -Path (Join-Path $root 'TeknoParrot-Manager.ps1') } | Should -Throw '*source file not found*'
        Test-Path -LiteralPath (Join-Path $root 'UpdateBackups') | Should -BeFalse
    }
}

Describe 'Get-TpmResponseContentLength' {
    It 'returns 0 when Content-Length is absent, under strict mode' {
        InModuleScope TpmAutoUpdate.Core {
            Set-StrictMode -Version Latest
            $fake = [pscustomobject]@{ Content = [pscustomobject]@{ Headers = [pscustomobject]@{ ContentLength = $null } } }
            Get-TpmResponseContentLength -Response $fake | Should -Be 0
        }
    }

    It 'returns the declared length when Content-Length is present' {
        InModuleScope TpmAutoUpdate.Core {
            Set-StrictMode -Version Latest
            $fake = [pscustomobject]@{ Content = [pscustomobject]@{ Headers = [pscustomobject]@{ ContentLength = [Nullable[long]]1234 } } }
            $length = Get-TpmResponseContentLength -Response $fake
            $length | Should -Be 1234
            $length | Should -BeOfType ([long])
        }
    }
}

Describe 'Invoke-TpmDownloadBitTransfer no-progress guard' {
    It 'uses a 120-second no-progress window by default' {
        InModuleScope TpmAutoUpdate.Core {
            $script:TpmDownloadNoProgressTimeoutSeconds | Should -Be 120
        }
    }

    It 'cancels a BITS job that makes no progress and throws so the next tier runs' -Skip:(-not (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue)) {
        InModuleScope TpmAutoUpdate.Core -Parameters @{ Td = $TestDrive } {
            param($Td)
            $savedTimeout = $script:TpmDownloadNoProgressTimeoutSeconds
            $script:TpmDownloadNoProgressTimeoutSeconds = 0
            try {
                Mock Start-BitsTransfer {
                    [pscustomobject]@{ JobId = [guid]'11111111-1111-1111-1111-111111111111'; JobState = 'TransientError'; BytesTransferred = [uint64]0; BytesTotal = [uint64]::MaxValue }
                }
                Mock Get-BitsTransfer {
                    [pscustomobject]@{ JobId = [guid]'11111111-1111-1111-1111-111111111111'; JobState = 'TransientError'; BytesTransferred = [uint64]0; BytesTotal = [uint64]::MaxValue }
                }
                Mock Complete-BitsTransfer { throw 'A stalled job must not be completed.' } -RemoveParameterType 'BitsJob'
                Mock Remove-BitsTransfer {} -RemoveParameterType 'BitsJob'
                Mock Start-Sleep {}
                Mock Write-TpmDownloadProgress {}

                { Invoke-TpmDownloadBitTransfer -DownloadUrl 'https://example.invalid/p.zip' -TempPath (Join-Path $Td 'p.partial') -Label 'test' } |
                    Should -Throw '*no progress*'
                Should -Invoke Remove-BitsTransfer -Times 1 -Exactly
                Should -Invoke Complete-BitsTransfer -Times 0 -Exactly
            } finally {
                $script:TpmDownloadNoProgressTimeoutSeconds = $savedTimeout
            }
        }
    }
}
