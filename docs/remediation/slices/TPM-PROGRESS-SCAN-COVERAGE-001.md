# RC8 progress scan coverage remediation slice

## 1. Slice name

- Name: Universal progress scan coverage across scanners and transactional mutation loops
- Contract ID: `TPM-PROGRESS-SCAN-COVERAGE-001`
- Issue/PR: PR #321; owner report IDs 3, 4, 5, and 29

## 2. Owner report IDs included

- The final gate-required categories are audited: ReShade version discovery is one 10-second HTML request with a visible checking message; FFB upstream metadata calls are bounded and stage-reported while DLL transfers use shared compact/workflow progress; Crosshair target planning and HyperSpin system-file, existing-game, and UserProfiles scans now emit known-total progress, distinct from bounded preview and asset writes.

## 3. Explicit exclusions

- Owner IDs not included: all other PR #321 rows, including ID 6 thumbnail progress and ID 32 global prompt consistency.
- Features, modules, package, runtime, and release actions excluded: no new progress feature, no change to network transport, retry, URL, or error behavior, no game mutation, packaging, runtime smoke, commit, push, merge, tag, publication, certification, or release authorization. ReShade asset acquisition uses the existing silent web-request wrapper through its existing compact-download status helper; only status visibility changes.

## 4. Behavior contract

- Current failure: known-total AutoSync ZIP classification and multiple GameProfiles catalog scans lacked call-site-bound progress; the universal inventory also omitted standalone FFB per-profile phases and dgVoodoo2 registered-profile scanning. Follow-up audits found UserProfiles manifest/backup/restore, generic transactional file batch/promotion/rollback, owned-state migration, ReShade acquisition/deploy/removal, support profile/plugin scans, PostgreSQL reinitialize/recovery scans, cursor-hide/crosshair scans, and recursive game-file discovery requiring explicit compact status.
- Expected behavior: both AutoSync pickers, catalog helpers, profile indexing, ProfileSet retry/tree/fallback, FFB planning/revalidation/update/final-verification phases, dgVoodoo2 registered-profile scanning, verified UserProfiles manifest/backup/restore phases, generic transaction staging/backup/promotion/final-verification/rollback phases, owned-state migration inventory and mutation phases, ReShade approved-asset acquisition/deploy/removal scans and transaction phases, support profile/plugin inventory scans, PostgreSQL plan/recovery profile scans, CursorHide planning/revalidation/update/final-verification loops, Crosshair PNG/profile discovery, and registration game-file discovery expose compact bounded status with known totals where available and close rows.
- Support package lifecycle: the embedded `SupportWorkflowAtArchiveSnapshot` and manifest line are point-in-time evidence captured while the ZIP workflow is active. The returned workflow result and `WorkflowCompleted` event become Finished only after identity-bound promotion and path verification. Archive creation and promotion status are never reported as workflow completion before those operations finish.
- Support inventory uniqueness: nested allowlisted roots are collapsed before traversal, so each safe plugin path contributes exactly one TSV row and each filesystem entry advances progress once.
- Forbidden regressions: no `Write-Progress`; no invented percentage for unknown totals; no change to candidate ordering, profile classification, GPU/FFB field results, picker choices, backup bytes/hashes, mutation boundaries, transaction outcomes, rollback order, or scan failure handling; no paths or per-item identifiers in progress labels except the established thumbnail label containing profile code and count; no progress rendering in redirected output beyond existing renderer behavior.
- Design boundaries and deliberate exclusions: bounded waits and renderer-aware interactions remain governed by `TPM-PROGRESS-001`; opaque framework calls without per-item callbacks retain explicit bounded/short-circuit dispositions. Independent re-audit found user-extensible Crosshairs PNG discovery and filename sorting uncovered. The working-tree fix uses `-ErrorAction Stop`, keeps unknown-total progress active through the sort, and closes before validation; six other residual expressions remain bounded/short-circuit. Final source gates are pending.
- Verified coverage for the newly audited paths: Crosshair PNG discovery/sorting now remains visible until completion, then image validation emits known-total progress; profile planning and HyperSpin system-file lookup, named-file validation, existing-game load/index, and UserProfiles XML scans close known-total rows while preserving profile order, deployment targets, and exported JSON. ReShade latest-version lookup and FFB revision/support-table requests remain bounded metadata requests with visible phase messages; DLL transfers use shared download progress. Signature validation, fixed-size preview rendering, and single-file asset writes remain bounded no-progress surfaces.

## 5. Source/function ownership

- Files: `TeknoParrot-Manager.ps1`; `Tests/TeknoParrot-Manager.Tests.ps1`; `Tests/SupportPackage.Tests.ps1`; `ARCHITECTURE.md`; `docs/remediation/PR-321-control-board.md`; `docs/remediation/PR-321-reconciliation.md`.
- Functions/regions: `Select-GamesInteractive`; `Select-GamesInteractiveCombined`; `Get-GpuFixFieldNames`; `Get-GpuAndFfbFieldNames`; `Get-FFBBlasterFieldNames`; `Build-ProfileIndex`; `Get-TeknoParrotProfileSet`; `Invoke-FFBBlasterSetup`; `Invoke-DgVoodoo2Setup`; `Get-TpmUserProfilesBackupManifest`; `New-TpmVerifiedUserProfilesBackup`; `Restore-TpmVerifiedUserProfilesBackup`; `Invoke-TpmTransactionalFileBatch`; `Invoke-TpmTransactionalPromote`; `Invoke-TpmOwnedMigration`; `Acquire-TpmReShadeApprovedEffect`; `Install-TpmReShadeApprovedEffect`; `Install-TpmReShadeProfileDeployment`; `Get-TpmReShadeRemovalScan`; `Remove-TpmReShadeOwnedDeployment`; `Get-TpmSupportPluginInventory`; `New-TpmSupportPackage`; `Get-PostgresReinitializePlansFromProfiles`; `New-PostgresRecoveryBackup`; `Invoke-CursorHideSetup`; `Invoke-CrosshairSetup`; `Get-GameFiles`; `Register-GamesLegacy`; `Write-TpmCompactExtractionProgress`.
- Owning subsystem: Progress.Core / PR #321.
- Additional audited functions: `Invoke-CrosshairSetup`; `Export-HyperSpinJson`; `Get-ReShadeLatestVersion`; `Get-FFBPluginSourceRevision`; `Get-FFBPluginGameMap`.

## 6. Tests required before implementation

- Focused behavior tests: existing coverage binds progress to AutoSync classification, GPU/FFB catalog helpers, profile indexing, ProfileSet routes, FFB mutation, and dgVoodoo2 scanning. Before changing newly audited mutation paths, add fixture-backed behavior tests observing progress in verified UserProfiles backup/restore, transactional file batch/promotion, and owned-state migration while asserting resulting files/outcomes. Before changing ReShade/support/registration paths, add tests asserting progress alongside acquired/deployed/removed bytes, support ZIP/evidence contents and inventory limits, and registration's discovered executable set. PostgreSQL backup tests, CursorHide mutation tests, and Crosshair UI-boundary tests must assert progress without weakening existing safety or interaction boundaries.
- Before production edits for the newly identified loops, add fixture-backed tests that invoke the real Crosshair setup through mocked browser/mutation boundaries and HyperSpin export with fixture JSON/XML; assert progress current/total/completion plus unchanged deployment targets/export results.
## 7. Tests required after implementation

- Focused behavior tests: named progress call-site tests, FFB success path and dgVoodoo2 scan tests; fixture-backed transaction, migration, ReShade acquisition/deploy/removal, support profile/plugin inventory, and `Get-GameFiles` registration discovery tests assert both progress and real outputs.
- Support inventory must contain one row per safe plugin path, even when the allowlisted roots overlap; the fixture asserts both unique TSV rows and one traversal of the nested plugin file.
- Post-edit tests must prove Crosshair PNG discovery advances with unknown totals and closes before the known-total validation pass, while preserving the accepted candidate set, sorted selection, P1/P2 target bytes, and the existing profile-planning behavior. HyperSpin discovery must continue preserving JSON/file contents.
- Regression suite: full `Tests/TeknoParrot-Manager.Tests.ps1`, `Tests/SupportPackage.Tests.ps1`, parser, ASCII, PSScriptAnalyzer, InjectionHunter, `git diff --check`, and permanent procedure gate.

## 8. Documentation/report updates required

- Control board row: ID 3 is `SOURCE FIXED; OWNER RUNTIME NEEDED` after focused discovery/sort/failure coverage and finite progress-census closure. The final aggregate source/permanent gate passed; exact-SHA candidate-source preparation is eligible, while package build and owner runtime remain subject to their separate authorization gates. IDs 4 and 5 retain separate call-site and combined-source-scan conditions.
- Remediation report row: `docs/remediation/PR-321-reconciliation.md`, with exact source/test results and remaining owner runtime proof.
- Hunk classification: `TPM-PROGRESS-SCAN-COVERAGE-001` / PR #321 / owner IDs 3-5 and 29 / `TPM-PROGRESS-001` / `TPM-PROGRESS-002` / `TPM-TRACE-001`.
- Changelog and user docs: no new feature or release-version change. The active RC8 changelog records discovery/validation progress; README.md and the packaged README correct the user-added-image description and dynamic gallery-index range; architecture documents the open progress row through sorting.

