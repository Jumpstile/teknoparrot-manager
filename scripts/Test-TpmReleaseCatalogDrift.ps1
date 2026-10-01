[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RecordedEvidencePath,
    [Parameter(Mandatory = $true)][string]$ObservedReleasePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $RecordedEvidencePath -PathType Leaf)) { throw "Recorded release evidence is missing: $RecordedEvidencePath" }
if (-not (Test-Path -LiteralPath $ObservedReleasePath -PathType Leaf)) { throw "Observed release evidence is missing: $ObservedReleasePath" }
$recorded = Get-Content -LiteralPath $RecordedEvidencePath -Raw | ConvertFrom-Json -ErrorAction Stop
$observed = Get-Content -LiteralPath $ObservedReleasePath -Raw | ConvertFrom-Json -ErrorAction Stop
$recordedHash = [string]$recorded.Current.AssetSha256
$observedHash = [string]$observed.Current.AssetSha256
$result = [ordered]@{
    RecordedSnapshotId = 'TPM-GAME-SUPPORT-RELEASE-1.0.0.2128-ASSET-9E6A8628'
    RecordedVersion = [string]$recorded.Current.Version
    RecordedAssetSha256 = $recordedHash
    ObservedVersion = [string]$observed.Current.Version
    ObservedAssetSha256 = $observedHash
    Status = if ($recordedHash -ceq $observedHash) { 'UP_TO_DATE' } else { 'NEW_RELEASE_SNAPSHOT_AVAILABLE' }
    Action = if ($recordedHash -ceq $observedHash) { 'Retain the historical snapshot.' } else { 'Stop automatic refresh. Create a new reviewed immutable snapshot.' }
}
$result | ConvertTo-Json -Depth 10
