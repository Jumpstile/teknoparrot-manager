# Auto-Update System

Status: the standalone helper and the Check for Updates menu item (16) are part of v1.0 RC8.1, v1.0 RC8.2, v1.0 RC8.3, v1.0 RC8.4, v1.0 RC9, v1.0 RC9.1, v1.0 RC9.2 and v1.0 RC9.3. RC9.3 is the latest published release: https://github.com/Jumpstile/teknoparrot-manager/releases/tag/v1.0-RC9.3. The previous published release is v1.0 RC9.2: https://github.com/Jumpstile/teknoparrot-manager/releases/tag/v1.0-RC9.2. The older published releases are v1.0 RC9.1, RC9, RC8.4, RC8.3, RC8.2, RC8.1 and RC7. RC8 was a tester build and was never published. Final Version 1.0 has not been published yet. All releases: https://github.com/Jumpstile/teknoparrot-manager/releases

RC8.1 is the first build that can update itself in place with Check for Updates, including a release with many files. If you run RC8.1 or newer, Check for Updates offers the newer release when there is one. Builds before RC8.1 (for example RC8 or RC7) cannot update themselves. If you run one of those, install the newest release by hand once: download its ZIP from the Releases page and extract it over your old folder. After that, Check for Updates does the work.

The v0.99.38 and v1.0-RC3 live-verification references below are historical.
They are not current download instructions.

The asset-name pattern is version-agnostic.

**In plain words:**

TeknoParrot Manager uses a **manual, backup-first auto-update model**.

The updater must never silently replace files. When you ask it to update, it does these things in order:

1. It finds the latest release on GitHub and explains what it found.
2. It downloads the release ZIP and checks its SHA-256 (a fingerprint check) against the one GitHub published.
3. It looks inside the ZIP before changing anything.
4. It checks there is enough free space (twice the unpacked size).
5. It saves a backup of every file it replaces, in `UpdateBackups`.
6. It installs the files and checks each one. If anything goes wrong, it puts every file back.
7. You start TeknoParrot Manager again yourself.

It never deletes your own files, `UserProfiles`, your backups or older files the release no longer has.

## Release version identity

TeknoParrot Manager compares the complete version name, not just the numbers.

A release candidate (RC) always comes before the final release.

So `1.0-RC7 < 1.0-RC9 < 1.0`.

The same rule is used by the menu check, the startup check, and the standalone updater.

### More detail

**How versions are compared:**

- Comparison uses the complete local script identity (`$ScriptVersion` plus the optional `$ReleaseCandidateLabel`) and the release tag.
- Numeric version components compare numerically.
- For the same base, RC numbers compare numerically and every RC precedes the final release.
- The same ordering drives menu and startup checks, the standalone updater, downloaded-script/tag validation, and installed-version readback.
- Numeric-base parsing alone is not version ordering.

**How the script identity is read:**

- Candidate and installed-script identity checks use the PowerShell AST parser.
- They do not execute a downloaded script to read its version.
- The accepted identity consists of exactly one bare, unwrapped, unscoped root `$ScriptVersion =` assignment with a direct constant-string RHS, plus at most one equivalent `$ReleaseCandidateLabel` assignment.

**Which writes the parsers look for:**

- The parsers scan known static write forms: assignments and destructuring targets, attributed/cast and transparent parenthesized targets, member/index lvalue roots, increment/decrement, `foreach` variables, root script parameters, and named data-statement variables.
- Any additional protected write or unsupported declaration shape fails closed.
- Function-local parameters do not bind the root script identity.

**Limits of this check:**

- This finite AST check is not a general sandbox or full data-flow analysis.
- Indirect mutation is outside its guarantee. That means commands such as `Set-Variable`, variable-provider writes, `-OutVariable`, `[ref]`, .NET/session-state APIs, aliases/splatting, dynamic names, imports/dot-sourcing, or invoked scriptblocks.
- Comments and string data cannot spoof AST declarations.

## Download checks and audit records

Every update download is checked before it is used.

If the check fails, the update stops and your current installation is not changed.

A rejected download is removed.

If verification is unavailable, download the complete ZIP manually from https://github.com/Jumpstile/teknoparrot-manager/releases.

This check detects corruption or a mismatch against GitHub's stored asset. It does not protect against a compromised publishing account.

### More detail

**What the update check requires:**

