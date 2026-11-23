#Requires -Module Pester

# FIX98: honest results. A failure is never shown as success and a success never as failure: exit code, final screen, log and
# progress bar must agree.
#
#  S6  Unattended Health Check: an inspection that could not look at everything says so and exits non-zero (2); a finished
#      inspection that found problems in the library still exits 0. The progress row is "incomplete", not FAILED.
#  S7  Controls with no usable reference game for a family are skipped by design: NO_OP alone, done alongside saved games.
#      Real save/backup failures stay FAILED even beside design skips.
#  S8  A stall (silent for 60+ seconds) is telemetry. Work that later finishes closes as done. Error, Cancelled and Incomplete
#      keep priority (Error > Cancelled > Incomplete > Stalled), whatever order they were recorded in.
#  S9  Registration screens pass the real unattended state and keep their details for the final return prompt (D).
#
# The production script is parsed and only the needed function definitions are dot-sourced. Every file lives under TestDrive.
# No TeknoParrot, service, registry or network is touched. Each It names the product mutation that makes it fail.

BeforeAll {
    $script:Fix98ProductionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $script:Fix98Tokens = $null
    $script:Fix98Errors = $null
    $script:Fix98Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Fix98ProductionPath, [ref]$script:Fix98Tokens, [ref]$script:Fix98Errors)
    if ($script:Fix98Errors.Count -gt 0) { throw 'FIX98 tests could not parse the production script.' }
}

