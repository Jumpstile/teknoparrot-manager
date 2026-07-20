# Specification Inventory and System Invariant Inventory Standard

Status: canonical Engineering System standard, adopted for TeknoParrot
Manager and the template for every Jumpstile project. Companion document
to `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`, which requires these
artifacts; this document defines what they are, when each is required,
and how to build one. Repository-agnostic: every example below is
illustrative.

---

## Why these exist

`SPECIFICATION_DRIVEN_REVIEW_STANDARD.md` requires resolving the *entire
applicable family* of rules a specification defines, not just the one
rule a review finding happened to violate. That requirement is only as
good as the implementer's ability to actually enumerate the applicable
family. Recalling a specification's rules from memory, under review
pressure, one gap at a time, is exactly the failure pattern that standard
exists to prevent (see its "Motivating incident").

An **Inventory** -- a Specification Inventory or a System Invariant
Inventory -- replaces "recall the rules from memory" with "consult a
written list built by actually reading the source of truth." It is a
work product, not a formality: building one is often what *reveals* the
remaining gaps, before a reviewer has to find them one at a time.

## Two kinds of inventory, and why both

A component's correctness has two distinct sources of "what must be
true":

- **External conformance** -- rules imposed by something outside the
  project's own control: a file format, a protocol, a language grammar,
  a regulatory requirement, a third-party API contract. The source of
  truth is the external specification document.
- **Internal correctness** -- properties the system promises to maintain
  regardless of what any external specification says: "this operation
  never leaves the target file in a partially-written state," "this
  restore always leaves the original byte-for-byte unchanged,"
  "certification scoring never double-counts a check," "this validator
  never reports success without every layer of validation actually
  passing." The source of truth is the project's own design intent --
  often not written down anywhere before the invariant inventory is
  built.

**A Specification Inventory** enumerates the first kind. **A System
Invariant Inventory** enumerates the second. They complement each other:
a component can be perfectly conformant with an external specification
and still violate an internal invariant (a PNG parser can correctly
reject every malformed chunk the spec defines and *still* leave a file
handle locked, or still let a validation failure be silently reported as
success). Neither inventory substitutes for the other; a Review Ready
submission for a component with both kinds of requirement needs both.

## Requirement levels

This document, `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`, and every other
document that references either inventory type use exactly these four
terms, consistently, and no others, to describe whether an inventory (or
an item within one) applies:

- **REQUIRED** -- the inventory (or item) must exist and be current before
  the work it governs is Review Ready (`SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`'s
  Definition of Review Ready) or before a release that touches the
  governed component (`RELEASE-SAFETY-CHECKLIST.md`). Absence is a gap,
  not a judgment call.
