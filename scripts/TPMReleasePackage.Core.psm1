Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-TPMReleasePackageFileMapV1 {
    param([string]$SourceRoot = (Split-Path -Parent $PSScriptRoot))
    $map = New-Object Collections.Generic.List[object]
    $rootFiles = @(
        'TeknoParrot-Manager.ps1','TeknoParrot-Manager.bat','TeknoParrot-Manager-README.txt',
        'TeknoParrot-Manager-QuickStart.txt','TeknoParrot-Manager-CHANGELOG.txt','LICENSE'
    )
    foreach ($name in $rootFiles) { $map.Add([pscustomobject]@{ ZipPath = $name; SourcePath = $name }) }
    foreach ($number in 0..320) {
        $name = ('{0:D3}.png' -f $number)
        $map.Add([pscustomobject]@{ ZipPath = "Crosshairs/$name"; SourcePath = "Crosshairs/$name" })
    }
    foreach ($name in @(
        'TPM-preview-landscape.png','TPM-preview-original.svg','TPM-preview-clean.svg',
        'TPM-preview-vivid.svg','TPM-preview-crt.svg','TPM-preview-enhanced.svg'
    )) {
        $path = "PreviewAssets/ReShadePreviews/$name"
        $map.Add([pscustomobject]@{ ZipPath = $path; SourcePath = $path })
    }
    foreach ($name in @('Invoke-TpmAutoUpdate.ps1','TpmAutoUpdate.Core.psm1')) {
        $path = "tools/$name"
        $map.Add([pscustomobject]@{ ZipPath = $path; SourcePath = $path })
    }
    foreach ($name in @('TpmRequiredPatchEngine.ps1','TpmRequiredPatchRecipes.json','TPMCertification.Contracts.psm1','TPMCertification.Authority.psm1')) {
        $path = "scripts/$name"
        $map.Add([pscustomobject]@{ ZipPath = $path; SourcePath = $path })
    }
    $map.Add([pscustomobject]@{ ZipPath = 'scripts/resources/contracts/pcsx2x6/contract.json'; SourcePath = 'contracts/pcsx2x6/contract.json' })
    $map.Add([pscustomobject]@{ ZipPath = 'scripts/resources/contracts/pcsx2x6/runtime-evidence-index.json'; SourcePath = 'contracts/pcsx2x6/runtime-evidence-index.json' })
    return $map.ToArray()
}

function Get-TPMReleasePackageDirectoryEntriesV1 {
    param([Parameter(Mandatory = $true)][object[]]$FileMap)
    $directories = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($item in $FileMap) {
        $parts = ([string]$item.ZipPath).Split('/')
        for ($i = 1; $i -lt $parts.Length; $i++) {
            $directories.Add((($parts[0..($i - 1)] -join '/') + '/')) | Out-Null
        }
    }
    $result = [string[]]@($directories)
    [Array]::Sort($result, [StringComparer]::Ordinal)
    return $result
}

function Get-TPMReleasePackageEntrySha256V1 {
    param([Parameter(Mandatory = $true)][System.IO.Stream]$Stream, [Parameter(Mandatory = $true)][long]$MaximumLength)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $buffer = New-Object byte[] 65536
    $total = 0L
    try {
        while ($true) {
            $remainingWithSentinel = $MaximumLength - $total + 1
            $readLimit = [int][Math]::Min([long]$buffer.Length, $remainingWithSentinel)
            $read = $Stream.Read($buffer, 0, $readLimit)
            if ($read -eq 0) { break }
            $total += $read
            if ($total -gt $MaximumLength) { throw 'PACKAGE_ENTRY_OVERSIZE: stream exceeds the source file length' }
            $sha.TransformBlock($buffer, 0, $read, $buffer, 0) | Out-Null
        }
        $sha.TransformFinalBlock([byte[]]@(), 0, 0) | Out-Null
        return [pscustomobject]@{ Length = $total; Sha256 = ([BitConverter]::ToString($sha.Hash)).Replace('-', '').ToUpperInvariant() }
    } finally { $sha.Dispose() }
}

