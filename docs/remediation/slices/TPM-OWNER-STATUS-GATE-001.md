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
- Features, modules, package, runtime, and release actions excluded: no product behavior change, package build, runtime smoke, merge, tag, publication, certification, or release authorization. Commit/push is authorized only after source gates pass and only to PR #321's existing head ref to obtain exact-head CI.

## 4. Behavior contract

- Baseline failure: `Test-TpmPermanentProcedures.ps1` recognized only four legacy statuses, read the earlier owner mapping instead of the declared canonical corrected table, did not compare canonical IDs with the control-board owner table (which now reaches ID 35), and rejected stale-package evidence unconditionally in source mode. Its whitelist also conflicted with the JSON registry, operating model, and report template.
- Expected behavior: derive allowed labels and dispositions from the registry, validate a one-to-one mapping, classify the canonical corrected-status column, require exact unique owner-ID set equality with the control-board table, and reject unresolved labels in source mode. An explicitly `NOT FIXED` path in the progress audit blocks source mode; absence of that disposition is valid when the completed census has no uncovered paths. Preserve the separate `-RequireOwnerRuntime` failure for `SOURCE FIXED; OWNER RUNTIME NEEDED`; certification requires an explicit current-candidate status of `VALIDATED` and must reject `NOT BUILT`, `STALE`, missing, or malformed current status. Historical stale-candidate prose must not override a current validated status. Redirected child-process output is normalized to remove ANSI control sequences before status assertions, preserving the diagnostic text and preventing invalid control bytes in the Pester result report. Pull-request CI checks out the PR head SHA and verifies the checked-out commit before running gates.
- Forbidden regressions: promote any unresolved owner ID, read historical statuses as release decisions, omit/add/duplicate canonical IDs, pass an unresolved canonical status or `NOT FIXED` progress path, weaken the source/runtime distinction, allow unknown vocabulary, or block source gating solely because the candidate package is stale.
- Design boundaries and deliberate exclusions: `DEFERRED BY OWNER` remains a recognized owner disposition; this contract does not decide whether an owner deferral is appropriate for any ID. No product call site or runtime behavior changes.

## 5. Source/function ownership

- Files: `quality/permanent-procedures.json`; `scripts/Test-TpmPermanentProcedures.ps1`; `scripts/Run-TpmQualityGate.ps1`; `Tests/TeknoParrot-Manager.Tests.ps1`; `docs/governance/tpm-development-operating-model.md`; `docs/governance/permanent-procedures.md`; `docs/templates/remediation-gate-report.md`; `docs/remediation/PR-321-current-slice.md`; `docs/remediation/PR-321-control-board.md`; `docs/remediation/PR-321-reconciliation.md`; `docs/remediation/slices/TPM-PROGRESS-SCAN-COVERAGE-001.md`; `.github/workflows/ci.yml`.
- Functions/regions: `Get-TpmOwnerStatusDisposition`; canonical owner-row parsing and status classification in `Test-TpmPermanentProcedures.ps1`; `freshnessPaths` in `Run-TpmQualityGate.ps1`.
- Owning subsystem: remediation governance and permanent procedure enforcement.

## 6. Tests required before implementation

- Focused failing or characterization tests: run the existing permanent gate against the current report without a freshness boundary; it must show that `SOURCE REMEDIATION REQUIRED` is rejected as an invalid status rather than recognized and blocked.
- Source/inventory checks: compare the control board, operating model, report template, and permanent-gate registry; validate that every registry status has exactly one recognized disposition and no unregistered status can pass.

## 7. Tests required after implementation

- Focused behavior tests: load status/disposition data from `quality/permanent-procedures.json`; exercise all seven statuses and an unknown status; prove conflicting historical/canonical rows follow the canonical table; prove missing/extra IDs and a blank corrected-status cell fail; prove source mode rejects the current/synthetic unresolved canonical status and a deliberately `NOT FIXED` path; prove certification requires exactly one current-candidate status equal to `VALIDATED`, rejects `NOT BUILT`/`STALE`/missing/malformed/duplicate status fields, ignores historical stale-package prose, and continues blocking owner-runtime-needed statuses.
- Regression suite: full main Pester under PowerShell 7 and Windows PowerShell 5.1; SupportPackage suite; parser, ASCII, PSScriptAnalyzer, InjectionHunter, `git diff --check`, and permanent-procedure gate. The focused child-process assertion must pass with ANSI output normalized, and PR CI must prove its checked-out SHA equals the PR head SHA.

