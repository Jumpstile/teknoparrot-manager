===============================================================================
  TeknoParrot Manager  |  v1.0 RC9.1
  Author: Jumpstile
===============================================================================

  Registers your extracted games with TeknoParrot so they appear and launch
  automatically, copies your controls between games of the same type, and
  keeps your game library organized. Windows / PowerShell 5.1+.

  Made for beginners, and useful if you already know TeknoParrot. It hides
  complexity, not detail: repeatable bulk steps save manual work, it backs
  up your game settings before it changes them, and Details and the log
  show what was done. See docs\ADVANCED-USERS.md.

  This is v1.0 RC9.1, the latest published release:
  https://github.com/Jumpstile/teknoparrot-manager/releases/tag/v1.0-RC9.1
  The previous published release is v1.0 RC9:
  https://github.com/Jumpstile/teknoparrot-manager/releases/tag/v1.0-RC9
  If you use RC9, choose 15) Check for Updates to get RC9.1.
  Older published releases: v1.0 RC8.4, RC8.3, RC8.2, RC8.1, RC7 and RC6.
  RC8 was a tester build and was never published.
  Final Version 1.0 has not been published yet.
  The changes since RC9 are in TeknoParrot-Manager-CHANGELOG.txt.
  All releases: https://github.com/Jumpstile/teknoparrot-manager/releases

  Test one game after each run. AutoSync backs up UserProfiles before
  extraction; preview mode skips that backup.

  New? Open docs\START-HERE.md first; when stuck, see docs\TROUBLESHOOTING.md.

  For a one-page version, see TeknoParrot-Manager-QuickStart.txt.

  That same QuickStart file is also a complete beginner walkthrough.
  It works offline, so you do not need the docs folder.

  It has the full install steps, the first-run answers, a glossary and
  ten troubleshooting cases.

  Allow about 10 minutes once your downloads are ready.
  Installs and special controllers take longer.

  TeknoParrot Manager never provides, downloads, or links to games, ROMs,
  or patch files.

  What the normal backup saves:

    -- It copies TeknoParrot's saved game settings folder (UserProfiles).

  What it does NOT save:

    -- game-side NVRAM (the game's own saved memory)
    -- test-menu settings
    -- calibration files outside UserProfiles
    -- whole games

  Back those up yourself, separately.

  Other actions make their own small saved copies. These are not
  whole-game protection. See issue 378:
  https://github.com/Jumpstile/teknoparrot-manager/issues/378




-------------------------------------------------------------------------------
  CONTENTS
-------------------------------------------------------------------------------

  This is a plain-text file, so the names below are not clickable.

  To jump to a section, press Ctrl+F (Find). Then type the heading shown
  below in capitals.

    WHO IS THIS FOR?
    FEATURES
    GLOSSARY                       -- unfamiliar terms used throughout this file
    HOW IT WORKS
    REQUIREMENTS
    RUNNING THE SCRIPT
    AUTO-DETECT TEKNOPARROT PATH
    MODES                          -- the main menu, one entry per mode
    GAME SELECTION (AutoSync mode)
    THE STAGING FOLDER
    REGISTRATION
    HOW FUZZY MATCHING WORKS
    CONTROL PROPAGATION
    PROPAGATE CONTROLS              -- mode 4
    DEVICE SURVEY
    FRONTEND LAUNCHER INTEGRATION
      LAUNCHBOX
      RETROBAT / BATOCERA
    CROSSHAIR SETUP                -- mode 5
    RESHADE VISUAL ENHANCEMENTS    -- mode 6
    DGVOODOO2 LEGACY COMPATIBILITY -- mode 7
    GPU COMPATIBILITY FIXES        -- mode 8
    FORCE FEEDBACK (FFB) SETUP     -- mode 9
    BEPINEX SETUP                   -- mode 10
    REGION SETUP                   -- mode 11
    REQUIRED GAME PATCHES          -- mode 13
    POSTGRES SETUP                 -- mode 12
    CHECK FOR UPDATES              -- mode 16
    CREATE SUPPORT PACKAGE          -- mode 17
    THUMBNAIL DOWNLOAD
    "NO PROFILE MATCH" REPORT
    CONTROLS STATUS FILE
    PER-GAME OVERRIDES
    ACTION REQUIRED SUMMARY
    UNATTENDED / SCHEDULED MODE
    GAME REPAIR
    CONTROLLERS AND INPUT NOTES
    SAFETY, BACKUP AND LOG
    RE-RUNNING
    RESETTING
    TROUBLESHOOTING
    WHAT IT DOES NOT DO
    SUPPORT / CONTRIBUTING
    LICENSE
    APPENDIX: FUZZY MATCHING DETAILS


-------------------------------------------------------------------------------
  WHO IS THIS FOR?
-------------------------------------------------------------------------------

  TeknoParrot Manager is for people with large TeknoParrot collections.

  It handles registration, controls and game management for you.
  (Registration means telling TeknoParrot where each game is.)

  You will get the most out of it if you:

    -- have a large collection (dozens or hundreds of games)
    -- keep your games as ZIP files on a NAS (a storage box on your network)
       and want them unzipped for you

    -- use LaunchBox, RetroBat, or Batocera to start your games
       (these are called frontends)

    -- want crosshairs, ReShade, or dgVoodoo2 set up across all your games
       at once, rather than game by game

  You may not need this script if:

    -- you only have a handful of games
    -- you prefer to register and configure games by hand in TeknoParrotUI


-------------------------------------------------------------------------------
  FEATURES
-------------------------------------------------------------------------------

  This section lists what TeknoParrot Manager can do.

  Every feature has a short plain summary first. The technical details
  come last, in blocks that start with MORE DETAIL. You can skip those
  blocks the first time you read this.

  Registering a game means telling TeknoParrot where the game is. After
  that, the game shows up and starts in TeknoParrotUI.

  Getting your games in
  ---------------------

  - Automatic extraction (AutoSync). Copies and unzips your game ZIP files
    into a folder you choose. It skips games that are already done.

  - Game selection. Pick everything, browse an A-Z list, or search by name.

  - Extraction progress. A progress bar shows how far each game has got.

  - Smart folder matching. It will not make a second copy of a game that
    is already there under an older folder name.

  - Auto-detect TeknoParrot path. It finds your TeknoParrot folder for you
    on first run.

  Telling TeknoParrot about your games
  ------------------------------------

  - Automatic registration. It finds your games and registers them.
    Games you already registered are not overwritten. The one exception is
    a duplicate you choose to switch yourself: you are asked first, and a
    backup is made first. One more exception: if an already-added game's
    saved path points into another game's folder, TeknoParrot Manager
    fixes it to the game's own folder. It backs up first and writes the
    change to the log.

  - Fuzzy name matching. When several games share one file name, it picks
    the closest match to the folder name. If it is not sure, it asks you.

  - Dat file (optional). A community list that matches game files to their
    real titles. It helps when a game's files do not say what it is.

  - Already-registered detection. Games you set up yourself are not
    flagged again on every run.

  - Game folders not recognized list. It lists game folders it could not
    match to any game setup file, so you know which ones to check.

  - Game repair. It fixes broken or empty game paths.

  - Thumbnail download. It can fetch game icons for you. It never
    overwrites icons you already have.

  Controls
  --------

  - Control propagation. Set up the buttons for ONE game of each type.
    TeknoParrot Manager copies them to the other games of that type.

  - Device survey. You say which controls you own. It tells you which
    game to set up first with which device.

  - Controls status file. After every real run it writes a list of your
    games and their control state.

  - Crosshair setup. Gives your lightgun games custom crosshair pictures.

  Picture, sound and compatibility helpers (all optional)
  -------------------------------------------------------

  - ReShade visual enhancements (menu option 6). Adds screen looks such as
    CRT scanlines or a soft glow. You can change or undo the look later.
    You can do that for all games or for one game.

  - dgVoodoo2 (menu option 7). Helps older games that crash or show a
    black screen.

  - GPU compatibility fixes (menu option 8). Applies the right fix for
    your graphics card (AMD, NVIDIA or Intel).

  - Force feedback (FFB) (menu option 9). Wheel and stick rumble. There
    are two ways to set it up.

  - BepInEx update and setup (menu option 10). Installs or updates a game
    add-on that some Unity games need.

  - Region setup (menu option 11). Sets the country your games start in,
    for example USA or Europe. You are also asked once after new games are
    registered.

  - Required game patches (menu option 13). Puts back certain missing
    game files for certain games.

  - Postgres setup (menu option 12). Sets up the database that some
    Incredible Technologies games need. It ends with a short result
    screen. Press D there for details.

  - Compatibility warnings (automatic). Warns you about known problem
    games before you waste time. No action needed unless flagged.

  Game launchers
  --------------

  - LaunchBox integration (menu option 3). Adds your registered games to
    LaunchBox for you. No import wizard is needed.

  - RetroBat / Batocera support. One setting makes the folder names fit
    RetroBat and Batocera.

  Safety and keeping things tidy
  ------------------------------

  - Preview / dry-run mode. Shows what would change, and changes nothing.
    Good for your first run.

  - Restore from backup (menu option 15). Puts back a saved copy. The
    lists show the newest saved copy first.

  - Unattended mode. Runs the read-only Library Health Check by itself,
    with no questions. It does not run AutoSync or Register only.

  - Per-game overrides. A small settings file lets you give special rules
    to single games.

  - Action summary. At the end of every run you get a list of what still
    needs your attention.

  - Check for Updates (menu option 16). Looks on GitHub for a newer release.
    It checks the download and looks inside the ZIP first. Nothing is
    changed unless you say Y.

  - Safe by design. It backs up first, never deletes your games, and logs
    everything.

  Want the technical details? Read the MORE DETAIL blocks below, in the
  same order as the groups above.


  MORE DETAIL: Getting your games in
  ----------------------------------

  - AutoSync extraction. Copies and extracts game ZIPs from a NAS or local
    source into a staging folder you choose, skipping unchanged games.

    It tracks what has been extracted, so future runs only touch new or
    changed ZIPs.

    A supplementary source (a separate optional library) can be configured.
    It is scanned alongside the main collection in the same pick session.

    The staging folder can be on a network drive. The script measures write
    speed and warns if throughput is too low for reliable extraction or play.

  - Game selection. When extracting, all sources are presented in one
    combined A-Z list.

    Supplementary-library entries are marked [+]. Counts are shown per
    source so you always know the breakdown.

    Choose to extract everything, browse an A-Z paginated list, or search
    by keyword. Games already on disk are filtered from the list
    automatically.

  - Extraction progress. A real-time progress bar shows file count and
    percentage during each game's extraction -- no more blinking cursor.

  - Smart folder matching. Extraction folders use the same naming
    convention as the ZIP files.

    If a game was previously extracted under an older naming convention
    (e.g. with spaces between bracket groups), the script recognizes it and
    does not create a duplicate.

  - Auto-detect TeknoParrot path. On first run, instead of asking for the
    root folder immediately, the script scans common install locations
    (LaunchBox emulators folder, drive roots, Program Files) for
    TeknoParrotUi.exe and suggests the match.

    If multiple installs are found, it lists them numbered so you can pick
    without typing.


  MORE DETAIL: Telling TeknoParrot about your games
  -------------------------------------------------

  - Automatic registration. Scans your extracted games, matches each to the
    correct TeknoParrot profile, and makes it appear and launch in
    TeknoParrotUI.

    It scans all common executable types: .exe, .elf, .iso, .xbe (Sega
    Chihiro/cxbxr games such as Virtua Cop 3 and OutRun 2), .dll (Konami PC
    arcade games such as DanceDanceRevolution 2013, Steel Chronicle, Metal
    Gear Arcade), and more.

    Existing registrations are not overwritten, except a duplicate you
    choose to switch yourself (you are asked first, and a backup is made).

  - Fuzzy name matching. For platforms that share a single executable file
    (most notably NESiCAxLive, where 80+ games all use game.exe), the script
    compares the game folder name to every candidate profile code.

    It auto-registers the best match when the similarity score is high
    enough.

    Games below the confidence threshold are shown with every validated
    candidate. TeknoParrot Manager offers an explicit in-product choice.
    Pressing Enter leaves the case unresolved for TeknoParrotUI instead of
    guessing.

  - Dat file integration (optional). A "dat file" is a community-maintained
    lookup file that maps game files to their correct titles and metadata.

    Think of it as an answer key the script can check against when a game's
    own files don't make its identity obvious.

    During initial setup, the script offers to download the Eggman/RomVault
    dat ZIP directly from GitHub (~145 MB) or accept a path to a local copy.

    The ZIP contains both the collection dat and the supplementary dat. Both
    are read directly from inside the archive with no extraction step.

    The dat's <GameProfile> code is used as the authoritative source for
    three registration scenarios:

      (1) shared-executable games where multiple profiles match the same
          exe name;

      (2) games whose exe name does not appear in any GameProfile at all
          (e.g. pcsx2x6 ELF games, ELF-based Lindbergh titles) -- a second
          pass looks them up in the dat by normalized folder name;

      (3) slightly misnamed folders -- a fuzzy scan of all dat entries finds
          the best match above the auto-register threshold.

    Games registered via the dat are shown as "Registered (dat)". The log
    also says whether the match was exact (dat/exact) or by similarity
    (dat/fuzzy).

    The dat file says which format it uses. This version of TeknoParrot
    Manager knows version 1. If a dat says another version, TeknoParrot
    Manager tells you in plain words, still reads it the same way and
    notes it in the log; some games may then not match. A dat with no
    version is read as before.

    A third registration pass (independent of the dat) Dice-matches
    normalized folder names against normalized GameProfile code names.

    This resolves games whose GameProfile has an empty ExecutableName --
    they never enter the exe-name index and may not appear in the dat
    either.

    Examples: BladeStrangers, LuigisMansion, MaiMaiGreen, PokkenTournament,
    ProjectDiva, SonicDashExtreme, HydroThunder. These appear as
    "Registered (code/fuzzy)".

    The supplementary dat can be indexed to show alternate versions of your
    games (different regions, revisions, bonus content).

    After registration completes, a "Game Info" block shows alternate
    versions and game notes (from the notes text file in the ZIP) for each
    newly registered game.

    The dat path can also be set in TeknoParrot-Manager.overrides.json
    (datFile key); that path is used instead of the one from setup. If an
    Eggman DAT ZIP is set up, the ZIP is used and datFile is ignored.

    Profile list. The script tries to read TeknoParrot's full game list
    online when it starts, to match dat codes that do not exactly match a
    local game setup file. When the online list is not available, it uses
    the setup files in your own TeknoParrot GameProfiles folder instead.

  - Already-registered detection. Before flagging a shared-executable folder
    as needing an explicit registration choice, the script checks whether
    any candidate profile already has a UserProfile XML (i.e. was
    registered via TeknoParrotUI or a previous run).

    If so, it is marked "already set" and removed from ACTION REQUIRED.
    Games set up outside the script no longer reappear on every run.

  - Game folders not recognized list. After scanning your staging folder,
    it lists every game folder whose executables did not match any profile
    in the TeknoParrot GameProfiles folder, so they were not registered.

    These are surfaced in the ACTION REQUIRED section with advice: make
    sure TeknoParrot is up to date and TeknoParrotUI has been opened once,
    then run Register only again.

  - Game repair. Finds broken or empty game paths and re-points them to the
    correct executable in your staging folder.

  - Thumbnail download. After registration, optionally downloads game icons
    from the TeknoParrotUIThumbnails GitHub repository directly into
    TeknoParrot's Icons folder.

    It only fetches icons that are absent; it never overwrites existing
    files.

    It uses one compact progress row, lists the exact games missing from the
    online pack, and explains that a missing icon does not mean the game is
    unsupported.


  MORE DETAIL: Controls
  ---------------------

  - Control propagation. Bind ONE game of each control type once. The
    script can copy those known controls to compatible unbound games in the
    same detected control family, matched so a wheel value can never land on
    a gun.

    Aim-mode settings (relative input, sensitivity, hide-cursor) are also
    carried across.

  - Device survey. Asks which controls you have and prints a tailored plan
    of which game to bind with which device.

  - Controls status file. After every real run, writes a persistent
    TeknoParrot-Manager-controls.txt listing every registered game, its
    control family, whether controls were propagated and from which
    reference game, and how many buttons are still set manually.

    This is a propagation inventory, not proof that controls have been
    verified. The ACTION REQUIRED summary remains authoritative for the
    separate controls-readiness state.

  - Crosshair setup. Deploys custom Player 1 (P1) and Player 2 (P2) cursor
    images to registered lightgun games.

    A built-in, keyboard-accessible preview window shows the 321 included
    designs and your own PNGs.

    Optionally also hides the Windows mouse cursor for all lightgun games by
    setting the cursor-hide field in each UserProfile XML.


  MORE DETAIL: ReShade visual enhancements
  ----------------------------------------

  ReShade is optional. Your games work perfectly without it.

  - What it does. Installs ReShade post-processing into your game folders,
    auto-detecting the correct DLL name from each game's executable.

    ReShade works with 64-bit games. 32-bit games are skipped.

    During ReShade setup, TeknoParrot Manager checks for a newer version
    and offers an automatic official download and update.

  - The first menu. Choose 6 at the main menu. You see:
    S) Set up ReShade visual enhancements, R) Remove verified TeknoParrot
    Manager-managed ReShade files, U) Undo ReShade changes.
    The default is S.

  - The looks. Beginner profile and restore choices are explicit and
    per-game. TeknoParrot Manager offers 17 profiles chosen for arcade play
    (Original plus 16 arcade looks), built from 12 of the 25 approved
    effects and listed best first.

    Each profile has a one-line description of what it does in a game and a
    rough cost (light, medium or heavy; an estimate, not a measurement).

    It also offers catalog-bound favorites and a remembered selection.

    No profile is marked recommended or validated without measured
    evidence. Pinned effect hashes establish catalog integrity, not
    performance validation.

  - Restore is never automatic. When you set up games one at a time, you
    can choose R to restore the previous trusted profile for that game.
    The operator must choose it.

    History is accepted only when the current profile definition, ordered
    approved effect hashes, and intensity variant still match.

    Missing, corrupt, stale, retired, or unsupported history falls back to
    fresh selection.

    A retired profile such as Cartoon or Clean & Sharp is reported as a
    custom/previous profile that is no longer offered. It is never remapped
    or replaced silently. Files it installed keep working, are left
    untouched and stay removable.

    TeknoParrot Manager never copies historical file paths.

  - The preview gallery. An optional non-modal gallery opens before final
    confirmation. Its profile drop-down and the terminal chooser use the
    same group names: CRT Choices, then Main Catalog.

    In the drop-down, group headings are labels rather than choices.
    Keyboard and mouse selection moves to a profile entry. Selecting a
    profile in either place updates the other.

    If you resize the terminal while its choice prompt waits, TeknoParrot
    Manager rebuilds the selection display and keeps the characters you have
    typed.

    Typing is end-of-line only. If a console update cannot be completed
    safely, TeknoParrot Manager prints a short notice and redraws the
    prompt.

    The comparison view and 0-100 slider are independent of profile
    selection, and the slider is aligned to the displayed image.

    No current profile needs HDR, so no HDR group is offered. The HDR
    display check stays in TeknoParrot Manager but no current profile uses
    it.

    To use the preview, choose a profile entry, compare Before/After/Split
    or move the slider, then return to the terminal. Type U and confirm to
    continue.

    B returns without changing game/profile files; R reopens the preview.
    Browsing the gallery does not change game or profile files.

  - License evidence. An effect is offered only while its recorded license
    evidence is complete and current (pinned files matched upstream, in-file
    notices or repository license copies checked, includes resolved).

    All 25 effects are held to the same standard. An effect whose evidence
    is missing, stale or incomplete is withheld, with the specific reason in
    the review inventory.

  The 17 looks, as the chooser lists them:

      [1] Original
          No visual processing.

      CRT Choices

      [2] Curved Arcade Monitor [CRT-Geom]
          Makes the game look like it is on a curved arcade cabinet monitor:
          bent screen edges, rounded corners, scanlines and a fine dot
          pattern. Cost: medium.

      [3] Classic Arcade CRT [CRT Lottes]
          Makes the game look like a classic arcade CRT screen: visible
          scanlines and a soft shadow-mask pattern. Cost: heavy.

      [4] Sharp Aperture Grille [CRT-Aperture]
          A sharp, bright Trinitron-style picture: fine red, green and blue
          stripes, clear scanlines and a light glow; the screen stays flat.
          Cost: medium.

      [5] Balanced Flat CRT [CRT-Easymode]
          A balanced flat CRT look: clear scanlines and a gentle color mask
          with sharp edges and no screen curve. Cost: medium.

      [6] Sharp Phosphor CRT [CRT-Hyllian]
          A sharp, vivid CRT look: crisp pixels, scanlines that fade between
          the lines and a fine phosphor dot pattern. Cost: medium.

      [7] Arcade CRT Glow [CRT Lottes + ArcaneBloom]
          The classic arcade CRT look plus a soft glow around bright areas,
          like a bright cabinet screen. Cost: heavy.

      [8] Detailed Arcade CRT [CRT-Royale]
          The most detailed CRT look, with a fine phosphor mask and
          scanlines; it needs a strong graphics card. Cost: heavy.

      [9] Fast CRT [CRT-ZFast]
          Scanlines and a light mask for a CRT look that costs very little
          speed, so it also runs well on slower PCs. Cost: light.

      [10] Lightweight CRT [CRT-Pi]
          Simple scanlines for a retro arcade look that also runs well on
          slower PCs. Cost: light.

      [11] Scanline Glow [CRT-Pi + ArcaneBloom]
          Simple scanlines plus a soft glow around bright areas, at a lower
          cost than the classic CRT look. Cost: medium.

      [12] Bright Scanlines [Levels + CRT-Pi]
          Simple scanlines with deeper blacks and brighter whites, so the
          picture stays bright behind the scanlines. Cost: light.

      Main Catalog

      [13] Arcade Glow [ArcaneBloom]
          A soft glow around bright lights and effects, like a bright arcade
          cabinet screen. Cost: medium.

      [14] Crisp 3D [SMAA + Curves + Levels]
          Smooths jagged edges in 3D games and adds stronger contrast with
          deeper blacks. Cost: medium.

      [15] Crisp 3D Glow [SMAA + Levels + ArcaneBloom]
          Smooths jagged edges in 3D games, deepens blacks and adds a soft
          glow around bright areas. Cost: medium.

      [16] Balanced Contrast [Curves]
          Stronger contrast in the midtones, so a flat-looking game gets
          more depth. Cost: medium.

      [17] Black/White Point Adjustment [Levels]
          Deeper blacks and brighter whites for games that look washed out
          or gray. Cost: light.

  The choice line under the list reads:

    Choose: [1-17] Select profile  [U] Use selected profile
            [N] Skip ReShade -- no changes  [R] Reopen preview  [B] Back
            [D] Details

  - The terminal always works. The terminal remains usable if the gallery
    is behind another window, closed, unavailable, or fails.

    U is the only path toward deployment. B cancels without changes and D
    returns after showing details.

  - What the gallery is. The gallery is a safe approximation based on the
    bundled TeknoParrot Manager-owned landscape reference image from
    PreviewAssets\ReShadePreviews\TPM-preview-landscape.png. It does not run
    the game or execute ReShade shaders.

    The selected profile's description and approved shader
    filenames/techniques appear in the preview.

    Before is the untouched baseline, After is a TeknoParrot Manager
    approximation of the selected profile, Split places baseline left and
    the approximation right, and the slider moves that boundary from all
    processed to all baseline. Actual in-game results may vary.

    Selecting a profile does not write files. Deployment remains behind U
    and the existing explicit confirmation. The preview closes
    automatically when the terminal chooser returns.

  - Which games. After you confirm the look, you choose the games:
    A) All registered games, or L) Browse and select specific games.

    For ONE game, choose L, type that game's number, then D (done).

  - Safe file handling. The DLL, generated preset, and approved effect
    files are staged and promoted together.

    Before replacing a destination, TeknoParrot Manager requires a matching
    TeknoParrot Manager-managed ownership entry for that game. Existing
    unknown or user-owned files cause a collision and remain untouched.

    Earlier TeknoParrot Manager-managed files are retained when changing
    profiles rather than being silently deleted.

  - Checks and the result screen. Before it installs anything, TeknoParrot
    Manager tells you how many of the games you picked it can change now
    and that it leaves the others alone. Press D to see why for each game.
    A game it could not check is not called unsafe or damaged.

    The final result states changed and unchanged games. For a game that
    could not be checked, it gives the direct details and tells you to
    repair or review the listed issue before rerunning ReShade setup with
    Select.

    Adopted installations are counted separately from ordinary installs.
    Onboarding pauses for review before dgVoodoo2.

  - Games that already have ReShade. Protected existing files stay
    unchanged unless you explicitly choose to replace them and confirm.

    When some games were left alone, the result screen offers these keys:
    A (replace them with TeknoParrot Manager's ReShade; you choose the look
    again, and a copy of the old files is saved so you can undo it), S
    (choose games one by one), M (show the games that could not be found),
    B (leave them as they are) and D (details).

    D shows the full technical information and asks again. The same
    information is also kept in the log. When nothing needs a choice, the
    screen ends with "Press D for details, or Enter to return to the menu".

  - TeknoParrot's own CRT effect. Native TeknoParrot CRT, SSAA, shader,
    scanline, and post-process settings are read but preserved. Enabled
    settings trigger a warning about possible display-effect stacking.

    If a game already uses TeknoParrot's own CRT look, TeknoParrot Manager
    asks what to do before it installs ReShade. K keeps TeknoParrot's CRT
    look (the default). T turns it off for the games that get ReShade now.
    D shows details.

    Before T changes anything, a saved copy of your game profiles is made.
    Removing ReShade later does not turn TeknoParrot's own CRT look back
    on. To put it back, use Restore backup, or ReShade > Undo ReShade
    changes when an undo copy exists.

  - Changing your look. Change the look for all games: choose 6, then S,
    pick the new look, press U, then Y. Choose A for all registered games,
    then Y.

    Change the look for one game: choose 6, then S, pick the look, press U,
    then Y. Choose L, pick that game's number, then D.

    Games last set up by TeknoParrot Manager with a different look are
    listed, with the choice to change them (A) or keep their current look
    (K).

  - Undoing your look. Choose 6, then U. The list shows the games
    TeknoParrot Manager changed, newest first.

    Undo one game: type its number, then type YES when asked.

    Undo all games: choose A, then type ALL when asked.

    A game that changed since is left as it is.

  - Removing ReShade. Choose 6, then R. Pick the games, then type REMOVE.
    Only verified TeknoParrot Manager-managed files are removed. Protected
    bundled, preinstalled, changed, and ambiguous files are preserved.

  - Display notes. Multi-monitor suitability is read-only and advisory,
    uses caller-supplied evidence, treats duplicate target IDs as ambiguous,
    and does not separately label EXTENDED arrangements or acquire Windows
    display topology itself.


  MORE DETAIL: Older games and game fixes
  ---------------------------------------

  - dgVoodoo2 legacy compatibility. Fixes older arcade games that crash or
    show black screens due to DirectX 8, DirectDraw, or Glide API usage.

    It auto-detects which registered games use those APIs and deploys the
    correct dgVoodoo2 DLLs. Optional -- only needed for games that do not
    run correctly.

  - GPU compatibility fixes. Many TeknoParrot games include optional
    per-vendor fix settings (AMD, NVIDIA, Intel) in their profiles. This
    mode auto-detects your GPU and applies the correct fix to every
    registered game that has one.

    TeknoParrot's GameProfiles folder is scanned at runtime so newly added
    games are always covered. Safe to re-run any time you change or update
    your GPU.

    If a saved game path is missing or unavailable, the result offers a
    direct handoff to mode 14, Library Health Check.

    Available as menu option 8 or as an optional step at the end of a
    normal run.

  - Infinity Blade FX 1.02 has two independent missing-file repairs for
    Binaries/Win32/matrix32.dll and Binaries/Win32/dinput8.dll.

    Both require matrix32.TEKNOPARROT.dll and TPFIX.ini in that directory
    to be present. Presence does not validate their bytes or configuration.

    TeknoParrot Manager does not rename the original library, edit
    TPFIX.ini, or choose the first-launch TeknoParrot.dll path.
    Compatibility and gameplay remain separate checks.

  - Required game patches. Option 13 contains 120 exact-build recipes
    across 71 exact ProfileId/build/executable identities (54 game
    profiles).

    The list started with 58 earlier recipes and has grown since. Later
    additions include absent-only Main restores for MaiMai GreeN
    `freeglut.dll` and `libcurl.dll`, Rabbids Hollywood
    `RabbidsHollywood_Operator.exe`, and Cross Raid 1.05 Ver A
    `rom/shader.farc`.

    The first 58 recipes contain three Taisen Hot Gimmick 5 (2.04)
    single-file restores; three user-selected plugin restores for Mars
    Sortie, the separate Rabbids Hollywood operator plugin, and Super Bikes
    3 1.91 x64; five native recipes for Cross Raid 1.05, VF5R 1.001, and
    Sonic Dash Extreme;

    and 34 Main-component restorations: 14 Hummer, 14 Hummer Extreme, two
    Primeval Hunt, two SB3 FMOD, and two Infinity Blade FX 1.02.

    108 `CreateFile` operations create only absent targets; twelve
    `ReplaceFile` operations require an exact before-state. Exact-after
    files are skipped; unknown bytes are refused.

    Full guide coverage, setup readiness, controls, launch, and gameplay are
    not claimed.

    Two further TMNT 1.59 Main recipes independently restore only absent
    OrenVid.dll and PK-UnityPlugin.dll under TMNT_Data/Plugins/x86_64/.
    They do not install BepInEx or change configuration. Setup, controls,
    launch and gameplay still require separate verification.

    The source follow-up also adds four independent KOF Maximum Impact
    Regulation A Main restorations (d3d8.dll, d3d9.dll, ddraw.dll and
    wined3d.dll) and the exact MKDX USA 1.06 Main D3D11Ref.dll restoration.

    Each creates only an absent target and preserves unknown existing bytes.
    These repairs do not prove graphics compatibility, setup or gameplay.

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


  MORE DETAIL: Force feedback, BepInEx and Postgres
  -------------------------------------------------

  - Force feedback (FFB). Two independent ways to get wheel/stick rumble
    and force feedback: TeknoParrot's own built-in FFB Blaster (needs a
    paid TeknoParrot membership) and a free third-party plugin (no
    subscription needed, fetched live from GitHub each run).

    Both can be set up at once since they cover different games. If a game
    is covered by both, you are asked once which to use for all such games.

    Missing or unavailable saved paths are reported separately and offer a
    direct handoff to mode 14, Library Health Check. Unsupported/no-match
    games remain distinct from true deployment errors.

    See FORCE FEEDBACK (FFB) SETUP below for full details. Available as
    menu option 9.

  - BepInEx update and setup. BepInEx is a third-party Unity
    plugin/modding framework some games need (a live-fetched example list
    is shown in the menu).

    Mode 10 offers a user-approved install or update for selected games using
    the stable x64 or x86 package matching each validated executable.

    The prompt is [Y] Install/update, [B] Back, [N] Cancel. Unsafe roots
    and failed validation make no changes.

    Missing or unavailable saved paths offer a conditional H handoff to
    mode 14, Library Health Check. Ordinary deployment failures keep their
    normal retry, Details, and support guidance.

    See BEPINEX SETUP below. Available as menu option 10.

  - Postgres setup. Installs and configures the local PostgreSQL 8.3
    database that some Incredible Technologies games need (every Golden
    Tee Live and PGA Tour game, Power Putt Live, Silver Strike Bowling
    Live, Target Toss Pro, Orange County Choppers Pinball).

    Newer TeknoParrot profiles of these games have a Storage box. Internal
    is the new default: no database install is needed, and you start the
    game once so it makes its own database. Existing PostgreSQL is for
    keeping an existing server and its saved progress. Postgres setup and
    Library health check skip Internal games and never call their database
    missing. TeknoParrot Manager never switches a game from one choice to
    the other, and never touches saved progress without a backup first.
    Older profiles with no Storage box work as before.

    It detects which of your registered games need it automatically. It
    never reinstalls an existing PostgreSQL install. It does not recreate
    or restore over a database that already exists unless you choose a
    restore (mode 15) or the [I] rebuild and then type YES. The one other
    case is a database that TeknoParrot Manager's own note says an earlier
    setup was still building when it stopped: that unfinished copy is
    removed and built again.

    TeknoParrot Manager asks Windows for permission itself when setup needs
    it and continues the same operation.

    Setup ends with a short result screen. It says how many games were set
    up, how many databases were created and how many were already set up.

    Press D there for the details. The full information is also
    kept in the log.

    Setup makes each game database from the game's own backup file and
    tests it with the game's own settings before it says the game is ready.
    For a game set to Existing PostgreSQL you do not need any extra step in
    TeknoParrot or on the first start. A game set to Internal storage is
    skipped: start it once so it makes its own database. A game with no
    starting database file (pg_backup) and TeknoParrot's "Automatically
    create Database" option (Golden Tee Live 2018 and newer, PGA Tour)
    gets its profile set up and is called "Profile ready": TeknoParrot
    makes the database the first time the game starts. Any other game
    with no starting database file is left out and named. The other games
    are still set up.

    See POSTGRES SETUP below. Available as menu option 12.


  MORE DETAIL: Game launchers
  ---------------------------

  - LaunchBox integration. Adds your registered games directly into
    LaunchBox's own library -- no import wizard needed.

    It checks LaunchBox is closed, backs up the files it is about to
    change, and never duplicates a game already there.

    Choose to mix TeknoParrot games into your existing Arcade platform, a
    dedicated "TeknoParrot" platform, a platform with a name you choose, or
    both Arcade and a dedicated platform at once. You are asked each time;
    the choice is not saved.

    The end-of-run menu is explicit: P previews without changing
    LaunchBox, A adds missing games, G fills in details and playlists, V
    groups regions and versions, S keeps LaunchBox in step with
    TeknoParrot, L links games for art and details, F creates a manual
    import/reference file, and B skips the optional LaunchBox step.

    A manual-import reference file remains available if you prefer not to
    let the script touch LaunchBox's files directly.

  - RetroBat / Batocera support. A single setting switches extraction to
    use GameName.teknoparrot folder naming as required by RetroBat and
    Batocera.

    The script also recognizes .parrot and .game suffixes for existing
    folders. Registration, fuzzy matching, and all other features work
    identically.


  MORE DETAIL: Safety, updates and automation
  -------------------------------------------

  - Preview / dry-run mode. Before AutoSync or Register only does anything,
    you can choose to preview what it would do:

      -- which games would extract,
      -- which would register and to which profile,
      -- which broken paths would be repaired,
      -- which controls would propagate.

    A preview does not apply game/profile changes. Scans and logging still
    occur.

    No profile backup is created. Follow-up offers (LaunchBox export,
    thumbnail download, GPU fix) are skipped since there is nothing yet to
    act on.

    Preview is useful the first time you point the script at a new library,
    or after changing settings, to build confidence before committing.

    Choose P (Preview, default -- show what would change; no game or
    profile changes), R (Run now -- back up UserProfiles first, then make
    the changes), or B (Back).

    Or pass -DryRun on the command line to always preview. -Unattended is
    not a way to preview a scheduled AutoSync: it runs only the Health Check.

    After a preview finishes ("PREVIEW -- no games or profiles were
    changed."), no proposed game/profile changes were applied.

    TeknoParrot Manager asks "Do you want to make these changes for real
    now?" and offers [D] Details next to Y and N. Answer Y (scan again,
    then apply the changes) to re-run the same mode for real, with the
    same game selection the preview used. This is a fresh scan, not a
    replay of the preview.

    Answer N to return to the main menu without changing anything.

  - Restore from backup. A menu option lists all timestamped backups and
    restores the one you pick in one step, without touching File Explorer.

    Restore backup is main menu option 15. The lists are shown newest
    first.

  - Unattended mode. A -Unattended switch skips all Y/N prompts and uses
    saved settings.

    In this release it runs only the read-only Library Health Check. It
    does not extract games, register them, copy controls or download
    thumbnails, so it cannot run AutoSync overnight.

    It needs the saved setting "UnattendedMode": "HealthCheck". See the
    UNATTENDED / SCHEDULED MODE section.

    At start-up it prints "TeknoParrot Manager found your saved settings."
    and "[Unattended] Using saved settings." It asks no question.

  - Per-game overrides. A JSON file lets you exclude games from sync or
    propagation, whitelist specific games for extraction, pin a game to a
    specific reference game for control copying, or override the
    auto-detected control family for mis-classified titles.

  - Action summary. At the end of every run the script prints a clear list
    of everything that needs your attention in TeknoParrotUI.

    It includes which ambiguous games received an explicit candidate
    choice, which paths to fix, and which control types still need to be
    set up.

  - Check for Updates. Manually checks the latest GitHub release against
    the version you're running. Nothing is downloaded or changed without
    your explicit Y/N confirmation.

    An approved update may temporarily clear only the target read-only
    attribute and restores it after the attempt.

    See CHECK FOR UPDATES below. Available as menu option 16.

  - Safe by design. AutoSync backs up UserProfiles before extraction
    (preview skips the backup), never deletes your games, guards the staging
    folder against the emulator and source folders, checks free space, and
    logs everything.


