# TPM Remediation Slice Contract

## 1. Slice name

- Name: PostgreSQL 8.3 password reset through temporary authenticated recovery policy
- Contract ID: TPM-POSTGRES-RESET-TRANSPORT-001
- Issue/PR: PR #321 remediation control board, owner report ID 16

## 2. Owner report IDs included

- IDs: 16
- Exact owner-visible failures: The reset used elevated PostgreSQL single-user mode, which PostgreSQL 8.3 rejects. The confirmed recovery procedure temporarily permits only localhost connections as role `postgres`, issues the role change through local `psql`, restores the exact authentication policy, and verifies authentication after restart.

## 3. Explicit exclusions

- Owner IDs not included: All IDs other than 16.
- Features, modules, package, runtime, and release actions excluded: Database/profile restore and reset policy, unrelated RC8 findings, package/release changes, merge/tag/publication, and wiki. The supplied owner directive authorizes commit/push after required source gates; it does not authorize release actions.

## 4. Behavior contract

- Current failure: `Reset-PostgresPasswordAutomatically` executes `postgres.exe --single` with administrative privileges and PostgreSQL 8.3 rejects the operation.
- Expected behavior: Require verified recovery evidence and byte-identical live `pg_hba.conf`; stop PostgreSQL; add a first-match `host all postgres 127.0.0.1/32 trust` rule; execute ALTER ROLE through `psql` standard input pinned to port 5432; restore and SHA-256 verify the exact original policy before restart; authenticate with the new password; restore the original service state; retain DPAPI save/read-back only after verification.
- Forbidden regressions: No restart with temporary trust present; no password in process arguments, logs, normal UI, or retry state after committed-but-unverified mutation; no loss of truthful committed-state reporting; no destructive database/profile change without existing backup gates. If the service cannot be confirmed stopped after ALTER ROLE, return ACTION_REQUIRED / UNKNOWN, do not restart, and disclose in Details/logs that the temporary localhost rule may remain active in the running service. If policy restore fails, no restart is attempted; report ACTION_REQUIRED / UNKNOWN without claiming the service is stopped.
- Design boundaries and deliberate exclusions: Existing transaction and protected-resume governance remains authoritative. Technical mechanism details are confined to Details/logs; normal progress uses plain-language stages.

## 5. Source/function ownership

- Files: `TeknoParrot-Manager.ps1`, `Tests/TeknoParrot-Manager.Tests.ps1`, `ARCHITECTURE.md`, `docs/remediation/PR-321-control-board.md`, `docs/remediation/PR-321-reconciliation.md`, this contract.
- Functions/regions: `Get-PostgresResetFailureGuidance`, `Reset-PostgresPasswordAutomatically`, automatic-reset tests, normal PostgreSQL recovery output.
- Owning subsystem: PostgreSQL recovery.

## 6. Tests required before implementation

- Focused failing or characterization tests: PostgreSQL automatic-reset success, failure, committed-but-unverified, redaction, and normal-mode UX tests.
- Source/inventory checks: Verify actual PostgreSQL 8.3 rejection evidence from owner report; inspect the existing backup and service transaction boundary.

## 7. Tests required after implementation

- Focused behavior tests: Success path, strict trust rule, live-policy drift, ALTER failure rollback/service state, stop failure after ALTER, initially-stopped service restoration, restore failure after ALTER, restart failure, authentication failure, hash restoration, port pinning, no password in args/logs, no `--single`, and normal-mode detail boundary.
- Regression suite: Focused PostgreSQL tests on PowerShell 7 and Windows PowerShell 5.1; full main suite when focused checks pass.
- Static and procedure gates: Parser, ASCII, `git diff --check`, PSScriptAnalyzer, and required remediation quality gate.

## 8. Documentation/report updates required

- Control board row: Owner ID 16 and PostgreSQL runtime proof boundary.
- Remediation report row: Changed-file/hunk classification and observed gate evidence.
- Hunk classification: Owner report 16 / PR #321 / TPM-TRACE-001 / TPM-POSTGRES-RESET-TRANSPORT-001.
- Changelog or user docs, if applicable: Architecture contract only; no release version bump requested.

## 9. Permanent procedure IDs affected

- TPM-TRACE-001 and TPM-OWNER-001; runtime proof is separately identified and must not be inferred from tests.

## 10. Runtime smoke checklist

- Exact packaged behavior: Rebuild from exact pushed SHA; exercise reset success and failures against approved PostgreSQL 8.3 runtime; confirm restored policy hash, service state, and successful new-password authentication.
- Required source/package identity: Exact pushed SHA and rebuilt candidate package.
- Evidence artifacts: Reset transaction result, service state, restored-policy digest, and live authentication result.
- Owner/runtime authorization: Owner report records completed ARCADE physical proof for the mechanism; any new source/package exact-SHA proof remains separately tracked.

## 11. Stop condition

Stop after required focused/static/procedure gates, hunk/report mapping, commit, and push. Do not merge, tag, publish, release, or claim additional runtime proof.

## 12. Forbidden actions

No physical data deletion, Desktop Commander/shared-host interaction, unrelated user-process changes, unrelated RC8 work, merge, tag, publication, or release.

## 13. Commit/package authorization status

- Commit/push authorized: Yes, when required source gates pass.
- Package/release authorized: No additional release action authorized.
