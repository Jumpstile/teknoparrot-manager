# Auto-Update System

Status: review blockers fixed, pending re-review before merge

TeknoParrot Manager uses a **manual, backup-first auto-update model**.

The updater must never silently replace files. It checks GitHub Releases, explains what it found, creates a local backup, downloads the selected release asset, validates the downloaded file, and only then replaces the local script.

## Current review status

Independent Claude and Codex reviews found real blockers on the first pass. All four have been fixed and retested against the live `Jumpstile/teknoparrot-manager` releases (both under Windows PowerShell 5.1). Do not merge or wire this into the menu until a re-review confirms the fixes.

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

## Pre-1.0 integration target

Before 1.0, wire this helper into the main menu only after Claude/Codex re-review confirms the blockers are resolved.

Expected flow:

1. Show local version.
2. Query latest GitHub Release.
3. If no newer version exists, report that the user is current.
4. If a newer version exists, show release tag/name and asset selected.
5. Ask for explicit confirmation.
6. Backup current script.
7. Download replacement.
8. Validate replacement content.
9. Replace script.
10. Tell the user to restart TeknoParrot Manager.

## Non-goals for 1.0

- No silent updating.
- No updater service.
- No scheduled task.
- No unsigned third-party update source.
- No complex package manager.
- No automatic execution of downloaded code in the same session.
