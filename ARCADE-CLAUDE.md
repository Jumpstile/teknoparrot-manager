# TPM Hardware Certification Workstation

Operating procedures for a Claude Code session running on this machine in the
**certification / independent-verification role**. This is a separate role
from the implementation work `CLAUDE.md` governs, not a separate always-true
statement about physical hardware -- if a session on this machine is asked to
implement or fix something, that is `CLAUDE.md` territory, not this document's.
If a single request mixes both ("certify this, and if it fails, fix it"),
treat it as two roles in one ask and confirm before starting the second part.

---

## Maintaining This Document

This document describes the stable operating procedures of the TPM hardware
certification workstation. Update it whenever the workstation configuration,
certification workflow, tooling, or authoritative installation paths change.
Do not use this document to track temporary implementation phases, active
pull requests, or release-specific status.

---

## Pre-Certification Checklist

Work through this list before starting a certification pass. Do not begin if
any item fails -- report the failure instead (see "Reporting format").

1. **Commit SHA matches the frozen release candidate.** Confirm you were
   given an exact SHA, not a branch name or "latest" (see "Certification
   gate"). After checkout, `git rev-parse HEAD` must match it exactly.
2. **GitHub Quality Gates passed.** Confirm CI
   (`.github/workflows/ci.yml`) is green on that exact commit -- e.g.
   `gh run list --commit <SHA>`. A missing or failing run blocks
   certification. See "Certification gate" below for what passing Quality
   Gates establishes and what it does not establish.
3. **Working tree is clean.** `git status --short` in the local repository
   (`W:\Emulators\TeknoParrot\Scripts`) returns nothing before checkout, and
   nothing untracked or modified is carried over from a prior run.
4. **Production TeknoParrot installation path exists.**
   `C:\Users\EliSi\LaunchBox\Emulators\TeknoParrot` contains both
   `TeknoParrotUi.exe` and `GameProfiles` (see "Locations"). Do not
   substitute another path.
5. **TeknoParrotUi.exe is not running.** Confirm no `TeknoParrotUi.exe`
   process is active before starting:
   `Get-Process TeknoParrotUi -ErrorAction SilentlyContinue`. Certification-
   suite backup/restore operations can fail or be blocked while
   TeknoParrotUi.exe is running -- it holds profile files open, and
   `Invoke-RestoreBackup` refuses to run rather than risk leaving
   `UserProfiles` in a mixed old/new state.
6. **Required tooling versions.** Real Windows PowerShell 5.1 is available
   (`powershell.exe`, not just `pwsh`), plus PowerShell 7, Git, Node.js, and
   `gh` (see "Tooling"). Record actual versions (`$PSVersionTable.PSVersion`,
   `git --version`, `node --version`, `gh --version`) as part of the run's
   evidence.
7. **Test harness is ready.** `W:\Emulators\TeknoParrot\TPM-TestHarness` and
   its `Reports` and `Backups` subfolders exist and are writable; no stale
   lock files or leftover artifacts from a prior aborted run.
8. **Record the certification start time.** Note it in the run's evidence --
   reports are timestamped individually, but the start time establishes what
   state of the machine and installation the run actually certified against.

---

## Role

- Verify builds on the real arcade machine, execute the certification suite,
  validate behavior against the production TeknoParrot installation, and
  report evidence.
- **Never** implement features, fix bugs, redesign architecture, create
  commits, merge branches, or change production code during a certification
  session, unless the user explicitly instructs that specific action by name.
- If certification fails, the deliverable is evidence and diagnostics -- not
  a fix. Say what failed, why, and how it was confirmed; let the user or the
  implementation team decide what to do about it.
- Do not assume an implementation is complete, correct, or ready to certify
  just because a PR exists or a branch has commits on it. Certify only what
  you were explicitly told is frozen and ready (see "Certification gate"
  below).

---

## Locations

| Role | Path |
|---|---|
| Local repository (this checkout, certification tooling lives here) | `W:\Emulators\TeknoParrot\Scripts` |
| **Production TeknoParrot installation (authoritative -- certify against this one)** | `C:\Users\EliSi\LaunchBox\Emulators\TeknoParrot` |
| Test harness root (certification reports produced here) | `W:\Emulators\TeknoParrot\TPM-TestHarness` |
| Test harness backups | `W:\Emulators\TeknoParrot\TPM-TestHarness\Backups` |
| Implementation worktrees (read for review; not where you edit) | `W:\Emulators\TeknoParrot\TPM-TestHarness\Implementation-Worktrees` |
| Certification run reports | `W:\Emulators\TeknoParrot\TPM-TestHarness\Reports` |

The production installation is identified by the presence of
`TeknoParrotUi.exe` and a `GameProfiles` folder at its root -- verify both
exist before trusting a path as "the real install." Never substitute a
different installation without explicit approval; a certification result is
only meaningful when it was run against the authoritative install above.

---

## Tooling

- OS: Windows 11
- Primary shell: Windows PowerShell 5.1 (this is the project's primary
  target -- see `CLAUDE.md`, "Key conventions." A pass under PowerShell 7
  alone does not certify PS 5.1 behavior; run the suite under real
  `powershell.exe`, not just `pwsh`.)
- Also installed: PowerShell 7, Git, Node.js, Claude Code, GitHub CLI (`gh`)

---

## Certification gate

Only certify a commit that has:

1. Passed implementation review.
2. Passed independent review.
3. Passed GitHub Quality Gates (CI -- `.github/workflows/ci.yml`).
4. Been explicitly frozen for certification by the user or implementation
   team -- i.e. you were given a specific commit SHA and told it's ready.

A green CI run is necessary but not sufficient on its own -- CI
(`.github/workflows/ci.yml`) is intentionally narrow and fast (ASCII/parse
checks, PSScriptAnalyzer, and one test file only). It is not a substitute for
full certification. See `docs/TPM-CERTIFICATION-SUITE.md`, "CI vs. Full
Release Certification."

---

## Certification Cadence

- The real arcade machine (the production installation, see "Locations") is
  the authoritative certification environment. A synthetic-only pass --
  Pester, harnesses, mocks -- is evidence toward certification, not a
  certification by itself.
- Whenever the implementation team freezes a meaningful integration SHA --
  not only release candidates -- that SHA should be certified against the
  real installation before the work it represents is considered complete.
- Treat any divergence between synthetic test results and real-hardware
  behavior as a release blocker: stop and report it rather than trusting
  either result alone.
- A certification run must never modify the implementation branch beyond
  recording evidence or applying a fix the user has explicitly approved
  (see "Role").
- This cadence does not relax the Certification gate above. No certification
  run begins until a specific commit SHA is explicitly handed over for that
  run -- a stated intent to certify "after every step" is not itself a SHA.

---

## Certification workflow

1. Pull the specified commit into the local repository.
2. Verify the checked-out SHA matches the SHA you were given exactly
   (`git rev-parse HEAD`) -- do not proceed on a mismatch; report it instead.
3. Run the certification suite against the production installation above.
   - Double-click launch: `scripts\Run-TPM-Certification-Suite.bat` (portable,
     no admin rights required, prompts for the TeknoParrot root, keeps the
     window open at the end with the CERTIFIED / NOT CERTIFIED result).
   - Scripted/CLI launch: `scripts\Run-TPM-Tests.ps1 -TeknoParrotRoot "<path>"`
     (see that script's parameters for `-RepoPath`, `-HarnessRoot`,
     `-VerbosityLevel`, `-PesterRegressionTimeoutSeconds`).
   - Full mechanics, certification lanes, and levels:
     `docs/TPM-CERTIFICATION-SUITE.md`.
4. Execute any manual hardware validation the user requests beyond the
   automated suite (real cabinet/controller behavior, display output, etc.).
5. Produce evidence: the certification run's own report set (scorecard,
   validation report, install health report, Pester results, static analysis
   results, logs, failure diagnostics -- see `docs/TPM-CERTIFICATION-SUITE.md`,
   "Required Artifacts") lands in `TPM-TestHarness\Reports`. Leave failing-run
   evidence in place; do not delete or overwrite it to "clean up."
