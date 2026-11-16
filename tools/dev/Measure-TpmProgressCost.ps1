#Requires -Version 5.1
# Dev-only cost measurement for the live progress display; this script is not part of the release package.
# Run it in a normal Windows Terminal or conhost window (output not redirected, at least 100 columns and 20 rows), in a
# NEW PowerShell process: the stall check comes first and includes the cold start of the first progress operation.
#
# 1. Stall check (FIX24; -StallSeconds, default 20, 0 skips it). One operation with one task driven like a real loop,
#    +5 units every 50 ms (100 units/s), for StallSeconds. The end of every frame (Live.Frame.DrawnAt, monotonic ms;
#    Live.Frame.Frames counts frames) is sampled about every 15 ms from this thread, which otherwise only makes the
#    progress calls. A gap is the time between two consecutive frames: how long the display went without an update.
#    Value updates only publish, so a gap that ends with the writer's first frame includes the rest of its warm-up.
#    Also reported: how long Start-TpmProgressOperation and Add-TpmProgressTask took, whether the new row was on screen
#    right after Add-TpmProgressTask returned (read back once with GetBufferContents), and when the refresh writer
#    became ready. PASS when the max gap (cold start included) is <= 150 ms, or <= 3 x the sustained frame cost on a
#    console slower than 50 ms per frame; the new row was on screen; and the writer became ready.
# 2. Cost check (FIX23). One operation with six tasks (seven live rows) while the background refresh writer runs:
#   - six Add-TpmProgressTask calls, each drawing its row inline: max ms (<= 50 ms when the stall check ran first, so
#     the console and the code are warm);
#   - 200 Set-TpmProgressTask calls and 200 Set-TpmProgressStage calls with no sleep: average, p95 and max ms. Each
#     loop first makes 20 unmeasured warm-up calls (script compilation); the first call is reported separately.
#   - the screen read back once with $Host.UI.RawUI.GetBufferContents right after the loops: seven rows, each exactly
#     once, showing the final counts. The loop calls only publish (the non-blocking path) and nothing else draws
#     before the read, so the rows on screen were drawn by the background refresh writer.
#   - then the cost of one forced frame, average of 20 (after 2 warm-up frames), drawn exactly as the refresh writer
#     draws it: Invoke-TpmProgressRefreshStep inside the Gate, timed without the Gate wait. A frame that was not
#     actually drawn (the step returned early) fails the check instead of counting as a fast frame.
#   PASS when both update loops have an average < 1.0 ms and a p95 < 5 ms, the frame average is <= 20 ms, the refresh
#   writer was running and ready, and the rows are correct.
# Exit code 0 when every check passes, 1 otherwise. -ResultPath writes the same lines to a text file. The console
# buffer and window size are never changed.
param([string]$ResultPath = '', [ValidateRange(0, 600)][int]$StallSeconds = 20)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:CostFailures = 0
$script:CostLines = New-Object System.Collections.Generic.List[string]

function Add-CostLine {
    param([string]$Text)
    [void]$script:CostLines.Add($Text)
}

function Add-CostResult {
    param([bool]$Pass, [string]$Name, [string]$Evidence)
    if (-not $Pass) { $script:CostFailures++ }
    $word = if ($Pass) { 'PASS' } else { 'FAIL' }
    Add-CostLine ('{0} {1}: {2}' -f $word, $Name, $Evidence)
}

function Get-CostStatistics {
    # Average, p95 (nearest rank) and maximum of a sample set in milliseconds.
    param([double[]]$Samples)
    $sorted = [double[]]$Samples.Clone()
    [Array]::Sort($sorted)
    $sum = 0.0
    foreach ($value in $sorted) { $sum += $value }
    $rank = [int][Math]::Ceiling(0.95 * $sorted.Length) - 1
    return [pscustomobject]@{
        Count = $sorted.Length
        Average = $sum / $sorted.Length
        P95 = $sorted[[Math]::Max(0, $rank)]
        Max = $sorted[$sorted.Length - 1]
    }
}

function Format-CostMs {
    param([double]$Value)
    return $Value.ToString('0.000', [System.Globalization.CultureInfo]::InvariantCulture)
}

