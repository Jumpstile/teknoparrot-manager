# Troubleshooting: common beginner problems

Find the problem below that matches what you see. Each problem has a short fix with numbered steps.

Before you try again, keep the exact error message and the log. Do not delete game setup files, saved copies, records, or leftover marker files just to force a retry.

[Start here](START-HERE.md) explains setup. Its [glossary](START-HERE.md#glossary) explains the words.

Many result screens offer **D** for Details. Type **D** and press **Enter** to see the full technical information. It is also saved in the log.

The log is here: `<TeknoParrotFolder>\TeknoParrotManager\Logs\TeknoParrot-Manager.log`.

`<TeknoParrotFolder>` means your chosen installation folder. It is not text to type.

### More detail

- Reports normally live in the folder next to the log, named `Reports`.
- Early start-up may log beside the TeknoParrot Manager script, before the TeknoParrot folder is known.

## 1. Nothing is found

Symptom: TeknoParrot Manager cannot find any games to add. You may see one of these messages:

- AutoSync says `No game ZIPs found directly in this ZIP folder.` (sometimes followed by `Tip: these folders inside it contain ZIPs -- choose one of them as your game ZIP folder:`)
- AutoSync says `All games in this ZIP folder are already extracted. Nothing left to extract.` followed by `To register games that are already extracted, choose Register only from the main menu.`
- Register only says `The games folder TeknoParrot Manager recommended does not exist yet.`

Cause: you picked the wrong folder, your games are already extracted, or the folder you gave does not exist.

Fix:

1. Open the folder it shows in File Explorer.

   You will see: what is inside the folder.

   Next: check whether your game ZIPs are directly in it.

2. For AutoSync, select the folder that directly holds your own game ZIPs.

   You will see: your ZIPs listed. TeknoParrot Manager may also list child folders that contain them.

   Next: choose the right one.

3. For games that are already extracted, choose **2) Register only** and give their existing parent folder. Choose **R** to select another games folder when offered, or **Q** to return.

   You will see: the games found in that folder.

   Next: continue with the preview.

4. If your archives are `.rar` or `.7z` files, extract them yourself first. Then use Register only. AutoSync tells you when it skips one.

   You will see: your extracted game folders.

   Next: run Register only on them.

5. Apply the changes and read the real result. A preview alone does not add games.

   You will see: the result of the real run.

   Next: check TeknoParrotUi.exe for the game.

Expected result: the game you want is listed for extraction or registration. Or TeknoParrot Manager says it already has nothing to extract.

### More detail

- AutoSync looks for game ZIPs directly inside the selected source folder, not in other nested folders.

## 2. A game is not matched

Symptom: TeknoParrot Manager does not recognize a game folder. You may see this message: `3 game folder(s) not matched to a TeknoParrot profile -- see the ACTION REQUIRED list saved below.`

The report may show `GAME FOLDERS NOT MATCHED TO A TEKNOPARROT PROFILE` or `REGISTER THESE GAMES IN TEKNOPARROTUI`. The end-of-run summary may show `3 game folders were not recognized by TeknoParrot.` (for one game: `1 game folder was not recognized by TeknoParrot.`).

Cause: TeknoParrot Manager found no ready-made game setup file (a profile) that fits the game's program file. This does not mean TeknoParrot will never support the game.

Fix:

