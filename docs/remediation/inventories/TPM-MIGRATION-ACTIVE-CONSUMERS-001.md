# Active consumer migration inventory

Contract: TPM-MIGRATION-ACTIVE-CONSUMERS-001; owner 34 / #323.

When this contract was written, the prior allowlist contained 26 entries and
five active source-root operational entries were retained. That count is
superseded in part: later RC8 work relocates PostgresRecoveryBackups (see its
row), so four active entries remain at the program root. Generated diagnostic
reports are archives, not settings or recovery lookup inputs. The controls
report and the Action Items report are now written to the managed Reports
folder.

| Prior entry | Disposition | Current consumer / verification |
|---|---|---|
| TeknoParrot-Manager.config.json | State, unchanged | Startup assigns managed ConfigPath after migration. |
| TeknoParrot-Manager.log | Logs, unchanged | Startup assigns managed LogPath after migration. |
| TeknoParrot-Manager-controls.txt | Reports archive, unchanged | Current producer writes to the managed Reports folder; older copies beside the script are diagnostic archives. |
| TeknoParrot-Manager-ActionItems.txt | Reports archive, unchanged | Current producer defaults to the managed Reports folder with an optional Save dialog destination; migrated historical copies are diagnostic archives, not the fresh producer path. |
| TeknoParrot-Manager-HealthCheck.txt | Reports archive, unchanged | Diagnostic output, not configuration or recovery input. |
| TeknoParrot-Manager-Readiness.txt | Reports archive, unchanged | Diagnostic output, not configuration or recovery input. |
| TeknoParrot-Manager-TeknoParrotUI-Troubleshooting.txt | Reports archive, unchanged | Diagnostic output, not configuration or recovery input. |
| TPM-Validation-Report.md | Reports archive, unchanged | Historical maintainer diagnostic. |
| TPM-Validation-Report.json | Reports archive, unchanged | Historical maintainer diagnostic. |
| TPM-Certification-Scorecard.md | Reports archive, unchanged | Historical maintainer diagnostic. |
| TPM-Certification-Scorecard.json | Reports archive, unchanged | Historical maintainer diagnostic. |
| TPM-Certification-Final-Outcome.md | Reports archive, unchanged | Historical maintainer diagnostic. |
| TPM-Certification-Final-Outcome.json | Reports archive, unchanged | Historical maintainer diagnostic. |
| TPM-Certification-Manifest.md | Reports archive, unchanged | Historical maintainer diagnostic. |
| TPM-Certification-Manifest.json | Reports archive, unchanged | Historical maintainer diagnostic. |
| TeknoParrot-Manager.overrides.json | Retain program root | Actual startup assignment/template/loader uses PSScriptRoot; real before/after regression. |
| LaunchBoxBackups | Retain program root | Backup-LaunchBoxFiles and Invoke-RestoreLaunchBoxBackup default; actual default-expression regression. |
| PostgresBackups | Retain program root | New database backup path and Invoke-RestorePostgresBackup default; actual default-expression regression. |
| PostgresRecoveryBackups | SUPERSEDED: relocated (originally "Retain program root") | Private recovery evidence is moved to the managed `Backups\PostgresRecoveryBackups\` through the protected-ACL copy/move path (`Get-TpmLegacyOwnedItems`). A managed copy and a legacy copy existing together are refused as an occupied destination (`DESTINATION_OCCUPIED`), and `Get-TpmOwnedBackupsRoot` throws when both exist; neither copy is merged or deleted. |
| SupportPackages | Flatten into SupportPackages, unchanged | Owned package result path and retained archives. |
| ReShade | Assets, unchanged | Managed Assets consumer and configured-source rebinding. |
| ReShadePresets | Assets, unchanged | Managed Assets preset consumer. |
| ReShadePreviewCache | Cache, unchanged | Managed preview Cache consumer. |
| CustomThumbnails | Assets, unchanged | Managed custom-thumbnail Assets consumer. |
| FFBPlugin | Cache, unchanged | Existing FFB setup uses managed Cache path. |
| BepInExCache | Retain program root | Existing BepInEx setup passes program-root CacheDir; actual assignment regression. |

## Required system invariants

| ID | Invariant | Coverage |
|---|---|---|
| MAC-1 | Migration never disconnects an active settings/recovery/cache consumer from its existing bytes. | Six preservation cases across overrides and four directory families. |
| MAC-2 | Decline, destination collision, and failed safety backup preserve active legacy state. | Three independent safeguard cases. |
| MAC-3 | Other managed-state migration and verified backup-before-move remain unchanged. | Accepted log migration case plus existing full migration suite. |
| MAC-4 | Previously moved artifacts are preserved and are never adopted or overwritten by filename guesses. | Deliberate exclusion from this fix; owner-runtime preflight/manual review required. |

No external file-format grammar changes are made. The governing rule here is
the existing internal migration/consumer-location contract. This component
requires a system-invariant inventory because it performs transactional moves.