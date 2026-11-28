#Requires -Module Pester

# FIX80: screen readability, wave 2 (audit items 2, 3, 14, 16, 17).
#
#  2.  Registration recap and the last "Next" screen: a short result, items that need attention only when there are
#      some, everything else under Details and in the log.
#  3.  The optional ReShade / dgVoodoo2 / graphics card questions: one line each, D says what the step is.
#  14. Create Support Package: one plain opening sentence, the TeknoParrotUI step under D, a short result.
#  16. LaunchBox step after registration: four short choices, the same preview is never printed twice, only the
#      NAME of a backup folder in the default view.
#  17. The first-run migration question: three plain sentences, the list of moves under D.
#
# The production script is parsed and only its function definitions are dot-sourced. Every file lives under
# TestDrive. Each It names the product mutation that makes it fail.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($productionPath)
    $tokens = $null
    $parseErrors = $null
    $script:F80Ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX80 tests could not parse the production script.' }
    $definitions = @($script:F80Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $functionFile = Join-Path $TestDrive 'tpm-fix80-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, (@($definitions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"), (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')

    $script:F80RecapArgs = @{
        AutoSyncRan = $true; ZipsExtracted = 7; NewlyRegistered = 3; AlreadyPresent = 10; DatAction = 'Reused'
        ThumbnailsRequested = $true; ThumbnailsDownloaded = 2; BackupPath = 'C:\Backups\Run1'; LogPath = 'C:\Logs\TeknoParrot-Manager.log'
        ControlsStatusPath = 'C:\Reports\controls.txt'
    }

    function Install-F80Mocks {
        param([int]$Width = 120, [string[]]$Answers = @(), [bool]$Interactive = $false)
        $script:F80Screen = New-Object System.Collections.Generic.List[object]
        $script:F80Log = New-Object System.Collections.Generic.List[string]
        $script:F80Prompts = New-Object System.Collections.Generic.List[string]
        $script:F80Defaults = New-Object System.Collections.Generic.List[string]
        $script:F80Answers = New-Object 'System.Collections.Generic.Queue[string]'
        $script:F80Width = $Width
        $script:F80Interactive = $Interactive
        foreach ($answer in $Answers) { [void]$script:F80Answers.Enqueue($answer) }
        Mock Write-Host { [void]$script:F80Screen.Add([pscustomobject]@{ Text = [string]($Object -join ' '); Color = [string]$ForegroundColor }) }
        Mock Write-Log { [void]$script:F80Log.Add([string]$msg) }
        Mock Get-ConsoleContentWidth { return [int]$script:F80Width }
        Mock Test-TpmInteractiveInput { return ([bool]$script:F80Interactive -and -not [bool]$Unattended) }
        Mock Read-HostSafe {
            [void]$script:F80Prompts.Add([string]$Prompt)
            [void]$script:F80Defaults.Add([string]$Default)
            if ($script:F80Answers.Count -eq 0) { throw ("UNEXPECTED PROMPT '{0}'" -f $Prompt) }
            return $script:F80Answers.Dequeue()
        }
    }

    function Get-F80Lines { return @($script:F80Screen | ForEach-Object { $_.Text }) }

    # The whole screen as one line of text with single spaces, so a sentence that wrapped still matches.
    function Get-F80Flat { return ((@(Get-F80Lines) -join ' ') -replace '\s+', ' ') }

    # The longest stretch of lines with text and no blank line between them.
    function Get-F80MaxRun {
        param([string[]]$Lines)
        $max = 0
        $run = 0
        foreach ($line in $Lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { $run = 0 } else { $run++; if ($run -gt $max) { $max = $run } }
        }
        return $max
    }

    function Get-F80BlockText {
        param([object[]]$Blocks)
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($block in $Blocks) { [void]$lines.Add([string]$block.Heading); foreach ($line in @($block.Lines)) { [void]$lines.Add([string]$line) } }
        return ((@($lines) -join ' ') -replace '\s+', ' ')
    }

    # What the main flow does with the recap: build it, then print it through the shared result writer.
    function Show-F80Recap {
        param([hashtable]$RecapArguments)
        $recap = Get-TpmRegistrationRecap @RecapArguments
        Write-TpmOutcome -Title $recap.Title -Status $recap.Status -Done $recap.Done -Needs $recap.Needs -DetailBlocks $recap.DetailBlocks -Unattended:(-not $script:F80Interactive)
        return $recap
    }

    function Get-F80Calls {
        param([string]$Name, [switch]$AnyScope)
        return @($script:F80Ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq $Name
        }, $true) | Where-Object {
            if ($AnyScope) { return $true }
            $parent = $_.Parent
            while ($null -ne $parent -and $parent -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $parent = $parent.Parent }
            $null -eq $parent
        })
    }

    function Get-F80NamedArgument {
        param($Command, [string]$Name)
        $elements = @($Command.CommandElements)
        for ($i = 0; $i -lt $elements.Count; $i++) {
            if ($elements[$i] -is [System.Management.Automation.Language.CommandParameterAst] -and $elements[$i].ParameterName -eq $Name) {
                if ($null -ne $elements[$i].Argument) { return $elements[$i].Argument.Extent.Text }
                if ($i + 1 -lt $elements.Count) { return $elements[$i + 1].Extent.Text }
            }
        }
        return $null
    }

    function New-F80LaunchBoxResult {
        param([string]$Outcome = 'NO_CHANGES', [string]$Summary = 'Preview only, nothing was written.')
        return (New-TpmLaunchBoxResult -Outcome $Outcome -Summary $Summary)
    }
}

