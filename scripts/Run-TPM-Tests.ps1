param(
    [string]$RepoPath,
    [string]$TeknoParrotRoot = "W:\Emulators\TeknoParrot",
    [string]$HarnessRoot,
    [switch]$RunUnattendedTPM
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoPath)) {
    $RepoPath = Split-Path -Parent $PSScriptRoot
}

$harness = Join-Path $PSScriptRoot "Invoke-TPM-RealInstanceSmoke.ps1"

if (!(Test-Path -LiteralPath $harness -PathType Leaf)) {
    throw "Test harness not found: $harness"
}

$params = @{
    RepoPath = $RepoPath
    TeknoParrotRoot = $TeknoParrotRoot
}

if (![string]::IsNullOrWhiteSpace($HarnessRoot)) {
    $params.HarnessRoot = $HarnessRoot
}

if ($RunUnattendedTPM) {
    $params.RunUnattendedTPM = $true
}

& $harness @params