## 9. Permanent procedure IDs affected

- `TPM-PROGRESS-001`: known-total progress behavior verified at real call sites.
- `TPM-PROGRESS-002`: each named scan path explicitly inventoried.
- `TPM-PROGRESS-003`: production source contains no PowerShell progress panel.
- `TPM-TRACE-001`: every source hunk mapped to this contract, IDs 3-5, PR #321.

## 10. Runtime smoke checklist

- Exact packaged behavior: run AutoSync with multiple source ZIPs and GPU Fix/Health Check with a non-trivial GameProfiles catalog; verify compact progress advances and closes without a blue PowerShell panel.
- Exercise the Crosshair profile-planning scan and optional HyperSpin export scan with a nontrivial UserProfiles directory; each compact row must advance and close while outputs remain unchanged except the selected operation.
- Required source/package identity: exact pushed branch SHA and rebuilt package SHA.
- Evidence artifacts: operator screen capture/logs and exact package/source identity.
- Owner/runtime authorization: required; no owner smoke is authorized by this slice.

## 11. Stop condition

- Stop when focused call-site tests, the complete script-wide progress inventory, final source gates, report status, hunk mapping, and permanent procedure evidence are complete. The Crosshairs discovery/sort path is now covered; owner runtime remains a separate release blocker.

## 12. Forbidden actions

No unrelated cleanup, broad rewrite, package, release, certification, wiki update, ARCADE work, owner smoke, or runtime mutation.

## 13. Commit/package authorization status

- Commit authorized: No; explicit authorization required.
- Package authorized: No.
- Release/certification authorized: No.
## 14. Additional ID 3 source re-audit -- BepInEx progress

- Exact failure: `Invoke-BepInExUpdateCheck` scans registered profile paths and inspects eligible installations without compact progress. `Invoke-TpmTransactionalTreePromote` performs known-total destination preflight, file promotion/verification, and rollback loops without compact progress. The existing table's BepInEx progress claim is not supported by those call sites.
- Expected behavior: show bounded TPM compact progress for BepInEx path preflight and installation inspection, plus known-total progress for destination preflight, per-file promotion/verification, and rollback. Progress is status only; it does not change selected-game order, release-query/download behavior, safety checks, backup-before-write, destination identity checks, transaction results, or rollback ordering.
- Forbidden regressions: no path/game identifiers in progress labels; no new percentage for opaque per-item work; no bypass of existing preflight, backup, hash verification, transactional promotion, or rollback.
- Focused tests before/with implementation: `reports compact progress while checking each BepInEx path before release query, prompt, or download`; `reports per-file BepInEx promotion progress and preserves promoted output`; existing `restores the exact destination when staged promotion validation fails`.
- Runtime proof: exact authorized candidate package must exercise BepInEx path preflight and a multi-file deployment/rollback case; capture package/source identity and operation output. No package or runtime authorization is implied by this source contract.
- Stop condition: stop if progress changes a BepInEx decision, deployment order, destination, backup, transaction result, or rollback outcome. This source audit is complete. ID 3 is `SOURCE FIXED; OWNER RUNTIME NEEDED` following Crosshairs coverage and census closure; the final aggregate source/permanent gate passed. Exact-SHA candidate-source preparation may proceed, but package and owner-runtime gates remain separate. Owner runtime remains mandatory.
- Hunk mapping: `Invoke-BepInExUpdateCheck` and `Invoke-TpmTransactionalTreePromote` source/tests; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.
## 15. Additional ID 3 source re-audit -- live profile and LaunchBox paths

- Exact uncovered paths: AutoSync's top-level UserProfiles backup `Copy-Item -Recurse`; the live `Invoke-RestoreBackupLegacy` path, including both failure rollback branches; `Export-LaunchBoxXml`, `Backup-LaunchBoxFiles`, and `Invoke-RestoreLaunchBoxBackup`; `Register-Games` existing-profile/code and GamePath-index scans; `Invoke-FFBPluginSetup` profile matching and deployment planning; `Backup-PostgresDatabases` profile discovery; and `Invoke-PostgresGameSetup` per-profile preflight, database creation, profile mutation, and final verification loops.
- Expected behavior: expose known-total compact progress for top-level backup/restore work, LaunchBox profile/file loops, registration profile indexing, FFB-plugin profile planning, PostgreSQL backup profile discovery, and every PostgreSQL setup profile/database plan loop. Factor the shared legacy restore rollback removal/copy loop so both failure branches report known-total work. Keep recursive copies explicitly at their top-level item boundary; do not invent descendant or byte percentages. PostgreSQL restore remains structured workflow-step status.
- Forbidden regressions: preserve backup-before-mutation and abort-on-backup-failure, restore/delete/rollback ordering and error accounting, LaunchBox export results and XML bytes, registration match/order rules, FFB candidate/accounting rules, PostgreSQL database selection and backup result classification, and all existing prompt/network behavior.
- Focused behavior tests before/with implementation: `preserves AutoSync UserProfiles backup contents while reporting each top-level copy`; `reports progress for live UserProfiles restore phases and preserves restored files`; direct rollback-helper behavior test verifies restored bytes, FullBackup preservation, and per-item progress; `reports progress for LaunchBox export and restore while preserving outputs`; `reports progress while indexing existing UserProfiles during registration`; `reports FFB plugin profile-planning progress without changing accounting`; `reports PostgreSQL backup profile-scan progress without changing failure results`; `rolls back setup-created databases when a coupled profile write fails` checks preflight, database, and mutation progress, with successful read-back progress asserted by an integration test.
- Runtime proof: exact authorized candidate package must exercise AutoSync backup, UserProfiles restore, LaunchBox export/restore, registration, FFB plugin planning, PostgreSQL backup, and PostgreSQL setup; record exact package/source identity and operation results. This source contract does not authorize package creation, owner smoke, ARCADE work, or release.
- Stop condition: stop if operation ordering, profile selection, backups, bytes, restore outcomes, candidate accounting, or database results change. These live-profile/LaunchBox paths and the user-extensible Crosshairs discovery/sort path are covered; the final aggregate source gates must pass before candidate preparation.
- Hunk mapping: AutoSync UserProfiles backup helper/top-level call, `Invoke-RestoreBackupLegacy`, LaunchBox export/backup/restore, `Register-Games`, `Invoke-FFBPluginSetup`, `Backup-PostgresDatabases`, and `Invoke-PostgresGameSetup` source/tests; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 16. Additional ID 3 source re-audit -- FFB overlap safety snapshot

- Exact uncovered paths: `Disable-FFBBlasterForOverlap` performs a known-total target-profile preflight, creates and validates a recursive whole-UserProfiles safety snapshot, and restores it on failure; `Restore-FFBPluginDeploymentTransaction` restores that snapshot if later optional-plugin deployment/evidence handling fails. Recursive copies expose top-level item progress only.
- Expected behavior: report known-total progress for target-profile preflight, snapshot entries, backup verification, native-field update/read-back, and both rollback-copy paths. Recursive descendants remain represented by their top-level item only. Preserve all preflight, backup, ownership-switch, rollback, and error-result order.
- Focused behavior tests before/with implementation: native-overlap transition verifies preflight/snapshot/backup/native-switch progress; `reports progress while restoring a UserProfiles overlap snapshot` verifies restored bytes and per-entry rollback progress.
- Runtime proof: exact authorized candidate package must exercise native-to-plugin overlap selection and a forced post-backup failure/verified rollback; no runtime or release authorization is implied.
- Stop condition: stop if selected profile set, backup bytes, XML mutation, rollback outcome, or plugin deployment gate changes.
- Hunk mapping: `Disable-FFBBlasterForOverlap` and `Restore-FFBPluginDeploymentTransaction` source and overlap transition/rollback tests; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.


## 18. Additional ID 3 source re-audit -- Health Check profile backup

- Exact uncovered paths: `New-LibraryHealthProfileBackup` copies each registered XML profile before an explicit Library Health Check repair without compact progress; `Invoke-LibraryHealthCheck` scans registered profiles first for saved-path findings and again for optional setup coverage.
- Expected behavior: report the known-total backup copy loop and both read-only profile scans; preserve verified source/destination path checks, backup contents, findings, and fail-closed behavior before any profile write.
- Focused behavior test before/with implementation: extend the successful manual Health Check repair test to assert backup bytes and progress; the read-only Health Check fixture asserts both profile passes' findings and progress rows.
- Runtime proof: exact authorized candidate package must exercise manual repair with a verified backup and backup-copy failure before profile mutation, plus read-only Library Health on a multi-profile library; this does not authorize runtime or release actions.
- Stop condition: stop if backup location/content, path validation, findings, read-only state, failure handling, or repair write ordering changes.
- Hunk mapping: `New-LibraryHealthProfileBackup`, both `Invoke-LibraryHealthCheck` profile loops, and manual/read-only Health Check tests; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 19. Additional ID 3 source re-audit -- Control Propagation profile scans

