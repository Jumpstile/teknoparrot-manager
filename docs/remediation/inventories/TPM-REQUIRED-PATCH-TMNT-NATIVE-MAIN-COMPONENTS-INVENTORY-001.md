# TMNT 1.59 Main-component specification and system-invariant inventory

Status: REQUIRED inventory for `TPM-REQUIRED-PATCH-TMNT-NATIVE-MAIN-COMPONENTS-001` under Issue #351. The two exact source members and executable identity are owner-reviewed; catalog integration and focused transaction verification are pending. This inventory does not claim installed-target absence or runtime compatibility.

## Component and boundary

This slice proposes two independent absent-only restorations from the exact TMNT 1.59 Main build: `TMNT_Data/Plugins/x86_64/OrenVid.dll` and `TMNT_Data/Plugins/x86_64/PK-UnityPlugin.dll`. The source proof records one exact member occurrence for each, ZIP method 8 (Deflate), and exact size/SHA-1/SHA-256. The unique `TMNT.exe` SHA-256 matches the existing catalog anchor. No source archive path or private evidence path is published here.

The engine owns source staging, planning, transactional creation, read-back, receipts, and undo. The rows do not install BepInEx, edit configuration, establish that either installed target is missing, or prove that both components are required together.

## Specification Inventory (REQUIRED)

Governing contract: the existing schema-3 required-patch catalog and exact local ZIP-member boundary documented by `scripts/TpmRequiredPatchEngine.ps1` and `SECURITY.md`, section `Required game-patch source and target boundary (RC8 candidate)`. No ZIP parser or engine policy is changed by this slice.

| ID | Rule / source | Status | Implementation pointer | Verification pointer | Trace |
|---|---|---|---|---|---|
| TMNT-SPEC-001 | Each recipe binds `ProfileId=TMNT`, the exact 1.59 build, `TMNT.exe` and its SHA-256, `SourceRole=Main`, exact `SourceSet`/`SourceEntry`, source size, SHA-1, and SHA-256. | Source pins verified; catalog row pending | Proposed two-entry fragment; schema-3 catalog loader | Independent source proof; focused exact-metadata assertions pending | Issue #351 / this slice / `TPM-TRACE-001`, `TPM-EVIDENCE-001` |
| TMNT-SPEC-002 | Each recipe has one `CreateFile` operation with `BeforeState=Absent`; `Target` equals `SourceEntry`; `AfterSha256` and `PayloadSha256` equal the pinned source SHA-256. | Existing engine shape; new rows pending | `Read-TpmRequiredPatchCatalog`, `Get-TpmPatchPlan`, `Invoke-TpmCatalogPatch` | Focused absent/read-back and foreign-state cases pending | Issue #351 / this slice / `TPM-EVIDENCE-001` |
| TMNT-SPEC-003 | Source selection is the recipe-named Main ZIP and exact member. The reviewed source members each occur once and use Deflate method 8. Runtime staging validates declared size and SHA-256; SHA-1 remains source identity metadata. | Source pins verified; synthetic staging test pending | `New-TpmRequiredPatchPayloadStage` | Synthetic exact-member ZIP staging and independent source proof | Issue #351 / this slice / `TPM-EVIDENCE-001` |
| TMNT-SPEC-004 | Payload cache names use the established basenames `payload/OrenVid.dll` and `payload/PK-UnityPlugin.dll`; source/target paths remain the full archive member paths. | Mapped; fragment pending | New fragment | Exact metadata assertions pending | Issue #351 / this slice / `TPM-TRACE-001` |
| TMNT-SPEC-005 | No unverified hardware, BepInEx, configuration, or other prerequisite is inferred; the pair has no shared exclusive group or atomic transaction claim. | Mapped | New fragment uses empty `ExclusiveGroup` and `Prerequisites` | Independent field assertions pending | Issue #351 / this slice / `TPM-TRUTH-001` |

### Deliberately out of scope

- Whether either target is absent from an installed game; `BeforeState=Absent` is only the non-overwrite policy.
- Dependency/version compatibility, plugin loading, first-launch configuration, full setup, launch readiness, controls, visual behavior, or gameplay.
- Atomicity or all-or-nothing behavior across the two files.
- Execution or inspection of DLL code and all other archive members.
- Changes to automatic discovery, hardware selection, engine policy, or the manager script.

## System Invariant Inventory (REQUIRED)

| ID | Invariant | Status | Implementation pointer | Verification pointer | Failure mode / trace |
|---|---|---|---|---|---|
| TMNT-SII-001 | A target mutation requires the exact TMNT profile/build/executable identity and pinned executable SHA-256. | Existing engine guard; new-row test pending | `Get-TpmPatchPlan` | Wrong-executable refusal before target/recovery mutation | Wrong-build file mutation; Issue #351 / slice / `TPM-EVIDENCE-001`, `TPM-TRUTH-001` |
| TMNT-SII-002 | A `CreateFile` applies only when its target is absent; exact after-state is a no-op; every other present state is refused without byte changes. | Existing engine guard; new-row test pending | `Get-TpmPatchPlan`, `Invoke-TpmCatalogPatch` | Absent apply/read-back, exact-after no-op, unknown-present refusal | Overwrite of user/third-party bytes; Issue #351 / slice / `TPM-EVIDENCE-001` |
| TMNT-SII-003 | Undo is receipt-bound and removes only the original created file object; identical bytes on a substituted file object do not authorize deletion. | Existing engine guard; new-row test pending | `Undo-TpmCatalogPatch` | Receipt undo to absence and same-byte foreign-object refusal | Deletion of a file not created by this transaction; Issue #351 / slice / `TPM-EVIDENCE-001` |
| TMNT-SII-004 | Applying or undoing either component preserves sibling configuration, plugin, and unrelated files. | New-row verification pending | Existing per-target transaction boundary | Sibling sentinel preservation test | Collateral mutation of unrelated user state; Issue #351 / slice / `TPM-EVIDENCE-001` |
| TMNT-SII-005 | Staging reads only the named ZIP member into the TPM-owned temporary root, enforces the size limit and SHA-256, and does not extract archive paths or write to the source archive. | Existing engine guard; synthetic test pending | `New-TpmRequiredPatchPayloadStage` | Synthetic ZIP member staging/read-back and temporary-root containment | Untrusted or unrelated archive bytes reaching a target; Issue #351 / slice / `TPM-EVIDENCE-001` |
| TMNT-SII-006 | Source pins and a local file transaction are not represented as installed-target, setup, compatibility, gameplay, or owner-acceptance proof. | Required reporting invariant | Slice, control board, reconciliation | Review of mapped wording; owner-runtime evidence remains pending | Source evidence overstated as readiness; Issue #351 / slice / `TPM-TRUTH-001`, `TPM-OWNER-001`, `TPM-OWNER-002`, `TPM-OWNER-003` |

## Focused verification map

The planned public suite is `Tests/TpmRequiredPatchTmntNativeMainComponents.Tests.ps1`. It must use isolated synthetic ZIP/payload/game/recovery roots and assert the exact pins independently of the fragment. Planned behaviors: metadata, source staging, absent apply/read-back, exact-after no-op, unknown-present refusal, wrong-executable refusal, receipt-bound undo, changed-object refusal, and sibling preservation. Run only this focused suite with explicit Pester 5.7.1 in both supported PowerShell engines; do not require NAS availability or execute any real DLL.
