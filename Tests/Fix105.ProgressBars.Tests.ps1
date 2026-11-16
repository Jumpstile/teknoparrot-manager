#Requires -Module Pester

# FIX105: progress bars must look like bars. The one renderer (scripts\TpmProgress.psm1) and the one product wrapper
# (Write-TpmCompactExtractionProgress) are tested with fakes only: console seams are mocked, so nothing touches a real
# console, an install, the registry or the network. Glyphs are built at run time; this file is pure ASCII.

BeforeAll {
    $script:modulePath = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $PSScriptRoot '..\scripts') 'TpmProgress.psm1'))
    Get-Module -Name TpmProgress -All | Remove-Module -Force
    Import-Module $script:modulePath -Force -ErrorAction Stop
    $script:full = [string][char]0x2588
    $script:empty = [string][char]0x00B7
    $script:shade = [string][char]0x2591
    $script:tick = [string][char]0x2713
    $script:columns = @('Description', 'Bar', 'Percentage', 'Count', 'Elapsed', 'Remaining', 'Spinner')

    function Set-Fix105DefaultMocks {
        Mock Get-TpmProgressDefaultColumns { @('Description', 'Bar', 'Percentage', 'Count', 'Elapsed', 'Remaining', 'Spinner') } -ModuleName TpmProgress
        Mock Start-TpmProgressRefresh {} -ModuleName TpmProgress
        Mock Get-TpmProgressCursorVisible { $true } -ModuleName TpmProgress
        Mock Set-TpmProgressCursorVisible {} -ModuleName TpmProgress
    }
}

AfterAll {
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
}

Describe 'FIX105 solid bar glyphs' {
    BeforeEach { Set-Fix105DefaultMocks }

    It 'draws the filled part with the full block and the empty part as tiny dots (U+00B7) in Block style' {
        # Mutation: Get-TpmProgressBarGlyphs returns '#' and '-' for the Block style (the old look).
        $bar = Format-TpmProgressBar -Current 5 -Total 10 -BarWidth 12 -Style Block
        $bar | Should -BeExactly ('|' + ($script:full * 5) + ($script:empty * 5) + '|')
        $bar | Should -Not -Match $script:shade
        $bar | Should -Not -Match ' '
        $bar | Should -Not -Match '#'
    }

    It 'shows an empty track at 0 percent, a capped bar while running and a full bar only when Final' {
        # Mutation: the 99 percent cap is removed, or a Final bar is not filled to the end.
        (Format-TpmProgressBar -Current 0 -Total 10 -BarWidth 12 -Style Block) | Should -BeExactly ('|' + ($script:empty * 10) + '|')
        (Format-TpmProgressBar -Current 10 -Total 10 -BarWidth 12 -State Running -Style Block) | Should -BeExactly ('|' + ($script:full * 9) + $script:empty + '|')
        (Format-TpmProgressBar -Current 10 -Total 10 -BarWidth 12 -State Final -Style Block) | Should -BeExactly ('|' + ($script:full * 10) + '|')
    }

    It 'rounds a partial bar down to whole blocks and never uses a half-block glyph in Block style' {
        # Mutation: the fractional-block branch is enabled for Block (those glyphs are missing from OEM code pages).
        $bar = Format-TpmProgressBar -Current 25 -Total 100 -BarWidth 12 -Style Block
        $bar | Should -BeExactly ('|' + ($script:full * 2) + ($script:empty * 8) + '|')
        $bar | Should -Not -Match '[\u2589-\u258F]'
    }

    It 'keeps plain ASCII glyphs for the Ascii style (redirected output, logs, captures)' {
        # Mutation: the Ascii style starts using block glyphs, so logs stop being plain ASCII.
        $bar = Format-TpmProgressBar -Current 5 -Total 10 -BarWidth 12 -Style Ascii
        $bar | Should -BeExactly '|#####-----|'
        $bar | Should -Not -Match '[^\x20-\x7E]'
    }

    It 'animates an unknown total with ASCII arrows on a tiny-dot track in Block style' {
        # Mutation: Block uses '-' or the light shade as its empty cell for the unknown-total pulse.
        (Format-TpmProgressBar -Current 0 -Total 0 -BarWidth 20 -Style Block -Tick 0) | Should -BeExactly ('|' + ('>' * 14) + ($script:empty * 4) + '|')
    }

    It 'builds a line of exactly the window width at every width, made only of ASCII, the block and the middle dot (no shade glyph)' {
        # Mutation: a Block line uses a glyph outside ASCII + U+2588 + U+00B7 (for example the old U+2591 shade), or a width is off by one.
        foreach ($width in @(120, 79, 59, 40, 30, 20, 12, 8)) {
            $line = Format-TpmProgressLine -Title 'Checking' -Stage 'your games for PostgreSQL' -Current 3 -Total 10 -ElapsedSeconds 2 -Width $width -Style Block
            $line.Length | Should -Be $width
            $line | Should -Not -Match '[^\x20-\x7E\u2588\u00B7]'
            $line | Should -Not -Match '#'
        }
    }

    It 'shows the bar in both glyphs once the window is wide enough for it' {
        # Mutation: the Block bar is dropped from the layout.
        $line = Format-TpmProgressLine -Title '' -Stage 'Checking your games for PostgreSQL' -Current 3 -Total 10 -ElapsedSeconds 2 -Width 100 -Style Block
        $line | Should -Match ('\|' + $script:full + '+' + $script:empty + '+\|')
        $line | Should -Match '\[30%\]'
    }

    It 'truncates a very long label instead of the bar or the percent' {
        # Mutation: the label is allowed to push the bar or the percent out of a narrow line.
        $line = Format-TpmProgressLine -Title '' -Stage ('Checking ' + ('x' * 200)) -Current 3 -Total 10 -ElapsedSeconds 2 -Width 60 -Style Block
        $line.Length | Should -Be 60
        $line | Should -Match '\.\.\.'
        $line | Should -Match $script:full
        $line | Should -Match '\[30%\]'
    }
}

