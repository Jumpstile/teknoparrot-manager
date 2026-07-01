# Auto-Update System

Status: blocked pending review fixes

TeknoParrot Manager uses a **manual, backup-first auto-update model**.

The updater must never silently replace files. It checks GitHub Releases, explains what it found, creates a local backup, downloads the selected release asset, validates the downloaded file, and only then replaces the local script.

## Current review status

Independent Claude and Codex reviews found real blockers. Do not merge this branch or wire the updater into the menu until these are fixed and retested.

Required fixes:

1. **Release packaging mismatch**
   - Current real releases use assets such as `TeknoParrot.Manager.v0.99.38.BETA.zip`.
   - The first helper expected a bare `TeknoParrot-Manager.ps1` asset.
   - The helper must either require a real `.ps1` release asset or become zip-aware.

2. **Content validation before replacement**
   - The updater must never move raw zip bytes over `TeknoParrot-Manager.ps1`.
   - If using zip assets, it must extract `TeknoParrot-Manager.ps1`, validate that it is a script, validate that it contains the expected `$ScriptVersion` assignment, and only then replace the target.

3. **PowerShell 5.1 TLS hardening**
   - Add TLS 1.2 before GitHub API/download calls, matching the main script's compatibility pattern.

4. **Testability**
   - Pure helper logic should be split into a no-side-effect module before adding Pester tests, or the entry script must provide a safe way to load functions without making network calls.

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
