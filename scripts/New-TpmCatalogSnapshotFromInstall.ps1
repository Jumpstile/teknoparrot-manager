<#
.SYNOPSIS
  Development tool (not shipped to players). Builds a catalog snapshot folder from an INSTALLED TeknoParrot folder.

.DESCRIPTION
  Writes the same six files as New-TpmReleaseCatalogSnapshot.ps1 (snapshot-manifest.json, delta.json, release-evidence.json,
  source-proof.json, semantic-comparison.json, asset-mutability.json), so Test-TpmReleaseCatalogSnapshot.ps1 and every consumer accept it.
  Read-only on the install: it only reads GameProfiles (and GameSetup / Metadata when the folder has them). UserProfiles is never read.
  No network. Nothing from an upstream repository is used.

  What is honest about the result:
  - Release.AssetName / AssetSize / AssetSha256 are the name, size and SHA-256 of TeknoParrotUi.exe in the install. There is no release asset.
  - Release.Version is the file version of that exe (or -InstallVersion).
  - SnapshotId must equal TPM-GAME-SUPPORT-RELEASE-<version>-ASSET-<first 8 hex of that SHA-256, upper case>; the tool refuses any other id.
  - SourceProof.Commit is 'installed-semantic-sha256:<digest of the GameProfiles content>', not a git commit; nothing independent proves the content.
  - delta.json compares against the profile list in the previous snapshot's manifest (no files needed).

  -PreviousSnapshotPath is a snapshot folder or its snapshot-manifest.json.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InstallRoot,
    [Parameter(Mandatory = $true)][string]$PreviousSnapshotPath,
    [Parameter(Mandatory = $true)][string]$OutputRoot,
    [Parameter(Mandatory = $true)][string]$SnapshotId,
    [Parameter(Mandatory = $true)][string]$CapturedAtUtc,
    [string]$InstallVersion = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TpmReleaseCatalogSnapshot.Common.ps1')

