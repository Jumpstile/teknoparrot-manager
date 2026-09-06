# TeknoParrot Manager Engineering Workflow

Status: canonical current workflow for issue #294.

This document owns cross-machine handoff, workspace roles, validation identity,
and the boundary between engineering readiness and release authorization. It
does not authorize a merge, package, tag, publication, wiki update, or mirror
copy. The current published release is v1.0 RC7. RC8 is remediation/review
work only, and final Version 1.0 remains unpublished.

Related policy sources:

- `CONSTITUTION.md` -- governance hierarchy and release authorization.
- `ENGINEERING_GOVERNANCE.md` -- issue fields, labels, milestones, and
  relationships.
- GitHub issue `#293` -- standing local-worktree and GitHub handoff authority.
- `INDEPENDENT_REVIEW_WORKFLOW_STANDARD.md` -- independent review and delta
  review.
- `RELEASE-SAFETY-CHECKLIST.md` -- release gates and publication order.
- `docs/TPM-CERTIFICATION-SUITE.md` -- certification lanes and artifacts.
- `ROADMAP.md` -- product scope, including the post-1.0 boundary.

## Authority and handoff

This section is the current implementation of the local-worktree and GitHub
handoff policy tracked by `#293`.

1. GitHub is authoritative for cross-machine and cross-agent handoff. The
   repository, pull request, issue, branch, CI result, and exact commit SHA
   are the shared source of truth.
2. A branch name, ZIP filename, local folder, or verbal description is not a
   sufficient handoff. Every implementation or validation handoff records
   the exact SHA and the GitHub branch or tag from which it came.
3. Local clones and worktrees are working copies. They must be clean and
   traceable to the GitHub ref being reviewed or validated.
4. Historical reports and old agent instructions are evidence only. They do
   not override this workflow or prove current release state without fresh
   verification.

## Roles and workspace conventions

| Role | Current responsibility | Active Git workspace |
| --- | --- | --- |
| Desktop ChatGPT | Chief architect, workflow coordinator, release-gate reviewer, and final readiness/go-no-go recommendation. It reconciles evidence and does not publish. | `C:\REPOS\teknoparrot-manager` or a local worktree beneath `C:\REPOS`. |
| Desktop Codex | Implementation, repository edits, local validation, and PR preparation. | `C:\REPOS\teknoparrot-manager` or a local worktree beneath `C:\REPOS`. |
| Arcade ChatGPT | Arcade-side validation evidence coordinator and reviewer. It reconciles Arcade Codex runtime and hardware reports and does not implement or publish. | `E:\REPOS\teknoparrot-manager` or a local worktree beneath `E:\REPOS`. |
| Arcade Codex | Exact-SHA validation, runtime observation, hardware certification, and evidence collection. It does not repair the implementation during certification. | `E:\REPOS\teknoparrot-manager` or a local worktree beneath `E:\REPOS`. |
| Claude | Historical or optional only. Claude is not required by any active workflow step. | None assigned by default. |
| Release Manager | Human authority for release identity, tag, publication, release notes, wiki publication, and any distribution mirror. | GitHub and the explicitly approved release workspace. |

Desktop ChatGPT and Desktop Codex stay on the C path; Arcade ChatGPT and
Arcade Codex stay on the E path. The two role pairs are separate evidence
paths, and an independent reviewer must not be the author of the change being
reviewed. Reinstating Claude for a named task requires explicit instruction and
does not change the path or gate rules here.

## Workspace and path policy

- Active implementation, review, certification, and release-validation Git
  worktrees are local clones or local worktrees. Do not use a NAS, SMB share,
  mapped drive, or UNC path as an authoritative active Git worktree.
- The Desktop host uses `C:\REPOS\teknoparrot-manager` or an explicitly
  Desktop-local worktree beneath `C:\REPOS`.
- The ARCADE host uses `E:\REPOS\teknoparrot-manager` or an explicitly
  ARCADE-local worktree beneath `E:\REPOS`.
- These are normative host/path pairs, not interchangeable examples. A drive
  letter does not identify another machine. A `C:\REPOS` path observed from
  ARCADE is still ARCADE-local storage and is not Desktop evidence; an
  `E:\REPOS` path observed from Desktop is still Desktop-local storage unless
  an explicitly configured remote transport proves otherwise.
