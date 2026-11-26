#Requires -Module Pester

# RC8 UI: the one shared progress renderer (scripts\TpmProgress.psm1). Layout, ASCII vs glyph mode, percent and ETA
# rules, unknown totals, failure closes, redirected output and nested ownership. Fake-only: the module's clock and
# console seams (Get-TpmProgressNow, Write-TpmProgressRaw, Write-TpmProgressPlainLine, Get-TpmProgressCursor,
# Get-TpmProgressWidth, Test-TpmProgressOutputRedirected) are mocked, so nothing here touches a real console,
# the product script, an install, or the network.

BeforeAll {
    $script:modulePath = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $PSScriptRoot '..\scripts') 'TpmProgress.psm1'))
    # Module-scoped mocks (Mock -ModuleName / InModuleScope) need exactly one loaded TpmProgress. Earlier test files in the
    # same session can leave a fixture copy loaded from their $TestDrive, and Import-Module -Force from this second path
    # would load a second module of the same name (test-PC run 5): remove every copy, then import the repository copy.
    Get-Module -Name TpmProgress -All | Remove-Module -Force
    Import-Module $script:modulePath -Force -ErrorAction Stop
    $script:glyphFill = [string][char]0x2588
    $script:glyphHalf = [string][char]0x258C

    # Which optional columns appear on a line. Labels in these tests contain no digits or colons.
    function Get-Rc8UiColumns {
        param([string]$Line)
        $columns = New-Object System.Collections.Generic.List[string]
        if ($Line -match '\d+%') { [void]$columns.Add('pct') }
        if ($Line -match '\|[#-]+\|') { [void]$columns.Add('bar') }
        if ($Line -match '\d+/\d+') { [void]$columns.Add('count') }
        if ($Line -match '\bin \d+(\.\d+)?s') { [void]$columns.Add('time') }
        if ($Line -match 'ETA \d') { [void]$columns.Add('eta') }
        return $columns.ToArray()
    }

    # Pester 5 rejects a BeforeEach directly in the file root ("Each test setup is not supported in root"), which
    # reported every test in this file as not run. Every top-level Describe calls this first in its own BeforeEach,
    # so each test gets the same per-test mocks as before and Describe-specific mocks still override them.
    function Set-RendererDefaultMocks {
        # Exercise the configurable full-data layout; FIX16B covers the Spectre-style default separately.
        Mock Get-TpmProgressDefaultColumns { @('Spinner', 'Description', 'Bar', 'Percentage', 'Count', 'Elapsed', 'Remaining') } -ModuleName TpmProgress
        Mock Start-TpmProgressRefresh {} -ModuleName TpmProgress
        Mock Get-TpmProgressCursorVisible { $true } -ModuleName TpmProgress
        Mock Set-TpmProgressCursorVisible {} -ModuleName TpmProgress
    }
}

AfterAll {
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
}

Describe 'Format-TpmProgressLine layout' {
    BeforeEach { Set-RendererDefaultMocks }

    It 'returns exactly the requested width at every window width, never wrapping' {
        foreach ($width in @(200, 140, 100, 79, 60, 59, 50, 40, 30, 20, 16, 12, 8, 4, 1)) {
            $line = Format-TpmProgressLine -Title 'Scan' -Stage 'Fixture' -Current 3 -Total 10 -ElapsedSeconds 7 -EtaSeconds 16 -Width $width
            $line.Length | Should -Be $width
            $line | Should -Not -Match "[`r`n]"
        }
    }

    It 'shows every column when there is room' {
        $line = Format-TpmProgressLine -Title 'Scan' -Stage 'Fixture' -Current 3 -Total 10 -ElapsedSeconds 7 -EtaSeconds 16 -Width 100
        $line | Should -Match 'Scan: Fixture'
        $line | Should -Match '\|#+-+\|'
        $line | Should -Match '\[30%\]'
        $line | Should -Match '\s3/10'
        $line | Should -Match '\bin 7\.0s'
        $line | Should -Match 'ETA 0:16'
    }

    It 'drops columns in the fixed order ETA, elapsed, count, bar, percent as the window narrows' {
        $order = @('pct', 'bar', 'count', 'time', 'eta')
        $previous = 99
        foreach ($width in 200..12) {
            $line = Format-TpmProgressLine -Title 'Scan' -Stage 'Fixture' -Current 3 -Total 10 -ElapsedSeconds 7 -EtaSeconds 16 -Width $width
            $present = @(Get-Rc8UiColumns -Line $line)
            # The visible columns are always a prefix of the priority list: nothing is dropped out of order.
            $expected = if ($present.Count -eq 0) { '' } else { ($order[0..($present.Count - 1)]) -join ',' }
            ($present -join ',') | Should -Be $expected
            $present.Count | Should -BeLessOrEqual $previous
            $previous = $present.Count
        }
    }

    It 'retains all columns in a wide window and drops ETA before elapsed as space narrows' {
        $wide = Get-Rc8UiColumns -Line (Format-TpmProgressLine -Title 'Scan' -Stage 'Fixture' -Current 3 -Total 10 -ElapsedSeconds 7 -EtaSeconds 16 -Width 200)
        ($wide -join ',') | Should -Be 'pct,bar,count,time,eta'
        $withoutEta = @(200..12 | ForEach-Object {
            $columns = @(Get-Rc8UiColumns -Line (Format-TpmProgressLine -Title 'Scan' -Stage 'Fixture' -Current 3 -Total 10 -ElapsedSeconds 7 -EtaSeconds 16 -Width $_))
            if (($columns -join ',') -eq 'pct,bar,count,time') { $_ }
        })
        $withoutEta.Count | Should -BeGreaterThan 0
    }

    It 'truncates a long label with an ellipsis inside the label column' {
        $line = Format-TpmProgressLine -Title 'Extracting' -Stage ('Game-' + ('x' * 200)) -Current 3 -Total 10 -ElapsedSeconds 2 -Width 80
        $line.Length | Should -Be 80
        $line | Should -Match '\.\.\.'
        $line | Should -Match '\[30%\]'
    }

    It 'aligns bars and percentages for different labels and counts using shared row widths' {
        InModuleScope TpmProgress {
            $columns = @('Spinner', 'Description', 'Bar', 'Percentage', 'Count', 'Elapsed', 'Remaining')
            $a = (@(Format-TpmProgressSegments -Title 'Scan' -Stage 'A' -Current 1 -Total 9 -ElapsedSeconds 1 -Width 120 -DescriptionWidth 32 -CountWidth 9 -Columns $columns) | ForEach-Object { $_.Text }) -join ''
            $b = (@(Format-TpmProgressSegments -Title 'Extracting' -Stage 'A much longer label' -Current 5 -Total 9 -ElapsedSeconds 1 -Width 120 -DescriptionWidth 32 -CountWidth 9 -Columns $columns) | ForEach-Object { $_.Text }) -join ''
            $a.IndexOf('|', 2) | Should -BeGreaterThan 0
            $a.IndexOf('|', 2) | Should -Be $b.IndexOf('|', 2)
            $a.IndexOf('%') | Should -Be $b.IndexOf('%')
        }
    }

    # FIX27 (owner decision 1(a) of FIX26): a label that the label-first rule would still cut takes whole optional
    # columns before it is shortened. The expected lines are exact, so they also pin every column that must stay.
    It 'gives a label that would be cut the elapsed/rate column first, and the count only when the whole label then fits' {
        $columns = @('Spinner', 'Description', 'Bar', 'Percentage', 'Count', 'Elapsed', 'Remaining')
        $render = { param([string]$Stage, [double]$Eta = -1) Format-TpmProgressLine -Title 'Work' -Stage $Stage -Current 4 -Total 10 -ElapsedSeconds 10 -EtaSeconds $Eta -Rate 0 -Width 79 -Columns $columns }
        # A label that fits keeps every column (the unchanged layout).
        & $render 'Copy' | Should -BeExactly '|        Work: Copy |####------|  [40%]      4/10 in 10.0s (0.00/s)            '
        # 35 cells at the 79-column redirected default: the elapsed/rate column gives way; the count and a shown ETA stay.
        & $render 'Waiting for the child process' | Should -BeExactly '| Work: Waiting for the child process |########--------------|  [40%]      4/10'
        & $render 'Waiting for the child process' 16 | Should -BeExactly '| Work: Waiting for the child process |####------|  [40%]      4/10 ETA 0:16   '
        # 53 cells: the elapsed/rate column is not enough, so the count gives way as well; the bar and percent stay.
        & $render 'Waiting for the child process to finish copying' | Should -BeExactly '| Work: Waiting for the child process to finish copying |#####---------|  [40%]'
        # Too long even without the count: only the elapsed/rate column gives way, the count stays, the label is shortened.
        & $render ('Waiting for ' + ('x' * 80)) | Should -BeExactly ('| Work: Waiting for ' + ('x' * 28) + '... |###-----|  [40%]      4/10')
        # Without a Percentage column the count is the only progress number: it stays and the label is shortened.
        Format-TpmProgressLine -Title 'Work' -Stage 'Waiting for the child process to finish copying files' -Current 4 -Total 10 -ElapsedSeconds 10 -Rate 0 -Width 79 -Columns @('Spinner', 'Description', 'Bar', 'Count', 'Elapsed', 'Remaining') |
            Should -BeExactly '| Work: Waiting for the child process to finish copying... |###-----|      4/10'
    }

    It 'keeps the state word, bar and percent when a failure note takes the optional columns' {
        $columns = @('Spinner', 'Description', 'Bar', 'Percentage', 'Count', 'Elapsed', 'Remaining')
        # The redirected abandoned close at the 79-column default, which used to read "Scanning: Abandon...".
        Format-TpmProgressLine -Title 'Scanning' -Stage 'Abandoned before completion' -Current 0 -Total 4 -State Error -Width 79 -Columns $columns |
            Should -BeExactly 'X Scanning: Abandoned before completion |-------X|   [0%]   (!) 0/4 FAILED     '
        Format-TpmProgressLine -Title 'Backup' -Stage 'Copy failed: the target disk is full' -Current 4 -Total 10 -State Error -Width 79 -Columns $columns |
            Should -BeExactly 'X Backup: Copy failed: the target disk is full |####------X|  [40%] FAILED     '
    }

    It 'gives a label the blank percent column of an unknown total, never its count' {
        $columns = @('Spinner', 'Description', 'Bar', 'Percentage', 'Count', 'Elapsed', 'Remaining')
        Format-TpmProgressLine -Title 'Discovery' -Stage 'Looking for games in every library folder' -Current 17 -Total 0 -ElapsedSeconds 30 -Width 79 -Columns $columns |
            Should -BeExactly '| Discovery: Looking for games in every library folder |>>>>>>>>>>>>|        17'
        # Too long even without the blank percent column: that column stays and the label is shortened.
        Format-TpmProgressLine -Title 'Discovery' -Stage 'Looking for games in every library folder and its subfolders' -Current 17 -Total 0 -ElapsedSeconds 30 -Width 79 -Columns $columns |
            Should -BeExactly '| Discovery: Looking for games in every library ... |>>>>>>>>|               17'
    }

    It 'drops only the elapsed/rate column in a live frame, on every row, so the rows stay aligned' {
        InModuleScope TpmProgress {
            # Live rows share the description, count, percent and time widths (Write-TpmProgressLiveFrame).
            $shared = @{
                Current = 4; Total = 10; ElapsedSeconds = 10; Rate = 0; Width = 79; DescriptionWidth = 35; CountWidth = 9; PercentWidth = 6; TimeWidth = 17
                Columns = @('Spinner', 'Description', 'Bar', 'Percentage', 'Count', 'Elapsed', 'Remaining')
            }
            $long = (@(Format-TpmProgressSegments -Title 'Work' -Stage 'Waiting for the child process' @shared) | ForEach-Object { $_.Text }) -join ''
            $short = (@(Format-TpmProgressSegments -Title 'Work' -Stage 'Copy' @shared) | ForEach-Object { $_.Text }) -join ''
            $long | Should -BeExactly '| Work: Waiting for the child process |###------|  [40%]      4/10             '
            $short | Should -BeExactly '|                          Work: Copy |###------|  [40%]      4/10             '
            $short.IndexOf('|', 2) | Should -Be $long.IndexOf('|', 2)
        }
    }

    It 'leaves the output at 120 columns unchanged when the labels fit there, with every column' {
        $columns = @('Spinner', 'Description', 'Bar', 'Percentage', 'Count', 'Elapsed', 'Remaining')
        Format-TpmProgressLine -Title 'Work' -Stage 'Waiting for the child process' -Current 4 -Total 10 -ElapsedSeconds 10 -Rate 0 -Width 120 -Columns $columns |
            Should -BeExactly '|   Work: Waiting for the child process |############-------------------|  [40%]      4/10 in 10.0s (0.00/s)            '
        Format-TpmProgressLine -Title 'Scanning' -Stage 'Abandoned before completion' -Current 0 -Total 4 -State Error -Rate 0 -Width 120 -Columns $columns |
            Should -BeExactly 'X  Scanning: Abandoned before completion |------------------------------X|   [0%]   (!) 0/4 in 0.0s (0.00/s) FAILED     '
        InModuleScope TpmProgress {
            $shared = @{
                Current = 4; Total = 10; ElapsedSeconds = 10; Rate = 0; Width = 120; DescriptionWidth = 35; CountWidth = 9; PercentWidth = 6; TimeWidth = 17
                Columns = @('Spinner', 'Description', 'Bar', 'Percentage', 'Count', 'Elapsed', 'Remaining')
            }
            (@(Format-TpmProgressSegments -Title 'Work' -Stage 'Waiting for the child process' @shared) | ForEach-Object { $_.Text }) -join '' |
                Should -BeExactly '| Work: Waiting for the child process |############--------------------|  [40%]      4/10 in 10.0s (0.00/s)             '
            (@(Format-TpmProgressSegments -Title 'Work' -Stage 'Copy' @shared) | ForEach-Object { $_.Text }) -join '' |
                Should -BeExactly '|                          Work: Copy |############--------------------|  [40%]      4/10 in 10.0s (0.00/s)             '
        }
    }

    It 'sanitizes control and non-ASCII characters in labels' {
        $line = Format-TpmProgressLine -Title 'Scan' -Stage ("Caf" + [char]0xE9 + "`r`nX") -Current 1 -Total 2 -Width 80
        $line | Should -Not -Match "[^\x20-\x7E]"
    }
}

