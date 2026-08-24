# Setting Up Automated Testing for TeknoParrot Manager

Version: 0.3

This guide sets up the local Desktop and ARCADE workflows for scripted TPM
testing against an approved TeknoParrot installation. The canonical policy
is docs/ENGINEERING-WORKFLOW.md; this guide is a setup aid and does not
replace its exact-SHA or release-gate rules.

## Roles

- Desktop ChatGPT is the chief architect and final readiness/go-no-go
  recommender from `C:\REPOS\teknoparrot-manager`.
- Desktop Codex performs implementation, repository edits, local checks, and
  PR preparation from `C:\REPOS\teknoparrot-manager`.
- Arcade ChatGPT coordinates and reviews arcade validation evidence from
  `E:\REPOS\teknoparrot-manager`.
- Arcade Codex performs exact-SHA validation, runtime observation, and
  hardware certification from `E:\REPOS\teknoparrot-manager`.
- Claude is historical or optional. No active step in this guide requires it.

## Important path rule

Active Git clones and worktrees must be local. Do not use a NAS, SMB share,
mapped drive, or UNC path as the active repository. NAS storage remains valid
for ROM/source data, packages, generated artifacts, evidence, backups, and
mirrors after the local run; it is not source authority.

The standard local paths are:

~~~text
Desktop repository: C:\REPOS\teknoparrot-manager
ARCADE repository:  E:\REPOS\teknoparrot-manager
~~~

RepoPath must point to the local checkout used for the run. HarnessRoot
defaults beside that repository. TeknoParrotRoot is a run-specific runtime
input and must pass its marker, containment, and reparse checks.

## Safety rules

1. Use a clean local checkout and record the GitHub branch and exact SHA.
2. Run scripted commands; do not make ad hoc runtime changes during a test.
3. Smoke-test first. Any state-changing test must create and verify backups.
4. Save reports before deciding whether a code change is needed.
5. Do not edit, commit, push, merge, package, tag, publish, update the live
   wiki, or copy a release ZIP to a distribution mirror during validation.
6. Use -RunUnattendedTPM only when the user explicitly requests that lane.

## Step 1 - Install and verify tools

Install Git, PowerShell 7, GitHub CLI, and the project's supported PowerShell
modules. Windows PowerShell 5.1 is also required for the primary target.

~~~powershell
git --version
pwsh --version
powershell.exe -NoProfile -Command "$PSVersionTable.PSVersion"
gh --version

Install-Module Pester -Scope CurrentUser -Force -RequiredVersion 5.7.1
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
~~~

Authenticate GitHub CLI only when the task requires live CI or branch
inspection:

~~~powershell
gh auth login
gh auth status
~~~

Claude installation and diagnostics are optional and are not a prerequisite
for implementation or certification.

## Step 2 - Prepare the Desktop checkout

Use a clean local clone or isolated worktree. The normal fresh-main sequence
is:

~~~powershell
cd C:\REPOS\teknoparrot-manager
git fetch origin --prune
git switch main
git pull --ff-only origin main
git switch -c review/<issue-or-purpose>
git status --short
~~~

Desktop Codex runs the relevant local gates, records the changed files, and
hands off the GitHub branch and exact SHA. A branch-only handoff is
insufficient.

## Step 3 - Prepare the ARCADE checkout

Arcade Codex refreshes a separate local checkout. It must not validate the
Desktop working directory or an artifact-store Git worktree:

~~~powershell
$Repo = 'E:\REPOS\teknoparrot-manager'
$Branch = 'review/<issue-or-purpose>'
$ExpectedSha = '<exact SHA from GitHub>'

git -C $Repo fetch origin --prune
git -C $Repo fetch origin $Branch
git -C $Repo switch --detach $ExpectedSha
git -C $Repo status --short
git -C $Repo rev-parse HEAD
git -C $Repo ls-remote origin "refs/heads/$Branch"
~~~

The remote branch SHA, local HEAD, clean status, expected ancestry, and CI
result must all be recorded. Stop if the branch moved or the SHA differs.

## Step 4 - Run the safe validation lane

Set the approved runtime root and local harness path, then run:

~~~powershell
$TeknoParrotRoot = '<approved TeknoParrot runtime root>'
$HarnessRoot = 'E:\REPOS\TPM-TestHarness'
pwsh -ExecutionPolicy Bypass -File "$Repo\scripts\Run-TPM-Tests.ps1" -RepoPath $Repo -TeknoParrotRoot $TeknoParrotRoot -HarnessRoot $HarnessRoot
~~~

The suite reports the repository path, commit, runtime root, harness path,
and report folder. Keep the local Reports and Backups outputs. If a copy is
placed in an artifact or evidence store, record the original local paths and
exact SHA beside it.

## Step 5 - Independent evidence review

Arcade Codex reviews the generated reports independently. It must verify:

1. the exact branch/SHA and clean local checkout;
2. the CI result belongs to that SHA;
3. Pester and PSScriptAnalyzer output was captured;
4. runtime markers, containment, and backup gates passed;
5. every failure is actionable and reproducible from the actual evidence;
6. controls readiness, registration, launch observation, and verification
   are reported as separate dimensions.

Return a concise evidence report. Do not make implementation changes while
performing the independent review.

## Step 6 - ChatGPT coordination

Desktop ChatGPT works from `C:\REPOS\teknoparrot-manager` and reconciles
the issue or PR, source branch, exact SHA, changed-file list, CI result,
Desktop checks, and the independent arcade evidence into a final READY or
HOLD recommendation.

Arcade ChatGPT works from `E:\REPOS\teknoparrot-manager` and reviews the
Arcade Codex runtime/hardware report against the same exact SHA. Provide
the issue or PR, branch, exact SHA, CI result, runtime evidence, report
paths, and any failure excerpts. Arcade ChatGPT does not implement or
publish.

A READY recommendation does not authorize a release. No release package,
tag, public release, live wiki update, or Scripts mirror occurs before
the explicit Desktop ChatGPT gate and the human Release Manager's
authorization.

## Scope boundaries

- This guide does not fix the RC8 blockers tracked by #292.
- #279, #280, and #281 remain post-1.0 unless explicitly re-scoped.
- Broad automatic mapping under #200 remains deferred unless explicitly
  approved.
- Historical reports and old procedures are not current evidence without
  exact-SHA verification.
