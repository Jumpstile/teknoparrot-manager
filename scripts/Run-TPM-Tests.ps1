param(
    [string]$RepoPath,
    # No default -- a prior default of "W:\Emulators\TeknoParrot" pointed at a
    # location that is not actually a TeknoParrot install on any machine this
    # has been run from (confirmed against a real run). A wrong silent default
    # here would make every downstream check -- pcsx2x6 verification, install
    # health, GameProfiles/UserProfiles backups -- run against nothing, and
    # certify a real install that was never actually checked. Always pass the
    # real path explicitly.
    [Parameter(Mandatory = $true)]
    [string]$TeknoParrotRoot,
    [string]$HarnessRoot,
    [switch]$RunUnattendedTPM,
    [switch]$NoPwshRelaunch,

    [ValidateSet('Summary', 'Detailed', 'Diagnostic')]
    [string]$VerbosityLevel = 'Summary',

    [int]$PesterRegressionTimeoutSeconds = 1800
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
    $argsList += @('-VerbosityLevel', $VerbosityLevel)
    $argsList += @('-PesterRegressionTimeoutSeconds', $PesterRegressionTimeoutSeconds)

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
$params.VerbosityLevel = $VerbosityLevel
$params.PesterRegressionTimeoutSeconds = $PesterRegressionTimeoutSeconds

& $harness @params
