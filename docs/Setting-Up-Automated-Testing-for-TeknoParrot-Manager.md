# Setting Up Automated Testing for TeknoParrot Manager

Version: 0.2 draft

This guide gets a Windows arcade machine ready to run automated TeknoParrot Manager testing against a real TeknoParrot installation using PowerShell, Pester, PSScriptAnalyzer, Claude Code, Codex, and ChatGPT review.

## Important Path Rule

The TPM repository does **not** have to live on `C:`.

Use whatever development drive makes sense. Recommended examples:

```text
W:\Development\teknoparrot-manager
W:\Development\TPM-TestHarness
W:\Emulators\TeknoParrot
```

or:

```text
D:\Jumpstile\teknoparrot-manager
D:\Jumpstile\TPM-TestHarness
W:\Emulators\TeknoParrot
```

The scripts are now path-portable:

- `RepoPath` can point anywhere.
- `TeknoParrotRoot` can point anywhere.
- `HarnessRoot` can point anywhere.
- If `RepoPath` is omitted when running `scripts\Run-TPM-Tests.ps1`, it automatically uses the repository containing the script.
- If `HarnessRoot` is omitted, it creates `TPM-TestHarness` next to the repository folder.

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
3. First runs must be smoke-test only.
4. Any test that changes TeknoParrot state must create backups first.
5. Reports must be saved before deciding whether to make code changes.
6. Code changes should happen only after a verified, reproducible failure.

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
Install-Module Pester -Scope CurrentUser -Force -RequiredVersion 5.7.1
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
```

Verify:

```powershell
Get-Module Pester -ListAvailable
Get-Module PSScriptAnalyzer -ListAvailable
```

## Step 5 - Clone TeknoParrot Manager

Choose your dev root. Example using `W:\Development`:

```powershell
mkdir W:\Development -Force
cd W:\Development
git clone https://github.com/Jumpstile/teknoparrot-manager.git
cd W:\Development\teknoparrot-manager
git status
```

Expected result:

```text
On branch main
nothing to commit, working tree clean
```

## Step 6 - First Safe Run

From the TPM repo folder:

```powershell
cd W:\Development\teknoparrot-manager
pwsh -ExecutionPolicy Bypass -File .\scripts\Run-TPM-Tests.ps1 `
  -TeknoParrotRoot "W:\Emulators\TeknoParrot"
```

This automatically uses:

```text
RepoPath     = current TPM repository
HarnessRoot = W:\Development\TPM-TestHarness
```

Reports go under:

```text
W:\Development\TPM-TestHarness\Reports\
```

Backups go under:

```text
W:\Development\TPM-TestHarness\Backups\
```

## Optional: Fully Explicit Paths

Use this if your folders are somewhere else:

```powershell
pwsh -ExecutionPolicy Bypass -File "D:\Jumpstile\teknoparrot-manager\scripts\Run-TPM-Tests.ps1" `
  -RepoPath "D:\Jumpstile\teknoparrot-manager" `
  -TeknoParrotRoot "W:\Emulators\TeknoParrot" `
  -HarnessRoot "D:\Jumpstile\TPM-TestHarness"
```

## Step 7 - Claude Prompt

Paste this into Claude Code on the arcade machine:

```text
You are working on Jumpstile/teknoparrot-manager on my arcade machine.

Do not modify files, commit, push, create branches, create releases, or change TeknoParrot state.

Run this exact command from the TPM repo folder:

pwsh -ExecutionPolicy Bypass -File .\scripts\Run-TPM-Tests.ps1 -TeknoParrotRoot "W:\Emulators\TeknoParrot"

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

## Step 8 - Codex Prompt

Paste this into Codex after Claude produces the report:

```text
Independently review the latest TPM test report generated under the configured TPM-TestHarness\Reports folder.

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

## Step 9 - ChatGPT Review

Paste Claude's summary, Codex's verification report, and any important report excerpts back into ChatGPT.

ChatGPT should then:

- Identify real failures versus harmless environment differences.
- Decide whether additional testing is needed.
- Recommend GitHub issues for verified incompatibilities.
- Recommend whether TPM is safe to proceed toward release.

## Step 10 - Real Integration Run

Run this only after the safe report looks good:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\Run-TPM-Tests.ps1 `
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

- HTML report generation.
- JUnit output for CI.
- Stronger before/after diff summaries.
- Automated rollback validation.
- Feature-specific integration tests for crosshairs, ReShade, dgVoodoo, GPU fixes, LaunchBox, HyperSpin, and thumbnails.
