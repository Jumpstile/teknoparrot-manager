# PR #321 Remediation Gate Report

- Repository root: `C:\REPOS\teknoparrot-manager\.worktrees\rc8-release-readiness`
- Branch: `release/rc8-readiness-2026-10-01`
- HEAD before this review-reconciliation slice: `0295415fb1b9d4bf6880945eb4807d4b2b27ec96`.
- Repository and source fingerprints captured UTC: 2026-10-03T12:47:20.7444836Z.
- Source/test last-edit UTC: main `2026-10-03T12:04:54.0992008Z`; main tests `2026-10-03T12:11:40.4473767Z`; updater module `2026-10-03T12:05:13.4853727Z`; updater core tests `2026-10-03T12:11:44.7738098Z`; updater runner `2026-10-03T06:30:32.1621661Z`; destructive updater tests `2026-10-03T06:32:22.7512886Z`; SupportPackage tests `2026-10-02T06:01:00.5945312Z`.
- Main source SHA-256: `C649214E769EA19780352EF1B449099957C85AEF86F2FC767CDDA10F82DC1209`.
- Main test SHA-256: `BD262A64921E9EBD92D77F112976E78847C7BE106727D29CB2B02697086EDF99`.
- Support test SHA-256: `C56CFC5947DC989AF89036877519725B4F03340375F84D45F60989335628F4A9`.
- Updater module SHA-256: `41944B88766C06D299354CAED0DBA5531E8042A5339BBF76855E0F188E78ADE9`; runner SHA-256: `CAAE71ABD4D2D859FC545802BE06E273CD8CFC026F885494C4989965546933E9`.
- Updater core test SHA-256: `F56FF89E05C1A0EAD1DD60CBD3A454BFC46D722F52E2C4F30B39510C81868FEA`; destructive updater test SHA-256: `32445A67C398AECFE190D10B7B978D2007989CC9D03DAD6C0E8D1A0DF523C21B`.
- Permanent procedure gate last-edit UTC: 2026-10-02T11:14:26.5739714Z; SHA-256: `489819CAD9A3FD8981CBC4996E46D3F8D2E7660D3A306BB6C91735B70A0501F2`.
- Task-start worktree identity: root `C:\REPOS\teknoparrot-manager\.worktrees\rc8-release-readiness`; branch `release/rc8-readiness-2026-10-01`; HEAD `7d92a3f2379038b9c1ba3e3750766e8cf1a5ac42`, based on PR #321 ref `0295415fb1b9d4bf6880945eb4807d4b2b27ec96`. `git ls-remote` verified the existing origin branch at that ref; local HEAD is its descendant and one commit ahead; no upstream is configured. At this evidence-recording point, the scoped changes were not committed or pushed. The user authorized scoped commit/push to the existing PR #321 head only after all required gates pass; parent owns exact-head CI. No package build, runtime smoke, or release action has occurred.
- The earlier PS7 aggregate attempts exposed a Pester assertion issue and stale evidence; both were corrected. The final aggregate passed at 2026-10-02T12:54:54.9646896Z: main Pester 1276/1276, SupportPackage 42/42, ASCII/parse, configured PSScriptAnalyzer, `git diff --check`, and permanent procedure gate. ID 3 is recorded `SOURCE FIXED; OWNER RUNTIME NEEDED`; candidate identity, owner-runtime proof, and release authorization remain outstanding.
- Current candidate status: STALE
- Current candidate source SHA: NONE
- Current candidate package SHA-256: NONE
- Current candidate package validation: NOT RUN
- Scope: PR #321 RC8 remediation, including expanded ID 3 progress coverage, corrected fail-closed owner-status gate, canonical owner-ID coverage through ID 35, source re-audits for IDs 7, 20, 23-27, and 30-32, ID 29 support-inventory correction, and the separately authorized ReShade IDs 1/9/10 ten-effect/twelve-profile selection slice. The ReShade slice includes pinned runtime-format specification and system-invariant inventories; inventory timing deviation, package identity, and owner-runtime proof remain explicit review gates.
- Current status: ID 3 is `SOURCE FIXED; OWNER RUNTIME NEEDED` after finite progress-census closure and failing-before/passing-after Crosshairs coverage. Unknown-total discovery advances for every direct user-extensible `Crosshairs\*.png`, stays active through sorting, closes before validation, and uses `-ErrorAction Stop`; candidate ordering, validation, dynamic indices, and unchanged P1/P2 bytes are covered. The final aggregate source/permanent gate passed. Exact package identity, owner-runtime proof, and release authorization remain separate.

## Provenance

- This worktree retains the PostgreSQL pre-UAC guidance slice and adds
  expanded compact-progress source/tests, support ZIP lifecycle correction,
  registry-backed permanent-gate status/ID validation, freshness coverage,
  and synchronized architecture/control-board/slice-contract/reconciliation
  updates.
- The canonical control board is `docs/remediation/PR-321-control-board.md`.
- No monitor-pipeline files changed.
- No runtime, state, log, ZIP, or package artifact was created by this work.

## Owner report mapping table
Rows 1-32 retain the historical pre-reaudit mapping. IDs 33-35 were added
later and are mapped at their current registered status. The canonical
release-decision table below is the sole status source and supersedes
historical status cells.

| ID | Owner report | Status | Files/functions | Exact test names | Runtime proof still needed |
|---:|---|---|---|---|---|
| 1 | ReShade no-change/back/cancel crash | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade action-result handling | ReShade null-result regression | Packaged `Original -> U -> B` smoke |
| 2 | Duplicate ErrorAction binding | SOURCE FIXED; OWNER RUNTIME NEEDED | Invoke-TpmWebRequestSilently and download wrappers | Focused RC8 remediation contracts | Startup, Eggman, ProfileSet, game-data, thumbnail smoke |
| 3 | Script-wide universal progress | SOURCE FIXED; OWNER RUNTIME NEEDED | Script-wide progress inventory and compact TPM progress call sites | Progress.Core focused source inventory; full Pester | Full packaged operation matrix |
| 4 | AutoSync old scan output | SOURCE FIXED; OWNER RUNTIME NEEDED | AutoSync compact progress | `truncates compact progress to constrained width and shows elapsed heartbeat` | Packaged AutoSync scan |
| 5 | GPU Fix blue PowerShell progress | SOURCE FIXED; OWNER RUNTIME NEEDED | `Invoke-GpuFixSetupWithStatus`; `Invoke-GpuFixSetup` per-profile loop; GPU menu retry path | `wraps GPU Fix in the universal workflow status lifecycle`; GPU-specific source scan: 0 `Write-Progress`, 2 compact progress calls | GPU Fix packaged smoke |
| 6 | Thumbnail bad progress | SOURCE FIXED; OWNER RUNTIME NEEDED | Thumbnail download caller | `supports opt-in no-fallback behavior for thumbnail-style 404 probes` | Packaged thumbnail smoke |
| 7 | Missing thumbnail list | SOURCE FIXED; OWNER RUNTIME NEEDED | Invoke-ThumbnailDownload | `clarifies thumbnail download is box art only, not game data` | Verify every no-icon code is listed |
| 8 | Thumbnail 404 fallback | SOURCE FIXED; OWNER RUNTIME NEEDED | Invoke-TpmDownload | `supports opt-in no-fallback behavior for thumbnail-style 404 probes` | Packaged 404 behavior |
| 9 | ReShade preview sync | SOURCE FIXED; OWNER RUNTIME NEEDED | Read-TpmReShadeTerminalProfile | `uses the live Classic Arcade CRT preview selection when U is pressed` | Actual preview selection smoke |
| 10 | ReShade selector visibility | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade selector instructions | ReShade selector contract coverage | Packaged UI smoke |
| 11 | Protected ReShade adopt/replace | SOURCE FIXED; OWNER RUNTIME NEEDED | `Get-TpmReShadeOwnershipClassification`; `Install-TpmReShadeProfileDeployment`; `Invoke-ReShadeSetup` | ReShade protected-adoption tests | Explicit adopt/replace smoke |
| 12 | ReShade all-games accounting | SOURCE FIXED; OWNER RUNTIME NEEDED | `Get-TpmReShadeApplyPreflight`; `Get-TpmReShadeApplyAccounting`; `Invoke-ReShadeSetup` | ReShade accounting tests | All-games packaged smoke |
| 13 | Crosshair browser close | SOURCE FIXED; OWNER RUNTIME NEEDED | Export-CrosshairPreview | Crosshair source-contract coverage | Actual browser P1/P2 smoke |
| 14 | Crosshair focus return | SOURCE FIXED; OWNER RUNTIME NEEDED | Crosshair focus fallback | Crosshair fallback tests | Actual focus smoke |
| 15 | Crosshair prompt row | SOURCE FIXED; OWNER RUNTIME NEEDED | `Invoke-CrosshairSetup` and `Read-TpmWorkflowInput` | `routes the P1 and P2 prompts through workflow input when a status context exists` | Constrained console smoke |
| 16 | PostgreSQL repair loop | SOURCE FIXED; OWNER RUNTIME NEEDED | PostgreSQL recovery action loop and password-mismatch retry | `keeps password mismatch inside the reset flow`; `retries protected backup after validated password` | Backup-failure R smoke |
| 17 | Affected-games repair scope | SOURCE FIXED; OWNER RUNTIME NEEDED | Repair-GamePaths and Health Check handoff | `emits compact repair progress for each profile` | One/multiple/zero affected smoke |
| 18 | Health Check no-candidate explanation | SOURCE FIXED; OWNER RUNTIME NEEDED | Health Check repair reporting | Health Check repair tests | No-candidate smoke |
| 19 | Health Check source recopy | SOURCE FIXED; OWNER RUNTIME NEEDED | Scoped AutoSync re-entry | Affected-path source contracts | Source recopy smoke |
| 20 | Health Check Back routing | SOURCE FIXED; OWNER RUNTIME NEEDED | Health Check routing | Health Check Back routing coverage | Press B in packaged runtime |
| 21 | Option 10 repair clarity | SOURCE FIXED; OWNER RUNTIME NEEDED | Repair result reporting | Repair result tests | Verify per-game accounting |
| 22 | Post-thumbnail repair scope | SOURCE FIXED; OWNER RUNTIME NEEDED | Affected-only AutoSync handoff | Scoped repair tests | Verify no optional-flow escape |
| 23 | LaunchBox Back gate | SOURCE FIXED; OWNER RUNTIME NEEDED | Optional-chain routing | LaunchBox Back coverage | Packaged B smoke |
| 24 | LaunchBox prompt wording | SOURCE FIXED; OWNER RUNTIME NEEDED | LaunchBox `P/A/F/B`, detected-root, and platform prompts | `Prompt.Core fixed choice routes`; `Read-TpmChoice validation` | Guided packaged prompt smoke |
| 25 | HyperSpin direct prompt | SOURCE FIXED; OWNER RUNTIME NEEDED | `Export-HyperSpinJson` missing-ID `G/S` choice | `Prompt.Core fixed choice routes`; source parse | Normal completion smoke |
| 26 | Invalid optional Y/N input | SOURCE FIXED; OWNER RUNTIME NEEDED | Centralized finite-choice routes plus documented stateful/exact-token/secure/path boundaries | `Read-TpmChoice validation`; `Prompt.Core fixed choice routes` | Invalid-input matrix |
| 27 | Support final prompt | SOURCE FIXED; OWNER RUNTIME NEEDED | Support `1-3` and package `O/B` routes | `Prompt.Core fixed choice routes`; SupportPackage.Tests | Packaged support prompt |
| 28 | Fatal support workflow surfacing | SOURCE FIXED; OWNER RUNTIME NEEDED | Get-TpmSupportManifestText | SupportPackage.Tests: `records Action Required freshness in the packaged manifest` | Fresh fatal-log package |
| 29 | Action Required freshness/scoping | SOURCE FIXED; OWNER RUNTIME NEEDED | New-TpmSupportPackage; EvidenceClass manifest records | SupportPackage.Tests; current/stale/ambient and plugin-inventory coverage | Complete troubleshooting intake and rebuilt support package |
| 30 | Controls truthfulness | SOURCE FIXED; OWNER RUNTIME NEEDED | `Write-ControlPropagationResults`; control-readiness engine | `Write-ControlPropagationResults` focused tests; existing controls tests | Zero-bound packaged runtime result |
| 31 | dgVoodoo2 wording | SOURCE FIXED; OWNER RUNTIME NEEDED | dgVoodoo2 result wording | No dedicated wording test | Owner wording review |
| 32 | Global consistency rule | SOURCE FIXED; OWNER RUNTIME NEEDED | `TPM-PROMPT-001` finite-choice inventory and documented stateful/exact-token/secure/path/renderer-aware boundaries | `Read-TpmChoice validation`; `Prompt.Core fixed choice routes` | Packaged consistency smoke |
| 33 | FFB membership/prompt and optional-plugin completion | SOURCE FIXED; OWNER RUNTIME NEEDED | FFB caller and plugin transaction completion | `uses one membership decision prompt and clear FFB completion rules`; `blocks the optional plugin after a failed native FFB setup` | Packaged mode-8 matrix |
| 34 | Migration explanation and Eggman DAT update path | SOURCE FIXED; OWNER RUNTIME NEEDED | Owned-state migration, valid transaction-result startup gate, and active DAT update filename | `rejects invalid migration transaction results before startup`; `allows only valid typed migration outcomes without requiring prompt input`; migration and DAT tests | Packaged migration decline/confirm and DAT update smoke |
| 35 | Cross-cutting user-facing cleanup | SOURCE FIXED; OWNER RUNTIME NEEDED | Normal prompts, full profile labels, compact progress | `uses product wording and full profile names in normal UI output`; `truncates compact progress to constrained width and shows elapsed heartbeat` | Packaged terminology and progress smoke |


## SCRIPT-WIDE UNIVERSAL PROGRESS BAR AUDIT

