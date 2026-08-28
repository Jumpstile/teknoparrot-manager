# TeknoParrot Manager — Quick Start

> Current published release: v1.0 RC7 -- test one game after every run. Profiles are backed up automatically before every run. [RC7 release archive](https://github.com/Jumpstile/teknoparrot-manager/releases/tag/v1.0-RC7). Previous published release: v1.0 RC6 (historical). v1.0 RC8 is the candidate being prepared and is not published. Final Version 1.0 remains unpublished.

Full documentation: [README.md](README.md)

---

## Contents

- [Requirements](#requirements)
- [Run It](#run-it)
- [Mode List](#mode-list)
- [Create Support Package](#create-support-package)
- [Game Selection (AutoSync)](#game-selection-autosync)
- [Copy Your Controls](#copy-your-controls)
- [Crosshair Setup](#crosshair-setup)
- [ReShade Visual Enhancements](#reshade-visual-enhancements)
- [dgVoodoo2 Legacy Compatibility](#dgvoodoo2-legacy-compatibility)
- [GPU Compatibility Fixes](#gpu-compatibility-fixes)
- [Force Feedback (FFB) Setup](#force-feedback-ffb-setup)
- [BepInEx update and setup](#bepinex-update-and-setup)
- [Postgres Setup](#postgres-setup)
- [LaunchBox Integration](#launchbox-integration)
- [HyperSpin 2 Export](#hyperspin-2-export)
- [RetroBat / Batocera](#retrobat--batocera)
- [Preview / Dry-Run Mode](#preview--dry-run-mode)
- [Unattended Mode](#unattended-mode)
- [Thumbnail Download](#thumbnail-download)
- [Restoring a Backup](#restoring-a-backup)
- [Library Health Check](#library-health-check)
- [Fuzzy Matching and Dat Integration](#fuzzy-matching-and-dat-integration)
- [Action Required Summary](#action-required-summary)
- [Good to Know](#good-to-know)
- [Quick Fixes](#quick-fixes)
- [Files the Script Keeps](#files-the-script-keeps)

---

## Requirements

- Windows 10 or 11
- PowerShell 5.1 (built into Windows — no install needed)
- TeknoParrot installed with `TeknoParrotUi.exe`; TPM opens it automatically
  when its profile library is missing
- Your games as ZIP files (for AutoSync) or already extracted into subfolders
- TPM asks Windows for permission automatically when a safe setup step needs it — you do not need to prepare an Administrator PowerShell window

---

## TeknoParrotUI first-run handoff

After you choose the TeknoParrot folder, TPM checks for the local game
profiles. If they are missing, TPM opens `TeknoParrotUi.exe` and waits while
TeknoParrot finishes its own first setup. TPM does not edit its
`ParrotData.xml`, controls, or DAT/XML settings. If the setup window needs
your attention, TPM tells you exactly what to do and checks again in the same
workflow. This handoff is separate from checking whether a game's controls
are mapped and verified.

## Advanced users

TPM is also for people who already know TeknoParrot and want repeatable,
auditable library operations. Use previews, logs, backups, action summaries,
exact paths, profile identifiers, hashes, and validation evidence to review
bulk work without losing the technical detail.

The full advanced-user guide in docs/ADVANCED-USERS.md explains the evidence
model and ownership boundaries. Expert workflows still detect first, preview
supported changes, back up before writes, and verify the result.

---

## Run It

1. Double-click **`TeknoParrot-Manager.bat`**. This is the normal beginner-friendly way to start TPM; it opens the menu for you.

   Advanced users can run the script directly from PowerShell in the folder containing `TeknoParrot-Manager.ps1`:

   ```powershell
   cd "C:\path\to\TeknoParrot\Scripts"
   .\TeknoParrot-Manager.ps1
   ```

2. If you are using the advanced PowerShell route and Windows blocks the script, allow it for this session only:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\TeknoParrot-Manager.ps1
   ```

3. On first run the script auto-detects TeknoParrot's install path. If found it confirms it; if multiple installs are found it lists them numbered for easy selection.

4. On later runs it offers to reuse your saved settings — press **Y** to continue, **N** to reconfigure.

5. Pick a mode. After each mode completes you return to the menu.

6. For AutoSync, TPM recommends a safe staging folder derived from your configured TeknoParrot location. Press **Enter** to use it or **B** to browse elsewhere. The accepted folder must have enough free space and must be outside (and not contain) TeknoParrot, TPM's program folder, and both ZIP source folders. TPM creates it on a real run if it does not exist; Preview/Dry Run leaves it untouched.

7. Launch `TeknoParrotUi.exe` after registration to see the games. If the
   profile library is missing earlier, TPM opens TeknoParrotUI and waits for
   its first setup automatically.

## Workflow status

During multi-step work TPM shows `TPM STATUS` with the current action, what
just finished, the next step, and anything it needs from you. It uses real
step counts, keeps important failures visible until you acknowledge them,
and adapts safely when the PowerShell window is resized. Redirected,
unattended, and certification runs use structured status events without
cursor-control output.

---

## Mode List

| #   | Mode                           | What it does                                                                                                                               |
| --- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | **AutoSync**                   | Extract ZIPs from NAS or local source, then register                                                                                       |
| 2   | **Register only**              | Games already extracted — just register                                                                                                    |
| 3   | **Propagate Controls**         | Copy known bindings from a reference game to compatible unbound games in the same detected family; not universal device or shooter mapping |
| 4   | **Crosshair setup**            | Pick and deploy custom crosshairs to lightgun games                                                                                        |
| 5   | **ReShade setup**              | Add visual post-processing to game folders                                                                                                 |
| 6   | **dgVoodoo2 setup**            | Fix old DX8 / DirectDraw / Glide games                                                                                                     |
| 7   | **GPU fix setup**              | Apply AMD / NVIDIA / Intel vendor fix to registered games                                                                                  |
| 8   | **Force feedback (FFB) setup** | Native FFB Blaster (membership) + free third-party plugin                                                                                  |
| 9   | **BepInEx setup**       | User-approved install, update, or repair-reset using stable x64/x86 releases                                                                     |
| 10  | **Library health check**       | Read-only registered/broken/empty status, plus GPU fix / FFB Blaster / dgVoodoo2 / Postgres coverage and ReShade/BepInEx install counts    |
| 11  | **Restore backup**             | Roll TeknoParrot profiles, LaunchBox's library files, or Postgres databases back to a previous backup                                      |
| 12  | **Postgres setup**             | Installs/configures the local PostgreSQL database some Incredible Technologies games need                                                  |
| 13  | **Check for Updates**          | Check GitHub for a newer TPM release and install it                                                                                        |
| 14  | **Create Support Package**     | Gather safe logs and reports into one ZIP to send when asking for help                                                                   |
| 15  | **Exit**                       | Quit                                                                                                                                       |
## Create Support Package

If you need help, choose **Create Support Package**. TPM collects safe logs and
reports for you, checks private information, and creates one ZIP in
`SupportPackages\` beside the script. Send that ZIP when asking for help.

The package may include allowlisted TPM and TeknoParrot text logs, safe
game-local logs, and metadata about plugin files. It never includes ROMs, game
executables, arbitrary DLL payloads, firmware, profiles, credentials,
PostgreSQL passwords, `.pgpass`, recovery state, tokens, API keys, cookies, or
unrelated personal files. If an optional diagnostic is missing or cannot be
read, TPM says so and marks the package partial when appropriate. A failed
collection or ZIP creation is never reported as success.

Choose **Open TPM Logs and Reports** in the same menu to browse the folder
containing TPM's current logs and reports.

---


## Game Selection (AutoSync)

After entering your folders, the script filters out already-extracted games and shows:

```
A) All unextracted games    -- extract everything not yet on disk
L) Browse and select        -- paginated A-Z list, pick by number
S) Search by keyword        -- filter by name, pick by number
D) Done                     -- proceed with current selection
```

In Browse or Search: type numbers or ranges (e.g. `1,3,5-7`) to add games to your queue. Games already in your queue are marked with `*`. Mix Browse and Search sessions before pressing D to confirm.

---

## Copy Your Controls

Bind ONE game of each control type in TeknoParrotUI. The script can copy those known bindings to compatible unbound games in the same detected control family. This is a bounded reference-copy aid, not universal controller or gun detection or complete shooter mapping.

**Good reference games to bind first:**

| Type               | Suggestions                                             |
| ------------------ | ------------------------------------------------------- |
| Fighting / buttons | Street Fighter III, BlazBlue, Tekken 7, Dead or Alive 5 |
| Driving            | Daytona Championship USA, Initial D, OutRun 2 SP        |
| Lightgun           | House of the Dead 4, Aliens Extermination               |
| Trackball          | Golden Tee Live, Silver Strike Bowling                  |

**Steps:**

1. In TeknoParrotUI, fully bind one game of each type — buttons, axes, Test, Service, Coin, Start
2. Re-run this script — propagation runs automatically after registration
3. Launch ONE updated game and test it before trusting the rest

---

## Crosshair Setup

Mode 4 deploys custom crosshair cursor images to all registered lightgun games.

**Steps:**

1. An HTML preview page opens in your browser showing all 321 included designs
2. Enter the index number for your P1 and P2 crosshair (can be the same)
3. The script copies the images to every registered lightgun game:
   - Standard games: `P1.png` + `P2.png` in the game's exe folder
   - ElfLdr2 games: shared pair in the ElfLdr2 emulator folder
   - Pcsx2x6 games: shared pair in `pcsx2x6\TeknoParrot\crosshairs\` (the official upstream location); `inis\PCSX2.ini` is also updated with `cursor_path` for each USB guncon2 port
4. Optionally choose to hide the Windows cursor in all gun game profiles (a backup is taken automatically first)

Run mode 4 again any time to change designs. Add your own PNG files to the `Crosshairs\` folder and the script picks them up automatically.

---

## ReShade Visual Enhancements

ReShade adds post-processing effects without modifying game data. TPM does not automatically remove unowned or changed hook files; use the advanced troubleshooting path for those files.

**Popular effects:**

| Effect                  | What it does                         |
| ----------------------- | ------------------------------------ |
| LumaSharpen / CAS       | Removes blurry upscaling             |
| CRT_Royale / CRT_Lottes | Classic scanlines and curvature      |
| Levels / Vibrance       | Vivid colours on modern monitors     |
| Border                  | Arcade cabinet artwork in black bars |

### Advanced emergency fallback (normal users should use mode 5)

ReShade DLLs are not bundled in the release ZIP because ReShade is not
redistributed by TPM. Mode 5 can download and verify the official installer
from `reshade.me`, extract the required DLLs, and deploy them transactionally.
If the automatic source is unavailable, an advanced user may obtain the
official installer separately and place validated DLLs in `ReShade\`.

The installer signature is checked before any deployment. A signature or
archive failure stays blocked; TPM never substitutes an unverified DLL.

**In-game:** press **Home** to open the ReShade overlay. Toggle effects, adjust sliders — settings save to `ReShade.ini` in the game folder.

**Removal:** TPM does not automatically remove unowned or changed hook files; use the advanced troubleshooting path for those files.

**Note:** before deploying, the script checks your ReShade DLLs Authenticode signature (ReShade installer is code-signed) and warns -- without blocking -- if it is not validly signed. When mode 5 downloads the installer, the log also records the authoritative source, filename/version, SHA-256, transfer metrics, signer/status/thumbprint, and final trust result; the SHA-256 is an audit hash, not a published-digest comparison.

---

## dgVoodoo2 Legacy Compatibility

Some older arcade games use DirectX 8, DirectDraw, or 3dfx Glide. On modern PCs these cause crashes or black screens. dgVoodoo2 translates old API calls into DirectX 11/12 — no game files are changed.

**Only use this for games that crash or show a black screen on first launch.**

**Setup:** run mode 6. TPM downloads and verifies the official dgVoodoo2
release, extracts the required files in staging, and deploys only after the
complete set passes validation. An advanced emergency fallback may use a
folder already obtained from the official source; TPM still validates its
layout before deployment.

**To remove:** use the dgVoodoo2 setup flow to review deployed files. TPM does
not delete an unowned file that could belong to another compatibility tool.

---

## GPU Compatibility Fixes

Many TeknoParrot games include optional fix settings for AMD, NVIDIA, or Intel GPUs. Mode 7 auto-detects your GPU via WMI and applies the correct fix to every registered game that supports one. `GameProfiles` is scanned at runtime — newly added games are always covered without a script update. Safe to re-run any time you change GPU or update drivers.

---

## Force Feedback (FFB) Setup

Mode 8 covers two independent ways to get force feedback / rumble working, and they're not mutually exclusive:

- **Native FFB Blaster** — TeknoParrot's own built-in feature, but it requires an active paid TeknoParrot membership. The script asks if you have one; answer N and this part is skipped entirely (there's no point enabling a field that has no effect without a subscription). If you answer Y, the field is discovered dynamically by scanning your `GameProfiles` folder — never hardcoded.
- **Third-party plugin** ([mightymikem/FFBArcadePlugin](https://github.com/mightymikem/FFBArcadePlugin)) -- free, no subscription needed. The per-game DLL table is fetched live from that project's GitHub repo every run. The shared audit records its source, filename/version, computed SHA-256, and transfer metrics; no signer or published-digest trust gate is claimed.

If a game is covered by both, the script asks **one** batched question — keep native FFB Blaster for all of them, or switch to the plugin for all of them — rather than asking per game. DLL collisions (e.g. ReShade already using `d3d9.dll`) are skipped with a warning, never overwritten.

**Removal:** TPM records its own deployed hook files. When you choose native
FFB for an overlap, it backs up and removes only a matching unchanged file.
Unowned or changed files remain untouched and are reported as an advanced
troubleshooting boundary.

---

## BepInEx update and setup

[BepInEx](https://docs.bepinex.dev) is a third-party Unity plugin/modding
framework some games need for controls or fixes. Mode 9 is the BepInEx update
and setup flow: it offers a user-approved install, update, or repair-reset for
games. TPM chooses the stable x64 or x86 package from the game's executable,
downloads it with digest validation, backs up the existing fixed BepInEx
tree, and rolls back on a failed promotion.

Nothing is installed silently into every game. If a game folder is unsafe or
the network cannot be reached, TPM explains that no change was made and
offers the automatic retry path. Manual deletion of BepInEx files is not the
normal workflow; TPM only removes the fixed files it can verify as part of
its own approved transaction.
Power Putt Live (2012/2013), Silver Strike Bowling Live, Target Toss Pro
(Bags / Lawn Darts), and Orange County Choppers Pinball -- need a small local
PostgreSQL 8.3 database. Mode 12 detects which registered games need it.

- If PostgreSQL is not installed yet, TPM installs it when a registered game
  needs it. You choose the service-account and database passwords through
  masked confirmation prompts. If Windows permission is needed, TPM asks
  Windows itself and continues the same setup after you approve it.
- If PostgreSQL is already installed, TPM preserves existing data. If the saved
  password no longer works, TPM explains the problem, asks whether to fix it,
  and lets you choose and confirm a new password. TPM creates and verifies a
  protected recovery backup, asks Windows for permission when needed, resets
  only the postgres role, verifies the new password, saves it securely, and
  continues the setup without sending you back to the menu.
- If Windows permission is declined or the repair cannot finish, TPM keeps the
  temporary protected repair information and offers a retry. Your password is
  never shown in commands, logs, or messages, and no database data is deleted.
- Recovery changes the role password only. TPM does not edit pg_hba.conf, drop
  or recreate databases, or wipe existing PostgreSQL data.
- After recovery, TPM updates only affected profiles whose connection values are
  not already correct. The TeknoParrotUI Pass field remains plaintext because
  TeknoParrotUI reads it directly; already-correct profiles are skipped.
- Recovery evidence and database backups are created before profile population.
  Any backup, reset, database, or profile-write failure is reported as blocked.
  If none of your registered games need Postgres, mode 12 says so and exits immediately without installing anything. The PostgreSQL guide download is logged with source, filename/version, SHA-256, and transfer metrics; this path does not claim Authenticode or published-digest verification.

---

## Check for Updates

Mode 13 manually checks the latest GitHub release against the version you are running -- nothing is downloaded or changed without your explicit Y/N confirmation. If an update exists, it backs up the current script, downloads and validates the update, replaces the script, then exits so you can restart cleanly. An approved update may temporarily clear only the target file protection and restores it after the attempt; any failure tells you exactly what went wrong and whether a backup was made. The download log records source, filename/version, SHA-256, and transfer metrics; the manager update path does not consume GitHub optional asset digests, so the hash is audit-only.

---

## LaunchBox Integration

At the end of most runs:

```
Add your registered games to LaunchBox now? (Y/N)
```

Answer Y to write directly into LaunchBox's own library — no import wizard needed. The script checks LaunchBox/BigBox are closed first, backs up the files it's about to change, and never duplicates a game already there. The first time you use it, choose how games should appear:

1. Mixed into your existing **Arcade** platform
2. A separate **TeknoParrot** platform
3. A platform with a **name you choose**
4. **Both** Arcade and a dedicated platform at once

Your choice is remembered for next time. New entries have no box art/metadata yet — use LaunchBox's own "Search"/re-scrape per game.

Prefer not to let the script touch LaunchBox directly? Answer N, then Y to the next prompt for the older `TeknoParrot-LaunchBox-Import.xml` manual-import file and wizard instructions instead.

---

## HyperSpin 2 Export

At the end of every run:

```
Export registered games to HyperSpin 2? (Y/N)
```

Answer Y to merge every registered game not already present into HyperSpin 2's TeknoParrot game list (default data folder: `C:\ProgramData\HyperSpin\data`). Your path is saved and reused on future runs.

**Prerequisites:** TeknoParrot must be set up as an emulator in HyperSpin 2 first — the emulator title must contain "TeknoParrot" (spacing and capitalisation variations are fine). HyperSpin 2 must not be running when you answer Y.

Games are added with title only. Use HyperSpin 2's Scrape feature for box art and metadata.

---

## RetroBat / Batocera

On first run the script asks:

```
Is this a RetroBat/Batocera installation? (Y/N)
```

Answer **Y** and game folders are extracted as `GameName.teknoparrot` instead of `GameName`. Registration and fuzzy matching are identical — the suffix is stripped before any comparison. The script also recognises `.parrot` and `.game` suffixes from other tools. The answer is saved and never asked again.

**To switch an existing library:** delete `TeknoParrot-Manager.config.json` and re-run. To re-extract with the new naming, also delete `TeknoParrot-Manager.syncstate.json` from your staging folder.

---

## Preview / Dry-Run Mode

Before AutoSync or Register actually writes anything, the script offers:

```
Run in PREVIEW mode first? (Y/N)
```

Answer Y (or pass `-DryRun` on the command line) to see exactly what would happen — extraction, registration, repair, control propagation — with **zero files written**. After a preview pass, the script offers to apply the same run for real immediately, without re-entering any answers.

Preview mode skips the LaunchBox/HyperSpin 2 export offers, the thumbnail download offer, and the GPU fix offer too, since those are themselves writes that don't make sense after a run that changed nothing.

---

## Unattended Mode

Run with `-Unattended` to skip all prompts:

```powershell
.\TeknoParrot-Manager.ps1 -Unattended
```

Automatically: extracts new games, registers, repairs, propagates controls, downloads thumbnails, and logs everything. Requires saved settings from a prior interactive run. Restore mode and Postgres setup are not available unattended.

**Scheduling with Windows Task Scheduler:**

1. Run interactively once to save your settings
2. Open Task Scheduler (`taskschd.msc`) and create a new Task
3. General tab: set a name, check "Run whether user is logged on or not" and "Run with highest privileges"
4. Triggers tab: set your preferred schedule
5. Actions tab — Action: Start a program
   - Program: `powershell.exe`
   - Arguments: `-ExecutionPolicy Bypass -NonInteractive -File "C:\path\to\Scripts\TeknoParrot-Manager.ps1" -Unattended`
6. (Optional) Conditions tab: "Start only if the following network connection is available"

Check `TeknoParrot-Manager.log` after each scheduled run.

---

## Thumbnail Download

After registration the script asks:

```
Download thumbnails for registered games missing an icon? (Y/N)
```

Answer Y to fetch ProfileCode.png for every registered game not already in <TeknoParrotRoot> Icons. Source: TeknoParrotUIThumbnails on GitHub. Missing games are skipped without error. The shared audit records source, filename, SHA-256, and transfer metrics; no published digest or signer trust gate is claimed for icons.

**Custom thumbnails:**

1. Create a `CustomThumbnails\` folder next to the script
2. Name each image `ProfileCode.png` — e.g. `Daytona3.png`, `HouseOfDead4.png`
3. Run the script and answer Y to the thumbnail prompt — your images are copied to TeknoParrot's Icons folder. Files already present are never overwritten.

**Finding a game's profile code:** after any run, open `TeknoParrot-Manager-controls.txt` — every registered game is listed with its exact profile code.

---

## Restoring a Backup

1. Choose **mode 11 — Restore backup**. TPM keeps the selected backup and
   explains if TeknoParrot or LaunchBox/BigBox must be closed.
2. Close the named application, then press Enter when TPM asks it to check
   again. TPM resumes the same restore choice; you do not restart the whole
   workflow.
3. Pick which kind to restore:
   - **TeknoParrot UserProfiles backup**
   - **LaunchBox library backup** — only relevant if you've used direct LaunchBox integration
   - **Postgres database backup** — only relevant if you've used Postgres setup (mode 12); this replaces the _current_ content of each database restored
4. The script lists all available backups of that kind (most recent first), pick one by number, type `YES` to confirm
5. Re-open TeknoParrot (or LaunchBox) to use the restored data

---

## Library Health Check

Mode 10 is a **read-only** status check — it never extracts, registers, repairs, propagates, or touches the network. Safe to run any time. Reports:

- Registered/broken/empty `GamePath` counts, with affected profile codes listed
- GPU fix / FFB Blaster / dgVoodoo2 / Postgres coverage — which eligible games don't have each applied yet
- ReShade / BepInEx install counts, informationally (these are cosmetic per-game choices, not flagged as something to fix)

Third-party FFB plugin coverage isn't included here (checking it needs a live lookup) — use mode 8 for that instead.

---

## Fuzzy Matching and Dat Integration

### Fuzzy Matching (NESiCAxLive and shared-exe platforms)

Games that share an executable (all NESiCAxLive titles use `game.exe`) are auto-registered by comparing the game folder name to every candidate profile using a similarity score.

| Score   | Action                                                                         |
| ------- | ------------------------------------------------------------------------------ |
| >= 0.72 | Auto-registered and shown in cyan — spot-check                                 |
| >= 0.40 | Presented in TPM for an explicit candidate choice; unresolved cases remain in ACTION REQUIRED |
| < 0.40  | Listed in ACTION REQUIRED with full candidate list                             |

Folder names are normalised before comparison: years like `(2012)`, ISO dates like `(2015-12-28)`, decimal versions like `(2.10.00)`, region codes like `(JPN)`, version strings like `(ver 1.1)`, and bracket metadata like `[NESiCAxLive]` are all stripped. Meaningful names like `(Special Edition)` are kept because they may distinguish two titles.

**Wrong match?** Delete the game's `.xml` from `UserProfiles` and add a `forceArchetype` entry in `overrides.json` to pin it on the next run.

### Dat File Integration

During initial setup the script asks:

```
D) Download from GitHub now  (~145 MB; TPM chooses the safe data location)
B) Browse/import a ZIP or dat file I already have
N) Skip
```

Both the collection dat and supplementary dat are read directly from inside the ZIP — no extraction needed. The supplementary dat takes priority for any game in both (it represents the version you should install).

Eggman recognition data is separate from TeknoParrotUI's `ParrotData.xml` and DAT/XML setting, and separate from the main/supplementary game ZIP sources and the staging/install folder. The normal first-run download goes to `%LOCALAPPDATA%\TeknoParrotManager\Eggman` without a save-location prompt, and browse/import remains available for an existing local file. A later explicit update reuses a valid configured ZIP at its existing location without an alternate-location save dialog. Every supplied, previously configured, or user-selected destination is canonicalized and revalidated before reuse, download, or write; unsafe destinations are rejected before network/download work begins.

On repeat runs, the script reuses your last dat choice automatically but offers to check for a newer dat release first.

The dat resolves three registration scenarios that would otherwise require manual action:

- **Shared-executable games** (NESiCAxLive, etc.) — disambiguated instantly by folder name
- **Games with no profile match** (pcsx2x6, ELF-based Lindbergh titles) — found by normalised folder name in a second pass
- **Slightly misnamed folders** — fuzzy scan of all dat entries

Games registered via dat are shown as `Registered (dat/exact)` or `Registered (dat/fuzzy)`.

---

## Action Required Summary

At the end of every run the script prints — and saves to a text file (default `TeknoParrot-Manager-ActionItems.txt` next to the script; a Save dialog lets you pick somewhere else) — everything still needing attention:

| Section                          | Meaning                                                                                                                                                                                                                                                                                                          |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Not in TeknoParrot**           | Folders that matched no TeknoParrot profile — informational, likely unsupported games                                                                                                                                                                                                                            |
| **Register these games**         | Shared-exe games below confidence threshold — choose a validated candidate in TPM, or leave it unresolved for TeknoParrotUI                                                                                                                                                                                                             |
| **Fix these game paths**         | Profiles with broken paths that couldn't be auto-repaired — open TeknoParrotUI and point each to the correct folder                                                                                                                                                                                              |
| **Extract first**                | Profiles pointing at unextracted games — extract and re-run Repair                                                                                                                                                                                                                                               |
| **Set up controls**              | Control types with no reference game bound yet — shows which games are waiting and suggests what to bind                                                                                                                                                                                                         |
| **Controls not ready**           | Registered games whose catalog-backed controls are **Missing**, **Not verified**, **Unsupported**, or **Unknown**. Registration, a successful launch, and TeknoParrot wizard completion do not verify controls. Open TeknoParrot controls configuration and map/test controls before treating the game as ready. |
| **Setup notes**                  | Registered games with special setup notes from the community compatibility database — shows the expected executable name and the full notes text                                                                                                                                                                 |
| **Compatibility warnings**       | Known install-path-length limits, pinned-file-version requirements, and GPU-vendor incompatibilities for specific games                                                                                                                                                                                          |
| **Firmware not installed**       | Registered games whose emulator (currently pcsx2x6 only) needs firmware/BIOS files TeknoParrot itself doesn't provide — shows the exact files and folder needed. TPM never downloads, links, or redistributes these; existence check only                                                                        |
| **Emulator component not found** | A contract-backed required emulator component is missing at its expected path. Shows the contract/detector evidence and affected profiles. Use the normal TeknoParrot installation/update process; TPM does not diagnose why it is missing or repair, download, reinstall, or modify TeknoParrot                 |

---

## Good to Know

- Profiles are backed up before every run to `UserProfiles\FullBackup\<date_time>\`. Nothing is ever deleted automatically.
- If backup folder creation fails, the script stops rather than proceeding without a restore point.
- You must own or otherwise have lawful rights to the original arcade PCB and any ROM/game data you use. TPM does not provide, distribute, or endorse unauthorized game files.
  The log also records a download audit trail: ReShade installer source/filename/version/SHA-256 plus Authenticode signer/status/thumbprint/trust result; BepInEx GitHub source/filename/version/SHA-256 plus digest validation when available; dgVoodoo2, FFBArcadePlugin, Eggman/RomVault dat, PostgreSQL guide, TPM update package, and TeknoParrotUI thumbnails with source/hash/transfer audit fields. Transfer method, size, elapsed time, and average MB/s are included. Sources without a published digest or signing anchor are not described as cryptographically authenticated.
- If an extraction is interrupted (Ctrl+C, power loss, disk error), the incomplete folder is automatically detected and re-extracted on the next run.
- Fuzzy name matching auto-registers most NESiCAxLive and other shared-exe games. The similarity score is shown for spot-checking.
- Games already bound are always left untouched. Game-specific controls that don't exist in the reference game are left for manual setup and reported in ACTION REQUIRED.
- After every run, `TeknoParrot-Manager-controls.txt` is written next to the script: every game, its control family, propagation source, bound count, and any buttons still set manually. It is a propagation inventory, not proof that controls have been verified; review the ACTION REQUIRED controls status and map/test required controls before treating a game as ready.
- After registering, the script offers to repair any broken game paths automatically.
- On later runs the script remembers your settings — press Y to reuse, N to reconfigure.
- To fix a mis-classified control family (e.g. FamilyGuyBowling auto-detected as driving when it should be trackball), add it to the `familyOverride` section of `overrides.json`.
- A Postgres Pass is updated only for affected profiles after a verified backup; values that already match the approved password are skipped. Other non-empty settings remain protected and are not silently overwritten.

---

## Quick Fixes

| Problem                                    | Fix                                                                                                                                                                                 |
| ------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Game won't launch                          | Open TeknoParrotUI, point the profile to the correct `.exe`. Re-run the script and choose Repair.                                                                                   |
| Game not in TeknoParrot                    | For an ambiguous shared executable, choose one of TPM's validated candidates or leave it for TeknoParrotUI. If no candidate is safe, extract the game first.                                                                                                |
| Extraction keeps failing                   | Check the log for the specific error. Verify free space and that the ZIP is not corrupted.                                                                                          |
| Controls wrong after propagation           | Restore from backup (mode 11), or delete the game's `.xml` and re-run after fixing the reference game's bindings in TeknoParrotUI.                                                  |
| Wrong fuzzy match                          | Delete the game's `.xml` from `UserProfiles` and add a `forceArchetype` entry in `overrides.json`.                                                                                  |
| Game appears twice in TeknoParrotUI        | Delete one of the duplicate `.xml` files from `UserProfiles` — keep the one with the correct path and any bindings already set.                                                     |
| `[UNLOGGED]` on console                    | Log file is inaccessible — check that the TeknoParrot folder is not read-only and you have write permission.                                                                        |
| HyperSpin 2 export fails                   | TeknoParrot must be set up as an emulator in HyperSpin 2 first — the title must contain "TeknoParrot".                                                                              |
| Postgres setup needs Windows permission | TPM asks Windows automatically and resumes the same setup. Approve the Windows prompt; if you decline it, choose the automatic repair retry when TPM offers it. |

---

## Files the Script Keeps

| File                                  | Location                                                 | Purpose                                                                                                                                        |
| ------------------------------------- | -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `TeknoParrot-Manager.config.json`     | Scripts folder                                           | Saved folders and settings (Postgres password stored DPAPI-encrypted)                                                                          |
| `TeknoParrot-Manager.overrides.json`  | Scripts folder                                           | Per-game tweaks (noSync, onlySync, noPropagate, forceArchetype, familyOverride, canonicalArchetype, datFile)                                   |
| TeknoParrot-Manager.log               | Scripts folder                                           | Log of every run, including ReShade/BepInEx/dgVoodoo2 and other download audit fields: source, filename/version, SHA-256, and transfer metrics |
| `TeknoParrot-Manager.syncstate.json`  | Staging folder                                           | Tracks extracted ZIPs — delete to re-extract all                                                                                               |
| `TeknoParrot-Manager-controls.txt`    | Scripts folder                                           | Controls state after every run                                                                                                                 |
| `TeknoParrot-Manager-ActionItems.txt` | Scripts folder (default; Save dialog can pick elsewhere) | Action items from last run                                                                                                                     |
| `TeknoParrot-LaunchBox-Import.xml`    | Scripts folder                                           | LaunchBox manual-import reference XML (only if you skip direct integration)                                                                    |
| `LaunchBoxBackups\`                   | Scripts folder                                           | Timestamped backups of LaunchBox's own files, made before each direct write                                                                    |
| `PostgresBackups\`                    | Scripts folder                                           | Timestamped `pg_dump` backups of Postgres databases, made before each Postgres setup run                                                       |
| `ReShade\ReShade64.dll`               | Scripts folder                                           | User-provided ReShade DLL (64-bit; not included in the release ZIP)                                                                            |
| `ReShade\ReShade32.dll`               | Scripts folder                                           | User-provided ReShade DLL (32-bit, optional; not included in the release ZIP)                                                                  |
| `dgVoodoo2\*.dll` + `dgVoodoo.conf`   | Scripts folder                                           | dgVoodoo2 DLLs (you provide)                                                                                                                   |
| `Crosshairs\*.png`                    | Scripts folder                                           | Crosshair images (321 included)                                                                                                                |
| `CustomThumbnails\*.png`              | Scripts folder                                           | Your own game icons (optional, you create)                                                                                                     |

---

> Full documentation: [README.md](README.md)
