# TPM Certification Suite

The TPM Certification Suite is the canonical quality and release-validation framework for TeknoParrot Manager.
Current release state: v1.0 RC8.4 is the latest published release;
v1.0 RC8.3 is the previous published release; RC8.2, RC8.1, RC7 and RC6 are
earlier published releases; final Version 1.0
has not been published yet.

## Mission

Certify builds - not just run tests.

A build is only eligible for release when all required certification gates pass. The lanes marked "not implemented" below are not gates yet and do not count as passed.

## Certification Lanes

- Regression Suite
- Human-Use Simulation
- Real Install Validation
- Known Bug Regression
- Golden Normalization
- Adversarial Testing
- Mutation Testing (not implemented)
- Fuzz Testing (not implemented)
- Property Testing (not implemented)
- Chaos Testing (not implemented)
- Performance & Scale Testing (not implemented)
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
  the 5 scenarios in `testdata/human-use-scenarios.json` that have a runnable
  screen (startup, update offer, read-only update failure, main menu, cancel)
  drive real function
  calls (`Invoke-CheckForUpdates`, and the main menu's choice-validation
  block extracted via the safe temp-file AST pattern) with scripted
  `Read-Host` answers, capture real console output, and assert the
  scenario's required/forbidden phrases -- not just that the dataset is
  well-formed JSON (that structural check is `Tests/HumanUseSimulation.Tests.ps1`,
  and stays separate). The other 2 scenarios (the PostgreSQL password screen and Create
  Support Package) are not run on screen; `Tests/HumanUseSimulation.Tests.ps1`
  checks that every required phrase of every scenario is real product text, so
  a scenario can never keep asking for wording the product does not have.
- **Idempotency / repeat-run safety** (`VirtualBetaTester.Idempotency.Tests.ps1`):
  runs real repeat-run code (the verified UserProfiles backup and the AutoSync
  folder lookup) more than once with identical inputs and asserts the result
  doesn't drift or duplicate --
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

- **Existing backup already present**: a new `New-TpmVerifiedUserProfilesBackup` run
  coexists safely alongside an older, pre-existing backup without
  disturbing it.
