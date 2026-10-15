# Infinity Blade FX Main-component specification and system-invariant inventory

Status: REQUIRED specification and system-invariant inventory for the two-entry `TPM-REQUIRED-PATCHES-INFINITYBLADEFX-001` slice under Issue #351. Current staging aggregate is 58 entries / 22 identities / 50 `CreateFile` / eight `ReplaceFile`, catalog SHA-256 `F86F09A8BD2749DC9C4531CD1D00A69BF07D85B14A8D281D33767732ED5B720A`, engine SHA-256 `7AFAE497F5EFED0BE5F94497D4A7A5C25C073743485B700A7498B1A34681F6E4` (catalog pin only). This inventory defines catalog and transaction scope only; owner-runtime acceptance remains separate.

## Component and boundary

The catalog adds two exact-build absent-file restorations for `Binaries/Win32/matrix32.dll` and `Binaries/Win32/dinput8.dll` in Infinity Blade FX 1.02. Each has independent presence-only prerequisites for `Binaries/Win32/matrix32.TEKNOPARROT.dll` and `Binaries/Win32/TPFIX.ini`. These repairs do not install, rename, or configure the loader, do not select the user's first-launch path, and do not establish complete setup or compatibility.

The accepted fragment is `tools/required-patches/fragments/support-infinitybladefx-main-components-20261015.json`, SHA-256 `45AA403A5DB320CD31292EC6CA5F0A9F7AB9A6DABC96F76147CEA13E86FB1472`. The accepted portable suite is `Tests/TpmRequiredPatchInfinityBladeFxLane.Tests.ps1`, SHA-256 `E9C7C4095B3170A9C2851A37C4D5BB297EE5B83C608E60A556098872999B880F`.

## Specification Inventory (REQUIRED)

Governing contract: schema-3 recipe metadata and file-operation semantics documented by `scripts/TpmRequiredPatchEngine.ps1` and `SECURITY.md`, plus the accepted exact-build Main member pins. This slice adds only two single-file `CreateFile` operations.

| ID | Rule / source | Status | Implementation pointer | Verification pointer | Trace |
|---|---|---|---|---|---|
| IFX-SPEC-001 | Both recipes bind ProfileId `InfinityBladeFX`, exact build `Infinity Blade FX (1.02)(2020)[Adrenaline PC][TP]`, executable `Binaries/Win32/SwordGame.exe`, and executable SHA-256 `8E605C3748C6D3D45832F40316C1FEC35D2507E31E51A5F85DCB3B664DA72D24`. | Implemented | Exact fragment rows; catalog loader | `binds exact 1.02 Main DLL members and excludes the separate rename/config/first-run procedure` | Issue #351 / `TPM-REQUIRED-PATCHES-INFINITYBLADEFX-001` / `TPM-TRACE-001`, `TPM-EVIDENCE-001` |
| IFX-SPEC-002 | Each recipe pins its Main SourceSet, exact SourceEntry, size, SHA-1 identity metadata, and SHA-256; operation target equals SourceEntry and AfterSha256/PayloadSha256 equal SourceSha256. | Implemented | Exact fragment rows; schema-3 catalog loader | Exact-fragment metadata assertions in the accepted suite; central integrated count/pin/ID assertion | Issue #351 / slice / `TPM-TRACE-001`, `TPM-EVIDENCE-001` |
| IFX-SPEC-003 | Each recipe contains one `CreateFile` operation with `BeforeState=Absent`; no replace or shared multi-file transaction is added. | Implemented | Exact fragment rows; `Get-TpmPatchPlan`, `Invoke-TpmCatalogPatch` | Metadata case and synthetic transaction case | Issue #351 / slice / `TPM-TRACE-001`, `TPM-EVIDENCE-001` |
| IFX-SPEC-004 | Both prerequisites are file-presence checks only: `Binaries/Win32/matrix32.TEKNOPARROT.dll` and `Binaries/Win32/TPFIX.ini`. No content hash, version, INI key/value, or pair-compatibility claim is made. | Implemented | Exact fragment prerequisites; `Test-TpmRequiredPatchPrerequisites` | Metadata case and synthetic prerequisite lifecycle case | Issue #351 / slice / `TPM-EVIDENCE-001`, `TPM-TRUTH-001` |
| IFX-SPEC-005 | The focused Infinity suite uses synthetic fixture payloads and does not call `New-TpmRequiredPatchPayloadStage`, open a ZIP, or stage a Main member. | Implemented | Accepted focused suite | The two named Infinity tests; ZIP staging is not claimed by this suite | Issue #351 / slice / `TPM-TRUTH-001` |

