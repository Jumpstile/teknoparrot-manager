# Desktop Codex workflow entry point

This is the implementation entry point for Desktop Codex.

Read [`docs/ENGINEERING-WORKFLOW.md`](docs/ENGINEERING-WORKFLOW.md) and
`AGENTS.md` before editing. Work from the local Desktop convention
`C:\REPOS\teknoparrot-manager` or an isolated worktree beneath `C:\REPOS`.
GitHub branch and exact SHA are the handoff authority; do not use a NAS, SMB,
mapped-drive, or UNC Git worktree for implementation or review.

Desktop Codex owns scoped repository edits, local validation, documentation
reconciliation, and PR preparation. Preserve unrelated changes, report the
exact checkout identity, and leave a reviewable diff. Do not merge, publish,
tag, update the live wiki, or copy a release ZIP to a `Scripts` mirror unless
the explicit release gate has been granted.

Arcade runtime validation belongs to Arcade Codex under the local
`E:\REPOS\teknoparrot-manager` convention and the legacy-named
`ARCADE-CLAUDE.md` entry point. A separate independent reviewer must review
work that Desktop Codex authored.
