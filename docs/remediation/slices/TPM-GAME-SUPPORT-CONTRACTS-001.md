# TPM-GAME-SUPPORT-CONTRACTS-001

Status: IMPLEMENTATION COMPLETE; OWNER-RUNTIME EVIDENCE REQUIRED

## Owner report and objective

- Owner report ID: `TPM_GAME_SUPPORT_CONTRACTS_001`
- Scope: catalog-wide static support contracts plus a separate read-only
  runtime assessment for every pinned TeknoParrotUI GameProfiles profile.
- Pinned source: `teknogods/TeknoParrotUI` commit `5880e019016c5c3a0576e97a6c2a7f14bf54e3d1`.
- Expected catalog: 695 GameProfiles XML files, joined case-insensitively to optional GameSetup and Metadata evidence.
- Expected behavior: every pinned profile receives exactly one validated static contract and one final posture: `AUTOMATED_SAFE`, `REVIEW_MANUAL`, or `BLOCKED_UNSUPPORTED`.
- Hummer and Hummer Extreme are representative seeded `REVIEW_MANUAL` records only; they do not define the slice boundary.

## Contract and invariants

- Static contract schema version is `1.2.0`; the immutable `1.1.0` contract
  and registry schemas remain available for version-specific validation.
- Runtime assessment schema is `GameSupportAssessmentV1` version `1.0.0`.
- Registry coverage is exactly one static contract per pinned profile code.
- Profile codes are the case-preserving GameProfiles filename stems; duplicate comparison is case-insensitive.
- Static contracts include profile identity, raw profile SHA-256, launch evidence, media/CHD state, fix domains, ownership, typed support-file, administrator, and controller declarations, granular automation policy, catalog evidence, posture, classification reason, and evidence gaps.
- Static contracts contain no machine state, privilege observation, file presence, controller identity, launch result, or controls result.
- Assessments bind to `ContractId`, `ContractSchemaVersion`, and `ContractSnapshotId`; they never rewrite the static contract.
- Final generation rejects `UNCLASSIFIED`; it is an internal development failure and an RC8 closure failure.
- `NOT_DECLARED` means unknown. It never means no fix, not applicable, unavailable, installed, verified, or successful, and never enables mutation or acquisition.
- Declared typed prerequisite items require evidence references and a verification rule.
- Support-file presence, path, and hash states are orthogonal; aggregate requirement status is derived and never replaces those observations.
- TeknoParrotUI-owned settings remain outside TPM write authority.
- Source-only contracts start `ContractStatus=DECLARED` and contain no runtime validation status.

## Source and implementation mapping

- Static schemas: `contracts/_schema/GameSupportContractV1.1.schema.json`,
  `contracts/_schema/GameSupportContractRegistryV1.1.schema.json`,
  `contracts/_schema/GameSupportContractV1.2.schema.json`, and
  `contracts/_schema/GameSupportContractRegistryV1.2.schema.json`.
- Assessment schema: `contracts/_schema/GameSupportAssessmentV1.schema.json`.
- Static authority module: `scripts/TPMGameSupport.Contracts.psm1`.
- Assessment authority module: `scripts/TPMGameSupport.Assessments.psm1`.
- Standalone generator: `scripts/New-TpmGameSupportContracts.ps1`.
- Integrated generator: `scripts/New-TpmSupportPostureCorpus.ps1`.
- Assessment validator: `scripts/Test-TpmGameSupportAssessment.ps1`.
- Generated artifacts: `game-support-contracts.json` and
  `game-support-contract-validation.json` below the caller-owned output root.
- Focused tests: `Tests/TPMGameSupport.Contracts.Tests.ps1`,
  `Tests/TPMGameSupport.Assessments.Tests.ps1`, and
  `Tests/SupportPostureCorpus.Tests.ps1`.

## Forbidden regressions

