Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-TPMReleasePackageFileMapV1 {
    param([string]$SourceRoot = (Split-Path -Parent $PSScriptRoot))
    $map = New-Object Collections.Generic.List[object]
    $rootFiles = @(
        'TeknoParrot-Manager.ps1','TeknoParrot-Manager.bat','TeknoParrot-Manager-CHANGELOG.txt','LICENSE'
    )
    foreach ($name in $rootFiles) { $map.Add([pscustomobject]@{ ZipPath = $name; SourcePath = $name }) }
    # The tester guide ships only in release candidate builds (label starts with RC), never in version 1.0.
    $candidateLabel = ''
    $mainScript = Join-Path $SourceRoot 'TeknoParrot-Manager.ps1'
    if (Test-Path -LiteralPath $mainScript -PathType Leaf) {
        $labelLine = Select-String -LiteralPath $mainScript -Pattern '^\s*\$ReleaseCandidateLabel\s*=\s*"([^"]*)"' -List
        if ($labelLine) { $candidateLabel = [string]$labelLine.Matches[0].Groups[1].Value }
    }
    if ($candidateLabel -like 'RC*') {
        $map.Add([pscustomobject]@{ ZipPath = 'TeknoParrot-Manager-Tester-Guide.pdf'; SourcePath = 'TeknoParrot-Manager-Tester-Guide.pdf'; AssetType = 'Guide' })
    }
    foreach ($item in (Get-TPMReleasePackageDocumentationFileMapV1)) {
        $map.Add([pscustomobject]@{ ZipPath = $item.ZipPath; SourcePath = $item.SourcePath; AssetType = $item.AssetType })
    }
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
    foreach ($name in @('TpmRequiredPatchEngine.ps1','TpmRequiredPatchRecipes.json','TPMCertification.Contracts.psm1','TPMCertification.Authority.psm1','TpmProgress.psm1')) {
        $path = "scripts/$name"
        $map.Add([pscustomobject]@{ ZipPath = $path; SourcePath = $path })
    }
    $map.Add([pscustomobject]@{ ZipPath = 'scripts/resources/contracts/pcsx2x6/contract.json'; SourcePath = 'contracts/pcsx2x6/contract.json' })
    $map.Add([pscustomobject]@{ ZipPath = 'scripts/resources/contracts/pcsx2x6/runtime-evidence-index.json'; SourcePath = 'contracts/pcsx2x6/runtime-evidence-index.json' })
    return $map.ToArray()
}

function Get-TPMReleasePackageDocumentationFileMapV1 {
    return @(
        [pscustomobject]@{ AssetType = 'Guide'; ZipPath = 'TeknoParrot-Manager-QuickStart.txt'; SourcePath = 'TeknoParrot-Manager-QuickStart.txt' }
        [pscustomobject]@{ AssetType = 'Guide'; ZipPath = 'TeknoParrot-Manager-README.txt'; SourcePath = 'TeknoParrot-Manager-README.txt' }
        [pscustomobject]@{ AssetType = 'Guide'; ZipPath = 'docs/START-HERE.md'; SourcePath = 'docs/START-HERE.md' }
        [pscustomobject]@{ AssetType = 'Guide'; ZipPath = 'docs/TROUBLESHOOTING.md'; SourcePath = 'docs/TROUBLESHOOTING.md' }
        [pscustomobject]@{ AssetType = 'Screenshot'; ZipPath = 'images/release/RC8-MainMenu.png'; SourcePath = 'images/release/RC8-MainMenu.png' }
        [pscustomobject]@{ AssetType = 'Screenshot'; ZipPath = 'docs/images/01-installer-window.png'; SourcePath = 'docs/images/01-installer-window.png' }
        [pscustomobject]@{ AssetType = 'Screenshot'; ZipPath = 'docs/images/02-installer-new-folder.png'; SourcePath = 'docs/images/02-installer-new-folder.png' }
        [pscustomobject]@{ AssetType = 'Screenshot'; ZipPath = 'docs/images/03-installer-core-selected.png'; SourcePath = 'docs/images/03-installer-core-selected.png' }
        [pscustomobject]@{ AssetType = 'Screenshot'; ZipPath = 'docs/images/04-installer-done.png'; SourcePath = 'docs/images/04-installer-done.png' }
        [pscustomobject]@{ AssetType = 'Screenshot'; ZipPath = 'docs/images/05-ui-first-run-information.png'; SourcePath = 'docs/images/05-ui-first-run-information.png' }
        [pscustomobject]@{ AssetType = 'Screenshot'; ZipPath = 'docs/images/06-ui-updated-policies.png'; SourcePath = 'docs/images/06-ui-updated-policies.png' }
        [pscustomobject]@{ AssetType = 'Screenshot'; ZipPath = 'docs/images/07-ui-setup-wizard.png'; SourcePath = 'docs/images/07-ui-setup-wizard.png' }
        [pscustomobject]@{ AssetType = 'Screenshot'; ZipPath = 'docs/images/08-ui-main-window.png'; SourcePath = 'docs/images/08-ui-main-window.png' }
        [pscustomobject]@{ AssetType = 'Screenshot'; ZipPath = 'docs/images/09-tpm-welcome.png'; SourcePath = 'docs/images/09-tpm-welcome.png' }
        [pscustomobject]@{ AssetType = 'Screenshot'; ZipPath = 'docs/images/10-tpm-register-only-menu.png'; SourcePath = 'docs/images/10-tpm-register-only-menu.png' }
        [pscustomobject]@{ AssetType = 'Screenshot'; ZipPath = 'docs/images/11-tpm-action-required.png'; SourcePath = 'docs/images/11-tpm-action-required.png' }
    )
}

