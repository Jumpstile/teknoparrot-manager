# TPM Remediation Slice Contract

## 1. Slice name

- Name: Cross Raid 1.05 Ver A Main base-shader absent restoration
- Contract ID: `TPM-REQUIRED-PATCH-CROSSRAID-BASE-001`
- Issue/PR: Issue #351; no numbered PR #321 owner row is assigned.

## 2. Owner report IDs included

- IDs: None assigned; this is the separately authorized Issue #351 recipe request.
- Exact owner-visible failures: No owner-runtime failure or acceptance is claimed. The current catalog lacks a recipe for restoring the exact Main `rom/shader.farc` component when that target is absent.

## 3. Explicit exclusions

- Owner IDs not included: No numbered PR #321 owner-report row is assigned; no owner/runtime acceptance is inferred.
- Features, modules, package, runtime, and release actions excluded: Other games and source families; Cross Raid IC-card automation; iDmac/JVS/NESiCA drivers; managed plugins; automatic GPU selection; source acquisition; game/profile installation; executable or payload execution; game launch/gameplay; packaging; commit, push, release, tag, and main merge.

## 4. Behavior contract

- Current failure: The exact Cross Raid 1.05 Ver A profile/build/executable has no catalog operation to restore its known Main `rom/shader.farc` component when the target is absent.
- Expected behavior: One schema-3 `CreateFile` recipe binds `ShiningForceCrossRaid`, build `Shining Force - Cross Raid (1.05 Ver A)(2011-08-03)(JPN)[Sega RingEdge][TP]`, executable `project_f-ringedge-release.exe` with SHA-256 `82E66635A9A91CEC59721DB7BD9258464F70C44377BA707FFCB51EA2D3DB9317`, Main ZIP `Shining Force - Cross Raid (1.05 Ver A)(2011-08-03)(JPN)[Sega RingEdge][TP].zip`, member/target `rom/shader.farc`, size 9,173,328, SHA-1 `04E0DCEC14CCA1B69BF190A7E02F2F0AB56E0231`, and SHA-256 `66E0CC00E84C01F6E77E6B446A019212EBD27610FDD81CA866648C5E97E80933`. Create only from `BeforeState=Absent`; exact-after is a no-op; unknown and AMD/NVIDIA-present bytes are refused; receipt-bound undo removes only the object created by this operation.
- Forbidden regressions: No overwrite or replacement of a present target; no hardware predicate or vendor exclusivity added to the base recipe; no automatic target-parent creation; no executable/payload launch; no relaxed receipt/object-identity guard; no change to engine behavior other than the catalog SHA-256 pin.
- Design boundaries and deliberate exclusions: This is restoration of a known Main base component, not a GPU shader fix, Black Textures classification, atomic shader-set install, complete setup, compatibility, or gameplay proof. The versioned 1.05 raw shader component is Main-identical; the older unversioned RAR is excluded. AMD/NVIDIA replacement entries remain separate and retain their existing hardware predicates. No IC-card files are modified.

## 5. Source/function ownership

- Files: `scripts/TpmRequiredPatchRecipes.json`; the catalog integrity-pin line only in `scripts/TpmRequiredPatchEngine.ps1`; `tools/required-patches/fragments/native-crossraid-base-shader-20261015.json`; `Tests/TpmRequiredPatchCrossRaidBaseLane.Tests.ps1`; `.github/workflows/ci.yml`; this slice and its invariant inventory; current control board and reconciliation; scoped architecture/user-doc wording.
- Functions/regions: Existing schema-3 catalog loader, exact ZIP-member staging, planner, apply/read-back, receipt, and undo behavior. No engine function or Main-script changes.
- Owning subsystem: Required-patch catalog and existing transaction engine.

## 6. Tests required before implementation

- Focused failing or characterization tests: The immutable seven-case held-lane suite ran before catalog edits under Pester 5.7.1 on PowerShell 7 and Windows PowerShell 5.1; both passed 7/7 with zero failures/skips and actual child exit 0. It exercises exact metadata, absent apply/read-back/no-op/receipt undo, wrong-executable and unknown-present refusal, AMD/NVIDIA non-overwrite, synthetic source staging, and both vendor compositions including the base receipt object-identity refusal.
- Source/inventory checks: Reuse the exact Main source and nested-archive provenance receipts; verify their source hashes against this contract, preserve the 61 current catalog entries semantically, then verify 62 unique IDs, 23 exact profile/build/executable identities, 54 `CreateFile` operations, eight `ReplaceFile` operations, and the engine pin equals the final catalog hash.

## 7. Tests required after implementation

