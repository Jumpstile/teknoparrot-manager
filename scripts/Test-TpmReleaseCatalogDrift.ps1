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
function Get-CurrentField($Evidence, [string]$Name) {
    if ($null -eq $Evidence -or -not $Evidence.PSObject.Properties['Current']) { return '' }
    $current = $Evidence.Current
    if ($null -eq $current -or -not $current.PSObject.Properties[$Name]) { return '' }
    return [string]$current.$Name
}
$recordedHash = Get-CurrentField $recorded 'AssetSha256'
$observedHash = Get-CurrentField $observed 'AssetSha256'
$recordedVersion = Get-CurrentField $recorded 'Version'
$observedVersion = Get-CurrentField $observed 'Version'
$hashPattern = '^[0-9A-Fa-f]{64}$'
$recordedComplete = $recordedHash -match $hashPattern
$observedComplete = $observedHash -match $hashPattern
$result = [ordered]@{
    RecordedSnapshotId = if ($recordedComplete) { 'TPM-GAME-SUPPORT-RELEASE-{0}-ASSET-{1}' -f $recordedVersion, $recordedHash.Substring(0, 8).ToUpperInvariant() } else { '' }
    RecordedVersion = $recordedVersion
    RecordedAssetSha256 = $recordedHash
    ObservedVersion = $observedVersion
    ObservedAssetSha256 = $observedHash
    Status = if (-not $recordedComplete) { 'RECORDED_EVIDENCE_INCOMPLETE' } elseif (-not $observedComplete) { 'OBSERVED_EVIDENCE_INCOMPLETE' } elseif ($recordedHash -ieq $observedHash) { 'UP_TO_DATE' } else { 'NEW_RELEASE_SNAPSHOT_AVAILABLE' }
    Action = if (-not $recordedComplete) { 'The recorded release evidence has no valid file hash. Repair the recorded evidence before checking for a new release.' } elseif (-not $observedComplete) { 'The observed release evidence has no valid file hash. Fetch the release evidence again.' } elseif ($recordedHash -ieq $observedHash) { 'Retain the historical snapshot.' } else { 'Stop automatic refresh. Create a new reviewed immutable snapshot.' }
}
$result | ConvertTo-Json -Depth 10
