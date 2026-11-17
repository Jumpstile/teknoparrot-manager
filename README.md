# TeknoParrot Manager

![TeknoParrot Manager](images/banner.png)

TeknoParrot Manager is a Windows PowerShell tool for managing TeknoParrot arcade libraries on Windows. It registers extracted games, propagates controls, deploys lightgun crosshairs, applies ReShade and dgVoodoo2 compatibility fixes, and exports libraries to LaunchBox.

TeknoParrot Manager is made for beginners and is also useful if you already know TeknoParrot. It hides complexity, not detail. Repeatable bulk steps (AutoSync, Register, Propagate Controls) save manual work. Where it changes your files it says so, makes a backup first, and shows what it did under Details and in the log. It keeps four things apart: games found, games registered, a game that launches, and controls that are set up. See [Advanced users](docs/ADVANCED-USERS.md).

Canonical links: [GitHub repository](https://github.com/Jumpstile/teknoparrot-manager) | [Releases](https://github.com/Jumpstile/teknoparrot-manager/releases) | [Issue tracker](https://github.com/Jumpstile/teknoparrot-manager/issues)

> **This guide describes v1.0 RC9.** RC9 is the current build and is not published yet. The latest published release is v1.0 RC8.2, a fix-up release for RC8.1. The previous published release is v1.0 RC8.1, the first version that can update itself in place (see Check for Updates). If you use RC8.1 or RC8.2, choose Check for Updates (menu 15) when RC9 comes out. Earlier published releases are v1.0 RC7 and RC6. RC8 was a tester build and was never published. The changes since RC8.2 are listed in `TeknoParrot-Manager-CHANGELOG.txt`. Final Version 1.0 remains unpublished. AutoSync backs up UserProfiles before extraction; preview mode skips the backup. Test one game after each run.


## Start here: your first game in about 10 minutes

TeknoParrot Manager adds games you own to TeknoParrot and helps copy controls and apply supported fixes. It is a separate tool, not TeknoParrot, and does not install or set up TeknoParrot itself.

Allow about 10 minutes once your downloads are ready.

Installing TeknoParrot, updates, large games, and special controllers take longer.

Release page of the latest published release: [v1.0 RC8.2](https://github.com/Jumpstile/teknoparrot-manager/releases/tag/v1.0-RC8.2).

You need:

- A Windows PC with PowerShell 5.1.
- Internet access.
- Enough disk space.
- Your own legally obtained games.

TeknoParrot Manager never provides, downloads, or links to games, ROMs, or patch files.

[Full step-by-step Start Here guide](docs/START-HERE.md) | [Ten beginner problems](docs/TROUBLESHOOTING.md) | [Plain-language glossary](docs/START-HERE.md#glossary)

If the menu numbers on your screen differ from this guide, use the names instead.

Each step below says what you will see. Do the steps in order.

**Part 1 -- Install TeknoParrot by hand**

1. Open the [official TeknoParrot download page](https://teknoparrot.com/en/Home/Download).

   You will see: the recommended stable installer and a separate experimental UI offer.

2. Click **Download TeknoParrot Installer**.

   You will see: the installer ZIP in your download folder.

3. In File Explorer, use **Extract All** to unpack that ZIP into a short folder you can write to.

   Extract first. Do not run the installer from inside the ZIP.

   You will see: `TeknoParrotInstaller.exe`, outside the ZIP.

4. Run **TeknoParrotInstaller.exe**.

   You will see: a folder box that starts as `C:\Windows\system32`.

   **Warning:** never install there.

5. Click **Browse...**, then **New folder**. Make a new empty folder with a short path and no spaces, such as `C:\TeknoParrot` (files go directly into it).

   You will see: your new folder in the path box.

6. Click the **TeknoParrotUI (v...) [REQUIRED]** row so it turns blue.

   You will see: the row turns blue.

7. Click **Download Selected**. Wait for `TeknoParrotUI: 100%`.

   **Full Install (Download All)** is optional. It downloads all 45 cores (size not measured).

   You will see: `TeknoParrotUi.exe` and `GameProfiles` directly in your folder.

8. Install **DirectX End-User Runtimes (June 2010)** from the official page's Recommended Software links.

   Runtimes are helper programs that many games need.

9. Install **Visual C++ Redistributable Runtimes All-in-One** from the same links.

   You will see: each runtime installer's result. (No runtime request appeared during the 2026-10-31 check, but the official page recommends both.)

10. Open **TeknoParrotUi.exe** yourself.

    You will see: the **Information** window.

11. Click **OK** on **Information**, then **OK** on **Privacy Notice**.

    Then click **Accept and Continue** on **Updated Policies**. (**Quit** closes the program instead.)

    You will see: a 6-step setup wizard.

12. Click **Skip Setup** (or skip wizard steps 2 to 5) if you will add games with TeknoParrot Manager.

    Next: go to the last wizard step.

13. Click **Finish** on the last step.

    You will see: TeknoParrotUI's main window with an empty game list.

    Next: close it before running TeknoParrot Manager. [How TeknoParrot Manager relates to the wizard](docs/START-HERE.md#3-open-teknoparrotui-once).

**Part 2 -- Get and start TeknoParrot Manager**

14. Download the complete latest published TeknoParrot Manager release ZIP from [TeknoParrot Manager releases](https://github.com/Jumpstile/teknoparrot-manager/releases).

    Or use the complete package supplied for testing.

    You will see: one package ZIP, not just a `.ps1` file.

15. Extract the whole package to a short writable folder such as `C:\TPM`, outside Program Files.

    You will see: `TeknoParrot-Manager.bat`, the script, and all supplied folders together.

16. Double-click **TeknoParrot-Manager.bat**.

    On a first run you will see: `Welcome to TeknoParrot Manager` and `Press Enter to continue`.

    If you saved settings before, you will see: `TeknoParrot Manager found your saved settings.` and the question `Use these settings? (Y/N, D = show them)`.

17. First run: press **Enter** at `Press Enter to continue`.

    You will see: the first-time questions.

    If you saw the saved-settings question, type **Y** to keep them.

    You will see: `Using your saved settings.`

    Next: skip steps 18 to 20. The folder questions are not asked again.

    Type **N** to use the first-time questions instead. Type **D** to show the saved settings and be asked again.

**Part 3 -- Answer the first-time questions**

18. Find the TeknoParrot folder question.

    You will see: `Auto-detected TeknoParrot at: ...` followed by `Use this path? (Y/N)`.

    Other things you might see: `Found TeknoParrot in multiple locations:` (pick one from the list), or `Type the path of your TeknoParrot folder, the one with TeknoParrotUi.exe in it, or Q to quit (or type B to browse)`.

19. Type **Y** only if the detected path is correct. Otherwise type **N**, then type **B** to browse, or type the folder yourself. Type **Q** to quit. Nothing is changed if you quit.

    Select the TeknoParrot folder that contains `TeknoParrotUi.exe`.

    You will see: the games-folder question, unless you kept your saved settings.

20. At the `Games folder (also called the staging folder)` question, choose the separate [staging folder](docs/START-HERE.md#staging-folder).

    Register only: use the parent folder of your extracted games. AutoSync: use the folder the ZIPs will be extracted into.

    You will see: the accepted folder, or a reason to choose another.

    It must not overlap either program or any ZIP source folder.

21. Press **Enter** at **Use RetroBat folder naming? (Y/N, default N)** for ordinary names.

    Choose **Y** only if you need RetroBat/Batocera's `.teknoparrot` names.

    You will see: the optional [DAT](docs/START-HERE.md#dat) question.

22. At the DAT question, choose **D** (default) for the optional community matching index. Choose **B** to import one you have. Choose **N** to skip.

    The index contains names, not games.

    You will see: the result of your choice, for example `Saved: ...` after a download.

**Part 4 -- Register your first game**

23. Choose **2) Register only** for extracted games, or **1) AutoSync** for your own ZIPs.

    You will see: **P** preview (default), **R** run now, **B** back.

    [The guide walks through source folders and selecting one ZIP](docs/START-HERE.md#6-register-your-first-game).

24. Press **Enter** for **P** to preview first.

    You will see: the proposed work, with no changes to games or setup files. Scans and logging still occur.

25. Choose **Y** at the end-of-preview apply question only if the proposed game and paths are correct.

    You will see: a fresh scan and the real results, after any repeated game selection.

    If something went wrong, you will see an error or an unresolved item rather than success.

    After new games are registered, you are asked once which country they should start in. Type **0** to leave them as they are. You can change it later with **10) Region setup**.

26. After a successful [registration](docs/START-HERE.md#registration), open **TeknoParrotUi.exe** yourself.

    You will see: your game in its list.

    TeknoParrot Manager never opens the UI. It also does not check whether the game setup files ([profiles](docs/START-HERE.md#profile)) are current.

27. Set and save that game's controls in TeknoParrotUI before using its launch action.

    You will see: saved button/axis bindings.

    Next: [test one game before copying controls](docs/START-HERE.md#7-make-one-game-work-well-then-copy-what-is-safe).

Next: [launch and test the game, then add only the fixes you need](docs/START-HERE.md#7-make-one-game-work-well-then-copy-what-is-safe).

GPU fixes, crosshairs, required patches, dgVoodoo2, ReShade, and FFB are explained there in priority order.

[LaunchBox](docs/START-HERE.md#launchbox) is optional. Choose **B** to skip it, or [preview before approving its library changes](docs/START-HERE.md#9-launchbox-is-optional).

**What the backup covers**

TeknoParrot Manager's normal [backup](docs/START-HERE.md#backup) saves a copy of TeknoParrot's saved game settings folder ([UserProfiles](docs/START-HERE.md#userprofiles)) only.

It does not cover game folders. It also does not cover game-side NVRAM, test-menu settings, or calibration files outside UserProfiles ([issue 378](https://github.com/Jumpstile/teknoparrot-manager/issues/378)).

Back up that game-side state yourself.

Optional library, database, and patch jobs make their own scoped backups. These are not whole-game protection.

**Where things are saved**

- Saved game-settings copies: `<TeknoParrotFolder>\UserProfiles\FullBackup\`
- Normal logs: `<TeknoParrotFolder>\TeknoParrotManager\Logs\`
- Reports: `<TeknoParrotFolder>\TeknoParrotManager\Reports\`

[Recovery instructions](docs/TROUBLESHOOTING.md#10-restore-a-backup).

Stuck? Use [Troubleshooting](docs/TROUBLESHOOTING.md) before changing more files.

### More detail: Start here

Official install sources were checked on 2026-10-31:

- [current download page](https://teknoparrot.com/en/Home/Download)
- [legacy guide](https://teknoparrot.com/wiki/getstarted.html) (it describes an older install flow)

The installer and first-run steps above were checked on 2026-10-31 with `TeknoParrotInstaller_2.0.0.11.zip` and TeknoParrotUI 1.0.0.2276. Later versions may differ.

The current page does not specify a .NET version or minimum Windows version.

[Install details and antivirus precautions](docs/START-HERE.md#2-install-teknoparrot-by-hand-first).

---


## Table of Contents

- [Start here](#start-here-your-first-game-in-about-10-minutes)
- [Beginner troubleshooting](docs/TROUBLESHOOTING.md)
- [Features](#features)
- [Glossary](#glossary)
- [How It Works](#how-it-works)
- [Requirements](#requirements)
- [Installation](#installation)
- [Running the Script](#running-the-script)
- [Progress bars](#progress-bars)
- [Modes](#modes)
- [Create Support Package](#create-support-package)
- [Game Selection (AutoSync)](#game-selection-autosync)
- [The Staging Folder](#the-staging-folder)
- [Registration](#registration)
- [How Fuzzy Matching Works](#how-fuzzy-matching-works)
- [Dat File Integration](#dat-file-integration)
- [Control Propagation](#control-propagation)
- [Propagate Controls (standalone menu option)](#propagate-controls-standalone-menu-option)
- [Device Survey](#device-survey)
- [Crosshair Setup](#crosshair-setup)
- [ReShade Visual Enhancements](#reshade-visual-enhancements)
- [dgVoodoo2 Legacy Compatibility](#dgvoodoo2-legacy-compatibility)
- [GPU Compatibility Fixes](#gpu-compatibility-fixes)
- [Force Feedback (FFB) Setup](#force-feedback-ffb-setup)
- [BepInEx update and setup](#bepinex-update-and-setup)
- [Required game patches](#required-game-patches)
- [Region Setup](#region-setup)
- [Postgres Setup](#postgres-setup)
- [Check for Updates](#check-for-updates)
- [LaunchBox Integration](#launchbox-integration)
- [Optional CPS3 first-boot files](#optional-cps3-first-boot-files)
- [Post-1.0 optional plugin scope](#post-10-optional-plugin-scope)
- [RetroBat / Batocera](#retrobat--batocera)
- [Thumbnail Download](#thumbnail-download)
- [Controls Status File](#controls-status-file)
- [Per-Game Overrides](#per-game-overrides)
- [Action Required Summary](#action-required-summary)
- [Unattended / Scheduled Mode](#unattended--scheduled-mode)
- [Preview / Dry-Run Mode](#preview--dry-run-mode)
- [Game Repair](#game-repair)
- [Safety, Backup and Log](#safety-backup-and-log)
- [Registration Evidence Ledger](#registration-evidence-ledger)
- [Resetting](#resetting)
- [Uninstalling / Removing the Manager](#uninstalling--removing-the-manager)
- [Troubleshooting](#troubleshooting)
- [What It Does Not Do](#what-it-does-not-do)
- [Files Reference](#files-reference)
- [Support / Contributing](#support--contributing)
- [License](#license)

---

## Features

This is a short list of what TeknoParrot Manager can do. Technical details are in the "More detail" part at the end of this section.

A "profile" is a small setup file for one game. TeknoParrot ships one for every game it supports.

- **Auto-registration** -- finds your extracted games and adds them to TeknoParrot with the right game path. It does not overwrite a game that is already added. The one exception is a duplicate that you choose to switch yourself: you are asked first, and a backup is made first.

- **Fuzzy name matching** -- works out the right game when several games share one program file. It compares folder names with game codes and adds the best match when it is sure enough.

- **Dat file integration** -- uses an optional community list of game names to recognize hard-to-match games, including games with no known program file and wrongly named folders.

- **Profile code matching** -- a third matching pass. It compares folder names directly with TeknoParrot's game codes.

- **GitHub profile resolution** -- tries to look up TeknoParrot's full game list online when it starts. If the online list is not available (it is not today), it uses the game setup files in your own TeknoParrot `GameProfiles` folder instead. This helps when a dat code does not exactly match a local game setup file.

- **Control propagation** -- set up the controls for one game of each control type. TeknoParrot Manager can then copy those controls to similar games that have none. It is a limited helper, not a universal device or shooter mapping.

- **AutoSync extraction** -- copies and unpacks game ZIPs from a NAS (a network drive) or a local folder. It leaves a game folder alone when its ZIP did not change. When a changed ZIP replaces a folder, the old folder's extra files (saves, settings, ReShade files) are saved first. If they cannot be saved, the game is skipped.

- **Game repair** -- finds broken or empty game paths and points them to the right place again.

- **Crosshair setup** -- gives lightgun games custom P1/P2 cursor images. A built-in preview of the included designs works with the keyboard.

- **ReShade** -- adds picture effects to game folders. From the ReShade menu you can also turn off TeknoParrot's own (native) CRT effect. You can change or undo your ReShade look for all games or for one game.

- **dgVoodoo2** -- fixes older games that crash on DirectX 8, DirectDraw, or Glide.

- **GPU fixes** -- detects your graphics card (AMD / NVIDIA / Intel). It applies the matching fix to every registered game that has one.

- **Force feedback (FFB)** -- two options that cover different games: native FFB Blaster (needs a paid TeknoParrot membership) and a free third-party plugin (fetched live, no subscription needed). If a game is covered by both, you're asked once which to use for all such games.

- **BepInEx setup** -- installs or updates BepInEx for the games you choose, after you approve. It makes a private, checked backup first. The backup is deleted after the update is verified, and kept if something goes wrong. It never removes an existing installation.

- **Region setup** -- lets you pick the country your games start in (like USA or Europe). It shows the games that offer that country, lets you choose all or some of them, asks you to confirm, saves a backup, and then changes them. It can also put games back to Auto. After registration you are also asked once about new games.

- **Required game patches** -- installs patches from your local ZIPs for known games. Success of a patch does not prove the game is ready.

- **Postgres setup** -- sets up the local PostgreSQL 8.3 database that some Incredible Technologies games need. It detects which registered games need it. It does not reinstall Postgres, and it does not recreate a game's database that already exists, unless you choose a restore (mode 14) or the `[I]` rebuild and then type `YES`. The one other case is a database that TeknoParrot Manager's own note says an earlier setup was still building when it stopped: that unfinished copy is removed and built again. The result screen is short; press D for details. Every game database is tested with the game's own settings before setup says it is ready, so you do not need any extra step in TeknoParrot or on the first start. A game with no starting database file (`pg_backup`) is left out and named. The other games are still set up.

- **Automatic compatibility warnings** -- every run checks for known problems and lists the details in ACTION REQUIRED.

- **Game-specific setup notes** -- every run checks the community compatibility database (eggmansworld.github.io/TeknoParrot) for registered games with special setup notes. The notes go to the separate `TeknoParrot-Manager-game-notes.txt` report. Raw source notes are not copied into ACTION REQUIRED.

- **LaunchBox direct integration** -- writes games straight into LaunchBox's own library.

- **Unattended mode** -- `-Unattended` flag for scheduled runs of the read-only Library Health Check (not AutoSync).

- **Preview / dry-run mode** -- shows the proposed AutoSync/Register changes without applying game/profile file changes. Choosing Apply reruns the operation and rescans before making changes.

- **Download audit logging** -- the log records where every download came from, the file name, and how the transfer went.

- **Safe by design** -- backups before destructive changes, free-space check, full log, one-click restore. Restore backup lists your saved copies newest first.

### More detail: Features

Auto-registration details:

- It scans `.exe`, `.elf`, `.iso`, `.xbe` (Sega Chihiro/cxbxr games such as Virtua Cop 3 and OutRun 2), `.dll` (Konami PC arcade games such as DanceDanceRevolution 2013 and Steel Chronicle), and more.

Matching details:

- Fuzzy name matching handles shared-executable platforms (NESiCAxLive, etc.). It compares folder names to profile codes and auto-registers the best match above a confidence threshold.

- Dat file integration downloads or reads the Eggman/RomVault dat ZIP. It resolves shared executables, registers games with no known exe (pcsx2x6, ELF-based Lindbergh titles), and handles misnamed folders.

- Profile code matching Dice-matches folder names directly against TeknoParrot profile code names. It resolves games whose profile has an empty `ExecutableName` (BladeStrangers, LuigisMansion, MaiMaiGreen, PokkenTournament, and others) without needing a dat entry.

- GitHub profile resolution tries to fetch the full GameProfile list from the TeknoParrot repo at launch. When that list is not available, it uses your local `GameProfiles` folder instead. It uses the list to resolve dat codes that don't exactly match a local template.

Control propagation details:

- It copies known bindings to compatible unbound games in the same detected control family. This is a bounded reference-copy aid, not universal device or shooter mapping.

ReShade, BepInEx and download details:

- ReShade works with 64-bit games. 32-bit games are skipped.

- The official installer downloaded by TeknoParrot Manager must pass a pinned Authenticode trust check before extraction. Checks on manually supplied DLLs are advisory.

- BepInEx setup uses stable x64/x86 packages. It makes a private verified backup and a journaled rollback.

Required game patches details:

- It installs 120 evidence-pinned recipes across 71 exact ProfileId/build/executable identities (54 game profiles) from local ZIPs.

- One hundred eight operations create only absent files. Twelve require an exact known before-state.

- Hardware alternatives require unambiguous captured evidence.

- Unknown target bytes are refused.

Postgres setup details:

- The games it covers are Golden Tee Live, Power Putt Live, Silver Strike Bowling Live, Target Toss Pro, and Orange County Choppers Pinball.

- Every game database is tested at the end of setup with the game's own saved settings. A game with no starting database file (`pg_backup`) cannot be made ready: it is left out, named on the result screen, and every other game is still set up.

Automatic compatibility warnings details:

- Install-path-length limits (Raw Thrills titles, Yu-Gi-Oh! Duel Terminal 6).

- Pinned-file-version requirements (BlazBlue/iDmacDrv32.dll, Tekken Tag Tournament 2/EBOOT.BIN).

- Known GPU-vendor incompatibilities (AMD/Intel).

Game-specific setup notes details:

- The notes cover workarounds, known quirks, and the expected executable name.

Preview / dry-run details:

- The preview covers extract, register, repair, and propagate.

- TeknoParrot Manager still records run activity in its log.

Download audit logging details:

- Every shared-pipeline download records its authoritative source URL, filename, version when known, computed SHA-256, and transfer metrics (method, size, elapsed time, average speed).

- ReShade additionally logs the installer signer/subject, Authenticode status, signer thumbprint, and the status/thumbprint/trust result. Its SHA-256 is an audit hash, not a published-digest comparison.

- BepInEx records its GitHub release source, filename/version, and computed SHA-256. When GitHub supplies an asset digest, the downloader validates it before extraction and logs/fails closed on a mismatch.

- dgVoodoo2 uses the same digest validation when available.

- FFBArcadePlugin, Eggman/RomVault dat, the PostgreSQL guide bundle, the TeknoParrot Manager update package, and TeknoParrotUI thumbnail downloads receive source/hash/transfer audit entries.

- Unsigned or digest-less sources are not described as cryptographically authenticated.

---

## Glossary

Terms used throughout this README, in the order you're likely to need them.

Short version: a "profile" is a small setup file for one game. There are two kinds, the GameProfile and the UserProfile.

| Term                             | Meaning                                                                                                                                                                                                                                                             |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **GameProfile**                  | The setup file TeknoParrot ships for one game, for example `StreetFighterIII3rdStrike.xml`. It lives in TeknoParrot's `GameProfiles\` folder. It lists the buttons and settings that game has. It does not yet point at your copy of the game. |
| **UserProfile**                  | Your own copy of a GameProfile. It is made when a game is registered. It lives in `UserProfiles\`, one file per registered game. It holds your actual `GamePath`, your control bindings, and your per-game settings. |
| **Profile Code**                 | The file name (without `.xml`) that a GameProfile and its UserProfile share, for example `StreetFighterIII3rdStrike`. The script and its logs use it to name one specific game. |
| **GamePath**                     | The field inside a UserProfile that points to the game's program file (its executable, or exe) on disk. Registration is mostly finding the right exe and writing it here. `GamePath2` is the same idea for games that need a second exe (see `HasTwoExecutables`). |
| **Registration**                 | Matching an extracted game folder to the correct GameProfile. Then creating or updating its UserProfile with the right GamePath. See [Registration](#registration). |
| **AutoSync**                     | This script's combined extract-and-register mode (mode 1). It pulls ZIPs from your NAS (network drive) or local source into a staging folder. Then it registers what it extracted. See [Game Selection (AutoSync)](#game-selection-autosync). |
| **Staging folder**               | The local folder AutoSync extracts ZIPs into before registration. See [The Staging Folder](#the-staging-folder). |
| **Fuzzy matching**               | How this script works out which GameProfile an extracted folder belongs to when the exe name alone is unclear. It compares the folder name with each candidate profile's code. See [How Fuzzy Matching Works](#how-fuzzy-matching-works). |
| **Dat file**                     | An optional community-made list (Eggmansworld TeknoParrot collection). It maps exact ZIP names to the right profile code. It is used instead of fuzzy matching for unclear games when available, because it is exact rather than a best guess. |
| **Control propagation**          | Set up the controls for ONE game per control type in TeknoParrot's own UI. TeknoParrot Manager can then copy known bindings to compatible unbound games in the same detected family. This is not universal device or shooter mapping. See [Control Propagation](#control-propagation). |
| **Archetype / reference game**   | A game where you have already bound enough buttons for it to be the source for copying controls to its control family. Its button bindings are kept. An explicit canonical reference can correct its InputAPI without rebinding. |
| **Family**                       | Which kind of controls a game uses: button / driving / lightgun / trackball / analog. It is found automatically per game. You can override it in `TeknoParrot-Manager.overrides.json`. |
| **ACTION REQUIRED**              | The end-of-run list of everything that still needs your attention in TeknoParrotUI. Examples: unclear registration choices, paths to fix, missing bindings. See [Action Required Summary](#action-required-summary). |
| **Dry-run / preview mode**       | Shows proposed AutoSync or Register changes without applying game/profile changes. Scanning, configuration handling, and logging still occur. |
| **Overrides (`TeknoParrot-Manager.overrides.json`)** | An optional file next to this script. It overrides automatic choices per game: skip syncing one, pin a game to a specific archetype, override its detected family, and a few other exceptions. See [Per-Game Overrides](#per-game-overrides). |
| **HasTwoExecutables**            | A GameProfile property (for example Initial D: Arcade Stage games). It means the game needs a second companion executable launched alongside the main one. It is handled automatically via `GamePath2`. |

---

## How It Works

TeknoParrot keeps two folders of game setup files in its main folder (its root):

| Folder         | Purpose                                                                                                                                           |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GameProfiles` | Ready-made setup files that ship with TeknoParrot, one per supported game. Each names the program file it expects. Each also carries that game's settings and controls. |
| `UserProfiles` | Your games. A game appears and launches once its setup file is copied here with the path to your program file filled in. |

This script automates the copy-and-fill step.

1. It scans your games.
2. It matches each program file to the right setup file.
3. It copies that setup file to `UserProfiles` and sets the path.

TeknoParrot picks the games up the next time it starts.

**Profile updates:** TeknoParrotUI keeps the `GameProfiles` folder current. TeknoParrot Manager downloads no profiles. It does not open TeknoParrotUI for you.

Games it cannot match are listed in the ACTION REQUIRED report.

---

## Requirements

- A Windows PC with PowerShell 5.1 available for TeknoParrot Manager; follow the current official requirements for TeknoParrot
- PowerShell 5.1 (built into Windows -- no install needed)
- TeknoParrot installed with `TeknoParrotUi.exe`
- Your games as ZIP files (for AutoSync) or already extracted into subfolders

---

## Installation

1. Download the current official release asset from
   [GitHub Releases](https://github.com/Jumpstile/teknoparrot-manager/releases).

   You will see: a ZIP file in your download folder.

2. Extract the complete package to a short writable folder outside Program Files (e.g. `C:\TPM`). Keep all supplied subfolders.

   You will see: `TeknoParrot-Manager.bat` with the other supplied folders beside it.

3. Double-click **`TeknoParrot-Manager.bat`**.

   You will see: the start-up screen described under [Running the Script](#running-the-script).

TeknoParrot Manager does not install TeknoParrot.

Install TeknoParrot and the extra programs it needs (its prerequisite runtimes) first, using [Start Here](docs/START-HERE.md).

Optional tools (ReShade, dgVoodoo2) are set up separately. See their sections below.

---

## Running the Script

**Option A -- Double-click launcher (easiest):**

```
TeknoParrot-Manager.bat
```

What happens at start-up:

1. On a first run, it looks in common places for `TeknoParrotUi.exe` before asking you to type a path.

   You will see: the places it found, numbered, if it finds more than one install. Type the number to pick one.

   If it finds none, it asks `Type the path of your TeknoParrot folder, the one with TeknoParrotUi.exe in it, or Q to quit (or type B to browse)`. Type the folder, type `B` to browse, or type `Q` to quit. Nothing is changed if you quit.

   If you close the browse window without choosing a folder, you see `No folder was chosen. Type the path again, or type B to browse again.` and the question comes back.

   If the folder is not right, you see `That folder does not exist. Check the spelling, or type B to browse.` or `TeknoParrotUi.exe is not in that folder. Pick the folder that has TeknoParrotUi.exe in it.` The question comes back each time.

2. Any time you are asked for a file or folder path, you can type `B` instead.

   You will see: a Windows browse window where you pick the folder with the mouse. Typing the path directly still works.

3. On later runs, it finds your saved settings.

   You will see: `TeknoParrot Manager found your saved settings.` and then the question `Use these settings? (Y/N, D = show them)`.

   Next: type **Y** to keep them. You will see: `Using your saved settings.`

   Type **N** to answer the first-time questions again.

   Type **D** to list your saved settings, then be asked the same question again.

### More detail: Running the Script

**Tester checkout entry point -- convenience launcher:**

```
Sync-And-Run.bat
```

This launcher is for testers who work from a copy of the source repository. It is not part of the release ZIP. Use `TeknoParrot-Manager.bat` instead.

**Advanced users -- direct PowerShell (not needed for the normal workflow):**

```powershell
cd "C:\path\to\TeknoParrot Manager"
.\TeknoParrot-Manager.ps1
```

If Windows blocks an advanced direct launch, use the one-session command below.
Most users should double-click `TeknoParrot-Manager.bat` instead:

```powershell
powershell -ExecutionPolicy Bypass -File .\TeknoParrot-Manager.ps1
```

If several installs are found on first run, they are listed numbered for easy picking.

The saved-settings question is asked only on an interactive start. A first run has no saved settings, so it shows the welcome screen instead.

## Workflow status

During multi-step work, TeknoParrot Manager shows a `TeknoParrot Manager status` area. It is written to be easy to read for beginners.

It shows:

- The current action.
- Recent completed work.
- The next step.
- Whether it needs anything from you.

Failures stay visible until you acknowledge them.

The status uses real workflow steps, not invented percentages.

Normal output stays plain-English first.

Technical paths and exception details are kept in the separate Details view, the log, or the support package.

On result screens that offer it, press **D** to open the Details. It shows the full technical information. The same information is also kept in the log.

When a failure has recovery information, the status action line names the concrete Retry and Stop choices and their remediation. It does not show a plain acknowledgement alone.

### More detail: Workflow status

The status area adapts to a resized PowerShell window.

- It clears only its own known area.
- It truncates safely in narrow windows.
- It falls back to ordinary status lines when the console cannot safely reserve a footer.

Redirected, unattended, and certification runs keep structured status events. They do not write cursor controls or cosmetic footer output.

## Progress bars

Long steps show a one-line progress bar.

Each menu workflow runs inside a single bar. The steps inside it only change the stage text and the count, for example
`Scanning GameProfiles` with the count `3/40` next to it.

- **The count is finished work.** `3/40` means three items are done, not that
  the third is in progress. The bar advances after an item completes, so it can
  look one step behind while a slow item runs. A bar that closes after a
  successful run shows the real finished count.

- **No invented numbers.** When TeknoParrot Manager cannot know the total in advance, the bar
  moves without a count or percentage.

Read the message printed after the step. That message is the real outcome. The bar only shows activity and finished counts.

### More detail: Progress bars

- **Closing state.** A workflow's bar closes from that workflow's own result:
  success, no-op, canceled, or error. A step that counts items and reports nothing for 60
  seconds is marked `Stalled` the next time it updates. A step that is one long
  installer with no item count (for example the PostgreSQL install) shows "still working"
  instead. A wait on one silent call shows "still working" too: a PostgreSQL tool, a web request,
  the PostgreSQL service, or the administrator window. That is normal and is not a stall. A rollback
  or a scan that failed or only partly worked ends as failed, never green. A finished step with no
  known size is a full bar. The empty part of a bar is drawn as tiny dots (a quiet background), not dotted blocks.

- **Verification is its own stage where TeknoParrot Manager has one.** The commit step of a
  file promotion and the BepInEx post-promotion validation appear as separate
  stages, so a full copy bar is not a verified result.

- **Redirected output.** When output is redirected, TeknoParrot Manager writes plain lines when
  the stage changes, at each 10% of a known total, every 5 seconds, and when
  the step closes.

Limits: the bar shows activity and finished counts; the result message printed
after the step is the outcome to read.

Some scanning steps that stop early on an
error still print a closing line marked `FINAL` with a finished count below the
total, so read the message, not the bar alone.

Not every workflow splits its
verification into a separate stage yet. For example, PostgreSQL setup and
recovery and some other file transactions report their steps on one bar.

A very narrow window truncates the line.

---

## Modes

The main menu repeats. After each mode finishes, you come back to the menu.

Type a number from 1 to 17 and press Enter.

Modes 1 and 2 offer a preview/dry-run option first (a practice run that changes nothing). See [Preview / Dry-Run Mode](#preview--dry-run-mode).

| #                                                             | Mode                           | What it does                                                                                                                                                                                                  |
| ------------------------------------------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Library Management**                                        |                                |                                                                                                                                                                                                               |
| 1                                                             | **AutoSync**                   | Extract (unpack) your game ZIPs, then register the games (add them to TeknoParrot)                                                                                                                           |
| 2                                                             | **Register only**              | Register games you already extracted                                                                                                                                                                          |
| 3                                                             | **Propagate Controls**         | Copy controls from a game you set up to games of the same type, without going through AutoSync/Register first                                                                                                |
| **Game Enhancements** (optional -- not every game needs them) |                                |                                                                                                                                                                                                               |
| 4                                                             | **Crosshair setup**            | Pick custom crosshairs and copy them to lightgun games                                                                                                                                                        |
| 5                                                             | **ReShade setup**              | Install post-processing shaders (visual filters: sharper image, CRT-style scanlines, borders). Change or undo your ReShade look for all games or one game. Turn off TeknoParrot's own CRT effect if you want |
| 6                                                             | **dgVoodoo2 setup**            | Fix some old DX8, DirectDraw, and Glide game crashes or black screens                                                                                                                                         |
| 7                                                             | **GPU fix setup**              | Apply the AMD / NVIDIA / Intel vendor fix for your graphics card to all games                                                                                                                                 |
| 8                                                             | **Force feedback (FFB) setup** | Wheel or stick rumble. Covers FFB Blaster (membership) + a free third-party plugin                                                                                                                            |
| 9 | **BepInEx setup** | BepInEx is an add-on some games use. TeknoParrot Manager can install or update it after you approve. Unsafe folders and failed downloads make no changes |
| 10                                                            | **Region setup**               | Pick the country your games start in (like USA or Europe). TeknoParrot Manager shows the games that offer it, lets you choose all or some of them, asks you to confirm, saves a backup, then changes them. You can also put games back to Auto. |
| **Game Requirements** (only for some games)                   |                                |                                                                                                                                                                                                               |
| 11                                                            | **Postgres setup**             | Installs/configures the local PostgreSQL database some Incredible Technologies games need (Golden Tee Live, Power Putt Live, Silver Strike Bowling Live, Target Toss Pro, Orange County Choppers Pinball). Ends with a short result screen; press D for details |
| 12                                                            | **Required game patches**      | Find, check, back up, install, verify, and undo required fixes for supported exact game builds using your local ZIPs                                                                                          |
| **Maintenance and Recovery**                                  |                                |                                                                                                                                                                                                               |
| 13                                                            | **Library health check**       | Reports registered/broken/unregistered games plus GPU fix / FFB Blaster / dgVoodoo2 and ReShade/BepInEx counts, without changing anything. Any repair it suggests is a separate choice that you confirm first |
| 14                                                            | **Restore backup**             | Put back a saved copy of TeknoParrot's saved game settings folder (UserProfiles), Postgres, or LaunchBox, or use Reset and Restore. Choice 5 rebuilds one game folder from its ZIP and keeps your old folder. Lists show the newest first. Invalid numbers ask again |
| **Application**                                               |                                |                                                                                                                                                                                                               |
| 15                                                            | **Check for Updates**          | You can start it yourself, and TeknoParrot Manager also checks once when it starts (you can turn that off). It checks the latest GitHub release. Nothing is downloaded or changed unless you answer Y; if you do, it saves a backup first. A release made of several files is refused with nothing changed |
| 16                                                            | **Create Support Package**     | Gathers safe information about TeknoParrot Manager, TeknoParrot, and your games into one ZIP to send when asking for help                                                                                  |
| 17                                                            | **Exit**                       | Quit the script                                                                                                                                                                                               |

### Result screens: the D key

Some screens show a short result first. The technical details stay hidden so the screen is easy to read.

To see the details:

1. Look for a line such as `[D] Details` or "Press D for details".
2. Type D and press Enter. You will see the full technical information.
3. Next: follow the prompt on the screen to carry on.

The same technical information is also saved in the log. Keys are not case sensitive.

**After Postgres setup (menu 11)**

You will see:

- `PostgreSQL setup finished.`
- A count line, for example `Games set up: 3. Databases created: 1. Already set up: 2.`
- One short line per game. Games with the same result share one line.
- `Next: open TeknoParrot and start any game. Every game database was checked and is ready.`
- `[D] Show details` and the prompt `Press Enter to return to menu, or D for details`

Next: press Enter to go back to the main menu, or type D to see `Details` and then press Enter.

Every game database is tested before setup says it is ready: TeknoParrot Manager connects to it with the settings saved in the game's own profile and counts its tables.

If a game has no starting database file (`pg_backup`) and its database does not exist, setup cannot make that database ready. It leaves that game out (nothing is created or changed for it), sets up every other game, and names the left-out game on the result screen. The run is then shown as needing attention, not as a clean success. Put the game's `pg_backup` folder back, then run setup again.

If some games kept their own PostgreSQL password or settings, a yellow line says so. It ends with `Press D to see which.`

**Restore backup (menu 14)**

You will see a menu called Restore from Backup with four choices:

- `1) TeknoParrot UserProfiles backup`
- `2) Postgres database backup (only relevant if you've used the Postgres setup mode)`
- `3) LaunchBox library backup (verified current-state backup first)`
- `4) Reset and Restore: put back one game or all games from a restore point saved when TeknoParrot Manager started`
- `5) Rebuild one game from its ZIP: put one game folder back to exactly what its ZIP holds (your old folder is kept)`

Type 1, 2, 3, 4 or 5 and press Enter. Lists of saved copies show the newest first.

Type the number of the copy you want. Press Enter instead to cancel. The product asks you to confirm before it puts anything back.

**ReShade setup (menu 5)**

Type 5. Then choose S to set up or change your ReShade look, R to remove it, or U to undo ReShade changes.

You can change the look for all games or for one game. You can also undo the last ReShade change for one game or for all games.

If a game already uses TeknoParrot's own CRT look, the product asks if you want to keep it (K) or turn it off (T), so the picture does not look doubled.

When some games are left alone, the result screen offers A, S, B or D. Press D for details.

See [ReShade Visual Enhancements](#reshade-visual-enhancements) for the full steps.

### Required game patches

Menu 12 fixes a few specific games that are missing files or need a known fix.

- It only works for exact game versions (builds) that it knows about.
- It uses ZIP files you already have. It never downloads patch files.
- It saves a copy before it changes anything, so you can undo.
- If your game version is not covered, nothing is changed.

More help is in [Start Here: Required patches](docs/START-HERE.md#8-required-game-patches-menu-12).

**How to use it:**

1. Choose **12) Required game patches**. You will see four choices: **A**, **M**, **U** and **Q**. Next: use **A** (Automatic mode), the usual way.
2. **A** checks your registered games. Games with the same result share one line. You will see `Ready to install 14 patches for 1 game` and `Press Y to install, D for details, or Enter to cancel`.
3. Read the lines. Next: press **Y** once to install the fixes.
4. To put back only what TeknoParrot Manager changed, choose **U) Undo patches that TeknoParrot Manager installed**.

**Manual** install (**M**) also works. Each game is listed once with its patch count, for example `Hummer Extreme Edition (14 patches)`. Type the number of your game, then choose the folder where it is installed. You are asked for the folder once. Manual install does not register the game. TeknoParrot Manager tells you to register it and set up the controls afterward.

**Messages you may see:**

- `None of your registered games has a patch in this list. Nothing was changed.` No game you registered has a patch here. If a game is installed but not registered, choose **M**.
- `Nothing was installed. Fix the problem above, then try again.` A check stopped a fix. The reason is above this line in plain words. It is not shown when everything was already installed.
- `Already installed, nothing to do` The game already has the patch. You need to do nothing.

Press **D** at the last question to see the technical details: patch names, the exact reason, result codes, and the folder with your undo copy.

After a fix, still register the game and set up its controls. Then test it.

#### More detail: required game patches

**How Automatic mode checks**

- Automatic mode checks registered games with matching profiles and executable hashes.

- It verifies the required member in your local source ZIP.

- It checks installed prerequisites and target bytes.

- It then shows one plain-language list for a single confirmation.

- The same safe engine supports manual installation into an already-installed game folder, even when that game is not registered yet.

- Manual install does not register it; TeknoParrot Manager tells you to register it and configure controls afterward.

**What it covers**

- It covers known game builds only. A build that is not on the list is left alone.

- Each fix creates a missing file, or replaces one exact known file. A file with unknown contents is never overwritten.

- Some games have two fixes for different graphics cards (AMD and NVIDIA). TeknoParrot Manager picks one only when the evidence is clear. It works with an extra Windows display adapter. If you have two real graphics cards, you are asked once which one the game uses.

- It asks only for the ZIP of the game version you have. Patch ZIPs can be up to 512 MB and can be 7z or RAR files when 7-Zip is installed. Long folder paths work. Free space is checked first.

**Safety and readiness**

- Every patch backs up first, checks the written file, and keeps an undo record. **U) Undo** puts back only what TeknoParrot Manager installed. It accepts a path with a trailing backslash and ignores a game version you never installed.

- TeknoParrot Manager does not host or download patch files.

- Some games also need BepInEx or another setup step that this menu does not do. Registration, controls and launch settings are separate.

- Test through TeknoParrotUI and verify controls and gameplay before considering a game ready. Patch installation alone is not a readiness claim.

---

### Adaptive responsive menu

The menu changes how much text it shows to fit your window size.

- A large window shows the full descriptions listed above.
- A medium window shows a one-line description for each option.
- A narrow or short window shows labels only.

Menu numbers, what each option does, and how to choose one stay the same. Only the amount of description text changes.

At the menu prompt, press `H` for the help screen, `L` to open the log folder, or `Q` to quit.

You can resize the window at any time. The menu, progress bars and the ReShade chooser are drawn again for the new size.

#### More detail: adaptive menu

- The default-sized Windows Terminal layout is clamped to the compact readable mode when the host reports its backing buffer rather than the visible width.

- It keeps the title/version, options 1-17, and the prompt together without giant empty frame or repeated filler.

- A classic console window is maximized automatically on startup.

- Inside Windows Terminal (also when Windows opens a double-clicked `.bat` there) TeknoParrot Manager never resizes the window.

- The ReShade profile chooser is one of the screens drawn again when the window size changes.

---

## Library Health Check

Library Health Check looks over your games and tells you what it found.

It starts as a look-only check. The title says "Library Health Check (read-only)" and the report ends with "Read-only report complete." It changes nothing.

A broken saved path is a saved game location that points to a file or folder that is missing. They are listed by game name and count.

The check also has a **Game support** row. It says `OK` when nothing is missing, or `Needs attention` when some games need you: a game file is missing, a second game file (for example a CHD) is not chosen, or PostgreSQL settings are missing. Choose `D` to see, for each emulator, how many games are registered, have their game file, and have setup steps in your Game Notes file. The steps come from the copy of the Game Notes page that TeknoParrot Manager saved earlier; this check never goes online. The full per-game list is in [Game support](docs/GAME-SUPPORT.md).

**If it finds broken paths:**

1. You will see "Broken saved paths need repair before optional setup." and a line such as "2 games cannot be found at the saved path:" followed by the game names.
2. You will also see these choices. Next: type a letter and press Enter. Plain Enter picks B.

- `[R] Try automatic path repair`
- `[M] Let me pick the correct executable or folder manually`
- `[S] Search another game folder`
- `[D] Details`
- `[B] Back to main menu`

**To use automatic repair (R):**

1. Type R and press Enter. You will see "TeknoParrot Manager will search" your games folder "for matching executables." with `[Y] Search for repair candidates` and `[N] Cancel`.
2. Type Y and press Enter. You will see "Candidate paths found (no profile changes made):" with a "before" path and an "after" path for each game.
3. Check that the new paths look right. Next: type Y to choose `[Y] Apply only these reviewed candidates`, or N to choose `[N] Leave them unchanged`.
4. If you chose Y, you will see "Repair result:" with the number FIXED and STILL BROKEN, and a "Safety backup:" line.
5. Next: press Enter at "Press Enter to return to the main menu".

**If no safe candidate is found:**

1. You will see "No safe automatic candidates were found in this folder. Nothing was changed." and the saved executable name for each broken game.
2. If you have set up a ZIP source folder, you also see `[C] Re-copy/re-extract only these affected games from the configured source`.
3. You will also see `[S] Search another game folder` and `[B] Back to the main menu`. Next: type S, B or C and press Enter.

**To pick the file yourself (M):** you select the exact executable. TeknoParrot Manager never guesses.

**When no broken paths remain:**

You will see "No broken saved paths were found." Then the screen offers extra setup choices.

- `[P] Set up PostgreSQL for these games` (only when database-backed games need setup)
- `[5] ReShade`, `[6] dgVoodoo2`, `[7] GPU Fix`, `[8] Force Feedback`, and `[9] BepInEx`
- `[D] Details` shows counts and the path of the log file.
- `[B] Back to main menu` leaves the library unchanged.

Health Check never installs, deploys, or rewrites anything until you pick one of these actions.

**Game databases (PostgreSQL):** the check also looks at every game database. If one is missing, cannot be opened with the game's own settings, or has no tables, the PostgreSQL row says `Problem` and Details lists `Problem - <game>` for each one. Next: run Postgres setup (menu 11). It makes and checks those databases. The health check itself only looks and changes nothing.

**When it cannot look:** if the check cannot read something (the PostgreSQL service, game profiles, startup files, or a game on a drive that is not connected), it says `Could not check` and asks for your attention. It does not say OK. A damaged profile is named as one that could not be read, and it gets no path repair.

### More detail: Library Health Check

- Library Health Check begins with a read-only assessment; confirmed follow-up actions may write changes.

- It checks registered profile paths and optional coverage, then explicitly says that it did not change anything.

- Automatic repair first performs a dry-run candidate search and displays the exact proposed paths.

- The configured games folder is the default search root; `[S]` accepts only an existing, canonical, non-reparse folder outside the TeknoParrot root, TeknoParrot Manager program folder, and ZIP source folders.

- If no candidate is found, TeknoParrot Manager shows the saved executable paths and offers `[C]` to re-copy/re-extract only the affected profile codes from a configured source, or `[S]` to search another folder.

- TeknoParrot Manager asks again before applying the reviewed set, creates a complete `UserProfiles\FullBackup\HealthCheck_*` backup, and applies only that reviewed set.

- `[C]` re-enters AutoSync with an explicit whitelist of the broken profile codes, so its normal preview and fresh apply scan cannot broaden recovery into an all-games extraction.

- Manual repair requires you to select the exact executable and never guesses.

---

## Game Selection (AutoSync)

After you enter your folders, AutoSync hides games that are already on your disk. It then shows one combined list from all your sources.

If you also set up a supplementary library, both collections are merged into one list. Extra titles from it are marked `[+]`.

You will see something like this:

```
347 game(s) already extracted -- not shown.
136 game(s) available to extract (104 collection, 32 supplementary [+]).

A) All unextracted games (136)
L) Browse and select from list (136 games, A-Z)
S) Search by keyword
D) Done -- continue with selected queue
B) Back / cancel AutoSync selection
```

Choose one:

- **A** -- extract everything not already on disk. Fastest option for a full library.
- **L** -- a paged A-Z list, 20 at a time. Type numbers or ranges (`1,3,5-7`) to add games. `[+]` marks supplementary titles.
- **S** -- search by keyword. Type numbers or ranges to add matches.
- **D** -- continue with the games you have picked so far (the queue).
- **B** -- go back and cancel the AutoSync selection.

Commands inside the list (**L**): `N` next page, `P` previous, `B` back, `D` done.

Commands inside search (**S**): type `back` to return or `done` to finish.

You can mix Browse and Search to build a queue before pressing D. Games already in your queue are marked with `*`. During each extraction, a live progress bar shows the file count and percentage.

AutoSync is careful about what counts as already extracted. It only hides a game when a matching folder exists and is not empty.

It never deletes, renames, or moves folders. An empty matching folder counts as an unfinished extraction, so you can try again.

**When a game folder already exists:**

- If the ZIP did not change, AutoSync leaves the folder alone. Your saves and settings stay.
- If a changed ZIP replaces a folder, every file in the old folder that is extra or different from the ZIP (saves, settings, ReShade files) is copied first to `Backups\AutoSyncReplaced` inside the `TeknoParrotManager` folder in your TeknoParrot folder.
- If those files cannot be saved, or no Backups folder is set up, AutoSync changes nothing for that game. The old folder stays as it is, and the screen says the game was not updated.

### More detail: Game Selection

- Already-extracted detection is intentionally conservative.

- AutoSync and the extraction pickers share the same resolver.

- The order of checks is: exact and normalized folder names first, then RetroBat suffixes (`.teknoparrot`, `.parrot`, `.game`), known Raw Thrills short-name aliases, dat/profile identity, registered profile paths, and finally a high-confidence fuzzy match for harmless metadata differences such as year/date drift.

- The resolver never deletes, renames, or moves folders; it only hides a game from the extraction prompt when the matching folder exists and is non-empty.

- Empty matching folders are treated as incomplete extractions and can be retried.

---

## The Staging Folder

AutoSync unpacks games into a staging folder. This is the folder where your extracted games go.

On a new setup, TeknoParrot Manager suggests a safe folder next to your TeknoParrot location, for example <same-volume>\TeknoParrot Games, and shows it before asking.

1. Look at the suggested folder.
2. Press **Enter** to use it, or **B** to browse for a different folder.
3. Next: if the folder does not exist yet, TeknoParrot Manager creates it when a real AutoSync run begins. Preview/Dry Run does not create it.

Your original ZIPs stay in their source folders.

Rules:

- **Recommended: local drive** for best performance. Network drives are allowed but the script measures write speed and warns if throughput is insufficient for smooth extraction or gameplay.

- Must **not be inside or contain** the TeknoParrot folder
- Must **not overlap** the main or supplementary ZIP source folder
- Must **not be inside or contain** the TeknoParrot Manager program/package folder
- An invalid typed or browsed path is rejected before it is saved or used
- The script warns if the drive has less than ~1.5x the total ZIP size free

If TeknoParrot Manager cannot make a backup of your game settings (a backup folder or copy failure), a real AutoSync run stops before it extracts anything. There is no "continue anyway" choice, including for unattended runs.

**If an extraction is interrupted:**

1. You will see ACTION REQUIRED. TeknoParrot Manager keeps what it found (the incomplete-operation evidence).
2. Open Details.
3. Review the log, the source archive, the free space, and the retained paths.
4. Next: fix the cause, then try again.

Do not delete an `.extracting` marker just to make the warning disappear. Removing it does not verify the game files. Seek help if the safe recovery action is unclear.

---

## Registration

For each game folder, TeknoParrot Manager shows one of these results.

TeknoParrot keeps one small setup file, called a profile, for each game. "Registered" means TeknoParrot has a profile for the game.

| Result                      | Meaning                                                                                                                                                                                                                          |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Registered**              | A matching profile was found and the game now appears in TeknoParrot.                                                                                                                                                            |
| **Registered (fuzzy)**      | Many games share one exe name (e.g. `game.exe` for 80+ NESiCAxLive titles), but the folder name matched one specific profile with high confidence. Profile code and score shown -- spot-check these.                        |
| **Registered (dat)**        | The folder name matched a dat file entry (the dat is a list of known games). The dat's authoritative profile code and executable path are used. Covers shared-exe games, exe-less-matched folders (pcsx2x6, ELF-based), and slightly misnamed folders. |
| **Registered (code/fuzzy)** | Folder name matched a TeknoParrot profile code by Dice similarity. Used for games whose profile has an empty `ExecutableName` (BladeStrangers, LuigisMansion, etc.) -- the best available executable in the folder is selected.   |
| **Already set**             | A profile for this game already exists and is left exactly as-is.                                                                                                                                                                |
| **Register manually**       | Advanced TeknoParrotUI fallback when an ambiguous case is left unresolved; TeknoParrot Manager presents validated candidates first.                                                                                              |

After new games are registered, you are asked once which country they should start in. See [Region Setup](#region-setup). You can answer `0` to leave every game as it is.

---

## How Fuzzy Matching Works

Some game types use the same program file name for every game. On NESiCAxLive, every game uses `game.exe`. The name alone cannot tell the games apart.

So the script compares the **folder name** of each game with the name of every known game. It gives each pair a score. A higher score means a closer match.

**Example:**

```
Folder:  "Akai Katana Shin (2012)[Taito NESiCAxLive][TP]"
Profile: "AkaiKatanaShinNesica"

After normalization:
  Folder:  "akaikatanashin"
  Profile: "akaikatanashinnesica"

Dice score: ~0.85  -->  auto-registered
```

**Thresholds:**

| Score   | Action                                                                                             |
| ------- | -------------------------------------------------------------------------------------------------- |
| >= 0.72 | Auto-registered. Shown in cyan with score -- spot-check.                                           |
| >= 0.40 | Shown by TeknoParrot Manager for an explicit candidate choice; unresolved cases remain in ACTION REQUIRED. |
| < 0.40  | Flagged in ACTION REQUIRED with full candidate list only.                                          |

**Wrong match?**

1. Save a checked backup copy of that game's UserProfile XML file. Keep it outside UserProfiles. It holds your controls and settings.
2. Confirm the correct official profile and executable.
3. Next: use TeknoParrot Manager's validated candidate choice when it is offered. Or set the correct profile and GamePath in TeknoParrotUI.

Do not delete a profile just to retry matching.

### More detail: Fuzzy Matching

- The score is a Sorensen-Dice bigram similarity score between the folder name and each candidate profile code.

- **What is stripped during normalization:** square-bracket metadata, bare 4-digit years, ISO dates, decimal versions, region codes (JPN/USA/EUR/etc.), version strings with prefix (ver/rev/v).

- Meaningful names like `(Special Edition)` are kept intentionally.

- `forceArchetype` selects a control-propagation reference; it does not change registration matching.

---

## Dat File Integration

A dat file is a list of known games and their file names. It helps TeknoParrot Manager recognize games whose folder names are confusing.

During first-time setup, the script offers to configure the Eggman/RomVault dat.

1. You will see a question and three choices:

```
Optional: download the DAT index (a list of game names, no games)?
D = download it (default), or B = browse for a DAT file I already have
N = skip for now (it asks again next time)
Choice (D/B/N, default D)
```

2. Choose D to download it (the default), B if you already have the file, or N to skip it.
3. Next: setup carries on.

Both the collection dat and the supplementary dat are read directly from inside the ZIP. No extraction is needed. The supplementary dat takes priority for any game that appears in both (alternate versions that replace the collection version).

The dat solves three cases that would otherwise need manual work:

1. **Shared-executable games** (NESiCAxLive, etc.) -- the dat tells them apart instantly using the folder name
2. **Games with no profile match** (pcsx2x6, ELF-based Lindbergh) -- a second pass looks them up by normalized folder name
3. **Slightly misnamed folders** -- fuzzy scan of all dat entries

Games registered via the dat are shown as `Registered (dat)`. The log also says whether the match was exact (`dat/exact`) or by similarity (`dat/fuzzy`).

If you use the Eggman DAT ZIP, TeknoParrot Manager asks `Check for a newer Eggman dat release? (Y/N)` each time you start it by hand. Answer `N` to keep the ZIP you already have. Nothing is downloaded unless you answer `Y`.

### More detail: Dat File Integration

- Eggman recognition data is separate from TeknoParrotUI's `ParrotData.xml` and DAT/XML setting, and separate from both game ZIP contents and the local staging/install folder.

- On the normal first-run download path TeknoParrot Manager stores the ZIP under `%LOCALAPPDATA%\TeknoParrotManager\Eggman` without asking where to save it.

- Browse/import remains available for an existing local file.

- On a later explicit update, TeknoParrot Manager reuses a valid configured ZIP at its existing location without opening an alternate-location save dialog.

- If the current DAT is under the TeknoParrot root, TeknoParrot Manager will not overwrite it; it can offer the configured primary ZIP/source folder, including a reachable mapped/network folder such as `Z:\Source Collection`, as the explicit destination. The supplementary source is not selected automatically.

- Every destination supplied to the downloader is canonicalized, checked for protected/reparse/ambiguous paths, and revalidated immediately before write; if no safe external folder exists, TeknoParrot Manager explains how to correct the configuration instead of silently skipping.

- When the script downloads the Eggman/RomVault ZIP, it uses the shared hardened download pipeline also used for other live file downloads: BITS first, HttpClient fallback, and `Invoke-WebRequest` only as a last resort.

- Downloads go to a partial/temp file first, show readable progress with size/speed/ETA when available, log final method/size/elapsed/speed metrics, and only move into the cache/final path after completion validation.

- A third registration pass (independent of the dat) Dice-matches normalized folder names against normalized profile code names. This resolves games whose GameProfile has an empty `<ExecutableName>` -- they never enter the exe-name index and may not be in the dat either. Examples: BladeStrangers, LuigisMansion, MaiMaiGreen, PokkenTournament, ProjectDiva, SonicDashExtreme, HydroThunder.

- The script also tries to fetch the full list of `GameProfile` filenames from the `teknogods/TeknoParrotUI` GitHub repo at launch to resolve dat codes that don't exactly match a local template filename (e.g. `BladeArcusFromShining` -> `BladeArcus.xml`).

- When that online list is not available (the repository currently answers HTTP 404, and the same happens when you are offline), it uses your local `GameProfiles` folder instead. When it loads the list, TeknoParrot Manager prints which one it used.

---

## Control Propagation

Controls are the buttons, sticks and wheels you set up for a game.

Set up the controls for ONE game of each type in TeknoParrotUI. TeknoParrot Manager can then copy those controls to other games of the same type that have no controls yet.

**Good reference games to set up first:**

| Type               | Suggestions                                                 |
| ------------------ | ----------------------------------------------------------- |
| Fighting / buttons | Street Fighter III, BlazBlue, Tekken 7, Dead or Alive 5     |
| Driving            | Daytona Championship USA, Initial D, OutRun 2 SP, F-Zero AX |
| Lightgun           | House of the Dead 4, Aliens Extermination, Point Blank      |
| Trackball          | Golden Tee Live, Silver Strike Bowling, Target Toss Pro     |

**How to use it:**

1. In TeknoParrotUI, fully bind one game of each type -- buttons, axes, Test, Service, Coin, Start. ("Bind" means link each control to a button or axis on your device.)
2. Next: run this script again. Propagation runs automatically after registration.
3. Launch ONE updated game and test it before trusting the rest.

**How matching works:** each control is matched by what it does, so a steering axis is never copied onto a gun axis. Mixed device setups (e.g. Xbox stick + arcade buttons) copy across intact.

**What stays manual:** game-specific controls that do not exist in the reference game still need to be set by hand.

If a type has no usable example game, those games are skipped by design. Done means the copy run finished, not that every game's controls work. The summary counts the skips; Details and the log list the games and the reason. Add one game of this family with your own controls, then run this again. A failed save still ends as an error. If all games are skipped, the screen says no game was changed. If that is the only thing left to do, the end-of-run screen still shows the next step under "CONTROLS: ONE MORE STEP" and it is saved in the Action Items file, but it is not counted as something that went wrong.

If anything goes wrong, restore from the backup made at the start of the run.

### More detail: Control Propagation

- This is a bounded reference-copy aid, not universal controller or gun detection or complete shooter mapping.

---

## Propagate Controls (standalone menu option)

Mode 3 does only the control-copying step described above. You do not need to run AutoSync or Register first.

It does not extract or register any games.

Use it when your library is already registered and you just set up a new or updated reference game in TeknoParrotUI. Run it right away instead of sitting through a full AutoSync/Register pass.

You will see: `You have 2 games with their controls set up.` Then you see a preview of what would change. It ends with `Preview only. Nothing was saved.` After that comes the question `Copy controls from 2 games to your other games of the same type? (Y/N, D = details)`. Press **D** to see each example game and the settings that will be copied. Check them against your real hardware, then press **Y** or **N**. If you press **N**, nothing changes.

If you press **Y**, a saved copy of your game settings is made first, and its folder is shown. After the copy, you are asked `Undo these changes and put your game settings back as they were? (Y/N)`. Press **Y** to undo everything at once. You can also undo later with **14) Restore backup**.

### More detail: Propagate Controls

- Behavior is identical to the propagation step at the end of AutoSync/Register.

- It uses the same reference-game pool, one approval after reference review and the same hardware-check warnings.

- It has the same backup-before-write safety net (UserProfiles are backed up and the backup is checked before anything is changed), and the same results reporting. Unlike the step at the end of AutoSync/Register, mode 3 shows a preview first and offers a one-step undo after saving.

- This option is a thin entry point into that existing pipeline, not a different implementation of it.

- A `familyOverride` in `TeknoParrot-Manager.overrides.json` also applies to the games controls are copied from. A game set to `spinner` finds a reference game of that type.

---

## Device Survey

On first run (or when you ask), the script asks which controls you have: Xbox pad, arcade stick, trackball, spinner, wheel, lightgun, keyboard.

It then prints a plan that says which game to set up with which device.

It only reads. It changes nothing. If a controller is connected, it looks for it first. When it finds an Xbox-style controller, it asks one question (`Use the Xbox controller for all games?`) instead of seven.

---

## Crosshair Setup

Mode 4 copies custom P1/P2 crosshair cursor images to all registered lightgun games. You can also run it on its own at any time from the main menu.

**How to use it:**

1. TeknoParrot Manager opens its own preview window. You will see every valid design found in `Crosshairs\`: the 321 included designs plus any valid user-added PNGs.
2. Pick a design for Player 1 (P1). Click a design, or use Tab and Shift+Tab to focus one and press Enter or Space.
3. Pick a design for Player 2 (P2) the same way. The same design can be used for both players. The window closes after P2 is chosen.
4. Review the P1 and P2 choices in the TeknoParrot Manager console. Next: confirm. Images are copied to registered games only after you confirm.
5. Optionally set cursor-hide for all gun games (backs up profiles first).

**If the preview closes early or cannot open:**

1. Any selection already made is kept.
2. Type a number in the console for each missing player choice.
3. Pressing Esc, using the Close button, or waiting 45 seconds closes the preview and returns to number entry. No images are deployed until you confirm.
4. If the preview cannot open, enter both numbers in the console. TeknoParrot Manager still asks you to confirm before copying the selected images.

**Adding your own crosshairs:** drop any PNG into the `Crosshairs\` folder next to the script. No naming convention required, though numbering helps. TeknoParrot Manager checks each file's header (the first bytes that identify it as a PNG) before including it.

321 crosshair designs (000.png-320.png) are included. Source: [emuline.org](https://www.emuline.org/topic/3080-custom-crosshairs-emulators-loaders/)

### More detail: Crosshair Setup

**How TeknoParrot uses crosshairs:**

- **Standard games** -- `P1.png` + `P2.png` in the game's executable folder
- **ElfLdr2 games** -- shared pair in the ElfLdr2 loader folder (auto-detected)
- **Pcsx2x6 games** -- shared pair in `pcsx2x6\TeknoParrot\crosshairs\` (the official upstream location); under the current contract, `cursor_path` remains emulator-owned, so TeknoParrot Manager leaves it unchanged and reports existing values read-only when available.

---

## ReShade Visual Enhancements

ReShade is a free add-on that changes how a game looks.
For example, it can add scanlines like an old arcade screen.

It does not change the game's own data.
It is optional. Not every game needs it.

TeknoParrot Manager does not remove ReShade files that it did not install, or files that were changed.
Review those through the advanced troubleshooting path (see More detail at the end of this section).

### Set up ReShade step by step

You do this in the main menu, under "Game Enhancements (optional -- not every game needs them)".
The menu entry is called `ReShade setup`.
Its short text is "Visual filters: sharper image, CRT-style scanlines, borders."

1. At `Enter 1-17:` type `5` and press Enter.

   You will see: `ReShade Visual Enhancements Setup` and three choices.

   Next: press Enter to set up ReShade. Enter picks the default, S.

```text
  S) Set up ReShade visual enhancements
  R) Remove verified TeknoParrot Manager-managed ReShade files
  U) Undo ReShade changes
  Action (S/R/U, default S):
```

2. If ReShade has not been downloaded yet, you will see `ReShade 64-bit DLL not found.`

   A DLL is a small program file that ReShade needs. You see three choices:

```text
    D) Download automatically from reshade.me
    B) Browse for a file I already have
    N) Skip
  Choice (D/B/N)
```

   Next: type `D` and press Enter. Here D means Download, not Details.
   If you already have the file, type `B` instead. If you do not want ReShade now, type `N`.

3. You will see a short note that ReShade is ready to use.

   The note also says whether Windows could confirm who published the file.
   Windows often cannot confirm this for ReShade. That is normal.

   Next: read the note. You can choose D at the next prompt to see the technical facts.

4. You will see: `Choose how your game should look. Nothing will be changed until you confirm.`

   Below it is a numbered list of looks. A preview window may open too.

   Next: type the number of a look and press Enter. Pick 1 if you are unsure. 1 is `Original`, which changes nothing.

5. You will see: `Preview selection changed to: ` followed by the name of the look you picked.

   Next: type `U` and press Enter to use that look.
   If you have not picked a number yet, you see `Choose a numbered profile before using it.`

6. You will see: `Use the selected ReShade profile?`

   Below it: `[Y] Yes, use {FriendlyName}  [S] Custom preset  [B] Back`, then `Choice (default Y)`.
   Here {FriendlyName} is the name of the look you picked.

   Next: press Enter to say Yes. Use `S` only if you already have your own ReShade .ini preset file.

7. You will see: `Which games should get ReShade?` and `You can run setup again later to add or change individual games.`

```text
    A) All {n} registered game(s)
    L) Browse and select specific games
    Enter A or L:
```

   Next: type `A` for all your games, or `L` to pick games from a list.

8. If you picked `L`, you see a list of games with page numbers.

   You will see: `Enter number(s) to toggle (e.g. 1,3,5-7) | N=next | P=prev | A=all | D=done`.

   Next: type the numbers of your games, then type `D` (done) and press Enter.

9. If you picked more than one game, you see `You selected ...` and a question like `Apply {FriendlyName} to {M games}?`

```text
  [Y] Yes
  [S] Select games one by one
  [B] Back
  [D] Details
  Choice, default Y
```

   Next: press Enter to say Yes.
   Type `D` first if a line says `Press D to see why.` It explains which games will be left alone.

10. Sometimes you see a question about TeknoParrot's own CRT effect.

    Next: read the topic "Turning off TeknoParrot's own CRT effect" below.

11. You will see: `Installing ReShade into {N games}...` and then the result screen.

    Next: read the topic "After you choose: the result screen" below.

To stop at any point, choose `B`. You see `ReShade setup canceled. No files were changed.`
To skip ReShade at the look list, choose `N`. You see `ReShade setup skipped. No ReShade files were installed or changed.`

### Choose a look

Each look is called a profile on the screen.
A profile is a ready-made set of ReShade effects.

The list has 17 choices: `Original` plus 16 arcade looks.
`Original` is the untouched picture. It is not an effect.

The 16 looks are listed best first, in two groups: CRT Choices, then Main Catalog.
Each look has one line that says what it does in a game.
It also shows a rough cost: light, medium or heavy.

Cost means how hard the look works your PC.
Light is easy. Heavy needs a strong graphics card.
Cost is a guess, not a measurement.

Two looks that do the same kind of job are never stacked automatically.
For example, sharpeners, color strength and CRT looks are never combined for you.

The list looks like this on screen:

```text
[1] Original
    No visual processing.

CRT Choices
[2] Curved Arcade Monitor [CRT-Geom]
    Makes the game look like it is on a curved arcade cabinet monitor: bent screen edges, rounded corners, scanlines and a fine dot pattern. Cost: medium.
[3] Classic Arcade CRT [CRT Lottes]
    Makes the game look like a classic arcade CRT screen: visible scanlines and a soft shadow-mask pattern. Cost: heavy.
[4] Sharp Aperture Grille [CRT-Aperture]
    A sharp, bright Trinitron-style picture: fine red, green and blue stripes, clear scanlines and a light glow; the screen stays flat. Cost: medium.
[5] Balanced Flat CRT [CRT-Easymode]
    A balanced flat CRT look: clear scanlines and a gentle color mask with sharp edges and no screen curve. Cost: medium.
[6] Sharp Phosphor CRT [CRT-Hyllian]
    A sharp, vivid CRT look: crisp pixels, scanlines that fade between the lines and a fine phosphor dot pattern. Cost: medium.
[7] Arcade CRT Glow [CRT Lottes + ArcaneBloom]
    The classic arcade CRT look plus a soft glow around bright areas, like a bright cabinet screen. Cost: heavy.
[8] Detailed Arcade CRT [CRT-Royale]
    The most detailed CRT look, with a fine phosphor mask and scanlines; it needs a strong graphics card. Cost: heavy.
[9] Fast CRT [CRT-ZFast]
    Scanlines and a light mask for a CRT look that costs very little speed, so it also runs well on slower PCs. Cost: light.
[10] Lightweight CRT [CRT-Pi]
    Simple scanlines for a retro arcade look that also runs well on slower PCs. Cost: light.
[11] Scanline Glow [CRT-Pi + ArcaneBloom]
    Simple scanlines plus a soft glow around bright areas, at a lower cost than the classic CRT look. Cost: medium.
[12] Bright Scanlines [Levels + CRT-Pi]
    Simple scanlines with deeper blacks and brighter whites, so the picture stays bright behind the scanlines. Cost: light.

Main Catalog
[13] Arcade Glow [ArcaneBloom]
    A soft glow around bright lights and effects, like a bright arcade cabinet screen. Cost: medium.
[14] Crisp 3D [SMAA + Curves + Levels]
    Smooths jagged edges in 3D games and adds stronger contrast with deeper blacks. Cost: medium.
[15] Crisp 3D Glow [SMAA + Levels + ArcaneBloom]
    Smooths jagged edges in 3D games, deepens blacks and adds a soft glow around bright areas. Cost: medium.
[16] Balanced Contrast [Curves]
    Stronger contrast in the midtones, so a flat-looking game gets more depth. Cost: medium.
[17] Black/White Point Adjustment [Levels]
    Deeper blacks and brighter whites for games that look washed out or gray. Cost: light.

Choose: [1-17] Select profile  [U] Use selected profile  [N] Skip ReShade -- no changes  [R] Reopen preview
        [B] Back  [D] Details
```

A star (`*`) next to a number marks the look you have picked.
Under the list you see `Current selection:` and the name of that look.
Before you pick, it says `Current selection: none -- choose a profile in the preview or terminal`.

At the prompt `Choice` you can use these keys. Type the key and press Enter.

| Key | What happens |
| --- | --- |
| A number | Picks that look. You see `Preview selection changed to: ` and its name. You are asked again. |
| `U` | Uses the look you picked. |
| `N` | Skips ReShade. Nothing is installed or changed. |
| `R` | Opens the preview window again. |
| `B` | Goes back and cancels. Nothing is changed. |
| `D` | Shows more facts about the list and about every look. |

If you type something else, you see `Invalid choice. Use 1-{N}, U, N, R, B, or D.`

The preview window is a picture that shows roughly what a look will do.
It is a guess made from one sample picture. It is not the game running.
Pick a look in the window or in the list. Both stay in step.
The real result in your game may look a little different.

Nothing is written to your games when you pick a look.
Files change only after you press `U` and confirm.

### After you choose: the result screen

After the install, a result screen tells you what changed and what did not.
You do not need to understand every line.

If it worked, you see in green: `Done: {look} applied to {N games}.`
You also see: `To turn the effect on or off, start a game and press the Home key.`
If nothing changed, you see in yellow: `Nothing was changed.`

A red line starts with `Problem:`. It means some games could not be changed.
It says: `See the FAILED lines above, or the log.`

A yellow `Not changed:` line says why some games were left alone.
For example: `{N games} already {has|have} a ReShade that TeknoParrot Manager did not install.`
Another one: `It was left alone to protect your own setup.`

When undo copies are ready, you see: `Next: You can undo this in ReShade > Undo ReShade changes.`

**If every game was done and nothing needs a choice**, the screen ends with:

```text
  Press D for details, or Enter to return to the menu
```

Type `D` and press Enter for the full technical information.
Press Enter alone to go back to the main menu.

**If some games were left alone**, you see a list of keys, one per line.
Only the keys that apply are shown:

```text
[A] Replace {that game | those N games} with TeknoParrot Manager's ReShade (you choose the look again; a copy of the old files is saved, so you can undo it)
[S] Choose games one by one
[M] Open the Library Health Check to see which games could not be found
[B] Leave them as they are
[D] Details
  Press A, S, B or D:
```

The last line lists the keys that are shown, for example `Press A, S, M, B or D`.
The default is B. If you only press Enter, nothing is replaced.

| Key | What happens |
| --- | --- |
| `A` | Asks `Replace the old ReShade files in {that game\|those N games}? You will choose the look again. A copy of the old files is saved, so you can undo it. Press Y to replace them, or N to leave them. (Y/N)` |
| `S` | Goes back into ReShade setup so you can choose games one by one. After games that were not safe, the line reads `[S] Choose games one by one and try again`. |
| `M` | Opens the Library health check (main menu 13) so you can repair missing game paths. |
| `B` or Enter | Leaves the games as they are. Without protected games the line reads `[B] Back to the main menu`. |
| `D` | Shows the details, then asks again. |

If you answer `Y` to the question under `A`, you see:

- `Some games already have ReShade files.`
- `TeknoParrot Manager left them alone to protect your own setup.`
- `You chose to replace them with TeknoParrot Manager's ReShade.`
- `TeknoParrot Manager saves a copy of the old files first.`
- `To put them back later, use ReShade > Undo ReShade changes.`

If you answer `N`, you see `Nothing was replaced. No files were changed.`

For the Details key on result screens, the line says `[D] Details`.
Type `D` and press Enter. The result screen then shows the same facts again.
TeknoParrot Manager also writes the full information to its log.

### Turning off TeknoParrot's own CRT effect

TeknoParrot has its own CRT effect in some game settings.
If you add a ReShade CRT look on top, the picture can look doubled.

TeknoParrot Manager asks you about this only when a game you picked already has a CRT, SSAA or shader setting.
That setting lives in the game's TeknoParrot setup file.
By default it keeps TeknoParrot's setting as it is.

When the look you chose is a CRT look, and a game can be turned off, you see:

```text
  This game already uses TeknoParrot's own CRT look.
  Together with this ReShade look, it can look doubled.

  [K] Keep TeknoParrot's CRT look (default)
  [T] Turn it off for this game
  [D] Details
  Choice, default K
```

With several games, the first line reads `{N} of these games already use TeknoParrot's own CRT look.`
The `[T]` line then reads `[T] Turn it off for {N games}`.
If some games cannot be turned off, you also see `{n} of them cannot be turned off here. Press D to see why.`

| Key | What happens |
| --- | --- |
| `K` or Enter | Keeps TeknoParrot's CRT look. Nothing is changed in TeknoParrot. |
| `T` | Turns it off. You see `OK. It will be turned off only in games that get ReShade now.` and `A saved copy of your game profiles is made first.` |
| `D` | Shows details, then asks the question again. |

The turn-off happens game by game, right after ReShade is installed on that game.
Games that do not get ReShade in this run keep TeknoParrot's CRT look.

After `T`, the result says: `TeknoParrot's own CRT look was turned off for {N games}.`
Then you see: `Next: You can undo this in ReShade > Undo ReShade changes.`
You can also type `D` at `[D] Details, or press Enter to continue`.

If nothing was changed, you see `TeknoParrot's own CRT look was not changed.`

**If the look is not a CRT look, or nothing can be turned off**, you see a short notice instead:

```text
  This game uses TeknoParrot's own screen settings, such as a CRT look.
  TeknoParrot Manager keeps them as they are. A ReShade look can add to them.
  Press D for details, or Enter to continue
```

With several games you see `{N} of these games use TeknoParrot's own screen settings, such as a CRT look.` and `Press D at the next menu for details.`

To put TeknoParrot's own CRT look back, use `U` in the ReShade menu if an undo copy exists.
Or open `Restore backup` (main menu 14).
Removing ReShade later does not turn TeknoParrot's own CRT look back on.

### Change or undo your look

You can change or undo your ReShade look for all games, or for one game.
Each change makes a saved copy first, so you can undo it.

**Change the look for all games:**

1. Type `5` at the main menu and press Enter.

   You will see: the three choices S, R and U.

   Next: press Enter for S.

2. Pick the new look from the list.

   You will see: `Preview selection changed to: ` and its name.

   Next: type `U` and press Enter.

3. You will see: `Use the selected ReShade profile?`

   Next: press Enter to say Yes (`[Y]`).

4. You will see: `Which games should get ReShade?`

   Next: type `A` for all games and press Enter.

5. You will see: `You selected {N games}.` and `Apply {FriendlyName} to {M games}?`

   Next: press Enter to say Yes (`[Y] Yes`).

6. Some games may have been set up by TeknoParrot Manager before with a different look. Then you see:

```text
  [A] Change these TeknoParrot Manager-managed games to the selected profile
  [K] Keep their current profiles
  [S] Select games manually
  [D] Details
  [B] Back
  Choice, default A
```

   Next: press Enter to change them, or type `K` to keep their current looks.
   Type `D` to read: `A changes only TeknoParrot Manager-owned profiles; K leaves those game folders untouched.`

**Change the look for one game:**

1. Type `5` at the main menu and press Enter, then press Enter for S.

   You will see: the look list.

   Next: type the number of the new look, then type `U` and press Enter.

2. You will see: `Use the selected ReShade profile?`

   Next: press Enter to say Yes (`[Y]`).

3. You will see: `Which games should get ReShade?`

   Next: type `L` and press Enter.

4. You will see a list of games, with page numbers.

   Next: type the number of that game and press Enter. Then type `D` (done) and press Enter.

5. If that game had an earlier look, you may see `Reapply {look} for this game? (Y/N, default N)` or `Use remembered {look} for this game? (Y/N, default N)`.

   Next: type `Y` to use the earlier look, or press Enter to use the look you just picked.

6. You will see: `Installing ReShade into {N games}...` and then the result screen.

   Next: read the topic "After you choose: the result screen" above.

**Undo your ReShade look:**

1. Type `5` at the main menu and press Enter. Next: type `U` and press Enter.

   If there is nothing to undo, you see `There is nothing to undo right now.`
   You also see `TeknoParrot Manager saves a copy each time it changes the ReShade of a game.`
   Next: press Enter to return to the menu.

2. You will see: `Undo ReShade changes` and `TeknoParrot Manager changed the ReShade of these games. Newest first.`

   Each row looks like this: `3) Daytona USA - no ReShade -> Fast CRT, 2026-11-03 14:05`.
   A look is shown as the look name, `no ReShade`, or `its own ReShade`.

```text
[1-{k}] Undo one game
[A] Undo all ({N games})
[D] Details
[B] Back
Choice, default B
```

   Next: type a game's number to undo one game, or `A` to undo all of them.

3. To undo ONE game, you see a plain preview. It says `{Game} goes back from {after} to {before}.`

   Then you see `Any answer other than YES cancels, and nothing is changed.`
   Next: type `YES` and press Enter at `Type YES to undo it`. Anything else cancels.

4. To undo ALL games, you see `This undoes the last ReShade change of {N games}.`

   A game that changed since then is left as it is.
   You see `Any answer other than ALL cancels, and nothing is changed.`
   Next: type `ALL` and press Enter at `Type ALL to undo all of them`.

5. You will see: `ReShade changes were undone for {N games}.` and `Next: Start the game to check its look.`

   Next: press Enter at `[D] Details, or press Enter to continue`, or type `D` for the details.

If a game changed after TeknoParrot Manager changed it, you see `{Game} changed after TeknoParrot Manager changed it.`
You also see `To keep those later changes, nothing is undone.`
Press Enter to leave it as it is, or type `D` for details.

If nothing was undone, you see `Nothing was undone.`
If an undo did not finish, you see `Press D to see the files to check before you play.`

### Remove ReShade

Use this to take away the ReShade files that TeknoParrot Manager installed.
Games with ReShade files that TeknoParrot Manager did not install are left alone.

1. Type `5` at the main menu and press Enter.

   You will see the three choices S, R and U.
   Next: type `R` and press Enter.

2. You will see how many files can be removed, then a game list.

   The list contains only games with removable or protected ReShade findings.
   You also see: `Protected bundled, preinstalled, changed, and ambiguous files will be preserved.`
   Next: pick the games, as in the steps above.

3. You will see: `ReShade removal preview -- no changes have been made:` with `REMOVE` and `KEEP` rows.

   Next: read the rows. `REMOVE` files will go. `KEEP` files stay.

4. You will see: `Type REMOVE to back up and remove verified TeknoParrot Manager-owned files, or press Enter to cancel`

   Next: type `REMOVE` and press Enter to continue. Press Enter alone to cancel.

If you cancel at the chooser, the preview or the confirmation, every file stays unchanged.
If you do not need removal, you see `No ReShade games need review or safe removal.`
After removal you see `Next: You can undo this in ReShade > Undo ReShade changes.`

### Popular effects for arcade games

| Effect                  | What it does                                              |
| ----------------------- | --------------------------------------------------------- |
| LumaSharpen / CAS       | Removes the blurry look of upscaled games                 |
| CRT_Royale / CRT_Lottes | Adds classic CRT scanlines and curvature                  |
| Levels / Vibrance       | Restores vivid colors on modern monitors                 |
| Border                  | Adds decorative arcade cabinet artwork in black bar areas |

### Getting the ReShade files, updating and playing

**Setup:** ReShade works with 64-bit games. 32-bit games are skipped.
It needs one program file, `ReShade64.dll`. It is not part of the release ZIP.

When the 64-bit file is missing, TeknoParrot Manager can download the official installer from reshade.me and take the files out for you.
To use this, choose `D` when you are asked. See step 2 above.
If you cannot or would rather not download, use the advanced manual steps in More detail.

**In-game:** press **Home** to open the ReShade overlay.
Toggle effects with tick-boxes, adjust with sliders.
Settings save automatically to `ReShade.ini` in the game folder.

**No pop-ups at game start:** every `ReShade.ini` that TeknoParrot Manager writes turns off the welcome window, the FPS and clock counters and the on-screen messages (it sets `TutorialProgress=4` and sets `ShowClock`, `ShowFPS`, `ShowFrameTime`, `ShowScreenshotMessage` and `ShowPresetTransitionMessage` to `0` under `[OVERLAY]`). The key that opens ReShade still works. A short ReShade version banner may still show for a moment when the game starts. ReShade has no setting to hide it.

**Updating:** when a newer version is found, the current setup offers an automatic official download/update prompt.
Choose `Y` to download and verify the update, or `N` to keep the current version.
Declining does not update the DLLs. Manual replacement is an alternative, not the only update path.

**Signature check:** TeknoParrot Manager checks the official installer it downloads before it uses it.
Signatures on manually supplied DLLs are informational only.
A missing or invalid signature gives a warning but does not block the install.

**Library Health Check:** it reports, purely informationally, how many registered games have ReShade installed.
This is not flagged as something to fix, since it is a per-game cosmetic choice rather than a clear right answer.
Its result screen also offers direct optional setup actions.

### More detail

This part is for advanced users.
You do not need it to use ReShade.

**Removing and unowned files:** TeknoParrot Manager does not automatically remove unowned or changed ReShade hooks.
Review those files through the advanced troubleshooting path.

**Beginner visual profiles:** ReShade setup opens an optional non-modal comparison gallery with a profile drop-down and the existing view controls.
The terminal numbered chooser remains available.
Both inputs select the same profile and stay synchronized in real time.

A change made in the gallery while the terminal prompt is waiting updates the menu marker and the "Current selection" line in place.
Your partly typed choice is kept, and no new menu is printed.
`U` always returns the latest choice.

If the console cannot be updated safely (for example it was resized), a one-line announcement is printed instead.
While the prompt waits, you see `Preview selection changed to [{n}] {label}. Type U to use it.`
Typing is end-of-line only: the cursor always sits after what you have typed.
The terminal still works if the gallery is behind another window, closed, unavailable, or fails to open.
If the preview window cannot open, you see `ReShade visual gallery unavailable; choose a profile in the terminal.`

**The catalog and license evidence:** the catalog defines 25 effects.
The offered list is 17 profiles chosen for arcade play (Original plus 16 arcade looks), built from 12 of those effects.
**Original** is the untouched reference; it is not an effect.

An effect is offered only while its recorded license evidence is complete and current.
That means the pinned files matched upstream byte for byte.
Every in-file license notice or repository license copy was checked, and the include closure resolves.

All 25 effects are held to that same standard (an earlier approval is not license evidence).
An effect whose record is missing, stale or incomplete is withheld, with the specific reason listed in the review inventory.
The other 16 are listed best first in two groups -- CRT Choices, then Main Catalog.
Each says in one line what it does in a game and gives a rough cost (light, medium or heavy; an estimate, not a measurement).
Alternatives that do the same kind of job (sharpeners, color strength, CRT looks) are never stacked automatically.

**HDR:** no current profile needs HDR, so no **Actual HDR Setups Only** group is offered.
The HDR display check stays in TeknoParrot Manager.
Such a group would be shown only when Windows reports HDR-specific support (not just "advanced color", which is also true for wide-gamut SDR) for the display being evaluated and HDR is active there.

If HDR support is unknown, unidentified, stale or absent, the whole group is hidden.
With several displays and no known game display, every display must qualify.
Windows HDR being on does not show that a particular game renders HDR.
TeknoParrot Manager never changes a Windows HDR setting.

**Effects no longer in the beginner catalog:** Cartoon, Film Grain, Monochrome, Sepia Tone and Vignette are no longer part of the beginner catalog.
Neither are Smooth Edges, Clean & Sharp, Adaptive Clarity, Smooth Gradients, Vivid Arcade, Shadow & Midtone Balance, Exposure & Tint, Color Balance, Enhanced Arcade, Detail-Preserving Sharpen, Filmic Sharpen, Colorfulness, Fast Game Enhancement, HDR Highlight Mapping and HDR Black-Level Fix.

A saved choice or history entry that names one of them is reported as a custom/previous profile that is no longer offered.
It is never silently replaced or remapped to another profile.
Its installed files keep working and are not deleted (they stay removable).

**Gallery and terminal list:** choose a profile directly from the gallery drop-down or use its matching number in the terminal.
Either choice updates the same selection and preview.
The view buttons and 0-100 slider remain independent, and the slider is aligned to the displayed image.

Previews are labeled approximations on one bundled image, and every profile except Original shows a visible difference.
Edge smoothing (SMAA) is not visible on the still picture.
So the Crisp 3D and Crisp 3D Glow notes say the preview shows only their contrast, black/white and glow part.

The `D` key in the terminal list shows `About this list` and then `Profiles`.
Under each profile it shows `What it does:`, `Techniques:`, `Preview:` and `Cost:`.
The gallery and terminal list (press `D`) show the rough cost and the approved shader file and technique name for each profile.
The `D` list in the terminal shows this for each profile (some profiles also show a `Preview:` line):

```text
Original
    What it does: No visual processing.
    Techniques: (none; no ReShade techniques)
Curved Arcade Monitor [CRT-Geom]
    What it does: Makes the game look like it is on a curved arcade cabinet monitor: bent screen edges, rounded corners, scanlines and a fine dot pattern.
    Techniques: CRTGeom.fx / GeomCRT
    Cost: medium (rough estimate, not measured).
Classic Arcade CRT [CRT Lottes]
    What it does: Makes the game look like a classic arcade CRT screen: visible scanlines and a soft shadow-mask pattern.
    Techniques: CRT_Lottes.fx / CRT_Lottes
    Cost: heavy (rough estimate, not measured).
Sharp Aperture Grille [CRT-Aperture]
    What it does: A sharp, bright Trinitron-style picture: fine red, green and blue stripes, clear scanlines and a light glow; the screen stays flat.
    Techniques: CRTAperture.fx / ApertureCRT
    Cost: medium (rough estimate, not measured).
Balanced Flat CRT [CRT-Easymode]
    What it does: A balanced flat CRT look: clear scanlines and a gentle color mask with sharp edges and no screen curve.
    Techniques: CRTEasymode.fx / EasymodeCRT
    Cost: medium (rough estimate, not measured).
Sharp Phosphor CRT [CRT-Hyllian]
    What it does: A sharp, vivid CRT look: crisp pixels, scanlines that fade between the lines and a fine phosphor dot pattern.
    Techniques: CRTHyllian.fx / CRTHyllian
    Cost: medium (rough estimate, not measured).
Arcade CRT Glow [CRT Lottes + ArcaneBloom]
    What it does: The classic arcade CRT look plus a soft glow around bright areas, like a bright cabinet screen.
    Techniques: CRT_Lottes.fx / CRT_Lottes; ArcaneBloom.fx / ArcaneBloom
    Cost: heavy (rough estimate, not measured).
Detailed Arcade CRT [CRT-Royale]
    What it does: The most detailed CRT look, with a fine phosphor mask and scanlines; it needs a strong graphics card.
    Techniques: crt-royale.fx / CRT_Royale
    Cost: heavy (rough estimate, not measured).
Fast CRT [CRT-ZFast]
    What it does: Scanlines and a light mask for a CRT look that costs very little speed, so it also runs well on slower PCs.
    Techniques: zfast_crt.fx / CRTZFast
    Cost: light (rough estimate, not measured).
Lightweight CRT [CRT-Pi]
    What it does: Simple scanlines for a retro arcade look that also runs well on slower PCs.
    Techniques: CRTPi.fx / CRTPi
    Cost: light (rough estimate, not measured).
Scanline Glow [CRT-Pi + ArcaneBloom]
    What it does: Simple scanlines plus a soft glow around bright areas, at a lower cost than the classic CRT look.
    Techniques: CRTPi.fx / CRTPi; ArcaneBloom.fx / ArcaneBloom
    Cost: medium (rough estimate, not measured).
Bright Scanlines [Levels + CRT-Pi]
    What it does: Simple scanlines with deeper blacks and brighter whites, so the picture stays bright behind the scanlines.
    Techniques: Levels.fx / Levels; CRTPi.fx / CRTPi
    Cost: light (rough estimate, not measured).
Arcade Glow [ArcaneBloom]
    What it does: A soft glow around bright lights and effects, like a bright arcade cabinet screen.
    Techniques: ArcaneBloom.fx / ArcaneBloom
    Cost: medium (rough estimate, not measured).
Crisp 3D [SMAA + Curves + Levels]
    What it does: Smooths jagged edges in 3D games and adds stronger contrast with deeper blacks.
    Techniques: SMAA.fx / SMAA; Curves.fx / Curves; Levels.fx / Levels
    Cost: medium (rough estimate, not measured).
Crisp 3D Glow [SMAA + Levels + ArcaneBloom]
    What it does: Smooths jagged edges in 3D games, deepens blacks and adds a soft glow around bright areas.
    Techniques: SMAA.fx / SMAA; Levels.fx / Levels; ArcaneBloom.fx / ArcaneBloom
    Cost: medium (rough estimate, not measured).
Balanced Contrast [Curves]
    What it does: Stronger contrast in the midtones, so a flat-looking game gets more depth.
    Techniques: Curves.fx / Curves
    Cost: medium (rough estimate, not measured).
Black/White Point Adjustment [Levels]
    What it does: Deeper blacks and brighter whites for games that look washed out or gray.
    Techniques: Levels.fx / Levels
    Cost: light (rough estimate, not measured).
```

**Shader sources:** shader sources are live-fetched from pinned upstream commits and integrity-checked (SHA-256 and byte length) during deployment.
They are not bundled in the release ZIP.
Each effect's license text and a TeknoParrot Manager notice are written next to its files.
Performance is not measured, so none is claimed; the light/medium/heavy cost words are rough estimates.

**The CRT looks added for issue #383:** Curved Arcade Monitor, Sharp Aperture Grille, Balanced Flat CRT, Sharp Phosphor CRT and Fast CRT also write a short preset with the values the shader needs.
That preset has a 640x480 picture size (the usual arcade picture size, set equal for screen and frame as the shaders ask).
It also has the mask, scanline and brightness values of that look.

Curved Arcade Monitor turns the interlace switch to 5 so a 480-line picture does not flicker.
Balanced Flat CRT raises its scanline cut-off so its scanlines stay on at 480 lines.
The preview pictures are TeknoParrot Manager approximations, not the shaders running.
The cost words are rough unmeasured estimates, and how a look appears on a real game has not been measured.

**Not offered, on purpose:**

- CRT-Guest-Advanced and the Sony CRT shader candidate (no verifiable pinned source in the approved repositories).
- A vertical-mask (tate) CRT look (no verifiable shader).
- FXAA (the SweetFX copy at the pinned commit is only a 127-byte placeholder, not a usable shader).
- LUT color grading (the lut.png at the pinned commit is a 273-byte neutral table, so a look built on it would change nothing).

MAMEPostProc (ColorMAME) was dropped for three reasons.
Its saved file has no license notice or copyright line, its port repository has no license file, and it adds a refresh-roll flicker bar.
scanlines-abs was dropped because no look needs it (CRT-Pi already gives the cheapest scanlines).

**How the preview and `U` work:** `U` in the terminal is the only path toward deployment.
`B` cancels without changes, `D` shows descriptions, and `R` reopens the optional gallery without taking terminal input away from the user.
The gallery uses a safe deterministic comparison based on the bundled `PreviewAssets\ReShadePreviews\TPM-preview-landscape.png` reference image.
It does not run the game or execute ReShade shaders.

TeknoParrot Manager validates the image before use and records its identity, version, and SHA-256 in preview cache metadata.
`Before` is the untouched baseline, and `After` is a TeknoParrot Manager preview approximation of the selected profile.
`Split` shows baseline on the left and the approximation on the right.
The slider moves that boundary from 0 (all processed) to 100 (all baseline). The actual in-game result may vary.

Choosing a profile in either input does not write files.
Deployment remains behind terminal `U` and the existing explicit confirmation.
After the chooser returns, the preview closes automatically.
If rendering or display is unavailable, terminal selection remains available.

**The result after deployment:** the result states what changed and what did not change.
It separates newly installed or updated TeknoParrot Manager-managed files, adopted replacements, protected unchanged files, missing saved paths, unsafe or malformed paths or ownership metadata, unsupported architecture, and errors.

Unsafe or malformed games include direct details and the next action: repair or review the listed issue, then rerun ReShade setup with `Select`.
Missing saved paths include the game name; use the main-menu path-repair tool and run ReShade setup again.
Before deployment, TeknoParrot Manager reports ready, protected, missing-executable, and unsafe/malformed preflight counts.
Protected existing files remain unchanged unless you explicitly choose `Adopt` and confirm.
Adopted installations are counted separately from ordinary installs.

The `D` view of the apply-scope menu shows `Profile: {FriendlyName} -- {description}` and a preflight line.
That line reads `ReShade preflight: {n} ready, {n} protected, {n} missing executable, {n} unsafe or malformed.`

**Native CRT, SSAA and shader settings:** TeknoParrot Manager reads native TeknoParrot CRT, SSAA, shader, scanline, and post-process settings without changing them.
If enabled settings are detected, the result warns that the selected ReShade effect may stack with the native display effect.
The result pauses before the optional dgVoodoo2 step so these outcomes can be reviewed.

The `D` view of the CRT question shows a note: `TeknoParrot Manager keeps these settings as they are, unless you turn the CRT look off. A ReShade CRT or shader look can add to them.`
For each game it shows `Settings:`, a `ReShade:` line and a `Turn off:` line.
The `Turn off:` line says either that option T sets a field to a value, or that it cannot be turned off here (the game profile has no off value for it), or that it is not changed (ReShade is not installed for this game).

It also shows a block `About turning it off`:

- `It changes: only that one setting`
- `Where: only in games that get ReShade in this run`
- `First: a saved copy of your game profiles is made`
- `Undo: use Restore backup; removing ReShade later does not turn it back on`

An unattended run (no questions asked) always keeps TeknoParrot's setting.
In the log you may see `ReShade: the user kept TeknoParrot's own CRT effect.`
If the game's profile is damaged, the result says `Next: Open Restore backup from the main menu and pick the newest saved copy.`

**Advisory metadata:** profile and effect catalog metadata is advisory until measured evidence exists.
No profile is marked recommended or `VALIDATED_SINGLE` without that evidence.
Pinned hashes establish catalog integrity, not performance validation.

Multi-monitor suitability is read-only and advisory.
It uses caller-supplied evidence and treats duplicate target IDs as ambiguous.
It does not separately label `EXTENDED` arrangements or acquire Windows display topology itself.

**Remembered profiles and restore:** TeknoParrot Manager stores per-game profile selection and a bounded history using stable profile IDs and approved effect SHA-256 values.
When you set up one game at a time, it asks whether to reapply the previous trusted profile (`R) Reapply previous trusted profile for {game}: {look}`).
It can also offer a remembered one (`Remembered for {game}: {look}`).

Remembered selections are offered separately and require explicit confirmation.
TeknoParrot Manager never restores automatically.
A restore is accepted only when the current profile definition, ordered effects, pinned hashes, and intensity variant still match.
Missing, corrupt, stale, or unsupported history falls back to a friendly fresh-selection path and never copies historical file paths.

**Transactional safety:** DLL, generated preset, and approved effect files are staged and promoted together.
Before replacement, every existing destination must be recorded as TeknoParrot Manager-managed in that game's ownership manifest.
Unknown or user-owned files cause a collision and remain untouched.
Earlier TeknoParrot Manager-managed files are retained when changing profiles; TeknoParrot Manager does not silently delete them.

**How removal checks files:** the `R` choice sits in the ReShade tools prompt of mode 5.
TeknoParrot Manager scans registered games and shows only games with removable or reviewable ReShade findings in the existing filtered chooser.
The preview lists verified TeknoParrot Manager-owned files that can be removed and protected files that will be kept.
The counts are shown first, for example `verified TPM-owned files: {n}`.

TeknoParrot Manager removes only files whose ownership manifest says they are TeknoParrot Manager-managed, whose paths resolve inside the current ReShade target folder, and whose live SHA-256 still matches the recorded value.
Immediately before each backup and deletion, it re-reads the profile metadata, re-resolves the target, and rechecks each destination as an existing canonical non-reparse leaf inside that target.
A verified backup is created before deletion; manifest updates roll back with the files if the commit fails.

Bundled/preinstalled, unowned, ambiguous, changed, malformed, and out-of-target files are protected by default.
Game executables, TeknoParrot profiles, LaunchBox data and other frontend data are never removal targets.
The final report separates removed effects, already-clean games, missing saved paths, protected bundled/preinstalled files, protected ambiguous/needs-review files, changed hashes, malformed metadata, safe rollbacks, and failures.

**Undo details:** the `D` key in the undo list shows these labels for a game: `Change:`, `Look before:`, `Look now:`, `Changed on:`, `CRT setting:`, `Files saved:`, `Files the change added:` and `Saved copy:`.
It also shows a note: `Undo puts files back only while they are exactly as TeknoParrot Manager left them.`
The undo list shows 4 games per page, newest first; `[M] More games` shows the next page.

The undo preview says what happens in plain words:

- `The ReShade files TeknoParrot Manager added are removed.`
- `Its own ReShade files are put back exactly as they were.`
- `Its ReShade files are put back exactly as they were.`
- `TeknoParrot's own CRT look is turned back on.`

**Result screen details:** the `D` view of the ReShade result screen shows the note `Press A to replace protected ReShade files. TeknoParrot Manager asks you to confirm before it changes anything.`
It then shows these blocks: `What happened` (`Summary:`, `Changed:`, `Protected existing:`, `Missing paths:`, `Failed:`, `Unsafe/malformed:`), `What TeknoParrot Manager did`, one block per protected game (`What happened:`, `Reason code:`, `Technical detail:`), `Counts and notes from the run`, `Notes for each game`, and `Undo` (`Saved for undo:`, `Where: ReShade > Undo ReShade changes`).

**Automatic download and the installer check:** DLLs are never bundled in the release ZIP.
When the required 64-bit DLL is missing, TeknoParrot Manager can automatically download the official installer from reshade.me and extract the DLLs.
Existing or user-supplied DLL paths are used as supplied instead of being freshly fetched.
If automatic acquisition is unavailable or you prefer not to use it, the manual steps below are an advanced fallback.

For automatic acquisition, choose D when prompted.
TeknoParrot Manager checks the installer's Authenticode status and signer thumbprint against ReShade's pinned trust policy before trusting it.
The log records the authoritative installer URL, filename/version, computed SHA-256, transfer method/size/time/speed, and the Authenticode signer/subject, status, thumbprint, and final trust result.
The SHA-256 is an audit hash; the trust gate is the pinned thumbprint plus accepted status, not a published ReShade digest.

Signatures: TeknoParrot Manager validates the official installer it downloads against pinned Authenticode status and certificate values before extraction.
Signatures on manually supplied DLLs are informational only.
A missing or invalid signature triggers a warning but does not block deployment.

**Where the DLLs live:** the script looks for DLLs in `<TeknoParrotRoot>\TeknoParrotManager\Assets\ReShade\`. A `ReShade\` folder next to the script is also found, and the startup tidy-up moves it into the managed folder:

- `ReShade64.dll` -- for 64-bit games (required)

**Advanced manual fallback:**

1. Download the free installer from [reshade.me](https://reshade.me)
2. Run it -- point it at any 64-bit TeknoParrot game exe. It creates a DLL in that folder.
3. Copy that DLL to `Assets\ReShade\ReShade64.dll` (under `<TeknoParrotRoot>\TeknoParrotManager\`)
4. Run "ReShade setup" from the main menu, or answer Y when prompted after a normal run

---

## dgVoodoo2 Legacy Compatibility

Some older arcade games were made for very old graphics systems (DirectX 8, DirectDraw, or the 3dfx Glide API).

On modern PCs these old systems can cause crashes, black screens, or missing shapes in the picture.

dgVoodoo2 is a free helper. It translates those old graphics calls into DirectX 11/12 commands that a modern PC understands.

**Only use this if a game crashes or shows a black screen on first launch.** Games that run correctly do not need it.

### Running dgVoodoo2 setup (automatic, recommended)

1. At the main menu, choose dgVoodoo2 setup. You will see: a list of the games that need it, with auto-detected games first. Next: pick the games.
2. If asked where the dgVoodoo2 files come from, press `D`. You will see: TeknoParrot Manager downloading the latest release from the official GitHub page. Next: wait for it to finish.
3. Install to all the listed games at once, or pick them one by one.
4. Read the result screen. Next: follow its advice, then start the game once to check it.

If you answer Y when asked after a normal run, you get the same setup.

TeknoParrot Manager never puts the dgVoodoo2 files in the release ZIP. It uses a dgVoodoo2 folder you already have first, and downloads the files from the official source only when it finds none.

### What the result screen tells you

After a successful run the beginner result screen says `dgVoodoo2 setup finished`.

It names each installed game and the old graphics system found (for example `Glide2x`).

It explains that older DirectX/Glide calls may not display correctly on modern Windows. It also says what to try next.

Existing dgVoodoo2 DLL files that are already in a game folder are not removed or replaced. This includes files that are not owned by TeknoParrot Manager or that were changed. A DLL is added only when it is missing.

One file is different. If you put a per-game config file named `<ProfileCode>.conf` in `<TeknoParrotRoot>\TeknoParrotManager\Assets\dgVoodoo2Presets\`, TeknoParrot Manager replaces that game's `dgVoodoo.conf` with it. The screen tells you this before you choose games, and the result screen says for how many games `dgVoodoo.conf` was replaced. Keep your own copy of any `dgVoodoo.conf` you want to keep before you run setup. TeknoParrot Manager keeps a checked copy only so it can roll back if the setup fails part way. It does not offer an undo for a finished run.

The global `dgVoodoo.conf` works the other way round. If your `dgVoodoo2\` folder holds a `dgVoodoo.conf`, TeknoParrot Manager adds a copy of it to every game you pick whose folder has no `dgVoodoo.conf` yet. A game folder that already has one keeps it. The screen tells you this before you choose games. To undo it for a game, delete the `dgVoodoo.conf` in that game's folder (the folder with the game's exe). That folder had none before, so nothing of yours is lost. If you do not want it added to more games, take `dgVoodoo.conf` out of your `dgVoodoo2\` folder before you run setup.

You can press these keys on the result screen:

- Press `D` for technical deployment and skip details.
- Press `O` for support-package and log guidance.

If the result is partial or blocked, counts of unavailable devices include reconnect guidance.

Library Health Check is offered only when a saved game path is missing.

### More detail

**What it fixes:**

| Import        | DLLs deployed              |
| ------------- | -------------------------- |
| `d3d8.dll`    | `D3D8.dll` + `D3DImm.dll`  |
| `ddraw.dll`   | `DDraw.dll` + `D3DImm.dll` |
| `glide2x.dll` | `Glide2x.dll`              |
| `glide3x.dll` | `Glide3x.dll`              |

DLLs are never bundled in the release ZIP; TeknoParrot Manager uses a dgVoodoo2 folder you already have first, and fetches from the official source only when there is none.

**Automatic download, in technical terms:** run dgVoodoo2 setup from the main menu and choose D. TeknoParrot Manager downloads the latest release directly from the official dege-diosg/dgVoodoo2 GitHub Releases channel. It verifies the ZIP SHA-256 against the GitHub asset digest when available. It extracts only the files it needs. The log records the GitHub source, filename/version, computed SHA-256, and transfer metrics. A digest mismatch is logged and fails closed.

**Manual:**

1. Download dgVoodoo2 from [dege.freeweb.hu](https://dege.freeweb.hu/dgVoodoo2/dgVoodoo2/)
2. Create a `dgVoodoo2\` folder in `<TeknoParrotRoot>\TeknoParrotManager\Assets\` (TeknoParrot Manager uses that folder first; a `dgVoodoo2\` folder next to this script also works when the Assets one holds no dgVoodoo2 files) and copy in:
   - From `MS\x86\`: `D3D8.dll`, `DDraw.dll`, `D3DImm.dll`
   - From `3Dfx\x86\`: `Glide2x.dll`, `Glide3x.dll`
   - From the ZIP root: `dgVoodoo.conf` (optional; TeknoParrot Manager adds a copy to each game you pick that has no `dgVoodoo.conf` yet)
3. Run "dgVoodoo2 setup" from the main menu, or answer Y when prompted after a normal run

The wizard scans every registered game exe for legacy API imports and shows auto-detected games first. You can install to all at once or pick individually.

---

## GPU Compatibility Fixes

A GPU fix changes some settings so a game runs better on your graphics card (AMD, NVIDIA, or Intel).

Not sure if you are missing any? Library Health Check can tell you. It lists the registered games that could use a GPU fix but do not have one yet. It changes nothing.

The Library Health Check result screen offers direct `[7] GPU Fix` setup after the report.

If GPU setup skips missing or unavailable saved paths, its result offers `[H] Open 13) Library Health Check`.

### Running GPU Fix and recovering a blocked result

1. At the main menu, choose `7) GPU fix setup`. You will see: TeknoParrot Manager detects AMD, NVIDIA, or Intel.
2. If it cannot identify your graphics card maker, enter one of those names, or press Enter to cancel.
3. Wait while it makes and checks a saved copy (backup) of the registered game setup files (profiles). It does this before it changes any compatibility field.
4. Read the result. Each result belongs to the exact game setup file that was processed. A count does not stand in for a game name.

If a saved game drive is disconnected or a game file (executable) is missing, reconnect it. Or use `13) Library Health Check` to repair the saved path. Then try again.

If the result says a profile write could not be verified, do not run GPU Fix again straight away.

Instead, follow its recovery instruction. Restore the named profile from the verified GPU Fix backup first.

A verified backup is a copy that TeknoParrot Manager checked against the original before allowing any changes.

---

## Force Feedback (FFB) Setup

Force feedback makes a wheel or stick push back or rumble to match what is happening on screen. Examples are road vibration, recoil, and collisions.

Mode 8 covers two completely independent ways to get it. Neither needs the other. You can set up both at once, because they cover different games.

- **Mechanism 1 -- FFB Blaster:** TeknoParrot's own built-in feature. It needs a paid TeknoParrot membership.
- **Mechanism 2 -- Third-party FFB plugin:** a free plugin that covers a different set of racers and shooters.

### Mechanism 1 -- FFB Blaster (native, requires a paid membership)

This is TeknoParrot's own built-in force feedback feature. It is well integrated, but it **only works with an active, paid TeknoParrot membership** ([teknoparrot.com/en/Home/Subscription](https://teknoparrot.com/en/Home/Subscription)).

The script can't check your subscription status, so it asks you directly before changing anything. Answering N skips it entirely.

If you answer Y, the script looks through your TeknoParrot install for games that have the FFB Blaster setting. It turns the setting on for every registered game that has it. Your saved game settings folder (`UserProfiles`) is backed up first.

If the backup or copy fails, or a profile write fails, the native step is reported as incomplete. The optional plugin is then not offered. A later plugin result cannot hide the native failure.

Library Health Check also reports which registered games could use FFB Blaster but do not have it turned on yet. This check is read-only. Its result screen offers direct `[8] Force Feedback` setup.

### Mechanism 2 -- Third-party FFB plugin (free, no subscription needed)

This is a free plugin kept up to date by someone else (mightymikem/FFBArcadePlugin). It covers a different set of arcade racers and shooters.

The list of supported games and the plugin files are always fetched live from GitHub. Nothing is bundled, so the list grows over time with no script update needed.

Controller support (per the plugin's own docs): true force feedback on FFB-capable wheels (Thrustmaster and similar), and rumble on Xbox/XInput-style controllers.

### If a game is covered by both

The script lists every such game once. It then asks a single question:

- Keep FFB Blaster (native) for all of them, or
- use the third-party plugin for all of them.

Native is the safe default. Only an explicit `N` selects the plugin. A blank or invalid answer keeps native.

### Plugin file name clashes

A few games need the same file name for both ReShade and this plugin. For example, H2Overdrive needs `d3d9.dll` for both.

If another file already has that name in the game folder (ReShade's file, for example, or a plugin file from an earlier run), FFB setup skips that game with a warning. It never overwrites that file.

### Removing FFB

TeknoParrot Manager records the plugin files it put in place. When you choose native FFB for a game covered by both, it backs up and removes only a matching unchanged file.

Files that it does not own, or that were changed, stay untouched. They are reported as an advanced troubleshooting boundary.

### More detail

- **Plugin trust.** The shared audit records the source, filename/version when known, computed SHA-256, and transfer metrics. This source has no TeknoParrot Manager-enforced signer or published-digest trust anchor.
- **Where FFB Blaster is turned on.** The script scans your TeknoParrot install's `GameProfiles` for the FFB Blaster field. The field is detected at runtime, never hardcoded. It is enabled on every registered profile that has it.
- **Library Health Check coverage.** It does not fetch the third-party plugin. Third-party plugin coverage is not included there, because checking it needs a live lookup.
- **Choosing the plugin for overlaps.** It creates a fresh verified profile backup. It clears the native FFB Blaster fields for exactly those overlaps before any third-party DLL is deployed. If that switch cannot be verified, deployment is blocked.
- **Path problems.** Missing saved paths and unavailable saved devices are classified separately. They offer a direct handoff to `[H] 13) Library Health Check`.
- **Other results.** Unsupported or no-match games remain distinct from true deployment errors. This holds even when a plugin deployment also has path-limited games.
- **Removing FFB, in technical terms.** TeknoParrot Manager records its own deployed hook files. Unowned or changed files remain untouched.

---

## BepInEx update and setup

[BepInEx](https://docs.bepinex.dev) is a free add-on tool (a plugin and modding framework) for games made with Unity.

Mode 9 is the BepInEx update and setup flow. It offers an install or update for the games you select.

Nothing is installed silently into every game. You approve each change first.

TeknoParrot Manager never removes an existing BepInEx installation (see "Rollback and recovery evidence" below).

### Running BepInEx setup and reading its result

1. At the main menu, choose `9) BepInEx setup`. You will see: TeknoParrot Manager checks the registered game folders and each game's type (x64 or x86, the game executable architecture).
2. Read the list of games that need an install or an update.
3. Choose `Y` to install or update, `B` to go back, or `N` to cancel. Next: nothing changes until you approve the listed operation.
4. Read the result.

The prompt is `[Y] Install/update  [B] Back  [N] Cancel`. There is no repair-reset choice. After a successful or no-change run, the screen waits for one Enter before it goes back.

The result reports these groups:

- clean updates
- skipped and protected games
- missing or unavailable paths
- unsupported and unreadable architectures
- errors

What to do for each result:

- **Known unsupported architecture:** the game is left unchanged. Use a package that supports that game, or check the game vendor.
- **Unknown or unreadable architecture:** the game is also left unchanged. Verify the game executable and its BepInEx architecture before trying again.
- **Missing or disconnected game path:** use `13) Library Health Check` first.
- **Connection failure:** try again when GitHub is reachable.
- **Any other blocked result:** review Details and the support log before another repair attempt.
- **Cleanup uncertain after an update:** use the preserved staging path in Details. Do not count that game as a clean update.

Missing or unavailable saved paths are offered a direct `[H] Open 13) Library Health Check` handoff. Ordinary deployment failures keep their normal Details/support guidance. The official troubleshooting guide remains available for advanced cases.

### Rollback and recovery evidence

Before it changes a game, TeknoParrot Manager saves a copy of that game's BepInEx files. If something goes wrong, it can undo the change.

- If an undo cannot be verified, the result says ACTION REQUIRED.
- In that case, do not retry blindly.
- Close TeknoParrot, keep the paths the message names, and have the game files inspected first.

### More detail

TeknoParrot Manager chooses the stable x64 or x86 package that matches each executable. It validates the download, backs up the game's BepInEx files into a private backup folder, writes the new files under a journal, and rolls back a failed promotion.

Unsafe roots, failed backups, extraction errors, digest failures, and rollback uncertainty fail closed.

Network failures keep the operation incomplete and offer an automatic retry. They do not claim that the setup finished.

If promotion succeeds but cleanup cannot be verified, the game is not counted as updated cleanly. TeknoParrot Manager reports ACTION REQUIRED and preserves the exact staging-residue path in Details for recovery.

**Rollback and recovery evidence, in detail:**

- **Backup.** Before it changes a game, TeknoParrot Manager copies that game's `BepInEx` folder, `doorstop_config.ini`, `winhttp.dll`, `.doorstop_version`, and `changelog.txt` into `<game folder>\BepInEx_Backup_<id>\`, restricted to the current Windows user, with an inventory receipt, and verifies the copy. After the update is verified, TeknoParrot Manager removes this folder. It is kept only if the update fails or the cleanup could not finish; then it is your recovery copy.

- **Refusals before any change.** A game is refused if an existing BepInEx destination file is a link (junction, symlink, or hard link) or cannot be read as a plain file.

- **Writing.** A new file is created exclusively, so a file that appears at that path afterwards is never overwritten. A file being replaced is rewritten only while it still has the identity and bytes TeknoParrot Manager recorded. New folders are created exclusively and a folder that already exists is never adopted.

- **Rollback.** TeknoParrot Manager removes only files and folders it can prove it created (their identity and bytes still match its own record), puts replaced originals back, then checks that every original matches again (bytes and ordinary attributes) and that every created path is gone. Anything that does not match is preserved untouched. For example, a file you or another program edited after it was written, or a folder that gained other content.

- **When rollback cannot be verified.** The result is ACTION REQUIRED with `TPM TRANSACTION ROLLBACK FAILED ... evidence remains at ...`, naming the preserved paths. TeknoParrot Manager keeps the staging folder and the backup. Do not retry blindly: close TeknoParrot, keep those paths, and have the game files inspected first.

Limits: "exact" means the recorded inventory (paths, kinds, bytes, ordinary
attributes, and the modification time of replaced files). Folder timestamps,
permissions (ACLs) and alternate data streams are not captured.

TeknoParrot Manager has a recovery routine that can recreate missing parts of a partly removed
BepInEx tree without overwriting changed or unknown entries. Nothing in
the current menus calls it, because removal of an existing installation is
not offered.

---

## Region Setup

Some games can start in a country you pick, like USA or Europe. It changes things like the language. Games left on `Auto` or `Default` usually start as Japan.

Region setup sets that country for you. You do not have to open each game in TeknoParrotUI.

You can use it in two ways:

- **After you register new games.** TeknoParrot Manager asks once: `Which country do you want your games to start in?` Type the number of a country, or type `0` to leave every game as it is. This question is not asked in a preview or in an unattended run.
- **Any time, from the main menu.** Choose `10) Region setup`.

### Using Region setup (menu 10)

1. At the main menu, type `10` and press Enter. You will see: `Which country do you want your games to start in?` and a numbered list. Each country shows how many of your games offer it, for example `1) USA (12 games)`.
2. Type the number of a country. Or type `A` for `Back to automatic` (the games go back to their normal setting). Or type `0` to go back and change nothing.
3. You will see: `These games can be set to ...` and a list of games. Each game shows its current region, for example `(now: Auto)`. Type `A` to take all of them, or `L` to pick some of them. Next: with `L`, type game numbers to tick them, then `D` when you are done.
4. You will see: how many games will change, how many stay as they are and how many already have it. Next: type `Y` to change them, or `N` to stop. `N` is the default.
5. TeknoParrot Manager saves a restore point of your game settings first. Then it makes the change and reads each game back to check it.
6. Read the result, for example `Region set to USA for 3 games.` Press `D` for the game-by-game details. Press Enter to go back to the menu.

### What Region setup will and will not do

- It lists only the countries your games really offer. A game never gets a region it does not have. A game that does not offer your choice stays as it is and is named under `Do not offer this region (stay as they are)`.
- A region you chose earlier is kept when TeknoParrot Manager asks after a registration. It is only replaced when you change it yourself in Region setup (menu 10).
- Some games have only countries in their list, such as JAPAN, USA and EXPORT, and no automatic choice. The question after registration does not change them. In `Back to automatic` they are named as having no automatic choice, and they stay as they are.
- It changes the game's `Region` setting. For games that have `PcbRegion` and `DongleRegion` instead, it changes both together, so they always match.
- It does not change a true/false export setting, or a region that is typed in as free text (about 6 games). Those stay as they are.
- Online play still uses the automatic region. Region setup does not touch it.

If a game could not be changed, the result says `Could not be changed` and tells you to press `D`. Your other games are still changed. If you want to undo a change, use [Restore backup](#modes) (menu 14) and pick the restore point saved just before.

## Postgres Setup

Several Incredible Technologies games need a small local PostgreSQL 8.3 database. PostgreSQL is a free program that stores data for a game.

The games are:

- Golden Tee Live (2006-2020)
- Power Putt Live (2012/2013)
- Silver Strike Bowling Live
- Target Toss Pro (Bags / Lawn Darts)
- Orange County Choppers Pinball

Mode 11 detects which registered games need it automatically.

### Running Postgres setup

1. At the main menu, choose `11) Postgres setup`. You will see: setup works through the steps for your games.
2. If PostgreSQL is not installed yet and a registered game needs it, Windows asks for permission first. Approve it. TeknoParrot Manager asks Windows for permission itself, so you do not need to open a separate Administrator window.
3. Next: in the window that opens, type a service-account password and a database password at the masked prompts, and confirm each one. A short password such as `1` works. To leave a password prompt without choosing, press Enter.
4. When setup is done, you will see: a short result screen that starts with `PostgreSQL setup finished.`
5. Read the line that starts with `Games set up:`. It gives the counts: games set up, databases created, and already set up.
6. Read the lines under it. Each one tells you what happened for a game, or a group of games.
7. Read the last line: `Next: open TeknoParrot and start any game. Every game database was checked and is ready.`
8. Press Enter to return to the menu. Or press `D` first for details.

The prompt at the bottom reads `Press Enter to return to menu, or D for details`.

### What the result lines mean

- **Ready** -- the database is there, and TeknoParrot Manager connected to it with the game's own settings and found its tables. The line also says whether the database was created from the game's own backup or was already there.

If a game has no starting database file, it is named under `Could NOT be made ready`, and the other games are still set up. If a database cannot be opened with the game's own settings, setup does not say Ready. When it had already created databases, it puts everything back the way it was and checks that.

Games that share the same result are shown together on one line.

If a game is in a folder path longer than 259 characters, setup and the `[I]` rebuild cannot read its backup file. They stop and say so. Move the game to a shorter folder, then try again.

Some games may keep their own PostgreSQL password or settings. TeknoParrot Manager does not change those. The screen then says so, and adds `Press D to see which.`

### Details (press D)

Type `D` and press Enter at the prompt. You will see a screen called `Details`. It shows:

- a summary of what setup did
- what setup checked (it connected to each database with the game's own settings and counted its tables)
- one block per game, with its database, game setup file, what happened and what it means
- any other notes, and what to do next
- `Totals`: `Games set up` (the same number as on the first screen), then `Fields updated`, `Databases created` and `Profiles unchanged`, and the number of errors if there were any (see `TeknoParrot-Manager.log`). `Fields updated` is the same number as `Games set up`, and `Profiles unchanged` is the same number as `Already set up` on the first screen.

TeknoParrot Manager did not start any game; it checked each database by connecting to it. After the details, press Enter to return to the menu.

Everything the short screen shows is also written to the log.

The automatic PostgreSQL repair uses the same short screen. It has no `[D] Show details` line and no prompt, because it cannot ask you anything.

### If setup does not finish

If PostgreSQL setup stops, you see `PostgreSQL setup did not complete successfully:` and a plain sentence about your data. For example: `Setup stopped. Everything was put back the way it was, and checked.` or `PostgreSQL setup stopped before changing any databases or profiles.` If TeknoParrot Manager could not check that your data is back as it was, it says so and tells you to ask for help before you try again. Then you see `Press D to see why, or Enter to continue`. Press D to see `Details` with the reason. The reason is also in the log.

If the PostgreSQL install itself fails, the screen tells you what is true:

- If the Windows installer already ran: `PostgreSQL did not finish installing. Parts of it may now be on this PC. Your games and game settings were not changed.` Then: `Next: open View Log, then choose PostgreSQL setup again. If setup then lists PostgreSQL items it found, read the warning on that screen before you delete anything.`
- If it stopped before the installer ran: `PostgreSQL was not installed. Nothing was changed.`

If setup then shows `These PostgreSQL items are already on this PC.` and a list, it did not remove or change any of them. The list uses plain words. The registry paths, account IDs and service names are in the log, not on the screen. The screen warns: `Do not delete anything on this list unless you are sure what it is.` A PostgreSQL folder can hold game databases and saved scores. Deleting it erases them for good. Copy the folder to a safe place first. If you are not sure, ask someone who knows computers before you delete or uninstall anything.

If a rebuild (`[I]` reinitialize) does not finish, you see `The rebuild did not finish.` and one plain sentence about your data. Then you see `Press D for details, or Enter to continue`. If a rebuild stops in an unexpected way, the screen says some of your data may have been changed and tells you to open View Log. It does not say that nothing changed.

### If the saved password no longer works

If PostgreSQL is already installed, TeknoParrot Manager keeps your existing data.

If the saved password no longer works, it:

1. explains the problem,
2. offers `[F]` so you can type the password PostgreSQL already has. TeknoParrot Manager checks it and saves it. Nothing in PostgreSQL is changed,
3. offers `[X]` ("I do not know the password") only after PostgreSQL has really refused the password.

Choosing `[X]` does not reset anything. It explains why TeknoParrot Manager cannot reset the PostgreSQL password for you. It also tells you that nothing was changed. Press `D` there to see the manual steps for resetting the password yourself.

Next: if you know the password, choose `[F]` and type it. If nobody knows it, press `D` after choosing `[X]` and follow the manual steps.

Why there is no automatic reset: the old method had to add a "trust" line to PostgreSQL's `pg_hba.conf` file. If the window closed or the power went out at the wrong moment, that line could stay behind. Then any program on this PC could log in as postgres without a password. So TeknoParrot Manager no longer does it.

If Windows permission is declined, or a recovery step fails, TeknoParrot Manager keeps any protected retry information it already saved. It offers to try again. The password you type is never shown in commands, logs, messages, or reports.

### If it says the repair came from a different copy

If TeknoParrot Manager says the protected repair came from a different copy, or that the script or configuration changed while Windows permission was open, it stops before it changes PostgreSQL.

Do this:

1. Restart setup from the same TeknoParrot Manager copy that opened the permission prompt.
2. Check the TeknoParrot Manager log for the exact path or file-hash difference.
3. Do not switch to another TeknoParrot Manager copy to continue that repair.

### If a backup fails

Recovery evidence and database backups are created before profile population. Any backup, database, or profile-write failure stops setup.

If an existing database backup fails, TeknoParrot Manager captures the PostgreSQL client diagnostic and exit code. It lists every affected game and database. It classifies the failure as connection, service, tool, permission, missing database, or unknown query failure. Details include the failed check and next action.

On that screen you can choose:

- `[P]` lets you type and test the postgres password. It is shown only when the error mentions the password.
- `[X]` explains why TeknoParrot Manager cannot reset the password for you. It is shown only after PostgreSQL has really refused the saved password. Nothing is changed.
- `[R]` diagnoses the problem and retries the protected backup. This is the default.
- `[I]` reinitializes PostgreSQL data for the affected games. It REPLACES the current data in each listed game database with the game's own starting database. You must type `YES` in capital letters first. TeknoParrot Manager saves and checks a copy of the current data first. If that copy fails, that database is not changed. After a good rebuild it keeps that saved copy and does not delete it.
- `[D]` shows details.
- `[O]` points to logs and support guidance.
- `[B]` goes back to the main menu without profile or database changes.

Next: choose `[R]` after you fix the cause. Choose `[I]` only if you accept that the current game data is replaced.

### More detail

- TeknoParrot Manager does not change the postgres password and does not edit PostgreSQL's authentication rules (`pg_hba.conf`). The password choices (`[F]`, `[P]` and `[X]`) never delete, recreate or restore over a database. TeknoParrot Manager does not wipe PostgreSQL data on its own. Two choices that you confirm yourself do replace database content: restoring a saved PostgreSQL backup (mode 14, after you type `YES`) and `[I]` reinitialize (after you type `YES` in capital letters).
- TeknoParrot Manager updates only affected profiles whose connection values are not already correct. The TeknoParrotUI Pass field remains plaintext because TeknoParrotUI reads it directly. Already-correct profiles are skipped.
- The recovery evidence that TeknoParrot Manager keeps (copies of PostgreSQL `pg_hba.conf` and
  `postgresql.conf`, TeknoParrot Manager's saved settings, and the affected game profiles) is
  private to the current Windows user. See "Recovery evidence privacy" under
  [Safety, Backup and Log](#safety-backup-and-log).
- The `Details` screen says that setup connected to each game's database with the settings saved in that game's profile and counted its tables. TeknoParrot Manager does not start any game, so it does not test a game launch.

**A note on trust:** the PostgreSQL 8.3 installer is distributed via Eggmansworld/tp-it-guides GitHub release bundle. The installer is not Authenticode-signed and this path does not consume a published asset digest. So the script records source, filename/version, computed SHA-256, and transfer metrics. It cannot independently verify publisher authenticity the way it does for ReShade. This is a limitation of the installer/source, not something a stronger check in this script can fix.

---

## Check for Updates

Menu 15 checks GitHub for the latest TeknoParrot Manager release and compares it with the version you are running. If a newer one exists, it can install it for you.

Nothing is downloaded or changed unless you say Y. Before anything is installed, the download is checked against the SHA-256 value GitHub lists for it, and the ZIP is opened and inspected first. If a check fails, nothing is installed.

### What you will see

- If you are already current, it says so and returns you to the menu.
- If a newer version exists, it explains what updating will do. Then it asks a single Y/N question.
- After a successful update, the script exits so you can restart it cleanly. It never keeps running the old code in the same session.
- If anything fails partway, the exact error is shown. You are told whether a backup was created. The script returns safely to the main menu without exiting.

### Installing the update

RC9 is the first version that can update itself in place. When you say Y, it does four things:

1. It downloads the update and checks that it is the real file.
2. It looks inside it.
3. It makes a backup of every file it replaces, in the `UpdateBackups` folder.
4. It installs the files and checks them.

Then you start TeknoParrot Manager again yourself. It does not restart on its own.

- It replaces the program files that are different in the new release. Files that are the same are left alone. New files are added.
- It never deletes anything. Your own files, `UserProfiles` and your backups are not touched. Older program files that the new release no longer has stay where they are.
- If any file cannot be replaced, every file is put back and nothing changes.
- If the drive is too full, it says `There is not enough free space for the update` and installs nothing. Free some space and try again.

**Using a build before RC9 (for example RC8 or RC7)?** Those builds cannot update in place. Install RC9 by hand once: when RC9 comes out, download its ZIP from [GitHub Releases](https://github.com/Jumpstile/teknoparrot-manager/releases), then extract all of its files over your TeknoParrot Manager folder. After that, menu 15 does the updating.

The separate tool `tools\Invoke-TpmAutoUpdate.ps1 -Apply` still refuses a release with many files. It changes nothing.

### Automatic check at startup

The script also quietly checks for updates once, right when it launches. If you are current, nothing is shown.

If a newer version exists, you will see the version and a brief release summary. Then you choose:

- **Y** to update now (same backup-first process as mode 15),
- **N** to continue to the menu and be asked again next time, or
- **V** to read the full release notes first.

To skip the check at launch, set `CheckForUpdatesOnStartup` to `false` in `TeknoParrot-Manager.config.json`. The default is `true`.

You can also run the update check outside the menu via `tools\Invoke-TpmAutoUpdate.ps1 -CheckOnly` (or `-Apply`). See `docs/AUTO_UPDATE.md` for that standalone helper.

See `docs/Compatibility.md` for the compatibility checklist and known tester watchlist.

### More detail

All update checks compare full version identity: numeric base, then numeric
RC number, then final release. For example, `v1.0-RC7 < v1.0-RC9 < 1.0`.

Before replacement, both updater paths parse candidate source without executing it. They accept exactly one bare, unwrapped, unscoped root `$ScriptVersion =` declaration with a constant-string value and at most one equivalent `$ReleaseCandidateLabel` declaration.

These are rejected: attributes/casts, parentheses, scoped or nested assignments, duplicate/destructured writes, compound assignments, increment/decrement, `foreach` targets, root parameters, data-statement variables, and member/index writes rooted at either identity. Function-local parameters do not count as root declarations.

This finite AST check does not prove absence of indirect runtime mutation through commands, providers, `[ref]`, .NET/session state, dynamic names, imports/dot-sourcing, aliases/splatting, or invoked scriptblocks. The main updater also reads the installed script identity back after replacement.

- **Multi-file releases, in technical terms.** TeknoParrot Manager ships required modules (for example `scripts\TpmRequiredPatchEngine.ps1`, `scripts\TpmProgress.psm1`, the certification modules, and `tools\`) and packaged data alongside `TeknoParrot-Manager.ps1`. When the ZIP contains anything besides `TeknoParrot-Manager.ps1` at its root, Check for Updates installs the whole package: entry names are checked first (no drive names, no `..`, no reserved names), the free space on the program drive must be at least twice the unpacked size, the files are unpacked into a `tpm-update-staging-<id>` folder, and the staged script must match the release tag and be newer than the installed one. Every replaced file is copied to `UpdateBackups\TeknoParrotManager_<timestamp>\` with its hash checked. Files are installed with a verified rollback; the main script goes last. Older files the package no longer has are listed in Details and left in place. The staging folder and the downloaded ZIP are removed at the end.

- For a single-file release ZIP (only `TeknoParrot-Manager.ps1` at the root), the current script is backed up to `UpdateBackups\TeknoParrotManager_<timestamp>\` (a new folder every run; a second backup in the same second gets `_2`, `_3`, ... added; never reused) before anything is replaced. If the target is marked read-only, an approved update temporarily clears only that file attribute and restores it after the attempt; failures remain actionable. The standalone `tools\Invoke-TpmAutoUpdate.ps1` differs: it names its backup folder `UpdateBackups\<yyyyMMdd-HHmmss>_<id>\` and refuses a read-only target instead of clearing it.

- The update download is recorded with its GitHub source, filename/version, computed SHA-256, and transfer metrics. Both updater paths require the GitHub release asset's `sha256:<64 hex>` digest and verify it before opening the ZIP, changing target file protection, or creating a backup. Missing, malformed, or mismatched digests stop installation and remove the rejected download. Download the complete ZIP manually from [GitHub Releases](https://github.com/Jumpstile/teknoparrot-manager/releases) if verification is unavailable. This detects corruption or mismatch against GitHub's stored asset, not a compromised publishing account.

- The startup check uses the `CheckForUpdatesOnStartup` setting in `TeknoParrot-Manager.config.json` (default `true`).

---

## LaunchBox Integration

LaunchBox is a front-end program that shows your games in one list. TeknoParrot Manager can add your TeknoParrot games to it.

At the end of each normal interactive run (not in Preview or Unattended mode) the script offers a LaunchBox action menu. It looks like this:

```
Optional: add games to LaunchBox.
[P] Preview first. No changes.
[A] Add missing games (backed up).
[F] Import file only. No changes.
[B] Skip this step.
```

The default is `P`.

What each choice does:

- `P` reads your LaunchBox files and asks which platform to plan for. It prints what a write would do ("A write would add N game entries and change M file(s)"). It changes nothing in LaunchBox, then returns to this menu.
- `A` writes directly into LaunchBox's own `Data\` files.
- `F` creates the reference file without a LaunchBox write.
- `B` skips the optional step.

If no LaunchBox folder is saved in your settings, TeknoParrot Manager asks for the LaunchBox install folder (the folder that contains `LaunchBox.exe`).

### Choosing A: add the games

1. TeknoParrot Manager tells you to close LaunchBox and BigBox (`Close LaunchBox and BigBox first. TeknoParrot Manager will not close them for you.`).
   It asks `Add the missing games to LaunchBox now? (Y/N, D = about the risks)` (default N). Next: answer Y to go on, or press D to read about the risks first.
2. Choose the platform for this action (see below). The choice is not saved.
3. TeknoParrot Manager shows a read-only plan. Then it asks `Write exactly these changes after a
   verified backup? (Y/N)` (default N). If nothing would change, it says so and
   stops.
4. If LaunchBox or BigBox is still open, TeknoParrot Manager tells you and waits. Close it, then
   press Enter to check again, or type `N` to cancel with nothing written. It
   never force-closes either app.
5. TeknoParrot Manager then saves a checked backup, writes the files, and reads every file back to check them.

### Choosing a platform

Each direct-write action asks which platform(s) should receive missing games:

1. Mixed into your existing Arcade platform
2. A separate "TeknoParrot" platform (default)
3. Both -- mixed into Arcade AND a separate TeknoParrot platform
4. A separate platform with a safe custom name

Choosing "Both" creates separate new game records per platform. Existing game entries, favorites, play counts, and metadata are preserved.

The platform choice is made for this action, not silently persisted.

### After the games are added

New games have no box art or metadata yet.

In LaunchBox, right-click a newly added game and use **Edit... -> Search** to fetch it. This is the same way you would do it for any manually-imported game.

### Restoring LaunchBox files

1. Choose menu option 14 (**Restore backup**), then **3 LaunchBox library backup**. The restore menu lists 1 UserProfiles, 2 Postgres, 3 LaunchBox.
2. You will see: the saved copies (snapshots), newest first. Each is labeled with the LaunchBox folder it came from. The label says whether it was `taken before a write` or is a `safety snapshot taken before a restore`.
3. At `Choose a LaunchBox backup, or press Enter (or B) to cancel`, type the number of the one you want. Enter or `B` cancels.
4. Read what TeknoParrot Manager shows: the target folder, the folder the snapshot came from, each file and what will happen to it. It also warns that any LaunchBox edits made to those files since the snapshot will be replaced.
5. Answer the questions that follow.

The questions are:

- If the snapshot came from a different LaunchBox folder than the one you are restoring into, TeknoParrot Manager asks a separate `Y/N` (default N) before going on.
- A final `Y/N` (default N) confirms the restore into the named folder. Then the same guided wait for LaunchBox and BigBox to be closed applies.

If the restore fails and every attempted file is verified back to its prior state, the result is `FAILED`. If recovery cannot be verified, it is `PARTIAL`.

**PARTIAL restore rule, in plain words.** If a restore is `PARTIAL`, do not assume the rest of your library was restored. Keep the reported backup and every listed path. Do not delete or retry blindly.

### Older backups (legacy backup rule)

- **Location.** If the only LaunchBox backup folder is an older `LaunchBoxBackups\` next to `TeknoParrot-Manager.ps1`, TeknoParrot Manager keeps using it, both for new backups and as the restore source. It is not moved or merged by the startup migration. If that folder and a managed `Backups\LaunchBoxBackups\` both exist, backup and restore stop with "Both managed and legacy LaunchBoxBackups folders exist; preserve both and resolve the conflict before continuing."

- **Format.** A snapshot with no `manifest.json` (made by an older build) is listed as `legacy snapshot; source library unknown`. TeknoParrot Manager restores only the files that snapshot contains, each of which must be valid LaunchBox XML under an allowed name. It cannot prove the snapshot is complete or which library it came from, so a file that is not in it is never treated as something to delete, and TeknoParrot Manager says this before you confirm.

**Prefer the manual import wizard instead?** Choose `F` in the LaunchBox action menu to get a reference file (`TeknoParrot-LaunchBox-Import.xml`) and step-by-step wizard instructions. This is useful if you would rather not let the script touch LaunchBox's files directly.

The wizard command line is `--profile=%romfile%.xml`. Point it at your `UserProfiles` folder, importing the profile `*.xml` files themselves. Do not point it at the game executables. TeknoParrot launches by profile, so the profile XML is what LaunchBox treats as the "rom".

### More detail

What the LaunchBox write does and does not do:

- **Inventory and hashing.** TeknoParrot Manager inventories and hashes the target files, stages the new XML, takes a verified backup, replaces the files, and reads every file back.

- **Process checks.** After the guided wait, TeknoParrot Manager checks again before staging, again inside the backup, and again right before the first replace. A small race remains: an app can reopen after any check, and a multi-file save is not atomic. If LaunchBox saved a file between the last check and its replacement, TeknoParrot Manager keeps those newer bytes and rolls back.

- **Inventory and snapshot.** TeknoParrot Manager records every target (`Data\Emulators.xml`, `Data\Platforms.xml`, and each `Data\Platforms\<platform>.xml`), including a platform file that does not exist yet. It copies each existing target into a snapshot and verifies every copy by SHA-256 and a manifest read-back before any library write.

- **Snapshot folders.** A snapshot is built in a `.tpm-incomplete` folder and published only when complete, so an unfinished attempt never appears in the restore list. Each snapshot's `manifest.json` records the LaunchBox folder it came from, whether it was taken before a write or before a restore, and each file's hash (for a file that did not exist, the hash of the file TeknoParrot Manager created).

- **Backup location.** `LaunchBoxBackups\<timestamp>-<id>\` under `<TeknoParrotRoot>\TeknoParrotManager\Backups\`, or under the folder that contains the script when only an older `LaunchBoxBackups\` folder exists there (see "Older backups" above). If both exist, TeknoParrot Manager stops and tells you to preserve both and resolve the conflict; it never merges or deletes either.

- **Backups beside LaunchBox.** Safety backups are never kept inside the LaunchBox folder. When that folder would be inside it (for example TeknoParrot installed in `<LaunchBox>\Emulators\TeknoParrot`), TeknoParrot Manager keeps them in `%LOCALAPPDATA%\TeknoParrotManager\LaunchBoxBackups\<key>\` instead. Here `<key>` is the first 16 hex characters of the SHA-256 of the lower-cased LaunchBox folder path, so each library has its own folder. The preview names that folder, and the write result shows the exact snapshot path.

- **Existing bytes are kept.** For a library file that already exists, TeknoParrot Manager inserts only the new entries just before the closing `</LaunchBox>` tag. The encoding marker, line endings, indentation, existing entries and their order stay as they were; the new entries are not indented. TeknoParrot Manager supports UTF-8 and UTF-16 (with byte-order mark) XML and refuses a file it cannot edit that way. A platform file that does not exist yet is written as UTF-8 without a BOM.

- **Existing entries are not changed.** TeknoParrot Manager creates a missing emulator, platform, or emulator/platform link and never edits or reassigns an existing one. It stops, before any write, when the existing entries are ambiguous or incompatible (several TeknoParrot emulators, a duplicate identity, an emulator that points somewhere else, duplicate platform names); correct that in LaunchBox.

- **Games.** A game that already has an entry with the same path in the target platform is skipped, so re-runs never duplicate games or touch favorites and play counts. A registered profile whose game file cannot be found is not added and is counted in the result ("Not added (game file not found, not an error)").

- **Outcomes.** `SAVED` means every file was read back and matches. `FAILED` means TeknoParrot Manager refused or stopped and every attempted file was verified back to its pre-write state. `PARTIAL` means changed or unverified state remains: keep the reported backup, read the "Needs review" lines, and do not retry blindly. Compensation after a failed save restores only files whose bytes still match what TeknoParrot Manager wrote; anything else is left alone.

**Restoring LaunchBox files, in technical terms.** TeknoParrot Manager verifies the whole snapshot first (every member's hash, and that each file is a LaunchBox XML document). It takes its own verified safety snapshot of the current files, restores, and reads every file back.

Only `Data\Emulators.xml`, `Data\Platforms.xml` and `Data\Platforms\<name>.xml` can be restored. A snapshot that contains anything else is refused.

**PARTIAL restore rule, in detail.** A snapshot can record that a file did not exist before TeknoParrot Manager's write, meaning it created that file.

On restore it removes such a file only if its bytes are still exactly what TeknoParrot Manager wrote and you answer `Y` to "Remove the unchanged transaction-created file ...?" (default N).

If the file changed (you or LaunchBox edited it) or you decline, TeknoParrot Manager keeps it untouched. It restores the other files in the snapshot. It reports the restore as `PARTIAL` with a "Needs review: ... was left in place because ..." line for each kept file. Kept files are not copied into the safety snapshot because TeknoParrot Manager does not modify them.

A different `PARTIAL` result ("LaunchBox recovery is incomplete; changed or unverified files remain", with a "Needs review (not verified back to its pre-write state)" line) means the restore or its rollback could not be verified. Do not assume the rest of the library was restored. Preserve the reported backup and every listed path. Do not delete or retry blindly.

---

## Optional CPS3 first-boot files

TeknoParrot builds a cache file the first time each Capcom CPS3 game runs.
These games include Street Fighter III, JoJo, Red Earth, and the CPS3 multi-game.
That first start is slow.

You may already have the matching TeknoCPS cache (`.simms`) and NVRAM (`.nv`) files.
If you do, TeknoParrot Manager can copy them into your TeknoParrot folder.

This step is optional. Without it your games still work. Only the first start is slower.

**You supply your own files.** TeknoParrot Manager does not include, download, or point to these files.
The release ZIP contains none.
TeknoParrot Manager asks you to browse to a folder or `.zip` you already have.

The Eggman DAT and the Eggman Game Notes page (https://eggmansworld.github.io/TeknoParrot/) document these files.
They are references only.
TeknoParrot Manager does not fetch anything from them for this step.

**When it appears.** It shows up in a normal interactive run, right after the dgVoodoo2 step.
It appears only when a CPS3 game setup file (`cps_*.xml`) is registered in UserProfiles.
UserProfiles is TeknoParrot's saved game settings folder.
The step is skipped in Preview and Unattended mode.
It has no main-menu entry.

**What to do:**

1. Look for the question `Copy CPS3 files you already have? (Y/N, default N)`.

2. Press Y to continue, or N to skip.

3. If you pressed Y, choose where your files are:
   - `F` for a folder (the extracted set: the folder that contains the `TeknoCPS` folder and `README.txt`)
   - `Z` for a `.zip` of that set
   - `C` to cancel

Next: TeknoParrot Manager checks your files and copies them.

If you press N, or choose no location, you will see that nothing was changed.
TeknoParrot Manager does not claim an install.

Before you start, close TeknoParrot and any CPS3 game.
Your existing `.nv` save files are never replaced.

**Reading the result.** `Copied and verified N file(s)` means the copy worked.
If something goes wrong, TeknoParrot Manager tells you exactly what it could and could not confirm.

### More detail: CPS3 files

**All-or-nothing validation.**
TeknoParrot Manager compares the whole location with a built-in list of 103 expected files (name, size and SHA-256 only; no file data).
The list holds 18 `.simms` caches and 83 `.nv` files that can be installed, `README.txt`, and one further `.simms` cache that is checked but never installed.
Every one must be present exactly once with the exact size and checksum.

These problems refuse the whole set and write nothing:

- A missing file.
- An extra item (including `desktop.ini`, `Thumbs.db` or a drive's system folders).
- An unsafe name or link.
- A duplicate (also by letter case).
- A wrong size or checksum.

A folder without `README.txt`, the bare `TeknoCPS` folder, or a set already extracted over a TeknoParrot folder is not a valid source.
TeknoParrot Manager reads every file of the set to verify it, which can take a while.
It checks your TeknoParrot folder first.
If everything is already there and matching, it reports that nothing needs to be copied, without validating the location you chose.

**Where files go and what is never overwritten.**

- Destination: `<TeknoParrotRoot>\TeknoCPS\cps3-install\` for `.simms` and `<TeknoParrotRoot>\TeknoCPS\nvram\` for `.nv`. Destination names come only from the built-in list, never from the names in your location.

- `.nv` files are save/battery data: copied only when absent. A different existing `.nv` is never replaced, even with the replace choice below. An identical one needs no action.

- `.simms` files are regenerable caches: copied only when absent. A different existing one is reported and left alone. TeknoParrot Manager then asks `Replace them with the verified files from your location? (Y/N, default N)`. `Y` replaces only those files and keeps a recovery copy until the new ones verify.

- The copy uses the shared file transaction: staging on the TeknoParrot drive, a backup of anything replaced, link checks, a hash check after the copy, and a verified rollback.

- A file that appears at a destination after TeknoParrot Manager's last check is never overwritten. TeknoParrot Manager stops and rolls back its own earlier copies.

- Close TeknoParrot and any CPS3 game first. TeknoParrot Manager re-checks the `.nv` files it keeps, and stops with a rollback if one changes while the copy runs.

- Free space needed on the TeknoParrot drive is the size of the files to copy plus 64 MB (twice the file size for a `.zip`, which is extracted once to staging).

**Result wording.** `Copied and verified N file(s)` means the transaction succeeded.
TeknoParrot Manager says files were "not installed" only when it verified that nothing was left behind.
If it cannot verify the final state, it says so.
It then says that some CPS3 files may already be in the `TeknoCPS` folder, and which files were not restored or verified.

Limits: TeknoParrot Manager does not check the checksum of the outer `.zip` itself, only the members inside it.
A re-zipped set with identical members is accepted.

---

## Post-1.0 optional plugin scope

HyperSpin-specific core logic, settings, menu entries, guidance, and exports are not part of TeknoParrot Manager 1.0.

Any optional HyperSpin plugin comes after TeknoParrot Manager 1.0.
It is not part of this release.
TeknoParrot Manager does not install it.

---

## RetroBat / Batocera

RetroBat and Batocera need TeknoParrot game folders to end with a suffix.
The suffix can be `.teknoparrot`, `.parrot`, or `.game`.

On the first run, TeknoParrot Manager asks:

```
Use RetroBat folder naming? (Y/N, default N)
```

If you answer Y, game folders are named `GameName.teknoparrot` instead of `GameName`.
Your answer is saved and never asked again.

**Switching an existing library to RetroBat naming:**

1. At `Use these settings? (Y/N, D = show them)`, press N. Next: the first-time questions start, so the RetroBat question appears.
2. Answer Y to the RetroBat question.
3. Make safe copies of your current settings file, your extraction state and your game backups.
4. Look over your existing folder names and registration paths.
5. Run the manager again. Next: games are extracted again with `.teknoparrot` folder names.

Old folders are never deleted automatically.
Delete them yourself once the new ones are confirmed working.

### More detail: RetroBat / Batocera

Registration and fuzzy matching work the same way with or without the suffix.
The suffix is stripped before any profile comparison.

### Already have games set up? Who does what

**Can TeknoParrot Manager still help if my games are already unzipped and partly set up?** Yes. You do not have to delete, move or reset anything first. Start it, pick your TeknoParrot folder and the folder that holds your games, then choose **Register only** (2). It adds the games TeknoParrot does not know yet, and it asks before it fixes a broken game path. It does not delete your game folders.

**What does RetroBat mode change?** Only the names of the folders TeknoParrot Manager unpacks: `GameName.teknoparrot` instead of `GameName`. It does not change RetroBat, its settings or its game list.

**Who does what:**

| Program             | What it does |
| ------------------- | ------------ |
| TeknoParrot Manager | Adds your games to TeknoParrot, copies controls from a game you set up to games of the same type (after you say yes, with a backup first), applies the optional fixes you choose, and names the folders. |
| TeknoParrot         | Runs the games. It keeps each game's controls and input type (for example mouse and keyboard, a controller or a lightgun). It has its own first-time setup window. |
| RetroBat            | Keeps its own game list and starts games its own way. |

**Before you change any controls, check three things:** the game shows up in TeknoParrotUI, it starts from TeknoParrotUI, and you set up one example game of that type yourself.

**Only a mouse and keyboard for now?** TeknoParrot Manager does not set up mouse or keyboard input and does not test your devices. Set the controls for one game in TeknoParrotUI and choose its input type there (RawInput is the mouse and keyboard type). Start that game from TeknoParrot first. Then use **Propagate Controls** (3) to copy the setup to other games of the same type, and test one game before you trust the rest. Starting a game from TeknoParrot and starting it from RetroBat are two different ways to start it. TeknoParrot Manager does not change how RetroBat starts a game and cannot tell you why one way works and the other does not. If a game works in TeknoParrot but not from RetroBat, look at RetroBat's TeknoParrot settings or ask the RetroBat community.

**Later, with Sinden lightguns:** TeknoParrot Manager does not detect or set up lightguns. That setup happens in TeknoParrot and in the gun's own software. The crosshair option (4) only copies crosshair pictures to lightgun games.

### The first-time questions in plain words

- **TeknoParrot folder:** the folder with `TeknoParrotUi.exe`. TeknoParrot Manager never installs TeknoParrot.
- **ZIP source folder (AutoSync only):** where your game ZIPs are. TeknoParrot Manager only reads from it.
- **Games folder (also called the staging folder):** AutoSync unpacks games here. For Register only, it is the parent folder of games you already unpacked. It must not overlap either program or any ZIP source folder.
- **Eggman DAT (optional):** a list of game names that helps match folders to games. It is not a game download.
- **TeknoParrotUI's own first-time window:** it belongs to TeknoParrot. TeknoParrot Manager does not open or finish it. Open TeknoParrotUI once yourself before you register.

---

## Thumbnail Download

After registration, TeknoParrot Manager offers to download game icons:

```
TeknoParrot Manager can download small pictures for your games. It never downloads the games.
Download the missing game pictures? (Y/N, D = use your own pictures)
```

If you answer Y, it downloads an icon (`ProfileCode.png`) for every registered game that does not already have one. Press D instead to see how to use your own pictures.
Icons go in `<TeknoParrotRoot>\Icons\`, the folder TeknoParrotUI uses for thumbnails.
The source is TeknoParrotUIThumbnails on GitHub.

You will see one compact progress row.
TeknoParrot Manager lists exact games missing from the online pack.
A missing icon does not mean the game is unsupported.

**Custom thumbnails:**

1. Create the folder `<TeknoParrotRoot>\TeknoParrotManager\Assets\CustomThumbnails\` under your TeknoParrot folder.
2. Put your PNG files there. Name each one `ProfileCode.png` (for example `Daytona3.png`).
3. Run the thumbnail step. Next: TeknoParrot Manager copies them to TeknoParrot's Icons folder.

Files already in Icons are never overwritten.

**Finding a game's profile code:** after any run, open `TeknoParrot-Manager-controls.txt` in `<TeknoParrotRoot>\TeknoParrotManager\Reports\`.
Every registered game is listed there with its exact profile code.

### More detail: Thumbnail Download

The shared audit records source, filename, computed SHA-256, and transfer metrics.
No published digest or signer trust gate is claimed for icons.

---

## Controls Status File

After every real run, TeknoParrot Manager writes a report called `TeknoParrot-Manager-controls.txt`.
It goes to `<TeknoParrotRoot>\TeknoParrotManager\Reports\`.
Example:

```
[button]
  BlazBlueContinuumShift   52/52 bound   REFERENCE
  AkaiKatanaShinNesica     47/52 bound   propagated  <- BlazBlueContinuumShift
    manual: SpeedChange1, SpeedChange2

