# Local Git Worktree Policy

Status: accepted engineering policy.

## Authority

GitHub is authoritative for TeknoParrot Manager repository history and for
cross-machine engineering handoff. Every machine and agent uses its own local
clone or local disposable worktree. A pushed GitHub review branch is the only
cross-machine handoff; the receiving machine fetches that branch into its own
local checkout.

Do not use a mapped drive, UNC path, SMB share, synchronized folder, or NAS
checkout as an active shared Git worktree. A network path can have different
credentials, drive mappings, availability, file identity, Git metadata, or
uncommitted changes for each process. A successful read from one process does
not prove that another agent can safely write the same checkout.

## NAS and machine path roles

NAS locations remain useful and are not being deleted or cleaned. They may hold:

- backups and repository mirrors;
- ROM and ZIP source data;
- generated artifacts and test evidence;
- a separate runtime deployment when explicitly authorized.

The machine paths in `AGENTS.md` describe runtime and data roles, not Git
authority. In particular:

- `W:\Emulators\TeknoParrot\Scripts` is a runtime/program path, not an active
  shared Git checkout;
- `W:\ROMS\TeknoParrot Collection` is source data and may be selected as an
  Eggman destination only when it is reachable, canonicalized, non-reparse,
  and outside all protected install, supplementary, staging, and program
  roots;
- an existing dirty or inaccessible NAS checkout is preserved as user data,
  inventoried as far as access permits, and de-authorized without deletion,
  reset, cleanup, rename, or rewrite.

## Handoff sequence

1. Start from a fresh local clone or disposable local worktree.
2. Verify the exact repository root, remote, branch, base commit, and status.
3. Make the smallest scoped change and run the relevant local gates.
4. Push a review branch to GitHub only when the handoff is authorized.
5. The next machine fetches the branch into its own local checkout and verifies
   the commit and changed-file scope before reviewing or continuing.
6. Merge, release, deployment, backup, and mirror operations are separate
   decisions and are not implied by a green test run or a pushed branch.

No script, test, or documentation workflow may require an active UNC, SMB, or
mapped-drive Git worktree. Operator-selected source data paths are a separate
runtime concern and must be validated by the owning feature.
