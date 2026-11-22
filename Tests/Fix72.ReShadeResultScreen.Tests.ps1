#Requires -Module Pester
# FIX72: the result screen of ReShade setup (menu 5). The owner chose Fast CRT for 62 games; 61 already had ReShade files, so one game changed. The screen
# then showed a red FAILED progress row although nothing failed, a status line "Needs attention", a table with "0 game(s)" rows, the bare word "TPM",
# and never said in plain words why 61 games were left alone or what to do. These tests drive the real product functions with fake consoles and
# fake files; nothing touches TeknoParrot, LaunchBox, the registry, services or the network. Each It names the product change that makes it fail.
# What this CANNOT prove: how a real console paints the rows, and the menu 5 body itself (it is not a function; its decisions are made by
# Get-TpmReShadeResultSummaryText, Set-TpmReShadeSetupWorkflowEnd and Show-TpmReShadeSetupResult, which these tests call).

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $script:fix72Ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX72 bootstrap could not parse the production script.' }
    $script:fix72Source = [System.IO.File]::ReadAllText($scriptPath)
    $functionFile = Join-Path $TestDrive 'fix72-functions.ps1'
    ($script:fix72Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:DisplayVersion = 'v1.0 RC8'
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'fix72.log'
    $script:logWarnShown = $false

    # The result object of Invoke-ReShadeSetup in the owner's case: one game changed, many protected (not installed by TeknoParrot Manager).
    function New-Fix72Result {
        param(
            [int]$Deployed = 1, [int]$Protected = 61, [int]$Unsafe = 0, [int]$MissingPath = 0, [int]$MissingDevice = 0, [int]$ErrorCount = 0,
            [string]$Name = 'Fast CRT', [object[]]$Records = $null, [string[]]$Unverified = @(), [string[]]$UnsafeDetails = @()
        )
        if ($null -eq $Records) {
            # An empty list must stay an empty array: a $null here would reach the screen as one record without a code.
            $Records = @()
            if ($Protected -gt 0) {
                $Records = @(1..$Protected | ForEach-Object { [pscustomobject]@{ Game = ('Game{0:D2}' -f $_); Label = ('Game {0:D2}' -f $_); Code = 'RESHADE_NOT_OWNED'; Detail = 'A ReShade hook exists without verified TeknoParrot Manager ownership.' } })
            }
        }
        return [pscustomobject]@{
            Deployed = $Deployed; Protected = $Protected; Unsafe = $Unsafe; MissingPath = $MissingPath; MissingDevice = $MissingDevice
            Unsupported = 0; KeptPrevious = 0; ErrorCount = $ErrorCount; UnverifiedItems = $Unverified
            SelectedProfileName = $Name; ProtectedRecords = $Records; ProtectedDetails = @(); UnsafeDetails = $UnsafeDetails
            SummaryDetails = @('Installed new: 1 game'); DetailNotes = @('Game00  [dxgi.dll]  (preset: generated)'); SelectedProfileTechniques = 'CRT-ZFast'
        }
    }

    # Everything printed, as one string with white space collapsed (a sentence that wrapped over several rows reads as one sentence).
    function Get-Fix72Text {
        param($Rows)
        return ((@($Rows | ForEach-Object { ([string]$_.Text).Trim() }) -join ' ') -replace '\s+', ' ')
    }

    function Find-Fix72Row {
        param([string[]]$Rows, [string]$Prefix)
        for ($i = 0; $i -lt $Rows.Count; $i++) { if ($Rows[$i].StartsWith($Prefix)) { return $i } }
        return -1
    }

    # The most logical lines in a row with no blank row between them. A row that only continues the sentence above it (its first word did not
    # fit, so it was wrapped) belongs to that line. Slack covers the hanging indent of the first row of a paragraph. This can only count too few
    # lines (never too many), so a failure is always a real run of lines. Limit is the characters per row (width - 1).
    function Get-Fix72LongestRun {
        param([string[]]$Rows, [int]$Limit, [int]$Slack = 9)
        $longest = 0
        $run = 0
        $previous = ''
        foreach ($row in @($Rows)) {
            if ([string]::IsNullOrWhiteSpace($row)) { $run = 0; $previous = ''; continue }
            $firstWord = ($row.Trim() -split '\s+')[0]
            $continues = ($previous.Length -gt 0 -and ($previous.Length + 1 + $firstWord.Length) -gt ($Limit - $Slack))
            if (-not $continues) { $run++; if ($run -gt $longest) { $longest = $run } }
            $previous = [string]$row
        }
        return $longest
    }

    # What Get-TpmReShadeDllCheck returns for the 64-bit DLL.
    function New-Fix72Checks {
        param([string]$Status = 'UnknownError')
        return @([pscustomobject]@{ Label = '64-bit'; Present = $true; Version = '6.8.0'; Status = $Status; Signer = '(none)'; Thumbprint = ('C3' * 20); Sha256 = ('1A' * 32) })
    }
}

