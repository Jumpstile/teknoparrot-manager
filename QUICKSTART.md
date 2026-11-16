# TeknoParrot Manager - Quick Start

> This guide describes v1.0 RC8.2. RC8.2 is a fix-up release for RC8.1. It fixes problems that testers found. RC8.1 is the latest published release before it. If you use RC8.1, choose **15) Check for Updates** to get RC8.2. The previous published releases are v1.0 RC7 and RC6. RC8 was a tester build and was never published. The final v1.0 RC9 comes later. Final Version 1.0 remains unpublished. Test one game after every run. AutoSync backs up UserProfiles before extraction; preview mode skips the backup. [All releases](https://github.com/Jumpstile/teknoparrot-manager/releases).

Full documentation: [README.md](README.md)

## New here? Start with one game

TeknoParrot Manager adds your own games to TeknoParrot. It also helps copy controls and apply supported fixes.

It is not TeknoParrot. It does not install TeknoParrot or set it up for you.

**Start here:** [Start Here: complete beginner steps](docs/START-HERE.md). Read it before the reference sections below.

Allow about 10 minutes once your downloads are ready. TeknoParrot installation, large games, and special controllers take longer.

The Start Here guide covers:

- the official stable installer, including how to choose a safe install folder
- runtimes (small helper programs that Windows games need)
- opening TeknoParrotUI once yourself
- installing the complete TeknoParrot Manager ZIP
- each first-run answer
- registration (telling TeknoParrot about each game)
- testing controls
- fixes
- optional LaunchBox

TeknoParrot Manager never provides, downloads, or links to games, ROMs, or patch files. You must own the game data you use, or have the legal right to use it.

The optional community DAT is a list used to match your game names. It is not a game download. See the [plain-language glossary](docs/START-HERE.md#glossary) for any word you do not know.

**Before you use TeknoParrot Manager:**

1. Install TeknoParrot into its own folder, such as `C:\TeknoParrot`. Never use the installer's default `C:\Windows\system32`.
2. Open TeknoParrotUi.exe yourself, one time.
3. You will see a few pop-up windows. Click OK, OK, and Accept and Continue.
4. Next: you may use Skip Setup. Then add games with TeknoParrot Manager.

Make sure TeknoParrot is up to date. TeknoParrot Manager never updates or opens it. It also never checks whether TeknoParrot's game setup files (profiles) are current.

See the [verified install and first-run steps](docs/START-HERE.md#2-install-teknoparrot-by-hand-first).

**What the normal backup covers:**

The normal backup protects UserProfiles only. UserProfiles is TeknoParrot's saved game settings folder.

It does not protect game-side NVRAM (settings a game keeps itself), test-menu settings, or calibration files outside that folder ([issue 378](https://github.com/Jumpstile/teknoparrot-manager/issues/378)).

Other actions have their own saved copies. None of them is a whole-game backup. See [logs and backup locations](docs/START-HERE.md#10-read-progress-find-logs-and-keep-backups).

Stuck? [Ten beginner problems: symptoms, causes, fixes](docs/TROUBLESHOOTING.md).



**The main menu:**

The main menu stays open until you choose Exit. It has five groups:

- library management
- optional game enhancements
- game requirements (PostgreSQL setup and required game patches)
- maintenance and recovery
- application tools

Type the number of an option to begin.

Most beginners should confirm the TeknoParrot folder first. Then choose **1) AutoSync** for ZIP files, or **2) Register only** for games that are already extracted.


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
- [Required game patches](#required-game-patches)
- [Region Setup](#region-setup)
- [PostgreSQL setup](#postgresql-setup)
- [LaunchBox Integration](#launchbox-integration)
- [Post-1.0 plugin scope](#post-10-plugin-scope)
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

You need:

- A Windows PC with PowerShell 5.1 available for TeknoParrot Manager. Also check the current official requirements for TeknoParrot.
- PowerShell 5.1. It is built into Windows, so you do not install it.
- TeknoParrot installed, with `TeknoParrotUi.exe` in its folder.
- Your games as ZIP files (for AutoSync), or already extracted into subfolders.

TeknoParrot Manager asks Windows for permission by itself when a safe setup step needs it. You do not need to prepare an Administrator PowerShell window.

---

## Advanced users

TeknoParrot Manager is also for people who already know TeknoParrot. They want library changes that can be repeated and checked.

These tools help you review bulk work without losing detail:

- previews
- logs
- backups
- action summaries
- exact paths
- profile identifiers
- hashes
- validation evidence

The full advanced-user guide is in docs/ADVANCED-USERS.md. It explains the evidence model and who owns what.

Expert workflows still detect first, preview supported changes, back up before writes, and verify the result.

---

## Run It

1. Double-click **`TeknoParrot-Manager.bat`**.

   You will see: a text window opens. This is the normal way to start TeknoParrot Manager, and it opens the menu for you.

   Next: answer the start-up question in step 2.

2. Answer the start-up question. What you see depends on whether you have run it before.

   **First time:** you will see `Welcome to TeknoParrot Manager`. Press Enter to continue. It then looks for TeknoParrot by itself.

   - If it finds one copy, you will see `Auto-detected TeknoParrot at:` and the path. Type Y to use it, or N to choose another.
   - If it finds several copies, it lists them with numbers. Type the number of the one you want.
   - If it finds none, it asks `Type the path of your TeknoParrot folder, the one with TeknoParrotUi.exe in it, or Q to quit (or type B to browse)`. Type the folder, type B to browse, or type Q to quit. Nothing is changed if you quit.
   - If you close the browse window without choosing, the question comes back. If the folder is wrong, you see `That folder does not exist. Check the spelling, or type B to browse.` or `TeknoParrotUi.exe is not in that folder. Pick the folder that has TeknoParrotUi.exe in it.` and it asks again.

   **Later runs:** you will see `TeknoParrot Manager found your saved settings.` Then it asks:

   ```
   Use these settings? (Y/N, D = show them):
   ```

   Type one letter and press Enter:

   - **Y** -- you will see `Using your saved settings.` Your saved folders are used, and you are not asked for them again.
   - **N** -- it asks the first-time questions again. Your new answers are saved over the old settings later.
   - **D** -- it shows your saved settings (see More detail), then asks the question again.

   Any other key shows `Please choose Y or N.` and asks again.

3. Pick a mode. Type its number at `Enter 1-17:` and press Enter.

   Next: when a mode finishes, you return to the menu.

   After new games are registered, you are asked once which country they should start in (see [Region Setup](#region-setup)). Type **0** to leave them as they are.

4. For AutoSync, check the suggested folder. TeknoParrot Manager suggests a safe staging folder (the games folder).

   Press **Enter** to use it, or type **B** to browse for another folder.

   Next: it creates the folder on a real run if it does not exist. Preview / Dry Run leaves it untouched.

5. After registration, open `TeknoParrotUi.exe` yourself to see the games.

   TeknoParrot Manager never opens it for you.

### More detail

**The staging folder rules.** TeknoParrot Manager recommends a staging folder based on your configured TeknoParrot location. The folder you accept must have enough free space. It must also be outside all of these, and must not contain them:

- TeknoParrot
- TeknoParrot Manager's program folder
- both ZIP source folders

**What D shows at the saved-settings question.** It lists one row for each saved setting, such as the TeknoParrot root and the ZIP source folder. Then it asks the question again. By default the settings list is only written to the log, not printed.

**When the question is not asked.** On the very first run there are no saved settings, so there is no question. An unattended run uses the saved settings without asking. If the saved settings file cannot be read, you get a warning and the normal questions.

**Running the script directly (advanced).** Run it from PowerShell, in the folder that contains `TeknoParrot-Manager.ps1`:

```powershell
cd "C:\path\to\TeknoParrot Manager"
.\TeknoParrot-Manager.ps1
```

If Windows blocks the script on this route, allow it for this session only:

```powershell
powershell -ExecutionPolicy Bypass -File .\TeknoParrot-Manager.ps1
```

## Workflow status

During longer jobs, a bar shows how much work is finished. The bar does not prove a game works.

`3/40` means three items are finished. If the total is unknown, the bar moves without a percentage.

The status area says what is happening now. It also says whether you need to answer something.

Always read the final result, even when the bar is full.

**The Details option.** Many result screens offer a Details choice, such as `[D] Details` or `Press D for details, or Enter to continue`.

Type D and press Enter to see the full technical information. The same information is always kept in the log.

### More detail

During multi-step work, TeknoParrot Manager shows a `TeknoParrot Manager status` line. It shows the current action, what just finished, the next step, and anything it needs from you.

It uses real step counts. It keeps important failures visible until you acknowledge them. It adapts safely when the PowerShell window is resized.

Redirected, unattended, and certification runs use structured status events without cursor-control output.

---

## Mode List

This is the full menu. Type a number at `Enter 1-17:`.

| # | Mode | What it does |
| --- | --- | --- |
| 1 | **AutoSync** | Extract your game ZIPs, then register the games |
| 2 | **Register only** | Register games you already extracted |
| 3 | **Propagate Controls** | Copy controls from a game you set up to games of the same type. It copies only known button settings, and only to compatible games that have none yet. It is not universal device or shooter mapping |
| 4 | **Crosshair setup** | Pick and deploy custom crosshairs to lightgun games |
| 5 | **ReShade setup** | Add visual post-processing to game folders |
| 6 | **dgVoodoo2 setup** | Fix some old DX8, DirectDraw, and Glide game crashes or black screens |
| 7 | **GPU fix setup** | Apply AMD / NVIDIA / Intel vendor fix to registered games |
| 8 | **Force feedback (FFB) setup** | Native FFB Blaster (membership) + free third-party plugin |
| 9 | **BepInEx setup** | Install or update after you approve, using stable x64/x86 releases. It never removes an existing install |
| 10 | **Region setup** | Pick the country your games start in (like USA or Europe), choose all or some of the games that offer it, confirm, and TeknoParrot Manager saves a backup and changes them. You can also put games back to Auto |
| 11 | **Postgres setup** | Installs/configures the local PostgreSQL database some Incredible Technologies games need |
| 12 | **Required game patches** | Find, validate, back up, install, verify, or undo a required fix for a supported exact game build, using your local ZIP |
| 13 | **Library health check** | Reports registered/broken/unregistered games, plus GPU fix / FFB Blaster / dgVoodoo2 / Postgres coverage and ReShade/BepInEx counts, without changing anything. Any repair it suggests is a separate choice that you confirm first |
| 14 | **Restore backup** | Put TeknoParrot game setup files (profiles), LaunchBox's library files, or Postgres databases back from an earlier saved copy. Saved copies are listed newest first |
| 15 | **Check for Updates** | Check GitHub for a newer TeknoParrot Manager release and install it (RC8.1 and later) |
| 16 | **Create Support Package** | Gather safe logs and reports into one ZIP to send when asking for help |
| 17 | **Exit** | Quit |

---

## Create Support Package

If you need help, make a support package. It is one ZIP file with safe logs and reports.

1. At the main menu, type **16** and press Enter.

   You will see: `Create Support Package` with three choices. They are `1) Create Support Package`, `2) Open TeknoParrot Manager Logs and Reports`, and `3) Return to the main menu`.

2. Type **1** and press Enter.

   Next: TeknoParrot Manager collects safe logs and reports, checks them for private information, and makes one ZIP.

3. Find the ZIP in `<TPRoot>\TeknoParrotManager\SupportPackages\`.

4. Send that ZIP when you ask for help.

To look at the logs yourself, type **2** at the same menu. Choose **Open TeknoParrot Manager Logs and Reports**. This browses the folder with the current logs and reports.

The package does not include games, ROMs, passwords, or personal files.

### More detail

The package includes per-file ReShade ownership/removal scan and transaction details.

It may include allowlisted TeknoParrot Manager and TeknoParrot text logs, safe game-local logs, and metadata about plugin files.

It never includes ROMs, game executables, arbitrary DLL payloads, firmware, your original profile files, credentials, PostgreSQL passwords, `.pgpass`, recovery state, tokens, API keys, cookies, or unrelated personal files. It does include redacted copies of the profiles of games that need help.

If an optional diagnostic is missing or cannot be read, TeknoParrot Manager says so. It marks the package partial when appropriate.

A failed collection or ZIP creation is never reported as success.

---


## Game Selection (AutoSync)

After you enter your folders, TeknoParrot Manager hides games that are already extracted. Then it shows this menu:

```
A) All unextracted games
L) Browse and select from list (A-Z)
S) Search by keyword
D) Done -- continue with selected queue
B) Back / cancel AutoSync selection
```

What each choice does:

- **A** extracts everything that is not yet on disk.
- **L** shows a paginated A-Z list. Pick games by number.
- **S** filters games by name. Pick by number.
- **D** carries on with the games you picked.
- **B** goes back and cancels the AutoSync selection.

In Browse or Search, type numbers or ranges to add games to your queue. For example, type `1,3,5-7`.

**If a game folder already exists:** when its ZIP did not change, AutoSync leaves the folder alone, so your saves and settings stay. When a changed ZIP replaces a folder, files in it that are extra or different (saves, settings, ReShade files) are first copied to `Backups\AutoSyncReplaced`. If they cannot be saved, or no Backups folder is set up, that game is not updated, nothing is changed for it, and the screen says so.

Games already in your queue are marked with `*`.

You can mix Browse and Search sessions. Press D when you are ready to confirm.

---

## Copy Your Controls

TeknoParrot Manager can copy controls from one game to other games of the same type. You set up ONE game of each type first.

Setting up controls in TeknoParrotUI is called binding. A bound game has its buttons and axes assigned.

**Good reference games to bind first:**

| Type | Suggestions |
| --- | --- |
| Fighting / buttons | Street Fighter III, BlazBlue, Tekken 7, Dead or Alive 5 |
| Driving | Daytona Championship USA, Initial D, OutRun 2 SP |
| Lightgun | House of the Dead 4, Aliens Extermination |
| Trackball | Golden Tee Live, Silver Strike Bowling |

**Steps:**

1. In TeknoParrotUI, fully bind one game of each type. Set the buttons, axes, Test, Service, Coin, and Start.
2. Run TeknoParrot Manager again. Copying runs by itself after registration.
3. Launch ONE updated game and test it before you trust the rest.

To copy right away, choose **3) Propagate Controls** at the main menu.

You will see: `You have 2 games with their controls set up.` Then you see a preview of what would change. It ends with `Preview only. Nothing was saved.` Then you see the question `Copy controls from 2 games to your other games of the same type? (Y/N, D = details)`.

Next: press **D** to see each example game and the settings that will be copied. Check them against your real hardware. Then press **Y** to copy, or **N** to cancel. If you press **N**, nothing changes. A saved copy of your game settings is made when you approve.

After the copy, the program asks `Undo these changes and put your game settings back as they were? (Y/N)`. Press **Y** to put everything back at once. You can also undo later with **14) Restore backup**.

If a copied setting looks wrong, you also see a yellow line: `Check first: 1 game may have settings that do not match your real controller. Press D to see them.` Answer **N**, fix that game in TeknoParrotUI, then run this again.

When a game type has no usable example, its games are skipped. The run can finish with Done and a skipped count. Details and the log list those games. Add one game of this family with your own controls, then run this again. If all games are skipped, no game was changed. A failed save still ends as an error. Done does not prove that a game's controls work.

### More detail

The script copies known bindings to compatible unbound games in the same detected control family.

This is a bounded reference-copy aid. It is not universal controller or gun detection, and it is not complete shooter mapping.

---

## Crosshair Setup

Mode 4 puts custom crosshair cursor images into all your registered lightgun games.

**Steps:**

1. Type **4** at the main menu and press Enter.

   You will see: a preview window. It shows the 321 included designs, and any valid PNGs you added to `Crosshairs\`.

2. Choose a design for Player 1 (P1).

   Click a design. Or use Tab and Shift+Tab, then press Enter or Space.

3. Choose a design for Player 2 (P2) the same way. Both players can use the same design.

   You will see: the preview closes after P2 is chosen.

4. Check your choices in the console.

5. Confirm.

   Next: the script copies the images to every registered lightgun game.

6. Optionally, choose to hide the Windows cursor in all gun game profiles. A backup is taken automatically first.

If you press Esc, click **Close preview**, or the 45-second timer ends, your choices so far are kept. TeknoParrot Manager asks for the missing numbers in the console.

If the preview cannot open, enter both numbers in the console.

Nothing is deployed until you confirm.

Run mode 4 again any time to change designs. Add your own PNG files to the `Crosshairs\` folder and the script picks them up automatically.

### More detail

**Where the images go:**

- Standard games: `P1.png` + `P2.png` in the game's exe folder
- ElfLdr2 games: shared pair in the ElfLdr2 emulator folder
- Pcsx2x6 games: shared pair in `pcsx2x6\TeknoParrot\crosshairs\` (the official upstream location)

For Pcsx2x6 games, `cursor_path` stays emulator-owned under the current contract. TeknoParrot Manager leaves it unchanged and reports existing values read-only when available.

---

## ReShade Visual Enhancements

ReShade adds picture effects on top of a game: a sharper image, CRT-style scanlines, borders. It does not change game data.

ReShade works with 64-bit games only. 32-bit games are skipped and nothing in their folder changes.

**Popular effects:**

| Effect | What it does |
| --- | --- |
| LumaSharpen / CAS | Removes blurry upscaling |
| CRT_Royale / CRT_Lottes | Classic scanlines and curvature |
| Levels / Vibrance | Vivid colors on modern monitors |
| Border | Arcade cabinet artwork in black bars |

### Set up a ReShade look

1. At the main menu, type **5** and press Enter.

   You will see: `ReShade Visual Enhancements Setup` with three choices.

   ```
   S) Set up ReShade visual enhancements
   R) Remove verified TeknoParrot Manager-managed ReShade files
   U) Undo ReShade changes
   Action (S/R/U, default S):
   ```

2. Press Enter (or type **S**) to set up ReShade.

   You will see: a notice about the ReShade file. If ReShade is not found yet, you will see `ReShade 64-bit DLL not found.` (the DLL is the program file ReShade needs). Here **D** means download, not Details. Type **D** to download it from reshade.me, **B** to browse for a file you already have, or **N** to skip.

3. Choose how your game should look.

   You will see: `Choose how your game should look. Nothing will be changed until you confirm.` Under it is a numbered list in two groups, `CRT Choices` and `Main Catalog`. A preview window opens too. The preview is only an approximation.

4. Type a number to select a look.

   You will see: `Preview selection changed to: ` and the look's name. The preview window moves too.

5. Type **U** to use the selected look.

   You will see: `Choose a numbered profile before using it.` if you have not picked one yet.

6. Confirm the look.

   You will see: `Use the selected ReShade profile?` with `[Y] Yes, use ...`, `[S] Custom preset`, and `[B] Back`. Press Enter or type **Y**. Choose a custom ReShade .ini preset only if you already have one.

7. Choose which games get ReShade.

   You will see: `Which games should get ReShade?` with `A) All ... registered game(s)` and `L) Browse and select specific games`. Type **A** for all games. Type **L** for specific games.

   Next: with **L**, you see a paged list. Type game numbers (for example `1,3,5-7`), then type **D** (here D means done).

8. If you picked more than one game, answer the apply question.

   You will see: `You selected 12 games. 9 can be changed now.` (the numbers will be yours) and `Apply ... to 9 games?` The choices are `[Y] Yes`, `[S] Select games one by one`, `[B] Back`, and `[D] Details`. Press Enter or type **Y** to apply to every game that can be changed. If some games will be left alone, you also see `Press D to see why.`

9. Read the result. See "The result screen" below.

Other keys at the look list: **N** skips ReShade with no changes, **R** reopens the preview window, **B** cancels, and **D** shows details about every look.

### Use ReShade in a game

Start a game and press the **Home** key. This opens the ReShade overlay. Turn effects on or off and adjust the sliders there.

Your settings are saved to `ReShade.ini` in the game folder.

No welcome window, counters or messages show when a game starts. Every `ReShade.ini` that TeknoParrot Manager writes turns them off, and the key that opens ReShade still works. A short ReShade version banner may still show for a moment at game start. ReShade has no setting to hide it.

### The result screen

When ReShade finishes, you will see a line like `Done: <look name> applied to <number> games.` Under it: `To turn the effect on or off, start a game and press the Home key.` If nothing changed, you see `Nothing was changed.`

TeknoParrot Manager leaves a game alone when it already has ReShade files that TeknoParrot Manager did not install. These games are listed under `Not changed:`. This protects your own setup.

When some games were left alone, missing, or unsafe, you will see a choice. It only shows the keys that apply:

```
[A] Replace that game with TeknoParrot Manager's ReShade (you choose the look again; a copy of the old files is saved, so you can undo it)
[S] Choose games one by one
[M] Open the Library Health Check to see which games could not be found
[B] Leave them as they are
[D] Details
Press A, S, B or D:
```

Type one key and press Enter. Press Enter alone to pick B.

- **A** asks you to confirm. You will see `Press Y to replace them, or N to leave them. (Y/N)`. The default is N. If you say Y, you choose the look again. A copy of the old files is saved first, so you can undo it.
- **S** goes back into ReShade setup so you can choose games one by one.
- **M** opens the Library health check (mode 13) so you can repair missing game paths. It shows only when some games could not be found.
- **B** leaves the games as they are. When there are no protected games, B means back to the main menu.
- **D** shows the full details, then asks again. Details also tell you that **A** replaces protected ReShade files, and that TeknoParrot Manager asks you to confirm before it changes anything.

When nothing needs a choice, the screen ends with `Press D for details, or Enter to return to the menu`. Type D for details, or press Enter to go back to the main menu.

### TeknoParrot's own CRT look

Some games already use TeknoParrot's own CRT look (the "native" CRT effect). Together with a ReShade CRT look, it can look doubled.

This question only appears when a game you picked already has that setting. It is asked after you choose the look and the games. You will see:

```
This game already uses TeknoParrot's own CRT look.
Together with this ReShade look, it can look doubled.

[K] Keep TeknoParrot's CRT look (default)
[T] Turn it off for this game
[D] Details
Choice, default K
```

With several games, the choice reads `[T] Turn it off for` and the number of games. If some cannot be turned off here, you also see `Press D to see why.`

- **K** (or Enter) keeps TeknoParrot's CRT look.
- **T** turns it off, only in games that get ReShade now. You will see `OK. It will be turned off only in games that get ReShade now.` and `A saved copy of your game profiles is made first.`
- **D** shows details, then asks again.

Next: after T, you will see `Next: You can undo this in ReShade > Undo ReShade changes.` Removing ReShade later does not turn the CRT look back on. To put it back, use Undo (see below) or Restore backup.

If your look is not a CRT look, or nothing can be turned off, you only see a notice: `TeknoParrot Manager keeps them as they are. A ReShade look can add to them.` Then it says `Press D for details, or Enter to continue` (one game) or `Press D at the next menu for details.` (several games).

TeknoParrot Manager keeps the game's own settings unless you turn the CRT look off. It does this in interactive runs only. An unattended run always keeps TeknoParrot's setting.

### Change your ReShade look

**For all games:**

1. Type **5** at the main menu. Type **S** (or press Enter).
2. Select the new look from the list. Type **U** to use it.
3. Press Enter or type **Y** to confirm it.
4. Type **A** for all registered games. Press Enter or type **Y** to apply it.

Next: games last set up by TeknoParrot Manager with a different look are listed. You can press **A** to change them, **K** to keep their current look, **S** to choose games, **D** for details, or **B** to go back.

**For one game:**

1. Type **5** at the main menu. Type **S** (or press Enter).
2. Select the look from the list. Type **U** to use it. Confirm it with **Y**.
3. Type **L** to browse and select specific games.
4. Type the number of that game. Type **D** (done).

Next: if the game already has an earlier look, you may be asked whether to reapply or reuse it. Default is N. Otherwise the look you picked is applied to that game.

### Undo your ReShade look

TeknoParrot Manager saves a copy each time it changes the ReShade of a game. This is what lets you undo.

1. Type **5** at the main menu. Type **U**.

   You will see: `Undo ReShade changes` and `TeknoParrot Manager changed the ReShade of these games. Newest first.` Each row shows the game, the look before and after, and the date and time.

2. To undo one game, type its number. You will see a plain-words preview of what goes back. It asks `Type YES to undo it`. Any answer other than YES cancels, and nothing is changed.

3. To undo all games, type **A**. You will see `Type ALL to undo all of them`. Any answer other than ALL cancels, and nothing is changed. A game that changed since then is left as it is.

Other keys on the undo list are **M** (more games), **D** (details), and **B** (back). The default is B.

If nothing can be undone, you see `There is nothing to undo right now.`

When the undo finishes, you will see a result and `[D] Details, or press Enter to continue`.

### Remove the ReShade files

Choose `R` from mode 5 to take away the ReShade files that TeknoParrot Manager added.

1. Type **5** at the main menu. Type **R**.

   You will see: how many verified files were found. The next list has only games with removable or protected ReShade findings.

2. Pick the games.

   You will see: `ReShade removal preview -- no changes have been made:` with `REMOVE` and `KEEP` rows. `REMOVE` rows will be removed. `KEEP` rows stay.

3. Type `REMOVE` to go on. Press Enter to cancel.

   Next: a verified backup is made first. Cancel or back removes nothing.

TeknoParrot Manager does not remove ReShade files that it did not install, or that were changed since. For those files, use the advanced troubleshooting path.

### More detail

**How removal stays safe.** Only unchanged files that TeknoParrot Manager owns, inside the resolved ReShade target, are eligible.

Immediately before backup and deletion, TeknoParrot Manager re-reads the profile and re-resolves the target. It rechecks canonical non-reparse leaf containment and the exact hash.

A verified backup is created before deletion. Bundled, preinstalled, unowned, ambiguous, changed, malformed, and out-of-target files remain protected.

The final report separates removed, already-clean, missing-path, protected, changed, malformed, rolled-back, and failed outcomes.

**The look preview.** The optional non-modal preview offers 17 profiles chosen for arcade play. They are Original (the untouched reference) plus 16 arcade looks. They are built from 12 of the 25 approved pinned shader effects.

- They are listed best first in two groups: CRT Choices, then Main Catalog.
- Each has a one-line description and a rough cost (light, medium or heavy). The cost is an estimate, not a measurement.
- No current profile needs HDR, so no HDR group is shown.
- Retired profiles named in a saved choice are reported as retired, never remapped. Their installed files are left untouched.
- Every profile except Original shows a visible difference in the preview. Edge smoothing is not visible on the still picture, as the Crisp 3D notes say.

**How the preview and the list work together.** Choose a profile from the preview drop-down or the terminal numbered chooser. Both stay synchronized in real time, even while the terminal prompt is waiting.

An effect is offered only while its recorded license evidence is complete and current. Any effect without it is withheld.

The 0-100 comparison slider and view mode remain independent of profile choice. The bundled-image preview does not run the game or execute ReShade shaders.

A preview choice is transient. Terminal `U` and the existing explicit confirmation are still required before deployment. The preview closes when the chooser returns.

**The signature check.** Before deploying, the script checks your ReShade DLLs Authenticode signature (the ReShade installer is code-signed). It warns, without blocking, if the signature is not valid.

When mode 5 downloads the installer, the log also records the authoritative source, filename/version, SHA-256, transfer metrics, signer/status/thumbprint, and final trust result. The SHA-256 is an audit hash, not a published-digest comparison.

### Advanced emergency fallback (normal users should use mode 5)

ReShade DLLs are not bundled in the release ZIP, because ReShade is not redistributed by TeknoParrot Manager.

Mode 5 can download and verify the official installer from `reshade.me`. It extracts the required DLLs and deploys them transactionally.

If the automatic source is unavailable, an advanced user may obtain the official installer separately. They place validated DLLs in `<TPRoot>\TeknoParrotManager\Assets\ReShade\`.

The installer signature is checked before any deployment. A signature or archive failure stays blocked. TeknoParrot Manager never substitutes an unverified DLL.

---

## dgVoodoo2 Legacy Compatibility

Some older arcade games use old graphics systems: DirectX 8, DirectDraw, or 3dfx Glide. On modern PCs these can cause crashes or black screens.

dgVoodoo2 is a free helper that lets those games run on modern graphics. This adds compatibility DLLs to the game folder and may add or replace dgVoodoo.conf. It does not modify the game executable.

**Only use this for games that crash or show a black screen on first launch.**

**Setup:**

1. Type **6** at the main menu and press Enter.

   Next: TeknoParrot Manager downloads and checks the official dgVoodoo2 release. It deploys only after the complete set passes validation.

2. Read the result screen.

   You will see: a result with `[D] Details` and `[O] Open support/log guidance`. Type the letter and press Enter.

**To remove:** use the dgVoodoo2 setup flow to review deployed files. TeknoParrot Manager does not delete an unowned file that could belong to another compatibility tool.

### More detail

dgVoodoo2 translates old API calls into DirectX 11/12.

TeknoParrot Manager extracts the required files in staging first.

An advanced emergency fallback may use a folder already obtained from the official source. TeknoParrot Manager still validates its layout before deployment.

---

## GPU Compatibility Fixes

Many TeknoParrot games have optional fix settings for AMD, NVIDIA, or Intel graphics cards (GPUs).

Mode 7 finds your GPU and applies the right fix to every registered game that supports one.

It is safe to run again any time you change GPU or update drivers.

The result screen offers `[D] Details`, `[O] Open support/log guidance`, `[R] Run GPU Fix again`, and `[B] Back to main menu`.

### More detail

Mode 7 auto-detects your GPU via WMI.

`GameProfiles` is scanned at runtime. Newly added games are always covered without a script update.

---

## Force Feedback (FFB) Setup

Force feedback (FFB) makes a wheel or controller push back or rumble. Mode 8 covers two independent ways to get it working. They are not mutually exclusive.

- **Native FFB Blaster** -- TeknoParrot's own built-in feature. It needs an active paid TeknoParrot membership. The script asks if you have one. Answer N and this part is skipped entirely, because the setting has no effect without a subscription.
- **Third-party plugin** ([mightymikem/FFBArcadePlugin](https://github.com/mightymikem/FFBArcadePlugin)) -- free, no subscription needed.

If a game is covered by both, the script asks **one** question for all of them. You keep native FFB Blaster for all of them, or switch to the plugin for all of them. It does not ask per game.

If a file name is already in use, the file is skipped with a warning and never overwritten. For example, ReShade may already use `d3d9.dll`.

### More detail

**Native FFB Blaster.** If you answer Y, the field is discovered dynamically by scanning your `GameProfiles` folder. It is never hardcoded.

**Third-party plugin.** The per-game DLL table is fetched live from that project's GitHub repo every run. The shared audit records its source, filename/version, computed SHA-256, and transfer metrics. No signer or published-digest trust gate is claimed.

**Removal.** TeknoParrot Manager records its own deployed hook files. When you choose native FFB for an overlap, it backs up and removes only a matching unchanged file.

Unowned or changed files remain untouched. They are reported as an advanced troubleshooting boundary.

---

## BepInEx update and setup

[BepInEx](https://docs.bepinex.dev) is a free plugin/modding add-on system for Unity games. Some games need it for controls or fixes.

Mode 9 installs or updates BepInEx for games, but only after you give your explicit approval to install or update.

Nothing is installed silently into every game.

If a game folder is unsafe or the network cannot be reached, TeknoParrot Manager explains that no change was made. It then offers the automatic retry path.

The prompt is `[Y] Install/update  [B] Back  [N] Cancel`. There is no repair-reset choice. After a successful or no-change run, the screen waits for one Enter.

The failure screen offers `[D] Show details`, `[O] Open support/log guidance`, `[B] Back to main menu`, and `[R] Try BepInEx setup again`.

### More detail

TeknoParrot Manager chooses the stable x64 or x86 package from the game's executable. It downloads it with digest validation. It backs up the existing fixed BepInEx tree, and rolls back on a failed promotion.

Manual deletion of BepInEx files is not the normal workflow. TeknoParrot Manager only removes the fixed files it can verify as part of its own approved transaction.

## Required game patches

Menu 12 fixes a missing file in certain game builds.

It only uses ZIP files that are already on your computer. It never downloads patch files.

It makes a backup before it changes anything. It also keeps what it needs to undo the change.

**To use it:**

1. At the main menu, choose **option 12**.
   You will see: `Required game patches` and four choices: **A**, **M**, **U** and **Q**.
   Next: type **A** to check the games you registered.

2. Automatic mode (**A**) checks your registered games. Games with the same result share one line, for example `Already installed, nothing to do: Hummer Extreme Edition.`
   You will see: `Ready to install 14 patches for 1 game`, then `Press Y to install, D for details, or Enter to cancel`.
   Next: press **Y** to install. Press Enter to change nothing.

3. Manual mode (**M**) fixes one game that is installed but not registered. Each game is listed once, with its patch count, for example `Hummer Extreme Edition (14 patches)`.
   You will see: `Pick your game:` and `Type the number of your game, or D for details`.
   Next: type the number of your game, then choose the folder where it is installed. You are asked for the folder once, not once per patch.

4. Choosing a game folder does not register or change the game.
   Next: nothing is changed until you press **Y** to install.

**Messages you may see:**

- `None of your registered games has a patch in this list. Nothing was changed.`
  This means none of the games you registered has a patch here. If a game is installed but not registered, choose **M** and pick its folder.
- `Nothing was installed. Fix the problem above, then try again.`
  This means a check stopped the fix. The reason is above this line in plain words, for example that the ZIP file was not found. Fix that and try again. This line is not shown when everything was already installed.
- `Already installed, nothing to do`
  This means the game already has the patch. You do not need to do anything.

At the last question, press **D** to see the technical details: patch names, the exact reason, result codes, and the folder with your undo copy. They are also kept in the log.

"No match" does not mean the game needs no fix. Your build may simply not be covered.

A successful patch does not prove the game is ready. Register the game, set up its controls, start it through TeknoParrotUI, and check that it plays.

[Beginner explanation](docs/START-HERE.md#8-required-game-patches-menu-12).

### More detail

**Infinity Blade FX 1.02**

- It has two independent missing-file repairs, for Binaries/Win32/matrix32.dll and Binaries/Win32/dinput8.dll.
- Both need matrix32.TEKNOPARROT.dll and TPFIX.ini to be present in that directory.
- Presence does not validate their bytes or configuration.
- TeknoParrot Manager does not rename the original library, edit TPFIX.ini, or choose the first-launch TeknoParrot.dll path.
- Compatibility and gameplay remain separate checks.

**What this release contains**

- RC8.1 has 120 exact recipes across 71 exact ProfileId/build/executable identities (54 game profiles).

- The list started as the historical 13-entry baseline and the 58-entry PR #355 checkpoint, and has grown since.

- Later additions include MaiMai GreeN `freeglut.dll` and `libcurl.dll`, Rabbids Hollywood `RabbidsHollywood_Operator.exe`, and Cross Raid 1.05 Ver A `rom/shader.farc`.

- The existing 58-entry checkpoint includes three Taisen Hot Gimmick 5 (2.04) restores.

- It also has three user-selected plugin restores (Mars Sortie 1.46.9, the separate Rabbids Hollywood operator plugin, and SB3 1.91 x64).

- It also has five native recipes (Cross Raid 1.05, VF5R 1.001, and Sonic Dash Extreme), 30 Hummer/Hummer Extreme/Primeval Hunt components, two SB3 FMOD components, and two Infinity Blade FX 1.02 components.

- The MaiMai DLLs are separate transactions.

- The Rabbids utility is separate from the existing Assembly-CSharp and BepInEx operator-plugin recipes. TeknoParrot Manager does not execute it or edit registry or `.conf` state.

- One hundred eight `CreateFile` operations create only absent targets. Twelve `ReplaceFile` operations require the exact known before-state.

- Exact-after files are skipped. Other states are refused.

- This exact-component scope is not full semantic guide coverage.

**More recipes**

- Two further TMNT 1.59 Main recipes independently restore only absent OrenVid.dll and PK-UnityPlugin.dll under TMNT_Data/Plugins/x86_64/.

- They do not install BepInEx or change configuration.

- Setup, controls, launch and gameplay still require separate verification.

- The source follow-up also adds four independent KOF Maximum Impact Regulation A Main restorations (d3d8.dll, d3d9.dll, ddraw.dll and wined3d.dll).

- It also adds the exact MKDX USA 1.06 Main D3D11Ref.dll restoration.

- Each creates only an absent target and preserves unknown existing bytes.

- These repairs do not prove graphics compatibility, setup or gameplay.

**Hummer, Primeval Hunt and SB3**

- The 30 Main restorations do not establish Hummer Extreme frame-count behavior, Primeval Hunt `ElfLdr2` copy identity, or its modern NVIDIA fog behavior.
- SB3's two FMOD files are separately restored only when absent.
- Their DLL version, pair compatibility, audio, and full setup readiness remain unverified.
- The two FMOD operations are not an atomic pair.

**Taisen**

- The Taisen files are restored only when absent.
- Configure and save keyboard keys with `TTX-Config.exe`, then use `TTX-Loader.exe` as directed by the guide.
- TeknoParrot Manager does not configure keys or run either utility. Setup and game launch remain separate.

**Automatic and manual mode checks**

- Automatic mode lists eligible registered games for one confirmation.

- Manual mode can patch an already-installed game folder without registering it.

- TeknoParrot Manager checks the exact build, executable, local ZIP member, prerequisites and target bytes.

- The three added plugin recipes require exact-named local patch ZIPs. The prompt identifies them as patch ZIPs, not Main game ZIPs.

- All seven BepInEx plugin targets require core-file presence, not a BepInEx version check.

- Family Guy additionally requires the documented `[Preloader.Entrypoint] Type=MonoBehaviour` setting.

- SB3's Main ZIP already contains the plugin bytes. Its recipe restores only an absent installed target.

- The two FMOD component recipes separately restore missing `fmod64.dll` and `fmodstudio64.dll` from the exact Main ZIP.

- Their DLL version and pair compatibility remain unverified. This does not establish complete SB3 setup or audio readiness.

**Graphics-vendor and special recipes**

- Elysion, Cross Raid 1.05, and VF5R 1.001 each require exact build/executable, unambiguous AMD/NVIDIA evidence, and the selected recipe's exact before-hash.

- Cross Raid's AMD/NVIDIA variants share a common known before-state.

- VF5R's variants also share a common known before-state, not an opposite-vendor state.

- Cross Raid vendor source documentation says 1.05, not the `Ver A` suffix. The matching profile/build is not runtime compatibility proof.

- Separately, the exact 1.05 Ver A Main `rom/shader.farc` restoration creates only when absent.

- Vendor undo restores base bytes into a new file object. The earlier base-create receipt refuses undo on changed identity and preserves those bytes.

- No other Cross Raid build is enabled.

- Sonic is explicit opt-in, exact-before/after self-executable replacement with guarded transaction identity and receipt-bound undo. It does not prove a 60-fps outcome.

- Silent Hill's codec BAT is not run or installed.

- Register, configure controls, launch through TeknoParrotUI, and verify gameplay separately. A successful patch does not prove readiness.

---

## Region Setup

Some games can start in a country you pick, like USA or Europe. It changes things like the language. Games left on `Auto` or `Default` usually start as Japan.

Region setup sets that country for you. You do not have to open each game in TeknoParrotUI.

- **After you register new games**, TeknoParrot Manager asks once: `Which country do you want your games to start in?` Type the number of a country, or **0** to leave every game as it is. It does not ask in a preview or an unattended run.
- **Any time**, choose **10** at the main menu.

**Using Region setup (menu 10):**

1. At the main menu, type **10** and press Enter. You will see a numbered list of countries. Each one shows how many of your games offer it, for example `1) USA (12 games)`.
2. Type the number of a country. Or type **A** for `Back to automatic` (the games go back to their normal setting). Or type **0** to go back and change nothing.
3. You will see `These games can be set to ...` and a list of games. Each shows its current region, for example `(now: Auto)`. Type **A** to take all of them, or **L** to pick some of them.
4. You will see how many games will change. Next: type **Y** to change them, or **N** to stop. The default is **N**.
5. TeknoParrot Manager saves a restore point of your game settings first, then makes the change and reads each game back to check it.
6. Read the result, for example `Region set to USA for 3 games.` Type **D** for the game-by-game details.

**What it will and will not do:**

- Only countries your games really offer are listed. A game never gets a region it does not have. A game that does not offer your choice stays as it is.
- A region you chose earlier is kept after a registration. It is only replaced when you change it yourself in Region setup.
- Some games have only countries in their list (JAPAN, USA, EXPORT) and no automatic choice. The question after registration does not change them. `Back to automatic` names them as having no automatic choice and leaves them as they are.
- It changes the game's `Region` setting. For games with `PcbRegion` and `DongleRegion`, it changes both together.
- It does not change a true/false export setting, or a region typed in as free text (about 6 games).
- Online play still uses the automatic region. Region setup does not touch it.

---

## PostgreSQL setup

Some Incredible Technologies games need a local PostgreSQL 8.3 database. A database is a small store of game data that runs on your PC.

These games include Power Putt Live (2012/2013), Silver Strike Bowling Live, Target Toss Pro (Bags / Lawn Darts), and Orange County Choppers Pinball.

Mode 11 finds which of your registered games need it. If none do, mode 11 says so and exits at once without installing anything.

**What mode 11 does for you:**

- PostgreSQL not installed yet: TeknoParrot Manager installs it when a registered game needs it.
  You choose the service-account and database passwords at masked confirmation prompts.
  If Windows permission is needed, TeknoParrot Manager asks Windows itself. It continues the same setup after you approve.

- PostgreSQL already installed: TeknoParrot Manager keeps your existing data.
  If the saved password no longer works, it explains the problem.
  Next: choose `F` and type the password PostgreSQL already has. TeknoParrot Manager checks it and saves it. Nothing in PostgreSQL is changed.

- Nobody knows the password: choose `X` ("I do not know the password"). `X` is offered only after PostgreSQL has really refused the password.
  `X` explains why TeknoParrot Manager cannot reset the password for you. It shows manual steps under `D`. Nothing is changed by choosing `X`.

- Windows permission declined, or a repair step cannot finish: TeknoParrot Manager keeps any protected retry information it already saved and offers a retry.
  Your password is never shown in commands, logs, or messages. No database data is deleted.

**What you will see when it finishes:**

1. A short result screen starts with `PostgreSQL setup finished.`
2. Next is a count line, for example `Games set up: 3. Databases created: 1. Already set up: 2.`
3. Below it are short lines about your games. Games with the same result share one line, with names joined as `A, B and C`.
4. Then you see `Next: open TeknoParrot and start any game. Every game database was checked and is ready.`
5. Last, you see `[D] Show details` and the prompt `Press Enter to return to menu, or D for details`.

Next: press Enter to go back to the main menu. Or type D and press Enter to see the details.

If you type D, the details appear and then `Press Enter to return to menu.` asks you to press Enter.

**What the game lines mean:**

| Result for a game | What you see (one game) |
| ----------------- | ----------------------- |
| The database was already there | `Ready: {name}. The database was already there and was checked.` |
| Created from the game's own backup | `Ready: {name}. The database was created from the game's own backup and checked.` |

