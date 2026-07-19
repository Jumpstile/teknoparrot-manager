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

## When each is required

- **Specification Inventory**: required whenever
  `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md` applies -- i.e., whenever a
  review finding, or the area of work under review, traces to a governing
  external specification. Build (or update) the inventory before
  implementing further fixes, not after.
- **System Invariant Inventory**: required for any component whose
  correctness depends on internal guarantees that are not fully captured
  by an external specification (or that has no external specification at
  all, e.g. an internal state machine, a file-safety guarantee, a scoring
  computation). Build one whenever a component reaches the point where
  "does this still work correctly" can no longer be answered by rereading
  the code once -- typically once a component has accumulated several
  rounds of fixes, or before a significant refactor.
- Many components need both, maintained side by side (see the worked
  example below).

## How they integrate into Review Ready

`SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`'s Definition of Review Ready,
item 3, requires every rule in the applicable family to be implemented
"ideally checked against a Specification Inventory rather than recalled
from memory." Item 7 requires prior behavior to be confirmed unchanged,
"where the component maintains internal invariants beyond the external
specification, a System Invariant Inventory confirms those are also
unchanged." Concretely:

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

### Worked example

`docs/PNG-EVIDENCE-VALIDATOR-SPECIFICATION-INVENTORY.md` in this
repository is a real instance of this pattern, written for
`Test-TPMPngStructure` (the certification screenshot evidence validator)
against the W3C PNG specification. It is referenced here as the concrete
template new inventories should follow, not duplicated -- read it
directly for the worked example.

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

Every item in either inventory type is marked one of:

- **Implemented** -- enforced/verified now, with a pointer to where
  (function name, test name).
- **Missing** -- in scope, not yet enforced/verified. Every `Missing`
  in-scope item is a to-do for the current round, per
  `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md` Section 2.
- **Intentionally out of scope** -- a documented, reasoned decision per
  `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md` Section 6, not silence.

A submission is not Review Ready while any in-scope item is marked
`Missing`.

---

## Responsibilities

Ownership of building, maintaining, and auditing inventories follows
`SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`'s existing Responsibilities
section (Implementer / Independent Reviewer / Chief Architect / Release
Manager) -- this document does not define a separate set of roles. The
Implementer builds and updates the inventory as part of problem-class
resolution; the Independent Reviewer audits it for completeness against
the actual governing specification or actual system behavior, not just
against the implementer's own summary; the Chief Architect judges whether
out-of-scope markings are architecturally sound; the Release Manager's
role is unchanged (inventory completeness is release evidence, not
release authorization).

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
