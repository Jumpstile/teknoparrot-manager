#Requires -Module Pester

# TPM Certification Suite Phase 1.7 (issue #88, priority A2): Restore Backup
# Behavioral Recovery. Invoke-RestoreBackup had zero prior test coverage of
# any kind despite being one of TPM's highest-value safety features -- it
# is the last line of defense if a run goes wrong. Each test documents the
# human behavior replaced, the defect class it catches, and why existing
# certification wouldn't already catch it.
#
# Deterministic: no network, no GUI, no real TeknoParrot root, all writes
# confined to $TestDrive. Read-Host is mocked to drive the interactive
# choice/confirm prompts deterministically.
#
# Run with: Invoke-Pester -Path .\Tests\VirtualBetaTester.RestoreBackup.Tests.ps1

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\TeknoParrot-Manager.ps1"
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')"
    }
    $functionAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $extractedFunctionsPath = Join-Path $TestDrive ("vbt-restore-backup-functions-" + [guid]::NewGuid().ToString('N') + '.ps1')
    ($functionAsts | ForEach-Object { $_.Extent.Text }) -join "`n`n" | Set-Content -LiteralPath $extractedFunctionsPath -Encoding utf8
    . $extractedFunctionsPath

    $script:logPath = Join-Path $TestDrive "vbt-restore-backup.log"

    function New-RestoreFixture {
        param([string]$Name)
        $root = Join-Path $TestDrive ($Name + '-' + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        New-Item -ItemType Directory -Path $userProfilesDir -Force | Out-Null
        return $userProfilesDir
    }
}

Describe "Virtual Beta Tester: restore backup enumeration and selection (issue #88 A2)" -Tag 'TVD-High' {
    # Human behavior replaced: a tester who needs to roll back checks the
    # list of available backups, picks the one they want (most recent
    # first, matching how a person actually thinks about "the backup from
    # right before it broke"), and expects exactly that snapshot restored.
    # Defect class detectable: wrong backup selected, off-by-one index
    # handling, or a restore that silently no-ops instead of restoring.
    # Why existing certification wouldn't already catch it: Invoke-
    # RestoreBackup had no test coverage at all before this round.

    It "restores the selected backup's content into UserProfiles, replacing current content" {
        $userProfilesDir = New-RestoreFixture -Name 'restore-basic'
        Set-Content -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml') -Value '<GameProfile>current</GameProfile>' -Encoding ascii

        $backupDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-01_12-00-00'
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $backupDir 'ALIENS.xml') -Value '<GameProfile>backed-up</GameProfile>' -Encoding ascii

        Mock Read-Host { return "1" } -ParameterFilter { $Prompt -like "*Enter number to restore*" }
        Mock Read-Host { return "YES" } -ParameterFilter { $Prompt -like "*Type YES to confirm*" }
        Mock Get-Process { return $null } -ParameterFilter { $Name -eq "TeknoParrotUi" }

        Invoke-RestoreBackup -userProfilesDir $userProfilesDir

        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'ALIENS.xml')) | Should -Be $true -Because "the backed-up profile must be restored"
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml')) | Should -Be $false -Because "restore replaces current content with the selected backup's content"
    }

    It "picks the correct backup when multiple exist (numbered by the sorted, most-recent-first list)" {
        $userProfilesDir = New-RestoreFixture -Name 'restore-multi'

        $newerDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-02_09-00-00'
        $olderDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-01_09-00-00'
        New-Item -ItemType Directory -Path $newerDir -Force | Out-Null
        New-Item -ItemType Directory -Path $olderDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $newerDir 'NEWER.xml') -Value '<GameProfile>newer</GameProfile>' -Encoding ascii
        Set-Content -LiteralPath (Join-Path $olderDir 'OLDER.xml') -Value '<GameProfile>older</GameProfile>' -Encoding ascii

        # "1" must select the newest backup -- matching the sorted,
        # most-recent-first list a tester sees on screen.
        Mock Read-Host { return "1" } -ParameterFilter { $Prompt -like "*Enter number to restore*" }
        Mock Read-Host { return "YES" } -ParameterFilter { $Prompt -like "*Type YES to confirm*" }
        Mock Get-Process { return $null } -ParameterFilter { $Name -eq "TeknoParrotUi" }

        Invoke-RestoreBackup -userProfilesDir $userProfilesDir

        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'NEWER.xml')) | Should -Be $true -Because "option 1 must be the most recent backup, not an arbitrary one"
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'OLDER.xml')) | Should -Be $false
    }
}

