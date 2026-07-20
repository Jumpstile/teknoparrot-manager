# ADR-0155 Implementation Checklist

Status: In progress. This checklist is subordinate to the architecture-approved
`ADR-0155-certification-authority-redesign.md`. A checkbox may be marked complete
only when its implementation, direct regression test, and required quality gate
have passed. Stable identifiers are retained across revisions.

## Phase 0 -- Contract and traceability

- [x] ADR155-0001 -- Architecture approval recorded for ADR commit
  `98033787fb6f46c1e453cb1e64f7f464202ea31c`.
- [x] ADR155-0002 -- Every implementation item has a stable identifier.
- [ ] ADR155-0003 -- PR description links this checklist and the approved ADR.
- [x] ADR155-0004 -- Every implementation commit lists the checklist identifiers
  it advances. Commit `28b70092179efecdb073fb300175790c11436aa6`
  records ADR155-0101 through ADR155-0105; commit
  `408336ee0aa9ba34d4fe35bf179b5170def8e497` records ADR155-Q001 through
  ADR155-Q007; review-correction commit
  `589bd0a69453e7763845c5e5f2b90464d4bedd74` advances ADR155-0102,
  ADR155-0103, ADR155-0105, and ADR155-T008. Commit `f99e394` records
  ADR155-0201 through ADR155-0207. Review-correction commit `942e70f` records
  the `New-TPMWorkflowAuthorityV1`/`New-TPMShadowWorkflowAuthorityV1` naming
  and module-coexistence fix to ADR155-0201. Commit `1dd994a` records the
  Phase 3 prerequisite shared-primitive extraction described below. The
  Phase 3 production-dispatcher commit records ADR155-0301.

## Phase 1 -- Isolated authority primitives

- [x] ADR155-0101 -- Add the versioned, idempotent compiled-type loader for
  `Jumpstile.TPM.Certification.V1` and reject partial/incompatible type sets.
- [x] ADR155-0102 -- Authoritative compiled types expose only deeply immutable
  scalar/string/enum state and have no public constructors or setters.
- [x] ADR155-0103 -- Add RFC 8785 JCS serialization for the closed ADR schemas,
  strict UTF-8 without BOM, I-JSON range enforcement, and deterministic hashes.
- [x] ADR155-0104 -- Add component-aware Windows path containment with explicit
  sibling-prefix, traversal, ADS, device-path, and reparse-point rejection.
- [x] ADR155-0105 -- Add isolated PS 5.1 and pwsh regression coverage for type
  loading, canonicalization, hashing, and containment.

## Phase 2 -- Shadow fact and evidence authority

- [x] ADR155-0201 -- Add one dispatcher closure over one private shared state
  object; expose no token-bearing state or mutable authoritative reference.
- [x] ADR155-0202 -- Implement the closed phase machine and fail closed on every
  illegal transition, duplicate, missing fact, or post-seal write.
- [x] ADR155-0203 -- Record the complete raw schemas for all eleven certification
  categories; conclusions remain derived and are never accepted as facts.
- [x] ADR155-0204 -- Record the exact nine-item evidence manifest with immediate
  PNG validation, path ownership, file hashes, and terminal final evidence.
- [x] ADR155-0205 -- Seal to canonical private bytes, destroy mutable builders,
  and return only an immutable reader/projection.
- [x] ADR155-0206 -- Run legacy authority and new shadow authority without giving
  the shadow publication, console, status, or exit-code authority.
- [x] ADR155-0207 -- Persist field-level divergence diagnostics and exclude every
  divergent run from Phase 3 migration evidence.

## Phase 3 -- Authoritative cutover and publication

- [x] ADR155-0301 -- Derive the eleven score items and eligibility payload only
  from the sealed raw-fact and evidence authority.
- [ ] ADR155-0302 -- Implement the detached JCS eligibility envelope and every
  non-recursive hash domain from ADR Section 4.
- [ ] ADR155-0303 -- Render final evidence from eligibility only; it must never
  claim `CERTIFIED` before publication.
- [x] ADR155-0304 -- Replace arbitrary artifact callbacks with deterministic
  internal builders for the five canonical reports.
- [ ] ADR155-0305 -- Build the exact manifest and commit marker with canonical
  identities, byte lengths, SHA-256 hashes, and run correlation.
- [ ] ADR155-0306 -- Stage the complete seven-file bundle and expose authority
  only after the marker is durably validated; never overwrite a destination.
- [ ] ADR155-0307 -- Compose the sole final outcome from issued eligibility and
  issued publication outcomes; console, reports, result, and exit code agree.
- [ ] ADR155-0308 -- Publish authoritative NOT CERTIFIED bundles for ineligible
  runs without confusing committed publication with certification success.
- [ ] ADR155-0309 -- Remove every legacy decision assignment, arbitrary builder,
  and competing publisher at the atomic Phase 3 cutover.

## Phase 4 -- Consumer validation and migration cleanup

- [ ] ADR155-0401 -- Validate marker, manifest, five reports, hashes, schemas,
  containment, run identity, and semantic equivalence in the fixed ADR order.
- [ ] ADR155-0402 -- Reconstruct compiled eligibility/publication/final objects
  only after the complete committed bundle validates.
- [ ] ADR155-0403 -- Reject stale/copied markers, prior-run artifacts, missing,
  extra, reordered, renamed, modified, or sibling-prefix escaped files.
- [ ] ADR155-0404 -- Remove shadow migration diagnostics after the required clean
  equivalence matrix and agreed real-machine sample pass.

## Defect-class regression matrix

- [ ] ADR155-T001 -- Mutable public projections cannot change private facts,
  evidence, eligibility, publication, or final outcome.
- [ ] ADR155-T002 -- Caller-created, copied, replayed, cross-run, serialized, or
  substituted authoritative-looking objects fail provenance validation.
