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

function Get-TpmSnapshotSha256Bytes {
    param([byte[]]$Bytes)
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($algorithm.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $algorithm.Dispose()
    }
}

function Get-TpmSnapshotSha256File {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TpmFullPath {
    param([string]$Path)
    return ([System.IO.Path]::GetFullPath((Get-Item -LiteralPath $Path -Force).FullName)).TrimEnd('\')
}

function Get-TpmRelativePath {
    param(
        [string]$Root,
        [string]$Path
    )
    $rootFull = (Get-TpmFullPath -Path $Root) + '\'
    $pathFull = Get-TpmFullPath -Path $Path
    if (-not $pathFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escaped supplied root: $Path"
    }
    return $pathFull.Substring($rootFull.Length).Replace('\', '/')
}

function ConvertTo-TpmXmlEscaped {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    return $Value.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&apos;')
}

function ConvertTo-TpmCanonicalXmlNode {
    param([System.Xml.XmlNode]$Node)
    $builder = New-Object System.Text.StringBuilder
    $name = if ([string]::IsNullOrEmpty($Node.NamespaceURI)) { $Node.LocalName } else { '{' + $Node.NamespaceURI + '}' + $Node.LocalName }
    [void]$builder.Append('<').Append((ConvertTo-TpmXmlEscaped -Value $name))
    $attributes = @($Node.Attributes | Sort-Object @{ Expression = { $_.NamespaceURI } }, @{ Expression = { $_.LocalName } })
    foreach ($attribute in $attributes) {
        $attributeName = if ([string]::IsNullOrEmpty($attribute.NamespaceURI)) { $attribute.LocalName } else { '{' + $attribute.NamespaceURI + '}' + $attribute.LocalName }
        [void]$builder.Append(' ').Append((ConvertTo-TpmXmlEscaped -Value $attributeName)).Append('="').Append((ConvertTo-TpmXmlEscaped -Value ([string]$attribute.Value))).Append('"')
    }
    $elements = @($Node.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element })
    $text = ((@($Node.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Text } | ForEach-Object { $_.Value }) -join '')).Trim()
    if ($elements.Count -eq 0 -and [string]::IsNullOrEmpty($text)) {
        [void]$builder.Append('/>')
        return $builder.ToString()
    }
    [void]$builder.Append('>')
    if (-not [string]::IsNullOrEmpty($text)) { [void]$builder.Append((ConvertTo-TpmXmlEscaped -Value $text)) }
    foreach ($element in $elements) { [void]$builder.Append((ConvertTo-TpmCanonicalXmlNode -Node $element)) }
    [void]$builder.Append('</').Append((ConvertTo-TpmXmlEscaped -Value $name)).Append('>')
    return $builder.ToString()
}

function Get-TpmSemanticHash {
    param([string]$Path)
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -eq '.xml') {
        $document = New-Object System.Xml.XmlDocument
        $document.PreserveWhitespace = $false
        $document.Load($Path)
        $canonical = ConvertTo-TpmCanonicalXmlNode -Node $document.DocumentElement
        return Get-TpmSnapshotSha256Bytes -Bytes ([System.Text.Encoding]::UTF8.GetBytes($canonical))
    }
    if ($extension -eq '.json') {
        $value = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
        $canonical = ConvertTo-TpmCanonicalJsonValue -Value $value
        return Get-TpmSnapshotSha256Bytes -Bytes ([System.Text.Encoding]::UTF8.GetBytes($canonical))
    }
    throw "Unsupported semantic file type: $Path"
}

function ConvertTo-TpmJsonEscaped {
    param([string]$Value)
    return (ConvertTo-Json -InputObject ([string]$Value) -Compress -Depth 5)
}

function ConvertTo-TpmCanonicalJsonValue {
    param([object]$Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [System.Collections.IDictionary]) {
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($key in @($Value.Keys | Sort-Object)) {
            [void]$parts.Add((ConvertTo-TpmJsonEscaped -Value ([string]$key)) + ':' + (ConvertTo-TpmCanonicalJsonValue -Value $Value[$key]))
        }
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value -is [pscustomobject]) {
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) {
            [void]$parts.Add((ConvertTo-TpmJsonEscaped -Value $property.Name) + ':' + (ConvertTo-TpmCanonicalJsonValue -Value $property.Value))
        }
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($item in @($Value)) { [void]$parts.Add((ConvertTo-TpmCanonicalJsonValue -Value $item)) }
        return '[' + ($parts -join ',') + ']'
    }
    return (ConvertTo-Json -InputObject $Value -Compress -Depth 20)
}

function Assert-TpmCatalogRoot {
    param([string]$Root)
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "Catalog root is missing: $Root" }
    foreach ($name in @('GameProfiles', 'GameSetup', 'Metadata')) {
        $path = Join-Path $Root $name
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Catalog root is missing: $name" }
    }
}

