#Requires -Module Pester

# FIX82: screen readability wave 2 - the result screens of BepInEx (menu 9), GPU fix (menu 7), Force feedback (menu 8), dgVoodoo2 (menu 6)
# and Crosshair (menu 4). The owner's rule: SHORT plain words, one idea per line, never 6 or more text lines in a row, singular and plural
# right, no bare "TPM", technical facts hidden by default but ALWAYS available under Details (key D) and in the log.
#
# The production script is parsed and only its function definitions are dot-sourced. Every file lives under TestDrive. Nothing touches
# TeknoParrot, LaunchBox, the registry, services or the network. Each It names the product change that makes it fail.
# What these tests CANNOT prove: how a real console paints the rows, and the menu bodies themselves (they are not functions; their
# decisions are made by the Get-Tpm...View / Show-Tpm... functions that these tests call).

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $script:fix82Ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX82 bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'fix82-functions.ps1'
    ($script:fix82Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'fix82.log'
    $script:logWarnShown = $false

    # A fake console: every Write-Host row, every log line and every question is recorded; the width and the answers are set by the test.
    function Install-Fix82Console {
        param([int]$Width = 120, [string[]]$Answers = @(), [bool]$Interactive = $false)
        $script:fix82Rows = New-Object System.Collections.Generic.List[object]
        $script:fix82Log = New-Object System.Collections.Generic.List[string]
        $script:fix82Prompts = New-Object System.Collections.Generic.List[string]
        $script:fix82Answers = New-Object 'System.Collections.Generic.Queue[string]'
        $script:fix82Width = $Width
        $script:fix82Interactive = $Interactive
        foreach ($answer in $Answers) { [void]$script:fix82Answers.Enqueue($answer) }
        Mock Write-Host { [void]$script:fix82Rows.Add([pscustomobject]@{ Text = [string]($Object -join ' '); Color = $(if ($PesterBoundParameters.ContainsKey('ForegroundColor')) { [string]$ForegroundColor } else { '' }) }) }
        Mock Write-Log { [void]$script:fix82Log.Add([string]$msg) }
        Mock Get-ConsoleContentWidth { return [int]$script:fix82Width }
        Mock Test-TpmInteractiveInput { return [bool]$script:fix82Interactive }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Read-HostSafe {
            [void]$script:fix82Prompts.Add([string]$Prompt)
            if ($script:fix82Prompts.Count -gt 20) { throw 'runaway prompt loop in the test' }
            if ($script:fix82Answers.Count -gt 0) { return $script:fix82Answers.Dequeue() }
            return ''
        }
    }

    # Everything printed, as one string with white space collapsed (a sentence that wrapped over several rows reads as one sentence).
    function Get-Fix82Text {
        param($Rows)
        return ((@($Rows | ForEach-Object { ([string]$_.Text).Trim() }) -join ' ') -replace '\s+', ' ')
    }

    # The most logical lines in a row with no blank row between them. A row that only continues the sentence above it (its first word did
    # not fit, so it was wrapped) belongs to that line. This can only count too few lines (never too many), so a failure is a real run.
    function Get-Fix82LongestRun {
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

    function Get-Fix82RowTexts { return @($script:fix82Rows | ForEach-Object { [string]$_.Text }) }

    # The index of the first row that starts with Prefix, or -1.
    function Find-Fix82Row {
        param([string[]]$Rows, [string]$Prefix)
        for ($i = 0; $i -lt $Rows.Count; $i++) { if ($Rows[$i].StartsWith($Prefix)) { return $i } }
        return -1
    }

    function New-Fix82BepRecord {
        param([string]$Game = 'Alpha', [string]$Label = 'Alpha Game', [string]$Operation = 'inspection', [string]$Code = 'UNKNOWN_ARCHITECTURE')
        return [pscustomobject]@{
            Game = $Game; GameLabel = $Label; GameRoot = ('D:\Games\' + $Game); StagingPath = $null; BackupPath = $null
            Operation = $Operation; ReasonKey = $Code; Exception = 'Could not read the executable header.'
            EvidencePreserved = $false; NextAction = 'Verify the game executable, then run setup again.'
        }
    }

    # What Invoke-BepInExUpdateCheck returns (the fields the screen reads).
    function New-Fix82BepResult {
        param(
            [hashtable]$Counts = @{ 'UNKNOWN_ARCHITECTURE' = 1 }, [int]$Updated = 0, [int]$Skipped = 1, [int]$Protected = 0, [int]$MissingDevice = 0,
            [int]$MissingPath = 0, [int]$UnknownArchitecture = 1, [int]$Errors = 0, [int]$Failed = 0, [int]$Unattempted = 0,
            [object[]]$Records = $null, [string[]]$Selected = @('Alpha')
        )
        if ($null -eq $Records) { $Records = @((New-Fix82BepRecord)) }
        return [pscustomobject]@{
            Updated = $Updated; Skipped = $Skipped; Protected = $Protected; MissingDevice = $MissingDevice; MissingPath = $MissingPath
            UnsupportedArchitecture = 0; UnknownArchitecture = $UnknownArchitecture; Errors = $Errors; ReasonCode = 'SKIPPED_GAMES_REQUIRE_REVIEW'
            PathReasonCounts = $Counts; FailureRecords = $Records; SelectedItems = $Selected
            Mutation = [pscustomobject]@{ FailedItemCount = $Failed; UnattemptedItemCount = $Unattempted }
        }
    }

    # What Invoke-GpuFixSetup returns (the fields the screen reads).
    function New-Fix82GpuResult {
        param(
            [string]$Outcome = 'SUCCEEDED', [string]$Vendor = 'Intel', [int]$Updated = 3, [int]$Unchanged = 0, [int]$NotApplicable = 0, [int]$Skipped = 0,
            [int]$Errors = 0, [int]$MissingPath = 0, [int]$MissingDevice = 0, [bool]$Cancelled = $false, [object[]]$SkipDetails = @(), [object[]]$FailureRecords = @(),
            [string[]]$Changed = @('GpuBoolOn', 'GpuDiscovered', 'GpuDropdown'), [int]$Failed = 0, [string]$BackupPath = 'D:\TP\UserProfiles\FullBackup\GpuFix_1', [string]$Reason = ''
        )
        return [pscustomobject]@{
            Outcome = $Outcome; Cancelled = $Cancelled; GpuVendor = $Vendor; GpuName = ($Vendor + ' Arc'); Updated = $Updated; Unchanged = $Unchanged
            NotApplicable = $NotApplicable; Skipped = $Skipped; Errors = $Errors; MissingPath = $MissingPath; MissingDevice = $MissingDevice
            SkipDetails = $SkipDetails; FailureRecords = $FailureRecords; Reason = $Reason
            Backup = [pscustomobject]@{ RootPath = $BackupPath }
            Mutation = [pscustomobject]@{ ChangedItems = $Changed; FailedItems = @(); UnknownItems = @(); SkippedItems = @(); UnattemptedItems = @(); FailedItemCount = $Failed; UnknownItemCount = 0; UnattemptedItemCount = 0 }
        }
    }

    function New-Fix82DgDetail {
        param([string]$Game = 'GameA', [string[]]$Apis = @('D3D8'))
        return [pscustomobject]@{ Game = $Game; LegacyApis = $Apis; Files = @('D3D8.dll', 'DDraw.dll'); Destination = ('D:\Games\' + $Game); Config = 'dgVoodoo.conf' }
    }

    function New-Fix82DgResult {
        param([object[]]$Installed = @((New-Fix82DgDetail -Game 'GameA'), (New-Fix82DgDetail -Game 'GameB' -Apis @())), [object[]]$Skipped = @(), [bool]$NoOp = $false, [int]$Overrides = 0, [int]$MissingPath = 0, [int]$MissingDevice = 0)
        return [pscustomobject]@{
            NoOp = $NoOp; Deployed = @($Installed).Count; MissingPath = $MissingPath; MissingDevice = $MissingDevice
            DeploymentDetails = $Installed; SkipDetails = $Skipped; PresetOverrides = $Overrides
        }
    }

    function New-Fix82CrosshairResult {
        param([string[]]$Games = @('GunA', 'GunB', 'GunC', 'GunD'), [bool]$NoOp = $false, [bool]$NoTargets = $false, [string[]]$Hidden = @(), [int]$Skipped = 0)
        return [pscustomobject]@{
            Outcome = 'SUCCEEDED'; Succeeded = $true; NoOp = $NoOp; NoTargets = $NoTargets; Deployed = @($Games).Count; Skipped = $Skipped
            DeployedGames = $Games; P1Name = 'cross-red'; P2Name = 'cross-blue'
            TargetFolders = @([pscustomobject]@{ Item = 'ElfLdr2'; Folder = 'D:\TeknoParrot\ElfLdr2' }, [pscustomobject]@{ Item = 'Pcsx2x6'; Folder = 'D:\TeknoParrot\pcsx2x6\crosshairs' })
            EmulatorNotes = @('PCSX2 folder: D:\TeknoParrot\pcsx2x6', 'PCSX2 settings: PCSX2.ini updated')
            CursorResult = [pscustomobject]@{ Outcome = 'SUCCEEDED'; Mutation = [pscustomobject]@{ CompletedItems = $Hidden } }
        }
    }

    # The profile of the backup-gate tests: a lightgun game with an FFB Blaster field and a HideCursor field, both set to $Value.
    function New-Fix82ProfileFixture {
        param([string]$Root, [string]$Code = 'GameA', [string]$Value = '0')
        $profiles = Join-Path $Root 'UserProfiles'
        $tp = Join-Path $Root 'TeknoParrot'
        New-Item -ItemType Directory -Path $profiles, (Join-Path $tp 'GameProfiles') -Force | Out-Null
        $xml = "<GameProfile><GameName>$Code</GameName><EmulationProfile>Daytona3</EmulationProfile><GunGame>true</GunGame><ConfigValues><FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Enable</FieldName><FieldType>Bool</FieldType><FieldValue>$Value</FieldValue></FieldInformation><FieldInformation><FieldName>HideCursor</FieldName><FieldType>Bool</FieldType><FieldValue>$Value</FieldValue></FieldInformation></ConfigValues></GameProfile>"
        Set-Content -LiteralPath (Join-Path $profiles ($Code + '.xml')) -Value $xml -Encoding utf8
        return [pscustomobject]@{ Profiles = $profiles; Tp = $tp; File = (Join-Path $profiles ($Code + '.xml')) }
    }

    function New-Fix82VerifiedBackup {
        return [pscustomobject]@{ Required = $true; Attempted = $true; Created = $true; Succeeded = $true; Verified = $true; Path = 'backup-evidence'; Manifest = @(); FailureStage = $null; Reason = $null; ResiduePaths = @() }
    }
}

Describe 'FIX82 BepInEx result: one line per kind of problem, no counters, no codes' {
    BeforeEach { Install-Fix82Console }

    It 'says in plain words what is wrong for a game whose 32/64-bit kind is unknown, and hides the path check line and the code' {
        # Mutation: print "Path preflight: ..." on the default screen again, or the UNKNOWN_ARCHITECTURE code, or the long "did not complete safely" counter sentence.
        # Mutation: print "game(s)" instead of the right singular.
        $null = Show-TpmBepInExFailureSummary -Result (New-Fix82BepResult)
        $texts = Get-Fix82RowTexts
        $plain = Get-Fix82Text -Rows $script:fix82Rows
        $plain | Should -Match ([regex]::Escape('Could not tell if this game is 32-bit or 64-bit (1 game).'))
        $plain | Should -Not -Match 'Path preflight|UNKNOWN_ARCHITECTURE|game\(s\)|skip\(s\)|did not complete safely|Updated cleanly|protected/reparse|\bTPM\b'
        $texts[0] | Should -BeExactly ''
        $texts[1] | Should -BeExactly '  BepInEx could not finish for every game.'
        $texts | Should -Contain '    - Could not tell if this game is 32-bit or 64-bit (1 game).'
        @($script:fix82Rows | Where-Object { $_.Text -eq '  BepInEx could not finish for every game.' })[0].Color | Should -BeExactly 'Yellow'
        $plain | Should -Match ([regex]::Escape('Next: Press D to see why, or R to try again.'))
        $script:fix82Prompts.Count | Should -Be 0 -Because 'the menu under the screen owns the D key; the screen asks nothing itself'
        @($texts | Where-Object { $_.Trim() }).Count | Should -BeLessOrEqual 6
    }

    It 'prints only the kinds that happened, each with its own count and the right singular or plural' {
        # Mutation: print the zero counts again (a "0 games" row) or always append "s" ("1 games").
        # Mutation: list the codes in the order they were found instead of sorted, or drop the saved-path advice when a path is missing.
        $counts = @{ 'UNKNOWN_ARCHITECTURE' = 3; 'DEVICE_UNAVAILABLE' = 1; 'GAME_PATH_MISSING' = 2 }
        $null = Show-TpmBepInExFailureSummary -Result (New-Fix82BepResult -Counts $counts -Skipped 6 -MissingDevice 1 -MissingPath 2 -UnknownArchitecture 3)
        $texts = Get-Fix82RowTexts
        $bullets = @($texts | Where-Object { $_ -like '    - *' })
        $bullets.Count | Should -Be 3
        $bullets[0] | Should -BeExactly '    - The drive for this game is not connected (1 game).'
        $bullets[1] | Should -BeExactly '    - The game files were not found (2 games).'
        $bullets[2] | Should -BeExactly '    - Could not tell if these games are 32-bit or 64-bit (3 games).'
        (Get-Fix82Text -Rows $script:fix82Rows) | Should -Match ([regex]::Escape('Next: Press H to fix the saved game paths, then press R to try again.'))
        (Get-Fix82Text -Rows $script:fix82Rows) | Should -Not -Match '(?<!\d)0 games?\b'
    }

    It 'says what was set up, and counts failed games, when some games were updated' {
        # Mutation: drop the "set up for N games" line, or leave a failed game out of the problem list.
        $result = New-Fix82BepResult -Counts @{} -Updated 2 -Skipped 0 -UnknownArchitecture 0 -Failed 1 -Errors 1 -Records @() -Selected @('A', 'B', 'C')
        $null = Show-TpmBepInExFailureSummary -Result $result
        $texts = Get-Fix82RowTexts
        $texts | Should -Contain '    - BepInEx was set up for 2 games.'
        $texts | Should -Contain '    - 1 game could not be updated.'
        @($script:fix82Rows | Where-Object { $_.Text -eq '  BepInEx could not finish for every game.' })[0].Color | Should -BeExactly 'Red'
        (Get-TpmBepInExFailureView -Result (New-Fix82BepResult -Counts @{} -Updated 1 -Skipped 0 -Failed 1 -Records @())).Done[0] | Should -BeExactly 'BepInEx was set up for 1 game.'
    }

    It 'tells the person not to try again when a failed update could not be undone, and shows it as a problem' {
        # Mutation: offer "R to try again" in that case, or show it as a yellow Attention line.
        $result = New-Fix82BepResult -Counts @{ 'ROLLBACK_FAILED' = 1 } -Skipped 0 -UnknownArchitecture 0 -Records @()
        $null = Show-TpmBepInExFailureSummary -Result $result
        $plain = Get-Fix82Text -Rows $script:fix82Rows
        $plain | Should -Match ([regex]::Escape('A failed update could not be undone safely (1 game).'))
        $plain | Should -Match ([regex]::Escape('Next: Do not try again yet. Press D for details, or O for help.'))
        $plain | Should -Not -Match 'to try again\.'
        @($script:fix82Rows | Where-Object { $_.Text -eq '  BepInEx could not finish for every game.' })[0].Color | Should -BeExactly 'Red'
    }

    It 'does not call the run a failure when every picked game worked and only other games were skipped' {
        # Mutation: keep the "could not finish" title, or the red Problem status, when nothing the person picked failed.
        $counts = @{ 'UNKNOWN_ARCHITECTURE' = 3; 'DEVICE_UNAVAILABLE' = 2 }
        $view = Get-TpmBepInExFailureView -Result (New-Fix82BepResult -Counts $counts -Updated 4 -Skipped 5 -MissingDevice 2 -UnknownArchitecture 3 -Failed 0 -Errors 0 -Records @())
        $view.Title | Should -BeExactly 'BepInEx is set up for 4 games you picked. Other games in your library were left alone.'
        $view.Status | Should -BeExactly 'Attention'
        $view.Needs.Count | Should -BeGreaterThan 0
        # A real failure keeps the old wording.
        (Get-TpmBepInExFailureView -Result (New-Fix82BepResult -Counts @{} -Updated 4 -Skipped 0 -Failed 1 -Records @())).Title | Should -BeExactly 'BepInEx could not finish for every game.'
    }

    It 'never claims success when there is no result at all' {
        # Mutation: treat a missing result as done (no Problem status), or print nothing.
        $view = Get-TpmBepInExFailureView -Result $null
        $view.Status | Should -BeExactly 'Problem'
        $view.Title | Should -BeExactly 'BepInEx did not give a result. Nothing is counted as done.'
        $view.Next | Should -BeExactly 'Press R to try again, or B to go back.'
        ($view.DetailBlocks[0].Lines -join ' ') | Should -Match ([regex]::Escape('Totals: BepInEx did not return a result. No success was claimed.'))
    }

    It 'keeps every row inside the console and no run longer than 5 lines at <Width> columns' -ForEach @(
        @{ Width = 40 }
        @{ Width = 60 }
        @{ Width = 120 }
    ) {
        # Mutation: print the problem lines or the Next line without wrapping, or without a blank row before Next -> a row wider than the console or a run of 6 or more lines.
        $script:fix82Width = $Width
        $counts = @{ 'UNKNOWN_ARCHITECTURE' = 3; 'DEVICE_UNAVAILABLE' = 1; 'GAME_PATH_MISSING' = 2 }
        $null = Show-TpmBepInExFailureSummary -Result (New-Fix82BepResult -Counts $counts -Skipped 6 -MissingDevice 1 -MissingPath 2 -UnknownArchitecture 3)
        $texts = Get-Fix82RowTexts
        foreach ($text in $texts) { $text.Length | Should -BeLessOrEqual ($Width - 1) -Because "a row at $Width columns: '$text'" }
        (Get-Fix82LongestRun -Rows $texts -Limit ($Width - 1)) | Should -BeLessOrEqual 5
        $nextAt = Find-Fix82Row -Rows $texts -Prefix '  Next:'
        $nextAt | Should -BeGreaterThan 0
        $texts[$nextAt - 1] | Should -BeExactly ''
    }
}

Describe 'FIX82 BepInEx Details: every fact the old screen showed is still reachable' {
    BeforeEach { Install-Fix82Console }

    It 'shows the path check line, the counters, the reason codes, the log file and one block per game, once' {
        # Mutation: drop the path check line, the totals sentence, a reason code, the log path or any field of the per-game block from the Details view.
        # Mutation: build the path check line from the wrong counts (eligible must be games checked minus games skipped before the update).
        $records = @(
            (New-Fix82BepRecord -Game 'Gamma' -Label 'Gamma Game' -Operation 'root safety preflight' -Code 'PROTECTED_OR_REPARSE_ROOT'),
            (New-Fix82BepRecord -Game 'Delta' -Label 'Delta Game' -Operation 'path preflight' -Code 'DEVICE_UNAVAILABLE'),
            (New-Fix82BepRecord -Game 'Alpha' -Label 'Alpha Game' -Operation 'inspection' -Code 'UNKNOWN_ARCHITECTURE')
        )
        $counts = @{ 'PROTECTED_OR_REPARSE_ROOT' = 1; 'DEVICE_UNAVAILABLE' = 1; 'UNKNOWN_ARCHITECTURE' = 1 }
        $result = New-Fix82BepResult -Counts $counts -Skipped 3 -Protected 1 -MissingDevice 1 -UnknownArchitecture 1 -Records $records -Selected @('Alpha', 'Beta', 'Gamma', 'Delta')
        $view = Get-TpmBepInExFailureView -Result $result -LogPath 'C:\Logs\TeknoParrot-Manager.log'
        Show-TpmDetailBlocks -Blocks $view.DetailBlocks -Note $view.DetailsNote
        $details = Get-Fix82Text -Rows $script:fix82Rows
        foreach ($fact in @(
            'TeknoParrot Manager does not count a failed or unchecked update as done.',
            'Path preflight: 2 eligible game(s), 1 unavailable-device skip(s), 0 missing-path skip(s), 1 protected/reparse skip(s), 0 other skip(s).',
            'Totals: BepInEx did not complete safely. Updated cleanly: 0; failed: 0; not attempted: 0; skipped: 3 (protected: 1, missing device: 1, missing path: 0, unsupported architecture: 0, unreadable or unknown architecture: 1, other: 0); errors: 0.',
            'Result code: SKIPPED_GAMES_REQUIRE_REVIEW',
            'Reason code: DEVICE_UNAVAILABLE (1 game)', 'Reason code: PROTECTED_OR_REPARSE_ROOT (1 game)', 'Reason code: UNKNOWN_ARCHITECTURE (1 game)',
            'Technical log: C:\Logs\TeknoParrot-Manager.log',
            'Alpha Game', 'Reason: UNKNOWN_ARCHITECTURE', 'What it means: Could not tell if this game is 32-bit or 64-bit.', 'Root: D:\Games\Alpha',
            'Operation: inspection', 'Exception: Could not read the executable header.', 'Evidence preserved: False', 'Next action: Verify the game executable, then run setup again.',
            'Gamma Game', 'Reason: PROTECTED_OR_REPARSE_ROOT', 'Delta Game', 'Reason: DEVICE_UNAVAILABLE'
        )) { $details | Should -Match ([regex]::Escape($fact)) -Because $fact }
        ([regex]::Matches($details, [regex]::Escape('TeknoParrot Manager does not count a failed or unchecked update as done.'))).Count | Should -Be 1
        $texts = Get-Fix82RowTexts
        foreach ($heading in @('  Alpha Game', '  Gamma Game', '  Delta Game', '  What was counted')) {
            $at = [Array]::IndexOf($texts, $heading)
            $at | Should -BeGreaterThan 0 -Because $heading
            $texts[$at - 1] | Should -BeExactly '' -Because "$heading starts a new block"
        }
    }

    It 'writes the same facts to the log without anyone pressing D' {
        # Mutation: let the default screen skip Write-TpmOutcome's logging (the facts would be lost when D is not pressed).
        $null = Show-TpmBepInExFailureSummary -Result (New-Fix82BepResult)
        $log = $script:fix82Log -join "`n"
        $log | Should -Match ([regex]::Escape('Result detail [What was counted]: Path preflight: 1 eligible game(s)'))
        $log | Should -Match ([regex]::Escape('Result detail [Alpha Game]: Reason: UNKNOWN_ARCHITECTURE'))
        $log | Should -Match ([regex]::Escape('Result needs attention: Could not tell if this game is 32-bit or 64-bit (1 game).'))
    }

    It 'keeps the Details rows inside the console at <Width> columns' -ForEach @(
        @{ Width = 40 }
        @{ Width = 60 }
        @{ Width = 120 }
    ) {
        # Mutation: print a Details line without wrapping -> a row wider than the console.
        $script:fix82Width = $Width
        $view = Get-TpmBepInExFailureView -Result (New-Fix82BepResult) -LogPath 'C:\Logs\TeknoParrot-Manager.log'
        Show-TpmDetailBlocks -Blocks $view.DetailBlocks -Note $view.DetailsNote
        foreach ($text in (Get-Fix82RowTexts)) { $text.Length | Should -BeLessOrEqual ($Width - 1) -Because "a row at $Width columns: '$text'" }
    }
}

Describe 'FIX82 BepInEx update check: the path check line goes to the log, and the Details line is the same sentence' {
    BeforeEach { Install-Fix82Console }

    It 'logs the path check line instead of printing it, and the Details view rebuilds exactly that sentence from the result' {
        # Mutation: print the "Path preflight" row again (Write-Host instead of Write-Log), or let the Details line count differently from the logged one.
        $approved = Join-Path $TestDrive 'Fix82ApprovedGames'
        $outside = Join-Path $TestDrive 'Fix82OutsideGame'
        $profiles = Join-Path $TestDrive 'Fix82BepProfiles'
        New-Item -ItemType Directory -Path $approved, $outside, $profiles -Force | Out-Null
        $exe = Join-Path $outside 'game.exe'
        New-Item -ItemType File -Path $exe -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $profiles 'Outside.xml') -Value ("<GameProfile><GamePath>$exe</GamePath></GameProfile>")
        Mock Get-BepInExLatestRelease { throw 'release query should not run' }
        Mock Invoke-TpmDownload { throw 'download should not run' }
        $result = Invoke-BepInExUpdateCheckLegacy -UserProfilesDir $profiles -CacheDir (Join-Path $TestDrive 'Fix82BepCache') -ApprovedGamesRoot $approved
        $expected = 'Path preflight: 0 eligible game(s), 0 unavailable-device skip(s), 0 missing-path skip(s), 1 protected/reparse skip(s), 0 other skip(s).'
        (Get-Fix82Text -Rows $script:fix82Rows) | Should -Not -Match 'Path preflight'
        ($script:fix82Log -join "`n") | Should -Match ([regex]::Escape('BepInEx ' + $expected))
        $detailLines = @((Get-TpmBepInExDetailBlocks -Result $result)[0].Lines)
        $detailLines[0] | Should -BeExactly $expected
    }
}

Describe 'FIX82 GPU fix: the vendor is typed, as before' {
    BeforeEach { Install-Fix82Console }

    It 'maps <Answer> to <Vendor> and asks in plain words' -ForEach @(
        @{ Answer = 'AMD'; Vendor = 'AMD' }
        @{ Answer = 'nvidia'; Vendor = 'NVIDIA' }
        @{ Answer = 'Intel'; Vendor = 'Intel' }
        @{ Answer = 'geforce'; Vendor = 'NVIDIA' }
        @{ Answer = 'Radeon'; Vendor = 'AMD' }
    ) {
        # Mutation: change the accepted words, or lose the adapter name or the plain prompt.
        $script:fix82Answers.Enqueue($Answer)
        $chosen = Read-TpmGpuVendorChoice -AdapterName 'Some Adapter'
        $chosen | Should -BeExactly $Vendor
        (Get-Fix82Text -Rows $script:fix82Rows) | Should -Match ([regex]::Escape('Windows reports: Some Adapter'))
        $script:fix82Prompts[0] | Should -BeExactly '  Which graphics card do you have? Type AMD, NVIDIA or Intel (Enter to cancel)'
        ($script:fix82Log -join "`n") | Should -Match ([regex]::Escape("GPU Fix: user-specified vendor = $Vendor"))
    }

    It 'cancels without choosing a vendor on Enter, on a single letter or on anything else, and says nothing was changed: <Case>' -ForEach @(
        @{ Case = 'Enter'; Answer = ''; Said = 'GPU fix canceled. No game was changed.' }
        @{ Case = 'N (means No everywhere else)'; Answer = 'N'; Said = 'That was not AMD, NVIDIA or Intel. No game was changed.' }
        @{ Case = 'A'; Answer = 'A'; Said = 'That was not AMD, NVIDIA or Intel. No game was changed.' }
        @{ Case = 'I'; Answer = 'I'; Said = 'That was not AMD, NVIDIA or Intel. No game was changed.' }
        @{ Case = 'PowerVR'; Answer = 'PowerVR'; Said = 'That was not AMD, NVIDIA or Intel. No game was changed.' }
    ) {
        # Mutation: accept single letters (a beginner pressing N to back out would pick NVIDIA), or pick a default vendor when nothing valid is typed.
        $script:fix82Answers.Enqueue($Answer)
        $chosen = Read-TpmGpuVendorChoice
        $chosen | Should -BeNullOrEmpty -Because $Case
        (Get-Fix82Text -Rows $script:fix82Rows) | Should -Match ([regex]::Escape($Said)) -Because $Case
        (Get-Fix82Text -Rows $script:fix82Rows) | Should -Not -Match 'Using the' -Because $Case
    }
}

Describe 'FIX82 GPU fix result: one plain sentence, the names and paths under Details' {
    BeforeEach { Install-Fix82Console }

    It 'says "Applied the Intel fix to 3 games.", shows where the backup is, and hides the internal names and the zero counts' {
        # Mutation: print the profile names (GpuBoolOn ...), drop the backup folder, or print the Updated/Skipped/Errors rows with zeros on the default screen again.
        $null = Show-TpmGpuFixResult -Result (New-Fix82GpuResult)
        $texts = Get-Fix82RowTexts
        $texts | Should -Contain '  Applied the Intel fix to 3 games.'
        $texts | Should -Contain '  Next: Start a game to try it. Press B to go back.'
        (Get-Fix82Text -Rows $script:fix82Rows) | Should -Match ([regex]::Escape('A backup of your game settings is saved in this folder: D:\TP\UserProfiles\FullBackup\GpuFix_1'))
        (Get-Fix82Text -Rows $script:fix82Rows) | Should -Not -Match 'GpuBoolOn|GpuDiscovered|GpuDropdown|Errors|Skipped|game\(s\)|\bTPM\b'
        @($script:fix82Rows | Where-Object { $_.Text -like '*Applied the Intel fix*' })[0].Color | Should -BeExactly 'Green'
        $script:fix82Prompts.Count | Should -Be 0
    }

    It 'uses the singular for one game' {
        # Mutation: always append "s" -> "1 games".
        $null = Show-TpmGpuFixResult -Result (New-Fix82GpuResult -Vendor 'NVIDIA' -Updated 1 -Changed @('GameOnly'))
        (Get-Fix82RowTexts) | Should -Contain '  Applied the NVIDIA fix to 1 game.'
    }

    It 'shows every fact under Details: totals, names, saved paths, technical reasons, per-game steps and the backup folder' {
        # Mutation: drop the totals, a changed-name set, the backup folder, a skip block or a failure block from the Details view.
        $skip = [pscustomobject]@{ Game = 'GameS'; ReasonKey = 'DEVICE_UNAVAILABLE'; Reason = 'The saved game drive or device is unavailable.'; SavedPath = 'Z:\Games\s.exe'; NextAction = 'Reconnect the drive or device.'; Technical = 'Device not ready' }
        $failure = [pscustomobject]@{ Game = 'GameF'; Operation = 'profile processing'; ReasonKey = 'PROFILE_PROCESSING_FAILED'; Exception = 'Disk full'; EvidencePreserved = $true; BackupPath = 'D:\bk'; NextAction = 'Review the failure.' }
        $result = New-Fix82GpuResult -Outcome 'PARTIAL_APPLIED' -Updated 2 -Unchanged 1 -NotApplicable 4 -Skipped 1 -Errors 1 -Failed 1 -MissingDevice 1 -SkipDetails @($skip) -FailureRecords @($failure) -Changed @('GpuBoolOn', 'GpuDropdown')
        $view = Get-TpmGpuFixResultView -Result $result
        Show-TpmDetailBlocks -Blocks $view.DetailBlocks -Note $view.DetailsNote
        $details = Get-Fix82Text -Rows $script:fix82Rows
        foreach ($fact in @(
            'GPU Fix changes saved compatibility fields only; TeknoParrot Manager does not verify game launch or display output.',
            'GPU detected: Intel Arc', 'Updated: 2 games', 'Already correct: 1 game', 'No GPU fix fields: 4 games', 'Skipped: 1 game', 'Not attempted: 0 games (stopped before writing)', 'Errors: 1',
            'Folder: D:\TP\UserProfiles\FullBackup\GpuFix_1',
            'GameS', 'What happened: The saved game drive or device is unavailable.', 'Saved path: Z:\Games\s.exe', 'What to do: Reconnect the drive or device.', 'Technical: Device not ready', 'Reason code: DEVICE_UNAVAILABLE',
            'GameF', 'Step: profile processing', 'Reason code: PROFILE_PROCESSING_FAILED', 'Detail: Disk full', 'Verified backup: D:\bk', 'What to do: Review the failure.',
            'Changed (2)', 'GpuBoolOn, GpuDropdown'
        )) { $details | Should -Match ([regex]::Escape($fact)) -Because $fact }
        $texts = Get-Fix82RowTexts
        foreach ($heading in @('  GameS', '  GameF', '  What was counted')) {
            $at = [Array]::IndexOf($texts, $heading)
            $at | Should -BeGreaterThan 0 -Because $heading
            $texts[$at - 1] | Should -BeExactly '' -Because "$heading starts a new block"
        }
    }

    It 'groups skipped games by reason on one line and tells the user to plug in the drive' {
        # Mutation: print one line per skipped game, or lose the plug-in-the-drive advice when a drive is the problem.
        $reason = 'The saved game drive or device is unavailable.'
        $skips = @(
            [pscustomobject]@{ Game = 'GameA'; ReasonKey = 'DEVICE_UNAVAILABLE'; Reason = $reason; SavedPath = 'Z:\a.exe'; NextAction = 'n'; Technical = 't' },
            [pscustomobject]@{ Game = 'GameB'; ReasonKey = 'DEVICE_UNAVAILABLE'; Reason = $reason; SavedPath = 'Z:\b.exe'; NextAction = 'n'; Technical = 't' }
        )
        $result = New-Fix82GpuResult -Outcome 'FAILED_BEFORE_MUTATION' -Updated 0 -Skipped 2 -MissingDevice 2 -SkipDetails $skips -Changed @()
        $null = Show-TpmGpuFixResult -Result $result
        $texts = Get-Fix82RowTexts
        $texts | Should -Contain '  Nothing was changed. Some games were skipped.'
        $texts | Should -Contain '    - 2 games skipped. The saved game drive or device is unavailable.'
        (Get-Fix82Text -Rows $script:fix82Rows) | Should -Match ([regex]::Escape('Next: Plug in the drive for the game, then press R to run it again.'))
        @($texts | Where-Object { $_ -like '*GameA*' -or $_ -like '*Z:\*' }).Count | Should -Be 0
        @($script:fix82Rows | Where-Object { $_.Text -eq '  Nothing was changed. Some games were skipped.' })[0].Color | Should -BeExactly 'Yellow'
    }

    It 'words each other outcome in plain language: <Case>' -ForEach @(
        @{ Case = 'nothing needed'; Params = @{ Outcome = 'NO_OP'; Updated = 0; Unchanged = 4; Changed = @() }; Title = '  No game needed a GPU fix. Nothing was changed.'; Extra = ''; Next = 'Next: Press B to go back.' }
        @{ Case = 'cancelled'; Params = @{ Outcome = 'FAILED_BEFORE_MUTATION'; Cancelled = $true; Updated = 0; Changed = @() }; Title = '  GPU fix canceled. No game was changed.'; Extra = ''; Next = 'Next: Press B to go back.' }
        @{ Case = 'partly done'; Params = @{ Outcome = 'PARTIAL_APPLIED'; Updated = 2; Failed = 1; Errors = 1; Changed = @('A', 'B') }; Title = '  Applied the Intel fix to 2 games, but some games need attention.'; Extra = '    - 1 game could not be updated.'; Next = 'Next: Press D to see why, or R to run it again.' }
        @{ Case = 'safety copy failed'; Params = @{ Outcome = 'FAILED_BEFORE_MUTATION'; Updated = 0; Errors = 1; Failed = 1; Reason = 'PROFILE_BACKUP_FAILED'; Changed = @() }; Title = '  The GPU fix could not finish.'; Extra = '    - A safety copy of your game settings could not be made, so nothing was changed.'; Next = 'Next: Press D to see why, or R to run it again.' }
    ) {
        # Mutation: treat every non-success outcome with the same sentence, or leave the plain reason out when the safety copy fails.
        $paramSet = $Params
        $null = Show-TpmGpuFixResult -Result (New-Fix82GpuResult @paramSet)
        $texts = Get-Fix82RowTexts
        $texts | Should -Contain $Title -Because $Case
        if ($Extra) { $texts | Should -Contain $Extra -Because $Case }
        (Get-Fix82Text -Rows $script:fix82Rows) | Should -Match ([regex]::Escape($Next)) -Because $Case
    }

    It 'keeps every row inside the console and no run longer than 5 lines at <Width> columns' -ForEach @(
        @{ Width = 40 }
        @{ Width = 60 }
        @{ Width = 120 }
    ) {
        # Mutation: print the sentences without wrapping -> a row wider than the console.
        $script:fix82Width = $Width
        $null = Show-TpmGpuFixResult -Result (New-Fix82GpuResult -Outcome 'PARTIAL_APPLIED' -Updated 2 -Unchanged 1 -Failed 1 -Errors 1)
        $texts = Get-Fix82RowTexts
        foreach ($text in $texts) { $text.Length | Should -BeLessOrEqual ($Width - 1) -Because "a row at $Width columns: '$text'" }
        (Get-Fix82LongestRun -Rows $texts -Limit ($Width - 1)) | Should -BeLessOrEqual 5
    }
}

Describe 'FIX82 GPU fix run: the work in progress no longer prints raw rows' {
    BeforeEach { Install-Fix82Console }

    It 'prints no SKIP row, backup path, profile name or counter block, logs them instead, and never says TPM in a reason' {
        # Mutation: print "SKIP <id>: <reason>", the "Backup: <path>" row, the green profile name or the Updated/Skipped/Errors block again.
        # Mutation: bring back "TPM has a saved location ..." in the skip reason.
        $root = Join-Path $TestDrive 'fix82-gpu-run'
        $profiles = Join-Path $root 'UserProfiles'
        $gameRoot = Join-Path $root 'Game'
        New-Item -ItemType Directory -Path $profiles, $gameRoot -Force | Out-Null
        $gamePath = Join-Path $gameRoot 'game.exe'
        Set-Content -LiteralPath $gamePath -Value 'fixture'
        $field = '<ConfigValues><FieldInformation><FieldName>UseNvidiaFix</FieldName><FieldValue>1</FieldValue></FieldInformation></ConfigValues>'
        Set-Content -LiteralPath (Join-Path $profiles 'Example.xml') -Value ("<GameProfile><GamePath>{0}</GamePath>{1}</GameProfile>" -f [System.Security.SecurityElement]::Escape($gamePath), $field)
        Set-Content -LiteralPath (Join-Path $profiles 'Lost.xml') -Value ("<GameProfile><GamePath>Z:\nowhere\lost.exe</GamePath>{0}</GameProfile>" -f $field)
        Mock Get-DetectedGpuVendor { [pscustomobject]@{ Vendor = 'NVIDIA'; Name = 'Test GPU' } }
        Mock Get-GpuFixFieldNames { [pscustomobject]@{ GameProfilesFound = $true; BoolFields = @('UseNvidiaFix'); DropdownFields = @() } }
        Mock Test-TpmGameMutationPath { [pscustomobject]@{ Valid = $true; ReasonCode = $null; Reason = $null; ResolvedPath = $GamePath; GameDirectory = [System.IO.Path]::GetDirectoryName($GamePath) } }
        Mock Test-TpmGameMutationPath { [pscustomobject]@{ Valid = $false; ReasonCode = 'GAME_PATH_MISSING'; Reason = 'The game file was not found.'; ResolvedPath = $null; GameDirectory = $null } } -ParameterFilter { $GamePath -like '*nowhere*' }
        Mock New-TpmVerifiedUserProfilesBackup { New-Fix82VerifiedBackup }

        $result = Invoke-GpuFixSetupLegacy -UserProfilesDir $profiles -TpRoot $root

        $result.Updated | Should -Be 1
        $result.Skipped | Should -Be 1
        $texts = Get-Fix82RowTexts
        foreach ($text in $texts) { $text | Should -Not -Match '(?i)\bSKIP\b|Backup:|Updated\s+:|Skipped\s+:|Errors\s+:|Note: GPU Fix' }
        $texts | Should -Not -Contain '    Example'
        $log = $script:fix82Log -join "`n"
        $log | Should -Match ([regex]::Escape('GPU Fix: skipped Lost; path reason=GAME_PATH_MISSING'))
        $log | Should -Match ([regex]::Escape('GPU Fix: verified backup at backup-evidence'))
        $result.SkipDetails[0].Reason | Should -Match ([regex]::Escape('TeknoParrot Manager has a saved location for this game'))
        $result.SkipDetails[0].Reason | Should -Not -Match '\bTPM\b'
    }
}

Describe 'FIX82 Force feedback: a four-line intro, the subscription page named once, a one-line result' {
    BeforeEach { Install-Fix82Console }

    It 'shows at most four short lines at <Width> columns, inside the console, without the subscription address' -ForEach @(
        @{ Width = 40 }
        @{ Width = 60 }
        @{ Width = 120 }
    ) {
        # Mutation: restore the 14-line intro (more than 4 lines, with the URL and the FFB Blaster paragraph).
        $script:fix82Width = $Width
        Write-TpmFfbIntro
        $texts = Get-Fix82RowTexts
        foreach ($text in $texts) { $text.Length | Should -BeLessOrEqual ($Width - 1) -Because "a row at $Width columns: '$text'" }
        (Get-Fix82LongestRun -Rows $texts -Limit ($Width - 1)) | Should -BeLessOrEqual 4
        $plain = Get-Fix82Text -Rows $script:fix82Rows
        $plain | Should -Match 'paid membership'
        $plain | Should -Not -Match 'teknoparrot\.com|Subscription'
        if ($Width -eq 120) { @($texts | Where-Object { $_.Trim() }).Count | Should -Be 4 }
    }

    It 'names the subscription page exactly once across the intro and the membership question, and never repeats the FFB Blaster paragraph' {
        # Mutation: bring back the "FFB Blaster is TeknoParrot's own built-in force feedback" paragraph or the second URL.
        Mock Read-TpmYesNo { 'N' }
        Write-TpmFfbIntro
        $result = Invoke-FFBBlasterSetup -UserProfilesDir $TestDrive -TpRoot $TestDrive
        $plain = Get-Fix82Text -Rows $script:fix82Rows
        ([regex]::Matches($plain, [regex]::Escape('teknoparrot.com/en/Home/Subscription'))).Count | Should -Be 1
        $plain | Should -Match ([regex]::Escape('Do you have a paid TeknoParrot membership?'))
        $plain | Should -Not -Match "built-in force feedback|included with any paid"
        $result.ReasonCode | Should -BeExactly 'NO_MEMBERSHIP'
        (Get-Fix82LongestRun -Rows (Get-Fix82RowTexts) -Limit 119) | Should -BeLessOrEqual 5
    }

    It 'prints no profile name and no Updated row while FFB Blaster is applied, and logs them instead' {
        # Mutation: print "Updated  : N profile(s)" or the green internal profile name again.
        $f = New-Fix82ProfileFixture -Root (Join-Path $TestDrive 'fix82-ffb-run') -Code 'N09FfbCat'
        Mock Read-TpmYesNo { 'Y' }
        Mock Get-FFBBlasterFieldNames { @('FFB Blaster') }
        Mock New-TpmVerifiedUserProfilesBackup { New-Fix82VerifiedBackup }
        $result = Invoke-FFBBlasterSetup -UserProfilesDir $f.Profiles -TpRoot $f.Tp
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        $texts = Get-Fix82RowTexts
        $texts | Should -Not -Contain '    N09FfbCat'
        foreach ($text in $texts) { $text | Should -Not -Match 'Updated\s+:|N09FfbCat' }
        ($script:fix82Log -join "`n") | Should -Match ([regex]::Escape('FFBBlaster: updated N09FfbCat'))
        $view = Get-TpmFfbNativeResultView -Result $result
        $view.Title | Should -BeExactly 'FFB Blaster is now on for 1 game.'
        $view.DetailBlocks[0].Heading | Should -BeExactly 'Games where FFB Blaster was turned on (1)'
        $view.DetailBlocks[0].Lines | Should -Be @('N09FfbCat')
        $view.DetailBlocks[1].Lines | Should -Be @('Folder: backup-evidence')
    }

    It 'shows one result line, and the game names only when Details is chosen' {
        # Mutation: show the names (N09FfbCat, N09FfbField) or the safety copy folder on the default screen; or drop them from Details.
        $tx = New-TpmProfileTransactionResult -WorkflowKey 'FFBSetup' -OperationKey 'FFBBlaster' -Outcome 'SUCCEEDED' -ProductState 'INTENDED' -Summary 'FFB Blaster profiles were updated and verified.' -Items @('N09FfbCat', 'N09FfbField') -ChangedItems @('N09FfbCat', 'N09FfbField') -CompletedItems @('N09FfbCat', 'N09FfbField') -MutationStarted $true -Backup ([pscustomobject]@{ Required = $true; Attempted = $true; Created = $true; Verified = $true; Path = 'D:\bk\FFBBlaster_1'; Manifest = @() }) -ReasonCode 'PROFILE_UPDATES_VERIFIED' -FinalChecks @('read back')
        Install-Fix82Console -Interactive $true -Answers @('')
        Show-TpmFfbNativeResult -Result $tx
        $plain = Get-Fix82Text -Rows $script:fix82Rows
        $plain | Should -Match ([regex]::Escape('FFB Blaster is now on for 2 games.'))
        $plain | Should -Match ([regex]::Escape('Next: You can add the free FFB plugin for more games.'))
        $plain | Should -Not -Match 'N09Ffb|bk\\FFBBlaster'
        $script:fix82Prompts[0] | Should -BeExactly '  [D] Details, or press Enter to continue'
        Install-Fix82Console -Interactive $true -Answers @('D')
        Show-TpmFfbNativeResult -Result $tx
        $plain = Get-Fix82Text -Rows $script:fix82Rows
        $plain | Should -Match ([regex]::Escape('Games where FFB Blaster was turned on (2)'))
        $plain | Should -Match ([regex]::Escape('N09FfbCat, N09FfbField'))
        $plain | Should -Match ([regex]::Escape('Folder: D:\bk\FFBBlaster_1'))
    }
}

Describe 'FIX82 dgVoodoo2 result: one result line, one not-changed line, one next step' {
    BeforeEach { Install-Fix82Console }

    It 'replaces the five headed sections with three short parts and never repeats a sentence' {
        # Mutation: print the "What TeknoParrot Manager did / Why / did not change / What to do next" sections or the "unowned hook" sentence on the default screen again.
        $null = Show-TpmDgVoodoo2Result -Result (New-Fix82DgResult)
        $texts = Get-Fix82RowTexts
        $texts | Should -Be @(
            '',
            '  dgVoodoo2 was added to 2 games.',
            '  Not changed: Existing dgVoodoo2 files were not replaced or removed.',
            '',
            '  Next: Try a game. If it looks wrong or crashes, send a support package and the log.',
            ''
        )
        (Get-Fix82Text -Rows $script:fix82Rows) | Should -Not -Match 'What TeknoParrot Manager did|Why TeknoParrot Manager|unowned|hook|DLL|legacy API|game\(s\)|\bTPM\b'
        @($script:fix82Rows | Where-Object { $_.Text -like '*was added to*' })[0].Color | Should -BeExactly 'Green'
        $script:fix82Prompts.Count | Should -Be 0
    }

    It 'says plainly that nothing was installed when no game needed dgVoodoo2' {
        # Mutation: say "dgVoodoo2 was added to 0 games." for a no-op result.
        $null = Show-TpmDgVoodoo2Result -Result (New-Fix82DgResult -Installed @() -NoOp $true)
        $texts = Get-Fix82RowTexts
        $texts | Should -Contain '  No game needed a new dgVoodoo2 file. Nothing was changed.'
        $texts | Should -Contain '  Next: Nothing else to do. Press B to go back.'
        (Get-Fix82Text -Rows $script:fix82Rows) | Should -Not -Match '(?<!\d)0 games?\b'
    }

    It 'uses the singular for one game and groups skipped games by reason' {
        # Mutation: always append "s" or list skipped games one per line.
        $skip = @(
            [pscustomobject]@{ Game = 'GameS1'; ReasonCode = 'GAME_PATH_MISSING'; Reason = 'TeknoParrot Manager could not find the saved game executable.'; SavedPath = 'Z:\s1.exe'; NextAction = 'Use Library Health Check.'; Technical = 'Missing' },
            [pscustomobject]@{ Game = 'GameS2'; ReasonCode = 'GAME_PATH_MISSING'; Reason = 'TeknoParrot Manager could not find the saved game executable.'; SavedPath = 'Z:\s2.exe'; NextAction = 'Use Library Health Check.'; Technical = 'Missing' }
        )
        $null = Show-TpmDgVoodoo2Result -Result (New-Fix82DgResult -Installed @((New-Fix82DgDetail)) -Skipped $skip -MissingPath 2)
        $texts = Get-Fix82RowTexts
        $texts | Should -Contain '  dgVoodoo2 was added to 1 game.'
        (Get-Fix82Text -Rows $script:fix82Rows) | Should -Match ([regex]::Escape('2 games skipped (GameS1 and GameS2). TeknoParrot Manager could not find the saved game executable.'))
        @($texts | Where-Object { $_ -like '*Z:\*' }).Count | Should -Be 0
        @($script:fix82Rows | Where-Object { $_.Text -like '*was added to*' })[0].Color | Should -BeExactly 'Yellow'
    }

    It 'keeps every fact of the old screen under Details, each sentence once' {
        # Mutation: drop the why, the not-changed notes, the per-game API/destination/files/config, the skipped-game block or the override count from the Details view.
        $skip = @([pscustomobject]@{ Game = 'GameS'; ReasonCode = 'GAME_PATH_MISSING'; Reason = 'r'; SavedPath = 'Z:\s.exe'; NextAction = 'Use Library Health Check.'; Technical = 'Missing file' })
        $result = New-Fix82DgResult -Skipped $skip -Overrides 2
        $view = Get-TpmDgVoodoo2ResultView -Result $result
        Show-TpmDetailBlocks -Blocks $view.DetailBlocks -Note $view.DetailsNote
        $details = Get-Fix82Text -Rows $script:fix82Rows
        foreach ($fact in @(
            'Why: Older DirectX and Glide games may not display correctly on modern Windows. dgVoodoo2 helps translate those older graphics calls for modern Windows.',
            'Not changed: Existing dgVoodoo2 DLL files were not removed or replaced, including unowned or changed files.',
            'Also not changed: TeknoParrot Manager only added missing compatibility DLLs. Skipped missing-path games were not changed.',
            'Note: TeknoParrot Manager does not remove an unowned dgVoodoo2 hook automatically. If you want existing or changed files gone, remove them by hand.',
            'Config overrides: 2 per-game config override(s) found',
            'GameA', 'Legacy API: D3D8', 'Destination: D:\Games\GameA', 'Files: D3D8.dll, DDraw.dll', 'Config: dgVoodoo.conf',
            'GameB', 'Legacy API: not detected (manual selection)',
            'Skipped game: GameS', 'Saved path: Z:\s.exe', 'Reason: Missing file', 'Next action: Use Library Health Check.'
        )) { $details | Should -Match ([regex]::Escape($fact)) -Because $fact }
        ([regex]::Matches($details, [regex]::Escape('does not remove an unowned dgVoodoo2 hook automatically'))).Count | Should -Be 1
        $texts = Get-Fix82RowTexts
        foreach ($heading in @('  About this change', '  GameA', '  GameB', '  Skipped game: GameS')) {
            $at = [Array]::IndexOf($texts, $heading)
            $at | Should -BeGreaterThan 0 -Because $heading
            $texts[$at - 1] | Should -BeExactly '' -Because "$heading starts a new block"
        }
        $null = Show-TpmDgVoodoo2Result -Result $result
        ($script:fix82Log -join "`n") | Should -Match ([regex]::Escape('Result detail [GameA]: Destination: D:\Games\GameA'))
    }

    It 'keeps every row inside the console and no run longer than 5 lines at <Width> columns' -ForEach @(
        @{ Width = 40 }
        @{ Width = 60 }
        @{ Width = 120 }
    ) {
        # Mutation: print a sentence without wrapping, or without the blank row before Next.
        $script:fix82Width = $Width
        $null = Show-TpmDgVoodoo2Result -Result (New-Fix82DgResult)
        $texts = Get-Fix82RowTexts
        foreach ($text in $texts) { $text.Length | Should -BeLessOrEqual ($Width - 1) -Because "a row at $Width columns: '$text'" }
        (Get-Fix82LongestRun -Rows $texts -Limit ($Width - 1)) | Should -BeLessOrEqual 5
        $nextAt = Find-Fix82Row -Rows $texts -Prefix '  Next:'
        $texts[$nextAt - 1] | Should -BeExactly ''
    }
}

Describe 'FIX82 dgVoodoo2 setup run: no counter block and no repeated sentence while the files are installed' {
    BeforeEach { Install-Fix82Console }

    It 'logs the "unowned hook" note instead of printing it, prints no Deployed/OK rows, and returns what the Details view needs' {
        # Mutation: print "Deployed  : N game(s)", the "OK <game>" row or the two "unowned hook" rows again.
        $root = Join-Path $TestDrive 'fix82-dgvoodoo-run'
        $profiles = Join-Path $root 'UserProfiles'
        $source = Join-Path $root 'Source'
        $gameDir = Join-Path $root 'Game'
        $tpRoot = Join-Path $root 'TeknoParrot'
        $assets = Join-Path $root 'Assets'
        New-Item -ItemType Directory -Path $profiles, $source, $gameDir, (Join-Path $tpRoot 'GameProfiles') -Force | Out-Null
        $gamePath = Join-Path $gameDir 'game.exe'
        [System.IO.File]::WriteAllText($gamePath, 'game')
        [System.IO.File]::WriteAllText((Join-Path $source 'D3D8.dll'), 'dll-bytes')
        [System.IO.File]::WriteAllText((Join-Path $profiles 'Game.xml'), "<GameProfile><GamePath>$gamePath</GamePath></GameProfile>")
        $oldLayout = $script:TpmOwnedLayout
        $script:TpmOwnedLayout = [pscustomobject]@{ Assets = $assets }
        Mock Get-GameLegacyApi { @('D3D8') }
        Mock Read-TpmChoice { 'A' }
        try {
            $result = Invoke-DgVoodoo2Setup -UserProfilesDir $profiles -SourceDir $source
        } finally {
            $script:TpmOwnedLayout = $oldLayout
        }
        $diagnostics = 'result=' + ($result | ConvertTo-Json -Depth 3 -Compress) + ' log=[' + ($script:fix82Log -join ' | ') + ']'
        $result.Deployed | Should -Be 1 -Because $diagnostics
        $result.PresetOverrides | Should -Be 0
        @($result.DeploymentDetails).Count | Should -Be 1
        foreach ($text in (Get-Fix82RowTexts)) { $text | Should -Not -Match 'Deployed\s+:|^\s+OK\s|unowned|Per-game config overrides|Skipped\s+:|Errors\s+:' }
        ($script:fix82Log -join "`n") | Should -Match ([regex]::Escape('does not remove an unowned dgVoodoo2 hook automatically'))
        (Get-TpmDgVoodoo2ResultView -Result $result).Title | Should -BeExactly 'dgVoodoo2 was added to 1 game.'
    }
}

Describe 'FIX82 Crosshair result: games by name, folders under Details' {
    BeforeEach { Install-Fix82Console }

    It 'names the games and the choice and prints no folder' {
        # Mutation: print "<item> -> <folder>" rows, the "Deployed : N lightgun game(s)" row or a path on the default screen again.
        $null = Show-TpmCrosshairResult -Result (New-Fix82CrosshairResult -Hidden @('A', 'B', 'C', 'D')) -Unattended
        $texts = Get-Fix82RowTexts
        $texts | Should -Be @(
            '',
            '  Crosshairs are set up for 4 games.',
            '    - Player 1 uses cross-red. Player 2 uses cross-blue.',
            '    - Games: GunA, GunB, GunC and GunD',
            '    - The Windows cursor is now hidden in 4 games.',
            '',
            '  Next: Start a lightgun game to try the new crosshairs.',
            ''
        )
        (Get-Fix82Text -Rows $script:fix82Rows) | Should -Not -Match '\\|->|Deployed|Updated :|game\(s\)|\bTPM\b'
    }

    It 'uses the singular, and says plainly when nothing changed or there was no lightgun game: <Case>' -ForEach @(
        @{ Case = 'one game'; Params = @{ Games = @('Only Gun') }; Title = '  Crosshairs are set up for 1 game.' }
        @{ Case = 'already set up'; Params = @{ NoOp = $true }; Title = '  The crosshairs were already set up. Nothing was changed.' }
        @{ Case = 'no lightgun game'; Params = @{ Games = @(); NoTargets = $true }; Title = '  Your crosshair choice was saved. No lightgun games were found to update.' }
        @{ Case = 'nothing to do at all'; Params = @{ Games = @(); NoTargets = $true; NoOp = $true }; Title = '  No lightgun games were found. Nothing was changed.' }
        # Who gets hurt: a user whose only lightgun game was skipped (PCSX2 open, or setup declined) was told no lightgun games exist.
        # Mutation: build the title from NoTargets alone, as before -> "No lightgun games were found" although one was skipped.
        @{ Case = 'the only game was skipped'; Params = @{ Games = @(); NoTargets = $true; Skipped = 1 }; Title = '  Your crosshair choice was saved, but your lightgun games were skipped, so none were updated.' }
    ) {
        # Mutation: always append "s", or say "set up for 0 games" when there was no lightgun game.
        $paramSet = $Params
        $null = Show-TpmCrosshairResult -Result (New-Fix82CrosshairResult @paramSet) -Unattended
        (Get-Fix82RowTexts) | Should -Contain $Title -Because $Case
        (Get-Fix82Text -Rows $script:fix82Rows) | Should -Not -Match '(?<!\d)0 games?\b' -Because $Case
    }

    It 'shows at most six names and says how many more, with the full list under Details' {
        # Mutation: list all names on the default screen (a 40-game library would print a wall of names), or drop the full list from Details.
        $games = @(1..9 | ForEach-Object { 'Game{0:D2}' -f $_ })
        $result = New-Fix82CrosshairResult -Games $games
        $null = Show-TpmCrosshairResult -Result $result -Unattended
        (Get-Fix82RowTexts) | Should -Contain '    - Games: Game01, Game02, Game03, Game04, Game05, Game06 and 3 more'
        $view = Get-TpmCrosshairResultView -Result $result
        $all = @($view.DetailBlocks | Where-Object { $_.Heading -eq 'All games (9)' })[0]
        $all.Lines | Should -Be @(($games -join ', '))
    }

    It 'names each skipped game and why under Details' {
        # Mutation: leave the SkippedGames block out of the Details view -> the screen says "skipped" but Details cannot say which game.
        $result = New-Fix82CrosshairResult -Games @() -NoTargets $true -Skipped 2
        $result | Add-Member -NotePropertyName SkippedGames -NotePropertyValue @('Gun One: the ElfLdr2 folder was not found', 'Gun Two: the ElfLdr2 folder was not found')
        $block = @((Get-TpmCrosshairResultView -Result $result).DetailBlocks | Where-Object { $_.Heading -eq 'Skipped games (2)' })[0]
        $block.Lines | Should -Be @('Gun One: the ElfLdr2 folder was not found', 'Gun Two: the ElfLdr2 folder was not found')
    }

    It 'keeps every folder, the PCSX2 notes and the hidden-cursor games under Details, in blocks, and in the log' {
        # Mutation: drop the folders, the PCSX2 block or the cursor block from the Details view.
        Install-Fix82Console -Interactive $true -Answers @('D')
        Show-TpmCrosshairResult -Result (New-Fix82CrosshairResult -Hidden @('GunA', 'GunB'))
        $plain = Get-Fix82Text -Rows $script:fix82Rows
        $script:fix82Prompts[0] | Should -BeExactly '  [D] Details, or press Enter to continue'
        foreach ($fact in @(
            'Player 1: cross-red', 'Player 2: cross-blue',
            'ElfLdr2: D:\TeknoParrot\ElfLdr2', 'Pcsx2x6: D:\TeknoParrot\pcsx2x6\crosshairs',
            'PCSX2 folder: D:\TeknoParrot\pcsx2x6', 'PCSX2 settings: PCSX2.ini updated',
            'Cursor hidden (2)', 'GunA, GunB'
        )) { $plain | Should -Match ([regex]::Escape($fact)) -Because $fact }
        $texts = Get-Fix82RowTexts
        foreach ($heading in @('  Where the crosshair files went', '  PCSX2', '  Your crosshair choice')) {
            $at = [Array]::IndexOf($texts, $heading)
            $at | Should -BeGreaterThan 0 -Because $heading
            $texts[$at - 1] | Should -BeExactly '' -Because "$heading starts a new block"
        }
        ($script:fix82Log -join "`n") | Should -Match ([regex]::Escape('Result detail [Where the crosshair files went]: ElfLdr2: D:\TeknoParrot\ElfLdr2'))
    }

    It 'keeps every row inside the console and no run longer than 5 lines at <Width> columns' -ForEach @(
        @{ Width = 40 }
        @{ Width = 60 }
        @{ Width = 120 }
    ) {
        # Mutation: print a bullet without wrapping, or without the blank row before Next.
        $script:fix82Width = $Width
        $null = Show-TpmCrosshairResult -Result (New-Fix82CrosshairResult -Hidden @('A', 'B', 'C', 'D')) -Unattended
        $texts = Get-Fix82RowTexts
        foreach ($text in $texts) { $text.Length | Should -BeLessOrEqual ($Width - 1) -Because "a row at $Width columns: '$text'" }
        (Get-Fix82LongestRun -Rows $texts -Limit ($Width - 1)) | Should -BeLessOrEqual 5
        $nextAt = Find-Fix82Row -Rows $texts -Prefix '  Next:'
        $texts[$nextAt - 1] | Should -BeExactly ''
    }
}

Describe 'FIX82 Crosshair setup run: no folder rows while the files are copied, and the cursor rows are logged' {
    BeforeEach { Install-Fix82Console }

    It 'prints one short sentence instead of the folder rows and the Deployed count, and returns the games and folders for Details' {
        # Mutation: print "<item> -> <folder>" or "Deployed : N lightgun game(s)" again; or lose the game label / folder in the returned result.
        $root = Join-Path $TestDrive 'Fix82CrosshairRun'
        $crosshairs = Join-Path $TestDrive 'Crosshairs'
        $profiles = Join-Path $root 'UserProfiles'
        $games = Join-Path $root 'Games'
        $tpRoot = Join-Path $root 'TeknoParrot'
        foreach ($directory in @($crosshairs, $profiles, $games, $tpRoot)) { [void][System.IO.Directory]::CreateDirectory($directory) }
        [System.IO.File]::WriteAllBytes((Join-Path $crosshairs '001.png'), [byte[]](1, 2, 3))
        $gamePath = Join-Path $games 'FixtureGame.exe'
        [System.IO.File]::WriteAllText($gamePath, '', (New-Object System.Text.UTF8Encoding $false))
        [System.IO.File]::WriteAllText((Join-Path $profiles 'FixtureGame.xml'), ('<GameProfile><GameName>Fixture Game</GameName><GunGame>true</GunGame><EmulatorType>Other</EmulatorType><GamePath>{0}</GamePath></GameProfile>' -f $gamePath), (New-Object System.Text.UTF8Encoding $false))
        Mock Test-PngFile { $true }
        Mock Show-TpmCrosshairPreviewWindow { [pscustomobject]@{ Available = $false; Cancelled = $false; P1Index = $null; P2Index = $null; TimedOut = $false; Reason = 'FIXTURE' } }
        Mock Resolve-Pcsx2Directory { $null }
        Mock Test-TpmGameMutationPath { [pscustomobject]@{ Valid = $true; GameDirectory = $games } }
        Mock Read-HostSafe { if ($Prompt -match '(?i)Y/N') { if ($Prompt -match '(?i)hide the Windows cursor') { 'N' } else { 'Y' } } else { '0' } }

        $result = Invoke-CrosshairSetup -UserProfilesDir $profiles -TpRoot $tpRoot

        $result.Succeeded | Should -BeTrue
        $result.DeployedGames | Should -Be @('Fixture Game')
        $result.P1Name | Should -BeExactly '001'
        $result.TargetFolders[0].Item | Should -BeExactly 'FixtureGame'
        $result.TargetFolders[0].Folder | Should -BeExactly $games
        $texts = Get-Fix82RowTexts
        foreach ($text in $texts) { $text | Should -Not -Match '->|Deployed\s+:|lightgun game\(s\)|Skipped\s+:|Errors\s+:' }
        @($texts | Where-Object { $_.Contains($games) }).Count | Should -Be 0 -Because 'no folder is printed by the default screen'
        $texts | Should -Contain '  The crosshair files were copied and checked.'
        ($script:fix82Log -join "`n") | Should -Match ([regex]::Escape('Crosshairs: verified P1/P2 deployment to ' + $games))
        $view = Get-TpmCrosshairResultView -Result $result
        $view.Title | Should -BeExactly 'Crosshairs are set up for 1 game.'
        @($view.DetailBlocks | Where-Object { $_.Heading -eq 'Where the crosshair files went' })[0].Lines | Should -Contain ('FixtureGame: ' + $games)
    }

    It 'still reports success when one game was skipped but the other files were copied and checked' {
        $root = Join-Path $TestDrive 'Fix82CrosshairSkip'
        $crosshairs = Join-Path $TestDrive 'Crosshairs'
        $profiles = Join-Path $root 'UserProfiles'
        $games = Join-Path $root 'Games'
        $tpRoot = Join-Path $root 'TeknoParrot'
        foreach ($directory in @($crosshairs, $profiles, $games, $tpRoot)) { [void][System.IO.Directory]::CreateDirectory($directory) }
        [System.IO.File]::WriteAllBytes((Join-Path $crosshairs '001.png'), [byte[]](1, 2, 3))
        $gamePath = Join-Path $games 'FixtureGame.exe'
        [System.IO.File]::WriteAllText($gamePath, '', (New-Object System.Text.UTF8Encoding $false))
        $enc = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText((Join-Path $profiles 'FixtureGame.xml'), ('<GameProfile><GameName>Fixture Game</GameName><GunGame>true</GunGame><EmulatorType>Other</EmulatorType><GamePath>{0}</GamePath></GameProfile>' -f $gamePath), $enc)
        [System.IO.File]::WriteAllText((Join-Path $profiles 'NoPathGame.xml'), '<GameProfile><GameName>No Path Game</GameName><GunGame>true</GunGame><EmulatorType>Other</EmulatorType><GamePath></GamePath></GameProfile>', $enc)
        Mock Test-PngFile { $true }
        Mock Show-TpmCrosshairPreviewWindow { [pscustomobject]@{ Available = $false; Cancelled = $false; P1Index = $null; P2Index = $null; TimedOut = $false; Reason = 'FIXTURE' } }
        Mock Resolve-Pcsx2Directory { $null }
        Mock Test-TpmGameMutationPath { [pscustomobject]@{ Valid = $true; GameDirectory = $games } }
        Mock Read-HostSafe { if ($Prompt -match '(?i)Y/N') { if ($Prompt -match '(?i)hide the Windows cursor') { 'N' } else { 'Y' } } else { '0' } }

        $result = Invoke-CrosshairSetup -UserProfilesDir $profiles -TpRoot $tpRoot

        $result.Skipped | Should -Be 1
        $result.DeployedGames | Should -Be @('Fixture Game')
        $result.Succeeded | Should -BeTrue
    }

    It 'logs each hidden-cursor game instead of printing its name, and prints no "Updated" row' {
        # Mutation: print "Updated : <name>" or "Updated  : N lightgun game(s)" again.
        $f = New-Fix82ProfileFixture -Root (Join-Path $TestDrive 'fix82-cursor-run') -Code 'GameA'
        Mock New-TpmVerifiedUserProfilesBackup { New-Fix82VerifiedBackup }
        $result = Invoke-CursorHideSetup -UserProfilesDir $f.Profiles
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        foreach ($text in (Get-Fix82RowTexts)) { $text | Should -Not -Match 'Updated\s+:|GameA' }
        ($script:fix82Log -join "`n") | Should -Match ([regex]::Escape('CursorHide: updated GameA'))
        @($result.Mutation.CompletedItems) | Should -Be @('GameA')
    }
}

Describe 'FIX82 plain reasons for the new codes' {
    It 'knows the download and safety copy codes the screens use, with no bare TPM: <Code>' -ForEach @(
        @{ Code = 'RELEASE_QUERY_FAILED' }
        @{ Code = 'DOWNLOAD_FAILED' }
        @{ Code = 'UNSAFE_RELEASE_FILENAME' }
        @{ Code = 'PROFILE_BACKUP_FAILED' }
    ) {
        # Mutation: delete the entry from Get-TpmPlainReasonTable -> the generic "This could not be completed" sentence is shown for a known cause.
        $reason = Get-TpmPlainReason -Code $Code
        $reason.Known | Should -BeTrue -Because $Code
        $reason.Text | Should -Not -Match '\bTPM\b'
        $reason.Text | Should -Not -Match 'This could not be completed'
    }
}