Describe 'FIX80 registration recap (audit item 2)' {
    It 'titles the result with the right singular and plural: <Count> new games' -TestCases @(
        @{ Count = 0; Expected = 'No new games were registered.' },
        @{ Count = 1; Expected = 'Registered 1 game.' },
        @{ Count = 3; Expected = 'Registered 3 games.' }
    ) {
        param($Count, $Expected)
        # Mutation: always use the plural, or print "game(s)" -> the 1 game title is wrong.
        $recapArguments = $script:F80RecapArgs.Clone()
        $recapArguments.NewlyRegistered = $Count
        (Get-TpmRegistrationRecap @recapArguments).Title | Should -BeExactly $Expected
    }

    It 'keeps the default view to a title and three short facts, with no paths, counters or disclaimers' {
        # Mutation: print the old recap paragraphs, the Backup/Log lines or the scope disclaimer in the default view.
        Install-F80Mocks
        [void](Show-F80Recap -RecapArguments $script:F80RecapArgs)
        $lines = @(Get-F80Lines)
        $lines | Should -Contain '  Registered 3 games.'
        $lines | Should -Contain '    - 7 ZIP files unpacked.'
        $lines | Should -Contain '    - 10 games were already set up.'
        $lines | Should -Contain '    - A saved copy was made first.'
        $text = Get-F80Flat
        $text | Should -Not -Match 'C:\\'
        $text | Should -Not -Match 'DAT|verify|organizes|\bTPM\b|ACTION REQUIRED|Needs your attention'
        $script:F80Prompts.Count | Should -Be 0
    }

    It 'shows every old fact under Details when D is pressed' {
        # Mutation: drop the Good to know block, the DAT line or the paths from the Details view.
        Install-F80Mocks -Interactive $true -Answers @('D')
        [void](Show-F80Recap -RecapArguments $script:F80RecapArgs)
        $script:F80Prompts.Count | Should -Be 1
        $text = Get-F80Flat
        foreach ($fact in @(
            'What TeknoParrot Manager did', 'Unpacked: 7 ZIP files from your source folder into the staging folder.',
            'Registered: 3 games read back after saving.', 'Already set up: 10 existing game file(s) found.',
            "Reused an already-present Eggman's TeknoParrot DAT file", 'Downloaded missing game icons (small box-art images, not game data).',
            'It does not provide games, install TeknoParrot itself, or guarantee that a game will boot or run fullscreen.',
            'usually a TeknoParrot, game, or runtime setting', 'This recap does not verify later optional steps',
            'Saved copy: C:\Backups\Run1', 'Log: C:\Logs\TeknoParrot-Manager.log', 'Controls file: C:\Reports\controls.txt'
        )) { $text | Should -Match ([regex]::Escape($fact)) }
    }

    It 'writes the whole recap to the log even when Details is never opened' {
        # Mutation: skip the log lines (call a plain writer instead of Write-TpmOutcome).
        Install-F80Mocks
        [void](Show-F80Recap -RecapArguments $script:F80RecapArgs)
        $script:F80Log | Should -Contain 'Result [Ok]: Registered 3 games.'
        $script:F80Log | Should -Contain 'Result detail [What TeknoParrot Manager did]: Registered: 3 games read back after saving.'
        $script:F80Log | Should -Contain 'Result detail [Where things are saved]: Log: C:\Logs\TeknoParrot-Manager.log'
    }

    It 'says each Game list (DAT) action in plain words under Details: <Action>' -TestCases @(
        @{ Action = 'Downloaded'; Expected = "Downloaded Eggman's TeknoParrot DAT file (an index used to match games -- not a game download)." },
        @{ Action = 'Updated'; Expected = "Updated Eggman's TeknoParrot DAT file to the latest release." },
        @{ Action = 'Reused'; Expected = "Reused an already-present Eggman's TeknoParrot DAT file (no download this run)." },
        @{ Action = 'NotConfigured'; Expected = "No Eggman's TeknoParrot DAT file configured -- some games may need manual registration." }
    ) {
        param($Action, $Expected)
        # Mutation: map two actions to the same sentence.
        $recapArguments = $script:F80RecapArgs.Clone()
        $recapArguments.DatAction = $Action
        $recap = Get-TpmRegistrationRecap @recapArguments
        (Get-F80BlockText -Blocks $recap.DetailBlocks) | Should -Match ([regex]::Escape('Game list (DAT): ' + $Expected))
    }

    It 'says whether game pictures were downloaded under Details, not in the default view' {
        # Mutation: put the picture sentence back into the Done list.
        $recapArguments = $script:F80RecapArgs.Clone()
        $recapArguments.ThumbnailsRequested = $false
        $recap = Get-TpmRegistrationRecap @recapArguments
        (Get-F80BlockText -Blocks $recap.DetailBlocks) | Should -Match 'Game pictures: Skipped game icon download\.'
        (@($recap.Done) -join ' ') | Should -Not -Match 'icon|picture'
    }

    It 'does not say game pictures were downloaded when the download failed' {
        $recapArguments = $script:F80RecapArgs.Clone()
        $recapArguments.ThumbnailsRequested = $true
        $recapArguments.ThumbnailsFailed = $true
        $recap = Get-TpmRegistrationRecap @recapArguments
        $text = Get-F80BlockText -Blocks $recap.DetailBlocks
        $text | Should -Match 'Game pictures: Some game icons could not be downloaded\.'
        $text | Should -Not -Match 'Downloaded missing game icons'
    }

    It 'prints Needs your attention only when something needs it, with the right plural' -TestCases @(
        @{ Manual = 2; Unmatched = 3; Controls = 1; Lines = @('    - 2 games need to be added by hand in TeknoParrotUI.', '    - 3 game folders were not recognized by TeknoParrot.', '    - 1 game still needs its controls set up.') },
        @{ Manual = 1; Unmatched = 1; Controls = 2; Lines = @('    - 1 game needs to be added by hand in TeknoParrotUI.', '    - 1 game folder was not recognized by TeknoParrot.', '    - 2 games still need their controls set up.') }
    ) {
        param($Manual, $Unmatched, $Controls, $Lines)
        # Mutation: always print the heading, or use "game(s)" / "item(s)" -> the plural lines differ.
        Install-F80Mocks
        [void](Show-F80Recap -RecapArguments $script:F80RecapArgs)
        @(Get-F80Lines | Where-Object { $_ -like '*Needs your attention*' }).Count | Should -Be 0
        Install-F80Mocks
        $recapArguments = $script:F80RecapArgs.Clone()
        $recapArguments.ManualNeeded = $Manual
        $recapArguments.NotInTeknoParrot = $Unmatched
        $recapArguments.ControlsNeedAttention = $Controls
        $recap = Show-F80Recap -RecapArguments $recapArguments
        $recap.Status | Should -BeExactly 'Attention'
        $shown = @(Get-F80Lines)
        $headingIndex = [array]::IndexOf($shown, '  Needs your attention:')
        $headingIndex | Should -BeGreaterThan 0
        $shown[$headingIndex - 1] | Should -BeExactly ''
        foreach ($line in $Lines) { $shown | Should -Contain $line }
        (Get-F80Flat) | Should -Not -Match 'see ACTION REQUIRED below'
    }

    It 'turns a controls status file that could not be saved into an item that needs attention' {
        # Mutation: print the old yellow "Controls :" line outside the recap, or drop the item.
        $recapArguments = $script:F80RecapArgs.Clone()
        $recapArguments.ControlsStatusFailed = $true
        $recapArguments.ControlsStatusPath = ''
        $recap = Get-TpmRegistrationRecap @recapArguments
        $recap.Status | Should -BeExactly 'Attention'
        $recap.Needs | Should -Contain 'The controls status file could not be saved. The log has the reason.'
        @($recap.DetailBlocks | Where-Object { $_.Heading -eq 'Items that need attention' }).Count | Should -Be 0
        (Get-F80BlockText -Blocks $recap.DetailBlocks) | Should -Not -Match 'Controls file'
    }

    It 'describes a preview without a saved copy, a pictures line or a controls file' {
        # Mutation: use the registered wording in a preview, or list the saved copy of a run that wrote nothing.
        $recapArguments = $script:F80RecapArgs.Clone()
        $recapArguments.Preview = $true
        $recap = Get-TpmRegistrationRecap @recapArguments
        $recap.Title | Should -BeExactly 'Preview: 3 games would be registered.'
        (@($recap.Done) -join ' ') | Should -Not -Match 'saved copy'
        $detailText = Get-F80BlockText -Blocks $recap.DetailBlocks
        $detailText | Should -Match 'Would register: 3 games \(nothing was changed\)\.'
        $detailText | Should -Not -Match 'Game pictures|Saved copy|Controls file|read back after saving'
    }

    It 'stays short and inside the console at <Width> columns, with no six lines in a row' -TestCases @(
        @{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }
    ) {
        param($Width)
        # Mutation: print the old counts block and recap lines, or drop the blank line before the needs.
        foreach ($manual in @(0, 1)) {
            Install-F80Mocks -Width $Width
            $recapArguments = $script:F80RecapArgs.Clone()
            $recapArguments.ManualNeeded = $manual
            [void](Show-F80Recap -RecapArguments $recapArguments)
            $lines = @(Get-F80Lines)
            @($lines | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
            (Get-F80MaxRun -Lines $lines) | Should -BeLessThan 6
        }
    }
}

Describe 'FIX80 last screen: Next (audit item 2)' {
    It 'mentions ACTION REQUIRED only when that section has items' {
        # Mutation: always print "Work through the ACTION REQUIRED items above".
        $without = Get-TpmRegistrationNextSteps -HasActionRequired $false -ReShadeDone $false -DgVoodoo2Done $false
        $with = Get-TpmRegistrationNextSteps -HasActionRequired $true -ReShadeDone $false -DgVoodoo2Done $false
        $without.Next | Should -BeExactly 'Open TeknoParrotUI and check that your games appear. Then try one game.'
        $with.Next | Should -BeExactly 'Open TeknoParrotUI and check that your games appear. Then fix the items under ACTION REQUIRED above.'
        $withoutText = Get-F80BlockText -Blocks $without.DetailBlocks
        $withoutText | Should -Not -Match 'ACTION REQUIRED items'
        $withoutText | Should -Match 'Step 2: Test one game before trusting the rest\.'
        $withText = Get-F80BlockText -Blocks $with.DetailBlocks
        $withText | Should -Match 'Step 2: Work through the ACTION REQUIRED items above\.'
        $withText | Should -Match 'Step 3: Test one game before trusting the rest\.'
    }

    It 'keeps the ReShade and dgVoodoo2 hints under Details, and only when those steps ran' {
        # Mutation: always add the hints, or print them in the default view.
        $none = Get-TpmRegistrationNextSteps -HasActionRequired $false -ReShadeDone $false -DgVoodoo2Done $false
        @($none.DetailBlocks | ForEach-Object { $_.Heading }) | Should -Not -Contain 'ReShade'
        @($none.DetailBlocks | ForEach-Object { $_.Heading }) | Should -Not -Contain 'dgVoodoo2'
        $both = Get-TpmRegistrationNextSteps -HasActionRequired $false -ReShadeDone $true -DgVoodoo2Done $true -CrosshairsFolder 'C:\Tpm\Crosshairs\'
        $text = Get-F80BlockText -Blocks $both.DetailBlocks
        foreach ($fact in @(
            'Press the Home key to open the effects overlay.', 'Settings save automatically -- you only need to do this once per game.',
            'does not remove unowned ReShade hooks automatically', 'do not delete DLLs blindly',
            'The game executable is unchanged. Create a support package with the log.',
            'Custom crosshair images are in C:\Tpm\Crosshairs\', 'You can add your own PNG images to that folder at any time.',
            'Run mode 5 (Crosshair setup) to preview and deploy them to lightgun games.'
        )) { $text | Should -Match ([regex]::Escape($fact)) }
        $both.Next | Should -Not -Match 'Home|DLL|PNG'
    }

    It 'says under Details that the original ZIP files are never deleted and are still needed for a reset' {
        # Mutation: drop the block -> a user cannot tell what to do with the ZIP files after unpacking.
        $steps = Get-TpmRegistrationNextSteps -HasActionRequired $false -ReShadeDone $false -DgVoodoo2Done $false
        $text = Get-F80BlockText -Blocks @($steps.DetailBlocks | Where-Object { $_.Heading -eq 'Your game ZIP files' })
        $text | Should -Match 'never deletes them'
        $text | Should -Match 'needs the original ZIP'
        $text | Should -Match 'archive or delete the ZIP files yourself'
        $steps.Next | Should -Not -Match 'ZIP'
    }

    It 'prints one Next line and then asks only for Details, inside the console at <Width> columns' -TestCases @(
        @{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }
    ) {
        param($Width)
        # Mutation: print the four old steps and the tips in the default view.
        Install-F80Mocks -Width $Width -Interactive $true -Answers @('')
        $steps = Get-TpmRegistrationNextSteps -HasActionRequired $true -ReShadeDone $true -DgVoodoo2Done $true -CrosshairsFolder 'C:\Tpm\Crosshairs\'
        Write-TpmOutcome -Title '' -Next $steps.Next -DetailBlocks $steps.DetailBlocks
        $lines = @(Get-F80Lines)
        @($lines | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
        (Get-F80MaxRun -Lines $lines) | Should -BeLessThan 6
        (Get-F80Flat) | Should -Not -Match 'Step 1|Home key|PNG'
        $script:F80Prompts.Count | Should -Be 1
    }

    It 'is built from the new helpers in the main flow, after the controls status file is written' {
        # Mutation: call the recap before Write-ControlsStatus (the recap would not know whether it was saved) or keep the old summary function.
        $recapCalls = @(Get-F80Calls -Name 'Get-TpmRegistrationRecap')
        $recapCalls.Count | Should -Be 1
        $statusCalls = @(Get-F80Calls -Name 'Write-ControlsStatus')
        $statusCalls.Count | Should -Be 1
        $statusCalls[0].Extent.StartOffset | Should -BeLessThan $recapCalls[0].Extent.StartOffset
        @(Get-F80Calls -Name 'Get-TpmRegistrationNextSteps').Count | Should -Be 1
        @(Get-F80Calls -Name 'Get-WhatTpmDidSummaryLines').Count | Should -Be 0
        @($script:F80Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Get-WhatTpmDidSummaryLines' }, $true)).Count | Should -Be 0
    }
}

Describe 'FIX80 optional steps (audit item 3)' {
    It 'asks one short question for <Step> and nothing else by default' -TestCases @(
        @{ Step = 'ReShade'; Prompt = 'Optional: ReShade visuals. Set up now? (Y/N, D = what is this, default N)'; Default = 'N' },
        @{ Step = 'DgVoodoo2'; Prompt = 'Optional: dgVoodoo2 for old games. Set up now? (Y/N, D = what is this, default N)'; Default = 'N' },
        @{ Step = 'GpuFix'; Prompt = 'Optional: graphics card fixes. Apply now? (Y/N, D = what is this)'; Default = '' }
    ) {
        param($Step, $Prompt, $Default)
        # Mutation: print the old explanation page first, or change the default (the graphics card question has none).
        Install-F80Mocks -Answers @('N')
        (Read-TpmOptionalStepChoice -Step $Step -Default $Default) | Should -BeExactly 'N'
        $script:F80Prompts.Count | Should -Be 1
        $script:F80Prompts[0] | Should -BeExactly $Prompt
        $script:F80Defaults[0] | Should -BeExactly $Default
        @(Get-F80Lines | Where-Object { $_.Trim() }).Count | Should -Be 0
    }

    It 'shows what <Step> is when D is pressed, then asks again' -TestCases @(
        @{ Step = 'ReShade'; Fact = 'ReShade is a free tool that can make your arcade games look better on modern screens.' },
        @{ Step = 'DgVoodoo2'; Fact = 'dgVoodoo2 is a free compatibility layer that translates those old graphics calls into modern DirectX 11/12.' },
        @{ Step = 'GpuFix'; Fact = 'This step auto-detects your GPU and applies the right fix to every registered game that has one.' }
    ) {
        param($Step, $Fact)
        # Mutation: treat D as an invalid answer, or do not ask again after the help.
        Install-F80Mocks -Answers @('D', 'Y')
        (Read-TpmOptionalStepChoice -Step $Step -Default 'N') | Should -BeExactly 'Y'
        $script:F80Prompts.Count | Should -Be 2
        (Get-F80Flat) | Should -Match ([regex]::Escape($Fact))
    }

    It 'keeps every fact of the old <Step> panel under D' -TestCases @(
        @{ Step = 'ReShade'; Facts = @('Setup adds ReShade files (a DLL, ReShade.ini and effect files) to each game folder you choose.', 'Files already there are not replaced unless you approve it.', 'Sharpening: removes the blurry look of upscaled games', 'CRT scanlines: makes games look like an authentic arcade monitor', 'Color boost: makes older games more vivid and punchy', 'Borders: adds decorative bezel artwork around the game', 'ReShade is optional -- games do not need it to run.', 'It removes only the files TeknoParrot Manager added.', 'press Home to open the ReShade overlay', 'You can turn this on later from the main menu''s ReShade setup option, which can also download ReShade for you automatically.') },
        @{ Step = 'DgVoodoo2'; Facts = @('Some older arcade games use DirectX 8, DirectDraw, or the Glide API from 3dfx.', 'crashes, black screens, or missing graphics', 'it may also add or replace dgVoodoo.conf.', 'The game executable itself is not modified.', 'Only run this for games that crash or show black screens on first launch.', 'Games that run fine do not need it.', 'You can turn this on later from the main menu''s dgVoodoo2 setup option, which can also download dgVoodoo2 for you automatically.') },
        @{ Step = 'GpuFix'; Facts = @('Some games include settings that fix graphical issues specific to AMD, NVIDIA, or Intel graphics cards.', 'Safe to run any time -- re-run if you change or update your GPU.') }
    ) {
        param($Step, $Facts)
        # Mutation: drop a sentence of the old panel while moving it.
        $text = Get-F80BlockText -Blocks (Get-TpmOptionalStepHelpBlocks -Step $Step)
        foreach ($fact in $Facts) { $text | Should -Match ([regex]::Escape($fact)) }
    }

    It 'keeps the help of <Step> inside the console at <Width> columns' -TestCases @(
        @{ Step = 'ReShade'; Width = 40 }, @{ Step = 'ReShade'; Width = 60 }, @{ Step = 'ReShade'; Width = 120 },
        @{ Step = 'DgVoodoo2'; Width = 40 }, @{ Step = 'DgVoodoo2'; Width = 120 }, @{ Step = 'GpuFix'; Width = 40 }, @{ Step = 'GpuFix'; Width = 120 }
    ) {
        param($Step, $Width)
        # Mutation: write a help sentence with a fixed-width Write-Host instead of the wrapped writer.
        Install-F80Mocks -Width $Width
        Show-TpmDetailBlocks -Blocks (Get-TpmOptionalStepHelpBlocks -Step $Step)
        @(Get-F80Lines | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
    }

    It 'says which step is not offered when Crosshair setup did not finish: <Step>' -TestCases @(
        @{ Step = 'ReShade'; Name = 'ReShade visuals' }, @{ Step = 'DgVoodoo2'; Name = 'dgVoodoo2 for old games' }, @{ Step = 'GpuFix'; Name = 'graphics card fixes' }
    ) {
        param($Step, $Name)
        # Mutation: print the old context-free "Not offered because ..." sentence.
        Install-F80Mocks
        Write-TpmOptionalStepBlocked -Step $Step
        (Get-F80Flat) | Should -Match ([regex]::Escape(('Not offered: {0}. Crosshair setup did not finish. Fix that first.' -f $Name)))
    }

    It 'replaces the three full-page panels in the main flow with the one-line question' {
        # Mutation: bring back a Write-Host explanation before the question, or change a step's default.
        $calls = @(Get-F80Calls -Name 'Read-TpmOptionalStepChoice')
        $calls.Count | Should -Be 3
        @($calls | ForEach-Object { Get-F80NamedArgument -Command $_ -Name 'Step' }) | Should -Be @('ReShade', 'DgVoodoo2', 'GpuFix')
        @($calls | ForEach-Object { Get-F80NamedArgument -Command $_ -Name 'Default' }) | Should -Be @("'N'", "'N'", "''")
        @(Get-F80Calls -Name 'Write-TpmOptionalStepBlocked').Count | Should -Be 3
    }
}

Describe 'FIX80 game pictures question (audit item 2)' {
    It 'keeps the box-art explanation and the own-pictures tip under D' {
        # Mutation: drop the CustomThumbnails tip while moving it.
        $text = Get-F80BlockText -Blocks (Get-TpmThumbnailHelpBlocks)
        foreach ($fact in @('This downloads small box-art icons only, never the games themselves', 'Open this folder (make it if it is missing):', 'called the profile code', 'ending in .png instead of .xml', 'TeknoParrot-Manager-controls.txt lists every game''s file name.')) {
            $text | Should -Match ([regex]::Escape($fact))
        }
    }
}

Describe 'FIX80 Create Support Package (audit item 14)' {
    It 'opens with one plain sentence, keeps the menu keys and says nothing technical' {
        # Mutation: bring back the allowlisted-evidence / TeknoParrotUI intake paragraph before the menu.
        Install-F80Mocks
        Write-TpmSupportPackageIntro
        $lines = @(Get-F80Lines)
        @($lines | Where-Object { $_.Trim() })[0] | Should -BeExactly '  This makes one ZIP file that you can send to support.'
        $lines | Should -Contain '  1) Create Support Package'
        $lines | Should -Contain '  2) Open TeknoParrot Manager Logs and Reports'
        $lines | Should -Contain '  3) Return to the main menu'
        (Get-F80Flat) | Should -Not -Match 'allowlisted|ambient|intake|beside this script|\bTPM\b'
        (Get-F80Flat) | Should -Match 'Press D to see how'
    }

    It 'stays inside the console at <Width> columns, with no six lines in a row' -TestCases @(
        @{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }
    ) {
        param($Width)
        # Mutation: remove the blank line before the optional step.
        Install-F80Mocks -Width $Width
        Write-TpmSupportPackageIntro
        $lines = @(Get-F80Lines)
        @($lines | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
        (Get-F80MaxRun -Lines $lines) | Should -BeLessThan 6
    }

    It 'shows the TeknoParrotUI steps only after D, then asks again' {
        # Mutation: show the steps before the question, or return D as the choice.
        Install-F80Mocks -Answers @('D', '2')
        (Read-TpmSupportMenuChoice) | Should -BeExactly '2'
        $script:F80Prompts.Count | Should -Be 2
        $script:F80Prompts[0] | Should -BeExactly '  Choose 1-3, or D for the steps'
        $text = Get-F80Flat
        foreach ($fact in @('Troubleshooting', 'Save information to a text file', 'TeknoParrot-Manager-TeknoParrotUI-Troubleshooting.txt', 'Included: allowlisted current-run evidence plus labeled ambient diagnostics.', 'Never included: game files, credentials, or arbitrary folders.')) {
            $text | Should -Match ([regex]::Escape($fact))
        }
    }

    It 'accepts only 1, 2, 3 or D' {
        # Mutation: accept any answer.
        Install-F80Mocks -Answers @('x', '3')
        (Read-TpmSupportMenuChoice) | Should -BeExactly '3'
        @(Get-F80Lines | Where-Object { $_ -like '*Invalid choice*' }).Count | Should -Be 1
    }

    It 'says a created package in three short lines and keeps the full path under Details' {
        # Mutation: print the "Saved here: <full path>" line in the default view.
        Install-F80Mocks -Interactive $true -Answers @('D')
        Write-TpmSupportPackageResult -Result ([pscustomobject]@{ Succeeded = $true; PackagePath = 'C:\Tpm\SupportPackages\TeknoParrot-Support-1.zip'; Errors = @() })
        $lines = @(Get-F80Lines)
        $lines | Should -Contain '  Support package created.'
        $lines | Should -Contain '    - Saved as TeknoParrot-Support-1.zip.'
        $lines | Should -Contain '  Next: Send this ZIP to support. Tell them which game and step failed.'
        $shownBeforeDetails = @($lines | Select-Object -First ([array]::IndexOf($lines, '  Next: Send this ZIP to support. Tell them which game and step failed.') + 1))
        ($shownBeforeDetails -join ' ') | Should -Not -Match 'C:\\'
        (Get-F80Flat) | Should -Match ([regex]::Escape('Saved here: C:\Tpm\SupportPackages\TeknoParrot-Support-1.zip'))
    }

    It 'says the ZIP is ready when only a temporary folder could not be removed, and keeps the reason under Details' {
        # Mutation: tell the user not to send a complete, verified ZIP.
        Install-F80Mocks -Interactive $true -Answers @('D')
        Write-TpmSupportPackageResult -Result ([pscustomobject]@{ Succeeded = $false; PackagePath = 'C:\Tpm\SupportPackages\a.zip'; Errors = @('Could not delete the temporary folder.') })
        $lines = @(Get-F80Lines)
        $lines | Should -Contain '  The support ZIP is ready, but a temporary folder could not be removed.'
        $lines | Should -Contain '    - Saved as a.zip.'
        (Get-F80Flat) | Should -Not -Match 'Do not send'
        (Get-F80Flat) | Should -Match ([regex]::Escape('Reason: Could not delete the temporary folder.'))
        @($lines | Where-Object { $_ -like '*support package created*' }).Count | Should -Be 0
    }

    It 'says a package that was not created in plain words, with the reason only under Details' {
        # Mutation: print the raw error text in the default view.
        Install-F80Mocks -Interactive $false
        Write-TpmSupportPackageResult -Result ([pscustomobject]@{ Succeeded = $false; PackagePath = ''; Errors = @('Access to the path is denied.') }) -Unattended
        $lines = @(Get-F80Lines)
        $lines | Should -Contain '  The support package was not created.'
        $lines | Should -Contain '  Next: Check the TeknoParrot Manager log, then try again.'
        (Get-F80Flat) | Should -Not -Match 'Access to the path'
        $script:F80Log | Should -Contain 'Result detail [Support package]: Reason: Access to the path is denied.'
    }

    It 'keeps the support results inside the console at <Width> columns' -TestCases @(
        @{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }
    ) {
        param($Width)
        # Mutation: print a result line with Write-Host.
        foreach ($result in @(
            [pscustomobject]@{ Succeeded = $true; PackagePath = 'C:\Tpm\SupportPackages\TeknoParrot-Support-1.zip'; Errors = @() },
            [pscustomobject]@{ Succeeded = $false; PackagePath = 'C:\Tpm\SupportPackages\a.zip'; Errors = @('Could not delete the temporary folder.') },
            [pscustomobject]@{ Succeeded = $false; PackagePath = ''; Errors = @('Access denied.') }
        )) {
            Install-F80Mocks -Width $Width
            Write-TpmSupportPackageResult -Result $result -Unattended
            $lines = @(Get-F80Lines)
            @($lines | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
            (Get-F80MaxRun -Lines $lines) | Should -BeLessThan 6
        }
    }

    It 'no longer redraws the workflow footer after the support package' {
        # Mutation: restore the Render-TpmWorkflowStatus call that leaked the footer into the output.
        @(Get-F80Calls -Name 'Render-TpmWorkflowStatus').Count | Should -Be 0
        @(Get-F80Calls -Name 'Write-TpmSupportPackageResult').Count | Should -Be 1
    }
}

Describe 'FIX80 LaunchBox step (audit item 16)' {
    It 'offers short choices and keeps their keys' {
        # Mutation: bring back the long option sentences.
        Install-F80Mocks
        Write-TpmLaunchBoxOffer
        $lines = @(Get-F80Lines)
        $lines | Should -Contain '  TeknoParrot registration is finished.'
        foreach ($key in @('[P]', '[A]', '[G]', '[V]', '[S]', '[L]', '[F]', '[B]')) { @($lines | Where-Object { $_.StartsWith('  ' + $key + ' ') }).Count | Should -Be 1 }
        (Get-F80Flat) | Should -Not -Match 'verified backup before writing|no-write path|reference file'
    }

    It 'keeps the offer inside the console at <Width> columns, with no six lines in a row' -TestCases @(
        @{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }
    ) {
        param($Width)
        # Mutation: add a long sentence to an option.
        Install-F80Mocks -Width $Width
        Write-TpmLaunchBoxOffer
        $lines = @(Get-F80Lines)
        @($lines | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
        (Get-F80MaxRun -Lines $lines) | Should -BeLessThan 6
    }

    It 'keeps the race warning under D and the default notice to two sentences' {
        # Mutation: print the race sentence in the default notice.
        Install-F80Mocks
        Write-TpmLaunchBoxWriteNotice
        (Get-F80Flat) | Should -Match 'Close LaunchBox and BigBox first\. TeknoParrot Manager will not close them for you\. Only missing games are added\. Your own entries are kept\.'
        (Get-F80Flat) | Should -Not -Match 'race|atomic|reopen'
        $details = Get-F80BlockText -Blocks (Get-TpmLaunchBoxWriteNoticeBlocks)
        foreach ($fact in @('TeknoParrot Manager never force-closes either app.', 'An app can reopen after a process check. Multi-file saves are not atomic.', 'only missing entries are added.', 'A verified saved copy of your LaunchBox files is made before anything is written.')) {
            $details | Should -Match ([regex]::Escape($fact))
        }
    }

    It 'words a preview in plain words with the right plural: <Count> games' -TestCases @(
        @{ Count = 1; Expected = 'Preview: LaunchBox would get 1 game. Nothing was changed.' },
        @{ Count = 3; Expected = 'Preview: LaunchBox would get 3 games. Nothing was changed.' }
    ) {
        param($Count, $Expected)
        # Mutation: print the old "A write would add N game entries and change M file(s)" sentence.
        $result = New-F80LaunchBoxResult
        $result.Results = @{ TeknoParrot = $Count }
        $result.Reason = 'PREVIEW'
        $result | Add-Member -NotePropertyName WouldChangeFiles -NotePropertyValue 1 -Force
        (Get-TpmLaunchBoxPlainTitle -Result $result) | Should -BeExactly $Expected
    }

    It 'says LaunchBox already has everything when a preview has nothing to add' {
        # Mutation: show the technical summary instead.
        $result = New-F80LaunchBoxResult
        $result.Reason = 'PREVIEW'
        $result | Add-Member -NotePropertyName WouldChangeFiles -NotePropertyValue 0 -Force
        (Get-TpmLaunchBoxPlainTitle -Result $result) | Should -BeExactly 'Preview: LaunchBox already has all your games. Nothing would change.'
    }

    It 'shows only the name of the saved copy after a write, and the full path under Details' {
        # Mutation: print "Verified safety backup: <full path>" in the default view.
        Install-F80Mocks -Interactive $true -Answers @('D')
        $result = New-F80LaunchBoxResult -Outcome 'SAVED' -Summary 'LaunchBox files were saved and every target was read back and verified.'
        $result.Results = @{ Arcade = 2; TeknoParrot = 1 }
        $result.BackupPath = 'C:\LaunchBox\Backups\2026-11-03_10-00-57'
        $result | Add-Member -NotePropertyName SkippedMissingGame -NotePropertyValue 0 -Force
        Write-TpmLaunchBoxResult -Result $result
        $lines = @(Get-F80Lines)
        $lines | Should -Contain '  Added 3 games to LaunchBox.'
        $lines | Should -Contain '    - A saved copy of your LaunchBox files was made first: 2026-11-03_10-00-57'
        $detailsStart = [array]::IndexOf($lines, '  LaunchBox details')
        $detailsStart | Should -BeGreaterThan 0
        (@($lines | Select-Object -First $detailsStart) -join ' ') | Should -Not -Match 'C:\\'
        (Get-F80Flat) | Should -Match ([regex]::Escape('Verified safety backup: C:\LaunchBox\Backups\2026-11-03_10-00-57'))
        (Get-F80Flat) | Should -Match 'Added to Arcade: 2 games'
    }

    It 'names the folder for saved copies, not its path, when it is outside LaunchBox' {
        # Mutation: print the whole BackupLocationNote in the default view.
        Install-F80Mocks
        $result = New-F80LaunchBoxResult
        $result.Results = @{ TeknoParrot = 2 }
        $result.Reason = 'PREVIEW'
        $result | Add-Member -NotePropertyName WouldChangeFiles -NotePropertyValue 1 -Force
        $result | Add-Member -NotePropertyName BackupLocationNote -NotePropertyValue 'TeknoParrot''s own backup folder is inside this LaunchBox folder, so the safety backups for this library are kept outside it, in: C:\Users\Me\LaunchBoxBackups' -Force
        $result | Add-Member -NotePropertyName BackupLocationPath -NotePropertyValue 'C:\Users\Me\LaunchBoxBackups' -Force
        Write-TpmLaunchBoxResult -Result $result -Unattended
        (Get-F80Flat) | Should -Match 'Saved copies are kept outside LaunchBox, in the folder LaunchBoxBackups\.'
        (Get-F80Flat) | Should -Not -Match 'C:\\Users'
        $script:F80Log | Should -Contain 'Result detail [LaunchBox details]: Backup folder: TeknoParrot''s own backup folder is inside this LaunchBox folder, so the safety backups for this library are kept outside it, in: C:\Users\Me\LaunchBoxBackups'
    }

    It 'says how many games were left out because their game file is missing, with was and were' -TestCases @(
        @{ Skipped = 1; Expected = '1 game was not added because the game file was not found. This is not an error.' },
        @{ Skipped = 2; Expected = '2 games were not added because the game file was not found. This is not an error.' }
    ) {
        param($Skipped, $Expected)
        # Mutation: print "registered profile(s)" or the same verb for both.
        Install-F80Mocks
        $result = New-F80LaunchBoxResult
        $result.Reason = 'PREVIEW'
        $result | Add-Member -NotePropertyName WouldChangeFiles -NotePropertyValue 0 -Force
        $result | Add-Member -NotePropertyName SkippedMissingGame -NotePropertyValue $Skipped -Force
        Write-TpmLaunchBoxResult -Result $result -Unattended
        # The line wraps at 100 columns (the width cap), so the sentence is matched in the screen text with single spaces.
        (Get-F80Flat) | Should -Match ('Not changed: ' + [regex]::Escape($Expected))
    }

    It 'counts files that need a check and keeps their names under Details' {
        # Mutation: print "Needs review: <path>" in the default view.
        Install-F80Mocks -Interactive $true -Answers @('D')
        $result = New-F80LaunchBoxResult -Outcome 'PARTIAL' -Summary 'LaunchBox restore is PARTIAL.'
        $result.KeptFiles = @([pscustomobject]@{ Path = 'Data\Platforms\TeknoParrot.xml'; Reason = 'it changed after it was created' })
        $result.UnrecoveredPaths = @('Data\Platforms\TeknoParrot.xml')
        Write-TpmLaunchBoxResult -Result $result
        $lines = @(Get-F80Lines)
        $lines | Should -Contain '    - 1 LaunchBox file needs a check.'
        $detailsStart = [array]::IndexOf($lines, '  LaunchBox details')
        (@($lines | Select-Object -First $detailsStart) -join ' ') | Should -Not -Match 'TeknoParrot\.xml'
        (Get-F80Flat) | Should -Match ([regex]::Escape('Needs review: Data\Platforms\TeknoParrot.xml was left in place because it changed after it was created.'))
        (Get-F80Flat) | Should -Not -Match 'not verified back to its pre-write state'
    }

    It 'keeps the reason of a failed LaunchBox step under Details and writes one outcome line to the log' {
        # Mutation: print the exception text in the default view, or log the outcome twice.
        Install-F80Mocks -Interactive $false
        $result = New-F80LaunchBoxResult -Outcome 'FAILED' -Summary 'LaunchBox setup was refused before library writes.'
        $result.Errors = @('Close LaunchBox and BigBox before changing the library.')
        Write-TpmLaunchBoxResult -Result $result -Unattended
        $lines = @(Get-F80Lines)
        $lines | Should -Contain '  LaunchBox setup was refused before library writes.'
        $lines | Should -Contain '  Next: Press D to see what happened.'
        (Get-F80Flat) | Should -Not -Match 'Close LaunchBox and BigBox before'
        @($script:F80Log | Where-Object { $_ -like 'LaunchBox outcome=FAILED*' }).Count | Should -Be 1
        $script:F80Log | Should -Contain 'Result detail [LaunchBox details]: Reason: Close LaunchBox and BigBox before changing the library.'
    }

    It 'does not print the same preview twice' {
        # Mutation: always print the plan result, as the old flow did after [P] and again at [A].
        Install-F80Mocks
        $result = New-F80LaunchBoxResult -Summary 'Preview only, nothing was written. A write would add 3 game entries.'
        $result.Results = @{ TeknoParrot = 3 }
        $result.Reason = 'PREVIEW'
        $result | Add-Member -NotePropertyName WouldChangeFiles -NotePropertyValue 1 -Force
        Write-TpmLaunchBoxPlan -Result $result -AlreadyShownSummary $result.Summary
        $lines = @(Get-F80Lines)
        $lines | Should -Contain '  This is the same preview you just saw.'
        (Get-F80Flat) | Should -Not -Match 'would get'
        Install-F80Mocks
        Write-TpmLaunchBoxPlan -Result $result -AlreadyShownSummary 'A different preview' -Unattended
        (Get-F80Flat) | Should -Match 'Preview: LaunchBox would get 3 games\. Nothing was changed\.'
        (Get-F80Flat) | Should -Not -Match 'same preview'
    }

    It 'shows the plan when only the game names differ from the preview, and still hides an identical one' {
        # Mutation: compare only the summary text -> a plan with clean names is hidden as "the same preview" after official names were shown.
        Install-F80Mocks
        $summary = 'Preview only, nothing was written. A write would add 3 game entries.'
        $previewed = New-F80LaunchBoxResult -Summary $summary
        $previewed | Add-Member -NotePropertyName TitleChanges -NotePropertyValue @([pscustomobject]@{ Old = 'ghostsq'; New = 'Ghost Squad Evolution'; Id = '77'; Kind = 'New' }) -Force
        $plan = New-F80LaunchBoxResult -Summary $summary
        $plan.Results = @{ TeknoParrot = 3 }
        $plan.Reason = 'PREVIEW'
        $plan | Add-Member -NotePropertyName WouldChangeFiles -NotePropertyValue 1 -Force
        $plan | Add-Member -NotePropertyName TitleChanges -NotePropertyValue @([pscustomobject]@{ Old = 'ghostsq'; New = 'Ghostsq'; Id = ''; Kind = 'New' }) -Force
        Write-TpmLaunchBoxPlan -Result $plan -AlreadyShownSummary (Get-TpmLaunchBoxPlanSignature -Result $previewed) -Unattended
        (Get-F80Flat) | Should -Match 'would get 3 games'
        (Get-F80Flat) | Should -Not -Match 'same preview'
        Install-F80Mocks
        Write-TpmLaunchBoxPlan -Result $previewed -AlreadyShownSummary (Get-TpmLaunchBoxPlanSignature -Result $previewed) -Unattended
        (Get-F80Flat) | Should -Match 'same preview'
    }

    It 'keeps the preview screen inside the console at <Width> columns, with no six lines in a row' -TestCases @(
        @{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }
    ) {
        param($Width)
        # Mutation: print the backup note and the backup path as separate default lines.
        Install-F80Mocks -Width $Width
        $result = New-F80LaunchBoxResult
        $result.Results = @{ TeknoParrot = 3 }
        $result.Reason = 'PREVIEW'
        $result | Add-Member -NotePropertyName WouldChangeFiles -NotePropertyValue 1 -Force
        $result | Add-Member -NotePropertyName BackupLocationNote -NotePropertyValue 'The backups are kept outside it, in: C:\Users\Me\LaunchBoxBackups' -Force
        $result | Add-Member -NotePropertyName BackupLocationPath -NotePropertyValue 'C:\Users\Me\LaunchBoxBackups' -Force
        Write-TpmLaunchBoxResult -Result $result -Unattended
        $lines = @(Get-F80Lines)
        @($lines | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
        (Get-F80MaxRun -Lines $lines) | Should -BeLessThan 6
    }

    It 'passes the previewed summary to the plan in the main flow and keeps the exact consent question' {
        # Mutation: call Write-TpmLaunchBoxResult for the plan again.
        # The LaunchBox step is its own function now, so look inside Invoke-TpmLaunchBoxStep. The summary of the
        # preview that was shown reaches the plan through $lbShownBefore, and is cleared when the plan has official
        # game names (the plan then differs from the preview).
        $stepAst = @($script:F80Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Invoke-TpmLaunchBoxStep' }, $true))[0]
        $stepCalls = @($stepAst.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true))
        $planCalls = @($stepCalls | Where-Object { $_.GetCommandName() -eq 'Write-TpmLaunchBoxPlan' })
        $planCalls.Count | Should -Be 1
        Get-F80NamedArgument -Command $planCalls[0] -Name 'AlreadyShownSummary' | Should -BeExactly '$lbShownBefore'
        $stepAst.Extent.Text | Should -Match ([regex]::Escape('$lbShownBefore = $lbPreviewShownSummary'))
        @($stepCalls | Where-Object { $_.GetCommandName() -eq 'Read-TpmYesNo' -and (Get-F80NamedArgument -Command $_ -Name 'Prompt') -eq "'Write exactly these changes after a verified backup? (Y/N, D = about the risks)'" }).Count | Should -Be 1
    }
}

Describe 'FIX80 migration question (audit item 17)' {
    BeforeAll {
        $script:F80Layout = [pscustomobject]@{ Root = 'C:\Tpm\TeknoParrot\TeknoParrotManager' }
        $script:F80Destinations = @(
            [pscustomobject]@{ Item = [pscustomobject]@{ Name = 'TeknoParrot-Manager.config.json' }; Bucket = 'State'; Destination = 'C:\Tpm\TeknoParrot\TeknoParrotManager\State\TeknoParrot-Manager.config.json' },
            [pscustomobject]@{ Item = [pscustomobject]@{ Name = 'TeknoParrot-Manager.log' }; Bucket = 'Logs'; Destination = 'C:\Tpm\TeknoParrot\TeknoParrotManager\Logs\TeknoParrot-Manager.log' },
            [pscustomobject]@{ Item = [pscustomobject]@{ Name = 'CustomThumbnails' }; Bucket = 'Assets'; Destination = 'C:\Tpm\TeknoParrot\TeknoParrotManager\Assets\CustomThumbnails' }
        )
    }

    It 'asks in three plain sentences and shows no path' {
        # Mutation: print the category list, the destination root or the report path again.
        Install-F80Mocks
        Write-TpmOwnedMigrationOffer -Layout $script:F80Layout -Destinations $script:F80Destinations -ReportPath 'C:\Tpm\Reports\TPM-migration-1.md'
        $lines = @(Get-F80Lines)
        $lines | Should -Contain '  TeknoParrot Manager can tidy its own files into one folder.'
        $lines | Should -Contain '  Your games and TeknoParrot files are not touched.'
        $lines | Should -Contain '  If you say N, nothing changes. It will ask again next time.'
        @($lines | Where-Object { $_.Trim() }).Count | Should -Be 3
        (Get-F80Flat) | Should -Not -Match 'C:\\|->|Destination root|Not moved|State:|Logs:'
    }

    It 'writes the whole plan to the log' {
        # Mutation: drop the log lines (the list is then only reachable through D).
        Install-F80Mocks
        Write-TpmOwnedMigrationOffer -Layout $script:F80Layout -Destinations $script:F80Destinations -ReportPath 'C:\Tpm\Reports\TPM-migration-1.md'
        $script:F80Log | Should -Contain 'Owned-state migration plan: TeknoParrot-Manager.log -> C:\Tpm\TeknoParrot\TeknoParrotManager\Logs\TeknoParrot-Manager.log (Logs)'
        $script:F80Log | Should -Contain 'Owned-state migration plan: destination root C:\Tpm\TeknoParrot\TeknoParrotManager; details report C:\Tpm\Reports\TPM-migration-1.md'
        @($script:F80Log | Where-Object { $_ -like 'Owned-state migration plan: *' }).Count | Should -Be 4
    }

    It 'keeps the offer inside the console at <Width> columns, with no six lines in a row' -TestCases @(
        @{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }
    ) {
        param($Width)
        # Mutation: add a long sentence.
        Install-F80Mocks -Width $Width
        Write-TpmOwnedMigrationOffer -Layout $script:F80Layout -Destinations $script:F80Destinations -ReportPath 'C:\Tpm\Reports\TPM-migration-1.md'
        $lines = @(Get-F80Lines)
        @($lines | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
        (Get-F80MaxRun -Lines $lines) | Should -BeLessThan 6
    }

    It 'keeps every old fact in the Details view: one block per item, in the old category order' {
        # Mutation: drop a destination, the Not moved sentence or the report path.
        $blocks = Get-TpmOwnedMigrationDetailBlocks -Layout $script:F80Layout -Destinations $script:F80Destinations -ReportPath 'C:\Tpm\Reports\TPM-migration-1.md'
        @($blocks | ForEach-Object { $_.Heading }) | Should -Be @('Where the files go', 'TeknoParrot-Manager.config.json', 'TeknoParrot-Manager.log', 'CustomThumbnails')
        $general = @($blocks[0].Lines)
        $general | Should -Contain 'Folder: C:\Tpm\TeknoParrot\TeknoParrotManager'
        $general | Should -Contain 'Not moved: games, ROM ZIP sources, TeknoParrot installation files, LaunchBox data, and other frontend data. Everything inside the old SupportPackages folder is moved with it.'
        $general | Should -Contain 'If you choose N: nothing is moved. TeknoParrot Manager starts normally and asks again next time.'
        $general | Should -Contain 'Report, saved only if you choose Y: C:\Tpm\Reports\TPM-migration-1.md'
        @($blocks[2].Lines) | Should -Be @('Group: Logs', 'Goes to: C:\Tpm\TeknoParrot\TeknoParrotManager\Logs\TeknoParrot-Manager.log')
    }

    It 'shows the list when D is pressed, asks again, and moves nothing on N' {
        # Mutation: treat D as N (the list is never shown) or as Y (files are moved without an answer).
        $root = Join-Path $TestDrive 'fix80-migration-details'
        $scriptRoot = Join-Path $root 'program'
        $tpRoot = Join-Path $root 'TeknoParrot'
        New-Item -ItemType Directory -Path $scriptRoot, $tpRoot -Force | Out-Null
        $config = Join-Path $scriptRoot 'TeknoParrot-Manager.config.json'
        [System.IO.File]::WriteAllText($config, '{}')
        $layout = Initialize-TpmOwnedLayout -Layout (Get-TpmOwnedLayout -TeknoParrotRoot $tpRoot)
        Install-F80Mocks -Answers @('D', 'N')
        Mock Write-TpmCompactExtractionProgress {}
        $result = Invoke-TpmOwnedMigration -ScriptRoot $scriptRoot -Layout $layout
        $result.ReasonCode | Should -BeExactly 'DECLINED'
        [System.IO.File]::ReadAllText($config) | Should -BeExactly '{}'
        $script:F80Prompts.Count | Should -Be 2
        $script:F80Prompts[0] | Should -BeExactly 'Tidy up now? (Y/N, D = show the list)'
        $script:F80Prompts[1] | Should -BeExactly 'Tidy up now? (Y/N, D = show the list)'
        $script:F80Defaults[0] | Should -BeExactly 'N'
        (Get-F80Flat) | Should -Match 'Goes to:'
        (Get-F80Flat) | Should -Match 'TeknoParrot-Manager\.config\.json'
    }
}

Describe 'FIX80 wording rules for everything new' {
    It 'never says TPM in a visible sentence' {
        # Mutation: write "TPM" in any new default or Details text.
        $texts = New-Object System.Collections.Generic.List[string]
        $recapArguments = $script:F80RecapArgs.Clone()
        $recap = Get-TpmRegistrationRecap @recapArguments
        [void]$texts.Add($recap.Title)
        [void]$texts.Add((@($recap.Done) -join ' '))
        [void]$texts.Add((Get-F80BlockText -Blocks $recap.DetailBlocks))
        $steps = Get-TpmRegistrationNextSteps -HasActionRequired $true -ReShadeDone $true -DgVoodoo2Done $true -CrosshairsFolder 'C:\X\'
        [void]$texts.Add($steps.Next)
        [void]$texts.Add((Get-F80BlockText -Blocks $steps.DetailBlocks))
        foreach ($step in @('ReShade', 'DgVoodoo2', 'GpuFix')) { [void]$texts.Add((Get-F80BlockText -Blocks (Get-TpmOptionalStepHelpBlocks -Step $step))) }
        [void]$texts.Add((Get-F80BlockText -Blocks (Get-TpmThumbnailHelpBlocks)))
        [void]$texts.Add((Get-F80BlockText -Blocks (Get-TpmSupportPackageHelpBlocks)))
        [void]$texts.Add((Get-F80BlockText -Blocks (Get-TpmLaunchBoxWriteNoticeBlocks)))
        [void]$texts.Add((Get-F80BlockText -Blocks (Get-TpmOwnedMigrationDetailBlocks -Layout ([pscustomobject]@{ Root = 'C:\X' }) -Destinations @() -ReportPath 'C:\X\r.md')))
        # The thumbnail help names a folder under the test's own TestDrive; that path is not product wording, and the
        # temp folder of the PC running the tests may itself contain "TPM".
        foreach ($text in $texts) { $text.Replace([string]$TestDrive, '<TestDrive>') | Should -Not -Match '\bTPM\b' }
    }
}
