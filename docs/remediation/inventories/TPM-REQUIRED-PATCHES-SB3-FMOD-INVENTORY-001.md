# SB3 FMOD component-restoration specification and system-invariant inventory

Status: REQUIRED specification and system-invariant inventory for the two-entry SB3 FMOD restoration slice `TPM-REQUIRED-PATCHES-SB3-FMOD-001` under Issue #351. The slice was integrated at the 56-entry checkpoint; current staging after the separate Infinity slice is 58 entries / 22 identities / 50 `CreateFile` / eight `ReplaceFile`, catalog SHA-256 `F86F09A8BD2749DC9C4531CD1D00A69BF07D85B14A8D281D33767732ED5B720A`, engine SHA-256 `7AFAE497F5EFED0BE5F94497D4A7A5C25C073743485B700A7498B1A34681F6E4` (catalog pin only). Owner-runtime acceptance remains separate; the inventory does not establish installed FMOD version, pair compatibility, or complete setup.

## Component and boundary

The catalog adds two independent exact-build absent-file restorations for SB3 1.91 x64: `fmod64.dll` and `fmodstudio64.dll`. Each targets its exact `fnfmega_Data/Plugins/x86_64` Main member path. The two files are separate transactions; the sibling DLL is not a prerequisite and remains untouched. The engine does not create missing parent directories.

The immutable fragment is `tools/required-patches/fragments/plugins-sb3-fmod-components-20261015.json`, SHA-256 `0CC045CB454D802804E46FC25F049687164F48E55ACACFC3D38BA63AB528E418`. The portable test is `Tests/TpmRequiredPatchSb3FmodLane.Tests.ps1`, SHA-256 `D288325EB8BAD7D13C80499EB3E45091E99BBB89AA0E09C825C1692B5611FA05`. The accepted public boundary note is `tools/required-patches/fragments/sb3-fmod-component-boundary-20261015.md`, SHA-256 `EA90F3C8E4EF90061D34E350E65275CCC1557CC49AF7DCF2450A825CDAA2E7A4`.

The exact catalog BuildName is `Super Bikes 3 (1.91 x64)(2021-10-01)[Raw Thrills][TP]`; the exact Main ZIP SourceSet is `Super Bikes 3 (1.91 x64)(2021-10-01)[Raw Thrills PC][TP].zip`. The Main `PC` suffix is preserved as source identity and is not normalized to the guide BuildName.

## Specification Inventory (REQUIRED)

Governing contract: schema-3 recipe metadata and the exact named local ZIP-member rules in `scripts/TpmRequiredPatchEngine.ps1` and `SECURITY.md` section "Required game-patch source and target boundary (RC8 candidate)". This inventory covers only the two accepted SB3 Main-source component restorations.

| ID | Rule / source | Status | Implementation pointer | Verification pointer | Trace |
|---|---|---|---|---|---|
| SBF-SPEC-001 | Each entry binds ProfileId `SB3`, the exact guide BuildName, `fnfmega.exe` and exact executable SHA-256, exact Main ZIP SourceSet/member, size, SHA-1 and SHA-256. Preserve the guide BuildName/source ZIP naming difference. | Implemented | Schema-3 catalog loader; accepted fragment | `binds both exact x64 component members to the 1.91 Main build and absent-only targets` | Issue #351 / `TPM-REQUIRED-PATCHES-SB3-FMOD-001` / `TPM-TRACE-001`, `TPM-EVIDENCE-001` |
| SBF-SPEC-002 | Each entry has one `CreateFile` operation; `BeforeState` is `Absent`; source, after, and payload SHA-256 pins agree with the exact row. No hardware predicate or version prerequisite is inferred. | Implemented | Schema-3 catalog loader; exact frozen entries | `binds both exact x64 component members to the 1.91 Main build and absent-only targets`; bounded JSON field scan | Issue #351 / slice / `TPM-TRACE-001`, `TPM-TRUTH-001` |
| SBF-SPEC-003 | Each named ZIP member is subject to the shared stage function's exact-member, size, and SHA-256 checks; the two-entry fragment remains two independent one-file operations, not an atomic pair. The focused FMOD suite does not invoke ZIP staging. | Implemented | `New-TpmRequiredPatchPayloadStage` and one-operation catalog entries | The FMOD suite proves metadata and synthetic file lifecycle only; separate exact Main source evidence is recorded in the accepted boundary note/source proof | Issue #351 / slice / `TPM-EVIDENCE-001` |

