#Requires -Version 5.1
<#
.SYNOPSIS
    Developer preview of every TeknoParrot Manager progress state, drawn by the shared renderer
    (scripts\TpmProgress.psm1) - the same code the product uses. Run it in a real console and screenshot it.

.DESCRIPTION
    Shows: the detected host/style/color, a width gallery (120 down to 30 columns) of every state in ASCII and
    glyph mode, the state palette on light and dark backgrounds, live bars (determinate with ETA, the
    99%-until-verified rule, unknown-total spinner, byte download, failure, cancel, stall, no-op, a new stage that
    restarts the ETA, ordinary output printed while a bar is open, group workflow success and failure, a nested
    failure that keeps the parent open), the plain-line fallback used for redirected output, and optional prompt
    and resize checks.

    Nothing here touches a TeknoParrot install, LaunchBox, the network, or the product script.
    Run it under Windows PowerShell 5.1 (conhost), Windows Terminal, and PowerShell 7 for the owner comparison.

.PARAMETER Style
    Both (default: the thin-line glyph look and the ASCII fallback, one after the other), Unicode, Block (the solid bar
    with ASCII icons), Ascii, or Auto (exactly what the product would choose on this host: glyphs when the host can
    render them, the solid bar on other interactive consoles, otherwise ASCII).
.PARAMETER Fast
    Shorter pauses (for a quick look).
.PARAMETER StaticOnly
    Only the width gallery; no live bars.
.PARAMETER SkipPlain
    Skip the plain-line (redirected output) demonstration.
.PARAMETER Prompt
    Also demonstrate a prompt while a bar is open (waits for Enter).
.PARAMETER ResizeSeconds
    Also run one slow bar for this many seconds so the window can be resized while it draws.
.PARAMETER LookOnly
    Only the color look (FIX106): one live bar per state (running at 10, 25, 50 and 75 percent, done, ended early, failed,
    skipped, unknown total), with a message printed above the bars. Quick way to approve the look in a visible window.
#>
param(
    [ValidateSet('Auto', 'Ascii', 'Block', 'Unicode', 'Both')]
    [string]$Style = 'Both',
    [switch]$Fast,
    [switch]$StaticOnly,
    [switch]$SkipPlain,
    [switch]$Prompt,
    [ValidateRange(0, 600)]
    [int]$ResizeSeconds = 0,
    [switch]$LookOnly
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'TpmProgress.psm1') -Force

$script:Pause = if ($Fast) { 25 } else { 60 }

function Wait-Step {
    param([double]$Scale = 1)
    Start-Sleep -Milliseconds ([int]($script:Pause * $Scale))
}

function Write-Section {
    param([string]$Text)
    Write-Host ''
    Write-Host ('=== {0} ===' -f $Text) -ForegroundColor Yellow
}

function Invoke-Demo {
    param([string]$Name, [scriptblock]$Body)
    Write-Host ('-- {0}' -f $Name) -ForegroundColor DarkGray
    try { & $Body } finally { Stop-TpmProgressAbandoned }
}

