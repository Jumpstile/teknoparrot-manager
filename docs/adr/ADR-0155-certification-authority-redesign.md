# ADR-0155: Certification Transaction Architecture -- Authoritative Facts, Not Mutable State

**Status:** Proposed. No production code or tests changed as part of this document. Covers `scripts/Invoke-TPM-RealInstanceSmoke.ps1`'s certification-evidence/scoring/publication pipeline (issue #154, PR #155), as of commit `c6bc7ba` on `codex/issue-154-evidence-finalization`.

---

## 1. Context and problem statement

Three independent adversarial review rounds on this pipeline each found a real, distinct forgeability gap:

- **Round 1** (issue #151): evidence-capture correctness -- filename collisions, format masquerading, missing CRC integrity.
- **Round 2** (issue #154, round 1): the transaction wasn't the sole outcome authority -- evidence, score, report status, and process exit could disagree with each other.
- **Round 3** (issue #154, rounds 2-3): the transaction *was* the sole authority, but it still trusted several **descriptions** of workflow activity (a public evidence array, a caller-supplied score-item array, an optional publish callback) rather than **facts the workflow itself owned**. Round 3 fixed this for evidence (a private, reference-identity-checked ledger) and for publication (a mandatory, manifest-validated, atomically-committed artifact set with a durable commit marker).

**Problem statement:** the recurrence itself is the signal worth acting on. Each round's fix was correct and remains valid -- but the pattern (find a data category trusted by shape instead of by ownership, harden it, repeat) suggests the underlying object model, not any single missing check, is producing the findings. Is a fourth incremental hardening pass the right response, or does the pipeline need a different internal model?

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

This is the state after three rounds of genuine, tested hardening. It works -- the current test suite (812 tests) proves every known forgery technique against it fails. This ADR evaluates whether it's the right *shape*, not whether it's currently correct.

---

## 3. Current architecture assessment

### 3.1 What is the authoritative source of truth for certification?

There isn't one. There are **three different bespoke authorities**, each invented in a different round after a different category was separately found forgeable:

| Category | Mechanism | Round introduced |
|---|---|---|
| Evidence | Private append-only ledger, reference-identity check | 3 |
| Score | Shape-only manifest validation of a public array | 3 (manifest), never got an ownership mechanism |
| Publication | Manifest-validated artifact set + atomic commit marker | 3 |

Evidence and publication now have a real *owner* (a private list; an atomic on-disk commit). Score does not -- `$Certification.Items` is still just an array anyone in scope can construct and hand to the transaction, and the manifest only checks that it has the right *shape* (identifiers, count, Boolean types), not that it was genuinely derived from `$results.Checks`/Pester/PSScriptAnalyzer output. A well-formed, entirely fabricated Items array -- correct identifiers, all `Passed = $true` -- is currently indistinguishable from a real one.

### 3.2 What data is immutable?

Actually immutable today: the per-run `WorkflowId` (assigned once), and the evidence ledger's *append* discipline (entries are never rewritten, only added, then sealed).

Not immutable, despite representing settled facts: `$certification.Items` (a plain mutable array of mutable objects), `$certification` itself (`Add-Member -Force`d in place five separate times across a single run: `Overall`, `Status`, `ExitCode`, `ScoreEligible`, `EvidenceFinalization`, `Finalization`, `Screenshots`), and `$results` (an ordered hashtable -- the most mutable structure PowerShell has, with keys added or reassigned from many places across the whole script's lifetime).

### 3.3 What data is derived?

Correctly derived, fresh, at commit time: score `Overall`/`Passed`/`Total`/`ScorePercent` (`Get-TPMCertificationScoreFromItems`, never read off a stale field); evidence pass/fail (recomputed from the ledger every call); final `Status`/`Overall`/`ExitCode` (`scoreEligible AND evidencePassed`, never pre-computed and stored).

"Derived, not trusted" (round 2's core fix) is necessary but not sufficient on its own -- deriving correctly from an *input* that itself has no ownership guarantee (score Items) only pushes the trust problem one level up, which is exactly the gap round 3 closed for evidence and left open for score.

### 3.4 What data is merely presentation?

The provisional `[SHOT]`/`[SKIP]`/`[FAIL]` console lines and the "CERTIFICATION SCORECARD - PROVISIONAL" block; per-record console echoes in `Add-Screenshot`; the Markdown reports' prose sections (environment info, artifact folder path). None of these feed back into any decision -- this boundary is already correctly drawn today and needs no change.

### 3.5 What is the certification transaction boundary?

Currently split across two nested phases inside one function: `Complete-TPMCertificationTransaction`'s own body (evidence + score validation -> decision) is phase one; the `-BuildArtifacts` callback plus `Publish-TPMCertificationArtifacts` is phase two, invoked *from inside* phase one, whose failure **retroactively rewrites phase one's already-computed decision** via `Add-Member -Force` on the same object.

This nesting is itself informative: "commit" is not a single atomic step today, it's a decision followed by a publish that can still veto the decision after the fact, implemented by mutating the decision object in place rather than composing a new outcome from two independent values. It is provably correct (tested), but it is not a clean boundary.

### 3.6 What constitutes "committed"?

Operationally, and correctly: **the commit marker file exists on disk**, having been promoted strictly after every other artifact was durably re-read and verified. This is a genuinely good answer, arrived at only in round 3, and should be preserved and formalized rather than changed. It's the strongest evidence that round 3's design is not far from correct at the *publication* layer specifically.

### 3.7 What guarantees are required after process interruption, crash, or cleanup failure?

- **No partial/inconsistent authoritative output is ever observable** -- satisfied today by stage -> promote -> durably-verify -> marker-last.
- **A crashed run must not silently resume into a corrupted mid-state** -- not addressed, because it's never attempted: every run gets a fresh `$reportDir`/`$screenshotDir`/`WorkflowId`, so a crash just leaves an orphaned, marker-less directory that nothing ever revisits. This is a reasonable, currently-safe assumption, but it is an assumption, not an architectural guarantee.
- **Cleanup failure during rollback must not silently report success** -- satisfied (the existing catch path distinguishes "rolled back cleanly" from "rollback itself failed" and surfaces both).

### 3.8 Trust-boundary table

| Boundary | Protected by | Protects against | Does **not** protect against |
|---|---|---|---|
| Evidence identity | Reference-identity vs. private ledger | Forged/copied/substituted/replayed evidence objects | Direct mutation of a *real* ledger object's fields (caught instead by slower, enumerable field-level re-checks) |
| Evidence ordering | Ledger append-position + seal-on-final | Reordering/replay of the "issued last" claim | (fully covered -- reference-identity already implies positional match) |
| Score validity | Manifest **shape** check only | Malformed/incomplete/wrong-typed Items arrays | A well-formed but entirely fabricated Items array -- nothing ties it to real check output |
| Publication identity | Artifact-manifest Id/destination check | Wrong/incomplete/misdestined artifact sets | An artifact with the *right* Id/destination but *wrong* content -- content correctness is the callback author's responsibility, unverified |
| Publication durability | Stage -> promote -> durable-reread -> marker | Crash/interruption/partial write | External modification between durable-verify and a later read (TOCTOU against an external actor -- out of scope, consistent with SECURITY.md's existing threat model, which does not treat the local filesystem as adversarial) |

The table's clearest signal: **evidence and publication are structurally owned; score is still only shape-checked.** That asymmetry is the best available predictor of where a fourth review round would land if nothing changes.

### 3.9 Can the design be simplified instead of adding more validation?

Yes. The recurring finding has never really been "add one more check" -- it has been "this data category doesn't have a real owner yet." A simpler design doesn't need three bespoke defenses (a ledger for evidence, a shape-manifest for score, a manifest-plus-atomicity for publication); it needs **one rule applied uniformly**: nothing downstream of "checks execute" is trusted unless it's read from an object that was frozen the moment checks finished, enforced by the type system, not by convention.

### 3.10 Would a different internal model eliminate entire classes of attacks?

Yes, three specific changes each eliminate a class, not an instance:

1. **One immutable Fact Store, covering both evidence and score/check facts**, closes the score/evidence asymmetry in 3.8 without writing a single new score-specific validation rule.
2. **A frozen Decision Snapshot, produced once, never mutated** -- contrast with today's `$certification`, `Add-Member -Force`d in place five times per run -- eliminates the "publish failure has to retroactively downgrade an already-returned object" awkwardness.
3. **Staged Bundle -> Atomic Publish -> Commit Marker is already built and tested** (`Publish-TPMCertificationArtifacts`, round 3). The redesign's job here is only to make it the visible top-level shape of the whole system instead of an implementation detail nested inside one function's `try` block.

---

## 4. Proposed seven-stage pipeline

```
Checks execute -> Immutable Fact Store -> Decision Snapshot (frozen) ->
Artifact Builder -> Staged Bundle -> Atomic Publish -> Commit Marker
```

| Stage | Status today | Gap |
|---|---|---|
| Checks execute | **Exists** -- Pester, PSScriptAnalyzer, install health, evidence capture all run inline | None |
| Immutable Fact Store | **Partial** -- exists for evidence only; does not exist for score/check facts | **Largest gap** |
| Decision Snapshot (frozen) | **Partial** -- `$decisionSnapshot` exists but is plain-mutable, and the function still mutates a *different*, already-returned object in place on publish failure | Real, but smaller than it looks |
| Artifact Builder | **Exists** -- `-BuildArtifacts` callback, mandatory and manifest-validated | Minor: closures over mutable outer-scope variables instead of receiving an explicit frozen input |
| Staged Bundle | **Exists** -- `.pending` files in `Publish-TPMCertificationArtifacts` | None |
| Atomic Publish | **Exists** -- promote non-marker, durably verify, promote marker | None |
| Commit Marker | **Exists**, and is already the right definition of "committed" | None |

Four of seven stages need no structural change. The real gap is narrower than "rebuild the pipeline": introduce one real immutable Fact Store type covering both evidence and score facts, and stop mutating the decision object in place after it's been returned.

---

## 5. Proposed object ownership model

### 5.1 Unified `TPMFactStore`

A new type (real PowerShell `class`, not a hashtable/pscustomobject convention) that owns checks (Pester/PSScriptAnalyzer/install-health/restoration results) **and** evidence, superseding both `$results.Checks` and `$script:tpmEvidenceLedger`. Append-only during "checks execute"; `Seal()` once (generalizes the evidence ledger's already-proven seal-on-final pattern to the whole store); every mutator throws after seal. Because it's a real class, `-is [TPMFactStore]` becomes a genuine, unforgeable identity check -- strictly stronger than today's reference-identity-against-a-`List[object]` trick, and it covers evidence *and* score uniformly instead of needing a second bespoke mechanism for each new category that shows up later.

### 5.2 Immutable `TPMDecisionSnapshot`

Owns `Overall`/`Status`/`ExitCode`/`ScoreEligible`/evidence-pass details/score-manifest details. Constructed exactly once, by a pure function (`Get-TPMCertificationDecision -FactStore $store`), from a *sealed* `TPMFactStore`. Never mutated after construction -- not even on publish failure.

### 5.3 Composed `TPMPublicationOutcome`

Owns `Published`/`PublicationError`/the commit-marker path. Produced by attempting publish against a `TPMDecisionSnapshot` plus an artifact set.

### 5.4 `Merge-TPMCertificationOutcome`

A small pure function that composes a `TPMDecisionSnapshot` and a `TPMPublicationOutcome` into the final reported outcome -- replacing today's `Add-Member -Force`-after-return pattern with ordinary value composition.

### 5.5 Ownership rule

Nothing outside the functions that construct these types may build one directly.

---

## 6. Simplified transaction design (concrete flow, no code)

1. Main flow constructs **one** `$factStore = New-TPMFactStore` at run start -- replaces both the evidence-ledger init and much of `$results`'s current role.
2. Every check and every evidence capture writes into `$factStore` through narrow methods (`$factStore.RecordCheck(...)`, `$factStore.RecordEvidence(...)`) -- call sites in the main script barely change; `Add-CheckResult`/`Add-Screenshot` become thin wrappers around store methods instead of hashtable/list mutation.
3. On `final-certification-result`, the store seals (as today). `$decision = Get-TPMCertificationDecision -FactStore $factStore` replaces `Complete-TPMCertificationTransaction`'s validation body -- same validation *content* as today, but reading from a store that is authentic by type identity instead of parameters that have to be checked by hand.
4. `$artifacts = & $BuildArtifacts -Decision $decision -FactStore $factStore` -- same callback shape, now with explicit frozen inputs instead of closures over mutable outer variables.
5. `$publication = Publish-TPMCertificationBundle -Decision $decision -Artifacts $artifacts` -- the existing stage/promote/durable-verify/marker logic, reshaped only to *return* a `TPMPublicationOutcome` instead of mutating its caller's object.
6. `$outcome = Merge-TPMCertificationOutcome -Decision $decision -Publication $publication` -- composes the final `Status`/`Overall`/`ExitCode` exactly as today's downgrade logic does, but as composition, not in-place mutation of an already-returned value.
7. Reports/console read `$outcome`; process exits `$outcome.ExitCode` -- unchanged from today.

---

## 7. Alternatives considered

### 7.1 Do nothing; continue incremental hardening (status quo)

Keep patching the next forgeability gap as review rounds find it, the same way rounds 1-3 did. **Rejected as the primary path** -- it's the pattern that produced this ADR's motivating question in the first place. Each individual patch is real and correct, but the recurrence indicates the *category* of finding (a data source with no real owner) will keep appearing until every category gets one, and patching them one at a time costs a full review round per category discovered rather than closing the pattern once. Not adopted, but also not free-standing risk: the current implementation is safe to continue operating while a redesign is planned, since every round so far has left the system correct, just imperfectly modeled.

### 7.2 Full ground-up rewrite of the certification pipeline

Discard the current implementation and design a new pipeline from scratch around the seven-stage model. **Rejected.** Section 4's stage-by-stage assessment shows four of seven stages are already correct and tested; a ground-up rewrite would re-risk already-solved problems (PNG structural validation, atomic publish, commit-marker semantics) for no benefit over a targeted migration, and would cost far more review/verification cycles than the current codebase's proven 812-test regression suite can amortize.

### 7.3 Add provenance tracking to score Items without a unified Fact Store

Give `$certification.Items` its own bespoke ledger/reference-identity mechanism, mirroring what evidence already has, without unifying the two into one `TPMFactStore` type. **Rejected as the long-term answer**, though it is the smallest possible fix for gap 3.8/3.10's asymmetry. It would close the immediate score/evidence asymmetry but leaves the architecture with two separate, independently-maintained ownership mechanisms (and, by the same pattern that produced rounds 1-3, likely a third and fourth for whatever categories arrive at maturity next -- an artifact category, a config-snapshot category, etc.). A unified `TPMFactStore` is barely more work than a score-specific ledger and generalizes to every future category instead of only the one currently known to need it. Noted as an acceptable **fallback** if the full migration (Section 8) is deprioritized and only the highest-value fix is wanted immediately.

### 7.4 Cryptographic/signed evidence records

Make evidence and score records tamper-evident via a signature or HMAC rather than reference identity and type identity. **Rejected as disproportionate.** The threat model this pipeline actually defends against (per `SECURITY.md`'s existing threat model and this ADR's own trust-boundary table) is a caller constructing a convincing-looking substitute object within the same PowerShell process/script, not an adversary with no code-execution access attempting to forge a cryptographic artifact from outside the process. Reference-identity and real type-identity checks fully close the threat that's actually in scope, at a fraction of the implementation and key-management complexity a signing scheme would add.

---

## 8. Four-phase migration plan

- **Phase 1 (pure internal refactor, no behavior change).** Introduce `TPMFactStore`/`TPMDecisionSnapshot`/`TPMPublicationOutcome` as real classes. Port the evidence ledger's existing seal/reference-identity logic into `TPMFactStore` unchanged. Add check/score recording methods that internally do exactly what `$results.Checks +=`/`New-CertificationScorecard` do today, just through the owned type. If `Complete-TPMCertificationTransaction`'s external inputs/outputs are preserved, the existing 812-test suite should require zero content changes at this phase -- it's the verification gate for the refactor itself.
- **Phase 2.** Migrate `Complete-TPMCertificationTransaction` to read from `$factStore` instead of `$Results`/`$Certification` parameters. This is where score items gain the same authoritative-issuance protection evidence already has, closing the trust-boundary gap in Section 3.8. Score-manifest tests get rewritten to build Items through `$factStore.RecordCheck(...)`, the same migration pattern already proven twice in this repository's history (round 2's and round 3's fixture rewrites).
- **Phase 3.** Split the single mutating `$transaction` object into `TPMDecisionSnapshot` + `TPMPublicationOutcome` + `Merge-TPMCertificationOutcome`. Remove every `Add-Member -Force` currently patching decision state onto `$Certification`/`$Results` in place.
- **Phase 4.** Update main-script call sites; rewrite `ARCHITECTURE.md`'s certification section around the new ownership model (rather than amending it a fourth time); run the full verification matrix (ASCII/parse/PSScriptAnalyzer/InjectionHunter/Pester on both engines) exactly as every prior round required.

Each phase lands as its own reviewed round, not one large rewrite -- consistent with this repository's Specification-Driven Review and problem-class-batching governance standards, and keeps the verification/adversarial-test-rewrite work (already twice rehearsed) manageable per round.

---

## 9. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Phase 1's refactor silently changes observable behavior despite being framed as "no behavior change" | Phase 1's explicit acceptance criterion is zero required changes to the existing 812-test suite's *content* (only its internal fixture-construction mechanics may need to change, not its assertions) -- any assertion-level test change signals a real behavior change that must be justified separately, not folded into the refactor. |
| PowerShell `class` semantics (stricter parse-time type checking, different scoping rules than functions/hashtables) introduce a new class of PS 5.1-vs-pwsh-7 compatibility bug, distinct from the ASCII/em-dash issue this repository has hit before | Verify every new class definition under both Windows PowerShell 5.1 and pwsh 7.6.3 from the first phase, the same dual-engine verification already standard for this repository; do not defer cross-version testing to a later phase. |
| A four-phase migration spread across multiple rounds re-introduces the "unaddressed pattern across multiple rounds" risk this ADR itself is responding to | Each phase has its own closing verification (full test suite both engines, ASCII/parse/PSScriptAnalyzer/InjectionHunter) and its own Review Ready submission -- unlike rounds 1-3, phases 1-4 are pre-planned as one coherent migration with a shared end-state (this ADR), not independently-discovered fixes to independently-discovered gaps. |
| Score-item migration (Phase 2) is the highest-risk phase, since it changes what numeric-score derivation trusts | Land Phase 2 with the exact same adversarial test techniques already proven against evidence in round 3 (copied-field forgery, reordering, replay) re-applied to score items, before considering Phase 2 complete -- this is a known, already-rehearsed verification pattern, not a novel one. |
| Scope creep: "redesign the pipeline" expands into unrelated changes to PNG validation, Smoke File Safety logic, or release mechanics | Every phase's acceptance criteria (Section 10) explicitly excludes changes to PNG structural validation, Smoke File Safety tri-state logic, restoration, packaging, and release behavior, mirroring the scope discipline already demonstrated in rounds 1-3's commit messages. |

---

## 10. Acceptance criteria

This ADR is considered successfully implemented when, for each phase:

- **Phase 1:** `TPMFactStore`, `TPMDecisionSnapshot`, and `TPMPublicationOutcome` exist as real PowerShell classes; the evidence ledger's seal/reference-identity behavior is preserved byte-for-byte in test outcomes; the existing 812-test suite passes unchanged in assertion content on both pwsh 7 and Windows PowerShell 5.1 (only the pre-existing five #148 failures on 5.1 remain); ASCII/parse/PSScriptAnalyzer/InjectionHunter all clean per this repository's standard verification set.
- **Phase 2:** `Complete-TPMCertificationTransaction` reads exclusively from `$factStore` for both evidence and score facts; score items are protected by the same reference-identity/type-identity mechanism evidence already has; the full adversarial test matrix already proven against evidence (copied-field forgery, extra/missing/reordered/replayed records) is re-applied to score items and passes; no regression in the existing evidence-side adversarial tests.
- **Phase 3:** no `Add-Member -Force` remains anywhere in the certification transaction path; `TPMDecisionSnapshot` is verified immutable after construction (a test that attempts to mutate it after return either fails silently-safely or throws, and the attempted mutation has no observable effect on the final outcome); `Merge-TPMCertificationOutcome` is a pure function with dedicated unit tests independent of the full pipeline.
- **Phase 4:** `ARCHITECTURE.md`'s certification section is rewritten (not incrementally amended) around the new ownership model; the full verification matrix (ASCII/parse/PSScriptAnalyzer/InjectionHunter/Pester, both engines) passes; no change to PNG structural validation, Smoke File Safety tri-state logic, restoration, packaging, or release behavior, confirmed the same way rounds 1-3 confirmed it (explicit statement in the closing verification report).
- **Overall:** each phase is reviewed and merged independently, per this repository's Specification-Driven Review standard; this ADR's status is updated from Proposed to Accepted (or superseded by a follow-up ADR) once Phase 4 lands.

---

## 11. Conclusion

The current architecture is **not yet the simplest viable design**, but three rounds of hardening have already, mostly by convergent evolution, built four of the proposed pipeline's seven stages correctly (checks execute; staged bundle; atomic publish; commit marker -- Section 4). The gap is narrower than a rewrite:

1. **Score facts have no owner.** They're derived correctly (Section 3.3) from an input that's only shape-checked, never provenance-checked (Section 3.8) -- the single largest predictor of where the next finding would land.
2. **The Decision Snapshot exists in spirit but not in enforcement** -- a plain mutable object, still patched in place after being returned, rather than a frozen value composed with a separate publication result.

**Recommendation:** proceed with the four-phase migration in Section 8 rather than a fourth incremental hardening pass. It is a genuine simplification -- one ownership rule (frozen Fact Store -> frozen Decision Snapshot -> composed Outcome) replacing three bespoke, incrementally-discovered defense mechanisms -- not a ground-up rewrite, and each phase is independently verifiable against the existing test suite before the next begins.
