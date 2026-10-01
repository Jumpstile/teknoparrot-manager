# ReShade / dgVoodoo2 Auto-Download System Invariant Inventory
Release context: this inventory documents the published v1.0 RC7 release and the
unpublished RC8 candidate source. The v1.0 RC6 release is the previous published
release (historical); final Version 1.0 remains unpublished.

## Component and boundary

This inventory covers the internal correctness guarantees of the
dgVoodoo2 and ReShade auto-download feature in `TeknoParrot-Manager.ps1`:
the shared transactional-extraction primitives
(`New-TpmStagingDirectory`, `Copy-TpmZipEntryToFile`,
`Invoke-TpmTransactionalPromote`), the two extractors that use them
(`Expand-ReShadeSelfExtractingArchive`, `Expand-DgVoodoo2Zip`), and the
download-trust chain that must complete before either extractor is ever
invoked (`Invoke-TpmDownload` with `-ExpectedSha256`,
`Test-ReShadeSetupTrustedSignature`).

Triggers this component meets (per INVENTORY_STANDARDS.md, REQUIRED):
it implements transaction processing / a commit protocol (staged writes,
atomic promotion, rollback -- `Invoke-TpmTransactionalPromote`), and it
has already been the subject of two independent review rounds that each
found a genuinely new defect class (round 1: the P1 #1 partial-deploy
defect; round 2, same submission: the P1 #2 thumbprint-only trust defect).
Both triggers independently make a System Invariant Inventory REQUIRED
for this component.

**Explicitly NOT this component's responsibility** (boundary): validating
that the extracted DLLs actually work correctly when placed into a game
folder (that is `Invoke-ReShadeSetup`/`Invoke-DgVoodoo2Setup`'s job, a
separate component with its own existing test coverage); GitHub API
availability or rate limiting; whether reshade.me or GitHub themselves
have been compromised (this component's trust model assumes the
transport and identity checks it performs are sufficient, per the
Specification Inventory's `RESHADE-TRUST-002`).

The component boundary also includes the ReShade visual profile gallery
(`Show-TpmReShadeProfileGalleryWindow`) and its terminal-only fallback. The
gallery is a read-only preview surface: it may render in-memory comparison
images and update transient selection state, but it is not permitted to
deploy files, save configuration, or claim a profile was applied.

## Invariants

### TX-001 -- Destination is never touched until a complete, valid staged set exists
No file is written to, moved into, or removed from the real destination
(`Scripts\ReShade\` or `Scripts\dgVoodoo2\`) until every required file has
been extracted into an isolated staging directory
(`New-TpmStagingDirectory`) and validated there (entry presence, sanitized
names, containment, non-zero length).
- **Verified by:** `Expand-ReShadeSelfExtractingArchive` and
  `Expand-DgVoodoo2Zip`'s "leaves the destination completely untouched
  when extraction fails partway through" regression tests (Tests\TeknoParrot-Manager.Tests.ps1),
  which mock a failure on the 2nd required file during extraction and
  assert the destination directory's contents are byte-for-byte identical
  to their pre-call state.
- **Failure mode if violated:** a corrupted or format-mismatched download
  could leave a subset of files (some old, some new, some missing) in a
  live `Scripts\ReShade\`/`Scripts\dgVoodoo2\` folder that TPM then
  deploys into a user's game folders as if it were a complete, valid set
  -- exactly the defect an independent review found and this invariant
  now closes.

### TX-002 -- Promotion is rollback-safe: partial promotion is never observable
'Invoke-TpmTransactionalPromote' either succeeds completely (every
requested file ends up in the destination) or, on a recoverable failure,
leaves the destination in exactly its pre-call state. If a file move into
the destination fails partway through and rollback completes, every file
already promoted in that same call is removed again, every pre-existing
destination file that was moved aside to make room is restored to its
original name and location, and a destination directory the call itself
created (one that did not exist before) is removed again. If an underlying
filesystem mutation loses the original destination file before a valid
backup is observable, exact restoration cannot be claimed; the transaction
fails explicitly as 'ROLLBACK FAILED' / 'INCONSISTENT' and preserves recovery evidence.

**Status history:** marked 'Implemented' after the first remediation
round, then downgraded to 'Pending -- rollback bookkeeping gap found' when
a second independent review round proved that partially mutating
'Move-Item' calls were not tracked and rollback-step failures were only
logged. The second-round fixes restored the status to 'Implemented', but
the third independent review downgraded it to 'Pending' again after
adversarial execution found three remaining defects: phase-1 could lose
the original destination file before a usable backup was observable;
destination and rollback-directory setup was not one protected boundary;
and rollback-backup cleanup failure was not surfaced as a distinct
outcome. It is marked 'Implemented' again only after the complete
third-round primitive-and-wrapper matrix passed.

- **Fix (phase-1 source-loss bookkeeping):** before every phase-1
  move-aside, the transaction captures the existing file's length, SHA256,
  and timestamp. If 'Move-Item' throws, it immediately inspects both the
  original and backup paths. A backup is recorded for normal rollback only
  when its observed length and SHA256 match the captured pre-state. If the
  original has disappeared without a valid backup, the transaction records
  an explicit unrecoverable source-loss diagnostic and throws the distinct
  'TPM TRANSACTION ROLLBACK FAILED ... state may be INCONSISTENT' path,
  preserving the staging/backup evidence. An observed invalid backup is
  likewise reported instead of being trusted.
- **Fix (promotion bookkeeping and setup boundary):** every phase-2
  'Move-Item' that throws is followed by an observed destination-path
  check, so a partial cross-volume move cannot escape rollback tracking.
  Destination-directory creation and '.tpm-rollback-backup'
  initialization now occur inside the protected transaction setup
  boundary. If the destination was absent before the call, rollback
  removes the directory the transaction created when setup or promotion
  fails.
- **Fix (rollback and cleanup failure semantics):** rollback-step failures
  are collected, not swallowed. The 'ROLLBACK FAILED' exception carries
  the original promotion/setup error and every rollback error, states
  that the destination may be 'INCONSISTENT', and leaves
  '.tpm-rollback-backup' in place. If destination restoration succeeds but
  final rollback-backup cleanup throws, the transaction instead reports
  'TPM TRANSACTION CLEANUP FAILED', explicitly says restoration succeeded,
  preserves the residue, and remains a non-success result. Both extractor
  wrappers preserve their staging directory for either recovery-failure
  message so their 'finally' blocks cannot delete the evidence.
- **Verified by:** exact directory snapshots
  ('Get-TpmDirSnapshot'/'Assert-TpmDirSnapshotUnchanged') compare
  destination existence, every relative path, file-vs-directory type, and
  exact file bytes. The primitive matrix covers clean success; destination
  absent with first promotion failure; destination absent with first file
  successful and second failure; pre-existing destination with partial
  replacement failure; valid phase-1 backup observed after a thrown move;
  phase-1 source loss with no valid backup; destination-absent setup
  initialization failure; forced rollback failure; and restored destination
  with forced rollback-backup cleanup failure. The same adversarial source-
  loss, setup-failure, and cleanup-failure cases run end-to-end through
  both 'Expand-ReShadeSelfExtractingArchive' and 'Expand-DgVoodoo2Zip',
  alongside their clean-success, partial-promotion, absent-destination,
  and rollback-failure cases. Tests assert no backup residue after
  successful rollback, exact destination restoration and preserved
  residue for cleanup failure, and preserved recovery evidence for
  unrecoverable/rollback-failure outcomes.

- **Failure mode if violated:** an interrupted update (disk full, file
  locked by a running game, permission error, or a partially mutating
  cross-volume move) could leave a destination folder with, e.g., 4 of 6
  new dgVoodoo2 files and 2 stale ones -- an internally inconsistent DLL
  set silently deployed to games -- or could destroy the only recoverable
  copy of a pre-existing file while reporting an ordinary failure.

### TX-003 -- Staging directories are cleaned conditionally; recovery evidence never leaks
Every staging directory created by 'New-TpmStagingDirectory' for an
extraction attempt is removed before the extraction function returns on
ordinary success, extraction failure, or promotion failure whose rollback
completed, provided ordinary staging cleanup succeeds. If ordinary staging
cleanup itself fails while the destination
state is otherwise valid or restored, the wrapper reports the distinct
'TPM STAGING CLEANUP FAILED' condition with the exact staging path and
preserves the residue. When the shared transaction reports 'ROLLBACK FAILED' or
'TRANSACTION CLEANUP FAILED', the staging directory is deliberately
preserved so '.tpm-rollback-backup' and any other recovery evidence remain
available for manual inspection.

- **Verified by:** the conditional 'catch'/'finally' logic in both
  'Expand-ReShadeSelfExtractingArchive' and 'Expand-DgVoodoo2Zip', plus
  the transaction matrix asserting no staging/backup residue on clean
  success and ordinary successful rollback, preserved backup residue on
  rollback failure, preserved rollback residue on transaction cleanup
  failure, and preserved staging residue plus exact path/valid destination
  on ordinary staging cleanup failure. The wrapper tests exercise all of
  those outcomes through both
  extractors.
- **Failure mode if violated:** deleting evidence after an incomplete
  rollback would make manual recovery impossible; failing to clean up on
  ordinary outcomes would accumulate orphaned staging directories under
  the user's real '%TEMP%\TeknoParrotManagerStaging' on every failed
  download/extraction attempt.
### TRUST-004 -- Untrusted or integrity-failed artifacts never reach extraction/deployment
An artifact is never passed to `Expand-ReShadeSelfExtractingArchive` or
`Expand-DgVoodoo2Zip` (and by extension never reaches
`Invoke-TpmTransactionalPromote`) unless it has already passed the full
trust chain for its type: for ReShade, `Test-ReShadeSetupTrustedSignature`
must report `Trusted = $true` (both the pinned thumbprint AND an accepted
`.Status`, per Specification Inventory `RESHADE-TRUST-002`); for
dgVoodoo2, when the release asset's GitHub digest is available,
`Invoke-TpmDownload -ExpectedSha256` must have completed successfully
(size AND hash both validated) before the ZIP path is ever handed to
`Expand-DgVoodoo2Zip`.
- **Verified by:** the caller-side wiring in the standalone "ReShade
  setup" / "dgVoodoo2 setup" menu handlers (`Invoke-TpmDownload` called
  and checked before `Test-ReShadeSetupTrustedSignature`/extraction is
  ever reached; extraction is skipped and the partial download deleted on
  a failed/untrusted result) plus the full `Test-ReShadeSetupTrustedSignature`
  trust-matrix Pester tests and the `Test-TpmDownloadedFile -ExpectedSha256`
  mismatch tests, each independently confirming their own gate fails
  closed.
- **Failure mode if violated:** a tampered or spoofed ReShade installer,
  or a dgVoodoo2 ZIP that does not match the byte content GitHub actually
  serves, could be extracted and deployed into a user's TeknoParrot
  install as if it were genuine.

### TRUST-005 -- Thumbprint match alone is never sufficient for ReShade trust
`Test-ReShadeSetupTrustedSignature` never reports `Trusted = $true` solely
because the signer certificate's Thumbprint matches the pinned constant --
the signature `.Status` must also be on the explicit accept-list. This is
stated as its own invariant, separate from TRUST-004, because it was found
violated in a real, shipped-in-this-round implementation (an earlier
version of the function checked only the thumbprint), not merely a
theoretical property.
- **Verified by:** the dedicated "REJECTS a HashMismatch signature even
  with the exact pinned thumbprint" Pester test, plus the full status x
  thumbprint table-driven `Context` block covering every status TPM
  intentionally accepts or rejects.
- **Failure mode if violated:** a tampered or corrupted ReShade installer
  download, if its Authenticode-signed certificate metadata happened to
  still expose the pinned Thumbprint value (a field that survives some
  classes of post-signing modification independent of hash validity),
  would be treated as trusted and extracted -- this is the literal defect
  an independent review found and P1 #2 closes.

### GALLERY-001 -- Profile identity is independent of visual view mode
The gallery stores the selected approved profile as a stable `ProfileId` and
stores `ViewMode` separately (`Before`, `After`, `Split`, or `Slider`). ComboBox
entries are display-only objects carrying a validated profile ID. No gallery
handler reads an optional `.Mode` property from a selected item or uses the
view mode as profile identity.
- **Verified by:** the "uses stable ProfileId identity without reading a
  gallery item's Mode" regression, the "keeps gallery object identity and safe
  cancel behavior" regression, and the complete `Show-TpmReShadeProfileGalleryWindow`
  source audit.
- **Failure mode if violated:** a profile item with an absent or conflicting
  `Mode` property could be mistaken for view state, causing a WinForms event to
  throw or refresh the wrong profile.

### GALLERY-002 -- Gallery events cannot run against incomplete or malformed state
Preview refresh is disabled until the gallery controls, selection state, and
handlers are initialized. View, slider, and ComboBox callbacks validate their
sender/item shape and are guarded so null or mismatched selected items do not
escape as unhandled WinForms exceptions.
- **Verified by:** the executable "executes gallery callbacks safely for
  initialization and mismatched items" regression, the "suppresses gallery
  refresh events until initialization completes" regression, and the native
  source-loaded WinForms controls harness covering slider, Before/After/Split,
  ComboBox, and close events.
- **Failure mode if violated:** a TrackBar or ComboBox event fired during
  setup, or against a malformed item, could crash the gallery instead of
  leaving the terminal chooser usable.

### GALLERY-003 -- Preview failures fail closed and release gallery resources
Every gallery refresh failure records the triggering stage, disables further
preview refresh, logs the failure, and closes the optional form without
throwing through the WinForms event loop. Gallery cleanup disposes the actual
`Picture.Image`, clears that reference, safely disposes the form, and is
idempotent.
- **Verified by:** the "fails closed and records the exact preview refresh
  stage" regression, the executable callback regression with forced refresh
  failure, the "disposes the gallery picture image idempotently" regression,
  and the native forced-render-failure harness, which exits 0 after reporting
  `PreviewEnabled=False`, `Closed=True`, and
  `Stage=slider-value-changed`.
- **Failure mode if violated:** renderer errors could surface as unhandled JIT
  exceptions, leave a gallery window open in a broken state, or retain a
  disposed/undisposed bitmap across repeated close paths.

### GALLERY-004 -- Visual preview cannot mutate deployment or bypass confirmation
Gallery rendering, selection changes, event handling, and terminal profile
synchronization are transient/read-only operations. They do not deploy ReShade
files, save configuration, or claim an applied profile. Deployment remains
behind terminal `U` and the existing explicit confirmation; if the gallery is
unavailable, the typed terminal chooser remains authoritative.
- **Verified by:** the "keeps preview failure on the terminal-only path" and
  "routes ReShade selection through one visual gallery before confirmation"
  regressions, the focused 10-test menu/ReShade support run, the full 847-test
  Pester suite (847 passed, 0 failed, 0 skipped), and the native `2 -> R -> U`
  source-loaded chooser transcript (`chooser returned: CleanSharp`, `close
  returned`; marker-confirmed before controlled harness termination).
- **Failure mode if violated:** merely moving a slider or selecting a preview
  item could mutate a live game installation or make the UI claim deployment
  before the user explicitly confirms it.

## Status summary

| ID | Status | Implementation pointer | Verification pointer |
|---|---|---|---|
| TX-001 | Implemented | `Expand-ReShadeSelfExtractingArchive`, `Expand-DgVoodoo2Zip` (staging phase) | "leaves the destination completely untouched when extraction fails partway through" (both extractors) |
| TX-002 | Implemented (re-verified after the third-round phase-1 source-loss, setup-boundary, rollback-failure, and cleanup-failure matrix) | `Invoke-TpmTransactionalPromote` | `Invoke-TpmTransactionalPromote` Cases 1-8 + clean-success exact-snapshot matrix, including source-loss, setup failure, forced rollback failure, and restored-destination cleanup failure; the matching source-loss/setup/cleanup-failure cases plus clean-success and promotion-failure cases run end-to-end through both extractors |
| TX-003 | Implemented | `New-TpmStagingDirectory` + conditional `catch`/`finally` in both extractors (staging is preserved on `ROLLBACK FAILED`, `TRANSACTION CLEANUP FAILED`, or ordinary `TPM STAGING CLEANUP FAILED`) | End-to-end wrapper matrix proves no residue on clean success/ordinary rollback, preserved backup on `ROLLBACK FAILED`, preserved rollback residue on `TRANSACTION CLEANUP FAILED`, and the exact staging path plus valid destination on ordinary `TPM STAGING CLEANUP FAILED` |
| TRUST-004 | Implemented | Menu-handler wiring (`ReShadeSetup`/`DgVoodoo2Setup` mode blocks) + `Test-ReShadeSetupTrustedSignature` + `Invoke-TpmDownload -ExpectedSha256` | Trust-matrix tests; `Test-TpmDownloadedFile -ExpectedSha256` tests |
| TRUST-005 | Implemented | `Test-ReShadeSetupTrustedSignature` (`$statusAccepted -and $thumbprintMatch`) | "REJECTS a HashMismatch signature even with the exact pinned thumbprint" |
| GALLERY-001 | Implemented | `Show-TpmReShadeProfileGalleryWindow`, `New-TpmReShadeGalleryEventHandlers`, `Sync-TpmReShadeGallerySelection` | 10-test gallery run; stable-ID/view-mode and object-identity regressions; complete gallery source audit |
| GALLERY-002 | Implemented | `New-TpmReShadeGalleryEventHandlers`, `Invoke-TpmReShadeGalleryRefreshSafe` | 10-test gallery run including executable callback and initialization regressions; native slider/view/ComboBox/close harness |
| GALLERY-003 | Implemented | `Set-TpmReShadeGalleryPreviewFailed`, `Close-TpmReShadeProfileGallerySession` | 10-test gallery run including failure-stage and idempotent-image-disposal regressions; asserted native forced-render-failure harness |
| GALLERY-004 | Implemented | Gallery event handlers and `Read-TpmReShadeTerminalProfile` | Terminal-only fallback and visual-gallery ordering regressions; focused 10-test menu/ReShade run; full 847-test Pester suite; source-loaded `2 -> R -> U` transcript |

No item in this inventory is marked `Missing` or `Intentionally out of
scope` as of this round.