Describe 'FIX105 which look a console gets' {
    BeforeEach {
        Set-Fix105DefaultMocks
        $script:savedEnv = @{ Style = $env:TPM_PROGRESS_STYLE; Wt = $env:WT_SESSION; Term = $env:TERM_PROGRAM }
        $env:TPM_PROGRESS_STYLE = $null; $env:WT_SESSION = $null; $env:TERM_PROGRAM = $null
        Mock Test-TpmProgressOutputRedirected { $false } -ModuleName TpmProgress
        Mock Test-TpmProgressWideWriteAvailable { $true } -ModuleName TpmProgress
        Mock Get-TpmProgressOutputCodePage { 437 } -ModuleName TpmProgress
        Mock Test-TpmProgressConhostFont { $false } -ModuleName TpmProgress
        Mock Test-TpmProgressGlyphCells { $true } -ModuleName TpmProgress
        InModuleScope TpmProgress { $script:TpmProgressGlyphCells = $null }
    }
    AfterEach {
        $env:TPM_PROGRESS_STYLE = $script:savedEnv.Style; $env:WT_SESSION = $script:savedEnv.Wt; $env:TERM_PROGRAM = $script:savedEnv.Term
        InModuleScope TpmProgress { $script:TpmProgressGlyphCells = $null }
    }

    It 'gives the solid bar to an interactive console whose font is not verified (the Windows Sandbox case)' {
        # Mutation: Get-TpmProgressStyle returns Ascii whenever the full glyph set is not verified.
        Get-TpmProgressStyle | Should -BeExactly 'Block'
    }

    It 'gives the full glyph set to a verified host' {
        # Mutation: the Block branch is checked before the Unicode check.
        Mock Test-TpmProgressConhostFont { $true } -ModuleName TpmProgress
        Get-TpmProgressStyle | Should -BeExactly 'Unicode'
    }

    It 'keeps ASCII for redirected or captured output' {
        # Mutation: the redirected check is dropped from Test-TpmProgressGlyphOutputUsable.
        Mock Test-TpmProgressOutputRedirected { $true } -ModuleName TpmProgress
        Get-TpmProgressStyle | Should -BeExactly 'Ascii'
    }

    It 'keeps ASCII on a CJK double-byte code page, where block glyphs can take two cells' {
        # Mutation: Test-TpmProgressBlockBarUsable no longer asks about CJK code pages.
        Mock Get-TpmProgressOutputCodePage { 932 } -ModuleName TpmProgress
        Get-TpmProgressStyle | Should -BeExactly 'Ascii'
    }

    It 'keeps ASCII after a host was measured to draw glyphs two cells wide' {
        # Mutation: Test-TpmProgressBlockBarUsable ignores the measured glyph result.
        InModuleScope TpmProgress { $script:TpmProgressGlyphCells = $false }
        Get-TpmProgressStyle | Should -BeExactly 'Ascii'
    }

    It 'needs the UTF-16 console write or a UTF-8 code page to give any glyph' {
        # Mutation: the write-path check is dropped, so an OEM code page without UTF-16 writes gets glyphs.
        Mock Test-TpmProgressWideWriteAvailable { $false } -ModuleName TpmProgress
        Get-TpmProgressStyle | Should -BeExactly 'Ascii'
        Mock Get-TpmProgressOutputCodePage { 65001 } -ModuleName TpmProgress
        Get-TpmProgressStyle | Should -BeExactly 'Block'
    }

    It 'lets TPM_PROGRESS_STYLE=ascii force the plain look on any console' {
        # Mutation: the explicit ascii override is ignored.
        $env:TPM_PROGRESS_STYLE = 'ascii'
        Get-TpmProgressStyle | Should -BeExactly 'Ascii'
    }
}