- [ ] ADR155-T003 -- Missing, duplicate, reordered, malformed, or non-Boolean
  score facts cannot produce eligibility.
- [ ] ADR155-T004 -- Missing, duplicate, reordered, reused-path, escaped-path,
  malformed, skipped-required, or post-final evidence cannot produce eligibility.
- [ ] ADR155-T005 -- Publication failures before marker commitment produce no
  authoritative bundle; post-commit cleanup warnings do not reverse commitment.
- [ ] ADR155-T006 -- Marker presence alone never means CERTIFIED; consumer
  validation detects every modified or incomplete committed set.
- [ ] ADR155-T007 -- `PASS`, `CERTIFIED`, and exit code 0 occur only together;
  all other final outcomes are `FAIL`, `NOT CERTIFIED`, and exit code 1.
- [ ] ADR155-T008 -- RFC 8785/JCS, base64url Markdown transport, strict schemas,
  and semantic-equivalence rules have known-vector and adversarial coverage.

## Required quality gates

- [x] ADR155-Q001 -- Targeted tests pass under Windows PowerShell 5.1.
- [x] ADR155-Q002 -- Targeted tests pass under pwsh.
- [x] ADR155-Q003 -- Full suite passes under pwsh.
- [x] ADR155-Q004 -- Windows PowerShell 5.1 retains only the five issue #148
  failures until #148 is resolved separately.
- [x] ADR155-Q005 -- ASCII and parser checks pass.
- [x] ADR155-Q006 -- PSScriptAnalyzer passes with repository settings.
- [x] ADR155-Q007 -- InjectionHunter findings are individually dispositioned.
- [ ] ADR155-Q008 -- Independent code review returns MERGE-READY.
- [ ] ADR155-Q009 -- Final arcade-machine certification passes on the exact
  merged commit before PR #155 may be treated as release-ready.

## Phase 1 implementation evidence -- 2026-07-19

- ADR155-0101/0102: `scripts/TPMCertification.Authority.psm1` loads the
  exact ten-type V1 set once, rejects partial or incompatible collisions, and
  validates shared assembly identity, schema version, authority marker, private
  constructors, readonly scalar backing fields, and absence of public setters.
- ADR155-0103: the isolated module implements the closed-schema RFC 8785 subset
  used by this ADR (null, Boolean, string, safe signed integer, object, array),
  strict surrogate and UTF-8 handling, SHA-256 lowercase hex, and canonical
  whole-message unpadded base64url transport. `ConvertTo-TPMJcsV1` deliberately
  rejects every non-integer numeric value because the current authoritative
  schemas never require fractional values. Rejecting unsupported numeric forms
  is an intentional specification decision; ECMAScript shortest-round-trip
  formatting is therefore intentionally outside ADR-0155 Phase 1 scope.
- ADR155-0104: containment resolves relative candidates against the canonical
  absolute root and compares volume and components with OrdinalIgnoreCase. It
  rejects dot segments, sibling prefixes, ADS, device paths, non-file URI
  syntax, and existing reparse-point components without wildcard expansion.
- ADR155-0105/Q001/Q002: `Tests/TPMCertification.Authority.Tests.ps1` passed
  14/14 on pwsh 7.6.3 and 14/14 on Windows PowerShell 5.1.26100.8875.
- ADR155-Q003: `Invoke-Pester -Path .\Tests` passed 826/826 on pwsh 7.6.3.
- ADR155-Q004: the same suite passed 821/826 on Windows PowerShell 5.1; the
  only failures are the five unchanged Repair-GamePaths cases tracked by #148.
- ADR155-Q005: production script, new module, and focused tests each had zero
  non-ASCII bytes and zero parser errors.
- ADR155-Q006: repository-configured PSScriptAnalyzer returned zero findings
  for the production script, new module, and focused tests.
- ADR155-Q007: InjectionHunter returned zero findings for the new module. Its
  16 production-script findings are unchanged because Phase 1 does not modify
  `TeknoParrot-Manager.ps1`: four Add-Type calls use fixed assembly names, and
  twelve UnsafeEscaping findings use fixed format or regular-expression
  patterns rather than attacker-controlled code, command, or pattern text.
  No Phase 1 input reaches dynamic execution.

`New-TPMWorkflowAuthorityV1` is an isolated functioning prototype of
ADR155-0201. It exists in Phase 1 solely to validate capability separation,
sealing, post-seal recording rejection, and in-process provenance identity.
ADR155-0201 remains unchecked: full Phase 2 workflow integration, its complete
phase machine, and production observation routing are still pending independent
Phase 1 approval.

Phase 1 remains isolated and does not alter legacy certification authority.
Phase 2 and later checklist items remain intentionally incomplete.

## Phase 1 review-correction evidence -- 2026-07-19

- Commit `589bd0a69453e7763845c5e5f2b90464d4bedd74` adds explicit
  rejection of padded base64url and reflects over both every derived
  authoritative type and `ValueV1` when verifying deep immutability.
- Focused tests remained 14/14 on pwsh 7.6.3 and 14/14 on Windows PowerShell
  5.1.26100.8875. The two review cases strengthen existing tests rather than
  increasing test-container cardinality.
- Full Pester remained 826/826 on pwsh and 821/826 on Windows PowerShell 5.1,
  with exactly the five unchanged issue #148 Repair-GamePaths failures.
- ASCII and parser checks returned zero for the production script, Phase 1
  module, and focused tests. Repository-configured PSScriptAnalyzer returned
  zero findings for all three. InjectionHunter remained zero for the Phase 1
  module and at the individually dispositioned 16-finding production baseline.
- ADR155-0201 remains unchecked. Its dispatcher is an isolated prototype only;
  no Phase 2 production integration or workflow authority has begun.

## Phase 2 implementation evidence -- 2026-07-20

