#Requires -Module Pester

# FIX81: screen readability, wave 2.
#
#  Item 4  Required game patches: the game list is one row per game ("Hummer (14 patches)"), not one row per recipe id.
#  Item 5  Required game patches: results are grouped, in plain words; "No patch was applied... fix it" only for a real
#          failure; the receipt folder, recipe ids, reason text and result codes are behind the D key and in the log.
#  Item 6  Propagate Controls: one question, one short result; the technical rows are behind D and in the log.
#  Item 7  Custom rules notice at start-up: one line, no question (FIX90); the details are in the log.
#
# The production script is parsed and only its function definitions are dot-sourced (plus the required-patch engine).
# Every file lives under TestDrive. Each It names the product mutation that makes it fail.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($productionPath)
    $tokens = $null
    $parseErrors = $null
    $script:F81Ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX81 tests could not parse the production script.' }
    $definitions = @($script:F81Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $functionFile = Join-Path $TestDrive 'tpm-fix81-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, (@($definitions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"), (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    . (Join-Path $PSScriptRoot '..\scripts\TpmRequiredPatchEngine.ps1')
    # Get-ConfigCarryFlags reads this top-level table of the production script.
    $carryAssignment = @($script:F81Ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -eq '$ConfigCarryWarnings' })
    if ($carryAssignment.Count -ne 1) { throw 'Expected one production ConfigCarryWarnings assignment.' }
    . ([scriptblock]::Create($carryAssignment[0].Extent.Text))
    $script:F81EnginePath = (Resolve-Path (Join-Path $PSScriptRoot '..\scripts\TpmRequiredPatchEngine.ps1')).Path
    $script:F81RecipesPath = (Resolve-Path (Join-Path $PSScriptRoot '..\scripts\TpmRequiredPatchRecipes.json')).Path

    function Install-F81Mocks {
        param([int]$Width = 80, [string[]]$Answers = @(), [bool]$Interactive = $true)
        $script:F81Screen = New-Object System.Collections.Generic.List[object]
        $script:F81Log = New-Object System.Collections.Generic.List[string]
        $script:F81Prompts = New-Object System.Collections.Generic.List[string]
        $script:F81Answers = New-Object 'System.Collections.Generic.Queue[string]'
        $script:F81Width = $Width
        $script:F81Interactive = $Interactive
        foreach ($answer in $Answers) { [void]$script:F81Answers.Enqueue($answer) }
        Mock Write-Host { [void]$script:F81Screen.Add([pscustomobject]@{ Text = [string]($Object -join ' '); Color = [string]$ForegroundColor }) }
        Mock Write-Log { [void]$script:F81Log.Add([string]$msg) }
        Mock Get-ConsoleContentWidth { return [int]$script:F81Width }
        Mock Test-TpmInteractiveInput { if ($Unattended) { return $false }; return [bool]$script:F81Interactive }
        Mock Read-HostSafe {
            [void]$script:F81Prompts.Add([string]$Prompt)
            if ($script:F81Answers.Count -eq 0) { throw ("UNEXPECTED PROMPT '{0}'" -f $Prompt) }
            return $script:F81Answers.Dequeue()
        }
    }

    function Get-F81Lines { return @($script:F81Screen | ForEach-Object { $_.Text }) }

    # The screen as one text with every run of spaces and line breaks collapsed, so a wrapped sentence can be matched.
    function Get-F81Flat { return ((@(Get-F81Lines) -join ' ') -replace '\s+', ' ') }

    # The screen as paragraphs: the lines between blank lines, trimmed and joined with one space.
    function Get-F81Paragraphs {
        $paragraphs = New-Object System.Collections.Generic.List[string]
        $current = New-Object System.Collections.Generic.List[string]
        foreach ($line in @(Get-F81Lines)) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                if ($current.Count -gt 0) { [void]$paragraphs.Add(($current.ToArray() -join ' ')); $current.Clear() }
            } else { [void]$current.Add($line.Trim()) }
        }
        if ($current.Count -gt 0) { [void]$paragraphs.Add(($current.ToArray() -join ' ')) }
        return $paragraphs.ToArray()
    }

    # The longest run of text lines with no blank line between them.
    function Get-F81MaxRun {
        param([string[]]$Lines)
        $max = 0
        $run = 0
        foreach ($line in @($Lines)) {
            if ([string]::IsNullOrWhiteSpace($line)) { $run = 0 } else { $run++; if ($run -gt $max) { $max = $run } }
        }
        return $max
    }

    function New-F81Entry {
        param([string]$Id, [string]$Build, [string]$Hash = ('A' * 64), [string]$Zip = 'Pack.zip')
        return [pscustomobject]@{ Id = $Id; ProfileId = ($Build -replace '\W.*$', ''); BuildName = $Build; Executable = 'game.exe'; ExecutableSha256 = $Hash; SourceSet = $Zip }
    }

    function New-F81Results {
        param([object[]]$Specs)
        $list = New-Object 'System.Collections.Generic.List[object]'
        foreach ($spec in @($Specs)) {
            Add-TpmRequiredPatchResult -Results $list -Entry $spec.Entry -Status $spec.Status -Reason ([string]$spec.Reason) -Receipt ([string]$spec.Receipt) -Registered ($spec.Registered -ne $false)
        }
        return $list.ToArray()
    }

    function New-F81Source {
        param([string]$Code, [string]$Family = 'driving', [string]$Api = 'RawInput', [string[]]$Devices = @('ArchPad Btn'), [hashtable]$Carry = @{})
        return [pscustomobject]@{ Code = $Code; Family = $Family; InputApi = $Api; Devices = @($Devices); ConfigCarry = $Carry; BoundCount = 12 }
    }

    $script:F81HummerBuild = 'Hummer Extreme Edition (1.0)(2009-10-05)[Sega Lindbergh Yellow][TP]'
    $script:F81HummerEntries = @(1..14 | ForEach-Object { New-F81Entry -Id ('hummerextreme-main-component-data-global-shader-gauss2-part{0:D2}' -f $_) -Build $script:F81HummerBuild })
    $script:F81Mario = New-F81Entry -Id 'mario-kart-gp-dx-plugin' -Build 'Mario Kart Arcade GP DX (1.06.35-OF)(2022-08-01)(USA)[Namco ES3A][TP]'
    $script:F81Alpha = New-F81Entry -Id 'alpha-main-one' -Build 'Alpha Game (1.0)[TP]'
    $script:F81Alpha2 = New-F81Entry -Id 'alpha-main-two' -Build 'Alpha Game (1.0)[TP]'
    $script:F81Beta = New-F81Entry -Id 'beta-main-one' -Build 'Beta Game (2.0)[TP]'
}