"Checked" means TeknoParrot Manager connected to the database with the settings saved in the game's own profile and found its tables. If a game has no starting database file (`pg_backup`), setup leaves that game out, sets up every other game, and names it on the result screen as `Could NOT be made ready` with the reason `No starting database file came with this game, so its database cannot be built.` The run is then shown as needing attention.

If several games share a result, the line uses plural words, for example `Ready: {list}. The databases were already there and were checked.`

Some games may keep their own PostgreSQL password or settings. Then you see a yellow line: `1 game kept its own PostgreSQL password or settings, so TeknoParrot Manager did not change it.` (or `{N} games kept their own PostgreSQL password or settings, so TeknoParrot Manager did not change them.`).

That line ends with `Press D to see which.` Press D at the prompt to see which games.

**If setup does not finish:**

- You see `PostgreSQL setup did not complete successfully:` and a plain sentence about your data, for example `Setup stopped. Everything was put back the way it was, and checked.` or `PostgreSQL setup stopped before changing any databases or profiles.` Then you see `Press D to see why, or Enter to continue`.
- If the PostgreSQL install itself fails after the Windows installer ran, you see `PostgreSQL did not finish installing. Parts of it may now be on this PC. Your games and game settings were not changed.` Then: `Next: open View Log, then choose PostgreSQL setup again. If setup then lists PostgreSQL items it found, read the warning on that screen before you delete anything.` If it stopped before the installer ran, you see `PostgreSQL was not installed. Nothing was changed.`
- If setup lists PostgreSQL items that were already on this PC, you see `These PostgreSQL items are already on this PC. TeknoParrot Manager has no record that it made them, so it did not remove or change any of them:` Then you see the list and `Do not delete anything on this list unless you are sure what it is.` A PostgreSQL folder can hold game databases and saved scores, and deleting it erases them for good. Copy the folder to a safe place first, and ask someone who knows computers if you are not sure.
- If a rebuild (`[I]`) does not finish, you see `The rebuild did not finish.` and one plain sentence about your data. Then you see `Press D for details, or Enter to continue`.