### Deliberately out of scope

- FMOD DLL file-version metadata and installed-runtime compatibility.
- Pair compatibility, pair completeness, or atomic all-or-nothing installation.
- BepInEx, SB3 plugin, controls, setup, game launch, audio, or gameplay validation.
- Source downloads, other plugin-lane artifacts, or broader source-archive coverage.

Layering: exact Main bytes and successful synthetic transaction tests establish the bounded file recipe only. They do not establish the version or compatibility of an installed DLL or the state of its sibling.

## System Invariant Inventory (REQUIRED)

| ID | Invariant | Status | Implementation pointer | Verification pointer | Failure mode / trace |
|---|---|---|---|---|---|
| SBF-SII-001 | Planning is bound to the exact SB3 profile/build/executable hash; the two rows do not authorize a different executable revision. | Implemented | `Get-TpmPatchPlan` | Exact metadata test plus synthetic fixture setup | Wrong-build file mutation; Issue #351 / slice / `TPM-EVIDENCE-001`, `TPM-TRUTH-001` |
| SBF-SII-002 | Each absent target is created independently; exact after-state is skipped; unknown present bytes are refused and preserved. | Implemented | `Get-TpmPatchPlan`, `Invoke-TpmCatalogPatch` | `applies each absent component, skips exact repeats, receipt-undoes, and preserves foreign bytes` | Existing user bytes are overwritten; Issue #351 / slice / `TPM-EVIDENCE-001` |
| SBF-SII-003 | The target parent must already be a safe directory; the recipe does not create it or inspect/require the sibling DLL. | Implemented | Existing path and prerequisite handling | Shared missing-parent refusal is tested by the Main 152-case suite; FMOD suite separately asserts sibling preservation | Unsafe parent creation or unsupported pair inference; Issue #351 / slice / `TPM-EVIDENCE-001`, `TPM-TRUTH-001` |
| SBF-SII-004 | Source staging is governed by the shared exact-member, size, and SHA-256 checks; the FMOD focused suite does not directly exercise ZIP staging. | Implemented | `New-TpmRequiredPatchPayloadStage` | Public boundary note plus independent exact-Main source evidence; no ZIP-staging assertion in `TpmRequiredPatchSb3FmodLane.Tests.ps1` | Wrong archive member reaches an installed target; Issue #351 / slice / `TPM-EVIDENCE-001` |
| SBF-SII-005 | Undo for each component is authorized by its own valid receipt and file-object identity; foreign bytes remain untouched. | Implemented | `Undo-TpmCatalogPatch` | Receipt-undo and foreign-byte refusal assertions in the accepted standalone test | Undo removes a file not created by the transaction; Issue #351 / slice / `TPM-EVIDENCE-001` |
| SBF-SII-006 | File repair evidence is not represented as FMOD version verification, pair compatibility, complete SB3 setup, or gameplay proof. | Implemented | User/architecture wording; control board/reconciliation | Explicit limits in boundary note and staging report | File-byte evidence is overstated as runtime readiness; Issue #351 / slice / `TPM-TRUTH-001`, `TPM-OWNER-001`, `TPM-OWNER-002`, `TPM-OWNER-003` |

## Current verification boundary

At the 56-entry checkpoint, the FMOD suite passed 2/2 under Pester 5.7.1 on PowerShell 7 and Windows PowerShell 5.1. After the separate Infinity addition, the targeted v3 Infinity-plus-central assertions passed 3/3 under each engine with zero failures/skips and no input changes; the FMOD suite was not rerun. Receipts and timestamps are recorded in the current staging reconciliation. No game, DLL, or source payload is executed by these tests.
