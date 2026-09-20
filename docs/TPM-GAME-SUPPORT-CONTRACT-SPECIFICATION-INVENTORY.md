# TPM Game Support Contract Specification Inventory

Release context: this inventory documents the RC8 candidate support-contract
slice. The published v1.0 RC7 release and final Version 1.0 remain unchanged.

## Governing sources

- `teknogods/TeknoParrotUI` commit
  `5880e019016c5c3a0576e97a6c2a7f14bf54e3d1`.
- `TeknoParrotUi.Common/GameProfiles/*.xml` as the complete profile universe.
- Case-insensitive matching `GameSetup/*.xml` and `Metadata/*.json` as
  auxiliary evidence only.
- `contracts/_schema/GameSupportContractV1.1.schema.json` and
  `contracts/_schema/GameSupportContractRegistryV1.1.schema.json` as immutable
  1.1 compatibility references.
- `contracts/_schema/GameSupportContractV1.2.schema.json` and
  `contracts/_schema/GameSupportContractRegistryV1.2.schema.json` as the
  static 1.2 contract and registry schemas.
- `contracts/_schema/GameSupportAssessmentV1.schema.json` as the separate
  runtime assessment schema.
- `scripts/TPMGameSupport.Contracts.psm1` as the static PowerShell 5.1
  authority.
- `scripts/TPMGameSupport.Assessments.psm1` as the assessment authority.
- `scripts/New-TpmSupportPostureCorpus.ps1` as the offline source and posture
  generator.
- `docs/remediation/slices/TPM-GAME-SUPPORT-CONTRACTS-001.md` as the slice
  boundary and stop condition.

## Scope

The pinned corpus contains 695 GameProfiles XML files. The 1.2 registry must
emit exactly one static contract per profile code. The static contract records
launch identity, media and CHD declaration state, required/recommended/optional
fixes, known incompatibilities, user-owned content, TeknoParrotUI-owned
settings, prerequisite declarations, release posture, reason, evidence gaps,
and raw source hashes. It does not record runtime validation results.

The separate 1.0.0 assessment records machine/runtime observations bound to a
1.2.0 contract snapshot. Presence, path, and hash states remain independent;
launch success does not imply controls verification.

This slice is read-only. Installers, Guided Setup, Automatic Repair, component
deployment, and TeknoParrotUI-owned writes are outside scope.

## Contract terms

- `AUTOMATED_SAFE`: exact, safe, fully evidenced posture with a supported
  automation path.
- `REVIEW_MANUAL`: valid but incomplete, ambiguous, owner-controlled, or
  runtime-unverified posture.
- `BLOCKED_UNSUPPORTED`: malformed, contradictory, unsafe, or unsupported
  posture.
- `UNCLASSIFIED`: internal generation failure only; it fails RC8 closure.
- `NOT_DECLARED`: unknown. It never means no fix, not applicable, unavailable,
  installed, verified, or successful.
- cxbxr support files are backend-derived only for profiles whose pinned
  `EmulatorType` is `cxbxr`; the exact shared set is
  `ic10_g24lc64.bin`, `pc20_g24lc64.bin`, `ic11_24lc024.bin`, and
  `fpr21042_m29w160et.bin`.
- Controller input APIs, mappings, and backend transport require source-backed
  controller evidence. No Fanatec support claim is emitted without evidence.
- A declared fix item requires evidence references and a verification rule.
- `WITH_FIX` metadata is compatibility evidence only. It does not identify a
  required patch, file, installer, or verification rule by itself.
- Source declaration and runtime verification are separate states.

## Evidence requirements
Every record must retain the pinned repository, commit, profile filename, raw
profile SHA-256, profile revision when present, and matched setup/metadata
hashes when present. Missing auxiliary files become evidence gaps and never
remove the profile from the registry.

## Status

Implemented in the catalog-wide Slice 001 source and validator, including
immutable 1.1 routing, static 1.2 contracts, the 1.2 registry audit, and the
separate 1.0.0 assessment schema/authority. Runtime proof and write-capable
consumer integration remain deliberately out of scope.