Describe 'ASCII and glyph modes' {
    BeforeEach { Set-RendererDefaultMocks }

    It 'uses only printable ASCII in ASCII mode' {
        $line = Format-TpmProgressLine -Title 'Scan' -Stage 'Fixture' -Current 5 -Total 10 -ElapsedSeconds 3 -Width 100 -Style Ascii
        $line | Should -Not -Match '[^\x20-\x7E]'
        $line | Should -Match '\|#+-+\|'
    }

    It 'uses framed blocks with a tiny-dot track in glyph mode' {
        # The block look is the TPM_PROGRESS_BAR_STYLE default; clear an inherited 'line' setting (review: environment dependence).
        $savedBarStyle = $env:TPM_PROGRESS_BAR_STYLE
        try {
            $env:TPM_PROGRESS_BAR_STYLE = $null
            $line = Format-TpmProgressLine -Title 'Scan' -Stage 'Fixture' -Current 5 -Total 10 -ElapsedSeconds 3 -Width 100 -Style Unicode
            $line | Should -Match ('\|' + $script:glyphFill + '+' + $script:glyphHalf + '?' + [string][char]0x00B7 + '+\|')
            $line.Length | Should -Be 100
        } finally { $env:TPM_PROGRESS_BAR_STYLE = $savedBarStyle }
    }

    It 'uses the cross glyph for errors while retaining readable ASCII text' {
        $line = Format-TpmProgressLine -Title 'Scan' -Stage 'Fixture' -Current 5 -Total 10 -ElapsedSeconds 3 -Width 100 -Style Unicode -State Error
        $line.Contains([string][char]0x2717) | Should -BeTrue
        $line | Should -Match 'FAILED'
    }

    It 'builds bars of exactly the requested cell width in both styles, known and unknown totals' {
        foreach ($style in @('Ascii', 'Unicode')) {
            foreach ($width in @(8, 10, 20, 32)) {
                (Format-TpmProgressBar -Current 3 -Total 10 -BarWidth $width -Style $style).Length | Should -Be $width
                (Format-TpmProgressBar -Current 0 -Total 0 -BarWidth $width -Style $style -Tick 5).Length | Should -Be $width
            }
        }
    }

    It 'marks the boundary with a fractional block and never draws a full bar while running' {
        # The block look is the TPM_PROGRESS_BAR_STYLE default; clear an inherited 'line' setting (review: environment dependence).
        $savedBarStyle = $env:TPM_PROGRESS_BAR_STYLE
        try {
            $env:TPM_PROGRESS_BAR_STYLE = $null
            $bar = Format-TpmProgressBar -Current 5 -Total 10 -BarWidth 21 -Style Unicode
            $bar.Length | Should -Be 21
            $bar | Should -Be ('|' + ($script:glyphFill * 9) + $script:glyphHalf + ([string][char]0x00B7 * 9) + '|')
            $running = Format-TpmProgressBar -Current 10 -Total 10 -BarWidth 21 -State Running -Style Unicode
            $running.Length | Should -Be 21
            $running | Should -Not -Be ('|' + ($script:glyphFill * 19) + '|')
            $final = Format-TpmProgressBar -Current 10 -Total 10 -BarWidth 21 -State Final -Style Unicode
            $final | Should -Be ('|' + ($script:glyphFill * 19) + '|')
        } finally { $env:TPM_PROGRESS_BAR_STYLE = $savedBarStyle }
    }

    It 'keeps the ASCII bar free of the half cell' {
        (Format-TpmProgressBar -Current 5 -Total 10 -BarWidth 12 -Style Ascii) | Should -Be '|#####-----|'
    }

    It 'resolves the style from TPM_PROGRESS_STYLE, forcing either, and from verification when auto' {
        $saved = $env:TPM_PROGRESS_STYLE
        try {
            $env:TPM_PROGRESS_STYLE = 'ascii'
            Get-TpmProgressStyle | Should -Be 'Ascii'
            $env:TPM_PROGRESS_STYLE = 'unicode'
            Get-TpmProgressStyle | Should -Be 'Unicode'
            $env:TPM_PROGRESS_STYLE = 'glyph'
            Get-TpmProgressStyle | Should -Be 'Unicode'
            $env:TPM_PROGRESS_STYLE = 'block'
            Get-TpmProgressStyle | Should -Be 'Block'
            # Auto: the answer depends on the console, so both gates are mocked (the solid-bar gate used to be left to the real console,
            # which made this test pass redirected and fail in a real console window). Fix105.ProgressBars.Tests.ps1 covers the gate itself.
            $env:TPM_PROGRESS_STYLE = 'auto'
            Mock Test-TpmProgressUnicodeVerified { $false } -ModuleName TpmProgress
            Mock Test-TpmProgressBlockBarUsable { $false } -ModuleName TpmProgress
            Get-TpmProgressStyle | Should -Be 'Ascii'
            Mock Test-TpmProgressBlockBarUsable { $true } -ModuleName TpmProgress
            Get-TpmProgressStyle | Should -Be 'Block'
            Mock Test-TpmProgressUnicodeVerified { $true } -ModuleName TpmProgress
            Mock Test-TpmProgressBlockBarUsable { $false } -ModuleName TpmProgress
            Get-TpmProgressStyle | Should -Be 'Unicode'
            $env:TPM_PROGRESS_STYLE = $null
            Mock Test-TpmProgressUnicodeVerified { $false } -ModuleName TpmProgress
            Get-TpmProgressStyle | Should -Be 'Ascii'
            Mock Test-TpmProgressBlockBarUsable { $true } -ModuleName TpmProgress
            Get-TpmProgressStyle | Should -Be 'Block'
        } finally { $env:TPM_PROGRESS_STYLE = $saved }
    }

    It 'applies the glyph detection rule: redirected, UTF-16 write or UTF-8 encoding, and host/font verification' {
        $savedWt = $env:WT_SESSION; $savedTerm = $env:TERM_PROGRAM
        try {
            $env:WT_SESSION = $null; $env:TERM_PROGRAM = $null
            Mock Test-TpmProgressOutputRedirected { $true } -ModuleName TpmProgress
            Mock Test-TpmProgressWideWriteAvailable { $true } -ModuleName TpmProgress
            Mock Get-TpmProgressOutputCodePage { 437 } -ModuleName TpmProgress
            Mock Test-TpmProgressConhostFont { $true } -ModuleName TpmProgress
            # FIX10: the measured cell probe is the last gate; this test covers the rules before it.
            Mock Test-TpmProgressGlyphCells { $true } -ModuleName TpmProgress
            # Redirected output never gets glyphs.
            (InModuleScope TpmProgress { Test-TpmProgressUnicodeVerified }) | Should -BeFalse
            Mock Test-TpmProgressOutputRedirected { $false } -ModuleName TpmProgress
            # Classic conhost with a verified TrueType font: glyphs, even on an OEM code page, because frames are written as UTF-16.
            (InModuleScope TpmProgress { Test-TpmProgressUnicodeVerified }) | Should -BeTrue
            # Legacy raster or unknown font: ASCII.
            Mock Test-TpmProgressConhostFont { $false } -ModuleName TpmProgress
            (InModuleScope TpmProgress { Test-TpmProgressUnicodeVerified }) | Should -BeFalse
            # Windows Terminal and the VS Code terminal are verified without a font probe.
            $env:WT_SESSION = 'fixture-session'
            (InModuleScope TpmProgress { Test-TpmProgressUnicodeVerified }) | Should -BeTrue
            $env:WT_SESSION = $null; $env:TERM_PROGRAM = 'vscode'
            (InModuleScope TpmProgress { Test-TpmProgressUnicodeVerified }) | Should -BeTrue
            # Without the UTF-16 write path the output encoding must be UTF-8.
            $env:TERM_PROGRAM = $null; $env:WT_SESSION = 'fixture-session'
            Mock Test-TpmProgressWideWriteAvailable { $false } -ModuleName TpmProgress
            (InModuleScope TpmProgress { Test-TpmProgressUnicodeVerified }) | Should -BeFalse
            Mock Get-TpmProgressOutputCodePage { 65001 } -ModuleName TpmProgress
            (InModuleScope TpmProgress { Test-TpmProgressUnicodeVerified }) | Should -BeTrue
        } finally { $env:WT_SESSION = $savedWt; $env:TERM_PROGRAM = $savedTerm }
    }

    It 'reports every input of the style decision for the preview and support evidence' {
        $saved = $env:TPM_PROGRESS_STYLE
        try {
            $env:TPM_PROGRESS_STYLE = $null
            Mock Test-TpmProgressOutputRedirected { $true } -ModuleName TpmProgress
            $capabilities = Get-TpmProgressCapabilities
            $capabilities.Redirected | Should -BeTrue
            $capabilities.WideWrite | Should -BeFalse
            $capabilities.ConhostFont | Should -BeFalse
            $capabilities.Style | Should -Be 'Ascii'
            $capabilities.ColorMode | Should -BeExactly 'None'
        } finally { $env:TPM_PROGRESS_STYLE = $saved }
    }

    It 'never reports color for redirected output, NO_COLOR, TPM_PROGRESS_COLOR=off or TERM=dumb' {
        $savedNoColor = $env:NO_COLOR; $savedColor = $env:TPM_PROGRESS_COLOR; $savedTerm = $env:TERM
        try {
            $env:NO_COLOR = $null; $env:TPM_PROGRESS_COLOR = $null; $env:TERM = $null
            Mock Test-TpmProgressOutputRedirected { $false } -ModuleName TpmProgress
            Test-TpmProgressColorEnabled | Should -BeTrue
            $env:NO_COLOR = '1'
            Test-TpmProgressColorEnabled | Should -BeFalse
            $env:NO_COLOR = $null; $env:TPM_PROGRESS_COLOR = 'off'
            Test-TpmProgressColorEnabled | Should -BeFalse
            $env:TPM_PROGRESS_COLOR = $null; $env:TERM = 'dumb'
            Test-TpmProgressColorEnabled | Should -BeFalse
            $env:TERM = $null
            Mock Test-TpmProgressOutputRedirected { $true } -ModuleName TpmProgress
            Test-TpmProgressColorEnabled | Should -BeFalse
        } finally { $env:NO_COLOR = $savedNoColor; $env:TPM_PROGRESS_COLOR = $savedColor; $env:TERM = $savedTerm }
    }

    It 'maps bar fill to the state color and the unfilled track to dark gray' {
        InModuleScope TpmProgress {
            Get-TpmProgressSegmentColor -Role 'fill' -State 'Running' | Should -Be 'Cyan'
            Get-TpmProgressSegmentColor -Role 'fill' -State 'Final' | Should -Be 'Green'
            Get-TpmProgressSegmentColor -Role 'fill' -State 'Error' | Should -Be 'Red'
            Get-TpmProgressSegmentColor -Role 'fill' -State 'Cancelled' | Should -Be 'Yellow'
            Get-TpmProgressSegmentColor -Role 'rest' -State 'Running' | Should -Be 'DarkGray'
        }
    }
}

