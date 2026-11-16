# RC8 Blocker Reconciliation - Lane F

Worktree: <test-pc-repos>\tpm-rc8-lane-F-blockers (HEAD ba54ae5 plus untracked TpmProgress files).
Source file: TeknoParrot-Manager.ps1.
Line numbers are worktree line numbers. Issue bodies cite baseline 18e82a7 (about 58 lines lower in the Save-Config and migration area). #364, #368, and #369 cite script SHA256 7ebfda42.
Method: static reads only. No Pester, tests, gates, smoke, or diagnostics were run (owner hold).

Historical evidence: FIX108 supersedes row #342's outcome and field names. Missing-reference games now use `DesignSkippedItems` and are informational skips, not failed or missing-copy items; any real save failure still produces an error.

## Status key

- FIXED-IN-SOURCE (file:line): defect fixed in this lane.
- DEFECT-CONFIRMED-UNFIXED (reason): defect real in source; not fixed because it needs a design decision or spans multiple sites.
- NO-EVIDENCE (what was searched): no code-level defect found.
- ALREADY-FIXED (prior commit/line): present in ba54ae5 before this lane.

## Blocker table

| Issue | Status | Evidence (worktree file:line) | Notes |
|---|---|---|---|
| #337 LaunchBox false success on direct write | FIXED-IN-SOURCE | `Invoke-LaunchBoxDirectWrite` 30366-30490: `$attemptedPaths` recorded before each `Save-Xml` (30475-30490); catch returns `Failed = $true`, `AttemptedPaths`, `BackupPath`. Caller 36783-36794 prints a partial-update message with backup path and restore guidance when attempted paths exist, otherwise "No changes were made". | Action-required partial state, no rollback. Slice: `docs\remediation\slices\TPM-RC8-LANE-F-337.md`. |
| #335 LaunchBox backup copy errors ignored | FIXED-IN-SOURCE | `Backup-LaunchBoxFiles` 28542: `Copy-Item ... -ErrorAction Stop`. Before the fix, nonterminating copy errors skipped the catch (28544) and the function returned `$backupPath` (28554). | Slice: `TPM-RC8-LANE-F-335.md`. |
| #336 LaunchBox restore copy errors ignored | FIXED-IN-SOURCE | `Invoke-RestoreLaunchBoxBackup` restore loop 28671: `Copy-Item ... -ErrorAction Stop`. Before the fix, failures did not increment `$errCount`, and `Succeeded = $true` was returned (28688). | Caller 33990 prints "Restore finished and was verified" near 34002. That wording overstates the check (no readback is performed). Not changed; noted for the wording owner. Slice: `TPM-RC8-LANE-F-336.md`. |
| #364 DgVoodoo2 empty operation list | FIXED-IN-SOURCE | `Invoke-TpmDgVoodoo2FileTransaction` parameter 6171: `[Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Operations`. Caller 14360 passes `$deploymentOperations.ToArray()`, which may be empty. Shared routine 5468-5480 handles empty input. | Slice: `TPM-RC8-LANE-F-364.md`. |
| #342 No-archetype items dropped on non-SUCCEEDED propagation | FIXED-IN-SOURCE | `$noArchetypeItems = @($propResult.NoArchetypeItems)` moved ahead of the SUCCEEDED gate at 36541 (was inside the gate). Producer 27978 (`NoArchetypeItems = $noArchetype`). Consumers 37188-37193 and 37673-37677. Default `@()` at 36482. | `PARTIAL_APPLIED` is the normal case when no-archetype items are present (27646-27647), so the old placement dropped them in practice. Slice: `TPM-RC8-LANE-F-342.md`. |
| #334 Settings-only mutation omitted from transaction | FIXED-IN-SOURCE (current dirty integration) | `Invoke-ControlPropagation` reports `settings-only` after `Save-XmlMaybe` (`TeknoParrot-Manager.ps1:28643-28649`); `$written` includes it (`28387`), drives `ChangedItems`, `CompletedItems`, outcome, and `MutationStarted` (`28390-28391`). `BoundCount` remains based on binding-only `$changed` to preserve the distinct controls-bound count. | Runtime unverified. |
| #331 Migration over occupied destination; startup overwrites managed config | FIXED-IN-SOURCE (current dirty integration) | `Test-TpmOwnedMigrationStartupAllowed` blocks `DESTINATION_OCCUPIED` and `DESTINATION_UNVERIFIED` (`TeknoParrot-Manager.ps1:706-719`); the startup caller exits before normal workflows and displays destination-path evidence (`33039-33063`). | Source matches intended gate; runtime unverified. |
| #332 Migration backup ACL and rollback recovery | ACL and in-process failure classification FIXED-IN-SOURCE; crash recovery remains manual | The migration rejects an existing backup root, checks the path before/after creation, and applies its ACL before copies (`TeknoParrot-Manager.ps1:535-542`); copied trees are locked before manifest acceptance (`550-552`, helper `15654-15684`; directory ACL helper `15626-15632`). `Invoke-TpmOwnedMigration` treats a throwing in-flight move as unverified, preserves occupied source paths, and does not claim verified rollback when no move completed (`454-705`). The startup gate blocks `CLEANUP_RESIDUE` and unresolved destinations and prints evidence paths (`706-719`, `33039-33063`). Durable journaling and recovery after process interruption remain open; see `TPM-RC8-LANE-R-332.md`. | No automatic overwrite of unsafe residue. ACL/filesystem behavior unverified under owner hold. |
| #338 Backup writers and restore defaults still use PSScriptRoot after migration | FIXED-IN-SOURCE (current dirty integration) | `Get-TpmOwnedBackupsRoot` selects each backup tree (`LaunchBoxBackups`, `PostgresBackups`, `PostgresRecoveryBackups`) independently: a managed-only folder is used, a legacy-only folder beside the script is used without moving anything, and a managed folder plus a legacy folder of the same name throws ("preserve both and resolve the conflict") rather than being merged (`TeknoParrot-Manager.ps1`, function `Get-TpmOwnedBackupsRoot`). Current LaunchBox/PostgreSQL writer and restore defaults use that accessor. The startup migration does not move the backup histories collectively: `Get-TpmLegacyOwnedItems` relocates only `PostgresRecoveryBackups` (private recovery evidence) to the owned Backups folder through the protected-ACL copy path, and `LaunchBoxBackups` and `PostgresBackups` stay where they are. An occupied managed destination fails the migration before any change (`DESTINATION_OCCUPIED`). | Runtime unverified. |
| #340 PostgreSQL health status and profile inventory can be overstated after failed queries | FIXED-IN-SOURCE (status display and fail-closed inventory) | `Invoke-LibraryHealthCheck` queries service state and `psql.exe` path (`TeknoParrot-Manager.ps1:27438-27442`). Discovery/classifier errors set inventory `Error`/`Unknown`; PostgreSQL counts are withheld unless `Complete`, result is `ACTION_REQUIRED`, and setup choice `P` is gated in both presenter and dispatcher (`27241-27303`, `27443-27460`, `27502-27530`, `27541-27546`, `34798`). `Test-PostgresInstalled` remains a separate Boolean installation gate. | Runtime UNVERIFIED; no owner-approved execution. |
| #341 Icon/thumbnail write without containment | FIXED-IN-SOURCE (current dirty integration; checks are not atomic) | `Invoke-ThumbnailDownload` rejects an unsafe Icons path chain (`TeknoParrot-Manager.ps1:31303-31306`), checks the custom-copy destination before `Copy-Item` (`31366-31367`), and downloads through `Invoke-TpmDownload`, which checks the final destination before promotion (`19485-19490`, `19578-19590`). | Static guards do not eliminate check/write races. Runtime unverified. |
| #368 AutoSync target uses GamePath parent | FIXED-IN-SOURCE (current dirty integration) | `Resolve-RegisteredGameFolder` canonicalizes `GamePath`, rejects paths outside `InstallFolder` and paths whose candidate is the root itself, then ascends to the immediate child under `InstallFolder` (`TeknoParrot-Manager.ps1:27747-27783`). This matches the root-level `Get-StagingFolderMap` shape (`27624-27637`) and the resolver passes that folder to AutoSync as the transaction target (`18753-18759`). | Runtime unverified; ambiguous paths return no registered-folder match rather than use an executable's immediate parent. |
| #369 ZIP empty-directory parents not counted | ALREADY-FIXED | `Get-TpmAutoSyncZipInventory` 4895-4914: ancestor synthesis iterates every record in `$recordsByKey` (4896), including directory entries, and adds absent parents as directories (4906-4911). Issue cites file-only synthesis at baseline 4900; that form is not in ba54ae5. | `git log -S` was not run (no execution). Status rests on the current source. |
| Postgres stale trust rule after failed auth-policy restore | SOURCE FAIL-CLOSED; manual service recovery remains possible | On unconfirmed service stop, source persists and reads back `ServiceStopUnconfirmed` before attempting restore (`TeknoParrot-Manager.ps1:16208-16227`; marker writer `15809-15823`). Marker reconciliation clears or restores only after observing the service Stopped (`15864-15884`); password-operation guards use the marker state. Failure output names the trust residue and backup, and the outer path blocks restart (`16243-16257`, `35336-35353`). | If PostgreSQL remains running, its loaded trust rule may remain active until manual stop; TPM blocks subsequent password operations and does not restart it. Runtime unverified. |
Continuation correction: `Get-PostgresTrustRuleMarkerState` now walks existing recovery-root ancestors with terminating `Get-Item` calls before accepting a missing marker as `None`; an existing recovery root must be a non-reparse directory with a current-user-only ACL (`TeknoParrot-Manager.ps1:15933-15981`). This prevents unsafe, inaccessible, wrong-type, or ACL-weakened marker storage from being mistaken for “no pending recovery.” Static-only; runtime unverified.


## Known-fixed items not re-touched

#339, #333, #366, #367, the PostgreSQL MZ/PE guard (`Test-PostgresToolExecutable`), and `$script:PostgresAuthPolicyRestoreBlocked` were not modified.

## Source changes in this lane

- TeknoParrot-Manager.ps1: 6171, 28542, 28671, 30475-30490, 36783-36794 (#337, #335, #336, #364), and 36541-36543 (#342).
- Slice contracts: docs\remediation\slices\TPM-RC8-LANE-F-335.md, -336.md, -337.md, -342.md, -364.md.
- This report.

## Verification (static, no execution)

- Edited regions read back after each edit. The #342 hunk reads back as 36541-36543 with the else branch at 36549-36551 unchanged.
- Edited text is ASCII (uses `--` and `->` only where needed). A byte count was not run (owner hold on execution).
- Parse check by reading: the four #337/#335/#336/#364 hunks and the #342 hunk keep matching braces and pipelines.

## Blockers needing owner or design decision

#331, #332, #334, #338, #340, #341, #368, and the Postgres trust rule. Each needs one of: a design choice on the fix, multi-site scope, or the owner principal for ACLs.