- `CONVERTED TO UNIVERSAL TPM PROGRESS`: compact and structured workflow paths listed in the current slice inventory.
- `JUSTIFIED NO PROGRESS SURFACE`: bounded writes and renderer-aware/stateful interactions listed in the current slice inventory.
- `SOURCE REMEDIATION REQUIRED`: the uncovered Crosshairs discovery/sort path is fixed in the working tree, but final full source gates and the permanent procedure gate have not yet passed. Unknown-total progress remains active through sorting and closes before validation; six other residual expressions remain bounded/short-circuit.
| Path | Function/call site | Current behavior | Disposition | Test |
|---|---|---|---|---|
| AutoSync scan and ZIP classification | Select-GamesInteractive; Select-GamesInteractiveCombined | Single-source and combined main/supplement ZIP scans emit compact progress against known totals and close the row | SOURCE FIXED; OWNER RUNTIME NEEDED | Both call-site progress tests; packaged AutoSync smoke |
| AutoSync extraction | Invoke-AutoSync | Mixed compact status and operation output | SOURCE FIXED; OWNER RUNTIME NEEDED | `uses compact TPM progress and preserves cleanup instead of a PowerShell progress panel` |
| Remaining progress paths | Profile readiness and process-close waits | Bounded external waits use 120-second and 30-second deadlines with actionable messages; no fake percentage is emitted | EXPLICIT BOUNDED WAIT CONTRACT | `PR #321 Progress.Core source inventory` |
| Library Health Check repair search | Repair-GamePaths / Select-GamesInteractive | Compact search/selection status and scoped repair handoff; owner package proof absent | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing repair-flow tests; owner smoke |
| GPU Fix web/check/download | Invoke-GpuFixSetup | Workflow status plus compact per-profile checks/download stages; owner package proof absent | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing GPU source contracts; owner smoke |
| GPU GameProfiles catalog scan | Get-GpuFixFieldNames; Get-GpuAndFfbFieldNames | Each XML emits compact known-total scan progress; completion closes the row | SOURCE FIXED; OWNER RUNTIME NEEDED | `Get-GpuFixFieldNames reports catalog scan progress`; `Get-GpuAndFfbFieldNames reports catalog scan progress` |
| Profile catalog discovery | Build-ProfileIndex; Get-FFBBlasterFieldNames | Index and FFB field-name scans emit per-XML known-total compact progress | SOURCE FIXED; OWNER RUNTIME NEEDED | `Build-ProfileIndex reports progress for every catalog profile`; `Get-FFBBlasterFieldNames reports catalog scan progress` |
| Shared download tiers | Invoke-TpmDownload | Compact download status is centralized for network transfers; owner package proof absent | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing download tests; owner smoke |
| Thumbnail checks/downloads | Invoke-ThumbnailDownload | Registered-code indexing, custom-thumbnail work, missing-icon classification, and box-art downloads report compact progress against known totals | SOURCE FIXED; OWNER RUNTIME NEEDED | Fixture-backed index/copy/classification progress test; existing download tests; owner smoke |
| AutoSync registration/import | Register-Games | Registration scan is covered by per-executable compact TPM progress; owner package proof absent | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing registration/source tests; owner smoke |
| AutoSync copy/move operations | Invoke-AutoSync promotion | AutoSync extraction/promotion path uses compact TPM progress; owner package proof absent | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing AutoSync tests; owner smoke |
| Library Health Check affected-games re-copy/re-extract | Health Check scoped AutoSync | Scoped AutoSync reuses the universal extraction progress path; owner package proof absent | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing scoped-flow tests; owner smoke |
| DAT checks/downloads | Eggman DAT functions | Shared compact download progress plus bounded destination-selection prompt | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing DAT tests; owner smoke |
| Eggman game data fetch | Eggman game-data functions | Shared compact download progress; bounded release/download retries | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing game-data tests; owner smoke |
| ProfileSet GitHub/default-branch query | Get-TeknoParrotProfileSet | Three bounded API attempts are shown as a known-total query; GitHub tree and local fallback scans show known counts | SOURCE FIXED; OWNER RUNTIME NEEDED | ProfileSet tree and local-fallback progress tests; packaged startup smoke |
| Startup update check | CheckForUpdates | Shared download/status path; startup behavior still needs packaged proof | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing updater tests; owner smoke |
| updater download | Invoke-TpmDownload update path | Shared compact download progress | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing updater tests; owner smoke |
| dgVoodoo2 download/check/deploy | Invoke-DgVoodoo2Setup; Get-TpmRegisteredProfileCodes | Registered-profile and selected-target deployment preflight scans close known-total rows; profile membership uses a shared case-insensitive code scan | SOURCE FIXED; OWNER RUNTIME NEEDED | Registered-profile scan failure and selected deployment preflight tests; owner smoke |
| FFB catalog, planning, mutation, and overlap rollback | Get-FFBBlasterFieldNames; Invoke-FFBBlasterSetup; Disable-FFBBlasterForOverlap; Restore-FFBPluginDeploymentTransaction | Catalog/profile planning and native mutation use known-total rows; selected-profile overlap preflight, safety snapshots, and both rollback copies report top-level entries without claiming recursive descendant progress | SOURCE FIXED; OWNER RUNTIME NEEDED | FFB overlap preflight/snapshot/rollback progress tests; owner smoke |
| FFB/network/download checks | Get-FFBPluginSourceRevision; Get-FFBPluginGameMap; Invoke-FFBPluginDownload; Invoke-FFBPluginSetup | Revision/support-table lookups are bounded and stage-visible; pinned DLL transfers use shared compact/workflow download status; plugin matching/planning uses known-total rows; transaction status remains structured with per-game results | CONVERTED TO UNIVERSAL TPM PROGRESS for transfers and loops; JUSTIFIED NO PROGRESS SURFACE for bounded metadata checks | Shared downloader tests; FFB source/deployment/read-back tests; owner smoke |
| Backup operations | Health Check/LaunchBox/PostgreSQL backup helpers | Compact progress covers Health Check/LaunchBox file backups, PostgreSQL recovery profile enumeration, and per-database backup classification/dump boundaries; `pg_dump.exe` remains opaque within each item | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing backup tests and PostgreSQL database-backup progress test; owner smoke |
| Verified UserProfiles backup/restore | Get-TpmUserProfilesBackupManifest; New-TpmVerifiedUserProfilesBackup; Restore-TpmVerifiedUserProfilesBackup | Manifest discovery/hash, directory/file backup, verification, restore, and final verification loops report known totals where available | SOURCE FIXED; OWNER RUNTIME NEEDED | Fixture-backed backup/restore progress and file-integrity tests; owner smoke |
| Generic transactional file batches | Invoke-TpmTransactionalFileBatch | Preflight, staging, backup, final revalidation, promotion, verification, and rollback/metadata rollback loops report compact per-item status | SOURCE FIXED; OWNER RUNTIME NEEDED | Fixture-backed transaction success/rollback progress tests; owner smoke |
| Transactional promotion | Invoke-TpmTransactionalPromote | Move-aside, staging, promotion, rollback, and rollback-directory loops report compact per-item status | SOURCE FIXED; OWNER RUNTIME NEEDED | Fixture-backed promotion and rollback progress tests; owner smoke |
| Owned-state migration | Invoke-TpmOwnedMigration | Inventory, verified top-level backup/move, and rollback loops report status; recursive `Copy-Item -Recurse` remains opaque per descendant and is only represented at the top-level item boundary | SOURCE FIXED; OWNER RUNTIME NEEDED | Fixture-backed migration progress and rollback tests; owner smoke |
| ReShade acquisition/apply/removal | Acquire-TpmReShadeApprovedEffect; Get-TpmReShadeApplyPreflight; Install-TpmReShadeProfileDeployment; Get-TpmReShadeRemovalScan; Remove-TpmReShadeOwnedDeployment; Invoke-ReShadeSetupLegacy | Acquisition, known-total preflight, staged assets, per-game deployment, removal scan, validation, backup, deletion, and rollback report compact progress; transport and mutation safety are unchanged | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade progress, staged-output, safety, and rollback tests; owner smoke |
| ReShade download/check/signature/preview loading | Get-ReShadeLatestVersion; Invoke-TpmDownload; Test-ReShadeSetupTrustedSignature; Expand-ReShadeSelfExtractingArchive; preview renderer | Installer transfer and effect/deploy/removal loops use shared or known-total progress; latest-version discovery is one 10-second request with a visible checking message; signature/archive checks and local preview rendering are bounded synchronous work | CONVERTED TO UNIVERSAL TPM PROGRESS for transfers/loops; JUSTIFIED NO PROGRESS SURFACE for bounded metadata/signature/archive/preview work | Existing shared-download, ReShade signature, preview, acquisition, and deployment tests; owner smoke |
| Support profile/plugin inventory and ZIP | New-TpmSupportPackage; Get-TpmSupportPluginInventory | Known-total profile scan, unknown-total plugin traversal, and active unknown-total ZIP operation are reported; nested roots are collapsed so each safe plugin path appears once; workflow completion follows identity-bound ZIP promotion/path verification, with an explicitly named active archive snapshot | SOURCE FIXED; OWNER RUNTIME NEEDED | SupportPackage.Tests progress, lifecycle-order, unique-row, and archive-content tests; owner smoke |
| PostgreSQL profile scans | Get-PostgresReinitializePlansFromProfiles; New-PostgresRecoveryBackup | Profile planning and recovery-backup selection/copy loops report known-total progress without changing plan order or file results | SOURCE FIXED; OWNER RUNTIME NEEDED | PostgreSQL plan and backup progress/output tests; owner smoke |
| CursorHide profile phases | Invoke-CursorHideSetup | Profile scan, revalidation, update, and final verification report known-total progress | SOURCE FIXED; OWNER RUNTIME NEEDED | CursorHide progress and XML read-back tests; owner smoke |
| Crosshair image discovery/validation and profile planning | Invoke-CrosshairSetup | Every direct user-extensible `Crosshairs\*.png` reports unknown-total discovery progress through filename sorting; the row closes before known-total validation | SOURCE FIXED; OWNER RUNTIME NEEDED | Fixture asserts unknown-total events, sort-before-close, failure closure, candidate names, dynamic browser range, and unchanged P1/P2 outputs; final aggregate source/permanent gate passed at 2026-10-02T12:54:54.9646896Z; packaged owner smoke required |
| HyperSpin optional export scans | Export-HyperSpinJson | System-file lookup, named-file validation, existing-game load/index, and UserProfiles scans report known-total progress; backup/write behavior is unchanged | SOURCE FIXED; OWNER RUNTIME NEEDED | HyperSpin scan/export and mismatched-ID preservation tests; owner smoke |
| Registration game-file discovery | Register-GamesLegacy; Get-GameFiles | Recursive game-file discovery reports unknown-total item progress using a stable label; callback closes after discovery | SOURCE FIXED; OWNER RUNTIME NEEDED | Registration executable-set and discovery-progress tests; owner smoke |
| Restore operations | UserProfiles/LaunchBox/PostgreSQL restore flows | Compact progress covers UserProfiles snapshot/removal/main restore and both legacy rollback phases, plus LaunchBox file restore; PostgreSQL restore remains structured workflow-step status | SOURCE FIXED; OWNER RUNTIME NEEDED | Legacy restore and rollback-helper byte/progress tests; LaunchBox restore test; owner smoke |
| PostgreSQL profile/database setup, backup, and rollback | Backup-PostgresDatabases; Invoke-PostgresGameSetup; Restore-PostgresProfileBackups; Restore-PostgresSetupCreatedDatabases | Compact rows cover profile discovery, per-database backup boundaries, setup preflight/database creation/profile update/final verification, and profile/database rollback | SOURCE FIXED; OWNER RUNTIME NEEDED | PostgreSQL backup/setup/rollback progress tests; owner smoke |
| Support package collection | New-TpmSupportPackage; Get-TpmSupportPluginInventory | Diagnostic/profile/plugin collection and ZIP creation have progress; structured workflow completion follows ZIP creation, identity-bound promotion, and path verification. Embedded workflow evidence is a point-in-time active snapshot, not a false Finished result. | SOURCE FIXED; OWNER RUNTIME NEEDED | SupportPackage.Tests lifecycle-order and artifact evidence tests; owner smoke |
| External waits | Ensure-TeknoParrotProfilesReady; Wait-TpmForProcessClose | User-visible bounded waits with explicit deadlines and no forced close | JUSTIFIED WAITING SURFACE | `PR #321 Progress.Core source inventory` |
| LaunchBox export/write | LaunchBox functions | Compact export, backup, and restore progress added around file loops | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing LaunchBox tests; owner smoke |
| BepInEx package/download/deploy | Invoke-BepInExUpdateCheck | Compact preflight, version-check, and deployment progress added | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing BepInEx tests; owner smoke |
| Crosshair/HyperSpin bounded asset writes, setup, and export | Invoke-CrosshairSetup; Export-CrosshairPreview; Export-HyperSpinJson | Crosshair scans and HyperSpin export scans use compact known-total rows; gallery generation and one-file asset writes remain bounded, renderer-aware no-progress surfaces | CONVERTED TO UNIVERSAL TPM PROGRESS for scans; JUSTIFIED NO PROGRESS SURFACE for bounded writes/renderer interaction | Crosshair profile-planning and HyperSpin scan tests; owner smoke |
| Control Propagation and controls status | Build-ArchetypePool; Invoke-ControlPropagationLegacy; Write-ControlsStatus | Source-pool discovery, per-profile classification, and final status-report generation report known-total progress; ordering, report accounting, status output, and binding behavior remain unchanged | SOURCE FIXED; OWNER RUNTIME NEEDED | `uses an archetype match key only once per target profile`; `reports progress while generating the controls status file`; owner smoke |
| Onboarding readiness action scan | Get-ControlReadinessActionItems | Every registered XML is reported against the known total before catalog filtering; readiness output remains unchanged | SOURCE FIXED; OWNER RUNTIME NEEDED | `surfaces registered abc with wizard complete and missing controls as not ready`; owner smoke |
| Profile membership and setup notes | Get-TpmRegisteredProfileCodes; Get-GameSetupNotes | ReShade/dgVoodoo2 membership and setup-note code enumeration use the shared case-insensitive known-total XML scan | SOURCE FIXED; OWNER RUNTIME NEEDED | Membership/setup-notes fixture test; owner smoke |
| PostgreSQL setup requirement count | Get-TpmPostgresRequirementScan; Invoke-PostgresGameSetup | Required-profile counting reports known-total progress and closes for nonempty, malformed, and empty collections | SOURCE FIXED; OWNER RUNTIME NEEDED | Required/malformed/empty scan behavior tests; owner smoke |
| Library Health profile scans | Invoke-LibraryHealthCheck | Saved-path findings and optional-setup coverage each report and close a known-total per-profile row; operation remains read-only | SOURCE FIXED; OWNER RUNTIME NEEDED | Two-profile read-only findings/progress test; owner smoke |
| Compatibility warning scans | Get-CompatibilityWarnings | Compatibility classification and BIOS/component grouping each report known-total per-profile progress | SOURCE FIXED; OWNER RUNTIME NEEDED | Multi-game BIOS grouping/progress test; owner smoke |
| LaunchBox direct write | Invoke-LaunchBoxDirectWrite | Platform and profile classification reports known-total progress before existing XML write behavior | SOURCE FIXED; OWNER RUNTIME NEEDED | Fixture-backed direct-write output and progress test; owner smoke |
| ReShade bulk conflict scan | Invoke-ReShadeSetupLegacy | Each selected game is checked for an existing trusted-profile conflict against a known-total row; completion closes even if a lookup throws, without changing bulk choice outcomes | SOURCE FIXED; OWNER RUNTIME NEEDED | Selected-set ReShade integration test; owner smoke |
| AutoSync directory and ZIP manifests | Get-TpmDirectoryManifest; Get-TpmAutoSyncZipInventory | Recursive target/staging manifest entries report unknown-total enumeration/hash progress; ZIP inventory hashes each archive entry against its known total | SOURCE FIXED; OWNER RUNTIME NEEDED | Directory/ZIP fixture asserts preserved hashes, inventory decisions, and progress closure; owner smoke |
| BepInEx recursive safety, copy, restore, and reset | Get-BepInExEnumeratedItems; Test-BepInExExistingTreeSafe; Get-BepInExStagedFiles; Test-BepInExBackupEntry; New-BepInExUpdateBackup; Restore-BepInExUpdateBackup; Remove-BepInExFixedTree | Installed/staged/backup descendants and staged/source/backup files report unknown-total streaming discovery before known-total classification/hash verification; fixed-entry recursive copy, restore, and removal report known-total top-level phases; path/reparse gates remain intact | SOURCE FIXED; OWNER RUNTIME NEEDED | Multi-file fixture asserts exact discovery, staged paths, verification, backup/reset progress and preserved bytes; enumeration-failure test asserts closure |
| Nested ZIP source fallback | Get-TpmImmediateZipSubdirectorySummary; Select-GamesInteractive; Invoke-AutoSync | When no ZIP is at source root, the existing one-level subdirectory search reports each directory against the known total while preserving existing ZIP counts and guidance | SOURCE FIXED; OWNER RUNTIME NEEDED | Multi-subdirectory fixture asserts counts and progress closure; owner smoke |
| dgVoodoo2 ZIP entry indexing | Expand-DgVoodoo2Zip | Every downloaded archive entry reports known-total scan progress before exact required-path validation and staging | SOURCE FIXED; OWNER RUNTIME NEEDED | Valid six-file extraction fixture asserts unchanged output bytes and ZIP-scan completion; owner smoke |
| LaunchBox backup menu and restore-source discovery | Invoke-RestoreLaunchBoxBackup | Reports known-total backup-folder progress and streams unknown-total recursive per-file discovery for each menu count and the selected restore snapshot, then preserves known-total copy progress, recency order, displayed counts, and choice mapping | SOURCE FIXED; OWNER RUNTIME NEEDED | Two-backup nested-file fixture asserts exact discovery/restore counts, closure, and selected restore bytes; owner smoke |
| BepInEx staging cleanup | Remove-BepInExStagingDirectory | Streams unknown-total descendant safety checks and reports known-total file and reverse-directory deletion progress; controlled-root, reparse, immediate pre-delete, and residue checks remain intact | SOURCE FIXED; OWNER RUNTIME NEEDED | Isolated nested-tree test asserts exact scan/deletion counts and no residue; deletion-failure test asserts closure; outside-root refusal retained |
| ReShade embedded installer scan | Expand-ReShadeSelfExtractingArchive | Reports bounded-interval known-total PK-byte scanning, signature-offset candidate progress, and known-total archive-entry indexing before staging the first valid candidate | SOURCE FIXED; OWNER RUNTIME NEEDED | Valid and decoy fixtures assert signature/candidate/entry progress and extracted bytes; transactional failure tests retained |
| Support staging recursive cleanup | Remove-TpmSupportOwnedDirectoryTree; Remove-TpmSupportOwnedEntry; Remove-TpmSupportStageDirectory | Streams unknown-total subtree discovery and per-entry removal through the owned-handle recursion; keeps reparse, identity, and residue checks | SOURCE FIXED; OWNER RUNTIME NEEDED | Nested owned-stage fixture asserts exact discovery/removal counts; junction refusal test asserts closure |
| PostgreSQL partial-install cleanup | Remove-PostgresPartialInstall | Streams unknown-total installed-product/profile-registry discovery and reports before opaque MSI/filesystem work; advances during service/profile cleanup and closes in `finally` | SOURCE FIXED; OWNER RUNTIME NEEDED | Mocked fixture asserts progress/closure, exact owned cleanup targets, and unrelated uninstall exclusion |
| AutoSync inventory comparison | Test-TpmDirectoryAgainstZipInventory | Reports known-total indexing across prebuilt ZIP/directory records and known-total entry validation; closes both rows on match or early mismatch | SOURCE FIXED; OWNER RUNTIME NEEDED | Directory/ZIP fixture asserts exact totals, matching bytes, and closure after hash mismatch |
| Startup DAT and notes parsing | Build-DatIndexFromStream; Build-GameNotesIndexFromStream; disk/ZIP wrappers | Emits unknown-total progress at bounded game-record/line intervals before the main menu; reader/progress completion closes on parse failures | SOURCE FIXED; OWNER RUNTIME NEEDED | 205-game DAT fixture and 615-line notes fixture assert parsed content, exact advancement, and closure; malformed DAT asserts failure closure |
| PostgreSQL password-recovery subprocess | Invoke-PostgresSelectedPasswordRecovery; Reset-PostgresPasswordAutomatically; Invoke-PostgresNativeProcessWithInput | Workflow activity announces verified backup, password repair, and verification; the synchronous psql subprocess remains opaque within the active repair stage and has no per-process percentage callback | CONVERTED TO WORKFLOW STATUS; OWNER RUNTIME NEEDED | Existing password-recovery activity and reset transport tests assert stage changes, transport behavior, and result handling |

### ID 3 source closure re-opened -- user-extensible Crosshairs discovery

The independent re-audit correctly found that the earlier census treated the
bundled 321-image Crosshairs set as a fixed bound. README.md permits users to
add arbitrary PNGs, and `Invoke-CrosshairSetup` formerly materialized/sorted
the directory before progress.

The failing-before Windows PowerShell 5.1 regression began at
2026-10-02T10:39:26.5464525Z: expected five unknown-total discovery events,
received zero; completion time was not captured. The fix now reports an
initial unknown total, one event per discovered direct PNG, and a refresh
before sorting; the row closes in `finally` only after sorting finishes.
Enumeration uses `-ErrorAction Stop`, so failures are not silently treated as
an empty or partial image inventory.

The focused Windows PowerShell 5.1/Pester 5.7.1 runs passed the
Crosshair discovery/profile-planning, sort-before-close, enumeration-failure
closure, and dynamic browser-index cases. The 2026-10-02T11:05:14.9045516Z
run passed 2/2, 1274 not run; the separate sort-order run at
2026-10-02T11:07:22.7127742Z passed 1/1, 1275 not run. Candidate ordering
and P1/P2 output assertions remained green.

The source census now includes this formerly missed unbounded directory. Its
discovery and sort no longer complete before progress; the six other residual
expressions remain documented bounded/short-circuit cases. ID 3 is now
`SOURCE FIXED; OWNER RUNTIME NEEDED`; the final full source and permanent
procedure gates passed. Exact-SHA candidate preparation remains subject to
the pushed-source, #290, READY, and authorization gates.

Independent owner-status review also found certification searched all report
prose for candidate/stale wording. The gate now requires exactly one explicit
`Current candidate status` field equal to `VALIDATED` in certification mode;
`STALE`, missing, duplicate, or malformed fields fail closed. Historical stale
prose does not trigger the current-candidate check. The 2026-10-02T10:48:46Z
focused regression passed while retaining owner-runtime blocking. Source mode
still rejects unresolved canonical statuses and explicit `NOT FIXED` paths;
certification still blocks owner-runtime-needed statuses.

The discovery/sort fix is confirmed source-fixed after the failing-before/
passing-after regression, focused coverage, and census closure. The final
full source/permanent gate passed. No pushed source SHA or validated
candidate ZIP exists.

### Slice B -- universal progress/status contract

The earlier source-fixed declaration in this section was superseded by the
independent Crosshairs re-audit. The corrected report records ID 3 as
`SOURCE FIXED; OWNER RUNTIME NEEDED` after unknown-total progress through
sorting, visible enumeration failures, and preserved selection/output.
The final aggregate source/permanent gate passed: PowerShell 7 main Pester
1276/1276; SupportPackage 42/42; ASCII/parse, configured PSScriptAnalyzer,
`git diff --check`, and permanent procedure gate passed. Focused cross-engine
and Windows PowerShell 5.1 full-suite results are recorded above.
Candidate source-ref preparation may proceed; package build remains blocked
on exact pushed-SHA identity, current-cycle #290 repo docs/live-wiki audit,
exact-SHA READY, and human authorization. Eli's owner smoke remains after
candidate handoff.

Two known opaque operations have no per-descendant callbacks:
`ZipFile.CreateFromDirectory` reports only that archive creation is active,
and recursive owned-state backup reports progress at the top-level item
boundary. Interactive pickers and per-profile path-repair prompts remain
visible user-paced surfaces; no fabricated percentage is added. Package
rebuild, owner-runtime proof, and release authorization remain outstanding.

### Slice A -- web/download and thumbnail correctness

Owner IDs 2, 6, and 8 received a bounded source remediation. The web wrapper
continues to expose one typed request-action parameter. The shared downloader
now preserves a definitive HTTP 404 across transport fallback attempts, so
thumbnail setup retains the no-upstream-icon classification even if a later
fallback encounters an unrelated unknown network error. Non-404 transport,
validation, and integrity failures remain retry/failure outcomes. Thumbnail
progress remains compact and profile-labelled, and transient failures retain
named profile accounting for retry.

Package rebuild, owner-runtime proof, and release authorization remain
outstanding.

### Slice C -- ReShade ownership and accounting

Owner IDs 11 and 12 received a bounded source re-audit. The default Select
action protects unknown/user-owned and bundled ReShade files; explicit confirmed
Adopt/replace is the only overwrite path and remains inside the transactional
backup/rollback boundary. ReShade result actions keep protected conflicts ahead
of optional Health Check routing. All-games accounting now includes an explicit
`KeptPrevious` terminal outcome for TPM-managed profiles the operator elects to
leave unchanged, so the accounting total must still equal the selected count.

Focused ReShade coverage and the full main suite pass. Package rebuild,
owner-runtime proof, and release authorization remain outstanding.
Slice 3 also makes the preview contract explicit: the gallery is view-only and
the terminal remains the sole chooser. Normal output names all twelve RC8
beginner-safe profiles, uses full GameName values when available, reports
changeable versus unchanged bulk scope, and gives changed/not-changed/failure
accounting. Unsafe or malformed ownership remains fail-closed with repair,
explicit protected Adopt, skip, and Details/support guidance.

### Crosshair close, focus, and prompt slice -- working-tree status

IDs 13, 14, and 15 were re-audited separately. The generated browser page
enters a completed non-interactive state after P2; the manager now attempts to
close the process it opened and gives explicit close guidance when that is not
available. Console focus return is attempted with a plain-language fallback.
The Crosshair confirmation uses a workflow-aware prompt helper that clears the
status footer before and after input so Y/N remains on the active prompt line.
P1/P2 deployment semantics remain unchanged. Focused Crosshair coverage,
package rebuild, and owner-runtime proof remain outstanding.

## Prompt/gate/back-routing consistency audit
The Progress.Core inventory and classifications are recorded in
`docs/remediation/slices/PR-321-current-slice.md` under "Source inventory".
The prior Prompt.Core contract remains represented by the committed checkpoint.
This report retains the prior prompt audit table below for cross-slice traceability.

2026-10-01 source re-audit: IDs 7, 20, 23-26, and 30 are source-supported
without new source changes. ID 31's reported successful-with-skips screen is
unreachable, but its reachable device-only failure guidance did offer path
repair; the new route recommends reconnecting and exposes Health Check only for
MissingPath. ID 27 restores the post-ZIP O/B route through canonical,
non-reparse folder opening. ID 32 now centralizes the three numbered restore
menus; focused tests cover invalid retry and blank cancellation before
mutation. Package identity and owner-runtime proof remain outstanding.

| Pattern | Locations audited | Converted in TPM-PROMPT-001 | Excluded with documented boundary | Tests |
|---|---|---|---|---|
| Y/N | Optional setup, readiness, and process-wait prompts | `Read-TpmYesNo` owns ordinary Y/N decisions; finite Y/N routes in this slice use centralized readers | Secure/password input, exact-token safety, path/vendor/free text, and stateful pickers | `Read-TpmYesNo validation`; `Read-TpmChoice validation` |
| Invalid input | Main, setup, dynamic path, restore, and result prompts | `Read-TpmChoice` rejects invalid finite choices and re-prompts on the same prompt | Free-text search/path/vendor/profile prompts retain specialized validation | `Read-TpmChoice validation`; `PR #321 prompt and result behavior` restore-route tests |
| Finite choices | LaunchBox, HyperSpin, Support, AutoSync, DAT, startup update, BepInEx, ReShade, dgVoodoo2, GPU, FFB, Health Check, repair, PostgreSQL, staging, restore | Migrated finite choices use `Read-TpmChoice`, including the three numbered restore routes and dynamic path-aware arrays | Stateful picker commands remain documented design boundaries | `Read-TpmChoice validation`; source re-audit |
| Back | LaunchBox, HyperSpin, Support, Health Check, setup/result menus, repair, restore | Enumerated Back/return choices use centralized validation; Support O/B opens only the checked TPM support folder | Enter-only acknowledgements, browser/process wait controls, and stateful picker `back` commands | `PR #321 prompt and result behavior`; owner smoke outstanding |
| Skip | HyperSpin, DAT, BepInEx, optional setup, AutoSync | Finite skip/decline branches use centralized readers where feasible | Search/picker text and exact-token confirmations | `Read-TpmChoice validation`; owner smoke outstanding |
| Cancel | ReShade, dgVoodoo2, GPU, FFB, PostgreSQL, restore | Finite cancel/back routes use centralized readers where feasible | `REMOVE`, `YES`, blank path/vendor, and Enter-only safety/input contracts | `Read-TpmChoice validation`; owner smoke outstanding |
| Preview/Run | AutoSync and LaunchBox | `P/R/B` and `P/A/F/B` routes use centralized validation | ReShade terminal profile/search interaction remains renderer-aware | `Read-TpmChoice validation`; existing preview tests |
| Mutation confirmation | Repair, install, update, restore, ReShade | Finite mutation branches use centralized validation | `YES` and `REMOVE` remain exact-token gates | Existing mutation tests; owner smoke outstanding |
| Optional setup gates | GPU, FFB, dgVoodoo2, BepInEx, ReShade | Finite setup/result menus use centralized validation, including dynamic path-aware choices | GPU vendor, paths, passwords, and stateful selector input | `Read-TpmChoice validation`; owner smoke outstanding |
| Stateful pickers | AutoSync game selection, combined selection, ReShade terminal selector, crosshair/browser flows | No forced one-letter rewrite | Number lists, search terms, terminal keys, redraw, and blank semantics require their own contracts | Follow-up design and runtime proof |
| HyperSpin direct prompts | Missing-emulator-ID flow | `G/S` uses `Read-TpmChoice`; neither route invents an ID or writes game associations | Normal completion runtime proof remains absent | `HyperSpin emulator identity gate`: `defaults a missing emulator ID to Skip without creating or changing games data` |
| Support package prompts | Support main and package-open completion | `1-3` and O/B use `Read-TpmChoice`; O opens the canonical, non-reparse SupportPackages folder | Packaged support runtime proof remains absent | `PR #321 prompt and result behavior`: Support O/Back tests; SupportPackage.Tests |

- ID 3's source census covers user-extensible Crosshairs discovery/sorting; the canonical table records `SOURCE FIXED; OWNER RUNTIME NEEDED` after focused coverage and census closure. The final source/permanent gate passed. Six other residual expressions are bounded/short-circuit. IDs 7, 20, 23-27, and 30-32 are source-supported after re-audit; IDs 27, 31, and 32 have focused source fixes. ID 29 is source-fixed, including duplicate nested plugin-root elimination; exact-package and owner-runtime proof remain outstanding.
 - `TPM-RESHADE-001` protects unknown/custom ReShade files by default, gates adopt/replace behind explicit action and backup, reports preflight buckets, and enforces exact final accounting.
 - `TPM-LIBRARY-HEALTH-001` limits repair and optional recopy to affected profile codes, requires saved-path read-back, and classifies every repair report exactly once.
 - `TPM-CONTROLS-001` separates saved configuration, inferred readiness, and observed physical binding; propagation reports zero verified physical bindings because TPM does not test device input.
- PR #321 remains release-blocked on exact package identity and owner-runtime proof. Candidate preparation is conditional on all source gates and an exact pushed SHA; Eli's owner smoke awaits that candidate. No merge, tag, publication, or release action has occurred.

## Affected-games repair-flow scoping audit

- One affected game: source path uses the broken profile-code collection.
- Multiple affected games: source path passes all broken profile codes through the scoped handoff.
- Zero affected games: no repair should be offered; packaged runtime proof is absent.
- No-candidate result: source reporting exists; packaged runtime proof is absent.
- Back returns to main menu: source route exists; packaged runtime proof is absent.
- No BBHWorld hardcode exists in the inspected repair implementation.
- Full AutoSync escape: source-only evidence indicates affected-code filtering; runtime proof is absent.
- Thumbnails: no scoped-repair runtime proof.
- LaunchBox: no scoped-repair runtime proof.
- HyperSpin: no scoped-repair runtime proof.
- Controls propagation: no scoped-repair runtime proof.

- Status: SOURCE FIXED for the Slice E repair-flow cases; OWNER RUNTIME NEEDED for packaged and owner-runtime proof. One/multiple/zero/no-candidate coverage is present in source and focused tests.
### Slice E -- Library Health repair scope