- TeknoParrot Manager update packages require GitHub's release-asset `digest` metadata in the exact `sha256:<64 hex>` form.
- Both updater paths verify the downloaded bytes before opening the ZIP, changing target file protection, or creating a backup.
- Missing, malformed, or mismatched digests stop the update.

**What is recorded for other downloads:**

- All shared live-download audit entries record authoritative source, filename, version when known, computed SHA-256, and transfer metrics.
- ReShade additionally records installer Authenticode signer/status/thumbprint/trust; its SHA-256 is audit-only.
- BepInEx and dgVoodoo2 validate GitHub asset digests when available.
- Eggman dat, FFBPlugin, PostgreSQL packages, and thumbnails retain their existing source/hash audit fields.

## Current implementation status

An independent engineering review found real blockers on the first pass.

The packaging, validation, TLS, and testability blockers were fixed. They were retested against live `Jumpstile/teknoparrot-manager` releases under Windows PowerShell 5.1 before the menu integration was added.

In plain words, the four fixes are:

1. **Release packaging mismatch -- fixed**
   - The updater now picks the right file from the GitHub release.

2. **Content validation before replacement -- fixed**
   - The standalone helper takes only `TeknoParrot-Manager.ps1` from the downloaded zip, never the whole archive. (The menu update installs the whole release; see "Menu integration" below.)
   - It checks that file before replacing the live script.
   - The new script's version must match the release tag.

3. **PowerShell 5.1 TLS hardening -- fixed**
   - The updater switches on TLS 1.2 (a secure connection type) before any GitHub call.

4. **Testability -- fixed**
   - The update logic can be tested without changing any files.

### More detail

**1. Release packaging mismatch -- fixed**

- `-AssetNamePattern` now defaults to `^TeknoParrot\.Manager\.v.*\.zip$`, matching the published GitHub asset name `TeknoParrot.Manager.v1.0.RC7.zip`.
- Historical live verification against v1.0-RC3 confirmed the updater selected the real release asset.
- The version-agnostic pattern is also exercised by the published RC7 package validation; no older RC is an active download target.

**2. Content validation before replacement -- fixed**

- The updater extracts only the `TeknoParrot-Manager.ps1` entry from the downloaded zip (via `Expand-TpmReleaseZipEntry`), never the whole archive.
- Before replacing the live script, `Test-TpmExtractedScript` verifies that the file exists, is non-empty, is not raw zip data, and contains the `TeknoParrot Manager` marker.
- It also requires one bare, unwrapped, unscoped root `EndBlock` `$ScriptVersion =` assignment with a direct constant-string RHS, plus at most one equivalent `$ReleaseCandidateLabel` assignment.
- Additional statically identifiable protected writes fail closed: attributed/cast or transparent-parenthesis targets, scoped/nested/destructured or compound assignments, increment/decrement, foreach variables, root-script parameters, data-statement variables, and member/index lvalue roots.
- Function-local parameters are not root declarations; indirect/dynamic runtime mutation is outside the finite static-analysis contract.

**2. Content validation (continued):**

- It rejects any extracted-script byte above `0x7F` before AST parsing, preserving the BOM-less ASCII/Windows PowerShell 5.1 source interpretation.
- The standalone updater requires the extracted candidate identity to match the release tag before replacement.
- The main updater also reads the installed script identity back after replacement and verifies it against the release tag.
- Both compare the complete numeric-version/RC identity; standalone local-version reads use the same static declaration contract.

**2. Historical live verification:**

- Historical live verification: a full -Apply against v0.99.38 previously downloaded, extracted, validated, and installed the genuine script.
- That release is retired; RC6 is historical.
- RC7 validation uses the exact published GitHub asset and its mirror copy and does not change updater behavior.

**3. PowerShell 5.1 TLS hardening -- fixed**

- `Enable-TpmTls12` forces `Tls12` into `[Net.ServicePointManager]::SecurityProtocol` before any GitHub API/download call.
- It is guarded to skip on PowerShell 6+ where it is unnecessary.

**4. Testability -- fixed**

- All logic besides argument parsing and top-level orchestration now lives in `tools/TpmAutoUpdate.Core.psm1`, a side-effect-free module.
- `tools/Invoke-TpmAutoUpdate.ps1` is a thin orchestrator that imports it.
- `Tests/TpmAutoUpdate.Core.Tests.ps1` covers version parsing, asset selection, URL validation (URI-parsed, not `-like`), backup creation, zip extraction, content-validation failure modes, and an `-Apply -WhatIf` case asserting zero backup/download/replacement occurs.