- If the approved machine-scoped repository root is missing, fail closed and
  report the missing path. Do not substitute another local drive, checkout,
  mapped path, historical worktree, or similarly named folder.
- A copy from one local drive letter to another on the same host is not a
  cross-machine transfer. Cross-machine transfer is established only through
  the authoritative GitHub ref/SHA or another explicitly configured remote
  transport that the actual receiving host independently verifies.
- Claims such as `Desktop verified`, `ARCADE verified`, `transferred to Desktop`,
  or `transferred to ARCADE` require evidence produced by or independently
  verified from that actual host. Evidence from another machine cannot
  substitute for it.
- NAS storage may hold ROM/source data, packages, generated artifacts,
  validation evidence, backups, and mirrors. Those files are not an active
  Git checkout and do not establish source identity.
- Runtime paths are classified by role and canonical containment. Do not
  apply a blanket rule that all NAS paths are unsafe or all local paths are
  trusted. Each runtime procedure must verify the specific approved root,
  markers, containment, and reparse-point rules defined by its contract.
- A report copied to an artifact or evidence store after a local run remains
  evidence from the local checkout. Record the source host, source branch,
  exact SHA, local repository path, and report path together.

## Standard implementation and review flow

### 1. Triage the GitHub issue

Before active work begins, the issue receives:

- one Type label, one Priority label, one Component/Area label, and one
  Status label; new investigations use `status:needs-investigation` until a
  different state is justified;
- a milestone and matching Release label when a committed release target
  exists, or an explicit triage record that there is no committed release
  target yet;
- an explicit relationship review: `Blocks`, `Blocked by`, `Duplicate of`,
  `Related to`, or `None known`;
- acceptance criteria that another person or agent can check.

Do not use issue labels or a milestone as release authorization. The issue
graph records scope and dependencies; the Release Manager still controls
publication.

### 2. Prepare the Desktop checkout

Start from a clean local checkout. The normal fresh-main sequence is:

```powershell
cd C:\REPOS\teknoparrot-manager
git fetch origin --prune
git switch main
git pull --ff-only origin main
git switch -c <review-branch>
```

Before editing, record `git status --short`, `git rev-parse HEAD`, the
corresponding GitHub ref, and the issue or PR. Do not overwrite unrelated
local changes in an existing checkout; create an isolated local worktree
instead.

Desktop Codex performs the requested implementation and documentation work,
runs the relevant local gates, and prepares a reviewable branch/PR. It does
not merge, publish, tag, update the live wiki, or copy a release ZIP to a
distribution mirror without the explicit gate described below.

### 3. Establish the GitHub handoff

The PR handoff includes:

- repository and issue/PR number;
- source branch and exact HEAD SHA;
- CI result for that SHA;
- changed-file list and validation commands;
- known conflicts, historical references, and any remaining HOLD reason.

If the branch tip changes after handoff, the consumer must stop and re-freeze
the new SHA. Do not validate a moving branch under an old evidence record.

### 4. Validate on ARCADE

Arcade Codex creates or refreshes a local checkout under
`E:\REPOS\teknoparrot-manager`, fetches the named GitHub branch, and checks
out the exact handed-off SHA. If that ARCADE-local E root is unavailable,
validation stops with a missing-path report; ARCADE must not fall back to
`C:\REPOS` or any other local path and must not claim Desktop-side evidence.
A certification run is blocked unless all of the following are recorded:

- `git ls-remote origin refs/heads/<branch>` equals the expected SHA;
- local `git rev-parse HEAD` equals the expected SHA;
- the local worktree is clean and the SHA has the expected ancestry;
- the GitHub CI result belongs to that SHA;
- the approved TeknoParrot runtime root is present and passes its own marker
  and containment checks;
- the certification reports, logs, and hardware observations identify the
  same SHA.

A detached checkout is acceptable when the source branch and expected SHA are
recorded separately. The validation checkout itself must still be local; a
NAS or SMB Git worktree is not a substitute. Reports may be copied to an
evidence store after the run.