function Assert-TPMReleasePackageScreenshotPngV1 {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$AssetPath)
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        if ($stream.Length -lt 128) { throw "PACKAGE_SCREENSHOT_INVALID_PNG: '$AssetPath' must contain at least 128 bytes" }
        $signature = [byte[]]@(137, 80, 78, 71, 13, 10, 26, 10)
        foreach ($expectedByte in $signature) {
            if ($stream.ReadByte() -ne $expectedByte) { throw "PACKAGE_SCREENSHOT_INVALID_PNG: '$AssetPath' has no PNG signature" }
        }
        $stream.Position = 12
        foreach ($expectedByte in [byte[]]@(73, 72, 68, 82)) {
            if ($stream.ReadByte() -ne $expectedByte) { throw "PACKAGE_SCREENSHOT_INVALID_PNG: '$AssetPath' has no IHDR chunk at bytes 12-15" }
        }
        $width = 0L
        $height = 0L
        for ($index = 0; $index -lt 4; $index++) { $width = $width * 256 + $stream.ReadByte() }
        for ($index = 0; $index -lt 4; $index++) { $height = $height * 256 + $stream.ReadByte() }
        if ($width -lt 640 -or $height -lt 360) {
            throw "PACKAGE_SCREENSHOT_INVALID_PNG: '$AssetPath' dimensions ${width}x${height} are below the 640x360 minimum"
        }
    } finally { $stream.Dispose() }
}

