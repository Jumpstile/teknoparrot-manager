# TPM Remediation Slice Contract

## 1. Slice name

- Name: Cross Raid schema-3 receipt composition
- Contract ID: `TPM-CROSSRAID-COMPOSITION-001`
- Issue/PR: Issue #351; no numbered PR #321 owner row assigned.

## 2. Owner report IDs included

- IDs: Issue #351 Cross Raid base CreateFile -> AMD/NVIDIA ReplaceFile receipt-composition defect.
- Exact owner-visible failures: Applying the exact Cross Raid base shader restoration and then a vendor shader replacement succeeds, but vendor Undo is blocked by the still-Applied base receipt's live target check (`Grouped target conflict.`).

## 3. Explicit exclusions

- Owner IDs not included: No other numbered PR #321 owner-report row is assigned.
- Features, modules, package, runtime, and release actions excluded: Recipe/catalog promotion, other patch families, owner gameplay/setup, live game/ROM/DB changes, packaging, release, and main merge.

## 4. Behavior contract

- Current failure: `Assert-TpmMultiPatchExclusive` replans every Applied schema-3 receipt against current live target state before comparing groups, so a valid successor transaction is blocked by a predecessor receipt whose target has legitimately transitioned.
- Expected behavior: The exclusive gate may accept an Applied CreateFile predecessor only through one unique, fully validated schema-3 single-operation ReplaceFile chain with matching profile, canonical game root, catalog hash, and relative target. Every edge binds exact SHA-256 and file identity, and a Restored edge uses BeforeSha256 plus RestoredFileIdentity, retained backup, and terminal checkpoint. The bounded census permits at most 256 recovery directories, 262,144 bytes per receipt, and 16 MiB total; the directory set and every receipt hash are rechecked, then the target is reopened and its hash+identity checked immediately before acceptance. Unsupported multi-operation chains fail closed.
- Forbidden regressions: No global unrelated-receipt validation skip; no hash-only lineage; no ambiguous/cyclic witness acceptance; no receipt retirement, ownership transfer, lineage rewriting, stale object authorization, legacy receipt exception, weakening of backup/checkpoint/path/Prepared/same-group/hardware guards.
- Design boundaries and deliberate exclusions: The chain witness is exclusive-gate-only and cannot authorize the base CreateFile receipt's own undo. After vendor Undo publishes the base bytes into a new object, the original base receipt must refuse deletion and preserve those bytes. All non-overlap operations and unrelated receipts remain validated against live state.

## 5. Source/function ownership

- Files: `scripts/TpmRequiredPatchEngine.ps1`; `Tests/TpmRequiredPatchCrossRaidComposition.Tests.ps1`; this slice and its invariant inventory; board and reconciliation mapping.
- Functions/regions: `Assert-TpmMultiPatchExclusive`, `Assert-TpmMultiPatchReceipt`, `Get-TpmMultiPatchPlan`, receipt/checkpoint readers, `Undo-TpmCatalogPatch`.
- Owning subsystem: Required-patch multi-file transaction receipt validation.

## 6. Tests required before implementation

- Focused failing or characterization tests: Exact predecessor/successor hash+identity linkage; AMD and NVIDIA baseline vendor Undo red with exact `Grouped target conflict.`; unrelated live-target tamper positive control; Prepared transaction refusal; foreign same-byte object refusal; retained backup tamper refusal. Tests must assert exact error and unchanged bytes.
- Source/inventory checks: Prove each composed receipt retains canonical profile/root/catalog/target bindings, backups, identities, and terminal checkpoint; preserve a same-catalog unrelated operation.

## 7. Tests required after implementation

- Focused behavior tests: Pester 5.7.1 on PS7 and Windows PowerShell 5.1; the current 18-case suite passes on both. It covers AMD/NVIDIA apply -> vendor undo -> base undo refusal with new object identity -> vendor reapply as a new transaction -> vendor undo, exact predecessor/successor identity links, missing/corrupt/ambiguous/cyclic witnesses, census bounds, root snapshot mutation, blocked direct structural-mode access, foreign same-byte identity, backup/checkpoint tamper, Prepared, same-group, hardware mismatch, unrelated live-target tamper, and schema-2 catalog/schema-1 receipt ordinary undo.
- Regression suite: The focused composition suite plus the authorized full Main, Support, and registered required-patch lane suites on both engines. No result is claimed until captured.
- Static and procedure gates: Scoped parse/ASCII/privacy checks, configured analyzer on touched production script, and required permanent procedure gate with explicit `ChangedAtUtc` after final source/doc edits.

## 8. Documentation/report updates required

- Control board row: Add separate Issue #351 composition defect status and exact test evidence; keep native recipe held and catalog unchanged.
- Remediation report row: Add this contract and inventory with actual focused outcomes and implementation status.
- Hunk classification: Receipt-chain validation only; no recipe/catalog behavior change.
- Changelog or user docs, if applicable: None; this is an internal transaction correctness fix with no promoted recipe or user-facing readiness claim.

## 9. Permanent procedure IDs affected

- IDs and evidence: `TPM-TRACE-001` (every changed hunk maps to Issue #351 and the authorized composition requirement), `TPM-EVIDENCE-001` (behavioral tests for the feasible ownership claim), `TPM-OWNER-001` (owner runtime remains the acceptance gate). Controls-readiness procedure `TPM-TRUTH-001` is not changed by this slice; controls remain unverified. No numbered PR #321 owner report is assigned.

## 10. Runtime smoke checklist

- Exact packaged behavior: None in this source-only slice; no game payload is executed.
- Required source/package identity: Synthetic fixtures only; held Cross Raid recipe stays excluded from catalog.
- Evidence artifacts: Focused Pester output, exact input hashes, receipts/checkpoints in TestDrive, permanent procedure gate output.
- Owner/runtime authorization: Not requested or granted; gameplay remains unverified.

## 11. Stop condition

Stop when the complete focused chain/guard matrix passes on both engines, source and mapped evidence agree, and the permanent procedure gate passes. Do not promote or integrate the held recipe in this slice.

## 12. Forbidden actions

No unrelated cleanup, broad rewrite, force push, history rewrite, package, release, main merge, owner certification, wiki update, ARCADE work, or owner smoke.

## 13. Commit/package authorization status

- Scoped commit, ordinary branch push, exact-head CI and integration into `fix/rc8-release-blockers`: authorized after final review and source gates. Latest direction: "Proceed with final review and scoped publication/CI/integration under existing authorization." Correct author and committer identities are mandatory.
- Package authorized: No.
- Release/certification authorized: No.

## 14. Final local verification

Full Main, SupportPackage and seven required-patch suites passed 1714/1714 on each engine (Pester 5.7.1), with actual child exits 0. Both static gates and canonical InjectionHunter passed; the explicit-freshness permanent gate passed at 2026-10-15T12:05:48Z. Source code/test inputs remain unchanged; the final evidence-only document corrections are followed by a separate identity audit and freshness gate before commit. The held recipe is not promoted.
