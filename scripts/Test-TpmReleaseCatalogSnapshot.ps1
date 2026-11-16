[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [string]$CatalogRoot,
    [string]$SourceProofRoot,
    [string]$HistoricalCatalogRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-TpmSnapshotSha256Bytes {
    param([byte[]]$Bytes)
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($algorithm.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
}

function Get-TpmSnapshotSha256File {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TpmXmlEscaped {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    return $Value.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&apos;')
}

function Get-TpmCanonicalXmlNode {
    param([System.Xml.XmlNode]$Node)
    $builder = New-Object System.Text.StringBuilder
    $name = if ([string]::IsNullOrEmpty($Node.NamespaceURI)) { $Node.LocalName } else { '{' + $Node.NamespaceURI + '}' + $Node.LocalName }
    [void]$builder.Append('<').Append((Get-TpmXmlEscaped -Value $name))
    # Ordinal order (namespace, then local name): the same text on every PC, whatever its language setting.
    $attributes = [System.Xml.XmlAttribute[]]@($Node.Attributes)
    $attributeKeys = [string[]]@($attributes | ForEach-Object { $_.NamespaceURI + [char]0 + $_.LocalName })
    [System.Array]::Sort($attributeKeys, $attributes, [System.StringComparer]::Ordinal)
    foreach ($attribute in $attributes) {
        $attributeName = if ([string]::IsNullOrEmpty($attribute.NamespaceURI)) { $attribute.LocalName } else { '{' + $attribute.NamespaceURI + '}' + $attribute.LocalName }
        [void]$builder.Append(' ').Append((Get-TpmXmlEscaped -Value $attributeName)).Append('="').Append((Get-TpmXmlEscaped -Value ([string]$attribute.Value))).Append('"')
    }
    $elements = @($Node.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element })
    $text = ((@($Node.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Text } | ForEach-Object { $_.Value }) -join '')).Trim()
    if ($elements.Count -eq 0 -and [string]::IsNullOrEmpty($text)) { [void]$builder.Append('/>'); return $builder.ToString() }
    [void]$builder.Append('>')
    if (-not [string]::IsNullOrEmpty($text)) { [void]$builder.Append((Get-TpmXmlEscaped -Value $text)) }
    foreach ($element in $elements) { [void]$builder.Append((Get-TpmCanonicalXmlNode -Node $element)) }
    [void]$builder.Append('</').Append((Get-TpmXmlEscaped -Value $name)).Append('>')
    return $builder.ToString()
}

function Get-TpmJsonEscaped {
    param([object]$Value, [int]$Depth = 5)
    # Windows PowerShell 5.1 writes ' < > & as \u0027 \u003c \u003e \u0026; PowerShell 7 writes them as-is. Pin the 5.1 text so the hash is the same on both.
    return (ConvertTo-Json -InputObject $Value -Compress -Depth $Depth).Replace("'", '\u0027').Replace('<', '\u003c').Replace('>', '\u003e').Replace('&', '\u0026')
}

function Get-TpmCanonicalJsonValue {
    param([object]$Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [System.Collections.IDictionary]) {
        $parts = New-Object System.Collections.Generic.List[string]
        $sortedKeys = [string[]]@($Value.Keys)
        [System.Array]::Sort($sortedKeys, [System.StringComparer]::Ordinal)
        foreach ($key in $sortedKeys) { [void]$parts.Add((Get-TpmJsonEscaped -Value ([string]$key)) + ':' + (Get-TpmCanonicalJsonValue -Value $Value[$key])) }
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value -is [pscustomobject]) {
        $parts = New-Object System.Collections.Generic.List[string]
        $propertyNames = [string[]]@($Value.PSObject.Properties | ForEach-Object { $_.Name })
        [System.Array]::Sort($propertyNames, [System.StringComparer]::Ordinal)
        foreach ($propertyName in $propertyNames) { [void]$parts.Add((Get-TpmJsonEscaped -Value $propertyName) + ':' + (Get-TpmCanonicalJsonValue -Value $Value.PSObject.Properties[$propertyName].Value)) }
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($item in @($Value)) { [void]$parts.Add((Get-TpmCanonicalJsonValue -Value $item)) }
        return '[' + ($parts -join ',') + ']'
    }
    return (Get-TpmJsonEscaped -Value $Value -Depth 20)
}

function Get-TpmSemanticHash {
    param([string]$Path)
    if ([System.IO.Path]::GetExtension($Path).ToLowerInvariant() -eq '.xml') {
        $document = New-Object System.Xml.XmlDocument
        $document.PreserveWhitespace = $false
        $document.Load($Path)
        $canonical = Get-TpmCanonicalXmlNode -Node $document.DocumentElement
    } elseif ([System.IO.Path]::GetExtension($Path).ToLowerInvariant() -eq '.json') {
        # The pinned hashes were made by Windows PowerShell 5.1, which read these UTF-8 files as Windows-1252. Read them the same way on every engine and PC.
        $canonical = Get-TpmCanonicalJsonValue -Value ([System.Text.Encoding]::GetEncoding(1252).GetString([System.IO.File]::ReadAllBytes($Path)) | ConvertFrom-Json -ErrorAction Stop)
    } else {
        throw "Unsupported semantic file: $Path"
    }
    return Get-TpmSnapshotSha256Bytes -Bytes ([System.Text.Encoding]::UTF8.GetBytes($canonical))
}

function Get-TpmSnapshotRelativePath {
    param([string]$Root, [string]$Path)
    $rootFull = ([System.IO.Path]::GetFullPath((Get-Item -LiteralPath $Root -Force).FullName)).TrimEnd('\') + '\'
    $pathFull = [System.IO.Path]::GetFullPath((Get-Item -LiteralPath $Path -Force).FullName)
    if (-not $pathFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Path escaped root: $Path" }
    return $pathFull.Substring($rootFull.Length).Replace('\', '/')
}

function Get-TpmSnapshotInventory {
    param([string]$Root)
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($rootName in @('GameProfiles', 'GameSetup', 'Metadata')) {
        $rootPath = Join-Path $Root $rootName
        if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) { throw "Missing catalog root: $rootName" }
        $extension = if ($rootName -eq 'Metadata') { '.json' } else { '.xml' }
        foreach ($file in @(Get-ChildItem -LiteralPath $rootPath -Recurse -File | Sort-Object FullName)) {
            if ($file.Extension.ToLowerInvariant() -ne $extension) { throw "Unexpected extension: $($file.FullName)" }
            [void]$records.Add([pscustomobject][ordered]@{
                RelativePath = Get-TpmSnapshotRelativePath -Root $Root -Path $file.FullName
                Root = $rootName
                FileName = $file.Name
                ProfileCode = if ($rootName -eq 'GameProfiles') { [System.IO.Path]::GetFileNameWithoutExtension($file.Name) } else { $null }
                Length = [int64]$file.Length
                Sha256 = Get-TpmSnapshotSha256File -Path $file.FullName
                SemanticSha256 = Get-TpmSemanticHash -Path $file.FullName
            })
        }
    }
    return @($records | Sort-Object RelativePath)
}

function Get-TpmProfileMap {
    param([string]$Root)
    $map = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $Root 'GameProfiles') -Filter '*.xml' -File)) {
        $code = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        if ($map.ContainsKey($code)) { throw "Duplicate profile code: $code" }
        $map[$code] = $file.FullName
    }
    return $map
}

