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
- The numbered terminal profile chooser is the sole profile authority. The optional gallery follows the selected profile and exposes only comparison view controls, never a second profile selector.
- Final result output states what changed and did not change, lists unsafe or malformed details, and gives a direct review/repair-then-rerun action.
- Native TeknoParrot CRT, SSAA, shader, scanline, and post-process settings are read-only inputs; detected enabled settings produce a stacking warning and are never overwritten.
- Onboarding pauses after the ReShade result and before dgVoodoo2.

## Prompt inventory and classification

- Profile selection, game selection, bulk-apply, adopt/replace, preview, and
  Back/cancel decisions are in scope for this slice.
- Stateful game/profile pickers remain renderer-aware boundaries; this slice
  does not replace their selection grammar with a generic one-letter reader.
- Exact-token safety confirmations remain exact-token gates.

## Source inventory

- Ownership manifests are read and validated before mutation.
- ReShade removal already protects bundled, preinstalled, changed, ambiguous,
  missing, and malformed entries.
- Profile installation already has transactional staging, backup, promotion,
  rollback, and manifest commit boundaries.
- The slice must close the remaining protected-adopt/replace decision and prove
  complete all-games result accounting without weakening fail-closed paths.

## Required focused tests

- Protected files remain unchanged by default.
- Explicit adopt/replace backs up before replacement.
- Backup failure blocks replacement.
- Ownership metadata is committed only after successful replacement.
- Adopted ownership is recognized by later managed updates.
- All-games preflight counts safe, protected, missing, unsafe, and failed states.
- Final accounting totals equal selected games exactly once.
- Unsafe/malformed results expose details and route directly to review/repair then Select.
- Terminal selection updates the optional preview state; the preview cannot override it.
- Native shader/display warnings are read-only and preserve the source XML.
- Cancel, Back, preview, missing, unsafe, and null-result paths do not mutate.
- Existing ReShade focused tests remain green.

## Files allowed to change

- `TeknoParrot-Manager.ps1`
- `Tests/TeknoParrot-Manager.Tests.ps1`
- `ARCHITECTURE.md`
- `README.md`
- `TeknoParrot-Manager-README.txt`
- `TeknoParrot-Manager-QuickStart.txt`
- `TeknoParrot-Manager-CHANGELOG.txt`
- `docs/RC8-REMEDIATION-INVENTORY.md`
- `docs/remediation/PR-321-current-slice.md`
- `docs/remediation/PR-321-control-board.md`
- `docs/remediation/PR-321-reconciliation.md`

## Runtime proof required

None authorized in this slice. Owner proof requires a packaged candidate and a multi-game ReShade operation matrix.

## Stop condition

Stop if the implementation cannot preserve protected files by default, if backup/metadata ordering is ambiguous, if accounting cannot prove one outcome per selected game, or if package/runtime proof is required.

## Forbidden actions

No commit, push, package, release, certification, wiki, owner smoke, controls work, progress/prompt redesign, ARCADE/#323 work, or unrelated source cleanup.

## Working-tree evidence for this ReShade UX correction

- `Show-TpmReShadeProfileGalleryWindow` has no profile ComboBox or ignored
  profile-selection action. `Read-TpmReShadeTerminalProfile` owns the choice;
  `Sync-TpmReShadeGallerySelection` updates the optional preview state.
- `Invoke-ReShadeSetup` reports changed, protected, missing, unsafe/malformed,
  unsupported, and failed outcomes. Unsafe details are reconciled through
  `Get-TpmReShadeApplyAccounting` and the result action model routes directly
  to review/repair then Select.
- Native TeknoParrot CRT/SSAA/shader/scanline/post-process fields are read
  without XML mutation. Canonical shader filenames and technique names are
  shown instead of raw profile objects or cache paths.
- Normal onboarding prints and pauses on the ReShade result before the
  dgVoodoo2 section. Packaging, owner-runtime proof, and release authorization
  remain outside this slice.