function Assert-TPMReleasePackageRequiredScreenshotSourceV1 {
    param([Parameter(Mandatory = $true)][string]$SourceRoot)
    $sourceRootFull = [System.IO.Path]::GetFullPath($SourceRoot)
    $screenshotAssets = @(Get-TPMReleasePackageDocumentationFileMapV1 | Where-Object AssetType -eq 'Screenshot')
    if ($screenshotAssets.Count -eq 0) { throw 'PACKAGE_SCREENSHOT_MANIFEST_EMPTY: at least one current screenshot asset is required' }
    # Missing captures take precedence over format failures; never substitute another image.
    foreach ($asset in $screenshotAssets) {
        $sourcePath = Join-Path $sourceRootFull ($asset.SourcePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "PACKAGE_REQUIRED_SCREENSHOT_MISSING: '$($asset.SourcePath)' must be an actual current RC8 capture"
        }
    }
    foreach ($asset in $screenshotAssets) {
        $sourcePath = Join-Path $sourceRootFull ($asset.SourcePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        Assert-TPMReleasePackageScreenshotPngV1 -Path $sourcePath -AssetPath $asset.SourcePath
    }
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

function Get-TPMReleasePackagePathLeakPatternsV1 {
    # Generic, name-free detection of personal paths and addresses in packaged text. Each pattern carries a label;
    # the report prints the label only, so a private token is never echoed into an error or log.
    $octet = '(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)'
    $patterns = New-Object Collections.Generic.List[object]
    $userProfileRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    if (-not [string]::IsNullOrWhiteSpace($userProfileRoot)) {
        $patterns.Add([pscustomobject]@{ Label = 'user-profile-path'; Regex = '(?i)' + [regex]::Escape($userProfileRoot.TrimEnd('\', '/')) + '(?:[\\/]|$)' })
    }
    # Narrow allowlist of generic placeholder account names that may appear in examples. Anything else is a leak.
    $placeholderNames = 'Public|Default(?: User)?|All Users|Shared|Example|User(?:name)?|postgres'
    $placeholderEnd = '(?:[\\/''"`,;:)\]]|\.(?!\w)|$)'
    $patterns.Add([pscustomobject]@{ Label = 'user-profile-path'; Regex = '(?i)[A-Z]:[\\/]+Users[\\/]+(?!(?:' + $placeholderNames + ')' + $placeholderEnd + ')[^\\/\s''"`<>|*?.%$<{][^\\/\s''"`<>|*?]*' })
    $patterns.Add([pscustomobject]@{ Label = 'user-profile-path'; Regex = '(?i)(?<![\w.~:/\\-])/(?:Users|home)/(?!(?:' + $placeholderNames + ')' + $placeholderEnd + ')[^/\s''"`<>|*?.%$<{][^/\s''"`<>|*?]*' })
    # A JSON file stores a UNC path with every backslash doubled: four leading and doubled separators (two leading backslashes
    # followed by doubled separators are only an escaped single-backslash path).
    $patterns.Add([pscustomobject]@{ Label = 'unc-share'; Regex = '(?<![\\\w.:])(?:(?<json>\\{4})|\\{2})(?!(?:server|nas|host|hostname|computer|example[\w.-]*)\\)[A-Za-z0-9][\w.-]*(?(json)\\{2}|\\)[\w$.-]+' })
    $patterns.Add([pscustomobject]@{ Label = 'private-ip-address'; Regex = ('(?<![\d.])(?:10\.{0}\.{0}\.{0}|192\.168\.{0}\.{0}|172\.(?:1[6-9]|2\d|3[01])\.{0}\.{0})(?!\.?\d)' -f $octet) })
    # The release owner supplies private names outside source control, separated by commas or semicolons.
    $privateTokens = [string][Environment]::GetEnvironmentVariable('TPM_PACKAGE_PRIVATE_TOKENS')
    foreach ($item in ($privateTokens -split '[,;]')) {
        $token = $item.Trim()
        if ($token.Length -eq 0) { continue }
        $patterns.Add([pscustomobject]@{ Label = 'private-token'; Regex = '(?i)(?<![A-Za-z0-9])' + [regex]::Escape($token) + '(?![A-Za-z0-9])' })
    }
    return $patterns.ToArray()
}

function Test-TPMReleasePackageArchiveV1 {

    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [string]$SourceRoot = (Split-Path -Parent $PSScriptRoot),
        [string]$ExpectedDisplayVersion = 'v1.0 RC8.4'
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
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                if ($null -ne $item.PSObject.Properties['AssetType'] -and [string]$item.AssetType -ceq 'Screenshot') {
                    throw "PACKAGE_SOURCE_SCREENSHOT_MISSING: '$($item.SourcePath)'"
                }
                throw "PACKAGE_SOURCE_FILE_MISSING: '$($item.SourcePath)'"
            }
            if ($null -ne $item.PSObject.Properties['AssetType'] -and [string]$item.AssetType -ceq 'Screenshot') {
                Assert-TPMReleasePackageScreenshotPngV1 -Path $sourcePath -AssetPath $item.SourcePath
            }
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
            if ([System.IO.Path]::GetExtension($zipName) -ieq '.md') {
                $markdownStream = $entry.Open()
                try {
                    $markdownReader = New-Object System.IO.StreamReader($markdownStream)
                    try { $markdown = $markdownReader.ReadToEnd() } finally { $markdownReader.Dispose() }
                } finally { $markdownStream.Dispose() }
                if ($markdown.Contains('[SCREENSHOT:')) { throw "PACKAGE_DOCUMENTATION_PLACEHOLDER: '$zipName' contains an unresolved screenshot placeholder" }
            }
        }

        $textPathPatterns = @(Get-TPMReleasePackagePathLeakPatternsV1)
        $pathLeaks = New-Object Collections.Generic.List[string]
        foreach ($entry in $archive.Entries) {
            if ($entry.Length -le 0 -or $entry.FullName.EndsWith('/') -or $entry.FullName -notmatch '\.(bat|json|md|ps1|psm1|svg|txt)$') { continue }
            $stream = $entry.Open()
            try {
                $reader = New-Object System.IO.StreamReader($stream)
                try { $content = $reader.ReadToEnd() } finally { $reader.Dispose() }
            } finally { $stream.Dispose() }
            foreach ($leakPattern in $textPathPatterns) {
                if ($content -match $leakPattern.Regex) { $pathLeaks.Add("$($entry.FullName) [$($leakPattern.Label)]"); break }
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
        return [pscustomobject]@{
            ZipPath = $resolvedZip
            EntryCount = $archive.Entries.Count
            FileCount = $fileMap.Count
            CrosshairPngCount = @($entryMap.Keys | Where-Object { $_ -cmatch '^Crosshairs/\d{3}\.png$' }).Count
            PathLeakCount = $pathLeaks.Count
            ExpectedVersion = $ExpectedDisplayVersion
            Valid = $true
        }
    } finally { $archive.Dispose() }
}

Export-ModuleMember -Function Get-TPMReleasePackageDocumentationFileMapV1, Get-TPMReleasePackageFileMapV1, Assert-TPMReleasePackageRequiredScreenshotSourceV1, Get-TPMReleasePackageDirectoryEntriesV1, Test-TPMReleasePackageArchiveV1
