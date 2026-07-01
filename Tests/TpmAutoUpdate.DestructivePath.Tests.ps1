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
    $script:ModulePath = Join-Path $PSScriptRoot '..\tools\TpmAutoUpdate.Core.psm1'
    $script:OrchestratorPath = Join-Path $PSScriptRoot '..\tools\Invoke-TpmAutoUpdate.ps1'
    Import-Module $script:ModulePath -Force

    function New-DestructiveTestRoot {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-destructive-" + [guid]::NewGuid().ToString('N'))
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
            [switch]$WhatIf
        )

        Mock -ModuleName TpmAutoUpdate.Core Get-LatestRelease {
            [pscustomobject]@{
                tag_name = 'v0.99.99'
                assets   = @([pscustomobject]@{
                    name                 = 'TeknoParrot.Manager.v0.99.99.BETA.zip'
                    browser_download_url = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/TeknoParrot.Manager.v0.99.99.BETA.zip'
                })
            }
        }
        Mock -ModuleName TpmAutoUpdate.Core Invoke-WebRequest $WebRequestMock

        $params = @{
            Apply      = $true
            ScriptPath = $ScriptPath
            Owner      = 'Jumpstile'
            Repository = 'teknoparrot-manager'
        }
        if ($WhatIf) { $params['WhatIf'] = $true }

        $errorOutput = $null
        $stdout = $null
        try {
            $stdout = & $script:OrchestratorPath @params 2>&1
        } catch {
            $errorOutput = $_
        }

        return [pscustomobject]@{
            StdOut = $stdout
            Error  = $errorOutput
        }
    }
}

