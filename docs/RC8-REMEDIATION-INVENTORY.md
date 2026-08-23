# RC8 Remediation Specification and Invariant Inventory

This inventory is limited to the RC8 gate fixes on the RC7-descended remediation
branch. It does not authorize profile-pack import, broad control mapping, PCSX2x6
support, or any other post-1.0 feature.

## Specification inventory

| ID     | Area                      | Governing behavior                                                                                                                                                                                                                                                             | Implementation/test pointer                                   |
| ------ | ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------- |
| PG-S01 | PostgreSQL recovery       | A password reset must be performed by TPM after secure intake. The reset uses PostgreSQL 8.3 single-user mode with SQL on standard input; it must not require a follow-up command.                                                                                             | Reset-PostgresPasswordAutomatically; success/failure tests    |
| PG-S02 | PostgreSQL recovery       | Recovery changes only the postgres role password. It must not drop, recreate, restore over, or wipe a database.                                                                                                                                                                | Reset-PostgresPasswordAutomatically; no-data-wipe boundary    |
| PG-S03 | PostgreSQL backup         | Before stopping the service, resetting the role, or writing a profile, TPM must create and verify evidence containing relevant configuration and every affected profile.                                                                                                       | New-PostgresRecoveryBackup; backup-first tests                |
| PG-S04 | PostgreSQL credentials    | A .pgpass file is temporary, ACL-locked, never logged, removed in finally, and cleanup failure is an operation failure. The process environment is restored exactly.                                                                                                           | New/Remove-PostgresPgPassFile; redaction tests                |
| PG-S05 | TeknoParrot compatibility | The UserProfile Pass field remains plaintext only because TeknoParrotUI consumes it directly. TPM writes only after verified backup, never reports its value, and skips profiles whose value already matches.                                                                  | Invoke-PostgresGameSetup; multi-profile tests                 |
| PG-S06 | Installer boundary        | MSI public properties cannot be hidden from OS process inspection. TPM does not request a verbose MSI log, never logs raw arguments, clears password variables after the synchronous call, and documents the residual window.                                                  | Install-Postgres83; source review                             |
| EG-S01 | Eggman destination        | A safe configured/default destination is accepted without an unnecessary Browse prompt.                                                                                                                                                                                        | Invoke-EggmanDatDownloadInteractive; zero-prompt fixture      |
| EG-S02 | Eggman destination        | Every configured or user-selected destination is canonicalized and revalidated before reuse, download, or write.                                                                                                                                                               | Invoke-EggmanDatDownloadInteractive; unsafe no-download tests |
| BX-S01 | BepInEx target            | Each candidate root must be inside the approved games root and every existing path component must be non-reparse before update discovery can lead to a prompt, download, backup, or transaction.                                                                               | Test-BepInExGameRootSafe; no-write tests                      |
| BX-S02 | BepInEx transaction       | ZIP extraction occurs in isolated staging. Backup creation is verified before promotion. Live promotion rolls back all promoted files on failure; rollback failure preserves evidence and is never reported as success.                                                        | Invoke-TpmTransactionalTreePromote; rollback tests            |
| BX-S03 | BepInEx cleanup           | Recursive staging cleanup is limited to a canonical non-reparse `BepInEx-*` directory under the controlled TPM staging root. A post-promotion cleanup failure preserves residue, reports ACTION REQUIRED with the validated path, and is excluded from the clean-update count. | Remove-BepInExStagingDirectory; cleanup result tests          |

## System invariant inventory

| ID        | Invariant                                                                                                                                                                                                                                                           | Status requirement                            |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| INV-PG-01 | Existing PostgreSQL data is never deleted or recreated by guided password recovery.                                                                                                                                                                                 | Must hold on success and failure              |
| INV-PG-02 | A failed reset, service restart, configuration backup, profile backup, or profile write cannot produce a recovery-complete result.                                                                                                                                  | Must fail closed                              |
| INV-PG-03 | Passwords never appear in logs, summaries, console output, command arguments constructed for display, test artifacts, or issue output. The unavoidable TPUI Pass field and ACL-locked exact-recovery backup are documented local compatibility/evidence boundaries. | Must hold outside those bounded files         |
| INV-PG-04 | Profile XML writes are deterministic by filename and occur only after all affected profiles have been backed up.                                                                                                                                                    | Must hold for multi-profile runs              |
| INV-EG-01 | Unsafe Eggman paths are rejected before any download or destination write.                                                                                                                                                                                          | Must hold for default and user-selected paths |
| INV-BX-01 | No BepInEx live path is touched until root safety, digest, staging extraction, and backup verification pass.                                                                                                                                                        | Must hold for all candidates                  |
| INV-BX-02 | A recoverable BepInEx promotion failure restores the complete pre-operation tree; an unrecoverable failure preserves evidence and reports blocked.                                                                                                                  | Must hold in rollback matrix                  |
| INV-BX-03 | An applied BepInEx update is counted as clean only after its validated staging directory is removed. Cleanup failure preserves the exact validated residue path and produces ACTION REQUIRED output.                                                                | Must hold after successful promotion          |

## Adversarial review cases required before handoff

- Empty or mismatched secure password input.
- Password containing SQL quotes, backslashes, colons, and newline characters.
- Missing or ACL-unlockable .pgpass cleanup.
- PostgreSQL service stop/start failure and single-user reset nonzero exit.
- Missing pg_hba.conf or postgresql.conf evidence copy.
- Existing database with profile password already correct, empty, and stale.
- Duplicate database names across deterministically ordered profiles.
- BepInEx root outside the approved games root, a reparse root, an intermediate
  reparse component, and a reparse leaf.
- Failed BepInEx backup, failed staged extraction, digest mismatch, promotion
  failure, rollback failure, and ordinary staging cleanup failure.