Describe 'Percent rules' {
    BeforeEach { Set-RendererDefaultMocks }

    It 'never reports 100 percent for running, failed, canceled or stalled work' {
        foreach ($state in @('Running', 'Error', 'Cancelled', 'Stalled')) {
            Get-TpmProgressPercent -Current 10 -Total 10 -State $state | Should -Be 99
        }
    }

    It 'reports 100 percent only for a Final close with every unit finished' {
        Get-TpmProgressPercent -Current 10 -Total 10 -State Final | Should -Be 100
        Get-TpmProgressPercent -Current 9 -Total 10 -State Final | Should -Be 90
    }

    It 'floors, clamps and reports unknown totals as no percent' {
        Get-TpmProgressPercent -Current 1 -Total 3 -State Running | Should -Be 33
        Get-TpmProgressPercent -Current 0 -Total 10 -State Running | Should -Be 0
        Get-TpmProgressPercent -Current 99 -Total 10 -State Running | Should -Be 99
        Get-TpmProgressPercent -Current -4 -Total 10 -State Running | Should -Be 0
        Get-TpmProgressPercent -Current 5 -Total 0 -State Running | Should -Be -1
        Get-TpmProgressPercent -Current 5 -Total 0 -State Final | Should -Be -1
    }

    It 'prints 99 percent, not 100, for a running line whose counts are all finished' {
        $line = Format-TpmProgressLine -Title 'Verify' -Stage 'Fixture' -Current 10 -Total 10 -State Running -ElapsedSeconds 5 -Width 100
        $line | Should -Match '\[99%\]'
        $line | Should -Not -Match '100%'
        $line | Should -Match '\|#+-\|'
    }

    It 'prints 100 percent and done only when closed Final' {
        $line = Format-TpmProgressLine -Title 'Verify' -Stage 'Fixture' -Current 10 -Total 10 -State Final -ElapsedSeconds 5 -Width 100
        $line | Should -Match '100%'
        $line | Should -Match 'done'
        # FIX105: the old ASCII "+" status mark after "done" is gone; the word says it.
        $line | Should -Match '^\s+Verify: Fixture'
        $line | Should -Not -Match '\+'
        $line | Should -Match '\|#{10,}\|'
    }

    It 'shows the real count and a real percent when Final closes short of the total' {
        $line = Format-TpmProgressLine -Title 'Verify' -Stage 'Fixture' -Current 8 -Total 10 -State Final -ElapsedSeconds 5 -Width 100
        $line | Should -Match '\[80%\]'
        $line | Should -Not -Match '100%'
    }
}

