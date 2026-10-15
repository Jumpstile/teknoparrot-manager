# TPM Remediation Slice Contract

## 1. Slice name

- Name: PostgreSQL 8.3 setup and restore rollback compatibility
- Contract ID: TPM-POSTGRES-SETUP-ROLLBACK-001
- Issue/PR: PR #321 owner row 88; runtime evidence arrived through the issue #323 exact-package UX gate

## 2. Owner report IDs included

- IDs: PR #321 owner row 88 (PostgreSQL profile/database setup)
- Exact owner-visible failures: On source `d83aa303ef97d5ff0f1538c4d77c87288af8fd09`, package SHA-256 `608E247E6002A4B327A4DE07F458FC5A6D6E84FF8DC84BBE05EC53AA1E75F9E7`, menu 12 scanned 59 profiles and reported six games needing PostgreSQL. Existing-database backup reported no existing databases needed backup; setup then returned `ACTION_REQUIRED/UNKNOWN` because prior database state could not be verified, with rollback progress observed twice at 1/1. The read-only `PostgresAttempt-ProfileImpact-Corrected.json` packet has SHA-256 `42B9554AB7DFFFC9465B5F8FA9B0BC57D63943310D63B4C622F5E630E493C31D`, observed UTC time-of-day `18:46:04.1230563` (full date not included in handoff), baseline SHA-256 `02DEA729E19CB9D64CDED338B2FC72CDE28AF78CC17209B28F9BF0E068518322`; it reports GameProfiles 969->969 / 7,574,923 bytes and UserProfiles 8,698->8,698 / 297,810,587 bytes, with zero added/removed/changed profile files and no raw XML emitted. It explicitly reports `DatabaseCatalogVerified=false`; database state remains UNKNOWN.

## 3. Explicit exclusions

- Owner IDs not included: every PR #321 owner ID other than row 88.
- Features, modules, package, runtime, and release actions excluded: no PostgreSQL service, database, profile, credential, UAC, reset, restore, retry, or recovery action; no package rebuild/copy, merge, tag, publication, certification, wiki, or release action; no normal restore-selection, backup, ordering, or data semantics change beyond the three PostgreSQL 8.3-compatible verified-drop boundaries, setup rollback ownership, and multi-item rollback receipt/state-classification correction in this slice. Scoped commit/push to PR #321's existing head is authorized only after fresh required source gates and independent exact-diff review.

## 4. Behavior contract

- Current failure: The PostgreSQL 8.3.23 `dropdb` specification does not list `--if-exists`; source passed that option at restore mutation, restore rollback, and setup-created-database rollback callsites, so the pinned 8.3 client can reject each before absence verification. Separately, setup creation rolled back internally and returned only a Boolean, after which the caller could retry and treat any failed helper as eligible for drop. These source defects are confirmed; the exact live command failure remains pending corroboration, so do not assert that it was the production exception.
- Expected behavior: All rollback drops use only PostgreSQL 8.3.23-documented options through one boundary that verifies current state, skips drop when verified absent, otherwise issues the supported `dropdb` command and verifies absence; unknown state stops without a destructive guess. Setup returns structured mutation status and command receipts; the transaction owner alone rolls back, and a failed `createdb` command does not confer drop ownership. Verified absent pre-state after one rollback pass maps to `ROLLED_BACK_VERIFIED`/`UNCHANGED`; uncertain state or an unowned database appearing at the creation boundary maps to `ACTION_REQUIRED`/`UNKNOWN`, with evidence preserved and no retry. For a multi-database restore that fails after mutation, the retained receipt file is refreshed after rollback with every attempted item and its final rollback receipts; an unverified rollback removes the item from `CompletedItems` and records it as `UNKNOWN`.
- Restore receipts distinguish a successful TPM `createdb.exe` from a database merely observed after a failed command. Rollback may drop a present database only after successful TPM creation; if an unowned database appears after an absent pre-state, report `ACTION_REQUIRED`/`UNKNOWN` and preserve it. If a pre-existing database was dropped, restore its dump only when a fresh state check confirms absence; do not drop a present database without successful creation ownership.
- If the final receipt JSON refresh fails after rollback, clear `ReceiptPath` so stale JSON is not advertised as current; preserve the evidence root, record `ReceiptError`, and return `CLEANUP_RESIDUE` with cleanup incomplete when rollback itself was verified.
- Forbidden regressions: no database is dropped based only on a stale preflight plan or a false helper result; no unsupported PostgreSQL 8.3 option; no duplicate rollback attempt for one database; no automatic retry after rollback cannot be verified; no stale persisted receipts after rollback; no item is both `CompletedItems` and `UnknownItems`; no claim databases or profiles are unchanged without proof; no credential exposure or weakening of verified backup, profile rollback, service-state, or transaction-result gates.
- Design boundaries and deliberate exclusions: The governing CLI contract is PostgreSQL 8.3.23's versioned `dropdb` documentation. This slice does not add PostgreSQL versions or new restore capability. Preserve command ordering, database selection, backup evidence, password handling, service state, PostgreSQL 8.3 client gating, profile-write coupling, and beginner-safe output. Technical command diagnostics remain redacted and confined to Details/log evidence.

