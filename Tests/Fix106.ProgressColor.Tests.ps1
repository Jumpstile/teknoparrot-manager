#Requires -Module Pester

# FIX106: the progress bars are solid blocks whose COLOR follows progress, with a look for every state. The one renderer
# (scripts\TpmProgress.psm1) is tested with fakes only: console seams are mocked, so nothing here touches a real console,
# an install, the registry or the network. Glyphs are built at run time; this file is pure ASCII.

BeforeAll {
    $script:modulePath = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $PSScriptRoot '..\scripts') 'TpmProgress.psm1'))
    Get-Module -Name TpmProgress -All | Remove-Module -Force
    Import-Module $script:modulePath -Force -ErrorAction Stop
    $script:full = [string][char]0x2588
    $script:shade = [string][char]0x2591
    $script:dot = [string][char]0x00B7
    $script:tick = [string][char]0x2713
    $script:warn = [string][char]0x26A0
    $script:cross = [string][char]0x2717
    $script:square = [string][char]0x25A0
    $script:right = [string][char]0x25B6
    $script:esc = [string][char]27

    InModuleScope TpmProgress {
        # The glyphs again, in the module's own scope (the blocks below run there).
        $script:full = [string][char]0x2588
        $script:shade = [string][char]0x2591
        $script:dot = [string][char]0x00B7
        $script:tick = [string][char]0x2713
        $script:warn = [string][char]0x26A0
        $script:cross = [string][char]0x2717
        $script:square = [string][char]0x25A0
        $script:right = [string][char]0x25B6
        # A composed row as the live writer builds it: the segments of one line plus the state and percent that choose colors.
        function script:New-Fix106Row {
            param(
                [string]$State = 'Running', [long]$Current = 0, [long]$Total = 100, [string]$Style = 'Unicode',
                [double]$Elapsed = 10, [double]$Eta = -1, [double]$Rate = -1, [int]$Tick = 0, [int]$Width = 110
            )
            $segments = @(Format-TpmProgressSegments -Title '' -Stage 'Copying' -Current $Current -Total $Total -State $State -ElapsedSeconds $Elapsed -EtaSeconds $Eta -Rate $Rate -Width $Width -Tick $Tick -Style $Style)
            return [pscustomobject]@{
                Segments = $segments
                State = $(if ($Total -gt 0 -and $Current -gt $Total) { 'Error' } else { $State })
                Percent = $(if ($Total -gt 0) { 100.0 * $Current / $Total } else { -1 })
                Cells = $Width
                Text = (-join @(foreach ($segment in $segments) { $segment.Text }))
            }
        }
        # The colored runs of a frame: every ESC [ <params> m starts a run whose text follows it.
        function script:Get-Fix106Runs {
            param([string]$Frame)
            $runs = New-Object System.Collections.Generic.List[object]
            $pieces = $Frame -split ([regex]::Escape([string][char]27) + '\[')
            for ($index = 1; $index -lt $pieces.Count; $index++) {
                $end = $pieces[$index].IndexOf('m')
                [void]$runs.Add([pscustomobject]@{ Sgr = $pieces[$index].Substring(0, $end); Text = $pieces[$index].Substring($end + 1) })
            }
            return $runs.ToArray()
        }
        function script:Get-Fix106Frame {
            param($Row, [string]$ColorMode)
            return (ConvertTo-TpmProgressFrameText -Rows @($Row) -ColorMode $ColorMode -Background Black)
        }
    }

    # A console that takes VT sequences, with a known foreground. Test-TpmProgressColorEnabled is left real on purpose: it reads
    # NO_COLOR, TPM_PROGRESS_COLOR, TERM and the redirection mock.
    function Set-Fix106ConsoleMocks {
        Mock Test-TpmProgressOutputRedirected { $false } -ModuleName TpmProgress
        Mock Test-TpmProgressVt { $true } -ModuleName TpmProgress
        Mock Get-TpmProgressForeground { [System.ConsoleColor]::Gray } -ModuleName TpmProgress
    }
}

AfterAll {
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
}

