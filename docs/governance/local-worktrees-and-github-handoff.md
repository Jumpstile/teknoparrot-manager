# Local worktrees and GitHub handoff

This page records the standing rule from issue 293. It only repeats what these files already say: `RELEASE-SAFETY-CHECKLIST.md`, `docs/TPM-CERTIFICATION-SUITE.md`, `docs/RC8-REMEDIATION-INVENTORY.md` (row WS-S01) and the other pages in this folder. Where those files do not decide something, the line starts with "Decision needed".

## The rule

- GitHub is the authority. Each machine works in its own local clone or worktree on a local disk.
- Work moves between machines as a pushed ref plus the exact commit SHA. A folder copied over a network is not a handoff.
- A NAS (network storage) is storage and mirror evidence only. It is never an active Git worktree.
- A NAS, an SMB share, a mapped drive or a UNC path is never the source for a build or for certification.

## Before a release build

Copied from `RELEASE-SAFETY-CHECKLIST.md`:

1. Build from a local clone on a local disk, never from a network share.
2. Confirm the origin ref and the exact commit SHA being released, and that `git status` is clean.
3. Confirm that commit is an ancestor of `origin/main`.
4. Confirm the finished package reports that same commit SHA.

The owner makes the final release decision. Nothing is auto-merged, tagged, published or pushed as public work in progress, and live TeknoParrot is never altered.

## Certification

From `docs/TPM-CERTIFICATION-SUITE.md`:

- Certification evidence names one frozen GitHub branch and one exact commit SHA.
- Certification runs from a local checkout on the machine that runs it.
- `Sync-And-Run.bat` is a convenience launcher for manual testing of the latest `main`. It is not an exact-SHA handoff, not proof of package identity and not a release gate.

From `docs/governance/permanent-procedures.md`: get explicit authorization before any commit, push, package, certification, wiki or test-PC work. A test run on a fresh package needs the authorized commit frozen first.

## Source and data folders are not Git worktrees

The folders TPM uses at run time (your TeknoParrot folder, your game ZIP folders, the DAT folder, the staging folder) are your files. A Git worktree is a development folder. The first-run page `docs/FIRST-RUN-DECISIONS.md` explains the runtime folders.

## Decisions needed

- Decision needed: the release package does not yet record the source commit SHA, so checklist step 4 cannot be checked from the package alone. The owner decides whether the package manifest or its `.txt` files carry the SHA, and whether packaging refuses a dirty tree or a commit that is not on `origin/main`.
- Decision needed: written steps for the certification PC (fetch the exact branch and SHA into its own local clone, then record the branch, HEAD, origin ref, clean state and ancestry). The certification page says "local checkout" but not "fetch the exact SHA".
- Decision needed: whether certification should refuse a repository root on a UNC or mapped network drive. Today the rule is written down but nothing checks it.
- Decision needed: whether this page is linked from the README, the Quick Start or a docs index. It lives under `docs/governance`, which is kept out of the release package.
