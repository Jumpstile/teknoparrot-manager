# Auto-Update System

Status: pre-1.0 implementation branch

TeknoParrot Manager uses a **manual, backup-first auto-update model**.

The updater must never silently replace files. It checks GitHub Releases, explains what it found, creates a local backup, downloads the selected release asset, validates the downloaded file, and only then replaces the local script.

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

4. **Atomic-ish local replacement**
   - The new file is downloaded to a temporary path first.
   - The downloaded file must exist and have non-zero length.
   - The current script is copied to backup before replacement.
   - Replacement uses `Move-Item -Force` only after the backup and download both succeed.

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

Before 1.0, wire this helper into the main menu as:

```text
Check for TeknoParrot Manager update
```

Expected flow:

1. Show local version.
2. Query latest GitHub Release.
3. If no newer version exists, report that the user is current.
4. If a newer version exists, show release tag/name and asset selected.
5. Ask for explicit confirmation.
6. Backup current script.
7. Download replacement.
8. Replace script.
9. Tell the user to restart TeknoParrot Manager.

## Non-goals for 1.0

- No silent updating.
- No updater service.
- No scheduled task.
- No unsigned third-party update source.
- No complex package manager.
- No automatic execution of downloaded code in the same session.
