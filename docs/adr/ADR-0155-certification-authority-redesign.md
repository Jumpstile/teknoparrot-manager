# ADR-0155: Certification Authority Redesign

Status: Proposed. Architecture only; no implementation is included.

## 1. Decision

Certification is one closed pipeline:

    Collect facts and evidence
      -> derive non-authoritative score preview
      -> issue final evidence
      -> seal and reconstruct
      -> issue eligibility
      -> stage and commit publication
      -> issue final outcome

One private workflow authority owns mutable collection and sealing. Compiled,
deeply immutable objects cross authority boundaries. A detached eligibility
payload eliminates recursive hashing. Five reports, one manifest, and one commit
marker form the publication bundle. The marker proves publication only. One
final outcome, derived from validated eligibility and validated publication,
supplies every externally visible status and exit code.

## 2. Authority and lifecycle

### 2.1 Workflow authority

'New-TPMWorkflowAuthorityV1' creates one dispatcher closure over one private
state object. It is the only recording, sealing, and write-time provenance
capability. The main workflow is its only holder. It is never returned, placed
on another object, serialized, remoted, cloned, or passed to a callback,
renderer, publisher, consumer, or test fixture.

The dispatcher implements this closed phase machine:

| Current phase | Operation | Resulting phase |
|---|---|---|
| Collecting | RecordFact or RecordEvidence | Collecting |
| Collecting | DeriveScorePreview | Collecting |
| Collecting | IssueFinalEvidence using the issued preview | FinalEvidenceIssued |
| FinalEvidenceIssued | Seal | Sealed |
| Sealed | IssueEligibility using the issued sealed reader | EligibilityIssued |
| EligibilityIssued | IssuePublicationCandidate | PublicationCandidateIssued |
| PublicationCandidateIssued | RegisterCommittedPublication | PublicationIssued |
| EligibilityIssued or PublicationCandidateIssued | RegisterPublicationFailure | PublicationIssued |
| PublicationIssued | IssueFinalOutcome | FinalOutcomeIssued |

Any operation outside its listed phase fails closed. Seal validates the complete
fact and evidence manifests, writes canonical immutable strings into private
state, destroys every mutable builder, and permanently rejects all recording.
It returns only 'TPMSealedRunReaderV1', which has no capability operation.

### 2.2 Issuance provenance

The closure holds a private registry keyed by purpose. Write-time objects are
authoritative only when the dispatcher verifies all of:

- ReferenceEquals with the exact registered object;
- matching random 128-bit RunIdentity;
- exact compiled type, namespace, and schema version;
- exact purpose and legal phase; and
- no prior consumption where the object is single-use.

Copies, caller-constructed values, deserialized values, replays, and cross-run
objects fail even when value-equal. The publisher receives immutable candidate
bytes but not the dispatcher. It returns raw publication observations to the
workflow; only the dispatcher may issue 'TPMPublicationOutcomeV1'. Likewise only
the dispatcher may combine its issued eligibility and publication objects into
'TPMFinalOutcomeV1'. Thus anti-synthetic provenance covers facts, evidence,
eligibility, publication, and final outcome.

Post-publication consumers cannot use process identity. They establish
provenance by the validation contract in Section 9 and then reconstruct compiled
objects from exact canonical schemas.

### 2.3 Deep immutability and compiled-type lifecycle

Authoritative compiled types expose only strings, Booleans, signed 64-bit
integers, and enums. They expose no setter, mutable collection, parser object,
hashtable, PSCustomObject, stream, bitmap, or other mutable/disposable reference.
Structured values are canonical JSON strings. A future collection property must
return a defensive copy of immutable compiled leaves.

V1 uses namespace 'Jumpstile.TPM.Certification.V1'. Its closed compiled set is
TPMScorePreviewV1, TPMSealedRunReaderV1, TPMFactSetV1, TPMFactV1,
TPMEvidenceRecordV1, TPMScoreItemV1, TPMEligibilitySnapshotV1,
TPMPublicationCandidateV1, TPMPublicationOutcomeV1, and TPMFinalOutcomeV1.

'Initialize-TPMCertificationTypesV1' uses one static literal, non-interpolated C#
source compatible with Windows PowerShell 5.1: explicit private readonly fields
and ordinary getters; no records, init-only setters, nullable-reference syntax,
spans, or newer language dependencies. If no V1 type exists, Add-Type runs once.
If all exist with exact assembly identity and version, they are reused. A partial
or incompatible set fails. Breaking changes use namespace V2. Tests cover first
load, repeated same-process load, partial collision, version collision, Windows
PowerShell 5.1, and pwsh.

