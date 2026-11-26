#Requires -Module Pester
# Fake-only consumer regressions. No product entry point, console, scheduler or network is used.
BeforeAll {
    Get-Module -Name TpmProgress -All | Remove-Module -Force
    Import-Module (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Force -ErrorAction Stop
}
AfterAll { Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue }

Describe 'FIX16B recorded live progress surface' {
    BeforeEach {
        InModuleScope TpmProgress {
            $script:surface = @{
                Width = 121; Left = 0; Top = 0; Rows = @{}; Used = @{}; Wrapped = @{}
                Now = [datetime]'2026-01-01T00:00:00'; Visible = $true; Redirected = $false
                Writes = (New-Object System.Collections.Generic.List[string])
                Plain = (New-Object System.Collections.Generic.List[string])
                Visibility = (New-Object System.Collections.Generic.List[bool]); FailWrite = $false
            }
            # Character-cell surface with immediate exact-width wrap, including CursorLeft=0.
            function script:Write-Fix16BCells {
                param([string]$Text)
                foreach ($ch in $Text.ToCharArray()) {
                    if ($ch -eq "`r") { $script:surface.Left = 0; continue }
                    if ($ch -eq "`n") { $script:surface.Top++; continue }
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
            function script:Resize-Fix16BSurface {
                param([int]$Width)
                # Reflow observed written cells, not renderer metadata. Wrapped continuation rows belong
                # to the previous logical line even when the last continuation contains zero cells.
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
                            # A hard newline after an exact-width non-cursor row consumes that row only once.
                            [void]$script:surface.Wrapped.Remove($script:surface.Top)
                        } else { Write-Fix16BCells "`r`n" }
                    }
                    Write-Fix16BCells $lines[$i]
                }
            }
            function script:Get-Fix16BVisibleRows {
                foreach ($key in @($script:surface.Rows.Keys | Sort-Object)) {
                    if ($script:surface.Rows[$key].Trim().Length -gt 0) {
                        [pscustomobject]@{ Top = $key; Text = $script:surface.Rows[$key].TrimEnd() }
                    }
                }
            }
            function script:Step-Fix16BClock {
                param([int]$Milliseconds = 100)
                $script:surface.Now = $script:surface.Now.AddMilliseconds($Milliseconds)
                $live = $script:TpmProgressOp.Live
                [System.Threading.Monitor]::Enter($live.Gate)
                try { Invoke-TpmProgressRefreshStep -Live $live }
                finally { [System.Threading.Monitor]::Exit($live.Gate) }
            }
            function script:Step-Fix22Background {
                # One tick of the refresh runspace: the same call it makes, including the owner check.
                param([int]$Milliseconds = 100)
                $script:surface.Now = $script:surface.Now.AddMilliseconds($Milliseconds)
                $live = $script:TpmProgressOp.Live
                [System.Threading.Monitor]::Enter($live.Gate)
                try { Invoke-TpmProgressRefreshStep -Live $live -CheckOwner }
                finally { [System.Threading.Monitor]::Exit($live.Gate) }
            }
            function script:New-Fix22Owner {
                # A console host's default runspace while its script runs: Opened AND Available (observed on the test PC).
                param([string]$State = 'Opened')
                return [pscustomobject]@{
                    RunspaceAvailability = 'Available'
                    RunspaceStateInfo = [pscustomobject]@{ State = $State }
                }
            }
            Mock Start-TpmProgressRefresh {}
            Mock Get-TpmProgressNow { $script:surface.Now }
            # Frame cost uses the monotonic clock; on the recording surface it follows the virtual clock. Ticks are taken
            # relative to the surface's start in integer arithmetic first: a 2026 tick count (about 6.4E+17) is not exact
            # as a double, and the rounding showed up as frame costs such as 300.0078125 ms for a 300 ms write.
            Mock Get-TpmProgressTimestamp { ($script:surface.Now.Ticks - ([datetime]'2026-01-01T00:00:00').Ticks) / 10000.0 }
            Mock Test-TpmProgressOutputRedirected { $script:surface.Redirected }
            Mock Get-TpmProgressWidth {
                param($Requested)
                if ($Requested -gt 0) { return [Math]::Min($Requested, $script:surface.Width - 1) }
                return ($script:surface.Width - 1)
            }
            Mock Get-TpmProgressBufferWidth { $script:surface.Width }
            Mock Get-TpmProgressWindowHeight { 100 }
            Mock Get-TpmProgressCursor { [pscustomobject]@{ Left = $script:surface.Left; Top = $script:surface.Top } }
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
            Mock Set-TpmProgressCursorVisible {
                param($Visible)
                $script:surface.Visible = $Visible; [void]$script:surface.Visibility.Add($Visible)
            }
            Mock Get-TpmProgressStyle { 'Ascii' }
            Mock Get-TpmProgressBackground { $null }
            Mock Test-TpmProgressColorEnabled { $false }
            Mock Test-TpmProgressWideWriteAvailable { $false }
            Mock Test-TpmProgressConhostFont { $false }
            Mock Test-TpmProgressGlyphCells { $false }
            Mock Get-TpmProgressOutputCodePage { 437 }
            Mock Write-TpmProgressRaw {
                param($Text, $NewLine)
                if ($script:surface.FailWrite) { throw 'recording surface output failure' }
                $value = [string]$Text
                if ($NewLine) { $value += "`r`n" }
                [void]$script:surface.Writes.Add($value)
                Write-Fix16BCells $value
            }
            Mock Write-TpmProgressPlainLine { param($Text) [void]$script:surface.Plain.Add([string]$Text) }
        }
    }
    AfterEach {
        InModuleScope TpmProgress {
            $script:surface.FailWrite = $false
            if (Test-TpmProgressActive) { Stop-TpmProgressAbandoned }
        }
    }

    It 'reflows wide to exact-wrap narrow to wide without stacking or blank separator rows' {
        InModuleScope TpmProgress {
            $null = Start-TpmProgressOperation -Title 'Scanning' -Stage ('Profile-' + ('x' * 220)) -Total 62
            @(Get-Fix16BVisibleRows).Count | Should -Be 1
            Resize-Fix16BSurface 60
            $script:surface.Left | Should -Be 0
            $script:surface.Top | Should -Be 2
            Step-Fix16BClock
            $rows = @(Get-Fix16BVisibleRows)
            $rows.Count | Should -Be 1
            $rows[0].Top | Should -Be 0
            $rows[0].Text.Length | Should -BeLessOrEqual 59
            $rows[0].Text | Should -Match '\.\.\.'
            Resize-Fix16BSurface 213
            Step-Fix16BClock
            $rows = @(Get-Fix16BVisibleRows)
            $rows.Count | Should -Be 1
            $rows[0].Top | Should -Be 0
            $rows[0].Text.Length | Should -BeLessOrEqual 212
            $rows[0].Text.IndexOf('|') | Should -BeGreaterThan 48
            ($script:surface.Writes -join '') | Should -Not -Match "`n"
            # The next progress operation (the original reported failure) also starts on one clean row.
            Complete-TpmProgressOperation -State Error
            $null = Start-TpmProgressOperation -Title 'Second scan' -Stage 'Profiles' -Total 62
            Step-Fix16BClock
            $rows = @(Get-Fix16BVisibleRows)
            $rows.Count | Should -Be 2
            $rows[0].Top | Should -Be 0
            $rows[1].Top | Should -Be 1
            Suspend-TpmProgressLine
            Write-Fix16BCells "Question?`r`n"
            Resume-TpmProgressLine
            # The second scan is now below a real prompt. Its 212 cells wrap exactly at 106.
            Resize-Fix16BSurface 106
            $script:surface.Left | Should -Be 0
            Step-Fix16BClock
            $second = @(Get-Fix16BVisibleRows | Where-Object { $_.Text -match '^\s*Second scan' })
            $second.Count | Should -Be 1
            $second[0].Text.Length | Should -BeLessOrEqual 105
            $narrowTop = $second[0].Top
            Step-Fix16BClock
            @(Get-Fix16BVisibleRows | Where-Object { $_.Text -match '^\s*Second scan' })[0].Top | Should -Be $narrowTop
            Resize-Fix16BSurface 213
            Step-Fix16BClock
            $second = @(Get-Fix16BVisibleRows | Where-Object { $_.Text -match '^\s*Second scan' })
            $second.Count | Should -Be 1
            $second[0].Text.Length | Should -BeLessOrEqual 212
            @(Get-Fix16BVisibleRows | Where-Object { $_.Text -match '^Question\?' }).Count | Should -Be 1
            $wideTop = $second[0].Top
            Step-Fix16BClock
            @(Get-Fix16BVisibleRows | Where-Object { $_.Text -match '^\s*Second scan' })[0].Top | Should -Be $wideTop
        }
    }

    It 'uses the current width and restores description text beyond the old 48-character cap at 213' {
        InModuleScope TpmProgress {
            $description = 'Scanning-' + ('q' * 65) + '-END-OF-DESCRIPTION'
            Resize-Fix16BSurface 213
            $null = Start-TpmProgressOperation -Title $description -Stage '' -Total 10
            @(Get-Fix16BVisibleRows)[0].Text | Should -Match ([regex]::Escape($description))
            Resize-Fix16BSurface 40
            Step-Fix16BClock
            $narrow = @(Get-Fix16BVisibleRows)
            $narrow.Count | Should -Be 1
            $narrow[0].Text.Length | Should -BeLessOrEqual 39
            $narrow[0].Text | Should -Match '\.\.\.'
            $narrow[0].Text | Should -Not -Match 'END-OF-DESCRIPTION'
            Resize-Fix16BSurface 213
            Step-Fix16BClock
            @(Get-Fix16BVisibleRows)[0].Text | Should -Match ([regex]::Escape($description))
        }
    }

    It 'animates an indeterminate bar every 100ms without consumer updates and never invents a percentage' {
        InModuleScope TpmProgress {
            $null = Start-TpmProgressOperation -Title 'Discovering' -Stage '' -Total 0
            $first = @(Get-Fix16BVisibleRows)[0].Text
            $first | Should -Match '\|[^|]*\|'
            $first | Should -Not -Match '%'
            $writes = $script:surface.Writes.Count
            Step-Fix16BClock 99
            $script:surface.Writes.Count | Should -Be $writes
            Step-Fix16BClock 1
            $second = @(Get-Fix16BVisibleRows)[0].Text
            $second | Should -Not -Be $first
            $second | Should -Not -Match '%'
            # Bar itself, not just the spinner, has to move while the caller is idle.
            [regex]::Match($second, '\|[^|]*\|').Value | Should -Not -Be ([regex]::Match($first, '\|[^|]*\|').Value)
            Step-Fix16BClock 100
            @(Get-Fix16BVisibleRows).Count | Should -Be 1
            (Get-TpmProgressState).Current | Should -Be 0
        }
    }

    It 'adds independent running rows with aligned bars percentages counts and elapsed columns' {
        InModuleScope TpmProgress {
            $null = Start-TpmProgressOperation -Title 'Owner' -Stage '' -Total 10 -Columns Description,Bar,Percentage,Count,Elapsed,Spinner
            $id = Add-TpmProgressTask -Description 'Longer child description' -Total 1000
            Set-TpmProgressTask -Id $id -Current 250
            $rows = @(Get-Fix16BVisibleRows)
            $rows.Count | Should -Be 2
            $rows[0].Top | Should -Be 0
            $rows[1].Top | Should -Be 1
            $rows[1].Text | Should -Match 'Longer child description'
            $rows[1].Text | Should -Match '25%'
            $rows[1].Text | Should -Match '250/1000'
            $rows[0].Text.IndexOf('|') | Should -Be $rows[1].Text.IndexOf('|')
            $rows[0].Text.IndexOf('%') | Should -Be $rows[1].Text.IndexOf('%')
            $rows[0].Text.IndexOf('in 0.0s') | Should -Be $rows[1].Text.IndexOf('in 0.0s')
            Set-TpmProgressTask -Id $id -Current 1000 -State Final
            $rows = @(Get-Fix16BVisibleRows)
            $rows.Count | Should -Be 2
            $rows[1].Text | Should -Match '100%'
        }
    }

    It 'aligns mixed Items and Bytes rows using one shared count column width' {
        InModuleScope TpmProgress {
            Resize-Fix16BSurface 213
            $null = Start-TpmProgressOperation -Title 'Items owner' -Stage '' -Total 10 -Columns Description,Bar,Percentage,Count,Elapsed,Spinner
            $id = Add-TpmProgressTask -Description 'Bytes child' -Total 20971520 -Unit Bytes
            Set-TpmProgressTask -Id $id -Current 10485760
            $rows = @(Get-Fix16BVisibleRows)
            $rows.Count | Should -Be 2
            $rows[0].Text | Should -Match '0/10'
            $rows[1].Text | Should -Match '10\.0/20\.0 MB'
            $rows[0].Text.IndexOf('|') | Should -Be $rows[1].Text.IndexOf('|')
            $rows[0].Text.IndexOf('%') | Should -Be $rows[1].Text.IndexOf('%')
            $rows[0].Text.IndexOf('in 0.0s') | Should -Be $rows[1].Text.IndexOf('in 0.0s')
            # Right-aligned count cells end at the same offset despite their different unit formats.
            $itemCount = [regex]::Match($rows[0].Text, '0/10')
            $byteCount = [regex]::Match($rows[1].Text, '10\.0/20\.0 MB')
            ($itemCount.Index + $itemCount.Length) | Should -Be ($byteCount.Index + $byteCount.Length)
        }
    }

    It 'aligns mixed hour and minute elapsed values without shifting following columns' {
        InModuleScope TpmProgress {
            Resize-Fix16BSurface 213
            $null = Start-TpmProgressOperation -Title 'Long clock' -Stage '' -Total 10 -StallSeconds 10000 -Columns Description,Elapsed,Bar,Percentage,Spinner
            Step-Fix16BClock 3600000
            $id = Add-TpmProgressTask -Description 'Short clock' -Total 10
            Step-Fix16BClock 1000
            $rows = @(Get-Fix16BVisibleRows)
            $rows.Count | Should -Be 2
            # FIX105: nothing finished yet, so no rate is shown (it used to print a made-up "(0.00/s)").
            $longTime = [regex]::Match($rows[0].Text, 'in 3601\.0s')
            $shortTime = [regex]::Match($rows[1].Text, 'in 1\.0s')
            $longTime.Success | Should -BeTrue
            $shortTime.Success | Should -BeTrue
            ($longTime.Index + $longTime.Length) | Should -Be ($shortTime.Index + $shortTime.Length)
            $rows[0].Text.IndexOf('|') | Should -Be $rows[1].Text.IndexOf('|')
            $rows[0].Text.IndexOf('%') | Should -Be $rows[1].Text.IndexOf('%')
            $rows[0].Text.Length | Should -Be $rows[1].Text.Length
        }
    }

    It 'keeps known and unknown totals on the same narrow shared grid' {
        InModuleScope TpmProgress {
            Resize-Fix16BSurface 49
            $null = Start-TpmProgressOperation -Title 'Known' -Stage '' -Total 10 -Columns Description,Bar,Percentage,Count,Elapsed,Spinner
            $id = Add-TpmProgressTask -Description 'Unknown' -Total 0
            $rows = @(Get-Fix16BVisibleRows)
            $rows.Count | Should -Be 2
            $rows[0].Text | Should -Match '0%'
            $rows[1].Text | Should -Not -Match '%'
            $rows[0].Text.IndexOf('|') | Should -BeGreaterThan -1
            $rows[0].Text.IndexOf('|') | Should -Be $rows[1].Text.IndexOf('|')
            # Both rows retain the same bar width; the unknown row has no percentage.
            $rows[0].Text.LastIndexOf('|') | Should -Be $rows[1].Text.LastIndexOf('|')
            $rows[0].Text.Length | Should -Be $rows[1].Text.Length
            $rows[0].Text.Length | Should -BeLessOrEqual 48
            $knownCount = [regex]::Match($rows[0].Text, '0/10')
            $knownCount.Success | Should -BeTrue
            $countEnd = $knownCount.Index + $knownCount.Length
            $rows[1].Text.Substring($countEnd - 1, 1) | Should -Be '0'
            Step-Fix16BClock
            @(Get-Fix16BVisibleRows).Count | Should -Be 2
        }
    }

    It 'removes completed rows when requested and auto-clears all remaining cells on close' {
        InModuleScope TpmProgress {
            $null = Start-TpmProgressOperation -Title 'Owner' -Stage '' -Group -HideCompleted -AutoClear
            $first = Add-TpmProgressTask -Description 'Finished child' -Total 1
            $second = Add-TpmProgressTask -Description 'Still running' -Total 1
            Set-TpmProgressTask -Id $first -Current 1 -State Final
            $rows = @(Get-Fix16BVisibleRows)
            $rows.Count | Should -Be 2
            $rows[1].Top | Should -Be 1
            ($rows.Text -join '') | Should -Not -Match 'Finished child'
            $rows[1].Text | Should -Match 'Still running'
            Set-TpmProgressTask -Id $second -Current 1 -State Final
            @(Get-Fix16BVisibleRows).Count | Should -Be 1
            Complete-TpmProgressOperation
            @(Get-Fix16BVisibleRows).Count | Should -Be 0
            $script:surface.Top | Should -Be 0
            $script:surface.Left | Should -Be 0
            $script:surface.Visible | Should -BeTrue
        }
    }

    It 'emits only printable ASCII plain lines under redirection with no cursor traffic' {
        InModuleScope TpmProgress {
            $script:surface.Redirected = $true
            $title = 'Caf' + [char]0xE9 + [char]27 + "[31m`r`n" + [char]9 + ' scan'
            $null = Start-TpmProgressOperation -Title $title -Stage '' -Total 10
            $id = Add-TpmProgressTask -Description 'Child' -Total 1
            Set-TpmProgressTask -Id $id -Current 1 -State Final
            Set-TpmProgressStage -Stage 'Finishing' -Current 10 -Total 10
            Complete-TpmProgressOperation
            $script:surface.Plain.Count | Should -BeGreaterThan 1
            foreach ($line in $script:surface.Plain) {
                $line | Should -Not -BeNullOrEmpty
                $line | Should -Not -Match '[^\x20-\x7E]'
            }
            $script:surface.Writes.Count | Should -Be 0
            $script:surface.Visibility.Count | Should -Be 0
        }
    }

    It 'blocks refresh through nested prompts and excludes the entire pause from group and task elapsed' {
        InModuleScope TpmProgress {
            $null = Start-TpmProgressOperation -Title 'Workflow' -Stage '' -Group -Columns Description,Elapsed
            Step-Fix16BClock 2000
            $id = Add-TpmProgressTask -Description 'Child clock' -Total 1
            Step-Fix16BClock 3000
            Suspend-TpmProgressLine
            Suspend-TpmProgressLine
            # Simulated prompt output is foreign text and must survive every attempted refresh.
            Write-Fix16BCells "Question?`r`n"
            $writes = $script:surface.Writes.Count
            Step-Fix16BClock 30000
            $script:surface.Writes.Count | Should -Be $writes
            Resume-TpmProgressLine
            Step-Fix16BClock 30000
            $script:surface.Writes.Count | Should -Be $writes
            @(Get-Fix16BVisibleRows).Count | Should -Be 1
            Resume-TpmProgressLine
            Step-Fix16BClock 2000
            $rows = @(Get-Fix16BVisibleRows)
            $rows.Count | Should -Be 3
            $rows[0].Text | Should -Be 'Question?'
            $rows[1].Text | Should -Match 'Workflow.*in 7\.0s'
            $rows[2].Text | Should -Match 'Child clock.*in 5\.0s'
            Set-TpmProgressTask -Id $id -Current 1 -State Final
            Complete-TpmProgressOperation
            $rows = @(Get-Fix16BVisibleRows)
            # Terminal group elapsed uses Started, not just the active stage clock.
            $rows[1].Text | Should -Match 'Workflow.*in 7\.0s'
            $rows[2].Text | Should -Match 'Child clock.*in 5\.0s'
            $script:surface.Visible | Should -BeTrue
        }
    }

    It 'restores cursor visibility and keeps the work going when a counted update output throws' {
        # FIX110A S-2: a drawing failure no longer reaches the caller; the renderer is switched off and the operation closes normally.
        InModuleScope TpmProgress {
            $null = Start-TpmProgressOperation -Title 'Fails on update' -Stage 'Counting' -Total 10
            $script:surface.FailWrite = $true
            $script:surface.Now = $script:surface.Now.AddMilliseconds(100)
            { Set-TpmProgressStage -Stage 'Counting' -Current 1 -Total 10 } | Should -Not -Throw
            $script:surface.Visible | Should -BeTrue
            { Complete-TpmProgressOperation -State Final } | Should -Not -Throw
            Test-TpmProgressActive | Should -BeFalse
        }
    }

    It 'lifts the bar already on screen when a drawing failure switches the renderer off, so the next line starts on its own row' {
        # Mutation: drop the frame lift from Disable-TpmProgressRenderer -> the stale bar stays and the next line is glued to its row.
        InModuleScope TpmProgress {
            $null = Start-TpmProgressOperation -Title 'Copy' -Stage 'Files' -Total 10
            @(Get-Fix16BVisibleRows).Count | Should -Be 1
            $script:surface.FailWrite = $true
            $script:surface.Now = $script:surface.Now.AddMilliseconds(500)
            Set-TpmProgressStage -Stage 'Files' -Current 3 -Total 10
            $script:surface.FailWrite = $false
            $null = Suspend-TpmProgressOutput
            Write-Fix16BCells "Next line`r`n"
            Resume-TpmProgressOutput
            $rows = @(Get-Fix16BVisibleRows)
            $rows.Count | Should -Be 1
            $rows[0].Text | Should -BeExactly 'Next line'
            Complete-TpmProgressOperation -State Final
        }
    }

    It 'restores the original cursor visibility and does not throw when initial output throws' {
        InModuleScope TpmProgress {
            $script:surface.FailWrite = $true
            { Start-TpmProgressOperation -Title 'Fails at start' } | Should -Not -Throw
            $script:surface.Visible | Should -BeTrue
            { Stop-TpmProgressAbandoned } | Should -Not -Throw
            Test-TpmProgressActive | Should -BeFalse
        }
    }

    It 'restores an originally hidden cursor and releases ownership without throwing when closing output throws' {
        InModuleScope TpmProgress {
            $script:surface.Visible = $false
            $null = Start-TpmProgressOperation -Title 'Fails on close'
            $script:surface.FailWrite = $true
            { Complete-TpmProgressOperation -State Error } | Should -Not -Throw
            $script:surface.Visible | Should -BeFalse
            Test-TpmProgressActive | Should -BeFalse
        }
    }

    It 'preserves foreign text above multiple exact-width reflowed task rows' {
        InModuleScope TpmProgress {
            Write-Fix16BCells "Do not erase`r`n"
            Resize-Fix16BSurface 120
            $null = Start-TpmProgressOperation -Title ('A' * 119) -Stage '' -Columns Description
            $id = Add-TpmProgressTask -Description ('B' * 119)
            Resize-Fix16BSurface 119
            $script:surface.Left | Should -Be 0
            Step-Fix16BClock
            $rows = @(Get-Fix16BVisibleRows)
            $rows.Count | Should -Be 3
            $rows[0].Top | Should -Be 0
            $rows[0].Text | Should -Be 'Do not erase'
            $rows[1].Top | Should -Be 1
            $rows[1].Text | Should -Match '^A+\.\.\.$'
            $rows[2].Top | Should -Be 2
            $rows[2].Text | Should -Match '^B+\.\.\.$'
            Resize-Fix16BSurface 240
            Step-Fix16BClock
            $rows = @(Get-Fix16BVisibleRows)
            $rows.Count | Should -Be 3
            $rows[0].Text | Should -Be 'Do not erase'
            $rows[1].Text | Should -Be ('A' * 119)
            $rows[2].Text | Should -Be ('B' * 119)
        }
    }

    It 'keeps the parent stall clock fresh after a nested successful close' {
        InModuleScope TpmProgress {
            $null = Start-TpmProgressOperation -Title 'Parent' -Stage '' -Group
            $null = Start-TpmProgressOperation -Title 'Leaf'
            $script:surface.Now = $script:surface.Now.AddSeconds(50)
            Complete-TpmProgressOperation
            Step-Fix16BClock 20000
            Test-TpmProgressStalled | Should -BeFalse
            $rows = @(Get-Fix16BVisibleRows)
            $rows.Count | Should -Be 1
            $rows[0].Text | Should -Not -Match 'stalled|!'
        }
    }

    It 'keeps drawing from the refresh writer while the owner runspace reports Available during its script' {
        InModuleScope TpmProgress {
            $op = Start-TpmProgressOperation -Title 'Owner busy' -Stage 'Scan' -Total 100
            $op.Live.Owner = New-Fix22Owner
            $id = Add-TpmProgressTask -Description 'Late row' -Total 100
            Set-TpmProgressTask -Id $id -Current 40
            $first = @(Get-Fix16BVisibleRows | Where-Object { $_.Text -match 'Late row' })
            $first.Count | Should -Be 1
            $first[0].Text | Should -Match 'in 0\.0s'
            $writes = $script:surface.Writes.Count
            Step-Fix22Background 2000
            $script:surface.Writes.Count | Should -BeGreaterThan $writes
            $op.Live.Abandoned | Should -BeFalse
            $op.Live.Stop | Should -BeFalse
            Test-TpmProgressActive | Should -BeTrue
            $script:surface.Visible | Should -BeFalse
            $rows = @(Get-Fix16BVisibleRows)
            $rows.Count | Should -Be 2
            $late = @($rows | Where-Object { $_.Text -match 'Late row' })
            $late.Count | Should -Be 1
            $late[0].Top | Should -Be $first[0].Top
            $late[0].Text | Should -Match 'in 2\.0s'
            $late[0].Text | Should -Match '40/100'
        }
    }

    It 'stops the refresh writer and restores the cursor when the owner runspace is no longer open' {
        InModuleScope TpmProgress {
            foreach ($ownerState in @('Closing', 'Closed', 'Broken')) {
                $op = Start-TpmProgressOperation -Title ('Owner ' + $ownerState) -Stage '' -Total 10
                $op.Live.Owner = New-Fix22Owner -State $ownerState
                $writes = $script:surface.Writes.Count
                Step-Fix22Background 500
                $script:surface.Writes.Count | Should -Be $writes
                $op.Live.Abandoned | Should -BeTrue
                $op.Live.Stop | Should -BeTrue
                $script:surface.Visible | Should -BeTrue
                Test-TpmProgressActive | Should -BeFalse
                # A later invocation may prompt or print before starting its own operation; nothing is drawn.
                Suspend-TpmProgressLine
                Resume-TpmProgressLine
                Suspend-TpmProgressOutput | Should -BeFalse
                Resume-TpmProgressOutput
                Stop-TpmProgressAbandoned
                $script:surface.Writes.Count | Should -Be $writes
                $script:surface.Visible | Should -BeTrue
            }
        }
    }

    It 'stops the refresh writer when the thread that opened the operation has ended' {
        InModuleScope TpmProgress {
            $op = Start-TpmProgressOperation -Title 'Ended thread' -Stage '' -Total 10
            $op.Live.Owner = New-Fix22Owner
            $op.Live.OwnerThread = [pscustomobject]@{ IsAlive = $false }
            $writes = $script:surface.Writes.Count
            Step-Fix22Background 500
            $script:surface.Writes.Count | Should -Be $writes
            $op.Live.Abandoned | Should -BeTrue
            $script:surface.Visible | Should -BeTrue
            Test-TpmProgressActive | Should -BeFalse
        }
    }

    It 'parks the refresh writer after foreign output such as the prompt of a returned owner' {
        InModuleScope TpmProgress {
            $op = Start-TpmProgressOperation -Title 'Unclosed scan' -Stage '' -Total 10
            $op.Live.Owner = New-Fix22Owner
            # The shell writes its prompt below the open display (no Suspend-TpmProgressOutput).
            Write-Fix16BCells ("`r`n" + 'PS C:\> ')
            $writes = $script:surface.Writes.Count
            Step-Fix22Background 500
            Step-Fix22Background 500
            $script:surface.Writes.Count | Should -Be $writes
            $op.Live.Parked | Should -BeTrue
            $script:surface.Visible | Should -BeTrue
            $script:surface.Left | Should -Be 8
            @(Get-Fix16BVisibleRows | Where-Object { $_.Text -match 'Unclosed scan' }).Count | Should -Be 1
            # An owner call redraws once on a fresh row below that output; the refresh writer then resumes in place.
            Set-TpmProgressStage -Stage 'Resumed' -Current 5 -Total 10
            $op.Live.Parked | Should -BeFalse
            $script:surface.Visible | Should -BeFalse
            $rows = @(Get-Fix16BVisibleRows)
            $rows[1].Text | Should -Be 'PS C:\>'
            @($rows | Where-Object { $_.Text -match 'Resumed' }).Count | Should -Be 1
            $resumedTop = @($rows | Where-Object { $_.Text -match 'Resumed' })[0].Top
            $resumedTop | Should -Be 2
            $writes = $script:surface.Writes.Count
            Step-Fix22Background 500
            $script:surface.Writes.Count | Should -BeGreaterThan $writes
            $after = @(Get-Fix16BVisibleRows | Where-Object { $_.Text -match 'Resumed' })
            $after.Count | Should -Be 1
            $after[0].Top | Should -Be $resumedTop
        }
    }

    It 'redraws rows added after the first frame in place from the refresh writer without stacking' {
        InModuleScope TpmProgress {
            $op = Start-TpmProgressOperation -Title 'Twelve tasks' -Stage 'Adding' -Total 0
            $op.Live.Owner = New-Fix22Owner
            for ($i = 1; $i -le 12; $i++) {
                $id = Add-TpmProgressTask -Description ('Task {0:00}' -f $i) -Total 100
                Set-TpmProgressTask -Id $id -Current ($i * 8)
                if ($i % 4 -eq 0) { Step-Fix22Background 150 }
            }
            for ($i = 0; $i -lt 3; $i++) { Step-Fix22Background 200 }
            $op.Live.Abandoned | Should -BeFalse
            $op.Live.Parked | Should -BeFalse
            $rows = @(Get-Fix16BVisibleRows)
            $rows.Count | Should -Be 13
            for ($i = 0; $i -lt $rows.Count; $i++) { $rows[$i].Top | Should -Be $i }
            @($rows | Where-Object { $_.Text -match 'Twelve tasks' }).Count | Should -Be 1
            for ($i = 1; $i -le 12; $i++) {
                $match = @($rows | Where-Object { $_.Text -match ('Task {0:00}\b' -f $i) })
                $match.Count | Should -Be 1
                $match[0].Text | Should -Match ('{0}/100' -f ($i * 8))
            }
        }
    }
    It 'changes a pending child to running on its existing row' {
        InModuleScope TpmProgress {
            $null = Start-TpmProgressOperation -Title 'Owner' -Stage '' -Total 10
            $id = Add-TpmProgressTask -Description 'Pending child' -Total 100 -Pending
            $before = @(Get-Fix16BVisibleRows | Where-Object { $_.Text -match 'Pending child' })
            $before.Count | Should -Be 1
            $before[0].Text | Should -Not -Match '%|ETA'
            Set-TpmProgressTask -Id $id -Current 25
            $after = @(Get-Fix16BVisibleRows | Where-Object { $_.Text -match 'Pending child' })
            $after.Count | Should -Be 1
            $after[0].Top | Should -Be $before[0].Top
            $after[0].Text | Should -Match '25/100'
            $after[0].Text | Should -Match '25%'
        }
    }

    It 'erases live rows before output and redraws them below each complete message' {
        InModuleScope TpmProgress {
            $null = Start-TpmProgressOperation -Title 'Owner' -Stage '' -Total 10
            $id = Add-TpmProgressTask -Description 'Child' -Total 10
            Set-TpmProgressTask -Id $id -Current 3
            $messages = @('host line', 'warning line', 'log line', 'error line')
            foreach ($message in $messages) {
                Suspend-TpmProgressOutput | Should -BeTrue
                Write-Fix16BCells ($message + "`r`n")
                Resume-TpmProgressOutput
                Step-Fix16BClock
            }
            $rows = @(Get-Fix16BVisibleRows)
            $rows.Count | Should -Be 6
            for ($i = 0; $i -lt 4; $i++) {
                $rows[$i].Text | Should -Be $messages[$i]
                $rows[$i].Top | Should -Be $i
            }
            $rows[4].Text | Should -Match 'Owner'
            $rows[5].Text | Should -Match 'Child'
            $rows[4].Top | Should -Be 4
            $rows[5].Top | Should -Be 5
        }
    }

    It 'keeps a no-op on the complete path rather than marking a failure' {
        InModuleScope TpmProgress {
            $null = Start-TpmProgressOperation -Title 'Owner' -Stage '' -Total 1
            $id = Add-TpmProgressTask -Description 'Already complete' -Total 10
            Set-TpmProgressTask -Id $id -Current 10 -State No-op
            $line = @(Get-Fix16BVisibleRows | Where-Object { $_.Text -match 'Already complete' })[0].Text
            $line | Should -Match '100%'
            $line | Should -Not -Match 'FAILED|\(!\)'
        }
    }

    It 'uses exponentially smoothed samples and a nonzero ETA at 90 percent' {
        InModuleScope TpmProgress {
            Resize-Fix16BSurface 213
            $op = Start-TpmProgressOperation -Title 'Rate owner' -Stage 'Processing' -Total 100
            foreach ($count in @(10, 20, 30, 90)) {
                Step-Fix16BClock 1000
                Set-TpmProgressStage -Stage 'Processing' -Current $count -Total 100
            }
            $op.SmoothedRate | Should -BeGreaterThan 10
            $op.SmoothedRate | Should -BeLessThan 60
            # The update to 90 is not drawn inline: a frame was drawn at this same instant, and a value update waits for
            # the next frame (100 ms frame interval). One refresh step later, as the writer would draw it:
            Step-Fix16BClock
            $line = @(Get-Fix16BVisibleRows)[0].Text
            $line | Should -Match '\[90%\]'
            $line | Should -Match 'ETA 0:01'
            $line | Should -Not -Match 'ETA 0:00'
            $rate = $op.SmoothedRate
            Suspend-TpmProgressLine
            Step-Fix16BClock 60000
            Resume-TpmProgressLine
            Step-Fix16BClock 1000
            Set-TpmProgressStage -Stage 'Processing' -Current 100 -Total 100
            $op.SmoothedRate | Should -BeLessThan $rate
            $op.SmoothedRate | Should -BeGreaterThan 10
        }
    }

    It 'reverses the unknown-total arrows at both ends as the virtual clock advances' {
        InModuleScope TpmProgress {
            $null = Start-TpmProgressOperation -Title 'Bounce' -Stage '' -Total 0
            $first = [regex]::Match(@(Get-Fix16BVisibleRows)[0].Text, '\|[><-]+\|').Value
            $first | Should -Match '^\|'
            $first | Should -Match '>{14}'
            $travel = $first.Length - 16
            $travel | Should -BeGreaterThan 0
            Step-Fix16BClock ($travel * 100)
            $backward = [regex]::Match(@(Get-Fix16BVisibleRows)[0].Text, '\|[><-]+\|').Value
            $backward | Should -Match '<{14}'
            Step-Fix16BClock ($travel * 100)
            $again = [regex]::Match(@(Get-Fix16BVisibleRows)[0].Text, '\|[><-]+\|').Value
            $again | Should -Be $first
        }
    }

    It 'writes colored runs through the console colors, with no escape sequences, on a surface without VT support' {
        InModuleScope TpmProgress {
            Mock Get-TpmProgressBackground { 'Black' }
            Mock Test-TpmProgressColorEnabled { $true }
            Mock Test-TpmProgressVt { $false }
            Mock Get-TpmProgressForeground { [System.ConsoleColor]::Gray }
            Mock Set-TpmProgressForeground {}
            $op = Start-TpmProgressOperation -Title 'Legacy' -Stage 'Processing' -Total 10
            Set-TpmProgressStage -Stage 'Processing' -Current 5 -Total 10
            # A value update right after the first frame is drawn by the next frame (100 ms frame interval), not inline.
            Step-Fix16BClock
            $op.ColorMode | Should -BeExactly 'Console16'
            ($script:surface.Writes -join '') | Should -Not -Match ([regex]::Escape([string][char]27))
            @(Get-Fix16BVisibleRows)[0].Text | Should -Match '5/10'
        }
    }

    It 'erases the old wider frame when only the window narrows between the initial and the pre-write measurements' {
        InModuleScope TpmProgress {
            # Buffer stays 240 columns; only the window shrinks from 121 to 80 columns right after the first width
            # measurement of a frame, i.e. after the same-shape decision but before the late geometry reread that
            # precedes the frame's single write.
            Resize-Fix16BSurface 240
            $script:surface.WindowWidth = 121
            $script:surface.ShrinkAfter = 0
            Mock Get-TpmProgressWidth {
                param($Requested)
                $measured = $script:surface.WindowWidth - 1
                if ($script:surface.ShrinkAfter -gt 0) {
                    $script:surface.ShrinkAfter--
                    if ($script:surface.ShrinkAfter -eq 0) { $script:surface.WindowWidth = 80 }
                }
                return $measured
            }
            foreach ($case in @(@{ Tasks = 0; ShrinkAfter = 1 }, @{ Tasks = 1; ShrinkAfter = 1 })) {
                $script:surface.WindowWidth = 121
                $null = Start-TpmProgressOperation -Title ('Wide-' + ('w' * 200)) -Stage '' -Total 10 -AutoClear
                if ($case.Tasks -gt 0) { $null = Add-TpmProgressTask -Description ('Child-' + ('c' * 200)) -Total 10 }
                $wide = @(Get-Fix16BVisibleRows)
                $wide.Count | Should -Be (1 + $case.Tasks)
                # Nonblank cells exist beyond column 79 before the shrink.
                @($wide | Where-Object { $_.Text.Length -gt 79 }).Count | Should -BeGreaterThan 0
                $script:surface.ShrinkAfter = $case.ShrinkAfter
                Step-Fix16BClock
                $script:surface.WindowWidth | Should -Be 80
                $narrow = @(Get-Fix16BVisibleRows)
                $narrow.Count | Should -Be (1 + $case.Tasks)
                foreach ($row in $narrow) { $row.Text.Length | Should -BeLessOrEqual 79 }
                $narrow[0].Top | Should -Be $wide[0].Top
                $narrow[0].Text | Should -Match '^Wide-'
                # A later same-shape narrow refresh stays on the same rows without stale cells.
                Step-Fix16BClock
                $again = @(Get-Fix16BVisibleRows)
                $again.Count | Should -Be (1 + $case.Tasks)
                foreach ($row in $again) { $row.Text.Length | Should -BeLessOrEqual 79 }
                # Auto-clear on close erases every owned cell, including the formerly wide extent.
                Complete-TpmProgressOperation
                @(Get-Fix16BVisibleRows).Count | Should -Be 0
            }
        }
    }

    It 'closes a never-started pending task as Skipped without blocking a successful owner close' {
        InModuleScope TpmProgress {
            # Documents the owner decision: Pending means optional work; it never turns a successful close into a failure.
            $op = Start-TpmProgressOperation -Title 'Owner' -Stage '' -Group
            $done = Add-TpmProgressTask -Description 'Done child' -Total 1
            $null = Add-TpmProgressTask -Description 'Never started' -Total 5 -Pending
            Set-TpmProgressTask -Id $done -Current 1 -State Final
            Complete-TpmProgressOperation
            $op.State | Should -Be 'Final'
            @($op.Tasks | Where-Object { $_.Title -eq 'Never started' })[0].State | Should -Be 'Skipped'
            @($op.Tasks | Where-Object { $_.Title -eq 'Done child' })[0].State | Should -Be 'Final'
        }
    }

    Context 'console VT mode ownership' {
        BeforeEach {
            InModuleScope TpmProgress {
                $script:TpmProgressVtReady = $null
                $script:TpmProgressVtOwned = $false
                $script:fakeConsole = @{ Mode = [uint32]3; Sets = (New-Object System.Collections.Generic.List[uint32]) }
                Mock Get-TpmProgressConsoleMode { [uint32]$script:fakeConsole.Mode }
                Mock Set-TpmProgressConsoleMode {
                    param($Mode)
                    [void]$script:fakeConsole.Sets.Add([uint32]$Mode); $script:fakeConsole.Mode = [uint32]$Mode; return $true
                }
            }
        }
        AfterEach {
            InModuleScope TpmProgress { $script:TpmProgressVtReady = $null; $script:TpmProgressVtOwned = $false }
        }

        It 'sets VT when it was off and restore clears only that bit, keeping a later unrelated mode change' {
            InModuleScope TpmProgress {
                Test-TpmProgressVt | Should -BeTrue
                $script:fakeConsole.Mode | Should -Be 7
                $script:fakeConsole.Sets.Count | Should -Be 1
                $script:TpmProgressVtOwned | Should -BeTrue
                # Someone else changes another mode bit after us; it must survive the restore.
                $script:fakeConsole.Mode = [uint32]15
                Restore-TpmProgressVt
                $script:fakeConsole.Mode | Should -Be 11
                $script:fakeConsole.Sets.Count | Should -Be 2
                $script:TpmProgressVtOwned | Should -BeFalse
                $script:TpmProgressVtReady | Should -BeNullOrEmpty
                # Nothing is owned any more: a second restore changes nothing.
                Restore-TpmProgressVt
                $script:fakeConsole.Sets.Count | Should -Be 2
            }
        }

        It 'never changes or restores a mode that already had VT enabled' {
            InModuleScope TpmProgress {
                $script:fakeConsole.Mode = [uint32]7
                Test-TpmProgressVt | Should -BeTrue
                $script:TpmProgressVtOwned | Should -BeFalse
                Restore-TpmProgressVt
                $script:fakeConsole.Sets.Count | Should -Be 0
                $script:fakeConsole.Mode | Should -Be 7
            }
        }

        It 'keeps ownership when a restore fails and clears the bit on a later retry' {
            InModuleScope TpmProgress {
                Test-TpmProgressVt | Should -BeTrue
                $script:fakeConsole.Mode | Should -Be 7
                # 1) The mode cannot be read: nothing proven, ownership is kept.
                Mock Get-TpmProgressConsoleMode { $null }
                Restore-TpmProgressVt
                $script:TpmProgressVtOwned | Should -BeTrue
                # 2) The read works but the clear fails: ownership is kept.
                Mock Get-TpmProgressConsoleMode { [uint32]$script:fakeConsole.Mode }
                Mock Set-TpmProgressConsoleMode { param($Mode) [void]$script:fakeConsole.Sets.Add([uint32]$Mode); return $false }
                Restore-TpmProgressVt
                $script:TpmProgressVtOwned | Should -BeTrue
                $script:fakeConsole.Mode | Should -Be 7
                # A re-probe in between sees the bit set but must not disown it.
                Test-TpmProgressVt | Should -BeTrue
                $script:TpmProgressVtOwned | Should -BeTrue
                # 3) The retry succeeds: only the owned bit is cleared and ownership is released.
                Mock Set-TpmProgressConsoleMode {
                    param($Mode)
                    [void]$script:fakeConsole.Sets.Add([uint32]$Mode); $script:fakeConsole.Mode = [uint32]$Mode; return $true
                }
                Restore-TpmProgressVt
                $script:fakeConsole.Mode | Should -Be 3
                $script:TpmProgressVtOwned | Should -BeFalse
            }
        }

        It 'does not write the mode when VT was already cleared by someone else before restore' {
            InModuleScope TpmProgress {
                Test-TpmProgressVt | Should -BeTrue
                $script:fakeConsole.Mode = [uint32]3
                Restore-TpmProgressVt
                $script:fakeConsole.Sets.Count | Should -Be 1
                $script:fakeConsole.Mode | Should -Be 3
                $script:TpmProgressVtOwned | Should -BeFalse
            }
        }

        It 'enables VT for a colored operation and restores the original mode at its terminal close' {
            InModuleScope TpmProgress {
                Mock Get-TpmProgressBackground { 'Black' }
                Mock Test-TpmProgressColorEnabled { $true }
                # Keep the real console's foreground color untouched by colored segment writes.
                Mock Write-TpmProgressSegments {}
                $op = Start-TpmProgressOperation -Title 'Colored' -Stage '' -Total 10
                $op.ColorMode | Should -Not -BeExactly 'None'
                $script:fakeConsole.Mode | Should -Be 7
                Complete-TpmProgressOperation
                $script:fakeConsole.Mode | Should -Be 3
                $script:TpmProgressVtOwned | Should -BeFalse
                $script:TpmProgressVtReady | Should -BeNullOrEmpty
            }
        }
    }

    Context 'FIX23 progress cost: one write per frame, non-blocking updates, adaptive throttle' {
        It 'writes each live frame, including the closing frame, with one console write that holds every row' {
            InModuleScope TpmProgress {
                $null = Start-TpmProgressOperation -Title 'Owner' -Stage 'Scan' -Total 100
                foreach ($i in 1..6) {
                    $id = Add-TpmProgressTask -Description ('Task {0}' -f $i) -Total 100
                    Set-TpmProgressTask -Id $id -Current ($i * 10)
                }
                $before = $script:surface.Writes.Count
                Step-Fix16BClock
                $script:surface.Writes.Count | Should -Be ($before + 1)
                $frame = $script:surface.Writes[$script:surface.Writes.Count - 1]
                $frame | Should -Match "^`r"
                ([regex]::Matches($frame, "`r`n")).Count | Should -Be 6
                $rows = @(Get-Fix16BVisibleRows)
                $rows.Count | Should -Be 7
                for ($i = 0; $i -lt 7; $i++) { $rows[$i].Top | Should -Be $i }
                $rows[6].Text | Should -Match 'Task 6.*60/100'
                $before = $script:surface.Writes.Count
                Complete-TpmProgressOperation -State Incomplete -Message 'stopped'
                $script:surface.Writes.Count | Should -Be ($before + 1)
                $script:surface.Writes[$script:surface.Writes.Count - 1] | Should -Match "`r`n$"
                @(Get-Fix16BVisibleRows).Count | Should -Be 7
            }
        }

        It 'colors a frame with VT sequences inside its single write and restores the foreground once per frame' {
            InModuleScope TpmProgress {
                $savedColor = $env:TPM_PROGRESS_COLOR
                $savedWt = $env:WT_SESSION
                try {
                    $env:WT_SESSION = 'fixture-session'
                    $script:surface.Restores = New-Object System.Collections.Generic.List[string]
                    Mock Get-TpmProgressBackground { 'Black' }
                    Mock Test-TpmProgressColorEnabled { $true }
                    Mock Test-TpmProgressVt { $true }
                    Mock Get-TpmProgressForeground { [System.ConsoleColor]::Gray }
                    Mock Set-TpmProgressForeground { param($Color) [void]$script:surface.Restores.Add([string]$Color) }
                    # The recording console applies SGR sequences as attributes: they take no cells.
                    Mock Write-TpmProgressRaw {
                        param($Text, $NewLine)
                        $value = [string]$Text
                        if ($NewLine) { $value += "`r`n" }
                        [void]$script:surface.Writes.Add($value)
                        Write-Fix16BCells ($value -replace ([string][char]27 + '\[[0-9;]*m'), '')
                    }
                    $esc = [regex]::Escape([string][char]27)
                    foreach ($case in @(@{ Mode = ''; ColorMode = 'TrueColor'; Fill = '38;2;\d+;\d+;\d+' }, @{ Mode = 'quantized'; ColorMode = 'Vt16'; Fill = '33' })) {
                        $env:TPM_PROGRESS_COLOR = $case.Mode
                        $script:surface.Restores.Clear()
                        $op = Start-TpmProgressOperation -Title 'Owner' -Stage 'Scan' -Total 100
                        $op.ColorMode | Should -BeExactly $case.ColorMode
                        $id = Add-TpmProgressTask -Description 'Child' -Total 100
                        Set-TpmProgressTask -Id $id -Current 40
                        $before = $script:surface.Writes.Count
                        Step-Fix16BClock
                        $script:surface.Writes.Count | Should -Be ($before + 1)
                        $frame = $script:surface.Writes[$script:surface.Writes.Count - 1]
                        # 40 percent: the RGB gradient, or the nearest of the 16 console colors (dark yellow, SGR 33) in quantized mode.
                        $frame | Should -Match ($esc + '\[' + $case.Fill + 'm#')
                        $frame | Should -Match ($esc + '\[39m')
                        $script:surface.Restores.Count | Should -Be $script:surface.Writes.Count
                        @($script:surface.Restores | Where-Object { $_ -ne 'Gray' }).Count | Should -Be 0
                        $rows = @(Get-Fix16BVisibleRows | Select-Object -Last 2)
                        $rows[0].Text | Should -Match '^\s*Owner: Scan'
                        $rows[1].Text | Should -Match 'Child.*\|#+-+\|.*40/100'
                        Complete-TpmProgressOperation -State Incomplete
                        $script:surface.Writes.Clear()
                    }
                } finally {
                    $env:TPM_PROGRESS_COLOR = $savedColor
                    $env:WT_SESSION = $savedWt
                }
            }
        }

        It 'returns from task and stage updates without drawing or waiting while the refresh writer holds the Gate' {
            InModuleScope TpmProgress {
                $op = Start-TpmProgressOperation -Title 'Owner' -Stage 'Scan' -Total 100
                $id = Add-TpmProgressTask -Description 'Child' -Total 100
                $op.Live.Owner = New-Fix22Owner
                # A running refresh writer that is busy drawing: another thread holds the Gate until released.
                $op.Live.RefreshService = [hashtable]::Synchronized(@{ Signal = (New-Object System.Threading.AutoResetEvent($false)); Failure = $null })
                $held = New-Object System.Threading.ManualResetEvent($false)
                $release = New-Object System.Threading.ManualResetEvent($false)
                $holder = [powershell]::Create()
                $async = $null
                try {
                    [void]$holder.AddScript('param($gate, $held, $release) [System.Threading.Monitor]::Enter($gate); try { [void]$held.Set(); [void]$release.WaitOne(10000) } finally { [System.Threading.Monitor]::Exit($gate) }')
                    [void]$holder.AddArgument($op.Live.Gate).AddArgument($held).AddArgument($release)
                    $async = $holder.BeginInvoke()
                    $held.WaitOne(10000) | Should -BeTrue
                    $writes = $script:surface.Writes.Count
                    $script:surface.Now = $script:surface.Now.AddMilliseconds(500)
                    $watch = [System.Diagnostics.Stopwatch]::StartNew()
                    Set-TpmProgressTask -Id $id -Current 40
                    Set-TpmProgressStage -Stage 'Scan' -Current 60 -Total 100
                    Set-TpmProgressStage -Stage 'Next stage' -Current 0 -Total 50
                    $watch.Stop()
                    $watch.ElapsedMilliseconds | Should -BeLessThan 3000
                    $script:surface.Writes.Count | Should -Be $writes
                    $op.Live.Snapshot.Stage | Should -Be 'Next stage'
                    @($op.Live.Snapshot.Tasks)[0].Current | Should -Be 40
                    [void]$release.Set()
                    [void]$holder.EndInvoke($async)
                    $async = $null
                    # Printing still redraws synchronously right below the message while the writer exists.
                    Suspend-TpmProgressOutput | Should -BeTrue
                    Write-Fix16BCells "host line`r`n"
                    $writes = $script:surface.Writes.Count
                    Resume-TpmProgressOutput
                    $script:surface.Writes.Count | Should -Be ($writes + 1)
                } finally {
                    [void]$release.Set()
                    if ($null -ne $async) { try { [void]$holder.EndInvoke($async) } catch {} }
                    $holder.Dispose(); $held.Dispose(); $release.Dispose()
                    $op.Live.RefreshService = $null
                }
                $rows = @(Get-Fix16BVisibleRows)
                $rows.Count | Should -Be 3
                $rows[0].Text | Should -Be 'host line'
                $rows[1].Text | Should -Match 'Owner: Next stage'
                $rows[2].Text | Should -Match 'Child.*40/100'
                # The refresh writer keeps drawing that published state in place.
                Step-Fix22Background 200
                $after = @(Get-Fix16BVisibleRows)
                $after.Count | Should -Be 3
                $after[1].Top | Should -Be $rows[1].Top
                $after[2].Text | Should -Match 'Child.*40/100'
            }
        }
    }

    Context 'FIX24 responsive refresh: robust frame interval, inline structural frames, writer warm-up, no blank frames' {
        BeforeEach {
            InModuleScope TpmProgress {
                # Every console write costs WriteCost ms of the module clock: the frame cost the adaptive throttle measures.
                $script:surface.WriteCost = 0
                Mock Write-TpmProgressRaw {
                    param($Text, $NewLine)
                    if ($script:surface.FailWrite) { throw 'recording surface output failure' }
                    $value = [string]$Text
                    if ($NewLine) { $value += "`r`n" }
                    [void]$script:surface.Writes.Add($value)
                    Write-Fix16BCells $value
                    $script:surface.Now = $script:surface.Now.AddMilliseconds($script:surface.WriteCost)
                }
            }
        }

        It 'ignores the warm-up frames and one slow frame, keeps 100 ms for 24 ms frames and redraws right after an overrun' {
            InModuleScope TpmProgress {
                # A cold start: the first three frames cost 300 ms each (first-call compile), then the console is fast.
                $script:surface.WriteCost = 300
                $op = Start-TpmProgressOperation -Title 'Cold start' -Stage '' -Total 10
                $writes = $script:surface.Writes.Count
                Step-Fix16BClock 100
                Step-Fix16BClock 100
                $script:surface.Writes.Count | Should -Be ($writes + 2)
                $op.Live.Frame.Frames | Should -Be 3
                $op.Live.Frame.CostMs | Should -Be 300
                Get-TpmProgressFrameInterval -Frame $op.Live.Frame | Should -Be 100
                # Steady 24 ms frames keep the 100 ms interval.
                $script:surface.WriteCost = 24
                $writes = $script:surface.Writes.Count
                for ($i = 0; $i -lt 4; $i++) { Step-Fix16BClock 100 }
                $script:surface.Writes.Count | Should -Be ($writes + 4)
                $op.Live.Frame.SustainedMs | Should -Be 24
                Get-TpmProgressFrameInterval -Frame $op.Live.Frame | Should -Be 100
                # One 215 ms frame (a console hiccup) does not move the interval, and the next frame follows at once.
                $script:surface.WriteCost = 215
                Step-Fix16BClock 100
                $op.Live.Frame.CostMs | Should -Be 215
                $op.Live.Frame.SustainedMs | Should -Be 24
                Get-TpmProgressFrameInterval -Frame $op.Live.Frame | Should -Be 100
                Get-TpmProgressRefreshWait -Live $op.Live | Should -Be 1
                $script:surface.WriteCost = 24
                $writes = $script:surface.Writes.Count
                Step-Fix16BClock 1
                $script:surface.Writes.Count | Should -Be ($writes + 1)
                # A due attempt that cannot draw (a prompt is open) waits a whole interval, never 1 ms in a loop.
                Suspend-TpmProgressLine
                Step-Fix16BClock 100
                Get-TpmProgressRefreshWait -Live $op.Live | Should -Be 100
                Resume-TpmProgressLine
            }
        }

        It 'backs off for a console that stays slow, never past 250 ms, and returns to 100 ms when it is fast again' {
            InModuleScope TpmProgress {
                $op = Start-TpmProgressOperation -Title 'Slow console' -Stage '' -Total 10
                Step-Fix16BClock 100
                Step-Fix16BClock 100
                # Sustained 60 ms frames: three times the cost.
                $script:surface.WriteCost = 60
                for ($i = 0; $i -lt 3; $i++) { Step-Fix16BClock 250 }
                $op.Live.Frame.SustainedMs | Should -Be 60
                Get-TpmProgressFrameInterval -Frame $op.Live.Frame | Should -Be 180
                # Sustained 200 ms frames: capped at 250 ms (three times would be 600 ms).
                $script:surface.WriteCost = 200
                for ($i = 0; $i -lt 3; $i++) { Step-Fix16BClock 250 }
                $op.Live.Frame.SustainedMs | Should -Be 200
                Get-TpmProgressFrameInterval -Frame $op.Live.Frame | Should -Be 250
                Get-TpmProgressRefreshWait -Live $op.Live | Should -Be 50
                $writes = $script:surface.Writes.Count
                Step-Fix16BClock 49
                $script:surface.Writes.Count | Should -Be $writes
                Step-Fix16BClock 1
                $script:surface.Writes.Count | Should -Be ($writes + 1)
                # Fast again: three fast frames bring the interval back to 100 ms.
                $script:surface.WriteCost = 0
                for ($i = 0; $i -lt 3; $i++) { Step-Fix16BClock 250 }
                $op.Live.Frame.SustainedMs | Should -Be 0
                Get-TpmProgressFrameInterval -Frame $op.Live.Frame | Should -Be 100
            }
        }

        It 'draws a new row and a task state change inline while the refresh writer only gets value updates' {
            InModuleScope TpmProgress {
                $op = Start-TpmProgressOperation -Title 'Owner' -Stage 'Scan' -Total 100
                $service = [hashtable]::Synchronized(@{ Signal = (New-Object System.Threading.AutoResetEvent($false)); Failure = $null })
                $op.Live.RefreshService = $service
                try {
                    $writes = $script:surface.Writes.Count
                    $id = Add-TpmProgressTask -Description 'New row' -Total 100
                    # The row is on screen when the call returns: one inline frame, no waiting for the writer.
                    $script:surface.Writes.Count | Should -Be ($writes + 1)
                    @(Get-Fix16BVisibleRows | Where-Object { $_.Text -match 'New row' }).Count | Should -Be 1
                    Set-TpmProgressTask -Id $id -Current 30
                    $script:surface.Writes.Count | Should -Be ($writes + 1)
                    @($op.Live.Snapshot.Tasks)[0].Current | Should -Be 30
                    Set-TpmProgressTask -Id $id -Current 100 -State Final
                    $script:surface.Writes.Count | Should -Be ($writes + 2)
                    $row = @(Get-Fix16BVisibleRows | Where-Object { $_.Text -match 'New row' })
                    $row.Count | Should -Be 1
                    $row[0].Text | Should -Match '100%'
                } finally {
                    $op.Live.RefreshService = $null
                    $service.Signal.Dispose()
                }
            }
        }

        It 'keeps value updates snapshot-only and never waits for the Gate while the refresh writer warms up; new rows still draw inline' {
            InModuleScope TpmProgress {
                $op = Start-TpmProgressOperation -Title 'Owner' -Stage 'Scan' -Total 100
                $id = Add-TpmProgressTask -Description 'Ramp' -Total 100
                # A refresh writer that has not finished its warm-up (Ready is false) while another thread holds the Gate.
                $service = [hashtable]::Synchronized(@{ Signal = (New-Object System.Threading.AutoResetEvent($false)); Failure = $null; Ready = $false })
                $op.Live.RefreshService = $service
                $held = New-Object System.Threading.ManualResetEvent($false)
                $release = New-Object System.Threading.ManualResetEvent($false)
                $holder = [powershell]::Create()
                $async = $null
                try {
                    [void]$holder.AddScript('param($gate, $held, $release) [System.Threading.Monitor]::Enter($gate); try { [void]$held.Set(); [void]$release.WaitOne(10000) } finally { [System.Threading.Monitor]::Exit($gate) }')
                    [void]$holder.AddArgument($op.Live.Gate).AddArgument($held).AddArgument($release)
                    $async = $holder.BeginInvoke()
                    $held.WaitOne(10000) | Should -BeTrue
                    $writes = $script:surface.Writes.Count
                    $watch = [System.Diagnostics.Stopwatch]::StartNew()
                    # 200 ms of 50 ms updates: frames fall due, but value updates neither draw nor wait for the Gate.
                    foreach ($step in 1..4) {
                        $script:surface.Now = $script:surface.Now.AddMilliseconds(50)
                        Set-TpmProgressTask -Id $id -Current ($step * 5)
                        Set-TpmProgressStage -Stage 'Scan' -Current $step -Total 100
                    }
                    Set-TpmProgressStage -Stage 'Next stage' -Current 0 -Total 50
                    $watch.Stop()
                    $watch.ElapsedMilliseconds | Should -BeLessThan 3000
                    $script:surface.Writes.Count | Should -Be $writes
                    @($op.Live.Snapshot.Tasks)[0].Current | Should -Be 20
                    $op.Live.Snapshot.Stage | Should -Be 'Next stage'
                    [void]$release.Set()
                    [void]$holder.EndInvoke($async)
                    $async = $null
                    # A structural change is still drawn inline while the writer warms up.
                    $null = Add-TpmProgressTask -Description 'Late row' -Total 10
                    $script:surface.Writes.Count | Should -Be ($writes + 1)
                    @(Get-Fix16BVisibleRows | Where-Object { $_.Text -match 'Late row' }).Count | Should -Be 1
                } finally {
                    [void]$release.Set()
                    if ($null -ne $async) { try { [void]$holder.EndInvoke($async) } catch {} }
                    $holder.Dispose(); $held.Dispose(); $release.Dispose()
                    $op.Live.RefreshService = $null
                    $service.Signal.Dispose()
                }
            }
        }

        It 'rewrites rows in place when rows are added or removed and blanks only the rows that went away' {
            InModuleScope TpmProgress {
                $script:surface.Cleared = New-Object System.Collections.Generic.List[int]
                Mock Clear-TpmProgressCells {
                    param($Top, $Count)
                    [void]$script:surface.Cleared.Add($Top)
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
                $null = Start-TpmProgressOperation -Title 'Owner' -Stage '' -Total 10 -HideCompleted
                $first = Add-TpmProgressTask -Description 'First child' -Total 1
                $null = Add-TpmProgressTask -Description 'Second child' -Total 1
                # Rows were added: the frame was written over itself and nothing was blanked first.
                $script:surface.Cleared.Count | Should -Be 0
                $rows = @(Get-Fix16BVisibleRows)
                $rows.Count | Should -Be 3
                for ($i = 0; $i -lt 3; $i++) { $rows[$i].Top | Should -Be $i }
                Set-TpmProgressTask -Id $first -Current 1 -State Final
                # A row went away: only the old last row was blanked; the kept rows were overwritten in place.
                $script:surface.Cleared.Count | Should -Be 1
                $script:surface.Cleared[0] | Should -Be 2
                $rows = @(Get-Fix16BVisibleRows)
                $rows.Count | Should -Be 2
                $rows[0].Text | Should -Match '^\s*Owner'
                $rows[1].Text | Should -Match 'Second child'
                $rows[1].Top | Should -Be 1
            }
        }

        It 'warms up the whole frame path with every console change switched off and leaves the operation on screen alone' {
            InModuleScope TpmProgress {
                $op = Start-TpmProgressOperation -Title 'On screen' -Stage 'Scan' -Total 10
                $screen = @(Get-Fix16BVisibleRows)
                $writes = $script:surface.Writes.Count
                $frames = $op.Live.Frame.Frames
                $snapshot = $op.Live.Snapshot
                # The seams record each console change the warm-up asks for and whether the dry-run switch was on.
                $script:surface.Dry = New-Object System.Collections.Generic.List[string]
                Mock Write-TpmProgressRaw { param($Text, $NewLine) [void]$script:surface.Dry.Add('write ' + $script:TpmProgressDryRun) }
                Mock Set-TpmProgressCursor { param($Left, $Top) [void]$script:surface.Dry.Add('cursor ' + $script:TpmProgressDryRun); return $true }
                Mock Clear-TpmProgressCells { param($Top, $Count) [void]$script:surface.Dry.Add('clear ' + $script:TpmProgressDryRun); return $true }
                Mock Set-TpmProgressForeground { param($Color) [void]$script:surface.Dry.Add('color ' + $script:TpmProgressDryRun) }
                Invoke-TpmProgressWarmup
                $script:TpmProgressDryRun | Should -BeFalse
                # Both passes composed a frame (appended, then redrawn in place), always with the switch on.
                @($script:surface.Dry | Where-Object { $_ -like 'write *' }).Count | Should -Be 2
                @($script:surface.Dry | Where-Object { $_ -like 'cursor *' }).Count | Should -Be 1
                @($script:surface.Dry | Where-Object { $_ -notlike '* True' }).Count | Should -Be 0
                # The operation on screen and its frame state are untouched.
                $script:surface.Writes.Count | Should -Be $writes
                $op.Live.Frame.Frames | Should -Be $frames
                [object]::ReferenceEquals($op.Live.Snapshot, $snapshot) | Should -BeTrue
                $after = @(Get-Fix16BVisibleRows)
                $after.Count | Should -Be $screen.Count
                $after[0].Text | Should -Be $screen[0].Text
            }
        }
    }

}

Describe 'FIX17B progress glyphs and palette' {
    It 'interpolates the documented RGB gradient and maps it to the nearest of the 16 console colors' {
        InModuleScope TpmProgress {
            $cases = @(
                @{ P = 0; R = 255; G = 140; B = 30; Color = 'Yellow' },
                @{ P = 25; R = 238; G = 150; B = 32; Color = 'Yellow' },
                @{ P = 50; R = 170; G = 190; B = 40; Color = 'DarkYellow' },
                @{ P = 75; R = 30; G = 200; B = 210; Color = 'Cyan' },
                @{ P = 100; R = 40; G = 230; B = 90; Color = 'Green' }
            )
            foreach ($case in $cases) {
                $color = Get-TpmProgressGradient -Percent $case.P -Background Black
                $color.Red | Should -Be $case.R
                $color.Green | Should -Be $case.G
                $color.Blue | Should -Be $case.B
                $color.Color | Should -Be $case.Color
            }
            (Get-TpmProgressGradient -Percent 25 -Background White).Color | Should -Be 'DarkYellow'
        }
    }

    It 'selects state and text colors independently of the running gradient' {
        InModuleScope TpmProgress {
            Get-TpmProgressSegmentColor -Role fill -State Final -Background Black | Should -Be 'Green'
            Get-TpmProgressSegmentColor -Role fill -State Incomplete -Background Black | Should -Be 'Yellow'
            Get-TpmProgressSegmentColor -Role fill -State Error -Background Black | Should -Be 'Red'
            Get-TpmProgressSegmentColor -Role unknown -State Running -Background Black | Should -Be 'Cyan'
            Get-TpmProgressSegmentColor -Role unknown -State Pending -Background Black | Should -Be 'DarkGray'
            Get-TpmProgressSegmentColor -Role state -State Skipped -Background Black | Should -Be 'DarkGray'
            Get-TpmProgressSegmentColor -Role pct -State Running -Background Black | Should -Be 'Green'
            Get-TpmProgressSegmentColor -Role time -State Running -Background Black | Should -Be 'Cyan'
            Get-TpmProgressSegmentColor -Role label -State Running -Background Black | Should -Be 'Gray'
            Get-TpmProgressSegmentColor -Role fill -State Error -Background White | Should -Be 'DarkRed'
        }
    }

    It 'draws exact framed state bars in Unicode and ASCII' {
        InModuleScope TpmProgress {
            $oldStyle = $env:TPM_PROGRESS_BAR_STYLE
            try {
                $env:TPM_PROGRESS_BAR_STYLE = 'block'
                $block = [string][char]0x2588
                $dot = [string][char]0x00B7
                $warning = [string][char]0x26A0
                $cross = [string][char]0x2717
                Format-TpmProgressBar -Current 10 -Total 10 -BarWidth 12 -State Final -Style Unicode |
                    Should -Be ('|' + ($block * 10) + '|')
                Format-TpmProgressBar -Current 5 -Total 10 -BarWidth 12 -State Incomplete -Style Unicode |
                    Should -Be ('|' + ($block * 5) + $warning + ($dot * 4) + '|')
                Format-TpmProgressBar -Current 12 -Total 10 -BarWidth 12 -State Error -Style Unicode |
                    Should -Be ('|' + ($block * 9) + $cross + '|')
                Format-TpmProgressBar -Current 5 -Total 10 -BarWidth 12 -State Incomplete -Style Ascii |
                    Should -Be '|#####!----|'
                Format-TpmProgressBar -Current 12 -Total 10 -BarWidth 12 -State Error -Style Ascii |
                    Should -Be '|#########X|'
                Format-TpmProgressBar -Current 10 -Total 10 -BarWidth 12 -State Final -Style Ascii |
                    Should -Be '|##########|'
                Format-TpmProgressBar -Current 0 -Total 10 -BarWidth 12 -State Skipped -Style Ascii |
                    Should -Be '|----------|'
                Format-TpmProgressBar -Current 1 -Total 20 -BarWidth 12 -State Running -Style Unicode |
                    Should -Be ('|' + [char]0x258C + ($dot * 9) + '|')
                $env:TPM_PROGRESS_BAR_STYLE = 'line'
                Format-TpmProgressBar -Current 5 -Total 10 -BarWidth 12 -State Running -Style Unicode |
                    Should -Be ('|' + ([string][char]0x2501 * 5) + ([string][char]0x2500 * 5) + '|')
            } finally { $env:TPM_PROGRESS_BAR_STYLE = $oldStyle }
        }
    }

    It 'bounces fourteen directional arrows at both edges in Unicode and ASCII' {
        InModuleScope TpmProgress {
            $savedStyle = $env:TPM_PROGRESS_BAR_STYLE
            try {
            $env:TPM_PROGRESS_BAR_STYLE = 'block'
            $right = [string][char]0x25B6
            $dot = [string][char]0x00B7
            $left = [string][char]0x25C0
            Format-TpmProgressBar -Total 0 -BarWidth 20 -Tick 0 -Style Unicode |
                Should -Be ('|' + ($right * 14) + ($dot * 4) + '|')
            Format-TpmProgressBar -Total 0 -BarWidth 20 -Tick 4 -Style Unicode |
                Should -Be ('|' + ($dot * 4) + ($left * 14) + '|')
            Format-TpmProgressBar -Total 0 -BarWidth 20 -Tick 8 -Style Unicode |
                Should -Be ('|' + ($right * 14) + ($dot * 4) + '|')
            Format-TpmProgressBar -Total 0 -BarWidth 20 -Tick 0 -Style Ascii |
                Should -Be ('|' + ('>' * 14) + ('-' * 4) + '|')
            Format-TpmProgressBar -Total 0 -BarWidth 20 -Tick 4 -Style Ascii |
                Should -Be ('|' + ('-' * 4) + ('<' * 14) + '|')
            } finally { $env:TPM_PROGRESS_BAR_STYLE = $savedStyle }
        }
    }

    It 'uses the exact status glyph and fallback for each state' {
        InModuleScope TpmProgress {
            # FIX105: a finished step has no ASCII status mark (the word "done" says it), so its fallback is a blank.
            $cases = @(
                @{ State = 'Pending'; Unicode = 0x25CB; Ascii = 'o' },
                @{ State = 'Final'; Unicode = 0x2713; Ascii = ' ' },
                @{ State = 'No-op'; Unicode = 0x2713; Ascii = ' ' },
                @{ State = 'Incomplete'; Unicode = 0x26A0; Ascii = '!' },
                @{ State = 'Error'; Unicode = 0x2717; Ascii = 'X' },
                @{ State = 'Skipped'; Unicode = 0x002D; Ascii = '-' }
            )
            foreach ($case in $cases) {
                Format-TpmProgressLine -Title 'task' -State $case.State -Width 1 -Style Unicode |
                    Should -Be ([string][char]$case.Unicode)
                Format-TpmProgressLine -Title 'task' -State $case.State -Width 1 -Style Ascii |
                    Should -Be $case.Ascii
            }
            Format-TpmProgressLine -Title 'task' -State Running -Width 1 -Tick 1 -Style Ascii | Should -Be '/'
        }
    }

    It 'shows actual count and percent, prefixes only attention states, and never invents unknown ETA' {
        InModuleScope TpmProgress {
            foreach ($style in @('Ascii', 'Unicode')) {
                $done = Format-TpmProgressLine -Title 'Complete' -Current 5000 -Total 5000 -State Final -ElapsedSeconds 6.4 -Width 160 -Style $style
                $done | Should -Match '5000/5000'
                $done | Should -Match '\[100%\]'
                $done | Should -Not -Match '\(!\)'
                $early = Format-TpmProgressLine -Title 'Early' -Current 5000 -Total 7000 -State Incomplete -ElapsedSeconds 6.4 -Rate 781.23 -Width 160 -Style $style
                $early | Should -Match '\(!\)\s*5000/7000'
                $early | Should -Match '\[71%\]'
                $early | Should -Match 'in 6\.4s \(781\.23/s\)'
                $over = Format-TpmProgressLine -Title 'Overshoot' -Current 5000 -Total 4000 -State Running -ElapsedSeconds 6.4 -Width 160 -Style $style
                $over | Should -Match '\(!\)\s*5000/4000'
                $over | Should -Not -Match '%'
                $unknown = Format-TpmProgressLine -Title 'Unknown' -Current 4291 -Total 0 -State Running -EtaSeconds 5 -Width 160 -Style $style
                $unknown | Should -Match '4291'
                $unknown | Should -Not -Match '%|ETA|/0'
                $unknown | Should -Not -Match '\(!\)'
            }
        }
    }

    It 'disables color for NO_COLOR and redirected output' {
        InModuleScope TpmProgress {
            $savedNoColor = $env:NO_COLOR
            $savedColor = $env:TPM_PROGRESS_COLOR
            $savedTerm = $env:TERM
            try {
                $env:TPM_PROGRESS_COLOR = 'quantized'
                $env:TERM = 'xterm'
                $env:NO_COLOR = '1'
                Mock Test-TpmProgressOutputRedirected { $false }
                Test-TpmProgressColorEnabled | Should -BeFalse
                $env:NO_COLOR = ''
                Mock Test-TpmProgressOutputRedirected { $true }
                Test-TpmProgressColorEnabled | Should -BeFalse
            } finally {
                $env:NO_COLOR = $savedNoColor
                $env:TPM_PROGRESS_COLOR = $savedColor
                $env:TERM = $savedTerm
            }
        }
    }
}

Describe 'FIX22 bar fill is proportional to finished work' {
    It 'fills ASCII bars in proportion at several widths' {
        foreach ($barWidth in @(12, 22, 42)) {
            $inner = $barWidth - 2
            foreach ($percent in @(0, 10, 25, 50, 71, 75, 99)) {
                $expected = [int][Math]::Floor($percent * $inner / 100)
                Format-TpmProgressBar -Current $percent -Total 100 -BarWidth $barWidth -State Running -Style Ascii |
                    Should -Be ('|' + ('#' * $expected) + ('-' * ($inner - $expected)) + '|')
            }
        }
        Format-TpmProgressBar -Current 25 -Total 100 -BarWidth 42 -Style Ascii | Should -Be ('|' + ('#' * 10) + ('-' * 30) + '|')
        Format-TpmProgressBar -Current 50 -Total 100 -BarWidth 42 -Style Ascii | Should -Be ('|' + ('#' * 20) + ('-' * 20) + '|')
        Format-TpmProgressBar -Current 75 -Total 100 -BarWidth 42 -Style Ascii | Should -Be ('|' + ('#' * 30) + ('-' * 10) + '|')
    }

    It 'fills Unicode block bars with whole cells plus one eighth-step partial' {
        $saved = $env:TPM_PROGRESS_BAR_STYLE
        try {
            $env:TPM_PROGRESS_BAR_STYLE = 'block'
            $block = [char]0x2588
            foreach ($barWidth in @(12, 22, 42)) {
                $inner = $barWidth - 2
                foreach ($percent in @(25, 33, 50, 75)) {
                    $bar = Format-TpmProgressBar -Current $percent -Total 100 -BarWidth $barWidth -State Running -Style Unicode
                    $bar.Length | Should -Be $barWidth
                    $exact = $percent * $inner / 100.0
                    $whole = [int][Math]::Floor($exact)
                    @($bar.ToCharArray() | Where-Object { $_ -eq $block }).Count | Should -Be $whole
                    $eighths = [int][Math]::Floor(($exact - $whole) * 8)
                    if ($eighths -gt 0) { $bar[1 + $whole] | Should -Be ([char](0x2590 - $eighths)) }
                    else { $bar[1 + $whole] | Should -Be ([char]0x00B7) }
                }
            }
        } finally { $env:TPM_PROGRESS_BAR_STYLE = $saved }
    }

    It 'keeps the fill proportional inside laid-out rows, including rows closed Incomplete' {
        foreach ($width in @(60, 80, 119)) {
            foreach ($percent in @(0, 25, 50, 75)) {
                foreach ($state in @('Running', 'Incomplete')) {
                    $line = Format-TpmProgressLine -Title 'Row' -Current $percent -Total 100 -State $state -Width $width -Style Ascii
                    $line.Length | Should -Be $width
                    $bar = [regex]::Match($line, '\|(#*)(!?)(-*)\|')
                    $bar.Success | Should -BeTrue
                    $inner = $bar.Groups[1].Length + $bar.Groups[2].Length + $bar.Groups[3].Length
                    $inner | Should -BeGreaterOrEqual 8
                    $bar.Groups[1].Length | Should -Be ([int][Math]::Floor($percent * $inner / 100))
                    if ($state -eq 'Incomplete') { $bar.Groups[2].Value | Should -Be '!' }
                }
            }
        }
    }

    It 'shows fractional elapsed seconds and rates below one per second' {
        $line = Format-TpmProgressLine -Title 'Slow' -Current 1 -Total 10 -ElapsedSeconds 2.7 -Rate 0.3 -Width 160 -Style Ascii
        $line | Should -Match 'in 2\.7s \(0\.30/s\)'
    }
}

Describe 'FIX24 refresh writer warm-up switch on the real console seams' {
    It 'makes the seams that write, move the cursor or blank cells do nothing while the switch is on' {
        InModuleScope TpmProgress {
            $savedOut = [Console]::Out
            $savedWide = $script:TpmProgressWideWriteActive
            $capture = New-Object System.IO.StringWriter
            try {
                $script:TpmProgressWideWriteActive = $false
                [Console]::SetOut($capture)
                $script:TpmProgressDryRun = $true
                Write-TpmProgressRaw -Text 'dry' -NewLine
                # Impossible coordinates: the real console calls fail, so only the switch can report success.
                Set-TpmProgressCursor -Left -1 -Top -1 | Should -BeTrue
                Clear-TpmProgressCells -Top -1 -Count 3 | Should -BeTrue
                $script:TpmProgressDryRun = $false
                Write-TpmProgressRaw -Text 'live'
                Set-TpmProgressCursor -Left -1 -Top -1 | Should -BeFalse
                Clear-TpmProgressCells -Top -1 -Count 3 | Should -BeFalse
            } finally {
                $script:TpmProgressDryRun = $false
                $script:TpmProgressWideWriteActive = $savedWide
                [Console]::SetOut($savedOut)
            }
            $capture.ToString() | Should -Be 'live'
        }
    }
}