## 5. Source/function ownership

- Files: `TeknoParrot-Manager.ps1`; `Tests/TeknoParrot-Manager.Tests.ps1`; `ARCHITECTURE.md`; `docs/RC8-REMEDIATION-INVENTORY.md`; `docs/remediation/PR-321-current-slice.md`; `docs/remediation/PR-321-control-board.md`; `docs/remediation/PR-321-reconciliation.md`; this contract.
- Functions/regions: `Invoke-Postgres83RestoreDatabase`; `Restore-Postgres83DatabaseFromReceipt`; `Invoke-PostgresRestoreTransaction`; `New-PostgresDatabaseFromBackup`; `Invoke-PostgresGameSetup`; `Restore-PostgresSetupCreatedDatabases`; the shared verified-drop helper; S1 deterministic PostgreSQL fixtures/tests.
- Owning subsystem: PostgreSQL 8.3 restore and profile/database setup transactions.

## 6. Tests required before implementation

- Focused failing or characterization tests: Update the deterministic 8.3 fake to reject `dropdb.exe --if-exists`; cover restore mutation and rollback, setup-created-database rollback, verified-absent skip, and one-owner setup rollback. The current production implementation must fail these fixtures without contacting PostgreSQL. A multi-item restore with an earlier successful database and later failure must also prove the receipt file is refreshed with every rollback result; an unverified rollback must not remain in `CompletedItems` or overlap `UnknownItems`.
- Source/inventory checks: Read PostgreSQL 8.3.23 `dropdb` options at https://www.postgresql.org/docs/8.3/app-dropdb.html and enumerate every production dropdb call. Update the Specification Inventory and System Invariant Inventory before source edits. Confirm all setup and restore callsites use the shared verified-drop boundary and no unsupported switch remains.

## 7. Tests required after implementation

- Focused behavior tests: A verified absent target issues no drop command; an existing target is dropped with only documented PostgreSQL 8.3 arguments and then verified absent; failed drop/query yields `ACTION_REQUIRED`/`UNKNOWN` without retry; a database-restore failure rolls back prior state through the 8.3-compatible path; multi-item `ACTION_REQUIRED` persists every attempted receipt with updated rollback outcomes and classifies unverified items as `UNKNOWN` without terminal-set overlap; setup rollback after a failed restore attempts once; setup pre-creation rejection never drops a database that appeared after the initial plan; preserve successful restore/setup, existing-database preservation, profile-write rollback, backup gates, service-state restoration, and transaction-result assertions.
- Restore collision tests: absent-prestate `createdb` collision must retain the observed database with zero `dropdb.exe` calls and `ACTION_REQUIRED`/`UNKNOWN`; after dropping a pre-existing database, a failed replacement creation must never drop the newly observed unowned database during rollback.
- Receipt persistence failure: force the final refresh write to fail after a prior receipt write; preserve the transaction root, clear `ReceiptPath`, expose `ReceiptError`, set cleanup incomplete, retain a valid `CLEANUP_RESIDUE` result for a verified rollback, and pass `Assert-TpmTransactionResult`.
- Regression suite: Run the focused `S1-DB-RESTORE` / PostgreSQL setup tests, then `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1` under the repository's required Pester version. Run the applicable focused tests under PowerShell 7 and Windows PowerShell 5.1 where the existing workflow provides them.
- Static and procedure gates: PowerShell parser, ASCII, PSScriptAnalyzer Error/Warning with `PSScriptAnalyzerSettings.psd1`, `git diff --check`, required InjectionHunter disposition review, and `pwsh -NoProfile -File .\scripts\Run-TpmQualityGate.ps1 -ReportPath .\docs\remediation\PR-321-reconciliation.md` after exact report evidence is recorded.

