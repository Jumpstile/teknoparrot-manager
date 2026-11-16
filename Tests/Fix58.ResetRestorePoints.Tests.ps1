#Requires -Module Pester

# FIX58 (issue #348): verified start-up restore points and the Reset and
# Restore menu (Restore backup, option 4). A restore point is a verified copy
# of UserProfiles plus the TeknoParrot Manager settings file, recorded in a
# manifest (every file with length and SHA-256, and the settings file's hash or
# absence). The first one (Baseline) is kept separately; an unchanged state
# reuses the newest checked restore point instead of copying again; a failed or
# unverifiable restore point stops what depends on it. Reset/Restore puts back
# one game or everything through the existing verified UserProfiles restore
# transaction, makes a retained BeforeReset restore point first, checks bytes
# afterwards and rolls back on failure.
#
# The production script is parsed and only its function definitions are
# dot-sourced; no top-level product code runs. Every file lives under
# TestDrive; TeknoParrot is never started or stopped (Wait-TpmForProcessClose
# is mocked). Each It names the product mutation that makes it fail.

BeforeAll {
    $script:Fix58PriorWorkflowState = @{}
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $snapshot = Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
        $script:Fix58PriorWorkflowState[$name] = [pscustomobject]@{ Exists = ($null -ne $snapshot); Value = $(if ($null -ne $snapshot) { $snapshot.Value } else { $null }) }
    }
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false

    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($productionPath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX58 tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:Fix58FunctionFile = Join-Path $TestDrive 'tpm-fix58-functions.ps1'
    [System.IO.File]::WriteAllText($script:Fix58FunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:Fix58FunctionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:logPath = Join-Path $TestDrive 'fix58.log'

    function New-F58Fixture {
        param([Parameter(Mandatory)][string]$Name)
        $root = Join-Path $TestDrive ('f58-' + $Name + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $profiles = Join-Path $root 'UserProfiles'
        $stateDir = Join-Path $root 'State'
        New-Item -ItemType Directory -Path $profiles, $stateDir -Force | Out-Null
        $state = [pscustomobject]@{
            Log = New-Object System.Collections.Generic.List[string]
            Screen = New-Object System.Collections.Generic.List[string]
            Prompts = New-Object System.Collections.Generic.List[string]
            Answers = New-Object 'System.Collections.Generic.Queue[string]'
        }
        return [pscustomobject]@{
            Root = $root
            Profiles = $profiles
            Points = (Join-Path $root 'RestorePoints')
            Config = (Join-Path $stateDir 'TeknoParrot-Manager.config.json')
            State = $state
        }
    }

    function Set-F58File {
        param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Text)
        [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
    }

    function Get-F58Text {
        param([Parameter(Mandatory)][string]$Path)
        return [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding $false))
    }

    function Get-F58Sha {
        param([Parameter(Mandatory)][string]$Path)
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    }

    function Get-F58ScreenText {
        param([Parameter(Mandatory)]$Fixture)
        return ((@($Fixture.State.Screen) -join ' ') -replace '\s+', ' ')
    }

    function Get-F58BackupFolders {
        param([Parameter(Mandatory)]$Fixture)
        $backupRoot = Join-Path $Fixture.Profiles 'FullBackup'
        if (-not (Test-Path -LiteralPath $backupRoot)) { return @() }
        return @(Get-ChildItem -LiteralPath $backupRoot -Directory -Force | Sort-Object Name)
    }

    function Install-F58Mocks {
        param([Parameter(Mandatory)]$Fixture, [string[]]$Answers = @())
        $script:F58State = $Fixture.State
        foreach ($answer in $Answers) { [void]$Fixture.State.Answers.Enqueue($answer) }
        Mock Write-Log { [void]$script:F58State.Log.Add([string]$msg) }
        Mock Write-Host { [void]$script:F58State.Screen.Add(([string]($Object -join ' '))) }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Wait-TpmForProcessClose { return $true }
        Mock Read-HostSafe {
            [void]$script:F58State.Prompts.Add([string]$Prompt)
            if ($script:F58State.Answers.Count -eq 0) { throw ("UNEXPECTED PROMPT '{0}'" -f $Prompt) }
            return $script:F58State.Answers.Dequeue()
        }
    }

    # Baseline fixture: two games and a settings file, then one start-up restore point.
    function New-F58Baseline {
        param([Parameter(Mandatory)]$Fixture)
        Set-F58File -Path (Join-Path $Fixture.Profiles 'GameA.xml') -Text '<GameProfile><GameName>Game A</GameName><Value>a-old</Value></GameProfile>'
        Set-F58File -Path (Join-Path $Fixture.Profiles 'GameB.xml') -Text '<GameProfile><GameName>Game B</GameName><Value>b-old</Value></GameProfile>'
        Set-F58File -Path $Fixture.Config -Text '{"TeknoParrotRoot":"C:\\TP","Marker":"settings-old"}'
        $startup = Invoke-TpmStartupRestorePoint -UserProfilesDir $Fixture.Profiles -ConfigPath $Fixture.Config -RestorePointsRoot $Fixture.Points
        if (-not $startup.Succeeded) { throw ('Fixture baseline failed: ' + $startup.Reason) }
        return (Read-TpmRestorePoint -Path $startup.Path)
    }
}

AfterAll {
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $prior = $script:Fix58PriorWorkflowState[$name]
        if ($prior.Exists) { Set-Variable -Name $name -Scope Script -Value $prior.Value } else { Remove-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue }
    }
    Remove-Variable -Name TpmConfigRestoreRestartRequired -Scope Script -ErrorAction SilentlyContinue
}