Describe 'Unknown total' {
    BeforeEach { Set-RendererDefaultMocks }

    It 'shows a spinner and the count with no percent, bar fill, or ETA' {
        $line = Format-TpmProgressLine -Title 'Scan' -Stage 'Discovery' -Current 17 -Total 0 -ElapsedSeconds 30 -EtaSeconds 12 -Width 100
        $line | Should -Not -Match '%'
        $line | Should -Not -Match 'ETA'
        $line | Should -Match '\s17(\s|$)'
        $line | Should -Not -Match '17/'
        $line | Should -Match '\|>+-*\|'
    }

    It 'rotates the spinner through four ASCII frames' {
        $frames = foreach ($tick in 0..3) { (Format-TpmProgressLine -Title 'Scan' -Stage 'X' -Current 1 -Total 0 -Width 60 -Tick $tick).Substring(0, 1) }
        ($frames -join '') | Should -Be '|/-\'
    }

    It 'moves the marker across the track as the tick advances' {
        (Format-TpmProgressBar -Current 0 -Total 0 -BarWidth 20 -Tick 0) | Should -Not -Be (Format-TpmProgressBar -Current 0 -Total 0 -BarWidth 20 -Tick 6)
    }

    It 'closes without a marker or a percent' {
        $line = Format-TpmProgressLine -Title 'Scan' -Stage 'Discovery' -Current 17 -Total 0 -State Final -ElapsedSeconds 30 -Width 100
        $line | Should -Not -Match '%'
        $line | Should -Not -Match '[<>]'
        $line | Should -Match 'done'
    }

    It 'keeps the count when the window is too narrow for the bar' {
        $line = Format-TpmProgressLine -Title 'Scan' -Stage 'Discovery' -Current 17 -Total 0 -ElapsedSeconds 30 -Width 30
        $line.Length | Should -Be 30
        $line | Should -Match '17'
    }
}

Describe 'ETA rules' {
    BeforeEach { Set-RendererDefaultMocks }

    It 'stays hidden until three samples and three seconds exist' {
        Get-TpmProgressEta -Current 2 -Total 20 -StartCurrent 0 -ElapsedSeconds 10 -Samples 2 | Should -Be -1
        Get-TpmProgressEta -Current 3 -Total 20 -StartCurrent 0 -ElapsedSeconds 2.9 -Samples 3 | Should -Be -1
    }

    It 'stays hidden with an unknown total, nothing left, or no measurable progress' {
        Get-TpmProgressEta -Current 5 -Total 0 -StartCurrent 0 -ElapsedSeconds 10 -Samples 5 | Should -Be -1
        Get-TpmProgressEta -Current 20 -Total 20 -StartCurrent 0 -ElapsedSeconds 10 -Samples 5 | Should -Be -1
        Get-TpmProgressEta -Current 4 -Total 20 -StartCurrent 4 -ElapsedSeconds 10 -Samples 5 | Should -Be -1
    }

    It 'extrapolates the average rate since the stage started' {
        Get-TpmProgressEta -Current 10 -Total 20 -StartCurrent 0 -ElapsedSeconds 10 -Samples 5 | Should -Be 10
        Get-TpmProgressEta -Current 15 -Total 20 -StartCurrent 5 -ElapsedSeconds 10 -Samples 5 | Should -Be 5
    }

    It 'formats durations as m:ss and h:mm:ss and hides invalid values' {
        Format-TpmProgressDuration -Seconds 7 | Should -Be '0:07'
        Format-TpmProgressDuration -Seconds 75 | Should -Be '1:15'
        Format-TpmProgressDuration -Seconds 3725 | Should -Be '1:02:05'
        Format-TpmProgressDuration -Seconds -1 | Should -Be '--:--'
    }

    It 'formats sizes scaled to the total and items as padded counts' {
        Format-TpmProgressCount -Current 12582912 -Total 20971520 -Unit Bytes | Should -Be '12.0/20.0 MB'
        Format-TpmProgressCount -Current 2048 -Total 0 -Unit Bytes | Should -Be '2.0 KB'
        Format-TpmProgressCount -Current 5 -Total 120 | Should -Be '  5/120'
        Format-TpmProgressCount -Current 5 -Total 0 | Should -Be '5'
    }

    It 'floors sizes and never shows equal figures before the work is done (review MAJOR-1)' {
        # 99.99995 percent of 20 MB must not read 20.0/20.0.
        Format-TpmProgressCount -Current 20971519 -Total 20971520 -Unit Bytes | Should -Be '19.9/20.0 MB'
        # Equal at one decimal: more decimals separate them.
        Format-TpmProgressCount -Current 21000000 -Total 21010000 -Unit Bytes | Should -Be '20.02/20.03 MB'
        # Equal at every precision: raw bytes.
        Format-TpmProgressCount -Current 104857600 -Total 104857601 -Unit Bytes | Should -Be '104857600/104857601 B'
        # A finished size may show equal figures.
        Format-TpmProgressCount -Current 20971520 -Total 20971520 -Unit Bytes | Should -Be '20.0/20.0 MB'
        # A 0.6 MB file at 0.51 MB shows KB figures and never rounds up to "1/1".
        Format-TpmProgressCount -Current 534773 -Total 629146 -Unit Bytes | Should -Be '522.2/614.4 KB'
    }

    It 'summarizes for the status footer with the same percent, count, elapsed and ETA wording' {
        Format-TpmProgressSummary -Current 12582912 -Total 20971520 -Unit Bytes -ElapsedSeconds 12 -EtaSeconds 8 | Should -Be '60%  12.0/20.0 MB  0:12  ETA 0:08'
        Format-TpmProgressSummary -Current 12582912 -Total 0 -Unit Bytes -ElapsedSeconds 12 | Should -Be '12.0 MB  0:12'
    }
}

Describe 'Failure and cancel closes' {
    BeforeEach { Set-RendererDefaultMocks }

    It 'closes Error with the FAILED word and never 100 percent, even when every count was finished' {
        # The shipped default columns (Get-TpmProgressDefaultColumns, FIX17B) put the Spinner column last; this file's
        # per-test mock puts it first, so the shipped default is passed explicitly here.
        $line = Format-TpmProgressLine -Title 'Backup' -Stage 'Fixture' -Current 10 -Total 10 -State Error -ElapsedSeconds 4 -Width 100 -Columns @('Description', 'Bar', 'Count', 'Percentage', 'Elapsed', 'Remaining', 'Spinner')
        $line | Should -Match 'FAILED'
        $line | Should -Not -Match '100%'
        # The default Spinner column is last: the line ends with the terminal error icon.
        $line.TrimEnd() | Should -MatchExactly ' X$'
        $line | Should -Match '\[99%\]'
    }

    It 'keeps the state word at every width, dropping other columns first' {
        foreach ($case in @(@('Error', 'FAILED'), @('Cancelled', 'canceled'), @('Stalled', 'stalled'))) {
            foreach ($width in @(100, 70, 60, 50, 40, 30, 28)) {
                $line = Format-TpmProgressLine -Title 'Backup' -Stage 'Fixture' -Current 4 -Total 10 -State $case[0] -ElapsedSeconds 4 -Width $width
                $line.Length | Should -Be $width
                $line | Should -Match $case[1]
            }
        }
    }

    It 'still says FAILED in the label column when the window is too narrow for any column' {
        (Format-TpmProgressLine -Title 'Backup' -Stage 'Fixture' -Current 4 -Total 10 -State Error -Width 18) | Should -Match 'FAILED'
    }
}