Describe 'FIX106 which color a console gets' {
    BeforeEach {
        $script:savedEnv = @{ Wt = $env:WT_SESSION; Term = $env:TERM_PROGRAM; NoColor = $env:NO_COLOR; Color = $env:TPM_PROGRESS_COLOR; TermName = $env:TERM }
        $env:WT_SESSION = $null; $env:TERM_PROGRAM = $null; $env:NO_COLOR = $null; $env:TPM_PROGRESS_COLOR = $null; $env:TERM = $null
        Set-Fix106ConsoleMocks
    }
    AfterEach {
        $env:WT_SESSION = $script:savedEnv.Wt; $env:TERM_PROGRAM = $script:savedEnv.Term; $env:NO_COLOR = $script:savedEnv.NoColor
        $env:TPM_PROGRESS_COLOR = $script:savedEnv.Color; $env:TERM = $script:savedEnv.TermName
    }

    It 'gives true color to Windows Terminal, and the 16-color version when TPM_PROGRESS_COLOR=quantized asks for it' {
        # Mutation: the quantized override is ignored, or Windows Terminal is not given RGB.
        $env:WT_SESSION = 'fixture-session'
        InModuleScope TpmProgress { Get-TpmProgressColorMode -Background 'Black' } | Should -BeExactly 'TrueColor'
        $env:TPM_PROGRESS_COLOR = 'quantized'
        InModuleScope TpmProgress { Get-TpmProgressColorMode -Background 'Black' } | Should -BeExactly 'Vt16'
    }

    It 'gives true color to a plain console that takes virtual terminal sequences' {
        # Mutation: only WT_SESSION (not a plain console with VT) selects true color.
        InModuleScope TpmProgress { Get-TpmProgressColorMode -Background 'Black' } | Should -BeExactly 'TrueColor'
    }

    It 'falls back to the console''s own 16 colors without virtual terminal support, and to none when the host color is unknown' {
        # Mutation: a console without VT gets no color at all, or Console16 is chosen although the foreground cannot be restored.
        Mock Test-TpmProgressVt { $false } -ModuleName TpmProgress
        InModuleScope TpmProgress { Get-TpmProgressColorMode -Background 'Black' } | Should -BeExactly 'Console16'
        Mock Get-TpmProgressForeground { $null } -ModuleName TpmProgress
        InModuleScope TpmProgress { Get-TpmProgressColorMode -Background 'Black' } | Should -BeExactly 'None'
    }

    It 'never colors redirected output, even inside Windows Terminal' {
        # Mutation: the redirected check is dropped from the decision.
        $env:WT_SESSION = 'fixture-session'
        Mock Test-TpmProgressOutputRedirected { $true } -ModuleName TpmProgress
        InModuleScope TpmProgress { Get-TpmProgressColorMode -Background 'Black' } | Should -BeExactly 'None'
    }

    It 'turns color off for NO_COLOR and TPM_PROGRESS_COLOR=off, but an empty NO_COLOR does not' {
        # Mutation: Get-TpmProgressColorMode does not ask Test-TpmProgressColorEnabled, or an empty NO_COLOR counts as set.
        $env:NO_COLOR = '1'
        InModuleScope TpmProgress { Get-TpmProgressColorMode -Background 'Black' } | Should -BeExactly 'None'
        $env:NO_COLOR = ''
        InModuleScope TpmProgress { Get-TpmProgressColorMode -Background 'Black' } | Should -BeExactly 'TrueColor'
        $env:NO_COLOR = $null
        $env:TPM_PROGRESS_COLOR = 'off'
        InModuleScope TpmProgress { Get-TpmProgressColorMode -Background 'Black' } | Should -BeExactly 'None'
    }

    It 'gives no color when the console background is not known' {
        # Mutation: an unknown background still gets color (it could make any chosen color unreadable).
        InModuleScope TpmProgress { Get-TpmProgressColorMode -Background $null } | Should -BeExactly 'None'
    }
}

Describe 'FIX106 NO_COLOR keeps the bar readable' {
    BeforeEach {
        $script:savedNoColor = $env:NO_COLOR
        $env:NO_COLOR = '1'
        Set-Fix106ConsoleMocks
    }
    AfterEach { $env:NO_COLOR = $script:savedNoColor }

    It 'writes no escape sequences but keeps the block bar, the count, the percent and the word' {
        # Mutation: the None mode still writes SGR sequences, or drops the bar, the count, the percent or the word.
        $mode = InModuleScope TpmProgress { Get-TpmProgressColorMode -Background 'Black' }
        $mode | Should -BeExactly 'None'
        $frame = InModuleScope TpmProgress -Parameters @{ Mode = $mode } {
            Get-Fix106Frame -Row (New-Fix106Row -State Final -Current 100 -Total 100) -ColorMode $Mode
        }
        $frame | Should -Not -Match ([regex]::Escape($script:esc))
        $frame | Should -Match '100/100'
        $frame | Should -Match '\[100%\]'
        $frame | Should -Match 'done'
        $frame | Should -Match $script:full
    }
}

Describe 'FIX106 the console mode is switched on by the renderer and put back' {
    BeforeEach {
        $script:savedWt = $env:WT_SESSION; $env:WT_SESSION = $null
        $script:fakeMode = [uint32]3
        $script:fakeAllowSet = $true
        Mock Test-TpmProgressOutputRedirected { $false } -ModuleName TpmProgress
        Mock Test-TpmProgressColorEnabled { $true } -ModuleName TpmProgress
        Mock Get-TpmProgressForeground { [System.ConsoleColor]::Gray } -ModuleName TpmProgress
        Mock Get-TpmProgressConsoleMode { $script:fakeMode } -ModuleName TpmProgress
        Mock Set-TpmProgressConsoleMode { param($Mode) if ($script:fakeAllowSet) { $script:fakeMode = [uint32]$Mode; return $true }; return $false } -ModuleName TpmProgress
        InModuleScope TpmProgress { $script:TpmProgressVtReady = $null; $script:TpmProgressVtOwned = $false }
    }
    AfterEach {
        $env:WT_SESSION = $script:savedWt
        InModuleScope TpmProgress { $script:TpmProgressVtReady = $null; $script:TpmProgressVtOwned = $false }
    }

    It 'enables VT on a plain console for true color and restores the old mode on exit' {
        # Mutation: the decision never turns VT on (mode stays 3), or Restore-TpmProgressVt leaves the bit set.
        $mode = InModuleScope TpmProgress { Get-TpmProgressColorMode -Background 'Black' }
        $mode | Should -BeExactly 'TrueColor'
        $script:fakeMode | Should -Be 7
        InModuleScope TpmProgress { Restore-TpmProgressVt }
        $script:fakeMode | Should -Be 3
    }

    It 'uses the console''s own colors when VT cannot be turned on' {
        # Mutation: a failed SetConsoleMode still reports VT as ready.
        $script:fakeAllowSet = $false
        InModuleScope TpmProgress { Get-TpmProgressColorMode -Background 'Black' } | Should -BeExactly 'Console16'
        $script:fakeMode | Should -Be 3
    }
}