Describe "Virtual Beta Tester: restore backup safe cancel/decline (issue #88 A2 / A4)" -Tag 'TVD-High' {
    # Human behavior replaced: a tester who opens the restore menu just to
    # look, or who gets cold feet at the confirmation warning, expects to
    # back out with zero side effects -- no partial delete, no partial
    # restore, current profiles completely untouched.
    # Defect class detectable: a cancel path that still deletes current
    # UserProfiles content before checking for confirmation (delete-then-
    # ask instead of ask-then-delete), or one that leaves a half-completed
    # restore behind.
    # Why existing certification wouldn't already catch it: no test
    # exercised either cancel path before this round.

    It "pressing Enter at the backup-selection prompt cancels with zero changes" {
        $userProfilesDir = New-RestoreFixture -Name 'restore-cancel-select'
        Set-Content -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml') -Value '<GameProfile>current</GameProfile>' -Encoding ascii
        $backupDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-01_12-00-00'
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $backupDir 'ALIENS.xml') -Value '<GameProfile>backed-up</GameProfile>' -Encoding ascii

        Mock Read-Host { return "" } -ParameterFilter { $Prompt -like "*Enter number to restore*" }

        Invoke-RestoreBackup -userProfilesDir $userProfilesDir

        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml')) | Should -Be $true -Because "cancelling at selection must leave current profiles completely untouched"
        (Test-Path -LiteralPath $backupDir) | Should -Be $true -Because "the backup itself must be untouched too"
    }

    It "declining the YES confirmation cancels with zero changes -- current content is never deleted before confirmation" {
        $userProfilesDir = New-RestoreFixture -Name 'restore-decline-confirm'
        Set-Content -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml') -Value '<GameProfile>current</GameProfile>' -Encoding ascii
        $backupDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-01_12-00-00'
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $backupDir 'ALIENS.xml') -Value '<GameProfile>backed-up</GameProfile>' -Encoding ascii

        Mock Read-Host { return "1" } -ParameterFilter { $Prompt -like "*Enter number to restore*" }
        Mock Read-Host { return "no" } -ParameterFilter { $Prompt -like "*Type YES to confirm*" }

        Invoke-RestoreBackup -userProfilesDir $userProfilesDir

        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml')) | Should -Be $true -Because "declining confirmation must never have deleted current content -- confirm-then-act, not act-then-confirm"
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'ALIENS.xml')) | Should -Be $false -Because "nothing should have been restored either"
    }

    It "an invalid selection (out of range) is treated as a cancel with zero changes" {
        $userProfilesDir = New-RestoreFixture -Name 'restore-invalid-select'
        Set-Content -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml') -Value '<GameProfile>current</GameProfile>' -Encoding ascii
        $backupDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-01_12-00-00'
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $backupDir 'ALIENS.xml') -Value '<GameProfile>backed-up</GameProfile>' -Encoding ascii

        Mock Read-Host { return "99" } -ParameterFilter { $Prompt -like "*Enter number to restore*" }

        Invoke-RestoreBackup -userProfilesDir $userProfilesDir

        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'ALIENS.xml')) | Should -Be $false
    }
}