- Exact uncovered paths: `Build-ArchetypePool` scans all UserProfiles XML to construct the source pool; `Invoke-ControlPropagationLegacy` then classifies each XML and may update it without compact progress; `Write-ControlsStatus` scans the profile library to emit the final control status report without compact progress.
- Expected behavior: report known-total per-profile progress in all three passes while preserving file order, pool/source matching, report accounting, status-file content, and all XML mutation semantics.
- Focused behavior tests before/with implementation: extend `uses an archetype match key only once per target profile` to assert known-total progress for the first two scans and preserve its binding/report assertions; add forced helper-failure tests proving `Build-ArchetypePool` and `Invoke-ControlPropagationLegacy` both close their rows; add a fixture-backed `Write-ControlsStatus` test asserting generated status content and known-total progress.
- Runtime proof: exact authorized candidate package must exercise Control Propagation with a multi-profile library and produce its status report; no package or runtime authorization is implied.
- Stop condition: stop if progress changes profile order, archetype selection, report classification, status output, or profile bytes.
- Hunk mapping: `Build-ArchetypePool`, `Invoke-ControlPropagationLegacy`, `Write-ControlsStatus`, and corresponding tests; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 20. Additional ID 3 source re-audit -- PostgreSQL rollback loops

- Exact uncovered paths: `Restore-PostgresProfileBackups` copies and hashes every profile backup; `Restore-PostgresSetupCreatedDatabases` rolls back each setup-created database and verifies absence.
- Expected behavior: report known-total per-file/per-database progress and close the progress row while preserving restore order, hash/state verification, error aggregation, and rollback results.
- Focused behavior tests before/with implementation: a fixture-backed profile-backup test verifies restored bytes and progress; `rolls back setup-created databases when a coupled profile write fails` verifies database rollback progress and the unchanged verified rollback result.
- Runtime proof: exact authorized candidate package must exercise PostgreSQL profile-write failure rollback; package/runtime authorization remains separate.
- Stop condition: stop if backup bytes, database rollback order, state verification, or final recovery classification changes.
- Hunk mapping: `Restore-PostgresProfileBackups`, `Restore-PostgresSetupCreatedDatabases`, and PostgreSQL rollback tests; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 21. Additional ID 3 source re-audit -- PostgreSQL database backups

- Exact uncovered paths: `Backup-PostgresDatabases` classifies each discovered database when `pg_dump.exe` is unavailable and invokes `pg_dump.exe` per database when available, without known-total per-database progress.
- Expected behavior: report known-total progress for both database-item loops; keep each native dump opaque between item boundaries and preserve failure classification, output validation, and credential-file cleanup.
- Focused behavior tests before/with implementation: fixture-backed missing-executable and successful multi-database backup tests assert per-database progress, preserved output bytes, and unchanged failure/results.
- Runtime proof: exact authorized candidate package must back up multiple existing PostgreSQL databases and show per-database status; no package/runtime authorization is implied.
- Stop condition: stop if database order, dump arguments, backup contents, failure details, or credential cleanup changes.
- Hunk mapping: `Backup-PostgresDatabases` source and database-backup tests; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.
## 22. Additional ID 3 source re-audit -- readiness action-item scan

- Exact uncovered path: `Get-ControlReadinessActionItems` scans every registered UserProfiles XML before filtering to catalog-backed readiness requirements and performing profile assessments, without compact progress.
- Expected behavior: report known-total per-profile progress through the complete scan while preserving sorted profile order, requirement filtering, assessment results, and returned action items.
- Focused behavior test before/with implementation: extend `surfaces registered abc with wizard complete and missing controls as not ready` to assert the existing readiness result and the known-total scan progress row.
- Runtime proof: exact authorized candidate package must exercise the onboarding handoff with registered profiles; no package/runtime authorization is implied.
- Stop condition: stop if action-item membership, assessment fields, returned ordering, or readiness summaries change.
- Hunk mapping: `Get-ControlReadinessActionItems` and its fixture-backed action-item test; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.
## 23. Additional ID 3 source re-audit -- LaunchBox direct writer

- Exact uncovered path: `Invoke-LaunchBoxDirectWrite` scans every registered profile separately for each requested LaunchBox platform while writing the profile entries, without per-profile progress.
- Expected behavior: report known-total progress for each platform scan while preserving platform/profile order, valid-game filtering, deduplication, saved XML contents, and result counts.
- Focused behavior test before/with implementation: add a fixture-backed direct-writer test that asserts generated LaunchBox game entry, result count, and progress closure for a platform scan.
- Runtime proof: exact authorized candidate package must export multiple profiles to one and two platforms; no package/runtime authorization is implied.
- Stop condition: stop if game entries, order, per-platform counts, backup boundary, or saved file set changes.
- Hunk mapping: `Invoke-LaunchBoxDirectWrite` and direct-writer integration test; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.
## 24. Additional ID 3 source re-audit -- preset profile-code membership scans

- Exact uncovered paths: ReShade's per-game preset validation and dgVoodoo2's per-game configuration validation each enumerate every registered UserProfiles XML to build a case-insensitive membership set when custom override files exist. The shared helper also materializes/sorts the full XML array before its existing known-total progress.
- Expected behavior: stream unknown-total compact progress while discovering direct-child XML files, then report the existing known-total profile-code scan; preserve BaseName sorting, `FullBackup` exclusion, ordinal-ignore-case lookup, and returned membership.
- Focused behavior test before/with implementation: extend the fixture-backed helper test to assert exact code membership, case-insensitivity, `FullBackup` exclusion, unknown-total discovery advancement/closure, and known-total scan completion.
- Runtime proof: exact authorized candidate package must validate custom overrides in both ReShade and dgVoodoo2 setup; no package/runtime authorization is implied.
- Stop condition: stop if accepted override codes, case handling, or setup behavior changes.
- Hunk mapping: shared profile-code helper, ReShade/dgVoodoo2 preset validation call sites, and helper fixture test; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.
## 25. Additional ID 3 source re-audit -- PostgreSQL setup requirement scan

- Exact uncovered path: the PostgreSQL setup menu scans every registered profile to count games requiring PostgreSQL while an outer workflow step only reports the stage; no per-profile progress or closed compact row is emitted.
- Expected behavior: report each profile against the known total and close the scan row while preserving fail-closed classification and the exact required-game count.
- Focused behavior test before/with implementation: add a fixture-backed requirement-scan helper test with required, non-required, and malformed profiles, asserting counts, blocked status, and known-total progress closure.
- Runtime proof: exact authorized candidate package must show the requirement scan before PostgreSQL setup; no package/runtime authorization is implied.
- Stop condition: stop if profile read failures cease to block setup or the required-game count changes.
- Hunk mapping: PostgreSQL requirement-scan helper, top-level setup caller, and helper regression test; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.
## 26. Additional ID 3 source re-audit -- Library Health and compatibility scans

- Exact uncovered paths: `Invoke-LibraryHealthCheck` classifies every profile's saved path and then scans each profile again for optional setup coverage; `Get-CompatibilityWarnings` scans the profile library once for compatibility checks and again for BIOS/component grouping when a TeknoParrot root is supplied.
- Expected behavior: each pass reports known-total per-profile progress and closes its row while preserving findings, read-only behavior, logs, and compatibility result grouping.
- Focused behavior tests before/with implementation: extend the existing read-only Library Health test and a BIOS compatibility test to assert the findings and progress-row closure for every applicable pass.
- Runtime proof: exact authorized candidate package must run Library Health and compatibility checks on a multi-profile library; no package/runtime authorization is implied.
- Stop condition: stop if the warning sets, order-sensitive accounting, or read-only state changes.
- Hunk mapping: both profile passes in `Invoke-LibraryHealthCheck`, both `Get-CompatibilityWarnings` profile loops, and focused fixture tests; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 27. Additional ID 3 source re-audit -- startup notes and thumbnail profile scans

- Exact uncovered paths: `Get-GameSetupNotes` builds a registered-code membership set; `Invoke-ThumbnailDownload` indexes registered profile codes, validates/copies custom PNGs, and classifies missing icons across the whole profile library without compact progress.
- Expected behavior: report the known-total membership, custom-file, and missing-icon classification passes while preserving case-insensitive code matching, custom-file classification/copying, existing-icon counts, and transfer selection.
- Focused behavior tests before/with implementation: fixture-backed setup-note membership and thumbnail classification/copy tests assert preserved output/files and progress closure.
- Runtime proof: exact authorized candidate package must run startup notes and custom-thumbnail/missing-icon checks over multiple profiles; no package/runtime authorization is implied.
- Stop condition: stop if user-facing notes, custom-image acceptance/copying, missing-icon selection, or network request set changes.
- Hunk mapping: `Get-GameSetupNotes`, `Invoke-ThumbnailDownload`, and fixture-backed tests; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.
## 28. Additional ID 3 source re-audit -- dgVoodoo2 deployment preflight

