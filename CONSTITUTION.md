# Engineering Constitution

Status: top-level engineering governance for TeknoParrot Manager, and the
template for every Jumpstile project. This document exists to establish the
governance hierarchy itself and the small number of principles that sit
above any single standard. It intentionally stays short -- specific policy
belongs in the standards it points to, not duplicated here.

---

## Governance hierarchy

When applicable, Jumpstile project governance is followed in this order:

1. This document (`CONSTITUTION.md` / Engineering Canon).
2. `PROJECT_IDENTITY_STANDARD.md` -- public identity, branding, and
   attribution policy.
3. `TEAM_COORDINATION_STANDARD.md` -- issue-based coordination protocol
   for human and AI contributors.
4. Architecture Decision Records (ADRs), where a project has them.
5. Repository-specific engineering standards (e.g. `SECURITY.md`,
   `RELEASE-SAFETY-CHECKLIST.md`, `ARCHITECTURE.md`).
6. Task-specific instructions.

If an existing file, issue, PR, release note, wiki page, or other public
artifact conflicts with a document higher in this list, the higher document
is authoritative. The conflict is reported and a compliant resolution
recommended before proceeding with whatever task surfaced it -- silently
picking one side of the conflict is not an acceptable resolution.

Once a document is created and integrated into a project's governance
hierarchy, it applies automatically: every significant PR, merge
recommendation, and release is audited against it without needing to be
asked each time. A believed-necessary change to a standard is proposed
through the normal governance process (a PR against that document), not
bypassed in the moment it's inconvenient.

## Long-lived policy does not live in an issue tracker

GitHub issues (and their equivalents on other trackers) are for tracking
specific, closeable units of work -- a bug, a feature request, an
investigation. They are not the right home for policy meant to outlive any
single issue. When a coordination protocol, a standing rule, or an
engineering practice is discovered to have "grown up" inside an issue
thread, it is migrated into the appropriate governance document here, and
the issue is updated to point to that document rather than continuing to
serve as the source of truth. This document's own governance hierarchy
should always answer "where does a given piece of policy actually live."

## Privacy-first default

If there is any uncertainty about whether a public-facing artifact should
contain a personal identity, a work identity, an email address, an AI
assistant name, an AI product name, a development tool name, or branding
that is not the project's own public identity, default to the
privacy-preserving option: use neutral engineering language instead. If
uncertainty remains even after choosing neutral language, stop and ask
before introducing the reference at all. This applies everywhere any
governance document in this hierarchy applies -- it is not a separate,
lower-priority preference. (See `PROJECT_IDENTITY_STANDARD.md` Section 14
for the identity/attribution-specific version of this rule.)

## Applying this to a new Jumpstile project

1. Copy this file into the new project's repository root, adjusted only for
   project-specific names in the governance-hierarchy list (Section
   references to documents the new project doesn't have yet can be
   omitted, not left as broken pointers).
2. Copy or write `PROJECT_IDENTITY_STANDARD.md` and, if the project
   coordinates work across issues with multiple contributors (human or
   AI), `TEAM_COORDINATION_STANDARD.md`.
3. Add a reference to this document from the project's other governance
   documents (architecture notes, release checklists, contributing guide,
   security policy).
