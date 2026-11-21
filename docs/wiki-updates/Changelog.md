# Changelog

Full version history is kept in `TeknoParrot-Manager-CHANGELOG.txt`. It comes in every release ZIP and is in the [repository](https://github.com/Jumpstile/teknoparrot-manager/blob/main/TeknoParrot-Manager-CHANGELOG.txt).

RC8.4 is the latest published version: https://github.com/Jumpstile/teknoparrot-manager/releases/tag/v1.0-RC8.4. v1.0 RC8.4 is a fix-up release for RC8.3. Final Version 1.0 has not been published yet. RC8.1 is the first version that can update itself in place. RC8 was a tester build and was never published.
The previous published release was v1.0 RC8.3. RC4 and RC5 are historical; RC4 is superseded.

**Note:** this page has a gap between v0.99.32 and v0.99.41. See `TeknoParrot-Manager-CHANGELOG.txt` for the full history.

---

## v1.0 RC8.4 (changes since RC8.3)

### Fixes
- Adding games with AutoSync no longer skips the second of two different
  games that have almost the same name, such as the Type X and
  NESiCAxLive versions of one game, or two versions of the same game.
  Each one now gets its own folder.
- The BepInEx result no longer says "failed" when every game you picked
  worked.
- If a game is on a drive that is not connected, installing or undoing a
  game patch gives one plain message about it.
- ReShade tells you how many games it can change and that it leaves the
  others alone. A game it cannot check is no longer called unsafe or
  damaged.
- The dgVoodoo2 scan line says how many games were checked and how many
  were skipped.
- Lists of games show the game name instead of "and 1 more".
- The game picker shows how many games you have picked so far.
- AutoSync now writes a line to the log for every ZIP it skips and says
  why, so a game that did not get unpacked can be traced.
- The Propagate Controls result names every control family that has no
  game with your controls yet. It also lists games that are already set
  up and games skipped by your own rules on separate lines.
- The game picker has an A choice for all games. Typed numbers like
  1,3,6 and 1-8 still work.
- The result screens of patches, dgVoodoo2, BepInEx and the GPU fix say
  how many games you selected and how many were changed, already set
  up, skipped or failed, so the numbers add up. They also say where the
  backup is.
- dgVoodoo2 names the result of every game you selected, with the
  reason for each skipped or failed game.
- The Action Required list is grouped by feature, with a short heading
  for each group.
- A step that skipped games on a drive that is not connected now points
  to Library health check (menu 13) to repair them.
- Library health check lists the games that need BepInEx and do not
  have it set up.
- A game file that cannot be read is now told apart from a game whose
  32-bit or 64-bit type could not be worked out.

### Also new in this release
- LEDBlinky lighting (optional): if you use LEDBlinky, the Manager can
  add lighting info for your games. It looks for LEDBlinky on your
  drives and in Program Files, or asks where it is and remembers the
  folder. A game gets only the controls it uses that your cabinet has.
  You see a preview first, a saved copy is made, and you can undo it.
  Only entries the Manager added are ever removed.
- LaunchBox: the Manager can look each game up in LaunchBox's own game
  list on your PC and use the official name and the Games Database ID,
  so LaunchBox can find info and artwork. Choose [L] in the LaunchBox
  step to do this for games that have no ID yet. You see every old
  name, new name and ID first and approve before anything is saved.
  Names you typed yourself are never replaced. Nothing is downloaded.
- LaunchBox: "Fill in game details and make playlists" fills in the
  release year and developer where LaunchBox has nothing yet, and makes
  playlists for each arcade hardware family, plus "Light gun games" and
  "Driving games". Your own playlists and details are never touched.
  Restore puts everything back.
- LaunchBox: a new optional step adds clear logos or box art from a
  folder you pick. You see a preview first, close matches are used only
  if you say yes, and Undo removes the pictures that were added.
- Games that need PlayStation 3 firmware (RPCS3) or a Play! game file
  are now checked before they start, and the Manager tells you what is
  missing.
- The game list now also reads a second program and a test menu program
  for games that list them.
- Golden Tee Live and PGA Tour, PowerPutt Live, Silver Strike Bowling
  Live, Target Toss Pro and OCC Pinball: newer TeknoParrot profiles let
  you choose where the game keeps its database. Internal is the new
  default. It needs no database install, and you start the game once so
  it makes its own database. Existing PostgreSQL is for keeping an
  existing server and its saved progress. The Manager reads your choice.
  For Internal games it skips every PostgreSQL check, install offer and
  "database missing" warning. For games set to Existing PostgreSQL,
  nothing changes: the same checks, setup, backups and restores, still
  with PostgreSQL 8.3. The Manager never switches a game from one choice
  to the other and never touches saved progress without a backup first.
  Older profiles with no choice work as before.

### Other fixes
- After unpacking, when every new game was also registered in
  TeknoParrot, the message now says so. The "unpacked only" warning
  shows only when a game still needs your attention.
- A game profile with odd characters in its program name, such as a
  quote or a pipe, no longer stops the Manager with "Illegal
  characters in path".
- If a second problem is found on the PostgreSQL setup screen, it is
  shown and you return to the menu instead of the Manager stopping.
- All screens and guides use American spelling.

## v1.0 RC8.3 (changes since RC8.2)

### Setup
- When BepInEx cannot replace a file, it now says exactly why (for
  example, the file is shared with another folder, it is a folder, it is
  a link, or it cannot be read).
- Setting up ReShade one game at a time now asks only about games that
  can be changed. It shows "game 2 of 5" and has a Back choice.
- The optional setup questions after you add games (dgVoodoo2 and the
  graphics card fix) can walk back one step, so a step you skipped by
  accident can be done.
- The dgVoodoo2 result now names every game that already had all of its
  files, so every game you picked is listed.
- After registering new games, the Manager now offers to add them to
  LaunchBox even when you pick New game only.

### Fixes
- A crash on the PostgreSQL setup screen is fixed.
- A shared .zip file no longer causes false questions about duplicate
  profiles when you add games.
- Game folders are matched by their game title when notes follow it,
  such as (Landscape,Bezel).
- Installing or undoing a game patch no longer stops with a "could not
  be checked" error when the file it needs to check is simply not there
  yet in a game folder ending in [TP].
- The safety backup made before TeknoParrot Manager tidies up its own
  files now uses a shorter folder name, so tidying up no longer fails
  on very deep install folders.

## v1.0 RC8.2 (changes since RC8.1)

### Controls
- Propagate Controls (menu 3) now shows a preview first. It lists what
  would change and saves nothing until you say yes.
- Your game settings are backed up and the backup is checked before the
  first change. After the copy you can undo it in one step.
- The controls question looks for connected controllers. It only reads,
  and it changes nothing. If it finds an Xbox-style controller, it asks
  one question instead of seven.

### Fixes
- AutoSync extracts a game even when its TeknoParrot profile points to a
  game file that is missing at an old place (for example after you moved
  your games to another drive). It still refuses a game that is already
  installed at another place, so it never makes a second copy of a
  working game. When it refuses a game, the log says why.
- If you close the Game ZIP folder window without picking a folder, the
  question is asked again. Type Q to go back.
- When a support package cannot list the plugins of a game, it now says
  why.
## v1.0 RC8.1 (changes since RC7)

### Updates
- Check for Updates installs the whole release (scripts, data and tools),
  not only the main script. It downloads the update and checks it with
  SHA-256, looks inside the ZIP first, backs up every file it replaces,
  installs it and checks it. If anything goes wrong, every file is put
  back. It says so when there is not enough free space. Your own files
  and older files the release no longer has are never deleted. Then you
  start TeknoParrot Manager again yourself.
- Older builds cannot do this. Install RC8.1 or newer by hand once:
  download the ZIP from the Releases page and extract it over your old
  folder.
- A ZIP without the script, or a CPS3 ZIP that cannot be read, is
  refused. If the Eggman page has no DAT file, it says so.
- The updater says the old version was put back only when it checked that
  it was. Sync-And-Run says so when it could not check for updates. The
  update check works from another folder with a relative script path.

### Screens and messages
- The first question asks for your TeknoParrot folder. Type it, press B
  to browse or press Q to quit. Closing the browse window without
  choosing asks the question again. A folder without TeknoParrotUi.exe is
  explained in plain words and asked again.
- When TeknoParrot's own first-time setup is not finished, the Action
  Required list says so once, with the path to TeknoParrotUi.exe and the
  steps left: choose the DAT file, scan for games, set up controls.
- Result screens are short and use plain words. File names, folders and
  codes are under Details (press D) and in the log.
- Progress bars look like bars, change color as they fill, show finished
  counts and no longer wrap in a narrow window. A long quiet wait says
  "still working". A step that failed ends red.
- The console is not resized inside Windows Terminal. Start-up does not
  wait for a key press about your custom rules. Q closes the program. The
  main menu works in a very short window.
- Saying N to "Tidy up now?" leaves your settings as they were and does
  not block the next start. An older report beside the script is left
  where it is when a newer one exists.
- The guides were rewritten for a first-time user and match the real
  screens. The two launcher files (.bat) say where the log file is. All
  screens, guides and notes use American English spelling.
- Folder prompts accept a path pasted with quotes and a whole drive such as
  D:\. Canceling the staging-folder picker asks again. Back in Reset and
  Restore returns to its menu.

### Games and folders
- Registering now finds PCSX2x6 games: their .acgame files were never
  looked at before, so those games did not register by name.
- Library Health Check has a Game support row. It says when a game
  needs you (game file missing, second game file not chosen, PostgreSQL
  settings missing). Details show the counts for each emulator.
- AutoSync says when it skips a .7z or .rar archive (it only unpacks
  .zip files) and tells you to unpack it yourself, then use Register only.
- AutoSync leaves a game folder alone when its ZIP did not change, so
  saves and settings you made are not replaced. When a changed ZIP does
  replace a folder, every file in it that is extra or different from the
  ZIP is first copied to Backups\AutoSyncReplaced. If those files cannot
  be saved, or no Backups folder is set up, that game is not updated and
  nothing is changed for it.
- AutoSync only extracts the ZIPs named in onlySync. The ZIP picker lists
  and extracts a game once when both source folders hold it.
- A familyOverride in the overrides file also applies to the games
  controls are copied from, so a game set to "spinner" finds a reference
  game instead of "no usable reference game".
- Games in very long folder paths (over 259 characters) are found, read
  and configured everywhere. Installing add-ons into one says the path is
  too long and changes nothing.
- A game whose 32-bit or 64-bit type cannot be read is not counted as
  ready, and force feedback does not give it a 64-bit plugin.
- ReShade works with both 32-bit and 64-bit games. Games that run through
  BudgieLoader (a Linux-style game format) are skipped for now. ReShade does
  not show its welcome window, counters or messages when a game starts.
- Registering games and repairing paths keep a second executable path that
  points at a file that exists. A manual path repair checks its safety
  copy first and leaves a profile TeknoParrot changed meanwhile alone.
  If saving a profile fails after Windows removed the old file, the new
  file is kept and the message says where it is.
- Region setup (main menu item 10) sets the region of your games. After
  new games are registered you are also asked once which region to use.
  Only regions the games really offer are listed. A game never gets a
  region it does not have, and a region you chose before is kept unless
  you change it in Region setup. You can pick all games or some, and go
  back to the automatic region. A restore point is saved first.
- Missing startup files (firmware for PCSX2x6 games, four files for
  Chihiro games, PlayStation 3 firmware for RPCS3 games) are found before
  you start, and the screen says which games will not start. Files from
  your own collection are copied after a check against the Eggman DAT
  list; the PlayStation 3 firmware is installed from the firmware file in
  your collection. Nothing is downloaded or supplied. Optional CPS3
  first-boot files are copied only when the whole set matches. Play!
  games are checked for their own settings file.
- Required game patches can be up to 512 MB, can be 7z or RAR files when
  7-Zip is installed, and work on long paths. Free space is checked first.
  You are asked only for the ZIP of the game version you have. AMD and
  NVIDIA patches work with an extra Windows display adapter. With two real
  graphics cards you are asked once which one the game uses. Undo works
  with a trailing backslash and ignores the version you never installed.
- Game notes (what each game needs: firmware, BepInEx, administrator,
  setup program) and the LaunchBox import file are saved in the Reports
  folder. If notes cannot be saved, you are told.
- A saved DAT list is kept when an old DAT path is left in the overrides
  file. A DAT file set only there is used and the start-up question is
  skipped. Canceling the DAT save window downloads nothing. Two ZIP
  folders, one inside the other, do not block the DAT download.
- With two TeknoParrot folders on one PC, your settings are found and the
  "copy from another TeknoParrot folder" step finds both.

### ReShade, dgVoodoo2, force feedback and crosshairs
- ReShade has 25 approved effects and 17 profiles for arcade play: Original,
  11 CRT looks and 5 other looks. Each has a short description and a rough
  light, medium or heavy cost. The preview shows approximations. Its
  drop-down follows the numbered list, and a choice is only used when you
  confirm it.
- You can change the ReShade look at any time and undo it for one game or
  all games. If a game also uses TeknoParrot's own CRT look, you are asked
  whether to keep it (the default) or turn it off for that game.
- The ReShade result names each game that is left alone, and why, under
  Details. A game with only a leftover ReShade.ini can be replaced; the
  old file is copied first so you can undo it. Removal says so when the
  undo copy could not be finished.
- dgVoodoo2 copies the dgVoodoo.conf from your dgVoodoo2 folder to each
  game that has none. A game's own file stays, and a per-game preset wins.
- Force feedback setup keeps a plugin it just installed and updates one
  you installed earlier through TeknoParrot Manager. A file that is not
  ours is never overwritten.
- Crosshairs for ElfLdr2 go only into the real loader folder. Every
  skipped game is named with the reason, and a skipped game does not make
  a finished setup say "was not completed". The PCSX2 first-run question is
  asked once. The force feedback count never goes over the number of games.
- When GitHub answers but a download is missing, the screens say that and
  do not blame your internet.

### PostgreSQL setup and restore
- When setup stops, it says what happened to your data: put back and
  checked, or could not be checked. After a repair that stopped part way
  it says some things may have changed and points to View Log. A failed
  install says whether the Windows installer had already run. A rollback
  removes only a database made in that run.
- Password prompts can be left by pressing Enter.
- Setup keeps a note about databases it is building. If the PC stops in
  the middle, the next setup removes only the half-built database and
  builds it again.
- Every game database is made ready during setup and tested with the
  game's own settings: it must connect and hold its tables. Nothing is
  left for TeknoParrot to create when you first start a game. A game
  with no starting database file (pg_backup) cannot be made ready: it
  is left out and named, and every other game is still set up.
- A game with several identical backup files gets its database from the
  newest one, in setup and in the [I] rebuild. The confirm screen, Details
  and the log say which file was used. If it does not restore, setup stops
  and puts everything back. A backup with no ".backup" ending works, and
  notes such as readme.txt are never used as a backup.
- A backup that is cut short is never offered for restore. Five known
  warnings at the end of a game backup do not undo setup; Details name
  the links between tables that could not be made.
- Setup names each game profile that needs a fix and never writes over a
  profile saved while it ran. It asks before touching a game that points
  at another server, port or user. Choosing K leaves that profile alone.
- Before the Windows permission box, you are told to approve it with an
  administrator account of this PC. If it fails twice, "Try again" stops
  and says why.
- PostgreSQL tools have time limits, so a stuck tool counts as failed. A
  short password such as "1" works. A failed check does not reset the
  password. Capital letters in database names work.
- Two TeknoParrot Manager windows cannot change PostgreSQL at once, and a
  database made by another window is not removed. A database just created
  is not counted as "Already set up".
- A restore keeps the database's text encoding when it is known. A backup
  that is only locked says "could not be read, try again".

### Backups and undo
- Restore points are made at start-up. A Reset and Restore menu keeps
  working after TeknoParrot is moved, and Restore all brings back
  TeknoParrot Manager's own settings, even after the tidy-up moved them.
- Restore backup has a new choice, Rebuild one game from its ZIP. It puts
  a broken game folder back to exactly what its ZIP holds. The ZIP is
  unpacked and checked first (and checked against the DAT list when the
  game is in it). Your old folder is not deleted: it is kept aside, and
  you can put it back or delete it from the same menu.
- LaunchBox: games can be added directly. It asks first, waits for
  LaunchBox to close (it never closes it) and saves a checked copy of each
  file before writing. Restore lists UserProfiles, Postgres and LaunchBox
  backups, and a backup from another folder needs its own confirmation.
  Restore backup does not list the copies made when ReShade is removed.
- PostgreSQL recovery files are private to your Windows account. Older
  recovery folders move into TeknoParrotManager\Backups.
- BepInEx installs and updates keep a verified backup and roll back only
  what TeknoParrot Manager made. An update that could not remove its
  temporary files is shown as finished, with a note. A finished game mod
  update leaves no spare copy in the game folder.
- If the registration record cannot be read, the file is left as it is and
  you are told. AutoSync only calls its profile backup complete when it
  matches your live profiles. A short registration list is saved in its
  own file, and ACTION REQUIRED does not say a list was saved when none
  was.

### Library Health check
- It says "Could not check" and asks for attention, instead of OK, when
  it could not read the PostgreSQL service, the game profiles, the startup
  files or a game, or did not look at an area. Games on a drive that is not
  connected tell you to reconnect it. A game in a very long path counts as
  not fully checked.
- A damaged game profile is named as "could not be read" and gets no path
  repair. It does not stop the LaunchBox preview or add for other games.
  A path with characters Windows does not allow is named "not a valid
  path". Paths with spaces around them are read correctly.
- Choosing ReShade in the check starts ReShade setup.

### Support package
- Create Support Package makes one cleaned ZIP that leaves out game
  programs and passwords. Folder names with spaces are hidden.
- A package with missing information says "partial" and names what is
  missing. An empty log file is not called a failure. It keeps the newest
  part of a main log over 5 MB, lists each game's real controls and
  counts a profile snapshot only if it is inside. A complete ZIP that
  left a temporary folder behind says it is ready to send and names the
  folder under Details.

### Other
- Missing startup files are not listed under ACTION REQUIRED after they
  were copied. The run recap counts a DAT list you picked at start-up.
- Release packages hold only the files users need. On a slow PC, a late
  drive check does not show a wrong "could not tell" warning.

---

## v1.0 RC7 (2026-08-22) -- published

- Publication: v1.0 RC7 is published. Release archive:
  https://github.com/Jumpstile/teknoparrot-manager/releases/tag/v1.0-RC7
- Asset filename: GitHub serves the immutable asset as
  `TeknoParrot.Manager.v1.0.RC7.zip` after filename normalization. The
  verified SHA-256 is
  `45D14469CF750AC14B0F4113FB4117E2DA1C80F612C335D66B61C6E3FE5ABF84` and
  the size is 4,862,794 bytes.
- Release visibility: RC7 was not hidden from GitHub's front-page Releases
  panel. The GitHub prerelease flag was not used when it would have
  prevented that.
- Readiness: RC7 carries the read-only controls-readiness handoff and
  contract-backed missing-component warnings. When controls are Missing, Not
  verified, Unsupported, or Unknown, ACTION REQUIRED directs the user to open
  TeknoParrot controls configuration and map/test controls before treating the
  game as ready. Registration, launch observation, controls readiness, and verification
  remain separate.
- Previous published release: v1.0 RC6 (historical).

---

## v1.0 RC6 (2026-08-15) -- historical; superseded by RC7

RC6 remains in the version history only. See the repository changelog for its
feature and security details.

---

## v1.0 RC5 (2026-08-14) -- historical; RC4 packaging correction

RC5 corrected the RC4 package dependency omission. RC4 is historical and
superseded by later releases.

---

## v1.0 RC4 (2026-08-13) -- beginner clarity, Centipede Chaos coverage (historical; superseded by later releases)

- **Improvement (issue #222):** the Eggman dat, supplementary dat, and thumbnail download prompts now explain what the file is and confirm it never downloads game data, before asking whether to proceed. Added a "What TPM just did" recap to the end-of-run summary (ZIPs extracted, games registered, dat file action taken, thumbnail action, anything still needing manual attention). Added a first-run welcome screen (new installs only) framing that TPM organizes/extracts/registers/exports games but does not provide games or guarantee boot/fullscreen behavior.
- **Fix (issue #130/#79):** TPM's internal GameProfile schema-drift diagnostic had a stale baseline flagging long-standing, widely-used profile fields as "unknown." Re-captured against the live upstream catalog. Also confirms Centipede Chaos is fully supported through TPM's existing generic profile-parsing, matching, and export logic.

---

## v1.0 RC3 (2026-08-08) -- published hardware-certified release

- Fixed (issue #173): pcsx2x6 crosshair setup verifies first-run initialization and the contract-resolved DataRoot before deploying assets. Emulator-owned cursor_path settings remain verify-only; TPM never writes them.

---

## v1.0 RC2.1 (2026-07-10)

Release-hardening pass on top of RC2: thumbnail downloads, update-check version display, certification-suite reliability, and menu polish.

- **Fix (issue #132):** thumbnail downloads no longer leave a stale "Downloading Thumbnails" progress overlay stuck on screen after a failure -- most visible when every thumbnail in a batch came back with no online icon available. Reworded thumbnail messaging into plain language and stopped implying a missing icon means the game is unsupported.
- **Fix (issue #134):** the update checker's "Current version" and "Latest version" now share one canonical display format instead of showing the same release two different ways.
- **Fix (issue #136):** the internal Certification Suite (not something end users run) could hang indefinitely during its regression test phase with no diagnostics. It now shows live heartbeat progress and enforces a timeout so a hang fails cleanly with a clear reason.
- **Usability:** the Overrides summary line (advanced settings, shown only when configured) explains what it means and what action to take in plain language. The Preview/Dry Run "apply for real" prompt explains it performs a fresh scan, not a replay of the preview.
- **Visual polish:** the Professional/Ultra menu banner renders as a responsive FIGlet/ANSI-Shadow wordmark that scales with console width.

## v1.0 RC2 (2026-07-04)

- **Fix:** the first RC2 package was structurally valid but still displayed the runtime banner TeknoParrot Manager v1.0 RC1. The runtime banner/header now display TeknoParrot Manager v1.0 RC2.
- **Validation:** release package validation now checks the packaged TeknoParrot-Manager.ps1 version/header/banner, so a stale release identity cannot pass ZIP validation again.
- **UX:** the main menu now adapts to console size: full descriptions on roomy displays, a compact layout when space is tight, and `?` at the prompt for full descriptions on demand.
- **Gate:** Release Integrity Audit is now mandatory before every public release, alongside Certification.

## v1.0 RC1 (2026-07-03)

Promoted to RC1 for the upcoming 1.0 release. No new functional changes beyond what's listed below -- this entry was originally written as v0.99.45 BETA; the content is unchanged, only the version identity was promoted following Documentation Certification, a Human Trust Audit, and full Behavioral/Recovery Certification.

- **Fix:** pcsx2x6 crosshair deployment now writes `P1.png`/`P2.png` to the official upstream location, `pcsx2x6\TeknoParrot\crosshairs\`, instead of the emulator folder root. Files already deployed at the old location are left in place, not deleted. (#79)
- **Fix:** Check for Updates could report "Update installed successfully" without actually replacing the script if the destination file was briefly locked (for example by antivirus) at the moment of replacement. It now correctly reports failure and leaves the original script and its backup untouched. (#86)
- **New:** TPM now detects missing pcsx2x6 emulator firmware/BIOS files for registered games and reports it under ACTION REQUIRED, before you discover it at launch. Read-only, existence-check only -- TPM never provides, downloads, links, or redistributes these files. Informational only; does not block or change registration. (#85, tier 1)

## v0.99.44 BETA (2026-07-02)

- **Hardening:** live file downloads (Eggman/RomVault DAT, PostgreSQL guide bundle, FFBArcadePlugin DLLs, BepInEx release ZIP, TPM update package, TeknoParrotUI thumbnails) now share a single hardened download pipeline with readable progress and validated, atomic writes. Also fixed AutoSync/extraction duplicate-prompt false positives and an auto-detect return-value regression, with expanded regression test coverage.

## v0.99.43 BETA (2026-07-01)

- **New:** standalone "Propagate Controls" menu option (mode 3). Re-copies control bindings from reference games to other compatible games without going through AutoSync/Register first. (#59)
- **Changed:** the main menu is permanently reorganized into four logical groups -- Library Management, Game Enhancements, Maintenance and Recovery, Application.
- **Fixed:** the standalone Propagate Controls option could continue past an incomplete UserProfiles backup; any backup-copy error is now unconditionally fatal for this mode.

## v0.99.42 BETA (2026-07-01)

- **Changed:** the main menu is reorganized into four logical groups -- Library Management (1-3), Game Enhancements (4-9), Maintenance and Recovery (10-12), Application (13-14). Every wiki page's "(Mode N)" heading updated to match. See [[Home]] for the current full list, or `ARCHITECTURE.md` in the repository for the complete old-to-new mode number mapping.

## v0.99.41 BETA (2026-07-01)

- **New:** [[Propagate Controls]] menu option (mode 13, Exit moved to 14). Runs the same control-propagation step offered at the end of AutoSync/Register, without going through extraction/registration first. (#59)

## v0.99.32 BETA (2026-06-26)

- **Docs:** added a "New to TeknoParrot?" primer section to the Quick Start page — plain-English explanation of TeknoParrot, what this script does vs what TeknoParrot does, and a glossary of key terms (UserProfile, GameProfile, dat file, control propagation, archetype, FFB, BepInEx). For users new to TeknoParrot who find the docs assume prior knowledge. (#32)
- **Docs:** added a collapsible "What the menu looks like in the console" block to the Quick Start page, showing the exact menu text a new user will see when running the script. (#31)
- **Fix:** `$ScriptVersion` internal variable was mistakenly left at `"0.99.30"` after the v0.99.31 release; corrected to `"0.99.32"`.

## v0.99.31 BETA (2026-06-26)

- **New:** register mode now shows a live progress bar (`Scanning game library X/Y`) so large libraries don't look frozen. (#21)
- **New:** `subFolderMap` override in `overrides.json` — for games (e.g. CrediarDolphin / Tatsunoko vs. Capcom) whose executable must live in a specific subfolder of the TeknoParrot root rather than the staging folder. (#11)
- **Docs:** added Uninstalling / Removing the Manager section. (#35)
- **Docs:** expanded Troubleshooting with common error messages (access denied, path too long, network timeouts, Postgres password, LaunchBox open, frozen-looking scan). (#33)

## v0.99.30 BETA (2026-06-25)

- **Fix:** control propagation now detects directional/action slot mismatches on already-bound (REFERENCE) profiles and flags them in the ACTION REQUIRED output and controls-status file, so you know which buttons to rebind manually in TeknoParrot's UI without needing a manual XML dump. No bindings are ever rewritten. (#17 follow-up)
- **Fix:** the AutoSync-entry network-path checks (staging folder and ZIP source) now share a single drive-info fetch instead of each spawning an independent background job. Drive info is cached for the duration of each menu pass and refreshed automatically when you return to the menu. (#19)
- **Fix:** the duplicate-path conflict resolver's "switch to conflicting copy" choice now respects dry-run mode instead of always writing to disk. (#34)
- **Fix:** `Get-PrimaryExecutableName` now uses the DOM parser directly instead of a regex pre-pass. The DOM parser ignores XML comments by design, which was the original goal of the regex -- the regex approach was fragile and redundant. (#22, #25)
- **Fix:** GameProfile XML reads in the profile-index scan now explicitly use UTF-8 encoding. (#24)

## v0.99.29 BETA (2026-06-25)

- **Fix:** control propagation could copy the wrong physical input into a game's directional slots when two profiles share an InputMapping enum value but use it for different purposes. For example, SF3 uses `P1ButtonUp` for the joystick Up direction; Tekken 6 assigns the same key to "Left Punch". The script now checks that source and target slots agree on whether they represent a joystick direction (pure Up/Down/Left/Right label) before copying a binding; a mismatch leaves the slot in the ACTION REQUIRED manual list instead of writing incorrect input data. Games already configured with wrong directional bindings from a prior run need those specific buttons rebound manually in TeknoParrot's UI.

## v0.99.28 BETA (2026-06-25)

- **New:** every prompt that asks you to type a file or folder path -- the TeknoParrot root, games install folder, ZIP source and supplementary ZIP source folders, Eggman dat files, ReShade preset/DLL, dgVoodoo2 folder, LaunchBox root, HyperSpin 2 data path, and the Eggman ZIP download save location -- now also accepts typing "B" to open a native Windows folder/file browser instead of typing the path by hand. Typing the path directly still works exactly as before.
- **Fix:** two prompts (ReShade and dgVoodoo2 "DLL/folder not found") told you to choose the wrong menu option number for getting back to that setup step. Corrected to match the real menu.

## v0.99.27 BETA (2026-06-25)

- **Fix:** a regression from v0.99.23's network-drive-detection hard timeout. Declining "Use these settings? (Y/N)" (or running for the first time, or anything else that triggers auto-detecting your TeknoParrot folder) threw a wall of "Test-IsNetworkPath : Cannot process argument transformation on parameter 'Drives'" errors. Root cause: the background-job mechanism used for the hard timeout doesn't preserve .NET object types across the job boundary. Fixed by only ever passing plain data across that boundary. Also hardened the saved-settings loader against a stale config file with the TeknoParrot root stored in the wrong internal format. Thanks to the tester who reported this.

## v0.99.26 BETA (2026-06-24)

- **Packaging:** the release ZIP now includes the project's MIT LICENSE file. No script changes.

## v0.99.25 BETA (2026-06-24)

- **Fix:** the FFB plugin setup summary lumped two different situations together under "Skipped (no match)" -- a game the plugin's table doesn't know about, vs. a game it knows about but whose DLL isn't downloaded locally (fixable). These now get separate, clearly labeled counts.
- **Docs fix:** the README and QuickStart .txt files told you to choose "mode 5" for ReShade setup in several places -- that's dgVoodoo2's number; ReShade is mode 4. Corrected (this wiki and README.md already had it right).

## v0.99.24 BETA (2026-06-24)

- **Hardening:** two Postgres install-path comparisons used -like/-notlike (wildcard pattern matching) where exact equality was actually intended. Harmless in practice since the compared path is a fixed constant with no wildcard characters, but switched to the correct case-insensitive exact-equality operators, found during a full code scan. No change to normal operation.

## v0.99.23 BETA (2026-06-24)

- **Hardening:** the network-vs-local drive detection used when suggesting your TeknoParrot/LaunchBox folder and warning about a network staging/source path is now wrapped in a hard timeout, so a deeply unresponsive network share can never block the script indefinitely. This closes a residual, never-actually-observed theoretical gap on top of the v0.83 fix for a real 20-30s hang this same check used to have. No change to normal operation. See issue #5.

## v0.99.22 BETA (2026-06-24)

- **Security hardening:** before uninstalling a stale/partial PostgreSQL install (only ever done when its registered InstallLocation already matches this script's expected install path), it now also cross-checks PostgreSQL's own installer-written registry record as a second, independent confirmation before proceeding. No change to normal operation -- this only affects the rare partial-install cleanup path. See issue #4.

## v0.99.21 BETA (2026-06-23)

- **Security hardening:** every Postgres database helper that shells out to psql.exe/pg_dump.exe/pg_restore.exe/createdb.exe/dropdb.exe used to pass the database password via the PGPASSWORD environment variable for the duration of that call -- briefly visible in that child process's own environment block to anything else on the system that could inspect it. These now use a temporary PostgreSQL `.pgpass` credential file instead (locked down to the current user, deleted immediately after use). No user-visible behavior change. See issue #3.

## v0.99.20 BETA (2026-06-23)

- **Fix:** a reference game whose Input API was corrected via the `canonicalArchetype` override (v0.99.17) had that correction written to disk, but other games that propagate their controls from that same reference game later in the same run still picked up the old, pre-correction Input API value -- the fix never applied to anything it propagated to until the NEXT run. Both the reference game's correction and every other game's propagation from it now use the corrected value within a single run. See issue #1.

## v0.99.19 BETA (2026-06-23)

- **Fix:** the shared-executable-name disambiguation pass (used when several profiles use a generic exe name like `game.exe`) had no tie-break between candidates. If two different profiles both scored at or above the auto-register threshold against the same folder name, whichever one the internal candidate list happened to be iterated to last would silently win, with no real signal it was the better match. A folder name that's a near-miss of two different real profile codes (typo, truncation, etc.) could previously have been auto-registered to the wrong one with no warning. Now requires a clear score gap between the best and runner-up candidate before trusting an automatic match; anything too close to call falls through to the existing dat lookup / manual ACTION REQUIRED review instead. See issue #15.

## v0.99.18 BETA (2026-06-22)

- **Fix:** AutoSync and the extraction pickers could still report a game as "available to extract" even though it was already extracted and fully registered, if its folder had been renamed to something the folder-name-matching logic could not predict. The v0.99.15 fix only ever helped a narrow case; extraction availability is now also cross-checked against the game's own registered GamePath, so an already-registered game is never reported as missing again regardless of what its folder is named. See issue #13.

## v0.99.17 BETA (2026-06-22)

- **New:** `canonicalArchetype` overrides.json key. A reference game is normally never modified -- not its bindings, and not its Input API, since the script has no reliable way to tell which of two reference games in the same control family is actually correct if they disagree. `canonicalArchetype` lets you name the correct one explicitly, per family; every OTHER reference game in that family then gets its Input API corrected to match it on the next control propagation run. Bindings are still never touched, only the Input API field. See issue #1.

## v0.99.16 BETA (2026-06-22)

- **Fix:** `Register-Games` could fail to auto-register a game whose executable name is shared by several profiles (e.g. `sdaemon.exe` across multiple Raw Thrills titles) if its staging folder had been renamed to the short name recommended by a PATH TOO LONG warning in ACTION REQUIRED (e.g. `NicktoonsNitro` -> `NTN`). The folder-vs-profile-code fuzzy match never knew about that rename, so the renamed folder no longer resembled its actual profile code closely enough to clear the auto-match threshold and was reported as needing manual registration instead. The fuzzy match now also tries the recommended short name as an alias for each candidate profile.

## v0.99.15 BETA (2026-06-22)

- **Fix:** AutoSync and the extraction pickers (modes 1/2) could report a game as "available to extract" even though it was already extracted, if its staging folder had been manually renamed to the short name recommended by a PATH TOO LONG warning in ACTION REQUIRED (e.g. `AliensArmageddon` -> `ALIENS`). The folder-matching logic only compared normalized names, and a renamed folder no longer matched the ZIP's original name. Already-synced games are now also self-healed: AutoSync recognizes the renamed folder and updates its stored path automatically.

## v0.99.14 BETA (2026-06-22)

- **Fix:** reverts a regression introduced in v0.99.12. That release let an archetype's own Input API be retroactively "corrected" against the best-overlap match from other archetypes, but in practice almost every well-bound button-family profile is itself an archetype, so this ended up cross-correcting independently-correct profiles against each other with no real signal for which one was right -- confirmed on a real library, where it flipped a manually-configured `MergedInput` reference profile to `DirectInput` because an unrelated profile won an overlap comparison. An archetype's Input API (and bindings) are once again never modified, full stop.

## v0.99.13 BETA (2026-06-22)

- **Fix:** `GamePath2` backfill for two-executable profiles (Initial D: Arcade Stage Zero/Ver. 2 and similar) refused to touch a `GamePath2` that was already non-empty, even if it was stale -- e.g. left pointing at a pre-migration folder after `GamePath` itself had since been repaired to a new location. `GamePath2` is now only left alone when it already points at the correct companion exe; a stale value gets corrected the same way a stale `GamePath` already does.

## v0.99.12 BETA (2026-06-22)

- **Fix:** control propagation's retroactive Input API correction (added in v0.99.10) could never actually reach the games it was meant to fix. Any profile bound well enough to qualify for the API check also qualified, at the same threshold, to become a reference archetype for its control family -- and an archetype was always skipped outright, so the API check never ran on it. The fix now still never copies button bindings into an archetype, but its own Input API is checked and corrected against the best-matching other archetype just like any other already-bound profile.

## v0.99.11 BETA (2026-06-21)

- **Fix:** the Eggman collection dat parser was silently dropping roughly half of all games from its lookup index (493 opened, only 236 indexed in a real collection dat), due to an off-by-one in how it skips each game's checksum entries for performance. Confirmed as the real cause behind several previously-reported "game not recognized" cases, including OutRun 2 and Time Crisis 5 -- both have perfectly valid catalog entries and were just two of the ~257 games this bug happened to drop. 476 games now index correctly.

## v0.99.10 BETA (2026-06-21)

- **Fix:** control propagation's Input API correction (added in v0.99.2 for "button"-family games whose archetype uses MergedInput) only ever ran as part of the same pass that copies button bindings. A game that was already fully bound from an earlier run -- including every game bound before v0.99.2 shipped -- skips that whole pass, so it could never have its Input API retroactively corrected even after upgrading. Propagation now checks and fixes the Input API on an already-bound profile too, without touching any of its button bindings.

## v0.99.9 BETA (2026-06-21)

- **Fix:** the `GamePath2` fix from v0.99.6 (for two-executable games like Initial D: Arcade Stage Zero) only ever ran when registering a brand-new profile. A profile that was already registered -- including any registered before v0.99.6 added this field at all -- was skipped as "already done" and never got `GamePath2` backfilled. Registration now also backfills `GamePath2` on an already-registered profile if it's missing and the companion executable is found.

## v0.99.8 BETA (2026-06-21)

- **Fix:** a game folder could still be wrongly listed as needing manual registration even though its real executable was already correctly registered, if that same folder also contained a second, unrelated exe-like file whose name happened to collide with other profiles. Confirmed against a real tester log: a generic shared launcher stub sitting next to an already-registered real executable was enough to keep re-flagging the folder every run.

## v0.99.7 BETA (2026-06-21)

- **Fix:** hardened the registration check that recognizes a game whose UserProfile is already correctly configured, even when the folder's executable name is shared by several profiles. The check compares the profile's saved game path against the file actually found on disk, but only stripped a trailing backslash, not other incidental whitespace -- so a saved path with extra whitespace would never match, wrongly flagging the game as still needing registration.

## v0.99.6 BETA (2026-06-21)

- **Fix:** profiles that require two executables (`HasTwoExecutables=true` -- e.g. Initial D: Arcade Stage Zero/Ver. 2/The Arcade and its companion `amdaemon.exe` process) only ever had their primary `GamePath` configured during registration. The second executable's required `GamePath2` field was never set, leaving these profiles half-configured even though registration reported success. Registration now also looks for the profile's `ExecutableName2` alongside the already-resolved primary exe and sets `GamePath2` when found. Never overwrites an existing `GamePath2` and never blocks registration of the primary exe if the companion file isn't found.

## v0.99.5 BETA (2026-06-21)

- **Fix:** `Write-DownloadAudit` (the SHA256 logging done for every third-party binary this script downloads -- the Eggman dat ZIP, the BepInEx release ZIP, and the FFBArcadePlugin DLLs) silently swallowed a missing or locked source file instead of logging it as a hashing failure, because `Get-FileHash`'s default non-terminating error was never caught by the existing try/catch. No security impact (this logging never gated or blocked anything), but the audit trail itself was misleading on failure. Fixed by forcing the error to be terminating so the catch behaves as documented.

## v0.99.4 BETA (2026-06-21)

- **Fix:** registration could mark an entire game folder as "accounted for" the moment any exe-like file inside it (an installer, uninstaller, redistributable stub, or other non-launcher file) happened to share a filename with an unrelated profile's executable name -- even when that collision itself only produced an unresolved "needs manual registration" result. This permanently blocked the dat-lookup and profile-code fuzzy-match passes from ever getting a chance to resolve the folder's real launcher via a different exe in the same folder. A folder is now only marked accounted for when an exe's own outcome was conclusive (registered, already registered, or a genuine profile-code conflict).

## v0.99.3 BETA (2026-06-21)

- **Fix:** a folder whose game was already correctly registered in TeknoParrotUI could still be wrongly flagged as needing manual registration, when that folder's executable name is shared by several TeknoParrot profiles. Registration now also checks, before any fuzzy-name matching, whether any existing UserProfile already points its GamePath at this exact executable -- a name-independent signal that catches cases where the correct profile's own code doesn't fuzzy-match the folder name closely enough, or was never even a fuzzy-match candidate to begin with.

## v0.99.2 BETA (2026-06-21)

- **Fix:** on newer TeknoParrot builds, FFB Blaster setup (mode 7) and the Library health check's FFB Blaster coverage report could find zero eligible games even with a paid membership. The identifying text moved from the field's name to its category label in newer GameProfile XML. Discovery now checks the category label first, falling back to the old field-name check for older profiles.
- **Fix:** control propagation (mode 6) could copy a real, correct button binding into a target profile but leave its buttons appearing empty in the TeknoParrot UI, because the propagated archetype's Input API (e.g. MergedInput) was being silently rejected when the target profile's on-disk FieldOptions hadn't listed it yet. Now mirrors TeknoParrot's own UI behavior of dynamically adding that option.

## v0.99.1 BETA (2026-06-20)

- **Fix:** the third-party FFB plugin setup (mode 7) could crash with an unhandled "Value cannot be null" error right after FFB Blaster setup aborted (e.g. no FFB Blaster field found, or no membership). Root cause: a PowerShell pipeline quirk where an empty-array return value is silently turned into `$null` once captured by a plain variable assignment. Fixed at every affected return point, plus a defensive guard added at the actual crash site.
- **Fix:** the same quirk meant pressing "A) All unextracted games" in the AutoSync picker silently extracted nothing instead of extracting everything. Fixed the same way.
- **Fix:** `Remove-PostgresPartialInstall` (used before a fresh PostgreSQL install attempt) now verifies a matched registry entry's install location before uninstalling it, and only stops/removes a service with the exact expected name -- closes a theoretical gap where an unrelated standalone PostgreSQL 8.3 install could have been caught by cleanup. Found via external security review; no evidence this was ever actually triggered.

---

## v0.99 BETA (2026-06-19)

- **New:** [[Postgres Setup]] (mode 11). Installs and configures the local PostgreSQL 8.3 database that some Incredible Technologies games need (Golden Tee Live, Power Putt Live, Silver Strike Bowling Live, Target Toss Pro, Orange County Choppers Pinball). Detects which of your registered games need it automatically -- no manual list to maintain. Never reinstalls PostgreSQL if it's already installed, and never recreates or restores over a database that already exists. For older game profiles that predate TeknoParrot's own "Automatically create Database" feature, creates the database and restores that game's bundled backup itself; for newer profiles, just fills in the connection settings. Installing PostgreSQL itself requires running the script as Administrator -- the first feature in this script that does.
- **New:** Postgres database backups. Every Postgres setup run backs up every existing database first. Restore them via mode 9 ([[Restore Backup]]), alongside the TeknoParrot UserProfiles and LaunchBox library backup choices.
- **New:** the database password is encrypted with Windows DPAPI before being saved -- the first secret this script has ever stored.

---

## v0.98 BETA (2026-06-19)

- **New:** direct LaunchBox integration. The script can now write registered games straight into LaunchBox's own library files -- no import wizard needed. Checks LaunchBox/BigBox are closed first, backs up every file it's about to change into `Scripts\LaunchBoxBackups\`, and never duplicates a game already present. The first time you use it, choose how TeknoParrot games should appear: mixed into your existing Arcade platform, a separate "TeknoParrot" platform, a platform with a name you choose, or both at once. See [[Register#launchbox]] and [[Restore Backup]].
- **New:** a "LaunchBox library backup" option under mode 9 restores the exact LaunchBox files the direct integration last changed.
- **Fix:** the LaunchBox manual-import reference file had its `ApplicationPath` pointing at the game's executable. Confirmed against a real working LaunchBox installation that this is wrong -- LaunchBox's own TeknoParrot emulator entry launches by profile (`--profile=%romfile%.xml`), so the path it needs is the GameProfile XML itself. Also fixed the printed import-wizard instructions, which told users to import `*.exe` files; the correct target is the `UserProfiles\*.xml` profile files.

---

## v0.97 BETA (2026-06-18)

- Every binary downloaded from a third party (Eggman dat ZIP, BepInEx release ZIP, both FFBArcadePlugin DLLs) now has its source URL, filename, version (where known), and **SHA256** logged to `TeknoParrot-Manager.log` -- an audit trail, not a verification gate, since none of these sources publish checksums to check against.
- ReShade setup now checks the **Authenticode signature** on your `ReShade64.dll`/`ReShade32.dll` before deploying them, since ReShade's own installer is code-signed. An invalid or missing signature is shown with a plain-English explanation plus the raw status, but does not block setup.

---

## v0.96 BETA (2026-06-18)

- ACTION REQUIRED now includes a **GAME-SPECIFIC SETUP NOTES** section for any registered game with special setup notes in the community compatibility database ([eggmansworld.github.io/TeknoParrot](https://eggmansworld.github.io/TeknoParrot/)) -- shows the expected executable name and the full notes text, word-wrapped and separated game-by-game.
- Saving the ACTION REQUIRED summary now opens a **Save dialog** instead of always writing silently to `TeknoParrot-Manager-ActionItems.txt` next to the script. Skipped automatically in unattended runs and preview/dry-run mode.
- Internal: extracted the eggmansworld.github.io fetch-and-parse logic into a shared `Get-EggmanGameData` helper, reused by both the BepInEx required-games list and the new setup-notes lookup.

---

## v0.95 BETA (2026-06-18)

- Library health check (mode 10) now also reports **dgVoodoo2** coverage -- which registered games import a legacy DX8/DDraw/Glide API but don't have the matching DLL deployed yet, checked locally with no network access.
- Also reports, purely informationally, how many registered games have **ReShade** or **BepInEx** installed (not flagged as a gap to fix).
- Fixed a pre-existing stale "mode 6" reference for dgVoodoo2 setup in the README (it's mode 5).

---

## v0.94 BETA (2026-06-18)

- The extraction summary now shows how many games a preview run would extract.
- Library health check (mode 10) now also reports **GPU fix** and **FFB Blaster** coverage -- which registered games are eligible but don't have it applied yet, checked locally with no network access.
- Crosshair setup (mode 3) remembers your last P1/P2 choice and offers it as a default.

---

## v0.93 BETA (2026-06-18)

After AutoSync/Register's preview/dry-run mode finishes, the script now asks **"Apply these changes for real now?"** instead of requiring a manual re-run. Answering Y silently re-enters the same mode for real; N returns to the menu unchanged.

---

## v0.92 BETA (2026-06-18)

**Preview / dry-run mode.** AutoSync and Register only can now show what they would do (extractions, registrations, repairs, control propagation) without writing anything -- answer Y to the new "Run in PREVIEW mode first?" prompt, or pass `-DryRun` on the command line. No backup is created and the LaunchBox/HyperSpin export, thumbnail download, and GPU fix follow-up offers are skipped in preview mode.

**Live BepInEx game list.** The BepInEx Update Check menu (mode 8) now shows a live-fetched example list of games known to require BepInEx instead of a hardcoded one that could go stale.

---

## v0.91 BETA (2026-06-18)

**Security hardening.** Found and fixed four real issues affecting how untrusted, live-fetched filenames were used in path construction, none known to be exploited:
- Path traversal in `Invoke-FFBPluginSetup` (untrusted destination filename from a live-fetched file).
- Path traversal in `Invoke-BepInExUpdateCheck` (untrusted filename from the GitHub Releases API).
- Path traversal in the Eggman dat downloader's default save path (same root cause).
- Malformed `\\?\` long-path prefix for UNC destination paths in `Expand-ZipFileSafe`.

All four fixed and verified with synthetic tests.

---

## v0.90 BETA (2026-06-18)

**New automatic check: known GPU-vendor incompatibilities**

Went back through eggmansworld.github.io/TeknoParrot's structured per-vendor GPU status fields (a clean enum, not free text) and found 16 games confirmed not to work on AMD and 45 on Intel (verified directly against the live data; NVIDIA has none).

Every AutoSync/Register run now silently auto-detects your GPU vendor and flags any registered game confirmed broken on that vendor in ACTION REQUIRED. Informational only -- no fix to apply, just earlier confirmation that something is a known limitation rather than a setup mistake.

---

## v0.89 BETA (2026-06-18)

Verified the v0.88 compatibility tables against the new structured replacement for the old game notes document ([eggmansworld.github.io/TeknoParrot](https://eggmansworld.github.io/TeknoParrot/)) and found two genuinely new cases:
- **Yu-Gi-Oh! Duel Terminal 6** (YugiohDT6U) -- its own 64-character path limit.
- **Tekken Tag Tournament 2** (ttt2) -- needs `EBOOT.BIN` at CRC32 `3DD05100`, not `919F19EC`. The version-pin check is now generalized to any per-game filename, not just `iDmacDrv32.dll`.

Other CRC mentions in the new source describe known-valid alternate file versions or antivirus false positives, not "broken version" cases -- not added.

---

## v0.88 BETA (2026-06-18)

**New feature: [[BepInEx]] update check (mode 8)**

Checks every registered game that already has BepInEx installed against the latest stable release on GitHub and offers a single batched update. Never installs BepInEx fresh, never touches a 32-bit install, never uses a pre-release build. Backs up the existing install before overwriting anything.

**Baked into the script: two automatic compatibility checks**

These used to live only in a separate game-notes document that won't be available going forward. They now run automatically on every AutoSync/Register run as new ACTION REQUIRED items, with step-by-step fix instructions:
- **Raw Thrills path-length limits** -- specific older titles fail to launch if their install path is too long for that engine era. The script tells you the exact short folder name to rename to.
- **iDmacDrv32.dll version pins** -- five BlazBlue-series games need a specific OLDER DLL version (a newer one causes a coin error). The script checks the CRC32 and tells you the required version and where to get it.

**Documentation fixes:** README.md (the GitHub homepage) was missing the entire Force Feedback section from v0.87 -- fixed, along with several stale mode-number references and a factual error in the staging-folder network-drive rule.

---

## v0.87 BETA (2026-06-17)

**New feature: [[FFB Setup]] (mode 7)**

Two independent force feedback mechanisms, both optional:
- **FFB Blaster** -- TeknoParrot's own built-in force feedback. Paywalled (requires a paid membership), field discovered dynamically, backed up before writing.
- **Third-party plugin** ([mightymikem/FFBArcadePlugin](https://github.com/mightymikem/FFBArcadePlugin)) -- free, no subscription, the per-game DLL table and DLLs are fetched live from GitHub every run.

Real overlap between the two turned out to be substantial (roughly half the third-party table also has a native FFB Blaster field). Too many for a per-game prompt, so the script lists every overlapping game once and asks a single question: keep native for all of them, or use the plugin for all of them. See [[FFB Setup]] for full details.

**Menu reorder:** modes renumbered so related features sit together -- see the updated tables on [[Home]] and [[Quick Start]].

**Bug fix:** the Eggman dat collection's source repo (Eggmansworld/Datfiles) posted its final release and moved to Eggmansworld/TeknoParrot, which uses date-based release tags instead of a fixed tag. The script now queries that repo's "latest" release instead -- dat downloads would otherwise have silently stopped working.

---

## v0.86 BETA (2026-06-17)

**Bug fix: silently-dropped games when a sibling sharing their exe was already registered**

For shared-executable games (Raw Thrills' `sdaemon.exe` and similar), a folder whose name didn't fuzzy-match well used to be skipped entirely if ANY sibling sharing that exe was already registered -- even though the folder's own game was a different title that was never actually registered. It vanished completely: not registered, not flagged, not even logged. Found from a real run where X-Games Snowboarder and Winter X Games never appeared anywhere. Fixed: only the folder's own best-guess candidate being already registered now counts as "handled".

---

## v0.85 BETA (2026-06-17)

**Bug fix + four follow-on enhancements**

- Fixed a false-positive "duplicate profile" report that could affect shared-executable games (NESiCAxLive's `game.exe` and similar). A folder whose own name didn't fuzzy-match well would incidentally mark unrelated already-registered titles as "claimed" while scanning the shared candidate pool; when that title's own folder was processed later, it got wrongly flagged as a conflict even though it was already correctly registered. One real run hit ~140 false positives from this. Now fixed by snapshotting which codes existed before the run started.
- dgVoodoo2 per-game config override: `dgVoodoo2Presets\<ProfileCode>.conf` overrides the global config for one game, always overwriting (unlike the global conf, which never overwrites).
- Interactive duplicate-profile resolution: right after registration, genuine same-run conflicts (e.g. multiple ROM revisions sharing one profile) can now be resolved on the spot with [K]eep / [S]witch / [Q]uit, instead of requiring a trip to TeknoParrotUI.
- New mode 8: Library health check -- read-only, reports valid/broken/empty profile counts. No extraction, registration, repair, or network access.
- Bounded timeout on the GPU-vendor detection WMI query, consistent with the v0.83 network-drive fix.

---

## v0.84 BETA (2026-06-17)

**New feature: per-game ReShade presets**

- Mode 5 (ReShade setup) previously applied one preset choice to every selected game in a run. Added `ReShadePresets\<ProfileCode>.ini`: a file named by profile code overrides the global preset for that one game only, falling back to the global choice for every other selected game.
- Same convention as `CustomThumbnails\<ProfileCode>.png` -- validated against registered profiles, with a `WRONG NAME` warning for typos.
- The end-of-run summary now reports how many games received a per-game override.

---

## v0.83 BETA (2026-06-17)

- `Test-IsNetworkPath` used a WMI query (`Get-CimInstance -ClassName Win32_LogicalDisk`) to classify drive letters. WMI queries against a mapped network drive that has dropped off the network or gone to sleep can hang 20-30 seconds before timing out, stalling the script at startup during the drive scan. Replaced with `[System.IO.DriveInfo]::GetDrives()`, which classifies drive type via a local Win32 call instead of a WMI round-trip.

---

## v0.82 BETA (2026-06-17)

- `Get-ReShadeLatestVersion`'s regex required exactly three dot-separated version components. Verified live against reshade.me -- it currently serves a 3-part version, so today's behavior was correct, but the regex would have silently truncated a future 4-part release instead of erroring. The capture group now accepts an optional fourth segment.

---

## v0.81 BETA (2026-06-17)

- Fixed recurring version drift: the GitHub API User-Agent header was hardcoded to a stale `TeknoParrot-Manager/0.76` in two places (same class of bug fixed once before at v0.71). All GitHub API calls and the startup banner/log now read from a single version variable.
- Hardened profile discovery against the upstream `teknogods/TeknoParrotUI` repository ever renaming its default branch: the script now queries the repo's actual default branch via the GitHub API instead of hardcoding "master", falling back to "master" if that lookup fails.

---

## v0.80 BETA (2026-06-17)

**Registration fix: duplicate profile codes no longer silently dropped**

- Fixed a bug where games whose executable name (or dat/folder match) resolves to a TeknoParrot profile code already claimed by another folder in the same run were silently dropped -- no entry in Registered, Already, Ambiguous, or Unmatched. This hit any game with several on-disk variants sharing one generic exe name and one TeknoParrot profile (multiple Virtua Fighter 5 Lindbergh ROM revisions, multiple Taiko no Tatsujin versions, multiple Star Wars Battle Pod releases).
- These "duplicate profile code" conflicts now appear in the REGISTER THESE GAMES IN TEKNOPARROTUI action item, naming which folder already holds the profile.

---

## v0.79 BETA (2026-06-17)

- Saved configuration with a blank TeknoParrot root or games install folder is now treated as corrupt and falls through to manual prompts, instead of silently reusing empty values.
- AutoSync: added a path-containment guard on the resolved extraction folder before destructive use, matching the defense-in-depth pattern already used everywhere else a script-controlled folder is joined with an externally-influenced name.
- Fixed stale version numbers in project docs.

---

## v0.78 BETA (2026-06-16)

**Additional fixes**

- `PCSX2.ini` is now backed up (`.bak_<timestamp>`) before Crosshair setup rewrites its `cursor_path` entries, same as other config/profile writes.
- Added guard comments above every backup/restore pipeline explaining why `-LiteralPath` is unnecessary there today (the pipeline already passes resolved file objects, bypassing wildcard expansion) and flagging that it must be added back if a future refactor swaps the source for raw path strings.

---

## v0.77 BETA (2026-06-16)

**Fixes**

- GPU fix setup (mode 7) now backs up UserProfiles to `FullBackup\GpuFix_<timestamp>` before writing vendor-fix fields. Previously this mode had no backup step at all when reached directly from the main menu.
- HyperSpin export's final write is now atomic, with a Delete+Move fallback for environments where `File.Replace`'s 3-argument overload throws.
- Fixed a stale User-Agent version literal sent with GitHub API requests.

---

## v0.76 BETA (2026-06-16)

**Control propagation safety**

- Before the "Propagate controls now?" prompt, the script lists each reference game's carried aim-mode settings (relative input, sensitivity, hide-cursor, "Use Keyboard/Button For Axis") alongside its bound count and device, since these settings copy to every other game of that type.
- Added automatic red WARNING flags for known device-mismatch patterns: "Use Keyboard/Button For Axis" = True on a driving reference, "Use Relative Input" = True on a lightgun reference, and any carried sensitivity value of 0. All three usually mean the reference game was bound with a substitute device (keyboard/mouse) rather than its real hardware. See [[Register]] for details.

---

## v0.74 BETA (2026-06-16)

**README restructure (no script changes)**

- Added **Who is this for?** section near the top so readers can immediately judge whether the script suits their setup.
- Condensed **How fuzzy matching works** to a plain decision table. Full algorithm details moved to a new appendix at the end of the README.

---

## v0.73 BETA (2026-06-16)

**Download retry logic**

- Added retry loops (up to 3 attempts) to all four network download sites: the GitHub profile-set query, the Eggman dat release query, the Eggman dat ZIP download fallback, and the thumbnail download loop. 5xx/connection errors retry with a delay; 4xx errors (e.g. rate-limits, 404) fall through immediately without retrying.

---

## v0.72 BETA (2026-06-16)

**Comment audit pass 2 + bug/security hardening**

- Log writes now use BOM-less UTF-8 consistently (previously used the system default encoding, which silently corrupted non-ASCII game names/paths in the log).
- HyperSpin export and config load both hardened against PS 5.1's `ConvertFrom-Json` returning `$null` instead of an empty array/object for empty input.
- AutoSync failure-path cleanup now guards against an empty extraction path before `Remove-Item`.

---

## v0.71 BETA (2026-06-16)

**Comment audit, bug fixes, and security hardening**

- Corrupt UserProfile XMLs and corrupted HyperSpin JSON files were previously skipped silently; both now log the failure before continuing.
- Added `IsNullOrWhiteSpace` guards before `Get-ChildItem -LiteralPath` calls in the AutoSync game pickers, replacing a hard crash on an empty path with a graceful "no ZIPs found" message.

---

## v0.70 BETA (2026-06-16)

- **Critical fix**: config saves from ReShade/dgVoodoo2 setup (modes 5/6) were silently dropping the Eggman dat fields (`EggmanDatZip`, `DatFilePath`, `SupplementaryDatPath`, `IncludeSupplementary`) on every write, permanently disabling dat-based registration after running either mode.
- Security: XPath field-name interpolation in cursor-hide and input-API setters is now escaped consistently via `ConvertTo-XPathStringLiteral`, matching the existing GPU-fix pattern.
- Fixed a NAS ZIP size comparison that mismatched types for files over 2.1 GB in PS 5.1.
- README/QuickStart corrections: ReShade DLLs are not bundled in the release ZIP (users must obtain them from reshade.me); fixed a wrong config filename reference; documented that `spinner` is never auto-detected and must be set via `familyOverride`.

---

## v0.69 BETA (2026-06-14)

**Bug fix: supplementary ZIP source prompt now re-appears after a prior skip**

- Fixed the supplementary source prompt being silently skipped when the user had previously pressed Enter to skip it. The v0.68 fix saved an empty string to suppress re-prompting, but this left users with no way to add a supplementary source on a later run without editing the config JSON manually. The prompt now fires whenever the supplementary path is not configured (null or empty), regardless of prior skips.

---

## v0.68 BETA (2026-06-14)

**Bug fixes: AutoSync crash and ZIP source paths not saved between runs**

- Fixed a crash at AutoSync startup: the queue-status header used `(if ...)` inline as a cmdlet argument, which PowerShell 5.1 does not allow. Changed to `$(if ...)` subexpression syntax.
- Fixed the main collection ZIP folder and supplementary ZIP folder not being remembered between runs. Both are prompted inside the main menu loop after the initial config save runs, so they were always written as null/empty. A config re-save now fires immediately after the paths are captured.
- Fixed the supplementary folder prompt repeating every run when the user had explicitly skipped it. A deliberate skip (pressing Enter) is now saved as an empty string and distinguished from "never asked" so the prompt does not reappear.

---

## v0.67 BETA (2026-06-14)

**Bug fix: D (Done) with empty queue now works correctly**

- Pressing D with no games in the queue now proceeds correctly instead of blocking with "Queue is empty." D always means "proceed with what I selected" -- an empty queue extracts zero games. Use **A** to extract everything.
- In the combined picker (main + supplementary), selecting games from the main collection but nothing from supplementary now correctly **skips supplementary extraction**. Previously D with an empty supplementary queue would extract all supplementary games.
- `Expand-ZipFileSafe` archive handle leak fixed: `ZipFile::OpenRead` is now inside the `try` block so a failure cannot leak the handle.

---

## v0.66 BETA (2026-06-14)

**AutoSync: combined picker, extraction progress bar, network staging**

- Game selection now combines the main collection and supplementary library into one A-Z list. Supplementary entries are marked `[+]` and the header shows per-source counts. No more two separate menus back to back.
- A real-time progress bar now shows file count and percentage during each extraction. Previously the screen showed a blinking cursor with no feedback.
- The staging folder can now be on a network drive. The previous hard error is replaced by a write-speed benchmark: the script measures throughput, rates it, and asks Y/N whether to proceed.
- Supplementary source validation now runs before the picker so errors appear before you're asked to make a selection.

---

## v0.65 BETA (2026-06-14)

**Bug fix: AutoSync supplementary source prompt now shown correctly**

- The supplementary ZIP folder prompt was being suppressed when the user accepted a saved configuration that predated the supplementary feature. Users with an existing config that had no supplementary folder set would never be asked to configure one. Fixed so the prompt now appears whenever the supplementary source is not configured, mirroring the behavior of the main collection prompt. In Unattended mode the prompt is still skipped (configure it interactively first).

---

## v0.64 BETA (2026-06-14)

**Registration improvements: .xbe/.dll scanning and profile code fuzzy pass**

- `.xbe` and `.dll` files are now included when scanning for game executables. Sega Chihiro games emulated via cxbxr (Virtua Cop 3, OutRun 2, Ollie King, etc.) use `.xbe` files; Konami PC arcade games (DanceDanceRevolution 2013, Steel Chronicle, Silent Scope Bone Eater, Metal Gear Arcade, Love Plus Arcade) use a game-specific `.dll`. Both were previously invisible to the scanner.
- A third registration pass now Dice-matches normalized folder names against normalized GameProfile code names. This catches games with an empty `<ExecutableName>` in their profile (BladeStrangers, LuigisMansion, MaiMaiGreen, PokkenTournament, ProjectDiva, SonicDashExtreme, StreetFighterVTypeArcade, HydroThunder, and others) that fell through the exe-index and dat passes.

**Security / reliability**

- TLS protocol now uses bitwise OR so existing protocols (e.g. TLS 1.3) are preserved rather than replaced. Redundant per-function TLS lines removed.
- Eggman dat download fallback updated from deprecated `WebClient.DownloadFile` to `Invoke-WebRequest`.
- dgVoodoo2 API scan now logs profile parse errors instead of discarding them silently.

---

## v0.63 BETA (2026-06-14)

**AutoSync ZIP source: subdirectory hint and clearer prompts**

- When the configured ZIP source folder contains no ZIP files at the top level, AutoSync now scans one level of subdirectories and lists any that do contain ZIPs — so you can immediately see the correct path to enter. This covers both interactive and unattended mode, and applies to the main collection source and the supplementary source.
- The ZIP source path prompts now include a note that the path must point *directly* at the folder containing the ZIP files (not a parent folder), plus an example path.

---

## v0.62 BETA (2026-06-14)

**Supplementary game library support in AutoSync**

- AutoSync now supports a second optional ZIP source folder for the TeknoParrot Supplementary collection. When configured, a separate game picker and extraction pass runs after the main collection, both extracting into the same staging folder and sharing the same sync-state file. The supplementary ZIP source is saved to config so subsequent runs use it automatically without re-prompting.

---

## v0.61 BETA (2026-06-14)

**EggmanDat URL validation fix**

- Fixed a regex bug in `Get-EggmanDatRelease` that caused every automatic Eggman dat download attempt to fail with "unexpected download URL format". The pattern required at least one character before `github.com`, so standard GitHub release URLs (`https://github.com/...`) were rejected. Changed quantifier from `+` to `*` so bare `github.com` and subdomain URLs (e.g. `objects.githubusercontent.com`) are both accepted.

---

## v0.60 BETA (2026-06-14)

**Global error handler**

- The main menu loop is now wrapped in a top-level `try/catch`. Any unhandled exception is caught, logged in full to `TeknoParrot-Manager.log`, and shown on screen with a "FATAL ERROR" banner and a prompt before the script exits. Previously such exceptions produced a raw PowerShell red-text dump with no log entry.

---

## v0.59 BETA (2026-06-14)

**GitHub profile set resolution, supplementary dat as priority overrides**

- The script now fetches the full list of GameProfile XML filenames from the teknogods/TeknoParrotUI GitHub repository before every registration run. The fetched set is used to validate and resolve dat profile codes before they are written to UserProfiles.
- Supplementary dat entries can now act as priority overrides: when the main dat has no match but the supplementary dat does, the supplementary profile code is used.

---

*For older versions see the full [CHANGELOG](https://github.com/Jumpstile/teknoparrot-manager/blob/main/TeknoParrot-Manager-CHANGELOG.txt) in the repository.*