Describe 'FIX105 the rate is measured, or left out' {
    BeforeEach { Set-Fix105DefaultMocks }

    It 'leaves the rate out when the step is shorter than one second' {
        # Mutation: Get-TpmProgressTaskRate drops the one-second minimum (1 item in 0.2 s would read 5.00/s).
        InModuleScope TpmProgress {
            $task = [pscustomobject]@{ NoCount = $false; Current = 1; StageFirstCurrent = 0 }
            Get-TpmProgressTaskRate -Task $task -ElapsedSeconds 0.2 | Should -Be -1
            Get-TpmProgressTaskRate -Task $task -ElapsedSeconds 0.99 | Should -Be -1
        }
    }

    It 'computes the rate from the real finished count since the stage began and the real elapsed time' {
        # Mutation: the rate uses the smoothed value or the whole count instead of the count since the stage began.
        InModuleScope TpmProgress {
            Get-TpmProgressTaskRate -Task ([pscustomobject]@{ NoCount = $false; Current = 10; StageFirstCurrent = 0 }) -ElapsedSeconds 2 | Should -Be 5
            Get-TpmProgressTaskRate -Task ([pscustomobject]@{ NoCount = $false; Current = 6; StageFirstCurrent = 4 }) -ElapsedSeconds 2 | Should -Be 1
        }
    }

    It 'leaves the rate out when nothing has finished yet, or when the closing line has no count' {
        # Mutation: a zero-finished step shows 0.00/s, or a count-less group close shows a made-up rate.
        InModuleScope TpmProgress {
            Get-TpmProgressTaskRate -Task ([pscustomobject]@{ NoCount = $false; Current = 4; StageFirstCurrent = 4 }) -ElapsedSeconds 9 | Should -Be -1
            Get-TpmProgressTaskRate -Task ([pscustomobject]@{ NoCount = $true; Current = 1; StageFirstCurrent = 0 }) -ElapsedSeconds 9 | Should -Be -1
        }
    }

    It 'prints the time alone for an unmeasured rate and the rate after it for a measured one' {
        # Mutation: Format-TpmProgressElapsed always appends the rate.
        InModuleScope TpmProgress {
            Format-TpmProgressElapsed -ElapsedSeconds 0.2 -Rate -1 | Should -BeExactly 'in 0.2s'
            Format-TpmProgressElapsed -ElapsedSeconds 5 -Rate 0.3333 | Should -BeExactly 'in 5.0s (0.33/s)'
        }
    }

    It 'does not repeat the smoothed 0.33/s for one item finished in 0.2 s (the reported line)' {
        # Mutation: Get-TpmProgressLineSegments passes $Op.SmoothedRate again.
        InModuleScope TpmProgress {
            $now = [datetime]'2026-01-01T00:00:10'
            $op = [pscustomobject]@{
                Title = ''; Stage = 'Checking your games for PostgreSQL'; Current = 1; Total = 1; Tick = 0; Unit = 'Items'; NoCount = $false
                Columns = @('Description', 'Bar', 'Percentage', 'Count', 'Elapsed', 'Remaining', 'Spinner'); EtaHidden = $false
                StageFirstCurrent = 0; StageSamples = 1; SmoothedRate = 0.3333; PauseStarted = $null; Finished = $now; Group = $false
                Started = $now.AddSeconds(-0.2); StageStarted = $now.AddSeconds(-0.2)
            }
            $text = (@(Get-TpmProgressLineSegments -Op $op -State Final -Now $now -Width 110 -Style Block) | ForEach-Object { $_.Text }) -join ''
            $text | Should -Match '\[100%\]'
            $text | Should -Match 'in 0\.2s'
            $text | Should -Not -Match '/s\)'
            $text | Should -Not -Match '0\.33'
        }
    }

    It 'shows a measured rate for a step that took real time' {
        # Mutation: the rate is hidden for every step.
        InModuleScope TpmProgress {
            $now = [datetime]'2026-01-01T00:00:10'
            $op = [pscustomobject]@{
                Title = ''; Stage = 'Copying'; Current = 10; Total = 10; Tick = 0; Unit = 'Items'; NoCount = $false
                Columns = @('Description', 'Bar', 'Percentage', 'Count', 'Elapsed', 'Remaining', 'Spinner'); EtaHidden = $false
                StageFirstCurrent = 0; StageSamples = 1; SmoothedRate = 0.0; PauseStarted = $null; Finished = $now; Group = $false
                Started = $now.AddSeconds(-4); StageStarted = $now.AddSeconds(-4)
            }
            $text = (@(Get-TpmProgressLineSegments -Op $op -State Final -Now $now -Width 110 -Style Block) | ForEach-Object { $_.Text }) -join ''
            $text | Should -Match 'in 4\.0s \(2\.50/s\)'
        }
    }
}

