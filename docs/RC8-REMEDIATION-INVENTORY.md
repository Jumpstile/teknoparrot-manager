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
understand. The remediation must keep the result visible until acknowledgement,
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
wait for acknowledgement; technical details remain available separately.
The acceptance question is whether a 14-year-old can complete the workflow
without specialist knowledge.

The shared mutation-path invariant below is the required response to the
missing-device findings. No affected workflow may promote or mutate a game
until its registered path is revalidated at the mutation boundary.

## Specification inventory

| ID     | Area                      | Governing behavior                                                                                                                                                                                                                                                             | Implementation/test pointer                                   |
| ------ | ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------- |
| PG-S01 | PostgreSQL recovery       | A password reset must be performed by TPM after secure intake. The reset uses PostgreSQL 8.3 single-user mode with SQL on standard input; it must not require a follow-up command.                                                                                             | Reset-PostgresPasswordAutomatically; success/failure tests    |
| PG-S02 | PostgreSQL recovery       | Recovery changes only the postgres role password. It must not drop, recreate, restore over, or wipe a database.                                                                                                                                                                | Reset-PostgresPasswordAutomatically; no-data-wipe boundary    |
| PG-S03 | PostgreSQL backup         | Before stopping the service or resetting the role, TPM must create and verify evidence containing relevant configuration and every affected profile. After reset/authentication verification, configuration is saved before database backup; profile/database setup follows only after both verified backup stages. | New-PostgresRecoveryBackup; ordering and cutoff tests |
| PG-S04 | PostgreSQL credentials    | A .pgpass file is temporary, ACL-locked, never logged, removed in finally, and cleanup failure is an operation failure. The process environment is restored exactly.                                                                                                           | New/Remove-PostgresPgPassFile; redaction tests                |
| PG-S05 | TeknoParrot compatibility | The UserProfile Pass field remains plaintext only because TeknoParrotUI consumes it directly. TPM writes only after verified backup, never reports its value, and skips profiles whose value already matches.                                                                  | Invoke-PostgresGameSetup; multi-profile tests                 |
| PG-S06 | Installer boundary        | MSI public properties are passed through the in-process Windows Installer Automation interface, not a password-bearing child command line. TPM does not request verbose logging, does not log the property string, clears password variables after the call, and verifies the installed service. | Install-Postgres83; source and runtime smoke tests    |
| PG-S07 | PostgreSQL elevation UX   | UAC carries only a random path to a DPAPI-authenticated complete envelope. A durable issuance identity is protected in the payload and bound to the legal filename; nonce/attempt are recorded in the one-time tombstone. Claim validation failure restores the encrypted challenge and removes temporary markers. The child binds exact hashes, paths, origin identity, parent executable/start identity, and five-minute lifetime. UAC denial reuses the untouched challenge; started-child failure mints a fresh attempt. | Start-PostgresRecoveryAsAdministrator; adversarial state tests |
| PG-S08 | PostgreSQL recovery UX   | When the saved password is unusable, TPM explains the problem, offers automatic repair, asks the user to choose and confirm a non-empty password with masked input, creates verified backup evidence before reset, verifies the new password before saving it, and keeps messages visible until acknowledged. | Read-ConfirmedPostgresPassword; option-12 source guards |
| PG-S09 | PostgreSQL service state | Recovery keeps PostgreSQL running through reset authentication, configuration save, database backup, and profile/database setup, then restores the original service state. Restoration failure blocks completion. | Restore-PostgresServiceState; transaction cutoff tests |
| EG-S01 | Eggman destination        | A safe configured/default destination is accepted without an unnecessary Browse prompt.                                                                                                                                                                                        | Invoke-EggmanDatDownloadInteractive; zero-prompt fixture      |
| EG-S02 | Eggman destination        | Every configured or user-selected destination is canonicalized and revalidated before reuse, download, or write.                                                                                                                                                               | Invoke-EggmanDatDownloadInteractive; unsafe no-download tests |
| EG-S03 | Eggman path roles         | An external primary ZIP/source folder may be an explicit DAT destination when it is reachable, non-reparse, outside protected roots, and revalidated before the final move; supplementary and ambiguous source roles are never auto-selected.                                  | Get-EggmanDatPathRole; fallback/reparse/role tests             |
| BX-S01 | BepInEx target            | Each candidate root must be inside the approved games root and every existing path component must be non-reparse before update discovery can lead to a prompt, download, backup, or transaction. Integrity health checks must also identify incomplete current-version trees so repair-reset remains reachable.                                                                               | Test-BepInExGameRootSafe; no-write tests                      |
| BX-S02 | BepInEx transaction       | ZIP extraction occurs in isolated staging. Backup creation is verified before promotion. Live promotion rolls back all promoted files on failure; rollback failure preserves evidence and is never reported as success.                                                        | Invoke-TpmTransactionalTreePromote; rollback tests            |
| BX-S05 | Shared game mutation path | ReShade, dgVoodoo2, GPU-fix, and BepInEx validate the registered executable path immediately before inspection and again at the mutation boundary; unavailable devices, missing leaves, inaccessible/reparse paths, and resolution changes are classified and never mutated. | Test-TpmGameMutationPath; workflow preflight/boundary tests |
| BX-S03 | BepInEx cleanup           | Recursive staging cleanup is limited to a canonical non-reparse `BepInEx-*` directory under the controlled TPM staging root. A post-promotion cleanup failure preserves residue, reports ACTION REQUIRED with the validated path, and is excluded from the clean-update count. | Remove-BepInExStagingDirectory; cleanup result tests          |

