#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$SourceRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$ExpectedDisplayVersion = 'v1.0 RC8'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceRootFull = [System.IO.Path]::GetFullPath($SourceRoot)
if (-not (Test-Path -LiteralPath $sourceRootFull -PathType Container)) { throw "PACKAGE_SOURCE_ROOT_MISSING: $sourceRootFull" }
$outputFull = [System.IO.Path]::GetFullPath($OutputPath)
if ([System.IO.Path]::GetExtension($outputFull) -cne '.zip') { throw 'PACKAGE_OUTPUT_EXTENSION_INVALID: output must use .zip' }
$outputParent = [System.IO.Path]::GetDirectoryName($outputFull)
if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) { throw "PACKAGE_OUTPUT_DIRECTORY_MISSING: $outputParent" }
$rootPrefix = $sourceRootFull.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
if ($outputFull.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'PACKAGE_OUTPUT_INSIDE_SOURCE: write the package outside the source tree' }
if (Test-Path -LiteralPath $outputFull) { throw "PACKAGE_OUTPUT_EXISTS: refusing to overwrite '$outputFull'" }

$modulePath = Join-Path $PSScriptRoot 'TPMReleasePackage.Core.psm1'
Import-Module $modulePath -Force -ErrorAction Stop
$fileMap = @(Get-TPMReleasePackageFileMapV1 -SourceRoot $sourceRootFull)
$directoryEntries = @(Get-TPMReleasePackageDirectoryEntriesV1 -FileMap $fileMap)
$temporaryPath = Join-Path $outputParent ('.tpm-package-{0}.tmp' -f [guid]::NewGuid().ToString('N'))
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

try {
    $archive = [System.IO.Compression.ZipFile]::Open($temporaryPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($directory in $directoryEntries) { $archive.CreateEntry($directory) | Out-Null }
        foreach ($item in $fileMap) {
            $sourcePath = Join-Path $sourceRootFull ($item.SourcePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "PACKAGE_SOURCE_FILE_MISSING: '$($item.SourcePath)'" }
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $sourcePath, $item.ZipPath, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    } finally { $archive.Dispose() }

    $validation = Test-TPMReleasePackageArchiveV1 -ZipPath $temporaryPath -SourceRoot $sourceRootFull -ExpectedDisplayVersion $ExpectedDisplayVersion
    [System.IO.File]::Move($temporaryPath, $outputFull)
    return [pscustomobject]@{
        ZipPath = $outputFull
        EntryCount = $validation.EntryCount
        FileCount = $validation.FileCount
        CrosshairPngCount = $validation.CrosshairPngCount
        PathLeakCount = $validation.PathLeakCount
        ExpectedVersion = $validation.ExpectedVersion
        Valid = $validation.Valid
    }
} finally {
    if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) { Remove-Item -LiteralPath $temporaryPath -Force }
}
