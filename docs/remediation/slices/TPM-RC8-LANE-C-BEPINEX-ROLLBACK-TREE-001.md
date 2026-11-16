# TPM Remediation Slice Contract

## 1. Slice name

- Name: RC8 lane C -- BepInEx reset rollback restores exact originals and removes created directories
- Contract ID: TPM-RC8-LANE-C-BEPINEX-ROLLBACK-TREE-001
- Issue/PR: #366 (related #300, #348, #323; PR #321)

## 2. Owner report IDs included

- IDs: no owner-table ID is assigned to #366 in the control board. Mapping is issue-level. Nearest section: "Owner-Smoke Remediation Slice 1 -- BepInEx safety and rollback" (rollback failure is terminal; preserve evidence).
- Exact owner-visible failures:
  1. After a failure injected after the first promotion, the BepInEx rollback leaves created directories behind. Cause: the created-directory cleanup condition in `Invoke-TpmTransactionalTreePromote` puts `-and` outside the `Test-Path` parentheses, so `Test-Path` receives an `and` parameter and throws. The rollback error is recorded and the remaining cleanup is skipped.
  2. The reset rollback restores a backup into a surviving BepInEx directory, which nests the backup as `BepInEx\BepInEx`.

## 3. Explicit exclusions

- Owner IDs not included: all other BepInEx transaction, prompt, and architecture-detection findings.
- Features, modules, package, runtime, and release actions excluded: no change to package resolution, promotion order, the fail-closed verification, or the manual-recovery messaging; no packaging; no owner-runtime smoke.

## 4. Behavior contract

- Current failure: see Section 2.
- Expected behavior:
  - Created directories are removed when empty during promotion rollback, deepest first, and the rollback completes all remaining steps.
  - `Restore-BepInExUpdateBackup` clears the fixed BepInEx tree (through `Remove-BepInExFixedTree`, which keeps its reparse-point refusal) before copying the backup, so the restored tree equals the backup and is never nested.
  - Restore failure still sets `rollbackFailure` and preserves evidence.
- Forbidden regressions: deletion outside the fixed tree names; removal of non-empty directories; weakened reparse-point checks; a restore that reports success without `Test-BepInExBackupEntry` verification; changes to the promotion commit path.
- Design boundaries and deliberate exclusions: the restore relies on the reset having owned the fixed names, which the caller guarantees by only calling it when `resetApplied` is true.

## 5. Source/function ownership

- Files: `TeknoParrot-Manager.ps1` (lane C worktree only).
- Functions/regions:
  - `Restore-BepInExUpdateBackup` (clear before copy).
  - `Invoke-TpmTransactionalTreePromote`, created-directory rollback loop (condition at the `Test-Path` line).
- Owning subsystem: BepInEx update transaction and rollback.

## 6. Tests required before implementation

- Focused failing-before case: inject a failure after the first promotion; assert that created, empty directories are removed. Fails on the unfixed base because the rollback throws on the `-and` parameter.
- Focused failing-before case: restore a backup into a game root that still holds a BepInEx directory; assert the tree equals the backup and contains no `BepInEx\BepInEx` child. Fails on the unfixed base.
- Characterization: a reparse-point destination in the fixed tree is still refused.
- Lane note: per the lane assignment, no tests were authored or run in lane C. Main must add and run these.

## 7. Tests required after implementation

- Focused behavior tests: the two cases in Section 6 pass; the reparse refusal passes.
- Regression suite: `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1`.
- Static and procedure gates: ASCII byte check, parse check, configured PSScriptAnalyzer, permanent procedure gate with the remediation report.

## 8. Documentation/report updates required

- Control board row: section appended to `docs/remediation/PR-321-control-board.md` (RC8 lane C follow-up), mapped to #366 and the BepInEx rollback section.
- Remediation report row: section appended to `docs/remediation/PR-321-reconciliation.md`.
- Hunk classification: the two changed hunks map to #366 / this contract / TPM-TRACE-001.
- Changelog or user docs: not updated in lane C.

## 9. Permanent procedure IDs affected

- IDs and evidence: TPM-TRACE-001, TPM-EVIDENCE-001, TPM-OWNER-001 (owner runtime, not run). Evidence is pending Main verification.

## 10. Runtime smoke checklist

- Exact packaged behavior: a forced BepInEx repair failure after promotion leaves the game directory byte-identical to the pre-repair tree with no empty created directories.
- Required source/package identity: the RC8 candidate source identity recorded by the integration owner.
- Evidence artifacts: directory listing and hash comparison before and after the forced failure.
- Owner/runtime authorization: required; not run by lane C.

## 11. Stop condition

Stop when the contract's focused tests, report status, hunk mapping, and required gate evidence are complete. Do not widen scope to unrelated findings.

## 12. Forbidden actions

No unrelated cleanup, broad rewrite, commit, push, package, release, certification, wiki update, test-PC work, or owner smoke unless separately authorized.

## 13. Commit/package authorization status

- Commit authorized: No / Yes, explicit authorization required
- Package authorized: No / Yes, explicit authorization required
- Release/certification authorized: No / Yes, explicit authorization required
