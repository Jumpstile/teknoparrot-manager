# Dev-only console-buffer helpers shared by Measure-TpmProgressCost.ps1 and Test-TpmProgressRealConsole.ps1 (dot-sourced; not part of the release package).

function Read-ConsoleBufferRows {
    # Text of buffer rows From..To (inclusive). Trailing halves of wide cells are skipped.
    param([int]$From, [int]$To)
    $raw = $Host.UI.RawUI
    $width = [int]$raw.BufferSize.Width
    $rect = New-Object System.Management.Automation.Host.Rectangle -ArgumentList 0, $From, ($width - 1), $To
    $cells = $raw.GetBufferContents($rect)
    $rows = New-Object System.Collections.Generic.List[string]
    for ($r = 0; $r -le $cells.GetUpperBound(0); $r++) {
        $line = New-Object System.Text.StringBuilder
        for ($c = 0; $c -le $cells.GetUpperBound(1); $c++) {
            $cell = $cells[$r, $c]
            if ($cell.BufferCellType -eq [System.Management.Automation.Host.BufferCellType]::Trailing) { continue }
            [void]$line.Append($cell.Character)
        }
        [void]$rows.Add($line.ToString().TrimEnd())
    }
    return ,$rows.ToArray()
}

function Get-ConsoleBufferRegion {
    # Rows after the marker line up to the first blank row: the live display.
    param([string]$Marker, [int]$MarkerRow, [int]$Reserve)
    $bufferHeight = [int]$Host.UI.RawUI.BufferSize.Height
    $from = [Math]::Max(0, $MarkerRow - $Reserve)
    $to = [Math]::Min($bufferHeight - 1, $MarkerRow + $Reserve)
    $rows = Read-ConsoleBufferRows -From $from -To $to
    $start = -1
    for ($i = 0; $i -lt $rows.Count; $i++) { if ($rows[$i] -eq $Marker) { $start = $i } }
    if ($start -lt 0) { return $null }
    $region = New-Object System.Collections.Generic.List[string]
    for ($i = $start + 1; $i -lt $rows.Count; $i++) {
        if ([string]::IsNullOrEmpty($rows[$i])) { break }
        [void]$region.Add($rows[$i])
    }
    return ,$region.ToArray()
}

function Find-ConsoleBufferRows {
    # The operation row reads "<title>: <stage>", task rows "<description>" followed by the bar.
    param([string[]]$Region, [string]$Description)
    $pattern = '(^|\s)' + [regex]::Escape($Description) + '(:|\s|$)'
    return @(for ($i = 0; $i -lt $Region.Count; $i++) { if ($Region[$i] -match $pattern) { $i } })
}
