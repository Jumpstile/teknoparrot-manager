#Requires -Module Pester

# FIX123 progress meter.
#   1. The empty part of a bar is tiny dots (U+00B7) in dim gray in the Block and Unicode looks, never blank and never the dotted light
#      shade (U+2591). The Ascii look (redirected output, no-color and plain-text paths, TPM_PROGRESS_STYLE=ascii) stays plain ASCII.
#   2. A step that is ONE long external job (Set-TpmProgressStage -LongStep, for example the PostgreSQL installer) reads "still working"
#      in the running color, with no "(!)" and no recorded stall. A step without -LongStep that goes silent (a counted loop that stopped
#      advancing) is still shown and recorded as stalled.
# Every console write is a mock and the clock is a variable. Glyphs are built at run time; this file is pure ASCII.
# What this CANNOT prove: how a real console font draws the dots, or the real Windows Installer wait.

BeforeAll {
    $script:F123ModuleSource = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1'))
    $script:F123ProductPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $script:shade = [string][char]0x2591
    $script:full = [string][char]0x2588
    $script:dot = [string][char]0x00B7
}

Describe 'FIX123 the empty part of the bar is tiny dots' {
    BeforeAll {
        Get-Module -Name TpmProgress -All | Remove-Module -Force
        Import-Module $script:F123ModuleSource -Force -ErrorAction Stop
    }
    AfterAll { Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue }

    It 'draws the empty part of a Block bar as tiny dots (U+00B7) next to the solid fill' {
        # Mutation: Get-TpmProgressBarGlyphs gives the Block look blanks, the light shade (U+2591) or '-' again.
        (Format-TpmProgressBar -Current 3 -Total 10 -BarWidth 12 -Style Block) | Should -BeExactly ('|' + ($script:full * 3) + ($script:dot * 7) + '|')
        (Format-TpmProgressBar -Current 0 -Total 0 -BarWidth 20 -Style Block -Tick 0) | Should -BeExactly ('|' + ('>' * 14) + ($script:dot * 4) + '|')
        (Format-TpmProgressBar -Current 3 -Total 10 -BarWidth 12 -Style Block) | Should -Not -Match ' '
        (Format-TpmProgressBar -Current 3 -Total 10 -BarWidth 12 -Style Unicode) | Should -BeExactly ('|' + ($script:full * 3) + ($script:dot * 7) + '|')
        (Format-TpmProgressBar -Current 25 -Total 100 -BarWidth 12 -Style Unicode) | Should -BeExactly ('|' + ($script:full * 2) + [string][char]0x258C + ($script:dot * 7) + '|')
    }

    It 'draws no light shade in any style, state or kind of bar' {
        # Mutation: any state or bar kind (counted, unknown total, skipped, closed early) falls back to the shade for its empty cells.
        foreach ($style in @('Ascii', 'Block', 'Unicode')) {
            foreach ($state in @('Running', 'Waiting', 'Stalled', 'Final', 'No-op', 'Error', 'Cancelled', 'Incomplete', 'Pending', 'Skipped')) {
                foreach ($counts in @(@(0, 10), @(4, 10), @(0, 0), @(15, 0))) {
                    $bar = Format-TpmProgressBar -Current $counts[0] -Total $counts[1] -BarWidth 24 -State $state -Style $style -Tick 5
                    $bar | Should -Not -Match $script:shade -Because ('{0} {1} {2}/{3}' -f $style, $state, $counts[0], $counts[1])
                    $line = Format-TpmProgressLine -Title 'Install' -Stage 'Installer running' -Current $counts[0] -Total $counts[1] -State $state -ElapsedSeconds 9 -Width 100 -Style $style
                    $line | Should -Not -Match $script:shade -Because ('line {0} {1} {2}/{3}' -f $style, $state, $counts[0], $counts[1])
                }
            }
        }
    }

    It 'draws the empty cells of the Block and Unicode looks as dim gray dots and never as a blank' {
        # Mutation: the empty cells lose their dim gray role, or a state (counted, unknown total, closed early) draws a space.
        $savedBarStyle = $env:TPM_PROGRESS_BAR_STYLE
        try {
            $env:TPM_PROGRESS_BAR_STYLE = $null
            InModuleScope TpmProgress {
                $dot = [string][char]0x00B7
                foreach ($style in @('Block', 'Unicode')) {
                    foreach ($state in @('Running', 'Waiting', 'Stalled', 'Final', 'No-op', 'Error', 'Cancelled', 'Incomplete', 'Pending')) {
                        foreach ($counts in @(@(0, 10), @(4, 10), @(0, 0), @(15, 0))) {
                            $segments = @(New-TpmProgressBarSegments -Current $counts[0] -Total $counts[1] -BarWidth 24 -State $state -Tick 5 -Style $style)
                            $text = (($segments | ForEach-Object { $_.Text }) -join '')
                            $text | Should -Not -Match ' ' -Because ('{0} {1} {2}/{3}' -f $style, $state, $counts[0], $counts[1])
                            foreach ($segment in @($segments | Where-Object { $_.Text.Contains($dot) })) {
                                $segment.Role | Should -BeExactly 'dots'
                                $segment.Text | Should -Match ('^' + $dot + '+$')
                                Get-TpmProgressSegmentColor -Role $segment.Role -State $state -Background 'Black' | Should -BeExactly 'DarkGray'
                            }
                        }
                    }
                }
            }
        } finally { $env:TPM_PROGRESS_BAR_STYLE = $savedBarStyle }
    }

    It 'keeps the plain-text (Ascii) look made of printable ASCII only, for every state' {
        # Mutation: the Ascii look takes a non-ASCII glyph, or a new state (Waiting) draws a non-ASCII mark.
        foreach ($state in @('Running', 'Waiting', 'Stalled', 'Final', 'No-op', 'Error', 'Cancelled', 'Incomplete', 'Pending', 'Skipped')) {
            $line = Format-TpmProgressLine -Title 'Install' -Stage 'Installer running' -Current 4 -Total 10 -State $state -ElapsedSeconds 9 -Width 100 -Style Ascii
            $line | Should -Not -Match '[^\x20-\x7E]' -Because $state
            $line.Length | Should -Be 100
        }
    }

    It 'keeps every Ascii bar printable ASCII with # filled and - empty, and never the middle dot' {
        # Mutation: the Ascii look takes the middle dot (U+00B7) or any other non-ASCII glyph for its empty cells.
        (Format-TpmProgressBar -Current 3 -Total 10 -BarWidth 12 -Style Ascii) | Should -BeExactly '|###-------|'
        foreach ($state in @('Running', 'Waiting', 'Stalled', 'Final', 'No-op', 'Error', 'Cancelled', 'Incomplete', 'Pending', 'Skipped')) {
            foreach ($counts in @(@(0, 10), @(4, 10), @(0, 0), @(15, 0))) {
                $bar = Format-TpmProgressBar -Current $counts[0] -Total $counts[1] -BarWidth 24 -State $state -Style Ascii -Tick 5
                $bar | Should -Not -Match '[^\x20-\x7E]' -Because ('{0} {1}/{2}' -f $state, $counts[0], $counts[1])
            }
        }
    }
}

