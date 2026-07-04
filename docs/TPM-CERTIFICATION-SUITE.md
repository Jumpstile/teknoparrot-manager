# TPM Certification Suite

The TPM Certification Suite is the canonical quality and release-validation framework for TeknoParrot Manager.

## Mission

Certify builds—not just run tests.

A build is only eligible for release when all required certification gates pass.

## Certification Lanes

- Regression Suite
- Human-Use Simulation
- Real Install Validation
- Known Bug Regression
- Golden Normalization
- Adversarial Testing
- Mutation Testing
- Fuzz Testing
- Property Testing
- Chaos Testing
- Performance & Scale Testing
- Security & Static Analysis
- Release Certification
- Certification Scorecard
- Virtual Beta Tester (issue #88 phase 1)

## Behavioral Certification (Virtual Beta Tester) -- issue #88

Mission: the certification suite should meaningfully replace scarce human
beta testing, not just run tests. Real, executable coverage against
production behavior lives in `Tests/VirtualBetaTester.*.Tests.ps1` and is
reported as its own "Behavioral Certification (Virtual Beta Tester)" gate
in the certification scorecard, not folded anonymously into the overall
Pester count. The gate reports a category breakdown (human behaviors,
idempotency, recovery, environment variations) plus a count of High-TVD
behaviors covered (see `CONSTITUTION.md`, "Tester Value Density" -- this
count is coverage evidence only, never converted to a percentage or used
in the gate's pass/fail decision).

### Phase 1 -- foundational coverage

- **Human workflow simulation** (`VirtualBetaTester.HumanWorkflow.Tests.ps1`):
  the 5 scenarios in `testdata/human-use-scenarios.json` drive real function
  calls (`Invoke-CheckForUpdates`, and the main menu's choice-validation
  block extracted via the safe temp-file AST pattern) with scripted
  `Read-Host` answers, capture real console output, and assert the
  scenario's required/forbidden phrases -- not just that the dataset is
  well-formed JSON (that structural check is `Tests/HumanUseSimulation.Tests.ps1`,
  and stays separate).
- **Idempotency / repeat-run safety** (`VirtualBetaTester.Idempotency.Tests.ps1`):
  runs a real state-writing function (`Set-Pcsx2CursorPaths`) twice with
  identical inputs and asserts the result doesn't drift or duplicate --
  replacing the specific human-tester habit of "run it again to make sure."
- **Real-world messy environment simulation** (`VirtualBetaTester.MessyFixture.Tests.ps1`):
  one combined fixture with several messy conditions at once (a duplicate/
  oddly-named game folder, an incomplete extraction, a GameProfile missing
  required elements, an alternate-cased PCSX2 folder name, legacy-root and
  canonical-subfolder crosshairs coexisting) -- asserting the combination is
  handled safely, not each condition only in isolation.

### Phase 1.5 -- expanded decision paths, AutoSync idempotency, preview safety

- `Invoke-StartupUpdateCheck`'s full Y/N/V decision tree: view-then-decline,
  accept-then-confirm, accept-then-decline (proves double confirmation is
  required before install), empty input, mixed-case yes, whitespace-padded
  input, repeated view-notes.
- `Resolve-ExtractedGameFolder` (the shared resolver AutoSync itself calls)
  gives an identical answer across two simulated passes with zero
  filesystem changes -- deliberately narrower than the full `Register-Games`
  matching pipeline, which stays excluded from black-box testing.
- `Register-Games -DryRun` reports what it would register but writes zero
  UserProfile files -- proves the preview/dry-run safety invariant holds.

### Phase 1.6 -- Recovery Behavioral Certification (`VirtualBetaTester.Recovery.Tests.ps1`)

Recovery-focused verification a careful human beta tester naturally
performs before trusting a release -- not "does the happy path work," but
"what happens when the state isn't clean":

- **Existing backup already present**: a new `New-PropagationBackup` run
  coexists safely alongside an older, pre-existing backup without
  disturbing it.
- **Partial/malformed state**: `Set-Pcsx2CursorPaths` recovers correctly
  when a PCSX2.ini is missing one or both guncon2 sections entirely (a
  realistic fresh-install condition, not a contrived edge case).
- **Missing dependency**: `Resolve-Pcsx2Directory` returns a clean null,
  never a throw or a guess, when no pcsx2-shaped folder exists at all --
  the common case for most real installs.
- **Existing registration / safe no-op**: re-running `Register-Games`
  against a game that already has a real, user-customized UserProfile
  correctly reports it as `Already`, never re-writes it, and leaves the
  user's existing customization byte-identical.

### Phase 1.7 -- Interrupted-write, restore, conflict-resolution, and cancel/decline certification (issue #88, priorities A1-A4)

Replaces the highest-risk human beta-testing activities identified in the
post-Phase-1.6 roadmap review: what happens when a run gets interrupted,
whether "restore from backup" (one of TPM's highest-value safety features)
actually works, whether registration conflicts are resolved conservatively
instead of guessed, and whether every state-changing workflow's cancel path
genuinely makes zero changes.

- **Interrupted write / partial output recovery** (`VirtualBetaTester.InterruptedWriteRecovery.Tests.ps1`):
  a leftover `.xml.tmp` from a killed mid-write is structurally invisible
  to every profile scan in the codebase (the same `*.xml` filter every
  scan uses); `Save-Xml` recovers cleanly and produces correct final
  content even when a stale `.tmp` from a prior interrupted run already
  occupies its temp path, across repeated interrupted-then-recovered
  cycles; a failed temp-file write never touches the existing good file
  (the atomicity guarantee the write-to-temp-then-rename pattern exists
  for); a fresh backup run is complete even when an earlier interrupted
  backup left a partial folder behind; a truncated/malformed profile is
  skipped without crashing the scan, and every other valid profile is
  still processed.
- **Restore Backup behavioral recovery** (`VirtualBetaTester.RestoreBackup.Tests.ps1`):
  `Invoke-RestoreBackup` had zero prior test coverage despite being one of
  TPM's highest-value safety features. Covers: enumeration and correct
  most-recent-first selection across multiple backups; safe cancel at
  either prompt (selection or confirmation) with zero changes and no
  delete-before-confirm ordering bug; a malformed backup (zero XML
  profiles) is rejected before any deletion happens; restoring one backup
  never disturbs any sibling backup snapshot; refuses to run while
  TeknoParrotUi.exe is open.
- **AutoSync / registration conflict resolution** (`VirtualBetaTester.RegistrationConflictResolution.Tests.ps1`):
  `Repair-GamePaths` (the "a game folder moved since it was registered"
  handler) had zero prior test coverage. Covers: fixes a broken GamePath
  when the exe now lives at a new, unambiguous location; reports
  `ambiguous` (never guesses) when the same exe name exists at two
  locations on disk, or maps to more than one profile in the library;
  reports `not-found` (never fabricates a path) when the exe is genuinely
  gone; a valid GamePath is never even reported, let alone rewritten;
  DryRun reports what would be fixed without writing anything.
- **Cancel / decline matrix** (`VirtualBetaTester.CancelDeclineMatrix.Tests.ps1`):
  `Invoke-GpuFixSetup`'s cancel paths (pressing Enter, or typing an
  unrecognized vendor, when GPU auto-detection fails) had zero prior
  coverage -- both now proven to make zero changes and create no backup
  folder before any work begins; a read-only compatibility scan is proven
  to genuinely touch nothing on disk via a full before/after filesystem
  diff, not just console wording.

Explicitly out of scope through phase 1.7 (tracked in issue #88 for later
phases, not implemented yet): broad fuzzing, long soak testing, mutation
testing, a full property-based framework, randomized menu walking, large
synthetic libraries, GUI/browser automation, performance timing, soak
testing, cross-project portability.

## Certification Levels

### Level 1 — Development Certified
Fast developer validation.

### Level 2 — Beta Certified
Adds human-use simulation and real-install validation.

### Level 3 — Release Candidate Certified
Adds adversarial, mutation, fuzz, performance, and security validation.

### Level 4 — Gold Certified
Full certification including long-duration, scale, and stress testing.

## Required Artifacts

Every certification run should produce:

- TPM-Certification-Scorecard.md
- TPM-Certification-Scorecard.json
- TPM-Validation-Report.md
- TPM-Validation-Report.json
- Install Health report
- Pester results
- Static analysis results
- Detailed logs
- Performance metrics
- Failure diagnostics

## Running Certification

For manual tester validation of the latest merged TPM code (not a full
certification pass), run `Sync-And-Run.bat` from the repository root on
`main`. This file lives at the repo root because it depends on the checkout's
`.git` directory: it fetches `origin/main`, fast-forwards only when safe,
then launches `TeknoParrot-Manager.ps1`. It is a tester checkout launcher,
not an installed runtime launcher and not a release ZIP entry point.

The easiest way to run a certification pass on the arcade machine is to
double-click `scripts\Run-TPM-Certification-Suite.bat`. It can be copied
anywhere (Desktop, a USB stick) and still finds the repo -- it does not
need to be run from inside the repo folder, and does not require
administrator privileges. It prompts for the TeknoParrot root (with a
default), runs `scripts\Run-TPM-Tests.ps1`, and keeps the window open at
the end so you can read the CERTIFIED / NOT CERTIFIED result and the
report folder location before it closes.

For scripted or CI-style use, call `scripts\Run-TPM-Tests.ps1` directly
with `-TeknoParrotRoot` (see that script's parameters for `-RepoPath`,
`-HarnessRoot`, and `-VerbosityLevel`).

## Known Implementation Constraints

`Tests/TPMCertificationHarness.Tests.ps1` extracts functions from
`scripts/Invoke-TPM-RealInstanceSmoke.ps1` via AST (neither that script nor
`TeknoParrot-Manager.ps1` can be dot-sourced directly -- both have top-level
executable code). The extracted function text is written to a temporary
`.ps1` file and dot-sourced from there, not dot-sourced directly from a
`[scriptblock]::Create()` result. This is required, not stylistic: the
`[scriptblock]::Create()` form was confirmed to break
`Tests/TpmAutoUpdate.DestructivePath.Tests.ps1`'s module-scoped Pester mock
when both files run together (the normal case for a real certification
run), letting real GitHub API calls through and failing on rate limits. See
`LESSONS_LEARNED.md` ("TPM Certification Suite (commit bb2a160)") for the
full bisection. Do not revert this to `[scriptblock]::Create()` without
re-running the full `Tests/` folder to confirm the destructive-path suite
still passes -- a single-file test run will not catch the regression.

## CI vs. Full Release Certification

These are deliberately different in scope, and neither substitutes for the
other.

**CI (`.github/workflows/ci.yml`)** runs on every push and pull request
against `main`. It is intentionally narrow and fast: ASCII/parse checks on
`TeknoParrot-Manager.ps1`, PSScriptAnalyzer against that same file, and
`Tests/TeknoParrot-Manager.Tests.ps1` only -- not the rest of the `Tests/`
folder. Its job is to catch an obviously broken commit before it lands,
in minutes, without needing a real TeknoParrot install.

**Full release certification** (`scripts/Run-TPM-Tests.ps1`, or
`scripts\Run-TPM-Certification-Suite.bat` for a double-click run) is
broader and slower: the entire `Tests/` folder together (not file by
file), PSScriptAnalyzer, a real-install health check, pcsx2x6-specific
verification, backup-before-touch safety checks, and a certification
scorecard, run against an actual TeknoParrot installation.

This difference is not incidental. The cross-file Pester mock
interference documented above (`Tests/TPMCertificationHarness.Tests.ps1`
vs. `Tests/TpmAutoUpdate.DestructivePath.Tests.ps1`) could **only** be
caught by running the full `Tests/` folder together -- CI's narrower,
single-file scope would never have surfaced it, since CI does not run
those two files in the same Pester invocation. A green CI run is
necessary before merging, but it is not evidence that a change is safe
at the level full certification checks. Do not treat CI passing as a
substitute for running full certification before a release; do not treat
a CI job in isolation as sufficient coverage for a change to the test
suite's own cross-file behavior.

## Guiding Principle

Passing tests does not automatically certify a build. Certification requires all applicable quality gates to pass.

## Release Integrity Audit

Certification is necessary but no longer sufficient for a public release. Every
RC, Beta, Final, and Hotfix must also pass the Release Integrity Audit in
`RELEASE-SAFETY-CHECKLIST.md` before publication.

The audit verifies that the delivered product matches the certified build:

- runtime banner and display version,
- `$ScriptVersion` and release-candidate label,
- update dialogs and updater comparisons,
- generated reports and certification scorecards,
- README, Quick Start, changelog, release notes, docs, and wiki,
- release ZIP filename and packaged `TeknoParrot-Manager.ps1`,
- GitHub Release tag, title, asset name, asset size, and downloaded asset.

The packaged runtime must identify itself as the release being published. A
structurally valid ZIP is not release-ready if its banner, docs, release notes,
or GitHub metadata identify a different release.
