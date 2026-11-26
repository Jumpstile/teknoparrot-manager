# Troubleshooting

Find the problem that looks like yours, then follow the steps under it. Press `D` on a result screen to see the details. The full story is also in the log, `TeknoParrot-Manager.log` (in `TeknoParrotManager\Logs` inside your TeknoParrot folder).

If you are stuck, make a package with **17) Create Support Package** and ask for help. See [[Support Package]]. Questions and bug reports go to the [issues page](https://github.com/Jumpstile/teknoparrot-manager/issues).

---

## A game will not start

**It needs files TPM does not provide (firmware, BIOS, or settings files).**
TPM checks for these before you start a game and says which games will not start. It never downloads them. It can copy them from your own game collection after checking them against the DAT list. To let it check, say yes when it offers to get the DAT list.

- **Arcade games on PlayStation 3 style hardware (RPCS3):** some arcade games (for example the Tekken 6 arcade games) need this. Put the firmware file (`PS3UPDAT.PUP`, in the `[EMU] Sony PlayStation 3 Firmware` ZIP) in your collection. Run TPM again and answer `Y` when it offers to install it. This takes about a minute and no window opens.
- **Play! games:** each game needs its own small settings file (`.arcadedef`). Put the `[EMU] Play! working arcadedefs` ZIP in your collection, run TPM again, and answer `Y` when it offers to copy the files.
- **Chihiro games:** four BIOS files are needed. They come from the `[EMU] CxbxR BIOS Firmware for Sega Chihiro` ZIP.
- **PCSX2x6 games:** two firmware files are needed. They come from the `[EMU] PCSX2x6 Emulator BIOS Files` ZIP.

See [[Game Startup Files]]. For the optional CPS3 step, see [[CPS3 First-Boot Files]].

**A game shows in TeknoParrotUI but will not launch.**
Its path may point to the wrong `.exe`, or the game was not fully extracted. In TeknoParrotUI, point the game to the right `.exe`. Or run TPM and answer `Y` to `Check for and repair broken game paths now? (Y/N)`.

**The game folder path is too long.**
TPM finds and reads games in very long folder paths (over 259 characters). But installing add-ons into one stops with a message and changes nothing. Move the game to a shorter folder and try again. If a restore says the path is too long for Windows, move TeknoParrot to a folder with a shorter path.

**Library health check says a game is `not available yet`.**
TeknoParrot lists that game as development only, so it cannot be played yet. Nothing is wrong with your setup. Try again after TeknoParrot releases it.

**Library health check says a game needs you to pick the game file by hand.**
The game's profile names no game file, and TeknoParrot has no setup file for it, so TPM cannot find it. Open the game in TeknoParrotUI and set its game file.

**Library health check says the emulator for a game type is not in your TeknoParrot folder.**
Each game type has its own emulator folder inside your TeknoParrot folder. Update TeknoParrot so that folder is there, then run the check again. A game type TPM does not know is named too. Its games may still run.

---

## Registration

**A game does not show up in TeknoParrotUI.**
Read the ACTION REQUIRED part at the end of the run. The game may need manual registration (it shares an `.exe`, or another copy already claimed its profile), or it is not extracted yet. If neither fits, look in the log for a registration error for that game.

**A game was registered with the wrong profile.**
Copy that game's `.xml` from `UserProfiles` to a safe place first. Then choose the correct profile and path in TeknoParrotUI. Do not delete a profile just to try matching again.

**A game shows up twice.**
Two profile files may exist for one game. Compare their paths and settings, keep copies of both, and remove only the one you are sure is a duplicate.

**A TeknoS11 arcade game was not registered.**
Some games name two ZIPs: the game's own ZIP and a parent ZIP. They must sit in the same folder. A folder that holds only the parent ZIP does not register the game. Put both ZIPs in one folder, then run Register again. See [[Register]].

**TeknoParrot's own first-time setup is not finished.**
TPM says so in ACTION REQUIRED with the path to `TeknoParrotUi.exe`. Open it, choose your DAT file when it asks, let it scan for games, and set up your controls.

---

## AutoSync

**A game does not extract.**
Check that the ZIP folder is right and the ZIP is not damaged, and that the games drive has free space. A failed extraction leaves no half-made folder, so the next run tries again. Open Details and read the log before you retry.

**My saves or settings in a game folder are gone.**
AutoSync leaves a game folder alone when its ZIP did not change. When a changed ZIP does replace a folder, every file in the old folder that is extra or different from the ZIP (saves, settings, ReShade files) is copied first to `TeknoParrotManager\Backups\AutoSyncReplaced`. Copy what you need back from there.

**AutoSync skipped a game and left the old folder as it was.**
It could not save the extra files first, or no Backups folder is set up. Nothing was changed for that game. Close programs that may be using the folder (a virus scanner, for example), check the free space and the Backups folder, and run AutoSync again.

**A game extracts again on every run.**
An extraction was cut short. Read the log and check the free space and the ZIP before you retry. Do not delete the `.extracting` marker just to hide the warning.

---

## Controls

**Controls were not set up for a game.**
The game may not have a controller choice that TPM can set, TeknoParrot's saved settings for it may be an older version (open the game once in TeknoParrotUI), or a button TPM wants is already used by another control in that game. TPM leaves such a game alone and says why on the screen. See [[Controls]].

**A game's controls are wrong after setting them up.**
Use **15) Restore backup** and look at the list before you restore. Then pick a different layout in [[Controls]], or fix the game in TeknoParrotUI.

TPM does not promise working controls, full-screen mode, firmware, or a game that starts. Map and test the controls in TeknoParrot and read ACTION REQUIRED.

---

## Check for Updates

