# TeknoParrot Manager -- Architecture Reference

Implementation details, design decisions, and key invariants for the major
features. This is the authoritative reference for how things are built and why
particular design choices were made. For what went wrong and the lessons drawn,
see LESSONS_LEARNED.md.

Implementation-specific constraints for a given subsystem may also be
documented in that subsystem's own architecture document (e.g.
`docs/TPM-CERTIFICATION-SUITE.md` for the certification suite) rather than
here, with a matching entry in `LESSONS_LEARNED.md` -- see `CONSTITUTION.md`,
"Documenting non-obvious implementation constraints," for when this applies.

Current release state: v1.0 RC7 is the current published release; RC8 is the
candidate being prepared and is not published; v1.0 RC6 is the previous
published release (historical); final Version 1.0 remains unpublished.

---
## RC8 runtime recovery and visual selection
## Beginner-friendly default UX (RC8 release gate)

TPM is written for a user who wants to play games, not administer Windows.
Normal screens use plain English first, remain visible until acknowledgement,
and explain what happened, why an item was skipped or blocked, what TPM did or
did not change, and the next safe action. Technical paths and exceptions stay
in Details, logs, or support packages. No workflow may require knowledge of
PowerShell, PostgreSQL, XML, ACLs, reparse points, BepInEx internals,
permissions, or elevation. The release acceptance question is whether a
14-year-old can complete the workflow without that specialist knowledge.


The PostgreSQL setup path classifies client diagnostics before presenting
recovery. Password authentication failures receive a distinct masked-password
validation path; rejected credentials are not saved or logged, and profile
changes remain behind the verified backup boundary.

Crosshair browser selection is deliberately consumed from the main PowerShell
runspace. `HttpListener` completion is polled and finalized with
`EndGetContext`; PowerShell scriptblocks are never used as I/O-thread callbacks.
Listener shutdown is guaranteed, and typed numeric selection remains the
fallback when preview or browser startup fails.

ReShade profile selection opens an optional non-modal gallery and immediately
leaves the terminal at the authoritative numbered chooser. The terminal
chooser remains usable when WinForms is behind another window, closed,
unavailable, or fails to open. Numbered selection updates the gallery when it
is available; `U` is the only path toward deployment, while `B` and invalid
input remain non-mutating. The gallery changes the displayed deterministic,
TPM-owned comparison when the user changes profile, but does not deploy files.
The reference is the bundled `PreviewAssets\ReShadePreviews\TPM-preview-landscape.png`
asset, validated by System.Drawing decoding, fixed dimensions, identity
`TPM-LANDSCAPE-V1`, version `3`, and SHA-256
`7203032094bfd4d174cd3125ef55c87d7b35053fc4e274914b6ae1ac43f286d8`. `Before` is the
untouched reference, `After` contains only the selected profile transform,
and `Split`/`Slider` compose those two bitmaps at the requested boundary.
Deployment remains behind the existing explicit confirmation. The reference
identity, renderer version, and effect hashes are part of the cache key so
stale artifacts regenerate.
The gallery keeps a stable internal `SelectedProfileId` separate from the
`ViewMode` (`Before`, `After`, `Split`, or `Slider`). ComboBox entries are
display-only objects carrying a validated profile ID; event handlers never
infer view state from a selected item or read an optional `Mode` property.
Initialization keeps preview events disabled until controls and state are
complete. Every gallery event is closure-bound, guarded, and fail-closed:
renderer or state errors are logged with their stage, the optional gallery is
closed, and the terminal-only chooser remains authoritative. Gallery events,
preview refresh, and all comparison controls are visual-only; deployment is
still unreachable until terminal `U` plus the existing explicit confirmation.

**Shared game mutation path boundary (RC8).** ReShade, dgVoodoo2, GPU-fix,
and BepInEx call `Test-TpmGameMutationPath` before inspection and immediately
before a game mutation. The guard canonicalizes the registered executable,
classifies unavailable devices separately from missing leaves, rejects
reparse/inaccessible paths, and requires the resolved target to remain the
same. A failed boundary leaves that game unchanged and prevents a partial
success result from being reported as complete.
Mutation exceptions are mapped to the same `DEVICE_UNAVAILABLE` and
`GAME_PATH_MISSING` reason codes before workflow counters are updated, so an
unavailable device cannot be reported as a generic deployment error.

**PostgreSQL committed-state recovery (RC8).** The single-user `ALTER ROLE`
is the mutation cutoff. If it succeeds but service restart or new-password
authentication cannot be verified, recovery returns `PasswordChangeCommitted`
and a blocked result with evidence; it never says the old password remains
authoritative and never saves the unverified replacement credential.


## Startup: network-path detection and hard timeout (v0.99.23)

`Find-TeknoParrotRoot` and `Find-LaunchBoxRoot` filter candidate drive letters by
whether they are network paths -- a necessary check because the script refuses to
set a network-hosted root as the TeknoParrot installation folder. Originally used
`Get-CimInstance` (WMI), which caused a real 20-30s hang when a mapped drive
dropped off the network. Replaced with `[System.IO.DriveInfo]::GetDrives()`, which
avoided that specific hang but left a theoretical residual risk: the Win32 call itself
could still block on a deeply wedged share redirector.

**`Invoke-WithHardTimeout`** (next to `Test-IsNetworkPath`) wraps any scriptblock in
a background `Start-Job` and waits up to `$TimeoutSeconds` (default 5), returning
`$null` on timeout or error rather than blocking. Uses `Start-Job` (a separate
process), not a runspace/thread -- PS 5.1 has no safe way to abort a thread stuck
inside a native blocking call, so only killing the whole process actually frees it if
the theoretical deeper hang ever turns out real.

**`Get-LocalDriveInfoSafe`** wraps the actual `GetDrives()` call through
`Invoke-WithHardTimeout`. Computes the `DriveType == Network` classification INSIDE
the job scriptblock (where real `DriveInfo` instances are valid) and returns only
plain `[pscustomobject]` data (`Name`, `IsNetwork` bool). String/bool primitives
survive `Receive-Job` deserialization intact; real `[System.IO.DriveInfo]` objects do
not (they come back as `Deserialized.System.IO.DriveInfo` and fail parameter binds).
See LESSONS_LEARNED.md (v0.99.27) for the regression that proved this.

**`Test-IsNetworkPath`** accepts an optional `-Drives` parameter (the plain-object
list from `Get-LocalDriveInfoSafe`). When supplied, no job spawn happens; the caller
passes in the already-fetched drive list. Drive info is fetched ONCE per scan (not
once per candidate drive letter), threaded into every `Test-IsNetworkPath` call via
this parameter, so the hard-timeout job spawns at most once per scan.

**Performance tradeoff:** `Start-Job`'s process-spawn cost added ~736ms to the
normal-case call in a live timing test. Acceptable because these helpers are called
only at `Find-TeknoParrotRoot`/`Find-LaunchBoxRoot` start (once per script run) and
at the two interactive AutoSync-mode-entry checks, never in a hot loop.

**Fail-safe:** `Test-IsNetworkPath` returns `$false` (not `$true`) when
`Get-LocalDriveInfoSafe` returns `$null` (job timed out or errored). "Could not
determine" is never treated as "is a network path"; it just means that candidate path
is silently skipped, not silently accepted.

---

## Transactional extraction (shared by ReShade and dgVoodoo2 auto-download)

Added in a P1 remediation pass: an independent review forced a failure
partway through a multi-file extraction and confirmed the first file was
left behind in the live destination folder, contradicting an earlier
"no partial deploy" claim that described intent, not yet enforced
behavior. `Expand-ReShadeSelfExtractingArchive` and `Expand-DgVoodoo2Zip`
now share three primitives (defined next to `Test-PathInside`):

- `New-TpmStagingDirectory` -- a fresh, uniquely-named directory under
  `%TEMP%\TeknoParrotManagerStaging\`, never the real destination.
- `Copy-TpmZipEntryToFile` -- the single-entry copy step, factored out so
  both extractors share one implementation and so extraction-time failures
  are independently testable.
- `Invoke-TpmTransactionalPromote` -- moves a fully-staged, fully-validated
  set of files into the real destination. Any pre-existing destination
  file being replaced is moved aside first; if any file's promotion fails
  partway through, every file already promoted in that same call is
  removed again and every moved-aside file is restored to its original
  name/location. On a recoverable failure, the destination ends up
  byte-for-byte identical to its pre-operation state at either phase.
  If an underlying filesystem mutation makes exact restoration impossible,
  the transaction reports `ROLLBACK FAILED` / `INCONSISTENT` and preserves
  recovery evidence instead of claiming restoration.

Sequence: extract every required file into staging -> validate the
complete staged set (entry presence, sanitized names, containment,
non-zero length) -> only then call `Invoke-TpmTransactionalPromote`. The
staging directory is removed afterward on ordinary success, extraction
failure, or promotion failure whose rollback completes. It is preserved
when transaction recovery, transaction cleanup, or ordinary staging
cleanup fails, so recovery evidence/residue remains available. See
SECURITY.md ("Transactional extraction (staging + rollback-safe
promotion)") for the full rationale and the regression tests that force a
failure during extraction and a separate failure during promotion for
both extractors.

## ReShade deployment (Mode 5)

**Source DLLs.** Not bundled in the release ZIP (not redistributable -- reshade.me's
own policy: "Do NOT share the binaries or shader files. Link users to this website
instead."). Two ways to obtain them at `Scripts\ReShade\ReShade64.dll` (x64) and
optionally `ReShade32.dll` (x86): (1) the standalone "ReShade setup" menu entry's
D) auto-download option (below), or (2) manually -- run the ReShade installer on any
game exe to extract the DLL, then copy and rename it here for distribution. If absent
at startup the script prompts at runtime.

**Auto-download (freeze exception, added alongside dgVoodoo2 auto-download).**
`Get-ReShadeSetupDownloadUrl` constructs `https://reshade.me/downloads/ReShade_Setup_<version>.exe`
from `Get-ReShadeLatestVersion`'s scraped version string and validates it against the
same host-allowlist pattern used elsewhere (scheme=https, host exactly `reshade.me`,
no userinfo, path under `/downloads/`). The single-host, direct-link, no-redirect/form
download is confirmed live, not assumed.

`ReShade_Setup_<version>.exe` is a small C# WPF EXE stub with a standard ZIP archive
appended to the end of the file (self-extracting-archive format) -- confirmed by
reading crosire/reshade's own published, open-source (BSD-3/MIT) installer code
(`setup/MainWindow.xaml.cs`, `InstallStep_InstallReShadeModule`), which scans forward
for the ZIP local-file-header signature (`PK\x03\x04`) and opens everything from that
offset as a `ZipArchive`. `Expand-ReShadeSelfExtractingArchive` replicates this in
PowerShell, with one correction found during live verification: the PE stub's own
resource data (e.g. an embedded icon) can contain an earlier byte sequence that also
matches the `PK\x03\x04` signature and opens as a technically-valid but empty
`ZipArchive` -- taking the first raw signature match unconditionally therefore produces
zero entries, not the real archive. The function instead collects every `PK\x03\x04`
offset in file order and tries each as a candidate, using the first one that opens
successfully AND contains both required entries (`ReShade32.dll`, `ReShade64.dll`);
extraction happens inside that same successful iteration, but only into an isolated
STAGING directory (`New-TpmStagingDirectory`), never directly into `Scripts\ReShade\` --
see "Transactional extraction" below. Fails closed if no candidate qualifies.
Verified live against the real `ReShade_Setup_6.8.0.exe` during implementation: the
real archive's DLLs sat at file offset 152576, with an empty decoy match earlier at
offset 127840.

The compression bootstrap explicitly loads both framework assemblies before any
archive type is referenced. Windows PowerShell 5.1 does not reliably resolve
ZipArchive or ZipArchiveMode from System.IO.Compression.FileSystem alone:
ZipArchive and ZipArchiveMode are provided by System.IO.Compression.dll, while
ZipFile and ZipFileExtensions are provided by the separate
System.IO.Compression.FileSystem.dll. The production startup therefore loads
System.IO.Compression first and retains the FileSystem load for ZipFile APIs.
The regression test proves all four required types in a pristine Windows
PowerShell 5.1 child process, so a developer session with a previously loaded
assembly cannot mask the dependency.

**Signature verification before extraction (identity-pinning, stronger than
BepInEx/dgVoodoo2/FFBPlugin).** The downloaded `Setup.exe` itself is Authenticode-signed
with a self-signed certificate (Windows can never chain it to a trusted root, so
`Status` is always `UnknownError`, never `Valid`). `Test-ReShadeSetupTrustedSignature`
gates on BOTH the signer certificate's **Thumbprint** (`589690208A5E52FB96980C4A6698F50ACD47C49F`,
`$Script:ReShadeTrustedCertThumbprint`) as the hard trust anchor -- a self-signed cert's
Subject string alone proves nothing, since anyone can mint one with any Subject text --
**AND** an explicit accept-list of `.Status` values (`$Script:ReShadeAcceptedSignatureStatuses`,
currently just `UnknownError`, the one status a genuine installer produces). Both gates
must pass: a `HashMismatch` status (tampered/corrupted file) fails closed even with the
exact pinned thumbprint -- an earlier version of this function checked only the
thumbprint and missed this case; found and fixed via independent review. Subject match
is a secondary sanity check only. Fails closed on any thumbprint mismatch, unaccepted
status, missing, or unparseable signature; no auto-adoption of a changed fingerprint or
status into config. Full rationale, live-verification evidence, and the rotation
procedure: SECURITY.md ("ReShade identity-pinning with rotation"). This check happens on
the authoritative signed artifact before any extraction -- a stronger guarantee than the
manual DLL path, where TPM only ever sees a DLL the user already extracted, with no way
to confirm it came from a signed installer.

**Wiring.** The standalone "ReShade setup" menu entry's DLL-not-found branch offers
`D) Download automatically / B) Browse for a file I already have / N) Skip`. The
onboarding wizard's ReShade offer defaults to N and, if the DLL isn't already
available, points the user at the standalone menu entry rather than blocking with
manual instructions.

**Authenticode check (existing, user-supplied DLLs).** `Test-ReShadeDllSignature` (next to `Get-ReShadeLatestVersion`)
checks the embedded PE signature once per DLL at the start of `Invoke-ReShadeSetup`,
before any per-game deployment. Informational, not a hard gate: an invalid/missing
signature is surfaced loudly via `Get-SignatureStatusText` (plain English plus the raw
enum value) but does not block setup. A revocation-check failure on an offline machine
is indistinguishable from a tampered file, and bricking a user's working install over
that would be worse than the risk it guards against.

**Destination resolution.** `Get-ReShadeTargetInfo` (next to `Get-GameApiDll`) is a
pure extraction of `Invoke-ReShadeSetup`'s destination logic, shared with the Library
health check so both always agree on where ReShade would land:

- OpenParrot games: deploy to `openparrot\` subfolder if it exists.
- BudgieLoader games: rename to `opengl32.dll` (forced, regardless of API).
- Otherwise: `Get-GameApiDll`-detected DLL name from the API scan.

Verified via before/after fixture comparison across 7 scenarios (standard/OpenParrot/
BudgieLoader, with/without detected API) -- identical TargetDir/DllName output in every
case. Repeat that approach if this function is touched again.

**API detection.** Scans first 2 MB of the game exe for DX/GL import strings.
Per-game arch: x86 exe -> `ReShade32.dll`; x64 exe -> `ReShade64.dll`; unknown ->
`ReShade64.dll`.

**Per-game preset override.** `Scripts\ReShadePresets\<ProfileCode>.ini` takes
priority over the global preset chosen in the menu for that one game. Validated against
registered profiles (WRONG NAME warning for typos), never required. Same
`<ProfileCode>.ext` convention as `CustomThumbnails\<ProfileCode>.png`.

**Read-only multi-monitor suitability evidence (RC8).** `Get-TpmDisplayTopologyClassification` classifies caller-supplied display records without querying or changing monitor configuration. It distinguishes unavailable/zero-usable, single-display, multiple-primary, mixed-resolution/orientation/refresh, mirrored, no-primary, and malformed topologies. It does not assign a separate `EXTENDED` state; an extended desktop is represented by the applicable multiple-display state. Live Windows display acquisition is not wired into the eligibility path, so callers must supply the evidence. `TargetDisplayId` is optional evidence: an explicit target must still be present and connected to be `CONFIDENT`; duplicate matches are `AMBIGUOUS` and no monitor is selected. A missing target is `UNKNOWN` and does not fall back to another display. Without an explicit target, a sole usable display is confident, while multiple usable displays remain `AMBIGUOUS` until the caller identifies the game target.

The result is advisory input to ReShade eligibility only. It may add `DISPLAY_TARGET_AMBIGUOUS` and downgrade suitability to `UNKNOWN`; it never changes the primary monitor, enables or disables displays, changes resolution/refresh/orientation, moves windows, or writes game display settings. Target resolution reuses `Get-TpmResolutionClassification`, so bounded low/normal/high/wide evidence and ReShade effect-sensitivity metadata remain advisory rather than becoming monitor configuration policy. A changed or stale topology invalidates prior target confidence and requires fresh evidence.
**Canonical visual profiles and generated presets (RC8).** TPM exposes exactly five bounded profiles: Original (empty stack), Clean & Sharp (`SweetFX.LumaSharpen`), Vivid Arcade (`SweetFX.Vibrance`), Classic Arcade CRT (`FXShaders.CRT_Lottes`), and Enhanced Arcade (`SweetFX.LumaSharpen` followed by `SweetFX.Vibrance`). Profile IDs select definitions, but trust remains in the approved effect catalog, pinned revisions, required files, and SHA-256 values. Curated profile and effect metadata is `ADVISORY_UNMEASURED` with `MeasuredEvidence = $false`; no profile is marked `Recommended` or `VALIDATED_SINGLE` without measured evidence. CRT is isolated from sharpening and vibrance in normal profile mode; the enhanced two-effect order is explicit.

`New-TpmReShadePresetContent` generates stable TPM-owned preset text from the selected definition, with normalized technique order and no timestamps, randomness, paths, or user code. `Test-TpmReShadePresetContent` validates the generated structure and rejects techniques outside the approved bounded set. Original intentionally generates no effect techniques. Advanced custom `.ini` input remains opt-in and is path/extension/existence validated; its contents do not become approved effect evidence.
**Preview renderer and cache (RC8 freeze exception).** `New-TpmReShadePreviewBitmap` decodes the bundled `TPM-preview-landscape.png` reference and renders deterministic `Before`, `After`, `Split`, and percentage-driven `Slider` output. The processed bitmap is derived from the same decoded reference and cached per profile; comparison composition copies bounded pixel regions so the untouched side remains byte-stable. `New-TpmReShadePreviewArtifact` materializes results under `ReShadePreviewCache\`; rendering does not depend on live-fetched ReShade runtime files.

The cache manifest records the subject/mode, slider position when applicable, intensity identity, preset version, approved shader SHA-256 values, reference identity/version/hash, and renderer version. A missing, corrupt, stale, or mismatched manifest/image regenerates safely; cache artifacts are never trust or deployment evidence. The WinForms lifecycle keeps one reference and processed-bitmap cache per window, lazily creates it when needed, and disposes every cached bitmap during close. `Open-TpmReShadePreviewWindow`, `Update-TpmReShadePreviewWindow`, `Close-TpmReShadePreviewWindow`, and `Show-TpmReShadePreviewWindow` provide the window lifecycle. WinForms is loaded lazily, requires STA for actual display, and returns a text-only fallback in noninteractive or unavailable environments. Preview rendering and mode changes never write game files, generated presets, effect assets, trust evidence, or display settings.
**Full profile deployment and restore (RC8 freeze exception).** Normal ReShade setup and the explicit per-game restore action call `Install-TpmReShadeProfileDeployment`. It stages the architecture-selected ReShade DLL, a canonical generated `ReShade.ini` when a trusted profile is selected, and every approved effect asset, then promotes them with one `Invoke-TpmTransactionalPromote` transaction. The per-game ownership manifest is stored under `ReShade\TPM-State\Deployments\<SHA256(game ID)>.json`; ownership is committed only after the physical promotion and post-promotion hashes succeed. A later profile-history entry is written only after that deployment returns success.

Restore history is a selector, not trust evidence. Restore validates the profile schema, ordered approved effect IDs, ordered catalog hashes, and intensity variant before deployment; it never copies a historical path or arbitrary historical file. Missing, corrupt, stale, or unsupported history produces a friendly fresh-selection path. The chooser requires an explicit `R` restore choice, offers a remembered profile only after explicit confirmation, and exposes catalog-bound favorites through `F`.
The normal visual-first setup prints the profile descriptions, opens an optional
non-modal gallery, and immediately presents the terminal chooser for all five
profiles. The numbered terminal path remains authoritative when WinForms is
unavailable or the gallery closes. It does not block on modal UI or leave the
workflow without a visible prompt; text selection, `U`, `R`, `B`, and `D` all
remain available before explicit confirmation.
Before game selection, `Invoke-ReShadeUpdateIfAvailable` compares the installed trusted
installer version with the official `reshade.me` version, verifies the downloaded installer
and extracted DLLs, and offers an explicit update/keep choice. It does not deploy to games
until the source decision and all later preflight checks succeed. When multiple eligible
games are selected, setup asks once whether to apply the chosen profile to all games;
`S` retains the per-game chooser, `D` shows profile details, and `B` returns without
deployment. Remembered profiles are described as reapply actions, not restore operations.

Before replacing any target file, deployment requires a matching TPM-managed ownership entry. Existing files without that ownership evidence return `COLLISION` / `USER_OWNED_CONTENT_PRESERVED` and remain byte-for-byte untouched. Previous TPM-managed files not part of the new profile are retained rather than deleted, so switching to `Original` or a smaller effect set is non-destructive and may require manual review of old files.


**ReShade removal (RC8 freeze exception).** `Get-TpmReShadeRemovalScan` emits
one status record per registered game instead of silently discarding findings.
Records distinguish `Removable`, `ProtectedBundled`, `ProtectedAmbiguous`,
`Changed`, `MissingPath`, `MalformedMetadata`, and `AlreadyClean`. Only
reviewable records enter the existing `Select-RegisteredGamesInteractive`
chooser; no-ReShade and missing-path games are not removable targets, while
missing paths remain in the report.

`Remove-TpmReShadeOwnedDeployment` re-reads the profile and re-resolves the
current ReShade target before every backup and every deletion. It compares the
current GamePath, EmulatorType, target directory, and hook name with the
scan-time record. It accepts only `ReShadeDll`, `ReShadePreset`, and
`ApprovedEffect` entries marked `TPMManaged`, with an exact live SHA-256 match,
an existing canonical non-reparse leaf, and a destination contained by the
resolved target directory. It creates and verifies a backup before deleting
files, updates or removes only the ownership manifest, and restores files and
the manifest if the commit fails. The mode 5 `R` action previews and
enumerates remove/keep decisions and requires the literal `REMOVE` confirmation.
Its final report separates removed, already-clean, missing-path, protected,
changed, malformed, rolled-back, and failed outcomes. Game executables,
UserProfiles XML, LaunchBox data, HyperSpin data, bundled files, and ambiguous
files are never deletion targets.
Certification strict-mode invariant: empty approved-profile/effect/display
lookups, optional eligibility/storage evidence, and optional failure-result
fields are represented as explicit null/empty values. Strict certification
must preserve collision and verified-rollback outcomes instead of converting
them into property or index exceptions.
---

## dgVoodoo2 deployment (Mode 6)

**Source DLLs.** Not bundled in the release ZIP (dgVoodoo2's standalone
redistribution/hosting terms are separate from its bundled-with-a-game/mod
permission; TPM sidesteps needing either by never hosting the ZIP itself). Placed
at `Scripts\dgVoodoo2\` via either the standalone "dgVoodoo2 setup" menu entry's
D) auto-download option (below) or manually (user provides). Required DLLs from
the dgVoodoo2 ZIP: `MS\x86\D3D8.dll`, `MS\x86\DDraw.dll`, `MS\x86\D3DImm.dll`;
`3Dfx\x86\Glide2x.dll`, `3Dfx\x86\Glide3x.dll`; root `dgVoodoo.conf` (optional
config) -- subpaths verified live against the real `dgVoodoo2_87_3.zip` release
layout during implementation.

**Auto-download (freeze exception).** `Get-DgVoodoo2LatestRelease` mirrors
`Get-BepInExLatestRelease` almost exactly: queries
`https://api.github.com/repos/dege-diosg/dgVoodoo2/releases/latest` (the official
GitHub Releases channel -- authenticated, structured JSON, preferred over
HTML-scraping dege.freeweb.hu), selects the main (non-dev, non-debug) ZIP asset
by name pattern (`^dgVoodoo2[_0-9.]*\.zip$`, which the dev/debug variant asset
names like `dgVoodoo2_87_3_dev64.zip` and `dgVoodoo2_87_3_dbg.zip` fail to
match), and applies the same URL-allowlist validation (scheme=https, host
exactly `github.com`/`api.github.com`, no userinfo, path under
`/dege-diosg/dgVoodoo2/releases/download/`) and 3-attempt retry/backoff/4xx-
shortcircuit as BepInEx. Also extracts the release asset's GitHub-served SHA-256
`digest` field for `Invoke-TpmDownload -ExpectedSha256` verification -- see
SECURITY.md ("SHA-256 digest verification").

