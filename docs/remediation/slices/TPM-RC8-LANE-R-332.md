# TPM-RC8-LANE-R-332 -- Migration backup root inherits broad ACL

## Owner issue
GitHub issue #332 (legacy-to-owned migration backup protection).

## Original finding and current source behavior

`Invoke-TpmOwnedMigration` originally created `Layout.Backups\LegacyMigration_<guid>` without
restricting its ACL before copying legacy state. The current source creates and checks the backup
root, calls `Lock-PostgresRecoveryDirectory` before any copy, and aborts on lock failure.

## Current backup verification

For each planned item, the migration computes a source manifest, copies the item, computes a
backup manifest, and re-reads the source. It refuses to proceed unless source, copy, and re-read
match. The verified manifest hash is retained on the planned move. After each move, the
destination is re-inventoried and must match that hash; a mismatch enters rollback. Rollback is
reported verified only if each restored source matches its pre-migration manifest and its
destination is absent. Directory manifests cover relative paths, item types, lengths, and file
SHA-256 digests; reparse entries are rejected. Failed backup results expose the retained root
as residue when present instead of hiding a partial copy.
Before rollback moves a failed migration destination back to its legacy source, it rechecks the destination path for reparse points and verifies the full manifest against the pre-migration manifest. A changed, missing, unreadable, or reparse destination is left in place and recorded as rollback residue instead of being moved over the source path. Automated recovery after that refusal remains open.
Known legacy-item existence and directory-shape checks use `-ErrorAction Stop`. Inventory errors return `ACTION_REQUIRED` / `UNCHANGED` with `MutationStarted=false`; the existing startup gate blocks normal workflow instead of treating the error as an empty inventory and `NO_OP`.


Preflight now rejects every existing target path, including an empty directory, before backup or
mutation; this avoids ambiguous `Move-Item -Destination` behavior at an occupied target.
Migration reports now include a GUID suffix and are created with `FileMode.CreateNew` rather than overwriting a same-second report or pre-existing file. The report writer flushes and reads back the exact UTF-8 text. This prevents report-path collisions from silently replacing prior evidence; runtime behavior remains unverified under the owner hold.


The migration backup root is rejected if already present, checked for reparse points before creation, and rechecked before its ACL is restricted. Each target is reparse-checked after parent creation and checked absent immediately before the move. If a `Move-Item` invocation throws before returning, the current item is recorded as unverified with candidate source/destination paths and is excluded from automatic rollback; the result cannot claim `ROLLED_BACK_VERIFIED` for an untracked partial move. Rollback refuses to move into a legacy source path that became occupied. A target that becomes occupied or cannot be checked blocks startup even after prior moves are verified rolled back; a failure before any completed move returns `FAILED_BEFORE_MUTATION` instead of an invalid empty `ROLLED_BACK_VERIFIED`.

## Still-open scope

- Rollback failure details include source/destination candidates, and current migration results expose retained backup/rollback paths through `Cleanup.ResiduePaths` without converting an unknown product state into `CLEANUP_RESIDUE`. Startup gates now reject `CLEANUP_RESIDUE`, `DESTINATION_OCCUPIED`, and `DESTINATION_UNVERIFIED`, and print destination evidence when available (`TeknoParrot-Manager.ps1:706-719,33039-33063`). This exposes evidence for manual recovery but does not verify or automate restoration. Durable pending-migration journaling and automated recovery after rollback refusal remain open. Runtime unverified.
- Path checks and filesystem moves are separate operations; concurrent replacement races and Windows move/ACL behavior remain runtime-unverified.
No change to migrated item selection. No TPM tests, parser checks, gates, smoke, or runtime
operations were run under the owner hold.

## Forbidden regressions
- The migration does not move legacy state unless every source/backup/re-read manifest matches; any existing destination path blocks the move, and migrated item selection is unchanged.

## Verification
Owner hold: no TPM tests, parser checks, gates, smoke, or runtime operations in this lane.
Verification remains pending owner approval.

## Original slice stop condition

Lock call applied; file remains pure ASCII.

