#Requires -Version 5.1

param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath,

    [string]$ExpectedDisplayVersion = 'v1.0 RC8'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$validatorModule = Join-Path $repoRoot 'scripts/TPMReleasePackage.Core.psm1'
Import-Module $validatorModule -Force -ErrorAction Stop
Test-TPMReleasePackageArchiveV1 -ZipPath $ZipPath -SourceRoot $repoRoot -ExpectedDisplayVersion $ExpectedDisplayVersion |
    Format-List
