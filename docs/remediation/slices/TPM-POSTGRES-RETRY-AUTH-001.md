# TPM PostgreSQL Verified Retry Credential

## 1. Slice name

- Name: Protected PostgreSQL retry credential authentication boundary
- Contract ID: TPM-POSTGRES-RETRY-AUTH-001
- Issue/PR: PR #321 remediation control board, owner report ID 16

## 2. Owner report IDs included

- IDs: 16
- Exact owner-visible failures: An elevated PostgreSQL recovery could commit `ALTER ROLE`, fail live password authentication, then issue a fresh protected resume state containing the rejected candidate and advertise a retry as safe.

## 3. Explicit exclusions

- Owner IDs not included: Every owner ID other than 16.
- Features and release actions excluded: PostgreSQL data reset/reinitialization policy, backup implementation, unrelated recovery UX, merge, tag, publication, release assets, release-identity changes, and wiki publication. The current owner directive separately authorizes exact-head package rebuild, ARCADE staging, and exhaustive runtime smoke after preceding source/CI gates pass.

## 4. Behavior contract

- Current failure: When the reset helper's post-ALTER authentication check succeeded but the selected-recovery wrapper's final live revalidation failed, the wrapper returned `ACTION_REQUIRED` without copying `PasswordChangeCommitted` from the reset result. Protected resume therefore treated the committed mutation as retryable and minted a fresh envelope from its candidate password. The shared protected-exit path could also issue that envelope for other committed-but-unverified failures.
- Expected behavior: A committed role-password change followed by failed restart/authentication revalidation is a mutation cutoff. Preserve `PasswordChangeCommitted` through wrapper results, remove the consumed state, do not mint or advertise a credential retry, and truthfully state that the password change committed but the new password could not be verified. A live-verified credential may continue only through the existing protected envelope and child-side authentication check; database/profile mutation still requires verified safety backup.
- Forbidden regressions: No password in plaintext artifacts, logs, or user-facing output; no unverified credential retry; no claim that the old password remains authoritative after commit; no database/profile mutation without verified backup; preserve DPAPI, PGPASSFILE, fatal native-command, and redaction protections.
- Design boundaries and deliberate exclusions: Changes only the retry-state issuance behavior after a committed-but-unverified role change. It does not change credential encryption, PostgreSQL reset mechanics, backup behavior, or ordinary interactive recovery.

## 5. Source/function ownership

- Files: `TeknoParrot-Manager.ps1`; `Tests/TeknoParrot-Manager.Tests.ps1`; `ARCHITECTURE.md`; `docs/RC8-REMEDIATION-INVENTORY.md`; `docs/remediation/PR-321-control-board.md`; this contract.
- Functions/regions: `Invoke-PostgresSelectedPasswordRecovery` caller in protected resume; `Exit-PostgresRecoveryResume`; protected resume terminal regression probe.
- Owning subsystem: PostgreSQL recovery and UAC resume.

## 6. Tests required before implementation

- Focused failing or characterization tests: Existing committed-reset authentication failure test, protected resume process probe, and recovery-state tests.
- Source/inventory checks: Confirmed reset commits before revalidation; confirmed protected resume's generic failure exit minted the retry directly from `resumeState.PasswordPlain`; confirmed ordinary backup-before-mutation gate remains unchanged.

## 7. Tests required after implementation

- Focused behavior tests: Committed post-change authentication failure removes the consumed envelope and neither mints nor advertises a retry; ordinary protected failure remains retryable; successful protected resume exits cleanly; reset authentication and database backup contracts remain intact.
- Regression suite: Focused PostgreSQL recovery/password/backup tests under PS7 and Windows PowerShell 5.1, followed by the full main Pester suite and SupportPackage suite.
- Static and procedure gates: ReleaseConsistency, production parser under PS7 and PS5.1, PSScriptAnalyzer Error/Warning, ASCII, `git diff --check`, and the permanent procedure gate when a remediation report is available.

## 8. Documentation/report updates required

- Control board row: Owner ID 16, updated with committed-but-unverified retry correction and runtime proof boundary.
- Remediation report row: Update the owner ID 16 report with the regression test and changed-file mapping; no report artifact was present in this checkout at implementation time.
- Hunk classification: Owner report ID 16 / permanent procedure evidence to be recorded in the remediation report / `TPM-POSTGRES-RETRY-AUTH-001` / PR #321.
- Changelog or user docs, if applicable: No release version or user guide update; architecture and invariant inventory updated for the corrected contract.

## 9. Permanent procedure IDs affected

- IDs and evidence: `TPM-TRACE-001` and `TPM-OWNER-001`, per `docs/remediation/slices/PR-321-current-slice.md`; owner ID 16. The required per-run remediation gate report was not present in this checkout, so the fail-closed procedure gate and commit authorization remain pending.

## 10. Runtime smoke checklist

- Exact packaged behavior: Rebuild from the pushed SHA; exercise protected password reset with failed post-change authentication and verify no retry state is issued or advertised. Also test verified-password backup retry and successful recovery.
- Required source/package identity: Exact pushed SHA and rebuilt RC8 candidate package; no stale package is valid evidence.
- Evidence artifacts: Captured child exit code, parent-side routing, visible truthful committed-state guidance, retry-state absence, PostgreSQL service state, and backup evidence.
- Owner/runtime authorization: The 2026-09-30 owner directive authorizes exact-head package rebuild/verification, ARCADE staging, and exhaustive RC8 smoke after legitimate source gates, commit/push, and exact-head CI. Merge, tag, publication, and release remain prohibited pending later owner approval.

## 11. Stop condition

Stop when focused and required source gates pass, report mapping and permanent procedure identity are resolved, and runtime proof is assigned to the authorized owner lane. Keep disposition HOLD until missing procedure/report evidence and runtime proof are complete.

## 12. Forbidden actions

No destructive ARCADE baseline change, baseline deletion, unrelated cleanup, merge, tag, publication, wiki update, release action, or release-identity change. Commit/push are authorized only after all source gates pass on `review/rc8-determinism-integration`; exact-head package build, ARCADE staging, and exhaustive smoke are authorized only after their preceding gates pass.

## 13. Commit/package authorization status

- Commit/push authorized: Yes, conditional on all required source gates passing.
- Exact-head package build and ARCADE exhaustive smoke authorized: Yes, conditional on commit/push and exact-head CI passing first.
- Merge/tag/publication/release authorized: No; later owner approval is required.
