# RC8 Lane G -- PostgreSQL fail-closed restore

Contract: docs\remediation\slices\TPM-RC8-LANE-G-PG-FAILCLOSED-001.md
Base: 785647659aff687b7d2fae7518be3ad25a298243
Scope file: TeknoParrot-Manager.ps1 (only)

## What changed

- New helper `Restore-PostgresHbaFromBackup` restores `pg_hba.conf` from the pre-change recovery backup. It refuses unless the backup exists and its SHA-256 equals the hash recorded in `RecoveryBackup.ConfigBackups`. It writes those bytes and verifies the live file hash.
- `Reset-PostgresPasswordAutomatically` uses the recorded hash (not an in-memory copy) and refuses before mutation if the backup does not match it. Both the success restore and the catch-path retry use the helper.
- If the restore fails, the result is ACTION_REQUIRED with ReasonCode `MANUAL_RECOVERY_REQUIRED`. The reason names the exact `pg_hba.conf` path and the backup path. `$script:PostgresManualRecoveryRequired` is set to the live path.
- `Test-PostgresManualRecoveryRequired` gates `Reset-PostgresPasswordAutomatically`, `Invoke-PostgresSelectedPasswordRecovery`, and `Invoke-RestorePostgresBackup`. While the flag is set, they return ACTION_REQUIRED before any password use or database mutation. The setup pass does not clear the flag.
- Restore wording (#336 sites): success text now reads "Restore completed; verification: <check>", where the check is the transaction outcome for PostgreSQL restores, or "every file copy completed without error" for file restores. Sites: Invoke-RestorePostgresBackup success branch, restore menu status step and final message.

## Residual gap (not fixed here)

- The trust line on disk survives a process restart. The flag is session-scoped. A new TPM process does not know about it; the existing AUTHENTICATION_POLICY_UNSAFE guard still blocks recovery while the trust line is present, but other entry points are not gated. Manual restoration of `pg_hba.conf` is required.
- If the file is unwritable, TPM cannot remove the trust line; the user must restore it manually.

## Not run

No Pester, tests, gates, smoke runs, or packaging (owner hold).
