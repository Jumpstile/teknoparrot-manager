===============================================================================
  TeknoParrot Manager  |  v0.98 BETA
  Author: Jumpstile
===============================================================================

  Registers your extracted games with TeknoParrot so they appear and launch
  automatically, copies your controls between games of the same type, and
  keeps your game library organised. Windows / PowerShell 5.1+.

  This is a beta release. Test one game after each run. Your profiles are
  backed up automatically at the start of every run.

  For a one-page version, see TeknoParrot-Manager-QuickStart.txt.



-------------------------------------------------------------------------------
  WHO IS THIS FOR?
-------------------------------------------------------------------------------

  This script is for people with large TeknoParrot collections who want
  registration, controls, and game management handled automatically.

  You will get the most out of it if you:

    -- have a large collection (dozens or hundreds of games)
    -- store games as ZIPs on a NAS and want automated extraction
    -- use LaunchBox, HyperSpin 2, RetroBat, or Batocera as a frontend
    -- want crosshairs, ReShade, or dgVoodoo2 set up across all your games
       at once rather than game by game

  You may not need this script if:

    -- you only have a handful of games
    -- you prefer to register and configure games manually in TeknoParrotUI


-------------------------------------------------------------------------------
  FEATURES
-------------------------------------------------------------------------------

  - Automatic registration. Scans your extracted games, matches each to the
    correct TeknoParrot profile, and makes it appear and launch in
    TeknoParrotUI. Scans all common executable types: .exe, .elf, .iso,
    .xbe (Sega Chihiro/cxbxr games such as Virtua Cop 3 and OutRun 2),
    .dll (Konami PC arcade games such as DanceDanceRevolution 2013, Steel
    Chronicle, Metal Gear Arcade), and more. Existing registrations are
    never overwritten.

  - Fuzzy name matching. For platforms that share a single executable file
    (most notably NESiCAxLive, where 80+ games all use game.exe), the script
    compares the game folder name to every candidate profile code and
    auto-registers the best match when the similarity score is high enough.
    Games below the confidence threshold are flagged with their best-guess
    profile shown, so even manual registration takes one click instead of
    hunting through a long list.

  - Dat file integration (optional). A "dat file" is a community-maintained
    lookup file that maps game files to their correct titles and metadata --
    think of it as an answer key the script can check against when a game's
    own files don't make its identity obvious. During initial setup, the
    script offers to download the Eggman/RomVault dat ZIP directly from
    GitHub (~145 MB) or accept a path to a local copy. The ZIP contains both
    the collection dat and the supplementary dat; both are read directly from
    inside the archive with no extraction step. The dat's <GameProfile> code
    is used as the authoritative source for three registration scenarios:
    (1) shared-executable games where
    multiple profiles match the same exe name; (2) games whose exe name does not
    appear in any GameProfile at all (e.g. pcsx2x6 ELF games, ELF-based Lindbergh
    titles) -- a second pass looks them up in the dat by normalized folder name;
    (3) slightly misnamed folders -- a fuzzy scan of all dat entries finds the
    best match above the auto-register threshold. Games registered via the dat
    are shown as "Registered (dat/exact)" or "Registered (dat/fuzzy)".

    A third registration pass (independent of the dat) Dice-matches normalised
    folder names against normalised GameProfile code names. This resolves games
    whose GameProfile has an empty ExecutableName -- they never enter the exe-name
    index and may not appear in the dat either. Examples: BladeStrangers,
    LuigisMansion, MaiMaiGreen, PokkenTournament, ProjectDiva, SonicDashExtreme,
    HydroThunder. These appear as "Registered (code/fuzzy)".

    The supplementary dat can be indexed to show alternate versions of your
    games (different regions, revisions, bonus content). After registration
    completes, a "Game Info" block shows alternate versions and game notes (from
    the notes text file in the ZIP) for each newly registered game. The dat path
    can also be set in overrides.json (datFile key); that takes precedence.

  - Already-registered detection. Before flagging a shared-executable folder
    as needing manual registration, the script checks whether any candidate
    profile already has a UserProfile XML (i.e. was registered via
    TeknoParrotUI or a previous run). If so, it is marked "already set" and
    removed from ACTION REQUIRED. Games set up outside the script no longer
    reappear on every run.

  - AutoSync extraction. Copies and extracts game ZIPs from a NAS or local
    source into a staging folder you choose, skipping unchanged games. Tracks
    what has been extracted so future runs only touch new or changed ZIPs.
    A supplementary source (separate optional library) can be configured and
    is scanned alongside the main collection in the same pick session.
    The staging folder can be on a network drive; the script measures write
    speed and warns if throughput is too low for reliable extraction or play.

  - Game selection. When extracting, all sources are presented in one combined
    A-Z list. Supplementary-library entries are marked [+] and counts are shown
    per source so you always know the breakdown. Choose to extract everything,
    browse an A-Z paginated list, or search by keyword. Games already on disk
    are filtered from the list automatically.

  - Extraction progress. A real-time progress bar shows file count and
    percentage during each game's extraction -- no more blinking cursor.

  - Smart folder matching. Extraction folders use the same naming convention
    as the ZIP files. If a game was previously extracted under an older naming
    convention (e.g. with spaces between bracket groups), the script
    recognises it and does not create a duplicate.

  - Control propagation. Bind ONE game of each control type once; the script
    copies those controls to every other game of the same type, matched so a
    wheel value can never land on a gun. Aim-mode settings (relative input,
    sensitivity, hide-cursor) are also carried across.

  - Device survey. Asks which controls you have and prints a tailored plan of
    which game to bind with which device.

  - Game repair. Finds broken or empty game paths and re-points them to the
    correct executable in your staging folder.

  - LaunchBox integration. Adds your registered games directly into
    LaunchBox's own library -- no import wizard needed. Checks LaunchBox is
    closed, backs up the files it is about to change, and never duplicates a
    game already there. Choose to mix TeknoParrot games into your existing
    Arcade platform, a dedicated "TeknoParrot" platform, a platform with a
    name you choose, or both Arcade and a dedicated platform at once; your
    choice is remembered for next time. A manual-import reference file (for
    LaunchBox's own Import wizard) remains available if you prefer not to
    let the script touch LaunchBox's files directly.

  - HyperSpin 2 export. After each run the script offers to add all registered
    games to HyperSpin 2's game list. Locates the TeknoParrot system in your
    HyperSpin 2 data folder and merges in any games not already present. Games
    are added with title only; use HyperSpin's Scrape feature to fetch box art
    and metadata.

  - RetroBat / Batocera support. A single setting switches extraction to use
    GameName.teknoparrot folder naming as required by RetroBat and Batocera.
    The script also recognises .parrot and .game suffixes for existing folders.
    Registration, fuzzy matching, and all other features work identically.

  - "Not in TeknoParrot" report. After scanning your staging folder, lists
    every game folder whose executables did not match any TeknoParrot profile.
    Games that disappear silently are now surfaced in the ACTION REQUIRED
    section so you know exactly which titles are not yet supported.

  - Controls status file. After every run, writes a persistent
    TeknoParrot-Manager-controls.txt listing every registered game, its
    control family, whether controls were propagated and from which reference
    game, and how many buttons are still set manually. Useful weeks later
    when a game aims wrong and you have forgotten what state it was left in.

  - Thumbnail download. After registration, optionally downloads game icons
    from the TeknoParrotUIThumbnails GitHub repository directly into
    TeknoParrot's Icons folder. Only fetches icons that are absent; never
    overwrites existing files. Reports how many were fetched, already present,
    or not yet in the repo.

  - Unattended mode. A -Unattended switch skips all Y/N prompts, uses
    saved settings, extracts all new games, runs registration, repair, and
    propagation automatically, and logs everything. Designed for scheduling
    as a Windows Task to run overnight when new ZIPs appear on the NAS.

  - Preview / dry-run mode. Before AutoSync or Register only does anything,
    you can choose to preview what it would do -- which games would extract,
    which would register and to which profile, which broken paths would be
    repaired, which controls would propagate -- without writing a single
    file. No backup is created (nothing needs restoring), and the optional
    follow-up offers (LaunchBox/HyperSpin export, thumbnail download, GPU
    fix) are skipped since there is nothing yet to act on. Useful the first
    time you point the script at a new library, or after changing settings,
    to build confidence before committing. Answer Y to the prompt, or pass
    -DryRun on the command line to always preview (combine with -Unattended
    to preview a scheduled run without any prompts). After a preview
    finishes, the script asks "Apply these changes for real now?" -- answer
    Y to immediately re-run the same mode for real with no further prompts,
    or N to return to the menu without changing anything.

  - Auto-detect TeknoParrot path. On first run, instead of asking for the
    root folder immediately, the script scans common install locations
    (LaunchBox emulators folder, drive roots, Program Files) for
    TeknoParrotUi.exe and suggests the match. If multiple installs are
    found, it lists them numbered so you can pick without typing.

  - Restore from backup. A menu option lists all timestamped backups and
    restores the one you pick in one step, without touching File Explorer.

  - Crosshair setup. Deploys custom P1/P2 crosshair cursor images to all
    registered lightgun games. An HTML preview grid lets you browse 321
    included designs (or your own PNGs) visually before picking by index.
    Optionally also hides the Windows mouse cursor for all lightgun games
    by setting the cursor-hide field in each UserProfile XML.

  - ReShade visual enhancements. Installs ReShade post-processing into your
    game folders, auto-detecting the correct DLL name from each game's
    executable. Supports both 64-bit (ReShade64.dll) and 32-bit (ReShade32.dll)
    games -- the correct DLL is chosen automatically based on each game's
    architecture. Checks reshade.me for newer versions on each run. Optional --
    your games work perfectly without it.

  - dgVoodoo2 legacy compatibility. Fixes older arcade games that crash or
    show black screens due to DirectX 8, DirectDraw, or Glide API usage.
    Auto-detects which registered games use those APIs and deploys the correct
    dgVoodoo2 DLLs. Optional -- only needed for games that do not run correctly.

  - GPU compatibility fixes. Many TeknoParrot games include optional per-vendor
    fix settings (AMD, NVIDIA, Intel) in their profiles. This mode auto-detects
    your GPU and applies the correct fix to every registered game that has one.
    TeknoParrot's GameProfiles folder is scanned at runtime so newly added games
    are always covered. Safe to re-run any time you change or update your GPU.
    Available as menu option 6 or as an optional step at the end of a normal run.

  - Force feedback (FFB). Two independent ways to get wheel/stick rumble and
    force feedback -- TeknoParrot's own built-in FFB Blaster (needs a paid
    TeknoParrot membership) and a free third-party plugin (no subscription
    needed, fetched live from GitHub each run). Both can be set up at once
    since they cover different games; if a game is covered by both, you are
    asked once which to use for all such games. See FORCE FEEDBACK (FFB)
    SETUP below for full details. Available as menu option 7.

  - BepInEx update check. BepInEx is a third-party Unity plugin/modding
    framework some games need (a live-fetched example list is shown in the
    menu). This checks every game that already has BepInEx installed
    against the latest stable release and offers one batched update. Never
    installs BepInEx into a game that doesn't have it, and only the 64-bit
    stable line is ever used. See BEPINEX UPDATE CHECK below. Available as
    menu option 8.

  - Path-length, file-version, and GPU compatibility warnings (automatic).
    Every AutoSync/Register run automatically checks for known
    compatibility traps and adds them to the ACTION REQUIRED summary:
      (1) specific games whose install path exceeds a hard-coded
          engine-specific length limit (Raw Thrills titles, Yu-Gi-Oh!
          Duel Terminal 6) -- shows the exact short folder name to use.
      (2) specific games needing an older, specifically pinned version
          of a particular file rather than the latest one (BlazBlue-
          series games and iDmacDrv32.dll; Tekken Tag Tournament 2 and
          EBOOT.BIN) -- shows the required CRC32 and where to get it.
      (3) specific games confirmed NOT to work on your detected GPU
          vendor (AMD or Intel) -- informational only, no fix exists,
          but lets you know before you spend time troubleshooting blind.
    No action needed unless flagged.

  - Per-game overrides. A JSON file lets you exclude games from sync or
    propagation, whitelist specific games for extraction, pin a game to a
    specific reference game for control copying, or override the auto-detected
    control family for mis-classified titles.

  - Action summary. At the end of every run the script prints a clear list of
    everything that needs your attention in TeknoParrotUI, including which
    games to register manually (with best-guess profile shown), which paths to
    fix, and which control types still need to be set up.

  - Safe by design. Backs up all profiles before every run, never deletes
    your games, guards the staging folder against the emulator and source
    folders, checks free space, and logs everything.


