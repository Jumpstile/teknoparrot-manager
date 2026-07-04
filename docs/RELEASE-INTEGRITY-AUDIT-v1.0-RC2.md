# Release Integrity Audit -- v1.0 RC2

Date: 2026-07-04

Status: NOT CLEAN YET. The release identity defects are fixed in the working
tree, but production script and certification-harness code changed after the
certified `15f3400e1f3d200c9df98a86605abff4fe419fe1` build. RC2 must be
re-certified before any replacement public asset is published.

## Scope

Audited runtime identity, release artifact identity, release metadata,
repository documentation, live GitHub wiki pages, updater/version behavior,
generated certification reports, and regression protection.

## Issue #104 Adaptive Menu Verification

- Issue #104 is still open.
- Branch `feature/issue-104-adaptive-menu-1.1` is still separate from `main`.
- PR #112 is open from `feature/issue-104-adaptive-menu-1.1` to `main` and is
  explicitly titled `[1.1, DO NOT MERGE YET]`.
- PR #112 body and commit `b91af37f828f8f42511db59978908f049ab4ad39`
  explicitly state the adaptive menu is real new-capability work deferred to
  Version 1.1 by the feature freeze.
- Commit `15f3400e1f3d200c9df98a86605abff4fe419fe1` is therefore expected to
  contain the classic menu.
- Missing adaptive menu behavior in RC2 is not an RC2 regression.
- Stale metadata remains on issue #104 itself: labels/milestone still include
  `release-blocker`, `rc2-required`, and `RC2`. That issue-tracker metadata
  conflicts with PR #112's explicit 1.1 deferral and should be cleaned up
  separately before final 1.0 governance review.

## Runtime Version Discrepancy Root Cause

Downloaded GitHub asset `TeknoParrot.Manager.v1.0.RC2.zip` was extracted and
inspected. Its packaged `TeknoParrot-Manager.ps1` has:

- Header: `# TeknoParrot Manager  |  v1.0 RC1`
- `$ScriptVersion = "1.0"`
- Banner line: `Write-Host "       TeknoParrot Manager  v$ScriptVersion RC1"`

The same three lines exist in commit
`15f3400e1f3d200c9df98a86605abff4fe419fe1`. The release asset was therefore
built from the certified commit, but the certified commit itself still carried
the stale RC1 display label. Structural ZIP validation passed because it only
checked package contents, not packaged runtime identity.

The GitHub Release title, tag, and asset name said RC2; the packaged runtime
said RC1. That made the published RC2 asset invalid.

## Corrections Made

- `TeknoParrot-Manager.ps1`: header now says `v1.0 RC2`; added
  `$ReleaseCandidateLabel = "RC2"` and `$DisplayVersion = "v$ScriptVersion
  $ReleaseCandidateLabel"`; startup banner now renders `$DisplayVersion`
  instead of a hardcoded `RC1` suffix.
- `Tests/Test-ReleasePackage.ps1`: release package validation now checks the
  packaged script header, release-candidate label, display-version banner
  source, and rejects the stale RC1 banner.
- `Tests/QualitySystem.Tests.ps1`: added source-level Release Integrity checks
  for script identity, README latest tag, release-facing docs, and the
  mandatory Release Integrity Audit gate.
- `Tests/TeknoParrot-Manager.Tests.ps1` and
  `Tests/TpmAutoUpdate.Core.Tests.ps1`: updater version parsing now includes
  the current `v1.0-RC2` tag in addition to historical `v1.0-RC1` regression
  coverage.
- `scripts/Invoke-TPM-RealInstanceSmoke.ps1`: certification scorecards and
  Markdown reports now include `TpmDisplayVersion` / "TPM display version" in
  addition to numeric `$ScriptVersion`.
- `Tests/TPMCertificationHarness.Tests.ps1`: provenance test now covers
  `TpmDisplayVersion`.
- `README.md`, `TeknoParrot-Manager-README.txt`,
  `TeknoParrot-Manager-QuickStart.txt`, `TeknoParrot-Manager-CHANGELOG.txt`,
  and `AGENTS.md`: current release identity updated to RC2.
- `QUICKSTART.md`: corrected stale ReShade guidance; ReShade DLLs are not
  bundled in the ZIP release.
- `docs/AUTO_UPDATE.md`: corrected the safety model to describe the current
  quiet startup check accurately while preserving the no-silent-install rule.
- `RELEASE-SAFETY-CHECKLIST.md`: added mandatory Release Integrity Audit
  phases for every public release and renumbered later sections.
- `docs/TPM-CERTIFICATION-SUITE.md` and
  `docs/CROSS-PROJECT-CERTIFICATION-SUITE-PORTABILITY.md`: documented Release
  Integrity as mandatory alongside Certification.
- `docs/wiki-updates/Changelog.md`: added RC2 release-integrity entry.
- Live wiki updated and pushed at wiki commit
  `c6fd2fb Update RC2 release integrity wiki pages`.

## Repository Files Reviewed

