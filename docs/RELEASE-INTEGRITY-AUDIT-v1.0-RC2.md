# Release Integrity Audit -- v1.0 RC2

Date: 2026-07-04

Status: NOT CLEAN YET. The release identity defects are fixed and issue #104
adaptive menu work has been ported into the corrected RC2 line, but production
script and certification-harness code changed after the certified
`15f3400e1f3d200c9df98a86605abff4fe419fe1` build. RC2 must be re-certified
before any replacement public asset is published.

## Scope

Audited runtime identity, release artifact identity, release metadata,
repository documentation, live GitHub wiki pages, updater/version behavior,
generated certification reports, and regression protection.

## Open Branch / PR Inventory

Open PR classification for corrected RC2:

| PR | Branch | Classification | Reason |
| --- | --- | --- | --- |
| #112 | `feature/issue-104-adaptive-menu-1.1` | Include in RC2 | Release Manager explicitly expanded RC2 scope to include the adaptive/professional menu unless unsafe unrelated work was found. Reviewed implementation commit touches menu rendering and tests only; docs commit touches matching docs. Ported by cherry-picking commits, not by merging branch sync commits. |
| #114 | `tooling/sync-and-run-launcher` | Abandon/close as stale | `Sync-And-Run.bat` already exists on `main` via commit `ef3fbda`. The open PR branch is stale/duplicative and not needed for RC2. |
| #110 | `docs/issue-109-cost-aware-testing` | Needs review | Useful process improvement, but it adds a PR template and testing policy language that overlaps the newly mandatory Release Integrity gate. Do not blindly fold into RC2 without reconciling policy wording. |
| #93 | `docs/mvri-roadmap-item` | Defer post-1.0 | Roadmap/planning item, not release-critical and not needed for RC2 external testing. |
| #60 | `docs/constitution-and-coordination-standard` | Needs review / likely superseded | Main already contains `CONSTITUTION.md`; branch is old governance work that may conflict with current release-governance text. Review separately after 1.0 unless a concrete blocker is found. |
| #58 | `docs/project-identity-standard` | Defer / needs review | Project identity standard was previously called out as needing intentional review before adoption. Not required for RC2 product testing. |
| #57 | `docs/release-candidate-checklist` | Needs review / likely superseded | New Release Integrity Audit section in `RELEASE-SAFETY-CHECKLIST.md` covers the current gate. Old checklist branch should be reconciled later rather than merged blindly. |
| #56 | `feature/updater-sha256-verification` | Defer post-1.0 | Valuable updater hardening, but PR itself says "Not a blocker for 1.0" and it adds new updater behavior. Keep out of RC2 unless separately authorized and re-certified. |

Notable unmerged/non-PR branches:

- `feature/issue-85-tier1-bios-detection`, issue #88 phase branches, DAT UX
  branches, certification provenance branches, and updater RC-tag fixes have
  already shipped to `main` through merged PRs in the current cycle.
- `review/issue-80-normalization` has divergent local/remote history but issue
  #80 golden cases are covered on `main`; do not merge blindly.
- Older release/docs/governance branches are either already represented on
  `main`, stale, or post-1.0 review material.

## Issue #104 Adaptive Menu Verification

- Issue #104 is still open.
- Branch `feature/issue-104-adaptive-menu-1.1` is still separate from `main`.
- PR #112 is open from `feature/issue-104-adaptive-menu-1.1` to `main` and is
  explicitly titled `[1.1, DO NOT MERGE YET]`.
- PR #112 body and commit `b91af37f828f8f42511db59978908f049ab4ad39`
  originally stated the adaptive menu was deferred to Version 1.1 by the
  feature freeze.
- The Release Manager later expanded/clarified RC2 scope: completed current
  1.0 testing-cycle work should be included unless unsafe, unrelated,
  incomplete, or explicitly post-1.0, and specifically directed that issue
  #104 / PR #112 be included in RC2 unless unsafe unrelated work was found.
- Commit `15f3400e1f3d200c9df98a86605abff4fe419fe1` was expected to contain
  the classic menu at the time it was certified. Under the revised RC2 scope,
  corrected RC2 must contain the adaptive/professional menu.
- Missing adaptive menu behavior in the invalid `15f3400` RC2 asset was not a
  packaging regression; it was a scope decision that has now been superseded.

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
- Issue #104 / PR #112 adaptive menu implementation was ported into the
  corrected RC2 line by cherry-picking the reviewed implementation and docs
  commits (`b91af37f828f8f42511db59978908f049ab4ad39` and
  `c5a9f6a262d01219d4800852b7d96c0135556cb3`) without the branch merge
  commits.

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
  currently published packaged runtime is not.

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
- Historical PR #112 text still records its original 1.1 deferral. That was
  true when written, but has been superseded by the Release Manager's explicit
  RC2 scope clarification.

## Required Before Replacement RC2 Publication

1. Run full local quality gates.
2. Rebuild RC2 ZIP from the corrected commit.
3. Validate local ZIP with `Tests/Test-ReleasePackage.ps1`.
4. Extract the ZIP and confirm the startup banner displays `TeknoParrot Manager
   v1.0 RC2`.
5. Confirm extracted ZIP includes the adaptive/professional menu.
6. Run real-machine certification against the corrected commit because
   production script and certification harness changed.
7. Publish only after downloaded GitHub asset validation passes.
8. Resolve immutable-release handling: delete/recreate `v1.0-RC2` with explicit
   authorization, or use a new replacement tag/release.
