param(
    [Parameter(Mandatory=$true)]
    [string]$RepoPath,

    [Parameter(Mandatory=$true)]
    [string]$TeknoParrotRoot,

    [string]$HarnessRoot,

    [switch]$RunUnattendedTPM
)

$ErrorActionPreference = "Stop"

$RepoPath = (Resolve-Path -LiteralPath $RepoPath).Path

if (!(Test-Path -LiteralPath $TeknoParrotRoot -PathType Container)) {
    throw "TeknoParrot root not found: $TeknoParrotRoot"
}
$TeknoParrotRoot = (Resolve-Path -LiteralPath $TeknoParrotRoot).Path

if ([string]::IsNullOrWhiteSpace($HarnessRoot)) {
    $repoParent = Split-Path -Parent $RepoPath
    $HarnessRoot = Join-Path $repoParent "TPM-TestHarness"
}

$stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportDir = Join-Path $HarnessRoot "Reports\$stamp"
$backupDir = Join-Path $HarnessRoot "Backups\$stamp"

New-Item -ItemType Directory -Force -Path $reportDir, $backupDir | Out-Null

$md = Join-Path $reportDir "TPM-RealInstance-Report.md"
$json = Join-Path $reportDir "TPM-RealInstance-Report.json"

function Add-Report {
    param([string]$Text)
    $Text | Out-File -FilePath $md -Append -Encoding utf8
}

function Copy-IfExists {
    param([string]$Path, [string]$DestName)
    if (Test-Path -LiteralPath $Path) {
        Copy-Item -LiteralPath $Path -Destination (Join-Path $backupDir $DestName) -Recurse -Force
        return $true
    }
    return $false
}

function Get-TreeHash {
    param([string]$Path)
    if (!(Test-Path -LiteralPath $Path)) { return @() }

    Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
        Sort-Object FullName |
        ForEach-Object {
            $h = Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
            [pscustomobject]@{
                Path = $_.FullName
                Hash = $h.Hash
                Length = $_.Length
            }
        }
}

$results = [ordered]@{
    Timestamp = $stamp
    RepoPath = $RepoPath
    TeknoParrotRoot = $TeknoParrotRoot
    HarnessRoot = $HarnessRoot
    Checks = @()
}

Add-Report "# TeknoParrot Manager Real Instance Smoke Test"
Add-Report ""
Add-Report "Timestamp: $stamp"
Add-Report "Repo: $RepoPath"
Add-Report "TeknoParrot Root: $TeknoParrotRoot"
Add-Report "Harness Root: $HarnessRoot"
Add-Report ""

Push-Location $RepoPath

