# TPM Remediation Slice Contract

## 1. Slice name

- Name: LaunchBox direct-write partial-save reporting
- Contract ID: TPM-RC8-LANE-F-337
- Issue/PR: #337

## 2. Owner report IDs included

- IDs: #337
- Exact owner-visible failures: the LaunchBox setup flow reports "did not complete ... No changes were made" after the save step has already started writing LaunchBox files (Emulators.xml, Platforms.xml, or a platform file), so the user is told nothing changed when the library may be partly modified.

## 3. Explicit exclusions

- Owner IDs not included: #335, #336, #364, and all others.
- Features, modules, package, runtime, and release actions excluded: no rollback of written files, no new restore flow, no change to pre-save refusal paths, no change to backup or readback logic.

## 4. Behavior contract

- Current failure: `Invoke-LaunchBoxDirectWrite` returns `$null` from its save catch (30481-30486 in ba54ae5) even after a save has started. The caller (36778-36780) treats `$null` as "no changes were made".
- Expected behavior: each file path is recorded in `AttemptedPaths` before its `Save-Xml` call. The save catch returns `@{ Failed = $true; AttemptedPaths; BackupPath }`. The caller reports a possible partial update with the backup path when `AttemptedPaths` is non-empty, and keeps "No changes were made" only for refusals before any save.
- Forbidden regressions: success output and return shape (`Results`, `BackupPath`) unchanged; pre-save `return $null` paths unchanged; no new prompts.
- Design boundaries and deliberate exclusions: no rollback of written files. Recovery is the existing backup restore, as the success message already states.

## 5. Source/function ownership

- Files: TeknoParrot-Manager.ps1
- Functions/regions: `Invoke-LaunchBoxDirectWrite` save block (30475-30486 in ba54ae5); LaunchBox setup caller (36778-36780).
- Owning subsystem: LaunchBox integration.

## 6. Tests required before implementation

- Focused failing or characterization tests: none run (owner hold on tests; static review only).
- Source/inventory checks: confirm the single caller at 36778 and no other reader of the `$null` result.

## 7. Tests required after implementation

- Focused behavior tests: a save failure after the first save attempt must report a possible partial update and the backup path.
- Regression suite: Tests\TeknoParrot-Manager.Tests.ps1 (run by main agent).
- Static and procedure gates: ASCII check, parse check, PSScriptAnalyzer with PSScriptAnalyzerSettings.psd1.

## 8. Documentation/report updates required

- Control board row: docs\remediation\PR-321-control-board.md (main agent).
- Remediation report row: docs\remediation\RC8-BLOCKER-RECONCILIATION-LANE-F.md.
- Hunk classification: defect fix, bounded to the save catch and one caller branch.
- Changelog or user docs, if applicable: main agent decides at release time.

## 9. Permanent procedure IDs affected

- IDs and evidence: none identified in this lane.

## 10. Runtime smoke checklist

- Exact packaged behavior: not run (owner hold).
- Required source/package identity: not applicable in this lane.
- Evidence artifacts: none.
- Owner/runtime authorization: required before any runtime check.

## 11. Stop condition

Stop when the save catch returns the failure object, the caller branches on it, and both edited regions are read back. Do not widen scope to #335, #336, or #364.

## 12. Forbidden actions

No unrelated cleanup, broad rewrite, commit, push, package, release, certification, wiki update, test-PC work, or owner smoke unless separately authorized.

## 13. Commit/package authorization status

- Commit authorized: No, explicit authorization required
- Package authorized: No, explicit authorization required
- Release/certification authorized: No, explicit authorization required
