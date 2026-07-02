param(
    [string]$RepoPath = "C:\Jumpstile\teknoparrot-manager",
    [string]$TeknoParrotRoot = "W:\Emulators\TeknoParrot",
    [switch]$RunUnattendedTPM
)

$ErrorActionPreference = "Stop"

$harness = Join-Path $PSScriptRoot "Invoke-TPM-RealInstanceSmoke.ps1"

if (!(Test-Path -LiteralPath $harness -PathType Leaf)) {
    throw "Test harness not found: $harness"
}

if ($RunUnattendedTPM) {
    & $harness -RepoPath $RepoPath -TeknoParrotRoot $TeknoParrotRoot -RunUnattendedTPM
} else {
    & $harness -RepoPath $RepoPath -TeknoParrotRoot $TeknoParrotRoot
}
