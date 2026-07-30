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
- [x] ADR155-0305 -- Build the exact manifest and commit marker with canonical
  identities, byte lengths, SHA-256 hashes, and run correlation.
- [x] ADR155-0306 -- Stage the complete seven-file bundle and expose authority
  only after the marker is durably validated; never overwrite a destination.
- [x] ADR155-0307 -- Compose the sole final outcome from issued eligibility and
  issued publication outcomes; console, reports, result, and exit code agree.
- [x] ADR155-0308 -- Publish authoritative NOT CERTIFIED bundles for ineligible
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

## Phase 3 delta review correction -- 2026-07-20

Independent review of commit `0b43384` returned CHANGES REQUIRED with one
P2 finding, corrected in this commit:

**P2 (confirmed by direct reproduction before fixing):** both Markdown
builders interpolated `RunIdentity`, SHA-256 fields, and
`FailureReasons[].Code` directly after checking only compiled type and
field presence -- never their format. Since a same-compiled-type object
is reachable via reflection (exactly as this suite's own provenance-
rejection tests already construct), a malformed `RunIdentity` containing
an embedded newline and fake heading text was demonstrated to inject
arbitrary Markdown structure into `New-TPMScorecardReportV1`'s output
before this fix (`Run-Identity: deadbeef` followed by a literal injected
`## INJECTED HEADING` / `Status: PASS` line pair, reproduced directly
against the built module).

- Added `Assert-TPMMarkdownRunIdentityV1` (`^[0-9a-f]{32}$`),
  `Assert-TPMMarkdownSha256V1` (`^[0-9a-f]{64}$`), and
  `Assert-TPMMarkdownFailureCodeV1` (closed-vocabulary membership) to
  Reports.psm1, and call all three before any of those fields are
  interpolated in either builder. Malformed values are rejected with
  `REPORT_INVALID`; nothing is sanitized or escaped, matching the
  instruction not to alter Markdown-structural characters into a
  different-but-still-parsed form. `EligibilityPayloadSha256` needed no
  new check -- it is always computed by the builder itself via
  `Get-TPMSha256HexV1`, never taken from parsed input.
- Added `Get-TPMFactFailureCodesV1` to Authority.psm1: the closed,
  44-code vocabulary of every code `Get-TPMFactDecisionV1` can actually
  emit (enumerated directly from its `Add-Reason` call sites, not the
  broader theoretical set Section 5's prose lists, some of which --
  `HEALTH_CHECK_MISSING`, `HEALTH_CHECK_DUPLICATE`,
  `HEALTH_CHECK_NON_BOOLEAN` -- are rejected earlier as `SCHEMA_INVALID`
  by `Assert-TPMFactRecordV1` and can never reach a decision as a
  `FailureReasons` entry). `New-TPMScorecardReportV1`'s per-item
  `FailureReasons` (sourced only from `Get-TPMFactDecisionV1`) validates
  against this vocabulary alone; `New-TPMValidationReportV1`'s top-level
  `FailureReasons` (the ordered union of score-item and evidence reasons,
  per `Get-TPMEligibilityPayloadV1`) validates against this vocabulary
  unioned with the existing `Get-TPMEvidenceFailureCodesV1`.
- Free-text failure messages remain exclusively in
  `Failure-Message-Base64Url`, unchanged by this fix.
- Added regression tests to both builders' Describe blocks (via two new
  synthetic-object helpers, `New-SyntheticEligibilityV1` and
  `New-SyntheticSealedRunV1`, each building a complete, otherwise-valid
  eleven-item compiled object with one caller-controlled field) covering
  a newline-bearing `RunIdentity`, a malformed `FactSetSha256`/
  `EvidenceSetSha256`, and a newline-bearing or unknown failure code, for
  both `New-TPMScorecardReportV1` and `New-TPMValidationReportV1`.
- ADR155-Q001/Q002: `Tests/TPMCertification.Reports.Tests.ps1` gained 7
  more tests (41 total; 126 combined with all prior focused suites).
  126/126 on pwsh 7.6.3 and 126/126 on Windows PowerShell 5.1.26100.8875.
- ADR155-Q003/Q004: `Invoke-Pester -Path .\Tests` passed 906/906 on pwsh
  7.6.3 and 901/906 on Windows PowerShell 5.1, with exactly the same five
  unchanged issue #148 Repair-GamePaths failures.
- ADR155-Q005/Q006/Q007: all three changed files had zero non-ASCII
  bytes, zero parser errors, zero PSScriptAnalyzer findings, and zero
  InjectionHunter findings.

No architectural or behavioral change beyond this one finding. No
manifest/marker, staging, publication, or harness wiring began.

## Phase 3 manifest and commit-marker report builders -- 2026-07-20

Completes ADR155-0305: the last two of the seven canonical publication
artifacts, both pure builders with no file I/O, staging, or harness wiring.

- Adds `New-TPMManifestReportV1` (`TPM-Certification-Manifest.json`,
  Section 8) to Reports.psm1. Takes the issued `TPMEligibilitySnapshotV1`
  and all five already-built report objects (Eligibility, Publication,
  Final-Outcome JSON; Scorecard, Validation Markdown), validates the
  Eligibility snapshot's compiled type and its `CanonicalJson`'s
  `RunIdentity` format, validates each report argument is in its correct
  fixed positional slot by checking `FileName` against a new
  `$script:TpmManifestArtifactsV1` constant (the fixed
  Identifier/FileName/ContentType order from Section 8), and computes
  `ArtifactSha256` per artifact plus `ArtifactSetSha256` over the
  assembled `Artifacts` array -- both from the reports' own `Bytes`, never
  from caller-supplied duplicate data. `EligibilityPayloadSha256` is
  independently recomputed from the snapshot's own `CanonicalJson` bytes,
  matching the same self-verifying pattern used throughout this module.
- Adds `New-TPMCommitMarkerReportV1` (`TPM-Certification-Commit.json`,
  Section 8) to Reports.psm1. Takes only the manifest report object,
  strict-parses its own trusted `Json`, validates the manifest's
  `RunIdentity`/`EligibilityPayloadSha256`/`ArtifactSetSha256` formats and
  `ArtifactCount`, and computes `ManifestSha256` from the manifest's own
  `Bytes` -- the marker never receives or trusts any value the manifest
  builder did not itself already validate and emit.
- Both builders reuse `Get-TPMSha256HexV1`/`ConvertTo-TPMJcsV1` from
  Authority.psm1 and the `Assert-TPMMarkdownRunIdentityV1`/
  `Assert-TPMMarkdownSha256V1` format validators added in the prior
  delta-review fix; no new validation logic was invented for formats
  already covered.
- Manually verified end-to-end (outside the builder code, via
  independently recomputed SHA-256 hashes over a full 7-artifact bundle
  from a fresh pipeline run) before formal test authoring: every
  individual report's hash matches the manifest's own per-artifact
  `Sha256` entry; the manifest's own bytes hash to the marker's
  `ManifestSha256`; the manifest's `ArtifactSetSha256` matches the
  marker's own `ArtifactSetSha256`.
- One test-authoring defect caught before committing: a "sorted top-level
  key" assertion in the new manifest-schema test used `Sort-Object`'s
  default culture-aware comparison, which disagrees with
  `ConvertTo-TPMJcsV1`'s actual `[StringComparer]::Ordinal` sort
  (`'ArtifactSetSha256'` sorts before `'Artifacts'` under ordinal
  comparison because uppercase `S` precedes lowercase `s`, opposite of
  culture-aware default order). Fixed by sorting the asserted key array
  with `[Array]::Sort($x,[StringComparer]::Ordinal)` to match the
  production code's own comparer instead of relying on the default.
- ADR155-Q001/Q002: `Tests/TPMCertification.Reports.Tests.ps1` gained 8
  more tests (49 total; 134 combined with all prior focused suites) --
  exact six-field manifest schema with fixed artifact order and correct
  per-artifact hashes, independently recomputed `ArtifactSetSha256`
  cross-check, rejection of a report passed in the wrong positional slot,
  rejection of synthetic/wrong-type/null Eligibility, rejection of a
  same-compiled-type Eligibility with a newline-bearing `RunIdentity`,
  exact eight-field marker schema with every hash/identity field
  cross-checked against the manifest's own values, and rejection of a
  manifest-shaped-but-invalid object and of null input. 134/134 on pwsh
  7.6.3 and 134/134 on Windows PowerShell 5.1.26100.8875.
- ADR155-Q003/Q004: `Invoke-Pester -Path .\Tests` passed 913/913 on pwsh
  7.6.3 and 908/913 on Windows PowerShell 5.1, with exactly the same five
  unchanged issue #148 Repair-GamePaths failures.
- ADR155-Q005/Q006/Q007: both changed files (`scripts/TPMCertification.Reports.psm1`,
  `Tests/TPMCertification.Reports.Tests.ps1`) had zero non-ASCII bytes,
  zero parser errors, zero PSScriptAnalyzer findings (repository settings),
  and zero InjectionHunter findings. `scripts/TPMCertification.Authority.psm1`
  was not touched this checkpoint.

ADR155-0305 is now checked: the exact seven-file canonical publication
bundle (five reports plus manifest plus commit marker) exists in full as
pure, deterministic, side-effect-free builders. No staging, publication,
atomic cutover, filesystem writes, or harness wiring began. Remaining
Phase 3 work: staging/publication (ADR155-0306), the sole final-outcome
composition already substantially covered by the dispatcher's
`IssueFinalOutcome` (ADR155-0307), NOT-CERTIFIED bundle publication
(ADR155-0308), and the atomic cutover (ADR155-0309).

## Phase 3 publication staging (ADR155-0306, partial) -- 2026-07-20

Adds `scripts/TPMCertification.Publication.psm1`: `New-TPMPublicationStagingV1`,
the first filesystem-writing function in Phase 3. Deliberately scoped to
deterministic staging only, per instruction: no promotion to a final
destination, no durable-validation read-back, no `Committed=true`
transition, and no wiring into the dispatcher's
`RegisterCommittedPublication`/`RegisterPublicationFailure` phase machine.
The result object's `Committed` field is hardcoded `$false` in every
outcome to make that boundary explicit and unambiguous to any future
caller.

- Takes the five report objects plus the already-built Manifest and
  Marker (from ADR155-0305) and an absolute `StagingParentRoot`. Before
  any filesystem action, it cross-validates the bundle purely from data
  the prior builders already vouched for: re-parses Manifest.Json and
  Marker.Json, confirms `Manifest.RunIdentity == Marker.RunIdentity` and
  `Marker.ManifestSha256` matches the actual `Manifest.Bytes` hash, then
  walks the Manifest's own `Artifacts` array and requires each supplied
  report argument's `FileName` and SHA-256 (recomputed from its own
  `Bytes`, never trusted from the caller) match what the Manifest already
  recorded for that identifier. A caller passing a report in the wrong
  parameter slot, or a Manifest/Marker pair from two different runs, is
  rejected with `PUBLISH_INVALID` before any directory or file is
  touched -- confirmed by a test that asserts zero files exist under
  `StagingParentRoot` after such a rejection.
- Deterministic, atomic construction: the staging directory is
  `StagingParentRoot\<RunIdentity>`, resolved through the existing
  `Resolve-TPMContainedPathV1` (component-based containment, reparse
  rejection) rather than any new path logic. The same RunIdentity always
  resolves to the same location, so a second staging attempt for an
  already-fully-staged run deterministically collides on the first file
  write rather than silently landing somewhere else.
- Per-file, never-overwrite semantics matching Section 10's "leaf must
  not exist" rule: each of the seven files is written with
  `IO.FileStream` opened `FileMode.CreateNew` (the same idiom already
  used by `Write-TPMShadowDiagnosticV1` in Shadow.psm1), which throws if
  that exact file already exists; nothing is ever truncated or replaced.
  The staging directory itself is created if absent but may also be
  reused if already present (e.g. a retry after a prior run's clean
  rollback) -- reuse is safe specifically because the per-file check
  still fails closed on any actual collision.
- Rollback: files written during a failed staging attempt are tracked in
  an owned-paths list and deleted only from that list, never by
  directory-wide cleanup, so a colliding pre-existing file that this call
  did not create is never touched even when it caused the failure. The
  freshly created staging directory is removed only if this call created
  it and it is empty afterward; a reused (already-existing) directory is
  never removed. Failure codes follow the ADR-Section-9 vocabulary
  (`STAGING_FAILED` for directory-level problems including reparse-point
  rejection, `PROMOTION_FAILED` for a report-file collision or write
  exception, `MARKER_WRITE_FAILED` specifically when the failing artifact
  is the marker, `ROLLBACK_FAILED` if cleanup itself throws).
- Exports `Assert-TPMMarkdownRunIdentityV1`/`Assert-TPMMarkdownSha256V1`
  from Reports.psm1 (previously private, added during the ADR155-0304
  Markdown-injection fix) so the new module reuses the existing format
  validators instead of duplicating the regexes.
- Manually verified end-to-end before writing formal tests: happy-path
  staging of a full 7-artifact bundle with on-disk bytes hash-matched
  against the source report bytes; re-staging the same run rejected with
  the original files unmodified; a deliberately pre-placed colliding file
  at the third artifact position caused the first two already-written
  files to be rolled back while the pre-existing collider remained
  untouched.
- ADR155-Q001/Q002: `Tests/TPMCertification.Publication.Tests.ps1` (11
  tests: exact seven-file output with on-disk byte-hash verification
  against every source report; deterministic RunIdentity-named staging
  path; re-staging the same run fails closed with originals untouched;
  rollback removes only the files this call wrote when a mid-bundle
  write collides, leaving the pre-existing collider intact; rollback of
  a freshly created empty directory on a first-file collision; rejection
  of a staging directory that is a pre-existing reparse point -- skipped
  automatically on both engines in this sandbox since creating a
  symbolic link requires elevated privileges here; relative/null/empty
  `StagingParentRoot` rejection; Manifest/Marker shape and null
  rejection; cross-run Marker/Manifest correlation rejection; mismatched
  report-argument rejection; and confirmation that pre-flight rejection
  performs zero filesystem writes) passed 11/11 on pwsh 7.6.3 and 10/11
  (1 skipped for the reason above) on Windows PowerShell 5.1.26100.8875.
  Combined with `Tests/TPMCertification.Reports.Tests.ps1` (unchanged
  behavior, re-run to confirm the new Reports.psm1 exports introduced no
  regression): 59/59 on pwsh, 58/59 (1 skipped) on Windows PowerShell 5.1.
- ADR155-Q003/Q004: `Invoke-Pester -Path .\Tests` passed 924/924 on pwsh
  7.6.3 and 918/924 (5 unchanged issue #148 Repair-GamePaths failures, 1
  skipped) on Windows PowerShell 5.1.