## Destructive-path validation (`Tests/TpmAutoUpdate.DestructivePath.Tests.ps1`)

These tests check what happens when an update goes wrong.

In every case the original script must stay safe.

**The download is bad:**

1. A corrupt zip download is rejected. The original and backup stay intact.
2. A zip missing `TeknoParrot-Manager.ps1` is rejected with a specific "does not contain expected entry" error.
3. Two content-validation failures are rejected before replacement: a missing `$ScriptVersion`, and an extracted file that is itself raw zip bytes.
4. A truncated/partial download is treated as corrupt and rejected.

**Something fails during the update:**

5. The script file is marked read-only. The approved main-menu flow clears only the target file's ReadOnly attribute after explicit approval, then restores it in cleanup. The standalone `tools\` helper remains manual-unlock-only.
6. If backup creation fails, the update aborts after the verified download and before replacement. The original is untouched.
7. If extraction fails (valid zip, corrupted entry payload), the update is rejected. The original and backup stay intact.
8. If replacement fails after a successful backup (another program has the file locked), the original file is provably unchanged. The backup and the temp cleanup both hold.

### More detail

- These regression scenarios exercise failure handling. Downloads need a verified SHA-256 before anything is backed up or replaced.
- Scenario 8 detail: the destination is locked by another handle, `Move-Item` fails, and the original file is provably unchanged (not partially written).

**9. Module-scope error-action regression guard**

- This was a real bug found while writing this suite.
- A module's `$ErrorActionPreference` is snapshotted from the caller at *import* time, and the orchestrator intentionally imports without `-Force` (to stay mockable).
- An already-loaded module instance would silently keep whatever preference was active at its original import.
- That meant a non-terminating cmdlet error inside the module could be silently swallowed.
- Fixed by setting `$ErrorActionPreference = 'Stop'` explicitly at the top of `TpmAutoUpdate.Core.psm1` itself, independent of import history.

## Safety rules

1. **Manual by default**
   - Checking for updates is safe and read-only (it only looks).
   - Applying an update requires an explicit user action.
   - Startup may perform a quiet read-only GitHub check, but it never installs silently: applying still requires an explicit user action (you must press Y).
   - No background updater service, scheduled update task, or silent self-replacement.

2. **Backup before replacement**
   - The current script is copied to a new backup folder under `UpdateBackups` before replacement.
   - Backup folders are never reused or overwritten.
   - The standalone `tools/Invoke-TpmAutoUpdate.ps1 -Apply` refuses a multi-file release ZIP and changes nothing, and tells the user to use menu 16. The menu flow installs it whole (see Menu integration below).
   - If backup creation fails, the update is aborted.

3. **GitHub Releases only**
   - Releases are fetched from `Jumpstile/teknoparrot-manager`.
   - Update assets must come from GitHub release asset URLs.
   - Arbitrary URLs are never accepted.

4. **Validated local replacement**
   - The asset is downloaded to a temporary path first. It must exist and have non-zero length.
   - Both updater paths require and verify the GitHub release-asset SHA-256 before ZIP inspection or extraction. Case differences are accepted; malformed or missing digests are not.
   - If the asset is a zip, the updater must extract and validate `TeknoParrot-Manager.ps1` before replacement.
   - The current script is copied to backup first. Replacement happens only after the backup, download, extraction, and content validation all succeed.

5. **Version-aware**
   - Local version is read from the script's `$ScriptVersion` value.
   - Latest version is read from the GitHub release tag.
   - Tags are normalized by trimming a leading `v`.

6. **Recoverable**
   - The backup path is printed after update.
   - A failed update leaves the current script in place whenever possible.
   - Restore remains manual and transparent.

### More detail

**Backup folder names:**