try {
    Add-Report "## Git Status"
    $gitStatus = git status --short
    if ($LASTEXITCODE -ne 0) { throw "git status failed" }
    if (-not $gitStatus) { $gitStatus = "(clean)" }
    Add-Report '```'
    Add-Report ($gitStatus | Out-String)
    Add-Report '```'

    Add-Report "## Backup"
    $backupItems = [ordered]@{}

    $backupItems.UserProfiles = Copy-IfExists (Join-Path $TeknoParrotRoot "UserProfiles") "UserProfiles"
    $backupItems.GameProfiles = Copy-IfExists (Join-Path $TeknoParrotRoot "GameProfiles") "GameProfiles"
    $backupItems.Pcsx2x6Crosshairs = Copy-IfExists (Join-Path $TeknoParrotRoot "pcsx2x6\TeknoParrot\crosshairs") "pcsx2x6-crosshairs"
    $backupItems.Config = Copy-IfExists (Join-Path $RepoPath "TeknoParrot-Manager.config.json") "TeknoParrot-Manager.config.json"

    $results.Backup = $backupItems
    Add-Report "Backup path: $backupDir"
    Add-Report ""

    Add-Report "## Pre-Test Snapshot"
    $preUserProfiles = Get-TreeHash (Join-Path $TeknoParrotRoot "UserProfiles")
    $preCrosshairs = Get-TreeHash (Join-Path $TeknoParrotRoot "pcsx2x6\TeknoParrot\crosshairs")
    Add-Report "UserProfiles files: $($preUserProfiles.Count)"
    Add-Report "pcsx2x6 crosshair files: $($preCrosshairs.Count)"
    Add-Report ""

    Add-Report "## Pester"
    Invoke-Pester -Path $RepoPath -Output Detailed -PassThru |
        ConvertTo-Json -Depth 8 |
        Out-File (Join-Path $reportDir "Pester.json") -Encoding utf8
    Add-Report "Pester completed. See Pester.json."
    Add-Report ""

    Add-Report "## PSScriptAnalyzer"
    $analyzer = Invoke-ScriptAnalyzer -Path $RepoPath -Recurse
    $analyzer | ConvertTo-Json -Depth 6 | Out-File (Join-Path $reportDir "PSScriptAnalyzer.json") -Encoding utf8

    if ($analyzer.Count -eq 0) {
        Add-Report "PSScriptAnalyzer: clean"
    } else {
        Add-Report "PSScriptAnalyzer findings: $($analyzer.Count)"
    }
    Add-Report ""

    Add-Report "## TeknoParrot Structure Checks"

    $expected = @(
        "TeknoParrotUi.exe",
        "GameProfiles",
        "UserProfiles",
        "pcsx2x6"
    )

    foreach ($item in $expected) {
        $path = Join-Path $TeknoParrotRoot $item
        $exists = Test-Path -LiteralPath $path
        Add-Report "- $item : $exists"
        $results.Checks += [pscustomobject]@{ Name=$item; Exists=$exists; Path=$path }
    }

    $officialCrosshairPath = Join-Path $TeknoParrotRoot "pcsx2x6\TeknoParrot\crosshairs"
    Add-Report ""
    Add-Report "Official pcsx2x6 crosshair path exists: $(Test-Path -LiteralPath $officialCrosshairPath)"
    Add-Report "Expected files:"
    Add-Report "- $officialCrosshairPath\P1.png"
    Add-Report "- $officialCrosshairPath\P2.png"
    Add-Report ""

    Add-Report "## GameProfile Checks"
    $profilesPath = Join-Path $TeknoParrotRoot "GameProfiles"
    if (Test-Path -LiteralPath $profilesPath) {
        $profiles = Get-ChildItem -LiteralPath $profilesPath -File -ErrorAction SilentlyContinue
        Add-Report "GameProfiles count: $($profiles.Count)"

        $centipede = $profiles | Where-Object { $_.Name -match "centipede|chaos" }
        Add-Report "Centipede/Chaos profile candidates:"
        if ($centipede) {
            foreach ($p in $centipede) { Add-Report "- $($p.Name)" }
        } else {
            Add-Report "- none found"
        }
    }
    Add-Report ""

    if ($RunUnattendedTPM) {
        Add-Report "## TPM Unattended Run"
        $scriptPath = Join-Path $RepoPath "TeknoParrot-Manager.ps1"

        if (!(Test-Path -LiteralPath $scriptPath)) {
            throw "TeknoParrot-Manager.ps1 not found at $scriptPath"
        }

        $tpmLog = Join-Path $reportDir "TPM-Unattended.log"
        pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Unattended *> $tpmLog
        Add-Report "TPM unattended run completed. See TPM-Unattended.log."
        Add-Report ""
    } else {
        Add-Report "## TPM Unattended Run"
        Add-Report "Skipped. Re-run with -RunUnattendedTPM only after confirming config and backups."
        Add-Report ""
    }

    Add-Report "## Post-Test Snapshot"
    $postUserProfiles = Get-TreeHash (Join-Path $TeknoParrotRoot "UserProfiles")
    $postCrosshairs = Get-TreeHash (Join-Path $TeknoParrotRoot "pcsx2x6\TeknoParrot\crosshairs")

    Add-Report "UserProfiles files after: $($postUserProfiles.Count)"
    Add-Report "pcsx2x6 crosshair files after: $($postCrosshairs.Count)"
    Add-Report ""

    $results.ReportPath = $reportDir
    $results.Status = "Completed"
}
catch {
    $results.Status = "Failed"
    $results.Error = $_.Exception.Message
    Add-Report "## ERROR"
    Add-Report $_.Exception.Message
    throw
}
finally {
    Pop-Location
    $results | ConvertTo-Json -Depth 10 | Out-File $json -Encoding utf8
    Add-Report ""
    Add-Report "JSON report: $json"
}