## 8. Documentation/report updates required

- Control board row: ID 3 is `SOURCE FIXED; OWNER RUNTIME NEEDED` after the user-extensible discovery/sort fix, focused coverage, and finite census. The final full source/permanent aggregate gate passed; exact-SHA candidate-source preparation is eligible, while package build still requires current-cycle #290 review, exact-SHA READY, and human authorization. Keep allowed statuses synchronized and derive IDs from the board table.
- Remediation report row: record the reopened source gap, exact before/after test evidence, and explicit current-candidate status enforcement. Source mode must reject unresolved statuses and explicit `NOT FIXED` paths; certification must require one `VALIDATED` current candidate and continue blocking owner-runtime-needed statuses.
- Hunk classification: this contract ID / owner ID 3 / `TPM-OWNER-003`, `TPM-TRACE-001`, `TPM-AUTH-001` / PR #321.
- CI test-output and checkout hunks: owner ID 3 status semantics only; PR #321; `TPM-OWNER-STATUS-GATE-001`; `TPM-OWNER-003`; `TPM-TRACE-001`; `TPM-AUTH-001`.

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

No unrelated cleanup, product feature work, package, release, certification, wiki update, test-PC work, or owner smoke. Commit/push is authorized only after source gates pass and only to PR #321's existing head ref for exact-head CI.

## 13. Commit/package authorization status

- Commit/push authorized only to PR #321's existing head ref after source gates pass, solely to obtain exact-head CI.
- Package authorized: No.
- Release/certification authorized: No.
## 14. Additional certification re-audit -- historical stale candidate wording

- Exact failure: `Test-TpmPermanentProcedures.ps1` currently scans all report text for `candidate` followed by `stale` or `predates`. The report intentionally keeps historical stale-candidate evidence, so certification rejects a future valid package even when its current provenance is fresh.
- Expected behavior: certification reads an explicit current-candidate status field only. Missing, malformed, `NOT BUILT`, or `STALE` fields fail closed; `VALIDATED` removes this stale-status blocker without erasing historical audit text. Existing `OWNER RUNTIME NEEDED` statuses must still fail certification.
- Focused test before implementation: create a report fixture whose current candidate status is `VALIDATED` while retaining the real historical stale-package notes; invoke certification mode and assert the historical text does not cause a stale-candidate failure. The unresolved owner statuses may still cause the expected certification failure. Verify a `STALE` current field remains rejected.
- Focused tests after implementation: exercise missing/invalid/`NOT BUILT`/`STALE`/`VALIDATED` current-candidate fields; preserve historical stale prose in the validated fixture; assert unresolved owner and owner-runtime statuses remain blocking in their respective modes.
- Runtime proof: not applicable to the governance-code correction. Exact package identity and the owner's smoke test remain mandatory for owner-runtime closure.
- Stop condition: do not mark certification current while the stale-text false positive persists or owner-runtime statuses pass; no historical audit prose may be removed or falsified.
- Hunk mapping: `Test-TpmPermanentProcedures.ps1`, `Run-TpmQualityGate.ps1` if freshness inputs change, owner-status regression, and remediation evidence; owner ID 3 status semantics only; PR #321; `TPM-OWNER-STATUS-GATE-001`; `TPM-OWNER-003`; `TPM-TRACE-001`; `TPM-AUTH-001`.

## 15. CI ANSI-output and exact-head checkout finding

- Exact CI failure: run `37090573916` checked out the synthetic PR merge tree, not the PR head tree. Its Pester test `uses canonical owner statuses and scopes stale-package rejection to certification mode` captured child `Write-Error` output containing ANSI escape sequences. Those sequences split the expected status across non-whitespace control bytes, causing the assertion failure; the same raw ESC byte then made Pester 5.7.1's NUnit XML export fail.
- Expected behavior: strip ANSI terminal control sequences from the redirected child output before assertions; retain the diagnostic content. Configure pull-request checkout to use `github.event.pull_request.head.sha` and assert `git rev-parse HEAD` equals that SHA before the test gates run.
- Required evidence: focused owner-status test passes without raw ANSI in its assertion output; fresh PR CI logs the exact checked-out head SHA and completes NUnit XML export.
- Hunk mapping: owner ID 3 status semantics; PR #321; `TPM-OWNER-STATUS-GATE-001`; `TPM-OWNER-003`; `TPM-TRACE-001`; `TPM-AUTH-001`.
- No package, owner-runtime, merge, tag, publication, certification, or release action is authorized.

