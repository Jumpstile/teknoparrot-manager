# Owner 1/9, #323, TPM-RC8-RESHADE-CONSOLE-BUFFER-001.
BeforeAll {
    $root = Split-Path -Path $PSScriptRoot -Parent
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'TeknoParrot-Manager.ps1'), [ref]$null, [ref]$null)
    $names = @('Write-TpmReShadeTerminalLines', 'Get-TpmReShadeConsoleTextWidth', 'Get-TpmConsoleMetrics', 'Get-TpmConsoleCursorPosition', 'Set-TpmConsoleCursorPosition', 'Write-TpmConsoleText', 'Read-TpmConsoleRowText', 'Get-TpmReShadeConsoleGeometrySnapshot', 'Test-TpmReShadeConsoleGeometryChanged', 'New-TpmReShadeTerminalLayout', 'Get-TpmConsoleRowCount', 'Update-TpmReShadeTerminalSelectionInPlace', 'Get-TpmReShadeProfileDisplayLabel', 'Get-TpmReShadeProfileTextField', 'Write-Log')
    $defs = $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $names }, $true)
    $extract = Join-Path $TestDrive 'finite-console-functions.ps1'
    [IO.File]::WriteAllText($extract, (($defs | ForEach-Object { $_.Extent.Text }) -join "`r`n"), (New-Object Text.UTF8Encoding($false)))
    . $extract
    function New-FiniteConsole {
        param([int]$Width = 20, [int]$Height = 6, [int]$Start = 0)
        @{ Width = $Width; Height = $Height; Row = $Start; Col = 0; Rows = @('') * $Height; History = (New-Object 'System.Collections.Generic.List[string]'); Scrolls = 0; Unsupported = $false }
    }
    function Add-FiniteConsoleText {
        param([string]$Text)
        foreach ($ch in $Text.ToCharArray()) {
            if ($ch -eq "`r") { $script:finite.Col = 0; continue }
            if ($ch -eq "`n") {
                if ($script:finite.Row -eq $script:finite.Height - 1) {
                    [void]$script:finite.History.Add($script:finite.Rows[0])
                    for ($i = 1; $i -lt $script:finite.Height; $i++) { $script:finite.Rows[$i - 1] = $script:finite.Rows[$i] }
                    $script:finite.Rows[$script:finite.Row] = ''
                    $script:finite.Scrolls++
                } else { $script:finite.Row++ }
                $script:finite.Col = 0
                continue
            }
            if ($script:finite.Col -ge $script:finite.Width) { Add-FiniteConsoleText "`n" }
            $row = $script:finite.Rows[$script:finite.Row].PadRight($script:finite.Col)
            $tail = if ($row.Length -gt $script:finite.Col + 1) { $row.Substring($script:finite.Col + 1) } else { '' }
            $script:finite.Rows[$script:finite.Row] = $row.Substring(0, $script:finite.Col) + $ch + $tail
            $script:finite.Col++
        }
    }
    function New-FiniteLine {
        param([string]$Text, [string]$Kind = 'Text', [string]$ProfileId = '')
        [pscustomobject]@{ Text = $Text; Color = 'White'; Kind = $Kind; ProfileId = $ProfileId }
    }
}
Describe 'ReShade finite buffer rendering' {
    BeforeEach {
        $script:finite = New-FiniteConsole
        Mock Write-TpmConsoleText { Add-FiniteConsoleText $Text }
        Mock Write-Host { Add-FiniteConsoleText ([string]$Object + $(if ($NoNewline) { '' } else { "`n" })) }
        Mock Write-Log {}
        Mock Get-TpmConsoleCursorPosition { if ($script:finite.Unsupported) { throw 'no console cursor' }; [pscustomobject]@{ Left = $script:finite.Col; Top = $script:finite.Row } }
        Mock Get-TpmConsoleMetrics {
            if ($script:finite.Unsupported) { throw 'no console geometry' }
            [pscustomobject]@{ Width = $script:finite.Width; Left = 0; Top = 0; Height = $script:finite.Height; BufferWidth = $script:finite.Width; BufferHeight = $script:finite.Height }
        }
        Mock Set-TpmConsoleCursorPosition {
            if ($Left -lt 0 -or $Left -ge $script:finite.Width -or $Top -lt 0 -or $Top -ge $script:finite.Height) { throw 'finite console cursor out of bounds' }
            $script:finite.Col = $Left; $script:finite.Row = $Top
        }
        # FIX46: the in-place update reads rows back from the console; this finite buffer is that console.
        Mock Read-TpmConsoleRowText {
            if ($Row -lt 0 -or $Row -ge $script:finite.Height) { throw 'finite console row out of bounds' }
            ([string]$script:finite.Rows[$Row]).PadRight($Left + $Width).Substring($Left, $Width)
        }
    }
    It 'retains every row and naturally scrolls from <Start> with <Count> rows' -TestCases @(
        @{ Start = 0; Count = 2 }, @{ Start = 4; Count = 2 }, @{ Start = 5; Count = 1 }, @{ Start = 0; Count = 9 }
    ) {
        param($Start, $Count)
        $script:finite.Row = $Start
        $texts = @(1..$Count | ForEach-Object { 'row ' + $_ })
        Write-TpmReShadeTerminalLines -Lines @($texts | ForEach-Object { New-FiniteLine $_ })
        $rendered = @($script:finite.History) + @($script:finite.Rows)
        ($rendered[$Start..($Start + $Count - 1)] -join '|') | Should -Be ($texts -join '|')
        $script:finite.Row | Should -Be ([Math]::Min(5, $Start + $Count))
        $script:finite.Col | Should -Be 0
        $script:finite.Scrolls | Should -Be ([Math]::Max(0, $Start + $Count - 5))
    }
    It 'retains blank and wrapped rows across the bottom boundary' {
        $script:finite.Row = 5
        Write-TpmReShadeTerminalLines -Lines @((New-FiniteLine ''), (New-FiniteLine 'abcdefghijklmnopqrstuvw'), (New-FiniteLine 'tail'))
        $rendered = @($script:finite.History) + @($script:finite.Rows)
        ($rendered[5..8] -join '|') | Should -Be '|abcdefghijklmnopqrs|tuvw|tail'
        $script:finite.Rows[4] | Should -Be 'tail'
        $script:finite.Row | Should -Be 5
        $script:finite.Scrolls | Should -Be 4
    }
    It 'uses the new width for a subsequent render after resize without losing text' {
        Write-TpmReShadeTerminalLines -Lines @((New-FiniteLine 'first'))
        $script:finite.Width = 8
        Write-TpmReShadeTerminalLines -Lines @((New-FiniteLine 'abcdefghijklmnop'))
        ($script:finite.Rows[0..3] -join '|') | Should -Be 'first|abcdefg|hijklmn|op'
        $script:finite.Col | Should -Be 0
    }
    It 'preserves append-only output when geometry is unsupported' {
        $script:finite.Unsupported = $true
        Write-TpmReShadeTerminalLines -Lines @((New-FiniteLine 'first'), (New-FiniteLine ''), (New-FiniteLine 'last'))
        ($script:finite.Rows[0..2] -join '|') | Should -Be 'first||last'
    }
    It 'preserves append-only output for zero-width redirected geometry' {
        Mock Get-TpmConsoleMetrics { [pscustomobject]@{ Width = 0; Left = 0; Top = 0; Height = 0; BufferWidth = 0; BufferHeight = 0 } }
        Write-TpmReShadeTerminalLines -Lines @((New-FiniteLine 'redirected'), (New-FiniteLine ''), (New-FiniteLine 'last'))
        ($script:finite.Rows[0..2] -join '|') | Should -Be 'redirected||last'
    }
    It 'updates visible selection and restores partial input after the buffer has scrolled' {
        $script:finite.Width = 60
        $script:finite.Row = 5
        $lines = @((New-FiniteLine '  [1] * Old' 'Title' 'Old'), (New-FiniteLine '  [2]   New' 'Title' 'New'), (New-FiniteLine '  Current selection: Old' 'Current'), (New-FiniteLine '  Choose profile' 'Choose'))
        Write-TpmReShadeTerminalLines -Lines $lines
        $layout = New-TpmReShadeTerminalLayout -Lines $lines -Width 60 -Metrics (Get-TpmConsoleMetrics)
        Write-TpmConsoleText '  Choice: 12'
        $beforeRow = $script:finite.Row
        $beforeScrolls = $script:finite.Scrolls
        $fixtureProfile = [pscustomobject]@{ ProfileId = 'New'; FriendlyName = 'New'; TechnicalName = '' }
        $result = Update-TpmReShadeTerminalSelectionInPlace -Layout $layout -NewProfile $fixtureProfile -Prompt '  Choice' -BufferLength 2
        $result.Updated | Should -BeTrue
        $result.MarkersUpdated | Should -Be 2
        $script:finite.Rows[1].TrimEnd() | Should -Be '  [1]   Old'
        $script:finite.Rows[2].TrimEnd() | Should -Be '  [2] * New'
        $script:finite.Rows[3].TrimEnd() | Should -Be '  Current selection: New'
        $script:finite.Rows[5] | Should -Be '  Choice: 12'
        $script:finite.Row | Should -Be $beforeRow
        $script:finite.Col | Should -Be 12
        $script:finite.Scrolls | Should -Be $beforeScrolls
    }
}
