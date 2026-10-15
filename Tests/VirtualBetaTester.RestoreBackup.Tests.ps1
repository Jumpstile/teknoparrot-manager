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
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    $script:PostgresRecoveryStatus = $null
    $script:PostgresRecoveryResumeState = $null

    $script:logPath = Join-Path $TestDrive "vbt-restore-backup.log"

    function New-RestoreFixture {
        param([string]$Name)
        $root = Join-Path $TestDrive ($Name + '-' + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        New-Item -ItemType Directory -Path $userProfilesDir -Force | Out-Null
        return $userProfilesDir
    }

    # Finite, fail-fast restore prompt scripting. Production re-prompts on invalid
    # input (Read-TpmChoice), so a mock that always returns an invalid value would
    # loop forever. These helpers script the exact prompt sequence, throw on queue
    # exhaustion or an unexpected prompt, and verify that nothing on disk changed
    # before each prompt is answered.
    function New-IsolatedRestoreFixture {
        param([Parameter(Mandatory)][string]$Name, [string]$BackupName = 'PropagateControls_2026-07-01_12-00-00')
        $root = Join-Path $TestDrive ($Name + '-' + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        $backupDir = Join-Path (Join-Path $userProfilesDir 'FullBackup') $BackupName
        if (-not [System.IO.Path]::GetFullPath($root).StartsWith([System.IO.Path]::GetFullPath($TestDrive), [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Restore fixture must stay inside TestDrive.'
        }
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $userProfilesDir 'CURRENT.xml'), [System.Text.Encoding]::ASCII.GetBytes('<GameProfile>current</GameProfile>'))
        [System.IO.File]::WriteAllBytes((Join-Path $backupDir 'ALIENS.xml'), [System.Text.Encoding]::ASCII.GetBytes('<GameProfile>backed-up</GameProfile>'))
        return [pscustomobject]@{
            UserProfilesDir = $userProfilesDir
            BackupDir = $backupDir
            CurrentPath = (Join-Path $userProfilesDir 'CURRENT.xml')
            RestoredPath = (Join-Path $userProfilesDir 'ALIENS.xml')
            BackupFilePath = (Join-Path $backupDir 'ALIENS.xml')
            CurrentBytesBase64 = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes('<GameProfile>current</GameProfile>'))
            BackupBytesBase64 = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes('<GameProfile>backed-up</GameProfile>'))
        }
    }

    function Get-RestoreFixtureSnapshot {
        param([Parameter(Mandatory)][string]$UserProfilesDir)
        $base = [System.IO.Path]::GetFullPath($UserProfilesDir)
        $entries = New-Object System.Collections.Generic.List[string]
        foreach ($item in @(Get-ChildItem -LiteralPath $UserProfilesDir -Recurse -Force | Sort-Object FullName)) {
            $relative = $item.FullName.Substring($base.Length)
            if ($item.PSIsContainer) { [void]$entries.Add('D|' + $relative) }
            else { [void]$entries.Add('F|' + $relative + '|' + (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash) }
        }
        return ($entries.ToArray() -join "`n")
    }

    function Initialize-RestorePromptScript {
        param([Parameter(Mandatory)][object[]]$Steps, [Parameter(Mandatory)][string]$UserProfilesDir)
        $script:RestorePromptSteps = [System.Collections.Generic.Queue[object]]::new()
        foreach ($step in $Steps) { [void]$script:RestorePromptSteps.Enqueue($step) }
        $script:RestorePromptLog = New-Object System.Collections.Generic.List[string]
        $script:RestoreHostLines = New-Object System.Collections.Generic.List[string]
        $script:RestorePromptDir = $UserProfilesDir
        $script:RestorePromptBaseline = Get-RestoreFixtureSnapshot -UserProfilesDir $UserProfilesDir
    }

    function Invoke-ScriptedRestorePrompt {
        param([string]$Prompt)
        [void]$script:RestorePromptLog.Add($Prompt)
        if ($script:RestorePromptSteps.Count -eq 0) { throw ("PROMPT QUEUE EXHAUSTED at prompt '{0}'" -f $Prompt) }
        $step = $script:RestorePromptSteps.Dequeue()
        if ($Prompt -notlike $step.PromptLike) { throw ("UNEXPECTED PROMPT '{0}' (expected a prompt like '{1}')" -f $Prompt, $step.PromptLike) }
        if ((Get-RestoreFixtureSnapshot -UserProfilesDir $script:RestorePromptDir) -cne $script:RestorePromptBaseline) {
            throw ("FIXTURE CHANGED before prompt '{0}' was answered" -f $Prompt)
        }
        return [string]$step.Response
    }
}

