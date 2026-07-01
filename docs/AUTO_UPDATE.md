# Auto-Update System

Status: standalone helper merged; menu integration (v0.99.39) pending independent review before merge

TeknoParrot Manager uses a **manual, backup-first auto-update model**.

The updater must never silently replace files. It checks GitHub Releases, explains what it found, creates a local backup, downloads the selected release asset, validates the downloaded file, and only then replaces the local script.

## Current review status

An independent engineering review found real blockers on the first pass. All four have been fixed and retested against the live `Jumpstile/teknoparrot-manager` releases (both under Windows PowerShell 5.1). Do not merge or wire this into the menu until a re-review confirms the fixes.

1. **Release packaging mismatch -- fixed**
   - `-AssetNamePattern` now defaults to `^TeknoParrot\.Manager\.v.*\.zip$`, matching real release assets like `TeknoParrot.Manager.v0.99.38.BETA.zip`.
   - Verified live: `-CheckOnly` now correctly finds and selects the real release asset instead of throwing.

2. **Content validation before replacement -- fixed**
   - The updater extracts only the `TeknoParrot-Manager.ps1` entry from the downloaded zip (via `Expand-TpmReleaseZipEntry`), never the whole archive.
   - Before replacing the live script, `Test-TpmExtractedScript` verifies: the file exists, is non-empty, does not begin with a zip signature (`PK`), contains the `TeknoParrot Manager` marker, and contains a `$ScriptVersion = "..."` assignment.
   - Verified live: a full `-Apply` against the real `v0.99.38` release downloads, extracts, validates, and installs the genuine script (confirmed by reading back `$ScriptVersion` after replacement).

3. **PowerShell 5.1 TLS hardening -- fixed**
   - `Enable-TpmTls12` forces `Tls12` into `[Net.ServicePointManager]::SecurityProtocol` before any GitHub API/download call, guarded to skip on PowerShell 6+ where it is unnecessary.

4. **Testability -- fixed**
   - All logic besides argument parsing and top-level orchestration now lives in `tools/TpmAutoUpdate.Core.psm1`, a side-effect-free module. `tools/Invoke-TpmAutoUpdate.ps1` is a thin orchestrator that imports it.
   - `Tests/TpmAutoUpdate.Core.Tests.ps1` covers version parsing, asset selection, URL validation (URI-parsed, not `-like`), backup creation, zip extraction, content-validation failure modes, and an `-Apply -WhatIf` case asserting zero backup/download/replacement occurs.

## Destructive-path validation (`Tests/TpmAutoUpdate.DestructivePath.Tests.ps1`)

Ten tests, all passing, deliberately induce failure conditions and verify the original installation survives, no raw zip bytes ever land in the `.ps1` target, backups are preserved, temp files do not leak, and errors are actionable:

1. Corrupt zip download -- rejected, original and backup intact.
2. Zip missing `TeknoParrot-Manager.ps1` -- rejected with a specific "does not contain expected entry" error.
3. Content-validation failures -- both a missing `$ScriptVersion` and an extracted file that is itself raw zip bytes are rejected before replacement.
4. Truncated/partial download -- treated as corrupt, rejected.
5. Read-only destination -- **documented finding, not a defect**: `Move-Item -Force` clears the `ReadOnly` attribute and replaces the file rather than failing closed. Verified in isolation, not just in this test. Marking the script read-only is not a safety mechanism against this updater; if that protection is wanted, `Install-DownloadedUpdate` would need an explicit `ReadOnly` check before `-Force`.
6. Backup creation failure -- aborts before any download; original untouched.
7. Extraction failure (valid zip, corrupted entry payload) -- rejected, original and backup intact.
8. Replacement failure after a successful backup (destination locked by another handle) -- `Move-Item` fails, original file is provably unchanged (not partially written), backup and temp cleanup both hold.
9. Module-scope error-action regression guard -- a real bug found while writing this suite: a module's `$ErrorActionPreference` is snapshotted from the caller at *import* time, and the orchestrator intentionally imports without `-Force` (to stay mockable). An already-loaded module instance would silently keep whatever preference was active at its original import, meaning a non-terminating cmdlet error inside the module could be silently swallowed. Fixed by setting `$ErrorActionPreference = 'Stop'` explicitly at the top of `TpmAutoUpdate.Core.psm1` itself, independent of import history.

## Safety rules

1. **Manual by default**
   - Checking for updates is safe and read-only.
   - Applying an update requires an explicit user action.
   - No background updater, scheduled task, startup updater, or silent self-replacement.

2. **Backup before replacement**
   - The current script is copied to `UpdateBackups/<timestamp>/` before replacement.
   - If backup creation fails, the update is aborted.

3. **GitHub Releases only**
   - Releases are fetched from `Jumpstile/teknoparrot-manager`.
   - Update assets must come from GitHub release asset URLs.
   - Arbitrary URLs are never accepted.