- ADR155-0201/0202: commit `f99e394` adds `scripts/TPMCertification.Shadow.psm1`,
  a single dispatcher closure (`New-TPMShadowWorkflowAuthorityV1`) over one
  private `[pscustomobject]` state object, reusing the Phase 1 provenance/JCS/
  hash/containment primitives. The dispatch scriptblock fails closed on every
  illegal phase transition, duplicate fact, out-of-order fact, duplicate
  score-preview issuance, post-final evidence, and post-seal write
  (`ILLEGAL_PHASE`, `FACT_DUPLICATE`, `FACT_ORDER_INVALID`,
  `DUPLICATE_ISSUANCE`, `EVIDENCE_POST_FINAL`, `MANIFEST_INCOMPLETE`).
- ADR155-0203: `Assert-TPMFactRecordV1` enforces the exact field set for each
  of the eleven certification categories from ADR Section 5. Conclusions
  (`Get-TPMFactDecisionV1`) are computed separately from the recorded raw
  data and are never accepted as input.
- ADR155-0204: `Assert-TPMEvidenceRecordV1` enforces the nine-item manifest
  order, immediate PNG validation via the injected validator callback, path
  containment and per-run path ownership (rejecting reuse), a SHA-256 file
  hash re-verified after validation, and a terminal ninth (`IssueFinalEvidence`)
  record that consumes the score preview by identity.
- ADR155-0205: `Seal` requires all eleven facts and nine evidence records,
  builds canonical JSON directly from the recorded per-item JCS fragments,
  nulls every mutable collection, and returns only a compiled
  `TPMSealedRunReaderV1` issued through the same identity-checked closure as
  Phase 1's `TPMSealedRunReaderV1`.
- ADR155-0206: `Invoke-TPMShadowCertificationV1` and its harness call site in
  `Invoke-TPM-RealInstanceSmoke.ps1` run only after the legacy
  `final-certification-result` screenshot and before
  `Complete-TPMCertificationTransaction`. The shadow result is written to a
  separate `ShadowMigration` diagnostic file and the harness never reads it
  back into `$results`; regression test `ADR-0155 Phase 2 production shadow
  boundary` asserts this ordering and the absence of any `$results.Shadow`
  reference by inspecting the production script's own source text.
- ADR155-0207: `Compare-TPMShadowScoreV1` records field-level
  `ScoreItems[i].{Identifier,Status,Passed}` divergences against the legacy
  score items; `Invoke-TPMShadowCertificationV1` sets `MigrationEligible`
  false whenever any divergence, or any shadow-side exception, occurs, and
  persists the diagnostic via `Write-TPMShadowDiagnosticV1`
  (`FileMode.CreateNew`, refusing to overwrite a prior run's diagnostic).
- Defect fix: the encoding-path validator in `Assert-TPMFactRecordV1`'s
  `Static Analysis` case checked `$f.Contains('\\')` -- a two-character
  literal in a single-quoted string, i.e. two consecutive backslashes -- and
  split dot-segments only on `/`, so `..\bad.ps1` was accepted. It now
  checks `$f.Contains('\')` (one backslash) and splits on `[\\/]`, matching
  the split behavior already used by Phase 1's `Resolve-TPMContainedPathV1`.
- ADR155-Q001/Q002: `Tests/TPMCertification.Shadow.Tests.ps1` passed 16/16 on
  pwsh 7.6.3 and 16/16 on Windows PowerShell 5.1.26100.8875.
- ADR155-Q003: `Invoke-Pester -Path .\Tests` passed 842/842 on pwsh 7.6.3.
- ADR155-Q004: the same suite passed 837/842 on Windows PowerShell 5.1; the
  only failures are the five unchanged Repair-GamePaths cases tracked by
  #148, individually confirmed unchanged by name against the Phase 1
  baseline.
- ADR155-Q005: the new module, its focused tests, and the modified harness
  script each had zero non-ASCII bytes and zero parser errors.
- ADR155-Q006: repository-configured PSScriptAnalyzer returned zero findings
  for all three files.
- ADR155-Q007: InjectionHunter returned zero findings for the new module and
  its focused tests. The harness script's six findings (one `AddScript`, one
  `StaticPropertyInjection`, four `AddType`) are byte-for-byte the same six
  findings present before this change (confirmed by re-running
  InjectionHunter against the pre-diff working tree via `git stash`); the
  Phase 2 diff introduces none of them and does not touch any of the
  flagged lines.

## Phase 2 review-correction evidence -- 2026-07-20