Describe 'FIX106 the fill color follows progress' {
    It 'is exactly the anchor color at 0, 10, 20, 45, 50, 70, 85 and 100 percent' {
        # Mutation: an anchor RGB or its percent changes, or the gradient is clamped to different ends.
        InModuleScope TpmProgress {
            $anchors = @(
                @{ P = 0; Rgb = '255,140,30' }, @{ P = 10; Rgb = '255,140,30' }, @{ P = 20; Rgb = '255,140,30' },
                @{ P = 45; Rgb = '170,190,40' }, @{ P = 50; Rgb = '170,190,40' },
                @{ P = 70; Rgb = '30,200,210' }, @{ P = 85; Rgb = '30,200,210' }, @{ P = 100; Rgb = '40,230,90' }
            )
            foreach ($anchor in $anchors) {
                $color = Get-TpmProgressGradient -Percent $anchor.P -Background Black
                ('{0},{1},{2}' -f $color.Red, $color.Green, $color.Blue) | Should -BeExactly $anchor.Rgb -Because ('{0} percent' -f $anchor.P)
            }
        }
    }

    It 'changes smoothly and in one direction per channel between the anchors, with no jump' {
        # Mutation: the gradient becomes a step function, or a channel reverses inside a segment.
        InModuleScope TpmProgress {
            $segments = @(
                @{ From = 20; To = 45 }, @{ From = 50; To = 70 }, @{ From = 85; To = 100 }
            )
            foreach ($segment in $segments) {
                $start = Get-TpmProgressGradient -Percent $segment.From -Background Black
                $end = Get-TpmProgressGradient -Percent $segment.To -Background Black
                $previous = $start
                for ($percent = $segment.From + 1; $percent -le $segment.To; $percent++) {
                    $color = Get-TpmProgressGradient -Percent $percent -Background Black
                    foreach ($channel in 'Red', 'Green', 'Blue') {
                        $direction = [Math]::Sign($end.$channel - $start.$channel)
                        # FIX127: a flat channel (direction 0) must stay exactly where it started. The old check multiplied the change by 0, so it
                        # passed whatever that channel did. (No channel of these three segments is flat today; this keeps it from passing vacuously.)
                        if ($direction -eq 0) { $color.$channel | Should -Be $start.$channel -Because ('flat {0} at {1} percent' -f $channel, $percent) }
                        else { ($color.$channel - $previous.$channel) * $direction | Should -BeGreaterOrEqual 0 -Because ('{0} at {1} percent' -f $channel, $percent) }
                        # The steepest stretch (50 to 70 percent, blue +170) moves 8.5 per percent: anything above 9 is a jump.
                        [Math]::Abs($color.$channel - $previous.$channel) | Should -BeLessOrEqual 9 -Because ('{0} at {1} percent' -f $channel, $percent)
                    }
                    $previous = $color
                }
                $previous.Red | Should -Be $end.Red
                $previous.Green | Should -Be $end.Green
                $previous.Blue | Should -Be $end.Blue
            }
        }
    }

    It 'gives bars at different percentages different colors at the same moment' {
        # Mutation: every running row uses one color (the gradient is not read per row).
        InModuleScope TpmProgress {
            $rows = @(
                (New-Fix106Row -Current 10 -Total 100),
                (New-Fix106Row -Current 45 -Total 100),
                (New-Fix106Row -Current 74 -Total 100),
                (New-Fix106Row -State Final -Current 100 -Total 100)
            )
            $frame = ConvertTo-TpmProgressFrameText -Rows $rows -ColorMode TrueColor -Background Black
            $fills = @($frame -split "`r`n" | ForEach-Object { @((Get-Fix106Runs -Frame $_) | Where-Object { $_.Text.StartsWith($script:full) })[0].Sgr })
            ($fills -join '|') | Should -BeExactly '38;2;255;140;30|38;2;170;190;40|38;2;30;200;210|38;2;40;230;90'
        }
    }

    It 'maps the same gradient to the nearest of the 16 console colors, dark ones on a light background' {
        # Mutation: the 16-color mapping uses fixed bands instead of the nearest color.
        InModuleScope TpmProgress {
            $dark = @{ 10 = 'Yellow'; 20 = 'Yellow'; 45 = 'DarkYellow'; 50 = 'DarkYellow'; 70 = 'Cyan'; 85 = 'Cyan'; 100 = 'Green' }
            foreach ($percent in $dark.Keys) {
                (Get-TpmProgressGradient -Percent $percent -Background Black).Color | Should -BeExactly $dark[$percent] -Because ('{0} percent on black' -f $percent)
            }
            $light = @{ 10 = 'DarkYellow'; 45 = 'DarkYellow'; 70 = 'DarkCyan'; 100 = 'DarkGreen' }
            foreach ($percent in $light.Keys) {
                (Get-TpmProgressGradient -Percent $percent -Background White).Color | Should -BeExactly $light[$percent] -Because ('{0} percent on white' -f $percent)
            }
        }
    }
}