-------------------------------------------------------------------------------
  HOW IT WORKS
-------------------------------------------------------------------------------

  TeknoParrot keeps two profile folders in its root:

    GameProfiles   Templates that ship with TeknoParrot, one per supported
                   game. Each names the executable it expects and carries
                   that game's settings and controls.

    UserProfiles   Your games. A game appears and launches once its template
                   is copied here with the path to your executable filled in.

  This script automates that copy-and-fill step: it scans your games, matches
  each executable to the right template, copies it to UserProfiles, and sets
  the path. TeknoParrot picks the games up on its next launch.


-------------------------------------------------------------------------------
  REQUIREMENTS
-------------------------------------------------------------------------------

  - Windows 10 or 11 with PowerShell 5.1 or later (built in).
  - A TeknoParrot install containing TeknoParrotUi.exe and its GameProfiles
    folder. Run TeknoParrotUi.exe once first so it downloads profiles.
  - Your games extracted into per-game subfolders, or as ZIP files for
    AutoSync to extract.


-------------------------------------------------------------------------------
  RUNNING THE SCRIPT
-------------------------------------------------------------------------------

  Step 1.  Open PowerShell and navigate to the folder that contains
           TeknoParrot-Manager.ps1 (typically a Scripts subfolder inside
           your TeknoParrot install):

      cd "C:\path\to\TeknoParrot\Scripts"

  Step 2.  Run the script:

      .\TeknoParrot-Manager.ps1

      If the script is blocked, allow it for this session only:

      powershell -ExecutionPolicy Bypass -File .\TeknoParrot-Manager.ps1

  Step 3.  Choose a mode (see below). On later runs the script remembers your
           settings and offers to reuse them -- press Y to continue.


-------------------------------------------------------------------------------
  AUTO-DETECT TEKNOPARROT PATH
-------------------------------------------------------------------------------

  On first run (or any run where the TeknoParrot root is not saved), the
  script scans common install locations for TeknoParrotUi.exe before asking
  you to type the path manually:

    - Your LaunchBox Emulators folder under USERPROFILE
    - Drive roots: C:\TeknoParrot, D:\TeknoParrot, etc.
    - Drive roots with sub-paths: \Games\TeknoParrot, \Emulators\TeknoParrot
    - Program Files and Program Files (x86) on every mounted drive

  If exactly one install is found, it is offered for confirmation:

      Auto-detected TeknoParrot at: C:\Users\...\LaunchBox\Emulators\TeknoParrot
      Use this path? (Y/N)

  If multiple installs are found, they are listed numbered so you can pick
  without typing. If nothing is found, the manual prompt appears as before.


-------------------------------------------------------------------------------
  MODES
-------------------------------------------------------------------------------

  The main menu is a persistent loop -- after each mode finishes you are
  returned to the menu to choose another mode or exit.

  1) AutoSync
       For games stored as ZIP files (for example on a NAS).
       You provide:  a ZIP source folder and a local staging folder.
       The script:   presents a game selection menu, extracts the games you
                     choose into the staging folder, then registers them.
                     Unchanged games are skipped automatically.

  2) Register only
       For games you have already extracted.
       You provide:  the folder that contains your extracted games.
       The script:   scans it and registers everything it recognises.

  3) Crosshair setup
       Deploys custom P1/P2 crosshair cursor images to all registered
       lightgun games. Opens an HTML preview grid (321 included designs)
       in your browser so you can browse before picking by number.
       Optionally hides the Windows cursor for all lightgun games.
       Returns to the menu when done.

  4) ReShade setup
       Installs ReShade post-processing into your game folders. Auto-detects
       the correct DLL name and architecture (32-bit or 64-bit) for each
       game. Optional -- see RESHADE VISUAL ENHANCEMENTS below.
       Returns to the menu when done.

  5) dgVoodoo2 setup
       Deploys dgVoodoo2 compatibility DLLs for games that use DirectX 8,
       DirectDraw, or the Glide API. Auto-detects which registered games
       need it. Optional -- see DGVOODOO2 LEGACY COMPATIBILITY below.
       Returns to the menu when done.

  6) GPU fix setup
       Detects your GPU vendor (AMD/NVIDIA/Intel) via WMI and applies the
       correct fix flag to every registered game that has one. Scans
       TeknoParrot's GameProfiles at runtime -- no update needed when new
       games are added. Optional. Returns to the menu when done.

  7) Force feedback (FFB) setup
       Sets up wheel/stick rumble and force feedback for supported games.
       Covers two independent mechanisms -- see FORCE FEEDBACK (FFB) SETUP
       below. Optional. Returns to the menu when done.

  8) BepInEx update check
       Checks every registered game that already has BepInEx installed
       against the latest stable release and offers a single batched
       update. Never installs BepInEx fresh into a game that doesn't have
       it, and only ever uses the latest stable 64-bit build -- see
       BEPINEX UPDATE CHECK below. Optional. Returns to the menu when done.

  9) Restore from backup
       Choose which backup to restore: (1) your UserProfiles -- rolls back
       to a previous backup without touching File Explorer, lists all
       timestamped backup folders with file counts, you pick one by number,
       type YES to confirm; or (2) LaunchBox's library files -- only
       relevant if you have used the direct LaunchBox integration, restores
       Emulators.xml/Platforms.xml/platform file(s) to their state before
       the script last wrote to them. Returns to the menu when done.

  10) Library health check
       Read-only. Reports how many registered profiles have a valid,
       broken, or empty GamePath, lists the affected profile codes, and
       shows the summary line from your last full run. Also reports
       optional-setup coverage: how many registered games are eligible
       for a GPU fix, FFB Blaster, or dgVoodoo2 but don't have it applied
       yet (all checked locally, no network access -- third-party FFB
       plugin coverage needs a live lookup, so check that via mode 7
       instead). Also shows, purely informationally, how many registered
       games have ReShade or BepInEx installed -- these two are per-game
       choices rather than a clear right answer, so they are not flagged
       as something to fix, just reported as a count. Does not extract,
       register, repair, propagate, or touch the network -- safe to run
       any time for a quick status check. Returns to the menu when done.

  11) Exit
       Exits the script.


-------------------------------------------------------------------------------
  GAME SELECTION (AutoSync mode)
-------------------------------------------------------------------------------

  After entering your folders, the script scans the staging folder and filters
  out games already extracted there. When a supplementary ZIP source is
  configured, both libraries are merged into one combined list. Games from the
  supplementary source are marked with [+] in the list, and the header shows
  a per-source count breakdown so you always know the origin of each title.

  The script then shows:

      347 game(s) already extracted -- not shown.
      136 game(s) available to extract.  (main: 120  supplementary: 16)

  Followed by the selection menu:

      A) All unextracted games (136)
      L) Browse and select from list (136 games, A-Z)
      S) Search by keyword
      D) Done -- proceed with current queue

  A -- All unextracted games
       Extracts everything not already on disk. The fastest option if you
       want a full library.

  L -- Browse and select from list
       Shows the unextracted games in alphabetical order, 20 at a time.
       Commands inside the list:
         Numbers or ranges   1,3,5-7 to add games to the queue.
         N                   Next page.
         P                   Previous page.
         B                   Back to the selection menu.
         D                   Done -- finish selecting and start extracting.
       Games already in your queue are marked with * in the list.

  S -- Search by keyword
       Type any part of a game name. The script shows matching unextracted
       games numbered; type numbers or ranges to add them to your queue.
       Type "back" to return to the selection menu, or "done" to finish.

  D -- Done (from the main menu)
       Proceeds with whatever is in the queue. You can freely switch between
       Browse and Search to build up a queue across multiple searches before
       pressing D. If the queue is empty, D exits with no games selected --
       extraction is skipped for that source. Use A to extract all games.

  At any point the header shows how many games are in the queue. After
  pressing D, the full queue is listed before extraction starts.