1. Open **TeknoParrotUi.exe** yourself at least once ([first-run steps](START-HERE.md#3-open-teknoparrotui-once)). Then close it again.

   You will see: TeknoParrotUI's main window, then it closes.

   Next: make sure TeknoParrot is up to date.

2. Make sure TeknoParrot is up to date.

   You will see: the newest TeknoParrot you can get from its official sources.

   Next: run Register only again.

3. Run **Register only** again, with the correct TeknoParrot folder selected.

   You will see: the preview and the matches.

   Next: read ACTION REQUIRED.

4. Read ACTION REQUIRED. Check that the game's program file (its .exe) is in your extracted game folder.

   You will see: the games that were not matched, with a reason.

   Next: if a list of candidates is offered, go to step 5. If not, go to step 6.

5. If TeknoParrot Manager offers candidate game setup files, choose only the one you can identify. Otherwise leave the match unresolved.

   You will see: that game's checked result, or an item left unresolved.

   Next: go to step 6 only if the report asks for manual registration.

6. If the report asks for manual registration, use TeknoParrotUI's add-game action and select the correct .exe.

   The legacy official guide calls the actions **Add Game** and **GAME SETTINGS**. Current labels may differ.

   You will see: the game in TeknoParrotUI's list.

   Next: if you think a match was wrong, go to step 7.

7. If you suspect a wrong match, first make a copy of that game's settings file from UserProfiles (TeknoParrot's saved game settings folder). Keep the copy outside UserProfiles. Do not delete the XML file just to retry.

   You will see: your copy saved safely.

   Next: correct the setup file or path.

Expected result: a checked registration, or a clear unresolved item. The optional DAT (a list of game names) may improve matching. It cannot add support for an unsupported game.

### More detail

- Other possible causes: several games share the same executable name, the wrong game build was selected, or the folder is a utility rather than a supported game.
- Preserve the affected UserProfile and its settings outside UserProfiles before correcting the profile or path.
- TeknoParrot Manager does not update TeknoParrot, check profile freshness, or open TeknoParrotUI for you.

## 3. TeknoParrot profiles are missing or old

Symptom: a supported game will not match. Or registration says `ERROR: No usable profiles found in GameProfiles.` and `Check that this is the folder where the TeknoParrot installer put TeknoParrotUi.exe. Its GameProfiles come with TeknoParrotUI: install it with the official TeknoParrot installer (TeknoParrotUI [REQUIRED], Download Selected), then retry.`

Cause: TeknoParrot is out of date or was not fully installed, you selected the wrong folder, or the ready-made game setup files in `GameProfiles` cannot be read.

Fix:

1. Find **TeknoParrotUi.exe** in the installation you selected for TeknoParrot Manager.

   You will see: a `GameProfiles` folder next to it. The official installer puts it there.

   Next: open TeknoParrotUi.exe.

2. Open TeknoParrotUi.exe yourself once. Click through its first-run boxes (OK, OK, Accept and Continue). Then close it.

   You will see: the main window, then it closes.

   Next: update TeknoParrot.

3. Make sure TeknoParrot is up to date. Follow TeknoParrot's official guidance for updating.

   You will see: the newest TeknoParrot.

   Next: run Register only again.

4. Run **Register only** again against that same installation.

   You will see: the preview and the matches.

   Next: if `GameProfiles` is still empty or unreadable, go to step 5.

5. If `GameProfiles` is still empty or unreadable, fix the TeknoParrot installation or update through its official guidance. Then retry registration.

   You will see: the problem gone, or a clear message from TeknoParrot.

   Next: run Register only again.

Expected result: the ready-made game setup files are available for matching. TeknoParrot Manager does not install or repair TeknoParrot.

### More detail

- TeknoParrot Manager no longer runs a separate check for stale or missing profile notices. It no longer offers to open TeknoParrotUI.
- Verified on 2026-10-31: the official installer delivers TeknoParrotUI including `GameProfiles`.
- How TeknoParrotUI updates itself later was not verified. Re-running the installer over an existing folder was not verified either.

## 4. The folder path is too long

Symptom: ACTION REQUIRED says `PATH TOO LONG -- THESE GAMES MAY FAIL TO LAUNCH`. Or a file operation reports `Could not find a part of the path`.

The second message can also mean a folder is missing. It does not always mean the path is too long.

Cause: some games cannot handle a long folder path. Or deeply nested folders are too long for a Windows file operation.

Fix:

1. Make a copy of the affected game's settings file (an XML file in UserProfiles) and any current settings you need. Keep the copy outside the folders you are about to change.

   You will see: your copy saved.

   Next: close the programs.

2. Close TeknoParrotUI and the game.

   You will see: both are closed.

   Next: shorten the game's folder path.

3. Follow TeknoParrot Manager's suggested short folder name for a listed game. Shorten the parent folders too if needed, for example `C:\Games\ShortName`.

   You will see: the game in its shorter folder.

   Next: tell TeknoParrot the new path.

4. In TeknoParrotUI, update that game's saved executable path (GamePath).

   You will see: the new path saved.

   Next: run TeknoParrot Manager's path repair if needed.

5. Use TeknoParrot Manager's path repair if needed. Then launch and test the game.

   You will see: the game starting, or a clear message.

   Next: you are done. If the problem was a backup failure, go to step 6.

6. For a backup-path failure (not a game warning), keep every backup and evidence path shown. Read the full log before moving an installation or retrying.

   You will see: the reason in the log.

   Next: fix that reason, then retry.

Expected result: the game points at the shorter existing path. TeknoParrot Manager does not rename game folders for you from this report.

### More detail

- A game may have its own short-path limit. That is separate from Windows' limit.

## 5. LaunchBox or BigBox is open

Symptom: TeknoParrot Manager says `Keep closed: Close LaunchBox and BigBox and keep them closed. TeknoParrot Manager never force-closes either app.`

It may wait and check again. It may cancel a library operation if an app is still open or opens again.

Cause: LaunchBox and BigBox can save their own library over TeknoParrot Manager's changes.

Fix:

1. Save your work in LaunchBox or BigBox.

   You will see: nothing unsaved.

   Next: close both apps.

2. Close both apps. Keep them closed until TeknoParrot Manager finishes.

   You will see: neither app running.

   Next: go back to TeknoParrot Manager.

3. If TeknoParrot Manager is waiting, press **Enter** when it asks to check again. If it canceled, start that LaunchBox action again.

   You will see: the LaunchBox action running, or the preview again.

   Next: read the preview.

4. Preview and approve only the changes you want. Read the final result before you open LaunchBox.

   You will see: the final result and backup details.

   Next: open LaunchBox.

Expected result: a checked backup and the library change you asked for. Or an honest "canceled" or "partial" result. TeknoParrot Manager never force-closes the apps.

### More detail

- These checks apply to LaunchBox writes and restores. They are not a general TeknoParrotUI check in Register or AutoSync.
- A small reopen race remains after the last process check: an app could be reopened right after TeknoParrot Manager looks.

## 6. Antivirus blocks a file

Symptom: your Windows security software quarantines a file, blocks it, or a needed program file disappears. This is a Windows or security-program message. It is not one fixed TeknoParrot Manager message.

Cause: the official legacy TeknoParrot guide warns about false alarms. But a warning can also mean the file is unsafe. Do not assume every warning is harmless.

Fix:

1. Read the security program's details and find which file it blocked.

   You will see: the file name and the reason.

   Next: check where the program came from.

2. Confirm TeknoParrot came from the [official download page](https://teknoparrot.com/en/Home/Download). Confirm TeknoParrot Manager came from its [official releases](https://github.com/Jumpstile/teknoparrot-manager/releases).

   You will see: whether your copy came from the official place.

   Next: if you cannot be sure, go to step 3.

3. If you cannot be sure the file is trustworthy, leave it blocked. Ask the publisher or your security program's maker for help.

   You will see: the file stays blocked.

   Next: stop here until you get help.

4. Only if you trust that official copy, you may consider the official guide's exception for the TeknoParrot folder. Use your security program's instructions. Never turn off antivirus for the whole PC. Never exclude all downloads.

   You will see: only the TeknoParrot folder excluded.

   Next: fix any missing files with the trusted package.

5. Fix the detection and any missing files from the trusted package. Then try again.

   You will see: the program running again.

   Next: continue with setup.

Expected result: a trusted program runs, or the suspicious file stays blocked. A folder exception is not proof that a file is safe.

## 7. PowerShell is blocked

Symptom: starting the script says scripts are disabled, a policy warning appears, or the launcher says `Script exited with an error.`

That launcher sentence is generic. Read the error above it. The log is `TeknoParrot-Manager.log`, in the `TeknoParrotManager\Logs` folder inside your TeknoParrot folder. If that folder is not set up yet, it is next to the launcher.

Cause: Windows has a rule (an "execution policy") that stops scripts from running. Or your download is blocked, or a work or school PC forbids it.

Fix:

1. Extract the complete TeknoParrot Manager package to a normal folder. Do not run it from inside the ZIP.

   You will see: the files in a normal folder.

   Next: start it with the launcher.

2. Start it by double-clicking **TeknoParrot-Manager.bat**, not the `.ps1` file.

   You will see: TeknoParrot Manager opening.

   Next: if it opens, you are done. If not, go to step 3.

3. If you deliberately use PowerShell directly, open it in the TeknoParrot Manager folder. Use the one-session command below, only for the trusted official package:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File ".\TeknoParrot-Manager.ps1"
   ```

   You will see: TeknoParrot Manager opening.

   Next: if it is still blocked on a managed PC, go to step 4.

4. If policy still blocks it on a managed PC, ask its administrator. Do not weaken machine-wide policy or security controls.

   You will see: an answer from the administrator.

   Next: follow it.

5. If it closes straight away, reopen it through the `.bat`. Keep the error above it and the log for support.

   You will see: the same message again, or a normal start.

   Next: ask for help with that message. Not every failure is caused by policy.

Expected result: TeknoParrot Manager opens normally, or you have the exact blocking rule or error for support. The normal launcher needs no permanent policy change.

### More detail

- A direct `.ps1` launch may use a restrictive policy. The normal `.bat` launcher already asks for a process-only execution-policy bypass. It cannot override every organization policy.

## 8. A path contains spaces

Symptom: a typed path is not found, or a command treats part of the path as a command.

TeknoParrot Manager has no special error for spaces alone. `ERROR: ZIP source folder not found:` can instead mean a typing mistake or a folder you cannot open.

Cause: the path was typed wrongly, or an advanced PowerShell command did not put quotes around it. Spaces alone do not mean you must rename your folders.

Fix:

1. At a TeknoParrot Manager prompt that offers browsing, type **B** to pick the folder visually.

   You will see: a folder chooser.

   Next: pick the exact folder.

2. Select the folder that was asked for. Do not pick its parent, and do not pick an executable when it asks for a folder.

   You will see: the folder accepted.

   Next: if you type instead, go to step 3.

3. If you type the path, enter the full folder path as one answer, for example `C:\Arcade Games`. If unsure, browse instead.

   You will see: the folder accepted.

   Next: if you use a PowerShell command, go to step 4.

4. In a PowerShell command, put quotes around any path with spaces, for example `cd "C:\My TPM Folder"` followed by `.\TeknoParrot-Manager.ps1`.

   You will see: the command run without a path error.

   Next: check the folder again.

5. Check that the folder exists and you can open it in File Explorer.

   You will see: the folder open.

   Next: try TeknoParrot Manager again.

Expected result: TeknoParrot Manager uses the full path you meant. Short paths are still better for games that cannot handle long paths.

## 9. A network drive is unavailable

Symptom: TeknoParrot Manager says `ERROR: ZIP source folder not found:` followed by a network path. Or it warns that games will be extracted to and played from a network folder.

A disconnected share can produce other access errors too. There is no single message for all network failures.

Cause: the shared folder is disconnected, you have no permission, a mapped drive is missing in this Windows session, or the games destination is on a slow network drive.

Fix:

1. Open the exact source path in File Explorer, using the same Windows account.

   You will see: the folder opens, or an error.

   Next: if it does not open, reconnect it.

2. Reconnect the drive or fix the permission, then try again. Do not put passwords in a command, log, or support report.

   You will see: the folder open in File Explorer.

   Next: choose where games are extracted.

3. Where you can, use a local games folder with enough free space. Your ZIP source can stay on the network. That is different from playing games from a network folder.

   You will see: a local games folder selected.

   Next: check your saved settings if the path changed.

4. If the saved path changed, type **D** at **Use these settings? (Y/N, D = show them)** to see the saved folders. Then type **N** and pick the folders again. Do not delete settings or backups.

   You will see: your saved settings listed, then the question again. After **N**, you will see the folder questions.

   Next: choose the right folders.

5. After an interrupted extraction, keep its marker files and the paths it shows. Look at Details (type **D** when offered) and the log. Fix the reported problem before you try again.

   You will see: the reason in Details and the log.

   Next: retry once it is fixed.

Expected result: the source can be reached and extraction goes where you intended. Or the operation stops with a clear error. A network source affects copying speed. A network games folder also affects play.

### More detail

- Marker files are the state markers TeknoParrot Manager keeps so it can resume safely.

## 10. Restore a backup

Symptom: you need your earlier controls or settings back after a change.

Choose **15) Restore backup** from the main menu. It shows five choices:

- `TeknoParrot UserProfiles backup`
- `Postgres database backup`
- `LaunchBox library backup (verified current-state backup first)`
- `Reset and Restore: put back one game or all games from a restore point saved when TeknoParrot Manager started`
- `Rebuild one game from its ZIP: put one game folder back to exactly what its ZIP holds (your old folder is kept)`

Cause: the current settings are no longer what you want. These are separate kinds of saved copy.

The normal game-settings backup protects only UserProfiles. It does not protect game-side saved machine state (NVRAM), test-menu state, calibration files, or whole games.

Fix:

1. Make a copy of the current files and settings you still need. Keep the copy outside the folders to be replaced. Restoring an older backup can lose later changes.

   You will see: your copy saved.

   Next: close the programs.

2. For a game-settings restore, close TeknoParrot and the game. For a LaunchBox restore, close LaunchBox and BigBox.

   You will see: the programs closed.

   Next: open the restore menu.

3. At the main menu, type **15** to choose **15) Restore backup**.

   You will see: the **Restore from Backup** screen with five numbered choices, plus **B** to go back.

   Next: type **1**, **2**, **3**, **4**, or **5**. Pressing only **Enter** goes back to the main menu.

4. Type **1** for your game settings (UserProfiles).

   Choose **2** only to restore PostgreSQL databases. Choose **3** only for LaunchBox library files. Choose **4** to put back one game or all games from a restore point. Do not choose a database restore just to fix controls.

   You will see: a list headed **Saved copies of your game settings, newest first:**. The newest backup is number 1.

   Next: pick one.

5. Check the folder name and the file count in each row. Normal backups are under `<TeknoParrotFolder>\UserProfiles\FullBackup\`. Type the number you want and press **Enter**.

   You will see: a **You chose:** line with the backup you chose.

   Next: read the warning.

6. Read the warning. A saved copy shown as `older copy, cannot be fully checked` has no completion record, so TeknoParrot Manager cannot prove it is complete. It says games missing from it will be removed and asks you to type **UNVERIFIED**. That one word is the only confirmation. You are not asked to type YES as well.

   You will see: the warning, then the prompt **Type UNVERIFIED to use this copy anyway**. A copy that can be checked shows the prompt **Type YES to confirm** instead.

   Next: confirm only if you are sure.

7. Type exactly what the prompt on your screen shows. If it says **Type UNVERIFIED to use this copy anyway**, type **UNVERIFIED** (you are not asked for YES). If it says **Type YES to confirm**, type **YES**. For LaunchBox, answer **Y** or **N** (default **N**). Any other answer cancels and nothing is changed.

   You will see: the restore running, then **Restore complete.**, or **Restore canceled.**

   Next: if it asks you to close an app, go to step 8. If not, go to step 9.

8. If TeknoParrot Manager asks you to close an app, close it and press **Enter** to check again. If the operation was canceled, restore again after closing the app.

   You will see: the restore start or finish.

   Next: read the final result.

9. Read the final result before you reopen the app. On a partial or failed restore, keep all evidence and ask for help. Do not copy files over it by hand.

   You will see: a banner with **Restore complete.** (for LaunchBox: **LaunchBox restore outcome:** and the result), then **Press Enter to return to menu**.

   Next: test a restored game.

10. Open one restored game and test its controls and settings.

    You will see: the controls and settings as they were.

    Next: you are done.

Expected result: the saved copy you picked is restored and checked. Or TeknoParrot Manager tells you why it stopped.

Undoing a required game patch is separate. Choose **13) Required game patches**, then **U**. It uses the patch record kept for that change. It is not a restore of a whole game.

### More detail

- A LaunchBox restore first makes a verified backup of the current library.
- Folders named `INCOMPLETE_...` are interrupted backups and are never offered.
- A database restore (option 2) also lists its backups newest first. If the restore did not simply succeed, you see a plain line such as `The restore did not finish. Your data is back the way it was. TeknoParrot Manager put everything back and checked it.` Then it asks `Press D for details, or Enter to continue`.
- The Postgres line on the menu reads like this (it shows on two lines): `Postgres database backup (only relevant if you've used the Postgres setup mode)`.
- Option 4 (Reset and Restore) uses restore points. TeknoParrot Manager saves a checked one when it starts, but only when something changed since the last one. The first restore point that has your games in it is always kept. Game files, saves, and databases are not part of a restore point.
- Option 4 shows: **1) Reset one game (back to the first restore point)**, **2) Restore one game (choose a restore point)**, **3) Reset all games (back to the first restore point)**, **4) Restore all games (choose a restore point)**, **5) Remove older restore points**, and **B) Back**.
- Choosing 2 or 4 shows **Restore points, newest first:**. Each row has a date, what kind of restore point it is, and a file count.
- Before one game or all games are put back, TeknoParrot Manager saves and checks a new restore point of your current settings, so you can undo the change here. For one game, it asks you to type **YES**. For all games, it asks for **YES**, then **ALL**.
- The normal game-settings backup does not cover everything: see [issue 378](https://github.com/Jumpstile/teknoparrot-manager/issues/378).

## A game shows a backup memory error the first time you start it

Symptom: the first time you start some arcade games (for example Pac-Man Battle Royale), you see a black screen with `BACKUP RAM.. NG`. You also see a message such as `BACKUP MEMORY ERROR 1. Please go to the Test Mode and execute a BACKUP MEMORY INITIALIZE.`

Cause: the game keeps its settings and counters in a small saved memory, like the battery-backed memory on a real arcade cabinet. On the very first start that memory is blank, so the game asks you to set it up.

This is normal behavior of the game itself. TeknoParrot Manager does not change this memory and did not cause the message.

Fix:

1. Close the game and start it again.

   You will see: often the message is gone the second time, because the game sets up its memory on the first start.

   Next: if the message is gone, you are done. If it comes back, go to step 2.

2. Open TeknoParrot, select the game, and click **TEST MODE** instead of PLAY.

   You will see: the game's service menu.

   Next: look for the memory entry.

3. In the game's service menu, look for an entry named like **Backup Memory Initialize**. The exact name varies by game. Choose it and confirm.

   You will see: the game set up its memory.

   Next: leave the test menu.

4. Leave the test menu, then start the game normally with **PLAY**.

   You will see: the game starting normally.

   Next: if the message appears every time, go to step 5.

5. If the message appears every time, the game cannot save its memory. Check that the game's folder is not read-only and is not in a protected location. Then try again.

   You will see: the message gone after the folder is fixed.

   Next: you are done.

Expected result: the game starts normally and keeps working on later starts.

## ReShade text or a window shows when the game starts

Symptom: a ReShade welcome window, an FPS or clock counter, or a message shows when the game starts.

Cause: TeknoParrot Manager turns these off in every `ReShade.ini` it writes. If you still see them, that game's `ReShade.ini` was not written by TeknoParrot Manager, or it was changed by hand.

Fix:

1. At the main menu, type **6** to choose **6) ReShade setup**, then choose the game and pick a look again.

   You will see: the result screen for that game.

   Next: start the game. The welcome window, counters and messages should be gone.

