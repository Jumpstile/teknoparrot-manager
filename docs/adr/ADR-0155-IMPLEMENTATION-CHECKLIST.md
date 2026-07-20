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
  ADR155-0103, ADR155-0105, and ADR155-T008.

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

- [ ] ADR155-0301 -- Derive the eleven score items and eligibility payload only
  from the sealed raw-fact and evidence authority.
- [ ] ADR155-0302 -- Implement the detached JCS eligibility envelope and every
  non-recursive hash domain from ADR Section 4.
- [ ] ADR155-0303 -- Render final evidence from eligibility only; it must never
  claim `CERTIFIED` before publication.
- [ ] ADR155-0304 -- Replace arbitrary artifact callbacks with deterministic
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