Describe 'FIX72 progress row and workflow: games that were only left alone are not a failure' {
    BeforeAll {
        # Stand-ins for the progress module: they record how the group bar was closed.
        function Import-TpmProgressModule { }
        function Test-TpmProgressGroupOwned { return $false }
        function Test-TpmProgressActive { return $false }
        function Stop-TpmProgressAbandoned { }
        function Start-TpmProgressOperation { param([string]$Title, [switch]$Group) }
        function Complete-TpmProgressOperation { param([string]$State = 'Final', [string]$Message = '') $script:fix72CloseState = $State }
        function New-Fix72Legacy {
            param([int]$Errors = 0, [string[]]$Unverified = @())
            return [pscustomobject]@{
                Succeeded = $false; Deployed = 1; Errors = $Errors; Skipped = 0; Protected = $(if ($Errors -gt 0) { 1 } else { 2 })
                SelectedItems = @('Game0', 'Game1', 'Game2'); ChangedItems = @('Game0')
                SkippedItems = $(if ($Errors -gt 0) { @('Game1') } else { @('Game1', 'Game2') }); FailedItems = $(if ($Errors -gt 0) { @('Game2') } else { @() })
                UnverifiedItems = $Unverified; Accounting = [pscustomobject]@{ Complete = $true }
            }
        }
    }
    BeforeEach {
        $script:fix72CloseState = ''
        Mock Write-Log {}
        Mock Exit-TpmReShadeInteractiveProgressHold {}
    }

    It 'maps a result that left games alone with no error to a finished row, and every real failure to a failed row' {
        # Mutation: delete the SOME_GAMES_NOT_CHANGED line in Get-TpmProgressCloseState -> the owner's red FAILED row comes back for a result with no error.
        # Mutation: make that line return Final for every PARTIAL_APPLIED outcome -> a real error would show a finished row.
        (Get-TpmProgressCloseState -Result ([pscustomobject]@{ Outcome = 'PARTIAL_APPLIED'; ReasonCode = 'SOME_GAMES_NOT_CHANGED' })) | Should -BeExactly 'Final'
        (Get-TpmProgressCloseState -Result ([pscustomobject]@{ Outcome = 'FAILED_BEFORE_MUTATION'; ReasonCode = 'SOME_GAMES_NOT_CHANGED' })) | Should -BeExactly 'Final'
        (Get-TpmProgressCloseState -Result ([pscustomobject]@{ Outcome = 'PARTIAL_APPLIED'; ReasonCode = 'PROFILES_PARTIALLY_APPLIED' })) | Should -BeExactly 'Error'
        (Get-TpmProgressCloseState -Result ([pscustomobject]@{ Outcome = 'ACTION_REQUIRED'; ReasonCode = 'DEPLOYMENT_UNVERIFIED' })) | Should -BeExactly 'Error'
    }

    It 'gives the code only when no game failed and nothing is unverified, and the progress group closes accordingly' {
        # Mutation: drop "$errorCount -eq 0" from the SOME_GAMES_NOT_CHANGED condition in Invoke-ReShadeSetup -> a result with an error is closed as finished.
        # Mutation: drop "$unverified.Count -eq 0" -> a deployment that could not be verified is closed as finished.
        Mock Invoke-ReShadeSetupLegacy { New-Fix72Legacy }
        $left = Invoke-ReShadeSetup -UserProfilesDir $TestDrive
        $left.ReasonCode | Should -BeExactly 'SOME_GAMES_NOT_CHANGED'
        $left.Outcome | Should -BeExactly 'PARTIAL_APPLIED'
        $left.ErrorCount | Should -Be 0
        $null = Invoke-TpmProgressGroup -Title 'ReShade setup' -Action { $left }
        $script:fix72CloseState | Should -BeExactly 'Final'

        Mock Invoke-ReShadeSetupLegacy { New-Fix72Legacy -Errors 1 }
        $failed = Invoke-ReShadeSetup -UserProfilesDir $TestDrive
        $failed.ReasonCode | Should -BeExactly 'PROFILES_PARTIALLY_APPLIED'
        $null = Invoke-TpmProgressGroup -Title 'ReShade setup' -Action { $failed }
        $script:fix72CloseState | Should -BeExactly 'Error'

        Mock Invoke-ReShadeSetupLegacy { New-Fix72Legacy -Unverified @('Game0') }
        $unverified = Invoke-ReShadeSetup -UserProfilesDir $TestDrive
        $unverified.ReasonCode | Should -BeExactly 'DEPLOYMENT_UNVERIFIED'
        $null = Invoke-TpmProgressGroup -Title 'ReShade setup' -Action { $unverified }
        $script:fix72CloseState | Should -BeExactly 'Error'
    }
}

Describe 'FIX72 workflow status: Set-TpmReShadeSetupWorkflowEnd' {
    BeforeEach {
        Mock Write-Log {}
        Mock Render-TpmWorkflowStatus {}
        $script:ActiveTpmWorkflowStatus = $null
        $script:fix72Context = New-TpmWorkflowStatusContext -WorkflowKey 'ReShadeSetup' -Title 'ReShade setup' -Steps @(
            @{ Id = 'inspect'; Label = 'Check the ReShade source' }
            @{ Id = 'acquire'; Label = 'Download and verify the official installer' }
            @{ Id = 'apply'; Label = 'Install the selected visual enhancement' }
            @{ Id = 'verify'; Label = 'Verify the result' }
        )
        [void](Start-TpmWorkflowStatus -Context $script:fix72Context)
        [void](Start-TpmWorkflowStep -Context $script:fix72Context -StepId 'inspect' -Activity 'Checking ReShade files')
    }
    AfterEach { $script:ActiveTpmWorkflowStatus = $null }

    It 'finishes the workflow without raising a failure when games were only left alone' {
        # Mutation: call Set-TpmWorkflowFailure for every incomplete result again (the owner's "Needs attention: ReShade applied partially" status line).
        $result = [pscustomobject]@{ ReasonCode = 'SOME_GAMES_NOT_CHANGED'; ErrorCount = 0; UnverifiedItems = @(); Deployed = 1 }
        $nothingFailed = Set-TpmReShadeSetupWorkflowEnd -Context $script:fix72Context -Result $result -Summary 'ReShade applied partially: 1 game changed, 0 errors, 0 unavailable-device skips.'
        $nothingFailed | Should -BeTrue
        $script:fix72Context.Failure | Should -BeNullOrEmpty
        $script:fix72Context.Lifecycle | Should -BeExactly 'Finished'
        { Close-TpmWorkflowStatus -Context $script:fix72Context } | Should -Not -Throw
    }

    It 'raises the failure, in plain words, when a game failed or a deployment is unverified' -ForEach @(
        @{ Case = 'an error'; Result = [pscustomobject]@{ ReasonCode = 'PROFILES_PARTIALLY_APPLIED'; ErrorCount = 1; UnverifiedItems = @(); Deployed = 1 } }
        @{ Case = 'an unverified game'; Result = [pscustomobject]@{ ReasonCode = 'DEPLOYMENT_UNVERIFIED'; ErrorCount = 0; UnverifiedItems = @('Game0'); Deployed = 1 } }
        @{ Case = 'a missing result'; Result = $null }
    ) {
        # Mutation: return $true whenever Deployed -gt 0 -> a real error or an unverified game is finished normally.
        $nothingFailed = Set-TpmReShadeSetupWorkflowEnd -Context $script:fix72Context -Result $Result -Summary 'The summary.'
        $nothingFailed | Should -BeFalse -Because $Case
        $script:fix72Context.Failure.FailureId | Should -BeExactly 'reshade-incomplete'
        $script:fix72Context.Failure.DataSafety | Should -BeExactly 'TeknoParrot Manager did not claim success for every selected game; skipped and failed games were left unchanged.'
        $script:fix72Context.Failure.DataSafety | Should -Not -Match '\bTPM\b'
    }
}