Describe 'FIX105 no stray status mark and no repeated words' {
    BeforeEach { Set-Fix105DefaultMocks }

    It 'ends a finished ASCII or Block line with the word done, not a plus sign' {
        # Mutation: the Final status mark is '+' again for non-Unicode styles.
        foreach ($style in @('Ascii', 'Block')) {
            $line = Format-TpmProgressLine -Title '' -Stage 'Checking your games' -Current 1 -Total 1 -State Final -ElapsedSeconds 0.2 -Width 100 -Style $style
            $line.TrimEnd() | Should -Match 'done$'
            $line | Should -Not -Match '\+'
        }
    }

    It 'keeps the check mark for the full glyph set' {
        # Mutation: the Unicode check mark is removed together with the ASCII plus.
        $line = Format-TpmProgressLine -Title '' -Stage 'Checking your games' -Current 1 -Total 1 -State Final -ElapsedSeconds 0.2 -Width 100 -Style Unicode
        $line.TrimEnd() | Should -Match ($script:tick + '$')
    }

    It 'joins a title and a stage once, and shows the stage alone when there is no title' {
        # Mutation: Get-TpmProgressLabelText always prefixes "<title>: ", also for a blank title.
        InModuleScope TpmProgress {
            Get-TpmProgressLabelText -Title 'Scanning' -Stage 'Copying' | Should -BeExactly 'Scanning: Copying'
            Get-TpmProgressLabelText -Title '' -Stage 'Checking your games' | Should -BeExactly 'Checking your games'
            Get-TpmProgressLabelText -Title 'Scanning' -Stage '' | Should -BeExactly 'Scanning'
        }
        $line = Format-TpmProgressLine -Title '' -Stage 'Checking your games' -Current 1 -Total 2 -Width 100 -Style Block
        $line | Should -Match '^\s*Checking your games \|'
        $line | Should -Not -Match ':'
    }
}