Describe 'FIX58 start-up restore points' {
    BeforeEach { $script:TpmConfigRestoreRestartRequired = $false }

    It 'saves a verified Baseline that records every file, its SHA-256 and the settings file bytes, without any prompt' {
        # Mutation: drop the settings-file copy or record the wrong hash in New-TpmRestorePoint -> the settings assertions fail;
        # add any prompt to the start-up restore point path (Read-HostSafe, Read-Host, Read-TpmChoice or Read-TpmYesNo) ->
        # that prompt is invoked (start-up must not wait for input).
        $fx = New-F58Fixture -Name 'baseline'
        Install-F58Mocks -Fixture $fx
        Mock Read-Host { throw 'Read-Host must not be called while a start-up restore point is made.' }
        Mock Read-TpmChoice { throw 'Read-TpmChoice must not be called while a start-up restore point is made.' }
        Mock Read-TpmYesNo { throw 'Read-TpmYesNo must not be called while a start-up restore point is made.' }
        $point = New-F58Baseline -Fixture $fx

        $point.Readable | Should -BeTrue
        $point.Kind | Should -BeExactly 'Baseline'
        $entryA = @($point.Record.Entries | Where-Object { $_.RelativePath -eq 'GameA.xml' })[0]
        $entryA.Sha256 | Should -BeExactly (Get-F58Sha -Path (Join-Path $fx.Profiles 'GameA.xml'))
        [int]$point.Record.FileCount | Should -Be 2
        $point.Record.Config.Present | Should -BeTrue
        $point.Record.Config.Sha256 | Should -BeExactly (Get-F58Sha -Path $fx.Config)
        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Join-Path $point.Path 'settings.json'))) | Should -BeExactly ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($fx.Config)))
        (Test-TpmRestorePoint -RestorePoint $point -UserProfilesDir $fx.Profiles).Valid | Should -BeTrue
        @(Get-F58BackupFolders -Fixture $fx).Count | Should -Be 1
        @(Get-F58BackupFolders -Fixture $fx)[0].Name | Should -BeLike 'Baseline_*'
        Should -Invoke Read-HostSafe -Times 0 -Exactly
        Should -Invoke Read-Host -Times 0 -Exactly
        Should -Invoke Read-TpmChoice -Times 0 -Exactly
        Should -Invoke Read-TpmYesNo -Times 0 -Exactly
    }

    It 'reuses the newest restore point when nothing changed and keeps the first one separate after a change' {
        # Mutation: remove the unchanged-state reuse in Invoke-TpmStartupRestorePoint -> every start copies UserProfiles again;
        # always use Kind Baseline -> the first baseline is no longer the only one.
        $fx = New-F58Fixture -Name 'repeat'
        Install-F58Mocks -Fixture $fx
        $first = New-F58Baseline -Fixture $fx

        $second = Invoke-TpmStartupRestorePoint -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points
        $second.Succeeded | Should -BeTrue
        $second.Reused | Should -BeTrue
        $second.Created | Should -BeFalse
        $second.Path | Should -BeExactly $first.Path
        @(Get-F58BackupFolders -Fixture $fx).Count | Should -Be 1

        Set-F58File -Path (Join-Path $fx.Profiles 'GameB.xml') -Text '<GameProfile><GameName>Game B</GameName><Value>b-new</Value></GameProfile>'
        $third = Invoke-TpmStartupRestorePoint -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points
        $third.Created | Should -BeTrue
        $third.Kind | Should -BeExactly 'Startup'
        $points = @(Get-TpmRestorePoints -RestorePointsRoot $fx.Points)
        @($points | Where-Object { $_.Kind -eq 'Baseline' }).Count | Should -Be 1
        @($points | Where-Object { $_.Kind -eq 'Baseline' })[0].Path | Should -BeExactly $first.Path
        @(Get-F58BackupFolders -Fixture $fx).Count | Should -Be 2
    }

    It 'stops with a plain reason and publishes nothing when the game settings copy cannot be verified' {
        # Mutation: ignore the Verified flag of New-TpmVerifiedUserProfilesBackup -> an unverified restore point is published.
        $fx = New-F58Fixture -Name 'copyfail'
        Install-F58Mocks -Fixture $fx
        Set-F58File -Path (Join-Path $fx.Profiles 'GameA.xml') -Text 'a'
        Mock New-TpmVerifiedUserProfilesBackup { [pscustomobject]@{ Verified = $false; Succeeded = $false; Path = $null; Manifest = @(); Reason = 'Backup verification failed for GameA.xml.'; ResiduePaths = @() } }

        $result = Invoke-TpmStartupRestorePoint -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $result.Succeeded | Should -BeFalse
        $result.Reason | Should -Match 'could not be made and checked'
        @(Get-ChildItem -LiteralPath $fx.Points -Force -ErrorAction SilentlyContinue).Count | Should -Be 0
        @(Get-TpmRestorePoints -RestorePointsRoot $fx.Points).Count | Should -Be 0
    }

    It 'refuses before copying anything when the drive has too little free space' {
        # Mutation: remove the free-space check in New-TpmRestorePoint -> a FullBackup folder is created anyway.
        $fx = New-F58Fixture -Name 'space'
        Install-F58Mocks -Fixture $fx
        Set-F58File -Path (Join-Path $fx.Profiles 'GameA.xml') -Text 'a'
        Mock Get-TpmRestorePointFreeBytes { return [int64]1 }

        $result = Invoke-TpmStartupRestorePoint -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $result.Succeeded | Should -BeFalse
        $result.Reason | Should -Match 'not enough free disk space'
        Test-Path -LiteralPath (Join-Path $fx.Profiles 'FullBackup') | Should -BeFalse
        Test-Path -LiteralPath $fx.Points | Should -BeFalse
    }

    It 'does not reuse a restore point whose copy was changed; it reports it damaged and makes a new one' {
        # Mutation: reuse the newest restore point without Test-TpmRestorePoint -> the damaged copy stays the only one.
        # FIX61: the damaged point is the first restore point, so the new one is a Baseline (a Baseline counts only while its copy passes the check).
        $fx = New-F58Fixture -Name 'damaged'
        Install-F58Mocks -Fixture $fx
        $first = New-F58Baseline -Fixture $fx
        $copy = Join-Path (Join-Path (Join-Path $fx.Profiles 'FullBackup') ([string]$first.Record.UserProfilesBackup)) 'GameA.xml'
        Set-F58File -Path $copy -Text 'tampered'

        $check = Test-TpmRestorePoint -RestorePoint $first -UserProfilesDir $fx.Profiles
        $check.Valid | Should -BeFalse
        $check.Reason | Should -Match 'failed its check'
        $next = Invoke-TpmStartupRestorePoint -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points
        $next.Created | Should -BeTrue
        $next.Kind | Should -BeExactly 'Baseline'
    }

    It 'treats a changed settings copy and an unreadable record as unusable' {
        # Mutation: skip the settings-copy hash check in Test-TpmRestorePoint -> the changed copy is accepted;
        # treat a record that fails to parse as readable -> a damaged point is offered.
        $fx = New-F58Fixture -Name 'records'
        Install-F58Mocks -Fixture $fx
        $first = New-F58Baseline -Fixture $fx
        Set-F58File -Path (Join-Path $first.Path 'settings.json') -Text '{"changed":true}'
        $check = Test-TpmRestorePoint -RestorePoint $first -UserProfilesDir $fx.Profiles
        $check.Valid | Should -BeFalse
        $check.Reason | Should -Match 'settings'

        Set-F58File -Path (Join-Path $first.Path 'restore-point.json') -Text '{ not json'
        $listed = @(Get-TpmRestorePoints -RestorePointsRoot $fx.Points)
        $listed.Count | Should -Be 1
        $listed[0].Readable | Should -BeFalse
        $menu = Invoke-TpmResetRestoreMenu -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points
        $menu.RestartRequired | Should -BeFalse
        Should -Invoke Read-HostSafe -Times 0 -Exactly
        (Get-F58ScreenText -Fixture $fx) | Should -Match '1 restore point is damaged and is not offered'
    }
}

