# TPM Remediation Slice Contract

## 1. Slice name

- Name: PostgreSQL recovery must fail closed when the authentication policy restore fails
- Contract ID: TPM-RC8-LANE-G-PG-FAILCLOSED-001
- Issue/PR: none assigned in this lane (owner report #336 wording is included in section 2)

## 2. Owner report IDs included

- IDs: #336 (wording only)
- Exact owner-visible failures:
  - A failed PostgreSQL authentication-policy restore leaves the temporary `host all postgres 127.0.0.1/32 trust` line in `pg_hba.conf`. The recovery reports ACTION_REQUIRED but does not name the file, and later password operations in the same session are not stopped.
  - Restore success text states "Restore finished and was verified" without saying what was checked.

## 3. Explicit exclusions

- Owner IDs not included: all others.
- Features, modules, package, runtime, and release actions excluded: no change to the recovery order (stop, trust line, ALTER ROLE, restore, restart, verify); no change to `postgresql.conf` handling; no new backup format; no change to the user profile or LaunchBox restore logic beyond the wording lines listed in section 5.

## 4. Behavior contract

- Current failure (base 785647659):
  - `Reset-PostgresPasswordAutomatically` (15551-15716) restores `pg_hba.conf` from an in-memory copy taken at 15606 (`$originalHbaBytes`). On failure, the catch at 15668-15670 retries that write and, on failure, sets `$restoreFailed` and `$script:PostgresAuthPolicyRestoreBlocked`. The function still returns through 15701-15710. The result has no file path and no manual-recovery state.
  - `$script:PostgresAuthPolicyRestoreBlocked` is reset to `$false` at the start of every setup pass (34323), so a second pass can reach password operations again.
- Expected behavior:
  - The restore source is the recorded pre-change backup file `<RecoveryBackup.Path>\PostgreSQL\pg_hba.conf`. Its SHA-256 must equal the `Sha256` recorded in `RecoveryBackup.ConfigBackups` by `Copy-PostgresRecoveryEvidenceFile` (15423). The file must exist. Only then is it written to `$hbaPath`, and the live file hash is read back and must equal the recorded hash.
  - If the backup is missing, its hash does not match the recorded hash, or the restore write/readback fails, the restore is retried once (existing catch path) and then the result is `ACTION_REQUIRED` with ReasonCode `MANUAL_RECOVERY_REQUIRED`. The summary names the exact `$hbaPath` and the backup path.
  - When `MANUAL_RECOVERY_REQUIRED` is set, `$script:PostgresManualRecoveryRequired` holds `$hbaPath` for the rest of the process. The following entry points return ACTION_REQUIRED before any password operation: `Reset-PostgresPasswordAutomatically`, `Invoke-PostgresSelectedPasswordRecovery`, and `Invoke-RestorePostgresBackup`. The setup pass does not clear this flag.
  - Success wording states only what was verified: "Restore completed; verification: <what was checked>", where the check is the transaction outcome for PostgreSQL restores and "every file copy completed without error" for file-based restores.
- Forbidden regressions:
  - No start of PostgreSQL after a failed authentication-policy restore (existing 34817 and 34829 guards stay).
  - No new password operation while the manual-recovery flag is set.
  - No success wording that names an unperformed check.
  - No logging of passwords or of the recorded hash in a way that changes existing log redaction.
- Design boundaries and deliberate exclusions:
  - The trust line cannot be removed by TPM if the file is unwritable; in that case the result is ManualRecoveryRequired with the path, and the user must restore the file.
  - A new TPM process does not know about an earlier session's flag. The existing AUTHENTICATION_POLICY_UNSAFE guard (15615-15618) still refuses a recovery attempt when the trust line is present on disk.

## 5. Source/function ownership

- Files: TeknoParrot-Manager.ps1 (only)
- Functions/regions:
  - `Reset-PostgresPasswordAutomatically` (15551-15716): restore block 15604-15700; result block 15701-15715.
  - New helper `Restore-PostgresHbaFromBackup` and `Test-PostgresManualRecoveryRequired`, placed after `Get-PostgresRecoveryBackupState` (15481-15497).
  - `Invoke-PostgresSelectedPasswordRecovery` (20109): guard at entry.
  - `Invoke-RestorePostgresBackup` (29927): guard at entry; success wording at 30043.
  - Restore menu (33999-34038): success wording at 34008-34009 and 34030-34031, with a shared `$restoreVerification` variable.
- Owning subsystem: PostgreSQL recovery and restore menu.

## 6. Tests required before implementation

- Focused failing or characterization tests: none run (owner hold; static review only).
- Source/inventory checks: confirm callers of `Reset-PostgresPasswordAutomatically` (20136, 34629) and `Invoke-PostgresSelectedPasswordRecovery` (20117 caller set, 34349, 34413) still receive the same result shape.

## 7. Tests required after implementation

- Focused behavior tests (main agent, if authorized): a forced `pg_hba.conf` write failure returns ReasonCode `MANUAL_RECOVERY_REQUIRED` and names `$hbaPath`; a backup hash that differs from the recorded hash blocks restore; a second recovery call after the flag is set makes no ALTER ROLE call.
- Regression suite: Tests\TeknoParrot-Manager.Tests.ps1 (run by main agent).
- Static and procedure gates: ASCII check, parse check, PSScriptAnalyzer with PSScriptAnalyzerSettings.psd1.

## 8. Documentation/report updates required

- Control board row: docs\remediation\PR-321-control-board.md (main agent).
- Remediation note: docs\remediation\RC8-LANE-G-PG-FAILCLOSED.md.
- Hunk classification: fail-closed behavior change in recovery; wording-only change in restore menu.
- Changelog or user docs, if applicable: main agent decides at release time.

## 9. Permanent procedure IDs affected

- IDs and evidence: none identified in this lane.

## 10. Runtime smoke checklist

- Exact packaged behavior: not run (owner hold).
- Required source/package identity: not applicable in this lane.
- Evidence artifacts: none.
- Owner/runtime authorization: required before any runtime check.

## 11. Stop condition

Stop when the restore block, the result mapping, the three guards, and the wording lines are edited and read back, and ASCII/byte checks pass. Do not widen scope.

## 12. Forbidden actions

No unrelated cleanup, broad rewrite, commit, push, package, release, certification, wiki update, test-PC work, or owner smoke unless separately authorized.

## 13. Commit/package authorization status

- Commit authorized: No, explicit authorization required
- Package authorized: No, explicit authorization required
- Release/certification authorized: No, explicit authorization required

## 14. Current dirty-worktree continuation (source-only; not validated)

- `Set-PostgresHbaPolicyAtomically` uses `[NullString]::Value` for .NET's optional replacement-backup filename. It creates its stage exclusively, applies the existing target ACL before writing bytes, flushes and hash-checks the stage, and atomically replaces the target. There is no delete/move fallback.
- PostgreSQL recovery markers are staged exclusively under an owner-only recovery directory, restricted to the current user's ACL, flushed, and atomically moved/replaced. Marker reads require a non-reparse path and verified current-user-only ACL; a marker with broader or inherited permissions fails closed and may require manual recovery.
- If a pre-existing marker has broad/inherited ACLs or fails path checks, TPM does not trust its stored HBA/backup paths: it blocks password recovery, names the marker and error, and directs manual verification of the configured `pg_hba.conf` against a trusted recovery backup. Path/ACL checks do not pin filesystem identities; a concurrent substitution can still require manual recovery. Unsupported atomic replacement fails closed without a delete/move fallback.
- When the service stop cannot be verified, TPM durably sets `ServiceStopUnconfirmed` before any on-disk authentication-policy restore. Failure to persist that flag prevents the restore attempt. A marker is retained while shutdown is unconfirmed; marker-state reconciliation does not clear or restore based on the file hash alone and requires an observed `Stopped` service.
- Recovery consumers recheck that backup files are non-reparse paths with current-user-only ACLs before reading/copying. PostgreSQL profile rollback is limited to profiles whose write was attempted, so unattempted profiles are not overwritten; attempted profile items are reported restored only after profile rollback verifies, otherwise they are unknown. It preflights every selected backup digest/ACL and destination path/type before the first restore copy, then rechecks backup evidence and destination safety at each write boundary and verifies each restored file against its recorded SHA-256. A failed preflight performs no profile copies; an in-progress failure or cancellation reports Error or Cancelled respectively and stops further copies. An interrupted setup closes Cancelled only after its profile/database rollback verifies; unverified rollback remains Error.
- Static source review only. No TPM tests, parser, gates, smoke, or runtime verification were run; owner hold remains.
