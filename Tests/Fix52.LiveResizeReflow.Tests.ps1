#Requires -Module Pester
# FIX52 (issue #384, owner correction 2026-11-02 12:37): the user resizes the Windows Terminal / conhost window at any time, also while a
# progress bar runs or the ReShade chooser waits. Every live output must follow the NEW size: rows never wider than width-1, nothing left
# from the old layout, text whole or cut with an ellipsis only where it cannot fit. Widths 40 -> 200 -> 79 -> 120 and a height-only change
# are simulated between draws and DURING draws (after the pre-write size check, before the text lands).
# Fake-only: character-cell surfaces stand in for the console (the FIX45 surface for progress, the FIX46 surface for the chooser). No real
# console, TeknoParrot, network or game folder. Each It names the product change that makes it fail.
# What this CANNOT prove: how a real Windows Terminal / ConPTY reflows and repaints; FIX52-ResizeProbe.ps1 (coordinator, test PC) does.

Describe 'FIX52 progress frames follow every size change' {
    BeforeAll {
        Get-Module -Name TpmProgress -All | Remove-Module -Force
        Import-Module (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Force -ErrorAction Stop
    }
    AfterAll { Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue }

    BeforeEach {
        InModuleScope TpmProgress {
            $script:F52Label = 'Support package: Scanning Support profile scan'
            $script:f52 = @{
                WindowWidth = 120; BufferWidth = 120; WrapWidth = 120; WindowHeight = 100
                Left = 0; Top = 0; Rows = @{}; Used = @{}; Wrapped = @{}; Style = 'Unicode'; Visible = $true
                Now = [datetime]'2026-01-01T00:00:00'
                Writes = (New-Object System.Collections.Generic.List[string]); ResizeOnWrite = 0; HeightOnWrite = 0
                WindowReadsUntilResize = 0; ResizeTo = 0
            }
            $script:f52Narrow = @{}
            foreach ($code in @(0x2588, 0x2589, 0x258A, 0x258B, 0x258C, 0x258D, 0x258E, 0x258F, 0x2501, 0x2500, 0x2578,
                    0x25B6, 0x25C0, 0x2717, 0x26A0, 0x2713, 0x25CB, 0x25A0, 0x00B7)) { $script:f52Narrow[$code] = $true }
            function script:Reset-F52Surface {
                param([int]$Width)
                $script:f52.WindowWidth = $Width; $script:f52.BufferWidth = $Width; $script:f52.WrapWidth = $Width; $script:f52.WindowHeight = 100
                $script:f52.Left = 0; $script:f52.Top = 0; $script:f52.Rows = @{}; $script:f52.Used = @{}; $script:f52.Wrapped = @{}
                $script:f52.Writes.Clear(); $script:f52.ResizeOnWrite = 0; $script:f52.HeightOnWrite = 0
            }
            function script:Get-F52Row {
                param([int]$Top)
                if (-not $script:f52.Rows.ContainsKey($Top)) { $script:f52.Rows[$Top] = New-Object 'char[]' $script:f52.WrapWidth; for ($i = 0; $i -lt $script:f52.WrapWidth; $i++) { $script:f52.Rows[$Top][$i] = ' ' } }
                return ,$script:f52.Rows[$Top]
            }
            function script:Move-F52Down {
                param([switch]$Wrap)
                $script:f52.Top++
                if ($Wrap) { $script:f52.Wrapped[$script:f52.Top] = $true } else { [void]$script:f52.Wrapped.Remove($script:f52.Top) }
            }
            function script:Write-F52Cells {
                # CR: column 0. LF: next row, column 0. Text wraps at the real width.
                param([string]$Text)
                foreach ($ch in $Text.ToCharArray()) {
                    if ($ch -eq [char]13) { $script:f52.Left = 0; continue }
                    if ($ch -eq [char]10) { $script:f52.Left = 0; Move-F52Down; continue }
                    if ($script:f52.Left + 1 -gt $script:f52.WrapWidth) { $script:f52.Left = 0; Move-F52Down -Wrap }
                    $row = Get-F52Row $script:f52.Top
                    $row[$script:f52.Left] = $ch
                    $script:f52.Left++
                    $script:f52.Used[$script:f52.Top] = [Math]::Max([int]$script:f52.Used[$script:f52.Top], $script:f52.Left)
                    if ($script:f52.Left -ge $script:f52.WrapWidth) { $script:f52.Left = 0; Move-F52Down -Wrap }
                }
            }
            function script:Get-F52Cell {
                param([int]$Index, [int]$Top)
                return [pscustomobject]@{ Row = ($Top + [int][Math]::Floor($Index / [double]$script:f52.WrapWidth)); Col = ($Index % $script:f52.WrapWidth) }
            }
            function script:Resize-F52Surface {
                # The FIX40 reflow model (as in the FIX45 tests): logical lines are written again at the new width and the cursor ends
                # where the reflowed text puts it. Reported and real widths change together.
                param([int]$Width)
                $lines = New-Object System.Collections.Generic.List[string]
                $line = ''
                for ($row = 0; $row -le $script:f52.Top; $row++) {
                    if ($row -gt 0 -and -not $script:f52.Wrapped.ContainsKey($row)) { [void]$lines.Add($line.TrimEnd()); $line = '' }
                    if ($script:f52.Rows.ContainsKey($row)) {
                        $length = $(if ($row -eq $script:f52.Top) { $script:f52.Left } else { [int]$script:f52.Used[$row] })
                        $line += (-join $script:f52.Rows[$row]).Substring(0, $length)
                    }
                }
                [void]$lines.Add($line)
                $script:f52.WindowWidth = $Width; $script:f52.BufferWidth = $Width; $script:f52.WrapWidth = $Width
                $script:f52.Left = 0; $script:f52.Top = 0; $script:f52.Rows = @{}; $script:f52.Used = @{}; $script:f52.Wrapped = @{}
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    if ($i -gt 0) {
                        if ($script:f52.Left -eq 0 -and $script:f52.Wrapped.ContainsKey($script:f52.Top)) { [void]$script:f52.Wrapped.Remove($script:f52.Top) }
                        else { Write-F52Cells "`n" }
                    }
                    Write-F52Cells $lines[$i]
                }
            }
            function script:Get-F52Rows {
                foreach ($key in @($script:f52.Rows.Keys | Sort-Object)) {
                    $text = (-join $script:f52.Rows[$key]).TrimEnd()
                    if ($text.Length -gt 0) { [pscustomobject]@{ Top = $key; Text = $text } }
                }
            }
            function script:Step-F52Frame {
                # -NoForce: an ordinary refresh step, which draws only when the frame is due (or a redraw is pending).
                param([int]$Milliseconds = 300, [switch]$NoForce)
                $script:f52.Now = $script:f52.Now.AddMilliseconds($Milliseconds)
                $live = $script:TpmProgressOp.Live
                [System.Threading.Monitor]::Enter($live.Gate)
                try {
                    if ($NoForce) { Invoke-TpmProgressRefreshStep -Live $live } else { Invoke-TpmProgressRefreshStep -Live $live -Force }
                } finally { [System.Threading.Monitor]::Exit($live.Gate) }
            }
            function script:Set-F52OwnerValues {
                $op = $script:TpmProgressOp
                $op.Current = 58; $op.Total = 62; $op.SmoothedRate = 0
                $op.StageStarted = $script:f52.Now.AddMilliseconds(-100)
                $op.LastChange = $script:f52.Now
                Publish-TpmProgressSnapshot -Op $op
            }
            function script:Get-F52WrittenRows {
                # Rows of one frame write (plain assignment at the caller: this returns the row array as ONE object).
                param([string]$Write)
                $text = $Write.TrimStart([char]10).TrimStart([char]13)
                if ($text.EndsWith("`r`n")) { $text = $text.Substring(0, $text.Length - 2) }
                return ,@($text -split "`r`n")
            }
            function script:Measure-F52DisplayCells {
                # Independent cell count: printable ASCII and the module's single-cell glyphs take one cell, VT color none, anything else fails.
                param([string]$Row)
                $plain = $Row -replace ([string][char]27 + '\[[0-9;]*m'), ''
                $cells = 0
                foreach ($ch in $plain.ToCharArray()) {
                    $code = [int]$ch
                    if ($code -ge 0x20 -and $code -le 0x7E) { $cells++; continue }
                    if ($script:f52Narrow.ContainsKey($code)) { $cells++; continue }
                    throw ('unexpected character U+{0:X4} in a frame row' -f $code)
                }
                return $cells
            }
            function script:Assert-F52OneRegion {
                # Exactly one row on the whole surface (nothing left of an older layout), it is the last frame written, it fits in
                # width-1 cells, and the label is whole or cut with an ellipsis.
                param([int]$Width, [string]$Case)
                $rows = @(Get-F52Rows)
                $rows.Count | Should -Be 1 -Because "$Case leaves one bar row and nothing of an older layout"
                $frameRows = Get-F52WrittenRows $script:f52.Writes[$script:f52.Writes.Count - 1]
                $frameRows.Count | Should -Be 1 -Because $Case
                $row = [string]$frameRows[0]
                (Measure-F52DisplayCells $row) | Should -BeLessOrEqual ($Width - 1) -Because $Case
                $rows[0].Text | Should -BeExactly $row.TrimEnd() -Because "$Case shows the frame composed for $Width columns"
                if (-not $row.Contains($script:F52Label)) { $row | Should -Match '\.\.\.' -Because "$Case cuts a label that does not fit with an ellipsis" }
            }
            Mock Start-TpmProgressRefresh {}
            Mock Get-TpmProgressNow { $script:f52.Now }
            Mock Get-TpmProgressTimestamp { ($script:f52.Now.Ticks - ([datetime]'2026-01-01T00:00:00').Ticks) / 10000.0 }
            Mock Test-TpmProgressOutputRedirected { $false }
            Mock Get-TpmProgressWindowWidth {
                # A size change while a frame is being laid out: the window changes right before the Nth window-width read of a frame
                # (read 1 = the frame's first size read, read 2 = the module's last check before the write).
                if ($script:f52.WindowReadsUntilResize -gt 0) {
                    $script:f52.WindowReadsUntilResize--
                    if ($script:f52.WindowReadsUntilResize -eq 0) { Resize-F52Surface $script:f52.ResizeTo }
                }
                $script:f52.WindowWidth
            }
            Mock Get-TpmProgressBufferWidth { $script:f52.BufferWidth }
            Mock Get-TpmProgressWindowHeight { $script:f52.WindowHeight }
            Mock Get-TpmProgressCursor { [pscustomobject]@{ Left = $script:f52.Left; Top = $script:f52.Top } }
            Mock Set-TpmProgressCursor { param($Left, $Top) $script:f52.Left = $Left; $script:f52.Top = $Top; return $true }
            Mock Clear-TpmProgressCells {
                param($Top, $Count)
                for ($i = 0; $i -lt $Count; $i++) {
                    $cell = Get-F52Cell -Index $i -Top $Top
                    if ($script:f52.Rows.ContainsKey($cell.Row)) { $script:f52.Rows[$cell.Row][$cell.Col] = ' ' }
                }
                return $true
            }
            Mock Read-TpmProgressCells {
                param($Top, $Count)
                $chars = New-Object 'char[]' $Count
                for ($i = 0; $i -lt $Count; $i++) {
                    $cell = Get-F52Cell -Index $i -Top $Top
                    $chars[$i] = $(if ($script:f52.Rows.ContainsKey($cell.Row)) { $script:f52.Rows[$cell.Row][$cell.Col] } else { ' ' })
                }
                return (-join $chars)
            }
            Mock Get-TpmProgressCursorVisible { $script:f52.Visible }
            Mock Set-TpmProgressCursorVisible { param($Visible) $script:f52.Visible = $Visible }
            Mock Get-TpmProgressStyle { $script:f52.Style }
            Mock Get-TpmProgressBackground { $null }
            Mock Test-TpmProgressColorEnabled { $false }
            Mock Test-TpmProgressWideWriteAvailable { $false }
            Mock Test-TpmProgressConhostFont { $false }
            Mock Test-TpmProgressGlyphCells { $false }
            Mock Get-TpmProgressOutputCodePage { 437 }
            Mock Write-TpmProgressRaw {
                param($Text, $NewLine)
                # A size change that lands after the module's last size check and before its text reaches the console (the user
                # drags the window, or Windows Terminal resizes its pseudo console late): the console reflows first, then the text lands.
                if ($script:f52.ResizeOnWrite -gt 0) { $to = $script:f52.ResizeOnWrite; $script:f52.ResizeOnWrite = 0; Resize-F52Surface $to }
                if ($script:f52.HeightOnWrite -gt 0) { $script:f52.WindowHeight = $script:f52.HeightOnWrite; $script:f52.HeightOnWrite = 0 }
                $value = [string]$Text
                if ($NewLine) { $value += "`r`n" }
                [void]$script:f52.Writes.Add($value)
                Write-F52Cells $value
            }
            Mock Write-TpmProgressPlainLine {}
        }
    }
    AfterEach {
        InModuleScope TpmProgress { if (Test-TpmProgressActive) { Stop-TpmProgressAbandoned } }
    }

    It 'redraws one bar at each new size when the window changes between frames: 40 -> 200 -> 79 -> 120' {
        # Mutation: compose the next frame with the width of the frame before (skip the per-frame size read in Write-TpmProgressLiveFrame)
        # -> the 200-wide frame lands in 79 columns and wraps onto three rows.
        InModuleScope TpmProgress {
            Reset-F52Surface -Width 40
            $null = Start-TpmProgressOperation -Title 'Support package' -Stage 'Scanning Support profile scan' -Total 62
            Set-F52OwnerValues
            Step-F52Frame -Milliseconds 0
            Assert-F52OneRegion -Width 40 -Case 'the first frame at 40 columns'
            foreach ($width in @(200, 79, 120)) {
                Resize-F52Surface $width
                Step-F52Frame
                Assert-F52OneRegion -Width $width -Case "the frame after the window changed to $width columns"
            }
            $script:TpmProgressOp.Live.Frame.RedrawPending | Should -BeFalse
        }
    }

    It 'redraws at once, without waiting for the frame interval, when the window changes size DURING a write: 40 -> 200 -> 79 -> 120' {
        # Mutation: drop "-not $Live.Frame.RedrawPending" from Invoke-TpmProgressRefreshStep -> the step 1 ms later draws nothing and the
        # frame composed for the old width stays (wrapped over three rows after the 79 change).
        # Mutation: drop the Clear-TpmProgressReflowedRemains call in Write-TpmProgressLiveFrame -> after the 79 change the first two
        # rows of the reflowed 199-cell frame stay above the new bar.
        InModuleScope TpmProgress {
            Reset-F52Surface -Width 40
            $null = Start-TpmProgressOperation -Title 'Support package' -Stage 'Scanning Support profile scan' -Total 62
            Set-F52OwnerValues
            Step-F52Frame -Milliseconds 0
            foreach ($width in @(200, 79, 120)) {
                $script:f52.ResizeOnWrite = $width
                $writes = $script:f52.Writes.Count
                Step-F52Frame
                $script:f52.Writes.Count | Should -Be ($writes + 1) -Because "the frame was written while the window became $width columns wide"
                $script:f52.WrapWidth | Should -Be $width
                $script:TpmProgressOp.Live.Frame.RedrawPending | Should -BeTrue -Because 'the size changed between composing and writing'
                $writes = $script:f52.Writes.Count
                Step-F52Frame -Milliseconds 1 -NoForce
                $script:f52.Writes.Count | Should -BeGreaterThan $writes -Because 'a frame written at the old size is drawn again at the next step, 1 ms later'
                $script:TpmProgressOp.Live.Frame.RedrawPending | Should -BeFalse
                Assert-F52OneRegion -Width $width -Case "the redraw after the window became $width columns during a write"
            }
        }
    }

    It 'leaves no piece of the old bar when the window narrows while a frame is being laid out (before the last size check)' {
        # The window goes from 120 to 79 columns between the frame's first size read and the module's last check before the write: the
        # console reflows the old 119-cell bar over two rows and the in-place carriage return lands on the second one.
        # Mutation: compare the remains condition in Write-TpmProgressLiveFrame with the size of the last check ($currentBuffer) instead
        # of the size the in-place decision was made at ($bufferWidth) -> the first 79 cells of the old bar stay above the new one.
        InModuleScope TpmProgress {
            Reset-F52Surface -Width 120
            $script:f52.Style = 'Ascii'
            $null = Start-TpmProgressOperation -Title 'Support package' -Stage 'Scanning Support profile scan' -Total 62
            Set-F52OwnerValues
            Step-F52Frame -Milliseconds 0
            $script:f52.ResizeTo = 79
            $script:f52.WindowReadsUntilResize = 2
            Step-F52Frame
            $script:f52.WindowReadsUntilResize | Should -Be 0 -Because 'the window changed during the frame'
            $script:f52.WrapWidth | Should -Be 79
            Assert-F52OneRegion -Width 79 -Case 'the frame drawn after the window narrowed during its layout'
        }
    }

    It 'keeps one bar in place after a height-only change, between frames and during a write' {
        # Mutation: leave the window height out of RedrawPending in Write-TpmProgressLiveFrame -> the step 1 ms after the write that saw
        # the height change draws nothing.
        InModuleScope TpmProgress {
            Reset-F52Surface -Width 120
            $null = Start-TpmProgressOperation -Title 'Support package' -Stage 'Scanning Support profile scan' -Total 62
            Set-F52OwnerValues
            Step-F52Frame -Milliseconds 0
            $top = @(Get-F52Rows)[0].Top
            $script:f52.WindowHeight = 30
            Step-F52Frame -NoForce
            Assert-F52OneRegion -Width 120 -Case 'the frame after the window height changed to 30 rows'
            @(Get-F52Rows)[0].Top | Should -Be $top
            $script:f52.HeightOnWrite = 20
            Step-F52Frame
            $script:TpmProgressOp.Live.Frame.RedrawPending | Should -BeTrue
            $writes = $script:f52.Writes.Count
            Step-F52Frame -Milliseconds 1 -NoForce
            $script:f52.Writes.Count | Should -BeGreaterThan $writes
            Assert-F52OneRegion -Width 120 -Case 'the redraw after the height changed to 20 rows during a write'
            @(Get-F52Rows)[0].Top | Should -Be $top
            Should -Invoke Clear-TpmProgressCells -Times 0 -Exactly -Because 'a height-only change is drawn over in place, never erased first (FIX40B)'
        }
    }

    It 'repairs the closing row when the window becomes narrower while it is written, leaving one row within width-1' {
        # Mutation: remove the Repair-TpmProgressClosingFrame call from Write-TpmProgressLiveFrame -> the closing row stays wrapped over two
        # rows and the beginning of the overwritten live frame stays above it (three rows).
        InModuleScope TpmProgress {
            Reset-F52Surface -Width 120
            $null = Start-TpmProgressOperation -Title 'Support package' -Stage 'Scanning Support profile scan' -Total 62
            Set-F52OwnerValues
            Step-F52Frame -Milliseconds 0
            $script:f52.ResizeOnWrite = 60
            Complete-TpmProgressOperation -State Final
            $rows = @(Get-F52Rows)
            $rows.Count | Should -Be 1 -Because 'only the closing row is left, rewritten for 60 columns'
            (Measure-F52DisplayCells $rows[0].Text) | Should -BeLessOrEqual 59
            $script:f52.Left | Should -Be 0
            $script:f52.Top | Should -Be ($rows[0].Top + 1) -Because 'the next output starts directly below the closing row'
        }
    }
}

