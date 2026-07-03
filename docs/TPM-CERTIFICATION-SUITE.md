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

## Virtual Beta Tester (issue #88 phase 1)

Mission: the certification suite should meaningfully replace scarce human
beta testing, not just run tests. Phase 1 wires real, executable coverage
against production behavior -- `Tests/VirtualBetaTester.*.Tests.ps1` -- and
is reported as its own "Virtual Beta Tester coverage" gate in the
certification scorecard, not folded anonymously into the overall Pester
count.

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

Explicitly out of scope for phase 1 (tracked in issue #88 for later phases,
not implemented yet): broad fuzzing, long soak testing, mutation testing,
a full property-based framework, cross-project portability, a performance
trend system.

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

## Roadmap / Future Capabilities (not 1.0 milestones)

### Manual Verification Replacement Index (MVRI)

**Status: roadmap item only. Not part of the Version 1.0 release criteria.**

A future portfolio-level metric measuring how much manual beta testing
has been replaced by deterministic, evidence-based certification. MVRI
is not a correctness score or a release gate -- it is a planning and
maturity metric, answering: "How much of our release confidence comes
from repeatable automation instead of scarce human testing?"

Relationship to TVD (see `CONSTITUTION.md`, "Tester Value Density"):
Tester Value Density evaluates the value of an individual behavioral
test; MVRI would evaluate the overall maturity of the certification
suite as a whole.

Example dimensions such a metric might track coverage across: human
workflows automated, recovery scenarios automated, repeat-run/
idempotency behaviors automated, messy real-world environment scenarios
automated, startup/update decision paths automated, cancel/decline
safety behaviors automated -- reported as coverage counts or maturity
indicators, never as a percentage of software quality.

Guiding principle for if/when this is built: MVRI must encourage
replacing meaningful manual verification with deterministic, maintainable
automation, and must never incentivize adding low-value or brittle tests
simply to increase the metric. Future work on this item should be driven
by engineering evidence and real reductions in manual testing effort, not
by this roadmap entry's presence here.

## Guiding Principle

Passing tests does not automatically certify a build. Certification requires all applicable quality gates to pass.
