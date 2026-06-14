# TeknoParrot Manager — Quick Start

> **Beta** — test one game after each run. Profiles are backed up automatically before every run.

Full documentation: [README.md](README.md)

---

## Contents

- [Requirements](#requirements)
- [Run It](#run-it)
- [Mode List](#mode-list)
- [Game Selection (AutoSync)](#game-selection-autosync)
- [Copy Your Controls](#copy-your-controls)
- [Crosshair Setup](#crosshair-setup)
- [ReShade Visual Enhancements](#reshade-visual-enhancements)
- [dgVoodoo2 Legacy Compatibility](#dgvoodoo2-legacy-compatibility)
- [GPU Compatibility Fixes](#gpu-compatibility-fixes)
- [RetroBat / Batocera](#retrobat--batocera)
- [Unattended Mode](#unattended-mode)
- [Thumbnail Download](#thumbnail-download)
- [LaunchBox Export](#launchbox-export)
- [HyperSpin 2 Export](#hyperspin-2-export)
- [Restoring a Backup](#restoring-a-backup)
- [Fuzzy Matching and Dat Integration](#fuzzy-matching-and-dat-integration)
- [Action Required Summary](#action-required-summary)
- [Good to Know](#good-to-know)
- [Quick Fixes](#quick-fixes)
- [Files the Script Keeps](#files-the-script-keeps)

---

## Requirements

- Windows 10 or 11
- PowerShell 5.1 (built into Windows — no install needed)
- TeknoParrot installed with `TeknoParrotUi.exe` run at least once so it has downloaded its `GameProfiles` folder
- Your games as ZIP files (for AutoSync) or already extracted into subfolders

---

## Run It

1. Open PowerShell in the folder containing `TeknoParrot-Manager.ps1`:

   ```powershell
   cd "C:\path\to\TeknoParrot\Scripts"
   .\TeknoParrot-Manager.ps1
   ```

2. Blocked by execution policy? Allow it for this session only:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\TeknoParrot-Manager.ps1
   ```

3. On first run the script auto-detects TeknoParrot's install path. If found it confirms it; if multiple installs are found it lists them numbered for easy selection.

4. On later runs it offers to reuse your saved settings — press **Y** to continue, **N** to reconfigure.

5. Pick a mode. After each mode completes you return to the menu.

6. Answer the folder prompts. For AutoSync, choose a **local** staging folder with enough free space, **outside** both TeknoParrot and your ZIP source.

7. Launch `TeknoParrotUi.exe` — your games now appear.

---

## Mode List

| # | Mode | What it does |
|---|------|-------------|
| 1 | **AutoSync** | Extract ZIPs from NAS or local source, then register |
| 2 | **Register only** | Games already extracted — just register |
| 3 | **Restore backup** | Roll UserProfiles back to a previous backup |
| 4 | **Crosshair setup** | Pick and deploy custom crosshairs to lightgun games |
| 5 | **ReShade setup** | Add visual post-processing to game folders |
| 6 | **dgVoodoo2 setup** | Fix old DX8 / DirectDraw / Glide games |
| 7 | **GPU fix setup** | Apply AMD / NVIDIA / Intel vendor fix to registered games |
| 8 | **Exit** | Quit |

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

Bind ONE game of each control type in TeknoParrotUI — then the script copies those bindings to every other game of the same type automatically.

**Good reference games to bind first:**

| Type | Suggestions |
|------|------------|
| Fighting / buttons | Street Fighter III, BlazBlue, Tekken 7, Dead or Alive 5 |
| Driving | Daytona Championship USA, Initial D, OutRun 2 SP |
| Lightgun | House of the Dead 4, Aliens Extermination |
| Trackball | Golden Tee Live, Silver Strike Bowling |

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
   - Pcsx2x6 games: shared pair in the pcsx2x6 emulator folder; `inis\PCSX2.ini` is also updated with `cursor_path` for each USB guncon2 port
4. Optionally choose to hide the Windows cursor in all gun game profiles (a backup is taken automatically first)

Run mode 4 again any time to change designs. Add your own PNG files to the `Crosshairs\` folder and the script picks them up automatically.

---

## ReShade Visual Enhancements

ReShade adds post-processing effects without modifying any game files. Remove it by deleting one DLL from a game folder.

**Popular effects:**

| Effect | What it does |
|--------|-------------|
| LumaSharpen / CAS | Removes blurry upscaling |
| CRT_Royale / CRT_Lottes | Classic scanlines and curvature |
| Levels / Vibrance | Vivid colours on modern monitors |
| Border | Arcade cabinet artwork in black bars |

### If you downloaded the ZIP release

`ReShade64.dll` is already in the `ReShade\` folder. Just run mode 5 or answer Y when prompted at the end of any run.

### If you cloned from GitHub (DLLs not included in repo)

1. Download the installer from [reshade.me](https://reshade.me)
2. Run it — point it at any 64-bit TeknoParrot game exe. It creates a DLL in that folder.
3. Copy that DLL to `ReShade\ReShade64.dll` next to the script
4. (Optional) Repeat with a 32-bit game exe and save as `ReShade32.dll`
5. Run mode 5 or answer Y when prompted

**In-game:** press **Home** to open the ReShade overlay. Toggle effects, adjust sliders — settings save to `ReShade.ini` in the game folder.

**To remove:** delete the DLL (`dxgi.dll`, `d3d9.dll`, `d3d12.dll`, or `opengl32.dll`) from the game folder.

---

## dgVoodoo2 Legacy Compatibility

Some older arcade games use DirectX 8, DirectDraw, or 3dfx Glide. On modern PCs these cause crashes or black screens. dgVoodoo2 translates old API calls into DirectX 11/12 — no game files are changed.

**Only use this for games that crash or show a black screen on first launch.**

**Setup:**
1. Download dgVoodoo2 from [dege.freeweb.hu](https://dege.freeweb.hu/dgVoodoo2/dgVoodoo2/)
2. Create a `dgVoodoo2\` folder next to this script and copy in:
   - From `MS\x86\`: `D3D8.dll`, `DDraw.dll`, `D3DImm.dll`
   - From `3Dfx\x86\`: `Glide2x.dll`, `Glide3x.dll`
   - From the ZIP root: `dgVoodoo.conf`
3. Run mode 6 or answer Y at the end of any run. The wizard auto-detects which games need it and shows them first.

**To remove:** delete the deployed DLL(s) from the game folder.

---

## GPU Compatibility Fixes

Many TeknoParrot games include optional fix settings for AMD, NVIDIA, or Intel GPUs. Mode 7 auto-detects your GPU via WMI and applies the correct fix to every registered game that supports one. `GameProfiles` is scanned at runtime — newly added games are always covered without a script update. Safe to re-run any time you change GPU or update drivers.

---

## RetroBat / Batocera

On first run the script asks:

```
Is this a RetroBat/Batocera installation? (Y/N)
```

Answer **Y** and game folders are extracted as `GameName.teknoparrot` instead of `GameName`. Registration and fuzzy matching are identical — the suffix is stripped before any comparison. The script also recognises `.parrot` and `.game` suffixes from other tools. The answer is saved and never asked again.

**To switch an existing library:** delete `TeknoParrot-Manager.config.json` and re-run. To re-extract with the new naming, also delete `TeknoParrot-Manager.syncstate.json` from your staging folder.

---

## Unattended Mode

Run with `-Unattended` to skip all prompts:

```powershell
.\TeknoParrot-Manager.ps1 -Unattended
```

Automatically: extracts new games, registers, repairs, propagates controls, downloads thumbnails, and logs everything. Requires saved settings from a prior interactive run. Restore mode is not available unattended.

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

Answer Y to fetch `ProfileCode.png` for every registered game not already in `<TeknoParrotRoot>\Icons\`. Source: [TeknoParrotUIThumbnails](https://github.com/teknogods/TeknoParrotUIThumbnails). Missing games are skipped without error.

**Custom thumbnails:**
1. Create a `CustomThumbnails\` folder next to the script
2. Name each image `ProfileCode.png` — e.g. `Daytona3.png`, `HouseOfDead4.png`
3. Run the script and answer Y to the thumbnail prompt — your images are copied to TeknoParrot's Icons folder. Files already present are never overwritten.

**Finding a game's profile code:** after any run, open `TeknoParrot-Manager-controls.txt` — every registered game is listed with its exact profile code.

---

## LaunchBox Export

At the end of every run:

```
Export a LaunchBox import XML for all registered games? (Y/N)
```

Answer Y to write `TeknoParrot-LaunchBox-Import.xml` next to the script with every game's title, platform, TeknoParrotUI path, and `--profile=` argument.

**How to import into LaunchBox:**

1. If TeknoParrot is not yet in LaunchBox: **Tools → Manage → Emulators → Add**
   - Name: `TeknoParrot`
   - Emulator path: browse to `TeknoParrotUi.exe`
   - Command-line parameters: `--profile="{rom}"`
   - Save

2. **Tools → Import → Emulated Games**

3. Wizard screen 1:
   - Emulator: TeknoParrot
   - Import type: Import ROM files
   - Folder: your games staging folder
   - File types: `*.exe`

4. Click Next, review matches, click Import. Re-run the wizard any time you add more games — LaunchBox skips games already in your library.

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

## Restoring a Backup

1. Close TeknoParrot completely before restoring
2. Re-run the script and choose mode 3 — Restore backup
3. The script lists all backups (most recent first) with file counts
4. Pick one by number, type `YES` to confirm
5. Re-open TeknoParrot to use the restored profiles

---

## Fuzzy Matching and Dat Integration

### Fuzzy Matching (NESiCAxLive and shared-exe platforms)

Games that share an executable (all NESiCAxLive titles use `game.exe`) are auto-registered by comparing the game folder name to every candidate profile using a similarity score.

| Score | Action |
|-------|--------|
| >= 0.72 | Auto-registered and shown in cyan — spot-check |
| >= 0.40 | Listed in ACTION REQUIRED with best-guess profile shown — one click to confirm |
| < 0.40 | Listed in ACTION REQUIRED with full candidate list |

Folder names are normalised before comparison: years like `(2012)`, ISO dates like `(2015-12-28)`, decimal versions like `(2.10.00)`, region codes like `(JPN)`, version strings like `(ver 1.1)`, and bracket metadata like `[NESiCAxLive]` are all stripped. Meaningful names like `(Special Edition)` are kept because they may distinguish two titles.

**Wrong match?** Delete the game's `.xml` from `UserProfiles` and add a `forceArchetype` entry in `overrides.json` to pin it on the next run.

### Dat File Integration

During initial setup the script asks:

```
D) Download from GitHub now  (~145 MB)
Z) I have the ZIP already -- enter path
F) I have separate dat files -- enter paths
N) Skip
```

Both the collection dat and supplementary dat are read directly from inside the ZIP — no extraction needed. The supplementary dat takes priority for any game in both (it represents the version you should install).

The dat resolves three registration scenarios that would otherwise require manual action:
- **Shared-executable games** (NESiCAxLive, etc.) — disambiguated instantly by folder name
- **Games with no profile match** (pcsx2x6, ELF-based Lindbergh titles) — found by normalised folder name in a second pass
- **Slightly misnamed folders** — fuzzy scan of all dat entries

Games registered via dat are shown as `Registered (dat/exact)` or `Registered (dat/fuzzy)`.

---

## Action Required Summary

At the end of every run the script prints — and saves to `TeknoParrot-Manager-ActionItems.txt` — everything still needing attention:

| Section | Meaning |
|---------|---------|
| **Not in TeknoParrot** | Folders that matched no TeknoParrot profile — informational, likely unsupported games |
| **Register these games** | Shared-exe games below confidence threshold — shows exe, best-guess profile, and full candidate list |
| **Fix these game paths** | Profiles with broken paths that couldn't be auto-repaired — open TeknoParrotUI and point each to the correct folder |
| **Extract first** | Profiles pointing at unextracted games — extract and re-run Repair |
| **Set up controls** | Control types with no reference game bound yet — shows which games are waiting and suggests what to bind |

---

## Good to Know

- Profiles are backed up before every run to `UserProfiles\FullBackup\<date_time>\`. Nothing is ever deleted automatically.
- If backup folder creation fails, the script stops rather than proceeding without a restore point.
- If the log file is inaccessible, a one-time warning shows the reason. Every entry that can't be written is echoed to the console prefixed with `[UNLOGGED]` so nothing is silently lost.
- If an extraction is interrupted (Ctrl+C, power loss, disk error), the incomplete folder is automatically detected and re-extracted on the next run.
- Fuzzy name matching auto-registers most NESiCAxLive and other shared-exe games. The similarity score is shown for spot-checking.
- Games already bound are always left untouched. Game-specific controls that don't exist in the reference game are left for manual setup and reported in ACTION REQUIRED.
- After every run, `TeknoParrot-Manager-controls.txt` is written next to the script: every game, its control family, propagation source, bound count, and any buttons still set manually.
- After registering, the script offers to repair any broken game paths automatically.
- On later runs the script remembers your settings — press Y to reuse, N to reconfigure.
- To fix a mis-classified control family (e.g. FamilyGuyBowling auto-detected as driving when it should be trackball), add it to the `familyOverride` section of `overrides.json`.

---

## Quick Fixes

| Problem | Fix |
|---------|-----|
| Game won't launch | Open TeknoParrotUI, point the profile to the correct `.exe`. Re-run the script and choose Repair. |
| Game not in TeknoParrot | Check ACTION REQUIRED — may need manual registration or needs to be extracted first. |
| Extraction keeps failing | Check the log for the specific error. Verify free space and that the ZIP is not corrupted. |
| Controls wrong after propagation | Restore from backup (mode 3), or delete the game's `.xml` and re-run after fixing the reference game's bindings in TeknoParrotUI. |
| Wrong fuzzy match | Delete the game's `.xml` from `UserProfiles` and add a `forceArchetype` entry in `overrides.json`. |
| Game appears twice in TeknoParrotUI | Delete one of the duplicate `.xml` files from `UserProfiles` — keep the one with the correct path and any bindings already set. |
| `[UNLOGGED]` on console | Log file is inaccessible — check that the TeknoParrot folder is not read-only and you have write permission. |
| HyperSpin 2 export fails | TeknoParrot must be set up as an emulator in HyperSpin 2 first — the title must contain "TeknoParrot". |

---

## Files the Script Keeps

| File | Location | Purpose |
|------|----------|---------|
| `TeknoParrot-Manager.config.json` | Scripts folder | Saved folders and settings |
| `TeknoParrot-Manager.overrides.json` | Scripts folder | Per-game tweaks (noSync, onlySync, noPropagate, forceArchetype, familyOverride, datFile) |
| `TeknoParrot-Manager.log` | Scripts folder | Log of every run |
| `TeknoParrot-Manager.syncstate.json` | Staging folder | Tracks extracted ZIPs — delete to re-extract all |
| `TeknoParrot-Manager-controls.txt` | Scripts folder | Controls state after every run |
| `TeknoParrot-Manager-ActionItems.txt` | Scripts folder | Action items from last run |
| `TeknoParrot-LaunchBox-Import.xml` | Scripts folder | LaunchBox reference XML |
| `ReShade\ReShade64.dll` | Scripts folder | Bundled ReShade DLL (64-bit) |
| `ReShade\ReShade32.dll` | Scripts folder | Bundled ReShade DLL (32-bit, optional) |
| `dgVoodoo2\*.dll` + `dgVoodoo.conf` | Scripts folder | dgVoodoo2 DLLs (you provide) |
| `Crosshairs\*.png` | Scripts folder | Crosshair images (321 included) |
| `CustomThumbnails\*.png` | Scripts folder | Your own game icons (optional, you create) |

---

> Full documentation: [README.md](README.md)
