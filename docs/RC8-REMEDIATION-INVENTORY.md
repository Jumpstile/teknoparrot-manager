# RC8 Remediation Specification and Invariant Inventory

This inventory is limited to the RC8 gate fixes on the RC7-descended remediation
branch. It does not authorize profile-pack import, broad control mapping, PCSX2x6
support, or any other post-1.0 feature.

## Skylinekiller hold evidence

External tester: Skylinekiller
Support package: `TeknoParrotManager-Support-20260902-161402.zip`
SHA-256: `6a2fa446e09dc795748773ea542e75576715ced9b7803b750cfe71c90d8763ab`
Entries: 5
This evidence remains a remediation hold record, not runtime certification:

- ReShade: partial installation occurred and errors occurred. The stale
  `No local ReShade source was found` / setup incomplete wording appeared
  despite source acquisition/install activity. Missing-device failures must be
  classified as safe skips.
- dgVoodoo2: BattleFantasia was auto-detected as a legacy API game, then
  deployment failed with `A device which does not exist was specified.` The
  result must be a missing-device/path skip, not a generic deployment failure.
- GPU Compatibility Fix: setup fatally aborted with
  `A device which does not exist was specified.` The result must be a
  per-game safe skip, not a script-aborting fatal.
- BepInEx: 15 games reported update blocked, and rollback-failure/update-blocked
  evidence was present in the support log. Missing device/path, protected or
  unowned files, rollback failure, and update blocked must remain separate
  reason categories.

## Post-0909174 runtime hold evidence

Support package: `TeknoParrotManager-Support-20260903-032415.zip`
SHA-256: `D206E58D3492F83877E04F610A7D66B509EAFBB7E3813D97E0F1706CF3E802F2`
Entries: 11

This evidence is a remediation hold record, not runtime certification. The
ReShade log records repeated empty-`CacheRoot` parameter binding failures,
with 51 generic errors and no deployment. The transcript also confirms that
preview reopen reported only "unavailable", bulk Apply All asked per-game
reapply questions for a different saved profile, and Before/After did not
teach a visible difference. The source-signature message did not explain
download source, hash/size validation, Authenticode status, or whether it was
safe to continue.

Separately, the crosshair picker needs intermediate browser feedback after P1
selection and before P2 selection. The selected P1 tile must be highlighted,
typed numeric fallback must remain available, and deployment must remain
behind terminal confirmation.

## Post-0909174 GPU Fix runtime hold evidence

Support package: `TeknoParrotManager-Support-20260903-033006.zip`
SHA-256: `CAADEC33984E9349B206CF94E4A73DAB2CC5E082E295BEE593BAE75763BAEF80`
Entries: 11

The runtime detected NVIDIA Quadro P620, created a backup, updated zero
games, left 51 unchanged, skipped four missing saved executables
(2Spicy, AkaiKatanaShinNesica, BBHPro, BBHWorld), and reported zero errors.
The operation was safe but the result cleared too quickly for the user to
understand. The remediation must keep the result visible until acknowledgment,
explain each skip in beginner language with a next action, and provide a
separate technical Details view.

## Post-0909174 BepInEx runtime hold evidence

Support package: `TeknoParrotManager-Support-20260903-033354.zip`
SHA-256: `C404AF1E5F8CB3E1742B55B77AD18FAAA2262EB22E58BAB273F1C32E374606FF`
Entries: 11

BepInEx safely preflight-skipped four missing executables and one protected or
reparse-backed root, but 15 approved updates reported rollback failure and one
reported an unverifiable destination parent. TPM did not claim success. The
remediation must preserve the exact rollback operation, exception, evidence
paths, and post-failure file state; group common failures, stop repetition,
offer repair-reset and Details, and explain destination resolution failures
with full canonical paths.

The remediation now returns structured failure records, preserves exact
per-game roots/staging/backup paths and exception text, groups rollback
failures by a stable operation/exception-type key, stops repeated same-cause
candidate processing, and exposes repair-reset, Details, and support/log
guidance. Runtime certification remains held until the approved live
installation is exercised.

## Post-0909174 PostgreSQL runtime hold evidence

Support package: `TeknoParrotManager-Support-20260903-034015.zip`
SHA-256: `69BBDCD82B696889EE58FA95D9782D57F33C8BB0CF77B5D7351A24D07D4F4313`
Entries: 11

PostgreSQL recovery still fails the user-runtime gate. The saved postgres
password was rejected for six affected databases. A mismatched replacement
password returned the user to the full backup-failure wall, and Details
repeated raw psql and PowerShell errors instead of grouping the common cause.
The log later recorded a validated replacement password, but the workflow did
not clearly retry and complete the protected backup. This is a primary blocker:
recovery must be self-contained, grouped, status-accurate, password-safe, and
must explain every post-validation state transition.

## Release-gate UX invariant

