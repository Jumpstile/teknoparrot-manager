# Engineering Velocity and Time Stewardship Standard

Status: canonical Engineering System standard, adopted for TeknoParrot
Manager and the template for every Jumpstile project. Repository-agnostic:
every example below is illustrative.

---

## Core principle

> Time is the only engineering resource that cannot be recovered.
> Optimize engineering velocity wherever possible, but never by
> compromising correctness, security, maintainability, documentation,
> testability, independent review, certification, or long-term project
> quality.

Every other resource in a software project -- money, compute, even
personnel -- can, in principle, be recovered, replaced, or added to.
Elapsed time spent cannot. A day spent on avoidable rework, redundant
review cycles, or a manual step that could have been automated is gone
permanently, regardless of how the project's other resources are
managed. This standard exists to make velocity a deliberate, tracked
engineering concern -- not an accident of how much automation happened to
already exist, and not an excuse to cut a corner that would cost more
time later than it saves now.

**This is not a speed-over-quality standard.** The quality gates this
portfolio already requires -- `CONSTITUTION.md`'s Engineering review
rule, `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`'s problem-class
resolution, `RELEASE-SAFETY-CHECKLIST.md`'s pre-commit and release gates,
independent review, real-hardware certification -- are not velocity costs
to be minimized. They are the boundary condition every velocity
improvement under this standard must stay inside. A change that makes
work faster by skipping one of them is not a velocity improvement; it is
a quality regression that happens to also arrive sooner.

---

## Principles

**Parallelize independent work whenever safe.** Work with no data or
ordering dependency on other in-flight work should proceed concurrently,
not be serialized by habit or by defaulting to one work stream at a time.
"Safe" is the operative qualifier: parallelizing is only a velocity gain
if the parallel streams are actually independent -- two changes to the
same file, or a change and the review that depends on its exact final
state, are not safe to parallelize.

**Prefer automation over repetitive manual work.** A manual step repeated
identically across multiple cycles (a release checklist item, a recurring
audit, a data transformation) is a candidate for automation the first
time its repetition is noticed, not after the tenth time it's performed
by hand. Automating it is a durable time investment; performing it
manually again is a recurring one.

**Batch related work into complete problem-class resolutions.** This is
`SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`'s core principle, restated from
the velocity side: resolving an entire applicable problem family in one
round, backed by a real self-adversarial review, is not slower than
fixing one instance at a time -- it is faster in total elapsed time,
because it eliminates the round-trip cost (implement, submit, wait for
review, receive the next finding, repeat) of every additional cycle a
narrower fix would have required. See that standard's "Motivating
incident" for a real, measured instance of this: three additional review
round-trips that a Specification Inventory, built once, would have
avoided.

**Reduce unnecessary engineer decision points.** A decision an engineer
(human or AI) has to make repeatedly, the same way every time, given the
same inputs, is a candidate for a documented default, a template, or
automation -- not a standing cognitive-load tax paid on every occurrence.
This does not mean removing judgment from genuinely judgment-requiring
decisions (e.g. whether a documented out-of-scope boundary is
architecturally sound); it means not making an engineer re-derive a
settled answer from scratch every time a routine situation recurs.

**Automate workflow coordination where appropriate.** Where multiple
contributors (human or AI) are working on related but independent parts
of the same effort, prefer coordination mechanisms that don't require an
engineer to manually poll, re-explain context, or re-synchronize state
that could be tracked automatically (issue cross-links, status labels,
CI status, automated handoff notes). Manual coordination overhead is time
spent on the *work about the work*, not the work itself.

**Preserve all quality gates.** Every principle in this standard operates
inside the existing gate structure -- pre-commit checks, static analysis,
the full test suite, independent review, real-hardware certification
where applicable, and (per `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`) the
Definition of Review Ready for specification-governed work. None of these
are optional under time pressure. A velocity improvement that proposes
skipping, weakening, or deferring a quality gate is not a velocity
improvement under this standard; it does not qualify for consideration
under this document at all.

**Never trade engineering quality for short-term speed.** Where a
genuine tension exists between finishing something sooner and finishing
it correctly, correctness wins, every time, without exception carved out
by this standard. This standard's entire purpose is finding velocity
gains that do *not* require that tradeoff -- parallelism, automation,
batching, reduced decision overhead -- specifically because those gains
are real and do not come at correctness's expense. Reaching for a
tradeoff velocity gain is a sign the search for a non-tradeoff gain
stopped too early, not evidence that a tradeoff was necessary.

**Prefer durable improvements over one-off optimizations.** A change that
speeds up this specific task once is worth less than a change that speeds
up every future occurrence of the same class of task -- automating a
repeated manual step, building a reusable inventory template
(`INVENTORY_STANDARDS.md`), or fixing a process gap at the standard level
rather than patching around it in one instance. When choosing between a
faster one-off path and a slightly slower durable one, the durable path
is usually the better velocity investment measured over the project's
remaining lifetime, not just the current task.

**Continuously look for opportunities to reduce project elapsed time
safely.** This is a standing, ongoing responsibility, not a one-time
audit. Whenever work reveals a recurring inefficiency -- a manual step
performed more than once, a review cycle that took multiple rounds for a
reason a process change could prevent, a coordination gap that cost
elapsed time waiting rather than working -- that observation is itself a
candidate for a durable fix under this standard, reported and acted on
rather than silently absorbed as "just how it goes."