Describe 'FIX106 every state in true color' {
    It 'draws each state with its fill, mark, word and symbol colors' {
        # Mutation: any state keeps the running gradient (done not bright green, ended early not pale yellow with an orange sign,
        # failed not red), or a state word or symbol loses its color.
        InModuleScope TpmProgress {
            $full = $script:full
            $cases = @(
                @{ Name = 'running 74%'; State = 'Running'; Current = 74; Total = 100; Eta = 3.4; Fill = '38;2;30;200;210'; Mark = $null; MarkSgr = $null; Word = 'ETA 0:04'; Symbol = '|'; TailSgr = '96' }
                @{ Name = 'done'; State = 'Final'; Current = 100; Total = 100; Eta = -1; Fill = '38;2;40;230;90'; Mark = $null; MarkSgr = $null; Word = 'done'; Symbol = $script:tick; TailSgr = '92' }
                @{ Name = 'ended early'; State = 'Incomplete'; Current = 60; Total = 100; Eta = -1; Fill = '38;2;240;230;140'; Mark = $script:warn; MarkSgr = '38;2;255;140;30'; Word = 'incomplete'; Symbol = $script:warn; TailSgr = '93' }
                @{ Name = 'failed'; State = 'Error'; Current = 120; Total = 100; Eta = -1; Fill = '38;2;235;60;60'; Mark = $script:cross; MarkSgr = '38;2;235;60;60'; Word = 'FAILED'; Symbol = $script:cross; TailSgr = '91' }
            )
            foreach ($case in $cases) {
                $row = New-Fix106Row -State $case.State -Current $case.Current -Total $case.Total -Eta $case.Eta -Rate 7.55
                $runs = @(Get-Fix106Runs -Frame (Get-Fix106Frame -Row $row -ColorMode TrueColor))
                $fill = @($runs | Where-Object { $_.Text.StartsWith($full) })
                $fill.Count | Should -Be 1 -Because $case.Name
                $fill[0].Sgr | Should -BeExactly $case.Fill -Because $case.Name
                if ($case.Mark -and $case.State -eq 'Error') {
                    $fill[0].Text | Should -Match ('^' + $full + '+' + $case.Mark + '$') -Because $case.Name
                } elseif ($case.Mark) {
                    $mark = @($runs | Where-Object { $_.Text -ceq $case.Mark })
                    $mark.Count | Should -Be 1 -Because $case.Name
                    $mark[0].Sgr | Should -BeExactly $case.MarkSgr -Because $case.Name
                }
                $last = @($runs | Where-Object { $_.Text.Trim() })[-1]
                $last.Text | Should -Match ([regex]::Escape($case.Word) + '\s+' + [regex]::Escape($case.Symbol) + '\s*$') -Because $case.Name
                $last.Sgr | Should -BeExactly $case.TailSgr -Because $case.Name
            }
        }
    }

    It 'shows the percent in green brackets for running, done, ended early and failed' {
        # Mutation: the percent run loses its green color, or the failed percent is not the real 120.
        InModuleScope TpmProgress {
            foreach ($case in @(@{ S = 'Running'; C = 74; P = '[74%]' }, @{ S = 'Final'; C = 100; P = '[100%]' }, @{ S = 'Incomplete'; C = 60; P = '[60%]' }, @{ S = 'Error'; C = 120; P = '[120%]' })) {
                $row = New-Fix106Row -State $case.S -Current $case.C -Total 100
                $runs = @(Get-Fix106Runs -Frame (Get-Fix106Frame -Row $row -ColorMode TrueColor))
                $percent = @($runs | Where-Object { $_.Text.Trim() -ceq $case.P })
                $percent.Count | Should -Be 1 -Because $case.P
                $percent[0].Sgr | Should -BeExactly '92' -Because $case.P
            }
        }
    }

    It 'draws a skipped step as a gray dash with no fill and the word skipped in gray' {
        # Mutation: Skipped draws a fill, or loses its gray.
        InModuleScope TpmProgress {
            $row = New-Fix106Row -State Skipped -Current 0 -Total 100 -Elapsed 0 -Rate 0
            $runs = @(Get-Fix106Runs -Frame (Get-Fix106Frame -Row $row -ColorMode TrueColor))
            @($runs | Where-Object { $_.Text.Contains($script:full) }).Count | Should -Be 0
            $dash = @($runs | Where-Object { $_.Text -match '^\|-' })
            $dash.Count | Should -Be 1
            $dash[0].Sgr | Should -BeExactly '90'
            $last = @($runs | Where-Object { $_.Text.Trim() })[-1]
            $last.Text | Should -Match 'skipped\s+-\s*$'
            $last.Sgr | Should -BeExactly '90'
            $row.Text | Should -Match 'in 0\.0s \(0\.00/s\)'
        }
    }

    It 'draws an unknown total as cyan bouncing arrows with a cyan square and no percent' {
        # Mutation: the unknown total shows a percent, a fill, or a non-cyan animation or symbol.
        InModuleScope TpmProgress {
            $row = New-Fix106Row -Current 4180 -Total 0 -Elapsed 10 -Rate 418
            $row.Text | Should -Not -Match '%'
            $runs = @(Get-Fix106Runs -Frame (Get-Fix106Frame -Row $row -ColorMode TrueColor))
            $arrows = @($runs | Where-Object { $_.Text.Contains($script:right * 14) })
            $arrows.Count | Should -Be 1
            $arrows[0].Sgr | Should -BeExactly '96'
            $last = @($runs | Where-Object { $_.Text.Trim() })[-1]
            $last.Text | Should -Match ($script:square + '\s*$')
            $last.Sgr | Should -BeExactly '96'
            $row.Text | Should -Match '4180'
        }
    }

    It 'colors the solid Block look the same way (the look every interactive console gets)' {
        # Mutation: only the Unicode style is colored.
        InModuleScope TpmProgress {
            $row = New-Fix106Row -Current 74 -Total 100 -Style Block
            $runs = @(Get-Fix106Runs -Frame (Get-Fix106Frame -Row $row -ColorMode TrueColor))
            $fill = @($runs | Where-Object { $_.Text.StartsWith($script:full) })
            $fill.Count | Should -Be 1
            $fill[0].Sgr | Should -BeExactly '38;2;30;200;210'
            $fill[0].Text | Should -Not -Match $script:shade
            # The empty part is tiny dots (U+00B7) in dim gray (console color DarkGray = SGR 90), never blank and never the shade.
            $dots = @($runs | Where-Object { $_.Text.Contains($script:dot) })
            $dots.Count | Should -BeGreaterOrEqual 1
            foreach ($run in $dots) { $run.Sgr | Should -BeExactly '90' }
            $dots[0].Text | Should -Match ('^' + $script:dot + '+')
            $row.Text | Should -Not -Match $script:shade
        }
    }

    It 'gives the empty-cell dots the dim gray on every known background, not the host foreground' {
        # Mutation: the dots take the track role (host foreground on a dark background that is not black) or a state color.
        InModuleScope TpmProgress {
            foreach ($background in @('Black', 'DarkBlue', 'DarkMagenta', 'White')) {
                foreach ($state in @('Running', 'Final', 'Error', 'Stalled', 'Waiting')) {
                    Get-TpmProgressSegmentColor -Role dots -State $state -Background $background | Should -BeExactly 'DarkGray' -Because ($background + ' ' + $state)
                }
            }
            # DarkGray on a Gray background would be the background's own hue: the host foreground is used instead.
            Get-TpmProgressSegmentColor -Role dots -State Running -Background Gray | Should -BeNullOrEmpty
            (Get-TpmProgressBarGlyphs -Style Ascii).RestRole | Should -BeExactly 'rest'
            (Get-TpmProgressBarGlyphs -Style Block).RestRole | Should -BeExactly 'dots'
            @(New-TpmProgressBarSegments -Current 3 -Total 10 -BarWidth 12 -Style Ascii | Where-Object { $_.Role -eq 'dots' }).Count | Should -Be 0
        }
    }
}