## 3. Canonical encoding and exact validation

All authoritative JSON uses RFC 8785 JSON Canonicalization Scheme (JCS), with
I-JSON input constraints, as the sole canonical representation. The JCS output
bytes are encoded directly as UTF-8 without BOM. JCS therefore governs every
byte-level choice: object properties are sorted lexicographically by UTF-16 code
units; array order is preserved; insignificant whitespace is absent; null is the
four bytes null; true and false are lowercase; numbers use the ECMAScript
shortest round-trippable finite-number form; NaN, Infinity, and negative zero are rejected. Every authoritative integer is
restricted to the I-JSON interoperable range -9007199254740991 through
9007199254740991 even when its compiled storage type is signed 64-bit.

Strings must contain Unicode scalar values only; unpaired UTF-16 surrogates are
rejected. Quotation mark, reverse solidus, and U+0000 through U+001F use the JCS
JSON escapes. The short escapes \b, \t, \n, \f, and \r are used where defined;
other control characters use lowercase four-digit \u hexadecimal. Solidus is
never escaped. All other characters, including non-ASCII characters, are emitted
as their direct UTF-8 encoding. These rules and RFC 8785 are normative; the same
logical typed object must produce identical bytes in every implementation.

Schema tables in this ADR define required membership and array order, not an
alternative object-property order. JCS property sorting is the serialized object
order. Object schemas are closed: unknown, missing, or duplicate properties
fail before canonicalization. Arrays reject missing, extra, duplicate,
substituted, or reordered identifiers. Enums are ordinal case-sensitive.

Fact, evidence, eligibility, publication, and final-outcome documents are
limited to 16 MiB each. Manifest and marker are limited to 1 MiB. Limits apply
before allocation. Parsers reject invalid UTF-8, BOM, duplicate keys, trailing
tokens, excessive nesting, wrong types, out-of-range values, and inconsistent
cardinality. ConvertFrom-Json output is never authoritative; a strict parser
must preserve duplicate-key and exact-number detection before reconstruction.

## 4. Sealed run schema and hash authorities

The sealed run object has exactly, in order:

1. SchemaVersion: integer 1.
2. RunIdentity: 32 lowercase hexadecimal characters.
3. Mode: Smoke or Unattended.
4. Facts: the eleven ordered Section 5 records.
5. Evidence: the nine ordered Section 6 records.

It contains no integrity fields. Seal serializes it once and retains its exact
bytes privately.

| Hash | Exact input bytes | Includes evidence | Includes integrity metadata | Producer | Consumer |
|---|---|---:|---:|---|---|
| FactSetSha256 | Canonical JSON array value of Facts, including '[' through ']' | No | No | Seal | eligibility and bundle validators |
| EvidenceSetSha256 | Canonical JSON array value of Evidence | Yes, only evidence | No | Seal | eligibility and bundle validators |
| SealedRunSha256 | Canonical complete sealed run object | Yes | No | Seal | eligibility and bundle validators |
| EligibilityPayloadSha256 | Canonical EligibilityPayload object in Section 7.2 | Indirectly through EvidenceSetSha256 and SealedRunSha256 | No | eligibility issuer | all report and bundle validators |
| ArtifactSha256 | Exact closed bytes of one staged report | As that report defines | All fields present in that report | publisher | manifest and consumer |
| ArtifactSetSha256 | Canonical JSON array of the five manifest artifact entries, excluding the manifest | Indirectly | Entry hashes included | publisher | marker and consumer |
| ManifestSha256 | Exact closed bytes of TPM-Certification-Manifest.json | Indirectly | Manifest fields included | publisher | marker and consumer |

All hashes use SHA-256 and 64 lowercase hexadecimal output. No object contains
its own byte hash. In particular, TPM-Certification-Eligibility.json contains
EligibilityPayload plus Integrity, while EligibilityPayloadSha256 covers only
the detached EligibilityPayload bytes and excludes the entire Integrity object.

## 5. Eleven certification categories

Each fact record has exactly Identifier, Applicable (Boolean), and Data. Each
score item has exactly Identifier, Status, Passed, Details, and FailureReasons.
Status is Pass, Fail, or NotApplicable. Passed is Boolean for Pass/Fail and null
only for N/A. Details is the category's exact Data object, not prose.
FailureReasons is an ordered array of objects with exactly Code and Message.
Code must be one of the category codes below; Message is a non-empty diagnostic
projection and is never used for decisions. Pass and N/A require an empty
FailureReasons array; Fail requires one or more applicable codes. An applicable
item contributes one
point; N/A contributes neither numerator nor denominator.