Describe 'FIX123 a long external step reads still working' {
    BeforeAll {
        Get-Module -Name TpmProgress -All | Remove-Module -Force
        Import-Module $script:F123ModuleSource -Force -ErrorAction Stop
    }
    AfterAll { Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue }

    It 'shows "still working" and no warning sign in every style at every width that has room for the word' -ForEach @(
        @{ Style = 'Ascii' }
        @{ Style = 'Block' }
        @{ Style = 'Unicode' }
    ) {
        # Mutation: the Waiting state falls back to the Stalled word or its "(!)" marker.
        foreach ($width in @(120, 100, 80, 60)) {
            $line = Format-TpmProgressLine -Title 'Install' -Stage 'Installer running' -Current 0 -Total 0 -State Waiting -ElapsedSeconds 107 -Width $width -Style $Style
            $line.Length | Should -Be $width
            $line | Should -Match 'still working' -Because ('width {0}' -f $width)
            $line | Should -Not -Match '\(!\)'
            $line | Should -Not -Match 'stalled'
            $line | Should -Not -Match '!'
            $line | Should -Not -Match ([string][char]0x26A0)
        }
    }

    It 'never shows the warning for the waiting state, even in the narrowest layouts' {
        # Mutation: a narrow layout puts the Stalled mark or word in front of the label for a waiting step.
        foreach ($width in @(50, 40, 30, 20, 12)) {
            $line = Format-TpmProgressLine -Title 'Install' -Stage 'Installer running' -Current 0 -Total 0 -State Waiting -ElapsedSeconds 107 -Width $width -Style Block
            $line.Length | Should -Be $width
            $line | Should -Not -Match '\(!\)|stalled|!'
        }
    }

    It 'still shows the stall warning for a step that is stalled, with or without a count' {
        # Mutation: the Stalled state loses its "(!)" marker or its word, so a real stall is no longer visible.
        foreach ($counts in @(@(4, 10), @(15, 0))) {
            $line = Format-TpmProgressLine -Title 'Check' -Stage 'Scanning' -Current $counts[0] -Total $counts[1] -State Stalled -ElapsedSeconds 107 -Width 100 -Style Ascii
            $line | Should -Match '\(!\)\s+\d'
            $line | Should -Match 'stalled'
        }
    }

    It 'draws the waiting word in the running color, not the warning color' -ForEach @(
        @{ Background = 'Black' }
        @{ Background = 'White' }
    ) {
        # Mutation: Get-TpmProgressSegmentColor maps Waiting to the warning color (palette.Warn).
        InModuleScope TpmProgress -Parameters @{ Background = $Background } {
            param($Background)
            $palette = Get-TpmProgressPalette -Background $Background
            $palette.Warn | Should -Not -BeExactly $palette.Running
            foreach ($role in @('state', 'status')) {
                Get-TpmProgressSegmentColor -Role $role -State 'Waiting' -Background $Background | Should -BeExactly $palette.Running
                Get-TpmProgressSegmentColor -Role $role -State 'Stalled' -Background $Background | Should -BeExactly $palette.Warn
            }
        }
    }
}

