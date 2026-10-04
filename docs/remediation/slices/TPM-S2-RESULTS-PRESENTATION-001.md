# TPM S2-A Shared Transaction Presentation Contract

## 1. Slice name

- Name: Shared transaction result presentation contract
- Contract ID: TPM-S2-RESULTS-PRESENTATION-001
- Issue/PR: PR #321 remediation control board

## 2. Owner report IDs included

- IDs: S2-A presentation-contract authorization
- Exact owner-visible failures:
  - Transaction results have seven authoritative outcomes but no shared
    beginner-safe presentation projection.
  - Workflow callers can still infer success from compatibility booleans,
    counters, generic status text, or legacy result fields.
  - Technical evidence can be mixed into normal result wording.
  - Details/support records do not have a stable presentation contract.

## 3. Explicit exclusions

- Owner IDs not included: workflow-wide renderer migration and runtime proof.
- Features, modules, package, runtime, and release actions excluded:
  - No workflow caller migration.
  - No workflow-status event or support-package serialization migration.
  - No package generation or rebuild.
  - No owner smoke, Arcade work, wiki work, push, commit, merge, tag,
    publication, certification, or release-readiness decision.

## 4. Behavior contract

- Current failure: `TPM.TransactionResult.v1` is authoritative, but there is
  no deterministic shared projection with fixed wording, item labels, and
  redaction boundaries.
- Expected behavior:
  - `ConvertTo-TpmTransactionPresentation` accepts only a validated
    `TPM.TransactionResult.v1`.
  - The result is `TPM.TransactionPresentation.v1`.
  - All seven outcomes receive fixed beginner-safe wording.
  - Counts are derived from authoritative v1 item sets.
  - Compatibility booleans, legacy counters, workflow status, and console text
    cannot change the projection.
  - Paths, passwords, credentials, hashes, raw commands, and stack traces are
    excluded from normal presentation fields.
  - The projection exposes only safe Details/support references and never
    embeds the source transaction or raw technical evidence.
- Forbidden regressions:
  - Do not turn `NO_OP` into a mutation success.
  - Do not present `ACTION_REQUIRED` or `CLEANUP_RESIDUE` as ordinary success.
  - Do not lose the verified-restore meaning of `ROLLED_BACK_VERIFIED`.
  - Do not lose the partial-change meaning of `PARTIAL_APPLIED`.
  - Do not weaken S1 transaction validation or password redaction.
- Design boundaries and deliberate exclusions:
  - S2-A defines and validates the projection; S2-B will migrate workflow
    status and renderers.
  - Technical evidence remains owned by existing result, log, report, and
    support redaction/provenance boundaries.

## 5. Source/function ownership

- Files:
  - `TeknoParrot-Manager.ps1`
  - `Tests/TeknoParrot-Manager.Tests.ps1`
  - `ARCHITECTURE.md`
- Functions/regions:
  - `Test-TpmTransactionPresentationSafeText`
  - `Get-TpmTransactionPresentationItemLabel`
  - `Get-TpmTransactionPresentationOutcomeDefinition`
  - `Assert-TpmTransactionPresentation`
  - `Test-TpmTransactionPresentation`
  - `ConvertTo-TpmTransactionPresentation`
  - S1 transaction outcome model and test fixture boundary
- Owning subsystem: transaction result authority and beginner-safe result
  presentation.

## 6. Tests required before implementation

- Focused characterization:
  - Existing S1 transaction outcome and redaction tests.
  - Existing v1 legacy normalization tests.
- Source/inventory checks:
  - Exact seven-outcome inventory.
  - Product-state inventory.
  - Authoritative item-set and cleanup invariants in
    `Assert-TpmTransactionResult`.
  - Beginner UX and credential-redaction requirements in `ARCHITECTURE.md`
    and `SECURITY.md`.

## 7. Tests required after implementation

- Focused behavior tests:
  - All seven outcomes.
  - Fixed headline, next-action, retry-safety, attention, and data-safety
    mapping.
  - Compatibility booleans are non-authoritative.
  - NO_OP, ACTION_REQUIRED, CLEANUP_RESIDUE, ROLLED_BACK_VERIFIED, and
    PARTIAL_APPLIED wording boundaries.
  - Counts and labels derive from v1 item sets.
  - Unsafe presentation text and technical item identifiers are rejected or
    redacted.
  - Source technical details are not embedded in the projection.
- Regression suite:
  - Existing S1 transaction-focused tests.
  - Full `Tests/TeknoParrot-Manager.Tests.ps1` suite.
  - `Tests/SupportPackage.Tests.ps1` if support code is touched.
- Static and procedure gates:
  - Parser check.
  - PSScriptAnalyzer Error/Warning check with project settings.
  - ASCII check.
  - InjectionHunter.
  - `git diff --check`.
  - Final status capture.

## 8. Documentation/report updates required

- Control board row: append S2-A implementation evidence and retain owner-smoke
  paused status.
- Remediation report row: append S2-A scope, source evidence, tests, and
  deferred runtime/package actions.
- Hunk classification: transaction presentation source, focused tests,
  architecture contract, control-board evidence, reconciliation evidence, and
  this slice contract.
- Changelog or user docs, if applicable: none; this slice does not migrate a
  user-facing workflow renderer.

## 9. Permanent procedure IDs affected

- TPM-TRACE-001: source hunk to S2-A contract and PR #321 mapping.
- TPM-OWNER-001: runtime proof remains required later and is not authorized.
- PR #321 fail-closed remediation gate: implementation evidence only; no
  release authorization.

## 10. Runtime smoke checklist

- Exact packaged behavior: deferred. S2-A has no workflow-wide renderer
  migration.
- Required source/package identity: source identity is the authorized branch
  and HEAD recorded in the implementation packet; package identity is not
  created.
- Evidence artifacts: focused tests, full Pester, static gates, and this
  contract/report update.
- Owner/runtime authorization: owner smoke remains paused and unauthorized.

## 11. Stop condition

Stop when the contract's focused tests, report status, hunk mapping, and
required gate evidence are complete. Do not widen scope to workflow migration
or unrelated findings.

## 12. Forbidden actions

No unrelated cleanup, broad rewrite, package, release, certification, wiki
update, ARCADE work, owner smoke, push, commit, merge, tag, or publication.

## 13. Commit/package authorization status

- Commit authorized: No; explicit authorization required.
- Package authorized: No.
- Release/certification authorized: No.
