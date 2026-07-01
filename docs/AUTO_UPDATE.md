# Auto-Update System

Status: review blockers fixed, pending re-review before merge

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
5. Read-only destination -- **fixed**: `Assert-TpmWritableTarget` checks the target explicitly, before any backup/download work begins. `Move-Item -Force` was found (empirically, in isolation) to silently clear the `ReadOnly` attribute and replace the file anyway rather than failing closed, so the updater never relies on it -- a read-only target is refused with an actionable error naming the file and the command to unlock it.
6. Backup creation failure -- aborts before any download; original untouched.
7. Extraction failure (valid zip, corrupted entry payload) -- rejected, original and backup intact.
8. Replacement failure after a successful backup (destination locked by another handle) -- `Move-Item` fails, original file is provably unchanged (not partially written), backup and temp cleanup both hold.
9. Missing checksum -- an asset with no GitHub-provided digest is refused before extraction.
10. Corrupted checksum (malformed digest format) -- refused before extraction.
11. Checksum unavailable because the release query itself failed -- aborts cleanly before any backup/download (see "Checksum verification" below for why this collapses into the existing release-query-failure path rather than being a distinct "checksum download failed" case).
12. Module-scope error-action regression guard -- a real bug found while writing this suite: a module's `$ErrorActionPreference` is snapshotted from the caller at *import* time, and the orchestrator intentionally imports without `-Force` (to stay mockable). An already-loaded module instance would silently keep whatever preference was active at its original import, meaning a non-terminating cmdlet error inside the module could be silently swallowed. Fixed by setting `$ErrorActionPreference = 'Stop'` explicitly at the top of `TpmAutoUpdate.Core.psm1` itself, independent of import history.

Also covered directly in the destructive-path suite: incorrect checksum (a truncated/partial download naturally produces a hash that does not match the complete file's published digest -- caught before any zip parsing is attempted) and a checksum-valid-but-still-corrupt file (a checksum can only confirm the download matches what was published, not that the publisher uploaded something well-formed -- content validation remains a separate, necessary layer).

## Checksum verification (SHA-256)

Adds an independent integrity-verification layer between download and extraction, on top of (not replacing) the existing GitHub-release-URL validation, content validation, backup-first replacement, and fail-closed behavior.

**Design: GitHub's native asset digest, not a sidecar file.** GitHub computes and serves a SHA-256 digest for every release asset server-side, at upload time -- the Releases API already returns `assets[].digest` in the format `sha256:<64 lowercase hex chars>` (confirmed against the real `Jumpstile/teknoparrot-manager` release assets). This is used instead of publishing a separate `.sha256` or `checksums.txt` release asset, for several concrete reasons:

- **No extra download, no extra release-process step.** The digest travels in the exact same API response `Select-TpmUpdateAsset` already parses for the asset name and download URL -- nothing new to upload, and nothing to forget uploading.
- **Fewer failure modes.** A sidecar checksum file introduces its own "checksum download failed" case; with the digest bundled into the release-metadata response, that case collapses into the release query itself failing (`Get-LatestRelease`), which was already handled.
- **Cannot go stale independently.** A sidecar file and the asset it describes are two separate uploads that could theoretically drift (wrong file attached, forgotten update); a server-computed digest of the actual stored bytes cannot.

**Known limitation, stated plainly:** this defends against transport corruption, partial downloads, and disk/CDN corruption between GitHub's storage and the local machine -- it verifies the downloaded bytes are exactly what GitHub has stored for that asset. It does **not** defend against a compromised repository or publishing account, since an attacker with upload access could replace both the asset and, implicitly, the digest GitHub computes for it. That same limitation already applies to the GitHub-release-URL check; the checksum is an additional independent layer, not a replacement for keeping the repository and release process itself trustworthy.

**Implementation:** `Get-TpmTrustedAssetDigest` extracts and validates the digest format from the asset object (missing or malformed -- wrong algorithm prefix, wrong length, non-hex characters -- both refuse to install, since a missing/malformed digest means this whole verification layer would otherwise be silently skipped). `Assert-TpmDownloadIntegrity` computes the downloaded file's actual SHA-256 (`Get-FileHash`) and compares. Both run between `Save-TpmReleaseAsset` (download) and `Expand-TpmReleaseZipEntry` (extract) in `Invoke-TpmAutoUpdate.ps1` -- a mismatch or missing/malformed digest aborts before any extraction or replacement is attempted, leaving the existing installation and any backup already created untouched.

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

Before 1.0, wire this helper into the main menu only after independent verification confirms the blockers are resolved.

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