### 5.1 Repository

Data: RepositoryPath normalized per Section 10; RepositoryAvailable Boolean;
RepositoryClean Boolean; GitStatus string.

Pass: available and clean. Fail otherwise. Never N/A. Failure codes:
REPOSITORY_UNAVAILABLE and REPOSITORY_DIRTY.

### 5.2 Pester

Data: Executed Boolean; Total, Passed, Failed, Skipped, NotRun integers >= 0;
Engine non-empty string and SuiteSha256 64-hex when Executed=true, otherwise
both null. Counts must satisfy
Passed + Failed + Skipped + NotRun = Total.

Pass: Executed, Total > 0, Failed = 0, NotRun = 0, and consistent counts.
Fail otherwise. Never N/A. Codes: PESTER_NOT_EXECUTED, PESTER_EMPTY,
PESTER_FAILURES, PESTER_NOT_RUN, PESTER_COUNTS_INVALID.

### 5.3 Static Analysis

Data contains exactly:
- Parser: two ordered entries WindowsPowerShell51 and Pwsh, each with Executed
  Boolean, ErrorCount integer >= 0, and ToolVersion non-empty when Executed or
  null otherwise.
- Encoding: Executed Boolean and NonAsciiByteCount integer >= 0 for every
  production PowerShell file listed in Files; Files is an ordered, non-empty
  array of normalized repository-relative strings.
- PSScriptAnalyzer: Executed Boolean, FindingCount integer >= 0, ToolVersion
  non-empty when executed or null otherwise.
- InjectionHunter: Executed Boolean, FindingCount integer >= 0,
  UnresolvedFindingCount integer >= 0, ToolVersion non-empty when executed or
  null otherwise, and Dispositions. Dispositions is an ordered array with
  exactly FindingIdentifier and Disposition for each finding; Disposition is
  Confirmed, Mitigated, or FalsePositive. Its count equals FindingCount, and
  UnresolvedFindingCount is the count without Mitigated or FalsePositive.

Pass: both parser engines executed with zero errors; encoding executed with zero
non-ASCII bytes; both analyzers executed; PSScriptAnalyzer FindingCount = 0; and
InjectionHunter UnresolvedFindingCount = 0. Recorded InjectionHunter findings
may remain only when each has a disposition in validation projections. Fail
otherwise. Never N/A. Codes: PARSER_NOT_EXECUTED, PARSER_ERRORS,
ENCODING_NOT_EXECUTED, ENCODING_NON_ASCII, ANALYZER_NOT_EXECUTED,
PSSCRIPTANALYZER_FINDINGS, INJECTION_FINDING_UNRESOLVED.

### 5.4 Real Install Health

Data: ReportPath normalized or null; LoadState Loaded, Missing, or InvalidJson;
LoadError null only when Loaded; Checks. Loaded requires exactly these ordered
Name/Passed Boolean records: TeknoParrotUi.exe exists, GameProfiles folder
exists, UserProfiles folder exists. Other states require empty Checks and
non-empty LoadError.

Pass: Loaded and every required check appears exactly once with Passed=true.
Fail otherwise. Never N/A. Codes: HEALTH_REPORT_MISSING,
HEALTH_REPORT_INVALID, HEALTH_CHECK_MISSING, HEALTH_CHECK_DUPLICATE,
HEALTH_CHECK_NON_BOOLEAN, HEALTH_CHECK_FAILED.

### 5.5 Backups

Data: UserProfilesBackupCreated and GameProfilesBackupCreated Booleans; matching
nullable normalized paths; BackupVerificationExecuted Boolean; each created
backup has Verified Boolean and Sha256. A path/hash is non-null exactly when its
backup was created.

Pass: verification executed and at least one required backup was created and
verified; every created backup verifies. Fail otherwise. Never N/A. Codes:
BACKUP_NONE_CREATED, BACKUP_VERIFICATION_NOT_EXECUTED,
BACKUP_VERIFICATION_FAILED, BACKUP_METADATA_INVALID.

### 5.6 Smoke File Safety

Smoke Data: exactly UserProfiles, GameProfiles, Pcsx2x6Crosshairs, each with
Added, Removed, Changed, BeforeSkipped, AfterSkipped integers >= 0.
Pass when every Added, Removed, Changed, BeforeSkipped, and AfterSkipped is zero.
Fail otherwise. Unattended: N/A with Data exactly empty. Codes:
SMOKE_TREE_CHANGED and SMOKE_TREE_UNREADABLE.