Owner IDs 17, 18, 19, 21, and 22 received a bounded source re-audit.
Candidate search and reviewed apply remain limited to the affected broken
profile codes. One, multiple, zero, and no-candidate paths retain explicit
outcomes and Back routing. Repair writes require a complete profile backup and
saved-path read-back before `FIXED` is reported. Repair result accounting now
classifies every report once as fixed, candidate, or still broken. Optional
source recopy re-enters AutoSync with `OnlyProfileCodes` restricted to the
affected set, and the repair result completes before the optional thumbnail
prompt.

Package rebuild, owner-runtime proof, and release authorization remain
outstanding.
### Slice D -- PostgreSQL recovery

Owner ID 16 received the Slice 8B source implementation after owner evidence
showed that the prior readable-name and diagnosis contracts were incomplete.
Registered PostgreSQL profiles now resolve normal names from authoritative
`/GameProfile/GameName` metadata and use `Unknown game title -- see Details`
when that value is absent. Profile keys and database names remain technical
evidence only; normal read-only diagnosis groups safe categories, removes
identifier-bearing check names, and collapses repeated `Backup detail:
Reported` rows. Details, logs, and support guidance retain the profile key,
database, category, and redacted raw detail.

Automatic reset results now expose a specific `FailureStage`, preserve that
stage through the recovery wrapper, render beginner-safe stage guidance, and
update workflow status during password validation and reset. The password
validation (`P`) and local reset (`X`) branches remain separate from
reinitialize (`I`).

Focused Slice 8B tests cover authoritative and missing-title fixtures, normal
diagnosis exclusions, technical evidence retention, reset stages and guidance,
workflow activities, and password/reset routing. The protected-resume exit
slice additionally guarantees that every elevated child terminal path exits
without `Read-HostSafe`/`Read-Host`; ordinary non-resume prompts remain
interactive. Contract: `TPM-POSTGRES-RESUME-EXIT-001`. Package rebuild and
owner-runtime proof remain outstanding.
### Slice F -- Support evidence scoping

Owner ID 29 received a bounded support-evidence re-audit. Action Required
freshness is compared with the latest TPM log and labeled stale when older.
Current-run records remain distinct from Ambient evidence supplied or
discovered without current-workflow provenance. Game-local BepInEx logs and
metadata-only plugin inventories, including FamilyGuy-style findings, remain
Ambient; plugin payloads are not copied. Allowlist, redaction, manifest, and
ZIP-entry invariants remain covered by SupportPackage.Tests.

Package rebuild and owner-runtime proof remain outstanding.




## Support package/fatal surfacing audit

- Fatal workflow fallback when metadata is unavailable: source implementation and SupportPackage.Tests coverage exist.
- Newest Action Required inclusion: source selects newest `*ActionItems*.txt`; SupportPackage.Tests coverage exists.
- Stale evidence labeled stale: manifest source implementation exists.
- Support final prompt: SOURCE FIXED; `O/B` behavior is covered by Prompt.Core source contracts; runtime proof remains outstanding.
- Fresh owner-runtime support package proof: outstanding.