- ADR155-Q005/Q006/Q007: all three changed/new files
  (`scripts/TPMCertification.Reports.psm1`,
  `scripts/TPMCertification.Publication.psm1`,
  `Tests/TPMCertification.Publication.Tests.ps1`) had zero non-ASCII
  bytes, zero parser errors, zero PSScriptAnalyzer findings (repository
  settings), and zero InjectionHunter findings.

ADR155-0306 remains unchecked and is explicitly partial: this checkpoint
delivers deterministic staging and rollback only. Still outstanding for
ADR155-0306: durable post-write validation (reading the staged bundle
back and re-verifying it against the Manifest/Marker before treating it
as authoritative), promotion from the private staging directory to a
final destination, and the sole `Committed` transition described in
Section 9. No publication-state transition beyond staging was wired into
the dispatcher; `RegisterCommittedPublication`/`RegisterPublicationFailure`
are unchanged and still take only the publisher's raw observations as
before this commit. No atomic cutover (ADR155-0309) began.

## Phase 3 delta review correction -- 2026-07-20

Independent review of commit `9a1da1f` returned CHANGES REQUIRED with one
blocking P2 finding, corrected in this commit:

**P2 (confirmed by direct reproduction before fixing):**
`New-TPMPublicationStagingV1` validated `Manifest.Json`/`Marker.Json` (the
RunIdentity, ArtifactSetSha256, and cross-correlation checks all read
parsed JSON) but staged `Manifest.Bytes`/`Marker.Bytes` directly without
ever proving those byte arrays were the exact BOM-less UTF-8 encoding of
the JSON that had just been validated. A proof-of-concept confirmed the
gap directly: a real, valid Manifest/Marker pair produced by the actual
builder pipeline, with `Manifest.Bytes` swapped for an unrelated string
and a `Marker.Json`/`Bytes` pair rebuilt to match that divergent hash
(exactly what `New-TPMCommitMarkerReportV1` would do if handed the
tampered object, since it only trusts `Manifest.Bytes` for hashing) was
accepted by pre-flight validation and staged to disk verbatim -- the
on-disk `TPM-Certification-Manifest.json` file contained the tampered
string, not the JSON that had passed every logical check.

- Added, immediately after `Manifest.Json`/`Marker.Json` parse (before
  any other field validation): compute
  `Get-TPMSha256HexV1 -Bytes (UTF8Encoding($false).GetBytes(Manifest.Json))`
  and require it match `Get-TPMSha256HexV1 -Bytes $Manifest.Bytes`
  exactly; same for Marker. Mismatch throws `PUBLISH_INVALID: Manifest.Bytes
  is not the exact BOM-less UTF-8 encoding of Manifest.Json` (and the
  Marker equivalent) before any directory or file is touched. No bytes
  are normalized, repaired, or replaced -- a mismatch is rejected outright,
  never silently corrected to the "intended" value.
  `$manifestHash` (already computed for the existing
  `Marker.ManifestSha256` correlation check) is now reused for this new
  check rather than recomputed, so the same SHA-256 of `Manifest.Bytes`
  backs both invariants.
- Added 6 regression tests to
  `Tests/TPMCertification.Publication.Tests.ps1`, each asserting both the
  specific `PUBLISH_INVALID` rejection and zero filesystem writes under
  `StagingParentRoot` afterward: Manifest.Bytes an unrelated divergent
  value; Marker.Bytes an unrelated divergent value; Manifest.Bytes a
  UTF-8-BOM-prefixed (`EF BB BF`) encoding of its own otherwise-correct
  Json; Manifest.Bytes its own correctly encoded Json plus one trailing
  byte; and the same BOM-prefixed and trailing-byte variants for
  Marker.Bytes.
- ADR155-Q001/Q002: `Tests/TPMCertification.Publication.Tests.ps1` gained
  6 tests (17 total). 17/17 on pwsh 7.6.3 and 16/17 (1 skipped, unchanged
  reason: symbolic-link creation for the reparse-point test requires
  elevated privileges in this sandbox) on Windows PowerShell
  5.1.26100.8875.
- ADR155-Q003/Q004: `Invoke-Pester -Path .\Tests` passed 930/930 on pwsh
  7.6.3 and 924/930 on Windows PowerShell 5.1 (same five unchanged issue
  #148 Repair-GamePaths failures, 1 skipped).
- ADR155-Q005/Q006/Q007: both changed files
  (`scripts/TPMCertification.Publication.psm1`,
  `Tests/TPMCertification.Publication.Tests.ps1`) had zero non-ASCII
  bytes, zero parser errors, zero PSScriptAnalyzer findings, and zero
  InjectionHunter findings.

No architectural or behavioral change beyond this one finding. No durable
read-back, promotion, dispatcher transitions, or atomic cutover began;
ADR155-0306 remains partial for the same reasons as above.

## Phase 3 publication commit: promotion and durable validation (ADR155-0306, complete) -- 2026-07-20

Completes ADR155-0306. Adds `New-TPMPublicationCommitV1` to
`scripts/TPMCertification.Publication.psm1`, alongside (not in place of)
the already-approved `New-TPMPublicationStagingV1`, which it calls
internally and does not modify. Still no wiring into the dispatcher's
`RegisterCommittedPublication`/`RegisterPublicationFailure`, and no
atomic cutover -- per instruction, this checkpoint is the last of
ADR155-0306's own scope, not ADR155-0309.

- Validates `DestinationRoot` (absolute, non-empty) before calling
  `New-TPMPublicationStagingV1`; a staging failure is propagated verbatim
  (`Committed=$false`, staging's own `FailureCode`/`FailureMessage`) with
  no promotion attempt and no destination directory created.
- Promotion: a deterministic `DestinationRoot\<RunIdentity>` directory
  (same RunIdentity-per-run scheme as staging, same
  create-or-reuse-with-reparse-rejection care, intentionally duplicated
  rather than extracted into a shared helper so the already-reviewed
  `New-TPMPublicationStagingV1` internals stay untouched). Each of the
  seven staged files is moved via `IO.File.Move` in the manifest's fixed
  order (five reports, manifest, marker); a pre-existence check on the
  destination path enforces "never overwrite a destination" per-file,
  matching the same idiom already used for staging's own
  `FileMode.CreateNew` writes.
- Durable validation: after all seven files are promoted, each is
  re-read from its destination path and its SHA-256 recomputed and
  compared against the hash the Manifest already recorded for it (the
  five reports against `Manifest.Artifacts[i].Sha256`; the Manifest and
  Marker themselves against the hashes already computed during staging's
  pre-flight). A mismatch fails closed with `DURABLE_VALIDATION_FAILED`
  and is rolled back like any other promotion failure. Because staging's
  own pre-flight already guarantees every staged artifact's bytes match
  what the Manifest recorded for it, and `IO.File.Move` is a rename that
  cannot alter file contents, this branch is unreachable through the
  public API's own trust chain under normal operation -- it exists as
  defense-in-depth against out-of-band corruption (e.g. antivirus
  quarantine-and-replace, disk-level corruption) between promotion and
  read-back, and is exercised by code review rather than a runtime test;
  the same is true of the `ROLLBACK_FAILED` code, which requires a
  genuine filesystem-level failure (a locked handle, a permissions
  change mid-operation) to trigger and was judged not worth a fragile,
  potentially environment-dependent lock-contention test.
- Rollback (promotion or durable-validation failure): every file this
  call itself promoted is moved back from the destination to its
  original staging path -- never deleted outright -- so a failed commit
  leaves the staging directory exactly as staging originally produced it
  and nothing is lost; only files this call actually moved are touched,
  matching the same "removes only files owned by this run" guarantee
  already established for staging. The destination directory is removed
  only if this call created it and it ends up empty.
- The sole `Committed` transition: `Committed` starts `$false` and is
  set to `$true` only once, after every file has promoted and durably
  validated successfully; nothing after that point can change it back
  (post-commit cleanup failure only appends a diagnostic warning). On
  success the result also carries `ManifestSha256` and `ArtifactSetSha256`
  (independently recomputed/read from the already-validated Manifest,
  not re-derived from caller input) plus `DiagnosticWarnings` -- exactly
  the three fields `Assert-TPMPublicationObservationV1` in
  `TPMCertification.Production.psm1` already expects for a future
  `RegisterCommittedPublication` call, confirmed by a test asserting the
  returned values satisfy that function's own format regexes and
  closed-vocabulary warning check. This shape match is deliberate reuse
  of an already-defined contract, not new wiring: `RegisterCommittedPublication`
  is not called anywhere in this module or its tests.
- Post-commit cleanup: once `Committed=true`, the (now-empty, since every
  file was moved out) private staging directory is removed; failure adds
  `POST_COMMIT_CLEANUP_FAILED` to `DiagnosticWarnings` without changing
  `Committed`, matching Section 9 exactly.
- Manually verified end-to-end before writing formal tests: full 7-file
  commit with post-write on-disk hash verification against every source
  report, confirmed `ManifestSha256`/`ArtifactSetSha256` match the
  Manifest's own recorded values, confirmed staging-directory cleanup,
  and confirmed re-committing the same run fails closed with the
  original destination untouched and the second attempt's own staged
  files rolled back to its own staging directory.
- ADR155-Q001/Q002: `Tests/TPMCertification.Publication.Tests.ps1` gained
  6 tests (23 total): full commit with per-file on-disk hash
  verification and `ManifestSha256`/`ArtifactSetSha256`/`DiagnosticWarnings`
  correctness; the returned shape satisfying
  `Assert-TPMPublicationObservationV1`'s own format rules; re-committing
  the same run rejected with the original destination untouched and the
  second attempt's files rolled back to its own staging directory;
  staging-failure propagation with zero destination writes; a
  mid-promotion collision rolling the already-promoted files back to
  staging rather than leaving a partially promoted destination; and
  relative/null/empty `DestinationRoot` rejection. 23/23 on pwsh 7.6.3
  and 22/23 (1 skipped, unchanged reason: symbolic-link creation for the
  staging-side reparse-point test requires elevated privileges in this
  sandbox) on Windows PowerShell 5.1.26100.8875.
- ADR155-Q003/Q004: `Invoke-Pester -Path .\Tests` passed 936/936 on pwsh
  7.6.3 and 930/936 on Windows PowerShell 5.1 (same five unchanged issue
  #148 Repair-GamePaths failures, 1 skipped).
- ADR155-Q005/Q006/Q007: both changed files
  (`scripts/TPMCertification.Publication.psm1`,
  `Tests/TPMCertification.Publication.Tests.ps1`) had zero non-ASCII
  bytes, zero parser errors, zero PSScriptAnalyzer findings, and zero
  InjectionHunter findings.

ADR155-0306 is now fully checked. `RegisterCommittedPublication`,
`RegisterPublicationFailure`, and the rest of the dispatcher's phase
machine are unchanged and still take only raw publisher observations as
before -- no dispatcher wiring, and no atomic cutover, began. Remaining
Phase 3 work: the sole final-outcome composition already substantially
covered by the dispatcher's `IssueFinalOutcome` (ADR155-0307),
NOT-CERTIFIED bundle publication (ADR155-0308), and the atomic cutover
that removes every legacy decision assignment and competing publisher
(ADR155-0309).

## Phase 3 sole final-outcome composition projection (ADR155-0307) -- 2026-07-20

Completes ADR155-0307. The certification decision itself was already
composed exactly once, by the dispatcher's own `IssueFinalOutcome`
operation in `scripts/TPMCertification.Production.psm1`
(`$certified=[bool]$state.EligibleForCertification-and[bool]$state.PublicationCommitted`,
tested since the Phase 3 production-dispatcher checkpoint). What
remained per Section 9's closing sentence -- "Console, process return,
and every in-memory status project this one final object" -- was a
single, pure, reusable projection of that already-decided outcome into
what a console message, process exit code, and in-memory result would
need, so that harness wiring (ADR155-0309, not begun here) has exactly
one function to call rather than an occasion to re-derive the
CERTIFIED/NOT CERTIFIED decision a second time from raw booleans.

- Adds `New-TPMFinalOutcomeProjectionV1` to
  `scripts/TPMCertification.Reports.psm1`. It calls the already-approved
  `New-TPMFinalOutcomeReportV1` internally (unmodified) and derives its
  output from that report's own validated JSON, rather than re-parsing
  `FinalOutcome.CanonicalJson` a second time independently -- there is
  exactly one place in this codebase (`New-TPMFinalOutcomeReportV1`)
  that validates and shapes the final-outcome fields, and this function
  reuses it rather than duplicating the check. Wrong-compiled-type and
  null-input rejection are inherited from that call, confirmed by test.
- Returns `{RunIdentity, FinalStatus, ExitCode, ConsoleMessage}`.
  `ConsoleMessage` is a fixed-format string built only from
  `RunIdentity` (re-validated via the existing
  `Assert-TPMMarkdownRunIdentityV1`), the closed two-value `FinalStatus`
  vocabulary (`CERTIFIED`/`NOT CERTIFIED`, explicitly checked), and
  `ExitCode` (checked to be exactly 0 or 1) -- no free-text field (e.g.
  `FailureReasons[].Message`) is interpolated into it, so there is no
  Markdown-injection-class surface to defend against here the way the
  Scorecard/Validation builders needed to; the full `FailureReasons`
  detail remains available only in the already-built
  `TPM-Certification-Final-Outcome.json`/eligibility artifacts for
  anyone consuming the detail, deliberately keeping this projection
  minimal.
- Adds one defense-in-depth consistency check not present in
  `New-TPMFinalOutcomeReportV1`: `FinalStatus` and `ExitCode` must agree
  (`CERTIFIED` iff `ExitCode=0`) or the projection is rejected with
  `REPORT_INVALID: FinalStatus and ExitCode disagree`. This is a
  same-object internal-consistency check, not a re-derivation of the
  certification decision from `EligibleForCertification`/
  `PublicationCommitted` -- those booleans are never read by this
  function.
- Manually verified end-to-end against three real pipeline outcomes
  (CERTIFIED; NOT CERTIFIED via publication failure; NOT CERTIFIED via
  score ineligibility) before writing formal tests, and against a
  reflectively constructed same-compiled-type object with
  `FinalStatus="CERTIFIED"`/`ExitCode=1` to confirm the consistency
  check rejects it.
- ADR155-Q001/Q002: `Tests/TPMCertification.Reports.Tests.ps1` gained 7
  tests (55 total): CERTIFIED projection with exact `ConsoleMessage`
  text; NOT CERTIFIED (publication-failed) and NOT CERTIFIED
  (score-ineligible) projections; confirmation the projection's three
  scalar fields match `New-TPMFinalOutcomeReportV1`'s own output rather
  than being independently derived; wrong-type/null rejection;
  FinalStatus/ExitCode disagreement rejection; and out-of-vocabulary
  FinalStatus/ExitCode rejection. 55/55 on pwsh 7.6.3 and 55/55 on
  Windows PowerShell 5.1.26100.8875.
- ADR155-Q003/Q004: `Invoke-Pester -Path .\Tests` passed 943/943 on pwsh
  7.6.3 and 937/943 on Windows PowerShell 5.1, with exactly the same
  five unchanged issue #148 Repair-GamePaths failures (1 unrelated
  skipped test, unchanged reason, from the Publication suite).
- ADR155-Q005/Q006/Q007: both changed files had zero non-ASCII bytes,
  zero parser errors, zero PSScriptAnalyzer findings, and zero
  InjectionHunter findings.

ADR155-0307 is now checked. This is a pure, side-effect-free function --
no `Write-Host`, no file I/O, no process-exit-code call, and no harness
wiring. `TeknoParrot-Manager.ps1` is untouched by this commit. Remaining
Phase 3 work: NOT-CERTIFIED bundle publication (ADR155-0308) and the
atomic cutover that removes every legacy decision assignment and
competing publisher (ADR155-0309).

## Phase 3 authoritative NOT CERTIFIED bundle publication (ADR155-0308) -- 2026-07-20

Completes ADR155-0308. No new production code path was needed: since
`IssuePublicationCandidate` (Production.psm1) was never gated on
`EligibleForCertification`, and none of the report/manifest/marker/
staging/commit builders reference `EligibleForCertification` or
`FinalStatus` as anything other than data to project, the single
existing publication path already staged and committed a NOT CERTIFIED
run's bundle exactly the same way as a CERTIFIED one -- confirmed by
grep across `Reports.psm1`/`Publication.psm1` before writing any code,
per instruction to avoid introducing an alternate path. This checkpoint
is therefore proof, not new construction.

- Added `Describe 'ADR-0155 Phase 3 authoritative NOT CERTIFIED bundle
  publication'` to `Tests/TPMCertification.Publication.Tests.ps1`,
  extending the existing `New-FullPipelineRunV1`/`New-FullBundleV1`
  helpers with the same `ForcePesterFailure` parameter already used
  elsewhere in this suite family, so a score-ineligible run can be
  driven through the complete pipeline (facts through commit) for the
  first time in this test file.
- **Defect found and fixed by this checkpoint's own new tests, not a
  pre-existing known issue:** `New-TPMValidationReportV1`'s top-level
  failure-code vocabulary check built
  `$allowedFailureCodes=@(Get-TPMFactFailureCodesV1)+@(Get-TPMEvidenceFailureCodesV1)`.
  Both `Get-*FailureCodesV1` accessors already return their array as one
  object via the established `return ,@(...)` idiom (documented from an
  earlier round of this same PR); wrapping each call in an *additional*
  `@()` re-wrapped that single array object into a one-element array
  containing it, so concatenation produced a 2-element array of arrays
  (63 codes hidden two levels deep) instead of a flat 63-element array
  of code strings. Confirmed by direct reproduction
  (`(@(Get-TPMFactFailureCodesV1)+@(Get-TPMEvidenceFailureCodesV1))
  -contains 'PESTER_FAILURES'` returned `False`) before fixing. This is
  the third occurrence of the exact double-array-wrap defect class this
  repository has hit before (see `LESSONS_LEARNED.md`'s PowerShell
  `return @()` gotcha). Every prior test of this vocabulary used either
  a single-array call site (`New-TPMScorecardReportV1`'s per-item check,
  never wrapped, never buggy) or a synthetic/reflectively constructed
  object crafted specifically to be *rejected* -- so nothing before this
  checkpoint's own new end-to-end test (which is the first to drive a
  real, non-synthetic `PESTER_FAILURES` code through the top-level
  Validation path) exercised the false-negative direction of this check.
  Fixed by removing the redundant `@()` wrapping:
  `$allowedFailureCodes=(Get-TPMFactFailureCodesV1)+(Get-TPMEvidenceFailureCodesV1)`.
  Re-verified directly: the corrected expression is a flat 63-element
  `[string]` array containing both `PESTER_FAILURES` and a representative
  evidence code. Without this fix, any real ineligible run with an actual
  failure reason would have thrown `REPORT_INVALID: unrecognized failure
  code ...` out of the Validation builder, which would have blocked
  exactly the NOT CERTIFIED publication this checkpoint requires --
  ADR155-0308 could not have been completed without this fix.
- Regression coverage added (4 tests): a score-ineligible run's full
  bundle stages and commits successfully (`Committed=true`) through the
  same `New-TPMPublicationStagingV1`/`New-TPMPublicationCommitV1` path
  used for eligible runs, producing all seven files; the committed
  Final-Outcome artifact on disk and the `New-TPMFinalOutcomeProjectionV1`
  projection both independently read `FinalStatus='NOT CERTIFIED'`/
  `ExitCode=1` even though `Committed=true` -- the specific non-conflation
  the checklist item names; the committed Scorecard shows `Eligibility:
  NOT ELIGIBLE`, a `Status: FAIL` category line, and the `PESTER_FAILURES`
  Failure-Code (this is the test that caught the defect above); and the
  commit result's field set and hash-format guarantees
  (`ManifestSha256`/`ArtifactSetSha256` format) are identical between an
  eligible and an ineligible run's commit, confirming there is exactly
  one schema and one code path, not two.
- ADR155-Q001/Q002: `Tests/TPMCertification.Publication.Tests.ps1` gained
  4 more tests (27 total). Combined with `Tests/TPMCertification.Reports.Tests.ps1`
  (unchanged behavior, re-run to confirm the one-line fix introduced no
  regression): 82/82 on pwsh 7.6.3 and 81/82 (1 skipped, unchanged
  reason) on Windows PowerShell 5.1.26100.8875.
- ADR155-Q003/Q004: `Invoke-Pester -Path .\Tests` passed 947/947 on pwsh
  7.6.3 and 941/947 on Windows PowerShell 5.1, with exactly the same
  five unchanged issue #148 Repair-GamePaths failures (1 unrelated
  skipped test).
