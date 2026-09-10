[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$ReportPath,
    [string]$SourcePath = '',
    [datetime]$ChangedAtUtc = [datetime]::MinValue,
    [switch]$AllowMissingReport
)
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$failures = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { [void]$failures.Add($Message) }
$repo = [IO.Path]::GetFullPath($RepoRoot)
$registryPath = Join-Path $repo 'quality\permanent-procedures.json'
if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) { Fail "Missing registry: $registryPath" }
$controlBoardPath = Join-Path $repo 'docs\remediation\PR-321-control-board.md'
$sliceTemplatePath = Join-Path $repo 'docs\templates\tpm-slice-contract.md'
$currentSlicePath = Join-Path $repo 'docs\remediation\slices\PR-321-current-slice.md'
foreach ($requiredArtifact in @($controlBoardPath,$sliceTemplatePath,$currentSlicePath)) {
    if (-not (Test-Path -LiteralPath $requiredArtifact -PathType Leaf)) { Fail "Missing TPM governance artifact: $requiredArtifact" }
}
if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
    if (-not $AllowMissingReport) { Fail "Missing remediation report: $ReportPath" }
} else {
    $report = Get-Content -LiteralPath $ReportPath -Raw -ErrorAction Stop
    if ((Get-Content -LiteralPath $controlBoardPath -Raw).IndexOf('## Owner report table', [StringComparison]::OrdinalIgnoreCase) -lt 0) { Fail 'Control board is missing the owner report table.' }
    if ($report.IndexOf('PR-321-control-board.md', [StringComparison]::OrdinalIgnoreCase) -lt 0) { Fail 'Remediation report does not reference the control board.' }
    $board = Get-Content -LiteralPath $controlBoardPath -Raw
    $reportIds = [regex]::Matches($report, '(?im)^\|\s*(\d+)\s*\|') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    foreach ($id in $reportIds) {
        if ($board -notmatch ("(?im)^\|\s*" + [regex]::Escape($id) + '(\s*\||-)')) { Fail "Owner report ID $id is missing from the control board." }
    }
    $slice = Get-Content -LiteralPath $currentSlicePath -Raw
    foreach ($requiredSliceText in @('Explicit exclusions','Stop condition','Forbidden actions','Runtime proof required','Prompt inventory and classification')) {
        if ($slice.IndexOf($requiredSliceText, [StringComparison]::OrdinalIgnoreCase) -lt 0) { Fail "Current slice is missing: $requiredSliceText" }
    }
    $requiredSections = @(
        '## Provenance','## Owner report mapping table','## SCRIPT-WIDE UNIVERSAL PROGRESS BAR AUDIT',
        '## Prompt/gate/back-routing consistency audit','## Affected-games repair-flow scoping audit',
        '## Support package/fatal surfacing audit','## Tests with exact counts and timestamps',
        '## Static gates','## Hunk classification','## Permanent procedure compliance',
        '## Non-actions','## Runtime owner-smoke checklist'
    )
    foreach ($section in $requiredSections) { if ($report.IndexOf($section, [StringComparison]::OrdinalIgnoreCase) -lt 0) { Fail "Report missing required section: $section" } }
    $allowed = @('FIXED + TESTED','SOURCE FIXED; OWNER RUNTIME NEEDED','NOT FIXED','DEFERRED BY OWNER')
    $ownerStart = $report.IndexOf('## Owner report mapping table')
    $ownerEnd = $report.IndexOf('## SCRIPT-WIDE UNIVERSAL PROGRESS BAR AUDIT')
    $ownerSection = if ($ownerStart -ge 0 -and $ownerEnd -gt $ownerStart) { $report.Substring($ownerStart, $ownerEnd - $ownerStart) } else { '' }
    $sliceIdMatch = [regex]::Match($slice, '(?im)^\s*-\s*Slice ID:\s*(\S+)')
    if (-not $sliceIdMatch.Success) {
        Fail 'Current slice does not declare a Slice ID.'
    } elseif ($report.IndexOf($sliceIdMatch.Groups[1].Value, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        Fail 'Remediation report hunk classification does not reference the current slice contract.'
    }
    if ($report -match '(?im)## Tests with exact counts and timestamps[\s\S]*Main Pester[^|]*\|[^|]*\|\s*[^|]*\|\s*[^|]*\|\s*[^|]*\|') {
        if ($ownerSection -notmatch '(?i)Exact test names') { Fail 'Broad suite counts are not accompanied by focused owner test names.' }
    }
    $statusMatches = [regex]::Matches($ownerSection, '(?im)^\|\s*\d+\s*\|[^|]*\|\s*([^|]+?)\s*\|')
    if ($statusMatches.Count -eq 0) { Fail 'Owner report mapping contains no numbered status rows.' }
    foreach ($match in $statusMatches) {
        $status = $match.Groups[1].Value.Trim()
        if ($allowed -notcontains $status) { Fail "Invalid owner report status: $status" }
    }
    if ($ownerSection -match '(?im)\|\s*NOT FIXED\s*\|') { Fail 'Owner report contains unresolved NOT FIXED items.' }
    if ($ownerSection -match '(?im)\|\s*SOURCE FIXED; OWNER RUNTIME NEEDED\s*\|') { Fail 'Owner-runtime evidence remains outstanding.' }
    if ($report -match '(?im)candidate[^.\r\n]*(predates|stale)') { Fail 'Candidate package is stale relative to source changes.' }
    foreach ($word in @('addressed','improved','mostly','done-ish','should be fixed','probably')) {
        if ($report -match ('(?i)\b' + [regex]::Escape($word) + '\b')) { Fail "Vague status language is forbidden: $word" }
    }
    $progressSection = $report.Substring($report.IndexOf('## SCRIPT-WIDE UNIVERSAL PROGRESS BAR AUDIT'))
    foreach ($path in @('AutoSync scan','AutoSync extraction','AutoSync registration/import','AutoSync copy/move','Library Health Check repair search','Library Health Check affected-games re-copy/re-extract','GPU Fix','Thumbnail','DAT','Eggman game data','ProfileSet','Startup update','updater download','dgVoodoo2','ReShade','FFB','backup','restore','support package','LaunchBox')) {
        if ($progressSection.IndexOf($path, [StringComparison]::OrdinalIgnoreCase) -lt 0) { Fail "Progress audit missing required path: $path" }
    }
    if ($progressSection -match '(?i)incomplete[^\r\n]*CONVERTED TO UNIVERSAL TPM PROGRESS|CONVERTED TO UNIVERSAL TPM PROGRESS[^\r\n]*incomplete') { Fail 'Incomplete progress path is labeled converted.' }
    $promptSection = $report.Substring($report.IndexOf('## Prompt/gate/back-routing consistency audit'))
    foreach ($path in @('Y/N','Invalid input','Back','Skip','Cancel','Preview/Run','Mutation confirmation','Optional setup gates','Support package prompts')) { if ($promptSection.IndexOf($path, [StringComparison]::OrdinalIgnoreCase) -lt 0) { Fail "Prompt audit missing: $path" } }
    $repairSection = $report.Substring($report.IndexOf('## Affected-games repair-flow scoping audit'))
    foreach ($path in @('one','multiple','zero','no-candidate','Back','thumbnails','LaunchBox','HyperSpin','controls')) { if ($repairSection.IndexOf($path, [StringComparison]::OrdinalIgnoreCase) -lt 0) { Fail "Repair audit missing evidence: $path" } }
    if ($repairSection -match '(?i)BBHWorld\s*=') { Fail 'Affected-games repair audit reports a BBHWorld hardcode.' }
    $supportSection = $report.Substring($report.IndexOf('## Support package/fatal surfacing audit'))
    foreach ($path in @('fatal','newest Action Required','stale','final prompt')) { if ($supportSection.IndexOf($path, [StringComparison]::OrdinalIgnoreCase) -lt 0) { Fail "Support audit missing: $path" } }
    $progressStart = $report.IndexOf('## SCRIPT-WIDE UNIVERSAL PROGRESS BAR AUDIT')
    $progressEnd = $report.IndexOf('## Prompt/gate/back-routing consistency audit')
    $progressSection = if ($progressStart -ge 0 -and $progressEnd -gt $progressStart) { $report.Substring($progressStart, $progressEnd - $progressStart) } else { '' }
    foreach ($path in @(
        'AutoSync scan','AutoSync extraction','AutoSync registration/import',
        'AutoSync copy/move operations','Library Health Check repair search',
        'Library Health Check affected-games re-copy/re-extract','GPU Fix web/check/download',
        'Shared download tiers','Thumbnail checks/downloads','DAT checks/downloads',
        'Eggman game data fetch','ProfileSet GitHub/default-branch query',
        'Startup update check','updater download','dgVoodoo2 download/check/deploy',
        'ReShade download/check/signature/preview loading','FFB/network/download checks',
        'Backup operations','Restore operations','PostgreSQL profile/database setup',
        'Support package collection','LaunchBox export/write','BepInEx package/download/deploy',
        'Crosshair/HyperSpin bounded asset writes'
    )) {
        if ($progressSection.IndexOf($path, [StringComparison]::OrdinalIgnoreCase) -lt 0) { Fail "Progress audit missing path: $path" }
    }
    foreach ($disposition in @('CONVERTED TO UNIVERSAL TPM PROGRESS','NOT FIXED','JUSTIFIED NO PROGRESS SURFACE')) {
        if ($progressSection.IndexOf($disposition, [StringComparison]::OrdinalIgnoreCase) -lt 0) { Fail "Progress audit missing disposition: $disposition" }
    }
    $consistencyStart = $report.IndexOf('## Prompt/gate/back-routing consistency audit')
    $consistencyEnd = $report.IndexOf('## Affected-games repair-flow scoping audit')
    $consistencySection = if ($consistencyStart -ge 0 -and $consistencyEnd -gt $consistencyStart) { $report.Substring($consistencyStart, $consistencyEnd - $consistencyStart) } else { '' }
    foreach ($pattern in @('Y/N','Invalid input','Back','Skip','Cancel','Preview/Run','Mutation confirmation','Optional setup gates','HyperSpin direct prompts','Support package prompts')) {
        if ($consistencySection.IndexOf("| $pattern |", [StringComparison]::OrdinalIgnoreCase) -lt 0) { Fail "Consistency audit missing pattern: $pattern" }
    }
    $nonActions = $report.Substring($report.IndexOf('## Non-actions'))
    foreach ($action in @('commit','push','package','wiki','release','certification','ARCADE')) { if ($nonActions.IndexOf($action, [StringComparison]::OrdinalIgnoreCase) -lt 0) { Fail "Non-actions section omits: $action" } }
    if ($report -notmatch '(?i)InjectionHunter (unavailable in this environment; no InjectionHunter result claimed\.|[0-9]+ findings, 0 unresolved)') { Fail 'InjectionHunter evidence wording is missing.' }
    if ($ChangedAtUtc -ne [datetime]::MinValue) {
        $testsSection = $report.Substring($report.IndexOf('## Tests with exact counts and timestamps'))
        $times = [regex]::Matches($testsSection, '\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}')
        if ($times.Count -eq 0) { Fail 'Validation timestamps are missing.' }
        foreach ($file in @($ReportPath,$SourcePath)) {
            if ($file -and (Test-Path -LiteralPath $file -PathType Leaf) -and (Get-Item -LiteralPath $file).LastWriteTimeUtc -gt $ChangedAtUtc) { Fail "Evidence/report is newer than supplied ChangedAtUtc but validation freshness is not proven: $file" }
        }
    }
}
if (Test-Path -LiteralPath $registryPath -PathType Leaf) {
    try { $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json; foreach ($entry in @($registry.procedures)) { foreach ($property in @('id','rule','enforcementType','requiredEvidence','failureMessage')) { if (-not $entry.PSObject.Properties[$property] -or [string]::IsNullOrWhiteSpace([string]$entry.$property)) { Fail "Registry entry is incomplete: $($entry.id) / $property" } } } } catch { Fail "Registry JSON is invalid: $($_.Exception.Message)" }
}
if ($SourcePath -and (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    $source = Get-Content -LiteralPath $SourcePath -Raw
    if ($source -match '(?im)^\s*Write-Progress\b') { Fail 'Production source contains Write-Progress.' }
    if ($source -match '(?i)Scanning\s+[^\r\n]*--\s*\d+\s*/\s*\d+') { Fail 'Production source contains a legacy scan progress string.' }
    if ($source -match '(?i)Checking Thumbnails via Invoke-WebRequest') { Fail 'Production source contains legacy thumbnail progress text.' }
}
if ($failures.Count -gt 0) { Write-Error (($failures | ForEach-Object { "PERMANENT PROCEDURE GATE FAIL: $_" }) -join [Environment]::NewLine); exit 1 }
Write-Output 'Permanent procedure gate passed.'
exit 0