| FFB-S01 | FFB plugin ownership   | TPM records each deployed hook with game-root/path/source/deployed hashes and removes it only when the current file still matches the recorded ownership. Unowned or changed hooks remain untouched. | Write/Remove-FFBPluginOwnership; ownership tests |
| UX-S01  | Workflow status        | Multi-step workflows expose structured real-step status, pinned failures, deterministic close/failure cleanup, explicit single-owner serialization, resize-safe footer/append-only fallback, unknown-step rejection, and no cursor writes in redirected/unattended/certification runs. | New/Publish/Render-TpmWorkflowStatus; resize tests |
| BX-S04 | BepInEx refusal UX        | An unsafe game root is refused before release discovery with a beginner-readable reason, a concrete path/root correction action, and an explicit no-download/no-write statement. | Write-BepInExUnsafeRootGuidance; refusal-message tests         |
| UX-S02  | Restore recovery        | Preserve the selected backup and wait for TeknoParrot/LaunchBox to close; never force-close unsaved user work; report only verified completion. | Invoke-RestoreBackup; restore recovery tests |
| UX-S03  | Crosshair lock          | Keep the selected operation pending while PCSX2 closes; do not silently rerun or claim deployment when the lock remains. | Wait-TpmForProcessClose; crosshair tests |
| UX-S04  | TeknoParrotUI ownership | Launch TPUI only to complete its own profile/setup state when required; TPM does not edit ParrotData, controls, DAT, or XML-owned setup state. | Ensure-TeknoParrotProfilesReady; first-run tests |
| UX-S05  | Optional downloads      | Automatic ReShade/dgVoodoo2 acquisition retries or offers an explicit advanced existing-file path; signature/digest gates remain mandatory and cancel is truthful. | Invoke-ReShadeSetup; Invoke-DgVoodoo2Setup |
| UX-S06  | Registration ambiguity  | Present validated candidate profiles for an explicit choice; blank/invalid input leaves the case unresolved instead of guessing. | Invoke-ManualRegistrationChoices; registration tests |
| UX-S07  | Health boundaries       | Missing firmware/components remain contract-backed, read-only warnings with a legitimate-source/TPUI repair handoff; TPM does not fabricate or replace vendor files. | Get-CompatibilityWarnings; health tests |
| UX-S08  | Health Check guided repair | Health Check reports `read-only` and `did not change anything` before offering direct, plain-language broken-path, PostgreSQL, and optional-component actions. Automatic path repair asks before saving; manual repair requires explicit folder/file selection and never guesses; Details remains separate. | Invoke-LibraryHealthCheck; Show-LibraryHealthNextActions; Health Check UX and boundary tests |
| RS-S01  | ReShade profile display | The five bounded profile choices show beginner-friendly names and descriptions first, followed by a `Techniques:` line derived from canonical `TechniqueOrder` and approved effect-catalog shader filenames/technique names. The terminal chooser remains ordered 1-5; internal paths and live runtime files are never displayed. | Get-TpmReShadeProfileTechniqueDisplay; ReShade chooser/gallery tests |
| RS-S02  | ReShade preview lifecycle | The optional gallery owns one preview session and its cached bitmaps; closing the gallery disposes the session, `R` closes the old session before opening a fresh one, and selection remains usable when the gallery is unavailable. | Show-TpmReShadeProfileGalleryWindow; Close-TpmReShadeProfileGallerySession; Sync-TpmReShadeGallerySelection; gallery lifecycle tests |
| RS-S03  | ReShade slider paint | Slider drag paint reads only the cached reference and processed bitmaps, never allocates a composite bitmap, replaces `PictureBox.Image`, decodes files, or reruns profile processing; rapid changes are coalesced and keyboard updates remain supported. | New-TpmReShadePreviewPaintHandler; New-TpmReShadeGalleryEventHandlers; cached-paint and slider tests |
| CH-S01  | Crosshair browser feedback | The visual picker reports P1 selection and highlights it before accepting P2, confirms the P2 selection, preserves typed numeric fallback, and keeps deployment behind terminal confirmation. | Export-CrosshairPreview; Start/Read-CrosshairSelectionBridge; P1/P2 browser feedback tests |
| GPU-S01 | GPU Fix safe routing | GPU Fix validates each registered executable at the mutation boundary; missing or unavailable paths become per-game skips with actionable result guidance, never a fatal batch abort or false success. | Invoke-GpuFixSetup; Test-TpmGameMutationPath; GPU missing-device and guided-repair tests |
| FFB-S02  | FFB overlap ownership | FFB setup resolves plugin candidates before third-party mutation, identifies games covered by both native FFB Blaster and the plugin, asks once for one owner, defaults to native, switches native fields off with a verified backup before third-party deployment, prevents both owners, and reports overlap skips separately. | Invoke-FFBPluginSetup; Disable-FFBBlasterForOverlap; Get-FFBBlasterSupport; overlap and FFB workflow tests |
| SUP-S01 | Support package collection | Option 14 gathers only allowlisted TPM/TeknoParrot/game text diagnostics and metadata-only plugin inventories into a fixed support ZIP; it never archives arbitrary directories or game payloads. The manifest and completion output lead with `What failed` and `What TPM did not change`. | New-TpmSupportPackage; SupportPackage.Tests.ps1 |
| SUP-S02 | Support package privacy | Common credentials and user-profile paths are redacted from included text and user-facing failure summaries; credentials, profiles, recovery state, executables, DLL payloads, archives, firmware, and unrelated files are excluded. The manifest records collected/absent/excluded/failed/unsafe-content-rejected sources. | Redact-TpmSupportText; manifest/privacy tests |
| SUP-S03 | Support package object-bound safety | Source/profile/plugin reads consume identity-validated opened handles; unsafe path identity is rejected, destination promotion uses an identity-validated directory handle and CREATE_NEW, and staging cleanup deletes only through validated owned handles. | Open-TpmSupportSafeFileStream; Move-TpmSupportZipByIdentity; adversarial/workflow tests |
| WS-S01 | Engineering handoff      | GitHub is authoritative; each machine uses a local clone/worktree and hands off pushed refs plus exact SHAs. NAS is storage/mirror evidence, not an authoritative active Git worktree. | AGENTS.md; RELEASE-SAFETY-CHECKLIST.md; #293 policy           |

