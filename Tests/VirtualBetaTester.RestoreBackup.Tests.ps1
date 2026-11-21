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
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force
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
        Mock Read-Host { return "UNVERIFIED" } -ParameterFilter { $Prompt -like "*Type UNVERIFIED*" }
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
        Mock Read-Host { return "UNVERIFIED" } -ParameterFilter { $Prompt -like "*Type UNVERIFIED*" }
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
        Should -Invoke Save-Config -Times 0 -Exactly
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
        Mock Read-Host { return 'UNVERIFIED' } -ParameterFilter { $Prompt -like '*Type UNVERIFIED*' }
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
        Should -Invoke Save-Config -Times 0 -Exactly
    }

    It "declining the typed confirmation cancels with zero changes -- current content is never deleted before confirmation" {
        $userProfilesDir = New-RestoreFixture -Name 'restore-decline-confirm'
        Set-Content -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml') -Value '<GameProfile>current</GameProfile>' -Encoding ascii
        $backupDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-01_12-00-00'
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $backupDir 'ALIENS.xml') -Value '<GameProfile>backed-up</GameProfile>' -Encoding ascii
        Mock Read-Host { return "1" } -ParameterFilter { $Prompt -like "*Enter number to restore*" }
        Mock Read-Host { return "no" } -ParameterFilter { $Prompt -like "*Type UNVERIFIED*" }
        Mock Read-Host { throw 'An unchecked copy is approved once; it must not ask Type YES to confirm as well.' } -ParameterFilter { $Prompt -like "*Type YES to confirm*" }
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
        Should -Invoke Save-Config -Times 0 -Exactly
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
            @{ PromptLike = '*Type UNVERIFIED*'; Response = 'no' }
        ) }
        @{ Name = 'valid number, then declined unverified-backup confirmation'; Reason = 'USER_DECLINED'; Invalid = 0; Steps = @(
            @{ PromptLike = '*Enter number to restore*'; Response = '1' }
            @{ PromptLike = '*Type UNVERIFIED*'; Response = 'YES' }
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

    It "restores only after a valid selection and the one typed confirmation (UNVERIFIED for a copy that cannot be checked), with no change at either prompt and no second question: <Name>" -ForEach @(
        @{ Name = 'valid number, then UNVERIFIED'; Invalid = 0; Steps = @(
            @{ PromptLike = '*Enter number to restore*'; Response = '1' }
            @{ PromptLike = '*Type UNVERIFIED*'; Response = 'UNVERIFIED' }
        ) }
        @{ Name = 'invalid, then valid number, then UNVERIFIED'; Invalid = 1; Steps = @(
            @{ PromptLike = '*Enter number to restore*'; Response = '99' }
            @{ PromptLike = '*Enter number to restore*'; Response = '1' }
            @{ PromptLike = '*Type UNVERIFIED*'; Response = 'UNVERIFIED' }
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
        Mock Read-Host { return "UNVERIFIED" } -ParameterFilter { $Prompt -like "*Type UNVERIFIED*" }
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
        Mock Read-Host { return "UNVERIFIED" } -ParameterFilter { $Prompt -like "*Type UNVERIFIED*" }
        Mock Wait-TpmForProcessClose { return $false }
        Invoke-RestoreBackup -userProfilesDir $userProfilesDir
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'ALIENS.xml')) | Should -Be $false
    }
}

# FIX29 (SCAN2-01): a backup becomes a normal restore choice only once it is complete. Interrupted or failed backups
# keep their INCOMPLETE_ name and are never offered; a completed backup must still match its completion record before
# anything changes; an older backup without a record needs an explicit UNVERIFIED confirmation that shows its file
# count; and the pre-restore snapshot is kept unless the restored profiles equal the selected backup exactly.
Describe "Virtual Beta Tester: UserProfiles backup completion protocol (FIX29 SCAN2-01)" -Tag 'TVD-High' {
    BeforeAll {
        # The screen as one text: every run of spaces and line breaks becomes one space, so a sentence the
        # product wraps at the console width is matched the same at any width.
        function Get-Fx29Screen { return ((@($script:fx29HostLines) -join ' ') -replace '\s+', ' ').Trim() }
    }
    BeforeEach {
        Mock Write-TpmCompactExtractionProgress {}
        $script:fx29LogLines = New-Object System.Collections.Generic.List[string]
        Mock Write-Log { [void]$script:fx29LogLines.Add([string]$msg) }
        $script:fx29HostLines = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$script:fx29HostLines.Add([string]($Object -join ' ')) }
    }

    It "publishes a verified backup under its final name with a matching completion record" {
        $userProfilesDir = New-RestoreFixture -Name 'fx29-producer'
        [System.IO.File]::WriteAllText((Join-Path $userProfilesDir 'A.xml'), '<GameProfile>a</GameProfile>')
        [void](New-Item -ItemType Directory -Path (Join-Path $userProfilesDir 'Nested') -Force)
        [System.IO.File]::WriteAllText((Join-Path $userProfilesDir 'Nested\B.xml'), '<GameProfile>b</GameProfile>')

        $backup = New-TpmVerifiedUserProfilesBackup -UserProfilesDir $userProfilesDir -Label 'Fixture'

        $backup.Verified | Should -BeTrue -Because ([string]$backup.Reason)
        $finalName = [System.IO.Path]::GetFileName([string]$backup.Path)
        $finalName | Should -BeLike 'Fixture_*'
        (@(Get-ChildItem -LiteralPath (Join-Path $userProfilesDir 'FullBackup') -Directory -Force | ForEach-Object Name) -join ',') | Should -BeExactly $finalName
        $record = [System.IO.File]::ReadAllText((Join-Path $backup.Path 'TPM-BACKUP-COMPLETE.json')) | ConvertFrom-Json
        $record.Schema | Should -Be 'TPM.UserProfilesBackupCompletion.v1'
        [int]$record.FileCount | Should -Be 2
        (Test-TpmUserProfilesBackupCompletion -BackupPath $backup.Path -Inventory @(Get-TpmUserProfilesBackupInventory -BackupPath $backup.Path)).Valid | Should -BeTrue
    }

    It "keeps a failed backup whose cleanup also failed only under its INCOMPLETE_ name, and restore never offers it" {
        $userProfilesDir = New-RestoreFixture -Name 'fx29-failed-producer'
        [System.IO.File]::WriteAllText((Join-Path $userProfilesDir 'A.xml'), '<GameProfile>a</GameProfile>')
        [System.IO.File]::WriteAllText((Join-Path $userProfilesDir 'B.xml'), '<GameProfile>b</GameProfile>')
        Mock Copy-Item {
            param($LiteralPath, $Destination)
            if ($LiteralPath -like '*B.xml') { throw 'simulated copy failure on B.xml' }
            [System.IO.File]::Copy($LiteralPath, $Destination, $true)
        }
        Mock Remove-Item { throw 'simulated cleanup failure' }

        $backup = New-TpmVerifiedUserProfilesBackup -UserProfilesDir $userProfilesDir -Label 'Fixture'

        $backup.Verified | Should -BeFalse
        @($backup.ResiduePaths).Count | Should -Be 1
        [System.IO.Path]::GetFileName([string]@($backup.ResiduePaths)[0]) | Should -BeLike 'INCOMPLETE_Fixture_*'
        Test-Path -LiteralPath (Join-Path ([string]@($backup.ResiduePaths)[0]) 'A.xml') | Should -BeTrue
        @(Get-ChildItem -LiteralPath (Join-Path $userProfilesDir 'FullBackup') -Directory -Force | Where-Object { $_.Name -notlike 'INCOMPLETE_*' }).Count | Should -Be 0

        $liveBefore = Get-RestoreFixtureSnapshot -UserProfilesDir $userProfilesDir
        Mock Read-Host { throw ("UNEXPECTED PROMPT '{0}': an incomplete backup must not be offered" -f $Prompt) }
        $result = Invoke-RestoreBackupLegacy -userProfilesDir $userProfilesDir

        $result.Outcome | Should -Be 'NO_OP'
        $result.ReasonCode | Should -Be 'NO_BACKUPS_FOUND'
        $result.MutationStarted | Should -BeFalse
        Should -Invoke Read-Host -Times 0 -Exactly
        # Mutation: stop telling the user that an unfinished saved copy was skipped, or drop the INCOMPLETE_ folder name from the log.
        (Get-Fx29Screen) | Should -Match '1 unfinished saved copy was skipped\. It is kept as evidence and cannot be restored\.'
        @($script:fx29LogLines | Where-Object { $_ -like 'Restore: 1 incomplete backup folder(s) named INCOMPLETE_* were skipped*' }).Count | Should -Be 1
        Get-RestoreFixtureSnapshot -UserProfilesDir $userProfilesDir | Should -BeExactly $liveBefore
    }

    It "restores a completed backup after the number and YES only, verifies it, and never copies its completion record" {
        $userProfilesDir = New-RestoreFixture -Name 'fx29-verified-restore'
        [System.IO.File]::WriteAllText((Join-Path $userProfilesDir 'A.xml'), '<GameProfile>a</GameProfile>')
        [System.IO.File]::WriteAllText((Join-Path $userProfilesDir 'B.xml'), '<GameProfile>b</GameProfile>')
        $backup = New-TpmVerifiedUserProfilesBackup -UserProfilesDir $userProfilesDir -Label 'Fixture'
        $backup.Verified | Should -BeTrue -Because ([string]$backup.Reason)
        [System.IO.File]::Delete((Join-Path $userProfilesDir 'A.xml'))
        [System.IO.File]::WriteAllText((Join-Path $userProfilesDir 'CURRENT.xml'), '<GameProfile>current</GameProfile>')
        Mock Read-Host { return '1' } -ParameterFilter { $Prompt -like '*Enter number to restore*' }
        Mock Read-Host { return 'YES' } -ParameterFilter { $Prompt -like '*Type YES to confirm*' }
        Mock Read-Host { throw 'A completed backup must not ask for the UNVERIFIED confirmation.' } -ParameterFilter { $Prompt -like '*Type UNVERIFIED*' }
        Mock Wait-TpmForProcessClose { return $true }

        $result = Invoke-RestoreBackupLegacy -userProfilesDir $userProfilesDir

        $result.Outcome | Should -Be 'SUCCEEDED'
        [System.IO.File]::ReadAllText((Join-Path $userProfilesDir 'A.xml')) | Should -Be '<GameProfile>a</GameProfile>'
        [System.IO.File]::ReadAllText((Join-Path $userProfilesDir 'B.xml')) | Should -Be '<GameProfile>b</GameProfile>'
        Test-Path -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $userProfilesDir 'TPM-BACKUP-COMPLETE.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $backup.Path 'TPM-BACKUP-COMPLETE.json') | Should -BeTrue
        @($script:fx29HostLines | Where-Object { $_ -like '*UNVERIFIED*' }).Count | Should -Be 0
    }

    It "refuses, before any change, a completed backup whose content no longer matches its completion record" {
        $userProfilesDir = New-RestoreFixture -Name 'fx29-damaged-backup'
        [System.IO.File]::WriteAllText((Join-Path $userProfilesDir 'A.xml'), '<GameProfile>a</GameProfile>')
        [System.IO.File]::WriteAllText((Join-Path $userProfilesDir 'B.xml'), '<GameProfile>b</GameProfile>')
        $backup = New-TpmVerifiedUserProfilesBackup -UserProfilesDir $userProfilesDir -Label 'Fixture'
        $backup.Verified | Should -BeTrue -Because ([string]$backup.Reason)
        # The SCAN2-01 shape: the selectable folder holds fewer profiles than the live set it claims to cover.
        [System.IO.File]::Delete((Join-Path $backup.Path 'B.xml'))
        $liveBefore = Get-RestoreFixtureSnapshot -UserProfilesDir $userProfilesDir
        Mock Read-Host { return '1' } -ParameterFilter { $Prompt -like '*Enter number to restore*' }
        Mock Read-Host { throw 'A damaged backup must be refused before confirmation.' } -ParameterFilter { $Prompt -like '*Type YES to confirm*' -or $Prompt -like '*Type UNVERIFIED*' }
        Mock Wait-TpmForProcessClose { throw 'A damaged backup must be refused before the process check.' }

        $result = Invoke-RestoreBackupLegacy -userProfilesDir $userProfilesDir

        $result.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -Be 'BACKUP_VERIFICATION_FAILED'
        $result.MutationStarted | Should -BeFalse
        Get-RestoreFixtureSnapshot -UserProfilesDir $userProfilesDir | Should -BeExactly $liveBefore
    }

    It "says the backup could not be checked, not that it does not match, when its completion record cannot be read right now" {
        # Mutation: ignore CouldNotCheck in Invoke-RestoreBackupLegacy -> the user is told the copy "does not match its completion record".
        $userProfilesDir = New-RestoreFixture -Name 'fx29-locked-record'
        [System.IO.File]::WriteAllText((Join-Path $userProfilesDir 'A.xml'), '<GameProfile>a</GameProfile>')
        $backup = New-TpmVerifiedUserProfilesBackup -UserProfilesDir $userProfilesDir -Label 'Fixture'
        $backup.Verified | Should -BeTrue -Because ([string]$backup.Reason)
        $liveBefore = Get-RestoreFixtureSnapshot -UserProfilesDir $userProfilesDir
        Mock Read-Host { return '1' } -ParameterFilter { $Prompt -like '*Enter number to restore*' }
        Mock Read-Host { throw 'A backup that could not be checked must stop before confirmation.' } -ParameterFilter { $Prompt -like '*Type YES to confirm*' -or $Prompt -like '*Type UNVERIFIED*' }
        Mock Wait-TpmForProcessClose { throw 'A backup that could not be checked must stop before the process check.' }
        # Take the real inventory first, then lock the record: only the completion check itself then hits the lock.
        $script:Fx29RealInventory = @(Get-TpmUserProfilesBackupInventory -BackupPath $backup.Path)
        Mock Get-TpmUserProfilesBackupInventory { $script:Fx29RealInventory }
        $lock = [System.IO.File]::Open((Join-Path $backup.Path 'TPM-BACKUP-COMPLETE.json'), [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        try {
            $result = Invoke-RestoreBackupLegacy -userProfilesDir $userProfilesDir
        } finally { $lock.Dispose() }
        $result.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        $result.Summary | Should -Match 'could not be checked right now'
        $result.Summary | Should -Not -Match 'does not match'
        (Get-Fx29Screen) | Should -Match 'could not be checked right now'
        (Get-Fx29Screen) | Should -Not -Match 'failed its completeness check'
        Get-RestoreFixtureSnapshot -UserProfilesDir $userProfilesDir | Should -BeExactly $liveBefore
    }

    It "shows the total file count of an older backup without a record and stops unless UNVERIFIED is typed" {
        $fixture = New-IsolatedRestoreFixture -Name 'fx29-legacy-decline'
        [void](New-Item -ItemType Directory -Path (Join-Path $fixture.BackupDir 'Nested') -Force)
        [System.IO.File]::WriteAllText((Join-Path $fixture.BackupDir 'Nested\Other.xml'), '<GameProfile>other</GameProfile>')
        $baseline = Get-RestoreFixtureSnapshot -UserProfilesDir $fixture.UserProfilesDir
        Mock Read-Host { return '1' } -ParameterFilter { $Prompt -like '*Enter number to restore*' }
        # The overwrite question for an older copy: the first answer opens Details, the second declines it.
        $script:fx29UnverifiedAnswers = New-Object 'System.Collections.Generic.Queue[string]'
        foreach ($answer in @('D', 'YES')) { [void]$script:fx29UnverifiedAnswers.Enqueue($answer) }
        Mock Read-Host { return $script:fx29UnverifiedAnswers.Dequeue() } -ParameterFilter { $Prompt -like '*Type UNVERIFIED*' }
        Mock Read-Host { throw 'The overwrite confirmation must not be reached without UNVERIFIED.' } -ParameterFilter { $Prompt -like '*Type YES to confirm*' }
        Mock Wait-TpmForProcessClose { throw 'Restore must not reach the process-close step.' }

        $result = Invoke-RestoreBackupLegacy -userProfilesDir $fixture.UserProfilesDir

        $result.Outcome | Should -Be 'NO_OP'
        $result.ReasonCode | Should -Be 'USER_DECLINED'
        # Mutation: drop the older-copy warning from the screen, or the file total from Details or the log -> the user is not told how much the copy holds.
        $screen = Get-Fx29Screen
        $screen | Should -Match 'This copy cannot be checked\. TeknoParrot Manager cannot be sure it is complete\.'
        $screen | Should -Match 'Press D to see the details first\.'
        $screen | Should -Match 'Files: 2 Games: 1 Check: It has no completion record'
        $script:fx29UnverifiedAnswers.Count | Should -Be 0
        @($script:fx29LogLines | Where-Object { $_ -like 'Restore: selected backup * (1 profile(s), 2 file(s) in total).' }).Count | Should -Be 1
        Get-RestoreFixtureSnapshot -UserProfilesDir $fixture.UserProfilesDir | Should -BeExactly $baseline
    }

    It "keeps the pre-restore snapshot and reports ACTION_REQUIRED when the restored profiles do not equal the backup" {
        $userProfilesDir = New-RestoreFixture -Name 'fx29-verify-fails'
        [System.IO.File]::WriteAllText((Join-Path $userProfilesDir 'A.xml'), '<GameProfile>a</GameProfile>')
        $backup = New-TpmVerifiedUserProfilesBackup -UserProfilesDir $userProfilesDir -Label 'Fixture'
        $backup.Verified | Should -BeTrue -Because ([string]$backup.Reason)
        [System.IO.File]::Delete((Join-Path $userProfilesDir 'A.xml'))
        [System.IO.File]::WriteAllText((Join-Path $userProfilesDir 'CURRENT.xml'), '<GameProfile>current</GameProfile>')
        $script:fx29LiveDir = $userProfilesDir
        # A writer adds a profile right after the copy finished; the copy itself reports no error.
        Mock Write-TpmCompactExtractionProgress {
            if ($Label -eq 'UserProfiles restore' -and $Complete) { [System.IO.File]::WriteAllText((Join-Path $script:fx29LiveDir 'Intruder.xml'), '<GameProfile>x</GameProfile>') }
        }
        Mock Read-Host { return '1' } -ParameterFilter { $Prompt -like '*Enter number to restore*' }
        Mock Read-Host { return 'YES' } -ParameterFilter { $Prompt -like '*Type YES to confirm*' }
        Mock Wait-TpmForProcessClose { return $true }

        $result = Invoke-RestoreBackupLegacy -userProfilesDir $userProfilesDir

        try {
            $result.Outcome | Should -Be 'ACTION_REQUIRED'
            $result.ReasonCode | Should -Be 'RESTORE_VERIFICATION_FAILED'
            $result.Succeeded | Should -BeFalse
            [string]::IsNullOrWhiteSpace([string]$result.RollbackPath) | Should -BeFalse
            [System.IO.File]::ReadAllText((Join-Path $result.RollbackPath 'CURRENT.xml')) | Should -Be '<GameProfile>current</GameProfile>'
            @($script:fx29HostLines | Where-Object { $_ -like ('*' + $result.RollbackPath + '*') }).Count | Should -BeGreaterThan 0
        } finally {
            if ($result.RollbackPath -and ([System.IO.Path]::GetFileName([string]$result.RollbackPath) -like 'tpm-restore-rollback-*') -and (Test-Path -LiteralPath $result.RollbackPath)) {
                [System.IO.Directory]::Delete([string]$result.RollbackPath, $true)
            }
        }
    }
}
