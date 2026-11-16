# Quick Start

Get TeknoParrot Manager (TPM) running in a few minutes. This page matches v1.0 RC8.1, the interim build for testers, which is not published yet. The final v1.0 RC9 comes later. The latest published release today is RC7: see the [releases page](https://github.com/Jumpstile/teknoparrot-manager/releases).

Test one game after each run.

---

## What is it?

[TeknoParrot](https://www.teknoparrot.com/) is a free Windows program that runs arcade games on a normal PC. **TPM is not TeknoParrot.** It is a helper that sets up TeknoParrot's saved game settings (called profiles) for many games at once, so you do not have to do each game by hand in `TeknoParrotUi.exe`.

TPM does not provide game files, firmware, or BIOS. You bring your own.

It plays safe: it makes a backup first, shows a preview first, asks before it changes things, and stops if a check fails.

Registered, launched, and controls-ready are three different things. A game that is registered still needs its controls mapped and tested in TeknoParrot.

<details>
<summary>Details</summary>

| Term | Meaning |
|---|---|
| **TeknoParrotUi.exe** | TeknoParrot's own window, where you launch games and set them up by hand. TPM edits the same profile files. |
| **DAT file** | A community list of game names (Eggman/RomVault). TPM uses it to recognize games with odd or renamed files. |
| **Control propagation** | You set up the controls for one game. TPM copies them to other games of the same type. |
| **BepInEx** | A plugin framework some games use. See [[BepInEx]]. |
| **FFB** | Force feedback for wheels and sticks. See [[FFB Setup]]. |

</details>

---

## What you need

- Windows 10 or 11
- PowerShell 5.1 or later (already part of Windows)
- TeknoParrot installed, and `TeknoParrotUi.exe` opened at least once
- Your games, as ZIP files (for AutoSync) or already extracted into one folder per game

TeknoParrot has its own first-time setup (choose the DAT file, scan for games, set up controls). If it is not finished, TPM tells you at the end of a run.

---

## Run it

**1.** Open PowerShell in the folder that holds `TeknoParrot-Manager.ps1`:

```
cd "C:\path\to\TeknoParrot Manager"
```

**2.** Start it:

```
.\TeknoParrot-Manager.ps1
```

If Windows blocks the script, allow it for this window only:

```
powershell -ExecutionPolicy Bypass -File .\TeknoParrot-Manager.ps1
```

You can also double-click `TeknoParrot-Manager.bat`.

**3.** First run:

1. You see `Welcome to TeknoParrot Manager`. Press Enter.
2. TPM looks for `TeknoParrotUi.exe`. You see `Auto-detected TeknoParrot at: ...` and `Use this path? (Y/N)`. Press `Y` to accept. If it finds several, pick a number. If it finds none, it asks for the folder: type it, type `B` to browse, or type `Q` to quit. If you close the browse window or type a wrong folder, it asks again.
3. You are asked for your games folder (also called the staging folder), folder naming, and the DAT list. The default answers are fine if you are not sure.

**Later runs.** You see `TeknoParrot Manager found your saved settings.` and `Use these settings? (Y/N, D = show them)`. Press `Y` to keep them, `D` to look first, or `N` to answer the first-time questions again. `N` deletes nothing.

**4.** Pick from the main menu. Type a number and press Enter. The prompt is `Enter 1-17:`.

| # | Menu item | Use it when |
|---|---|---|
| 1 | AutoSync | Your games are ZIP files |
| 2 | Register only | Your games are already extracted |
| 3 | Propagate Controls | You want to copy controls again |
| 4 | Crosshair setup | You want custom crosshairs on lightgun games |
| 5 | ReShade setup | You want visual filters |
| 6 | dgVoodoo2 setup | An old game crashes or shows a black screen |
| 7 | GPU fix setup | You want the fix for your AMD, NVIDIA, or Intel card |
| 8 | Force feedback (FFB) setup | You have a wheel or stick with force feedback |
| 9 | BepInEx setup | A game needs BepInEx |
| 10 | Region setup | You want to pick the country your games start in. See [[Region Setup]] |
| 11 | Postgres setup | A game needs PostgreSQL (like Golden Tee Live). See [[Postgres Setup]] |
| 12 | Required game patches | A supported game needs a fix. See [[Required Game Patches]] |
| 13 | Library health check | You want a status check that changes nothing |
| 14 | Restore backup | You want to put something back. See [[Restore Backup]] and [[Reset and Restore]] |
| 15 | Check for Updates | You want to see if a newer version is out. See [[Check for Updates]] |
| 16 | Create Support Package | You need to send diagnostics when asking for help. See [[Support Package]] |
| 17 | Exit | |

After each item you come back to this menu. In a small window the menu shows a short layout. At the prompt you can also type `H` (help), `L` (view log), or `Q` (quit).

Many result screens say `Press D for details`. Press `D` for the full technical information. It is also saved in the log.

<details>
<summary>What the menu looks like in the console</summary>

```
--------------------------------------------
 Mode
--------------------------------------------
  LIBRARY MANAGEMENT
  ------------------
  1) AutoSync        -- Extract your game ZIPs into your games
                        folder, then register the games.
  2) Register only   -- Register games already in the games folder.
  3) Propagate Controls -- Copy controls from a game you set up
                        to games of the same type, without
                        going through AutoSync/Register first.

  GAME ENHANCEMENTS (OPTIONAL -- NOT EVERY GAME NEEDS THEM)
  ---------------------------------------------------------
  4) Crosshair setup -- Pick and deploy custom crosshairs to all
                        registered lightgun games.
  5) ReShade setup   -- ReShade adds post-processing filters on top of
                        the game -- sharper image, better colors,
                        CRT-style scanlines, and screen borders, for a
                        more authentic arcade-cabinet look.
  6) dgVoodoo2 setup -- Fix some old DX8, DirectDraw, and Glide game
                        crashes or black screens.
  7) GPU fix setup   -- Auto-detect your GPU (AMD / NVIDIA / Intel) and
                        apply the matching compatibility fix to every
                        registered game that has one.
  8) Force feedback (FFB) setup -- Wheel/stick rumble and force feedback.
                        Covers TeknoParrot's built-in FFB Blaster (needs a
                        paid membership) and a free third-party plugin.
  9) BepInEx setup -- BepInEx is a modding framework some games use
                        for extra features and fixes. TPM can install or
                        update it after you approve; repair-reset is
                        unavailable. Unsafe folders and failed downloads
                        make no changes.
  10) Region setup -- Pick a country (like USA or Europe) and set it
                        on the games that offer it. You can pick which
                        games, and go back to Auto at any time.

  GAME REQUIREMENTS (ONLY FOR SOME GAMES)
  ---------------------------------------
  11) Postgres setup -- Installs/configures local PostgreSQL for
                        Incredible Technologies games, including
                        Golden Tee Live 2020, Golden Tee Live,
                        Power Putt Live, Silver Strike Bowling Live,
                        and Target Toss Pro. A missing game database
                        is made from the game's own backup.
                        Every game database is then tested with the
                        game's own settings before it is called ready.
                        Administrator is required if PostgreSQL isn't
                        installed yet.
  12) Required game patches -- Find required patches for supported exact
                        game builds using your local Main or
                        Supplementary ZIP files. TPM validates the
                        game, backs up, applies, and verifies files.
                        A verified patch is not gameplay proof.

  MAINTENANCE AND RECOVERY
  ------------------------
  13) Library health check -- Reports registered/broken/unregistered games
                        plus GPU fix / FFB Blaster / dgVoodoo2 and
                        ReShade/BepInEx counts, without changing
                        anything. Any repair it suggests is a separate
                        choice that you confirm first.
  14) Restore backup -- Restore selected backup files with verification.
                        LaunchBox recovery first backs up current targets;
                        keep LaunchBox and BigBox closed throughout.

  APPLICATION
  -----------
  15) Check for Updates -- Manual check against the latest
                        GitHub release. Nothing is downloaded or changed
                        without your explicit confirmation.
  16) Create Support Package -- Gather safe TPM, TeknoParrot, and game diagnostics
                        into one ZIP you can send when asking for help.
  17) Exit

Enter 1-17:
```
</details>

**5.** For **AutoSync** (item 1):

1. Choose **P** (Preview, the default) to see what would change without changing anything. Choose **R** (Run now) to back up your UserProfiles and then make the changes. See [[AutoSync]].
2. If asked, choose the folder that holds your game ZIP files. Your games folder must be a different folder, outside TeknoParrot.
3. Choose what to extract. The prompt is `Enter A, L, S, D, or B`:

| Key | Action |
|---|---|
| A | All games not extracted yet |
| L | Browse the A-Z list and pick by number |
| S | Search by word, then pick by number |
| D | Done: go on with the games you picked |
| B | Back: cancel |

After new games are registered, TPM asks once which country they should start in. Type `0` to leave them as they are. See [[Region Setup]].

**6.** Open `TeknoParrotUi.exe`. Your games are there.

---

## Copy your controls (recommended)

Set up the controls once, and TPM copies them to the other games of the same type.

1. In TeknoParrot, fully set up **one game of each type**: buttons, axes, Test, Service, Coin, Start. Good ones to start with:
   - **Fighting / buttons:** Street Fighter III, BlazBlue, Tekken 7
   - **Driving:** Daytona Championship USA, Initial D, OutRun 2 SP
   - **Lightgun:** House of the Dead 4, Aliens Extermination
   - **Trackball:** Golden Tee Live, Silver Strike Bowling
2. Run TPM again (item 1 or 2). After registering, it copies the controls on its own. To copy without registering, choose item 3. See [[Propagate Controls]].
3. Start **one** game and test it before you trust the rest.

---

## More setup (any time)

- [[Crosshairs]] (4), [[ReShade]] (5), [[dgVoodoo2]] (6), [[GPU Fix]] (7), [[FFB Setup]] (8), [[BepInEx]] (9)
- [[Region Setup]] (10)
- [[Postgres Setup]] (11), [[Required Game Patches]] (12)
- [[Health Check]] (13)
- Games that will not start because files are missing (PS3 firmware, Chihiro files): see [[Game Startup Files]]. [[CPS3 First-Boot Files]] covers the optional CPS3 step.
- [[LaunchBox Integration]]

---

## If something goes wrong

- Your UserProfiles are backed up before AutoSync changes anything (not in a preview). To put things back, choose **14) Restore backup**. See [[Restore Backup]] and [[Reset and Restore]].
- To ask for help, choose **16) Create Support Package**. See [[Support Package]].
- Common problems: [[Troubleshooting]].