Describe 'FIX123 a long step in a live operation' {
    BeforeAll {
        Get-Module -Name TpmProgress -All | Remove-Module -Force
        Import-Module $script:F123ModuleSource -Force -ErrorAction Stop
    }
    AfterAll { Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue }
    BeforeEach {
        $global:F123Now = [datetime]'2026-01-01T00:00:00'
        $global:F123Lines = New-Object System.Collections.Generic.List[string]
        Mock Get-TpmProgressDefaultColumns { @('Spinner', 'Description', 'Bar', 'Percentage', 'Count', 'Elapsed', 'Remaining') } -ModuleName TpmProgress
        Mock Start-TpmProgressRefresh {} -ModuleName TpmProgress
        Mock Get-TpmProgressCursorVisible { $true } -ModuleName TpmProgress
        Mock Set-TpmProgressCursorVisible {} -ModuleName TpmProgress
        Mock Get-TpmProgressNow { $global:F123Now } -ModuleName TpmProgress
        Mock Test-TpmProgressOutputRedirected { $true } -ModuleName TpmProgress
        Mock Test-TpmProgressColorEnabled { $false } -ModuleName TpmProgress
        Mock Get-TpmProgressStyle { 'Ascii' } -ModuleName TpmProgress
        Mock Write-TpmProgressPlainLine { [void]$global:F123Lines.Add($Text) } -ModuleName TpmProgress
    }
    AfterEach {
        Stop-TpmProgressAbandoned
        Remove-Variable -Name F123Now, F123Lines -Scope Global -ErrorAction SilentlyContinue
    }

    It 'reads still working, not stalled, when the step stays silent for longer than the stall time' {
        # Mutation: Set-TpmProgressStage ignores -LongStep, or the plain frame picks Stalled from the silence alone.
        Start-TpmProgressOperation -Title 'Install' -Stage 'Getting ready' | Out-Null
        Set-TpmProgressStage -Stage 'Installer running' -Current 0 -Total 0 -LongStep
        $global:F123Now = $global:F123Now.AddSeconds(107)
        $global:F123Lines.Clear()
        InModuleScope TpmProgress { Write-TpmProgressFrame -Force -Sync }
        $global:F123Lines.Count | Should -BeGreaterThan 0
        $last = $global:F123Lines[$global:F123Lines.Count - 1]
        $last | Should -Match 'still working'
        $last | Should -Not -Match 'stalled'
        $last | Should -Not -Match '\(!\)'
        $last | Should -Not -Match '!'
        Test-TpmProgressStalled | Should -BeFalse
        (Get-TpmProgressState).Outcome | Should -BeNullOrEmpty
    }

    It 'keeps the plain "running" look until the stall time has passed' {
        # Mutation: the waiting word is shown from the first frame instead of after the silence.
        Start-TpmProgressOperation -Title 'Install' -Stage 'Getting ready' | Out-Null
        Set-TpmProgressStage -Stage 'Installer running' -Current 0 -Total 0 -LongStep
        $global:F123Now = $global:F123Now.AddSeconds(20)
        $global:F123Lines.Clear()
        InModuleScope TpmProgress { Write-TpmProgressFrame -Force -Sync }
        $global:F123Lines[$global:F123Lines.Count - 1] | Should -Not -Match 'still working|stalled'
    }

    It 'records no stall when the long step ends, and the close stays a normal finish' {
        # Mutation: the next stage update or the close adds "(no update for ...)" and registers Stalled for the installer's own silence.
        Start-TpmProgressOperation -Title 'Install' -Stage 'Getting ready' | Out-Null
        Set-TpmProgressStage -Stage 'Installer running' -Current 0 -Total 0 -LongStep
        $global:F123Now = $global:F123Now.AddSeconds(107)
        Set-TpmProgressStage -Stage 'Installer running done' -StageOnly
        (Get-TpmProgressState).Outcome | Should -BeNullOrEmpty
        $global:F123Now = $global:F123Now.AddSeconds(1)
        Complete-TpmProgressOperation -State Final
        ($global:F123Lines -join "`n") | Should -Not -Match 'stalled|no update for'
    }

    It 'records no stall when the close comes straight after a long silent step' {
        # Mutation: Complete-TpmProgressOperation tests the raw silence instead of Test-TpmProgressStalled.
        Start-TpmProgressOperation -Title 'Install' -Stage 'Getting ready' | Out-Null
        Set-TpmProgressStage -Stage 'Installer running' -Current 0 -Total 0 -LongStep
        $global:F123Now = $global:F123Now.AddSeconds(107)
        Complete-TpmProgressOperation -State Final
        ($global:F123Lines -join "`n") | Should -Not -Match 'stalled|no update for'
    }

    It 'shows the silence note once on the closing line when the work went quiet twice' {
        Start-TpmProgressOperation -Title 'Copy' -Stage 'Getting ready' | Out-Null
        $global:F123Now = $global:F123Now.AddSeconds(200)
        Set-TpmProgressStage -Stage 'Copying files' -Current 1 -Total 10
        $op = InModuleScope TpmProgress { $script:TpmProgressOp }
        $global:F123Now = $global:F123Now.AddSeconds(200)
        Complete-TpmProgressOperation -State Final
        $op.Stage | Should -Match 'no update for \d+s\)$'
        $op.Stage | Should -Not -Match 'no update for \d+s\) \(no update for'
    }

    It 'still shows and records a stall for a step that is not marked, with or without a count' -ForEach @(
        @{ Current = 15; Total = 0 }
        @{ Current = 4; Total = 10 }
    ) {
        # Mutation: every silent step reads as waiting (the marker is ignored), so a counted loop that stopped advancing is never flagged.
        Start-TpmProgressOperation -Title 'Check' -Stage 'Getting ready' | Out-Null
        Set-TpmProgressStage -Stage 'Scanning' -Current $Current -Total $Total
        $global:F123Now = $global:F123Now.AddSeconds(107)
        $global:F123Lines.Clear()
        InModuleScope TpmProgress { Write-TpmProgressFrame -Force -Sync }
        $last = $global:F123Lines[$global:F123Lines.Count - 1]
        $last | Should -Match 'stalled'
        $last | Should -Match '\(!\)'
        $last | Should -Not -Match 'still working'
        Test-TpmProgressStalled | Should -BeTrue
        Set-TpmProgressStage -Stage 'Scanning more' -Current ($Current + 1) -Total $Total
        (Get-TpmProgressState).Outcome | Should -BeExactly 'Stalled'
    }

    It 'goes back to normal stall detection as soon as the next stage starts' {
        # Mutation: the long-step mark stays on after the next Set-TpmProgressStage, so later silence is never a stall.
        Start-TpmProgressOperation -Title 'Install' -Stage 'Getting ready' | Out-Null
        Set-TpmProgressStage -Stage 'Installer running' -Current 0 -Total 0 -LongStep
        $global:F123Now = $global:F123Now.AddSeconds(107)
        Set-TpmProgressStage -Stage 'Checking the result' -Current 1 -Total 10
        (Get-TpmProgressState).Outcome | Should -BeNullOrEmpty
        $global:F123Now = $global:F123Now.AddSeconds(75)
        Test-TpmProgressStalled | Should -BeTrue
        Set-TpmProgressStage -Stage 'Checking the result' -Current 2 -Total 10
        (Get-TpmProgressState).Outcome | Should -BeExactly 'Stalled'
    }

    It 'hides the count during the long step and shows it again afterwards' {
        # Mutation: the long step keeps the meaningless "0" count, or the count stays hidden for the next stage.
        Start-TpmProgressOperation -Title 'Install' -Stage 'Getting ready' | Out-Null
        Set-TpmProgressStage -Stage 'Installer running' -Current 0 -Total 0 -LongStep
        (Get-TpmProgressState).NoCount | Should -BeTrue
        Set-TpmProgressStage -Stage 'Checking the result' -Current 3 -Total 10
        (Get-TpmProgressState).NoCount | Should -BeFalse
    }
}

