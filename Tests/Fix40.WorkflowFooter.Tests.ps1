#Requires -Module Pester
# FIX40: the workflow status footer must never leave text behind that a later prompt or heading is written over
# ("Choice, default R: dstatus  [OK] ..."). Fake-only: a character-cell screen behind a RawUI stand-in; no real console.
# What this CANNOT prove: how a real ConsoleHost / Windows Terminal reports window position and cursor while it scrolls.
BeforeAll {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors -join '; ') }
    $wanted = @('Get-TpmWorkflowFooterRowText', 'Get-TpmWorkflowFooterRowMatch', 'Clear-TpmWorkflowFooterCells', 'Write-Host')
    $texts = foreach ($name in $wanted) {
        $found = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $name }, $true))
        if ($found.Count -ne 1) { throw "Expected exactly one $name." }
        # The host shim is renamed so the test cannot replace the real Write-Host for Pester itself.
        $found[0].Extent.Text -replace '^function Write-Host\b', 'function Write-Fix40Host'
    }
    $functionPath = Join-Path $TestDrive 'fix40-footer-functions.ps1'
    $texts -join "`r`n`r`n" | Set-Content -LiteralPath $functionPath -Encoding UTF8
    . $functionPath

    function Clear-TpmWorkflowFooter { param($Context) [void]$script:fix40Events.Add('clear') }
    function Render-TpmWorkflowStatus { param($Context) [void]$script:fix40Events.Add('render') }

    function New-Fix40Raw {
        param([int]$Width = 100, [int]$Height = 40, [int]$WindowTop = 10, [int]$WindowHeight = 30)
        $raw = [pscustomobject]@{
            Rows = (New-Object 'System.Collections.Generic.List[string]')
            BufferSize = [pscustomobject]@{ Width = $Width; Height = $Height }
            WindowSize = [pscustomobject]@{ Width = $Width; Height = $WindowHeight }
            WindowPosition = [pscustomobject]@{ X = 0; Y = $WindowTop }
            CursorPosition = [pscustomobject]@{ X = 0; Y = 0 }
        }
        for ($i = 0; $i -lt $Height; $i++) { [void]$raw.Rows.Add(' ' * $Width) }
        $raw | Add-Member -MemberType ScriptMethod -Name GetBufferContents -Value {
            param($Rectangle)
            $rowCount = $Rectangle.Bottom - $Rectangle.Top + 1
            $colCount = $Rectangle.Right - $Rectangle.Left + 1
            $cells = New-Object 'System.Management.Automation.Host.BufferCell[,]' $rowCount, $colCount
            for ($y = 0; $y -lt $rowCount; $y++) {
                $text = $this.Rows[$Rectangle.Top + $y]
                for ($x = 0; $x -lt $colCount; $x++) {
                    $cells[$y, $x] = New-Object System.Management.Automation.Host.BufferCell($text[$Rectangle.Left + $x], [ConsoleColor]::Gray, [ConsoleColor]::Black, [System.Management.Automation.Host.BufferCellType]::Complete)
                }
            }
            return ,$cells
        }
        $raw | Add-Member -MemberType ScriptMethod -Name SetBufferContents -Value {
            param($Rectangle, $Fill)
            for ($y = $Rectangle.Top; $y -le $Rectangle.Bottom; $y++) {
                $chars = $this.Rows[$y].ToCharArray()
                for ($x = $Rectangle.Left; $x -le $Rectangle.Right; $x++) { $chars[$x] = $Fill.Character }
                $this.Rows[$y] = -join $chars
            }
        }
        return $raw
    }
    function Set-Fix40Text {
        # Writes Text at (Column, Row) over whatever is there, the way ordinary console output does.
        param($Raw, [int]$Row, [string]$Text, [int]$Column = 0)
        $chars = $Raw.Rows[$Row].ToCharArray()
        for ($i = 0; $i -lt $Text.Length; $i++) { $chars[$Column + $i] = $Text[$i] }
        $Raw.Rows[$Row] = -join $chars
    }
}

