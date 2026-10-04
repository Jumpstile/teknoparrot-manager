# TPM S1 PostgreSQL 8.3 Database Restore

- Slice ID: TPM-S1-DB-RESTORE-001
- Slice name: PostgreSQL 8.3 database restore transaction semantics
- Included owner-report IDs: 16, plus the authorized S1 database restore design findings.
- Issue/PR: PR #321 remediation control board.
- Permanent procedures: TPM-TRACE-001, TPM-OWNER-001, and the PR #321 fail-closed remediation gate.

## Behavior contract

- Only the PostgreSQL 8.3 client set (`psql.exe`, `pg_dump.exe`, `dropdb.exe`, `createdb.exe`, `pg_restore.exe`) is accepted, and every executable must report PostgreSQL 8.3 before mutation.
- The selected backup directory is a closed, deterministic set of safe database names and stable, non-empty, readable archives whose `pg_restore --list` checks succeed.
- Existing database state is verified and dumped before the first destructive drop; each dump is hash- and archive-verified.
- Restore order is deterministic, each database has a mutation receipt, and no new database mutation starts after the first failure.
- A failure after mutation rolls back changed databases from verified dumps in reverse order. Unverified rollback is `ACTION_REQUIRED` with `UNKNOWN` product state and preserved evidence.
- Final verification maps outcomes to `TPM.TransactionResult.v1`; ordinary output contains only beginner-safe status and keeps technical paths, commands, hashes, and receipts in Details/log evidence.
- PostgreSQL setup keeps database creation and required profile writes coupled; any unverified rollback maps to `ACTION_REQUIRED`.

## Explicit exclusions

- PostgreSQL versions other than 8.3, compatibility features outside the existing shipped restore paths, owner smoke, packaging, push, merge, tag, publication, certification, Arcade, wiki, and release authorization.
- Non-PostgreSQL workflows and unrelated cleanup.

## Source ownership

- `TeknoParrot-Manager.ps1`: restore transaction engine, guided setup coupling, normal restore UI, and transaction result mapping.
- `Tests/TeknoParrot-Manager.Tests.ps1`: deterministic fake PostgreSQL command harness, filesystem fixtures, and S1 behavior coverage.
- `ARCHITECTURE.md`: PostgreSQL S1 design and invariants.
- `docs/remediation/PR-321-control-board.md` and `docs/remediation/PR-321-reconciliation.md`: owner mapping, hunk classification, and evidence.

## Required verification

- Focused S1-DB-RESTORE, S1-DIRECTORY-REPLACEMENT, S1-FILE-PROMOTION, S1-BACKUP-GATE, and S1-TX-CORE tests.
- Full `Tests/TeknoParrot-Manager.Tests.ps1` Pester suite, parser check, PSScriptAnalyzer Error/Warning check with `PSScriptAnalyzerSettings.psd1`, ASCII check, `git diff --check`, and final status capture.
- No PostgreSQL 12 proof and no owner smoke.

## Stop condition

Stop when the focused tests, full suite, static checks, slice contract, control-board row, remediation report mapping, and implementation packet evidence are complete. Do not widen scope.

## Forbidden actions

No commit, push, package, release, certification, owner smoke, Arcade work, wiki update, merge, tag, publication, or unrelated workflow migration.

## Authorization

- Source implementation: authorized for this slice only.
- Commit/package/release/certification: not authorized.
- Runtime owner proof: paused and not authorized.
