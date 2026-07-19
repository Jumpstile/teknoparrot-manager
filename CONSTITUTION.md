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
2. Architecture Decision Records (ADRs), where a project has them.
3. `ENGINEERING_GOVERNANCE.md` -- the GitHub issue/label governance
   standard (issue taxonomy, label taxonomy, milestone/cross-link/
   acceptance-criteria policy, bug and feature lifecycle).
4. **Engineering Standards** -- portfolio-wide, repository-agnostic
   standards adopted across every Jumpstile project (e.g.
   `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`, `INVENTORY_STANDARDS.md`,
   `ENGINEERING_VELOCITY_AND_TIME_STEWARDSHIP_STANDARD.md`, and, once
   adopted, `PROJECT_IDENTITY_STANDARD.md` /
   `TEAM_COORDINATION_STANDARD.md`). These documents govern *how*
   engineering work is done, independent of which project it's done in.
5. **Project Standards** -- this repository's own engineering standards
   (e.g. `SECURITY.md`, `RELEASE-SAFETY-CHECKLIST.md`, `ARCHITECTURE.md`).
   These apply this project's specific technical decisions and threat
   model; they operate inside the boundaries tier 4's portfolio standards
   set, but are not themselves portfolio-wide.
6. **Project Documentation** -- user- and contributor-facing documentation
   that is not itself a standard (e.g. `README.md`, the wiki, Quick Start
   guides, `CONTRIBUTING.md`). Authoritative for what the project
   currently does and how to use/contribute to it, but does not carry
   engineering-standard authority over tiers 1-5.
7. Task-specific instructions.

Tiers 4 and 5 were a single, undifferentiated tier ("repository-specific
engineering standards") before this document's Codex-reviewed governance
round; splitting them makes explicit what was previously only implied by
each standard's own "Status" line (several tier-4 documents already
described themselves as "the template for every Jumpstile project," which
is a portfolio-wide claim a project-specific document like `SECURITY.md`
does not and should not make). When adopting a new standard, place it in
tier 4 only if it is genuinely intended to be repository-agnostic and
adopted unchanged (or near-unchanged) across projects; place it in tier 5
if it encodes this project's own specific decisions, even if structured
similarly to a tier-4 document.

`PROJECT_IDENTITY_STANDARD.md` (public identity, branding, and attribution
policy) and `TEAM_COORDINATION_STANDARD.md` (issue-based coordination
protocol for human and AI contributors) are anticipated future additions to
tier 4, not currently present in this repository. They are deliberately
omitted from the numbered list above rather than referenced as if live -- a
governance document should never point at something that doesn't exist. If
and when either is adopted, it slots into tier 4 alongside the other
Engineering Standards, and this list is updated in the same change that
adds it.

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

### Legal, regulatory, and safety obligations sit outside and above this hierarchy

The seven-tier hierarchy above resolves conflicts *between* this
portfolio's own governance documents. It is not the full universe of
obligations a project must satisfy, and none of its tiers -- including
tier 4's Engineering Standards, and any artifact one of them requires (a
Specification Inventory, a System Invariant Inventory, a velocity
checklist, or any other engineering-scope document) -- may be read as
permission to exclude, narrow, defer, or deprioritize a legal requirement,
regulatory requirement, compliance obligation, safety requirement,
security requirement, or organizational policy that applies to the work.
Those obligations always take precedence over every tier of this
hierarchy, in full, regardless of how any tier-4/5 standard scopes its own
engineering requirements. A Specification Inventory's "Deliberately out of
scope" section, for example, documents an *engineering* scoping decision
about what a component itself is responsible for verifying -- it never
documents a decision to skip a legal, regulatory, safety, or security
obligation; if such an obligation applies, it applies regardless of what
any inventory says, and should appear in the inventory (if at all) only as
a cross-reference to the separate control that actually satisfies it (e.g.
`SECURITY.md`, a compliance policy document, or an external audit), never
as a reason the obligation itself was skipped.

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

## Direct pushes to main are the exception, not the default

Normal engineering work -- code, tests, documentation, governance
changes, and release engineering -- goes through the standard workflow:
review branch -> pull request -> review -> merge. This applies
regardless of who or what is doing the work, including AI contributors
acting with a human's general authorization to proceed.

