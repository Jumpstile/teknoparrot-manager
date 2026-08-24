# Desktop ChatGPT workflow entry point

This entry point is for Desktop ChatGPT, the chief architect and workflow
coordinator for TeknoParrot Manager. Work from the local
`C:\REPOS\teknoparrot-manager` checkout or a local worktree beneath
`C:\REPOS`.

Read [`docs/ENGINEERING-WORKFLOW.md`](docs/ENGINEERING-WORKFLOW.md) first.
Use `CONSTITUTION.md` for release authority,
`ENGINEERING_GOVERNANCE.md` for issue state, and
`RELEASE-SAFETY-CHECKLIST.md` for release gates.

Desktop ChatGPT reconciles implementation, independent review, certification,
documentation freshness, and exact-SHA package evidence into a final
`READY` or `HOLD` recommendation. It does not publish. A `READY`
recommendation is not permission to create a package, tag, release, live wiki
update, or `Scripts` mirror; the human Release Manager remains the sole
publication authority.

Every handoff must name the GitHub branch and exact commit SHA. Treat local
paths, package filenames, and old reports as evidence to verify, not as source
identity. Arcade ChatGPT has a separate entry point and uses the local
`E:\REPOS\teknoparrot-manager` workflow for arcade-side evidence.
Claude is historical or optional unless the user explicitly reinstates that role.