Independent Phase 2 review of commits `f99e394`/`e900a8b` found one finding:
`scripts/TPMCertification.Authority.psm1` and `scripts/TPMCertification.Shadow.psm1`
both exported a public function named `New-TPMWorkflowAuthorityV1` with
incompatible signatures (Authority's Phase 1 prototype takes no parameters;
Shadow's Phase 2 dispatcher requires `-Mode`/`-EvidenceRoot`). Reviewer testing
showed that once both modules are imported into one session -- which
`Invoke-Pester -Path .\Tests` already does, and which Phase 3 will require --
`Get-Command New-TPMWorkflowAuthorityV1` resolved to whichever module was
imported later, hiding the other.

- Renamed Shadow's exported factory from `New-TPMWorkflowAuthorityV1` to
  `New-TPMShadowWorkflowAuthorityV1` in `scripts/TPMCertification.Shadow.psm1`
  (the function definition, its Export-ModuleMember entry, and its own
  internal call site inside `Invoke-TPMShadowCertificationV1`), and updated
  every call site in `Tests/TPMCertification.Shadow.Tests.ps1`.
  `scripts/TPMCertification.Authority.psm1` is unchanged; its Phase 1
  `New-TPMWorkflowAuthorityV1` prototype keeps its name.
- The rename alone was insufficient: reviewer testing after the rename showed
  that importing `TPMCertification.Authority.psm1` at global/session scope
  and then importing `TPMCertification.Shadow.psm1` still removed Authority's
  entire exported surface (not just the renamed factory --
  `Initialize-TPMCertificationTypesV1`, `ConvertTo-TPMJcsV1`,
  `Get-TPMSha256HexV1`, `Resolve-TPMContainedPathV1`, all of it) from the
  session. The cause was Shadow's own top-of-file
  `Import-Module ... TPMCertification.Authority.psm1 -Force`: forcing a
  reload of a module already loaded at global scope, from within a second
  module's nested import, re-parents that module's exports to the second
  module's private scope and drops the prior global registration. Removing
  `-Force` from that one line (`scripts/TPMCertification.Shadow.psm1:1`) is
  sufficient: a non-forced `Import-Module` of an already-loaded module by the
  same resolved path is a no-op rather than a destructive reload, and Shadow
  still resolves the Authority functions it depends on internally either way.
- Added `Describe 'ADR-0155 Phase 1/Phase 2 module coexistence'` to
  `Tests/TPMCertification.Shadow.Tests.ps1`: it spawns a child process of the
  current engine for each import order (Authority-then-Shadow and
  Shadow-then-Authority), imports both modules by absolute path, and asserts
  by `Get-Command ... ModuleName` that `New-TPMWorkflowAuthorityV1` remains
  owned by `TPMCertification.Authority` and `New-TPMShadowWorkflowAuthorityV1`
  remains owned by `TPMCertification.Shadow` in both orders, and that calling
  each with no arguments fails or succeeds according to its own real
  parameter set (Authority's succeeds with zero arguments; Shadow's fails on
  its own missing-mandatory-parameter message) rather than the other
  factory's behavior.
- ADR155-Q001/Q002: `Tests/TPMCertification.Authority.Tests.ps1` (unchanged)
  passed 14/14 on pwsh 7.6.3 and 14/14 on Windows PowerShell 5.1.26100.8875;
  `Tests/TPMCertification.Shadow.Tests.ps1` passed 17/17 (16 existing plus the
  new coexistence test) on both engines.
- ADR155-Q003/Q004: `Invoke-Pester -Path .\Tests` passed 843/843 on pwsh
  7.6.3 and 838/843 on Windows PowerShell 5.1, with exactly the same five
  unchanged issue #148 Repair-GamePaths failures.
- ADR155-Q005/Q006/Q007: `scripts/TPMCertification.Shadow.psm1` and
  `Tests/TPMCertification.Shadow.Tests.ps1` each had zero non-ASCII bytes,
  zero parser errors, zero PSScriptAnalyzer findings, and zero InjectionHunter
  findings after the fix.

This fix is isolated to import statements, one function name, and its call
sites; it changes no schema, phase-machine transition, provenance check, or
publication behavior. ADR155-0201/0202/0206 evidence above remains accurate
under the new name.

Phase 2 shadow authority does not alter legacy certification decisions,
console output, reports, or exit codes. Phase 3 and Phase 4 checklist items
remain intentionally incomplete; Phase 3 has not begun.

## Phase 3 prerequisite: shared primitive extraction -- 2026-07-20

Commit `1dd994a` advances this prerequisite (not a numbered ADR155 item
itself, since Section 2.2 requires eligibility/publication/final-outcome to
be issued by the same continuous dispatcher that recorded facts and
evidence, which means the Phase 3 production dispatcher needs the same
fact/evidence schema and decision logic Shadow.psm1 already implements).

- Moved `Assert-TPMFactRecordV1`, `Get-TPMFactDecisionV1`,
  `Assert-TPMEvidenceRecordV1`, their schema/copy helpers, and the three
  manifest constant arrays from `scripts/TPMCertification.Shadow.psm1` to
  `scripts/TPMCertification.Authority.psm1` verbatim; no logic changed.
  Added `Get-TPMFactIdentifiersV1`, `Get-TPMEvidenceManifestV1`, and
  `Get-TPMEvidenceFailureCodesV1` accessors for the moved constant data.
- Exported only the primitives Shadow.psm1 calls externally
  (`Assert-TPMFactRecordV1`, `Get-TPMFactDecisionV1`,
  `Assert-TPMEvidenceRecordV1`, `Copy-TPMClosedValueV1`, and the three
  accessors); the field/type-level helpers (`Assert-TPMExactFieldsV1`,
  `Assert-TPMBooleanV1`, etc.) stay private to Authority.psm1.
- `scripts/TPMCertification.Shadow.psm1` now imports these from Authority.psm1
  instead of defining them; `New-TPMShadowWorkflowAuthorityV1`'s phase
  machine, schemas, and decisions are otherwise unchanged.
- Caught and fixed a double-array-wrap defect introduced by the move itself:
  the new accessor functions return their array as one object via
  `return ,@(...)`, so callers must bind the result directly rather than
  wrapping it in `@()` again; an extra `@()` around an already-single-object
  array return produces a one-element array containing that array. This
  surfaced immediately as `FACT_ORDER_INVALID` across the Shadow suite and
  was fixed before committing.
- Added direct-export regression coverage to
  `Tests/TPMCertification.Authority.Tests.ps1` (positive/negative fact and
  evidence vectors, N/A decision, defensive-copy isolation) and extended the
  module-coexistence test in `Tests/TPMCertification.Shadow.Tests.ps1` to
  assert `Assert-TPMFactRecordV1` and `Get-TPMFactIdentifiersV1` resolve to
  `TPMCertification.Authority` regardless of import order, alongside the
  existing workflow-authority-factory coexistence coverage.
- ADR155-Q001/Q002: `Tests/TPMCertification.Authority.Tests.ps1` and
  `Tests/TPMCertification.Shadow.Tests.ps1` together passed 36/36 on both
  pwsh 7.6.3 and Windows PowerShell 5.1.26100.8875 (14+17 prior plus 5 new
  Authority tests).
- ADR155-Q003/Q004: `Invoke-Pester -Path .\Tests` passed 848/848 on pwsh
  7.6.3 and 843/848 on Windows PowerShell 5.1, with exactly the same five
  unchanged issue #148 Repair-GamePaths failures.
- ADR155-Q005/Q006/Q007: all four changed files had zero non-ASCII bytes,
  zero parser errors, zero PSScriptAnalyzer findings, and zero InjectionHunter
  findings.

Shadow's own behavior is unchanged (17/17 Shadow tests pass, byte-identical
assertions, before and after the move).