# The restore suite is intentionally behavioral: selection is most-recent-first,
# confirmation happens before deletion, malformed backups leave live profiles
# untouched, sibling snapshots survive, and application locks cancel without
# force-closing or consuming the selected backup. These cases are the safety
# contract for the beginner-facing restore flow, not incidental implementation
# assertions.
Describe "Virtual Beta Tester: restore backup enumeration and selection (issue #88 A2)" -Tag 'TVD-High' {
    It "restores the selected backup's content into UserProfiles, replacing current content" {
        $userProfilesDir = New-RestoreFixture -Name 'restore-basic'
        Set-Content -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml') -Value '<GameProfile>current</GameProfile>' -Encoding ascii
        $backupDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-01_12-00-00'
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $backupDir 'ALIENS.xml') -Value '<GameProfile>backed-up</GameProfile>' -Encoding ascii
        Mock Read-Host { return "1" } -ParameterFilter { $Prompt -like "*Enter number to restore*" }
        Mock Read-Host { return "YES" } -ParameterFilter { $Prompt -like "*Type YES to confirm*" }
        Mock Wait-TpmForProcessClose { return $true }
        Invoke-RestoreBackup -userProfilesDir $userProfilesDir
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'ALIENS.xml')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml')) | Should -Be $false
    }

    It "picks the correct backup when multiple exist (numbered by the sorted, most-recent-first list)" {
        $userProfilesDir = New-RestoreFixture -Name 'restore-multi'
        $newerDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-02_09-00-00'
        $olderDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-01_09-00-00'
        New-Item -ItemType Directory -Path $newerDir -Force | Out-Null
        New-Item -ItemType Directory -Path $olderDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $newerDir 'NEWER.xml') -Value '<GameProfile>newer</GameProfile>' -Encoding ascii
        Set-Content -LiteralPath (Join-Path $olderDir 'OLDER.xml') -Value '<GameProfile>older</GameProfile>' -Encoding ascii
        Mock Read-Host { return "1" } -ParameterFilter { $Prompt -like "*Enter number to restore*" }
        Mock Read-Host { return "YES" } -ParameterFilter { $Prompt -like "*Type YES to confirm*" }
        Mock Wait-TpmForProcessClose { return $true }
        Invoke-RestoreBackup -userProfilesDir $userProfilesDir
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'NEWER.xml')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'OLDER.xml')) | Should -Be $false
    }
}