`Expand-DgVoodoo2Zip` extracts only the 6 known files at their expected subpaths
(above), sanitizing each destination name and containment-checking it via
`Test-PathInside` before writing -- same protection class as BepInEx/FFBPlugin.
Fails closed if any expected entry is missing at its expected subpath (a changed
ZIP layout in a future release is a "stop and tell the user" event), and extraction
is staged/transactional the same way as ReShade -- see "Transactional extraction"
below.

**Wiring.** The standalone "dgVoodoo2 setup" menu entry's folder-not-found
branch offers `D) Download automatically / B) Browse for a folder I already have
/ N) Skip`, mirroring the Eggman-dat menu's freshness pattern. The onboarding
wizard's dgVoodoo2 offer defaults to N and points the user at the standalone
menu entry rather than blocking with manual instructions.

**API detection.** `Get-GameLegacyApi` scans first 2 MB for D3D8/DDraw/Glide2x/Glide3x
import strings. DLL mapping:

- D3D8 -> D3D8.dll + D3DImm
- DDraw -> DDraw.dll + D3DImm
- Glide2x -> Glide2x.dll
- Glide3x -> Glide3x.dll

**Health check helper.** `Test-DgVoodoo2UpToDate` (next to `Get-GameLegacyApi`) is a
NEW function, not extracted from `Invoke-DgVoodoo2Setup`. The deploy logic also depends
on which DLLs the user has bundled -- it falls back to deploying everything available if
the ideal DLL is missing for a manually-picked game. That is an intentional difference
from "does this game need dgVoodoo2 at all." The health check answers only the latter,
independently of what is bundled.

**Per-game config override.** `Scripts\dgVoodoo2Presets\<ProfileCode>.conf` always
overwrites the destination (unlike the global conf, which never overwrites). Same WRONG
NAME validation convention as ReShadePresets.

**Beginner result screen.** A successful top-level dgVoodoo2 run renders a
plain-language summary, not just `Done.`. It identifies each deployed game's
detected legacy API, explains why older DirectX/Glide calls need translation on
modern Windows, states that existing dgVoodoo2 DLLs (including unowned or
changed DLLs) and skipped missing-path games were not changed, and gives launch,
support-package, and skipped-path recovery guidance. `DeploymentDetails` and
`SkipDetails` remain available behind `D` Details; `O` exposes the support/log
locations without creating a package.

---

## Force feedback (FFB) setup (Mode 8)

Two independent mechanisms, both optional.

### Native FFB Blaster

TeknoParrot's own built-in feature (requires any paid membership). Field name discovered
dynamically by scanning `GameProfiles\*.xml` for Bool `FieldInformation` matching
`(?i)ffb.*blaster|blaster.*ffb` -- never hardcoded.

**Capability gate.** `Get-FFBBlasterSupport` returns `{Status, Reason, WouldWrite,
Eligible, UpToDate, Changes, Platform}`. Only `Status = 'Supported'` ever sets
`WouldWrite = $true`. The deny-list (`$script:FFBBlasterUnsupportedPlatforms`) is checked
FIRST -- field presence cannot override a platform deny. An FFB-Blaster-shaped field
with a non-Bool FieldType returns `Unknown`, not `Supported`, and `WouldWrite = $false`.
This answers TWO independent questions: "does this profile have the right field?" AND
"is this platform one where the feature works?" A positive answer to the first alone is
not sufficient to authorize a write.

### Third-party plugin (mightymikem/FFBArcadePlugin)

Per-game destination-DLL table fetched live from the repo's `AutoSetup.cmd` every run --
never hardcoded or bundled. Source DLLs (`MAME32.dll`/`MAME64.dll`) also fetched live.

Overlap handling: roughly half the third-party table also has a native FFB Blaster field.
`Invoke-FFBPluginSetup` resolves all overlapping games first, then asks ONE batched
question: keep native for all of them, or use the plugin for all of them. Never silently
defaults either way.