### More detail

**The details screen (D)**

- It starts with `Details` and a gray note: `TeknoParrot Manager checked each database by connecting to it with the game's own settings. It did not start any game.`

- A `Summary` block gives the result, for example `PostgreSQL setup finished. Every game database was checked and is ready.`

- When nothing needed doing, it says `No PostgreSQL setup changes were needed. Every game database was checked and is ready.`

- A `What setup checked` block says setup connected to each game's database with the settings saved in that game's profile and counted its tables.

- One block per game gives `Database:`, `Profile:`, `What happened:` and `What it means:`.

- An `Other notes` block lists anything that belongs to no single game, such as the profile names that kept their existing password.

- A `What to do next` block appears only when something went wrong. It says to fix the problem the details name, then run setup again.

- A `Totals` block ends the screen with `Games set up` (the same number as on the first screen), `Fields updated`, `Databases created` and `Profiles unchanged`, plus `Errors: {n} (see TeknoParrot-Manager.log)` if there were errors. `Fields updated` is the same number as `Games set up`, and `Profiles unchanged` is the same number as `Already set up` on the first screen.

**Details are kept in the log**

- Everything the screen shows is also written to the log, one line per item.
- The automatic repair that runs in a protected helper window shows the same screen with no `[D] Show details` line and no prompt. Its yellow line then ends with `The log says which.`