Describe "Virtual Beta Tester: restore backup safe cancel/decline (issue #88 A2 / A4)" -Tag 'TVD-High' {
    It "pressing Enter at the backup-selection prompt cancels with zero changes" {
        $userProfilesDir = New-RestoreFixture -Name 'restore-cancel-select'
        Set-Content -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml') -Value '<GameProfile>current</GameProfile>' -Encoding ascii
        $backupDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-01_12-00-00'
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $backupDir 'ALIENS.xml') -Value '<GameProfile>backed-up</GameProfile>' -Encoding ascii
        Mock Read-Host { return "" } -ParameterFilter { $Prompt -like "*Enter number to restore*" }
        Mock Save-Config { throw 'Restore must not write configuration.' }
        $result = Invoke-RestoreBackup -userProfilesDir $userProfilesDir
        $result.PSTypeNames | Should -Contain 'TPM.TransactionResult.v1'
        $result.Outcome | Should -Be 'NO_OP'
        $result.ProductState | Should -Be 'UNCHANGED'
        $result.Mutation.Started | Should -BeFalse
        $result.ReasonCode | Should -Be 'USER_CANCELLED'
        $result.Backup.Attempted | Should -BeFalse
        $result.Backup.Created | Should -BeFalse
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml')) | Should -Be $true
        (Test-Path -LiteralPath $backupDir) | Should -Be $true
        (Get-Content -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml') -Raw) | Should -Be ('<GameProfile>current</GameProfile>' + [Environment]::NewLine)
        (Test-Path -LiteralPath (Join-Path $backupDir 'ALIENS.xml')) | Should -BeTrue
        (Get-Content -LiteralPath (Join-Path $backupDir 'ALIENS.xml') -Raw) | Should -Be ('<GameProfile>backed-up</GameProfile>' + [Environment]::NewLine)
        Assert-MockCalled Save-Config -Times 0 -Exactly
    }

    It "refuses a restore when the pre-restore rollback snapshot cannot be created" {
        $userProfilesDir = New-RestoreFixture -Name 'restore-rollback-snapshot-failure'
        $current = Join-Path $userProfilesDir 'CURRENT.xml'
        Set-Content -LiteralPath $current -Value '<GameProfile>current</GameProfile>' -Encoding ascii
        $backupDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-01_12-00-00'
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $backupDir 'ALIENS.xml') -Value '<GameProfile>backed-up</GameProfile>' -Encoding ascii
        Mock Read-Host { return '1' } -ParameterFilter { $Prompt -like '*Enter number to restore*' }
        Mock Read-Host { return 'YES' } -ParameterFilter { $Prompt -like '*Type YES to confirm*' }
        Mock Wait-TpmForProcessClose { return $true }
        Mock Copy-Item { throw 'simulated rollback snapshot failure' }
        Mock Save-Config { throw 'Restore must not write configuration.' }

        $result = Invoke-RestoreBackup -userProfilesDir $userProfilesDir

        $result.Succeeded | Should -BeFalse
        $result.PSTypeNames | Should -Contain 'TPM.TransactionResult.v1'
        $result.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        $result.ProductState | Should -Be 'UNCHANGED'
        $result.Mutation.Started | Should -BeFalse
        $result.ReasonCode | Should -Be 'ROLLBACK_SNAPSHOT_FAILED'
        $result.Backup.Attempted | Should -BeTrue
        $result.Backup.Created | Should -BeFalse
        (Get-Content -LiteralPath $current -Raw) | Should -Be ('<GameProfile>current</GameProfile>' + [Environment]::NewLine)
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'ALIENS.xml')) | Should -BeFalse
        (Test-Path -LiteralPath $backupDir) | Should -BeTrue
        (Test-Path -LiteralPath (Join-Path $backupDir 'ALIENS.xml')) | Should -BeTrue
        (Get-Content -LiteralPath (Join-Path $backupDir 'ALIENS.xml') -Raw) | Should -Be ('<GameProfile>backed-up</GameProfile>' + [Environment]::NewLine)
        Assert-MockCalled Save-Config -Times 0 -Exactly
    }

    It "declining the YES confirmation cancels with zero changes -- current content is never deleted before confirmation" {
        $userProfilesDir = New-RestoreFixture -Name 'restore-decline-confirm'
        Set-Content -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml') -Value '<GameProfile>current</GameProfile>' -Encoding ascii
        $backupDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-01_12-00-00'
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $backupDir 'ALIENS.xml') -Value '<GameProfile>backed-up</GameProfile>' -Encoding ascii
        Mock Read-Host { return "1" } -ParameterFilter { $Prompt -like "*Enter number to restore*" }
        Mock Read-Host { return "no" } -ParameterFilter { $Prompt -like "*Type YES to confirm*" }
        Mock Save-Config { throw 'Restore must not write configuration.' }
        $result = Invoke-RestoreBackup -userProfilesDir $userProfilesDir
        $result.PSTypeNames | Should -Contain 'TPM.TransactionResult.v1'
        $result.Outcome | Should -Be 'NO_OP'
        $result.ProductState | Should -Be 'UNCHANGED'
        $result.Mutation.Started | Should -BeFalse
        $result.ReasonCode | Should -Be 'USER_DECLINED'
        $result.Backup.Attempted | Should -BeFalse
        $result.Backup.Created | Should -BeFalse
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'ALIENS.xml')) | Should -Be $false
        (Get-Content -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml') -Raw) | Should -Be ('<GameProfile>current</GameProfile>' + [Environment]::NewLine)
        (Test-Path -LiteralPath $backupDir) | Should -BeTrue
        (Get-Content -LiteralPath (Join-Path $backupDir 'ALIENS.xml') -Raw) | Should -Be ('<GameProfile>backed-up</GameProfile>' + [Environment]::NewLine)
        Assert-MockCalled Save-Config -Times 0 -Exactly
    }

    # Production re-prompts after invalid restore input (docs/remediation/slices/
    # TPM-PR321-PROMPT-RESULTS-002.md): invalid numbers reject and re-ask, blank
    # maps to Back, and nothing may change before a valid selection plus an
    # explicit YES. The scripted input below is finite and fails immediately on
    # exhaustion or an unexpected prompt; the real Read-TpmChoice/Read-HostSafe run.
    It "re-prompts invalid restore input and cancels with zero changes: <Name>" -ForEach @(
        @{ Name = 'out-of-range number, then B'; Reason = 'USER_CANCELLED'; Invalid = 1; Steps = @(
            @{ PromptLike = '*Enter number to restore*'; Response = '99' }
            @{ PromptLike = '*Enter number to restore*'; Response = 'B' }
        ) }
        @{ Name = 'out-of-range number, then blank'; Reason = 'USER_CANCELLED'; Invalid = 1; Steps = @(
            @{ PromptLike = '*Enter number to restore*'; Response = '99' }
            @{ PromptLike = '*Enter number to restore*'; Response = '' }
        ) }
        @{ Name = 'non-numeric text, then lowercase b'; Reason = 'USER_CANCELLED'; Invalid = 1; Steps = @(
            @{ PromptLike = '*Enter number to restore*'; Response = 'abc' }
            @{ PromptLike = '*Enter number to restore*'; Response = 'b' }
        ) }
        @{ Name = 'two invalid answers (99, 0), then blank'; Reason = 'USER_CANCELLED'; Invalid = 2; Steps = @(
            @{ PromptLike = '*Enter number to restore*'; Response = '99' }
            @{ PromptLike = '*Enter number to restore*'; Response = '0' }
            @{ PromptLike = '*Enter number to restore*'; Response = '' }
        ) }
        @{ Name = 'invalid, then valid number, then declined confirmation'; Reason = 'USER_DECLINED'; Invalid = 1; Steps = @(
            @{ PromptLike = '*Enter number to restore*'; Response = '99' }
            @{ PromptLike = '*Enter number to restore*'; Response = '1' }
            @{ PromptLike = '*Type YES to confirm*'; Response = 'no' }
        ) }
    ) {
        $fixture = New-IsolatedRestoreFixture -Name 'restore-scripted-cancel'
        $baseline = Get-RestoreFixtureSnapshot -UserProfilesDir $fixture.UserProfilesDir
        Initialize-RestorePromptScript -Steps $Steps -UserProfilesDir $fixture.UserProfilesDir
        Mock Read-Host { Invoke-ScriptedRestorePrompt -Prompt $Prompt }
        Mock Write-Host { [void]$script:RestoreHostLines.Add([string]($Object -join ' ')) }
        Mock Save-Config { throw 'Restore must not write configuration.' }
        Mock Wait-TpmForProcessClose { throw 'Restore must not reach the process-close step without an explicit YES.' }

        $result = Invoke-RestoreBackup -userProfilesDir $fixture.UserProfilesDir

        $result.PSTypeNames | Should -Contain 'TPM.TransactionResult.v1'
        $result.Outcome | Should -Be 'NO_OP'
        $result.ProductState | Should -Be 'UNCHANGED'
        $result.Mutation.Started | Should -BeFalse
        $result.ReasonCode | Should -Be $Reason
        $result.Backup.Attempted | Should -BeFalse
        $result.Backup.Created | Should -BeFalse
        $script:RestorePromptLog.Count | Should -Be @($Steps).Count
        $script:RestorePromptSteps.Count | Should -Be 0
        Should -Invoke Read-Host -Times @($Steps).Count -Exactly
        @($script:RestoreHostLines | Where-Object { $_ -like '*Invalid choice*' }).Count | Should -Be $Invalid
        Should -Invoke Save-Config -Times 0 -Exactly
        Should -Invoke Wait-TpmForProcessClose -Times 0 -Exactly
        (Get-RestoreFixtureSnapshot -UserProfilesDir $fixture.UserProfilesDir) | Should -BeExactly $baseline
        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($fixture.CurrentPath)) | Should -Be $fixture.CurrentBytesBase64
        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($fixture.BackupFilePath)) | Should -Be $fixture.BackupBytesBase64
        (Test-Path -LiteralPath $fixture.RestoredPath) | Should -BeFalse
    }

    It "restores only after a valid selection and an explicit YES, with no change at either prompt: <Name>" -ForEach @(
        @{ Name = 'valid number, then YES'; Invalid = 0; Steps = @(
            @{ PromptLike = '*Enter number to restore*'; Response = '1' }
            @{ PromptLike = '*Type YES to confirm*'; Response = 'YES' }
        ) }
        @{ Name = 'invalid, then valid number, then YES'; Invalid = 1; Steps = @(
            @{ PromptLike = '*Enter number to restore*'; Response = '99' }
            @{ PromptLike = '*Enter number to restore*'; Response = '1' }
            @{ PromptLike = '*Type YES to confirm*'; Response = 'YES' }
        ) }
    ) {
        $fixture = New-IsolatedRestoreFixture -Name 'restore-scripted-confirm'
        Initialize-RestorePromptScript -Steps $Steps -UserProfilesDir $fixture.UserProfilesDir
        Mock Read-Host { Invoke-ScriptedRestorePrompt -Prompt $Prompt }
        Mock Write-Host { [void]$script:RestoreHostLines.Add([string]($Object -join ' ')) }
        Mock Save-Config { throw 'Restore must not write configuration.' }
        Mock Wait-TpmForProcessClose { return $true }

        $result = Invoke-RestoreBackup -userProfilesDir $fixture.UserProfilesDir

        $script:RestorePromptLog.Count | Should -Be @($Steps).Count
        $script:RestorePromptSteps.Count | Should -Be 0
        Should -Invoke Read-Host -Times @($Steps).Count -Exactly
        @($script:RestoreHostLines | Where-Object { $_ -like '*Invalid choice*' }).Count | Should -Be $Invalid
        $result.Outcome | Should -Be 'SUCCEEDED'
        $result.Mutation.Started | Should -BeTrue
        Should -Invoke Wait-TpmForProcessClose -Times 1 -Exactly
        Should -Invoke Save-Config -Times 0 -Exactly
        (Test-Path -LiteralPath $fixture.CurrentPath) | Should -BeFalse
        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($fixture.RestoredPath)) | Should -Be $fixture.BackupBytesBase64
        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($fixture.BackupFilePath)) | Should -Be $fixture.BackupBytesBase64
    }

    It "fails immediately instead of looping when the scripted restore input is exhausted" {
        $fixture = New-IsolatedRestoreFixture -Name 'restore-scripted-exhausted'
        Initialize-RestorePromptScript -Steps @(@{ PromptLike = '*Enter number to restore*'; Response = '99' }) -UserProfilesDir $fixture.UserProfilesDir
        Mock Read-Host { Invoke-ScriptedRestorePrompt -Prompt $Prompt }
        Mock Write-Host {}
        Mock Save-Config { throw 'Restore must not write configuration.' }
        Mock Wait-TpmForProcessClose { throw 'Restore must not reach the process-close step.' }

        { Invoke-RestoreBackup -userProfilesDir $fixture.UserProfilesDir } | Should -Throw '*PROMPT QUEUE EXHAUSTED*'

        $script:RestorePromptLog.Count | Should -Be 2
        (Get-RestoreFixtureSnapshot -UserProfilesDir $fixture.UserProfilesDir) | Should -BeExactly $script:RestorePromptBaseline
    }

    It "fails immediately when the restore flow asks an unexpected prompt" {
        $fixture = New-IsolatedRestoreFixture -Name 'restore-scripted-unexpected'
        Initialize-RestorePromptScript -Steps @(@{ PromptLike = '*Type YES to confirm*'; Response = 'YES' }) -UserProfilesDir $fixture.UserProfilesDir
        Mock Read-Host { Invoke-ScriptedRestorePrompt -Prompt $Prompt }
        Mock Write-Host {}
        Mock Save-Config { throw 'Restore must not write configuration.' }
        Mock Wait-TpmForProcessClose { throw 'Restore must not reach the process-close step.' }

        { Invoke-RestoreBackup -userProfilesDir $fixture.UserProfilesDir } | Should -Throw '*UNEXPECTED PROMPT*'

        $script:RestorePromptLog.Count | Should -Be 1
        (Get-RestoreFixtureSnapshot -UserProfilesDir $fixture.UserProfilesDir) | Should -BeExactly $script:RestorePromptBaseline
    }
}