## Tests with exact counts and timestamps
| Gate/test | Exact command | Count/result | Started UTC | Finished UTC | Engine/version |
|---|---|---|---|---|---|
| 2026-09-30 source quality gate | `Run-TpmQualityGate.ps1 -RepoRoot C:\\REPOS\\tpm-rc8-determinism-integration -ReportPath C:\\REPOS\\tpm-rc8-determinism-integration\\docs\\remediation\\PR-321-reconciliation.md` | Main Pester 1176 passed, 0 failed, 0 skipped, 0 not run; SupportPackage 41 passed, 0 failed, 0 skipped, 0 not run; ASCII/parse, PSScriptAnalyzer, and `git diff --check` passed; permanent-procedure phase reached and failed only because this report still predated the final governance edits | 2026-09-30T10:56:57 | 2026-09-30T11:10:55 | Pester 6.1.0 / pwsh |
| 2026-09-30 permanent-procedure source gate | `Test-TpmPermanentProcedures.ps1 -RepoRoot <absolute worktree> -ReportPath <absolute report> -SourcePath <absolute source> -ChangedAtUtc <latest governed-input UTC>` | PASS; governed-input freshness boundary `2026-09-30T10:56:11`; owner-runtime evidence remains separately pending | 2026-09-30T11:12:33 | 2026-09-30T11:12:33 | Windows PowerShell / pwsh-compatible script |
| PostgreSQL reset transport focused Pester (PS7) | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*automatic reset*','*low-level reset mechanics*','*single-user transport*') -PassThru` | 15 passed, 0 failed, 0 skipped, 1172 not run | 2026-10-01T01:25:45 | 2026-10-01T01:25:58 | PowerShell 7 / Pester 5.7.1 |
| PostgreSQL reset transport focused Pester (Windows PowerShell 5.1) | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*automatic reset*','*low-level reset mechanics*','*single-user transport*') -PassThru` | 15 passed, 0 failed, 0 skipped, 1172 not run | 2026-10-01T01:26:08 | 2026-10-01T01:26:22 | Windows PowerShell 5.1 / Pester 5.7.1 |
| PostgreSQL reset and guidance follow-up focused Pester (Windows PowerShell 5.1) | `powershell.exe -NoProfile -Command "Import-Module Pester -RequiredVersion 5.7.1; Invoke-Pester -Path './Tests/TeknoParrot-Manager.Tests.ps1' -FullNameFilter '*automatic reset*','*beginner-safe guidance*','*password recovery activity*' -CI"` | 16 passed, 0 failed, 0 skipped, 1171 not run; result observed by 2026-10-01T02:13:33Z. The earlier 15-test run used different filters (`*low-level reset mechanics*`, `*single-user transport*`). | not captured | not captured | Windows PowerShell 5.1 / Pester 5.7.1 |
| Main Pester (Slice 8B historical checkpoint) | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -CI -Output Normal` | 1052 passed, 0 failed, 0 skipped | not captured | not captured | Pester 5.7.1 |
| TPM source quality gate before follow-up corrections | `pwsh -NoProfile -File scripts/Run-TpmQualityGate.ps1 -ReportPath docs/remediation/PR-321-reconciliation.md` | Main Pester 1187 passed, 0 failed, 0 skipped, 0 not run; SupportPackage 41 passed, 0 failed, 0 skipped, 0 not run; parse/ASCII, PSScriptAnalyzer, diff check, and permanent procedure gate passed | 2026-10-01T01:27:12 | 2026-10-01T01:40:29 | PowerShell 7 / Pester 5.7.1 |
| 2026-10-01 follow-up suite rerun | `pwsh -NoProfile -File ./scripts/Run-TpmQualityGate.ps1 -ReportPath ./docs/remediation/PR-321-reconciliation.md` | Main Pester 1187 passed, 0 failed, 0 skipped, 0 not run; SupportPackage 41 passed, 0 failed, 0 skipped, 0 not run; parse/ASCII, PSScriptAnalyzer, and `git diff --check` passed. Quality-gate command failed only because permanent-procedure freshness evidence was older than the latest source/test edits; result observed by 2026-10-01T02:13:33Z. | not captured | not captured | PowerShell 7 / Pester 5.7.1 |
| 2026-10-01 permanent procedure recheck | `Test-TpmPermanentProcedures.ps1 -RepoRoot C:\REPOS\teknoparrot-manager -ReportPath C:\REPOS\teknoparrot-manager\docs\remediation\PR-321-reconciliation.md -SourcePath C:\REPOS\teknoparrot-manager\TeknoParrot-Manager.ps1 -ChangedAtUtc 2026-10-01T01:50:17.7041915Z` | PASS; latest governed-input freshness boundary 2026-10-01T01:50:17.7041915Z | 2026-10-01T02:15:43 | 2026-10-01T02:15:43 | PowerShell 7 |
| 2026-10-01 final TPM quality gate after evidence refresh | `pwsh -NoProfile -File ./scripts/Run-TpmQualityGate.ps1 -ReportPath ./docs/remediation/PR-321-reconciliation.md` | PASS; Main Pester 1187 passed, 0 failed, 0 skipped, 0 not run; SupportPackage 41 passed, 0 failed, 0 skipped, 0 not run; ASCII/parse, PSScriptAnalyzer, `git diff --check`, and permanent procedure gate passed; output observed by 2026-10-01T02:30:24Z | not captured | not captured | PowerShell 7 / Pester 5.7.1 |
| Slice A focused Pester | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*Invoke-TpmDownload*','*Thumbnail*','*RC8 PostgreSQL and support UX*') -CI -Output Normal` | 54 passed, 0 failed, 0 skipped, 975 not run | not captured | not captured | Pester 5.7.1 |
| SupportPackage Pester (current) | `Invoke-Pester -Path .\Tests\SupportPackage.Tests.ps1 -CI -Output Normal -PassThru` | 41 passed, 0 failed, 0 skipped, 0 not run | 2026-10-01T01:02:37 | 2026-10-01T01:03:05 | PowerShell 7 / Pester 5.7.1 |
| Controls focused Pester | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter '*Write-ControlPropagationResults*' -Output Detailed` | 3 passed, 0 failed, 0 skipped | not captured | not captured | Pester 6.1.0 |
| ReShade focused Pester | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*ReShade*','*protected adoption and accounting*','*ReShade result action priority*') -CI -Output Normal` | 192 passed, 0 failed, 0 skipped, 837 not run | not captured | not captured | Pester 5.7.1 |
| Progress.Core focused Pester | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter '*Progress.Core*' -Output Detailed` | 2 passed, 0 failed, 0 skipped at prior checkpoint | not captured | not captured | Pester 6.1.0 |
| Prompt.Core focused Pester | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter '*Prompt.Core*' -Output Detailed` | 4 passed, 0 failed, 0 skipped at prior checkpoint | not captured | not captured | Pester 6.1.0 |
| Slice D focused Pester | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*RC8 PostgreSQL*','*Postgres guided recovery*','*New-PostgresPgPassFile*') -CI -Output Normal` | 44 passed, 0 failed, 0 skipped, 986 not run | not captured | not captured | Pester 5.7.1 |
| Slice 8B focused Pester | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*PostgreSQL Slice 8B*','*Postgres guided recovery*','*RC8 PostgreSQL*','*PostgreSQL recovery runtime hold*','*PostgreSQL grouped diagnosis*') -CI -Output Normal` | 54 passed, 0 failed, 0 skipped, 998 not run | not captured | not captured | Pester 5.7.1 |
| Slice E focused Pester | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*Library Health*','*Repair-GamePaths*','*repair*','*scoped*','*affected*') -CI -Output Normal` | 33 passed, 0 failed, 0 skipped, 996 not run | prior Slice E checkpoint | prior Slice E checkpoint | Pester 5.7.1 |
| Slice F focused Pester | `Invoke-Pester -Path .\Tests\SupportPackage.Tests.ps1 -FullNameFilter @('*freshness*','*ambient*','*BepInEx*','*plugin*','*manifest*','*ZIP*','*allowlist*','*redact*') -CI -Output Normal` | 16 passed, 0 failed, 0 skipped, 25 not run | not captured | not captured | Pester 5.7.1 |
| SupportPackage full Pester | `Invoke-Pester -Path .\Tests\SupportPackage.Tests.ps1 -CI -Output Normal` | 41 passed, 0 failed, 0 skipped | not captured | not captured | Pester 5.7.1 |
| Governance/source parse, ASCII, registry, PSScriptAnalyzer, InjectionHunter, diff | Final static-check commands; individual start/finish timestamps not captured | 0 production parse errors; 0 PSScriptAnalyzer findings; production ASCII 0; InjectionHunter 42 findings, 0 unresolved, tool 1.0.0; diff check clean | not captured | not captured | pwsh / PSScriptAnalyzer / InjectionHunter |
| Historical permanent procedure gate (pre-census/status closure) | `.\scripts\Test-TpmPermanentProcedures.ps1 -RepoRoot . -SourcePath .\TeknoParrot-Manager.ps1 -ReportPath .\docs\remediation\PR-321-reconciliation.md` | Historical block for unresolved owner statuses; superseded by the complete census, canonical owner-status regression, and final fresh-gate rerun below. Owner-runtime evidence remains outstanding | not captured | not captured | pwsh |
| Slice 6 focused Pester | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -CI -Output Normal -FullName '*migration*','*DAT*','*Eggman*'` | 192 passed, 0 failed, 0 skipped, 848 not run | not captured | not captured | Pester 5.7.1 |
| Slice 7 focused Pester | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -CI -Output Normal -FullName '*product wording*','*migration*','*latest DAT*'` | 6 passed, 0 failed, 0 skipped, 1035 not run | not captured | not captured | Pester 5.7.1 |
| PostgreSQL pre-UAC guidance focused Pester (PS7) | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter '*RC8 PostgreSQL and support UX*','*Postgres guided recovery*','*PostgreSQL Slice 8B*' -CI -Output Normal` | 60 passed, 0 failed, 0 skipped, 1128 not run | 2026-10-01T04:34:24 | 2026-10-01T04:35:13 | PowerShell 7 / Pester 5.7.1 |
| PostgreSQL pre-UAC guidance focused Pester (Windows PowerShell 5.1) | `powershell.exe -NoProfile -Command "Import-Module Pester -RequiredVersion 5.7.1; Invoke-Pester -Path './Tests/TeknoParrot-Manager.Tests.ps1' -FullNameFilter '*RC8 PostgreSQL and support UX*','*Postgres guided recovery*','*PostgreSQL Slice 8B*' -CI -Output Normal"` | 60 passed, 0 failed, 0 skipped, 1128 not run | 2026-10-01T04:35:14 | 2026-10-01T04:36:16 | Windows PowerShell 5.1 / Pester 5.7.1 |
| TPM source quality gate | `pwsh -NoProfile -File ./scripts/Run-TpmQualityGate.ps1 -ReportPath ./docs/remediation/PR-321-reconciliation.md` | Main Pester 1188 passed, 0 failed; SupportPackage 41 passed, 0 failed; ASCII/parse, PSScriptAnalyzer, diff check, and permanent procedure gate passed | not captured | observed complete by 2026-10-01T04:52:36Z | PowerShell 7 / Pester 5.7.1 |
| InjectionHunter production-script scan | `Invoke-ScriptAnalyzer -Path ./TeknoParrot-Manager.ps1 -CustomRulePath C:/Users/EliSi/OneDrive/Documents/PowerShell/Modules/InjectionHunter/1.0.0/InjectionHunter.psm1` plus matching against `scripts/InjectionHunterDispositions.psd1` | 30 findings; all 30 matched individually reviewed FalsePositive entries; 0 unmatched/unresolved. Fixed regex/replacement literals, assembly names, bounded internal properties, and fixed argument-array quoting; no new finding from this guidance change. | not captured | observed complete by 2026-10-01T05:00:36Z | pwsh / PSScriptAnalyzer / InjectionHunter 1.0.0 |
| Compact progress focused Pester (PowerShell 7) | `pwsh -NoProfile -Command "Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*progress*','*reports protected, missing, and ready ReShade preflight buckets*') -Output Normal"` | 43 passed, 0 failed, 0 skipped, 1168 not run | not captured | not captured | PowerShell 7 / Pester 5.7.1 |
| Compact progress focused Pester (Windows PowerShell 5.1) | `powershell.exe -NoProfile -Command "Import-Module Pester -RequiredVersion 5.7.1; Invoke-Pester -Path '.\Tests\TeknoParrot-Manager.Tests.ps1' -FullNameFilter @('*progress*','*reports protected, missing, and ready ReShade preflight buckets*') -Output Normal"` | 43 passed, 0 failed, 0 skipped, 1168 not run | not captured | not captured | Windows PowerShell 5.1 / Pester 5.7.1 |
| FFB save/read-back progress contract (PowerShell 7) | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter '*returns SUCCEEDED only after FFB save read-back verification*' -Output Normal` | 1 passed, 0 failed, 0 skipped, 1210 not run | not captured | not captured | PowerShell 7 / Pester 5.7.1 |
| FFB save/read-back progress contract (Windows PowerShell 5.1) | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter '*returns SUCCEEDED only after FFB save read-back verification*' -Output Normal` | 1 passed, 0 failed, 0 skipped, 1210 not run | not captured | not captured | Windows PowerShell 5.1 / Pester 5.7.1 |
| ReShade removal progress and rollback (PowerShell 7) | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*requires confirmation and removes only verified owned files*','*rolls back removed files and ownership when manifest commit fails*')` | 2 passed, 0 failed, 0 skipped, 1209 not run | not captured | not captured | PowerShell 7 / Pester 5.7.1 |
| ReShade removal progress and rollback (Windows PowerShell 5.1) | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*requires confirmation and removes only verified owned files*','*rolls back removed files and ownership when manifest commit fails*')` | 2 passed, 0 failed, 0 skipped, 1209 not run | not captured | not captured | Windows PowerShell 5.1 / Pester 5.7.1 |
| Full SupportPackage Pester (PowerShell 7) | `Invoke-Pester -Path .\Tests\SupportPackage.Tests.ps1 -Output Normal` | 41 passed, 0 failed, 0 skipped, 0 not run | not captured | not captured | PowerShell 7 / Pester 5.7.1 |
| Full SupportPackage Pester (Windows PowerShell 5.1) | `Invoke-Pester -Path .\Tests\SupportPackage.Tests.ps1 -Output Normal` | 41 passed, 0 failed, 0 skipped, 0 not run | not captured | not captured | Windows PowerShell 5.1 / Pester 5.7.1 |
| Unique metadata-only plugin inventory rows (PowerShell 7) | `Invoke-Pester -Path .\Tests\SupportPackage.Tests.ps1 -FullNameFilter '*generates metadata-only plugin inventories*' -Output Normal` | 1 passed, 0 failed, 0 skipped, 40 not run; confirms nested roots do not duplicate file rows | not captured | not captured | PowerShell 7 / Pester 5.7.1 |
| Unique metadata-only plugin inventory rows (Windows PowerShell 5.1) | `Invoke-Pester -Path .\Tests\SupportPackage.Tests.ps1 -FullNameFilter '*generates metadata-only plugin inventories*' -Output Normal` | 1 passed, 0 failed, 0 skipped, 40 not run; confirms nested roots do not duplicate file rows | not captured | not captured | Windows PowerShell 5.1 / Pester 5.7.1 |
| Initial full main Pester before FFB assertion correction | `pwsh -NoProfile -Command "Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -Output None -PassThru"` | Historical checkpoint: 1210 passed, 1 failed because the test expected four `GameA` progress calls; the assertion was corrected to four stable phase rows. Subsequent final full suites passed 1215/1215 in both engines. | not captured | not captured | PowerShell 7 / Pester 5.7.1 |
| Canonical InjectionHunter production inventory | `Test-TPMProductionInjectionHunterV1` via `scripts\TPMCertification.ProductionFacts.psm1` and `scripts\InjectionHunterDispositions.psd1` | Executed=True; 42 findings; 0 unresolved; tool 1.0.0 | 2026-10-01T15:25:00.5224436Z | 2026-10-01T15:26:14.2878238Z | PowerShell 7 / InjectionHunter 1.0.0 |
| Owner-status focused regressions (PowerShell 7) | `Invoke-Pester -Path Tests/TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*requires the TPM remediation and prompt-slice artifacts','*classifies every registry owner status and blocks unresolved dispositions','*uses canonical owner statuses and scopes stale-package rejection to certification mode') -Output Minimal -PassThru` | 3 passed, 0 failed, 0 skipped; 1212 not run | 2026-10-01T16:51:51.1844623Z | 2026-10-01T16:52:09.7004586Z | PowerShell 7 / Pester 5.7.1 |
| Owner-status focused regressions (Windows PowerShell 5.1) | `Invoke-Pester -Path Tests/TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*requires the TPM remediation and prompt-slice artifacts','*classifies every registry owner status and blocks unresolved dispositions','*uses canonical owner statuses and scopes stale-package rejection to certification mode') -Output Minimal -PassThru` | 3 passed, 0 failed, 0 skipped; 1212 not run | 2026-10-01T16:51:50.4926162Z | 2026-10-01T16:52:09.7888442Z | Windows PowerShell 5.1 / Pester 5.7.1 |
| Full main Pester suite | `Invoke-Pester -Path Tests/TeknoParrot-Manager.Tests.ps1 -Output Minimal -PassThru` | 1215 passed, 0 failed, 0 skipped, 0 not run | 2026-10-01T16:40:02.3709216Z | 2026-10-01T16:45:48.0170799Z | PowerShell 7 / Pester 5.7.1 |
| Full main Pester suite | `Invoke-Pester -Path Tests/TeknoParrot-Manager.Tests.ps1 -Output Minimal -PassThru` | 1215 passed, 0 failed, 0 skipped, 0 not run | 2026-10-01T16:40:02.1539328Z | 2026-10-01T16:44:07.6395395Z | Windows PowerShell 5.1 / Pester 5.7.1 |
| Full SupportPackage Pester suite | `Invoke-Pester -Path Tests/SupportPackage.Tests.ps1 -Output Minimal -PassThru` | 41 passed, 0 failed, 0 skipped, 0 not run | 2026-10-01T16:40:02.3699062Z | 2026-10-01T16:40:24.2282148Z | PowerShell 7 / Pester 5.7.1 |
| Full SupportPackage Pester suite | `Invoke-Pester -Path Tests/SupportPackage.Tests.ps1 -Output Minimal -PassThru` | 41 passed, 0 failed, 0 skipped, 0 not run | 2026-10-01T16:40:02.1594479Z | 2026-10-01T16:40:19.1711836Z | Windows PowerShell 5.1 / Pester 5.7.1 |
| Final static checks | Windows PowerShell 5.1 parser/ASCII/registry validation; PSScriptAnalyzer for product and governance scripts; `git diff --check` | Production ASCII non-ASCII bytes 0; five PowerShell files parsed with 0 errors; registry 7 statuses/7 dispositions; product PSScriptAnalyzer 0 findings; governance-script analyzer 0 findings; diff check passed | not captured | not captured | Windows PowerShell 5.1 / PowerShell 7 |
| Full ReShade profile/deployment/preview filter (PowerShell 7) | `Invoke-Pester -Path Tests/TeknoParrot-Manager.Tests.ps1 -FullNameFilter '*ReShade*' -Output Normal` | 207 passed, 0 failed, 0 skipped; 1017 not run | not captured | not captured | PowerShell 7 / Pester 5.7.1 |
| Full main Pester (PowerShell 7) | `Invoke-Pester -Path Tests/TeknoParrot-Manager.Tests.ps1 -PassThru -Output Normal` | 1224 passed, 0 failed, 0 skipped, 0 not run | not captured | not captured | PowerShell 7 / Pester 5.7.1 |
| Full SupportPackage Pester (PowerShell 7) | `Invoke-Pester -Path Tests/SupportPackage.Tests.ps1 -PassThru -Output Normal` | 41 passed, 0 failed, 0 skipped, 0 not run | 2026-10-01T23:19:44 | 2026-10-01T23:20:03 | PowerShell 7 / Pester 5.7.1 |
| Full main Pester (Windows PowerShell 5.1) | `Invoke-Pester -Path Tests/TeknoParrot-Manager.Tests.ps1 -PassThru -Output Normal` | 1224 passed, 0 failed, 0 skipped, 0 not run | 2026-10-01T23:20:20 | 2026-10-01T23:24:51 | Windows PowerShell 5.1 / Pester 5.7.1 |
| Full SupportPackage Pester (Windows PowerShell 5.1) | `Invoke-Pester -Path Tests/SupportPackage.Tests.ps1 -PassThru -Output Normal` | 41 passed, 0 failed, 0 skipped, 0 not run | 2026-10-01T23:25:05 | 2026-10-01T23:25:19 | Windows PowerShell 5.1 / Pester 5.7.1 |
| Static source gates | PS7 and Windows PowerShell 5.1 ASCII/parser checks for main, main tests, and quality wrapper; project-settings PSScriptAnalyzer for main script | Non-ASCII bytes 0; parser errors 0 in both engines; PSScriptAnalyzer findings 0 | not captured | not captured | PowerShell 7 / Windows PowerShell 5.1 |
| Full main Pester after test-file whitespace cleanup (Windows PowerShell 5.1) | `Invoke-Pester -Path Tests/TeknoParrot-Manager.Tests.ps1 -PassThru -Output Normal` | 1224 passed, 0 failed, 0 skipped, 0 not run | 2026-10-01T23:40:28 | 2026-10-01T23:44:42 | Windows PowerShell 5.1 / Pester 5.7.1 |
| Full SupportPackage Pester after test-file whitespace cleanup (Windows PowerShell 5.1) | `Invoke-Pester -Path Tests/SupportPackage.Tests.ps1 -PassThru -Output Normal` | 41 passed, 0 failed, 0 skipped, 0 not run | 2026-10-01T23:44:42 | 2026-10-01T23:44:53 | Windows PowerShell 5.1 / Pester 5.7.1 |
| Run-TpmQualityGate.ps1 (source mode) | `powershell.exe -NoProfile -Command` launching `pwsh.exe -NoProfile -File scripts/Run-TpmQualityGate.ps1 -ReportPath docs/remediation/PR-321-reconciliation.md` | Main Pester 1224/1224; SupportPackage 41/41; static and diff-check stages passed (line-ending warning only); permanent procedure gate blocked only by unresolved ID 3; wrapper exit 1 | 2026-10-01T23:57:50 | 2026-10-02T00:07:10 | PowerShell 7 / Pester 5.7.1 |
| Historical full main Pester before final Crosshairs discovery/sort and owner-gate regressions | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -CI -Output Minimal -PassThru` | 1276 passed, 0 failed, 0 skipped, 0 not run on earlier source/test bytes; superseded by the final frozen rerun below | 2026-10-02T10:07:21.6446355Z | 2026-10-02T10:12:41.3237390Z | Windows PowerShell 5.1 / Pester 5.7.1 |
| Historical full SupportPackage Pester before final Crosshairs source edit | `Invoke-Pester -Path .\Tests\SupportPackage.Tests.ps1 -CI -Output Minimal -PassThru` | 42 passed, 0 failed, 0 skipped, 0 not run on earlier source bytes; superseded by the final frozen rerun below | 2026-10-02T09:49:06.4301639Z | 2026-10-02T09:49:23.5514230Z | Windows PowerShell 5.1 / Pester 5.7.1 |
| Catalog discovery/scan closure regressions | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*Get-GpuFixFieldNames reports catalog scan progress*','*Get-GpuAndFfbFieldNames reports catalog scan progress*','*Build-ProfileIndex reports progress for every catalog profile*','*Get-FFBBlasterFieldNames reports catalog scan progress*','*Get-TeknoParrotProfileSet reports known-total local fallback progress*') -CI -Output Minimal -PassThru` | 5 passed, 0 failed, 0 skipped; 1271 not run | not captured | not captured | Windows PowerShell 5.1 / Pester 5.7.1 |
| Product PSScriptAnalyzer | `Invoke-ScriptAnalyzer -Path .\TeknoParrot-Manager.ps1 -Severity Error,Warning -Settings .\PSScriptAnalyzerSettings.psd1` | 0 findings | not captured | not captured | Windows PowerShell 5.1 / PSScriptAnalyzer |
| Canonical InjectionHunter inventory | `Test-TPMProductionInjectionHunterV1` via `scripts\TPMCertification.ProductionFacts.psm1` and `scripts\InjectionHunterDispositions.psd1` | Executed=True; 42 findings; 0 unresolved; tool 1.0.0 | not captured | not captured | Windows PowerShell 5.1 / InjectionHunter 1.0.0 |
| Previous post-status Run-TpmQualityGate attempt | `pwsh.exe -NoProfile -File ./scripts/Run-TpmQualityGate.ps1 -ReportPath ./docs/remediation/PR-321-reconciliation.md` | Main Pester 1275 passed, 1 failed (stale-package diagnostic wrapping assertion); SupportPackage 42/42; ASCII/parse, PSScriptAnalyzer, and diff-check passed. Permanent procedure gate blocked on an inapplicable required `NOT FIXED` category and stale validation timestamps. Gate/test correction follows; superseded by final runs below. | not captured | not captured | pwsh / Pester |
| Owner-status gate regression (Windows PowerShell 5.1) | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter '*uses canonical owner statuses and scopes stale-package rejection to certification mode*' -CI -Output Minimal -PassThru` | 1 passed, 0 failed, 0 skipped; 1275 not run | 2026-10-02T10:05:38.1599617Z | 2026-10-02T10:05:55.8132227Z | Windows PowerShell 5.1 / Pester 5.7.1 |
| Final focused catalog/status gate regressions (Windows PowerShell 5.1) | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*Get-GpuFixFieldNames reports catalog scan progress*','*Get-GpuAndFfbFieldNames reports catalog scan progress*','*Build-ProfileIndex reports progress for every catalog profile*','*Get-FFBBlasterFieldNames reports catalog scan progress*','*Get-TeknoParrotProfileSet reports known-total local fallback progress*','*uses canonical owner statuses and scopes stale-package rejection to certification mode*') -CI -Output Minimal -PassThru` | 6 passed, 0 failed, 0 skipped; 1270 not run | 2026-10-02T10:15:55.3515017Z | 2026-10-02T10:16:14.6449148Z | Windows PowerShell 5.1 / Pester 5.7.1 |
| Previous Run-TpmQualityGate (PowerShell 7; pre-Crosshairs re-audit) | `powershell.exe -NoLogo -NoProfile -Command` launching `pwsh.exe -NoProfile -File ./scripts/Run-TpmQualityGate.ps1 -ReportPath ./docs/remediation/PR-321-reconciliation.md` | Historical PASS on earlier bytes: Main Pester 1276/1276; SupportPackage 42/42; ASCII/parse, PSScriptAnalyzer, diff check, and permanent procedure gate passed; does not include the later Crosshairs discovery regression or independent re-audit | 2026-10-02T10:19:40.0850443Z | 2026-10-02T10:29:33.3911233Z | PowerShell 7 / Pester 5.7.1 |
| Crosshairs user-added PNG discovery regression before implementation (Windows PowerShell 5.1) | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter '*Crosshair profile-planning progress*' -CI -Output Minimal -PassThru` | Expected failing-before result: 0 passed, 1 failed, 1275 not run; `Expected 5, but got 0` for unknown-total discovery events. Completion timestamp was not captured. | 2026-10-02T10:39:26.5464525Z | not captured | Windows PowerShell 5.1 / Pester 5.7.1 |
| Historical focused Crosshairs and owner-status regressions before Sort-Object mock fallback correction (Windows PowerShell 5.1) | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*Crosshair profile-planning progress*','*rejects invalid browser selection tokens and indexes*','*uses canonical owner statuses and scopes stale-package rejection to certification mode*') -Output Minimal -PassThru` | 3 passed, 0 failed, 0 skipped; 1273 not run on earlier test bytes; superseded by the cross-engine reruns below | 2026-10-02T11:18:14.7194510Z | 2026-10-02T11:18:40.1412707Z | Windows PowerShell 5.1 / Pester 5.7.1 |
| Historical full main Pester suite before Sort-Object mock fallback correction | `powershell.exe -NoLogo -NoProfile -Command "Import-Module Pester -RequiredVersion 5.7.1; Invoke-Pester -Path './Tests/TeknoParrot-Manager.Tests.ps1' -CI -Output Minimal -PassThru"` | 1276 passed, 0 failed, 0 skipped, 0 not run on earlier test bytes; superseded by the final frozen rerun below | 2026-10-02T11:20:21.5718799Z | 2026-10-02T11:26:35.3125846Z | Windows PowerShell 5.1 / Pester 5.7.1 |
| Final frozen full main Pester suite after Sort-Object mock fallback correction | `powershell.exe -NoLogo -NoProfile -Command "Import-Module Pester -RequiredVersion 5.7.1; Invoke-Pester -Path './Tests/TeknoParrot-Manager.Tests.ps1' -CI -Output Minimal -PassThru"` | 1276 passed, 0 failed, 0 skipped, 0 not run | 2026-10-02T12:02:15.9362857Z | 2026-10-02T12:07:55.7168071Z | Windows PowerShell 5.1 / Pester 5.7.1 |
| Final frozen full SupportPackage Pester suite | `powershell.exe -NoLogo -NoProfile -Command "Import-Module Pester -RequiredVersion 5.7.1; Invoke-Pester -Path './Tests/SupportPackage.Tests.ps1' -CI -Output Minimal -PassThru"` | 42 passed, 0 failed, 0 skipped, 0 not run | 2026-10-02T11:21:38.0145176Z | 2026-10-02T11:21:55.4470819Z | Windows PowerShell 5.1 / Pester 5.7.1 |
| Pester 6.1.0 focused regression before mock fallback correction (PowerShell 7) | `Invoke-Pester -Path ./Tests/TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*Crosshair profile-planning progress*','*rejects invalid browser selection tokens and indexes*','*requires the TPM remediation and prompt-slice artifacts*','*classifies every registry owner status and blocks unresolved dispositions*','*uses canonical owner statuses and scopes stale-package rejection to certification mode*') -Output Detailed -PassThru` | 4 passed, 1 failed, 1271 not run. Crosshair profile-planning test failed because its filtered `Sort-Object Name` mock had no default for the later `Sort-Object BaseName` call. Corrected by adding an unfiltered pass-through mock using the saved cmdlet. | 2026-10-02T11:57:15.0590638Z | not captured | PowerShell 7 / Pester 6.1.0 |
| Crosshairs and browser-index regressions after mock fallback correction (PowerShell 7) | `Import-Module Pester -RequiredVersion 5.7.1; Invoke-Pester -Path ./Tests/TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*Crosshair profile-planning progress*','*rejects invalid browser selection tokens and indexes*') -Output Detailed -PassThru` | 2 passed, 0 failed, 1274 not run | 2026-10-02T11:59:25.7321105Z | 2026-10-02T11:59:32.8435855Z | PowerShell 7 / Pester 5.7.1 |
| Crosshairs and browser-index regressions after mock fallback correction (Windows PowerShell 5.1) | `Invoke-Pester -Path ./Tests/TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*Crosshair profile-planning progress*','*rejects invalid browser selection tokens and indexes*') -Output Detailed -PassThru` | 2 passed, 0 failed, 1274 not run | 2026-10-02T11:59:41.9715159Z | 2026-10-02T11:59:48.9085636Z | Windows PowerShell 5.1 / Pester 5.7.1 |
| Crosshairs and browser-index regressions after mock fallback correction (PowerShell 7 default) | `Invoke-Pester -Path ./Tests/TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*Crosshair profile-planning progress*','*rejects invalid browser selection tokens and indexes*') -Output Detailed -PassThru` | 2 passed, 0 failed, 1274 not run | 2026-10-02T12:00:00.3772213Z | 2026-10-02T12:00:07.8290714Z | PowerShell 7 / Pester 6.1.0 |
| PowerShell 7 source quality gate before mock fallback correction | `pwsh -NoLogo -NoProfile -File ./scripts/Run-TpmQualityGate.ps1 -ReportPath ./docs/remediation/PR-321-reconciliation.md` | Main Pester 1275 passed, 1 failed; SupportPackage 42 passed, 0 failed; ASCII/parse, configured product PSScriptAnalyzer, and `git diff --check` passed; permanent procedure gate correctly blocked unresolved ID 3. The focused reproduction identified the missing default Sort-Object mock; wrapper exit 1. | not captured | not captured | PowerShell 7 / source quality wrapper |
| Permanent procedure gate PSScriptAnalyzer | `Invoke-ScriptAnalyzer -Path ./scripts/Test-TpmPermanentProcedures.ps1 -Severity Error,Warning -Settings ./PSScriptAnalyzerSettings.psd1` | 0 findings | not captured | 2026-10-02T11:56:04.0092203Z | PowerShell 7 / PSScriptAnalyzer |
| Historical full main Pester suite before report-output normalization | `powershell.exe -NoLogo -NoProfile -Command "Import-Module Pester -RequiredVersion 5.7.1; Invoke-Pester -Path './Tests/TeknoParrot-Manager.Tests.ps1' -CI -Output Minimal -PassThru"` | 1276 passed, 0 failed, 0 skipped, 0 not run on earlier test bytes; superseded by the final frozen rerun below | 2026-10-02T12:02:15.9362857Z | 2026-10-02T12:07:55.7168071Z | Windows PowerShell 5.1 / Pester 5.7.1 |
| Promoted-status focused regressions before output-normalization correction (Windows PowerShell 5.1) | `Invoke-Pester -Path ./Tests/TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*requires the TPM remediation and prompt-slice artifacts*','*classifies every registry owner status and blocks unresolved dispositions*','*uses canonical owner statuses and scopes stale-package rejection to certification mode*') -Output Detailed -PassThru` | 2 passed, 1 failed, 1273 not run. Long owner-runtime diagnostics wrapped the missing-candidate message; assertions were normalized to whitespace before matching. | 2026-10-02T12:15:12.6595886Z | not captured | Windows PowerShell 5.1 / Pester 5.7.1 |
| Corrected focused Crosshairs/status regressions (Windows PowerShell 5.1) | `Invoke-Pester -Path ./Tests/TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*Crosshair profile-planning progress*','*rejects invalid browser selection tokens and indexes*','*requires the TPM remediation and prompt-slice artifacts*','*classifies every registry owner status and blocks unresolved dispositions*','*uses canonical owner statuses and scopes stale-package rejection to certification mode*') -Output Minimal -PassThru` | 5 passed, 0 failed, 1271 not run | 2026-10-02T12:18:06.9677187Z | 2026-10-02T12:18:34.7502594Z | Windows PowerShell 5.1 / Pester 5.7.1 |
| Corrected focused Crosshairs/status regressions (PowerShell 7) | `Import-Module Pester -RequiredVersion 5.7.1; Invoke-Pester -Path ./Tests/TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*Crosshair profile-planning progress*','*rejects invalid browser selection tokens and indexes*','*requires the TPM remediation and prompt-slice artifacts*','*classifies every registry owner status and blocks unresolved dispositions*','*uses canonical owner statuses and scopes stale-package rejection to certification mode*') -Output Minimal -PassThru` | 5 passed, 0 failed, 1271 not run | 2026-10-02T12:18:51.4005034Z | 2026-10-02T12:19:17.5527923Z | PowerShell 7 / Pester 5.7.1 |
| Corrected owner-status assertion (PowerShell 7 default) | `Invoke-Pester -Path ./Tests/TeknoParrot-Manager.Tests.ps1 -FullNameFilter '*uses canonical owner statuses and scopes stale-package rejection to certification mode*' -Output Detailed -PassThru` | 1 passed, 0 failed, 1275 not run | 2026-10-02T12:21:12.9368751Z | 2026-10-02T12:21:37.9226666Z | PowerShell 7 / Pester 6.1.0 |
| Final frozen full main Pester suite after owner-output normalization | `powershell.exe -NoLogo -NoProfile -Command "Import-Module Pester -RequiredVersion 5.7.1; Invoke-Pester -Path './Tests/TeknoParrot-Manager.Tests.ps1' -CI -Output Minimal -PassThru"` | 1276 passed, 0 failed, 0 skipped, 0 not run | 2026-10-02T12:19:34.2745145Z | 2026-10-02T12:25:18.7095600Z | Windows PowerShell 5.1 / Pester 5.7.1 |
| PowerShell 7 aggregate gate after status promotion, before output-normalization correction | `pwsh -NoLogo -NoProfile -File ./scripts/Run-TpmQualityGate.ps1 -ReportPath ./docs/remediation/PR-321-reconciliation.md` | Main Pester 1275 passed, 1 failed; SupportPackage 42 passed, 0 failed; ASCII/parse, configured product PSScriptAnalyzer, and diff check passed; permanent procedure gate failed because report test evidence predated the newer status/slice files. The missing-candidate assertion's wrapped-output defect was corrected afterward; wrapper exit 1. | not captured | not captured | PowerShell 7 / source quality wrapper |
| Promoted owner-status regressions after residual report/board holds were synchronized (Windows PowerShell 5.1) | `Invoke-Pester -Path ./Tests/TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*requires the TPM remediation and prompt-slice artifacts*','*classifies every registry owner status and blocks unresolved dispositions*','*uses canonical owner statuses and scopes stale-package rejection to certification mode*') -Output Minimal -PassThru` | 3 passed, 0 failed, 1273 not run | 2026-10-02T12:34:03.3202264Z | 2026-10-02T12:34:26.0058162Z | Windows PowerShell 5.1 / Pester 5.7.1 |
| Owner-status regressions after reconciling canonical ID 3 status row (Windows PowerShell 5.1) | `Invoke-Pester -Path ./Tests/TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*requires the TPM remediation and prompt-slice artifacts*','*classifies every registry owner status and blocks unresolved dispositions*','*uses canonical owner statuses and scopes stale-package rejection to certification mode*') -CI -Output Detailed -PassThru` | 3 passed, 0 failed, 1273 not run | 2026-10-02T12:44:16.7661011Z | 2026-10-02T12:44:39.6558306Z | Windows PowerShell 5.1 / Pester 5.7.1 |
| Final PowerShell 7 source-quality aggregate after canonical ID 3 row correction | `powershell.exe -NoLogo -NoProfile -Command "& { $started=[DateTime]::UtcNow; 'STARTED UTC: '+$started.ToString('o'); & pwsh -NoLogo -NoProfile -File './scripts/Run-TpmQualityGate.ps1' -ReportPath './docs/remediation/PR-321-reconciliation.md'; $code=$LASTEXITCODE; $finished=[DateTime]::UtcNow; 'FINISHED UTC: '+$finished.ToString('o'); 'GATE EXIT CODE: '+$code; exit $code }"` | Main Pester 1276 passed, 0 failed; SupportPackage 42 passed, 0 failed; ASCII/parse, configured PSScriptAnalyzer, `git diff --check`, and permanent procedure gate passed; exit code 0 | 2026-10-02T12:45:32.2927796Z | 2026-10-02T12:54:54.9646896Z | PowerShell 7 / default Pester 6.1.0 |
| Final owner-status regressions after status/document synchronization (Windows PowerShell 5.1) | `Invoke-Pester -Path ./Tests/TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*requires the TPM remediation and prompt-slice artifacts*','*classifies every registry owner status and blocks unresolved dispositions*','*uses canonical owner statuses and scopes stale-package rejection to certification mode*') -CI -Output Detailed -PassThru` | 3 passed, 0 failed, 1273 not run | 2026-10-02T13:00:01.4719456Z | 2026-10-02T13:00:23.7286347Z | Windows PowerShell 5.1 / Pester 5.7.1 |
| Owner-status regressions after source-ref handoff wording updates (Windows PowerShell 5.1) | `Invoke-Pester -Path ./Tests/TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*requires the TPM remediation and prompt-slice artifacts*','*classifies every registry owner status and blocks unresolved dispositions*','*uses canonical owner statuses and scopes stale-package rejection to certification mode*') -CI -Output Detailed -PassThru` | 3 passed, 0 failed, 1273 not run | 2026-10-02T13:15:13.2108829Z | 2026-10-02T13:15:40.8664393Z | Windows PowerShell 5.1 / Pester 5.7.1 |
| RC8 updater core Pester | `Import-Module Pester -RequiredVersion 5.7.1 -Force; Invoke-Pester -Path .\Tests\TpmAutoUpdate.Core.Tests.ps1 -PassThru` | 51 passed, 0 failed, 0 skipped; includes valid-UTF-8 non-ASCII candidate rejection, local AST identity, release-tag equality, and Apply spoof rejection | 2026-10-03T06:40:59Z | 2026-10-03T06:41:02Z | PowerShell 7.6.6 / Pester 5.7.1 |
| RC8 updater core Pester | `Import-Module Pester -RequiredVersion 5.7.1 -Force; Invoke-Pester -Path .\Tests\TpmAutoUpdate.Core.Tests.ps1 -PassThru` | 51 passed, 0 failed, 0 skipped | 2026-10-03T06:40:59Z | 2026-10-03T06:41:02Z | Windows PowerShell 5.1 / Pester 5.7.1 |
| Full main Pester suite | `Import-Module Pester -RequiredVersion 5.7.1 -Force; Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -PassThru` | 1290 passed, 0 failed, 0 skipped; includes successful single-quoted RC8 Apply and valid-UTF-8 non-ASCII candidate rejection | 2026-10-03T06:43:18Z | 2026-10-03T06:52:16Z | PowerShell 7.6.6 / Pester 5.7.1 |
| Full main Pester suite | `Import-Module Pester -RequiredVersion 5.7.1 -Force; Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -PassThru` | 1290 passed, 0 failed, 0 skipped | 2026-10-03T06:43:17Z | 2026-10-03T06:49:11Z | Windows PowerShell 5.1 / Pester 5.7.1 |
| Destructive updater-path Pester | `Import-Module Pester -RequiredVersion 5.7.1 -Force; Invoke-Pester -Path .\Tests\TpmAutoUpdate.DestructivePath.Tests.ps1 -PassThru` | 10 passed, 0 failed, 0 skipped; candidate validation precedes replacement and preserves original on failure | 2026-10-03T06:43:17Z | 2026-10-03T06:43:19Z | PowerShell 7.6.6 / Pester 5.7.1 |
| SupportPackage Pester | `Import-Module Pester -RequiredVersion 5.7.1 -Force; Invoke-Pester -Path .\Tests\SupportPackage.Tests.ps1 -PassThru` | 42 passed, 0 failed, 0 skipped | 2026-10-03T06:49:05Z | 2026-10-03T06:49:26Z | PowerShell 7.6.6 / Pester 5.7.1 |
| QualitySystem Pester | `Import-Module Pester -RequiredVersion 5.7.1 -Force; Invoke-Pester -Path .\Tests\QualitySystem.Tests.ps1 -PassThru` | 24 passed, 0 failed, 0 skipped | 2026-10-03T06:49:06Z | 2026-10-03T06:49:08Z | PowerShell 7.6.6 / Pester 5.7.1 |
| Main updater identity/extraction/install focused regressions | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter @("*Manager script version identity*","*Test-ManagerUpdateExtractedScript*","*Invoke-ManagerUpdateInstall*") -PassThru` | PowerShell 7 run: 27 passed, 0 failed. Windows PowerShell 5.1 simultaneous run: 26 passed, 1 failed because the extraction-failure test observed one file in its process-global temp-directory glob (`Expected 0, but got 1`); the same PS 5.1 test then passed in isolation (1/1), and a post-run inspection found no matching temp files. Cross-process temp-file interference is the explanation consistent with the overlapping runs, but remains an inference. | 2026-10-03T07:01:48.2892948Z (PS7); 2026-10-03T07:01:47.5389815Z (PS5.1) | 2026-10-03T07:02:01.2213102Z (PS7); 2026-10-03T07:02:00.7734186Z (PS5.1) | Pester 5.7.1; PS7 7.6.6 and Windows PowerShell 5.1 |
| Isolated updater extraction-failure regression after parallel temp-glob observation | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter "*extraction failure (valid ZIP, corrupted entry payload)*" -PassThru` | 1 passed, 0 failed, 1289 not run; no matching updater temp files remained after the concurrent runs | 2026-10-03T07:03:25.3321083Z | 2026-10-03T07:03:31.6730242Z | Windows PowerShell 5.1 / Pester 5.7.1 |
| RC8 main updater focused regressions after source/doc sync | `Import-Module Pester -RequiredVersion 5.7.1 -Force; Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter @("*Manager script version identity*","*Test-ManagerUpdateExtractedScript*","*Invoke-ManagerUpdateInstall*") -PassThru` | 27 passed, 0 failed, 1263 not run | 2026-10-03T07:01:48.2892948Z | 2026-10-03T07:02:01.2213102Z | PowerShell 7.6.6 / Pester 5.7.1 |
| RC8 standalone updater core Pester after source/doc sync | `Import-Module Pester -RequiredVersion 5.7.1 -Force; Invoke-Pester -Path .\Tests\TpmAutoUpdate.Core.Tests.ps1 -PassThru` | 51 passed, 0 failed, 0 skipped | 2026-10-03T07:01:48.9587670Z | 2026-10-03T07:01:54.4987628Z | PowerShell 7.6.6 / Pester 5.7.1 |
| RC8 standalone updater core Pester after source/doc sync | `Import-Module Pester -RequiredVersion 5.7.1 -Force; Invoke-Pester -Path .\Tests\TpmAutoUpdate.Core.Tests.ps1 -PassThru` | 51 passed, 0 failed, 0 skipped | 2026-10-03T07:01:48.8856769Z | 2026-10-03T07:01:54.5033360Z | Windows PowerShell 5.1 / Pester 5.7.1 |
| Final frozen full main Pester suite after updater source changes | `powershell.exe -NoLogo -NoProfile -Command "Import-Module Pester -RequiredVersion 5.7.1 -Force; Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -CI -Output Minimal -PassThru"` | 1290 passed, 0 failed, 0 skipped, 0 not run | 2026-10-03T07:08:31.9249935Z | 2026-10-03T07:14:35.7219195Z | Windows PowerShell 5.1 / Pester 5.7.1 |
| Canonical production InjectionHunter inventory | `Import-Module .\scripts\TPMCertification.ProductionFacts.psm1 -Force; invoke private Test-TPMProductionInjectionHunterV1 in that module scope with Get-TPMProductionPowerShellInventoryV1 and .\scripts\InjectionHunterDispositions.psd1` | Executed=True; 40 findings, all 40 individually reviewed `FalsePositive` dispositions; 0 unresolved; tool 1.0.0. All 40 source/rule/extent entries match; no stale disposition failure. | 2026-10-03T07:13:10.8658645Z | 2026-10-03T07:14:39.3309246Z | PowerShell 7 / InjectionHunter 1.0.0 |
| Current owner-status and remediation-artifact contract tests after P1 board sync | `Import-Module Pester -RequiredVersion 5.7.1 -Force; Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter @("*requires the TPM remediation and prompt-slice artifacts*","*classifies every registry owner status and blocks unresolved dispositions*","*uses canonical owner statuses and scopes stale-package rejection to certification mode*") -PassThru` | 3 passed, 0 failed, 1287 not run | 2026-10-03T07:20:05.1699281Z | 2026-10-03T07:20:30.8266990Z | PowerShell 7.6.6 / Pester 5.7.1 |
| Governance/QualitySystem tests after SECURITY.md and P1 evidence synchronization | `Import-Module Pester -RequiredVersion 5.7.1 -Force; Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter @("*requires the TPM remediation and prompt-slice artifacts*","*classifies every registry owner status and blocks unresolved dispositions*","*uses canonical owner statuses and scopes stale-package rejection to certification mode*") -PassThru; Invoke-Pester -Path .\Tests\QualitySystem.Tests.ps1 -PassThru` | Owner/status/artifact tests 3 passed, 0 failed; QualitySystem 24 passed, 0 failed | 2026-10-03T07:34:44.2531124Z | 2026-10-03T07:35:08.4620996Z | PowerShell 7.6.6 / Pester 5.7.1 |
| Final source quality wrapper after SECURITY.md synchronization | `pwsh.exe -NoProfile -File ./scripts/Run-TpmQualityGate.ps1 -ReportPath ./docs/remediation/PR-321-reconciliation.md` | PASS (exit 0); Main Pester 1290/1290; SupportPackage 42/42; ASCII/parse, configured PSScriptAnalyzer, `git diff --check`, and permanent procedure gate passed | 2026-10-03T07:35:44.2922377Z | 2026-10-03T07:45:16.7882201Z | PowerShell 7 |
| Final board/report contract verification | `Import-Module Pester -RequiredVersion 5.7.1 -Force; $tests=Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter @("*requires the TPM remediation and prompt-slice artifacts*","*classifies every registry owner status and blocks unresolved dispositions*","*uses canonical owner statuses and scopes stale-package rejection to certification mode*") -PassThru; if($tests.FailedCount -ne 0 -or $tests.PassedCount -ne 3){throw "Final board-contract Pester count mismatch."}; & .\scripts\Test-TpmPermanentProcedures.ps1 -RepoRoot (Get-Location).Path -ReportPath (Join-Path (Get-Location).Path "docs\remediation\PR-321-reconciliation.md") -SourcePath (Join-Path (Get-Location).Path "TeknoParrot-Manager.ps1"); if($LASTEXITCODE -ne 0){throw "Permanent procedure gate failed with exit code $LASTEXITCODE."}` | Owner/status/artifact tests 3 passed, 0 failed, 1287 not run; permanent procedure gate passed | 2026-10-03T07:47:09.3878984Z | 2026-10-03T07:47:32.3320146Z | PowerShell 7.6.6 / Pester 5.7.1 |
| Final post-board-sync source quality wrapper | `powershell.exe -NoLogo -NoProfile -Command '$started=[DateTime]::UtcNow; Write-Output ("STARTED UTC: "+$started.ToString("o")); & pwsh.exe -NoLogo -NoProfile -File .\scripts\Run-TpmQualityGate.ps1 -ReportPath .\docs\remediation\PR-321-reconciliation.md; $code=$LASTEXITCODE; $finished=[DateTime]::UtcNow; Write-Output ("FINISHED UTC: "+$finished.ToString("o")); Write-Output ("GATE EXIT CODE: "+$code); exit $code'` | PASS (exit 0); Main Pester 1290/1290; SupportPackage 42/42; ASCII/parse, configured PSScriptAnalyzer, `git diff --check`, and permanent procedure gate with wrapper-computed `ChangedAtUtc` passed | 2026-10-03T07:50:11.2656367Z | 2026-10-03T07:59:42.0035591Z | PowerShell 7 |
| Full relevant Pester suites after UVO-08 review (Windows PowerShell 5.1) | Sequential `Invoke-Pester -Path` loop over main, SupportPackage, updater core, and destructive-path suites with Pester 5.7.1 and `-Output Minimal -PassThru` | Main 1296 passed, SupportPackage 42 passed, updater core 58 passed, destructive-path 10 passed; 0 failures/skips/not-run | Not captured | Not captured | Windows PowerShell 5.1 / Pester 5.7.1 |
| Full relevant Pester suites after UVO-08 review (PowerShell 7.6.6) | Sequential `Invoke-Pester -Path` loop over main, SupportPackage, updater core, and destructive-path suites with Pester 5.7.1 and `-Output Minimal -PassThru` | Main 1296 passed, SupportPackage 42 passed, updater core 58 passed, destructive-path 10 passed; 0 failures/skips/not-run | Not captured | Not captured | PowerShell 7.6.6 / Pester 5.7.1 |
| Static source verification after UVO-08 review | `Parser.ParseFile` under both engines for main source, core module, and two changed test files; ASCII byte check; configured `Invoke-ScriptAnalyzer` Error/Warning for main/updater runner/core; canonical `Test-TPMProductionInjectionHunterV1` production inventory | Both engines: 0 parse errors in each of four files; main script non-ASCII bytes 0; 0 configured analyzer findings in all three scripts; InjectionHunter `Executed=True`, 40 findings, 0 unresolved, version 1.0.0; all disposition matches succeeded | Not captured | Not captured | Windows PowerShell 5.1 and PowerShell 7.6.6; InjectionHunter 1.0.0 |
| Remediation artifact and owner-status focused tests after board/slice synchronization | `pwsh -NoProfile -Command` running `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter` for the required three remediation-artifact and owner-status tests, `-Output Minimal -PassThru` | 3 passed, 0 failed, 0 skipped; 1293 not run | 2026-10-03T12:51:39.9710388Z | 2026-10-03T12:52:03.0217124Z | PowerShell 7.6.6 / Pester 5.7.1 |
| Fresh source quality wrapper after UVO-08 board/slice synchronization | `powershell.exe -NoLogo -NoProfile -Command '$started = [DateTime]::UtcNow; Write-Output ("STARTED UTC: " + $started.ToString("o")); & pwsh.exe -NoLogo -NoProfile -File .\scripts\Run-TpmQualityGate.ps1 -ReportPath .\docs\remediation\PR-321-reconciliation.md; $code = $LASTEXITCODE; $finished = [DateTime]::UtcNow; Write-Output ("FINISHED UTC: " + $finished.ToString("o")); Write-Output ("GATE EXIT CODE: " + $code); exit $code'` | PASS (exit 0); Main Pester 1296/1296; SupportPackage 42/42; ASCII/parse, configured PSScriptAnalyzer, `git diff --check`, and permanent procedure gate passed | 2026-10-03T12:53:48.6373092Z | 2026-10-03T13:03:44.2421320Z | PowerShell 7 |
| Final artifact-contract tests after final board status synchronization | `pwsh.exe -NoLogo -NoProfile -Command` running the three remediation-artifact and owner-status Pester tests with `-Output Minimal -PassThru` | 3 passed, 0 failed, 0 skipped; 1293 not run | 2026-10-03T13:16:23.3840478Z | 2026-10-03T13:16:47.9141373Z | PowerShell 7.6.6 / Pester 5.7.1 |
| Final post-status-sync permanent procedure gate | `Test-TpmPermanentProcedures.ps1` with `ChangedAtUtc` computed as the newest wrapper freshness-path `LastWriteTimeUtc` | PASS; `ChangedAtUtc` 2026-10-03T13:05:26.4410451Z; final artifact-contract tests completed after that timestamp | 2026-10-03T13:10:00.0438969Z | 2026-10-03T13:10:01.3871542Z | Windows PowerShell 5.1 |
| Permanent procedure gate attempt before report evidence refresh | Direct `pwsh.exe` 7.6.6 invocation of `Test-TpmPermanentProcedures.ps1`, with `ChangedAtUtc` from the wrapper freshness paths | FAIL (exit 1): report's newest validation timestamp preceded `ChangedAtUtc` because the 13:16 post-board test result had not yet been recorded | 2026-10-03T13:17:05.2288243Z | 2026-10-03T13:17:06.7255318Z | PowerShell 7.6.6 |
| Permanent procedure gate after recording final post-board tests | Direct `pwsh.exe` 7.6.6 invocation of `Test-TpmPermanentProcedures.ps1`, with `ChangedAtUtc` from the wrapper freshness paths | PASS (exit 0); `ChangedAtUtc` 2026-10-03T13:16:01.5759170Z; post-board artifact tests recorded at 13:16:47Z | 2026-10-03T13:17:53.9079816Z | 2026-10-03T13:17:55.2598338Z | PowerShell 7.6.6 |