## Phase 3 production dispatcher -- 2026-07-20

Adds `scripts/TPMCertification.Production.psm1`: a dispatcher closure
(`New-TPMProductionWorkflowAuthorityV1`, deliberately named apart from both
`New-TPMWorkflowAuthorityV1` and `New-TPMShadowWorkflowAuthorityV1` to avoid
the exact export collision fixed earlier in this PR) implementing the
complete closed phase machine from ADR Section 2.1, Collecting through
FinalOutcomeIssued. `RecordFact`, `RecordEvidence`, `DeriveScorePreview`,
`IssueFinalEvidence`, and `Seal` reuse the same fact/evidence schemas and
phase-machine rules as the approved Phase 1/2 authorities (via the shared
Authority.psm1 primitives above) -- Facts and Evidence are deliberately kept
in private state after `Seal` (unlike the Phase 2 shadow dispatcher, which
discards them) because `IssueEligibility` must derive its payload from that
same raw, sealed data, not from a second parse of any serialized form.

- ADR155-0301: `IssueEligibility` validates the caller's sealed-run reader by
  the same ReferenceEquals/RunIdentity/type/schema provenance check as every
  other issuance, then derives all eleven score items via the shared
  `Get-TPMFactDecisionV1`, evidence eligibility from the nine sealed evidence
  records against the manifest's `Required`/`Status` rules, and the full
  Section 7.2 payload shape (`ApplicableCount`, `PassedCount`,
  `PercentageBasisPoints` rounded per `MidpointRounding.AwayFromZero`,
  `ThresholdBasisPoints`, `ScoreEligible`, `EvidenceEligible`,
  `EligibleForCertification`, ordered `FailureReasons`) in
  `Get-TPMEligibilityPayloadV1`, exported for direct unit testing.
- Partial ADR155-0302 progress: implements the `FactSetSha256`,
  `EvidenceSetSha256`, `SealedRunSha256`, and `EligibilityPayloadSha256` hash
  domains from the Section 4 table (computed from the exact bytes retained at
  `Seal`, not re-parsed JSON) and issues `TPMEligibilitySnapshotV1` holding
  the canonical Payload bytes. The checklist item remains unchecked because
  the detached Payload-then-Integrity file envelope itself (the actual
  `TPM-Certification-Eligibility.json` document) and the `ArtifactSha256`/
  `ArtifactSetSha256`/`ManifestSha256` hash domains belong to the not-yet-built
  report/manifest builders (ADR155-0304).
- Extends the same provenance-gated issuance pattern through
  `IssuePublicationCandidate` (Section 8.2 candidate schema),
  `RegisterCommittedPublication`/`RegisterPublicationFailure` (Section 9
  `TPMPublicationOutcomeV1`, from raw publisher observations the dispatcher
  itself never produces -- no publisher exists yet), and `IssueFinalOutcome`
  (Section 9 `TPMFinalOutcomeV1`, composing `FinalStatus`/`ExitCode` only from
  the dispatcher's own already-validated `EligibleForCertification` and
  `Committed` booleans). This exercises the full phase table but does not
  complete ADR155-0303/0304/0305/0306/0307/0308/0309, all of which need the
  report builders, staging/publisher, and harness cutover that remain
  unbuilt.
- Two defects were caught and fixed while writing this module, both before
  committing:
  - Every call from inside the dispatcher's own `.GetNewClosure()` scriptblock
    to a function imported (without `-Force`) from `TPMCertification.Authority.psm1`
    failed with "term not recognized," even though the same functions resolved
    fine from plain (non-closure) functions in the same module. The existing,
    approved Shadow dispatcher already worked around exactly this by capturing
    each cross-module function as a `${function:Name}` reference before
    building the closure and invoking it via `&$captured` instead of calling
    it by name; this module was missing that pattern for its own new
    operations and now follows it throughout.
  - `Get-TPMEligibilityPayloadV1` wrapped its `$Facts`/`$Evidence`
    `Collections.Generic.List[object]` parameters in `@(...)` inside a
    function that also declares other parameters, which threw "Argument
    types do not match" -- the same PowerShell binder quirk already
    documented elsewhere in this repository's history for
    `Invoke-TPM-RealInstanceSmoke.ps1`. Fixed by copying into a new
    `List[object]` via `foreach` instead of wrapping with `@()`.
  - The new module-coexistence test's `$orders` array (three candidate
    import orders, each itself a 3-element array) silently flattened into one
    6-element array, because a multi-line `@( @(...) @(...) )` literal with
    no commas between rows treats each row as separate pipeline output that
    the outer `@()` re-flattens -- the same class of bug as the two above,
    fixed with the established `,@(...)` idiom on each row.
- ADR155-Q001/Q002: `Tests/TPMCertification.Production.Tests.ps1` (14 tests:
  full pipeline to CERTIFIED, publication-failure and eligibility-failure
  outcomes, RegisterPublicationFailure directly from EligibilityIssued,
  phase/provenance/schema rejection for every new operation, eligibility
  rounding and zero-applicable-count derivation, and three-module
  coexistence) passed 14/14 on pwsh 7.6.3 and 14/14 on Windows PowerShell
  5.1.26100.8875. Combined with the unchanged Authority and Shadow suites:
  50/50 on both engines.
- ADR155-Q003/Q004: `Invoke-Pester -Path .\Tests` passed 862/862 on pwsh
  7.6.3 and 857/862 on Windows PowerShell 5.1, with exactly the same five
  unchanged issue #148 Repair-GamePaths failures.