Describe 'FIX123 the product wrapper for the installer step' {
    BeforeAll {
        # The wrappers are copied into TestDrive next to a copy of the module, so their own Import-TpmProgressModule loads that copy.
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:F123ProductPath, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) { throw 'FIX123 tests could not parse the production script.' }
        $wanted = @('Import-TpmProgressModule', 'Write-TpmCompactExtractionProgress', 'Get-TpmFriendlyProgressLabel')
        $texts = foreach ($name in $wanted) {
            $nodes = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name }, $true))
            if ($nodes.Count -ne 1) { throw ('FIX123 tests expected one {0}, found {1}.' -f $name, $nodes.Count) }
            $nodes[0].Extent.Text
        }
        New-Item -ItemType Directory -Path (Join-Path $TestDrive 'scripts') -Force | Out-Null
        Copy-Item -LiteralPath $script:F123ModuleSource -Destination (Join-Path $TestDrive 'scripts\TpmProgress.psm1') -Force
        $functionPath = Join-Path $TestDrive 'wrappers123.ps1'
        [System.IO.File]::WriteAllText($functionPath, ($texts -join "`r`n`r`n"), (New-Object System.Text.UTF8Encoding $false))
        . $functionPath
        Get-Module -Name TpmProgress -All | Remove-Module -Force
        Import-Module (Join-Path $TestDrive 'scripts\TpmProgress.psm1') -Force -ErrorAction Stop
    }
    AfterAll { Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue }
    BeforeEach {
        $global:F123Now = [datetime]'2026-01-01T00:00:00'
        $global:F123Lines = New-Object System.Collections.Generic.List[string]
        function Write-Log { param([string]$msg) }
        Mock Get-TpmProgressDefaultColumns { @('Spinner', 'Description', 'Bar', 'Percentage', 'Count', 'Elapsed', 'Remaining') } -ModuleName TpmProgress
        Mock Start-TpmProgressRefresh {} -ModuleName TpmProgress
        Mock Get-TpmProgressCursorVisible { $true } -ModuleName TpmProgress
        Mock Set-TpmProgressCursorVisible {} -ModuleName TpmProgress
        Mock Get-TpmProgressNow { $global:F123Now } -ModuleName TpmProgress
        Mock Test-TpmProgressOutputRedirected { $true } -ModuleName TpmProgress
        Mock Test-TpmProgressColorEnabled { $false } -ModuleName TpmProgress
        Mock Get-TpmProgressStyle { 'Ascii' } -ModuleName TpmProgress
        Mock Write-TpmProgressPlainLine { [void]$global:F123Lines.Add($Text) } -ModuleName TpmProgress
    }
    AfterEach {
        Stop-TpmProgressAbandoned
        Set-TpmProgressRenderLogger -Logger $null
        Remove-Variable -Name F123Now, F123Lines -Scope Global -ErrorAction SilentlyContinue
    }

    It 'reads still working for a silent installer step inside a group, and ends the mark with the step' {
        # Mutation: the wrapper drops -LongStep, or its -Complete call leaves the mark on.
        Start-TpmProgressOperation -Title 'PostgreSQL install' -Group | Out-Null
        Write-TpmCompactExtractionProgress -Phase Installing -Label 'PostgreSQL installer' -Current 0 -Total 0 -LongStep
        $global:F123Now = $global:F123Now.AddSeconds(107)
        $global:F123Lines.Clear()
        InModuleScope TpmProgress { Write-TpmProgressFrame -Force -Sync }
        $last = $global:F123Lines[$global:F123Lines.Count - 1]
        $last | Should -Match 'still working'
        $last | Should -Not -Match 'stalled|\(!\)'
        Write-TpmCompactExtractionProgress -Phase Installing -Label 'PostgreSQL installer' -Complete -Outcome Final
        (Get-TpmProgressState).Outcome | Should -BeNullOrEmpty
        # The next measured stage is a normal one again: silence there is a real stall.
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Service check' -Current 1 -Total 5
        $global:F123Now = $global:F123Now.AddSeconds(75)
        $global:F123Lines.Clear()
        InModuleScope TpmProgress { Write-TpmProgressFrame -Force -Sync }
        $global:F123Lines[$global:F123Lines.Count - 1] | Should -Match 'stalled'
    }

    It 'names the installer step in plain words' {
        # Mutation: the label is missing from the plain-label table, so the screen shows the internal name with a phase word in front.
        Get-TpmFriendlyProgressLabel -Label 'PostgreSQL installer' | Should -BeExactly 'Running the PostgreSQL installer'
    }
}