-------------------------------------------------------------------------------
  THE STAGING FOLDER
-------------------------------------------------------------------------------

  AutoSync extracts games into a staging folder that YOU choose. The script
  enforces these rules to keep everything healthy:

    - It can be on a network drive, but the script measures write speed
      first and warns if throughput looks too low for reliable extraction
      or play -- a local drive is recommended when possible for speed.
    - It must NOT be inside the TeknoParrot folder.
    - It must NOT overlap the ZIP source folder.
    - There must be room. The script warns if the drive has less than ~1.5x
      the total ZIP size free and asks before continuing.

  Pick a folder on a drive with space, for example  D:\TeknoParrotGames.

  Naming convention. Extraction folders use the raw ZIP file name as-is,
  so they match the naming convention used by the collection. If a game was
  previously extracted under an older naming convention (spaces between
  bracket groups vs no spaces), the script normalises the names and recognises
  the existing folder -- it will not create a duplicate.

  Metadata ZIPs. Files in the ZIP source whose name starts with
  "!TeknoParrot Collection" (the collection changelog, readme, and game notes)
  are always skipped automatically regardless of date.

  Interrupted extractions. If an extraction is cut short for any reason
  (Ctrl+C, power loss, disk error mid-write), the script places a
  .extracting sentinel file next to the game folder at the start and removes
  it only when extraction completes successfully. If the sentinel is found on
  the next run, the incomplete folder is detected and the game is
  re-extracted from scratch automatically. The sentinel is removed with the
  highest priority -- it is the sole responsibility of a dedicated finally
  block that runs regardless of success, exception, or interruption.


-------------------------------------------------------------------------------
  REGISTRATION
-------------------------------------------------------------------------------

  The script matches each game executable to its TeknoParrot profile by name.
  There are four outcomes per game:

    Registered          A matching profile was found and your game now appears
                          in TeknoParrot.

    Registered (fuzzy)  The executable name is shared by multiple games
                          (e.g. game.exe is used by 80+ NESiCAxLive titles),
                          but the folder name matched a specific profile with
                          high confidence. The profile code and similarity
                          score are shown in Cyan so you can spot-check.
                          These registrations are correct the vast majority
                          of the time; test the game to confirm.

    Registered (dat)    The game folder name matched an entry in the
                          configured dat file. The dat's authoritative
                          profile code is used directly, and if the dat
                          includes an Executable path, that exact binary is
                          used. This covers three cases: shared-executable
                          games, games whose exe is not in any GameProfile
                          (e.g. pcsx2x6 / ELF-based titles), and slightly
                          misnamed folders (fuzzy dat scan). Configure the
                          dat path during setup or via datFile in
                          overrides.json -- see PER-GAME OVERRIDES.

    Registered          Folder name matched a TeknoParrot profile code
    (code/fuzzy)          directly by Dice similarity. Used for games whose
                          GameProfile has an empty ExecutableName (examples:
                          BladeStrangers, LuigisMansion, MaiMaiGreen,
                          PokkenTournament, SonicDashExtreme, HydroThunder).
                          The best available executable in the folder is
                          selected automatically.

    Already set          A profile for this game already exists and is left
                          exactly as it is. The script never overwrites
                          existing work.

    Register manually    The executable name is shared and the folder name
                          did not match any profile confidently enough to
                          auto-register. The ACTION REQUIRED section shows
                          the executable to browse to, a best-guess profile
                          name (where the similarity score was still
                          meaningful), and the full list of candidates to
                          choose from in TeknoParrotUI.

    Register manually    A TeknoParrot profile allows only one GamePath. If
    (duplicate)            this folder resolves to a profile code another
                          folder already claimed earlier in the same run
                          (common with multiple ROM revisions of one game
                          that share a generic exe name, e.g. several Virtua
                          Fighter 5 Lindbergh dumps, or multiple Taiko no
                          Tatsujin versions), it cannot be auto-registered
                          too. Right after registration, if any of these
                          are found, the script offers to resolve them on
                          the spot: for each one it shows which folder
                          currently holds the profile and which folder is
                          contesting it, then lets you choose [K]eep the
                          current copy, [S]witch the profile to the other
                          copy, or [Q]uit and leave the rest for manual
                          handling in TeknoParrotUI. Anything you don't
                          resolve still appears in ACTION REQUIRED.

  At the end of the run the ACTION REQUIRED section lists every game that
  needs manual registration.


-------------------------------------------------------------------------------
  HOW FUZZY MATCHING WORKS
-------------------------------------------------------------------------------

  Many platforms share a single executable file across all their titles. On
  NESiCAxLive, for example, every game uses game.exe. Without fuzzy matching,
  none of these games could be auto-registered.

  The script compares the game folder name against candidate profile codes and
  assigns a confidence score from 0.0 to 1.0:

    Score >= 0.72   Auto-registered. Shown in Cyan with the score so you
                    can spot-check the match.

    Score >= 0.40   Flagged in ACTION REQUIRED with a best-guess profile
                    shown. One click in TeknoParrotUI to confirm.

    Score < 0.40    Flagged in ACTION REQUIRED with only the full candidate
                    list. No reliable guess could be made.

  WHEN FUZZY MATCHING GETS IT WRONG

  If a game is registered against the wrong profile:
    1. Delete that game's .xml from UserProfiles.
    2. Add a forceArchetype entry in overrides.json to pin it to the correct
       profile on the next run: { "WrongCode": "CorrectCode" }

  If a game's control family is misdetected (e.g. a trackball game treated
  as lightgun), add a familyOverride entry in overrides.json.

  For details on the scoring algorithm and what is stripped from folder
  names before comparison, see APPENDIX: FUZZY MATCHING DETAILS.


-------------------------------------------------------------------------------
  CONTROL PROPAGATION
-------------------------------------------------------------------------------

  Binding controls for every game by hand is tedious when many games use the
  same device. Instead, bind ONE game of each control type, and the script
  copies those controls to the rest.

  How to use it:

    1. In TeknoParrotUi.exe, fully bind one game of each control type you
       use -- a lightgun game, a driving game, a fighting game, a trackball
       game, and so on. Bind everything: buttons, axes, Test, Service, Coin,
       Start. Good games to start with:

         Fighting / buttons    Street Fighter III, BlazBlue, Tekken 7,
                               Dead or Alive 5
         Driving               Daytona Championship USA, Initial D,
                               OutRun 2 SP, F-Zero AX
         Lightgun              House of the Dead 4, Aliens Extermination,
                               Point Blank
         Trackball             Golden Tee Live, Silver Strike Bowling,
                               Target Toss Pro

    2. Re-run this script. After registration it will run propagation and
       ask about your devices if it has not done so before.

  How it matches:

    Each control is matched by function (its input mapping and analog type),
    so a steering value is never copied onto a gun axis. The script copies
    each control's device exactly as you bound it, and carries aim-mode
    settings (relative input, sensitivity, hide-cursor) between same-type
    games so a copied game feels identical to the one you set up.

  Mixed devices in one game are fine. TeknoParrot stores each control's
  device individually, so a single game can use, for example, an Xbox stick
  to aim and arcade buttons to fire. Mixed setups copy across intact.

  What is safe:

    - The games you bind are read only and never modified.
    - A game you have already bound is detected and left unchanged.
    - Everything is reported so you can see exactly what changed.

  Before it asks "Propagate controls now?", the script lists each reference
  game along with the aim-mode settings it will copy (relative input,
  sensitivity, hide-cursor, "Use Keyboard/Button For Axis"). Check these
  against your real hardware before answering Y -- they apply to every other
  game of that type. For example, if you bind a driving game with a real
  wheel, "Use Keyboard/Button For Axis" should read False; if it reads True,
  answer N, fix the reference game in TeknoParrotUI, then re-run.

  The script also auto-flags a few known device-mismatch patterns with a red
  WARNING line, since they usually mean the reference game was bound with a
  substitute device instead of its real hardware:

    - Driving: "Use Keyboard/Button For Axis" = True (wheel/pedal axes would
      be read as digital keyboard input, not analog).
    - Lightgun: "Use Relative Input" = True (gun aim would be read as
      relative mouse movement, not absolute screen position).
    - Any sensitivity setting carried as 0 (silently disables aiming/axis
      response on every propagated game).

  A WARNING does not block propagation -- it is a prompt to double-check the
  reference game in TeknoParrotUI before answering Y.

  What stays manual (and is reported):

    - Game-specific controls that do not exist in the game you bound.
    - Any game whose control type you have not yet bound a reference for.
      These appear in the ACTION REQUIRED section at the end of the run
      with the control type name and a suggestion of which game to bind.

  After propagation, launch ONE updated game and test it before trusting the
  rest. If anything is wrong, restore from the backup made at the start of
  the run.


-------------------------------------------------------------------------------
  DEVICE SURVEY
-------------------------------------------------------------------------------

  On a first run (or on request) the script asks which controls you have:
  Xbox pad, arcade stick, trackball, spinner, wheel, lightgun, or keyboard.
  It then prints a plan of which game to bind with which device. It reads
  nothing and changes nothing; it is guidance for the binding step.

  If you have no lightgun, gun games can be aimed with the Windows mouse
  cursor (a mouse or trackball, absolute aim) or with the Xbox right stick.


-------------------------------------------------------------------------------
  FRONTEND LAUNCHER INTEGRATION