2. If the result says it left that game alone, press **D** to read why.

   You will see: the reason under Details.

   Next: follow the reason on the screen.

A short ReShade version banner at game start is normal. ReShade has no setting to hide it. The key that opens ReShade still works.

Expected result: no welcome window, counters or messages when the game starts.

## Your games start in the wrong country or language

Symptom: a game starts in Japan or in the wrong language.

Cause: games left on `Auto` or `Default` usually start as Japan.

Fix:

1. At the main menu, type **11** to choose **11) Region setup**.

   You will see: `Which country do you want your games to start in?` and a numbered list of countries.

   Next: type the number of a country.

2. Choose all the games, or pick some, then type **Y** to confirm.

   You will see: `Region set to <country> for <number> games.` A restore point of your game settings is saved first.

   Next: start the game to check.

Only countries a game really offers are listed. A game never gets a region it does not have. A game that does not offer your country stays as it is and is named under Details (press **D**). To go back, choose **A** (`Back to automatic`) in Region setup, or use **15) Restore backup**.

Expected result: the game starts in the country you chose.

## AutoSync skipped games and said it could not confirm the game folder

Symptom: AutoSync says `TeknoParrot Manager skipped '<game>': it could not confirm the game folder.`

Cause: this happens when a game is already registered, and its saved game file is somewhere TeknoParrot Manager cannot safely use. The log line that starts with `AutoSync: refused unproven extraction root` says which case it was.