### 5.7 Artifacts and package validation

Data: ReportDirectory normalized and contained; ReportDirectoryReserved,
StagingDirectoryReady, RequiredArtifactManifestConfigured, PublisherAvailable,
PackageValidationExecuted, and PackageValidationPassed Booleans;
PackageValidationErrorCount integer >= 0; PackageValidationDiagnostics an
ordered array of zero or more records with exactly Stage, FailureCode,
FailureMessage, and ExceptionType. FailureCode and FailureMessage preserve the
publisher/preflight failure returned by the real publication pipeline.

Package Validation means validation of the certification bundle contract in
Sections 8-10, not creation or validation of a release ZIP. It is a preflight of
the exact schemas, canonical filenames, destination reservation, and publisher
availability; committed publication is evaluated later and cannot be a score
input.

Pass: all six Booleans true and error count zero. Fail otherwise. Never N/A.
Codes: REPORT_DIRECTORY_UNAVAILABLE, STAGING_UNAVAILABLE,
ARTIFACT_MANIFEST_UNCONFIGURED, PUBLISHER_UNAVAILABLE,
PACKAGE_VALIDATION_NOT_EXECUTED, PACKAGE_VALIDATION_FAILED.
When either broad publisher code is emitted, the authority Details and reason
message retain the structured PackageValidationDiagnostics rather than
reducing the failure to a Boolean and count.

### 5.8 pcsx2x6 crosshair path (issue #79)

Data: Present, CanonicalFilesDeployed, LegacyRootPresent, IniFound, and
CursorPathPointsCanonical Booleans; Pcsx2Directory normalized or null.

When Present=false: N/A, directory null, all other Booleans false. When present:
Pass only when CanonicalFilesDeployed, IniFound, and CursorPathPointsCanonical
are true and LegacyRootPresent is false. Fail otherwise. Codes:
PCSX2_FILES_MISSING, PCSX2_INI_MISSING, PCSX2_PATH_NONCANONICAL,
PCSX2_LEGACY_ROOT_PRESENT.

### 5.9 Behavioral Certification (Virtual Beta Tester)

Data: Executed Boolean; Total, Passed, Failed, HumanBehaviors,
IdempotencyChecks, RecoveryBehaviors, EnvironmentVariations, HighTvdBehaviors
integers >= 0; Passed + Failed = Total.

Pass: Executed, Total > 0, Failed = 0, and valid counts. Fail otherwise. Never
N/A. Codes: VBT_NOT_EXECUTED, VBT_EMPTY, VBT_FAILURES, VBT_COUNTS_INVALID.

### 5.10 Unattended TPM root binding

Data: RequestedRoot normalized; EffectiveRoot normalized or null;
EffectiveRootParseState Parsed, Missing, or Invalid.

Unattended: Pass only when Parsed and requested/effective roots are component-
equal under Section 10. Fail otherwise. Smoke: N/A with EffectiveRoot null and
state Missing. Codes: EFFECTIVE_ROOT_MISSING, EFFECTIVE_ROOT_INVALID,
EFFECTIVE_ROOT_MISMATCH.

### 5.11 Unattended TPM config restoration

Unattended Data: PriorConfigExisted, TemporaryConfigCreated, RestoreAttempted,
RestoreSucceeded, VerificationSucceeded Booleans; SnapshotSha256 nullable;
FailureReason nullable. Prior config requires snapshot hash and byte-exact
restoration. No prior config requires verified temporary-file removal.

Pass: RestoreAttempted, RestoreSucceeded, and VerificationSucceeded, with the
appropriate prior/no-prior invariant. Fail otherwise. Smoke: N/A with Data
exactly empty. Codes: RESTORE_NOT_ATTEMPTED, RESTORE_FAILED,
RESTORE_VERIFICATION_FAILED, RESTORE_SNAPSHOT_INVALID,
TEMP_CONFIG_NOT_REMOVED.

## 6. Evidence authority

Each evidence record has exactly Identifier, Status, EvidenceType, Required,
Path, CaptureScope, FileSha256, Width, Height, FailureCode, FailureMessage.
Captured requires EvidenceType ScreenCapture or DeterministicRender, unique
contained normalized path, validated PNG, 64-hex hash, positive dimensions,
null FailureCode/FailureMessage, and scope ConsoleWindow, BoundedRegion,
FullDesktop, or Deterministic. Skipped requires Required=false, all capture
fields null, FailureCode EVIDENCE_SKIPPED, and a non-empty FailureMessage.
Failed requires all capture fields null and one non-empty authoritative code and
explanatory message.

