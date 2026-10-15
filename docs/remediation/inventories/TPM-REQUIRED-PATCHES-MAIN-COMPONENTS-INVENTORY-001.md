# Main-component restoration specification and system-invariant inventory

Status: REQUIRED specification and system-invariant inventory for the 30-entry Main-component restoration slice `TPM-REQUIRED-PATCHES-MAIN-COMPONENTS-001` under Issue #351. This slice was integrated at the 56-entry checkpoint; current staging after the separate Infinity slice is 58 entries / 22 identities / 50 `CreateFile` / eight `ReplaceFile`, catalog SHA-256 `F86F09A8BD2749DC9C4531CD1D00A69BF07D85B14A8D281D33767732ED5B720A`, engine SHA-256 `7AFAE497F5EFED0BE5F94497D4A7A5C25C073743485B700A7498B1A34681F6E4` (catalog pin only). Owner-runtime acceptance remains separate.

## Component and boundary

The catalog adds 30 exact-build absent-file restorations: 14 Hummer 1.0, 14 Hummer Extreme 1.0, and two Primeval Hunt 1.0 shader components. The shared engine owns source staging, planning, transactional creation, read-back, receipts, and undo. The entries do not replace existing files, install a new shader patch, or prove that the whole game setup is complete.

The immutable entry source is `tools/required-patches/fragments/native-main-component-restorations-20261015.json`, SHA-256 `54AB378F9F13213F67C47A628DDEFE3AA0F4FEB8BE2E1BCE51B87818E247D38E`. The portable regression suite is `Tests/TpmRequiredPatchNativeMainComponentRestorations.Tests.ps1`, SHA-256 `673D1C434033E1076CA4BE6174D535B5A1C0353651B9EA6D1B63EEF3340C88C7`.

## Specification Inventory (REQUIRED)

Governing contract: schema-3 recipe metadata and the local ZIP-member behavior documented by `scripts/TpmRequiredPatchEngine.ps1` and `SECURITY.md` section "Required game-patch source and target boundary (RC8 candidate)". This inventory covers only the single-file Main-source operations enabled by this slice.

| ID | Rule / source | Status | Implementation pointer | Verification pointer | Trace |
|---|---|---|---|---|---|
| NMC-SPEC-001 | Each row binds the exact ProfileId, BuildName, executable name/hash, Main SourceSet, SourceEntry, SourceSize, SourceSha1, and SourceSha256. SHA-1 is source identity metadata; runtime payload integrity uses SHA-256. | Implemented | Schema-3 catalog loader; `New-TpmRequiredPatchPayloadStage` | `binds the complete fragment to all 30 independent frozen Main rows`; `stages synthetic Main ZIP member for source row <Index>` | Issue #351 / `TPM-REQUIRED-PATCHES-MAIN-COMPONENTS-001` / `TPM-TRACE-001`, `TPM-EVIDENCE-001` |
| NMC-SPEC-002 | Each row has one `CreateFile` operation; `BeforeState` is `Absent`; `AfterSha256` and `PayloadSha256` equal the exact source SHA-256; target equals the declared recipe target. | Implemented | Schema-3 catalog loader and `New-TpmRequiredPatchPayloadStage` | `binds the complete fragment to all 30 independent frozen Main rows`; central aggregate count/ID assertions | Issue #351 / slice / `TPM-TRACE-001`, `TPM-EVIDENCE-001` |
| NMC-SPEC-003 | The 30 rows do not add hardware predicates or `AllowExecutableSelfPatch`; no additional operation or prerequisite is inferred. | Implemented | Exact frozen fragment | Independent JSON-field scan plus full metadata assertions in the portable suite | Issue #351 / slice / `TPM-TRACE-001`, `TPM-TRUTH-001` |
| NMC-SPEC-004 | Archive staging reads only the recipe-named local ZIP and exact member, within existing size limits, and verifies size and SHA-256 before a plan can mutate a target. | Implemented | `New-TpmRequiredPatchPayloadStage` | `stages synthetic Main ZIP member for source row <Index>`; `imports the exact 30-entry fragment through the production planner before the executable identity guard` | Issue #351 / slice / `TPM-EVIDENCE-001` |

