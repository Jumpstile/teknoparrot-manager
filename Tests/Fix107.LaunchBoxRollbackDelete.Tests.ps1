#Requires -Module Pester

# FIX107 (NEW-S1): a LaunchBox rollback that has to delete a file this run created must never delete a newer save.
#   When a save creates a platform file that did not exist and a later file fails, the rollback removes the new file.
#   The check and the delete are one step on one open file: the file must still be the file this run created (same file
#   identity) and still hold the bytes this run wrote. A file another program saved in its place is kept and the rollback
#   is reported as incomplete. A file that is already gone is fine.
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.
# Everything lives under TestDrive with synthetic files. The race is simulated at the exact point between the check and
# the delete. Each It names the product change that makes it fail.
# What this CANNOT prove: a real LaunchBox or BigBox, or a second program racing in real time.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX107 tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:F107FunctionFile = Join-Path $TestDrive 'tpm-fix107-lb-functions.ps1'
    [System.IO.File]::WriteAllText($script:F107FunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:F107FunctionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')

    $script:F107Mine = '<LaunchBox><Platform><Name>Mine</Name></Platform></LaunchBox>'
    $script:F107Newer = '<LaunchBox><Platform><Name>Saved by LaunchBox meanwhile</Name></Platform></LaunchBox>'

    # A LaunchBox library with one existing file (Data\Emulators.xml) and room for a new one (Data\Platforms\Fresh.xml).
    function New-F107LaunchBox {
        $root = Join-Path $TestDrive ('f107-lb-' + [guid]::NewGuid().ToString('N'))
        $library = Join-Path $root 'LaunchBox'
        [void][System.IO.Directory]::CreateDirectory((Join-Path $library 'Data\Platforms'))
        [void][System.IO.Directory]::CreateDirectory((Join-Path $root 'Source'))
        [System.IO.File]::WriteAllText((Join-Path $library 'Data\Emulators.xml'), '<LaunchBox><Emulator><ID>original-emulator</ID></Emulator></LaunchBox>')
        return [pscustomobject]@{ Root = $library; Backups = (Join-Path $root 'Backups'); Source = (Join-Path $root 'Source'); Fresh = (Join-Path $library 'Data\Platforms\Fresh.xml'); Emulators = (Join-Path $library 'Data\Emulators.xml') }
    }

    function New-F107Plan {
        param([Parameter(Mandatory)]$Fixture, [Parameter(Mandatory)][string]$RelativePath, [Parameter(Mandatory)][string]$NewText)
        $source = Join-Path $Fixture.Source ([System.IO.Path]::GetFileName($RelativePath))
        [System.IO.File]::WriteAllText($source, $NewText)
        return [pscustomobject]@{
            RelativePath = $RelativePath; Changed = $true; Delete = $false
            Before = (Get-TpmLaunchBoxFileState -Path (Join-Path $Fixture.Root $RelativePath))
            Document = $null; Source = $source; SourceHash = ''; AfterHash = ''; BaseChildCount = 0
        }
    }

    # Commits Data\Platforms\Fresh.xml (a new file) first, then fails on Emulators.xml (its staged bytes are spoiled), so the new file must be rolled back.
    # $AtRollbackDelete runs between the rollback's check and its delete of the new file.
    function Invoke-F107FailedSave {
        param([Parameter(Mandatory)]$Fixture, [scriptblock]$AtRollbackDelete = $null, [string]$Operation = 'write')
        $script:F107Fixture = $Fixture
        $script:F107AtRollbackDelete = $AtRollbackDelete
        $fresh = New-F107Plan -Fixture $Fixture -RelativePath 'Data\Platforms\Fresh.xml' -NewText $script:F107Mine
        $emulators = New-F107Plan -Fixture $Fixture -RelativePath 'Data\Emulators.xml' -NewText '<LaunchBox><Emulator><ID>mine</ID></Emulator></LaunchBox>'
        return (Invoke-TpmLaunchBoxFileTransaction -lbRoot $Fixture.Root -Plans @($fresh, $emulators) -BackupRoot $Fixture.Backups -Operation $Operation)
    }
}

