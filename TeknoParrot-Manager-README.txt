===============================================================================
  TeknoParrot Manager  |  v0.26 BETA
===============================================================================

  Registers your extracted games with TeknoParrot so they appear and launch
  automatically, copies your controls between games of the same type, and
  keeps your game library organised. Windows / PowerShell 5.1+.

  This is a beta release. Test one game after each run. Your profiles are
  backed up automatically at the start of every run.

  For a one-page version, see TeknoParrot-Manager-QuickStart.txt.


-------------------------------------------------------------------------------
  FEATURES
-------------------------------------------------------------------------------

  - Automatic registration. Scans your extracted games, matches each to the
    correct TeknoParrot profile, and makes it appear and launch in
    TeknoParrotUI. Existing registrations are never overwritten.

  - Fuzzy name matching. For platforms that share a single executable file
    (most notably NESiCAxLive, where 80+ games all use game.exe), the script
    compares the game folder name to every candidate profile code and
    auto-registers the best match when the similarity score is high enough.
    Games below the confidence threshold are flagged with their best-guess
    profile shown, so even manual registration takes one click instead of
    hunting through a long list.

  - AutoSync extraction. Copies and extracts game ZIPs from a NAS or local
    source into a staging folder you choose, skipping unchanged games. Tracks
    what has been extracted so future runs only touch new or changed ZIPs.

  - Game selection. When extracting, choose to extract everything, browse an
    A-Z paginated list, or search by keyword. Games already on disk are
    filtered from the list automatically.

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

  - LaunchBox export. Builds a LaunchBox-compatible XML file listing every
    registered game (title, platform, emulator path, profile argument). Export
    at any time and use LaunchBox's own import wizard to add games in one pass.
    The wizard assigns metadata, box art, and the correct internal emulator ID
    automatically.

  - Restore from backup. A menu option lists all timestamped backups and
    restores the one you pick in one step, without touching File Explorer.

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

  Step 1.  Open PowerShell and go to your TeknoParrot root folder:

      cd "C:\path\to\TeknoParrot"

  Step 2.  Run the script:

      .\TeknoParrot-Manager.ps1

      If the script is blocked, allow it for this session only:

      powershell -ExecutionPolicy Bypass -File .\TeknoParrot-Manager.ps1

  Step 3.  Choose a mode (see below). On later runs the script remembers your
           settings and offers to reuse them -- press Y to continue.


-------------------------------------------------------------------------------
  MODES
-------------------------------------------------------------------------------

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

  3) Restore from backup
       Rolls your UserProfiles back to a previous backup without touching
       File Explorer. The script lists all timestamped backup folders with
       file counts, you pick one by number, type YES to confirm, and the
       restore runs. The script exits after restoring.


-------------------------------------------------------------------------------
  GAME SELECTION (AutoSync mode)
-------------------------------------------------------------------------------

  After entering your folders, the script scans the staging folder and filters
  out games already extracted there. It then shows:

      347 game(s) already extracted -- not shown.
      136 game(s) available to extract.

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
       pressing D.

  At any point the header shows how many games are in the queue. After
  pressing D, the full queue is listed before extraction starts.


-------------------------------------------------------------------------------
  THE STAGING FOLDER
-------------------------------------------------------------------------------

  AutoSync extracts games into a staging folder that YOU choose. The script
  enforces these rules to keep everything healthy:

    - It must be on a LOCAL drive (network extraction is too slow).
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
  There are three outcomes per game:

    Registered          A matching profile was found and your game now appears
                          in TeknoParrot.

    Registered (fuzzy)  The executable name is shared by multiple games
                          (e.g. game.exe is used by 80+ NESiCAxLive titles),
                          but the folder name matched a specific profile with
                          high confidence. The profile code and similarity
                          score are shown in Cyan so you can spot-check.
                          These registrations are correct the vast majority
                          of the time; test the game to confirm.

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

  At the end of the run the ACTION REQUIRED section lists every game that
  needs manual registration.


-------------------------------------------------------------------------------
  HOW FUZZY MATCHING WORKS
-------------------------------------------------------------------------------

  Many platforms share a single executable file across all their titles. On
  NESiCAxLive, for example, every game uses game.exe. Without fuzzy matching,
  none of these games could be auto-registered.

  The script compares the FOLDER NAME of each game to every candidate profile
  code using a Sørensen-Dice bigram similarity score -- a standard string
  similarity algorithm that counts how many two-character pairs the two
  strings have in common.

  Example:
    Folder:  "Akai Katana Shin (2012)[Taito NESiCAxLive][TP]"
    Profile: "AkaiKatanaShinNesica"

  After normalisation (stripping years, version strings, bracket metadata,
  splitting CamelCase, lowercasing):
    Folder:  "akaikatanashin"
    Profile: "akaikatanashinnesica"

  Dice similarity: ~0.85  -- well above the auto-register threshold of 0.72.

  THE THRESHOLD

    Score >= 0.72   Auto-registered. Shown in Cyan with the score so you can
                    spot-check the match.

    Score >= 0.40   Flagged in ACTION REQUIRED with a best-guess profile
                    shown. One click in TeknoParrotUI to confirm and register.

    Score < 0.40    Flagged in ACTION REQUIRED with only the full candidate
                    list. No reliable guess could be made.

  The threshold is the constant $FuzzyAutoThreshold near the top of the
  helper functions block in the script. Raising it makes auto-registration
  more conservative (fewer matches, less chance of a wrong one); lowering
  it is more aggressive (more matches, higher chance of error).

  WHAT IS PRESERVED DURING NORMALISATION

  Years like (2012) and version strings like (ver 1.1) or (rev 2) are
  stripped because they appear in folder names but not in profile codes.
  Meaningful parenthesised names like (Special Edition) are intentionally
  kept -- they may be the only thing distinguishing two game titles.
  Square-bracket metadata [Platform][TP] is always stripped.

  WHEN FUZZY MATCHING GETS IT WRONG

  If a game is registered against the wrong profile:
    1. Delete that game's .xml from UserProfiles.
    2. Add a forceArchetype entry in overrides.json to pin it to the correct
       profile on the next run: { "WrongCode": "CorrectCode" }

  If a game's control family is misdetected (e.g. a trackball game treated
  as lightgun), add a familyOverride entry in overrides.json.


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
  LAUNCHBOX INTEGRATION