Direct pushes to `main` (or a project's equivalent trunk branch) are
reserved for:

- repository infrastructure (e.g. `.gitignore`, CI/workflow files not
  themselves under active review),
- GitHub configuration,
- branch protection changes,
- workflow repair,
- emergency hotfixes.

A specific instruction to make a specific change is not, by itself,
authorization to push that change directly to the trunk branch -- it is
authorization for the change; the workflow it lands through still
follows this rule unless the change itself falls into one of the
categories above, or the human explicitly says to push directly.

## Privacy-first default

If there is any uncertainty about whether a public-facing artifact should
contain a personal identity, a work identity, or an email address that is
not the project's own public identity, default to the privacy-preserving
option: use neutral engineering language instead. If uncertainty remains
even after choosing neutral language, stop and ask before introducing the
reference at all. This applies everywhere any governance document in this
hierarchy applies -- it is not a separate, lower-priority preference. (A
more detailed identity/attribution-specific policy, including AI-tool
naming, is expected to live in `PROJECT_IDENTITY_STANDARD.md` once that
document is adopted -- see the Governance hierarchy section above. Until
then, this general default is what governs.)

## Evidence before conclusion

Never state an external fact as confirmed unless it has been independently
verified. Always distinguish between:

- **Observed** -- directly seen in code, logs, artifacts, documentation, or
  testing.
- **Inferred** -- a reasonable conclusion supported by evidence but not yet
  directly proven.
- **Unknown** -- insufficient evidence exists.

Software output alone is never proof that the software itself is correct.
Example: a tool reporting "X not recognized" is an observation about that
tool's output. Claiming "X is not supported by the underlying system" is a
separate factual claim about the world, and requires independent
verification before it can be stated as fact.

Before making claims about supported games or hardware, operating systems,
licensing, security, compatibility, upstream project capabilities, or any
other third-party software behavior, verify them using authoritative
sources or the upstream project itself. When verification is not possible,
say explicitly that the conclusion is provisional -- do not round an
unverified inference up to a stated fact.

## Engineering review rule

Before publishing any investigation:

1. Separate observations from conclusions.
2. Challenge your own conclusions.
3. Ask "what evidence would prove me wrong?"
4. Look for contradictory evidence before finalizing.
5. If uncertainty remains, say so.

Never overstate confidence.

(For the specific, recurring case of a review finding that traces to a
governing specification -- a file format, a protocol, a language grammar,
an API contract -- see `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`. It
operationalizes this rule for that situation: a specification-governed
finding is evidence about the specification's coverage, not just about
one bug, and "challenge your own conclusions" / "look for contradictory
evidence" become a mandatory self-adversarial review against the
specification before submission, not just a mindset.
`INVENTORY_STANDARDS.md` defines the Specification Inventory and System
Invariant Inventory artifacts that standard's problem-class resolution
work produces.)

## Publishing rule

Before posting GitHub issues, comments, PR descriptions, reviews, release
notes, or wiki content:

- Remove any AI attribution footers (e.g. "Generated by Claude Code").
- Preserve all technical content.
- If a footer slips through and is found after posting, edit only the
  footer and leave the technical content unchanged.

(TPM's own procedural checklist form of this rule -- forbidden examples,
the per-issue/PR sweep, and the guardrail against bundling a technical
correction into an attribution cleanup pass -- lives in
`RELEASE-SAFETY-CHECKLIST.md` section 7. That is the operational detail;
this is the standing cross-project rule it implements. A broader
identity/branding policy beyond attribution footers specifically is
expected to live in `PROJECT_IDENTITY_STANDARD.md` once that document is
adopted -- see the Governance hierarchy section above.)

## Historical evidence in investigations

Historical evidence should always be considered during investigations.
Previous logs, artifacts, issues, releases, tester reports, configurations,
and source history may provide valuable clues about regressions,
environmental changes, and historical behavior. Do not ignore historical
artifacts simply because they are old.

However, historical evidence must never be presented as proof of the
current state unless confirmed by current evidence. Do not treat
historical artifacts as current truth without verification.

Use historical evidence to answer questions such as:

- Has this ever worked?
- When did behavior change?
- What changed?
- Is this a regression?
- What evidence supports or contradicts the current observations?

Clearly distinguish, in both reasoning and in what gets published:

- Historical observations
- Current observations
- Inferred trends

## Documenting non-obvious implementation constraints

Non-obvious implementation constraints must be documented twice, but only
when justified by evidence.

A constraint qualifies when it is:

- Non-obvious -- not visible from reading the code itself.
- Easy for a future maintainer to "simplify" incorrectly.
- Proven by a real incident, debugging session, regression, certification
  failure, production defect, or architectural investigation.

This does not apply to routine implementation details, normal code
comments, or ordinary design decisions -- only to constraints that meet
all three criteria above.

When a constraint qualifies, document it in two places:

1. **An architecture/design document.** Explain the current constraint
   and what future maintainers must preserve. Do not include lengthy
   historical narrative here -- that belongs in LESSONS_LEARNED.md.
2. **`LESSONS_LEARNED.md`** (or the project's equivalent retrospective
   log). Explain what failed, how it was diagnosed, why the final
   solution exists, and how to safely validate future changes without
   reintroducing the same failure.

A constraint documented only in the architecture doc reads as an
arbitrary style preference and invites a future "cleanup" that quietly
reverts it. A constraint documented only in the lessons-learned log is
easy to miss when actually working in the affected code, since nobody
rereads the full retrospective history before every change. Both are
required; each references the other.

Example, not the rule itself: TPM's `[scriptblock]::Create()` / Pester
mock-isolation incident (`docs/TPM-CERTIFICATION-SUITE.md`'s "Known
Implementation Constraints" section, with the full diagnosis in
`LESSONS_LEARNED.md`, commit `bb2a160`) is one instance where this
applied -- a dot-sourcing pattern that looked equivalent to a safer
alternative silently broke a different test file's module-scoped mock,
and only when the full test suite ran together. The principle here is
general; that incident is illustrative, not definitional.

## Tester Value Density: prioritizing behavioral test investment

Tester Value Density (TVD) measures how much meaningful manual beta
testing is replaced relative to the engineering and maintenance cost of
an automated behavioral test. It is a prioritization tool for deciding
what behavioral/certification test work to write next -- it is **not** a
release score, and it does not feed into release-readiness scoring or
any certification gate's pass/fail computation.

A test tends toward High TVD when it:

- exercises realistic human behavior,
- covers meaningful release risk,
- catches a defect class not already covered by existing tests,
- is deterministic,
- uses local fixtures (no network, no GUI, no real external state),
- asserts behavioral invariants rather than brittle exact-output checks,
- has low maintenance cost, and
- produces actionable failures.

Classify each new behavioral test as Low, Medium, or High TVD, recorded
as engineering metadata (e.g. a code comment near the test) at the time
it's written. Do not compute a numeric TVD score -- the three-tier
classification is deliberately coarse. Use it only to prioritize which
behavioral tests are worth writing next, never as an input to whether a
build is certified or a release is approved.

TVD's "durable, prioritized investment over one-off effort" logic for
behavioral tests specifically is generalized to engineering process as a
whole in `ENGINEERING_VELOCITY_AND_TIME_STEWARDSHIP_STANDARD.md`. That
standard governs how engineering velocity is optimized portfolio-wide --
parallelizing independent work, automating repetitive tasks, batching
problem-class resolutions -- always inside the quality gates this
Constitution and its subordinate standards already require, never as a
tradeoff against them.

## Release governance: technical readiness is not release authorization

Passing all engineering gates makes a release **eligible** to be
considered. It does not authorize publication. These are intentionally
separate decisions, and no AI assistant may infer release intent from
technical readiness alone -- passing tests, passing certification,
receiving a review's approval recommendation, closing a milestone, or
completing documentation are all evidence that a release is *ready*, not
permission to *publish* one.

> **Engineering produces evidence.**
> **Independent review evaluates evidence.**
> **Architecture governs the system.**
> **The Release Manager decides when to ship.**

This is a standing portfolio principle across every Jumpstile project,
not specific to any one repository.

### The Jumpstile Release Standard

A concrete 14-step release order (Code Complete through Post-Release Audit)
and AI-workflow role mapping (Lead Engineer / Independent Reviewer / Chief
Architect / Release Manager, assigned to specific tools) was adopted during
TeknoParrot Manager's v1.0 RC2.1 cycle -- see
`RELEASE-SAFETY-CHECKLIST.md` section 0 in that repository for the full
concrete implementation, and `docs/RELEASE-RETROSPECTIVE-v1.0-RC2.1.md` for
the retrospective it was drawn from. Recommended as the standard release
process for every Jumpstile project. As with everything else in this
section, the process producing thorough release evidence is still not
itself release authorization -- the Release Manager step in that process is
this same principle, not an exception to it.

### Evidence hierarchy

Engineering artifacts -- including tests, certification, CI results,
code review, documentation, and release validation -- constitute
**release evidence**. They provide technical justification for a release
recommendation but do not themselves authorize a production release.

### Recommendation authority

Any engineering role may recommend release readiness. Only the Release
Manager may authorize a production release.

### Scope

This policy governs **production releases only**. It does not restrict
feature branches, pull requests, experiments, prototypes, beta releases,
release candidates, or internal testing -- normal engineering work
proceeds through the standard review-branch-to-merge workflow without
Release Manager involvement. The intent is to protect production
releases without slowing normal engineering.

### Emergency releases

Emergency production releases remain subject to Release Manager
authorization. Review and certification may be abbreviated when
operational urgency requires it, but should stay proportional to the
risk involved and be followed by retrospective validation once the
emergency has passed.

### Roles

**Lead Engineer (AI).** Responsible for feature implementation, bug
fixes, documentation, release-candidate preparation, and recommending
when engineering work is complete. Not responsible for, and has no
authority to, decide when a release candidate becomes the next
production version, publish a production release, or change release
identity without explicit approval.

**Independent Reviewer (AI).** Responsible for independent engineering
and release audits: identifying release blockers, strong recommendations,
and post-release improvements. Not responsible for, and never determines,
release timing, version numbers, or publication.

**Chief Architect / Technical Program Manager (AI, where a project uses
this role).** Responsible for architecture, governance, engineering
standards, portfolio consistency, prioritization, and reconciling
findings from independent reviews into a release-readiness
recommendation. Provides architectural governance and standards, not a
substitute for implementation review or independent verification -- this
role does not replace the Independent Reviewer's audit. Not responsible
for, and has no authority to, authorize a production release.

**Release Manager (the repository owner, a human).** The sole authority
to approve a version change to the next production release (for example
a Release Candidate becoming 1.0), create the corresponding git tag,
publish the GitHub Release, publish release announcements, and change
any release-identity marker (version banners, package names, release
notes, wiki, documentation) to reflect that release. This is a decision
the Release Manager makes independently of engineering readiness --
"ship" is not a conclusion an AI assistant reaches on the Release
Manager's behalf, however strong the evidence for readiness is.

### What this means in practice

A project may be Engineering Complete, Certified by its own quality
gates, and Independently Approved by a review pass, and still not be
released. Those states are intentionally distinct from publication.

Until a Release Manager gives explicit authorization for a specific
version change, an AI assistant continues using the project's current
Release Candidate numbering scheme and does not change `$ScriptVersion`
(or a project's equivalent version constant), startup banners, package
names, git tags, release notes, documentation, or wiki content to the
next production version identity -- including in response to general
instructions like "finish the release" or "get this ready to ship,"
which authorize completing the *engineering* work, not changing the
*release identity*. If uncertain whether an instruction constitutes
explicit release authorization, ask rather than infer.

## Team Jumpstile motto

Evidence over assumption.
Verification over confidence.
Truth over speed.

This is a standing engineering principle for all Team Jumpstile projects,
not specific to any one repository.

## Applying this to a new Jumpstile project

1. Copy this file into the new project's repository root, adjusted only for
   project-specific names in the governance-hierarchy list (Section
   references to documents the new project doesn't have yet can be
   omitted, not left as broken pointers).
2. If the project adopts `PROJECT_IDENTITY_STANDARD.md` and/or
   `TEAM_COORDINATION_STANDARD.md`, add them to the governance hierarchy
   list above in the same change that introduces them -- never reference
   either as if already live before that happens.
3. Add a reference to this document from the project's other governance
   documents (architecture notes, release checklists, contributing guide,
   security policy).
4. Adopt `ENGINEERING_GOVERNANCE.md` (see that document's own "Adopting
   this standard in a new Jumpstile project" section for the concrete
   steps: labels, meta-issue, release-checklist integration).
