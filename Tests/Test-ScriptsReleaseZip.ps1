#Requires -Version 5.1

param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptsPath,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedZipPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedScriptsPath = (Resolve-Path -LiteralPath $ScriptsPath).Path
$resolvedExpectedZip = (Resolve-Path -LiteralPath $ExpectedZipPath).Path

$zips = @(Get-ChildItem -LiteralPath $resolvedScriptsPath -Filter 'TeknoParrot Manager*.zip' -File)
if ($zips.Count -ne 1) {
    throw "Scripts release ZIP mirror must contain exactly one TeknoParrot Manager*.zip file; found $($zips.Count)."
}

$mirrorZip = $zips[0]
$expectedZip = Get-Item -LiteralPath $resolvedExpectedZip

$nameMatches = ($mirrorZip.Name -eq $expectedZip.Name)
if (-not $nameMatches) {
    throw "Scripts release ZIP mirror name mismatch. Expected '$($expectedZip.Name)', found '$($mirrorZip.Name)'."
}

$mirrorHash = (Get-FileHash -LiteralPath $mirrorZip.FullName -Algorithm SHA256).Hash
$expectedHash = (Get-FileHash -LiteralPath $expectedZip.FullName -Algorithm SHA256).Hash
$hashMatches = ($mirrorHash -eq $expectedHash)
if (-not $hashMatches) {
    throw "Scripts release ZIP mirror hash mismatch. Expected SHA256 $expectedHash, found $mirrorHash."
}

[pscustomobject]@{
    ScriptsPath         = $resolvedScriptsPath
    MirrorZipPath       = $mirrorZip.FullName
    ExpectedZipPath     = $expectedZip.FullName
    ZipCount            = $zips.Count
    NameMatchesExpected = $nameMatches
    HashMatchesExpected = $hashMatches
    Sha256              = $mirrorHash
    Valid               = $true
} | Format-List