- **RECOMMENDED** -- strongly encouraged, produces real velocity and
  quality benefit (see "How they reduce review cycles, risk, and improve
  velocity" below), but its absence does not by itself block Review Ready
  or a release. An Independent Reviewer may still ask for one if its
  absence makes the review meaningfully harder.
- **OPTIONAL** -- may be built if the implementer or reviewer judges it
  useful; absence carries no review or release consequence and requires
  no justification.
- **NOT APPLICABLE** -- the trigger conditions for this inventory type
  genuinely do not apply to this component. Recorded, not silently
  assumed (see "Ownership and lifecycle" below for who records this and
  how).

Earlier drafts of this standard and `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`
used softer, inconsistent language in places ("strongly recommended,"
"ideally") for cases that are actually REQUIRED under the rule below. That
inconsistency is resolved: wherever this document says REQUIRED, treat
every softer phrasing elsewhere as an error in that document to be
corrected on sight, not as a genuine exception.

## When each requirement level applies

### Specification Inventory

**REQUIRED** whenever `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md` applies at
all -- i.e., whenever a review finding, or the area of work under review,
traces to a governing external specification (a file format, a protocol,
a language grammar, an API contract, a regulatory rule). This is the
*entire* trigger; there is no additional "is it worth it" judgment call
once that condition is met. Build (or update) the inventory before
implementing further fixes, not after. (`SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`
Section 2's "strongly recommended... whenever non-trivial to enumerate
from memory" and Definition of Review Ready item 3's "ideally checked" are
both superseded by this REQUIRED rule -- see the note above.)

There is no NOT APPLICABLE case for a Specification Inventory once
`SPECIFICATION_DRIVEN_REVIEW_STANDARD.md` applies -- if the work is
specification-governed at all, an inventory is required. Work that is not
specification-governed (no external file format/protocol/grammar/contract
involved) is simply outside this inventory type's scope entirely, which is
a different statement than "not applicable": `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`
itself doesn't apply, so this inventory type's requirement question never
arises.

### System Invariant Inventory

**REQUIRED** when a component meets at least one of the following
objective triggers:

- It implements or governs **workflow orchestration** -- a sequence of
  steps with an outcome that depends on their order, completeness, or
  interdependency (e.g. a multi-phase setup process, a pipeline).
- It implements or governs a **certification, gating, or scoring system**
  -- any component whose output is a pass/fail or scored decision other
  code or a human relies on as evidence of correctness.
- It implements **transaction processing or a commit protocol** -- any
  operation with an explicit "did this succeed as a whole, or not at all"
  semantic (staged writes, atomic promotion, rollback).
- It implements **synchronization or concurrency coordination** -- shared
  mutable state accessed from more than one execution context, a lock, a
  queue, or an ordering guarantee between concurrent operations.
- It implements a **state machine** with more than two meaningfully
  distinct states (a simple boolean flag does not trigger this on its
  own).
- It implements **replication or distributed coordination** -- state kept
  consistent across more than one process, machine, or storage location.
- It has already been the subject of **two or more independent review
  rounds that each found a genuinely new defect class** (not a repeat or
  variant of a previously-found class) -- this is the objective,
  retrospective trigger for "does this still work correctly can no longer
  be answered by rereading the code once," replacing the earlier
  subjective "typically once a component has accumulated several rounds
  of fixes" wording.
- It is about to undergo a **significant refactor that changes its
  internal state or object-ownership model** -- build (or update) the
  inventory before the refactor, so the refactor has a checkable list of
  properties to preserve.

**RECOMMENDED** when a component has non-trivial internal state or
multi-step behavior but meets none of the REQUIRED triggers above -- e.g.
a moderately complex validator with several internal steps but no
orchestration, transaction, or concurrency dimension.

**NOT APPLICABLE**, explicit examples:

- A pure function -- same input always produces the same output, no side
  effects, no persisted state, no ordering dependency (e.g. a string
  formatter, a unit converter, a simple predicate).
- A component whose entire correctness surface is already covered by a
  Specification Inventory, with no internal guarantee beyond conformance
  to that external specification (rare in practice -- most real components
  have at least one internal guarantee beyond the spec, such as "never
  leaves a partially-written file behind," so this should be treated as
  an exceptional case requiring explicit justification, not a default
  assumption).
- A read-only rendering/reporting function whose only job is to format
  already-validated, already-decided data for display, with no decision
  logic of its own (e.g. a Markdown report line generator that only
  interpolates fields it did not compute).
- Short-lived glue/wiring code with no state and no branching logic worth
  independently verifying (e.g. a one-line parameter pass-through).

Many components need both a Specification Inventory and a System
Invariant Inventory, maintained side by side (see the worked example
below).

## How they integrate into Review Ready

`SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`'s Definition of Review Ready,
item 3, requires every rule in the applicable family to be implemented,
"checked against a Specification Inventory... not recalled from memory"
-- REQUIRED, per this document's "Requirement levels" above, not optional
or "ideal." Item 7 requires prior behavior to be confirmed unchanged;
"where the component meets a System Invariant Inventory REQUIRED
trigger... that inventory confirms those invariants are also unchanged."
Concretely:

1. Build or update the relevant inventory (or inventories) before
   implementing.
2. Mark every item's status honestly (see below) -- this is the
   self-adversarial review's structured form, not a separate step.
3. Implement every `Missing` in-scope item.
4. Write regression coverage keyed to inventory items, not just to the
   originally reported case (`SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`
   Section 5) -- a test suite that visibly maps to inventory rows is
   itself evidence the defect class was actually covered, not just the
   instance.
5. Attach the completed inventory (or a link/reference to it) to the
   submission as part of the Review Ready evidence.

## How they reduce review cycles, risk, and improve velocity

An inventory converts an open-ended "did we get everything?" question --
which a reviewer can only answer by independently re-deriving the same
list the implementer should have already built -- into a closed,
checkable list both sides can audit against the same source of truth.
This is a direct application of
`ENGINEERING_VELOCITY_AND_TIME_STEWARDSHIP_STANDARD.md`'s "batch related
work into complete problem-class resolutions" and "reduce unnecessary
engineer decision points" principles:

- **Fewer review round trips.** Each round-trip in the motivating
  incident behind `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md` cost a full
  implement/test/review cycle to find one gap an inventory would have
  surfaced immediately. An inventory built once amortizes across every
  future round of work on that component.
- **Lower risk of regression.** A System Invariant Inventory turns
  "we're pretty sure nothing else broke" into a specific list of
  properties re-checked -- exactly the evidence
  `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`'s Review Ready item 7 asks
  for.
- **Durable, not one-off.** The inventory itself is a maintained
  artifact -- update it in place as scope changes, rather than
  rebuilding the enumeration from scratch on the next round. This is the
  Time Stewardship standard's "prefer durable improvements over one-off
  optimizations" principle applied to review artifacts specifically.
- **Faster independent review.** A reviewer auditing against a
  pre-built, honestly-marked inventory spends their time verifying the
  inventory's accuracy and the marked items' implementation, not
  re-deriving the applicable rule family from the specification
  themselves -- the same verification work happens once, by the
  implementer, instead of twice.

---

## Building a Specification Inventory

A Specification Inventory is a short document (or a section of one) that
answers, for a single component and a single governing specification:

1. **Governing source.** The exact specification, edition/version, and
   (where the spec is large) the specific sections relevant to this
   component.
2. **In scope.** Every rule family the component is expected to enforce,
   grouped by area (e.g. "framing and bounds," "required elements and
   their ordering," "value validity"). Specific enough that a reviewer
   could check each line against the spec text directly.
3. **Deliberately out of scope.** Every rule family the component
   consciously does not enforce, and why -- per
   `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md` Section 6, "too much work"
   is not an acceptable reason; the actual reason is (e.g.) that it
   belongs to a different problem than this component solves, or that a
   downstream layer already owns it.
4. **Layering note**, where applicable -- how this component's
   conformance check relates to other validation layers around it (e.g.
   "structural success alone never produces a passing result; a
   downstream decode/format layer still has to succeed too").

### Worked example (TeknoParrot Manager, illustrative)

`docs/PNG-EVIDENCE-VALIDATOR-SPECIFICATION-INVENTORY.md`, in the
`Jumpstile/teknoparrot-manager` repository specifically, is a real
instance of this pattern, written for `Test-TPMPngStructure` (that
project's certification screenshot evidence validator) against the W3C
PNG specification. It is referenced here as a concrete template new
inventories can follow, not duplicated into this document -- read it
directly (in that repository) for the worked example. A project adopting
this standard will not have this specific file; build its own worked
example under its own `docs/` (or equivalent) as its first
specification-governed component reaches this point.

---

## Building a System Invariant Inventory

A System Invariant Inventory is a short document (or a section of one)
that answers, for a single component, "what must always be true about
this component's behavior, independent of any external specification?"

1. **Component and boundary.** What the component is responsible for,
   and what it explicitly is not (its boundary with adjacent
   components).
2. **Invariants.** Each stated as a concrete, checkable property, not a
   vague goal -- "the original file's byte content is restored exactly,
   even if the operation that used it throws" is checkable; "config
   handling is safe" is not. Group by area if the component has several
   (e.g. "file-safety guarantees," "state-machine guarantees," "scoring
   guarantees").
3. **How each is currently verified.** A specific test, assertion, or
   mechanism -- not "it should work." An invariant with no verification
   mechanism is a gap, marked `Missing`, the same as an unimplemented
   specification rule.
4. **Failure mode if violated.** What actually goes wrong if this
   invariant breaks -- this is what makes an invariant worth tracking
   rather than an arbitrary implementation detail; if nothing
   observable would go wrong, it may not be a real invariant.

### Example invariants (illustrative, not a fixed list)

- "A capture is never reported as successful evidence unless every
  validation layer -- structural, format, decode, dimension -- actually
  passed" (verified by: the layered-validation regression tests; failure
  mode if violated: certification evidence looks trustworthy but isn't).
- "A configuration file temporarily modified for one operation is
  restored to its exact original byte content afterward, even if that
  operation throws" (verified by: a restore-after-exception regression
  test comparing before/after bytes; failure mode if violated: a
  developer's real saved settings are silently corrupted by an
  unattended run).
- "Certification scoring never counts the same check twice, and evidence
  capture (screenshots, logs) never itself affects the score" (verified
  by: score-isolation regression tests; failure mode if violated: a
  passing score stops meaning what it claims to mean).

---

## Status marking (both inventory types)

Every *item* within an inventory (not the inventory's own REQUIRED/
RECOMMENDED/OPTIONAL/NOT APPLICABLE requirement level -- see "Requirement
levels" above, a separate axis) is marked one of:

- **Implemented** -- enforced/verified now, with a pointer to where
  (function name, test name).
- **Missing** -- in scope, not yet enforced/verified. Every `Missing`
  in-scope item is a to-do for the current round, per
  `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md` Section 2.
- **Intentionally out of scope** -- a documented, reasoned decision per
  `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md` Section 6, not silence. This
  marks an *engineering* scoping decision only -- see "Inventories define
  engineering scope only" below for what this status must never be used
  to represent.

A submission is not Review Ready while any in-scope item is marked
`Missing`.

### Distinguishing intentional absence from a missing requirement

The status markings above are for items *within* an inventory. A
reviewer must also be able to tell, at a glance, why an entire inventory
is absent for a given component -- "this inventory does not exist because
it was never required" reads identically to "this inventory does not
exist because it was required and nobody built it" unless the reason is
stated explicitly. When a component's Specification Inventory or System
Invariant Inventory does not exist, record which of these is true,
alongside the component (in its own doc header, the governing PR/issue,
or both):

- **"NOT APPLICABLE -- \<trigger condition\> does not apply to this
  component."** A deliberate, reasoned determination against the
  objective triggers in "When each requirement level applies" above --
  the same evidentiary bar as an item marked `Intentionally out of
  scope`.
- **"OPTIONAL -- not built."** The component meets no REQUIRED trigger
  and a RECOMMENDED-or-lower inventory was judged not worth building this
  round. Carries no review or release consequence, but is still stated,
  not left to be inferred.
- **A REQUIRED inventory that is simply absent is not a valid state to
  report at all** -- it is a Review Ready blocker (per "Requirement
  levels" above), reported as a gap to close, never phrased as though it
  were a scoping decision.

### Row-level traceability (both inventory types)

Every item within either inventory type -- a rule family in a
Specification Inventory's "In scope" list, an invariant in a System
Invariant Inventory -- carries a **stable identifier** in addition to its
status marking, so it can be referenced unambiguously by implementation
code, tests, review comments, issues, and release certification evidence
across revisions, without anyone having to re-describe the item in prose
each time. Concretely, each item records:

- **Stable identifier.** A short, namespaced ID (e.g. `PNG-CHUNK-ORDER-003`,
  `SII-CERT-SCORE-002`) assigned when the item is first added and never
  reassigned to a different item afterward, even if the item's wording is
  later refined. If an item is removed, its identifier is retired, not
  reused for something else -- a stale reference to a retired ID should
  fail loudly (point at nothing), never silently point at an unrelated
  later item.
- **Governing-source citation** (Specification Inventory items) or
  **invariant statement** (System Invariant Inventory items, per
  "Building a System Invariant Inventory" below) -- what the item
  actually requires, specific enough to check directly.
- **Implementation pointer.** The function, module, or code location that
  enforces the item, once `Implemented`.
- **Verification pointer.** The specific test (by name) that verifies it,
  once `Implemented` -- this is what "Write regression coverage keyed to
  inventory items" (see "How they integrate into Review Ready" above)
  concretely means: the test name and the item's stable identifier should
  be cross-referenceable in both directions.

A table is the natural format for this (columns: ID, description/
citation, status, implementation pointer, verification pointer), but the
requirement is the content, not a specific document format.

### Inventories define engineering scope only

An inventory -- either type, and every status an item within one can
carry, including `Intentionally out of scope` -- defines what a component
is engineered to verify. It is never authority to exclude, narrow, defer,
or deprioritize a legal requirement, regulatory requirement, compliance
obligation, safety requirement, security requirement, or organizational
policy. Those always take precedence over anything an inventory says,
per `CONSTITUTION.md`'s "Legal, regulatory, and safety obligations sit
outside and above this hierarchy." If such an obligation applies to a
component, it applies in full regardless of whether the inventory
enumerates it; where it's useful to note the obligation in the inventory
at all, note it as a cross-reference to the control that actually
satisfies it (`SECURITY.md`, a compliance policy, an external audit --
whatever governs it in this project), never mark it `Intentionally out of
scope` as if the inventory itself were the authority that decided to skip
it.

---

## Ownership and lifecycle

Inventories are living engineering artifacts, not one-time deliverables
filed away once a finding closes.

- **Who creates one.** For a **REQUIRED** trigger, the Implementer must
  build the inventory -- this is not discretionary, per "Requirement
  levels" above. For a **RECOMMENDED** trigger, building one is the
  Implementer's judgment call, not an obligation; a RECOMMENDED inventory
  that is never built carries no review or release consequence (again,
  per "Requirement levels" -- RECOMMENDED absence is legitimate on its
  own, and this lifecycle section does not silently upgrade it to
  REQUIRED). If a RECOMMENDED inventory *is* built, the Implementer who
  built it owns it going forward, the same as a REQUIRED one. Either way,
  inventory work typically happens while resolving the review finding
  that revealed the need for one, per `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`
  Section 2.
- **Who updates one.** Whoever next touches the governed component in a
  way that could change the inventory's accuracy -- a new rule from an
  updated external specification, a newly discovered internal invariant,
  a changed component boundary, or a refactor. Updating the inventory is
  part of that round's work, in the same PR, not a follow-up task.
  Letting an inventory go stale while continuing to change the component
  it describes is equivalent to not having built one.
- **When it must be reviewed.** At minimum: (1) whenever the Independent
  Reviewer audits a submission that touches the governed component
  (`SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`'s Responsibilities section);
  (2) during the Documentation Sweep and Release Integrity Audit for any
  release that includes a change to the governed component
  (`RELEASE-SAFETY-CHECKLIST.md` sections 3 and 5, where adopted); (3)
  before a significant refactor of the governed component begins.
- **What events require revision**, explicitly: the governing external
  specification is updated to a new version; a review finds a defect
  class the inventory did not anticipate; the component's responsibility
  or boundary with an adjacent component changes; a new internal
  guarantee is deliberately added or removed; the component is
  deprecated or retired.
- **Relationship to PR review.** The inventory (or a link/reference to
  it) is Review Ready evidence, audited by the Independent Reviewer as
  part of the same review pass as the code change -- not a separate
  approval gate, and not something the Independent Reviewer takes on
  faith from the implementer's summary of it.
- **Relationship to release certification.** Per `CONSTITUTION.md`'s
  evidence hierarchy, a current, accurate inventory is release *evidence*
  -- it demonstrates the governed component was verified against a
  checkable list -- never release *authorization*. Where a project's
  release process includes a Documentation Sweep or Release Integrity
  Audit (`RELEASE-SAFETY-CHECKLIST.md` sections 3 and 5 in this
  repository), confirming each REQUIRED inventory is current is part of
  that audit.
- **Archival.** An inventory for a retired or removed component is not
  deleted -- it is moved to an archive location (e.g. `docs/retired/`, or
  this project's existing archival convention) with a note recording why
  the component was retired and when. This preserves the institutional
  memory of what was verified and why, consistent with `CONSTITUTION.md`'s
  "Historical evidence in investigations" principle -- a deleted inventory
  looks identical to one that was never built, to a future engineer
  trying to understand what used to be true about a now-removed
  component.

---

## Responsibilities

Ownership of building, maintaining, and auditing inventories follows
`SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`'s existing Responsibilities
section (Implementer / Independent Reviewer / Chief Architect / Release
Manager) -- this document does not define a separate set of roles. The
Implementer builds and updates the inventory as part of problem-class
resolution (see "Ownership and lifecycle" above for the concrete
create/update/review triggers); the Independent Reviewer audits it for
completeness against the actual governing specification or actual system
behavior, not just against the implementer's own summary; the Chief
Architect judges whether out-of-scope markings are architecturally sound
(and, per "Inventories define engineering scope only" above, confirms no
out-of-scope marking is being used to sidestep a legal/regulatory/safety/
security/policy obligation); the Release Manager's role is unchanged
(inventory completeness is release evidence, not release authorization).

---

## Adopting this standard in a new Jumpstile project

1. Copy this file into the new project's repository root.
2. Adopt `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md` in the same change, if
   not already adopted -- these two documents are meant to be adopted
   together.
3. Add it to that project's `CONSTITUTION.md` governance-hierarchy list,
   alongside `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`.
4. Reference it from that project's `RELEASE-SAFETY-CHECKLIST.md` and AI
   onboarding documentation at the same point
   `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md` is referenced.
5. As components accumulate specification- or invariant-governed
   findings, start their inventories under `docs/` (or that project's
   equivalent), following the worked example referenced above.