-------------------------------------------------------------------------------

  At the end of each run the script offers to export your games to a
  LaunchBox-compatible XML file:

      Export a LaunchBox import XML for all registered games? (Y/N)

  Answering Y writes TeknoParrot-LaunchBox-Import.xml next to the script,
  containing one entry per registered game with its title, platform (Arcade),
  the full path to TeknoParrotUi.exe, and the correct --profile= argument.

  Why there is no automatic write to LaunchBox's database:

    LaunchBox stores its game library in Data\Platforms\Arcade.xml and
    several related files. Writing to these files directly from an external
    script is not safe because:

      - LaunchBox must be completely closed before any of its database files
        are modified. If it is open, it overwrites external changes when it
        shuts down.
      - LaunchBox's XML format has changed across versions. Missing or
        unexpected fields can cause import errors or broken metadata.
      - Each game entry must reference a specific internal emulator ID that
        only LaunchBox itself assigns when you add the emulator through its
        own UI. Writing entries without the correct ID means games may not
        launch from the LaunchBox interface even if they appear in the list.

    The safe approach is LaunchBox's own import wizard, which handles all of
    this correctly and takes about 30 seconds.

  HOW TO IMPORT YOUR GAMES INTO LAUNCHBOX
  ----------------------------------------

  Step 1.  Make sure TeknoParrot is set up as an emulator in LaunchBox.
           If you have not done this yet:
             a. Go to  Tools -> Manage -> Emulators -> Add.
             b. Name: TeknoParrot
             c. Emulator path: browse to TeknoParrotUi.exe in your
                TeknoParrot root folder.
             d. Command-line parameters:  --profile="{rom}"
             e. Save.

  Step 2.  Go to  Tools -> Import -> Emulated Games.

  Step 3.  On the first screen of the wizard:
             - Emulator: select TeknoParrot from the drop-down.
             - Import type: Import ROM files.
             - Folder: browse to your games staging folder (the folder
               containing all your extracted game subfolders).
             - File types: *.exe  (or whatever extension your games use).

  Step 4.  Click Next. LaunchBox scans the folder and lists every game it
           finds. It will attempt to match each one to its database for
           metadata and box art automatically.

  Step 5.  Review the matches, adjust any that look wrong, and click Import.
           LaunchBox adds the games to your library.

  The exported XML file (TeknoParrot-LaunchBox-Import.xml) is a reference
  showing every registered game, its profile code, and its executable path.
  Use it to verify the list or as a record of what was registered. You do
  not need to import it directly into LaunchBox.

  Note: if you re-run the import wizard after adding more games, LaunchBox
  will skip games already in your library and only add new ones.


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
      "familyOverride": { "ProfileCode": "trackball" }
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
                    Format: { "GameProfileCode": "trackball" }

  Leave any key empty or omit it if you do not need it. Bad or missing
  entries are ignored safely.

  Note on ZIP base names: these are the ZIP file names without the .zip
  extension, exactly as they appear in your source folder.


-------------------------------------------------------------------------------
  ACTION REQUIRED SUMMARY
-------------------------------------------------------------------------------

  At the end of every run, the script prints an ACTION REQUIRED section
  listing everything that needs your attention. It has up to four parts:

    Register these games      Games found on disk that could not be
                              auto-registered because their executable name
                              is shared by multiple TeknoParrot profiles and
                              the folder-name similarity score was below the
                              auto-register threshold. Shows the executable to
                              browse to, a best-guess profile where the score
                              was still meaningful, and the full candidate
                              list.

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

  To restore from inside the script, choose mode 3) Restore from backup at
  the startup menu. The script checks that TeknoParrot is fully closed first,
  lists all available backups with file counts, and asks you to type YES to
  confirm before changing anything.

  To restore manually: close TeknoParrot completely, then copy the .xml files
  from a backup folder back into UserProfiles, overwriting the current ones.

  Log. Every run appends to TeknoParrot-Manager.log next to the script:
  what was extracted, registered, repaired and propagated, and any errors.

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
    may need manual registration (shared executable -- see "Register these
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
    Use mode 3) Restore from backup to roll back to the backup made at the
    start of that run, or delete the affected game's .xml from UserProfiles
    and re-run propagation after correcting the reference game's bindings in
    TeknoParrotUI.

  A game appears twice in TeknoParrotUI.
    Two UserProfile files exist for the same game. This can happen if the
    game was registered manually and then again by the script. Delete one of
    the duplicate .xml files from UserProfiles. Keep the one with the correct
    GamePath and any manual bindings you have already set.


-------------------------------------------------------------------------------
  WHAT IT DOES NOT DO
-------------------------------------------------------------------------------

  - It does not invent control bindings. A control is set only when a
    reference game you have bound already has it. Everything else is left
    for you and reported in the ACTION REQUIRED summary.

  - It does not provide game files. You supply your own legally obtained
    games; the script only registers and configures them.


===============================================================================
  v0.26 BETA -- Test one game after each run.
  Profiles are backed up automatically at the start of every run.
===============================================================================
