# TPM S1 Legacy State Transactions

## 1. Slice name

- Name: S1 legacy state transaction normalization
- Contract ID: TPM-S1-LEGACY-STATE-TRANSACTIONS-001
- Issue/PR: PR #321 remediation control board
- Permanent procedures: TPM-TRACE-001, TPM-EVIDENCE-001, TPM-OWNER-001, PR #321 fail-closed remediation gate

## 2. Owner report IDs included

- IDs: 5, 11, 12, 16, 17, 18, 19, 20, 21, 22, 30, 34, plus the authorized S1 legacy transaction design findings for GPU Fix, TPM-owned migration, UserProfiles restore, Register-Games, PCSX2 cursor-path update, and PostgreSQL wrapper normalization. For ID 34, startup first requires a valid `TPM.TransactionResult.v1` and stops before new log/config path selection for invalid results, `ACTION_REQUIRED`, or `UNKNOWN` product state.
- Exact owner-visible failures: stateful workflows return legacy booleans, counters, status objects, or nested transaction results; partial mutation and cleanup residue are not uniformly represented by TPM.TransactionResult.v1.

## 3. Explicit exclusions

- LaunchBox export/restore, HyperSpin export, thumbnail acquisition, and optional artifact/download workflows unless a separately authorized review classifies a path as live runtime replacement.
- PostgreSQL 12 or other compatibility paths.
- Unrelated workflow migration, feature work, UI redesign, package rebuild, owner smoke, Arcade, wiki, merge, tag, publication, certification, or release authorization.
- A commit and push are authorized only after source gates pass, and only to PR #321's existing head ref to obtain exact-head CI.

## 4. Behavior contract

- Every in-scope destructive/stateful workflow returns TPM.TransactionResult.v1 as its authoritative result.
- Mutation items, pre-state, backup, final verification, rollback, and cleanup evidence are populated consistently.
- A required backup failure blocks mutation.
- A known mixed result is PARTIAL_APPLIED, not clean success.
- A verified restore is ROLLED_BACK_VERIFIED.
- An unverified product or rollback state is ACTION_REQUIRED.
- Cleanup failure preserves residue evidence and is CLEANUP_RESIDUE where product state is verified.
- Startup invariant: an `ACTION_REQUIRED` outcome, `UNKNOWN` product state, missing result, or unrecognized outcome stops startup before new log/config paths are assigned. The stop is non-interactive and occurs before the main workflow continues.
- Beginner-facing output contains no paths, commands, hashes, database names, passwords, or PowerShell details.
- Password-redaction and PostgreSQL credential boundaries remain unchanged.

Forbidden regressions:

- Do not weaken existing canonical path/reparse checks.
- Do not remove existing ReShade/BepInEx rollback evidence.
- Do not claim password rollback after a committed PostgreSQL role-password change.
- Do not change LaunchBox, HyperSpin, thumbnail, or optional artifact behavior.
- Do not make owner-runtime or package claims from desktop source tests.

## 5. System Invariant Inventory

| ID | Invariant | Required evidence |
|---|---|---|
| LST-01 | Every selected mutation item appears in exactly one terminal item set. | Assert-TpmTransactionResult; per-workflow item accounting tests |
| LST-02 | No mutation is reported as FAILED_BEFORE_MUTATION or NO_OP after a live write. | mutation-boundary fault tests |
| LST-03 | Required backup failure prevents the first mutation. | backup-gate tests for each profile/filesystem workflow |
| LST-04 | Final verification re-reads the affected state rather than trusting in-memory objects. | per-workflow final verification tests |
| LST-05 | A known partial result is PARTIAL_APPLIED and records changed, failed, skipped, and unattempted items. | aggregate-result tests |
| LST-06 | Verified rollback records rollback items and leaves product state unchanged. | rollback tests with hashes/content assertions |
| LST-07 | Rollback or cleanup uncertainty preserves evidence and returns ACTION_REQUIRED or CLEANUP_RESIDUE. | residue/failure tests |
| LST-08 | User-facing summaries remain technical-detail-free. | source and result-summary tests |
| LST-09 | PostgreSQL committed-but-unverified password changes remain recovery-blocked. | password recovery tests |
| LST-10 | Deferred workflows are not changed by this slice. | changed-file/hunk classification and source audit |
| LST-11 | Startup does not select migrated log/config paths or continue the main workflow when migration state is `ACTION_REQUIRED`, `UNKNOWN`, missing, or unrecognized. | Migration-startup gate behavior tests; exact-head CI |

## 6. Source/function ownership