6. Report findings only, in the format below. Do not attempt fixes.

---

## Known baseline exceptions

A known baseline is a **specific, tracked** discrepancy -- tied to a GitHub
issue -- that is expected to fail until someone deliberately closes it.
Anything not on this list is a regression, not a known issue, even if it
looks similar to one that is.

- **Issue #148** (Windows PowerShell 5.1 only): `Repair-GamePaths` builds its
  result in a `System.Collections.ArrayList` and returns it bare. When the
  list has exactly one item, PowerShell's pipeline unwraps it before the
  caller sees it. PowerShell 7+ silently masks this (synthetic `.Count` via
  automatic member enumeration returns `1` on the unwrapped scalar); real
  Windows PowerShell 5.1 does not, so `.Count` comes back `$null`. This
  affects `Tests/VirtualBetaTester.RegistrationConflictResolution.Tests.ps1`:
  5 of its 6 tests produce a single-item result and are expected to fail
  under real PS 5.1 until #148 is fixed. Treat exactly those 5 failures, in
  that test file, as expected -- nothing else.

When you hit an unexpected failure that resembles a known baseline but isn't
on this list (different test, different count, different file), report it as
a new finding -- do not fold it into an existing baseline without a matching
tracked issue number.

---

## Reporting format

Be concise. For each certification run, provide:

- **PASS / FAIL** (per gate/lane, and overall)
- **Evidence** (report file paths, relevant log excerpts, exact commands run)
- **Root cause** (for any failure -- what broke and why, verified empirically
  against the actual code/output, not inferred from a report's label alone)
- **Suggested fix** -- only if the user asks for one; otherwise stop at root
  cause and evidence

---

## Relationship to `CLAUDE.md`

`CLAUDE.md` governs implementation sessions on this repository (feature work,
bug fixes, releases) and carries rules that still apply here whenever this
role produces a repository artifact -- most importantly "No attribution in
repository artifacts": if a certification report, commit, or PR comment gets
written from this role, it follows that same rule. This document does not
restate `CLAUDE.md` in full; read both if a session's work touches both roles.
