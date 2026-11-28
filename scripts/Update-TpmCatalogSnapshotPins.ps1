<#
.SYNOPSIS
  Development tool. Moves every pin of the current catalog snapshot to a new snapshot folder in one pass, and says what it changed.

.DESCRIPTION
  1. Reads contracts\snapshots\<NewSnapshotId>\snapshot-manifest.json and delta.json (made by New-TpmCatalogSnapshotFromInstall.ps1 or
     New-TpmReleaseCatalogSnapshot.ps1) and checks they really are NewSnapshotId / NewVersion.
  2. Rewrites contracts\snapshots\CURRENT-SNAPSHOT-PIN.json (the one place the verifier, the support corpus tool, the drift tool and the tests
     read the accepted snapshot from). It must currently name OldSnapshotId, or nothing is written.
  3. Replaces the old snapshot id and the old asset SHA-256 with the new ones in scripts\*.ps1, scripts\*.json, Tests\*.ps1, docs\*.md and
     docs\remediation\inventories\*.md. The dated records under docs\remediation (control board, reconciliation, slices) and everything under
     contracts\snapshots\<id> are history and are left alone; files that still name the old id are listed.
  4. Runs Test-TpmReleaseCatalogSnapshot.ps1 on the new manifest (needs the repo's scripts folder) and reports whether it is valid.
  -DryRun shows what would change and writes nothing. The old snapshot folder is kept: it is the "previous snapshot" of the next rebuild.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OldSnapshotId,
    [Parameter(Mandatory = $true)][string]$NewSnapshotId,
    [Parameter(Mandatory = $true)][string]$NewVersion,
    [string]$RepoRoot = '',
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$idPattern = '^TPM-GAME-SUPPORT-RELEASE-\d+(\.\d+){3}-ASSET-[0-9A-F]{8}$'
if ($OldSnapshotId -cnotmatch $idPattern) { throw "OldSnapshotId is not a snapshot id: $OldSnapshotId" }
if ($NewSnapshotId -cnotmatch $idPattern) { throw "NewSnapshotId is not a snapshot id: $NewSnapshotId" }
if ($OldSnapshotId -ceq $NewSnapshotId) { throw 'Old and new snapshot ids are the same.' }
if (-not $RepoRoot) { $RepoRoot = [System.IO.Directory]::GetParent($PSScriptRoot).FullName }
$repo = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
$snapshotsRoot = Join-Path $repo 'contracts\snapshots'
$pinPath = Join-Path $snapshotsRoot 'CURRENT-SNAPSHOT-PIN.json'
$newFolder = Join-Path $snapshotsRoot $NewSnapshotId
foreach ($path in @($pinPath, (Join-Path $newFolder 'snapshot-manifest.json'), (Join-Path $newFolder 'delta.json'))) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing: $path" }
}

$pin = Get-Content -LiteralPath $pinPath -Raw | ConvertFrom-Json -ErrorAction Stop
if ([string]$pin.SnapshotId -cne $OldSnapshotId) { throw "The pin file names $($pin.SnapshotId), not $OldSnapshotId. Nothing was changed." }
$manifest = Get-Content -LiteralPath (Join-Path $newFolder 'snapshot-manifest.json') -Raw | ConvertFrom-Json -ErrorAction Stop
$delta = Get-Content -LiteralPath (Join-Path $newFolder 'delta.json') -Raw | ConvertFrom-Json -ErrorAction Stop
if ([string]$manifest.SnapshotId -cne $NewSnapshotId) { throw "The manifest in $newFolder is $($manifest.SnapshotId), not $NewSnapshotId." }
if ([string]$manifest.Release.Version -cne $NewVersion) { throw "The manifest version is $($manifest.Release.Version), not $NewVersion." }
$oldAssetSha = [string]$pin.AssetSha256
$newAssetSha = [string]$manifest.Release.AssetSha256

$newPin = [ordered]@{
    PinSchemaVersion = '1.0.0'
    SnapshotId = $NewSnapshotId
    Version = $NewVersion
    AssetSha256 = $newAssetSha
    AssetSize = [int64]$manifest.Release.AssetSize
    SourceProofCommit = [string]$manifest.SourceProof.Commit
    CatalogCounts = [ordered]@{
        GameProfiles = [int]$manifest.CatalogCounts.GameProfiles
        GameSetup = [int]$manifest.CatalogCounts.GameSetup
        Metadata = [int]$manifest.CatalogCounts.Metadata
        TotalFiles = [int]$manifest.CatalogCounts.TotalFiles
    }
    Delta = [ordered]@{
        Historical = [int]$delta.HistoricalProfileCount
        Current = [int]$delta.CurrentProfileCount
        Added = [int]$delta.AddedProfileCount
        Removed = [int]$delta.RemovedProfileCount
        Changed = [int]$delta.SemanticChangedProfileCount
        Unchanged = [int]$delta.SemanticUnchangedProfileCount
    }
}