- Exact uncovered path: after game selection, `Invoke-DgVoodoo2Setup` re-reads, revalidates, and builds file operations for every selected profile before starting its transactional write, without per-profile preflight progress.
- Expected behavior: report each selected profile against the known total and close the row while preserving selected-profile order, path revalidation, per-game failure classification, and transaction operation construction.
- Focused behavior test before/with implementation: add a fixture-backed successful one-profile setup test asserting deployed DLL bytes, result count, and preflight progress closure.
- Runtime proof: exact authorized candidate package must run dgVoodoo2 setup over multiple selected profiles and observe preflight before transactional deployment; no package/runtime authorization is implied.
- Stop condition: stop if deployment operations, file bytes, selected targets, or failure classification changes.
- Hunk mapping: `Invoke-DgVoodoo2Setup` deployment preflight and fixture-backed deployment test; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.
## 29. Additional ID 3 source re-audit -- ReShade bulk conflict scan

- Exact uncovered path: `Invoke-ReShadeSetupLegacy` scans each selected game for an existing trusted profile conflict before the bulk-change decision; the scan may invoke ownership/state reads without per-game progress.
- Expected behavior: report a known-total row for the selected-game conflict scan and close it while preserving conflict membership, ownership state, and all subsequent A/K/S/B outcomes.
- Focused behavior test before/with implementation: extend the selected-set ReShade integration test to assert its unchanged selected/changed/skipped/failed results and conflict-scan progress closure.
- Runtime proof: exact authorized candidate package must exercise multi-game bulk ReShade selection with a prior trusted profile on one game; no package/runtime authorization is implied.
- Stop condition: stop if conflict detection or bulk-choice behavior changes.
- Hunk mapping: `Invoke-ReShadeSetupLegacy` bulk conflict scan and selected-set integration test; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.
## 30. Additional ID 3 source re-audit -- AutoSync directory manifests

- Exact uncovered path: `Get-TpmDirectoryManifest` recursively enumerates and hashes every entry in target/staging directories during AutoSync preflight, promotion verification, and rollback verification without visible per-entry progress.
- Expected behavior: report unknown-total entry progress while the manifest is traversed and close the compact row on success or failure; preserve sorted manifest contents, hashes, reparse rejection, and AutoSync transaction decisions.
- Focused behavior test before/with implementation: extend the directory-manifest fixture to assert unknown-total entry advancement and row closure while retaining ZIP inventory comparison and tamper detection.
- Runtime proof: exact authorized candidate package must run multi-file AutoSync staging/promotion and a verified rollback; no package/runtime authorization is implied.
- Stop condition: stop if manifest contents, SHA-256 values, failure state, or AutoSync transaction outcome changes.
- Hunk mapping: `Get-TpmDirectoryManifest` and its directory/ZIP inventory fixture; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.
## 31. Additional ID 3 source re-audit -- AutoSync ZIP inventory hashing

- Exact uncovered path: `Get-TpmAutoSyncZipInventory` reads and SHA-256 hashes every ZIP entry before the AutoSync staging transaction without compact progress.
- Expected behavior: report each archive entry against the known archive-entry total and close the row in `finally`; preserve path validation, duplicate/collision rejection, inventory ordering, byte totals, and entry hashes.
- Focused behavior test before/with implementation: extend the fixture-backed ZIP/directory inventory test to assert the known-total inventory row and completion alongside the expected inventory match and tamper rejection.
- Runtime proof: exact authorized candidate package must inventory and synchronize a multi-entry ZIP; no package/runtime authorization is implied.
- Stop condition: stop if the manifest entries, hashes, validation failures, or AutoSync transaction result changes.
- Hunk mapping: `Get-TpmAutoSyncZipInventory` and directory/ZIP inventory fixture; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.
## 32. Additional ID 3 source re-audit -- BepInEx recursive tree scans

- Exact uncovered paths: `Test-BepInExExistingTreeSafe` recursively validates installed-tree descendants; `Get-BepInExStagedFiles` validates every staged descendant and then classifies staged files; `Test-BepInExBackupEntry` enumerates and hashes directory backup contents.
- Expected behavior: report known-total progress for staged tree/file validation and backup verification, and unknown-total progress while checking installed descendants; close each row on all exits without weakening reparse/path safety or byte/hash verification.
- Focused behavior test before/with implementation: fixture-backed multi-file staged-file and backup verification tests assert returned paths/verified bytes and progress advancement/closure; installed-tree safety test asserts a safe tree remains accepted and reports progress.
- Runtime proof: exact authorized candidate package must exercise a multi-file BepInEx install/update and rollback; no package/runtime authorization is implied.
- Stop condition: stop if path safety, accepted staged files, backup hashes, or deployment/rollback results change.
- Hunk mapping: `Test-BepInExExistingTreeSafe`, `Get-BepInExStagedFiles`, `Test-BepInExBackupEntry`, and focused fixture tests; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.
## 33. Additional ID 3 source re-audit -- nested ZIP source fallback

- Exact uncovered paths: `Select-GamesInteractive` and `Invoke-AutoSync` each enumerate every immediate ZIP-source subdirectory and count contained ZIPs when the selected source root itself contains none.
- Expected behavior: share a known-total per-subdirectory scan that closes its row, preserving exact one-level search depth, ZIP counts, path ordering, and guidance text.
- Focused behavior test before/with implementation: fixture-backed summary test creates multiple direct child folders with and without ZIPs and asserts exact counts/order plus progress closure.
- Runtime proof: exact authorized candidate package must exercise the no-root-ZIP guidance in both source selection and AutoSync; no package/runtime authorization is implied.
- Stop condition: stop if nested search depth, candidate ordering, ZIP counts, or fallback behavior changes.
- Hunk mapping: shared immediate-subdirectory ZIP summary helper, both callers, and fixture test; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.
## 34. Additional ID 3 source re-audit -- dgVoodoo2 ZIP entry scan

- Exact uncovered path: `Expand-DgVoodoo2Zip` enumerates every downloaded ZIP entry to index the archive before selecting six required DLL/config files.
- Expected behavior: report known-total archive-entry progress and close the row while preserving normalized path mapping, layout-drift rejection, extraction order, and transactional destination safety.
- Focused behavior test before/with implementation: extend the valid six-file extraction fixture to assert archive scan progress alongside exact extracted bytes; retain the layout-drift and failure rollback tests.
- Runtime proof: exact authorized candidate package must download, index, and deploy the official dgVoodoo2 archive; no package/runtime authorization is implied.
- Stop condition: stop if entry matching, layout validation, extracted bytes, or rollback behavior changes.
- Hunk mapping: `Expand-DgVoodoo2Zip` archive lookup and valid six-file fixture; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 35. Additional ID 3 source re-audit -- LaunchBox backup menu scan

- Exact uncovered paths: `Invoke-RestoreLaunchBoxBackup` enumerates the backup root before sorting, recursively counts each candidate backup for the menu, and materializes the selected backup's restore sources before progress.
- Expected behavior: stream unknown-total backup-folder discovery, report known-total progress across sorted folders, and stream unknown-total per-file discovery during each recursive count and selected restore-source scan, preserving recency order, displayed counts, menu text, restore selection, and file-copy order.
- Focused behavior test before/with implementation: extend the LaunchBox restore fixture with multiple backups and nested files; assert exact folder/per-file discovery and restore totals, closure, displayed counts, and unchanged restored bytes.
- Runtime proof: exact authorized candidate package must present the restore menu for multiple LaunchBox backups and restore the selected snapshot; no package/runtime authorization is implied.
- Stop condition: stop if backup ordering, displayed counts, choice mapping, or restored bytes change.
- Hunk mapping: `Invoke-RestoreLaunchBoxBackup` backup-root enumeration, menu counting, selected restore-source discovery, and fixture-backed menu/restore tests; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 36. Additional ID 3 source re-audit -- BepInEx streaming discovery

- Exact uncovered paths: `Test-BepInExExistingTreeSafe`, `Get-BepInExStagedFiles`, and `Test-BepInExBackupEntry` materialize recursive `Get-ChildItem` results before emitting progress; staged-file classification and backup source/destination file inventories also complete enumeration before their known-total rows.
- Expected behavior: stream each recursive discovery with unknown-total progress as entries arrive, preserve known-total validation/hash rows after enumeration, and close each row on success or error without weakening reparse, containment, ordering, or byte-equality checks.
- Focused behavior test before/with implementation: extend the multi-file installed/staged/backup fixture to assert per-entry unknown-total discovery advancement, known-total classification/verification counts, fail-closed reparse handling, and unchanged staged paths/bytes.
- Runtime proof: exact authorized candidate package must scan safe and reparse-containing multi-file BepInEx trees and complete update/rollback; no package/runtime authorization is implied.
- Stop condition: stop if accepted paths, traversal safety, verification results, cleanup, or deployment/rollback behavior changes.
- Hunk mapping: BepInEx installed-tree, staged-tree/file, backup-tree/file discovery and focused fixtures; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 37. Additional ID 3 source re-audit -- BepInEx staging cleanup

