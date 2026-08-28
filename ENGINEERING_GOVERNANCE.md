# Engineering Governance

Status: canonical GitHub issue/label governance standard for TeknoParrot
Manager, and the template for every Jumpstile project. This document
governs how work is tracked (issues, labels, milestones), not how software
is built or released -- see `CONSTITUTION.md` for the governance hierarchy
this document sits under, and `RELEASE-SAFETY-CHECKLIST.md` section 0 (The
Jumpstile Release Standard) for the release-process standard this document
is audited against on every release.

This document was adopted 2026-07-10 as part of the first full GitHub issue
governance audit of this repository (97 issues reviewed and retagged; see
issue #138, "Engineering Governance and Project Health," for the permanent
tracking meta-issue this audit established).

---

## A. GitHub Issue Governance Standard

### Required issue fields

Every issue must carry, at minimum:

- **One Type label** (what kind of work this is)
- **One Priority label** (how urgent)
- **One Component/Area label** (what part of the system it affects)
- **One Status label** (what state the issue is in; new investigations use `status:needs-investigation` until a different state is justified)

Every issue must also record:

- **A milestone/release decision** -- use the matching milestone and `release:` label when a committed release target exists; otherwise record that there is no committed release target yet.
- **A relationship review** -- explicitly record `Blocks`, `Blocked by`, `Duplicate of`, `Related to`, or `None known`.
- **Acceptance criteria** -- state how another person or agent can verify that the issue is fixed or complete.

An issue missing any required field is not fully triaged. Labels, milestones, and
relationships describe scope and dependencies; none of them alone authorizes a
release or publication.

### Label taxonomy

See Section B below for the full list. Every label uses a `category:value`
prefix (e.g. `type:bug`, `priority:high`) specifically so the same word
can mean different things in different categories without collision (for
example, `component:testing` -- the Pester suite as an affected area -- and
`type:testing` -- test-infrastructure work as the *kind* of change -- are
deliberately different labels).

### Milestone policy

- A milestone represents a **committed release target** (a specific
  version, e.g. "RC2", "Version 1.0"), not a generic bucket like "someday"
  or "backlog" -- that's what `release:post-1.0` is for.
