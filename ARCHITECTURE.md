# TeknoParrot Manager -- Architecture Reference

Implementation details, design decisions, and key invariants for the major
features. This is the authoritative reference for how things are built and why
particular design choices were made. For what went wrong and the lessons drawn,
see LESSONS_LEARNED.md.

---

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

## ReShade deployment (Mode 5)

**Source DLLs.** Not bundled in the release ZIP (not redistributable). The user
obtains from reshade.me and places at `Scripts\ReShade\ReShade64.dll` (x64) and
optionally `ReShade32.dll` (x86). If absent at startup the script prompts at
runtime. Run the ReShade installer on any game exe to extract the DLL, then copy
and rename it here for distribution.

**Authenticode check.** `Test-ReShadeDllSignature` (next to `Get-ReShadeLatestVersion`)
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

---

## dgVoodoo2 deployment (Mode 6)

**Source DLLs.** Bundled at `Scripts\dgVoodoo2\` (not in repo; user provides). Required
DLLs from the dgVoodoo2 ZIP: `MS\x86\D3D8.dll`, `DDraw.dll`, `D3DImm.dll`;
`3Dfx\x86\Glide2x.dll`, `Glide3x.dll`; root `dgVoodoo.conf` (optional config).

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
has its own summary line and log field.

### Eggman dat source

Migrated from `Eggmansworld/Datfiles` (archived, fixed "teknoparrot" tag) to
`Eggmansworld/TeknoParrot` (date-based tags per release). `Get-EggmanDatRelease` queries
`.../releases/latest` instead of a fixed tag.

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

---

## Dry-run / preview mode (-DryRun, v0.92)

Scoped to modes 1 (AutoSync) and 2 (Register only). The other modes already have
per-feature Y/N confirmation before writing.

**Single write gate.** `Save-XmlMaybe $doc $path $DryRun` either saves for real or logs
"would save." Every dry-run-aware write goes through this wrapper -- one place that could
accidentally still write during a preview, covered by tests. `Invoke-AutoSync`,
`Register-Games`, `Repair-GamePaths`, and `Invoke-ControlPropagation` all take a
`[bool]$DryRun` parameter.

**Interactive flow.** The "Run in PREVIEW mode first?" prompt is asked once per
AutoSync/Register run, skipped when `-Unattended` or when `-DryRun` was already passed
on the command line. Both paths converge on one runtime variable (`$dryRunActive`) passed
into every downstream call -- never branch on the raw switch and the prompt result
separately.

**Preview skips.** The `FullBackup` step, LaunchBox/HyperSpin 2 export offers, thumbnail
download offer, and GPU fix offer are all skipped in preview mode. They are themselves
writes/downloads that do not make sense after a run that changed nothing. ACTION REQUIRED
and the controls-status file still print/write normally (reports, not mutations).

**Apply immediately.** After a preview pass, an "Apply these changes for real now?" prompt
lets the user commit without re-running the script. Implemented via `$pendingApplyMode`
(the mode to silently re-enter) and `$forceRealApply` (consumed once to skip the preview
question). Deliberately reuses the existing `while ($true)` menu loop with `continue`/
`break` rather than a nested loop -- the loop body already has many unlabeled `continue`
statements that abort to the menu on error; wrapping it in a new loop would silently
redirect those into a retry instead.

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

**Health check scope.** The Library health check's GPU/FFB coverage report is read-only.
It never calls `Invoke-GpuFixSetup`/`Invoke-FFBBlasterSetup` (which prompt, back up, and
write), only the shared detection helpers. Third-party FFB plugin coverage is NOT included
-- checking it needs a live fetch of `AutoSetup.cmd` (`Get-FFBPluginGameMap`), which
would break the health check's documented "no network access" contract. The check prints a
one-line note pointing at mode 8 instead.

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

**`Write-DownloadAudit`** (next to `Test-PathInside`) logs source URL, filename, version
(if known), and SHA256 for every binary the script downloads: the Eggman dat ZIP, the
BepInEx release ZIP, and the two FFBArcadePlugin DLLs. Deliberately NOT a pass/fail gate
-- none of these sources publish checksums, and the FFBArcadePlugin/BepInEx binaries are
unsigned community builds with no trust anchor to enforce. The log exists so a user who
wants to verify what was fetched has a record without reproducing the download.

**ReShade Authenticode.** The one download-adjacent case where an actual trust anchor
exists: the ReShade DLL is not downloaded by the script (user provides it), but the
installer IS code-signed, and Authenticode signatures are embedded in the PE itself and
survive extracting/renaming the DLL. `Test-ReShadeDllSignature` checks this once per DLL
at `Invoke-ReShadeSetup` start. Informational, not a gate (see ReShade section).

**PostgreSQL MSI.** Not Authenticode-signed (confirmed empirically via
`Get-AuthenticodeSignature`, `Status: NotSigned`). Audit-logging-only is already the
practical ceiling here. Re-check only if EnterpriseDB/the guide repo ships a newer, signed
installer.

**Scope rationale.** GitHub Releases assets have no published hashes, and most binaries
are unsigned. A hard verification gate would have nothing legitimate to check against for
3 of the 4 sources. Authenticode enforcement was only added for ReShade specifically,
since it is the one source that is actually signed.

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

**MSI log security.** Deferred custom actions log connection passwords in plaintext in the
verbose install log even though the command-line echo masks them. `Install-Postgres83`
always deletes its entire working folder (ZIP, extracted MSI, verbose log) in a `finally`
block, success or failure.

**Credential storage.**
- Postgres superuser password: DPAPI-encrypted (`ConvertFrom-SecureString` with no `-Key`,
  tied to the current Windows user + machine) in `config.json` as
  `PostgresSuperPasswordEncrypted`.
- Windows service account password: never persisted at all -- only needed once, at install time.
- Postgres `Pass` field in UserProfiles: stored in plaintext. This is TeknoParrotUI's own
  `ConfigValues/FieldInformation` schema -- TeknoParrotUI reads that literal field directly
  to connect at game-launch time. Encrypting it would break TPUI's own connection; there
  is no token-indirection mechanism TPUI would understand. Accepted, documented risk.

**pgpass credential files.** `New-PostgresPgPassFile`/`Remove-PostgresPgPassFile` (next to
`Test-SafePostgresDbName`) write/delete a temporary `.pgpass`-format file instead of using
`$env:PGPASSWORD` (which exposes the password in the child process's environment block for
the duration of the call). All five `psql`/`pg_dump`/`pg_restore`/`createdb`/`dropdb`
call sites use this pattern. The file uses `*` for the database field
(`127.0.0.1:5432:*:postgres:<password>`), covering every call site since they all use the
same fixed host/port/user. The colon-escaping in the file is `-replace ':', '\:'` and the
backslash-escaping is `-replace '\\', '\\'` -- the single-quoted replacement string is a
literal two-character string (not regex), so this correctly doubles backslashes rather than
quadrupling them.

**Scope split.** If a profile's `Automatically create Database` field is present and `1`
(TPUI's "Express Database Install", GT2018+), this script only fills in connection fields
and leaves database creation/restore to TPUI's first-launch flow. Only for older
`GameProfileRevision`s missing that field does this script run `createdb`/`pg_restore`.

**Critical invariants.**
- A database that already exists is NEVER recreated or restored over. Every
  database-touching function is gated on `Test-PostgresDatabaseExists` first.
- A `Pass` field that is already non-empty is never overwritten.
- `Test-PostgresPassword` (a trivial `SELECT 1`) is called immediately after obtaining a
  password -- whether decrypted from saved config or freshly typed -- and BEFORE saving a
  freshly-typed one to config.

**Known accepted risks.**
- `SERVICEPASSWORD`/`SUPERPASSWORD` passed to `msiexec` as command-line properties are
  briefly visible to process inspection tools (Task Manager, Process Explorer, WMI) for
  the duration of that one call. There is no `msiexec` mechanism that avoids this for a
  silent property-driven install.
- The Postgres `Pass` field in UserProfiles is in plaintext (see Credential storage above).
- The PostgreSQL installer is not Authenticode-signed (audit logging only -- same as
  BepInEx/FFBArcadePlugin).

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

**Fuzzy-match alias.** The shared-executable fuzzy-match loop in `Register-Games` (~line
4640) also tries each candidate's `$RawThrillsPathLimits[$cand.Code].Suggested` value as a
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
- **Application** (13-14): Check for Updates, Exit.

**Old -> new mapping** (for anyone cross-referencing an older screenshot, forum post, or
saved `-Unattended` invocation): 1->1, 2->2, 3 Crosshair->4, 4 ReShade->5, 5 dgVoodoo2->6,
6 GPU fix->7, 7 FFB->8, 8 BepInEx->9, 9 Restore backup->11, 10 Health check->10 (unchanged),
11 Postgres->12, 12 Check for Updates->13, 13 Propagate Controls->3, 14 Exit->14.

**Drift prevention.** `Tests/TeknoParrot-Manager.Tests.ps1`'s "Main menu source-level
drift check" reads the raw script source (the menu loop is top-level code, not a function,
so it isn't reachable through the AST function-extraction the rest of the suite uses) and
cross-checks the displayed option numbers against the `switch` statement's case labels,
asserting a contiguous 1..N sequence with no gaps and no mismatch. This is the same drift
class documented in `LESSONS_LEARNED.md` for v0.99.25/v0.99.28 (stale mode-number
references surviving a menu change); the new test makes it a CI failure instead of a
manually-run grep sweep's responsibility to catch.

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
