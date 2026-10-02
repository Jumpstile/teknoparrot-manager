# TPM Remediation Slice Contract

## 1. Slice name

- Name: Fail-closed owner-report status classification
- Contract ID: `TPM-OWNER-STATUS-GATE-001`
- Issue/PR: PR #321; supporting owner report ID 3 without closing it

## 2. Owner report IDs included

- IDs: 3 (status semantics only; current Crosshairs discovery gap keeps the canonical status unresolved until source remediation and focused coverage close it)
- Exact owner-visible failure: the progress inventory was incomplete and the gate did not recognize the truthful remediation status. After the complete census and focused source coverage, the gate may accept `SOURCE FIXED; OWNER RUNTIME NEEDED` for ID 3 while continuing to block unresolved owner statuses and any explicitly `NOT FIXED` progress path.

## 3. Explicit exclusions

- Owner IDs not included: all other PR #321 IDs; ID 3 advances only after complete source census and focused coverage, and its owner-runtime requirement remains.
- Features, modules, package, runtime, and release actions excluded: no product behavior change, package build, runtime smoke, commit, push, merge, tag, publication, certification, or release authorization.

## 4. Behavior contract

- Baseline failure: `Test-TpmPermanentProcedures.ps1` recognized only four legacy statuses, read the earlier owner mapping instead of the declared canonical corrected table, did not compare canonical IDs with the control-board owner table (which now reaches ID 35), and rejected stale-package evidence unconditionally in source mode. Its whitelist also conflicted with the JSON registry, operating model, and report template.
- Expected behavior: derive allowed labels and dispositions from the registry, validate a one-to-one mapping, classify the canonical corrected-status column, require exact unique owner-ID set equality with the control-board table, and reject unresolved labels in source mode. An explicitly `NOT FIXED` path in the progress audit blocks source mode; absence of that disposition is valid when the completed census has no uncovered paths. Preserve the separate `-RequireOwnerRuntime` failure for `SOURCE FIXED; OWNER RUNTIME NEEDED`; certification requires an explicit current-candidate status of `VALIDATED` and must reject `NOT BUILT`, `STALE`, missing, or malformed current status. Historical stale-candidate prose must not override a current validated status.
- Forbidden regressions: promote any unresolved owner ID, read historical statuses as release decisions, omit/add/duplicate canonical IDs, pass an unresolved canonical status or `NOT FIXED` progress path, weaken the source/runtime distinction, allow unknown vocabulary, or block source gating solely because the candidate package is stale.
- Design boundaries and deliberate exclusions: `DEFERRED BY OWNER` remains a recognized owner disposition; this contract does not decide whether an owner deferral is appropriate for any ID. No product call site or runtime behavior changes.

## 5. Source/function ownership

- Files: `quality/permanent-procedures.json`; `scripts/Test-TpmPermanentProcedures.ps1`; `scripts/Run-TpmQualityGate.ps1`; `Tests/TeknoParrot-Manager.Tests.ps1`; `docs/governance/tpm-development-operating-model.md`; `docs/governance/permanent-procedures.md`; `docs/templates/remediation-gate-report.md`; `docs/remediation/PR-321-current-slice.md`; `docs/remediation/PR-321-control-board.md`; `docs/remediation/PR-321-reconciliation.md`; `docs/remediation/slices/TPM-PROGRESS-SCAN-COVERAGE-001.md`.
- Functions/regions: `Get-TpmOwnerStatusDisposition`; canonical owner-row parsing and status classification in `Test-TpmPermanentProcedures.ps1`; `freshnessPaths` in `Run-TpmQualityGate.ps1`.
- Owning subsystem: remediation governance and permanent procedure enforcement.

## 6. Tests required before implementation

- Focused failing or characterization tests: run the existing permanent gate against the current report without a freshness boundary; it must show that `SOURCE REMEDIATION REQUIRED` is rejected as an invalid status rather than recognized and blocked.
- Source/inventory checks: compare the control board, operating model, report template, and permanent-gate registry; validate that every registry status has exactly one recognized disposition and no unregistered status can pass.

## 7. Tests required after implementation

- Focused behavior tests: load status/disposition data from `quality/permanent-procedures.json`; exercise all seven statuses and an unknown status; prove conflicting historical/canonical rows follow the canonical table; prove missing/extra IDs and a blank corrected-status cell fail; prove source mode rejects the current/synthetic unresolved canonical status and a deliberately `NOT FIXED` path; prove certification requires exactly one current-candidate status equal to `VALIDATED`, rejects `NOT BUILT`/`STALE`/missing/malformed/duplicate status fields, ignores historical stale-package prose, and continues blocking owner-runtime-needed statuses.
- Regression suite: full main Pester under PowerShell 7 and Windows PowerShell 5.1; SupportPackage suite; parser, ASCII, PSScriptAnalyzer, InjectionHunter, `git diff --check`, and permanent-procedure gate. ID 3 is recorded `SOURCE FIXED; OWNER RUNTIME NEEDED` after the final aggregate source/permanent gate PASS; any later gate failure restores `SOURCE REMEDIATION REQUIRED`. Candidate-source preparation requires source gates to pass; owner-runtime remains separate.