-------------------------------------------------------------------------------

  The script integrates with three frontends: LaunchBox, HyperSpin 2, and
  RetroBat/Batocera. LaunchBox and HyperSpin 2 receive your registered games
  as optional export steps at the end of each run. RetroBat/Batocera support
  is a one-time extraction setting that changes how game folders are named
  on disk.


  LAUNCHBOX
  ---------

  At the end of each run the script offers to add your registered games
  directly into LaunchBox:

      Add your registered games to LaunchBox now? (Y/N)

  Answering Y writes straight into LaunchBox's own Data\ files -- no import
  wizard step required. Before writing anything, the script:

      - Checks that LaunchBox and BigBox are both closed (refuses to write
        while either is running, since LaunchBox can overwrite external
        changes when it next saves).
      - Backs up every file it is about to change into
        Scripts\LaunchBoxBackups\<timestamp>\, preserving the same relative
        layout as your LaunchBox install. If the backup fails for any
        reason, nothing is written.
      - Creates the TeknoParrot emulator entry in LaunchBox if one does not
        already exist (or reuses your existing one by name, so re-running
        this never creates a duplicate).
      - Skips any game that already has an entry in the target platform, so
        re-runs never duplicate games or touch favorites/play counts you
        have already set in LaunchBox.

  The first time you use this, you are asked how TeknoParrot games should
  appear in LaunchBox:

      1) Mixed into your existing Arcade platform
      2) A separate "TeknoParrot" platform
      3) A separate platform with a name you choose
      4) Both -- mixed into Arcade AND a separate TeknoParrot platform

  Your choice is remembered and offered again (with the option to change it)
  on future runs. Choosing "Both" creates two separate game records (one per
  platform) pointing at the same TeknoParrot profile -- LaunchBox has no
  concept of one game belonging to two platforms at once, so favorites and
  play counts are tracked separately between the two views.

  New games have no box art or metadata yet, since this script has no way to
  populate LaunchBox's own scraped database fields. In LaunchBox, right-click
  a newly added game and use Edit... -> Search to fetch metadata and box art,
  the same way you would for any manually-imported game.

  If anything looks wrong afterward, use menu option 9 (Restore backup) and
  choose "LaunchBox library backup" to restore the exact files the script
  changed, from before it changed them.

  PREFER THE MANUAL IMPORT WIZARD INSTEAD?

  Answer N to the direct-integration question, then Y to the follow-up
  question, to get a reference file and step-by-step instructions for
  LaunchBox's own Import wizard instead -- useful if you would rather not
  let the script touch LaunchBox's files directly. This writes
  TeknoParrot-LaunchBox-Import.xml next to the script and prints the exact
  wizard steps, including the emulator command line
  (--profile=%romfile%.xml) and where to point the wizard (your
  UserProfiles folder, importing the profile *.xml files themselves --
  TeknoParrot launches games by profile, so the profile XML is what
  LaunchBox treats as the "rom" for each game, not the game's executable).


  HYPERSPIN 2
  -----------

  At the end of each run the script offers to add your registered games to
  HyperSpin 2's game list:

      Export registered games to HyperSpin 2? (Y/N)

  Answering Y locates the TeknoParrot system inside your HyperSpin 2 data
  folder (default: C:\ProgramData\HyperSpin\data) and merges in every
  registered game not already present. Your path is saved to config so the
  prompt is skipped on future runs.

  How it finds the TeknoParrot game list:

    HyperSpin 2 stores one JSON file per system under <dataPath>\games\.
    The script reads emulators.json to find TeknoParrot's entry, takes
    the system GUID from that entry, then scans the games subfolder for the
    JSON file whose entries reference the same GUID. If no file is found by
    GUID (older HyperSpin 2 installs where the emulator entry has no id), it
    falls back to looking for the file whose ROM entries use the .xml
    extension. If still no file is found, the script creates a new empty one
    named after the emulator title -- so no game needs to be added manually
    first.

    Title matching is flexible: "TeknoParrot", "Tekno Parrot", "teknoparrot"
    and other variations are all recognised by stripping spaces and
    punctuation before comparing.

  What it does:

    1. Checks that HyperSpin 2 is not currently running.
    2. Parses emulators.json to find the TeknoParrot entry.
    3. Locates or creates the TeknoParrot game list JSON in the games subfolder.
    4. Backs up the existing game list before any write (skipped if the file
       was just created).
    5. Checks every XML in your UserProfiles folder.
    6. For each registered game not already in the list, adds a new entry.
    7. Reports how many games were added (or confirms the list is up to date).

  Games already present in HyperSpin 2 are never duplicated.

  Games are added with title only. Use HyperSpin 2's Scrape feature to
  fetch box art, descriptions, and ratings for new entries.

  The export is skipped automatically in -Unattended mode. HyperSpin 2 must
  not be running when you answer Y; the script checks and will refuse to
  write if the process is detected.

  Prerequisites:

    - TeknoParrot must be set up as an emulator in HyperSpin 2 (it must
      appear in emulators.json with a title that contains "TeknoParrot",
      such as "TeknoParrot" or "Tekno Parrot").
    - No games need to be added to HyperSpin 2 first. The script creates the
      game list file if it does not yet exist.


  CROSSHAIR SETUP
  ---------------

  Mode 3 deploys custom crosshair cursor images to all registered lightgun
  games. It can also be run as a standalone mode at any time from the main
  menu without triggering a full AutoSync or registration pass.

  Supported games are those whose TeknoParrot profile has <GunGame>true</GunGame>
  in the UserProfile XML. This includes titles such as House of the Dead 4,
  Aliens Extermination, Aliens Armageddon, Rambo, and Terminator Salvation.

  HOW CROSSHAIRS WORK IN TEKNOPARROT

    TeknoParrot supports custom cursor images placed as P1.png and P2.png in
    the game's executable directory.

    ElfLdr2 games: a single shared pair is placed in the ElfLdr2 loader folder
    (searched dynamically since its exact name varies across installs).

    Pcsx2x6 games: P1.png and P2.png are placed in the pcsx2x6 emulator folder
    (searched as pcsx2x6, PCSX2x6, pcsx2, PCSX2, or any pcsx2-prefixed
    subfolder). If inis\PCSX2.ini exists, cursor_path is set automatically
    under [USB Port 1 guncon2] and [USB Port 2 guncon2]. Existing keys are
    replaced; missing keys are inserted; absent sections are appended.

    Standard games: each game receives its own P1.png and P2.png in the folder
    containing the game's executable.

  USING THE CROSSHAIR PICKER

    1. The script scans the Crosshairs\ folder next to the script for PNG
       files. Each file is validated against the PNG magic-byte signature;
       anything that fails validation is reported and skipped.

    2. An HTML preview grid (TeknoParrot-Crosshairs-Preview.html) is
       generated and opened in your default browser so you can browse all
       available designs visually before picking.

    3. Enter the index number for your Player 1 crosshair and Player 2
       crosshair. The two can be the same or different. The script
       remembers your last choice (by filename, so it still works if you
       add or remove PNGs from the folder) and offers it as a default --
       just press Enter to reuse it on your next run.

    4. The script copies the chosen images to every registered lightgun game
       folder, reporting the count of games deployed, skipped, and errored.

    5. After deploying, the script asks whether to also hide the Windows
       mouse cursor for all lightgun games. If you answer Y, it sets the
       cursor-hide field (HideCursor, "Hide Cursor", or DisableCursor
       depending on the game) to enabled in each gun game's UserProfile XML.
       A timestamped backup is taken automatically before any XML is changed.
       This step is independent -- you can answer N and run mode 3 again
       later if you change your mind.

  ADDING YOUR OWN CROSSHAIRS

    You can add any PNG image to the Crosshairs\ folder at any time. The
    script auto-detects all PNG files in the folder, validates them, and
    includes them in the preview grid on the next run. Files do not need to
    follow a specific naming convention -- but numbering them makes them
    easier to identify in the HTML preview.

    321 crosshair designs (000.png--320.png) are included in the package.
    Source: https://www.emuline.org/topic/3080-custom-crosshairs-emulators-loaders/


  RESHADE VISUAL ENHANCEMENTS
  ---------------------------

  What is ReShade?

    ReShade is a free, widely-used graphics tool that adds post-processing
    effects to games. It sits between the game and your screen, improving how
    the image looks without modifying any game files. If you remove ReShade
    (by deleting one file per game folder), the game is completely unchanged.

  What can it do for your arcade games?

    Sharpening       Many TeknoParrot games run at a fixed resolution and look
                     slightly blurry when stretched to fill a modern HD screen.
                     ReShade's sharpening filters restore the crisp look.

    CRT scanlines    Real arcade monitors use a CRT display that creates
                     horizontal scanlines across the image. ReShade can
                     reproduce this effect, making emulated games feel more
                     authentic on an LCD.

    Colour boost     Older graphics engines often produce flat, washed-out
                     colours on modern monitors. ReShade's colour and contrast
                     filters restore the vivid, punchy look of the original.

    Borders / bezels Some games are designed for a 4:3 aspect ratio but display
                     with black bars on a widescreen monitor. ReShade can fill
                     those bars with decorative arcade cabinet artwork.

  Your games work perfectly WITHOUT ReShade. It is entirely optional and
  can be uninstalled at any time. No knowledge of graphics or shaders is
  required to use it -- you pick effects through a simple in-game menu.

  HOW IT IS INSTALLED

    ReShade works by placing one DLL file in the same folder as a game's
    executable. When the game loads, it loads ReShade automatically. The DLL
    name depends on the graphics API the game uses:

      d3d9.dll       DirectX 9 games
      dxgi.dll       DirectX 10 / DirectX 11 games
      d3d12.dll      DirectX 12 games
      opengl32.dll   OpenGL games and BudgieLoader games

    The script detects the correct name automatically by scanning the game's
    executable. For BudgieLoader games it always uses opengl32.dll regardless
    of what the scan finds. For OpenParrot games the DLL is placed in an
    openparrot subfolder rather than the game root.

    You do not need to know any of this -- the script handles it for you.

  HOW TO SET IT UP

    The script looks for ReShade DLLs in the  ReShade\  folder next to the
    script and deploys the right one for each game's architecture:
      ReShade64.dll -- for 64-bit games (required for Mode 5 to work)
      ReShade32.dll -- for 32-bit games (optional; 32-bit games are skipped
                       if this file is absent)

    WHERE TO GET THE DLLS

    The DLLs are NOT included in the release ZIP or the source repository
    (ReShade is free software but its DLLs are not redistributable).
    Obtain them as follows:

    Step 1.  Go to  https://reshade.me  and download the free installer.
             Choose the standard version (not the add-on version) unless you
             know you need add-on support.

    Step 2.  Run the installer. When it asks for a game executable, point it
             at a 64-bit TeknoParrot game exe. It will create a DLL file in
             that game folder (e.g. dxgi.dll, d3d9.dll). Let the installation
             complete -- you do not need to select any shaders at this stage.

    Step 3.  Copy that DLL into the  ReShade\  folder next to this script
             and rename it to  ReShade64.dll.
             If you also have 32-bit games: repeat with a 32-bit game exe and
             rename the resulting DLL to  ReShade32.dll.

    Step 4.  Run TeknoParrot Manager and choose mode 5 (ReShade setup), or
             answer Y when prompted at the end of a normal run.

    The script will:
      a. Show the version of the bundled DLL and check reshade.me for updates.
      b. Check the Authenticode signature on the DLL(s) -- ReShade's own
         installer is code-signed, and that signature survives extracting
         and renaming the DLL. An invalid or missing signature is shown as
         a warning with the reason in plain English, but does NOT block
         setup -- you supplied this file yourself, just make sure it
         actually came from reshade.me.
      c. Ask whether you want to use a preset file (a ready-made set of
         effects), or just install the DLL and configure effects yourself.
      d. Let you pick which games to install ReShade on (all games, or a
         specific selection from a list).
      e. Copy the DLL with the correct name into each selected game folder.

  PER-GAME PRESETS

    The preset chosen in step (b) above applies to every selected game. To
    give one specific game a different preset (or a preset while leaving
    every other game on "no preset"), create a  ReShadePresets\  folder next
    to this script and drop a file named  ProfileCode.ini  in it -- for
    example  ReShadePresets\Daytona3.ini.

    A per-game file always overrides the global choice for that one game
    only; every other selected game still gets whatever was chosen in
    step (b). Find a game's profile code in
    TeknoParrot-Manager-controls.txt (written after every run).

    A file whose name does not match any registered profile code is reported
    as WRONG NAME and ignored, the same way CustomThumbnails handles a
    mismatched icon filename.

  USING RESHADE IN-GAME

    Once installed, launch any game that has ReShade and press the  Home  key.
    The ReShade overlay appears, showing a list of available effects. Toggle
    effects on or off with a tick-box, and adjust their settings with sliders.
    Your settings are saved automatically to a ReShade.ini file in the game
    folder, so you only need to configure once.

    Common effects to try for arcade games:
      LumaSharpen or CAS     Sharpening
      CRT_Royale or CRT_Lottes   CRT scanlines and curvature
      Levels or Vibrance     Colour and contrast
      Border                 Bezel artwork (requires a border image file)

  UPDATING RESHADE

    The script checks reshade.me for a newer version each time ReShade setup
    runs. If a newer version is available you will be told. To update:

    1. Download the new installer from reshade.me.
    2. Run it on any game exe (or extract the DLL manually with 7-Zip).
    3. Copy the new DLL to  ReShade\ReShade64.dll, replacing the old one.
       If you use ReShade32.dll for 32-bit games, update that file too.
    4. Re-run ReShade setup (mode 5) to redeploy the updated DLLs.

  REMOVING RESHADE

    To remove ReShade from a single game: delete the DLL file (d3d9.dll,
    dxgi.dll, d3d12.dll, or opengl32.dll) from that game's folder. If you
    copied a preset, delete ReShade.ini as well. Nothing else needs changing.

    To remove ReShade from all games: delete the named DLL from every game
    folder where you installed it. The ReShade\ folder next to the script can
    also be deleted -- it does not affect game operation.

  NOTE ON KEY CONFLICTS

    ReShade uses the  Home  key to open its overlay by default. If a game
    uses the same key for another function, you can change ReShade's key by
    editing the KeyOverlay value in the game's ReShade.ini file. Look for the
    line  KeyOverlay=  and change the key code there.

  ATTRIBUTION

    ReShade is developed by crosire and is distributed under the BSD 3-Clause
    licence. The included DLLs are unmodified binaries of the official ReShade
    release. For source code, full licence text, and the latest version see:
      https://reshade.me
      https://github.com/crosire/reshade

  Mode 10 (Library health check) reports, purely informationally, how
  many of your registered games have ReShade installed. This is not
  flagged as something to fix -- ReShade is a per-game cosmetic choice,
  not a clear right-or-wrong answer like a GPU fix.


  DGVOODOO2 LEGACY COMPATIBILITY
  --------------------------------

  What is dgVoodoo2?

    Some older arcade games were written for DirectX 8, DirectDraw (DX1-DX7),
    or the 3dfx Glide API. On modern PCs these calls can fail silently,
    producing crashes, black screens, or missing geometry.

    dgVoodoo2 (by Dege) is a free compatibility layer that intercepts those
    old graphics calls and re-issues them as modern DirectX 11/12 commands.
    It works by placing one or more small DLL files in the game's folder.
    Your original game files are never modified. To remove it, delete the
    DLL(s) from the game folder.

  What it fixes

    DX8 games     -- games that import  d3d8.dll  receive  D3D8.dll  (and
                     D3DImm.dll for the legacy immediate-mode layer).
    DDraw games   -- games that import  ddraw.dll  receive  DDraw.dll
                     (+ D3DImm.dll).
    Glide 2x/3x   -- games that import  glide2x.dll  or  glide3x.dll
                     receive the matching Glide wrapper.

  Should I use it?

    Only if a game crashes, shows a black screen, or renders incorrectly on
    first launch. Games that run correctly do not need it.

  How to set it up

    Method A -- Bundled folder (recommended):
      1. Download the latest dgVoodoo2 ZIP from:
           https://dege.freeweb.hu/dgVoodoo2/dgVoodoo2/
      2. Open the ZIP. Create a folder called  dgVoodoo2\  next to this
         script and copy in these files:
           From the  MS\x86\     subfolder : D3D8.dll  DDraw.dll  D3DImm.dll
           From the  3Dfx\x86\  subfolder : Glide2x.dll  Glide3x.dll
           From the root of the ZIP      : dgVoodoo.conf
      3. Run TeknoParrot Manager and choose mode 5 (dgVoodoo2 setup), or
         answer Y to the prompt at the end of a normal run.

    Method B -- Custom folder:
      Keep your dgVoodoo2 DLLs anywhere and enter the path when prompted.
      The path is saved to the configuration file so you only need to do
      this once.

  How the wizard works

    The wizard scans every registered game exe for legacy API imports and
    shows you a list of auto-detected games before asking for confirmation.
    You can install to all auto-detected games at once, or pick manually
    from the full list.

    For auto-detected games the script deploys only the DLL(s) needed for
    that game's API. For manually selected games with no detectable API,
    all available DLLs are deployed.

    If  dgVoodoo.conf  is present in your dgVoodoo2 folder, it is copied
    alongside the DLLs (once per game -- never overwritten on re-runs).

  Per-game config overrides

    The global  dgVoodoo.conf  above applies to every selected game. To
    give one specific game a different config, create a
    dgVoodoo2Presets\  folder next to this script and drop a file named
    ProfileCode.conf  in it -- for example  dgVoodoo2Presets\VF5.conf.

    Unlike the global conf, a per-game file always overwrites the
    destination on every run (it is an explicit per-game choice), so it
    takes effect even if a previous run already deployed a config to that
    game. Every other selected game is unaffected and still follows the
    "never overwrite" rule for the global conf. A filename that does not
    match any registered profile code is reported as WRONG NAME and
    ignored, the same way ReShadePresets and CustomThumbnails handle a
    mismatched filename.

  Removing dgVoodoo2

    Delete the deployed DLL files (D3D8.dll / DDraw.dll / Glide2x.dll /
    Glide3x.dll) and dgVoodoo.conf from the game's folder. Nothing else is
    changed.

  Mode 10 (Library health check) reports which registered games are
  eligible for dgVoodoo2 (import D3D8/DDraw/Glide) but don't have the
  matching DLL deployed yet, read-only and without changing anything.


  FORCE FEEDBACK (FFB) SETUP
  ---------------------------

  What is force feedback?

    Force feedback makes a wheel or stick push back / rumble to match what
    is happening on screen (road vibration, recoil, collisions). Mode 7
    covers two completely independent mechanisms. Neither requires the
    other, and both can be set up at once -- they cover different games.

  Mechanism 1 -- FFB Blaster (native, requires a paid membership)

    FFB Blaster is TeknoParrot's own built-in force feedback feature. It is
    well-integrated, but it ONLY works with an active, paid TeknoParrot
    membership:
      https://teknoparrot.com/en/Home/Subscription

    The script cannot check your subscription status, so it asks directly
    before changing anything. If you answer N, FFB Blaster is skipped --
    enabling the field without a membership has no effect.

    If you answer Y, the script scans your TeknoParrot install's
    GameProfiles for the FFB Blaster field (this is detected at runtime,
    not hardcoded, so it keeps working as TeknoParrot adds support for more
    games) and enables it on every registered profile that has it. Your
    UserProfiles are backed up first, same as every other destructive
    operation in this script.

  Mechanism 2 -- Third-party FFB plugin (free, no subscription needed)

    A free, separately-maintained plugin (mightymikem/FFBArcadePlugin) that
    adds force feedback to a different set of arcade racers and shooters.
    The script always fetches the current supported-games list and DLLs
    live from that project's GitHub repository -- nothing is bundled with
    this script, so the list of supported games can grow over time without
    needing a script update.

    Controller support (per the plugin's own documentation): true force
    feedback on FFB-capable wheels (Thrustmaster and similar), and rumble
    on Xbox/XInput-style controllers and similar rumble-capable pads. The
    plugin's own GUI (FFBPluginGUI.exe, not part of this script) has a
    "Reverse Rumble" option if a controller's motors feel backwards.

    If a game is covered by BOTH mechanisms, the script lists every such
    game once and asks a single question: keep FFB Blaster (native) for
    all of them, or use the third-party plugin for all of them instead.
    Your answer applies to every game in that overlap list for this run.

    Plugin DLL collisions: a few games need the same destination DLL name
    for both ReShade and this plugin (for example H2Overdrive needs
    d3d9.dll for both). If ReShade already occupies that filename in a
    game's folder, FFB plugin setup skips that game with a warning rather
    than overwriting it.

  Removing FFB

    FFB Blaster: there is no "undo" button in the menu -- manually set the
    field back to 0 in the affected UserProfiles\*.xml files, or restore
    from a pre-FFB backup (mode 9) if you ran this before enabling FFB
    Blaster.
    Third-party plugin: delete the deployed DLL file from the game's folder.


  BEPINEX UPDATE CHECK
  ----------------------

  What is BepInEx?

    BepInEx is a third-party Unity plugin/modding framework -- not part of
    TeknoParrot itself. A handful of TeknoParrot games need a community
    plugin running on top of BepInEx to get controls or fixes working.
    Mode 8 shows a live-fetched list of known examples (checked against
    the eggmansworld.github.io compatibility data each time you open this
    mode, so it keeps tracking new games as they're added upstream rather
    than going stale).

  What mode 8 does (and does not do)

    This mode ONLY checks and updates games that ALREADY have BepInEx
    installed. It never installs BepInEx into a game that doesn't have it
    -- if a game above isn't working and you suspect it needs BepInEx,
    that initial install is still a manual step (see the official BepInEx
    docs: https://docs.bepinex.dev).

    For every game with an existing BepInEx install, the script compares
    it against the latest STABLE release on GitHub. Only the 64-bit
    ("x64") build is ever used -- never a 32-bit build, and never a
    pre-release/beta build. If a game's existing install is 32-bit, it is
    left alone and reported separately; update that one manually.

    If anything is outdated, the script lists every such game once and
    asks a single question: update all of them to the latest version?
    Answering Y backs up the existing BepInEx folder and related files
    (to BepInEx_Backup_<timestamp> inside that game's own folder) before
    overwriting anything.

  Troubleshooting and manual reset

    Official troubleshooting guide:
      https://docs.bepinex.dev/articles/user_guide/troubleshooting.html

    To cleanly uninstall BepInEx from a game folder by hand (for example
    to start over after a problem), delete these from the game's folder:
      doorstop_config.ini
      winhttp.dll
      .doorstop_version
      changelog.txt
      the BepInEx folder
    This fully reverts the game to vanilla -- nothing else is touched.


  RETROBAT / BATOCERA
  -------------------

  RetroBat and Batocera require TeknoParrot game folders to end with a
  recognised suffix to be identified as TeknoParrot titles. The script
  supports all three variants:

    .teknoparrot   (most common -- used for new extractions)
    .parrot
    .game

  Extraction always creates .teknoparrot folders. The other two suffixes are
  recognised when detecting existing folders, so a library previously
  extracted by another tool is handled correctly without re-extraction.

  ENABLING RETROBAT MODE

  On a fresh setup (no saved config, or when you decline to reuse saved
  settings), the script asks:

      Is this a RetroBat/Batocera installation?
      (Y = game folders are named  GameName.teknoparrot  instead of  GameName)

  Answer Y and the setting is saved. The question is never asked again.

  To change the setting later: delete TeknoParrot-Manager.config.json and
  re-run, or edit the JSON file directly and set "RetroBat": true.

  WHAT CHANGES IN RETROBAT MODE

  AutoSync extraction. Games are extracted into folders named
  GameName.teknoparrot instead of GameName. For example:

      Standard mode:   E:\TeknoParrotGames\Daytona Championship USA (2017)[Sega]
      RetroBat mode:   E:\TeknoParrotGames\Daytona Championship USA (2017)[Sega].teknoparrot

  Registration. The suffix is stripped automatically before folder names are
  compared against TeknoParrot profiles. Registration, fuzzy matching, and
  the "Not in TeknoParrot" report all work identically to standard mode.

  Already-extracted detection. The script recognises existing folders with
  .teknoparrot, .parrot, or .game suffixes (as well as no suffix) when
  deciding whether to re-extract a game, so switching mode mid-library does
  not cause duplicate extractions.

  UPGRADING AN EXISTING LIBRARY TO RETROBAT NAMING

  If you have already extracted games without suffixes and want to switch to
  RetroBat naming:

    1. Decline "Use these settings?" (press N) so the RetroBat prompt appears.
    2. Answer Y to RetroBat mode.
    3. Delete TeknoParrot-Manager.syncstate.json from your staging folder to
       force re-extraction (otherwise the script sees the old folders as
       already extracted and will not create the new .teknoparrot ones).
    4. Re-run. Games will be re-extracted with .teknoparrot folder names.

  Note: the old folders are never deleted automatically. You can remove them
  manually once the new .teknoparrot folders are confirmed working.


-------------------------------------------------------------------------------
  THUMBNAIL DOWNLOAD
-------------------------------------------------------------------------------

  After registration the script offers to download game icons:

      Download thumbnails for registered games missing an icon? (Y/N)

  Answering Y connects to the TeknoParrotUIThumbnails repository on GitHub
  and downloads a <ProfileCode>.png for every registered game that does not
  already have one in <TeknoParrotRoot>\Icons\. That is the exact folder
  TeknoParrotUI reads when it displays game thumbnails.

  Source repository:
    https://github.com/teknogods/TeknoParrotUIThumbnails

  What it does:

    1. Copies any PNG files from the  CustomThumbnails\  folder next to the
       script into <TeknoParrotRoot>\Icons\ (see CUSTOM THUMBNAILS below).
    2. Checks every XML in your UserProfiles folder.
    3. For each profile code, checks whether <TeknoParrotRoot>\Icons\<Code>.png
       already exists. If it does, that game is counted as "already present"
       and skipped -- nothing is overwritten.
    4. Downloads each missing icon from the repository.
    5. Reports a summary: fetched / already present / not in repo / failed.

  The Icons folder is created automatically if it does not exist.

  Note that not all TeknoParrot games have a thumbnail in the repository.
  Games without a matching icon are counted as "not in repo" and skipped
  without error.

  The download uses TLS 1.2, which GitHub requires but which PS 5.1 may
  not negotiate by default. The script sets it automatically for this step.


  CUSTOM THUMBNAILS

  There are two ways to provide your own icons:

  Option A -- CustomThumbnails\ folder (recommended for most users):

    Create a  CustomThumbnails\  folder next to the script (in the same
    folder as TeknoParrot-Manager.ps1). Drop your PNG files in there,
    named <ProfileCode>.png (for example, Daytona3.png or HouseOfDead4.png).

    Every time you run the thumbnail download step, the script copies any
    PNG files from that folder into TeknoParrot's Icons folder automatically.
    You never have to touch the TeknoParrot installation folder yourself.

    Files are only copied if the destination does not already exist. Your
    custom thumbnails are never overwritten by the GitHub download.

    Name validation: before copying, each file is checked against the list
    of registered profile codes. If a filename does not match any registered
    game, the script shows a clear warning and skips that file -- it is NOT
    copied until the name is corrected. This catches typos before they cause
    silent failures. The warning message tells you to check
    TeknoParrot-Manager-controls.txt for the correct profile code name.

  Option B -- Icons folder directly:

    Drop your PNG files directly into  <TeknoParrotRoot>\Icons\  named
    <ProfileCode>.png. The script sees them as "already present" on the next
    run and never overwrites them.

  How to find the profile code for a game:

    The profile code is TeknoParrot's internal name for a game. It is NOT
    always the same as the game's display name. There are three easy ways
    to find it:

    Method 1 -- controls file (easiest after your first run):
      After any run, TeknoParrot Manager writes a file called
      TeknoParrot-Manager-controls.txt next to the script. Open it -- every
      registered game is listed with its profile code. Copy the exact name
      from that file and add .png to get the thumbnail filename.

    Method 2 -- Icons folder:
      If you have previously downloaded thumbnails, open TeknoParrot's
      Icons folder. The filenames there ARE the profile codes. Match your
      own images to the same naming pattern.
      Typical location:  <TeknoParrotRoot>\Icons\

    Method 3 -- UserProfiles folder:
      TeknoParrot stores one .xml file per registered game in its
      UserProfiles folder. Each file is named  ProfileCode.xml. Remove
      the .xml extension to get the thumbnail filename.
      Typical location:  <TeknoParrotRoot>\UserProfiles\

    Examples:
      Display name                  Profile code      Thumbnail filename
      ----------------------------  ----------------  --------------------
      Daytona Championship USA      Daytona3          Daytona3.png
      House of the Dead 4           HouseOfTheDead4   HouseOfTheDead4.png
      Aliens Extermination          AliensExtermination  AliensExtermination.png
      Tekken 7                      Tekken7           Tekken7.png


-------------------------------------------------------------------------------
  "NOT IN TEKNOPARROT" REPORT
-------------------------------------------------------------------------------

  After scanning your staging folder and completing registration, the script
  reports any game folder whose executables did not match any profile in
  TeknoParrot's GameProfiles library:

      1 game folder(s) not recognised by TeknoParrot -- see ACTION REQUIRED

  The ACTION REQUIRED section at the end of the run lists the folder names.
  This is informational -- no action is needed. It tells you whether a folder
  contains a game TeknoParrot does not yet support, a game that uses an
  unusual executable name, or a utility folder sitting alongside your games.

  What this is NOT:

    - A game that shares an executable name with multiple profiles -- those
      appear in "Register these games" (manual registration required).
    - A game whose path is broken -- those appear in "Fix these game paths".
    - A game not yet extracted -- those appear in "Extract first".

  The "not in TeknoParrot" report is specifically for folders where no
  executable matched any profile at all. If you have a dat file configured,
  these folders are also tried against the dat by normalized name (and by
  fuzzy scan if needed) before they reach this report -- so the list is
  shorter when a dat is configured.


-------------------------------------------------------------------------------
  CONTROLS STATUS FILE
-------------------------------------------------------------------------------

  After every run the script writes TeknoParrot-Manager-controls.txt next to
  itself. This file is a current-state snapshot of every registered game:

    [button]
      BlazBlueContinuumShift     52/52 bound   REFERENCE
      AkaiKatanaShinNesica       47/52 bound   propagated  <- BlazBlueContinuumShift
      StreetFighter6             47/52 bound   propagated  <- BlazBlueContinuumShift
        manual: SpeedChange1, SpeedChange2, SpeedChange3

    [driving]
      Daytona3                   31/31 bound   REFERENCE
      InitialD8                  29/31 bound   propagated  <- Daytona3
        manual: GearUp, GearDown

    [lightgun]
      SomeNewGame                 0/52 bound   no controls

  Each game shows:
    - Control family (button, driving, lightgun, trackball, analog, spinner)
    - How many buttons are bound out of the total in the profile
    - Status: REFERENCE (your bound example game), propagated (controls were
      copied from a reference), already bound (had controls before this run),
      bound (bound but not via propagation), partial (some bound, below
      threshold), no controls, no reference game (waiting for you to bind one)
    - Which reference game the controls came from (for propagated games)
    - Any buttons still left manual (listed by name)

  The file is overwritten on every run. It reflects the state of your
  UserProfiles at the moment the script completed, regardless of whether
  propagation was run or skipped this time.

  This is particularly useful when a game aims wrong days or weeks later --
  open the file and you can immediately see whether controls were propagated
  and from which reference game, without re-running the script.


-------------------------------------------------------------------------------
  PER-GAME OVERRIDES
-------------------------------------------------------------------------------

  The file TeknoParrot-Manager.overrides.json (created empty next to the
  script on first run) lets you fine-tune individual games. Edit it with
  any text editor. All keys are optional:

    {
      "noSync":         ["ZipBaseName1", "ZipBaseName2"],
      "onlySync":       ["ZipBaseName1", "ZipBaseName2"],
      "noPropagate":    ["ProfileCode1", "ProfileCode2"],
      "forceArchetype": { "ProfileCode": "ReferenceProfileCode" },
      "familyOverride": { "ProfileCode": "trackball" },
      "datFile":        "C:\\full\\path\\to\\collection.dat"
    }

    noSync          ZIP base names (file name without .zip) to always skip
                    during extraction, even when extracting all games.

    onlySync        Whitelist. If this list is non-empty, ONLY these ZIPs
                    are extracted. This bypasses the interactive selection
                    menu and is useful for scripted or repeatable runs.
                    For casual use, the interactive picker is easier.

    noPropagate     Profile codes (UserProfile file name without .xml) to
                    leave untouched during control propagation.

    forceArchetype  Pin a game to copy its controls from a specific reference
                    game instead of the automatic best match. Useful when the
                    script picks the wrong game type for an unusual title.
                    Format: { "GameProfileCode": "ReferenceProfileCode" }

    familyOverride  Override the auto-detected control family for a game.
                    Use this when the script mis-classifies a title (for
                    example, FamilyGuyBowling is detected as a lightgun game
                    because of its input mappings, but it should draw controls
                    from the trackball pool).
                    Valid values: "button", "driving", "lightgun",
                                  "trackball", "analog", "spinner"
                    NOTE: "spinner" is never auto-detected. Spinner games
                    must always be assigned explicitly via familyOverride.
                    Format: { "GameProfileCode": "trackball" }

    datFile         Full path to a No-Intro TeknoParrot dat file (for example
                    the Eggman/RomVault collection dat). Overrides the dat path
                    entered during initial setup. When set, the script reads
                    the dat's <GameProfile> and <Executable> fields and uses
                    them to auto-register games across three scenarios: shared
                    executables, exe-less-matched folders, and slightly misnamed
                    folders (fuzzy fallback). The dat is loaded once before the
                    main menu loop and reused each run.
                    Leave this key empty or omit it entirely to use the path
                    from setup (config.json), or if you do not have a dat file.
                    Format: "C:\\path\\to\\TeknoParrot Collection.dat"

  Leave any key empty or omit it if you do not need it. Bad or missing
  entries are ignored safely.

  Note on ZIP base names: these are the ZIP file names without the .zip
  extension, exactly as they appear in your source folder.


-------------------------------------------------------------------------------
  ACTION REQUIRED SUMMARY
-------------------------------------------------------------------------------

  At the end of every run, the script prints an ACTION REQUIRED section
  listing everything that needs your attention. It has up to nine parts:

    Not in TeknoParrot        Game folders whose executables did not match
                              any TeknoParrot profile. Informational -- no
                              action is needed. See the full section above.

    Register these games      Games found on disk that could not be
                              auto-registered because either their executable
                              name is shared by multiple TeknoParrot profiles
                              and the folder-name similarity score was below
                              the auto-register threshold, or the one profile
                              they match was already claimed by another folder
                              earlier in the same run. Shows the executable to
                              browse to, a best-guess profile where the score
                              was still meaningful (or which folder already
                              holds the profile, for the duplicate case), and
                              the full candidate list.

    Fix these game paths      Profiles with a broken path that could not be
                              auto-repaired because the executable is shared
                              across multiple game folders. Shows which
                              profiles need fixing and which executable to
                              look for, grouped to keep the list compact.

    Extract first             Profiles with a broken path because the game
                              has not been extracted to your staging folder
                              yet. No action needed now -- extract the game
                              and re-run Repair.

    Set up controls           Control types for which no reference game has
                              been bound yet. Shows which games are waiting
                              and suggests specific titles to bind in
                              TeknoParrotUI for each type.

    Path too long             Specific games (Raw Thrills titles, Yu-Gi-Oh!
                              Duel Terminal 6) whose install path exceeds a
                              hard-coded engine-specific length limit and
                              may fail to launch. Shows the exact short
                              folder name to rename to.

    File version mismatch     Specific games needing an OLDER, specifically
                              pinned version of a particular file rather
                              than the latest one (BlazBlue-series games and
                              iDmacDrv32.dll; Tekken Tag Tournament 2 and
                              EBOOT.BIN). Shows the file name, current and
                              required CRC32, and where to get the right
                              version.

    GPU incompatibility       Specific registered games confirmed NOT to
                              work on your detected GPU vendor (AMD or
                              Intel -- NVIDIA has no known-broken titles
                              in this data). Informational only -- no fix
                              exists, this just saves you troubleshooting
                              time on something that was never going to work.

    Setup notes               Any currently registered game that has special
                              setup notes in the community compatibility
                              database (eggmansworld.github.io/TeknoParrot) --
                              workarounds, known quirks, anything else that
                              site's maintainer has written up for that game.
                              Shows the executable TeknoParrot expects to run
                              and the full notes text, word-wrapped and
                              separated game-by-game so long entries stay
                              readable. Informational only.

  These last four checks run automatically on every AutoSync/Register
  run -- no separate mode needed. The GPU check silently skips if your
  GPU vendor cannot be auto-detected -- it never prompts mid-run. The
  setup notes check needs a live fetch of that site's data and is skipped
  (with nothing shown) if the fetch fails -- it never blocks the rest of
  the run.

  At the end of every registration run that has action items, the same list
  is also saved to a text file -- TeknoParrot-Manager-ActionItems.txt next to
  the script by default. A Save dialog lets you pick a different location or
  file name; it's skipped automatically during unattended runs and preview/
  dry-run mode, both of which just save to the default path with no prompt.
  The script tells you the path when it writes the file.


-------------------------------------------------------------------------------
  UNATTENDED / SCHEDULED MODE
-------------------------------------------------------------------------------

  Run the script with -Unattended to skip all prompts and proceed automatically:

      .\TeknoParrot-Manager.ps1 -Unattended

  What it does automatically:

    - Loads saved settings from TeknoParrot-Manager.config.json (exits with
      an error if no saved settings exist -- run once interactively first).
    - Auto-detects the TeknoParrot path if not in saved settings.
    - Selects ALL unextracted games (equivalent to pressing A in the picker).
    - Downloads missing thumbnails.
    - Runs repair.
    - Propagates controls if reference games are available.
    - Skips LaunchBox and HyperSpin 2 export (use interactively when needed).
    - Always writes the controls status file.
    - Logs every auto-decision to TeknoParrot-Manager.log.

  What it does NOT do:
    - It will not proceed without saved settings (exits cleanly with an error).
    - It will not proceed without a valid TeknoParrot root (exits cleanly).
    - It will not run Restore mode (exits with an error -- restore requires
      you to pick a backup interactively; use interactive mode for this).
    - It continues through low disk space and backup warnings but logs them.

  SCHEDULING WITH WINDOWS TASK SCHEDULER

  To run the script automatically overnight:

  Step 1.  Run the script once interactively and save your settings.

  Step 2.  Open Task Scheduler (taskschd.msc).

  Step 3.  Create Task (not Basic Task). On the General tab:
             - Name: TeknoParrot AutoSync
             - Run whether user is logged on or not (if you want it headless)
             - Run with highest privileges

  Step 4.  Triggers tab: New -> On a schedule, set your preferred time.

  Step 5.  Actions tab: New -> Start a program.
             Program: powershell.exe
             Arguments: -ExecutionPolicy Bypass -NonInteractive -File
               "W:\Emulators\TeknoParrot\Scripts\TeknoParrot-Manager.ps1"
               -Unattended
             (adjust the path to match your Scripts folder)

  Step 6.  Conditions tab: optionally check "Start only if the following
           network connection is available" and select your NAS connection.

  After each scheduled run, check TeknoParrot-Manager.log for a summary and
  TeknoParrot-Manager-controls.txt for the updated controls state.


-------------------------------------------------------------------------------
  GAME REPAIR
-------------------------------------------------------------------------------

  After registration the script offers to repair broken game paths. A path is
  broken if it is empty or points to a file that no longer exists (for
  example after moving or re-extracting a game). Repair finds the game by its
  executable name in your staging folder and updates the path.

    Fixed                The path was re-pointed to the correct executable.
    Not yet extracted    The game has not been extracted to the staging folder
                          yet. Extract it first, then run Repair again.
    Register manually    The executable is shared by multiple games and cannot
                          be safely auto-assigned. Use TeknoParrotUI to point
                          this profile to the correct game folder.

  Games whose path already works are left untouched.


-------------------------------------------------------------------------------
  CONTROLLERS AND INPUT NOTES
-------------------------------------------------------------------------------

  - Input method. Most games can be bound using XInput, RawInput or
    DirectInput. You choose this per game in the TeknoParrot UI when you
    bind your reference game; the script copies whatever you chose.

  - Keyboard. With no controller, map the keyboard in TeknoParrot's controller
    setup and use a keyboard-bound game as the reference for similar games.

  - Negative pedals. Some racing games expect a pedal on a negative axis (for
    example Y- or Z-). Bind it that way in your reference game and the script
    carries the setting across.

  - Unsupported controllers. If a pad is not recognised, wrappers such as
    DS4Windows or XInputPlus can make it appear as an XInput device. These
    run outside this script.

  - Light guns. A gun such as the Sinden presents to Windows as a pointer and
    is bound in RawInput mode. Bind it on your lightgun reference game and it
    propagates; gun calibration lives in the gun's own software.


-------------------------------------------------------------------------------
  SAFETY, BACKUP AND LOG
-------------------------------------------------------------------------------

  Backup. Before any change, the script copies your entire UserProfiles
  folder to:

    <TeknoParrot>\UserProfiles\FullBackup\<date_time>\

  If backup folder creation fails (for example, disk full or permissions),
  the script exits rather than proceeding without a restore point. If any
  files fail to copy during the backup, the script asks before continuing.

  To restore from inside the script, choose mode 9) Restore from backup at
  the startup menu. The script checks that TeknoParrot is fully closed first,
  lists all available backups with file counts, and asks you to type YES to
  confirm before changing anything.

  To restore manually: close TeknoParrot completely, then copy the .xml files
  from a backup folder back into UserProfiles, overwriting the current ones.

  Log. Every run appends to TeknoParrot-Manager.log next to the script:
  what was extracted, registered, repaired and propagated, and any errors.
  It also records a download audit trail -- source URL, filename, version
  (where known), and SHA256 -- for every third-party binary the script
  fetches (the Eggman dat ZIP, the BepInEx release, and the FFBArcadePlugin
  DLLs). This does not verify or block anything; it is a record you can
  check later if you want to confirm what was actually downloaded.

  If the log file is inaccessible (permissions, disk full, or path issue),
  the script does not fail silently:
    - A one-time warning is printed to the console showing the log path and
      the exact error so you can diagnose it.
    - Every subsequent entry that cannot be written is echoed to the console
      prefixed with [UNLOGGED] so nothing is lost during the run even though
      the file is unavailable.
  The script continues normally in both cases.


-------------------------------------------------------------------------------
  RE-RUNNING
-------------------------------------------------------------------------------

  Run the script as often as you like. Each run backs up first, then only
  does what is needed: new games are extracted and registered, unchanged games
  are skipped, already-bound games are left alone. Safe to re-run any time.


-------------------------------------------------------------------------------
  RESETTING
-------------------------------------------------------------------------------

  Saved settings      Delete TeknoParrot-Manager.config.json to be prompted
                      for folders and mode again on the next run.

  Re-extract all      Delete TeknoParrot-Manager.syncstate.json from your
                      staging folder to treat all ZIPs as new on the next run.

  Re-register one     Delete that game's .xml from UserProfiles, then re-run.
                      Note: this discards any manual bindings in that file.


-------------------------------------------------------------------------------
  TROUBLESHOOTING
-------------------------------------------------------------------------------

  A game appears in TeknoParrotUI but won't launch.
    Its GamePath is pointing to the wrong executable, or the game was not
    fully extracted. Open TeknoParrotUI, find the game, and point it to the
    correct .exe. Re-run the script and choose Repair to fix broken paths
    automatically where possible.

  A game does not appear in TeknoParrotUI after running the script.
    Check the ACTION REQUIRED section printed at the end of the run. The game
    may need manual registration (shared executable, or its profile was
    already claimed by another copy of the game -- see "Register these
    games") or may not yet be extracted ("Extract first"). If neither applies,
    check TeknoParrot-Manager.log for a registration error for that game.

  A game does not extract.
    Check that the ZIP source path is correct and the file is not corrupted.
    A failed extraction leaves no partial folder behind -- the next run retries
    automatically. If it keeps failing, check the log for the specific error
    and verify the staging drive has sufficient free space.

  An extraction was interrupted and the game re-extracts every run.
    The .extracting sentinel was not cleaned up (this should be rare -- the
    script uses try/finally to remove it unconditionally). Delete the file
    named <GameName>.extracting from your staging folder and re-run.

  Controls are not being copied to a game.
    Either no reference game for that control type has been bound yet (see
    "Set up controls" in ACTION REQUIRED), or the game is in the noPropagate
    list in overrides.json, or the game already has five or more bound
    controls and is treated as a reference game itself.

  The console shows [UNLOGGED] entries.
    The log file (TeknoParrot-Manager.log) cannot be written to. Check that
    the TeknoParrot folder is not read-only and you have write permission.
    The [UNLOGGED] entries are echoed on-screen so nothing is lost this run.

  A fuzzy-matched game was registered against the wrong profile.
    Delete that game's .xml from UserProfiles and add a forceArchetype entry
    in overrides.json: { "WrongProfileCode": "CorrectProfileCode" }. Re-run
    and the correct profile will be used.

  A game's controls are wrong after propagation.
    Use mode 9) Restore from backup to roll back to the backup made at the
    start of that run, or delete the affected game's .xml from UserProfiles
    and re-run propagation after correcting the reference game's bindings in
    TeknoParrotUI.

  A game appears twice in TeknoParrotUI.
    Two UserProfile files exist for the same game. This can happen if the
    game was registered manually and then again by the script. Delete one of
    the duplicate .xml files from UserProfiles. Keep the one with the correct
    GamePath and any manual bindings you have already set.

  HyperSpin 2 export fails with "TeknoParrot not found in emulators.json".
    TeknoParrot must be set up as an emulator in HyperSpin 2 before the
    export can add games. Open HyperSpin 2, add TeknoParrot as an emulator
    (the title must contain "TeknoParrot" -- variations like "Tekno Parrot"
    are fine), then re-run the export.

  HyperSpin 2 export fails with "Could not find a TeknoParrot game list".
    This can happen if the TeknoParrot emulator entry in HyperSpin 2's
    emulators.json has no GUID and the games folder contains no JSON file
    whose ROM entries use the .xml extension. Verify that TeknoParrot is
    fully set up as an emulator in HyperSpin 2 (not just listed but
    properly configured with its executable path), then try the export
    again. Check TeknoParrot-Manager.log for the exact failure detail.


-------------------------------------------------------------------------------
  WHAT IT DOES NOT DO
-------------------------------------------------------------------------------

  - It does not invent control bindings. A control is set only when a
    reference game you have bound already has it. Everything else is left
    for you and reported in the ACTION REQUIRED summary.

  - It does not provide game files. You supply your own legally obtained
    games; the script only registers and configures them.


-------------------------------------------------------------------------------
  APPENDIX: FUZZY MATCHING DETAILS
-------------------------------------------------------------------------------

  THE ALGORITHM

  The script uses a Sorensen-Dice bigram similarity score -- a standard string
  similarity algorithm that counts how many two-character pairs the two
  strings have in common. Scores range from 0.0 (no similarity) to 1.0
  (identical).

  Example:
    Folder:  "Akai Katana Shin (2012)[Taito NESiCAxLive][TP]"
    Profile: "AkaiKatanaShinNesica"

  After normalisation (stripping years, version strings, bracket metadata,
  splitting CamelCase, lowercasing):
    Folder:  "akaikatanashin"
    Profile: "akaikatanashinnesica"

  Dice similarity: ~0.85 -- well above the auto-register threshold of 0.72.

  THE THRESHOLD

  The threshold is the constant $FuzzyAutoThreshold near the top of the
  helper functions block in the script. Raising it makes auto-registration
  more conservative (fewer matches, less chance of a wrong one); lowering
  it is more aggressive (more matches, higher chance of error).

  WHAT IS STRIPPED DURING NORMALISATION

  The following are always removed before comparison:
    - Square-bracket metadata: [Sega NESiCAxLive][TP]
    - Bare 4-digit years: (2012)
    - Full ISO date strings: (2015-12-28) -- common in Eggman dat names
    - Decimal version strings without a ver/v prefix: (2.10.00), (1.00.48)
    - Known region/territory codes: (JPN), (USA), (EUR), (EXP), and others
    - Version strings with prefix: (ver 1.1), (rev 2), (v3), (v1.2b)
    - Parenthesised pure numbers: (2), (12)

  Meaningful parenthesised names like (Special Edition) are intentionally
  kept -- they may be the only thing distinguishing two game titles.


===============================================================================
  v0.98 BETA -- Test one game after each run.
  Profiles are backed up automatically at the start of every run.
===============================================================================