- Do not add `.chd` to product game-file discovery.
- Do not register games, repair paths, write UserProfiles/GameProfiles, or alter TeknoParrotUI-owned fields while generating, validating, or assessing contracts.
- Do not infer required patches or fixes from vague metadata such as `WITH_FIX` without an exact pinned mapping.
- Do not choose an arbitrary first CHD or nearest media directory.
- Do not infer `SUPPLEMENTARY_GAMES` provenance from owner knowledge or file presence.
- Do not infer Fanatec support or incompatibility.
- Do not wire this registry or assessment into installers, Guided Setup, Automatic Repair, ReShade, dgVoodoo2, BepInEx, FFB, FFBPlugin, Crosshair, launch, or other deployment paths in this slice.
- Do not emit paths outside the explicitly supplied output root.
- Do not claim runtime or production verification from static generation.
- Do not permit assessment execution to copy, install, download, redistribute, elevate, remap, or write any game or TeknoParrotUI file.

## Tests before and with implementation

- Pinned-catalog fixture generates exactly 695 contracts with zero duplicate profile codes and zero `UNCLASSIFIED` records.
- Hummer and Hummer Extreme seed records retain their pinned revisions, executable rules, manual posture, and disabled automation.
- Missing setup/metadata evidence is retained as an evidence gap.
- `NOT_DECLARED` cannot enable mutation or acquisition.
- `WITH_FIX` metadata does not become a required patch declaration.
- Declared typed prerequisite entries require evidence references and verification rules.
- 1.1 artifacts validate only through the 1.1 validator; 1.2 artifacts validate only through the 1.2 validator.
- Orthogonal support-file presence/path/hash states and aggregate status are covered.
- Exact cxbxr matching profile set and four support filenames are covered without invented hashes or provenance.
- ReVolt administrator scope and Ridge Racer V/Road Fighters backend distinction are covered.
- Existing support-posture fixture corpus and full regression suite remain required.

## Runtime proof and stop condition

- Owner runtime proof is not part of this Desktop OMP implementation slice.
- Before any contract is promoted to runtime-verified or consumed by a
  write-capable flow, owner-approved evidence must show executable containment,
  media/CHD relationship, ownership preservation, prerequisite observations,
  privilege state, and observed controls outcome.
- Stop and retain `REVIEW_MANUAL`, `BLOCKED_UNSUPPORTED`, `DECLARED`, or
  `NOT_EVALUATED` when owner evidence is absent, source identity changes,
  installed profile evidence conflicts with the pinned contract, or assessment
  binding is stale or mismatched.

## External software schema 1.3 extension -- Desktop source/test slice

- Owner report ID: `TPM_GAME_SUPPORT_CONTRACTS_001`; extension scope is limited to
  additive schemas, provenance normalization, source validators/generators,
  read-only assessment state, and permanent tests.
- Contract/registry schema `1.3.0` and assessment schema `1.1.0` are additive.
  Contract/registry `1.2.0` and assessment `1.0.0` remain immutable and are
  dispatched separately; unsupported versions fail closed.
- `Prerequisites.ExternalSoftware` is the only external-software domain.
  Support-file items remain a separate typed domain. Each external item has an
  item-level policy; no domain-level policy is introduced.
- Showdown is the only pinned declaration: canonical profile code `Showdown`,
  one required Rapture3D Game Edition audio-runtime item, vendor/version
  identity as evidence only, no minimum version, unknown architecture, and
  local-installer location only.
- External software assessment generation is read-only and emits no runtime observations
  without supplied machine evidence. The generated Showdown assessment remains
  `NOT_EVALUATED` with null/unknown observed fields and no runtime evidence references.
- No installer execution, download, redistribution, EULA acceptance, menu
  integration, repair, launch, product behavior, owner-runtime proof, package
  rebuild, or release operation is in this slice.
- New source/test mappings: `contracts/_schema/GameSupportContractV1.3.schema.json`,
  `contracts/_schema/GameSupportContractRegistryV1.3.schema.json`,
  `contracts/_schema/GameSupportAssessmentV1.1.schema.json`,
  `scripts/TPMGameSupport.Contracts.psm1`,
  `scripts/TPMGameSupport.Assessments.psm1`,
  `scripts/New-TpmGameSupportContracts.ps1`,
  `scripts/New-TpmSupportPostureCorpus.ps1`,
  `Tests/TPMGameSupport.Contracts.Tests.ps1`,
  `Tests/TPMGameSupport.Assessments.Tests.ps1`, and
  `Tests/SupportPostureCorpus.Tests.ps1`.
- Stop condition: retain `REVIEW`, `NOT_EVALUATED`, or owner-runtime-needed
  dispositions when independent installation evidence, source verification,
  hash authority, or owner-approved runtime proof is absent.