Describe 'FIX72 result screen: a short plain summary, a plain choice, every fact under Details' {
    BeforeEach {
        $script:fix72Rows = [System.Collections.Generic.List[object]]::new()
        $script:fix72Log = New-Object System.Collections.Generic.List[string]
        $script:fix72Prompts = New-Object System.Collections.Generic.List[string]
        $script:fix72Answers = New-Object 'System.Collections.Generic.Queue[string]'
        $script:fix72Width = 120
        Mock Write-Host { [void]$script:fix72Rows.Add([pscustomobject]@{ Text = [string]$Object; Color = $(if ($PesterBoundParameters.ContainsKey('ForegroundColor')) { [string]$ForegroundColor } else { '' }) }) }
        Mock Write-Log { [void]$script:fix72Log.Add([string]$msg) }
        Mock Get-ConsoleContentWidth { return [int]$script:fix72Width }
        Mock Read-HostSafe {
            [void]$script:fix72Prompts.Add([string]$Prompt)
            if ($script:fix72Prompts.Count -gt 40) { throw 'runaway prompt loop in the test' }
            if ($script:fix72Answers.Count -gt 0) { return $script:fix72Answers.Dequeue() }
            return $Default
        }
    }

    It 'says what was done, what was left alone and why, and what to do, for 1 game changed and 61 protected' {
        # Mutation: restore the old Result table, the "What next" line or the Data safety line on the default screen (the wall of text the owner saw).
        # Mutation: print "game(s)" or a "0 games" row again.
        $screen = Show-TpmReShadeSetupResult -Result (New-Fix72Result)
        $rows = @($script:fix72Rows)
        $texts = @($rows | ForEach-Object { [string]$_.Text })
        $plain = Get-Fix72Text -Rows $rows
        $plain | Should -Match ([regex]::Escape('Done: Fast CRT applied to 1 game.'))
        $plain | Should -Match ([regex]::Escape('Not changed: 61 games already have a ReShade that TeknoParrot Manager did not install. They were left alone to protect your own setup.'))
        # Mutation: say "and apply <look>" again -> the line promises something A does not do (A re-opens the setup and the look is chosen again).
        $plain | Should -Match ([regex]::Escape("[A] Replace those 61 games with TeknoParrot Manager's ReShade (you choose the look again; a copy of the old files is saved, so you can undo it)"))
        $plain | Should -Not -Match 'and apply Fast CRT'
        $plain | Should -Match ([regex]::Escape('[S] Choose games one by one'))
        $plain | Should -Match ([regex]::Escape('[B] Leave them as they are'))
        $plain | Should -Match ([regex]::Escape('[D] Details'))
        $plain | Should -Not -Match 'FAILED|game\(s\)|Result:|What next|Data safety|Adopt/replace|Protected existing|applied partially|Needs attention|\bTPM\b'
        $plain | Should -Not -Match '(?<!\d)0 games?\b'
        $texts[0] | Should -BeExactly ''
        (Find-Fix72Row -Rows $texts -Prefix '  Done: Fast CRT applied to 1 game.') | Should -Be 1
        $notChangedAt = Find-Fix72Row -Rows $texts -Prefix '  Not changed:'
        $texts[$notChangedAt - 1] | Should -BeExactly '' -Because 'a blank row separates the sections'
        $choiceAt = Find-Fix72Row -Rows $texts -Prefix '  [A] Replace those 61 games'
        $choiceAt | Should -BeGreaterThan $notChangedAt
        $texts[$choiceAt - 1] | Should -BeExactly ''
        @($rows | Where-Object { $_.Text -like '  Done:*' })[0].Color | Should -BeExactly 'Green'
        @($rows | Where-Object { $_.Text -like '  Not changed:*' })[0].Color | Should -BeExactly 'Yellow'
        $screen.Choice | Should -BeExactly 'B'
        $screen.PendingApplyMode | Should -BeNullOrEmpty
        $script:fix72Prompts.Count | Should -Be 1
        $script:fix72Prompts[0] | Should -BeExactly '  Press A, S, B or D'
    }

    It 'keeps every row inside the console and its sections short at <Width> columns' -ForEach @(
        @{ Width = 40 }
        @{ Width = 60 }
        @{ Width = 120 }
    ) {
        # Mutation: print the choice lines or the Not changed block without a blank row before them, or without wrapping -> a row wider than the console or a run of more than 5 lines.
        $script:fix72Width = $Width
        $null = Show-TpmReShadeSetupResult -Result (New-Fix72Result)
        $texts = @($script:fix72Rows | ForEach-Object { [string]$_.Text })
        foreach ($text in $texts) { $text.Length | Should -BeLessOrEqual ($Width - 1) -Because "a row at $Width columns: '$text'" }
        (Get-Fix72Text -Rows $script:fix72Rows) | Should -Match ([regex]::Escape('Not changed: 61 games already have a ReShade that TeknoParrot Manager did not install. They were left alone to protect your own setup.'))
        (Get-Fix72LongestRun -Rows $texts -Limit ($Width - 1)) | Should -BeLessOrEqual 5 -Because "wrapped rows count once at $Width columns"
        $notChangedAt = Find-Fix72Row -Rows $texts -Prefix '  Not changed:'
        $texts[$notChangedAt - 1] | Should -BeExactly ''
        $choiceAt = Find-Fix72Row -Rows $texts -Prefix '  [A] Replace'
        $texts[$choiceAt - 1] | Should -BeExactly ''
    }

    It 'prints only non-zero counts with the right singular and plural' -ForEach @(
        @{ Case = 'two changed, none left'; Params = @{ Deployed = 2; Protected = 0 }; Expect = 'Done: Fast CRT applied to 2 games.'; Absent = 'Not changed' }
        @{ Case = 'one protected'; Params = @{ Deployed = 1; Protected = 1 }; Expect = 'Not changed: 1 game already has a ReShade that TeknoParrot Manager did not install. It was left alone to protect your own setup.'; Absent = 'Nothing was changed in' }
        @{ Case = 'two cannot be found'; Params = @{ Deployed = 0; Protected = 0; MissingPath = 1; MissingDevice = 1 }; Expect = 'Not changed: 2 games could not be found. The game file is missing or its drive is not connected. Nothing was changed in them.'; Absent = 'Done:' }
        @{ Case = 'one unsafe'; Params = @{ Deployed = 3; Protected = 0; Unsafe = 1 }; Expect = 'Not changed: 1 game could not be checked safely. Nothing was changed in it.'; Absent = 'already have' }
    ) {
        # Mutation: format every count as "{0} game(s)" or always append "s" -> "1 games" or "game(s)".
        # Mutation: print the zero-count rows again (Missing paths, Failed, Unsafe/malformed) -> a "0 games" row.
        $paramSet = $Params
        $null = Show-TpmReShadeSetupResult -Result (New-Fix72Result @paramSet)
        $plain = Get-Fix72Text -Rows $script:fix72Rows
        $plain | Should -Match ([regex]::Escape($Expect)) -Because $Case
        $plain | Should -Not -Match $Absent -Because $Case
        $plain | Should -Not -Match 'game\(s\)'
        $plain | Should -Not -Match '(?<!\d)0 games?\b'
    }

    It 'groups games with the same reason on one line and words an earlier TeknoParrot Manager install by its real reason' {
        # Mutation: print one row per game -> far more than 3 bullet rows.
        # Mutation: say "did not install" for the earlier-version group (ignore RESHADE_EARLIER_VERSION) -> the message blames a ReShade TeknoParrot Manager did install.
        $records = @(
            [pscustomobject]@{ Game = 'A1'; Label = 'Game A1'; Code = 'RESHADE_NOT_OWNED'; Detail = 'd' }
            [pscustomobject]@{ Game = 'A2'; Label = 'Game A2'; Code = 'RESHADE_NOT_OWNED'; Detail = 'd' }
            [pscustomobject]@{ Game = 'B1'; Label = 'Game B1'; Code = 'RESHADE_EARLIER_VERSION'; Detail = 'd' }
            [pscustomobject]@{ Game = 'C1'; Label = 'Game C1'; Code = 'RESHADE_PREINSTALLED'; Detail = 'd' }
        )
        $null = Show-TpmReShadeSetupResult -Result (New-Fix72Result -Deployed 1 -Protected 4 -Records $records)
        $texts = @($script:fix72Rows | ForEach-Object { [string]$_.Text })
        $bullets = @($texts | Where-Object { $_ -like '    - *' })
        $bullets.Count | Should -Be 3
        $bullets[0] | Should -BeExactly '    - 2 games already have a ReShade that TeknoParrot Manager did not install.'
        $bullets[1] | Should -BeExactly '    - 1 game has ReShade files from an earlier version of TeknoParrot Manager.'
        $bullets[2] | Should -BeExactly '    - 1 game came with ReShade files of its own.'
        $bullets[1] | Should -Not -Match 'did not install'
        (Get-Fix72Text -Rows $script:fix72Rows) | Should -Match ([regex]::Escape('They were left alone to protect your own setup.'))
        $texts.Count | Should -BeLessThan 25
    }

    It 'does not say a game that was missing or on an unplugged drive was left alone to protect your own setup' {
        $null = Show-TpmReShadeSetupResult -Result (New-Fix72Result -Deployed 1 -Protected 2 -MissingDevice 1)
        $plain = Get-Fix72Text -Rows $script:fix72Rows
        $plain | Should -Match ([regex]::Escape('1 game could not be found. The game file is missing or its drive is not connected.'))
        $plain | Should -Not -Match 'left alone to protect'
    }

    It 'shows every fact under Details in one short block per game, once, and asks the choice again' {
        # Mutation: drop the reason code, the technical detail, the old table, the data-safety line or the per-game notes from the Details blocks.
        # Mutation: repeat the common "Press A to replace" note for each game -> it appears more than once.
        $script:fix72Answers.Enqueue('D')
        $script:fix72Answers.Enqueue('B')
        $result = New-Fix72Result -Deployed 1 -Protected 3 -Unsafe 1 -UnsafeDetails @('GameU: ReShade target could not be resolved safely.')
        $null = Show-TpmReShadeSetupResult -Result $result
        $script:fix72Prompts.Count | Should -Be 2
        $script:fix72Prompts[1] | Should -BeExactly '  Press A, S, B or D'
        $texts = @($script:fix72Rows | ForEach-Object { [string]$_.Text })
        $detailsFrom = Find-Fix72Row -Rows $texts -Prefix '  Press A to replace protected ReShade files.'
        $detailsFrom | Should -BeGreaterThan 0 -Because 'the Details start with the common note'
        $details = Get-Fix72Text -Rows @($script:fix72Rows | Select-Object -Skip $detailsFrom)
        foreach ($fact in @(
            'Summary: ReShade applied partially: 1 game changed, 0 errors, 0 unavailable-device skips.',
            'Changed: 1 game', 'Protected existing: 3 games', 'Missing paths: 0 games', 'Failed: 0 games', 'Unsafe/malformed: 1 game',
            'Changed: verified ReShade deployments only.',
            'Not changed: protected, unsafe/malformed, unknown, or unavailable game folders.',
            'Data safety: TeknoParrot Manager did not claim success for every selected game; skipped and failed games were left unchanged.',
            'What to do next: review the games listed here, repair the listed issue, then run ReShade setup again.',
            'Game 01', 'Game 02', 'Game 03',
            'What happened: This game already has a ReShade that TeknoParrot Manager did not install.',
            'Reason code: RESHADE_NOT_OWNED',
            'Technical detail: A ReShade hook exists without verified TeknoParrot Manager ownership.',
            'GameU', 'What happened: ReShade target could not be resolved safely.',
            'Selected profile techniques: CRT-ZFast',
            'Installed new: 1 game',
            'Game00 [dxgi.dll] (preset: generated)'
        )) { $details | Should -Match ([regex]::Escape($fact)) -Because $fact }
        ([regex]::Matches($details, [regex]::Escape('Press A to replace protected ReShade files.'))).Count | Should -Be 1
        $texts = @($script:fix72Rows | ForEach-Object { [string]$_.Text })
        foreach ($heading in @('  Game 01', '  Game 02', '  Game 03', '  GameU')) {
            $at = [Array]::IndexOf($texts, $heading)
            $at | Should -BeGreaterThan 0 -Because $heading
            $texts[$at - 1] | Should -BeExactly '' -Because "$heading starts a new block"
        }
        # the same facts are in the log, shown or not
        $log = $script:fix72Log -join "`n"
        $log | Should -Match ([regex]::Escape('ReShade result detail [Game 02]: Reason code: RESHADE_NOT_OWNED'))
        $log | Should -Match ([regex]::Escape('ReShade result detail [What TeknoParrot Manager did]: Not changed: protected, unsafe/malformed, unknown, or unavailable game folders.'))
    }

    It 'keeps the Details rows inside the console at <Width> columns' -ForEach @(
        @{ Width = 40 }
        @{ Width = 60 }
        @{ Width = 120 }
    ) {
        # Mutation: write the detail lines without wrapping (plain Write-Host) -> a row wider than the console.
        $script:fix72Width = $Width
        $script:fix72Answers.Enqueue('D')
        $script:fix72Answers.Enqueue('B')
        $null = Show-TpmReShadeSetupResult -Result (New-Fix72Result -Deployed 1 -Protected 3)
        foreach ($text in @($script:fix72Rows | ForEach-Object { [string]$_.Text })) { $text.Length | Should -BeLessOrEqual ($Width - 1) -Because "a row at $Width columns: '$text'" }
    }

    It 'keeps the keys: A starts the replacement with one press (the screen already says a copy is saved), S chooses by game, B leaves everything' -ForEach @(
        @{ Case = 'A'; Answers = @('A'); Choice = 'A'; Mode = 'ReShadeSetup'; Action = 'Adopt' }
        @{ Case = 'S'; Answers = @('S'); Choice = 'S'; Mode = 'ReShadeSetup'; Action = 'Select' }
        @{ Case = 'B'; Answers = @('B'); Choice = 'B'; Mode = $null; Action = $null }
        @{ Case = 'Enter (the default)'; Answers = @(); Choice = 'B'; Mode = $null; Action = $null }
    ) {
        # Mutation: ask a second Y/N question after A again, or return Adopt for S, B or Enter.
        foreach ($answer in $Answers) { $script:fix72Answers.Enqueue($answer) }
        $screen = Show-TpmReShadeSetupResult -Result (New-Fix72Result -Deployed 1 -Protected 2)
        $screen.Choice | Should -BeExactly $Choice -Because $Case
        if ($null -eq $Mode) { $screen.PendingApplyMode | Should -BeNullOrEmpty -Because $Case } else { $screen.PendingApplyMode | Should -BeExactly $Mode -Because $Case }
        if ($null -eq $Action) { $screen.PendingReShadeAction | Should -BeNullOrEmpty -Because $Case } else { $screen.PendingReShadeAction | Should -BeExactly $Action -Because $Case }
        @($script:fix72Prompts | Where-Object { $_ -like '*(Y/N)*' }).Count | Should -Be 0
        if ($Case -eq 'A') { (Get-Fix72Text -Rows $script:fix72Rows) | Should -Match 'a copy of the old files is saved, so you can undo it' }
    }

    It 'offers M only when a game could not be found, and routes M to the health check' {
        # Mutation: always offer M (or never) -> the keys no longer follow the old action model.
        $script:fix72Answers.Enqueue('M')
        $screen = Show-TpmReShadeSetupResult -Result (New-Fix72Result -Deployed 1 -Protected 2 -MissingPath 1)
        $screen.PendingApplyMode | Should -BeExactly 'HealthCheck'
        $screen.PendingReShadeAction | Should -BeExactly 'Select'
        $script:fix72Prompts[0] | Should -BeExactly '  Press A, S, M, B or D'
        (Get-Fix72Text -Rows $script:fix72Rows) | Should -Match ([regex]::Escape('[M] Open the Library Health Check to see which games could not be found'))
        $script:fix72Rows.Clear()
        $script:fix72Prompts.Clear()
        $null = Show-TpmReShadeSetupResult -Result (New-Fix72Result -Deployed 1 -Protected 2)
        $script:fix72Prompts[0] | Should -BeExactly '  Press A, S, B or D'
    }

    It 'shows a clean success with the Home-key hint, no choice menu and only the Details question' {
        # Mutation: show the A/S/B menu for a result with nothing left alone -> the clean path asks a question that does not apply.
        $screen = Show-TpmReShadeSetupResult -Result (New-Fix72Result -Deployed 3 -Protected 0)
        $plain = Get-Fix72Text -Rows $script:fix72Rows
        $plain | Should -Match ([regex]::Escape('Done: Fast CRT applied to 3 games.'))
        $plain | Should -Match ([regex]::Escape('To turn the effect on or off, start a game and press the Home key.'))
        $plain | Should -Not -Match ([regex]::Escape('[A]'))
        $plain | Should -Not -Match 'Not changed'
        $script:fix72Prompts.Count | Should -Be 1
        $script:fix72Prompts[0] | Should -BeExactly '  Press D for details, or Enter to return to the menu'
        $screen.PendingApplyMode | Should -BeNullOrEmpty
    }

    It 'still shows a real failure in red and names it' {
        # Mutation: drop the Problem lines -> an error or an unverified game is silent on the default screen.
        $null = Show-TpmReShadeSetupResult -Result (New-Fix72Result -Deployed 0 -Protected 0 -ErrorCount 2 -Unverified @('Game9'))
        $rows = @($script:fix72Rows)
        $plain = Get-Fix72Text -Rows $rows
        $plain | Should -Match ([regex]::Escape('Nothing was changed.'))
        $plain | Should -Match ([regex]::Escape('Problem: 2 games could not be changed. See the FAILED lines above, or the log.'))
        $plain | Should -Match ([regex]::Escape('Problem: TeknoParrot Manager could not confirm the files in 1 game. Check the log before you try again.'))
        @($rows | Where-Object { $_.Text -like '  Problem:*' }).Count | Should -BeGreaterOrEqual 2
        foreach ($problem in @($rows | Where-Object { $_.Text -like '  Problem:*' })) { $problem.Color | Should -BeExactly 'Red' }
    }

    It 'does not fail when there is no result at all' {
        # Mutation: remove [AllowNull()] from the Result parameter of Show-TpmReShadeSetupResult -> the screen throws instead of saying nothing changed.
        { $null = Show-TpmReShadeSetupResult -Result $null } | Should -Not -Throw
        (Get-Fix72Text -Rows $script:fix72Rows) | Should -Match ([regex]::Escape('Nothing was changed.'))
        $script:fix72Prompts[0] | Should -BeExactly '  Press D for details, or Enter to return to the menu'
    }
}

