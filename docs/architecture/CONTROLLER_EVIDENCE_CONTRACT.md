# TpmControllerEvidence/v1

This contract is the neutral boundary between controller detection and everything that uses it. It describes what a provider observed on this PC, not what TPM accepts, configures, or verifies.

Status: draft for review. Applies to TPM 1.0. Tracking issue: #410. Schema: `schemas/TpmControllerEvidence.v1.schema.json`.

Related: #200 (controller mapping), #201 (full HIP integration, post-1.0), #303 (capability contract), #306 (Xbox XInput P1 apply), #307 (verification).

## Ownership

Providers own device probing, provider identity and version, normalized device-class observations, confidence and basis for each observation, and bounded availability status. They do not choose a capability profile, a survey answer, or any setting.

TPM's Controls screen owns the Device Survey, the suggestion shown to the user, the controller layout choice, and all writes. It may read this evidence. It may not treat it as an answer.

The #303 capability contract owns capability classes and profile identity. Evidence may suggest one. The user's explicit selection stays authoritative.

The #307 verification model owns the Verified status. Device presence is never proof that a game's controls work.

`Get-TpmHardwareEnvironmentEvidence` (GPU, storage, displays) remains separate and explicitly excludes controls. This contract covers controls only and reuses the same rules: facts only, explicit UNKNOWN, no identifiers.

## Status and failure

`EvidenceStatus` is `Observed`, `SourceUnavailable`, or `Rejected`.

- `Observed`: the provider ran. `DeviceObservations` may still be empty.
- `SourceUnavailable`: the provider is missing, timed out, or failed. `DeviceObservations` is empty and `ReasonCodes` says why.
- `Rejected`: reserved for a future provider (such as HIP) whose output fails validation against this contract. The 1.0 local provider builds its own result and never returns it.

Every status is a normal result. None of them blocks the Device Survey or the Controls screen. With any status other than `Observed`, TPM behaves exactly as RC8.1 and asks the user.

## Confidence and basis

`Confidence` is `High`, `Medium`, or `Low`. `Basis` is `XInputSlotActive`, `HidUsage`, `WindowsDeviceClass`, or `NameHint`.

In 1.0 only an active XInput slot with class `XboxStylePad` may be `High`. Every other basis is at most `Medium`. `NameHint` is always `Low`, because Windows often gives arcade hardware generic names. Only `High` may pre-fill an answer. `Medium` and `Low` may only be shown as "possible".

## Time facts

`ObservationTimeUtc` is the only time fact. It is excluded from `EvidenceId`. Evidence from an earlier run of the survey or controls setup is stale and must be observed again, never reused.

A fingerprint set of the arcade encoders seen when the player taught TPM their keys is kept with the saved keys (`cabinet.json`, `EncoderFingerprints`, with the older `EncodersWhenLearned` count) and compared with a new observation. It is a note about the past, never evidence about the present, and it may only produce a hint: the controllers are the same, one was added or removed, or TPM could not check. It never changes a saved answer and never decides Verified.

## Identity and safety

`EvidenceId` is deterministic: the SHA-256 of a canonical projection of the provider identity and the sorted `DeviceObservations`, excluding `ObservationTimeUtc`. The same connected controllers always give the same `EvidenceId`.

Serial numbers, MAC addresses, user names, and machine names are never read, stored, logged, or reported. Device paths, vendor and product numbers, and device instance IDs may be read, in memory only, so that TPM can count the boards of one model and recognize the same controller again. They are never stored, logged, shown, put in a guide, a report, an issue text, a support package, or the returned evidence. What is kept is the coarse class plus a local fingerprint per recognized arcade encoder (next paragraph). `SensitiveIdentifiersIncluded` is always false and `ReadOnly` is always true. A provider that cannot meet this must return `SourceUnavailable`. Detection writes no file, changes no setting, and starts no program. Each Windows query is limited to 3 seconds. If both probes (XInput and the device list) fail, the result is `SourceUnavailable`. If only one fails, the result is still `Observed` with a reason code for the failed probe.

