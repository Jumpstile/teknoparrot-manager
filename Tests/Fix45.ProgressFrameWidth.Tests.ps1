#Requires -Module Pester
# FIX45: live progress frames are never wider than the window, and a frame that took more rows than it was composed for
# (or a bar row a caller moved the cursor into) never leaves a fragment on screen. Fake-only: a character-cell surface
# stands in for the console. Its REPORTED window and buffer widths (the values the module can read) and its REAL wrap
# width (where text actually wraps) are separate, and chosen characters can take two cells. Get-TpmProgressWidth is NOT
# mocked: the module's own width rule runs against the reported values. No product entry point, real console, scheduler or
# network is used. What this CANNOT prove: what a real Windows Terminal / ConPTY window reports and draws; the coordinator's
# FIX45-RealConsoleProbe.ps1 run measures that on the test PC.
BeforeAll {
    Get-Module -Name TpmProgress -All | Remove-Module -Force
    Import-Module (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Force -ErrorAction Stop
}
AfterAll { Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue }

Describe 'FIX45 progress frame width and wrapped-frame cleanup' {
    BeforeEach {
        # The wide-glyph tests draw the block bar. A TPM_PROGRESS_BAR_STYLE=line left in the user's or the shell's environment turns the bar into line glyphs and fails them.
        $script:F45SavedBarStyle = $env:TPM_PROGRESS_BAR_STYLE
        $env:TPM_PROGRESS_BAR_STYLE = $null
        InModuleScope TpmProgress {
            $script:f45 = @{
                WindowWidth = 121; BufferWidth = 121; WrapWidth = 121; BufferHeight = 0; WindowHeight = 100
                Left = 0; Top = 0; Rows = @{}; Used = @{}; Wrapped = @{}; Wide = @{}; Style = 'Ascii'; Visible = $true
                Now = [datetime]'2026-01-01T00:00:00'
                Writes = (New-Object System.Collections.Generic.List[string]); Inject = ''
            }
            # Single-cell glyphs the module may draw (the bar, the arrows, the icons and the unknown-total status square).
            $script:f45Narrow = @{}
            foreach ($code in @(0x2588, 0x2589, 0x258A, 0x258B, 0x258C, 0x258D, 0x258E, 0x258F, 0x2501, 0x2500, 0x2578,
                    0x25B6, 0x25C0, 0x2717, 0x26A0, 0x2713, 0x25CB, 0x25A0, 0x00B7)) { $script:f45Narrow[$code] = $true }
            $script:f45Status = @('|', '/', '-', '\', '+', 'X', '!', 'o', ([string][char]0x25A0), ([string][char]0x2713),
                ([string][char]0x2717), ([string][char]0x26A0), ([string][char]0x25CB))
            function script:Reset-F45Surface {
                param([int]$Width, [string]$Style = 'Ascii', [int]$WindowWidth = 0, [int]$BufferWidth = 0, [int]$WrapWidth = 0, [int]$BufferHeight = 0)
                $script:f45.WindowWidth = $(if ($WindowWidth -gt 0) { $WindowWidth } else { $Width })
                $script:f45.BufferWidth = $(if ($BufferWidth -gt 0) { $BufferWidth } else { $Width })
                $script:f45.WrapWidth = $(if ($WrapWidth -gt 0) { $WrapWidth } else { $Width })
                $script:f45.BufferHeight = $BufferHeight
                $script:f45.Style = $Style
                $script:f45.Left = 0; $script:f45.Top = 0; $script:f45.Rows = @{}; $script:f45.Used = @{}; $script:f45.Wrapped = @{}; $script:f45.Wide = @{}
                $script:f45.Writes.Clear(); $script:f45.Inject = ''
            }
            function script:Get-F45Row {
                param([int]$Top)
                if (-not $script:f45.Rows.ContainsKey($Top)) { $script:f45.Rows[$Top] = New-Object 'char[]' $script:f45.WrapWidth; for ($i = 0; $i -lt $script:f45.WrapWidth; $i++) { $script:f45.Rows[$Top][$i] = ' ' } }
                return ,$script:f45.Rows[$Top]
            }
            function script:Move-F45Down {
                param([switch]$Wrap)
                $script:f45.Top++
                if ($script:f45.BufferHeight -gt 0 -and $script:f45.Top -ge $script:f45.BufferHeight) {
                    # The buffer is full: every row moves up one and the top row is gone (a console with no scrollback room).
                    foreach ($name in @('Rows', 'Used', 'Wrapped')) {
                        $moved = @{}
                        foreach ($key in @($script:f45[$name].Keys)) { if ($key -ge 1) { $moved[$key - 1] = $script:f45[$name][$key] } }
                        $script:f45[$name] = $moved
                    }
                    $script:f45.Top = $script:f45.BufferHeight - 1
                }
                # An automatic wrap makes the new row a continuation of the logical line above; a line feed never does.
                if ($Wrap) { $script:f45.Wrapped[$script:f45.Top] = $true } else { [void]$script:f45.Wrapped.Remove($script:f45.Top) }
            }
            function script:Write-F45Cells {
                # CR: column 0. LF: next row, column 0 (console default newline handling). Text wraps at the REAL width,
                # whatever the reported widths say; a character in the Wide set takes two cells.
                param([string]$Text)
                foreach ($ch in $Text.ToCharArray()) {
                    if ($ch -eq [char]13) { $script:f45.Left = 0; continue }
                    if ($ch -eq [char]10) { $script:f45.Left = 0; Move-F45Down; continue }
                    $cells = $(if ($script:f45.Wide.ContainsKey([int]$ch)) { 2 } else { 1 })
                    if ($script:f45.Left + $cells -gt $script:f45.WrapWidth) { $script:f45.Left = 0; Move-F45Down -Wrap }
                    $row = Get-F45Row $script:f45.Top
                    for ($i = 0; $i -lt $cells; $i++) { $row[$script:f45.Left + $i] = $ch }
                    $script:f45.Left += $cells
                    $script:f45.Used[$script:f45.Top] = [Math]::Max([int]$script:f45.Used[$script:f45.Top], $script:f45.Left)
                    if ($script:f45.Left -ge $script:f45.WrapWidth) { $script:f45.Left = 0; Move-F45Down -Wrap }
                }
            }
            function script:Get-F45Cell {
                param([int]$Index, [int]$Top)
                $row = $Top + [int][Math]::Floor($Index / [double]$script:f45.WrapWidth)
                return [pscustomobject]@{ Row = $row; Col = ($Index % $script:f45.WrapWidth) }
            }
            function script:Resize-F45Surface {
                # The FIX40 reflow model: logical lines (rows joined across automatic wraps) are written again at the new
                # width, and the cursor ends where the reflowed text puts it. Reported and real widths all change together.
                param([int]$Width)
                $lines = New-Object System.Collections.Generic.List[string]
                $line = ''
                for ($row = 0; $row -le $script:f45.Top; $row++) {
                    if ($row -gt 0 -and -not $script:f45.Wrapped.ContainsKey($row)) { [void]$lines.Add($line.TrimEnd()); $line = '' }
                    if ($script:f45.Rows.ContainsKey($row)) {
                        $length = $(if ($row -eq $script:f45.Top) { $script:f45.Left } else { [int]$script:f45.Used[$row] })
                        $line += (-join $script:f45.Rows[$row]).Substring(0, $length)
                    }
                }
                [void]$lines.Add($line)
                $script:f45.WindowWidth = $Width; $script:f45.BufferWidth = $Width; $script:f45.WrapWidth = $Width
                $script:f45.Left = 0; $script:f45.Top = 0; $script:f45.Rows = @{}; $script:f45.Used = @{}; $script:f45.Wrapped = @{}
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    if ($i -gt 0) {
                        if ($script:f45.Left -eq 0 -and $script:f45.Wrapped.ContainsKey($script:f45.Top)) {
                            # A hard line break after an exact-width row consumes that row only once.
                            [void]$script:f45.Wrapped.Remove($script:f45.Top)
                        } else { Write-F45Cells "`n" }
                    }
                    Write-F45Cells $lines[$i]
                }
            }
            function script:Get-F45Rows {
                foreach ($key in @($script:f45.Rows.Keys | Sort-Object)) {
                    $text = (-join $script:f45.Rows[$key]).TrimEnd()
                    if ($text.Length -gt 0) { [pscustomobject]@{ Top = $key; Text = $text } }
                }
            }
            function script:Write-F45Host {
                # TPM's Write-Host proxy: lift the bar, write, put the bar back below the text.
                param([string]$Text, [switch]$NoNewline)
                $lifted = Suspend-TpmProgressOutput
                try { Write-F45Cells ($Text + $(if ($NoNewline) { '' } else { "`n" })) }
                finally { if ($lifted) { Resume-TpmProgressOutput } }
            }
            function script:Step-F45Frame {
                param([int]$Milliseconds = 300, [switch]$Background)
                $script:f45.Now = $script:f45.Now.AddMilliseconds($Milliseconds)
                $live = $script:TpmProgressOp.Live
                [System.Threading.Monitor]::Enter($live.Gate)
                try {
                    if ($Background) { Invoke-TpmProgressRefreshStep -Live $live -CheckOwner }
                    else { Invoke-TpmProgressRefreshStep -Live $live -Force }
                } finally { [System.Threading.Monitor]::Exit($live.Gate) }
            }
            function script:Set-F45OwnerValues {
                # The owner's screenshot values: 58/62 finished, 0.1 s into the stage, no measured rate yet.
                param([long]$Current = 58, [long]$Total = 62, [double]$ElapsedSeconds = 0.1, [double]$Rate = 0)
                $op = $script:TpmProgressOp
                $op.Current = $Current; $op.Total = $Total; $op.SmoothedRate = $Rate
                $op.StageStarted = $script:f45.Now.AddMilliseconds(-1000 * $ElapsedSeconds)
                $op.LastChange = $script:f45.Now
                Publish-TpmProgressSnapshot -Op $op
            }
            function script:Get-F45WrittenRows {
                # Rows of one frame write: the leading CR or LF CR and a closing CR LF are not row content.
                param([string]$Write)
                $text = $Write.TrimStart([char]10).TrimStart([char]13)
                if ($text.EndsWith("`r`n")) { $text = $text.Substring(0, $text.Length - 2) }
                return ,@($text -split "`r`n")
            }
            function script:Measure-F45DisplayCells {
                # Independent of the module's segment lengths: printable ASCII and the module's single-cell glyphs take one
                # cell each; VT color sequences take none; anything else is an error (its width would be unknown).
                param([string]$Row)
                $plain = $Row -replace ([string][char]27 + '\[[0-9;]*m'), ''
                $cells = 0
                foreach ($ch in $plain.ToCharArray()) {
                    $code = [int]$ch
                    if ($code -ge 0x20 -and $code -le 0x7E) { $cells++; continue }
                    if ($script:f45Narrow.ContainsKey($code)) { $cells++; continue }
                    throw ('unexpected character U+{0:X4} in a frame row' -f $code)
                }
                return $cells
            }
            Mock Start-TpmProgressRefresh {}
            Mock Get-TpmProgressNow { $script:f45.Now }
            Mock Get-TpmProgressTimestamp { ($script:f45.Now.Ticks - ([datetime]'2026-01-01T00:00:00').Ticks) / 10000.0 }
            Mock Test-TpmProgressOutputRedirected { $false }
            Mock Get-TpmProgressWindowWidth { $script:f45.WindowWidth }
            Mock Get-TpmProgressBufferWidth { $script:f45.BufferWidth }
            Mock Get-TpmProgressWindowHeight { $script:f45.WindowHeight }
            Mock Get-TpmProgressCursor { [pscustomobject]@{ Left = $script:f45.Left; Top = $script:f45.Top } }
            Mock Set-TpmProgressCursor {
                param($Left, $Top)
                $script:f45.Left = $Left; $script:f45.Top = $Top; return $true
            }
            Mock Clear-TpmProgressCells {
                param($Top, $Count)
                for ($i = 0; $i -lt $Count; $i++) {
                    $cell = Get-F45Cell -Index $i -Top $Top
                    if ($script:f45.Rows.ContainsKey($cell.Row)) { $script:f45.Rows[$cell.Row][$cell.Col] = ' ' }
                }
                return $true
            }
            Mock Read-TpmProgressCells {
                param($Top, $Count)
                $chars = New-Object 'char[]' $Count
                for ($i = 0; $i -lt $Count; $i++) {
                    $cell = Get-F45Cell -Index $i -Top $Top
                    $chars[$i] = $(if ($script:f45.Rows.ContainsKey($cell.Row)) { $script:f45.Rows[$cell.Row][$cell.Col] } else { ' ' })
                }
                return (-join $chars)
            }
            Mock Get-TpmProgressCursorVisible { $script:f45.Visible }
            Mock Set-TpmProgressCursorVisible { param($Visible) $script:f45.Visible = $Visible }
            Mock Get-TpmProgressStyle { $script:f45.Style }
            Mock Get-TpmProgressBackground { $null }
            Mock Test-TpmProgressColorEnabled { $false }
            Mock Test-TpmProgressWideWriteAvailable { $false }
            Mock Test-TpmProgressConhostFont { $false }
            Mock Test-TpmProgressGlyphCells { $false }
            Mock Get-TpmProgressOutputCodePage { 437 }
            Mock Write-TpmProgressRaw {
                param($Text, $NewLine)
                $value = [string]$Text
                if ($NewLine) { $value += "`r`n" }
                [void]$script:f45.Writes.Add($value)
                Write-F45Cells $value
                # Foreign output that lands right after this write (another thread or process), once.
                if ($script:f45.Inject) { $inject = $script:f45.Inject; $script:f45.Inject = ''; Write-F45Cells $inject }
            }
            Mock Write-TpmProgressPlainLine {}
        }
    }
    AfterEach {
        InModuleScope TpmProgress {
            if (Test-TpmProgressActive) { Stop-TpmProgressAbandoned }
        }
        $env:TPM_PROGRESS_BAR_STYLE = $script:F45SavedBarStyle
    }

    It 'keeps every live and closing row of the owner''s support-package label within width-1 at every width from 40 to 200' {
        # Mutation: drop the "- 1" in Get-TpmProgressWidth (or let a long label skip truncation) -> rows reach the full
        # width, the surface wraps them and the one-row checks fail.
        InModuleScope TpmProgress {
            foreach ($width in 40..200) {
                Reset-F45Surface -Width $width -Style 'Unicode'
                $null = Start-TpmProgressOperation -Title 'Support package' -Stage 'Scanning Support profile scan' -Total 62
                Set-F45OwnerValues
                Step-F45Frame -Milliseconds 0
                # Plain assignment (not @(...)): the helper returns ,@(rows), which @(...) would wrap a second time, so
                # Count would always be 1 and [0] would be the whole row array instead of the first row (issue #384).
                $live = Get-F45WrittenRows $script:f45.Writes[$script:f45.Writes.Count - 1]
                $live.Count | Should -Be 1
                $live[0].Length | Should -BeLessOrEqual ($width - 1) -Because "the module's own cell count at width $width"
                (Measure-F45DisplayCells $live[0]) | Should -BeLessOrEqual ($width - 1) -Because "the independent cell count at width $width"
                # The spinner/icon is the last thing on the row and inside it.
                $script:f45Status | Should -Contain ([string]$live[0].TrimEnd()[-1])
                if ($width -ge 100) { $live[0] | Should -Match 'Support package: Scanning Support profile scan' }
                if ($width -ge 110) { $live[0] | Should -Match '58/62' }
                @(Get-F45Rows).Count | Should -Be 1 -Because "no row wrapped at width $width"
                Stop-TpmProgressAbandoned
                $closing = Get-F45WrittenRows $script:f45.Writes[$script:f45.Writes.Count - 1]
                # Before #384 the whole row array was measured as one joined string, which implied exactly one row.
                $closing.Count | Should -Be 1 -Because "the closing write at width $width is one row"
                (Measure-F45DisplayCells $closing[0]) | Should -BeLessOrEqual ($width - 1)
                @(Get-F45Rows).Count | Should -Be 1
            }
        }
    }

    It 'truncates labels of 5 to 120 characters instead of overflowing, in both glyph sets, with the elapsed column dropped first' {
        # Mutation: let the label keep its full length when it does not fit (skip Limit-TpmProgressText) -> rows longer than
        # width-1 and a second surface row.
        InModuleScope TpmProgress {
            $labels = @(5, 9, 14, 30, 46, 64, 90, 120)
            $widths = @(40, 41, 47, 60, 79, 80, 100, 109, 110, 111, 119, 120, 121, 160, 200)
            foreach ($style in @('Ascii', 'Unicode')) {
                foreach ($length in $labels) {
                    $label = ('Label-' + ('x' * 130)).Substring(0, $length)
                    foreach ($width in $widths) {
                        Reset-F45Surface -Width $width -Style $style
                        $null = Start-TpmProgressOperation -Title $label -Stage '' -Total 62
                        Set-F45OwnerValues -ElapsedSeconds 22.6 -Rate 149.48
                        Step-F45Frame -Milliseconds 0
                        # Plain assignment (not @(...)): the helper returns ,@(rows), which @(...) would wrap a second time.
                        $frameRows = Get-F45WrittenRows $script:f45.Writes[$script:f45.Writes.Count - 1]
                        $row = [string]$frameRows[0]
                        (Measure-F45DisplayCells $row) | Should -BeLessOrEqual ($width - 1) -Because "$style label $length at width $width"
                        @(Get-F45Rows).Count | Should -Be 1 -Because "$style label $length at width $width"
                        $script:f45Status | Should -Contain ([string]$row.TrimEnd()[-1])
                        if ($row.Length -gt 0 -and $length -gt $width) { $row | Should -Match '\.\.\.' -Because 'a cut label shows an ASCII ellipsis' }
                        # #379: a label that does not fit loses the elapsed/rate column before it is cut; the bar stays.
                        if ($width -ge 80) { $row | Should -Match '\|' }
                        if ($width -ge 80 -and -not $row.Contains($label)) { $row | Should -Not -Match '149\.48/s' -Because "$style label $length at width $width is cut, so the elapsed/rate column must be gone" }
                        Stop-TpmProgressAbandoned
                    }
                }
            }
        }
    }

    It 'composes each row exactly once per frame' {
        # Mutation: add a row twice in Get-TpmProgressRows / Get-TpmProgressFrameRows -> four rows, a description twice.
        InModuleScope TpmProgress {
            Reset-F45Surface -Width 121
            $null = Start-TpmProgressOperation -Title 'Owner' -Stage '' -Total 10 -Columns Description,Bar,Percentage,Count,Elapsed,Spinner
            $null = Add-TpmProgressTask -Description 'Child alpha' -Total 20
            $null = Add-TpmProgressTask -Description 'Child beta' -Total 30
            foreach ($step in 1..3) {
                Step-F45Frame
                $rows = Get-F45WrittenRows $script:f45.Writes[$script:f45.Writes.Count - 1]
                $rows.Count | Should -Be 3
                @($rows | Where-Object { $_ -match 'Owner' }).Count | Should -Be 1
                @($rows | Where-Object { $_ -match 'Child alpha' }).Count | Should -Be 1
                @($rows | Where-Object { $_ -match 'Child beta' }).Count | Should -Be 1
                foreach ($row in $rows) { (Measure-F45DisplayCells $row) | Should -BeLessOrEqual 120 }
                @(Get-F45Rows).Count | Should -Be 3
            }
        }
    }

    It 'leaves no stale rows when the window shrinks and grows between frames' {
        # Mutation: compose the next frame with the width read before the resize (skip the per-frame re-read) -> the narrow
        # frame wraps on the surface and leaves a second row; or keep the old region on a grow -> two regions.
        InModuleScope TpmProgress {
            Reset-F45Surface -Width 121 -Style 'Unicode'
            $null = Start-TpmProgressOperation -Title 'Support package' -Stage 'Scanning Support profile scan' -Total 62
            Set-F45OwnerValues
            Step-F45Frame -Milliseconds 0
            foreach ($width in @(110, 80, 41, 200, 110, 60, 121)) {
                # Between two frames the window changes size and the host reflows what is on screen (FIX40 model).
                Resize-F45Surface $width
                Step-F45Frame
                $rows = @(Get-F45Rows)
                $rows.Count | Should -Be 1 -Because "one region after the change to $width columns"
                $rows[0].Top | Should -Be 0
                $frameRows = Get-F45WrittenRows $script:f45.Writes[$script:f45.Writes.Count - 1]
                $frameRows.Count | Should -Be 1 -Because "the frame after the change to $width columns is one row"
                $last = [string]$frameRows[0]
                (Measure-F45DisplayCells $last) | Should -BeLessOrEqual ($width - 1)
                $rows[0].Text | Should -Be $last.TrimEnd()
                $script:TpmProgressOp.Live.Frame.Overflow | Should -BeFalse
            }
        }
    }

    It 'bounds the width by the window when the buffer is wider, and by the buffer when the window is wider (Windows Terminal case)' {
        # Mutation: bound the width by only one of the two reported widths -> the 126-wide one wins, the frame is 125 cells,
        # wraps at the real 110 columns and the one-row check fails.
        InModuleScope TpmProgress {
            foreach ($case in @(
                    @{ Window = 110; Buffer = 126; Wrap = 110; Source = 'Window' },
                    @{ Window = 126; Buffer = 110; Wrap = 110; Source = 'Buffer' })) {
                Reset-F45Surface -Width 110 -Style 'Unicode' -WindowWidth $case.Window -BufferWidth $case.Buffer -WrapWidth $case.Wrap
                $null = Start-TpmProgressOperation -Title 'Support package' -Stage 'Scanning Support profile scan' -Total 62
                Set-F45OwnerValues
                Step-F45Frame
                $frameRows = Get-F45WrittenRows $script:f45.Writes[$script:f45.Writes.Count - 1]
                $frameRows.Count | Should -Be 1
                $row = [string]$frameRows[0]
                (Measure-F45DisplayCells $row) | Should -BeLessOrEqual 109
                @(Get-F45Rows).Count | Should -Be 1
                $script:TpmProgressOp.Live.Frame.WidthSource | Should -Be $case.Source
                $script:TpmProgressOp.Live.Frame.FrameWidth | Should -Be 109
                Stop-TpmProgressAbandoned
            }
        }
    }

    It 'records how the width was decided and keeps the previous width while the window query fails' {
        # Mutation: fall back to the fixed 79 instead of the previous width -> 79 instead of 109.
        InModuleScope TpmProgress {
            $script:TpmProgressLastWidth = 0
            $script:f45.WindowWidth = 110; $script:f45.BufferWidth = 300
            Get-TpmProgressWidth -Live | Should -Be 109
            $script:TpmProgressLastWidthSource | Should -Be 'Window'
            $script:f45.WindowWidth = 0
            Get-TpmProgressWidth -Live | Should -Be 109
            $script:TpmProgressLastWidthSource | Should -Be 'Previous'
            $script:f45.BufferWidth = 50
            Get-TpmProgressWidth -Live | Should -Be 49
            $script:TpmProgressLastWidthSource | Should -Be 'Buffer'
        }
    }

    It 'records nothing and erases nothing when the cursor ends where the frame''s own glyphs cannot explain' {
        # Foreign output that lands right after a frame write (another thread or a child process): not a wrap of ours.
        # Mutation: record every unexpected cursor end as an overflow region -> the next redraw blanks "Foreign line".
        InModuleScope TpmProgress {
            Reset-F45Surface -Width 121
            $null = Start-TpmProgressOperation -Title 'Support package' -Stage 'Scanning Support profile scan' -Total 62
            $script:f45.Inject = "`nForeign line`n"
            Step-F45Frame
            $script:TpmProgressOp.Live.Frame.Overflow | Should -BeFalse
            [bool]$script:TpmProgressOp.Live['ForceAscii'] | Should -BeFalse
            Step-F45Frame
            $foreign = @(Get-F45Rows | Where-Object { $_.Text -eq 'Foreign line' })
            $foreign.Count | Should -Be 1
            $foreign[0].Top | Should -Be 1
        }
    }

    # In the wide-glyph tests the host draws every ambiguous-width glyph two cells wide: the block cells AND the middle dot
    # that fills the empty part of the bar (both are East Asian "ambiguous" width, so a real CJK-mode console widens both).
    # The very first frame already wraps (its dots alone add cells), so the overflow is registered when the bar starts.
    It 'lifts every row of a frame whose glyphs took two cells before a prompt, so nothing is left below the prompt' {
        # Mutation: record the wrapped frame with its composed cells (skip Register-TpmProgressOverflow) -> the lift blanks
        # only the first row and the wrapped remainder ")   ... /" stays below the prompt (the owner's stray fragment).
        InModuleScope TpmProgress {
            Reset-F45Surface -Width 121 -Style 'Unicode'
            foreach ($code in @(0x2588, 0x2589, 0x258A, 0x258B, 0x258C, 0x258D, 0x258E, 0x258F, 0x00B7)) { $script:f45.Wide[$code] = $true }
            $null = Start-TpmProgressOperation -Title 'Support package' -Stage 'Scanning Support profile scan' -Total 62
            @(Get-F45Rows).Count | Should -Be 2
            $frame = $script:TpmProgressOp.Live.Frame
            $frame.Overflow | Should -BeTrue
            $frame.FrameRows | Should -Be 2
            $frame.FrameTop | Should -Be 0
            Suspend-TpmProgressLine
            Write-F45Cells 'Choose O or B: '
            $rows = @(Get-F45Rows)
            $rows.Count | Should -Be 1
            $rows[0].Text | Should -Be 'Choose O or B:'
            $rows[0].Top | Should -Be 0
            Resume-TpmProgressLine
        }
    }

    It 'erases every row of a frame whose glyphs took two cells, then draws ASCII glyphs on one row' {
        # Mutation: drop the ForceAscii assignment in Register-TpmProgressOverflow -> the next frame wraps again (two rows).
        # Mutation 2: redraw an overflow region in place -> the wrapped remainder row stays.
        InModuleScope TpmProgress {
            Reset-F45Surface -Width 121 -Style 'Unicode'
            foreach ($code in @(0x2588, 0x2589, 0x258A, 0x258B, 0x258C, 0x258D, 0x258E, 0x258F, 0x00B7)) { $script:f45.Wide[$code] = $true }
            $null = Start-TpmProgressOperation -Title 'Support package' -Stage 'Scanning Support profile scan' -Total 62
            $script:TpmProgressOp.Live.Frame.Overflow | Should -BeTrue
            $script:TpmProgressOp.Live['ForceAscii'] | Should -BeTrue
            Set-F45OwnerValues
            Step-F45Frame
            $rows = @(Get-F45Rows)
            $rows.Count | Should -Be 1
            $rows[0].Top | Should -Be 0
            $rows[0].Text | Should -Match '^Support package: Scanning Support profile scan \|#+'
            $rows[0].Text | Should -Not -Match '[^\x20-\x7E]'
            $script:TpmProgressOp.Live.Frame.Overflow | Should -BeFalse
            Complete-TpmProgressOperation -State Final
            $script:TpmProgressGlyphCells | Should -BeFalse -Because 'later operations must not use the glyphs this host drew two cells wide'
        }
    }

    It 'finds every row of a two-row frame whose glyphs wrapped and scrolled the buffer, and erases only its own rows' {
        # Mutation: count only the last row's wrap (rows from the cursor movement alone) -> the first bar row above the
        # region survives; or count one row too many -> "Line B" above the bar is blanked.
        InModuleScope TpmProgress {
            Reset-F45Surface -Width 121 -Style 'Unicode' -BufferHeight 5
            # The glyphs turn wide only after the first two frames, so the 4-row frame is the one that wraps and scrolls.
            Write-F45Cells "Line A`nLine B`n"
            $script:f45.Top | Should -Be 2
            $null = Start-TpmProgressOperation -Title 'Support package' -Stage 'Scanning Support profile scan' -Total 62
            $null = Add-TpmProgressTask -Description 'Child task' -Total 62
            @(Get-F45Rows).Count | Should -Be 4
            $task = $script:TpmProgressOp.Tasks[0]
            $task.Current = 58
            $task.StageStarted = $script:f45.Now.AddMilliseconds(-100)
            Set-F45OwnerValues
            foreach ($code in @(0x2588, 0x2589, 0x258A, 0x258B, 0x258C, 0x258D, 0x258E, 0x258F, 0x00B7)) { $script:f45.Wide[$code] = $true }
            Step-F45Frame
            # Both rows wrapped once and the last wrap scrolled the buffer: "Line A" is gone, the frame covers rows 1 to 4.
            $frame = $script:TpmProgressOp.Live.Frame
            $frame.Overflow | Should -BeTrue
            $frame.FrameRows | Should -Be 4
            $frame.FrameTop | Should -Be 1
            Step-F45Frame
            $rows = @(Get-F45Rows)
            $rows.Count | Should -Be 3
            $rows[0].Text | Should -Be 'Line B'
            $rows[1].Top | Should -Be 1
            $rows[1].Text | Should -Match 'Support package: Scanning Support profile scan \|#+'
            $rows[2].Top | Should -Be 2
            $rows[2].Text | Should -Match 'Child task \|#+'
        }
    }

    It 'does not treat a cursor past the bar''s cells as moved into the bar, so text written after the bar keeps its place' {
        # Mutation: drop the column check in Find-TpmProgressMovedRegion -> the owner update redraws in place and leaves the
        # cursor at the bar's end, where the next write lands on "abc".
        InModuleScope TpmProgress {
            Reset-F45Surface -Width 121
            $null = Start-TpmProgressOperation -Title 'Scanning' -Stage 'Support profile scan' -Total 62 -Width 60
            Write-F45Cells 'abc'
            $script:f45.Now = $script:f45.Now.AddSeconds(1)
            Set-TpmProgressStage -Stage 'Support profile scan' -Current 10 -Total 62
            $rows = @(Get-F45Rows)
            $rows.Count | Should -Be 2
            $rows[0].Text | Should -Match 'abc$'
            $rows[1].Top | Should -Be 1
            $rows[1].Text | Should -Match '10/62'
            $script:f45.Top | Should -Be 1
        }
    }

    It 'erases the bar row a caller moved the cursor into before printing a menu there, so no bar fragment stays beside the menu' {
        # The ReShade chooser pattern (owner screenshot S1): each menu line is printed after SetCursorPosition(0, current
        # row) through the Write-Host proxy, and the bar is redrawn below every newline.
        # Mutation: drop the Find-TpmProgressMovedRegion fallback in Remove-TpmProgressLiveRegion -> every menu row keeps
        # the rest of the bar to its right and "Choice:" is written over a bar.
        InModuleScope TpmProgress {
            Reset-F45Surface -Width 121
            $null = Start-TpmProgressOperation -Title 'ReShade setup'
            $lines = @('  [1] * Original', '  [2]   Filmic Sharpen', '  Current selection: Original', '  Choose: [1-2] Select profile  [U] Use selected profile')
            foreach ($line in $lines) {
                $script:f45.Left = 0
                Write-F45Host $line -NoNewline
                Write-F45Host "`n" -NoNewline
            }
            $script:f45.Left = 0
            Suspend-TpmProgressLine
            Write-F45Cells '  Choice: '
            $rows = @(Get-F45Rows)
            $rows.Count | Should -Be 5
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $rows[$i].Top | Should -Be $i
                $rows[$i].Text | Should -Be $lines[$i]
            }
            $rows[4].Text | Should -Be '  Choice:'
            Resume-TpmProgressLine
        }
    }

    It 'never erases a moved-to bar row whose cells no longer hold the bar text' {
        # Mutation: skip the cell read-back comparison in Find-TpmProgressMovedRegion -> the row is blanked and the text
        # someone else wrote there ("Typed") is lost.
        InModuleScope TpmProgress {
            Reset-F45Surface -Width 121
            $null = Start-TpmProgressOperation -Title 'ReShade setup'
            $script:f45.Left = 0
            Write-F45Cells 'Typed'
            $script:f45.Left = 0
            $lifted = Suspend-TpmProgressOutput
            $lifted | Should -BeTrue
            Should -Invoke Clear-TpmProgressCells -Times 0 -Exactly
            @(Get-F45Rows)[0].Text | Should -Match '^Typed'
            Resume-TpmProgressOutput
        }
    }

    It 'redraws in place when an owner update finds the cursor moved into its unchanged row, instead of stacking a second bar' {
        # Mutation: drop the Find-TpmProgressMovedRegion call in Write-TpmProgressLiveFrame -> a second bar row is appended
        # below the first.
        InModuleScope TpmProgress {
            Reset-F45Surface -Width 121
            $null = Start-TpmProgressOperation -Title 'Scanning' -Stage 'Support profile scan' -Total 62
            $script:f45.Left = 7
            $script:f45.Now = $script:f45.Now.AddSeconds(1)
            Set-TpmProgressStage -Stage 'Support profile scan' -Current 10 -Total 62
            $rows = @(Get-F45Rows)
            $rows.Count | Should -Be 1
            $rows[0].Top | Should -Be 0
            $rows[0].Text | Should -Match '10/62'
        }
    }

    It 'lets the background writer park, never draw, while the cursor sits in its row where a caller moved it' {
        # Mutation: let the background writer use Find-TpmProgressMovedRegion as well -> it redraws in place and moves the
        # cursor away from the column the caller set before printing.
        InModuleScope TpmProgress {
            Reset-F45Surface -Width 121
            $null = Start-TpmProgressOperation -Title 'Scanning' -Stage 'Support profile scan' -Total 62
            $before = (@(Get-F45Rows)[0]).Text
            $writes = $script:f45.Writes.Count
            $script:f45.Left = 0
            Step-F45Frame -Background
            $script:TpmProgressOp.Live.Parked | Should -BeTrue
            $script:f45.Writes.Count | Should -Be $writes
            $script:f45.Left | Should -Be 0
            (@(Get-F45Rows)[0]).Text | Should -Be $before
        }
    }

    It 'leaves the cursor directly below the closed bar: the module adds no blank rows before the result text' {
        # Owner screenshot S3 showed about ten blank rows between the finished bar and the result text. The module's own
        # part is exactly one closing row and a line break.
        # Mutation: end the closing frame with two line breaks -> the result text moves one row further down.
        InModuleScope TpmProgress {
            Reset-F45Surface -Width 121
            $null = Start-TpmProgressOperation -Title 'Support package' -Group
            Set-TpmProgressStage -Stage 'Scanning Support profile scan' -Current 58 -Total 62
            Step-F45Frame
            Complete-TpmProgressOperation -State Final
            Write-F45Host ''
            Write-F45Host '  Support package created.'
            $rows = @(Get-F45Rows)
            $rows.Count | Should -Be 2
            $rows[0].Top | Should -Be 0
            $rows[0].Text | Should -Match '^Support package'
            $rows[1].Top | Should -Be 2
            $rows[1].Text | Should -Be '  Support package created.'
            $script:f45.Top | Should -Be 3
            $script:f45.Left | Should -Be 0
        }
    }
}