## ReShade ten-effect/twelve-profile source slice

- The authorized catalog contains twelve canonical profiles and ten approved
  effects. Generated presets set both `Techniques` and `TechniqueSorting` to
  the exact canonical profile order; `Original` leaves both empty.
- Runtime format was checked against pinned upstream ReShade v6.8.0 source.
  Both preset paths resolve to `.\ReShade.ini`; effect lookup roots are
  `.\Shaders,.\Shaders\SweetFX,.\Shaders\TPM`.
- Shared include closure is staged once per identity. Conflicting content for
  a shared include fails before target mutation; deployment and ownership
  rollback remain transactional.
- Focused regressions cover `defines twelve canonical profiles and exact
  effect order`, `provides a complete approved include closure and valid
  runtime search and preset paths for every profile`, `rejects conflicting
  shared include identities before target mutation`,
  `deduplicates identical shared includes when deploying the two-effect
  profile on a clean target`, and `renders meaningful distinct outputs for
  every approved profile without changing the baseline`.
- Governing inventories:
  `docs/RESHADE-PROFILE-SELECTION-SPECIFICATION-INVENTORY.md` and
  `docs/RESHADE-PROFILE-SELECTION-INVARIANT-INVENTORY.md`. They explicitly
  record the process deviation: both were created after implementation
  began, contrary to the required pre-implementation timing. Neither has
  independent review; the deviation and review remain open.
- Fixture-backed source tests passed. Candidate package identity and owner
  runtime remain unverified and unauthorized.


## Migration and Eggman DAT remediation -- Slice 6

Migration remains opt-in and confirmation-based. The normal preview now names
the destination root, groups planned manager-owned moves by category, explains
what is excluded, states that Y applies direct moves and N applies none, and
identifies the details report as optional evidence. Eggman DAT updates now
derive the destination filename from the latest release and update the active
configuration only from the canonical path returned by the successful download.

## Cross-cutting user-facing cleanup -- Slice 7

Normal-path prompts and status messages now spell out TeknoParrot Manager.
Registered-game selection uses the profile GameName when available and keeps
profile codes for internal lookup and technical evidence. Compact progress
continues through the bounded single-row renderer; raw technical diagnostics
remain in logs or Details output. Owner-runtime proof is still outstanding.


## FFB completion and prompt remediation -- Slice 5

The FFB membership gate now presents one decision question with explicit
choices. Optional-plugin results distinguish installed files, native-preferred
skips, unsupported/no-match skips, preserved existing files, and actual
failures. Complete accounting with zero deployment is successful when native
FFB Blaster is preferred or no supported plugin target exists; download,
deployment, missing-path, unavailable-device, unavailable-file, incomplete
accounting, and evidence errors remain failures. Normal output uses full game
names where available and beginner-safe wording; profile codes and technical
ownership/source details remain in logs and evidence. The pinned SHA,
same-revision support table/DLL acquisition, atomic evidence, exact-once
accounting, and unowned-file preservation contracts remain unchanged.

## FFB mode-8 hardening round -- 2026-09-08

This committed TPM-only slice hardens the existing third-party FFBPlugin
path. The mutable upstream branch is resolved once to a validated full
commit SHA; the support table and both DLL downloads use that same SHA. DLL
acquisition is staged all-or-nothing, existing custom cache files are
preserved, and SHA256/provenance evidence is written atomically. Deployment,
ownership metadata, native-overlap cleanup, and final evidence persistence
roll back on failure. The setup result reports exact accounting and records
zero-deployment outcomes without mutating game profiles.

| FFB validation | Exact command | Count/result | Started UTC | Finished UTC | Engine/version |
|---|---|---|---|---|---|
| FFB focused Pester | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter '*FFB*' -CI -Output Normal` | 40 passed, 0 failed, 0 skipped | 2026-09-08T20:58:37 | 2026-09-08T20:58:47 | Pester 5.7.1 |
| SupportPackage.Tests | `Invoke-Pester -Path .\Tests\SupportPackage.Tests.ps1 -CI -Output Normal` | 40 passed, 0 failed, 0 skipped | 2026-09-08T20:58:55 | 2026-09-08T20:59:13 | Pester 5.7.1 |
| Main Pester | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -Output Normal` | 1028 passed, 0 failed, 0 skipped | not captured | not captured | Pester 5.7.1 |
| Permanent procedure gate | `Test-TpmPermanentProcedures.ps1 -RepoRoot . -SourcePath .\TeknoParrot-Manager.ps1 -ReportPath .\docs\remediation\PR-321-reconciliation.md` | Failed closed on unresolved source/owner blockers and owner-runtime evidence; no completion claim | not captured | not captured | pwsh |

Pester 5.7.1 was verified with `Get-Module Pester -ListAvailable`. Parse
checks returned zero errors, PSScriptAnalyzer returned zero Error/Warning
findings, the production script contained zero non-ASCII bytes, `git
diff --check` passed, and no generated result file remained. The existing
changelog contains 40 non-ASCII bytes outside this FFB slice. No package,
owner-runtime smoke, release, certification, commit, or push was performed.

## Static gates

### PostgreSQL reset transport source gates -- 2026-10-01

- PS7 reset transport focused Pester: 15 passed, 0 failed, 0 skipped; 1172 not run; 2026-10-01T01:25:45Z--2026-10-01T01:25:58Z.
- Windows PowerShell 5.1 reset transport focused Pester: 15 passed, 0 failed, 0 skipped; 1172 not run; 2026-10-01T01:26:08Z--2026-10-01T01:26:22Z.
- PS7 full main Pester suite: 1187 passed, 0 failed, 0 skipped, 0 not run; 2026-10-01T01:27:12Z--2026-10-01T01:40:29Z (full quality-gate interval).
- SupportPackage suite: 41 passed, 0 failed, 0 skipped, 0 not run in the same quality-gate run.
- Follow-up source quality gate: all source/static checks passed; 1187 main tests and 41 SupportPackage tests passed; Windows PowerShell 5.1 reset-focused suite passed 16/16. Its permanent-procedure phase initially rejected stale report timestamps; following evidence refresh, the permanent gate passed at 2026-10-01T02:15:43Z with freshness boundary 2026-10-01T01:50:17.7041915Z.
- Final `Run-TpmQualityGate.ps1` rerun after refreshing the report evidence passed; output observed by 2026-10-01T02:30:24Z.
- Production and test PowerShell parse: 0 errors.
- Production ASCII: 0 non-ASCII bytes.
- PSScriptAnalyzer: 0 Error/Warning findings (also confirmed directly).
- `git diff --check`: passed.
- Permanent procedure gate: passed.
- Earlier TPM quality gate (before follow-up corrections): passed; exact run interval 2026-10-01T01:27:12Z--2026-10-01T01:40:29Z.
- Runtime: owner-reported ARCADE mechanism proof predates this source revision. Exact pushed-SHA package proof remains outstanding.

## Hunk classification

