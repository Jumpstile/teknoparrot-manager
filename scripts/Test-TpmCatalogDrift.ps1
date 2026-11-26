<#
Repo tool (not shipped to players): what changed in a TeknoParrot folder since the
pinned catalog snapshot, and which new games need a person to decide something.

Reads (nothing is run or changed):
  -ProfilesPath          a TeknoParrot folder, a folder that holds GameProfiles, or a GameProfiles folder
  -DecisionsPath         scripts\TpmGameSupportDecisions.json (default)
  -SnapshotManifestPath  the pinned snapshot-manifest.json (default: the newest one under contracts\snapshots)
Writes only what you name:
  -ReportPath            a Markdown report
  -WriteFactsPath        facts only (code, emulator type, executable name, revision) of every profile, to refresh testdata\
  -MarkdownPath          regenerates docs\GAME-SUPPORT.md through scripts\New-TpmGameCoverage.ps1 (needs -GuidePath, the guide page or its game-data JSON)

Each profile resolves to a decision:
  Recorded       the decisions file has a row for the code
  FamilyDefault  no row, but the emulator type (loader) has rows, so the profile gets that family's usual handling
  GenericDefault no row and no family: TeknoParrot Manager still registers it and writes a plain Game Notes entry (register-only)
A new profile that resolves to GenericDefault needs a decision, so the exit code is 1. Anything else exits 0.
Changed profiles are compared with the snapshot by the snapshot's own semantic hash (formatting-only changes do not count).
#>
[CmdletBinding()]
param(
    [string]$ProfilesPath = '',
    [string]$DecisionsPath = '',
    [string]$SnapshotManifestPath = '',
    [string]$ReportPath = '',
    [string]$WriteFactsPath = '',
    [string]$TeknoParrotVersion = '',
    [string]$GuidePath = '',
    [string]$MarkdownPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$toolFolder = Split-Path -Parent $MyInvocation.MyCommand.Path

# The snapshot tool's own hash functions, taken from it as text so there is one definition (it cannot be dot-sourced: its parameters are mandatory).
$snapshotToolText = [System.IO.File]::ReadAllText((Join-Path $toolFolder 'New-TpmReleaseCatalogSnapshot.ps1'))
$snapshotAst = [System.Management.Automation.Language.Parser]::ParseInput($snapshotToolText, [ref]$null, [ref]$null)
$wantedFunctions = @('Get-TpmSnapshotSha256Bytes', 'ConvertTo-TpmXmlEscaped', 'ConvertTo-TpmCanonicalXmlNode', 'Get-TpmSemanticHash')
$functionAsts = @($snapshotAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wantedFunctions -contains $n.Name }, $true))
if ($functionAsts.Count -ne $wantedFunctions.Count) { throw 'The snapshot tool no longer has the hash functions this tool reuses.' }
. ([scriptblock]::Create((@($functionAsts | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n")))

function Find-TpmDriftProfilesDir {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "The profiles folder does not exist: $Path" }
    $direct = Join-Path $Path 'GameProfiles'
    if (Test-Path -LiteralPath $direct -PathType Container) { return $direct }
    if (@(Get-ChildItem -LiteralPath $Path -Filter '*.xml' -File -ErrorAction SilentlyContinue).Count -gt 0) { return $Path }
    $found = @(Get-ChildItem -LiteralPath $Path -Directory -Recurse -Filter 'GameProfiles' -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } | Select-Object -First 1)
    if ($found.Count -eq 0) { throw "No GameProfiles folder was found under: $Path" }
    return $found[0].FullName
}

# One fact row per profile file. A file that does not read as XML is listed as unreadable, never skipped.
function Get-TpmDriftProfileFacts {
    param([Parameter(Mandatory)][string]$ProfilesDir)
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($file in @(Get-ChildItem -LiteralPath $ProfilesDir -Filter '*.xml' -File | Sort-Object Name)) {
        $row = [ordered]@{ Code = $file.BaseName; EmulatorType = ''; ExecutableName = ''; GameProfileRevision = ''; SemanticSha256 = ''; Unreadable = '' }
        try {
            $doc = New-Object System.Xml.XmlDocument
            $doc.XmlResolver = $null
            $doc.Load($file.FullName)
            $field = { param($name) $node = $doc.SelectSingleNode('/GameProfile/' + $name); if ($null -ne $node) { $node.InnerText.Trim() } else { '' } }
            $row.EmulatorType = & $field 'EmulatorType'
            $row.ExecutableName = & $field 'ExecutableName'
            $row.GameProfileRevision = & $field 'GameProfileRevision'
            $row.SemanticSha256 = Get-TpmSemanticHash -Path $file.FullName
        } catch { $row.Unreadable = [string]$_.Exception.Message }
        [void]$rows.Add([pscustomobject]$row)
    }
    return $rows.ToArray()
}

# Lookup tables over the decisions file: one decision per recorded code, and a usual handling per emulator type (loader) with rows.
function Get-TpmCatalogDecisionIndex {
    param([Parameter(Mandatory)]$Decisions)
    $byProfile = @{}
    $loaderCounts = @{}
    foreach ($row in @($Decisions.Profiles)) {
        $byProfile[[string]$row.Profile] = $row
        $loader = [string]$row.Loader
        if (-not $loader -or $loader -ieq 'Unspecified') { continue }
        if (-not $loaderCounts.ContainsKey($loader)) { $loaderCounts[$loader] = @{} }
        $disposition = [string]$row.Disposition
        $loaderCounts[$loader][$disposition] = 1 + [int]$loaderCounts[$loader][$disposition]
    }
    $loaderDefault = @{}
    foreach ($loader in $loaderCounts.Keys) {
        $loaderDefault[$loader] = [string](@($loaderCounts[$loader].GetEnumerator() | Sort-Object @{ Expression = { $_.Value }; Descending = $true }, @{ Expression = { $_.Key } })[0].Key)
    }
    # The ROM-set loaders have no rows of their own: the decisions file says they are covered by the ROM family decisions, so registering is their handling.
    foreach ($loader in @($Decisions.Scope.ExcludedLoaders)) { if (-not $loaderDefault.ContainsKey([string]$loader)) { $loaderDefault[[string]$loader] = 'register-only' } }
    # TeknoDOS, TeknoRender0 and TeknoTJC: decided as register-only in the decisions file (RegisterOnlyLoaders), not ROM-set loaders.
    foreach ($loader in @($Decisions.Scope.RegisterOnlyLoaders)) { if ($loader -and -not $loaderDefault.ContainsKey([string]$loader)) { $loaderDefault[[string]$loader] = 'register-only' } }
    return [pscustomobject]@{ ByProfile = $byProfile; LoaderDefault = $loaderDefault }
}

# The decision for one profile code. Never throws and never returns nothing: a code with no row and no family still gets the generic default.
function Get-TpmCatalogDecision {
    param([Parameter(Mandatory)][string]$Code, [string]$EmulatorType = '', [Parameter(Mandatory)]$Index)
    if ($Index.ByProfile.ContainsKey($Code)) {
        $row = $Index.ByProfile[$Code]
        return [pscustomobject]@{ Code = $Code; Source = 'Recorded'; Disposition = [string]$row.Disposition; Family = [string]$row.Loader }
    }
    if ($EmulatorType -and $Index.LoaderDefault.ContainsKey($EmulatorType)) {
        return [pscustomobject]@{ Code = $Code; Source = 'FamilyDefault'; Disposition = [string]$Index.LoaderDefault[$EmulatorType]; Family = $EmulatorType }
    }
    return [pscustomobject]@{ Code = $Code; Source = 'GenericDefault'; Disposition = 'register-only'; Family = '' }
}

function Compare-TpmCatalogDrift {
    param([Parameter(Mandatory)][object[]]$Facts, [Parameter(Mandatory)]$Manifest, [Parameter(Mandatory)]$Index)
    $pinned = @{}
    foreach ($file in @($Manifest.Files)) { if ([string]$file.Root -eq 'GameProfiles') { $pinned[[string]$file.ProfileCode] = [string]$file.SemanticSha256 } }
    $current = @{}
    foreach ($fact in $Facts) { $current[[string]$fact.Code] = $fact }
    $new = New-Object System.Collections.Generic.List[object]
    $changed = New-Object System.Collections.Generic.List[string]
    $needsDecision = New-Object System.Collections.Generic.List[object]
    foreach ($code in @($current.Keys | Sort-Object)) {
        $fact = $current[$code]
        if (-not $pinned.ContainsKey($code)) {
            $decision = Get-TpmCatalogDecision -Code $code -EmulatorType ([string]$fact.EmulatorType) -Index $Index
            $item = [pscustomobject]@{ Code = $code; EmulatorType = [string]$fact.EmulatorType; Source = $decision.Source; Disposition = $decision.Disposition; Family = $decision.Family; Unreadable = [string]$fact.Unreadable }
            [void]$new.Add($item)
            if ($decision.Source -eq 'GenericDefault' -or $item.Unreadable) { [void]$needsDecision.Add($item) }
        } elseif (-not $fact.Unreadable -and $pinned[$code] -cne [string]$fact.SemanticSha256) {
            [void]$changed.Add($code)
        }
    }
    $removed = @($pinned.Keys | Where-Object { -not $current.ContainsKey($_) } | Sort-Object)
    return [pscustomobject]@{ New = $new.ToArray(); Removed = $removed; Changed = $changed.ToArray(); NeedsDecision = $needsDecision.ToArray(); PinnedCount = $pinned.Count; CurrentCount = $current.Count }
}

function Get-TpmCatalogDriftReport {
    param([Parameter(Mandatory)]$Drift, [string]$Version = '', [string]$PinnedVersion = '')
    $nl = "`r`n"
    $cap = 150
    $list = { param($items) if (@($items).Count -eq 0) { '(none)' } else { (@($items | Select-Object -First $cap) -join ', ') + $(if (@($items).Count -gt $cap) { ' ... and ' + (@($items).Count - $cap) + ' more' } else { '' }) } }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('# TeknoParrot catalog drift' + $nl + $nl)
    [void]$sb.Append(('Checked: TeknoParrot {0} ({1} profiles). Pinned snapshot: {2} ({3} profiles).' -f $(if ($Version) { $Version } else { '(version not given)' }), $Drift.CurrentCount, $(if ($PinnedVersion) { $PinnedVersion } else { '(unknown)' }), $Drift.PinnedCount) + $nl + $nl)
    if (@($Drift.NeedsDecision).Count -gt 0) {
        [void]$sb.Append('## Needs a decision' + $nl + $nl)
        [void]$sb.Append('These new profiles have no recorded decision and no emulator type TeknoParrot Manager knows (or the file cannot be read). TeknoParrot Manager still registers them and writes a plain Game Notes entry; a person must check whether the emulator type needs its own checks.' + $nl + $nl)
        [void]$sb.Append('| Profile | Emulator type | Why |' + $nl + '|---|---|---|' + $nl)
        foreach ($item in $Drift.NeedsDecision) {
            [void]$sb.Append(('| {0} | {1} | {2} |' -f $item.Code, $(if ($item.EmulatorType) { $item.EmulatorType } else { '(none)' }), $(if ($item.Unreadable) { 'not readable: ' + $item.Unreadable } else { 'new emulator type' })) + $nl)
        }
        [void]$sb.Append($nl)
    } else {
        [void]$sb.Append('Nothing needs a decision.' + $nl + $nl)
    }
    $byFamily = @($Drift.New | Where-Object { $_.Source -ne 'GenericDefault' } | Group-Object { if ($_.Family) { $_.Family } else { '(none)' } } | Sort-Object Name)
    [void]$sb.Append(('## New profiles ({0})' -f @($Drift.New).Count) + $nl + $nl)
    [void]$sb.Append('New profiles that fit a family default (handled with no change):' + $nl + $nl)
    foreach ($group in $byFamily) { [void]$sb.Append(('- {0}: {1}' -f $group.Name, (& $list @($group.Group | ForEach-Object { $_.Code }))) + $nl) }
    if ($byFamily.Count -eq 0) { [void]$sb.Append('- (none)' + $nl) }
    [void]$sb.Append($nl + ('## Removed profiles ({0})' -f @($Drift.Removed).Count) + $nl + $nl + (& $list $Drift.Removed) + $nl + $nl)
    [void]$sb.Append(('## Changed profiles ({0})' -f @($Drift.Changed).Count) + $nl + $nl + (& $list $Drift.Changed) + $nl + $nl)
    [void]$sb.Append('Changed means the profile differs from the pinned snapshot by more than formatting. Compared with the snapshot, not with last week.' + $nl)
    return $sb.ToString()
}

if ($MyInvocation.InvocationName -eq '.') { return }

if (-not $ProfilesPath) { throw 'Give -ProfilesPath.' }
if (-not $DecisionsPath) { $DecisionsPath = Join-Path $toolFolder 'TpmGameSupportDecisions.json' }
if (-not $SnapshotManifestPath) {
    $manifests = @(Get-ChildItem -LiteralPath (Join-Path $toolFolder '..\contracts\snapshots') -Filter 'snapshot-manifest.json' -File -Recurse | Sort-Object { $_.Directory.Name } -Descending)
    if ($manifests.Count -eq 0) { throw 'No pinned snapshot-manifest.json was found.' }
    $SnapshotManifestPath = $manifests[0].FullName
}
$profilesDir = Find-TpmDriftProfilesDir -Path $ProfilesPath
$decisions = [System.IO.File]::ReadAllText($DecisionsPath) | ConvertFrom-Json
$manifest = [System.IO.File]::ReadAllText($SnapshotManifestPath) | ConvertFrom-Json
$index = Get-TpmCatalogDecisionIndex -Decisions $decisions
$facts = @(Get-TpmDriftProfileFacts -ProfilesDir $profilesDir)
if ($facts.Count -eq 0) { throw "No profile files were found in: $profilesDir" }
$drift = Compare-TpmCatalogDrift -Facts $facts -Manifest $manifest -Index $index
$report = Get-TpmCatalogDriftReport -Drift $drift -Version $TeknoParrotVersion -PinnedVersion ([string]$manifest.Release.Version)
Write-Host $report
if ($ReportPath) { [System.IO.File]::WriteAllText($ReportPath, $report, (New-Object System.Text.UTF8Encoding $false)) }
if ($WriteFactsPath) {
    $out = [ordered]@{
        Source = 'Facts only (profile code, emulator type, executable name, profile revision). No profile settings, no game files.'
        Profiles = @($facts | ForEach-Object { [ordered]@{ Code = $_.Code; EmulatorType = $_.EmulatorType; ExecutableName = $_.ExecutableName; GameProfileRevision = $_.GameProfileRevision } })
    }
    [System.IO.File]::WriteAllText($WriteFactsPath, ($out | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding $false))
}
if ($MarkdownPath) {
    if (-not $GuidePath) { throw 'Regenerating docs\GAME-SUPPORT.md needs -GuidePath (the guide page or its game-data JSON).' }
    # New-TpmGameCoverage.ps1 reads its catalog from a snapshot manifest, so the current folder is handed to it as one.
    $currentManifest = [ordered]@{
        Release = [ordered]@{ Version = $(if ($TeknoParrotVersion) { $TeknoParrotVersion } else { 'current' }) }
        CatalogCounts = [ordered]@{ GameProfiles = $facts.Count }
        Files = @($facts | ForEach-Object { [ordered]@{ Root = 'GameProfiles'; ProfileCode = $_.Code } })
    }
    $tempManifest = Join-Path ([System.IO.Path]::GetTempPath()) ('tpm-current-catalog-' + [guid]::NewGuid().ToString('N') + '.json')
    try {
        [System.IO.File]::WriteAllText($tempManifest, ($currentManifest | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding $false))
        & (Join-Path $toolFolder 'New-TpmGameCoverage.ps1') -GuidePath $GuidePath -SnapshotManifestPath $tempManifest -ProfilesDir $profilesDir -MarkdownPath $MarkdownPath | Out-Null
    } finally {
        Remove-Item -LiteralPath $tempManifest -Force -ErrorAction SilentlyContinue
    }
}
exit $(if (@($drift.NeedsDecision).Count -gt 0) { 1 } else { 0 })