. (Join-Path $PSScriptRoot 'TpmConsoleBuffer.ps1')

function Write-CostMarker {
    # Reserves rows below the cursor so the display never scrolls the marker away (the window may be the whole buffer),
    # writes the marker line and returns its buffer row.
    param([string]$Marker, [int]$Reserve)
    if ([Console]::CursorLeft -gt 0) { [Console]::WriteLine() }
    for ($i = 0; $i -lt $Reserve; $i++) { [Console]::WriteLine() }
    [Console]::SetCursorPosition(0, [Console]::CursorTop - $Reserve)
    Write-Host $Marker
    return ([Console]::CursorTop - 1)
}

function Get-CostTimestamp {
    # Monotonic milliseconds: the clock of the module's frame times (Get-TpmProgressTimestamp, Live.Frame.DrawnAt).
    return ([System.Diagnostics.Stopwatch]::GetTimestamp() * 1000.0 / [System.Diagnostics.Stopwatch]::Frequency)
}

$modulePath = Join-Path $PSScriptRoot '..\..\scripts\TpmProgress.psm1'
$marker = 'TPM-PROGRESS-COST ' + ([guid]::NewGuid().ToString('N').Substring(0, 8))
$opTitle = 'TPM cost check'
$descriptions = @(1..6 | ForEach-Object { 'Cost task {0}' -f $_ })
$warmup = 20
$measured = 200
$frameWarmup = 2
$frameSamples = 20
$reserve = 12
$aborted = $null
$taskStats = $null
$stageStats = $null
$frameStats = $null
$frameMissed = 0
$taskFirst = $null
$stageFirst = $null
$writerActive = $false
$writerCost = $null
$interval = $null
$region = $null
$taskCounts = @(0, 0, 0, 0, 0, 0)
$stageCount = 0
$environment = $null
$addTimes = New-Object System.Collections.Generic.List[double]
# Stall check results.
$stallTitle = 'TPM stall check'
$stallTask = 'Stall ramp'
$stallReserve = 6
$stallRan = $false
$stallGaps = New-Object System.Collections.Generic.List[object]
$stallMissed = 0
$stallFrames = 0
$stallStartMs = $null
$stallAddMs = $null
$stallReadyMs = $null
$stallRowSeen = $false
$stallRegion = $null
$stallSustained = $null
$stallInterval = $null
$stallLastCost = $null