Describe "Virtual Beta Tester: restore backup malformed-backup rejection (issue #88 A2)" -Tag 'TVD-High' {
    # Human behavior replaced: a tester who somehow ends up with an empty
    # or corrupted backup folder (interrupted backup creation, manual
    # tampering) checks that TPM refuses to "restore" it rather than
    # wiping current profiles and leaving nothing in their place.
    # Defect class detectable: a restore that deletes current UserProfiles
    # content BEFORE discovering the selected backup is empty/invalid,
    # leaving the user with nothing at all -- strictly worse than the
    # bug it was meant to protect against.
    # Why existing certification wouldn't already catch it: no fixture
    # combined an empty backup folder with a restore attempt before this
    # round.

    It "refuses to restore a backup folder containing zero XML profiles, leaving current content untouched" {
        $userProfilesDir = New-RestoreFixture -Name 'restore-empty-backup'
        Set-Content -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml') -Value '<GameProfile>current</GameProfile>' -Encoding ascii

        $emptyBackupDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-01_12-00-00'
        New-Item -ItemType Directory -Path $emptyBackupDir -Force | Out-Null
        # Deliberately no .xml files inside -- simulates an interrupted or
        # corrupted backup.

        Mock Read-Host { return "1" } -ParameterFilter { $Prompt -like "*Enter number to restore*" }

        Invoke-RestoreBackup -userProfilesDir $userProfilesDir

        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml')) | Should -Be $true -Because "an empty/malformed backup must be rejected before any deletion happens -- current content must survive"
    }
}

Describe "Virtual Beta Tester: restore backup preserves unrelated state (issue #88 A2)" -Tag 'TVD-High' {
    # Human behavior replaced: a tester with several historical backups
    # checks that restoring one of them doesn't destroy the others -- the
    # whole point of keeping a backup history is that it survives being
    # used.
    # Defect class detectable: a restore routine that clears the FullBackup
    # folder itself (all sibling snapshots), not just the live UserProfiles
    # content, losing the tester's entire safety net in one action.
    # Why existing certification wouldn't already catch it: no fixture
    # exercised a restore with multiple sibling backups present to prove
    # the ones NOT selected survive.

    It "restoring one backup leaves every other backup snapshot in FullBackup completely intact" {
        $userProfilesDir = New-RestoreFixture -Name 'restore-preserves-siblings'

        $selectedDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-02_09-00-00'
        $siblingDir  = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-01_09-00-00'
        New-Item -ItemType Directory -Path $selectedDir -Force | Out-Null
        New-Item -ItemType Directory -Path $siblingDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $selectedDir 'SELECTED.xml') -Value '<GameProfile>selected</GameProfile>' -Encoding ascii
        Set-Content -LiteralPath (Join-Path $siblingDir 'SIBLING.xml') -Value '<GameProfile>sibling</GameProfile>' -Encoding ascii

        Mock Read-Host { return "1" } -ParameterFilter { $Prompt -like "*Enter number to restore*" }
        Mock Read-Host { return "YES" } -ParameterFilter { $Prompt -like "*Type YES to confirm*" }
        Mock Get-Process { return $null } -ParameterFilter { $Name -eq "TeknoParrotUi" }

        Invoke-RestoreBackup -userProfilesDir $userProfilesDir

        (Test-Path -LiteralPath (Join-Path $siblingDir 'SIBLING.xml')) | Should -Be $true -Because "restoring one backup must never disturb any other backup snapshot"
        (Test-Path -LiteralPath (Join-Path $selectedDir 'SELECTED.xml')) | Should -Be $true -Because "the backup that was restored FROM is also left intact, not consumed or moved"
    }

    It "refuses to restore while TeknoParrotUi.exe is running, leaving current content untouched" {
        $userProfilesDir = New-RestoreFixture -Name 'restore-tp-running'
        Set-Content -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml') -Value '<GameProfile>current</GameProfile>' -Encoding ascii
        $backupDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-01_12-00-00'
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $backupDir 'ALIENS.xml') -Value '<GameProfile>backed-up</GameProfile>' -Encoding ascii

        Mock Read-Host { return "1" } -ParameterFilter { $Prompt -like "*Enter number to restore*" }
        Mock Read-Host { return "YES" } -ParameterFilter { $Prompt -like "*Type YES to confirm*" }
        Mock Get-Process { return [pscustomobject]@{ Name = "TeknoParrotUi" } } -ParameterFilter { $Name -eq "TeknoParrotUi" }

        Invoke-RestoreBackup -userProfilesDir $userProfilesDir

        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml')) | Should -Be $true -Because "TeknoParrot must be fully closed before a restore touches live profile files it may have open"
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'ALIENS.xml')) | Should -Be $false
    }
}
