[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CatalogRoot,
    [Parameter(Mandatory = $true)][string]$HistoricalCatalogRoot,
    [Parameter(Mandatory = $true)][string]$SourceProofRoot,
    [Parameter(Mandatory = $true)][string]$ReleaseEvidencePath,
    [Parameter(Mandatory = $true)][string]$OutputRoot,
    [Parameter(Mandatory = $true)][string]$SnapshotId,
    [Parameter(Mandatory = $true)][string]$CapturedAtUtc
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TpmReleaseCatalogSnapshot.Common.ps1')


function Get-TpmDelta {
    param(
        [string]$CurrentRoot,
        [string]$HistoricalRoot
    )
    $current = Get-TpmProfileMap -Root $CurrentRoot
    $historical = Get-TpmProfileMap -Root $HistoricalRoot
    $added = New-Object System.Collections.Generic.List[string]
    $removed = New-Object System.Collections.Generic.List[string]
    $changed = New-Object System.Collections.Generic.List[string]
    $unchanged = New-Object System.Collections.Generic.List[string]
    $rawDifferent = New-Object System.Collections.Generic.List[string]
    foreach ($key in $current.Keys) {
        if (-not $historical.ContainsKey($key)) { [void]$added.Add([System.IO.Path]::GetFileNameWithoutExtension($current[$key])); continue }
        $currentSemantic = Get-TpmSemanticHash -Path $current[$key]
        $historicalSemantic = Get-TpmSemanticHash -Path $historical[$key]
        $canonical = [System.IO.Path]::GetFileNameWithoutExtension($current[$key])
        if ((Get-TpmSnapshotSha256File -Path $current[$key]) -cne (Get-TpmSnapshotSha256File -Path $historical[$key])) { [void]$rawDifferent.Add($canonical) }
        if ($currentSemantic -cne $historicalSemantic) { [void]$changed.Add($canonical) } else { [void]$unchanged.Add($canonical) }
    }
    foreach ($key in $historical.Keys) {
        if (-not $current.ContainsKey($key)) { [void]$removed.Add([System.IO.Path]::GetFileNameWithoutExtension($historical[$key])) }
    }
    $result = [ordered]@{
        HistoricalSourceCommit = '5880e019016c5c3a0576e97a6c2a7f14bf54e3d1'
        HistoricalProfileCount = $historical.Count
        CurrentProfileCount = $current.Count
        AddedProfileCount = $added.Count
        RemovedProfileCount = $removed.Count
        SemanticChangedProfileCount = $changed.Count
        SemanticUnchangedProfileCount = $unchanged.Count
        RawByteDifferentProfileCount = $rawDifferent.Count
        FormattingOnlyChangedProfileCount = @($rawDifferent | Where-Object { $changed -notcontains $_ }).Count
        Added = Get-TpmCanonicalNameList -Values @($added)
        Removed = Get-TpmCanonicalNameList -Values @($removed)
        Changed = Get-TpmCanonicalNameList -Values @($changed)
        Unchanged = Get-TpmCanonicalNameList -Values @($unchanged)
    }
    if ($result.HistoricalProfileCount -ne 695 -or $result.CurrentProfileCount -ne 925 -or $result.AddedProfileCount -ne 230 -or $result.RemovedProfileCount -ne 0 -or $result.SemanticChangedProfileCount -ne 38 -or $result.SemanticUnchangedProfileCount -ne 657) {
        throw "Unexpected current-release delta counts. Historical=$($result.HistoricalProfileCount), Current=$($result.CurrentProfileCount), Added=$($result.AddedProfileCount), Removed=$($result.RemovedProfileCount), Changed=$($result.SemanticChangedProfileCount), Unchanged=$($result.SemanticUnchangedProfileCount)"
    }
    return $result
}


if (-not (Test-Path -LiteralPath $ReleaseEvidencePath -PathType Leaf)) { throw "Release evidence file is missing: $ReleaseEvidencePath" }
$release = Get-Content -LiteralPath $ReleaseEvidencePath -Raw | ConvertFrom-Json -ErrorAction Stop
$catalogRecords = Get-TpmCatalogRecords -Root $CatalogRoot
$proofRecords = Get-TpmCatalogRecords -Root $SourceProofRoot
$proofByPath = @{}
foreach ($record in $proofRecords) { $proofByPath[$record.RelativePath] = $record }
$semanticMismatches = New-Object System.Collections.Generic.List[string]
foreach ($record in $catalogRecords) {
    if (-not $proofByPath.ContainsKey($record.RelativePath)) { [void]$semanticMismatches.Add($record.RelativePath + ':missing-proof-file'); continue }
    if ($record.SemanticSha256 -cne $proofByPath[$record.RelativePath].SemanticSha256) { [void]$semanticMismatches.Add($record.RelativePath + ':semantic-mismatch') }
}
if ($semanticMismatches.Count -gt 0) { throw "Source-proof semantic comparison failed: $($semanticMismatches -join ', ')" }
if ($catalogRecords.Count -ne 2231 -or @($catalogRecords | Where-Object Root -eq 'GameProfiles').Count -ne 925 -or @($catalogRecords | Where-Object Root -eq 'GameSetup').Count -ne 383 -or @($catalogRecords | Where-Object Root -eq 'Metadata').Count -ne 923) { throw 'Catalog inventory count mismatch.' }
$delta = Get-TpmDelta -CurrentRoot $CatalogRoot -HistoricalRoot $HistoricalCatalogRoot
$rootDigests = [ordered]@{}
foreach ($rootName in @('GameProfiles', 'GameSetup', 'Metadata')) { $rootDigests[$rootName] = Get-TpmRootSemanticDigest -Records $catalogRecords -RootName $rootName }
$manifest = [ordered]@{
    SnapshotSchemaVersion = '1.0.0'
    SnapshotId = $SnapshotId
    CapturedAtUtc = $CapturedAtUtc
    SnapshotKind = 'TPM_CURRENT_RELEASE_CATALOG'
    Release = [ordered]@{
        Version = [string]$release.Current.Version
        Tag = [string]$release.Current.Tag
        ReleaseId = [int64]$release.Current.ReleaseId
        AssetName = [string]$release.Current.AssetName
        AssetUrl = [string]$release.Current.AssetUrl
        AssetSize = [int64]$release.Current.AssetSize
        AssetSha256 = [string]$release.Current.AssetSha256
        AssetUpdatedAt = [string]$release.Current.AssetUpdatedAt
    }
    SourceProof = [ordered]@{
        Repository = 'TeknoParrot-install'
        Commit = [string]$release.SourceProof.Commit
        Tree = [string]$release.SourceProof.Tree
        Role = 'Immutable semantic content proof; not official release provenance'
    }
    CatalogCounts = [ordered]@{ GameProfiles = 925; GameSetup = 383; Metadata = 923; TotalFiles = 2231 }
    CatalogRoots = @('GameProfiles', 'GameSetup', 'Metadata')
    SemanticRootDigests = $rootDigests
    Files = @($catalogRecords)
    SemanticComparison = [ordered]@{ Valid = $true; ComparedFileCount = 2231; MismatchCount = 0; ProofCommit = [string]$release.SourceProof.Commit }
    DeltaManifest = 'delta.json'
    ReleaseEvidence = 'release-evidence.json'
    MutabilityRecord = 'asset-mutability.json'
    ParserVersion = 'TPM-RELEASE-SNAPSHOT-PARSER-1'
    ProvenanceDiscrepancy = 'The stable release locator is mutable. The release tag and target commit report stale catalog counts. This snapshot pins the captured asset SHA-256 and records dc998e... only as an immutable semantic source-proof reference.'
}
$mutability = [ordered]@{
    RecordSchemaVersion = '1.0.0'
    CurrentSnapshotId = $SnapshotId
    ObservedAssetHistory = @($release.PreviousStableObservation, $release.Current)
    Conclusion = 'The stable release locator is mutable and must not be used as the sole historical catalog source. A changed asset requires a new reviewed snapshot.'
    Policy = 'Historical validation uses the immutable TPM-controlled snapshot and immutable source-proof commit. Upstream drift watch may report a changed live asset but must not silently refresh the snapshot.'
}
$sourceProofRecord = [ordered]@{
    RecordSchemaVersion = '1.0.0'
    Repository = 'TeknoParrot-install'
    Commit = [string]$release.SourceProof.Commit
    Tree = [string]$release.SourceProof.Tree
    Role = 'Immutable semantic content proof; not official release provenance'
    CatalogPaths = [ordered]@{
        GameProfiles = 'TeknoParrotUi.Common/GameProfiles'
        GameSetup = 'TeknoParrotUi.Common/GameSetup'
        Metadata = 'TeknoParrotUi.Common/Metadata'
    }
    SemanticEquality = [ordered]@{
        GameProfilesCompared = 925
        GameSetupCompared = 383
        MetadataCompared = 923
        MismatchCount = 0
    }
    ApplicationCodeChangedInProofCommit = @(
        'TeknoParrotUi.Common/GameProfile.cs',
        'TeknoParrotUi.Common/JoystickMapping.cs',
        'TeknoParrotUi/GameProfileLoader.cs',
        'TeknoParrotUi/Helpers/JoystickControlDirectInput.cs',
        'TeknoParrotUi/JoystickHelper.cs'
    )
    RuntimeScope = 'Recorded for later joystick/profile-loading/FFB compatibility work; not implemented in Slice 0.'
}
$semanticRecord = [ordered]@{
    RecordSchemaVersion = '1.0.0'
    SnapshotId = $SnapshotId
    AssetSha256 = [string]$release.Current.AssetSha256
    ProofCommit = [string]$release.SourceProof.Commit
    ComparisonMethod = 'Parsed XML and JSON semantic canonicalization; relative catalog paths compared one-to-one.'
    Roots = [ordered]@{
        GameProfiles = [ordered]@{ AssetCount = 925; ProofCount = 925; Compared = 925; Mismatches = 0 }
        GameSetup = [ordered]@{ AssetCount = 383; ProofCount = 383; Compared = 383; Mismatches = 0 }
        Metadata = [ordered]@{ AssetCount = 923; ProofCount = 923; Compared = 923; Mismatches = 0 }
    }
    TotalCompared = 2231
    TotalMismatches = 0
    Result = 'PASS'
}
$manifestPath = Join-Path $OutputRoot 'snapshot-manifest.json'
Assert-TpmSnapshotOutputRoot -ManifestPath $manifestPath -SnapshotId $SnapshotId -AssetSha256 ([string]$release.Current.AssetSha256) -OutputRoot $OutputRoot
Write-TpmSnapshotJson -Value $mutability -Path (Join-Path $OutputRoot 'asset-mutability.json')
Write-TpmSnapshotJson -Value $sourceProofRecord -Path (Join-Path $OutputRoot 'source-proof.json')
Write-TpmSnapshotJson -Value $semanticRecord -Path (Join-Path $OutputRoot 'semantic-comparison.json')
Write-TpmSnapshotJson -Value $delta -Path (Join-Path $OutputRoot 'delta.json')
Write-TpmSnapshotJson -Value $release -Path (Join-Path $OutputRoot 'release-evidence.json')
# The manifest names the other files, so it is written last: an interrupted run never leaves a manifest that points at missing files.
Write-TpmSnapshotJson -Value $manifest -Path $manifestPath
[ordered]@{
    SnapshotId = $SnapshotId
    ManifestPath = [System.IO.Path]::GetFullPath($manifestPath)
    CatalogFileCount = $catalogRecords.Count
    GameProfiles = 925
    GameSetup = 383
    Metadata = 923
    Added = $delta.AddedProfileCount
    Removed = $delta.RemovedProfileCount
    Changed = $delta.SemanticChangedProfileCount
    Unchanged = $delta.SemanticUnchangedProfileCount
    SemanticProof = $true
} | ConvertTo-Json -Depth 10