Describe 'Stateful renderer: redirected output prints plain periodic lines' {
    BeforeEach {
        Set-RendererDefaultMocks
        $global:TpmUiNow = [datetime]'2026-01-01T00:00:00'
        $global:TpmUiLines = New-Object System.Collections.Generic.List[string]
        Mock Get-TpmProgressNow { $global:TpmUiNow } -ModuleName TpmProgress
        Mock Test-TpmProgressOutputRedirected { $true } -ModuleName TpmProgress
        Mock Test-TpmProgressColorEnabled { $false } -ModuleName TpmProgress
        Mock Get-TpmProgressStyle { 'Ascii' } -ModuleName TpmProgress
        Mock Write-TpmProgressPlainLine { [void]$global:TpmUiLines.Add($Text) } -ModuleName TpmProgress
        Mock Write-TpmProgressRaw { throw 'redirected output must not use the live console writer' } -ModuleName TpmProgress
    }
    AfterEach {
        Stop-TpmProgressAbandoned
        Remove-Variable -Name TpmUiNow, TpmUiLines -Scope Global -ErrorAction SilentlyContinue
    }

    It 'writes a line at start, on each 10 percent step, every 5 seconds, and once at close, all plain ASCII' {
        Start-TpmProgressOperation -Title 'Scan' -Stage 'Files' -Total 100 | Out-Null
        $global:TpmUiLines.Count | Should -Be 1
        Set-TpmProgressStage -Stage 'Files' -Current 1 -Total 100
        $global:TpmUiLines.Count | Should -Be 1
        Set-TpmProgressStage -Stage 'Files' -Current 10 -Total 100
        $global:TpmUiLines.Count | Should -Be 2
        $global:TpmUiNow = $global:TpmUiNow.AddSeconds(6)
        Set-TpmProgressStage -Stage 'Files' -Current 11 -Total 100
        $global:TpmUiLines.Count | Should -Be 3
        Complete-TpmProgressOperation -State Final
        $global:TpmUiLines.Count | Should -Be 4
        foreach ($line in $global:TpmUiLines) {
            $line | Should -Not -Match "[`r`n]"
            $line | Should -Not -Match '[^\x20-\x7E]'
            $line | Should -Not -Match '\s+$'
        }
        # FIX17B: a standalone Final close short of its known total (11/100 here) closes Incomplete, never done.
        $global:TpmUiLines[3] | Should -Match 'incomplete'
        Test-TpmProgressActive | Should -BeFalse
    }

    It 'shows the ETA only after three finished-count samples and three seconds' {
        Start-TpmProgressOperation -Title 'Scan' -Stage 'Files' -Total 10 | Out-Null
        foreach ($n in 1..3) {
            $global:TpmUiNow = $global:TpmUiNow.AddSeconds(1)
            Set-TpmProgressStage -Stage 'Files' -Current $n -Total 10
        }
        $global:TpmUiLines.Count | Should -Be 4
        $global:TpmUiLines[1] | Should -Not -Match 'ETA'
        $global:TpmUiLines[2] | Should -Not -Match 'ETA'
        $global:TpmUiLines[3] | Should -Match 'ETA 0:07'
        $global:TpmUiLines[3] | Should -Match '\[30%\]'
    }

    It 'restarts the stage clock and hides the ETA again when a new stage with a different total begins' {
        Start-TpmProgressOperation -Title 'Scan' -Stage 'First' -Total 10 | Out-Null
        foreach ($n in 1..3) {
            $global:TpmUiNow = $global:TpmUiNow.AddSeconds(1)
            Set-TpmProgressStage -Stage 'First' -Current $n -Total 10
        }
        Set-TpmProgressStage -Stage 'Second' -Current 0 -Total 50
        $global:TpmUiLines[$global:TpmUiLines.Count - 1] | Should -Match 'Second'
        $global:TpmUiLines[$global:TpmUiLines.Count - 1] | Should -Not -Match 'ETA'
        $global:TpmUiLines[$global:TpmUiLines.Count - 1] | Should -Match '\bin 0\.0s'
    }

    It 'closes Error as FAILED, not Final and not 100 percent' {
        Start-TpmProgressOperation -Title 'Backup' -Stage 'Files' -Total 4 | Out-Null
        Set-TpmProgressStage -Stage 'Files' -Current 4 -Total 4
        Complete-TpmProgressOperation -State Error
        $last = $global:TpmUiLines[$global:TpmUiLines.Count - 1]
        $last | Should -Match 'FAILED'
        $last | Should -Not -Match '100%'
        Test-TpmProgressActive | Should -BeFalse
    }

    It 'keeps a recorded failure when the owner later closes Final' {
        Start-TpmProgressOperation -Title 'Backup' -Stage 'Files' -Total 4 | Out-Null
        Register-TpmProgressOutcome -State Error
        Complete-TpmProgressOperation -State Final
        $global:TpmUiLines[$global:TpmUiLines.Count - 1] | Should -Match 'FAILED'
    }

    It 'closes a canceled operation as canceled' {
        Start-TpmProgressOperation -Title 'Backup' -Stage 'Files' -Total 4 | Out-Null
        Complete-TpmProgressOperation -State Cancelled
        $global:TpmUiLines[$global:TpmUiLines.Count - 1] | Should -Match 'canceled'
    }

    It 'closes an abandoned operation as Error' {
        Start-TpmProgressOperation -Title 'Backup' -Stage 'Files' -Total 4 | Out-Null
        Stop-TpmProgressAbandoned
        $global:TpmUiLines[$global:TpmUiLines.Count - 1] | Should -Match 'FAILED'
        Test-TpmProgressActive | Should -BeFalse
    }

    It 'closes a stage that a new stage replaced without a result as incomplete, never done' {
        Start-TpmProgressOperation -Title 'Backup' -Stage 'Files' -Total 10 | Out-Null
        Set-TpmProgressStage -Stage 'Files' -Current 4 -Total 10
        Complete-TpmProgressOperation -State Final -Superseded
        $last = $global:TpmUiLines[$global:TpmUiLines.Count - 1]
        $last | Should -Match 'incomplete'
        $last | Should -Not -Match 'done'
        $last | Should -Not -Match '100%'
        $last | Should -Match '^! '
    }

    It 'still closes a replaced stage Final when its total was reached or was never known' {
        Start-TpmProgressOperation -Title 'Backup' -Stage 'Files' -Total 10 | Out-Null
        Set-TpmProgressStage -Stage 'Files' -Current 10 -Total 10
        Complete-TpmProgressOperation -State Final -Superseded
        $global:TpmUiLines[$global:TpmUiLines.Count - 1] | Should -Match 'done'
        Start-TpmProgressOperation -Title 'Scan' -Stage 'Discovery' | Out-Null
        Complete-TpmProgressOperation -State Final -Superseded
        $global:TpmUiLines[$global:TpmUiLines.Count - 1] | Should -Match 'done'
    }
}

Describe 'Stateful renderer: group ownership and nesting' {
    BeforeEach {
        Set-RendererDefaultMocks
        $global:TpmUiNow = [datetime]'2026-01-01T00:00:00'
        $global:TpmUiLines = New-Object System.Collections.Generic.List[string]
        Mock Get-TpmProgressNow { $global:TpmUiNow } -ModuleName TpmProgress
        Mock Test-TpmProgressOutputRedirected { $true } -ModuleName TpmProgress
        Mock Test-TpmProgressColorEnabled { $false } -ModuleName TpmProgress
        Mock Get-TpmProgressStyle { 'Ascii' } -ModuleName TpmProgress
        Mock Write-TpmProgressPlainLine { [void]$global:TpmUiLines.Add($Text) } -ModuleName TpmProgress
    }
    AfterEach {
        Stop-TpmProgressAbandoned
        Remove-Variable -Name TpmUiNow, TpmUiLines -Scope Global -ErrorAction SilentlyContinue
    }

    It 'keeps one group bar open across leaf stages and leaf completions' {
        Start-TpmProgressOperation -Title 'Games' -Group | Out-Null
        Test-TpmProgressGroupOwned | Should -BeTrue
        Set-TpmProgressStage -Stage 'Scan files' -Current 3 -Total 10
        $global:TpmUiLines[$global:TpmUiLines.Count - 1] | Should -Match '^\S\s+Games: Scan files'
        $global:TpmUiLines[$global:TpmUiLines.Count - 1] | Should -Match '\[30%\]'
        $global:TpmUiLines[$global:TpmUiLines.Count - 1] | Should -Match '3/10'
        Set-TpmProgressStage -Stage 'Scan files done' -StageOnly
        Test-TpmProgressActive | Should -BeTrue
        (Get-TpmProgressState).Total | Should -Be 10
    }

    It 'nested starts only deepen; only the outermost Final close ends the group' {
        $group = Start-TpmProgressOperation -Title 'Workflow' -Group
        $nested = Start-TpmProgressOperation -Title 'Scanning' -Stage 'Inner'
        [object]::ReferenceEquals($group, $nested) | Should -BeTrue
        (Get-TpmProgressState).Depth | Should -Be 2
        Complete-TpmProgressOperation -State Final
        Test-TpmProgressActive | Should -BeTrue
        (Get-TpmProgressState).Depth | Should -Be 1
        Complete-TpmProgressOperation -State Final
        Test-TpmProgressActive | Should -BeFalse
    }

    It 'keeps the parent open on a nested Error and closes it FAILED only when the owner closes (FIX10 MAJOR 1)' {
        Start-TpmProgressOperation -Title 'Workflow' -Group | Out-Null
        Start-TpmProgressOperation -Title 'Scanning' -Stage 'Inner' | Out-Null
        Complete-TpmProgressOperation -State Error
        Test-TpmProgressActive | Should -BeTrue
        (Get-TpmProgressState).Depth | Should -Be 1
        (Get-TpmProgressState).Outcome | Should -Be 'Error'
        # Upper-case FAILED is the closing word; the running "Scanning failed" note on the parent is not a close.
        @($global:TpmUiLines | Where-Object { $_ -cmatch 'FAILED' }).Count | Should -Be 0
        Complete-TpmProgressOperation -State Final
        Test-TpmProgressActive | Should -BeFalse
        $global:TpmUiLines[$global:TpmUiLines.Count - 1] | Should -Match '^X\s+Workflow'
        $global:TpmUiLines[$global:TpmUiLines.Count - 1] | Should -Match 'FAILED'
    }

    It 'a group never adopts an open standalone operation: it closes that one as FAILED first' {
        # The redirected default width (79): the closing line keeps the whole abandoned note (FIX27: the elapsed/rate
        # column gives way to it) and the FAILED word.
        Start-TpmProgressOperation -Title 'Scanning' -Stage 'Standalone' -Total 4 | Out-Null
        Start-TpmProgressOperation -Title 'Workflow' -Group | Out-Null
        ($global:TpmUiLines | Where-Object { $_ -match 'Scanning: Abandoned before completion' -and $_ -match 'FAILED' }).Count | Should -Be 1
        Test-TpmProgressGroupOwned | Should -BeTrue
    }

    It 'closes a successful group as a full verified bar with no leftover leaf count' {
        Start-TpmProgressOperation -Title 'Games' -Group | Out-Null
        Set-TpmProgressStage -Stage 'Scan files' -Current 3 -Total 10
        Complete-TpmProgressOperation -State Final
        $last = $global:TpmUiLines[$global:TpmUiLines.Count - 1]
        $last | Should -Match '^\s+Games'
        $last | Should -Not -Match '\+'
        $last | Should -Match '100%'
        $last | Should -Match 'done'
        $last | Should -Not -Match 'Scan files'
        $last | Should -Not -Match '\d/\d'
    }

    It 'closes a failed group with no percent and the FAILED word' {
        Start-TpmProgressOperation -Title 'Games' -Group | Out-Null
        Set-TpmProgressStage -Stage 'Scan files' -Current 3 -Total 10
        Register-TpmProgressOutcome -State Error
        Complete-TpmProgressOperation -State Final
        $last = $global:TpmUiLines[$global:TpmUiLines.Count - 1]
        $last | Should -Match '^X\s+Games'
        $last | Should -Match 'FAILED'
        $last | Should -Not -Match '%'
    }
}

