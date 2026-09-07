# PR #321 Current Slice: ReShade Ownership and Accounting

- Slice ID: TPM-RESHADE-001
- Slice name: Protected ReShade adopt/replace and all-games accounting
- Included owner-report IDs: 11, 12.
- Issue: PR #321.
- Permanent procedures: TPM-TRACE-001, TPM-OWNER-001.
- Explicit exclusions: controls runtime proof (30), progress inventory (3), prompt migration (26/32), repair (16-22), packaging, release, certification, owner-runtime smoke, ARCADE/#323, wiki, commit, and push.

## Behavior contract

- Protected or unknown ReShade files are preserved by default.
- Explicit adopt/replace is the only path that may replace protected files; the UI must explain the risk and backup requirement.
- Existing protected files are backed up before replacement. Backup failure blocks replacement and ownership metadata is not written.
- Ownership metadata is written only after successful replacement and records TPM-managed ownership for future operations.
- All-games preflight reports managed-ready, protected, missing-path, unsafe, and failed/preflight-blocked counts before mutation.
- Every selected game receives exactly one terminal accounting outcome: changed, adopted/replaced, protected unchanged, missing, unsafe, failed, skipped, or cancelled.
- Missing paths, unsafe paths, cancel, Back, and preview remain non-mutating.

## Prompt inventory and classification

- Profile selection, game selection, bulk-apply, adopt/replace, preview, and
  Back/cancel decisions are in scope for this slice.
- Stateful game/profile pickers remain renderer-aware boundaries; this slice
  does not replace their selection grammar with a generic one-letter reader.
- Exact-token safety confirmations remain exact-token gates.

## Source inventory

- Ownership manifests are read and validated before mutation.
- ReShade removal already protects bundled, preinstalled, changed, ambiguous, missing, and malformed entries.
- Profile installation already has transactional staging, backup, promotion, rollback, and manifest commit boundaries.
- The slice must close the remaining protected-adopt/replace decision and prove complete all-games result accounting without weakening fail-closed paths.

## Required focused tests

- Protected files remain unchanged by default.
- Explicit adopt/replace backs up before replacement.
- Backup failure blocks replacement.
- Ownership metadata is committed only after successful replacement.
- Adopted ownership is recognized by later managed updates.
- All-games preflight counts safe, protected, missing, unsafe, and failed states.
- Final accounting totals equal selected games exactly once.
- Cancel, Back, preview, missing, unsafe, and null-result paths do not mutate.
- Existing ReShade focused tests remain green.

## Files allowed to change

- `TeknoParrot-Manager.ps1`
- `Tests/TeknoParrot-Manager.Tests.ps1`
- `ARCHITECTURE.md`
- `docs/remediation/PR-321-current-slice.md`
- `docs/remediation/PR-321-control-board.md`
- `docs/remediation/PR-321-reconciliation.md`

## Runtime proof required

None authorized in this slice. Owner proof requires a packaged candidate and a multi-game ReShade operation matrix.

## Stop condition

Stop if the implementation cannot preserve protected files by default, if backup/metadata ordering is ambiguous, if accounting cannot prove one outcome per selected game, or if package/runtime proof is required.

## Forbidden actions

No commit, push, package, release, certification, wiki, owner smoke, controls work, progress/prompt redesign, ARCADE/#323 work, or unrelated source cleanup.