- `AGENTS.md`
- `ARCHITECTURE.md`
- `CLAUDE.md` (ignored local file, reviewed but not tracked)
- `CONSTITUTION.md`
- `LESSONS_LEARNED.md`
- `QUICKSTART.md`
- `README.md`
- `RELEASE-SAFETY-CHECKLIST.md`
- `SECURITY.md`
- `forum-post-beta-testing.txt` (ignored local file, reviewed but not tracked)
- `TeknoParrot-Manager.ps1`
- `TeknoParrot-Manager.bat`
- `Sync-And-Run.bat`
- `TeknoParrot-Manager-README.txt`
- `TeknoParrot-Manager-QuickStart.txt`
- `TeknoParrot-Manager-CHANGELOG.txt`
- `.github/ISSUE_TEMPLATE/tpm-test-report.md`
- `docs/ADVERSARIAL-TESTING-PLAN.md`
- `docs/AUTO_UPDATE.md`
- `docs/Compatibility.md`
- `docs/CROSS-PROJECT-CERTIFICATION-SUITE-PORTABILITY.md`
- `docs/HUMAN-USE-SIMULATION-PLAN.md`
- `docs/REGRESSION_MATRIX.md`
- `docs/REGRESSION-REGISTER.md`
- `docs/Setting-Up-Automated-Testing-for-TeknoParrot-Manager.md`
- `docs/TPM-CERTIFICATION-SUITE.md`
- `docs/wiki-updates/AutoSync.md`
- `docs/wiki-updates/Changelog.md`
- `docs/wiki-updates/Check-for-Updates.md`
- `docs/wiki-updates/Release-Notes-v0.99.44.md`
- `scripts/Invoke-TPM-RealInstanceSmoke.ps1`
- `scripts/Run-TPM-Certification-Suite.bat`
- `scripts/Run-TPM-Tests.ps1`
- `tools/Invoke-TpmAutoUpdate.ps1`
- `tools/TpmAutoUpdate.Core.psm1`
- `Tests/*.ps1`

`CONTRIBUTING.md`, `PROJECT_OVERVIEW.md`, and `RELEASE-NOTES.md` are not
present in this repository.

## Wiki Pages Reviewed

- `_Sidebar.md`
- `AutoSync.md`
- `BepInEx.md`
- `Changelog.md` -- updated
- `Check-for-Updates.md`
- `Crosshairs.md`
- `dgVoodoo2.md`
- `FFB-Setup.md`
- `GPU-Fix.md`
- `Health-Check.md`
- `Home.md` -- updated
- `Postgres-Setup.md`
- `Propagate-Controls.md`
- `Quick-Start.md` -- updated
- `Register.md`
- `ReShade.md` -- updated
- `Restore-Backup.md`
- `Setup.md`
- `Troubleshooting.md`

## Release Artifact Audit

Published asset inspected:

- Release: `v1.0-RC2`
- Asset: `TeknoParrot.Manager.v1.0.RC2.zip`
- Size: `4,761,723` bytes
- Asset digest reported by GitHub: `sha256:cbc60a9005f735ac4efa6e5d28a44b38be5051210bf6cc928def0d2e851a35f2`
- Extracted packaged script SHA256:
  `D90C481ADA95C3CD1849485ADE04898FAC04895423D9DF053B67D9E4D31FCC14`
- Result: INVALID. Runtime identity says RC1.

GitHub marks the published RC2 release immutable. Attempts to move it back to
draft and to delete the invalid asset were rejected by GitHub. Replacing the
public artifact requires either explicit authorization to delete/recreate the
immutable release/tag, or publication under a new tag after re-certification.

## Release Metadata Audit

- GitHub release tag: `v1.0-RC2`
- GitHub release title: `TeknoParrot Manager v1.0 RC2`
- GitHub release target: `15f3400e1f3d200c9df98a86605abff4fe419fe1`
- GitHub latest endpoint: `v1.0-RC2`
- Metadata result: GitHub metadata is internally RC2-consistent, but the
  packaged runtime is not.

## Remaining Intentional Discrepancies

- `$ScriptVersion` remains `1.0` by design. Release-candidate identity is now
  represented by `$ReleaseCandidateLabel` / `$DisplayVersion`; updater
  comparison treats `v1.0-RC2` as numeric base `1.0`, so an already-running
  1.0 release candidate is not offered the same release as an update.
- Historical test comments and test cases still reference `v1.0-RC1` because
  issue #105 was specifically caused by the real RC1 release tag. These are
  regression history, not current release identity.
- Historical changelog entries remain historical. The current release identity
  is represented by the new RC2 entry.
- Issue #104 tracker labels/milestone still imply RC2-required, but branch and
  PR evidence show adaptive menu work is intentionally deferred to 1.1.

## Required Before Replacement RC2 Publication

1. Run full local quality gates.
2. Rebuild RC2 ZIP from the corrected commit.
3. Validate local ZIP with `Tests/Test-ReleasePackage.ps1`.
4. Extract the ZIP and confirm the startup banner displays `TeknoParrot Manager
   v1.0 RC2`.
5. Run real-machine certification against the corrected commit because
   production script and certification harness changed.
6. Publish only after downloaded GitHub asset validation passes.
7. Resolve immutable-release handling: delete/recreate `v1.0-RC2` with explicit
   authorization, or use a new replacement tag/release.
