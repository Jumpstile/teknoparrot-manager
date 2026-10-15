[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$ReportPath,
    [string]$SourcePath = '',
    [datetime]$ChangedAtUtc = [datetime]::MinValue,
    [switch]$AllowMissingReport,
    [switch]$RequireOwnerRuntime
)
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$failures = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { [void]$failures.Add($Message) }
function Get-TpmOwnerStatusDisposition {
    param([string]$Status,[string[]]$AllowedStatuses,[hashtable]$Dispositions)
    if ($AllowedStatuses -notcontains $Status) { return 'INVALID' }
    if (-not $Dispositions.ContainsKey($Status)) { return 'INVALID' }
    $disposition = [string]$Dispositions[$Status]
    if (@('CLOSED','OWNER RUNTIME NEEDED','DEFERRED','UNRESOLVED') -notcontains $disposition) { return 'INVALID' }
    return $disposition
}
    $repo = [IO.Path]::GetFullPath($RepoRoot)
    $registryPath = Join-Path $repo 'quality\permanent-procedures.json'
    $registry = $null
    $allowedOwnerStatuses = @()
    $ownerStatusDispositions = @{}
    if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) {
        Fail "Missing registry: $registryPath"
    } else {
        try {
            $registry = Get-Content -LiteralPath $registryPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $allowedOwnerStatuses = @($registry.procedureStatuses | ForEach-Object { [string]$_ })
            $dispositionDefinitions = @($registry.procedureStatusDispositions)
            if ($allowedOwnerStatuses.Count -eq 0) { Fail 'Registry has no procedureStatuses.' }
            if ($dispositionDefinitions.Count -ne $allowedOwnerStatuses.Count) { Fail 'Registry owner-status disposition count does not match procedureStatuses.' }
            foreach ($status in $allowedOwnerStatuses) {
                $definitions = @($dispositionDefinitions | Where-Object { [string]$_.status -ceq $status })
                if ($definitions.Count -ne 1) { Fail "Owner status '$status' must have exactly one disposition."; continue }
                $disposition = [string]$definitions[0].disposition
                if (@('CLOSED','OWNER RUNTIME NEEDED','DEFERRED','UNRESOLVED') -notcontains $disposition) { Fail "Owner status '$status' has invalid disposition '$disposition'."; continue }
                $ownerStatusDispositions[$status] = $disposition
            }
            foreach ($definition in $dispositionDefinitions) {
                $status = [string]$definition.status
                if ([string]::IsNullOrWhiteSpace($status) -or $allowedOwnerStatuses -notcontains $status) { Fail "Owner status disposition refers to unknown status '$status'." }
            }
        } catch {
            Fail "Registry JSON is invalid: $($_.Exception.Message)"
            $registry = $null
            $allowedOwnerStatuses = @()
            $ownerStatusDispositions = @{}
        }
    }
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
        '## Provenance','## Owner report mapping table','## Canonical owner-ID status table -- release decisions',
        '## SCRIPT-WIDE UNIVERSAL PROGRESS BAR AUDIT','## Prompt/gate/back-routing consistency audit','## Affected-games repair-flow scoping audit',
        '## Support package/fatal surfacing audit','## Tests with exact counts and timestamps',
        '## Static gates','## Hunk classification','## Permanent procedure compliance',
        '## Non-actions','## Runtime owner-smoke checklist'
    )
    foreach ($section in $requiredSections) { if ($report.IndexOf($section, [StringComparison]::OrdinalIgnoreCase) -lt 0) { Fail "Report missing required section: $section" } }
    $ownerStart = $report.IndexOf('## Owner report mapping table')
    $ownerEnd = $report.IndexOf('## SCRIPT-WIDE UNIVERSAL PROGRESS BAR AUDIT')
    $ownerMappingSection = if ($ownerStart -ge 0 -and $ownerEnd -gt $ownerStart) { $report.Substring($ownerStart, $ownerEnd - $ownerStart) } else { '' }
    $canonicalOwnerHeader = '## Canonical owner-ID status table -- release decisions'
    $canonicalOwnerStart = $report.IndexOf($canonicalOwnerHeader)
    $canonicalOwnerEnd = if ($canonicalOwnerStart -ge 0) { $report.IndexOf("`n## ", $canonicalOwnerStart + $canonicalOwnerHeader.Length, [StringComparison]::Ordinal) } else { -1 }
    $canonicalOwnerSection = if ($canonicalOwnerStart -ge 0 -and $canonicalOwnerEnd -gt $canonicalOwnerStart) { $report.Substring($canonicalOwnerStart, $canonicalOwnerEnd - $canonicalOwnerStart) } elseif ($canonicalOwnerStart -ge 0) { $report.Substring($canonicalOwnerStart) } else { '' }
    $boardOwnerHeader = '## Owner report table'
    $boardOwnerStart = $board.IndexOf($boardOwnerHeader, [StringComparison]::OrdinalIgnoreCase)
    $boardOwnerEnd = if ($boardOwnerStart -ge 0) { $board.IndexOf("`n## ", $boardOwnerStart + $boardOwnerHeader.Length, [StringComparison]::Ordinal) } else { -1 }
    $boardOwnerSection = if ($boardOwnerStart -ge 0 -and $boardOwnerEnd -gt $boardOwnerStart) { $board.Substring($boardOwnerStart, $boardOwnerEnd - $boardOwnerStart) } elseif ($boardOwnerStart -ge 0) { $board.Substring($boardOwnerStart) } else { '' }
    $boardOwnerIds = @([regex]::Matches($boardOwnerSection, '(?im)^\|\s*(\d+)\s*\|') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $canonicalRowMatches = [regex]::Matches($canonicalOwnerSection, '(?im)^\|\s*(\d+)\s*\|([^\n]*)$')
    $canonicalOwnerIds = @($canonicalRowMatches | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    if ($boardOwnerIds.Count -eq 0) { Fail 'Control board owner report table contains no numbered IDs.' }
    $boardIdCounts = @([regex]::Matches($boardOwnerSection, '(?im)^\|\s*(\d+)\s*\|') | ForEach-Object { $_.Groups[1].Value } | Group-Object | Where-Object { $_.Count -gt 1 })
    $canonicalIdCounts = @($canonicalRowMatches | ForEach-Object { $_.Groups[1].Value } | Group-Object | Where-Object { $_.Count -gt 1 })
    if ($boardIdCounts.Count -gt 0) { Fail ('Control board owner report table contains duplicate IDs: ' + (($boardIdCounts | ForEach-Object { $_.Name }) -join ', ')) }
    if ($canonicalIdCounts.Count -gt 0) { Fail ('Canonical owner-ID status table contains duplicate IDs: ' + (($canonicalIdCounts | ForEach-Object { $_.Name }) -join ', ')) }
    $missingCanonicalIds = @($boardOwnerIds | Where-Object { $canonicalOwnerIds -notcontains $_ })
    $extraCanonicalIds = @($canonicalOwnerIds | Where-Object { $boardOwnerIds -notcontains $_ })
    if ($missingCanonicalIds.Count -gt 0) { Fail ('Canonical owner-ID status table is missing board IDs: ' + ($missingCanonicalIds -join ', ')) }
    if ($extraCanonicalIds.Count -gt 0) { Fail ('Canonical owner-ID status table has IDs absent from the control board: ' + ($extraCanonicalIds -join ', ')) }
    if ($canonicalOwnerSection -notmatch '(?im)^\|\s*ID\s*\|[^|\r\n]*\|[^|\r\n]*\|\s*Corrected status\s*\|') { Fail 'Canonical owner-ID status table must place Corrected status in the fourth column.' }
    $canonicalStatusRows = New-Object System.Collections.Generic.List[object]
    foreach ($rowMatch in $canonicalRowMatches) {
        $cells = $rowMatch.Groups[2].Value.Split('|')
        if ($cells.Count -lt 3 -or [string]::IsNullOrWhiteSpace($cells[2])) {
            Fail "Canonical owner-ID row $($rowMatch.Groups[1].Value) has no corrected status."
            continue
        }
        [void]$canonicalStatusRows.Add([pscustomobject]@{ Id = $rowMatch.Groups[1].Value; Status = $cells[2].Trim() })
    }
    if ($canonicalStatusRows.Count -ne $canonicalRowMatches.Count) { Fail 'Every canonical owner-ID row must contain a corrected status.' }
    $sliceIdMatch = [regex]::Match($slice, '(?im)^\s*-\s*Slice ID:\s*(\S+)')
    if (-not $sliceIdMatch.Success) {
        Fail 'Current slice does not declare a Slice ID.'
    } elseif ($report.IndexOf($sliceIdMatch.Groups[1].Value, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        Fail 'Remediation report hunk classification does not reference the current slice contract.'
    }
    if ($report -match '(?im)## Tests with exact counts and timestamps[\s\S]*Main Pester[^|]*\|[^|]*\|\s*[^|]*\|\s*[^|]*\|\s*[^|]*\|') {
        if ($ownerMappingSection -notmatch '(?i)Exact test names') { Fail 'Broad suite counts are not accompanied by focused owner test names.' }
    }
    if ($canonicalStatusRows.Count -eq 0) { Fail 'Canonical owner-ID status table contains no status-bearing numbered rows.' }
    foreach ($row in $canonicalStatusRows) {
        $status = $row.Status
        $disposition = Get-TpmOwnerStatusDisposition -Status $status -AllowedStatuses $allowedOwnerStatuses -Dispositions $ownerStatusDispositions
        if ($disposition -eq 'INVALID') { Fail "Invalid canonical owner report status for ID $($row.Id): $status"; continue }
        if ($disposition -eq 'UNRESOLVED') { Fail "Canonical owner report contains unresolved status for ID $($row.Id): $status"; continue }
        if ($RequireOwnerRuntime -and $disposition -eq 'OWNER RUNTIME NEEDED') { Fail "Owner-runtime evidence remains outstanding for ID $($row.Id)." }
    }
    if ($RequireOwnerRuntime) {
        $candidateStatusMatches = [regex]::Matches($report, '(?im)^-[ \t]*Current candidate status:[ \t]*(.*?)[ \t]*$')
        if ($candidateStatusMatches.Count -ne 1) {
            Fail 'Current candidate status is missing or invalid.'
        } else {
            $candidateStatus = $candidateStatusMatches[0].Groups[1].Value.Trim()
            if ($candidateStatus -ceq 'STALE') {
                Fail 'Candidate package is stale relative to source changes.'
            } elseif ($candidateStatus -cne 'VALIDATED') {
                Fail 'Current candidate status is missing or invalid.'
            }
        }
    }
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
    if ($progressSection -match '(?im)^\|[^|\r\n]*\|[^|\r\n]*\|[^|\r\n]*\|\s*NOT FIXED\s*\|') {
        Fail 'Progress audit contains an unaddressed NOT FIXED path.'
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
        if ($times.Count -eq 0) {
            Fail 'Validation timestamps are missing.'
        } else {
            $latestValidationUtc = $times | ForEach-Object {
                [datetime]::ParseExact($_.Value, 'yyyy-MM-ddTHH:mm:ss', [Globalization.CultureInfo]::InvariantCulture, ([Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal))
            } | Sort-Object -Descending | Select-Object -First 1
            if ($latestValidationUtc -lt $ChangedAtUtc.ToUniversalTime()) { Fail 'Validation evidence predates the latest source/test/gate change.' }
        }
    }
}
if ($null -ne $registry) {
    try {
        if (-not $registry.PSObject.Properties['procedures']) { Fail 'Registry procedure list is missing.' }
        foreach ($entry in @($registry.procedures)) {
            foreach ($property in @('id','rule','enforcementType','requiredEvidence','failureMessage')) {
                if (-not $entry.PSObject.Properties[$property] -or [string]::IsNullOrWhiteSpace([string]$entry.$property)) { Fail "Registry entry is incomplete: $($entry.id) / $property" }
            }
        }
    } catch { Fail "Registry procedure validation failed: $($_.Exception.Message)" }
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