### Deliberately out of scope

- Full semantic coverage of all guide records or source archives; this is a 30-row exact component subset.
- Proving shader-set atomicity, visual compatibility, or gameplay behavior.
- Hummer Extreme frame-count settings; Primeval Hunt `ElfLdr2` library-copy identity; Primeval modern NVIDIA fog behavior.
- Game launching, executable/payload execution, profile installation, controls, or readiness.

Layering: a catalog parse, staged exact member, or successful local transaction proves only the recipe/file operation. It does not prove install completeness, game startup, visual correctness, or owner acceptance.

## System Invariant Inventory (REQUIRED)

| ID | Invariant | Status | Implementation pointer | Verification pointer | Failure mode / trace |
|---|---|---|---|---|---|
| NMC-SII-001 | A recipe plan requires the exact profile/build/executable identity and exact executable SHA-256 before any target mutation. | Implemented | `Get-TpmPatchPlan` | `refuses wrong executable without target or recovery mutation for row <Index>` | Wrong-build mutation; Issue #351 / slice / `TPM-EVIDENCE-001`, `TPM-TRUTH-001` |
| NMC-SII-002 | Creation is allowed only for an absent target; exact after-state is a no-op; unknown present bytes are preserved and refused. | Implemented | `Get-TpmPatchPlan`, `Invoke-TpmCatalogPatch` | `lifecycle row <Index>: apply, no-op, undo, and foreign-byte refusal` | Overwrite of user/third-party bytes; Issue #351 / slice / `TPM-EVIDENCE-001` |
| NMC-SII-003 | The engine does not create missing target parent directories; every path must pass the existing canonical containment and reparse guards. | Implemented | Existing target-path validation in `Get-TpmPatchPlan` | Missing-parent refusal case in `TpmRequiredPatchNativeMainComponentRestorations.Tests.ps1` | Implicit or unsafe path mutation; Issue #351 / slice / `TPM-EVIDENCE-001` |
| NMC-SII-004 | Only the exact named source member is staged beneath the TPM-owned temporary root; runtime staging enforces pinned size and SHA-256. SourceSha1 is source identity metadata and is not recomputed or compared by the staging function. | Implemented | `New-TpmRequiredPatchPayloadStage` | `stages synthetic Main ZIP member for source row <Index>` for all 30 rows; exact SourceSha1 values are asserted in the independent frozen-row metadata test | Substituted or unrelated source bytes reach a target; Issue #351 / slice / `TPM-EVIDENCE-001` |
| NMC-SII-005 | Undo requires the recipe's valid receipt and the original created-file object identity; same bytes on a substituted object are not sufficient. | Implemented | `Undo-TpmCatalogPatch` receipt/object checks | `refuses receipt undo after same-byte replacement changes object identity for row <Index>` | Removal of a file not created by this transaction; Issue #351 / slice / `TPM-EVIDENCE-001` |
| NMC-SII-006 | Source pins and file transaction results are not reported as setup, compatibility, gameplay, or release proof. | Implemented | User/architecture wording; control board/reconciliation status | Scope docs and staging reconciliation; owner-runtime checklist remains pending | Source evidence is overstated as readiness; Issue #351 / slice / `TPM-TRUTH-001`, `TPM-OWNER-001`, `TPM-OWNER-002`, `TPM-OWNER-003` |

## Current verification boundary

The 152-case native suite passed under Pester 5.7.1 on PowerShell 7.6.7 and Windows PowerShell 5.1 at the 56-entry checkpoint. After the separate Infinity addition, the targeted v3 Infinity-plus-central assertions passed 3/3 under each engine with zero failures/skips and no input changes; the 152-case suite was not rerun. Receipts and timestamps are recorded in the current staging reconciliation. Owner runtime/gameplay remains pending.
