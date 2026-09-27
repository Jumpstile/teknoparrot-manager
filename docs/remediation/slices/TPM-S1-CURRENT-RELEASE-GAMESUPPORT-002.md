# TPM-S1-CURRENT-RELEASE-GAMESUPPORT-002

## 1. Slice name

- Name: Current-release GameSupport contract migration
- Contract ID: `TPM-S1-CURRENT-RELEASE-GAMESUPPORT-002`
- Issue/PR: PR #321

## 2. Owner report IDs included

- IDs: `TPM_GAME_SUPPORT_CONTRACTS_001`; `TPM_RELEASE_SNAPSHOT_001`
- Exact owner-visible failure: the static GameSupport generator only closes the historical pinned 695-profile corpus, while the accepted immutable current-release catalog contains 925 GameProfiles.

## 3. Explicit exclusions

- Owner IDs not included: runtime reproduction, owner smoke, package, Arcade, merge, tag, publish, certification, and release authorization.
- Excluded runtime targets: SRC, SRTV, SWDC, Wacky Races, OutRun 2, ReVolt, RRV, Road Fighters 3D, and Showdown runtime behavior.
- Live master, mutable release ZIP contents, installed machine state, and runtime observations are not inputs.

## 4. Behavior contract

- Historical generation remains explicitly reproducible as `HISTORICAL_PINNED_695`.
- Current generation is explicitly selected as `CURRENT_RELEASE_925` and requires the accepted immutable snapshot ID, source-proof commit, historical root, and delta manifest.
- Current generation produces exactly one deterministic GameSupport contract per current GameProfile, exactly 925 contracts, zero duplicate canonical identities, zero case-insensitive duplicates, and zero final `UNCLASSIFIED` postures.
- Current output records the immutable SnapshotId and source-proof identity without treating the proof commit as official release provenance.
- Added-profile and semantic-change evidence is generated from the pinned current/historical roots and checked against the accepted delta manifest.
- Static generation never emits runtime observations and never writes outside the caller-owned output root.

## 5. Source/function ownership

- Files: `scripts/New-TpmSupportPostureCorpus.ps1`,
  `scripts/TPMGameSupport.Contracts.psm1`,
  `scripts/New-TpmGameSupportContracts.ps1`,
  `Tests/SupportPostureCorpus.Tests.ps1`,
  `Tests/TPMGameSupport.Contracts.Tests.ps1`, the immutable input contract
  `contracts/TPM-HISTORICAL-695-MANIFEST-ORDER.json`, and the current snapshot
  evidence under `contracts/snapshots/`.
- Functions/regions: generation-mode validation, pinned source ingestion,
  `Assert-TpmSupportHistoricalManifestOrder`, GameProfile/GameSetup executable
  precedence, current/historical delta comparison, registry generation, and
  fail-closed validation. The immutable rank artifact is an input contract,
  never derived from the baseline output tree at runtime.
- Owning subsystem: static GameSupport corpus generation and contract validation.

## 6. Tests required before implementation

- Characterization: accepted snapshot identity, source proof, 925/383/923/2231 catalog counts, historical 695 count, and 230/0/38/657 delta counts.
- Inventory checks: schema 1.3 remains structurally sufficient; historical generation and existing fixture corpus remain unchanged.

## 7. Tests required after implementation

- Executable evidence comparison must normalize path separators and compare the
  executable leaf name before declaring a conflict; directory-qualified
  GameSetup evidence is not a contradiction when it names the same executable.
- Historical compatibility is a byte-level contract against the durable
  replacement evidence inventory at
  `contracts/baselines/TPM-HISTORICAL-695/`: all 703 files, path names, file
  bytes, and tree digest must match under the accepted historical identity.
  `C:\tmp\tpm-slice1-baseline-output` is preserved only as a legacy candidate
  for corroborative compatibility comparison; it is not authoritative.
- Historical `GenerationMode` and `ComparisonArtifacts` root fields are
  absent where absent in the baseline; they must not be added merely to
  describe the explicit generation mode.
- Historical `PrimaryCandidates` and `SecondaryCandidates` preserve the
  producer's external shape: zero candidates are `null`, one candidate is a
  scalar string, and multiple candidates are an array.
- Historical profile, contract, manifest, and Markdown ordering must match
  the baseline while remaining deterministic across supported engines and
  cultures. The manifest's accepted historical order is an immutable,
  identity-bound rank artifact at
  `contracts/TPM-HISTORICAL-695-MANIFEST-ORDER.json`; generation must not read
  the baseline output tree to derive order.
- Current-release generation must produce 925 profiles/contracts with zero
  duplicate identities, zero `UNCLASSIFIED`, exact snapshot/source binding,
  230 added identities, 38 changed-profile records, and the required
  `jdredd`, Showdown, cxbxr, ReVolt, rrv, Road Fighters 3D, and
  VirtuaRLimit cases.
- Executable-evidence tests must cover precedence, GameSetup fallback,
  duplicate/case normalization, directory-qualified equivalent paths, and
  contradictory declarations failing closed.