Describe 'FIX105 one step is one bar on a live console' {
    BeforeEach {
        Set-Fix105DefaultMocks
        $global:TpmUiNow = [datetime]'2026-01-01T00:00:00'
        $global:TpmUiRaw = New-Object System.Text.StringBuilder
        Mock Get-TpmProgressNow { $global:TpmUiNow } -ModuleName TpmProgress
        Mock Get-TpmProgressTimestamp { 0 } -ModuleName TpmProgress
        Mock Test-TpmProgressOutputRedirected { $false } -ModuleName TpmProgress
        Mock Test-TpmProgressColorEnabled { $false } -ModuleName TpmProgress
        Mock Get-TpmProgressStyle { 'Block' } -ModuleName TpmProgress
        Mock Test-TpmProgressWideWriteAvailable { $false } -ModuleName TpmProgress
        Mock Get-TpmProgressWidth { 100 } -ModuleName TpmProgress
        Mock Get-TpmProgressCursor { [pscustomobject]@{ Left = 0; Top = 7 } } -ModuleName TpmProgress
        Mock Write-TpmProgressRaw { [void]$global:TpmUiRaw.Append($Text) } -ModuleName TpmProgress
        Mock Get-TpmProgressBufferWidth { 101 } -ModuleName TpmProgress
        Mock Get-TpmProgressWindowHeight { 30 } -ModuleName TpmProgress
        Mock Get-TpmProgressBackground { 'Black' } -ModuleName TpmProgress
        Mock Clear-TpmProgressCells { $true } -ModuleName TpmProgress
        Mock Set-TpmProgressCursor { $true } -ModuleName TpmProgress
    }
    AfterEach {
        Stop-TpmProgressAbandoned
        Remove-Variable -Name TpmUiNow, TpmUiRaw -Scope Global -ErrorAction SilentlyContinue
    }

    It 'writes solid-bar frames and no # characters while a step runs' {
        # Mutation: Start-TpmProgressOperation does not take the style from Get-TpmProgressStyle, or Block draws '#'.
        Start-TpmProgressOperation -Title '' -Stage 'Checking your games' -Total 10 | Out-Null
        $global:TpmUiNow = $global:TpmUiNow.AddSeconds(1)
        Set-TpmProgressStage -Stage 'Checking your games' -Current 5 -Total 10
        $text = $global:TpmUiRaw.ToString()
        $text | Should -Match $script:full
        $text | Should -Not -Match $script:shade
        $text | Should -Not -Match '#'
    }

    It 'leaves one finished row for a measured step' {
        # Mutation: the transient-close rule also clears rows of steps that have a known total.
        Start-TpmProgressOperation -Title '' -Stage 'Checking your games' -Total 1 | Out-Null
        $global:TpmUiNow = $global:TpmUiNow.AddMilliseconds(200)
        Set-TpmProgressStage -Stage 'Checking your games' -Current 1 -Total 1 -SameStage
        Complete-TpmProgressOperation -State Final
        Should -Invoke Write-TpmProgressRaw -ModuleName TpmProgress -ParameterFilter { $Text -like "`r*`r`n" } -Times 1 -Exactly
        $global:TpmUiRaw.ToString() | Should -Match '\[100%\]'
    }

    It 'removes the row of a finished step that only counted (no known total)' {
        # Mutation: Test-TpmProgressTransientClose returns false, so the empty "Scanning" bar stays on screen.
        Start-TpmProgressOperation -Title '' -Stage 'Checking your games' -Total 0 | Out-Null
        $global:TpmUiNow = $global:TpmUiNow.AddMilliseconds(100)
        Set-TpmProgressStage -Stage 'Checking your games' -Current 1 -Total 0
        Complete-TpmProgressOperation -State Final
        Should -Invoke Write-TpmProgressRaw -ModuleName TpmProgress -ParameterFilter { $Text -like "`r*`r`n" } -Times 0 -Exactly
        Should -Invoke Clear-TpmProgressCells -ModuleName TpmProgress -ParameterFilter { $Top -eq 7 } -Times 1
    }

    It 'leaves exactly one row when a counting scan is followed by the measured check of the same step' {
        # Mutation: the scan closes with a printed row, so the screen shows two bars for one step (the reported bug).
        Start-TpmProgressOperation -Title '' -Stage 'Checking your games' -Total 0 | Out-Null
        Set-TpmProgressStage -Stage 'Checking your games' -Current 1 -Total 0
        Complete-TpmProgressOperation -State Final
        $global:TpmUiNow = $global:TpmUiNow.AddSeconds(1)
        Start-TpmProgressOperation -Title '' -Stage 'Checking your games' -Total 1 | Out-Null
        Set-TpmProgressStage -Stage 'Checking your games' -Current 1 -Total 1 -SameStage
        Complete-TpmProgressOperation -State Final
        Should -Invoke Write-TpmProgressRaw -ModuleName TpmProgress -ParameterFilter { $Text -like "`r*`r`n" } -Times 1 -Exactly
    }

    It 'keeps the row of a step with no known total that failed' {
        # Mutation: Test-TpmProgressTransientClose ignores the close state, so a failed scan vanishes.
        Start-TpmProgressOperation -Title '' -Stage 'Checking your games' -Total 0 | Out-Null
        Set-TpmProgressStage -Stage 'Checking your games' -Current 1 -Total 0
        Complete-TpmProgressOperation -State Error
        Should -Invoke Write-TpmProgressRaw -ModuleName TpmProgress -ParameterFilter { $Text -like "`r*`r`n" -and $Text -match 'FAILED' } -Times 1 -Exactly
    }

    It 'only treats a finished, ungrouped, task-less, size-less step as transient' {
        # Mutation: any one of the four conditions in Test-TpmProgressTransientClose is dropped.
        InModuleScope TpmProgress {
            $plain = [pscustomobject]@{ Group = $false; Total = 0; Tasks = (New-Object System.Collections.Generic.List[object]) }
            Test-TpmProgressTransientClose -Op $plain -State Final | Should -BeTrue
            Test-TpmProgressTransientClose -Op $plain -State 'No-op' | Should -BeTrue
            Test-TpmProgressTransientClose -Op $plain -State Error | Should -BeFalse
            Test-TpmProgressTransientClose -Op $plain -State Incomplete | Should -BeFalse
            Test-TpmProgressTransientClose -Op ([pscustomobject]@{ Group = $true; Total = 0; Tasks = $plain.Tasks }) -State Final | Should -BeFalse
            Test-TpmProgressTransientClose -Op ([pscustomobject]@{ Group = $false; Total = 5; Tasks = $plain.Tasks }) -State Final | Should -BeFalse
            $busy = New-Object System.Collections.Generic.List[object]; $busy.Add('task')
            Test-TpmProgressTransientClose -Op ([pscustomobject]@{ Group = $false; Total = 0; Tasks = $busy }) -State Final | Should -BeFalse
        }
    }
}