$changes = New-Object System.Collections.Generic.List[object]
$left = New-Object System.Collections.Generic.List[string]
function Get-RelativeName([string]$Path) { return $Path.Substring($repo.Length + 1) }
$targets = New-Object System.Collections.Generic.List[string]
$targetFolders = @(
    @{ Path = 'scripts'; Filters = @('*.ps1', '*.json') }
    @{ Path = 'Tests'; Filters = @('*.ps1') }
    @{ Path = 'docs'; Filters = @('*.md') }
    @{ Path = 'docs\remediation\inventories'; Filters = @('*.md') }
)
foreach ($folder in $targetFolders) {
    $folderPath = Join-Path $repo $folder.Path
    if (-not (Test-Path -LiteralPath $folderPath -PathType Container)) { continue }
    foreach ($filter in $folder.Filters) {
        foreach ($file in @(Get-ChildItem -LiteralPath $folderPath -Filter $filter -File)) {
            # This tool and its own test hold the words they are about; they are never rewritten.
            if ($file.Name -in @('Update-TpmCatalogSnapshotPins.ps1', 'TpmCatalogSnapshotTools.Tests.ps1')) { continue }
            [void]$targets.Add($file.FullName)
        }
    }
}
foreach ($path in $targets) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes, $(if ($hasBom) { 3 } else { 0 }), $bytes.Length - $(if ($hasBom) { 3 } else { 0 }))
    $updated = $text.Replace($OldSnapshotId, $NewSnapshotId)
    if ($oldAssetSha) { $updated = $updated.Replace($oldAssetSha, $newAssetSha) }
    if ($updated -ceq $text) { continue }
    $idHits = ([regex]::Matches($text, [regex]::Escape($OldSnapshotId))).Count
    $shaHits = if ($oldAssetSha) { ([regex]::Matches($text, [regex]::Escape($oldAssetSha))).Count } else { 0 }
    [void]$changes.Add([pscustomobject]@{ File = Get-RelativeName $path; SnapshotIdReplacements = $idHits; AssetShaReplacements = $shaHits })
    if (-not $DryRun) { [System.IO.File]::WriteAllText($path, $updated, (New-Object System.Text.UTF8Encoding($hasBom))) }
}
# History: dated records that still name the old snapshot are listed, not rewritten.
foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $repo 'docs\remediation') -Filter '*.md' -File -Recurse -ErrorAction SilentlyContinue)) {
    if ((Get-Content -LiteralPath $file.FullName -Raw).Contains($OldSnapshotId)) { [void]$left.Add((Get-RelativeName $file.FullName)) }
}
if (-not $DryRun) { [System.IO.File]::WriteAllText($pinPath, (($newPin | ConvertTo-Json -Depth 10) + "`r`n"), (New-Object System.Text.UTF8Encoding($false))) }

$verifier = Join-Path $repo 'scripts\Test-TpmReleaseCatalogSnapshot.ps1'
$verification = 'NOT_RUN'
if ($DryRun) { $verification = 'NOT_RUN_DRY_RUN' }
elseif (-not (Test-Path -LiteralPath $verifier -PathType Leaf)) { $verification = 'NOT_RUN_VERIFIER_NOT_FOUND' }
else {
    $verdict = (& $verifier -ManifestPath (Join-Path $newFolder 'snapshot-manifest.json') -PinPath $pinPath) | Out-String | ConvertFrom-Json
    $verification = if ($verdict.Valid) { 'VALID' } else { 'INVALID: ' + (@($verdict.Errors) -join '; ') }
}
[ordered]@{
    DryRun = [bool]$DryRun
    OldSnapshotId = $OldSnapshotId
    NewSnapshotId = $NewSnapshotId
    NewVersion = $NewVersion
    PinFile = (Get-RelativeName $pinPath)
    PinFileRewritten = (-not $DryRun)
    FilesChanged = $changes.ToArray()
    HistoricalRecordsStillNamingOldSnapshot = $left.ToArray()
    Verification = $verification
} | ConvertTo-Json -Depth 10
