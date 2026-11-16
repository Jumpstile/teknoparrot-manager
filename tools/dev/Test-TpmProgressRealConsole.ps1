#Requires -Version 5.1
# Dev-only real-console self-check for the live progress display; this script is not part of the release package.
# Run it in a normal Windows Terminal or conhost window (output not redirected, at least 100 columns and 20 rows).
# It opens one operation with six tasks at known percents, lets the background refresh run, reads the screen back
# with $Host.UI.RawUI.GetBufferContents and prints PASS/FAIL lines with evidence:
#   - the expected row count, each description exactly once (no stacked frames),
#   - each known-percent row's whole fill cells within one cell of the expected count,
#   - counters advanced from the first frame, and elapsed text advanced while ONLY the refresh writer was running,
#   - the print-hook line complete at column 0 above the bars.
# Exit code 0 when every check passes, 1 otherwise. The console buffer and window size are never changed.
param([ValidateRange(2, 30)][int]$RefreshSeconds = 2)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:SelfCheckFailures = 0
$script:SelfCheckResults = New-Object System.Collections.Generic.List[string]

function Add-SelfCheckResult {
    param([bool]$Pass, [string]$Name, [string]$Evidence)
    if (-not $Pass) { $script:SelfCheckFailures++ }
    $word = if ($Pass) { 'PASS' } else { 'FAIL' }
    [void]$script:SelfCheckResults.Add(('{0} {1}: {2}' -f $word, $Name, $Evidence))
}

. (Join-Path $PSScriptRoot 'TpmConsoleBuffer.ps1')

function Get-SelfCheckFill {
    # Whole fill cells and track width of the first framed bar in a row, or $null when no bar is visible.
    param([string]$Row)
    $bar = [regex]::Match($Row, '\|([^|]{6,})\|')
    if (-not $bar.Success) { return $null }
    $inner = $bar.Groups[1].Value
    $fillChars = @('#', [string][char]0x2588, [string][char]0x2501)
    $whole = @($inner.ToCharArray() | Where-Object { $fillChars -contains [string]$_ }).Count
    return [pscustomobject]@{ Whole = $whole; Inner = $inner.Length; Text = $inner }
}

function Get-SelfCheckElapsed {
    param([string]$Row)
    $match = [regex]::Match($Row, 'in (\d+\.\d)s')
    if (-not $match.Success) { return $null }
    return [double]::Parse($match.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture)
}

$modulePath = Join-Path $PSScriptRoot '..\..\scripts\TpmProgress.psm1'
$marker = 'TPM-PROGRESS-SELFCHECK ' + ([guid]::NewGuid().ToString('N').Substring(0, 8))
$hookText = 'Print-hook line from the self-check: it must stay complete above the bars'
$opTitle = 'TPM self-check'
$percents = @(0, 10, 25, 50, 75, 90)
$descriptions = @($percents | ForEach-Object { 'Check task at {0:00} percent' -f $_ })
$reserve = 14
$aborted = $null
$snapshots = @{}
$active = $false