**Recovery rules**

- TeknoParrot Manager does not change the postgres password or edit pg_hba.conf. The password choices never delete, recreate, or restore over a database, and it does not wipe PostgreSQL data on its own. Two choices that you confirm yourself do replace database content: restoring a saved PostgreSQL backup (mode 14) and the Reinitialize choice `[I]` on the backup-failure screen. Each asks you to type YES first.

- Before it changes game database data, it creates and verifies a protected recovery backup.

- It asks Windows for permission when needed.

- After you type the password, TeknoParrot Manager updates only affected game setup files (profiles) whose connection values are not already correct.

- The TeknoParrotUI Pass field remains plaintext because TeknoParrotUI reads it directly. Already-correct profiles are skipped.

- Recovery evidence and database backups are created before profile population.

- Any backup, database, or profile-write failure stops setup.

- The PostgreSQL guide download is logged with source, filename/version, SHA-256, and transfer metrics. This path does not claim Authenticode or published-digest verification.

---

## Check for Updates

Mode 15 checks GitHub for the latest release and compares it with the version you are running.

Nothing is downloaded or changed unless you say Y.

**To update:**

1. Choose mode 15 to check for updates.
   You will see: the result of the check and a Y/N question.

2. Type Y. TeknoParrot Manager does four things:
   1) Downloads the update and checks that it is the real file.
   2) Checks what is inside it.
   3) Backs up every file it replaces, in the `UpdateBackups` folder.
   4) Installs it and checks it.

