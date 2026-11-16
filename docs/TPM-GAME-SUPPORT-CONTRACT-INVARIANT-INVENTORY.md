# TPM Game Support Contract System Invariant Inventory

Release context: this inventory governs the RC8 catalog-wide support-contract
slice. It does not authorize release publication or runtime deployment.

## Component boundary

This inventory covers the offline corpus reader, catalog registry generator,
static contract validator, assessment validator, deterministic artifacts,
posture finalization, and read-only support-posture integration:

- `scripts/New-TpmSupportPostureCorpus.ps1`
- `scripts/TPMGameSupport.Contracts.psm1`
- `scripts/TPMGameSupport.Assessments.psm1`
- `scripts/New-TpmGameSupportContracts.ps1`
- `contracts/_schema/GameSupportContractV1.1.schema.json`
- `contracts/_schema/GameSupportContractRegistryV1.1.schema.json`
- `contracts/_schema/GameSupportContractV1.2.schema.json`
- `contracts/_schema/GameSupportContractRegistryV1.2.schema.json`
- `contracts/_schema/GameSupportAssessmentV1.schema.json`

It does not cover component installers, Guided Setup, Automatic Repair, runtime
repair, game registration, UserProfiles writes, GameProfiles writes, or
TeknoParrotUI-owned settings.

## Invariants

### CAT-001 -- Pinned profile coverage is exact

The pinned GameProfiles directory produces exactly one registry contract per
case-insensitive profile code. For commit
`5880e019016c5c3a0576e97a6c2a7f14bf54e3d1`, the count is 695. Duplicate codes
or count mismatch fail validation.

### CAT-002 -- Every final record has a posture

Every final record is `AUTOMATED_SAFE`, `REVIEW_MANUAL`, or
`BLOCKED_UNSUPPORTED`. `UNCLASSIFIED` is an internal failure and cannot be
serialized as a valid final registry.

### CAT-003 -- Profile evidence is hash-bound

Every record carries the raw profile filename and SHA-256. Matched GameSetup
and Metadata evidence carries its own source path and SHA-256. Missing
auxiliary evidence is explicit and never silently treated as a negative fact.

### CAT-004 -- Unknown does not authorize action

`NOT_DECLARED` fix, media, CHD, ownership, or runtime state never enables
automation or implies absence, success, installation, or verification.

### CAT-005 -- Declared fixes are verifiable

Every declared or incompatible fix item has evidence references and a
verification rule. Vague metadata, including `WITH_FIX`, cannot create a
required patch or automatic action without an exact pinned mapping.

### CAT-006 -- Media selection is not guessed

The generator never chooses an arbitrary first CHD, nearest folder, or
filesystem candidate. Unknown or ambiguous media relationships remain manual;
contradictory or unsafe relationships fail closed.

### CAT-007 -- Static declaration and runtime assessment are separate

Static 1.2 contracts contain source-derived declarations only. The separate
1.0.0 assessment binds the immutable contract snapshot and records machine or
runtime observations. Presence, path, and hash states remain independent.
Launch success never promotes controls to verified.

### CAT-008 -- Runtime evidence does not promote static state

Source-generated contracts remain static declarations. A runtime assessment
cannot promote a contract to verified or mutate it; owner-approved runtime
evidence is a separate gate.

### CAT-009 -- Generation is read-only and contained

Generation writes only below the caller-supplied output root. It does not
register games, repair paths, modify GameProfiles/UserProfiles, alter
TeknoParrotUI-owned settings, or deploy component files.

### CAT-010 -- Output is deterministic

Given identical pinned inputs, source hashes, fixture inputs, snapshot ID, and
capture time, registry, validation, manifest, JSON, and Markdown outputs are
byte-stable and sorted deterministically.

### CAT-011 -- Backend-derived support is exact and gated

The cxbxr support set contains exactly four BIOS paths and is emitted only for
profiles whose pinned `EmulatorType` is `cxbxr`. Controller APIs, mappings, and
transport are emitted only from source-backed controller evidence. No hardware
support claim is inferred from a game title or unsupported metadata.

## Verification pointers

- `Tests/TPMGameSupport.Contracts.Tests.ps1`
- `Tests/SupportPostureCorpus.Tests.ps1`
- `docs/remediation/slices/TPM-GAME-SUPPORT-CONTRACTS-001.md`
- `docs/remediation/PR-321-control-board.md`
- `docs/remediation/PR-321-reconciliation.md`

Owner-runtime evidence, package identity, hosted CI, and release certification
are separate gates and remain outside this implementation slice.