function Show-Environment {
    Write-Section 'Detected environment'
    $capabilities = Get-TpmProgressCapabilities
    $width = $null
    try { $width = [Console]::WindowWidth } catch {}
    $rows = [ordered]@{
        'Host'                    = '{0} / PowerShell {1} ({2})' -f $Host.Name, $PSVersionTable.PSVersion, $PSVersionTable.PSEdition
        'Output redirected'       = $capabilities.Redirected
        'Window width'            = $width
        'Output code page'        = $capabilities.OutputCodePage
        'UTF-16 console write'    = $capabilities.WideWrite
        'Windows Terminal'        = $capabilities.WindowsTerminal
        'VS Code terminal'        = $capabilities.VsCodeTerminal
        'conhost Consolas/Cascadia TrueType font' = $capabilities.ConhostFont
        'CJK double-byte code page'   = $capabilities.CjkCodePage
        'Measured glyph cells (1 each)' = $(if ($null -eq $capabilities.GlyphCells) { 'not measured' } else { $capabilities.GlyphCells })
        'Console background'      = $(if ($capabilities.Background) { $capabilities.Background } else { 'unknown (no color)' })
        'TPM_PROGRESS_STYLE'      = $(if ($capabilities.StyleOverride) { $capabilities.StyleOverride } else { 'not set (auto)' })
        'NO_COLOR'                = $(if ($env:NO_COLOR) { 'set' } else { 'not set' })
        'TPM_PROGRESS_COLOR'      = $(if ($env:TPM_PROGRESS_COLOR) { $env:TPM_PROGRESS_COLOR } else { 'not set' })
        'Chosen style'            = $(switch ($capabilities.Style) { 'Unicode' { 'Unicode (thin-line glyphs)' } 'Block' { 'Block (solid bar, ASCII icons)' } default { 'Ascii (fallback)' } })
        'Color mode'              = $capabilities.ColorMode
    }
    foreach ($key in $rows.Keys) { Write-Host ('  {0,-42} {1}' -f $key, $rows[$key]) }
    Write-Host '  Rule: glyphs unless the output is redirected, or frames cannot be written as UTF-16 and the code page is not UTF-8,' -ForegroundColor DarkGray
    Write-Host '        or the code page is CJK double-byte, or the host is not Windows Terminal / VS Code / a conhost TrueType' -ForegroundColor DarkGray
    Write-Host '        Consolas or Cascadia font, or the measured probe saw a glyph take other than one cell.' -ForegroundColor DarkGray
    Write-Host '        Force ASCII with $env:TPM_PROGRESS_STYLE = ''ascii''. NO_COLOR only removes color.' -ForegroundColor DarkGray
    Write-Host '        Color follows the console background; an unknown background gets no color.' -ForegroundColor DarkGray
}

function Write-PreviewOutput {
    # The same coordination the product's Write-Host proxy does: lift the bar, print, redraw the bar below.
    param([string]$Text, [string]$Color = 'Gray')
    $lifted = Suspend-TpmProgressOutput
    try { Write-Host $Text -ForegroundColor $Color } finally { if ($lifted) { Resume-TpmProgressOutput } }
}

function Invoke-WithProgressStyle {
    # Runs the body with the renderer forced to one style (the same override the product reads) and puts the old setting back afterwards.
    param([Parameter(Mandatory)][string]$StyleName, [Parameter(Mandatory)][scriptblock]$Body)
    $savedStyle = $env:TPM_PROGRESS_STYLE
    try {
        $env:TPM_PROGRESS_STYLE = $StyleName.ToLowerInvariant()
        & $Body
    } finally { $env:TPM_PROGRESS_STYLE = $savedStyle }
}

function Show-StateLook {
    # FIX106: every bar state at once, drawn by the same live renderer the product uses. The bars stay at the bottom; the message
    # printed in the middle appears above them. Running bars end at 10, 25, 50 and 75 percent, so different percentages show
    # different colors at the same moment.
    param([Parameter(Mandatory)][string]$LookStyle)
    Write-Section ('The color look: one live bar per state - {0} glyphs' -f $LookStyle)
    Invoke-Demo 'Running 10/25/50/75 percent, done, ended early, failed (120/100), skipped and an unknown total; a message above the bars' {
        Start-TpmProgressOperation -Title 'TeknoParrot Manager' -Stage 'Some bars fail or stop early on purpose' -Total 100 | Out-Null
        $running = @(10, 25, 50, 75 | ForEach-Object { [pscustomobject]@{ Target = $_; Id = (Add-TpmProgressTask -Description ('Running {0} percent' -f $_) -Total 100) } })
        $done = Add-TpmProgressTask -Description 'Done' -Total 100
        $early = Add-TpmProgressTask -Description 'Ended early' -Total 100
        $failed = Add-TpmProgressTask -Description 'Failed' -Total 100
        $skipped = Add-TpmProgressTask -Description 'Skipped' -Total 100 -Pending
        $scan = Add-TpmProgressTask -Description 'Scanning' -Total 0
        foreach ($step in 1..60) {
            Wait-Step 1.5
            Set-TpmProgressStage -Stage 'Some bars fail or stop early on purpose' -Current ([int]($step * 100 / 60)) -Total 100
            foreach ($bar in $running) { Set-TpmProgressTask -Id $bar.Id -Current ([int]($bar.Target * $step / 60)) }
            Set-TpmProgressTask -Id $scan -Current ($step * 70)
            if ($step -eq 30) { Write-PreviewOutput '    Found 12 games. This message is printed above the bars.' 'Green' }
        }
        Set-TpmProgressTask -Id $done -Current 100 -State Final
        Set-TpmProgressTask -Id $early -Current 60 -State Incomplete
        Set-TpmProgressTask -Id $failed -Current 120 -State Error
        # Skipped is set here, not left to the close: the close would also end the running and scanning rows as incomplete.
        Set-TpmProgressTask -Id $skipped -State Skipped
        Start-Sleep -Milliseconds $(if ($Fast) { 2500 } else { 7000 })
        Complete-TpmProgressOperation -State Final
    }
}