3. You see `Update installed and verified. Restart TeknoParrot Manager to use it.` Start `TeknoParrot-Manager.bat` again yourself.

Your own files, `UserProfiles` and backups are never touched or deleted. If any file cannot be replaced, every file is put back and nothing changes. If the drive is too full, it says `There is not enough free space for the update` and installs nothing.

**Using a build before RC8.1 (for example RC8 or RC7)?** Those builds cannot update in place. Install RC8.1 by hand once: after RC8.1 comes out, download the complete ZIP from [GitHub Releases](https://github.com/Jumpstile/teknoparrot-manager/releases) and extract all of its files over your TeknoParrot Manager folder. Do the same if the check is unavailable.

The separate tool `tools\Invoke-TpmAutoUpdate.ps1 -Apply` still refuses a release with many files and changes nothing.

### More detail

**Checking the download**

- Both mode 15 (including an approved startup update) and `tools\Invoke-TpmAutoUpdate.ps1 -Apply` require GitHub's `sha256:<64 hex>` asset digest.
- They verify the downloaded ZIP before opening it or changing your installed copy.
- Missing, invalid, or mismatched digests stop installation and remove the rejected download.
- This detects mismatch with GitHub's stored asset, not a compromised publisher.

**Single-file release ZIP**

- Only for a single-file release ZIP does the updater back up the current script, validate the candidate, and replace the script.
- The backup goes to a new `UpdateBackups\TeknoParrotManager_<timestamp>\` folder, never reused. A second backup in the same second gets `_2`, `_3`, ... added.
- An approved update may temporarily clear only the target file protection after digest verification. It restores it after the attempt. (The standalone `tools\Invoke-TpmAutoUpdate.ps1` instead names its backup folder `<yyyyMMdd-HHmmss>_<id>` and refuses a read-only target.)
- Any failure says what went wrong and whether a backup was made.
- The download log records source, filename/version, SHA-256, and transfer metrics.

---

## LaunchBox Integration

At the end of most normal interactive runs, you see this menu:

```
Optional: add games to LaunchBox.
[P] Preview first. No changes.
[A] Add missing games (backed up).
[F] Import file only. No changes.
[B] Skip this step.
  Choice, default P
```

What each key does:

- `P` previews without changing LaunchBox. It reads your LaunchBox files, asks which platform, shows the plan, then returns to this offer.
- `A` adds games that are missing from LaunchBox's own library. It tells you to close LaunchBox and BigBox first (TeknoParrot Manager will not close them), asks `Add the missing games to LaunchBox now? (Y/N, D = about the risks)` (default N), then the platform, then shows the plan and asks `Write exactly these changes after a verified backup? (Y/N)` (default N). Entries that are already there are kept as they are.
- `F` creates the reference file without a LaunchBox write.
- `B` skips the optional LaunchBox step.

The first time you use direct integration, choose how games should appear:

1. **Arcade** (existing platform)
2. **TeknoParrot** (separate platform; default)
3. **Both** Arcade and TeknoParrot
4. **Custom** platform name (offered for apply, not preview)

You are asked each time you run it; your choice is not remembered.

New entries have no box art or metadata yet. Use LaunchBox's own "Search"/re-scrape per game.

Prefer not to let the script touch LaunchBox directly? Choose `F` for the manual `TeknoParrot-LaunchBox-Import.xml` file and wizard instructions.

---

## Post-1.0 plugin scope

HyperSpin-specific core logic, settings, menu entries, guidance, and exports are excluded from TeknoParrot Manager 1.0.

Any optional HyperSpin plugin is deferred until after TeknoParrot Manager 1.0. It is not part of this release.

---

## RetroBat / Batocera

On first run the script asks:

```
Use RetroBat folder naming? (Y/N, default N)
```

Answer **Y** and game folders are extracted as `GameName.teknoparrot` instead of `GameName`.

Registration and fuzzy matching work the same way, because the suffix is stripped before any comparison. The script also recognizes `.parrot` and `.game` suffixes from other tools.

The answer is saved and never asked again.

**To switch an existing library:**

1. Start TeknoParrot Manager.
   You will see: `Use these settings? (Y/N, D = show them)`.
2. Answer **N** to decline the saved settings.
   Next: the first-time questions appear again.
3. Choose the intended mode.

### More detail

- Preserve configuration, extraction state and game backups before advanced changes.
- Existing-folder detection may retain old names.
- Do not delete state to force a populated-library conversion.

---

## Preview / Dry-Run Mode

Before AutoSync or Register actually writes anything, the script offers this menu:

```
[P] Preview (default) -- show what would change; no game or profile changes
[R] Run now -- back up UserProfiles first, then make the changes
[B] Back
Choice, default P
```

UserProfiles is TeknoParrot's saved game settings folder.

**To preview first:**

1. Press Enter for P (or pass `-DryRun` on the command line).
   You will see: the planned extraction, registration, repair, and control copying. No game or profile changes are applied.

2. At the end you see the question `Do you want to make these changes for real now?` with `[D] Details` next to Y and N.
   Next: choose Y or N, or D to read the details first.

3. Choose Y to scan again and then apply the changes.
   Applying performs a fresh scan and uses the same game selection the preview used.

4. Choose N to return to the main menu. Nothing is changed.

Preview mode skips the LaunchBox export offer, the thumbnail download offer, and the GPU fix offer too.

Those are writes themselves, so they make no sense after a run that changed nothing.

### More detail

- Scans, configuration handling, and logging still occur in preview mode.

---

## Unattended Mode

Unattended mode runs without asking you any questions. In this release it does one job only: the read-only Library Health Check. It does not extract games, register them, copy controls or download thumbnails, so it cannot run AutoSync or Register only on a schedule.

To use it:

1. Run TeknoParrot Manager once yourself so your settings are saved.

2. Add `"UnattendedMode": "HealthCheck"` to the saved settings file, `TeknoParrot-Manager.config.json` in `<TeknoParrotRoot>\TeknoParrotManager\State\`. An ordinary save from the menus keeps this value.

3. Start it with `-Unattended`:

```powershell
.\TeknoParrot-Manager.ps1 -Unattended
```

Without saved settings you see `ERROR: Unattended mode requires saved settings.` Without `UnattendedMode` (or with any other value) you see `[Unattended] Mode must be set before starting.` and the run ends with exit code 1. Restore mode and Postgres setup are not available unattended.

Exit code 0 means the check finished, even if it found problems in your library. Exit code 2 means some checks could not finish.

**Scheduling the Health Check with Windows Task Scheduler:**

1. Run interactively once to save your settings, then add `UnattendedMode` as described above.

2. Open Task Scheduler (`taskschd.msc`) and create a new Task.

3. General tab: set a name, check "Run whether user is logged on or not" and "Run with highest privileges".

4. Triggers tab: set your preferred schedule.

5. Actions tab: set Action to "Start a program".

6. Set Program to `powershell.exe`.

7. Set Arguments to `-ExecutionPolicy Bypass -NonInteractive -File "C:\path\to\Scripts\TeknoParrot-Manager.ps1" -Unattended`

8. (Optional) Conditions tab: if your games are on a network drive, "Start only if the following network connection is available".

Next: check `TeknoParrot-Manager.log` after each scheduled run. To extract or register games, run TeknoParrot Manager yourself from the menu.

---

## Thumbnail Download

After registration the script asks:

```
Download the missing game pictures? (Y/N, D = use your own pictures)
```

Answer Y to fetch ProfileCode.png for every registered game not already in <TeknoParrotRoot> Icons. Press D to see how to use your own pictures instead.

The pictures come from TeknoParrotUIThumbnails on GitHub. Missing games are skipped without error.

**Custom thumbnails:**

1. Create `<TPRoot>\TeknoParrotManager\Assets\CustomThumbnails\`
2. Name each image `ProfileCode.png` -- e.g. `Daytona3.png`, `HouseOfDead4.png`
3. Run the script and answer Y to the thumbnail prompt. Your images are copied to TeknoParrot's Icons folder.

Files already present are never overwritten.

**Finding a game's profile code:** after any run, open `TeknoParrot-Manager-controls.txt` in `<TeknoParrotRoot>\TeknoParrotManager\Reports\`. Every registered game is listed with its exact profile code.

### More detail

- The shared audit records source, filename, SHA-256, and transfer metrics.
- No published digest or signer trust gate is claimed for icons.

---

## Restoring a Backup

**To put back an older saved copy:**

1. At the main menu, choose **mode 14 -- Restore backup**.
   You will see: the "Restore from Backup" screen with four choices, numbered 1 to 4.

2. Pick which kind to restore:
   - **1) TeknoParrot UserProfiles backup**
   - **2) Postgres database backup** -- only relevant if you've used Postgres setup (mode 11); this replaces the _current_ content of each database restored
   - **3) LaunchBox library backup** -- only relevant if you've used direct LaunchBox integration
   - **4) Reset and Restore** -- put back one game or all games from a restore point saved when TeknoParrot Manager started

3. Pick the backup you want by its number.
   You will see: the list of backups, **newest first**.
   Next: check its date and time, and think about the later settings you would lose.

4. Confirm the restore.
   UserProfiles and database restores ask you to type `YES`. Reset and Restore also asks for `YES` (and `ALL` when restoring all games).
   LaunchBox asks Y/N (default N) and first verifies a backup of the current library.

5. If TeknoParrot Manager says TeknoParrot or LaunchBox/BigBox must be closed, close that application.
   Next: press Enter when TeknoParrot Manager asks it to check again.
   It resumes the same restore choice. You do not restart the whole workflow.

6. When the restore ends, press Enter to return to the menu.

7. Re-open TeknoParrot (or LaunchBox) to use the restored data.

Keep any current settings you still need somewhere outside the folders being restored. A restore replaces them.

### More detail

**What the newest-first lists look like**

- UserProfiles backups: the heading is `Saved copies of your game settings, newest first:`. Each row looks like `<kind and time> - 12 files`. Press D for details such as the folder name.
- A row ends with `- older copy, cannot be fully checked` when the folder has no completion record. You then see `This copy cannot be checked. TeknoParrot Manager cannot be sure it is complete.` and `Games that are missing from it will be removed.` You must type `UNVERIFIED` to use it anyway.
- Postgres backups: the heading is `Available Postgres database backups (most recent first):`. A row ends with `[INCOMPLETE - cannot be restored]` when it cannot be used.
- LaunchBox backups: the list is sorted newest first. Each row has a label such as `[taken before a write] library: {path}` or `[safety snapshot taken before a restore] library: {path}`.
- Reset and Restore: the choices that let you pick a restore point open a list headed `Restore points, newest first:`.

**Prompts and results**

- For UserProfiles you pick with `Enter number to restore, or Enter to cancel`. Enter or B cancels with `Restore canceled.`

- UserProfiles restore warns `Warning: this replaces ALL your current game settings with this saved copy.` and asks `Type YES to confirm`.

- If TeknoParrot is still running, the restore stops safely and your selected backup is unchanged.

- The Postgres restore warns that it will `REPLACE the current content of each database listed above with this backup snapshot`. It asks for your PostgreSQL password if the saved one does not work.

- If the Postgres restore did not simply succeed, you see a plain line that starts with `The restore did not finish.` or `Restore stopped before changing any databases.` Then you see `Press D for details, or Enter to continue`.

- When a restore finishes, a banner shows the outcome. Then `Press Enter to return to menu`.

---

## Library Health Check

Mode 13 begins with a **read-only** assessment. It looks at your setup and does not change anything.

It explicitly says that it checked your setup and did not change anything. Confirmed follow-up actions may write changes.

It reports how many game paths are valid, broken or empty, and counts of games that use extra tools.

**Fixing broken saved paths:**

1. Read the result screen. It offers **R** automatic repair (a search of known folders, plus your confirmation).
2. Choose **M** to repair manually. You select the exact executable; the program never guesses.
3. Choose **S** to search another game folder. The search checks only known game folders and never changes a valid path.
4. Before a confirmed path repair, it creates a complete backup of your game setup files first.

No repair or setup starts until you choose an action.

It also checks every game database. A database that is missing, cannot be opened with the game's own settings or has no tables shows as `Problem - <game>` under **D**. Next: run Postgres setup (menu 11).

The screen can also offer **P** PostgreSQL setup when needed. It offers direct **5** ReShade, **6** dgVoodoo2, **7** GPU Fix, **8** Force Feedback, and **9** BepInEx actions.

**D** shows details. **B** returns to the menu.

### More detail

- The report lists valid/broken/empty `GamePath` counts with affected profile codes.
- It also reports GPU fix / FFB Blaster / dgVoodoo2 / Postgres coverage, and informational ReShade / BepInEx counts.
- Third-party FFB plugin coverage isn't included here because checking it needs a live lookup. Choose **8** for that instead.

---

## Fuzzy Matching and Dat Integration

### Fuzzy Matching (NESiCAxLive and shared-exe platforms)

Some games share one program file. For example, all NESiCAxLive titles use `game.exe`.

For these games, the script compares the game folder name to every candidate game setup file and gives each a similarity score.

| Score   | Action                                                                         |
| ------- | ------------------------------------------------------------------------------ |
| >= 0.72 | Auto-registered and shown in cyan -- spot-check                                 |
| >= 0.40 | Presented in TeknoParrot Manager for an explicit candidate choice; unresolved cases remain in ACTION REQUIRED |
| < 0.40  | Listed in ACTION REQUIRED with full candidate list                             |

Before comparing, folder names are cleaned up. Years like `(2012)`, region codes like `(JPN)` and bracket notes like `[NESiCAxLive]` are removed.

Meaningful names like `(Special Edition)` are kept because they may distinguish two titles.

**Wrong match?**

1. Make a verified backup of the affected UserProfile outside UserProfiles, including bindings and settings you need.
2. Confirm the correct official profile and executable.
3. Use a validated TeknoParrot Manager candidate when offered, or configure the correct profile and GamePath in TeknoParrotUI.

Do not delete XML merely to retry.

### More detail

- All of these are stripped before comparison: years like `(2012)`, ISO dates like `(2015-12-28)`, decimal versions like `(2.10.00)`, region codes like `(JPN)`, version strings like `(ver 1.1)`, and bracket metadata like `[NESiCAxLive]`.
- `forceArchetype` selects a control reference and does not change registration matching.

### Dat File Integration

A dat file is a list of known game names. It helps the script recognize your game folders.

During initial setup the script asks:

```
Optional: download the DAT index (a list of game names, no games)?
D = download it (default), or B = browse for a DAT file I already have
N = skip for now (it asks again next time)
Choice (D/B/N, default D)
```

Both the collection dat and supplementary dat are read directly from inside the ZIP -- no extraction needed.

The supplementary dat takes priority for any game in both (it represents the version you should install).

On repeat runs, the script reuses your last dat choice automatically but offers to check for a newer dat release first.

The dat resolves three registration scenarios that would otherwise require manual action:

- **Shared-executable games** (NESiCAxLive, etc.) -- disambiguated instantly by folder name
- **Games with no profile match** (pcsx2x6, ELF-based Lindbergh titles) -- found by normalized folder name in a second pass
- **Slightly misnamed folders** -- fuzzy scan of all dat entries

Games registered via dat are shown as `Registered (dat)`. The log also says whether the match was exact (`dat/exact`) or by similarity (`dat/fuzzy`).

If you use the Eggman DAT ZIP, TeknoParrot Manager asks `Check for a newer Eggman dat release? (Y/N)` each time you start it by hand. Answer `N` to keep the ZIP you already have.

### More detail

**Where the dat data lives**

- Eggman recognition data is separate from TeknoParrotUI's `ParrotData.xml` and DAT/XML setting.

- It is also separate from the main/supplementary game ZIP sources and the staging/install folder.

- The normal first-run download goes to `%LOCALAPPDATA%\TeknoParrotManager\Eggman` without a save-location prompt. The browse/import choice remains available for an existing local file.

- A later explicit update reuses a valid configured ZIP at its existing location without an alternate-location save dialog.

- Every supplied, previously configured, or user-selected destination is canonicalized and revalidated before reuse, download, or write.

- Unsafe destinations are rejected before network/download work begins.

---

## Action Required Summary

At the end of every run, the script prints a list of everything that still needs your attention.

It also saves the list to a text file. The default is `TeknoParrot-Manager-ActionItems.txt` in `<TeknoParrotRoot>\TeknoParrotManager\Reports\`. A Save dialog lets you pick somewhere else.

Each section below has a name and a plain meaning:

| Section                          | Meaning                                                                                                                                                                                                                                                                                                          |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **GAME FOLDERS NOT RECOGNIZED BY TEKNOPARROT** | Folders whose executables matched no profile in the TeknoParrot GameProfiles folder, so they were not registered -- make sure TeknoParrot is up to date and TeknoParrotUI has been opened once (TeknoParrot Manager does not update or open it), then run Register only again; if still unmatched, they may be unsupported games or utilities/launchers |
| **REGISTER THESE GAMES IN TEKNOPARROTUI** | Shared-exe games below confidence threshold -- choose a validated candidate in TeknoParrot Manager, or leave it unresolved for TeknoParrotUI |
| **FIX THESE GAME PATHS IN TEKNOPARROTUI** | Profiles with broken paths that couldn't be auto-repaired -- open TeknoParrotUI and point each to the correct folder |
| **EXTRACT THESE GAMES FIRST, THEN RE-RUN REPAIR** | Profiles pointing at unextracted games -- extract, then re-run and answer Y to the path repair question |
| **CONTROLS NOT READY : (game code)** | Registered games whose catalog-backed controls are **Missing**, **Not verified**, **Unsupported**, or **Unknown**. Registration, a successful launch, and TeknoParrot wizard completion do not verify controls. Open TeknoParrot controls configuration and map/test controls before treating the game as ready. |
| **Additional informational game notes** | Special setup notes from the community compatibility database are written to a separate notes file. The report names its path |
| **FILE VERSION MISMATCH -- THESE GAMES NEED A SPECIFIC OLDER FILE** | A game needs a specific older version of a file; the screen says which file |
| **PATH TOO LONG -- THESE GAMES MAY FAIL TO LAUNCH** | The game folder path is too long; shorten it yourself |
| **(EMULATOR NAME) FIRMWARE NOT INSTALLED** | Registered games whose emulator (PCSX2x6, Chihiro/CxbxR, RPCS3 for PlayStation 3) needs startup files TeknoParrot itself doesn't provide -- says which games will not start and gives one next step. If the files are in your own collection (the "[EMU]" archive, for example the PlayStation 3 firmware ZIP), it offers to copy or install them after checking them against the Eggman DAT list; it never downloads or redistributes them and never replaces a different file without asking. Play! games are also checked for their own settings file |
| **(EMULATOR NAME) EMULATOR COMPONENT NOT FOUND** | A contract-backed required emulator component is missing at its expected path. Shows the contract/detector evidence and affected profiles. Use the normal TeknoParrot installation/update process; TeknoParrot Manager does not diagnose why it is missing or repair, download, reinstall, or modify TeknoParrot |

---

## Good to Know

- AutoSync backs up the current UserProfiles contents before extraction. Preview mode skips this backup. Nothing is ever deleted automatically.

- If the backup cannot be created or completed, AutoSync does not proceed with extraction.

- You must own or otherwise have lawful rights to the original arcade PCB and any ROM/game data you use. TeknoParrot Manager does not provide, distribute, or endorse unauthorized game files.

- If an extraction is interrupted (Ctrl+C, power loss, disk error), TeknoParrot Manager preserves evidence and may require attention before retrying. Review Details and the log. Do not delete a state marker merely to bypass the warning.

- Fuzzy name matching auto-registers most NESiCAxLive and other shared-exe games. The similarity score is shown for spot-checking.

- Existing button bindings are preserved. Game-specific controls that don't exist in the reference game are left for manual setup and reported in ACTION REQUIRED.

- After every real run, `TeknoParrot-Manager-controls.txt` is written to `<TeknoParrotRoot>\TeknoParrotManager\Reports\`. It lists every game, its control family, where the controls came from, how many buttons are bound, and any buttons still set manually.

- This file is not proof that controls work. Check the ACTION REQUIRED controls status, and map/test the required controls before treating a game as ready.

- After registering, the script offers to repair any broken game paths automatically.

- When you start TeknoParrot Manager with saved settings, you see the question `Use these settings? (Y/N, D = show them)`.
  Y prints `Using your saved settings.` and carries on.
  N asks the first-time questions again.
  D shows the saved settings list, then asks again.

### More detail

- TeknoParrot Manager may correct the InputAPI setting without rebinding buttons.

- The controls file is a propagation inventory (its propagation source and bound count per game), not proof that controls have been verified.

- To fix a mis-classified control family (e.g. FamilyGuyBowling auto-detected as driving when it should be trackball), add it to the `familyOverride` section of `TeknoParrot-Manager.overrides.json`.

- A Postgres Pass is filled in only for affected profiles whose Pass is blank, after a verified backup. Values that already match the approved password are skipped. A profile with its own password or other settings is changed only if you choose to replace it when asked; the default is to keep it.

- The log also records a download audit trail.

- For ReShade, it records the installer source/filename/version/SHA-256 plus Authenticode signer/status/thumbprint/trust result.

- For BepInEx, it records the GitHub source/filename/version/SHA-256 plus digest validation when available.

- dgVoodoo2, FFBArcadePlugin, Eggman/RomVault dat, the PostgreSQL guide, the TeknoParrot Manager update package, and TeknoParrotUI thumbnails are logged with source/hash/transfer audit fields.

- Transfer method, size, elapsed time, and average MB/s are included.

- Sources without a published digest or signing anchor are not described as cryptographically authenticated.

---

## Quick Fixes

For nothing found, unmatched games, missing/old profiles, long paths, open LaunchBox, antivirus, blocked PowerShell, spaces in paths, network drives, and restore: use [the beginner troubleshooting guide](docs/TROUBLESHOOTING.md).

When a game is not recognized, make sure TeknoParrot is up to date and TeknoParrotUI has been opened once. Then run Register only again.

| Problem                                    | Fix                                                                                                                                                                                 |
| ------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Game won't launch                          | Open TeknoParrotUI, point the profile to the correct `.exe`. Re-run the script and answer Y when it asks to repair game paths.                                                                                   |
| Game not in TeknoParrot                    | For an ambiguous shared executable, choose one of TeknoParrot Manager's validated candidates or leave it for TeknoParrotUI. If no candidate is safe, extract the game first.                                                                                                |
| Extraction keeps failing                   | Check the log for the specific error. Verify free space and that the ZIP is not corrupted.                                                                                          |
| Controls wrong after propagation | Review the mode 14 backup and later settings it would replace. Preserve needed current settings and fix the reference; do not delete XML merely to retry. |
| Wrong fuzzy match | Preserve the UserProfile, confirm the correct official profile/GamePath, and use validated candidate/manual setup. forceArchetype is controls-only. |
| Game appears twice in TeknoParrotUI | Confirm both profiles refer to the same game and preserve backups of both before removing a verified duplicate. Keep needed paths, bindings and settings. |
| `[UNLOGGED]` on console                    | Log file is inaccessible -- check the shown log path and its folder permissions; the normal RC8.1 log is under TeknoParrotManager\Logs.                                                                        |
| ReShade text or a window shows at game start | Run **5** (ReShade setup) for that game and pick a look again. TeknoParrot Manager writes `ReShade.ini` with the welcome window, counters and messages off. If it says the game was left alone, press **D** to read why. A short version banner at game start is normal. |
| Postgres setup needs Windows permission | TeknoParrot Manager asks Windows automatically and resumes the same setup. Approve the Windows prompt; if you decline it, choose the automatic repair retry when TeknoParrot Manager offers it. |

---

## Files the Script Keeps

`<ProgramFolder>` means the folder containing TeknoParrot-Manager.ps1.

RC8.1 places its normal configuration and log under `<TeknoParrotRoot>\TeknoParrotManager\State\` and `Logs\`.

The table below lists each file, where it lives, and what it is for:

| File                                  | Location                                                 | Purpose                                                                                                                                        |
| ------------------------------------- | -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `TeknoParrot-Manager.config.json` | `<TeknoParrotRoot>\TeknoParrotManager\State\` | Saved folders and settings (Postgres password stored DPAPI-encrypted)                                                                          |
| `TeknoParrot-Manager.overrides.json`  | Scripts folder                                           | Per-game tweaks (noSync, onlySync, noPropagate, forceArchetype, familyOverride, canonicalArchetype, datFile)                                   |
| TeknoParrot-Manager.log | `<TeknoParrotRoot>\TeknoParrotManager\Logs\` | Log of every run, including ReShade/BepInEx/dgVoodoo2 and other download audit fields: source, filename/version, SHA-256, and transfer metrics |
| `TeknoParrot-Manager.syncstate.json`  | Staging folder                                           | Tracks extraction identity/state; preserve it before advanced recovery                                                                                               |
| `TeknoParrot-Manager-controls.txt`    | `<TeknoParrotRoot>\TeknoParrotManager\Reports\`          | Controls state after every real run (a preview run leaves it alone)                                                                            |
| `TeknoParrot-Manager-ActionItems.txt` | `<TeknoParrotRoot>\TeknoParrotManager\Reports\` (default; Save dialog can pick elsewhere) | Action items from last run                                                                                                                     |
| `TeknoParrot-LaunchBox-Import.xml`    | `<TeknoParrotRoot>\TeknoParrotManager\Reports\`          | LaunchBox manual-import reference XML (only if you skip direct integration)                                                                    |
| `LaunchBoxBackups\`                   | `<TeknoParrotRoot>\TeknoParrotManager\Backups\` (or the Scripts folder for an older legacy-only history); `%LOCALAPPDATA%\TeknoParrotManager\LaunchBoxBackups\<key>\` when TeknoParrot is inside the LaunchBox folder | Timestamped backups of LaunchBox's own files, made before each direct write; never kept inside the LaunchBox folder |
| `PostgresBackups\`                    | `<TeknoParrotRoot>\TeknoParrotManager\Backups\` (or the Scripts folder if an older folder is already there) | Timestamped `pg_dump` backups of Postgres databases, made before each Postgres setup run |
| `ReShade\ReShade64.dll`               | `<TPRoot>\TeknoParrotManager\Assets\ReShade\` or the Scripts folder | User-provided ReShade DLL (64-bit; not included in the release ZIP)                                                                            |
| `dgVoodoo2\*.dll` + `dgVoodoo.conf`   | `<TPRoot>\TeknoParrotManager\Assets\` or the Scripts folder | dgVoodoo2 DLLs (you provide)                                                                                                                   |
| `Crosshairs\*.png`                    | Scripts folder                                           | Crosshair images (321 included)                                                                                                                |
| `CustomThumbnails\*.png`              | `<TPRoot>\TeknoParrotManager\Assets\CustomThumbnails\`                                           | Your own game icons (optional, you create)                                                                                                     |

### More detail

- Startup previews only the known items it can safely migrate.
- Active `TeknoParrot-Manager.overrides.json` and `BepInExCache\` remain in ProgramFolder. `LaunchBoxBackups\` and `PostgresBackups\` are used from the Backups folder unless an older folder already exists in ProgramFolder.
- That is because current settings, restore and cache consumers still use those locations.
- `PostgresRecoveryBackups\` (private recovery evidence) is the one backup folder that is moved. It goes to `<TeknoParrotRoot>\TeknoParrotManager\Backups\PostgresRecoveryBackups\` through a protected copy.
- Each backup folder is handled on its own. If a managed copy and an older copy beside the script both exist, TeknoParrot Manager stops, merges nothing, deletes nothing, and asks you to keep both.
- This rule does not automatically adopt copies already moved by an earlier candidate.
- Preserve all copies and the migration report for a reviewed recovery. Do not merge or delete them merely to clear a warning.

---

> Full documentation: [README.md](README.md)