| File | Hunk/range | Procedure ID, owner report ID, issue, or authorization | Evidence |
|---|---|---|---|
| AGENTS.md | Permanent gate checklist addition | TPM-AUTH-001, authorized governance requirement | Changed-section review |
| RELEASE-SAFETY-CHECKLIST.md | Permanent gate checklist addition | TPM-AUTH-001, TPM-TRACE-002 | Changed-section review |
| docs/ENGINEERING-WORKFLOW.md | Remediation gate workflow | TPM-OWNER-001, TPM-TRACE-001 | Changed-section review |
| quality/permanent-procedures.json | Machine-readable procedure and owner-status/disposition registry | TPM-OWNER-003; all procedure IDs | JSON parse and status/disposition reconciliation |
| docs/governance/permanent-procedures.md; docs/governance/tpm-development-operating-model.md | Source/certification gate workflow and registered status policy | TPM-OWNER-003, TPM-AUTH-001 | Changed-section review |
| docs/templates/remediation-gate-report.md | Seven-status report schema and source/certification semantics | TPM-OWNER-003, TPM-TRACE-001 | Required-section/status review |
| scripts/Test-TpmPermanentProcedures.ps1 | Registry-derived status classification, corrected canonical table parsing, status-bearing rows, exact control-board ID equality, unresolved blocking, and certification-only stale-package check | TPM-OWNER-003, TPM-TRACE-001; owner IDs 3, 33-35; PR #321; TPM-OWNER-STATUS-GATE-001 | Direct source gate blocks only canonical unresolved statuses; focused behavior tests pass 3/3 in both engines |
| scripts/Run-TpmQualityGate.ps1 | Combined quality wrapper and freshness inputs for registry, report schema, control board, operating model, active slice contracts, and ReShade inventories | TPM-AUTH-001, TPM-EVIDENCE-001, TPM-OWNER-STATUS-GATE-001, TPM-RESHADE-TEN-EFFECTS-001 | Main and SupportPackage Pester pass; `git diff --check` passes; permanent procedure gate blocks only on unresolved ID 3 |
| quality/permanent-procedures.json; scripts/Test-TpmPermanentProcedures.ps1; scripts/Run-TpmQualityGate.ps1; Tests/TeknoParrot-Manager.Tests.ps1; docs/governance/tpm-development-operating-model.md; docs/governance/permanent-procedures.md; docs/templates/remediation-gate-report.md; docs/remediation/PR-321-current-slice.md; docs/remediation/PR-321-control-board.md; docs/remediation/PR-321-reconciliation.md; docs/remediation/slices/TPM-PROGRESS-SCAN-COVERAGE-001.md; docs/remediation/slices/TPM-OWNER-STATUS-GATE-001.md | Registry-derived owner-status dispositions, canonical status-bearing row parsing, exact owner-ID set, source-mode unresolved blocking, certification-only stale-package rejection, and freshness boundaries | owner ID 3; TPM-OWNER-003; TPM-TRACE-001; TPM-AUTH-001; PR #321; contract TPM-OWNER-STATUS-GATE-001 | Baseline invalid-status/stale-source failure; registry/status matrix; historical/canonical, missing/extra-ID, blank-status, and source/certification tests pass 3/3 in both engines |
| .github/pull_request_template.md | PR checklist | TPM-AUTH-001, TPM-TRACE-001 | File review |
| TeknoParrot-Manager.ps1 | Prompt.Core helper and finite-choice routes | TPM-PROMPT-001, owner report IDs 24-27/32, PR #321 | Production parse, focused prompt tests; owner runtime outstanding |
| Tests/TeknoParrot-Manager.Tests.ps1 | Progress.Core source inventory and bounded-wait contracts | TPM-PROGRESS-001, owner report ID 3, progress portion of ID 32, PR #321 | Focused progress tests; final full suite 1215/1215 passed in PowerShell 7 and Windows PowerShell 5.1 |
| Tests/TeknoParrot-Manager.Tests.ps1 | `Read-TpmChoice` behavior, Prompt.Core route contracts, and specialized-boundary inventory | TPM-PROMPT-001, owner report IDs 26/32, PR #321 | Focused prompt tests; final full suite 1215/1215 passed in both engines; owner runtime outstanding |
| ARCHITECTURE.md | Prompt.Core finite-choice invariant and boundaries | TPM-PROMPT-001, TPM-TRACE-001, PR #321 | Changed-section review |
| ARCHITECTURE.md | Progress.Core compact/workflow/waiting contract | TPM-PROGRESS-001, TPM-TRACE-001, PR #321 | Changed-section review |
| TeknoParrot-Manager.ps1; Tests/TeknoParrot-Manager.Tests.ps1; ARCHITECTURE.md; docs/remediation/PR-321-control-board.md; docs/remediation/slices/TPM-PROGRESS-SCAN-COVERAGE-001.md | Known-total AutoSync ZIP classification and GPU/GameProfiles catalog scan progress; three real call-site behavior tests | TPM-PROGRESS-001/002, TPM-TRACE-001, owner IDs 3-5, PR #321 | Focused tests: 3 passed in PS7 and 3 passed in Windows PowerShell 5.1; ID 3's pattern-wide audit and owner runtime remain open |
| TeknoParrot-Manager.ps1; Tests/TeknoParrot-Manager.Tests.ps1; ARCHITECTURE.md; docs/remediation/PR-321-control-board.md; docs/remediation/slices/TPM-PROGRESS-SCAN-COVERAGE-001.md; docs/remediation/PR-321-reconciliation.md | Known-total Crosshair profile-planning and optional HyperSpin system-file, named-file, existing-game, and UserProfiles scans; ReShade/FFB bounded-request dispositions | TPM-PROGRESS-001/002, TPM-TRACE-001; owner ID 3; slice contract TPM-PROGRESS-SCAN-COVERAGE-001; PR #321 | Three expected progress-test failures reproduced before source changes; focused behavior tests passed; final full suite 1215/1215 in PowerShell 7 and Windows PowerShell 5.1 |
| docs/remediation/slices/PR-321-current-slice.md; docs/remediation/PR-321-control-board.md | ReShade ownership/accounting contract, prompt inventory, boundaries, statuses, and slice assignment | TPM-RESHADE-001, TPM-TRACE-001, TPM-OWNER-001, owner report IDs 11-12, PR #321 | Artifact review and focused source tests |
| README.md; QUICKSTART.md; TeknoParrot-Manager-README.txt; TeknoParrot-Manager-QuickStart.txt | Corrected LaunchBox/HyperSpin prompt instructions | TPM-PROMPT-001, owner report IDs 24-25, PR #321 | Documentation review against current routes |
| TeknoParrot-Manager.ps1 | FFB source resolution, support-table parsing, staged DLL acquisition, transactional deployment, ownership rollback, and evidence persistence | TPM-FFB-001, TPM-TRACE-001, PR #321 | Production parse, analyzer, focused FFB tests |
| Tests/TeknoParrot-Manager.Tests.ps1 | FFB source, URL, cache, hash, collision, ownership, evidence, rollback, accounting, and support contracts | TPM-FFB-001, TPM-TRACE-001, PR #321 | 40 focused FFB tests; final full main suite 1215/1215 passed in PowerShell 7 and Windows PowerShell 5.1 |
| TeknoParrot-Manager.ps1 | `Invoke-TpmDownload` definitive-404 preservation across transport fallback | owner report IDs 2, 6, 8, PR #321 Slice A | Production parse, PSScriptAnalyzer, focused download/thumbnail tests |
| Tests/TeknoParrot-Manager.Tests.ps1 | Regression for 404 followed by unknown fallback failure | owner report IDs 6, 8, PR #321 Slice A | Slice A focused suite: 54 passed |
| ARCHITECTURE.md; TeknoParrot-Manager-CHANGELOG.txt; docs/remediation/PR-321-control-board.md; docs/remediation/PR-321-reconciliation.md | Slice A contract and evidence update | owner report IDs 2, 6, 8, PR #321 Slice A | Changed-section review |
| TeknoParrot-Manager.ps1 | ReShade all-games accounting with `KeptPrevious` terminal outcome | owner report ID 12, PR #321 Slice C | Production parse, focused ReShade tests, full main suite |
| Tests/TeknoParrot-Manager.Tests.ps1 | ReShade protected adoption, result priority, backup/rollback, and exact accounting contracts | owner report IDs 11-12, PR #321 Slice C | ReShade focused suite: 192 passed |
| ARCHITECTURE.md; TeknoParrot-Manager-CHANGELOG.txt; docs/remediation/PR-321-control-board.md; docs/remediation/PR-321-reconciliation.md | Slice C ownership/accounting contract and evidence update | owner report IDs 11-12, PR #321 Slice C | Changed-section review |
| TeknoParrot-Manager.ps1 | Pinned ten-effect catalog, twelve canonical profiles, ordered `Techniques`/`TechniqueSorting`, canonical preset paths, and transactional shared-include deployment | PR #321 / owner IDs 1, 9, 10 / TPM-RESHADE-TEN-EFFECTS-001 / TPM-RESHADE-001 / TPM-EVIDENCE-001 / TPM-OWNER-002 / TPM-OWNER-003 / TPM-TRACE-001 / TPM-AUTH-001 | Pinned runtime-format inventory; ReShade regressions and full-suite evidence above |
| Tests/TeknoParrot-Manager.Tests.ps1 | Canonical preset order, include closure/collision, Original empty lists, config paths, and deterministic twelve-profile preview | PR #321 / owner IDs 1, 9, 10 / TPM-RESHADE-TEN-EFFECTS-001 / TPM-EVIDENCE-001 / TPM-TRACE-001 | ReShade filter 207/207; full main Pester 1224/1224 in both engines |
| ARCHITECTURE.md; README.md; TeknoParrot-Manager-README.txt; TeknoParrot-Manager-CHANGELOG.txt; LICENSE; docs/remediation/PR-321-control-board.md; docs/remediation/PR-321-reconciliation.md; docs/remediation/slices/TPM-RESHADE-TEN-EFFECTS-001.md; docs/remediation/slices/PR-321-current-slice.md | ReShade profile/effect contract, provenance, Original behavior, and remaining package/runtime gates | PR #321 / owner IDs 1, 9, 10 / TPM-RESHADE-TEN-EFFECTS-001 / TPM-RESHADE-001 / TPM-EVIDENCE-001 / TPM-OWNER-002 / TPM-OWNER-003 / TPM-TRACE-001 / TPM-AUTH-001 | Changed-section review; owner-runtime and independent inventory review remain open |
| docs/RESHADE-PROFILE-SELECTION-SPECIFICATION-INVENTORY.md; docs/RESHADE-PROFILE-SELECTION-INVARIANT-INVENTORY.md; docs/RESHADE-DGVOODOO2-AUTODOWNLOAD-SPECIFICATION-INVENTORY.md; docs/RESHADE-DGVOODOO2-AUTODOWNLOAD-INVARIANT-INVENTORY.md | Profile runtime-format and system-invariant inventories; adjacent installer-scope distinction | PR #321 / owner IDs 1, 9, 10 / TPM-RESHADE-TEN-EFFECTS-001 / TPM-EVIDENCE-001 / TPM-TRACE-001 / TPM-AUTH-001 | Inventory timing deviation disclosed; no independent review claimed |
| scripts/Run-TpmQualityGate.ps1; Tests/TeknoParrot-Manager.Tests.ps1 | Include ReShade inventories in gate freshness inputs and assert required artifact presence/membership | PR #321 / TPM-RESHADE-TEN-EFFECTS-001 / TPM-EVIDENCE-001 / TPM-TRACE-001 / TPM-AUTH-001 | `requires the TPM remediation and prompt-slice artifacts`; full wrapper evidence recorded below |
| Tests/SupportPackage.Tests.ps1 | FFB evidence allowlist and support-package collection | TPM-FFB-001, TPM-EVIDENCE-001, PR #321 | 40 support-package tests |
| scripts/InjectionHunterDispositions.psd1 | Added dispositions for two pre-existing fixed-input false positives surfaced by the Slice 8B gate run | InjectionHunter evidence gate | 42 findings, 0 unresolved |
| TeknoParrot-Manager.ps1; Tests/TeknoParrot-Manager.Tests.ps1; ARCHITECTURE.md; TeknoParrot-Manager-CHANGELOG.txt; docs/remediation/PR-321-control-board.md; docs/remediation/PR-321-reconciliation.md | PostgreSQL Slice 8B display, diagnosis, reset-stage, status, and routing contract | owner ID 16, PR #321 Slice 8B | 54 focused tests; 1052 full main tests; owner runtime outstanding |
| TeknoParrot-Manager.ps1; Tests/TeknoParrot-Manager.Tests.ps1; ARCHITECTURE.md; docs/RC8-REMEDIATION-INVENTORY.md; docs/remediation/PR-321-control-board.md; docs/remediation/slices/PR-321-current-slice.md; docs/remediation/slices/TPM-POSTGRES-RETRY-AUTH-001.md; docs/remediation/PR-321-reconciliation.md | PostgreSQL protected retry-authentication boundary: preserve committed-password state, suppress unverified retry-envelope issuance, update exact regression coverage and governance evidence | owner report 16 / PR #321 / TPM-TRACE-001 / TPM-OWNER-001 / TPM-POSTGRES-RETRY-AUTH-001 | Focused PostgreSQL recovery/password/resume PS7 57 passed / 0 failed; Windows PowerShell 5.1 57 passed / 0 failed; full main Pester 1176 passed / 0 failed; SupportPackage 41 passed / 0 failed; owner runtime remains outstanding |
| scripts/Test-TpmPermanentProcedures.ps1; scripts/Run-TpmQualityGate.ps1; docs/governance/permanent-procedures.md; Tests/TeknoParrot-Manager.Tests.ps1; docs/remediation/slices/PR-321-current-slice.md; docs/remediation/slices/TPM-POSTGRES-RETRY-AUTH-001.md; docs/remediation/PR-321-reconciliation.md | Split permanent-procedure enforcement into source/test eligibility and runtime-complete certification so an exact committed SHA and fresh package can exist before owner-runtime proof, while certification still fails closed on pending owner runtime | PR #321 / TPM-TRACE-001 / TPM-OWNER-001 / TPM-AUTH-001 / TPM-POSTGRES-RETRY-AUTH-001 | Source gate must allow `SOURCE FIXED; OWNER RUNTIME NEEDED`; `-CertificationMode` must reject it until ARCADE proof updates statuses |
| TeknoParrot-Manager.ps1; Tests/TeknoParrot-Manager.Tests.ps1; ARCHITECTURE.md; docs/RC8-REMEDIATION-INVENTORY.md; TeknoParrot-Manager-CHANGELOG.txt; TeknoParrot-Manager-README.txt; README.md; docs/remediation/PR-321-control-board.md; docs/remediation/PR-321-reconciliation.md; docs/remediation/slices/TPM-POSTGRES-RESET-TRANSPORT-001.md | PostgreSQL 8.3 reset transport: verified localhost-only temporary authentication rule, psql stdin ALTER ROLE pinned to port 5432, hash-verified original-policy restoration, accurate service-state and committed-mutation reporting, restore of original running/stopped state, and ordinary-mode progress/guidance | owner report 16 / PR #321 / TPM-TRACE-001 / TPM-OWNER-001 / TPM-POSTGRES-RESET-TRANSPORT-001 | Focused PS7 and Windows PowerShell 5.1 transport suites: 15 passed each; final main Pester: 1187 passed; SupportPackage: 41 passed; static and permanent-procedure gates passed; exact pushed-SHA runtime remains outstanding |
| TeknoParrot-Manager.ps1; Tests/TeknoParrot-Manager.Tests.ps1; ARCHITECTURE.md; docs/RC8-REMEDIATION-INVENTORY.md; TeknoParrot-Manager-CHANGELOG.txt; docs/remediation/PR-321-control-board.md; docs/remediation/PR-321-reconciliation.md; docs/remediation/slices/TPM-POSTGRES-UAC-GUIDANCE-001.md | Beginner-safe PostgreSQL UAC guidance before all four install/recovery/reinitialize elevation handoffs; exact semantic and immediate-order tests | owner report 16 / PR #321 / TPM-TRACE-001 / TPM-OWNER-001 / TPM-POSTGRES-UAC-GUIDANCE-001 | Focused PS7 and Windows PowerShell 5.1 PostgreSQL/UX tests; exact counts and gate evidence recorded above; package/runtime proof outstanding |

### PostgreSQL pre-UAC guidance correction -- 2026-10-01

- Owner report 16 / PR #321 / `TPM-POSTGRES-UAC-GUIDANCE-001`.
- Focused behavioral tests: `explains temporary administrator access and the complete UAC recovery handoff`; `uses the same UAC expectations for PostgreSQL installation`; `prints one guidance block immediately before every non-admin PostgreSQL UAC handoff`.
- PS7: 60 passed; 0 failed; 0 skipped. Windows PowerShell 5.1: 60 passed; 0 failed; 0 skipped. Exact run times and command are recorded above.
- Fresh `Test-TpmPermanentProcedures.ps1` passed with ChangedAtUtc `2026-10-01T04:14:11.1751832Z`; complete `Run-TpmQualityGate.ps1` passed with main 1188/1188 and SupportPackage 41/41.
- InjectionHunter found 30 production-script matches; all matched existing individually reviewed `FalsePositive` dispositions, with 0 unmatched/unresolved. Dynamic property reads were verified against closed internal field lists; Add-Type, regex, and argument-quoting inputs were verified as fixed or bounded.
- Default guidance is source/test-covered for all four non-admin callsites. Exact pushed-SHA package/runtime proof remains outstanding; no package was built in this lane.

## Permanent procedure compliance

- Registry exists and contains 27 stable IDs.
- Report uses the required owner statuses only.
- The Progress.Core census covers user-extensible Crosshairs discovery and filename sorting. ID 3 is `SOURCE FIXED; OWNER RUNTIME NEEDED`; the final full source/permanent gate passed. Six other residual expressions are bounded/short-circuit.
- Affected-games repair remains SOURCE FIXED; OWNER RUNTIME NEEDED.
- Support fatal/newest/stale evidence and the support `O/B` route are source/test covered; owner-runtime proof is outstanding.
- Current base for this uncommitted working-tree slice: `193796a08d17f87f823d047646a3e848b85977fc`. HEAD is unchanged; the worktree is dirty, no upstream is configured, and the matching local origin ref is absent.
- The earlier Run-TpmQualityGate result predates the Crosshairs re-audit and remains historical. The final aggregate passed after the canonical status row was corrected; full counts and static/permanent-gate evidence are recorded in the test table.
- This report distinguishes source-gate completion from package identity, documentation/wiki freshness, owner-runtime proof, and release authorization; it does not claim those later gates are complete.

## Non-actions
Source commit and push are limited to exact-SHA candidate-source preparation. No package build, wiki publication, merge, tag, publication, release, certification, or ARCADE action has been performed in this source-gate lane. The Crosshairs discovery/sort gap and stale-history certification false positive are corrected; final source gates passed. The final report content is reconciled to the passing aggregate and owner-status evidence. Package build additionally requires current-cycle #290 repository-document/live-wiki review, exact-SHA READY, and human authorization. The candidate ZIP remains unchanged and stale; Eli's owner smoke and final approval remain outstanding after exact candidate handoff.
No generated runtime artifact remains in the worktree.

## Runtime owner-smoke checklist

Owner-runtime proof remains required for the packaged candidate for ReShade
null/back/cancel, preview synchronization, universal progress, GPU and
thumbnail progress, crosshair close/focus/row placement, PostgreSQL retry,
LaunchBox/HyperSpin gates, affected-games repair scoping, support-package
freshness/fatal evidence, and controls truthfulness.
## Live re-audit correction -- 2026-09-08

The prior owner-report table incorrectly treated every row as `SOURCE FIXED; OWNER RUNTIME NEEDED`. That blanket status is withdrawn. The canonical corrected 32-row table is now in `docs/remediation/PR-321-control-board.md` under the same heading.

Corrections supported by new evidence:

- IDs 13 and 14 (Crosshair browser close/focus) were `SOURCE CLAIM INVALID / RE-AUDIT REQUIRED` at that earlier audit point because the generated HTML had no `window.close()` implementation; the current crosshair slice re-audits the accepted contract, which permits a completed non-interactive state with explicit close guidance instead of requiring `window.close()`.
- ID 2 (duplicate `ErrorAction`) is `SOURCE REMEDIATION REQUIRED`: direct search of `TeknoParrotManager-Support-20260908-023904.zip` found the exact error repeatedly in startup update, Eggman DAT, ProfileSet GitHub, thumbnails, Eggman game-data, and PostgreSQL-resume runs.
- ID 29 (Action Required freshness/scoping) is SOURCE FIXED; OWNER RUNTIME NEEDED. Stale Action Required labeling is tied to the latest TPM log; ambient BepInEx/plugin diagnostics are explicitly labeled as untested/current-workflow-independent evidence and remain metadata-only.
- ID 16 (PostgreSQL recovery) is SOURCE FIXED; OWNER RUNTIME NEEDED. Recovery now classifies password, service, missing-database, corruption, tool, permission, and connection failures, keeps retry/back paths explicit, and preserves no-mutation guarantees before a verified safety decision.
- ID 3 remains source-remediation required. Rows not explicitly marked source remediation require renewed source/package audit before owner-runtime-only classification.

The previous "32 owner-runtime-only" count is unreliable. The candidate package/source gate is not trustworthy for release acceptance. Re-audit and source remediation must precede package rebuild and owner-runtime retest.

That statement describes the prior bounded slice only. The subsequent crosshair slice separately re-audited IDs 13, 14, and 15, corrected the browser to a completed non-interactive state after P2, added best-effort focus reporting, routed workflow prompts with typed fallback, and retained no package, release, certification, push, or ARCADE/#323 action.
## Canonical owner-ID status table -- release decisions
This table is the sole release-decision status source for owner IDs. The
historical mapping above and earlier `NOT FIXED` prose are retained for audit
traceability but do not override these corrected classifications.

| ID | Workflow | Prior status | Corrected status | Evidence | Source remediation | Owner retest | Live record |
|---:|---|---|---|---|---|---|---|
| 1 | Startup/ReShade | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | No contrary source evidence | No | Yes | 5578628627 |
| 2 | Web/Eggman GitHub | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Wrapper now uses RequestErrorAction; prior log defect was confirmed and remediated in source | No | Yes | 5578636706; 5578669949 |
| 3 | Universal progress | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Crosshairs discovery/sort gap has failing-before/passing-after and focused coverage; finite census reconciled; current full Windows PowerShell suite passes; final PS7 aggregate passes 1276/1276 main and 42/42 support plus static/permanent gates | Gap corrected; any later failed source gate restores remediation | Yes, full packaged operation matrix | 5578628627 |
| 4 | AutoSync progress | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Both source ZIP pickers report progress over known totals and close their rows; focused call-site tests pass | No further source change | Yes | 5578628627 |
| 5 | GPU UX | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | GPU catalog scans and per-profile setup phases have compact status; focused call-site tests pass | No further source change | Yes | 5578628627 |
| 6 | Thumbnail progress | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Thumbnail download caller reports compact profile-labelled progress; packaged behavior remains to be confirmed | No further source change | Yes | 5578636706 |
| 7 | Thumbnail accounting | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Current-run definitive 404 profile codes are listed separately from transient download failures; re-audit found no contrary source evidence | No further source change | Yes | 5578628627 |
| 8 | Thumbnail fallback | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Definitive HTTP 404 survives fallback to an unrelated network error; transient transport failures remain retry/failure outcomes | No further source change | Yes | 5578636706 |
| 9 | ReShade preview sync | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Source/test evidence not contradicted | No | Yes | 5578628627 |
| 10 | ReShade selector | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Selector contract remains source-supported | No | Yes | 5578628627 |
| 11 | ReShade protected ownership | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Slice 3 source re-audit and protected/unsafe action remediation passed focused/full source tests | No | Yes | 5578628627 |
| 12 | ReShade accounting/result | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Slice 3 apply-all wording, accounting separation, and terminal invariant passed focused/full source tests | No | Yes | 5578628627 |
| 13 | Crosshair close | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Export-CrosshairPreview now enters a completed non-interactive state after P2 and gives explicit return/close guidance | No | Yes | 5585999038 |
| 14 | Crosshair focus | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Best-effort SetForegroundWindow return is logged when unavailable; terminal workflow remains usable | No | Yes | 5585999038 |
| 15 | Crosshair prompt row | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Workflow-aware P1/P2, confirmation, first-run, and cursor-hide prompts with typed fallback | No | Yes | 5585999038 |
| 16 | PostgreSQL recovery | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Categorized resume reasons and reachable P path; focused tests pass | No | Yes | 5578669949 |
| 17 | Health Check scope | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | One/multiple/zero/no-candidate search and apply paths are limited to affected broken profile codes; no BBHWorld hardcode remains | No further source change | Yes | 5578628627 |
| 18 | Health Check no-candidate | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | No-candidate and zero-affected paths report explicit outcomes and do not offer invalid repair | No further source change | Yes | 5578628627 |
| 19 | Health Check recopy | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Optional AutoSync recopy receives only affected profile codes; the thumbnail prompt follows repair completion | No further source change | Yes | 5578628627 |
| 20 | Health Check Back | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Back stays within Health Check routing and returns through the documented menu path; source re-audit found no contrary behavior | No further source change | Yes | 5578628627 |
| 21 | Repair result clarity | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Reports classify fixed/candidate/still-broken outcomes exactly once; `FIXED` requires verified saved-path read-back | No further source change | Yes | 5578628627 |
| 22 | Post-thumbnail repair | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Post-thumbnail repair handoff remains scoped to affected games and follows explicit repair accounting | No further source change | Yes | 5578628627 |
| 23 | LaunchBox Back | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Optional-chain/back routes preserve Back without escaping to unintended mutation | No further source change | Yes | 5578628627 |
| 24 | LaunchBox prompts | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Finite LaunchBox choices use validated routes and action-specific wording | No further source change | Yes | 5578628627 |
| 25 | HyperSpin missing ID | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Missing-ID `G/S` route is validated and does not invent an emulator identity | No further source change | Yes | 5578628627 |
| 26 | Optional Y/N | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Finite optional decisions use the central reader; exact-token, path, secure, and stateful boundaries remain explicit | No further source change | Yes | 5578628627 |
| 27 | Support prompt | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Support `1-3` and post-ZIP O/B routes validate choices and preserve Back/open-folder outcomes | Yes, source fix | Yes | 5578628627 |
| 28 | Fatal support evidence | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Manifest/focused source coverage exists | No | Yes | 5578628627 |
| 29 | Support freshness/scoping | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Current/stale/ambient classifications and metadata-only plugin inventory are source-covered; overlapping roots now yield one TSV row per safe path | Yes, source fix | Yes | 5578628627 |
| 30 | Controls truthfulness | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Saved settings, inferred readiness, and observed physical binding remain distinct; source re-audit and focused tests support zero verified bindings absent device observation | No further source change | Yes | 5578628627 |
| 31 | dgVoodoo2 wording | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Reachable device-only failure guidance recommends reconnecting and exposes Health Check only for MissingPath; successful-with-skips route was unreachable | Yes, source fix | Yes | 5578628627 |
| 32 | Global consistency | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Enumerated finite-choice routes are centralized or retain documented stateful/exact-token/secure/path/renderer-aware boundaries | Yes, source fix | Yes | 5578628627 |
| 33 | FFB membership/prompt and optional-plugin completion | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Membership, completion, and deployment-error behavior remain source-covered by the FFB focused suite | No further source change in this slice | Yes | PR-321 control board |
| 34 | Migration explanation and Eggman DAT update path | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Migration preview/decline and current DAT filename behavior remain covered; the RC8 startup gate validates typed transaction results and stops on ACTION_REQUIRED / UNKNOWN | Yes, RC8 P1-2 source fix | Yes | PR-321 control board |
| 35 | Cross-cutting user-facing cleanup | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Full-name output and bounded compact progress remain source-covered; owner-visible runtime review is pending | No further source change in this slice | Yes | PR-321 control board |

Product requirements retained for subsequent slices:

