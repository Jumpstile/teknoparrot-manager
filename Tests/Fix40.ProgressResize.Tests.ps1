#Requires -Module Pester
# FIX40: the live progress bar while the console window is resized. Fake-only: a recording character-cell surface that
# reflows its text when the width changes (the same model as Fix16B.Progress.Tests.ps1) stands in for the console; no
# product entry point, real console, scheduler or network is used. What this CANNOT prove: how a real Windows Terminal /
# ConPTY repaints its buffer during a drag resize. The surface reflows exactly the way the renderer's own row model
# expects, apart from the one test that moves the cursor to a column the model did not predict.
BeforeAll {
    Get-Module -Name TpmProgress -All | Remove-Module -Force
    Import-Module (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Force -ErrorAction Stop
}
AfterAll { Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue }

Describe 'FIX40 progress region survives console resizes' {
    BeforeEach {
        InModuleScope TpmProgress {
            $script:surface = @{
                Width = 121; Height = 100; Left = 0; Top = 0; Rows = @{}; Used = @{}; Wrapped = @{}
                Now = [datetime]'2026-01-01T00:00:00'; Visible = $true
                Writes = (New-Object System.Collections.Generic.List[string])
                WidthQueryFails = $false; HeightQueryFails = $false
                CursorReadsUntilResize = 0; ResizeTo = 0
            }
            function script:Write-Fix40Cells {
                param([string]$Text)
                foreach ($ch in $Text.ToCharArray()) {
                    if ($ch -eq "`r") { $script:surface.Left = 0; continue }
                    if ($ch -eq "`n") {
                        # A hard line break: the row it lands on starts a new logical line, never a wrapped continuation of
                        # the row above, whatever an earlier (since erased or overwritten) text left in the wrap flag.
                        $script:surface.Top++
                        [void]$script:surface.Wrapped.Remove($script:surface.Top)
                        continue
                    }
                    $row = $script:surface.Top
                    if (-not $script:surface.Rows.ContainsKey($row)) {
                        $script:surface.Rows[$row] = ' ' * $script:surface.Width
                    }
                    $cells = $script:surface.Rows[$row].ToCharArray()
                    $cells[$script:surface.Left] = $ch
                    $script:surface.Rows[$row] = -join $cells
                    $script:surface.Left++
                    $script:surface.Used[$row] = [Math]::Max([int]$script:surface.Used[$row], $script:surface.Left)
                    if ($script:surface.Left -eq $script:surface.Width) {
                        $script:surface.Left = 0; $script:surface.Top++
                        $script:surface.Wrapped[$script:surface.Top] = $true
                    }
                }
            }
            function script:Resize-Fix40Surface {
                param([int]$Width)
                $lines = New-Object System.Collections.Generic.List[string]
                $line = ''
                for ($row = 0; $row -le $script:surface.Top; $row++) {
                    if ($row -gt 0 -and -not $script:surface.Wrapped.ContainsKey($row)) {
                        [void]$lines.Add($line.TrimEnd()); $line = ''
                    }
                    if ($script:surface.Rows.ContainsKey($row)) {
                        $length = if ($row -eq $script:surface.Top) { $script:surface.Left } else { [int]$script:surface.Used[$row] }
                        $line += $script:surface.Rows[$row].Substring(0, $length)
                    }
                }
                [void]$lines.Add($line)
                $script:surface.Width = $Width; $script:surface.Left = 0; $script:surface.Top = 0
                $script:surface.Rows = @{}; $script:surface.Used = @{}; $script:surface.Wrapped = @{}
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    if ($i -gt 0) {
                        if ($script:surface.Left -eq 0 -and $script:surface.Wrapped.ContainsKey($script:surface.Top)) {
                            [void]$script:surface.Wrapped.Remove($script:surface.Top)
                        } else { Write-Fix40Cells "`r`n" }
                    }
                    Write-Fix40Cells $lines[$i]
                }
            }
            function script:Get-Fix40Rows {
                foreach ($key in @($script:surface.Rows.Keys | Sort-Object)) {
                    if ($script:surface.Rows[$key].Trim().Length -gt 0) {
                        [pscustomobject]@{ Top = $key; Text = $script:surface.Rows[$key].TrimEnd() }
                    }
                }
            }
            function script:Step-Fix40Clock {
                param([int]$Milliseconds = 100)
                $script:surface.Now = $script:surface.Now.AddMilliseconds($Milliseconds)
                $live = $script:TpmProgressOp.Live
                [System.Threading.Monitor]::Enter($live.Gate)
                try { Invoke-TpmProgressRefreshStep -Live $live }
                finally { [System.Threading.Monitor]::Exit($live.Gate) }
            }
            Mock Start-TpmProgressRefresh {}
            Mock Get-TpmProgressNow { $script:surface.Now }
            Mock Get-TpmProgressTimestamp { ($script:surface.Now.Ticks - ([datetime]'2026-01-01T00:00:00').Ticks) / 10000.0 }
            Mock Test-TpmProgressOutputRedirected { $false }
            Mock Get-TpmProgressWidth {
                param($Requested)
                if ($Requested -gt 0) { return [Math]::Min($Requested, $script:surface.Width - 1) }
                return ($script:surface.Width - 1)
            }
            Mock Get-TpmProgressBufferWidth { if ($script:surface.WidthQueryFails) { 0 } else { $script:surface.Width } }
            Mock Get-TpmProgressWindowHeight { if ($script:surface.HeightQueryFails) { 0 } else { $script:surface.Height } }
            Mock Get-TpmProgressCursor {
                $position = [pscustomobject]@{ Left = $script:surface.Left; Top = $script:surface.Top }
                if ($script:surface.CursorReadsUntilResize -gt 0) {
                    $script:surface.CursorReadsUntilResize--
                    # The window is resized right after this read returned: the position handed back is the old one.
                    if ($script:surface.CursorReadsUntilResize -eq 0) { Resize-Fix40Surface $script:surface.ResizeTo }
                }
                return $position
            }
            Mock Set-TpmProgressCursor {
                param($Left, $Top)
                $script:surface.Left = $Left; $script:surface.Top = $Top; return $true
            }
            Mock Clear-TpmProgressCells {
                param($Top, $Count)
                for ($i = 0; $i -lt $Count; $i++) {
                    $row = $Top + [int][Math]::Floor($i / [double]$script:surface.Width)
                    $col = $i % $script:surface.Width
                    if ($script:surface.Rows.ContainsKey($row)) {
                        $cells = $script:surface.Rows[$row].ToCharArray(); $cells[$col] = ' '
                        $script:surface.Rows[$row] = -join $cells
                    }
                }
                return $true
            }
            Mock Get-TpmProgressCursorVisible { $script:surface.Visible }
            Mock Set-TpmProgressCursorVisible { param($Visible) $script:surface.Visible = $Visible }
            Mock Get-TpmProgressStyle { 'Ascii' }
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
                [void]$script:surface.Writes.Add($value)
                Write-Fix40Cells $value
            }
            Mock Write-TpmProgressPlainLine {}
        }
    }
    AfterEach {
        InModuleScope TpmProgress {
            if (Test-TpmProgressActive) { Stop-TpmProgressAbandoned }
        }
    }

    It 'redraws one region after the window gets wider' {
        InModuleScope TpmProgress {
            $null = Start-TpmProgressOperation -Title 'Scanning' -Stage 'Support profile scan' -Total 62
            @(Get-Fix40Rows).Count | Should -Be 1
            Resize-Fix40Surface 200
            Step-Fix40Clock
            $rows = @(Get-Fix40Rows)
            $rows.Count | Should -Be 1
            $rows[0].Top | Should -Be 0
            $rows[0].Text | Should -Match 'Scanning'
            $rows[0].Text.Length | Should -BeLessOrEqual 199
            $script:TpmProgressOp.Live.Frame.Resizes | Should -Be 1
        }
    }

    It 'erases the rows that wrapped when the window got narrower and redraws one region' {
        InModuleScope TpmProgress {
            $null = Start-TpmProgressOperation -Title 'Scanning' -Stage 'Support profile scan' -Total 62
            # 120 cells at 60 columns: the old frame now occupies two buffer rows plus the exact-wrap cursor row.
            Resize-Fix40Surface 60
            @(Get-Fix40Rows).Count | Should -Be 2
            Step-Fix40Clock
            $rows = @(Get-Fix40Rows)
            $rows.Count | Should -Be 1
            $rows[0].Top | Should -Be 0
            $rows[0].Text.Length | Should -BeLessOrEqual 59
            $script:surface.Top | Should -Be 0
        }
    }

    It 'handles a much narrower window with one clipped row and nothing left behind' {
        InModuleScope TpmProgress {
            $null = Start-TpmProgressOperation -Title 'Scanning' -Stage 'Support profile scan' -Total 62
            Resize-Fix40Surface 20
            Step-Fix40Clock
            $rows = @(Get-Fix40Rows)
            $rows.Count | Should -Be 1
            $rows[0].Top | Should -Be 0
            $rows[0].Text.Length | Should -BeLessOrEqual 19
            foreach ($width in @(121, 20, 121)) {
                Resize-Fix40Surface $width
                Step-Fix40Clock
                @(Get-Fix40Rows).Count | Should -Be 1
                @(Get-Fix40Rows)[0].Top | Should -Be 0
            }
        }
    }

    It 'keeps exactly one region through rapid repeated size changes, one frame per change' {
        InModuleScope TpmProgress {
            $null = Start-TpmProgressOperation -Title 'Scanning' -Stage 'Support profile scan' -Total 62
            $widths = @(100, 80, 60, 45, 30, 60, 90, 121, 70, 200)
            foreach ($width in $widths) {
                Resize-Fix40Surface $width
                Step-Fix40Clock
                $rows = @(Get-Fix40Rows)
                $rows.Count | Should -Be 1
                $rows[0].Top | Should -Be 0
                $rows[0].Text.Length | Should -BeLessOrEqual ($width - 1)
            }
            $script:TpmProgressOp.Live.Frame.Resizes | Should -Be $widths.Count
        }
    }

    It 'recovers when the window changes twice before the next frame' {
        InModuleScope TpmProgress {
            $null = Start-TpmProgressOperation -Title 'Scanning' -Stage 'Support profile scan' -Total 62
            Resize-Fix40Surface 60
            Resize-Fix40Surface 90
            Step-Fix40Clock
            $rows = @(Get-Fix40Rows)
            $rows.Count | Should -Be 1
            $rows[0].Top | Should -Be 0
            $rows[0].Text.Length | Should -BeLessOrEqual 89
        }
    }

    It 'keeps every row of a multi-row region on its own row after a resize' {
        InModuleScope TpmProgress {
            $null = Start-TpmProgressOperation -Title 'Owner' -Stage '' -Total 10 -Columns Description,Bar,Percentage,Count,Elapsed,Spinner
            $null = Add-TpmProgressTask -Description 'Child task' -Total 20
            @(Get-Fix40Rows).Count | Should -Be 2
            foreach ($width in @(60, 45, 121)) {
                Resize-Fix40Surface $width
                Step-Fix40Clock
                $rows = @(Get-Fix40Rows)
                $rows.Count | Should -Be 2
                $rows[0].Top | Should -Be 0
                $rows[1].Top | Should -Be 1
                $rows[0].Text | Should -Match 'Owner'
                $rows[1].Text | Should -Match 'Child'
            }
        }
    }

    It 'still finds the region when the host leaves the cursor in a column the reflow model did not predict' {
        InModuleScope TpmProgress {
            $null = Start-TpmProgressOperation -Title 'Scanning' -Stage 'Support profile scan' -Total 62
            Resize-Fix40Surface 60
            $script:surface.Left = 7
            Step-Fix40Clock
            $rows = @(Get-Fix40Rows)
            $rows.Count | Should -Be 1
            $rows[0].Top | Should -Be 0
        }
    }

    It 'does not erase text written after the region when the window also changes size' {
        InModuleScope TpmProgress {
            $null = Start-TpmProgressOperation -Title 'Scanning' -Stage 'Support profile scan' -Total 62
            # Foreign output (no Suspend call) lands on the row below the region, then the window narrows to 50 columns.
            # The cursor ends in a column and on a row the reflow of the region alone does not explain.
            Write-Fix40Cells "`r`nQuestion?"
            Resize-Fix40Surface 50
            $script:surface.Top | Should -Be 3
            Step-Fix40Clock
            Should -Invoke Clear-TpmProgressCells -Times 0 -Exactly
            $question = @(Get-Fix40Rows | Where-Object { $_.Text -eq 'Question?' })
            $question.Count | Should -Be 1
            $question[0].Top | Should -Be 3
        }
    }

    It 'records the geometry the cursor was read at when the window changes between the reads' {
        InModuleScope TpmProgress {
            $null = Start-TpmProgressOperation -Title 'Scanning' -Stage 'Support profile scan' -Total 62
            # Reads of the cursor in the next frame: the placement read, then the one that follows the write. The window
            # narrows right after the second one returned.
            $script:surface.ResizeTo = 60
            $script:surface.CursorReadsUntilResize = 2
            Step-Fix40Clock
            $script:surface.CursorReadsUntilResize | Should -Be 0
            $script:surface.Width | Should -Be 60
            Step-Fix40Clock
            $rows = @(Get-Fix40Rows)
            $rows.Count | Should -Be 1
            $rows[0].Top | Should -Be 0
        }
    }

    It 'never throws and keeps drawing at the previous size while the size queries fail' {
        InModuleScope TpmProgress {
            $null = Start-TpmProgressOperation -Title 'Scanning' -Stage 'Support profile scan' -Total 62
            $script:surface.WidthQueryFails = $true
            $script:surface.HeightQueryFails = $true
            { Step-Fix40Clock } | Should -Not -Throw
            { Step-Fix40Clock } | Should -Not -Throw
            $script:surface.WidthQueryFails = $false
            $script:surface.HeightQueryFails = $false
            Step-Fix40Clock
            $rows = @(Get-Fix40Rows)
            $rows.Count | Should -Be 1
            $rows[0].Top | Should -Be 0
            $script:TpmProgressOp.Live.Frame.Resizes | Should -Be 0
        }
    }

    It 'draws a window height change in place: one region, the old rows are overwritten and nothing is erased first' {
        InModuleScope TpmProgress {
            $null = Start-TpmProgressOperation -Title 'Scanning' -Stage 'Support profile scan' -Total 62
            $script:surface.Height = 60
            $writesBefore = $script:surface.Writes.Count
            Step-Fix40Clock
            $script:TpmProgressOp.Live.Frame.Resizes | Should -Be 1
            $script:TpmProgressOp.Live.Frame.FrameWindowHeight | Should -Be 60
            $script:surface.Writes.Count | Should -Be ($writesBefore + 1)
            $rows = @(Get-Fix40Rows)
            $rows.Count | Should -Be 1
            $rows[0].Top | Should -Be 0
            $rows[0].Text | Should -Match 'Scanning'
            Should -Invoke Clear-TpmProgressCells -Times 0 -Exactly
        }
    }
}