Describe 'FIX105 the product wrapper says the step once' {
    BeforeAll {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path (Join-Path $PSScriptRoot '..') 'TeknoParrot-Manager.ps1'), [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) { throw 'Failed to parse TeknoParrot-Manager.ps1.' }
        foreach ($name in @('Write-TpmCompactExtractionProgress', 'Get-TpmFriendlyProgressLabel')) {
            $found = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true))
            if ($found.Count -ne 1) { throw "Expected exactly one $name." }
            . ([scriptblock]::Create($found[0].Extent.Text))
        }
        # Recording stand-ins for the renderer and the log; the real wrapper and the real label table are under test.
        function Import-TpmProgressModule {}
        function Write-Log { param($Message) }
        function Test-TpmProgressActive { return [bool]$script:fxActive }
        function Test-TpmProgressGroupOwned { return [bool]$script:fxGroup }
        function Get-TpmProgressTitle { return $script:fxTitle }
        function Register-TpmProgressOutcome { param($State) }
        function Start-TpmProgressOperation {
            param([AllowEmptyString()]$Title, $Stage, $Total, $Width, [switch]$Group, $Unit = 'Items')
            $script:fxActive = $true; $script:fxTitle = $Title
            [void]$script:fxEvents.Add([pscustomobject]@{ Kind = 'Start'; Title = $Title; Stage = $Stage })
        }
        function Set-TpmProgressStage {
            param([string]$Stage, [long]$Current, [long]$Total, [switch]$StageOnly, $Unit = 'Items', [switch]$SameStage)
            [void]$script:fxEvents.Add([pscustomobject]@{ Kind = 'Stage'; Title = $null; Stage = $Stage })
        }
        function Complete-TpmProgressOperation {
            param($State = 'Final', $Message = '', [switch]$Superseded)
            [void]$script:fxEvents.Add([pscustomobject]@{ Kind = 'Complete'; Title = $null; Stage = $null })
            $script:fxActive = $false
        }
        function Format-TpmProgressLine { param([AllowEmptyString()]$Title, $Stage, $Current, $Total, $ElapsedSeconds, $Width, $Unit = 'Items') return ('[{0}] {1}' -f $Title, $Stage) }
        function Get-TpmProgressWidth { param($Requested) return 80 }
    }
    BeforeEach {
        $script:fxEvents = New-Object System.Collections.Generic.List[object]
        $script:fxActive = $false; $script:fxGroup = $false; $script:fxTitle = $null
    }

    It 'opens the bar of a plain-worded step with no phase word in front of the label' {
        # Mutation: the wrapper passes -Title $Phase for a mapped label, giving "Scanning: Checking your games for PostgreSQL".
        Write-TpmCompactExtractionProgress -Phase Scanning -Label 'PostgreSQL backup file discovery' -Current 0 -Total 0
        $start = @($script:fxEvents | Where-Object Kind -eq 'Start')[0]
        $start.Stage | Should -BeExactly 'Checking your games for PostgreSQL'
        $start.Title | Should -BeExactly ''
    }

    It 'keeps the phase word in front of a label that has no plain wording' {
        # Mutation: the phase word is dropped for every label, so unmapped technical labels lose their verb.
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Some unmapped fixture step' -Current 1 -Total 2
        @($script:fxEvents | Where-Object Kind -eq 'Start')[0].Title | Should -BeExactly 'Checking'
    }

    It 'continues the same bar when the phase changes but the plain step is the same' {
        # Mutation: the wrapper compares the open title with $Phase, so the phase change closes the bar and opens a second one.
        Write-TpmCompactExtractionProgress -Phase Scanning -Label 'PostgreSQL backup file discovery' -Current 1 -Total 0
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'PostgreSQL backup file discovery' -Current 1 -Total 3
        @($script:fxEvents | Where-Object Kind -eq 'Complete').Count | Should -Be 0
        @($script:fxEvents | Where-Object Kind -eq 'Start').Count | Should -Be 1
    }

    It 'still closes a bar that an unmapped step replaces under a new phase' {
        # Mutation: the supersede rule is removed for unmapped labels.
        Write-TpmCompactExtractionProgress -Phase Scanning -Label 'Some unmapped fixture step' -Current 1 -Total 0
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Another unmapped fixture step' -Current 1 -Total 3
        @($script:fxEvents | Where-Object Kind -eq 'Complete').Count | Should -Be 1
        @($script:fxEvents | Where-Object Kind -eq 'Start').Count | Should -Be 2
    }

    It 'does not put the phase in front of a plain label on a group-owned bar either' {
        # Mutation: the group stage text is always "$Phase $Label", giving "Checking Checking your games for PostgreSQL".
        $script:fxActive = $true; $script:fxGroup = $true
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'PostgreSQL backup file discovery' -Current 1 -Total 3
        @($script:fxEvents | Where-Object Kind -eq 'Stage')[0].Stage | Should -BeExactly 'Checking your games for PostgreSQL'
        $script:fxEvents.Clear()
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Some unmapped fixture step' -Current 1 -Total 3
        @($script:fxEvents | Where-Object Kind -eq 'Stage')[0].Stage | Should -BeExactly 'Checking Some unmapped fixture step'
    }

    It 'returns text without a phase prefix for a plain label' {
        # Mutation: the -ReturnText path still passes the phase as the title.
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'PostgreSQL backup file discovery' -Current 1 -Total 3 -ReturnText |
            Should -BeExactly '[] Checking your games for PostgreSQL'
    }
}