- The main script uses `UpdateBackups\TeknoParrotManager_<timestamp>\`.
- A second backup in the same second takes the next free numbered folder (`_2`, `_3`, ...).
- The name stays short on purpose. Required game patches reuse this helper deep inside their recovery folders.
- Windows PowerShell 5.1 cannot use paths longer than 259 characters unless Windows long-path support is enabled.
- The standalone tool's backup folder is `UpdateBackups\<yyyyMMdd-HHmmss>_<32 hex>\` (GUID suffix).

## Standalone helper

The standalone helper is for scripted or manual use outside the interactive menu.

`-CheckOnly` only looks for a newer release. `-Apply` installs it (see Menu integration below for multi-file ZIPs).

```powershell
.\tools\Invoke-TpmAutoUpdate.ps1 -CheckOnly
.\tools\Invoke-TpmAutoUpdate.ps1 -Apply
```

### More detail

- This keeps the first cut reviewable before wiring it into the main menu.

## Download transport

The updater downloads the same careful way as the rest of TeknoParrot Manager.

It uses the same hardened transport order as the main script's shared `Invoke-TpmDownload` pipeline.

It tries these methods in order:

1. `Start-BitsTransfer` when BITS (the Windows background download service) is available and running.
2. `System.Net.Http.HttpClient` streamed download.
3. `Invoke-WebRequest` only as an emergency fallback after BITS and HttpClient fail.

**What happens to the downloaded file:**

- It is written to a temporary/partial path first.
- It is verified to exist and be non-empty.
- It is size-checked when the GitHub asset metadata includes a byte count.
- Only after validation is it moved into the path used by extraction.
- Partial files are cleaned up on failure.

**What you see while it downloads:**

Progress uses a single updating progress activity.

It shows percent, downloaded MB / total MB, MB/s, and ETA (time left) when the total size is known.

When the total size is not known, it shows an indeterminate downloaded-MB/MB/s message.

Final metrics record the method used, file size, elapsed time, and average MB/s.

### More detail

- The standalone module has a module-local copy of this transport helper rather than importing the main script.
- This preserves the no-side-effect, Pester-testable module used by `tools\Invoke-TpmAutoUpdate.ps1` without loading the main script.
- Keep the two implementations behaviorally aligned until a future consolidation.

## Menu integration (v0.99.39)

TeknoParrot Manager has a "Check for Updates" main menu option (option 16 in the current menu).

It follows the flow originally planned here.

**What you do and what you see:**

1. Choose "Check for Updates" (option 16) at the main menu. You will see "Check for Updates", then `Checking for updates...`. Next: wait for the check to finish. The check itself changes nothing and saves no backup.
2. If you are up to date, you will see `You have the newest version (...).` and then `No update needed.` Next: press Enter to return to the menu.
3. If a newer version exists, you will see `An update is available: <current> -> <latest>` and an `Updating will:` list of 4 numbered lines: download the update and check it, check what is inside, back up every file it replaces, and install it, check it and restart. Nothing is changed until you answer Y. Next: read the list.

**Then you choose:**

4. You will see `Update to <version> now? (Y/N)`. Next: type N to skip, or Y to update.
5. If you type N, you will see `Skipped -- no changes made.` Nothing changes.
6. If you type Y on a single-file release ZIP, the update runs and TPM asks you to restart. You will see `Restart TeknoParrot Manager now to run the verified update.` Next: press Enter to exit, then start TeknoParrot Manager again.

**If the new release is a multi-file package (RC8.1 and later):**

The update installs the whole package. It backs up every file it replaces first, and puts every file back if anything goes wrong. If the drive is too full, it says so and installs nothing. When it is done, you see `Update installed and verified. Restart TeknoParrot Manager to use it.` Start it again yourself.

Files from an older version that the new release no longer has are left where they are and listed in Details. Your own files are never deleted.

The step list in "More detail" below describes the single-script path; "Multi-file release" describes the full package.

**If something goes wrong:**

Any failure at any step displays the exact error.

It also states whether a backup was created, and returns safely to the main menu without exiting.

### More detail

**How it is built:**

- The interactive checker is implemented as plain functions inside TeknoParrot-Manager.ps1 itself: `Get-ManagerUpdateRelease`, `Assert-ManagerUpdateTargetWritable`, `New-ManagerUpdateBackup`, `Expand-ManagerUpdateAsset`, `Test-ManagerUpdateExtractedScript`, `Invoke-CheckForUpdates`.
- It does not import `tools/TpmAutoUpdate.Core.psm1`.
- The logic (asset pattern, content validation, read-only pre-check) is deliberately kept in lockstep with the standalone module.
- `tools/Invoke-TpmAutoUpdate.ps1` remains available separately for scripted/manual use outside the interactive menu.

**Multi-file release (RC8.1 and later), menu flow only:**

- TeknoParrot Manager is not a single-file runtime. It ships required modules (for example `scripts/TpmRequiredPatchEngine.ps1`, `scripts/TpmProgress.psm1`, the certification modules, and `tools/`) and packaged data alongside `TeknoParrot-Manager.ps1`, so the menu flow installs the whole package.
- `Get-ManagerUpdatePackageFiles` checks every entry name before anything is extracted (no rooted or drive names, no `..`, no reserved names, no names that differ only by letter case). Reason code `UPDATE_PACKAGE_BAD_ENTRY`.
- The free space on the program's drive must be at least twice the unpacked size. Reason code `UPDATE_NOT_ENOUGH_DISK_SPACE`.
- The package is unpacked into a new `tpm-update-staging-<id>` folder inside the program folder (same drive) with `Expand-ZipFileSafe`; each file's size is checked. The staged script goes through `Test-ManagerUpdateExtractedScript`, must match the release tag, and must be newer than the installed script (reason code `UPDATE_VERSION_NOT_NEWER`).
- `Get-ManagerUpdateInstallPlan` sorts the files into new, changed and identical. Identical files are not touched.
- Every file that will be replaced is copied (same relative path, hash checked) into `UpdateBackups\TeknoParrotManager_<timestamp>\`. The folder is named in the log and in Details (`TechnicalDetails.MultiFile.BackupFolder`).
- The files are installed with `Invoke-TpmTransactionalPromote`, the same staging, promote and rollback primitive the ReShade and dgVoodoo2 installs use. The main script is replaced last. Every installed file is hashed again inside the promotion; a mismatch rolls everything back. If any step fails, every changed file is put back and every added file is removed (`ROLLED_BACK_VERIFIED`, reason code `UPDATE_ROLLBACK_VERIFIED`). If the rollback itself cannot be proven, the result is `ACTION_REQUIRED` with `UPDATE_ROLLBACK_UNVERIFIED` and the staging folder is kept.
- Read-only flags on replaced files are cleared for the install and set again afterward.
- Nothing is deleted. Files from an older version that the new package no longer has, inside the folders the package uses, are left in place and listed in Details (`TechnicalDetails.MultiFile.LeftInPlace`).
- The staging folder (created by this run) and the downloaded ZIP are removed at the end, success or failure.
- `tools/Invoke-TpmAutoUpdate.ps1 -Apply` still refuses a multi-file ZIP and changes nothing. Its message now says to use menu 16 (Check for Updates) or the startup update, which install the whole release through the verified code above (there is no second implementation).
- While an update runs, the staging folder holds an open marker file (`.tpm-update-running`). Each file's checksum is taken while it is written to staging and must equal the staged file before anything is installed, so a file damaged on its way to disk is never installed. The ZIP's SHA-256 from GitHub already covers every byte of every file in the ZIP; a list of per-file checksums inside the same ZIP would have the same trust root and add no protection, so none is shipped.
- If an update is cut off (power loss, window closed), the staging folder is left behind. At the next start `Write-TpmInterruptedUpdateNotice` says so in plain words, names the newest `UpdateBackups` folder and how to copy the old files back, and logs it. A folder whose marker is still held open belongs to a running update (for example in a second window) and gets no notice. The folder is never deleted automatically, because it can hold the only copy of files that were moved aside; a guided restore is not offered because it cannot be verified.

**Actual flow (single-file ZIP), checking and confirming:**

1. Show local version.
2. Query latest GitHub Release.
3. If no newer version exists, report that the user is current and return to the menu.
4. If a newer version exists, show release tag/name and asset selected.
5. Explain what updating will do (download and check the file, check what is inside, back up every file it replaces, install and check, restart) and ask for explicit Y/N confirmation.

**Actual flow, downloading and backing up:**

6. Require valid GitHub digest metadata, download the asset, and verify its SHA-256. Stop on missing or failed verification without changing the installed script or creating a backup.
7. Inspect the package first. A ZIP with only `TeknoParrot-Manager.ps1` takes the single-script path (steps 8-9 and the replace step below). Any other ZIP (RC8.1 and later) is installed whole, see "Multi-file release" above. A ZIP without the script is refused before anything changes. The standalone helper still refuses a multi-file ZIP.
8. If the target is read-only, the approved main-menu flow temporarily clears only that target attribute; cleanup restores it. The standalone helper stops and tells the operator how to unlock it manually.
9. Back up the current script before replacement, then extract the single-script candidate and validate its content.

**Actual flow, replacing and restarting:**

10. Replace script. As of issue #86 (v0.99.45), the replace step itself is verified, not just assumed to succeed: `Move-Item` is called with `-ErrorAction Stop`, and a post-move `Test-Path` confirms the destination now actually holds the new content before reporting success.
11. Tell the user to restart TeknoParrot Manager, then exit this session -- it never continues running the replaced script in the current process.

**Why step 10 is checked:**

- Previously, a briefly-locked destination (for example, antivirus scanning the new file) could let `Move-Item` silently no-op while the script still reported "Update installed successfully".
- The fix makes that failure surface as a real, actionable error instead, with the original script and its backup left untouched.

## Startup update check (v0.99.39)

When TeknoParrot Manager starts, it quietly checks for updates once.

You can switch this off with `CheckForUpdatesOnStartup` in `TeknoParrot-Manager.config.json` (default `true`).

It never runs in `-Unattended` mode.

**What you will see:**

1. If you are already up to date, nothing is shown. The menu appears.
2. If GitHub cannot be reached or the check is too slow, nothing is shown. The menu appears.
3. If a newer version exists, you will see an "Update Available" screen. It shows `Current version`, `Latest version`, the release name if there is one, and a one-line summary.
4. The screen then shows the `Updating will:` list and the choices one by one: `Y = Update now`, `N = Remind me later`, `V = View release notes`. You are asked `Your choice (Y/N/V)`. Next: type Y, N, or V.

**What each answer does:**

- **Y** starts the update right away. There is no second question. The `Updating will:` list is shown above the choices, so you read it before you answer. The update still downloads and checks the file, backs up every file it replaces, and puts the old version back if anything fails.
- **N** (or pressing only Enter) continues to the menu. You will see `Continuing -- you can check again any time from the menu.`
- **V** prints the full release notes, then asks the question again.
- Any other key shows `Invalid choice. Enter Y, N, or V.` and asks again. It does not continue to the menu.

If the release has no notes, you will see `No release notes were provided for this release.`

### More detail

**Flow:**

1. Runs once, right after the program starts, before the saved-settings question and before any TeknoParrot-root prompts. Never runs in `-Unattended` mode -- there is no way to show an interactive prompt there, and Unattended is meant to be fast and non-interactive.
2. Queries the latest release with a single short-timeout attempt (`-MaxAttempts 1 -TimeoutSec 5`, vs. the menu option's patient 3x/20s retry) so an unreachable GitHub cannot meaningfully delay startup. A failed or timed-out check is logged and the script continues straight to the menu -- no error is shown to the user for what is, from their perspective, an unrequested background check.
3. If already current: nothing is shown, continues directly to the menu (optionally logged).
4. If a newer version exists: shows current/latest version, the release name if present, and a one-line summary (`Get-ManagerUpdateReleaseSummary` -- the first non-blank line of the release body, markdown heading/bullet markers stripped, clamped to 150 characters), then prompts Y/N/V.
5. A read-only target uses the same approved main-menu handling as the menu option; the standalone helper stops after download verification but before backup or replacement.

**How the answers work:**

- **Y** starts the update right away, then calls `Invoke-ManagerUpdateInstall`. There is no second confirmation; the "what updating will do" list is shown above the choices.
- A successful install still requires the caller (top-level script code, not the function) to exit.
- That is the same reasoning as the menu option: the function itself never calls `exit`, both for testability and so the N path can return normally.
- **N** (or pressing only Enter) -- continues straight to the menu; logged as "remind me later."
- Any other key shows `Invalid choice. Enter Y, N, or V.` and asks again. It does not continue to the menu.
- **V** -- prints the full release body, then re-prompts (Y/N/V again) rather than exiting the loop.

**How it is built:**

- `Invoke-StartupUpdateCheck` shares `Get-ManagerUpdateRelease`, `Get-ManagerVersionIdentity`, and `Compare-ManagerVersionText` with the menu.
- It uses the same install path (`Invoke-ManagerUpdateInstall`).
- So the callers retain the same full RC/final version ordering and backup/download/extract/validate/replace behavior.

## Non-goals for 1.0

TeknoParrot Manager will not do these things in 1.0.

**No silent behavior:**

- No silent updating.
- No updater service.
- No scheduled task.

**No risky shortcuts:**

- No unsigned third-party update source.
- No complex package manager.
- No automatic execution of downloaded code in the same session.
