# TPM S2-B1 Shared Transaction Renderers Contract

## 1. Slice name

- Name: Shared transaction normal, Details, and terminal status renderers
- Contract ID: TPM-S2B1-RENDERERS-001
- Issue/PR: PR #321 remediation control board

## 2. Owner report IDs included

- IDs: S2-B1 renderer implementation authorization
- Exact owner-visible failures:
  - The S2-A presentation projection exists but no shared normal or Details
    renderer consumes it.
  - Workflow status can still combine generic completion markers with a
    non-success transaction outcome.
  - Details output has no separate validated redaction/provenance context.
  - The normal ReShade summary still renders legacy counters and technical
    classifications directly.

## 3. Explicit exclusions

- Owner IDs not included: workflow-wide renderer migration and runtime proof.
- No package generation or rebuild, owner smoke, Arcade work, wiki work, push,
  commit, merge, tag, publication, certification, or release-readiness action.
- No workflow-wide event-schema migration, support-package serialization
  migration, ReShade acquisition/ownership migration, or Details caller
  migration.

## 4. Behavior contract

- `Format-TpmTransactionPresentationRows` accepts only a validated
  `TPM.TransactionPresentation.v1` and emits deterministic beginner-safe
  normal rows using fixed wording and authoritative item counts/labels.
- `TPM.TransactionDetailsContext.v1` carries only identity-matched redacted
  technical references with explicit evidence classes and safe recovery-action
  labels. Context validation rejects credentials, paths, hashes, commands,
  stack traces, unredacted values, and mismatched transaction identity.
- `Format-TpmTransactionDetailsRows` renders presentation identity, outcome,
  product state, item accounting, rollback/cleanup flags, and approved context
  only. Missing context is explicitly unavailable; raw source transaction and
  technical details are never used as a fallback.
- `Set-TpmWorkflowTransactionPresentation` makes the validated presentation
  the terminal status authority. Only `SUCCEEDED` can emit `[OK]` or
  `Finished`; `NO_OP` is `Unchanged`; verified rollback is `Restored`; all
  other outcomes avoid success and skipped terminal claims. Required missing
  or invalid presentation renders fail-closed review wording.
- The authorized normal ReShade summary converts its validated transaction to
  the shared presentation and prints shared normal rows. Protected and unsafe
  per-item details plus native-warning rows pass through a bounded redacted
  adapter. Existing ReShade acquisition, ownership, mutation, and separate
  Details behavior remain unchanged.

## 5. Forbidden regressions

- Do not turn `NO_OP`, `PARTIAL_APPLIED`, `ROLLED_BACK_VERIFIED`,
  `ACTION_REQUIRED`, or `CLEANUP_RESIDUE` into success or skipped status.
- Do not embed source `TransactionResult`, raw technical details, credentials,
  paths, hashes, commands, or stack traces in normal or Details rows.
- Do not weaken S2-A validation, S1 transaction validation, or existing support
  redaction/provenance boundaries.
- Do not claim workflow-wide renderer migration from the single ReShade
  summary adapter.

## 6. Source/function ownership

- Files:
  - `TeknoParrot-Manager.ps1`
  - `Tests/TeknoParrot-Manager.Tests.ps1`
  - `ARCHITECTURE.md`
- Functions/regions:
  - `Test-TpmTransactionDetailsSafeText`
  - `Assert-TpmTransactionDetailsContext`
  - `ConvertTo-TpmTransactionDetailsContext`
  - `Format-TpmTransactionPresentationRows`
  - `Format-TpmTransactionDetailsRows`
  - `Set-TpmWorkflowTransactionPresentation`
  - `Require-TpmWorkflowTransactionPresentation`
  - `Format-TpmWorkflowStatusRows`
  - normal ReShade onboarding result summary
- Owning subsystem: shared transaction presentation, terminal status policy,
  and beginner-safe normal/Details rendering.

## 7. Tests required after implementation

- Focused `S2-B1-RENDERERS` tests for all seven outcomes, fixed row order,
  item counts and labels, Details identity and redaction, status authority,
  fail-closed missing/invalid presentation, ReShade adapter source shape,
  actual changed/skipped/failed profile IDs, and selected-set accounting.
- Focused S2-A presentation regressions.
- Existing Issue #300 workflow-status regressions and S1 transaction suites.
- Full `Tests/TeknoParrot-Manager.Tests.ps1` suite.
- Static/procedure gates: Windows PowerShell parser, pwsh parser,
  PSScriptAnalyzer Error/Warning with project settings, ASCII check,
  InjectionHunter canonical scan, `git diff --check`, and final status capture.

## 8. Remediation mapping

- Control board: `PR-321-control-board.md` S2-B1 section.
- Reconciliation: `PR-321-reconciliation.md` S2-B1 section.
- Permanent procedures: TPM-TRACE-001 source-hunk mapping and TPM-OWNER-001
  owner-runtime deferral.

## 9. Runtime and release disposition

- Owner/runtime proof: unauthorized; owner smoke remains paused.
- Package identity: no package created or rebuilt.
- Release disposition: no release-ready, certification, publication, tag, push,
  merge, or wiki action.

## 10. Stop condition

Stop when focused S2-B1 tests, S2-A/status/S1 regressions, required static
checks, source/report mapping, and final implementation-packet evidence are
complete. Do not widen scope to workflow-wide migration or unrelated findings.