function Get-TpmSortedNames {
    param([object[]]$Values)
    if (@($Values).Count -eq 0) { return ,@() }
    # Ordinal order (lower-case name first, then the exact name): the same list on every PC, whatever its language setting.
    $names = [string[]]@($Values)
    $nameKeys = [string[]]@($names | ForEach-Object { $_.ToLowerInvariant() + [char]0 + $_ })
    [System.Array]::Sort($nameKeys, $names, [System.StringComparer]::Ordinal)
    return ,@($names)
}

$errors = New-Object System.Collections.Generic.List[string]
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Manifest is missing: $ManifestPath" }
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
if ($manifest.SnapshotSchemaVersion -cne '1.0.0') { [void]$errors.Add('SnapshotSchemaVersion mismatch.') }
if ($manifest.SnapshotId -notmatch '^TPM-GAME-SUPPORT-RELEASE-1\.0\.0\.2128-ASSET-[0-9A-F]{8}$') { [void]$errors.Add('SnapshotId is not content-addressed.') }
if ($manifest.Release.AssetSha256 -cne '9e6a8628d365a9d7c32f1dee07f1a62799656a9fdb1b58afe863526c5cf84901') { [void]$errors.Add('Asset SHA-256 mismatch.') }
if ([int64]$manifest.Release.AssetSize -ne 153159505) { [void]$errors.Add('Asset size mismatch.') }
if ([int]$manifest.CatalogCounts.GameProfiles -ne 925 -or [int]$manifest.CatalogCounts.GameSetup -ne 383 -or [int]$manifest.CatalogCounts.Metadata -ne 923 -or [int]$manifest.CatalogCounts.TotalFiles -ne 2231) { [void]$errors.Add('Catalog count mismatch.') }
if ($manifest.SourceProof.Commit -cne 'dc998e374608abbda373bb3c236db5b26b5afca7') { [void]$errors.Add('Source-proof commit mismatch.') }
$manifestFiles = @($manifest.Files)
if ($manifestFiles.Count -ne 2231) { [void]$errors.Add("Manifest file count mismatch: $($manifestFiles.Count).") }
$badPaths = @($manifestFiles | Where-Object { [System.IO.Path]::IsPathRooted($_.RelativePath) -or $_.RelativePath.Contains('..') -or $_.RelativePath.Contains('\') -or $_.RelativePath -notmatch '^(GameProfiles|GameSetup|Metadata)/[^/]+\.(xml|json)$' })
if ($badPaths.Count -gt 0) { [void]$errors.Add('Manifest contains unsafe paths.') }
$duplicatePaths = @($manifestFiles | Group-Object RelativePath | Where-Object Count -gt 1)
if ($duplicatePaths.Count -gt 0) { [void]$errors.Add('Manifest contains duplicate paths.') }
$duplicateInsensitive = @($manifestFiles | Group-Object @{ Expression = { $_.RelativePath.ToLowerInvariant() } } | Where-Object Count -gt 1)
if ($duplicateInsensitive.Count -gt 0) { [void]$errors.Add('Manifest contains case-insensitive duplicate paths.') }
$profileFiles = @($manifestFiles | Where-Object Root -eq 'GameProfiles')
$duplicateProfiles = @($profileFiles | Group-Object @{ Expression = { $_.ProfileCode.ToLowerInvariant() } } | Where-Object Count -gt 1)
if ($duplicateProfiles.Count -gt 0) { [void]$errors.Add('Manifest contains case-insensitive duplicate profile codes.') }

if ($CatalogRoot) {
    $inventory = Get-TpmSnapshotInventory -Root $CatalogRoot
    $byPath = @{}
    foreach ($record in $inventory) { $byPath[$record.RelativePath] = $record }
    foreach ($expected in $manifestFiles) {
        if (-not $byPath.ContainsKey($expected.RelativePath)) { [void]$errors.Add("Missing catalog file: $($expected.RelativePath)"); continue }
        $actual = $byPath[$expected.RelativePath]
        if ([int64]$actual.Length -ne [int64]$expected.Length -or $actual.Sha256 -cne $expected.Sha256) { [void]$errors.Add("File hash/length mismatch: $($expected.RelativePath)") }
    }
    if ($inventory.Count -ne $manifestFiles.Count) { [void]$errors.Add('Catalog inventory count differs from manifest.') }
}

if ($SourceProofRoot) {
    $proof = Get-TpmSnapshotInventory -Root $SourceProofRoot
    $proofByPath = @{}
    foreach ($record in $proof) { $proofByPath[$record.RelativePath] = $record }
    foreach ($expected in $manifestFiles) {
        if (-not $proofByPath.ContainsKey($expected.RelativePath)) { [void]$errors.Add("Missing proof file: $($expected.RelativePath)"); continue }
        if ($proofByPath[$expected.RelativePath].SemanticSha256 -cne $expected.SemanticSha256) { [void]$errors.Add("Proof semantic mismatch: $($expected.RelativePath)") }
    }
}

if ($HistoricalCatalogRoot) {
    $currentRootForDelta = if ($CatalogRoot) { $CatalogRoot } elseif ($SourceProofRoot) { $SourceProofRoot } else { $null }
    if (-not $currentRootForDelta) { [void]$errors.Add('Historical delta validation requires CatalogRoot or SourceProofRoot.') }
    $current = if ($currentRootForDelta) { Get-TpmProfileMap -Root $currentRootForDelta } else { @{} }
    $historical = Get-TpmProfileMap -Root $HistoricalCatalogRoot
    $added = New-Object System.Collections.Generic.List[string]
    $removed = New-Object System.Collections.Generic.List[string]
    $changed = New-Object System.Collections.Generic.List[string]
    $unchanged = New-Object System.Collections.Generic.List[string]
    foreach ($key in $current.Keys) {
        if (-not $historical.ContainsKey($key)) { [void]$added.Add([System.IO.Path]::GetFileNameWithoutExtension($current[$key])); continue }
        $name = [System.IO.Path]::GetFileNameWithoutExtension($current[$key])
        if ((Get-TpmSemanticHash -Path $current[$key]) -cne (Get-TpmSemanticHash -Path $historical[$key])) { [void]$changed.Add($name) } else { [void]$unchanged.Add($name) }
    }
    foreach ($key in $historical.Keys) { if (-not $current.ContainsKey($key)) { [void]$removed.Add([System.IO.Path]::GetFileNameWithoutExtension($historical[$key])) } }
    $delta = [ordered]@{
        HistoricalProfileCount = $historical.Count
        CurrentProfileCount = $current.Count
        Added = Get-TpmSortedNames -Values @($added)
        Removed = Get-TpmSortedNames -Values @($removed)
        Changed = Get-TpmSortedNames -Values @($changed)
        Unchanged = Get-TpmSortedNames -Values @($unchanged)
    }
    if ($delta.HistoricalProfileCount -ne 695 -or $delta.CurrentProfileCount -ne 925 -or $delta.Added.Count -ne 230 -or $delta.Removed.Count -ne 0 -or $delta.Changed.Count -ne 38 -or $delta.Unchanged.Count -ne 657) { [void]$errors.Add('Regenerated delta counts mismatch.') }
    $storedDeltaPath = Join-Path ([System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($ManifestPath))) 'delta.json'
    if (Test-Path -LiteralPath $storedDeltaPath -PathType Leaf) {
        $stored = Get-Content -LiteralPath $storedDeltaPath -Raw | ConvertFrom-Json -ErrorAction Stop
        foreach ($name in @('Added', 'Removed', 'Changed', 'Unchanged')) {
            if ((@($stored.$name) -join '|') -cne (@($delta.$name) -join '|')) { [void]$errors.Add("Stored delta list mismatch: $name") }
        }
    } else { [void]$errors.Add('Stored delta manifest is missing.') }
}

$result = [pscustomobject]@{
    Valid = ($errors.Count -eq 0)
    Errors = @($errors)
    SnapshotId = [string]$manifest.SnapshotId
    ManifestFileCount = $manifestFiles.Count
    AssetSha256 = [string]$manifest.Release.AssetSha256
    CatalogCounts = $manifest.CatalogCounts
}
$result | ConvertTo-Json -Depth 20
if (-not $result.Valid) { exit 1 }