DLL collision: if another DLL (e.g. ReShade's `d3d9.dll`) already occupies the plugin's
target filename, that game is skipped with a warning, never overwritten.

Per the plugin's README: true FFB on FFB-capable wheels (Thrustmaster/PWM2M2-style),
rumble on Xbox/XInput-style controllers.

**Skip counters.** `$skippedNoMatch` and `$skippedDllMissing` are separate. A game the
AutoSetup.cmd table does not know about is `$skippedNoMatch`; a game the table matches
but whose MAME DLL is not locally present is `$skippedDllMissing` (user-fixable). Each
has its own summary line and log field. Ownership cleanup copies the unchanged
hook to a verified game backup before deletion; if the ownership manifest cannot
be atomically rewritten, the deletion is restored from that backup and the
operation fails closed. If restoration itself fails, the backup path remains
recovery evidence and no clean completion is reported.

### Eggman dat source

Migrated from `Eggmansworld/Datfiles` (archived, fixed "teknoparrot" tag) to
`Eggmansworld/TeknoParrot` (date-based tags per release). `Get-EggmanDatRelease` queries
`.../releases/latest` instead of a fixed tag.

### Eggman recognition-data ownership (issue #252)

The Eggman/RomVault ZIP is TPM recognition data: an index TPM reads to resolve
ambiguous game/profile identities. It is not TeknoParrotUI's `ParrotData.xml`,
TeknoParrot's DAT/XML setting, a main or supplementary game ZIP, or the local
game staging/install directory.

New downloads use the deterministic per-user TPM data root
`%LOCALAPPDATA%\TeknoParrotManager\Eggman`. `Get-EggmanDatDataRoot` and
`Get-EggmanDatDefaultSavePath` only resolve that path; they do not create it.
The shared download pipeline creates the directory only when a download is
ready to write. Its partial-file cleanup remains responsible for leaving no
incomplete download behind.

The ordinary first-run `D` choice uses this default without asking the user for
a save location. The existing `B` browse/import path remains available for a
ZIP or standalone `.dat` the user already has. On a later explicit update, a
valid configured Eggman ZIP is reused at its existing location without an
alternate-location save dialog, so it is not silently relocated.

When a configured Eggman ZIP is already verified safe, the update flow
reuses a safe configured destination without an unnecessary browse prompt.
The path policy is role-based rather than location-based: the protected
TeknoParrot root, program/runtime paths, and game staging root remain blocked,
while the explicitly configured primary ZIP/source folder may be a DAT
destination when it is reachable, canonical, non-reparse, and outside those
protected roots. A mapped or NAS path is not rejected merely because it is
network-backed. The supplementary source is not auto-selected as a primary
DAT destination, and overlapping source roles are ambiguous and rejected.

Every destination supplied to the downloader, including a previously
configured or user-selected path, is canonicalized and revalidated before
reuse, download, or write. The destination is checked again immediately
before the shared downloader moves a validated temporary file into place.
If no role-safe external destination exists, TPM explains the recovery action
instead of silently skipping the update. Windows share permissions and
credentials remain an independent operating-system write boundary.
Before reuse or replacement, the ZIP must meet the expected byte count (when
known), open as a readable archive, and contain the collection DAT entry used
by `Build-DatIndexFromZip`. Validation happens before the shared downloader
replaces an existing destination. A failed or invalid download therefore
leaves the previous destination untouched and removes the partial file.

---

## BepInEx update safety and transaction boundary

Mode 9 validates the configured games root and every existing candidate
root before querying GitHub, prompting, downloading, creating a backup, or
starting a transaction. Existing path components and BepInEx target leaves
are rejected when outside the approved root or reparse-backed.

The release ZIP is staged and inventory-checked before promotion. A
timestamped BepInEx backup is copied and hash-verified before live changes.
Promotion uses one rollback-safe tree transaction; recoverable failures
restore the pre-operation tree, while rollback or cleanup uncertainty
preserves evidence and does not report clean completion. Rollback failure is
a distinct `ROLLBACK_FAILED` reason category and error counter; it takes
precedence over device/path text embedded in the original failure so recovery
uncertainty is never downgraded to a safe skip. If live promotion succeeds but
ordinary staging cleanup fails, the update is reported separately as
applied-with-cleanup-failure, excluded from the clean-update count, and the
validated residue path is logged and shown as ACTION REQUIRED. Before version
comparison, `Get-BepInExInstallationHealth` verifies required core/bootstrap
files, version, architecture, and reparse safety. A current-version but
incomplete tree therefore reaches the explicit repair-reset choice instead of
being classified healthy by version equality alone.

---

## Compatibility warnings (Get-CompatibilityWarnings)

**Data source.** `eggmansworld.github.io/TeknoParrot`. Data lives in a single inline
`<script type="application/json" id="game-data">` block -- fetch the page, regex out
that block, `ConvertFrom-Json`. 506 entries as of v0.99. Schema: `profile_name`,
`nvidia_status`/`amd_status`/`intel_status` (enum: NO_INFO/OK/WITH_FIX/HAS_ISSUES/NO),
plus free-text notes and `*_issues` fields.

**Hardcoded static data.** `$RawThrillsPathLimits`, `$FileVersionPins`,
`$GpuIncompatibleGames` are hardcoded -- static, empirically-confirmed facts about
specific old game builds/engines, not something that changes upstream. `$GpuIncompatibleGames`
is sourced from the `*_status == "NO"` enum specifically, not from free-text issue notes
(which are often "known-valid alternate file version" or antivirus false positive mentions
that look like CRC/version facts but are not "this is broken"). Verify any addition against
the live JSON directly, not a paraphrase, before hardcoding.

**GPU detection.** `Get-DetectedGpuVendor` is read-only/silent (no `Read-Host` prompt),
safe to call from the automatic every-run check. `Invoke-GpuFixSetup` layers its own
interactive fallback prompt when this returns `$null`; the automatic check just skips
silently instead.

**BepInEx game list.** `Get-BepInExRequiredGames` fetches the same JSON to build a
display-only example-games list via regex against free-text notes:
`(?i)requires?\s+(the\s+)?(latest\s+)?BepInEx|must\s+use\s+(the\s+)?(latest\s+)?BepInEx`.
No hardcoded fallback -- returns empty on any fetch failure; caller falls back to generic
wording.

**Missing emulator firmware/BIOS (issue #85 tier 1).** `$EmulatorBiosRequirements` is a
static, per-`EmulatorType` table (`@{ RelativeDir; RequiredFiles }`) of firmware files
TeknoParrot itself never bundles or downloads -- the user must obtain and place these
themselves. Currently one entry (`Pcsx2x6`), confirmed by a real install where a
correctly-registered game (per issue #79's fix) failed at launch with "PCSX2x64 Firmware
is not installed." `Get-CompatibilityWarnings` scans registered profiles' `EmulatorType`,
resolves the emulator folder via the shared `Resolve-Pcsx2Directory` helper (also used by
`Invoke-CrosshairSetup`, extracted from that function's own inline duplicate so both agree
on what counts as "present"), and reports one `BiosMissing` entry per (emulator, missing-
file-set) -- not one per affected game, since every game sharing that emulator would
otherwise produce an identical duplicate warning. Existence-only (`Test-Path`), never reads
or modifies file content: TPM does not provide, download, link, or redistribute these
files at any point. Detection is skipped entirely (not an error) when `-TeknoParrotRoot`
isn't supplied, or when the emulator's own folder isn't present yet -- nothing to check.
Read-only, informational only; never blocks or gates registration.

**Contract-backed missing emulator components (issues #254/#268).**
`Get-CompatibilityWarnings` now delegates required-component presence to the
generic `Get-ContractBackedMissingComponents` path. For each registered
`EmulatorType`, that helper loads the ECVF registry through
`TPMCertification.Contracts.psm1`, requires exactly one matching contract, and
examines only `EnvironmentCapabilities[].PresenceDetector` entries whose
method is `PathExists` and whose source is a safe relative path. The existing
pcsx2x6 directory resolver and `pcsx2-qtx64.exe` behavior remain unchanged;
other contract-backed families use a directory matching the contract ID.

A missing-component entry is produced only when the matching emulator folder
already exists and the shared `Test-TPMEmulatorPresentV1` detector reports the
contract-declared path absent. Each entry carries the contract ID/status,
evidence confidence, capability ID, detector method/source, expected path, and
the grouped affected registered profiles. The console and saved ACTION
REQUIRED summaries tell the operator to verify or restore the component through
the normal TeknoParrot installation/update process. `ExeMissing` is retained
as the compatibility result name for #254 callers; `ComponentMissing` is its
general semantic alias.

The current repository contract registry contains only `pcsx2x6`, so that is
the only real emulator family currently eligible for this warning. An
unmatched, missing, invalid, or ambiguous contract, an unsupported detector
method, or an absent emulator folder remains Unknown/unclassified and produces
no missing-component claim. This is a read-only, informational warning: it
does not claim antivirus or quarantine causality, block registration, download,
repair, re-extract, reinstall, or write to the TeknoParrot root, profiles,
configuration, ParrotData, emulator folders, or game folders.

**Pcsx2x6 first-run/crosshair prerequisite automation (issue #173).** Before this round,
`Invoke-CrosshairSetup`'s Pcsx2x6 branch silently skipped ini handling whenever
`inis\PCSX2.ini` wasn't found, and computed that path as `<Pcsx2Dir>\inis\PCSX2.ini` --
missing the `\TeknoParrot\` data-root subfolder the emulator actually uses (confirmed by
`contracts\pcsx2x6\evidence.md#ev-portable-root`, `EmuFolders::GetPortableModePath()`
defaults to `TeknoParrot` when `portable.txt` is empty/absent, and
`ev-live-ini-observation`, a hardware-verified real-cabinet path). That meant the branch
reported "PCSX2.ini not found" even on an already-initialized real install. Four new,
read-only-by-default functions replace that silent fallback:

- `Get-Pcsx2CrosshairPrerequisiteState` -- classifies a resolved pcsx2x6 install as
  `NotInstalled` / `Unknown` (ECVF framework unreachable) / `StockUninitialized` /
  `Incomplete` / `Canonical`, driven entirely by the pcsx2x6 contract's `env-init`
  `EnvironmentCapability` (`Test-TPMEmulatorPresentV1`, `Resolve-TPMEnvironmentDataRootV1`,
  `Test-TPMEnvironmentInitializedV1`) rather than a second hardcoded path/filename
  assumption. Never invokes `InitializationAction`; classification is always read-only.
- `Invoke-Pcsx2FirstRunSetup` -- only after `Get-Pcsx2CrosshairPrerequisiteState` returns
  `StockUninitialized` and the operator explicitly approves, triggers the contract's
  `InitializationAction` (`pcsx2-qtx64.exe -testconfig -portable`, the emulator's own
  headless first-run mechanism -- see `ev-testconfig-init`) via
  `Invoke-TPMEnvironmentInitializationActionV1`, then re-verifies with the same
  `Test-TPMEnvironmentInitializedV1` used for detection before reporting success. Never
  hand-authors `PCSX2.ini` content.
- `Get-Pcsx2CursorPathReport` -- strictly read-only report of the current on-disk
  `guncon2_cursor_path` values under `[USB1]`/`[USB2]` (the real section/key format per
  `ev-usb-ini-contract`, not the `[USB Port N guncon2]`/`cursor_path` format
  `Set-Pcsx2CursorPaths` still targets for its contract-denied write attempt -- that
  mismatch is harmless to write safety since the write is denied before any section is
  parsed, but it does mean `Set-Pcsx2CursorPaths` can't be reused to observe the real
  value). Surfaces operator guidance; never writes.
- `Test-Pcsx2ProcessRunning` -- guards the first-run trigger against racing a live
  `pcsx2-qtx64` process, mirroring the existing `Get-Process -Name` pattern used for
  LaunchBox/BigBox/TeknoParrotUi elsewhere in this script.

`Invoke-CrosshairSetup`'s Pcsx2x6 branch now calls `Get-Pcsx2CrosshairPrerequisiteState`
first; on `StockUninitialized` it prompts "Configure Automatically? (Y/N)" gating only the
first-run trigger (PNG placement's existing consent is the wizard's own P1/P2 selection,
unchanged) and declines to place assets or touch `cursor_path` until PCSX2.ini is actually
initialized. The ini path used for `Set-Pcsx2CursorPaths` and the new cursor-path report is
now `$prereqState.IniPath` (contract-derived, DataRoot-correct), not the old bare
`inis\PCSX2.ini` join. `Set-Pcsx2CursorPaths`'s own internal section-matching format
(`[USB Port N guncon2]`/`cursor_path`) was deliberately left unchanged -- it is dead code
today (the contract denies the write before any section is parsed), and fixing it is a
separate, narrower follow-up, not required for #173's detection/first-run/report scope.

`Invoke-TPMEnvironmentInitializationActionV1` (`TPMCertification.Contracts.psm1`) was
also fixed in the same round: `TimeoutSeconds` was declared in the contract schema but
never enforced (`Start-Process -Wait` blocks indefinitely). Since this branch's first-run
trigger is the first real production caller of that primitive, the gap stopped being
theoretical. Timeout is now enforced via `Process.WaitForExit(ms)`, killing and throwing
on a still-running process rather than blocking forever.

---

## Safe staging-folder selection (#217/#250)

The first-run AutoSync prompt treats the game installation folder as the
staging folder and normally requires no invented path. Get-TpmSafeStagingFolderDefault
derives candidates from the configured TeknoParrot volume/share and then uses
safe fallbacks; it never hardcodes a drive letter. Read-TpmStagingFolder displays
the recommendation and accepts Enter, or opens the folder browser on B.

Test-TpmStagingFolderCandidate canonicalizes each candidate and rejects a file,
an invalid path, or any symmetric overlap with the TeknoParrot installation,
main ZIP source, supplementary ZIP source, or TPM program/package directory.
Symmetric checking rejects both a staging child inside a protected folder and a
staging parent that would contain one. The first-run prompt may not know ZIP
sources yet, so the AutoSync boundary validates the saved path again after
those sources are known; recovery uses the same prompt instead of a raw browser
answer.

The prompt and validator do not create directories. AutoSync creates a missing
staging directory only after the preview decision and only for a real run.
Preview/Dry Run therefore remains read-only with respect to staging setup.

## Dry-run / preview mode (-DryRun, v0.92)

Scoped to modes 1 (AutoSync) and 2 (Register only). The other modes already have
per-feature Y/N confirmation before writing.

**Single write gate.** `Save-XmlMaybe $doc $path $DryRun` either saves for real or logs
"would save." Every dry-run-aware write goes through this wrapper -- one place that could
accidentally still write during a preview, covered by tests. `Invoke-AutoSync`,
`Register-Games`, `Repair-GamePaths`, and `Invoke-ControlPropagation` all take a
`[bool]$DryRun` parameter.

**Interactive flow.** Before AutoSync/Register work, the operator chooses an explicit
`[P] Preview only`, `[R] Run now`, or `[B] Back` action. The selector rejects all other
input and defaults to preview, so `N` cannot accidentally mean "run." Back exits before
backup, preflight, staging, or downstream input is consumed. Both preview and real paths
converge on `$dryRunActive`, which is passed into every downstream call.

**Preview skips.** The `FullBackup` step, LaunchBox/HyperSpin 2 export offers, thumbnail
download offer, and GPU fix offer are all skipped in preview mode. They are themselves
writes/downloads that do not make sense after a run that changed nothing. ACTION REQUIRED
and the controls-status file still print/write normally (reports, not mutations).

**Apply immediately.** After a preview pass, a "Preview completed successfully... Would you
like to perform the operation for real?" prompt lets the user commit without re-running the
script, explaining that applying performs a fresh scan rather than a replay of the preview
(state could have changed since it ran). Implemented via `$pendingApplyMode` (the mode to
silently re-enter) and `$forceRealApply` (consumed once to skip the preview question).
Deliberately reuses the existing `while ($true)` menu loop with `continue`/`break` rather
than a nested loop -- the loop body already has many unlabeled `continue` statements that
abort to the menu on error; wrapping it in a new loop would silently redirect those into a
retry instead.

**Known limitation.** `Get-CompatibilityWarnings` reads current UserProfiles, so during a
preview it reports the PRE-existing state, not what the previewed registrations would
produce. Fixing this requires a larger refactor and was not judged worth it for v0.92.

---

## Shared read-only detection helpers (v0.94)

The pattern: extract the "is this field already correct?" decision logic from the mutating
setup functions into separate pure helpers called by both the setup function and the
Library health check. Without this, a hand-duplicated copy of the decision logic in two
places is a real risk of silent drift (health check says "needs a fix" while the real
setup function disagrees, or vice versa).

**GPU fix:** `Get-GpuFixFieldNames` / `Test-GpuFixUpToDate` (next to `Get-DetectedGpuVendor`).

**FFB Blaster:** `Get-FFBBlasterFieldNames` / `Test-FFBBlasterUpToDate` (next to
`Invoke-FFBBlasterSetup`).

Both `Test-*UpToDate` functions return `{ Eligible; UpToDate; Changes }` rather than a
bare bool. `Changes` carries the exact XML node + new value for each field needing
updating, so the mutating setup functions do not re-derive the same vendor-specific
value-resolution branching a second time after calling the "pure" check.

**Verification discipline.** Both extractions were verified via before/after fixture diffs
-- same fixture run through pre-refactor code (pulled from git history) and refactored
code, byte-identical XML output and identical counts for every GPU vendor. Repeat that
approach if either function is touched again.

**Health check scope and guided actions.** The Library health check is strictly
read-only during inspection: it checks profile paths and shared optional-coverage
helpers, but never calls setup/install/deploy functions or writes game paths,
profiles, LaunchBox, PostgreSQL, ReShade, dgVoodoo2, GPU-fix, FFB, BepInEx, or
control state. Third-party FFB plugin coverage is NOT included -- checking it needs
a live fetch of `AutoSetup.cmd`, which would break the no-live-fetch inspection
contract. The result object carries the named broken/empty profiles and coverage
lists to the guided action screen. Automatic repair searches known game folders,
asks before saving, creates a complete `UserProfiles\FullBackup\HealthCheck_*`
backup first, and reports fixed, unchanged/unresolved, and save-failed outcomes.
Manual repair requires an explicit executable selection, validates the configured
games-root and reparse boundaries, and follows the same backup gate. PostgreSQL
and optional setup entries are direct next actions, but no mutating workflow
starts until the user selects one.

**Crosshair gallery selection.** The HTML gallery contains all discovered valid
crosshairs. A short-lived localhost bridge bound only to `127.0.0.1` accepts a
per-session token and an integer index from 0 through 320; incidental or invalid
requests do not consume the listener. If the bridge times out or is unavailable,
selection continues through the typed numeric P1/P2 fallback. Deployment has a
separate explicit confirmation before any crosshair files or state are written.

**Crosshair last-used state.** `TeknoParrot-Manager-crosshairs.json` (gitignored, like
`config.json`) remembers last-used P1/P2 crosshair filenames (not indices -- indices shift
if PNGs are added/removed). A saved filename that no longer resolves in the current
`Crosshairs\` scan is silently ignored, never an error.

---

## Health check library coverage (v0.95)

**ReShade.** `Get-ReShadeTargetInfo` is a pure extraction shared with the health check
(see ReShade section). Verified via before/after fixture comparison across 7 scenarios.

**dgVoodoo2.** `Test-DgVoodoo2UpToDate` -- new function, not extracted (see dgVoodoo2
section).

**ReShade and BepInEx install counts.** Informational only -- NOT flagged as "needs
attention." Both are open-ended per-game cosmetic/mod choices with no reliable signal for
"eligible but not applied." GPU fix, FFB Blaster, and dgVoodoo2 DO get flagged because
they have a clear right answer per game (detected GPU vendor, wheel presence, legacy API
import). BepInEx presence reuses `Get-BepInExInstalledVersion` directly (already a pure
read-only check).

---

## Supply-chain trust and download audit (v0.97)

**`Write-DownloadAudit` and `Write-TpmDownloadMetrics`.** The shared pipeline
records each live-fetched artifact's authoritative source URL, filename, version
when known, computed SHA-256, and transfer metrics (method, size, elapsed time,
average speed). ReShade additionally records installer Authenticode signer/
subject, status, signer thumbprint, and final trust result; its SHA-256 is an
audit hash rather than a published-digest comparison. BepInEx records its GitHub
release source and validates the asset digest when available. dgVoodoo2 uses the
same digest validation. Eggman/RomVault dat, FFBArcadePlugin, the PostgreSQL/
guide bundle, the TPM update package, and thumbnail downloads receive the same
source/hash/transfer audit fields, but an absent signer or digest is not treated
as cryptographic authenticity proof.

**ReShade Authenticode.** The auto-download path fetches the signed installer
from the authoritative reshade.me source and gates extraction on both the
allowlisted status and pinned signer thumbprint. `Test-ReShadeDllSignature`
remains informational for user-supplied DLLs; `Test-ReShadeSetupTrustedSignature`
is the fail-closed installer gate. Both the installer audit record and the
computed SHA-256 are retained in the log.
Under Windows PowerShell 5.1/Desktop it resolves the inbox Security, Management, and
Utility manifests directly from `$PSHOME\Modules\<module>\<module>.psd1` and imports
them with the resolved manifest path, preventing an inherited PowerShell 7 WindowsApps module
root from supplying incompatible command definitions. Under PowerShell 7+, it preserves
native module resolution. During PS5.1 imports only, the process-local PSModulePath is
scoped to the inbox root and restored in `finally`; user and machine environment is
never changed, and neither fail-closed gate is altered.

**PostgreSQL MSI.** Not Authenticode-signed (confirmed empirically via
`Get-AuthenticodeSignature`, `Status: NotSigned`). Audit-logging-only is already the
practical ceiling here. Re-check only if EnterpriseDB/the guide repo ships a newer, signed
installer.

**Scope rationale.** Cryptographic enforcement is applied where the implementation
has a real trust anchor: the ReShade installer's pinned Authenticode identity,
and GitHub asset digests for BepInEx/dgVoodoo2 when those digests are supplied.
Other live-fetched artifacts remain auditable with computed SHA-256 and transfer
metrics, but are not described as publisher-authenticated when no signer or
expected digest is available.

### Shared download pipeline (v0.99.40)

Live file downloads now go through `Invoke-TpmDownload` in `TeknoParrot-Manager.ps1`
instead of hand-rolled `Invoke-WebRequest -OutFile` loops at each call site. The helper
keeps caller-specific URL validation and allowlist checks outside the transport layer:
each feature still validates its own GitHub owner/repo/release pattern or raw content
source before handing the URL to the downloader.

Transport order is:

1. `Start-BitsTransfer`, when BITS is available and running.
2. `System.Net.Http.HttpClient`, streamed with `ResponseHeadersRead`.
3. `Invoke-WebRequest`, retained only as an emergency fallback after BITS and HttpClient
   fail.

All methods write to a sibling `.partial` file first. The helper validates that the
download is non-empty, and validates exact size when the release/API response supplies an
expected byte count, before moving the partial file into the final cache/destination path.
Failed attempts delete the partial file and leave the final path untouched whenever
possible. Progress is reported through a single `Write-Progress` activity: percent,
downloaded MB / total MB, MB/s, and ETA when `Content-Length`/BITS total size is known;
otherwise an indeterminate downloaded-MB/MB/s message is shown. Completion logs the method,
file size, elapsed time, and average MB/s, and still writes the SHA256 download audit.

Current main-script call sites using the helper:

- ReShade installer download (`Invoke-ReShadeSetup`)
- dgVoodoo2 release ZIP
- Eggman/RomVault DAT ZIP (`Invoke-EggmanDatDownload`)
- PostgreSQL guide/installer bundle
- FFBArcadePlugin DLLs
- BepInEx release ZIP
- TPM menu self-update package
- TeknoParrotUIThumbnails icon downloads (quiet final metrics to avoid per-icon line spam)

The standalone updater module (`tools/TpmAutoUpdate.Core.psm1`) has a module-local copy of
the same transport pipeline. This is deliberate for now: the main script remains a
self-contained single-file runtime, while the standalone updater stays importable and
Pester-testable as a no-side-effect module. The two implementations are kept behaviorally
aligned by tests. A future consolidation should preserve both constraints before removing
the duplication.

---

## LaunchBox direct integration (v0.98)

Feature-freeze exception, explicitly granted by the user. Do not generalize to other
LaunchBox/frontend ideas without asking again.

**Schema facts** (captured from a live LaunchBox installation, not guessed):

- A `<Game>` entry's `<ApplicationPath>` is the path to the TeknoParrot GameProfile XML
  itself (relative to the LaunchBox root), NOT the game executable. Per-game
  `<CommandLine>` is empty; the emulator template (`--profile=%romfile%.xml`, with
  `FileNameWithoutExtensionAndPath=true`) supplies the real command line by stripping
  path/extension from `%romfile%` and appending literal `.xml`.
- `ScrapeAs=Arcade` and `DisableAutoImport=true` are required on any platform this script
  creates -- TeknoParrot is not a real LaunchBox platform and will not work via the
  auto-import system (confirmed via a LaunchBox forum admin post and separately by the user).
- A real `<Game>` entry has ~80 fields, almost all scraped metadata this script cannot
  populate. `New-LaunchBoxGameEntry` clones a real existing entry from the target platform
  file and generically resets every non-identity field by type (`Missing*` -> true,
  true/false -> false, numeric -> 0, non-empty string -> blank). Falls back to a hardcoded
  skeleton only when the target platform file has zero existing entries to clone from.

**Safety requirements** (non-negotiable per explicit user request):

- `Test-LaunchBoxRunning`: refuses to write while LaunchBox/BigBox is open.
- `Backup-LaunchBoxFiles`: backs up every file about to change before any write, aborts
  the whole operation if backup fails. Scoped to the specific files changing only (not the
  whole Data\ folder -- platform files like Arcade.xml run 20+ MB).
- `Invoke-RestoreLaunchBoxBackup`: surfaced as a sub-choice under mode 11 (Restore Backup),
  not a new top-level mode. Mirrors `Invoke-RestoreBackup`'s existing UX (list by
  timestamp, confirm with YES).

**Dual-platform behavior.** "Both Arcade and a dedicated platform" creates two separate
`<Game>` records (one per platform file) pointing at the same profile. LaunchBox has no
concept of one game in two platforms; favorites/play counts are tracked separately between
the two views. Explicitly confirmed acceptable with the user.

**Platform filename safety.** A user-typed custom platform name is sanitized by
`Get-SafeLaunchBoxPlatformFileName` (strips invalid filename characters) before becoming
the `Data\Platforms\<name>.xml` filename. `Invoke-LaunchBoxDirectWrite` also runs
`Test-PathInside` against the Platforms folder before touching any path built from user
input. Same "live/user-supplied value joined into a filesystem path must be sanitized"
convention as SECURITY.md.

## HyperSpin 2 JSON export (RC8)

`Export-HyperSpinJson` treats the TeknoParrot emulator `id` in
`emulators.json` as the authoritative system identity. It scans existing
games JSON files for a matching `gameSystemId`; it never accepts a filename
or unrelated ROM extension as identity when a valid ID is present. With a valid
ID, an existing named file is usable only when it is empty or its entries
carry the same system GUID.
When the emulator entry has no `id`, export stops before creating the games
folder or writing a games file and presents Fix, Add anyway, and Skip. Skip
is the safe default and Fix returns without writes. Only an explicit Add
anyway choice enables the legacy scan for a games file whose first ROM entry
uses the `.xml` extension. If that scan finds nothing, the exporter creates
the sanitized emulator-title filename as a new empty games file. A valid ID
with no GUID match takes that named-file path directly; a nonempty existing
file with mismatched IDs fails closed instead of being mutated. It does not
use the legacy scan. Existing games files are backed up before mutation.

**Config consolidation.** `Save-Config` was consolidated from seven near-duplicate
`[ordered]@{...}` field-list blocks scattered at every settings-change call site. New
persistent settings go into `Save-Config` once, not at each call site.

---

## PostgreSQL setup for Incredible Technologies games (Mode 12, v0.99)

Feature-freeze exception, explicitly granted by the user.

**Affected games.** Golden Tee Live 2006-2019, Power Putt Live 2012/2013, Silver Strike
Bowling Live, Target Toss Pro Bags/Lawn Darts, Orange County Choppers Pinball (all
`EmulationProfile=IncredibleTechnologies`). Postgres settings live inside
`ConfigValues/FieldInformation` under `CategoryName=Postgres` -- the same generic
per-game-setting structure GPU Fix/FFB Blaster already use. `Test-GameNeedsPostgres`
detects these dynamically (category existence check); no hardcoded game list.

Backup verification failures are rendered before any PostgreSQL profile mutation.
The normal screen uses the profile's friendly `GameName` plus the technical database
identifier, states that nothing changed, and offers Retry, Skip, Details, and Back.
When the database existence query fails, TPM captures the psql diagnostic stream and
exit code before classifying the failure. The backup result retains structured
`FailureDiagnoses` plus display-safe detail text, so support can distinguish a
missing tool, stopped service, permission/elevation issue, missing database,
connection failure, or unknown query failure without treating the database as absent.
Other PostgreSQL failure branches carry explicit structured Retry and Stop
actions with remediation-specific labels (for example, check the service,
approve elevation, review evidence, or restore service state) rather than
exposing an acknowledgement-only recovery contract.

**Confirmed working silent-install recipe** (derived from real failed install attempts
root-caused via verbose MSI logs; see LESSONS_LEARNED.md for the full post-mortem):

- Target `postgresql-8.3-int.msi` directly, NOT `postgresql-8.3.msi` (a near-empty UI
  wrapper that has nothing to do under `/qn` and fails, since its only job is to drive the
  internal MSI through dialogs in the InstallUISequence, which silent mode skips).
- Required MSI properties: `INTERNALLAUNCH=1`, `ROOTDRIVE=C:\`,
  `SERVICEDOMAIN=<real computer name>` (NOT `.` -- the custom action does its own
  domain\username string handling and does not resolve `.` correctly, manifesting as
  "No mapping between account names and security IDs was done"),
  `SERVICEACCOUNT`, `SERVICEPASSWORD`, `SERVICEPASSWORDV`, `CREATESERVICEUSER=1`,
  `SUPERUSER`, `SUPERPASSWORD`, `LISTENPORT=5432`, `LOCALE=C`, `ENCODING=UTF8`,
  `CLENCODE=UTF8`, `PERMITREMOTE=0`, `RUNSTACKBUILDER=0`, `DOSERVICE=1`, `DOINITDB=1`.
- Real service name: `pgsql-8.3` (DisplayName "PostgreSQL Database Server 8.3") -- does
  NOT contain the substring "postgres"; detection/cleanup must check for `pgsql-8.3`
  specifically, never a `*postgres*` wildcard.

**Partial install cleanup.** `Remove-PostgresPartialInstall` always runs before a fresh
install attempt. A failed install leaves a real local Windows account (`postgres`) and an
orphaned profile + `ProfileList` registry SID entry behind even when the installer reports
failure. `Remove-LocalUser` alone does not clean up the profile folder or registry entry;
a leftover entry reproduces the same "No mapping" error on the next attempt.
`Remove-PostgresPartialInstall` only ever uninstalls a `PostgreSQL*8.3*` registry entry
whose `InstallLocation` matches `C:\Program Files (x86)\PostgreSQL\8.3` exactly (`-ieq`,
not `-like`), and only stops/removes a service named exactly `pgsql-8.3` (no wildcard).

**Registry cross-check.** `Test-PostgresInstallationsRegistry` (next to
`Remove-PostgresPartialInstall`) checks `HKLM\SOFTWARE\PostgreSQL\Installations\*` as
supplementary confirmation, never a blocking requirement. A partial/failed install may
never have written this key at all; its absence is "no additional information," not a
reason to skip cleanup. Only an explicit MISMATCH (key exists, entry found, points
elsewhere) blocks the uninstall. Every existing subkey under both the native and
WOW6432Node `\Installations\` roots is checked via wildcard (not assumed to literally be
`postgresql-8.3`). Uses `Base Directory` as the value name.

**MSI log and command-line security.**

The PostgreSQL 8.3 MSI receives SERVICEPASSWORD and SUPERPASSWORD through the
Windows Installer Automation interface, not a child process command line.
TPM does not print or log the property string, does not request a verbose MSI
log because this MSI can write connection passwords into deferred custom-action
logging, clears its password variables after the in-process call, and deletes
the downloaded/extracted working folder in finally.
**Credential storage.**

- Postgres superuser password: DPAPI-encrypted in config.json, tied to the
  current Windows user and machine.
- Guided recovery asks the user to choose and confirm a non-empty password.
  The password is held only for the immediate operation. If Windows permission
  is needed, TPM writes a short-lived DPAPI-authenticated envelope covering
  the password and all resume metadata: exact script/config/TeknoParrot paths
  and hashes, a durable random issuance identity, nonce, attempt number,
  creation/expiry, origin SID/machine, and parent PID/start time/executable
  path/hash. The issuance identity is encoded in the legal state filename, so
  a byte-for-byte copy cannot be consumed under another filename. The state
  directory/file ACL grants access only to the origin user, local
  Administrators, and SYSTEM. The UAC child receives only the random state-file
  path, atomically claims it, reserves a marker containing the issuance,
  nonce, and attempt, validates the envelope, decrypts the password, and
  continues option 12 automatically. Validation failure removes the marker
  and restores the encrypted challenge. UAC denial can reuse the untouched
  challenge; a started-child retry always receives a fresh attempt. The
  password is never placed in the child command line, logs, console output, or
  reports.
- Windows service-account password: never persisted; used only during
  installation and cleared afterward.
- UserProfile Postgres Pass: plaintext is required because TeknoParrotUI
  reads that field directly at game launch and has no encrypted-token
  indirection. TPM writes it only after a verified recovery backup, skips
  profiles already correct, and never includes its value in logs, summaries,
  console output, or reports. This is a local compatibility boundary.
- Recovery backups are TPM-owned evidence under PostgresRecoveryBackups.
  Inherited ACLs are removed and the current Windows identity receives full
  control. They remain until the operator removes them and may contain the
  prior plaintext profile state for exact restoration; they are not uploaded.
  **Temporary pgpass credential files.**

New-PostgresPgPassFile creates a GUID-named file in the Windows temporary
directory in libpq format. Inherited ACLs are removed and full control is
granted only to the current Windows identity. PGPASSFILE is process-scoped,
the prior value is restored after each helper, and the file is deleted in
finally. Cleanup failure blocks the operation. Passwords and native output
are redacted before diagnostic text is returned; no command-line argument
or log entry contains the password.
**Scope split.** If a profile's `Automatically create Database` field is present and `1`
(TPUI's "Express Database Install", GT2018+), this script only fills in connection fields
and leaves database creation/restore to TPUI's first-launch flow. Only for older
`GameProfileRevision`s missing that field does this script run `createdb`/`pg_restore`.

**Critical invariants.**

- Guided recovery changes only the postgres role password. It never edits
  pg_hba.conf, drops or recreates a database, restores over an existing
  database, or wipes PostgreSQL data.
- Verified recovery evidence is created before service stop, role reset, configuration
  persistence, database backup, or profile write.
- Database backup completes before config persistence or any UserProfile mutation. An
  incomplete backup returns affected game/database names plus redacted failure details;
  the operator can retry the backup, show details, skip PostgreSQL setup, or return to the
  main menu. No PostgreSQL setup mutation is reported complete after a failed backup.
- The role reset and authentication verification complete before the recovered password is
  saved to config.json. Profile setup starts only after both the protected recovery evidence
  and database backup succeed.
- A reset, restart, backup, or profile write that cannot be verified returns
  a blocked result and is never reported complete.
- Profiles are sorted deterministically. Database state is tri-state verified/
  exists so a query failure cannot be treated as database absence.
**Known accepted risks.**
- TPM's in-process Windows Installer call keeps the two installer passwords out
  of child process arguments. The MSI's lack of a signed package remains an
  audit boundary; no password-bearing verbose log is requested.
- TeknoParrotUI's plaintext UserProfile Pass field remains a compatibility
  boundary and must be protected as a local credential.
- The PostgreSQL installer is not Authenticode-signed (audit logging only).
---

## Control propagation (Invoke-ControlPropagation)

### canonicalArchetype override (v0.99.17)

Feature-freeze exception, explicitly granted by the user.

`canonicalArchetype` in `TeknoParrot-Manager.overrides.json` (`{ "family": "ProfileCode" }`)
lets the user explicitly designate which profile's Input API is ground truth for a given
button family. Implementation lives inside the existing archetype-skip branch
(`if ($sourcePaths.ContainsKey($f.FullName))`). The new code never runs unless
`canonicalArchetype` names this exact profile's family AND a different profile as the
source. Only pulls from that named profile's `InputApi` -- never a heuristic guess, never
touches bindings.

Reports `api-fixed-canonical` status (distinct from `api-fixed` for the non-archetype
API-fix case). `$validFamilies` is shared between the `familyOverride` and the new
`canonicalArchetype` parsing -- both validate against the exact same list, not duplicated.

**Critical:** After writing a canonical correction to disk, the in-memory `$pool` entry
is updated immediately (`$selfEntry.InputApi = $canon.InputApi`). Without this, downstream
targets in the same loop read the stale pre-correction API value from `$pool` (built once
at function start). PowerShell pscustomobjects are reference types, so assigning to
`$selfEntry` is visible to every later iteration. See LESSONS_LEARNED.md (v0.99.20).

### Directional vs action semantic check (v0.99.29)

`InputMapping` enum values like `P1ButtonUp` and `P1Button1` are NOT semantically stable
across game profile templates. In SF3, `P1ButtonUp` is joystick Up; in Tekken 6, the same
key is assigned to "Player 1 Left Punch" (a face button). Propagation by `InputMapping`
key equality alone silently writes wrong bindings.

`Test-ButtonNameDirectional` (next to `Get-ButtonKey`) classifies a slot as directional
only if its ButtonName, after stripping the player-number prefix (P1/P2/Player 1/Player 2),
consists EXCLUSIVELY of direction words (up/down/left/right/north/south/east/west). Any
additional qualifier (Punch, Kick, Shoulder, etc.) means it is an action button that
happens to use a direction word positionally -- not a joystick axis.

The copy site in `Invoke-ControlPropagation` (~line 6570) checks both source and target
ButtonName before cloning. If they disagree (one directional, one not), the target slot is
added to `$manual` (ACTION REQUIRED). Both sides "unknown" propagates as before --
conservative, blocking only the clear cases.

Already-contaminated profiles (e.g. Rampage, tekken6) cannot be auto-repaired if they are
already `REFERENCE` (>= `$minBound` bound) -- those buttons need manual rebinding in
TeknoParrot's own UI.

### Input API retroactive fix -- what was tried and why it was abandoned (v0.99.10-14)

v0.99.10 added a retroactive check to compare an already-bound profile's Input API against
its best-matching archetype and correct if different. The archetype-skip branch ran before
the check and silently nullified it (never fired, confirmed by grepping a real tester's
log for the fix's own log line and finding zero matches).

v0.99.12 attempted to fix that but was wrong in principle: `Build-ArchetypePool` and the
already-bound check both use the same `$minBound` threshold, so a profile bound well
enough to need the retroactive check is, by construction, always simultaneously a pool
member. There is no "already-bound but not an archetype" category that could be safely
targeted. On a real library, the fix flipped 10 archetypes to the wrong API.

v0.99.14 reverted v0.99.12 entirely. v0.99.17 (canonicalArchetype) is the correct approach
for this problem: require the user to supply the ground truth explicitly rather than
guessing it from button-key overlap.

**Known limitation.** An informational-only version (flag a mismatch without writing) would
produce the same false positives as a report -- the "best overlap match" heuristic cannot
distinguish two independently-correct archetypes from a real mismatch. Revisit only if a
tester reports a concrete real-world case of an already-bound, genuinely non-archetype
profile with a wrong Input API.

---

## Control readiness engine (issue #255)

Read-only assessment of a single profile code across three **independent**
dimensions, added as a standalone branch off issue #255's evidence session.
A tester's After Burner Climax (`abc`) session showed TeknoParrot launching a
game successfully while controls had been skipped or never verified in
TeknoParrotUI's own first-run wizard -- registration success, wizard
completion, and working controls are three different facts, and issue #253
already showed the wizard's own "Controls configuration completed" checkbox
can become checked with no mapping screen ever opened. Collapsing them into
one "Ready" boolean would reproduce that exact failure mode inside TPM
itself, so this engine deliberately never does.

**Dimensions and states** (each independent, no combined boolean):

- **Registration**: `Registered`, `Unregistered`, `Broken` -- from
  `UserProfiles\<code>.xml` alone: does the file exist, parse, have a
  `GamePath`, and does that `GamePath` still point at a real file.
- **Controls**: `Verified`, `NotVerified`, `Missing`, `Unsupported`,
  `Unknown` -- from whichever profile document exists on disk (the real
  UserProfile if registered, otherwise the read-only GameProfiles template),
  evaluated against an **authoritative requirements catalog**
  (`Get-ControlReadinessKnownRequirements`), never from raw document
  structure alone. A second review round on PR #258 found the original
  version inferred requiredness structurally -- "zero button nodes" as
  `Unsupported`, "zero bound" as `Missing`, "any bound" as `NotVerified` --
  which meant an arbitrary or malformed profile could walk through states
  it had no authoritative right to. The classifier now works like this:
  - No catalog entry for `$Code`, or the document's `ExecutableName`/
    `EmulationProfile`/`GameProfileRevision` don't _all_ match what the
    catalog entry expects (an ambiguous/unverifiable contract) ->
    **`Unknown`**. Today only `abc` (After Burner Climax) has a catalog
    entry, bound explicitly to the captured provenance: teknogods/TeknoParrotUI
    `GameProfiles/abc.xml`, `GameProfileRevision = 22`. The revision check
    exists so a future upstream revision of `abc.xml` with different
    required controls is never silently classified against this entry's
    stale requirements -- it reads as `Unknown` until a reviewer adds a
    matching contract. Every other code is `Unknown` by construction, not
    by omission.
  - The document's own `ConfigValues` declare a selected Input API
    (`FieldValue`) that is absent from its own declared `FieldOptions` --
    a real, document-declared contract violation, not a guess -> **`Unsupported`**.
  - Any catalog-required button `InputMapping` is absent from the document,
    present-but-unbound or bound with an empty binding element (per
    `Test-ControlReadinessButtonBindingUsable`, which layers a non-empty-
    content check on top of `Test-ButtonIsBound` rather than weakening that
    shared helper), or any catalog-required analog `InputMapping` is absent
    entirely or present with an empty/missing `AnalogType` (per
    `Test-ControlReadinessAnalogMappingUsable`) -> **`Missing`**.
  - Every catalog-required button and analog mapping is present and
    structurally usable (and, for buttons, bound with real content) ->
    **`NotVerified`**. This is the ceiling reachable by static evidence:
    usable, but not a successful bounded control test.
    **`Verified` is never assigned by this engine** -- confirming a control
    actually works requires real evidence (an observed successful test) that
    a static read-only pass cannot manufacture. Registration, wizard
    completion, a selected Input API, a profile's mere existence, an
    all-bound profile, or a stored physical-device reference (e.g. a
    `DirectInputDeviceGuid`) are explicitly not allowed to imply it (issue
    #255's own wording, and the specific matrix the review rounds required --
    see `Describe "Control Readiness Engine (issue #255)"`,
    `Context "Matrix: authoritative requiredness and signals that must not
imply Verified"`).
- **Launch observation**: `NotTestedByTpm`, `ObservedSuccess`,
  `ObservedFailure` -- TPM does not launch games itself (TeknoParrotUI and
  BudgieLoader own that path) and has no launch-outcome log to read today,
  so this dimension always reports `NotTestedByTpm`. The other two states
  are named as extension points for a future real evidence source; nothing
  in this engine may synthesize them from another dimension.

**Functions** (`TeknoParrot-Manager.ps1`, immediately before the interactive
menu's top-level code): `Get-ControlReadinessRegistrationState`,
`Get-ControlReadinessKnownRequirements`, `Test-ControlReadinessButtonBindingUsable`,
`Test-ControlReadinessAnalogMappingUsable`, `Get-ControlReadinessControlsState`,
`Get-ControlReadinessLaunchState`, `Test-ControlReadinessVerificationEvidence`,
`Get-ControlReadinessSummaryLines`, `Get-ControlReadinessAssessment`, and
`Get-ControlReadinessActionItems`
(combines the three dimensions into one `[pscustomobject]` row: `Code`,
`Registration`, `Controls`, `Launch`). `Get-ControlReadinessControlsState`
reuses `Get-ButtonNodes` / `Test-ButtonIsBound`, the same helpers
`Write-ControlsStatus` already uses, so bound-detection logic has exactly
one implementation; `Test-ControlReadinessButtonBindingUsable` layers a
non-empty-content check on top of `Test-ButtonIsBound` locally (an empty
`<DirectInputButton></DirectInputButton>` still counts as "bound" for
`Test-ButtonIsBound`'s own purposes, which is too permissive for readiness
classification) rather than changing that shared helper's behavior for its
other, unrelated callers. `Get-ControlReadinessKnownRequirements` builds
its tiny catalog inline on every call (not as a top-level script variable)
so the Pester harness's function-body AST extraction -- which only picks up
function definitions, not top-level script-scope variables -- includes it
automatically.

**Hard constraints** (do not weaken without an explicit CLAUDE.md /
ARCHITECTURE.md update and sign-off): never writes a UserProfile or
GameProfiles XML file; never runs `Invoke-ControlPropagation` or invokes
TeknoParrotUI's controls wizard; never infers a mapping not already present
on disk. `$Code` is validated against `^[\w]+$` (the same profile-code
invariant `Resolve-RegisteredGameFolder` already enforces, see SECURITY.md)
before being joined into either directory's path, since a future caller may
source it from an externally-fetched dat index rather than a trusted
filesystem enumeration.

**Precise I/O surface** (stated exactly, not more broadly than it is): the
control-readiness XML assessment reads `<code>.xml` under the caller-supplied
`UserProfilesDir`/`GameProfilesDir` only. Separately,
`Get-ControlReadinessRegistrationState` performs a read-only `Test-Path`
existence check against the registered profile's `GamePath` (an arbitrary
game executable location, not a UserProfiles/GameProfiles path) to
distinguish `Registered` from `Broken`. No function in this section calls
or reaches a write-capable path.

**Regression fixture.** Tests use a fixture modeled on the real, published
After Burner Climax profile (teknogods/TeknoParrotUI
`GameProfiles/abc.xml`, revision 22): Input API field plus its confirmed
required input families (Start, analog Joystick X/Y, Throttle Lever, Gun
Trigger, Missile Trigger, Climax Switch). See `Tests\TeknoParrot-Manager.Tests.ps1`,
`Describe "Control Readiness Engine (issue #255)"`.

**Display formatting.** `Get-ControlReadinessSummaryLines` turns one
`Get-ControlReadinessAssessment` row into the exact text lines issue #255's
candidate pre-1.0 UX specifies (`Game registered successfully` /
`Controls: Not verified` / `Launch status: Not tested by TPM`, followed by a
blank line and `Open TeknoParrot controls configuration and map/test controls
before treating this game as ready.`). It is
pure string formatting: it never prompts for input and never decides what a
follow-on action does. The closing instruction is included only when the (possibly
downgraded, see below) controls state is `NotVerified`, `Missing`, or
`Unknown` -- asking again after `Verified`, or asking when a profile
declares no controls at all (`Unsupported`), would be noise rather than the
recovery path issue #255 asked for.

**Runtime handoff wiring (issue #255 remediation).** After the registration
summary, `Get-ControlReadinessActionItems` enumerates the read-only
`UserProfiles` XML directory, selects only catalog-backed profile codes, and
reuses `Get-ControlReadinessAssessment` for each still-registered profile.
Ambiguous `abc` identity/revision data therefore appears as `Controls:
Unknown`; incomplete bindings appear as `Missing`; structurally complete but
untested bindings appear as `Not verified`; and positive contract violations
appear as `Unsupported`. Each item is rendered through
`Get-OnboardingHandoffSummaryLines`, so registration, launch observation,
TeknoParrot wizard state, and controls remain separate lines in the
ACTION REQUIRED console and saved summary. The recap counts these items as
manual attention, and the final next-step text tells the user to review the
controls status before treating a registered game as ready. There is still no
combined `Ready` flag. Uncataloged profiles remain outside this catalog-backed
action list and stay `Unknown` in direct assessments rather than being
promoted by heuristic structure.

**Fail-closed on `Controls = 'Verified'`.** `Get-ControlReadinessAssessment`
never produces `Verified` -- this engine has no evidence source that could
earn it. The only way `Verified` reaches the formatter is a caller building
an assessment object by hand (a review finding on the initial version of
this PR: nothing stopped `Get-ControlReadinessSummaryLines` from rendering
`Controls: Verified` for an arbitrary `[pscustomobject]` with that string
set, regardless of whether the caller had real evidence). `Get-ControlReadinessSummaryLines`
now calls `Test-ControlReadinessVerificationEvidence` before trusting
`Verified`: the assessment must carry a `VerificationEvidence` property that
is itself a `[pscustomobject]` with a non-empty `Method` (what was tested)
and a non-empty `ObservedAt` (when). Absent that, the displayed controls
state is silently downgraded to `NotVerified` -- registration, wizard
completion, a selected Input API, or a profile's mere existence must never
imply verified controls, and neither may an unqualified `Verified` string on
a hand-built object (issue #255's own wording, applied to the formatter's
input as well as to the engine's output).

**Not yet wired up.** This round adds the pure assessment functions, the
summary-line formatter, and their tests -- no interactive menu entry, no
report writer, no change to `Register-Games` or `Invoke-ControlPropagation`.
Issue #255's own scope is evidence-led investigation, not authorization to
change TeknoParrot-owned state or to decide the eventual UI surface; that is
a separate follow-up once the investigation's remaining open questions
(effective Input API, device enumeration, before/after UserProfile
comparison) are answered.

---

## TeknoParrot wizard readiness handoff (issue #253)

Read-only detection of TeknoParrotUI's own first-run wizard state, added so
TPM can tell a user what TeknoParrot may still ask them to do after
registration/AutoSync, without ever touching TeknoParrot-owned state. Issue
#253's own investigation of the upstream TeknoParrotUI source found the
wizard is shown/skipped based on `Lazydata.ParrotData.FirstTimeSetupComplete`
(`MainWindow.xaml.cs:813-816`), that `ParrotData.xml` is serialized in the
TeknoParrotUI working directory (`JoystickHelper.cs:41,56-58`), and that the
completion flag lives alongside `DatXmlLocation` (`ParrotData.cs:42-43`).
TeknoParrotUI's wizard also owns DAT/XML selection, game scanning, controls
configuration, and account/serial steps -- none of that is TPM's to perform
or claim credit for.

**Function**: `Get-TeknoParrotWizardState -TeknoParrotRoot $tpRoot` reads
`$tpRoot\ParrotData.xml` (same root TPM already resolves via
`Find-TeknoParrotRoot`, alongside the existing `UserProfiles`/`GameProfiles`
paths) and returns a `[pscustomobject]` with `State` and `DatXmlLocation`.

**States**: `Complete`, `Incomplete`, `Missing`, `Malformed`, `Unknown` --
five explicit outcomes, not a generic `Broken` catch-all:

- `Missing` -- no `ParrotData.xml` at all (clean install, or TeknoParrotUI
  never launched yet).
- `Malformed` -- the file exists but does not parse as XML (`XmlDocument.Load`
  throws).
- `Unknown` -- the file parses, but `FirstTimeSetupComplete` is absent,
  present more than once (whether the duplicate values agree or conflict --
  see below), or present exactly once with a value that isn't a
  recognizable boolean. This is the "ambiguous schema" outcome: an
  unrecognized `ParrotData.xml` layout is reported honestly rather than
  guessed at.
- `Incomplete` / `Complete` -- exactly one `FirstTimeSetupComplete` element
  found, read as `false` / `true`.

**Duplicate-field rule (Codex review).** `Get-TeknoParrotWizardState` uses
`SelectNodes('//FirstTimeSetupComplete')`, not `SelectSingleNode`, and
requires the result count to be exactly 1 before trusting it. More than one
`FirstTimeSetupComplete` element anywhere in the document -- even if every
occurrence agrees -- returns `Unknown` rather than picking one occurrence
and hoping it is authoritative, since a document with duplicate fields is
not the schema shape this detector has any confirmed contract for (see the
unverified-schema note below). This is a deliberate, documented choice, not
an oversight: see `Tests\TeknoParrot-Manager.Tests.ps1` for both the
duplicate-agreeing-value and duplicate-conflicting-value cases.

**Unverified schema assumption (explicitly flagged, not hidden).** No real,
hardware-verified `ParrotData.xml` was available to confirm the exact root
element name against during this round -- the detector locates the
`FirstTimeSetupComplete` and `DatXmlLocation` elements via the XPath
queries `//FirstTimeSetupComplete` and `//DatXmlLocation` (each matches
that element name anywhere in the document, regardless of the document's
actual root element) rather than assuming a specific root, and any
document where the expected field genuinely cannot be found reads as
`Unknown` rather than defaulting to a guess. This assumption should be
confirmed against a real installed `ParrotData.xml` before the detector is
relied on for anything beyond onboarding text.

**Handoff formatter.** `Get-OnboardingHandoffSummaryLines -Assessment
$assessment -WizardState $wizardState` combines the issue #255
`Get-ControlReadinessAssessment` row (`Registration`/`Controls`/`Launch`)
with this detector's `WizardState` into the user-facing handoff text --
four independent dimensions, reported as four separate lines, combined
only here as display text. There is still no combined "Ready" boolean
anywhere. The closing explanatory line reads "TPM registered this game.
TeknoParrot owns its own setup wizard, controls configuration, and DAT/XML
setup..." -- attributing registration to TPM and the wizard/controls/DAT
ownership to TeknoParrot explicitly and separately (an earlier draft of
this text incorrectly said "TeknoParrot handled registration," misattributing
TPM's own work; flagged and corrected in review). It fails closed on
`Controls = 'Verified'` exactly like `Get-ControlReadinessSummaryLines` (same
`Test-ControlReadinessVerificationEvidence` gate, reapplied independently
here rather than assumed from the caller), and every non-`Complete` wizard
state carries an explicit "TeknoParrot may still ask you to complete its
setup wizard" caveat -- `FirstTimeSetupComplete`, a successful launch,
bound-button counts, and stored device references are exactly the signals
issue #255/#253 both call out as **not** allowed to imply verified
controls or a finished setup, and this formatter does not let any of them
do so.

**Hard constraints** (same standing as the issue #255 engine -- do not
weaken without a CLAUDE.md/ARCHITECTURE.md update and sign-off): never
creates, writes, repairs, rewrites, or normalizes `ParrotData.xml` or any
other TeknoParrot-owned file; never invokes TeknoParrotUI's setup wizard;
never calls `Invoke-ControlPropagation`, `Set-ProfileInputApi`, or
`Save-XmlMaybe`. `Read-Xml` (the same helper the #255 engine uses) sets
`XmlResolver = $null` before loading, so this detector inherits the
existing XXE-safe parsing behavior rather than needing its own. The AST
no-write guard test checks both command names (`Add-Content`, `Set-Content`,
`Save-Xml`, etc.) and member/static invocations (`InvokeMemberExpressionAst`
covers both `$doc.Save(...)`-style instance calls and
`[System.IO.File]::Delete(...)`-style static calls) -- a CommandAst-only
check would miss .NET method calls entirely, since those never appear as a
CommandAst name.

**Read-only handoff wiring.** The #255 remediation calls the detector and
handoff formatter from the catalog-backed ACTION REQUIRED bridge after
registration/AutoSync. This is display-only: it adds no interactive menu
entry, does not launch or automate the TeknoParrot wizard, and does not write
TeknoParrot-owned state. Issue #253's coordination boundary remains intact;
determining whether any TeknoParrot-owned write is ever safe (file/field
owner, schema, backup, verification, rollback) remains separately scoped and
separately reviewed under that issue's "Acceptance and safety" section.

---

## Game registration (Register-Games)

### Two-executable profiles (v0.99.6)

Profiles with `HasTwoExecutables=true` (Initial D Arcade Stage Zero/Ver. 2/The Arcade --
always `ExecutableName2=amdaemon.exe`) need both `GamePath` and `GamePath2` set.
`Register-Games` has five separate places that resolve an exe and write `GamePath`; none
ever touched `GamePath2`.

`Set-SecondaryExecutablePath` is called from all five sites right before each
`Save-XmlMaybe`. If the matched template has `HasTwoExecutables=true`, looks for
`ExecutableName2` alongside the already-resolved primary exe and sets `GamePath2` if
found. Never overwrites an existing `GamePath2`; never fails primary registration if the
companion exe is not found.

There is no separate dat/folder hint for the second exe's location -- the schema assumes
it sits in the same folder as the primary exe, consistent with `LaunchSecondExecutableFirst`
implying TeknoParrot itself launches it from that same working directory.

### Extracted-folder resolution (v0.99.15/16/18/40)

Games renamed to the short names `$RawThrillsPathLimits` recommends (PATH TOO LONG
warning in ACTION REQUIRED) no longer normalise to match their original ZIP filenames,
causing false "needs extraction" reports.

**`Get-StagingFolderMap`** (next to `$RawThrillsPathLimits`) builds the normalised folder
map and registers multiple keys for each existing folder: the literal folder name, the
folder name without RetroBat-style suffixes (`.teknoparrot`, `.parrot`, `.game`), the
old/new convention key with spaces before metadata removed, and the full
`Get-NormalizedGameKey` value. It also maps each `$RawThrillsPathLimits` profile code to
its `Suggested` short-name folder when that folder exists.

**`Resolve-ExtractedGameFolder`** is the shared "is this ZIP already extracted?" resolver
used by `Select-GamesInteractive`, `Select-GamesInteractiveCombined`, and
`Invoke-AutoSync`. The resolver checks in conservative order:

1. Exact and normalized folder-name keys from `Get-StagingFolderMap`.
2. RetroBat suffix-aware matches (`.teknoparrot`, `.parrot`, `.game` stripped before
   comparison).
3. Known Raw Thrills/path-limit aliases from `$RawThrillsPathLimits`, using the DAT
   `ProfileCode` to connect a descriptive ZIP name to a short folder such as `ALIENS`.
4. DAT/profile identity, including profile-code keys and the registered profile fallback.
5. The registered profile path from `UserProfiles\<ProfileCode>.xml` via
   `Resolve-RegisteredGameFolder`.
6. A conservative fuzzy metadata match for harmless naming drift, such as date/year
   differences. This uses a high score threshold and runner-up gap before it suppresses
   extraction.

The resolver is intentionally read-only. It never deletes, renames, moves, or rewrites
existing game folders; it only prevents duplicate extraction prompts when an existing
candidate folder is present and non-empty. Empty folders are treated as incomplete failed
extractions and are still eligible to retry. DAT `ProfileCode` values remain validated
against `^[\w]+$` before being joined into a path (dat is untrusted external input, see
SECURITY.md).

Issue #66 added regression coverage for confirmed false positives:
`ALIENS.teknoparrot` is recognized for Aliens Armageddon via the Raw Thrills alias path,
and `Battle Gear 3 (2.08J)(2003-04-11)[Namco System 246][TP]` is recognized as the
already-extracted folder for the DAT/list entry
`Battle Gear 3 (2.08J)(2002)[Namco System 246][TP]`. The same tests cover a negative
similarly-named sequel case and ensure empty matching folders do not suppress extraction.

**Fuzzy-match alias.** The shared-executable fuzzy-match loop in `Register-Games` (~line 4640) also tries each candidate's `$RawThrillsPathLimits[$cand.Code].Suggested` value as a
second normalised string, taking the higher of the two (real code vs. short-name alias).
This is the same alias concept applied at the fuzzy-match call site, which `Get-StagingFolderMap`'s
fix never touched.

**`Invoke-AutoSync` self-heal.** A game already tracked in `syncstate.json` whose
`$stored.LocalPath` no longer matches after a rename self-heals to the renamed location on
first find (via `Get-StagingFolderMap`), so the next run hits the normal up-to-date path
directly.

### Fuzzy-match tie-break (v0.99.19)

`Resolve-BestFuzzyMatch` (same "pure, shared, testable" pattern as
`Get-GpuFixFieldNames`/`Test-GpuFixUpToDate`) tracks the runner-up score alongside the
best score. A match is only trusted (`IsConfidentMatch`) when the best score clears
`$FuzzyAutoThreshold` (0.72) AND beats the runner-up by `$FuzzyTieMargin` (0.1).
Anything that does not clear both bars falls through to dat lookup, then manual ACTION
REQUIRED -- same safe fallback as a plain below-threshold match. The `$RawThrillsPathLimits`
short-name alias fallback moved into this helper.

Both constants (`$FuzzyAutoThreshold`, `$FuzzyTieMargin`) must be mirrored in the Pester
suite's `BeforeAll` -- the AST extractor only loads function bodies, never top-level
`$script:X = ...` assignments. See LESSONS_LEARNED.md (general Pester entry, v0.99.19
extension).

### Interactive ambiguous registration choice (#300)

`Invoke-ManualRegistrationChoices` handles the remaining shared-executable cases after
`Register-Games` and duplicate-conflict resolution finish. It presents every validated
candidate profile code and writes only the profile explicitly selected by the operator.
Blank or invalid input leaves the folder in ACTION REQUIRED; no best guess is promoted.
The helper reads the immutable `GameProfiles` template, sets `GamePath`/secondary
executable state, and writes a new `UserProfiles` XML only when the destination does not
already exist. Candidate executable paths must remain inside the approved staging root.
Unresolved cases retain the TeknoParrotUI fallback in the final action summary.

### Ambiguous list post-loop filter (v0.99.8)

The "needs manual registration" list (`$ambiguous`) is filtered right before `return`
(after all passes have finished and `$matchedFolders` is fully settled) to drop any entry
whose folder key is by then in `$matchedFolders`. The filter was absent from the original
code despite `$unmatched` already having the equivalent filter one line below. Alphabetical
enumeration means a generic exe stub (e.g. `main`) can be added to `$ambiguous` BEFORE the
real named exe in the same folder sets `$matchedFolders[$folderKey] = $true` later in the
same pass. See LESSONS_LEARNED.md (v0.99.8) for the full post-mortem.

---

## Schema drift detection (v0.99.33)

`Get-GameProfileSchemaDrift` is a pure, read-only diagnostic that classifies a profile's
structure against a known baseline. Unknown top-level nodes and unknown FieldTypes are
reported but never acted on; `WouldWrite` is always `$false`. Exists so that upstream
GameProfile schema additions surface clearly before any setup flow touches new fields.

Pester contexts include: a pcsx2x6 profile that CARRIES an FFB Blaster field confirms
`WouldWrite = $false` anyway (the deny-list is checked before field presence); a new
FieldType appearing confirms `WouldWrite = $false`. These are the specific failure modes
the tests exist to prevent.

---

## Browse / file-picker integration (v0.99.28)

Feature-freeze exception, explicitly granted by the user.

`Read-PathWithBrowse` (next to `Write-Log`) wraps every file/folder path `Read-Host`
call. Typing "B" (case-insensitive, exact match only -- a path starting with `B:\` is
never misread as the trigger) opens a native Windows `FolderBrowserDialog`,
`OpenFileDialog`, or `SaveFileDialog` (`System.Windows.Forms`, ships with every Windows
PowerShell 5.1 install, no new dependency). Anything else is returned exactly as the
original `Read-Host` call already behaved.

Verified the STA apartment-state prerequisite: `powershell.exe` (Windows PowerShell,
the project's target) already defaults to STA; this does not apply to pwsh/PS7's MTA
default.

Converted every actual path prompt in the script (verified via `Read-Host` grep,
cross-checked against `path|folder|directory|\.zip|\.dat|\.dll|\.conf|\.ini` to leave
Y/N confirmations and "press Enter to continue" prompts untouched).

---

## Check for Updates (Mode 13, v0.99.39)

Feature-freeze exception, explicitly requested by the user as the planned follow-up to the
standalone `tools/Invoke-TpmAutoUpdate.ps1` helper (PR #51, merged) -- see
`docs/AUTO_UPDATE.md` for the full design and safety model shared by both.

The interactive checker is implemented as plain functions inside `TeknoParrot-Manager.ps1`
itself (`Get-ManagerUpdateRelease`, `Assert-ManagerUpdateTargetWritable`,
`New-ManagerUpdateBackup`, `Expand-ManagerUpdateAsset`, `Test-ManagerUpdateExtractedScript`,
`ConvertTo-ManagerComparableVersion`, `Invoke-CheckForUpdates`) rather than by importing
`tools/TpmAutoUpdate.Core.psm1` -- this script has no external module dependency anywhere
else, and this feature deliberately keeps that single-file, self-contained architecture. The
tradeoff is duplicated logic between the two; both are kept in lockstep deliberately (same
asset name pattern, same content-validation checks, same read-only pre-check) rather than
introducing a shared dependency.

Key invariants, each verified empirically while building the standalone tool this mirrors:

- **Never trust `Move-Item -Force` to protect a read-only target.** It silently clears the
  `ReadOnly` attribute and replaces the file anyway. `Assert-ManagerUpdateTargetWritable`
  checks explicitly, before any backup or download work begins, and refuses with an
  actionable error instead.
- **Never install unvalidated content.** `Test-ManagerUpdateExtractedScript` rejects an
  empty file, a file that is itself raw zip bytes (`PK` signature -- would happen if
  extraction were ever skipped or broken upstream), a file missing the `TeknoParrot
Manager` marker, or one missing a `$ScriptVersion` assignment, before it ever replaces
  the live script.
- **`Invoke-CheckForUpdates` never calls `exit`.** It returns `$true` only when a new
  script was actually installed; the menu dispatch block (untestable inline code, same as
  every other mode) is the only place that decides whether to `exit` (successful update --
  the in-memory code is now stale and must not keep running) or `continue` back to the
  menu (every other outcome: already current, declined, read-only, or failed). Putting
  `exit` inside the function would also kill the Pester test process that calls it.
- **URL validation is `System.Uri`-parsed, not `-like`/regex prefix matching** -- rejects
  userinfo tricks (`https://github.com@evil.example.com/...`) and lookalike hosts
  (`https://github.com.evil.example.com/...`) that a naive prefix check would miss.
- Backups go to `UpdateBackups\TeknoParrotManager_<timestamp>\`, matching this script's own
  `<Type>_<timestamp>` naming convention (see `GpuFix_`, `CursorHide_`, `FFBBlaster_`
  backups) rather than the standalone tool's `UpdateBackups\<timestamp>\` layout.
- `New-ManagerUpdateBackup` derives its backup root from `Split-Path -Parent $Path`, not
  `$PSScriptRoot`. `$PSScriptRoot` is an automatic variable PowerShell resets per function
  invocation (based on the function's own defining file/scriptblock), not an ordinary
  dynamically-scoped one -- a caller cannot override it by setting a same-named variable in
  its own scope. Found while writing the Pester tests for this function.

Startup update check (v0.99.39, same commit): `Invoke-StartupUpdateCheck`, wired in near the
top of the config-loading section (SECTION 1), gated on a new `CheckForUpdatesOnStartup`
config.json setting (default `true`) and never run under `-Unattended`. Shares
`Get-ManagerUpdateRelease`/`ConvertTo-ManagerComparableVersion`/`Invoke-ManagerUpdateInstall`
with the menu option -- the only new shared extraction was pulling the actual
backup/download/extract/validate/replace steps out of `Invoke-CheckForUpdates` into
`Invoke-ManagerUpdateInstall` so neither caller duplicates them or their confirmation
prompts (which differ: numbered "what will happen" list for the menu vs. a Y/N/V prompt
with a one-line release summary for the quiet startup notice). `Get-ManagerUpdateRelease`
gained `-MaxAttempts`/`-TimeoutSec` parameters so the startup path can use a single
short-timeout attempt (no retries) instead of the menu option's patient 3x/20s retry --
required so an unreachable GitHub cannot meaningfully delay every future launch of the
script for a check nobody explicitly asked for this time.

---

## Propagate Controls (Mode 3, v0.99.41)

Feature-freeze exception (issue #59), approved on the rationale that this introduces no
new propagation logic -- it exposes the existing, already-proven propagation pipeline
through a dedicated top-level menu entry, instead of only being reachable as the last
step of AutoSync/Register.

Implementation is a thin wrapper: the new `"PropagateControls"` mode block takes its own
UserProfiles backup (same pattern as GPU fix/cursor hide/FFB Blaster -- each standalone
destructive flow backs up independently rather than sharing one backup call), then calls
the same `Build-ArchetypePool` / `Invoke-ControlPropagation` functions the AutoSync/
Register flow already uses. No propagation algorithm code is duplicated.

**`Write-ControlPropagationResults`** (next to `Invoke-ControlPropagation`) is a new
extraction: the results-display block (per-status messaging, games-updated count,
no-archetype subset) was pulled out of the AutoSync/Register inline flow into a shared
function, specifically so this new entry point could reuse it verbatim instead of
duplicating ~35 lines of reporting logic. Both call sites now render identical output by
construction; a future change to how results are displayed only has one place to change.

Explicitly out of scope for this exception (per the approved rationale): no GamePath
repair step, no redesign of propagation behavior, no expansion beyond direct access to
the existing pipeline. The confirmation flow, hardware-mismatch warnings, and results
reporting are unchanged from what AutoSync/Register already show.

---

## Menu reorganization (v0.99.42)

Release-hardening pass, approved explicitly as menu/documentation architecture work, not
feature work: the menu had drifted into an order that reflected the sequence features were
added in, not how a user or maintainer would group them. Postgres setup (an occasional,
one-time system dependency install) sat after two maintenance-flavored modes; Library
health check sat between Restore backup and Postgres setup rather than next to Restore
backup where a "check status, then recover" reading flows naturally; Propagate Controls
(added the same release, before this reorg) landed at the end of the menu despite being a
core library-management action, not an app-level one.

**Final grouping**, applied to the menu display text and the `switch` statement only --
no `if ($mode -eq "X")` block was moved in the file, so every mode's implementation stays
exactly where it physically was and carries zero logic-change risk:

- **Library Management** (1-3): AutoSync, Register only, Propagate Controls -- the actions
  that build or update what's registered.
- **Game Enhancements** (4-9): Crosshair, ReShade, dgVoodoo2, GPU fix, FFB, BepInEx --
  all optional per-game visual/compatibility add-ons, contiguous for the first time.
- **Maintenance and Recovery** (10-12): Library health check, Restore backup, Postgres
  setup -- status-check first, then the recovery action it would inform, with Postgres
  setup last as the narrowest-scope item in the group (and the one whose own backups are
  restored via the same Restore backup flow, at mode 11, one position earlier).
- **Application** (13-15): Check for Updates, Create Support Package, Exit.

**Old -> new mapping** (for anyone cross-referencing an older screenshot, forum post, or
saved `-Unattended` invocation): 1->1, 2->2, 3 Crosshair->4, 4 ReShade->5, 5 dgVoodoo2->6,
6 GPU fix->7, 7 FFB->8, 8 BepInEx->9, 9 Restore backup->11, 10 Health check->10 (unchanged),
11 Postgres->12, 12 Check for Updates->13, 13 Propagate Controls->3, 14 Exit->15.

**Drift prevention.** `Tests/TeknoParrot-Manager.Tests.ps1`'s "Main menu source-level
drift check" reads the raw script source (the menu loop is top-level code, not a function,
so it isn't reachable through the AST function-extraction the rest of the suite uses) and
cross-checks the displayed option numbers against the `switch` statement's case labels,
asserting a contiguous 1..N sequence with no gaps and no mismatch. This is the same drift
class documented in `LESSONS_LEARNED.md` for v0.99.25/v0.99.28 (stale mode-number
references surviving a menu change); the new test makes it a CI failure instead of a
manually-run grep sweep's responsibility to catch.

---

## Adaptive responsive main menu (issue #104, included in v1.0 RC2)

**Status: included in RC2 by explicit Release Manager scope clarification.**
This began on branch `feature/issue-104-adaptive-menu-1.1` (PR #112) as
isolated future work, then was brought into RC2 after the release scope was
expanded to include completed current-cycle usability and certification work.

**Problem.** The v0.99.42 menu is a single, always-fully-detailed 14-item layout with
multi-line descriptions per item. On a narrow or short console window (a stacked terminal
pane, a small cabinet-mounted display, a low-resolution remote session) that layout can
force scrolling or wrap awkwardly -- readable on a full-size window, cramped everywhere
else.

**Design: one data model, four rendering tiers.**

The three-tier design (`Full` >=160 / `Standard` >=120 / `Compact` narrower) described in
the original issue #104 proposal was superseded during implementation by four tiers with
different breakpoints, refined through the RC2/RC2.1 cycle to cover real console width
ranges better than the original illustrative spec. This is the current, shipped design --
see `Get-ConsoleLayoutTier`'s actual thresholds below, not the three-tier numbers above,
which are historical only.

- `Get-MainMenuSections` -- the single source of truth. Returns an ordered array of section
  objects (`Header`, `Items`), each item carrying `Number`, `Mode` (the string the `switch`
  statement dispatches on), `Label`, `ShortDesc` (one line), and `FullDesc` (an array of
  lines, exactly the original v0.99.42 wording). A function, not a plain script-scope
  variable, specifically so the test suite's AST-based function extraction can see it like
  every other testable helper -- a top-level `$script:` assignment would be invisible to
  the dot-sourced test harness.
- `Get-MainMenuItems` -- flattens every section's items into one number-ordered list; used
  to derive the highest option number (the `Enter 1-N` prompt) and to avoid every caller
  re-flattening the section list itself.
- `Get-ConsoleLayoutTier -Width -Height -RequiredFullLines` -- pure, testable, and
  width-driven (console menus render in columns, not pixels; `-Height`/`-RequiredFullLines`
  are accepted and tracked for diagnostic/metrics purposes -- see
  `Get-MainMenuRenderMetrics`'s `HeightConstrained` output -- but do not themselves change
  which tier is selected). Returns exactly one of:
  - `Compact` -- width < 90
  - `Standard` -- width 90-119
  - `Professional` -- width 120-149
  - `Ultra` -- width >= 150
- `Show-MainMenu -Tier` -- pure display, never reads input. Ultra (`UltraCentered` layout
  mode specifically) reproduces the original full wording (`FullDesc`) exactly; Ultra's
  default `UltraTwoColumn` layout and Standard/Compact show progressively less detail;
  Professional has its own single-line description source (see "Description text sourcing
  varies by tier" below) rather than sharing Ultra-two-column's. Compact prints labels only.
- `Set-ConsoleMaximizedIfSupported` -- best-effort console sizing, called once at
   startup (not on every redraw). It grows `RawUI.BufferSize` before assigning
   `RawUI.WindowSize`, clamps the requested window to the resulting buffer, and
   catches unsupported-host failures. A script-scope attempt guard prevents the
   same resize error from repeating during later menu redraws; constrained tiers
   remain the normal fallback when sizing is unavailable.

**Wiring.** The main menu loop calls `Show-MainMenu -ReturnScreen` and refuses to prompt when
the returned screen is not complete for the actual viewport. In that case it prints resize
guidance and redraws; no hidden or clipped option can consume input. Once a complete screen
is available, `Resolve-MainMenuCommand` is the only command allowlist before numeric
dispatch: exact `1`-`15` selects a mode, `H` opens the distinct help screen, `L` opens the
log/report folder, and `Q` exits. Invalid text is stored as a render notice and shown on
the next cleared redraw before the prompt; legacy `U`, leading-zero numbers, and blank input
are rejected before any workflow branch can see them. Help returns on Enter and does not
alter menu expansion state.

**Unchanged by design:** existing menu numbering (1-13) and every existing mode's own behavior remain
unchanged; option 14 adds the support-package workflow and Exit is now option 15. The `switch`
dispatch and adaptive renderer keep the same one-source menu model.

**Description text sourcing varies by tier -- a real gap found in review (RC3).**
`Get-MainMenuSectionRows` does not use one shared description field for every tier:
Standard and Compact tiers show no description at all (Detail `'Labels'`); UltraCentered
(single-column) uses `$item.FullDesc`; Ultra-two-column and Professional use their bounded
description sources depending on `$Geometry.Layout`. The rendered command surface is
deliberately limited to the visible numeric options plus the footer's H/L/Q commands;
there is no hidden `?` help command or compact-tier hint advertising one.

**Complete-or-block rendering (RC8).** `Render-MainMenuScreen` never presents a partial
numbered menu. It first computes the visible option set against the caller's actual width
and height; the prompt is allowed only when every option 1-15 is visible and the layout
fits within the viewport. A too-short or otherwise incomplete render shows resize guidance
and the main loop consumes no menu choice. This prevents a beginner from selecting a
different action because the intended item was clipped below the prompt.

For tall enough windows, narrow layouts use a flow-packed fallback that keeps the normal
version banner and footer while fitting all numbered labels. For very short windows, the
emergency compact layout uses one-line banner/footer rows and whole, never-split item
tokens. If that still cannot fit, the renderer shows only the banner and resize guidance;
it does not trim the front or tail of the numbered menu.

**Emergency compact presentation for very short viewports (RC8).** The emergency renderer
uses `Get-MainMenuMinimalBannerRows`, `Get-MainMenuMinimalFooterRows`, and
`Get-MainMenuFlowPackedItemRows` to preserve the version identity, every whole numbered
item token, and the quit/help controls. The row budget is the caller's real requested
`-Height`, not the geometry helper's clamped math height. If all item tokens still cannot
fit, the result is banner plus resize guidance with `PromptAllowed = $false`; no partial
numbered list is offered and the next loop iteration redraws without consuming input.

**Test changes.** "Main menu source-level drift check" was rewritten to validate the data
model (`Get-MainMenuItems`) against the `switch` statement's case labels, instead of the
old raw-text `Write-Host "N)"` regex -- the menu is no longer hand-written display lines, so
that approach no longer applies. Same intent as the original test (no numbering gaps, the
`Enter` prompt matches the highest item), adapted to the new architecture. New Describe
blocks cover `Get-MainMenuSections`/`Get-MainMenuItems`, `Get-ConsoleLayoutTier`, and
`Show-MainMenu` directly. `Tests/VirtualBetaTester.HumanWorkflow.Tests.ps1`'s main-menu
extraction marker (which locates the inline if/else block by a distinctive string in its
own source text) was updated from the literal `"Library Management"` header -- which no
longer appears inline in the if-block, since it now lives inside `Get-MainMenuSections`
-- to `"Show-MainMenu"`.

## Shared workflow status and footer (issue #300)

`New-TpmWorkflowStatusContext` creates the structured state machine used by
multi-step RC8 workflows. Public transitions emit
`TPM.WorkflowStatusEvent.v1` events through an injected sink; cosmetic console
rendering never drives workflow decisions. Events carry sequence, immutable
step denominator, attempt, current activity, next step, user action, outcome,
bounded recent completions, and sanitized failure/data-safety fields. Passwords,
secure strings, native arguments, and raw exception text are excluded.

The renderer remeasures window and buffer geometry before every draw, owns only
its recorded footer rectangle, clips stale cells after resize, and truncates
rows to the current width. It refuses a first or subsequent cursor draw when
the body cursor occupies the footer rectangle, and switches to append-only when
scrolling changes the recorded window origin; it never clears arbitrary
scrollback after that invalidation. `Read-HostSafe` clears and redraws the
footer around prompt input. A too-short or failing RawUI downgrades to
append-only status lines; redirected, unattended, and certification runs keep
events but perform no cursor or progress writes. Failures remain pinned until
acknowledged. The existing menu clear/repaint path is never used as failure
acknowledgement. Workflow start rejects a second active context, and every
workflow branch must close or acknowledge/finalize before returning to the menu.

## Support package architecture (issue #300)

`New-TpmSupportPackage` is a fixed-scope collector invoked by the top-level
menu's option 14. It creates a uniquely named ZIP beneath the script's
`SupportPackages\` directory and returns a structured result with
`Succeeded`, `Partial`, `PackagePath`, per-source records, and failures.
Collection is split into TPM-owned files, allowlisted TeknoParrot files,
registered-game text logs, and metadata-only plugin inventories.

TPM and TeknoParrot sources use explicit relative filename allowlists. Game
diagnostics are considered only for registered game paths inside the approved
games root with non-reparse path chains. Profile paths are opened through a
controlled .NET stream, and the stream handle's final filesystem identity is
compared with an identity-validated profile-root handle before XML parsing.
The same opened-object identity proof protects game logs and TPM/TeknoParrot
diagnostics. The collector reads text only; plugin directories are inspected
for metadata and hashes but DLL payloads are never copied. Plugin hashes use
the validated opened stream; unsafe path-based version probes are omitted.
Every text artifact is validated as strict BOM-aware UTF-8/UTF-16 text and
rejected with `RejectedUnsafeContent` when it has executable/archive
signatures, NUL/control bytes, or invalid encoding.

The manifest records environment facts without usernames, source paths, or
secrets, and every dynamic source, destination, detail, error, and scope value
passes centralized redaction before insertion. ZIP entry names are generated
from bounded safe names. Promotion holds an identity-validated destination
directory handle, creates the ZIP with `CREATE_NEW`, writes through that
opened file handle, and verifies both root and file final identities after the
write. Staging cleanup opens each owned entry by handle, rejects reparse
objects, deletes only through those handles, and preserves residue if the
owned tree cannot be proven unchanged. Any unsafe path, staging failure,
redaction/read failure, or ZIP failure prevents a success result. Workflow
status is closed in `finally` on every exit path; redirected, unattended, and
certification hosts therefore retain the existing structured-status fallback
without cursor writes.

**Operator summary.** The normal console output presents counts for games checked, files
collected, plugin inventories, optional diagnostics not present, collection failures, and
intentionally excluded content. The manifest retains per-record detail, including verbose
`NotPresent` reasons, without flooding the default beginner-facing summary.

---

## Versioning

- Whole-number bumps: feature releases (v0.94, v0.95, ..., v0.99).
- Third segment: bug-fix-only releases (v0.99.1, v0.99.2, ...), introduced v0.99.1.
- Feature-freeze exceptions: LaunchBox (v0.98), Postgres (v0.99), canonicalArchetype
  (v0.99.17), Browse option (v0.99.28). Each required explicit user approval. Do not
  generalize any of these without asking again.
- A patch release (third-segment bump) still gets the full treatment: version bump in
  `$ScriptVersion` and the header comment, CHANGELOG entry, all doc version lines,
  wiki entry, tag + ZIP + GitHub release + prune-to-5. It does NOT need a full doc-sweep
  for new features/mode numbers -- by definition nothing user-facing changed except
  behavior that was already supposed to work.

## Certification-only and publication boundary

`Complete-TPMProductionCertificationCycleV1` is fail-closed by default:
certification issues the dispatcher-owned final outcome directly from sealed
eligibility and does not invoke `New-TPMPublicationCommitV1`. The result keeps
an explicit skipped commit object so callers can display that no publication
occurred. The report builder marks this outcome `NotRequiredForCertification`;
it does not infer that state from a failed publication.

The publication/finalization path is retained behind the explicit `-Publish`
switch. This separation prevents publisher availability, staging collisions,
or commit-marker failures from turning a completed certification decision into
an infrastructure block. Infrastructure failures before an authoritative
outcome remain harness-level `BLOCKED`.

## Certification finalization transaction (issue #154)

Complete-TPMCertificationTransaction is the sole authority for the final outcome, over the complete evidence lifecycle, not only the pass/fail decision. It is modeled as a database transaction: it consumes immutable, already-recorded facts -- a private workflow-owned issuance ledger, the scorecard's own Items, an authoritative artifact manifest -- rather than trusting descriptions of those facts that a caller could construct independently, and it treats publication as the final step of the same commit rather than a separate operation the caller has to keep in sync with the decision by hand.

**Round 3 (issue #154): from "validate the description" to "validate against the authority."** Round 2 made the transaction the sole decision authority and added manifest/ordering/derived-score checks, but those checks still validated the _public_ `$Results.Screenshots` array and a caller-supplied `$Certification.Items`/artifact set directly -- both are ordinary mutable objects nothing stops another piece of code (or an adversarial test) from constructing a convincing-looking substitute for, with every field, including `WorkflowId` and `Sequence`, copied from a real record. Round 3 does not add more field-level validation on top of that; it changes what is trusted:

- **Authoritative evidence issuance ledger, not the public array.** `$script:tpmEvidenceLedger` is a private, workflow-owned list populated only by `Add-Screenshot`, in real append order. `Complete-TPMCertificationTransaction` validates the caller-submitted `$Results.Screenshots` against this ledger by **reference identity, position for position** (`[object]::ReferenceEquals`) before it validates anything about individual records. A brand-new object with every field copied from a real ledger entry -- Name, Label, Path, WorkflowId, Sequence, all of it -- is still a different object, and reference identity is false for it. This is what "cannot be reconstructed merely by copying public fields" means concretely: the unforgeable fact is which object the workflow actually produced, not what any object claims about itself.
- **Ordering derived from ledger position, not a trusted property.** `Sequence` remains on each record as an informational/reporting field, but the transaction no longer trusts it for anything security-relevant -- a mutated `Sequence` on an already-issued object cannot forge a different position, because ordering is read directly from the ledger's own append order (`$ledger[$ledger.Count - 1]` must be `final-certification-result`).
- **Replay prevention and "final record issued last" by construction, not by check.** The ledger seals itself (`$script:tpmEvidenceLedgerSealed`) the instant `final-certification-result` is issued (`Add-Screenshot`), successfully, skipped, or failed. Any further `Add-Screenshot` call after that throws immediately. There is no code path left that can grow the ledger once sealed -- the "final record was genuinely last" invariant holds even before the transaction checks it.
- **Path ownership, containment, and identity/filename consistency, enforced at issuance and re-verified at commit.** `Add-Screenshot` rejects (fails closed, before the record ever enters the ledger) any path that escapes the run's `-ScreenshotDir`, or that duplicates a path already claimed by another ledger entry. `Complete-TPMCertificationTransaction` re-verifies containment, uniqueness, and that each record's filename and `Label` actually match its identifier, against the ledger's own copies of those fields, as defense-in-depth against direct same-scope ledger manipulation (a residual risk distinct from a caller constructing a public-looking object -- see "Documented boundary" below).
- **Real capture provenance for ScreenCapture evidence.** A required `ScreenCapture`-typed record must carry a non-empty `CaptureScope` (`Window` or `FullDesktop`, from `Save-TPMScreenCapture`) -- a `Captured` status with no recorded capture scope is rejected, since it cannot have come through the real capture path.
- **Authoritative score-item manifest, not an arbitrary Items array.** `Get-TPMExpectedScoreItemManifest` is the exact, closed set of certification score-item identifiers. `Test-TPMScoreItemManifest` validates `$Certification.Items` against it -- exact identifiers, no missing/extra/duplicate, strict `[bool]` `Passed` (a truthy non-Boolean like `'true'` or `1` is rejected), and correct NotApplicable/tri-state usage per item -- _before_ `Get-TPMCertificationScoreFromItems` is ever allowed to compute a score from it. A synthetic one-item "100% passing" scorecard cannot reach the scoring arithmetic at all.
- **Mandatory, manifest-validated publication commit.** `-BuildArtifacts` is a required parameter (`[Parameter(Mandatory=$true)]`) -- omitting it is a PowerShell binding error, not a silently-skipped publish. `Get-TPMExpectedArtifactManifest` defines the exact five authoritative artifact identities (four reports plus the commit marker); `Test-TPMArtifactManifest` validates the callback's returned set against it (exact Ids, unique destinations, every destination contained within `-ReportDir`) before `Publish-TPMCertificationArtifacts` ever touches disk.
- **A decision snapshot, not the transaction object, is what gets serialized.** The object handed to `-BuildArtifacts`, and the one attached to `$Certification.Finalization`/`$Results.Finalization` for JSON/Markdown serialization, deliberately has no `Published`/`PublicationError` fields. Those fields describe the outcome of an operation (publication) that has not happened yet when the content is generated -- embedding them would always serialize a stale value (`$false`, or whatever was true before the real outcome existed) into a report that might go on to publish successfully. The commit marker (below) is the actual durable proof of a complete publish; because a failed publish never leaves it on disk at all, its content never needs to describe an outcome that hadn't happened when it was written.
- **A real commit boundary: durable verification plus a commit marker, not just stage-then-promote.** `Publish-TPMCertificationArtifacts` treats the last artifact in the array (always the commit marker, by manifest) specially: every other artifact is staged, promoted, and durably re-read back from disk to confirm it matches what was staged, and only once all of that succeeds is the marker itself promoted and durably verified. A concurrent reader, or a process resuming after an interrupted run, should treat the marker's absence as "not committed" regardless of what report files already exist on disk -- partial output is never authoritative.
- **Documented boundary: this defends against constructed descriptions, not same-scope memory tampering or content forgery.** Everything above defends against a caller (or an adversarial test acting as one) constructing an object, array, or artifact set that merely _describes_ legitimate workflow output. It does not defend against an actor with the ability to directly mutate this script's own private state (`$script:tpmEvidenceLedger`, etc. -- the same risk class as editing the script itself) or against a structurally-valid PNG whose _content_ was substituted for a different real capture's bytes (see the regression test "rejects a reused PNG substituted for the final-certification-result path" for the explicit boundary: this documents it as intentionally out of scope, the same way PNG semantic/content authenticity was already out of scope for the validator -- see `docs/PNG-EVIDENCE-VALIDATOR-SPECIFICATION-INVENTORY.md`).
- **Commit atomicity and rollback semantics** (`Publish-TPMCertificationArtifacts`): every artifact is staged to a `.pending` file first; if staging, promotion, or durable verification fails partway, every pending file and every already-promoted file from this attempt is removed, and a pre-existing destination is never overwritten or deleted.

### System Invariant Inventory

1. The evidence manifest contains exactly these identifiers once each: certification-suite-running, requested-effective-root-evidence, live-thumbnail-evidence, live-controls-evidence, the three adaptive-menu captures, smoke-file-safety-evidence, and final-certification-result.
2. Required evidence is every non-skipped production capture. Every required record must be Captured, have its manifest-declared type, carry the current workflow provenance identifier, have a path, and pass PNG validation again during finalization.
3. The two conditional live-evidence slots are optional only when represented as pathless Skipped records. Optional evidence cannot masquerade as a capture or failure.
4. Exactly one case-sensitive final-certification-result must exist and must be the required validated ScreenCapture created in the current workflow. Zero, duplicates, wrong identity/type/provenance, skipped, failed, or unrelated substitutes fail.
5. Unexpected, null, malformed, extra, conflicting, or duplicate evidence fails the manifest. A later success never removes an earlier required failure.
6. A passing numeric score cannot override evidence failure. Conversely, complete evidence cannot override a failed score. Both are derived from `$Certification.Items` at commit time, never trusted off a precomputed field, and `$Certification.Items` is itself validated against `Get-TPMExpectedScoreItemManifest` before it is trusted (round 3).
7. Final PASS, CERTIFIED, and exit code 0 are emitted only together. Every other combination becomes FAIL, NOT CERTIFIED, and exit code 1.
8. Reports and console text render the transaction object; they do not recalculate outcome. The process exits with that same transaction's ExitCode.
9. The pre-final screenshot display is explicitly provisional and cannot claim certification before final evidence is validated.
10. Final report publication is guarded and is part of the same commit as the decision: a write failure downgrades the transaction in place, removes partial authoritative report files, prints only a failure console outcome, and exits nonzero; a final PASS console is emitted only after all reports (including the commit marker) are durably written and verified.
11. Every evidence record carries an informational `Sequence`, but ordering itself is derived from the ledger's own append position, never trusted off that property. `final-certification-result` must be the ledger's own last entry (round 3: previously a `Sequence` comparison; a mutable property is not a security boundary).
12. **(Round 3) Submitted evidence must be reference-identical, position for position, to the workflow's private issuance ledger.** A record with every field copied from a real one, a reordered submission, an extra fabricated record, a record missing from the submission, or a record replayed from a different workflow run's ledger all fail here -- this is the primary defense the round-2 design lacked.
13. **(Round 3) The evidence ledger seals on `final-certification-result` issuance.** No further evidence can be appended afterward (`Add-Screenshot` throws) -- replay-after-finalization is structurally impossible, not merely detected.
14. **(Round 3) Path ownership, containment, uniqueness, and identifier-to-label/identifier-to-filename consistency** are enforced both at issuance (`Add-Screenshot`, fail closed) and again at commit time against the ledger's own field values.
15. **(Round 3) Required ScreenCapture evidence must carry a real, non-empty CaptureScope.**
16. **(Round 3) `$Certification.Items` is validated against the exact expected score-item manifest** (identifiers, count, uniqueness, strict Boolean `Passed`, correct tri-state usage) before it can influence the score at all.
17. **(Round 3) `-BuildArtifacts` is mandatory**, and its returned artifact set is validated against the exact expected artifact-identity manifest (five identities, unique, contained within `-ReportDir`) before anything is written to disk.
18. **(Round 3) Serialized certification/validation content never embeds a `Published` field.** The commit marker's mere presence on disk, promoted and durably verified strictly after every other artifact, is the only authoritative proof of a complete publish -- there is no stale self-referential publish state to go wrong.

## ADR-0155 production fact adapter (ADR155-0309 Checkpoint B1)

`scripts/TPMCertification.ProductionFacts.psm1` builds all eleven raw facts
the production authority (`TPMCertification.Production.psm1`) consumes. It
is a dedicated module, separate from `TPMCertification.Shadow.psm1`'s Phase 2
adapter: it never imports or calls Shadow, and never expands Shadow's public
surface. Full design rationale, defect history, and evidence: ADR-0155
implementation checklist (`docs/adr/ADR-0155-IMPLEMENTATION-CHECKLIST.md`,
Checkpoint B1 entry). Key structural decisions:

- **The authoritative production PowerShell inventory is fixed and
  non-overridable.** `Get-TPMProductionPowerShellInventoryV1` takes only
  `-RepositoryPath` -- there is no parameter through which any caller,
  production or test, can substitute a different file set. The real,
  17-entry list (the union of the release-package PowerShell contents and
  every ADR-0155 production certification/harness script/module) lives in
  a module-private constant; a separate, unexported
  `Resolve-TPMProductionPowerShellInventoryEntriesV1` does the actual
  missing/duplicate/outside-root/unreadable validation and is the only
  thing tests exercise with a synthetic file list (via Pester's
  `InModuleScope`).
- **Static Analysis facts are real, not placeholders.** Parser (both engines,
  one out-of-process invocation per file, explicit timeout, exact
  requested-file/result correlation, cross-file engine-version consistency),
  encoding (multi-file, aggregate `NonAsciiByteCount`), PSScriptAnalyzer, and
  InjectionHunter all run fresh over the complete inventory every time --
  `Test-TPMProductionPSScriptAnalyzerV1`/`Test-TPMProductionInjectionHunterV1`
  never read the legacy harness's own precomputed `$Results.PSScriptAnalyzerFindings`.
- **InjectionHunter disposition identity is File + RuleName + Extent
  (match key), with Line only disambiguating multiple identical
  same-file occurrences.** Registry entries and current findings sharing a
  match key are paired one-to-one in ascending-Line order; a count mismatch
  either way leaves the surplus finding(s) Confirmed/unresolved or the
  surplus registry entry(ies) stale (fail-closed). A duplicate raw finding
  identity (File+RuleName+Extent+Line appearing twice from a single scan)
  is treated as a scanner defect and also fails closed.
  `scripts/InjectionHunterDispositions.psd1` is the checked-in disposition
  record for every current finding across the complete inventory.
- **Artifacts preflight genuinely exercises the real pipeline.** Rather than
  trusting `Get-Command` visibility as the dependency contract,
  `Test-TPMProductionPackagePreflightV1` drives a full synthetic run through
  the real production authority, all five report builders, the manifest,
  the commit marker, and `New-TPMPublicationCommitV1`, entirely inside one
  owned scratch child directory it creates beneath the caller's
  `PreflightScratchRoot` (see the scratch-ownership invariant below) --
  never the caller's real `StagingParentRoot`/`DestinationRoot`, which are
  checked separately for write-reservation only.
- **Bounded execution for in-process analysis.** PSScriptAnalyzer and
  InjectionHunter scans run via `Invoke-TPMBoundedScriptBlockV1`, which uses
  `Start-Job` (a genuine background process) rather than a same-process
  runspace -- confirmed necessary because `DiagnosticRecord.Line`/`Column`
  are ScriptProperties bound to the producing runspace, not intrinsic .NET
  properties, and cross-runspace access to them was unreliable. This gives
  every per-file scan a real wall-clock timeout.
The default bound is 180 seconds per file for PSScriptAnalyzer because analysis
of a real inventory file can exceed one minute on a slow Windows PowerShell 5.1
engine. The bound remains finite; a timeout still fails the fact closed as not
executed.

### Scratch-directory ownership invariant (New-/Remove-TPMOwnedScratchDirectoryV1)

`Test-TPMProductionPackagePreflightV1` used to recursively delete its
caller-supplied `PreflightScratchRoot` directly in a `finally` block -- if
that path pre-existed or were misbound to a broad directory, unrelated data
could be erased. The corrected model:

1. `New-TPMOwnedScratchDirectoryV1` creates and owns exactly one
   GUID-named child beneath a validated parent; it rejects a pre-existing
   child name, an out-of-root child path, and (if the resulting child were
   ever found to be a reparse point) refuses to proceed.
2. `Remove-TPMOwnedScratchDirectoryV1` re-verifies containment and
   re-checks for a reparse point immediately before deleting, and
   recursively removes only that exact owned child -- never the caller's
   parent, never a pre-existing directory, never anything the containment
   check can no longer prove is the same path.
3. Cleanup failure is folded into `PackageValidationErrorCount` and forces
   `PackageValidationPassed=$false` -- it can never be silently masked by an
   otherwise-successful pipeline proof.

### System Invariant Inventory (Checkpoint B1)

1. The production PowerShell inventory returned by
   `Get-TPMProductionPowerShellInventoryV1` is always the same fixed
   17-entry list; no exported parameter, on this function or any other
   production entry point, can substitute a different file set.
2. Every inventory entry must exist, be readable, resolve inside the
   repository root, and be distinct from every other entry -- a single
   invalid entry fails the whole inventory rather than silently shrinking
   it.
3. `Static Analysis`'s Parser/Encoding/PSScriptAnalyzer/InjectionHunter
   sub-facts are always freshly observed against the complete current
   inventory; none of them may be populated from a previously computed or
   externally supplied value (in particular, never from the legacy
   harness's own `$Results.PSScriptAnalyzerFindings`).
4. A parser probe's `Executed=$true` requires every requested file to have
   produced exactly one structured, schema-valid, exactly-correlated result
   from the exact same engine version -- a version mismatch across files,
   a missing/extra/malformed result, or any file failing coverage forces
   the whole engine's result to `Executed=$false`.
5. An InjectionHunter disposition-registry entry's identity is File +
   RuleName + Extent + Line; two entries may never share that full
   identity. A finding's match against the registry uses File + RuleName +
   Extent only, with same-key entries and findings paired in ascending-Line
   order -- a registry entry that cannot be paired against any current
   finding (stale) fails the whole check closed; a finding that cannot be
   paired against any registry entry is Confirmed/unresolved, never
   silently passed.
6. A duplicate raw current-finding identity (File+RuleName+Extent+Line
   appearing twice from a single scan) is never silently deduplicated or
   double-counted -- it fails the check closed as a scanner-integrity
   defect.
7. `Test-TPMProductionPackagePreflightV1` never writes synthetic
   certification-looking artifacts into the caller's real
   `StagingParentRoot`/`DestinationRoot` -- every genuine pipeline
   invocation happens inside its own disposable, owned scratch child.
8. `PublisherAvailable`/`PackageValidationPassed` can never be `$true` on
   the strength of `Get-Command` name resolution alone -- they require a
   genuine, successful synthetic invocation of the real authority/report/
   publication pipeline, including a real canonical-filename cross-check.
9. A scratch-directory helper never recursively deletes a caller-supplied
   parent directory, a path that no longer resolves inside its recorded
   parent, or a path that is (or has become) a reparse point -- it deletes
   only the one child it itself created and still owns.
10. Every `Artifacts` fact carries an ordered `PackageValidationDiagnostics`
    collection. Each diagnostic preserves the real publication/preflight
    `Stage`, `FailureCode`, `FailureMessage`, and optional `ExceptionType`; the
    broad `PUBLISHER_UNAVAILABLE` and `PACKAGE_VALIDATION_FAILED` decisions
    retain that detail in both authority `Details` and failure-reason text.
11. `Complete-TPMProductionCertificationCycleV1` requires an identity guard.
    The production harness guard re-snapshots branch, commit, remote, refs,
    and reflogs before eligibility, before commit, after commit, after final
    outcome, and after final projection. A rejection after commit stays inside
    the existing rollback boundary and cannot leave an authoritative-looking
    marker without a valid identity.

### System Invariant Inventory (collection abort and launcher exit)

1. Production composition is reachable only after the harness records that
   every collection gate completed. An exception before that point is an
   infrastructure abort, never an authoritative NOT CERTIFIED decision.
2. The first collection exception is retained as the initiating error record
   and diagnostic. Cleanup and abort reporting must not replace it with a
   secondary schema or strict-mode exception.
3. Incomplete collection cannot create a production authority, adapt facts or
   evidence, seal a run, issue an outcome, or invoke publication. It returns a
   nonzero process exit and writes no authoritative marker or bundle.
4. A health result without an explicit load error is valid input to the
   production fact adapter only when it is a structured object with a present,
   non-null, non-empty collection-valued `Checks` property. Every entry must be
   a non-null `PSCustomObject` with a present, nonblank string `Name` and a
   present strict-Boolean `Passed`; scalar/nested-collection entries, malformed
   unexpected entries, missing required checks, and duplicate required checks
   are deliberate `PRODUCTION_HEALTH_RESULT_SCHEMA_INVALID` infrastructure
   errors before any member is trusted. The adapter never invents `Checks` or
   weakens strict mode. Structurally valid additional checks are permitted but
   are not projected into the three-check authoritative fact.
5. An explicit install-health load error remains evidence of a fail-closed
   `Missing` or `InvalidJson` fact. That path does not require a health result
   object and is distinct from the invalid no-error schema states above.
6. On normal child completion, the PowerShell direct and relaunch paths return
   the harness's exact exit code; a thrown harness error or unavailable pwsh
   fails nonzero rather than being converted to success. The batch launcher
   returns the `RUN_EXIT` captured immediately after its PowerShell child even
   when the report/Explorer presentation branch runs; pause, Explorer launch,
   `popd`, and `endlocal` cannot replace that saved result. No exact numeric
   code is promised for a child that terminates by exception before producing
   one.
7. Process-level abort tests use only copied synthetic repositories and
   test-local module/source substitution. No production parameter, environment
   variable, or callable hook can inject a collection failure or bypass a gate.

## ADR-0155 production harness cutover (ADR155-0309 Checkpoint B2)

`scripts/Invoke-TPM-RealInstanceSmoke.ps1` is now driven end-to-end by the
Phase 3 production authority (`TPMCertification.Authority.psm1` /
`.Production.psm1` / `.ProductionCycle.psm1` / `.ProductionFacts.psm1` /
`.ProductionEvidence.psm1` / `.Publication.psm1` / `.Reports.psm1`) --
`Complete-TPMProductionCertificationCycleV1` is the sole certification
decision/publication path the harness invokes. Full design rationale,
defect history, and evidence: ADR-0155 implementation checklist
(`docs/adr/ADR-0155-IMPLEMENTATION-CHECKLIST.md`, Checkpoint B2 entry). Key
structural decisions:

- **The harness never imports or calls `TPMCertification.Shadow.psm1`.**
  Shadow remains a standalone, never-authoritative Phase 2 observer module,
  exercised only by its own test suite -- it has no wiring into the
  production harness at all (Checkpoint B1's shadow-observer integration is
  superseded, not extended). `scripts/TPMCertification.ProductionEvidence.psm1`
  is a fresh, independent evidence adapter (`New-TPMProductionEvidenceRecordV1`,
  its only exported function) converting the harness's legacy
  `Add-Screenshot` evidence-ledger records into the production authority's
  evidence schema -- it does not reuse or call any Shadow.psm1 code.
- **Every competing legacy certification/publication path is deleted, not
  merely bypassed.** `Complete-TPMCertificationTransaction`,
  `Get-TPMCertificationScoreFromItems`, `Test-TPMScoreItemManifest`,
  `Test-TPMArtifactManifest`, `Publish-TPMCertificationArtifacts`, and their
  associated `Get-TPMExpectedScoreItemManifest`/`Get-TPMExpectedArtifactManifest`/
  `Get-TPMCertificationFinalConsoleLines`/`Get-TPMCertificationFinalReportLines`
  helpers no longer exist anywhere in the harness source. There is no
  remaining code path that can assign a competing `FINAL STATUS`/`Overall`/
  exit code, or write a competing report/marker/bundle.
- **Exactly one authoritative destination, one bundle, one publisher.**
  `$reportDir` is the sole publication destination; `New-TPMPublicationCommitV1`
  (invoked only through `Complete-TPMProductionCertificationCycleV1`) is the
  sole writer of `TPM-Certification-{Eligibility,Publication,Final-Outcome,
Scorecard,Validation,Manifest,Commit}.{json,md}`. The remaining
  non-authoritative surfaces are clearly distinct and never share a
  filename or an outcome-bearing field with the authoritative bundle:
  - The pre-flight `TPM-Invalid-Certification-Environment.{md,json}`
    diagnostic, written only when the requested TeknoParrot root fails
    validation, before the production authority is even constructed --
    it throws immediately after, so it never reaches the decision surface.
  - The "TPM CERTIFICATION SCORECARD - PROVISIONAL" console block, explicitly
    labeled "Pending: final evidence validation" and computed by informational-
    only inline arithmetic (not `Get-TPMCertificationScoreFromItems`, which no
    longer exists) -- it never sets the exit code and is clearly distinguished
    from the genuine, dispatcher-issued final status printed later.
- **An exception before a genuine final outcome produces an infrastructure
  abort, never a fabricated certification decision.** The entire
  authority-construction-through-cycle-completion sequence (build authority,
  record 11 facts, record 9 evidence records via `New-TPMProductionEvidenceRecordV1`,
  issue final evidence, seal, invoke `Complete-TPMProductionCertificationCycleV1`)
  runs inside one `try`/`catch`. Any exception there sets `$productionAborted`,
  prints an explicit "CERTIFICATION PIPELINE ABORTED (infrastructure failure)"
  diagnostic naming the failure, and exits `1` -- it never falls back to the
  removed legacy mechanism, never reports `CERTIFIED`/`NOT CERTIFIED`, and
  never publishes a marker or bundle.
- **Publication and finalization are identity-guarded as one rollback window.**
  `Complete-TPMProductionCertificationCycleV1` requires the production caller
  to supply a guard and invokes it before eligibility, before publication,
  after commit, after the dispatcher issues the final outcome, and after the
  final projection is built. The real smoke harness guard re-snapshots the
  checkout and compares it with the pre-cycle identity. A mutation after
  commit is therefore treated like any other post-commit finalization failure:
  the commit marker is removed first and the cycle reports rollback success or
  rollback failure truthfully.
- **The dispatcher-issued final outcome is the sole source of the harness's
  externally visible status and exit code.** `$productionCycleResult.Projection`
  (`FinalStatus`, `ExitCode`, `RunIdentity`) drives the only "FINAL STATUS"/
  "EXIT CODE" lines and the only `exit` call reachable after certification
  facts/evidence begin recording.

## Certification isolation and result-validation hardening (ADR155-0309, 2026-07-24)

`scripts/TPMCertification.Execution.psm1` is the shared child-process
isolation primitive (`Invoke-TPMIsolatedProcessV1`) and Pester-result contract
validator (`Read-TPMPesterResultV1`) every certification child process and
structured result in this pipeline goes through. Full design rationale,
defect history (including two real regressions found and fixed during
independent review -- a transient file-lock race and a directory-auto-create
regression), and the complete adversarial test inventory are in the ADR-0155
implementation checklist (`docs/adr/ADR-0155-IMPLEMENTATION-CHECKLIST.md`,
"ADR155-0309 certification isolation and result-validation hardening" entry).
Summary:

- **`Invoke-TPMIsolatedProcessV1`** launches every certification child
  (Pester, the parser probe, PSScriptAnalyzer/InjectionHunter bounded jobs'
  external dependencies, the adaptive-menu renderer, the unattended-TPM
  relaunch) with `-NoProfile -NonInteractive`, a GUID-nonce-prefixed,
  `FileMode.CreateNew` empty stdin file (never inherited stdin), separate
  stdout/stderr files, a bounded timeout with confirmed termination
  (`Stop-Process` plus a `WaitForExit` grace window and an explicit
  `HasExited` re-check -- never fire-and-forget `Kill()`), and a
  `<prefix>-process.json` metadata record that logs executable identity
  (filename only), phase identity, PID, timing, exit code, and argument
  _count_ -- never argument content. Its working/log directories are resolved
  to a full path, verified non-reparse-point, and (via
  `Assert-TPMOwnedDirectoryV1 -CreateIfMissing`) created on first use if they
  do not already exist. As of the round 3 correction below, the caller must
  supply a distinct `-WorkingDirectoryRoot`/`-LogDirectoryRoot` trust anchor
  for each -- see "Trusted-root wiring correction" for what each real caller
  supplies and why.
- **`Read-TPMPesterResultV1`** treats the JSON result `Invoke-TPM-PesterChild.ps1`
  writes as a closed contract: exact top-level and `Categories` field sets,
  pinned `SchemaVersion`, every numeric field constrained to a true bounded
  nonnegative integral type, `Discovered == Passed+Failed+Skipped+NotRun`,
  `FailedContainers <= Containers`, `VirtualBetaTesterTotal ==
VirtualBetaTesterPassed + VirtualBetaTesterFailed` bounded by the applicable
  global totals, and `Failures` a present array whose entry count equals
  `Failed` exactly, with every entry's `Name`/`Message` a nonblank string.
  Every malformed state throws the single `PESTER_RESULT_SCHEMA_INVALID:
<reason>` error family, which the harness's collection-abort gate (see
  "System Invariant Inventory (collection abort and launcher exit)", above)
  turns into an infrastructure abort with no authority/facts/evidence/marker/
  bundle produced -- never a raw `PropertyNotFoundException`.
- **`TPMCertification.ProductionFacts.psm1`'s external-process helper**
  (`Invoke-TPMExternalProcessWithTimeoutV1`) delegates directly to
  `Invoke-TPMIsolatedProcessV1` rather than maintaining a second isolation
  implementation, so every parser/PSScriptAnalyzer/InjectionHunter child
  inherits the same closed-stdin, bounded-timeout, confirmed-termination
  guarantees.
- **No blanket confirmation suppression** (`$PSDefaultParameterValues['*:Confirm']
= $false` or equivalent) exists anywhere in `scripts/` or `Tests/`; each
  call site that needs non-interactive behavior handles it locally. Real,
  bounded child-process probes prove `Read-Host`, `$Host.UI.PromptForChoice`,
  a `-Confirm`-triggering `ShouldProcess` call, and a missing-mandatory-
  parameter cmdlet call all fail promptly with a nonzero exit and no hang
  under `-NonInteractive` with closed stdin, on both PowerShell engines.

### Fail-closed correction round (PR #155 static review, ADR155-0309)

A follow-up static review of the isolation primitive above found two places
where the original hardening still failed open. Both are now fail-closed;
neither claims to eliminate every possible filesystem race in general, only
the specific ones described here.

**Log-sanitization retry (`Write-TPMSafeTechnicalFileV1`).** The original
bounded retry around reading/writing a just-exited child's captured
stdout/stderr (see the transient-handle-release race in LESSONS_LEARNED.md)
retried every `IOException` indiscriminately and, on exhaustion, silently
returned as if sanitization had succeeded -- so a persistently locked file
left unsanitized content in place with no signal to the caller.
`Invoke-TPMSafeFileRetryV1` now classifies exceptions before retrying:

- **Retried** (transient only): an `IOException` whose `.HResult` is exactly
  `0x80070020` (`ERROR_SHARING_VIOLATION`) or `0x80070021`
  (`ERROR_LOCK_VIOLATION`) -- the two Win32 codes the just-exited-child
  handle-release race actually produces. `Exception.HResult` is a plain
  `Int32` on every `System.Exception` in both Windows PowerShell 5.1 (.NET
  Framework) and pwsh 7+ (.NET), so this classification is identical under
  both engines without any engine-only API.
- **Not retried** (fail immediately): every other `IOException` (disk-full,
  a bad/missing path, `PathTooLongException`/`DirectoryNotFoundException` --
  both of which derive from `IOException` and would otherwise have been
  silently retried too), `UnauthorizedAccessException`, and anything else.
- **Bound**: 20 attempts, 100ms apart (~2 seconds worst case per direction --
  read and write are each retried independently), chosen because the
  handle-release race this exists for is a sub-second OS delay; 2 seconds is
  headroom without letting a genuinely stuck lock hang the pipeline.
- **On exhaustion**: throws a deliberately tagged exception
  (`SANITIZATION_RETRY_EXHAUSTED: operation=... target=... attempts=...
elapsedMs=... innerType=... innerHResult=...`, carried as a
  `System.IO.IOException` with the original exception preserved as
  `InnerException`) rather than returning. Both the read half and the write
  half of `Write-TPMSafeTechnicalFileV1` throw on exhaustion -- neither can
  silently look like it succeeded. The underlying unsanitized file is never
  deleted or overwritten on failure (the preserved technical evidence for
  diagnosis), and no unsanitized content is ever written to the operator
  console, including on this failure path. Because
  `Invoke-TPMIsolatedProcessV1` calls this function unguarded, the exception
  propagates naturally into the harness's existing top-level `catch`, which
  is the same "PIPELINE ABORTED (infrastructure failure)" path every other
  isolation failure already uses -- no separate classification wiring was
  needed.

**Owned-directory reparse validation (`Assert-TPMOwnedDirectoryV1`,
`New-TPMCreateNewFileV1`).** The original version checked only the final
directory's own `ReparsePoint` attribute and used a `$path.StartsWith($root

- separator)`containment check. Two gaps: (1) a reparse point anywhere in
an *ancestor* of the owned directory -- not the directory's own leaf
attributes -- can silently redirect the effective location, and a
leaf-only check never saw that; (2)`-Force`on`New-Item -ItemType
  Directory` silently no-ops if something (including an attacker-planted
  reparse point) already exists at that exact path, rather than failing.
  Now:

* `Assert-TPMNoReparseInChainV1` validates every _existing_ path component
  from the declared owned root through the target (inclusive of both ends),
  individually, for the `ReparsePoint` attribute -- not just the final leaf.
  Only the single authorized creation leaf (`-CreateIfMissing`'s target) may
  be missing; every other missing component in the chain is rejected, not
  silently created.
* Containment is a component-boundary comparison
  (`Test-TPMPathIsContainedV1`, splitting both paths into segments and
  comparing element-by-element), not a string-prefix check -- immune to
  sibling-prefix confusion (`C:\Owned-Evil` is never treated as being under
  `C:\Owned`).
* `Assert-TPMOwnedDirectoryV1 -CreateIfMissing` now requires the parent of
  the directory being created to already exist and pass validation, creates
  the leaf with plain `New-Item` (no `-Force`, so a raced/attacker-planted
  entry at that path fails the creation instead of being silently reused),
  and then **revalidates the entire chain again** before returning --
  narrowing the TOCTOU window between the pre-creation check and the
  directory actually coming into existence. The pre-creation validation is
  never trusted to still hold post-creation.
* `New-TPMCreateNewFileV1` still uses `FileMode.CreateNew` (never
  `Create`/`OpenOrCreate`) so file creation itself fails closed rather than
  silently reusing or overwriting an existing (possibly attacker-planted)
  file, and now validates the file's own containment/reparse chain with the
  same component-boundary/chain-walk logic instead of the old prefix check.
* This closes the specific reparse-redirection and sibling-prefix races
  identified in this round's review -- it is not a claim that every possible
  filesystem race anywhere in the certification pipeline is eliminated.

**Trusted-root wiring correction (ADR155-0309 round 3).** An independent
static reviewer found that the round-2 version of `Assert-TPMOwnedDirectoryV1`
above, while it did walk the full chain from "root" to "target" for reparse
points, was always invoked internally with Root and Target set to the SAME
path (`Assert-TPMNoReparseInChainV1 -Root $full -Target $full`). Because
`Assert-TPMNoReparseInChainV1`'s chain walk only inspects components at or
below the point where Root and Target parts start to differ, a Root==Target
call inspects _only the leaf_ -- functionally identical to the pre-round-2
leaf-only check the round-2 work was written to fix. An intermediate-level
junction (e.g. planted at the harness's own `Reports` or `ProductionWork`
folder, one level above the timestamped run directory actually passed in)
was never inspected at all; `New-Item -ItemType Directory` was then relied
on to silently create that unvalidated intermediate level as part of
creating the deeper leaf. This defeated the round-2 hardening's actual
purpose without failing any of round 2's own tests, because every one of
those tests happened to validate a directory that was already exactly one
level below an already-existing, already-validated parent -- the specific
gap (an intermediate level ABOVE a multi-level missing path) was never
exercised.

The fix makes the trusted root a distinct, explicit, CALLER-SUPPLIED
parameter that is never inferred, and never silently collapsed onto the
target just because the target happens to already exist as a directory:

- `Assert-TPMOwnedDirectoryV1 -Root <trustedRoot> -Path <target>
[-CreateIfMissing]` -- `-Root` is validated on its own (must exist, be
  stat-able, and not itself be a reparse point) before anything else
  happens. `-Path` must equal `-Root` or be a component-boundary descendant
  of it; Root==Target is a deliberately supported, explicitly tested case
  (e.g. a caller's own already-established top-level directory), not an
  accidental default. A drive/path-root-qualifier mismatch between `-Root`
  and `-Path` (e.g. root on `C:`, target resolving to `D:`) is rejected
  before any filesystem access.
- `-CreateIfMissing` still creates only the single immediate leaf -- its
  parent must already be an existing, already-validated component of the
  chain. Bringing a _multi-level_ path into existence beneath a trusted
  root (e.g. `HarnessRoot\Reports\<stamp>`, two levels below `HarnessRoot`)
  now goes through `New-TPMOwnedDirectoryChainV1 -Root <trustedRoot> -Path
<target>`, which creates/validates one authorized level at a time via
  repeated `Assert-TPMOwnedDirectoryV1 -CreateIfMissing` calls -- never by
  asking the filesystem to create several untracked intermediate levels in
  one call, which is exactly the shortcut the round-3 defect exploited.
- `New-TPMCreateNewFileV1 -Root <trustedRoot> -Parent <parent> -Name <name>`
  now takes the same distinct trusted-root parameter, revalidates `-Parent`
  against it, and then revalidates the full chain a SECOND time immediately
  before the underlying `FileStream` is actually opened -- a second,
  closer-to-use TOCTOU-narrowing point, distinct from the post-creation
  revalidation `Assert-TPMOwnedDirectoryV1` already performs.
  `Invoke-TPMIsolatedProcessV1`'s own directly-created metadata file
  (`<prefix>-process.json`, which does not go through
  `New-TPMCreateNewFileV1`) gets the same pre-open revalidation call
  inline, for the same reason.
- **Residual race, stated plainly:** narrowing a TOCTOU window is not
  eliminating it. A substitution that lands strictly between the final
  pre-use revalidation and the actual open/create call remains possible in
  principle on this OS; this code fails closed (throws) if it is ever
  observed at any validation point, but no claim is made, in code comments
  or here, that the race is eliminated -- only narrowed at each additional
  validation point.

**`Invoke-TPMIsolatedProcessV1`** now takes `-WorkingDirectoryRoot` and
`-LogDirectoryRoot` as separate mandatory parameters alongside
`-WorkingDirectory`/`-LogDirectory`. Every real caller was updated to supply
its own genuinely-already-established trust anchor, never a convenient but
unvalidated parent:

- `scripts/Run-TPM-Tests.ps1` -- `HarnessRoot` (the tool's own top-level,
  operator-configured output boundary) is the root for `$reportDirectory`
  and `$logDirectory` (both brought into existence via
  `New-TPMOwnedDirectoryChainV1 -Root $HarnessRoot`, replacing the previous
  raw `New-Item -ItemType Directory -Force` loop over both paths at once).
  `$RepoPath`/`$resolvedRepo` is its own root for the working-directory
  parameter (Root==Target: the repository checkout itself has no
  narrower, more-authoritative ancestor available to this tool).
- `scripts/Invoke-TPM-RealInstanceSmoke.ps1` -- same pattern: `$reportDir`,
  `$backupDir`, and `$productionWorkingDirectory` are all established via
  `New-TPMOwnedDirectoryChainV1 -Root $HarnessRoot` near the top of the
  script (replacing the previous raw `New-Item -Force -Path $reportDir,
$backupDir`). All three `Invoke-TPMIsolatedProcessV1` call sites (Pester
  child, unattended-TPM relaunch, adaptive-menu renderer) use `$reportDir`
  as `-LogDirectoryRoot` (their `-LogDirectory` is always
  `$reportDir\TechnicalLogs`, one level below) and `$RepoPath` as
  `-WorkingDirectoryRoot` (Root==Target).
- `scripts/TPMCertification.ProductionFacts.psm1` -- `New-TPMProductionFactRecordsV1`
  gained a new mandatory `-WorkingDirectoryRoot` parameter, threaded through
  `Test-TPMProductionParserProbeV1` and `Invoke-TPMExternalProcessWithTimeoutV1`
  down to `Invoke-TPMIsolatedProcessV1` (used as both the working- and
  log-directory root, since the parser probe's working directory and log
  directory are deliberately the same directory). The real harness caller
  supplies its own already-established `$productionWorkingDirectory`
  (`HarnessRoot\ProductionWork\<stamp>`, itself brought into existence via
  `New-TPMOwnedDirectoryChainV1` before this call) as its own root
  (Root==Target: once established by the caller, it is already validated).

No caller in this codebase was found that lacked a clear, already-justified
trust-root authority to supply -- every call site's root is traceable to
either `HarnessRoot` (this tool's own top-level output boundary) or the
caller's own already-resolved repository checkout path. Test callers
(`Tests/*.ps1`) anchor their roots in their own `$TestDrive` (Pester's
per-test isolated temp directory) or another `New-Item`-created directory
under it -- never a shared or real filesystem location.

## Absent-tree snapshot diffing (Get-TreeHash / Compare-TreeSnapshot, issue #172)

`scripts/Invoke-TPM-RealInstanceSmoke.ps1`'s `UserProfiles`/`GameProfiles`/
`Pcsx2x6Crosshairs` Smoke File Safety facts are all produced by the same two
functions, called before and after the certification suite runs, feeding the
same `Compare-TreeSnapshot`:

- `Get-TreeHash -Path <dir>` walks a directory recursively (`Get-ChildItem
-Recurse -File`), hashing every file, and returns one record per file:
  `RelativePath`, `Path`, `Hash`, `Length`. When `<dir>` does not exist, it
  returns a genuine zero-length array (`return ,@()`) -- never `$null`.
- `Compare-TreeSnapshot -Before <snapshot> -After <snapshot>` diffs two such
  arrays by `RelativePath`, producing `Added`/`Removed`/`Changed` counts plus
  `BeforeSkipped`/`AfterSkipped` counts for any genuinely malformed entry
  (a `$null` element, or an element with a blank `RelativePath`) found in
  either snapshot. It normalizes a `$null` `-Before`/`-After` argument to a
  real empty array itself, independent of what produced that argument --
  every layer in this path (producer, consumer, and every caller-side
  fallback) defends against the same class of bug on its own; see
  LESSONS_LEARNED.md's issue #172 entry for the three-layer defect this
  replaced and why no single layer's fix was considered sufficient.
- No per-tree special-casing exists anywhere in this path. `UserProfiles`,
  `GameProfiles`, and `Pcsx2x6Crosshairs` are three call sites sharing
  identical semantics through the same two functions -- a fix or regression
  in one is a fix or regression in all three.

### Certification execution boundary (ADR155 operator experience)

Certification enters a noninteractive boundary after target paths are resolved. `Run-TPM-Tests.ps1` preflights every required executable, module, configuration file, and writable report location without installing anything. Its direct Git reads pass command-scoped `safe.directory=<exact resolved repository>` together with `-C <exact repository>`. Repository paths resolved for Git or isolated-process working directories use the FileSystem `ProviderPath`, never the provider-qualified `.Path` form Git rejects for UNC NAS paths. Separately, the Pester child inherits one matching process-local `safe.directory` entry and suppresses global and system Git configuration. Neither path writes persistent Git configuration or uses a wildcard `safe.directory` value. It then launches the harness with closed standard input, `-NoProfile -NonInteractive`, separate timestamped stdout/stderr logs, bounded lifetime, and termination metadata. Pester runs only in `Invoke-TPM-PesterChild.ps1`; its parent accepts only the exact version-1 JSON result schema and rejects missing, malformed, unknown, or contradictory results as infrastructure aborts. The operator surface is an append-only numbered phase display; technical streams remain in `TechnicalLogs`. Certification never fetches or mutates Git state.

#### Redirected-cleanup refusal and real HarnessRoot bootstrap proof (ADR155-0309 follow-up round)

Two behavioral properties implied by the isolation design above, but not
previously exercised against real reparse points through the actual
production entry points, now have dedicated adversarial coverage:

- **Cleanup refusal.** `Remove-TPMOwnedScratchDirectoryV1`
  (`TPMCertification.ProductionFacts.psm1`) revalidates the full
  ParentRoot-to-Path chain through `Resolve-TPMContainedPathV1`
  (`TPMCertification.Authority.psm1`) before every recursive delete, and
  independently checks the target's own `ReparsePoint` attribute. This was
  already correct; `Tests/TPMCertification.ProductionFacts.Tests.ps1`'s
  "redirected-cleanup refusal via the real production path" `Describe` block
  now proves it with real NTFS junctions across the full matrix -- root
  junction, intermediate-component junction, leaf junction, a
  Root-vs-Root-Evil sibling-prefix attempt, a forged foreign directory, and
  cleanup invoked after an uncertain (crash/kill/timeout) child-process
  termination -- confirming byte-identical foreign content (SHA-256 hash and
  full directory listing, before and after) in every refusal case. No
  production change was needed; the coverage closes the gap between the
  design and its proof.
- **Real HarnessRoot bootstrap.** `Tests/TPMCertificationHarness.Tests.ps1`'s
  "Run-TPM-Tests.ps1 real HarnessRoot bootstrap" `Describe` block invokes the
  actual `scripts/Run-TPM-Tests.ps1` entry point as a real child process
  (via the same `Invoke-TPMIsolatedProcessV1` primitive production code
  uses) against a TestDrive-copied fixture repository, with the single
  downstream call to `Invoke-TPM-RealInstanceSmoke.ps1` replaced -- only
  inside that copied fixture, gated by an environment variable the
  production call site does not otherwise branch on -- by a stub that
  records the resolved paths/commit and exits immediately. This proves the
  real preflight-then-bootstrap path (not `New-TPMOwnedDirectoryChainV1` in
  isolation) creates exactly the intended `Reports\<stamp>\TechnicalLogs`
  hierarchy and nothing else, and fails closed -- before ever reaching the
  fixture stop-point, with a nonzero exit and no marker written -- when: the
  HarnessRoot parent is a junction, HarnessRoot itself is a junction, an
  intermediate component (`HarnessRoot\Reports`) is a junction, the parent is
  missing, a dot-segment traversal value is supplied (which canonicalizes
  correctly and never touches a decoy sibling), or a file already occupies
  the name a directory needs to be created at. A genuine downstream failure
  exit code propagates unchanged and is never observable as a `CERTIFIED`/
  `NOT CERTIFIED` verdict.
- **Diagnostic hardening completed.** The prior round's PSScriptAnalyzer/
  InjectionHunter tool-execution `Diagnostic` hardening (Stage/ExceptionType/
  sanitized Message on every `Executed=$false` path) left one bare,
  information-destroying `catch{}` (around `Stop-Job` in
  `Invoke-TPMBoundedScriptBlockV1`) and no schema validation for the
  `Diagnostic` shape itself. Both are closed: `Stop-Job` failures are now
  captured and reported via a sanitized `Write-Warning` without changing the
  timeout/termination-confirmed outcome, and a new
  `Assert-TPMDiagnosticRecordV1` (`TPMCertification.Authority.psm1`) is
  called from `New-TPMProductionFactRecordsV1` for both tools' results,
  failing closed on a missing, malformed, or wrong-typed `Diagnostic` rather
  than letting one silently reach the authoritative fact record. The
  27-finding/27-disposition/0-unresolved InjectionHunter baseline is
  unchanged (confirmed by direct invocation against the live production
  inventory under both engines, not merely by the unit tests' small
  synthetic fixtures).
- **Path-validation exception boundary (diagnostic-path-check round).**
  `Test-TPMProductionPSScriptAnalyzerV1`'s `SettingsPath` check and
  `Test-TPMProductionInjectionHunterV1`'s `DispositionRegistryPath` check
  both call `Test-Path` before either function's own try/catch begins.
  Confirmed by direct reproduction against the real `powershell.exe` 5.1
  engine: under `$ErrorActionPreference='Stop'` (which every real entry
  point -- `Run-TPM-Tests.ps1`, `Invoke-TPM-RealInstanceSmoke.ps1` -- sets),
  a path containing real control characters makes `Test-Path` throw
  `System.ArgumentException` instead of returning `$false`; unguarded, that
  exception escaped uncaught before any `Diagnostic` could be constructed.
  (pwsh's `Test-Path` never throws for this input, even under the same
  preference -- confirmed separately -- so this is a genuine Windows
  PowerShell 5.1-only failure mode, not a cross-engine one.) Both call
  sites now wrap the check in its own try/catch, adding two new distinct
  Stage tags reserved exclusively for a genuine path-check exception, never
  reused for an ordinary missing-file result:
  `PSSCRIPTANALYZER_SETTINGS_PATH_CHECK_FAILED` and
  `INJECTIONHUNTER_REGISTRY_PATH_CHECK_FAILED`. Neither `-Path` value is
  sanitized before the check itself -- only the `Diagnostic.Message` text
  is sanitized afterward -- so this never changes which path is actually
  inspected. `Find-TPMInjectionHunterModuleV1`, the other filesystem check
  in this call graph, is unaffected: it only ever scans internal
  `$env:PSModulePath` entries (never `SettingsPath`/`DispositionRegistryPath`)
  and its own `Get-ChildItem` call already used `-ErrorAction
SilentlyContinue`, which suppresses this class of error regardless of
  `$ErrorActionPreference`.

  **Follow-up correction: both `Test-Path` calls also need
  `-ErrorAction Stop`.** The try/catch alone only converts the exception
  when the CALLER's `$ErrorActionPreference` already happens to be `'Stop'`
  (true for every real entry point, but not the ambient default). Confirmed
  by direct reproduction that under this engine's default (non-`Stop`)
  preference, the same illegal-character condition instead writes a raw,
  unsanitized `Test-Path : Illegal characters in path` record straight to
  the error stream and merely falls through to the ordinary missing-path
  branch -- the function still behaves correctly from its own return
  value's perspective, but that raw record leaks regardless of what the
  caller's preference is. Adding `-ErrorAction Stop` directly to both
  `Test-Path` calls makes them terminate unconditionally, independent of
  ambient `$ErrorActionPreference`, so the adjacent try/catch always
  converts the condition into the structured, sanitized `Diagnostic` with
  nothing ever written to the error stream. Confirmed this makes the
  behavior fully deterministic per engine (not merely one of two tolerated
  outcomes): genuine Windows PowerShell 5.1 (`PSEdition 'Desktop'`) always
  throws for a real control-character path and always reaches the new
  `*_PATH_CHECK_FAILED` stage with zero error-stream output; pwsh
  (`PSEdition 'Core'`) never raises an error for this input at all, with or
  without `-ErrorAction Stop`, and always reaches the ordinary `*_MISSING`
  stage.

## Real-hardware certification blockers (issue #154, 2026-07-27 run)

A real-hardware certification run at commit `2405a59` aborted with two
independently confirmed blockers. Both are fixed narrowly; neither is a
feature addition.

### Unattended mode selection (`TeknoParrot-Manager.ps1` exit 1: "Mode must be

set before starting")

`-Unattended` had no CLI or config mechanism to choose which mode to run.
Every mode's own body already auto-answers its internal prompts under
`-Unattended` (the many `if ($Unattended) { ... }` blocks throughout the
script), but the INITIAL mode choice itself was only ever reachable through
the interactive menu (`Read-MainMenuChoiceResponsive`) or a same-session
preview "Apply for real now?" re-entry (`$pendingApplyMode`). Confirmed by
direct reproduction (not assumed) that a fresh `-Unattended` process always
reached the menu loop with no mode ever chosen and exited 1. Git history
confirms the "Mode must be set before starting" check has been unchanged
since the v0.51 BETA commit that introduced it -- this is a genuine,
long-standing gap in the `-Unattended` contract, not a regression from
recent work.

Fixed with a new, optional saved-config field, `UnattendedMode`, read only
when `-Unattended` is set (an interactive run always chooses its mode from
the menu regardless of this field) and validated against a single accepted
name, `HealthCheck` -- not the full set of mode-name strings the main-loop
`switch` statement otherwise accepts. This RC ships support for only the one
audited unattended path this harness's certification gate actually needs;
every other value (including every other real mode name, and never a raw
menu number) fails safely as unsupported, silently falling through to the
original "Mode must be set before starting" error. `HealthCheck` (Library
health check, read-only) is the value this harness's own "Unattended TPM
root binding" gate needs and now writes: proving config-driven root binding
and mode selection work end-to-end without writing, deleting, or modifying
anything in the real install. Since no mode previously exited cleanly under
`-Unattended` -- every mode ends with a blocking `Read-Host` and a `continue`
back to the menu, which would immediately re-hit the same "Mode must be set"
error on the next loop iteration -- `HealthCheck`'s own completion block now
exits 0 under `-Unattended` instead of looping back; no other mode's
completion path was touched, since this harness never selects any other
mode.

`New-TPMTemporaryUnattendedConfig` (`scripts/Invoke-TPM-RealInstanceSmoke.ps1`,
no-prior-config path) now writes the complete minimal config
TeknoParrot-Manager.ps1's `-Unattended` flow needs to pass config load AND
actually select and run a mode to completion: `TeknoParrotRoot`,
`GamesInstallFolder`, `UnattendedMode`. `Set-TPMConfigJsonRoot` (existing-
config path) now also sets `UnattendedMode=HealthCheck` via
`Add-Member -Force` -- confirmed by direct reproduction that assigning to a
PSCustomObject property that does not already exist throws
`SetValueInvocationException`, which a pre-existing config saved before
this field existed would otherwise hit -- while every other saved field is
left untouched, matching the existing `TeknoParrotRoot`-only override
contract.

Proven end-to-end with a real, unmodified child-process fixture
(`Tests/TeknoParrot-Manager.Tests.ps1`): the real script, copied into
TestDrive, invoked with `-Unattended` against a synthetic (non-real)
install directory containing only the placeholder files SECTION 2's
existence checks require (`TeknoParrotUi.exe`, `GameProfiles`), passes
configuration validation, runs the real `Invoke-LibraryHealthCheck`, and
exits 0 on its own -- confirming both the config field and the clean-exit
fix together, not merely that the process avoided the specific error text.

**RC scope note:** the `UnattendedMode` value is validated against a single
accepted name, `HealthCheck` -- not the full closed set of mode-name strings
the main-loop `switch` statement otherwise accepts. This RC ships support for
only the one audited unattended path this harness's certification gate
actually needs; a general config-driven selector across every mode is out of
scope for the feature freeze and is deliberately not implemented. Any other
saved value (including every other real mode name) is rejected the same as
an unrecognized string.

**Legacy-config strict-mode regression (found and fixed same round):** a
config saved before this field existed has no `UnattendedMode` property on
the object at all (not `$null` -- genuinely absent). Confirmed by direct
reproduction that `$cfg.UnattendedMode` on such an object throws
`PropertyNotFoundException` under `Set-StrictMode -Version Latest` (both
pwsh and Windows PowerShell 5.1) -- reproducible only when strict mode is
active in the same top-level script scope as the read (a separately invoked
script via the call operator `&` does not inherit the caller's strict-mode
setting; dot-sourcing does). All three direct `$cfg.UnattendedMode` reads
(the config-summary display line and the two mode-selection reads) now go
through `$cfg.PSObject.Properties['UnattendedMode']` existence guards
instead of bare dot-access, so a legacy config missing the field is read
exactly like any other absent optional field: no exception, config still
accepted, falls through to the pre-existing "no mode chosen" safe failure
under `-Unattended`. Covered by a dedicated real child-process regression
test in `Tests/TeknoParrot-Manager.Tests.ps1` that dot-sources the
unmodified script through a wrapper enabling `Set-StrictMode -Version
Latest`, against a config carrying every other field `Save-Config` has ever
written (some null) minus only `UnattendedMode` -- confirmed by direct A/B
testing to fail against the pre-guard code and pass against the fix.

### 225 Pester failures -- Pester 5.8.0 regression, not a production defect

Preserved certification evidence recorded `Pester-summary.json`: 1010
passed, 225 failed, 0 skipped, 1235 total, and the run's own `Engine` field
(`Pester-result-v1.json`) as `Pester 5.8.0 / pwsh 7.6.3`. Reproduced exactly
(same 1010/225/1235 split, overlapping failure signatures) in an isolated
checkout by installing Pester 5.8.0 side-by-side with the previously
validated 5.7.1 (both from the real PowerShell Gallery, confirmed real,
published 2026-06-30) and letting `Invoke-TPM-PesterChild.ps1`'s
then-open-ended `Import-Module Pester -MinimumVersion 5.0` auto-select the
newer one.

Definitive A/B proof: the exact same full `.\Tests` suite (1235 tests)
scores 1234 passed / 1 failed under Pester 5.7.1 (the one remaining failure
a pre-existing, already-documented nondeterministic screenshot/display-
handle-timing test, unrelated to Pester version) versus 1010 passed / 225
failed under Pester 5.8.0, with nothing else in the environment changed.
Running any single affected file in isolation (e.g.
`TeknoParrot-Manager.Tests.ps1`, 371/371 either version) shows no
difference at all -- the regression only manifests running the full
29-container suite together, consistent with the dominant failure
signatures (103 of 225 failures carry no exception message at all --
Pester's own fallback text for a test whose container `BeforeAll` failed;
most of the rest are `$script:`-scoped setup variables, e.g.
`$script:RawThrillsPathLimits`/`$script:tpmEvidenceWorkflowId`, "cannot be
retrieved because it has not been set" -- both classes are consistent with
a cross-file/BeforeAll script-scope handling change between 5.7.1 and 5.8.0
during a multi-file run, not with any single test's own logic).

Fixed by pinning `Invoke-TPM-PesterChild.ps1` to
`Import-Module Pester -RequiredVersion 5.7.1` (a hard pin, not a floor) and
aligning `Run-TPM-Tests.ps1`'s own preflight check to look for that exact
version rather than "any Pester >= 5" -- the preflight previously could
report success with only 5.8.0 present, then have the child fail to import
it, turning a clear preflight signal into a confusing downstream failure.
This is deliberately pinning to the version this suite is ALREADY proven
against, to prevent a future auto-installed Pester release from silently
changing certification behavior again without a human deciding to
re-validate and bump the pin -- not adopting a new version.

An unrelated stray `Pester 3.4.0` install
(`C:\Program Files\WindowsPowerShell\Modules\Pester\3.4.0`) was found on
the development machine during this investigation; it was ruled out early
(`-MinimumVersion 5.0`/`-RequiredVersion 5.7.1` both refuse it outright) and
was not touched -- noted here as a housekeeping item for a separate round,
not part of this fix.

### `PSScriptAnalyzer.json` zero-byte evidence file -- confirmed correct, not

a defect

The preserved evidence includes a genuine zero-byte `PSScriptAnalyzer.json`.
Confirmed by direct reproduction: `scripts/Invoke-TPM-RealInstanceSmoke.ps1`
writes this file via `$analyzer | ConvertTo-Json -Depth 6 | Out-File ...`;
piping a genuinely empty array (`@()`, i.e. zero PSScriptAnalyzer findings)
through `ConvertTo-Json` produces zero pipeline output objects (a
well-documented PowerShell pipeline behavior -- `@() | ConvertTo-Json`
differs from `ConvertTo-Json -InputObject @()`, which would produce the
literal text `"[]"`), so `Out-File` writes nothing at all. A zero-byte file
is therefore the correct, expected representation of zero findings here,
matching the run's own `OperatorStatus.txt` ("zero Error/Warning
findings"). No code change made.

---

## Product evolution roadmap

The canonical product evolution roadmap is maintained in [ROADMAP.md](ROADMAP.md).
ARCHITECTURE.md remains the implementation reference for current and completed
features. ROADMAP.md is planning-only and does not authorize RC7 scope changes,
product-code, test, issue, release-package, or updater work.