Describe 'FIX72 how a protected game is classified and worded' {
    BeforeEach {
        Mock Test-TpmNoReparsePath { $true }
        $script:fix72Folder = Join-Path $TestDrive ('marker-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $script:fix72Folder -Force)
    }

    It 'recognizes the header TeknoParrot Manager writes into ReShade.ini, and nothing else' -ForEach @(
        @{ Case = 'the managed-profile header'; Text = "; TPM-managed approved ReShade profile: FastCrt`r`n; Generated by TeknoParrot Manager. Do not edit.`r`nPresetName=Fast CRT`r`n"; Expected = $true }
        @{ Case = 'the generated-by header alone'; Text = "; Generated by TeknoParrot Manager. Do not edit.`r`n"; Expected = $true }
        @{ Case = 'a plain user ReShade.ini'; Text = "[GENERAL]`r`nPresetPath=.\my.ini`r`n"; Expected = $false }
        @{ Case = 'a header only after 20 lines'; Text = ((1..25 | ForEach-Object { "Key$_=1" }) -join "`r`n") + "`r`n; Generated by TeknoParrot Manager. Do not edit.`r`n"; Expected = $false }
    ) {
        # Mutation: match any ReShade.ini, or search the whole file -> a user's own file is called ours.
        [System.IO.File]::WriteAllText((Join-Path $script:fix72Folder 'ReShade.ini'), $Text)
        (Test-TpmReShadeOwnMarker -TargetDir $script:fix72Folder) | Should -Be $Expected -Because $Case
    }

    It 'finds no marker when there is no ReShade.ini, no folder, or the folder is a link' {
        # Mutation: return $true when the file is missing -> every unowned DLL is called ours.
        (Test-TpmReShadeOwnMarker -TargetDir $script:fix72Folder) | Should -BeFalse
        (Test-TpmReShadeOwnMarker -TargetDir '') | Should -BeFalse
        [System.IO.File]::WriteAllText((Join-Path $script:fix72Folder 'ReShade.ini'), "; Generated by TeknoParrot Manager. Do not edit.`r`n")
        Mock Test-TpmNoReparsePath { $false }
        (Test-TpmReShadeOwnMarker -TargetDir $script:fix72Folder) | Should -BeFalse
    }

    It 'words the reason by the ownership record, not by one fixed sentence' {
        # Mutation: return RESHADE_NOT_OWNED for every status -> an earlier version's files and bundled files are blamed on the user.
        [System.IO.File]::WriteAllText((Join-Path $script:fix72Folder 'ReShade.ini'), "; TPM-managed approved ReShade profile: FastCrt`r`n")
        (Get-TpmReShadeProtectedReasonCode -Status 'UnknownUserOwnedConflict' -TargetDir $script:fix72Folder) | Should -BeExactly 'RESHADE_EARLIER_VERSION'
        (Get-TpmReShadeProtectedReasonCode -Status 'UnknownUserOwnedConflict' -TargetDir (Join-Path $TestDrive 'nowhere')) | Should -BeExactly 'RESHADE_NOT_OWNED'
        (Get-TpmReShadeProtectedReasonCode -Status 'BundledPreinstalledProtected' -TargetDir $script:fix72Folder) | Should -BeExactly 'RESHADE_PREINSTALLED'
        (Get-TpmReShadeProtectedReasonCode -FileCollision) | Should -BeExactly 'RESHADE_FILE_NOT_OWNED'
        (Get-TpmReShadeProtectedReasonCode -Status 'Something else') | Should -BeExactly 'RESHADE_OWNER_UNKNOWN'
    }

    It 'has a plain sentence for every protected reason and the group sentences read right for 1 and for 2' {
        # Mutation: drop a RESHADE_* entry from Get-TpmPlainReasonTable -> the Details show the generic "could not be completed" sentence.
        foreach ($code in @('RESHADE_NOT_OWNED', 'RESHADE_EARLIER_VERSION', 'RESHADE_PREINSTALLED', 'RESHADE_FILE_NOT_OWNED', 'RESHADE_OWNER_UNKNOWN', 'SOME_GAMES_NOT_CHANGED', 'GAME_PATH_MISSING', 'DEVICE_UNAVAILABLE')) {
            (Get-TpmPlainReason -Code $code).Known | Should -BeTrue -Because $code
        }
        (Get-TpmReShadeProtectedGroupText -Code 'RESHADE_NOT_OWNED' -Count 1) | Should -BeExactly '1 game already has a ReShade that TeknoParrot Manager did not install.'
        (Get-TpmReShadeProtectedGroupText -Code 'RESHADE_NOT_OWNED' -Count 61) | Should -BeExactly '61 games already have a ReShade that TeknoParrot Manager did not install.'
        (Get-TpmReShadeProtectedGroupText -Code 'RESHADE_EARLIER_VERSION' -Count 1) | Should -BeExactly '1 game has ReShade files from an earlier version of TeknoParrot Manager.'
        (Get-TpmReShadeProtectedGroupText -Code 'RESHADE_PREINSTALLED' -Count 2) | Should -BeExactly '2 games came with ReShade files of their own.'
        (Get-TpmReShadeProtectedGroupText -Code 'RESHADE_FILE_NOT_OWNED' -Count 1) | Should -BeExactly '1 game has a file in its folder that TeknoParrot Manager did not install.'
        (Get-TpmReShadeProtectedGroupText -Code 'RESHADE_OWNER_UNKNOWN' -Count 3) | Should -BeExactly 'TeknoParrot Manager could not tell who installed the ReShade files in 3 games.'
    }

    It 'counts "game" and "games" correctly' {
        # Mutation: always append "s" -> "1 games".
        (Format-TpmGameCount -Count 0) | Should -BeExactly '0 games'
        (Format-TpmGameCount -Count 1) | Should -BeExactly '1 game'
        (Format-TpmGameCount -Count 2) | Should -BeExactly '2 games'
    }
}

Describe 'FIX72 the real setup records the reason a game is protected' {
    BeforeEach {
        $script:fix72Root = Join-Path $TestDrive ('setup-' + [guid]::NewGuid().ToString('N'))
        $script:fix72Profiles = Join-Path $script:fix72Root 'UserProfiles'
        $script:fix72GameDir = Join-Path $script:fix72Root 'Game'
        [void](New-Item -ItemType Directory -Path $script:fix72Profiles, $script:fix72GameDir -Force)
        $script:fix72GameExe = Join-Path $script:fix72GameDir 'Game.exe'
        [IO.File]::WriteAllText($script:fix72GameExe, 'game')
        [IO.File]::WriteAllText((Join-Path $script:fix72GameDir 'dxgi.dll'), 'a ReShade hook')
        $script:fix72ProfileFile = Join-Path $script:fix72Profiles 'Game.xml'
        [IO.File]::WriteAllText($script:fix72ProfileFile, ('<GameProfile><GamePath>{0}</GamePath></GameProfile>' -f $script:fix72GameExe))
        $script:fix72Dll = Join-Path $script:fix72Root 'ReShade64.dll'
        [IO.File]::WriteAllText($script:fix72Dll, 'fixture-64')
        $script:TpmOwnedLayout = [pscustomobject]@{ Assets = (Join-Path $script:fix72Root 'Assets') }
        $script:fix72Status = 'UnknownUserOwnedConflict'
        $script:fix72Rows = [System.Collections.Generic.List[object]]::new()
        Mock Write-Host { [void]$script:fix72Rows.Add([pscustomobject]@{ Text = [string]$Object }) }
        Mock Write-Log {}
        Mock Get-ConsoleContentWidth { return 120 }
        Mock Get-TpmConsoleMetrics { [pscustomobject]@{ Width = 120; Left = 0; Top = 0; Height = 40; BufferWidth = 120; BufferHeight = 300 } }
        Mock Test-TpmNoReparsePath { $true }
        Mock Test-ReShadeDllSignature { [pscustomobject]@{ Status = 'UnknownError'; Signer = '(none)'; Thumbprint = ('C3' * 20) } }
        Mock Invoke-ReShadeUpdateIfAvailable { param($SourceDll, $InstalledVersion) [pscustomobject]@{ Updated = $false; SourceDll = $SourceDll } }
        Mock Read-TpmReShadeState { [pscustomobject]@{ Favorites = @() } }
        Mock Get-TpmReShadeHdrGate { [pscustomobject]@{ State = 'HIDDEN'; Visible = $false; Enabled = $false; Reason = 'test'; Fingerprint = '' } }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Show-TpmReShadeProfileGalleryWindow { [pscustomobject]@{ Available = $false; Reason = 'fixture' } }
        Mock Close-TpmReShadeProfileGallerySession {}
        Mock Read-TpmReShadeTerminalProfile { [pscustomobject]@{ Cancelled = $false; SelectedProfile = (Get-TpmReShadeProfile -ProfileId 'Original'); PreviewSession = $null } }
        Mock Read-TpmChoice { 'Y' }
        Mock Select-RegisteredGamesInteractive { @(Get-Item -LiteralPath $script:fix72ProfileFile) }
        Mock Get-TpmReShadeChooserOptions { [pscustomobject]@{ Restore = [pscustomobject]@{ Found = $false; Valid = $false }; Remembered = [pscustomobject]@{ Found = $false; Valid = $false } } }
        Mock Get-TpmReShadeProfileOwnershipPath { Join-Path $script:fix72Root ($GameId + '.ownership.json') }
        Mock Get-ReShadeTargetInfo { [pscustomobject]@{ TargetDir = $script:fix72GameDir; DllName = 'dxgi.dll'; ApiDetected = $true } }
        Mock Get-ExeArchitecture { 'x64' }
        Mock Test-TpmGameMutationPath { [pscustomobject]@{ Valid = $true; ReasonCode = $null; Reason = 'valid'; ResolvedPath = $script:fix72GameExe; GameDirectory = $script:fix72GameDir } }
        Mock Get-TpmReShadeOwnershipClassification { [pscustomobject]@{ Status = $script:fix72Status; Detail = 'fixture detail' } }
        Mock Install-TpmReShadeProfileDeployment { throw 'a protected game must not be changed' }
    }
    AfterEach { $script:TpmOwnedLayout = $null }

    It 'records <Code> for <Case> and keeps the game unchanged' -ForEach @(
        @{ Case = 'a DLL with no ownership record and no marker'; Status = 'UnknownUserOwnedConflict'; Marker = $false; Code = 'RESHADE_NOT_OWNED' }
        @{ Case = 'a DLL with no record whose ReShade.ini carries the TeknoParrot Manager header'; Status = 'UnknownUserOwnedConflict'; Marker = $true; Code = 'RESHADE_EARLIER_VERSION' }
        @{ Case = 'files the record marks as bundled or preinstalled'; Status = 'BundledPreinstalledProtected'; Marker = $false; Code = 'RESHADE_PREINSTALLED' }
    ) {
        # Mutation: stop passing the classification status or the target folder to Get-TpmReShadeProtectedReasonCode -> every case records RESHADE_NOT_OWNED.
        $script:fix72Status = $Status
        if ($Marker) { [IO.File]::WriteAllText((Join-Path $script:fix72GameDir 'ReShade.ini'), "; TPM-managed approved ReShade profile: FastCrt`r`n") }
        $result = Invoke-ReShadeSetupLegacy -UserProfilesDir $script:fix72Profiles -SourceDll $script:fix72Dll
        $result.Protected | Should -Be 1
        $result.Deployed | Should -Be 0
        @($result.ProtectedRecords).Count | Should -Be 1
        $result.ProtectedRecords[0].Code | Should -BeExactly $Code -Because $Case
        $result.ProtectedRecords[0].Game | Should -BeExactly 'Game'
        $result.SelectedProfileName | Should -BeExactly 'Original'
        Should -Invoke Install-TpmReShadeProfileDeployment -Times 0 -Exactly
        $screen = (@($script:fix72Rows | ForEach-Object { $_.Text }) -join "`n")
        $screen | Should -Not -Match 'game\(s\)|unsafe/malformed, unchanged|\bTPM\b' -Because 'the per-game lines moved to Details and the log'
        @($script:fix72Rows | Where-Object { $_.Text -like '*-- unchanged*' }).Count | Should -Be 0
    }

    It 'records RESHADE_FILE_NOT_OWNED when an installed file would replace one the record does not own' {
        # Mutation: record the collision as RESHADE_NOT_OWNED, or leave it out of ProtectedRecords -> the screen counts a protected game it cannot explain.
        $script:fix72Status = 'ManagedByTeknoParrotManager'
        Mock Install-TpmReShadeProfileDeployment { [pscustomobject]@{ Succeeded = $false; State = 'COLLISION'; Reason = 'USER_OWNED_CONTENT_PRESERVED'; Error = 'Existing file not managed by TeknoParrot Manager was preserved: dxgi.dll' } }
        $result = Invoke-ReShadeSetupLegacy -UserProfilesDir $script:fix72Profiles -SourceDll $script:fix72Dll
        $result.Protected | Should -Be 1
        $result.ProtectedRecords[0].Code | Should -BeExactly 'RESHADE_FILE_NOT_OWNED'
        $result.ProtectedRecords[0].Detail | Should -BeExactly 'Existing file not managed by TeknoParrot Manager was preserved: dxgi.dll'
        $result.ProtectedDetails | Should -Contain 'Game: protected existing ReShade files'
    }
}

Describe 'FIX72 the DLL notice names the right file and the real signature status' {
    It 'keeps an unusual signature status on the default line and does not call it common' -ForEach @(
        @{ Status = 'HashMismatch'; Expected = '  ReShade 6.8.0 is ready to use. Windows found a problem with the DLL signature (HashMismatch).' }
        @{ Status = 'NotTrusted'; Expected = '  ReShade 6.8.0 is ready to use. Windows found a problem with the DLL signature (NotTrusted).' }
        @{ Status = 'NotSigned'; Expected = '  ReShade 6.8.0 is ready to use. Windows could not confirm who published the DLL, which is common for ReShade.' }
    ) {
        # Mutation: show the "common for ReShade" sentence for every status that is not Valid -> a changed file (HashMismatch) is called normal.
        $lines = @(Get-TpmReShadeDllNoticeLines -Checks (New-Fix72Checks -Status $Status) -TextWidth 0)
        $lines[0].Text | Should -BeExactly $Expected
        $lines[0].Color | Should -BeExactly 'Yellow'
        $lines[1].Text | Should -BeExactly '  Choose [D] below for the signature status, SHA-256 and thumbprint.'
    }
}

Describe 'FIX72 no bare TPM in the words of the ReShade flow' {
    It 'has no TPM in a visible string of the ReShade flow functions or the menu 5 body, and the three named strings are fixed' {
        # Mutation: put "TPM" back into any visible string of these functions (the old Data safety text, the Details of the ownership classification, the dgVoodoo2 skip reasons).
        $functionNames = @(
            'Show-TpmReShadeSetupResult', 'Set-TpmReShadeSetupWorkflowEnd', 'Get-TpmReShadeResultSummaryText', 'Get-TpmReShadeProtectedGroupText',
            'Get-TpmReShadeProtectedReasonCode', 'Get-TpmReShadeOwnershipClassification', 'Invoke-ReShadeSetup', 'Invoke-ReShadeSetupLegacy',
            'Get-TpmReShadeApplyPreflight', 'Get-TpmReShadeDllNoticeLines', 'Get-TpmReShadeDllDetailLines', 'Get-TpmReShadeChooserIntroLines',
            'Get-TpmReShadeTerminalMenuLines', 'Read-TpmReShadeTerminalProfile', 'Invoke-DgVoodoo2Setup'
        )
        $scopes = New-Object System.Collections.Generic.List[object]
        foreach ($name in $functionNames) {
            $found = @($script:fix72Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true))
            $found.Count | Should -Be 1 -Because $name
            [void]$scopes.Add([pscustomobject]@{ Name = $name; Node = $found[0] })
        }
        $menu5 = @($script:fix72Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.IfStatementAst] -and $node.Clauses[0].Item1.Extent.Text -eq '$mode -eq "ReShadeSetup"' }, $true))
        $menu5.Count | Should -Be 1
        [void]$scopes.Add([pscustomobject]@{ Name = 'menu 5 body'; Node = $menu5[0] })
        $offenders = New-Object System.Collections.Generic.List[string]
        foreach ($scope in $scopes) {
            $strings = $scope.Node.FindAll({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $node -is [System.Management.Automation.Language.ExpandableStringExpressionAst] }, $true)
            foreach ($stringNode in $strings) {
                $inLog = $false
                $parent = $stringNode.Parent
                while ($null -ne $parent) {
                    if ($parent -is [System.Management.Automation.Language.CommandAst] -and $parent.GetCommandName() -in @('Write-Log', 'Write-Verbose')) { $inLog = $true; break }
                    $parent = $parent.Parent
                }
                if ($inLog) { continue }
                $value = [string]$stringNode.Value
                if ($value -eq 'TPM-ReShade-') { continue }   # the name of a temporary file, never shown
                if ($value -cmatch '\bTPM\b') { [void]$offenders.Add(('{0}: {1}' -f $scope.Name, $value)) }
            }
        }
        ($offenders -join "`n") | Should -BeExactly ''
        $script:fix72Source | Should -Not -Match ([regex]::Escape('TPM did not claim success for every selected game'))
        $script:fix72Source | Should -Not -Match ([regex]::Escape('TPM has a saved location for this game'))
        $script:fix72Source | Should -Not -Match ([regex]::Escape('TPM could not find the saved game executable'))
    }
}
