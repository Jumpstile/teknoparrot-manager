#Requires -Version 5.1
#Requires -Module Pester

$script:repoRoot = Split-Path -Parent $PSScriptRoot
$script:requiredRc8ScreenshotRelativePath = 'images/release/RC8-MainMenu.png'

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:requiredRc8ScreenshotRelativePath = 'images/release/RC8-MainMenu.png'
    $script:packageTestDriveRoot = [IO.Path]::GetFullPath($TestDrive)
    $script:expectedGuidePaths = @('TeknoParrot-Manager-README.txt','TeknoParrot-Manager-QuickStart.txt','docs/START-HERE.md','docs/TROUBLESHOOTING.md','TeknoParrot-Manager-User-Guide.pdf')
    $script:expectedScreenshotPaths = @(
        $script:requiredRc8ScreenshotRelativePath
        'docs/images/01-installer-window.png'
        'docs/images/02-installer-new-folder.png'
        'docs/images/03-installer-core-selected.png'
        'docs/images/04-installer-done.png'
        'docs/images/05-ui-first-run-information.png'
        'docs/images/06-ui-updated-policies.png'
        'docs/images/07-ui-setup-wizard.png'
        'docs/images/08-ui-main-window.png'
        'docs/images/09-tpm-welcome.png'
        'docs/images/10-tpm-register-only-menu.png'
        'docs/images/11-tpm-action-required.png'
        'docs/images/12-tpm-first-run-questions.png'
        'docs/images/13-tpm-main-menu.png'
        'docs/images/14-tpm-help.png'
        'docs/images/15-tpm-health-check.png'
        'docs/images/16-tpm-support-package.png'
        'docs/images/17-tpm-required-patches.png'
        'docs/images/18-tpm-register-only.png'
        'docs/images/19-tpm-propagate-controls.png'
        'docs/images/20-tpm-crosshair-picker.png'
        'docs/images/21-tpm-crosshair-apply.png'
        'docs/images/22-tpm-reshade-setup.png'
    )
    $script:syntheticPackagePngBytes = @{}

