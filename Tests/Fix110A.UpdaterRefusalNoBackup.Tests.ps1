#Requires -Module Pester

# FIX110A / S-24: the standalone updater (tools/Invoke-TpmAutoUpdate.ps1 -Apply) refuses a
# multi-file release package before it probes the install target or makes a backup, so a
# refusal changes nothing on disk (docs/AUTO_UPDATE.md promises this).

BeforeAll {
    $modulePath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\tools\TpmAutoUpdate.Core.psm1')).ProviderPath
    Get-Module TpmAutoUpdate.Core -All | Remove-Module -Force
    Import-Module $modulePath -Force

    function New-F110Zip {
        param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string[]]$Entries, [Parameter(Mandatory)][string]$ScriptContent)
        Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $archive = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($name in $Entries) {
                $entry = $archive.CreateEntry($name)
                $writer = New-Object System.IO.StreamWriter($entry.Open())
                try { $writer.Write($ScriptContent) } finally { $writer.Dispose() }
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

Describe 'Invoke-TpmAutoUpdate.ps1 -Apply refusal changes nothing on disk' {
    It 'refuses a multi-file package without probing the target or creating any backup, even when asked twice' {
        # Mutation: move Assert-TpmWritableTarget / New-TpmUpdateBackup back above Test-TpmUpdatePackageIsSingleScript
        # -> an UpdateBackups folder appears after the refusal and both mocks are called.
        $root = Join-Path $TestDrive 'r1'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $scriptPath = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $scriptPath -Value '$ScriptVersion = "0.99.99"' -Encoding ascii
        $originalHash = (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash
        $candidateContent = "# TeknoParrot Manager`n" + '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
        $sourceZip = New-F110Zip -Path (Join-Path $TestDrive 'src1.zip') -Entries @('TeknoParrot-Manager.ps1', 'scripts/TpmProgress.psm1') -ScriptContent $candidateContent
        $orchestratorPath = Join-Path $PSScriptRoot '..\tools\Invoke-TpmAutoUpdate.ps1'
        # The updater deletes the file Save-TpmReleaseAsset returns, so every download is a fresh copy.
        $saveAssetMock = { $copy = Join-Path $TestDrive ('dl-' + [guid]::NewGuid().ToString('N') + '.zip'); Copy-Item -LiteralPath $sourceZip -Destination $copy; return $copy }.GetNewClosure()

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
        Mock Assert-TpmWritableTarget { }
        Mock New-TpmUpdateBackup { throw 'No backup may be made for a refused package.' }
        Mock Expand-TpmReleaseZipEntry { throw 'Extraction must not run for a refused package.' }

        foreach ($attempt in 1..2) {
            $caught = $null
            try {
                & $orchestratorPath -Apply -Confirm:$false -ScriptPath $scriptPath -Owner 'Jumpstile' -Repository 'teknoparrot-manager' 6>&1 | Out-Null
            } catch {
                $caught = $_
            }
            $caught | Should -Not -BeNullOrEmpty
            $caught.Exception.Message | Should -BeLike 'This release is a multi-file package.*nothing was installed*'
        }

        Should -Invoke Save-TpmReleaseAsset -Times 2 -Exactly
        Should -Invoke Assert-TpmWritableTarget -Times 0 -Exactly
        Should -Invoke New-TpmUpdateBackup -Times 0 -Exactly
        Should -Invoke Expand-TpmReleaseZipEntry -Times 0 -Exactly
        Test-Path -LiteralPath (Join-Path $root 'UpdateBackups') | Should -BeFalse
        (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash | Should -Be $originalHash
        (@(Get-ChildItem -LiteralPath $root -Force | ForEach-Object { $_.Name }) -join '|') | Should -BeExactly 'TeknoParrot-Manager.ps1'
    }

    It 'still probes the target and makes the verified backup for a single-script package' {
        # Mutation: drop the backup step or the writable-target probe for accepted packages -> a call count below 1.
        $root = Join-Path $TestDrive 'r2'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $scriptPath = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $scriptPath -Value '$ScriptVersion = "0.99.99"' -Encoding ascii
        $candidateContent = "# TeknoParrot Manager`n" + '$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"'
        $sourceZip = New-F110Zip -Path (Join-Path $TestDrive 'src2.zip') -Entries @('TeknoParrot-Manager.ps1') -ScriptContent $candidateContent
        $orchestratorPath = Join-Path $PSScriptRoot '..\tools\Invoke-TpmAutoUpdate.ps1'
        $saveAssetMock = { $copy = Join-Path $TestDrive ('dl-' + [guid]::NewGuid().ToString('N') + '.zip'); Copy-Item -LiteralPath $sourceZip -Destination $copy; return $copy }.GetNewClosure()

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
        Mock Assert-TpmWritableTarget { }
        Mock New-TpmUpdateBackup { return 'backup-path-from-mock' }
        Mock Expand-TpmReleaseZipEntry { throw 'stop after the backup step' }

        $caught = $null
        try {
            & $orchestratorPath -Apply -Confirm:$false -ScriptPath $scriptPath -Owner 'Jumpstile' -Repository 'teknoparrot-manager' 6>&1 | Out-Null
        } catch {
            $caught = $_
        }
        $caught.Exception.Message | Should -BeLike '*stop after the backup step*'
        Should -Invoke Assert-TpmWritableTarget -Times 1 -Exactly
        Should -Invoke New-TpmUpdateBackup -Times 1 -Exactly
    }
}