Describe "Virtual Beta Tester: restore backup malformed-backup rejection (issue #88 A2)" -Tag 'TVD-High' {
    It "refuses to restore a backup folder containing zero XML profiles, leaving current content untouched" {
        $userProfilesDir = New-RestoreFixture -Name 'restore-empty-backup'
        Set-Content -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml') -Value '<GameProfile>current</GameProfile>' -Encoding ascii
        $emptyBackupDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-01_12-00-00'
        New-Item -ItemType Directory -Path $emptyBackupDir -Force | Out-Null
        Mock Read-Host { return "1" } -ParameterFilter { $Prompt -like "*Enter number to restore*" }
        Invoke-RestoreBackup -userProfilesDir $userProfilesDir
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml')) | Should -Be $true
    }
}

Describe "Virtual Beta Tester: restore backup preserves unrelated state (issue #88 A2)" -Tag 'TVD-High' {
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
        Mock Wait-TpmForProcessClose { return $true }
        Invoke-RestoreBackup -userProfilesDir $userProfilesDir
        (Test-Path -LiteralPath (Join-Path $siblingDir 'SIBLING.xml')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $selectedDir 'SELECTED.xml')) | Should -Be $true
    }

    It "refuses to restore while TeknoParrotUi.exe is running, leaving current content untouched" {
        $userProfilesDir = New-RestoreFixture -Name 'restore-tp-running'
        Set-Content -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml') -Value '<GameProfile>current</GameProfile>' -Encoding ascii
        $backupDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-01_12-00-00'
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $backupDir 'ALIENS.xml') -Value '<GameProfile>backed-up</GameProfile>' -Encoding ascii
        Mock Read-Host { return "1" } -ParameterFilter { $Prompt -like "*Enter number to restore*" }
        Mock Read-Host { return "YES" } -ParameterFilter { $Prompt -like "*Type YES to confirm*" }
        Mock Wait-TpmForProcessClose { return $false }
        Invoke-RestoreBackup -userProfilesDir $userProfilesDir
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'ALIENS.xml')) | Should -Be $false
    }
}