See [[Check for Updates]].

**"Could not check for updates (GitHub was unreachable or returned no usable release)."**
Your copy is unchanged. Try again later.

**I run a build before RC8.1 (such as RC8 or RC7) and the update does not install.**
Builds before RC8.1 cannot install a whole release. This is a one-time step. Download the newest release ZIP from the [releases page](https://github.com/Jumpstile/teknoparrot-manager/releases) and extract all of it over your TeknoParrot Manager folder. After that, Check for Updates installs releases for you.

**"There is not enough free space for the update."**
Nothing was installed. Free some space on the drive that holds TeknoParrot Manager and try again.

**"The update was not installed ..."**
TPM checks the download against the published SHA-256 value and looks inside the ZIP first. If the ZIP has no script, or does not match the published file, it stops. Your current copy is not changed. Try again later or download the release ZIP yourself.

---

## PostgreSQL setup

See [[Postgres Setup]].

**It asks for the PostgreSQL password.**
Choose `F` and type the existing password. TPM checks it and saves it. If nobody knows it and `X` is offered, choose it: it explains the manual steps and changes nothing. You can leave a password prompt by pressing Enter.

**Golden Tee, Power Putt, Silver Strike Bowling, Target Toss or Orange County Choppers Pinball is skipped, or its database is not mentioned.**
The game's profile is set to Internal storage (the new default). It needs no PostgreSQL. Start the game once and it makes its own database. Postgres setup and the health check skip it on purpose. Only games set to Existing PostgreSQL (or older profiles with no Storage box) use this page.

**Windows asks for permission, or setup says Administrator is needed.**
Setup tells you what it will ask for and waits for you to press Enter before the Windows window opens. Read it, then press Enter. Click Yes in the Windows window and approve it with an administrator account of this PC. If your Windows account is not an administrator, close TPM and start it again with "Run as administrator". Then read the result before you try again.

**It says a game could NOT be made ready.**
That game has no starting database file (`pg_backup`), and its profile does not say TeknoParrot creates the database itself. Put its `pg_backup` folder back and run Postgres setup again. The other games are still set up. (A Golden Tee Live 2018 or newer game, or a PGA Tour game, says `Profile ready` instead: start it once.)

**"PostgreSQL did not finish installing" or "PostgreSQL setup did not complete successfully".**
The screen says what happened to your data. Press `D` for why, and open View Log. If setup lists PostgreSQL items it found on this PC, read the warning before you delete anything. A PostgreSQL folder can hold game databases and saved scores.

---

## ReShade

See [[ReShade]].

**ReShade does not work on a game.**
ReShade works with both 32-bit and 64-bit games. Games that run through BudgieLoader (a Linux-style game format) are skipped for now, and nothing in their folder changes. Press `D` on the result to see why a game was left alone.

**The Home key does not open ReShade.**
ReShade may not be installed for that game, or the game uses Home for something else. Change `KeyOverlay=` in the game's `ReShade.ini`.

**The picture looks doubled with a CRT look.**
The game may already use TeknoParrot's own CRT look. When you pick a look, TPM asks whether to turn TeknoParrot's off for that game (`[T]`) or keep it. To bring it back, use ReShade > Undo ReShade changes, or Restore backup.

**A bezel is not shown, or a game is skipped in the bezel step.**
The bezel step (menu 6, then `B`) needs ReShade set up for the game first. A game that shares its folder with other games is skipped. A Low match or a different sequel number is not applied unless you pick it. TPM puts the file where ReShade looks for it, but it is not confirmed that every game shows it. See [[ReShade]].

---

## Other messages

**BepInEx says the game folder is unsafe.**
The game must be inside your games folder and must not contain a junction or symlink. Fix the profile path or remove the link, then run item 10 again. Nothing is downloaded or written meanwhile.

**BepInEx says "TPM TRANSACTION ROLLBACK FAILED".**
TPM could not prove it undid its own changes. Do not retry. Close TeknoParrot, keep the `BepInEx_Backup_<id>` folder inside the game folder, and ask for help. See [[BepInEx]].

**It says LaunchBox or BigBox is still open.**
Close it, then press Enter to check again, or type `N` to cancel. TPM never closes either app. See [[LaunchBox Integration]] and [[Restore Backup]].

**A LaunchBox restore says PARTIAL, or lists "Needs review".**
Some files were not verified or were left in place on purpose. Keep the reported backup and every listed file, do not retry blindly, and open Details or make a support package. See [[Restore Backup]].

**A LaunchBox game has a `Needs setup` note, or is in a `Needs setup` playlist.**
That game cannot start yet: its game file, firmware or BepInEx is missing. Fix that (see [[Health Check]] and [[Game Startup Files]]). The note and the playlist entry go away by themselves when the problem is fixed. Notes you wrote yourself stay.

**The Eggman DAT update says the current DAT is protected.**
TPM will not save a DAT inside your TeknoParrot folder, your games folder or the folder TeknoParrot Manager runs from. Choose a different folder (for example your ZIP folder) and try again.

**Start-up stops with "needs review" or "the registration evidence ledger is ...".**
TPM could not safely check one of its own files. Keep every file and path it prints, make a support package, and ask for help. See [[Registration Ledger]].

**The console shows `[UNLOGGED]`.**
The log file cannot be written. Make sure the TeknoParrot folder is not read-only. The lines are still shown on screen, but they are not saved to the log, so copy anything you need from the screen first.

**TPM asks for my settings again.**
You pressed `N` at `Use these settings?`, or the settings file was deleted or damaged (`WARNING: Saved configuration could not be read`). Answer the questions again. To start fresh, see "Resetting" in [[Setup]].