-------------------------------------------------------------------------------
  GLOSSARY
-------------------------------------------------------------------------------

  These are the words used in this file, in the order you will probably
  need them. You do not have to learn them now. Come back when you meet one.

  GameProfile           The ready-made setup file that TeknoParrot comes
                        with for one game, for example
                        StreetFighterIII3rdStrike.xml. It lives in
                        TeknoParrot's GameProfiles\ folder. It does not
                        know where YOUR copy of the game is.

  UserProfile           Your own copy of a GameProfile. It is made when a
                        game is registered (added to TeknoParrot). It
                        lives in TeknoParrot's saved game settings folder
                        (UserProfiles\), one file per game.

  Profile Code          The file name without .xml. A GameProfile and its
                        UserProfile share it, for example
                        "StreetFighterIII3rdStrike". The script and its
                        logs use it as the name of one game.

  GamePath              The setting inside a UserProfile that points to the
                        game's program file (the .exe) on your disk.
                        Registration is mostly finding the right .exe and
                        writing it here. GamePath2 is the same idea for a
                        second program (see HasTwoExecutables below).

  Registration          Matching a game folder you extracted to the right
                        GameProfile, then making or updating its
                        UserProfile with the right GamePath. See
                        REGISTRATION below.

  AutoSync              The "extract + register" mode of TeknoParrot
                        Manager (mode 1). It takes ZIP files from your
                        network drive (NAS) or a local folder, unpacks
                        them into a staging folder, then registers them.
                        See MODES and GAME SELECTION below.

  Staging folder        The local folder AutoSync unpacks ZIP files into
                        before registering them. See THE STAGING FOLDER
                        below.

  Fuzzy matching        How the script works out which GameProfile a game
                        folder belongs to, when the program name fits
                        several games. It compares the folder name with
                        each candidate's profile code. See HOW FUZZY
                        MATCHING WORKS below.

  Dat file              An optional list kept by the community (from the
                        Eggmansworld TeknoParrot collection). It links
                        exact ZIP names to the right profile code. It is
                        used instead of fuzzy matching for confusing
                        games, because it is exact, not a best guess.

  Control propagation   A shortcut so you do not set up every game's
                        controls by hand. Set up ONE game of each type in
                        TeknoParrot's own window. The script copies those
                        controls to every other game of that type that
                        has none yet. See CONTROL PROPAGATION below.

  Archetype / reference game
                        A game that already has enough buttons set up (by
                        you, in TeknoParrot's own window). Its settings
                        are copied to other games of the same family. Its
                        button settings are kept.

  Family                Which kind of controls a game uses: button,
                        driving, lightgun, trackball or analog. It is
                        found automatically for each game.

  ACTION REQUIRED       The summary at the end of a run. It lists what you
                        still need to do in TeknoParrotUI itself. See
                        ACTION REQUIRED SUMMARY below.

  Dry-run / preview mode
                        Shows exactly what WOULD happen, without changing
                        any games or game setup files. It still writes to
                        the log. It is offered automatically before a
                        real run in modes 1 and 2.

  Overrides (TeknoParrot-Manager.overrides.json)
                        An optional file next to this script. It lets you
                        change the automatic choices for single games. See
                        PER-GAME OVERRIDES below.

  HasTwoExecutables     A property some GameProfiles have (for example the
                        Initial D: Arcade Stage games). It means the game
                        needs a second program started next to the main
                        one. This is handled automatically.


  MORE DETAIL: Glossary
  ---------------------

  Archetype / reference game. An explicit canonical reference can correct
  InputAPI. The button bindings of the archetype are preserved.

  Family. It can be overridden per game in
  TeknoParrot-Manager.overrides.json if this script guesses wrong.

  Overrides (TeknoParrot-Manager.overrides.json). You can skip syncing one
  game, pin a game to a specific archetype, override its detected family,
  and make a few other per-game exceptions.

  HasTwoExecutables. It is handled automatically via GamePath2 above, which
  holds the second companion executable.


-------------------------------------------------------------------------------
  HOW IT WORKS
-------------------------------------------------------------------------------

  TeknoParrot keeps two folders of game setup files in its main folder:

    GameProfiles   Templates that come with TeknoParrot, one per supported
                   game. Each names the program it expects and carries
                   that game's settings and controls.

    UserProfiles   Your games. A game shows up and starts once its template
                   is copied here with the path to your program filled in.

  TeknoParrot Manager does this copy-and-fill step for you:

    1. It scans your games.
    2. It matches each game program to the right template.
    3. It copies the template to UserProfiles.
    4. It writes the path to your game into the copy.

  TeknoParrot picks the games up the next time you open it.


-------------------------------------------------------------------------------
  REQUIREMENTS
-------------------------------------------------------------------------------

  You need all of these before you start:

  - A Windows PC with PowerShell 5.1 available for TeknoParrot Manager.

  - TeknoParrot installed in its own folder, such as C:\TeknoParrot. Do not
    use the installer's default C:\Windows\system32. The folder must hold
    TeknoParrotUi.exe and GameProfiles.

  - TeknoParrot up to date. Open TeknoParrotUi.exe yourself once before you
    use TeknoParrot Manager.

  - Your games extracted into one subfolder per game, or as ZIP files for
    AutoSync to extract.

  TeknoParrot Manager never updates TeknoParrot, never opens it, and never
  checks whether its game setup files are fresh.

  Verified install and first-run steps:
  TeknoParrot-Manager-QuickStart.txt, sections 2 and 3.


-------------------------------------------------------------------------------
  RUNNING THE SCRIPT
-------------------------------------------------------------------------------

  Step 1.  Double-click TeknoParrot-Manager.bat.
           This is the normal way to start TeknoParrot Manager. You do
           not have to type any PowerShell command.
           You will see: a window opens and TeknoParrot Manager starts.
           Next: go to Step 2.

  Step 2.  Look at the first screen.

           First run, with no saved settings yet. You will see:

               Welcome to TeknoParrot Manager

           and then "Press Enter to continue".
           Next: press Enter and answer the first-time questions.

           Later runs. You will see:

               TeknoParrot Manager found your saved settings.

           Next: go to Step 3.

  Step 3.  Answer the question about your saved settings. You will see:

               Use these settings? (Y/N, D = show them):

           Type one letter and press Enter:

               Y   Use them.
                   You will see "Using your saved settings."
                   TeknoParrot Manager does not ask for your folders
                   again. Next: go to Step 4.

               N   Do not use them.
                   TeknoParrot Manager asks the first-time questions
                   again. Nothing is deleted.

               D   Show the saved settings, one per line.
                   Then the same question is asked again.
                   You can press D as often as you like.

           Any other answer (even just Enter) shows "Please choose Y or
           N." and the question is asked again.

  Step 4.  Choose a mode from the main menu. You will see the prompt
           "Enter 1-18:". Type the number of a mode and press Enter.
           See MODES below. Next: follow the screens for that mode.

  Any time you are asked to type a file or folder path, you can type B
  instead. A normal Windows window opens, and you pick the file or folder
  with the mouse. Typing the path still works exactly as before.


  WORKFLOW STATUS
  ---------------
  During jobs with many steps, TeknoParrot Manager shows a status area in
  plain words. It tells you what it is doing now, what just finished, what
  comes next, and anything it needs from you.

  A failure stays on screen until you acknowledge it. If the status area
  offers Retry and Stop choices, it names them and says what to do.


  MORE DETAIL: Running the script
  -------------------------------

  Advanced route. Instead of double-clicking, open PowerShell and go to the
  folder that holds TeknoParrot-Manager.ps1 (the folder you unpacked the
  release ZIP into, next to TeknoParrot-Manager.bat):

      cd "C:\path\to\TeknoParrot Manager"
      .\TeknoParrot-Manager.ps1

  If Windows blocks that advanced route, allow it for this session only:

      powershell -ExecutionPolicy Bypass -File .\TeknoParrot-Manager.ps1

  Saved settings. The settings list is not printed at start-up. D prints
  it, one row per saved setting (a name, then its value). A row appears
  only if that setting is saved. N does not delete the old settings. The
  new answers are saved over them later.

  Workflow status. It uses real step counts and keeps failures visible
  until acknowledged. It adapts safely when the PowerShell window is
  resized. Redirected, unattended, and certification runs keep structured
  events without cursor-control output.

  When recovery metadata is available, the status action line names the
  concrete Retry and Stop choices and their remediation instead of showing
  acknowledgement alone.


-------------------------------------------------------------------------------
  AUTO-DETECT TEKNOPARROT PATH
-------------------------------------------------------------------------------

  On the first run, TeknoParrot Manager looks for TeknoParrot for you. It
  does the same on any run where the TeknoParrot folder is not saved. This
  saves you from typing the path.

  It looks for TeknoParrotUi.exe in these common places:

    - Your LaunchBox Emulators folder under USERPROFILE
    - Drive roots: C:\TeknoParrot, D:\TeknoParrot, etc.
    - Drive roots with sub-paths: \Games\TeknoParrot, \Emulators\TeknoParrot
    - Program Files and Program Files (x86) on every mounted drive

  If it finds exactly one install, you will see:

      Auto-detected TeknoParrot at: C:\Users\...\LaunchBox\Emulators\TeknoParrot
      Use this path? (Y/N)

  Next: type Y if the path is right, or N if it is not.

  If it finds several installs, they are listed with numbers. You will see
  "Found TeknoParrot in multiple locations:". Next: pick one by number.

  If it finds nothing, you are asked to type the path. You will see "Type
  the path of your TeknoParrot folder, the one with TeknoParrotUi.exe in
  it, or Q to quit (or type B to browse)". Next: type the folder path, type
  B to browse for it, or type Q to quit. Nothing is changed if you quit.

  If you close the browse window without choosing a folder, you see "No
  folder was chosen. Type the path again, or type B to browse again." and
  the question comes back. If the folder is wrong, you see "That folder
  does not exist. Check the spelling, or type B to browse." or
  "TeknoParrotUi.exe is not in that folder. Pick the folder that has
  TeknoParrotUi.exe in it." It then asks again.


-------------------------------------------------------------------------------
  MODES
-------------------------------------------------------------------------------

  The main menu comes back after every mode. When a mode finishes, you
  return to the menu to choose another mode or to exit.

  RESULT SCREENS AND DETAILS
  --------------------------

  Result screens are short on purpose. They say what happened and what to
  do next.

  Many result screens offer Details. You will see a line such as
  "[D] Details" or "Press D for details". Type D and press Enter to see
  the full technical information.

  Details are not needed to use the program. The same information is also
  kept in the log file.

  LIBRARY MANAGEMENT
  ------------------

  1) AutoSync
       For games stored as ZIP files (for example on a network drive).
       You provide:  a ZIP source folder and a local staging folder.

       The script:   shows a game selection menu, unpacks the games you
                     choose into the staging folder, then registers them.
                     A game whose ZIP did not change is left alone, so
                     the saves and settings in its folder stay as they are.

  2) Register only
       For games you have already extracted.
       You provide:  the folder that contains your extracted games.
       The script:   scans it and registers everything it recognizes.

  3) LaunchBox integration
       Adds your registered games to LaunchBox, fills in details and
       playlists, links art, and keeps LaunchBox in step. It opens the
       LaunchBox choices (P, A, G, V, S, L, C, F, B) any time, without
       registering or extracting anything first. If you have no LaunchBox
       yet, it tells you so and how to continue.

       See LAUNCHBOX below.

  4) Propagate Controls
       Copies your current TeknoParrot controls from your reference games
       to other games of the same type. It also sets up games with your
       controller layout, checks which games have all their controls, and
       learns your arcade buttons (choices 1 to 5 on that screen).

       This step never registers or extracts games. It is the same step
       offered at the end of AutoSync and Register. You can run it any time,
       without going through extraction or registration first.

       See CONTROL PROPAGATION below.

  GAME ENHANCEMENTS (optional -- not every game needs them)
  ---------------------------------------------------------

  5) Crosshair setup
       Puts custom crosshair pictures (Player 1 (P1) and Player 2 (P2)
       cursor images) into your registered lightgun games.

       It opens TeknoParrot Manager's own preview window. You can browse
       321 included designs and choose by clicking or using the keyboard.

       It can also hide the Windows cursor for all lightgun games.
       It returns to the menu when done.

  6) ReShade setup
       Installs ReShade into your game folders. ReShade adds visual
       filters on top of a game, such as a sharper image, CRT-style
       scanlines and screen borders.

       ReShade works with 64-bit games. 32-bit games are skipped. You will
       see three choices: S) Set up ReShade visual
       enhancements, R) Remove verified TeknoParrot Manager-managed
       ReShade files, and U) Undo ReShade changes. Plain Enter picks S.

       See RESHADE VISUAL ENHANCEMENTS below. It returns to the menu
       when done.

       What you see when ReShade setup finishes. The result screen says
       "Done:" with the look and the number of games. It also says "To
       turn the effect on or off, start a game and press the Home key."
       If some games were left alone, you may press A, S, B or D:

         A   Replace the old ReShade files of those games with
             TeknoParrot Manager's ReShade. You choose the look again. A
             copy of the old files is saved, so you can undo it.

         S   Choose games one by one.
         B   Leave them as they are.
         D   Show the full technical details, then ask again.

       Some result screens also offer M (show the games that could not be
       found). When no choice is needed, the screen ends with "Press D for
       details, or Enter to return to the menu".

       TeknoParrot's own CRT look. Some games already use it. With a
       ReShade CRT look on top, the picture can look doubled. When this
       applies, you will see this question:

         K   Keep TeknoParrot's CRT look (this is the default)
         T   Turn it off for this game (or for several games)
         D   Details

       Next: type K, T or D and press Enter. T turns the effect off only in
       games that get ReShade now. A saved copy of your game profiles is
       made first. To put it back, use ReShade > Undo ReShade changes, or
       use Restore backup (mode 15).

       Changing the look for ALL games:

         1. At the main menu, type 6.
         2. Type S and choose the new look. Then type U to use it.
         3. Type Y at "Use the selected ReShade profile?".
         4. Choose A) All registered games.
         5. Type Y at the question "Apply ... to ... games?".

       Games that TeknoParrot Manager set up earlier with a different look
       are listed. [A] changes them to the new look. [K] keeps their
       current look.

       Changing the look for ONE game:

         1. At the main menu, type 6.
         2. Type S and choose a look. Then type U to use it.
         3. Type Y at "Use the selected ReShade profile?".
         4. Choose L) Browse and select specific games.
         5. Type that game's number, then type D (done).

       Undoing your ReShade look:

         1. At the main menu, type 6, then type U.
         2. To undo ONE game, type its number. Then type YES.
         3. To undo ALL games, type A. Then type ALL.

  7) dgVoodoo2 setup
       Fixes some old games that crash or show a black screen. It is for
       games that use DirectX 8, DirectDraw, or the Glide API. It finds
       by itself which registered games need it.

       See DGVOODOO2 LEGACY COMPATIBILITY below. It returns to the menu
       when done.

  8) GPU fix setup
       Finds your graphics card maker (AMD, NVIDIA or Intel). Then it
       applies the matching fix to every registered game that has one.

       TeknoParrot's list of games is read every time, so nothing needs
       updating when new games are added. It returns to the menu when done.

  9) Force feedback (FFB) setup
       Sets up wheel and stick rumble and force feedback for supported
       games. It covers two separate ways of doing it.

       See FORCE FEEDBACK (FFB) SETUP below. It returns to the menu when
       done.

  10) BepInEx setup
       BepInEx is a modding framework that some games use for extra
       features and fixes. You approve an install or an update for the
       games you choose. It uses the stable package that matches each
       game's program (32-bit or 64-bit).

       The prompt is [Y] Install/update, [B] Back, [N] Cancel. Unsafe
       folders and failed checks make no changes.

       See BEPINEX SETUP.

  11) Region setup
       Sets the country your games start in, for example USA or Europe.
       You pick a country (or Back to automatic), see the games that can
       take it, pick all or some of them, and confirm with Y or N. A
       restore point is saved first. Type D on the result screen for the
       game-by-game details.

       See REGION SETUP below. It returns to the menu when done.

  MORE DETAIL: Game enhancements (modes 5-11)
  -------------------------------------------

  Mode 6, ReShade. It installs ReShade post-processing. ReShade works with
  64-bit games. 32-bit games are skipped. Every ReShade.ini it writes turns
  off the welcome window, the counters and the on-screen messages. A short
  ReShade version banner may still show at game start.

  Mode 6 undo and per-game choices. After a change, the result screen says
  "Next: You can undo this in ReShade > Undo ReShade changes." A game that
  changed after TeknoParrot Manager's own change is left as it is.

  Mode 6, turning off TeknoParrot's own CRT look. This question is only
  asked in an interactive run. An unattended run always keeps TeknoParrot's
  setting. Removing ReShade later does not turn TeknoParrot's own CRT look
  back on.

  Mode 7, dgVoodoo2. It deploys dgVoodoo2 compatibility DLLs. It
  auto-detects which registered games need it.

  Mode 8, GPU fix. It detects your GPU vendor (AMD/NVIDIA/Intel) via WMI
  and applies the correct fix flag to every registered game that has one.
  It scans TeknoParrot's GameProfiles at runtime -- no update is needed
  when new games are added.

  The GPU fix offered at the end of first-time setup ("Apply now?") shows
  the same result as mode 8: how many games you selected, changed, skipped
  and failed. A game on a drive that is not connected is called skipped,
  not failed. The drive letter is named, and the result points to Library
  health check (menu 14) to repair the game paths.

  Mode 9, FFB. The two independent mechanisms are described under FORCE
  FEEDBACK (FFB) SETUP below.

  Mode 10, BepInEx. The install or update is user-approved. It uses the
  stable package matching each executable's architecture. It never removes
  an existing installation. Unsafe roots and failed validation make no
  changes.

  Mode 11, Region setup. You pick a country (for example USA or Europe).
  It lists the games whose own settings offer that country, with the
  country each one has now. You choose all of them or only some, then
  confirm how many will change. A backup is saved first. Games that do
  not offer the country are left as they are. You can also choose Back to
  Auto. After registration you are asked once about the new games; that
  question never replaces a country you chose before.

  GAME REQUIREMENTS (ONLY FOR SOME GAMES)
  ---------------------------------------

  12) Postgres setup
       Installs and sets up the local PostgreSQL 8.3 database that some
       Incredible Technologies games need (every Golden Tee Live and PGA
       Tour game, Power Putt Live, Silver Strike Bowling Live, Target Toss
       Pro, Orange County Choppers Pinball).

       It finds by itself which of your registered games need it.

       Games set to Internal storage (the new default in newer profiles)
       need no PostgreSQL and are skipped.

       If PostgreSQL is already installed, it is never reinstalled or
       changed. If a game's database already exists, setup leaves it as it
       is. Only two choices that you confirm yourself replace database
       content: restoring a saved backup (mode 15) and Reinitialize ([I]
       on the backup-failure screen).

       When Windows permission is needed, TeknoParrot Manager first waits
       for you to press Enter, so you can read what it will ask for. Then
       it asks Windows itself and carries on the same job after you
       approve. You do not need to close TeknoParrot Manager or choose
       mode 12 again.

       When it finishes, you see a short result screen. For example:

         PostgreSQL setup finished.
         Games set up: 3. Databases created: 1. Already set up: 2.

       Then you see one line for each game or group of games, and:

         Next: open TeknoParrot and start any game. Every game database was
         checked and is ready.

       Next: type D and press Enter for details, or just press
       Enter to go back. The prompt reads "Press Enter to return to menu,
       or D for details". You will see "[D] Show
       details" above it.

       Every game database is tested before setup says it is ready:
       TeknoParrot Manager connects to it with the settings saved in the
       game's own profile and counts its tables. A game with no starting
       database file (pg_backup) is "Profile ready" when TeknoParrot
       creates its database itself; otherwise setup leaves that game out,
       sets up all the other games, and names the game as not ready.

       See POSTGRES SETUP below for full details.

  MORE DETAIL: Postgres setup, maintenance and recovery (modes 12, 14, 15)
  ------------------------------------------------------------------------

  Mode 14, Library health check. It is read-only. It first reports how
  many registered profiles have a valid, broken, or empty GamePath and
  lists broken profile codes by name. It also checks every game database
  (except games set to Internal storage) and shows "Problem - <game>" for
  each one that is not ready.

  For broken paths, [R] Try automatic path repair first performs a dry-run
  candidate search. TeknoParrot Manager displays the exact proposed paths,
  then asks again before applying the reviewed set. The configured games
  folder is the default search root.

  If no candidate is found, TeknoParrot Manager shows each saved
  executable path and offers [C] to re-copy/re-extract only the affected
  profile codes from a configured source, or [S] to search another game
  folder.

  [S] Search another game folder accepts only an existing, canonical,
  non-reparse folder outside TeknoParrot, TeknoParrot Manager, and both
  ZIP source folders.

  [C] returns to AutoSync with only the broken profile codes selected; it
  cannot broaden into an all-games extraction. [M] Let me pick the correct
  executable or folder manually requires you to select the exact executable
  and never guesses. A complete HealthCheck backup is made before confirmed
  saves.

  Mode 15, Restore from backup. Option 1 lists all timestamped backup
  folders with file counts, newest first, and you type YES to confirm.
  Option 2 restores each database from its pg_dump backup. If it does not
  simply succeed, you see a plain line such as "The restore did not
  finish. Your data is back the way it was. TeknoParrot Manager put
  everything back and checked it." Then you see "Press D for details, or
  Enter to continue".

  Option 3 restores Emulators.xml/Platforms.xml/platform file(s) to their
  state before the script last wrote to them. Its labels read [taken
  before a write] or [safety snapshot taken before a restore].

  Option 4 is Reset and Restore. See 15) Restore from backup below.

  Mode 12, Postgres setup. Pressing D shows "Details". It starts
  with the note that TeknoParrot Manager checked each database by
  connecting to it with the game's own settings, and did not start any
  game.

  Then come a summary, what setup checked, one block per game (database,
  profile, what happened, what it means), other notes, what to do next,
  and totals.

  For each game, "What it means" says that TeknoParrot Manager connected
  with the game's own settings, how many tables it found, and that the
  game is ready.

  If some games kept their own PostgreSQL password or settings, the screen
  says so in yellow: "1 game kept its own PostgreSQL password or settings,
  so TeknoParrot Manager did not change it." Press D to see which.

  What is shown on screen is also written to the log.

  13) Required game patches
       Finds fixes that some game versions need. It only works for exact
       game versions it knows. You supply the patch ZIP files yourself,
       from your own computer.

       TeknoParrot Manager checks the game, saves a backup copy, applies
       the files, and checks them again. A checked patch does not prove
       that the game will play well.

       There are two ways to use it:

         Automatic   Lists the patches that fit your registered games.
                     One confirmation applies the list you are shown.
         Manual      You pick one patch and a game folder that is
                     already installed, registered or not.

       Both ways need the exact game version, your own local ZIP, a
       closed game, and everything the screen lists as required. The
       backup lets you undo the change. A game that already has the patch
       is skipped. Other files already there are never overwritten.

       At the start you choose A (your registered games), M (one game
       you pick), U (undo patches that TeknoParrot Manager installed) or
       Q (go back). Each game is listed once with its patch count, for
       example "Hummer Extreme Edition (14 patches)". Games with the same
       result share one line. Press D at the last question for the
       technical details.

  MORE DETAIL: Required game patches (mode 13)
  --------------------------------------------

  Both modes require an exact executable/build, a user-supplied local ZIP
  member with verified hashes, safe target state, closed game, and every
  listed prerequisite. One confirmation applies the displayed automatic list.
  TeknoParrot Manager keeps verified backup/undo evidence; it skips an exact
  already-applied target and refuses any other existing bytes.

  Automatic mode lists applicable recipes for registered games; manual mode
  installs a selected recipe into an already-installed game folder,
  registered or not.

  Messages in mode 13:

    "None of your registered games has a patch in this list. Nothing was
    changed." No registered game has a patch here. If a game is installed
    but not registered, use M.

    "Nothing was installed. Fix the problem above, then try again." A check
    blocked a fix. The reason is above that line in plain words. The line
    is not shown when everything was already installed.

    "Already installed, nothing to do". The game already has the patch.

    The technical details behind D are: patch names, exact reason, result
    codes, and the folder with your undo copy. They are also in the log.

  Option 13 has 120 exact-build recipes across 71 exact
  ProfileId/build/executable identities (54 game profiles).

  The list started with 58 earlier recipes and has grown since. Later
  additions include absent-only Main restores: MaiMai GreeN
  `freeglut.dll` and `libcurl.dll`, Rabbids Hollywood
  `RabbidsHollywood_Operator.exe`, and Cross Raid 1.05 Ver A
  `rom/shader.farc`.

  The first 58 recipes contain three Taisen Hot Gimmick 5 (2.04)
  single-file restores, and three local user-selected plugin restores
  (Mars Sortie 1.46.9, the separate Rabbids Hollywood operator plugin, and
  SB3 1.91 x64).

  It also contains five native recipes (Cross Raid 1.05 AMD/NVIDIA, VF5R
  1.001 AMD/NVIDIA, and Sonic Dash Extreme), 30 Main-component
  restorations (14 Hummer, 14 Hummer Extreme, two Primeval Hunt), two SB3
  FMOD restorations, and two Infinity Blade FX 1.02 restorations.

  The Taisen files are restorations only. Configure and save keyboard keys
  with `TTX-Config.exe`, then use `TTX-Loader.exe` as directed by the game
  guide. TeknoParrot Manager does not configure keys or run either utility;
  operator setup and game launch remain separate.

  Two further TMNT 1.59 Main recipes independently restore only absent
  OrenVid.dll and PK-UnityPlugin.dll under TMNT_Data/Plugins/x86_64/. They do
  not install BepInEx or change configuration. Setup, controls, launch and
  gameplay still require separate verification.

  BBCP Chronophantasma replaces only its exact known driver before-hash with
  the guide-required hash from the named Central Fiction Main ZIP; absent or
  unknown BBCP bytes are refused.

  The 108 `CreateFile` operations restore only absent targets; twelve
  `ReplaceFile` operations require exact before-hashes. Exact desired bytes
  are skipped, and all other states are refused.

  The four baseline Main-source plugin payloads and three added user-selected
  patch ZIPs are distinct. The Rabbids operator executable is separate from
  both the existing `Assembly-CSharp.dll` repair and BepInEx operator plugin;
  it is not executed, and TeknoParrot Manager does not change registry or
  `.conf` state.

  SB3's Main ZIP already contains its plugin bytes; that recipe restores only
  a missing installed target. MaiMai's two DLL restores are independent
  transactions.

  The two FMOD recipes separately restore missing Main-source `fmod64.dll`
  and `fmodstudio64.dll` targets; they are not an atomic pair, and DLL
  version/pair compatibility are unverified.

  The 30 Hummer, Hummer Extreme, and Primeval recipes restore missing Main
  components only; frame-count, `ElfLdr2` copy identity, and modern NVIDIA
  fog caveats remain outside these recipes.

  All seven BepInEx plugin targets require the core file to be present.
  Family Guy additionally requires its documented configuration value:

    `[Preloader.Entrypoint]`
    `Type = MonoBehaviour`

  Core-file presence is not a BepInEx version check. Silent Hill's codec BAT
  is separate and is never run or installed. Users provide exact named local
  ZIPs; TeknoParrot Manager does not host or download payloads.

  Elysion, Cross Raid 1.05, and VF5R 1.001 each use mutually exclusive
  AMD/NVIDIA shader alternatives with exact executable, hardware, and
  target-state checks. Cross Raid source documentation identifies version
  1.05 but not the `Ver A` suffix; the matching vendor profile/build is not
  runtime compatibility proof.

  Separately, the exact 1.05 Ver A Main `rom/shader.farc` restoration creates
  only when absent. Vendor undo restores base bytes into a new file object;
  the earlier base-create receipt refuses undo on changed identity and
  preserves those bytes. No other Cross Raid build is enabled.

  Sonic is an explicit opt-in exact-before/after executable replacement with
  backup and receipt undo; it does not prove a 60-fps outcome.

  Manual mode does not register games; patch success does not prove
  readiness, controls, launch, or gameplay.

  MAINTENANCE AND RECOVERY
  ------------------------

  14) Library health check
       Looks at your library and changes nothing by itself. It tells you
       how many registered games have a good, a broken, or an empty
       GamePath. It lists the broken ones by name.

       It also says clearly that it checked your setup and did not change
       anything.

       If some paths are broken, you can choose:

         [R] Try automatic path repair
             Searches for the right game folders. It shows you the exact
             paths it proposes. It asks you again before it changes
             anything. The folder with your games is searched first.

         [M] Let me pick the correct executable or folder manually
             You choose the exact game program yourself. Nothing is
             guessed.

       If no match is found, TeknoParrot Manager shows each saved game
       path and offers two more choices:

         [C] Re-copy/re-extract only these affected games from the
             configured source. It goes back to AutoSync.

         [S] Search another game folder.

       When no broken paths are left, it may offer [P] Set up PostgreSQL
       for these games. It may also offer shortcuts to [6] ReShade, [7]
       dgVoodoo2, [8] GPU Fix, [9] Force Feedback and [10] BepInEx.

       Other keys: [D] Details shows technical counts and the log path.
       [B] returns to the main menu. No repair or setup begins until you
       choose an action.

       It also checks every game database. A database that is missing,
       cannot be opened with the game's own settings, or has no tables
       shows as "Problem - <game>" under D. Next: run Postgres setup
       (menu 12). Games set to Internal storage are skipped here. They
       show "Game database: OK" with a note to start each game once so it
       makes its own database.

       It also has rows for these, with the names under D:

         - game types TeknoParrot Manager does not know
         - games TeknoParrot has not released yet ("not available yet")
         - emulators missing from your TeknoParrot folder
         - games that need you to pick the game file by hand (the profile
           names no game file and there is no setup file)
         - System 11 games with no saved files yet

  15) Restore from backup
       Puts back a saved copy. The menu calls this "Restore backup". You
       will see "Restore from Backup" and five choices (1 to 5, plus B to
       go back). Type 1, 2, 3, 4 or 5 and press Enter. Pressing only
       Enter goes back to the main menu:

         1) TeknoParrot UserProfiles backup
            Goes back to an earlier saved copy of your game settings
            folder (UserProfiles). You do not need File Explorer.

         2) Postgres database backup (only relevant if you've used the
            Postgres setup mode)
            Puts back each database from its saved copy.

         3) LaunchBox library backup (verified current-state backup first)
            Only matters if you used the direct LaunchBox link. It puts
            LaunchBox's library files back to how they were before
            TeknoParrot Manager last changed them.

         4) Reset and Restore: put back one game or all games from a
            restore point saved when TeknoParrot Manager started
            Puts one game or all games back to a restore point.
         5) Rebuild one game from its ZIP: put one game folder back to
            exactly what its ZIP holds (your old folder is kept)

       Lists of saved copies show the newest one first:

         1) You will see "Saved copies of your game settings, newest first:".
            Each folder is shown with the number of files in it.
            Type a number, then type YES to confirm.

         2) You will see "Available Postgres database backups (most
            recent first):". Each shows how many databases it holds.

         3) The newest LaunchBox backup is listed first. Each one has a
            label such as [taken before a write].

         4) You will see "Restore points, newest first:".

       The lists do not show the copies made when ReShade is removed.

       Keep LaunchBox and BigBox closed while you restore a LaunchBox
       backup. When the restore is done, you return to the menu.

       Choice 4 (Reset and Restore) works from restore points. Each time
       TeknoParrot Manager starts, it saves a checked restore point of
       your game settings (UserProfiles) and of its own settings. It does
       this only when something changed since the last one.

       The first restore point that has your games in it is always kept. Game files, saves and
       databases are not part of a restore point. Its menu:

         1) Reset one game (back to the first restore point)
         2) Restore one game (choose a restore point)
         3) Reset all games (back to the first restore point)
         4) Restore all games (choose a restore point)

         5) Remove older restore points
         B) Back

       Next (choice 4): for a single game, you confirm with YES. For all
       games, you type YES and then ALL. Nothing changes before you confirm.

       Choice 5 (Rebuild one game from its ZIP) is for a game that is
       broken for no clear reason. It puts the game folder back to
       exactly what is in the game's original ZIP. You need that ZIP in
       your ZIP folder. TeknoParrot Manager finds it by the names
       AutoSync uses and, when the DAT list knows the game, checks the
       ZIP against it. Its menu:

         1) Rebuild one game from its ZIP
         2) Put an old folder back (undo a rebuild)
         3) Delete an old folder I no longer need
         B) Back

       Choice 1: pick a game, read the preview (files, size, where your
       old folder will be kept) and type YES. The ZIP is unpacked and
       checked in a temporary folder on the same drive. Your current
       folder is then renamed and kept in TPM-old-game-folders, beside
       your games folder. Nothing is copied twice or deleted. Saves and
       your own settings that are not in the ZIP stay in the old folder.
       If anything goes wrong, the old folder is put back. The TeknoParrot
       settings for the game are not changed. If the ZIP is missing, the
       disk is too full, the ZIP does not match the DAT list or the game
       is running, it says so and changes nothing.
       Choice 2 puts the old folder back. Choice 3 deletes an old folder
       for good, after you type YES. Old folders use disk space until you
       delete them.


  APPLICATION
  -----------

  16) Check for Updates
       Checks by hand for the newest GitHub release and compares it with
       the version you are running. Nothing is downloaded or changed
       without your explicit Y/N confirmation.

       See CHECK FOR UPDATES below for full details.

  17) Create Support Package
       Gathers safe information into one ZIP file. You can send it when
       you ask for help. It does not include game files, credentials, or
       arbitrary folders.

       Follow these steps:

         1. In TeknoParrotUI, choose Troubleshooting -> Save information
            to a text file.

         2. Save it with exactly this name:
            TeknoParrot-Manager-TeknoParrotUI-Troubleshooting.txt
            Put it in the Reports folder:
            <TeknoParrotRoot>\TeknoParrotManager\Reports\
            (At the Create Support Package menu, D shows the exact
            folder.)

         3. In TeknoParrot Manager, type 17 at the menu.

         4. Choose 1) Create Support Package.

         5. Send the ZIP when asking for help. It is saved under
            <TeknoParrotRoot>\TeknoParrotManager\SupportPackages\.

       The same menu has 2) Open TeknoParrot Manager Logs and Reports.

       If only some of the information could be collected, the result says
       the package is partial. If the ZIP is ready but a temporary folder
       could not be removed, it says that. It never claims a clean success
       when something went wrong.

  18) Exit
       Exits the script.

  MORE DETAIL: Create Support Package (mode 17)
  ---------------------------------------------

  The ZIP collects safe TeknoParrot Manager, TeknoParrot, TeknoParrotUI,
  and affected-game diagnostics. It includes redacted profile snapshots,
  metadata-only plugin inventories, and per-file ReShade
  ownership/removal scan and transaction details when available.

  TeknoParrot Manager accepts only that exact allowlisted intake filename.
  Evidence is labeled Current, Ambient, or Stale; an old Action Required
  report is marked Stale until the affected workflow is rerun.

  Text is checked for binary/archive content and common private
  information before inclusion; unsafe content is recorded as rejected. A
  package that is missing some information is marked partial. If the ZIP
  is ready but a temporary folder could not be removed, the result says
  so and you can delete that folder yourself. If no ZIP is made, the
  result says the package was not created.


  ADAPTIVE RESPONSIVE MENU
  -------------------------
  The menu changes how much it shows to fit the size of your window:

    - A large window shows the full descriptions above.
    - A medium window shows one line for each option.
    - A narrow or short window shows only the labels.

  The menu numbers and what each option does stay the same.

  Three keys work at the menu prompt. Type the letter and press Enter:

    H   Open the separate help screen.
    L   Open the log folder.
    Q   Quit.

  MORE DETAIL: Adaptive responsive menu
  -------------------------------------

  A classic console window is maximized automatically on startup. Inside
  Windows Terminal (also when Windows opens a double-clicked .bat there)
  TeknoParrot Manager never resizes the window. You can resize it at any
  time, and the menu, progress bars and the ReShade profile chooser are
  drawn again for the new size.

  Within each release, menu numbers, what each option does, and how to
  choose one stay consistent across the responsive layouts -- only how
  much description text is shown adapts to your window size.


