# ADR-0155: Certification Transaction Architecture -- Authoritative Facts, Not Mutable State

**Status:** Proposed. No production code or tests changed as part of this document. Covers `scripts/Invoke-TPM-RealInstanceSmoke.ps1`'s certification-evidence/scoring/publication pipeline (issue #154, PR #155), as of commit `c6bc7ba` on `codex/issue-154-evidence-finalization`.

**Revision history:**
- Draft 1: named the abstractions (`TPMFactStore`, `TPMDecisionSnapshot`, "commit marker") without defining what made them authoritative. Returned ARCHITECTURE CHANGES REQUIRED.
- Draft 2: replaced named abstractions with mechanisms, but several were still described conceptually (immutability PowerShell classes cannot actually enforce; an ownership token that is itself an observable, copyable value; check facts that were still interpreted Booleans rather than raw measurements; a decision/publish/decision cycle; unspecified failure-publication and manifest/marker semantics; migration phases without an explicit no-dual-authority rule). This revision (Draft 3) replaces every one of those with a mechanism concrete enough that an implementer never has to infer intent.

---

## 1. Context and problem statement

Three independent adversarial review rounds on the *implemented* pipeline (rounds 1-3, summarized below) each found a real, distinct forgeability gap. Two further independent architecture reviews of *this ADR itself* (the two revisions above) found that describing the fix conceptually is not the same as specifying it concretely -- an abstraction that is merely named, or a mechanism that PowerShell cannot actually enforce the way it's described, reproduces exactly the "named but not proven" failure mode the ADR exists to close.

