# Specification-Driven Review and Problem-Class Resolution Standard

Status: canonical Engineering System standard, adopted for TeknoParrot
Manager and the template for every Jumpstile project. Promoted from
`Jumpstile/teknoparrot-manager#153`, which records the motivating incident
and the original draft. This document governs how implementation work
responds to a review finding that traces to a governing specification (a
file format, a protocol, a language grammar, an API contract, a
regulatory rule) -- not how work is tracked (`ENGINEERING_GOVERNANCE.md`)
and not how releases are authorized (`CONSTITUTION.md`'s release
governance section, which this document does not alter or supersede).

This document is repository-agnostic. Every path, tool name, and example
below is illustrative; nothing in this standard depends on TeknoParrot
Manager's specific stack. See `INVENTORY_STANDARDS.md` for the concrete
artifact (a Specification Inventory) this standard's Section 2/3 work
produces, and `ENGINEERING_VELOCITY_AND_TIME_STEWARDSHIP_STANDARD.md` for
how resolving a full problem class in one round -- what this standard
requires -- is also the higher-velocity path, not a tradeoff against it.

---

## Motivating incident

TeknoParrot Manager PR #152 (issue #151, automatic certification
screenshot capture) went through five independent-review rounds against
its PNG evidence-validation logic. Each round fixed exactly the one gap
the previous round's review found -- filename collisions, then
JPEG-content-masquerading-as-PNG, then truncation, then CRC integrity,
then chunk ordering/uniqueness -- without ever stepping back to ask "what
does the governing specification require in full, and have I checked all
of it?" Every individual fix was correct and well-tested against the
specific case reported. None of them addressed the underlying pattern
until explicitly instructed to. A sixth round, driven by a Specification
Inventory built before writing any more code, closed the remaining gaps
(reserved-bit validation, IHDR dimension bounds, and ordering/multiplicity
rules for every registered ancillary chunk the validator recognizes) in
one pass instead of three more single-issue round trips.

A reviewer finding one instance of a specification-governed problem is
evidence about the specification's *coverage*, not just about one bug.
The correct response is to close the family of gaps the specification
defines, not to patch the one instance and wait for the next review round
to find the next one.

## Core principle

> A review finding that traces to a governing specification is evidence
> about the specification's coverage, not just about one bug.
> Fix the coverage gap, not the instance.

When a defect exists because an implementation didn't fully honor a
specification, the correct unit of work is "bring this implementation
into conformance with the specification," not "make this one failing
case pass." The narrower framing produces exactly the failure pattern
this standard exists to prevent: a review cycle that finds one gap, gets
a fix for that gap, and finds the next gap next time, indefinitely.

---

## 1. Specification-driven implementation

Implementation work on specification-governed behavior starts from the
specification, not from the existing code's assumptions about it and not
from the single case that prompted the work. Before writing or modifying
code that must conform to a specification, identify which specification
governs the behavior and treat it as the source of truth for what
"correct" means -- existing code, prior review comments, and even prior
passing tests are all secondary evidence, not substitutes for the
specification itself.

## 2. Problem-class resolution

When a review finding cites a specification, a standard, or a
well-defined rule set (not just "this specific input broke"), the
implementer's first obligation is to identify what *class* of problem the
finding represents, not just the reported instance.

Ask: "If I only fix the exact case that was reported, what other cases
governed by the same rule would still be broken?" If the honest answer is
"some," the finding has not been fully addressed yet, regardless of
whether the reported test case now passes.

Having identified the problem class, implement conformance with the
*entire* applicable family of rules the specification defines for the
affected area -- not only the rule the reported case happened to violate.
"Applicable" is doing real work in that sentence: this does not mean
re-implementing the entire specification end to end (see Section 6 on
documenting deliberate scope boundaries). It means solving every rule
that governs the actual area of behavior under review. If the finding was
about chunk ordering in a file format, the applicable family is that
format's ordering *and* uniqueness *and* required-element rules for the
chunks the implementation already handles -- not the one ordering rule
that was reported broken, and not chunk types the implementation has no
reason to ever encounter.

A **Specification Inventory** (see `INVENTORY_STANDARDS.md`) is the
concrete artifact that makes "the applicable family" a checkable list
instead of a judgment call repeated from memory every round. Building or
updating one before implementing is **REQUIRED** whenever this section
applies at all -- i.e. whenever a finding traces to a governing
specification, full stop, not only when the applicable family happens to
be "non-trivial to enumerate from memory." See `INVENTORY_STANDARDS.md`'s
"Requirement levels" section for the authoritative REQUIRED/RECOMMENDED/
OPTIONAL/NOT APPLICABLE rule this document defers to.