Describe 'Stateful renderer: live console behavior' {
    BeforeEach {
        Set-RendererDefaultMocks
        $global:TpmUiNow = [datetime]'2026-01-01T00:00:00'
        $global:TpmUiWidth = 80
        $global:TpmUiCursorLeft = 0
        Mock Get-TpmProgressNow { $global:TpmUiNow } -ModuleName TpmProgress
        # Frame cost (adaptive throttle) is measured on the monotonic clock; keep it at 0 so the 100 ms floor applies.
        Mock Get-TpmProgressTimestamp { 0 } -ModuleName TpmProgress
        Mock Test-TpmProgressOutputRedirected { $false } -ModuleName TpmProgress
        Mock Test-TpmProgressColorEnabled { $false } -ModuleName TpmProgress
        Mock Get-TpmProgressStyle { 'Ascii' } -ModuleName TpmProgress
        Mock Get-TpmProgressWidth { $global:TpmUiWidth } -ModuleName TpmProgress
        Mock Get-TpmProgressCursor { [pscustomobject]@{ Left = $global:TpmUiCursorLeft; Top = 7 } } -ModuleName TpmProgress
        Mock Write-TpmProgressRaw {} -ModuleName TpmProgress
        Mock Get-TpmProgressBufferWidth { $global:TpmUiWidth + 1 } -ModuleName TpmProgress
        Mock Get-TpmProgressWindowHeight { 30 } -ModuleName TpmProgress
        Mock Get-TpmProgressBackground { 'Black' } -ModuleName TpmProgress
        Mock Clear-TpmProgressCells { $true } -ModuleName TpmProgress
        Mock Set-TpmProgressCursor { $true } -ModuleName TpmProgress
    }
    AfterEach {
        Stop-TpmProgressAbandoned
        Remove-Variable -Name TpmUiNow, TpmUiWidth, TpmUiCursorLeft, TpmUiRaw -Scope Global -ErrorAction SilentlyContinue
    }

    It 'redraws one in-place line with a carriage return, no newline, until the operation closes' {
        Start-TpmProgressOperation -Title 'Scan' -Stage 'Files' -Total 10 | Out-Null
        $global:TpmUiNow = $global:TpmUiNow.AddSeconds(1)
        Set-TpmProgressStage -Stage 'Files' -Current 2 -Total 10
        # Each frame is one write that starts with the carriage return.
        Should -Invoke Write-TpmProgressRaw -ModuleName TpmProgress -ParameterFilter { $Text -like "`r*" } -Times 2 -Exactly
        Should -Invoke Write-TpmProgressRaw -ModuleName TpmProgress -ParameterFilter { $NewLine -or $Text -match "`n" } -Times 0 -Exactly
        Complete-TpmProgressOperation -State Final
        Should -Invoke Write-TpmProgressRaw -ModuleName TpmProgress -ParameterFilter { $NewLine -or $Text -match "`n" } -Times 1 -Exactly
        Should -Invoke Write-TpmProgressRaw -ModuleName TpmProgress -ParameterFilter { $Text -like "`r*`r`n" } -Times 1 -Exactly
    }

    It 'throttles rapid updates so a tight loop does not flood the console' {
        Start-TpmProgressOperation -Title 'Scan' -Stage 'Files' -Total 1000 | Out-Null
        foreach ($n in 1..50) {
            $global:TpmUiNow = $global:TpmUiNow.AddMilliseconds(1)
            Set-TpmProgressStage -Stage 'Files' -Current $n -Total 1000
        }
        Should -Invoke Write-TpmProgressRaw -ModuleName TpmProgress -ParameterFilter { $Text -like "`r*" } -Times 1 -Exactly
    }

    It 'redraws in place after a width change, blanking the old frame first instead of leaving a row behind' {
        Start-TpmProgressOperation -Title 'Scan' -Stage 'Files' -Total 10 | Out-Null
        $global:TpmUiWidth = 50
        $global:TpmUiNow = $global:TpmUiNow.AddSeconds(1)
        Set-TpmProgressStage -Stage 'Files' -Current 2 -Total 10
        Should -Invoke Clear-TpmProgressCells -ModuleName TpmProgress -ParameterFilter { $Top -eq 7 } -Times 1 -Exactly
        Should -Invoke Set-TpmProgressCursor -ModuleName TpmProgress -ParameterFilter { $Left -eq 0 -and $Top -eq 7 } -Times 1 -Exactly
        Should -Invoke Write-TpmProgressRaw -ModuleName TpmProgress -ParameterFilter { $Text -like "`n`r*" } -Times 0 -Exactly
    }

    It 'starts a fresh line after a width change when the old frame cannot be blanked and the cursor is mid-line' {
        $global:TpmUiCursorLeft = 40
        Mock Clear-TpmProgressCells { $false } -ModuleName TpmProgress
        Start-TpmProgressOperation -Title 'Scan' -Stage 'Files' -Total 10 | Out-Null
        $global:TpmUiWidth = 50
        $global:TpmUiNow = $global:TpmUiNow.AddSeconds(1)
        Set-TpmProgressStage -Stage 'Files' -Current 2 -Total 10
        # One fresh line for the first frame (the cursor was mid-line) and one for the frame after the resize.
        Should -Invoke Write-TpmProgressRaw -ModuleName TpmProgress -ParameterFilter { $Text -like "`n`r*" } -Times 2 -Exactly
    }

    It 'starts a fresh line when other output moved the cursor mid-line, and not when it is at column 0' {
        Start-TpmProgressOperation -Title 'Scan' -Stage 'Files' -Total 10 | Out-Null
        $global:TpmUiCursorLeft = 12
        $global:TpmUiNow = $global:TpmUiNow.AddSeconds(1)
        Set-TpmProgressStage -Stage 'Files' -Current 2 -Total 10
        Should -Invoke Write-TpmProgressRaw -ModuleName TpmProgress -ParameterFilter { $Text -like "`n`r*" } -Times 1 -Exactly
        $global:TpmUiCursorLeft = 0
        $global:TpmUiNow = $global:TpmUiNow.AddSeconds(1)
        Set-TpmProgressStage -Stage 'Files' -Current 3 -Total 10
        Should -Invoke Write-TpmProgressRaw -ModuleName TpmProgress -ParameterFilter { $Text -like "`n`r*" } -Times 1 -Exactly
    }


    It 'excludes time spent at a prompt from the stage elapsed time' {
        Start-TpmProgressOperation -Title 'Scan' -Stage 'Files' -Total 10 | Out-Null
        Suspend-TpmProgressLine
        $global:TpmUiNow = $global:TpmUiNow.AddSeconds(30)
        Resume-TpmProgressLine
        Set-TpmProgressStage -Stage 'Files' -Current 1 -Total 10
        # The 30 seconds were spent at a prompt, not in the stage: no frame may show them as elapsed time.
        Should -Invoke Write-TpmProgressRaw -ModuleName TpmProgress -ParameterFilter { $Text -match '\bin 30\.0s' } -Times 0 -Exactly
        Should -Invoke Write-TpmProgressRaw -ModuleName TpmProgress -ParameterFilter { $Text -match '\bin 0\.0s' } -Times 2 -Exactly
    }

    It 'never writes a frame wider than the window while resizing narrower and wider' {
        $global:TpmUiRaw = New-Object System.Text.StringBuilder
        Mock Write-TpmProgressRaw { [void]$global:TpmUiRaw.Append($Text) } -ModuleName TpmProgress
        Start-TpmProgressOperation -Title 'Scan' -Stage 'Files' -Total 10 | Out-Null
        $widths = @(120, 79, 59, 40, 25, 15, 79)
        foreach ($width in $widths) {
            $global:TpmUiWidth = $width
            $global:TpmUiNow = $global:TpmUiNow.AddSeconds(1)
            Set-TpmProgressStage -Stage 'Files' -Current 3 -Total 10
        }
        # Frames are introduced by a carriage return; after a width change the old frame is blanked and redrawn in place.
        $frames = @($global:TpmUiRaw.ToString() -split "`r" | Where-Object { $_ -ne '' } | ForEach-Object { $_.TrimEnd("`n") })
        $frames.Count | Should -Be 8
        $expected = @(80) + $widths
        for ($i = 0; $i -lt $frames.Count; $i++) { $frames[$i].Length | Should -Be $expected[$i] }
    }
}