- Collect allowlisted TeknoParrot logs and TeknoParrotUI Troubleshooting output, preserving exact shader/display fields and current/ambient/stale classification.
- Preserve affected-game profile evidence snapshots without copying raw unrelated UserProfiles.
- Organize TPM-owned state under `<TeknoParrotRoot>\TeknoParrotManager` with safe migration and conflict preservation.
- Use real deployed ReShade shader/effect names in friendly names or Details.
- Read and preserve TeknoParrot-native CRT/SSAA/display settings; never mutate them in ReShade setup.
- Harden the existing mode-8 FFBPlugin path; do not add a parallel implementation.

First remediation slice completed at source/test level: PostgreSQL recovery reason classification plus duplicate-ErrorAction web-wrapper remediation. No package or runtime proof claimed.

## Library Health repair slice -- working-tree update

This uncommitted TPM-only slice addresses the source-remediation details for
IDs 17-22 while retaining `SOURCE FIXED; OWNER RUNTIME NEEDED` as the target
status after a fresh package/runtime audit. The repair path now emits explicit
`CANDIDATE`, `FIXED`, and `STILL BROKEN` outcomes, verifies saved GamePath
values by reading profiles back, keeps Health Check search and AutoSync
re-copy scoped to affected profiles, redacts before/after path evidence, and
places thumbnail prompts after the repair result. Registration already-set
profiles are summarized, and Raw Thrills path warnings now explain parent
folder shortening and saved-GamePath update steps. Focused Library Health
tests passed for the source working tree. No package, owner smoke, release, or
certification evidence was produced by this slice.

## Desktop OMP Slice 1 -- BepInEx safety and rollback

| Area | Source disposition | Evidence/acceptance |
|---|---|---|
| Canonical containment | Remediated in working tree | Valid child destination uses canonical containment; genuine escapes remain blocked |
| Broad inspection failures | Remediated in working tree | Concrete reason codes and beginner-safe summaries are recorded per game |
| Rollback failure | Remediated in working tree | Failure is terminal; backup/staging evidence remains available |
| Retry guidance | Remediated in working tree | Manual inspection is the default after uncertain state; blind retry is not recommended |
| Prompt/name UX | Remediated in working tree | `[B] Back` is visible; full GameName is used when available; touched normal output says TeknoParrot Manager |
| Owner runtime | BLOCKED | Requires a rebuilt package and a later authorized owner smoke |

`ElevatorAction` remains log-only evidence because its support profile snapshot
was absent. The broad “inspection failed” pattern remains tracked separately
from that single unsafe-root classification.

### Slice 1 system-invariant inventory

| ID | Invariant | Verification |
|---|---|---|
| BEP-01 | A destination equal to or contained by the canonical game root is accepted. | `Test-PathInside`; focused child-path test |
| BEP-02 | A destination outside the canonical root or behind a reparse/junction hazard is rejected before mutation. | Root/reparse focused tests and preflight guard |
| BEP-03 | Every inspection failure has a stable reason key and preserved technical detail. | `Get-BepInExInspectionFailure`; focused classification test |
| BEP-04 | Not-installed/not-applicable/unsupported outcomes are not emitted as generic inspection failures. | Inspection-loop branches and focused classification assertions |
| BEP-05 | Rollback failure is terminal and preserves recovery evidence. | Existing transactional rollback tests plus BepInEx rollback tests |
| BEP-06 | An uncertain rollback state does not default to blind retry. | Failure record `NextAction` and prompt contract |
| BEP-07 | Every accepted finite BepInEx action visibly includes Back. | Production-source prompt contract and focused source test |

## Desktop OMP S1 -- PostgreSQL 8.3 database restore transaction

- Slice contract: `TPM-S1-DB-RESTORE-001`.
- Owner mapping: report ID 16; scope is limited to PostgreSQL 8.3 restore
  transactions and the coupled database/profile setup boundary.
- Source hunks: `TeknoParrot-Manager.ps1` PostgreSQL restore, reset, setup,
  transaction-result, and normal restore presentation functions;
  `Tests/TeknoParrot-Manager.Tests.ps1` deterministic fake command harness,
  filesystem fixtures, and S1 contracts; `ARCHITECTURE.md` design reference.
- Explicit non-actions: no PostgreSQL 12 proof, non-PostgreSQL workflow
  migration, package, push, owner smoke, Arcade, wiki, merge, tag, publish,
  certification, or release authorization.
- Runtime proof: not authorized in this slice; owner smoke remains paused.
- Desktop OMP verification: canonical Pester 5.7.1 main suite passed
  `1121/1121`; focused S1 suites passed `18/18` transaction core,
  `12/12` file promotion, `18/18` directory replacement, `9/9` backup gate,
  and `12/12` PostgreSQL restore. Parser, analyzer, ASCII, and diff checks
  passed. No PostgreSQL 12 proof or owner-runtime proof was performed.

## Desktop OMP S1 -- legacy state transaction normalization

- Slice contract: `TPM-S1-LEGACY-STATE-TRANSACTIONS-001`.
- Authorized owner mapping: IDs 5, 11, 12, 16, 17, 18, 19, 20, 21, 22,
  and 30, plus the explicitly authorized S1 legacy-result normalization
  findings.
- System invariant inventory: LST-01 through LST-11 in the slice contract.
- Source boundary: legacy workflow adapters, verified profile-backup gates,
  PostgreSQL recovery/reinitialize wrappers, PCSX2 cursor-path transaction,
  migration transaction, and the shared v1 validator.
- Tests: deterministic v1 outcome/item-set tests were added alongside the
  existing source and S1 transaction suites. Full main Pester passed
  `1125/1125`; required S1 transaction regression tags passed `16/16`;
  setup/update and PostgreSQL UX focused coverage passed `60/60`.
- Static evidence: parser `ParseErrors=0`, source ASCII `NonAscii=0`,
  PSScriptAnalyzer Error/Warning `Findings=0`, and `git diff --check` passed.
  InjectionHunter 1.0.0 reported `42` findings and `0` unresolved after
  disposition matching.
- Deferred by explicit instruction: LaunchBox export/restore, HyperSpin
  export, thumbnail acquisition, and optional artifact/download workflows.
- No-action confirmations: no package, push, owner smoke, Arcade, wiki,
  merge, tag, publish, certification, or release-ready disposition was
  performed. Runtime proof remains unauthorized and owner smoke is paused.
- RC8FullReview P1-2 delta: owner ID 34; PR #321; `TPM-S1-LEGACY-STATE-TRANSACTIONS-001`; `TPM-TRACE-001`; behavioral tests also map to `TPM-EVIDENCE-001`. Source fixed: `Test-TpmOwnedMigrationStartupAllowed` first requires `Test-TpmTransactionResult`, then rejects `ACTION_REQUIRED` / `UNKNOWN` before new log/config path selection. Typed/malformed migration policy coverage passed `2/2`; the full source quality wrapper has now passed, while exact-head CI remains pending. Commit/push is authorized only to PR #321's existing head after source gates pass; package, merge, release, and owner runtime remain unauthorized.

## Desktop OMP S1 -- setup and manager-update transaction normalization

- Slice contract: `TPM-S1-SETUP-UPDATE-TRANSACTIONS-001`.
- Owner mapping: PR #321 owner rows 81 (startup/update flow) and 88
  (PostgreSQL profile/database setup); no separate external owner report ID was
  supplied for this implementation packet.
- Source boundary: `Invoke-PostgresGameSetup`,
  `Invoke-ManagerUpdateInstall`, `Invoke-CheckForUpdates`,
  `Invoke-StartupUpdateCheck`, their top-level callers, and the shared v1
  profile transaction wrapper.
- Deterministic focused evidence: setup/update and PostgreSQL UX tests passed
  `60/60`; required S1 transaction regression tags passed `16/16`.
- Behavior evidence: every named setup/update terminal path returns
  `TPM.TransactionResult.v1`; caller restart/completion decisions require a
  validated `SUCCEEDED` result. Backup, pre-state, final verification,
  rollback, cleanup, and terminal item accounting are retained in technical
  result fields.
- Explicit exclusions: no LaunchBox, HyperSpin, thumbnails, optional artifact
  or download outer-contract migration, dgVoodoo2, FFB, PostgreSQL 12 proof,
  package, push, owner smoke, Arcade, wiki, merge, tag, publish, certification,
  or release-ready action.
- Full-suite/static evidence: main Pester passed `1125/1125`; parser
  `ParseErrors=0`; source ASCII `NonAscii=0`; PSScriptAnalyzer Error/Warning
  `Findings=0`; and `git diff --check` passed. InjectionHunter 1.0.0 reported
  `42` findings and `0` unresolved after disposition matching.
- Permanent quality gate result: `Run-TpmQualityGate.ps1` ran the source,
  main-suite, and support-package checks successfully, then held the packet
  because owner-runtime evidence remains outstanding and report validation
  freshness was not proven. This is expected while owner smoke is paused.
  Owner/runtime proof remains unauthorized and paused.

## RC8FullReview P1-1 -- update version identity ordering

Status: MAIN AND STANDALONE AST/ASCII FIXES IMPLEMENTED; MAIN PESTER 1290/1290 AND STANDALONE CORE PESTER 51/51 UNDER BOTH ENGINES; DESTRUCTIVE APPLY 10/10; FULL SOURCE QUALITY WRAPPER PASSED 2026-10-03T07:59:42.0035591Z; EXACT-HEAD CI PENDING; OWNER RUNTIME NEEDED; OWNER SMOKE PAUSED

- Slice contract: `TPM-S1-UPDATE-VERSION-ORDERING-001`.
- Owner mapping: PR #321 owner row 81 (startup/update flow); review finding RC8FullReview P1-1; issue #105 is supporting context only.
- Conflict resolution: issue #105's historical equality of final `1.0` and `1.0-RC1` is superseded by the current user-authorized finding. The current candidate must distinguish RC7, RC8, and final 1.0; the required precedence is `1.0-RC7 < 1.0-RC8 < 1.0`. Issue #105 remains applicable to numeric-base ordering such as `0.99.99 < 1.0-RC1` and to coverage across all updater paths.
- Prior failure: main and standalone updater comparisons stripped or omitted `$ReleaseCandidateLabel`; candidate and installed script verification compared only `$ScriptVersion`, making RC7, RC8, and final 1.0 indistinguishable at the same numeric base.
- Source boundary: main `Get-ManagerVersionIdentity`, `Get-ManagerScriptVersionIdentityFromContent`, `Compare-ManagerVersionText`, update/candidate/installed identity checks, `tools/TpmAutoUpdate.Core.psm1` (`Compare-TpmVersions`, `Get-TpmLocalVersion`), and `tools/Invoke-TpmAutoUpdate.ps1`. The main script remains self-contained; no module import is added.
- Before evidence: after correcting test scope, the RC7-to-RC8 menu and RC8-to-final startup decision tests failed because the updater returned `UPDATE_ALREADY_CURRENT`; an RC7 candidate for an RC8 tag was accepted, and pre-state identity omitted the RC label.
- Spoof reproduction before AST correction: a here-string containing apparent `$ScriptVersion = "1.0"` and `$ReleaseCandidateLabel = "RC8"` declarations caused the raw-line parser to return `1.0-RC8`, while the actual top-level label was RC7; the regression expected `1.0-RC7` and failed with actual `1.0-RC8`.
- Main-path after evidence: `Tests/TeknoParrot-Manager.Tests.ps1` passed `1290/1290` under PowerShell 7 and Windows PowerShell 5.1. This includes the full comparator, source-identity, pre-state, menu/startup, candidate-install, installed-readback, rollback, and owner-status coverage; the main updater now installs a single-quoted RC8 candidate and rejects a valid-UTF-8 non-ASCII candidate before parsing.
- Standalone failing-before evidence: the focused local-reader/apply set failed `5/9`: here-string data spoofed the local identity, a valid single-quoted declaration was rejected by the regex parser, invalid declarations were not rejected, a string-only candidate passed Apply validation, and an RC7 candidate was installed under an RC8 release tag. A valid-UTF-8 candidate containing U+2014 in quoted source also passed the pre-guard standalone validator.
- Standalone after evidence: `Tests/TpmAutoUpdate.Core.Tests.ps1` passed `51/51` under PowerShell 7 and Windows PowerShell 5.1, including local AST identity extraction, candidate/tag matching, valid-UTF-8 non-ASCII rejection, and mocked Apply rejection before replacement. `Tests/TpmAutoUpdate.DestructivePath.Tests.ps1` passed `10/10` under PowerShell 7 after its harness began supplying the expected release identity. These tests establish source behavior only; the full source quality wrapper subsequently passed, and exact-head CI remains pending.
- Current static-gate evidence: Windows PowerShell 5.1 and PowerShell 7 parsed
  all six changed PowerShell source/test files with zero errors; the main
  script contains zero non-ASCII bytes; configured PSScriptAnalyzer returned
  zero findings for the main script and both updater scripts. The canonical
  production InjectionHunter scan found 40 entries, all matched to reviewed
  `FalsePositive` dispositions, with zero unresolved. Its exact time/count and
  all 40 source/rule identifiers are recorded in the test/evidence table.
- Full source-quality wrapper: `Run-TpmQualityGate.ps1` started at
  `2026-10-03T07:35:44.2922377Z` and passed at
  `2026-10-03T07:45:16.7882201Z` (exit 0). Main Pester passed `1290/1290`;
  SupportPackage passed `42/42`; ASCII/parse, configured PSScriptAnalyzer,
  `git diff --check`, and the permanent procedure gate passed.
- Direct production-validator smoke (PowerShell 7; temporary directory
  removed): extracted the actual main validator functions from the source AST
  without dot-sourcing the interactive script, then exercised those functions
  and the standalone module. Both reported local identity `1.0-RC8`, accepted
  a single-quoted RC8 candidate, and rejected a valid-UTF-8 non-ASCII candidate;
  the standalone validator also rejected an RC7 candidate under an RC8 tag.
  Candidate content was parsed, never executed. Runtime/network update paths
  were not exercised.
- One cross-engine focused Pester invocation was run concurrently in both
  PowerShell processes; Windows PowerShell 5.1's global-temp cleanup assertion
  observed a transient matching file while the PowerShell 7 updater group was
  also executing. The isolated assertion passed 1/1, and the subsequent
  serial full Windows PowerShell suite passed 1290/1290. Cross-process
  interference is the explanation consistent with the overlap, but remains
  an inference; no product cleanup behavior was changed for that observation.
- Self-adversarial identity check: PowerShell 7.6.6 and Windows PowerShell
  5.1 parse direct prefix/postfix `++` and `--` against the literal string
  identity variables as unary AST nodes, not assignment nodes. Executing
  those operators on the declared `System.String` values throws and leaves
  `1.0` / `RC8` unchanged; no identity bypass was observed. Command-based or
  dynamic-scope mutation remains the documented static-analysis boundary.
- Hunk mapping: owner row 81; PR #321 review finding P1-1; supporting issue #105 with its earlier final/RC equality assumption explicitly superseded; `TPM-S1-UPDATE-VERSION-ORDERING-001`; `TPM-TRACE-001`. Behavioral test hunks also map to `TPM-EVIDENCE-001`; architecture, security model, updater design docs, user readmes, candidate changelog, board, report, current-slice pointer, and `scripts/InjectionHunterDispositions.psd1` are mapped through the same contract and `TPM-TRACE-001`.
- No package, owner-runtime, merge, tag, release, certification, wiki, or publication action is authorized.

## Delta review TPM-7D92-DELTA-20261003 -- typed identity targets

Status: EXPANDED UVO-08 MATRIX IMPLEMENTED; REVIEW FOUND NO BLOCKING FINDINGS; MAIN/SUPPORT/UPDATER-CORE/DESTRUCTIVE SUITES PASSED UNDER WINDOWS POWERSHELL 5.1 AND POWERSHELL 7.6.6; STATIC CHECKS PASSED; FRESH SOURCE WRAPPER/PERMANENT GATE PENDING

- Review report: `TPM-7D92-DELTA-20261003`; reviewed commit `7d92a3f2379038b9c1ba3e3750766e8cf1a5ac42`; base `0295415fb1b9d4bf6880945eb4807d4b2b27ec96`; verdict CHANGES REQUIRED.
- Original finding: `AssignmentStatementAst.GetAssignmentTargets()` returns a `ConvertExpressionAst` for a typed target such as `[string]$script:ScriptVersion`. The variable-only filters skipped the target, so the scoped overwrite was not counted or scope-checked. The reviewed parsed-only reproduction accepted full identity `1.0-RC8` in Windows PowerShell 5.1 and PowerShell 7.6.6; the candidate was not executed.
- Self-adversarial follow-up: parser diagnostics in both PowerShell 5.1 and 7.6.6 confirmed `($script:ScriptVersion) = "1.1"` parses without errors as `ParenExpressionAst`, and `[string]($script:ScriptVersion)` is a `ConvertExpressionAst` wrapping that parenthesized target. The original variable-only filters also skipped these shapes.
- Before-fix test evidence: the cast-target tests failed under both engines: the main parser and validator did not throw and the install regression observed one `Move-Item` call; standalone local reader, validator, and `-Apply` did not throw. The follow-up parenthesized parser regression also failed before the correction; all fixtures assert zero PowerShell parser errors before checking rejection.
- Contract mapping: UVO-08 in `TPM-S1-UPDATE-VERSION-ORDERING-001`; PR #321 owner row 81; review report `TPM-7D92-DELTA-20261003`; supporting issue #105; PR #321; `TPM-TRACE-001`; behavioral tests `TPM-EVIDENCE-001`; owner/runtime proof `TPM-OWNER-001`.
Historical pre-expansion implementation: both parsers unwrapped nested `ConvertExpressionAst.Child` targets and only transparent one-command-expression parentheses. A dual-engine parsed-only probe then found `[ValidateNotNull()]$script:ScriptVersion = "1.1"` as `AttributedExpressionAst.Child = VariableExpressionAst`; that pre-expansion code missed it. The current implementation handles that shape and the complete reviewed direct-static matrix below.
- Historical pre-expansion focused evidence: both parser/test files passed 6/6 UVO-08 cases per engine, but this did not cover attributed targets or the new write classes. The prior independent `APPROVED` verdict applies only to those old hashes; the subsequent attributed-target review returned CHANGES REQUIRED. The revised contract plan is confirmed, not a source-code verdict.
- Historical pre-expansion full suites: Pester 5.7.1 in this worktree passed 1357/1357 in PS7 and 1357/1357 in Windows PowerShell 5.1 before the attributed-expression discovery; the separate wrong-root 1235/1235 run remains excluded. The integrated `bg_87` run passed main Pester 1293/1293 and SupportPackage 42/42, then failed the permanent procedure gate because validation evidence predated the latest source/test/gate change (`artifact://1060`). Preserve all output; none is final acceptance.
- Historical pre-expansion static evidence: main-script non-ASCII byte count 0; five PowerShell source/test files parsed with 0 errors; configured PSScriptAnalyzer 0 findings; canonical InjectionHunter tool 1.0.0, 40 findings, 0 unresolved, with disposition matching and no stale entries. These checks must be rerun after source changes.
- Historical pre-expansion SHA-256 only: main `CE14DA8BE76090997D4D6C15F0069AE8889EE5D7DBE33D66B08DC63480368FF7`; core module `5402D505B3B6D2720F1EB00494D878A4F01489AAE38961BE253383E9FA3BB38D`; main tests `EAF7F16CAF7B30F54046312CB0D5E1AFF1D327181238C77B4BD92EAC57B3A829`; core tests `1564FB0E3620B310975B0DE478FEC5326CA7B27EEF2BAC17EA61B7C5E57FE9BA`. Do not use these as final hashes.
- Current implementation: both parsers inspect assignment targets and traverse only attributed/cast children, transparent one-command-expression parentheses, `ArrayLiteralAst.Elements`, `MemberExpressionAst.Expression`, and `IndexExpressionAst.Target`. Lvalue traversal uses an explicit stack rather than recursive calls. Protected prefix/postfix increment/decrement, foreach variables, root script parameters, and data-statement variables are rejected; function-local parameters remain allowed. Indirect command/provider/data-flow mutation is outside scope; no sandbox claim is made.
- Current focused evidence after implementation: main `[UVO-08]` tests passed `6/6` in Windows PowerShell 5.1 and `6/6` in PowerShell 7.6.6; standalone core `[UVO-08]` tests passed `7/7` under both. Main candidate install and standalone Apply tests assert no replacement on attributed protected writes; valid proof snippets assert zero parser errors. `Get-TpmLocalVersion` accepts the actual manager source as `1.0-RC8` under both engines. Focused evidence is not full-suite or source-gate acceptance.
- Before/after matrix evidence: first expanded regressions failed under both engines before implementation (main parser/validator accepted attributed writes and main install called `Move-Item`; standalone reader/validator/apply accepted the write). The post-implementation focused results above pass. Candidate content is parsed, never executed.
- Docs synchronized in the same slice: `ARCHITECTURE.md`, `SECURITY.md`, `docs/AUTO_UPDATE.md`, `docs/wiki-updates/Check-for-Updates.md` (staging only), `README.md`, `TeknoParrot-Manager-README.txt`, and the existing RC8 candidate changelog entry now describe the finite static-write contract and explicitly disclaim indirect runtime mutation.
- Final source/test review: no blocking findings on the stable UVO-08 implementation and test matrix. Exact reviewed SHA-256 identities: main source `C649214E769EA19780352EF1B449099957C85AEF86F2FC767CDDA10F82DC1209`; standalone core `41944B88766C06D299354CAED0DBA5531E8042A5339BBF76855E0F188E78ADE9`; main tests `BD262A64921E9EBD92D77F112976E78847C7BE106727D29CB2B02697086EDF99`; core tests `F56FF89E05C1A0EAD1DD60CBD3A454BFC46D722F52E2C4F30B39510C81868FEA`. No source/test edits have followed this review.
- Current mapping remains UVO-08 in `TPM-S1-UPDATE-VERSION-ORDERING-001`; PR #321 owner row 81; report `TPM-7D92-DELTA-20261003`; `TPM-TRACE-001`; behavioral tests `TPM-EVIDENCE-001`; owner-runtime proof `TPM-OWNER-001`. The expanded review found no blocking findings on the reviewed source/test hashes. Both-engine full suites, static checks, and the fresh source wrapper passed. Final post-board artifact-contract tests passed 3/3 at 2026-10-03T13:16:47Z; the procedure gate then passed at 2026-10-03T13:17:53Z with `ChangedAtUtc` 2026-10-03T13:16:01Z. Dottie owns remote CI; no polling or status check from this lane.
- No package, runtime/owner smoke, merge, tag, release, certification, live wiki, or publication action is authorized. Scoped commit/push to the existing PR #321 head is authorized only after all required gates pass; parent owns exact-head CI.

## Run 37090573916 -- narrow CI failure reconciliation