- Exact uncovered path: `Remove-BepInExStagingDirectory` traverses every staging descendant before deleting each file and directory, without visible scan or deletion progress.
- Expected behavior: stream unknown-total descendant safety checks and report known-total file and reverse-directory deletion progress, closing each row on success or failure while preserving controlled-root containment, reparse rejection, immediate pre-delete revalidation, deletion order, and residue reporting.
- Focused behavior test before/with implementation: add an isolated controlled-temp-tree fixture asserting exact discovery/file/directory counts, successful removal, and no residual tree; retain refusal tests for paths outside the controlled root.
- Runtime proof: exact authorized candidate package must clean nested staging trees and refuse unsafe paths; no package/runtime authorization is implied.
- Stop condition: stop if any path outside the exact staging tree can be removed, any reparse descendant is followed, cleanup order changes, or failure evidence/residue is lost.
- Hunk mapping: `Remove-BepInExStagingDirectory` traversal and deletion loops plus isolated cleanup fixture; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 38. Additional ID 3 source re-audit -- ReShade embedded installer scans

- Exact uncovered paths: `Expand-ReShadeSelfExtractingArchive` scans every installer byte for embedded PK headers, tests candidate suffixes in order, and indexes each candidate archive's entries before staging the first candidate with both required DLLs.
- Expected behavior: report known-total signature-byte scan progress at bounded intervals, each candidate against the known signature-offset total, and each opened archive entry against its known total; close rows on failure while preserving first-valid-candidate ordering, archive disposal, staging cleanup, and destination rollback.
- Focused behavior test before/with implementation: extend valid and decoy-signature fixtures to assert exact signature/candidate/entry progress totals and the unchanged extracted DLL bytes; retain all missing-entry and transactional-failure cases.
- Runtime proof: exact authorized candidate package must extract a valid installer, skip the invalid decoy, and preserve target bytes on failures; no package/runtime authorization is implied.
- Stop condition: stop if candidate ordering, accepted entry names, extracted bytes, resource disposal, or destination/rollback state changes.
- Hunk mapping: `Expand-ReShadeSelfExtractingArchive` signature, candidate, and ZIP-entry scans plus valid/decoy fixtures; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 39. Additional ID 3 source re-audit -- BepInEx recursive copy/removal

- Exact uncovered paths: `New-BepInExUpdateBackup` and `Restore-BepInExUpdateBackup` use recursive `Copy-Item` for fixed top-level backup entries, and `Remove-BepInExFixedTree` recursively removes fixed top-level install entries without phase progress.
- Expected behavior: report every top-level entry against the known fixed/listed total while each recursive copy/removal is active, close rows on failure, and preserve backup verification, path/reparse checks, restore order, and reset safety.
- Focused behavior test before/with implementation: extend backup verification and reset/restore fixtures to assert unchanged files, exact per-entry progress totals, and closure after injected failures.
- Runtime proof: exact authorized candidate package must complete BepInEx update/reset/rollback on an authorized fixture install; no package/runtime authorization is implied.
- Stop condition: stop if backup bytes, reset targets, restoration ordering, path safety, or rollback state changes.
- Hunk mapping: `New-BepInExUpdateBackup`, `Restore-BepInExUpdateBackup`, `Remove-BepInExFixedTree`, and fixture-backed tests; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 40. Additional ID 3 source re-audit -- support staging recursive cleanup

- Exact uncovered paths: `Remove-TpmSupportOwnedDirectoryTree` materializes recursive descendants during cleanup of the diagnostics and metadata stage trees, while `Remove-TpmSupportOwnedEntry` has no per-entry removal status.
- Expected behavior: stream unknown-total descendant discovery as children are enumerated and report per-entry removal status through the owned-handle recursion; close both rows on success or failure and preserve handle-identity, canonical-root, reparse, and residue checks.
- Focused behavior test before/with implementation: add a nested owned-stage fixture asserting exact discovery/removal advancement, completion closure, complete stage removal, and retained unsafe-junction refusal with closed rows.
- Runtime proof: exact authorized candidate package must clean a nested support package stage and preserve/flag replaced-path residue; no package/runtime authorization is implied.
- Stop condition: stop if handle ownership checks, child order, external-path refusal, or cleanup-residue behavior changes.
- Hunk mapping: `Remove-TpmSupportOwnedDirectoryTree`, `Remove-TpmSupportOwnedEntry`, `Remove-TpmSupportStageDirectory`, and nested cleanup fixtures; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 41. Additional ID 3 source re-audit -- PostgreSQL partial-install cleanup

- Exact uncovered path: `Remove-PostgresPartialInstall` may scan the installed-product registry, wait for a matched MSI uninstall, recursively remove the fixed install directory and stale user-profile directories, and enumerate/delete PostgreSQL profile registry keys without user-visible progress.
- Expected behavior: advance unknown-total cleanup progress while streaming installed-product/profile registry enumeration and before opaque MSI/filesystem work; advance as matched service/profile items are processed; close the status on success or failure without changing exact-install matching, cleanup targets, or error policy.
- Focused behavior test before/with implementation: mock external process/service/registry/filesystem commands, assert exact streamed enumeration/item advancement, closure on successful cleanup and an injected MSI failure, and verify unrelated uninstall records remain untouched.
- Runtime proof: exact authorized candidate package must remove only its own partial install and stale PostgreSQL profile state; no package/runtime authorization is implied.
- Stop condition: stop if any unrelated install/service/profile is touched or the current cleanup error policy changes.
- Hunk mapping: `Remove-PostgresPartialInstall` and its mocked cleanup fixture; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 42. Additional ID 3 source re-audit -- AutoSync inventory comparison

- Exact uncovered path: `Test-TpmDirectoryAgainstZipInventory` builds dictionaries from complete ZIP/directory inventories and compares every entry without progress; AutoSync invokes the check repeatedly during preflight, staging, promotion, and final verification.
- Expected behavior: report known-total progress while indexing both prebuilt inventories and comparing ZIP paths, closing both rows on success or any early mismatch without changing comparison results.
- Focused behavior test before/with implementation: extend the directory/ZIP fixture to assert exact indexing/comparison advancement and closure for both matching and hash-mismatch outcomes.
- Runtime proof: exact authorized candidate package must preserve existing AutoSync no-change, stage, promotion, and final-verification decisions; no package/runtime authorization is implied.
- Stop condition: stop if any inventory match decision, path acceptance, transaction outcome, or source/target byte changes.
- Hunk mapping: `Test-TpmDirectoryAgainstZipInventory` and the fixture-backed AutoSync directory/ZIP inventory tests; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 43. Additional ID 3 source re-audit -- startup DAT and notes parsing

- Exact uncovered paths: startup `Build-DatIndexFromStream` parses large XML DATs and `Build-GameNotesIndexFromStream` iterates notes streams before the main menu without parser progress; disk and ZIP wrappers share these stream parsers.
- Expected behavior: show an unknown-total status before parsing and advance at a bounded record/line interval; close the row on success or parse failure without changing stream ownership, parser results, or resource disposal.
- Focused behavior test before/with implementation: extend the DAT stream fixture past the progress interval and add a notes stream fixture; assert indexed content, exact advancement, and completion closure.
- Runtime proof: exact authorized candidate package must complete startup loading for direct and ZIP-backed DAT/notes sources without changing profile matching; no package/runtime authorization is implied.
- Stop condition: stop if parser output, stream/reader disposal, error fallback, startup source precedence, or match results change.
- Hunk mapping: `Build-DatIndexFromStream`, `Build-GameNotesIndexFromStream`, disk/ZIP wrappers, and stream-parser fixtures; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.
## 44. Additional ID 3 source re-audit -- UserProfiles and PostgreSQL restore menus

- Exact uncovered paths: `Invoke-RestoreBackupLegacy` enumerates and sorts the UserProfiles backup root, counts direct files in each candidate for the menu, and enumerates selected XML profiles before restore; `Invoke-RestorePostgresBackup` enumerates/sorts its backup root, scans each candidate's direct `.backup` files for menu counts/names, and rescans the selected backup before restore. The actual UserProfiles snapshot/removal/copy loops and PostgreSQL transaction workflow already have progress/status coverage.
- Expected behavior: stream unknown-total backup-folder and per-candidate file discovery with completion closure; report known-total menu indexing; stream selected-source discovery before validation/confirmation. Preserve backup recency/order, direct-child count semantics, displayed database/profile names, choice mapping, and all restore/rollback decisions.
- Focused behavior test before/with implementation: extend the UserProfiles and PostgreSQL restore-menu fixtures to include multiple ordered backup folders and multiple candidate files; assert exact discovery/menu/selected-source progress, labels and ordering, closure, cancellation/decline before mutation, and unchanged restored bytes/results where applicable.
- Runtime proof: exact authorized candidate package must present multiple UserProfiles and PostgreSQL restore backups in the existing order and complete selected restores safely; no package/runtime authorization is implied.
- Stop condition: stop if menu ordering, direct-child counting, displayed names, selection mapping, restore bytes/database transaction, confirmation boundary, or rollback behavior changes.
- Hunk mapping: `Invoke-RestoreBackupLegacy`, `Invoke-RestorePostgresBackup`, restore-menu fixtures; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 45. Additional ID 3 source re-audit -- AutoSync source ZIP size preflight