Describe 'FIX98 S8 a stall is telemetry, not the final result' {
    BeforeAll {
        Get-Module -Name TpmProgress -All | Remove-Module -Force
        Import-Module ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1'))) -Force -ErrorAction Stop
        function Get-Fix98LastLine { return $global:Fix98Lines[$global:Fix98Lines.Count - 1] }
    }
    AfterAll { Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue }
    BeforeEach {
        $global:Fix98Now = [datetime]'2026-01-01T00:00:00'
        $global:Fix98Lines = New-Object System.Collections.Generic.List[string]
        Mock Get-TpmProgressDefaultColumns { @('Spinner', 'Description', 'Bar', 'Percentage', 'Count', 'Elapsed', 'Remaining') } -ModuleName TpmProgress
        Mock Start-TpmProgressRefresh {} -ModuleName TpmProgress
        Mock Get-TpmProgressCursorVisible { $true } -ModuleName TpmProgress
        Mock Set-TpmProgressCursorVisible {} -ModuleName TpmProgress
        Mock Get-TpmProgressNow { $global:Fix98Now } -ModuleName TpmProgress
        Mock Test-TpmProgressOutputRedirected { $true } -ModuleName TpmProgress
        Mock Test-TpmProgressColorEnabled { $false } -ModuleName TpmProgress
        Mock Get-TpmProgressStyle { 'Ascii' } -ModuleName TpmProgress
        Mock Write-TpmProgressPlainLine { [void]$global:Fix98Lines.Add($Text) } -ModuleName TpmProgress
        Mock Write-TpmProgressRaw { throw 'redirected output must not use the live console writer' } -ModuleName TpmProgress
    }
    AfterEach {
        Stop-TpmProgressAbandoned
        Remove-Variable -Name Fix98Now, Fix98Lines -Scope Global -ErrorAction SilentlyContinue
    }

    It 'closes done when a stage went silent for over a minute, resumed, and finished' {
        # Mutation: keep the first non-Final state (old Register-TpmProgressOutcome) and let a Stalled outcome replace the Final close -> the row says stalled.
        Start-TpmProgressOperation -Title 'Copy' -Stage 'Files' | Out-Null
        $global:Fix98Now = $global:Fix98Now.AddSeconds(75)
        Set-TpmProgressStage -Stage 'Files' -Current 1 -Total 0
        (Get-TpmProgressState).Outcome | Should -BeExactly 'Stalled'
        $global:Fix98Now = $global:Fix98Now.AddSeconds(2)
        Set-TpmProgressStage -Stage 'Files' -Current 2 -Total 0
        Complete-TpmProgressOperation -State Final
        $last = Get-Fix98LastLine
        $last | Should -Match '\bdone\b'
        $last | Should -Not -Match 'stalled|FAILED|incomplete'
    }

    It 'closes done when the work stayed silent for over a minute and then finished (the slow disk copy)' {
        # Mutation: turn a Final close after a silent gap into Stalled (the old Complete-TpmProgressOperation branch) -> the verified success reads stalled.
        Start-TpmProgressOperation -Title 'Copy' -Stage 'Files' | Out-Null
        $global:Fix98Now = $global:Fix98Now.AddSeconds(90)
        Complete-TpmProgressOperation -State Final
        $last = Get-Fix98LastLine
        $last | Should -Match '\bdone\b'
        $last | Should -Not -Match 'stalled'
    }

    It 'closes a workflow group done when one of its stages stalled and the owner returned a verified success' {
        # Mutation: register the stall on the group and let it win over the owner's Final close -> the group row says stalled.
        Start-TpmProgressOperation -Title 'Workflow' -Group | Out-Null
        $global:Fix98Now = $global:Fix98Now.AddSeconds(90)
        Set-TpmProgressStage -Stage 'Copying files' -Current 0 -Total 0
        $global:Fix98Now = $global:Fix98Now.AddSeconds(1)
        Complete-TpmProgressOperation -State Final
        $last = Get-Fix98LastLine
        $last | Should -Match '\bdone\b'
        $last | Should -Not -Match 'stalled'
    }

    It 'still closes FAILED when a real error was recorded after the stall' {
        # Mutation: keep the first recorded state (Stalled) when an Error arrives later -> the failure is hidden behind a stall.
        Start-TpmProgressOperation -Title 'Copy' -Stage 'Files' | Out-Null
        $global:Fix98Now = $global:Fix98Now.AddSeconds(75)
        Set-TpmProgressStage -Stage 'Files' -Current 1 -Total 0
        Register-TpmProgressOutcome -State Error
        Complete-TpmProgressOperation -State Final
        Get-Fix98LastLine | Should -Match 'FAILED'
    }

    It 'still closes FAILED when the stall is recorded after the error' {
        # Mutation: let a later Stalled replace an earlier Error -> the failure turns into done.
        Start-TpmProgressOperation -Title 'Copy' -Stage 'Files' | Out-Null
        Register-TpmProgressOutcome -State Error
        $global:Fix98Now = $global:Fix98Now.AddSeconds(75)
        Set-TpmProgressStage -Stage 'Files' -Current 1 -Total 0
        Complete-TpmProgressOperation -State Final
        Get-Fix98LastLine | Should -Match 'FAILED'
    }

    It 'closes canceled when the work was canceled after it stalled' {
        # Mutation: keep the first recorded state (Stalled) -> the cancellation reads stalled.
        Start-TpmProgressOperation -Title 'Copy' -Stage 'Files' | Out-Null
        $global:Fix98Now = $global:Fix98Now.AddSeconds(75)
        Set-TpmProgressStage -Stage 'Files' -Current 1 -Total 0
        Register-TpmProgressOutcome -State Cancelled
        Complete-TpmProgressOperation -State Final
        Get-Fix98LastLine | Should -Match 'canceled'
    }

    It 'records the worst outcome whatever the order: <First> then <Second> is <Expected>' -ForEach @(
        @{ First = 'Incomplete'; Second = 'Cancelled'; Expected = 'Cancelled' }
        @{ First = 'Cancelled'; Second = 'Incomplete'; Expected = 'Cancelled' }
        @{ First = 'Stalled'; Second = 'Incomplete'; Expected = 'Incomplete' }
        @{ First = 'Incomplete'; Second = 'Stalled'; Expected = 'Incomplete' }
        @{ First = 'Cancelled'; Second = 'Error'; Expected = 'Error' }
        @{ First = 'Error'; Second = 'Cancelled'; Expected = 'Error' }
    ) {
        # Mutation: first event wins (if ($null -eq $op.Outcome) { $op.Outcome = $State }) -> every case that expects the second state fails.
        Start-TpmProgressOperation -Title 'Copy' -Stage 'Files' | Out-Null
        Register-TpmProgressOutcome -State $First
        Register-TpmProgressOutcome -State $Second
        (Get-TpmProgressState).Outcome | Should -BeExactly $Expected
    }

    It 'a recorded <Recorded> beats an explicit <Close> close: the row says <Word>' -ForEach @(
        @{ Recorded = 'Error'; Close = 'Incomplete'; Word = 'FAILED' }
        @{ Recorded = 'Error'; Close = 'Stalled'; Word = 'FAILED' }
        @{ Recorded = 'Error'; Close = 'Cancelled'; Word = 'FAILED' }
        @{ Recorded = 'Cancelled'; Close = 'Stalled'; Word = 'canceled' }
        @{ Recorded = 'Cancelled'; Close = 'Incomplete'; Word = 'canceled' }
        @{ Recorded = 'Incomplete'; Close = 'Stalled'; Word = 'incomplete' }
    ) {
        # Mutation: consult the recorded outcome only for Final/No-op closes (the old line) -> the explicit milder close hides the unresolved error or cancellation.
        Start-TpmProgressOperation -Title 'Copy' -Stage 'Files' | Out-Null
        Register-TpmProgressOutcome -State $Recorded
        Complete-TpmProgressOperation -State $Close
        Get-Fix98LastLine | Should -Match $Word
    }

    It 'a milder recorded outcome does not weaken a worse explicit close' {
        # Mutation: always replace the close state with the recorded one -> a recorded stall turns an explicit Error close into stalled.
        Start-TpmProgressOperation -Title 'Copy' -Stage 'Files' | Out-Null
        Register-TpmProgressOutcome -State Stalled
        Complete-TpmProgressOperation -State Error
        Get-Fix98LastLine | Should -Match 'FAILED'
    }

    It 'still shows stalled when the owner itself closes the work as stalled' {
        # Mutation: ignore an explicit Stalled close -> an owner that declares a stall sees done.
        Start-TpmProgressOperation -Title 'Copy' -Stage 'Files' | Out-Null
        Complete-TpmProgressOperation -State Stalled
        Get-Fix98LastLine | Should -Match 'stalled'
    }
}

