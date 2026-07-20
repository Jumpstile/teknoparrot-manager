# ADR-0155: Certification Authority Redesign

Status: Proposed. Architecture only; this ADR does not implement the design.

## Context and decision

The current harness moves mutable PowerShell objects through collection,
scoring, evidence, reporting, publication, and exit selection. Validation around
those objects cannot establish one owner or prevent later mutation.

The replacement is one seven-stage pipeline:

    Collect facts/pre-final evidence -> Derive score candidate -> Issue final evidence
    -> Seal and reconstruct -> Decide eligibility -> Build/commit bundle
    -> Compose final outcome

It preserves the eleven current score categories and their policy. One private
fact authority owns collection and sealing. It issues a deeply immutable fact
reader and eligibility snapshot. One canonical eligibility JSON document feeds
all reports. A manifest plus marker commits publication. One final outcome,
composed from eligibility and publication, supplies every status and exit code.

## 1. Authority, capabilities, and provenance

### 1.1 One shared private authority

'New-TPMFactAuthorityV1' creates one dispatcher closure over one private state
object containing RunIdentity, phase, mutable builders, issued-object registry,
and sealed canonical JSON. This dispatcher is the only capability-bearing
handle. Its closed operation set is:

- RecordFact and RecordEvidence: validate and append while phase is Collecting.
- DeriveScoreCandidate: validate the complete eleven-fact builder without
  exposing it, issue an immutable non-final candidate used only to render the
  final evidence, and remain in Collecting.
- IssueFinalEvidence: accept only that candidate, append the exact required final
  record once, and advance to FinalEvidenceIssued.
- Seal: require FinalEvidenceIssued, validate both complete manifests exactly
  once, serialize them, erase all builders, set phase Sealed, register and return
  a read-only handle.
- IssueEligibility: accept only that issued reader, decide once, register the
  result, and set phase EligibilityIssued.
- ValidateIssued: verify object reference, run, type, purpose, and phase.

Every operation reads and writes the same closure-private phase. Recording after
seal, a second seal, or decision before seal is a controlled workflow-state
failure. There are no separate recorder/sealer closures and no script-scope seal
flag.

The main workflow alone retains the dispatcher. It never returns, serializes,
remotes, clones, or passes it to renderers, publishers, callbacks, tests, or
consumers. Seal returns a different type, 'TPMSealedRunReaderV1', exposing read
operations only. No wrapper may contain both capability and reader.

### 1.2 Provenance is not immutability

Immutability prevents alteration but does not prove origin. During the
single-process write workflow, an object is authoritative only when
ValidateIssued confirms ReferenceEquals with the exact object in the private
registry plus matching 128-bit random RunIdentity, compiled type, schema
version, purpose, and legal phase. Value-equal synthetic objects, copies,
deserialized objects, replays, and objects from another run fail.

Object identity is intentionally limited to this single-process boundary. No
legitimate pre-publication path crosses serialization, remoting, cloning, or a
process boundary. Post-publication consumers instead establish provenance by
validating marker, manifest, exact hashes, schemas, run correlation, and report
semantics before reconstructing new compiled objects.

### 1.3 Deep immutability

Authoritative compiled objects expose no setter or nested mutable reference.
Public fields are strings, Booleans, signed 64-bit integers, or enums. Structured
data is held as canonical JSON strings and reparsed through exact schemas. No
property returns a backing array, list, dictionary, PSCustomObject, hashtable,
stream, bitmap, or disposable object. A future collection API must return a
defensive copy of immutable compiled leaf values.

## 2. Compiled-type lifecycle

V1 types use namespace 'Jumpstile.TPM.Certification.V1'.
'Initialize-TPMCertificationTypesV1' uses one static literal C# source with no
caller-controlled interpolation. It uses Windows PowerShell 5.1-compatible C#:
explicit private readonly fields and ordinary getters; no records, init-only
setters, nullable-reference syntax, spans, or newer-language dependencies.

Initialization is idempotent:

1. Probe the complete closed set of V1 names.
2. If none exists, call Add-Type once, then verify every name and its public
   schema-version constant.