- Exact uncovered path: the AutoSync staging-space preflight enumerates every top-level source ZIP in `zipSource` through `Get-ChildItem | Measure-Object -Property Length -Sum` before reporting free space, without progress.
- Expected behavior: stream the same top-level `*.zip` enumeration with unknown-total progress, accumulate the exact byte total used by the existing free-space estimate, and close the row on success or failure without changing path filtering, low-space decisions, unattended behavior, or error fallback.
- Focused behavior test before/with implementation: fixture a directory containing multiple `.zip` files and an unrelated file; assert exact byte sum, unknown-total per-file advancement, and closure, including the empty-directory result.
- Runtime proof: exact authorized candidate package must show the AutoSync staging-space preflight for a populated and empty source folder and preserve the existing threshold decision; no package/runtime authorization is implied.
- Stop condition: stop if any non-ZIP file affects the sum, the exact summed bytes/threshold decision changes, or preflight error handling changes.
- Hunk mapping: AutoSync ZIP source byte-total helper and top-level preflight call, helper behavior fixture; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 46. Additional ID 3 source re-audit -- ZIP subfolder summary enumeration

- Exact uncovered path: `Get-TpmImmediateZipSubdirectorySummary` materializes immediate source subdirectories before status, then counts all `*.zip` entries in each candidate folder with an unreported `Get-ChildItem` enumeration.
- Expected behavior: stream unknown-total source-subdirectory discovery and per-folder ZIP-entry counting with completion closure; retain the known-total directory summary pass and preserve one-level depth, source enumeration order, matching `*.zip` behavior, and returned path/count pairs.
- Focused behavior test before/with implementation: extend the three-folder fixture with multiple ZIPs, an empty folder, and an unrelated file; assert exact discovery/count advancement, closure, and unchanged summary entries.
- Runtime proof: exact authorized candidate package must present the existing immediate-subfolder summary for empty-top-level-ZIP sources without changing AutoSync/selection routing; no package/runtime authorization is implied.
- Stop condition: stop if folder depth, `*.zip` inclusion semantics, summary order/counts, or no-top-level-ZIP routing changes.
- Hunk mapping: `Get-TpmImmediateZipSubdirectorySummary` and its fixture-backed selector test; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.
## 47. Additional ID 3 source re-audit -- AutoSync source ZIP discovery

- Exact uncovered paths: `Select-GamesInteractive` and both branches of `Select-GamesInteractiveCombined` materialize and sort top-level source ZIP arrays before the existing known-total picker classification progress; `Invoke-AutoSync` separately materializes its top-level `*.zip` processing list before its per-ZIP work.
- Expected behavior: stream unknown-total compact progress while discovering source ZIP entries at each call site; preserve picker exclusion of `!TeknoParrot Collection*`, BaseName sort order, combined-source separation, `Invoke-AutoSync` provider order, ZIP filtering, selection outcomes, and extraction behavior.
- Forbidden regressions: no changed picker menu/order, selected names, source routing, extraction order, sync state, byte accounting, or failure handling; no new percentage for unknown totals.
- Focused behavior tests before/with implementation: extend the real single- and combined-picker progress fixtures to assert both discovery closure and existing classification/selection behavior; extend an `Invoke-AutoSync` transaction fixture to assert initial source-list discovery progress alongside the existing extracted output and transaction result.
- Runtime proof: exact authorized candidate package must exercise the single-source picker, combined-source picker, and AutoSync execution against multi-ZIP sources; this contract does not authorize package creation or owner runtime.
- Stop condition: stop if discovery changes source membership, reserved collection exclusion, order, picker choices, transaction result, or installed output.
- Hunk mapping: shared top-level ZIP discovery helper, both AutoSync pickers, `Invoke-AutoSync`, and integration tests; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.
## 48. Additional ID 3 source re-audit -- UserProfiles backup root discovery

- Exact uncovered paths: `Get-TpmUserProfilesBackupManifest` materializes and sorts the direct UserProfiles root entries before its recursive descendant-discovery status; `Copy-TpmAutoSyncUserProfilesBackup` materializes the direct entries before its known-total copy loop. The recursive manifest work and top-level copy loop already report per-item progress after enumeration.
- Expected behavior: stream unknown-total progress while discovering direct root entries, then retain existing sort/ordering, recursive hashing, known-total top-level copy status, backup contents, and exclusion of `FullBackup`.
- Forbidden regressions: no change to manifest membership/order/hashes, recursive traversal, backup destination contents, error propagation, or copy boundary.
- Focused behavior tests before/with implementation: extend the real manifest fixture and AutoSync top-level-copy fixture to assert unknown-total discovery advancement/closure alongside their exact manifest/backup output assertions.
- Runtime proof: exact authorized candidate package must exercise verified UserProfiles backup and AutoSync safety backup on a populated profile library; this contract does not authorize package creation or runtime smoke.
- Stop condition: stop if manifest entries/hashes, copied paths/bytes, FullBackup handling, backup-before-mutation, or failure behavior changes.
- Hunk mapping: `Get-TpmUserProfilesBackupManifest`, `Copy-TpmAutoSyncUserProfilesBackup`, and their fixture-backed tests; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.
## 49. Additional ID 3 source re-audit -- registered-game picker discovery

- Exact uncovered paths: `Select-RegisteredGamesInteractive` and `Select-DgVoodoo2GamesInteractive` materialize/sort direct UserProfiles XML arrays before their first picker output or progress update.
- Expected behavior: stream unknown-total progress while discovering candidate XML files, then preserve `FullBackup` exclusion, BaseName ordering, all-game/list selection semantics, pagination, and empty-library behavior.
- Forbidden regressions: no change to candidate membership/order, selection mapping, picker prompts, or ReShade/dgVoodoo2 routing.
- Focused behavior tests before/with implementation: invoke each picker with fixture XML files and mocked `Read-TpmChoice`/`Read-HostSafe`; assert selected profile names, ordering, unknown-total updates, and completion.
- Runtime proof: exact authorized candidate package must exercise ReShade and dgVoodoo2 multi-profile pickers; no package/runtime authorization is implied.
- Stop condition: stop if candidate set/order, selected profiles, picker prompts, or setup routing changes.
- Hunk mapping: both registered-game picker functions and their fixture-backed tests; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.
## 50. Additional ID 3 source re-audit -- throughput ZIP source selection

- Exact uncovered paths: `Measure-PathThroughput` sorts every top-level source `*.zip` by length and selects the largest file before any progress/status; `Measure-PathWriteThroughput` writes 10 MB in fixed chunks without known-total status.
- Expected behavior: stream unknown-total progress while discovering ZIP candidates and known-total progress during both selected sample-read and fixed-size test-write loops; preserve exact descending-length selection, the 20 MB/10 MB limits, throughput math, temporary-file cleanup, and null/error behavior.
- Forbidden regressions: no change to candidate filtering, largest-file selection, throughput calculation, sample sizes, file-handle disposal, temp-file cleanup, or failure behavior.
- Focused behavior test before/with implementation: fixture multiple ZIP files with distinct lengths and a non-ZIP file; assert largest-candidate selection plus discovery/sample-read progress; exercise the 10 MB write and assert known-total byte advancement, completion, and temporary-file removal.
- Runtime proof: exact authorized candidate package must run the existing throughput estimate on a populated network-source path; no package/runtime authorization is implied.
- Stop condition: stop if candidate membership, selected largest file, calculated result, stream disposal, or error fallback changes.
- Hunk mapping: `Get-TpmLargestZipSourceFile`, `Measure-PathThroughput`, `Measure-PathWriteThroughput`, and their fixture-backed tests; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.
## 51. Additional ID 3 source re-audit -- directory emptiness probes

- Exact uncovered paths: `Test-ExtractedFolderHasContent` counts every child with `Measure-Object`; migration and transactional rollback cleanup use full `Get-ChildItem` arrays solely to decide whether a directory is empty; `Ensure-TeknoParrotProfilesReady` repeatedly counts every `GameProfiles` XML during its readiness wait.
- Expected behavior: short-circuit each existence/emptiness probe after the first matching item; preserve empty/nonempty decisions, `-Force`/`*.xml -File` filters, cleanup boundaries, wait cadence, and error handling.
- Forbidden regressions: no removal of nonempty/user-owned paths, no changes to backup/rollback order, readiness timeout, or startup prompts.
- Focused behavior tests before/with implementation: test missing/empty/nonempty directory probe results; rerun existing transaction rollback tests that remove newly created directories and a fixture readiness test proving profile detection still resumes.
- Runtime proof: exact authorized candidate package must exercise cleanup rollback with empty and occupied directories plus first-run profile readiness; no package/runtime authorization is implied.
- Stop condition: stop if a probe changes an empty/nonempty result, readiness branch, cleanup target, or rollback outcome.
- Hunk mapping: `Test-ExtractedFolderHasContent`, transactional migration/file/tree rollback emptiness checks, readiness XML probes, and their fixture tests; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.
## 52. Additional ID 3 source re-audit -- registered-profile inventory discovery

