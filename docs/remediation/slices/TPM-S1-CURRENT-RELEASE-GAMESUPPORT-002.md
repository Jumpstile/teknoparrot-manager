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

- Files: `scripts/New-TpmSupportPostureCorpus.ps1`, `scripts/TPMGameSupport.Contracts.psm1`, `scripts/New-TpmGameSupportContracts.ps1`, `Tests/SupportPostureCorpus.Tests.ps1`, `Tests/TPMGameSupport.Contracts.Tests.ps1`, and the current snapshot evidence under `contracts/snapshots/`.
- Functions/regions: generation-mode validation, pinned source ingestion, GameProfile/GameSetup executable precedence, current/historical delta comparison, registry generation, and fail-closed validation.
- Owning subsystem: static GameSupport corpus generation and contract validation.

## 6. Tests required before implementation

- Characterization: accepted snapshot identity, source proof, 925/383/923/2231 catalog counts, historical 695 count, and 230/0/38/657 delta counts.
- Inventory checks: schema 1.3 remains structurally sufficient; historical generation and existing fixture corpus remain unchanged.

## 7. Tests required after implementation

- Executable evidence comparison must normalize path separators and compare the
  executable leaf name before declaring a conflict; directory-qualified
  GameSetup evidence is not a contradiction when it names the same executable.
- Historical comparison must be semantically equivalent to the accepted
  pre-Slice-1 corpus. The only permitted differences are deterministic
  generation metadata added by the explicit mode model; resolver-driven
  contract or posture drift is a failed implementation.
- Documentation screenshot gate must be explicit: README, QuickStart, setup,
  and feature docs require current validated runtime screenshots before release.
  If no such screenshots exist, do not create placeholders; keep the slice on
  hold and leave those user-facing docs unchanged.

- Focused current-release generation: 925 profiles/contracts, zero duplicates, zero `UNCLASSIFIED`, exact snapshot/source binding, 230 added identities, 38 changed-profile matrix, `jdredd`, Showdown, cxbxr, ReVolt, rrv, Road Fighters 3D, and VirtuaRLimit.
- Executable evidence tests: profile precedence, GameSetup fallback, duplicate/case normalization, directory-qualified equivalent paths, and contradictory declarations fail closed.
- Historical compatibility: canonical semantic projections of historical
  `game-support-contracts.json`, `game-support-contract-validation.json`,
  `support-posture.json`, and `manifest.json` must match the accepted
  baseline. The support-posture projection excludes only `GenerationMode` and
  `ComparisonArtifacts`, which are deterministic mode metadata.
- Determinism: two clean output roots have identical path sets, file counts, bytes, and SHA-256 hashes.
- Static gates: schema validation, output containment, checkout contamination, parser, PSScriptAnalyzer, ASCII, `git diff --check`, and the seven-suite Pester 5.7.1 run.

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