The complete evidence-code inventory, evaluated in this fixed first-failure
order, is: EVIDENCE_IDENTIFIER_INVALID, EVIDENCE_DUPLICATE,
EVIDENCE_ORDER_INVALID, EVIDENCE_POST_FINAL, EVIDENCE_METADATA_INVALID,
EVIDENCE_TYPE_INVALID, EVIDENCE_REQUIRED_SKIPPED,
EVIDENCE_CAPTURE_ACTION_MISSING, EVIDENCE_CAPTURE_EXCEPTION,
EVIDENCE_PATH_INVALID, EVIDENCE_PATH_OUTSIDE_ROOT, EVIDENCE_PATH_DUPLICATE,
EVIDENCE_FILE_MISSING, EVIDENCE_FILE_EMPTY, EVIDENCE_PNG_INVALID,
EVIDENCE_DIMENSIONS_INVALID, EVIDENCE_FILE_LOCKED, EVIDENCE_HASH_FAILED, and
EVIDENCE_SKIPPED. Manifest-level failures use SourceIdentifier
evidence-manifest; record failures use that record's Identifier, or
unidentified-evidence when the identifier itself is invalid. Eligibility maps
each non-Captured required record and each Failed optional record to exactly
SourceIdentifier, FailureCode as Code, and FailureMessage as Message. Codes and
source identifiers are authoritative. Messages are explanatory only.

Exactly once and in order:
certification-suite-running (required ScreenCapture);
requested-effective-root-evidence (required ScreenCapture);
live-thumbnail-evidence (optional);
live-controls-evidence (optional);
adaptive-menu-normal, adaptive-menu-small, adaptive-menu-maximized (each
required DeterministicRender); smoke-file-safety-evidence (required
DeterministicRender); final-certification-result (required ScreenCapture, last).

Every required record must be Captured. Optional records may be Captured or
Skipped but not Failed. The unattended smoke-file image must render N/A without
claiming diffing. Final evidence renders the issued score preview as ELIGIBLE or
NOT ELIGIBLE PENDING EVIDENCE AND PUBLICATION, never CERTIFIED. It moves the
authority to FinalEvidenceIssued; Seal then prevents all later recording.
Duplicate paths, copied objects, reordered records, or post-final records fail.

## 7. Eligibility schema and derivation

### 7.1 Score arithmetic

ApplicableCount is the number of non-N/A items. PassedCount is the count with
Status Pass. ApplicableCount must be greater than zero. PercentageBasisPoints is
PassedCount * 10000 / ApplicableCount, rounded to the nearest signed integer with
midpoints away from zero. ThresholdBasisPoints is exactly 10000. ScoreEligible
is true only when every applicable item passes and PercentageBasisPoints=10000.
User-facing percentage text is derived as the integer quotient and two-digit
remainder of PercentageBasisPoints divided by 100; it is never parsed back into
authority. EvidenceEligible follows Section 6. EligibleForCertification =
ScoreEligible AND EvidenceEligible.

### 7.2 Detached eligibility payload

'TPM-Certification-Eligibility.json' has exactly Payload then Integrity.

Payload has exactly, in order: SchemaVersion=1, RunIdentity, Mode,
FactSetSha256, EvidenceSetSha256, SealedRunSha256, ScoreItems (eleven ordered
Section 5 items), ApplicableCount, PassedCount, PercentageBasisPoints integer,
ThresholdBasisPoints integer 10000, ScoreEligible, EvidenceEligible,
EligibleForCertification, FailureReasons.

FailureReasons is the stable ordered union of score-item reasons followed by
evidence reasons. Each has exactly SourceIdentifier, Code, Message. Ordering is
manifest order, then local reason order. SourceIdentifier and Code determine
semantic equivalence. Message is explanatory, is not authoritative, and is
excluded from semantic-equivalence comparisons.

Integrity has exactly Algorithm='SHA-256' and EligibilityPayloadSha256. The hash
covers the canonical Payload object bytes only, starting with its opening brace
and ending with its closing brace. It excludes the outer document, the Integrity
property name/value, and all separators surrounding Integrity. This detached
envelope has no recursive dependency.

Unknown fields fail. The workflow authority produces and consumes the snapshot;
report builder consumes its exact payload bytes; publisher and external consumer
validate the payload hash before use.

## 8. Seven canonical publication artifacts

The publication directory contains exactly these seven canonical files. Five are
manifest-listed reports; manifest and marker are control artifacts.

### 8.1 Eligibility JSON

'TPM-Certification-Eligibility.json' is exactly Section 7.2.

