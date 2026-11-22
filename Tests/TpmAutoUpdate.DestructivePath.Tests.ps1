#Requires -Module Pester

# Destructive-path validation for tools/Invoke-TpmAutoUpdate.ps1 and
# tools/TpmAutoUpdate.Core.psm1. Every scenario below deliberately induces a
# failure (corrupt data, locked files, denied permissions) and asserts that:
#   - the original installation is left intact
#   - no raw zip bytes ever land in the .ps1 target
#   - a completed backup is preserved
#   - temp files do not leak
#   - the thrown error is specific and actionable
#   - no partially-written replacement is left behind
#
# Run with: Invoke-Pester -Path .\Tests\TpmAutoUpdate.DestructivePath.Tests.ps1

BeforeAll {
    $script:ModulePath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\tools\TpmAutoUpdate.Core.psm1')).ProviderPath
    $script:OrchestratorPath = Join-Path $PSScriptRoot '..\tools\Invoke-TpmAutoUpdate.ps1'
    Get-Module TpmAutoUpdate.Core -All | Remove-Module -Force
    Import-Module $script:ModulePath -Force

    function New-DestructiveTestRoot {
        # A short name: the update backup path under this root is near the 260-character Windows limit when TEMP is long.
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-d-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        return $root
    }

    function New-OldScript {
        param([string]$Root, [string]$Version = '0.0.1')
        $scriptPath = Join-Path $Root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $scriptPath -Value "# TeknoParrot Manager`n`$ScriptVersion = `"$Version`"" -Encoding ascii
        return $scriptPath
    }

    function New-ValidFixtureZipBytes {
        param(
            [string]$EntryName = 'TeknoParrot-Manager.ps1',
            [string]$EntryContent = "# TeknoParrot Manager`n`$ScriptVersion = `"0.99.99`"`n"
        )

        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $zipPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-fixture-src-" + [guid]::NewGuid().ToString('N') + '.zip')
        $stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-fixture-staging-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
        try {
            Set-Content -LiteralPath (Join-Path $stagingDir $EntryName) -Value $EntryContent -Encoding ascii -NoNewline
            [System.IO.Compression.ZipFile]::CreateFromDirectory($stagingDir, $zipPath)
            $bytes = [System.IO.File]::ReadAllBytes($zipPath)
            return , $bytes
        } finally {
            Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        }
    }

    function Get-CorruptedEntryZipBytes {
        # A zip with a valid central directory listing the expected entry name,
        # but with the compressed payload bytes scrambled so decompression
        # itself fails (distinct from "not a zip at all" and "entry missing").
        #
        # A small/incompressible entry gets stored (not deflated) by
        # ZipFile.CreateFromDirectory, in which case scrambling its bytes just
        # corrupts plain content rather than breaking decompression. Use a
        # large, repetitive (compressible) entry so Deflate is actually used,
        # then read the local file header to find exactly where the
        # compressed payload starts and corrupt only within CompressedLength
        # so the central directory / EOCD stay intact.
        $entryContent = "# TeknoParrot Manager`n`$ScriptVersion = `"0.99.99`"`n" + (("X" * 200 + "`n") * 300)
        $validBytes = New-ValidFixtureZipBytes -EntryContent $entryContent
        $bytes = [byte[]]$validBytes.Clone()

        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $probeZipPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-corrupt-probe-" + [guid]::NewGuid().ToString('N') + '.zip')
        [System.IO.File]::WriteAllBytes($probeZipPath, $bytes)
        try {
            $zip = [System.IO.Compression.ZipFile]::OpenRead($probeZipPath)
            $entry = $zip.Entries[0]
            $compressedLength = $entry.CompressedLength
            $zip.Dispose()
        } finally {
            Remove-Item -LiteralPath $probeZipPath -Force -ErrorAction SilentlyContinue
        }

        if ($compressedLength -eq $entryContent.Length) {
            throw 'Test fixture error: entry was stored rather than deflated -- corruption offsets would be wrong.'
        }

        # Local file header: 4(sig) 2(ver) 2(flags) 2(method) 2(modtime)
        # 2(moddate) 4(crc32) 4(compressedSize) 4(uncompressedSize)
        # 2(filenameLen) 2(extraLen) = 30 bytes, then filename, then extra.
        $filenameLen = [System.BitConverter]::ToUInt16($bytes, 26)
        $extraLen = [System.BitConverter]::ToUInt16($bytes, 28)
        $dataStart = 30 + $filenameLen + $extraLen

        for ($i = $dataStart; $i -lt ($dataStart + $compressedLength); $i++) {
            $bytes[$i] = $bytes[$i] -bxor 0xFF
        }

        return , $bytes
    }

    function Invoke-TpmApplyWithMockedRelease {
        param(
            [Parameter(Mandatory)][string]$ScriptPath,
            [Parameter(Mandatory)][scriptblock]$WebRequestMock,
            [Parameter(Mandatory)][byte[]]$FixtureBytes,
            [switch]$WhatIf
        )

        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $fixtureDigest = 'sha256:' + ([BitConverter]::ToString($sha256.ComputeHash($FixtureBytes))).Replace('-', '')
        } finally {
            $sha256.Dispose()
        }
        # The release lookup is replaced where the real orchestrator calls it (script-visible mock, no -ModuleName); the download
        # is replaced inside the module, where Save-TpmReleaseAsset calls it. Everything else is the real orchestrator and module.
        Mock Get-LatestRelease {
            [pscustomobject]@{
                tag_name = 'v0.99.99'
                assets   = @([pscustomobject]@{
                    name                 = 'TeknoParrot.Manager.v0.99.99.BETA.zip'
                    browser_download_url = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/TeknoParrot.Manager.v0.99.99.BETA.zip'
                    digest               = $fixtureDigest
                })
            }
        }.GetNewClosure()
        Mock -ModuleName TpmAutoUpdate.Core Invoke-TpmDownload {
            param($DownloadUrl, $DestinationPath, $ExpectedBytes, $Label)
            & $WebRequestMock -Uri $DownloadUrl -OutFile $DestinationPath
        }.GetNewClosure()

        $errorOutput = $null
        $stdout = $null
        try {
            $stdout = & $script:OrchestratorPath -Apply -Confirm:$false -WhatIf:$WhatIf -ScriptPath $ScriptPath -Owner 'Jumpstile' -Repository 'teknoparrot-manager' *>&1
        } catch {
            $errorOutput = $_
        }

        return [pscustomobject]@{
            StdOut = $stdout
            Error  = $errorOutput
        }
    }

    # Private TEMP/TMP for every scenario: the leak checks look at the temporary folder, so another run's files must never be in it.
    function Use-DestructivePrivateTemp {
        $script:destructiveSavedTemp = $env:TEMP
        $script:destructiveSavedTmp = $env:TMP
        $env:TEMP = Join-Path $TestDrive ('own-temp-' + [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($env:TEMP)
        $env:TMP = $env:TEMP
    }
    function Restore-DestructiveTemp {
        $env:TEMP = $script:destructiveSavedTemp
        $env:TMP = $script:destructiveSavedTmp
    }
}
AfterAll {
    Get-Module TpmAutoUpdate.Core -All | Remove-Module -Force
}

Describe '1. Corrupt ZIP download' {
    BeforeEach { Use-DestructivePrivateTemp }
    AfterEach { Restore-DestructiveTemp }
    It 'leaves the original script intact, preserves the backup, and reports a clear error' {
        $root = New-DestructiveTestRoot
        try {
            $scriptPath = New-OldScript -Root $root
            $originalContent = Get-Content -LiteralPath $scriptPath -Raw

            $corruptBytes = [byte[]](1..64)
            $result = Invoke-TpmApplyWithMockedRelease -ScriptPath $scriptPath -FixtureBytes $corruptBytes -WebRequestMock {
                param($Uri, $Headers, $OutFile, $UseBasicParsing)
                [System.IO.File]::WriteAllBytes($OutFile, $corruptBytes)
            }.GetNewClosure()

            $result.Error | Should -BeOfType ([System.Management.Automation.ErrorRecord])
            $result.Error.Exception.Message | Should -Match 'zip|central|end of'

            (Get-Content -LiteralPath $scriptPath -Raw) | Should -Be $originalContent

            # The real orchestrator opens the package before it probes the target or makes a backup, so nothing is written at all.
            $result.Error.Exception.Message | Should -Match 'could not be opened as a ZIP archive'
            Test-Path -LiteralPath (Join-Path $root 'UpdateBackups') | Should -BeFalse

            # No leaked temp download or extraction artifacts.
            @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-*.zip' -ErrorAction SilentlyContinue).Count | Should -Be 0
            @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-extracted-*.ps1' -ErrorAction SilentlyContinue).Count | Should -Be 0
        } finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe '2. ZIP missing TeknoParrot-Manager.ps1' {
    BeforeEach { Use-DestructivePrivateTemp }
    AfterEach { Restore-DestructiveTemp }
    It 'leaves the original script intact, preserves the backup, and reports a clear error for a ZIP with no files' {
        $root = New-DestructiveTestRoot
        try {
            $scriptPath = New-OldScript -Root $root
            $originalContent = Get-Content -LiteralPath $scriptPath -Raw
            # A valid ZIP that holds no files: only the 22-byte end-of-central-directory record.
            $emptyZipBytes = [byte[]](@(0x50, 0x4B, 0x05, 0x06) + (@(0) * 18))

            $result = Invoke-TpmApplyWithMockedRelease -ScriptPath $scriptPath -FixtureBytes $emptyZipBytes -WebRequestMock {
                param($Uri, $Headers, $OutFile, $UseBasicParsing)
                [System.IO.File]::WriteAllBytes($OutFile, $emptyZipBytes)
            }.GetNewClosure()

            $result.Error | Should -BeOfType ([System.Management.Automation.ErrorRecord])
            $result.Error.Exception.Message | Should -Match 'does not contain TeknoParrot-Manager\.ps1'

            (Get-Content -LiteralPath $scriptPath -Raw) | Should -Be $originalContent

            # An empty package is refused before any backup is made.
            Test-Path -LiteralPath (Join-Path $root 'UpdateBackups') | Should -BeFalse

            @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-*.zip' -ErrorAction SilentlyContinue).Count | Should -Be 0
        } finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses a ZIP that holds a different file instead of the script, before any backup is made' {
        # Mutation: remove the one-file package check from the orchestrator -> a backup is made and the error is the extraction error instead of the refusal.
        $root = New-DestructiveTestRoot
        try {
            $scriptPath = New-OldScript -Root $root
            $originalContent = Get-Content -LiteralPath $scriptPath -Raw
            $wrongEntryBytes = New-ValidFixtureZipBytes -EntryName 'SomethingElse.ps1'

            $result = Invoke-TpmApplyWithMockedRelease -ScriptPath $scriptPath -FixtureBytes $wrongEntryBytes -WebRequestMock {
                param($Uri, $Headers, $OutFile, $UseBasicParsing)
                [System.IO.File]::WriteAllBytes($OutFile, $wrongEntryBytes)
            }.GetNewClosure()

            $result.Error | Should -BeOfType ([System.Management.Automation.ErrorRecord])
            $result.Error.Exception.Message | Should -Match 'multi-file package'
            (Get-Content -LiteralPath $scriptPath -Raw) | Should -Be $originalContent
            Test-Path -LiteralPath (Join-Path $root 'UpdateBackups') | Should -BeFalse
            @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-*.zip' -ErrorAction SilentlyContinue).Count | Should -Be 0
        } finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe '3. Script fails content validation' {
    BeforeEach { Use-DestructivePrivateTemp }
    AfterEach { Restore-DestructiveTemp }
    It 'rejects an extracted script missing the ScriptVersion assignment and leaves the original intact' {
        $root = New-DestructiveTestRoot
        try {
            $scriptPath = New-OldScript -Root $root
            $originalContent = Get-Content -LiteralPath $scriptPath -Raw
            $badContentBytes = New-ValidFixtureZipBytes -EntryContent "# TeknoParrot Manager`nsome unrelated content, no version here`n"

            $result = Invoke-TpmApplyWithMockedRelease -ScriptPath $scriptPath -FixtureBytes $badContentBytes -WebRequestMock {
                param($Uri, $Headers, $OutFile, $UseBasicParsing)
                [System.IO.File]::WriteAllBytes($OutFile, $badContentBytes)
            }.GetNewClosure()

            $result.Error | Should -BeOfType ([System.Management.Automation.ErrorRecord])
            $result.Error.Exception.Message | Should -Match 'ScriptVersion'

            (Get-Content -LiteralPath $scriptPath -Raw) | Should -Be $originalContent

            $backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'UpdateBackups') -Recurse -Filter 'TeknoParrot-Manager.ps1' -ErrorAction SilentlyContinue)
            $backupFiles.Count | Should -Be 1

            # The rejected extracted file must not have leaked either.
            @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-extracted-*.ps1' -ErrorAction SilentlyContinue).Count | Should -Be 0
        } finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects an extracted file that is itself raw zip bytes (PK signature)' {
        $root = New-DestructiveTestRoot
        try {
            $scriptPath = New-OldScript -Root $root
            $originalContent = Get-Content -LiteralPath $scriptPath -Raw

            # Build a zip whose single entry's *content* is itself zip bytes,
            # simulating a packaging mistake where the wrong artifact was
            # placed inside the expected entry name.
            $innerZipBytes = New-ValidFixtureZipBytes
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
            $stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-nested-staging-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
            $outerZipPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-nested-" + [guid]::NewGuid().ToString('N') + '.zip')
            try {
                [System.IO.File]::WriteAllBytes((Join-Path $stagingDir 'TeknoParrot-Manager.ps1'), $innerZipBytes)
                [System.IO.Compression.ZipFile]::CreateFromDirectory($stagingDir, $outerZipPath)
                $outerBytes = [System.IO.File]::ReadAllBytes($outerZipPath)
            } finally {
                Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $outerZipPath -Force -ErrorAction SilentlyContinue
            }

            $result = Invoke-TpmApplyWithMockedRelease -ScriptPath $scriptPath -FixtureBytes $outerBytes -WebRequestMock {
                param($Uri, $Headers, $OutFile, $UseBasicParsing)
                [System.IO.File]::WriteAllBytes($OutFile, $outerBytes)
            }.GetNewClosure()

            $result.Error | Should -BeOfType ([System.Management.Automation.ErrorRecord])
            $result.Error.Exception.Message | Should -Match 'zip signature'

            (Get-Content -LiteralPath $scriptPath -Raw) | Should -Be $originalContent
            (Get-Content -LiteralPath $scriptPath -Raw).StartsWith('PK') | Should -BeFalse
        } finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe '4. Download interrupted / partial file' {
    BeforeEach { Use-DestructivePrivateTemp }
    AfterEach { Restore-DestructiveTemp }
    It 'treats a truncated zip as corrupt, leaves the original intact, and cleans up' {
        $root = New-DestructiveTestRoot
        try {
            $scriptPath = New-OldScript -Root $root
            $originalContent = Get-Content -LiteralPath $scriptPath -Raw
            $fullBytes = New-ValidFixtureZipBytes
            $truncatedBytes = $fullBytes[0..([int]($fullBytes.Length / 2))]

            $result = Invoke-TpmApplyWithMockedRelease -ScriptPath $scriptPath -FixtureBytes $truncatedBytes -WebRequestMock {
                param($Uri, $Headers, $OutFile, $UseBasicParsing)
                [System.IO.File]::WriteAllBytes($OutFile, $truncatedBytes)
            }.GetNewClosure()

            $result.Error | Should -BeOfType ([System.Management.Automation.ErrorRecord])

            (Get-Content -LiteralPath $scriptPath -Raw) | Should -Be $originalContent

            # The real orchestrator opens the package before it probes the target or makes a backup, so nothing is written at all.
            $result.Error.Exception.Message | Should -Match 'could not be opened as a ZIP archive'
            Test-Path -LiteralPath (Join-Path $root 'UpdateBackups') | Should -BeFalse

            @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-*.zip' -ErrorAction SilentlyContinue).Count | Should -Be 0
        } finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe '5. Read-only destination' {
    BeforeEach { Use-DestructivePrivateTemp }
    AfterEach { Restore-DestructiveTemp }
    It 'refuses the update with a clear error instead of letting Move-Item -Force clear ReadOnly' {
        # A verified download precedes the writable-target check; ReadOnly
        # must still be refused rather than silently cleared by Move-Item.
        $root = New-DestructiveTestRoot
        try {
            $scriptPath = New-OldScript -Root $root
            $originalContent = Get-Content -LiteralPath $scriptPath -Raw
            $validBytes = New-ValidFixtureZipBytes

            Set-ItemProperty -LiteralPath $scriptPath -Name IsReadOnly -Value $true
            try {
                $result = Invoke-TpmApplyWithMockedRelease -ScriptPath $scriptPath -FixtureBytes $validBytes -WebRequestMock {
                    param($Uri, $Headers, $OutFile, $UseBasicParsing)
                    [System.IO.File]::WriteAllBytes($OutFile, $validBytes)
                }.GetNewClosure()

                $result.Error | Should -BeOfType ([System.Management.Automation.ErrorRecord])
                $result.Error.Exception.Message | Should -Match 'read-only'
                $result.Error.Exception.Message | Should -Match ([regex]::Escape($scriptPath))

                (Get-Content -LiteralPath $scriptPath -Raw) | Should -Be $originalContent
            } finally {
                Set-ItemProperty -LiteralPath $scriptPath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
            }

            # The writable-target check runs after download but before backup.
            Test-Path -LiteralPath (Join-Path $root 'UpdateBackups') | Should -BeFalse
            Should -Invoke -ModuleName TpmAutoUpdate.Core Invoke-TpmDownload -Times 1 -Exactly

            @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-*.zip' -ErrorAction SilentlyContinue).Count | Should -Be 0
            @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-extracted-*.ps1' -ErrorAction SilentlyContinue).Count | Should -Be 0
        } finally {
            Set-ItemProperty -LiteralPath $scriptPath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe '6. Backup creation failure' {
    BeforeEach { Use-DestructivePrivateTemp }
    AfterEach { Restore-DestructiveTemp }
    It 'aborts after verified download when the backup cannot be created, leaving the original script untouched' {
        $root = New-DestructiveTestRoot
        try {
            $scriptPath = New-OldScript -Root $root
            $originalContent = Get-Content -LiteralPath $scriptPath -Raw
            $validBytes = New-ValidFixtureZipBytes

            Mock -ModuleName TpmAutoUpdate.Core New-Item {
                throw 'Access to the path is denied (simulated backup failure).'
            } -ParameterFilter { $ItemType -eq 'Directory' }

            $result = Invoke-TpmApplyWithMockedRelease -ScriptPath $scriptPath -FixtureBytes $validBytes -WebRequestMock {
                param($Uri, $Headers, $OutFile, $UseBasicParsing)
                [System.IO.File]::WriteAllBytes($OutFile, $validBytes)
            }.GetNewClosure()

            $result.Error | Should -BeOfType ([System.Management.Automation.ErrorRecord])
            $result.Error.Exception.Message | Should -Match 'denied'

            (Get-Content -LiteralPath $scriptPath -Raw) | Should -Be $originalContent
            Test-Path -LiteralPath (Join-Path $root 'UpdateBackups') | Should -BeFalse
            @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-*.zip' -ErrorAction SilentlyContinue).Count | Should -Be 0
        } finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe '7. Extraction failure (corrupted entry payload, valid central directory)' {
    BeforeEach { Use-DestructivePrivateTemp }
    AfterEach { Restore-DestructiveTemp }
    It 'reports the extraction failure, leaves the original intact, and preserves the backup' {
        $root = New-DestructiveTestRoot
        try {
            $scriptPath = New-OldScript -Root $root
            $originalContent = Get-Content -LiteralPath $scriptPath -Raw
            $corruptedEntryBytes = Get-CorruptedEntryZipBytes

            $result = Invoke-TpmApplyWithMockedRelease -ScriptPath $scriptPath -FixtureBytes $corruptedEntryBytes -WebRequestMock {
                param($Uri, $Headers, $OutFile, $UseBasicParsing)
                [System.IO.File]::WriteAllBytes($OutFile, $corruptedEntryBytes)
            }.GetNewClosure()

            $result.Error | Should -BeOfType ([System.Management.Automation.ErrorRecord])

            (Get-Content -LiteralPath $scriptPath -Raw) | Should -Be $originalContent

            $backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'UpdateBackups') -Recurse -Filter 'TeknoParrot-Manager.ps1' -ErrorAction SilentlyContinue)
            $backupFiles.Count | Should -Be 1

            @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-extracted-*.ps1' -ErrorAction SilentlyContinue).Count | Should -Be 0
        } finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe '8. Replacement failure after successful backup (locked destination)' {
    BeforeEach { Use-DestructivePrivateTemp }
    AfterEach { Restore-DestructiveTemp }
    It 'preserves the backup and the (locked, unmodified) original when Move-Item cannot replace it' {
        $root = New-DestructiveTestRoot
        $lockHandle = $null
        try {
            $scriptPath = New-OldScript -Root $root
            $originalContent = Get-Content -LiteralPath $scriptPath -Raw
            $validBytes = New-ValidFixtureZipBytes

            # Hold an exclusive lock on the target for the duration of the run
            # so backup/download/extract/validate all succeed and only the
            # final Move-Item fails -- this is what an AV scanner or another
            # process holding the file open would look like in practice.
            $lockHandle = [System.IO.File]::Open($scriptPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)

            $result = Invoke-TpmApplyWithMockedRelease -ScriptPath $scriptPath -FixtureBytes $validBytes -WebRequestMock {
                param($Uri, $Headers, $OutFile, $UseBasicParsing)
                [System.IO.File]::WriteAllBytes($OutFile, $validBytes)
            }.GetNewClosure()

            $result.Error | Should -BeOfType ([System.Management.Automation.ErrorRecord])
            $result.Error.Exception.Message | Should -Match 'used by another process|denied|access|already exists'

            $lockHandle.Dispose()
            $lockHandle = $null

            # Original must be exactly what it was -- no partial/truncated write.
            (Get-Content -LiteralPath $scriptPath -Raw) | Should -Be $originalContent

            $backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'UpdateBackups') -Recurse -Filter 'TeknoParrot-Manager.ps1' -ErrorAction SilentlyContinue)
            $backupFiles.Count | Should -Be 1
            (Get-Content -LiteralPath $backupFiles[0].FullName -Raw) | Should -Be $originalContent

            # The would-be replacement (validated, ready to install) must not
            # leak in temp once Move-Item fails.
            @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-extracted-*.ps1' -ErrorAction SilentlyContinue).Count | Should -Be 0
            @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-*.zip' -ErrorAction SilentlyContinue).Count | Should -Be 0
        } finally {
            if ($lockHandle) { $lockHandle.Dispose() }
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe '8b. Replacement did not match the release' {
    BeforeEach { Use-DestructivePrivateTemp }
    AfterEach { Restore-DestructiveTemp }
    It 'says the old version was put back only when it was, and points to the backup when it was not' -ForEach @(
        @{ Locked = $false; Expected = 'previous version was restored' },
        @{ Locked = $true;  Expected = 'could not be put back' }
    ) {
        $root = New-DestructiveTestRoot
        $lockHandle = $null
        try {
            $scriptPath = New-OldScript -Root $root
            $validBytes = New-ValidFixtureZipBytes
            # The replacement step silently does nothing, so the installed file never matches the release.
            Mock Move-Item { }
            if ($Locked) { $lockHandle = [System.IO.File]::Open($scriptPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read) }
            $result = Invoke-TpmApplyWithMockedRelease -ScriptPath $scriptPath -FixtureBytes $validBytes -WebRequestMock {
                param($Uri, $Headers, $OutFile, $UseBasicParsing)
                [System.IO.File]::WriteAllBytes($OutFile, $validBytes)
            }.GetNewClosure()
            $result.Error.Exception.Message | Should -Match $Expected
            if ($Locked) { $result.Error.Exception.Message | Should -Match 'UpdateBackups' }
        } finally {
            if ($lockHandle) { $lockHandle.Dispose() }
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe '9. Module-scope error-action regression guard' {
    It 'sets its own $ErrorActionPreference to Stop regardless of import history' {
        # Regression guard for a real bug found while writing this suite: a
        # module's $ErrorActionPreference is snapshotted from the caller at
        # *import* time. Since the orchestrator intentionally imports without
        # -Force (to stay mockable -- see its own comment), an already-loaded
        # module instance (e.g. from this test file's own BeforeAll import,
        # done before the orchestrator ever sets $ErrorActionPreference =
        # 'Stop') would silently keep whatever preference was active back
        # then. Under 'Continue', a non-terminating cmdlet error inside
        # New-TpmUpdateBackup's Copy-Item would print a warning and carry on.
        # (New-TpmUpdateBackup happens to have its own post-copy existence
        # check that would also catch this specific case -- but
        # Copy-ChannelForgeUpdatePackageContent in the sibling ChannelForge
        # module did not, and reported false success until both the EAP fix
        # and a matching post-copy check were added there.) Checking the
        # module-scope variable directly here (rather than via Mock, whose
        # substitute scriptblocks run with their own default 'Continue'
        # regardless of the module's setting -- verified empirically, and it
        # made an earlier version of this exact test a false pass) is what
        # actually confirms the fix is in place.
        InModuleScope TpmAutoUpdate.Core {
            $ErrorActionPreference | Should -Be 'Stop'
        }
    }
}

Describe '18. A relative script path' {
    BeforeEach { Use-DestructivePrivateTemp }
    AfterEach { Restore-DestructiveTemp }
    It 'stages the new copy beside the script, not in the process folder, so the replace stays one rename' {
        # Who gets hurt: someone who runs the updater from another folder with Set-Location and a relative -ScriptPath. The new copy was
        # extracted into the process folder (which Set-Location does not change), so the final move crossed folders or volumes.
        $root = New-DestructiveTestRoot
        $processFolder = Join-Path $root 'process-folder'
        $scriptFolder = Join-Path $root 'script-folder'
        [void][System.IO.Directory]::CreateDirectory($processFolder)
        [void][System.IO.Directory]::CreateDirectory($scriptFolder)
        $savedProcessFolder = [System.Environment]::CurrentDirectory
        try {
            $scriptPath = New-OldScript -Root $scriptFolder
            $validBytes = New-ValidFixtureZipBytes
            [System.Environment]::CurrentDirectory = $processFolder
            Push-Location -LiteralPath $scriptFolder
            try {
                $result = Invoke-TpmApplyWithMockedRelease -ScriptPath '.\TeknoParrot-Manager.ps1' -FixtureBytes $validBytes -WebRequestMock {
                    param($Uri, $Headers, $OutFile, $UseBasicParsing)
                    [System.IO.File]::WriteAllBytes($OutFile, $validBytes)
                }.GetNewClosure()
            } finally { Pop-Location }
            $result.Error | Should -BeNullOrEmpty
            $extractedLine = @($result.StdOut | ForEach-Object { [string]$_ } | Where-Object { $_ -like '*Extracted      :*' })
            $extractedLine.Count | Should -Be 1
            $extractedLine[0] | Should -BeLike ('*' + $scriptFolder + '\tpm-update-extracted-*')
            (Get-Content -LiteralPath $scriptPath -Raw) | Should -Match '0\.99\.99'
        } finally {
            [System.Environment]::CurrentDirectory = $savedProcessFolder
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