## 3. Mandatory governing-spec review

Before implementing a fix that touches specification-governed behavior,
read (or re-read) the actual governing specification for the affected
area -- not a summary, not a secondhand explanation, not "what the
existing code already assumes." When the governing document is large,
read the sections relevant to the affected behavior in full, not just the
clause that explains the one reported failure.

This is a prerequisite step, not an optional enrichment. Implementing a
fix without having read the governing specification is how problem-class
findings get treated as isolated-bug findings in the first place.

## 4. Mandatory self-adversarial review

Before submitting work for independent review (or re-review after
addressing prior findings), the implementer performs their own
adversarial review against the same governing specification, actively
trying to find the next gap an independent reviewer would find. This is
not a re-read of the diff -- it is a deliberate attempt to break the
implementation using the specification as the attack surface, the same
way an independent reviewer will.

Findings from this self-review are fixed in the same round, before
submission -- not deferred with a note to "catch it next time." A
self-adversarial review that finds nothing is a valid outcome and should
be reported as such (see the Review Ready checklist below); a
self-adversarial review that isn't performed at all is a process failure,
independent of whether the resulting submission happens to pass anyway.

## 5. Defect-class regression testing

Regression tests added in response to a specification-governed finding
must cover the defect *class*, not only the exact reported case.
Concretely:

- If the finding was "X is accepted when it should be rejected because of
  rule R," tests should cover rule R's boundary conditions (the exact
  violation, near-miss non-violations that must still be accepted, and
  where practical, sibling rules in the same family), not only the one
  specific input that was reported.
- Where a specification defines an enumerable set of valid/invalid
  combinations (e.g. a fixed table of legal value pairs), tests should
  exercise the table, not one row of it.
- Tests must prove the implementation's *logic*, not incidentally pass or
  fail for an unrelated reason. When a fixture could fail for multiple
  reasons (e.g. a malformed-checksum fixture that would also fail as
  malformed-structure), construct it so the specific rule under test is
  what actually determines the outcome.

## 6. Documented out-of-scope decisions

Not every rule in a governing specification belongs in every
implementation -- an evidence validator is not obligated to become a full
decoder, a protocol client is not obligated to implement every optional
extension, and so on. Deliberately choosing not to implement part of a
specification is a legitimate engineering decision.

What is not legitimate is leaving that decision implicit. Every
deliberately-out-of-scope rule or rule family must be documented, at the
point the scoping decision is made, with:

- what the rule is,
- why it's out of scope for this implementation specifically (not "too
  much work" -- the actual reason: it belongs to a different problem than
  the one this component solves, it's a decoder-compatibility signal
  rather than a correctness/corruption concern, it would require
  understanding domain semantics this component has no need to
  understand, etc.),
- and where a future maintainer or reviewer would look to find this
  decision again (a code comment, an architecture doc section, a
  Specification Inventory's "Deliberately out of scope" section -- see
  `INVENTORY_STANDARDS.md`).

An unstated scope boundary looks identical to an oversight to the next
reviewer. A stated one is a design decision they can agree or disagree
with, but not one they have to rediscover from scratch.

## 7. Formal review-readiness criteria

See "Definition of Review Ready" below. Work is not submitted (or
resubmitted) for independent review against a specification-governed
finding until it satisfies that definition, and the submission states
explicitly that it does.

---

## Definition of Review Ready

Specification-governed work is Review Ready only when **all** of the
following are true, and the implementer has said so explicitly in the
submission:

1. The finding has been generalized to its problem class (Section 2).
2. The governing specification's relevant sections have been read or
   re-read for this round (Section 3).