- ADR155-Q005/Q006/Q007: the new module and its tests, plus
  `TPMCertification.Authority.psm1` (two more primitives exported --
  `Assert-TPMExactFieldsV1` and `Assert-TPMStringV1` -- needed by this
  module's publication-observation validators), had zero non-ASCII bytes,
  zero parser errors, zero PSScriptAnalyzer findings, and zero InjectionHunter
  findings.

This dispatcher is not wired into the production harness and has no
publication, console, status, or exit-code authority; `Invoke-TPM-RealInstanceSmoke.ps1`
is unchanged by this commit. Phase 3 report/manifest/marker builders,
staging/publisher, external consumer validation, and the atomic cutover
(ADR155-0303 through 0309) remain unbuilt.

Independently reviewed and returned APPROVED (commit `0848424` reviewed as a
production-dispatcher checkpoint separate from the frozen Phase 2 baseline;
Phase 1/2 files confirmed byte-identical to the last approved Phase 2
commit). One non-blocking maintainability note from that review: four of
the five `DUPLICATE_ISSUANCE` guards in the dispatcher (`Eligibility`,
`PublicationCandidate`, `PublicationOutcome` from either `Register*` path,
`FinalOutcome`) are unreachable given the phase machine's strictly forward
progression -- a repeat call always hits its `ILLEGAL_PHASE` guard first.
Harmless defense-in-depth; left as-is, noted here for a future maintainer.

## Phase 3 eligibility report builder -- 2026-07-20

Adds `scripts/TPMCertification.Reports.psm1`: `New-TPMEligibilityReportV1`,
a pure, side-effect-free builder that turns an issued `TPMEligibilitySnapshotV1`
into the exact `TPM-Certification-Eligibility.json` bytes from ADR Section
7.2/8.1. Deliberately kept in its own module, separate from the dispatcher
(`Production.psm1`) and from any future publisher/staging code, matching
the Section 12 producer/consumer split between "deterministic builder" and
"publisher."

- Advances the remaining half of ADR155-0302: the detached
  Payload-then-Integrity envelope itself. Confirmed by direct test that
  `ConvertTo-TPMJcsV1` sorts the two top-level keys as `Integrity` before
  `Payload` (`"I" < "P"` under ordinal UTF-16 comparison) -- opposite of the
  ADR prose's reading order, which Section 3 explicitly says is membership/
  array order, not a claim about serialized object-property order. The
  builder therefore hardcodes `Integrity` first via literal string
  concatenation of already-canonical fragments (the same technique `Seal`
  already uses for the sealed-run document), splicing in the eligibility
  snapshot's own `CanonicalJson` verbatim as the `Payload` value rather than
  re-parsing and re-serializing it -- avoiding any risk of round-trip drift
  between the hash that was computed at `IssueEligibility` time and the
  bytes actually embedded in the report.
  `EligibilityPayloadSha256` is independently recomputed by the builder
  from the snapshot's own canonical bytes rather than trusted from a
  caller-supplied value, so the report is self-verifying.
  ADR155-0302 remains unchecked: `ArtifactSha256`, `ArtifactSetSha256`, and
  `ManifestSha256` are still outstanding, and per the Section 4 table their
  producer is the publisher, not this builder -- they depend on the
  not-yet-built manifest/staging work (ADR155-0304/0305/0306).
- The builder validates its input is exactly a
  `Jumpstile.TPM.Certification.V1.TPMEligibilitySnapshotV1` instance (type
  and namespace) and rejects anything else, including a same-type object
  constructed directly via reflection rather than issued by a real
  dispatcher -- documented explicitly as a boundary, not a gap: ADR Section
  2.1 forbids the dispatcher's own capability (and therefore its private
  `ReferenceEquals` registry) from ever being passed to a renderer/builder,
  so full dispatcher-identity provenance is deliberately out of reach here
  by design; the workflow must only ever call this builder with an object
  it just received directly from its own dispatcher.
- ADR155-Q001/Q002: `Tests/TPMCertification.Reports.Tests.ps1` (6 tests:
  exact envelope key order and hash self-consistency, verbatim Payload
  byte-splice with no re-serialization drift, BOM-less UTF-8 output, wrong-
  compiled-type rejection, and null/plain-object rejection) passed 6/6 on
  pwsh 7.6.3 and 6/6 on Windows PowerShell 5.1.26100.8875.
- ADR155-Q003/Q004: `Invoke-Pester -Path .\Tests` passed 868/868 on pwsh
  7.6.3 and 863/868 on Windows PowerShell 5.1, with exactly the same five
  unchanged issue #148 Repair-GamePaths failures.
- ADR155-Q005/Q006/Q007: the new module and its tests had zero non-ASCII
  bytes, zero parser errors, zero PSScriptAnalyzer findings, and zero
  InjectionHunter findings.

This builder produces bytes only; nothing is written to disk, staged, or
published, and no harness wiring or final-authority ownership was touched.
ADR155-0303 through 0309 remain unbuilt.

## Phase 3 shared score aggregate and final-evidence status -- 2026-07-20

Adds `Get-TPMScoreAggregateV1` to `scripts/TPMCertification.Authority.psm1`:
the score-arithmetic portion of `Get-TPMEligibilityPayloadV1` (ApplicableCount,
PassedCount, PercentageBasisPoints with `MidpointRounding.AwayFromZero`,
ThresholdBasisPoints, ScoreEligible from Section 7.1), extracted so it can be
reused rather than duplicated. `Get-TPMEligibilityPayloadV1` (Production.psm1)
now calls it instead of recomputing the same logic inline; behavior is
unchanged, confirmed by rerunning the existing Production suite unmodified
(still 14/14 on both engines).

