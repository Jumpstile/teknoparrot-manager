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

## Guiding Principle

Passing tests does not automatically certify a build. Certification requires all applicable quality gates to pass.