function Show-PaletteGallery {
    Write-Section 'State palette per console background (mark, fill and word colored; numbers keep the host foreground)'
    $states = @(
        @{ State = 'Running'; Mark = '|'; Word = 'running' },
        @{ State = 'Waiting'; Mark = '|'; Word = 'still working' },
        @{ State = 'Final'; Mark = '+'; Word = 'done' },
        @{ State = 'Error'; Mark = 'x'; Word = 'FAILED' },
        @{ State = 'Cancelled'; Mark = '-'; Word = 'canceled' }
    )
    foreach ($background in @('Black', 'DarkBlue', 'DarkMagenta', 'Gray', 'White')) {
        $palette = Get-TpmProgressPalette -Background $background
        Write-Host ('  {0,-12}' -f $background) -NoNewline
        foreach ($entry in $states) {
            $key = switch ($entry.State) { 'Error' { 'Error' } 'Final' { 'Final' } 'Cancelled' { 'Warn' } default { 'Running' } }
            $stateColor = $palette[$key]
            $trackColor = $palette['Dim']
            $tinyDots = ([string][char]0x00B7) * 5
            $text = ' {0} {1} ' -f $entry.Mark, $entry.Word
            if ($stateColor) { Write-Host $text -BackgroundColor $background -ForegroundColor $stateColor -NoNewline } else { Write-Host $text -BackgroundColor $background -NoNewline }
            if ($trackColor) { Write-Host $tinyDots -BackgroundColor $background -ForegroundColor $trackColor -NoNewline } else { Write-Host $tinyDots -BackgroundColor $background -NoNewline }
        }
        Write-Host ''
    }
    Write-Host '  The tiny dots after each word are the empty part of a bar in the Block look (a quiet dim gray background).' -ForegroundColor DarkGray
    Write-Host '  An empty color above means the console foreground is used (the palette never draws in the background hue).' -ForegroundColor DarkGray
}

function Show-WidthGallery {
    param([ValidateSet('Ascii', 'Block', 'Unicode')][string]$GalleryStyle)
    Write-Section ('Width gallery - {0} glyphs (plain text; live bars below are colored)' -f $GalleryStyle)
    $cases = @(
        @{ Name = 'running 42% with ETA';        Params = @{ Title = 'Extracting'; Stage = 'Fixture Game (Sega)'; Current = 42; Total = 100; State = 'Running'; ElapsedSeconds = 37; EtaSeconds = 51; Tick = 1 } },
        @{ Name = 'running 99% (verifying)';     Params = @{ Title = 'Checking'; Stage = 'Verifying backup'; Current = 100; Total = 100; State = 'Running'; ElapsedSeconds = 90; Tick = 2 } },
        @{ Name = 'final 100%';                  Params = @{ Title = 'Repairing'; Stage = 'Promotion staging'; Current = 100; Total = 100; State = 'Final'; ElapsedSeconds = 91 } },
        @{ Name = 'unknown total (spinner)';     Params = @{ Title = 'Scanning'; Stage = 'Game-file discovery'; Current = 1287; Total = 0; State = 'Running'; ElapsedSeconds = 12; Tick = 3 } },
        @{ Name = 'download in bytes';           Params = @{ Title = 'Checking'; Stage = 'ReShade via BITS'; Current = 12582912; Total = 20971520; State = 'Running'; ElapsedSeconds = 8; EtaSeconds = 5; Unit = 'Bytes'; Tick = 0 } },
        @{ Name = 'failed';                      Params = @{ Title = 'Repairing'; Stage = 'UserProfiles restore'; Current = 12; Total = 40; State = 'Error'; ElapsedSeconds = 14 } },
        @{ Name = 'cancelled';                   Params = @{ Title = 'Repairing'; Stage = 'UserProfiles restore'; Current = 12; Total = 40; State = 'Cancelled'; ElapsedSeconds = 14 } },
        @{ Name = 'stalled (counted loop stopped)'; Params = @{ Title = 'Checking'; Stage = 'Waiting for PostgreSQL'; Current = 4; Total = 10; State = 'Stalled'; ElapsedSeconds = 75 } },
        @{ Name = 'still working (installer)';   Params = @{ Title = 'PostgreSQL install'; Stage = 'Running the PostgreSQL installer'; Current = 0; Total = 0; State = 'Waiting'; ElapsedSeconds = 107; NoCount = $true } },
        @{ Name = 'no-op';                       Params = @{ Title = 'Scanning'; Stage = 'Nothing to do'; Current = 0; Total = 0; State = 'No-op'; ElapsedSeconds = 1 } }
    )
    foreach ($width in @(120, 100, 80, 60, 50, 40, 30)) {
        Write-Host ('  width {0}' -f $width) -ForegroundColor DarkGray
        foreach ($case in $cases) {
            $lineParams = $case.Params
            $line = Format-TpmProgressLine @lineParams -Width $width -Style $GalleryStyle
            Write-Host ('  ' + $line.TrimEnd())
        }
    }
    Write-Host ''
    Write-Host '  Status-footer summary (same wording, no bar):' -ForegroundColor DarkGray
    Write-Host ('    ReShade: ' + (Format-TpmProgressSummary -Current 12582912 -Total 20971520 -Unit Bytes -ElapsedSeconds 8 -EtaSeconds 5))
}