Describe 'FIX58 Reset and Restore for one game' {
    BeforeEach { $script:TpmConfigRestoreRestartRequired = $false }

    It 'puts back only the chosen game byte for byte, keeps later edits of other games and keeps a BeforeReset restore point' {
        # Mutation: restore the whole UserProfiles folder instead of the one file -> GameB loses its later edit;
        # skip the BeforeReset restore point -> the previous GameA bytes are not recoverable.
        $fx = New-F58Fixture -Name 'onegame'
        Install-F58Mocks -Fixture $fx
        $baseline = New-F58Baseline -Fixture $fx
        $gameA = Join-Path $fx.Profiles 'GameA.xml'
        $gameB = Join-Path $fx.Profiles 'GameB.xml'
        $oldA = Get-F58Text -Path $gameA
        Set-F58File -Path $gameA -Text '<GameProfile><GameName>Game A</GameName><Value>a-new</Value></GameProfile>'
        Set-F58File -Path $gameB -Text '<GameProfile><GameName>Game B</GameName><Value>b-new</Value></GameProfile>'
        $newASha = Get-F58Sha -Path $gameA

        $result = Restore-TpmRestorePointGame -RestorePoint $baseline -UserProfilesDir $fx.Profiles -RelativePath 'GameA.xml' -ExpectedCurrentSha256 $newASha -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        Get-F58Text -Path $gameA | Should -BeExactly $oldA
        Get-F58Text -Path $gameB | Should -Match 'b-new'
        $safety = Read-TpmRestorePoint -Path $result.SafetyRestorePoint
        $safety.Kind | Should -BeExactly 'BeforeReset'
        @($safety.Record.Entries | Where-Object { $_.RelativePath -eq 'GameA.xml' })[0].Sha256 | Should -BeExactly $newASha
        @(Get-ChildItem -LiteralPath $fx.Profiles -Filter '*.tpm-restore' -Force).Count | Should -Be 0
    }

    It 'changes nothing when the game changed after the preview' {
        # Mutation: drop the ExpectedCurrentSha256 check -> the later edit is overwritten without a new preview.
        $fx = New-F58Fixture -Name 'drift'
        Install-F58Mocks -Fixture $fx
        $baseline = New-F58Baseline -Fixture $fx
        $gameA = Join-Path $fx.Profiles 'GameA.xml'
        Set-F58File -Path $gameA -Text 'a-edited-after-preview'

        $result = Restore-TpmRestorePointGame -RestorePoint $baseline -UserProfilesDir $fx.Profiles -RelativePath 'GameA.xml' -ExpectedCurrentSha256 ('0' * 64) -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -BeExactly 'CHANGED_SINCE_PREVIEW'
        Get-F58Text -Path $gameA | Should -BeExactly 'a-edited-after-preview'
        @(Get-TpmRestorePoints -RestorePointsRoot $fx.Points).Count | Should -Be 1
        Should -Invoke Wait-TpmForProcessClose -Times 0 -Exactly
    }

    It 'leaves a game that the restore point does not have byte for byte as it was' {
        # Mutation: remove the NOT_IN_RESTORE_POINT guard in Restore-TpmRestorePointGame -> the game file is rewritten or
        # removed, a BeforeReset restore point is made, or TeknoParrot is waited for.
        $fx = New-F58Fixture -Name 'newgame'
        Install-F58Mocks -Fixture $fx
        $baseline = New-F58Baseline -Fixture $fx
        $gameC = Join-Path $fx.Profiles 'GameC.xml'
        Set-F58File -Path $gameC -Text 'c-added-later'
        $bytesBefore = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($gameC))
        $writtenBefore = (Get-Item -LiteralPath $gameC).LastWriteTimeUtc

        $result = Restore-TpmRestorePointGame -RestorePoint $baseline -UserProfilesDir $fx.Profiles -RelativePath 'GameC.xml' -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -BeExactly 'NOT_IN_RESTORE_POINT'
        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($gameC)) | Should -BeExactly $bytesBefore
        (Get-Item -LiteralPath $gameC).LastWriteTimeUtc | Should -Be $writtenBefore
        @(Get-TpmRestorePoints -RestorePointsRoot $fx.Points).Count | Should -Be 1
        @(Get-ChildItem -LiteralPath $fx.Profiles -Filter '*.tpm-restore' -Force).Count | Should -Be 0
        Should -Invoke Wait-TpmForProcessClose -Times 0 -Exactly
    }

    It 'changes nothing when the restore point copy is damaged' {
        # Mutation: skip Test-TpmRestorePoint in Restore-TpmRestorePointGame -> the tampered bytes are written into UserProfiles.
        $fx = New-F58Fixture -Name 'corruptcopy'
        Install-F58Mocks -Fixture $fx
        $baseline = New-F58Baseline -Fixture $fx
        Set-F58File -Path (Join-Path (Join-Path (Join-Path $fx.Profiles 'FullBackup') ([string]$baseline.Record.UserProfilesBackup)) 'GameA.xml') -Text 'tampered'
        $gameA = Join-Path $fx.Profiles 'GameA.xml'
        Set-F58File -Path $gameA -Text 'a-new'

        $result = Restore-TpmRestorePointGame -RestorePoint $baseline -UserProfilesDir $fx.Profiles -RelativePath 'GameA.xml' -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -BeExactly 'RESTORE_POINT_DAMAGED'
        Get-F58Text -Path $gameA | Should -BeExactly 'a-new'
    }

    It 'rolls back to the previous file and checks it when the swapped-in bytes are wrong' {
        # Mutation: remove the rollback in Restore-TpmRestorePointGame -> GameA keeps the corrupted bytes;
        # remove the after-swap hash check in Invoke-TpmVerifiedFileSwap -> SUCCEEDED is reported for wrong bytes.
        $fx = New-F58Fixture -Name 'rollback'
        Install-F58Mocks -Fixture $fx
        $baseline = New-F58Baseline -Fixture $fx
        $gameA = Join-Path $fx.Profiles 'GameA.xml'
        Set-F58File -Path $gameA -Text 'a-new'
        $script:F58ReplaceCalls = 0
        Mock Invoke-TpmAtomicFileReplace {
            $script:F58ReplaceCalls++
            if ($script:F58ReplaceCalls -eq 1) {
                # Like the real replace, keep the bytes that are replaced at -Backup.
                if ($Backup) { [System.IO.File]::Copy($Destination, $Backup) }
                [System.IO.File]::WriteAllText($Destination, 'corrupted')
                Remove-Item -LiteralPath $Source -Force
            } else {
                [System.IO.File]::Replace($Source, $Destination, $(if ($Backup) { $Backup } else { [NullString]::Value }))
            }
        }

        $result = Restore-TpmRestorePointGame -RestorePoint $baseline -UserProfilesDir $fx.Profiles -RelativePath 'GameA.xml' -ExpectedCurrentSha256 (Get-F58Sha -Path $gameA) -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $result.Outcome | Should -BeExactly 'ROLLED_BACK_VERIFIED'
        Get-F58Text -Path $gameA | Should -BeExactly 'a-new'
        $script:F58ReplaceCalls | Should -Be 2
        @(Get-ChildItem -LiteralPath $fx.Profiles -Filter '*.tpm-restore' -Force).Count | Should -Be 0
    }

    It 'menu: shows the game and what changes, cancels on anything but YES, and puts the game back on YES' {
        # Mutation: call Restore-TpmRestorePointGame before the YES confirmation -> GameA changes on NO;
        # drop the preview line -> the screen does not say the whole settings file goes back.
        $fx = New-F58Fixture -Name 'menuone'
        Install-F58Mocks -Fixture $fx -Answers @('2', '1', '1', 'NO')
        $baseline = New-F58Baseline -Fixture $fx
        $gameA = Join-Path $fx.Profiles 'GameA.xml'
        $oldA = [System.IO.File]::ReadAllText((Join-Path (Join-Path (Join-Path $fx.Profiles 'FullBackup') ([string]$baseline.Record.UserProfilesBackup)) 'GameA.xml'))
        Set-F58File -Path $gameA -Text '<GameProfile><GameName>Game A</GameName><Value>a-new</Value></GameProfile>'

        $declined = Invoke-TpmResetRestoreMenu -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points
        $declined.Result.ReasonCode | Should -BeExactly 'USER_DECLINED'
        Get-F58Text -Path $gameA | Should -Match 'a-new'
        @(Get-TpmRestorePoints -RestorePointsRoot $fx.Points).Count | Should -Be 1
        $screen = Get-F58ScreenText -Fixture $fx
        $screen | Should -Match 'Game: Game A'
        $screen | Should -Not -Match 'Game A \(GameA\)'
        $screen | Should -Match 'whole settings file goes back'

        foreach ($answer in @('2', '1', '1', 'YES')) { [void]$fx.State.Answers.Enqueue($answer) }
        $accepted = Invoke-TpmResetRestoreMenu -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points
        $accepted.Result.Outcome | Should -BeExactly 'SUCCEEDED'
        $accepted.RestartRequired | Should -BeFalse
        Get-F58Text -Path $gameA | Should -BeExactly $oldA
        $fx.State.Answers.Count | Should -Be 0
    }
}