Adds `Get-TPMFinalEvidenceStatusV1` to `scripts/TPMCertification.Reports.psm1`:
given an issued `TPMScorePreviewV1`, calls the same shared
`Get-TPMScoreAggregateV1` to derive its status text -- exactly `'ELIGIBLE'`
or `'NOT ELIGIBLE PENDING EVIDENCE AND PUBLICATION'`, never `'CERTIFIED'` --
per Section 6's rule for what the `final-certification-result` evidence
capture may render at `IssueFinalEvidence` time, before Sealing or
Eligibility exist. Advances the pure-logic portion of ADR155-0303; the item
stays unchecked because "render" implies the harness actually using this
function to produce the on-screen/captured text, which is deliberately not
done here -- wiring a report/status builder into the live certification
harness is harness-integration work, out of scope until explicitly
authorized, per ADR155-0309's atomic-cutover framing.

- ADR155-Q001/Q002: `Tests/TPMCertification.Reports.Tests.ps1` gained 6
  more tests (ELIGIBLE/NOT-ELIGIBLE rendering, an explicit assertion the
  status never contains "CERTIFIED" even for a fully passing run, and
  synthetic/wrong-type/null rejection); `Tests/TPMCertification.Authority.Tests.ps1`
  gained 3 tests for `Get-TPMScoreAggregateV1` directly (aggregate counts
  and rounding, the ScoreEligible conjunction, and the zero-applicable
  throw). Combined with all prior focused suites: 65/65 on pwsh 7.6.3 and
  65/65 on Windows PowerShell 5.1.26100.8875.
- ADR155-Q003/Q004: `Invoke-Pester -Path .\Tests` passed 877/877 on pwsh
  7.6.3 and 872/877 on Windows PowerShell 5.1, with exactly the same five
  unchanged issue #148 Repair-GamePaths failures.
- ADR155-Q005/Q006/Q007: all five changed/touched files had zero non-ASCII
  bytes, zero parser errors, zero PSScriptAnalyzer findings, and zero
  InjectionHunter findings.

No harness wiring, file I/O, staging, or publication in this commit.

## Phase 3 publication and final-outcome report builders -- 2026-07-20

Adds two more of the five canonical reports (ADR155-0304) to
`scripts/TPMCertification.Reports.psm1`:

- `New-TPMPublicationReportV1` -- `TPM-Certification-Publication.json`
  (Section 8.2). The issued `TPMPublicationCandidateV1`'s field set
  matches the file schema exactly (same seven fields), so this builder
  validates the compiled type and passes its `CanonicalJson` through
  verbatim rather than reconstructing it -- no re-parse/re-serialize
  drift is possible because there is no transformation to perform.
- `New-TPMFinalOutcomeReportV1` -- `TPM-Certification-Final-Outcome.json`
  (Section 8.3). Unlike Publication, this file schema is a genuine
  *projection* of the issued `TPMFinalOutcomeV1`, not a verbatim copy:
  the compiled object carries `EligibleForCertification`/
  `PublicationCommitted` Booleans and `FailureReasons`, while the file
  requires `EligibilityStatus` (`'Eligible'`/`'NotEligible'`, derived from
  `EligibleForCertification`), the fixed literal
  `RequiredPublicationState='Committed'`, and no `FailureReasons` field at
  all. The builder strict-parses the compiled object's own trusted
  `CanonicalJson`, asserts every field it depends on is present, and
  rebuilds the six-field file schema through `ConvertTo-TPMJcsV1` rather
  than hand-splicing, since (unlike Publication and Eligibility) the
  output is a different shape from the input.
- Both builders follow the established pattern: validate the exact
  compiled type and namespace before doing anything else, reuse
  `Get-TPMSha256HexV1`/`ConvertTo-TPMJcsV1` from Authority.psm1 rather
  than reimplementing hashing or canonicalization, and produce bytes
  only -- no file I/O, staging, or harness wiring.
- ADR155-Q001/Q002: `Tests/TPMCertification.Reports.Tests.ps1` gained 9
  more tests (exact seven/six-field schemas, verbatim-vs-projected
  behavior confirmed directly against both builders, all three
  EligibilityStatus/FinalStatus/ExitCode combinations -- eligible+committed,
  eligible+publication-failed, score-ineligible+committed -- an explicit
  check that `FailureReasons` is present on the compiled object but absent
  from the final-outcome file, and synthetic/wrong-type/null rejection for
  both builders). Combined with all prior focused suites: 84/84 on pwsh
  7.6.3 and 84/84 on Windows PowerShell 5.1.26100.8875.
- ADR155-Q003/Q004: `Invoke-Pester -Path .\Tests` passed 884/884 on pwsh
  7.6.3 and 879/884 on Windows PowerShell 5.1, with exactly the same five
  unchanged issue #148 Repair-GamePaths failures.
- ADR155-Q005/Q006/Q007: both changed/touched files had zero non-ASCII
  bytes, zero parser errors, zero PSScriptAnalyzer findings, and zero
  InjectionHunter findings.

ADR155-0304 remains unchecked: three of five canonical reports are done
(Eligibility, Publication, Final Outcome); the two Markdown reports
(Scorecard, Validation) remain, and need the Section 8.4 base64url
transport machinery this round deliberately did not build. No harness
wiring, file I/O, staging, or publication in this commit.

## Phase 3 delta review correction -- 2026-07-20

Independent delta review of commit `05239c7` returned CHANGES REQUIRED
with two findings, both corrected in this commit:

- P2: `New-TPMFinalOutcomeReportV1`'s required-source-field validation
  list checked six of the seven `TPMFinalOutcomeV1` fields it depends on
  the source object being well-formed for, omitting `PublicationCommitted`
  -- even though the builder's own output never reads that field's value
  (`RequiredPublicationState` is the fixed file-schema literal
  `'Committed'`, never derived from `PublicationCommitted`, which is
  unchanged by this fix). Added `PublicationCommitted` to the validation
  list, so a malformed or incomplete compiled object is rejected before
  being treated as authoritative, rather than only checking the fields the
  builder happens to consume. Added a regression test constructing a
  same-compiled-type `TPMFinalOutcomeV1` whose canonical JSON omits
  `PublicationCommitted`; the builder now rejects it with
  `REPORT_INVALID`.