function Show-LiveDemos {
    Invoke-Demo 'Determinate: 1/N finished counts, ETA after 3 samples and 3 s, 99% until verified, then 100% Final' {
        Start-TpmProgressOperation -Title 'Extracting' -Stage 'Fixture Game' -Total 40 | Out-Null
        foreach ($n in 1..40) { Wait-Step 3; Set-TpmProgressStage -Stage 'Fixture Game' -Current $n -Total 40 }
        Set-TpmProgressStage -Stage 'Verifying extracted files' -Current 40 -Total 40
        Start-Sleep -Milliseconds 1200
        Complete-TpmProgressOperation -State Final
    }
    Invoke-Demo 'Unknown total: spinner and count only, no percent' {
        Start-TpmProgressOperation -Title 'Scanning' -Stage 'Game-file discovery' | Out-Null
        foreach ($n in 1..60) { Wait-Step 3; Set-TpmProgressStage -Stage 'Game-file discovery' -Current ($n * 21) -Total 0 }
        Complete-TpmProgressOperation -State Final
    }
    Invoke-Demo 'Byte download with size, percent and ETA (stays below 100% until verified)' {
        $total = 48MB
        Start-TpmProgressOperation -Title 'Checking' -Stage 'ReShade via HttpClient' -Total $total -Unit Bytes | Out-Null
        foreach ($n in 1..48) { Wait-Step 3; Set-TpmProgressStage -Stage 'ReShade via HttpClient' -Current ([long]$n * 1MB) -Total $total -Unit Bytes }
        Set-TpmProgressStage -Stage 'Verifying ReShade' -Current $total -Total $total -Unit Bytes
        Start-Sleep -Milliseconds 1000
        Complete-TpmProgressOperation -State Final
    }
    Invoke-Demo 'Failure: closes as FAILED, never 100%' {
        Start-TpmProgressOperation -Title 'Repairing' -Stage 'UserProfiles restore' -Total 40 | Out-Null
        foreach ($n in 1..16) { Wait-Step 3; Set-TpmProgressStage -Stage 'UserProfiles restore' -Current $n -Total 40 }
        Complete-TpmProgressOperation -State Error
    }
    Invoke-Demo 'Cancelled' {
        Start-TpmProgressOperation -Title 'Repairing' -Stage 'UserProfiles restore' -Total 40 | Out-Null
        foreach ($n in 1..12) { Wait-Step 3; Set-TpmProgressStage -Stage 'UserProfiles restore' -Current $n -Total 40 }
        Complete-TpmProgressOperation -State Cancelled
    }
    Invoke-Demo 'Stalled: no update for longer than the stall threshold (1 s here)' {
        Start-TpmProgressOperation -Title 'Checking' -Stage 'Waiting for PostgreSQL' -Total 10 -StallSeconds 1 | Out-Null
        foreach ($n in 1..3) { Wait-Step 3; Set-TpmProgressStage -Stage 'Waiting for PostgreSQL' -Current $n -Total 10 }
        Start-Sleep -Milliseconds 1600
        Set-TpmProgressStage -Stage 'Waiting for PostgreSQL' -Current 4 -Total 10
        Complete-TpmProgressOperation -State Final
    }
    Invoke-Demo 'Long installer step (no count): a long wait reads "still working", never "stalled" (threshold 1 s here)' {
        Start-TpmProgressOperation -Title 'PostgreSQL install' -Stage 'Getting ready' -StallSeconds 1 | Out-Null
        Set-TpmProgressStage -Stage 'Running the PostgreSQL installer' -Current 0 -Total 0 -LongStep
        Start-Sleep -Milliseconds $(if ($Fast) { 3000 } else { 6000 })
        Set-TpmProgressStage -Stage 'Running the PostgreSQL installer done' -StageOnly
        Complete-TpmProgressOperation -State Final
    }
    Invoke-Demo 'No-op: nothing needed changing' {
        Start-TpmProgressOperation -Title 'Scanning' -Stage 'GameProfiles' -Total 8 | Out-Null
        foreach ($n in 1..8) { Wait-Step 2; Set-TpmProgressStage -Stage 'GameProfiles' -Current $n -Total 8 }
        Set-TpmProgressStage -Stage 'GameProfiles' -Current 8 -Total 8
        Complete-TpmProgressOperation -State No-op
    }
    Invoke-Demo 'Group workflow (one owner bar, each stage shows its own count), closed Final from the verified result' {
        Start-TpmProgressOperation -Title 'Register games' -Group | Out-Null
        foreach ($n in 1..20) { Wait-Step 3; Set-TpmProgressStage -Stage 'Scanning GameProfiles' -Current $n -Total 20 }
        Set-TpmProgressStage -Stage 'Scanning GameProfiles done' -StageOnly
        foreach ($n in 1..25) { Wait-Step 3; Set-TpmProgressStage -Stage 'Checking registered paths' -Current $n -Total 25 }
        Set-TpmProgressStage -Stage 'Checking registered paths done' -StageOnly
        Start-Sleep -Milliseconds 600
        Complete-TpmProgressOperation -State Final
    }
    Invoke-Demo 'Group workflow whose leaf failed: the owner closes FAILED even when asked for Final' {
        Start-TpmProgressOperation -Title 'Restore backup' -Group | Out-Null
        foreach ($n in 1..10) { Wait-Step 3; Set-TpmProgressStage -Stage 'Restoring UserProfiles' -Current $n -Total 30 }
        Register-TpmProgressOutcome -State Error
        Complete-TpmProgressOperation -State Final
    }
    Invoke-Demo 'New stage with the same total: the clock and ETA restart instead of carrying over' {
        Start-TpmProgressOperation -Title 'Checking' -Stage 'Stage A: hashing' -Total 30 | Out-Null
        foreach ($n in 1..15) { Wait-Step 3; Set-TpmProgressStage -Stage 'Stage A: hashing' -Current $n -Total 30 }
        foreach ($n in 15..30) { Wait-Step 6; Set-TpmProgressStage -Stage 'Stage B: comparing' -Current $n -Total 30 }
        Complete-TpmProgressOperation -State Final
    }
    Invoke-Demo 'Ordinary output while a bar is open: each line starts on a clean row and the bar is redrawn below it' {
        Start-TpmProgressOperation -Title 'Repairing' -Stage 'CursorHide profile update' -Total 6 | Out-Null
        foreach ($n in 1..6) {
            Wait-Step 6
            if ($n -eq 4) { Write-PreviewOutput ('    FAILED  Fixture{0}: profile was not verified' -f $n) 'Red' } else { Write-PreviewOutput ('    Updated : Fixture{0}' -f $n) 'Green' }
            Set-TpmProgressStage -Stage 'CursorHide profile update' -Current $n -Total 6
        }
        Complete-TpmProgressOperation -State Error
    }
    Invoke-Demo 'Nested failure inside a group: the parent stays open, names the failure, and closes FAILED at its own close' {
        Start-TpmProgressOperation -Title 'Outer workflow' -Group | Out-Null
        Start-TpmProgressOperation -Title 'Inner step' | Out-Null
        Wait-Step 5
        Complete-TpmProgressOperation -State Error -Message 'fixture failure'
        Write-PreviewOutput ('   after inner Error: parent still open = {0}' -f (Test-TpmProgressActive)) 'DarkGray'
        foreach ($n in 1..10) { Wait-Step 3; Set-TpmProgressStage -Stage 'Outer recovery' -Current $n -Total 10 }
        Complete-TpmProgressOperation -State Final
        Write-Host ('   after outer close: still open = {0}' -f (Test-TpmProgressActive)) -ForegroundColor DarkGray
    }
    if ($Prompt) {
        Invoke-Demo 'Prompt while a bar is open: the bar line is left above the prompt and the cursor stays usable' {
            Start-TpmProgressOperation -Title 'Checking' -Stage 'Waiting for your choice' -Total 10 | Out-Null
            foreach ($n in 1..4) { Wait-Step 3; Set-TpmProgressStage -Stage 'Waiting for your choice' -Current $n -Total 10 }
            Suspend-TpmProgressLine
            try { [void](Read-Host 'Type anything and press Enter') } finally { Resume-TpmProgressLine }
            foreach ($n in 5..10) { Wait-Step 3; Set-TpmProgressStage -Stage 'Waiting for your choice' -Current $n -Total 10 }
            Complete-TpmProgressOperation -State Final
        }
    }
    if ($ResizeSeconds -gt 0) {
        Invoke-Demo ('Resize check: resize the window narrower and wider during the next {0} s (the bar is redrawn in place, no rows left behind)' -f $ResizeSeconds) {
            $steps = [Math]::Max(1, $ResizeSeconds * 5)
            Start-TpmProgressOperation -Title 'Extracting' -Stage 'Resize me' -Total $steps | Out-Null
            foreach ($n in 1..$steps) { Start-Sleep -Milliseconds 200; Set-TpmProgressStage -Stage 'Resize me' -Current $n -Total $steps }
            Complete-TpmProgressOperation -State Final
        }
    }
}