-------------------------------------------------------------------------------
  GAME SELECTION (AutoSync mode)
-------------------------------------------------------------------------------

  After you enter your folders, the script looks at the staging folder. It
  leaves out games that are already extracted there.

  If AutoSync extracts nothing new, it ends with one short note: "Nothing
  new was extracted, so registration was skipped. To register games
  already extracted, choose Register only." This is only a note. It is not
  under ACTION REQUIRED and does not send you to a saved list.

  You may also have a second (supplementary) ZIP source. Then both
  libraries are merged into one list. Games from the supplementary source
  are marked with [+]. The top of the list shows a count for each source,
  so you always know where a title came from.

  You will see something like this:

      347 game(s) already extracted -- not shown.
      136 game(s) available to extract (120 collection, 16 supplementary [+]).

  Then you see the selection menu:

      A) All unextracted games (136)
      L) Browse and select from list (136 games, A-Z)
      S) Search by keyword
      D) Done -- continue with selected queue
      B) Back / cancel AutoSync selection

  The prompt is "Enter A, L, S, D, or B". Above the menu a header says
  "Queue: empty" or "Queue: N game(s) selected".

  Next: type a letter and press Enter. Each choice is explained here.

  A -- All unextracted games
       Extracts everything that is not on disk yet. This is the fastest
       way to get a full library.

  L -- Browse and select from list
       Shows the games that are not extracted yet in A-Z order, 20 at a
       time. Games already in your queue are marked with *.

       Commands inside the list:

         Numbers or ranges   1,3,5-7 to add games to the queue.
         N                   Next page.
         P                   Previous page.
         B                   Back to the selection menu.
         D                   Done -- finish selecting and start extracting.

  S -- Search by keyword
       Type any part of a game name. The matching games are shown with
       numbers. Type numbers or ranges to add them to your queue.
       Type "back" to return to the selection menu, or "done" to finish.

  D -- Done (from the main menu)
       Carries on with whatever is in the queue. You can switch between
       Browse and Search as often as you like. This builds up one queue
       across many searches. Press D when you are ready.

       If the queue is empty, D leaves with no games selected, and
       extraction is skipped for that source. Use A to extract all games.

  The top of the screen always shows how many games are in the queue. After
  you press D, the full queue is listed before extraction starts.


-------------------------------------------------------------------------------
  THE STAGING FOLDER
-------------------------------------------------------------------------------

  AutoSync unpacks your games into a staging folder. Your original ZIP files
  stay where they are, in their source folders.

  On first setup, TeknoParrot Manager picks a safe default for you. It
  builds it from the TeknoParrot location you set, for example
  <same volume>\TeknoParrot Games.

  Next: press Enter to use it, or type B to browse for a different folder.

  TeknoParrot Manager makes a missing folder you accepted only when a real
  AutoSync run begins. A Preview/Dry Run leaves it alone.

  The folder you choose must follow these rules:

    - It is on a drive with enough room. A local drive is recommended
      because it is faster.

    - It is NOT inside the TeknoParrot folder, and does not contain it.

    - It does NOT overlap the main or supplementary ZIP source folder.

    - It is NOT inside the TeknoParrot Manager program/package folder, and
      does not contain it.

  Folder names. Extraction folders use the raw ZIP file name as-is, so
  they match the naming convention used by the collection.

  If a game was extracted earlier under an older naming style (spaces
  between bracket groups, or none), the script fixes the names. It
  recognizes the existing folder, so it will not make a duplicate.

  Collection information files. A ZIP in the ZIP source whose name starts
  with "!TeknoParrot Collection" holds the collection changelog, readme,
  and game notes. These are always skipped automatically, whatever their
  date.

  When a ZIP did change. AutoSync replaces that game's folder with the new
  files. First it copies every file in the old folder that is extra or
  different from the ZIP (saves, settings, ReShade files) to
  <TeknoParrotRoot>\TeknoParrotManager\Backups\AutoSyncReplaced\. If those
  files cannot be saved, that game is skipped and its old folder stays as
  it was. The same happens when no Backups folder is set up: that game is
  not updated and nothing is changed for it.

  If an extraction was interrupted:

    1. Look at the screen. It says ACTION REQUIRED.
    2. Open Details (type D and press Enter), and read the log.
    3. Check the source archive, the free space, and the retained paths.
    4. Try again.

  Do not delete an .extracting marker just to clear the warning. Removing
  it does not verify the game files. Seek help if needed.

  MORE DETAIL: The staging folder
  -------------------------------

  Every typed or browsed recovery choice passes the same checks as the
  first choice.

  A profile-backup folder or copy failure stops real AutoSync before
  extraction. There is no "continue anyway" override, including in
  unattended runs.

  For an interrupted extraction, TeknoParrot Manager preserves
  incomplete-operation evidence and reports ACTION REQUIRED. Review the
  log, source archive, available space, and retained paths before
  retrying.


-------------------------------------------------------------------------------
  REGISTRATION
-------------------------------------------------------------------------------

  Registration tells TeknoParrot which games you have.

  The script looks at each game folder and finds the game's .exe file (the
  program that starts the game). It matches that name to a TeknoParrot game
  setup file. TeknoParrot calls a game setup file a "profile".

  When a match is found, the game appears in TeknoParrot.

  Every game ends with one of the results below. The result is shown on
  screen.

  After new games are registered, you are asked once which country they
  should start in. Type 0 to leave them as they are. See REGION SETUP.

    Registered          A matching game setup file was found. Your game now
                        appears in TeknoParrot.

    Registered (fuzzy)  Many games share the same .exe name (for example,
                        game.exe is used by 80+ NESiCAxLive titles). The
                        folder name was a very close match for one game.
                        Its code and score are shown in Cyan (light blue)
                        so you can check them. Test the game to be sure.

    Registered (dat)    The folder name matched an entry in your dat file.
                        A dat file is a list of games and their codes. The
                        script uses the code from that list.

    Registered          The folder name matched a game code directly. This
    (code/fuzzy)        is used for games whose setup file has no .exe name.
                        The script picks the best .exe in the folder by
                        itself.

    Already set         This game already has a setup file. The script
                        leaves it exactly as it is. It never overwrites
                        your existing work.

    Register manually   The .exe name is shared by many games. The script
                        shows a short list of checked choices and you pick
                        one. If you press Enter instead, the game goes
                        into ACTION REQUIRED (a list shown at the end of
                        the run). Set it up in TeknoParrotUI.

    Register manually   A game setup file can point to only one game
    (duplicate)         folder. If two folders match the same game, only
                        the first one can be registered. The second one is
                        marked as a duplicate.

  What happens with duplicates:

    1. Right after registration, the script offers to sort them out.

    2. For each duplicate it shows which folder holds the game now and
       which folder wants it.

    3. You choose: [K]eep current, [S]witch to conflicting copy, or [Q]uit
       resolving.

    4. K keeps the current copy. S moves the game setup file to the other
       copy. Q leaves the rest for you to handle in TeknoParrotUI.

  Anything you do not sort out still appears in ACTION REQUIRED.

  At the end of the run, the script also offers a choice for each game it
  was unsure about. Any case you leave open stays in ACTION REQUIRED. There
  you can finish it in TeknoParrotUI.

  EVERY TEKNOPARROT GAME

  TPM is checked against every game setup file in TeknoParrot
  1.0.0.2334 (2,544 of them), and against the Eggman game list and guide. docs\GAME-SUPPORT.md lists every game
  and what TPM does for it. These cases work with no extra steps:

    Two versions of a game   Each version is registered. If TeknoParrot has
                             only one setup file for both, the second one is
                             reported as a duplicate. It is never dropped
                             without a message.

    A Lindbergh game         TeknoParrot has retired its Lindbergh setup file
                             and replaced it with a newer ElfLdr2 one. The
                             Eggman list names both, and both are
                             registered. If the ElfLdr2 one needs a game file
                             that is not in the folder, it is left out and
                             the log says why.

    A game TeknoParrot has   Listed as "not in TeknoParrot" (for example the
    no setup file for        Sega Rally 3 track mods and Escape from Monster
                             Manor). That is not a failure.

    Unusual file names       Game files that end in .exec or .chd, and names
                             with a hyphen (R-Tuned), are recognized.

  Games that use more than one ZIP. A game set has a child game that uses
  a parent ZIP. A child game is never registered only because its parent
  ZIP is present, unless the Eggman list names that parent ZIP. A System 11 game that names two ZIPs (child and parent)
  is registered only when both are in the same folder. If a game needs a
  disc image (*.chd), it is chosen for you when there is exactly one. With
  several, TeknoParrot Manager never guesses.

  System 11 saved files (optional). After registration, if a System 11
  game has no saved files yet, you see "OPTIONAL: System 11 saved game
  files". If you have your own saved-files set (a ZIP in your collection
  folders, or a folder or ZIP you pick), TeknoParrot Manager copies the
  files for your games into TeknoParrotUi's TeknoS11\state\<game>\cabinet-1
  folder. It only adds files and never replaces one. It tells you which of
  your games the set has no files for. It does not ask again when the set
  has nothing new. It does not provide or download the set.


  MORE DETAIL: REGISTRATION
  -------------------------

    Registered (fuzzy): the profile code and the similarity score are shown
    in Cyan so you can spot-check the match.

    Registered (dat): the dat's authoritative profile code is used directly.
    If the dat includes an Executable path, that exact binary is used.

    This covers three cases: shared-executable games, games whose exe is
    not in any GameProfile (e.g. pcsx2x6 / ELF-based titles), and slightly
    misnamed folders (fuzzy dat scan). Configure the dat path during setup
    or via datFile in TeknoParrot-Manager.overrides.json -- see PER-GAME
    OVERRIDES.

    Registered (code/fuzzy): the folder name matched a TeknoParrot profile
    code directly by Dice similarity. It is used for games whose
    GameProfile has an empty ExecutableName.

    Examples: BladeStrangers, LuigisMansion, MaiMaiGreen, PokkenTournament,
    SonicDashExtreme, HydroThunder. The best available executable in the
    folder is selected automatically.

    Already set: a profile for this game already exists and is left exactly
    as it is.

    Register manually: the executable is shared. TeknoParrot Manager
    presents validated candidates for an explicit choice. Pressing Enter
    leaves the case in ACTION REQUIRED for TeknoParrotUI instead of
    promoting a best guess.

    Register manually (duplicate): a TeknoParrot profile allows only one
    GamePath. If this folder resolves to a profile code another folder
    already claimed earlier in the same run, it cannot be auto-registered
    too.

    This is common with multiple ROM revisions of one game that share a
    generic exe name, e.g. several Virtua Fighter 5 Lindbergh dumps, or
    multiple Taiko no Tatsujin versions.

    The duplicate prompt lets you [K]eep the current copy, [S]witch the
    profile to the other copy, or [Q]uit and leave the rest for manual
    handling in TeknoParrotUI.


-------------------------------------------------------------------------------
  HOW FUZZY MATCHING WORKS