Describe 'FIX58 Reset and Restore for all games' {
    BeforeEach { $script:TpmConfigRestoreRestartRequired = $false }

    It 'puts back every game and the settings file through the verified restore, then refuses to save stale settings' {
        # Mutation: skip the settings file in Restore-TpmRestorePointAll -> the settings stay new;
        # remove the latch check in Save-Config -> the stale in-memory settings overwrite the restored file.
        $fx = New-F58Fixture -Name 'all'
        Install-F58Mocks -Fixture $fx
        $baseline = New-F58Baseline -Fixture $fx
        $oldConfig = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($fx.Config))
        $oldA = Get-F58Text -Path (Join-Path $fx.Profiles 'GameA.xml')
        $oldB = Get-F58Text -Path (Join-Path $fx.Profiles 'GameB.xml')
        Set-F58File -Path (Join-Path $fx.Profiles 'GameA.xml') -Text 'a-new'
        Remove-Item -LiteralPath (Join-Path $fx.Profiles 'GameB.xml') -Force
        Set-F58File -Path (Join-Path $fx.Profiles 'GameC.xml') -Text 'c-added-later'
        Set-F58File -Path $fx.Config -Text '{"TeknoParrotRoot":"C:\\TP","Marker":"settings-new"}'

        $plan = Get-TpmRestorePointChangePlan -RestorePoint $baseline -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config
        (@($plan.Changes | Where-Object { $_.RelativePath -eq 'GameA.xml' })[0]).Change | Should -BeExactly 'Replace'
        (@($plan.Changes | Where-Object { $_.RelativePath -eq 'GameB.xml' })[0]).Change | Should -BeExactly 'PutBack'
        (@($plan.Changes | Where-Object { $_.RelativePath -eq 'GameC.xml' })[0]).Change | Should -BeExactly 'Remove'
        $plan.ConfigChange | Should -BeExactly 'Replace'

        $result = Restore-TpmRestorePointAll -RestorePoint $baseline -UserProfilesDir $fx.Profiles -Plan $plan -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        $result.RestartRequired | Should -BeTrue
        Get-F58Text -Path (Join-Path $fx.Profiles 'GameA.xml') | Should -BeExactly $oldA
        Get-F58Text -Path (Join-Path $fx.Profiles 'GameB.xml') | Should -BeExactly $oldB
        Test-Path -LiteralPath (Join-Path $fx.Profiles 'GameC.xml') | Should -BeFalse
        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($fx.Config)) | Should -BeExactly $oldConfig
        $safety = Read-TpmRestorePoint -Path $result.SafetyRestorePoint
        @($safety.Record.Entries | Where-Object { $_.RelativePath -eq 'GameC.xml' }).Count | Should -Be 1

        $configPath = $fx.Config
        Save-Config | Should -BeFalse
        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($fx.Config)) | Should -BeExactly $oldConfig
    }

    It 'changes nothing when settings changed after the preview' {
        # Mutation: drop the CurrentStateKey comparison in Restore-TpmRestorePointAll -> the later edit is overwritten.
        $fx = New-F58Fixture -Name 'alldrift'
        Install-F58Mocks -Fixture $fx
        $baseline = New-F58Baseline -Fixture $fx
        Set-F58File -Path (Join-Path $fx.Profiles 'GameA.xml') -Text 'a-new'
        $plan = Get-TpmRestorePointChangePlan -RestorePoint $baseline -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config
        Set-F58File -Path (Join-Path $fx.Profiles 'GameB.xml') -Text 'b-edited-after-preview'

        $result = Restore-TpmRestorePointAll -RestorePoint $baseline -UserProfilesDir $fx.Profiles -Plan $plan -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $result.ReasonCode | Should -BeExactly 'CHANGED_SINCE_PREVIEW'
        Get-F58Text -Path (Join-Path $fx.Profiles 'GameA.xml') | Should -BeExactly 'a-new'
        Get-F58Text -Path (Join-Path $fx.Profiles 'GameB.xml') | Should -BeExactly 'b-edited-after-preview'
        $result.RestartRequired | Should -BeFalse
    }

    It 'menu: all games needs YES and then ALL; a missing second confirmation changes nothing' {
        # Mutation: remove the second (ALL) confirmation in Invoke-TpmResetRestoreAllGames -> every file changes after one YES.
        $fx = New-F58Fixture -Name 'menuall'
        Install-F58Mocks -Fixture $fx -Answers @('4', '1', 'YES', 'no')
        $null = New-F58Baseline -Fixture $fx
        Set-F58File -Path (Join-Path $fx.Profiles 'GameA.xml') -Text 'a-new'

        $menu = Invoke-TpmResetRestoreMenu -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $menu.Result.ReasonCode | Should -BeExactly 'USER_DECLINED'
        Get-F58Text -Path (Join-Path $fx.Profiles 'GameA.xml') | Should -BeExactly 'a-new'
        @(Get-TpmRestorePoints -RestorePointsRoot $fx.Points).Count | Should -Be 1
        @($fx.State.Prompts | Where-Object { $_ -like '*Type ALL*' }).Count | Should -Be 1
    }

    It 'the UserProfiles restore refuses a preselected folder outside FullBackup and still asks YES without -AlreadyConfirmed' {
        # Mutation: accept any -SelectedBackupPath in Invoke-RestoreBackupLegacy -> the outside folder is restored;
        # skip the YES prompt whenever a path is preselected -> the ordinary restore loses its confirmation.
        $fx = New-F58Fixture -Name 'legacy'
        Install-F58Mocks -Fixture $fx -Answers @('no')
        $baseline = New-F58Baseline -Fixture $fx
        Set-F58File -Path (Join-Path $fx.Profiles 'GameA.xml') -Text 'a-new'
        $outside = Join-Path $fx.Root 'Outside'
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        Set-F58File -Path (Join-Path $outside 'Evil.xml') -Text 'outside'

        $refused = Invoke-RestoreBackupLegacy -userProfilesDir $fx.Profiles -SelectedBackupPath $outside -AlreadyConfirmed
        $refused.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $refused.ReasonCode | Should -BeExactly 'BACKUP_UNAVAILABLE'
        Test-Path -LiteralPath (Join-Path $fx.Profiles 'Evil.xml') | Should -BeFalse
        Should -Invoke Read-HostSafe -Times 0 -Exactly

        $backupPath = Join-Path (Join-Path $fx.Profiles 'FullBackup') ([string]$baseline.Record.UserProfilesBackup)
        $declined = Invoke-RestoreBackupLegacy -userProfilesDir $fx.Profiles -SelectedBackupPath $backupPath
        $declined.ReasonCode | Should -BeExactly 'USER_DECLINED'
        Get-F58Text -Path (Join-Path $fx.Profiles 'GameA.xml') | Should -BeExactly 'a-new'
        @($fx.State.Prompts | Where-Object { $_ -like '*Type YES to confirm*' }).Count | Should -Be 1
    }
}

