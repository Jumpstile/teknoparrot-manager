# Setting Up Automated Testing for TeknoParrot Manager

Version: 0.1 draft

This guide gets a Windows arcade machine ready to run automated TeknoParrot Manager testing against a real TeknoParrot installation using PowerShell, Pester, PSScriptAnalyzer, Claude Code, Codex, and ChatGPT review.

## Goal

After completing this guide, the arcade machine can run a scripted test harness that:

- Verifies the TPM repository state.
- Runs Pester tests.
- Runs PSScriptAnalyzer.
- Checks the real TeknoParrot folder structure.
- Backs up important TeknoParrot folders before state-changing tests.
- Produces timestamped Markdown and JSON reports.
- Gives Claude/Codex a repeatable command to run instead of freeform manual testing.

## Safety Rules

1. Do not give any AI assistant unrestricted access to the arcade machine.
2. Claude and Codex should run scripted commands only.
3. First runs must be read-only/smoke-test only.
4. Any test that changes TeknoParrot state must create backups first.
5. Reports must be saved before deciding whether to make code changes.
6. Code changes should happen only after a verified, reproducible failure.

## Recommended Folder Layout

```text
C:\Jumpstile\
  teknoparrot-manager\

C:\TPM-TestHarness\
  Scripts\
  Reports\
  Backups\
```

Adjust the real TeknoParrot path for the arcade machine. Example used in this guide:

```text
W:\Emulators\TeknoParrot
```

## Step 1 - Install Required Software

Open Windows Terminal or PowerShell as Administrator.

Install the core tools with WinGet:

```powershell
winget install --id Git.Git -e
winget install --id Microsoft.PowerShell -e
winget install --id GitHub.cli -e
winget install --id Microsoft.VisualStudioCode -e
```

Install Claude Code from Anthropic's official installation instructions.

Install Codex from OpenAI's official Codex instructions or the supported ChatGPT/OpenAI entry point available to the user.

Optional but recommended:

```powershell
winget install --id 7zip.7zip -e
winget install --id Microsoft.Sysinternals -e
```

Restart the machine after installation.

## Step 2 - Verify Tools

Open PowerShell 7, not Windows PowerShell.

Run:

```powershell
git --version
pwsh --version
gh --version
code --version
```

If Claude Code is installed, run:

```powershell
claude --version
claude doctor
```

## Step 3 - Authenticate GitHub CLI

Run:

```powershell
gh auth login
```

Recommended choices:

```text
GitHub.com
HTTPS
Login with browser
```

Then verify:

```powershell
gh auth status
```

## Step 4 - Install PowerShell Test Modules

Run in PowerShell 7 as the normal user:

```powershell
Install-Module Pester -Scope CurrentUser -Force
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
```

Verify:

```powershell
Get-Module Pester -ListAvailable
Get-Module PSScriptAnalyzer -ListAvailable
```

## Step 5 - Clone TeknoParrot Manager

```powershell
mkdir C:\Jumpstile -Force
cd C:\Jumpstile
git clone https://github.com/Jumpstile/teknoparrot-manager.git
cd C:\Jumpstile\teknoparrot-manager
git status
```

Expected result:

```text
On branch main
nothing to commit, working tree clean
```

## Step 6 - Create Test Harness Folders

```powershell
mkdir C:\TPM-TestHarness -Force
mkdir C:\TPM-TestHarness\Scripts -Force
mkdir C:\TPM-TestHarness\Reports -Force
mkdir C:\TPM-TestHarness\Backups -Force
```

## Step 7 - Create the Smoke Test Harness

Create this file:

```powershell
notepad C:\TPM-TestHarness\Scripts\Invoke-TPM-RealInstanceSmoke.ps1
```

Paste this script:

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$RepoPath,

    [Parameter(Mandatory=$true)]
    [string]$TeknoParrotRoot,

    [switch]$RunUnattendedTPM
)

$ErrorActionPreference = "Stop"

$stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$root = "C:\TPM-TestHarness"
$reportDir = Join-Path $root "Reports\$stamp"
$backupDir = Join-Path $root "Backups\$stamp"

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
    Checks = @()
}

Add-Report "# TeknoParrot Manager Real Instance Smoke Test"
Add-Report ""
Add-Report "Timestamp: $stamp"
Add-Report "Repo: $RepoPath"
Add-Report "TeknoParrot Root: $TeknoParrotRoot"
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
```

## Step 8 - First Safe Run

This does not run TPM unattended. It backs up key folders, runs static checks, and writes reports.

```powershell
pwsh -ExecutionPolicy Bypass -File C:\TPM-TestHarness\Scripts\Invoke-TPM-RealInstanceSmoke.ps1 `
  -RepoPath "C:\Jumpstile\teknoparrot-manager" `
  -TeknoParrotRoot "W:\Emulators\TeknoParrot"
```

Review the newest folder under:

```text
C:\TPM-TestHarness\Reports\
```

## Step 9 - Claude Prompt

Paste this into Claude Code on the arcade machine:

```text
You are working on Jumpstile/teknoparrot-manager on my arcade machine.

Do not modify files, commit, push, create branches, create releases, or change TeknoParrot state.

Run this exact command:

pwsh -ExecutionPolicy Bypass -File C:\TPM-TestHarness\Scripts\Invoke-TPM-RealInstanceSmoke.ps1 `
  -RepoPath "C:\Jumpstile\teknoparrot-manager" `
  -TeknoParrotRoot "W:\Emulators\TeknoParrot"

Then summarize:
1. Whether the repo was clean.
2. Whether Pester passed.
3. Whether PSScriptAnalyzer was clean.
4. Whether GameProfiles and UserProfiles exist.
5. Whether pcsx2x6\TeknoParrot\crosshairs exists.
6. Whether Centipede Chaos profile candidates were found.
7. The full report folder path.
8. Any actionable incompatibilities only.

Do not make changes.
```

## Step 10 - Codex Prompt

Paste this into Codex after Claude produces the report:

```text
Independently review the latest TPM test report generated under C:\TPM-TestHarness\Reports.

Do not modify files, commit, push, create branches, create releases, or change TeknoParrot state.

Verify:
1. The test command used was safe and did not include -RunUnattendedTPM.
2. Backups were created for all existing target folders.
3. Pester and PSScriptAnalyzer results were captured.
4. The TeknoParrot folder structure checks are valid.
5. The pcsx2x6 crosshair path check matches upstream expectations.
6. The report identifies any Centipede Chaos profile candidates.
7. Any failure is actionable and reproducible.

Return a concise independent verification report. Do not make changes.
```

## Step 11 - ChatGPT Review

Paste Claude's summary, Codex's verification report, and the report path/results back into ChatGPT.

ChatGPT should then:

- Identify real failures versus harmless environment differences.
- Decide whether additional testing is needed.
- Recommend GitHub issues for verified incompatibilities.
- Recommend whether TPM is safe to proceed toward release.

## Step 12 - Real Integration Run

Run this only after the safe report looks good:

```powershell
pwsh -ExecutionPolicy Bypass -File C:\TPM-TestHarness\Scripts\Invoke-TPM-RealInstanceSmoke.ps1 `
  -RepoPath "C:\Jumpstile\teknoparrot-manager" `
  -TeknoParrotRoot "W:\Emulators\TeknoParrot" `
  -RunUnattendedTPM
```

Before using this mode, confirm:

- TPM config is already saved and valid.
- A full TeknoParrot backup exists.
- The previous smoke test passed.
- The repo is clean.

## Future Work

This first guide is intentionally practical and TPM-focused. Later improvements should include:

- A one-command wrapper script.
- HTML report generation.
- JUnit output for CI.
- Stronger before/after diff summaries.
- Automated rollback validation.
- Feature-specific integration tests for crosshairs, ReShade, dgVoodoo, GPU fixes, LaunchBox, HyperSpin, and thumbnails.