-------------------------------------------------------------------------------

  Many arcade platforms use one .exe name for all of their games. On
  NESiCAxLive, for example, every game uses game.exe. Without fuzzy
  matching, none of these games could be registered automatically.

  "Fuzzy matching" means matching names that are close, but not exactly the
  same.

  The script compares the game folder name with the known game codes. It
  gives each match a score from 0.0 (no match) to 1.0 (perfect match).

  What happens depends on the score:

    Score >= 0.72   Registered automatically. Shown in Cyan with the score
                    so you can check the match.

    Score >= 0.40   You get a list of choices and pick one. A game you
                    leave open stays in ACTION REQUIRED.

    Score < 0.40    Goes into ACTION REQUIRED with the full list of
                    possible games. No reliable guess could be made.

  WHEN FUZZY MATCHING GETS IT WRONG

  Sometimes a game is registered as the wrong game. To fix it:

    1. Save a checked copy of that game's setup file somewhere outside the
       UserProfiles folder (TeknoParrot's saved game settings folder).

    2. Find the correct official game and its .exe. If the script offers a
       checked candidate, use it. Otherwise set the correct GamePath in
       TeknoParrotUI.

    3. Do not delete the XML file just to try again.

  If the script gets the control type wrong (for example, a trackball game
  treated as a lightgun), add a familyOverride entry in
  TeknoParrot-Manager.overrides.json.

  To see how the score is worked out, and what is removed from folder names
  before comparing, see APPENDIX: FUZZY MATCHING DETAILS.


  MORE DETAIL: HOW FUZZY MATCHING WORKS
  -------------------------------------

    Score >= 0.40: the cases are presented in TeknoParrot Manager for an
    explicit candidate choice. Unresolved cases remain in ACTION REQUIRED.

    When a game is registered against the wrong profile: preserve a
    verified backup of its UserProfile outside UserProfiles, and confirm
    the correct official profile and executable. Use a validated candidate
    when offered. Do not delete XML merely to retry.

    forceArchetype chooses a control reference; it does not change
    registration matching.


-------------------------------------------------------------------------------
  CONTROL PROPAGATION
-------------------------------------------------------------------------------

  Setting up the controls for every game by hand takes a very long time.
  Control propagation saves you that work.

  You set up the controls for ONE game of each control type. The script then
  copies those controls to your other games of the same type.

  "Control type" means the kind of game: lightgun, driving, fighting,
  trackball, and so on. "Binding" means telling TeknoParrot which button or
  stick does what.

  How to use it:

    1. Open TeknoParrotUi.exe.

    2. Pick one game of a control type you use. Bind everything in that
       game: buttons, axes (steering or aiming), Test, Service, Coin and
       Start.
       Next: do the same for one game of each other control type you use.

    3. Run this script again.
       You will see: after registration, the script copies the controls.
       If it has not asked before, it first asks about your devices.

    4. Read the line about your example games.
       You will see: "You have N games with their controls set up." Then a
       preview lists what would change. It ends with "Preview only. Nothing
       was saved." If a copied setting looks wrong, a yellow "Check first"
       line also appears.

       Next: press D to see each reference game, with the aim settings the
       script will copy: relative input, sensitivity, hide-cursor and "Use
       Keyboard/Button For Axis". Check these against your real hardware.
       They apply to every other game of that type.

    5. Answer the question "Copy controls from N games to your other games
       of the same type? (Y/N, D = details)".
       Answer Y if the settings match your hardware.
       Answer N if they do not. Nothing changes. Then fix the reference
       game in TeknoParrotUI and run the script again.

       After a copy, the program asks: "Undo these changes and put your
       game settings back as they were? (Y/N)". Answer Y to put everything
       back at once. You can also undo later with main menu option 15
       (Restore backup).

    6. Start ONE updated game and test it before you trust the rest.
       Next: if anything is wrong, restore from the saved copy made at the
       start of the run (main menu option 15, Restore backup).

    If a game type has no usable example, its games are skipped.
    The registration screen ends with "Registration run finished" (not
    "Done"). That means the run ended, not that every game's controls work.
    When games are skipped because no game of their type has your controls
    yet, Details names one game of each type to set up first in
    TeknoParrotUI, then run Propagate Controls (menu 4). Choosing a device
    in the binding plan does not set up a game.
    The summary counts the skips. Details and the log list the games.
    Add one game of this family with your own controls, then run this again.
    If all games are skipped, the screen says no game was changed.
    A failed save still ends as an error.

  Good games to start with:

    Fighting / buttons    Street Fighter III, BlazBlue, Tekken 7,
                          Dead or Alive 5

    Driving               Daytona Championship USA, Initial D,
                          OutRun 2 SP, F-Zero AX

    Lightgun              House of the Dead 4, Aliens Extermination,
                          Point Blank

    Trackball             Golden Tee Live, Silver Strike Bowling,
                          Target Toss Pro

  Example for step 5: you bound a driving game with a real wheel. Then
  "Use Keyboard/Button For Axis" should read False. If it reads True,
  answer N, fix the reference game in TeknoParrotUI, then run the script
  again.

  Mixed devices in one game are fine. For example, one game can use an
  Xbox stick to aim and arcade buttons to fire. Mixed setups copy across
  as you set them up.

  What is safe:

    - Button settings in your reference game are kept.
    - Buttons that are already set up in other games are kept.
    - Everything is reported, so you can see exactly what changed.

  Check first lines:

    The script shows a yellow "Check first" line for a few known mistakes.
    Press D to see a Warning line for each reference game. They usually
    mean the reference game was set up with a stand-in device instead of
    its real hardware.

    - Driving: "Use Keyboard/Button For Axis" = True. The wheel and pedals
      would act like keyboard keys instead of smooth controls.

    - Lightgun: "Use Relative Input" = True. The gun would follow mouse
      movement instead of pointing at an exact spot on the screen.

    - Any sensitivity set to 0. This switches off aiming or axis response
      in every game that gets the copy.

    A Check first line does not stop the copy. It is a hint to double-check
    the reference game in TeknoParrotUI before you answer Y.

  What stays manual (and is reported):

    - Game-specific controls that do not exist in the game you bound.
    - Any game whose control type has no reference game yet. These appear
      under "CONTROLS SKIPPED BY DESIGN" in the ACTION REQUIRED section at
      the end of the run. Each one tells you to add one game of that control
      type with your own controls, then run again.


  MORE DETAIL: CONTROL PROPAGATION
  --------------------------------

    How it matches: each control is matched by function (its input mapping
    and analog type), so a steering value is never copied onto a gun axis.

    The script copies each control's device exactly as you bound it, and
    carries aim-mode settings (relative input, sensitivity, hide-cursor)
    between same-type games so a copied game feels identical to the one
    you set up.

    Mixed devices: TeknoParrot stores each control's device individually,
    so a single game can use, for example, an Xbox stick to aim and arcade
    buttons to fire. Mixed setups copy across intact.

    What is safe, in technical terms:

      - Reference-game button bindings are preserved. An explicit canonical
        reference can correct the InputAPI setting without rebinding
        buttons.

      - Already-bound buttons are preserved; InputAPI may still be
        corrected.

    Warning patterns, in technical terms:

      - Driving: "Use Keyboard/Button For Axis" = True (wheel/pedal axes
        would be read as digital keyboard input, not analog).

      - Lightgun: "Use Relative Input" = True (gun aim would be read as
        relative mouse movement, not absolute screen position).

      - Any sensitivity setting carried as 0 (silently disables
        aiming/axis response on every propagated game).


-------------------------------------------------------------------------------
  PROPAGATE CONTROLS                -- mode 4
-------------------------------------------------------------------------------

  Mode 4 does only the copy step from CONTROL PROPAGATION above.

  It uses the same set of games, the same question and hardware-check
  warnings, the same saved copy before any change, and the same report.

  It skips AutoSync and Register. It does not extract or register any games.

  Unlike the copy step at the end of AutoSync and Register, mode 4 shows a
  preview first and offers a one-step undo after it saves.

  Use it when your library is already registered and you have just set up a
  new or updated reference game in TeknoParrotUi.exe. You can copy the
  controls right away. You do not have to wait for a full AutoSync or
  Register run.


-------------------------------------------------------------------------------
  DEVICE SURVEY
-------------------------------------------------------------------------------

  On a first run (or when you ask), the script asks which controls you
  have: Xbox pad, arcade stick, trackball, spinner, wheel, lightgun, or
  keyboard.

  If a controller is connected, it looks for it first. When it finds an
  Xbox-style controller, it asks one question ("Use the Xbox controller
  for all games?") instead of seven. A match that is only a guess from a
  device name is shown as "may be connected" and never answers for you.

  It then prints a plan of which game to bind with which device. It
  changes no game file.

  Your answers are saved in TPM's own settings folder
  (State\Controls), so you are not asked the same thing twice. Next time
  it shows your answers and asks one question ("Keep these answers?"). It
  asks again if a controller turns up that you said you do not have. A
  saved file that cannot be read is set aside, never overwritten, and the
  last good copy is kept next to the new one as a .bak file.

  MY CONTROLS (Propagate Controls, choice 5)

    Nothing here changes a TeknoParrot game file.

    - Learn my arcade buttons. You say how many players and buttons your
      cabinet has. First TPM waits 2 seconds with your hands off
      the cabinet. If a key shows up on its own, a button may be stuck,
      and it tells you. If LEDBlinky is installed, it then offers the
      keys its own key list names (one Y/N). It can also offer the
      standard arcade keys that MAME and Ultimarc I-PAC boards both use
      (for example Left Ctrl for button 1). It uses them only after you
      say yes and press two buttons that really send those keys. Then it
      asks you to press each control ("Press Player 1 Start") and
      remembers the key it sends. Esc skips a control your cabinet does
      not have. A key already given to another control is refused. If a
      press also sends another key, or a button is still down after 3
      seconds, it tells you and keeps the first key. At the end, one
      question ("Save this?") keeps the answers, and TPM also
      notes which arcade encoders it can see right now. Other encoder
      brands' own setup files are not read: no maker writes down which
      pin is which button. Pressing the buttons works for any encoder.
    - Is it the same controller? My controls and the Device Survey say,
      in one line, whether TPM sees the same arcade encoders as
      when you taught it your keys, whether one was added or removed, or
      whether it could not check. It is only a hint. It never changes a
      saved key or answer and never marks a game Verified. If you
      changed your encoder, learn your buttons again. Details:
      TPM can only tell encoders from makers it recognizes (today
      Ultimarc, such as the I-PAC). For each one it keeps a private
      one-way code in State\Controls, made from the maker and model
      numbers on this PC. The numbers, serial numbers and device paths
      are never saved, logged, printed or put in a report, and the code
      never leaves your PC. Moving an encoder to another USB port is not
      a change. Swapping one for an identical one cannot be noticed.
    - Show or print the controls of one game. Lists each control the game
      has, what it does, the key TPM suggests, and whether the
      game has it set up. It suggests your key only for the standard
      controls: coin, start, numbered buttons, and directions the game
      plainly calls directions. For anything else, such as a game's
      "Menu Up" or "Volume Down" slot, it says "I'm not sure". If your
      own LEDBlinky file gives a control a color, the page also shows it
      in a Light column (TPM does not change any lights). One
      question saves the list as a page in Reports\Control Guides and
      opens it so you can print it.
    - Tell TPM how a game played. W means you played it and every control
      you tried reacted correctly. TPM keeps that, with the date
      and the game's revision, and calls the game's controls Verified
      until its controls or its settings change. Starting a game,
      registering it, or seeing a controller never makes a game Verified.
      A wheel, gun or other analog game is not Verified until you say its
      calibration is done (or not needed). You can also record that a
      first-run Test or Service menu step is still to do. N makes
      TPM forget that a game worked.
    - Show or print my cabinet controls. The same page for the cabinet
      itself: each control and the key it sends.
    - Does my cabinet fit the game? The page for one game starts with a
      few plain lines that compare the game with what you told
      TPM. It says if your cabinet has enough players and buttons
      ("Your cabinet has no button 3" is shown on that row), and which
      device the game needs (trackball, spinner, wheel and pedals, light
      gun) that you said you do not have. If you have no wheel but have
      an Xbox controller, or no light gun but have a trackball or an
      Xbox controller, it says that can stand in. If you never told
      TPM, it says it does not know instead of guessing. This only
      compares: it sets up nothing and changes no game file. The same
      lines go to the log.
    - Exit, Pause and Menu. When learning buttons, TPM first
      asks, one by one, if your cabinet has an Exit, a Pause or a Menu
      (admin) button. The answer is N unless you say Y. For these three,
      Esc counts as a key, because many cabinets use Esc for Exit. They
      show on your cabinet page.
    - Undo my last save. Every time TPM saves your answers or
      keys it keeps the older file next to it as a .bak copy. When such
      a copy exists, My controls offers "6 = Undo my last save". It
      shows how many keys the older answers hold and asks one question.
      If you say Y the older answers come back, and your newest answers
      are kept as the copy, so you can undo the undo.

  If you have no lightgun, you can aim gun games in two ways:

    - With the Windows mouse cursor (a mouse or trackball, absolute aim).
    - With the Xbox right stick.


-------------------------------------------------------------------------------
  FRONTEND LAUNCHER INTEGRATION
-------------------------------------------------------------------------------

  A frontend is a program that shows all your games in one nice menu.

  The script works with these:

    LaunchBox           The script adds your games to it directly.

    RetroBat/Batocera   This is a one-time setting used when games are
                        extracted. It changes how game folders are named
                        on disk.


  LAUNCHBOX
  ---------

  At the end of each normal interactive run, the script offers an optional
  LaunchBox step.

  You will see:

      TeknoParrot registration is finished.

      Optional: add games to LaunchBox.
      [P] Preview first. No changes.
      [A] Add missing games (backed up).
      [G] Fill in game details and make playlists (backed up).
      [V] Group regions and versions of a game into one (backed up).
      [S] Keep LaunchBox in step with TeknoParrot: removed, moved, renamed
          games (backed up).
      [L] Link games for art and details (backed up).
      [C] Fill in players and controllers for Big Box (backed up).
      [F] Import file only. No changes.
      [B] Skip this step.

  Then you will see the question "Choice, default P".

  What each choice does:

    P   Shows a preview. It reads your LaunchBox files and shows what A
        would do. LaunchBox is not changed.

    A   Writes straight into LaunchBox's own Data\ files, after the close
        and backup checks. New games get their real game name (for
        example "Too Spicy", not "2Spicy"), plus release year and
        developer. Firmware updaters, drive checkers and test boards are
        never added. A game is linked by itself only when TeknoParrot
        Manager is sure; if not, you choose from the possible games. The
        platform it makes is called TeknoParrot and is looked up as
        Arcade.

    G   Fills in game details and makes playlists, after a backup. It
        fills in the release year and developer where LaunchBox has
        nothing yet. It makes playlists for each arcade hardware family,
        plus "Light gun games" and "Driving games". A game that cannot
        start yet (game file, firmware or BepInEx missing) gets a plain
        "Needs setup" note and goes into a "Needs setup" playlist. Both
        go away by themselves when the problem is fixed. Your own
        playlists, notes and details are never touched. Restore puts
        everything back.

    V   Groups the regions and versions of one game into one entry, after
        a backup. You pick the version. Only games that are certainly
        the same game are grouped. The default version follows the
        region you chose in Region setup (menu 11). Restore puts them
        back.

    S   Keeps LaunchBox in step with TeknoParrot, after a preview and a
        backup. Removed games are removed. Moved games get the new
        location. Old TeknoParrot Manager names become the clean title. A
        missing game file, such as an unplugged drive, never removes a game.
        Names you typed and games with a Games Database ID are never
        renamed. If most games have no profile, nothing changes. Restore
        undoes it.

    L   Links games for art and details, after a backup. It looks each
        game up in LaunchBox's own game list on your PC. A game is linked
        by itself only when TeknoParrot Manager is sure (a different
        year or number is a different game; region, version and board
        tags are ignored). For the rest you choose from possible games.
        You see every old name, new name and ID first and approve before
        anything is saved. Names you typed yourself are never replaced.
        Nothing is downloaded.

    C   Fills in players and controllers for Big Box, after a backup. For
        each TeknoParrot game it fills in how many players the game has
        and which controller it needs (joystick, steering wheel, light
        gun, trackball or paddle), from the game's TeknoParrot controls.
        It fills empty boxes only: what you or LaunchBox already have is
        never changed, and a game that already lists controllers keeps
        them. You see every game and what it would get first (press D)
        and approve before anything is saved. Right after saving it
        offers to undo at once. Restore puts everything back.

    F   Creates a reference file. LaunchBox is not changed.

    B   Skips the LaunchBox step.

  To add your games with A:

    1. Close LaunchBox and BigBox, and keep them closed.
       The script never closes them for you.

    2. Type A and press Enter.
       You will see: "Close LaunchBox and BigBox first. TeknoParrot Manager
       will not close them for you." and "Only missing games are added. Your
       own entries are kept." You already chose A, so there is no extra
       "now?" question.
       Next: the script asks for the platform.

    3. If you are asked for it, type your LaunchBox install folder.
       Next: the script asks how the games should appear.

    4. Choose where your TeknoParrot games should appear.
       You will see: "Platform: 1 Arcade, 2 TeknoParrot, 3 Both, 4 Custom,
       B cancel". The choices are:

         1   Mixed into your existing Arcade platform
         2   A separate "TeknoParrot" platform
         3   Both: mixed into Arcade AND a separate TeknoParrot platform
         4   Custom platform name (apply only; not offered in preview)

       The choice is not saved; you are asked again next time.
       "Both" creates two separate game entries that point at the same
       TeknoParrot game setup file.

    5. Read the plan of changes.
       You will see: what would change, then "Write exactly these changes
       after a verified backup? (Y/N, D = about the risks)". This is the
       only approval.
       Next: Y writes the changes. N stops. You will see "LaunchBox write
       canceled; nothing was changed."

  After the write: new games have no box art or details yet. Choose L
  (Link games for art and details) and G (Fill in game details and make
  playlists) in the LaunchBox step, or in LaunchBox right-click a game
  and use Edit -> Search.

  Logos and box art (optional). After the LaunchBox choices you see:
  "Optional: add logos or box art to LaunchBox from a folder you pick."

      [I] Add pictures from a folder. You see a preview first.
      [U] Undo the last picture import.
      [S] Skip this step.

  I asks for your folder, then "Picture type: 1 Clear logos, 2 Box
  front, B back", then the platform. You see a preview: sure matches,
  close matches to check, and games with no picture. When LaunchBox's own
  game list is on your PC, each picture is matched by the game itself:
  another name of the same game is a sure match, and a picture of a
  different game with the same name is never used. Close names still need
  your yes. Pictures LaunchBox already has stay unless you choose to
  replace them. Nothing is downloaded. U removes the pictures that the
  last import added.

  Lighting for your arcade buttons (LEDBlinky, optional). If you use
  LEDBlinky, a full run (not "New game only") ends with "Optional:
  lighting for your arcade buttons." TPM looks for LEDBlinky on
  your drives and in Program Files, or asks where it is and remembers
  the folder. You see:

      LEDBlinky was found on this PC.
      [P] Preview first. No changes.
      [A] Add lighting info to LEDBlinky (backed up, can be undone).
      [U] Undo the last add.
      [C] Use a different LEDBlinky folder.
      [O] Switch between the usual arcade colors and your own colors.
      [B] Skip this step.

  A game gets only the controls it uses that your cabinet has. You see a
  preview first, a saved copy is made, and you can undo it. Only entries
  TPM added are ever removed.

  If anything looks wrong afterward:

    1. Choose option 15 (Restore backup) in the main menu.

    2. Choose option 3, "LaunchBox library backup".
       You will see: your LaunchBox backups, newest first.
       Next: pick one. This restores the exact files that were changed.

  PREFER THE MANUAL IMPORT WIZARD INSTEAD?

  LaunchBox has its own Import wizard. The script can give you a reference
  file and step-by-step instructions for it.

    1. At the LaunchBox choice, type F and press Enter.
       You will see: "Exported : N game(s)", then "File :" with a path.
       Then you will see "HOW TO IMPORT INTO LAUNCHBOX" with the wizard
       steps.
       Next: close LaunchBox, then follow those steps.

  The file is called TeknoParrot-LaunchBox-Import.xml. It is saved in the
  TeknoParrotManager\Reports folder inside your TeknoParrot folder.

  Important: import the game setup *.xml files themselves (the ones in the
  UserProfiles folder). Do not import the game .exe files.


  MORE DETAIL: LAUNCHBOX
  ----------------------

    A writes directly into LaunchBox's own Data\ files after the close and
    backup checks. It asks each time how TeknoParrot games should appear
    (the platform choice above). "Both" creates two separate game records
    pointing at the same TeknoParrot profile.

    The F step writes TeknoParrot-LaunchBox-Import.xml to the Reports folder
    and prints the exact wizard steps, including --profile=%romfile%.xml
    and the UserProfiles folder. Import the profile *.xml files themselves,
    not game executables.

    Restore backup option 3 ("LaunchBox library backup") restores the exact
    changed files.



  CROSSHAIR SETUP
  ---------------

  A crosshair is the aiming mark you see on screen in a lightgun game.

  Mode 5 puts your chosen crosshair pictures into all your registered
  lightgun games. You can run it at any time from the main menu. It does
  not start a full AutoSync or registration run.

  It works for lightgun games. Examples are House of the Dead 4, Aliens
  Extermination, Aliens Armageddon, Rambo, and Terminator Salvation.

  HOW CROSSHAIRS WORK IN TEKNOPARROT

    TeknoParrot shows a custom crosshair when two picture files sit next to
    the game's .exe. They are named P1.png (player 1) and P2.png (player
    2).

    Where the script puts the files depends on the kind of game:

    - ElfLdr2 games: one shared pair goes in the ElfLdr2 loader folder.
    - Pcsx2x6 games: the pair goes in the emulator's official crosshairs
      folder.
    - Standard games: each game gets its own pair, in the folder that holds
      the game's .exe.

  USING THE CROSSHAIR PICKER

    1. Choose 5, Crosshair setup, in the main menu.
       You will see: a screen titled "Crosshair Setup".

    2. Wait while the script checks the Crosshairs\ folder next to the
       script for PNG files.
       You will see: "Found N valid crosshair(s). Opening the built-in
       preview...". A file that fails the check is reported and skipped.

    3. Look at the preview window.
       You will see: a window titled "TeknoParrot Crosshair Preview". It
       lists all valid images: the 321 included designs plus any valid
       PNGs you added. It says "Ready. Choose a crosshair for P1."

    4. Choose a design for Player 1 (P1). Click it, or press Tab and
       Shift+Tab to move to it and press Enter or Space.
       Next: choose a design for Player 2 (P2) the same way. You can pick
       the same design for both players. The window closes after you pick
       P2.

    5. Check the selected names in the console.
       You will see: "P1: <name>    P2: <name>" and the question
       "Apply these crosshairs? (Y/N, default Y)".
       Next: Y copies the images. N stops. You will see "Crosshair setup
       canceled. No files were changed."

    6. Wait while the script copies the images to every registered
       lightgun game folder.
       You will see: a report of deployed, skipped, and errored games.

    7. Answer the question about the Windows mouse cursor.
       You will see: "Also hide the Windows cursor for all lightgun games?
       (Y/N)".

       Next: Y hides the cursor in all lightgun games. A saved copy of the
       game settings is made automatically first. N leaves the cursor
       alone. You can run mode 5 again later if you change your mind.

       This question is skipped if crosshair setup had a problem.

    If the preview window does not work as expected:

    - To close it early, press Esc, choose Close preview, or wait 45
      seconds.

    - The script keeps the choices you already made. It asks in the
      console for each missing number.

    - If the preview cannot open, type both numbers in the console.

    - The script remembers your last choice by file name and offers it as
      a default. Press Enter to reuse it on your next run.

  ADDING YOUR OWN CROSSHAIRS

    You can add any PNG image to the Crosshairs\ folder at any time. On the
    next run it appears in the preview window.

    File names can be anything. But numbering them makes them easier to
    find in the preview window.

    321 crosshair designs (000.png--320.png) are included in the package.
    Source: https://www.emuline.org/topic/3080-custom-crosshairs-emulators-loaders/

  MORE DETAIL: CROSSHAIR SETUP
  ----------------------------

    Supported games are those whose TeknoParrot profile has
    <GunGame>true</GunGame> in the UserProfile XML.

    Each PNG is validated against the PNG magic-byte signature. Anything
    that fails validation is reported and skipped.

    ElfLdr2 games: a single shared pair is placed in the ElfLdr2 loader
    folder (searched dynamically since its exact name varies across
    installs).

    Pcsx2x6 games: P1.png and P2.png are placed in
    <pcsx2x6 folder>\TeknoParrot\crosshairs\, the official upstream
    location (pcsx2x6 folder searched as pcsx2x6, PCSX2x6, pcsx2, PCSX2,
    or any pcsx2-prefixed subfolder).

    The current contract marks cursor_path as emulator-owned:
    TeknoParrot Manager does not write PCSX2.ini and reports existing
    values read-only when available. Unknown or unavailable contract state
    fails closed.

    Standard games: each game receives its own P1.png and P2.png in the
    folder containing the game's executable.

    Cursor hiding: if you answer Y, the script sets the cursor-hide field
    (HideCursor, "Hide Cursor", or DisableCursor depending on the game) to
    enabled in each gun game's UserProfile XML. A timestamped backup is
    taken automatically before any XML is changed. This step is
    independent of the crosshair copy.


  RESHADE VISUAL ENHANCEMENTS
  ---------------------------

  What is ReShade?

    ReShade is a free tool that makes game pictures look better. It sits
    between the game and your screen and adds effects to the image.

    ReShade is optional. Games do not need it to run.

    ReShade setup adds a few files to each game folder you choose. They are
    a small helper file (a DLL), a settings file called ReShade.ini and some
    effect files. Files that are already there are not replaced unless you
    approve.

    To remove ReShade later, use ReShade setup again. It removes only the
    files TeknoParrot Manager added.

  What can it do for your arcade games?

    Sharpening       Many TeknoParrot games run at a fixed picture size. They
                     look a little blurry on a modern HD screen. ReShade's
                     sharpening filters bring back the crisp look.

    CRT scanlines    Real arcade monitors (CRT screens) show thin horizontal
                     lines across the picture. ReShade can copy this effect.
                     Games then feel more like the real arcade on an LCD.

    Color boost     Older games often look flat and washed out on modern
                     monitors. ReShade's color and contrast filters bring
                     back the vivid, punchy look of the original.

    Borders / bezels Some games are made for a 4:3 shape (nearly square).
                     On a widescreen monitor they show black bars. ReShade
                     can fill those bars with arcade cabinet artwork.

  Your games work perfectly WITHOUT ReShade. It is entirely optional and
  you can uninstall it at any time.

  You do not need to know anything about graphics or shaders. You pick
  effects from a simple menu.

  BEGINNER VISUAL PROFILES

    A "look" is a ready-made set of effects. ReShade setup calls each look a
    "profile". You pick one look from a list.

    ReShade setup opens a preview window and shows the list in the terminal.
    You will see:

      Choose how your game should look.
      Nothing will be changed until you confirm.
      The preview is only an approximation.
      Pick a profile in the preview window or below.

    The list has two groups: CRT Choices and Main Catalog. Each row looks
    like this:

      [2] * Fast CRT [CRT-ZFast]

    The star (*) marks the look that is selected now. Under each row is a
    short description. It ends with the rough cost of the look: light,
    medium or heavy. This tells you how hard the look works your PC.

    Original is the plain picture with no effects. It is only there to
    compare against.

    The preview window has these views:

      Before   The plain picture, with nothing added.
      After    The picture with the look added.
      Split    Plain on the left, with the look on the right.
      Slider   Goes from 0 to 100, from all look to all plain.

    If the preview window cannot open, you will see:

      ReShade visual gallery unavailable; choose a profile in the terminal.

    Next: choose a look from the list. You will see this line under it:

      Choose: [1-N] Select profile  [U] Use selected profile
      [N] Skip ReShade -- no changes  [R] Reopen preview  [B] Back
      [D] Details

    (TeknoParrot Manager prints this on one line, or wraps it on a narrow
    window. N is the number of the last look in the list.) The prompt is
    Choice.

      A number   Picks that look. The preview window moves to it too.
                 You will see: Preview selection changed to: and the name.

      U          Uses the look you picked. If you have not picked one, you
                 will see: Choose a numbered profile before using it.

      N          Skips ReShade. You will see: ReShade setup skipped. No
                 ReShade files were installed or changed.

      R          Reopens the preview window if you closed it.

      B          Goes back and cancels. You will see: ReShade setup
                 canceled. No files were changed.

      D          Shows details: About this list, the DLL signature, and for
                 each look What it does, Techniques, Preview and Cost.

    The looks you can pick are listed here, best first.

    CRT Choices:

      Original
          No visual processing.

      Curved Arcade Monitor [CRT-Geom]
          Makes the game look like it is on a curved arcade cabinet
          monitor: bent screen edges, rounded corners, scanlines and a fine
          dot pattern. Cost: medium.

      Classic Arcade CRT [CRT Lottes]
          Makes the game look like a classic arcade CRT screen: visible
          scanlines and a soft shadow-mask pattern. Cost: heavy.

      Sharp Aperture Grille [CRT-Aperture]
          A sharp, bright Trinitron-style picture: fine red, green and blue
          stripes, clear scanlines and a light glow; the screen stays flat.
          Cost: medium.

      Balanced Flat CRT [CRT-Easymode]
          A balanced flat CRT look: clear scanlines and a gentle color
          mask with sharp edges and no screen curve. Cost: medium.

      Sharp Phosphor CRT [CRT-Hyllian]
          A sharp, vivid CRT look: crisp pixels, scanlines that fade
          between the lines and a fine phosphor dot pattern. Cost: medium.

      Arcade CRT Glow [CRT Lottes + ArcaneBloom]
          The classic arcade CRT look plus a soft glow around bright areas,
          like a bright cabinet screen. Cost: heavy.

      Detailed Arcade CRT [CRT-Royale]
          The most detailed CRT look, with a fine phosphor mask and
          scanlines; it needs a strong graphics card. Cost: heavy.

      Fast CRT [CRT-ZFast]
          Scanlines and a light mask for a CRT look that costs very little
          speed, so it also runs well on slower PCs. Cost: light.

      Lightweight CRT [CRT-Pi]
          Simple scanlines for a retro arcade look that also runs well on
          slower PCs. Cost: light.

      Scanline Glow [CRT-Pi + ArcaneBloom]
          Simple scanlines plus a soft glow around bright areas, at a lower
          cost than the classic CRT look. Cost: medium.

      Bright Scanlines [Levels + CRT-Pi]
          Simple scanlines with deeper blacks and brighter whites, so the
          picture stays bright behind the scanlines. Cost: light.

    Main Catalog:

      Arcade Glow [ArcaneBloom]
          A soft glow around bright lights and effects, like a bright
          arcade cabinet screen. Cost: medium.

      Crisp 3D [SMAA + Curves + Levels]
          Smooths jagged edges in 3D games and adds stronger contrast with
          deeper blacks. Cost: medium.

      Crisp 3D Glow [SMAA + Levels + ArcaneBloom]
          Smooths jagged edges in 3D games, deepens blacks and adds a soft
          glow around bright areas. Cost: medium.

      Balanced Contrast [Curves]
          Stronger contrast in the midtones, so a flat-looking game gets
          more depth. Cost: medium.

      Black/White Point Adjustment [Levels]
          Deeper blacks and brighter whites for games that look washed out
          or gray. Cost: light.

    The cost words are rough estimates, not measurements. No claim is made
    about how fast any look runs on your PC.

    Previews are only approximations. Every look except Original shows a
    visible difference in the preview. A preview is not a guarantee for
    every game.

    Previewing never changes your games or your settings.

    Next: pick a look, then go to HOW TO SET IT UP below to confirm it and
    choose your games.

  MORE DETAIL: BEGINNER VISUAL PROFILES
  -------------------------------------

    Where each look comes from. The friendly description is followed by the
    rough cost and the approved shader filename and technique. (Press D in
    the terminal for the full list with preview notes.)

      Original
          Techniques: (none; no ReShade techniques)
      Curved Arcade Monitor [CRT-Geom]
          Techniques: CRTGeom.fx / GeomCRT
      Classic Arcade CRT [CRT Lottes]
          Techniques: CRT_Lottes.fx / CRT_Lottes
      Sharp Aperture Grille [CRT-Aperture]
          Techniques: CRTAperture.fx / ApertureCRT
      Balanced Flat CRT [CRT-Easymode]
          Techniques: CRTEasymode.fx / EasymodeCRT
      Sharp Phosphor CRT [CRT-Hyllian]
          Techniques: CRTHyllian.fx / CRTHyllian
      Arcade CRT Glow [CRT Lottes + ArcaneBloom]
          Techniques: CRT_Lottes.fx / CRT_Lottes; ArcaneBloom.fx / ArcaneBloom
      Detailed Arcade CRT [CRT-Royale]
          Techniques: crt-royale.fx / CRT_Royale
      Fast CRT [CRT-ZFast]
          Techniques: zfast_crt.fx / CRTZFast
      Lightweight CRT [CRT-Pi]
          Techniques: CRTPi.fx / CRTPi
      Scanline Glow [CRT-Pi + ArcaneBloom]
          Techniques: CRTPi.fx / CRTPi; ArcaneBloom.fx / ArcaneBloom
      Bright Scanlines [Levels + CRT-Pi]
          Techniques: Levels.fx / Levels; CRTPi.fx / CRTPi
      Arcade Glow [ArcaneBloom]
          Techniques: ArcaneBloom.fx / ArcaneBloom
      Crisp 3D [SMAA + Curves + Levels]
          Techniques: SMAA.fx / SMAA; Curves.fx / Curves; Levels.fx / Levels
      Crisp 3D Glow [SMAA + Levels + ArcaneBloom]
          Techniques: SMAA.fx / SMAA; Levels.fx / Levels;
          ArcaneBloom.fx / ArcaneBloom
      Balanced Contrast [Curves]
          Techniques: Curves.fx / Curves
      Black/White Point Adjustment [Levels]
          Techniques: Levels.fx / Levels

    Original is the untouched reference, not an effect. There are 17
    profiles built from 12 of the 25 approved effects. No current profile
    needs HDR, so no Actual HDR Setups Only group is shown.

    Alternatives that do the same job (sharpening, color strength, CRT
    looks) are never stacked automatically.

    Retired profiles are no longer offered: Cartoon, Film Grain,
    Monochrome, Sepia Tone and Vignette.

    Also retired now: Smooth Edges, Clean & Sharp, Adaptive Clarity, Smooth
    Gradients, Vivid Arcade, Shadow & Midtone Balance, Exposure & Tint,
    Color Balance, Enhanced Arcade, Detail-Preserving Sharpen, Filmic
    Sharpen, Colorfulness, Fast Game Enhancement, HDR Highlight Mapping and
    HDR Black-Level Fix.

    A saved choice or history entry naming a retired profile is reported as
    retired and never remapped. Files it installed are left untouched and
    stay removable.

    The edge smoothing in Crisp 3D and Crisp 3D Glow works on the jagged
    edges of 3D game graphics. The still preview picture has none, so their
    notes say the preview shows only the contrast, black/white and glow
    part.

    The cost words are rough estimates; no performance claim is made. How
    a look appears on a real game has not been measured.

    Shader sources are live-fetched from pinned upstream commits and
    integrity-checked, with each effect's license text written beside it.
    They are not bundled in the release ZIP. Labels do not expose internal
    cache paths.

    These are approved TeknoParrot Manager-generated profile definitions.
    Shader sources are live-fetched and integrity-checked during
    deployment.

    The newest CRT looks (Curved Arcade Monitor, Sharp Aperture Grille,
    Balanced Flat CRT, Sharp Phosphor CRT and Fast CRT) also write a short
    preset of values for their shader. It has a 640x480 picture size (the
    usual arcade picture size, set equal for screen and frame as the
    shaders ask) plus mask, scanline and brightness values.

    Curved Arcade Monitor sets its interlace switch to 5 so a 480-line
    picture does not flicker. Balanced Flat CRT raises its scanline cut-off
    so its scanlines stay on at 480 lines.

    The preview pictures are TeknoParrot Manager approximations, not the
    shaders running.

    Not offered, on purpose:

      CRT-Guest-Advanced and the Sony CRT shader candidate
          No verifiable pinned source in the approved repositories.

      A vertical-mask (tate) CRT look
          No verifiable shader.

      FXAA
          The SweetFX copy at the pinned commit is only a 127-byte
          placeholder, not a usable shader.

      LUT color grading
          The lut.png at the pinned commit is a 273-byte neutral table, so
          a look built on it would change nothing.

      MAMEPostProc (ColorMAME)
          Dropped because its saved file has no license notice or
          copyright line, its port repository has no license file, and it
          adds a refresh-roll flicker bar.

      scanlines-abs
          Dropped because no look needs it (CRT-Pi already gives the
          cheapest scanlines).

    One visual gallery opens before the final confirmation. It uses the
    bundled and hash-validated TeknoParrot Manager landscape reference at
    PreviewAssets\ReShadePreviews\TPM-preview-landscape.png.

    It offers Before as the untouched baseline, After as the processed
    profile, Split with baseline on the left and processed output on the
    right, and a 0-100 slider from all processed to all baseline while you
    switch profiles.

    The preview is illustrative, not a pixel-perfect guarantee for every
    game. Cached renderings are local TeknoParrot Manager-owned data and
    are not trust or deployment evidence.

    If rendering or display is unavailable, TeknoParrot Manager shows the
    profile description and continues normally. Previewing never changes
    ReShade trust, generated presets, game files, monitor settings, or
    deployment state.

  HOW IT IS INSTALLED

    ReShade works by putting one helper file (a DLL) in the same folder as
    the game's program file. When the game starts, it loads ReShade by
    itself.

    TeknoParrot Manager picks the right helper file name for each game.
    You do not need to know any of this -- TeknoParrot Manager handles it
    for you.

  MORE DETAIL: HOW IT IS INSTALLED
  --------------------------------

    The DLL name depends on the graphics API the game uses:

      d3d9.dll       DirectX 9 games
      dxgi.dll       DirectX 10 / DirectX 11 games
      d3d12.dll      DirectX 12 games
      opengl32.dll   OpenGL games and BudgieLoader games

    TeknoParrot Manager detects the correct name automatically by scanning
    the game's executable. For BudgieLoader games it always uses
    opengl32.dll regardless of what the scan finds. For OpenParrot games the
    DLL is placed in an openparrot subfolder rather than the game root.

  HOW TO SET IT UP

    You set up ReShade from the main menu, in ReShade setup (option 6).

    TeknoParrot Manager looks for the ReShade helper files (DLLs) in
    <TeknoParrotRoot>\TeknoParrotManager\Assets\ReShade\ . A  ReShade\
    folder next to TeknoParrot-Manager.ps1 is also found, and the startup
    tidy-up moves it into the managed folder. ReShade works with 64-bit
    games. 32-bit games are skipped. The one file it needs is:

      ReShade64.dll (needed for ReShade setup, which is Mode 6)

    WHERE TO GET THE DLLS

    The DLLs are NOT included in the release ZIP or the source repository
    (ReShade is free software but its DLLs are not redistributable).

    You have two options. Option A is recommended.

    OPTION A -- Automatic download (recommended)

      Step 1.  At the main menu, type 6 for ReShade setup.
               You will see: ReShade Visual Enhancements Setup, then
               four choices:

                 S) Set up ReShade visual enhancements
                 R) Remove verified TeknoParrot Manager-managed ReShade
                    files
                 U) Undo ReShade changes
                 B) Use my bezel folder (bezels you already have)

               The prompt is Action (S/R/U/B, default S).
               Next: press Enter, or type S and press Enter.

      Step 2.  If ReShade is not downloaded yet, you will see:
               ReShade 64-bit DLL not found.
               Next: type D and press Enter. D means Download here.

               The choices are:
                 D) Download automatically from reshade.me
                 B) Browse for a file I already have
                 N) Skip

               The prompt is Choice (D/B/N). Choose B to pick a file you
               already have, or N to skip.

      Step 3.  Wait while TeknoParrot Manager downloads and checks the
               official installer from reshade.me.
               Next: it unpacks the helper files by itself.

      Nothing is bundled with TeknoParrot Manager itself. The installer is
      fetched fresh from reshade.me under ReShade's own redistribution
      policy.

    OPTION B -- Manual (if you prefer, or already have the DLL)

    Step 1.  Go to  https://reshade.me  and download the free installer.
             Choose the standard version (not the add-on version) unless
             you know you need add-on support.

    Step 2.  Run the installer.
             You will see: it asks for a game executable (program file).
             Next: point it at a 64-bit TeknoParrot game exe.

    Step 3.  Let the installation finish.
             You will see: a DLL file in that game folder (for example
             dxgi.dll or d3d9.dll).
             You do not need to select any shaders at this stage.

    Step 4.  Copy that DLL into the  Assets\ReShade\  folder under
             <TeknoParrotRoot>\TeknoParrotManager\ .
             Next: rename the copy to  ReShade64.dll.

    Step 5.  Run TeknoParrot Manager and choose "ReShade setup" from the
             main menu, or answer Y when prompted at the end of a normal
             run.

    After that, TeknoParrot Manager walks you through the steps below.

    CHOOSING YOUR LOOK AND YOUR GAMES

    Step 1.  Read the DLL message.
             You will see a short line such as: ReShade (version) is ready
             to use. Windows could not confirm who published the DLL,
             which is common for ReShade.

             A line under it says: Choose [D] below for the signature
             status, SHA-256 and thumbprint.
             Next: nothing to do. Go on to step 2.

    Step 2.  Pick a look from the list (see BEGINNER VISUAL PROFILES).
             Next: type the look's number, then type U to use it.

    Step 3.  Confirm the look. You will see:

               Use the selected ReShade profile?

             with these choices:

               [Y] Yes, use (your look)
               [S] Custom preset
               [B] Back

             The prompt is Choice (default Y).
             Next: press Enter for Y.

             Use S only if you already have your own ReShade preset file (a
             ready-made set of effects, .ini). S asks: Path to your
             ReShade preset (.ini) file (or type B to browse). Then it says
             Custom preset selected.

             B says: ReShade setup canceled. No files were changed.

    Step 4.  Choose which games get ReShade. You will see:

               Which games should get ReShade?
               You can run setup again later to add or change individual
               games.

             with these choices:

               A) All (number) registered game(s)
               L) Browse and select specific games

             The prompt is Enter A or L.
             Next: type A for all games, or L to pick games.

    Step 5.  If you typed L, you will see a paged list with * marking the
             games you picked. Its help line says: Enter number(s) to
             toggle (e.g. 1,3,5-7) | N=next | P=prev | A=all | D=done.
             Next: type the game numbers, then type D when done. Here D
             means done.

    Step 6.  If you picked more than one game, you will see how many can be
             changed. Some may be left alone to protect your own files. The
             line says: Press D to see why. You will then see
             Apply (look) to (number) games? with these choices:

               [Y] Yes
               [S] Select games one by one
               [B] Back
               [D] Details

             The prompt is Choice, default Y.
             Next: press Enter to apply the look to every game that can be
             changed. Choose S to go game by game, or B to cancel.

    Step 7.  If some games already use a different TeknoParrot Manager look,
             you will see Previously TeknoParrot Manager-managed: and the
             old and new look for each game.

             The choices are:

               [A] Change these TeknoParrot Manager-managed games to the
                   selected profile
               [K] Keep their current profiles
               [S] Select games manually
               [D] Details
               [B] Back

             The prompt is Choice, default A.
             Next: press Enter to change them, or type K to keep their look.

    Step 8.  You will see: Installing ReShade into (number) games...
             Next: wait. Then read the result screen below.
             While it works, the progress line counts only the games
             being changed (for example "Applying ReShade: 1 of 34"), not
             your whole library. Checking your games first is shown as its
             own step, "Checking your games for ReShade".

    TURNING OFF TEKNOPARROT'S OWN CRT EFFECT

    Some TeknoParrot games already have a CRT effect of their own. A ReShade
    CRT look on top of it can look doubled. Setup asks about this only when
    one of your chosen games already has such a setting.

    If your look is a CRT look and a game can be turned off, you will see:

      This game already uses TeknoParrot's own CRT look.
      Together with this ReShade look, it can look doubled.

    (For several games it says: (number) of these games already use
    TeknoParrot's own CRT look.) Then the choices appear:

      [K] Keep TeknoParrot's CRT look (default)
      [T] Turn it off for this game
      [D] Details

    The prompt is Choice, default K. With several games, [T] says Turn it
    off for (number) games.

    Next: press Enter to keep TeknoParrot's CRT look, or type T to turn it
    off. If you type T, you will see:

      OK. It will be turned off only in games that get ReShade now.
      A saved copy of your game profiles is made first.

    The change happens for each game right after ReShade is installed on
    it. When it is done you will see: TeknoParrot's own CRT look was turned
    off for (number) games. A line says: Next: You can undo this in ReShade
    > Undo ReShade changes. (Or, if there is no undo copy: Next: To undo it,
    use Restore backup.)

    If nothing was changed you will see: TeknoParrot's own CRT look was not
    changed.

    If your look is not a CRT look, or nothing can be turned off, you will
    see: This game uses TeknoParrot's own screen settings, such as a CRT
    look. TeknoParrot Manager keeps them as they are. A ReShade look can add
    to them. Then Press D for details, or Enter to continue (for several
    games: Press D at the next menu for details).

    Good to know: removing ReShade later does not turn TeknoParrot's own
    CRT look back on. To put it back, use ReShade > Undo ReShade changes or
    Restore backup.

    THE RESULT SCREEN

    When ReShade setup is finished, you see a short result.

    If it worked, you will see:

      Done: (look) applied to (number) games.
      To turn the effect on or off, start a game and press the Home key.

    If nothing was changed, you will see: Nothing was changed. After that
    comes a line starting Not changed: that says why. It may also say:
    Next: You can undo this in ReShade > Undo ReShade changes.

    If a game could not be changed, you will see in red: Problem: (number)
    games could not be changed. See the FAILED lines above, or the log.

    When some games were left alone, missing or unsafe, you can choose what
    to do next. Only the keys that apply are shown:

      [A] Replace (that game or those games) with TeknoParrot Manager's
          ReShade (you choose the look again; a copy of the old files
          is saved, so you can undo it)
      [S] Choose games one by one
      [M] Open the Library Health Check to see which games could not be found
      [B] Leave them as they are
      [D] Details

    The prompt is Press A, S, B or D (the letters match the keys shown; for
    example Press A, S, M, B or D). The default is B.

      A    Goes straight into ReShade setup to replace the old ReShade
           files of those games, with no separate "Replace the old files?"
           question. You still choose the look and confirm it in setup. A
           copy of the old files is saved first, so you can undo it.

      S    Goes back into ReShade setup so you can choose games one by one.

      M    Opens the Library Health Check (main menu 14) to repair game
           paths that could not be found.

      B    Leaves the games as they are. Or press Enter: back to the main
           menu.

      D    Shows details, then asks again. The details start with: Press A
           to replace protected ReShade files. TeknoParrot Manager asks you
           to confirm before it changes anything.

    If no choice is needed, the screen ends with:

      Press D for details, or Enter to return to the menu

    Press D to see the full technical information, or Enter to go back to
    the main menu. The same details are also kept in the log.

  MORE DETAIL: HOW TO SET IT UP
  -----------------------------

    The download audit records the authoritative reshade.me source URL,
    installer filename and version, computed SHA-256, transfer method/size/
    elapsed time/average speed, and Authenticode signer/subject, status,
    thumbprint, and final trust result.

    The SHA-256 is an audit hash;
    TeknoParrot Manager does not claim it matches a separately published
    ReShade digest.

    TeknoParrot Manager validates the installer Authenticode status and
    pinned signer thumbprint before trusting it. A mismatch fails closed and
    returns to the manual-path choice. The trusted installer is then
    extracted into ReShade64.dll.

    Signature rules for a DLL you provide yourself:

      a. TeknoParrot Manager shows the version of the DLL you provided and
         checks reshade.me for updates.

      b. User-provided DLL signature checks are informational only; an
         invalid or missing signature warns but does NOT block deployment.
         TeknoParrot Manager separately verifies its downloaded official
         installer against pinned Authenticode status and certificate
         values before extraction. Confirm manually supplied DLLs came from
         reshade.me.

    In plain words, ReShade setup lets you use a preset file (a ready-made
    set of effects) or just the look you picked, and then install ReShade
    on all games or on a selection from a list. These are the confirm
    screen (S = Custom preset) and the game chooser (A or L) described
    above.

    The DLL with the correct name is copied into each selected game folder.

  PER-GAME PRESETS

    This is about preset files (.ini), not about the look you pick. A custom
    preset you choose with S at the confirm screen applies to every game you
    selected.

    To give one specific game a different preset, follow these steps. A
    preset can also be given to one game while every other game stays on "no
    preset".

    Step 1.  Create a  ReShadePresets\  folder here:
             <TeknoParrotRoot>\TeknoParrotManager\Assets\ReShadePresets\
    Step 2.  Put a file named  ProfileCode.ini  in it. Use your game's code
             in place of ProfileCode, for example
             <TeknoParrotRoot>\TeknoParrotManager\Assets\ReShadePresets\Daytona3.ini.

    Find a game's code (its profile code) in
    TeknoParrot-Manager-controls.txt. It is written after every real run.

    A per-game file always overrides the global choice for that one game
    only. Every other selected game still gets whatever you chose with S at
    the confirm screen.

    A file whose name does not match any registered profile code is reported
    as WRONG NAME and ignored, the same way CustomThumbnails handles a
    mismatched icon filename.

  USING RESHADE IN-GAME

    Once ReShade is installed, you can use it in the game.

    Step 1.  Start a game that has ReShade.
             Next: press the  Home  key.

    Step 2.  You will see: the ReShade overlay with a list of effects.
             Next: turn an effect on or off with its tick-box. Change its
             settings with the sliders.

    Your settings are saved automatically to a ReShade.ini file in the game
    folder, so you only need to set them once.

    Common effects to try for arcade games:

      LumaSharpen or CAS            Sharpening
      CRT_Royale or CRT_Lottes      CRT scanlines and curvature
      Levels or Vibrance            Color and contrast
      Border                        Bezel artwork (needs a border image file)

  CHANGING YOUR LOOK FOR ALL GAMES OR ONE GAME

    You can change your look at any time. TeknoParrot Manager saves a copy
    before it changes a game, so you can undo it (see the next topic).

    To change the look for ALL games:

    Step 1.  At the main menu, type 6.
             Next: type S (or press Enter) at Action (S/R/U/B, default S).

    Step 2.  Pick the new look in the list, then type U.
             Next: press Enter at Choice (default Y) to confirm it.

    Step 3.  At Enter A or L, type A for all games.
             Next: at the Apply question, press Enter for [Y] Yes.

    Step 4.  If you see [A] Change these TeknoParrot Manager-managed games
             to the selected profile and [K] Keep their current profiles,
             press Enter to change them.
             Next: read the result screen.

    To change the look for ONE game:

    Step 1.  At the main menu, type 6.
             Next: type S (or press Enter) at the Action prompt.

    Step 2.  Pick the look you want, then type U and confirm it.
             Next: at Enter A or L, type L.

    Step 3.  Type the number of that game.
             Next: type D when you are done. Here D means done.

    Step 4.  If a game has an earlier look, you may be asked:
             Reapply (look) for this game? (Y/N, default N) or
             Use remembered (look) for this game? (Y/N, default N).
             Next: type Y to use that earlier look, or press Enter to use
             the look you picked.

    One game is also what you get if you choose S at the Apply question
    (S = Select games one by one).

  UNDOING YOUR LOOK

    Undo puts a game back the way it was before TeknoParrot Manager changed
    it.

    Step 1.  At the main menu, type 6.
             Next: type U at the Action prompt.

    Step 2.  If you see There is nothing to undo right now. there is nothing
             to do. TeknoParrot Manager saves a copy each time it changes
             the ReShade of a game, and none are saved yet.
             Next: press Enter to return to the menu.

    Step 3.  Otherwise you will see: Undo ReShade changes. Under it is
             this line: TeknoParrot Manager changed the ReShade of these
             games. Newest first.
             Each row looks like this:

               3) Daytona USA - no ReShade -> Fast CRT, 2026-11-03 14:05

             Next: read the choices below it.

    Step 4.  Choose what to undo. The choices are:

               [1-k] Undo one game (or [1] Undo this game)
               [A] Undo all (number games)
               [M] More games (only when there is more than one page)
               [D] Details
               [B] Back

             The prompt is Choice, default B. The list shows 4 games per
             page, newest first.
             Next: type a game's number to undo one game, or A to undo
             all.

    Step 5.  To undo ONE game, you will see a short preview. It says the
             game goes back from one look to another. You will then see:
             Any answer other than YES cancels, and nothing is changed.
             Next: type YES to undo it. Anything else says Canceled.
             Nothing was changed.

    Step 6.  To undo ALL games, you will see: This undoes the last ReShade
             change of (number) games. A game that changed since then is
             left as it is. Any answer other than ALL cancels, and nothing is
             changed.
             Next: type ALL to undo all of them.

    Step 7.  When it is done, you will see: ReShade changes were undone for
             (number) games. A line says: Next: Start the game to check its
             look. Then: [D] Details, or press Enter to continue.
             Next: press Enter to continue, or D for details.

    If a game was changed after TeknoParrot Manager changed it, you will
    see: (Game) changed after TeknoParrot Manager changed it. It says which
    kinds of file are different now. You can choose [U] Undo only the files
    that did not change (shown only when that is possible), [D] Details, or
    [C] Leave it as it is. The prompt is Choice, default C.

    If an undo did not finish, you will see Press D to see the files to
    check before you play.

    To put back TeknoParrot's own CRT look that you turned off, use
    ReShade > Undo ReShade changes (if an undo copy exists) or Restore
    backup from the main menu.

  MORE DETAIL: UNDOING YOUR LOOK
  ------------------------------

    The D key on the Undo menu shows, for each game: Change, Look before,
    Look now, Changed on, CRT setting, Files saved, Files the change added
    and Saved copy. It also says: Undo puts files back only while they are
    exactly as TeknoParrot Manager left them.

    For the preview of one game, the plain-words lines can include: The
    ReShade files TeknoParrot Manager added are removed. Its own ReShade
    files are put back exactly as they were. TeknoParrot's own CRT look is
    turned back on.

    A look is shown as the look name, no ReShade, or its own ReShade.

  UPDATING RESHADE

    ReShade setup checks reshade.me for a newer version. If there is one,
    you will see Available: and the version number, then:

      [Y] Update now  [N] Keep current version  Choice, default Y

    Next: press Enter (or type Y) to update, or type N to keep your
    current version. Y downloads and verifies the official installer,
    extracts the DLLs, and uses them in the setup.

    Replacing the files yourself is an advanced fallback. Use it only if
    the automatic update does not work.

    1. Download the new installer from reshade.me.
    2. Run it on any game exe (or extract the DLL manually with 7-Zip).
    3. Copy the new DLL to Assets\ReShade\ReShade64.dll (under
       <TeknoParrotRoot>\TeknoParrotManager\), replacing the old one.
    4. Run ReShade setup (main menu option 6, Mode 6) again to redeploy the
       updated DLLs.

  REMOVING RESHADE

    Removing ReShade takes ReShade away from your games. It touches only
    files that TeknoParrot Manager added itself.

    Step 1.  At the main menu, type 6.
             Next: type R at the Action prompt.

    Step 2.  Wait while TeknoParrot Manager scans your games.
             You will see how many verified TeknoParrot Manager-owned files
             it found.

             Then you will see either: No ReShade games need review or safe
             removal. or: The next chooser contains only games with
             removable or protected ReShade findings.

             You will also see: Protected bundled, preinstalled, changed,
             and ambiguous files will be preserved.
             Next: choose games in the picker (A for all, or L for some).

    Step 3.  Read the preview. You will see: ReShade removal preview -- no
             changes have been made: with a REMOVE row for each file to
             remove and a KEEP row for each protected file to keep.
             Next: read the rows.

    Step 4.  Confirm. You will see: Type REMOVE to back up and remove
             verified TeknoParrot Manager-owned files, or press Enter to
             cancel.
             Next: type REMOVE to confirm. Press Enter or choose back to
             cancel. Cancel leaves every file unchanged.

    Step 5.  Read the result. It lists how many games had effects removed.
             You will see: Next: You can undo this in ReShade > Undo
             ReShade changes.
             Next: press Enter to return to the menu.

    Files that are not TeknoParrot Manager's own are kept. Game programs,
    TeknoParrot game setup files, LaunchBox files and other frontend files
    are never removed.

  MORE DETAIL: REMOVING RESHADE
  -----------------------------

    The removal chooser scans registered games and uses the existing
    filtered game chooser. It shows only games with removable or reviewable
    ReShade findings. The preview enumerates each verified
    TeknoParrot Manager-owned file to remove and each protected file to
    keep.

    TeknoParrot Manager removes only a TeknoParrot Manager-managed ReShade
    DLL, ReShade.ini, or approved effect file when the ownership manifest
    is valid, the destination is inside the current ReShade target folder,
    and the live SHA-256 exactly matches the recorded value.

    Immediately before each backup and deletion, TeknoParrot Manager
    re-reads the profile metadata, re-resolves the target, and rechecks the
    destination as an existing canonical non-reparse leaf inside that
    target. A verified backup is created first and a failed manifest update
    restores the files.

    Bundled/preinstalled, unowned, ambiguous, changed, malformed, and
    out-of-target files remain protected. Game executables, TeknoParrot
    profiles, LaunchBox files, and other frontend files are never removal
    targets.

    The result report separates removed effects, already-clean games,
    missing saved paths, protected bundled/preinstalled files, protected
    ambiguous or changed files, malformed metadata, safe rollbacks, and
    failures.

  NO WELCOME WINDOW OR COUNTERS

    Every ReShade.ini that TeknoParrot Manager writes has an [OVERLAY]
    section with TutorialProgress=4, and ShowClock, ShowFPS, ShowFrameTime,
    ShowScreenshotMessage and ShowPresetTransitionMessage set to 0. So no
    welcome window, counters or messages show when a game starts. The key
    that opens ReShade still works.

    A short ReShade version banner may still show for a moment at game
    start. ReShade has no setting to hide it.

  NOTE ON KEY CONFLICTS

    ReShade uses the  Home  key to open its overlay by default. Some games
    use the same key for something else. If that happens, you can change
    ReShade's key.

    Step 1.  Open the game's ReShade.ini file in the game folder.
    Step 2.  Find the line  KeyOverlay=
    Step 3.  Change the key code on that line, then save the file.

  ATTRIBUTION

    ReShade is developed by crosire and is distributed under the BSD
    3-Clause license. The included DLLs are unmodified binaries of the
    official ReShade release.

    For source code, full license text, and the latest version see:

      https://reshade.me
      https://github.com/crosire/reshade

  Library Health Check also reports how many registered games have ReShade
  installed. This is for information only.

  It is not flagged as something to fix. ReShade is a per-game cosmetic
  choice, not a clear right-or-wrong answer like a GPU fix.

  Library Health Check also lists the games that need BepInEx and do not
  have it set up. You see "Games that need BepInEx and do not have it set
  up:" followed by the game names. BepInEx is flagged only for games
  whose profile says they need it.

  Library Health Check also has a Game support row. It says OK when nothing
  is missing, or "Needs attention" when some games need you: a game file is
  missing, a second game file (for example a CHD) is not chosen, or
  PostgreSQL settings are missing. Choose D to see, for each emulator, how
  many games are registered, have their game file and have setup steps in
  your Game Notes file. The steps come from the copy of the Game Notes page
  that TeknoParrot Manager saved earlier; this check never goes online.

  The health result screen offers direct [6] ReShade setup after the
  read-only report.

  DGVOODOO2 LEGACY COMPATIBILITY
  --------------------------------

  What is dgVoodoo2?

    Some older arcade games were written for old graphics methods:
    DirectX 8, DirectDraw (DX1-DX7), or the 3dfx Glide API. On modern PCs
    these calls can fail silently. The result can be crashes, black
    screens, or missing geometry.

    dgVoodoo2 (by Dege) is a free compatibility layer. It catches those old
    graphics calls and re-issues them as modern DirectX 11/12 commands.

    It works by placing one or more small DLL files in the game's folder.
    It may also add or replace dgVoodoo.conf. It does not modify the game
    executable.

    TeknoParrot Manager does not automatically remove unowned or changed
    hook files; use the advanced troubleshooting path for those files.

  What it fixes

    DX8 games     -- games that import  d3d8.dll  receive  D3D8.dll  (and
                     D3DImm.dll for the legacy immediate-mode layer).
    DDraw games   -- games that import  ddraw.dll  receive  DDraw.dll
                     (+ D3DImm.dll).
    Glide 2x/3x   -- games that import  glide2x.dll  or  glide3x.dll
                     receive the matching Glide wrapper.

  Should I use it?

    Only if a game crashes, shows a black screen, or draws wrongly the
    first time you start it. Games that run correctly do not need it.

  How to set it up

    Step 1.  At the main menu, choose "dgVoodoo2 setup."
             Next: if the DLLs are not there yet, you will see these
             choices:

               D) Download automatically from the official GitHub release
               B) Browse for a folder I already have
               N) Skip

    Method A -- Automatic download (recommended):

      1. Type D and press Enter. D means Download here.
         You will see: TeknoParrot Manager fetches the latest release from
         the official dege-diosg/dgVoodoo2 GitHub Releases source.
         Next: wait. It unpacks the files it needs into  Assets\dgVoodoo2\
         under  TeknoParrotManager  in your TeknoParrot folder.

      Nothing is bundled with TeknoParrot Manager itself.

    Method B -- User-provided folder:

      1. Download the latest dgVoodoo2 ZIP from:

           https://dege.freeweb.hu/dgVoodoo2/dgVoodoo2/

      2. Open the ZIP. Create a folder called  dgVoodoo2  inside
         <TeknoParrotRoot>\TeknoParrotManager\Assets\  (a  dgVoodoo2\
         folder next to TeknoParrot-Manager.ps1 also works, but only when
         the Assets one holds no dgVoodoo2 files) and copy in these files:

           From the  MS\x86\     subfolder : D3D8.dll  DDraw.dll  D3DImm.dll
           From the  3Dfx\x86\  subfolder : Glide2x.dll  Glide3x.dll
           From the root of the ZIP      : dgVoodoo.conf (optional; a copy
                                           is added to each game you pick
                                           that has no dgVoodoo.conf)

      3. Run TeknoParrot Manager and choose "dgVoodoo2 setup" from the main
         menu, or answer Y to the prompt at the end of a normal run.

    Method C -- Custom folder:

      Keep your dgVoodoo2 DLLs anywhere and enter the path when prompted.
      The path is saved to the configuration file, so you only need to do
      this once.

    When setup is finished you will see a result screen with these choices:

      [D] Details   [O] Open support/log guidance
      [B] Back to main menu

    The prompt is Choose D, O, B. The default is B. If some games were
    skipped because of a missing path, setup does not show this screen.
    It shows [H] Open 14) Library Health Check for missing paths and
    [B] Back to main menu, and asks Choose H or B. The default is B.

    Next: press Enter to go back, or D to see each game's details.

    The result also says how many games you selected, for example "You
    selected 5 games: 3 changed, 1 already set up, 1 skipped." It says
    where the backup is. Press D to see "Every game you selected": every
    game with its result, and the reason for each game that was skipped
    or failed.

  MORE DETAIL: DGVOODOO2 SETUP
  ----------------------------

    When GitHub supplies the asset digest, TeknoParrot Manager validates it
    and fails closed on a mismatch before extracting the files it needs into
    Assets\dgVoodoo2\.

    TeknoParrot Manager records the source, filename/version, computed
    SHA-256, and transfer metrics. If no digest is supplied, the SHA-256
    remains an audit value rather than an authenticity claim.

  How the wizard works

    The wizard looks at every registered game's program file for old
    graphics calls. It shows you a list of games it found before it asks
    you to confirm.

    You can install to all the games it found at once, or pick games by
    hand from the full list.

    For games it found, it copies only the DLL(s) needed for that game's
    API. For games you picked by hand with no detectable API, it copies all
    available DLLs.

    The  dgVoodoo.conf  in your dgVoodoo2 folder is added to every game you
    pick whose folder has no dgVoodoo.conf yet. A game folder that already
    has one keeps it. Setup also adds the DLLs that a game is missing. A DLL
    that is already there is never replaced. The one exception is a
    per-game config file (see "Per-game config overrides" below).

    To undo the added dgVoodoo.conf for a game, delete the dgVoodoo.conf in
    that game's folder (the folder with the game's exe). That folder had
    none before, so nothing of yours is lost. If you do not want it added to
    more games, take dgVoodoo.conf out of your dgVoodoo2 folder before you
    run setup.

  Per-game config overrides

    To give one game its own  dgVoodoo.conf , follow these steps.

    Step 1.  Create a  dgVoodoo2Presets\  folder here:
             <TeknoParrotRoot>\TeknoParrotManager\Assets\dgVoodoo2Presets\
    Step 2.  Put a file named  ProfileCode.conf  in it. Use your game's
             code in place of ProfileCode, for example
             <TeknoParrotRoot>\TeknoParrotManager\Assets\dgVoodoo2Presets\VF5.conf.

    A per-game file always replaces the dgVoodoo.conf in the game folder on
    every run, because it is an explicit per-game choice. Keep your own copy
    of any dgVoodoo.conf you want to keep before you run setup. A checked
    copy is kept only to roll back if the setup fails part way. There is no
    undo for a finished run.

    A game without a per-game file gets the global dgVoodoo.conf only when
    its folder has none. A config that is already in its folder stays as it
    is.

    A filename that does not match any registered profile code is reported
    as WRONG NAME and ignored, the same way ReShadePresets and
    CustomThumbnails handle a mismatched filename.

  Removing dgVoodoo2

    TeknoParrot Manager does not remove files it did not add. They may
    belong to another tool, so existing or changed files stay as they are.

    Taking out files by hand from a known, user-owned setup is an advanced
    troubleshooting action. It is not the normal beginner way.

  MORE DETAIL: REMOVING DGVOODOO2
  -------------------------------

    TeknoParrot Manager does not delete an unowned graphics hook because it
    may belong to another tool. Existing or changed files remain untouched.
    Any manual removal of a known, user-owned deployment is an advanced
    troubleshooting action, not the normal beginner workflow.

  Library Health Check reports which registered games are eligible for
  dgVoodoo2 (import D3D8/DDraw/Glide) but don't have the matching DLL
  deployed yet. It is read-only and changes nothing. Its result screen
  offers direct [7] dgVoodoo2 setup after the report.

  GPU COMPATIBILITY FIXES
  ------------------------

  Some games have extra settings for your graphics card (your GPU). The
  settings are different for AMD, NVIDIA and Intel.

  Mode 8 finds out which graphics card you have. Then it turns on the right
  fix for every registered game that has one.

  Games you add later are covered too. TeknoParrot's GameProfiles folder is
  scanned each time, so no script update is needed.

  To run it:

    1. Choose mode 8 from the main menu.
       (Or answer Y when it is offered at the end of a normal run.)

    2. Wait for the result screen.
       You will see: the result for each game, and a few choices:
       [D] Details, [O] Open support/log guidance, [R] Run GPU Fix again,
       [B] Back to main menu.

    3. Read the result before you do anything else.
       Next: press B to go back to the main menu.

  You can run it again after you change your graphics card or driver. But
  read the result first, before you start another run.

  If TeknoParrot Manager cannot tell which brand you have, it asks you.
  Pick AMD, NVIDIA or Intel only if you know which one is installed.
  If you are not sure, cancel.

  Before it changes a game, it makes a saved copy of that game's setup file
  and checks the copy. (TeknoParrot calls a game setup file a "profile".)

  If a saved path is missing or the drive is not connected:

    1. Reconnect the drive.
    2. Use mode 14 Library Health Check to repair the path.
    3. Try mode 8 again.

  If a write or a saved copy is reported as "unverified":

    1. Follow the recovery steps TeknoParrot Manager shows you.
    2. Keep its Details and the support log.
    3. Do not repeat the operation until that game's state is clear.

  A few older games do not work with one graphics card brand at all. This is
  confirmed for that brand, not just "no fix available". These games are
  flagged automatically in every run's compatibility check. That check is
  separate from this setup step.

  Library Health Check also lists the games that could use a GPU fix but do
  not have it yet. It only reports and never changes anything. At the end of
  its result screen it offers [8] GPU Fix setup.


  MORE DETAIL: GPU COMPATIBILITY FIXES
  ------------------------------------

  Where fixes come from: games carry optional per-vendor fix settings (AMD,
  NVIDIA, Intel) in their profiles. Mode 8 auto-detects your GPU and
  applies the correct fix to every registered game that has one. The
  GameProfiles folder is scanned at runtime, so newly added games are always
  covered automatically.

  Backups and results: TeknoParrot Manager creates and verifies a backup of
  each profile before writing. Result entries identify the actual profile
  processed. Totals are not assigned to games by position.

  If a profile write or backup is reported as unverified, preserve its
  Details and the support log. Do not repeat the operation until the
  affected profile's state is clear.


  FORCE FEEDBACK (FFB) SETUP
  ---------------------------

  What is force feedback?

    Force feedback makes a wheel or stick push back or rumble. It matches
    what is happening on screen: road bumps, gun recoil, crashes.

    Mode 9 sets this up in two separate ways. You can use one of them or
    both. They cover different games.

  Mechanism 1 -- FFB Blaster (native, requires a paid membership)

    FFB Blaster is TeknoParrot's own built-in force feedback. It ONLY works
    with an active, paid TeknoParrot membership:
      https://teknoparrot.com/en/Home/Subscription

    The script cannot check your membership. So it asks you before it
    changes anything.

    If you answer N, FFB Blaster is skipped. Turning it on without a
    membership has no effect.

    If you answer Y, the script looks through your TeknoParrot install's
    GameProfiles for games that have the FFB Blaster setting. It turns the
    setting on for every registered game that has it.

    First it makes a saved copy of TeknoParrot's saved game settings folder
    (UserProfiles), like every other change in this script.

    This is found at run time, not from a fixed list. So it keeps working
    as TeknoParrot adds support for more games.

  Mechanism 2 -- Third-party FFB plugin (free, no subscription needed)

    This is a free plugin made by someone else (mightymikem/FFBArcadePlugin).
    It adds force feedback to a different set of arcade racers and shooters.

    Every time you choose it, the script looks up the NEWEST release of the
    plugin on GitHub and tells you which one it is using (for example
    "Using FFB Arcade Plugin v.2.0.0.51"). The release ZIP is about 93 MB.
    It is downloaded once and saved in the cache folder. It is downloaded
    again only when a newer release comes out. Nothing is bundled with this
    script, so new games and new releases need no script update.

    Every supported game gets its own set of files in its game folder: the
    plugin (renamed to the file name that game loads), that game's own
    FFBPlugin.ini settings file, and SDL2.dll (only when the game does not
    already have one).

    Your wheel: before it installs anything, the script lists the game
    controllers Windows can see, by name: wheels, joysticks, gamepads, and
    Xbox and PlayStation controllers. Pick your wheel, or skip. Your pick
    is written into every settings file it installs. A controller with no
    USB numbers can be picked, but no wheel is written; the plugin is
    still installed and each game's rumble settings are left as the
    plugin ships them. To change the wheel later, run mode 8 again and
    pick another one. If no controller is found, you can go on without
    one and set the wheel later.

    You are asked first: the script shows which games it will install or
    update and waits for your yes. If you say no, nothing changes.

    Updates: run mode 8 again after a newer release. The script backs up and
    replaces only the plugin files it installed earlier and that you have
    not changed. If you changed a game's FFBPlugin.ini, it asks before
    touching it. The default is to keep your file.

    Which controllers work (from the plugin's own documentation):

      - Force feedback on wheels that support it (Thrustmaster and similar).
      - Rumble on Xbox/XInput-style controllers and similar pads.

    The plugin has its own window (its GUI, FFBPluginGUI.exe). It is not
    part of this script. It has a "Reverse Rumble" option if a controller's
    motors feel backwards.

    If a game works with BOTH ways, the script lists each such game once.
    Then it asks one question for all of them: keep FFB Blaster (native),
    or use the third-party plugin instead.

    Your answer covers every game in that list for this run.

    Native is the safe default. Only an explicit N picks the plugin. A
    blank or invalid answer keeps native.

    A game can need the same file name for ReShade and for this plugin.
    For example, H2Overdrive needs d3d9.dll for both. If any other file
    already has that name in a game's folder (ReShade's file, for example),
    the plugin setup skips that game and shows a warning. It never
    overwrites that file. The same is true for an FFBPlugin.ini that the
    script did not put there. The one exception is an old plugin file:
    the script recognizes it by its fingerprint (SHA-256), says so before
    it changes anything, backs it up, and replaces it. A file that does
    not match is never touched. A game's own SDL2.dll is never
    overwritten; the plugin just uses it.

    Missing saved paths and unavailable saved devices are reported on their
    own. They offer a direct jump to mode 14, Library Health Check.

  Removing FFB

    TeknoParrot Manager keeps a record of the plugin files it puts in a
    game's folder (the plugin, the settings file and SDL2.dll).

    Say you choose native FFB for a game that has both. It makes a saved
    copy, then removes only a plugin file that is still exactly as it left it.

    Files it did not put there, or files that changed, are left alone. They
    are reported so you can look at them if you want.

  MORE DETAIL: FORCE FEEDBACK (FFB) SETUP
  ---------------------------------------

  Native FFB Blaster failure rule: if the native FFB Blaster backup cannot
  be created or copied completely, or a native profile write fails, the
  native step stops as incomplete and the optional plugin is not offered. A
  later plugin result cannot mask that native failure.

  Native FFB Blaster details: it is detected at runtime, not hardcoded, so it
  keeps working as TeknoParrot adds support for more games. It is enabled on
  every registered profile that has the field. The UserProfiles are backed up
  first, same as every other destructive operation in this script.

  Choosing the plugin for overlaps: this creates a fresh verified profile
  backup and clears the native FFB Blaster fields for exactly those overlaps
  before any third-party DLL is deployed. If that switch cannot be verified,
  deployment is blocked.

  Plugin DLL collisions: a few games need the same destination DLL name for
  both ReShade and this plugin (for example H2Overdrive needs d3d9.dll for
  both). If ReShade already occupies that filename in a game's folder, FFB
  plugin setup skips that game with a warning rather than overwriting it.

  Plugin trust: the download is compared with the SHA-256 checksum that
  GitHub publishes for the release file, when GitHub publishes one. If it
  does not, the screen and the log say so, and the ZIP is still checked
  before use. A ZIP is refused, with no files changed, if any path in it
  points outside its own folder, if a needed game folder lacks dinput8.dll
  or FFBPlugin.ini, or if it unpacks to more than 1 GiB. Only the needed
  files are unpacked and nothing from the ZIP is run. The audit records the
  source, file name, release version and computed SHA-256. There is no
  publisher signature check. With no network, a saved copy that passed its
  check can be used if you agree; you are told it may not be the newest.
  Games that earlier versions gave only the old renamed plugin DLL are
  recognized from the record and upgraded with a backup.

  Reports: missing saved paths and unavailable saved devices are reported
  separately and offer a direct handoff to mode 14, Library Health Check.
  Unsupported/no-match games remain distinct from true deployment errors,
  even when the same run has path-limited games.

  Removing FFB: TeknoParrot Manager records its own third-party hook
  deployments. When you choose native FFB for an overlap, it backs up and
  removes only a matching unchanged file. Unowned or changed files remain
  untouched and are reported for advanced troubleshooting.


  BEPINEX SETUP
  ----------------------

  What is BepInEx?

    BepInEx is a free add-on (plugin/modding) system for Unity games, made
    by someone else. It is not part of TeknoParrot.

    A few TeknoParrot games need a community plugin that runs on top of
    BepInEx. The plugin gets their controls or fixes working.

    Mode 10 shows a list of known examples. The list is fetched live. It is
    checked against the eggmansworld.github.io compatibility data each time
    you open this mode. So it keeps up as new games are added.

  What mode 10 does

    Mode 10 is the BepInEx update and setup flow.

    It installs or updates BepInEx for the games you choose.
    Nothing happens until you approve it.

    The prompt is [Y] Install/update, [B] Back, [N] Cancel. It is skipped
    when the only games are ones you picked by number from the "do not
    have BepInEx" list, because picking them was your answer. There is no
    repair-reset choice. After a successful or no-change run, the screen
    waits for one Enter.

    TeknoParrot Manager picks the stable 64-bit (x64) or 32-bit (x86)
    package that matches each game's program file.

    Nothing is installed in every game behind your back. It stops if a game
    folder looks unsafe, if a saved copy fails, or if a file does not check
    out. If the network fails, the work stays marked incomplete. It then
    offers the automatic retry path. It never reports an update as done
    when it is not.

  Reading the result and recovering

    The result tells you which games were changed, which needed no change,
    which were skipped or protected, which have an unsupported or unreadable
    build type, which have a missing path, and which had errors.

    You will see choices on the result screen, including [D] Show details,
    [O] Open support/log guidance, [B] Back to main menu and
    [R] Try BepInEx setup again.
    Next: press D to find the game and the reason.

    If it says "Unsupported architecture":

      - It read the game's program file, but it is not a supported x86/x64
        build.
      - No files are changed for that game.
      - Check for a supported build of the game, or ask the game's maker.

    If it says "Unknown or unreadable architecture":

      - It could not reliably read what type of program the game uses.
      - Make sure the game's program file exists and you can open it.
      - Then try again.

    If a saved path is broken, use mode 14 Library Health Check first.

    If the network failed, try again once your connection is back.

    If a protected folder, a failed saved copy or an unsure cleanup is
    reported, stop. Look at it before you try again. Keep the Details and
    the support log.

    Do not manually delete BepInEx or staging files. TeknoParrot Manager
    keeps notes about what it did, so the game can be checked safely.

  Troubleshooting

    Official troubleshooting guide:
      https://docs.bepinex.dev/articles/user_guide/troubleshooting.html

    TeknoParrot Manager does not delete a BepInEx or plugin file that it did
    not put there. Files can be removed by an advanced troubleshooting path,
    but only after checks show they belong to the approved TeknoParrot
    Manager change.

  MORE DETAIL: BEPINEX SETUP
  --------------------------

  Package choice and promotion: TeknoParrot Manager chooses the stable x64 or
  x86 package matching each game's validated executable. It downloads only
  after the game root passes the approved-root and non-reparse checks,
  verifies the staged file set and backup, and uses rollback-safe promotion.

  Failure rule: unsafe roots, failed backups, extraction errors, digest
  failures, and rollback uncertainty fail closed. A network failure keeps the
  operation incomplete and offers the automatic retry path; it never reports
  an update as complete.

  Result wording: TeknoParrot Manager reports completed changes, no-change
  cases, skipped/protected games, unsupported or unreadable architecture,
  missing paths, and errors.

  Architecture: Unsupported architecture means TeknoParrot Manager read the
  executable but it is not a supported x86/x64 build. Unknown or unreadable
  architecture means it could not reliably read the executable architecture.

  Cleanup: a protected root, backup failure, or uncertain cleanup needs
  review before another attempt. TeknoParrot Manager preserves transaction
  information so the affected game can be reviewed safely.

  Ownership: TeknoParrot Manager does not delete an unowned BepInEx or hook
  file. An advanced troubleshooting path may remove files only after
  ownership and backup checks identify them as part of the approved
  TeknoParrot Manager transaction.

  Download audit: a BepInEx download audit entry records the GitHub release
  source, asset filename/version, computed SHA-256, and transfer metrics.
  When GitHub supplies an asset digest, TeknoParrot Manager validates it and
  fails closed on a mismatch. Without a digest, the computed SHA-256 is
  audit-only.


  REGION SETUP
  ------------

  Some games can start in a country you pick, like USA or Europe. It changes
  things like the language. Games left on Auto or Default usually start as
  Japan. Region setup sets that country for you. You do not have to open
  each game in TeknoParrotUI.

  You see it in two places:

    - After you register new games, TeknoParrot Manager asks once: "Which
      country do you want your games to start in?" Type the number of a
      country, or 0 to leave every game as it is. It does not ask in a
      preview or an unattended run.
    - At the main menu, choose 11) Region setup any time.

  How to use Region setup (mode 11):

    1. At "Enter 1-18:" type 11 and press Enter.

       You will see: a numbered list of countries. Each one shows how many of
       your games offer it, for example "1) USA (12 games)".

    2. Type the number of a country. Or type A for "Back to automatic" (the
       games go back to their normal setting). Or type 0 to go back and
       change nothing.

       You will see: "These games can be set to ..." and a list of games.
       Each one shows its current region, for example "(now: Auto)".

    3. Type A to take all of them, or L to pick some. With L, type game
       numbers to tick them, then D when you are done.

       You will see: how many games will change, how many stay as they are
       and how many already have it.

    4. Type Y to change them, or N to stop. N is the default.

       You will see: a restore point of your game settings is saved first.
       Then each game is changed and read back to check it.

    5. Read the result, for example "Region set to USA for 3 games." Type D
       for the game-by-game details, then press Enter to go back.

  What it will and will not do:

    - Only countries your games really offer are listed. A game never gets a
      region it does not have. A game that does not offer your choice stays
      as it is and is named under "Do not offer this region (stay as they
      are)".
    - A region you chose earlier is kept after a registration. It is only
      replaced when you change it yourself in Region setup.
    - Some games have only countries in their list (JAPAN, USA, EXPORT) and
      no automatic choice. The question after registration does not change
      them. In "Back to automatic" they are named as having no automatic
      choice, and they stay as they are.
    - It changes the game's Region setting. For games that have PcbRegion and
      DongleRegion instead, it changes both together.
    - It does not change a true/false export setting, or a region typed in
      as free text (about 6 games). Those stay as they are.
    - Online play still uses the automatic region. Region setup does not
      touch it.

  If a game could not be changed, the result says "Could not be changed". Your
  other games are still changed. To undo a change, use 15) Restore backup and
  pick the restore point saved just before it.


  POSTGRES SETUP
  --------------

  Which games need this?

    Some Incredible Technologies games need a small database program on
    your PC. The program is PostgreSQL 8.3. The games keep their game data
    in it.

    These games need it:

      - Golden Tee Live (2006-2023, 2025, 2026)
      - Golden Tee PGA Tour (2021-2023, 2025, 2026)
      - Power Putt Live (2012/2013)
      - Silver Strike Bowling Live
      - Target Toss Pro (Bags / Lawn Darts)
      - Orange County Choppers Pinball

    Mode 12 (Postgres setup in the main menu) finds out which of your
    registered games need it. There is no fixed list to keep up to date.
    A new game is covered as soon as you register it.

    If none of your registered games need it, mode 12 says so and stops
    straight away. It never installs anything you do not need.

    Newer TeknoParrot profiles of these games have a Storage box. A game
    set to Internal needs no PostgreSQL: start the game once and it makes
    its own database. Mode 12 skips these games and never says their
    database is missing. Only a game set to Existing PostgreSQL uses the
    steps below. Older profiles with no Storage box work as before.

  What mode 12 does

    If PostgreSQL is not installed yet, the script downloads and installs it
    in the background when a registered game needs it. You do not click
    through an installer.

    You will be asked for two passwords. One is for the PostgreSQL service
    account. One is for the database. Each is typed twice, and the letters
    are hidden as you type.

    You can stop at a password question by pressing Enter without typing
    anything. Nothing is changed or saved.

    Windows may ask for permission. TeknoParrot Manager asks Windows itself.
    Approve it, and the same setup carries on.

    Before the Windows permission window opens, TeknoParrot Manager shows
    what it will ask for and waits. You will see: "Press Enter to open the
    Windows permission window". Next: read the text, then press Enter.
    This pause is skipped in unattended runs and when no keyboard is
    available.

    If PostgreSQL is already installed, your existing data is kept.

    If the saved password no longer works, you will see that it did not work
    and a short menu. The menu has these choices:

      [F] Enter the existing PostgreSQL password (recommended).
          TeknoParrot Manager checks it and saves it. Nothing in
          PostgreSQL is changed.
      [X] I do not know the password. This explains why TeknoParrot
          Manager cannot reset the password for you and shows manual
          steps under Details (press D). Nothing is changed by
          choosing X.
      [C] Check the saved password again.
      [B] Back to main menu. Nothing is changed.

    [X] and [C] only appear when they make sense. X is offered only
    after PostgreSQL has clearly rejected a password. The default is F.
    Next: pick a letter, then follow what the screen says.

    If PostgreSQL could not be repaired or checked, the screen says "Action
    Required". It sends you to Details and support. Do that before you try
    again.

    TeknoParrot Manager never changes the postgres user's password. The
    password choices (F, P and X) never delete, recreate or restore over a
    database. Restoring a saved backup (mode 15) and Reinitialize ([I])
    do replace database content, but only after you confirm by typing YES.

  What you see when it finishes

    1. You will see a short result screen.
       It starts with "PostgreSQL setup finished."

    2. Next comes one line with three numbers:
       "Games set up: 3. Databases created: 1. Already set up: 2."
       (The numbers here are an example.)

    3. Then you will see one line for each group of games.
       Games with the same result share one line.

    4. The screen ends with this line:
       "Next: open TeknoParrot and start any game. Every game database
       was checked and is ready."

    5. Last, you will see "[D] Show details" and this question:
       "Press Enter to return to menu, or D for details"
       Press Enter to go back to the main menu. Press D to see more.

  What the game lines mean

    Ready:
      "Ready: <game>. The database was already there and was checked."
      "Ready: <game>. The database was created from the game's own backup
      and checked."
      TeknoParrot Manager connected to the database with the game's own
      settings and found its tables. Nothing was changed for a database
      that was already there.

    No starting database file:
      If the profile has "Automatically create Database" set to 1 (Golden
      Tee Live 2018 and newer, PGA Tour), setup still saves the
      connection settings and says "Profile ready". TeknoParrot makes the
      database the first time the game starts. For any other game, setup
      leaves the game out (nothing is created or changed for it), sets up
      the other games, and names it under "Could NOT be made ready". The
      run is shown as needing attention. Put the game's pg_backup folder
      back, then run setup again.

    If a database cannot be opened with the game's own settings, setup
    does not say Ready. It puts back what it changed and says which game
    and why under Details.

    Some games may keep their own PostgreSQL password or settings. Then you
    will see a yellow line like "1 game kept its own PostgreSQL password or
    settings, so TeknoParrot Manager did not change it." It ends with
    "Press D to see which." That line means the program left those games
    alone on purpose.

  What D shows (details)

    Press D on the result screen. You will see "Details". Then
    press Enter ("Press Enter to return to menu.") to go back to the menu.

    First comes a note that TeknoParrot Manager checked each database by
    connecting to it with the game's own settings. It did not start any game.

    Then come these blocks:

      - Summary
      - What setup checked
      - One block for each game: Database, Profile, What happened, and
        What it means
      - Other notes (shown when something does not belong to a single game)
      - What to do next
      - Totals: Games set up, Fields updated, Databases created, Profiles
        unchanged, and "Errors: <n> (see TeknoParrot-Manager.log)" if there
        were any

    Everything on the result screen is also written to the log
    (TeknoParrot-Manager.log), one line per item.

  If setup does not finish

    You will see "PostgreSQL setup did not complete successfully:" and a
    plain sentence about your data. For example: "Setup stopped.
    Everything was put back the way it was, and checked." or "PostgreSQL
    setup stopped before changing any databases or profiles." If
    TeknoParrot Manager could not check that your data is back as it was,
    it says so and tells you to ask for help before you try again. Then
    you will see "Press D to see why, or Enter to continue". Press D to
    see "Details" with the reason. The reason is also in the log.

    If a repair stopped part way, the screen says that some things may
    already have been changed and points you to View Log. It does not say
    that nothing was changed.

    If the PostgreSQL install itself fails, the screen tells you what is
    true:

      - If the Windows installer already ran: "PostgreSQL did not finish
        installing. Parts of it may now be on this PC. Your games and game
        settings were not changed." Then: "Next: open View Log, then
        choose PostgreSQL setup again. If setup then lists PostgreSQL
        items it found, read the warning on that screen before you delete
        anything."
      - If it stopped before the installer ran: "PostgreSQL was not
        installed. Nothing was changed."

    If setup then shows "These PostgreSQL items are already on this PC",
    it did not remove or change any of them. The list uses plain words.
    The registry paths, account IDs and service names are in the log, not
    on the screen. The screen warns: "Do not delete anything on this list
    unless you are sure what it is." A PostgreSQL folder can hold game
    databases and saved scores. Deleting it erases them for good. Copy the
    folder to a safe place first. If you are not sure, ask someone who
    knows computers before you delete or uninstall anything. A listed
    folder may hold your data. Copy it to a safe place before you delete
    it.

    If a rebuild ([I] Reinitialize) does not finish, you will see "The
    rebuild did not finish." and one plain sentence about your data. Then
    you will see "Press D for details, or Enter to continue".

  Password storage

    The database password is encrypted before it is saved to the config
    file. Only your Windows account on this PC can read it.

    The service-account password is never saved after the installation.

    TeknoParrotUI needs one password field in the game's saved setting file
    to be plain text. It needs this to connect when the game starts. So
    TeknoParrot Manager writes that field only after it has a checked saved
    copy. It skips games that already have the right value.

    The recovery copy can hold a game's earlier settings. Only you can open
    it. Do not share it.

  Where this comes from

    Full manual setup guide (if you would rather not automate this):
      https://github.com/Eggmansworld/tp-it-guides

  A note on trust

    The PostgreSQL 8.3 installer comes from the Eggmansworld/tp-it-guides
    GitHub release bundle.

    The installer is not digitally signed (Authenticode), and GitHub gives
    no checksum for it. So TeknoParrot Manager cannot prove who published
    it. It can do this for the ReShade installer.

    The download is recorded in the log: where it came from, the file name,
    and how it was fetched.

  MORE DETAIL: POSTGRES SETUP
  ---------------------------

  Setup flow in full: if PostgreSQL isn't installed yet, the script
  downloads and installs it silently when a registered game needs it. You
  choose a service-account password and a database password through masked
  confirmation prompts. If Windows permission is needed, TeknoParrot Manager
  asks Windows itself and continues the same setup after you approve it.

  Recovery in full: if PostgreSQL is already installed, TeknoParrot Manager
  preserves existing data. If the saved password no longer works, it
  explains the problem. If you know the password, choose F and type it.
  TeknoParrot Manager checks it and saves it. If nobody knows the password,
  choose X. X explains why an automatic reset is not available and shows
  manual recovery steps under Details. Nothing is changed by choosing X.

  Why there is no automatic reset: the old method added a "trust" line to
  PostgreSQL's pg_hba.conf file. If the window closed or the power went out
  at the wrong moment, that line could stay behind. Then any program on
  this PC could log in as postgres without a password. So TeknoParrot
  Manager no longer does it.

  Before TeknoParrot Manager changes any game database data, it creates and
  verifies a protected recovery backup. If recovery cannot verify the
  service or security policy, TeknoParrot Manager reports Action Required
  and directs you to Details and support before retrying.

  TeknoParrot Manager does not change the postgres password, edit
  pg_hba.conf or wipe existing PostgreSQL data on its own. The password
  choices (F, P and X) never drop, recreate or restore over a database.
  Two choices that you confirm yourself do replace database content:
  restoring a saved backup (mode 15) drops and recreates the selected
  databases from that backup, and Reinitialize ([I]) replaces the data
  with the game's own starting database.

  Profile updates: TeknoParrot Manager updates only affected profiles whose
  values are not already correct, in a deterministic order, and fails closed
  on any backup or write failure. Any backup failure is shown before profile
  writes.

  Backup failure diagnosis: TeknoParrot Manager captures the PostgreSQL
  client diagnostic and exit code, lists each affected game/database, and
  classifies the cause as connection, service, tool, permission, missing
  database, or unknown query failure. Details include the failed check and
  next action.

  Backup failure menu: when the database backup did not complete, the screen
  says "PostgreSQL setup stopped because the database backup did not
  complete." and "No PostgreSQL database or game-profile changes were made."
  If PostgreSQL itself was installed or rebuilt earlier in the same run, it
  says "Your games and game settings
  were not changed. PostgreSQL itself was installed or rebuilt earlier in
  this run." instead. It then offers these choices (prompt "Choice,
  default R"):

    [P] Enter and test a postgres password
    [X] I do not know the password (explains why there is no automatic reset)
    [R] Check the problem and try the safety backup again
    [I] Reinitialize PostgreSQL data for these games
    [D] Show details
    [O] Open logs/support guidance
    [B] Back to main menu

  [P] and [X] only appear when the problem is the password; [X] only when
  PostgreSQL clearly rejected the saved password. Read the screen before you
  choose [I]. It REPLACES the current data in each listed game database
  with the game's own starting database, and you must type YES in capital
  letters first. TeknoParrot Manager saves and checks a copy of the current
  data first. If that copy fails, that database is not changed.

  Details view: it shows the result summary, for example
  "PostgreSQL setup finished. Every game database was checked and is
  ready."

  The "What setup checked" block says setup connected to each game's
  database with the settings saved in that game's profile and counted
  its tables.

  Per-game blocks give "What happened" and "What it means".

  Database already existed: it was left untouched, and TeknoParrot Manager
  connected to it with the game's own settings and found its tables.

  Created from the game's own backup: TeknoParrot Manager connected to
  it with the game's own settings and found its tables. If the backup
  ended with known warnings, the details name the links between tables
  that could not be made.

  Kept passwords: when some games kept their own PostgreSQL password or
  settings, "Other notes" says "Kept the existing PostgreSQL password or
  connection settings in <n> profile(s) because replacing them was not
  approved:" followed by the profile names.

  What to do next (in the details): shown only when something went wrong.
  Fix the problem the details name, then run setup again.

  Automatic repair: the automatic PostgreSQL repair uses the same result
  screen, but with no "[D] Show details" line and no prompt. The
  log says which games kept their own settings.

  Password handling: the database password is encrypted using Windows DPAPI
  (tied to your Windows account and this PC) before being saved to the
  config file. The service-account password is never saved after
  installation.

  During PostgreSQL operations TeknoParrot Manager hands the password to the
  PostgreSQL tool through a temporary setting that exists only for that
  one tool run. It is put back to its old value straight afterwards. The
  password is never written to a credential file.

  The password is never printed or written to logs, summaries, command
  arguments, or test evidence.

  TeknoParrotUI requires the affected UserProfile Pass field in plaintext to
  connect at game launch, so TeknoParrot Manager writes that compatibility
  field only after a verified recovery backup and skips profiles already
  containing the approved value.

  Recovery evidence is ACL-locked to the current Windows identity and may
  contain the prior profile state for exact restoration; do not share it.

  Trust: the PostgreSQL 8.3 installer is distributed via the
  Eggmansworld/tp-it-guides GitHub release bundle. Its live download audit
  records the release source, filename/version when known, computed SHA-256,
  and transfer metrics.

  The installer itself is not Authenticode-signed and no GitHub asset digest
  is consumed for this package, so TeknoParrot Manager cannot independently
  verify publisher authenticity as it does for the ReShade installer.


  CHECK FOR UPDATES
  -----------------

  What mode 16 does

    Mode 16 checks GitHub for the newest TeknoParrot Manager release. It
    compares it with the version you are running.

    It never downloads or changes anything without your OK. A quiet check
    can also run at startup (it changes nothing). See "Automatic check at
    startup" below.

    If you are already up to date, it says so. Then you are back at the menu.

    If a newer version exists, it first explains what updating will do. Then
    it asks one Y/N question.

  Installing the update (RC8.1 and later)

    RC8.1 is the first version that can update itself in place. Builds
    before RC8.1 (for example RC8 or RC7) cannot. If you have one of those,
    install the newest release by hand once (see "To update by hand"
    below). After that, mode 16 does the work.

    When you say Y, TeknoParrot Manager does these things:

      1. Downloads the update and checks that it is the real file
         (SHA-256).

      2. Checks what is inside it.

      3. Backs up every file it replaces, in a new folder (never reused):
         UpdateBackups\TeknoParrotManager_<timestamp>\

      4. Installs the files and checks them.

    Then you start TeknoParrot Manager again yourself. It does not restart
    on its own. You see: "Update installed and verified. Restart
    TeknoParrot Manager to use it."

    It replaces only the program files that are different. It adds new
    files. It never deletes anything: your own files, UserProfiles and your
    backups are not touched, and older program files that the new release
    no longer has stay where they are.

    If any file cannot be replaced, every file is put back and nothing
    changes. If the drive is too full, you see "There is not enough free
    space for the update" and nothing is installed.

    tools\Invoke-TpmAutoUpdate.ps1 -Apply still refuses a release with
    many files and changes nothing.

    To update by hand (needed once if you run a build before RC8.1):

      1. Download the complete release ZIP from
         https://github.com/Jumpstile/teknoparrot-manager/releases

      2. Extract ALL of its files over your existing TeknoParrot Manager
         folder.

      3. Start TeknoParrot-Manager.bat again.

  If the release holds only the script

    When the release ZIP holds just TeknoParrot-Manager.ps1 at its root,
    the update does these steps for you:

      1. Download the release and check that it matches the published file
         (SHA-256)

      2. Check what the ZIP contains.

      3. Back up the current script to a new folder (never reused):
         UpdateBackups\TeknoParrotManager_<timestamp>\
         (a second backup in the same second gets _2, _3, ... added)
         Then validate the downloaded script before installing it

      4. Replace TeknoParrot-Manager.ps1 with the new version

      5. Require you to restart TeknoParrot Manager afterward

    You will see: the script closes when it is done.
    Next: start TeknoParrot Manager again.

  Read-only targets

    A script file can be marked "read-only". After you approve an update,
    TeknoParrot Manager may clear that mark on the target file for a moment.
    It puts the mark back after the attempt.

    The backup is made before anything is replaced. Any failure is
    reported clearly.

  After a successful update

    The script exits so you can start it fresh. It never keeps running the
    old, replaced code in the same session.

  If anything fails

    You see the exact error and whether a backup was made. The script goes
    back to the main menu. It does not exit.

  Standalone use outside the menu

    These are for advanced users:

    tools\Invoke-TpmAutoUpdate.ps1 -CheckOnly
    tools\Invoke-TpmAutoUpdate.ps1 -Apply

    See docs/AUTO_UPDATE.md (in the source repository) for the full
    design of this standalone helper.

  Automatic check at startup

    The script also checks for updates once, quietly, right when it starts,
    before it asks whether to use your saved settings.
    This is controlled by CheckForUpdatesOnStartup in
    TeknoParrot-Manager.config.json. The default is true.

    If you are up to date, nothing is shown.

    If a newer version exists, you will see the "Update Available" screen:
    the current and latest version, a short release summary and the
    "Updating will:" list of steps. Under the list are the choices:

      Y = Update now. It starts right away; there is no second question.
          It uses the same steps as mode 16.
      N = Remind me later. You go to the menu and are asked again next
          time.
      V = View release notes. You read them, then choose again.

    To turn this off, set CheckForUpdatesOnStartup to false in the config
    file. Then check by hand with mode 16.

    It never runs in -Unattended mode.

  MORE DETAIL: CHECK FOR UPDATES
  ------------------------------

  Version order: RC releases compare by numeric version, numeric RC number,
  then final release -- for example, v1.0-RC7 < v1.0-RC9 < 1.0.

  Source check before replacement: both updater paths parse candidate source
  without executing it. They accept exactly one bare, unwrapped, unscoped
  root $ScriptVersion = declaration with a constant-string value and at most
  one equivalent $ReleaseCandidateLabel declaration.

  Rejected: attributes/casts, parentheses, scoped or nested assignments,
  duplicate/destructured writes, compound assignments,
  increment/decrement, foreach targets, root parameters, data-statement
  variables, and member/index writes rooted at either identity.
  Function-local parameters do not count as root declarations.

  This finite AST check does not prove absence of indirect runtime mutation
  through commands, providers, [ref], .NET/session state, dynamic names,
  imports/dot-sourcing, aliases/splatting, or invoked scriptblocks. The main
  updater also reads the installed script identity back after replacement.

  Read-only targets: after you approve an update, TeknoParrot Manager may
  temporarily clear only the target file's read-only attribute, then
  restores it after the attempt. Backup creation still comes first and any
  failure is reported clearly.


  RETROBAT / BATOCERA
  -------------------

  RetroBat and Batocera only find TeknoParrot games if the game folder name
  ends with a certain suffix (a short ending on the name). The script
  supports all three:

    .teknoparrot   (most common -- used for new extractions)
    .parrot
    .game

  New games are always extracted into .teknoparrot folders.

  The other two endings are also recognized on folders you already have. So
  a library that another tool extracted earlier works without extracting
  again.

  ENABLING RETROBAT MODE

  You choose this once, in the first-time questions. This happens on a fresh
  setup (no saved config), or when you answer N to the saved-settings
  question.

  You will see:

      Folder naming mode
      This sets how new game folders are named. If unsure, press Enter (N).
      N = Standard style: GameName  (used by LaunchBox and most other
          frontends)
      Y = RetroBat/Batocera style: GameName.teknoparrot
      Use RetroBat folder naming? (Y/N, default N):

  Answer Y for RetroBat or Batocera. Your answer is saved.

  You are not asked again while you keep using your saved settings.

  To change the setting later:

    1. Start TeknoParrot Manager.
       You will see: "Use these settings? (Y/N, D = show them)"

    2. Press N. Nothing is deleted by this.
       Next: you get the first-time questions again, including the folder
       naming question.

    3. Choose the mode you want.

  (Press D at that question to look at your saved settings first.)

  WHAT CHANGES IN RETROBAT MODE

  AutoSync extraction. Games are extracted into folders named
  GameName.teknoparrot instead of GameName. For example:

      Standard mode:   E:\TeknoParrotGames\Daytona Championship USA (2017)[Sega]
      RetroBat mode:   E:\TeknoParrotGames\Daytona Championship USA (2017)[Sega].teknoparrot

  Registration. The ending is removed automatically before folder names are
  compared with TeknoParrot's game setup files (profiles). Registration,
  fuzzy matching, and the not-recognized folders list all work the same as in
  standard mode.

  Folders you already have. The script recognizes existing folders that end
  in .teknoparrot, .parrot or .game (or have no ending). It uses this when
  it decides whether to extract a game again. So changing mode part-way
  through a library does not cause duplicate extractions.

  UPGRADING AN EXISTING LIBRARY TO RETROBAT NAMING

  If you have already extracted games without suffixes and want to switch to
  RetroBat naming:

    1. Start TeknoParrot Manager. At "Use these settings?", press N.
       You will see: the first-time questions, including the RetroBat
       question.

    2. Answer Y to RetroBat mode.

    3. Look at your existing folder names and registration paths before you
       change the library. Keep your saved settings, extraction state and
       game backups.

    4. Do not delete syncstate to force a naming change. The existing
       folders may be kept as they are. If you need to rename a library that
       already has games, get a reviewed migration plan first.

  Note: the old folders are never deleted automatically. You can remove them
  by hand once you have confirmed that the new .teknoparrot folders work.

  MORE DETAIL: RETROBAT / BATOCERA
  --------------------------------

  Advanced: to change the setting later, decline the saved-settings prompt
  and choose the intended mode. Preserve the current configuration before
  any advanced manual edit; do not delete it merely to change one setting.

  The standard-mode prompt reads "Use RetroBat folder naming? (Y/N, default
  N)". Y means game folders are named GameName.teknoparrot instead of
  GameName.

  ALREADY HAVE GAMES SET UP? WHO DOES WHAT
  ----------------------------------------

  Can TeknoParrot Manager still help if your games are already unzipped
  and partly set up? Yes. You do not have to delete, move or reset
  anything first. Pick your TeknoParrot folder and the folder that holds
  your games, then choose Register only (2). It adds the games TeknoParrot
  does not know yet, and it asks before it fixes a broken game path. It
  does not delete your game folders.

  What does RetroBat mode change? Only the names of the folders
  TeknoParrot Manager unpacks: GameName.teknoparrot instead of GameName.
  It does not change RetroBat, its settings or its game list.

  Who does what:
    TeknoParrot Manager  Adds your games to TeknoParrot, copies controls
                         from a game you set up to games of the same type
                         (after you say yes, with a backup first), applies
                         the optional fixes you choose, names the folders.
    TeknoParrot          Runs the games. Keeps each game's controls and
                         input type (for example mouse and keyboard, a
                         controller or a lightgun). Has its own first-time
                         setup window.
    RetroBat             Keeps its own game list and starts games its own
                         way.

  Before you change any controls, check three things: the game shows up
  in TeknoParrotUI, it starts from TeknoParrotUI, and you set up one
  example game of that type yourself.

  Only a mouse and keyboard for now? TeknoParrot Manager does not set up
  mouse or keyboard input and does not test your devices. Set the controls
  for one game in TeknoParrotUI and choose its input type there (RawInput
  is the mouse and keyboard type). Start that game from TeknoParrot first.
  Then use Propagate Controls (4) to copy the setup to other games of the
  same type, and test one game before you trust the rest. Starting a game
  from TeknoParrot and starting it from RetroBat are two different ways to
  start it. TeknoParrot Manager does not change how RetroBat starts a game
  and cannot tell you why one way works and the other does not. If a game
  works in TeknoParrot but not from RetroBat, look at RetroBat's
  TeknoParrot settings or ask the RetroBat community.

  Later, with Sinden lightguns: TeknoParrot Manager does not detect or set
  up lightguns. That setup happens in TeknoParrot and in the gun's own
  software. The crosshair option (5) only copies crosshair pictures to
  lightgun games.

  THE FIRST-TIME QUESTIONS IN PLAIN WORDS
  ---------------------------------------

  TeknoParrot folder: the folder with TeknoParrotUi.exe. TeknoParrot
  Manager never installs TeknoParrot.
  ZIP source folder (AutoSync only): where your game ZIPs are. TeknoParrot
  Manager only reads from it.
  Games folder (also called the staging folder): AutoSync unpacks games
  here. For Register only, it is the parent folder of games you already
  unpacked. It must not overlap either program or any ZIP source folder.
  Eggman DAT (optional): a list of game names that helps match folders to
  games. It is not a game download.
  TeknoParrotUI's own first-time window: it belongs to TeknoParrot.
  TeknoParrot Manager does not open or finish it. Open TeknoParrotUI once
  yourself before you register.