- CI metadata identifies PR head `0295415fb1b9d4bf6880945eb4807d4b2b27ec96`; the workflow checked out synthetic merge commit `39301e430849c0996746187aecfffa937fe705b6` with tree `8ff087e02ed81f8352b7991753d07b35b8ab2e3f`, not candidate tree `07d45a549d6db53371bfcb1f1a014d1a0b1b9b3b`.
- The one Pester assertion failure is `uses canonical owner statuses and scopes stale-package rejection to certification mode` at `Tests/TeknoParrot-Manager.Tests.ps1:17648`. It captures a child `pwsh` gate's redirected `Write-Error` output. CI log evidence shows ANSI escape sequences interleaved with `SOURCE REMEDIATION REQUIRED`; those non-whitespace bytes prevent the expected status regex from matching. The same raw ESC character causes Pester 5.7.1 NUnit XML export to fail.
- This test exercises synthetic owner-report status fixtures and `Test-TpmPermanentProcedures.ps1`; it does not run either updater comparison or migration startup. The failure is independent of both RC8FullReview P1 findings.
- Scoped correction: strip ANSI CSI sequences from captured child output; configure checkout to use the PR head repository and SHA, then assert `git rev-parse HEAD` equals the expected PR-head SHA. Map to owner ID 3 status semantics, PR #321, `TPM-OWNER-STATUS-GATE-001`, `TPM-OWNER-003`, `TPM-TRACE-001`, and `TPM-AUTH-001`.
- After correction, the focused main matrix including the owner-status assertion passed `21/21`. The broad workflow gate and fresh exact-head CI remain pending; the source correction does not promote owner status.

## Desktop OMP S2-A -- shared transaction presentation contract

- Slice contract: `TPM-S2-RESULTS-PRESENTATION-001`.
- Scope: deterministic `TPM.TransactionPresentation.v1` projection from
  validated `TPM.TransactionResult.v1`; fixed wording for all seven outcomes;
  authoritative item-set counts and safe item labels; redacted
  Details/support references; presentation text validation.
- Source boundary: `TeknoParrot-Manager.ps1` presentation contract helpers;
  `Tests/TeknoParrot-Manager.Tests.ps1` S2-A deterministic projection tests;
  `ARCHITECTURE.md`; this report; and the PR #321 control board.
- Explicit exclusions: workflow-wide renderer migration, workflow-status
  event migration, support-package serialization migration, package rebuild,
  owner smoke, Arcade, wiki, push, merge, tag, publish, certification, and
  release authorization.
- Runtime proof: not authorized; owner smoke remains paused.
- Focused S2-A evidence: 15 passed, 0 failed, 0 skipped, 1125 not run.
- S1 transaction regression evidence: 73 passed, 0 failed, 0 skipped,
  1067 not run.
- Support-package evidence: 41 passed, 0 failed, 0 skipped.
- Full main Pester evidence: 1140 passed, 0 failed, 0 skipped.
- Static evidence: Windows PowerShell parser `ParseErrors=0`, pwsh parser
  `ParseErrors=0`, production ASCII `NonAscii=0`, PSScriptAnalyzer
  Error/Warning `Findings=0`, and `git diff --check` passed.
- InjectionHunter scope reconciliation: the earlier 30-finding direct scan covered
  only `TeknoParrot-Manager.ps1`. The canonical
  `Test-TPMProductionInjectionHunterV1` scan covers the fixed 19-file production
  PowerShell inventory and reports 42 findings: 30 in the product script plus
  12 across the other production files. All 42 matched the current disposition
  registry using canonical occurrence-order reconciliation;
  `Unresolved=0`, `StaleEntries=0`.
- No-action confirmations: no package, push, owner smoke, Arcade, wiki,
  merge, tag, publish, certification, or release-ready disposition is part of
  S2-A.

## Desktop OMP S2-B1 -- shared transaction renderers

- Slice contract: `TPM-S2B1-RENDERERS-001`.
- Scope: pure normal and Details renderers over the S2-A presentation,
  redaction/provenance-bound Details context, narrow terminal workflow-status
  bridge, and the authorized normal ReShade summary adapter.
- Source boundary: `TeknoParrot-Manager.ps1` shared renderer and status-bridge
  helpers plus the normal ReShade onboarding summary; no workflow-wide caller
  migration or support-package serialization change.
- Test boundary: `Tests/TeknoParrot-Manager.Tests.ps1` tag
  `S2-B1-RENDERERS`, including all seven outcomes, item ordering, Details
  identity and redaction, status fail-closed behavior, ReShade summary
  adapter/detail preservation, actual changed/skipped/failed label mapping, and
  selected-set transaction accounting.
- Focused S2-B1 evidence: 12 passed, 0 failed, 0 skipped, 1140 not run.
- Focused S2-A evidence after S2-B1 source integration: 15 passed, 0 failed,
  0 skipped, 1133 not run.
- Full main Pester evidence after all S2-B1 edits: 1152 passed, 0 failed,
  0 skipped, 0 not run.
- Static evidence: Windows PowerShell parser `ParseErrors=0`, pwsh parser
  `ParseErrors=0`, production script ASCII `NonAscii=0`, PSScriptAnalyzer
  Error/Warning `Findings=0`, and `git diff --check` passed.
- InjectionHunter 1.0.0 canonical production inventory scan after the final
  source change: 42 findings matched 42 registry entries with `Unmatched=0`;
  no source finding was dismissed by label alone.
- InjectionHunter disposition review: the 12 non-product findings were
  individually traced to trusted repository AST re-parsing, fixed literal
  regex/assembly inputs, fixed allowlist property names, or fixed interop
  source. Their registry entries predate this slice; no disposition entry was
  added for S2-B1.
- Permanent procedure gate: source, main Pester, support Pester, parser,
  analyzer, ASCII, diff, and InjectionHunter checks passed; the fail-closed
  gate held the packet because owner-runtime evidence remains outstanding.
- Runtime proof: not authorized; owner smoke remains paused.
- Deferred actions: package rebuild, owner smoke, Arcade validation, wiki,
  push, merge, tag, publish, certification, and release-ready decision.

## Desktop OMP -- BepInEx functional transaction audit

- Slice contract: `TPM-BEPINEX-FUNCTIONAL-TRANSACTION-001`.
- Authorized source boundary: `TeknoParrot-Manager.ps1` BepInEx package
  handoff, candidate identity checks, legacy result accounting, and normal
  output; focused BepInEx tests; `ARCHITECTURE.md`; this report; and the
  control board.
- Functional correction: the selected architecture now resolves to the
  downloaded cache package through `$zipByArch`, with nonblank containment,
  existing-file, and non-reparse validation immediately before extraction.
- Identity correction: the canonical candidate game path/root is compared at
  pre-staging, pre-backup, and pre-promotion boundaries; the current candidate
  cannot inherit another candidate's destination.
- Accounting correction: actual selected, changed, failed, and skipped profile
  IDs are carried into `TPM.TransactionResult.v1`; synthetic counter names and
  unrelated XML profiles are excluded; `FailureRecords` remain in technical
  details.
- Presentation correction: protected roots remain unchanged safe skips; grouped
  output uses readable names where available; verified package download and
  per-game install failure are distinct; raw paths and exception text remain
  outside normal output.
- Focused BepInEx evidence: 19 passed, 0 failed, 0 skipped.
- S1 transaction-core evidence: 18 passed, 0 failed, 0 skipped.
- S2-A presentation evidence: 15 passed, 0 failed, 0 skipped.
- S2-B1 renderer evidence: 12 passed, 0 failed, 0 skipped.
- Full main Pester: 1155 passed, 0 failed, 0 skipped. Support Pester: 41
  passed, 0 failed, 0 skipped.
- Windows PowerShell and pwsh parser checks passed; PSScriptAnalyzer findings:
  0; production ASCII non-ASCII bytes: 0; `git diff --check` passed.
- Disposition-backed canonical InjectionHunter check: `Executed=True`;
  `FindingCount=42`; `UnresolvedFindingCount=0`; `ToolVersion=1.0.0`;
  `StaleEntries` was not reported by the result object.
- Permanent procedure gate executed after these checks and failed closed
  without release authorization because owner-runtime evidence remains
  outstanding and the supplied reconciliation report is newer than the source
  timestamp used for its freshness check.
- Runtime proof: not authorized; owner smoke remains paused.
- Package rebuild, Arcade, wiki, push, merge, tag, publish, certification, and
  release-ready actions remain excluded.

## Desktop OMP -- Support posture corpus and CHD/layout implementation

- Slice contract: `TPM-SUPPORT-POSTURE-001`.
- Owner requirement: `SUPPORT-POSTURE-001`, including the skylinekiller
  CHD/layout finding.
- Implementation status: offline corpus snapshot, classification, CHD/layout
  taxonomy, deterministic JSON/Markdown output, and focused fixtures/tests are
  implemented. Product registration, repair discovery, `.chd` recognition, and
  TeknoParrotUI-owned writes are unchanged.
- Source: `scripts/New-TpmSupportPostureCorpus.ps1`.
- Test: `Tests/SupportPostureCorpus.Tests.ps1` passed 9, failed 0, skipped 0.
- Fixture evidence: 22 generated records; `AUTOMATED_SAFE=4`,
  `REVIEW_MANUAL=13`, `BLOCKED_UNSUPPORTED=5`, `UNCLASSIFIED=0`; all 22
  fixture expectations passed. All 15 required CHD/layout taxonomy classes
  were observed.
- Corpus schema: `manifest.json` records snapshot/source identity and raw XML
  hashes; `support-posture.json` records normalized profile metadata,
  ownership, layout observations, DAT evidence, fixture coverage,
  classification totals, and release-gate booleans; `support-posture.md` is
  the beginner-readable matrix without raw filesystem paths.
- Source authority: installed GameProfiles are overlaid onto a pinned upstream
  profile set by case-insensitive ProfileCode; UserProfiles are read-only
  observations; Eggman/RomVault DATs are secondary evidence.
- Local validation: Windows PowerShell 5.1 parse passed; pwsh parse passed;
  PSScriptAnalyzer Error/Warning passed for the main script and new corpus
  script with `PSScriptAnalyzerSettings.psd1`; changed PowerShell/test files
  contain zero non-ASCII bytes; and `git diff --check` passed.
- InjectionHunter 1.0.0 scanned the new corpus script: 1 finding,
  `InjectionRisk.AddType` at line 419, disposition-backed as a fixed
  `System.IO.Compression.FileSystem` literal with 0 unresolved findings.
- Existing regression gates under Pester 5.7.1: `TeknoParrot-Manager.Tests.ps1`
  passed 1155, failed 0, skipped 0; `SupportPackage.Tests.ps1` passed 41,
  failed 0, skipped 0; focused support posture tests passed 9, failed 0,
  skipped 0.
- Generated-artifact review passed: the focused run created the expected
  manifest, JSON, Markdown, raw-profile, UserProfiles-observation, DAT, and
  fixture artifacts only under the explicit output root; no generated output
  was added to the repository.
- Permanent gate: `Run-TpmQualityGate.ps1` ran the source, main-suite, and
  support-package checks, then failed closed because owner-runtime evidence
  remains outstanding and the report is newer than the supplied source
  `ChangedAtUtc`; no completion claim was made.
- Remaining evidence: the actual owner-approved runtime CHD/layout smoke,
  package identity, and release certification are not authorized in this
  slice. Hosted CI and push are not authorized.
- Current disposition: implementation evidence is complete for this slice;
  release posture is `HOLD`.

## Desktop OMP -- Catalog-wide game support contracts

- Slice contract: `TPM-GAME-SUPPORT-CONTRACTS-001`.
- Owner report: `TPM_GAME_SUPPORT_CONTRACTS_001`.
- Pinned source: `teknogods/TeknoParrotUI` commit
  `5880e019016c5c3a0576e97a6c2a7f14bf54e3d1`.
- Catalog discovery: 695 GameProfiles XML files, 383 GameSetup XML files, and
  693 Metadata JSON files. All 695 GameProfiles parsed in the pinned-corpus
  generation run.
- Registry implementation: immutable compatibility schemas and validators for
  `GameSupportContractV1` 1.1.0, static `GameSupportContractV1` 1.2.0, and
  `GameSupportContractRegistryV1` 1.2.0. The separate
  `GameSupportAssessmentV1` 1.0.0 schema/authority binds machine/runtime
  observations to an immutable 1.2.0 contract snapshot.
- Static 1.2 contracts contain no runtime validation result or top-level
  runtime automation flag. Support-file presence, expected path, and hash
  states are orthogonal in assessments; successful launch does not verify
  controls.
- Pinned-corpus generation proof: 695 contracts, zero duplicate profile
  codes, zero `UNCLASSIFIED`, every record has posture/reason/profile hash,
  and registry closure eligible for the source-only snapshot.
- Source-only posture totals: `AUTOMATED_SAFE=0`, `REVIEW_MANUAL=695`,
  `BLOCKED_UNSUPPORTED=0`, `UNCLASSIFIED=0`. No runtime layout fixtures were
  supplied for the pinned catalog run.
- Hummer and Hummer Extreme retain pinned revisions 13 and 14, their exact
  executable rules and profile/setup/metadata hashes, and manual posture.
  No crash cause, media relationship, or unverified fix is declared.
- Backend derivation audit matched 14 cxbxr profiles:
  `CTHR`, `GBOS`, `HOTD3`, `OllieKing`, `or2`, `or2b`, `or2sp`, `SGC05`,
  `SGC06`, `vc3`, `WMMT1`, `WMMT1J`, `WMMT2`, and `WMMT2j`. Each matching
  record declares exactly `ic10_g24lc64.bin`, `pc20_g24lc64.bin`,
  `ic11_24lc024.bin`, and `fpr21042_m29w160et.bin` at the pinned cxbxr
  relative paths. Non-cxbxr records do not receive those items.
- Focused Pester 6.1.0 proof: the combined contract, assessment, and
  support-posture suites passed 32, failed 0, skipped 0.
- Core regression proof: `TeknoParrot-Manager.Tests.ps1` passed 1155,
  failed 0, skipped 0; `SupportPackage.Tests.ps1` passed 41, failed 0,
  skipped 0.
- Generated-artifact review passed: the pinned registry loaded and revalidated,
  and every generated file remained below the explicit output root; no
  generated artifact was added to the repository.
- Installer, repair, deployment, registration, launch, and TeknoParrotUI-owned
  write consumers are not wired to the registry or assessment.
- Direct InjectionHunter, owner-runtime evidence, package identity, hosted CI,
  Arcade, wiki, push, merge, tag, publish, certification, and release
  authorization remain outside this slice and were not performed.

## External software schema 1.3 implementation handoff

- Owner report: `TPM_GAME_SUPPORT_CONTRACTS_001`.
- Slice contract: `TPM-GAME-SUPPORT-CONTRACTS-001`.
- Implemented scope: additive Contract/Registry schema 1.3, Assessment schema
  1.1, typed external-software evidence, conservative Showdown declaration,
  read-only assessment state, version dispatch, and deterministic generation
  coverage.
- Permanent tests: `TPMGameSupport.Contracts.Tests.ps1`,
  `TPMGameSupport.Assessments.Tests.ps1`, and
  `SupportPostureCorpus.Tests.ps1`.
- No product menu, installer, repair, launch, download, redistribution, EULA,
  package, owner-runtime, Arcade, commit, push, merge, tag, publish,
  certification, or release operation was performed by this handoff.
- Disposition remains source/test implementation review only; runtime
  promotion and release authorization remain blocked pending their separate
  gates.

## Desktop OMP -- Slice 0 immutable current-release catalog snapshot

- Slice contract: `TPM-RELEASE-SNAPSHOT-001`.
- Owner report: `TPM_RELEASE_SNAPSHOT_001`.
- Scope is limited to immutable release/source evidence and machine-generated
  catalog delta artifacts. No product runtime behavior or contract migration
  is included.
- Stable release identity: TeknoParrotUI `1.0.0.2128`, release ID `16543041`,
  asset `TeknoParrotUi.zip`, size `153159505`, SHA-256
  `9e6a8628d365a9d7c32f1dee07f1a62799656a9fdb1b58afe863526c5cf84901`.
- Snapshot ID:
  `TPM-GAME-SUPPORT-RELEASE-1.0.0.2128-ASSET-9E6A8628`.
- Catalog inventory target: `925 GameProfiles`, `383 GameSetup`, `923
  Metadata`, and `2231` total files.
- Matching source-proof commit:
  `dc998e374608abbda373bb3c236db5b26b5afca7`, tree
  `7266c43c829bfd2147247b2fae0167ec44116fc5`. The commit is recorded as an
  immutable semantic proof only, not official release provenance and not a
  live-master dependency.
- The stable release asset was observed mutating in place from the earlier
  `1.0.0.2127` digest/size observation to the current `1.0.0.2128`
  digest/size observation. The history is preserved in
  `asset-mutability.json`.
- The full binary release ZIP is not vendored. The snapshot stores release
  evidence, per-file asset hashes, semantic-root digests, source-proof
  identity, and machine-generated delta lists. The immutable source-proof
  commit is the approved reproducibility backing after semantic equality is
  proven.
- Required delta counts remain `695` historical, `925` current, `230` added,
  `0` removed, `38` semantic changed, and `657` semantic unchanged. The
  canonical added identity is machine-generated from the asset and must be
  `jdredd`.
- Matching upstream commit application changes in `GameProfile.cs`,
  `JoystickMapping.cs`, `GameProfileLoader.cs`,
  `JoystickControlDirectInput.cs`, and `JoystickHelper.cs` are recorded for a
  later joystick/profile-loading/FFB slice only.
- Slice 0 does not perform contract migration, package rebuild, owner smoke,
  Arcade validation, merge, tag, publish, certification, or release action.
- Current disposition: implementation evidence pending focused validation and
  review; PR #321 remains `HOLD`.

## Desktop OMP -- Slice 1 current-release GameSupport contract migration

- Slice contract: `TPM-S1-CURRENT-RELEASE-GAMESUPPORT-002`.
- Inventory: `docs/remediation/inventories/TPM-S1-GAMESUPPORT-CONTRACT-INVENTORY.md`.
- The generator now has explicit `LEGACY_COMPATIBILITY`,
  `HISTORICAL_PINNED_695`, and `CURRENT_RELEASE_925` modes. Current mode
  rejects installed, fixture, DAT, and live-source inputs.
- Current output binds SnapshotId
  `TPM-GAME-SUPPORT-RELEASE-1.0.0.2128-ASSET-9E6A8628` and semantic proof
  commit `dc998e374608abbda373bb3c236db5b26b5afca7`, with 925 validated
  schema 1.3 contracts and zero `UNCLASSIFIED` records.
- Generated comparison evidence is exact: 230 added, 0 removed, 38 changed,
  and 657 unchanged. The added identities and changed-field matrix are
  written below the caller output root.
- Executable evidence is fail-closed: GameProfile wins, GameSetup fills only a
  missing profile declaration, equivalent case differences normalize, and
  contradictions clear the selected target and retain manual review.
- Historical fixture generation remains the compatibility path. No package,
  owner runtime, Arcade, hosted CI, commit, push, merge, tag, publish,
  certification, or release operation was performed.
- Current executable evidence is intentionally generation-mode scoped:
  `CURRENT_RELEASE_925` uses the generic resolver, while
  `HISTORICAL_PINNED_695` preserves the pre-Slice-1 GameProfile executable
  projection and does not allow GameSetup evidence to select or contradict a
  historical executable.
- Governing historical compatibility requirement: complete 703-file byte
  equality across every emitted artifact, not only contracts, validation, and
  manifest. Earlier implementation-pass evidence reached zero differences
  under both engines, but final frozen revalidation remains pending.
- Historical manifest ordering uses the immutable identity-bound input artifact.
  SchemaVersion, SnapshotId, source commit, declared/actual counts, exact and
  case-insensitive uniqueness, and complete coverage are validated before rank
  construction and fail closed. Permanent malformed-artifact and
  production-wiring tests cover those branches.
- Current-release generation was previously exercised under both engines with
  935 files and 925/230/38/657/0 invariants. Final frozen revalidation remains
  pending.
- The accepted historical order is independently bound by SHA-256
  `b7ec88b0de487fbcdcdf697334ccbec154a0f61e8c0a24712f2e99425425f4aa` over
  the UTF-8/LF ProfileCode projection. Reorder-only complete-set artifacts
  fail closed before rank construction. Final frozen equality remains pending.
- Current mode retains equivalent-path confirmation, UNKNOWN-as-non-evidence
  handling, and fail-closed contradictions.
- Representative current-mode evidence remains:
  `VirtuaRLimit` selects `launcher.exe` through `GAMESETUP_FALLBACK`;
  contradictory declarations clear the selected target; literal `UNKNOWN`
  setup evidence is discarded.
- Documentation screenshot gate is not satisfied: no current validated runtime
  screenshots exist. No mock, stale, or synthetic screenshots were added, and
  README, QuickStart, setup, and feature documentation remain unchanged until a
  later authorized runtime capture/doc slice.
- Corrected local evidence gates pass, but the current disposition remains
  `HOLD_SLICE_1_CONTRACT_MIGRATION` pending screenshot evidence and review.

## Historical baseline provenance re-baseline

The previous temporary baseline remains preserved as a legacy candidate. Its
703-file content, historical identity, and ordered sequence are strongly
corroborated, but the original creation command was not recoverable from
retained evidence. It is therefore not relabeled as an authoritative
baseline, and the issue is classified as evidence-retention/process loss,
not a demonstrated product defect.

The replacement evidence is durable under
`contracts/baselines/TPM-HISTORICAL-695/`. Its provenance manifest binds
`HISTORICAL_PINNED_695`, generator HEAD and script hash, the accepted source
root and commit `5880e019016c5c3a0576e97a6c2a7f14bf54e3d1`, SnapshotId
`TPM-HISTORICAL-695`, both execution engines, fixed generation parameters,
and the replacement output identity. The complete inventory records all 703
relative paths, byte lengths, and SHA-256 values. Its tree projection is
ordinal normalized-path order with UTF-8/LF serialization.

Independent PS5.1 and PS7 replacement generations matched with zero missing,
extra, or differing files. The replacement matched the legacy candidate
across all 703 files; this is retained only as
`CORROBORATIVE_COMPATIBILITY_WITH_LEGACY_CANDIDATE`. Compatibility semantics
and the independently pinned ProfileCode sequence digest remain unchanged.
Formal acceptance remains pending review; this record does not authorize
commit, release, certification, or runtime activity.

## Desktop OMP -- RC8 compact-default menu corrective slice

- Owner report: `ARC-UX-S01` (Issue #323).
- Slice contract: `TPM-MENU-COMPACT-DEFAULT-001`.
- Root cause: `TeknoParrot-Manager.ps1` had duplicate
  `Get-ConsoleLayoutTier` definitions. PowerShell used the later legacy
  width-only definition, defeating the compact-default policy and selecting a
  crowded two-column menu for ordinary viewports.
- Required source evidence: exactly one production selector definition; one
  centralized wide threshold used by production and
  `Debug-TPM-MenuLayout.ps1`; ordered options 1-15 with H/L/Q and prompt below;
  no consecutive blank render rows in the normal compact screen; complete
  constrained-height fallback; and workflow status closed before PostgreSQL
  failure return to the outer menu.
- Required test evidence: focused menu/layout and PostgreSQL return-to-menu
  tests under PS7 and Windows PowerShell 5.1, plus parser, PSScriptAnalyzer,
  ASCII, and `git diff --check`.
- Runtime disposition: `SOURCE FIXED; OWNER RUNTIME NEEDED`. Package identity,
  owner-runtime screenshots, and release authorization remain outside this
  desktop slice.
- Hunk mapping: `TeknoParrot-Manager.ps1` and
  `Tests/TeknoParrot-Manager.Tests.ps1` -> `TPM-MENU-COMPACT-DEFAULT-001` /
  `ARC-UX-S01` / `TPM-TRACE-001`; documentation evidence ->
  `TPM-OWNER-001` through `TPM-OWNER-003`.
