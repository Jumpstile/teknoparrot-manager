# Arcade validation entry point (legacy filename)

This file retains its historical ARCADE-CLAUDE.md name so existing local
launch points do not break. The current role is **Arcade Codex**: exact-SHA
validation, runtime observation, hardware certification, and evidence
collection. Claude is optional and is not required by this procedure.

The canonical cross-machine workflow is
docs/ENGINEERING-WORKFLOW.md. Read it before starting any validation session.

Arcade ChatGPT may coordinate and review this validation from the same local
`E:\REPOS\teknoparrot-manager` path. Its entry point is `ARCADE-CHATGPT.md`;
Arcade Codex remains the runtime and hardware validation executor.

## Role boundary

- Validate the frozen commit on the real arcade installation, execute the
  requested certification lanes, observe hardware behavior, and report
  evidence.
- Do not implement features, fix bugs, redesign architecture, create commits,
  merge branches, publish releases, update the live wiki, or copy a release
  ZIP to a distribution mirror during certification.
- If certification fails, return evidence and a verified diagnosis. The
  implementation team decides whether and how to fix it.
- A successful CI run or a pull request does not prove certification readiness.

## Workspace and path policy

The active validation Git checkout is local:

~~~text
E:\REPOS\teknoparrot-manager
~~~

Do not validate from a NAS, SMB share, mapped drive, or UNC Git worktree. A
NAS may receive ROM/source data, packages, generated artifacts, backups, or a
copy of completed evidence after the local run; it is not an authoritative
checkout and must not supply source identity.

The TeknoParrot runtime root is an explicit run input. It must contain
TeknoParrotUi.exe and GameProfiles, and it must pass the applicable canonical
containment and reparse-point checks. Do not substitute a runtime root based
only on a remembered machine path.

The default harness is next to the local repository. Record the exact local
Reports and Backups paths in the run handoff. Do not delete failing-run
evidence to make a folder look clean.

## Pre-certification checklist

Do not start the run until all items pass:

1. The handoff names a GitHub branch and exact commit SHA, not only "latest".
2. git ls-remote origin refs/heads/<branch> equals the handed-off SHA.
3. Local git rev-parse HEAD equals that SHA.
4. git status --short is empty and the expected ancestry is verified.
5. GitHub CI is green for that exact SHA.
6. The approved runtime root contains TeknoParrotUi.exe and GameProfiles.
7. TeknoParrotUi.exe is not running before backup or restore operations.
8. Windows PowerShell 5.1 is available for the project's primary target, and
   the actual tool versions are recorded.
9. The local harness Reports and Backups folders are ready.

If any item fails, stop and report the mismatch. Do not silently switch to a
different branch, local folder, runtime root, or old report.

## Checkout and validation flow

Use the GitHub branch and SHA supplied by Desktop Codex or ChatGPT:

~~~powershell
$Repo = 'E:\REPOS\teknoparrot-manager'
$Branch = 'review/example'
$ExpectedSha = '<exact SHA from GitHub>'

git -C $Repo fetch origin --prune
git -C $Repo fetch origin $Branch
git -C $Repo switch --detach $ExpectedSha
git -C $Repo status --short
git -C $Repo rev-parse HEAD
git -C $Repo ls-remote origin "refs/heads/$Branch"
~~~

The detached checkout is acceptable when the source branch is recorded with
the SHA. Stop if the remote branch moved after handoff; a new SHA must be
frozen and revalidated.

Run the suite from the local checkout. Supply the approved runtime root and a
local harness path:

~~~powershell
$TeknoParrotRoot = '<approved TeknoParrot runtime root>'
$HarnessRoot = 'E:\REPOS\TPM-TestHarness'
pwsh -ExecutionPolicy Bypass -File "$Repo\scripts\Run-TPM-Tests.ps1" -RepoPath $Repo -TeknoParrotRoot $TeknoParrotRoot -HarnessRoot $HarnessRoot
~~~

Use scripts\Run-TPM-Certification-Suite.bat only as a launcher for the same
local repository and approved runtime root. Sync-And-Run.bat is a convenience
launcher for manual latest-main testing; it is not the authority for an
exact-SHA certification handoff.

-RunUnattendedTPM is not a default validation step. Use it only when the user
explicitly requests that lane and the run records the separate gate, backup,
runtime root, and evidence requirements.

## Evidence and reporting

Record:

- repository, source branch, expected SHA, remote branch SHA, local HEAD,
  clean status, ancestry, and CI result;
- runtime root and marker/containment result;
- exact commands, tool versions, start time, lane results, and hardware
  observations;
- scorecard, validation report, install-health report, Pester output, static
  analysis output, logs, and failure diagnostics;
- local report paths and any later artifact-store copy path.

Report PASS or FAIL for each lane and overall. Explain failures from the actual
output and code, not from a report label alone. Do not recommend a release,
tag, wiki update, or mirror copy solely because the suite passed.
