param(
    [string]$RepoPath,
    [string]$TeknoParrotRoot = "W:\Emulators\TeknoParrot",
    [string]$HarnessRoot,
    [switch]$RunUnattendedTPM,
    [switch]$NoPwshRelaunch
)

$ErrorActionPreference = "Stop"

if (-not $NoPwshRelaunch -and $PSVersionTable.PSEdition -ne 'Core') {
    $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwshCommand) {
        throw "PowerShell 7 (pwsh) is required for the TPM validation runner. Install PowerShell 7, then rerun this command."
    }

    $argsList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath,
        '-NoPwshRelaunch'
    )

    if (![string]::IsNullOrWhiteSpace($RepoPath)) {
        $argsList += @('-RepoPath', $RepoPath)
    }
    if (![string]::IsNullOrWhiteSpace($TeknoParrotRoot)) {
        $argsList += @('-TeknoParrotRoot', $TeknoParrotRoot)
    }
    if (![string]::IsNullOrWhiteSpace($HarnessRoot)) {
        $argsList += @('-HarnessRoot', $HarnessRoot)
    }
    if ($RunUnattendedTPM) {
        $argsList += '-RunUnattendedTPM'
    }

    & $pwshCommand.Source @argsList
    exit $LASTEXITCODE
}

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
