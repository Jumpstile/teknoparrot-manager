# Shared helpers for the catalog snapshot tools (New-TpmReleaseCatalogSnapshot.ps1, New-TpmCatalogSnapshotFromInstall.ps1).
# Dot-source this file; it only defines functions and runs nothing.
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
    # Ordinal order (namespace, then local name): the same text on every PC, whatever its language setting.
    $attributes = [System.Xml.XmlAttribute[]]@($Node.Attributes)
    $attributeKeys = [string[]]@($attributes | ForEach-Object { $_.NamespaceURI + [char]0 + $_.LocalName })
    [System.Array]::Sort($attributeKeys, $attributes, [System.StringComparer]::Ordinal)
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
        # The pinned hashes were made by Windows PowerShell 5.1, which read these UTF-8 files as Windows-1252. Read them the same way on every engine and PC.
        $value = [System.Text.Encoding]::GetEncoding(1252).GetString([System.IO.File]::ReadAllBytes($Path)) | ConvertFrom-Json -ErrorAction Stop
        $canonical = ConvertTo-TpmCanonicalJsonValue -Value $value
        return Get-TpmSnapshotSha256Bytes -Bytes ([System.Text.Encoding]::UTF8.GetBytes($canonical))
    }
    throw "Unsupported semantic file type: $Path"
}

function ConvertTo-TpmJsonEscaped {
    param([object]$Value, [int]$Depth = 5)
    # Windows PowerShell 5.1 writes ' < > & as \u0027 \u003c \u003e \u0026; PowerShell 7 writes them as-is. Pin the 5.1 text so the hash is the same on both.
    return (ConvertTo-Json -InputObject $Value -Compress -Depth $Depth).Replace("'", '\u0027').Replace('<', '\u003c').Replace('>', '\u003e').Replace('&', '\u0026')
}

function ConvertTo-TpmCanonicalJsonValue {
    param([object]$Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [System.Collections.IDictionary]) {
        $parts = New-Object System.Collections.Generic.List[string]
        # Ordinal order, so the same data gives the same canonical JSON whatever the PC's language setting is.
        $sortedKeys = [string[]]@($Value.Keys)
        [System.Array]::Sort($sortedKeys, [System.StringComparer]::Ordinal)
        foreach ($key in $sortedKeys) {
            [void]$parts.Add((ConvertTo-TpmJsonEscaped -Value ([string]$key)) + ':' + (ConvertTo-TpmCanonicalJsonValue -Value $Value[$key]))
        }
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value -is [pscustomobject]) {
        $parts = New-Object System.Collections.Generic.List[string]
        $propertyNames = [string[]]@($Value.PSObject.Properties | ForEach-Object { $_.Name })
        [System.Array]::Sort($propertyNames, [System.StringComparer]::Ordinal)
        foreach ($propertyName in $propertyNames) {
            [void]$parts.Add((ConvertTo-TpmJsonEscaped -Value $propertyName) + ':' + (ConvertTo-TpmCanonicalJsonValue -Value $Value.PSObject.Properties[$propertyName].Value))
        }
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($item in @($Value)) { [void]$parts.Add((ConvertTo-TpmCanonicalJsonValue -Value $item)) }
        return '[' + ($parts -join ',') + ']'
    }
    return (ConvertTo-TpmJsonEscaped -Value $Value -Depth 20)
}

function Assert-TpmCatalogRoot {
    param([string]$Root, [switch]$InstallMode)
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "Catalog root is missing: $Root" }
    # An installed TeknoParrot folder must have GameProfiles; GameSetup and Metadata are used only when it has them.
    foreach ($name in $(if ($InstallMode) { @('GameProfiles') } else { @('GameProfiles', 'GameSetup', 'Metadata') })) {
        $path = Join-Path $Root $name
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Catalog root is missing: $name" }
    }
}