### 8.2 Publication JSON candidate

'TPM-Certification-Publication.json' has exactly SchemaVersion=1, RunIdentity,
EligibilityPayloadSha256, IntendedState='Committed', RequiredArtifactCount=5,
ManifestFileName='TPM-Certification-Manifest.json', and
CommitMarkerFileName='TPM-Certification-Commit.json'.

It is a conditional candidate, not proof of publication. It becomes an
authoritative reconstructed publication outcome only after marker validation.

### 8.3 Final outcome JSON candidate

'TPM-Certification-Final-Outcome.json' has exactly SchemaVersion=1, RunIdentity,
EligibilityPayloadSha256, EligibilityStatus ('Eligible' or 'NotEligible'),
RequiredPublicationState='Committed', FinalStatus ('CERTIFIED' only when
eligibility is Eligible, otherwise 'NOT CERTIFIED'), and ExitCode (0 only for
CERTIFIED, otherwise 1).

It is also conditional. Without a valid marker it is not an outcome and must be
ignored. This lets the marker commit the exact final projection without making
publication depend on an already-authoritative final outcome.

### 8.4 Normative Markdown scalar encoding and scorecard

Markdown is BOM-less UTF-8 with LF. Fixed headings and keys below are literal.
No caller-controlled value is interpolated into a heading, list marker, emphasis
construct, pipe-delimited table, inline-code span, or fenced block. Arbitrary
structured values use JCS bytes encoded as RFC 4648 Section 5 base64url without
padding on one ASCII line.

Failure-Message-Base64Url uses one exact transport. The producer must serialize
the complete message as exactly one RFC 8785 JCS-compliant JSON string, encode
that complete serialized string as UTF-8, base64url-encode the entire UTF-8 byte
sequence under RFC 4648 Section 5, and remove every trailing equals-sign padding
character. No subset of bytes, including only non-ASCII bytes, is encoded.

The consumer must first reject characters outside the unpadded RFC 4648
base64url alphabet and reject a length whose remainder modulo four is one. If
its decoder requires padding, it restores the unique required internal padding,
then base64url-decodes the entire field. It decodes the resulting bytes as
strict UTF-8, rejecting malformed byte sequences, and parses the decoded text as
exactly one JSON value with no trailing data. That value must be a string. The
consumer then RFC 8785 JCS-serializes the parsed string and requires byte-for-byte
equality with the decoded UTF-8 bytes; otherwise the field is non-canonical and
fails. Malformed base64url, invalid UTF-8, non-string JSON, trailing data, and
non-canonical serialization all invalidate the report.

This same producer and consumer contract governs every
Failure-Message-Base64Url field in Scorecard Markdown and Validation Markdown.
Thus newlines, pipes, backticks, fences, headings, emphasis markers, list
markers, and embedded delimiters can never alter Markdown structure.

'TPM-Certification-Scorecard.md' begins with exactly these single-line keys:

    Schema-Version: 1
    Run-Identity: <RunIdentity>
    Eligibility-Payload-SHA256: <hash>
    Fact-Set-SHA256: <hash>
    Evidence-Set-SHA256: <hash>

Then one blank line, '# Certification Eligibility Scorecard',
'Eligibility: ELIGIBLE|NOT ELIGIBLE', and
'Score: <PassedCount>/<ApplicableCount> (<derived percentage with two digits>%)'.
It then has eleven fixed '## <Identifier>' headings in manifest order. Each has
'Status: PASS|FAIL|N/A', 'Details-JCS-Base64Url: <value>', then one
'Failure-Code: <Code>' and 'Failure-Message-Base64Url: <value>' pair per reason.
No reasons is represented only by 'Failure-Code: none'.

### 8.5 Validation Markdown

'TPM-Certification-Validation.md' has the same five metadata lines, one blank
line, '# Certification Validation', then fixed sections '## Facts',
'## Evidence', '## Eligibility', and '## Failure Reasons'. Facts contains
'Facts-JCS-Base64Url: <value>'; Evidence contains
'Evidence-JCS-Base64Url: <value>'; Eligibility contains
'Eligibility-Payload-JCS-Base64Url: <value>'. Failure Reasons uses the same
code/message pair grammar as the scorecard. Base64url decoding must yield the
exact JCS bytes whose hashes and schemas are validated. No Markdown field
recalculates authority.

### 8.6 Manifest

'TPM-Certification-Manifest.json' has exactly SchemaVersion=1, RunIdentity,
EligibilityPayloadSha256, ArtifactCount=5, ArtifactSetSha256, Artifacts.