try {
    if ([Console]::IsOutputRedirected) { throw 'Output is redirected. Run this script in a real Windows Terminal or conhost window.' }
    $raw = $Host.UI.RawUI
    if ([int]$raw.WindowSize.Width -lt 100) { throw ('The window is {0} columns wide; at least 100 are needed.' -f $raw.WindowSize.Width) }
    if ([int]$raw.WindowSize.Height -lt ($reserve + 6)) { throw ('The window is {0} rows high; at least {1} are needed.' -f $raw.WindowSize.Height, ($reserve + 6)) }
    try { [void](Read-ConsoleBufferRows -From 0 -To 0) } catch { throw ('The screen cannot be read with GetBufferContents: ' + $_.Exception.Message) }

    Get-Module -Name TpmProgress -All | Remove-Module -Force
    $module = Import-Module $modulePath -Force -PassThru -ErrorAction Stop

    if ($StallSeconds -gt 0) {
        # 1. Stall check, first, so the cold start of this process is part of it.
        $stallMarker = $marker + ' stall'
        $stallMarkerRow = Write-CostMarker -Marker $stallMarker -Reserve $stallReserve
        $units = 100 * $StallSeconds
        $origin = Get-CostTimestamp
        $stallOp = Start-TpmProgressOperation -Title $stallTitle -Stage 'Ramp' -Total $units
        $stallStartMs = (Get-CostTimestamp) - $origin
        $frame = $stallOp.Live.Frame
        $seen = [int]$frame.Frames
        $lastDrawn = [double]$frame.DrawnAt
        $addStart = Get-CostTimestamp
        $stallId = Add-TpmProgressTask -Description $stallTask -Total $units
        $stallAddMs = (Get-CostTimestamp) - $addStart
        # Read back at once: the new row must already be on screen (drawn inline by Add-TpmProgressTask).
        $stallRegion = Get-ConsoleBufferRegion -Marker $stallMarker -MarkerRow $stallMarkerRow -Reserve $stallReserve
        $stallRowSeen = ($null -ne $stallRegion -and @(Find-ConsoleBufferRows -Region ([string[]]$stallRegion) -Description $stallTask).Count -eq 1)
        $current = 0
        $next = Get-CostTimestamp
        $end = $next + 1000.0 * $StallSeconds
        while ($true) {
            $now = Get-CostTimestamp
            if ($now -ge $end) { break }
            if ($now -ge $next) {
                $current = [Math]::Min($units, $current + 5)
                Set-TpmProgressTask -Id $stallId -Current $current
                $next += 50
            }
            $service = $stallOp.Live.RefreshService
            if ($null -eq $stallReadyMs -and $null -ne $service -and [bool]$service.Ready) { $stallReadyMs = $now - $origin }
            # CostMs and DrawnAt are set before Frames is counted, so a new count always comes with that frame's values
            # (or a newer frame's).
            $count = [int]$frame.Frames
            if ($count -ne $seen) {
                $drawn = [double]$frame.DrawnAt
                [void]$stallGaps.Add([pscustomobject]@{ Ms = $drawn - $lastDrawn; At = $drawn - $origin; Cost = [double]$frame.CostMs })
                $stallMissed += [Math]::Max(0, $count - $seen - 1)
                $seen = $count
                $lastDrawn = $drawn
            }
            [System.Threading.Thread]::Sleep(5)
        }
        # The time since the last frame counts too: a writer that stopped drawing near the end is a stall.
        $now = Get-CostTimestamp
        [void]$stallGaps.Add([pscustomobject]@{ Ms = $now - $lastDrawn; At = $now - $origin; Cost = [double]0 })
        $stallFrames = [int]$frame.Frames
        $stallSustained = [double]$frame.SustainedMs
        $stallLastCost = [double]$frame.CostMs
        $stallInterval = [double](& $module { param($f) Get-TpmProgressFrameInterval -Frame $f } $frame)
        Complete-TpmProgressOperation -State Incomplete -Message 'stall check finished'
        $stallRan = $true
    }

    # 2. Cost check.
    $markerRow = Write-CostMarker -Marker $marker -Reserve $reserve
    $null = Start-TpmProgressOperation -Title $opTitle -Stage 'Counting' -Total 1000
    $ids = @(foreach ($description in $descriptions) {
        $addStart = Get-CostTimestamp
        Add-TpmProgressTask -Description $description -Total 1000
        [void]$addTimes.Add((Get-CostTimestamp) - $addStart)
    })
    # Let the refresh writer finish its warm-up (a new process starts it cold), so the loops and the screen read below
    # measure it drawing in its steady state.
    $readyWait = [System.Diagnostics.Stopwatch]::StartNew()
    while ($readyWait.ElapsedMilliseconds -lt 10000 -and -not [bool](& $module { $null -ne $script:TpmProgressOp.Live.RefreshService -and [bool]$script:TpmProgressOp.Live.RefreshService.Ready })) {
        Start-Sleep -Milliseconds 20
    }
    $state = Get-TpmProgressState
    $environment = '{0} {1}; host {2}; window {3}x{4}; style {5}; color {6}{7}' -f $(if ($PSVersionTable.PSEdition -eq 'Core') { 'PowerShell' } else { 'Windows PowerShell' }),
        $PSVersionTable.PSVersion, $(if (-not [string]::IsNullOrEmpty($env:WT_SESSION)) { 'Windows Terminal' } else { 'console (no WT_SESSION)' }),
        $raw.WindowSize.Width, $raw.WindowSize.Height, $state.Style, $state.ColorMode,
        $(switch ($state.ColorMode) { 'TrueColor' { ' (RGB gradient)' } 'None' { '' } default { ' (16-color)' } })
    $writerActive = [bool](& $module { $null -ne $script:TpmProgressOp.Live.RefreshService -and [bool]$script:TpmProgressOp.Live.RefreshService.Ready -and $null -eq $script:TpmProgressOp.Live.Failure })
    $watch = New-Object System.Diagnostics.Stopwatch

    # Set-TpmProgressTask: rotate over the six tasks, each call one more finished unit for that task.
    $samples = New-Object 'double[]' $measured
    for ($call = 0; $call -lt ($warmup + $measured); $call++) {
        $slot = $call % $ids.Count
        $taskCounts[$slot]++
        $watch.Restart()
        Set-TpmProgressTask -Id $ids[$slot] -Current $taskCounts[$slot]
        $watch.Stop()
        if ($call -eq 0) { $taskFirst = $watch.Elapsed.TotalMilliseconds }
        if ($call -ge $warmup) { $samples[$call - $warmup] = $watch.Elapsed.TotalMilliseconds }
    }
    $taskStats = Get-CostStatistics -Samples $samples

    # Set-TpmProgressStage: the same stage, one more finished unit per call.
    $samples = New-Object 'double[]' $measured
    for ($call = 0; $call -lt ($warmup + $measured); $call++) {
        $stageCount++
        $watch.Restart()
        Set-TpmProgressStage -Stage 'Counting' -Current $stageCount -Total 1000
        $watch.Stop()
        if ($call -eq 0) { $stageFirst = $watch.Elapsed.TotalMilliseconds }
        if ($call -ge $warmup) { $samples[$call - $warmup] = $watch.Elapsed.TotalMilliseconds }
    }
    $stageStats = Get-CostStatistics -Samples $samples

    # No progress call between the loops and the screen read: let the refresh writer draw the final state, read once.
    $interval = [double](& $module { Get-TpmProgressFrameInterval -Frame $script:TpmProgressOp.Live.Frame })
    Start-Sleep -Milliseconds ([int][Math]::Max(500, 4 * $interval))
    $writerCost = [double](& $module { $script:TpmProgressOp.Live.Frame.CostMs })
    $writerActive = $writerActive -and [bool](& $module { $null -ne $script:TpmProgressOp.Live.RefreshService -and $null -eq $script:TpmProgressOp.Live.Failure -and -not $script:TpmProgressOp.Live.Stop })
    $region = Get-ConsoleBufferRegion -Marker $marker -MarkerRow $markerRow -Reserve $reserve

    # Forced frames, drawn the way the refresh writer draws them. CostMs = -1 marks "no frame drawn yet".
    $frameResult = & $module {
        param($warmupCount, $sampleCount)
        $live = $script:TpmProgressOp.Live
        $times = New-Object System.Collections.Generic.List[double]
        $missed = 0
        for ($i = 0; $i -lt ($warmupCount + $sampleCount); $i++) {
            [System.Threading.Monitor]::Enter($live.Gate)
            try {
                $live.Frame.CostMs = [double]-1
                $timer = [System.Diagnostics.Stopwatch]::StartNew()
                Invoke-TpmProgressRefreshStep -Live $live -Force
                $timer.Stop()
                $drawn = ($live.Frame.CostMs -ge 0)
                if (-not $drawn) { $live.Frame.CostMs = [double]0 }
            } finally { [System.Threading.Monitor]::Exit($live.Gate) }
            if ($i -lt $warmupCount) { continue }
            if ($drawn) { [void]$times.Add($timer.Elapsed.TotalMilliseconds) } else { $missed++ }
        }
        return [pscustomobject]@{ Times = $times.ToArray(); Missed = $missed }
    } $frameWarmup $frameSamples
    $frameMissed = [int]$frameResult.Missed
    if (@($frameResult.Times).Count -gt 0) { $frameStats = Get-CostStatistics -Samples ([double[]]$frameResult.Times) }

    Complete-TpmProgressOperation -State Incomplete -Message 'cost check finished'
} catch {
    $aborted = $_.Exception.Message
} finally {
    try {
        if ((Get-Command Test-TpmProgressActive -ErrorAction SilentlyContinue) -and (Test-TpmProgressActive)) { Stop-TpmProgressAbandoned }
    } catch {}
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
}