- Focused behavior tests: A portable standalone suite in the repo must assert the exact recipe and vendor pins, synthetic absent apply/read-back/exact-after no-op/receipt undo/unknown refusal, wrong executable refusal, actual AMD/NVIDIA present-state refusal without overwrite, and both base-to-vendor composition paths with the existing receipt/object-identity guards. Run only that suite with explicit Pester 5.7.1 under PowerShell 7 and Windows PowerShell 5.1.
- Regression suite: Update the central catalog count/identity/hash assertion and add the standalone suite to the explicit CI workflow path. No full Main, Support, or canonical suite is run in this staging lane before root review.
- Static and procedure gates: Verify catalog JSON/schema, unique IDs, exact source/operation pins, 62/23/54/8 counts, catalog hash pin, engine byte diff limited to the pin line, CI selection, ASCII/parse, and `git diff --check`. Root owns combined freeze gates.

## 8. Documentation/report updates required

- Control board row: Add a distinct 62nd-entry candidate checkpoint; preserve the historical 61-entry baseline and earlier 58-entry results.
- Remediation report row: Map the exact catalog/test/docs delta to Issue #351, this contract/inventory, and the procedure IDs below. No numbered PR #321 owner row is assigned.
- Hunk classification: One exact schema-3 `CreateFile` entry, one catalog SHA-256 pin update, focused test plus explicit CI inclusion, and scoped documentation. No manager script, engine behavior, source payload, or unrelated catalog entry changes.
- Changelog or user docs, if applicable: Update only the relevant existing required-patch/architecture wording to describe this absent-only Main restoration and its limits. No release version, package, live wiki, or owner-runtime claim.

## 9. Permanent procedure IDs affected

- IDs and evidence: `TPM-TRACE-001` for exact hunk mapping; `TPM-EVIDENCE-001` for behavioral proof; `TPM-TRUTH-001` and `TPM-OWNER-001`, `TPM-OWNER-002`, `TPM-OWNER-003` for truthful separation from owner runtime/gameplay; `TPM-UX-001` and `TPM-UX-002` for any user-facing wording. No new permanent procedure ID is asserted.

## 10. Runtime smoke checklist

- Exact packaged behavior: Not performed; no real game or game payload is executed.
- Required source/package identity: Exact Main member and executable pins above, corroborated by the existing Cross Raid source and nested-archive provenance receipts; no whole-archive compatibility or owner-runtime claim.
- Evidence artifacts: Frozen source-probe and nested-provenance receipts; frozen 7-case pre-integration suite outputs/XML; final standalone Pester outputs/XML and catalog/input hashes.
- Owner/runtime authorization: No live runtime authorization or owner acceptance is claimed.

## 11. Stop condition

Stop after the single entry, catalog pin, focused suite, CI route, mapped documentation, and scoped verification are complete for root review. Keep the recipe out of any release package unless separately authorized.

## 12. Forbidden actions

No unrelated cleanup, additional recipes, engine behavior changes, commits, pushes, packages, releases, tags, main merge, certification, live wiki update, ARCADE work, or owner smoke.

## 13. Commit/package authorization status

- Commit authorized: No
- Package authorized: No
- Release/certification authorized: No
## 14. Isolated implementation and focused verification result

- The 62nd candidate entry is present in the isolated catalog. The prior 61 entries remain semantically unchanged; the required-patch engine diff is limited to the catalog SHA-256 pin, and the manager script matches base `cc307092553397c8eb56543e9cb4db1219fb73ef`.
- The standalone portable suite passed 7/7 under explicit Pester 5.7.1 on PowerShell 7.6.7 and Windows PowerShell 5.1.26100.9549. The targeted central catalog identity test passed 1/1 on each engine; 1,487 other central tests were filtered out.
- Exact focused input/output receipt SHA-256: `7706F6AA6D23869A400D08A9D033B4E36B80E00F2DD713F3A6C41AAD36778642`. No focused-test input changed during execution.
- These results are isolated staging evidence only. The requested current summaries are synchronized in the README, changelog, quick-start, architecture, and wiki-staging files; no live wiki write occurred. Root-owned combined suites and procedure/security/static gates, CI, package validation, and owner-runtime validation remain pending. No compatibility, gameplay, complete-setup, release, or owner-acceptance claim is made.

## Clean 62-entry candidate local verification checkpoint

Local verification completed through2026-10-15T14:16:13Z. The complete evidence record and preserved failures are in docs/remediation/PR-321-reconciliation.md under this heading: Main1488 and Support42 passed per engine; corrected MainExtras/Shadow23 and package116 passed per engine with actual exits0. Source/package proofs do not establish owner runtime or release acceptance. Exact-head CI/integration and owner/ARCADE gates remain separate.