Artifacts has exactly these entries in order:
EligibilityJson -> TPM-Certification-Eligibility.json -> application/json;
PublicationJson -> TPM-Certification-Publication.json -> application/json;
FinalOutcomeJson -> TPM-Certification-Final-Outcome.json -> application/json;
ScorecardMarkdown -> TPM-Certification-Scorecard.md -> text/markdown;
ValidationMarkdown -> TPM-Certification-Validation.md -> text/markdown.

Each entry has exactly Identifier, FileName, ContentType, ByteLength integer > 0,
Sha256, EligibilityPayloadSha256. ArtifactSetSha256 hashes the exact canonical
Artifacts array. Duplicate identities, filenames, destinations, hashes, path
components, case variants, missing/extra/reordered entries, or unknown fields
fail.

### 8.7 Commit marker

'TPM-Certification-Commit.json' has exactly SchemaVersion=1, RunIdentity,
ManifestFileName='TPM-Certification-Manifest.json', ManifestByteLength integer
> 0, ManifestSha256, ArtifactSetSha256, ArtifactCount=5, and
EligibilityPayloadSha256. Unknown fields fail.

The marker proves only complete authoritative publication of the exact bundle.
It does not prove CERTIFIED. Certification additionally requires validated
eligibility, validated publication, validated provenance, exact reconstruction,
and final-outcome composition. Marker presence alone is never sufficient.

## 9. Publication, reconstruction, and equivalence

A private staging directory receives closed and flushed files. Promotion order
is the five reports, manifest, marker. Existing destinations fail; nothing is
overwritten. Before durable marker validation, state is Uncommitted. Staging,
promotion, marker-write, or durable-validation failure leaves Committed=false.
Pre-commit rollback removes only files owned by this run; rollback failure adds
ROLLBACK_FAILED beside the original publication failure but cannot create
authority.

Successful durable validation performs the sole monotonic transition from
Uncommitted to Committed. Once Committed=true it can never return to false.
Post-commit staging-directory cleanup runs afterward. Its failure records the
non-authoritative diagnostic warning POST_COMMIT_CLEANUP_FAILED but does not
change Committed, eligibility, final status, or exit code. An invalid marker is
never authority.

Consumer validation order is fixed and has no forward reference:

1. Apply Section 10 containment to the run directory and marker.
2. Strict-parse the marker and validate only its self-contained schema.
3. Resolve the manifest from the validated marker; validate its byte length and
   ManifestSha256.
4. Strict-parse the manifest; validate run correlation, count, order,
   identifiers, filenames, ArtifactSetSha256, and marker correlations.
5. Resolve all five reports from the validated manifest by literal contained
   paths; validate each byte length and ArtifactSha256.
6. Strict-parse EligibilityJson; validate its detached payload hash and obtain
   the expected fact, evidence, and sealed-run hashes.
7. Parse ValidationMarkdown's fixed grammar and base64url values. Strict-parse
   the decoded Facts and Evidence arrays, reconstruct the canonical sealed-run
   object using the already validated schema version, run identity, and mode,
   then validate FactSetSha256, EvidenceSetSha256, and SealedRunSha256.
8. Parse ScorecardMarkdown and compare authoritative codes, identifiers, status,
   counts, basis points, and hashes to EligibilityJson.
9. Strict-parse PublicationJson and FinalOutcomeJson and compare every
   authoritative field to the validated eligibility and manifest.
10. Reconstruct immutable eligibility and committed publication objects, then
    compose the immutable final outcome.

Semantic equivalence means equality after parsing into the exact typed field,
not textual similarity: strings and enums ordinal case-sensitive; hashes exact
lowercase; paths under Section 10; integers and basis points exact; Booleans
exact; null distinct from empty; arrays exact order/cardinality; Details JCS
bytes exact; and failure SourceIdentifier/Code pairs exact. Human-readable
FailureMessage text and Markdown prose are explanatory and excluded from
semantic equivalence. Any authoritative-field mismatch fails the whole bundle.

The workflow authority issues TPMPublicationOutcomeV1 only from the publisher's
raw observations plus durable validation. That compiled object has exactly
SchemaVersion=1, RunIdentity, EligibilityPayloadSha256, Committed Boolean,
ManifestSha256 nullable, ArtifactSetSha256 nullable, FailureReasons, and
DiagnosticWarnings. A committed outcome requires both hashes and no failure
reasons; DiagnosticWarnings may contain POST_COMMIT_CLEANUP_FAILED without
changing commitment. Pre-commit failure requires Committed=false and one or more
ordered codes from STAGING_FAILED, PROMOTION_FAILED, MARKER_WRITE_FAILED,
DURABLE_VALIDATION_FAILED, or ROLLBACK_FAILED.