Describe 'Plain-line request' {
    BeforeEach { Set-RendererDefaultMocks }

    It 'TPM_PROGRESS_PLAIN=1 forces the redirected/plain-line path even on a live console' {
        $saved = $env:TPM_PROGRESS_PLAIN
        try {
            $env:TPM_PROGRESS_PLAIN = '1'
            Test-TpmProgressOutputRedirected | Should -BeTrue
        } finally { $env:TPM_PROGRESS_PLAIN = $saved }
    }
}

Describe 'Write-TpmCompactExtractionProgress routes every site through the shared renderer' {
    BeforeAll {
        $tokens = $null
        $parseErrors = $null
        $uiAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path (Join-Path $PSScriptRoot '..') 'TeknoParrot-Manager.ps1'), [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) { throw 'Failed to parse TeknoParrot-Manager.ps1.' }
        $found = @($uiAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Write-TpmCompactExtractionProgress' }, $true))
        if ($found.Count -ne 1) { throw 'Expected exactly one Write-TpmCompactExtractionProgress.' }
        # Recording stand-ins for the renderer; the real wrapper is the unit under test.
        function Import-TpmProgressModule {}
        function Test-TpmProgressActive { return [bool]$script:uiActive }
        function Test-TpmProgressGroupOwned { return [bool]$script:uiGroup }
        function Get-TpmProgressTitle { return $script:uiTitle }
        function Register-TpmProgressOutcome { param($State) [void]$script:uiEvents.Add([pscustomobject]@{ Kind = 'Outcome'; State = $State }) }
        function Start-TpmProgressOperation {
            param($Title, $Stage, $Total, $Width, [switch]$Group, $Unit = 'Items')
            $script:uiActive = $true; $script:uiTitle = $Title
            [void]$script:uiEvents.Add([pscustomobject]@{ Kind = 'Start'; Stage = $Stage; Current = $null; Total = $Total; Unit = $Unit; UnitBound = $PSBoundParameters.ContainsKey('Unit'); StageOnly = $false; State = $null })
        }
        function Set-TpmProgressStage {
            param([string]$Stage, [long]$Current, [long]$Total, [switch]$StageOnly, $Unit = 'Items', [switch]$SameStage)
            [void]$script:uiEvents.Add([pscustomobject]@{ Kind = 'Stage'; Stage = $Stage; Current = $Current; Total = $Total; Unit = $Unit; UnitBound = $PSBoundParameters.ContainsKey('Unit'); StageOnly = [bool]$StageOnly; SameStage = [bool]$SameStage; State = $null })
        }
        function Complete-TpmProgressOperation {
            param($State = 'Final', $Message = '', [switch]$Superseded)
            [void]$script:uiEvents.Add([pscustomobject]@{ Kind = 'Complete'; State = $State; Superseded = [bool]$Superseded })
            $script:uiActive = $false
        }
        function Format-TpmProgressLine { param($Title, $Stage, $Current, $Total, $ElapsedSeconds, $Width, $Unit = 'Items') return ('{0}/{1} {2}' -f $Current, $Total, $Unit) }
        . ([scriptblock]::Create($found[0].Extent.Text))
    }
    BeforeEach {
        Set-RendererDefaultMocks
        $script:uiEvents = New-Object System.Collections.Generic.List[object]
        $script:uiActive = $false
        $script:uiGroup = $false
        $script:uiTitle = $null
    }

    It 'forwards -Unit Bytes to the opened operation and the stage, and leaves it unset for item counts' {
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Bytes' -Current 4096 -Total 8192 -Completed -Unit Bytes
        $start = @($script:uiEvents | Where-Object Kind -eq 'Start')[0]
        $stage = @($script:uiEvents | Where-Object Kind -eq 'Stage')[0]
        $start.Unit | Should -Be 'Bytes'
        $stage.Unit | Should -Be 'Bytes'
        $stage.Current | Should -Be 4096
        $script:uiEvents.Clear(); $script:uiActive = $false
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Items' -Current 1 -Total 2
        @($script:uiEvents | Where-Object { $_.Kind -in @('Start', 'Stage') } | ForEach-Object { $_.UnitBound }) -contains $true | Should -BeFalse
    }

    It 'records the finished counts when a group-owned leaf completes Final, instead of leaving the stage at its last started count' {
        $script:uiActive = $true; $script:uiGroup = $true
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Scan' -Current 5 -Total 5 -Complete
        $stage = @($script:uiEvents | Where-Object Kind -eq 'Stage')
        $stage.Count | Should -Be 1
        $stage[0].Stage | Should -Be 'Scan done'
        $stage[0].Current | Should -Be 5
        $stage[0].Total | Should -Be 5
        $stage[0].StageOnly | Should -BeFalse
        # "Scan done" relabels the measured stage: it must keep the stage clock (FIX10 MAJOR 3).
        $stage[0].SameStage | Should -BeTrue
        @($script:uiEvents | Where-Object Kind -eq 'Complete').Count | Should -Be 0
    }

    It 'only updates the text when a group-owned leaf completes without counts' {
        $script:uiActive = $true; $script:uiGroup = $true
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Scan' -Current 0 -Total 0 -Complete
        $stage = @($script:uiEvents | Where-Object Kind -eq 'Stage')[0]
        $stage.StageOnly | Should -BeTrue
        $stage.Stage | Should -Be 'Scan done'
    }

    It 'records a failed group-owned leaf on the group instead of closing it' {
        $script:uiActive = $true; $script:uiGroup = $true
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Scan' -Current 2 -Total 5 -Complete -Outcome Error
        @($script:uiEvents | Where-Object Kind -eq 'Outcome')[0].State | Should -Be 'Error'
        @($script:uiEvents | Where-Object Kind -eq 'Stage')[0].Stage | Should -Be 'Scan failed'
        @($script:uiEvents | Where-Object Kind -eq 'Complete').Count | Should -Be 0
    }

    It 'closes a standalone operation with the requested outcome and no count rewrite on failure' {
        $script:uiActive = $true
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Scan' -Current 3 -Total 3 -Complete -Outcome Error
        @($script:uiEvents | Where-Object Kind -eq 'Stage').Count | Should -Be 0
        @($script:uiEvents | Where-Object Kind -eq 'Complete')[0].State | Should -Be 'Error'
    }

    It 'marks the close of a stage replaced by another phase as superseded so it cannot read as done' {
        $script:uiActive = $true; $script:uiTitle = 'Scanning'
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'Next' -Current 1 -Total 3
        $close = @($script:uiEvents | Where-Object Kind -eq 'Complete')
        $close.Count | Should -Be 1
        $close[0].Superseded | Should -BeTrue
    }
}