The schema is intentionally generic about the device list: `DeviceClass` is `XboxStylePad`, `OtherGamePad`, `Wheel`, `LightGun`, `ArcadeEncoder`, `Keyboard`, `PointerOrTrackball`, `PlayStationPad`, `NintendoPad`, `FlightStick`, `WiiRemote`, `Guitar`, `Drums`, `DancePad`, or `Unknown`. Per-game, per-emulator, and per-brand fields are not v1 fields.

`DeviceFingerprints` is optional. It is `null` unless the caller passes a salt (`Get-TpmControllerEvidence -Salt`), and `null` when the device list could not be read. Otherwise it lists one `{ DeviceClass, Fingerprint }` per recognized arcade encoder (an empty list means none was recognized). `Fingerprint` is the SHA-256 of a version tag, the salt, the class, the maker and model numbers, and a counter (1, 2, ... for identical boards of one model, so two identical encoders have two different fingerprints). It does not include an instance id, so moving a board to another USB port keeps it. A board is counted by instance id: each interface of one board shows one id, so the most ids one interface shows is the number of boards. Swapping a board for an identical one is not detectable and is not claimed. Only makers on TPM's short list (`KnownVendor`, Medium at most) get a fingerprint. The fingerprint is not part of `EvidenceId`.

The salt is 16 random bytes made once by the code that saves the player's keys (never by detection), kept as `controller-salt.txt` in the Controls state folder, and never leaves the PC. The fingerprint is never shown as a device name, never logged, and never leaves the PC.

## Allowed and forbidden use

Allowed: pre-fill a Device Survey answer (`High` only), show a "found" or "possible" hint, suggest a starting capability class to #303 marked as suggested, list the observed classes in the support package, and compare the local fingerprint set with the one saved when the keys were taught, to show a hint.

Forbidden: mark any control or game Verified or ready, write or change any profile or setting, skip a question or hide a choice, choose a controller layout without the user's confirmation, and block any screen.

## Provider seam

All TPM code calls `Get-TpmControllerEvidence` and receives `TpmControllerEvidence/v1`. In 1.0 the provider is `TpmLocalDetection`. A later HIP provider (`Hip`) must map into this same shape, is subject to every rule above, and requires the HIP contract to be versioned and pinned in this repository first (recorded on #201).

## Module boundary matrix

| Module | Responsibilities | Inputs | Outputs | Non-goals | Allowed dependencies | Forbidden dependencies | Verification gates |
|---|---|---|---|---|---|---|---|
| Controller evidence provider | Probe connected controller classes and report them with confidence and basis. | Windows device information, XInput state. | `TpmControllerEvidence/v1`. | No profile reads, no writes, no capability choice, no identifiers. | Windows device APIs, this contract. | Profiles, UserProfiles, network, EPIC or HIP code (before HIP is pinned), any write path. | Schema validation, no-identifier scan, no-file-change check, timeout check. |
| Device Survey and controls setup (consumer) | Show hints, pre-fill `High` answers, keep the user's answer authoritative. | `TpmControllerEvidence/v1`, the user's answers. | Survey answers, suggestion to #303. | No Verified status, no automatic writes from evidence. | This contract, #303 capability contract. | Provider internals, raw device data. | Override-wins test, unchanged-behavior-on-failure test. |
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
8. When both probes fail, the result is `SourceUnavailable` and callers behave as in RC8.1.
9. The result validates against the schema.
10. The same controllers give the same `EvidenceId`, and changing `ObservationTimeUtc` does not change it.
11. With two identical boards, `Count` is 2 and there are two different fingerprints. One board that shows several interfaces counts once.
12. A board moved to another USB port has the same fingerprint. Another salt gives a different fingerprint.
13. The result and the saved `cabinet.json` hold no maker or model number, instance id, or salt. The log holds none of them either.
14. Without a salt, or when the device list could not be read, `DeviceFingerprints` is `null` and the notice says it could not check. With no controller it is an empty list.