Describe 'FIX106 every state in 16 colors' {
    It 'uses the nearest console colors for fill and mark, and the same state colors for words' {
        # Mutation: the 16-color frame keeps RGB sequences, or a state uses another console color.
        InModuleScope TpmProgress {
            $full = $script:full
            $cases = @(
                @{ Name = 'running 74%'; State = 'Running'; Current = 74; Total = 100; Fill = '96'; Mark = $null; MarkSgr = $null; TailSgr = '96' }
                @{ Name = 'done'; State = 'Final'; Current = 100; Total = 100; Fill = '92'; Mark = $null; MarkSgr = $null; TailSgr = '92' }
                @{ Name = 'ended early'; State = 'Incomplete'; Current = 60; Total = 100; Fill = '93'; Mark = $script:warn; MarkSgr = '33'; TailSgr = '93' }
                @{ Name = 'failed'; State = 'Error'; Current = 120; Total = 100; Fill = '91'; Mark = $null; MarkSgr = $null; TailSgr = '91' }
            )
            foreach ($case in $cases) {
                $row = New-Fix106Row -State $case.State -Current $case.Current -Total $case.Total
                $frame = Get-Fix106Frame -Row $row -ColorMode Vt16
                $frame | Should -Not -Match '38;2;' -Because $case.Name
                $runs = @(Get-Fix106Runs -Frame $frame)
                $fill = @($runs | Where-Object { $_.Text.StartsWith($full) })
                $fill.Count | Should -Be 1 -Because $case.Name
                $fill[0].Sgr | Should -BeExactly $case.Fill -Because $case.Name
                if ($case.Mark) {
                    $mark = @($runs | Where-Object { $_.Text -ceq $case.Mark })
                    $mark.Count | Should -Be 1 -Because $case.Name
                    $mark[0].Sgr | Should -BeExactly $case.MarkSgr -Because $case.Name
                }
                @($runs | Where-Object { $_.Text.Trim() })[-1].Sgr | Should -BeExactly $case.TailSgr -Because $case.Name
            }
        }
    }

    It 'draws skipped in gray and an unknown total in cyan' {
        # Mutation: skipped or unknown rows are not colored in the 16-color look.
        InModuleScope TpmProgress {
            $skipped = @(Get-Fix106Runs -Frame (Get-Fix106Frame -Row (New-Fix106Row -State Skipped -Total 100 -Elapsed 0 -Rate 0) -ColorMode Vt16))
            @($skipped | Where-Object { $_.Text -match '^\|-' })[0].Sgr | Should -BeExactly '90'
            $unknown = @(Get-Fix106Runs -Frame (Get-Fix106Frame -Row (New-Fix106Row -Current 4180 -Total 0 -Rate 418) -ColorMode Vt16))
            @($unknown | Where-Object { $_.Text.Contains($script:right * 14) })[0].Sgr | Should -BeExactly '96'
        }
    }
}

