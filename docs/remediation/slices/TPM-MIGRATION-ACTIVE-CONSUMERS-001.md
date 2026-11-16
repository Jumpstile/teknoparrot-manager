# TPM Remediation Slice Contract

## 1. Slice name
- Name: Preserve active source-root operational state during migration.
- Contract ID: TPM-MIGRATION-ACTIVE-CONSUMERS-001.
- Issue/PR: #323 / PR #321, owner report 34.

## 2. Owner report IDs included
- Owner 34: migration explanation and effective state preservation.
- Exact failure: accepted migration moves overrides to Reports and recovery/cache directories beneath managed roots while actual startup/recovery consumers still use the program root. Custom filters are ignored and old recovery/cache files disappear from default lookup.

## 3. Explicit exclusions
- No new managed override path, consumer rewrite, legacy-artifact adoption, live migration, package, release, or original-checkout change.

## 4. Behavior contract
- Keep active TeknoParrot-Manager.overrides.json, LaunchBoxBackups, PostgresBackups, and BepInExCache at their current consumer locations by excluding them from the legacy migration allowlist. (SUPERSEDED in part: this line originally also listed PostgresRecoveryBackups. It is now relocated to the managed Backups folder, as described under "Current per-directory backup policy" below.)
- Continue existing migration for all other listed State, Logs, diagnostic Reports, SupportPackages, Assets, and Cache entries.
- Preserve custom bytes, default recovery lookup, verified backup-before-move, occupied-destination refusal, decline, and backup-failure abort behavior.
- Existing artifacts moved by earlier unpublished candidates remain preserved for explicit manual review; do not guess which copy is authoritative or silently recover by filename.

### Current per-directory backup policy (supersedes the PostgresRecoveryBackups exclusion)
- Each backup folder is decided on its own. `PostgresRecoveryBackups` (private recovery evidence) is the only backup folder the startup migration moves, into `<TeknoParrotRoot>\TeknoParrotManager\Backups\`, through the protected-ACL copy path. `LaunchBoxBackups` and `PostgresBackups` stay where they are and are never moved, merged or deleted by migration.
- Lookup is also per folder (`Get-TpmOwnedBackupsRoot`): a managed-only folder is used, a legacy-only folder is used without moving anything, and a managed folder plus a legacy folder of the same name is refused ("preserve both and resolve the conflict") instead of being merged. LaunchBox backups additionally go through `Resolve-TpmLaunchBoxBackupLocation`, which keeps backups outside the LaunchBox folder.
- At startup, an occupied managed destination for `PostgresRecoveryBackups` fails the migration before any change (`DESTINATION_OCCUPIED`) and startup stops with the evidence paths.

## 5. Source/function ownership
- TeknoParrot-Manager.ps1: Get-TpmLegacyOwnedItems allowlist only for migration behavior.
- The one full-product-name substitution in the already reviewed controls introduction is owned by TPM-RC8-DOCS-SAFETY-RECONCILIATION-001, not a migration flow change; final mapping is recorded by the documentation lane.
- Tests/TpmOwnedMigration.ActiveConsumers.Tests.ps1: real helper and actual startup/default-consumer regression matrix.

## 6. Tests required before implementation
- Real isolated PS7 and PS5.1 probes both reproduce migration SUCCEEDED plus verified backup while actual startup no longer reads the custom onlySync setting.
- Nine-case PS7 characterization: three safeguard cases pass and six active-consumer preservation cases fail. All source and fixture identities are retained privately.

## 7. Tests required after implementation
- Nine focused Pester 5.7.1 cases on PS5.1 and PS7: accepted overrides/startup, overrides-only no-op, decline, occupied destination, backup failure, and four existing consumer default directories.
- ASCII/parse and configured analyzer checks; complete Tests folder together and permanent quality gate on final frozen source remain parent-owned gates.

## 8. Documentation/report updates required
- Complete active-consumer inventory TPM-MIGRATION-ACTIVE-CONSUMERS-001.
- Documentation lane owns fresh control-board/reconciliation/architecture appends and the user-guide exception paragraph, avoiding concurrent whole-file writes.
- All source/test/inventory hunks map to owner 34 / #323 / this slice / TPM-TRACE-001 / TPM-EVIDENCE-001 / TPM-TRUTH-001.

## 9. Permanent procedure IDs affected
- TPM-TRACE-001, TPM-EVIDENCE-001, TPM-TRUTH-001, TPM-AUTH-001.

## 10. Runtime smoke checklist
- Confirm accepted/declined migration preserves custom overrides and existing backup/cache lookup in an owned staged fixture.
- Read-only owner-runtime preflight should identify old misplaced artifacts for manual review without adopting, deleting, or overwriting them.
- No live install or game state is mutated by this slice's synthetic tests.

## 11. Stop condition
- Stop after bounded exclusion batch, nine-case dual-engine proof, independent review, and synchronized mappings. Final full-folder, package, and runtime gates remain separate.

## 12. Forbidden actions
- No broad path rewrite, new fallback, live app/database operation, original-checkout write, commit, push, package, public wiki, tag, or release.

## 13. Commit/package authorization status
- Local bug fix and tests: explicitly authorized for the isolated candidate.
- Commit/package/release: no authorization is created by this contract.