- Exact uncovered paths: direct UserProfiles XML discovery is materialized before existing known-total profile work or workflow scanning in `Get-TpmReShadeRemovalScan`, `Get-PostgresReinitializePlansFromProfiles`, `New-PostgresRecoveryBackup`, `Invoke-CursorHideSetup`, `Invoke-FFBBlasterSetup`, `Invoke-BepInExUpdateCheckLegacy`, `Backup-PostgresDatabases`, `Invoke-DgVoodoo2Setup`, `Invoke-PostgresGameSetup`, `Invoke-FFBPluginSetup`, `Disable-FFBBlasterForOverlap`, `New-LibraryHealthProfileBackup`, `Invoke-LibraryHealthCheck`, `Get-CompatibilityWarnings`, `Invoke-ThumbnailDownload`, `Get-ControlReadinessActionItems`, and PostgreSQL's startup requirement scan. `Read-PostgresRecoveryState` separately sorts a small control-state JSON set and is not a registered-profile inventory path; support diagnostics intentionally cap discovery at 200 XMLs.
- Expected behavior: add shared unknown-total direct-profile discovery progress before each existing sorted/known-total phase; preserve each caller's enumeration error action, FullBackup filter, ordering, candidate set, failure result, workflow boundary, and all later scan/backup/mutation behavior.
- Forbidden regressions: no changed profile membership/order, swallowed enumeration errors, altered backup-before-mutation or rollback behavior, changed FFB/CursorHide/BepInEx result accounting, or changed PostgreSQL recovery/setup decisions.
- Focused behavior tests before/with implementation: test the shared discovery helper against multiple direct XML files plus a nested FullBackup XML and unrelated file; assert returned candidate objects/order, unknown-total advancement and closure, and Stop versus SilentlyContinue enumeration behavior. Extend existing caller behavior tests for ReShade removal, dgVoodoo2, CursorHide, FFB plugin/Blaster, BepInEx path preflight, Library Health backup/scan, compatibility warnings, thumbnail indexing, control readiness, PostgreSQL reinitialize/setup/recovery/database backup, and PostgreSQL requirement scanning to assert discovery progress while retaining outcome assertions.
- Runtime proof: exact authorized candidate package must exercise representative ReShade, dgVoodoo2, CursorHide, FFB, BepInEx, Library Health, thumbnail, compatibility, onboarding, and PostgreSQL paths with multiple registered profiles; no package/runtime authorization is implied.
- Stop condition: stop if any candidate, ordering, error result, backup boundary, profile mutation, rollback result, or PostgreSQL plan changes.
- Hunk mapping: shared `Get-TpmRegisteredProfileFilesWithDiscoveryProgress` helper and all 17 callsites above; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 53. Additional ID 3 source re-audit -- profile processing inventory discovery

- Exact uncovered paths: `Invoke-GpuFixSetupLegacy` and its `Invoke-GpuFixSetup` transaction-result wrapper, Crosshair profile planning, both UserProfiles snapshots in registration (`preExistingFiles` and `gamePathProfiles`), `Repair-GamePaths`, `Build-ArchetypePool`, `Invoke-ControlPropagationLegacy`, `Export-LaunchBoxXml`, LaunchBox direct-write, HyperSpin profile import, `Write-ControlsStatus`, and the post-restore item projection in `Invoke-RestoreBackup` materialize direct profile-entry arrays before existing known-total work or result construction. Support diagnostics' `Select-Object -First 200` cap remains an explicitly bounded surface.
- Expected behavior: show unknown-total profile-entry discovery before the existing known-total phase; preserve each enumeration's error action, file/directory inclusion, FullBackup behavior, ordering, `OnlyGames` filtering, registration indexes, transaction-result items, and all scan/export/mutation results.
- Forbidden regressions: no changed registration conflicts, path-repair choices, control archetypes/propagation, LaunchBox or HyperSpin entries, status contents, GPU Fix writes, restore transaction outcomes, or error handling.
- Focused behavior tests before/with implementation: exercise the shared discovery helper with both file-only and directory-inclusive modes and error behavior; extend existing GPU Fix, Crosshair, registration, path-repair, Control Propagation, LaunchBox export/direct-write, HyperSpin, controls-status, and restore-result tests to preserve their output/state while observing discovery progress.
- Runtime proof: exact authorized candidate package must exercise representative profile scans and exports against a multi-profile library; no package/runtime authorization is implied.
- Stop condition: stop if candidate membership, ordering, directory inclusion, backup/rollback boundary, selected registration/path repair, exported data, or user-visible result changes.
- Hunk mapping: `Get-TpmRegisteredProfileFilesWithDiscoveryProgress`, its directory-inclusive and FullBackup-inclusive modes, and all 13 callsites above; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 54. Additional ID 3 source re-audit -- GameProfiles catalog discovery

- Exact uncovered paths: `Get-GpuFixFieldNames`, `Get-GpuAndFfbFieldNames`, `Get-FFBBlasterFieldNames`, `Build-ProfileIndex`, and `Get-TeknoParrotProfileSet`'s local fallback materialize the TeknoParrot `GameProfiles` catalog before their known-total profile work. The catalog can contain 1000+ XML entries.
- Expected behavior: stream unknown-total directory discovery before the existing known-total parse/index loop; preserve each callsite's `*.xml` matching, file-versus-directory inclusion, error action, fallback precedence, catalog/index contents, and parse-failure behavior.
- Forbidden regressions: no changed GPU/FFB field names, executable index, profile-set source selection, order, or error fallback.
- Focused behavior tests before/with implementation: test the shared directory-entry discovery helper in file-only and directory-inclusive modes, including a matching XML-named directory; extend GPU/FFB field catalog, `Build-ProfileIndex`, and ProfileSet local-fallback behavior tests to retain catalog/index contents while asserting discovery advancement and closure.
- Runtime proof: exact authorized candidate package must scan the installed GameProfiles catalog and exercise the local ProfileSet fallback; no package/runtime authorization is implied.
- Stop condition: stop if catalog membership, field names, executable alternatives, ProfileSet precedence, or parse fallback changes.
- Hunk mapping: `Get-TpmDirectoryEntriesWithDiscoveryProgress`, its UserProfiles wrapper, and the five GameProfiles catalog callsites above; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 55. Additional ID 3 source re-audit -- restore and rollback root-entry discovery

- Exact uncovered paths: FFB overlap snapshot/rollback (`Disable-FFBBlasterForOverlap`, `Restore-FFBPluginDeploymentTransaction`), `Restore-TpmLegacyUserProfilesSnapshot` removal and rollback inventories, and `Invoke-RestoreBackupLegacy` snapshot, live-removal, and selected-backup restore inventories materialize direct directory entries before their existing known-total copy/delete loops. `Restore-BepInExUpdateBackup` remains an explicitly bounded five-name backup surface.
- Expected behavior: stream unknown-total direct-entry discovery before each existing known-total operation; preserve `-Force`, error behavior, file/directory pipeline objects, FullBackup exclusion, source/destination paths, backup bytes, mutation order, and rollback outcomes.
- Forbidden regressions: no changed UserProfiles/FFB snapshot contents, removal target, restore membership, rollback ordering, wildcard safety, backup preservation, or error policy.
- Focused behavior tests before/with implementation: extend FFB overlap snapshot/rollback and UserProfiles restore success/failure fixtures to assert discovery advancement/closure alongside exact backed-up/restored bytes, protected FullBackup contents, and transaction outcomes.
- Runtime proof: exact authorized candidate package must restore a selected UserProfiles backup and exercise FFB overlap rollback with multiple profile-root entries; no package/runtime authorization is implied.
- Stop condition: stop if any root entry, backup bytes, removal target, mutation order, rollback result, or FullBackup preservation changes.
- Hunk mapping: generic directory-entry discovery helper and the seven root-entry inventory callsites above; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 56. Additional ID 3 source re-audit -- FFB overlap rollback discovery

- Exact uncovered path: `Disable-FFBBlasterForOverlap` materializes the backup-root entries during catch-path rollback before its known-total restore loop.
- Expected behavior: stream unknown-total direct-entry discovery before rollback; preserve `-Force`, `Stop` error behavior, entry order/types, restore destination, bytes, and rollback result.
- Forbidden regressions: no changed snapshot membership, restored profile bytes, rollback boundary/order, or failure result.
- Focused behavior test before/with implementation: extend the existing failed-save FFB overlap fixture to assert rollback discovery advancement/closure and original profile bytes.
- Runtime proof: exact authorized candidate package must force an FFB overlap save failure with multiple root entries and verify rollback; no package/runtime authorization is implied.
- Stop condition: stop if rollback source entries, destination, order, profile bytes, or transaction result changes.
- Hunk mapping: `Disable-FFBBlasterForOverlap` catch-path rollback inventory and its fixture-backed test; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 57. Additional ID 3 source re-audit -- support-package migration discovery

- Exact uncovered path: `Invoke-TpmOwnedMigration` materializes direct `SupportPackages` entries before appending them to the migration plan and its known-total backup/move loops.
- Expected behavior: stream unknown-total direct-entry discovery before plan expansion; preserve `-Force`, terminating enumeration errors, file/directory entries, provider order, destinations, backup/move contents, and transaction results.
- Forbidden regressions: no changed managed-package membership/order, migration plan, backup boundary, destination, or rollback behavior.
- Focused behavior test before/with implementation: extend the owned-state migration fixture with multiple SupportPackages entries and assert discovery advancement/closure plus exact migrated contents.
- Runtime proof: exact authorized candidate package must migrate a populated managed SupportPackages directory; no package/runtime authorization is implied.
- Stop condition: stop if any entry, ordering, destination, backup, or migration/rollback result changes.
- Hunk mapping: `Invoke-TpmOwnedMigration` SupportPackages child inventory and its fixture-backed tests; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 58. Additional ID 3 source re-audit -- support plugin data-directory discovery