Describe 'FIX106 a console without VT sequences is colored through its own colors' {
    BeforeEach {
        InModuleScope TpmProgress {
            $script:f106Calls = New-Object System.Collections.Generic.List[object]
            Mock Set-TpmProgressForeground { param($Color) [void]$script:f106Calls.Add([pscustomobject]@{ Kind = 'color'; Value = [string]$Color }) }
            Mock Write-TpmProgressRaw { param($Text) [void]$script:f106Calls.Add([pscustomobject]@{ Kind = 'text'; Value = [string]$Text }) }
        }
    }

    It 'writes the same text in runs of one color, with no escape sequences' {
        # Mutation: Console16 writes plain text only, drops a segment, or emits SGR sequences.
        InModuleScope TpmProgress {
            $row = New-Fix106Row -Current 74 -Total 100 -Eta 3.4 -Rate 7.55
            Write-TpmProgressSegments -Rows @($row) -Prefix "`r" -ColorMode Console16 -Background Black -Foreground ([System.ConsoleColor]::Gray)
            $color = ''
            $runs = New-Object System.Collections.Generic.List[object]
            foreach ($call in $script:f106Calls) {
                if ($call.Kind -eq 'color') { $color = $call.Value } else { [void]$runs.Add([pscustomobject]@{ Color = $color; Text = $call.Value }) }
            }
            (($runs | ForEach-Object { $_.Text }) -join '') | Should -BeExactly ("`r" + $row.Text)
            (($runs | ForEach-Object { $_.Text }) -join '') | Should -Not -Match ([regex]::Escape([string][char]27))
            $fill = @($runs | Where-Object { $_.Text.StartsWith($script:full) })
            $fill.Count | Should -Be 1
            $fill[0].Color | Should -BeExactly 'Cyan'
            @($runs | Where-Object { $_.Text.Trim() -ceq '[74%]' })[0].Color | Should -BeExactly 'Green'
            $script:f106Calls[$script:f106Calls.Count - 1].Value | Should -BeExactly 'Gray'
            $script:f106Calls[$script:f106Calls.Count - 1].Kind | Should -BeExactly 'color'
        }
    }

    It 'colors done green, ended early yellow with a dark yellow sign, and failed red' {
        # Mutation: Console16 ignores the row paint and colors every fill by the palette alone.
        InModuleScope TpmProgress {
            $cases = @(
                @{ State = 'Final'; Current = 100; Fill = 'Green'; Mark = $null },
                @{ State = 'Incomplete'; Current = 60; Fill = 'Yellow'; Mark = 'DarkYellow' },
                @{ State = 'Error'; Current = 120; Fill = 'Red'; Mark = $null }
            )
            foreach ($case in $cases) {
                $script:f106Calls.Clear()
                $row = New-Fix106Row -State $case.State -Current $case.Current -Total 100
                Write-TpmProgressSegments -Rows @($row) -ColorMode Console16 -Background Black -Foreground ([System.ConsoleColor]::Gray)
                $color = ''
                $runs = New-Object System.Collections.Generic.List[object]
                foreach ($call in $script:f106Calls) {
                    if ($call.Kind -eq 'color') { $color = $call.Value } else { [void]$runs.Add([pscustomobject]@{ Color = $color; Text = $call.Value }) }
                }
                @($runs | Where-Object { $_.Text.StartsWith($script:full) })[0].Color | Should -BeExactly $case.Fill -Because $case.State
                if ($case.Mark) { @($runs | Where-Object { $_.Text -ceq $script:warn })[0].Color | Should -BeExactly $case.Mark -Because $case.State }
            }
        }
    }

    It 'writes a TrueColor frame with ONE console write and puts the foreground back once' {
        # Mutation: the one-string frame is split into runs for VT consoles too.
        InModuleScope TpmProgress {
            $row = New-Fix106Row -Current 74 -Total 100
            Write-TpmProgressSegments -Rows @($row) -ColorMode TrueColor -Background Black -Foreground ([System.ConsoleColor]::Gray)
            @($script:f106Calls | Where-Object Kind -eq 'text').Count | Should -Be 1
            @($script:f106Calls | Where-Object Kind -eq 'color').Count | Should -Be 1
        }
    }
}

