# PR #321 Current Slice: PostgreSQL Retry Authentication Boundary

- Slice ID: TPM-POSTGRES-RETRY-AUTH-001
- Slice name: Protected PostgreSQL retry credential authentication boundary
- Included owner-report IDs: 16.
- Issue: PR #321.
- Permanent procedures: TPM-TRACE-001, TPM-OWNER-001, TPM-AUTH-001.
- Explicit exclusions: Other owner IDs; PostgreSQL reinitialization policy; backup implementation; unrelated recovery UX; merge, tag, publication, release assets, release-identity changes, and wiki publication. Exact-head package rebuild, ARCADE staging, and exhaustive #323 smoke are authorized only after the source gate, commit/push, and exact-head CI succeed.

## Behavior contract

- Current failure: A committed PostgreSQL role-password mutation followed by failed live revalidation could flow through protected resume as retryable. The result could omit `PasswordChangeCommitted` and mint a fresh protected resume envelope containing the rejected candidate.
- Expected behavior: Preserve committed-mutation state through wrapper results. On committed-but-unverified failure, remove consumed resume state, do not mint or advertise a credential retry, and report that the password change committed but the new password could not be verified. A verified credential continues only through the existing protected envelope and child-side authentication check; database/profile mutation still requires verified safety backup.
- Forbidden regressions: No plaintext password in artifacts, logs, or user-facing output; no retry with unverified credentials; no claim that the old password remains authoritative after commit; no database/profile mutation without verified backup; preserve DPAPI, PGPASSFILE, fatal native-command, and redaction protections.

## Prompt inventory and classification

- The change does not alter prompt choices or routing; protected-resume retry/status output and action handling are the affected terminal paths.
- Password input remains secure input and is not migrated to the finite-choice prompt reader.
- Existing recovery choice, cancel, and Back semantics remain unchanged.

## Source inventory

- The selected-recovery wrapper must preserve `PasswordChangeCommitted` through its final live revalidation result.
- The shared protected exit must not issue a retry envelope after committed-but-unverified mutation.
- Existing live authentication, protected envelope, backup-before-database/profile-mutation, and redaction boundaries remain in force.

## Required focused tests

- Committed post-change authentication failure removes consumed envelope and neither mints nor advertises a retry.
- Ordinary protected failure remains retryable when no password mutation committed.
- Successful protected resume exits cleanly.
- Reset authentication and database backup contracts remain intact.
- Run focused PostgreSQL recovery/password/resume tests under PS7 and Windows PowerShell 5.1; run the full main Pester and SupportPackage suites.

## Files allowed to change

- `TeknoParrot-Manager.ps1`
- `Tests/TeknoParrot-Manager.Tests.ps1`
- `ARCHITECTURE.md`
- `docs/RC8-REMEDIATION-INVENTORY.md`
- `docs/remediation/PR-321-current-slice.md`
- `docs/remediation/PR-321-control-board.md`
- `docs/remediation/PR-321-reconciliation.md`
- `docs/remediation/slices/TPM-POSTGRES-RETRY-AUTH-001.md`
- `scripts/Test-TpmPermanentProcedures.ps1`
- `scripts/Run-TpmQualityGate.ps1`
- `docs/governance/permanent-procedures.md`

## Runtime proof required

- Exact packaged behavior: From a candidate rebuilt from the exact reviewed source identity, exercise protected password reset with failed post-change authentication; verify no retry state is issued or advertised, and verify truthful committed-state guidance. Also exercise verified-password backup retry and successful recovery.
- Required source/package identity: Exact source commit and package rebuilt from it; a stale package is not evidence.
- Evidence artifacts: Child exit code, parent-side routing, visible committed-state guidance, retry-state absence, PostgreSQL service state, and backup evidence.
- Owner authorization: The 2026-09-30 owner directive authorizes commit/push after legitimate source gates, exact-head CI monitoring, exact-SHA package rebuild/verification, ARCADE staging, and the full exhaustive RC8 smoke. Merge, tag, publication, and release remain owner-blocked.

## Stop condition

Keep HOLD until the source-mode permanent-procedure gate passes legitimately, the exact source SHA is committed/pushed with exact-head CI green, a fresh package is rebuilt from that SHA, and the authorized ARCADE runtime proof completes. Certification-mode procedure validation must then pass before any release-ready claim. Stop immediately if a retry would contain an unverified credential or mutation could proceed without verified backup.

## Forbidden actions

No destructive ARCADE baseline change, baseline deletion, unrelated cleanup, merge, tag, publication, wiki update, release action, or release-identity change. Commit/push, exact-head package build, ARCADE staging, and exhaustive smoke are authorized by the current owner directive only after their preceding gates legitimately pass.

## Hunk classification

- `TeknoParrot-Manager.ps1`, `Tests/TeknoParrot-Manager.Tests.ps1`, `ARCHITECTURE.md`, `docs/RC8-REMEDIATION-INVENTORY.md`, control board, this current-slice record, and detailed contract: owner report 16 / PR #321 / TPM-TRACE-001 / TPM-POSTGRES-RETRY-AUTH-001.
- `scripts/Test-TpmPermanentProcedures.ps1`, `scripts/Run-TpmQualityGate.ps1`, `docs/governance/permanent-procedures.md`, and the governance assertions in `Tests/TeknoParrot-Manager.Tests.ps1`: PR #321 / TPM-TRACE-001 / TPM-OWNER-001 / TPM-AUTH-001 / TPM-POSTGRES-RETRY-AUTH-001; separates source-gate eligibility from runtime-complete certification without converting source evidence into runtime proof.
- Per-run owner/runtime evidence and disposition: owner report 16 / PR #321 / TPM-OWNER-001 / TPM-POSTGRES-RETRY-AUTH-001.