## 8. Documentation/report updates required

- Control board row: Add the confirmed PostgreSQL 8.3 rollback compatibility and setup rollback ownership defect to the PostgreSQL setup owner row; keep owner-runtime proof blocking.
- Remediation report row: Add exact owner report mapping, regression names/results, changed-file/hunk mapping, runtime evidence status, and explicit non-actions.
- Hunk classification: Owner row 88 / PR #321 / `TPM-POSTGRES-SETUP-ROLLBACK-001` / `TPM-TRACE-001` / `TPM-OWNER-001` / issue #323 exact-package smoke evidence.
- Changelog or user docs, if applicable: No new capability; architecture and remediation evidence only until a release candidate is explicitly re-authorized.

## 9. Permanent procedure IDs affected

- IDs and evidence: `TPM-TRACE-001` and `TPM-OWNER-001`; the report must preserve source/package/runtime separation and must not pass the owner-runtime gate.

## 10. Runtime smoke checklist

- Exact packaged behavior: Not authorized in this slice. Any later owner-runtime retry requires fresh exact-head source gates plus an approved mutation plan and explicit human GO; the failed ZIP remains immutable incident evidence.
- Required source/package identity: Failed source `d83aa303ef97d5ff0f1538c4d77c87288af8fd09`; failed ZIP SHA-256 `608E247E6002A4B327A4DE07F458FC5A6D6E84FF8DC84BBE05EC53AA1E75F9E7`; packaged script SHA-256 `C649214E769EA19780352EF1B449099957C85AEF86F2FC767CDDA10F82DC1209`.
- Evidence artifacts: Redacted owner packet metadata and existing file-delta evidence only: transaction outcome/product state/reason/stage; backup verification and item counts; ordered tool names, exit codes, and redacted diagnostics for creation and each rollback pass; stable-redacted database identifier; profile delta by field names/counts only; owner-observed service pre/post state. The corrected profile-impact packet SHA-256 is `42B9554AB7DFFFC9465B5F8FA9B0BC57D63943310D63B4C622F5E630E493C31D`; `DatabaseCatalogVerified=false`, DB state UNKNOWN. Never include credentials, raw UserProfile XML, or secret values.
- Owner/runtime authorization: No further PostgreSQL runtime action is authorized by this slice. Owner stopped work at the failure boundary; any recovery action requires separate explicit human approval after read-only state evidence is reviewed.

## 11. Stop condition

Stop if the fixture does not prove PostgreSQL 8.3 option compatibility and rollback ownership across all three callsites, if the owner packet contradicts the proposed link to the live failure, if any pre-state is not verified, or if source/result would imply unchanged state without proof. Do not initiate a live retry or recovery.

## 12. Forbidden actions

- No actual Arcade database/service/credential/UAC/reset/recovery/query action; no secret contents; no competing writer; no cleanup/reset/stash of existing workspace content; no package build, merge, tag, release, publication, certification, or owner smoke until fresh exact-head gates, approved mutation plan, and explicit GO.

## 13. Commit/package authorization status

- Commit authorized: Yes, only to PR #321's existing head after fresh required source gates and independent exact-diff review
- Package authorized: No
- Release/certification authorized: No