3. If all exist with exact namespace, assembly identity, and version, reuse them.
4. If a partial set or incompatible identity exists, fail; never redefine or mix.

The closed V1 compiled set is TPMScoreCandidateV1, TPMSealedRunReaderV1,
TPMFactSetV1, TPMFactV1, TPMEvidenceRecordV1,
TPMScoreItemV1, TPMEligibilitySnapshotV1, TPMPublicationOutcomeV1, and
TPMFinalOutcomeV1. The dispatcher capability itself remains a private PowerShell
closure and is not a compiled or serializable authority object.

Repeated Pester runs in one process reuse the exact types under real Windows
PowerShell 5.1 and pwsh. Breaking schemas use namespace V2; versions may coexist,
but one workflow pins one version. Tests cover first and repeated load, partial
and incompatible collisions, and both engines.

## 3. Canonical JSON and reconstruction

Canonical JSON is BOM-less UTF-8, LF, no insignificant whitespace, schema-order
properties and arrays, JSON-escaped strings, decimal integers, lowercase Boolean
literals, and null only where specified. SHA-256 is over exact canonical bytes
and represented by 64 lowercase hex characters.

The sealed-fact document and each report are limited to 16 MiB; manifest and
marker are limited to 1 MiB. Every parser enforces its limit before allocation,
then rejects invalid UTF-8, BOM,
duplicate keys, trailing tokens, excessive nesting, unknown/missing properties,
wrong JSON types, invalid ranges/enums/cardinality, and duplicate identifiers.
ConvertFrom-Json output is never authoritative. If the runtime parser cannot
detect duplicate keys or exact numeric types, a strict compatible pre-parser
must do so. Only a completely valid document is reconstructed into compiled
immutable objects.

Seal validates Section 4, serializes once, hashes, retains only the immutable
string/hash in private state, clears builders, and returns the registered reader.
The reader exposes only run ID, hash, canonical string, and validated
reconstruction. Reconstruction never exposes parser objects or builders and
never falls back to pre-seal state.

## 4. Complete raw-fact schema

The sealed document has exactly SchemaVersion (integer 1), RunIdentity (32
lowercase hex), Mode (Smoke or Unattended), Facts (exactly eleven ordered
entries), and Evidence (the exact ordered manifest in Section 4.1). Each fact
entry has exactly Identifier, Boolean Applicable, and Data. Names are
case-sensitive. Only fields explicitly called nullable accept JSON null.

1. Repository: RepositoryPath (normalized absolute non-empty string),
   RepositoryAvailable Boolean, RepositoryClean Boolean, GitStatus string.
2. Pester: Executed Boolean and integer Total, Passed, Failed, Skipped, NotRun,
   each >= 0; the four outcomes sum to Total.
3. Static Analysis: Executed Boolean, FindingCount integer >= 0, and non-empty
   Tool version string.
4. Real Install Health: ReportPath normalized absolute string or null; LoadState
   exactly Loaded, Missing, or InvalidJson; LoadError null only when Loaded,
   otherwise non-empty; and Checks. Loaded requires exactly these three ordered
   entries, each with exactly Name and Boolean Passed: 'TeknoParrotUi.exe
   exists', 'GameProfiles folder exists', and 'UserProfiles folder exists'.
   Missing/invalid requires an empty Checks array. Zero, duplicate, unknown,
   null, or non-Boolean checks fail the category.
5. Backups: Booleans UserProfilesBackupCreated and GameProfilesBackupCreated;
   nullable normalized absolute UserProfilesBackupPath and
   GameProfilesBackupPath, non-null exactly when its Boolean is true.
6. Smoke File Safety: in Smoke mode Applicable=true and Data has exactly
   UserProfiles, GameProfiles, Pcsx2x6Crosshairs; each has integers >= 0 named
   Added, Removed, Changed, BeforeSkipped, AfterSkipped. Pass requires all
   Added/Removed/Changed values zero. In Unattended mode it is
   Applicable=false and Data is exactly an empty object.