---

## Examples

These illustrate the principles above; they are not an exhaustive list of
every situation this standard applies to.

**Implementation proceeding while independent review happens in
parallel.** Where a review of one already-submitted piece of work is
underway, and unrelated work exists that does not depend on that review's
outcome, proceeding with the unrelated work concurrently -- rather than
idling until the first review completes -- is the "parallelize
independent work whenever safe" principle in practice. The safety
condition matters: this is only valid when the two work streams are
genuinely independent (different files, different components, no shared
state), and the review-in-progress is never itself modified or
interfered with by the parallel work.

**Governance or documentation work proceeding alongside software
review.** Standards work, documentation, and process improvements
frequently have no dependency on the outcome of an in-flight code review
-- they can, and should, proceed in parallel rather than waiting idle for
the code review to conclude. This is the same principle as the example
above, applied to a different kind of parallel work.

**Automation replacing repetitive release tasks.** A release checklist
item performed identically on every release (a version-string sweep, a
package-structure validation, a doc cross-reference check) is a candidate
for scripting the first time its manual repetition becomes visible as a
pattern, not after it has already consumed many release cycles' worth of
manual effort. `RELEASE-SAFETY-CHECKLIST.md`'s own package-validation
tooling (`Tests\Test-ReleasePackage.ps1` in this repository) is an
existing instance of this principle already in practice.

**Specification-driven implementation reducing review cycles.** Building
a Specification Inventory before implementing (`INVENTORY_STANDARDS.md`)
and resolving the full applicable problem family in one round
(`SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`) is simultaneously a
correctness practice and a velocity practice -- it is the concrete
example this standard's "batch related work" principle draws on. The
measured cost of *not* doing this (three additional review round-trips
in a real incident) is direct evidence for why this standard treats
problem-class batching as a velocity principle, not only a quality one.

---

## Checklist N/A handling

Any checklist built from this standard's principles (e.g.
`RELEASE-SAFETY-CHECKLIST.md` section 11 in this repository, or an
equivalent in a project that adopts this standard) will have items that
genuinely do not apply to a given round or release. This section defines
when N/A is a legitimate marking, who determines it, and what must be
recorded -- the same discipline `INVENTORY_STANDARDS.md` requires for its
own `Intentionally out of scope` item status, applied to velocity
checklists specifically.

**When an item may legitimately be marked N/A.** Only when the item's
own triggering condition genuinely did not occur this round -- for
example, "independent work streams proceeded in parallel where safe"
is N/A for a round where no genuinely independent second work stream
existed at all (not merely one nobody happened to start), and "a
repeated manual step was flagged as an automation candidate" is N/A for
a round where no step was performed identically across multiple recent
cycles. N/A is never a legitimate marking for "we chose not to do this
because it would have taken longer" -- that is exactly the tradeoff this
standard's "never trade engineering quality for short-term speed"
principle forbids marking as a routine skip.

**Who determines N/A.** The person or role executing the checklist (the
Lead Engineer role, in this repository's `RELEASE-SAFETY-CHECKLIST.md`
AI-workflow mapping) proposes the N/A marking with its one-line reason at
the time the checklist is completed. The Independent Reviewer may
challenge any N/A marking during review the same way they would challenge
a `Missing` inventory item marked `Intentionally out of scope` -- an N/A
that doesn't survive that challenge is not N/A, it's a skipped item.

**Documentation expectations.** An N/A marking is never a silently
unchecked or skipped box. It carries a one-line reason inline, at the
point of the checklist item itself (e.g. "N/A -- no second independent
work stream existed this round"), the same evidentiary bar
`INVENTORY_STANDARDS.md`'s Status marking section sets for
`Intentionally out of scope`. A checklist with unexplained skipped items
is not distinguishable, to a later auditor, from one where the work was
simply never done.

---

## Relationship to existing governance

This standard does not introduce any new authority, override any
existing gate, or change who may authorize a release. It is additive
process guidance operating strictly inside the boundaries
`CONSTITUTION.md` and `RELEASE-SAFETY-CHECKLIST.md` already establish.
Where this standard's guidance and any other adopted standard appear to
conflict, the other standard's quality/correctness requirement wins --
per this standard's own "preserve all quality gates" principle, that is
not a conflict this standard intends to create, and any apparent instance
of one should be reported and resolved (per `CONSTITUTION.md`'s
governance-hierarchy conflict-resolution rule) rather than treated as
license to relax the other standard.

It complements `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md` directly (see
that document's own cross-reference to this one) and `CONSTITUTION.md`'s
Tester Value Density principle, which already applies a similar
"durable, prioritized investment over one-off effort" logic to
behavioral test coverage specifically; this standard generalizes that
logic to engineering process as a whole.

---

## Adopting this standard in a new Jumpstile project

1. Copy this file into the new project's repository root.
2. Add it to that project's `CONSTITUTION.md` governance-hierarchy list,
   alongside `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md` and
   `INVENTORY_STANDARDS.md`, where those are also adopted.
3. Reference it from that project's `RELEASE-SAFETY-CHECKLIST.md` and AI
   onboarding documentation.
4. Apply it as a standing lens on recurring engineering work -- this
   standard is meant to be referenced when a recurring inefficiency is
   noticed, not only read once at adoption time.