For final RC8 pre-release validation, Arcade validation also requires the
**Arcade OMP Packaged Runtime UX Gate** defined in
`docs\TPM-CERTIFICATION-SUITE.md` and issue #323. It runs the exact packaged
source identity in default and constrained terminals, captures screenshots and
logs, and covers package identity, menu/prompt layout, ReShade, Health Check
repair, feature routing, failure truthfulness, and support-package clarity.
Pester remains the pure-logic contract layer; this packaged-runtime gate is the
last required gate before RC8 release authorization.


Controls readiness, launch observation, registration, and verification are
separate dimensions. Static or partial evidence must not be summarized as one
combined `Ready` state. See the certification suite and architecture docs for
the individual evidence ceilings.

### 5. Package and release identity

No release package, tag, public release, live wiki update, or `Scripts` mirror
copy occurs before an explicit Desktop ChatGPT gate. The human Release Manager must
also authorize the publication and release-identity change.

Before a package is accepted, its evidence record pairs the package SHA-256
with:

- the exact source commit SHA and GitHub branch or tag;
- the local build checkout and clean status;
- the GitHub remote ref and ancestry check;
- the package filename, package validator output, and build timestamp;
- the copy or download path when an artifact store is used.

The package filename and version banner alone do not prove source identity.
When the package format has no embedded commit marker, this source-to-package
evidence record is the required proof. A package found on NAS is not
authoritative until its bytes and source identity are reconciled.

### 6. Documentation and wiki freshness

Documentation freshness is a mandatory #290 gate. Review active Markdown,
plain-text release mirrors, user docs, engineering docs, certification docs,
release docs, and the GitHub wiki against current behavior and release state.
Clearly dated historical audits, retrospectives, and old evidence remain
historical; they must not be mistaken for active procedure.

Before a Desktop ChatGPT `READY` recommendation can be recorded for a release
or publication gate, the #290 evidence record must include all of the
following:

- audit timestamp with timezone;
- source branch and exact commit SHA under review;
- the complete list of repository documents reviewed, plus the changed
  repository-document list;
- the GitHub wiki checkout/ref or live-wiki inspection method, the complete
  page list reviewed, and the changed wiki-page list;
- exact stale-release, stale-feature, or consistency findings, including an
  explicit `none found` result where applicable;
- the packaged `.txt` documentation sweep result and the README/QuickStart
  consistency result; and
- the beginner-readability result for install and setup documentation.

The live wiki may be checked manually when CI cannot inspect it, but that
manual check must still record the page list, timestamp, exact findings, and
changed-page report. A repository-only scan is not a complete #290 gate.

The source-controlled `docs/wiki-updates/` files are staging/reference
content. The live wiki is updated only after the same explicit gate as a
release publication.

## Scope boundaries for the current cycle

- RC8 remains remediation/review work only and is not published. The final
  candidate incorporates the accepted #292 runtime fixes, but this workflow
  does not authorize publication.
- #279, #280, and #281 remain post-1.0 unless explicitly re-scoped and
  approved.
- Broad automatic mapping under #200 remains deferred unless explicitly
  approved; no workflow or profile language bypasses that boundary.
- A successful test, certification run, or ChatGPT READY recommendation is
  release evidence, not publication permission.

## Handoff record

Use this minimum record for implementation, certification, and release
validation handoffs:

```text
Repository: Jumpstile/teknoparrot-manager
Issue/PR:
Source branch or tag:
Expected GitHub SHA:
GitHub ref SHA at validation:
Current host: Desktop/ARCADE
Desktop checkout:
ARCADE checkout:
Local HEAD:
Working tree clean: yes/no
Ancestry verified: yes/no
CI result for exact SHA:
TeknoParrot runtime root and marker result:
Evidence/report paths:
Documentation freshness audit timestamp:
Repository documents reviewed:
Repository documents changed:
Wiki inspection method and checkout/ref:
Wiki pages reviewed:
Wiki pages changed:
Documentation freshness findings:
Package filename and SHA-256, if applicable:
Desktop ChatGPT gate: READY/HOLD/not requested
Release Manager authorization: not requested/approved
```

## Conflict-resolution rule

When an older procedure conflicts with this document, stop and identify the
conflict. Mark the old material historical or update it to link here. Do not
silently choose a stale branch name, shared worktree, agent role, release
claim, package identity rule, host, or drive because it appears in an older
report.
