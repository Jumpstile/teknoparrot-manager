#Requires -Version 5.1
# Dev-only visual sample; this script is not part of the release package.
param([switch]$Plain, [switch]$Quantized)

if ($Plain -and $Quantized) { throw 'Choose either -Plain or -Quantized, not both.' }
$oldPlain = $env:TPM_PROGRESS_PLAIN
$oldColor = $env:TPM_PROGRESS_COLOR
try {
    if ($Plain) { $env:TPM_PROGRESS_PLAIN = '1' }
    if ($Quantized) { $env:TPM_PROGRESS_COLOR = 'quantized' }
    Import-Module (Join-Path $PSScriptRoot '..\..\scripts\TpmProgress.psm1') -Force -ErrorAction Stop
    $null = Start-TpmProgressOperation -Title 'Unknown bouncing' -Stage 'Scanning' -Total 0
    $running = @{}
    foreach ($percent in @(0, 25, 50, 75, 100)) {
        $label = if ($percent -eq 100) { 'Running 100 units (99% cap)' } else { "Running $percent percent" }
        $running[$percent] = Add-TpmProgressTask -Description $label -Total 100
        Set-TpmProgressTask -Id $running[$percent] -Current $percent
    }
    $done = Add-TpmProgressTask -Description 'Complete' -Total 100
    Set-TpmProgressTask -Id $done -Current 100 -State Final
    $early = Add-TpmProgressTask -Description 'Ended early' -Total 7000
    Set-TpmProgressTask -Id $early -Current 5000 -State Incomplete
    $over = Add-TpmProgressTask -Description 'Overshoot' -Total 4000
    Set-TpmProgressTask -Id $over -Current 5000 -State Error
    $pending = Add-TpmProgressTask -Description 'Pending' -Total 100 -Pending
    $skipped = Add-TpmProgressTask -Description 'Skipped' -Total 100
    Set-TpmProgressTask -Id $skipped -State Skipped
    for ($i = 1; $i -le 30; $i++) {
        Start-Sleep -Milliseconds 100
        Set-TpmProgressStage -Stage 'Scanning' -Current ($i * 23) -Total 0
        if ($i -in @(8, 16, 24)) {
            $suspended = Suspend-TpmProgressOutput
            try { Write-Host ("Print-hook message ${i}: this line stays above the display") }
            finally { if ($suspended) { Resume-TpmProgressOutput } }
        }
    }
    Complete-TpmProgressOperation -State Incomplete
} finally {
    if (Get-Command Test-TpmProgressActive -ErrorAction SilentlyContinue) {
        if (Test-TpmProgressActive) { Stop-TpmProgressAbandoned }
    }
    $env:TPM_PROGRESS_PLAIN = $oldPlain
    $env:TPM_PROGRESS_COLOR = $oldColor
}