$exeName = 'TeknoParrotUi.exe'
if (-not (Test-Path -LiteralPath $InstallRoot -PathType Container)) { throw "Install folder is missing: $InstallRoot" }
$installFull = Get-TpmFullPath -Path $InstallRoot
$outputFull = [System.IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if (($outputFull + '\').StartsWith($installFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) { throw "OutputRoot must not be inside the install folder (the install is read-only): $OutputRoot" }
$exePath = Join-Path $installFull $exeName
if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) { throw "$exeName is missing in the install folder; the snapshot needs it as its identity: $installFull" }
$previousManifestPath = if (Test-Path -LiteralPath $PreviousSnapshotPath -PathType Container) { Join-Path $PreviousSnapshotPath 'snapshot-manifest.json' } else { $PreviousSnapshotPath }
if (-not (Test-Path -LiteralPath $previousManifestPath -PathType Leaf)) { throw "Previous snapshot manifest is missing: $previousManifestPath" }
if ($CapturedAtUtc -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$') { throw "CapturedAtUtc must look like 2026-11-27T10:00:00Z: $CapturedAtUtc" }

$version = if ($InstallVersion) { $InstallVersion } else { [string][System.Diagnostics.FileVersionInfo]::GetVersionInfo($exePath).FileVersion }
if ($version -notmatch '^\d+(\.\d+){3}$') { throw "The install version is '$version', not four numbers like 1.0.0.2340. Pass -InstallVersion." }
$exeSha = Get-TpmSnapshotSha256File -Path $exePath
$exeItem = Get-Item -LiteralPath $exePath
$expectedId = 'TPM-GAME-SUPPORT-RELEASE-{0}-ASSET-{1}' -f $version, $exeSha.Substring(0, 8).ToUpperInvariant()
if ($SnapshotId -cne $expectedId) { throw "SnapshotId must be $expectedId (version and the SHA-256 of $exeName); got $SnapshotId." }

$previous = Get-Content -LiteralPath $previousManifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
if ([string]$previous.SnapshotId -ceq $SnapshotId) { throw 'The previous snapshot has the same id; nothing new to record.' }
$records = Get-TpmCatalogRecords -Root $installFull -InstallMode
$skipped = @($script:TpmSnapshotSkippedFiles)
$profiles = @($records | Where-Object Root -eq 'GameProfiles')
if ($profiles.Count -eq 0) { throw "No GameProfiles XML files were found in: $installFull" }

$previousCommit = [string]$previous.SourceProof.Commit
$delta = Get-TpmDeltaFromRecords -CurrentRecords $records -HistoricalRecords @($previous.Files) -HistoricalSourceCommit $previousCommit
$delta['HistoricalSnapshotId'] = [string]$previous.SnapshotId
$rootNames = @('GameProfiles', 'GameSetup', 'Metadata') | Where-Object { @($records | Where-Object Root -eq $_).Count -gt 0 -or $_ -eq 'GameProfiles' }
$rootDigests = [ordered]@{}
foreach ($rootName in $rootNames) { $rootDigests[$rootName] = Get-TpmRootSemanticDigest -Records $records -RootName $rootName }
$proofCommit = 'installed-semantic-sha256:' + $rootDigests['GameProfiles']
$counts = [ordered]@{
    GameProfiles = $profiles.Count
    GameSetup = @($records | Where-Object Root -eq 'GameSetup').Count
    Metadata = @($records | Where-Object Root -eq 'Metadata').Count
    TotalFiles = $records.Count
}
$proofRole = 'Content read from an installed TeknoParrot folder; no independent source proof exists'
$current = [ordered]@{
    Version = $version
    Tag = 'INSTALLED-FOLDER'
    ReleaseId = 0
    AssetName = $exeName
    AssetUrl = ''
    AssetSize = [int64]$exeItem.Length
    AssetSha256 = $exeSha
    AssetUpdatedAt = $exeItem.LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
    PublishedAt = ''
    TargetCommitish = ''
}
$previousObservation = [ordered]@{
    Version = [string]$previous.Release.Version
    Tag = [string]$previous.Release.Tag
    AssetName = [string]$previous.Release.AssetName
    AssetSize = [int64]$previous.Release.AssetSize
    AssetSha256 = [string]$previous.Release.AssetSha256
    AssetUpdatedAt = [string]$previous.Release.AssetUpdatedAt
}
$release = [ordered]@{
    EvidenceSchemaVersion = '1.0.0'
    CapturedAtUtc = $CapturedAtUtc
    Repository = 'installed-folder'
    SourceKind = 'INSTALLED_FOLDER'
    Current = $current
    PreviousStableObservation = $previousObservation
    SourceProof = [ordered]@{ Commit = $proofCommit; Tree = '' }
    Note = "Captured from an installed TeknoParrot folder, not from an upstream release. AssetSha256 and AssetSize are those of $exeName in that folder."
}
$manifest = [ordered]@{
    SnapshotSchemaVersion = '1.0.0'
    SnapshotId = $SnapshotId
    CapturedAtUtc = $CapturedAtUtc
    SnapshotKind = 'TPM_CURRENT_RELEASE_CATALOG'
    SourceKind = 'INSTALLED_FOLDER'
    Release = [ordered]@{
        Version = $version
        Tag = $current.Tag
        ReleaseId = 0
        AssetName = $exeName
        AssetUrl = ''
        AssetSize = $current.AssetSize
        AssetSha256 = $exeSha
        AssetUpdatedAt = $current.AssetUpdatedAt
    }
    SourceProof = [ordered]@{ Repository = 'installed-folder'; Commit = $proofCommit; Tree = ''; Role = $proofRole }
    CatalogCounts = $counts
    CatalogRoots = @($rootNames)
    SemanticRootDigests = $rootDigests
    Files = @($records)
    SemanticComparison = [ordered]@{ Valid = $false; ComparedFileCount = 0; MismatchCount = 0; ProofCommit = $proofCommit; Note = 'Not applicable: there is no second source to compare an installed folder with.' }
    DeltaManifest = 'delta.json'
    ReleaseEvidence = 'release-evidence.json'
    MutabilityRecord = 'asset-mutability.json'
    ParserVersion = 'TPM-RELEASE-SNAPSHOT-PARSER-1'
    ProvenanceDiscrepancy = "This snapshot was captured from an installed TeknoParrot folder, not an upstream release. The asset hash is the SHA-256 of $exeName in that folder. SkippedFiles in source-proof.json lists files the folder held that are not catalog files."
}
$mutability = [ordered]@{
    RecordSchemaVersion = '1.0.0'
    CurrentSnapshotId = $SnapshotId
    ObservedAssetHistory = @($previousObservation, $current)
    Conclusion = 'The identity of this snapshot is the installed TeknoParrotUi.exe. A different install needs a new reviewed snapshot.'
    Policy = 'Validation uses the immutable TPM-controlled snapshot. A changed install must not silently refresh the snapshot.'
}
$sourceProofRecord = [ordered]@{
    RecordSchemaVersion = '1.0.0'
    Repository = 'installed-folder'
    Commit = $proofCommit
    Tree = ''
    Role = $proofRole
    CatalogPaths = [ordered]@{ GameProfiles = 'GameProfiles'; GameSetup = 'GameSetup'; Metadata = 'Metadata' }
    SemanticEquality = [ordered]@{ GameProfilesCompared = 0; GameSetupCompared = 0; MetadataCompared = 0; MismatchCount = 0 }
    SkippedFiles = @($skipped)
    RuntimeScope = 'None. Read-only catalog capture.'
}
$semanticRecord = [ordered]@{
    RecordSchemaVersion = '1.0.0'
    SnapshotId = $SnapshotId
    AssetSha256 = $exeSha
    ProofCommit = $proofCommit
    ComparisonMethod = 'None: an installed folder has no second source.'
    Roots = [ordered]@{
        GameProfiles = [ordered]@{ AssetCount = $counts.GameProfiles; ProofCount = 0; Compared = 0; Mismatches = 0 }
        GameSetup = [ordered]@{ AssetCount = $counts.GameSetup; ProofCount = 0; Compared = 0; Mismatches = 0 }
        Metadata = [ordered]@{ AssetCount = $counts.Metadata; ProofCount = 0; Compared = 0; Mismatches = 0 }
    }
    TotalCompared = 0
    TotalMismatches = 0
    Result = 'NOT_APPLICABLE'
}
$manifestPath = Join-Path $outputFull 'snapshot-manifest.json'
Assert-TpmSnapshotOutputRoot -ManifestPath $manifestPath -SnapshotId $SnapshotId -AssetSha256 $exeSha -OutputRoot $outputFull
Write-TpmSnapshotJson -Value $mutability -Path (Join-Path $outputFull 'asset-mutability.json')
Write-TpmSnapshotJson -Value $sourceProofRecord -Path (Join-Path $outputFull 'source-proof.json')
Write-TpmSnapshotJson -Value $semanticRecord -Path (Join-Path $outputFull 'semantic-comparison.json')
Write-TpmSnapshotJson -Value $delta -Path (Join-Path $outputFull 'delta.json')
Write-TpmSnapshotJson -Value $release -Path (Join-Path $outputFull 'release-evidence.json')
# The manifest names the other files, so it is written last: an interrupted run never leaves a manifest that points at missing files.
Write-TpmSnapshotJson -Value $manifest -Path $manifestPath
[ordered]@{
    SnapshotId = $SnapshotId
    Version = $version
    AssetSha256 = $exeSha
    ManifestPath = $manifestPath
    CatalogFileCount = $records.Count
    GameProfiles = $counts.GameProfiles
    GameSetup = $counts.GameSetup
    Metadata = $counts.Metadata
    PreviousSnapshotId = [string]$previous.SnapshotId
    Added = $delta.AddedProfileCount
    Removed = $delta.RemovedProfileCount
    Changed = $delta.SemanticChangedProfileCount
    Unchanged = $delta.SemanticUnchangedProfileCount
    SkippedFileCount = $skipped.Count
    SkippedFiles = @($skipped)
} | ConvertTo-Json -Depth 10
