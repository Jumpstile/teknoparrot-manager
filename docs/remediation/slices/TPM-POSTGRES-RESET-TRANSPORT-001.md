# TPM Remediation Slice Contract

## 1. Slice name

- Name: PostgreSQL 8.3 protected password recovery failure observability and pre-UAC readiness pause
- Contract ID: TPM-POSTGRES-RESET-TRANSPORT-001
- Issue/PR: PR #321 remediation control board, owner report ID 16

## 2. Owner report IDs included

- IDs: 16
- Exact owner-visible failures: Packaged PostgreSQL 8.3 protected recovery created its verified evidence bundle but exited before ALTER ROLE commit; available evidence identifies only a later database-backup failure summary and does not establish the earlier reset stage. Normal-mode pre-UAC guidance was too quickly followed by UAC and did not visually meet the owner's standard.

## 3. Explicit exclusions

- Owner IDs not included: All owner IDs other than 16.
- Features, modules, runtime, and release actions excluded: Database/profile restore and reset policy, unrelated RC8 findings, merge/tag/publication, and wiki. A diagnostic-only exact-head RC8 package is authorized for ARCADE runtime diagnosis; it is not a release candidate and does not authorize publication.

## 4. Behavior contract


- Current failure: Two exact-package attempts created backup evidence, preserved the prior authenticating password, and retained the original live pg_hba.conf hash, then reported database backup failure and issued retry. The evidence does not identify the earlier failure stage. Existing failure reporting can therefore collapse recovery-reset and later database-backup failures.
- Expected behavior: Preserve the verified-backup -> reset -> password-authentication -> database-backup ordering. Expose reset FailureStage, ReasonCode, and sanitized reason in a structured result and log. Preserve failure classification between recovery backup verification, password reset, and database backup. Before non-admin UAC handoff, normal mode shows a compact, well-spaced panel with the administrator-permission heading, protected PostgreSQL operation reason, Windows User Account Control notice, "Click Yes" action, and automatic continuation; then requires explicit Enter before UAC starts. Re-render the panel on retry. Protected child remains non-interactive.
- Forbidden regressions: No service state/policy safety loss, no password in process arguments, logs, normal UI, or retry state after committed-but-unverified mutation; no database/profile change without existing verified backup gates; no retry using an unverified committed credential.
- Design boundaries and deliberate exclusions: Existing transaction and protected-resume governance remains authoritative. Technical mechanism details are confined to Details/logs; normal progress uses plain-language stages. Never infer runtime proof from tests.

## 5. Source/function ownership

- Files: `TeknoParrot-Manager.ps1`, `Tests/TeknoParrot-Manager.Tests.ps1`, `scripts/Run-TpmQualityGate.ps1`, `ARCHITECTURE.md`, `SECURITY.md`, `docs/RC8-REMEDIATION-INVENTORY.md`, `docs/remediation/PR-321-control-board.md`, `docs/remediation/PR-321-reconciliation.md`, this contract.
- Functions/regions: `Write-PostgresAdministratorGuidance`, `Start-PostgresRecoveryAsAdministrator`, `Reset-PostgresPasswordAutomatically`, `Invoke-PostgresSelectedPasswordRecovery`, protected resume database backup, PostgreSQL reset and UAC tests, Pester 5.7.1 quality-gate launch.
- Owning subsystem: PostgreSQL recovery.

## 6. Tests required before implementation

- Focused failing or characterization tests: Existing pre-UAC tests establish guidance but not acknowledgment before `RunAs`; existing reset tests cover several stages but not the protected-child exact runtime-like ordering or safe stage/reason propagation.
- Source/inventory checks: Inspect reset stage assignments, result adaptation, and the protected child's verified-backup -> reset -> database-backup path; preserve committed-state and password secrecy invariants.

## 7. Tests required after implementation

- Focused behavior tests: PS7 and Windows PS5.1 guidance/Enter/UAC ordering; protected-child success; failed current-password auth with verified recovery backup and reset before database backup; safe reset stage/reason; no retry after committed-unverified credential; password absent from args/log/output; exact original hba restoration; distinguish recovery-backup verification, reset, and later database-backup failure.
- Regression suite: Existing PostgreSQL focused regressions; full main Pester suite; SupportPackage; parse; ASCII; PSScriptAnalyzer; `git diff --check`; permanent procedure gate.
- Runtime-like integration fixture: Exercise exact orchestration with a chosen password initially rejected, verified evidence, reset success, and subsequent database backup.

## 8. Documentation/report updates required

- Control board row: Owner ID 16 and physical-runtime proof boundary.
- Remediation report row: Update owner ID 16 test names, changed-file mapping, and exact gate evidence.
- Hunk classification: Owner report 16 / PR #321 / TPM-TRACE-001 / TPM-OWNER-001 / this contract.
- Changelog or user docs, if applicable: Architecture and Security descriptions corrected to actual supported local-psql reset behavior; RC8 candidate changelog entry.

## 9. Permanent procedure IDs affected

- TPM-TRACE-001 and TPM-OWNER-001; runtime proof remains separately identified.

## 10. Runtime smoke checklist

- Exact packaged behavior: Build the exact pushed head using the canonical package contents into a new SHA-scoped diagnostic candidate directory. Validate identity, contents, privacy/leak checks, crosshair assets, and ZIP SHA-256. Exercise packaged reset success/failure and the permission panel/readiness gate on ARCADE; verify original policy hash, service state, authenticated new password, and prompt ordering.
- Required source/package identity: Exact pushed source SHA, branch ref, source script SHA-256, package path, and package SHA-256. The package is for diagnosis only, not a release candidate.
- Evidence artifacts: Reset result stage/reason code, protected-child log, service state, restored-policy digest, live authentication, captured permission panel, readiness acknowledgement, and package validation record.
- Owner/runtime authorization: The 2026-10-01 owner directive authorizes a diagnostic exact-head package for later ARCADE diagnosis. ARCADE runtime execution remains pending and outside this worktree; no runtime proof is claimed.

## 11. Stop condition

Stop after source tests, static/permanent gates, commit/push, and diagnostic exact-head package validation. Keep runtime root cause unclaimed until ARCADE evidence identifies the failing stage. Do not merge, tag, publish, release, or claim RC8 readiness.

## 12. Forbidden actions

No physical data deletion, merge, tag, publication, release, wiki update, or unrelated RC8 work.

## 13. Commit/package authorization status

- Commit/push authorized: Yes, by the 2026-10-01 owner directive after required source gates pass.
- Diagnostic exact-head package authorized: Yes, after push and for ARCADE diagnosis only; not a release candidate.
- Merge/tag/publication/release authorized: No.