Describe 'FIX98 S6 and S7 an unfinished run is attention, a failed write stays FAILED' {
    BeforeAll {
        $definitions = @{}
        foreach ($node in $script:Fix98Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
            if (-not $definitions.ContainsKey($node.Name)) { $definitions[$node.Name] = @() }
            $definitions[$node.Name] += $node
        }
        $external = @('Write-Log', 'Write-TpmCompactExtractionProgress', 'Write-Host', 'Get-DetectedGpuVendor', 'Suspend-TpmProgressLine', 'Resume-TpmProgressLine',
            'Invoke-ControlPropagationLegacy', 'ConvertTo-TpmLegacyTransactionResult')
        $selected = @{}
        $pending = New-Object 'System.Collections.Generic.Queue[string]'
        foreach ($root in @('Invoke-LibraryHealthCheck', 'Get-TpmHealthCheckExitCode', 'Get-TpmProgressCloseState', 'Invoke-ControlPropagation',
                'Get-TpmControlPropagationSummary', 'Write-ControlPropagationResults')) { $pending.Enqueue($root) }
        while ($pending.Count) {
            $name = $pending.Dequeue()
            if ($selected.ContainsKey($name) -or $external -contains $name) { continue }
            if (-not $definitions.ContainsKey($name)) { throw "Missing production helper: $name" }
            if (@($definitions[$name]).Count -ne 1) { throw "Ambiguous production helper: $name" }
            $node = $definitions[$name][0]; $selected[$name] = $node
            foreach ($command in $node.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                $called = $command.GetCommandName()
                if ($called -and $definitions.ContainsKey($called) -and $external -notcontains $called) { $pending.Enqueue($called) }
            }
        }
        $functionPath = Join-Path $TestDrive 'fix98-s6-functions.ps1'
        [System.IO.File]::WriteAllText($functionPath, (($selected.Values | Sort-Object { $_.Extent.StartOffset } | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"), (New-Object System.Text.UTF8Encoding $false))
        . $functionPath
        function Write-Log { param([string]$Message) [void]$script:Fix98Log.Add($Message) }
        function Write-TpmCompactExtractionProgress { param([Parameter(ValueFromRemainingArguments = $true)]$Arguments) }
        function Get-DetectedGpuVendor { [pscustomobject]@{ Vendor = 'NVIDIA'; Name = 'isolated fixture' } }
        function Suspend-TpmProgressLine {}
        function Resume-TpmProgressLine {}
        function Invoke-ControlPropagationLegacy { param([Parameter(ValueFromRemainingArguments = $true)]$Arguments) }
        # Names every parameter Invoke-ControlPropagation passes: a Pester mock only sees $Outcome and $ReasonCode as variables if the command it replaces declares them.
        function ConvertTo-TpmLegacyTransactionResult {
            param($Legacy, $WorkflowKey, $OperationKey, $Items, $ChangedItems, $CompletedItems, $FailedItems, $SkippedItems, $Summary, $ReasonCode, $Backup, $MutationStarted, $Outcome, $ProductState)
        }
    }
    BeforeEach {
        $script:Fix98Log = New-Object 'System.Collections.Generic.List[string]'
        $script:Fix98Host = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-Host { [void]$script:Fix98Host.Add([string]($Object -join ' ')) }
        Mock Read-Host { 'B' }
        Mock Read-HostSafe { throw ("UNEXPECTED QUESTION '{0}'" -f $Prompt) }
        Mock Test-TpmInteractiveInput { $false }
        Mock Get-ConsoleContentWidth { 120 }
        Mock Get-Service { [pscustomobject]@{ Status = 'Stopped' } }
        Mock Start-Service { throw 'Health Check must never start a service.' }
        Mock Stop-Service { throw 'Health Check must never stop a service.' }
        $script:healthRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:profiles = Join-Path $script:healthRoot 'UserProfiles'
        [void][System.IO.Directory]::CreateDirectory($script:profiles)
        [void][System.IO.Directory]::CreateDirectory((Join-Path $script:healthRoot 'GameProfiles'))
        $script:PostgresServiceName = 'FIX98-test-service-must-never-exist'
        $script:PostgresBinDir = Join-Path $script:healthRoot 'pgsql'
        [void][System.IO.Directory]::CreateDirectory($script:PostgresBinDir)
        [System.IO.File]::WriteAllText((Join-Path $script:PostgresBinDir 'psql.exe'), 'inert marker, never execute')
        $script:FFBBlasterUnsupportedPlatforms = @('pcsx2x6')
        $script:FFBBlasterNamePattern = 'ffb.*blaster|blaster.*ffb'
    }

    It 'S6: an unreadable profile list is an incomplete check: reason code, exit code 2, progress row incomplete' {
        # Mutation: leave ReasonCode off the health result (or map ACTION_REQUIRED to Error) -> the progress row is FAILED again.
        # Mutation: return 0 for every outcome in Get-TpmHealthCheckExitCode -> an unattended run that could not look at the library exits 0.
        Mock Get-ChildItem { throw [System.UnauthorizedAccessException]::new('Injected profile enumeration denied') } -ParameterFilter { $LiteralPath -eq $script:profiles }
        $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot
        $result.Outcome | Should -BeExactly 'ACTION_REQUIRED'
        $result.ReasonCode | Should -BeExactly 'HEALTH_COVERAGE_INCOMPLETE'
        Get-TpmProgressCloseState -Result $result | Should -BeExactly 'Incomplete'
        Get-TpmHealthCheckExitCode -Result $result | Should -Be 2
    }

    It 'S6: a profile that cannot be classified makes the PostgreSQL inventory unknown, so the check is incomplete' {
        # Mutation: ignore PostgresInventoryStatus when choosing the exit code -> a malformed profile still exits 0.
        [System.IO.File]::WriteAllText((Join-Path $script:profiles 'BAD.xml'), '<GameProfile>')
        $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot
        $result.PostgresInventoryStatus | Should -BeExactly 'Unknown'
        Get-TpmProgressCloseState -Result $result | Should -BeExactly 'Incomplete'
        Get-TpmHealthCheckExitCode -Result $result | Should -Be 2
    }

    It 'S6: a finished check that found a broken game path still exits 0 and closes done' {
        # Mutation: return a non-zero exit code for every ordinary health finding -> a normal library with a problem looks like a failed run.
        [System.IO.File]::WriteAllText((Join-Path $script:profiles 'BROKENGAME.xml'), '<GameProfile><GamePath>C:\fix98-no-such-folder\game.exe</GamePath></GameProfile>')
        $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot
        @($result.Broken) | Should -Contain 'BROKENGAME'
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        $result.ReasonCode | Should -BeExactly 'HEALTH_CHECK_COMPLETED'
        Get-TpmProgressCloseState -Result $result | Should -BeExactly 'Final'
        Get-TpmHealthCheckExitCode -Result $result | Should -Be 0
    }

    It 'a game on a drive that is not connected says reconnect the drive, not pick a new path' {
        $letter = @('Z','Y','X','W','V','U','T') | Where-Object { -not (Test-Path -LiteralPath ($_ + ':\')) } | Select-Object -First 1
        [System.IO.File]::WriteAllText((Join-Path $script:profiles 'OFFLINEGAME.xml'), ('<GameProfile><GamePath>{0}:\Games\game.exe</GamePath></GameProfile>' -f $letter))
        [System.IO.File]::WriteAllText((Join-Path $script:profiles 'BROKENGAME.xml'), '<GameProfile><GamePath>C:\no-such-folder-for-health\game.exe</GamePath></GameProfile>')
        $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot
        @($result.DriveUnavailable) | Should -Be @('OFFLINEGAME')
        @($result.Broken) | Should -Be @('BROKENGAME')
        $rows = @(Get-TpmLibraryHealthRows -Result $result)
        $rows[0].Text | Should -Match 'Reconnect'
        $rows[0].Text | Should -Not -Match 'new path'
        @($rows | Where-Object Area -eq 'Game paths')[0].Text | Should -Match '^Needs attention - 1 game needs a new path'
    }

    It 'a game on a drive that is not connected points to R or S only when the next menu offers them' {
        # Mutation: put the R or S sentence back unconditionally -> the screen tells the user to type a key the menu does not have (a game with an empty saved path).
        $letter = @('Z','Y','X','W','V','U','T') | Where-Object { -not (Test-Path -LiteralPath ($_ + ':\')) } | Select-Object -First 1
        [System.IO.File]::WriteAllText((Join-Path $script:profiles 'OFFLINEGAME.xml'), ('<GameProfile><GamePath>{0}:\Games\game.exe</GamePath></GameProfile>' -f $letter))
        [System.IO.File]::WriteAllText((Join-Path $script:profiles 'EMPTYGAME.xml'), '<GameProfile><GamePath></GamePath></GameProfile>')
        $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot
        @($result.DriveUnavailable) | Should -Be @('OFFLINEGAME')
        @($result.Empty) | Should -Be @('EMPTYGAME')
        @(Get-TpmLibraryHealthRows -Result $result)[0].Text | Should -Match 'Reconnect'
        @(Get-TpmLibraryHealthRows -Result $result)[0].Text | Should -Not -Match 'R or S'
    }

    It 'a graphics card that was not detected is an unfinished check, so exit code 2' {
        # Mutation: ignore the GPU row when choosing the outcome -> a PC where the card was never checked exits 0.
        Mock Get-DetectedGpuVendor { [pscustomobject]@{ Vendor = $null; Name = 'isolated fixture' } }
        $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot
        $result.Outcome | Should -BeExactly 'ACTION_REQUIRED'
        Get-TpmHealthCheckExitCode -Result $result | Should -Be 2
    }

    It 'S6: the unattended branch exits with the health exit code, not a fixed 0' {
        # Mutation: put back "exit 0" in the unattended Health Check branch -> an incomplete check still exits success.
        $branches = @($script:Fix98Ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.IfStatementAst] -and $node.Clauses[0].Item1.Extent.Text -ceq '$Unattended' -and
                $node.Extent.Text -match 'health check (complete|\{0\})'
        }, $true))
        $branches.Count | Should -Be 1
        $exits = @($branches[0].FindAll({ $args[0] -is [System.Management.Automation.Language.ExitStatementAst] }, $true))
        $exits.Count | Should -Be 1
        $exits[0].Pipeline.Extent.Text | Should -BeExactly '$healthExitCode'
    }

    It 'S7: no usable family reference is skipped by design and all-skipped is NO_OP' {
        # Mutation: treat a missing reference as ACTION_REQUIRED or omit it from skips -> no-op progress and counts disagree.
        Mock Invoke-ControlPropagationLegacy { @([pscustomobject]@{ Code = 'ZGame'; Status = 'skipped-no-reference'; ReasonCode = 'NO_USABLE_FAMILY_REFERENCE'; Family = 'lightgun' }, [pscustomobject]@{ Code = 'AGame'; Status = 'skipped-unchanged' }) }
        Mock ConvertTo-TpmLegacyTransactionResult {
            [pscustomobject]@{ Outcome = $Outcome; ReasonCode = $ReasonCode; SkippedItems = @($SkippedItems) }
        }
        $tx = Invoke-ControlPropagation -userProfilesDir 'unused' -pool @{} -minBound 1 -DryRun $false
        $tx.Outcome | Should -BeExactly 'NO_OP'
        $tx.ReasonCode | Should -BeExactly 'NO_CHANGES_NEEDED'
        $tx.SkippedItems | Should -Contain 'ZGame'
        Get-TpmProgressCloseState -Result $tx | Should -BeExactly 'No-op'
        $summary = Get-TpmControlPropagationSummary -Reports @($tx.Reports) -Outcome ([string]$tx.Outcome)
        $summary.Title | Should -BeExactly 'No game was changed.'
        $summary.Status | Should -BeExactly 'Ok'
        $summary.Counts.SkippedCount | Should -Be 2
        @($summary.Needs).Count | Should -Be 0
        $summary.NotChanged | Should -Match '1 game skipped: no game of their family has your controls yet'
        $detail = @($summary.Blocks | Where-Object Heading -eq 'ZGame')
        $detail.Count | Should -Be 1
        ($detail.Lines -join ' ') | Should -Match "lightgun.*Add one game of this family with your own controls, then run this again\."
        ($detail.Lines -join ' ') | Should -Match 'NO_USABLE_FAMILY_REFERENCE'
        $summary.NotChanged | Should -Not -Match 'NO_USABLE_FAMILY_REFERENCE'
    }

    It 'S7: the next step names one game to set up for each control type that has no example game' {
        # Mutation: drop the named games -> the user has to guess which game to open in TeknoParrotUI (issue #342).
        $reports = @(
            [pscustomobject]@{ Code = 'ZGame'; Status = 'skipped-no-reference'; Family = 'lightgun' },
            [pscustomobject]@{ Code = 'AGame'; Status = 'skipped-no-reference'; Family = 'lightgun' },
            [pscustomobject]@{ Code = 'MGame'; Status = 'skipped-no-reference'; Family = 'driving' }
        )
        $summary = Get-TpmControlPropagationSummary -Reports $reports -Outcome 'NO_OP'
        $summary.Next | Should -Match 'for example driving: MGame; lightgun: AGame\)'
        (($summary.Blocks | Where-Object Heading -eq 'Games to set up first').Lines -join ' ') | Should -Match 'does not set up a game'
    }

    It 'S7: the unattended log explains each design skip and agrees with the screen' {
        # Mutation: log only ACTION_REQUIRED or hide skipped-game details in unattended mode -> the reason and next step disappear.
        $reports = @([pscustomobject]@{ Code = 'ZGame'; Status = 'skipped-no-reference'; ReasonCode = 'NO_USABLE_FAMILY_REFERENCE'; Family = 'lightgun' })
        [void](Write-ControlPropagationResults -Reports $reports -Outcome 'NO_OP' -Unattended)
        ($script:Fix98Host -join "`n") | Should -Match 'No game was changed\.'
        ($script:Fix98Host -join "`n") | Should -Match '1 game skipped: no game of their family has your controls yet'
        ($script:Fix98Log -join "`n") | Should -Match "ZGame: Skipped by design:.*'lightgun'.*Add one game of this family with your own controls, then run this again\."
        ($script:Fix98Log -join "`n") | Should -Match '1 game skipped: no game of their family has your controls yet'
        ($script:Fix98Log -join "`n") | Should -Not -Match 'NO_ARCHETYPE_MATCH|needs attention, it is not a failed save'
    }

    It 'S7: a real save failure stays FAILED, with or without a missing example game' -ForEach @(
        @{ Case = 'only a failed save'; Reports = @(@{ Code = 'AGame'; Status = 'save-failed' }) }
        @{ Case = 'a failed save and a missing example game'; Reports = @(@{ Code = 'AGame'; Status = 'save-failed' }, @{ Code = 'ZGame'; Status = 'skipped-no-reference'; Family = 'lightgun' }) }
    ) {
        # Mutation: map every ACTION_REQUIRED/FAILED_BEFORE_MUTATION control result to Incomplete -> a game that could not be saved no longer shows FAILED.
        $script:Fix98Reports = @($Reports | ForEach-Object { [pscustomobject]$_ })
        Mock Invoke-ControlPropagationLegacy { $script:Fix98Reports }
        Mock ConvertTo-TpmLegacyTransactionResult {
            [pscustomobject]@{ Outcome = $Outcome; ReasonCode = $ReasonCode }
        }
        $tx = Invoke-ControlPropagation -userProfilesDir 'unused' -pool @{} -minBound 1 -DryRun $false
        $tx.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $tx.ReasonCode | Should -BeExactly 'PROFILE_SAVE_FAILED'
        Get-TpmProgressCloseState -Result $tx | Should -BeExactly 'Error'
    }

    It 'S7: other action-required results are not relabeled as attention' {
        # Mutation: return Incomplete for every ACTION_REQUIRED outcome -> an unverified deployment stops showing FAILED.
        Get-TpmProgressCloseState -Result ([pscustomobject]@{ Outcome = 'ACTION_REQUIRED'; ReasonCode = 'DEPLOYMENT_UNVERIFIED' }) | Should -BeExactly 'Error'
        Get-TpmProgressCloseState -Result ([pscustomobject]@{ Outcome = 'FAILED_BEFORE_MUTATION'; ReasonCode = 'PROFILE_BACKUP_FAILED' }) | Should -BeExactly 'Error'
        Get-TpmProgressCloseState -Result ([pscustomobject]@{ Outcome = 'ACTION_REQUIRED'; ReasonCode = 'BACKUP_RETAINED_NO_PROFILE_CHANGE' }) | Should -BeExactly 'Incomplete'
    }

    It 'FIX107 S4: saved controls and a family design skip succeed and close done with an honest skipped count' {
        # Mutation: let a design skip force PARTIAL_APPLIED/Attention -> the otherwise successful run is not done/green.
        $script:Fix98Reports = @([pscustomobject]@{ Code = 'AGame'; Status = 'bound' }, [pscustomobject]@{ Code = 'ZGame'; Status = 'skipped-no-reference'; ReasonCode = 'NO_USABLE_FAMILY_REFERENCE'; Family = 'lightgun' })
        Mock Invoke-ControlPropagationLegacy { $script:Fix98Reports }
        Mock ConvertTo-TpmLegacyTransactionResult {
            [pscustomobject]@{ Outcome = $Outcome; ReasonCode = $ReasonCode; SkippedItems = @($SkippedItems) }
        }
        $tx = Invoke-ControlPropagation -userProfilesDir 'unused' -pool @{} -minBound 1 -DryRun $false
        $tx.Outcome | Should -BeExactly 'SUCCEEDED'
        $tx.ReasonCode | Should -BeExactly 'CONTROLS_PROCESSED'
        Get-TpmProgressCloseState -Result $tx | Should -BeExactly 'Final'
        $tx.SkippedItems | Should -Contain 'ZGame'
        $summary = Get-TpmControlPropagationSummary -Reports @($tx.Reports) -Outcome ([string]$tx.Outcome)
        $summary.Title | Should -Match 'updated'
        $summary.Status | Should -BeExactly 'Ok'
        $summary.Counts.SkippedCount | Should -Be 1
        @($summary.Needs).Count | Should -Be 0
        $summary.NotChanged | Should -Match '1 game skipped: no game of their family has your controls yet'
        [void](Write-ControlPropagationResults -Reports $tx.Reports -Outcome $tx.Outcome -Unattended)
        ($script:Fix98Log -join "`n") | Should -Match "ZGame: Skipped by design:.*lightgun.*Add one game"
    }

    It 'FIX107 S4: a real save failure next to saved controls stays FAILED: <Case>' -ForEach @(
        @{ Case = 'saved and failed'; Reports = @(@{ Code = 'AGame'; Status = 'bound' }, @{ Code = 'BGame'; Status = 'save-failed' }) }
        @{ Case = 'saved, failed and a missing example game'; Reports = @(@{ Code = 'AGame'; Status = 'bound' }, @{ Code = 'BGame'; Status = 'save-failed' }, @{ Code = 'ZGame'; Status = 'skipped-no-reference'; Family = 'lightgun' }) }
    ) {
        # Mutation: map every PARTIAL_APPLIED control result to Incomplete (or let the missing example game win the reason code) -> a profile that could not be saved no longer shows FAILED.
        $script:Fix98Reports = @($Reports | ForEach-Object { [pscustomobject]$_ })
        Mock Invoke-ControlPropagationLegacy { $script:Fix98Reports }
        Mock ConvertTo-TpmLegacyTransactionResult {
            [pscustomobject]@{ Outcome = $Outcome; ReasonCode = $ReasonCode }
        }
        $tx = Invoke-ControlPropagation -userProfilesDir 'unused' -pool @{} -minBound 1 -DryRun $false
        $tx.Outcome | Should -BeExactly 'PARTIAL_APPLIED'
        $tx.ReasonCode | Should -BeExactly 'PROFILE_SAVE_FAILED'
        Get-TpmProgressCloseState -Result $tx | Should -BeExactly 'Error'
    }

    It 'FIX107 S4: other partial results are not relabeled as incomplete' {
        # Mutation: return Incomplete for every PARTIAL_APPLIED outcome -> a partly finished registration or repair stops showing its own state.
        Get-TpmProgressCloseState -Result ([pscustomobject]@{ Outcome = 'PARTIAL_APPLIED'; ReasonCode = 'REGISTRATION_INCOMPLETE' }) | Should -BeExactly 'Error'
        Get-TpmProgressCloseState -Result ([pscustomobject]@{ Outcome = 'PARTIAL_APPLIED'; ReasonCode = 'PROFILE_SAVE_FAILED' }) | Should -BeExactly 'Error'
    }

    It 'a registration that only skipped games closes as attention, not as a failure' {
        foreach ($code in @('REGISTRATION_UNMATCHED_ONLY', 'REGISTRATION_NEEDS_CHOICES')) {
            Get-TpmProgressCloseState -Result ([pscustomobject]@{ Outcome = 'ACTION_REQUIRED'; ReasonCode = $code }) | Should -BeExactly 'Incomplete'
        }
    }
}

Describe 'FIX98 S9 registration screens keep their details for the final return prompt' {
    BeforeAll {
        $definitions = @{}
        foreach ($node in $script:Fix98Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
            if (-not $definitions.ContainsKey($node.Name)) { $definitions[$node.Name] = @() }
            $definitions[$node.Name] += $node
        }
        $external = @('Write-Log', 'Write-Host', 'Read-Host', 'Read-HostSafe', 'Test-TpmInteractiveInput', 'Show-TpmDetailBlocks', 'Get-ConsoleContentWidth')
        $selected = @{}
        $pending = New-Object 'System.Collections.Generic.Queue[string]'
        foreach ($root in @('Write-TpmOutcome', 'Read-TpmReturnToMenu', 'Add-TpmDeferredDetails', 'Clear-TpmDeferredDetails')) { $pending.Enqueue($root) }
        while ($pending.Count) {
            $name = $pending.Dequeue()
            if ($selected.ContainsKey($name) -or $external -contains $name) { continue }
            if (-not $definitions.ContainsKey($name)) { throw "Missing production helper: $name" }
            if (@($definitions[$name]).Count -ne 1) { throw "Ambiguous production helper: $name" }
            $node = $definitions[$name][0]; $selected[$name] = $node
            foreach ($command in $node.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                $called = $command.GetCommandName()
                if ($called -and $definitions.ContainsKey($called) -and $external -notcontains $called) { $pending.Enqueue($called) }
            }
        }
        $functionPath = Join-Path $TestDrive 'fix98-s9-functions.ps1'
        [System.IO.File]::WriteAllText($functionPath, (($selected.Values | Sort-Object { $_.Extent.StartOffset } | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"), (New-Object System.Text.UTF8Encoding $false))
        . $functionPath
        function Write-Log { param([string]$Message) }
        function Show-TpmDetailBlocks { param([object[]]$Blocks = @(), [string]$Note = '', [string]$HeadingColor = 'Cyan') }
        function Get-ConsoleContentWidth { return 120 }
        function Read-HostSafe { param([string]$Prompt) throw ("UNEXPECTED QUESTION '{0}'" -f $Prompt) }
        function Test-TpmInteractiveInput { param([switch]$Unattended) return $false }
    }
    BeforeEach {
        Clear-TpmDeferredDetails
        $script:Fix98Interactive = $true
        $script:Fix98Prompts = New-Object 'System.Collections.Generic.List[string]'
        $script:Fix98Answers = New-Object 'System.Collections.Generic.Queue[string]'
        $script:Fix98Shown = New-Object 'System.Collections.Generic.List[object]'
        Mock Write-Host {}
        Mock Test-TpmInteractiveInput { if ($Unattended) { return $false }; return [bool]$script:Fix98Interactive }
        # The product asks every question through Read-HostSafe (FIX110 S-11 moved the return prompt there), so that is what is recorded.
        Mock Read-HostSafe {
            [void]$script:Fix98Prompts.Add([string]$Prompt)
            if ($script:Fix98Answers.Count -eq 0) { return '' }
            return $script:Fix98Answers.Dequeue()
        }
        Mock Show-TpmDetailBlocks { [void]$script:Fix98Shown.Add([pscustomobject]@{ Blocks = @($Blocks); Note = $Note }) }
        $script:Fix98Blocks = @(@{ Heading = 'Game A'; Lines = @('Database: GameDB1', 'What happened: saved') })
    }

    It 'asks no question at the screen, then offers D once at the final prompt and shows the blocks' {
        # Mutation: ask "[D] Details, or press Enter to continue" at the screen again (drop -DeferDetails handling) -> UNEXPECTED QUESTION on every stage.
        # Mutation: Read-TpmReturnToMenu ignores D -> the blocks are never shown.
        Write-TpmOutcome -Title 'Registered.' -DetailBlocks $script:Fix98Blocks -Unattended:$false -DeferDetails
        Should -Invoke Read-HostSafe -Times 0 -Exactly
        $script:Fix98Answers.Enqueue('D')
        Read-TpmReturnToMenu
        @($script:Fix98Prompts) | Should -Be @('  [D] Details, or press Enter to return to menu', '  Press Enter to return to menu')
        $script:Fix98Shown.Count | Should -Be 1
        $script:Fix98Shown[0].Blocks[0].Heading | Should -BeExactly 'Game A'
    }

    It 'keeps collapsed lists reachable: more than three done items still end up in the details' {
        # Mutation: defer only the caller's DetailBlocks and not the collapsed "Everything that was done" block -> the items hidden by "... and 2 more" are lost.
        Write-TpmOutcome -Title 'Registered.' -Done @('One', 'Two', 'Three', 'Four', 'Five') -DetailBlocks $script:Fix98Blocks -Unattended:$false -DeferDetails
        $script:Fix98Answers.Enqueue('d')
        Read-TpmReturnToMenu
        $headings = @($script:Fix98Shown[0].Blocks | ForEach-Object { $_.Heading })
        $headings | Should -Contain 'Everything that was done'
        $headings | Should -Contain 'Game A'
    }

    It 'shows the screens in order, each with its own note' {
        # Mutation: keep only the last screen's blocks -> the first Show call is missing.
        Write-TpmOutcome -Title 'Controls.' -DetailBlocks $script:Fix98Blocks -DetailsNote 'Note one.' -Unattended:$false -DeferDetails
        Write-TpmOutcome -Title '' -Next 'Open TeknoParrotUI.' -DetailBlocks @(@{ Heading = 'Next steps'; Lines = @('Help: text') }) -DetailsNote 'Note two.' -Unattended:$false -DeferDetails
        $script:Fix98Answers.Enqueue('D')
        Read-TpmReturnToMenu
        $script:Fix98Shown.Count | Should -Be 2
        $script:Fix98Shown[0].Note | Should -BeExactly 'Note one.'
        $script:Fix98Shown[1].Note | Should -BeExactly 'Note two.'
    }

    It 'Enter skips the details and clears them, so a later run does not show old blocks' {
        # Mutation: do not clear the kept blocks at the final prompt -> the next run offers the previous run's details.
        Write-TpmOutcome -Title 'Registered.' -DetailBlocks $script:Fix98Blocks -Unattended:$false -DeferDetails
        Read-TpmReturnToMenu
        $script:Fix98Shown.Count | Should -Be 0
        $script:Fix98Prompts.Clear()
        Read-TpmReturnToMenu
        @($script:Fix98Prompts) | Should -Be @('  Press Enter to return to menu')
    }

    It 'keeps the old single sentence when no screen kept details' {
        # Mutation: always print the Details prompt -> a run without details asks "[D] Details" for nothing.
        Read-TpmReturnToMenu
        @($script:Fix98Prompts) | Should -Be @('  Press Enter to return to menu')
        $script:Fix98Shown.Count | Should -Be 0
    }

    It 'keeps today behavior for an unattended run: nothing is kept and nothing is asked' {
        # Mutation: defer the blocks even when the run is unattended -> a Details prompt appears in a run that must never ask.
        $script:Fix98Interactive = $false
        Write-TpmOutcome -Title 'Registered.' -DetailBlocks $script:Fix98Blocks -Unattended:$true -DeferDetails
        Write-TpmOutcome -Title 'Registered.' -DetailBlocks $script:Fix98Blocks -Unattended:$false -DeferDetails
        Read-TpmReturnToMenu
        @($script:Fix98Prompts) | Should -Be @('  Press Enter to return to menu')
    }

    It 'still asks at the screen when -DeferDetails is not used (other menus keep their Details question)' {
        # Mutation: defer for every Write-TpmOutcome call -> the Details question disappears from the other result screens.
        Mock Read-HostSafe { [void]$script:Fix98Prompts.Add([string]$Prompt); return '' }
        Write-TpmOutcome -Title 'Done.' -DetailBlocks $script:Fix98Blocks -Unattended:$false
        @($script:Fix98Prompts) | Should -Be @('  [D] Details, or press Enter to continue')
    }

    It 'the registration run clears kept details when it starts and ends with the return prompt that offers them' {
        # Mutation: leave out Clear-TpmDeferredDetails at the start of the registration flow or the Read-TpmReturnToMenu call at its end.
        function Get-Fix98TopLevelCalls {
            param([string]$Name)
            return @($script:Fix98Ast.FindAll({
                param($node)
                if ($node -isnot [System.Management.Automation.Language.CommandAst] -or $node.GetCommandName() -cne $Name) { return $false }
                for ($parent = $node.Parent; $null -ne $parent; $parent = $parent.Parent) {
                    if ($parent -is [System.Management.Automation.Language.FunctionDefinitionAst]) { return $false }
                }
                return $true
            }, $true))
        }
        $clear = @(Get-Fix98TopLevelCalls -Name 'Clear-TpmDeferredDetails')
        $return = @(Get-Fix98TopLevelCalls -Name 'Read-TpmReturnToMenu')
        $clear.Count | Should -Be 1
        $return.Count | Should -Be 1
        $clear[0].Extent.StartOffset | Should -BeLessThan $return[0].Extent.StartOffset
    }
}
