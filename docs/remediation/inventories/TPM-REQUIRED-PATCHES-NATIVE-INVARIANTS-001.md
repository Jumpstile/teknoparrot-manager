# Native required-patch recipe system invariant inventory

Status: implementation basis for the first exact-source batch; full native-family reconciliation remains open under NRP-11.

## Component and boundary

The Issue #351 recipe catalog and `TpmRequiredPatchEngine.ps1` evaluate a single exact recipe against a local installed game folder and user-supplied ZIP member. The engine may stage, back up, replace, verify, and receipt-undo approved files. It does not prove registration, configuration, controls, launch, gameplay, or readiness. Game payloads are never executed by this lane.

This component has REQUIRED system-invariant coverage: it implements transactional writes, recovery receipts, race coordination, and multi-state patch lifecycles.

## Governing input inventory

- Complete guide corpus: 1,888 retained profile records, 259 own-string fields with broad matches across 180 profiles; 97 GPU indicators. The lexical register is not a semantic patch count.
- Curated guide ledger: 95 references only; v4 delta records 13 implemented components, 50 held patch components, and 32 separate non-patch references. The v4 delta explicitly says it is not the full semantic guide enumeration.
- Source census: 1,272 retained source objects; 1,270 converted/verified; 2 held reader/safety failures; 308 production ZIPs, 260 unique archive byte identities, 12,132 internal production files, and 146,102 internal-member occurrences. These counts do not equal distinct patch counts or establish installation applicability.
- Full raw guide records, candidate evidence, source-scoped inventory, all source identities, owner receipts, and every catalog entry are checked as native recipe coverage work proceeds. Provenance filenames and raw-source hashes alone do not establish ZIP member bytes.

## Invariants

| ID | Checkable invariant | Failure mode | Verification |
|---|---|---|---|
| NRP-1 | A recipe is selectable only for exactly one declared profile/build/executable identity; duplicate/mismatched IDs refuse. | A fix is applied to a different game or revision. | Catalog validation and exact-profile/executable plan tests. |
| NRP-2 | Source bytes come only from the named local source role/set/member and must pass bounded size, SHA-1 metadata, and SHA-256 runtime payload pins. | Unrelated or substituted ZIP bytes reach the target. | Exact-member staging tests and source identity receipts. |
| NRP-3 | Every replacement accepts only the exact declared before-state or exact after-state; after-state is a no-op; all other, unreadable, absent, partial, or changed states refuse. | Existing user state is overwritten or misreported. | Before/after/unknown/absent state behavior matrix. |
| NRP-4 | Self-executable replacement is denied by default. The only exception is an explicit schema-3 single-file opt-in whose sole ReplaceFile target is the exact declared executable and whose before/after states are both pinned. | General self-patching becomes possible through ordinary recipes or multi-file transactions. | Default-denial test, opt-in structural validation matrix, and multi-file refusal tests. |
| NRP-5 | Apply and undo bind opened filesystem objects to canonical paths, identities, and expected hashes at the publication boundary; a race-substituted object is never overwritten or deleted as if owned. | A TOCTOU race mutates unrelated executable bytes. | Synthetic validation-hook replacement race test; handle identity/readback assertions. |
| NRP-6 | Successful apply has a verified pre-state backup, exact after-state readback, and a receipt bound to catalog/profile/game/target/object identity. | A patch is reported applied without recoverable evidence. | Backup/apply/receipt assertions in focused tests. |
| NRP-7 | Undo is authorized only by a valid receipt and exact applied object/hash; undo restores exact before bytes and preserves foreign changes. | Undo destroys later third-party updates or restores unrelated bytes. | Exact receipt undo, wrong object/hash refusal, and restore identity tests. |
| NRP-8 | Failed promotion restores the original object when possible; unverified rollback preserves evidence and never returns clean success. | Partial mutation or false success. | Race/failure injection and rollback state checks. |
| NRP-9 | Existing schema 1/2/3 behavior and all non-self recipe semantics remain unchanged. Unknown multi-file self-executable layouts remain denied. | Legacy recipe contract breaks or exception scope expands silently. | Existing focused regressions plus explicit non-self and schema compatibility tests. |
| NRP-10 | Source identity, catalog support, owner-installed state, runtime behavior, and release authorization remain separate evidence classes. | Source matching or patch success is presented as playability/readiness. | Documentation, control-board status, and owner-smoke boundary. |
| NRP-11 | Native-family mapping includes the complete cached guide field/profile and source inventories, not only the curated 95-row set; every candidate is labeled supported, held with missing evidence, or non-patch. | Narrow curation is mistaken for exhaustive coverage. | Reconciled per-family candidate/held/non-patch ledger with exact input files and receipts. |
| NRP-12 | Cross Raid IC-card source material is not treated as a native executable/graphics recipe; no shared root card files are mutated automatically. | Progress is corrupted by mixing shared card identity/state across Cross Elysion and Cross Raid. | Explicit lane scope boundary and held reason; no recipe/test authorizes card writes. |

## External format and API boundary

ZIP archive member selection remains the existing exact-name, bounded-stream contract in `New-TpmRequiredPatchPayloadStage`; this slice does not add new archive formats, Zstandard decoding, or source acquisition. The native self-executable opt-in must reuse the engine's existing opened-handle identity checks and no-replace promotion primitives. It must not create a new general-purpose executable patch API or relax the default self-target denial.

## Deliberately out of scope

- iDmac/JVS/NESiCA drivers/loaders and BepInEx-managed plugins belong to separate lanes.
- Unverified/unsupported archive formats, payload rights, hardware-to-game adapter association, install state, and owner gameplay are not inferred from source names, DAT metadata, guide notes, or byte equality.
- Cross Raid IC-card files require game-specific owner state and have shared-root filename hazards; automated card mutation is outside this transaction engine slice.

## Current native-lane classification -- 2026-10-15

- Supported in this candidate, source-pinned and hardware/build guarded:
  Sonic Dash Extreme exact executable before/after; Cross Raid 1.05 Ver A
  AMD/NVIDIA shader alternatives; VF5R 1.001 AMD/NVIDIA shader alternatives.
  Cross Raid ReadMes state 1.05 but do not name Ver A; compatibility remains
  unproven. No game execution or runtime outcome is claimed.
- Checked but research-held: Cross Raid 1.00 AMD lacks an exact matching Main
  target; Primeval Hunt source after-state bytes already match Main and no
  before-state is established (research hold, not an owner blocker); Ghost
  Squad Evolution ELF2 source is singular `shader` against plural guide
  wording and has unresolved full member mapping plus an unproven AMD
  `EnableAmdFix` prerequisite; WMMT3 has 38 candidate members requiring exact
  path/deduplication and multi-file staging; Hummer and Hummer Extreme require
  complete operation mapping and multi-file source staging.
- Not enabled or excluded: Cross Raid black-texture bytes match Main; no
  separate replacement is enabled, and patch-versus-absent-restoration
  classification is not adjudicated. IC-card automation belongs outside this
  file-patch transaction lane; iDmac/JVS/NESiCA and managed plugin payloads
  belong to other lanes.
- NRP-11 remains open. The 95-row curated register and this first-batch
  classification do not establish full semantic coverage of the cached guide
  and source inventories.
