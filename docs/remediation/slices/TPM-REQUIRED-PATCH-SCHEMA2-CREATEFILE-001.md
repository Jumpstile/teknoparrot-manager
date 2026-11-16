# TPM Remediation Slice Contract

## 1. Slice name

- Name: Schema-2 CreateFile planner precondition correction.
- Contract ID: TPM-REQUIRED-PATCH-SCHEMA2-CREATEFILE-001.
- Issue/PR: Issue #351 under TPM-REQUIRED-PATCHES-REVIEW-001. No numbered PR #321 owner-report row is assigned.

## 2. Owner report IDs included

- IDs: Issue #351, the existing owner-authorized required-patch issue. No PR #321 owner-report status changes.
- Exact finding: Schema-2 CreateFile requires Type, Target, BeforeState, AfterSha256, Payload, and PayloadSha256; it intentionally has no BeforeSha256. Get-TpmPatchPlan nevertheless reads BeforeSha256 unconditionally in its before/after no-op comparison. Under strict mode, that missing-property read can make the valid absent-only plan unavailable. The existing schema-2 compatibility case expects Ready. The historical Pester receipt A06AB583CD1045A6D50262DDFF78B2D385E55FAF9FAA807BEE0381F59A30CF94 contains one Ready-to-Unavailable result mapped to this case by the existing failure-cluster review, but it does not retain Plan.Reason and is not post-change evidence.
- Candidate before identities: engine E84EDEBF9374E4210FF4088A44346F72D474873CC9BA7A800BEAB290B2C37146; central test file 8A2325145135E3797FECB7855B914075D2135F7625EC02BAAC7A1D4D6E36E21C; architecture B0FD7D6DB9063D1141AA3E2AE6569E961E037D529920B89E44AED28304C728F5.

## 3. Explicit exclusions

- No new capability or catalog-contract change is introduced; this correction restores the already-defined schema-2 CreateFile planning behavior. No other user-facing behavior changes are intended. Recipe/catalog content, release behavior, operation types, receipts, apply/undo flows, transactions, and packages remain outside the scope of change.
- No schema-3 validation changes, ZIP/source guard investigation, variant-resolution changes, runtime access, owner handoff, or PR #321 owner-report status change.
- No execution of tests, parse checks, analyzer, permanent quality gate, Git, registry/CIM, build, package, release, or publication.

## 4. Behavior contract

- Current failure: the schema-1/2 operation validator selects BeforeState for schema-2 CreateFile, then the common no-op expression reads BeforeSha256 even when the operation is CreateFile.
- Expected behavior: compare BeforeSha256 with AfterSha256 only for ReplaceFile. Preserve the existing CreateFile requirements that BeforeState is exactly Absent, hashes are valid, AfterSha256 equals PayloadSha256, and only an absent target or exact already-applied target is accepted.
- Forbidden regressions: do not weaken hash validation, unknown or missing field rejection, exact replacement no-op rejection, path containment, parent-existence, target-state, or schema compatibility guards.
- Design boundary: this is a validator correction for an existing schema-2 operation shape, not a new operation or capability.

## 5. Source/function ownership

- Files: scripts/TpmRequiredPatchEngine.ps1, Tests/TeknoParrot-Manager.Tests.ps1, ARCHITECTURE.md, docs/remediation/slices/README.md, docs/remediation/PR-321-control-board.md, docs/remediation/PR-321-reconciliation.md, docs/remediation/inventories/TPM-REQUIRED-PATCHES-NATIVE-INVARIANTS-001.md, this contract, and the paired operation inventory.
- Functions/regions: Get-TpmPatchPlan operation validation and focused actual-planner cases.
- Owning subsystem: Issue #351 required-patch catalog under TPM-REQUIRED-PATCHES-REVIEW-001.

## 6. Tests required before implementation

- Characterization: retain the existing schema-1 replacement/schema-2 absent-file planner case and add the five cases listed below before changing the engine guard in this slice.
- Baseline execution: not run in this task under the explicit no-tests constraint. The saved historical full-suite receipt is context only, not a baseline for this edit.

## 7. Tests required after implementation

- TPM-CAT-OP-001: schema-2 CreateFile without BeforeSha256 returns Ready under strict mode.
- TPM-CAT-OP-002: non-Absent CreateFile pre-state returns Unavailable with the explicit pre-state reason.
- TPM-CAT-OP-003: mismatched CreateFile after and payload hashes return Unavailable under strict mode.
- TPM-CAT-OP-004: ReplaceFile without BeforeSha256 is rejected.
- TPM-CAT-OP-005: equal ReplaceFile before/after hashes are rejected.
- Pester, ASCII, parse, configured PSScriptAnalyzer, full manual scan, and the permanent quality gate remain required for later review/commit authorization. None was run in this task. No owner-runtime proof is claimed.

## 8. Documentation/report updates required

- Control board: add this bounded Issue #351 follow-up with verification pending; do not alter PR #321 owner-report status.
- Remediation report: record exact before/after hashes, the guard and test scope, and that verification was not run.
- Hunk mapping: engine guard, five planner cases, architecture note, inventory, and mapping updates -> Issue #351 / this contract / TPM-TRACE-001 / TPM-EVIDENCE-001 / TPM-TRUTH-001.
- Changelog, release version, and user docs: no change; existing required behavior is restored without adding a capability.

## 9. Permanent procedure IDs affected

- TPM-TRACE-001: map each source, test, and documentation hunk to Issue #351 and this contract.
- TPM-EVIDENCE-001: preserve exact candidate source, test, and mapping hashes; do not claim unrun results.
- TPM-TRUTH-001: distinguish historical suite evidence from current verification and owner-runtime proof.

## 10. Runtime smoke checklist

- Exact packaged behavior: not checked.
- Required source/package identity: isolated RC8 candidate only; no package or installed game was accessed.
- Evidence artifacts: source/test before and after hashes and the reviewable scoped changes.
- Owner/runtime authorization: no runtime or owner-handoff action is part of this slice.

## 11. Stop condition

Stop after the guard, five actual-planner cases, architecture note, focused inventory, and Issue #351 board/report/slice mappings are reviewable. Verification remains pending; no commit, package, release, or owner handoff is authorized.

## 12. Forbidden actions

No tests or static gates in this task, registry/CIM, live runtime, catalog expansion, unrelated remediation, Git action, commit, push, package, release, wiki update, or owner smoke.

## 13. Commit/package authorization status

- Commit authorized: No.
- Package authorized: No.
- Release/certification authorized: No.
- Local verification status: not run by explicit task constraint.