Describe 'FIX105 the preview script accepts every style the product can choose' {
    BeforeAll {
        $previewPath = Join-Path (Join-Path $PSScriptRoot '..\scripts') 'Preview-TPM-ProgressStyles.ps1'
        $tokens = $null
        $parseErrors = $null
        $script:previewAst = [System.Management.Automation.Language.Parser]::ParseFile($previewPath, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) { throw 'Failed to parse Preview-TPM-ProgressStyles.ps1.' }
        $gallery = @($script:previewAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Show-WidthGallery' }, $true))
        if ($gallery.Count -ne 1) { throw 'Expected exactly one Show-WidthGallery.' }
        . ([scriptblock]::Create($gallery[0].Extent.Text))
        function Write-Section { param([string]$Text) }
        # Every style the renderer accepts (and so every one Get-TpmProgressStyle can return), read from its own parameter.
        $script:productStyles = @((Get-Command Format-TpmProgressLine).Parameters['Style'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } | ForEach-Object { $_.ValidValues })
    }
    BeforeEach { Set-Fix105DefaultMocks }

    It 'draws the width gallery for Ascii, Block and Unicode without throwing' {
        # Mutation: Show-WidthGallery's ValidateSet lacks Block, so preview -Style Auto throws on an unverified console.
        foreach ($style in $script:productStyles) {
            $script:galleryOut = New-Object System.Collections.Generic.List[string]
            Mock Write-Host { [void]$script:galleryOut.Add([string]$Object) }
            { Show-WidthGallery -GalleryStyle $style } | Should -Not -Throw
            ($script:galleryOut -join "`n") | Should -Match 'width 120'
        }
    }

    It 'draws solid bars in the Block gallery and no # characters' {
        # Mutation: the gallery formats Block lines with the Ascii style.
        $script:galleryOut = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$script:galleryOut.Add([string]$Object) }
        Show-WidthGallery -GalleryStyle Block
        $text = $script:galleryOut -join "`n"
        $text | Should -Match $script:full
        $text | Should -Not -Match $script:shade
        $text | Should -Not -Match '#'
    }

    It 'lets the preview -Style parameter name every style the product can choose' {
        # Mutation: the script's -Style ValidateSet drops Block (or any style) while the product can still return it.
        $styleParam = @($script:previewAst.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Style' })[0]
        $validate = @($styleParam.Attributes | Where-Object { $_.TypeName.Name -eq 'ValidateSet' })[0]
        $allowed = @($validate.PositionalArguments | ForEach-Object { $_.Value })
        foreach ($style in $script:productStyles) { $allowed | Should -Contain $style }
    }

    It 'forces the solid bar when TPM_PROGRESS_STYLE=block, which the preview sets for its live demo' {
        # Mutation: Get-TpmProgressStyle ignores "block", so the live demo silently draws another look.
        $saved = $env:TPM_PROGRESS_STYLE
        try {
            $env:TPM_PROGRESS_STYLE = 'block'
            Mock Test-TpmProgressUnicodeVerified { $true } -ModuleName TpmProgress
            Get-TpmProgressStyle | Should -BeExactly 'Block'
        } finally { $env:TPM_PROGRESS_STYLE = $saved }
    }
}