7. Artifacts: these are pre-eligibility readiness facts, not built-file facts:
   ReportDirectory is a normalized absolute path contained by the configured
   report root; Booleans ReportDirectoryReserved, StagingDirectoryReady,
   RequiredArtifactManifestConfigured, and PublisherAvailable are collected
   before eligibility. All must be true. Report bytes cannot be raw facts because
   they are produced from eligibility; actual build and commit truth belongs only
   to the publication outcome and marker. This rule breaks the legacy circular
   dependency without inventing a pre-commit PASS.
8. pcsx2x6 crosshair path (issue #79): Booleans Present,
   CanonicalFilesDeployed, LegacyRootPresent, IniFound, and
   CursorPathPointsCanonical; nullable normalized absolute Pcsx2Directory.
   Absence is explicit, never inferred from an empty path; eligibility applies
   the existing absence policy explicitly.
9. Behavioral Certification (Virtual Beta Tester): Executed Boolean; integers
   >= 0 Total, Passed, Failed, HumanBehaviors, IdempotencyChecks,
   RecoveryBehaviors, EnvironmentVariations, and HighTvdBehaviors;
   Passed + Failed = Total. Pass requires Executed, Total > 0, Failed = 0.
10. Unattended TPM root binding: normalized absolute RequestedRoot; nullable
    normalized absolute EffectiveRoot; EffectiveRootParseState exactly Parsed,
    Missing, or Invalid. Unattended is applicable and requires Parsed plus
    Windows ordinal case-insensitive equality of normalized roots. Smoke is N/A
    with null EffectiveRoot and Missing state.
11. Unattended TPM config restoration: Unattended Data contains Boolean
    PriorConfigExisted, nullable SnapshotSha256, Boolean TemporaryConfigCreated,
    RestoreAttempted, RestoreSucceeded, VerificationSucceeded, and nullable
    FailureReason. Prior config requires a valid snapshot hash and byte-exact
    restoration; absent prior config requires verified temporary-file removal.
    Pass requires restoration and verification. Smoke is N/A with Data exactly
    an empty object.

No category input may exist only as prose. Applicability is explicit, never a
passing Boolean. Diagnostic projections may retain original requested path text,
but comparisons use the normalized raw field.

### 4.1 Authoritative evidence schema and ordering

Evidence uses the same private dispatcher and issuance registry but a separate
ordered builder. Each record has exactly Identifier, Status, EvidenceType,
Required, Path, CaptureScope, FileSha256, Width, Height, and FailureReason.
Status is Captured, Skipped, or Failed. EvidenceType is ScreenCapture or
DeterministicRender only when Captured and null otherwise. Required is Boolean.
Captured requires a unique normalized literal Path contained by this run's
screenshot directory, a valid PNG, a 64-hex hash, positive dimensions, null
FailureReason, and CaptureScope of ConsoleWindow, BoundedRegion, FullDesktop, or
Deterministic. Skipped requires Required=false, null path, hash, dimensions, and
scope, and a non-empty reason. Failed requires null path, hash, dimensions, and
scope and a non-empty reason. Unknown fields and contradictory combinations fail.

Exactly these nine identifiers occur once in this order:

1. certification-suite-running -- required ScreenCapture.
2. requested-effective-root-evidence -- required ScreenCapture.
3. live-thumbnail-evidence -- optional and may be Skipped.
4. live-controls-evidence -- optional and may be Skipped.
5. adaptive-menu-normal -- required DeterministicRender.
6. adaptive-menu-small -- required DeterministicRender.
7. adaptive-menu-maximized -- required DeterministicRender.
8. smoke-file-safety-evidence -- required DeterministicRender; in unattended
   mode its content explicitly renders Smoke File Safety as N/A and does not
   claim smoke diffing.
9. final-certification-result -- required ScreenCapture and last.

The final evidence image renders the authority-issued, non-final score candidate as
ELIGIBLE or NOT ELIGIBLE PENDING EVIDENCE AND PUBLICATION; it never claims
CERTIFIED. Issuing it moves the shared authority to FinalEvidenceIssued. Seal
then freezes facts and evidence together; no recording of either kind is legal
afterward. Only then does IssueEligibility evaluate required evidence and issue
the final eligibility snapshot. This removes a cycle: final outcome is never an input to
its own evidence. Zero, duplicate, substituted, copied, cross-run, reordered, or
post-final records invalidate evidence eligibility. One PNG path cannot satisfy
two records.

## 5. Eligibility authority

The dependency graph is acyclic:

    sealed facts -> exactly eleven score items -> score eligibility
    sealed facts -> required evidence eligibility
    score eligibility + evidence eligibility -> EligibleForCertification

Publication and final outcome are not eligibility inputs. The issued scalar-only
TPMEligibilitySnapshotV1 has exactly: SchemaVersion 1, RunIdentity,
FactSetSha256, canonical ScoreItemsJson, ApplicableCount, PassedCount,
Percentage, Boolean ScoreEligible, Boolean EvidenceEligible, Boolean
EligibleForCertification, and canonical FailureReasonsJson.

ScoreItemsJson contains exactly the eleven Section 4 identifiers in order. Each
has exactly Identifier, Status, Passed, Details. Status is Pass, Fail, or
NotApplicable; Passed is Boolean for Pass/Fail and null only for N/A. N/A is
allowed only for the mode-dependent categories identified above and is excluded
from numerator and denominator. Missing, extra, duplicate, substituted,
reordered, truthy non-Boolean, or contradictory entries invalidate eligibility.

'TPM-Certification-Scorecard.json' is the one canonical machine-readable
eligibility representation: the exact serialization of the issued snapshot,
not a recalculation. Every other report is a deterministic projection of those
bytes plus sealed facts. Renderers never calculate status.

## 6. Publication authority

### 6.1 Exact report manifest

Exactly four reports exist in this order:

1. EligibilityJson -> TPM-Certification-Scorecard.json -> application/json
2. ValidationJson -> TPM-Validation-Report.json -> application/json
3. EligibilityMarkdown -> TPM-Certification-Scorecard.md -> text/markdown
4. ValidationMarkdown -> TPM-Validation-Report.md -> text/markdown

ValidationJson is an exact envelope containing SchemaVersion, RunIdentity,
FactSetSha256, EligibilityDocumentSha256, and SealedFactsJson; the last field is
the exact canonical fact string from Section 3. Each other report embeds exact
RunIdentity, FactSetSha256, and EligibilityDocumentSha256. Markdown begins with
a fixed machine-readable metadata block. Any repeated
score, status, count, or reason must semantically equal canonical eligibility.
Consumers verify all projections before outcome reconstruction.

The exact manifest filename is 'TPM-Certification-Manifest.json'. Its fields, in
order, are SchemaVersion integer 1; RunIdentity; EligibilityDocumentIdentifier
exactly EligibilityJson; EligibilityDocumentSha256; ArtifactCount integer 4; and
Artifacts, exactly four entries in the above order. Each entry has exactly
Identifier, FileName, ContentType, ByteLength integer > 0, Sha256, and
EligibilityDocumentSha256.

Unknown fields, extra, missing, or reordered entries, duplicate identifiers,
filenames or destinations, path components, case variants, or mismatched hashes
and run IDs fail.

### 6.2 Exact commit marker

The exact filename 'TPM-Certification-Commit.json' is not a manifest artifact and
is written last. Its ordered fields are SchemaVersion integer 1; RunIdentity;
ManifestFileName exactly TPM-Certification-Manifest.json; ManifestByteLength
integer > 0; ManifestSha256; and ArtifactCount integer 4. Unknown or missing
fields, stale or foreign run ID, or any length, hash, or count mismatch fail.

### 6.3 Publication and consumer validation

All six names are reserved inside a newly created random run directory contained
by the report root. Existing destinations fail and are never overwritten. A
private sibling staging directory receives closed, flushed, validated files.
Promotion order is four reports, manifest, marker.

Failure before marker means no committed bundle. Best-effort rollback removes
only this run's files and records cleanup errors; cleanup never converts failure
to success. Failure after marker triggers durable revalidation: a fully valid
bundle remains committed, otherwise the run is NOT CERTIFIED and the marker is
not authority. Consumers ignore any directory without a fully valid marker.

Reports state eligibility only and use the phrase ELIGIBLE or NOT ELIGIBLE; they
never claim publication is committed. The commit marker is the sole on-disk proof
of the final CERTIFIED outcome. A consumer derives final status from validated
eligibility plus validated commit and cannot observe PASS alongside NOT CERTIFIED.

Validation order is mandatory: contain run directory and marker; strict-parse
marker; verify manifest bytes and hash; strict-parse manifest; verify run, count,
order, uniqueness, and names; literal-path resolve and hash all reports; parse
canonical eligibility; verify every report's semantic projection; reconstruct
compiled snapshot and publication; compose outcome. No later success skips an
earlier step.

## 7. Final outcome and failure publication

Issued TPMPublicationOutcomeV1 records run, Committed, manifest and marker
hashes, and canonical failure reasons. New-TPMFinalOutcomeV1 accepts only the
issued eligibility and publication objects for one run. CERTIFIED and exit 0
require both EligibleForCertification and Committed; every other combination is
NOT CERTIFIED and exit 1.

Console, JSON, Markdown, process result, and exit code are projections of this
one compiled outcome. A passing numeric score cannot override evidence or
publication failure. A NOT CERTIFIED eligibility result is still committed as
audit evidence when publication succeeds. Publication failure yields no
authoritative bundle, NOT CERTIFIED, and exit 1.

## 8. Migration

| Phase | Authority | Rule | Publisher |
|---|---|---|---|
| 1 | Legacy | V1 types and isolated tests only; no live new facts. | Legacy |
| 2 | Legacy | Shadow authority observes the same calls; it cannot affect output, publication, or exit. | Legacy only |
| 3 | New | Atomic cutover deletes legacy decisions and arbitrary build callback. | New only |
| 4 | New | Add consumer validation and remove migration diagnostics. | New only |

In Phase 2, disagreement produces a structured divergence with run ID,
category and field, legacy value, new value, and comparison rule. It invalidates
that run's migration evidence and blocks Phase 3, while preserving the legacy
decision, reports, publication, console, and exit for the run. It is never
silently coerced. Cutover requires zero unresolved divergences across the full
adversarial matrix and agreed real-run sample.

The Phase 3 commit changes fact, decision, and publisher authority together and
removes every legacy recalculation. Rollback reverts the whole cutover; mixed
authority or two publishers is prohibited.

## 9. Alternatives and risks

Continuing incremental validation is rejected because it retains mutable
sources of truth. Serializing every stage is rejected because serialization
does not prove provenance. Embedding all reports in the marker is rejected;
the two-artifact hash chain binds them without a large marker. Publishing only
success is rejected because committed failure evidence is operationally needed.

Controls are versioned idempotent types for process persistence, private
capability ownership, scalar-only public objects for deep immutability, issuance
registry for write provenance, exact parser reconstruction for read provenance,
marker-last publication for partial output, and legacy-only authority in Phase 2.

## 10. Acceptance criteria and consistency audit

Tests must prove one authority rejects recording after seal; reader has no
capability; no mutable nested reference is exposed; synthetic, copied, replayed,
cross-run, and deserialized write objects fail provenance; all eleven schemas
reject missing, extra, duplicate, null, and wrong-type data; seal and reconstruct
preserve bytes; N/A arithmetic is exact; all reports match canonical eligibility;
manifest and marker names, schemas, count, order, hash, containment, and run
correlation are exact; partial, stale, or foreign publication fails; CERTIFIED,
PASS, exit 0, valid evidence, and committed publication are inseparable; Phase 2
divergence blocks cutover but not legacy output; types initialize repeatedly on
PS 5.1 and pwsh; and rollback cannot leave mixed publishers.

Final audit: there is one recording and sealing capability, one immutable sealed
boundary, one write-time issuance registry, one canonical eligibility document,
one exact publication protocol, and one final outcome. Immutability and
provenance are separate. Failure and success bundles use the same publisher.
Migration never has two authoritative publishers. Type and schema identity are
versioned together. No example or phase creates a second source of truth.