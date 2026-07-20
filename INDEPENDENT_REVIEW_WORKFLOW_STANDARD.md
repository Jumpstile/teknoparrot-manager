# Independent Review Workflow Standard

Status: canonical Engineering System standard, adopted for TeknoParrot
Manager and the template for every Jumpstile project. Repository-agnostic:
every example below is illustrative. This document is the concrete
workflow that satisfies `CONSTITUTION.md`'s "Independent Review Required"
-- that section defines *what* the requirement is (a second, independent
pass before a change is treated as settled) and *why* it exists; this
standard defines the ordered process that carries it out in practice,
including how a review that returns findings reaches resolution without
either skipping re-verification or re-reviewing everything from scratch on
every iteration. See `CONSTITUTION.md`'s "Document ownership and canonical
responsibility" for why this content lives here rather than being
duplicated inline there.

---

## Purpose

This standard defines the required review lifecycle for non-trivial
engineering work. It preserves independent verification, gives every
reported finding an explicit resolution path, and avoids repeating a
complete review when only focused corrective changes were made.

## Required workflow

Non-trivial engineering work must follow this sequence:

1. **Approve architecture and requirements.** Agree on scope, constraints,
   acceptance criteria, and ownership boundaries before implementation
   begins.
2. **Complete implementation.** The implementer finishes the defined scope
   and records the relevant test and quality-gate results.
3. **Perform an independent full review.** A reviewer who did not author
   the implementation examines the complete change against the approved
   requirements and returns either `APPROVED` or `CHANGES REQUIRED`.
4. **Address findings in focused changes.** Each finding is corrected in
   one or more traceable commits without expanding scope unnecessarily.
5. **Perform a delta review.** The independent reviewer verifies the
   corrective changes and their immediate effects (see "Delta review
   principle" below).
6. **Approve progression.** After the delta review returns `APPROVED`,
   the work may proceed to merge, the next engineering phase, or final
   certification as applicable. If the delta review finds a correction
   incomplete, incorrect, or newly regressed, it returns to step 4, not
   step 3 -- the review stays scoped to what changed since the prior
   finding unless "When a new full review is required" below applies.

## Full review requirements

A full review evaluates the entire change within the approved scope. The
reviewer should verify, as applicable:

- architectural and requirements conformance;
- correctness and failure behavior;
- security and authority boundaries;
- compatibility and regression risk;
- test adequacy and traceability;
- documentation and maintainability;
- absence of unintended scope expansion.

The verdict must be unambiguous:

- `APPROVED`
- `CHANGES REQUIRED`

Each required change must identify its severity, location, rationale, and
exact recommended correction.

## Delta review principle

A delta review verifies the changes introduced to resolve previously
reported findings. It does not repeat the entire full review unless the
corrective work materially expands scope, alters approved architecture, or
changes areas outside the original findings.

This exists because it is what makes rounds of review practical rather
than theoretical. A workflow that required a full re-review after every
focused fix would create pressure to either skip re-verification
(defeating Independent Review Required) or bundle unrelated fixes to
amortize review cost (defeating focused, traceable commits). Scoping
re-review to the actual delta keeps both intact.

The delta reviewer must confirm that:

- every reported finding was addressed;
- the correction matches the requested outcome;
- the correction did not introduce an immediate regression or
  inconsistency;
- unrelated changes were not included;
- traceability between the finding and corrective commit is preserved.

The delta-review verdict must again be either `APPROVED` or
`CHANGES REQUIRED`.

## When a new full review is required

A new full review is required when corrective work:

- materially expands the implementation scope;
- changes an approved architectural decision;
- introduces a new subsystem or authority boundary;
- rewrites substantial portions of previously reviewed behavior;
- makes the original review conclusions unreliable.

## Independence and role separation

The independent reviewer must not silently become the implementer for the
same review cycle, and the implementer must not review their own work
under the guise of independence -- if a reviewer would be evaluating
something they authored, that is self-review, not independent review,
regardless of role labels applied to the session performing it. Review
findings should be returned to the assigned implementer unless an
explicit role reassignment is approved and recorded.

Environment-specific verification (a certification run on real hardware,
a check performed by a separate operator or machine) may be performed by
a separate operator or machine. Such verification complements, but does
not replace, independent engineering review.

## Merge and certification rule

Passing automated tests or Quality Gates is necessary where required, but
it is not a substitute for independent review. Work must not be merged or
advanced to final certification until all blocking findings have been
corrected and the required delta review has returned `APPROVED`.

## Traceability

Review records should identify:

- the reviewed commit or immutable change set;
- the reviewer verdict;
- each finding and its severity;
- the corrective commit or commits;
- the delta-review verdict;
- the final merge or phase-approval decision.

## Benefits

This workflow:

- maintains independent verification;
- reduces unnecessary reviewer effort;
- ensures every finding is explicitly revalidated;
- avoids redundant full re-reviews;
- preserves traceability between findings and corrective commits;
- creates clear approval boundaries between implementation phases.

## Applicability

This standard applies to production code, security-sensitive changes,
certification logic, release tooling, substantial tests, architecture
documents, operational procedures, and other non-trivial work. Trivial
editorial corrections may use a lighter process when they do not affect
meaning, behavior, policy, or operational safety.