## System invariant inventory

| ID        | Invariant                                                                                                                                                                                                                                                           | Status requirement                            |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| INV-PG-01 | Existing PostgreSQL data is never deleted or recreated by guided password recovery.                                                                                                                                                                                 | Must hold on success and failure              |
| INV-PG-02 | A failed reset, service restart, configuration backup, profile backup, or profile write cannot produce a recovery-complete result.                                                                                                                                  | Must fail closed                              |
| INV-PG-03 | Passwords never appear in logs, summaries, console output, command arguments constructed for display, test artifacts, or issue output. The unavoidable TPUI Pass field and ACL-locked exact-recovery backup are documented local compatibility/evidence boundaries. | Must hold outside those bounded files         |
| INV-PG-04 | Profile XML writes are deterministic by filename and occur only after all affected profiles have been backed up.                                                                                                                                                    | Must hold for multi-profile runs              |
| INV-EG-01 | Unsafe Eggman paths are rejected before any download or destination write.                                                                                                                                                                                          | Must hold for default and user-selected paths |
| INV-BX-01 | No BepInEx live path is touched until root safety, digest, staging extraction, and backup verification pass. | Must hold for all candidates                  |
| INV-SUP-01 | Support ZIP collection is fixed-scope and allowlist-driven; no arbitrary directory recursion or game payload copying is permitted. | Must hold for every package |
| INV-SUP-02 | Support package text is redacted for common secrets and user-profile paths, while credential-bearing files and recovery state are excluded before staging. | Must hold before ZIP creation |
| INV-SUP-03 | Support source/profile/plugin reads consume identity-validated opened objects; promotion uses an identity-validated destination directory and CREATE_NEW destination handle; cleanup deletes only through validated owned handles and remains partial/non-green when ownership is uncertain. | Must hold on every package path |
| INV-SUP-04 | Missing optional diagnostics are recorded as absent; collection/ZIP failures cannot produce a success result, and workflow status is closed on every exit. | Must hold on success and failure |
| INV-BX-02 | A recoverable BepInEx promotion failure restores the complete pre-operation tree; an unrecoverable failure preserves evidence and reports blocked.                                                                                                                  | Must hold in rollback matrix                  |
| INV-BX-03 | An applied BepInEx update is counted as clean only after its validated staging directory is removed. Cleanup failure preserves the exact validated residue path and produces ACTION REQUIRED output.                                                                | Must hold after successful promotion          |
| INV-BX-04 | Shared game mutation workflows never act on an unavailable, missing, reparse-backed, inaccessible, or changed registered executable path. | Must hold at every read and mutation boundary |
| INV-HC-01 | Health Check inspection is read-only and does not mutate game paths, profiles, LaunchBox, PostgreSQL, ReShade, dgVoodoo2, GPU-fix, FFB, BepInEx, or controls. A selected repair/setup action is the only transition to a mutating workflow, and path repair saves only after explicit confirmation and verified backup. | Must hold before selected action |
| INV-RS-01 | The ReShade gallery has one session owner for its form, handlers, and cached bitmaps; closing it disposes those resources, `R` closes the old session before opening a fresh one, and unavailable preview UI never blocks terminal selection. | Must hold on open, close, `R`, cancel, and fallback |
| INV-RS-02 | ReShade profile display text is generated from the selected canonical profile's ordered techniques and the approved effect catalog; it does not duplicate shader or technique names in a second stale list. | Must hold in terminal chooser, Details, setup listing, and gallery |
| INV-RS-03 | ReShade slider paint reads only cached reference and processed bitmaps; it never allocates a composite bitmap, replaces `PictureBox.Image`, decodes files, or reruns profile processing during drag, and rapid input is coalesced without removing keyboard updates. | Must hold for mouse, keyboard, and programmatic slider changes |
| INV-RS-04 | ReShade preview output is derived from the bundled hash-validated landscape reference; cache reuse never becomes deployment or trust evidence, and all in-memory bitmaps are disposed on gallery close. | Must hold for every preview mode |
| INV-CH-01 | Crosshair browser selection visibly confirms and highlights P1 before P2, validates the per-session token and bounded index, preserves typed numeric fallback, and cannot deploy before terminal confirmation. | Must hold for browser success, invalid click, timeout, and fallback |
| INV-GPU-01 | GPU Fix revalidates each registered executable at the mutation boundary; missing or unavailable paths are per-game safe skips with visible next-action guidance, never a fatal batch abort or false success. | Must hold for detected, unknown, missing, and unavailable paths |
| INV-FFB-01 | FFB setup classifies native/plugin overlap before third-party mutation, asks once for one owner with native as the safe default, treats only explicit `N` as plugin selection, switches native fields off with a verified backup before third-party deployment, prevents both owners, and reports native and collision skips separately from no-match and errors. | Must hold for every overlapping candidate batch |
| INV-PG-10 | PostgreSQL reset reports a committed-but-unverified state distinctly; it never claims the old password remains authoritative after ALTER succeeded, and it never saves an unverified replacement credential. | Must hold after every reset process outcome |

## Adversarial review cases required before handoff

- Empty or mismatched secure password input.
- Password containing SQL quotes, backslashes, colons, and newline characters.
- Missing or ACL-unlockable .pgpass cleanup.
- PostgreSQL service stop/start failure and single-user reset nonzero exit.
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