3. Every rule in the identified applicable family is implemented, not
   only the originally reported one (Section 2) -- checked against a
   Specification Inventory (`INVENTORY_STANDARDS.md`, REQUIRED whenever
   this standard applies -- see that document's "Requirement levels"),
   not recalled from memory.
4. A deliberate self-adversarial review was performed against the
   specification, and everything it found was fixed in this same round
   (Section 4).
5. New regression tests exercise the defect class, including
   boundary/table coverage where the specification defines one
   (Section 5).
6. Anything from the governing specification deliberately left
   unimplemented is documented with its rationale (Section 6).
7. Prior layered defenses, tests, and behavior outside the current
   finding's scope are confirmed unchanged -- problem-class resolution
   work must not weaken what was already correct. Where the component
   meets a System Invariant Inventory REQUIRED trigger
   (`INVENTORY_STANDARDS.md`'s "Requirement levels"), that inventory
   confirms those invariants are also unchanged.
8. Verification evidence (the actual commands run and their results --
   test totals, static analysis, linting, or whatever the project's
   standard verification set is) is reported alongside the submission,
   not asserted without evidence.

A submission that cannot honestly satisfy all eight items is not yet
Review Ready, regardless of whether the originally reported case now
passes.

---

## Responsibilities

**Implementer.** Owns specification-driven implementation, problem-class
identification, mandatory governing-spec review, proactive resolution of
the full applicable family, self-adversarial review and its findings, and
defect-class regression coverage. Responsible for producing the Review
Ready self-assessment against every item in the checklist above before
submitting. Not responsible for deciding whether a documented scope
boundary is *correct* for the project -- that is a review/architecture
judgment -- only for making sure the decision is visible and reasoned,
not silent.

**Independent Reviewer.** Responsible for auditing submissions against
this standard, not only against the originally reported finding:
verifying the problem class was correctly identified, spot-checking that
the applicable family is actually complete against the governing
specification (not just against the implementer's own summary of it),
confirming the Review Ready checklist was honestly satisfied, and judging
whether documented out-of-scope items reflect reasonable engineering
judgment rather than avoidance of inconvenient work. A reviewer who finds
a problem-class gap the implementer's self-adversarial review should have
caught should say so explicitly -- that is itself useful signal about
whether Section 4 is being taken seriously.

**Chief Architect / Technical Program Manager** (where a project uses
this role). Responsible for judging whether a documented out-of-scope
boundary is architecturally sound for the project's actual purpose, and
for reconciling recurring problem-class findings across a portfolio into
standards updates -- if the same category of specification-conformance
gap keeps recurring across projects, that is a signal this standard
itself needs a concrete addition, not just repeated case-by-case fixes.

**Release Manager.** Unchanged from `CONSTITUTION.md`'s existing release
governance section: conformance with this standard is release *evidence*,
not release *authorization*. A component being fully conformant with its
governing specification, per this standard, still requires the same
release-authorization process as any other engineering-complete work --
this standard does not create a new path to publication, and does not
change who may authorize one.

---

## Relationship to existing governance

This standard is a specific application of `CONSTITUTION.md`'s existing
"Engineering review rule" (separate observations from conclusions,
challenge your own conclusions, ask what evidence would prove you wrong,
look for contradictory evidence, never overstate confidence) to
specification-governed implementation work specifically. It does not
replace that rule; it operationalizes it for this recurring situation.

It complements, rather than duplicates, `CONSTITUTION.md`'s Tester Value
Density (TVD) principle: TVD prioritizes which *behavioral* tests are
worth writing next, given finite effort. This standard specifies what
*defect-class* regression coverage a specification-governed fix must
include regardless of TVD prioritization, since a defect-class gap is not
optional coverage to be prioritized against other work -- it is the
completion criterion for the finding itself.

It also complements the Engineering Velocity and Time Stewardship
standard (`ENGINEERING_VELOCITY_AND_TIME_STEWARDSHIP_STANDARD.md`, where
adopted): resolving a full problem class in one round, backed by a real
self-adversarial pass and a Specification Inventory, is what actually
shortens the total review cycle for specification-governed work -- fewer
round trips, not less rigor per round. Time Stewardship's "batch related
work into complete problem-class resolutions" principle and this
standard's Section 2 describe the same practice from two different
angles: velocity and correctness.

---

## Adopting this standard in a new Jumpstile project

1. Copy this file into the new project's repository root.
2. Add it to that project's `CONSTITUTION.md` governance-hierarchy list,
   in the **Engineering Standards** tier (portfolio-wide, repository-
   agnostic standards) -- not the Project Standards tier `SECURITY.md` /
   `RELEASE-SAFETY-CHECKLIST.md` / `ARCHITECTURE.md` occupy, since this
   document (unlike those) is meant to be adopted unchanged across
   projects.
3. Reference it from that project's `RELEASE-SAFETY-CHECKLIST.md` as a
   standing item to check on any PR that responds to a specification-
   governed review finding.
4. Reference it from that project's AI onboarding/required-reading
   documentation (e.g. `CLAUDE.md`, `AGENTS.md`, or their equivalents),
   so it is read before, not discovered during, specification-governed
   work.
5. File (or update) that project's "Engineering Governance and Project
   Health" meta-issue (see `ENGINEERING_GOVERNANCE.md`'s own adoption
   steps) to include this standard in its tracked scope.
