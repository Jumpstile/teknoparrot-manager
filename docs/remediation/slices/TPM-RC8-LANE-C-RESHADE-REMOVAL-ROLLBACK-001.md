# TPM Remediation Slice Contract

## 1. Slice name

- Name: RC8 lane C -- ReShade removal rollback restores only entries it deleted and never overwrites a concurrent edit
- Contract ID: TPM-RC8-LANE-C-RESHADE-REMOVAL-ROLLBACK-001
- Issue/PR: #367 (related #348, #247, #323; PR #321)

## 2. Owner report IDs included

- IDs: no owner-table ID is assigned to #367 in the control board. Mapping is issue-level. Nearest row: 11 (ReShade protected ownership).
- Exact owner-visible failures: when a ReShade removal fails part-way, the rollback copies every backup entry back over its source path, including entries the removal refused to delete. A file edited concurrently in that location is overwritten by the stale backup.

## 3. Explicit exclusions

- Owner IDs not included: ReShade selection, preview, install, and protected-conflict policy.
- Features, modules, package, runtime, and release actions excluded: no change to which files are removable, no change to the ownership manifest format, no new removal scope, no packaging, no owner-runtime smoke.

## 4. Behavior contract

- Current failure: the rollback loop in `Remove-TpmReShadeOwnedDeployment` iterates all `$backups`, not the entries actually deleted, and copies over any existing destination.
- Expected behavior:
  - Only entries this run deleted (`$deletedBackups`, appended after each successful `Remove-Item`) are restored.
  - A deleted destination that reappeared with the expected hash is treated as already restored.
  - A deleted destination that reappeared with different content is never overwritten. It is recorded in `$conflicts` and `rollbackErrors`, the backups are kept, and the result status is `ManualRecoveryRequired` with the backup path in `Detail`.
  - The ownership manifest is restored only if this run wrote it (`$manifestMutated`).
  - `Invoke-TpmReShadeRemoval` counts `ManualRecoveryRequired` as a failure.
- Forbidden regressions: restoring over a file that differs from the expected hash; reporting `RolledBack` when any entry was left for manual recovery; deleting any file that was previously refused; removing backups on failure.
- Design boundaries and deliberate exclusions: the removal and its revalidation checks are unchanged. Only the rollback and its status reporting change.

## 5. Source/function ownership

- Files: `TeknoParrot-Manager.ps1` (lane C worktree only).
- Functions/regions:
  - `Remove-TpmReShadeOwnedDeployment`: declarations near `$backups`; deletion loop append; manifest mutation flag; catch-block rollback loop, manifest restore condition, state and detail; `$conflicts` declaration.
  - `Invoke-TpmReShadeRemoval`: `$failed` status filter.
- Owning subsystem: ReShade removal and ownership manifest.

## 6. Tests required before implementation

- Focused failing-before case: create a removal where the second entry fails revalidation after the first is deleted, with a third, never-deleted entry edited to new content during the run. Assert that the edited entry keeps its new content after rollback. Fails on the unfixed base because the rollback overwrites it.
- Focused failing-before case: a deleted entry reappears with different content before rollback. Assert no overwrite, status `ManualRecoveryRequired`, and backup path reported.
- Characterization: a clean removal still returns `Removed`; a failure with only deleted entries and unchanged state still returns `RolledBack`.
- Lane note: per the lane assignment, no tests were authored or run in lane C. Main must add and run these.

## 7. Tests required after implementation

- Focused behavior tests: the cases in Section 6 pass.
- Regression suite: `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1`.
- Static and procedure gates: ASCII byte check, parse check, configured PSScriptAnalyzer, permanent procedure gate with the remediation report.

## 8. Documentation/report updates required

- Control board row: section appended to `docs/remediation/PR-321-control-board.md` (RC8 lane C follow-up), mapped to #367 and row 11.
- Remediation report row: section appended to `docs/remediation/PR-321-reconciliation.md`.
- Hunk classification: the rollback, state, and summary hunks map to #367 / this contract / TPM-TRACE-001.
- Changelog or user docs: not updated in lane C.

## 9. Permanent procedure IDs affected

- IDs and evidence: TPM-TRACE-001, TPM-EVIDENCE-001, TPM-AUTH-001 (protected-ownership behavior). Evidence is pending Main verification.

## 10. Runtime smoke checklist

- Exact packaged behavior: a ReShade removal interrupted by a concurrent edit leaves the edited file's new content in place and reports manual recovery with the backup path.
- Required source/package identity: the RC8 candidate source identity recorded by the integration owner.
- Evidence artifacts: file hashes before and after, and the removal result object.
- Owner/runtime authorization: required; not run by lane C.

## 11. Stop condition

Stop when the contract's focused tests, report status, hunk mapping, and required gate evidence are complete. Do not widen scope to unrelated findings.

## 12. Forbidden actions

No unrelated cleanup, broad rewrite, commit, push, package, release, certification, wiki update, test-PC work, or owner smoke unless separately authorized.

## 13. Commit/package authorization status

- Commit authorized: No / Yes, explicit authorization required
- Package authorized: No / Yes, explicit authorization required
- Release/certification authorized: No / Yes, explicit authorization required
