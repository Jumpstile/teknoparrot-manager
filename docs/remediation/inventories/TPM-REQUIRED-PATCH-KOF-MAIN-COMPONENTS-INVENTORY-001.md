# KOF Maximum Impact Regulation A Main-component specification and system-invariant inventory

Status: REQUIRED inventory for `TPM-REQUIRED-PATCH-KOF-MAIN-COMPONENTS-001` under Issue #351. The exact guide profile/build, executable identity, four Main member identities, and official WineD3D 10.16 x86 byte matches are source-reviewed. Local catalog/test integration is focused-verified below; full CI and owner gates remain separate. This inventory does not establish installed-target absence or runtime compatibility.

## Component and boundary

The four independent candidates are root files `d3d8.dll`, `d3d9.dll`, `ddraw.dll`, and `wined3d.dll` from the exact KOF Main ZIP. The guide index is 689, profile code `KingofFightersMaximumImpactRegulationA`, build `King of Fighters Maximum Impact Regulation A (2007)[Taito Type X2][TP]`, executable `game.exe` SHA-256 `CC40C926E19F17DD373C87A3D83120CB6C22C2F3CA9B492E28A6178813F6256F`.

The guide note spells `dddraw.dll`; the exact official WineD3D 10.16 archive and exact Main ZIP both identify the member as `ddraw.dll`. The recipe binds the source-corroborated `ddraw.dll` spelling; no alias or second target is added.

Private source receipts: official-source proof SHA-256 `BD4A7FCA7A4659EDA2EB1BD8E054D5658C67EE3B755E0A4645AB3ED5C0BE433D`; Main-member proof SHA-256 `FF5991A81A2176F8BF0614DBCA8DE68D2F5851845308DD7871EC4AAED75B6BE1`. The Main archive is not fully hashed; only exact member identities are asserted. The runtime source role is `Main`, so the user-provided Main ZIP is the sole source selected by these recipes.

| Target / exact Main member | Size | Source SHA-1 | Source SHA-256 | Official PE machine |
|---|---:|---|---|---|
| `d3d8.dll` | 286015 | `55542B7AB1B628FC2D7057A5FBE3B9048383F9A5` | `33B625B818B450203A4FCA0CC6068B722434535B94615FF3077239079866B115` | `014C` |
| `d3d9.dll` | 381363 | `BB46749FA47DA8A79A21171B1A93E9CA7F06E75C` | `A7FBE8B9AC236CE657E966925C5C7A8C1F0B5AA19011C1B983508CC07B3D7F13` | `014C` |
| `ddraw.dll` | 928562 | `7C6B0D12A06830C184726440AEEBDFA8A3D90F4C` | `BD7E1717B82E33046C0E2CF9A402E55630F3EE3B3299892FA82684B2F7E8D0B3` | `014C` |
| `wined3d.dll` | 4145581 | `3C592F1C9956709359B50FBAD7C31F88010E7B50` | `5F74F2BB715BFAA9A94127CD830050FDA15D34C02047633053C35D85D5469926` | `014C` |

All four Main member lengths/SHA-256 values match the official WineD3D 10.16 x86 source proof; the Main source proof separately records the four SHA-1 values. The guide note says 10.16 or a recent build and calls for x86 files. The author README describes DirectX-family usage, but does not bind KOF's required files to a specific graphics API or hardware. No per-entry prerequisite or hardware predicate is inferred.

## Specification Inventory (REQUIRED)

Governing contract: existing schema-3 required-patch catalog, exact local Main ZIP-member boundary, and `SECURITY.md` section `Required game-patch source and target boundary (RC8 candidate)`. No ZIP parser or engine behavior changes.

| ID | Rule / source | Status | Implementation pointer | Verification pointer | Trace |
|---|---|---|---|---|---|
| KOF-SPEC-001 | Each recipe binds the exact profile, build, `game.exe` name/hash, `SourceRole=Main`, Main ZIP name, exact root member, size, SHA-1, and SHA-256. | Source pins verified; integration pending | Four-entry fragment and catalog | Approved private source receipts; focused exact-field test planned | Issue #351 / slice / `TPM-TRACE-001`, `TPM-EVIDENCE-001` |
| KOF-SPEC-002 | The literal guide target `dddraw.dll` is mapped only to the source-verified official/Main member `ddraw.dll`. | Verified source spelling correction; integration pending | Fragment `ddraw.dll` entry | Exact official and Main member proof | Issue #351 / slice / `TPM-EVIDENCE-001`, `TPM-TRUTH-001` |
| KOF-SPEC-003 | Each entry has one `CreateFile` operation with `BeforeState=Absent`; target equals source member; after/payload SHA-256 equals the exact member SHA-256. | Existing schema shape; new entries pending | Schema-3 loader and four recipe rows | Metadata and absent/after-state cases planned | Issue #351 / slice / `TPM-EVIDENCE-001` |
| KOF-SPEC-004 | Runtime staging reads only the named member from the recipe-named local Main ZIP, with bounded length and SHA-256 verification; it does not use the official external URL. | Existing engine boundary; KOF test pending | `New-TpmRequiredPatchPayloadStage` | Synthetic exact-member ZIP staging planned | Issue #351 / slice / `TPM-EVIDENCE-001` |
| KOF-SPEC-005 | No unverified graphics API, hardware, prerequisite, or atomic-four-file rule is encoded. | Mapped; no extra condition in entries | Four independent entries; empty prerequisite/group fields | Exact metadata assertions planned | Issue #351 / slice / `TPM-TRUTH-001` |