Describe 'FIX40 pinned workflow footer erase' {
    BeforeEach {
        $script:fix40Width = 100
        $script:fix40Rows = @(
            'TeknoParrot Manager status  [OK] Game requirements checked -> Backing up existing databases',
            'Step 2 of 5 | Waiting for you | Choose a PostgreSQL recovery option',
            'Next: Review the result'
        )
        $script:fix40Bounds = [pscustomobject]@{ Top = 20; Height = 3; Width = 100; WindowTop = 10 }
        $script:fix40Raw = New-Fix40Raw -Width 100 -Height 40 -WindowTop 10 -WindowHeight 30
    }

    It 'blanks the whole footer when the window has scrolled since it was drawn' {
        $raw = $script:fix40Raw
        for ($i = 0; $i -lt 3; $i++) { Set-Fix40Text -Raw $raw -Row (20 + $i) -Text $script:fix40Rows[$i] }
        Set-Fix40Text -Raw $raw -Row 19 -Text 'menu line above the footer'
        $raw.WindowPosition.Y = 25
        $raw.CursorPosition.Y = 19
        (Clear-TpmWorkflowFooterCells -Raw $raw -Bounds $script:fix40Bounds -Rows $script:fix40Rows) | Should -BeTrue
        foreach ($row in 20..22) { $raw.Rows[$row].Trim() | Should -Be '' }
        $raw.Rows[19].TrimEnd() | Should -Be 'menu line above the footer'
    }

    It 'leaves a prompt and a heading that were written over the footer intact and removes the rest of the footer lines' {
        $raw = $script:fix40Raw
        for ($i = 0; $i -lt 3; $i++) { Set-Fix40Text -Raw $raw -Row (20 + $i) -Text $script:fix40Rows[$i] }
        Set-Fix40Text -Raw $raw -Row 20 -Text 'Choice, default R: d'
        Set-Fix40Text -Raw $raw -Row 21 -Text 'PostgreSQL backup details'
        $raw.CursorPosition.X = 20
        $raw.CursorPosition.Y = 20
        (Clear-TpmWorkflowFooterCells -Raw $raw -Bounds $script:fix40Bounds -Rows $script:fix40Rows) | Should -BeTrue
        $raw.Rows[20].TrimEnd() | Should -Be 'Choice, default R: d'
        $raw.Rows[21].TrimEnd() | Should -Be 'PostgreSQL backup details'
        $raw.Rows[22].Trim() | Should -Be ''
        $raw.Rows[20] | Should -Not -Match 'status'
        $raw.Rows[21] | Should -Not -Match 'recovery option'
    }

    It 'never blanks cells left of the cursor on its own row' {
        $raw = $script:fix40Raw
        for ($i = 0; $i -lt 3; $i++) { Set-Fix40Text -Raw $raw -Row (20 + $i) -Text $script:fix40Rows[$i] }
        $raw.CursorPosition.X = 30
        $raw.CursorPosition.Y = 20
        (Clear-TpmWorkflowFooterCells -Raw $raw -Bounds $script:fix40Bounds -Rows $script:fix40Rows) | Should -BeTrue
        $raw.Rows[20].TrimEnd() | Should -Be $script:fix40Rows[0].Substring(0, 30)
    }

    It 'finds the footer where it is now when the buffer scrolled it up, and touches nothing else' {
        $raw = $script:fix40Raw
        for ($i = 0; $i -lt 3; $i++) { Set-Fix40Text -Raw $raw -Row (18 + $i) -Text $script:fix40Rows[$i] }
        Set-Fix40Text -Raw $raw -Row 17 -Text 'foreign text above'
        Set-Fix40Text -Raw $raw -Row 22 -Text 'foreign text below'
        $raw.CursorPosition.Y = 21
        (Clear-TpmWorkflowFooterCells -Raw $raw -Bounds $script:fix40Bounds -Rows $script:fix40Rows) | Should -BeTrue
        foreach ($row in 18..20) { $raw.Rows[$row].Trim() | Should -Be '' }
        $raw.Rows[17].TrimEnd() | Should -Be 'foreign text above'
        $raw.Rows[22].TrimEnd() | Should -Be 'foreign text below'
    }

    It 'reports not found and erases nothing when no visible row carries the footer text' {
        $raw = $script:fix40Raw
        foreach ($row in 18..24) { Set-Fix40Text -Raw $raw -Row $row -Text ('someone else wrote row {0} of the screen here' -f $row) }
        $before = @($raw.Rows)
        (Clear-TpmWorkflowFooterCells -Raw $raw -Bounds $script:fix40Bounds -Rows $script:fix40Rows) | Should -BeFalse
        for ($i = 0; $i -lt $before.Count; $i++) { $raw.Rows[$i] | Should -Be $before[$i] }
    }
}

Describe 'FIX40 console output clears a footer that an actionable event drew' {
    BeforeEach {
        $script:fix40Events = New-Object System.Collections.Generic.List[string]
        $script:TpmWorkflowRendering = $false
        $script:ActiveTpmWorkflowStatus = $null
    }
    AfterEach {
        $script:ActiveTpmWorkflowStatus = $null
        $script:TpmWorkflowRendering = $false
    }

    It 'does nothing extra without an active workflow' {
        Write-Fix40Host 'plain' 6>$null
        $script:fix40Events.Count | Should -Be 0
    }

    It 'leaves ordinary output alone when routine telemetry is off and no footer is drawn' {
        $script:ActiveTpmWorkflowStatus = [pscustomobject]@{ Closed = $false; ShowTelemetry = $false; FooterBounds = $null }
        Write-Fix40Host 'plain' 6>$null
        $script:fix40Events.Count | Should -Be 0
    }

    It 'erases the footer before output when routine telemetry is off, and does not draw it again' {
        $script:ActiveTpmWorkflowStatus = [pscustomobject]@{ Closed = $false; ShowTelemetry = $false; FooterBounds = [pscustomobject]@{ Top = 20; Height = 3; Width = 100 } }
        Write-Fix40Host 'menu line' 6>$null
        @($script:fix40Events) | Should -Be @('clear')
    }

    It 'erases and redraws around output in telemetry mode as before' {
        $script:ActiveTpmWorkflowStatus = [pscustomobject]@{ Closed = $false; ShowTelemetry = $true; FooterBounds = $null }
        Write-Fix40Host 'menu line' 6>$null
        @($script:fix40Events) | Should -Be @('clear', 'render')
    }

    It 'does not recurse while the footer itself is being rendered' {
        $script:ActiveTpmWorkflowStatus = [pscustomobject]@{ Closed = $false; ShowTelemetry = $true; FooterBounds = [pscustomobject]@{ Top = 20; Height = 3; Width = 100 } }
        $script:TpmWorkflowRendering = $true
        Write-Fix40Host 'footer text' 6>$null
        $script:fix40Events.Count | Should -Be 0
    }
}