### Deliberately out of scope

- The authored procedure preserves the original `matrix32.dll` as `matrix32.TEKNOPARROT.dll`; the TPM recipes perform no automatic rename, `TPFIX.ini` edit, or first-launch path selection. The first-launch selection is the TeknoParrot installation's `TeknoParrot.dll`.
- Verifying prerequisite file bytes, DLL versions, component-pair compatibility, or whether all installation steps are complete.
- Executing DLLs, launching the game, source downloads, owner-runtime proof, or gameplay/visual compatibility.
- Replacing existing target or prerequisite files; the operations are absent-only and independent, not atomic.

Layering: exact metadata, presence-only prerequisites, and synthetic transaction results prove only catalog semantics and isolated file behavior. They do not prove source ZIP staging, complete installation, game startup, compatibility, or owner acceptance.

## System Invariant Inventory (REQUIRED)

| ID | Invariant | Status | Implementation pointer | Verification pointer | Failure mode / trace |
|---|---|---|---|---|---|
| IFX-SII-001 | A recipe is applicable only to the exact profile/build/executable identity and executable SHA-256. | Implemented | `Get-TpmPatchPlan` | Shared exact executable guard; central catalog assertion binds both rows | Wrong-build mutation; Issue #351 / slice / `TPM-EVIDENCE-001`, `TPM-TRUTH-001` |
| IFX-SII-002 | The original matrix32 component and TPFIX.ini must each exist; only path/file presence is checked. Missing either prerequisite prevents the recipe from being Ready. | Implemented | `Test-TpmRequiredPatchPrerequisites` | `restores each absent DLL only, skips exact repeats, receipt-undoes, and preserves sibling/config bytes` | False setup assurance or mutation without the authored prerequisites; Issue #351 / slice / `TPM-EVIDENCE-001` |
| IFX-SII-003 | Each absent target may be created from the recipe payload; exact after-state is a no-op; unknown present bytes are preserved and refused. | Implemented | `Get-TpmPatchPlan`, `Invoke-TpmCatalogPatch` | Synthetic lifecycle test for each entry | Overwrite of user/third-party bytes; Issue #351 / slice / `TPM-EVIDENCE-001` |
| IFX-SII-004 | Undo requires the valid recipe receipt and the file identity recorded by the production transaction; sibling and prerequisite files remain unchanged. | Implemented | `Undo-TpmCatalogPatch` receipt/object checks | Synthetic lifecycle test asserts receipt undo and sibling/config preservation | Removal of a file not created by this transaction; Issue #351 / slice / `TPM-EVIDENCE-001` |
| IFX-SII-005 | The two recipes are independent single-file transactions; successful restoration of one does not prove the other is present or compatible. | Implemented | Distinct fragment entries and operation targets | Test loops over each entry independently; no pair-atomicity claim | Partial install is mistaken for complete setup; Issue #351 / slice / `TPM-TRUTH-001`, `TPM-OWNER-001` |
| IFX-SII-006 | Neither source pins nor synthetic transactions imply loader installation, correct first-launch path, DLL compatibility, game startup, or gameplay success. | Implemented | User/architecture wording; control board/reconciliation status | Scope docs and owner-runtime checklist remain pending | Evidence overstated as readiness; Issue #351 / slice / `TPM-TRUTH-001`, `TPM-OWNER-001`, `TPM-OWNER-002`, `TPM-OWNER-003` |

## Current verification boundary

The v3 focused delta completed 2026-10-15T08:16:41.7586051Z (PowerShell 7.6.7) and 2026-10-15T08:17:17.1661187Z (Windows PowerShell 5.1.26100.9549), each with Pester 5.7.1: Infinity 2/2 and central 1/1 passed, zero failures/skips, 1487 central tests not run by the intentional name filter, and zero input changes. The suite does not stage a ZIP member. Owner runtime/gameplay and setup readiness remain pending.