## 16. Current qualification fixture preconditions -- 2026-10-24

- Mapping: owner ID 3, status semantics only; issue #323 / PR #321;
  TPM-OWNER-003, TPM-TRACE-001, TPM-EVIDENCE-001 and TPM-AUTH-001.
- Exact observed failure before this test edit: FinalMain-PS51 preserved
  1520 passed, 2 failed, 2 skipped, native exit 1 on the unchanged 642-file
  snapshot. The status test expected the STALE diagnostic while the real
  current report correctly declared NOT BUILT. No product-gate defect is
  established by that failure.
- Private EOF differential before the edit: EOFBaseline on both native
  PS5.1 and PS7, Pester 5.7.1, preserved 4 passed, 1 failed, 0 skipped,
  1519 intentionally not run, actual child exits 1. Restoring the original
  stdin-only EOF topology passed the real-host and all three redirected-input
  cases; only the status-fixture failure remained. Visible stdout is retained.
- Change: explicitly seed the existing copied report scenarios with STALE;
  use that private fixture for the STALE certification scenario. Continue
  exercising source mode against the actual report. Do not change any
  assertion, production gate, registry vocabulary or truthful real report state.

### Fixture specification inventory

| State or boundary | Required behavior | Evidence |
|---|---|---|
| Source mode / actual current report | Does not reject solely for NOT BUILT or STALE package state | Existing source-result assertions |
| Explicit STALE fixture / certification | Rejects stale candidate and outstanding owner runtime | Existing certification assertions |
| VALIDATED fixture with historical stale prose | Removes only the stale blocker; owner runtime still blocks | Existing validated-candidate assertions |
| Missing, malformed, NOT BUILT or duplicate field | Fails closed in certification | Existing remaining candidate-state assertions |
| Canonical/historical owner rows | Preserves canonical precedence and unresolved-owner rejection | Existing owner-status assertions |

### Fixture invariant inventory and stop condition

- Live report provenance must never be falsified to satisfy a scenario.
- Scenario setup must establish its package state independently of the current
  report's changing status; historical source-report text remains intact.
- Preserve every existing assertion and all current owner statuses. No mock of
  the production gate or unrelated command; no feature or runtime change.
- Required after-edit proof: the same five selected cases pass on both native
  engines with pinned Pester 5.7.1; independently review the test/harness delta,
  freeze all revised source/docs, then rerun required main/folder/permanent gates.
- Stop on failed assertions, unmapped hunks, drift or unobserved exits. The old
  failed freeze and every baseline remain immutable; no package, commit/push,
  certification, owner acceptance or publication authorization is supplied.

- Additional observed fixture precondition: after the line-ending-safe STALE
  setup advances, EOFVerified on both engines still returns 4 passed, 1 failed
  and actual exit 1. The synthetic extra-owner row hard-codes ID 36, which is
  now a real board owner. The production gate correctly rejects a duplicate,
  not an absent ID. Before the next test edit, require the extra-owner fixture
  to choose an integer above the maximum numbered ID in the actual board and
  interpolate that same ID in the existing absent-owner assertion. Do not
  re-pin to 37, weaken the assertion, change the gate or remove owner 36.
- Fixture invariant: negative missing/extra/blank-owner scenarios must establish
  the property their assertions exercise. An evolving owner census cannot
  turn an intended absent-owner case into a duplicate-owner case.

- Focused closure: EOFComplete, native PS5.1 5.1.26100.9711 and PS7 7.6.5,
  pinned Pester 5.7.1: each 5 passed, 0 failed, 0 skipped, 1519 intentionally
  not run; both actual native child exits 0 and all 642 working-source files
  matched before/after. Native process intervals:
  2026-10-24T21:39:08.1707981Z to 2026-10-24T21:39:41.4147742Z (PS5.1),
  2026-10-24T21:39:42.8603921Z to 2026-10-24T21:40:07.7041484Z (PS7).
- Scoped independent source review found no assertion weakening or product-gate
  change after the CRLF and synthetic-ID preconditions were corrected. Full
  final-source main/folder/permanent qualification remains separate; this
  focused closure is not an aggregate, package or owner-runtime acceptance.