- ADR155-Q005/Q006/Q007: both changed files
  (`scripts/TPMCertification.Reports.psm1`,
  `Tests/TPMCertification.Publication.Tests.ps1`) had zero non-ASCII
  bytes, zero parser errors, zero PSScriptAnalyzer findings, and zero
  InjectionHunter findings.

ADR155-0308 is now checked. No alternate publication path was
introduced -- the fix is a one-line correction inside the already-approved
`New-TPMValidationReportV1`, and no certification-decision logic changed
anywhere. Remaining Phase 3 work: the atomic cutover that removes every
legacy decision assignment and competing publisher (ADR155-0309), which
is now the only unchecked ADR155-030x item.

## Phase 3 ADR155-0309 prerequisite: Section 8.3 final-outcome candidate report builder -- 2026-07-21

Commit `c0dc793` resolves a staging/publication ordering circularity found
while starting ADR155-0309 harness wiring: `New-TPMFinalOutcomeReportV1`
(Section 9) strictly requires a genuine dispatcher-issued
`TPMFinalOutcomeV1`, which can only exist after `RegisterCommittedPublication`
-- but `RegisterCommittedPublication` needs real manifest hashes, and the
manifest needs a `FinalOutcomeJson` artifact. Independently reviewed in an
isolated worktree and returned APPROVED before this checklist entry was
added (this checklist file itself was not touched by that commit).

- Adds `New-TPMFinalOutcomeCandidateReportV1` to
  `scripts/TPMCertification.Reports.psm1`: builds the Section 8.3
  candidate schema (`EligibilityStatus`/`RequiredPublicationState`, no
  `FailureReasons` -- distinct from Section 9's
  `EligibleForCertification`/`PublicationCommitted`/`FailureReasons`)
  directly from an issued `TPMEligibilitySnapshotV1`, available
  immediately after `IssueEligibility`, before any publication attempt.
  `New-TPMFinalOutcomeReportV1` and `New-TPMFinalOutcomeProjectionV1` are
  unchanged -- same strict type check, same runtime authority; a
  regression test proves the candidate's own output object is rejected
  by both.
- ADR155-Q001/Q002: `Tests/TPMCertification.Reports.Tests.ps1` gained 8
  tests (63 total). 63/63 on pwsh 7.6.3 and 63/63 on Windows PowerShell
  5.1.
- ADR155-Q003/Q004: `Invoke-Pester -Path .\Tests` passed 955/955 on pwsh
  7.6.3. Windows PowerShell 5.1: 949 passed, 5 failed, 1 skipped = 955
  total, with the same five unchanged issue #148 failures and the same
  pre-existing skip.
- ADR155-Q005/Q006/Q007: both changed files had zero non-ASCII bytes,
  zero parser errors, zero PSScriptAnalyzer findings, and zero
  InjectionHunter findings.

Broader harness wiring (staging, manifest construction, publication,
final-outcome issuance) remained paused pending this review.

## Phase 3 ADR155-0309 Sub-step A: production certification cycle orchestration -- 2026-07-21

Wires the approved authority, builders, publication commit, and
projection into a single, tested orchestration path -- proving the
circularity fix from the prerequisite above actually closes end to end
with real values, not the placeholder `ManifestSha256`/`ArtifactSetSha256`
every dispatcher/publication test before this commit had to use. This is
the orchestration primitive that broader harness wiring will call; it
does not yet touch `Invoke-TPM-RealInstanceSmoke.ps1` or remove any
legacy decision/publish code (that remains for a later, separately
reviewed sub-step).

**Safety invariant** (documented in the function's own header comment,
repeated here per instruction): the Section 8.3 candidate and the
Section 9 dispatcher-issued `TPMFinalOutcomeV1` can diverge only when
`EligibleForCertification=true` and publication does not commit. In
every other case their `FinalStatus`/`ExitCode` agree -- the candidate's
eligibility-only derivation and the dispatcher's
`EligibleForCertification AND PublicationCommitted` derivation reduce to
the same value whenever `EligibleForCertification` is false, and
coincide by definition once `PublicationCommitted` is true. In the one
divergent case, the bundle is never durably committed -- no valid commit
marker exists at the destination -- so per Section 8.2/8.3 the
candidate-bearing bundle is non-authoritative and must be ignored by any
consumer.

- Adds `scripts/TPMCertification.ProductionCycle.psm1`:
  `Complete-TPMProductionCertificationCycleV1`, implementing the required
  seven-step sequence exactly: (1) issue eligibility through the
  workflow authority; (2) build the Section 8.3 candidate final-outcome
  report from that eligibility; (3) use the candidate only while
  constructing and staging the five-artifact bundle and manifest; (4)
  attempt publication (`New-TPMPublicationCommitV1`) and register the
  real observation (`RegisterCommittedPublication` on success,
  `RegisterPublicationFailure` on failure) -- `ManifestSha256`/
  `ArtifactSetSha256` come from the actual commit result, never a
  placeholder; (5) issue the genuine `TPMFinalOutcomeV1` only after the
  dispatcher has issued `TPMPublicationOutcomeV1` -- enforced by the
  dispatcher's own phase machine, not re-implemented here; (6) derive the
  runtime projection (`New-TPMFinalOutcomeProjectionV1`) only from that
  genuine object; (7) publication failure can never leave an
  authoritative bundle or marker (guaranteed by `New-TPMPublicationCommitV1`'s
  existing rollback, proven again through this orchestration) and can
  never produce CERTIFIED (guaranteed by the dispatcher's own
  `EligibleForCertification AND PublicationCommitted` composition).
- No new production code path for construction/staging/publication/
  projection itself -- this function only sequences calls to
  already-approved primitives from `Authority.psm1` (via the injected
  dispatcher closure), `Reports.psm1`, and `Publication.psm1`.
- **Defect found and fixed by this checkpoint's own integration testing,
  not a pre-existing known issue:** `Assert-TPMPublicationFailureReasonsV1`
  in `scripts/TPMCertification.Production.psm1` used `return $reasons`
  instead of `return ,$reasons`. When `RegisterPublicationFailure` is
  given exactly one failure reason -- the common case, and exactly what
  this orchestration produces on a single publish failure -- PowerShell's
  return statement unrolled the one-element array into a bare scalar on
  the pipeline, so `TPMPublicationOutcomeV1.FailureReasons` serialized as
  a bare JSON object instead of a one-element JSON array, violating
  Section 9's array schema. `IssueFinalOutcome`'s own `FailureReasons`
  aggregation was unaffected (it already used the safe `.ToArray()`/`@()`
  pattern), which is exactly why no prior test caught this -- every
  existing test asserted against the derived `TPMFinalOutcomeV1.FailureReasons`,
  never directly against `TPMPublicationOutcomeV1.FailureReasons`.
  Confirmed by direct reproduction before fixing. This is the fourth
  occurrence of the exact `return @()`-without-comma defect class this
  repository has hit before. Fixed with the one-character correction
  (`return ,$reasons`); added a direct regression test asserting the
  `TPMPublicationOutcomeV1.FailureReasons` JSON is a genuine array (not
  just checking `.Code`/`.Message`, which would not have caught this).
- Regression coverage added (`Tests/TPMCertification.ProductionCycle.Tests.ps1`,
  6 tests) proving both explicitly required watch items plus general
  correctness: a genuine CERTIFIED run end to end with real (non-placeholder)
  `ManifestSha256`/`ArtifactSetSha256` driving `RegisterCommittedPublication`;
  a genuine NOT CERTIFIED (score-ineligible) run that still publishes the
  complete seven-file committed bundle; **watch item 1** -- the candidate
  participates in manifest construction (its bytes are exactly what the
  manifest records for the `FinalOutcomeJson` slot) but is structurally
  rejected by both `New-TPMFinalOutcomeReportV1` and
  `New-TPMFinalOutcomeProjectionV1`, and the runtime projection is proven
  to come only from the genuine dispatcher-issued object; **watch item 2**
  -- an eligible run whose publication fails (mid-promotion collision)
  produces `Committed=false`, a `PublicationOutcome` with null hashes and
  a non-empty `FailureReasons` array, `PublicationCommitted:false` on the
  genuine `FinalOutcome`, `FinalStatus='NOT CERTIFIED'`/`ExitCode=1` from
  the projection, and no commit marker or extra file at the destination
  beyond the pre-existing collider; rollback leaves the failed attempt's
  files in its own staging directory rather than partially promoted; and
  the on-disk committed `Final-Outcome.json` matches the Section 8.3
  schema and agrees with the runtime projection when publication commits.