Describe '1. Corrupt ZIP download' {
    It 'leaves the original script intact, preserves the backup, and reports a clear error' {
        $root = New-DestructiveTestRoot
        try {
            $scriptPath = New-OldScript -Root $root
            $originalContent = Get-Content -LiteralPath $scriptPath -Raw

            $result = Invoke-TpmApplyWithMockedRelease -ScriptPath $scriptPath -WebRequestMock {
                param($Uri, $Headers, $OutFile, $UseBasicParsing)
                [System.IO.File]::WriteAllBytes($OutFile, [byte[]](1..64 | ForEach-Object { Get-Random -Maximum 255 }))
            }

            $result.Error | Should -BeOfType ([System.Management.Automation.ErrorRecord])
            $result.Error.Exception.Message | Should -Match 'zip|central|end of'

            (Get-Content -LiteralPath $scriptPath -Raw) | Should -Be $originalContent

            $backupRoot = Join-Path $root 'UpdateBackups'
            $backupFiles = @(Get-ChildItem -LiteralPath $backupRoot -Recurse -Filter 'TeknoParrot-Manager.ps1' -ErrorAction SilentlyContinue)
            $backupFiles.Count | Should -Be 1
            (Get-Content -LiteralPath $backupFiles[0].FullName -Raw) | Should -Be $originalContent

            # No leaked temp download or extraction artifacts.
            @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-*.zip' -ErrorAction SilentlyContinue).Count | Should -Be 0
            @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-extracted-*.ps1' -ErrorAction SilentlyContinue).Count | Should -Be 0
        } finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe '2. ZIP missing TeknoParrot-Manager.ps1' {
    It 'leaves the original script intact, preserves the backup, and reports a clear error' {
        $root = New-DestructiveTestRoot
        try {
            $scriptPath = New-OldScript -Root $root
            $originalContent = Get-Content -LiteralPath $scriptPath -Raw
            $wrongEntryBytes = New-ValidFixtureZipBytes -EntryName 'SomethingElse.ps1'

            $result = Invoke-TpmApplyWithMockedRelease -ScriptPath $scriptPath -WebRequestMock {
                param($Uri, $Headers, $OutFile, $UseBasicParsing)
                [System.IO.File]::WriteAllBytes($OutFile, $wrongEntryBytes)
            }.GetNewClosure()

            $result.Error | Should -BeOfType ([System.Management.Automation.ErrorRecord])
            $result.Error.Exception.Message | Should -Match 'does not contain expected entry'

            (Get-Content -LiteralPath $scriptPath -Raw) | Should -Be $originalContent

            $backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'UpdateBackups') -Recurse -Filter 'TeknoParrot-Manager.ps1' -ErrorAction SilentlyContinue)
            $backupFiles.Count | Should -Be 1

            @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-*.zip' -ErrorAction SilentlyContinue).Count | Should -Be 0
        } finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe '3. Script fails content validation' {
    It 'rejects an extracted script missing the ScriptVersion assignment and leaves the original intact' {
        $root = New-DestructiveTestRoot
        try {
            $scriptPath = New-OldScript -Root $root
            $originalContent = Get-Content -LiteralPath $scriptPath -Raw
            $badContentBytes = New-ValidFixtureZipBytes -EntryContent "# TeknoParrot Manager`nsome unrelated content, no version here`n"

            $result = Invoke-TpmApplyWithMockedRelease -ScriptPath $scriptPath -WebRequestMock {
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

            $result = Invoke-TpmApplyWithMockedRelease -ScriptPath $scriptPath -WebRequestMock {
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
    It 'treats a truncated zip as corrupt, leaves the original intact, and cleans up' {
        $root = New-DestructiveTestRoot
        try {
            $scriptPath = New-OldScript -Root $root
            $originalContent = Get-Content -LiteralPath $scriptPath -Raw
            $fullBytes = New-ValidFixtureZipBytes
            $truncatedBytes = $fullBytes[0..([int]($fullBytes.Length / 2))]

            $result = Invoke-TpmApplyWithMockedRelease -ScriptPath $scriptPath -WebRequestMock {
                param($Uri, $Headers, $OutFile, $UseBasicParsing)
                [System.IO.File]::WriteAllBytes($OutFile, $truncatedBytes)
            }.GetNewClosure()

            $result.Error | Should -BeOfType ([System.Management.Automation.ErrorRecord])

            (Get-Content -LiteralPath $scriptPath -Raw) | Should -Be $originalContent

            $backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'UpdateBackups') -Recurse -Filter 'TeknoParrot-Manager.ps1' -ErrorAction SilentlyContinue)
            $backupFiles.Count | Should -Be 1

            @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-*.zip' -ErrorAction SilentlyContinue).Count | Should -Be 0
        } finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe '5. Read-only destination' {
    It 'refuses the update with a clear error instead of letting Move-Item -Force clear ReadOnly' {
        # Assert-TpmWritableTarget checks the target explicitly before any
        # backup/download work happens, rather than relying on Move-Item
        # -Force -- which was previously found (empirically) to silently
        # clear the ReadOnly attribute and replace the file anyway.
        $root = New-DestructiveTestRoot
        try {
            $scriptPath = New-OldScript -Root $root
            $originalContent = Get-Content -LiteralPath $scriptPath -Raw
            $validBytes = New-ValidFixtureZipBytes

            Set-ItemProperty -LiteralPath $scriptPath -Name IsReadOnly -Value $true
            try {
                $result = Invoke-TpmApplyWithMockedRelease -ScriptPath $scriptPath -WebRequestMock {
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

            # The check happens before backup/download, so neither should
            # have been attempted at all.
            Test-Path -LiteralPath (Join-Path $root 'UpdateBackups') | Should -BeFalse
            Assert-MockCalled -ModuleName TpmAutoUpdate.Core Invoke-WebRequest -Times 0

            @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-*.zip' -ErrorAction SilentlyContinue).Count | Should -Be 0
            @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-extracted-*.ps1' -ErrorAction SilentlyContinue).Count | Should -Be 0
        } finally {
            Set-ItemProperty -LiteralPath $scriptPath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe '6. Backup creation failure' {
    It 'aborts before any download when the backup cannot be created, leaving the original script untouched' {
        $root = New-DestructiveTestRoot
        try {
            $scriptPath = New-OldScript -Root $root
            $originalContent = Get-Content -LiteralPath $scriptPath -Raw

            Mock -ModuleName TpmAutoUpdate.Core New-Item {
                throw 'Access to the path is denied (simulated backup failure).'
            } -ParameterFilter { $ItemType -eq 'Directory' }

            $webRequestCalled = $false
            $result = Invoke-TpmApplyWithMockedRelease -ScriptPath $scriptPath -WebRequestMock {
                param($Uri, $Headers, $OutFile, $UseBasicParsing)
                $script:webRequestCalled = $true
                throw 'Invoke-WebRequest should never be called when backup fails first.'
            }

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
    It 'reports the extraction failure, leaves the original intact, and preserves the backup' {
        $root = New-DestructiveTestRoot
        try {
            $scriptPath = New-OldScript -Root $root
            $originalContent = Get-Content -LiteralPath $scriptPath -Raw
            $corruptedEntryBytes = Get-CorruptedEntryZipBytes

            $result = Invoke-TpmApplyWithMockedRelease -ScriptPath $scriptPath -WebRequestMock {
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

            $result = Invoke-TpmApplyWithMockedRelease -ScriptPath $scriptPath -WebRequestMock {
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