TPM is beginner-friendly by default. A user who only wants to play games must
not need to understand PowerShell, PostgreSQL, XML, ACLs, reparse points,
BepInEx internals, permissions, or elevation. Every skipped, blocked, or failed
item must explain what happened, why it happened, what TPM did or did not
change, and what the user should do next. Normal screens remain readable and
wait for acknowledgment; technical details remain available separately.
The acceptance question is whether a 14-year-old can complete the workflow
without specialist knowledge.

The shared mutation-path invariant below is the required response to the
missing-device findings. No affected workflow may promote or mutate a game
until its registered path is revalidated at the mutation boundary.

## Superseded PostgreSQL password-reset requirements

FIX95 (owner rule R4) removed the automatic postgres password reset. The old
reset added a `host all postgres 127.0.0.1/32 trust` line to `pg_hba.conf`; a
crash or power cut could leave that line behind and let any local program log
in as postgres. TPM now fails closed: choosing `X` ("I do not know the
password") runs `Show-PostgresPasswordResetUnavailable`, which changes nothing
and shows manual recovery steps under Details. The password reaches the
PostgreSQL tools through the process `PGPASSWORD` variable, restored
afterwards; no `.pgpass` credential file is created.

The rows marked SUPERSEDED below (PG-S01 to PG-S04, PG-S08 to PG-S10,
INV-PG-02, INV-PG-10, INV-PG-11) record historical reset and credential-file
requirements. They are not implemented behavior. Only these parts still hold:
password recovery never drops, recreates, restores over or wipes existing
PostgreSQL data (the separately confirmed restore and Reinitialize choices
do replace database content after you type YES); a verified backup comes
before any profile write; passwords are never logged.


## Specification inventory

| ID     | Area                      | Governing behavior                                                                                                                                                                                                                                                             | Implementation/test pointer                                   |
| ------ | ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------- |
| PG-S01 | PostgreSQL recovery       | SUPERSEDED by the current fail-closed policy; not implemented. Historical requirement: a password reset is performed by TPM after secure intake, using a temporary localhost-only authentication rule, SQL on standard input, and a hash-verified restore of the original authentication policy. TPM now refuses the automatic reset (`Show-PostgresPasswordResetUnavailable`) and shows manual steps. | Show-PostgresPasswordResetUnavailable; fail-closed tests |
| PG-S02 | PostgreSQL recovery       | SUPERSEDED in part. Historical requirement: recovery changes only the postgres role password. TPM no longer changes the role password. Still in force: the password choices (F, P, X) must not drop, recreate, restore over, or wipe a database. The separately confirmed restore and Reinitialize (I) choices do replace database content after typed confirmation. | no-data-wipe boundary for password recovery |
| PG-S03 | PostgreSQL backup         | SUPERSEDED in part. Historical requirement: create and verify evidence before stopping the service or resetting the role, and save configuration after reset verification. There is no reset now. Still in force: a verified backup comes before any database or profile mutation. | New-PostgresRecoveryBackup; ordering and cutoff tests |
| PG-S04 | PostgreSQL credentials    | SUPERSEDED; not implemented. Historical requirement: a temporary ACL-locked .pgpass file. TPM now passes the password through the process `PGPASSWORD` variable for one tool run, restores the previous value exactly, never logs it, and creates no credential file. Legacy .pgpass cleanup remains. | Invoke-PostgresNativeCommand; redaction tests |
| PG-S05 | TeknoParrot compatibility | The UserProfile Pass field remains plaintext only because TeknoParrotUI consumes it directly. TPM writes only after verified backup, never reports its value, and skips profiles whose value already matches.                                                                  | Invoke-PostgresGameSetup; multi-profile tests                 |
| PG-S06 | Installer boundary        | MSI public properties are passed through the in-process Windows Installer Automation interface, not a password-bearing child command line. TPM does not request verbose logging, does not log the property string, clears password variables after the call, and verifies the installed service. | Install-Postgres83; source and runtime smoke tests    |
| PG-S07 | PostgreSQL elevation UX   | UAC carries only a random path to a DPAPI-authenticated complete envelope. A durable issuance identity is protected in the payload and bound to the legal filename; nonce/attempt are recorded in the one-time tombstone. Claim validation failure restores the encrypted challenge and removes temporary markers. The child binds exact hashes, paths, origin identity, parent executable/start identity, and five-minute lifetime. UAC denial reuses the untouched challenge; started-child failure mints a fresh attempt. Immediately before every non-admin install/recovery/reinitialize handoff, normal mode explains temporary administrator access, the local PostgreSQL purpose, the UAC prompt and Yes action, automatic continuation without relaunch/reselection, and temporary scope; no implementation mechanics appear. | Start-PostgresRecoveryAsAdministrator; adversarial state and guidance-order tests |
| PG-S08 | PostgreSQL recovery UX   | SUPERSEDED in part. The reset-related parts (verified backup before reset, verifying the new password before saving it) are historical; there is no reset now. Still in force: when the saved password is unusable, TPM explains the problem in plain words, offers `F`/`P` to type the existing password, offers `X` only after a positive rejection (it explains why there is no reset and changes nothing), keeps raw client diagnostics behind Details, asks for masked input, suppresses unrelated DAT/GitHub prompts during protected resume, and keeps ordinary messages visible until acknowledged. | Read-ConfirmedPostgresPassword; Show-PostgresPasswordResetUnavailable; Read-PostgresRecoveryState; protected-resume terminal probes |
| PG-S09 | PostgreSQL service state | SUPERSEDED in part. Historical requirement: keep PostgreSQL running through reset authentication. There is no reset now. Still in force: the original service state is restored, and a restoration failure blocks completion. | Restore-PostgresServiceState; transaction cutoff tests |
| PG-S10 | PostgreSQL recovery retry | SUPERSEDED in part. Historical requirement: a protected retry may carry a password only after the new password was authenticated, and a committed `ALTER ROLE` followed by failed authentication is a mutation cutoff. TPM no longer issues `ALTER ROLE`. Still in force: no protected retry may carry a credential that was not verified against the live server. | Exit-PostgresRecoveryResume; committed-authentication-failure probe |
| PG-S11 | PostgreSQL 8.3 rollback | PostgreSQL 8.3.23 `dropdb` accepts its documented database, echo/interactive, host, port, username, and password options; it does not document `--if-exists`. Rollback must verify current database state, skip a drop when verified absent, otherwise call `dropdb` without unsupported options, then verify absence. | `Invoke-Postgres83DropDatabaseVerified`; restore/setup transaction tests |
| PG-S12 | PostgreSQL setup transaction | Database creation returns structured mutation boundary, state, command receipts, and failure stage; the setup transaction owns one rollback pass and includes the failed database only when creation may have begun. Pre-mutation rejection cannot authorize dropping a database that appeared after planning. | `New-PostgresDatabaseFromBackup`; `Invoke-PostgresGameSetup`; setup rollback tests |
| PG-S13 | PostgreSQL restore rollback evidence | Persisted per-database receipts are refreshed after rollback so they include the failing item and final rollback attempts/verification; an item with unverified rollback is `UNKNOWN`, never simultaneously `COMPLETED`. If the refresh write fails, clear the advertised receipt path and preserve the recovery root with an explicit error and incomplete cleanup. | `Invoke-PostgresRestoreTransaction`; multi-item rollback receipt tests |
| PG-S14 | PostgreSQL restore creation ownership | A failed `createdb.exe` does not grant TPM authority to drop a database observed after failure. Rollback may drop a present database only after successful TPM creation; when a pre-existing target was dropped but replacement creation fails, restore only if a fresh state check confirms absence, otherwise preserve the observed database and report unknown. | `Invoke-Postgres83RestoreDatabase`; `Restore-Postgres83DatabaseFromReceipt`; collision tests |
| PG-S15 | PostgreSQL restore receipt persistence failure | A failed post-rollback receipt refresh clears `ReceiptPath`, exposes `ReceiptError`, retains the evidence root, and reports `CLEANUP_RESIDUE` with cleanup incomplete when rollback is verified; it never deletes the only remaining transaction evidence or advertises stale JSON as current. | `Invoke-PostgresRestoreTransaction`; receipt-refresh failure test |
| EG-S01 | Eggman destination        | A safe configured/default destination is accepted without an unnecessary Browse prompt.                                                                                                                                                                                        | Invoke-EggmanDatDownloadInteractive; zero-prompt fixture      |
| EG-S02 | Eggman destination        | Every configured or user-selected destination is canonicalized and revalidated before reuse, download, or write.                                                                                                                                                               | Invoke-EggmanDatDownloadInteractive; unsafe no-download tests |
| EG-S03 | Eggman path roles         | An external primary ZIP/source folder may be an explicit DAT destination when it is reachable, non-reparse, outside protected roots, and revalidated before the final move; supplementary and ambiguous source roles are never auto-selected.                                  | Get-EggmanDatPathRole; fallback/reparse/role tests             |
| BX-S01 | BepInEx target            | Each candidate root must be inside the approved games root and every existing path component must be non-reparse before update discovery can lead to a prompt, download, backup, or transaction. Integrity health checks must also identify incomplete current-version trees so repair-reset remains reachable.                                                                               | Test-BepInExGameRootSafe; no-write tests                      |
| BX-S02 | BepInEx transaction       | ZIP extraction occurs in isolated staging. Backup creation is verified before promotion. Live promotion rolls back all promoted files on failure; rollback failure preserves evidence and is never reported as success.                                                        | Invoke-TpmTransactionalTreePromote; rollback tests            |
| BX-S05 | Shared game mutation path | ReShade, dgVoodoo2, GPU-fix, and BepInEx validate the registered executable path immediately before inspection and again at the mutation boundary; unavailable devices, missing leaves, inaccessible/reparse paths, and resolution changes are classified and never mutated. | Test-TpmGameMutationPath; workflow preflight/boundary tests |
| BX-S03 | BepInEx cleanup | Recursive staging cleanup is limited to a canonical non-reparse `BepInEx-*` directory under the controlled TPM staging root. A post-promotion cleanup failure preserves the exact residue path in the typed `CLEANUP_RESIDUE` result and Details, retains the underlying product outcome without fabricating an incomplete game item, reports ACTION REQUIRED, and is excluded from the clean-update count. | Remove-BepInExStagingDirectory; cleanup result tests |

| FFB-S01 | FFB plugin ownership   | TPM records each deployed hook with game-root/path/source/deployed hashes and removes it only when the current file still matches the recorded ownership. Unowned or changed hooks remain untouched. | Write/Remove-FFBPluginOwnership; ownership tests |
| UX-S01  | Workflow status        | Multi-step workflows expose structured real-step status, pinned failures, deterministic close/failure cleanup, explicit single-owner serialization, resize-safe footer/append-only fallback, unknown-step rejection, and no cursor writes in redirected/unattended/certification runs. | New/Publish/Render-TpmWorkflowStatus; resize tests |
| BX-S04 | BepInEx refusal UX        | An unsafe game root is refused before release discovery with a beginner-readable reason, a concrete path/root correction action, and an explicit no-download/no-write statement. | Write-BepInExUnsafeRootGuidance; refusal-message tests         |
| UX-S02  | Restore recovery        | Preserve the selected backup and wait for TeknoParrot/LaunchBox to close; never force-close unsaved user work; report only verified completion. | Invoke-RestoreBackup; restore recovery tests |
| UX-S03  | Crosshair lock          | Keep the selected operation pending while PCSX2 closes; do not silently rerun or claim deployment when the lock remains. | Wait-TpmForProcessClose; crosshair tests |
| UX-S04  | TeknoParrotUI ownership | TPM never downloads profiles and never starts TeknoParrotUI. By owner decision (FIX28) it no longer checks whether GameProfiles/Metadata look missing or stale and shows no notice or offer to open TeknoParrotUI; games it cannot match stay in the normal ACTION REQUIRED report. TPM does not edit ParrotData, controls, DAT, or XML-owned setup state. | Source review: no TeknoParrotUi.exe launch in TeknoParrot-Manager.ps1; registration ACTION REQUIRED tests |
| UX-S05  | Optional downloads      | Automatic ReShade/dgVoodoo2 acquisition retries or offers an explicit advanced existing-file path; signature/digest gates remain mandatory and cancel is truthful. | Invoke-ReShadeSetup; Invoke-DgVoodoo2Setup |
| UX-S06  | Registration ambiguity  | Present validated candidate profiles for an explicit choice; blank/invalid input leaves the case unresolved instead of guessing. | Invoke-ManualRegistrationChoices; registration tests |
| UX-S07  | Health boundaries       | Missing firmware/components remain contract-backed, read-only warnings with a legitimate-source/TPUI repair handoff; TPM does not fabricate or replace vendor files. | Get-CompatibilityWarnings; health tests |
| UX-S08  | Health Check guided repair | Health Check reports `read-only` and `did not change anything` before plain-language actions. Automatic repair searches only broken profile codes, shows compact progress and redacted before/after GamePath evidence, asks for explicit review, saves only the reviewed set after a verified backup, re-reads and revalidates every saved profile before reporting `FIXED`, and reports failed saves as `STILL BROKEN`. Search roots are canonical existing non-reparse folders outside protected roots; no-candidate searches may switch folders; scoped AutoSync re-entry uses the broken-profile whitelist; manual repair requires explicit selection. | Repair-GamePaths; Write-LibraryHealthRepairResults; Health Check tests |
| RS-S01  | ReShade profile display | The bounded profile choices show beginner-friendly names and descriptions first, followed by a `Techniques:` line derived from canonical `TechniqueOrder` and approved effect-catalog shader filenames/technique names. The preview drop-down and terminal chooser both select from the same ordered 1-17 profile catalog (Original plus 16 arcade looks built from 12 of the 25 cataloged effects) and synchronize the canonical selected ID. The gallery exposes Before/After/Split plus the 0-100 Slider comparison control. Internal paths and live runtime files are never displayed. | Get-TpmReShadeProfileTechniqueDisplay; direct/terminal ReShade selector tests and WinForms smoke |
| RS-S02  | ReShade preview lifecycle | The optional gallery owns one preview session and its cached bitmaps; direct preview and terminal selection synchronize the same state, `U` accepts the latest selection after input pumping, and the normal setup path automatically closes/disposes the gallery when the chooser returns. `R` closes the old session before opening a fresh one; if the chooser then throws, it closes the newest replacement session while the caller closes the original. The terminal remains usable when the gallery is unavailable or closed. | Show-TpmReShadeProfileGalleryWindow; Close-TpmReShadeProfileGallerySession; Sync-TpmReShadeGallerySelection; selector and gallery lifecycle tests |
| RS-S03  | ReShade slider paint | The gallery's 0-100 TrackBar changes only comparison position/view; profile selection from either surface preserves slider position and view mode while refreshing the direct preview. Paint reads only cached reference/processed bitmaps, never allocates a composite, replaces `PictureBox.Image`, decodes files, or reruns profile processing. A 16 ms timer coalesces rapid `ValueChanged` events; keyboard `KeyUp` applies immediately. The output is a safe bundled-image approximation, not game/shader execution evidence, and actual in-game results may vary. | New-TpmReShadePreviewPaintHandler; Get-TpmReShadePreviewStateValue; New-TpmReShadeGalleryEventHandlers; Flush-TpmReShadeGallerySlider; gallery state/selection tests; WinForms gallery smoke |
| CH-S01  | Crosshair browser feedback | The visual picker reports P1 selection and highlights it before accepting P2, confirms the P2 selection, preserves typed numeric fallback, and keeps deployment behind terminal confirmation. | Export-CrosshairPreview; Start/Read-CrosshairSelectionBridge; P1/P2 browser feedback tests |
| GPU-S01 | GPU Fix safe routing | GPU Fix validates each registered executable at the mutation boundary; missing or unavailable paths become per-game skips with actionable result guidance and a conditional Health Check handoff, never a fatal batch abort or false success. | Invoke-GpuFixSetup; Test-TpmGameMutationPath; GPU missing-device and guided-repair tests |
| FFB-S02  | FFB overlap and path routing | FFB setup resolves plugin candidates before third-party mutation, identifies games covered by both native FFB Blaster and the plugin, asks once for one owner, defaults to native, switches native fields off with a verified backup before third-party deployment, prevents both owners, and reports overlap skips separately from no-match, no-DLL, missing saved path, unavailable device, and errors. Shared mutation-path classification preserves affected game names and offers a Health Check handoff even when plugin deployment also fails. | Invoke-FFBPluginSetup; Test-TpmGameMutationPath; Invoke-TpmFfbSetupMode; Disable-FFBBlasterForOverlap; Get-FFBBlasterSupport; overlap/path and FFB workflow tests |
| SUP-S01 | Support package collection | Menu option 17 (option 15 in RC8) gathers only allowlisted TPM/TeknoParrotUI/TeknoParrot/game text diagnostics, redacted affected-game profile snapshots, and metadata-only plugin inventories into a fixed support ZIP; the exact TeknoParrotUI intake filename is required and arbitrary directories or game payloads are never archived. The manifest and completion output lead with `What failed` and `What TPM did not change`, then label Current, Stale, and Ambient evidence. | New-TpmSupportPackage; support-package allowlist/privacy/manifest tests |
| SUP-S02 | Support package privacy | Common credentials and user-profile paths are redacted from included text and structured snapshots; credentials, raw UserProfile XML, recovery state, executables, DLL payloads, archives, firmware, and unrelated files are excluded. The manifest records collected/absent/excluded/failed/unsafe-content-rejected sources and stale Action Required evidence. | Redact-TpmSupportText; profile/intake/manifest privacy tests |
| SUP-S03 | Support package object-bound safety | Source/profile/plugin reads consume identity-validated opened handles; unsafe path identity is rejected, destination promotion uses an identity-validated directory handle and CREATE_NEW, and staging cleanup deletes only through validated owned handles. | Open-TpmSupportSafeFileStream; Move-TpmSupportZipByIdentity; adversarial/workflow tests |
| WS-S01 | Engineering handoff      | GitHub is authoritative; each machine uses a local clone/worktree and hands off pushed refs plus exact SHAs. NAS is storage/mirror evidence, not an authoritative active Git worktree. | RELEASE-SAFETY-CHECKLIST.md; #293 policy           |
| ARC-UX-S01 | Test-PC packaged runtime UX | Before RC8 release authorization, run the exact packaged source identity on the test-PC environment and capture package identity/hash/assets, terminal/menu screenshots, one-letter prompts, ReShade gallery/slider behavior, Health Check repair/routing, feature routing, backup-failure truthfulness, and support-package clarity. The ordinary-menu screenshot defect's confirmed cause was a duplicate legacy width-only `Get-ConsoleLayoutTier` definition overriding the compact-default width-and-height policy; source correction and focused tests are tracked in `TPM-MENU-COMPACT-DEFAULT-001`, while owner-runtime proof remains required. | Issue #323; `docs/TPM-CERTIFICATION-SUITE.md`; `docs/remediation/slices/TPM-MENU-COMPACT-DEFAULT-001.md`; Test-PC smoke evidence |
| PG-S10 | PostgreSQL helper results (#370) | Governing source: PowerShell about_Return / about_Try_Catch_Finally (5.1 and 7.x): every statement's output, including output produced by a `finally` block, becomes part of the function's output. `Get-PostgresDatabaseState`, `Test-PostgresPassword`, `New-PostgresDatabaseFromBackup`, and `Backup-PostgresDatabases` each emit exactly one typed result (`Exists` is a strict Boolean); temporary-credential cleanup emits nothing, and a cleanup failure still throws. | Remove-PostgresPgPassFile call sites; Tests/PostgresHelperResultContract.Tests.ps1 |
| ZIP-S01 | ZIP entry names (APPNOTE 4.4.17.1) | Governing source: PKWARE APPNOTE.TXT 6.3.10 section 4.4.17.1 -- a stored path MUST NOT contain a drive or device letter or a leading slash. `Expand-ZipFileSafe` checks the RAW entry name before any separator normalization: empty name, leading `/` or `\` (including `//server` and `\\server` UNC forms), and any `:` (drive letter, drive-relative path, or NTFS alternate stream) are rejected. | ConvertTo-SafeZipEntryRelativePath; Tests/ZipExtractionPreflight.Tests.ps1 |
| ZIP-S02 | ZIP entry segments | After normalization each path segment must be non-empty, must not be `.` or `..`, must not end in `.` or space (names Windows would otherwise reinterpret), must not contain invalid file-name characters, and must not be a reserved Windows device name per Microsoft "Naming Files, Paths, and Namespaces": CON, PRN, AUX, NUL, COM1-9, LPT1-9, and COM/LPT followed by superscript 1, 2 or 3 (U+00B9/U+00B2/U+00B3), with or without an extension. COM0, LPT0 and COM10 are not reserved and remain accepted. | ConvertTo-SafeZipEntryRelativePath; ZipExtractionPreflight pure device-name tests |
| ZIP-S03 | ZIP separators (deliberately out of scope) | APPNOTE 4.4.17.1 also says all slashes MUST be forward slashes. Interior backslashes are still accepted as separators: real Windows-produced archives contain them and existing extraction already treated them as separators. Only a leading backslash is rejected (ZIP-S01). | ARCHITECTURE.md "ZIP extraction entry validation" |
| ZIP-S04 | ZIP collisions | Duplicate entry paths (case-insensitive, after separator normalization), a file entry that is also a directory of another entry, and destination file/directory shape conflicts are rejected. Duplicate explicit directory entries are allowed. An existing file at a file target is replaced, as before. | Expand-ZipFileSafe preflight; ZipExtractionPreflight collision tests |
| ZIP-S05 | ZIP directory handling (#369) | `Expand-ZipFileSafe` preserves explicit directories, implicit parents, and nested empty directories. AutoSync inventory synthesis adds every missing ancestor for each validated ZIP record, including explicit empty-directory entries; exact staged path/type/length/SHA-256 validation must pass before replacement; long paths keep the `\\?\` prefix. | Expand-ZipFileSafe; Tests/ZipExtractionPreflight.Tests.ps1; Tests/TeknoParrot-Manager.Tests.ps1 (ZMI-003/ZMI-005) |

## System invariant inventory

| ID        | Invariant                                                                                                                                                                                                                                                           | Status requirement                            |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| INV-ARC-01 | Test-PC packaged runtime UX evidence is required before RC8 release authorization: the tested package must be tied to the exact source SHA, and screenshots/logs must cover menu/prompt layout, ReShade, path repair, feature routing, failure truthfulness, and support-package clarity. | Must hold before release authorization |
| INV-PG-01 | Existing PostgreSQL data is never deleted or recreated by guided password recovery.                                                                                                                                                                                 | Must hold on success and failure              |
| INV-PG-02 | SUPERSEDED in part. Historical wording: a failed reset, service restart, configuration backup, profile backup, or profile write cannot produce a recovery-complete result. There is no reset now. Still in force: a failed service restart, configuration backup, profile backup, or profile write cannot produce a recovery-complete result. | Must fail closed |
| INV-PG-03 | Passwords never appear in logs, summaries, console output, command arguments constructed for display, test artifacts, or issue output. The unavoidable TPUI Pass field and ACL-locked exact-recovery backup are documented local compatibility/evidence boundaries. | Must hold outside those bounded files         |
| INV-PG-04 | Profile XML writes are deterministic by filename and occur only after all affected profiles have been backed up.                                                                                                                                                    | Must hold for multi-profile runs              |
| INV-EG-01 | Unsafe Eggman paths are rejected before any download or destination write.                                                                                                                                                                                          | Must hold for default and user-selected paths |
| INV-BX-01 | No BepInEx live path is touched until root safety, digest, staging extraction, and backup verification pass. | Must hold for all candidates                  |
| INV-SUP-01 | Support ZIP collection is fixed-scope and allowlist-driven; no arbitrary directory recursion or game payload copying is permitted. | Must hold for every package |
| INV-SUP-02 | Support package text is redacted for common secrets and user-profile paths, while credential-bearing files and recovery state are excluded before staging. | Must hold before ZIP creation |
| INV-SUP-03 | Support source/profile/plugin reads consume identity-validated opened objects; promotion uses an identity-validated destination directory and CREATE_NEW destination handle; cleanup deletes only through validated owned handles and remains partial/non-green when ownership is uncertain. | Must hold on every package path |
| INV-SUP-04 | Missing optional diagnostics are recorded as absent; collection/ZIP failures cannot produce a success result, and workflow status is closed on every exit. | Must hold on success and failure |
| INV-BX-02 | A recoverable BepInEx promotion failure restores the complete pre-operation tree; an unrecoverable failure preserves evidence and reports blocked.                                                                                                                  | Must hold in rollback matrix                  |
| INV-BX-03 | An applied BepInEx update counts as clean only after its validated staging directory is removed. Cleanup failure preserves the exact validated residue path in `Cleanup.ResiduePaths` and Details, emits ACTION REQUIRED, returns `CLEANUP_RESIDUE` over the underlying product outcome without fabricating an incomplete game item, and excludes the update from the clean count. | Must hold after successful promotion |
| INV-BX-04 | Shared game mutation workflows never act on an unavailable, missing, reparse-backed, inaccessible, or changed registered executable path. | Must hold at every read and mutation boundary |
| INV-HC-01 | Health Check inspection is read-only and does not mutate game paths, profiles, LaunchBox, PostgreSQL, ReShade, dgVoodoo2, GPU-fix, FFB, BepInEx, or controls. A selected repair/setup action is the only transition to a mutating workflow. Path repair performs a dry-run review limited to broken profile codes, saves only the explicitly reviewed set after a verified backup, re-reads and revalidates saved GamePath values before `FIXED`, and reports failures as `STILL BROKEN`; search roots are canonical existing non-reparse folders outside protected roots; AutoSync re-extraction remains whitelist-scoped. | Must hold before selected action |
| INV-RS-01 | The ReShade gallery has one session owner for its form, handlers, and cached bitmaps; closing it disposes those resources, `R` closes the old session before opening a fresh one, and unavailable preview UI never blocks terminal selection. Preview output is a safe approximation derived from the bundled hash-validated landscape reference; TPM does not run the game or execute ReShade shaders, and cache reuse never becomes deployment or trust evidence. | Must hold on open, close, `R`, cancel, and fallback |
| INV-RS-02 | ReShade profile display text is generated from the selected canonical profile's ordered techniques and the approved effect catalog; it does not duplicate shader or technique names in a second stale list. | Must hold in terminal chooser, Details, setup listing, and gallery |
| INV-RS-03 | ReShade slider paint reads only cached reference and processed bitmaps; it never allocates a composite bitmap, replaces `PictureBox.Image`, decodes files, or reruns profile processing during drag, and rapid input is coalesced without removing keyboard updates. | Must hold for mouse, keyboard, and programmatic slider changes |
| INV-CH-01 | Crosshair browser selection visibly confirms and highlights P1 before P2, validates the per-session token and bounded index, preserves typed numeric fallback, and cannot deploy before terminal confirmation. | Must hold for browser success, invalid click, timeout, and fallback |
| INV-GPU-01 | GPU Fix revalidates each registered executable at the mutation boundary; missing or unavailable paths are per-game safe skips with visible next-action guidance, never a fatal batch abort or false success. | Must hold for detected, unknown, missing, and unavailable paths |
| INV-FFB-01 | FFB setup classifies native/plugin overlap before third-party mutation, asks once for one owner with native as the safe default, treats only explicit `N` as plugin selection, switches native fields off with a verified backup before third-party deployment, prevents both owners, and reports native and collision skips separately from no-match, missing DLL, missing path, unavailable device, and errors. Path-limited metadata and Health Check routing remain available even when plugin deployment fails. | Must hold for every overlapping candidate batch |
| INV-PG-10 | SUPERSEDED; not implemented (there is no reset). Historical invariant: a PostgreSQL reset reports a committed-but-unverified state distinctly and never saves an unverified replacement credential. | Historical only |
| INV-PG-11 | SUPERSEDED in part. Historical invariant: protected recovery retries never carry a credential as usable after a committed role-password change fails live revalidation. Still in force: no retry carries a credential that was not verified against the live server. | Must hold for every retry |
| INV-PG-12 | Every PostgreSQL 8.3 restore/setup drop uses the documented 8.3 CLI contract. A fresh verified state query is required before drop; verified absence skips the command; a present database is dropped without `--if-exists` and verified absent afterward. An unknown state never permits a destructive guess. | Must hold at every drop boundary |
| INV-PG-13 | Setup rollback has one transaction owner per database and retains structured creation/command/rollback evidence. Only a database whose creation may have begun is eligible for rollback; a pre-creation failure never drops an externally appeared database. Verified absent pre-state after one successful rollback maps to `ROLLED_BACK_VERIFIED`/`UNCHANGED`; any unknown state maps to `ACTION_REQUIRED`/`UNKNOWN` without retry. | Must hold on setup failure paths |
| INV-PG-14 | If a multi-database restore fails after any mutation, the retained receipt file reflects all attempted database receipts after rollback; an item with unverified rollback is removed from `CompletedItems` and placed in `UnknownItems`, with no terminal-set overlap. | Must hold on every rollback failure path |
| INV-PG-15 | A database observed after failed `createdb.exe` is not TPM-owned. Restore rollback must not drop it; an absent-prestate collision is `ACTION_REQUIRED`/`UNKNOWN`, and a dropped pre-existing database may be restored only after a fresh check verifies absence. | Must hold for restore collision boundaries |
| INV-PG-16 | If the final receipt JSON refresh fails, no stale file is exposed through `ReceiptPath`; the transaction evidence root remains present, `ReceiptError` is recorded, and cleanup is incomplete. A verified rollback is reported as `CLEANUP_RESIDUE`, not a clean rollback. | Must hold for receipt persistence failures |
| INV-PG-05 | A PostgreSQL helper never returns more than one value. A failed authentication, query, database creation, restore, or verification is a single `$false` (or a throw) and can never reach a consumer as a truthy collection. | Must hold on success, failure, and cleanup failure |
| INV-ZIP-01 | `Expand-ZipFileSafe` validates every entry name, internal collision, and destination shape conflict before it creates any directory or writes any file; an archive rejected by this preflight leaves an existing destination byte-for-byte unchanged and does not create a missing one. | Must hold for every archive rejected by preflight |
| INV-ZIP-02 | Preflight is not a transaction: an I/O failure after preflight (disk full, permission, concurrent change) can still leave a partial extraction, as before. Callers that need rollback use their own staging (BepInEx) or re-extraction (AutoSync). | Documented boundary, not a guarantee |
| INV-ZIP-03 | Rooted, UNC, drive, stream, device-name, and traversal entry names never reach a filesystem call (lexical check). This does not pin filesystem identities: an existing junction or other alias already inside the destination is followed by the write phase, as before; concurrency, payload/decompression errors, and write-phase I/O failures remain outside this guarantee. | Must hold for every entry name; alias boundary documented, not guaranteed |
| INV-ZIP-04 | AutoSync inventory includes every missing ancestor directory implied by each validated ZIP record, including explicit empty-directory entries; the staged tree must match inventory path, type, length, and SHA-256 before live replacement. | Must hold for each accepted archive shape before promotion |

## Adversarial review cases required before handoff

- Empty or mismatched secure password input.
- Password containing SQL quotes, backslashes, colons, and newline characters.
- (Historical, reset removed by FIX95) Missing or ACL-unlockable .pgpass cleanup.
- PostgreSQL service stop/start failure. (The single-user reset nonzero-exit case is historical; there is no reset now.)
- Missing pg_hba.conf or postgresql.conf evidence copy.
- Existing database with profile password already correct, empty, and stale.
- Support-package path traversal, reparse-point, malicious-name, oversized-log,
forbidden-binary, credential-file, redaction, partial-collection, ZIP-failure,
source/profile/plugin object-substitution, destination object-substitution,
cleanup-race, and workflow-cleanup cases.
- Duplicate database names across deterministically ordered profiles.
- BepInEx root outside the approved games root, a reparse root, an intermediate
  reparse component, and a reparse leaf.
- Failed BepInEx backup, failed staged extraction, digest mismatch, promotion
  failure, rollback failure, and ordinary staging cleanup failure.
- ReShade profile metadata with an unknown catalog technique or no approved
  `.fx` shader entry must fail closed rather than display a guessed or stale
  effect label. Canonical profile order is authoritative and may not be
  inferred from the display text.
 - PostgreSQL 8.3 `dropdb` rejects unsupported options; verified-absent targets skip drop, while present targets use documented arguments and are verified absent afterward.
 - PostgreSQL setup creation fails before the mutation boundary, during `createdb`, and after `createdb`; test command/state receipts, whether the failed database may exist, rollback ownership, and truthful terminal outcome.
 - Setup database appears after initial preflight; the helper's boundary recheck must preserve it and must not let the caller drop it.
 - Drop pre-state query, drop exit, or post-drop verification fails; stop without retry and preserve `ACTION_REQUIRED`/`UNKNOWN` evidence.
- A later multi-database restore failure triggers rollback after an earlier item succeeded; verify the retained receipt JSON reflects every rollback outcome, an unverified item is `UNKNOWN` rather than `COMPLETED`, terminal sets are disjoint, and diagnostics remain redacted.
- PostgreSQL restore `createdb.exe` fails after absent-state preflight while a database appears; do not drop the unowned database, retain `ACTION_REQUIRED`/`UNKNOWN`, and preserve receipts. Repeat after TPM dropped a pre-existing database to prove rollback does not drop an unowned replacement.
- Force the post-rollback receipt refresh to fail after an earlier receipt write; verify `ReceiptPath` is cleared, `ReceiptError` is recorded, the evidence root and stale file remain only as residue, cleanup is incomplete, and the typed transaction result validates.

| INV-GPU-02 | Every GPU Fix candidate has one authoritative file identity from discovery through mutation and final result; ChangedItems contain only profiles actually written, and CompletedItems, FailedItems, SkippedItems, and UnknownItems are actual, disjoint per-game outcomes. Counts never assign item identity. | Must hold for every candidate and mixed batch |
| INV-BX-05 | BepInEx architecture classification is based on positive executable or installed-package evidence: a known unsupported architecture is distinct from an unknown/unreadable architecture; both remain unchanged and retain a stable reason, safe next action, friendly game label, and accurate count. | Must hold for unknown, unreadable, supported, and known unsupported inputs |
| INV-BX-06 | BepInEx result presentation retains authoritative skipped, protected, unsupported, and unknown counts and per-game actions; actionable all-skipped inspection is ACTION_REQUIRED with ProductState UNCHANGED, while a genuinely up-to-date or non-applicable no-change result may remain NO_OP. | Must hold on every inspection result |