- The documentation screenshot gate remains explicit: README, QuickStart,
  setup, and feature documentation require current validated runtime
  screenshots before release. If absent, do not create placeholders; keep
  user-facing documentation unchanged and the slice on hold.
- Canonicalizer tests must cover actual characters, literal escape text,
  valid JSON parsing, exact value round trips, repeated byte determinism,
  and PS5.1/PS7 parity.
- Static gates are required after implementation: parser check,
  PSScriptAnalyzer with `PSScriptAnalyzerSettings.psd1`, ASCII check,
  `git diff --check`, and the seven-suite Pester 5.7.1 gate
  `Invoke-Pester -Path .\Tests`.
- Culture tests must compare default and deliberately non-default cultures
  against identical inputs and require identical governed output bytes.
- Determinism tests must cover independent source enumeration order,
  repeated generation, cross-engine output, raw serializer compatibility,
  Unicode preservation, and controller/control semantic invariants.
- Permanent manifest-order regression coverage must exercise the production
  validator and fail closed for: missing artifact, duplicate-696, real
  case-insensitive collision, missing required identity, extra identity,
  wrong SchemaVersion, wrong SnapshotId, wrong UpstreamCommitSha, and wrong
  declared ProfileCount. The duplicate-696 case has ProfileCount 695, an
  actual ProfileCodes array of 696 containing all legitimate identities plus
  one duplicate; hashtable cardinality is not sufficient evidence.
- The accepted ordered sequence is independently bound by SHA-256
  `b7ec88b0de487fbcdcdf697334ccbec154a0f61e8c0a24712f2e99425425f4aa`.
  The projection is UTF-8 without BOM of each ProfileCode followed by literal
  LF, including the final LF. A reorder-only complete-set mutation must fail
  as `HISTORICAL_MANIFEST_ORDER_SEQUENCE_INVALID` before rank construction.

## 8. Documentation/report updates required

- Control board: distinguish historical compatibility corpus 695 from current-release corpus 925 and record this contract.
- Remediation report: record mode selection, immutable identities, added list, changed matrix, executable rules, and validation evidence.
- Architecture: document the two-corpus model, provenance boundary, and source precedence.
- User-facing docs/changelog: no user-facing runtime behavior change in this static generation slice.

## 9. Permanent procedure IDs affected

- `TPM-TRACE-001`: map every source hunk to this contract and the PR #321 control board.
- `TPM_RELEASE_SNAPSHOT_001`: consume only the accepted immutable snapshot and proof identity.
- `TPM_GAME_SUPPORT_CONTRACTS_001`: preserve historical contract compatibility while adding current-release coverage.

## 10. Runtime smoke checklist

- Exact packaged behavior: none authorized; this slice produces static evidence only.
- Required source/package identity: no package authorized.
- Evidence artifacts: generated current registry, added-profile list, semantic-change matrix, validation result, deterministic hashes, and gate output.
- Owner/runtime authorization: not authorized.

## 11. Stop condition

Stop when the explicit modes, current/historical generation, comparison artifacts, focused tests, documentation mapping, and required local gates are complete. Stop and report the exact incompatible field if schema 1.3 cannot represent the current records.

## 12. Forbidden actions

No runtime reproduction, package, owner smoke, Arcade work, merge, tag, publish, certification, release, live-master lookup, mutable release ZIP dependency, or unrelated cleanup.

## 13. Commit/package authorization status

- Commit authorized: No; implementation packet review required.
- Package authorized: No.
- Release/certification authorized: No.
## 14. Historical baseline provenance remediation

The former `C:\tmp\tpm-slice1-baseline-output` is preserved as a legacy
candidate. Its content is corroborated, but its original creation command and
provenance were not recovered. This is an evidence-retention/process issue,
not a demonstrated product defect, and it does not change the historical
compatibility semantics.

The durable replacement evidence is retained under
`contracts/baselines/TPM-HISTORICAL-695/`:

- `baseline-provenance.json` binds `HISTORICAL_PINNED_695`, generator identity,
  accepted source root/commit, SnapshotId, fixed parameters, engine set,
  output identity, ProfileCode sequence digest, and governed tree digest.
- `baseline-files.sha256` contains every governed relative path, byte length,
  and SHA-256 in deterministic ordinal path order.

The replacement baseline is generated independently under Windows PowerShell
5.1 and pwsh 7.6.6 and must match byte-for-byte. Matching the legacy
candidate is recorded only as
`CORROBORATIVE_COMPATIBILITY_WITH_LEGACY_CANDIDATE`; this does not
retroactively make the legacy candidate authoritative.

Authoritative provenance additionally binds the omitted-field self-hash
projection, ordinal/case-sensitive file inventory, dirty-worktree generator
dependency hashes, working-tree diff digest, and in-process engine records.
Generator HEAD alone and an unversioned `pwsh` command are not sufficient
provenance.

`AcceptedAtUtc` remains null, and acceptance authority and acceptance time
remain pending formal ChatGPT/release-authority review.