function Get-TpmCatalogRecords {
    param([string]$Root)
    Assert-TpmCatalogRoot -Root $Root
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($rootName in @('GameProfiles', 'GameSetup', 'Metadata')) {
        $extension = if ($rootName -eq 'Metadata') { '.json' } else { '.xml' }
        $rootPath = Join-Path $Root $rootName
        foreach ($file in @(Get-ChildItem -LiteralPath $rootPath -Recurse -File | Sort-Object FullName)) {
            if ($file.Extension.ToLowerInvariant() -ne $extension) { throw "Unexpected catalog extension: $($file.FullName)" }
            $relative = Get-TpmRelativePath -Root $Root -Path $file.FullName
            if ($relative.StartsWith('../') -or $relative.Contains('/../') -or [System.IO.Path]::IsPathRooted($relative)) { throw "Unsafe catalog path: $relative" }
            [void]$records.Add([pscustomobject][ordered]@{
                RelativePath = $relative
                Root = $rootName
                FileName = $file.Name
                ProfileCode = if ($rootName -eq 'GameProfiles') { [System.IO.Path]::GetFileNameWithoutExtension($file.Name) } else { $null }
                Length = [int64]$file.Length
                Sha256 = Get-TpmSnapshotSha256File -Path $file.FullName
                SemanticSha256 = Get-TpmSemanticHash -Path $file.FullName
            })
        }
    }
    $exactDuplicates = @($records | Group-Object -Property RelativePath | Where-Object Count -gt 1)
    if ($exactDuplicates.Count -gt 0) { throw "Duplicate catalog paths: $($exactDuplicates.Name -join ', ')" }
    $pathDuplicates = @($records | Group-Object -Property @{ Expression = { $_.RelativePath.ToLowerInvariant() } } | Where-Object Count -gt 1)
    if ($pathDuplicates.Count -gt 0) { throw "Case-insensitive duplicate catalog paths: $($pathDuplicates.Name -join ', ')" }
    $profileRecords = @($records | Where-Object { $_.Root -eq 'GameProfiles' })
    $profileDuplicates = @($profileRecords | Group-Object -Property @{ Expression = { $_.ProfileCode.ToLowerInvariant() } } | Where-Object Count -gt 1)
    if ($profileDuplicates.Count -gt 0) { throw "Case-insensitive duplicate profile codes: $($profileDuplicates.Name -join ', ')" }
    return @($records | Sort-Object @{ Expression = { $_.RelativePath.ToLowerInvariant() } }, @{ Expression = { $_.RelativePath } })
}

function Get-TpmRootSemanticDigest {
    param([object[]]$Records, [string]$RootName)
    $lines = @($Records | Where-Object Root -eq $RootName | Sort-Object RelativePath | ForEach-Object { $_.RelativePath + '|' + $_.SemanticSha256 })
    return Get-TpmSnapshotSha256Bytes -Bytes ([System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n") + "`n"))
}

function Get-TpmProfileMap {
    param([string]$Root)
    $profileRoot = Join-Path $Root 'GameProfiles'
    $map = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $profileRoot -Filter '*.xml' -File)) {
        $key = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        if ($map.ContainsKey($key)) { throw "Duplicate profile identity: $key" }
        $map[$key] = $file.FullName
    }
    return $map
}

function Get-TpmCanonicalNameList {
    param([object[]]$Values)
    if (@($Values).Count -eq 0) { return ,@() }
    return ,@($Values | Sort-Object @{ Expression = { $_.ToLowerInvariant() } }, @{ Expression = { $_ } })
}

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

function Write-TpmSnapshotJson {
    param([object]$Value, [string]$Path)
    $parent = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Path))
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [void][System.IO.Directory]::CreateDirectory($parent) }
    $encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList ([object]$false)
    [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 100), $encoding)
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
        Repository = 'teknogods/TeknoParrotUI'
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
    Repository = 'teknogods/TeknoParrotUI'
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
Write-TpmSnapshotJson -Value $mutability -Path (Join-Path $OutputRoot 'asset-mutability.json')
Write-TpmSnapshotJson -Value $sourceProofRecord -Path (Join-Path $OutputRoot 'source-proof.json')
Write-TpmSnapshotJson -Value $semanticRecord -Path (Join-Path $OutputRoot 'semantic-comparison.json')
$manifestPath = Join-Path $OutputRoot 'snapshot-manifest.json'
Write-TpmSnapshotJson -Value $manifest -Path $manifestPath
Write-TpmSnapshotJson -Value $delta -Path (Join-Path $OutputRoot 'delta.json')
Write-TpmSnapshotJson -Value $release -Path (Join-Path $OutputRoot 'release-evidence.json')
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