Describe 'FIX58 removing older restore points' {
    It 'keeps the first restore point and the newest ones, and keeps a folder it cannot prove it made' {
        # Mutation: include Baseline in Get-TpmRestorePointRemovalCandidates -> the first restore point is removed;
        # drop the completion-record Producer check in Remove-TpmRestorePoint -> a folder made by another producer is deleted.
        $fx = New-F58Fixture -Name 'cleanup'
        Install-F58Mocks -Fixture $fx
        $baseline = New-F58Baseline -Fixture $fx
        $made = @()
        foreach ($value in @('one', 'two', 'three')) {
            Set-F58File -Path (Join-Path $fx.Profiles 'GameA.xml') -Text ('a-' + $value)
            $point = New-TpmRestorePoint -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -Kind 'Startup' -RestorePointsRoot $fx.Points
            $point.Succeeded | Should -BeTrue
            $made += $point
        }
        $points = @(Get-TpmRestorePoints -RestorePointsRoot $fx.Points)
        $candidates = @(Get-TpmRestorePointRemovalCandidates -RestorePoints $points -KeepCount 1)
        $candidates.Count | Should -Be 2
        @($candidates | Where-Object { $_.Kind -eq 'Baseline' }).Count | Should -Be 0
        @($candidates | Where-Object { $_.Path -eq $made[2].Path }).Count | Should -Be 0

        $foreign = @($candidates | Where-Object { $_.Path -eq $made[0].Path })[0]
        $foreignBackup = Join-Path (Join-Path $fx.Profiles 'FullBackup') ([string]$foreign.Record.UserProfilesBackup)
        $marker = Join-Path $foreignBackup 'TPM-BACKUP-COMPLETE.json'
        Set-F58File -Path $marker -Text ((Get-F58Text -Path $marker) -replace '"Producer":\s*"Startup"', '"Producer": "GpuFix"')
        $kept = Remove-TpmRestorePoint -RestorePoint $foreign -UserProfilesDir $fx.Profiles
        $kept.Removed | Should -BeFalse
        Test-Path -LiteralPath $foreign.Path | Should -BeTrue
        Test-Path -LiteralPath $foreignBackup | Should -BeTrue

        $own = @($candidates | Where-Object { $_.Path -eq $made[1].Path })[0]
        $ownBackup = Join-Path (Join-Path $fx.Profiles 'FullBackup') ([string]$own.Record.UserProfilesBackup)
        $removed = Remove-TpmRestorePoint -RestorePoint $own -UserProfilesDir $fx.Profiles
        $removed.Removed | Should -BeTrue
        Test-Path -LiteralPath $own.Path | Should -BeFalse
        Test-Path -LiteralPath $ownBackup | Should -BeFalse
        Test-Path -LiteralPath $baseline.Path | Should -BeTrue
    }
}