### Deliberately out of scope

- Whether any target is absent from an installed KOF directory. `BeforeState=Absent` is a non-overwrite policy, not an assertion about installed files.
- Whether KOF uses DirectX 7, 8, or 9 on the selected setup; no inferred API prerequisite, required combination, or all-four atomic transaction.
- Driver installation, system/Windows/PATH writes, hardware suitability, graphics correctness, WineD3D runtime compatibility, launch readiness, gameplay, or owner acceptance.
- Full Main archive hash, payload execution, or extraction of live/source archives.

## System Invariant Inventory (REQUIRED)

| ID | Invariant | Status | Implementation pointer | Verification pointer | Failure mode / trace |
|---|---|---|---|---|---|
| KOF-SII-001 | Mutation requires the exact guide profile/build/executable identity and pinned `game.exe` SHA-256. | Existing engine guard; KOF tests pending | `Get-TpmPatchPlan` | Wrong-executable refusal before mutation | Wrong-build file mutation; Issue #351 / slice / `TPM-EVIDENCE-001`, `TPM-TRUTH-001` |
| KOF-SII-002 | Each `CreateFile` acts only on an absent target; exact after-state is a no-op; unknown existing bytes are refused unchanged. | Existing engine guard; KOF tests pending | `Get-TpmPatchPlan`, `Invoke-TpmCatalogPatch` | Absent apply/read-back, exact-after idempotency, foreign-state refusal | Overwrite of user/third-party bytes; Issue #351 / `TPM-EVIDENCE-001` |
| KOF-SII-003 | Undo removes only the original file object created by its receipt; same bytes on a substituted object do not authorize deletion. | Existing engine guard; KOF tests pending | `Undo-TpmCatalogPatch` | Receipt undo and same-byte object-substitution refusal | Deletion of a file not created by the transaction; Issue #351 / `TPM-EVIDENCE-001` |
| KOF-SII-004 | Each component is independent; applying/undoing one target preserves the other three targets and unrelated siblings. | Required behavior; KOF tests pending | Per-target transaction boundary | Four-entry lifecycle loop and sibling sentinels planned | Collateral mutation or false atomicity claim; Issue #351 / `TPM-TRUTH-001` |
| KOF-SII-005 | Staging accepts only the exact named archive member and verifies size/SHA-256 before any game write. | Existing engine guard; KOF tests pending | `New-TpmRequiredPatchPayloadStage` | Synthetic Main ZIP with each exact member | Untrusted/mismatched archive bytes reaching target; Issue #351 / `TPM-EVIDENCE-001` |
| KOF-SII-006 | Source pins and synthetic transactions are not reported as installed-target state, WineD3D compatibility, setup, graphics behavior, gameplay, or owner acceptance. | Required reporting invariant | Slice, board, reconciliation | Wording review; owner-runtime remains unverified | Source proof overstated as readiness; Issue #351 / `TPM-TRUTH-001`, `TPM-OWNER-001/002/003` |

## Focused verification map

Suite: `Tests/TpmRequiredPatchKofMainComponents.Tests.ps1`. It will use isolated synthetic ZIP, game, payload, and recovery roots, and loop across all four exact metadata rows. Five cases cover field/census pins, exact member staging, absent apply/read-back plus exact-after/undo/unknown-state refusal and sibling preservation, wrong-executable refusal, and same-byte foreign-object undo refusal. Explicit Pester 5.7.1 dual-engine runs are reserved to Root; this slice runs no tests and uses no NAS input.

### Root focused verification, 2026-10-15 UTC

The combined source has69entries/25profiles/61CreateFile/eightReplaceFile. All prior64 entries and order, the engine body and product Main are unchanged. Root's independent XML review at2026-10-15T18:14:26Z verified34 specified cases per engine: KOF5, MKDX5, TMNT5, catalog2 and existing required-patch integration17. Initial fixture failures remain preserved. KOF's corrected five cases passed within a batch whose three MKDX fixture failures were subsequently corrected; the final MKDX-only five-case and Main17 workers exited0 in both engines. The focused proof is1826663DB68DC6F63B9CBDB280F9EE5183D5751E7BF058C5D0F8EB0E15B2F03E. This does not claim a new full-suite, package, graphics compatibility or owner-runtime result. Root source commit/push and integration follow the existing authorized workflow; no lane performed publication. No build or ZIP copy is authorized by this source verification.