- ADR155-Q001/Q002: `Tests/TPMCertification.ProductionCycle.Tests.ps1`
  (6 tests) plus one new regression test added to
  `Tests/TPMCertification.Production.Tests.ps1` for the `FailureReasons`
  array fix: 21/21 combined on pwsh 7.6.3 and 21/21 on Windows PowerShell
  5.1.26100.8875.
- ADR155-Q003/Q004: `Invoke-Pester -Path .\Tests` passed 962/962 on pwsh
  7.6.3. Windows PowerShell 5.1 showed one additional failure
  (`Tests/TpmAutoUpdate.DestructivePath.Tests.ps1`, unrelated to any file
  touched by this commit) on a run where the pwsh and Windows PowerShell
  5.1 full suites executed concurrently; re-run in isolation that file
  passed 10/10, and a clean, non-concurrent re-run of the full suite
  passed 956/962 with exactly the same five unchanged issue #148
  Repair-GamePaths failures and one unrelated pre-existing skip --
  confirmed as environmental flakiness from concurrent execution, not a
  regression.
- ADR155-Q005/Q006/Q007: all four changed/new PowerShell files
  (`scripts/TPMCertification.Production.psm1`,
  `scripts/TPMCertification.ProductionCycle.psm1`,
  `Tests/TPMCertification.Production.Tests.ps1`,
  `Tests/TPMCertification.ProductionCycle.Tests.ps1`) had zero non-ASCII
  bytes, zero parser errors, zero PSScriptAnalyzer findings, and zero
  InjectionHunter findings.

`Invoke-TPM-RealInstanceSmoke.ps1` and `TeknoParrot-Manager.ps1` are
untouched by this commit. No legacy decision assignment, arbitrary
builder, or competing publisher was removed yet -- that remains for a
separately reviewed ADR155-0309 sub-step, per the explicitly agreed
two-step sequencing (implementation and review checkpoints on this
branch only; no merge until both are approved). ADR155-0309 remains
unchecked and partial.

## Phase 3 ADR155-0309 Checkpoint B1: dedicated production fact adapter -- 2026-07-22

