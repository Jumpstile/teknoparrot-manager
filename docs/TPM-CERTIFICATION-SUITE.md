# TPM Certification Suite

The TPM Certification Suite is the canonical quality and release-validation framework for TeknoParrot Manager.
Current release state: v1.0 RC7 is the current published release; RC8 is the
candidate being prepared and is not published; v1.0 RC6 is the previous
published release (historical); final Version 1.0 remains unpublished.

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

## Arcade OMP Packaged Runtime UX Gate (final RC8 pre-release gate; issue #323)

Purpose: catch defects that appear only when TeknoParrot Manager runs as the
real packaged script in the real Arcade environment. This is the final required
gate before RC8 release authorization, not post-release hardening or optional polish.

### 1. Package identity

- Verify the package was built from the exact PR head and record the branch and
  commit SHA.
- Verify the packaged script hash matches that exact source head.
- Verify every bundled asset exists, including all 321 Crosshairs PNGs and
  packaged runtime dependencies.
- Verify the intended package path/name and source identity so no stale ZIP is
  used accidentally.

### 2. Terminal and menu UX

- Run the package in default-size Windows Terminal and in a constrained-height
  terminal.
- Capture screenshots and inspect the rendered output.
- Verify the title/version, options 1-15, H/L/Q controls, and prompt appear
  directly below the choices.
- Verify there is no giant empty frame, clipped choice, or lost prompt.

### 3. One-letter prompts

- Verify choices are immediately above each prompt, the prompt line is short,
  and the cursor remains on the same line after the prompt.
- Verify no malformed prompt such as `.:` appears.
- Cover GPU Fix, dgVoodoo2, ReShade, BepInEx, FFB, Health Check, PostgreSQL
  recovery, and support/log guidance.

### 4. ReShade runtime UX

- Open option 5 from the package and verify numbered profiles plus shader and
  technique names.
- Verify the wording identifies a preview approximation using the bundled
  image, says no game or shader execution occurs, and says actual results may
  vary.
- Verify the gallery opens non-modally while the terminal chooser remains
  usable.
- Verify the slider visibly moves the divider; switching profiles preserves
  slider operation; `R` reopen preserves selection and slider operation; and
  `U` applies only after confirmation.

### 5. Library Health Check path repair

- Use broken-path fixtures or real broken paths.
- Verify broken-path mode does not show unrelated setup choices.
- Verify automatic search precedes manual browse, candidates are displayed
  before saving, backups are created only before applying, and no save occurs
  without confirmation.
- Verify no-match offers manual executable selection and source re-copy or
  re-extraction.

### 6. Feature workflow routing

- Verify GPU Fix, dgVoodoo2, ReShade, BepInEx, and FFB skip broken paths
  safely and route to option 10, Library Health Check.
- Verify those workflows do not expose duplicate feature-specific path-repair
  wizards.

### 7. Failure truthfulness

- Simulate backup and profile-copy failures and verify each workflow fails
  closed before mutation.
- Verify plugin success cannot mask native FFB failure.
- Verify AutoSync aborts before extraction when backup or profile copy fails.
- Verify result screens state what happened, what TPM changed or did not
  change, and the next action.

### 8. Support package clarity

- Create a support package containing broken-path games and verify creation
  succeeds.
- Verify path-limited plugin inventory omissions are not counted as true
  collection failures.
- Verify affected games appear under `What TPM could not collect`.

Pester remains the home for pure logic and source contracts. Dedicated Arcade
packaged-runtime smoke scripts should exercise the real package, capture
screenshots and logs as evidence, and run on the exact frozen source identity.
The acceptance target is that clipped menus, hidden choosers, misleading
success screens, broken ReShade slider behavior, incorrect path-repair routing,
and support-package false-failure wording are caught before a user reports
them.


Explicitly out of scope through phase 1.7 (tracked in issue #88 for later
phases, not implemented yet): broad fuzzing, long soak testing, mutation
testing, a full property-based framework, randomized menu walking, large
synthetic libraries, performance timing, and cross-project portability. GUI
and browser automation remain out of scope for phase 1.7; the packaged-runtime
UX gate above is the separate final RC8 pre-release requirement tracked in #323.

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