- Exact uncovered path: `Get-TpmSupportPluginInventory` materializes all direct game-root directories before filtering `_Data` candidates; plugin-tree descendants already stream with unknown-total progress.
- Expected behavior: stream direct-entry discovery before preserving the existing directory-only `_Data$` match, reparse checks, candidate precedence, plugin-root de-duplication, traversal limit, and records.
- Forbidden regressions: no changed eligible plugin roots, reparse rejection, inventory membership/order, record data, or failure handling.
- Focused behavior test before/with implementation: extend support-plugin inventory fixtures with multiple `_Data` and unrelated direct entries; assert discovery advancement/closure and unchanged inventory records.
- Runtime proof: exact authorized candidate package must inspect a populated approved game root with multiple data directories; no package/runtime authorization is implied.
- Stop condition: stop if data-directory candidates, nested plugin traversal, limits, or inventory results change.
- Hunk mapping: `Get-TpmSupportPluginInventory` direct game-root discovery and its fixture-backed tests; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 59. Additional ID 3 source re-audit -- user configuration and thumbnail discovery

- Exact uncovered paths: ReShade preset `.ini` files, dgVoodoo2 preset `.conf` files, and custom-thumbnail `.png` files are materialized before setup validation or known-total thumbnail processing begins.
- Expected behavior: stream unknown-total file discovery at each directory, then preserve filters, provider order, matching profile-code checks, existing diagnostics, copy decisions, and all later progress.
- Forbidden regressions: no changed configuration/thumbnail candidate set, filename validation, installation result, copied bytes, or failure behavior.
- Focused behavior tests before/with implementation: extend ReShade, dgVoodoo2, and thumbnail fixtures with valid, invalid-name, and unrelated files; assert discovery advancement/closure and exact existing outcomes.
- Runtime proof: exact authorized candidate package must exercise each setup with multiple owned override files; no package/runtime authorization is implied.
- Stop condition: stop if candidates, validation, output files, user prompts, or operation results change.
- Hunk mapping: the three user-owned file discovery sites and fixture-backed ReShade/dgVoodoo2/thumbnail tests; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 60. Additional ID 3 source re-audit -- HyperSpin system-file discovery

- Exact uncovered path: `Export-HyperSpinGames` materializes all direct `games\*.json` files before its known-total GUID scan.
- Expected behavior: stream unknown-total JSON file discovery before the existing scan; preserve filter, provider order, GUID matching, early selection, parse-error handling, selected output path, and exported records.
- Forbidden regressions: no changed system-file candidate set/order, selected file, JSON contents, or HyperSpin mutation behavior.
- Focused behavior test before/with implementation: extend the real HyperSpin emulator-ID fixture with multiple JSON system files and assert discovery advancement/closure plus the exact selected/exported TeknoParrot game record.
- Runtime proof: exact authorized candidate package must inspect a populated HyperSpin games directory and export against the matching system GUID; no package/runtime authorization is implied.
- Stop condition: stop if discovery changes file membership/order, system selection, export contents, or error handling.
- Hunk mapping: `Export-HyperSpinGames` system JSON discovery and fixture-backed tests; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 61. Additional ID 3 source re-audit -- support plugin child-directory discovery

- Exact uncovered path: `Get-TpmSupportPluginInventory` wraps every recursive direct-child `Get-ChildItem` in an array before its existing unknown-total per-entry progress, delaying the first status update for a large plugin directory.
- Expected behavior: report unknown-total discovery while enumerating each directory before its existing child processing; preserve traversal stack order, reparse checks, file limit, record rows, and failure handling.
- Forbidden regressions: no changed plugin candidate membership/order, nested traversal, 500-file limit, safe-file opening, or emitted evidence.
- Focused behavior test before/with implementation: extend the support-plugin fixture with multiple direct files and a nested directory; assert per-directory discovery closes and the same inventory rows are emitted.
- Runtime proof: exact authorized candidate package must inspect a large approved plugin tree and preserve its inventory record; no package/runtime authorization is implied.
- Stop condition: stop if child order, traversal, limits, evidence rows, or failure results change.
- Hunk mapping: `Get-TpmSupportPluginInventory` per-directory child enumeration and its fixture-backed test; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 62. Additional ID 3 source re-audit -- PostgreSQL recovery retry-state discovery

- Exact uncovered path: `Find-PostgresRecoveryRetryState` materializes and sorts every recovery-state JSON candidate before validating retries.
- Expected behavior: stream unknown-total candidate discovery before preserving descending `LastWriteTimeUtc` order, previous-state exclusion, silent enumeration behavior, envelope validation, and selected retry path.
- Forbidden regressions: no changed retry candidate set/order, attempt/config/script/runtime matching, claim ownership, or failure fallback.
- Focused behavior test before/with implementation: create multiple state candidates and a valid later attempt; assert discovery advancement/closure and the exact state path selected by existing validation.
- Runtime proof: exact authorized candidate package must exercise retry recovery with multiple state candidates; no package/runtime authorization is implied.
- Stop condition: stop if candidate order, retry selection, replay protection, or error handling changes.
- Hunk mapping: `Find-PostgresRecoveryRetryState` candidate inventory and its recovery-state fixture tests; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.

## 63. Additional ID 3 source re-audit -- PostgreSQL backup candidate discovery

- Exact uncovered paths: `Get-PostgresBackupFile` materializes/sorts date subfolders and materializes every file in the selected folder before choosing the highest numbered backup.
- Expected behavior: report unknown-total discovery for date folders and selected-folder files before existing selection; preserve date-name filtering/order, latest-date precedence, leading-number sort, `-ErrorAction SilentlyContinue`, and null return.
- Forbidden regressions: no changed backup candidate, chosen path, date precedence, or missing-folder behavior.
- Focused behavior test before/with implementation: fixture multiple date folders, multiple numbered files, and unrelated files; assert discovery closure and the exact newest-date/highest-number path.
- Runtime proof: exact authorized candidate package must resolve an installed game's real `pg_backup` tree; no package/runtime authorization is implied.
- Stop condition: stop if any date/file candidate, selection, or null/error result changes.
- Hunk mapping: `Get-PostgresBackupFile` date/file inventories and a fixture-backed selector test; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.
## 64. Additional ID 3 source re-audit -- user-extensible Crosshairs PNG discovery

- Exact uncovered path: `Invoke-CrosshairSetup` materialized and sorted every direct `Crosshairs\*.png` before progress. The shipped bundle has 321 images, but README.md explicitly invites users to add any PNG, so this is not a bounded 321-item inventory.
- Expected behavior: stream unknown-total progress while enumerating each direct PNG and keep the row active through the existing filename sort; close only after sorting in `finally`, then preserve the known-total validation pass. Use `-ErrorAction Stop` so enumeration failures are not silently treated as empty/partial results. Preserve image acceptance, candidate order, preview list, selected P1/P2 files, and deployment targets.
- Forbidden regressions: no hidden fixed cap, no changed PNG filter/candidate membership, sort or selection semantics, no new image validation policy, no swallowed discovery failure, and no mutation before the existing explicit confirmation.
- Focused failing test before implementation: extend `Crosshair profile-planning progress` with multiple shipped/user-added PNG fixtures, capture progress and validation events, and assert unknown-total per-entry progress, sort-before-close, closure on enumeration failure, sorted candidates, and unchanged P1/P2 output bytes. Run before product edit; it should fail because no discovery progress is emitted.
- Focused behavior tests after implementation: the fixture-backed test asserts unknown-total discovery advances for all files, stays open through the real filename sort, closes before validation, closes on a simulated terminating enumeration error, and uses `-ErrorAction Stop`; known-total validation and existing profile-planning progress reach completion while sorted candidates and P1/P2 bytes remain unchanged. The dynamic browser-index boundary test proves valid user-added images beyond index 320 are accepted.
- Runtime proof: exact authorized package must validate a directory containing shipped and user-added PNGs; record exact source/package identity, selected file names, progress, and P1/P2 outputs. No owner smoke is performed by this source lane; Eli's owner runtime remains required.
- Stop condition: the discovery/sort source gap is corrected and its failing-before/passing-after regression and finite census are complete. ID 3 is `SOURCE FIXED; OWNER RUNTIME NEEDED`; the final aggregate source/permanent gate passed. Exact-SHA candidate-source preparation may proceed, but package build remains subject to pushed-SHA, current-cycle #290, READY, and human-authorization gates. Stop if candidate membership/order, image filtering, selection, output bytes, or existing mutation boundaries change.
- Hunk mapping: `Invoke-CrosshairSetup` PNG discovery and the fixture-backed Crosshair progress test; owner ID 3; PR #321; `TPM-PROGRESS-SCAN-COVERAGE-001`; `TPM-PROGRESS-001`; `TPM-PROGRESS-002`; `TPM-TRACE-001`.
