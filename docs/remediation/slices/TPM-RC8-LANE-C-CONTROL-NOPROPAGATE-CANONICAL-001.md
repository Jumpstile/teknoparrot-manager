# TPM Remediation Slice Contract

## 1. Slice name

- Name: RC8 lane C -- canonical Input API correction honors the noPropagate exclusion
- Contract ID: TPM-RC8-LANE-C-CONTROL-NOPROPAGATE-CANONICAL-001
- Issue/PR: #333 (related #300, PR #321)

## 2. Owner report IDs included

- IDs: F03 (as labeled in issue #333; priority P2). Nearest control-board row: 30 (Controls truthfulness).
- Exact owner-visible failures: a profile listed in the propagation exclusion list (`noPropagate`) is still rewritten by the designated canonical archetype Input API correction.

## 3. Explicit exclusions

- Owner IDs not included: all other control-propagation findings and the propagation report wording.
- Features, modules, package, runtime, and release actions excluded: no new exclusion UI, no new report status rows, no change to the propagation algorithm for non-excluded profiles, no packaging, no owner-runtime smoke.

## 4. Behavior contract

- Current failure: in `Invoke-ControlPropagationLegacy`, the canonical-correction branch runs for any archetype profile before the `noPropagate` guard, so an excluded archetype can be saved with a corrected Input API.
- Expected behavior: an excluded profile is never mutated by canonical correction (no save, no pool mutation, no report row). Non-excluded archetype profiles behave exactly as before.
- Forbidden regressions: excluded profiles changed on disk in any mode; dry-run output changed for non-excluded profiles; new `skipped-override` rows added for excluded archetypes; the excluded profile removed from the source pool used by other profiles.
- Design boundaries and deliberate exclusions: the excluded profile still serves as a propagation source for other profiles, as it did before. Only mutation is blocked.

## 5. Source/function ownership

- Files: `TeknoParrot-Manager.ps1` (lane C worktree only).
- Functions/regions: `Invoke-ControlPropagationLegacy`, canonical-correction branch (condition on the `$sourcePaths.ContainsKey($f.FullName)` block that starts the `$selfEntry` check).
- Owning subsystem: control propagation (controls truthfulness).

## 6. Tests required before implementation

- Focused failing-before case: a canonical archetype listed in `noPropagate` whose Input API differs from the canonical value. Assert that its file bytes are unchanged after `Invoke-ControlPropagation` (fails on the unfixed base).
- Characterization case: the same scenario without `noPropagate` still applies the canonical correction and reports `api-fixed-canonical`.
- Lane note: per the lane assignment, no tests were authored or run in lane C. Main must add and run these.

## 7. Tests required after implementation

- Focused behavior tests: excluded archetype unchanged in normal and dry-run modes; non-excluded archetype corrected as before.
- Regression suite: `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1`.
- Static and procedure gates: ASCII byte check, parse check, configured PSScriptAnalyzer, permanent procedure gate with the remediation report.

## 8. Documentation/report updates required

- Control board row: section appended to `docs/remediation/PR-321-control-board.md` (RC8 lane C follow-up), mapped to F03 and row 30.
- Remediation report row: section appended to `docs/remediation/PR-321-reconciliation.md`.
- Hunk classification: the single changed condition maps to #333 / this contract / TPM-TRACE-001.
- Changelog or user docs: not updated in lane C.

## 9. Permanent procedure IDs affected

- IDs and evidence: TPM-TRACE-001, TPM-EVIDENCE-001. Evidence is pending Main verification.

## 10. Runtime smoke checklist

- Exact packaged behavior: after propagation from the canonical archetype, a `noPropagate` profile's files are byte-identical to before.
- Required source/package identity: the RC8 candidate source identity recorded by the integration owner.
- Evidence artifacts: before/after file hashes for the excluded profile.
- Owner/runtime authorization: required; not run by lane C.

## 11. Stop condition

Stop when the contract's focused tests, report status, hunk mapping, and required gate evidence are complete. Do not widen scope to unrelated findings.

## 12. Forbidden actions

No unrelated cleanup, broad rewrite, commit, push, package, release, certification, wiki update, test-PC work, or owner smoke unless separately authorized.

## 13. Commit/package authorization status

- Commit authorized: No / Yes, explicit authorization required
- Package authorized: No / Yes, explicit authorization required
- Release/certification authorized: No / Yes, explicit authorization required