- **Round 1** (issue #151): evidence-capture correctness -- filename collisions, format masquerading, missing CRC integrity.
- **Round 2** (issue #154, round 1): the transaction wasn't the sole outcome authority.
- **Round 3** (issue #154, rounds 2-3): the transaction trusted *descriptions* of workflow activity rather than *facts the workflow itself owned*.

**Problem statement, restated for this revision:** every architectural guarantee in this document must answer, concretely, "what mechanism enforces this, in PowerShell, today, without relying on a language feature PowerShell classes don't actually provide (true immutability), without relying on an observable value as proof of ownership (which can leak or be guessed), without letting an interpreted conclusion masquerade as an observed fact, and without letting publication and outcome depend on each other in a cycle." Sections 5-16 below are organized so each of the eight review findings that produced this revision maps to exactly one section, stated at the top of that section.

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
        |- validates $Certification.Items against a shape-only manifest
        |- derives score from Items, derives evidence-pass from ledger
        |- Add-Member -Force's Status/Overall/ExitCode/... onto $Certification
        |  and $Results IN PLACE, repeatedly, across the run
        |- builds a decision object, invokes -BuildArtifacts, publishes
        `- on publish failure: mutates the ALREADY-RETURNED decision object
           in place
```

This is the state after three rounds of genuine, tested hardening (812 passing tests). It proves every *previously discovered* forgery technique fails against it -- it does not, by itself, establish that the architecture is structurally incapable of producing the next one, which is the standard this ADR is held to.

---

## 3. Current architecture assessment

### 3.1 Authoritative source of truth
Split across three bespoke, unevenly-strong mechanisms (evidence ledger with reference-identity; score validated by shape only; publication validated by artifact identity only), each invented reactively in a different round.

### 3.2 Immutable vs. mutable data
Actually immutable: the per-run `WorkflowId`; the evidence ledger's append-only discipline. Mutable and repeatedly mutated in place: `$certification.Items`, `$certification` itself, `$results`.

### 3.3 Derived vs. trusted data
Score and evidence-pass are derived fresh at commit time, but from inputs (score Items) with no ownership guarantee -- "derived, not trusted" needs the input to also be authoritative, which it currently isn't for score.

### 3.4 Presentation-only data
Provisional console output and report prose. Correctly non-authoritative already; unchanged by this ADR.

### 3.5 Transaction boundary
Two nested phases in one function; publish failure retroactively mutates an already-returned decision object rather than composing a new outcome. This is the specific defect Section 8 (via Section 6 of this revision) exists to remove.

### 3.6 What "committed" means today
A commit-marker file's existence, promoted last. Correct in spirit, underspecified in what a consumer must check -- see Section 10 (renumbered; publication/manifest/marker semantics, this revision's Finding 6).

### 3.7-3.10
Unchanged from the prior revision; superseded in detail by Sections 15 (trust boundaries) and 16 (simplification/alternatives) below.

---

## 4. Proposed pipeline (revised to remove the publish/outcome cycle -- Finding 4)

```
Checks execute
     |
     v
Immutable Fact Store (raw measurements only -- Finding 3)
     |
     v  Seal()
Eligibility Snapshot (frozen, derives every conclusion -- Finding 1, 3)
     |
     v
Artifact Builder (projects ONLY the Eligibility Snapshot into report content)
     |
     v
Staged Bundle (four reports)
     |
     v
Atomic Publish -> Committed Manifest -> Commit Marker (two artifacts, hash-chained -- Finding 6)
     |
     v
Publication Result (Published: bool: exists only in memory / as a verifiable marker, never embedded in the reports -- Finding 4)
     |
     v
Final Outcome (composed fresh from Eligibility Snapshot + Publication Result,
               both at write time and at every later read time -- Finding 4)
```

The critical correction from the prior draft: **the Artifact Builder consumes only the Eligibility Snapshot, never the Final Outcome.** The Final Outcome does not exist yet when artifacts are built (it cannot -- it requires knowing whether publication succeeded, and the artifacts are what get published). Publication depends on Eligibility; Final Outcome depends on Publication. There is no path in this diagram from Final Outcome back to Publication or to the artifacts -- the apparent cycle in the prior draft existed only because that draft never stated this ordering explicitly.

---

## 5. Finding 1 -- Actual immutability: a concrete, enforceable mechanism

**What was wrong:** the prior draft relied on PowerShell `class` semantics (`hidden` fields, an intended-but-unenforced absence of setters). PowerShell classes do not have a `readonly` property modifier; a `hidden` field remains reachable and settable through several ordinary PowerShell mechanisms (`$obj.psobject.Properties`, `Add-Member -Force`, and simple reflection), none of which require the "same-process arbitrary code" threat this ADR already places out of scope -- they are reachable through ordinary scripting. Describing this as "immutability" overstated what the language actually guarantees.

**The mechanism, concretely: compiled .NET value types with constructor-only assignment, plus string-backed sealed state.** Two techniques, used for two different things:

### 5.1 Language-guaranteed immutable value types, for every frozen output

`TPMFact`, `TPMEligibilitySnapshot`, `TPMPublicationResult`, `TPMFinalOutcome`, and each Committed-Manifest entry are defined as **compiled C# types via `Add-Type -Language CSharp -TypeDefinition "..."`** -- not PowerShell `class`. This repository already uses this exact mechanism (`Get-TPMConsoleWindowRect`'s P/Invoke wrapper), so it is a proven, working pattern on both Windows PowerShell 5.1 and pwsh 7 in this codebase, not a new dependency.

```csharp
public sealed class TPMFinalOutcome
{
    public string FinalStatus { get; }
    public string FinalOverall { get; }
    public int FinalExitCode { get; }
    public TPMFinalOutcome(string finalStatus, string finalOverall, int finalExitCode)
    {
        FinalStatus = finalStatus; FinalOverall = finalOverall; FinalExitCode = finalExitCode;
    }
}
```

This is a **language guarantee**, not a project convention: `{ get; }`-only auto-properties compile to a backing field with no public (or any ordinary-reachable) setter at the CLR level. PowerShell script code has no syntax that can assign `$outcome.FinalStatus = 'PASS'` -- the .NET property system itself rejects it ("property is read-only"), the same way it would reject the equivalent C# statement. This is categorically different from a PowerShell `class`'s `hidden` field, which remains assignable through ordinary PowerShell object-manipulation cmdlets. (Reflection -- `[System.Reflection.FieldInfo]::SetValue` against the compiled type's private backing field -- can still defeat this, exactly as it can defeat a real C# `readonly` field or a C# 9 `record`; this is the same explicitly-out-of-scope, same-process-arbitrary-code threat already stated in Section 15.10/15.6, not a new gap this mechanism introduces.)

### 5.2 Sealed internal state as an immutable string, for the Fact Store specifically

The Fact Store's working area, during "checks execute," is necessarily mutable (facts are appended one at a time) -- this is not claimed to be immutable, and does not need to be; it is protected by ownership (Finding 2), not by immutability. What changes at `Seal()`:

- `Seal()` serializes every accumulated `TPMFact` into a single canonical JSON string: `$this.SealedFactsJson = ($facts | ConvertTo-Json -Depth 6)`.
- `SealedFactsJson` is a `[string]`. **.NET strings are immutable by CLR language guarantee** -- there is no operation that mutates a `[string]` in place; every apparent "modification" produces a new string, leaving the original untouched. This is not a project convention either; it is a property of the CLR type itself.
- After `Seal()` runs, the store's pre-seal mutable list is never read again by any store method -- every accessor added after this point (`GetSealedFacts()`) works exclusively from `SealedFactsJson`, deserializing a **fresh** `TPMFact[]` via `ConvertFrom-Json` on every call.
- Because deserialization always allocates new objects, no two calls to `GetSealedFacts()` can ever return objects that share any mutable state -- this is what "copy-on-write detached primitive snapshot" (one of the review's own suggested mechanisms) means concretely here: the "write" is the one-time serialization at `Seal()`, and every subsequent read is a detached copy taken from that frozen string.

### 5.3 Distinguishing the three guarantee levels, explicitly

- **Language guarantee** (enforced by the CLR/C# compiler, cannot be violated by PowerShell script syntax at all): `{ get; }`-only auto-properties on the compiled types (5.1); `[string]` immutability (5.2).
- **Implementation guarantee** (enforced by this codebase's own function bodies, verifiable by test but not by the language itself): `Seal()` is the only place `SealedFactsJson` is ever assigned; no store method other than `Seal()`'s own body reads the pre-seal mutable list after sealing; `GetSealedFacts()` always deserializes fresh rather than caching and returning a shared deserialized instance.
- **Project invariant** (a discipline this pipeline's code review enforces, not verifiable by either the language or a single function's own logic in isolation): nothing in the certification pipeline ever holds a reference to a `TPMFact`/`TPMEligibilitySnapshot`/etc. instance across a call boundary in a way that lets it be handed to code that shouldn't have decision-relevant access to it; every function that receives one of these types treats it purely as an input to read, never attempts to reconstruct one via anything other than its constructor.

This three-level distinction is stated once, here, and referenced by name (`language guarantee` / `implementation guarantee` / `project invariant`) everywhere else in this document a guarantee is claimed, so a future implementer never has to guess which kind of guarantee a given sentence is making.

---

## 6. Finding 2 -- Ownership proof that is never an observable value

**What was wrong:** the prior draft's `OwningRunToken` was a GUID *stored as data on the object* and compared by value. Any code that could read the token's value (even from a `hidden` field, per Finding 1's own critique of what `hidden` actually protects; or from a log line, an error message, or a debug dump that happened to include it) could then construct an entirely new, unrelated object carrying the same token value and have it accepted -- ownership was reduced to "knows a copyable string," not "is the code the store was actually handed to."

**The mechanism: a closure-held capability, never exposed as object state.**

### 6.1 The recording authority is a scriptblock closure, not a token

`New-TPMFactStore` does not return an object with a settable-looking `OwningRunToken` property. It returns **two** things, only one of which can mutate anything:

```powershell
function New-TPMFactStore {
    $sealed = $false
    $facts = New-Object System.Collections.Generic.List[object]
    $recordFact = {
        param($Fact)
        if ($sealed) { throw 'fact store is sealed' }
        $facts.Add($Fact)
    }.GetNewClosure()
    $sealFn = {
        $script:sealed = $true   # closure-local, see 6.2 for the precise capture note
        # ... serialize $facts into the immutable SealedFactsJson (Section 5.2) ...
    }.GetNewClosure()
    $reader = New-TPMFactStoreReader ...   # read-only handle, Section 6.3
    [pscustomobject]@{ Recorder = $recordFact; Seal = $sealFn; Reader = $reader }
}
```

`$recordFact` is a `[scriptblock]` produced by `.GetNewClosure()` -- a real, working PowerShell mechanism (not hypothetical) that captures `$facts` and `$sealed` *by lexical reference* into the closure's own private execution context. The only way to add a fact to this specific store instance is to invoke *this specific scriptblock instance* -- `& $recordFact $someFact`. There is no property, field, or token whose *value* another piece of code could present to achieve the same effect; the authority is the closure reference itself, and a closure reference is not a value that can be reconstructed by knowing what it "looks like" -- it either is a reference to that exact closure, obtained from that exact `New-TPMFactStore` call, or it is not, with nothing in between.

### 6.2 Who obtains the recorder

Exactly the caller of `New-TPMFactStore` -- the main script body, at run start (unchanged cardinality from the previous revision's Section 5.2: exactly one call per run). `Add-TPMFactStoreCheck -Recorder $recordFact -Fact ...` and `Add-TPMFactStoreEvidence -Recorder $recordFact -Fact ...` take the closure itself as their mandatory parameter and invoke it -- they do not take the store object and a token; they take the capability directly. Nothing else in the script ever receives `$recordFact` -- it is not returned by the `Reader` handle (6.3), not embedded in any fact, not logged, not serialized.

### 6.3 The read side has no recording power at all

`$store.Reader` (or however the read handle is named) exposes only `GetSealedFacts()` (Section 5.2) and nothing else -- it does not expose `$recordFact`, does not expose `$sealFn`, and cannot be used, no matter what is done with it, to add or seal facts. **Possessing the reader, or the whole returned `[pscustomobject]` wrapper, proves nothing about recording authority** -- this directly satisfies the review's stated property: "consumers must never obtain the authority simply by possessing the object." The Artifact Builder (Section 4) receives only a `Reader`-equivalent detached fact projection (Section 5.2's fresh deserialization) and the Eligibility Snapshot -- never the recorder closure, never the store's mutable internals.

### 6.4 Why this is stronger than a compared value, restated plainly

A compared value (GUID, string, number) can always, in principle, be copied by anything that once observed it -- the security property of a comparison is only as strong as the value's secrecy, and Section 6 of the prior draft never actually kept the token secret (it was a "hidden" object field, readable through ordinary PowerShell reflection-adjacent mechanisms per Finding 1). A closure reference is not observed as a value at all -- there is no `Get-Something -Value` operation that yields "the recorder" as data; either a piece of code is the one specific caller `New-TPMFactStore` handed the scriptblock reference to, or it never had it, and no amount of inspecting the store, the reader, or any fact can manufacture it. This is the "closure-held capability" mechanism from the review's own example list, chosen over "private run context" or "registry-owned identity" because it requires no additional state (a private context/registry is itself one more piece of state that would need its own protection) and is directly expressible in PowerShell today via `.GetNewClosure()`, already a standard idiom.

---

## 7. Finding 3 -- Raw facts, not interpreted conclusions

**What was wrong:** the prior draft's check-fact schema stored a pre-computed Boolean (`the check's raw pass/fail Boolean as directly observed`) -- calling a Boolean verdict "raw" does not make it a measurement; a pass/fail Boolean is already the output of applying a judgment to some more primitive observation, and storing it in the Fact Store let a fabricated Boolean substitute for the judgment the Eligibility Snapshot is supposed to be the only place that computes.

**The principle, stated precisely (needed because the raw/interpreted line is genuinely subtle in a few cases):** a fact is raw if it is the most primitive value a producer function directly observes -- a count, a byte length, a hash, an existence check's own literal return value, a version string, a path. A fact is an interpreted conclusion if it is the result of applying a pass/fail *threshold or comparison* to some more primitive observation. `Test-Path $x` returning `$true` is a raw observation (it is the atomic thing the .NET/PowerShell runtime directly reports); `$FailedTests -eq 0` is a conclusion (it applies a threshold to a more primitive count). The Fact Store holds the former category exclusively; the Eligibility Snapshot computation (Section 8) is the only place the latter category is ever produced.

### 7.1 Revised check-fact raw-value schema, per category

| Canonical identifier | Raw observed measurement (replaces the prior draft's Boolean) |
|---|---|
| `Pester` | `TotalTests`, `PassedTests`, `FailedTests`, `SkippedTests` (four raw integer counts) |
| `Static Analysis` | `FindingsCount` (raw integer; optionally the raw findings list itself, if downstream reporting needs the detail, but eligibility only ever reads the count) |
| `Real Install Health` | The individual raw signals `Test-TPMInstallHealthGate` itself directly observes (e.g. each sub-check's own literal result), recorded as a set of named raw observations rather than pre-collapsed into one verdict -- the specific sub-signals are an implementation detail of that gate, ported unchanged in *shape*, only moved one level earlier (recorded before collapse, not after) |
| `Backups` | `UserProfilesBackupExists`, `GameProfilesBackupExists` (each the literal `Test-Path`-equivalent observation, not a judgment about whether backups are "sufficient") |
| `Smoke File Safety` | `SnapshotAdded`, `SnapshotRemoved`, `SnapshotChanged` (raw diff counts, per area if the underlying snapshot mechanism already reports per-area -- already close to raw in today's implementation, ported as-is) plus `SmokeModeActive` (the literal `-RunUnattendedTPM`-derived observation of which mode this run is, since applicability itself is derived from this raw fact, not stored as a pre-computed applicability judgment) |
| `pcsx2x6 crosshair path (issue #79)` | `ExpectedCanonicalPath`, `ObservedPath` (both raw strings; the equality comparison is a conclusion, computed only in Eligibility) |
| `Behavioral Certification (Virtual Beta Tester)` | `Total`, `Passed`, `Failed` (raw counts, mirroring Pester) |
| `Unattended TPM root binding` | `RequestedRoot`, `EffectiveRoot` (both raw strings; the comparison is a conclusion) |
| `Unattended TPM config restoration` | `ExpectedHash`, `ObservedHash` (both raw hash values of the config file's content before/after; the hash *comparison* -- do they match -- is a conclusion computed in Eligibility, per the review's own worked example for this exact category) |
| `Repository` | `RepositoryAvailable` (the literal existence/accessibility observation), `GitStatusRaw` (the raw `git status` text) -- "is the repository in an acceptable state" is a conclusion over these; "does `git status` return this text" is not |

### 7.2 What this changes about the Eligibility Snapshot

`Get-TPMCertificationEligibility` (Section 8) is now the **only** place any of the following comparisons happen: `FailedTests -eq 0`, `FindingsCount -eq 0`, `ExpectedCanonicalPath -ceq ObservedPath`, `ExpectedHash -eq ObservedHash`, and the equivalent threshold/comparison for every other category. No fact, anywhere, is permitted to already encode a pass/fail verdict -- if a future contributor adds a new check-fact category whose "raw value" is a pre-computed Boolean, that is a defect against this ADR's schema, not a legitimate new fact category, exactly as strictly as the existing PNG-structural-validation rules are enforced against new evidence categories.

### 7.3 Evidence facts (unchanged from the previous revision -- already raw)

Evidence facts (a captured file's path plus its structural PNG validation result) were already raw measurements in the prior revision -- "does this decode as a structurally valid PNG of positive dimensions" is an observation about the file, not a judgment about whether the certification should pass because of it (the judgment -- "is this required evidence's presence what certification needs" -- is applied in Eligibility, same as check facts). No change to Section 7's evidence schema from the previous revision is needed; only the check-fact schema (7.1 above) required correction.

---

## 8. Finding 4 -- Breaking the Outcome -> Publish -> Outcome cycle

**What was wrong:** the prior draft's `TPMFinalOutcome` was positioned as if it were an input the Artifact Builder or publication step might need, while also being described as composed *from* the publication result -- read literally, this implies final reports (built before publication) would need to already know the final outcome (which depends on publication), a genuine circular dependency the prior draft never explicitly resolved.

**The fix: four distinct, one-directionally-dependent objects, and an explicit statement of which object each downstream consumer reads.**

### 8.1 The four objects, restated with corrected dependencies

1. **Raw Facts** (Section 5-7) -- the sealed Fact Store's content. Depends on nothing else in this list.
2. **Eligibility Snapshot** (`TPMEligibilitySnapshot`, renamed from the prior draft's `TPMEligibilityDecision` to match this ADR's stage-diagram terminology) -- computed from Raw Facts alone, by `Get-TPMCertificationEligibility -Reader $factStoreReader`. Depends only on (1).
3. **Publication Result** (`TPMPublicationResult`, renamed from `TPMPublicationOutcome`) -- produced by attempting to publish artifacts that were built from (2) alone. Depends only on (2) -- **never on Final Outcome, because Final Outcome does not exist yet at this point in the run.**
4. **Final Outcome** (`TPMFinalOutcome`) -- composed from (2) and (3) together, by `New-TPMFinalOutcome -Eligibility $eligibility -Publication $publicationResult`. Depends on both, produced only after both already exist.

### 8.2 What the Artifact Builder actually receives (this is what breaks the cycle)

The Artifact Builder (Section 4, Section 11 of the prior revision, unchanged in this revision) receives **only the Eligibility Snapshot and the detached fact projection** -- never the Publication Result, never a Final Outcome, because neither exists at artifact-build time. The report content it produces therefore contains the Eligibility Snapshot's own fields (`EligibleForCertification`, and the structured evidence/score eligibility detail) -- **the reports say whether the run was eligible for certification, not whether they themselves were successfully published**, which is a question a report cannot answer about itself for the same reason round 3 already discovered (a `Published` field baked into content generated before publication is attempted is always stale or meaningless).

### 8.3 What "Final reports derive from Final Outcome" actually means

Not that the on-disk artifact *content* contains Final Outcome fields (Section 8.2 explains why that's impossible without a cycle) -- it means the **rendered, consumer-facing result** (console output at write time; `Read-TPMCommittedCertification`'s return value at read time, per Finding 6) is always computed by composing Eligibility with a freshly-determined Publication state:

- **At write time:** immediately after `Publish-TPMCertificationBundle` returns its `TPMPublicationResult`, the main script calls `New-TPMFinalOutcome -Eligibility $eligibility -Publication $publicationResult` once, and every write-time consumer (console `Write-Host`, the process exit code) reads that single `$finalOutcome` value. This is unchanged from the prior revision's Section 12 guarantee.
- **At read time** (a later, independent process auditing a committed bundle): there is no stored `TPMFinalOutcome` to read back at all -- `Read-TPMCommittedCertification` (Finding 6) reconstructs one, fresh, by (a) reading the Eligibility Snapshot fields embedded in the verified artifacts, and (b) treating "the commit marker validated successfully" as proof that `Publication.Published` was `$true` for this bundle (if it weren't, per Finding 5, no marker would exist to find) -- then calling the same `New-TPMFinalOutcome` composition function a second, independent time. **The composition function is pure and produces the same result from the same two inputs regardless of whether it's called at write time or read time**, which is what makes this not a cycle: nothing is ever read back into itself, because Final Outcome is never itself the thing being read -- Eligibility and (proof of) Publication are.

### 8.4 Explicit non-cyclic dependency graph

```
Raw Facts --> Eligibility Snapshot --> Artifact content (report bodies)
                    |                        |
                    |                        v
                    |                  Staged Bundle --> Atomic Publish --> Publication Result
                    |                                                             |
                    v                                                             v
                    +----------------------> New-TPMFinalOutcome <----------------+
                                                     |
                                                     v
                                          Final Outcome (write-time console/exit
                                          code; OR read-time, recomputed fresh
                                          by Read-TPMCommittedCertification)
```

Every arrow points forward exactly once; nothing downstream of Final Outcome feeds back into anything upstream of it.

---

## 9. Finding 5 -- Failure publication, defined as rigorously as success

**What was wrong:** the prior draft never stated whether a NOT CERTIFIED run publishes anything, leaving "what does a failed run's on-disk output look like" entirely to inference.

### 9.1 What reports exist for a failed run

**Identical to a successful run: the same four report artifacts plus the Committed Manifest plus the Commit Marker (Finding 6).** There is no reduced or different artifact set for a failure -- Section 9 of the prior revision's manifest (now Finding 6's two-artifact chain) is produced unconditionally by every run that reaches the publish step, regardless of `EligibleForCertification`.

### 9.2 Which artifacts are required

The same closed artifact-identity set (Section 11 of the prior revision, unchanged) for every outcome. `Test-TPMArtifactManifest`'s (successor's) required-identity check has no `EligibleForCertification`-conditional branch.

### 9.3 Do failures produce committed bundles

**Yes.** A NOT CERTIFIED run's bundle is committed (Committed Manifest + Commit Marker both promoted and durably verified) exactly like a CERTIFIED run's, *provided publication itself succeeds* -- eligibility and publication are orthogonal (Section 8.1's dependency graph: Publication depends only on Eligibility's *content*, not on Eligibility's *verdict*; a `-BuildArtifacts`-equivalent step runs, and a publish attempt happens, whether `EligibleForCertification` is `$true` or `$false`). This preserves the current, correct, already-relied-upon operational behavior: testers and auditors need durable, verifiable evidence of *why* a run failed, not only proof that passing runs passed. The only case with *no* committed bundle at all is when publication itself throws (Section 9.5).

### 9.4 How NOT CERTIFIED is represented

Inside the committed, hash-verified artifacts themselves: the Eligibility Snapshot's `EligibleForCertification = $false`, plus its structured `EvidenceEligibility`/`ScoreEligibility` detail explaining which raw facts (Section 7) caused it, rendered into the report content by the Artifact Builder exactly as a `$true` value would be -- there is no separate "failure report format," only the same template rendering a different (still fully specified) Eligibility Snapshot.

### 9.5 Consumer behavior

`Read-TPMCommittedCertification` (Finding 6) returns two logically independent pieces of information, and callers must check both, not conflate them: **`Valid`** (was this bundle genuinely, completely, tamper-free committed -- a question about publication integrity) and **`FinalOutcome.FinalStatus`** (was the underlying run certified -- a question about eligibility). A validly-committed bundle for a failed run returns `Valid = $true` (the bundle is real and trustworthy) with `FinalOutcome.FinalStatus = 'FAIL'` (the run itself did not certify) -- these are not the same axis, and this document states explicitly, here, that a consumer conflating them (e.g. treating `Valid = $true` as if it meant "certified") is a caller-side bug the API surface does not itself prevent by naming alone; call sites and their own tests are responsible for reading `FinalOutcome.FinalStatus`, not `Valid`, when the question is "did this run pass."

### 9.6 Commit-marker behavior

Identical mechanism for both outcomes (Section 8.2/8.3's rule that the marker/manifest never embed Publication or Final Outcome fields applies regardless of Eligibility's verdict) -- the marker does not, and structurally cannot, encode PASS/FAIL itself; it only proves the bundle (whatever Eligibility content it wraps) was durably and completely committed. A reader determines PASS/FAIL only by reading the Eligibility Snapshot content the marker's hash chain (Finding 6) already proved was genuinely part of this commit -- never from the marker's own bytes directly.

---

## 10. Finding 6 -- Manifest and commit marker: two artifacts, explicitly defined

**What was wrong:** the prior draft's Section 9 introduced a "committed manifest" containing per-artifact hashes while simultaneously describing it as effectively the same thing as round 3's existing "commit marker," without ever stating whether these were one artifact or two, or (if two) how they relate.

**Decision: two artifacts, in a three-tier hash chain.**

### 10.1 Identities

| Artifact | Identity (in the closed artifact-identity manifest) | Contains |
|---|---|---|
| Report artifacts (four, unchanged) | `CertificationScorecardJson`, `ValidationReportJson`, `CertificationScorecardMarkdown`, `ValidationReportMarkdown` | Eligibility Snapshot content, rendered (Section 8.2) |
| **Committed Manifest** (new) | `CommittedManifest` | For each of the four report artifacts: canonical filename, canonical destination, byte length, SHA-256 hash, schema-version, certification-run identity (the full field list from the prior draft's Section 9.1) |
| **Commit Marker** (existing, round 3, extended) | `CommitMarker` | A minimal record: schema-version, certification-run identity, and -- new in this revision -- the SHA-256 hash **of the Committed Manifest artifact itself** |

### 10.2 Ordering

Strict three-tier promotion order, all within the same atomic staged-bundle operation (Section 6 of the prior revision's stage/promote/durably-verify sequence, unchanged in its atomicity guarantees): the four report artifacts are staged and promoted first (fixed order, as today); the Committed Manifest is staged and promoted second, after all four reports are durably verified against the hashes it itself declares; the Commit Marker is staged and promoted **last**, only after the Committed Manifest is durably verified against the hash the Marker itself embeds.

### 10.3 Hashes and dependency, explicit

```
Report 1 --hash--\
Report 2 --hash---+--> Committed Manifest (embeds all four hashes)
Report 3 --hash---+          |
Report 4 --hash--/           v
                        hash of Committed Manifest
                              |
                              v
                        Commit Marker (embeds that one hash)
```

The Marker depends on (embeds a hash of) the Manifest; the Manifest depends on (embeds hashes of) the four reports. Verifying the Marker alone proves nothing about the reports directly -- it proves the Manifest it points to hasn't changed since the Marker was written; verifying the Manifest against its own embedded hashes is what actually proves the four reports haven't changed. A consumer must walk the whole chain (Section 10.4), not stop at the Marker.

### 10.4 Consumer validation (`Read-TPMCommittedCertification`, six steps, revised to reflect the two-artifact chain)

1. Marker exists at the expected path. Absence -> reject, "not committed."
2. Marker's embedded certification-run identity matches the run identity the caller expects (if checking a specific run) -- rejects a marker copied from a different run.
3. Manifest exists, parses, and its SHA-256 hash matches the hash the Marker embeds -- rejects a marker paired with a substituted or stale manifest.
4. For each of the four report artifacts the Manifest lists: file exists at the Manifest's canonical destination; filename matches; byte length matches; SHA-256 hash matches the Manifest's own recorded hash for that artifact.
5. Completeness: every artifact ID the Manifest declares is present (missing -> reject, "partial publication"), and no additional file in the report directory matches a known authoritative filename pattern without being listed in the Manifest (extra/debris file -> reject).
6. Only if 1-5 all pass: parse the Eligibility Snapshot fields out of the verified report artifacts, treat step 1-5's success as proof `Publication.Published = $true` for this bundle, and compute `FinalOutcome` via `New-TPMFinalOutcome` (Section 8.3's read-time recomposition) before returning `Valid = $true` plus the computed outcome.

This is the same six-step count and the same rejection coverage as the prior revision's Section 10, restructured to reflect that step "verify the manifest" and step "verify the marker" are now two distinct, hash-chained steps rather than one artifact wearing both names.

---

## 11. The Artifact Builder as a deterministic projection (unchanged from the prior revision's Section 11, restated briefly)

Canonical internal builder functions, pure from `(Eligibility Snapshot, detached fact projection)` to `(content string)`, no closures over mutable outer state; a schema-validated, output-checked extensibility point if a pluggable builder is ever genuinely needed, never an unconstrained callback. Section 8.2 above adds the explicit constraint that the builder's *input* is the Eligibility Snapshot only, never a Publication Result or Final Outcome, which did not exist as an explicit rule in the prior revision.

---

## 12. The composed Final Outcome as the only rendered result (unchanged in guarantee, restated with corrected terminology)

`TPMEligibilitySnapshot` and `TPMPublicationResult` have no property that means "certified" -- only `TPMFinalOutcome` does, producible only by `New-TPMFinalOutcome`, called once at write time and recomputed identically (Section 8.3) at read time, never stored as a field inside a published artifact (Finding 4's resolution makes this the reason, not merely an assertion). Every write-time consumer (console, exit code) and every read-time consumer (`Read-TPMCommittedCertification`'s return value) derives from a `TPMFinalOutcome` computed by that one function, from those two inputs, and nothing else.

---

## 13. Proposed object ownership model (summary, updated names and mechanisms)

| Type | Owns | Constructed by | Immutability mechanism (Finding 1) | Ownership mechanism (Finding 2) |
|---|---|---|---|---|
| Fact Store (mutable, pre-seal) | Accumulating `TPMFact` list | `New-TPMFactStore`, once per run | N/A -- protected by ownership, not immutability | Closure-held `Recorder`/`Seal` scriptblocks (Section 6) |
| Sealed Fact Store state | `SealedFactsJson` | `Seal()`, once | `[string]` CLR immutability (5.2) | Same closures; sealed state read only via fresh-deserialize accessor |
| `TPMFact` | One raw measurement (Section 7) | Compiled C# constructor, via `Recorder` | `{ get; }`-only compiled type (5.1) | Only constructible by the ingestion functions holding the `Recorder` |
| `TPMEligibilitySnapshot` | `EligibleForCertification` + structured detail (Section 8.1) | `Get-TPMCertificationEligibility`, from sealed state | Compiled type (5.1) | Only constructible by that one function |
| `TPMPublicationResult` | `Published`, `PublicationError` (Section 8.1) | The publish step's return value | Compiled type (5.1) | Only constructible by that one function |
| `TPMFinalOutcome` | `FinalStatus`, `FinalOverall`, `FinalExitCode` (Section 8.1) | `New-TPMFinalOutcome`, write-time once + read-time recompute (Section 8.3) | Compiled type (5.1) | Only constructible by that one function |
| Committed Manifest / Commit Marker (Section 10) | Hash chain over the report artifacts | The publish step | Immutable once promoted (on-disk, atomic) | Publish step is the sole writer; consumer contract (10.4) is the sole reader path |

---

## 14. Simplified transaction design (concrete flow, no code, corrected for Findings 2/4/6)

1. `$factStore = New-TPMFactStore` -- returns `{ Recorder, Seal, Reader }` (Section 6.1). Only the main script body ever holds `Recorder`/`Seal`.
2. Every check/evidence capture calls `Add-TPMFactStoreCheck`/`Add-TPMFactStoreEvidence -Recorder $factStore.Recorder -Fact ...`, recording **raw measurements only** (Section 7).
3. On `final-certification-result`, `& $factStore.Seal` -- transitions to the immutable `SealedFactsJson` representation (Section 5.2).
4. `$eligibility = Get-TPMCertificationEligibility -Reader $factStore.Reader` -- the only place any pass/fail comparison happens (Section 7.2); returns a `TPMEligibilitySnapshot` with **no final-status fields at all**.
5. `$artifacts = <canonical builders> -Eligibility $eligibility -FactProjection ($factStore.Reader.GetSealedFacts())` -- the four report contents, built from Eligibility alone (Section 8.2).
6. `$manifest = New-TPMCommittedManifest -Artifacts $artifacts -RunIdentity $runIdentity` -- hashes the four reports (Section 10.1).
7. `$publicationResult = Publish-TPMCertificationBundle -Manifest $manifest` -- stages/promotes the four reports, then the Manifest, then the Marker (Section 10.2), durably verifying the hash chain at each tier; returns `TPMPublicationResult`.
8. `$finalOutcome = New-TPMFinalOutcome -Eligibility $eligibility -Publication $publicationResult` -- the only point `FinalStatus`/`FinalOverall`/`FinalExitCode` come into existence (Section 8.1.4).
9. Console/exit code read `$finalOutcome` exclusively. `exit $finalOutcome.FinalExitCode`.
10. A later, independent read uses `Read-TPMCommittedCertification -ReportDir $dir` exclusively (Section 10.4), which recomputes a `TPMFinalOutcome` fresh rather than trusting any stored one.

---

## 15. Expanded trust-boundary analysis (unchanged in substance from the prior revision; renumbered)

Child-process boundaries; serialization/deserialization (now including the explicit note that `SealedFactsJson`'s `ConvertTo-Json`/`ConvertFrom-Json` round-trip, Section 5.2, is an internal freezing mechanism, not a trust boundary crossing -- the trust boundary remains only the on-disk committed artifacts, Section 10); external files as observations; concurrent certification runs; run-directory ownership; report-directory/run identity binding (now additionally enforced by the Manifest/Marker hash chain, Section 10.3, not only by an identity field); producer exceptions; partial producer completion; interrupted execution; same-process arbitrary code execution (explicitly out of scope, restated from Section 6.4/5.1's reflection caveat); reparse points/symlinks (future work item, not a current gap); and a consolidated inside/outside statement -- all as detailed in the prior revision, carried forward unchanged except where Sections 5-10 above sharpen a mechanism the trust-boundary table already referenced.

---

## 16. Alternatives considered (unchanged from the prior revision)

Do-nothing/continue incremental hardening (rejected -- the pattern that produced this ADR); full ground-up rewrite (rejected -- most of the pipeline's shape is already correct); score-only provenance ledger without unifying into one Fact Store (rejected as the long-term answer, acceptable fallback); cryptographic signing of in-process facts themselves rather than only the on-disk manifest (rejected as disproportionate for a same-process-only threat, per Section 6.4's ownership mechanism already closing the relevant gap without it); trusting marker presence alone (rejected, superseded by Section 10's chain).

---

## 17. Four-phase migration plan, with no dual decision authority (Finding 7) and an explicit publisher timeline (Finding 8)

**What was wrong:** the prior draft's phases specified writable/read-only components but never stated whether a phase could run the new and legacy decision logic *simultaneously* in a way that made either one authoritative depending on circumstance, and never named which function actually calls the publish step at each phase.

**The rule, stated once, applied to every phase below:** each phase names exactly one **authoritative source** (the only computation whose result reaches the console, the exit code, and the publish step) and, optionally, a **shadow source** (a second computation, run in parallel, whose result is logged for comparison and never read by anything that affects behavior). A shadow source is explicitly permitted; a second *authoritative* source, even briefly, is not. Each phase also names its **publication authority** -- the one function that actually calls a publish operation -- answering Finding 8 in the same table.

| Phase | Authoritative source | Shadow source | Prohibited actions | Publication authority (Finding 8) |
|---|---|---|---|---|
| **1** | Legacy (`$results`/`$certification`/`Complete-TPMCertificationTransaction`, unchanged) | None -- new types (`TPMFact`, `TPMEligibilitySnapshot`, etc.) exist only in isolated unit tests, not wired into the running pipeline at all | New types must not be constructed from, or compared against, any live run's data this phase | `Publish-TPMCertificationArtifacts` (round 3, unchanged) |
| **2** | Legacy (unchanged) | New: `TPMFactStore` records the *same* facts the legacy path records (both are written to, from the same call sites, for comparison purposes only), and `Get-TPMCertificationEligibility` computes a shadow `TPMEligibilitySnapshot`, logged (e.g. to a diagnostic file) but never read by console output, exit-code logic, or the publish step | The shadow Eligibility computation must not write to `$results`/`$certification`; must not be read by any report-rendering or exit-code call site; must not trigger its own publish attempt (exactly one publish call per run, by the authoritative/legacy path) | `Publish-TPMCertificationArtifacts` (still legacy, unchanged) |
| **3** | **New** (`Get-TPMCertificationEligibility` / `Publish-TPMCertificationBundle` / `New-TPMFinalOutcome`) -- authority flips here, once Phase 2's shadow comparison has demonstrated equivalence across the full adversarial matrix (both evidence- and now check-fact-side, per Finding 3's schema change) | None -- legacy is fully removed in this same phase, not merely demoted to shadow (removing the two-decision-engine risk entirely rather than prolonging it) | `Complete-TPMCertificationTransaction` and every direct `$results.Checks`/`$results.Screenshots`/`Add-Member -Force`-on-decision-state call site are deleted in the same change that flips authority -- both cannot coexist even transiently | **`Publish-TPMCertificationBundle`** (new, hash-chained per Finding 6) -- cutover from `Publish-TPMCertificationArtifacts` happens in this one atomic change; the old publisher is deleted in the same commit |
| **4** | New (unchanged from Phase 3) | None | The old `-BuildArtifacts` arbitrary-callback parameter and identity-only (non-hash-bound) manifest validation are removed entirely | `Publish-TPMCertificationBundle` (unchanged from Phase 3 -- this phase adds `Read-TPMCommittedCertification` and completes documentation; the publisher itself does not change again) |

**Why Phase 2's shadow comparison satisfies "shadow comparison is acceptable, decision authority is not":** the shadow computation in Phase 2 genuinely runs, on real data, every real run -- it is not a no-op placeholder -- but its result reaches nowhere a human or the process exit code would observe it during that phase; it exists solely to accumulate evidence (a diagnostic comparison log across many real runs) that the new engine agrees with the legacy engine before Phase 3 ever lets the new engine's result reach anything authoritative. This is the concrete difference between "shadow" (observed, not decisive) and "dual authority" (either could be decisive, even briefly) the review's finding asked this ADR to make unambiguous.

**Per-phase acceptance gates, rollback boundaries, and legacy-removal points** are otherwise unchanged from the prior revision's Section 16 (each phase: single atomic commit, revertible as a unit; Phase 2's gate is shadow-vs-legacy equivalence across the adversarial matrix; Phase 3's gate is the structural type-reflection test proving `TPMEligibilitySnapshot` has no final-status properties; Phase 4's gate is the full Section 19 acceptance-criteria list below).

---

## 18. Risks and mitigations (updated for this revision's new mechanisms)

| Risk | Mitigation |
|---|---|
| `Add-Type -Language CSharp` compiled types (Finding 1) behave differently under Windows PowerShell 5.1's older C# compiler vs. pwsh 7's | This repository already relies on `Add-Type -Language CSharp` successfully on both engines (`Get-TPMConsoleWindowRect`); get-only auto-properties are C# 6+, supported by both engines' compilers; verified on both from Phase 1. |
| A closure-based capability (Finding 2) is unfamiliar compared to a simple parameter, raising the chance a future contributor "simplifies" it back into a token | Documented here, in `ARCHITECTURE.md` (Phase 4), and enforced by a structural source-text test asserting the only two call sites that invoke `$factStore.Recorder`/`.Seal` are the sanctioned recording functions -- the same enforcement pattern already used elsewhere in this pipeline. |
| Re-deriving every check's raw measurements (Finding 3) instead of trusting existing Boolean checks requires touching every check category's recording call site | Phase 2 is exactly the phase this migration happens in, verified per-category against the existing adversarial matrix before Phase 3 flips authority -- not deferred or partial. |
| The Manifest/Marker hash chain (Finding 6) adds a second file and a second hash-verification pass to every publish | Two small JSON files and two SHA-256 computations over kilobyte-scale content is not performance-relevant for a run already dominated by Pester execution time; not treated as a risk requiring further mitigation. |
| Phase 2's shadow computation (Finding 7) doubles the work done per run (legacy + new, both computing eligibility) for the duration of that phase | Accepted as the explicit cost of proving equivalence before cutover -- Phase 2 is a bounded, single-round cost, not a standing overhead; it ends at Phase 3's cutover. |

---

## 19. Acceptance criteria

Implementation may not begin until this document defines all of the following concretely enough that an implementer never has to infer intent -- which, per the sections cited, it now does.

- [x] **Finding 1 -- Actual immutability**, defined via a concrete mechanism (Section 5): compiled C# value types with constructor-only, `{ get; }`-only properties (a language guarantee) for every frozen output type, and CLR string immutability for the Fact Store's sealed representation, with an explicit three-way distinction between language guarantees, implementation guarantees, and project invariants.
- [x] **Finding 2 -- Non-observable ownership proof** (Section 6): a closure-held `Recorder`/`Seal` capability returned only to the single caller of `New-TPMFactStore`, never exposed as comparable object state, with an explicit statement that possessing the store or its reader proves nothing about recording authority.
- [x] **Finding 3 -- Raw facts only** (Section 7): a revised schema for every check-fact category replacing pre-computed Booleans with raw measurements (counts, hashes, raw strings), a stated raw-vs-conclusion principle, and confirmation that evidence facts already satisfied this.
- [x] **Finding 4 -- No publish/outcome cycle** (Section 8): four objects with a strictly one-directional dependency graph, an explicit statement that the Artifact Builder consumes only the Eligibility Snapshot, and a description of Final Outcome as always-derived (at both write time and read time) rather than ever itself a stored, self-referential field.
- [x] **Finding 5 -- Failure publication** (Section 9): identical artifact/manifest requirements for every outcome, explicit confirmation that failed runs commit bundles, how NOT CERTIFIED is represented inside the committed content, and the explicit `Valid` vs. `FinalStatus` distinction consumers must not conflate.
- [x] **Finding 6 -- Manifest/marker relationship** (Section 10): decided as two artifacts, with explicit identities, promotion ordering, a three-tier hash chain, and a six-step consumer contract walking that chain.
- [x] **Finding 7 -- No dual decision authority during migration** (Section 17): every phase names one authoritative source, an optional non-decisive shadow source, explicit prohibited actions, and the rule that a shadow may observe but never decide.
- [x] **Finding 8 -- Publisher transition** (Section 17's table): the exact publisher function named for every one of the four phases, with the single cutover point (Phase 2 -> 3) stated explicitly.

Once Phase 4 (Section 17) lands, this ADR's Status changes from Proposed to Accepted.

---

## 20. Conclusion

Two rounds of architecture review of this document itself demonstrated the same lesson its subject matter already teaches: naming the right concept is not the same as specifying a mechanism that enforces it. This revision replaces every remaining conceptual description with something an implementer can build directly from the document alone -- compiled, language-enforced immutable types instead of PowerShell-class intentions (Section 5); a closure-held capability instead of a comparable token (Section 6); raw measurements instead of pre-judged Booleans (Section 7); an explicitly acyclic four-object dependency graph instead of an implied cycle (Section 8); a fully specified failure-publication path (Section 9); a named, hash-chained two-artifact manifest/marker relationship (Section 10); and a migration plan that names, per phase, exactly one authoritative decision source and exactly one publisher (Section 17).

**Recommendation, unchanged:** proceed with the four-phase migration as now fully specified. Implementation may begin once this document satisfies Section 19's acceptance criteria -- which it now does.