Describe 'FIX106 plain ASCII for redirected output and consoles that cannot do more' {
    It 'writes every state as plain ASCII with the count, the percent and the state word' {
        # Mutation: an ASCII line uses a block glyph or an escape sequence, or drops its count, percent or word.
        InModuleScope TpmProgress {
            $cases = @(
                @{ State = 'Running'; Current = 74; Total = 100; Pattern = '74/100\s+\[74%\]\s+in 10\.0s \(7\.55/s\)\s+ETA 0:04'; Fill = '#' },
                @{ State = 'Final'; Current = 100; Total = 100; Pattern = '100/100\s+\[100%\].*done'; Fill = '#' },
                @{ State = 'Incomplete'; Current = 60; Total = 100; Pattern = '\(!\)\s+60/100\s+\[60%\].*incomplete\s+!'; Fill = '#' },
                @{ State = 'Error'; Current = 120; Total = 100; Pattern = '\(!\)\s+120/100\s+\[120%\].*FAILED\s+X'; Fill = '#' },
                @{ State = 'Skipped'; Current = 0; Total = 100; Pattern = '\|-.*in 0\.0s \(0\.00/s\)\s+skipped\s+-'; Fill = '' },
                @{ State = 'Running'; Current = 4180; Total = 0; Pattern = '4180'; Fill = '>' }
            )
            foreach ($case in $cases) {
                $row = New-Fix106Row -State $case.State -Current $case.Current -Total $case.Total -Style Ascii -Elapsed $(if ($case.State -eq 'Skipped') { 0 } else { 10 }) -Eta $(if ($case.State -eq 'Running' -and $case.Total -gt 0) { 3.4 } else { -1 }) -Rate $(if ($case.State -eq 'Skipped') { 0 } else { 7.55 })
                $row.Text | Should -Not -Match '[^\x20-\x7E]' -Because $case.State
                $row.Text | Should -Match $case.Pattern -Because $case.State
                if ($case.Fill) { $row.Text | Should -Match ([regex]::Escape($case.Fill)) -Because $case.State }
                (Get-Fix106Frame -Row $row -ColorMode None) | Should -BeExactly $row.Text -Because $case.State
            }
        }
    }

    It 'draws an unknown total in ASCII with no percent' {
        # Mutation: the ASCII unknown-total line shows a percent.
        InModuleScope TpmProgress {
            $row = New-Fix106Row -Current 4180 -Total 0 -Style Ascii -Rate 418
            $row.Text | Should -Not -Match '%'
            $row.Text | Should -Match '>{14}'
        }
    }
}