It then issues TPMFinalOutcomeV1
from its own exact issued eligibility and publication references. That object
has exactly SchemaVersion=1, RunIdentity, EligibilityPayloadSha256,
EligibleForCertification Boolean, PublicationCommitted Boolean, FinalStatus
CERTIFIED or NOT CERTIFIED, ExitCode integer 0 or 1, and FailureReasons.
CERTIFIED and exit 0 require both Booleans true; all other combinations are NOT
CERTIFIED and exit 1 with the ordered eligibility reasons followed by
publication reasons. Console, process return, and every in-memory status project
this one final object.

## 10. Normative Windows path containment

For every configured root and candidate:

1. Reject null/empty, NUL, invalid path characters, alternate-data-stream colon
   outside the drive designator, device paths, and non-file URI syntax.
2. Require the configured root to be absolute. Convert root and candidate with
   System.IO.Path.GetFullPath; relative candidates are resolved only against the
   already-canonical root, never process current directory.
3. Normalize directory separators to backslash, remove trailing separators
   except a drive or UNC root, and reject any residual dot or dot-dot component.
4. Split each full path into its volume/UNC root and path components. Compare
   volume and every root component with OrdinalIgnoreCase. Candidate is contained
   only when all root components match and candidate has no differing component
   before root exhaustion. Equality is allowed only where that schema permits
   the root itself. Simple StartsWith/string-prefix containment is forbidden.
5. Walk every existing component from root through candidate parent using
   LiteralPath semantics. Reject ReparsePoint components, including junctions
   and symbolic links. The output leaf must not exist when reserving a new file.
6. Open/create by literal canonical path with CreateNew. After creation, repeat
   canonicalization, component containment, and reparse checks before accepting
   ownership.

Failures are PATH_INVALID, PATH_OUTSIDE_ROOT, PATH_REPARSE_POINT,
PATH_ALREADY_EXISTS, or PATH_CHANGED_DURING_VALIDATION. Windows path identity
uses OrdinalIgnoreCase; hashes and artifact identifiers remain case-sensitive.

## 11. Migration

Phase 1 adds types and isolated tests only; legacy remains authoritative.
Phase 2 records identical observations into the shadow authority. Any
field-level divergence records run, field, legacy/new values, and comparison
rule; it invalidates migration evidence and blocks cutover but cannot change the
legacy run status, report, publication, console, or exit. The shadow never
publishes. Phase 3 atomically makes the new authority and publisher authoritative
and deletes every legacy decision assignment and arbitrary artifact callback.
Phase 4 adds external consumer tooling and removes migration diagnostics.

Cutover requires zero unresolved divergence across the adversarial matrix and
agreed real-machine sample. Rollback reverts the entire Phase 3 authority and
publisher change. Mixed authorities and two publishers are prohibited.

## 12. Authoritative-object inventory and final audit

| Object | Producer | Consumer | Schema/integrity | Provenance/lifecycle |
|---|---|---|---|---|
| Raw builders | workflow dispatcher | dispatcher only | Sections 5-6 | private, mutable only while Collecting |
| Score preview | dispatcher | final-evidence workflow | Section 5 rules | issued reference, single purpose |
| Sealed run reader | dispatcher Seal | eligibility issuer | Sections 3-6 hashes | issued reference, immutable after Seal |
| Eligibility snapshot | dispatcher | builder and publisher | Section 7 payload/hash | issued reference, immutable |
| Publication candidate | dispatcher | publisher | Section 8.2 | issued reference, conditional |
| Publication outcome | dispatcher after validation | final composer | Sections 8-9 | issued reference, immutable |
| Final outcome | dispatcher | console/process/consumer projection | Sections 8.3 and 9 | issued once, immutable |
| Reports | deterministic builder | publisher/consumer | Sections 7-9 | authoritative only under valid marker |
| Manifest | publisher | marker/consumer | Sections 4 and 8.6 | hash-bound |
| Marker | publisher last | consumer | Section 8.7 | publication proof only |

Consistency audit: hashes have non-recursive exact byte domains; all score and
evidence decisions are closed rules; artifact schemas and equivalence are exact;
the marker proves publication rather than certification; provenance spans raw
facts through final outcome; path containment is component-based and rejects
reparse ambiguity; eligibility and publication remain acyclic; and no renderer,
prose field, marker presence, or passing numeric score can independently certify
a run.