4. **Validated local replacement**
   - The asset is downloaded to a temporary path first.
   - The downloaded file must exist and have non-zero length.
   - If the asset is a zip, the updater must extract and validate `TeknoParrot-Manager.ps1` before replacement.
   - The current script is copied to backup before replacement.
   - Replacement happens only after the backup, download, extraction, and content validation all succeed.

5. **Version-aware**
   - Local version is read from the script's `$ScriptVersion` value.
   - Latest version is read from the GitHub release tag.
   - Tags are normalized by trimming a leading `v`.

6. **Recoverable**
   - The backup path is printed after update.
   - A failed update leaves the current script in place whenever possible.
   - Restore remains manual and transparent.

## Current implementation

The first implementation is a standalone helper:

```powershell
.\tools\Invoke-TpmAutoUpdate.ps1 -CheckOnly
.\tools\Invoke-TpmAutoUpdate.ps1 -Apply
```

This keeps the first cut reviewable before wiring it into the main menu.

## Menu integration (v0.99.39)

TeknoParrot-Manager.ps1 now has a "Check for Updates" main menu option (12) that follows the flow originally planned here. The interactive checker is implemented as plain functions inside TeknoParrot-Manager.ps1 itself (`Get-ManagerUpdateRelease`, `Assert-ManagerUpdateTargetWritable`, `New-ManagerUpdateBackup`, `Expand-ManagerUpdateAsset`, `Test-ManagerUpdateExtractedScript`, `Invoke-CheckForUpdates`) rather than by importing `tools/TpmAutoUpdate.Core.psm1` -- this script has no external module dependencies anywhere else, and introducing one just for this would be inconsistent with its single-file, self-contained architecture. The logic (asset pattern, content validation, read-only pre-check) is deliberately kept in lockstep with the standalone module; `tools/Invoke-TpmAutoUpdate.ps1` remains available separately for scripted/manual use outside the interactive menu.

Actual flow:

1. Show local version.
2. Query latest GitHub Release.
3. If no newer version exists, report that the user is current and return to the menu.
4. If a newer version exists, show release tag/name and asset selected.
5. Explain exactly what updating will do (backup, download, validate, replace, restart) and ask for explicit Y/N confirmation.
6. If read-only, refuse before any backup/download work with an actionable error.
7. Backup current script.
8. Download replacement.
9. Validate replacement content.
10. Replace script.
11. Tell the user to restart TeknoParrot Manager, then exit this session -- it never continues running the replaced script in the current process.

Any failure at any step displays the exact error, states whether a backup was created, and returns safely to the main menu without exiting.

## Startup update check (v0.99.39)

In addition to the menu option, `TeknoParrot-Manager.ps1` also offers a quiet, opt-out check at launch, controlled by `CheckForUpdatesOnStartup` in `TeknoParrot-Manager.config.json` (default `true`). Implemented as `Invoke-StartupUpdateCheck`, sharing `Get-ManagerUpdateRelease`, `ConvertTo-ManagerComparableVersion`, and the same install path (`Invoke-ManagerUpdateInstall`, extracted from `Invoke-CheckForUpdates` so both callers use it without duplicating the backup/download/extract/validate/replace logic or its confirmation prompts).

Flow:

1. Runs once, right after config is loaded, before any TeknoParrot-root prompts. Never runs in `-Unattended` mode -- there is no way to show an interactive prompt there, and Unattended is meant to be fast and non-interactive.
2. Queries the latest release with a single short-timeout attempt (`-MaxAttempts 1 -TimeoutSec 5`, vs. the menu option's patient 3x/20s retry) so an unreachable GitHub cannot meaningfully delay startup. A failed or timed-out check is logged and the script continues straight to the menu -- no error is shown to the user for what is, from their perspective, an unrequested background check.
3. If already current: nothing is shown, continues directly to the menu (optionally logged).
4. If a newer version exists: shows current/latest version, the release name if present, and a one-line summary (`Get-ManagerUpdateReleaseSummary` -- the first non-blank line of the release body, markdown heading/bullet markers stripped, clamped to 150 characters), then prompts:
   - **Y** -- shows the same "what updating will do" explanation as the menu option, asks for a second explicit confirmation, then calls `Invoke-ManagerUpdateInstall`. A successful install still requires the caller (top-level script code, not the function) to exit -- same reasoning as the menu option: the function itself never calls `exit`, both for testability and so the "declined at the second confirmation" path can return normally.
   - **N** (or anything else) -- continues straight to the menu; logged as "remind me later."
   - **V** -- prints the full release body, then re-prompts (Y/N/V again) rather than exiting the loop.
5. A read-only target is refused the same way as the menu option -- before any backup/download work, with the same actionable error.

## Non-goals for 1.0

- No silent updating.
- No updater service.
- No scheduled task.
- No unsigned third-party update source.
- No complex package manager.
- No automatic execution of downloaded code in the same session.