Fix:

1. If you moved your games to a new folder or drive, update to v1.0 RC8.2 or later. When the saved game file is missing at the old place, AutoSync now extracts the game into the new folder and carries on.

   Next: run **1) AutoSync** again.

2. If the log says the game is already installed at another place, AutoSync is protecting your working copy. It does not make a second copy.

   Next: run **2) Register only** on the folder that works. Keep the old copy until you have checked that the games start from the replacement. Only then move or delete the old copy yourself.

Expected result: the games are unpacked once, into the games folder you chose, and appear once in TeknoParrot.

## The health check names a game it cannot use yet

Symptom: Library health check (menu 14) shows `Needs attention` for **Game types** or **Game files**. For example: `1 game is not available yet`, `the emulator for 2 games is not in your TeknoParrot folder`, or `1 game needs you to pick the game file by hand`.

Cause: one of these.

- `not available yet`: TeknoParrot lists the game as development only, so it cannot be played yet.
- `the emulator ... is not in your TeknoParrot folder`: each game type has its own emulator folder, and that folder is missing.
- `needs you to pick the game file by hand`: the game's profile names no game file, and TeknoParrot has no setup file for it, so TeknoParrot Manager cannot find the file.
- a game type that TeknoParrot Manager does not know. Its games may still run.

Fix:

1. Press **D** to see which games.

   You will see: the names, with what to do for each.

   Next: follow the matching step below.

2. For `not available yet`, wait until TeknoParrot releases the game. Nothing is wrong with your setup.

3. For a missing emulator, update TeknoParrot so that game type's emulator folder is in your TeknoParrot folder. Then run the health check again.

4. For a game file to pick by hand, open the game in TeknoParrotUI and set its game file there.

Expected result: the line says `OK`, or only the games that cannot be played yet are left.

### More detail

- An arcade game that uses the TeknoS11 loader (System 10, System 11, System 12, Sony ZN, Konami 573, Taito G-NET and similar boards) is registered only when both of its ZIPs (the game's own ZIP and its parent ZIP) are in the same folder. A folder with only the parent ZIP does not register the game. Put both ZIPs in one folder, then run **2) Register only** again.
- A TeknoS11 arcade game that has a disc image (`.chd`) gets it chosen for it when there is exactly one. With several, none is guessed.
- A LaunchBox game with a `Needs setup` note, or in a `Needs setup` playlist, cannot start yet because its game file, firmware or BepInEx is missing. The note and the playlist entry go away by themselves when that is fixed.
- A game set to Internal storage (Golden Tee Live and PGA Tour games from any year, Power Putt Live, Silver Strike Bowling Live, Target Toss Pro, Orange County Choppers Pinball) needs no PostgreSQL. The health check shows it as `Game database: OK`. Start the game once so it makes its own database.

## A game works in TeknoParrot but not from RetroBat

Starting a game from TeknoParrot and starting it from RetroBat are two different ways to start it. RetroBat keeps its own game list and starts the game its own way. TeknoParrot keeps the controls and the input type (RawInput is the mouse and keyboard type). A game that works one way can still fail the other way.

Fix:

1. Start the game from TeknoParrot first, with the controls you want, and make sure it works there.

   You will see: the game starts and responds to your mouse, keyboard or controller.

   Next: only then try it from RetroBat.

2. If it still fails from RetroBat, look at RetroBat's TeknoParrot settings, or ask the RetroBat community.

   You will see: TeknoParrot Manager cannot tell you why one way works and the other does not. It does not change how RetroBat starts a game and it does not change RetroBat.

   Next: do not delete or reset your games. Nothing here needs it.

Who does what: TeknoParrot Manager adds your games to TeknoParrot and, after you say yes, sets up their buttons from the controller layout you choose, with a backup first. TeknoParrot runs the games and keeps their controls. RetroBat keeps its own game list and starts games its own way.

Mouse and keyboard only for now? Set the controls for one game in TeknoParrotUI and choose its input type there, and test that game. If you add Sinden lightguns later, that setup happens in TeknoParrot and in the gun's own software. TeknoParrot Manager does not set up a lightgun.

## You forgot the PostgreSQL password

Symptom: Postgres setup says PostgreSQL rejected the saved password, and nobody knows the right one.

**Why TeknoParrot Manager cannot do this for you.**
To reset a forgotten PostgreSQL password, the database safety check has to be turned off for a short time.
While it is off, any program on this PC can open the database without a password.
If a crash or a power cut happens in the middle, the safety check could be left off.
TeknoParrot Manager will not take that risk for you.
You do it yourself, on purpose, with the steps below, and you turn the safety check back on at the end.

1. Stop the Windows service `pgsql-8.3`.
2. Copy `C:\Program Files (x86)\PostgreSQL\8.3\data\pg_hba.conf` to a safe place.
3. Open `pg_hba.conf` in Notepad. Add this line above all other lines, then save the file: `host all postgres 127.0.0.1/32 trust`. The safety check is now off.
4. Start the service. In a Command Prompt, run `"C:\Program Files (x86)\PostgreSQL\8.3\bin\psql.exe" -h 127.0.0.1 -p 5432 -U postgres -d postgres`.
5. Type `\password postgres` and enter the new password twice. Then type `\q`.
6. Turn the safety check back on. Stop the service. Put your copy of `pg_hba.conf` back. Start the service.
7. Open Postgres setup again, choose **F** and type the new password.
8. Check the safety check is back on. The `trust` line must be gone from `pg_hba.conf`. If it is still there, repeat step 6.

Do step 6 straight away. While the `trust` line is there, any program on this PC can log in as `postgres`. If a step fails, still do step 6 first. The same steps, with more help, are in the User Guide under "Appendix: PostgreSQL password recovery".

## Still stuck, or the game will not launch?

Check these things first:

- The saved executable path exists.
- The game is fully extracted.
- TeknoParrot is up to date.
- The required runtimes are installed.
- Startup files are present. Some games need them from your own collection: firmware for the arcade games that run on PlayStation 3 style hardware (RPCS3), four files for Chihiro games, or firmware for PCSX2x6 games. If one is missing, the Action Required list names the games that will not start and the next step. Put the matching file in your game collection and run TeknoParrot Manager again. It never downloads these files.
- AutoSync said a game was not updated. It could not save the extra files in the old folder (saves, settings, ReShade files), or no Backups folder is set up. Nothing was changed for that game. Fix the Backups folder or free some space, then run AutoSync again.
- Check for Updates cannot install in place (you run a build before RC8.1, such as RC8 or RC7). Install the newest release by hand once: download its ZIP from the Releases page and extract all of its files over your TeknoParrot Manager folder. RC8.1 and later can update themselves.

Then read that game's official compatibility information and TeknoParrot Manager's Game Notes documentation. Do this before you try any game-specific fix.

Do not treat every crash as a missing patch. Do not install every optional tool at once.

Choose **17) Create Support Package** for diagnostics. Keep the exact result and any backup or leftover paths it shows. A partial result is not success. Do not send game data, passwords, or credentials.

### More detail

- The support package collects diagnostics, not game files. Review it before you share it.