- `TeknoParrot-Manager.ps1`
- `Tests/TeknoParrot-Manager.Tests.ps1`
- `ARCHITECTURE.md`
- `docs/remediation/PR-321-control-board.md`
- `docs/remediation/PR-321-reconciliation.md`
- `docs/remediation/slices/TPM-S1-LEGACY-STATE-TRANSACTIONS-001.md`

Primary functions:

- `Invoke-GpuFixSetup`
- `Invoke-TpmOwnedMigration`
- `Test-TpmOwnedMigrationStartupAllowed`
- `Invoke-RestoreBackup`
- `Register-Games`
- `Invoke-ControlPropagation`
- `Repair-GamePaths`
- `Invoke-LibraryHealthManualPathRepair`
- `Set-Pcsx2CursorPaths`
- `Invoke-ReShadeSetup`
- `Invoke-BepInExUpdateCheck`
- `Reset-PostgresPasswordAutomatically`
- `Invoke-PostgresSelectedPasswordRecovery`
- `Reset-PostgresDatabaseFromBackup`
- `Invoke-PostgresReinitializePlan`
- shared transaction-result and verified-backup helpers

## 7. Tests required before implementation

- Existing transaction-core and S1 regression suites must remain green.
- Existing ReShade, BepInEx, Register-Games, controls, GPU, Library Health, restore, PCSX2, and PostgreSQL recovery characterization tests must be inventoried before edits.
- No owner smoke is required or authorized before implementation.
- Focused migration-startup policy tests reject `ACTION_REQUIRED` / `UNKNOWN`, malformed or missing transaction results, and unrecognized outcomes; allow `NO_OP`, `SUCCEEDED`, `ROLLED_BACK_VERIFIED`, and `FAILED_BEFORE_MUTATION` only as valid `TPM.TransactionResult.v1` results.

## 8. Tests required after implementation

- Focused S1-LEGACY-STATE-TRANSACTIONS tests for every listed workflow.
- Focused S1-TX-CORE, S1-DB-RESTORE, S1-DIRECTORY-REPLACEMENT, S1-FILE-PROMOTION, and S1-BACKUP-GATE tests.
- Existing ReShade and BepInEx regression tests.
- Existing Register-Games, controls, GPU, Library Health, UserProfiles restore, PCSX2, and PostgreSQL password recovery tests.
- Migration startup must stop before assigning the new log/config paths whenever the result does not establish a verified state.
- Full main Pester suite.
- Parser, ASCII, PSScriptAnalyzer Error/Warning, InjectionHunter, `git diff --check`, and final status.

## 9. Documentation/report updates required

- Control board: record owner ID 34's startup-stop invariant and current source/test/runtime disposition.
- Remediation report: add the exact owner mapping, LST-11 invariant, hunk classification, focused/full test evidence, and non-actions.
- Architecture: document the startup stop before new log/config path selection.
- Hunk classification: `Test-TpmOwnedMigrationStartupAllowed`, the top-level migration-result stop before log/config assignment, and deterministic decision tests map to owner ID 34, PR #321, `TPM-S1-LEGACY-STATE-TRANSACTIONS-001`, and `TPM-TRACE-001`; behavioral tests also map to `TPM-EVIDENCE-001`.
- Changelog/user docs: update only if the resulting behavior changes a user-facing promise; no new feature or mode is authorized.

## 10. Runtime smoke checklist

- Exact packaged behavior for each migrated workflow remains required.
- Required source/package identity: the later package must be built from the implementation commit and separately authorized.
- Evidence artifacts: focused/full test output, static gates, package identity, and owner report.
- Owner/runtime authorization: not authorized in this slice; owner smoke remains paused.

## 11. Stop condition

Stop when all contract invariants, focused tests, full suite, static gates, control-board/report status, hunk mapping, and implementation-packet evidence are complete. The `ACTION_REQUIRED` / `UNKNOWN` stop must precede assignment of migrated log/config paths and must not request input. Do not widen scope to deferred workflows or unrelated migrations.

## 12. Forbidden actions

No LaunchBox/HyperSpin/thumbnail/optional artifact migration, PostgreSQL 12 work, unrelated cleanup, package, release, certification, owner smoke, Arcade work, wiki update, merge, tag, or publication. Commit/push is authorized only to PR #321's existing head ref after source gates pass, for the requested exact-head CI.

## 13. Authorization status

- Source implementation: authorized for this slice only.
- Test changes: authorized for deterministic coverage of this slice only.
- Commit/push authorized only to PR #321's existing head ref after source gates pass, solely to obtain exact-head CI.
- Package/release/certification and runtime owner proof: not authorized; owner smoke remains paused.
- Runtime owner proof: paused and not authorized.
