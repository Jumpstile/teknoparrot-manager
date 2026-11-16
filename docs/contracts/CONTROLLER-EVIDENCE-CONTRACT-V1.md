# Controller Evidence Contract, Version 1

Status: draft for review. Applies to TPM 1.0. Tracking issue: #410.
Schema: `docs/contracts/ControllerEvidenceV1.schema.json`
Related issues: #200 (controller mapping), #201 (full HIP integration, post-1.0), #303 (capability contract), #306 (Xbox XInput P1 apply), #307 (verification).

## 1. Purpose

Control propagation needs to know what controllers are connected. This contract defines the one result shape that answers that question, who may produce it, who may use it, and what it is never allowed to do.

The result is evidence, not a decision. It can suggest. It cannot change a file, and it cannot say a game's controls work.

## 2. Contract types (see docs/governance/tpm-contract-types.md)

| Type | Statement |
|---|---|
| UX contract | Detection only pre-fills or suggests an answer. The user can always change it. If detection finds nothing or fails, the screen is exactly the same as before. |
| Mutation contract | None. Detection writes no file, changes no setting, and starts no program. The only allowed output is the in-memory result and a log line listing detected classes. |
| Progress contract | Detection is bounded and fast (target under 2 seconds, hard stop at 5 seconds). No progress surface is needed. A timeout returns UNKNOWN. |
| Repair contract | Not a repair. No profiles are read for detection. |
| Support evidence contract | The support package may list detected classes and the provider name. It must never list identifiers (section 6). |
| Package/runtime contract | The provider is part of the main script. The schema and this document ship in the repository only. |

## 3. Result shape (`ControllerEvidenceV1`)

| Field | Meaning |
|---|---|
| `ContractVersion` | Always `ControllerEvidenceV1`. |
| `Provider` | Who produced it: `TpmLocalDetection` in 1.0. A future HIP adapter uses `Hip`. |
| `ProviderVersion` | Version text of the provider. |
| `Status` | `OK`, `PARTIAL`, `UNKNOWN` or `FAILED`. |
| `ObservedAtUtc` | When detection ran (ISO 8601). Evidence older than the current survey or propagation run is stale and must not be reused. |
| `Devices` | List of detected controller entries (section 4). May be empty. |
| `SensitiveIdentifiersIncluded` | Always false. |
| `Notes` | Plain-words reasons for PARTIAL, UNKNOWN or FAILED. |

`UNKNOWN` and `FAILED` are normal results. They never stop TPM.

## 4. Device entry

| Field | Meaning |
|---|---|
| `Class` | One of `XboxStylePad`, `OtherGamePad`, `Wheel`, `LightGun`, `ArcadeEncoder`, `Keyboard`, `PointerOrTrackball`, `Unknown`. |
| `Confidence` | `High`, `Medium`, `Low`. Only `High` may pre-select an answer. `Medium` and `Low` may be shown as "possible" and never pre-selected. |
| `Basis` | Why the class was chosen: `XInputSlotActive`, `HidUsage`, `WindowsDeviceClass`, `NameHint`. Name-only evidence is always `Low`. |
| `Count` | How many devices of this class. |

1.0 rule: only an active XInput slot can be `High`. Everything else tops out at `Medium`, because Windows often gives arcade hardware generic names.

## 5. Allowed use

Callers may use the result to:

1. Pre-fill a Device Survey question when the class is `High`.
2. Show a "found" or "possible" hint next to a question.
3. Suggest a starting capability class to the #303 profile contract, marked as suggested.
4. Add the class list to the support package.

Callers must not use the result to:

1. Mark any control or game as `Verified`, ready, or configured.
2. Write, change, copy or delete any profile or setting.
3. Skip a question, hide a choice, or block a screen.
4. Choose a reference game or archetype without the user's confirmation.

The user's answer always wins over the result.

## 6. Privacy

Never read, store, log, or include in any report: serial numbers, device instance IDs, full device paths, MAC addresses, user names, or machine names. Vendor and product numbers are not collected in 1.0 either. Only the class, confidence, basis, and count leave the provider.

## 7. Failure behavior (fail closed)

| Situation | Result | TPM behavior |
|---|---|---|
| No controllers found | `OK`, empty `Devices` | Ask the user as today. |
| Detection throws or times out | `FAILED` | Ask the user as today. Log one line. |
| Some sources fail | `PARTIAL` | Use only `High` entries. Ask for the rest. |
| Two sources disagree | Lower the confidence to `Low` | Show as possible only. |
| Provider not present | `UNKNOWN` | Ask the user as today. |

## 8. Provider seam and HIP

All TPM code calls one function, `Get-TpmControllerEvidence`, and receives `ControllerEvidenceV1`. The provider behind it is replaceable.

A future HIP provider may fill the same shape. When it does:

1. Its output is mapped into this shape. This contract does not change.
2. HIP evidence is subject to every rule above, including: it can suggest, it cannot verify, and unknown means ask.
3. The HIP contract must be versioned and pinned in this repository before TPM uses it (decision recorded on #201).

## 9. Relation to other contracts

- #303 (capability contract): this result may suggest a capability class. The user's explicit selection stays authoritative.
- #306 (Xbox XInput P1 apply): may use an `XboxStylePad` suggestion to offer the Xbox baseline. Writing is #306's job and passes its own backup, preview and rollback gates.
- #307 (verification): only this model may mark gameplay as verified.
- RC8 shared hardware evidence (`Get-TpmHardwareEnvironmentEvidence`): separate. It covers GPU, storage and displays, and explicitly excludes controls. This contract covers controls only and reuses the same ideas (facts only, explicit UNKNOWN, no identifiers).

## 10. Required tests

1. Provider throws: result is `FAILED`, callers behave as in RC8.1.
2. Empty result: survey is unchanged.
3. Name-only evidence is `Low` and never pre-selects.
4. Only an active XInput slot yields `High`.
5. Result contains no identifiers (checked against a deny list of field names and patterns).
6. No file is created or changed by detection (before and after file listing).
7. The user's answer overrides a pre-filled value.
8. Timeout returns `UNKNOWN` within the hard stop.
9. Result validates against the schema.
