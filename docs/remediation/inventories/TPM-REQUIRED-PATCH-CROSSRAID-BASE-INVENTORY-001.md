# Cross Raid 1.05 Ver A base-shader recipe specification and invariant inventory

Status: Required specification and system-invariant inventory for the separately authorized one-entry Issue #351 Main-component candidate `TPM-REQUIRED-PATCH-CROSSRAID-BASE-001`. The baseline is 61 recipes / 23 exact profile-build-executable identities / 53 `CreateFile` / eight `ReplaceFile`, catalog SHA-256 `87DF31451B267F89FCD2CB3E3DEA1860972EDD4C7601ACE1998E80BD7E4CAD9E`. Recipe/catalog promotion is pending; owner-runtime acceptance is separate.

## Component and boundary

The candidate restores only `rom/shader.farc` for the exact Cross Raid 1.05 Ver A Main build when the target is absent. It does not replace a GPU-specific shader or establish Black Textures classification, setup completeness, compatibility, or gameplay. The AMD and NVIDIA shader replacements are separate recipes. The source binding is supported by the existing exact Main source-probe receipt and nested-shader provenance receipt; the older unversioned RAR is excluded.

Exact recipe identity: ProfileId `ShiningForceCrossRaid`; BuildName `Shining Force - Cross Raid (1.05 Ver A)(2011-08-03)(JPN)[Sega RingEdge][TP]`; executable `project_f-ringedge-release.exe`, SHA-256 `82E66635A9A91CEC59721DB7BD9258464F70C44377BA707FFCB51EA2D3DB9317`; Main SourceSet `Shining Force - Cross Raid (1.05 Ver A)(2011-08-03)(JPN)[Sega RingEdge][TP].zip`; SourceEntry/target `rom/shader.farc`; size 9,173,328; SHA-1 `04E0DCEC14CCA1B69BF190A7E02F2F0AB56E0231`; SHA-256 `66E0CC00E84C01F6E77E6B446A019212EBD27610FDD81CA866648C5E97E80933`.

## Specification Inventory (REQUIRED)

Governing contract: schema-3 recipe fields, exact named ZIP-member staging, file operation semantics, and receipt/object-identity rules documented by the required-patch engine and `SECURITY.md` section "Required game-patch source and target boundary (RC8 candidate)". This inventory covers one exact-build, one-file `CreateFile` candidate; the shared engine body is not changed.

| ID | Rule / source | Status before integration | Implementation pointer | Verification pointer | Trace |
|---|---|---|---|---|---|
| CRB-SPEC-001 | The entry binds the exact ProfileId, BuildName, executable name, and executable SHA-256 listed above. | Mapped; entry pending | Candidate fragment and schema-3 catalog loader | Exact metadata assertion and wrong-executable refusal in the standalone suite | Issue #351 / `TPM-REQUIRED-PATCH-CROSSRAID-BASE-001` / `TPM-TRACE-001`, `TPM-EVIDENCE-001` |
| CRB-SPEC-002 | SourceRole is `Main`; the exact Main ZIP, member, size, SHA-1 identity metadata, and SHA-256 are pinned. SHA-1 is provenance metadata; staged byte integrity is enforced by size and SHA-256. | Mapped; entry pending | Candidate fragment; `New-TpmRequiredPatchPayloadStage` | Exact source-pin assertion; existing Main probe and nested-provenance receipts | Issue #351 / slice / `TPM-TRACE-001`, `TPM-EVIDENCE-001` |
| CRB-SPEC-003 | Exactly one `CreateFile` operation targets `rom/shader.farc`; `BeforeState=Absent`; target equals SourceEntry; `AfterSha256` and `PayloadSha256` equal the Main SHA-256. No hardware predicate, exclusive group, or prerequisite is added. | Mapped; entry pending | Candidate fragment; existing catalog validator | Schema/field checks and catalog import | Issue #351 / slice / `TPM-TRACE-001`, `TPM-TRUTH-001` |
| CRB-SPEC-004 | Apply is allowed only when the target is absent; exact-after bytes are a no-op; unknown or vendor-specific present bytes are refused without overwrite. | Mapped; candidate behavior pending | Existing planner and transaction engine | Synthetic lifecycle, unknown-state, and AMD/NVIDIA present-state tests | Issue #351 / slice / `TPM-EVIDENCE-001` |
| CRB-SPEC-005 | Receipt undo is constrained by the created object identity. Existing base-to-vendor composition permits valid vendor undo, then refuses base undo when restoration creates a new object; bytes remain intact. | Mapped; candidate behavior pending | Existing schema-3 receipt and object-identity guards | Both vendor composition cases in the frozen and final portable suite | Issue #351 / slice / `TPM-EVIDENCE-001`, `TPM-TRUTH-001` |