## 8. Documentation/report updates required

- Control board row: ID 3 is `SOURCE FIXED; OWNER RUNTIME NEEDED` after the user-extensible discovery/sort fix, focused coverage, and finite census. The final full source/permanent aggregate gate passed; exact-SHA candidate-source preparation is eligible, while package build still requires current-cycle #290 review, exact-SHA READY, and human authorization. Keep allowed statuses synchronized and derive IDs from the board table.
- Remediation report row: record the reopened source gap, exact before/after test evidence, and explicit current-candidate status enforcement. Source mode must reject unresolved statuses and explicit `NOT FIXED` paths; certification must require one `VALIDATED` current candidate and continue blocking owner-runtime-needed statuses.
- Hunk classification: this contract ID / owner ID 3 / `TPM-OWNER-003`, `TPM-TRACE-001`, `TPM-AUTH-001` / PR #321.
- Changelog or user docs, if applicable: not applicable; this changes internal governance enforcement only.

## 9. Permanent procedure IDs affected

- `TPM-OWNER-003`: recognized owner status vocabulary and unresolved status blocking.
- `TPM-TRACE-001`: map the gate, test, current-slice, board, and report hunks to this contract and PR #321.
- `TPM-AUTH-001`: preserve the no-commit/push/package/runtime/release authorization boundary.

## 10. Runtime smoke checklist

- Exact packaged behavior: not applicable; no product behavior changes.
- Required source/package identity: local worktree base `193796a08d17f87f823d047646a3e848b85977fc`; package identity is not required for this governance-only change.
- Evidence artifacts: focused classification test and direct permanent-gate output showing a valid unresolved status blocks the source gate.
- Owner/runtime authorization: not authorized or required for this governance-only change; owner runtime remains a separate RC8 blocker.

## 11. Stop condition

- Stop when the canonical table has exactly one status-bearing row for every control-board owner ID, all gate-contract files participate in freshness validation, unresolved statuses and explicit `NOT FIXED` paths remain blocking, focused and regression tests pass, the current-slice pointer and report mapping name this contract, and the direct gate passes source mode while certification mode still rejects outstanding owner-runtime evidence and stale package identity.

## 12. Forbidden actions

No unrelated cleanup, product feature work, package, release, certification, wiki update, ARCADE work, owner smoke, commit, or push.

## 13. Commit/package authorization status

- Commit authorized: No; explicit authorization required.
- Package authorized: No.
- Release/certification authorized: No.
## 14. Additional certification re-audit -- historical stale candidate wording

- Exact failure: `Test-TpmPermanentProcedures.ps1` currently scans all report text for `candidate` followed by `stale` or `predates`. The report intentionally keeps historical stale-candidate evidence, so certification rejects a future valid package even when its current provenance is fresh.
- Expected behavior: certification reads an explicit current-candidate status field only. Missing, malformed, `NOT BUILT`, or `STALE` fields fail closed; `VALIDATED` removes this stale-status blocker without erasing historical audit text. Existing `OWNER RUNTIME NEEDED` statuses must still fail certification.
- Focused test before implementation: create a report fixture whose current candidate status is `VALIDATED` while retaining the real historical stale-package notes; invoke certification mode and assert the historical text does not cause a stale-candidate failure. The unresolved owner statuses may still cause the expected certification failure. Verify a `STALE` current field remains rejected.
- Focused tests after implementation: exercise missing/invalid/`NOT BUILT`/`STALE`/`VALIDATED` current-candidate fields; preserve historical stale prose in the validated fixture; assert unresolved owner and owner-runtime statuses remain blocking in their respective modes.
- Runtime proof: not applicable to the governance-code correction. Exact package identity and Eli's owner smoke remain mandatory for owner-runtime closure.
- Stop condition: do not mark certification current while the stale-text false positive persists or owner-runtime statuses pass; no historical audit prose may be removed or falsified.
- Hunk mapping: `Test-TpmPermanentProcedures.ps1`, `Run-TpmQualityGate.ps1` if freshness inputs change, owner-status regression, and remediation evidence; owner ID 3 status semantics only; PR #321; `TPM-OWNER-STATUS-GATE-001`; `TPM-OWNER-003`; `TPM-TRACE-001`; `TPM-AUTH-001`.
