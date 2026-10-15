# Cross Raid receipt-composition invariant inventory

Status: Implemented in the isolated composition worktree; base shader CreateFile remains held and excluded from the catalog.

## Component and boundary

`TpmRequiredPatchEngine.ps1` validates schema-3 multi-file transaction receipts and exclusive hardware alternatives. The defect is that an Applied predecessor is live-replanned as though its own after-state must still be the current target before a valid successor receipt can be undone. This inventory is limited to exact same-target receipt composition; it does not authorize recipe promotion, gameplay, configuration, or setup completion.

## Invariants

| ID | Checkable invariant | Failure mode | Verification |
|---|---|---|---|
| CRC-1 | A receipt-chain edge binds identical ProfileId, canonical GameRoot, CatalogSha256, and exact relative Target. | Cross-profile/root/catalog receipts become interchangeable. | Positive common-binding assertions and mismatch refusal tests. |
| CRC-2 | A successor ReplaceFile edge begins only at the predecessor's exact AfterSha256 and AfterFileIdentity. | Same bytes on a foreign object are mistaken for owned lineage. | Hash+identity edge assertion; replace-by-new-object same-byte refusal. |
| CRC-3 | A Restored ReplaceFile terminal edge ends at BeforeSha256 plus RestoredFileIdentity, backed by its retained backup and exact terminal checkpoint. | Tampered/incomplete undo evidence proves a false handoff. | Vendor undo receipt/checkpoint readback; backup/checkpoint tamper tests. |
| CRC-4 | For every Applied predecessor considered by the exclusive gate, exactly one complete acyclic validated edge chain reaches the actual current target hash and identity. | Missing or ambiguous successors, cycles, or stale state are accepted. | Valid AMD/NVIDIA lifecycle; missing, ambiguous, cyclic, wrong-identity witness refusal. |
| CRC-5 | Chain-aware structural inspection is internal to exclusive-gate evaluation; every unrelated receipt and every non-overlap operation remains live-validated. | A same/different-group receipt or unrelated target tamper is skipped. | Valid unrelated apply/undo-ready control, then foreign mutation; exact conflict and byte-preservation assertion. |
| CRC-6 | The chain witness never authorizes the predecessor's own undo. Base CreateFile undo requires its original receipt-bound object identity. | Base undo deletes a later vendor/restored object. | After vendor Undo, new RestoredFileIdentity differs from base AfterFileIdentity; base undo throws `Grouped target object identity changed.` and preserves base bytes. |
| CRC-7 | Reapply creates a new transaction whose Before identity is the latest Restored identity; all old receipts/checkpoints remain present and validated. | Reapply overwrites evidence or loses the chain. | Second vendor Apply/Undo cycle, unique RecoveryDirectory and retained old receipt/checkpoint assertions. |
| CRC-8 | Existing Prepared, same-group, hardware, backup, checkpoint, path, race, and legacy receipt rules remain effective. | Narrow chain handling weakens existing safety boundaries. | Exact guard-message negative cases with unchanged target bytes; legacy ordinary undo regression. |

## Existing evidence available

- Schema-3 operation receipts have `BeforeSha256` and `AfterSha256`; there is
  no separate restored-hash field. A Restored ReplaceFile uses its
  `BeforeSha256` with `RestoredFileIdentity`, retained backup, and terminal
  checkpoint. Receipt-level profile/root/catalog/transaction/state fields
  bind each transaction.
- Apply records `BeforeFileIdentity` and `AfterFileIdentity`. Successful
  ReplaceFile undo records `RestoredFileIdentity` and writes a terminal
  checkpoint. Each Apply creates a new GUID transaction directory.
- The retained pre-fix PS7/Pester 5.7.1 characterization passed 5/7, failing both AMD and NVIDIA vendor undo; that exact characterization was not run on PS5.1. Intermediate red harness results remain private historical evidence, not final acceptance.
- Final focused composition suite: 18 passed/0 failed/0 skipped on PowerShell 7.6.7/Pester 5.7.1 and 18/0/0 on Windows PowerShell 5.1.26100.9549/Pester 5.7.1. It proves AMD and NVIDIA vendor undo, strict base object-identity refusal after vendor undo, new-transaction reapply, and refusal paths including missing/corrupt/ambiguous/cyclic witnesses, bounded-census limits, root snapshot binding, unrelated-target tampering, backup/checkpoint integrity, hardware/same-group, Prepared, and legacy schema-2 catalog/schema-1 receipt undo.

## Deliberate exclusions

No global `different-group` receipt validation bypass, no hash-only exception, no receipt retirement/rewriting/ownership transfer, no legacy exception, no recipe/catalog modification, and no claim of gameplay or owner-runtime success.