-------------------------------------------------------------------------------
  THUMBNAIL DOWNLOAD
-------------------------------------------------------------------------------

  After registration the script offers to download game icons (small
  pictures that show in TeknoParrot's game list).

  You will see two lines first: "TeknoParrot Manager can download small
  pictures for your games. It never downloads the games." Then:

      Download the missing game pictures? (Y/N, D = use your own pictures)

  Answer Y to download. Answer N to skip. D explains the box-art icons and
  how to use your own pictures (the CustomThumbnails folder).

  If you answer Y, you will see "Downloading thumbnails from
  TeknoParrotUIThumbnails..." and then a summary.

  The script connects to the TeknoParrotUIThumbnails repository on GitHub.
  It downloads a <ProfileCode>.png for every registered game that does not
  already have one in <TeknoParrotRoot>\Icons\. That is the exact folder
  TeknoParrotUI reads when it shows game thumbnails.

  Source repository:
    https://github.com/teknogods/TeknoParrotUIThumbnails

  What it does:

    1. Copies any PNG files from the
       <TeknoParrotRoot>\TeknoParrotManager\Assets\CustomThumbnails\ folder
       into <TeknoParrotRoot>\Icons\ (see CUSTOM THUMBNAILS below).

    2. Checks every XML in your UserProfiles folder.

    3. For each profile code, checks whether <TeknoParrotRoot>\Icons\<Code>.png
       already exists. If it does, that game is counted as "already present"
       and skipped -- nothing is overwritten.

    4. Downloads each missing icon from the repository.

    5. Reports a summary: downloaded / already had one / no icon in the
       online pack / failed.

  The Icons folder is created automatically if it does not exist.

  Not every TeknoParrot game has an icon in the online pack yet. This does
  not mean those games are unsupported. It only means no artwork has been
  added for them yet.

  Games without a matching icon are skipped without an error. You can add
  your own icon in the folder
  <TeknoParrotRoot>\TeknoParrotManager\Assets\CustomThumbnails\ (see below).


  CUSTOM THUMBNAILS

  There are two ways to provide your own icons:

  Option A -- CustomThumbnails\ folder (recommended for most users):

    1. Create the folder
       <TeknoParrotRoot>\TeknoParrotManager\Assets\CustomThumbnails\
       under your TeknoParrot root.

    2. Drop your PNG files in there.
       Name each one <ProfileCode>.png (for example, Daytona3.png or
       HouseOfDead4.png).

    Next: every time you run the thumbnail download step, the script copies
    any PNG files from that folder into TeknoParrot's Icons folder. You never
    have to touch the TeknoParrot installation folder yourself.

    Files are only copied if the destination does not already exist. Your
    custom thumbnails are never overwritten by the GitHub download.

    Name check: before copying, each file name is checked against the
    registered profile codes. If a name does not match any registered game,
    the script shows a clear warning and skips that file.

    It is NOT copied until you fix the name. This catches typos before they
    cause silent failures. The warning tells you to check
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
      TeknoParrot-Manager-controls.txt in
      <TeknoParrotRoot>\TeknoParrotManager\Reports\.

      Open it. Every registered game is listed with its profile code. Copy
      the exact name from that file and add .png to get the thumbnail
      filename.

    Method 2 -- Icons folder:

      If you have downloaded thumbnails before, open TeknoParrot's Icons
      folder. The file names there ARE the profile codes. Match your own
      images to the same naming pattern.
      Typical location:  <TeknoParrotRoot>\Icons\

    Method 3 -- UserProfiles folder:

      TeknoParrot stores one .xml file per registered game in its
      UserProfiles folder. Each file is named  ProfileCode.xml. Remove
      the .xml ending to get the thumbnail filename.
      Typical location:  <TeknoParrotRoot>\UserProfiles\

    Examples:

      Display name                  Profile code      Thumbnail filename
      ----------------------------  ----------------  --------------------
      Daytona Championship USA      Daytona3          Daytona3.png
      House of the Dead 4           HouseOfTheDead4   HouseOfTheDead4.png
      Aliens Extermination          AliensExtermination  AliensExtermination.png
      Tekken 7                      Tekken7           Tekken7.png

  MORE DETAIL: THUMBNAIL DOWNLOAD
  -------------------------------

  The download uses TLS 1.2, which GitHub requires but which PS 5.1 may not
  negotiate by default. The script sets it automatically for this step.


-------------------------------------------------------------------------------
  "NO PROFILE MATCH" REPORT
-------------------------------------------------------------------------------

  Every game in TeknoParrot has a "game setup file" (called a profile).
  These files live in TeknoParrot's GameProfiles folder.

  After scanning your staging folder (the folder where your games are
  extracted) and registering, the script may show a message like this:

      1 game folder(s) not matched to a TeknoParrot profile --
      see the ACTION REQUIRED list saved below.

  It means TeknoParrot did not recognize that game folder. The folder was
  not registered.

  What to do:

  1. Update TeknoParrot to the newest version.

  2. Open TeknoParrotUI once, then close it.
     (TeknoParrot Manager does not update or open it for you.)

  3. Run Register only again.
     You will see: the folder is gone from the list if it now matches.
     Next: if it is still listed, read the reasons below.

  If a folder still does not match, it may be one of these:

    - a game TeknoParrot does not support
    - a game that uses an unusual executable (.exe) name
    - a utility or launcher that sits next to your games

  Where to find the list:

    - The ACTION REQUIRED section at the end of the run lists the folder
      names under GAME FOLDERS NOT MATCHED TO A TEKNOPARROT PROFILE.
    - The end-of-run summary says "1 game folder was not recognized by
      TeknoParrot." (or "N game folders were not recognized by
      TeknoParrot.").

  What this is NOT:

    - A game that shares an executable name with several game setup files.
      Those appear in "Register these games". You pick one in
      TeknoParrot Manager, or register it in TeknoParrotUI.

    - A game whose path is broken.
      Those appear in "Fix these game paths".

    - A game that is not extracted yet.
      Those appear under "EXTRACT THESE GAMES FIRST, THEN RE-RUN REPAIR".

  The not-recognized list is only for folders where no executable
  matched any game setup file at all.


  MORE DETAIL: NO PROFILE MATCH REPORT
  ------------------------------------

  If you have a dat file set up (a list of known game names), these folders
  are also tried against the dat by normalized name first. A fuzzy scan is
  used if needed. This happens before the folders reach this report, so the
  list is shorter when a dat is configured.


-------------------------------------------------------------------------------
  CONTROLS STATUS FILE
-------------------------------------------------------------------------------

  After every real run the script writes a small report file. It is named
  TeknoParrot-Manager-controls.txt. You will find it in:

    <TeknoParrotRoot>\TeknoParrotManager\Reports\

  <TeknoParrotRoot> means your TeknoParrot folder.

  The report shows the controls of every registered game, as they are right
  now. Here is an example:

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

  Each game line shows:

    - The control family: the kind of controls the game uses
      (button, driving, lightgun, trackball, analog, spinner).

    - How many buttons are set up, out of the total for that game.
      "52/52 bound" means all 52 buttons are set up.

    - The status (see the list below).

    - For "propagated" games, which reference game the controls were copied
      from.

    - Any buttons that are still left for you to set up by hand ("manual").

  The status can be one of these:

    REFERENCE           Your set-up example game.
    propagated          Controls were copied from a reference game.
    already bound       The game had controls before this run.
    bound               Set up, but not by copying.
    partial             Some buttons are set up, but too few.
    no controls         Nothing is set up yet.
    no reference game   Waiting for you to set up one example game.

  Good to know:

    - The file is replaced on every real run. A preview run does not touch
      it, so you still see the file from the run before.

    - It is useful when a game aims wrong days or weeks later. Open the file
      and you can see at once whether controls were copied, and from which
      reference game. You do not need to run the script again.

  MORE DETAIL: CONTROLS STATUS FILE
  ---------------------------------

  The file shows how many buttons are bound out of the total in the game's
  profile (its game setup file).

  The "partial" status means some buttons are bound, but fewer than the
  threshold.

  The file reflects the state of your UserProfiles (TeknoParrot's saved game
  settings folder) at the moment the script completed. It does this whether
  propagation (copying controls) was run or skipped this time.


-------------------------------------------------------------------------------
  PER-GAME OVERRIDES
-------------------------------------------------------------------------------

  Most people never need this section. You can skip it.

  The file TeknoParrot-Manager.overrides.json lets you give special
  instructions for single games. The script creates it empty, next to the
  script, the first time it runs.

  To use it:

  1. Open TeknoParrot-Manager.overrides.json in any text editor.
     (Notepad works.)

  2. Add only the keys you need. Every key is optional.

  3. Save the file.
     Next: run the script. It reads the file on the next run.

  Bad or missing entries are ignored safely. Leave any key empty, or leave
  it out, if you do not need it.

  What each key does:

    noSync          Games to always skip when extracting, even when you
                    extract all games.
                    Example: "noSync": ["ZipBaseName1"]

    onlySync        A short list of the only games to extract. If this list
                    is not empty, ONLY these ZIPs are extracted.
                    For normal use, the picker menu is easier.

    noPropagate     Games that must be left alone when controls are copied.

    forceArchetype  Copy a game's controls from one specific reference game.
                    Use it when the script picks the wrong example game.

    familyOverride  Tell the script which kind of controls a game uses.
                    Use it when the script gets the kind wrong.
                    Example: FamilyGuyBowling looks like a lightgun game,
                    but it should use trackball controls.

    canonicalArchetype
                    Say which reference game is the correct one for a kind
                    of controls. Only needed in a rare case (see More detail
                    below).

    datFile         The full path to a dat file (a list of known game names).
                    Use it if the path you gave at first setup is wrong.
                    Leave it out if you do not have a dat file.

  About ZIP base names: these are the ZIP file names without the .zip
  ending, exactly as they appear in your source folder.

  MORE DETAIL: PER-GAME OVERRIDES
  -------------------------------

  Here is a full example of the file. All keys are optional:

    {
      "noSync":             ["ZipBaseName1", "ZipBaseName2"],
      "onlySync":           ["ZipBaseName1", "ZipBaseName2"],
      "noPropagate":        ["ProfileCode1", "ProfileCode2"],
      "forceArchetype":     { "ProfileCode": "ReferenceProfileCode" },
      "familyOverride":     { "ProfileCode": "trackball" },
      "canonicalArchetype": { "button": "ReferenceProfileCode" },
      "datFile":            "C:\\full\\path\\to\\collection.dat"
    }

  A "profile code" is the UserProfile file name without .xml.

  noSync          ZIP base names (file name without .zip) to always skip
                  during extraction, even when extracting all games.

  onlySync        Whitelist. If this list is non-empty, ONLY these ZIPs are
                  extracted. This bypasses the interactive selection menu
                  and is useful for scripted or repeatable runs. For casual
                  use, the interactive picker is easier.

  noPropagate     Profile codes (UserProfile file name without .xml) to
                  leave untouched during control propagation.

  forceArchetype  Pin a game to copy its controls from a specific reference
                  game instead of the automatic best match. Useful when the
                  script picks the wrong game type for an unusual title.
                  Format: { "GameProfileCode": "ReferenceProfileCode" }

  familyOverride  Override the auto-detected control family for a game.
                  Use this when the script mis-classifies a title (for
                  example, FamilyGuyBowling is detected as a lightgun game
                  because of its input mappings, but it should draw
                  controls from the trackball pool).
                  Valid values: "button", "driving", "lightgun",
                                "trackball", "analog", "spinner"
                  NOTE: "spinner" is never auto-detected. Spinner games
                  must always be assigned explicitly via familyOverride.
                  The override also counts for the games controls are
                  copied from. So a game set to "spinner" finds a
                  reference game instead of "no usable reference game".
                  Format: { "GameProfileCode": "trackball" }

  canonicalArchetype
                  A reference game (one with enough controls already bound
                  to copy from) is normally never modified -- not its
                  bindings, and not its Input API. If two reference games
                  in the same control family end up on different Input APIs
                  (for example one set up with an XInput pad, another with
                  an arcade encoder), the script has no reliable signal for
                  which one is actually correct, so by default both are
                  left alone.

                  If you know which one is right, name it here as the
                  canonical archetype for that family. On the next control
                  propagation run, every OTHER reference game in that
                  family gets its Input API corrected to match -- bindings
                  are still never touched, only the Input API field.

                  Leave a family unset to keep the old behavior (no
                  reference game in that family is ever modified).
                  Format: { "button": "ReferenceProfileCode" }
                  Valid family names: same six as familyOverride above.

  datFile         Full path to a No-Intro TeknoParrot dat file (for example
                  the Eggman/RomVault collection dat). Used instead of the
                  dat path entered during initial setup. If an Eggman DAT
                  ZIP is set up, the ZIP is used and this file is ignored.

                  When set, the script reads the dat's <GameProfile> and
                  <Executable> fields and uses them to auto-register games
                  in three cases: shared executables, exe-less-matched
                  folders, and slightly misnamed folders (fuzzy fallback).
                  The dat is loaded once before the main menu loop and
                  reused each run.

                  Leave this key empty or omit it entirely to use the path
                  from setup (config.json), or if you do not have a dat
                  file.
                  Format: "C:\\path\\to\\TeknoParrot Collection.dat"


-------------------------------------------------------------------------------
  ACTION REQUIRED SUMMARY
-------------------------------------------------------------------------------

  At the end of every run, the script prints an ACTION REQUIRED section. It
  lists everything that needs your attention.

  It has up to twelve parts. A part with nothing in it is left out.

  Here is what each part means, in plain words:

    TEKNOPARROT'S OWN FIRST-TIME SETUP
                              Shown once when TeknoParrot's own setup is
                              not finished, or when TeknoParrot Manager
                              cannot tell. It gives the path to
                              TeknoParrotUi.exe and the steps left: choose
                              the DAT file, let it scan for games, and set
                              up controls.

    GAME FOLDERS NOT MATCHED TO A TEKNOPARROT PROFILE
                              (not registered)
                              Game folders that TeknoParrot did not
                              recognize, so they were not registered.
                              Next: update TeknoParrot, open TeknoParrotUI
                              once, then run Register only again. See the
                              full section above.

    REGISTER THESE GAMES IN TEKNOPARROTUI
                              Games found on disk that could not be
                              registered automatically. Their executable
                              is shared, or their game setup file was
                              already taken.

                              TeknoParrot Manager shows you a list of
                              choices it has checked. Pick one yourself.
                              Press Enter to skip a game. It stays here,
                              so you can use TeknoParrotUI instead. The
                              script never guesses.

    FIX THESE GAME PATHS IN TEKNOPARROTUI
                              Games with a broken path that could not be
                              fixed automatically, because the executable
                              is shared by several game folders. It shows
                              which games need fixing and which executable
                              to look for, in groups to keep it short.

    EXTRACT THESE GAMES FIRST, THEN RE-RUN REPAIR
                              Games with a broken path because they are
                              not extracted to your staging folder yet.
                              Nothing to do right now.
                              Next: extract the game, then run again and answer Y to repair.

    CONTROLS SKIPPED BY DESIGN (informational; not a failed save)
                              Games whose kind of controls has no usable
                              example game. The screen says: "Skipped by
                              design: no usable reference game for the
                              '<family>' family. Add one game of this
                              family with your own controls, then run
                              this again."

    CONTROLS NOT READY : <game code>
                              Registered games whose controls are Missing,
                              Not verified, Unsupported, or Unknown.
                              Registering and launching a game do NOT
                              prove its controls work.
                              Next: open TeknoParrot's controls setup,
                              then set up and test them.

    PATH TOO LONG -- THESE GAMES MAY FAIL TO LAUNCH
                              Some games (Raw Thrills titles, Yu-Gi-Oh!
                              Duel Terminal 6) may not start if their
                              folder path is too long. It shows the exact
                              short folder name to rename it to.

    FILE VERSION MISMATCH -- THESE GAMES NEED A SPECIFIC OLDER FILE
                              Some games need an OLDER, specific version
                              of one file, not the newest one: the
                              BlazBlue-series games (iDmacDrv32.dll) and
                              Tekken Tag Tournament 2 (EBOOT.BIN).
                              It shows the file name, the current and
                              needed CRC32, and where to get it.

    KNOWN <AMD or INTEL> GPU INCOMPATIBILITY -- NO FIX AVAILABLE
                              (information only)
                              Games known NOT to work on your graphics
                              card brand (AMD or Intel). NVIDIA has no
                              known-broken titles in this data.
                              This is information only. There is no fix.
                              It saves you troubleshooting time.

    <EMULATOR NAME> FIRMWARE NOT INSTALLED
                              Games whose emulator (PCSX2x6, Chihiro/
                              CxbxR, PlayStation 3/RPCS3, Play!) needs
                              startup files that TeknoParrot does not
                              provide. It says which games will not start
                              and gives one next step. If the files are in
                              your own collection, it offers to copy them
                              after checking them against the DAT list.
                              If it cannot find them, it asks once for
                              your Supplementary folder and remembers it.
                              One Y then installs everything it found and
                              checked. The result names what was installed,
                              already matching, missing (by file name) or
                              invalid, and the folders searched.
                              TeknoParrot Manager never downloads, links
                              to, or shares these files.

    <EMULATOR NAME> EMULATOR COMPONENT NOT FOUND
                              A required emulator part is missing from
                              where it should be. Use the normal
                              TeknoParrot install or update process.
                              TeknoParrot Manager does not repair,
                              download, reinstall, or change TeknoParrot.

  The setup notes are not a part of this list. The report ends with the
  line "Additional informational game notes were written separately to:"
  and the path of TeknoParrot-Manager-game-notes.txt. The notes come
  from the community compatibility database
  (eggmansworld.github.io/TeknoParrot). They can be workarounds, known
  quirks, setup steps (such as which ZIP or disc file to select),
  graphics card notes, extra files, the extra archives a game needs (use
  your own copy; none is downloaded), a linked profile (the same game
  with another setup) and a game the guide lists as broken or only
  partly working. Information only: nothing in the file is applied for
  you.

  The checks run on their own on every AutoSync/Register run. You do not
  need to choose a special mode.

  Where the list is also saved:

  - When a registration run has action items, the same list is saved to a
    text file. It is named TeknoParrot-Manager-ActionItems.txt. By default
    it goes in <TeknoParrotRoot>\TeknoParrotManager\Reports\ .

  - A Save dialog lets you pick a different place or file name.

  - The script tells you the path when it writes the file.

  - In unattended runs and in preview/dry-run mode, there is no dialog. The
    file goes to the default path.

  MORE DETAIL: ACTION REQUIRED SUMMARY
  ------------------------------------

  Register these games: the list of candidates is validated, and the choice
  is explicit and made inside the product. A case you leave unresolved
  keeps the TeknoParrotUI fallback instead of being guessed.

  Controls not ready: the controls are catalog-backed (checked against the
  controls catalog). The statuses are Missing, Not verified, Unsupported,
  or Unknown.

  Path too long: the limit is hard-coded and specific to the game engine.

  File version mismatch: the file names are iDmacDrv32.dll for the
  BlazBlue-series games and EBOOT.BIN for Tekken Tag Tournament 2. The
  report shows the current and required CRC32 values.

  Firmware not installed: the screen says in plain words which games will
  not start and gives one next step; the exact files and folders are under
  Details and in the log. The check is existence only. If the files are in
  your own collection (the "[EMU]" archive of the Supplementary set, or
  another TeknoParrot copy), TeknoParrot Manager offers to copy them after
  checking every file against the Eggman DAT (size and every listed hash).
  It saves a backup copy first and never replaces a different file without
  asking. It never downloads, links, or redistributes these files.

  For RPCS3 games, the files come from the PlayStation 3 firmware file in
  your own collection (the "[EMU] Sony PlayStation 3 Firmware" ZIP). RPCS3
  itself unpacks it, with no window. For Play! games, TeknoParrot Manager
  checks that each game has its own small settings file (.arcadedef) and
  copies it from the "[EMU] Play! working arcadedefs" ZIP.

  Emulator component not found: the component is contract-backed (it is
  required by a data contract). The report shows the contract/detector
  evidence and the affected profiles. TeknoParrot Manager does not
  diagnose why the component is missing.

  Setup notes: they are not an ACTION REQUIRED part. The notes come from
  the community compatibility database. The report writes the expected
  executable and sanitized notes to TeknoParrot-Manager-game-notes.txt,
  a separate file. The ACTION REQUIRED report only ends with a line that
  gives the path of that file. Informational only.
  If setup notes exist, the sanitized notes report is written separately,
  even when there are no ACTION REQUIRED items. Raw imported notes are
  never copied into the ActionItems report.

  Automatic checks: the compatibility, firmware, emulator-component,
  controls-readiness, and setup-notes checks run automatically on every
  AutoSync/Register run -- no separate mode is needed.

  The GPU check silently skips if your GPU vendor cannot be auto-detected.
  It never prompts mid-run.

  The setup notes check needs a live fetch of that site's data. It is
  skipped (with nothing shown) if the fetch fails. It never blocks the rest
  of the run.

  ActionItems file: unattended runs skip the Save dialog and save to the
  default path. A preview run saves nothing, so it never replaces the list
  from your last real run.


-------------------------------------------------------------------------------
  UNATTENDED / SCHEDULED MODE
-------------------------------------------------------------------------------

  Unattended mode runs the script without asking you any questions. In this
  release it does one job only: the read-only Library Health Check. It
  does not extract games, register them, copy controls or download
  thumbnails, so it cannot run AutoSync or Register only on a schedule.
  Most people can skip this section.

  To use it:

    Step 1.  Run the script once the normal way, so your settings are
             saved.

    Step 2.  Add "UnattendedMode": "HealthCheck" to the saved settings
             file, TeknoParrot-Manager.config.json, in
             <TeknoParrotRoot>\TeknoParrotManager\State\. An ordinary save
             from the menus keeps this value.

    Step 3.  Start it with this command:

                 .\TeknoParrot-Manager.ps1 -Unattended

  What it does by itself:

    - Loads your saved settings from TeknoParrot-Manager.config.json.
    - Runs the Library Health Check and writes the result to
      TeknoParrot-Manager.log. It changes nothing.
    - Never prompts and never starts a repair or setup.

  What it does NOT do:

    - It does not run without saved settings. It stops cleanly with an
      error. Run the script once the normal way first.

    - It does not run without a valid TeknoParrot root folder. It stops
      cleanly.

    - It does not run without "UnattendedMode": "HealthCheck". It prints
      "[Unattended] Mode must be set before starting." and exits with
      code 1. Any other value is ignored in the same way.

    - It does not run Restore mode. A restore needs you to pick a backup.
      Use the normal way for that.

  Exit codes: 0 means the check finished, even if it found problems in
  your library. 2 means some checks could not finish. 1 means no mode was
  set.

  VALIDATION REPORT (FOR RELEASE AND TEST PCs)

  To check a copy without any questions, run:

      .\TeknoParrot-Manager.ps1 -ValidationReport -ValidationRoot "D:\TeknoParrot" -ValidationJsonPath "D:\report.json"

  It prints the version and script checksum, the PowerShell and Windows
  versions, your TeknoParrot folder and saved settings (the saved
  PostgreSQL password is only shown as yes or no), how many games are
  registered, which games still need PostgreSQL settings, how many profiles
  support, do not support or do not say whether they support RawInput and
  RawInputTrackball, the files that ship with TeknoParrot Manager and the
  compatibility warnings. -ValidationRoot is optional when your settings
  are saved. -ValidationJsonPath is optional and is the only file it
  writes. It never changes TeknoParrot, your game profiles, your saved
  settings or the log.

  Exit codes: 0 pass, 3 action required, 4 failed (for example no
  TeknoParrot folder), 1 the report could not be made.

  CHECK AN OUTSIDE CONTROLLER LIST (ADVANCED)

  If you already have a controller list from somewhere else (for example
  RetroBat's teknoparrot.yml), you can compare it with your game setup
  files. Run:

      .\TeknoParrot-Manager.ps1 -MappingEvidenceFile "D:\teknoparrot.yml" -ValidationRoot "D:\TeknoParrot" -ValidationJsonPath "D:\details.json"

  -ValidationRoot is your TeknoParrot folder. -ValidationJsonPath is
  optional. It is the only file this check writes.

  It prints plain counts: how many games the list names, how many are in
  your TeknoParrot, how many are ready for a person to review, and how
  many are held back. A game is held back with a plain reason: the game
  is not in your TeknoParrot, the list names the game twice, the list sets
  one control twice, the list sets a control the game does not have, the
  list uses a button name that is not known, or two game actions share one
  controller button. Five known spelling mistakes in such lists are
  corrected and counted. The same inputs always give the same details file.

  This check only reads. It does not change any game setup file, and it
  does not trust, apply or ship the list.

  SCHEDULING WITH WINDOWS TASK SCHEDULER

  To run the Health Check automatically, follow these steps.

  Step 1.  Run the script once the normal way and save your settings.

  Step 2.  Open Task Scheduler (taskschd.msc).

  Step 3.  Create Task (not Basic Task). On the General tab:
             - Name: TeknoParrot Health Check
             - Run whether user is logged on or not (if you want it
               headless, meaning with no window)
             - Run with highest privileges

  Step 4.  Triggers tab: New -> On a schedule, set your preferred time.

  Step 5.  Actions tab: New -> Start a program.
             Program: powershell.exe
             Arguments: -ExecutionPolicy Bypass -NonInteractive -File
               "<Scripts folder>\TeknoParrot-Manager.ps1"
               -Unattended
             (adjust the path to match your Scripts folder)

  Step 6.  Conditions tab: if your games are on a network drive, you can
           check "Start only if the following network connection is
           available" and select that connection.

  After each scheduled run, open TeknoParrot-Manager.log for a summary.
  To extract or register games, run the script yourself from the menu.

  MORE DETAIL: UNATTENDED / SCHEDULED MODE
  ----------------------------------------

  With saved settings, an unattended start prints "TeknoParrot Manager found
  your saved settings." and then "[Unattended] Using saved settings." It
  does not ask the "Use these settings? (Y/N, D = show them)" question. It
  also prints the "Configuration:" list of your saved settings.

  Without saved settings it exits with: ERROR: Unattended mode requires
  saved settings.

  An unattended run always keeps TeknoParrot's own screen settings (it does
  not offer to turn off TeknoParrot's own CRT effect).


-------------------------------------------------------------------------------
  GAME REPAIR
-------------------------------------------------------------------------------

  After registration, the script offers to repair broken game paths.

  A game path is the place where TeknoParrot looks for the game's .exe file.
  It is broken if it is empty, or points to a file that no longer exists.
  This can happen after you move or re-extract a game.

  Repair looks for the game by its executable name in your staging folder.
  Then it updates the path.

  Repair shows one of these results for each game:

    Fixed                The path was re-pointed to the correct executable.

    Not yet extracted    The game is not extracted to the staging folder
                         yet.
                         Next: extract it first, then run again and answer Y to repair.

    Register manually    The executable is shared by several games.
                         TeknoParrot Manager shows you choices it has
                         checked. Pick one yourself. If you press Enter,
                         the game stays in ACTION REQUIRED, so you can use
                         TeknoParrotUI. It never guesses.

  Games whose path already works are left untouched.


-------------------------------------------------------------------------------
  CONTROLLERS AND INPUT NOTES
-------------------------------------------------------------------------------

  - Input method. Most games can be bound using XInput, RawInput or
    DirectInput. These are the different ways a game can talk to your
    controller. You choose one per game in the TeknoParrot UI when you set
    up your reference game. The script copies whatever you chose.

  - Keyboard. With no controller, set up the keyboard in TeknoParrot's
    controller setup. Then use a keyboard game as the reference for similar
    games.

  - Negative pedals. Some racing games expect a pedal on a negative axis
    (for example Y- or Z-). Set it up that way in your reference game. The
    script carries the setting across.

  - Unsupported controllers. If a pad is not recognized, wrappers such as
    DS4Windows or XInputPlus can make it appear as an XInput device. These
    run outside this script.

  - Light guns. A gun such as the Sinden shows up in Windows as a pointer.
    It is bound in RawInput mode. Set it up on your lightgun reference game
    and the controls are copied. Gun calibration lives in the gun's own
    software.


-------------------------------------------------------------------------------
  SAFETY, BACKUP AND LOG
-------------------------------------------------------------------------------

  What keeps your games safe:

    - Before it extracts anything, AutoSync saves a copy of your game
      settings.

    - Every run writes a log file, so you can see what happened.

    - You can go back to a saved copy with Restore backup.

  Many result screens also let you press D for Details. That shows the
  full technical information. The same information is also kept in the log.

  What the backup covers:

    - The normal backup covers UserProfiles only. That is TeknoParrot's
      saved game settings folder.

    - Game-side NVRAM, test-menu state, and calibration files outside
      UserProfiles need separate backups (issue 378).

    - This is not a full game backup.

  Backup

  Before extraction, AutoSync saves a copy of UserProfiles. The copy is
  marked with the date and time and goes in:

    <TeknoParrot>\UserProfiles\FullBackup\<label>_<date_time>_<id>\

  Notes:

    - Preview mode skips the backup.

    - If the folder cannot be created, or the copy cannot be finished,
      AutoSync does not begin extraction.

  To restore a saved copy:

  1. At the main menu, type 15 and press Enter. That is "Restore backup".
     You will see: the "Restore from Backup" screen with options 1 to 5,
     plus B to go back.

  2. Type 1 and press Enter to choose TeknoParrot UserProfiles backups.
     You will see: "Saved copies of your game settings, newest first:". The newest
     copy is at the top of the list. Each one has a number.

  3. Type the number of the copy you want and press Enter.
     Next: you are asked to confirm before anything is changed.

  4. To cancel, press Enter on its own.
     You will see: "Restore canceled." Nothing is changed.

  If you type a wrong number, you are asked again.

  The other options on the first screen are listed the same way, newest
  first:

    - 2 is the Postgres database backups.
    - 3 is the LaunchBox library backups.
    - 4 is "Reset and Restore". It lists "Restore points, newest first".

  The confirmation checks still apply before files or databases are
  changed.

  Log

  Every run adds to this log file:

    <TeknoParrotRoot>\TeknoParrotManager\Logs\TeknoParrot-Manager.log

  It records what was extracted, registered, repaired and propagated
  (copied controls). It also records any errors.

  If the log file cannot be written (permissions, a full disk, or a path
  problem), the script does not fail silently:

    - It prints a one-time warning on the screen. It shows the log path
      and the exact error, so you can find the cause.

    - Every later entry that cannot be written is also shown on the screen.
      It starts with [UNLOGGED], so nothing is lost during the run even
      though the file is not available.

  The script carries on normally in both cases.

  MORE DETAIL: SAFETY, BACKUP AND LOG
  -----------------------------------

  Where things live. ProgramFolder means the folder containing
  TeknoParrot-Manager.ps1. The normal configuration and log use
  TeknoParrotManager\State and Logs under your TeknoParrot root. Startup
  previews its safe, known-item migration.

  These active items stay in ProgramFolder for the current consumers:

    TeknoParrot-Manager.overrides.json
    BepInExCache\

  LaunchBoxBackups\ and PostgresBackups\ are used from
  TeknoParrotManager\Backups\ unless an older folder of the same name
  already exists in ProgramFolder.

  PostgresRecoveryBackups\ (private recovery evidence) is the one backup
  folder that is moved. At startup it goes to
  TeknoParrotManager\Backups\PostgresRecoveryBackups\ through a protected
  copy. Each backup folder is handled on its own: if a managed copy and an
  older copy beside the script both exist, TeknoParrot Manager stops,
  merges nothing, deletes nothing, and asks you to keep both.

  Copies moved by an earlier version are not automatically adopted.
  Preserve all copies and the migration report for reviewed recovery. Do
  not merge or delete them merely to clear a warning.

  Backups, database moves and saved proof files also work on PCs whose
  folders use older-style permissions. If one of these steps still fails,
  the log says what caused it.

  Advanced emergency recovery only: the normal Restore backup flow (main
  menu 15) keeps the selected backup, asks you to close TeknoParrot, and
  verifies the restore. Do not copy profile files manually unless the guided
  path is unavailable.

  Log start-up. Until the TeknoParrot folder is known, each launch writes
  its first lines to TeknoParrot-Manager.log beside the script. Once the
  managed log exists, startup appends them to it after a read-back check
  and removes the script-folder copy.

  An empty script-folder log is simply removed. Any other script-folder log
  that is not plain TeknoParrot Manager log text of at most 1 MiB is kept
  unchanged in the Logs folder as
  TeknoParrot-Manager.<date-time>-<id>.legacy.log.

  Download audit. The log also records an audit entry for every
  live-fetched artifact: authoritative source URL, filename, version when
  known, computed SHA-256, and transfer metrics (method, size, elapsed
  time, average speed).

  ReShade additionally records installer Authenticode signer/subject,
  status, thumbprint, and final trust result. Its SHA-256 is an audit hash,
  not a published-digest comparison.

  BepInEx records its GitHub release source, filename/version, SHA-256, and
  validates the GitHub asset digest when available, failing closed on
  mismatch. dgVoodoo2 uses the same digest validation when available.

  Both TeknoParrot Manager updaters require GitHub's release-asset SHA-256
  digest before opening the downloaded ZIP or changing the installed
  script. A missing, invalid or mismatched digest stops installation and
  removes the rejected download. Download the complete ZIP manually from
  https://github.com/Jumpstile/teknoparrot-manager/releases if verification
  is unavailable. This detects mismatch with GitHub's asset, not a
  compromised publisher.

  FFBArcadePlugin, Eggman dat, PostgreSQL and thumbnail downloads retain
  source/hash/transfer audit entries without an authenticity claim.


-------------------------------------------------------------------------------
  RE-RUNNING
-------------------------------------------------------------------------------

  You can run the script as often as you like. Each run does this:

    - A real AutoSync run saves a copy of UserProfiles before extraction.
      Preview mode skips the copy.

    - AutoSync then extracts and registers new games.

    - It leaves games whose ZIP did not change alone.

    - It leaves your existing button settings alone.

  Before you try again, read the ACTION REQUIRED section.


-------------------------------------------------------------------------------
  RESETTING
-------------------------------------------------------------------------------

  Saved settings      At the start, the script asks:
                      "Use these settings? (Y/N, D = show them)".
                      Type D to see what is saved. Type N to enter the
                      folders again. Before an advanced reset, keep a
                      copy of the existing config file.

  Extraction repair   First review Details, the source identity and the
                      retained state. Keep your backups. Removing
                      syncstate or a marker does not prove that
                      re-extraction is safe or needed.

  Correct one game    Keep its UserProfile. Confirm the correct official
                      profile and GamePath. Do not delete the XML just to
                      try again.


-------------------------------------------------------------------------------
  TROUBLESHOOTING
-------------------------------------------------------------------------------

  A game appears in TeknoParrotUI but won't launch.
    Its GamePath may point to the wrong executable. Or the game was not
    fully extracted.
    Next: open TeknoParrotUI, find the game, and point it to the correct
    .exe. Then run the script again and answer Y when it asks to repair
    broken game paths. It fixes them
    automatically where possible.

  A game does not appear in TeknoParrotUI after running the script.
    Check the ACTION REQUIRED section at the end of the run.
    The game may need your choice in "REGISTER THESE GAMES IN
    TEKNOPARROTUI", or the TeknoParrotUI fallback. Or it may not be
    extracted yet ("EXTRACT THESE GAMES FIRST, THEN RE-RUN REPAIR").
    If neither applies, look in TeknoParrot-Manager.log for a registration
    error for that game.

  A game does not extract.
    TeknoParrot Manager keeps what it found about the unfinished job and
    reports ACTION REQUIRED.
    Next: open Details and check the log, the source archive, the free
    space, and the kept paths before you try again.
    Do not delete an .extracting marker just to clear the warning. Deleting
    it does not check the game files. Ask for help if needed.

  An extraction was interrupted and the game re-extracts every run.
    TeknoParrot Manager keeps what it found about the unfinished job and
    reports ACTION REQUIRED.
    Next: open Details and check the log, the source archive, the free
    space, and the kept paths before you try again.
    Do not delete an .extracting marker just to clear the warning. Deleting
    it does not check the game files. Ask for help if needed.

  Controls are not being copied to a game.
    Check these three causes:
      - No reference game for that control type is set up yet (see
        "CONTROLS SKIPPED BY DESIGN" in ACTION REQUIRED).
      - The game is in the noPropagate list in
        TeknoParrot-Manager.overrides.json.
      - The game already has five or more bound controls. It is then
        treated as a reference game itself.

  ReShade text or a window shows when the game starts.
    TeknoParrot Manager turns the welcome window, the counters and the
    messages off in every ReShade.ini it writes. If you still see them, that
    game's ReShade.ini was not written by TeknoParrot Manager, or it was
    changed by hand.
    Next: run ReShade setup (main menu 6) for that game and pick a look
    again. If the result says it left the game alone, press D to read why.
    A short version banner at game start is normal. ReShade has no setting
    to hide it.

  The console shows [UNLOGGED] entries.
    The log file (TeknoParrot-Manager.log) cannot be written to.
    Check that the TeknoParrot folder is not read-only and that you have
    write permission.
    The [UNLOGGED] entries are shown on the screen so nothing is lost this
    run.

  A fuzzy-matched game was registered against the wrong profile.
    "Fuzzy-matched" means the script matched the folder name to a game by
    similarity.
    Next, in this order:
      1. Before you change anything, save a checked copy of the affected
         UserProfile XML outside UserProfiles. Include the bindings and
         settings you need.
      2. Confirm the correct official profile and executable.
      3. Use TeknoParrot Manager's checked choice list when it is offered.
         Or set the correct profile and GamePath in TeknoParrotUI.
    Do not delete a profile just to try matching again.
    forceArchetype picks a control reference. It does not pick a
    registration match.

  A game's controls are wrong after propagation.
    Next, in this order:
      1. Look at the Restore backup choices (main menu 15) before you
         restore. Check which later settings would be replaced.
      2. Keep a copy of the current bindings/settings you need, outside
         the affected paths.
      3. Fix the reference settings in TeknoParrotUI before you try again.
    Do not remove the XML just to try propagation again.

  A game appears twice in TeknoParrotUI.
    Next, in this order:
      1. Confirm that both profiles are for the same game.
      2. Compare GamePath, bindings and settings.
      3. Keep checked copies outside UserProfiles before you remove a
         confirmed duplicate.
    Leave any file you are not sure about untouched.



-------------------------------------------------------------------------------
  CREATE SUPPORT PACKAGE
-------------------------------------------------------------------------------

  If something goes wrong, choose "Create Support Package" from the main
  menu. It is number 17.

  TeknoParrot Manager collects safe diagnostics and makes one ZIP file in:

    <TeknoParrotRoot>\TeknoParrotManager\SupportPackages\

  Send that ZIP when you ask for help.

  The package never contains:

    - ROMs or game archives
    - executables or firmware
    - UserProfiles XML or configuration files
    - PostgreSQL passwords, .pgpass, tokens, API keys, or cookies
    - recovery state or unrelated files

  Missing optional information is noted in the package. A partial package is
  clearly marked. A failure to collect or to make the ZIP never reports
  success.

  After the ZIP is made, you are offered two choices:

    O   Open the support package folder.
    B   Back to the main menu.

  If a package fails and no ZIP is made, there is no folder-opening choice.

  MORE DETAIL: CREATE SUPPORT PACKAGE
  -----------------------------------

  The package collects safe diagnostics, including the per-file ReShade
  ownership/removal scan and transaction details when available.

  The package may contain allowlisted TeknoParrot Manager/TeknoParrot text
  logs, safe game-local text logs, and metadata-only inventories of plugin
  folders. It never contains arbitrary DLL payloads.

  Common credential patterns and unnecessary user-profile paths are
  redacted from included text as defense in depth.

  The package output leads with:

    What failed:
      A list of failed required diagnostics, or "Support collection
      itself reported no failed required diagnostics."
    What TPM did not change:
      No game files, executables, DLL payloads, profiles, credentials, or
      emulator files were included or modified by support collection.

  (The package file starts with these headings.)

  Routine missing optional diagnostics remain summarized in the manifest.

  The folder opens only after canonical-path and reparse checks pass.


-------------------------------------------------------------------------------
  WHAT IT DOES NOT DO
-------------------------------------------------------------------------------

  - It does not invent control bindings. A control is set only when a
    reference game you have set up already has it. Everything else is left
    for you and shown in the ACTION REQUIRED summary.

  - It does not provide game files. You must own, or otherwise have lawful
    rights to, the original arcade PCB and any ROM/game data you use.
    TeknoParrot Manager does not provide, share, or endorse unauthorized
    game files. The script only registers and sets up your legally obtained
    games.


-------------------------------------------------------------------------------
  SUPPORT / CONTRIBUTING
-------------------------------------------------------------------------------

  Found a bug, or something that does not work as described here? Open an
  issue:

    https://github.com/Jumpstile/teknoparrot-manager/issues

  Please attach these files if you can:

    - TeknoParrot-Manager.log
    - TeknoParrot-Manager-controls.txt (if it is relevant)

  Most reports get solved faster with these attached.

  Pull requests are welcome too. The repository, full source, and version
  history all live at:

    https://github.com/Jumpstile/teknoparrot-manager


-------------------------------------------------------------------------------
  LICENSE
-------------------------------------------------------------------------------

  TeknoParrot Manager is source-available for personal, non-commercial use
  of official releases.

  These are allowed:

    - viewing the source for transparency
    - issue reports
    - pull requests sent for consideration

  These need prior written permission under a separate commercial or
  integration license:

    - commercial use
    - redistribution, modified distribution, sublicensing, or bundling
    - paid support use
    - arcade-operator use
    - use inside TeknoParrot or another emulator, launcher, or
      arcade-management product

  The TeknoParrot Manager name and branding are reserved.

  The complete license text is provided with the source distribution. The
  commercial/integration licensing notice is maintained separately by the
  rights holder.


-------------------------------------------------------------------------------
  APPENDIX: FUZZY MATCHING DETAILS
-------------------------------------------------------------------------------

  This appendix is for advanced readers. You do not need it to use the
  script.

  In short: "fuzzy matching" lets the script match a folder name to a game
  even when the names are not exactly the same.

  THE ALGORITHM

  The script uses a Sorensen-Dice bigram similarity score. This is a
  standard way to compare two pieces of text. It counts how many
  two-character pairs the two strings have in common.

  Scores range from 0.0 (no similarity) to 1.0 (identical).

  Example:
    Folder:  "Akai Katana Shin (2012)[Taito NESiCAxLive][TP]"
    Profile: "AkaiKatanaShinNesica"

  After normalization (stripping years, version strings, bracket metadata,
  splitting CamelCase, lowercasing):
    Folder:  "akaikatanashin"
    Profile: "akaikatanashinnesica"

  Dice similarity: ~0.85 -- well above the auto-register threshold of 0.72.

  THE THRESHOLD

  The threshold is the constant $FuzzyAutoThreshold near the top of the
  helper functions block in the script.

  Raising it makes auto-registration more conservative (fewer matches, less
  chance of a wrong one). Lowering it is more aggressive (more matches,
  higher chance of error).

  WHAT IS STRIPPED DURING NORMALIZATION

  The following are always removed before comparison:
    - Square-bracket metadata: [Sega NESiCAxLive][TP]
    - Bare 4-digit years: (2012)
    - Full ISO date strings: (2015-12-28) -- common in Eggman dat names
    - Decimal version strings without a ver/v prefix: (2.10.00), (1.00.48)
    - Known region/territory codes: (JPN), (USA), (EUR), (EXP), and others
    - Version strings with prefix: (ver 1.1), (rev 2), (v3), (v1.2b)
    - Parenthesized pure numbers: (2), (12)

  Meaningful parenthesized names like (Special Edition) are intentionally
  kept -- they may be the only thing distinguishing two game titles.


===============================================================================
  Latest published release: v1.0 RC9.1. Previous published release: v1.0 RC9.
  Test one game after every run. AutoSync backs up UserProfiles before
  extraction; preview mode skips the backup.
===============================================================================