function New-SyntheticTestOnlyPackageScreenshot {
    param([Parameter(Mandatory = $true)][string]$Path, [int]$Width = 640, [int]$Height = 360)
    $pathFull = [IO.Path]::GetFullPath($Path)
    $testDrivePrefix = $script:packageTestDriveRoot.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    if (-not $pathFull.StartsWith($testDrivePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Synthetic package PNGs must remain below Pester TestDrive.'
    }
    $key = "${Width}x${Height}"
    if (-not $script:syntheticPackagePngBytes.ContainsKey($key)) {
        # Flat black, 1-bit grayscale, filter zero. Stored DEFLATE blocks avoid
        # runtime-dependent compression output; CRC32 and Adler32 are explicit.
        $raw = New-Object byte[] ((1 + [int][Math]::Ceiling($Width / 8.0)) * $Height)
        $ihdr = New-Object byte[] 13
        for ($index = 0; $index -lt 4; $index++) {
            $shift = 24 - 8 * $index
            $ihdr[$index] = [byte](($Width -shr $shift) -band 255)
            $ihdr[4 + $index] = [byte](($Height -shr $shift) -band 255)
        }
        $ihdr[8] = 1
        $zlib = New-Object IO.MemoryStream
        $png = New-Object IO.MemoryStream
        try {
            $zlib.WriteByte(120); $zlib.WriteByte(1)
            for ($offset = 0; $offset -lt $raw.Length; $offset += $blockLength) {
                $blockLength = [Math]::Min(65535, $raw.Length - $offset)
                $finalBlock = if ($offset + $blockLength -eq $raw.Length) { 1 } else { 0 }
                $zlib.WriteByte([byte]$finalBlock)
                $zlib.WriteByte([byte]($blockLength -band 255))
                $zlib.WriteByte([byte](($blockLength -shr 8) -band 255))
                $complement = 65535 - $blockLength
                $zlib.WriteByte([byte]($complement -band 255))
                $zlib.WriteByte([byte](($complement -shr 8) -band 255))
                $zlib.Write($raw, $offset, $blockLength)
            }
            $adler = (([long]($raw.Length % 65521) -shl 16) -bor 1)
            foreach ($shift in @(24,16,8,0)) { $zlib.WriteByte([byte](($adler -shr $shift) -band 255)) }
            $signature = [byte[]]@(137,80,78,71,13,10,26,10)
            $png.Write($signature, 0, $signature.Length)
            foreach ($chunk in @(
                @{ Type = 'IHDR'; Data = $ihdr }
                @{ Type = 'IDAT'; Data = $zlib.ToArray() }
                @{ Type = 'IEND'; Data = [byte[]]@() }
            )) {
                $data = [byte[]]$chunk.Data
                foreach ($shift in @(24,16,8,0)) { $png.WriteByte([byte](($data.Length -shr $shift) -band 255)) }
                $type = [Text.Encoding]::ASCII.GetBytes($chunk.Type)
                $png.Write($type, 0, $type.Length)
                $png.Write($data, 0, $data.Length)
                $crc = 4294967295L
                foreach ($part in @($type, $data)) {
                    foreach ($value in $part) {
                        $crc = $crc -bxor $value
                        for ($bit = 0; $bit -lt 8; $bit++) {
                            if ($crc -band 1) { $crc = ($crc -shr 1) -bxor 3988292384L }
                            else { $crc = $crc -shr 1 }
                        }
                    }
                }
                $crc = $crc -bxor 4294967295L
                foreach ($shift in @(24,16,8,0)) { $png.WriteByte([byte](($crc -shr $shift) -band 255)) }
            }
            $script:syntheticPackagePngBytes[$key] = $png.ToArray()
        } finally { $png.Dispose(); $zlib.Dispose() }
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $pathFull) -Force | Out-Null
    [IO.File]::WriteAllBytes($pathFull, $script:syntheticPackagePngBytes[$key])
}

function New-PackageSourceFixture {
    param([Parameter(Mandatory = $true)][string]$Destination, [Parameter(Mandatory = $true)][string]$RepositoryRoot)
    $destinationFull = [IO.Path]::GetFullPath($Destination)
    $testDrivePrefix = $script:packageTestDriveRoot.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    if (-not $destinationFull.StartsWith($testDrivePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Synthetic package fixtures must remain below Pester TestDrive.'
    }
    $map = @(Get-TPMReleasePackageFileMapV1 -SourceRoot $RepositoryRoot)
    foreach ($item in $map) {
        if ($null -ne $item.PSObject.Properties['AssetType'] -and [string]$item.AssetType -ceq 'Screenshot') { continue }
        $source = Join-Path $RepositoryRoot ($item.SourcePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
        $target = Join-Path $Destination ($item.SourcePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Package fixture source missing: '$($item.SourcePath)'"
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
        if ([IO.Path]::GetExtension($item.ZipPath) -ceq '.md') {
            $text = [IO.File]::ReadAllText($target)
            $resolved = [regex]::Replace($text, '\[SCREENSHOT: docs/(images/[^ |]+) \|[^\r\n]*\]', '![Synthetic test-only capture]($1)')
            if ($resolved -cne $text) {
                [IO.File]::WriteAllText($target, $resolved, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }
    foreach ($item in @($map | Where-Object AssetType -ceq 'Screenshot')) {
        $syntheticScreenshot = Join-Path $Destination ($item.SourcePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
        New-SyntheticTestOnlyPackageScreenshot -Path $syntheticScreenshot
        [IO.File]::WriteAllText((Join-Path (Split-Path -Parent $syntheticScreenshot) 'SYNTHETIC-TEST-ONLY.txt'), 'Flat-black PNG fixture generated by Pester. It is not an RC8 screenshot or release evidence.', (New-Object System.Text.UTF8Encoding($false)))
    }
    $fixtureValidatorDirectory = Join-Path $Destination 'Tests'
    New-Item -ItemType Directory -Path $fixtureValidatorDirectory -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'Tests/Test-ReleasePackage.ps1') -Destination (Join-Path $fixtureValidatorDirectory 'Test-ReleasePackage.ps1') -Force
    $fixtureScriptsDirectory = Join-Path $Destination 'scripts'
    New-Item -ItemType Directory -Path $fixtureScriptsDirectory -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'scripts/TPMReleasePackage.Core.psm1') -Destination (Join-Path $fixtureScriptsDirectory 'TPMReleasePackage.Core.psm1') -Force
    foreach ($name in @('evidence.md','experiments.md')) {
        $source = Join-Path $RepositoryRoot "contracts/pcsx2x6/$name"
        $target = Join-Path $Destination "contracts/pcsx2x6/$name"
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
    }
}


function Copy-PackageArchiveFixture {
    param([string]$Source, [string]$Destination)
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Add-PackageArchiveEntry {
    param([string]$ZipPath, [string]$Name, [string]$Text, [switch]$Replace)
    $mode = if (Test-Path -LiteralPath $ZipPath -PathType Leaf) { [System.IO.Compression.ZipArchiveMode]::Update } else { [System.IO.Compression.ZipArchiveMode]::Create }
    $archive = [System.IO.Compression.ZipFile]::Open($ZipPath, $mode)
    try {
        if ($Replace) {
            $existing = $archive.GetEntry($Name)
            if ($null -ne $existing) { $existing.Delete() }
        }
        $entry = $archive.CreateEntry($Name)
        $stream = $entry.Open()
        try {
            $writer = New-Object System.IO.StreamWriter($stream, (New-Object System.Text.UTF8Encoding($false)))
            try { $writer.Write($Text) } finally { $writer.Dispose() }
        } finally { $stream.Dispose() }
    } finally { $archive.Dispose() }
}

function Set-PackageArchiveFile {
    param([string]$ZipPath, [string]$Name, [string]$SourcePath)
    $archive = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Update)
    try {
        $entry = $archive.GetEntry($Name)
        if ($null -ne $entry) { $entry.Delete() }
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $SourcePath, $Name, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    } finally { $archive.Dispose() }
}

function Remove-PackageArchiveEntry {
    param([string]$ZipPath, [string]$Name)
    $archive = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Update)
    try { $entry = $archive.GetEntry($Name); if ($null -ne $entry) { $entry.Delete() } }
    finally { $archive.Dispose() }
}

function Corrupt-PackageArchiveCompressedMember {
    param([Parameter(Mandatory = $true)][string]$ZipPath, [Parameter(Mandatory = $true)][string]$Name)
    $bytes = [IO.File]::ReadAllBytes($ZipPath)
    $eocd = -1
    for ($offset = $bytes.Length - 22; $offset -ge [Math]::Max(0, $bytes.Length - 65557); $offset--) {
        if ([BitConverter]::ToUInt32($bytes, $offset) -eq 0x06054b50) { $eocd = $offset; break }
    }
    if ($eocd -lt 0) { throw 'Synthetic ZIP end record missing' }
    $entryCount = [BitConverter]::ToUInt16($bytes, $eocd + 10)
    $centralOffset = [BitConverter]::ToUInt32($bytes, $eocd + 16)
    $cursor = [int]$centralOffset
    for ($index = 0; $index -lt $entryCount; $index++) {
        if ([BitConverter]::ToUInt32($bytes, $cursor) -ne 0x02014b50) { throw 'Synthetic ZIP central directory malformed' }
        $method = [BitConverter]::ToUInt16($bytes, $cursor + 10)
        $compressedLength = [BitConverter]::ToUInt32($bytes, $cursor + 20)
        $nameLength = [BitConverter]::ToUInt16($bytes, $cursor + 28)
        $extraLength = [BitConverter]::ToUInt16($bytes, $cursor + 30)
        $commentLength = [BitConverter]::ToUInt16($bytes, $cursor + 32)
        $entryName = [Text.Encoding]::UTF8.GetString($bytes, $cursor + 46, $nameLength)
        if ($entryName -ceq $Name) {
            if ($method -ne 8 -or $compressedLength -lt 4) { throw \"Member $Name was not Deflate-compressed for this test\" }
            $localOffset = [BitConverter]::ToUInt32($bytes, $cursor + 42)
            $localNameLength = [BitConverter]::ToUInt16($bytes, $localOffset + 26)
            $localExtraLength = [BitConverter]::ToUInt16($bytes, $localOffset + 28)
            $dataOffset = [int]$localOffset + 30 + $localNameLength + $localExtraLength
            $corruptAt = $dataOffset + [int]($compressedLength / 2)
            $bytes[$corruptAt] = $bytes[$corruptAt] -bxor 0xFF
            [IO.File]::WriteAllBytes($ZipPath, $bytes)
            return
        }
        $cursor += 46 + $nameLength + $extraLength + $commentLength
    }
    throw \"Synthetic ZIP member missing: $Name\"
}

function Expand-PackageArchiveFixture {
    param([string]$ZipPath, [string]$Destination)
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $Destination)
    return $Destination
}

    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:packageInitialModules = @(Get-Module -All)
    $script:packageOwnedModulePaths = @(
        [IO.Path]::GetFullPath((Join-Path $script:repoRoot 'scripts/TPMReleasePackage.Core.psm1')),
        [IO.Path]::GetFullPath((Join-Path $script:repoRoot 'scripts/TPMCertification.Contracts.psm1')),
        [IO.Path]::GetFullPath((Join-Path $script:repoRoot 'scripts/TPMCertification.Authority.psm1'))
    )
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Import-Module (Join-Path $script:repoRoot 'scripts/TPMReleasePackage.Core.psm1') -Force
    Import-Module (Join-Path $script:repoRoot 'scripts/TPMCertification.Contracts.psm1') -Force
    $script:fixtureSource = Join-Path $TestDrive 'source fixture [package]'
    New-Item -ItemType Directory -Path $script:fixtureSource -Force | Out-Null
    New-PackageSourceFixture -Destination $script:fixtureSource -RepositoryRoot $script:repoRoot
    $script:validZip = Join-Path $TestDrive 'valid package [fixture].zip'
    & (Join-Path $script:repoRoot 'scripts/New-TPMReleasePackage.ps1') -OutputPath $script:validZip -SourceRoot $script:fixtureSource | Out-Null
}

Describe 'Strict user release package contents' {
    It 'accepts the complete source-mapped allowlist and byte-identical files' {
        $result = Test-TPMReleasePackageArchiveV1 -ZipPath $script:validZip -SourceRoot $script:fixtureSource
        $result.Valid | Should -BeTrue
        $result.FileCount | Should -Be 369
        $result.CrosshairPngCount | Should -Be 321
        $result.PathLeakCount | Should -Be 0
        { & (Join-Path $script:fixtureSource 'Tests/Test-ReleasePackage.ps1') -ZipPath $script:validZip } | Should -Not -Throw
    }

    It 'builds from a fresh stock Windows PowerShell process without ambient compression assemblies' {
        $builder = Join-Path $script:repoRoot 'scripts/New-TPMReleasePackage.ps1'
        $output = Join-Path $TestDrive 'stock powershell package.zip'
        $powershell = Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $powershell
        $startInfo.Arguments = '-NoProfile -File "{0}" -OutputPath "{1}" -SourceRoot "{2}"' -f $builder, $output, $script:fixtureSource
        $startInfo.WorkingDirectory = $script:repoRoot
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        $startInfo.EnvironmentVariables['PSModulePath'] = @(
            (Join-Path $env:ProgramFiles 'WindowsPowerShell/Modules')
            (Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/Modules')
        ) -join ';'
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        $null = $process.Start()
        $processHandle = $process.Handle
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $exitCode = [int]$process.ExitCode
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        $process.Dispose()

        $processHandle | Should -Not -Be ([IntPtr]::Zero)
        $exitCode | Should -Be 0
        $stderr | Should -Be ''
        Test-Path -LiteralPath $output -PathType Leaf | Should -BeTrue
    }
    It 'refuses overwrite and removes failed builder candidates' {
        $originalHash = (Get-FileHash -LiteralPath $script:validZip -Algorithm SHA256).Hash
        { & (Join-Path $script:repoRoot 'scripts/New-TPMReleasePackage.ps1') -OutputPath $script:validZip -SourceRoot $script:fixtureSource } | Should -Throw '*PACKAGE_OUTPUT_EXISTS*'
        (Get-FileHash -LiteralPath $script:validZip -Algorithm SHA256).Hash | Should -Be $originalHash

        $badRoot = Join-Path $TestDrive 'builder missing source evidence'
        New-Item -ItemType Directory -Path $badRoot -Force | Out-Null
        New-PackageSourceFixture -Destination $badRoot -RepositoryRoot $script:repoRoot
        Remove-Item -LiteralPath (Join-Path $badRoot 'contracts/pcsx2x6/evidence.md') -Force
        $failedOutput = Join-Path $TestDrive 'failed candidate.zip'
        { & (Join-Path $script:repoRoot 'scripts/New-TPMReleasePackage.ps1') -OutputPath $failedOutput -SourceRoot $badRoot } | Should -Throw '*SOURCE_EVIDENCE_MISSING*'
        Test-Path -LiteralPath $failedOutput | Should -BeFalse
        @(Get-ChildItem -LiteralPath $TestDrive -Filter '.tpm-package-*.tmp' -File -Recurse -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'keeps the menu diagnostic out of the user file map' {
        @(Get-TPMReleasePackageFileMapV1 | Where-Object ZipPath -eq 'scripts/Debug-TPM-MenuLayout.ps1').Count | Should -Be 0
        Test-Path -LiteralPath (Join-Path $script:repoRoot 'scripts/Debug-TPM-MenuLayout.ps1') -PathType Leaf | Should -BeTrue
    }

    It 'rejects unknown root and nested entries' {
        foreach ($case in @(@{ Name = 'developer-notes.md'; Replace = 'tools/' },@{ Name = 'scripts/private/'; Replace = 'scripts/resources/' },@{ Name = 'scripts/private/extra.ps1'; Replace = 'scripts/resources/' })) {
            $zip = Join-Path $TestDrive (([guid]::NewGuid().ToString('N')) + '.zip')
            Copy-PackageArchiveFixture -Source $script:validZip -Destination $zip
            Remove-PackageArchiveEntry -ZipPath $zip -Name $case.Replace
            Add-PackageArchiveEntry -ZipPath $zip -Name $case.Name -Text 'unknown'
            { Test-TPMReleasePackageArchiveV1 -ZipPath $zip -SourceRoot $script:fixtureSource } | Should -Throw '*PACKAGE_ENTRY_UNKNOWN*'
        }
    }

    It 'rejects missing entries, collisions, unsafe paths, oversize streams and malformed compression' {
        $missing = Join-Path $TestDrive 'missing-file.zip'
        Copy-PackageArchiveFixture -Source $script:validZip -Destination $missing
        Remove-PackageArchiveEntry -ZipPath $missing -Name 'LICENSE'
        { Test-TPMReleasePackageArchiveV1 -ZipPath $missing -SourceRoot $script:fixtureSource } | Should -Throw '*PACKAGE_ENTRY_MISSING*'

        $collision = Join-Path $TestDrive 'case-collision.zip'
        Copy-PackageArchiveFixture -Source $script:validZip -Destination $collision
        Remove-PackageArchiveEntry -ZipPath $collision -Name 'tools/'
        Add-PackageArchiveEntry -ZipPath $collision -Name 'license' -Text 'collision'
        { Test-TPMReleasePackageArchiveV1 -ZipPath $collision -SourceRoot $script:fixtureSource } | Should -Throw '*PACKAGE_PATH_DUPLICATE_OR_CASE_COLLISION*'

        foreach ($entryName in @('../escape.txt','tools\alternate.ps1')) {
            $zip = Join-Path $TestDrive (([guid]::NewGuid().ToString('N')) + '.zip')
            Copy-PackageArchiveFixture -Source $script:validZip -Destination $zip
            Remove-PackageArchiveEntry -ZipPath $zip -Name 'tools/'
            Add-PackageArchiveEntry -ZipPath $zip -Name $entryName -Text 'invalid'
            { Test-TPMReleasePackageArchiveV1 -ZipPath $zip -SourceRoot $script:fixtureSource } | Should -Throw '*PACKAGE_PATH_NONCANONICAL*'
        }

        $oversized = Join-Path $TestDrive 'oversized-file.zip'
        Copy-PackageArchiveFixture -Source $script:validZip -Destination $oversized
        Add-PackageArchiveEntry -ZipPath $oversized -Name 'LICENSE' -Text ('x' * 65536) -Replace
        { Test-TPMReleasePackageArchiveV1 -ZipPath $oversized -SourceRoot $script:fixtureSource } | Should -Throw '*PACKAGE_SOURCE_SIZE_MISMATCH*'

        $malformed = Join-Path $TestDrive 'malformed-compression.zip'
        Copy-PackageArchiveFixture -Source $script:validZip -Destination $malformed
        Corrupt-PackageArchiveCompressedMember -ZipPath $malformed -Name 'scripts/TPMCertification.Contracts.psm1'
        { Test-TPMReleasePackageArchiveV1 -ZipPath $malformed -SourceRoot $script:fixtureSource } | Should -Throw
        $reopened = [System.IO.Compression.ZipFile]::OpenRead($malformed)
        $reopened.Dispose()
    }

    It 'rejects each generic private path or address independently' {
        # Mutation: remove any one detector category; its isolated leak must no longer be rejected.
        foreach ($leak in @('C:\Users\FixturePerson\private', 'C:\Users\Example-Private\secret', '\\fixture-host\private\file', '10.23.45.67', '172.16.23.45', '192.168.23.45')) {
            $leakRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-PackageSourceFixture -Destination $leakRoot -RepositoryRoot $script:repoRoot
            $readme = Join-Path $leakRoot 'TeknoParrot-Manager-README.txt'
            [IO.File]::AppendAllText($readme, "`r`n$leak`r`n", (New-Object System.Text.UTF8Encoding($false)))
            $leakZip = Join-Path $TestDrive (([guid]::NewGuid().ToString('N')) + '.zip')
            { & (Join-Path $script:repoRoot 'scripts/New-TPMReleasePackage.ps1') -OutputPath $leakZip -SourceRoot $leakRoot } | Should -Throw '*PACKAGE_PATH_LEAK*'
            Test-Path -LiteralPath $leakZip | Should -BeFalse
        }
    }

    It 'scans packaged SVG files for personal paths' {
        # Mutation: leave svg out of the scanned extensions; an editor path left inside a preview image would ship.
        $leakRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-PackageSourceFixture -Destination $leakRoot -RepositoryRoot $script:repoRoot
        $svg = Join-Path $leakRoot 'PreviewAssets/ReShadePreviews/TPM-preview-clean.svg'
        $text = [IO.File]::ReadAllText($svg)
        $leaked = $text.Replace('<svg ', '<svg data-docname="C:\Users\Zorblax-Quentin\Desktop\preview.svg" ')
        $leaked | Should -Not -BeExactly $text
        [IO.File]::WriteAllText($svg, $leaked, (New-Object System.Text.UTF8Encoding($false)))
        $leakZip = Join-Path $TestDrive (([guid]::NewGuid().ToString('N')) + '.zip')
        $failure = $null
        try { & (Join-Path $script:repoRoot 'scripts/New-TPMReleasePackage.ps1') -OutputPath $leakZip -SourceRoot $leakRoot } catch { $failure = $_ }
        $failure | Should -Not -BeNullOrEmpty
        $failure.Exception.Message | Should -Match 'PACKAGE_PATH_LEAK:.*TPM-preview-clean\.svg \[user-profile-path\]'
        $failure.Exception.Message | Should -Not -Match 'Zorblax'
        Test-Path -LiteralPath $leakZip | Should -BeFalse
    }

    It 'preserves absolute-path leak rejection in packaged Markdown' {
        # Mutation: bypass Markdown scanning; both builder and archive rejection below must fail.
        $root = Join-Path $TestDrive 'Markdown source fixture [path leak]'
        New-PackageSourceFixture -Destination $root -RepositoryRoot $script:repoRoot
        $path = Join-Path $root 'docs/TROUBLESHOOTING.md'
        [IO.File]::AppendAllText($path, "`r`n\\fixture-host\private\file`r`n", (New-Object System.Text.UTF8Encoding($false)))
        $zip = Join-Path $TestDrive 'Markdown path leak package.zip'
        { & (Join-Path $script:repoRoot 'scripts/New-TPMReleasePackage.ps1') -OutputPath $zip -SourceRoot $root } |
            Should -Throw '*PACKAGE_PATH_LEAK*'
        Test-Path -LiteralPath $zip | Should -BeFalse

        Copy-PackageArchiveFixture -Source $script:validZip -Destination $zip
        Set-PackageArchiveFile -ZipPath $zip -Name 'docs/TROUBLESHOOTING.md' -SourcePath $path
        { Test-TPMReleasePackageArchiveV1 -ZipPath $zip -SourceRoot $root } |
            Should -Throw '*PACKAGE_PATH_LEAK*'
    }

    It 'rejects configured private names without disclosing the name in the error' {
        # Mutation: omit externally supplied names, or echo the matching regex into the error.
        $prior = $env:TPM_PACKAGE_PRIVATE_TOKENS
        try {
            $env:TPM_PACKAGE_PRIVATE_TOKENS = 'FIXTURE-PC-91;Other-Fixture-92'
            $root = Join-Path $TestDrive 'configured private name'
            New-PackageSourceFixture -Destination $root -RepositoryRoot $script:repoRoot
            $path = Join-Path $root 'docs/TROUBLESHOOTING.md'
            [IO.File]::AppendAllText($path, "`r`nfixture-pc-91`r`n", (New-Object System.Text.UTF8Encoding($false)))
            $zip = Join-Path $TestDrive 'private-name.zip'
            $failure = $null
            try { & (Join-Path $script:repoRoot 'scripts/New-TPMReleasePackage.ps1') -OutputPath $zip -SourceRoot $root } catch { $failure = $_ }
            $failure | Should -Not -BeNullOrEmpty
            $failure.Exception.Message | Should -Match 'PACKAGE_PATH_LEAK:.*private-token'
            $failure.Exception.Message | Should -Not -Match 'FIXTURE-PC-91|Other-Fixture-92'
            Test-Path -LiteralPath $zip | Should -BeFalse
        } finally {
            $env:TPM_PACKAGE_PRIVATE_TOKENS = $prior
        }
    }

    It 'accepts neutral examples, non-private addresses and longer names containing a private token' {
        # Mutation: broaden a private-address range or drop name boundaries; this valid build must be refused.
        $prior = $env:TPM_PACKAGE_PRIVATE_TOKENS
        try {
            $env:TPM_PACKAGE_PRIVATE_TOKENS = 'FIXTURE-PC-91'
            $root = Join-Path $TestDrive 'neutral privacy examples'
            New-PackageSourceFixture -Destination $root -RepositoryRoot $script:repoRoot
            $path = Join-Path $root 'docs/TROUBLESHOOTING.md'
            $examples = 'C:\Users\Example\Games \\server\share 172.15.1.2 172.32.1.2 192.169.1.2 10.0.26100.9711 FIXTURE-PC-910'
            [IO.File]::AppendAllText($path, "`r`n$examples`r`n", (New-Object System.Text.UTF8Encoding($false)))
            $zip = Join-Path $TestDrive 'neutral-examples.zip'
            $result = & (Join-Path $script:repoRoot 'scripts/New-TPMReleasePackage.ps1') -OutputPath $zip -SourceRoot $root
            $result.Valid | Should -BeTrue
            $result.PathLeakCount | Should -Be 0
        } finally {
            $env:TPM_PACKAGE_PRIVATE_TOKENS = $prior
        }
    }

    It 'rejects forged projections, missing source docs and missing source headings' {
        $forgedRoot = Join-Path $TestDrive 'forged source [index]'
        New-Item -ItemType Directory -Path $forgedRoot -Force | Out-Null
        New-PackageSourceFixture -Destination $forgedRoot -RepositoryRoot $script:repoRoot
        $indexPath = Join-Path $forgedRoot 'contracts/pcsx2x6/runtime-evidence-index.json'
        $indexText = [IO.File]::ReadAllText($indexPath).Replace('ev-portable-root','ev-altered-root')
        [IO.File]::WriteAllText($indexPath, $indexText, (New-Object System.Text.UTF8Encoding($false)))
        { Test-TPMReleasePackageArchiveV1 -ZipPath $script:validZip -SourceRoot $forgedRoot } | Should -Throw '*PACKAGE_SOURCE_INDEX_STALE*'

        $missingDocsRoot = Join-Path $TestDrive 'missing source docs [index present]'
        New-Item -ItemType Directory -Path $missingDocsRoot -Force | Out-Null
        New-PackageSourceFixture -Destination $missingDocsRoot -RepositoryRoot $script:repoRoot
        Remove-Item -LiteralPath (Join-Path $missingDocsRoot 'contracts/pcsx2x6/evidence.md') -Force
        { Test-TPMReleasePackageArchiveV1 -ZipPath $script:validZip -SourceRoot $missingDocsRoot } | Should -Throw '*SOURCE_EVIDENCE_MISSING*'

        $missingHeadingRoot = Join-Path $TestDrive 'missing source heading [index present]'
        New-Item -ItemType Directory -Path $missingHeadingRoot -Force | Out-Null
        New-PackageSourceFixture -Destination $missingHeadingRoot -RepositoryRoot $script:repoRoot
        $evidencePath = Join-Path $missingHeadingRoot 'contracts/pcsx2x6/evidence.md'
        $evidenceText = [IO.File]::ReadAllText($evidencePath).Replace('ev-portable-root','ev-renamed-portable-root')
        [IO.File]::WriteAllText($evidencePath, $evidenceText, (New-Object System.Text.UTF8Encoding($false)))
        { Test-TPMReleasePackageArchiveV1 -ZipPath $script:validZip -SourceRoot $missingHeadingRoot } | Should -Throw '*SOURCE_EVIDENCE_HEADING_MISSING*'
    }
}

Describe 'RC8 documentation and screenshot package contract' {
    It 'maps exactly five linked guides and twenty-three screenshot paths' {
        $documentationMap = @(Get-TPMReleasePackageDocumentationFileMapV1)
        $documentationMap.Count | Should -Be 28
        @($documentationMap | Where-Object AssetType -ceq 'Guide').Count | Should -Be 5
        @($documentationMap | Where-Object AssetType -ceq 'Screenshot').Count | Should -Be 23
        (@($documentationMap | Where-Object AssetType -ceq 'Guide' | ForEach-Object ZipPath | Sort-Object) -join '|') |
            Should -Be (($script:expectedGuidePaths | Sort-Object) -join '|')
        (@($documentationMap | Where-Object AssetType -ceq 'Screenshot' | ForEach-Object ZipPath | Sort-Object) -join '|') |
            Should -Be (($script:expectedScreenshotPaths | Sort-Object) -join '|')
        foreach ($assetType in @('Guide','Screenshot')) {
            $paths = if ($assetType -ceq 'Guide') { $script:expectedGuidePaths } else { $script:expectedScreenshotPaths }
            foreach ($path in $paths) {
                @($documentationMap | Where-Object ZipPath -ceq $path).Count | Should -Be 1
                @($documentationMap | Where-Object SourcePath -ceq $path).Count | Should -Be 1
                @($documentationMap | Where-Object { $_.ZipPath -ceq $path -and $_.SourcePath -ceq $path -and $_.AssetType -ceq $assetType }).Count |
                    Should -Be 1
            }
        }

        $fileMap = @(Get-TPMReleasePackageFileMapV1 -SourceRoot $script:repoRoot)
        $fileMap.Count | Should -Be 369
        foreach ($path in @($script:expectedGuidePaths) + @($script:expectedScreenshotPaths)) {
            @($fileMap | Where-Object ZipPath -ceq $path).Count | Should -Be 1
            @($fileMap | Where-Object SourcePath -ceq $path).Count | Should -Be 1
            $assetType = if ($script:expectedGuidePaths -ccontains $path) { 'Guide' } else { 'Screenshot' }
            @($fileMap | Where-Object { $_.ZipPath -ceq $path -and $_.SourcePath -ceq $path -and $_.AssetType -ceq $assetType }).Count | Should -Be 1
        }
        @($fileMap | Where-Object { $_.ZipPath -like 'images/*' }).Count | Should -Be 1
        @($fileMap | Where-Object { $_.ZipPath -like 'docs/images/*' }).Count | Should -Be 22
        @($fileMap | Where-Object ZipPath -in @('images/tpm-main-menu.png','images/banner.png','README.md','QUICKSTART.md')).Count | Should -Be 0
        $expectedCrosshairNames = @(0..320 | ForEach-Object { '{0:D3}.png' -f $_ })
        $mappedCrosshairNames = @($fileMap | Where-Object { $_.ZipPath -like 'Crosshairs/*' } | ForEach-Object { [IO.Path]::GetFileName($_.ZipPath) } | Sort-Object)
        $mappedCrosshairNames.Count | Should -Be 321
        ($mappedCrosshairNames -join '|') | Should -Be (($expectedCrosshairNames | Sort-Object) -join '|')
        $sourceCrosshairNames = @(Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'Crosshairs') -File | ForEach-Object Name | Sort-Object)
        $sourceCrosshairNames.Count | Should -Be 321
        ($sourceCrosshairNames -join '|') | Should -Be (($expectedCrosshairNames | Sort-Object) -join '|')

        $readme = [IO.File]::ReadAllText((Join-Path $script:repoRoot 'TeknoParrot-Manager-README.txt'))
        $quickStart = [IO.File]::ReadAllText((Join-Path $script:repoRoot 'TeknoParrot-Manager-QuickStart.txt'))
        $readme | Should -Match 'For a one-page version, see TeknoParrot-Manager-QuickStart\.txt'
        $quickStart | Should -Match 'Full details: TeknoParrot-Manager-README\.txt'
        $quickStart | Should -Match 'images\\release\\RC8-MainMenu\.png'

        $guideZip = Join-Path $TestDrive 'guide-only documentation fixture.zip'
        $archive = [System.IO.Compression.ZipFile]::Open($guideZip, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($guide in ($documentationMap | Where-Object AssetType -eq 'Guide')) {
                $sourcePath = Join-Path $script:repoRoot ($guide.SourcePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
                [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $sourcePath, $guide.ZipPath, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
            }
        } finally { $archive.Dispose() }
        $archive = [System.IO.Compression.ZipFile]::OpenRead($guideZip)
        try {
            foreach ($guide in ($documentationMap | Where-Object AssetType -eq 'Guide')) {
                $entry = $archive.GetEntry($guide.ZipPath)
                $entry | Should -Not -BeNullOrEmpty
                $sourcePath = Join-Path $script:repoRoot ($guide.SourcePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
                $entry.Length | Should -Be (Get-Item -LiteralPath $sourcePath).Length
                $entryStream = $entry.Open()
                $sha = [System.Security.Cryptography.SHA256]::Create()
                try {
                    $entryHash = [BitConverter]::ToString($sha.ComputeHash($entryStream)).Replace('-', '')
                    $entryHash | Should -Be (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
                } finally { $sha.Dispose(); $entryStream.Dispose() }
            }
        } finally { $archive.Dispose() }
    }

    It 'ships resolved Markdown and every valid synthetic PNG byte-identically to its fixture source' {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($script:validZip)
        try {
            foreach ($path in @($script:expectedGuidePaths) + @($script:expectedScreenshotPaths)) {
                $source = Join-Path $script:fixtureSource ($path.Replace('/', [IO.Path]::DirectorySeparatorChar))
                $entry = $archive.GetEntry($path)
                $entry | Should -Not -BeNullOrEmpty
                $entry.Length | Should -Be (Get-Item -LiteralPath $source).Length
                $stream = $entry.Open()
                $sha = [System.Security.Cryptography.SHA256]::Create()
                try {
                    [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') |
                        Should -Be (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
                } finally { $sha.Dispose(); $stream.Dispose() }
                if ($script:expectedScreenshotPaths -ccontains $path) {
                    $bytes = [IO.File]::ReadAllBytes($source)
                    $bytes.Length | Should -BeGreaterOrEqual 128
                    [BitConverter]::ToString($bytes, 0, 8) | Should -Be '89-50-4E-47-0D-0A-1A-0A'
                    [Text.Encoding]::ASCII.GetString($bytes, 12, 4) | Should -Be 'IHDR'
                    [BitConverter]::ToString($bytes, 16, 8) | Should -Be '00-00-02-80-00-00-01-68'
                    Test-Path -LiteralPath (Join-Path (Split-Path -Parent $source) 'SYNTHETIC-TEST-ONLY.txt') -PathType Leaf | Should -BeTrue
                } elseif ([IO.Path]::GetExtension($path) -ceq '.md') {
                    [IO.File]::ReadAllText($source).Contains('[SCREENSHOT:') | Should -BeFalse
                }
            }
        } finally { $archive.Dispose() }
    }

    It 'rejects unresolved placeholders in either Markdown guide during build and archive validation' {
        foreach ($path in @('docs/START-HERE.md','docs/TROUBLESHOOTING.md')) {
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-PackageSourceFixture -Destination $root -RepositoryRoot $script:repoRoot
            $source = Join-Path $root ($path.Replace('/', [IO.Path]::DirectorySeparatorChar))
            [IO.File]::AppendAllText($source, "`r`n[SCREENSHOT: synthetic unresolved capture]`r`n", (New-Object System.Text.UTF8Encoding($false)))
            $output = Join-Path $TestDrive (([guid]::NewGuid().ToString('N')) + '.zip')
            { & (Join-Path $script:repoRoot 'scripts/New-TPMReleasePackage.ps1') -OutputPath $output -SourceRoot $root } |
                Should -Throw '*PACKAGE_DOCUMENTATION_PLACEHOLDER*'
            Test-Path -LiteralPath $output | Should -BeFalse
            @(Get-ChildItem -LiteralPath $TestDrive -Filter '.tpm-package-*.tmp' -File -Recurse -ErrorAction SilentlyContinue).Count | Should -Be 0

            $zip = Join-Path $TestDrive (([guid]::NewGuid().ToString('N')) + '.zip')
            Copy-PackageArchiveFixture -Source $script:validZip -Destination $zip
            Set-PackageArchiveFile -ZipPath $zip -Name $path -SourcePath $source
            # Archive-only tampering retains the bounded source identity checks.
            { Test-TPMReleasePackageArchiveV1 -ZipPath $zip -SourceRoot $script:fixtureSource } |
                Should -Throw '*PACKAGE_SOURCE_SIZE_MISMATCH*'
            # Equal source/archive bytes must not make an unresolved placeholder shippable.
            { Test-TPMReleasePackageArchiveV1 -ZipPath $zip -SourceRoot $root } |
                Should -Throw '*PACKAGE_DOCUMENTATION_PLACEHOLDER*'
        }
    }

    It 'accepts real relative image links and case-distinct non-placeholder text in both Markdown guides' {
        $root = Join-Path $TestDrive 'resolved Markdown with literal near matches'
        New-PackageSourceFixture -Destination $root -RepositoryRoot $script:repoRoot
        foreach ($path in @('docs/START-HERE.md','docs/TROUBLESHOOTING.md')) {
            $source = Join-Path $root ($path.Replace('/', [IO.Path]::DirectorySeparatorChar))
            [IO.File]::AppendAllText($source, "`r`n![Synthetic test-only capture](images/01-installer-window.png)`r`n[screenshot: case-distinct text] [SCREENSHOT without colon]`r`n", (New-Object System.Text.UTF8Encoding($false)))
        }
        $zip = Join-Path $TestDrive 'resolved Markdown accepted.zip'
        $result = & (Join-Path $script:repoRoot 'scripts/New-TPMReleasePackage.ps1') -OutputPath $zip -SourceRoot $root
        $result.Valid | Should -BeTrue
        (Test-TPMReleasePackageArchiveV1 -ZipPath $zip -SourceRoot $root).Valid | Should -BeTrue
    }

    It 'retains content-hash checks for clean packaged Markdown' {
        foreach ($path in @('docs/START-HERE.md','docs/TROUBLESHOOTING.md')) {
            $source = Join-Path $script:fixtureSource ($path.Replace('/', [IO.Path]::DirectorySeparatorChar))
            $bytes = [IO.File]::ReadAllBytes($source)
            $bytes[0] = $bytes[0] -bxor 1
            $changed = Join-Path $TestDrive (([guid]::NewGuid().ToString('N')) + '.md')
            [IO.File]::WriteAllBytes($changed, $bytes)
            $zip = Join-Path $TestDrive (([guid]::NewGuid().ToString('N')) + '.zip')
            Copy-PackageArchiveFixture -Source $script:validZip -Destination $zip
            Set-PackageArchiveFile -ZipPath $zip -Name $path -SourcePath $changed
            { Test-TPMReleasePackageArchiveV1 -ZipPath $zip -SourceRoot $script:fixtureSource } |
                Should -Throw '*PACKAGE_SOURCE_CONTENT_MISMATCH*'
        }
    }

    It 'rejects wrong-signature, truncated, missing-IHDR and 64x64 old and new screenshots without bypassing source comparisons' {
        foreach ($path in @($script:requiredRc8ScreenshotRelativePath,'docs/images/01-installer-window.png')) {
            foreach ($kind in @('invalid-signature','undersized','missing-IHDR','64x64')) {
                $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
                New-PackageSourceFixture -Destination $root -RepositoryRoot $script:repoRoot
                $source = Join-Path $root ($path.Replace('/', [IO.Path]::DirectorySeparatorChar))
                if ($kind -ceq '64x64') { New-SyntheticTestOnlyPackageScreenshot -Path $source -Width 64 -Height 64 }
                $bytes = [IO.File]::ReadAllBytes($source)
                if ($kind -ceq 'invalid-signature') {
                    $bytes[0] = $bytes[0] -bxor 1
                } elseif ($kind -ceq 'missing-IHDR') {
                    $bytes[12] = [byte][char]'X'
                } elseif ($kind -ceq 'undersized') {
                    $bytes = [byte[]]@(137,80,78,71,13,10,26,10)
                }
                [IO.File]::WriteAllBytes($source, $bytes)
                $output = Join-Path $TestDrive (([guid]::NewGuid().ToString('N')) + '.zip')
                { & (Join-Path $script:repoRoot 'scripts/New-TPMReleasePackage.ps1') -OutputPath $output -SourceRoot $root } |
                    Should -Throw $(switch ($kind) {
                        'invalid-signature' { '*PACKAGE_SCREENSHOT_INVALID_PNG*no PNG signature*' }
                        'undersized' { '*PACKAGE_SCREENSHOT_INVALID_PNG*at least 128 bytes*' }
                        'missing-IHDR' { '*PACKAGE_SCREENSHOT_INVALID_PNG*no IHDR chunk*' }
                        '64x64' { '*PACKAGE_SCREENSHOT_INVALID_PNG*64x64*640x360 minimum*' }
                    })
                Test-Path -LiteralPath $output | Should -BeFalse
                @(Get-ChildItem -LiteralPath $TestDrive -Filter '.tpm-package-*.tmp' -File -Recurse -ErrorAction SilentlyContinue).Count | Should -Be 0

                $zip = Join-Path $TestDrive (([guid]::NewGuid().ToString('N')) + '.zip')
                Copy-PackageArchiveFixture -Source $script:validZip -Destination $zip
                Set-PackageArchiveFile -ZipPath $zip -Name $path -SourcePath $source
                $expectedError = if ($kind -in @('undersized','64x64')) { '*PACKAGE_SOURCE_SIZE_MISMATCH*' } else { '*PACKAGE_SOURCE_CONTENT_MISMATCH*' }
                { Test-TPMReleasePackageArchiveV1 -ZipPath $zip -SourceRoot $script:fixtureSource } | Should -Throw $expectedError
                { Test-TPMReleasePackageArchiveV1 -ZipPath $zip -SourceRoot $root } |
                    Should -Throw $(switch ($kind) {
                        'invalid-signature' { '*PACKAGE_SCREENSHOT_INVALID_PNG*no PNG signature*' }
                        'undersized' { '*PACKAGE_SCREENSHOT_INVALID_PNG*at least 128 bytes*' }
                        'missing-IHDR' { '*PACKAGE_SCREENSHOT_INVALID_PNG*no IHDR chunk*' }
                        '64x64' { '*PACKAGE_SCREENSHOT_INVALID_PNG*64x64*640x360 minimum*' }
                    })
            }
        }
    }

    It 'accepts exactly 640x360 screenshots in builder preflight and archive validation' {
        foreach ($path in $script:expectedScreenshotPaths) {
            $source = Join-Path $script:fixtureSource ($path.Replace('/', [IO.Path]::DirectorySeparatorChar))
            $bytes = [IO.File]::ReadAllBytes($source)
            [BitConverter]::ToString($bytes, 16, 8) | Should -Be '00-00-02-80-00-00-01-68'
        }
        { Assert-TPMReleasePackageRequiredScreenshotSourceV1 -SourceRoot $script:fixtureSource } | Should -Not -Throw
        $output = Join-Path $TestDrive 'exact-floor screenshots accepted.zip'
        $result = & (Join-Path $script:repoRoot 'scripts/New-TPMReleasePackage.ps1') -OutputPath $output -SourceRoot $script:fixtureSource
        $result.Valid | Should -BeTrue
        (Test-TPMReleasePackageArchiveV1 -ZipPath $output -SourceRoot $script:fixtureSource).Valid | Should -BeTrue
        @(Get-ChildItem -LiteralPath $TestDrive -Filter '.tpm-package-*.tmp' -File -Recurse -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'rejects missing source screenshots with the existing archive-validator error for old and new paths' {
        foreach ($path in @($script:requiredRc8ScreenshotRelativePath,'docs/images/11-tpm-action-required.png')) {
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-PackageSourceFixture -Destination $root -RepositoryRoot $script:repoRoot
            Remove-Item -LiteralPath (Join-Path $root ($path.Replace('/', [IO.Path]::DirectorySeparatorChar))) -Force
            { Test-TPMReleasePackageArchiveV1 -ZipPath $script:validZip -SourceRoot $root } |
                Should -Throw '*PACKAGE_SOURCE_SCREENSHOT_MISSING*'
        }
    }

    It 'prioritizes a missing new capture over unresolved Markdown and creates no candidate or final output' {
        $root = Join-Path $TestDrive 'missing newcomer screenshot with unresolved Markdown'
        New-PackageSourceFixture -Destination $root -RepositoryRoot $script:repoRoot
        Remove-Item -LiteralPath (Join-Path $root 'docs/images/11-tpm-action-required.png') -Force
        [IO.File]::AppendAllText((Join-Path $root 'docs/START-HERE.md'), "`r`n[SCREENSHOT: still unresolved]`r`n", (New-Object System.Text.UTF8Encoding($false)))
        $output = Join-Path $TestDrive 'missing newcomer screenshot must not ship.zip'
        { & (Join-Path $script:repoRoot 'scripts/New-TPMReleasePackage.ps1') -OutputPath $output -SourceRoot $root } |
            Should -Throw '*PACKAGE_REQUIRED_SCREENSHOT_MISSING*'
        Test-Path -LiteralPath $output | Should -BeFalse
        @(Get-ChildItem -LiteralPath $TestDrive -Filter '.tpm-package-*.tmp' -File -Recurse -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'blocks the builder before any candidate file when the required capture is absent' {
        $missingRoot = Join-Path $TestDrive 'source fixture without current screenshot'
        New-Item -ItemType Directory -Path $missingRoot -Force | Out-Null
        New-PackageSourceFixture -Destination $missingRoot -RepositoryRoot $script:repoRoot
        $missingImage = Join-Path $missingRoot ($script:requiredRc8ScreenshotRelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
        if (Test-Path -LiteralPath $missingImage -PathType Leaf) { Remove-Item -LiteralPath $missingImage -Force }

        $output = Join-Path $TestDrive 'must not create incomplete package.zip'
        { & (Join-Path $script:repoRoot 'scripts/New-TPMReleasePackage.ps1') -OutputPath $output -SourceRoot $missingRoot } |
            Should -Throw '*PACKAGE_REQUIRED_SCREENSHOT_MISSING*'
        Test-Path -LiteralPath $output | Should -BeFalse
        @(Get-ChildItem -LiteralPath $TestDrive -Filter '.tpm-package-*.tmp' -File -Recurse -ErrorAction SilentlyContinue).Count |
            Should -Be 0
    }

    It 'rejects unexpected root documentation and nested screenshot-directory files' {
        foreach ($unknownPath in @('developer-notes.md','images/release/extra-capture.txt','docs/private-notes.md','docs/images/extra-capture.png','docs/images/private/extra-capture.png','docs/images/private/')) {
            $candidateZip = Join-Path $TestDrive (([guid]::NewGuid().ToString('N')) + '.zip')
            Add-PackageArchiveEntry -ZipPath $candidateZip -Name $unknownPath -Text 'unlisted test entry'
            { Test-TPMReleasePackageArchiveV1 -ZipPath $candidateZip -SourceRoot $script:fixtureSource } |
                Should -Throw '*PACKAGE_ENTRY_UNKNOWN*'
        }
    }
}

Describe 'Packaged PCSx2x6 runtime projection' {
    It 'loads registry and read-only observations from a private extracted path with spaces and brackets' {
        $actualZip = Join-Path $TestDrive 'actual source package [private build].zip'
        $buildResult = & (Join-Path $script:repoRoot 'scripts/New-TPMReleasePackage.ps1') -OutputPath $actualZip -SourceRoot $script:fixtureSource
        $buildResult.Valid | Should -BeTrue
        $buildResult.FileCount | Should -Be 369
        $buildResult.CrosshairPngCount | Should -Be 321
        $stage = Join-Path $TestDrive 'private extracted package [runtime path]'
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        Expand-PackageArchiveFixture -ZipPath $actualZip -Destination $stage | Out-Null
        $modulePath = Join-Path $stage 'scripts/TPMCertification.Contracts.psm1'
            Import-Module $modulePath -Force -PassThru | Out-Null
        (Get-TPMContractsRootV1 -ValidationMode Runtime) | Should -Be (Join-Path $stage 'scripts/resources/contracts')
        $loaded = Get-TPMEmulatorContractV1 -ContractId 'pcsx2x6' -ValidationMode Runtime
        $loaded.Contract.EvidenceReferences.Count | Should -Be 9
        $integrity = Test-TPMContractRegistryIntegrityV1 -ValidationMode Runtime
        $integrity.Valid | Should -BeTrue
        $observations = Get-TPMEmulatorContractObservationsV1 -InstallRoot (Join-Path $TestDrive 'empty synthetic install root') -ValidationMode Runtime
        $observations.RegistryValid | Should -BeTrue
        (Test-Path -LiteralPath (Join-Path $stage 'contracts')) | Should -BeFalse
        (Test-Path -LiteralPath (Join-Path $stage 'scripts/resources/contracts/pcsx2x6/evidence.md')) | Should -BeFalse
        (Test-Path -LiteralPath (Join-Path $stage 'scripts/resources/contracts/_schema')) | Should -BeFalse
        $mainPath = Join-Path $stage 'TeknoParrot-Manager.ps1'
        $tokens = $null
        $parseErrors = $null
        $mainAst = [System.Management.Automation.Language.Parser]::ParseFile($mainPath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should -Be 0
        $wantedFunctions = @('Resolve-Pcsx2Directory','Get-ContractBackedMissingComponents')
        $functions = @($mainAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wantedFunctions -contains $node.Name
        }, $true))
        $functions.Count | Should -Be 2
        $helperPath = Join-Path $stage 'packaged-main-support-helpers.ps1'
        $helperText = ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
        [IO.File]::WriteAllText($helperPath, $helperText, (New-Object System.Text.UTF8Encoding($false)))
        . $helperPath
        $syntheticRoot = Join-Path $TestDrive 'synthetic TeknoParrot root'
        $pcsx2Directory = Join-Path $syntheticRoot 'pcsx2x6'
        New-Item -ItemType Directory -Path $pcsx2Directory -Force | Out-Null
        $mainAssessment = Get-ContractBackedMissingComponents -EmulatorType 'pcsx2x6' -TeknoParrotRoot $syntheticRoot
        $mainAssessment.State | Should -Be 'Missing'
        $mainAssessment.ContractId | Should -Be 'pcsx2x6'
        $mainAssessment.Components.Count | Should -BeGreaterThan 0
        $sourceContractDirectory = Join-Path $stage 'contracts/pcsx2x6'
        New-Item -ItemType Directory -Path $sourceContractDirectory -Force | Out-Null
        foreach ($name in @('contract.json','runtime-evidence-index.json','evidence.md','experiments.md')) {
            Copy-Item -LiteralPath (Join-Path $script:repoRoot "contracts/pcsx2x6/$name") -Destination (Join-Path $sourceContractDirectory $name) -Force
        }
        @(Get-TPMRegisteredEmulatorContractsV1 -ValidationMode Source -ContractsRoot (Join-Path $stage 'contracts')).Count | Should -Be 1
        Remove-Item -LiteralPath (Join-Path $stage 'scripts/resources/contracts') -Recurse -Force
        $noFallbackAssessment = Get-ContractBackedMissingComponents -EmulatorType 'pcsx2x6' -TeknoParrotRoot $syntheticRoot
        $noFallbackAssessment.State | Should -Be 'Unknown'
        $noFallbackAssessment.Components.Count | Should -Be 0
    }

    It 'rejects missing or duplicated rows, stale contract hash, and altered reference mappings' {
        foreach ($case in @('missing-index','stale-contract-hash','wrong-locator','missing-row','duplicate-row','wrong-heading')) {
            $stage = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $stage -Force | Out-Null
            Expand-PackageArchiveFixture -ZipPath $script:validZip -Destination $stage | Out-Null
            $indexPath = Join-Path $stage 'scripts/resources/contracts/pcsx2x6/runtime-evidence-index.json'
            $contractPath = Join-Path $stage 'scripts/resources/contracts/pcsx2x6/contract.json'
            if ($case -eq 'missing-index') {
                Remove-Item -LiteralPath $indexPath -Force
                { Get-TPMEmulatorContractV1 -ContractId 'pcsx2x6' -ValidationMode Runtime -ContractsRoot (Join-Path $stage 'scripts/resources/contracts') } | Should -Throw '*RUNTIME_EVIDENCE_INDEX_MISSING*'
                continue
            }
            $index = [IO.File]::ReadAllText($indexPath) | ConvertFrom-Json
            if ($case -eq 'stale-contract-hash') {
                $index.ContractSha256 = ('0' * 64)
            } elseif ($case -eq 'wrong-locator') {
                $index.EvidenceReferences[0].Locator = 'evidence.md#wrong-heading'
            } elseif ($case -eq 'missing-row') {
                $index.EvidenceReferences = @($index.EvidenceReferences | Select-Object -Skip 1)
            } elseif ($case -eq 'duplicate-row') {
                $index.EvidenceReferences = @($index.EvidenceReferences) + @($index.EvidenceReferences[0])
            } elseif ($case -eq 'wrong-heading') {
                $index.EvidenceReferences[0].Heading = 'wrong-heading'
            }
            [IO.File]::WriteAllText($indexPath, ($index | ConvertTo-Json -Depth 8 -Compress), (New-Object System.Text.UTF8Encoding($false)))
            $expectedError = if ($case -eq 'stale-contract-hash') { '*RUNTIME_EVIDENCE_CONTRACT_HASH_MISMATCH*' } else { '*RUNTIME_EVIDENCE_INDEX_INVALID*' }
            { Get-TPMEmulatorContractV1 -ContractId 'pcsx2x6' -ValidationMode Runtime -ContractsRoot (Join-Path $stage 'scripts/resources/contracts') } | Should -Throw $expectedError
        }
    }
}
AfterAll {
    $testDrivePrefix = [IO.Path]::GetFullPath($TestDrive)
    if (-not $testDrivePrefix.EndsWith([IO.Path]::DirectorySeparatorChar.ToString())) {
        $testDrivePrefix += [IO.Path]::DirectorySeparatorChar
    }
    $corePath = $script:packageOwnedModulePaths[0]
    foreach ($module in @(Get-Module -All)) {
        if (-not $module.Path -or -not [string]::Equals([IO.Path]::GetFullPath($module.Path),$corePath,[StringComparison]::OrdinalIgnoreCase)) { continue }
        $wasPreexisting = $false
        foreach ($prior in $script:packageInitialModules) {
            if ([object]::ReferenceEquals($module,$prior)) { $wasPreexisting = $true; break }
        }
        if ($wasPreexisting) { continue }
        $stillLoaded = $false
        foreach ($current in @(Get-Module -All)) {
            if ([object]::ReferenceEquals($module,$current)) { $stillLoaded = $true; break }
        }
        if ($stillLoaded) { Remove-Module -ModuleInfo $module -Force }
    }
    foreach ($module in @(Get-Module -All)) {
        if (-not $module.Path) { continue }
        $modulePath = [IO.Path]::GetFullPath($module.Path)
        $isOwned = $script:packageOwnedModulePaths -contains $modulePath -or $modulePath.StartsWith($testDrivePrefix,[StringComparison]::OrdinalIgnoreCase)
        if (-not $isOwned) { continue }
        $wasPreexisting = $false
        foreach ($prior in $script:packageInitialModules) {
            if ([object]::ReferenceEquals($module,$prior)) { $wasPreexisting = $true; break }
        }
        if ($wasPreexisting) { continue }
        $stillLoaded = $false
        foreach ($current in @(Get-Module -All)) {
            if ([object]::ReferenceEquals($module,$current)) { $stillLoaded = $true; break }
        }
        if ($stillLoaded) { Remove-Module -ModuleInfo $module -Force }
    }
    Import-Module $script:packageOwnedModulePaths[2] -Global -Force
    Import-Module $script:packageOwnedModulePaths[1] -Global -Force
}
