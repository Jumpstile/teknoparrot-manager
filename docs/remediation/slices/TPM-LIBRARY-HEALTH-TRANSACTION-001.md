# Library Health repair transaction outcome slice

## 1. Slice name

- Name: Truthful Library Health repair outcomes for mixed and no-change paths
- Contract ID: `TPM-LIBRARY-HEALTH-TRANSACTION-001`
- Issue/PR: PR #321

## 2. Owner report IDs included

- IDs: 21
- Exact owner-visible failure: automatic repair can return `SUCCEEDED` after fixing one profile while another affected profile remains unresolved, because the transaction adapter omits `not-found`, `no-exe-name`, `path-unsafe`, `not-reviewed`, and other non-fixed report states from its incomplete-item accounting. A valid library can also be reported as `FAILED_BEFORE_MUTATION` after a verified backup even when no path needs repair.

## 3. Explicit exclusions

- Owner IDs not included: 17, 18, 19, 20, 22; their affected-game scope, no-candidate explanation, scoped re-copy, Back routing, and post-thumbnail ordering remain separately evidenced.
- Features, modules, package, runtime, and release actions excluded: no new repair capability, no scope broadening, no backup format or bytes change, no change to candidate selection, path validation, write verification, rollback order, package build, runtime smoke, commit, push, merge, publication, or certification.

## 4. Behavior contract

- Current failure: `Repair-GamePaths` counts only a subset of unsuccessful report statuses as failed/skipped. A mixed repair can therefore be converted to `SUCCEEDED` although `Write-LibraryHealthRepairResults` reports `STILL BROKEN`. A no-change run can enter the mutation backup path before discovering that every profile is already valid.
- Expected behavior: run read-only candidate planning before backup; when all current paths are valid, return a verified `NO_OP` with current-state checks and no backup mutation. Before any profile write, retain the required verified backup and abort all writes if backup verification fails. `SUCCEEDED` requires every reported repair item to be fixed and verified. If at least one profile is fixed while any report remains failed, skipped, or unresolved, return `PARTIAL_APPLIED` with disjoint complete terminal item sets and `PARTIAL_KNOWN` state. If no profile changes and repair remains impossible, never return success; retain an attention-required pre-mutation outcome with the unresolved report codes.
- Forbidden regressions: no unverified path may be reported fixed; no changes to the affected profile whitelist, backup contents, reviewed-candidate selection, path containment/reparse checks, XML save/read-back, profile ordering, or optional-flow routing; no success outcome while any report is unresolved.
- Design boundaries and deliberate exclusions: the change is limited to Library Health automatic repair transaction planning/accounting. It does not change manual repair, the read-only Health Check, or the user's explicit decision to re-copy affected game archives.

## 5. Source/function ownership

- Files: `TeknoParrot-Manager.ps1`; `Tests/TeknoParrot-Manager.Tests.ps1`; `ARCHITECTURE.md`; `docs/governance/tpm-contract-types.md`; `docs/remediation/PR-321-control-board.md`; `docs/remediation/PR-321-reconciliation.md`; `docs/remediation/slices/PR-321-current-slice.md`.
- Functions/regions: `Repair-GamePaths`; `Repair-GamePathsLegacy`; `ConvertTo-TpmLegacyTransactionResult`; `Write-LibraryHealthRepairResults`.
- Owning subsystem: Library Health / typed profile transaction outcomes.

## 6. Tests required before implementation

- Focused failing or characterization tests: a fixture-backed mixed repair with one verified fixed profile and one unresolved `not-found` profile must reject `SUCCEEDED`; an all-valid fixture must require `NO_OP`, unchanged state, and no backup attempt. The existing failed-save and reviewed-candidate regressions must remain unchanged.
- Source/inventory checks: enumerate every `Repair-GamePathsLegacy` report status and map it to changed/completed/failed/skipped or current-state no-op handling.

## 7. Tests required after implementation

- Focused behavior tests: run the two characterization tests, existing Library Health one/multiple/zero-scope and reviewed-candidate tests, failed-save verification test, and the focused repair-flow regressions in PowerShell 7 and Windows PowerShell 5.1.
- Regression suite: full main and SupportPackage Pester suites under Pester 5.7.1; parser, ASCII, PSScriptAnalyzer, InjectionHunter, `git diff --check`, and permanent procedure gate.
- Static and procedure gates: `TPM-REPAIR-001`, `TPM-REPAIR-002`, `TPM-EVIDENCE-001`, `TPM-OWNER-002`, `TPM-OWNER-003`, and `TPM-TRACE-001`.

## 8. Documentation/report updates required

- Control board row: ID 21 and current blocker/next-slice queue.
- Remediation report row: canonical owner decision, focused test evidence, and source/runtime disposition.
- Hunk classification: PR #321 / owner ID 21 / `TPM-LIBRARY-HEALTH-TRANSACTION-001` / `TPM-REPAIR-001` / `TPM-REPAIR-002` / `TPM-EVIDENCE-001` / `TPM-OWNER-002` / `TPM-OWNER-003` / `TPM-TRACE-001`.
- Changelog or user docs, if applicable: no release-version change; update architecture and remediation evidence only.

## 9. Permanent procedure IDs affected

- `TPM-REPAIR-001`: preserve the one/multiple/zero affected-game boundary.
- `TPM-REPAIR-002`: preserve the no-unrelated-optional-flow boundary.
- `TPM-EVIDENCE-001`: fixture-backed behavior tests cover mixed and no-change outcomes.
- `TPM-OWNER-002` / `TPM-OWNER-003`: report source evidence and owner-runtime requirement without claiming package validation.
- `TPM-TRACE-001`: map every source/test hunk to this contract and PR #321 owner ID 21.

## 10. Runtime smoke checklist

- Exact packaged behavior: after an authorized rebuild, run Library Health repair against one fixable and one unresolved affected profile and against an all-valid library; verify truthful status, fixed/still-broken accounting, unchanged unaffected profiles, and no backup when no mutation is needed.
- Required source/package identity: exact reviewed source SHA and rebuilt package SHA must match.
- Evidence artifacts: operator-visible repair result, backup evidence for mutation cases, exact source/package identities, and owner-runtime record.
- Owner/runtime authorization: required and not granted by this slice; no package or owner smoke is authorized.

## 11. Stop condition

Stop when the behavior tests prove no false success, no-change outcome semantics satisfy the transaction contract, all listed procedure IDs and report/hunk mappings are current, and source-quality gates pass. Keep release certification blocked pending exact package and owner-runtime evidence.

## 12. Forbidden actions

No unrelated cleanup, broad rewrite, backup or rollback semantics change, package, runtime mutation, owner smoke, commit, push, merge, tag, publication, certification, wiki update, or ARCADE work.

## 13. Commit/package authorization status

- Commit authorized: No; explicit authorization required.
- Package authorized: No.
- Release/certification authorized: No.