try {
    if ([Console]::IsOutputRedirected) { throw 'Output is redirected. Run this script in a real Windows Terminal or conhost window.' }
    $raw = $Host.UI.RawUI
    if ([int]$raw.WindowSize.Width -lt 100) { throw ('The window is {0} columns wide; at least 100 are needed.' -f $raw.WindowSize.Width) }
    if ([int]$raw.WindowSize.Height -lt ($reserve + 6)) { throw ('The window is {0} rows high; at least {1} are needed.' -f $raw.WindowSize.Height, ($reserve + 6)) }
    try { [void](Read-ConsoleBufferRows -From 0 -To 0) } catch { throw ('The screen cannot be read with GetBufferContents: ' + $_.Exception.Message) }

    # Reserve rows below the cursor so the display never scrolls the marker away (the window may be the whole buffer).
    if ([Console]::CursorLeft -gt 0) { [Console]::WriteLine() }
    for ($i = 0; $i -lt $reserve; $i++) { [Console]::WriteLine() }
    [Console]::SetCursorPosition(0, [Console]::CursorTop - $reserve)
    Write-Host $marker
    $markerRow = [Console]::CursorTop - 1

    Get-Module -Name TpmProgress -All | Remove-Module -Force
    Import-Module $modulePath -Force -ErrorAction Stop
    $null = Start-TpmProgressOperation -Title $opTitle -Stage 'Counting' -Total 1000
    Set-TpmProgressStage -Stage 'Counting' -Current 10 -Total 1000
    for ($i = 0; $i -lt $percents.Count; $i++) {
        $id = Add-TpmProgressTask -Description $descriptions[$i] -Total 100
        Set-TpmProgressTask -Id $id -Current $percents[$i]
    }
    Start-Sleep -Milliseconds 300
    $snapshots.First = Get-ConsoleBufferRegion -Marker $marker -MarkerRow $markerRow -Reserve $reserve
    Start-Sleep -Milliseconds 700
    Set-TpmProgressStage -Stage 'Counting' -Current 600 -Total 1000
    $suspended = Suspend-TpmProgressOutput
    try { Write-Host $hookText }
    finally { if ($suspended) { Resume-TpmProgressOutput } }
    Start-Sleep -Milliseconds 150
    $snapshots.AfterHook = Get-ConsoleBufferRegion -Marker $marker -MarkerRow $markerRow -Reserve $reserve
    # No progress call from here on: only the background refresh writer can change the screen.
    Start-Sleep -Milliseconds ([Math]::Max(1000, ($RefreshSeconds * 1000) - 1150))
    $active = [bool](Test-TpmProgressActive)
    $snapshots.Final = Get-ConsoleBufferRegion -Marker $marker -MarkerRow $markerRow -Reserve $reserve
    Complete-TpmProgressOperation -State Incomplete -Message 'self-check finished'
} catch {
    $aborted = $_.Exception.Message
} finally {
    try {
        if ((Get-Command Test-TpmProgressActive -ErrorAction SilentlyContinue) -and (Test-TpmProgressActive)) { Stop-TpmProgressAbandoned }
    } catch {}
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($null -ne $aborted) {
    Add-SelfCheckResult -Pass $false -Name 'run' -Evidence $aborted
} else {
    $expectedRows = 1 + $descriptions.Count
    Add-SelfCheckResult -Pass $active -Name 'display still active after the refresh period' -Evidence ('Test-TpmProgressActive = {0}' -f $active)
    foreach ($name in @('First', 'AfterHook', 'Final')) {
        if ($null -eq $snapshots[$name]) { Add-SelfCheckResult -Pass $false -Name ('screen read ' + $name) -Evidence 'marker line not found on screen' }
    }
    if ($null -ne $snapshots.First -and $null -ne $snapshots.AfterHook -and $null -ne $snapshots.Final) {
        $final = [string[]]$snapshots.Final
        $first = [string[]]$snapshots.First

        # Row count and stacking: every description exactly once, nothing else but the print-hook line.
        foreach ($pair in @(@('First', $first), @('Final', $final))) {
            $region = [string[]]$pair[1]
            $hookRows = @(for ($i = 0; $i -lt $region.Count; $i++) { if ($region[$i] -eq $hookText) { $i } })
            $displayRows = $region.Count - $hookRows.Count
            Add-SelfCheckResult -Pass ($displayRows -eq $expectedRows) -Name ('row count ({0} frame)' -f $pair[0]) -Evidence ('{0} display rows, expected {1}' -f $displayRows, $expectedRows)
            $duplicates = @(foreach ($description in (@($opTitle) + $descriptions)) {
                $count = @(Find-ConsoleBufferRows -Region $region -Description $description).Count
                if ($count -ne 1) { '{0} x{1}' -f $description, $count }
            })
            Add-SelfCheckResult -Pass ($duplicates.Count -eq 0) -Name ('no stacked frames ({0} frame)' -f $pair[0]) -Evidence $(if ($duplicates.Count -eq 0) { 'each row appears exactly once' } else { $duplicates -join '; ' })
        }

        # Fill proportionality on the final frame (running rows cap at 99 percent).
        $fillTargets = @(@{ Description = $opTitle; Percent = 60 })
        for ($i = 0; $i -lt $percents.Count; $i++) { $fillTargets += @{ Description = $descriptions[$i]; Percent = $percents[$i] } }
        foreach ($target in $fillTargets) {
            $index = @(Find-ConsoleBufferRows -Region $final -Description $target.Description)
            if ($index.Count -ne 1) { Add-SelfCheckResult -Pass $false -Name ('fill ' + $target.Description) -Evidence 'row not found exactly once'; continue }
            $fill = Get-SelfCheckFill -Row $final[$index[0]]
            if ($null -eq $fill) { Add-SelfCheckResult -Pass $false -Name ('fill ' + $target.Description) -Evidence ('no bar in row: ' + $final[$index[0]]); continue }
            $expected = [int][Math]::Floor(([Math]::Min([double]99, [double]$target.Percent) / 100.0) * $fill.Inner)
            $pass = ([Math]::Abs($fill.Whole - $expected) -le 1)
            Add-SelfCheckResult -Pass $pass -Name ('fill ' + $target.Description) -Evidence ('{0} of {1} cells filled, expected {2} (+/-1); bar [{3}]' -f $fill.Whole, $fill.Inner, $expected, $fill.Text)
        }

        # Counters advanced from the first frame.
        $firstOp = @(Find-ConsoleBufferRows -Region $first -Description $opTitle)
        $finalOp = @(Find-ConsoleBufferRows -Region $final -Description $opTitle)
        $firstCount = if ($firstOp.Count -eq 1 -and $first[$firstOp[0]] -match '(\d+)/1000') { [int]$Matches[1] } else { -1 }
        $finalCount = if ($finalOp.Count -eq 1 -and $final[$finalOp[0]] -match '(\d+)/1000') { [int]$Matches[1] } else { -1 }
        Add-SelfCheckResult -Pass ($firstCount -eq 10 -and $finalCount -eq 600) -Name 'counter advanced from the first frame' -Evidence ('first frame {0}/1000, final frame {1}/1000 (expected 10 then 600)' -f $firstCount, $finalCount)

        # Elapsed text advanced while no progress call was made (proves the background refresh is drawing).
        $afterHook = [string[]]$snapshots.AfterHook
        $probe = $descriptions[3]
        $hookIndex = @(Find-ConsoleBufferRows -Region $afterHook -Description $probe)
        $finalIndex = @(Find-ConsoleBufferRows -Region $final -Description $probe)
        $before = if ($hookIndex.Count -eq 1) { Get-SelfCheckElapsed -Row $afterHook[$hookIndex[0]] } else { $null }
        $after = if ($finalIndex.Count -eq 1) { Get-SelfCheckElapsed -Row $final[$finalIndex[0]] } else { $null }
        $advanced = ($null -ne $before -and $null -ne $after -and ($after - $before) -ge 0.5)
        Add-SelfCheckResult -Pass $advanced -Name 'background refresh redrew without progress calls' -Evidence ('elapsed of "{0}": {1}s after the hook, {2}s at the end' -f $probe, $before, $after)

        # Print-hook line complete, at column 0, above the bars.
        $hookRows = @(for ($i = 0; $i -lt $final.Count; $i++) { if ($final[$i] -eq $hookText) { $i } })
        $firstDisplay = if ($finalOp.Count -eq 1) { $finalOp[0] } else { -1 }
        $hookPass = ($hookRows.Count -eq 1 -and $firstDisplay -ge 0 -and $hookRows[0] -lt $firstDisplay)
        $hookEvidence = if ($hookRows.Count -eq 1) { 'hook row {0}, first display row {1}' -f $hookRows[0], $firstDisplay } else {
            'complete hook line found {0} times; rows: {1}' -f $hookRows.Count, (@($final | Where-Object { $_ -match 'hook' }) -join ' | ')
        }
        Add-SelfCheckResult -Pass $hookPass -Name 'print-hook line above the bars' -Evidence $hookEvidence

        if ($script:SelfCheckFailures -gt 0) {
            [void]$script:SelfCheckResults.Add('Final frame as read from the screen:')
            foreach ($row in $final) { [void]$script:SelfCheckResults.Add('  ' + $row) }
        }
    }
}

foreach ($line in $script:SelfCheckResults) { Write-Host $line }
if ($script:SelfCheckFailures -gt 0) {
    Write-Host ('RESULT: FAIL ({0} check(s) failed)' -f $script:SelfCheckFailures)
    exit 1
}
Write-Host 'RESULT: PASS'
exit 0