Describe 'FIX107 S1: LaunchBox rollback deletes only the file this run created' {
    BeforeEach {
        $script:F107AtRollbackDelete = $null
        Mock Write-Log {}
        Mock Test-LaunchBoxRunning { $false }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Assert-TpmNoReparseWriteTarget {
            if ($Operation -eq 'LaunchBox commit' -and $Path -ieq $script:F107Fixture.Fresh) {
                # The new file was just put in place: spoil the staged bytes of the next file so the save fails and has to roll back.
                foreach ($staged in @(Get-ChildItem -LiteralPath (Join-Path $script:F107Fixture.Root 'Data') -Filter 'Emulators.xml.*.tmp')) { [System.IO.File]::AppendAllText($staged.FullName, ' ') }
            }
            if ($Operation -eq 'LaunchBox rollback deletion' -and $null -ne $script:F107AtRollbackDelete) { & $script:F107AtRollbackDelete $Path }
        }
        Mock Backup-LaunchBoxFiles {
            $backupDir = Join-Path $BackupRoot 'saved-copy'
            foreach ($item in $Items) {
                $from = Join-Path $lbRoot $item.RelativePath
                $to = Join-Path $backupDir $item.RelativePath
                [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($to))
                if (Test-Path -LiteralPath $from) { [System.IO.File]::Copy($from, $to) }
            }
            return [pscustomobject]@{ Path = $backupDir; Verified = $true }
        }
    }

    It 'removes the new file and calls the rollback verified when nobody touched it' {
        # Mutation: refuse to delete a file this run created (for example a missing identity) -> the new file stays and the rollback is not verified.
        $fx = New-F107LaunchBox
        $r = Invoke-F107FailedSave -Fixture $fx
        $r.Outcome | Should -BeExactly 'FAILED'
        $r.RollbackVerified | Should -BeTrue
        Test-Path -LiteralPath $fx.Fresh | Should -BeFalse
        @($r.UnrecoveredPaths).Count | Should -Be 0
    }

    It 'names the operation in the summary: a failed restore says restore, a failed save says save' -ForEach @(
        @{ Operation = 'restore-safety'; Expected = 'LaunchBox restore failed;*'; NotExpected = '*save failed*' },
        @{ Operation = 'write'; Expected = 'LaunchBox save failed;*'; NotExpected = '*restore failed*' }
    ) {
        # Who gets hurt: a user who ran Restore backup and was told a save failed (the result screen uses this summary as its title).
        # Mutation: use the save wording for the restore-safety operation.
        $fx = New-F107LaunchBox
        $r = Invoke-F107FailedSave -Fixture $fx -Operation $Operation
        $r.RollbackVerified | Should -BeTrue
        $r.Summary | Should -BeLike $Expected
        $r.Summary | Should -Not -BeLike $NotExpected
    }

    It 'keeps a newer save that has the very same bytes but is a different file' {
        # Mutation: check only the hash before the delete (path based) -> a file another program saved in its place is deleted when its bytes match.
        $fx = New-F107LaunchBox
        $r = Invoke-F107FailedSave -Fixture $fx -AtRollbackDelete {
            param($Path)
            $other = $Path + '.other'
            [System.IO.File]::WriteAllText($other, $script:F107Mine)
            [System.IO.File]::Replace($other, $Path, [NullString]::Value)
        }
        $r.RollbackVerified | Should -BeFalse
        $r.Outcome | Should -BeExactly 'PARTIAL'
        Test-Path -LiteralPath $fx.Fresh | Should -BeTrue
        [System.IO.File]::ReadAllText($fx.Fresh) | Should -BeExactly $script:F107Mine
        @($r.UnrecoveredPaths) | Should -Contain 'Data\Platforms\Fresh.xml'
        ($r.Errors -join ' ') | Should -Match 'left the file this run created as it is'
    }

    It 'keeps a newer in-place save with the same file identity and the same bytes' {
        # Mutation: leave -ExpectedLastWriteTimeUtc out of the rollback's Remove-TpmTreeOwnedFile call -> identity and hash both match and the newer save is deleted.
        $fx = New-F107LaunchBox
        $script:F107IdentityBefore = $null
        $r = Invoke-F107FailedSave -Fixture $fx -AtRollbackDelete {
            param($Path)
            $script:F107IdentityBefore = Get-TpmFileIdentityString -Path $Path
            [System.IO.File]::WriteAllText($Path, $script:F107Mine)
            [System.IO.File]::SetLastWriteTimeUtc($Path, [datetime]::UtcNow.AddMinutes(5))
        }
        (Get-TpmFileIdentityString -Path $fx.Fresh) | Should -BeExactly $script:F107IdentityBefore
        $r.RollbackVerified | Should -BeFalse
        Test-Path -LiteralPath $fx.Fresh | Should -BeTrue
        [System.IO.File]::ReadAllText($fx.Fresh) | Should -BeExactly $script:F107Mine
        @($r.UnrecoveredPaths) | Should -Contain 'Data\Platforms\Fresh.xml'
        ($r.Errors -join ' ') | Should -Match 'left the file this run created as it is'
    }

    It 'keeps a newer save that changed the bytes of the same file even when length and write time are restored' {
        # Mutation: delete without comparing the bytes on the open file -> the newer save is deleted (same length and write time, so only the hash check can keep it).
        $fx = New-F107LaunchBox
        $r = Invoke-F107FailedSave -Fixture $fx -AtRollbackDelete {
            param($Path)
            $stamp = [System.IO.File]::GetLastWriteTimeUtc($Path)
            [System.IO.File]::WriteAllText($Path, $script:F107Mine.Replace('Mine', 'Nope'))
            [System.IO.File]::SetLastWriteTimeUtc($Path, $stamp)
        }
        $r.RollbackVerified | Should -BeFalse
        [System.IO.File]::ReadAllText($fx.Fresh) | Should -BeExactly $script:F107Mine.Replace('Mine', 'Nope')
        @($r.UnrecoveredPaths) | Should -Contain 'Data\Platforms\Fresh.xml'
    }

    It 'treats a new file that is already gone as rolled back' {
        # Mutation: treat "already gone" as a failed delete -> a rollback that has nothing left to remove is reported as incomplete.
        $fx = New-F107LaunchBox
        $r = Invoke-F107FailedSave -Fixture $fx -AtRollbackDelete {
            param($Path)
            [System.IO.File]::Delete($Path)
        }
        $r.RollbackVerified | Should -BeTrue
        Test-Path -LiteralPath $fx.Fresh | Should -BeFalse
        @($r.UnrecoveredPaths).Count | Should -Be 0
    }

    It 'leaves the file alone when the identity of the file it created is unknown' {
        # Mutation: delete by path when no identity was recorded -> a file that cannot be proven to be ours is deleted.
        Mock Get-TpmFileIdentityString { $null }
        $fx = New-F107LaunchBox
        $r = Invoke-F107FailedSave -Fixture $fx
        $r.RollbackVerified | Should -BeFalse
        Test-Path -LiteralPath $fx.Fresh | Should -BeTrue
        ($r.Errors -join ' ') | Should -Match 'could not prove which file this run created'
    }
}