Describe 'Final closes only on the success path' {
    BeforeAll {
        $tokens = $null
        $parseErrors = $null
        $uiAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path (Join-Path $PSScriptRoot '..') 'TeknoParrot-Manager.ps1'), [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) { throw 'Failed to parse TeknoParrot-Manager.ps1.' }
        $names = @('Test-TpmDirectoryAgainstZipInventory', 'Measure-PathWriteThroughput', 'ConvertTo-SafeZipEntryRelativePath', 'Expand-ZipFileSafe')
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $found = @($uiAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $names }, $true))
        if ($found.Count -ne $names.Count) { throw 'Expected the functions under test.' }
        function Write-TpmCompactExtractionProgress {
            param([string]$Phase, [string]$Label, [long]$Current, [long]$Total, [datetime]$StartedAt, [int]$Width, [switch]$Complete, [switch]$Substage, [string]$Outcome = 'Final', [switch]$ReturnText, [switch]$Completed, [string]$Unit = 'Items')
            if ($script:throwOnLabel -and -not $Complete -and $Label -like $script:throwOnLabel) { throw 'fixture progress failure' }
            [void]$script:closeEvents.Add([pscustomobject]@{ Label = $Label; Current = $Current; Total = $Total; Complete = [bool]$Complete; Outcome = $Outcome; Unit = $Unit })
        }
        function Assert-TpmNoReparseWriteTarget { param([string]$Path, [string]$Operation) }
        . ([scriptblock]::Create((($found | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n")))
        function New-Rc8UiZip {
            param([string]$Path, [string[]]$EntryNames)
            $zip = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($entryName in $EntryNames) {
                    $entry = $zip.CreateEntry($entryName)
                    $writer = New-Object System.IO.StreamWriter($entry.Open())
                    try { $writer.Write('x-' + $entryName) } finally { $writer.Dispose() }
                }
            } finally { $zip.Dispose() }
        }
    }
    BeforeEach { Set-RendererDefaultMocks; $script:closeEvents = New-Object System.Collections.Generic.List[object]; $script:throwOnLabel = $null }

    It 'closes the byte-counted write sample Final with the full size after a complete write' {
        $dir = Join-Path $TestDrive ('rc8ui-write-' + [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($dir)
        [void](Measure-PathWriteThroughput -path $dir)
        $close = @($script:closeEvents | Where-Object { $_.Complete })
        $close.Count | Should -Be 1
        $close[0].Outcome | Should -Be 'Final'
        $close[0].Unit | Should -Be 'Bytes'
        $close[0].Current | Should -Be 10MB
        $close[0].Total | Should -Be 10MB
    }

    It 'closes the inventory comparison Final when a mismatch is the answer, not Error' {
        $manifest = [pscustomobject]@{ Readable = $true; Exists = $true; IsDirectory = $true; Items = @([pscustomobject]@{ RelativePath = 'a.txt'; IsDirectory = $false; Length = 1; Sha256 = 'AA' }) }
        $inventory = [pscustomobject]@{ Entries = @([pscustomobject]@{ RelativePath = 'a.txt'; IsDirectory = $false; Length = 1; Sha256 = 'BB' }) }
        Test-TpmDirectoryAgainstZipInventory -Manifest $manifest -Inventory $inventory | Should -BeFalse
        $compare = @($script:closeEvents | Where-Object { $_.Complete -and $_.Label -like '*comparison*' })
        $compare.Count | Should -Be 1
        $compare[0].Outcome | Should -Be 'Final'
    }

    It 'closes the inventory comparison Final after a clean full comparison' {
        $entry = [pscustomobject]@{ RelativePath = 'a.txt'; IsDirectory = $false; Length = 1; Sha256 = 'AA' }
        $manifest = [pscustomobject]@{ Readable = $true; Exists = $true; IsDirectory = $true; Items = @($entry) }
        $inventory = [pscustomobject]@{ Entries = @($entry) }
        Test-TpmDirectoryAgainstZipInventory -Manifest $manifest -Inventory $inventory | Should -BeTrue
        @($script:closeEvents | Where-Object { $_.Complete } | ForEach-Object { $_.Outcome } | Select-Object -Unique) | Should -Be @('Final')
    }

    It 'closes the indexing stage Error, one short, when the loop throws' {
        $entry = [pscustomobject]@{ RelativePath = 'a.txt'; IsDirectory = $false; Length = 1; Sha256 = 'AA' }
        $manifest = [pscustomobject]@{ Readable = $true; Exists = $true; IsDirectory = $true; Items = @($entry) }
        $inventory = [pscustomobject]@{ Entries = @($entry) }
        $script:throwOnLabel = '*indexing*'
        { Test-TpmDirectoryAgainstZipInventory -Manifest $manifest -Inventory $inventory } | Should -Throw '*fixture progress failure*'
        $index = @($script:closeEvents | Where-Object { $_.Complete -and $_.Label -like '*indexing*' })
        $index.Count | Should -Be 1
        $index[0].Outcome | Should -Be 'Error'
        $index[0].Current | Should -Be 0
    }

    It 'closes extraction Final with every byte counted after a complete extraction' {
        $zipPath = Join-Path $TestDrive ('rc8ui-ok-' + [guid]::NewGuid().ToString('N') + '.zip')
        $dest = Join-Path $TestDrive ('rc8ui-ok-dest-' + [guid]::NewGuid().ToString('N'))
        New-Rc8UiZip -Path $zipPath -EntryNames @('a.txt', 'b.txt')
        Expand-ZipFileSafe -ZipPath $zipPath -DestDir $dest -GameName 'Fixture'
        $close = @($script:closeEvents | Where-Object { $_.Complete })
        $close.Count | Should -Be 1
        $close[0].Outcome | Should -Be 'Final'
        $close[0].Current | Should -Be 14   # progress counts bytes: 7 + 7
        $close[0].Total | Should -Be 14
    }

    It 'closes extraction Error, one short, when the second file cannot be written (review BLOCKER-1)' {
        $zipPath = Join-Path $TestDrive ('rc8ui-fail-' + [guid]::NewGuid().ToString('N') + '.zip')
        $dest = Join-Path $TestDrive ('rc8ui-fail-dest-' + [guid]::NewGuid().ToString('N'))
        New-Rc8UiZip -Path $zipPath -EntryNames @('a.txt', 'b.txt')
        [void][System.IO.Directory]::CreateDirectory($dest)
        $lock = [System.IO.File]::Open((Join-Path $dest 'b.txt'), [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try {
            { Expand-ZipFileSafe -ZipPath $zipPath -DestDir $dest -GameName 'Fixture' } | Should -Throw
        } finally { $lock.Dispose() }
        $close = @($script:closeEvents | Where-Object { $_.Complete })
        $close.Count | Should -Be 1
        $close[0].Outcome | Should -Be 'Error'
        $close[0].Current | Should -Be 7    # only the first file's 7 bytes were written
        $close[0].Total | Should -Be 14
    }
}

Describe 'Write-TpmDownloadProgress with an active workflow status' {
    BeforeAll {
        $tokens = $null
        $parseErrors = $null
        $uiAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path (Join-Path $PSScriptRoot '..') 'TeknoParrot-Manager.ps1'), [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) { throw 'Failed to parse TeknoParrot-Manager.ps1.' }
        $found = @($uiAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Write-TpmDownloadProgress' }, $true))
        if ($found.Count -ne 1) { throw 'Expected Write-TpmDownloadProgress.' }
        function Import-TpmProgressModule {}
        function Test-TpmProgressGroupOwned { return [bool]$script:dlGroup }
        function Get-TpmProgressEta { param($Current, $Total, $StartCurrent, $ElapsedSeconds, $Samples) return -1 }
        function Format-TpmProgressSummary { param($Current, $Total, $Unit, $ElapsedSeconds, $EtaSeconds) return 'summary' }
        function Update-TpmWorkflowActivity { param($Context, $Activity) $script:dlFooter++ }
        function Write-TpmCompactExtractionProgress { param($Phase, $Label, $Current, $Total, $StartedAt, [switch]$Completed, [switch]$Complete, $Unit) $script:dlCompact++ }
        . ([scriptblock]::Create($found[0].Extent.Text))
    }
    BeforeEach {
        Set-RendererDefaultMocks
        $script:dlFooter = 0; $script:dlCompact = 0; $script:dlGroup = $false
        $script:ActiveTpmWorkflowStatus = [pscustomobject]@{ LastDownloadStatusUtc = $null }
    }
    AfterEach { $script:ActiveTpmWorkflowStatus = $null }

    It 'updates only the footer when no group owns progress' {
        Write-TpmDownloadProgress -Label 'X' -Method 'HttpClient' -DownloadedBytes 100 -TotalBytes 1000 -Elapsed ([TimeSpan]::FromSeconds(1))
        $script:dlFooter | Should -Be 1
        $script:dlCompact | Should -Be 0
    }

    It 'routes updates through the compact renderer when a group owns progress, because the footer is suppressed then' {
        $script:dlGroup = $true
        Write-TpmDownloadProgress -Label 'X' -Method 'HttpClient' -DownloadedBytes 100 -TotalBytes 1000 -Elapsed ([TimeSpan]::FromSeconds(1))
        Write-TpmDownloadProgress -Label 'X' -Method 'HttpClient' -DownloadedBytes 1000 -TotalBytes 1000 -Elapsed ([TimeSpan]::FromSeconds(2)) -Complete
        $script:dlCompact | Should -Be 2
        $script:dlFooter | Should -Be 0
    }
}