Describe 'FIX81 required patches: the game list (item 4)' {
    It 'groups the shipped recipes into one group per exact game build' {
        # Mutation: group by recipe id instead of build name -> as many groups as recipes, and no group of 14.
        $entries = @((Get-Content -LiteralPath $script:F81RecipesPath -Raw -Encoding UTF8 | ConvertFrom-Json).Entries)
        $groups = @(Get-TpmRequiredPatchGameGroups -Entries $entries)
        $groups.Count | Should -BeLessThan $entries.Count
        (($groups | Measure-Object -Property Count -Sum).Sum) | Should -Be $entries.Count
        @($groups | ForEach-Object { $_.Name } | Select-Object -Unique).Count | Should -Be $groups.Count
        @($groups | Where-Object { $_.Name -match '[\(\[]' -or $_.Name -match '\d{4}-\d{2}-\d{2}' }).Count | Should -Be 0
        $hummer = @($groups | Where-Object { $_.Name -ceq 'Hummer' })
        $hummer.Count | Should -Be 1
        $hummer[0].Count | Should -Be 14
    }

    It 'shows one row per game with its patch count and no recipe id at <Width> columns' -TestCases @(
        @{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }
    ) {
        param($Width)
        # Mutation: print one row per recipe ("Id -- Build") -> the ids show and the Beta row is number 4.
        Install-F81Mocks -Width $Width
        $groups = @(Get-TpmRequiredPatchGameGroups -Entries @($script:F81Alpha, $script:F81Alpha2, $script:F81Alpha, $script:F81Beta))
        Show-TpmRequiredPatchGameList -Groups $groups
        $lines = @(Get-F81Lines)
        $lines | Should -Contain '  1) Alpha Game (3 patches)'
        $lines | Should -Contain '  2) Beta Game (1 patch)'
        (($lines -join ' ') -match 'alpha-main|beta-main|--') | Should -BeFalse
        @($lines | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
    }

    It 'tells builds with the same short name apart by only the part that differs, in plain words' {
        # Mutation: always show the short name -> two rows read "Same Game" and cannot be told apart.
        # Mutation: show the exact build name -> the rows carry brackets and the date.
        $one = New-F81Entry -Id 'same-one' -Build 'Same Game (1.0)(2019-01-01)(JPN)[Sega ALLS][TP]'
        $two = New-F81Entry -Id 'same-two' -Build 'Same Game (2.0)(2019-02-02)(JPN)[Sega ALLS][TP]'
        $groups = @(Get-TpmRequiredPatchGameGroups -Entries @($one, $two))
        $groups.Count | Should -Be 2
        $groups[0].Name | Should -BeExactly 'Same Game, version 1.0'
        $groups[1].Name | Should -BeExactly 'Same Game, version 2.0'
        $groups[0].BuildName | Should -BeExactly 'Same Game (1.0)(2019-01-01)(JPN)[Sega ALLS][TP]'
    }

    It 'names a different region or hardware when that is what differs, and numbers builds that differ only by date' {
        # Mutation: always add the version -> the region row is not told apart by region; drop the numbering -> two rows read the same.
        $jpn = New-F81Entry -Id 'r-jpn' -Build 'Region Game (1.0)(2019-01-01)(JPN)[Sega ALLS][TP]'
        $usa = New-F81Entry -Id 'r-usa' -Build 'Region Game (1.0)(2019-01-01)(USA)[Sega ALLS][TP]'
        $groups = @(Get-TpmRequiredPatchGameGroups -Entries @($jpn, $usa))
        $groups[0].Name | Should -BeExactly 'Region Game, JPN'
        $groups[1].Name | Should -BeExactly 'Region Game, USA'
        $early = New-F81Entry -Id 'd-early' -Build 'Date Game (1.0)(2019-01-01)[TP]'
        $late = New-F81Entry -Id 'd-late' -Build 'Date Game (1.0)(2019-06-01)[TP]'
        $groups = @(Get-TpmRequiredPatchGameGroups -Entries @($early, $late))
        $groups[0].Name | Should -BeExactly 'Date Game, build 1'
        $groups[1].Name | Should -BeExactly 'Date Game, build 2'
    }

    It 'gives every shipped recipe a unique name with no bracket, no date and no tag' {
        # Mutation: show the exact build name for colliding builds -> 25 names carry brackets, a date and [TP].
        $entries = @((Get-Content -LiteralPath $script:F81RecipesPath -Raw -Encoding UTF8 | ConvertFrom-Json).Entries)
        $entries.Count | Should -Be 120
        $groups = @(Get-TpmRequiredPatchGameGroups -Entries $entries)
        $nameOfBuild = @{}
        foreach ($group in $groups) { $nameOfBuild[$group.BuildName] = [string]$group.Name }
        $names = @($entries | ForEach-Object { $nameOfBuild[[string]$_.BuildName] })
        @($names | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count | Should -Be 0
        @($names | Where-Object { $_ -match '[\(\)\[\]]|\d{4}-\d{2}-\d{2}|\bTP\b' }).Count | Should -Be 0
        @($nameOfBuild.Values | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique).Count | Should -Be $groups.Count
        $nameOfBuild['Dead or Alive 6 (1.01.00)(2019-07-04)(JPN)[Sega ALLS][TP]'] | Should -BeExactly 'Dead or Alive 6, version 1.01.00'
    }

    It 'returns the chosen game, and D shows the exact version and the recipe ids first' {
        # Mutation: drop the details or the answer loop -> D is read as a bad number, and the ids and version never show.
        Install-F81Mocks -Answers @('D', '2')
        $groups = @(Get-TpmRequiredPatchGameGroups -Entries @($script:F81Alpha, $script:F81Alpha2, $script:F81Beta))
        $chosen = Read-TpmRequiredPatchGameChoice -Groups $groups
        $chosen.BuildName | Should -BeExactly 'Beta Game (2.0)[TP]'
        $script:F81Prompts.Count | Should -Be 2
        $text = (Get-F81Lines) -join "`n"
        $text | Should -Match 'Exact version:\s+Beta Game \(2\.0\)\[TP\]'
        $text | Should -Match 'Patch ids:\s+alpha-main-one, alpha-main-two'
    }

    It 'returns nothing and says nothing was changed for an answer that is not in the list' {
        # Mutation: index the list with the unchecked number -> 9 returns $null silently or throws, and x selects game 1.
        Install-F81Mocks -Answers @('9')
        $groups = @(Get-TpmRequiredPatchGameGroups -Entries @($script:F81Alpha, $script:F81Beta))
        $null -eq (Read-TpmRequiredPatchGameChoice -Groups $groups) | Should -BeTrue
        ((Get-F81Lines) -join "`n") | Should -Match 'That is not a number in the list\. Nothing was changed\.'
        Install-F81Mocks -Answers @('x')
        $null -eq (Read-TpmRequiredPatchGameChoice -Groups $groups) | Should -BeTrue
    }
}

Describe 'FIX81 required patches: plain reasons and grouped results (item 5)' {
    It 'puts <Expect> in plain words for: <Reason>' -TestCases @(
        @{ Status = 'BLOCKED'; Reason = 'The selected folder does not contain the exact required ZIP.'; Expect = 'ZIP file with this patch was not found' }
        @{ Status = 'BLOCKED'; Reason = 'The exact required ZIP member is absent, duplicated, or has a different size.'; Expect = 'inside the ZIP' }
        @{ Status = 'BLOCKED'; Reason = 'The installed executable is not in an exact supported before/after state.'; Expect = 'not the game version' }
        @{ Status = 'BLOCKED'; Reason = 'Executable revision mismatch.'; Expect = 'not the game version' }
        @{ Status = 'BLOCKED'; Reason = 'The exact recipe executable is not present in the selected game folder.'; Expect = 'game file was not found' }
        @{ Status = 'BLOCKED'; Reason = 'Target conflict.'; Expect = 'different from what the patch expects' }
        @{ Status = 'FAILED'; Reason = 'Close the game before applying or undoing its patch.'; Expect = 'The game is running' }
        @{ Status = 'BLOCKED'; Reason = 'BepInEx is not installed for this game. Use the existing BepInEx setup.'; Expect = 'BepInEx is not installed' }
        @{ Status = 'BLOCKED'; Reason = 'Run the game once so BepInEx creates BepInEx\config\BepInEx.cfg.'; Expect = 'one more setting' }
        @{ Status = 'BLOCKED'; Reason = 'Exactly one verified undo receipt is required; ambiguous or missing receipts block undo.'; Expect = 'saved copy for undo' }
        @{ Status = 'BLOCKED'; Reason = 'This exact game has no verified applied patch state to undo.'; Expect = 'no patch from TeknoParrot Manager to undo' }
        @{ Status = 'ACTION REQUIRED'; Reason = 'ACTION REQUIRED: interrupted grouped transaction C:\x\GamePatches\0123 cannot be reconciled with the live targets (the targets are neither all original nor all promoted); every receipt and backup was retained for manual recovery.'; Expect = 'earlier patch install stopped' }
        @{ Status = 'BLOCKED'; Reason = 'The selected game folder overlaps TeknoParrot Manager files.'; Expect = 'cannot be used safely' }
        @{ Status = 'BLOCKED'; Reason = 'No bundled variant applies to the established adapter.'; Expect = 'graphics card' }
        @{ Status = 'BLOCKED'; Reason = 'A different exclusive hardware variant applies: shining-force-cross-elysion-shader-nvidia'; Expect = 'different graphics card' }
        @{ Status = 'BLOCKED'; Reason = 'An exclusive recipe is active; undo it before selecting another variant.'; Expect = 'already installed\. Undo it first' }
        @{ Status = 'BLOCKED'; Reason = 'The registered profile changed or points to a different game executable.'; Expect = 'not set up in TeknoParrot' }
        @{ Status = 'CANCELLED'; Reason = 'No game folder was selected.'; Expect = 'did not choose a game folder' }
        @{ Status = 'CANCELLED'; Reason = 'Undo was not confirmed; no game files were changed.'; Expect = 'chose not to undo' }
        @{ Status = 'BLOCKED'; Reason = 'Something nobody planned for.'; Expect = 'Details have the reason' }
    ) {
        param($Status, $Reason, $Expect)
        # Mutation: remove or reorder the rule (or return the raw reason) -> the sentence is the raw text or the generic one.
        (Get-TpmRequiredPatchPlainReason -Status $Status -Reason $Reason) | Should -Match $Expect
    }

    It 'says nothing about a reason for a result that is not a problem' {
        # Mutation: give every status a reason sentence -> the installed and already-installed lines get a stray sentence.
        (Get-TpmRequiredPatchPlainReason -Status 'ALREADY_APPLIED' -Reason 'The exact pinned target bytes are already present; no write was made.') | Should -BeExactly ''
        (Get-TpmRequiredPatchPlainReason -Status 'INSTALLED' -Reason 'Installed.') | Should -BeExactly ''
    }

    It 'shows 14 already-installed patches of one game on ONE plain line and keeps the facts in the details' {
        # Mutation: print one line per patch ("ALREADY_APPLIED: <build> -- The exact pinned target bytes...") -> 14 lines, raw words.
        Install-F81Mocks -Width 100
        $specs = @($script:F81HummerEntries | ForEach-Object { @{ Entry = $_; Status = 'ALREADY_APPLIED'; Reason = 'The exact pinned target bytes are already present; no write was made.' } })
        $results = @(New-F81Results -Specs $specs)
        $blocks = @(Show-TpmRequiredPatchResults -Results $results -Action 'Install')
        $lines = @(Get-F81Lines)
        @($lines | Where-Object { $_ -match '\S' }).Count | Should -Be 1
        $lines | Should -Contain '  Already installed, nothing to do: Hummer Extreme Edition.'
        (($lines -join ' ') -match 'pinned target|ALREADY_APPLIED|hummerextreme') | Should -BeFalse
        $blocks.Count | Should -Be 1
        $blocks[0].Heading | Should -BeExactly $script:F81HummerBuild
        $detail = @($blocks[0].Lines) -join "`n"
        $detail | Should -Match 'Technical reason: The exact pinned target bytes are already present; no write was made\.'
        $detail | Should -Match 'Result code: ALREADY_APPLIED'
        $detail | Should -Match 'What it means: This was already set up'
        $detail | Should -Match 'hummerextreme-main-component-data-global-shader-gauss2-part01, '
        $detail | Should -Match 'part14'
        (($script:F81Log -join "`n") -match 'Required patch result \[ALREADY_APPLIED\] hummerextreme-main-component-data-global-shader-gauss2-part07: The exact pinned target bytes') | Should -BeTrue
    }

    It 'groups games with the same result on one line and keeps different reasons apart' {
        # Mutation: group by status only -> the two reasons share one line, or group by game -> three lines.
        Install-F81Mocks -Width 120
        $zip = 'The selected folder does not contain the exact required ZIP.'
        $results = @(New-F81Results -Specs @(
            @{ Entry = $script:F81Alpha; Status = 'BLOCKED'; Reason = $zip }
            @{ Entry = $script:F81Beta; Status = 'BLOCKED'; Reason = $zip }
            @{ Entry = $script:F81Mario; Status = 'BLOCKED'; Reason = 'Target conflict.' }
        ))
        [void](Show-TpmRequiredPatchResults -Results $results -Action 'Install')
        $paragraphs = @(Get-F81Paragraphs)
        $paragraphs.Count | Should -Be 2
        $paragraphs[0] | Should -BeExactly 'Could not install: Alpha Game and Beta Game. The ZIP file with this patch was not found.'
        $paragraphs[1] | Should -BeExactly 'Could not install: Mario Kart Arcade GP DX. A file in the game folder is different from what the patch expects. It was left alone.'
    }

    It 'says "Could not undo" and "Undone" for an undo' {
        # Mutation: always say install -> an undo failure reads "Could not install".
        Install-F81Mocks -Width 120
        $results = @(New-F81Results -Specs @(
            @{ Entry = $script:F81Alpha; Status = 'UNDONE'; Reason = 'Undo result: Restored. The receipt and current target state were verified.' }
            @{ Entry = $script:F81Beta; Status = 'BLOCKED'; Reason = 'Exactly one verified undo receipt is required; ambiguous or missing receipts block undo.' }
        ))
        [void](Show-TpmRequiredPatchResults -Results $results -Action 'Undo')
        $text = Get-F81Flat
        $text | Should -Match 'Undone: Alpha Game\. The game files are back the way they were\.'
        $text | Should -Match 'Could not undo: Beta Game\. The saved copy for undo was not found or is not correct\. Nothing was changed\.'
        $text | Should -Not -Match 'Could not install'
    }

    It 'does not call a patch that was never installed a failed undo, and does not call another graphics-card variant a failure' {
        # Mutation: record both as BLOCKED -> a fully successful undo of a two-variant game shows "Could not undo", and "Nothing was installed. Fix the problem above".
        Install-F81Mocks -Width 120
        $results = @(New-F81Results -Specs @(
            @{ Entry = $script:F81Alpha; Status = 'UNDONE'; Reason = 'Undo result: Restored.' }
            @{ Entry = $script:F81Beta; Status = 'NOTHING_TO_UNDO'; Reason = 'This exact game has no verified applied patch state to undo.' }
        ))
        [void](Show-TpmRequiredPatchResults -Results $results -Action 'Undo')
        $text = Get-F81Flat
        $text | Should -Match 'Undone: Alpha Game\.'
        $text | Should -Match 'Nothing to undo: Beta Game\. There is no patch from TeknoParrot Manager to undo here\.'
        $text | Should -Not -Match 'Could not undo'
        Install-F81Mocks -Width 120
        $variant = @(New-F81Results -Specs @(@{ Entry = $script:F81Alpha; Status = 'OTHER_VARIANT'; Reason = 'A different exclusive hardware variant applies: x-nvidia' }))
        [void](Show-TpmRequiredPatchResults -Results $variant -Action 'Install')
        Write-TpmRequiredPatchNothingInstalled -Results $variant -Choice 'A'
        $variantText = Get-F81Flat
        $variantText | Should -Match 'Skipped: Alpha Game\. This version of the patch is for a different graphics card\.'
        $variantText | Should -Match 'Nothing was changed\.'
        $variantText | Should -Not -Match 'Fix the problem|Could not install'
    }

    It 'asks the ZIP folder once for patches that share a ZIP, and again for another ZIP' {
        # Mutation: call Resolve-TpmRequiredPatchSourceRoot for every patch -> 14 questions for one game.
        Mock Resolve-TpmRequiredPatchSourceRoot { return 'C:\Zips' }
        $cache = @{}
        $first = [pscustomobject]@{ SourceRole = 'UserSelected'; SourceSet = 'one.zip' }
        $second = [pscustomobject]@{ SourceRole = 'UserSelected'; SourceSet = 'two.zip' }
        (Get-TpmRequiredPatchSourceRootOnce -Cache $cache -Entry $first) | Should -BeExactly 'C:\Zips'
        (Get-TpmRequiredPatchSourceRootOnce -Cache $cache -Entry $first) | Should -BeExactly 'C:\Zips'
        Should -Invoke Resolve-TpmRequiredPatchSourceRoot -Times 1 -Exactly
        [void](Get-TpmRequiredPatchSourceRootOnce -Cache $cache -Entry $second)
        Should -Invoke Resolve-TpmRequiredPatchSourceRoot -Times 2 -Exactly
    }

    It 'asks for the ZIP folder once and reuses it for a different patch ZIP found in the same folder' {
        $folder = Join-Path ([IO.Path]::GetTempPath()) ('tpm-zipfolder-' + [guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($folder)
        try {
            foreach ($zipName in @('one.zip', 'two.zip')) { [IO.File]::WriteAllText((Join-Path $folder $zipName), 'x') }
            Mock Read-PathWithBrowse { return $folder }
            $cache = @{}
            [void](Get-TpmRequiredPatchSourceRootOnce -Cache $cache -Entry ([pscustomobject]@{ SourceRole = 'UserSelected'; SourceSet = 'one.zip' }))
            [void](Get-TpmRequiredPatchSourceRootOnce -Cache $cache -Entry ([pscustomobject]@{ SourceRole = 'UserSelected'; SourceSet = 'two.zip' }))
            Should -Invoke Read-PathWithBrowse -Times 1 -Exactly
        } finally { Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'lists at most five games and counts the rest' {
        # Mutation: remove the limit -> a long list of games fills the screen.
        (Format-TpmNameList -Names @('A', 'B', 'C', 'D', 'E', 'F', 'G')) | Should -BeExactly 'A, B, C, D, E and 2 more'
        (Format-TpmNameList -Names @('A', 'B', 'C')) | Should -BeExactly 'A, B and C'
        (Format-TpmNameList -Names @('A')) | Should -BeExactly 'A'
    }

    It 'calls "nothing was installed" a problem only when something really failed' {
        # Mutation: print the "fix it" sentence for every empty result -> a user whose games are all installed is told to fix something.
        Install-F81Mocks -Width 120
        $installed = @(New-F81Results -Specs @(@{ Entry = $script:F81Alpha; Status = 'ALREADY_APPLIED'; Reason = 'x' }))
        Write-TpmRequiredPatchNothingInstalled -Results $installed -Choice 'A'
        $text = (Get-F81Lines) -join "`n"
        $text | Should -Match 'Nothing was changed\.'
        $text | Should -Not -Match 'Nothing was installed|Fix the problem|No patch was applied'
        Install-F81Mocks -Width 120
        $blocked = @(New-F81Results -Specs @(@{ Entry = $script:F81Alpha; Status = 'BLOCKED'; Reason = 'Target conflict.' }))
        Write-TpmRequiredPatchNothingInstalled -Results $blocked -Choice 'A'
        ((Get-F81Lines) -join "`n") | Should -Match 'Nothing was installed\. Fix the problem above, then try again\.'
        Install-F81Mocks -Width 120
        Write-TpmRequiredPatchNothingInstalled -Results @() -Choice 'A'
        $none = (Get-F81Lines) -join "`n"
        $none | Should -Match 'None of your registered games has a patch in this list\. Nothing was changed\.'
        $none | Should -Match 'choose M and pick its folder'
        Install-F81Mocks -Width 120
        $cancelled = @(New-F81Results -Specs @(@{ Entry = $script:F81Alpha; Status = 'CANCELLED'; Reason = 'No game folder was selected.' }))
        Write-TpmRequiredPatchNothingInstalled -Results $cancelled -Choice 'M'
        ((Get-F81Lines) -join "`n") | Should -Not -Match 'Fix the problem'
    }

    It 'keeps the undo-copy folder out of the install result and in the details and the log' {
        # Mutation: print "Undo receipt: <path>" on the default line -> the long path shows on the screen.
        Install-F81Mocks -Width 100
        $folder = 'C:\Games\TeknoParrotManager\Backups\GamePatches\0123456789abcdef0123456789abcdef'
        $results = @(New-F81Results -Specs @(
            @{ Entry = $script:F81Alpha; Status = 'INSTALLED'; Reason = 'Installed. The result was read back and checked.'; Receipt = $folder }
            @{ Entry = $script:F81Alpha2; Status = 'INSTALLED'; Reason = 'Installed. The result was read back and checked.'; Receipt = ($folder + '2') }
        ))
        $blocks = @(Show-TpmRequiredPatchResults -Results $results -Action 'Install')
        $lines = @(Get-F81Lines)
        $lines | Should -Contain '  Installed and checked: Alpha Game.'
        (($lines -join ' ') -match 'Backups|receipt|0123456789') | Should -BeFalse
        (@($blocks[0].Lines) -join "`n") | Should -Match ([regex]::Escape('Undo copy folder: ' + $folder))
        (@($blocks[0].Lines) -join "`n") | Should -Match ([regex]::Escape('Undo copy folder: ' + $folder + '2'))
        ($script:F81Log -join "`n") | Should -Match ([regex]::Escape('Undo copy: ' + $folder))
    }

    It 'gives the next step once, and names the games that are not in TeknoParrot yet' {
        # Mutation: print the next step once per installed patch -> three identical Next lines.
        Install-F81Mocks -Width 120
        $results = @(New-F81Results -Specs @(
            @{ Entry = $script:F81Alpha; Status = 'INSTALLED'; Reason = 'x'; Registered = $false }
            @{ Entry = $script:F81Alpha2; Status = 'INSTALLED'; Reason = 'x'; Registered = $false }
            @{ Entry = $script:F81Beta; Status = 'INSTALLED'; Reason = 'x'; Registered = $true }
        ))
        Write-TpmRequiredPatchNextSteps -Results $results
        $paragraphs = @(Get-F81Paragraphs)
        $paragraphs.Count | Should -Be 2
        $paragraphs[0] | Should -BeExactly 'Not in TeknoParrot yet: Alpha Game. Use Register only in the main menu to add it.'
        $paragraphs[1] | Should -BeExactly 'Next: start the game in TeknoParrotUI and test it and its controls.'
        Install-F81Mocks -Width 120
        Write-TpmRequiredPatchNextSteps -Results @(New-F81Results -Specs @(@{ Entry = $script:F81Alpha; Status = 'FAILED'; Reason = 'x' }))
        @(Get-F81Lines).Count | Should -Be 0
    }

    It 'asks to install with the right singular and plural, and keeps the saved-copy fact' {
        # Mutation: hard-code "patches" and "games" -> "1 patches for 1 games".
        Install-F81Mocks -Width 120
        $one = @([pscustomobject]@{ Entry = $script:F81Alpha })
        Write-TpmRequiredPatchPlan -Candidates $one
        (Get-F81Lines) | Should -Contain '  Ready to install 1 patch for 1 game: Alpha Game.'
        Install-F81Mocks -Width 120
        $many = @([pscustomobject]@{ Entry = $script:F81Alpha }, [pscustomobject]@{ Entry = $script:F81Alpha2 }, [pscustomobject]@{ Entry = $script:F81Beta })
        Write-TpmRequiredPatchPlan -Candidates $many
        $paragraphs = @(Get-F81Paragraphs)
        $paragraphs | Should -Contain 'Ready to install 3 patches for 2 games: Alpha Game and Beta Game.'
        $paragraphs | Should -Contain 'TeknoParrot Manager keeps a saved copy of the original files, so you can undo this later.'
        ((Get-TpmRequiredPatchPlanBlocks -Candidates $many)[0].Lines -join "`n") | Should -Match 'Patch ids: alpha-main-one, alpha-main-two'
    }

    It 'never prints the bare word TPM and keeps every line inside the console and every paragraph short at <Width> columns' -TestCases @(
        @{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }
    ) {
        param($Width)
        # Mutation: bring back a "TPM" sentence, drop the blank line before a paragraph, or ignore the console width -> a TPM hit, a run of 6+ lines, or a line as wide as the console.
        Install-F81Mocks -Width $Width
        $zip = 'The selected folder does not contain the exact required ZIP.'
        $results = @(New-F81Results -Specs @(
            @{ Entry = $script:F81Alpha; Status = 'BLOCKED'; Reason = $zip }
            @{ Entry = $script:F81Beta; Status = 'BLOCKED'; Reason = $zip }
            @{ Entry = $script:F81Mario; Status = 'ALREADY_APPLIED'; Reason = 'x' }
            @{ Entry = $script:F81HummerEntries[0]; Status = 'BLOCKED'; Reason = 'BepInEx is not installed for this game. Use TeknoParrot Manager.' }
        ))
        [void](Show-TpmRequiredPatchResults -Results $results -Action 'Install')
        Write-TpmRequiredPatchNothingInstalled -Results $results -Choice 'A'
        Write-TpmRequiredPatchPlan -Candidates @([pscustomobject]@{ Entry = $script:F81Alpha }, [pscustomobject]@{ Entry = $script:F81Beta }, [pscustomobject]@{ Entry = $script:F81Mario })
        Write-TpmRequiredPatchNextSteps -Results @(New-F81Results -Specs @(@{ Entry = $script:F81Alpha; Status = 'INSTALLED'; Reason = 'x'; Registered = $false }))
        Write-TpmRequiredPatchCleanupWarning -Failures @('C:\Temp\RequiredPatch-1 -- in use')
        $lines = @(Get-F81Lines)
        $lines.Count | Should -BeGreaterThan 10
        (($lines -join "`n") -cmatch '\bTPM\b') | Should -BeFalse
        @($lines | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
        (Get-F81MaxRun -Lines $lines) | Should -BeLessOrEqual 5
    }

    It 'keeps the old technical facts under D at the last question, and asks the question exactly once without D' {
        # Mutation: ask a second question, or never offer D -> a piped answer is used up twice, or the details are lost.
        $blocks = @(@{ Heading = 'Hummer'; Lines = @('Result code: ALREADY_APPLIED') })
        Install-F81Mocks -Answers @('')
        Wait-TpmRequiredPatchReturn -DetailBlocks $blocks
        $script:F81Prompts.Count | Should -Be 1
        $script:F81Prompts[0] | Should -Be '  Press D for details, or Enter to go back'
        ((Get-F81Lines) -join "`n") | Should -Not -Match 'ALREADY_APPLIED'
        Install-F81Mocks -Answers @('d', '')
        Wait-TpmRequiredPatchReturn -DetailBlocks $blocks
        $script:F81Prompts.Count | Should -Be 2
        ((Get-F81Lines) -join "`n") | Should -Match 'Result code:\s+ALREADY_APPLIED'
        Install-F81Mocks -Answers @('')
        Wait-TpmRequiredPatchReturn
        $script:F81Prompts[0] | Should -Be '  Press Enter to go back'
    }

    It 'shows the temporary files that could not be removed, in plain words, and logs them' {
        # Mutation: drop the details or the log line -> the folder names are lost.
        Install-F81Mocks -Width 100
        Write-TpmRequiredPatchCleanupWarning -Failures @('C:\Temp\RequiredPatch-1 -- in use')
        $text = (Get-F81Lines) -join "`n"
        $text | Should -Match 'TeknoParrot Manager could not remove some temporary files\. Your game files are not affected\.'
        $text | Should -Match 'Left behind:\s+C:\\Temp\\RequiredPatch-1 -- in use'
        ($script:F81Log -join "`n") | Should -Match 'Required patch cleanup: C:\\Temp\\RequiredPatch-1 -- in use'
    }

    It 'has no bare TPM in any text of the engine that a person can read' {
        # Mutation: put "TPM" back into a throw, a Write-Host line or the BepInEx guidance -> a hit.
        $hits = @([System.IO.File]::ReadAllLines($script:F81EnginePath) | Where-Object { $_ -cmatch '\bTPM\b' })
        $hits.Count | Should -Be 0
    }
}

Describe 'FIX81 required patch menu end to end (mocked, one folder question per game)' {
    BeforeEach {
        $script:F81Root = Join-Path $TestDrive ('f81-' + [guid]::NewGuid().ToString('N'))
        $script:F81GameDir = Join-Path $script:F81Root 'game'
        $script:F81Src = Join-Path $script:F81Root 'zips'
        $temp = Join-Path $script:F81Root 'owned\Temp'
        foreach ($directory in @($temp, $script:F81GameDir, $script:F81Src)) { [void][IO.Directory]::CreateDirectory($directory) }
        $script:F81Exe = Join-Path $script:F81GameDir 'game.exe'
        [IO.File]::WriteAllText($script:F81Exe, 'synthetic executable; never launch')
        $hash = (Get-FileHash -LiteralPath $script:F81Exe -Algorithm SHA256).Hash
        $script:TpmOwnedLayout = [pscustomobject]@{ Root = (Join-Path $script:F81Root 'owned'); Temp = $temp; Backups = (Join-Path $script:F81Root 'owned\Backups') }
        $script:gamesInstallFolder = $script:F81GameDir
        $script:F81Entries = @(
            (New-F81Entry -Id 'alpha-main-one' -Build 'Alpha Game (1.0)[TP]' -Hash $hash),
            (New-F81Entry -Id 'alpha-main-two' -Build 'Alpha Game (1.0)[TP]' -Hash $hash),
            (New-F81Entry -Id 'beta-main-one' -Build 'Beta Game (2.0)[TP]' -Hash $hash)
        )
        Mock Read-TpmRequiredPatchCatalog { return [pscustomobject]@{ Path = 'x'; Content = '{}'; CatalogSha256 = ('A' * 64); Entries = $script:F81Entries; Schema = 3 } }
        Mock Read-PathWithBrowse { return $script:F81GameDir }
        Mock Resolve-TpmRequiredPatchSourceRoot { return $script:F81Src }
        Mock New-TpmRequiredPatchPayloadStage {
            $stage = Join-Path $script:TpmOwnedLayout.Temp ('RequiredPatch-' + [guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory($stage)
            return [pscustomobject]@{ Root = $stage; Payload = (Join-Path $stage 'payload.bin') }
        }
        Mock Get-TpmManualPatchContext {
            return [pscustomobject]@{ GamePath = $script:F81Exe; GameRoot = $script:F81GameDir; RecoveryRoot = (Join-Path $script:F81Root 'rec'); ProtectedRoots = @('x'); Registered = $false; ProfilePath = ''; ProfileSha256 = '' }
        }
        Mock Get-TpmPatchPlan { return [pscustomobject]@{ Status = 'AlreadyApplied'; Reason = '' } }
    }
    AfterEach {
        $script:TpmOwnedLayout = $null
        $script:gamesInstallFolder = $null
    }

    It 'lists games, asks for the game folder once for a game with two patches, and groups the answer on one line' {
        # Mutation: ask the folder once per patch, or list one row per patch -> two browse calls, and the second row is Alpha Game.
        Install-F81Mocks -Width 100 -Answers @('M', '1', '')
        Invoke-TpmRequiredPatchMenu -TpRoot $script:F81Root -UserProfilesDir $script:F81Root -ManagerRoot $script:F81Root -ProgramRoot $script:F81Root
        Should -Invoke Read-PathWithBrowse -Times 1 -Exactly
        Should -Invoke New-TpmRequiredPatchPayloadStage -Times 2 -Exactly
        $script:F81Prompts.Count | Should -Be 3
        $script:F81Prompts[1] | Should -Match 'number of your game'
        $lines = @(Get-F81Lines)
        $lines | Should -Contain '  1) Alpha Game (2 patches)'
        $lines | Should -Contain '  2) Beta Game (1 patch)'
        $lines | Should -Contain '  Already installed, nothing to do: Alpha Game.'
        $lines | Should -Contain '  Nothing was changed.'
        (($lines -join ' ') -match 'ALREADY_APPLIED|pinned target|alpha-main') | Should -BeFalse
        $script:F81Prompts[2] | Should -Be '  Press D for details, or Enter to go back'
        @(Get-ChildItem -LiteralPath $script:TpmOwnedLayout.Temp -Directory).Count | Should -Be 0
    }

    It 'shows every old fact when D is pressed at the last question' {
        # Mutation: leave the results out of the details -> the ids and the technical reason are gone.
        Install-F81Mocks -Width 100 -Answers @('M', '1', 'D', '')
        Invoke-TpmRequiredPatchMenu -TpRoot $script:F81Root -UserProfilesDir $script:F81Root -ManagerRoot $script:F81Root -ProgramRoot $script:F81Root
        $script:F81Prompts.Count | Should -Be 4
        $text = Get-F81Flat
        $text | Should -Match 'Patch ids: alpha-main-one, alpha-main-two'
        $text | Should -Match 'Technical reason: The exact pinned target bytes are already present; no write was made\.'
        $text | Should -Match 'Result code: ALREADY_APPLIED'
        $text | Should -Match 'Result: Already installed, nothing to do'
    }

    It 'goes back without asking for a folder when the answer is not a game number' {
        # Mutation: read the folder before checking the number -> a browse call after a bad answer.
        Install-F81Mocks -Width 100 -Answers @('M', '7')
        Invoke-TpmRequiredPatchMenu -TpRoot $script:F81Root -UserProfilesDir $script:F81Root -ManagerRoot $script:F81Root -ProgramRoot $script:F81Root
        Should -Invoke Read-PathWithBrowse -Times 0 -Exactly
        ((Get-F81Lines) -join "`n") | Should -Match 'That is not a number in the list\. Nothing was changed\.'
    }

    It 'reports a blank folder choice once, not once per patch' {
        # Mutation: report the cancel for every patch of the game -> two "Skipped" results for Alpha Game.
        Mock Read-PathWithBrowse { return '' }
        Install-F81Mocks -Width 100 -Answers @('M', '1', '')
        Invoke-TpmRequiredPatchMenu -TpRoot $script:F81Root -UserProfilesDir $script:F81Root -ManagerRoot $script:F81Root -ProgramRoot $script:F81Root
        $lines = @(Get-F81Lines)
        $lines | Should -Contain '  Skipped: Alpha Game. You did not choose a game folder, so nothing was changed.'
        $lines | Should -Contain '  Nothing was changed.'
        Should -Invoke New-TpmRequiredPatchPayloadStage -Times 0 -Exactly
    }

    It 'says plainly that nothing can be undone, and shows no game list, when no patch has a saved undo copy' {
        # Mutation: list every game in Undo again -> a "Pick your game" list and a folder question appear even though nothing was installed.
        Install-F81Mocks -Width 100 -Answers @('U', '')
        Invoke-TpmRequiredPatchMenu -TpRoot $script:F81Root -UserProfilesDir $script:F81Root -ManagerRoot $script:F81Root -ProgramRoot $script:F81Root
        $lines = @(Get-F81Lines)
        ($lines -join "`n") | Should -Match 'There is nothing to undo\.'
        ($lines -join "`n") | Should -Not -Match 'Pick your game'
        Should -Invoke Read-PathWithBrowse -Times 0 -Exactly
        $script:F81Prompts[1] | Should -Be '  Press Enter to go back'
    }

    It 'lists only the games that still have an undo copy, and counts only their patches' {
        # Mutation: ignore the saved copies, or count a copy already put back -> Beta Game or the second Alpha patch shows up.
        $recovery = Join-Path $script:TpmOwnedLayout.Backups 'GamePatches'
        foreach ($copy in @(@{ Patch = 'alpha-main-one'; State = 'Applied' }, @{ Patch = 'beta-main-one'; State = 'Restored' })) {
            $folder = Join-Path $recovery ([guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory($folder)
            $receipt = [ordered]@{ PatchId = $copy.Patch; ProfileId = 'p'; GameRoot = $script:F81GameDir; State = $copy.State }
            [IO.File]::WriteAllText((Join-Path $folder 'receipt.json'), ($receipt | ConvertTo-Json))
        }
        Install-F81Mocks -Width 100 -Answers @('U', '7')
        Invoke-TpmRequiredPatchMenu -TpRoot $script:F81Root -UserProfilesDir $script:F81Root -ManagerRoot $script:F81Root -ProgramRoot $script:F81Root
        $lines = @(Get-F81Lines)
        $lines | Should -Contain '  1) Alpha Game (1 patch)'
        (($lines -join "`n") -match 'Beta Game') | Should -BeFalse
    }

    It 'goes on to the game folder question when exactly one patch can be undone' {
        # Mutation: let a one-patch list collapse to a bare object -> .Count or indexing fails once the single game is picked.
        $folder = Join-Path (Join-Path $script:TpmOwnedLayout.Backups 'GamePatches') ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($folder)
        [IO.File]::WriteAllText((Join-Path $folder 'receipt.json'), '{"PatchId":"beta-main-one","ProfileId":"p","GameRoot":"x","State":"Applied"}')
        Install-F81Mocks -Width 100 -Answers @('U', '1', '')
        { Invoke-TpmRequiredPatchMenu -TpRoot $script:F81Root -UserProfilesDir $script:F81Root -ManagerRoot $script:F81Root -ProgramRoot $script:F81Root } | Should -Not -Throw
        Should -Invoke Read-PathWithBrowse -Times 1 -Exactly
    }

    It 'keeps a game in the undo list for an applied, interrupted or unmarked copy, and drops finished or unreadable ones' {
        # Mutation: hide a copy with no recorded state, or keep a Restored/RolledBack one -> a game that can still be undone vanishes, or an empty game is offered.
        $recovery = Join-Path $script:TpmOwnedLayout.Backups 'GamePatches'
        $copies = @(
            @{ Patch = 'p-applied'; Json = '{"PatchId":"p-applied","ProfileId":"p","GameRoot":"x","State":"Applied"}' }
            @{ Patch = 'p-prepared'; Json = '{"PatchId":"p-prepared","ProfileId":"p","GameRoot":"x","State":"Prepared"}' }
            @{ Patch = 'p-unmarked'; Json = '{"PatchId":"p-unmarked","ProfileId":"p","GameRoot":"x"}' }
            @{ Patch = 'p-restored'; Json = '{"PatchId":"p-restored","ProfileId":"p","GameRoot":"x","State":"Restored"}' }
            @{ Patch = 'p-rolledback'; Json = '{"PatchId":"p-rolledback","ProfileId":"p","GameRoot":"x","State":"RolledBack"}' }
            @{ Patch = 'p-noprofile'; Json = '{"PatchId":"p-noprofile","GameRoot":"x","State":"Applied"}' }
            @{ Patch = 'p-broken'; Json = '{not json' }
        )
        foreach ($copy in $copies) {
            $folder = Join-Path $recovery ([guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory($folder)
            [IO.File]::WriteAllText((Join-Path $folder 'receipt.json'), $copy.Json)
        }
        $ids = @(Get-TpmUndoablePatchIds -RecoveryRoot $recovery | Sort-Object)
        ($ids -join ',') | Should -Be 'p-applied,p-prepared,p-unmarked'
        @(Get-TpmUndoablePatchIds -RecoveryRoot (Join-Path $script:F81Root 'no-such-folder')).Count | Should -Be 0
    }
}

Describe 'FIX81 Propagate Controls (item 6)' {
    BeforeAll {
        $script:F81Reports = @(
            [pscustomobject]@{ Code = 'GameA'; Status = 'bound'; Family = 'driving'; Archetype = 'RefDriver'; Bound = 3; Manual = @(); ConfigCarried = @('Sensitivity=50'); ArchetypeApi = 'RawInput'; Forced = $false; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameB'; Status = 'bound'; Family = 'driving'; Archetype = 'RefDriver'; Bound = 1; Manual = @('Start'); ConfigCarried = @(); ArchetypeApi = 'RawInput'; Forced = $true; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameC'; Status = 'api-fixed'; ArchetypeApi = 'RawInput'; Archetype = 'RefDriver'; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameD'; Status = 'settings-only'; Bound = 0; ConfigCarried = @('Sensitivity=50'); Manual = @('Start') }
            [pscustomobject]@{ Code = 'GameE'; Status = 'skipped-no-reference'; ReasonCode = 'NO_USABLE_FAMILY_REFERENCE'; Family = 'lightgun'; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameF'; Status = 'skipped-bound'; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameG'; Status = 'skipped-override'; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameH'; Status = 'save-failed'; Archetype = 'RefDriver'; MismatchSlots = $null }
        )
    }

    It 'turns reports into a short summary counting missing family references as design skips' {
        # Mutation: omit design skips from skipped counts or classify them as Needs -> summary counts and status disagree.
        $summary = Get-TpmControlPropagationSummary -Reports $script:F81Reports
        $summary.Title | Should -BeExactly '4 games updated. 1 game could not be saved.'
        $summary.Status | Should -BeExactly 'Attention'
        @($summary.Done) | Should -Be @('Controls copied to 2 games.', 'Input API corrected for 1 game.')
        $summary.NotChanged | Should -Match '^1 game already set up\. 1 game skipped by your own rules\. 1 game skipped: no game of their family has your controls yet'
        @($summary.Needs) | Should -Be @(
            'GameB and GameD: set up the controls yourself in TeknoParrotUI.',
            'GameH: could not be saved. See the log.'
        )
        $summary.Next | Should -BeExactly 'Start one updated game in TeknoParrotUI and test its controls. If something is wrong, use Restore backup.'
        $counts = $summary.Counts
        $counts.ControlsCopiedCount | Should -Be 2
        $counts.SettingsOnlyCount | Should -Be 1
        $counts.ApiFixedCount | Should -Be 1
        $counts.BoundCount | Should -Be 3
        $counts.ManualCount | Should -Be 2
        $counts.SkippedCount | Should -Be 3
        $counts.FailedCount | Should -Be 1
        $counts.VerifiedPhysicalBindingsCount | Should -Be 0
        @($counts.DesignSkippedItems).Count | Should -Be 1
        $counts.DesignSkippedItems[0].Code | Should -BeExactly 'GameE'
    }

    It 'says "1 game updated." for one game and "No game needed a change." for none' {
        # Mutation: hard-code "games" -> "1 games updated."
        (Get-TpmControlPropagationSummary -Reports @($script:F81Reports[2])).Title | Should -BeExactly '1 game updated.'
        $none = Get-TpmControlPropagationSummary -Reports @($script:F81Reports[5], $script:F81Reports[6])
        $none.Title | Should -BeExactly 'No game needed a change.'
        $none.Status | Should -BeExactly 'Ok'
        $none.Next | Should -BeExactly ''
        (Get-TpmControlPropagationSummary -Reports @($script:F81Reports[7])).Status | Should -BeExactly 'Problem'
        (Get-TpmControlPropagationSummary -Reports @($script:F81Reports[4])).Title | Should -BeExactly 'No game was changed.'
    }

    It 'words a preview as "would" and says nothing was saved' {
        # Mutation: reuse the saved wording for a preview -> "Controls copied to 2 games." for a run that saved nothing.
        $summary = Get-TpmControlPropagationSummary -Reports $script:F81Reports -DryRun $true
        $summary.Title | Should -BeExactly 'Preview only. Nothing was saved.'
        @($summary.Done) | Should -Be @('Would copy controls to 2 games.', 'Would correct the Input API of 1 game.')
        $summary.Next | Should -BeExactly ''
        $summary.Note | Should -Match 'No game was saved'
    }

    It 'prints the short result at <Width> columns: inside the console, short paragraphs, no bare TPM, no old counter block' -TestCases @(
        @{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }
    ) {
        param($Width)
        # Mutation: bring back the per-game lines or the seven count lines, drop -Spaced, or ignore the width.
        Install-F81Mocks -Width $Width
        $counts = Write-ControlPropagationResults -Reports $script:F81Reports -Unattended
        $counts.ControlsCopiedCount | Should -Be 2
        $lines = @(Get-F81Lines)
        $text = $lines -join "`n"
        $text | Should -Not -Match 'Verified physical bindings|Games still needing manual|Settings carried only|Results:|GameA|GameF'
        (($text) -cmatch '\bTPM\b') | Should -BeFalse
        @($lines | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
        (Get-F81MaxRun -Lines $lines) | Should -BeLessOrEqual 5
        $script:F81Prompts.Count | Should -Be 0
    }

    It 'shows every old fact when D is pressed, and logs them without D' {
        # Mutation: leave the counts, the per-game rows or the saved-copy folder out of the details.
        Install-F81Mocks -Width 100 -Answers @('D')
        [void](Write-ControlPropagationResults -Reports $script:F81Reports -Outcome 'PARTIAL_APPLIED' -BackupPath 'C:\Games\Backups\PropagateControls_x')
        $script:F81Prompts.Count | Should -Be 1
        $text = Get-F81Flat
        $text | Should -Match 'Verified physical bindings: 0 \(TeknoParrot Manager does not launch games or test device input\)\.'
        $text | Should -Match 'Games with controls copied: 2'
        $text | Should -Match 'Games still needing manual setup: 2'
        $text | Should -Match 'Games failed: 1'
        $text | Should -Match 'Settings copied: Sensitivity=50'
        $text | Should -Match 'Still manual: Start'
        $text | Should -Match 'Pinned: you chose its example game'
        $text | Should -Match 'Folder: C:\\Games\\Backups\\PropagateControls_x'
        $text | Should -Match 'These counts describe saved settings, not a verified physical device binding\.'
        ($script:F81Log -join "`n") | Should -Match 'Result detail \[Counts\]: Games failed: 1'
        Install-F81Mocks -Width 100 -Interactive $false
        [void](Write-ControlPropagationResults -Reports $script:F81Reports)
        $script:F81Prompts.Count | Should -Be 0
        ($script:F81Log -join "`n") | Should -Match 'Result detail \[GameH\]: What happened: Could not be saved\.'
    }

    It 'writes the directional mismatch as a detail with what to do' {
        # Mutation: drop the mismatch lines -> the slots the user must fix are lost.
        Install-F81Mocks -Width 100 -Answers @('D')
        $report = [pscustomobject]@{ Code = 'GameM'; Status = 'api-fixed'; ArchetypeApi = 'RawInput'; Archetype = 'RefDriver'; MismatchSlots = 'P1 Up, P1 Down' }
        $summary = Get-TpmControlPropagationSummary -Reports @($report)
        @($summary.Needs) | Should -Be @('GameM: some buttons do the wrong thing. Set them again in TeknoParrotUI.')
        [void](Write-ControlPropagationResults -Reports @($report))
        $text = Get-F81Flat
        $text | Should -Match 'Needs attention: directional/action mismatch in P1 Up, P1 Down'
        $text | Should -Match 'What to do: set these slots again by hand'
    }

    It 'gives the example games as one line, and a warning line only when a copied setting looks wrong' {
        # Mutation: print the source rows ("api=... device(s): ...") or always warn -> technical rows or a false warning.
        Install-F81Mocks -Width 100
        $plain = New-F81Source -Code 'RefWheel' -Carry @{ 'Use Keyboard/Button For Axis' = 'False'; 'Player 1 Relative Sensitivity' = '50' }
        Write-TpmControlSourceSummary -Pool @($plain, (New-F81Source -Code 'RefPad'), (New-F81Source -Code 'RefGun' -Family 'lightgun'))
        $lines = @(Get-F81Lines)
        $lines | Should -Contain '  You have 3 games with their controls set up.'
        @($lines | Where-Object { $_ -match '\S' }).Count | Should -Be 1
        (($lines -join ' ') -match 'api=|device\(s\)|buttons|RefWheel|Sensitivity') | Should -BeFalse
        Install-F81Mocks -Width 100
        $bad = New-F81Source -Code 'RefBad' -Carry @{ 'Use Keyboard/Button For Axis' = 'True' }
        Write-TpmControlSourceSummary -Pool @($bad)
        $paragraphs = @(Get-F81Paragraphs)
        $paragraphs.Count | Should -Be 2
        $paragraphs[0] | Should -BeExactly 'You have 1 game with its controls set up.'
        $paragraphs[1] | Should -BeExactly 'Check first: 1 game may have settings that do not match your real controller. Press D to see them.'
    }

    It 'asks one question with D for details, keeps Y and N, and puts the old rows and advice under D' {
        # Mutation: drop DetailsAction, or leave the advice or the rows out of the blocks.
        Install-F81Mocks -Width 100 -Answers @('d', 'y')
        $bad = New-F81Source -Code 'RefBad' -Carry @{ 'Use Keyboard/Button For Axis' = 'True'; 'Player 1 Relative Sensitivity' = '50' }
        $answer = Read-TpmControlCopyApproval -Pool @($bad, (New-F81Source -Code 'RefPad' -Api 'DirectInput' -Devices @())) -BackupNote 'A saved copy of your game settings is made when you approve.'
        $answer | Should -BeExactly 'Y'
        $script:F81Prompts.Count | Should -Be 2
        $script:F81Prompts[0] | Should -Be '  Copy controls from 2 games to your other games of the same type? (Y/N, D = details)'
        $text = Get-F81Flat
        $text | Should -Match 'Input API: RawInput'
        $text | Should -Match 'Devices: ArchPad Btn'
        $text | Should -Match 'Devices: not known'
        $text | Should -Match 'Settings copied: .*Player 1 Relative Sensitivity=50'
        $text | Should -Match 'Warning: Use Keyboard/Button For Axis=True'
        $text | Should -Match 'copied to EVERY other game of that type'
        $text | Should -Match '"Use Keyboard/Button For Axis" should be False if you set up a real wheel'
        $text | Should -Match 'A saved copy of your game settings is made when you approve\.'
        Install-F81Mocks -Width 100 -Answers @('n')
        (Read-TpmControlCopyApproval -Pool @($bad)) | Should -BeExactly 'N'
    }

    It 'keeps the long per-game lines out of the source details when no setting is copied' {
        # Mutation: always print a Settings copied row -> an empty row for a game with nothing to copy.
        $blocks = @(Get-TpmControlSourceBlocks -Pool @(New-F81Source -Code 'RefPad'))
        $blocks.Count | Should -Be 2
        $blocks[1].Heading | Should -BeExactly 'RefPad'
        (@($blocks[1].Lines) -join "`n") | Should -Not -Match 'Settings copied|Warning'
        $blocks[1].ContainsKey('Color') | Should -BeFalse
    }
}

Describe 'FIX81 custom rules notice (item 7)' {
    BeforeAll {
        $script:F81NoCounts = [ordered]@{ noSync = 0; onlySync = 0; noPropagate = 0; forceArchetype = 0; familyOverride = 0; canonicalArchetype = 0; subFolderMap = 0 }
        $script:F81SomeCounts = [ordered]@{ noSync = 2; onlySync = 0; noPropagate = 1; forceArchetype = 0; familyOverride = 0; canonicalArchetype = 0; subFolderMap = 3 }
    }

    It 'prints nothing and asks nothing when the file holds no rules' {
        # Mutation: print the notice for zero rules -> a line on every start-up.
        Install-F81Mocks
        Show-TpmOverridesNotice -Counts $script:F81NoCounts -FilePath 'C:\TPM\TeknoParrot-Manager.overrides.json'
        @(Get-F81Lines).Count | Should -Be 0
        $script:F81Prompts.Count | Should -Be 0
    }

    It 'prints one plain line with a pointer to the log and no counters' {
        # Mutation: print the counters or the file path under the line -> "noSync=2" or a path on the start-up screen.
        # The console is 120 wide here, so the 89-character sentence stays on one line whatever the harness width is.
        Install-F81Mocks -Width 120
        Show-TpmOverridesNotice -Counts $script:F81SomeCounts -FilePath 'C:\TPM\TeknoParrot-Manager.overrides.json'
        $lines = @(Get-F81Lines)
        @($lines | Where-Object { $_ -match '\S' }) | Should -Be @('  You have custom rules in TeknoParrot-Manager.overrides.json. The full list is in the log.')
        (($lines -join ' ') -match '=|pinned|familyOverride|These come from') | Should -BeFalse
    }

    It 'writes what each rule does, how many there are and the file to the log, once' {
        # Mutation: drop the blocks or the note, or log a rule that has no entries -> a fact is lost or a line is noise.
        Install-F81Mocks
        Show-TpmOverridesNotice -Counts $script:F81SomeCounts -FilePath 'C:\TPM\TeknoParrot-Manager.overrides.json'
        $log = $script:F81Log -join "`n"
        $log | Should -Match 'Custom rules \[The file\]: Path: C:\\TPM\\TeknoParrot-Manager\.overrides\.json'
        $log | Should -Match 'Custom rules \[ZIP files that are never extracted\]: Setting: noSync'
        $log | Should -Match 'Custom rules \[ZIP files that are never extracted\]: How many: 2'
        $log | Should -Match 'What it does: These games are skipped when TeknoParrot Manager extracts ZIP files\.'
        $log | Should -Match 'Setting: noPropagate'
        $log | Should -Match 'Setting: subFolderMap'
        $log | Should -Not -Match 'Setting: onlySync|Setting: forceArchetype'
        ([regex]::Matches($log, 'If you did not make this file yourself')).Count | Should -Be 1
    }

    It 'lets the line wrap inside a <Width> column console' -TestCases @(
        @{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }
    ) {
        param($Width)
        # Mutation: write the line with Write-Host and no wrapping -> a line as wide as the console.
        Install-F81Mocks -Width $Width
        Show-TpmOverridesNotice -Counts $script:F81SomeCounts -FilePath 'x'
        $lines = @(Get-F81Lines | Where-Object { $_ -match '\S' })
        @($lines | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
        (($lines | ForEach-Object { $_.Trim() }) -join ' ') | Should -BeExactly 'You have custom rules in TeknoParrot-Manager.overrides.json. The full list is in the log.'
    }
}

Describe 'FIX81 shared helpers' {
    It 'counts a noun with the right singular and plural' {
        # Mutation: always append "s" -> "1 patchs"; ignore the plural argument -> "2 childs".
        (Format-TpmCountNoun -Count 1 -Singular 'patch') | Should -BeExactly '1 patch'
        (Format-TpmCountNoun -Count 0 -Singular 'patch') | Should -BeExactly '0 patches'
        (Format-TpmCountNoun -Count 2 -Singular 'box') | Should -BeExactly '2 boxes'
        (Format-TpmCountNoun -Count 2 -Singular 'child' -Plural 'children') | Should -BeExactly '2 children'
        (Format-TpmGameCount -Count 1) | Should -BeExactly '1 game'
        (Format-TpmGameCount -Count 3) | Should -BeExactly '3 games'
    }

    It 'asks the question once, repeats it after D, and treats D as an ordinary answer when there is nothing to show' {
        # Mutation: loop on D without blocks -> an endless loop; skip the repeat -> the answer after D is lost.
        $blocks = @(@{ Heading = 'One'; Lines = @('Label: text') })
        Install-F81Mocks -Answers @('x')
        (Read-TpmAnswerWithDetails -Prompt 'Question' -DetailBlocks $blocks) | Should -BeExactly 'X'
        $script:F81Prompts.Count | Should -Be 1
        Install-F81Mocks -Answers @('d', 'y')
        (Read-TpmAnswerWithDetails -Prompt 'Question' -DetailBlocks $blocks) | Should -BeExactly 'Y'
        $script:F81Prompts.Count | Should -Be 2
        Install-F81Mocks -Answers @('d')
        (Read-TpmAnswerWithDetails -Prompt 'Question') | Should -BeExactly 'D'
        $script:F81Prompts.Count | Should -Be 1
    }

    It 'lets Write-TpmOutcome put a blank line before every item when it is spaced' {
        # Mutation: ignore -Spaced -> two bullets and a not-changed line sit in one run.
        Install-F81Mocks -Width 120 -Interactive $false
        Write-TpmOutcome -Title 'Done.' -Done @('One.', 'Two.') -NotChanged 'Three.' -Needs @('Four.') -Spaced
        $spaced = @(Get-F81Lines)
        (Get-F81MaxRun -Lines $spaced) | Should -Be 1
        Install-F81Mocks -Width 120 -Interactive $false
        Write-TpmOutcome -Title 'Done.' -Done @('One.', 'Two.') -NotChanged 'Three.' -Needs @('Four.')
        (Get-F81MaxRun -Lines @(Get-F81Lines)) | Should -BeGreaterThan 3
    }
}