function Test-TPMReleasePackageArchiveV1 {

    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [string]$SourceRoot = (Split-Path -Parent $PSScriptRoot),
        [string]$ExpectedDisplayVersion = 'v1.0 RC8'
    )
    Set-StrictMode -Version Latest
    $sourceRootFull = [System.IO.Path]::GetFullPath($SourceRoot)
    if (-not (Test-Path -LiteralPath $sourceRootFull -PathType Container)) { throw "PACKAGE_SOURCE_ROOT_MISSING: $sourceRootFull" }
    $resolvedZip = (Resolve-Path -LiteralPath $ZipPath).Path
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $fileMap = @(Get-TPMReleasePackageFileMapV1 -SourceRoot $sourceRootFull)
    $sourceCrosshairs = @(Get-ChildItem -LiteralPath (Join-Path $sourceRootFull 'Crosshairs') -File -ErrorAction Stop | ForEach-Object { $_.Name })
    $expectedCrosshairs = @(0..320 | ForEach-Object { '{0:D3}.png' -f $_ })
    if ($sourceCrosshairs.Count -ne 321 -or @($sourceCrosshairs | Where-Object { $expectedCrosshairs -cnotcontains $_ }).Count -ne 0) {
        throw 'PACKAGE_SOURCE_CROSSHAIRS_INVALID: source must contain exactly 000.png through 320.png'
    }

    $contractDirectory = Join-Path $sourceRootFull 'contracts/pcsx2x6'
    $contractsModule = Join-Path $sourceRootFull 'scripts/TPMCertification.Contracts.psm1'
    Import-Module $contractsModule -Force -ErrorAction Stop
    $projection = Get-TPMSourceEvidenceProjectionV1 -ContractPath (Join-Path $contractDirectory 'contract.json') -ContractDirectory $contractDirectory
    $sourceIndexPath = Join-Path $contractDirectory 'runtime-evidence-index.json'
    if (-not (Test-Path -LiteralPath $sourceIndexPath -PathType Leaf)) { throw 'PACKAGE_SOURCE_INDEX_MISSING: runtime-evidence-index.json is required' }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $expectedIndexBytes = $utf8.GetBytes([string]$projection.Json)
    $actualIndexBytes = [System.IO.File]::ReadAllBytes($sourceIndexPath)
    $indexBytesMatch = $actualIndexBytes.Length -eq $expectedIndexBytes.Length
    if ($indexBytesMatch) {
        for ($i = 0; $i -lt $actualIndexBytes.Length; $i++) {
            if ($actualIndexBytes[$i] -ne $expectedIndexBytes[$i]) { $indexBytesMatch = $false; break }
        }
    }
    if (-not $indexBytesMatch) {
        throw 'PACKAGE_SOURCE_INDEX_STALE: runtime-evidence-index.json differs from the deterministic projection of actual source contract and Markdown'
    }

    $expectedFiles = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($item in $fileMap) { $expectedFiles.Add([string]$item.ZipPath) | Out-Null }
    $expectedDirectories = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($path in (Get-TPMReleasePackageDirectoryEntriesV1 -FileMap $fileMap)) { $expectedDirectories.Add($path) | Out-Null }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $archive = [System.IO.Compression.ZipFile]::OpenRead($resolvedZip)
    try {
        $maximumEntryCount = $fileMap.Count + $expectedDirectories.Count
        if ($archive.Entries.Count -gt $maximumEntryCount) { throw "PACKAGE_ENTRY_COUNT_EXCEEDED: $($archive.Entries.Count) exceeds $maximumEntryCount" }
        $entryMap = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
        foreach ($entry in $archive.Entries) {
            $raw = [string]$entry.FullName
            if ([string]::IsNullOrWhiteSpace($raw) -or $raw.Contains('\') -or $raw.StartsWith('/') -or $raw.Contains(':')) {
                throw "PACKAGE_PATH_NONCANONICAL: '$raw'"
            }
            $isDirectory = $raw.EndsWith('/')
            $path = if ($isDirectory) { $raw.Substring(0, $raw.Length - 1) } else { $raw }
            $segments = $path.Split('/')
            if ($path.Length -eq 0 -or @($segments | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
                throw "PACKAGE_PATH_NONCANONICAL: '$raw'"
            }
            if (-not $seen.Add($path)) { throw "PACKAGE_PATH_DUPLICATE_OR_CASE_COLLISION: '$raw'" }
            if ($isDirectory) {
                if (-not $expectedDirectories.Contains($raw)) { throw "PACKAGE_ENTRY_UNKNOWN: '$raw'" }
            } else {
                if (-not $expectedFiles.Contains($raw)) { throw "PACKAGE_ENTRY_UNKNOWN: '$raw'" }
                $entryMap.Add($raw, $entry)
            }
        }
        foreach ($item in $fileMap) {
            $zipName = [string]$item.ZipPath
            if (-not $entryMap.ContainsKey($zipName)) { throw "PACKAGE_ENTRY_MISSING: '$zipName'" }
            $sourcePath = Join-Path $sourceRootFull ($item.SourcePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "PACKAGE_SOURCE_FILE_MISSING: '$($item.SourcePath)'" }
            $sourceLength = (Get-Item -LiteralPath $sourcePath -ErrorAction Stop).Length
            $entry = $entryMap[$zipName]
            if ([long]$entry.Length -ne [long]$sourceLength) { throw "PACKAGE_SOURCE_SIZE_MISMATCH: '$zipName'" }

            $sourceStream = $null
            $zipStream = $null
            try {
                $sourceStream = [System.IO.File]::OpenRead($sourcePath)
                $zipStream = $entry.Open()
                $sourceHash = Get-TPMReleasePackageEntrySha256V1 -Stream $sourceStream -MaximumLength $sourceLength
                $zipHash = Get-TPMReleasePackageEntrySha256V1 -Stream $zipStream -MaximumLength $sourceLength
            } finally {
                if ($null -ne $zipStream) { $zipStream.Dispose() }
                if ($null -ne $sourceStream) { $sourceStream.Dispose() }
            }
            if ($sourceHash.Length -ne $sourceLength -or $zipHash.Length -ne $sourceLength -or
                $sourceHash.Sha256 -cne $zipHash.Sha256) {
                throw "PACKAGE_SOURCE_CONTENT_MISMATCH: '$zipName'"
            }
        }

        $textPathPatterns = @('W:\\','\\\\omvnas\\')
        $userProfileRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
        if (-not [string]::IsNullOrWhiteSpace($userProfileRoot)) {
            $profileRootPattern = '(?i)' + [regex]::Escape($userProfileRoot.TrimEnd('\','/')) + '(?:[\\/]|$)'
            $textPathPatterns += $profileRootPattern
        }
        $pathLeaks = New-Object Collections.Generic.List[string]
        foreach ($entry in $archive.Entries) {
            if ($entry.Length -le 0 -or $entry.FullName.EndsWith('/') -or $entry.FullName -notmatch '\.(bat|json|ps1|psm1|txt)$') { continue }
            $stream = $entry.Open()
            try {
                $reader = New-Object System.IO.StreamReader($stream)
                try { $content = $reader.ReadToEnd() } finally { $reader.Dispose() }
            } finally { $stream.Dispose() }
            foreach ($pattern in $textPathPatterns) {
                if ($content -match $pattern) { $pathLeaks.Add("$($entry.FullName) [$pattern]"); break }
            }
        }
        if ($pathLeaks.Count -gt 0) { throw "PACKAGE_PATH_LEAK: $($pathLeaks -join ', ')" }

        $scriptEntry = $entryMap['TeknoParrot-Manager.ps1']
        $scriptStream = $scriptEntry.Open()
        try {
            $reader = New-Object System.IO.StreamReader($scriptStream, [System.Text.Encoding]::ASCII)
            try { $scriptContent = $reader.ReadToEnd() } finally { $reader.Dispose() }
        } finally { $scriptStream.Dispose() }
        if ($scriptContent -notmatch [regex]::Escape("# TeknoParrot Manager  |  $ExpectedDisplayVersion")) { throw "PACKAGE_VERSION_INVALID: expected '$ExpectedDisplayVersion' in script header" }
        if ($ExpectedDisplayVersion -notmatch '^v[\d.]+\s+(\S+)$') { throw 'PACKAGE_VERSION_INVALID: cannot derive release-candidate label' }
        if ($scriptContent -notmatch ('\$ReleaseCandidateLabel\s*=\s*"{0}"' -f [regex]::Escape($Matches[1]))) { throw 'PACKAGE_VERSION_INVALID: ReleaseCandidateLabel mismatch' }
        if ($scriptContent -notmatch 'Get-ManagerVersionLine' -or $scriptContent -match 'TeknoParrot Manager\s+v\$ScriptVersion RC1') { throw 'PACKAGE_VERSION_INVALID: stale or inconsistent product banner' }
        if ($scriptContent -notmatch 'function Get-MainMenuRenderMetrics' -or $scriptContent -notmatch 'function Join-MainMenuColumns') { throw 'PACKAGE_VERSION_INVALID: adaptive menu renderer missing' }
        return [pscustomobject]@{
            ZipPath = $resolvedZip
            EntryCount = $archive.Entries.Count
            FileCount = $fileMap.Count
            CrosshairPngCount = 321
            PathLeakCount = 0
            ExpectedVersion = $ExpectedDisplayVersion
            Valid = $true
        }
    } finally { $archive.Dispose() }
}

Export-ModuleMember -Function Get-TPMReleasePackageFileMapV1, Get-TPMReleasePackageDirectoryEntriesV1, Test-TPMReleasePackageArchiveV1
