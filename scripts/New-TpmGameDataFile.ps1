<#
Builds the game-rules data file (TpmGameRulesV1) for one release from scripts\TpmGameSupportDecisions.json.
Owner tool. Run it, then sign the result with scripts\Sign-TpmGameData.ps1. It reads one file and writes one file; nothing else.

What goes in (data only; see docs\GAME-RULES-UPDATE.md):
  Games       one row per game whose decision is guided / needs-own-archive / not-supported / register-only (a short plain reason).
              Decisions that TPM backs with code (tpm-applies-patch, tpm-checks-files, tpm-warns) are NOT included: data cannot add code.
  GpuWarnings the games the decisions file marks as not working on a graphics card maker (Status NO, Action warning).
Rows that do not pass the same plain-text rules TPM enforces are skipped and listed, never silently changed.
The file is written as ASCII with LF line endings and no BOM, exactly the bytes that get signed.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateRange(1, 100000000)][int]$Version,
    [string]$DecisionsPath = '',
    [string]$OutputPath = '',
    [string]$PreviousPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($DecisionsPath)) { $DecisionsPath = Join-Path $PSScriptRoot 'TpmGameSupportDecisions.json' }
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'game-data\TpmGameRules.json' }

$profilePattern = '^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$'
$dataDispositions = @('guided', 'needs-own-archive', 'not-supported', 'register-only')
$vendors = @('AMD', 'Intel', 'NVIDIA')

$decisions = Get-Content -LiteralPath $DecisionsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$games = New-Object System.Collections.Generic.List[object]
$gpu = New-Object System.Collections.Generic.List[object]
$skipped = New-Object System.Collections.Generic.List[string]
$seenGame = New-Object 'System.Collections.Generic.HashSet[string]'
$seenGpu = New-Object 'System.Collections.Generic.HashSet[string]'

foreach ($row in @($decisions.Profiles)) {
    if ([string]$row.Disposition -cnotin $dataDispositions) { continue }
    $name = [string]$row.Profile
    $reason = [string]$row.Reason
    if (-not [regex]::IsMatch($name, $profilePattern) -or -not [regex]::IsMatch($reason, '^[\x20-\x7E]{1,300}$') -or -not $seenGame.Add($name.ToLowerInvariant())) {
        [void]$skipped.Add("Games: $name"); continue
    }
    $games.Add([ordered]@{ Profile = $name; Disposition = [string]$row.Disposition; Reason = $reason })
}
foreach ($row in @($decisions.Graphics)) {
    if ([string]$row.Status -cne 'NO' -or [string]$row.Action -cne 'warning') { continue }
    $name = [string]$row.Profile
    $vendor = [string]$row.Vendor
    if ($vendor -cnotin $vendors -or -not [regex]::IsMatch($name, $profilePattern) -or -not $seenGpu.Add(($vendor + '|' + $name.ToLowerInvariant()))) {
        [void]$skipped.Add("GpuWarnings: $vendor $name"); continue
    }
    $gpu.Add([ordered]@{ Profile = $name; Vendor = $vendor })
}

$sortedGames = @($games | Sort-Object { $_.Profile }, { $_.Disposition })
$sortedGpu = @($gpu | Sort-Object { $_.Vendor }, { $_.Profile })
$document = [ordered]@{ Format = 'TpmGameRulesV1'; Version = $Version; Games = $sortedGames; GpuWarnings = $sortedGpu }
$json = (ConvertTo-Json -InputObject $document -Depth 6) -replace "`r`n", "`n"
if (-not $json.EndsWith("`n")) { $json += "`n" }
if ($json -cmatch '[^\x09\x0A\x20-\x7E]') { throw 'The built file holds a character outside plain ASCII; nothing was written.' }

$outDir = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outDir)) { [void][System.IO.Directory]::CreateDirectory($outDir) }
[System.IO.File]::WriteAllBytes($OutputPath, [System.Text.Encoding]::ASCII.GetBytes($json))

Write-Host ("Wrote {0}: version {1}, {2} game rows, {3} graphics warnings." -f $OutputPath, $Version, $sortedGames.Count, $sortedGpu.Count)
foreach ($item in $skipped) { Write-Host "  skipped (not plain text or duplicate): $item" }
if (-not [string]::IsNullOrWhiteSpace($PreviousPath) -and (Test-Path -LiteralPath $PreviousPath -PathType Leaf)) {
    $previous = Get-Content -LiteralPath $PreviousPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int64]$previous.Version -ge $Version) { Write-Warning "The previous file is version $($previous.Version); TPM only accepts a higher version than the one in use." }
    $before = @{}; foreach ($row in @($previous.Games)) { $before[[string]$row.Profile] = "$($row.Disposition)|$($row.Reason)" }
    $added = 0; $changed = 0
    foreach ($row in $sortedGames) {
        if (-not $before.ContainsKey($row.Profile)) { $added++ } elseif ($before[$row.Profile] -cne "$($row.Disposition)|$($row.Reason)") { $changed++ }
    }
    $nowNames = @{}; foreach ($row in $sortedGames) { $nowNames[$row.Profile] = $true }
    $removed = @($before.Keys | Where-Object { -not $nowNames.ContainsKey($_) }).Count
    Write-Host ("Compared with version {0}: {1} added, {2} changed, {3} removed." -f $previous.Version, $added, $changed, $removed)
}
Write-Host 'Next: sign it with scripts\Sign-TpmGameData.ps1 (the private key stays outside the repository).'