- P3: renamed the "exact six-field file schema" test description to
  "exact seven-field file schema" -- the file schema has seven fields
  (SchemaVersion, RunIdentity, EligibilityPayloadSha256,
  EligibilityStatus, RequiredPublicationState, FinalStatus, ExitCode);
  the prose was simply miscounted.

- ADR155-Q001/Q002: `Tests/TPMCertification.Reports.Tests.ps1` gained 1
  more test (20 total). Combined with all prior focused suites: 85/85 on
  pwsh 7.6.3 and 85/85 on Windows PowerShell 5.1.26100.8875.
- ADR155-Q003/Q004: `Invoke-Pester -Path .\Tests` passed 885/885 on pwsh
  7.6.3 and 880/885 on Windows PowerShell 5.1, with exactly the same five
  unchanged issue #148 Repair-GamePaths failures.
- ADR155-Q005/Q006/Q007: both changed files had zero non-ASCII bytes, zero
  parser errors, zero PSScriptAnalyzer findings, and zero InjectionHunter
  findings.

No architectural or behavioral change beyond the two findings; ADR155-0304
remains unchecked for the same reason as above.

## Phase 3 base64url transport and Markdown report builders -- 2026-07-20

Completes ADR155-0304: the two remaining canonical reports (Scorecard,
Validation) and their Section 8.4 base64url transport prerequisite.

- Extends `ConvertTo-TPMJcsV1` (Authority.psm1) with a `PSCustomObject`
  branch alongside its existing `IDictionary`/`IEnumerable` handling.
  `ConvertFrom-Json` (used throughout this module's builders to consume a
  compiled object's own trusted `CanonicalJson`) produces `PSCustomObject`
  for JSON objects, not `IDictionary`; without this, re-canonicalizing a
  parsed sub-structure -- needed for `Details-JCS-Base64Url` per score
  item -- threw `unsupported JCS value`. Confirmed by direct reproduction
  before fixing. The change is purely additive (a new type branch; no
  existing behavior for hashtables, arrays, or scalars changes) and
  verified byte-identical on a representative round-trip
  (`canonicalize -> ConvertFrom-Json -> canonicalize again`) before being
  used anywhere else.
- Adds `ConvertTo-TPMJcsBase64UrlV1`/`ConvertFrom-TPMJcsBase64UrlV1`
  (Authority.psm1): the Section 8.4 "arbitrary structured values use JCS
  bytes encoded as RFC 4648 base64url without padding" transport --
  distinct from the already-approved `ConvertTo/FromTPMFailureMessageBase64UrlV1`
  pair (Phase 1), which wraps the message as one JCS JSON *string* first.
  This transport encodes already-canonical JCS bytes directly, with the
  same malformed-input/alphabet/padding rejection rules.
- Adds `New-TPMScorecardReportV1` (`TPM-Certification-Scorecard.md`,
  Section 8.4) and `New-TPMValidationReportV1`
  (`TPM-Certification-Validation.md`, Section 8.5) to Reports.psm1. Both
  strict-parse their input compiled object(s)' own trusted `CanonicalJson`
  (Eligibility alone for Scorecard; SealedRun plus Eligibility for
  Validation, with an explicit cross-check that both share the same
  `RunIdentity`), assert every field depended upon is present, and build
  the fixed-heading/fixed-key Markdown structure with no caller-controlled
  value interpolated into headings, list markers, or fences -- every
  Identifier and Code comes from the closed manifest/decision vocabulary,
  never free text; every free-text Message goes through the base64url
  transport.
- ADR155-Q001/Q002: `Tests/TPMCertification.Reports.Tests.ps1` gained 14
  more tests (34 total; 119 combined with all prior focused suites),
  including direct verification that decoding `Facts-JCS-Base64Url`/
  `Evidence-JCS-Base64Url`/`Eligibility-Payload-JCS-Base64Url` and
  rehashing reproduces the exact `Fact-Set-SHA256`/`Evidence-Set-SHA256`/
  original `Eligibility.CanonicalJson` bytes; a failing-category Scorecard
  render (`NOT ELIGIBLE`, `FAIL`, correct `Failure-Code`/
  `Failure-Message-Base64Url`); rejection of a `SealedRun`/`Eligibility`
  pair from two different runs; the new JCS-base64url transport's
  malformed-input rejection and its distinctness from the Failure-Message
  transport; and the `ConvertTo-TPMJcsV1` `PSCustomObject` round-trip
  itself, including the empty-object edge case. 119/119 on pwsh 7.6.3 and
  119/119 on Windows PowerShell 5.1.26100.8875.
- ADR155-Q003/Q004: `Invoke-Pester -Path .\Tests` passed 899/899 on pwsh
  7.6.3 and 894/899 on Windows PowerShell 5.1, with exactly the same five
  unchanged issue #148 Repair-GamePaths failures.
- ADR155-Q005/Q006/Q007: all three changed/touched files had zero
  non-ASCII bytes, zero parser errors, zero PSScriptAnalyzer findings, and
  zero InjectionHunter findings.

All five canonical reports (ADR155-0304) now exist as pure, deterministic,
side-effect-free builders. No harness wiring, file I/O, staging, or
publication. Remaining Phase 3 work: the manifest and commit-marker
builders (ADR155-0305), staging/publication (ADR155-0306), the sole
final-outcome composition already substantially covered by the
dispatcher's `IssueFinalOutcome` (ADR155-0307), NOT-CERTIFIED bundle
publication (ADR155-0308), and the atomic cutover (ADR155-0309).
