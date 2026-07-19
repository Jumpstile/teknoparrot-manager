# ADR-0155: Certification Transaction Architecture -- Authoritative Facts, Not Mutable State

**Status:** Proposed. No production code or tests changed as part of this document. Covers `scripts/Invoke-TPM-RealInstanceSmoke.ps1`'s certification-evidence/scoring/publication pipeline (issue #154, PR #155), as of commit `c6bc7ba` on `codex/issue-154-evidence-finalization`.

**Revision note:** an architecture review of this ADR's first draft returned ARCHITECTURE CHANGES REQUIRED -- the draft named abstractions (`TPMFactStore`, `TPMDecisionSnapshot`, "commit marker") without defining what makes each one *enforceably* authoritative rather than merely well-named. This revision replaces every such abstraction with a concrete ownership, immutability, provenance, and verification mechanism, expressed in terms PowerShell can actually enforce, not merely intend. No implementation has started; this remains a design document.

---

## 1. Context and problem statement

Three independent adversarial review rounds on this pipeline each found a real, distinct forgeability gap:

- **Round 1** (issue #151): evidence-capture correctness -- filename collisions, format masquerading, missing CRC integrity.
- **Round 2** (issue #154, round 1): the transaction wasn't the sole outcome authority -- evidence, score, report status, and process exit could disagree with each other.
- **Round 3** (issue #154, rounds 2-3): the transaction *was* the sole authority, but it still trusted several **descriptions** of workflow activity (a public evidence array, a caller-supplied score-item array, an optional publish callback) rather than **facts the workflow itself owned**.

**Problem statement:** the recurrence itself is the signal worth acting on. Naming a private ledger, a "decision snapshot," and a "commit marker" is not the same as making each of those things *structurally* unforgeable -- as this ADR's own first draft demonstrated by being sent back for exactly that reason. This revision's job is to specify, for each abstraction, the concrete mechanism that makes it authoritative, not merely the name that implies it should be.

---

## 2. Current architecture, as implemented

```
Main script body
 |- $results = [ordered]@{...}         (mutable hashtable, mutated for the whole run)
 |- Checks run inline (Pester, PSScriptAnalyzer, install health, restoration...)
 |    `- Add-CheckResult appends to $results.Checks
 |- Evidence captured inline, interleaved with checks
 |    `- Add-Screenshot: appends to $script:tpmEvidenceLedger (private, sealed on
 |        'final-certification-result') AND to $results.Screenshots (public mirror)
 |- $certification = New-CertificationScorecard -Results $results
 |    `- builds $certification.Items (array of score-item pscustomobjects) from
 |        $results.Checks, once, but Items remains a free-standing mutable array
 |- $buildCertificationArtifacts = { ...closure over $certification/$results/$reportDir... }
 `- $finalization = Complete-TPMCertificationTransaction `
        -Certification $certification -Results $results `
        -BuildArtifacts $buildCertificationArtifacts `
        -ScreenshotDir $screenshotDir -ReportDir $reportDir
        |
        |- validates submitted evidence against $script:tpmEvidenceLedger
        |  (reference-identity, seal check, manifest, path/label/scope checks)
        |- validates $Certification.Items against Get-TPMExpectedScoreItemManifest
        |  (shape only -- no ownership/provenance check)
        |- derives score from Items, derives evidence-pass from ledger
        |- Add-Member -Force's Status/Overall/ExitCode/... onto $Certification
        |  and $Results IN PLACE, repeatedly, across the run
        |- builds $decisionSnapshot (a fresh pscustomobject, no Published field)
        |- invokes -BuildArtifacts $decisionSnapshot -> artifact array
        |- validates artifacts against Get-TPMExpectedArtifactManifest
        |- Publish-TPMCertificationArtifacts: stage -> promote non-marker ->
        |  durably re-read non-marker -> promote marker -> durably re-read marker
        `- on publish failure: mutates the ALREADY-RETURNED $transaction object
           in place (Passed/Status/Overall/ExitCode/Published/PublicationError)
```

This is the state after three rounds of genuine, tested hardening. The 812-test suite proves every *previously discovered* forgery technique against it fails -- it does not prove the architecture is structurally incapable of producing the next one, which is what this ADR is now required to establish.

---

## 3. Current architecture assessment

### 3.1 Authoritative source of truth

There isn't one. Three different bespoke authorities exist (private ledger for evidence with reference-identity checking; shape-only manifest validation for score; manifest-validated atomic commit for publication), each invented in a different round after a different category was separately found forgeable, with no shared underlying mechanism.

### 3.2 Immutable vs. mutable data

Actually immutable today: the per-run `WorkflowId`, and the evidence ledger's append-only discipline. Not immutable: `$certification.Items` (a plain mutable array of mutable objects), `$certification` itself (`Add-Member -Force`d in place repeatedly), and `$results` (an ordered hashtable mutated from many call sites across the script's lifetime).

### 3.3 Derived vs. trusted data

Score arithmetic and evidence pass/fail are correctly *derived*, fresh, at commit time -- but derived from *inputs* (score Items) that have no ownership guarantee of their own. "Derived, not trusted" is necessary but not sufficient without also making the input authoritative.

### 3.4 Presentation-only data

Provisional console output, per-record capture echoes, and report prose sections. None of these feed back into any decision; this boundary is already correctly drawn.

### 3.5 Transaction boundary

Two nested phases inside one function: decision computation, then publication (invoked from inside the decision phase), whose failure retroactively mutates the already-computed decision object in place rather than composing a new outcome.

### 3.6 What "committed" means today

The commit marker file's existence on disk, promoted strictly after every other artifact is durably re-read and verified. Operationally correct, but (per the architecture review that produced this revision) insufficient on its own -- see Section 10 for what a consumer must additionally verify before trusting a marker's presence.

### 3.7 Interruption/crash guarantees

No partial output is ever observable (satisfied); no resumption of a crashed run is attempted (an assumption, not a guarantee -- addressed in Section 17); cleanup failure during rollback is surfaced, not swallowed (satisfied).

### 3.8 Trust-boundary table (superseded by Section 17's expanded version)

| Boundary | Protected by | Protects against | Does **not** protect against |
|---|---|---|---|
| Evidence identity | Reference-identity vs. private ledger | Forged/copied/substituted/replayed evidence objects | Direct field mutation of a *real* ledger object; same-process arbitrary code (see Section 17.9) |
| Score validity | Manifest **shape** check only | Malformed/incomplete/wrong-typed Items arrays | A well-formed but entirely fabricated Items array -- no provenance check exists at all |
| Publication identity | Artifact-manifest Id/destination check | Wrong/incomplete/misdestined artifact sets | Correct ID/destination with substituted or corrupted *content* -- no hash binding exists (see Section 9) |
| Publication durability | Stage -> promote -> durable-reread -> marker | Crash/interruption/partial write | A reader trusting marker presence alone without validating the manifest it commits (see Section 10) |

### 3.9 Can this be simplified rather than further validated?

Yes -- this remains the governing principle of the whole redesign: one uniformly-enforced ownership/immutability/provenance rule, applied to every fact category, replaces three independently-invented, unevenly-strong defense mechanisms.

### 3.10 Would a different internal model eliminate whole classes of attack?

Yes, per Sections 5-12 below, which is where this revision replaces the first draft's named-but-underspecified abstractions with concrete mechanisms.

---

## 4. Proposed seven-stage pipeline

```
Checks execute -> Immutable Fact Store -> Eligibility Decision (frozen) ->
Artifact Builder -> Staged Bundle -> Atomic Publish -> Commit Marker -> Final Outcome
```

(Renamed from the first draft's six-stage version: "Decision Snapshot" is renamed "Eligibility Decision" per Section 8, and an explicit eighth stage, "Final Outcome," is added because Section 8 establishes that eligibility and final certification status are not the same object.)

| Stage | Status today | Gap this ADR closes |
|---|---|---|
| Checks execute | Exists | None |
| Immutable Fact Store | Partial (evidence only) | Section 5-7: unify and make provenance-checked, not just type-checked |
| Eligibility Decision (frozen) | Partial, and semantically wrong (claims final status) | Section 8: correct the boundary |
| Artifact Builder | Exists, but arbitrary | Section 11: constrain to a deterministic projection |
| Staged Bundle | Exists | Section 9: bind to exact content via hashes |
| Atomic Publish | Exists | Section 9-10: hash-bound manifest, defined consumer contract |
| Commit Marker | Exists | Section 10: define what "trustworthy" means beyond presence |
| **Final Outcome** (new) | Does not exist as a distinct stage today | Section 8, 12: the only object authorized to carry PASS/CERTIFIED/exit-code semantics |

---

## 5. Workflow-owned provenance

**The first draft's error:** it said evidence objects were authenticated because they were reference-identical to entries in a `$script:tpmEvidenceLedger` `List[object]`, and implied a `TPMFactStore` *type* would generalize this. Neither claim, by itself, establishes genuine provenance: `-is [TPMFactStore]` proves an object is *shaped* like a fact-store record; it does not prove *this specific run's* workflow produced it, and reference-identity against a `List[object]` scoped only by ordinary PowerShell variable scoping is a convention, not a boundary enforced against same-process code.

### 5.1 One store instance per run, owned by run-specific identity

Each certification run generates a **run capability token** at start -- a fresh `[guid]` (already the existing `WorkflowId` pattern, generalized) held only by the top-level script scope that starts the run. The `TPMFactStore` constructor is **private-by-convention plus capability-gated**: it accepts the run capability token as a mandatory constructor argument and stores it in a `hidden` field. Every subsequent operation against the store that must prove "this call belongs to the run that owns this store" (sealing, and -- during migration Phase 2 -- direct fact recording from a context outside the designated recording functions) requires presenting the same token value, compared by exact value equality (`-ceq` against the GUID's string form, or `.Equals()` on the `[guid]` itself). A store constructed with, or later checked against, a different token is provably not this run's store.

This is not cryptographic secrecy (a GUID visible in-process is not a secret from other same-process code -- see 5.6) -- it is **identity binding**: it converts "is this object shaped like a fact store" into "was this object constructed with, and does it still carry, this run's specific capability value," which a copied or freshly-constructed impostor object cannot satisfy without also having obtained the real token, which is not exposed by any getter (see Section 6.2).

### 5.2 Who may create the store

Exactly one call, at the top of the main script body, immediately after the run capability token is generated: `$factStore = New-TPMFactStore -RunToken $runToken`. No other function in the script constructs a `TPMFactStore`. This is enforced the same way the current codebase already enforces "only `Add-Screenshot` appends to the evidence ledger" -- by code-review convention backed by a structural source-text check (the existing test suite already has a precedent for this: "uses the one transaction as the source... `Publish-TPMCertificationArtifacts -Artifacts` count is 1" -- the migration's regression suite adds an equivalent "`New-TPMFactStore` is called exactly once in the whole script" structural test).

### 5.3 Which code paths may append facts

Only two functions, both taking the store instance (not the run token directly) as a mandatory parameter, and both internally re-validating the store's token against the script-scope `$runToken` before writing: `Add-TPMFactStoreCheck -Store $factStore -Fact ...` and `Add-TPMFactStoreEvidence -Store $factStore -Fact ...` (the direct successors to today's `Add-CheckResult`/`Add-Screenshot`). No other function is granted this capability. The store's underlying fact collections (Section 6) are `hidden`, so nothing outside these two functions -- not even other functions in the same script -- can append directly, only through them.

### 5.4 How producers prove they belong to the run

The producer (main script body) already holds `$runToken` from Section 5.1 in its own scope, obtained once from the single `New-TPMFactStore` call site. `Add-TPMFactStoreCheck`/`Add-TPMFactStoreEvidence` require the caller to pass `-Store $factStore`, and internally assert `$Store.OwningRunToken -ceq $runToken` (where `$runToken` is itself read from the same script-scope variable the constructor call established, not re-derived) before accepting the fact. This closes the gap the first draft left open: it is not enough for the *object* to be a `TPMFactStore`; the *specific instance* must be provably the one this run created, checked at every write, not only at construction.

### 5.5 How facts from another run, or a copied/caller-created store instance, are rejected

Two independent, redundant mechanisms:

1. **Token mismatch.** A `TPMFactStore` instance belonging to a different run (a prior run's leftover object, or a deliberately-constructed impostor with a different or blank token) fails the `OwningRunToken` comparison in 5.4 and is rejected at the first write attempt -- not silently accepted and only caught later at commit time.
2. **Reference-identity at commit time** (generalizing round 3's evidence-ledger mechanism to the whole store, not just evidence): `Get-TPMCertificationEligibility -Store $factStore` (Section 8's successor to `Complete-TPMCertificationTransaction`) validates that every fact it examines is `[object]::ReferenceEquals` to an entry the store's own internal collection actually holds -- so even a *correctly-tokened* but field-copied fact object (someone who obtained the real token through some other means and built a convincing-looking record) still fails, because copying field values can never reproduce object identity.

A store instance constructed directly by calling code (bypassing 5.2's single call site) is, by definition, a "copied or caller-created" instance under this ADR's threat model -- it either carries no valid token (rejected by 5.4/5.5.1) or, if the caller also fabricated a plausible-looking token, still cannot make its facts reference-equal to anything the real store holds (rejected by 5.5.2), because the real store's internal collections are `hidden` and never returned by reference (Section 6.4).

### 5.6 Explicit threat-model boundary: same-process arbitrary code execution

**Out of scope**, stated explicitly rather than left implicit. If an actor already has the ability to execute arbitrary PowerShell in the same process as the certification run -- for example by dot-sourcing additional code into the running session, or by directly manipulating `hidden` fields via reflection (`.GetType().GetField(...)`, which PowerShell does not prevent) -- no in-process ownership or immutability mechanism this ADR describes can stop them, the same way no software can defend its own process's memory against code running with equal privilege in that same process. This is not a gap specific to this design: it is the same boundary the existing (round 3) evidence ledger already operates under, made explicit here rather than left implicit as it was in the first draft. The actual guarantee this ADR provides is: **constructing a plausible-looking object using only the public API surface (the exported functions and their documented parameters) is insufficient to forge a fact, a decision, or a publication** -- reflection-based or otherwise-privileged same-process tampering is a different, and explicitly out-of-scope, threat.

### 5.7 Three distinct properties, not one

The first draft conflated these; this revision separates them explicitly, because a check that only proves one is not proof of the others:

1. **Correct object type** (`-is [TPMFactStore]`, or `-is [TPMFact]` for an individual record) -- proves shape only. Necessary, not sufficient.
2. **Valid fact shape** (the closed schema in Section 7 -- required fields present, correctly typed, cardinality respected) -- proves the record is *structurally* well-formed. Still not sufficient on its own; a well-formed, entirely fabricated record is still fabricated.
3. **Genuinely issued by the active certification workflow** -- proven only by the combination of 5.4's token check at write time *and* 5.5.2's reference-identity check at read time. This is the property that actually matters for certification integrity, and it is the one the first draft's naming implied without defining.

---

## 6. Enforceable immutability

**The first draft's error:** it relied on "PowerShell class semantics" and a `Seal()` method as if declaring a class and adding a boolean flag were themselves sufficient. They are not -- a PowerShell class's properties remain publicly settable by default, a `Seal()`-checked mutator only blocks mutation through *that specific mutator method*, and returning a live reference to an internal collection from any getter hands the caller a mutable object regardless of how many seal checks guard the store's own methods.

Concrete mechanisms, all required together (none is sufficient alone):

### 6.1 Copy-on-ingress

Every `Add-TPMFactStoreCheck`/`Add-TPMFactStoreEvidence` call constructs a **new**, store-owned record from the caller-supplied values field-by-field (or via a defensive `.PSObject.Copy()`/manual property-by-property copy for the specific closed schema in Section 7) -- it never retains the caller's own object. This is what "copy-on-ingress" means concretely: the store's internal collection never contains an object the caller still holds a reference to.

### 6.2 Private internal records; no retained caller references

The store's internal collections (the fact-store successor to today's `$script:tpmEvidenceLedger` and `$results.Checks`) are `hidden` class fields, never exposed via a public property. There is no getter that returns `$this.InternalFacts` directly.

### 6.3 No shared mutable collections

The store never hands out its internal `List[TPMFact]` (or equivalent) itself, under any name, to any caller -- not even a "read-only view" that is actually the same `List[object]` wrapped in a thin, non-enforcing type. PowerShell's `List[T].AsReadOnly()` produces a `ReadOnlyCollection<T>` wrapper around the *same underlying list* -- mutating the original list through the store's own internal reference still mutates what the wrapper exposes, so `AsReadOnly()` alone is a documentation hint, not an enforcement boundary, and is not relied upon as one here.

### 6.4 Read-only or detached projections on egress

Any method that lets external code inspect the store's contents (e.g. `$factStore.GetFactsForReview()`, used by the Artifact Builder in Section 11) returns a **freshly-constructed array of freshly-constructed, detached copies** of each record -- not the internal objects themselves, not a wrapper around the internal collection. Mutating anything in the returned array has zero effect on the store's own internal state. This is the same "defensive copy on the way out" discipline as 6.1's "defensive copy on the way in," applied symmetrically.

### 6.5 Defensive copying for nested values

Where a fact's raw value is itself a reference type with mutable sub-fields (uncommon in this pipeline's actual fact categories -- see Section 7, which are deliberately scalar/string/path-valued -- but a general rule for any future fact category that isn't), the copy in 6.1 and the projection in 6.4 must be **deep**, not shallow: copying a wrapper object while leaving its nested mutable fields shared with the caller reintroduces exactly the hole this section closes.

### 6.6 Rejection of mutation after sealing

`Seal()` sets a `hidden` boolean. Every mutator (`AddCheck`, `AddEvidence`, and any other internal mutator) checks it first and `throw`s if already sealed -- this generalizes the existing, already-proven `Add-Screenshot` seal-check pattern from round 3 to the whole store. This is necessary but (per the header of this section) not sufficient by itself; it only prevents *new* facts from being added after sealing, it says nothing about whether an *already-added* fact's fields can still be mutated in place, which 6.1-6.4 separately close by ensuring no live, mutable reference to any stored fact ever escapes the store in the first place.

### 6.7 No callback receives an authoritative mutable object

The Artifact Builder callback (Section 11) receives only: (a) the array of detached, read-only-in-practice fact copies from 6.4, and (b) the Eligibility Decision (Section 8), itself constructed as a **frozen value type** -- a `class` whose every property is set once in the constructor and never has a public setter at all (PowerShell classes support this directly: declare properties without `[Parameter()]`-style external set access by simply never writing a method or property setter that mutates them post-construction, and by never exposing a constructor overload that allows re-construction from mutable external state after the fact). Neither object the callback receives is the store itself, and neither is anything the callback could mutate to retroactively change what the store, the eligibility decision, or the final outcome actually record.

### 6.8 How this differs from "intending" immutability

Every mechanism above is checkable independently by a test: 6.1/6.4 by asserting that mutating a value obtained from the store (via ingress or egress) has no observable effect on a value read from the store afterward; 6.2/6.3 by asserting no public property or method returns the internal collection by reference (a reflection-based test, or simply the absence of any such method in the public surface, audited during code review); 6.6 by asserting a mutator throws post-seal (already proven pattern); 6.7 by asserting the Artifact Builder callback's parameter types are the frozen/detached types, never the store type itself. This is what makes immutability *enforced*, in the sense the architecture review asked for, rather than merely documented as an intent.

---

## 7. Closed raw-fact schema

**The first draft's error:** it let `$certification.Items` (score facts) remain a free-standing, caller-constructed array validated only for shape, with no equivalent to evidence's ownership/provenance mechanism, and never separated "raw observed value" from "already-interpreted conclusion" for either fact category.

The Fact Store (Section 5-6) holds only **raw observed facts** -- what a check or capture actually produced -- never a caller's own conclusion about what those facts mean (that derivation happens once, in Section 8, from the sealed store). Every fact category is defined by the following closed schema; no fact category is added ad hoc without updating this table in the same change:

### 7.1 Evidence fact categories (unchanged in substance from round 3, restated in this schema)

| Field | Definition |
|---|---|
| Canonical fact identifier | One of the nine fixed strings already established in round 3 (`certification-suite-running`, `requested-effective-root-evidence`, `live-thumbnail-evidence`, `live-controls-evidence`, `adaptive-menu-normal`, `adaptive-menu-small`, `adaptive-menu-maximized`, `smoke-file-safety-evidence`, `final-certification-result`) |
| Raw observed value | The captured file's path plus its structural-validation result (PNG structure, dimensions) -- not an interpretation, just what was captured and whether it decodes |
| Authorized producer | `Add-TPMFactStoreEvidence`, exclusively (Section 5.3) |
| Cardinality | Exactly one per identifier for the seven required identifiers; exactly one (as an explicit Skipped record) for the two conditional identifiers |
| Ordering requirements | `final-certification-result` must be the last fact appended to the store, of any category (Section 5, generalizing round 3's ledger-position rule store-wide, not evidence-only) |
| Duplicate behavior | A second fact for an identifier already recorded is rejected at ingestion (`Add-TPMFactStoreEvidence` throws), not silently accepted and only caught at eligibility-computation time -- tightening round 3's "caught at commit" behavior to "rejected at write," consistent with Section 6.6's seal discipline generalized to per-identifier uniqueness during the open (pre-seal) phase too |
| Missing-fact behavior | A required identifier absent when the store seals is an eligibility-blocking gap (Section 8) |
| Applicability/tri-state behavior | The two conditional identifiers (`live-thumbnail-evidence`, `live-controls-evidence`) are the only ones permitted an explicit Skipped record in place of a capture |
| Provenance fields | `OwningRunToken` (Section 5.1, not a caller-visible field -- checked internally, never serialized), append-sequence position (informational, per round 3) |
| Ingestion-time validation | PNG structural validation, path containment/uniqueness, label/filename consistency, capture-scope presence for ScreenCapture types -- all already implemented in round 3's `Add-Screenshot`/`New-TPMCertificationScreenshot`, ported unchanged into `Add-TPMFactStoreEvidence` |

### 7.2 Check fact categories (new -- does not exist as a closed schema today)

| Field | Definition |
|---|---|
| Canonical fact identifier | One of the eleven fixed strings already established as score-item `Area` values (`Repository`, `Pester`, `Static Analysis`, `Real Install Health`, `Backups`, `Smoke File Safety`, `Artifacts`, `pcsx2x6 crosshair path (issue #79)`, `Behavioral Certification (Virtual Beta Tester)`, `Unattended TPM root binding`, `Unattended TPM config restoration`) |
| Raw observed value | The check's raw pass/fail Boolean *as directly observed* (e.g. `$results.Pester.Failed -eq 0`), plus supporting raw detail text -- not a pre-computed "score contribution," which does not exist at the fact level at all (see Section 8: scoring is derived later, never stored as a fact) |
| Authorized producer | `Add-TPMFactStoreCheck`, exclusively |
| Cardinality | Exactly one per identifier |
| Ordering requirements | None beyond "before the store seals" -- unlike evidence, check facts have no relative-ordering requirement among themselves |
| Duplicate behavior | Rejected at ingestion, same as evidence |
| Missing-fact behavior | An identifier absent when the store seals is an eligibility-blocking gap, same as evidence |
| Applicability/tri-state behavior | `Smoke File Safety` and `Unattended TPM config restoration` are the only two identifiers permitted a `NotApplicable` raw value in place of a Boolean, per the existing manifest (`Get-TPMExpectedScoreItemManifest`) |
| Provenance fields | `OwningRunToken`, append-sequence position |
| Ingestion-time validation | Strict `[bool]` typing for the raw value when not `NotApplicable` (already implemented in round 3's `Test-TPMScoreItemManifest`, ported into `Add-TPMFactStoreCheck`'s own validation instead of a separate post-hoc manifest check against a caller-supplied array) |

**Consequence of unifying both categories under one schema and one store:** `Test-TPMScoreItemManifest`'s current shape-only validation (Section 3.8's identified weak point) is subsumed -- once check facts can *only* enter the store through `Add-TPMFactStoreCheck`, with the same ownership/provenance mechanism evidence already has, there is no longer a separate "trust the caller's array" step for score facts to skip. The score derivation in Section 8 reads *only* from the sealed store, the same way evidence validation already does.

---

## 8. Correcting the decision boundary: eligibility vs. final outcome

**The first draft's error:** `TPMDecisionSnapshot` was described as the transaction's decision object, but its fields (`Passed`, `Status`, `Overall`, `ExitCode`) already claimed final certification semantics (`'PASS'`, `'CERTIFIED'`, `0`) *before* publication had even been attempted -- exactly the boundary confusion Section 3.5 identified in the current implementation, simply renamed rather than fixed.

### 8.1 `TPMEligibilityDecision` (replaces `TPMDecisionSnapshot`)

A frozen value (Section 6.7's construction discipline), computed once by `Get-TPMCertificationEligibility -Store $sealedFactStore`, expressing **only pre-publication eligibility**:

- `EligibleForCertification` (`[bool]`) -- true only if every required fact is present, valid, and (for evidence) passes structural re-validation, and every check fact's raw value satisfies the certification's pass condition.
- `EvidenceEligibility` (structured detail: which facts, if any, blocked eligibility and why).
- `ScoreEligibility` (structured detail: same, for check facts).

**`TPMEligibilityDecision` has no `Status`, `Overall`, `ExitCode`, `Passed`, or any field that reads as a final certification verdict.** It cannot, by construction (no such property exists on the type), be rendered to a console, a report, or a process exit code as if it were the certification's result -- there is nothing on the object that means that.

### 8.2 `TPMPublicationOutcome`

Produced by attempting publication (Section 9-10) of an artifact set built from an `EligibleForCertification` `TPMEligibilityDecision`. Fields: `Published` (`[bool]`), `PublicationError` (nullable string), `CommittedManifestHash` (Section 9's hash-bound manifest's own hash, once committed).

### 8.3 `TPMFinalOutcome` (new type -- did not exist even by name in the first draft)

The **only** type authorized to carry final certification semantics, produced by `New-TPMFinalOutcome -Eligibility $eligibilityDecision -Publication $publicationOutcome`:

- `FinalStatus` (`'PASS'` or `'FAIL'`)
- `FinalOverall` (`'CERTIFIED'` or `'NOT CERTIFIED'`)
- `FinalExitCode` (`0` or `1`)

Composition rule, stated exhaustively: `FinalStatus = 'PASS'` if and only if `Eligibility.EligibleForCertification -eq $true` **and** `Publication.Published -eq $true`; every other combination (including publication never having been attempted at all) produces `FinalStatus = 'FAIL'`, `FinalOverall = 'NOT CERTIFIED'`, `FinalExitCode = 1`. This is a pure function of its two frozen inputs -- it does not mutate either input, and it is the *only* function in the whole pipeline permitted to construct a `TPMFinalOutcome`.

### 8.4 Why this boundary correction matters structurally, not just semantically

Under the current (and first-draft) design, a caller who obtains the pre-publication decision object before publication is attempted holds an object that already *claims* `Status = 'PASS'` -- if anything in the pipeline were to render that object (a logging statement, a debug dump, a premature report write) before publication actually completes, it would misrepresent an ineligible-for-final-certification state as certified. Under this revision, no object exists, at any point before `New-TPMFinalOutcome` runs, that has a property meaning "certified" at all -- `TPMEligibilityDecision.EligibleForCertification` means "eligible to attempt publication," a categorically different and non-final claim, enforced by the type simply not having any of the final-status property names.

---

## 9. Binding publication to exact content

**The first draft's error:** the artifact manifest (`Test-TPMArtifactManifest`, round 3) validated artifact *identity* (Id, destination) but never artifact *content* -- an artifact with the correct Id and destination but substituted, corrupted, or stale content passed the manifest check, per Section 3.8's trust-boundary table.

### 9.1 Canonical committed artifact manifest

Before staging (Section 9.2), the Artifact Builder's output (Section 11) is assembled into a **canonical committed manifest** -- itself one more artifact in the staged bundle, promoted last (generalizing round 3's commit-marker-last ordering) -- containing, for every other artifact:

| Field | Definition |
|---|---|
| Artifact ID | The existing closed identity set (`CertificationScorecardJson`, `ValidationReportJson`, `CertificationScorecardMarkdown`, `ValidationReportMarkdown`) |
| Canonical filename | The exact filename component of the artifact's destination path, independent of the full path (so a filename substitution is detectable even if the directory happens to match) |
| Canonical contained destination | The full path, re-verified contained within `-ReportDir` (round 3's existing containment check, retained) |
| Byte length | The exact staged content's length in bytes, computed at staging time from the same byte buffer that gets written |
| Cryptographic hash | SHA-256 of the exact staged byte content (`[System.Security.Cryptography.SHA256]::Create().ComputeHash(...)` over the UTF-8-encoded content, consistent with this repository's existing BOM-less-UTF-8 convention) |
| Schema/version information | A fixed schema-version integer for the manifest format itself, so a future format change is detectable by a consumer rather than silently misparsed |
| Certification-run identity | The run capability token's string form (Section 5.1) -- binds the manifest, and everything it commits, to one specific run, not merely "a" run |

### 9.2 What "binding" means concretely

`Publish-TPMCertificationBundle` (the successor to `Publish-TPMCertificationArtifacts`) computes each artifact's hash *at staging time*, before promotion, and includes it in the manifest artifact that itself gets staged and promoted as part of the same all-or-nothing set (Section 6's staged-bundle mechanism, unchanged in its atomicity guarantees from round 3). The durable-verification step already present in round 3 (re-reading each promoted file and comparing to staged content) is extended to compare against the **hash recorded in the manifest**, not merely byte-for-byte against an in-memory staged copy -- so the check that currently only proves "the file on disk matches what this process just wrote" is strengthened to "the file on disk matches what the committed, hash-bound manifest itself asserts," which is the property a *later, independent* consumer (Section 10) can also verify without having been present for the original staging.

---

## 10. Commit-marker and consumer contract

**The first draft's error:** it asserted the marker's mere presence was "durable proof of a complete publish" without specifying what a consumer must actually check -- Section 3.6 already flagged this as insufficient on its own.

### 10.1 The consumer-side validator

`Read-TPMCommittedCertification -ReportDir $dir` is the **only** sanctioned way to read a certification run's result back for any purpose (a later audit, a release-integrity check, a dashboard). It performs, in order, and rejects (returns an explicit `Valid = $false` with a reason, never a partial/best-effort result) on failure of any step:

1. **Marker presence.** The commit-marker file exists at the expected path. Absence -> reject, "not committed."
2. **Marker freshness/run-binding.** The marker's own content includes the certification-run identity (Section 9.1) the caller expects (if the caller is checking a specific run) -- a marker copied from a different run's `-ReportDir` into this one (a stale or copied marker) is rejected here, because its embedded run identity won't match the directory's own other artifacts' embedded run identity (checked in step 4).
3. **Manifest presence and self-consistency.** The committed manifest artifact (Section 9.1) exists, parses, and its own schema-version is one this reader understands.
4. **Per-artifact verification against the manifest**, for every artifact the manifest lists: the file exists at the manifest's canonical destination; its filename matches the manifest's canonical filename; its byte length matches; its SHA-256 hash matches; its embedded run identity (where the artifact format carries one, e.g. the JSON artifacts' own `EvidenceWorkflowId` field) matches the manifest's certification-run identity.
5. **Completeness.** Every artifact ID the manifest declares is present on disk (missing artifact -> reject, "partial publication"), and **no additional file presents itself as an authoritative artifact** -- concretely, the reader also lists the report directory's actual contents and rejects if any file matches one of the known authoritative filename patterns but is *not* listed in the manifest (an extra, unmanifested "authoritative-looking" artifact -- e.g. a stray `TPM-Certification-Scorecard.json` left behind by a failed, uncleaned-up prior attempt -- is exactly the "partial publication" or "cleanup failure that leaves debris behind" scenario this step exists to catch).
6. **Substitution/tamper detection.** Step 4's hash comparison is what actually catches a substituted or modified artifact -- correct ID and destination with different bytes fails the hash check, closing the gap Section 3.8/9 identified.

Only if all six steps pass does `Read-TPMCommittedCertification` return `Valid = $true` together with the parsed `TPMFinalOutcome` fields it read from the (now-verified) artifacts. **Marker presence alone is never sufficient** -- it is step 1 of six, not the whole check, directly answering the architecture review's explicit correction on this point.

### 10.2 What this rejects, enumerated against the review's list

Stale/copied markers (10.1.2); markers from another run (10.1.2, 10.1.4); missing artifacts (10.1.5); additional authoritative artifacts (10.1.5); modified artifacts (10.1.4/10.1.6); substituted artifacts (10.1.6); mismatched hashes or lengths (10.1.4); wrong canonical filenames (10.1.4); mismatched manifests (10.1.3/10.1.4); partial publications (10.1.5); cleanup failures that leave a marker behind (10.1.5, via the "no unmanifested authoritative-looking file" check -- a cleanup failure that leaves the marker but not all real artifacts is caught at step 5's completeness check, and one that leaves extra debris is caught at step 5's extra-file check).

---

## 11. The Artifact Builder as a deterministic projection, not an arbitrary trust boundary

**The first draft's error:** `-BuildArtifacts` remained an arbitrary caller-supplied scriptblock, manifest-validated for identity but not constrained in what it could *do* -- nothing prevented a callback from producing content unrelated to the actual sealed facts and eligibility decision it was handed, as Section 3.8 and the review both flagged.

### 11.1 Canonical internal builders, preferred

For the four report artifacts already known today (`CertificationScorecardJson`, `ValidationReportJson`, `CertificationScorecardMarkdown`, `ValidationReportMarkdown`), the redesign's default is **no caller-supplied callback at all** -- four fixed, internal functions (`Get-TPMCertificationScorecardJsonArtifact -Eligibility $e -FactStoreProjection $facts`, and its three siblings), each a pure function from `(TPMEligibilityDecision, detached fact-copy array)` to `(content string)`, with no closure over mutable outer-scope variables (correcting the first draft's own noted minor gap: today's `$buildCertificationArtifacts` closures over `$certification`/`$results`/`$reportDir`). Determinism is checkable directly: calling the same builder twice with the same frozen inputs produces byte-identical content, verified by a regression test.

### 11.2 Where extensibility is genuinely required

If a future artifact category needs a pluggable builder (not currently the case for any of the four existing artifacts), the extensibility point is not "run arbitrary code and manifest-check its output's identity" -- it is a **schema-validated projection function** whose *output* is checked, not merely trusted: the returned content must parse against a fixed schema for that artifact category (e.g. a JSON Schema for the JSON artifacts, or a required-section-headings check for the Markdown ones), and every value the schema requires to trace back to the `TPMEligibilityDecision`/fact projection it was given (e.g. a JSON artifact's `EligibleForCertification` field must literally equal `$Eligibility.EligibleForCertification`, checked by the framework after the callback returns, not merely assumed) -- so a callback that produces schema-valid but *semantically disconnected* content (e.g. hardcoding `"EligibleForCertification": true` regardless of what it was actually handed) is caught by this post-return equality check, not merely by the artifact-identity manifest that never inspected content at all under the current design.

---

## 12. The composed Final Outcome as the only rendered result

**The first draft's error:** it asserted this as a design goal without a concrete guarantee mechanism.

Concrete guarantee: `TPMEligibilityDecision` (Section 8.1) has no property that means "certified," and `TPMPublicationOutcome` (Section 8.2) has no property that means "certified" either -- only `TPMFinalOutcome` (Section 8.3) does, and it is producible only by `New-TPMFinalOutcome`, called exactly once per run, after publication has been attempted (never before). Every consumer of a final result -- console output, the Markdown report, the JSON report, the returned structured result, and the process exit code -- reads from the single `$finalOutcome` variable the main script binds from that one call, and the existing structural-source-text-check pattern already used elsewhere in this pipeline's regression suite (e.g. round 3's "uses the one transaction as the source" test) is extended to assert: no `Write-Host`/report-building/`exit` call site in the main script references `$eligibilityDecision.EligibleForCertification` or `$publicationOutcome.Published` directly as if either were the final answer -- every such site is required to go through `$finalOutcome`. Because the intermediate types structurally cannot express "certified" (Section 8.4), this is not merely a convention the source-text check polices as a backstop -- it is impossible to violate by accident, since there is no field to accidentally read.

---

## 13. Proposed object ownership model (summary)

| Type | Owns | Constructed by | Mutable after construction? |
|---|---|---|---|
| `TPMFactStore` | Raw evidence + check facts (Section 7), keyed by canonical identifier | `New-TPMFactStore`, exactly once per run (Section 5.2) | Append-only until `Seal()`; no field mutation ever, per Section 6 |
| `TPMEligibilityDecision` | `EligibleForCertification` + structured evidence/score eligibility detail (Section 8.1) | `Get-TPMCertificationEligibility`, from a sealed store | No -- frozen at construction (Section 6.7) |
| `TPMPublicationOutcome` | `Published`, `PublicationError`, `CommittedManifestHash` (Section 8.2) | `Publish-TPMCertificationBundle`'s return value | No |
| `TPMFinalOutcome` | `FinalStatus`, `FinalOverall`, `FinalExitCode` (Section 8.3) | `New-TPMFinalOutcome`, exactly once (Section 12) | No |
| Committed manifest (Section 9.1) | Per-artifact ID/filename/destination/length/hash/schema-version/run-identity | The publish step, from the Artifact Builder's output | No (itself a promoted, immutable-on-disk artifact once committed) |

Ownership rule: nothing outside the constructing function for a given type may build one directly with the same effect as a genuine call -- for `TPMFactStore` this is enforced by the token/reference-identity mechanism in Section 5; for the three outcome-related types, by the combination of frozen construction (Section 6.7) and the single-call-site structural tests (Sections 5.2, 12).

---

## 14. Simplified transaction design (concrete flow, no code)

1. `$runToken = [guid]::NewGuid()`; `$factStore = New-TPMFactStore -RunToken $runToken` -- exactly once, at run start.
2. Every check and every evidence capture calls `Add-TPMFactStoreCheck`/`Add-TPMFactStoreEvidence -Store $factStore ...`, which internally re-validate `$Store.OwningRunToken` against `$runToken` before writing (Section 5.4).
3. On `final-certification-result`, `$factStore.Seal()` (Section 6.6).
4. `$eligibility = Get-TPMCertificationEligibility -Store $factStore` -- reads only sealed, reference-identity-verified facts (Section 5.5.2); returns a frozen `TPMEligibilityDecision` (Section 8.1) with **no final-status semantics**.
5. `$factProjection = $factStore.GetFactsForReview()` -- detached copies (Section 6.4), for the Artifact Builder's use.
6. `$artifacts = Get-TPMCertificationScorecardJsonArtifact -Eligibility $eligibility -FactStoreProjection $factProjection` and its three siblings (Section 11.1) -- or, if extensibility is used, a schema-validated callback (Section 11.2).
7. `$manifest = New-TPMCommittedManifest -Artifacts $artifacts -RunToken $runToken` (Section 9.1) -- computes hashes, appends the manifest itself as one more staged artifact.
8. `$publication = Publish-TPMCertificationBundle -Manifest $manifest` (Section 9.2) -- stage, promote non-marker artifacts in manifest order, durably verify each against its manifest hash, promote the manifest/marker last, durably verify it. Returns `TPMPublicationOutcome`.
9. `$finalOutcome = New-TPMFinalOutcome -Eligibility $eligibility -Publication $publication` (Section 8.3, 12) -- the **only** point where `FinalStatus`/`FinalOverall`/`FinalExitCode` come into existence.
10. Reports/console/exit code all read `$finalOutcome` exclusively (Section 12). `exit $finalOutcome.FinalExitCode`.
11. A later, independent read of this run's results (an audit, a release-integrity check) uses `Read-TPMCommittedCertification -ReportDir $dir` (Section 10.1) exclusively -- never re-parses individual report files directly and trusts them without the six-step verification.

---

## 15. Alternatives considered

### 15.1 Do nothing; continue incremental hardening

**Rejected as the primary path.** It's the pattern that produced this ADR. Not free-standing risk, though -- the current implementation remains safe to keep operating while this redesign is planned and phased in.

### 15.2 Full ground-up rewrite

**Rejected.** Section 4's stage-by-stage assessment shows most of the pipeline's structural shape (staged bundle, atomic publish, the concept of a commit marker) is already correct; a rewrite would re-risk already-solved problems for no benefit over a targeted migration.

### 15.3 Score-only provenance ledger, without unifying evidence and score into one Fact Store type

**Rejected as the long-term answer**, retained as an acceptable fallback if the full migration is deprioritized. Closes the immediate score/evidence asymmetry (Section 3.8) but leaves two independently-maintained ownership mechanisms instead of one that generalizes to whatever fact category is discovered next.

### 15.4 Cryptographic signing of evidence/score records themselves (not just the committed manifest)

**Rejected as disproportionate for in-process facts**, while a lighter-weight version is adopted for the *published, on-disk* artifacts (Section 9's SHA-256 manifest binding) where it earns its complexity: on-disk artifacts genuinely need to be verifiable later, by a separate process, potentially after the producing process has exited -- exactly where a hash-bound manifest is the appropriate tool. In-process facts, by contrast, are only ever read within the same run that produced them (Section 5.6's threat-model boundary), where reference-identity and token-checking already close the actually-relevant threat at far lower complexity than per-fact signing would add.

### 15.5 Trusting the marker's presence alone (the first draft's original position)

**Rejected**, per the architecture review and Section 10 -- superseded by the six-step consumer contract.

---

## 16. Four-phase migration plan, with explicit cutover rules

**The first draft's error:** it described four phases in prose without specifying, for each, what was and was not writable, or how the transition between phases avoided a period where both the legacy and new architectures could independently produce a decision.

### Phase 1 -- Introduce the types, read-only compatibility, zero behavior change

- **Authoritative source of truth:** unchanged -- still `$results`/`$certification`/`$script:tpmEvidenceLedger`, exactly as today.
- **Writable components:** `TPMFactStore`, `TPMEligibilityDecision`, `TPMPublicationOutcome`, `TPMFinalOutcome` classes are introduced and unit-tested **in isolation**, with their own dedicated test fixtures -- not yet wired into the main script at all.
- **Read-only compatibility projections:** none needed yet; nothing in the main flow reads the new types.
- **Prohibited legacy writes:** none prohibited -- legacy code is completely untouched this phase.
- **Dual-write prevention:** not applicable -- only one architecture is live (legacy).
- **Rollback boundary:** trivial -- Phase 1 adds new, unused code; reverting is deleting files, no data-model risk.
- **Acceptance gate before advancing to Phase 2:** every new type's own unit tests pass (immutability guarantees per Section 6.8, token/reference-identity checks per Section 5.7) on both PowerShell engines; zero changes to the existing 812-test suite's assertions.
- **Removal point for legacy paths:** none this phase.

### Phase 2 -- Fact recording moves to the new store; legacy `$results`/ledger become read-only mirrors

- **Authoritative source of truth:** `$factStore` becomes authoritative for both evidence and check facts.
- **Writable components:** `Add-TPMFactStoreCheck`/`Add-TPMFactStoreEvidence` are the only fact-recording entry points now called from the main script body (replacing `Add-CheckResult`/`Add-Screenshot`'s internal bodies, though the public function names/call sites in the main script can stay the same during transition -- only their internals change to delegate to the store).
- **Read-only compatibility projections:** `$results.Checks`/`$results.Screenshots` are populated as a **derived, read-only mirror** of the store's contents (via `GetFactsForReview()`, Section 6.4's detached copies) purely so any *reporting* code not yet migrated in this phase still has data to render -- never written to directly, and never read back into a decision.
- **Prohibited legacy writes:** direct `$results.Checks +=`/`$results.Screenshots +=` (or equivalent hashtable mutation) is removed from every call site; the only way a fact enters the system is through the two store-recording functions.
- **Dual-write prevention:** enforced by the prohibition above being a completed removal, not a soft deprecation -- Phase 2 does not ship with both a legacy write path and a store write path simultaneously live; the legacy write statements are deleted in the same change that introduces the store-backed replacements, verified by a structural source-text test (per the existing pattern) asserting zero remaining direct-mutation call sites.
- **Rollback boundary:** revertible as a single atomic commit revert (the phase lands as one reviewed round per Section 16's closing note) -- there is no intermediate, partially-migrated state committed to `main`.
- **Acceptance gate before advancing to Phase 3:** `Get-TPMCertificationEligibility` (reading only from the sealed store) produces identical `EligibleForCertification` results to the current `Complete-TPMCertificationTransaction`'s evidence-pass/score-eligible computation, across the full existing adversarial test matrix (copied-field forgery, reordering, replay -- Section 5.5's tests, now also applied to check facts per Section 7.2's unification) re-targeted at the new store; zero regression in evidence-side adversarial tests.
- **Removal point for legacy paths:** `$script:tpmEvidenceLedger` and direct `$results.Checks`/`$results.Screenshots` mutation are removed entirely this phase, not merely deprecated.

### Phase 3 -- Decision/publication/outcome split; remove in-place mutation

- **Authoritative source of truth:** `TPMEligibilityDecision` for eligibility; `TPMPublicationOutcome` for publish result; `TPMFinalOutcome` for the certification verdict -- three distinct objects, composed, never mutated into each other.
- **Writable components:** `Get-TPMCertificationEligibility`, `Publish-TPMCertificationBundle`, `New-TPMFinalOutcome` -- each producing its own immutable output, none mutating a pre-existing object.
- **Read-only compatibility projections:** `$certification`/`$results`'s `Overall`/`Status`/`ExitCode`/`Finalization` fields (if anything outside the migrated pipeline still reads them during this transitional phase) are populated **once, after `$finalOutcome` exists**, as a final, read-only mirror -- never the other way around, and never mutated a second time afterward.
- **Prohibited legacy writes:** every `Add-Member -Force` currently patching decision state onto `$Certification`/`$Results` in place (today's publish-failure downgrade path) is removed -- publish failure instead produces a `TPMPublicationOutcome` with `Published = $false`, composed into `TPMFinalOutcome` by `New-TPMFinalOutcome`'s ordinary composition rule (Section 8.3), never by mutating a previously-returned object.
- **Dual-write prevention:** `Complete-TPMCertificationTransaction` (the old, single mutating-in-place function) is deleted in the same change that introduces `Get-TPMCertificationEligibility`/`Publish-TPMCertificationBundle`/`New-TPMFinalOutcome` -- both cannot coexist as live, independently-decision-capable paths even transiently within this phase.
- **Rollback boundary:** single atomic commit revert, same discipline as Phase 2.
- **Acceptance gate before advancing to Phase 4:** a test asserting `TPMEligibilityDecision` has no property named `Status`/`Overall`/`ExitCode`/`Passed` (Section 8.4's structural guarantee, checked by reflection over the type's public properties); full existing adversarial matrix re-verified against the new composed-outcome flow; publish-failure-downgrades-in-place test class from round 3 is replaced with publish-failure-produces-FAIL-FinalOutcome tests against the new composition.
- **Removal point for legacy paths:** `Complete-TPMCertificationTransaction` itself is deleted this phase.

### Phase 4 -- Artifact/manifest/consumer-contract completion; documentation rewrite

- **Authoritative source of truth:** the committed manifest (Section 9.1) for "what was published"; `Read-TPMCommittedCertification` (Section 10.1) for "how anything downstream reads a result back."
- **Writable components:** `New-TPMCommittedManifest`, the canonical internal Artifact Builders (Section 11.1).
- **Read-only compatibility projections:** none remain by end of this phase -- this is the phase that removes the last of them.
- **Prohibited legacy writes:** the old `-BuildArtifacts` arbitrary-callback parameter and `Test-TPMArtifactManifest`'s identity-only (non-hash-bound) validation are removed.
- **Dual-write prevention:** `Publish-TPMCertificationArtifacts` (round 3's version, identity-only) is deleted in the same change `Publish-TPMCertificationBundle` (hash-bound) replaces it.
- **Rollback boundary:** single atomic commit revert.
- **Acceptance gate before this ADR is marked Accepted:** every Section 19 acceptance-criterion item is satisfied; `ARCHITECTURE.md`'s certification section is rewritten (not incrementally amended a fifth time) around this ownership model; full verification matrix (ASCII/parse/PSScriptAnalyzer/InjectionHunter/Pester, both engines) passes; no change to PNG structural validation, Smoke File Safety tri-state logic, restoration, packaging, or release behavior, confirmed the same explicit way rounds 1-3 confirmed it.
- **Removal point for legacy paths:** by the end of this phase, no function, type, or code path from the pre-ADR architecture remains reachable from the main script.

**Cross-phase invariant, stated once for all four phases:** at no point during or between phases does the codebase contain two independently-writable, independently-decision-capable representations of the same fact category simultaneously -- each phase either fully migrates a category's write path in one atomic change, or does not touch it yet at all. This directly answers the review's "no phase may allow both legacy and new to remain independently writable or decision-capable."

---

## 17. Expanded trust-boundary analysis

Extending Section 3.8's table with the categories the architecture review specifically named:

| Boundary | Position under this design |
|---|---|
| **17.1 Child-process boundaries** | The certification harness does not currently spawn child processes that participate in fact recording (Pester/PSScriptAnalyzer run in-process or as directly-invoked, synchronously-awaited cmdlets whose *results* are recorded as facts by the parent process, not as independent fact-producers). No fact-recording capability (the run token, Section 5.1) is passed to, or trusted from, any child process. If a future check needs to run out-of-process, its result must be re-validated and recorded by the parent via the normal `Add-TPMFactStoreCheck` path -- a child process is never granted direct fact-store write access. |
| **17.2 Serialization and deserialization** | The only serialization boundary in the redesigned pipeline is the committed manifest and its artifacts (Section 9) -- deliberately hash-bound because they cross a real trust boundary (written by this process, potentially read by a different, later process or session). In-process objects (`TPMFactStore`, `TPMEligibilityDecision`, etc.) are never serialized/deserialized mid-run; PowerShell's `ConvertTo-Json`/`ConvertFrom-Json` round-trip (used only for the final JSON *artifacts*, not for internal state) is explicitly a one-way, outbound-only operation in this design -- nothing deserializes a JSON artifact back into a live `TPMFactStore` or `TPMEligibilityDecision` mid-run. |
| **17.3 External files as observations** | Any check whose raw observed value comes from reading an external file (e.g. a Pester output file, a PSScriptAnalyzer results file) is a fact whose "authorized producer" (Section 7's schema) is still the in-process `Add-TPMFactStoreCheck` call that reads that file and records the result -- the external file itself is not trusted as a fact source directly; it is an input the producer function observes once, at a known point in the run, the same way today's code already reads Pester/PSScriptAnalyzer output into `$results`. |
| **17.4 Concurrent certification runs** | Each run generates its own `$runToken` (Section 5.1) and its own `-ReportDir`/`-ScreenshotDir`. Two concurrent runs never share a `TPMFactStore` instance (each run's main script body calls `New-TPMFactStore` exactly once, for itself). If two concurrent runs' output directories were ever misconfigured to overlap, `Publish-TPMCertificationArtifacts`'s existing (round 3) "destination already exists" pre-stage check would cause the second run's publish to fail closed, rather than silently interleave with the first's artifacts -- this behavior is retained unchanged in `Publish-TPMCertificationBundle`. |
| **17.5 Run-directory ownership** | `-ReportDir`/`-ScreenshotDir` are not independently "owned" by a capability mechanism the way the fact store is -- they are ordinary filesystem paths, protected only by normal OS file permissions and the atomic-publish "destination already exists" check (17.4). This is a deliberately lighter-weight boundary than the in-process fact-store ownership model, consistent with Section 5.6's threat model: filesystem-level tampering by an actor with write access to the report directory is the same class of out-of-scope threat as same-process code tampering, not a gap specific to this design. |
| **17.6 Report-directory/run identity binding** | Closed by Section 9.1's "certification-run identity" manifest field and Section 10.1 step 2/4 -- a reader can detect a report directory whose artifacts don't all agree on the same run identity, which is the concrete mechanism binding a directory's contents to one specific run rather than trusting the directory path alone. |
| **17.7 Producer exceptions** | `Add-TPMFactStoreCheck`/`Add-TPMFactStoreEvidence` catch exceptions from the underlying capture/check logic exactly as today's `Add-Screenshot` does (round 3's existing "evidence creation failed safely" pattern) -- a producer exception becomes a structured `Failed` fact, recorded through the normal ingestion path (Section 7), never an unrecorded silent gap. |
| **17.8 Partial producer completion** | If the main script itself crashes mid-run (after some facts are recorded but before `Seal()`), the store is simply never sealed and never reaches `Get-TPMCertificationEligibility` -- there is no partial-eligibility computation, because eligibility is only ever computed from a *sealed* store (Section 8.1's precondition). The orphaned, unsealed store and its facts are discarded with the process; nothing persists them past the crash (consistent with Section 3.7's existing "no resumption is attempted" assumption, now stated as an explicit precondition of `Get-TPMCertificationEligibility` rather than an implicit property of when it happens to be called). |
| **17.9 Interrupted execution** | Covered by 17.8 (pre-seal) and Section 10 (post-seal, during publication -- the six-step consumer contract's completeness/extra-file checks are exactly what "interrupted after some artifacts promoted" produces, and are rejected). |
| **17.10 Same-process arbitrary code execution** | Explicitly out of scope -- see Section 5.6. Restated here for completeness of this table, not because the boundary differs from Section 5.6's statement. |
| **17.11 Reparse points or symbolic links** | Not currently a concern this pipeline's actual deployment encounters (`-ReportDir`/`-ScreenshotDir` are ordinary local paths created by the harness itself, never user-supplied paths that could be a symlink to an unexpected location) -- explicitly out of scope for this ADR, but flagged here rather than silently unconsidered: if `-ReportDir` or `-ScreenshotDir` ever become externally-supplied/configurable paths in the future, path resolution should use `[System.IO.Path]::GetFullPath` followed by a check against `[System.IO.File]::ResolveLinkTarget` (or equivalent) to detect and reject a reparse point substituting a different physical destination than the one validated at containment-check time -- noted as a **future work item**, not a gap in the current design, since the current design's paths are never externally supplied. |
| **17.12 What is inside vs. outside the supported threat model, stated together** | **Inside:** a caller (test code, or a hypothetical malicious contributor working only through this pipeline's own public functions) constructing a plausible-looking fact, decision, artifact, or manifest object and attempting to have it accepted as genuine, without possessing the real run token or reference-identity to the real store/decision objects. **Outside:** same-process arbitrary code execution/reflection (17.10/5.6); OS-level file-permission or reparse-point tampering with the report directory outside this process's own writes (17.5, 17.11); a compromised PowerShell engine or host process itself; concurrent-run misconfiguration beyond the atomic-publish collision check already in place (17.4). |

---

## 18. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Phase 1's refactor silently changes observable behavior | Zero required changes to the existing 812-test suite's *assertion content* is the explicit Phase 1 gate (Section 16); any assertion-level change signals an unplanned behavior change requiring separate justification. |
| PowerShell `class` semantics introduce a PS-5.1-vs-pwsh-7 compatibility gap | Every new class verified under both engines from Phase 1 onward, per this repository's existing dual-engine verification standard. |
| A capability-token check (Section 5.4) is itself forgettable -- a future contributor adds a new fact-recording path that skips the token check | The structural source-text test pattern (already used for "exactly one `New-TPMFactStore` call," Section 5.2) is extended to assert every function that appends to the store's internal collections is one of exactly the two sanctioned recorder functions -- a new, unsanctioned append site fails this test even before any runtime check would catch it. |
| The six-step consumer contract (Section 10) is expensive to run on every read, discouraging its use in favor of ad hoc file reads | `Read-TPMCommittedCertification` is documented (Section 10.1) as the *only* sanctioned read path; a code-review-enforced rule (mirroring how this repository already enforces "only `Add-Screenshot` appends evidence") that any code reading a certification result must go through it, not re-implement a partial check. |
| Migration spread across four rounds re-introduces the "many rounds, same unaddressed pattern" risk this ADR responds to | Unlike rounds 1-3, all four phases are pre-planned as one coherent migration toward this ADR's single end-state, each with its own closing verification and explicit cutover rule (Section 16), not independently-discovered reactive fixes. |
| Scope creep into PNG validation, Smoke File Safety, or release mechanics | Every phase's acceptance criteria explicitly excludes these, mirroring the scope discipline already demonstrated in rounds 1-3's commit messages. |
| Hash computation (Section 9) adds measurable overhead to every publish | SHA-256 over report-sized text content (kilobytes, not megabytes) is not performance-relevant for a certification run already dominated by Pester-suite execution time; not treated as a risk requiring mitigation, noted only for completeness. |

---

## 19. Acceptance criteria

Implementation on this ADR **may not begin** until this document itself, in its current (revised) form, defines all of the following -- which it now does, at the sections indicated. This section is the explicit gate the architecture review asked for.

- [x] **Workflow-owned provenance** -- Section 5: run capability token, single construction call site, token-checked recording functions, dual rejection mechanism (token mismatch + reference-identity), explicit same-process threat-model boundary, three-way distinction between type/shape/genuine-issuance.
- [x] **Enforceable immutability** -- Section 6: copy-on-ingress, hidden internal records, no shared mutable collections (including why `AsReadOnly()` alone is insufficient), detached egress projections, deep-copy note for nested values, seal-checked mutators, callback isolation from authoritative mutable objects, and an explicit statement of how each mechanism is independently testable.
- [x] **Closed raw-fact schemas** -- Section 7: full schema table for both existing fact categories (evidence, checks), explicit separation of raw observed value from derived conclusion.
- [x] **Pre-publication eligibility vs. final outcome** -- Section 8: `TPMEligibilityDecision` redefined to carry no final-status fields at all; `TPMPublicationOutcome` and the new `TPMFinalOutcome` type; explicit composition rule; explanation of why this is a structural guarantee, not a naming change.
- [x] **Deterministic artifact construction** -- Section 11: canonical internal builders as the default; schema-validated, output-checked extensibility point as the only alternative; explicit rejection of an unconstrained callback.
- [x] **Hash-bound committed manifest** -- Section 9: full manifest field list including SHA-256 content hash and run identity; explicit description of how staging-time hashing binds to durable verification.
- [x] **Consumer verification** -- Section 10: six-step `Read-TPMCommittedCertification` contract, enumerated against every rejection case the review named.
- [x] **One final-outcome authority** -- Section 12: structural (not merely conventional) guarantee that only `TPMFinalOutcome` can express certification status, backed by the intermediate types simply lacking the relevant properties.
- [x] **Phase-specific cutover and rollback rules** -- Section 16: all four phases specify authoritative source of truth, writable components, read-only projections, prohibited legacy writes, dual-write prevention, rollback boundary, acceptance gate, and legacy-removal point, plus a stated cross-phase invariant against simultaneous dual decision-capability.
- [x] **Documented threat-model boundaries** -- Section 17: eleven explicit boundary categories plus a consolidated inside/outside statement, and Section 5.6's same-process caveat restated where relevant.

Once Phase 4 (Section 16) actually lands, this ADR's Status changes from Proposed to Accepted; until then, no phase begins implementation against a criterion this list does not yet mark satisfied by the document itself.

---

## 20. Conclusion

The current architecture is not the simplest viable design, and -- as the first draft of this ADR itself demonstrated by being sent back -- *naming* the right abstractions is not the same as *specifying* them. This revision replaces every previously-named-but-underspecified concept with a concrete PowerShell-realizable mechanism: a capability-token-and-reference-identity-checked Fact Store (Section 5), enforced through copy-on-ingress/egress discipline rather than class-declaration alone (Section 6), a closed schema separating raw facts from derived conclusions (Section 7), a decision boundary that structurally cannot claim final status before publication (Section 8), a hash-bound committed manifest (Section 9) with a six-step consumer contract (Section 10), a constrained rather than arbitrary Artifact Builder (Section 11), a single composed Final Outcome authority (Section 12), an explicit four-phase migration with per-phase cutover rules preventing any dual-decision-capable intermediate state (Section 16), and an expanded trust-boundary analysis naming exactly what is and is not defended (Section 17).

**Recommendation, unchanged from the first draft:** proceed with the four-phase migration, now fully specified, rather than a fifth incremental hardening pass. Implementation may begin only once this document satisfies Section 19's acceptance criteria -- which it now does.
