# TpmControllerCapability/v1

This contract is how TPM describes what a controller can do, in TPM's own words. It describes logical controls, not how TeknoParrot stores them. Nothing here reads or writes a profile.

Status: draft for review. Applies to TPM 1.0. Tracking issue: #303. Schema: `schemas/TpmControllerCapability.v1.schema.json`.

Related: #200 (controller mapping), #410 (controller evidence, `docs/architecture/CONTROLLER_EVIDENCE_CONTRACT.md`), #304 (external evidence importer), #305 (coverage and readiness inventory), #306 (Xbox XInput P1 apply), #307 (verification and calibration), #267 (cabinet control inventory, after 1.0).

## What the contract holds

- **Profile identity.** `ProfileId` names the capability profile. `ProfileRevision` goes up by one on every reviewed change.
- **Controller context.** `DeviceClass` (the same classes as the evidence contract), `PlayerSlot` (`P1` to `P6`, or `Cabinet`), and `SelectionSource`. The first target is `XboxStylePad` with `P1`.
- **Semantic controls.** Each control has a `ControlId` such as `Coin1` or `P1Button1`, a `Kind`, a plain `Meaning`, whether it is `Required` or `Optional`, whether it is `Bindable`, its `Scope` (`Player` or `Cabinet`), and an optional `SetupRequirement` (`NotRequired`, `CalibrationRequired`, or `FirstRunRequired`). When a contract does not say, the setup state stays `Unknown`. Cabinet controls such as Test and Service are optional by default and are listed only when a reviewed contract requires them.
- **Evidence.** `Origin` (`TpmReviewed`, `ExternalImport`, `UserProvided`), `ReviewState`, and `ReviewedUtc` say where the contract came from and whether a person reviewed it.
- **Game contracts.** Each reviewed game contract is keyed by `GameProfileId` plus `GameProfileHash` plus `ContractRevision`. A file name alone is never an identity.

## Status words

The schema defines three separate status lists, so they cannot be mixed up. #305 and #307 produce the values.

- **Structural:** `Complete`, `Partial`, `Missing`, `Unknown`, `Unsupported`. This says whether the mapping exists. It says nothing about whether it works.
- **Setup:** `NotRequired`, `CalibrationRequired`, `FirstRunRequired`, `Unknown`.
- **Verification:** `NotVerified` or `Verified`. `Verified` needs a `VerificationEvidenceId`. Only the #307 verification model may produce it.

Nothing is inferred. A bound-button count, a successful launch, a registered game, or a detected device never turns any status into `Complete` or `Verified`.

## Detection and the user's choice

Controller evidence (#410) may suggest a device class. When it does, `SelectionSource` is `SuggestedByEvidence` and `SuggestedFromEvidenceId` records which evidence produced the suggestion. Only an explicit choice by the user makes it `UserSelected`. A suggestion never replaces the user's choice, and detection never marks anything verified.

## No dependency on TeknoParrot storage

The schema has no field named after a TeknoParrot XML or JSON key, and every object rejects unknown fields. A later adapter (#306) maps `ControlId` values to whatever TeknoParrot currently stores. If TeknoParrot changes its storage, only the adapter changes. Reviewed contracts stay valid.

## Versioning and migration

`ContractVersion` is `TpmControllerCapability/v1`. `MinReaderVersion` is the lowest reader version that understands the file. A reader that is older than that must not use the file and must treat it as not reviewed. A later version records `MigratedFromVersion`. A migration never changes `ProfileId`, and never turns a status into a stronger one.

## What this contract does not do

It adds no write path, no profile reader, and no UI. It does not hold verification results, calibration results, or per-user bindings. The adapter and apply work stays in #306, the inventory in #305, and verification in #307.

## Required tests

1. A valid XInput P1 profile matches the schema.
2. Unknown fields are rejected, including TeknoParrot-style storage keys.
3. `SuggestedByEvidence` without an evidence ID is rejected.
4. `Verified` without a `VerificationEvidenceId` is rejected.
5. A game contract without a profile hash is rejected, so a file name alone cannot identify one.
6. Each status list contains exactly the agreed words.
7. The schema file contains no TeknoParrot storage key names and no machine names.
