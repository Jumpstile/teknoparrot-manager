# TpmControllerEvidence/v1

This contract is the neutral boundary between controller detection and everything that uses it. It describes what a provider observed on this PC, not what TPM accepts, configures, or verifies.

Status: draft for review. Applies to TPM 1.0. Tracking issue: #410. Schema: `schemas/TpmControllerEvidence.v1.schema.json`.

Related: #200 (controller mapping), #201 (full HIP integration, post-1.0), #303 (capability contract), #306 (Xbox XInput P1 apply), #307 (verification).

## Ownership

Providers own device probing, provider identity and version, normalized device-class observations, confidence and basis for each observation, and bounded availability status. They do not choose a capability profile, a reference game, a survey answer, or any setting.

TPM control propagation owns the Device Survey, the suggestion shown to the user, archetype choice, and all writes. It may read this evidence. It may not treat it as an answer.

The #303 capability contract owns capability classes and profile identity. Evidence may suggest one. The user's explicit selection stays authoritative.

The #307 verification model owns the Verified status. Device presence is never proof that a game's controls work.

`Get-TpmHardwareEnvironmentEvidence` (GPU, storage, displays) remains separate and explicitly excludes controls. This contract covers controls only and reuses the same rules: facts only, explicit UNKNOWN, no identifiers.

## Status and failure

`EvidenceStatus` is `Observed`, `SourceUnavailable`, or `Rejected`.

- `Observed`: the provider ran. `DeviceObservations` may still be empty.
- `SourceUnavailable`: the provider is missing, timed out, or failed. `DeviceObservations` is empty and `ReasonCodes` says why.
- `Rejected`: the provider output failed validation against this contract and was discarded.

Every status is a normal result. None of them blocks the Device Survey or Propagate Controls. With any status other than `Observed`, TPM behaves exactly as RC8.1 and asks the user.

## Confidence and basis

`Confidence` is `High`, `Medium`, or `Low`. `Basis` is `XInputSlotActive`, `HidUsage`, `WindowsDeviceClass`, or `NameHint`.

In 1.0 only an active XInput slot with class `XboxStylePad` may be `High`. Every other basis is at most `Medium`. `NameHint` is always `Low`, because Windows often gives arcade hardware generic names. Only `High` may pre-fill an answer. `Medium` and `Low` may only be shown as "possible". Two sources that disagree lower the observation to `Low` with reason code `SourcesDisagree`.

## Time facts

`ObservationTimeUtc` is the only time fact. It is excluded from `EvidenceId`. Evidence from an earlier run of the survey or propagation is stale and must be observed again, never reused.

## Identity and safety

`EvidenceId` is deterministic: the SHA-256 of a canonical projection of the provider identity and the sorted `DeviceObservations`, excluding `ObservationTimeUtc`. The same connected controllers always give the same `EvidenceId`.

Serial numbers, device instance IDs, device paths, MAC addresses, user names, machine names, and vendor or product numbers are never read, stored, logged, or reported. `SensitiveIdentifiersIncluded` is always false and `ReadOnly` is always true. A provider that cannot meet this must return `SourceUnavailable`. Detection writes no file, changes no setting, and starts no program. It is bounded to 5 seconds and returns `SourceUnavailable` with reason `Timeout` on expiry.

The schema is intentionally generic about the device list: `DeviceClass` is `XboxStylePad`, `OtherGamePad`, `Wheel`, `LightGun`, `ArcadeEncoder`, `Keyboard`, `PointerOrTrackball`, or `Unknown`. Per-game, per-emulator, and per-brand fields are not v1 fields.

## Allowed and forbidden use

Allowed: pre-fill a Device Survey answer (`High` only), show a "found" or "possible" hint, suggest a starting capability class to #303 marked as suggested, and list the observed classes in the support package.

Forbidden: mark any control or game Verified or ready, write or change any profile or setting, skip a question or hide a choice, choose a reference game without the user's confirmation, and block any screen.

## Provider seam

All TPM code calls `Get-TpmControllerEvidence` and receives `TpmControllerEvidence/v1`. In 1.0 the provider is `TpmLocalDetection`. A later HIP provider (`Hip`) must map into this same shape, is subject to every rule above, and requires the HIP contract to be versioned and pinned in this repository first (recorded on #201).

## Module boundary matrix

| Module | Responsibilities | Inputs | Outputs | Non-goals | Allowed dependencies | Forbidden dependencies | Verification gates |
|---|---|---|---|---|---|---|---|
| Controller evidence provider | Probe connected controller classes and report them with confidence and basis. | Windows device information, XInput state. | `TpmControllerEvidence/v1`. | No profile reads, no writes, no capability choice, no identifiers. | Windows device APIs, this contract. | Profiles, UserProfiles, network, EPIC or HIP code (before HIP is pinned), any write path. | Schema validation, no-identifier scan, no-file-change check, timeout check. |
| Device Survey and propagation (consumer) | Show hints, pre-fill `High` answers, keep the user's answer authoritative. | `TpmControllerEvidence/v1`, the user's answers. | Survey plan, suggestion to #303. | No Verified status, no automatic writes from evidence. | This contract, #303 capability contract. | Provider internals, raw device data. | Override-wins test, unchanged-behavior-on-failure test. |
| Capability contract (#303) | Own capability classes and profile identity. | Suggested class, user selection. | Capability profile. | No device probing. | This contract (read only). | Provider internals. | #303 schema tests. |
| Verification (#307) | Own gameplay verification. | Verification evidence only. | Verified status. | No inference from device presence. | Its own evidence. | This contract as a source of Verified. | #307 tests. |
| Support package | Report observed classes. | `TpmControllerEvidence/v1`. | Class list and provider name. | No identifiers. | This contract. | Raw device data. | No-identifier scan. |

## Required tests

1. Provider throws: result is `SourceUnavailable`, callers behave as in RC8.1.
2. Empty observation list: the survey is unchanged.
3. `NameHint` evidence is `Low` and never pre-fills.
4. Only an active XInput slot with class `XboxStylePad` yields `High`.
5. No identifier appears in the result (deny list of field names and patterns).
6. Detection creates and changes no file (file listing before and after).
7. The user's answer overrides a pre-filled value.
8. The 5-second bound returns `SourceUnavailable` with reason `Timeout`.
9. The result validates against the schema, and a result that does not validate is `Rejected`.
10. The same controllers give the same `EvidenceId`, and changing `ObservationTimeUtc` does not change it.