Add-CostLine ('TPM progress cost check {0}' -f ([datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)))
if ($null -ne $environment) { Add-CostLine ('Environment: ' + $environment) }
if ($stallRan) {
    $maxGap = 0.0
    $maxIdle = 0.0
    $earlyMax = 0.0
    $over = New-Object System.Collections.Generic.List[string]
    foreach ($gap in $stallGaps) {
        # Idle = the gap minus the cost of the frame that ended it: time nothing was being drawn. A large gap with a small
        # idle time is one slow console write; a large idle time is the writer not drawing.
        $idle = [Math]::Max([double]0, $gap.Ms - $gap.Cost)
        if ($gap.Ms -gt $maxGap) { $maxGap = $gap.Ms }
        if ($idle -gt $maxIdle) { $maxIdle = $idle }
        if ($gap.At -le 2000 -and $gap.Ms -gt $earlyMax) { $earlyMax = $gap.Ms }
        if ($gap.Ms -gt 150) { [void]$over.Add(('{0} ms (idle {1} ms, that frame cost {2} ms) ending {3} ms after the start' -f (Format-CostMs $gap.Ms), (Format-CostMs $idle), (Format-CostMs $gap.Cost), (Format-CostMs $gap.At))) }
    }
    # A console slower than 50 ms per frame may stretch the frame interval up to three times its sustained frame cost.
    $limit = if ($stallSustained -gt 50) { 3 * $stallSustained } else { 150.0 }
    Add-CostLine ('Stall check {0} s, one task +5 units every 50 ms: {1} frames ({2} not seen by the ~15 ms sampler; a missed frame merges two gaps, so the max is an upper bound); max gap {3} ms (max idle between frames {4} ms), max gap in the first 2 s {5} ms, gaps > 150 ms: {6}; sustained frame cost {7} ms, frame interval {8} ms, last frame {9} ms' -f
        $StallSeconds, $stallFrames, $stallMissed, (Format-CostMs $maxGap), (Format-CostMs $maxIdle), (Format-CostMs $earlyMax), $over.Count, (Format-CostMs $stallSustained), (Format-CostMs $stallInterval), (Format-CostMs $stallLastCost))
    Add-CostLine ('Cold start: Start-TpmProgressOperation {0} ms, Add-TpmProgressTask {1} ms, refresh writer ready {2}' -f
        (Format-CostMs $stallStartMs), (Format-CostMs $stallAddMs), $(if ($null -ne $stallReadyMs) { '{0} ms after the start' -f (Format-CostMs $stallReadyMs) } else { 'never' }))
    if ($over.Count -gt 0) { Add-CostLine ('Gaps > 150 ms (first 10): ' + (@($over | Select-Object -First 10) -join '; ')) }
    Add-CostResult -Pass ($maxGap -le $limit) -Name ('stall: max gap between frames <= {0} ms' -f (Format-CostMs $limit)) -Evidence ('{0} ms' -f (Format-CostMs $maxGap))
    Add-CostResult -Pass $stallRowSeen -Name 'stall: the new row was on screen when Add-TpmProgressTask returned' -Evidence $(if ($null -eq $stallRegion) { 'marker line not found on screen' } else { 'display: ' + (@($stallRegion) -join ' | ') })
    Add-CostResult -Pass ($null -ne $stallReadyMs) -Name 'stall: refresh writer became ready' -Evidence $(if ($null -ne $stallReadyMs) { '{0} ms after the start' -f (Format-CostMs $stallReadyMs) } else { 'not ready after {0} s' -f $StallSeconds })
}
if ($null -ne $aborted) {
    Add-CostResult -Pass $false -Name 'run' -Evidence $aborted
} else {
    Add-CostResult -Pass $writerActive -Name 'refresh writer running and warmed up (it draws every published update)' -Evidence ('active = {0}' -f $writerActive)
    if ($addTimes.Count -gt 0) {
        $addMax = [double]($addTimes | Measure-Object -Maximum).Maximum
        Add-CostLine ('Add-TpmProgressTask x{0} (each draws its new row inline): max {1} ms; {2}' -f $addTimes.Count, (Format-CostMs $addMax), (@($addTimes | ForEach-Object { Format-CostMs $_ }) -join ', '))
        if ($stallRan) { Add-CostResult -Pass ($addMax -le 50.0) -Name 'Add-TpmProgressTask <= 50 ms with a warm console' -Evidence ('max {0} ms' -f (Format-CostMs $addMax)) }
    }
    foreach ($entry in @(@('Set-TpmProgressTask', $taskStats, $taskFirst), @('Set-TpmProgressStage', $stageStats, $stageFirst))) {
        $stats = $entry[1]
        Add-CostLine ('{0} x{1}: avg {2} ms, p95 {3} ms, max {4} ms (first call {5} ms; {6} warm-up calls not measured)' -f $entry[0], $stats.Count,
            (Format-CostMs $stats.Average), (Format-CostMs $stats.P95), (Format-CostMs $stats.Max), (Format-CostMs $entry[2]), $warmup)
        Add-CostResult -Pass ($stats.Average -lt 1.0) -Name ('{0} average < 1.0 ms' -f $entry[0]) -Evidence ('{0} ms' -f (Format-CostMs $stats.Average))
        Add-CostResult -Pass ($stats.P95 -lt 5.0) -Name ('{0} p95 < 5 ms' -f $entry[0]) -Evidence ('{0} ms' -f (Format-CostMs $stats.P95))
    }
    if ($null -ne $frameStats) {
        Add-CostLine ('Forced frame ({0} rows) x{1}: avg {2} ms, p95 {3} ms, max {4} ms; refresh writer last frame {5} ms, frame interval {6} ms' -f
            (1 + $descriptions.Count), $frameStats.Count, (Format-CostMs $frameStats.Average), (Format-CostMs $frameStats.P95), (Format-CostMs $frameStats.Max),
            (Format-CostMs $writerCost), (Format-CostMs $interval))
    }
    Add-CostResult -Pass ($frameMissed -eq 0 -and $null -ne $frameStats) -Name 'every forced frame was drawn' -Evidence ('{0} of {1} forced frames not drawn' -f $frameMissed, $frameSamples)
    Add-CostResult -Pass ($null -ne $frameStats -and $frameStats.Average -le 20.0) -Name 'frame average <= 20 ms' -Evidence $(if ($null -ne $frameStats) { '{0} ms' -f (Format-CostMs $frameStats.Average) } else { 'no frame measured' })

    if ($null -eq $region) {
        Add-CostResult -Pass $false -Name 'rows rendered' -Evidence 'marker line not found on screen'
    } else {
        $rows = [string[]]$region
        $expectedRows = 1 + $descriptions.Count
        Add-CostResult -Pass ($rows.Count -eq $expectedRows) -Name 'row count' -Evidence ('{0} display rows, expected {1}' -f $rows.Count, $expectedRows)
        $expected = @(@{ Description = $opTitle; Count = $stageCount })
        for ($i = 0; $i -lt $descriptions.Count; $i++) { $expected += @{ Description = $descriptions[$i]; Count = $taskCounts[$i] } }
        foreach ($target in $expected) {
            $index = @(Find-ConsoleBufferRows -Region $rows -Description $target.Description)
            if ($index.Count -ne 1) {
                Add-CostResult -Pass $false -Name ('row ' + $target.Description) -Evidence ('found {0} times (expected exactly once)' -f $index.Count)
                continue
            }
            $text = $rows[$index[0]]
            $pass = ($text -match ('(^|\D){0}/1000(\D|$)' -f $target.Count))
            Add-CostResult -Pass $pass -Name ('row ' + $target.Description) -Evidence ('expected {0}/1000; row: {1}' -f $target.Count, $text.Trim())
        }
        if ($script:CostFailures -gt 0) {
            Add-CostLine 'Display as read from the screen:'
            foreach ($row in $rows) { Add-CostLine ('  ' + $row) }
        }
    }
}
Add-CostLine $(if ($script:CostFailures -gt 0) { 'RESULT: FAIL ({0} check(s) failed)' -f $script:CostFailures } else { 'RESULT: PASS' })

Write-Host ''
foreach ($line in $script:CostLines) { Write-Host $line }
if (-not [string]::IsNullOrWhiteSpace($ResultPath)) {
    try { Set-Content -LiteralPath $ResultPath -Value $script:CostLines.ToArray() -Encoding ASCII -ErrorAction Stop }
    catch {
        Write-Host ('Could not write the result file {0}: {1}' -f $ResultPath, $_.Exception.Message)
        exit 1
    }
}
if ($script:CostFailures -gt 0) { exit 1 }
exit 0