Describe 'FIX106 ETA, elapsed time, rate and spinner' {
    It 'shows ETA m:ss while running and leaves it out when it cannot be worked out' {
        # Mutation: ETA is shown for a closed row, shown as -1, or never shown.
        $line = Format-TpmProgressLine -Title '' -Stage 'Copying' -Current 74 -Total 100 -ElapsedSeconds 10 -EtaSeconds 3.4 -Rate 7.55 -Width 110 -Style Unicode
        $line | Should -Match '74/100\s+\[74%\]\s+in 10\.0s \(7\.55/s\)\s+ETA 0:04'
        (Format-TpmProgressLine -Title '' -Stage 'Copying' -Current 74 -Total 100 -ElapsedSeconds 10 -EtaSeconds 75 -Rate 7.55 -Width 110 -Style Unicode) | Should -Match 'ETA 1:15'
        (Format-TpmProgressLine -Title '' -Stage 'Copying' -Current 74 -Total 100 -ElapsedSeconds 10 -EtaSeconds -1 -Rate 7.55 -Width 110 -Style Unicode) | Should -Not -Match 'ETA'
        (Format-TpmProgressLine -Title '' -Stage 'Copying' -Current 100 -Total 100 -State Final -ElapsedSeconds 10 -EtaSeconds 3 -Rate 7.55 -Width 110 -Style Unicode) | Should -Not -Match 'ETA'
    }

    It 'works the remaining time out from the rate, and hides it for an unknown total' {
        # Mutation: Get-TpmProgressEta returns a value for an unknown total or with too few samples.
        Get-TpmProgressEta -Current 74 -Total 100 -ElapsedSeconds 10 -Samples 5 -SmoothedRate 7.55 | Should -BeGreaterThan 3.4
        Get-TpmProgressEta -Current 74 -Total 100 -ElapsedSeconds 10 -Samples 5 -SmoothedRate 7.55 | Should -BeLessThan 3.5
        Get-TpmProgressEta -Current 4180 -Total 0 -ElapsedSeconds 10 -Samples 5 -SmoothedRate 400 | Should -Be -1
        Get-TpmProgressEta -Current 74 -Total 100 -ElapsedSeconds 10 -Samples 2 -SmoothedRate 7.55 | Should -Be -1
    }

    It 'ends a running row with a spinner that cycles through four symbols' {
        # Mutation: the spinner does not follow the tick.
        $symbols = foreach ($tick in 0..3) {
            (Format-TpmProgressLine -Title '' -Stage 'Copying' -Current 5 -Total 10 -ElapsedSeconds 2 -Width 100 -Tick $tick -Style Unicode).TrimEnd()[-1]
        }
        @($symbols | Sort-Object -Unique).Count | Should -Be 4
        @($symbols | Where-Object { $_ -notin @('\', '|', '/', '-') }).Count | Should -Be 0
    }

    It 'shows a skipped row as 0.0 s and 0.00/s even when the step object was created earlier' {
        # Mutation: Get-TpmProgressElapsed or Get-TpmProgressTaskRate ignores the Skipped state.
        InModuleScope TpmProgress {
            $now = [datetime]'2026-01-01T00:00:10'
            $op = [pscustomobject]@{
                Title = 'Skipped'; Stage = ''; Current = 0; Total = 100; Tick = 0; Unit = 'Items'; NoCount = $false
                Columns = @('Description', 'Bar', 'Count', 'Percentage', 'Elapsed', 'Remaining', 'Spinner'); EtaHidden = $false
                StageFirstCurrent = 0; StageSamples = 0; SmoothedRate = 0.0; PauseStarted = $null; Finished = $now; Group = $false
                Started = $now.AddSeconds(-5); StageStarted = $now.AddSeconds(-5)
            }
            $text = (@(Get-TpmProgressLineSegments -Op $op -State Skipped -Now $now -Width 110 -Style Unicode) | ForEach-Object { $_.Text }) -join ''
            $text | Should -Match 'in 0\.0s \(0\.00/s\)'
            $text | Should -Match 'skipped'
            $text | Should -Not -Match '%'
            Get-TpmProgressElapsed -Op $op -State Skipped -Now $now | Should -Be 0
            Get-TpmProgressElapsed -Op $op -State Incomplete -Now $now | Should -Be 5
        }
    }
}

Describe 'FIX106 the live frame is colored, and printed messages stay above the bars' {
    BeforeEach {
        $global:TpmUiNow = [datetime]'2026-01-01T00:00:00'
        $global:TpmUiEvents = New-Object System.Collections.Generic.List[string]
        $global:TpmUiRaw = New-Object System.Text.StringBuilder
        $script:savedWt = $env:WT_SESSION
        $env:WT_SESSION = 'fixture-session'
        Mock Start-TpmProgressRefresh {} -ModuleName TpmProgress
        Mock Get-TpmProgressCursorVisible { $true } -ModuleName TpmProgress
        Mock Set-TpmProgressCursorVisible {} -ModuleName TpmProgress
        Mock Get-TpmProgressNow { $global:TpmUiNow } -ModuleName TpmProgress
        Mock Get-TpmProgressTimestamp { 0 } -ModuleName TpmProgress
        Mock Test-TpmProgressOutputRedirected { $false } -ModuleName TpmProgress
        Mock Test-TpmProgressColorEnabled { $true } -ModuleName TpmProgress
        Mock Test-TpmProgressVt { $true } -ModuleName TpmProgress
        Mock Get-TpmProgressForeground { [System.ConsoleColor]::Gray } -ModuleName TpmProgress
        Mock Set-TpmProgressForeground {} -ModuleName TpmProgress
        Mock Get-TpmProgressStyle { 'Unicode' } -ModuleName TpmProgress
        Mock Test-TpmProgressWideWriteAvailable { $false } -ModuleName TpmProgress
        Mock Get-TpmProgressWidth { 100 } -ModuleName TpmProgress
        Mock Get-TpmProgressCursor { [pscustomobject]@{ Left = 0; Top = 7 } } -ModuleName TpmProgress
        Mock Get-TpmProgressBufferWidth { 101 } -ModuleName TpmProgress
        Mock Get-TpmProgressWindowHeight { 30 } -ModuleName TpmProgress
        Mock Get-TpmProgressBackground { 'Black' } -ModuleName TpmProgress
        Mock Set-TpmProgressCursor { $true } -ModuleName TpmProgress
        Mock Write-TpmProgressRaw {
            [void]$global:TpmUiRaw.Append($Text)
            [void]$global:TpmUiEvents.Add($(if ($Text.Length -gt 1) { 'frame' } else { 'blank' }))
        } -ModuleName TpmProgress
        Mock Clear-TpmProgressCells { [void]$global:TpmUiEvents.Add('lift'); return $true } -ModuleName TpmProgress
    }
    AfterEach {
        Stop-TpmProgressAbandoned
        $env:WT_SESSION = $script:savedWt
        Remove-Variable -Name TpmUiNow, TpmUiEvents, TpmUiRaw -Scope Global -ErrorAction SilentlyContinue
    }

    It 'writes the running fill in its gradient color and the finished bar in bright green' {
        # Mutation: Start-TpmProgressOperation does not take the color mode from Get-TpmProgressColorMode, or the closing frame is plain.
        Start-TpmProgressOperation -Title '' -Stage 'Copying your games' -Total 10 | Out-Null
        (Get-TpmProgressState).ColorMode | Should -BeExactly 'TrueColor'
        $global:TpmUiNow = $global:TpmUiNow.AddSeconds(1)
        Set-TpmProgressStage -Stage 'Copying your games' -Current 7 -Total 10
        $global:TpmUiRaw.ToString() | Should -Match ($script:esc + '\[38;2;30;200;210m' + $script:full)
        $global:TpmUiNow = $global:TpmUiNow.AddSeconds(1)
        Set-TpmProgressStage -Stage 'Copying your games' -Current 10 -Total 10 -SameStage
        Complete-TpmProgressOperation -State Final
        $closing = $global:TpmUiRaw.ToString()
        $closing | Should -Match ($script:esc + '\[38;2;40;230;90m' + $script:full)
        $closing | Should -Match '\[100%\]'
        $closing | Should -Match ($script:tick)
    }

    It 'lifts the bars, prints the message, and draws the bars again below it, once' {
        # Mutation: Resume-TpmProgressOutput draws nothing, draws twice, or the bars are not lifted before the message.
        Start-TpmProgressOperation -Title '' -Stage 'Copying your games' -Total 10 | Out-Null
        $global:TpmUiEvents.Clear()
        (Suspend-TpmProgressOutput) | Should -BeTrue
        [void]$global:TpmUiEvents.Add('message')
        Resume-TpmProgressOutput
        ($global:TpmUiEvents -join ',') | Should -BeExactly 'lift,message,frame'
    }
}