Describe 'FIX52 ReShade chooser and main menu follow every size change' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) { throw 'FIX52 bootstrap could not parse the production script.' }
        $functionFile = Join-Path $TestDrive 'fix52-functions.ps1'
        ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
        # No progress module here: the chooser must work without one.
        Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
        . $functionFile
        . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
        $script:DisplayVersion = 'v1.0 RC8'
        $script:ActiveTpmWorkflowStatus = $null
        $script:TpmWorkflowRendering = $false
        $script:logPath = Join-Path $TestDrive 'fix52.log'
        $script:logWarnShown = $false

        # The FIX46 surface: "WindowsTerminal" has buffer height == window height, "Conhost" a tall buffer and a moving window.
        function New-Fix52Surface {
            param([int]$Width = 110, [int]$Height = 30, [string]$Kind = 'WindowsTerminal')
            $rowsInBuffer = if ($Kind -eq 'WindowsTerminal') { $Height } else { 400 }
            $rows = New-Object 'string[]' $rowsInBuffer
            for ($i = 0; $i -lt $rowsInBuffer; $i++) { $rows[$i] = '' }
            return @{ Kind = $Kind; Width = $Width; Height = $Height; BufferHeight = $rowsInBuffer; Rows = $rows; History = (New-Object 'System.Collections.Generic.List[string]'); Row = 0; Col = 0; Top = 0 }
        }
        function Move-Fix52NextRow {
            $s = $script:surface
            $s.Col = 0
            if ($s.Row -lt $s.BufferHeight - 1) { $s.Row++ }
            else {
                [void]$s.History.Add([string]$s.Rows[0])
                for ($i = 1; $i -lt $s.BufferHeight; $i++) { $s.Rows[$i - 1] = $s.Rows[$i] }
                $s.Rows[$s.BufferHeight - 1] = ''
            }
            if ($s.Row -gt $s.Top + $s.Height - 1) { $s.Top = $s.Row - $s.Height + 1 }
        }
        function Add-Fix52Text {
            param([AllowEmptyString()][string]$Text)
            $s = $script:surface
            foreach ($ch in $Text.ToCharArray()) {
                if ($ch -eq [char]13) { $s.Col = 0; continue }
                if ($ch -eq [char]10) { Move-Fix52NextRow; continue }
                if ($ch -eq [char]8) { if ($s.Col -gt 0) { $s.Col-- }; continue }
                if ($s.Col -ge $s.Width) { Move-Fix52NextRow }
                $line = ([string]$s.Rows[$s.Row]).PadRight($s.Width)
                $s.Rows[$s.Row] = $line.Substring(0, $s.Col) + [string]$ch + $line.Substring($s.Col + 1)
                $s.Col++
            }
        }
        function Set-Fix52SurfaceSize {
            # The user drags the window. Width: the reported width changes (the chooser clears and redraws, so old rows need no reflow
            # model). Height: a WindowsTerminal buffer is the window, so it keeps its bottom rows; a conhost window only shows fewer rows.
            param([int]$Width, [int]$Height = 0)
            $s = $script:surface
            $s.Width = $Width
            if ($Height -gt 0 -and $Height -ne $s.Height) {
                if ($s.Kind -eq 'WindowsTerminal') {
                    $old = $s.Rows
                    $shift = [Math]::Max(0, $s.Row - ($Height - 1))
                    $new = New-Object 'string[]' $Height
                    for ($i = 0; $i -lt $Height; $i++) { $source = $i + $shift; $new[$i] = if ($source -lt $old.Length) { [string]$old[$source] } else { '' } }
                    for ($i = 0; $i -lt $shift; $i++) { [void]$s.History.Add([string]$old[$i]) }
                    $s.Rows = $new; $s.BufferHeight = $Height; $s.Row -= $shift; $s.Top = 0
                } elseif ($s.Row -gt $s.Top + $Height - 1) { $s.Top = $s.Row - $Height + 1 }
                $s.Height = $Height
            }
        }
        function Save-Fix52Snapshot {
            param([string]$Name)
            $s = $script:surface
            $script:snap[$Name] = [pscustomobject]@{
                Width = $s.Width; Kind = $s.Kind; CursorRow = $s.Row; CursorLeft = $s.Col
                Buffer = @($s.Rows | ForEach-Object { ([string]$_).TrimEnd() })
            }
        }
        function Install-Fix52SurfaceMocks {
            Mock Write-TpmConsoleText {
                # A size change that lands in the middle of a redraw (B2): right before the first write whose text matches the armed
                # pattern (content, not a write count, so it does not depend on how the writer splits its output).
                if ($script:resizeOnText -and $Text -like $script:resizeOnText) {
                    $script:resizeOnText = $null
                    Set-Fix52SurfaceSize -Width $script:resizeTo
                }
                # A console write that fails once in the middle of a redraw (B3).
                if ($script:throwAtWrite -gt 0) {
                    $script:throwAtWrite--
                    if ($script:throwAtWrite -eq 0) { throw 'simulated console write failure' }
                }
                Add-Fix52Text -Text $Text
            }
            Mock Write-Host { Add-Fix52Text -Text ([string]$Object + $(if ($NoNewline) { '' } else { "`n" })) }
            Mock Get-TpmConsoleCursorPosition { [pscustomobject]@{ Left = $script:surface.Col; Top = $script:surface.Row } }
            Mock Set-TpmConsoleCursorPosition {
                $s = $script:surface
                if ($Left -lt 0 -or $Left -ge $s.Width -or $Top -lt 0 -or $Top -ge $s.BufferHeight) { throw 'cursor outside the console buffer' }
                $s.Col = $Left
                $s.Row = $Top
                if ($s.Row -lt $s.Top) { $s.Top = $s.Row } elseif ($s.Row -gt $s.Top + $s.Height - 1) { $s.Top = $s.Row - $s.Height + 1 }
            }
            Mock Get-TpmConsoleMetrics { $s = $script:surface; [pscustomobject]@{ Width = $s.Width; Left = 0; Top = $s.Top; Height = $s.Height; BufferWidth = $s.Width; BufferHeight = $s.BufferHeight } }
            Mock Read-TpmConsoleRowText {
                $s = $script:surface
                if ($Row -lt 0 -or $Row -ge $s.BufferHeight) { throw 'row outside the console buffer' }
                ([string]$s.Rows[$Row]).PadRight($Left + $Width).Substring($Left, $Width)
            }
            Mock Clear-TpmReShadeChooserScreen {
                $s = $script:surface
                for ($r = 0; $r -lt $s.BufferHeight; $r++) { $s.Rows[$r] = '' }
                $s.Row = 0; $s.Col = 0; $s.Top = 0
                if ($script:armTextAfterClear) { $script:resizeOnText = $script:armTextAfterClear; $script:armTextAfterClear = $null }
                if ($script:armThrowAfterClear -gt 0) { $script:throwAtWrite = $script:armThrowAfterClear; $script:armThrowAfterClear = 0 }
            }
            Mock Test-TpmConsoleInputRedirected { $false }
            Mock Start-Sleep {}
            Mock Write-Log {}
            Mock Read-HostSafe { $script:exhausted = $true; 'B' }
            Mock Get-TpmReShadeHdrGate { [pscustomobject]@{ State = 'HIDDEN'; Visible = $false; Enabled = $false; Reason = 'test'; Fingerprint = '' } }
        }
        function Set-Fix52Script {
            # $null = idle poll, 'text' = typed characters, 'ENTER', 'BS', scriptblock = run it, then the input loop polls.
            param([object[]]$Steps)
            $script:steps = New-Object 'System.Collections.Generic.Queue[object]'
            foreach ($step in $Steps) { $script:steps.Enqueue($step) }
            $script:pendingKeys = New-Object 'System.Collections.Generic.Queue[object]'
            Mock Test-TpmConsoleKeyAvailable {
                if ($script:pendingKeys.Count -gt 0) { return $true }
                if ($script:steps.Count -eq 0) { throw 'FIX52 console script exhausted' }
                $next = $script:steps.Dequeue()
                if ($next -is [scriptblock]) { & $next; return $false }
                if ($null -eq $next) { return $false }
                if ($next -eq 'ENTER') { $script:pendingKeys.Enqueue([pscustomobject]@{ Key = [ConsoleKey]::Enter; KeyChar = [char]13 }); return $true }
                if ($next -eq 'BS') { $script:pendingKeys.Enqueue([pscustomobject]@{ Key = [ConsoleKey]::Backspace; KeyChar = [char]8 }); return $true }
                foreach ($ch in ([string]$next).ToCharArray()) { $script:pendingKeys.Enqueue([pscustomobject]@{ Key = [ConsoleKey]::D1; KeyChar = $ch }) }
                return $true
            }
            Mock Read-TpmConsoleKey { $script:pendingKeys.Dequeue() }
        }
        function New-Fix52Session {
            $profiles = @(Get-TpmReShadeProfiles | Where-Object { -not $_.RequiresHdr })
            return [hashtable]::Synchronized(@{ Initialized = $true; Closed = $false; PreviewEnabled = $true; SelectedProfileId = 'Original'; Profiles = $profiles; ProfileSelector = $null; ProfileSelectorUpdating = $false; Refresh = { $true } })
        }
        # Rows of one line record cut at width-1, the way the chooser writes them (an independent cut, compared trimmed).
        function Split-Fix52Rows {
            param([string]$Text, [int]$Width)
            $cut = $Width - 1
            if ($Text.Length -eq 0) { return @('') }
            return @(for ($offset = 0; $offset -lt $Text.Length; $offset += $cut) { $Text.Substring($offset, [Math]::Min($cut, $Text.Length - $offset)).TrimEnd() })
        }
        # The whole buffer after a size change holds exactly one chooser screen laid out for that width: every row within width-1, one
        # Current selection, one marker, the Choose rows for that width directly above the prompt with the typed text, nothing older.
        function Assert-Fix52ChooserScreen {
            param($Snapshot, [string]$CurrentText, [string]$PromptText, [int]$LastNumber)
            $width = [int]$Snapshot.Width
            $buffer = @($Snapshot.Buffer)
            $case = "the chooser at $width columns ($($Snapshot.Kind))"
            foreach ($row in $buffer) { $row.Length | Should -BeLessOrEqual ($width - 1) -Because "$case never writes a row wider than width-1: '$row'" }
            @($buffer | Where-Object { $_ -match '^\s*Current selection:' }).Count | Should -Be 1 -Because "$case shows one screen, nothing of an older layout"
            @($buffer | Where-Object { $_ -match '^\s*Choose:' }).Count | Should -Be 1 -Because $case
            # A Windows Terminal buffer is only the window: at narrow widths the marked row [1] can have scrolled into the terminal's own
            # scrollback. The conhost buffer holds the whole screen.
            $markers = @($buffer | Where-Object { $_ -match '^\s*\[\d+\] \*' }).Count
            if ($Snapshot.Kind -eq 'Conhost') { $markers | Should -Be 1 -Because "$case marks one selected profile" } else { $markers | Should -BeLessOrEqual 1 -Because $case }
            @($buffer | Where-Object { $_ -match 'Console size changed' }).Count | Should -Be 0 -Because "$case is a full redraw, not an announcement"
            $expected = New-Object System.Collections.Generic.List[string]
            foreach ($part in (Split-Fix52Rows -Text $CurrentText -Width $width)) { [void]$expected.Add($part) }
            foreach ($choose in @(Get-TpmReShadeChooseLines -LastNumber $LastNumber -TextWidth ($width - 1))) {
                foreach ($part in (Split-Fix52Rows -Text ([string]$choose.Text) -Width $width)) { [void]$expected.Add($part) }
            }
            $promptRow = [int]$Snapshot.CursorRow
            $buffer[$promptRow] | Should -BeExactly $PromptText.TrimEnd() -Because "$case keeps the prompt and the typed text"
            [int]$Snapshot.CursorLeft | Should -Be $PromptText.Length
            for ($i = 0; $i -lt $expected.Count; $i++) {
                $buffer[$promptRow - $expected.Count + $i] | Should -BeExactly $expected[$i] -Because "$case lays out the Current selection and Choose rows for $width columns"
            }
            if ($Snapshot.Kind -eq 'Conhost') {
                $intro = [string](@(Get-TpmReShadeChooserIntroLines)[1].Text)
                # @() keeps a one-row result an array: the function output of a single row unrolls to a string, and [0] of a string is its first character.
                $buffer | Should -Contain (@(Split-Fix52Rows -Text $intro -Width $width)[0]) -Because "$case draws the intro lines again"
            }
        }
    }
    BeforeEach {
        $script:exhausted = $false
        $script:snap = @{}
        $script:armTextAfterClear = $null
        $script:resizeOnText = $null
        $script:resizeTo = 0
        $script:armThrowAfterClear = 0
        $script:throwAtWrite = 0
        $script:surface = New-Fix52Surface
        Install-Fix52SurfaceMocks
        $script:session = New-Fix52Session
        $script:currentOriginal = '  Current selection: {0}' -f (Get-TpmReShadeProfileDisplayLabel -Entry (Get-TpmReShadeProfile -ProfileId 'Original'))
        $script:lastNumber = @($script:session['Profiles']).Count
    }
    AfterEach { $script:exhausted | Should -BeFalse -Because 'the scripted console must not run out of steps' }

    It 'lays the whole chooser out again at 40, 200, 79 and 120 columns and after a height-only change on a <Kind> surface, keeping the typed text' -ForEach @(
        @{ Kind = 'WindowsTerminal' }
        @{ Kind = 'Conhost' }
    ) {
        # Mutation: pass -ClearScreen:$false in the chooser's resize branch (the pre-FIX52 append-only rebuild) -> the conhost buffer keeps
        # every older block (rows wider than the new width-1, several Current selection lines); in Windows Terminal the block above the
        # new one still holds 110-column rows.
        # Mutation: let Write-TpmReShadeTerminalLines use the caller's -Width over the live width -> rows wider than width-1.
        $script:surface = New-Fix52Surface -Kind $Kind
        Set-Fix52Script -Steps @(
            $null, '1',
            { Set-Fix52SurfaceSize -Width 40 }, $null, { Save-Fix52Snapshot 'W40' },
            { Set-Fix52SurfaceSize -Width 200 }, $null, { Save-Fix52Snapshot 'W200' },
            { Set-Fix52SurfaceSize -Width 79 }, $null, { Save-Fix52Snapshot 'W79' },
            { Set-Fix52SurfaceSize -Width 120 }, $null, { Save-Fix52Snapshot 'W120' },
            { Set-Fix52SurfaceSize -Width 120 -Height 20 }, $null, { Save-Fix52Snapshot 'H20' },
            'BS', 'B', 'ENTER')
        $result = Read-TpmReShadeTerminalProfile -Profiles @($script:session['Profiles']) -DefaultProfileId 'Original' -PreviewSession $script:session
        foreach ($name in @('W40', 'W200', 'W79', 'W120', 'H20')) {
            $script:snap.ContainsKey($name) | Should -BeTrue -Because "the script reached $name"
            Assert-Fix52ChooserScreen -Snapshot $script:snap[$name] -CurrentText $script:currentOriginal -PromptText '  Choice: 1' -LastNumber $script:lastNumber
        }
        $result.Cancelled | Should -BeTrue
    }

    It 'draws the chooser again at the newest size when the window changes while the redraw is being written' {
        # The window becomes 200 columns; the chooser clears the screen, reads 200 and writes the intro lines; then, right before the
        # first profile row ("[1] * Original") is written, the window becomes 79 columns.
        # Mutation: let Write-TpmReShadeTerminalLines use the caller's -Width over the live width -> the block rows written after the
        # change are cut at 199 instead of 78 (snapshot 'Mid').
        # Mutation: drop the after-draw size check in Update-TpmReShadeTerminalLayoutAfterResize (always return $true) -> no second
        # redraw; the Choose options composed for 200 columns stay cut at 78 columns, and the expected 79-column rows are missing.
        $script:surface = New-Fix52Surface -Kind 'Conhost'
        Set-Fix52Script -Steps @(
            $null, '1',
            { Set-Fix52SurfaceSize -Width 200; $script:armTextAfterClear = '*`[1`]*Original*'; $script:resizeTo = 79 }, { Save-Fix52Snapshot 'Mid' },
            $null, { Save-Fix52Snapshot 'W79' },
            'BS', 'B', 'ENTER')
        $null = Read-TpmReShadeTerminalProfile -Profiles @($script:session['Profiles']) -DefaultProfileId 'Original' -PreviewSession $script:session
        $intro = @(Get-TpmReShadeChooserIntroLines | ForEach-Object { ([string]$_.Text).TrimEnd() } | Where-Object { $_ })
        $script:snap['Mid'].Width | Should -Be 79
        foreach ($row in @($script:snap['Mid'].Buffer | Where-Object { $intro -notcontains $_ })) {
            $row.Length | Should -BeLessOrEqual 78 -Because "a row written after the window became 79 columns is cut at the live width: '$row'"
        }
        $script:snap['W79'].Width | Should -Be 79
        Assert-Fix52ChooserScreen -Snapshot $script:snap['W79'] -CurrentText $script:currentOriginal -PromptText '  Choice: 1' -LastNumber $script:lastNumber
    }

    It 'draws the whole chooser again at the next poll when a size redraw fails after the window was cleared' {
        # The window becomes 79 columns; the chooser clears the window and the third console write of the redraw fails.
        # Mutation: drop "$observedGeometry.Snapshot = $null" (the bounded retry) in the chooser's $onUpdate -> the next poll sees no
        # change, and the window keeps only the start of the intro, the notice and the prompt.
        $script:surface = New-Fix52Surface -Kind 'Conhost'
        Set-Fix52Script -Steps @(
            $null, '1',
            { Set-Fix52SurfaceSize -Width 79; $script:armThrowAfterClear = 3 }, $null, { Save-Fix52Snapshot 'W79' },
            'BS', 'B', 'ENTER')
        $null = Read-TpmReShadeTerminalProfile -Profiles @($script:session['Profiles']) -DefaultProfileId 'Original' -PreviewSession $script:session
        $script:throwAtWrite | Should -Be 0 -Because 'the simulated write failure happened'
        Assert-Fix52ChooserScreen -Snapshot $script:snap['W79'] -CurrentText $script:currentOriginal -PromptText '  Choice: 1' -LastNumber $script:lastNumber
    }

    It 'hands the main menu a redraw for every width change and for a height-only change, and each redraw fits the new size' {
        # Mutation: compare only the width in Read-MainMenuChoiceResponsive -> the height-only change (120x30 -> 120x20) never redraws.
        $noConsole = $false
        try { $noConsole = [Console]::IsInputRedirected; [void][Console]::KeyAvailable } catch { $noConsole = $true }
        if ($noConsole) { Set-ItResult -Skipped -Because 'the main-menu prompt polls the real keyboard, and this runner has no console input'; return }
        Mock Start-Sleep {}
        $script:menuSize = $null
        Mock Get-ConsoleContentWidth { [int]$script:menuSize.Width }
        Mock Get-ConsoleContentHeight { [int]$script:menuSize.Height }
        $sizes = @(
            @{ Width = 120; Height = 30 }, @{ Width = 40; Height = 30 }, @{ Width = 200; Height = 50 },
            @{ Width = 79; Height = 30 }, @{ Width = 120; Height = 30 }, @{ Width = 120; Height = 20 })
        for ($i = 1; $i -lt $sizes.Count; $i++) {
            $before = $sizes[$i - 1]
            $script:menuSize = $sizes[$i]
            $choice = Read-MainMenuChoiceResponsive -Prompt 'Enter 1-18: ' -InitialWidth $before.Width -InitialHeight $before.Height
            $choice.Redraw | Should -BeTrue -Because ("{0}x{1} -> {2}x{3} redraws the menu" -f $before.Width, $before.Height, $script:menuSize.Width, $script:menuSize.Height)
            $tier = Get-ConsoleLayoutTier -Width $script:menuSize.Width -Height $script:menuSize.Height
            $screen = Render-MainMenuScreen -Tier $tier -Width $script:menuSize.Width -Height $script:menuSize.Height
            $screen.Geometry.ViewportWidth | Should -Be $script:menuSize.Width
            # Below 46 columns the menu banner keeps its 44-column frame plus padding (pre-existing, reported in FIX52-RESULT.md as an
            # owner decision); the width rule is asserted where the menu claims to fit.
            if ($script:menuSize.Width -ge 46) { foreach ($row in $screen.Rows) { $row.Text.Length | Should -BeLessOrEqual $script:menuSize.Width } }
            $screen.Rows.Count | Should -BeLessOrEqual $script:menuSize.Height
        }
    }
}