Certification evidence must identify one frozen GitHub branch and exact
commit SHA. Desktop ChatGPT and Desktop Codex use the local
`C:\REPOS\teknoparrot-manager` checkout; Arcade ChatGPT and Arcade Codex
use the local `E:\REPOS\teknoparrot-manager` checkout. Do not use a NAS,
SMB share, mapped drive, or UNC Git worktree as source authority.

`Sync-And-Run.bat` is a convenience launcher for manual latest-main
testing. It may fetch `origin/main` on a local `main` checkout, but it is
not an exact-SHA certification handoff, package identity proof, or release
gate.

For an arcade certification pass, Arcade Codex checks out the handed-off
SHA in the local E path and runs `scripts\Run-TPM-Certification-Suite.bat`
or `scripts\Run-TPM-Tests.ps1` with the approved TeknoParrot runtime root
and local harness path. Arcade ChatGPT reviews and coordinates the resulting
runtime/hardware evidence from the same E-path workflow.

Before reporting a result, record the branch, remote branch SHA, local HEAD,
clean status, ancestry, CI result, runtime marker/containment result, tool
versions, and local report paths. A report copied to an artifact store after
the run must retain those source details.

For scripted or CI-style use, call `scripts\Run-TPM-Tests.ps1` directly
with `-TeknoParrotRoot` (see that script's parameters for `-RepoPath`,
`-HarnessRoot`, `-VerbosityLevel`, and `-PesterRegressionTimeoutSeconds`).

Passing tests or a successful runtime run is evidence, not release or
publication authorization.

### Certification-only boundary

Certification execution is evidence-only and fail-closed. The production cycle
issues the authoritative `CERTIFIED` or `NOT CERTIFIED` outcome from sealed
eligibility without calling `New-TPMPublicationCommitV1`, writing a commit
marker, or creating a publication directory. Infrastructure exceptions remain
`BLOCKED` at the harness boundary and return nonzero.

Publication and release finalization are separate operations. A caller must
explicitly pass `-Publish` to `Complete-TPMProductionCertificationCycleV1`;
the certification runner never passes that switch. Passing tests or a
certification result does not authorize packaging, tagging, releasing,
pushing, or merging.

## Pester regression gate: hang detection and live progress (issue #136)

The Pester regression gate runs on a dedicated in-process runspace, not a
blocking call on the main thread and not a background Job (a Job crosses a
process boundary via CliXml serialization, which would not preserve the deep
result object the Virtual Beta Tester reporting reads several levels into).
While it runs:

- A heartbeat prints every 15 seconds to the console, the console
  title/status, and `Pester-progress.txt` in the report folder -- elapsed
  time plus the last captured line of live Pester output (current
  file/Describe block/test), so a genuinely hung run and a merely slow one
  are never indistinguishable.
- A configurable hard timeout (`-PesterRegressionTimeoutSeconds`, default
  1800s -- the whole suite takes well under a minute on typical hardware)
  stops the run and throws a diagnostic error naming the elapsed time,
  limit, and last known output if it's ever exceeded, rather than blocking
  the certification run forever. The existing report-writing path still
  produces a full certification scorecard on a timeout, showing this gate
  FAILED with a clear reason.
- `Pester-output.txt` always receives live per-test detail regardless of
  `-VerbosityLevel` -- Pester's progress text is captured from the
  Information stream, and Output.Verbosity is always at least `Detailed`
  internally, even in the default `Summary` console mode (confirmed this
  does not additionally echo to the live console).

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
the two Pester suites `Tests/TeknoParrot-Manager.Tests.ps1` and
`Tests/QualitySystem.Tests.ps1` -- not the rest of the `Tests/` folder. Its
job is to catch an obviously broken commit before it lands, in minutes,
without needing a real TeknoParrot install.

**Full release certification** (`scripts/Run-TPM-Tests.ps1`, or
`scripts\Run-TPM-Certification-Suite.bat` for a double-click run) is
broader and slower: the entire `Tests/` folder together (not file by
file), PSScriptAnalyzer, a real-install health check, pcsx2x6-specific
verification, backup-before-touch safety checks, and a certification
scorecard, run against an actual TeknoParrot installation.

This difference is not incidental. The cross-file Pester mock
interference documented above (`Tests/TPMCertificationHarness.Tests.ps1`
vs. `Tests/TpmAutoUpdate.DestructivePath.Tests.ps1`) could **only** be
caught by running the full `Tests/` folder together -- CI's narrow two-file
scope would never have surfaced it, since CI does not run those two files in
its Pester invocation. A green CI run is
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