[driving]
  Daytona3                 31/31 bound   REFERENCE
  InitialD8                29/31 bound   propagated  <- Daytona3
    manual: GearUp, GearDown

[lightgun]
  SomeNewGame               0/52 bound   no controls
```

Each entry shows:

- The control family (button, driving, lightgun and so on).
- How many buttons are bound (set up).
- The status: REFERENCE, propagated (copied from another game), already bound, or no controls.
- Which reference game the controls came from.
- Any buttons you still have to set by hand.

This file is a list of what was copied. It is not proof that a game's controls work.
The ACTION REQUIRED summary can still report Controls: Not verified, Missing, Unsupported, or Unknown.
That stays true until the required controls are mapped and tested.

The file is replaced on every real run. A preview run does not touch it, so you still see the file from the run before.
It helps most when a game misbehaves days later.
You can see at once whether controls were copied, and from which reference game, without running the script again.

---

## Per-Game Overrides

You can fine-tune single games.
Edit `TeknoParrot-Manager.overrides.json`.
The file is created empty on the first run.

```json
{
  "noSync": ["ZipBaseName1", "ZipBaseName2"],
  "onlySync": ["ZipBaseName1", "ZipBaseName2"],
  "noPropagate": ["ProfileCode1", "ProfileCode2"],
  "forceArchetype": { "ProfileCode": "ReferenceProfileCode" },
  "familyOverride": { "ProfileCode": "trackball" },
  "canonicalArchetype": { "button": "ReferenceProfileCode" },
  "datFile": "C:\\full\\path\\to\\collection.dat"
}
```

| Key                  | Effect |
| -------------------- | ------ |
| `noSync`             | ZIP base names to always skip during extraction |
| `onlySync`           | Whitelist -- if it has anything in it, ONLY these ZIPs are extracted |
| `noPropagate`        | Profile codes to leave untouched when controls are copied |
| `forceArchetype`     | Pin a game to copy its controls from one specific reference game |
| `familyOverride`     | Override the control family that was found automatically (`button`, `driving`, `lightgun`, `trackball`, `analog`, `spinner`) |
| `canonicalArchetype` | The one reference game per control family whose Input API is treated as correct. Every other reference game in that family gets its Input API corrected to match it. See "Reference game Input API mismatches" below. |
| `datFile`            | Full path to a dat file -- used instead of the dat file path from setup. If an Eggman DAT ZIP is set up, that ZIP is used and this file is ignored. TeknoParrot Manager does not ask the start-up DAT question while this is set and the file exists. If the file is missing, it asks as usual. |

All keys are optional.
Leave any key empty or leave it out.

### Reference game Input API mismatches

A "reference game" is a game that already has enough controls bound to copy from.
The manager normally never changes a reference game.
That means it leaves its bindings alone, and its Input API too.
The Input API is the way the game reads your controller.

Two reference games in the same control family can end up on different Input APIs.
For example, one is set up with an XInput pad and another with an arcade encoder.
The script cannot tell which one is correct, so by default it leaves both alone.

If you know which one is right, set it as the `canonicalArchetype` for that family.
On the next run that copies controls, every OTHER reference game in that family gets its Input API corrected to match.
Its bindings are still never touched. Only the Input API field changes.

Leave a family unset to keep the old behavior.
Then no reference game in that family is ever changed.

---

## Action Required Summary

At the end of every run, the script prints a list of everything that needs your attention.
It also saves the list to a text file.

By default the file is `TeknoParrot-Manager-ActionItems.txt` in `<TeknoParrotRoot>\TeknoParrotManager\Reports\`.
A Save dialog lets you pick a different location or file name.
Unattended runs skip the Save dialog and use the default path.
A preview run saves nothing, so it never replaces the list from your last real run.

Each section below appears only when it applies to your games.

| Section                          | Meaning |
| -------------------------------- | ------- |
| **GAME FOLDERS NOT MATCHED TO A TEKNOPARROT PROFILE** | Folders whose program files (`.exe`) matched no game setup file in the TeknoParrot GameProfiles folder, so they were not registered. First make sure TeknoParrot is up to date and TeknoParrotUI has been opened once. TeknoParrot Manager does not update or open it. Then run Register only again. If they still do not match, they may be unsupported games, utilities/launchers, or games whose main file is named differently from what TeknoParrot expects. If you are sure TeknoParrot supports the game, add it in TeknoParrotUI yourself. |
| **REGISTER THESE GAMES IN TEKNOPARROTUI** | Games that share one program file with other games, and are below the auto-register threshold. TeknoParrot Manager shows you the checked list of choices to pick from. Unresolved cases stay in the action summary. |
| **FIX THESE GAME PATHS IN TEKNOPARROTUI** | Games with a broken path that could not be repaired automatically (shared exe, multiple candidates). Open TeknoParrotUI and point each one to the correct folder. |
| **EXTRACT THESE GAMES FIRST, THEN RE-RUN REPAIR** | Games with a broken path because the game is not extracted yet. Extract it, then run TeknoParrot Manager again and answer Y when it asks to repair game paths. |
| **CONTROLS SKIPPED BY DESIGN (informational; not a failed save)** | Games whose control type has no usable reference game yet. Add one game of that type with your own controls, then run this again. |
| **CONTROLS NOT READY : (game code)** | Registered games whose controls are **Missing**, **Not verified**, **Unsupported**, or **Unknown**. Registering a game, launching it, or finishing the TeknoParrot wizard does not check the controls. Open TeknoParrot controls configuration and map and test them before you treat the game as ready. |
| **PATH TOO LONG -- THESE GAMES MAY FAIL TO LAUNCH** | Specific games (Raw Thrills titles, Yu-Gi-Oh! Duel Terminal 6) whose install path is too long. Shows the exact short folder name to rename to. Checked automatically every run. |
| **FILE VERSION MISMATCH -- THESE GAMES NEED A SPECIFIC OLDER FILE** | Specific games that need an OLDER version of one file instead of the latest (BlazBlue-series/`iDmacDrv32.dll`, Tekken Tag Tournament 2/`EBOOT.BIN`). Shows the file name, the current and required CRC32, and where to get the right version. Checked automatically every run. |
| **KNOWN (AMD or INTEL) GPU INCOMPATIBILITY -- NO FIX AVAILABLE** | Specific registered games confirmed not to work on your graphics card brand (AMD or Intel). Informational only -- no fix exists. Checked automatically every run. Silently skipped if the brand can't be detected. |
| **(EMULATOR NAME) FIRMWARE NOT INSTALLED** | Registered games whose emulator needs startup files that TeknoParrot itself doesn't provide: firmware for PCSX2x6, four files for Chihiro/CxbxR, PlayStation 3 firmware for RPCS3 games, and the small settings file each Play! game reads. Says in plain words which games will not start and gives one next step; the exact files and folders are under Details. If the files are in your own collection (the "[EMU]" archives of the TeknoParrot Supplementary set, or another TeknoParrot copy), TeknoParrot Manager offers to copy them after checking every file against the Eggman DAT list (size and every listed hash), and never replaces a different file without asking (it saves a backup copy first). For RPCS3, it installs the firmware from the PlayStation 3 firmware file (`PS3UPDAT.PUP`) in your own collection by running RPCS3 for you. It never downloads, links, or redistributes these files. Also in the Health Check (the "Game startup files" row, key F). Checked automatically every run. |
| **(EMULATOR NAME) EMULATOR COMPONENT NOT FOUND** | A required emulator part is missing from its expected path. Shows the evidence and the affected games. Use the normal TeknoParrot installation/update process. TeknoParrot Manager does not diagnose why it is missing, and does not repair, download, reinstall, or modify TeknoParrot. |
| **Additional informational game notes** | Registered games with special setup notes in the community compatibility database (eggmansworld.github.io/TeknoParrot) -- workarounds, known quirks, and so on. Informational only. Skipped silently if the live fetch fails. See More detail below. |

### More detail: Action Required Summary

- **Additional informational game notes:** the expected executable name and sanitized notes go to the separate `TeknoParrot-Manager-game-notes.txt` report. For each registered game that has them, the file also lists the guide's setup steps and known issues (such as which ZIP or disc file to select), graphics card notes for AMD, NVIDIA and Intel, a second game file and a test program. It also names the extra archives a game needs (bring your own copy; none is downloaded), a linked profile (the same game with another setup, and whether it is registered here), and a game the guide lists as broken or only partly working. A version of a game that shares its base game's steps shows them under the base game when that game is registered too. Nothing in this file is applied for you. Raw source notes are excluded from Action Required.

- **REGISTER THESE GAMES IN TEKNOPARROTUI:** the list is the validated candidate list, and you make an explicit in-product choice.

- **CONTROLS NOT READY:** the controls are those backed by the controls catalog. Registration, a successful launch, and TeknoParrot wizard completion do not verify controls.

- **PATH TOO LONG:** the limit is a hard-coded engine-specific limit.

- **EMULATOR COMPONENT NOT FOUND:** the component is contract-backed. The section shows the contract/detector evidence and affected profiles.

- **FIX THESE GAME PATHS IN TEKNOPARROTUI:** these are profiles with a broken path that could not be auto-repaired.

---

## Unattended / Scheduled Mode

Unattended mode skips all questions.
In this release it does one job only: the read-only Library Health Check.
It does NOT extract games, register games, copy controls or download thumbnails, so it cannot run AutoSync or Register only on a schedule.
It does NOT run Restore mode, because that needs you to pick a backup.
It does NOT run LaunchBox direct integration.

**To use it:**

1. Run TeknoParrot Manager once yourself, so your settings are saved.

2. Add `"UnattendedMode": "HealthCheck"` to the saved settings file, `TeknoParrot-Manager.config.json` in `<TeknoParrotRoot>\TeknoParrotManager\State\`. An ordinary save from the menus keeps this value.

3. Start it with `-Unattended`:

```powershell
.\TeknoParrot-Manager.ps1 -Unattended
```

Without saved settings you will see `ERROR: Unattended mode requires saved settings.`
With saved settings, you will see `TeknoParrot Manager found your saved settings.` and then `[Unattended] Using saved settings.`
It does not ask `Use these settings? (Y/N, D = show them)`.

Without `UnattendedMode` set to `HealthCheck`, you will see `[Unattended] Mode must be set before starting.` and the run ends with exit code 1.
Any other value is ignored in the same way.

**Exit codes:** 0 means the check finished, even if it found problems in your library. 2 means some checks could not finish. 1 means no mode was set.

**Scheduling the Health Check with Windows Task Scheduler:**

1. Run TeknoParrot Manager once, interactively, to save your settings.

2. Open Task Scheduler (`taskschd.msc`).

3. Choose Create Task.

4. On the General tab, give the task a name.

5. On the General tab, set "Run whether user is logged on or not".

6. On the General tab, also set "Run with highest privileges".

7. On the Triggers tab, set your preferred schedule.

8. On the Actions tab, choose Start a program.

9. For Program, type `powershell.exe`.

10. For Arguments, type `-ExecutionPolicy Bypass -NonInteractive -File "C:\path\to\Scripts\TeknoParrot-Manager.ps1" -Unattended` (use your own path).

11. (Optional) On the Conditions tab, if your games are on a network drive, choose "Start only if network connection available" and select that connection.

Next: after each run, check `TeknoParrot-Manager.log`. To extract or register games, run TeknoParrot Manager yourself from the menu.

---

## Preview / Dry-Run Mode

A preview shows what would change, before anything changes.
Scanning, settings handling and logging still happen.

A preview shows:

- Which games would extract (and why -- new, changed on NAS, and so on).
- Which games would register, and to which TeknoParrot game setup file.
- Which broken paths would be repaired.
- Which controls would be copied, and from which reference game.

**To preview:**

1. Choose AutoSync or Register only from the main menu.
2. You will see three choices: `[P] Preview (default) -- show what would change; no game or profile changes`, `[R] Run now -- back up UserProfiles first, then make the changes`, and `[B] Back`.
3. Choose **P** (or press Enter, because P is the default).

To always preview without being asked, start the script with `-DryRun`:

```powershell
.\TeknoParrot-Manager.ps1 -DryRun
```

`-DryRun` previews AutoSync or Register only. `-Unattended` runs only the Health Check, so it is not a way to preview a scheduled AutoSync.

To check a copy before a release or on a test PC without any questions, run the read-only validation report:

```powershell
.\TeknoParrot-Manager.ps1 -ValidationReport -ValidationRoot "D:\TeknoParrot" -ValidationJsonPath "D:\report.json"
```

It prints the version and script checksum, the PowerShell and Windows versions, the TeknoParrot folder and saved settings (the saved PostgreSQL password is only shown as yes or no), how many games are registered, which games still need PostgreSQL settings, how many profiles support, do not support or do not say whether they support RawInput and RawInputTrackball, the files that ship with TeknoParrot Manager, and the compatibility warnings. `-ValidationRoot` is optional when your settings are saved; `-ValidationJsonPath` is optional and is the only file it writes. It never changes TeknoParrot, your game profiles, your saved settings or the log. Exit codes: 0 pass, 3 action required, 4 failed (for example no TeknoParrot folder), 1 the report could not be made.

In preview mode:

- No backup is created. There is nothing yet to restore.
- The optional LaunchBox direct-integration offer, the thumbnail download and the GPU fix are skipped. They only make sense after real changes.
- The summary and ACTION REQUIRED sections still print normally, based on the games that would have been registered.

**After a preview:**

1. You will see `PREVIEW -- no games or profiles were changed.`
2. Next you will see `Do you want to make these changes for real now?` with `[D] Details` next to `[Y]` and `[N]`.
3. Choose **Y** to scan again and apply the changes. Choose **D** first to read the details.
4. Or choose **N** to return to the main menu. Nothing is changed.

Applying runs a fresh scan. It does not replay the preview.
It uses the same game selection the preview used (main and supplementary sources, and the Health Check scope), so you are not asked to pick the games again.

Preview is most useful the first time you point the script at a new library.
It also helps after you change settings.
You can see what will happen before the script touches your files.

---

## Game Repair

After registration, the script offers to repair broken game paths.
A broken path is empty, or points to a file that no longer exists (for example after you moved your games).

| Result                | Meaning |
| --------------------- | ------- |
| **Fixed**             | The path was pointed to the correct program file |
| **Not yet extracted** | The game is not in the staging folder -- extract it, then run TeknoParrot Manager again and answer Y when it asks to repair game paths |
| **Register manually** | The game shares a program file, so it can't be assigned safely by itself. Use TeknoParrotUI. |

---

## Safety, Backup and Log

The normal backup covers only your `UserProfiles` folder.
It does NOT include:

- Game-side NVRAM (the game's own saved memory).
- Test-menu settings.
- Calibration files outside UserProfiles.
- A full copy of the game.

Save those yourself ([issue 378](https://github.com/Jumpstile/teknoparrot-manager/issues/378)).
LaunchBox, database and patch backups protect only the particular data those actions change.

**UserProfiles backup:** AutoSync saves a timestamped copy before it extracts anything.
It goes here:

```
<TeknoParrot>\UserProfiles\FullBackup\<label>_<date_time>_<id>\
```

Preview mode skips the backup.
If the backup cannot be created or completed, AutoSync does not start extraction.

**Replaced game folders:** when AutoSync replaces a game folder because its ZIP changed, the old folder's extra or different files (saves, settings, ReShade files) are copied to `<TeknoParrotRoot>\TeknoParrotManager\Backups\AutoSyncReplaced\` first. Restore backup does not list these. Copy files back by hand if you need them.

**Restore:**

1. At the main menu prompt `Enter 1-17:`, type 14 (Restore backup) and press Enter.
2. You will see the `Restore from Backup` screen with four choices.
3. Type 1, 2, 3 or 4, then press Enter. The choices are explained below.

Every list of saved copies shows the newest one first.
Press Enter at the number prompt to cancel.

**Choice 1: TeknoParrot UserProfiles backup.**
You will see `Saved copies of your game settings, newest first:` with a number, the kind and time of the copy, and a file count for each copy. Press `D` to see the folder name.
Type the number of the one you want.

You will see a warning that the restore will overwrite all current UserProfiles.
Type `YES` to confirm.
A restore does not keep a copy of the settings it replaces. TeknoParrot Manager keeps a temporary copy only while the restore runs, so it can roll back if the restore fails, and deletes it after a verified success. If you may want your current settings back, make your own copy first or use Reset and Restore.
When it works you will see a green `Restore complete.` line.

**Choice 2: Postgres database backup.**
This only matters if you have used Postgres setup (mode 11).
You will see `Available Postgres database backups (most recent first):`, with the databases in each copy.

It lists timestamped backups from `<TeknoParrotRoot>\TeknoParrotManager\Backups\PostgresBackups\`. (An older `PostgresBackups\` folder beside the script is used only if it already exists.)
Each database is restored from its `pg_dump` snapshot.
This replaces the _current_ content of each database that is restored.
TeknoParrot Manager first saves a copy of what is there now and keeps that copy after a good restore. It shows the folder, and you can delete it yourself later.

You must type `YES` first.
If the restore did not simply succeed, you will see a plain line such as `The restore did not finish. Your data is back the way it was. TeknoParrot Manager put everything back and checked it.` Then you see `Press D for details, or Enter to continue`.
Press D to see `Details`.

**Choice 3: LaunchBox library backup.**
You will see the LaunchBox backups listed with the newest first.
Each row has a label, such as `[taken before a write]` or `[safety snapshot taken before a restore]`.

Type the number you want.
You are then asked `Y/N`, and N is the default.
A restore that has to keep a TeknoParrot Manager-created file that you changed, or declined to remove, is reported as `PARTIAL`.

Full rules: [Restoring LaunchBox files](#restoring-launchbox-files).

**Choice 4: Reset and Restore.**
This puts back one game or all games from a restore point.
A restore point is a checked copy that TeknoParrot Manager saves when it starts.
You will see this menu:

```
1) Reset one game (back to the first restore point)
2) Restore one game (choose a restore point)
3) Reset all games (back to the first restore point)
4) Restore all games (choose a restore point)
5) Remove older restore points
B) Back
```

Choices 2 and 4 show `Restore points, newest first:`.
Before anything changes, you see what will change.
A wrong answer cancels it, and nothing is changed.

Next: at the end you will see `Press Enter to return to menu`.

**Choice 5: Rebuild one game from its ZIP.**
Use this when one game is broken and you do not know why. It puts the game folder back to exactly what is in the game's original ZIP.
You need the game's ZIP in the ZIP folder you use for AutoSync. TeknoParrot Manager finds it by the same names AutoSync uses. If the DAT list knows the game, the ZIP is checked against it too.
You will see this menu:

```
1) Rebuild one game from its ZIP
2) Put an old folder back (undo a rebuild)
3) Delete an old folder I no longer need
B) Back
```

For choice 1 you pick a game and read a short preview: how many files, how big, and where your old folder will be kept. Type `YES` to go on. Any other answer cancels and nothing is changed.
The ZIP is unpacked and checked in a temporary folder on the same drive. Then your current folder is renamed and kept in `TPM-old-game-folders`, beside your games folder, and the new folder takes its place. Nothing is copied twice and nothing is deleted. Saves and your own settings that are not in the ZIP stay in the old folder.
If anything goes wrong, your old folder is put back. The TeknoParrot settings for the game are not changed.
It says so and changes nothing when the ZIP is not found, when there is not enough free space, when the ZIP does not match the DAT list, or when the game is running.
Choice 2 puts the old folder back and keeps the rebuilt folder instead. Choice 3 deletes an old folder for good after you type `YES`. Old folders use disk space until you delete them.

**Manual restore:** if you restore files by hand, be careful.
First save a checked copy of your current files somewhere outside the folders that will be replaced.
Think about which later settings you would lose.

Close TeknoParrot before any UserProfiles recovery.
For LaunchBox, use the checked restore in menu 14 instead of copying many files by hand.
Keep LaunchBox and BigBox closed the whole time.

After a failure, keep all recovery evidence.

**Log:** every run adds to `TeknoParrot-Manager.log`.
If the log cannot be written, you see a one-time warning with the path and the error.
Lines that cannot be written are shown with `[UNLOGGED]`.

### More detail: Safety, Backup and Log

**LaunchBox backups (choice 3).**
The restore finds backups the same way as backup creation, using the same managed/legacy root resolver.
A legacy-only `LaunchBoxBackups\` next to the script is listed and used.

A managed and a legacy folder together stop the restore.
When that folder is inside the LaunchBox folder, the per-library `%LOCALAPPDATA%\TeknoParrotManager\LaunchBoxBackups\<key>\` folder is listed too.
It also receives the new safety snapshot, and TeknoParrot Manager prints that folder above the list.

Incomplete backup attempts cannot be selected.
Snapshot discovery errors, missing members, or hash mismatches refuse writes.
The restore asks Y/N (default N) rather than `YES`.

**Recovery evidence privacy:** PostgreSQL recovery evidence (`PostgresRecoveryBackups\`) holds copies of PostgreSQL configuration, TeknoParrot Manager's saved settings, and affected game profiles.
So TeknoParrot Manager restricts it to the current Windows user.
Inheritance is removed and only that account is granted access.
No other account (administrators included) gets an access entry.

TeknoParrot Manager creates each folder, locks it to you, checks it is empty, and only then writes each file and locks it.
It does not rely on Copy-Item or Move-Item permission behavior.
A folder or file that cannot be verified private stops the operation before bytes are written to it. On a drive that keeps no file permissions (FAT, FAT32 or exFAT) there is nothing to restrict, so that check counts as passed.
TeknoParrot Manager never deletes retained recovery evidence to clear an error.

**Startup migration of owned state:** at startup, TeknoParrot Manager can move manager-owned state it finds beside the script into `<TeknoParrotRoot>\TeknoParrotManager\`.
It first asks `Tidy up now? (Y/N, D = show the list)` (default N; nothing is moved unless you answer Y). Unattended mode does not ask and does not move your folders; the only thing it may move is the start-up log file alone, into the `Logs` folder.
`PostgresRecoveryBackups\` is one of the moved items and goes to `Backups\PostgresRecoveryBackups\`.
`LaunchBoxBackups\` and `PostgresBackups\` stay where they are.

For recovery evidence the move works like this:

1. A private copy goes to `Backups\LegacyMigration_<id>\`.
2. The folder is then copied into its new place.
3. TeknoParrot Manager checks the copy matches byte for byte and is private.
4. It re-checks that the original did not change.
5. Only then does it remove the original.

If the original changed after it was copied, TeknoParrot Manager keeps both copies.
TeknoParrot Manager first restricts the original folder to your account.
That stays in place even if the migration then stops.
A report goes to `Reports\TPM-migration-<date>-<id>.md` when the move is applied or stops because a destination is occupied. Answering N writes no report.

TeknoParrot Manager stops startup with "Startup stopped because owned-state migration needs review" only in these cases:

- The migration ends as ACTION REQUIRED or with cleanup residue.
- The product state is unknown.
- A managed destination was occupied or could not be checked.

It then lists the backup and residue paths to preserve and asks you not to delete or overwrite them.

These cases do not block startup:

- The migration stops before moving anything (for example, its safety backup could not be verified).
- The migration is declined.
- The migration is fully rolled back and verified.

In those cases TeknoParrot Manager prints a notice and continues, and the originals stay where they were.

A managed `Backups\PostgresRecoveryBackups\` and an older `PostgresRecoveryBackups\` beside the script existing together stop startup as an occupied destination.
Preserve both folders and the migration report and ask for help.
TeknoParrot Manager does not merge or delete either.

Limits: a file written into the original evidence folder in the short moment between the final check and its removal would not be copied.
The protected copy uses ordinary Windows paths, so a very deep TeknoParrot folder path can make it fail.
TeknoParrot Manager then reports the failure and keeps what it has instead of deleting evidence.

**Log details:** until the TeknoParrot folder is known, each launch writes its first lines to `TeknoParrot-Manager.log` beside the script.
Once the managed log exists, startup appends them to it after a read-back check and removes the script-folder copy.
An empty script-folder log is simply removed.
Any other script-folder log that is not plain TeknoParrot Manager log text of at most 1 MiB is kept unchanged in the Logs folder.
It is renamed `TeknoParrot-Manager.<date-time>-<id>.legacy.log`, and nothing is overwritten.

**Download audit trail:** the log also records a download audit trail for every shared-pipeline artifact.

- ReShade installer: source/filename/version/SHA-256 plus Authenticode signer/status/thumbprint/trust result.
- BepInEx GitHub: source/filename/version/SHA-256 plus digest validation when available.
- dgVoodoo2, FFBArcadePlugin, Eggman/RomVault dat, PostgreSQL guide, TeknoParrot Manager update package, and TeknoParrotUI thumbnails: source/hash/transfer audit fields.

Transfer method, size, elapsed time, and average MB/s are recorded for each download.
Sources without a published digest or signing anchor are not described as cryptographically authenticated.

---

## Registration Evidence Ledger

AutoSync, Register-only, and manual registration choices keep a lasting record.
It notes what a run selected and what it did.
So a crash or a closed window does not leave you guessing.

The record is a file:
`<TeknoParrotRoot>\TeknoParrotManager\State\TPM-RegistrationLedger.json`

Keep this file when you ask for help.
Support packages read it.

**If you see "Action required: the registration evidence ledger is ...":**

1. Keep the file exactly as it is. Do not edit, trim or delete it.
2. Create a support package.
3. Ask for help before you run the manager again.

TeknoParrot Manager starts no extraction or registration when the ledger is unusable.

### More detail: Registration Evidence Ledger

- **Before the first write.** AutoSync publishes the list of ZIPs it selected before it examines the first one. Register-only and manual choices publish the game folders they will act on before any profile is written. TeknoParrot Manager reads the file back. If it cannot, the run stops before extraction or registration and changes nothing.

- **Each profile write.** TeknoParrot Manager records the attempt before it writes. It marks it `VERIFIED` only after reading the saved profile back and confirming that its game path and executable match the intended mapping. A write it could not read back stays `WRITE_ATTEMPTED_UNVERIFIED`. An existing profile TeknoParrot Manager did not write is never recorded as verified.

- **States.** Each game folder ends as `VERIFIED`, `PARTIAL`, `SKIPPED` (with a reason such as an ambiguous shared executable or no profile match), `FAILED_BEFORE_WRITE`, or `WRITE_ATTEMPTED_UNVERIFIED`. Work that an earlier run never closed (a crash, a closed window) is `INTERRUPTED_UNKNOWN` on the next run. It is never reported as success.

- **An unusable ledger.** The file may be corrupt, unreadable, not a version 1 ledger, larger than 1 MiB, or on a link (junction or symlink) path. Then TeknoParrot Manager prints "Action required", and starts no extraction or registration (before the backup, for Register). It does not change, trim, or delete the file. Keep it as it is, create a support package, and ask for help before running again.

- **A publication failure during a run.** TeknoParrot Manager says that the evidence could not be published. It starts no further extraction or registration in that menu workflow, and does not roll back or retry. Results already known stay in that session's output and log but are not durable.

- **Fatal errors.** TeknoParrot Manager appends a short redacted record (message cut at 500 characters) tied to the run and its open operations. It never overwrites an unusable ledger.

Limits:

- The ledger is capped at 1 MiB, checked before every write. A large "all games" run adds roughly 100-130 bytes per selected ZIP or folder and 350-450 bytes per attempted mapping, so many runs can fill it. When it is full, TeknoParrot Manager drops the oldest finished runs to make room, so later runs are never blocked. It never drops a run that is unfinished or still in progress, and it counts every dropped run in the `TrimmedOperations` number inside the file and writes each one to the log. If it still cannot make room, it refuses the run and changes nothing.
- It records AutoSync extraction and the registration writes (exact, dat, single-executable, fuzzy, name-code, subfolder, manual choice, and duplicate switch). Other workflows that edit profiles, such as Library Health path repair, are not recorded.
- When the ledger cannot be updated after a profile was already written, the on-screen result can still report the games it registered. The uncertainty is flagged in the result's warnings, the log, and the ledger's last durable record.
- Restart reconciliation against the saved profile appears in the support package only. It is never written back into the ledger.

**Package identity limits.** The support package's `runtime-identity.json` records what TeknoParrot Manager can prove about the running copy.
That is the script path, length and SHA-256 captured at startup, PowerShell version and edition, OS, process architecture, and the version label.

The package id, package manifest hash and source commit are reported only when a `TPM-PackageIdentity.json` sits beside the script.
That file must be at most 64 KiB, with a `PackageId` of letters, digits, `.`, `_`, `-`, and a 40-character hex `SourceCommit`.
TeknoParrot Manager's release packaging does not produce that file.
So a normal release package reports those three fields as `unavailable`.
The version label (for example `v1.0`) is never used as a package hash or a commit.

---

## Resetting

| What to reset              | How |
| -------------------------- | --- |
| Saved settings             | Answer N at `Use these settings? (Y/N, D = show them)` to enter your locations again. For any advanced manual reset, first keep a copy of your existing settings file. |
| Re-extract or repair games | First look at TeknoParrot Manager Details, the source identity and the state it kept. Keep your backups. Deleting syncstate is not proof that re-extraction is safe or needed. |
| Correct one registration   | Keep a copy of its UserProfile. Check the correct official game setup file and GamePath. Use the checked candidate or manual setup. Do not delete the XML just to try again. |

---

## Uninstalling / Removing the Manager

Most of the manager's own files (settings, logs, reports, assets and backups) are in the `TeknoParrotManager\` folder inside your TeknoParrot folder.
A few stay next to the script: `TeknoParrot-Manager.overrides.json`, `TeknoParrot-Manager-crosshairs.json`, and the `Crosshairs\` and `BepInExCache\` folders.
It also adds files to TeknoParrot's own `UserProfiles\` folder.
Mode 11 may install PostgreSQL as an optional local extra.
TeknoParrot Manager has no menu action to uninstall PostgreSQL.

**To remove the manager entirely:**

1. If you want to undo all changes, restore your UserProfiles to their state before the script, using mode 14 (Restore backup). Or leave them as they are if they work correctly.
2. Only if you really want PostgreSQL gone: use the normal Windows installed-apps list, and only after you keep any database backups you need. This is an advanced system-maintenance job, not part of the beginner workflow.
3. If you used the direct LaunchBox integration, restore your LaunchBox files first, with mode 14 > LaunchBox library backup. Then close LaunchBox so it reads its files again.
4. Remove only the verified TeknoParrot Manager program files you mean to uninstall. Do not delete a shared Scripts folder or unrelated files. Keep needed settings, logs, assets and backups before you remove TeknoParrot Manager's own runtime files.

**Undo without full removal:** use mode 14 (Restore backup) at any time.
It can put your TeknoParrot UserProfiles, LaunchBox library files, or Postgres databases back to an earlier state.
This is the intended way to undo a bad run. It is not a full uninstall.

**What happens if you remove each file:**

Before you remove anything, keep a checked backup outside the affected folders and make sure the file is TeknoParrot Manager's own.
The table shows consequences.
It is not permission to delete shared files or recovery evidence you may need.

| File                                                     | Effect after verified removal |
| -------------------------------------------------------- | ----------------------------- |
| `TeknoParrot-Manager.config.json`                        | the script asks for settings again on the next run |
| `TeknoParrot-Manager.overrides.json`                     | recreated as an empty template; you lose your overrides |
| `TeknoParrot-Manager.log`                                | a fresh log is created on the next run |
| `TeknoParrot-Manager.syncstate.json` (in staging folder) | the record of what was extracted is lost; check the source and folder identity before any further sync |
| `TeknoParrot-Manager-controls.txt`                       | recreated on the next run |
| `TeknoParrot-Manager-ActionItems.txt`                    | recreated on the next run |
| `TeknoParrot-Manager-crosshairs.json`                    | the crosshair choice goes back to the defaults |
| `LaunchBoxBackups\`                                      | removes the saved copies that let you undo LaunchBox changes; keep any backups you need |
| `PostgresBackups\`                                       | removes database recovery copies; keep any backups you need |
| `PostgresRecoveryBackups\`                               | removes private recovery evidence (PostgreSQL config copies, saved settings, profiles); keep it |
| `AutoSyncReplaced\` (in `TeknoParrotManager\Backups\`)    | removes the saved copies of files from game folders AutoSync replaced; keep them until you are sure you do not need those saves |
| `State\TPM-RegistrationLedger.json`                      | removes the record of earlier registration attempts; keep it while you need support |
| `TeknoParrotManager\Backups\RestorePoints\`              | removes your saved restore points, so Reset and Restore can no longer put those settings back; keep it |
| `TeknoParrot-LaunchBox-Import.xml`                       | recreated if you run the LaunchBox export again |

---

## Troubleshooting

New users: start with [ten beginner problems, symptoms, causes, and fixes](docs/TROUBLESHOOTING.md).

If a game is reported as not recognized, do this:

1. Make sure TeknoParrot is up to date.
2. Open TeknoParrotUI once.
3. Run Register only again.

TeknoParrot Manager does not update TeknoParrot, check how fresh the game setup files are, or open the UI.

**A game appears in TeknoParrotUI but won't launch.**
Its GamePath is wrong, or the game wasn't fully extracted.
In TeknoParrotUI, find the game and point it to the correct `.exe`.
Run the script again and answer Y when it asks to repair broken game paths.

**A game does not appear in TeknoParrotUI.**
Some games share one program file.
For those, choose one of the checked candidates TeknoParrot Manager offers, or leave it for TeknoParrotUI.
If the game has not been extracted yet, extract it first.
Otherwise check the log for a registration error.

**A game keeps re-extracting after an interrupted extraction.**
TeknoParrot Manager keeps the evidence of the unfinished job and reports ACTION REQUIRED.
Open Details and look at the log, the source archive, the free space and the kept paths before you try again.

Do not delete an `.extracting` marker just to make the warning go away.
Removing it does not verify the game files.
Ask for help if the safe next step is unclear.

**A game folder was replaced and my saves or settings are gone.**
AutoSync replaces a game folder only when its ZIP changed. The files that were extra or different are in `<TeknoParrotRoot>\TeknoParrotManager\Backups\AutoSyncReplaced\`. Copy back what you need. If AutoSync could not save those files, or no Backups folder is set up, it did not update that game and left the old folder alone. Nothing was changed for that game.

**Controls are not being copied to a game.**
There are three possible reasons:

- No reference game for that control type has been bound yet (see "CONTROLS SKIPPED BY DESIGN" in ACTION REQUIRED).
- The game is in `noPropagate` in `TeknoParrot-Manager.overrides.json`.
- The game already has enough bound controls to count as a reference itself.

**A fuzzy-matched game was registered against the wrong profile.**
A "fuzzy match" is a guess made from similar names.

1. Save a checked copy of the affected UserProfile XML outside UserProfiles before you change it. Include any bindings and settings you need.
2. Confirm the correct official game setup file and executable.
3. Use TeknoParrot Manager's checked candidate choice when it is offered. Or set the correct game setup file and GamePath in TeknoParrotUI.

Do not delete a profile just to try matching again.
`forceArchetype` picks which game controls are copied from. It does not change registration matching.

**A game's controls are wrong after propagation.**
"Propagation" means copying controls from a reference game.

1. Use mode 14 to look at the available UserProfiles backup before you restore. Check which later settings it would replace.
2. Save any current bindings and settings you need outside the affected paths.
3. Correct the reference game's settings in TeknoParrotUI.
4. Try again.

Do not remove a UserProfile unless you have checked who owns it, which settings it needs, and that you have a verified backup.

**A game appears twice in TeknoParrotUI.**
First confirm that two UserProfiles really refer to the same game.
Compare their GamePath, bindings and settings.

Save checked copies of both outside UserProfiles before you remove a confirmed duplicate.
Keep the settings you need.
If you are not sure who owns it or which one is meant, leave both alone and ask for help.

**Script appears to hang or freeze during registration.**
The scan is probably still running. Large game libraries can take a minute.
A progress bar (`Scanning game library`) shows the current folder and the total exe count.
If the console is truly frozen (no progress bar, no output for several minutes), check your staging folder.
Make sure it is reachable and not on a disconnected network drive.

**"Access denied" or "you do not have permission" errors.**
Most features run as a normal user.
When PostgreSQL setup needs Windows permission, TeknoParrot Manager asks for it automatically.

It carries on with the same job after you approve.
If you decline the prompt, choose the retry TeknoParrot Manager offers.
Do not open a separate Administrator PowerShell window.

**ACTION REQUIRED says "Path too long".**
TeknoParrot Manager can unpack games into very long folder paths and can find and set them up there.
A few games (some Raw Thrills titles and Yu-Gi-Oh! Duel Terminal 6) cannot start from a long path.
ACTION REQUIRED names them and shows the short folder name to use.
Rename the folder yourself, for example use `E:\TP Games\` instead of `E:\My Arcade Games Collection\TeknoParrot Games 2024\`.

**ReShade text or a window shows when the game starts.**
TeknoParrot Manager turns the welcome window, the counters and the messages off in every `ReShade.ini` it writes.
If you still see them, the game's `ReShade.ini` was not written by TeknoParrot Manager, or it was changed by hand.
Next: run `5) ReShade setup`, choose that game and pick a look again. TeknoParrot Manager then writes the file with these settings off. If the result says it left that game alone, press `D` to read why.
A short ReShade version banner at game start is normal. ReShade has no setting to hide it.

**TeknoParrot Manager says LaunchBox or BigBox is still open.**
For a direct write and for a restore, TeknoParrot Manager tells you the app is open and waits.

1. Save your work in LaunchBox or BigBox.
2. Close it.
3. Press Enter to check again. Or type `N` to cancel, with nothing written.

TeknoParrot Manager never force-closes either app.
If an app reopens before the write begins, the job stops with "Close LaunchBox and BigBox ..." and nothing changes.
A small chance remains that an app reopens just after the last check.

### More detail: Troubleshooting

**`[UNLOGGED]` entries on console.**
`TeknoParrot-Manager.log` can't be written.
Check that the `<TeknoParrotRoot>\TeknoParrotManager\Logs\` folder is not read-only and you have write permission.

**Network drive timeouts at startup.**
The script detects mapped network drives so it does not scan them during game discovery.
If a drive that was mapped before is now unreachable, startup may take a few seconds before it times out gracefully.
This is expected, and the drive is skipped.

**Postgres connection fails / "password authentication failed".**
The database password is saved encrypted in `config.json`.
If it was changed outside the manager (via pgAdmin or similar), mode 11 explains the problem.

It asks you to type the password PostgreSQL already has (`[F]`). TeknoParrot Manager checks it and saves it.
If nobody knows the password, choose `[X]`. It does not reset anything. It explains why there is no automatic reset. Press `D` to see the steps for resetting it yourself.

Next: if you know the password, type it. If not, follow the manual steps under `D`.

TeknoParrot Manager does not change the password, wipe data or edit authentication rules.

**Startup stopped: "owned-state migration needs review".**
Preserve the backup and residue paths it lists, plus the migration report under `Reports\`.
Do not delete or overwrite them.
See "Startup migration of owned state" under [Safety, Backup and Log](#safety-backup-and-log).

**"Action required: the registration evidence ledger is ..."**
TeknoParrot Manager refused to start extraction or registration because `State\TPM-RegistrationLedger.json` is unusable or cannot be updated.
Keep that file as it is, create a support package, and ask for help before running again.
See [Registration Evidence Ledger](#registration-evidence-ledger).

---

## What It Does Not Do

- It does not invent control bindings. A control is set only when a reference game you have already bound has it. Everything else is left for you and reported in ACTION REQUIRED.
- It does not provide game files. You must own or otherwise have lawful rights to the original arcade PCB and any ROM/game data you use. TeknoParrot Manager does not provide, distribute, or endorse unauthorized game files. The script only registers and configures your legally obtained games.

---

## Create Support Package

If something goes wrong, you can send the helpers a support package.
It is one ZIP file with safe diagnostics inside.

**To create it:**

1. Optional but best: in TeknoParrotUI choose **Troubleshooting -> Save information to a text file**.

2. Save that file in the Reports folder: `<TeknoParrotRoot>\TeknoParrotManager\Reports\`. Name it `TeknoParrot-Manager-TeknoParrotUI-Troubleshooting.txt`. At the Create Support Package menu, **D** shows the exact folder. TeknoParrot Manager uses that exact allowlisted filename. It does not read an arbitrary troubleshooting path.

3. In TeknoParrot Manager, choose **Create Support Package** from the main menu.

4. Wait while it gathers the diagnostics. Next: it creates one ZIP in the `<TeknoParrotRoot>\TeknoParrotManager\SupportPackages\` folder under your TeknoParrot folder.

5. You will see whether the ZIP was created, and its exact path. This is the file to send when you ask for help.

6. Press **O** to open the `<TeknoParrotRoot>\TeknoParrotManager\SupportPackages\` folder, or **B** to return to the main menu.

If some optional diagnostics were missing, the ZIP is marked as partial.
If a collection or ZIP step fails, you never see a success message.
A failed package with no ZIP does not offer the folder-opening follow-up.

The package never copies game executables, ROMs, archives, firmware, passwords, tokens, API keys, cookies, or unrelated personal files.
The exact list is under More detail.

### More detail: Create Support Package

**What the package contains.** It includes a plain-language manifest.
Where safely available, it also holds allowlisted TeknoParrot Manager logs, TeknoParrot logs, the TeknoParrotUI troubleshooting intake, and game-local text logs.
It adds redacted affected-game profile snapshots, metadata-only plugin inventories, and per-file ReShade removal scan/transaction details.

**Evidence labels.** The manifest labels evidence as:

- `Current` (captured or generated by this TeknoParrot Manager run).
- `Ambient` (supplied or discovered without current-run provenance).
- `Stale` (older than the latest TeknoParrot Manager run).

Action Required evidence becomes `Stale` when its timestamp predates `TeknoParrot-Manager.log`.
Run the affected workflow again before sending the ZIP.

The exact TeknoParrotUI intake filename and evidence-class labels are also printed in the package README and manifest.
So support intake can tell authoritative current-run facts from ambient or stale diagnostics.

**Package output.** The package output leads with `What failed:` and `What TPM did not change:`.
The first section keeps detailed allowlisted collection failures, while routine missing optional diagnostics stay collapsed.
The second section states that support collection does not change game files, profiles, credentials, or emulator files.
Redacted profile snapshots keep only structured path, registration, controls, ReShade, PostgreSQL, LaunchBox, and related review fields.
Original UserProfile XML is never copied.

Support packages also carry registration and identity evidence under `metadata\`:

- `registration-ledger.json` is an allowlisted, redacted view of the [registration ledger](#registration-evidence-ledger). Work an earlier run never closed shows as `INTERRUPTED_UNKNOWN (derived ...)`, never as success. Absolute paths are reduced to `<absolute>\leaf` or `<install-root>`. Each mapping notes whether the saved profile still matches the intended mapping. `fatal-record.json` and `transaction-facts.json` are the matching redacted fatal-error and transaction records.
- `profile-inventory.json` gives every registered profile a disposition (`SNAPSHOT_INCLUDED`, `UNSAFE`, `UNREADABLE_OR_MALFORMED`, `NOT_PRESENT`, or `INTENTIONALLY_OMITTED`) with totals. Profiles named by the ledger go first and are exempt from the 200-profile cutoff. Once 200 profiles have been collected, any further profile that the ledger does not name is listed and counted but not inspected, and the package is marked partial with the reason.
- `runtime-identity.json` is what TeknoParrot Manager can prove about the running copy: startup script path, length and SHA-256, PowerShell version and edition, OS, process architecture, and the version label (see "Package identity limits" in the ledger section).
- `workflow-result.json` says how the last finished workflow ended (for example a dgVoodoo2 setup that stopped): its name, final state, the activity, the next step and the last few step results, with personal folders removed. TeknoParrot Manager keeps that one small record in `State\TPM-LastWorkflow.json`, so a package made after a restart still shows it. `FromEarlierRun` says whether it is from before this start.

A corrupt ledger, a profile listing that did not finish, or a metadata file over its 4 MiB limit makes the package partial.
The manifest then carries `PARTIAL EVIDENCE:` lines.
Support collection never changes ledger states or workflow outcomes.

**What is never copied.** The package never copies game executables, ROMs, archives, firmware, arbitrary DLL payloads, your original profile files, configuration files, credentials, PostgreSQL passwords, `.pgpass`, recovery state, tokens, API keys, cookies, or unrelated personal files. It does include redacted copies of the profiles of games that need help.
Text diagnostics are checked for executable/archive signatures, binary control bytes, invalid encoding, common secrets, and user-profile paths before inclusion.
Unsafe content is recorded as rejected rather than staged.
This redaction is extra protection, not a guarantee that every possible secret can be detected.

**Partial results.** If some information could not be collected, TeknoParrot Manager marks the package partial. If the ZIP is ready but a temporary folder could not be removed, it says so and you can delete that folder yourself. If no ZIP could be made, it says the package was not created. It never reports a clean success after a problem.

**Opening the folder.** The folder opens only after canonical-path and reparse checks pass.

---

## Files Reference

`<ProgramFolder>` means the folder containing TeknoParrot-Manager.ps1.

TeknoParrot Manager places its normal configuration and log under `<TeknoParrotRoot>\TeknoParrotManager\State\` and `Logs\`.

| File                                  | Location                                                 | Purpose |
| ------------------------------------- | -------------------------------------------------------- | ------- |
| `TeknoParrot-Manager.config.json`     | `<TeknoParrotRoot>\TeknoParrotManager\State\` | Saved folders and settings |
| `TeknoParrot-Manager.overrides.json`  | Scripts folder                                           | Per-game tweaks |
| `TeknoParrot-Manager.log`             | `<TeknoParrotRoot>\TeknoParrotManager\Logs\` | Log of every run |
| `TeknoParrot-Manager.syncstate.json`  | Staging folder                                           | Tracks extracted ZIPs |
| `TeknoParrot-Manager-controls.txt`    | `<TeknoParrotRoot>\TeknoParrotManager\Reports\`          | Controls state after every real run |
| `TeknoParrot-Manager-ActionItems.txt` | `<TeknoParrotRoot>\TeknoParrotManager\Reports\` (default; Save dialog can pick elsewhere) | Action items from last run |
| `SupportPackages\`                    | `<TeknoParrotRoot>\TeknoParrotManager\SupportPackages\` | Safe support ZIPs created by the in-product support action |
| `TeknoParrot-LaunchBox-Import.xml`    | `<TeknoParrotRoot>\TeknoParrotManager\Reports\`          | LaunchBox manual-import reference XML (only if you skip direct integration) |
| `LaunchBoxBackups\`                   | Managed Backups root, or existing legacy-only ProgramFolder root; `%LOCALAPPDATA%\TeknoParrotManager\LaunchBoxBackups\<key>\` when that root is inside the LaunchBox folder | Verified pre-write and pre-restore snapshots; conflicting roots stop the operation; never inside the LaunchBox folder |
| `PostgresRecoveryBackups\`            | Managed Backups root (moved there at startup), or an existing legacy copy beside the script until moved | Private (current-user-only) PostgreSQL recovery evidence |
| `State\TPM-RegistrationLedger.json`   | `<TeknoParrotRoot>\TeknoParrotManager\State\`            | Durable record of AutoSync/Register selections and verified or unverified profile writes (1 MiB cap) |
| `TeknoCPS\cps3-install\`, `TeknoCPS\nvram\` | `<TeknoParrotRoot>\TeknoCPS\`                      | CPS3 `.simms` caches and `.nv` files copied from files you supply (optional step) |
| `BepInEx_Backup_<id>\`                | The game's own folder                                    | Private backup of the game's BepInEx files taken before an update; removed after the update is verified, kept only if the update fails or cleanup could not finish |
| `PostgresBackups\`                    | `<TeknoParrotRoot>\TeknoParrotManager\Backups\`          | Timestamped `pg_dump` backups of Postgres databases, made before each Postgres setup run (an older folder beside the script is used only if it already exists) |
| `AutoSyncReplaced\`                   | `<TeknoParrotRoot>\TeknoParrotManager\Backups\`          | Extra or different files (saves, settings, ReShade files) copied out of a game folder before AutoSync replaced it from a changed ZIP |
| `ReShade\ReShade64.dll`               | `<TeknoParrotRoot>\TeknoParrotManager\Assets\ReShade\` or the Scripts folder | ReShade DLL (64-bit; not included in the release ZIP; downloaded for you if you choose D) |
| `dgVoodoo2\*.dll` + `dgVoodoo.conf`   | `<TeknoParrotRoot>\TeknoParrotManager\Assets\` or the Scripts folder | dgVoodoo2 DLLs (not in the release ZIP; used from your folder, or downloaded for you if you choose D) |
| `Crosshairs\*.png`                    | Scripts folder                                           | Crosshair images (321 included) |
| `CustomThumbnails\*.png`              | `<TeknoParrotRoot>\TeknoParrotManager\Assets\CustomThumbnails\` | Your own game icons (optional, you create) |

### More detail: Files Reference

Startup migration leaves existing `LaunchBoxBackups\` and `PostgresBackups\` histories in place.
It moves `PostgresRecoveryBackups\` (private recovery evidence) into the managed Backups folder through a protected copy (see "Safety, Backup and Log").

LaunchBox backup creation and discovery share an owned-layout-aware resolver:

- Managed-only histories are used where present.
- An existing legacy-only history remains usable.
- Competing roots stop the operation for owner-directed resolution.

No LaunchBox history is silently merged, deleted, or migrated.
Preserve all copies and migration reports.

---

## Support / Contributing

Found a problem?
Choose **Create Support Package** in TeknoParrot Manager and send us the ZIP it creates.
It gathers safe diagnostics automatically.
Manual log attachments are an advanced fallback.

Pull requests are welcome too.
Full source and version history: [github.com/Jumpstile/teknoparrot-manager](https://github.com/Jumpstile/teknoparrot-manager).

---

## License

TeknoParrot Manager is source-available under the [TeknoParrot Manager
Source-Available Personal/Non-Commercial License](LICENSE). Official
releases may be used personally and non-commercially, and the source may be
viewed for transparency. Issue reports and pull requests are welcome for
consideration.

Commercial use, redistribution, modified distribution, sublicensing,
bundling, paid support use, arcade-operator use, or incorporation into
TeknoParrot or another emulator, launcher, or arcade-management product
requires prior written permission under a separate commercial or integration
license. See [COMMERCIAL-LICENSE.md](COMMERCIAL-LICENSE.md). The
TeknoParrot Manager name and branding are reserved.

---

> TeknoParrot Manager v1.0 RC9 (not published yet). The latest published release is v1.0 RC8.2. Test one game after each run. AutoSync backs up UserProfiles before extraction; preview mode skips the backup.