### Deliberately out of scope

- The older unversioned Cross Raid raw RAR, Cross Raid 1.00, and any source lacking an exact Main target binding.
- AMD/NVIDIA hardware classification or replacement behavior in the base recipe; vendor alternatives remain independent.
- Black Textures patch-versus-restoration classification; byte equality alone does not establish that classification.
- IC-card files, shared card roots, iDmac/JVS/NESiCA drivers, managed plugins, registry/configuration edits, and automatic setup.
- Shader-set atomicity, visual correctness, compatibility, launch, gameplay, or owner acceptance.

## System Invariant Inventory (REQUIRED)

| ID | Invariant | Status before integration | Implementation pointer | Verification pointer | Failure mode / trace |
|---|---|---|---|---|---|
| CRB-SII-001 | The exact profile/build/executable and executable SHA-256 must match before target mutation. | Existing guard; candidate test pending | `Get-TpmPatchPlan` | Wrong-executable refusal without target/recovery mutation | Wrong-build mutation; Issue #351 / slice / `TPM-EVIDENCE-001`, `TPM-TRUTH-001` |
| CRB-SII-002 | The recipe creates only an absent target; exact-after is not rewritten; unknown and AMD/NVIDIA bytes are preserved and refused. | Existing guard; candidate test pending | `Get-TpmPatchPlan`, `Invoke-TpmCatalogPatch` | Lifecycle and three present-state refusal assertions | Overwrite of user/vendor bytes; Issue #351 / slice / `TPM-EVIDENCE-001` |
| CRB-SII-003 | Target paths remain subject to canonical containment, reparse-point, and existing-parent checks; the recipe does not create parent directories. | Existing guard | Existing target validation | Existing engine regressions and scoped source review; no new parent behavior | Unsafe path creation or write; Issue #351 / slice / `TPM-EVIDENCE-001` |
| CRB-SII-004 | Only the exact named Main ZIP member is staged beneath TPM-owned temporary storage; runtime checks size and SHA-256. | Existing guard; exact source bytes remain source-evidence bound | `New-TpmRequiredPatchPayloadStage` | Existing source-pin receipts and portable synthetic staging coverage | Unrelated archive data reaches mutation; Issue #351 / slice / `TPM-EVIDENCE-001` |
| CRB-SII-005 | Undo requires the correct receipt and file-object identity; byte equality on another object is insufficient. | Existing guard; composition regression covered by baseline suite | `Undo-TpmCatalogPatch` | AMD/NVIDIA composition tests assert vendor undo then base undo refusal after object replacement | Removal of an object not created by the transaction; Issue #351 / slice / `TPM-EVIDENCE-001` |
| CRB-SII-006 | Source pins and successful file transactions are not setup, compatibility, gameplay, release, or owner-runtime proof. | Required wording invariant | Slice, inventory, board, reconciliation, and scoped architecture/user docs | Review exact claims; no game execution or live target inspection | Source evidence overstated as readiness; Issue #351 / slice / `TPM-TRUTH-001`, `TPM-OWNER-001`, `TPM-OWNER-002`, `TPM-OWNER-003` |

## Verification boundary

The frozen seven-case suite passed 7/7 under explicit Pester 5.7.1 on PowerShell 7.6.7 and Windows PowerShell 5.1.26100.9549 before catalog edits; actual child exit was 0 for each run and all seven cases were present in NUnit XML. Those runs prove the existing engine/catalog baseline and held candidate fixture only. They do not establish real game runtime, visual behavior, owner acceptance, or package readiness. Final recipe-specific verification is pending.