- A milestone closes only when the release it represents actually ships,
  not merely when its issues happen to all be closed early. An
  issue-complete-but-not-yet-released milestone stays open; closing it
  prematurely reads as a release-identity claim, which requires the same
  Release Manager authorization as any other release-identity change (see
  `CONSTITUTION.md`, "Release governance: technical readiness is not
  release authorization").
- Every issue in a milestone should also carry the matching `release:`
  label (e.g. a "RC2" milestone issue also gets `release:rc-required`).
  The milestone is the release-planning view; the label is what makes that
  same information visible from the issue list and searchable without
  opening the milestone.

### Cross-link policy

- An issue that blocks, is blocked by, or duplicates another issue should
  say so explicitly in its body (`Blocks #N`, `Blocked by #N`,
  `Duplicate of #N`), not just rely on GitHub's automatic reference
  detection from a passing mention.
- A release-gate issue (e.g. #124, "RC2 release gate") should list every
  issue it's actually waiting on, and that list should be kept current as
  issues close -- a gate issue with a stale dependency list is worse than
  no dependency list, because it looks authoritative while being wrong.
- When an issue is closed with evidence (a fix commit, a certification
  run, a test result), that evidence belongs in the closing comment, not
  only in a commit message -- someone auditing issue history later should
  not have to cross-reference git log to understand why an issue was
  considered resolved.
- Explicit cross-linking is also what makes safe parallel work possible
  (`ENGINEERING_VELOCITY_AND_TIME_STEWARDSHIP_STANDARD.md`'s "parallelize
  independent work whenever safe" principle) -- an accurately cross-
  linked dependency graph is how a contributor confirms two issues are
  genuinely independent before working on them concurrently, rather than
  discovering a hidden dependency after the fact.

### Acceptance criteria policy

- Every `type:bug` or `type:feature` issue should have a concrete
  "how would we know this is fixed/done" statement before it's
  considered `status:ready` -- either explicit acceptance criteria in the
  issue body, or (for small, obvious fixes) a clear problem statement
  that makes the fix condition self-evident.
- A release-gate issue's acceptance criteria should be independently
  checkable by someone who didn't write the fix -- "tests pass" is
  necessary but not sufficient for anything the certification suite
  itself doesn't already cover (see `CONSTITUTION.md`'s "Engineering
  review rule").
- When a bug or finding traces to a governing specification (a file
  format, a protocol, a language grammar, an API contract), acceptance
  criteria are not "the reported case now passes" -- see
  `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`'s "Definition of Review
  Ready" and `INVENTORY_STANDARDS.md` for the Specification Inventory
  that criteria should be checked against. An issue closed against a
  specification-governed finding should reference that it was resolved
  as a problem class, not as an isolated instance, in its closing
  evidence.

### Release assignment policy

- `release:rc-required` means: must close before the *current* release
  candidate ships. This label's meaning moves with whichever RC is
  currently active -- it is not re-scoped per RC number (there is no
  separate `release:rc2-required` vs `release:rc2.1-required`); the
  milestone (e.g. "RC2") plus this label together say "current candidate,
  required."
- `release:version-1.0` means: must be resolved before or as part of the
  1.0 release specifically, distinct from whatever RC is currently in
  flight.
- `release:version-1.1` / future version labels are added only once that
  release actually has committed scope, not speculatively.
- `release:post-1.0` means: real, tracked work, deliberately deferred --
  not a place to lose track of an idea. Feature-freeze-deferred
  enhancements belong here.
- An issue with no `release:` label has no committed release target yet.
  That is a normal, valid state for most issues, not an oversight.

### Bug lifecycle

1. **Reported** -- filed with `type:bug`, a component, and a priority
   (best-guess priority is fine at filing time; refined during triage).
2. **`status:needs-investigation`** -- root cause not yet known, or scope
   not yet clear.
3. **`status:ready`** -- root cause known, fix scoped, ready to implement.
4. **`status:blocked`** -- ready but cannot proceed (waiting on another
   issue, external dependency, or a decision).
5. **Fixed** -- a commit closes the loop; the issue gets a closing comment
   with the fix commit hash and how it was verified (tests, manual
   confirmation, or both).
6. **`status:verified`** -- for anything where "the code changed" and "the
   fix actually works" are meaningfully different confirmations (UX/visual
   fixes, hardware-dependent behavior, anything needing a human look) --
   applied once that separate confirmation actually happened, not merely
   once the code merged.
7. **Closed.**

A bug does not skip straight from "Reported" to "Closed" without passing
through enough of this lifecycle to leave an audit trail -- the point is
that someone reading the issue later can reconstruct what was wrong, why,
and how it was confirmed fixed, without needing to have been present.

### Feature lifecycle

1. **Proposed** -- filed with `type:feature` or `type:enhancement`,
   component, and priority. During a feature freeze (see `AGENTS.md`),
   new proposals default to `release:post-1.0` unless the freeze is
   explicitly lifted for that specific item.
2. **Scoped** -- acceptance criteria added, `status:ready`.
3. **In progress** -- implementation underway (no dedicated status label;
   an assignee or a linked in-progress PR is the signal).
4. **Shipped** -- closed with a reference to the release/commit it shipped
   in.

Distinguishing `type:feature` (a wholly new capability) from
`type:enhancement` (an improvement to something that already exists) is a
judgment call at filing time, not a hard rule -- when genuinely ambiguous,
default to `type:enhancement`, since it is the less consequential label to
be wrong about (an enhancement can always be relabeled a feature if scope
grows; the reverse relabeling is just as easy, so the cost of guessing
wrong either way is low).

---

## B. GitHub Label Standard

### TYPE

| Label | Meaning |
|---|---|
| `type:bug` | A defect in existing behavior |
| `type:feature` | A wholly new capability |
| `type:enhancement` | An improvement to existing behavior |
| `type:documentation` | Documentation-only work |
| `type:investigation` | Root cause / feasibility research, no fix implied yet |
| `type:technical-debt` | Code health improvement, not a user-facing defect |
| `type:governance` | Process, policy, or engineering-standard work |
| `type:certification` | The certification suite itself, as a system |
| `type:testing` | Test coverage or test-infrastructure work |
| `type:security` | Security-relevant defect or hardening |
| `type:performance` | Speed/resource-usage concern |
| `type:ux` | User experience / clarity concern |
| `type:refactor` | Internal restructuring, no behavior change intended |

### PRIORITY

| Label | Meaning |
|---|---|
| `priority:critical` | Release-blocking or actively harmful |
| `priority:high` | Should be next, real user/engineering impact |
| `priority:medium` | Normal priority |
| `priority:low` | Nice to have, no urgency |

### COMPONENT

| Label | Meaning |
|---|---|
| `component:menu` | Main menu / interactive console UI |
| `component:ui` | General console UI/output, not menu-specific |
| `component:dat` | Eggman/community DAT selection and parsing |
| `component:thumbnails` | Game icon/thumbnail download and management |
| `component:updater` | Self-update (Check for Updates) |
| `component:installer` | Postgres and other component installers |
| `component:certification` | Certification suite (as affected area) |
| `component:release` | Release packaging, versioning, tagging |
| `component:documentation` | README/wiki/docs content |
| `component:automation` | Background jobs, caching, scheduled/unattended behavior |
| `component:testing` | Pester suite and test tooling |
| `component:export` | LaunchBox/HyperSpin/RetroBat export and frontend integration |
| `component:profiles` | GameProfiles/UserProfiles matching and registration |
| `component:sync` | AutoSync / extraction |
| `component:backup` | Backup and restore |
| `component:github` | CI workflows, GitHub Actions, repo tooling |
| `component:networking` | Network path detection, downloads, connectivity |

### RELEASE

| Label | Meaning |
|---|---|
| `release:rc-required` | Must close/verify before the current release candidate ships |
| `release:version-1.0` | Must be resolved before or as part of 1.0 |
| `release:version-1.1` | Targeted for a 1.1 release |
| `release:post-1.0` | Deferred until after 1.0, no committed release yet |

A `release:breaking-change` label is deliberately not adopted yet -- this
project has not shipped a 1.0 with a stable public contract to break.
Add it (documented here, in the same change) if and when that becomes a
real concern, not preemptively.

### STATUS

| Label | Meaning |
|---|---|
| `status:blocked` | Cannot proceed until a dependency resolves |
| `status:needs-investigation` | Not yet root-caused or scoped |
| `status:ready` | Scoped and ready to implement |
| `status:verified` | Fix confirmed working, evidence attached |

### Retained non-taxonomy labels

GitHub's default triage labels remain in use for their original purpose,
outside this taxonomy: `duplicate`, `good first issue`, `help wanted`,
`invalid`, `question`, `wontfix`. These describe an issue's *disposition*,
not its type/priority/component, and are not retired by this standard.

### Retired labels (2026-07-10 audit)

The following pre-taxonomy labels were retired -- every issue that carried
one was retagged into the taxonomy above, and the label definitions were
deleted from the repository: `bug`, `enhancement`, `documentation`,
`security`, `release-blocker`, `1.0-blocker`, `post-1.0`, `diagnostics`,
`technical debt`, `investigation`, `reliability`, `usability`,
`compatibility`, `updater`, `dat-integration`, `process`, `testing`,
`rc2-required`, `game-support`, `postgresql`, `certification`.

---

## Adopting this standard in a new Jumpstile project

1. Copy this file into the new project's repository root.
2. Create the labels in Section B via `gh label create` (or the GitHub UI),
   adjusted only if the new project genuinely needs a Component this
   project doesn't have -- add it here, in the same change, rather than
   inventing an undocumented label.
3. Add `ENGINEERING_GOVERNANCE.md` to the governance-hierarchy list in that
   project's `CONSTITUTION.md`.
4. File a "Engineering Governance and Project Health" meta-issue (see this
   repository's #138 for the template) and reference it from
   `RELEASE-SAFETY-CHECKLIST.md` (or the new project's equivalent) as a
   permanent, reviewed-every-release item.
5. If the new project doesn't have Component values that fit its actual
   architecture, adjust the Component list for that project -- Component
   is the one category expected to genuinely vary project to project;
   Type, Priority, and Status are meant to port unchanged.