function Show-PlainDemo {
    Write-Section 'Plain-line fallback (what redirected / non-interactive output looks like)'
    $saved = $env:TPM_PROGRESS_PLAIN
    try {
        $env:TPM_PROGRESS_PLAIN = '1'
        Invoke-Demo 'Lines on start, each 10%, every 5 s, and once at close; no carriage returns, no color' {
            Start-TpmProgressOperation -Title 'Extracting' -Stage 'Fixture Game' -Total 25 | Out-Null
            foreach ($n in 1..25) { Start-Sleep -Milliseconds $(if ($Fast) { 40 } else { 250 }); Set-TpmProgressStage -Stage 'Fixture Game' -Current $n -Total 25 }
            Complete-TpmProgressOperation -State Final
        }
    } finally { $env:TPM_PROGRESS_PLAIN = $saved }
}

$styles = switch ($Style) {
    'Both' { @('Unicode', 'Ascii') }
    'Auto' { @((Get-TpmProgressStyle)) }
    default { @($Style) }
}

Show-Environment
if (-not $StaticOnly) {
    foreach ($styleName in $styles) { Invoke-WithProgressStyle -StyleName $styleName -Body { Show-StateLook -LookStyle $styleName } }
}
if ($LookOnly) {
    Write-Host ''
    Write-Host 'Preview finished. Nothing was changed on this machine.' -ForegroundColor Green
    return
}
Show-PaletteGallery

foreach ($styleName in $styles) {
    Show-WidthGallery -GalleryStyle $styleName
    if ($StaticOnly) { continue }
    Write-Section ('Live bars - {0} glyphs' -f $styleName)
    Invoke-WithProgressStyle -StyleName $styleName -Body { Show-LiveDemos }
}

if (-not $StaticOnly -and -not $SkipPlain) { Show-PlainDemo }
Write-Host ''
Write-Host 'Preview finished. Nothing was changed on this machine.' -ForegroundColor Green