Replaces `New-TPMShadowFactRecordsFromLegacyV1` (Phase 2's placeholder-
tolerant, never-authoritative shadow adapter) as the production authority's
fact source with a dedicated module,
`scripts/TPMCertification.ProductionFacts.psm1`, that never imports or
calls `TPMCertification.Shadow.psm1` and never expands its public surface.
Full architecture summary: `ARCHITECTURE.md` ("ADR-0155 production fact
adapter (ADR155-0309 Checkpoint B1)").

**Iteration history (independent implementation, not the unreviewed
c0dc793..b6f54b1 reference lineage, which was consulted only as prior-art
spec material and never merged or cherry-picked):**

- **Round 1** built the module with an exported `-RelativePaths` test seam
  on the inventory function, a four-file inventory (release package only),
  an InjectionHunter identity of RuleName+Extent (no File), and a
  `Test-TPMProductionPackagePreflightV1` that recursively deleted its
  caller-supplied `PreflightScratchRoot` directly.
- **Round 2 corrections (first review pass):** removed the `-RelativePaths`
  seam from the exported entry point (moved to a private, InModuleScope-only
  `Resolve-TPMProductionPowerShellInventoryEntriesV1`); expanded the
  inventory to the full 16-entry union of release-package and ADR-0155
  production certification/harness content (`scripts/Invoke-TPM-
  RealInstanceSmoke.ps1`, `scripts/Invoke-TPM-InstallHealthCheck.ps1`,
  `scripts/Resolve-Pcsx2Directory.ps1`, `scripts/Run-TPM-Tests.ps1`, all six
  `TPMCertification.*.psm1` modules including `Shadow.psm1`'s own file
  content -- but not its exports -- and `Test-TPMParserCheckV1.ps1`, with
  `scripts/Preview-TPM-ConsoleUx.ps1` and `Tests/*` explicitly documented as
  excluded dev-only content); added File to the InjectionHunter match key and
  FindingIdentifier, with same-file duplicate-extent occurrences (a real,
  legitimate case in this repository, e.g. TeknoParrot-Manager.ps1's
  `-replace '\.(teknoparrot|parrot|game)$'` construct at two separate lines)
  resolved by ascending-Line pairing between findings and registry entries
  sharing a match key, and a genuinely duplicate raw finding identity treated
  as a scanner defect (fail closed); replaced the unsafe direct
  `Remove-Item -Recurse` on the caller's scratch root with
  `New-/Remove-TPMOwnedScratchDirectoryV1` (owns and deletes exactly one
  validated child, never the parent); added parser cross-file engine-version
  consistency checking, `Invoke-TPMExternalProcessWithTimeoutV1` preserving
  diagnostics rather than deleting them when a timed-out child's termination
  cannot be confirmed, and `Invoke-TPMBoundedScriptBlockV1` (a genuine
  wall-clock bound for the in-process PSScriptAnalyzer/InjectionHunter
  scans).
- **Defects found and fixed by this checkpoint's own integration testing,
  not pre-existing known issues:**
  1. `Start-Process -ArgumentList` does not quote array elements containing
     spaces or Win32 command-line metacharacters on this environment's
     PowerShell/Windows build -- a path like `a file (with) [odd] chars.ps1`
     arrived at the child process split into multiple separate argv tokens,
     silently corrupting it. Fixed with `ConvertTo-TPMWin32QuotedArgumentV1`,
     a CommandLineToArgvW-compatible quoting function applied to every
     argument before `Start-Process` joins them; proven with a dedicated
     regression test using a path containing both spaces and metacharacters.
  2. Windows PowerShell 5.1 does not reliably populate `.ExitCode` on a
     `Start-Process -PassThru` object unless `.Handle` is touched first --
     confirmed by direct reproduction (`$proc.ExitCode` read back `$null`
     even after a normal, non-timed-out exit, until `[void]$proc.Handle` was
     added immediately after `Start-Process` returns). See
     `LESSONS_LEARNED.md`.
  3. `DiagnosticRecord.Line`/`.Column` are ScriptProperties bound to the
     runspace that produced them, not intrinsic .NET properties -- reading
     them back after a same-process `[PowerShell]::Create()` runspace
     handoff intermittently failed (and, worse, produced sporadic unrelated
     failures reading other results depending on timing). Fixed by switching
     `Invoke-TPMBoundedScriptBlockV1` to `Start-Job` (a genuine background
     process, not a same-process runspace) and projecting to plain
     primitive-typed fields before the result crosses back. See
     `LESSONS_LEARNED.md`.
  4. The PowerShell array-subexpression operator (`@(...)`) applied directly
     to a `System.Collections.Generic.List[object]` variable threw
     "Argument types do not match" on this environment's pwsh 7.6.4 build,
     even though the identical list enumerated correctly via `.ToArray()`,
     an `[array]` cast, or piping through `ForEach-Object` -- this corrupted
     the InjectionHunter finding/registry-entry pairing logic in a way that
     was silently absorbed by the surrounding `try`/`catch` as a bare
     `Executed=$false`, not a visible error, until debugged directly. Fixed
     by never wrapping a `List[object]` directly in `@()`; added a
     dedicated `Sort-TPMByLineV1` manual-sort helper (also avoiding
     `Sort-Object` piped over a collection of Hashtables, which showed the
     same failure mode) in place of `@($list | Sort-Object Line)`. See
     `LESSONS_LEARNED.md`.
- Regression coverage: `Tests/TPMCertification.ProductionFacts.Tests.ps1`
  (51 tests) covering: the fixed 16-file inventory and its non-overridable
  production entry point; missing/duplicate/outside-root/unreadable
  inventory-entry rejection (via `InModuleScope`); parser success/failure/
  no-engine/timeout/non-zero-exit/malformed/extra/partial/mismatched-path/
  missing-field/negative-count/cross-file-version-mismatch/full-coverage
  gating, plus the space-and-metacharacter path regression; a genuine
  (non-mocked) bounded-execution timeout; PSScriptAnalyzer aggregation
  (never reusing the legacy count) and missing-settings handling; disposition
  registry accept and six rejection modes (closed schema, bad SchemaVersion,
  bad File normalization, bad Disposition, duplicate File+RuleName+Extent+
  Line, and the same-key/different-Line acceptance case); InjectionHunter
  cross-file non-collision, same-file duplicate-occurrence pairing, stale-
  entry fail-closed, missing-registry/missing-module handling; scratch-
  directory ownership (creates/owns/removes exactly one child; rejects a
  pre-existing child name and an outside-root child name; refuses to
  recursively remove a path no longer resolving inside its recorded parent
  or a reparse point standing in the owned child's place); the real
  preflight pipeline's genuine success, genuine command-failure (mocked to
  throw, not merely absent from `Get-Command`), staging failure, and
  cleanup-failure-forces-PackageValidationPassed-false cases; a self-scan
  proving the complete real 16-file inventory (not merely the newly
  authored files) is ASCII-clean, parses under both engines, and is
  analyzed by both Static Analysis gates with zero unresolved findings; and
  full 11-fact integration through the real dispatcher.
- ADR155-Q005/Q006/Q007: the four new/changed files
  (`scripts/TPMCertification.ProductionFacts.psm1`,
  `scripts/Test-TPMParserCheckV1.ps1`,
  `scripts/InjectionHunterDispositions.psd1`,
  `Tests/TPMCertification.ProductionFacts.Tests.ps1`) had zero non-ASCII
  bytes, zero parser errors, zero PSScriptAnalyzer findings, and zero
  InjectionHunter findings (against the module code itself; the complete
  16-file production inventory's own findings are the 27 real dispositioned
  entries in `scripts/InjectionHunterDispositions.psd1`, one new pre-existing
  PSScriptAnalyzer finding was newly surfaced in
  `scripts/Invoke-TPM-InstallHealthCheck.ps1` by scanning it for the first
  time -- observed and reported honestly, not fixed, as out of scope for
  this checkpoint).
- Full suite: 1013/1013 on pwsh 7.6.4; 1006/1011 on Windows PowerShell 5.1
  with exactly the five pre-existing issue #148 Repair-GamePaths failures
  and two legitimate skips (one pre-existing reparse-point skip, one new
  symlink-creation-permission skip in the scratch-ownership adversarial
  test, matching the same `Set-ItResult -Skipped` pattern already used
  elsewhere in this suite for unprivileged environments).

`TPMCertification.Production.psm1` is untouched by this checkpoint (byte-
identical to its pre-checkpoint state). No harness wiring, fact-source
swap into `Invoke-TPM-RealInstanceSmoke.ps1`, ECVF work, or hardware
certification was performed. Nothing from this checkpoint has been
committed, staged, or pushed. ADR155-0309 remains unchecked and partial.

## Phase 3 ADR155-0309 Checkpoint B1 -- round 3 corrections -- 2026-07-22

Three focused corrections after the second review pass:

1. **Fixed the genuine `PSAvoidAssignmentToAutomaticVariable` finding** the
   complete inventory surfaced in `scripts/Invoke-TPM-InstallHealthCheck.ps1`
   (line 33, `Write-HealthLog`'s `-Event` parameter collided with
   PowerShell's automatic `$Event` variable). Renamed to `-EventName`;
   every existing call site uses positional arguments, so no caller needed
   updating. Added `Tests/InstallHealthCheck.Tests.ps1` coverage (3 new
   tests: original positional call shape unchanged, `-EventName` works as a
   named parameter, `-Event` no longer exists as a parameter name) proving
   behavior is otherwise identical. `Test-TPMProductionPSScriptAnalyzerV1`
   now genuinely reports `FindingCount=0` across the real 16-file inventory
   -- confirmed by direct re-run, not assumed.
2. **Minimized the module's public surface to exactly two functions**:
   `Get-TPMProductionPowerShellInventoryV1` and
   `New-TPMProductionFactRecordsV1`. Every other function (parser/
   PSScriptAnalyzer/InjectionHunter probes, the bounded-execution and
   external-process primitives, the disposition-registry validator, and --
   the specific finding -- `New-`/`Remove-TPMOwnedScratchDirectoryV1`) is
   now unexported. The scratch-directory primitives being exported let any
   caller forge an `Owned=$true` descriptor with an arbitrary
   `ParentRoot`/`Path` and invoke a public recursive-deletion capability --
   ownership represented by a caller-constructible object is not an
   authorization boundary. All existing tests for the now-private functions
   were rewritten to reach them via Pester's `InModuleScope`
   (`-Parameters`, not closure capture -- confirmed by direct reproduction
   that a plain outer-scope variable is NOT visible inside an
   `InModuleScope` scriptblock without it). Added a regression test
   asserting the exact exported command set.
3. **Analyzer version truthfulness and bounded-job hardening.**
   `Test-TPMProductionPSScriptAnalyzerV1`/`Test-TPMProductionInjectionHunterV1`
   now report `ToolVersion` from a value the bounded `Start-Job` itself
   returns (querying its own loaded `PSScriptAnalyzer` module, or the exact
   `InjectionHunter` manifest at the `-CustomRulePath` it was handed) --
   never a parent-process `Get-Module -ListAvailable` discovery, which is
   not proof of what the job genuinely loaded and ran. Both functions fail
   closed when the job cannot load the analyzer, when the returned version
   is missing/malformed, when different files report different versions,
   or when the per-file result is missing, duplicate, extra, or malformed
   (schema-checked against the job's own declared fields).
   `Invoke-TPMBoundedScriptBlockV1` now re-checks the job's own `.State`
   after `Stop-Job` (a short grace-window `Wait-Job` first, since `Stop-Job`
   does not guarantee the job has actually stopped by the time it returns)
   and reports `TerminationConfirmed=$false` with the job's Id/State
   preserved (never `Remove-Job`-ed) rather than silently reporting a
   cleanly handled timeout when termination could not be confirmed.
   - **Defects found and fixed by this round's own testing:**
     1. `Receive-Job` attaches its own bookkeeping properties
        (`RunspaceId`, and `PSShowComputerName` observed in some runs) to
        every deserialized job-result object -- the new strict per-file
        result schema check initially (and incorrectly) treated these as
        unexpected/malformed extra fields, which made the real (non-mocked)
        analysis of every file report `Executed=$false`, discovered by
        direct reproduction against the real inventory, not assumed to be
        correct from the code alone. Fixed with a shared
        `Get-TPMJobResultOwnPropertyNamesV1` helper that filters known job
        bookkeeping properties before comparing against the expected
        schema.
     2. Mocking `Invoke-TPMBoundedScriptBlockV1` with Pester consistently
        threw `ParseException: The ordered attribute can be specified only
        on a hash literal node` regardless of the mock's own content --
        traced by direct bisection to the function's own `-Parameters`
        parameter being typed
        `[System.Collections.Specialized.OrderedDictionary]`; Pester's
        mock-proxy generation could not handle that type constraint.
        Removed the strict type (kept as an untyped parameter, documented
        by a comment above `param()` establishing the `[ordered]@{...}`
        calling convention every caller in this module already follows) --
        confirmed this alone resolves the mocking failure with an isolated
        repro before reapplying it to the full suite.
   - Regression coverage added: cross-file version-consistency and
     malformed/missing/duplicate/extra-result-record fail-closed tests for
     both `Test-TPMProductionPSScriptAnalyzerV1` and
     `Test-TPMProductionInjectionHunterV1`; a genuine (non-mocked) confirms
     the exact `ToolVersion` reported matches the real installed module
     version for both PSScriptAnalyzer and InjectionHunter.
- ADR155-Q005/Q006/Q007: the four fact-adapter files plus the two
  `Invoke-TPM-InstallHealthCheck.ps1`/`Tests/InstallHealthCheck.Tests.ps1`
  files touched by correction 1 all had zero non-ASCII bytes, zero parse
  errors, zero PSScriptAnalyzer findings, and zero InjectionHunter findings.
  `Test-TPMProductionPSScriptAnalyzerV1` run fresh against the complete
  real 16-file inventory reports `FindingCount=0` (confirmed directly, not
  assumed) -- the `Invoke-TPM-InstallHealthCheck.ps1` finding from the prior
  round's evidence entry no longer exists.
- Full suite: 1023/1023 on pwsh 7.6.4 (0 skipped); 1016/1023 on Windows
  PowerShell 5.1 (1016 passed, 5 failed, 2 skipped) -- reconciling exactly:
  the 5 failures are the same pre-existing issue #148 Repair-GamePaths
  failures (confirmed by name), and the 2 skips are the pre-existing
  reparse-point skip plus this round's scratch-ownership
  symlink-creation-permission skip (both legitimate, unprivileged-
  environment `Set-ItResult -Skipped` cases -- pwsh's 0-skip run on this
  machine reflects that engine's own environment permitting symbolic-link
  creation where the unelevated Windows PowerShell 5.1 session does not).
  1016 + 5 + 2 = 1023, matching pwsh's total test count exactly.

`TPMCertification.Production.psm1` remains untouched by this checkpoint.
No harness wiring, fact-source swap into `Invoke-TPM-RealInstanceSmoke.ps1`,
ECVF work, or hardware certification was performed. Nothing from this
checkpoint has been committed, staged, or pushed. ADR155-0309 remains
unchecked and partial.

## Phase 3 ADR155-0309 Checkpoint B2: atomic production-harness cutover -- 2026-07-22

Base: `codex/issue-154-evidence-finalization` at
`17c3c2e8c67d2acd504a2b31e1517a11d1547966` (Checkpoint B1, approved, pushed,
CI-green). `scripts/Invoke-TPM-RealInstanceSmoke.ps1` is rewired end-to-end
onto the Phase 3 production authority; every competing legacy certification
path is deleted, not bypassed.

1. **New adapter: `scripts/TPMCertification.ProductionEvidence.psm1`.**
   Exactly one exported function, `New-TPMProductionEvidenceRecordV1`,
   converting one legacy `Add-Screenshot` evidence-ledger record into the
   production authority's evidence schema. Deliberately does not import or
   call `TPMCertification.Shadow.psm1` -- a fresh implementation against
   Authority.psm1's schema, not a reuse of Shadow's Phase 2 adapter. Strict
   (`-ceq`/`-cne`) identity/order checks against the legacy record's own
   `Name`/`Status` fields before trusting it as `Captured`; PNG validation
   (`Test-TPMScreenshotFileValid` + `System.Drawing.Image`) gates every
   `Captured` evidence path before its hash/dimensions are recorded.
2. **Harness rewiring.** Import block now imports Authority/Production/
   Reports/Publication/ProductionFacts/ProductionCycle/ProductionEvidence
   directly (never Shadow). The certification-decision tail (inside the
   pre-existing outer `finally` block) builds the production authority,
   records all 11 facts (`New-TPMProductionFactRecordsV1`), records the 9
   real evidence records in ledger order via
   `New-TPMProductionEvidenceRecordV1`, issues final evidence, seals, and
   invokes `Complete-TPMProductionCertificationCycleV1` -- the sole
   certification-decision/publication call. This entire sequence runs
   inside one `try`/`catch`: any exception produces an explicit
   "CERTIFICATION PIPELINE ABORTED (infrastructure failure)" diagnostic and
   exit code 1, never a fabricated decision, never a legacy fallback (none
   exists to fall back to), never a marker/bundle write. On success, the
   only "FINAL STATUS"/"EXIT CODE" console lines and the only `exit` call
   in that path come from `$productionCycleResult.Projection` -- the
   dispatcher's own final outcome.
3. **Legacy-path removal (problem-class sweep, not just the named
   functions).** Deleted entirely from `Invoke-TPM-RealInstanceSmoke.ps1`:
   `Complete-TPMCertificationTransaction`, `Get-TPMCertificationScoreFromItems`,
   `Test-TPMScoreItemManifest`, `Test-TPMArtifactManifest`,
   `Publish-TPMCertificationArtifacts`, `Get-TPMExpectedScoreItemManifest`,
   `Get-TPMExpectedArtifactManifest`, `Get-TPMCertificationFinalConsoleLines`,
   `Get-TPMCertificationFinalReportLines`, and the `Add-Report`/
   `Add-CertificationReport` accumulators that fed them. Repo-wide grep
   confirmed every remaining reference to these names is inside an
   explanatory comment about their removal, never a live call. The only
   surviving `Overall`/status-producing surfaces are (a) the pre-flight
   `TPM-Invalid-Certification-Environment.{md,json}` diagnostic, which
   throws before the production authority is even constructed, and (b) the
   explicitly-labeled "PROVISIONAL"/"Pending: final evidence validation"
   console preview, computed by informational-only inline arithmetic --
   neither reaches or competes with the dispatcher's own final-outcome exit
   path, which is the sole live `exit` site reachable after certification
   begins.
4. **B1 inventory/InjectionHunter update.** `TPMCertification.ProductionEvidence.psm1`
   added to the fixed inventory (`TPMCertification.ProductionFacts.psm1`'s
   `$script:TpmProductionPowerShellInventoryRelativePathsV1`, now 17
   entries) and to the Pester fixture/self-scan test expectations. Fresh
   PSScriptAnalyzer and InjectionHunter scans of the new file: zero
   findings on both -- no new `InjectionHunterDispositions.psd1` entries
   were needed.
5. **Two real defects found and fixed while re-validating the gates against
   the rewritten harness** (both are also recorded in LESSONS_LEARNED.md):
   - Large-scale legacy-function deletion was done with `sed -i` line-range
     deletion; `sed` silently flattened the file's CRLF working-tree line
     endings to bare LF. This invalidated the `InjectionRisk.AddScript`
     disposition-registry entry, which hardcodes its `Extent` field with
     explicit `` `r`n `` escapes to match the working tree's real CRLF form
     -- surfacing as a `DISPOSITION_REGISTRY_STALE` exception, not an
     obviously line-ending-related symptom. Fixed by normalizing both
     `Invoke-TPM-RealInstanceSmoke.ps1` and the new `ProductionEvidence.psm1`
     back to CRLF before re-running the gates; no registry changes were
     needed once line endings were restored.
   - `Test-TPMProductionInjectionHunterV1`'s pairing loop used a bare
     `else{@()}` for a match key with no registry entry at all -- an
     if/else branch's own output enumeration collapsed that empty array to
     `$null` when captured by assignment (the same "`return @()` unwraps to
     `$null`" class already documented elsewhere in this file, but never
     comma-wrapped in this one spot). This had stayed latent through three
     B1 review rounds (every prior finding always matched an existing
     registry entry) and was only exposed once B2's deletions shifted
     enough code to produce, briefly, an unmatched match key. Fixed with
     `else{,@()}`. One existing test had been asserting
     `Executed | Should -BeFalse` for exactly this scenario -- passing only
     because of the crash, not because it verified the intended
     `Confirmed`/unresolved fallthrough; corrected to assert the real
     contract (`Executed=$true`, `UnresolvedFindingCount=1`, the correct
     per-finding disposition).
6. **Test suite changes.** Removed `Tests/TPMCertificationHarness.Tests.ps1`'s
   entire `Describe "Issue #154 round 3 -- authoritative workflow-owned
   facts, not descriptions of them"` block (~554 lines) -- it exercised only
   the now-deleted legacy transaction/publication pipeline by design, not a
   regression. Replaced `Tests/TPMCertification.Shadow.Tests.ps1`'s
   `Describe "ADR-0155 Phase 2 production shadow boundary"` (which asserted
   the now-superseded Shadow-in-harness wiring) with
   `Describe "ADR-0155 Phase 3 production shadow boundary (ADR155-0309
   Checkpoint B2)"`, asserting the real current invariant: no live
   `Import-Module`/invocation of any Shadow.psm1 symbol anywhere in the
   harness (comments naming Shadow to document its deliberate absence are
   correctly excluded from the check).
7. **Gate totals.**
   - ASCII/BOM: 0 non-ASCII bytes across all 17 inventory files (pwsh and
     WinPS 5.1 both confirmed).
   - Dual-engine parser: 0 parse errors on both engines across all 17 files.
   - PSScriptAnalyzer (project settings): 0 findings across all 17 files on
     both engines.
   - InjectionHunter: `Executed=true`, `FindingCount=27`,
     `UnresolvedFindingCount=0`, `ToolVersion=1.0.0` on both engines
     (unchanged from B1's 27 -- the new file contributed zero findings).
   - Full Pester suite: 976/976 on pwsh 7.6.4 (0 skipped); 969/976 on
     Windows PowerShell 5.1 (969 passed, 5 failed, 2 skipped) -- the 5
     failures are the same pre-existing issue #148 `Repair-GamePaths`
     failures this repo's WinPS 5.1 environment has always produced
     (confirmed by name against the B1 checklist entry), and the 2 skips
     are the same pre-existing unelevated-environment
     reparse-point/symlink-permission cases. 969 + 5 + 2 = 976, matching
     pwsh's total exactly.

Complete file list this checkpoint touches: `ARCHITECTURE.md`,
`LESSONS_LEARNED.md`, `SECURITY.md`,
`docs/adr/ADR-0155-IMPLEMENTATION-CHECKLIST.md`,
`Tests/TPMCertification.ProductionFacts.Tests.ps1`,
`Tests/TPMCertification.Shadow.Tests.ps1`,
`Tests/TPMCertificationHarness.Tests.ps1`,
`scripts/Invoke-TPM-RealInstanceSmoke.ps1`,
`scripts/TPMCertification.ProductionFacts.psm1` (inventory-list addition
only), and the new `scripts/TPMCertification.ProductionEvidence.psm1`.
`TPMCertification.Authority.psm1`/`.Production.psm1`/`.ProductionCycle.psm1`/
`.Publication.psm1`/`.Reports.psm1`/`.Shadow.psm1` are all byte-identical to
B1. No packaging-manifest changes were needed: `Tests/Test-ReleasePackage.ps1`
and the release ZIP contents list in CLAUDE.md never enumerated any
`TPMCertification.*.psm1` file (they are dev/certification-only, never
packaged), so the new adapter needs no entry there, consistent with every
sibling module. No ECVF/EXP-002/hardware-certification/packaging-output/
release-publication work was touched. Nothing from this checkpoint has been
committed, staged, or pushed -- it is left for independent review exactly as
requested.

## Issue #172 correction -- absent-tree false-positive skip (discovered during ADR-0155 real-hardware validation, adjacent to Checkpoint B2, not itself a checkpoint) -- 2026-07-22

Real certification (`RunIdentity 2e045f369a2240adb8eaaaed4d9496a0`) against a
machine whose pcsx2x6 crosshair setup was never completed reported
`Pcsx2x6Crosshairs BeforeSkipped=1`/`AfterSkipped=1` even though the
canonical crosshairs directory simply does not exist there -- nothing was
ever unreadable. This is pre-existing `Invoke-TPM-RealInstanceSmoke.ps1`
tree-diffing code (`Get-TreeHash`/`Compare-TreeSnapshot`), not part of the
Checkpoint B1/B2 production-authority cutover, discovered only because
ADR-0155 real-hardware validation was what actually exercised the
never-completed-crosshairs machine state.

Confirmed root cause: the same "`return @()` unwraps to `$null`" class this
session's own LESSONS_LEARNED.md already documents twice, present
independently at three layers -- `Get-TreeHash`'s absent-path `return @()`,
`Compare-TreeSnapshot`'s own `@($Before)` turning that `$null` into a
one-element array containing a single `$null` (counted as a skip), and a
caller-side `else { @() }` fallback with the identical un-wrapped-branch bug.
Fixed all three independently (`,@()` at the producer; explicit,
both-branches-comma-wrapped `$null` normalization inside
`Compare-TreeSnapshot` itself; `,@()` at both caller-side fallbacks) rather
than relying on any single layer's fix to protect the others, per the
review's explicit "resolve the full producer/caller/consumer problem class"
requirement. Independently implemented on this approved PR lineage; the
unreviewed alternate-lineage implementation was not consulted or
cherry-picked.

Eight new regression tests (`Tests/TPMCertificationHarness.Tests.ps1`,
`Describe "Get-TreeHash / Compare-TreeSnapshot absent-tree handling (issue
#172)"`) prove: an absent tree compared before/after is all-zero, not a
phantom skip; `Get-TreeHash` returns a genuine non-null zero-count array for
an absent path; `Compare-TreeSnapshot` treats a literal `$null` argument as
empty; absent-to-present and present-to-absent transitions remain accurate;
a genuinely malformed entry (a real `$null` element, or a blank
`RelativePath`) inside an otherwise non-empty snapshot is still counted as
skipped -- fail-closed behavior for real defects is unchanged; and
`UserProfiles`/`GameProfiles`/`Pcsx2x6Crosshairs` share identical semantics,
proven by exercising the same shared functions every production call site
uses rather than asserting per-tree special cases that do not exist. The
fix was verified against a hand-reproduction of the exact pre-fix code
(`BeforeSkipped=1`/`AfterSkipped=1`, matching the real certification run's
symptom exactly) before confirming the new tests catch it.

Files touched: `scripts/Invoke-TPM-RealInstanceSmoke.ps1` (the fix, all
three layers), `Tests/TPMCertificationHarness.Tests.ps1` (the eight new
tests), `LESSONS_LEARNED.md`, `ARCHITECTURE.md`,
`docs/adr/ADR-0155-IMPLEMENTATION-CHECKLIST.md` (this entry). No ECVF,
pcsx2x6 configuration, EXP-002, packaging, release state, or unrelated issue
was touched. Left uncommitted and unstaged for independent review.

## ADR155-0309 infrastructure-abort repair exposed by Issue #172 -- 2026-07-23

A real certification run aborted before Pester/install-health collection, but
the harness's unconditional `finally` tail continued into production fact
adaptation. The uninitialized `$healthResult` was `$null`; strict-mode access to
`$HealthResult.Checks` raised a secondary `PropertyNotFoundException` that
replaced the unknown initiating exception. Independently,
`Run-TPM-Tests.ps1` omitted `exit $LASTEXITCODE` on its direct pwsh path and
the batch launcher saved `RUN_EXIT` but never returned it after presentation.

The correction records explicit collection state before the main `try`, keeps
the initiating `ErrorRecord` and complete diagnostic, marks collection complete
only after the last collection gate, and places an infrastructure-abort exit
before scorecard/evidence/authority/fact/seal/outcome/publication work in
`finally`. The production fact adapter now deliberately rejects null, scalar,
collection, missing-`Checks`, and null-`Checks` values when no load error was
reported, while explicit Missing/InvalidJson load failures retain their
existing fail-closed fact schema. The PowerShell runner exits with the exact
harness code in direct and relaunch paths; the batch tail uses
`endlocal & exit /b %RUN_EXIT%` only after pause and `popd`.

Regression coverage exercises malformed health schemas, explicit load-error
states, an actual child-process pre-Pester failure against a synthetic install
and harness root, absence of every authoritative publication filename, exact
initiating text, nonzero abort exit, sentinel exit propagation through both
PowerShell paths, and batch `RUN_EXIT` return after cleanup. No real-install
certification, TeknoParrot/PCSX2 mutation, ECVF, EXP-002, packaging, release,
emulator-contract, hardware, GitHub, commit, staging, or push action is part of
this checkpoint.

### Independent-review correction: inner schema and behavioral abort surfaces

The outer `HealthResult`/`Checks` validation was insufficient because it still
read `.Name` and `.Passed` from unchecked entries. The adapter now validates
the complete entry schema before member use and deliberately rejects null,
scalar, nested-collection, missing-member, null-member, malformed-name, and
non-Boolean entries. Empty collections, missing required checks, and duplicate
required checks are schema/infrastructure errors. Valid additional checks are
accepted but do not expand the authority contract's three projected checks;
explicit Missing/InvalidJson load-error facts remain unchanged.

Process-level regressions run copied harness/module sources from a synthetic Git
repository and synthetic install root. Test-only substitutions inject a late
smoke failure after a real synthetic install-health report and an unattended
failure only after temporary configuration restoration. Instrumented copied
production entry points leave an observable marker if authority, fact,
evidence, or cycle composition is entered; both abort paths prove the marker
and every authoritative bundle/marker filename remain absent while preserving
the initiating text and a nonzero process exit. This seam exists only in test
copies and adds no production bypass.

Launcher regressions now cover explicit sentinel exits through direct/relaunch
paths, thrown harness errors, unavailable pwsh, batch cleanup, and the
report-present Explorer branch with a harmless test PATH substitute. Exact exit
preservation is claimed only when a child returns a code; exceptional launch or
script failures are required to remain nonzero.

### Operator-experience execution invariant

- [x] Certification performs no active Git synchronization.
- [x] PowerShell children use `-NoProfile -NonInteractive` with closed stdin.
- [x] Child stdout/stderr and process metadata are retained under timestamped technical logs.
- [x] Pester returns an exact versioned result contract that is validated fail-closed.
- [x] Normal operator output is numbered, append-only, and reports elapsed/status locations.
- [x] Optional post-run Explorer/pause occurs only after the certification exit code is captured.
- [ ] Independent review and real-install certification remain separate checkpoints.

## ADR155-0309 certification isolation and result-validation hardening -- 2026-07-24

An independent review of the in-progress PR #155 operator-experience work found
five problem classes that needed correction before the pipeline could be
trusted to run unattended and non-interactively. This round resolves all five
as problem classes, not point patches.

**1. Closed structured Pester-result contract.** `Read-TPMPesterResultV1`
(`scripts/TPMCertification.Execution.psm1`) validates the entire result object
before any field is consumed: exact top-level field set (no missing, no
unexpected extras), `SchemaVersion` pinned to `1`, `Engine` a nonblank string,
every numeric field (`Discovered`/`Passed`/`Failed`/`Skipped`/`NotRun`/
`Containers`/`FailedContainers`/`DurationMilliseconds`) constrained to a true
integral .NET numeric type in `0..2147483647` (strings, fractions, booleans,
null, NaN/Infinity, arrays, and out-of-range values are all rejected before
use), and the reconciliation invariant `Discovered == Passed + Failed +
Skipped + NotRun` plus `FailedContainers <= Containers`. `Categories` gets its
own exact field set and integer validation, `VirtualBetaTesterTotal ==
VirtualBetaTesterPassed + VirtualBetaTesterFailed`, and every category total
bounded by the applicable global total. `Failures` must be a JSON array (never
a bare object or scalar); every entry has the exact `Name`/`Message` field set
with both nonblank strings; the entry count must equal `Failed` exactly in
both directions (a zero-failure result requires an empty, present array --
never `$null` -- and a nonzero-failure result requires exactly that many
entries, not more and not fewer). This repository's own PowerShell reads a
JSON array property back as a real `System.Object[]` even at zero or one
elements (confirmed by direct reproduction under both pwsh and Windows
PowerShell 5.1 -- the collapse-to-scalar/`$null` behavior only happens for a
*top-level* JSON document, not for an array-valued object property), so no
`,@()`-style wrapping was needed inside the validator itself; the empty-vs-null
distinction is still asserted explicitly in the adversarial suite so a future
change to this behavior would be caught. Every malformed state throws the one
stable `PESTER_RESULT_SCHEMA_INVALID: <reason>` error family -- never a raw
`PropertyNotFoundException` or JSON conversion exception -- and the harness's
own fail-closed collection-abort path (`$collectionCompleted` gate, documented
above) ensures a validation failure prevents every downstream artifact:
authority, facts, evidence, marker, and bundle. Table-driven adversarial
coverage lives in `Tests/TPMCertification.OperatorExperience.Tests.ps1`
(missing/empty/truncated/malformed JSON, wrong top-level shape, extra/missing
top-level fields, unsupported `SchemaVersion`, every invalid `Engine` shape,
every invalid numeric shape crossed with every numeric field, contradictory
totals, malformed `Categories` in every documented way, malformed `Failures`
in every documented way, a valid zero-failure result, and a valid result with
failures).

**2. No blanket confirmation suppression.** The
`$PSDefaultParameterValues['*:Confirm']=$false` global override that had been
present in `scripts/Invoke-TPM-PesterChild.ps1` is removed outright and not
replaced by any other global bypass; a repository-wide regression test
(`Tests/TPMCertification.OperatorExperience.Tests.ps1`) asserts no script or
test under `scripts/` or `Tests/` sets this pattern again. Real, bounded
child-process prompt probes (same file) launch `powershell.exe`/`pwsh` with
`-NoProfile -NonInteractive` and closed stdin (via
`Invoke-TPMIsolatedProcessV1`, the same primitive every production child uses)
and attempt `Read-Host`, `$Host.UI.PromptForChoice`, a `-Confirm`-triggering
`ShouldProcess` call (`Remove-Item -Confirm`), and a cmdlet call missing a
mandatory parameter, each with `$ErrorActionPreference='Stop'` set to match
every real production entry point's own top-of-script posture (confirmed by
direct reproduction: without `Stop`, a NonInteractive-mode prompt failure is a
non-terminating error that a bare script silently continues past to its own
`exit 0` -- this is why `$ErrorActionPreference='Stop'` is a repository-wide
convention on every production entry point, not an incidental detail). Every
probe is asserted to terminate promptly with a nonzero exit code, confirmed
termination, and no hang, under both engines, with a bounded per-probe
timeout.

**3. Closed parser-child stdin.** `TPMCertification.ProductionFacts.psm1`'s
`Invoke-TPMExternalProcessWithTimeoutV1` (used by the parser probe,
PSScriptAnalyzer, and InjectionHunter fact collectors) now delegates directly
to `Invoke-TPMIsolatedProcessV1` in `TPMCertification.Execution.psm1` instead
of maintaining a second, independent process-launch implementation -- closing
the circular-dependency question by having `ProductionFacts.psm1` import
`Execution.psm1` (a one-directional dependency; `Execution.psm1` does not
import `ProductionFacts.psm1`). Every parser/analysis child therefore
inherits the same hardening: GUID-named stdin/stdout/stderr files created with
`FileMode.CreateNew` (never overwrite-if-exists) beneath a directory verified
non-reparse-point and (for `Invoke-TPMIsolatedProcessV1`'s own working/log
roots) either pre-existing or freshly created by this process, separate
stdout/stderr streams, `-NoProfile -NonInteractive` arguments, a bounded
timeout with confirmed termination (`Stop-Process` followed by a
`WaitForExit` grace window and an explicit `HasExited` re-check, never a
fire-and-forget `Kill()`), exit code captured before the process object is
disposed, and temp files removed only after termination is confirmed (an
unconfirmed termination preserves every log for investigation instead of
deleting evidence). Real (non-mocked) parser-probe tests in
`Tests/TPMCertification.ProductionFacts.Tests.ps1` already exercised genuine
child-process parsing (including a file path containing spaces and shell
metacharacters); the closed-stdin/no-prompt/no-hang property itself is proven
directly against the shared primitive in
`Tests/TPMCertification.OperatorExperience.Tests.ps1`'s prompt-probe suite,
since every parser/analysis child launched by `ProductionFacts.psm1` now goes
through that exact code path.

**4. Restored behavioral early-abort regression test.** The prior
`Describe 'real harness incomplete-collection fail-closed path'` block in
`Tests/TPMCertificationHarness.Tests.ps1` asserted only that certain strings
appeared in the harness's own source in a certain order -- it proved nothing
about runtime behavior. A new `Describe 'a pre-Pester collection failure
genuinely aborts the real harness child process'` block (same file) launches
the real harness entry point as a real child process (via
`Invoke-TPMIsolatedProcessV1`) against a copied synthetic repository with a
single injected `throw` immediately before the harness's own unique Pester-gate
marker line -- i.e., strictly before Pester, install-health collection, or any
later gate ever runs. It proves: nonzero process exit code; the original
sentinel error text is retained verbatim in the captured output (not replaced
by a secondary exception -- and the output is asserted to contain no
`PropertyNotFoundException`); the operator-facing "CERTIFICATION PIPELINE
ABORTED (infrastructure failure)" banner is present; no `FINAL STATUS:
CERTIFIED`/`FINAL STATUS: NOT CERTIFIED` line and no scorecard `Overall:
CERTIFIED`/`NOT CERTIFIED` line appear anywhere in the output (a bare
case-insensitive `\bCERTIFIED\b` scan was tried first and rejected as a test
design -- it false-positived against unrelated harness prose, e.g. a gate
purpose string reading "Confirms the certified commit and working-tree
state"); the Pester child process is never invoked at all (proven by an
instrumented copy of `Invoke-TPM-PesterChild.ps1` that would append to a
test-only marker file the moment its own `Import-Module Pester` line is
reached, and by confirming no `Pester-result-v1.json` exists anywhere under
the harness root); no authority/facts/evidence/cycle composition is entered
(the same instrumented-module marker pattern used by the pre-existing late-
failure tests); no authoritative artifact file
(`TPM-Certification-Final-Outcome`/`Commit`/`Manifest`/`Scorecard`/
`Eligibility`/`Publication`) exists anywhere under the harness root; and the
child process neither prompts nor hangs, under a bounded timeout. The original
source-string Describe block is left in place as a cheap smoke check but is no
longer the only evidence for early-abort behavior. The pre-existing late-smoke
and post-restoration behavioral abort tests are unchanged.

**5. Related isolation hardening.** `Invoke-TPMIsolatedProcessV1`'s stdin/
stdout/stderr/process-metadata filenames are GUID-nonce-prefixed and created
with `FileMode.CreateNew` (the prior timestamp-at-one-second-granularity
naming scheme is gone from every file in `scripts/` and `Tests/` -- confirmed
by a repository-wide grep for the `yyyyMMdd-HHmmss` pattern). Every owned
working/log directory is resolved to a full path and verified non-reparse-
point before use (`Assert-TPMOwnedDirectoryV1`), and every created file's full
path is verified to remain under that owned root before creation
(`New-TPMCreateNewFileV1`). Process metadata written to
`<prefix>-process.json` logs executable identity by filename only
(`[IO.Path]::GetFileName($FilePath)`), a caller-supplied phase identity, PID,
start/end timestamps, duration, exit code, and `ArgumentCount` -- never the
argument values themselves -- so no credential- or path-shaped argument
content reaches a log by default. `Write-TPMSafeTechnicalFileV1` retries
briefly (bounded, `IOException`-scoped) before giving up on a captured log
file, because Windows can briefly hold a just-exited child's redirected-output
handle open after `Process.HasExited` already reports true (confirmed by
direct reproduction under load: reading a just-exited child's stdout log
immediately afterward intermittently threw `IOException: being used by
another process`); a still-locked file after the retry budget is left
unsanitized rather than the caller being aborted over a diagnostics-only
best-effort step. `Assert-TPMOwnedDirectoryV1`'s `-CreateIfMissing` switch
lets `Invoke-TPMIsolatedProcessV1` bring its own working/log directories into
existence on first use (restoring behavior several existing call sites --
e.g. the harness's Pester-gate `TechnicalLogs` directory -- depend on and that
an earlier, stricter "must already exist" draft of this function had silently
broken) while still rejecting a reparse-point target either way. This alone
was not sufficient: `TPMCertification.ProductionFacts.psm1`'s
`Invoke-TPMExternalProcessWithTimeoutV1` had its own separate, redundant
pre-existence guard in front of the delegated call to
`Invoke-TPMIsolatedProcessV1` -- a leftover from before this function
delegated at all -- which silently short-circuited to a not-executed result
before the shared primitive's own `-CreateIfMissing` logic ever ran. This was
found and fixed only by `git stash`-based bisection against the real
end-to-end `Tests/TPMCertification.ProductionHarnessComposition.Tests.ps1`
composition test (which had silently flipped from `CERTIFIED` to `NOT
CERTIFIED`), not by any unit test of the primitive in isolation; the guard is
now removed entirely, trusting the shared primitive as the single source of
truth with the caller's existing `try`/`catch` as the fail-closed backstop.
PSScriptAnalyzer and InjectionHunter tool-version/availability are already
reported from inside the same bounded job (`Invoke-TPMBoundedScriptBlockV1`)
that performs the actual scan, not from a parent-process
`Get-Module -ListAvailable` check assumed to still hold true later.

No PowerShell module/provider installation or execution-policy/trust-setting
change was added anywhere in this round. No general-purpose "skip validation
in test/CI" bypass was added; the only injected-failure seam is the synthetic-
repository copy pattern already established for the late-abort tests, present
only in test doubles.

**6. Fail-closed correction (PR #155 static review, following commit).** Two
paragraphs above are superseded by a later round: `Write-TPMSafeTechnicalFileV1`
no longer "gives up gracefully" / "leaves unsanitized" on retry exhaustion --
retries are scoped to exactly `IOException.HResult` `0x80070020`
(`ERROR_SHARING_VIOLATION`) / `0x80070021` (`ERROR_LOCK_VIOLATION`), every
other exception throws immediately, and exhaustion of the transient retry
throws a tagged `SANITIZATION_RETRY_EXHAUSTED:` exception (a
`System.IO.IOException` carrying the original exception as `InnerException`)
instead of returning. `Assert-TPMOwnedDirectoryV1` now walks every existing
path component from the owned root through the target for the `ReparsePoint`
attribute (not just the leaf), uses a component-boundary containment check
instead of a string-prefix check, and revalidates the whole chain again after
`-CreateIfMissing` creates a directory (TOCTOU close). See ARCHITECTURE.md
("Fail-closed correction round") and SECURITY.md for the corrected contracts,
and `Tests/TPMCertification.OperatorExperience.Tests.ps1` for the added
behavioral coverage (genuine OS-level file locks and NTFS junctions).

That same review raised a disposition-registry question: `scripts/
InjectionHunterDispositions.psd1`'s one line-number change across the
commit that introduced this section (163 -> 244, `TPMCertification.
Execution.psm1`, `InjectionRisk.StaticPropertyInjection`, extent
`$result.$name`) was hypothesized to be caused by the `$PSDefaultParameterValues
['*:Confirm']=$false` line deleted from `scripts/Invoke-TPM-PesterChild.ps1`
in that same commit having its own InjectionHunter finding that disappeared
(an assumed 27 -> 26 finding-count drop). An exact re-run of InjectionHunter
(identical tool version, identical production inventory, identical per-file
invocation used by `Test-TPMProductionInjectionHunterV1`) against both
commits disproved this: the finding count was unchanged (27 in both), and
`Invoke-TPM-PesterChild.ps1` had zero InjectionHunter findings in either
commit -- the deleted line was never flagged by the tool at all. The
line-number change was ordinary drift: unrelated function additions earlier
in `TPMCertification.Execution.psm1` shifted every later line down,
including the one pre-existing `$result.$name` finding the entry has always
covered. The fail-closed correction round in this same commit added roughly
140 more lines ahead of that same finding, so the registry entry's line was
updated again, 244 -> 401, for the same reason -- still the same finding
(same file/rule/extent), never a removed-and-re-added one.

## ADR155-0309 round 3 -- trusted-root wiring correction -- 2026-07-24

A further independent static review of PR #155 found a real defect the
round-6 "fail-closed correction" above did not catch: `Assert-TPMOwnedDirectoryV1`
always called `Assert-TPMNoReparseInChainV1` with `-Root $full -Target $full`
-- the SAME path -- so the ancestor-chain walk that round only ever inspected
the leaf directory's own attributes, never any real ancestor. This defeated
the round-6 hardening's stated purpose (walking every existing component from
"the declared owned root" through the target) without failing any of that
round's own tests, because every one of those tests happened to validate a
directory already exactly one level below an already-existing, already-
validated parent. The specific gap -- an intermediate-level junction planted
above a multi-level MISSING path (e.g. the harness's own `Reports` or
`ProductionWork` folder, one level above the timestamped run directory
actually passed to the function) -- was reachable in production (`New-Item
-ItemType Directory` silently creates untracked intermediate levels) but was
never exercised by any prior test.

**Self-root wiring defect and correction, precisely.** The defect: Root and
Target parameters were the same string in every call, by construction --
`Assert-TPMOwnedDirectoryV1 -Path $full` computed `$full` once and passed it
as both Root and Target to the chain walker, so "declared owned root" was
never actually a caller-declared value distinct from the thing being
validated. The correction: `Assert-TPMOwnedDirectoryV1 -Root <trustedRoot>
-Path <target> [-CreateIfMissing]` now requires the caller to supply a
distinct trusted root as a separate, mandatory parameter. The root is
validated on its own (existence, stat-ability, non-reparse) before the target
is even resolved. Root == Target remains a supported, explicitly tested case
(a caller's own already-established top-level directory) -- the fix is not
"Root and Target must always differ," it is "the caller must say what the
root is, rather than the function silently manufacturing one by copying the
target." A new `New-TPMOwnedDirectoryChainV1` helper brings a multi-level
path into existence one authorized level at a time (each level going through
`Assert-TPMOwnedDirectoryV1 -CreateIfMissing` against the previous,
already-validated level as its root) instead of ever relying on `New-Item`'s
own multi-level auto-create. `New-TPMCreateNewFileV1` gained the same
distinct `-Root` parameter and a second revalidation point, immediately
before the underlying `FileStream` is opened, narrowing (not eliminating) the
TOCTOU window a single validate-then-use call leaves open.
`Invoke-TPMIsolatedProcessV1` gained mandatory `-WorkingDirectoryRoot`/
`-LogDirectoryRoot` parameters; every real caller was updated to supply its
own genuinely-already-established anchor (`HarnessRoot` for the harness
scripts' report/log/production-work trees, the repository checkout path
itself for working directories, each caller's own already-validated
scratch parent for `TPMCertification.ProductionFacts.psm1`'s parser probe)
-- see ARCHITECTURE.md's "Trusted-root wiring correction (ADR155-0309 round
3)" for the exact caller list and what each one supplies. See SECURITY.md
for the corrected invariant statement, including the explicit acknowledgment
that this narrows, and does not eliminate, the residual TOCTOU race.

**Signed-HResult empirical verification (Item 3).** The same round's static
review flagged that `Test-TPMTransientIOHResultV1`'s comparison of
`Exception.HResult` (a signed `Int32`) against the hex literals `0x80070020`/
`0x80070021` had never been empirically verified against real OS-produced
values under both engines, and that comparing a signed HResult against an
unsigned/wrongly-typed hex literal is a classic PowerShell footgun. Direct
verification (both `pwsh` 7.6.4 and Windows PowerShell 5.1.26100.8875, this
machine): `0x80070020`/`0x80070021` parse as genuine `[int32]` literals with
values `-2147024864`/`-2147024863` under BOTH engines (PowerShell's hex-literal
parser keeps an 8-hex-digit literal as `Int32`, using its 32-bit bit pattern
including the sign bit, rather than promoting it to `Int64`/`UInt32` -- the
footgun the reviewer was right to be suspicious of does not actually occur for
an 8-digit literal on either engine tested). A genuine OS-level sharing
violation (`[IO.FileStream]` opened twice with `FileShare.None`) and a genuine
lock violation (`FileStream.Lock()` called twice over the same byte range)
were reproduced directly (not synthesized via the `IOException(message,
hresult)` constructor) and both produced `System.IO.IOException` with
`.HResult` exactly `-2147024864` (`0x80070020`) and `-2147024863`
(`0x80070021`) respectively, identically under both engines -- matching the
classifier's existing literals exactly. No code change to
`Test-TPMTransientIOHResultV1` was needed; the classification was already
correct, now with empirical proof rather than an unverified assumption behind
it. New tests in `Tests/TPMCertification.OperatorExperience.Tests.ps1`
("ADR155-0309 round 3: classifies the ACTUAL, empirically-observed HResult of
a genuine OS-level sharing violation and lock violation...") reproduce both
real violations directly and assert the classifier, plus an off-by-one
adjacent-value check on both sides of each transient literal.

**InjectionHunter disposition-registry occurrence-count correction (Item
4).** The disposition-registry entry for `scripts/Invoke-TPM-RealInstanceSmoke.ps1`'s
`Add-Type -AssemblyName System.Drawing` finding read "A second, separate
occurrence of Add-Type with the same fixed AssemblyName literal elsewhere in
this file (see line 1169 above)." A direct grep of the source (both at commit
`3931b5e9` and in the round-3-corrected checkout) shows THREE textually
identical occurrences of that statement, not two. A fresh raw InjectionHunter
scan (identical tool version 1.0.0, identical 19-file production inventory,
exported to JSON and diffed by File+RuleName+Line+Column+Extent identity)
against both `3931b5e9` (27 raw findings) and the round-3-corrected checkout
(27 raw findings) confirmed: the scanner emits a finding for only TWO of the
three source occurrences in either commit (the `Save-TPMScreenCapture`
occurrence, immediately preceded in the same function by a separate `Add-Type
-AssemblyName System.Windows.Forms` call, never produces its own finding);
every other finding identity is unchanged between the two commits modulo pure
line-number drift from this round's edits (verified: 21 of 27 identities
unchanged at the exact same line, the remaining 6 shifted by exactly the
lines this round added ahead of them in `scripts/TPMCertification.Execution.psm1`
and `scripts/Invoke-TPM-RealInstanceSmoke.ps1`, same File+RuleName+Extent
throughout); zero added, zero removed findings. No new disposition entry was
added for the third, unflagged source occurrence -- per this registry's own
stated purpose (dispositioning findings the scanner actually emits, not
speculative source review), an occurrence the tool never flags gets no entry
of its own, only a documented explanation. The existing entry's reasoning
text was corrected to state the true count (three source occurrences, two
flagged, the third's absence explained) instead of the false "a second,
separate occurrence" framing.
`Test-TPMProductionInjectionHunterV1` run directly against the corrected
registry and current inventory reports `FindingCount=27`,
`UnresolvedFindingCount=0`, `Dispositions.Count=27` -- zero unresolved, and
`Assert-TPMDispositionRegistryV1`'s own stale-entry check (every registry
entry must be consumed by a real current finding) raised no
`DISPOSITION_REGISTRY_STALE` error, confirming zero stale entries.

## Phase 3 ADR155-0309 Checkpoint B1 -- round 4 line-identity correction -- 2026-07-24

Pure line-accuracy audit of `scripts/InjectionHunterDispositions.psd1`,
prompted by the possibility that commits landed after round 3's own
correction (`0b216e1`, `9b01f13`, `f6fe0fa`, `32145d8`, and this branch's
own `cf14a80`/`3931b5e`/`1f0a03f`/`a812352` -- none of which touched the
disposition registry itself) shifted line numbers in
`scripts/Invoke-TPM-RealInstanceSmoke.ps1` out from under round 3's
line-accurate entries again. No production PowerShell behavior changed this
round; the registry is a `.psd1` data file, not executable logic.

**Method.** A fresh raw InjectionHunter scan (tool version 1.0.0, the same
19-file production inventory `Get-TPMProductionPowerShellInventoryV1`
enumerates, the same `Invoke-ScriptAnalyzer -Path <file> -CustomRulePath
<InjectionHunter.psd1>` invocation `Test-TPMProductionInjectionHunterV1`
itself uses) was captured to structured JSON (File, RuleName, Extent,
Line, EndLine, StartColumn, EndColumn) and diffed against the registry by
File+RuleName+Extent match key, pairing same-key occurrences in ascending
Line order on both sides. 27 raw findings, 27 registry entries, one-to-one
key coverage with no missing and no stale keys and no per-key count
mismatch -- the registry's content/reasoning was already correct; only 5 of
27 `Line` values had drifted:

| File | RuleName | Extent | Old Line | New Line |
|---|---|---|---|---|
| scripts/Invoke-TPM-RealInstanceSmoke.ps1 | InjectionRisk.StaticPropertyInjection | `$candidate.$name` | 654 | 664 |
| scripts/Invoke-TPM-RealInstanceSmoke.ps1 | InjectionRisk.AddType | `Add-Type -AssemblyName System.Drawing` (1st, Test-TPMPngStructure) | 1185 | 1195 |
| scripts/Invoke-TPM-RealInstanceSmoke.ps1 | InjectionRisk.AddType | `Add-Type -Language CSharp -TypeDefinition $tpmWindowInteropSource -ErrorAction Stop` | 1248 | 1258 |
| scripts/Invoke-TPM-RealInstanceSmoke.ps1 | InjectionRisk.AddType | `Add-Type -AssemblyName System.Windows.Forms` (Save-TPMScreenCapture) | 1276 | 1286 |
| scripts/Invoke-TPM-RealInstanceSmoke.ps1 | InjectionRisk.AddType | `Add-Type -AssemblyName System.Drawing` (2nd, Save-TPMRenderedTextCapture) | 1314 | 1324 |

All five are a uniform +10 within `scripts/Invoke-TPM-RealInstanceSmoke.ps1`
(consistent with 10 lines having been added earlier in that file since
round 3), but each was independently verified against its own paired raw
finding rather than applied as a blanket offset. No line in any other
file (`TeknoParrot-Manager.ps1`, `tools/Invoke-TpmAutoUpdate.ps1`,
`tools/TpmAutoUpdate.Core.psm1`, `scripts/Debug-TPM-MenuLayout.ps1`,
`scripts/TPMCertification.Execution.psm1`) had drifted; in particular
`scripts/TPMCertification.Execution.psm1`'s `$result.$name` entry (round 3
significantly modified this file) was re-verified still exactly correct at
line 484 with no side-effect drift from round 3's own edits.

**Round 3's occurrence-count claims re-verified, still true.** Direct grep
of current source confirms: `scripts/Invoke-TPM-RealInstanceSmoke.ps1`
still contains exactly THREE `Add-Type -AssemblyName System.Drawing`
statements (Test-TPMPngStructure/PNG validation at line 1195,
Save-TPMScreenCapture at line 1287, Save-TPMRenderedTextCapture at line
1324); the scanner still emits findings for only the first and third (1195,
1324) -- the Save-TPMScreenCapture occurrence at 1287, immediately preceded
by its own `Add-Type -AssemblyName System.Windows.Forms` call at 1286, still
does not produce its own finding. Same file still contains exactly TWO
`$candidate.$name`-shaped dynamic member-access occurrences (line 664, over
the fixed per-field name set; line 671, `$candidate.$name` selecting from
the fixed `Duration`/`Time` name set) and the scanner still emits a finding
for only the first (664). No new disposition entries were added for either
unflagged occurrence, per this registry's stated purpose.

**New audit finding, not requiring a registry change.** This round's source
sweep also located a THIRD, previously-undocumented `Add-Type -AssemblyName
System.Windows.Forms` occurrence in `TeknoParrot-Manager.ps1` at line 13598
(the Action-Items-summary save-dialog path), in addition to the two already
known (line 417, disposed; the `Invoke-TPM-RealInstanceSmoke.ps1` one at
1286, disposed separately). The raw scan does not emit a finding for line
13598 -- confirmed by direct grep-and-scan cross-check, not assumed -- so no
disposition entry was added for it (same "tool never flagged it, no entry"
rule as the System.Drawing/`$candidate.$name` cases above). Noted here for
the record; the existing line-417 entry's reasoning makes no occurrence-count
claim, so it did not need correction.

**Verification.** `Test-TPMProductionInjectionHunterV1` invoked directly
(not simulated) against the corrected registry and the live 19-file
inventory, under both pwsh 7.6.4 and Windows PowerShell 5.1, reports
identically: `Executed=$true`, `FindingCount=27`,
`UnresolvedFindingCount=0`, `Dispositions.Count=27`, every disposition
`FalsePositive`, no `DISPOSITION_REGISTRY_STALE` exception.

Full `.\Tests` suite: pwsh 7.6.4 reports 1191/1191 passed (0 failed, 0
skipped). Windows PowerShell 5.1 reports 1183 passed, 6 failed, 2 skipped
(1191 total) -- reconciled directly against the unmodified
`a8123520344ed8c2ef0e9c9a2cbf21235abc2958` baseline itself (via `git stash`
of this round's two changed files, a full PS5.1 suite run against the bare
baseline commit, then `git stash pop`): the baseline run reports the
identical 1183/6/2 split, the same 6 failing test names (the 5 pre-existing
"Virtual Beta Tester: registered-but-moved recovery via Repair-GamePaths
(issue #88 A3)" failures plus one genuinely flaky, environment-dependent
"Screenshot privacy disclosure... Save-TPMScreenCapture returns a
CaptureScope" failure -- reproduced in isolation, failing identically under
both pwsh and PS5.1 with a `Win32Exception: The handle is invalid` from
`Graphics.CopyFromScreen`, and confirmed nondeterministic: it does not fail
inside the full pwsh suite run despite failing every time it was run in
isolation, indicating a console/display-handle timing dependency rather than
anything code- or disposition-registry-related) and the same 2 skips
(reparse-point creation permission cases). No pass/fail/skip outcome moved
in either direction as a result of this round's changes -- exactly as
expected, since no production PowerShell behavior was touched.
PSScriptAnalyzer with `PSScriptAnalyzerSettings.psd1` against
`TeknoParrot-Manager.ps1`, `scripts/`, and `tools/` reports zero findings
(unaffected, as expected -- no `.ps1`/`.psm1` production file touched; a
recursive sweep including `Tests/` surfaces one pre-existing
`PSUseSupportsShouldProcess` finding in
`Tests/TpmAutoUpdate.DestructivePath.Tests.ps1`, outside this round's
authorized file list and outside the standard non-recursive production
gate). Zero non-ASCII bytes and zero parse errors on
`scripts/InjectionHunterDispositions.psd1` and this checklist file, under
both engines. `git diff --check` clean.

## ADR155-0309 operator-experience review round -- redirected-cleanup refusal, real HarnessRoot bootstrap, diagnostic-hardening completion -- 2026-07-27

Closes the two behavioral items left incomplete by the prior round's
diagnostic-hardening commit (`cb0dd97127cb6d4e40c247cefe05599c6a819299`):
proving the real cleanup path refuses redirected/junctioned targets, and
proving the real `Run-TPM-Tests.ps1` entry point bootstraps `HarnessRoot`
correctly and fails closed. Also completes the diagnostic-hardening audit
itself, which a partial prior round had begun but not finished.

**Changed files:** `scripts/TPMCertification.Authority.psm1`,
`scripts/TPMCertification.ProductionFacts.psm1`,
`Tests/TPMCertification.Authority.Tests.ps1`,
`Tests/TPMCertification.ProductionFacts.Tests.ps1`,
`Tests/TPMCertificationHarness.Tests.ps1`.

**Redirected-cleanup refusal.** `Tests/TPMCertification.ProductionFacts.Tests.ps1`'s
"redirected-cleanup refusal via the real production path
(Remove-TPMOwnedScratchDirectoryV1)" `Describe` block exercises the actual
production cleanup primitive -- never a replica -- against real NTFS
junctions: ordinary cleanup succeeds; an already-missing owned leaf is
idempotent; a forged foreign directory is refused; a root-level junction,
an intermediate-component junction, and a leaf junction are each refused
independently; a Root-vs-Root-Evil sibling-prefix confusion is refused;
cleanup invoked after an uncertain (crash/kill/timeout) child-process
termination is still refused when the leaf was left redirected. Every
junction-based refusal case asserts SHA-256-hash and directory-listing
byte-identity on the foreign target before and after the refused attempt.
No production defect was found -- `Remove-TPMOwnedScratchDirectoryV1` and
`Resolve-TPMContainedPathV1` already revalidated the full chain correctly;
this round adds the missing behavioral proof, not a fix. A real
junction-capability probe (`BeforeDiscovery`) skips only the junction-
dependent sub-cases when the test account/OS cannot create junctions; every
non-junction ownership test remains unconditional.

**Real HarnessRoot bootstrap.** `Tests/TPMCertificationHarness.Tests.ps1`'s
"Run-TPM-Tests.ps1 real HarnessRoot bootstrap" `Describe` block invokes the
actual `scripts/Run-TPM-Tests.ps1` entry point as a real child process
(via `Invoke-TPMIsolatedProcessV1`, `-NoProfile -NonInteractive`, closed
stdin, redirected stdout/stderr, bounded timeout) against a TestDrive-copied
fixture repository. The only substitution is inside that copied fixture: the
single downstream call to `Invoke-TPM-RealInstanceSmoke.ps1` is replaced by
an environment-variable-gated stub (inert unless the variable is set, which
production code never sets) that records resolved paths/commit and exits.
Proven: the success path creates exactly `Reports\<stamp>\TechnicalLogs` and
nothing else, with the stub receiving the correct resolved paths/commit;
failure is fail-closed (nonzero exit, no marker, never observable as a
`CERTIFIED`/`NOT CERTIFIED` verdict) when HarnessRoot's parent is a
junction, HarnessRoot itself is a junction, an intermediate component
(`Reports`) is a junction, the parent is missing, a dot-segment traversal
`-HarnessRoot` value is supplied (proven to canonicalize correctly and never
touch a decoy sibling), or a file occupies the name a directory needs to be
created at; a Root-vs-Root-Evil sibling is untouched; a genuine downstream
failure exit code propagates unchanged; no Explorer launch, prompt, or open
stdin is reachable in the noninteractive path (verified against the real
entry-point source). No production defect was found in
`Run-TPM-Tests.ps1`/`TPMCertification.Execution.psm1`; all scenarios passed
against the existing implementation.

**Diagnostic-hardening completion.** Two real gaps found by a line-by-line
audit of `cb0dd97`'s own diff (not merely trusting its commit message) were
closed: (1) a bare `try{Stop-Job -Job $job -ErrorAction Stop}catch{}` in
`Invoke-TPMBoundedScriptBlockV1` now captures and reports the failure via a
sanitized `Write-Warning`, without changing the timeout/termination-
confirmed outcome; (2) a new `Assert-TPMDiagnosticRecordV1`
(`TPMCertification.Authority.psm1`) validates the `Diagnostic` shape
(`Stage`/`ExceptionType`/`Message`) and is called from
`New-TPMProductionFactRecordsV1` for both `Test-TPMProductionPSScriptAnalyzerV1`
and `Test-TPMProductionInjectionHunterV1` results, failing closed on a
missing, malformed, or wrong-typed `Diagnostic` rather than letting one
reach the authoritative fact record. (`cb0dd97` itself had already hardened
2 of PSScriptAnalyzer's 8 failure branches and all of InjectionHunter's;
this round's audit found and closed the remaining 6 PSScriptAnalyzer
branches were left at `Diagnostic=$null` -- see LESSONS_LEARNED.md's
"operator-experience follow-up round" entry for why the asymmetry wasn't
caught earlier.) The two `Write-Warning` lines identified as interpolating
an unsanitized `path=`/`file=` field next to a sanitized exception message
(`INJECTIONHUNTER_MANIFEST_READ_FAILED`, `PRODUCTION_ENCODING_READ_FAILED`)
were made consistent by routing those fields through
`ConvertTo-TPMSafeTechnicalTextV1` as well.

**Verification.** Focused: 108/108 passed (ProductionFacts + Authority,
including all new cleanup-refusal and Diagnostic-schema tests) and 280/280
passed (Harness, including all three new HarnessRoot bootstrap scenarios)
under both pwsh 7.6.4 and Windows PowerShell 5.1, 0 failed, 0 skipped in
either. Full `.\Tests` suite: pwsh reports 1226/1226 passed (0 failed, 0
skipped); Windows PowerShell 5.1 reports the identical 1226/1226 passed (0
failed, 0 skipped) -- no pre-existing WinPS5.1-only failure reproduced in
this run. `Test-TPMProductionInjectionHunterV1` invoked directly against the
live production inventory reports `Executed=$true`, `FindingCount=27`,
`UnresolvedFindingCount=0`, `Dispositions.Count=27` under both engines,
matching the established baseline exactly. PSScriptAnalyzer with
`PSScriptAnalyzerSettings.psd1` against `TeknoParrot-Manager.ps1`,
`scripts/`, and `tools/` reports zero findings under both engines. Zero
non-ASCII bytes and zero parse errors (both engines' parser) across
`scripts/`, `Tests/`, and every doc touched this round. `git diff --check`
clean.

## Issue #154 real-hardware certification blockers -- unattended Mode config and Pester 5.8.0 regression -- 2026-07-27

Two independently confirmed blockers from a real-hardware certification run
at `2405a59` (preserved evidence:
`W:\Emulators\TeknoParrot\TPM-TestHarness\Reports\2026-07-27_19-33-01`).

**Blocker 1 -- `[Unattended] Mode must be set before starting.` (exit 1).**
Root cause: `-Unattended` had no CLI or config mechanism to select an
initial mode; confirmed via git history that this gap has existed unchanged
since the v0.51 BETA commit that introduced the check, not a recent
regression. Fixed with a new optional `UnattendedMode` saved-config field
(read only when `-Unattended`, validated against a single accepted name,
`HealthCheck` -- not the full set of mode-name strings the main-loop
`switch` otherwise accepts; this RC supports only the one audited
unattended path the certification gate needs, and every other value fails
safely as unsupported), and a clean `exit 0` for
`HealthCheck`'s own completion under `-Unattended` instead of looping back
into the same error. `New-TPMTemporaryUnattendedConfig` and
`Set-TPMConfigJsonRoot` (`scripts/Invoke-TPM-RealInstanceSmoke.ps1`) both
write/preserve this field now (the latter via `Add-Member -Force`, since a
direct property assignment throws `SetValueInvocationException` on a
PSCustomObject property that does not already exist -- confirmed by direct
reproduction). Proven end-to-end with a real, unmodified `pwsh -File
TeknoParrot-Manager.ps1 -Unattended` child process
(`Tests/TeknoParrot-Manager.Tests.ps1`) against a synthetic (non-real)
install fixture: passes configuration validation, runs the real
`Invoke-LibraryHealthCheck`, exits 0. See ARCHITECTURE.md's "Real-hardware
certification blockers (issue #154, 2026-07-27 run)" for the full
inventory of every mandatory config field this required (TeknoParrotRoot,
GamesInstallFolder, UnattendedMode, plus the pre-existing unconditional
`TeknoParrotUi.exe`/`GameProfiles` existence checks in SECTION 2).

**Blocker 2 -- 225 Pester failures (1010 passed / 225 failed / 1235
total).** Root cause: `Invoke-TPM-PesterChild.ps1`'s open-ended
`Import-Module Pester -MinimumVersion 5.0` silently picked up Pester 5.8.0
(a real, newer PowerShell Gallery release) instead of the 5.7.1 this suite
was actually validated against. Reproduced exactly (identical 1010/225/1235
split) in an isolated checkout; definitive A/B proof that the SAME full
1235-test suite scores 1234/1235 under 5.7.1 (the one remaining failure a
pre-existing, unrelated, already-documented flaky screenshot test) versus
1010/225/1235 under 5.8.0, with nothing else changed. The regression only
manifests running the full multi-file suite (any single affected file
alone shows no difference between Pester versions), consistent with the
dominant failure signatures being cross-file/`BeforeAll` script-scope
symptoms, not independent per-test bugs. Fixed by pinning to
`-RequiredVersion 5.7.1` (a hard pin, not a floor) and aligning
`Run-TPM-Tests.ps1`'s preflight check to the same exact version. See
LESSONS_LEARNED.md's "Issue #154" entry for the general rule this
establishes about open-ended version constraints on test-running tools.
An unrelated stray Pester 3.4.0 install was found and ruled out (both
`-MinimumVersion 5.0` and `-RequiredVersion 5.7.1` refuse it outright) but
not touched -- a separate housekeeping item, not part of this fix.

**Also audited (no defect found):** the preserved evidence's zero-byte
`PSScriptAnalyzer.json` is confirmed the correct, expected representation
of zero findings (`@() | ConvertTo-Json | Out-File` genuinely produces zero
bytes for an empty array piped through the pipeline -- a real PowerShell
behavior, not corruption). No code change made for this item.

**Changed files:** `TeknoParrot-Manager.ps1`,
`scripts/Invoke-TPM-RealInstanceSmoke.ps1`, `scripts/Invoke-TPM-PesterChild.ps1`,
`scripts/Run-TPM-Tests.ps1`, `Tests/TeknoParrot-Manager.Tests.ps1`,
`Tests/TPMCertificationHarness.Tests.ps1`, `ARCHITECTURE.md`,
`LESSONS_LEARNED.md`, this checklist.

**Verification.** Focused tests for both fixes pass under Pester 5.7.1
(config creation/preservation/restoration, the real `-Unattended`
child-process fixture, all pre-existing `Set-TPMConfigJsonRoot`/
`New-TPMTemporaryUnattendedConfig`/`Restore-TPMConfigJsonSnapshot`/
`Test-TPMConfigRestored`/`Invoke-TPMUnattendedRootBinding` tests). Static
gates all clean under both engines: zero non-ASCII bytes, zero parse
errors, zero PSScriptAnalyzer findings, InjectionHunter
`FindingCount=27`/`UnresolvedFindingCount=0`/`Dispositions=27` against the
live inventory, `git diff --check` clean. Full `.\Tests` suite results
under both engines with Pester pinned to 5.7.1 recorded separately once
the complete run finishes.