- **Partial/malformed state**: `Get-Pcsx2CursorPathReport` reports empty values
  and changes nothing when a PCSX2.ini has no guncon2 cursor path keys at all (a
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

## Test-PC Packaged Runtime UX Gate (final RC8 pre-release gate; issue #323)

Purpose: catch defects that appear only when TeknoParrot Manager runs as the
real packaged script in the real test-PC environment. This is the final required
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
- Verify the title/version, options 1-17, H/L/Q controls, and prompt appear
  directly below the choices.
- Verify there is no giant empty frame, clipped choice, or lost prompt.

### 3. One-letter prompts

- Verify choices are immediately above each prompt, the prompt line is short,
  and the cursor remains on the same line after the prompt.
- Verify no malformed prompt such as `.:` appears.
- Cover GPU Fix, dgVoodoo2, ReShade, BepInEx, FFB, Health Check, PostgreSQL
  recovery, and support/log guidance.

### 4. ReShade runtime UX

- Open option 5 from the package and verify the 17 profiles (Original plus 16
  arcade looks, built from 12 of the 25 pinned shader effects) appear best first
  in the preview selector and terminal list as [1]-[17], in the CRT Choices
  (11 looks) and then Main Catalog (5 looks) groups, each with its one-line
  description and rough cost (light, medium or heavy). Verify the Choose line
  reads `[1-17] Select profile
  [U] Use selected profile  [N] Skip ReShade -- no changes  [R] Reopen preview
  [B] Back  [D] Details`. No profile needs HDR: verify no HDR group appears,
  with Windows HDR on or off. Verify every profile except Original shows a
  visible difference in the preview and that the Crisp 3D notes say the edge
  smoothing is not visible on the still picture.
- Select profiles directly in the preview and by terminal number; verify both
  inputs synchronize the selected name, description, technique list, and
  bundled-image approximation.
- Verify the wording identifies a preview approximation using the bundled
  image, says no game or shader execution occurs, and says actual results may
  vary.
- Verify the gallery opens non-modally. The 0-100 TrackBar remains responsive
  to drag and keyboard input after profile selection; profile changes do not
  change its value or view mode.
- Type `U` after changing the preview selection while terminal input pumps
  WinForms events; verify the latest preview profile is accepted, deployment
  still requires explicit confirmation, and the gallery closes automatically
  when the chooser returns. Verify the terminal remains usable after the
  gallery is closed or unavailable.

### 5. Library Health Check path repair

- Use broken-path fixtures or real broken paths.
- Verify broken-path mode does not show unrelated setup choices.
- Verify automatic search precedes manual browse, candidates are displayed
  before saving, backups are created only before applying, and no save occurs
  without confirmation.
- Verify no-match offers manual executable selection and source re-copy or
  re-extraction.

### 6. Feature workflow routing

- Verify GPU Fix, dgVoodoo2, ReShade, BepInEx, FFB, and required patches skip
  broken paths safely and route to option 13, Library Health Check.
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

Pester remains the home for pure logic and source contracts. Dedicated test-PC
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

### Level 1 - Development Certified
Fast developer validation.

### Level 2 - Beta Certified
Adds human-use simulation and real-install validation.

### Level 3 - Release Candidate Certified
Adds adversarial, mutation, fuzz, performance, and security validation.

### Level 4 - Gold Certified
Full certification including long-duration, scale, and stress testing.

## Required Artifacts

A normal certification run (`scripts\Run-TPM-Tests.ps1`, `scripts\Run-TPM-Certification-Suite.bat`) writes these files into its report folder:

- `Pester-result-v1.json`, `Pester-summary.json`, `Pester-NUnit.xml` and `Pester-Failures.txt` (Pester results, with the skipped count)
- `PSScriptAnalyzer.json` (static analysis results)
- `InstallHealth\InstallHealth.md` and `InstallHealth.json`, plus `InstallHealth-console.txt` (the Install Health report)
- `TechnicalLogs\` (the output of each helper process, such as the Pester child)
- the screenshots and rendered menu captures for the evidence slots

The signed outcome files (`TPM-Certification-Scorecard`, `TPM-Validation-Report`, the eligibility, final outcome, manifest and commit files, `.md` and `.json`) are written only by the publication step. A certification run never starts that step (see "Certification-only boundary" below), so it does not produce them.

## Running Certification

Certification evidence must identify one frozen GitHub branch and exact
commit SHA. Use a local checkout of the repository on the machine that
runs the certification; do not use a NAS, SMB share, mapped drive, or UNC
Git worktree as source authority.

`Sync-And-Run.bat` is a convenience launcher for manual latest-main
testing. It may fetch `origin/main` on a local `main` checkout, but it is
not an exact-SHA certification handoff, package identity proof, or release
gate.

For a test-PC certification pass, check out the handed-off SHA in a local
path and run `scripts\Run-TPM-Certification-Suite.bat` or
`scripts\Run-TPM-Tests.ps1` with the approved TeknoParrot runtime root
and local harness path, after opting in as described under "Real-data runs
are opt-in" below. The reviewer coordinates the resulting runtime and
hardware evidence from the same local checkout.

Before reporting a result, record the branch, remote branch SHA, local HEAD,
clean status, ancestry, CI result, runtime marker/containment result, tool
versions, and local report paths. A report copied to an artifact store after
the run must retain those source details.

For scripted or CI-style use, call `scripts\Run-TPM-Tests.ps1` directly
with `-TeknoParrotRoot` (see that script's parameters for `-RepoPath`,
`-HarnessRoot`, `-VerbosityLevel`, and `-PesterRegressionTimeoutSeconds`).

### Real-data runs are opt-in

Tests are fixture-only by default. Two things can read data that belongs to the
person running them, and both start only when that person asks on purpose:

- **The real-instance harness** (`scripts\Invoke-TPM-RealInstanceSmoke.ps1`,
  started by `scripts\Run-TPM-Tests.ps1` and by
  `scripts\Run-TPM-Certification-Suite.bat`). It reads the TeknoParrot folder
  it is given and copies profile files from it into the report. Both the
  wrapper and the harness refuse to start, before they read, probe or create
  anything, unless `TPM_REAL_DATA_TESTS` is exactly `1` for that run. The
  launcher has no default TeknoParrot folder: name it as the second argument
  or in `TPM_TEKNOPARROT_ROOT`. Running the product itself against that folder
  (`-RunUnattendedTPM`) is a separate opt-in.
- **The real CPS3 source test** (last `Describe` in
  `Tests\TpmCps3Supplementary.Tests.ps1`). It has its own, separate opt-in: it
  runs only when `TPM_REAL_SOURCE_TESTS` is exactly `1` and
  `TPM_CPS3_REAL_SOURCE` points at a folder or `.zip` you own.
  `TPM_REAL_DATA_TESTS=1` does not start it, and a `TPM_CPS3_REAL_SOURCE` that
  is only inherited from the environment does nothing. The test reads the
  source, installs into a disposable TestDrive folder, and fails if the source
  was added to, removed from, rewritten or unreadable (`Get-TpmSourceStamp`
  compares a hash of every file). It never writes to the source.

The certification run clears `TPM_REAL_DATA_TESTS`, `TPM_REAL_SOURCE_TESTS` and
`TPM_CPS3_REAL_SOURCE` for its Pester child, so a certification run never reads
a real source. A program cannot tell a value you set on purpose from one that
an earlier shell left behind, which is why the real-source test has its own
variable and why you unset everything afterwards.

`Tests\TpmRealDataOptIn.ps1` holds the shared rule (`Get-TpmRealDataSource`).
A new real-data test case must use it, so the rule stays in one place.
Select a real-data run like this, in the shell that starts the run.

For a certification run:

~~~powershell
$env:TPM_REAL_DATA_TESTS = '1'
~~~

For the CPS3 real-source test only:

~~~powershell
$env:TPM_REAL_SOURCE_TESTS = '1'
$env:TPM_CPS3_REAL_SOURCE = '<folder or .zip you own>'
~~~

Unset them afterwards. Ordinary and CI-style runs leave them unset and read
only synthetic fixtures.

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

The Pester regression gate runs in a separate PowerShell process
(`scripts\Invoke-TPM-PesterChild.ps1`), not on a thread of the harness. While
it runs:

- The wrapper prints `Certification is still running - hh:mm:ss elapsed` every
  30 seconds, and passes on the step lines (`[n/m] ...`), the `Pester totals:`
  line, the final status and the report paths. It writes no progress file.
- A configurable hard timeout (`-PesterRegressionTimeoutSeconds`, default
  1800s) stops the Pester process if it is ever exceeded. The harness then
  throws `Pester regression suite timed out after N seconds.`; that message is
  recorded as an `Unhandled validation error` check, and the run is not
  certified.
- The Pester child's own output goes to `TechnicalLogs\`, and the final results
  go to `Pester-result-v1.json`, `Pester-NUnit.xml`, `Pester-summary.json` and
  `Pester-Failures.txt`.

Skipped tests: some tests skip on purpose (they need an opt-in or an optional
tool such as 7-Zip), so a skipped test does not fail certification. The count
is shown on the Pester line of the score list (`skipped=N`), in the `Pester
totals:` line, in `Pester-summary.json`, and as a yellow line on the console
when it is above zero. The names of the skipped tests are in `Pester-NUnit.xml`.

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
against `main`. It is fast and needs no real TeknoParrot install. It runs
ASCII/parse checks on `TeknoParrot-Manager.ps1`, PSScriptAnalyzer against
that same file, the game-support and release-catalog checks, and 25 chosen
Pester files (the main and quality suites, the game-support, support-package,
certification and release-package suites, and the required-patch suites) --
not the whole `Tests/` folder. Its job is to catch an obviously broken commit
before it lands, in minutes.

**Full release certification** (`scripts/Run-TPM-Tests.ps1`, or
`scripts\Run-TPM-Certification-Suite.bat` started from a console window with
the opt-in and the TeknoParrot folder set first: it does nothing when you
double-click it, see "Real-data runs are opt-in" above) is
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