# -InstallMode reads an installed folder: files that are not a profile/setup XML or metadata JSON directly inside the root folder are
# left out of the list and named in $script:TpmSnapshotSkippedFiles, never silently dropped. Without it any such file is an error.
function Get-TpmCatalogRecords {
    param([string]$Root, [switch]$InstallMode)
    Assert-TpmCatalogRoot -Root $Root -InstallMode:$InstallMode
    $script:TpmSnapshotSkippedFiles = New-Object System.Collections.Generic.List[string]
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($rootName in @('GameProfiles', 'GameSetup', 'Metadata')) {
        $extension = if ($rootName -eq 'Metadata') { '.json' } else { '.xml' }
        $rootPath = Join-Path $Root $rootName
        if ($InstallMode -and -not (Test-Path -LiteralPath $rootPath -PathType Container)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $rootPath -Recurse -File | Sort-Object FullName)) {
            if ($InstallMode -and ($file.Extension.ToLowerInvariant() -ne $extension -or $file.DirectoryName.TrimEnd('\') -ne (Get-TpmFullPath -Path $rootPath))) {
                [void]$script:TpmSnapshotSkippedFiles.Add((Get-TpmRelativePath -Root $Root -Path $file.FullName))
                continue
            }
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
    # Ordinal order (lower-case path first, then the exact path): the same list on every PC, whatever its language setting.
    $sortedRecords = $records.ToArray()
    $sortKeys = [string[]]@($sortedRecords | ForEach-Object { $_.RelativePath.ToLowerInvariant() + [char]0 + $_.RelativePath })
    [System.Array]::Sort($sortKeys, $sortedRecords, [System.StringComparer]::Ordinal)
    return @($sortedRecords)
}

function Get-TpmRootSemanticDigest {
    param([object[]]$Records, [string]$RootName)
    $rootRecords = [object[]]@($Records | Where-Object Root -eq $RootName)
    $rootPaths = [string[]]@($rootRecords | ForEach-Object { $_.RelativePath })
    [System.Array]::Sort($rootPaths, $rootRecords, [System.StringComparer]::Ordinal)
    $lines = @($rootRecords | ForEach-Object { $_.RelativePath + '|' + $_.SemanticSha256 })
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
    # Ordinal order (lower-case name first, then the exact name): the same list on every PC, whatever its language setting.
    $names = [string[]]@($Values)
    $nameKeys = [string[]]@($names | ForEach-Object { $_.ToLowerInvariant() + [char]0 + $_ })
    [System.Array]::Sort($nameKeys, $names, [System.StringComparer]::Ordinal)
    return ,@($names)
}
function Write-TpmSnapshotJson {
    param([object]$Value, [string]$Path)
    $parent = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Path))
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [void][System.IO.Directory]::CreateDirectory($parent) }
    $encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList ([object]$false)
    [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 100), $encoding)
}

# A pinned snapshot folder is never refreshed in place: an existing manifest must describe this same snapshot and asset.
function Assert-TpmSnapshotOutputRoot {
    param([string]$ManifestPath, [string]$SnapshotId, [string]$AssetSha256, [string]$OutputRoot)
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { return }
    $existingId = $null; $existingAsset = $null
    try { $existing = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json -ErrorAction Stop; $existingId = [string]$existing.SnapshotId; $existingAsset = [string]$existing.Release.AssetSha256 } catch { $null = $_ }
    if ($existingId -cne $SnapshotId -or $existingAsset -cne $AssetSha256) { throw "OutputRoot already holds a different snapshot ($existingId). A changed asset needs a new reviewed snapshot in a new folder; nothing was written: $OutputRoot" }
}

# Delta of two profile lists (records from Get-TpmCatalogRecords or from a snapshot manifest's Files): added, removed, semantically changed, unchanged.
# Formatting-only means the file bytes differ but the parsed content does not. Same field names as the delta.json of New-TpmReleaseCatalogSnapshot.ps1.
function Get-TpmDeltaFromRecords {
    param([object[]]$CurrentRecords, [object[]]$HistoricalRecords, [string]$HistoricalSourceCommit)
    $current = @{}
    foreach ($record in @($CurrentRecords | Where-Object Root -eq 'GameProfiles')) { $current[[string]$record.ProfileCode] = $record }
    $historical = @{}
    foreach ($record in @($HistoricalRecords | Where-Object Root -eq 'GameProfiles')) { $historical[[string]$record.ProfileCode] = $record }
    $added = New-Object System.Collections.Generic.List[string]
    $removed = New-Object System.Collections.Generic.List[string]
    $changed = New-Object System.Collections.Generic.List[string]
    $unchanged = New-Object System.Collections.Generic.List[string]
    $rawDifferent = New-Object System.Collections.Generic.List[string]
    foreach ($key in $current.Keys) {
        $name = [string]$current[$key].ProfileCode
        if (-not $historical.ContainsKey($key)) { [void]$added.Add($name); continue }
        if ($current[$key].Sha256 -cne $historical[$key].Sha256) { [void]$rawDifferent.Add($name) }
        if ($current[$key].SemanticSha256 -cne $historical[$key].SemanticSha256) { [void]$changed.Add($name) } else { [void]$unchanged.Add($name) }
    }
    foreach ($key in $historical.Keys) { if (-not $current.ContainsKey($key)) { [void]$removed.Add([string]$historical[$key].ProfileCode) } }
    return [ordered]@{
        HistoricalSourceCommit = $HistoricalSourceCommit
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
}
