# RC9 owner test plan: issues that need a real screen or real hardware

These checks cannot be proven with fake folders. Each one needs a person at a real
Windows PC. Do them in order. Write down what you saw; a screenshot helps.
Use a copy of your settings or a test TeknoParrot folder. Do not use a folder you care about.

## #347 Responsive screens and the grouped ReShade list

1. Double-click `TeknoParrot-Manager.bat` so it opens in Windows Terminal. Do not start it from an open terminal tab.
2. Open the main menu. Maximize the window, then make it small, then maximize it again.
   Pass: every row stays inside the window and nothing is pushed to the far right.
3. Choose the ReShade setup. Pass: the list has three headings in this order: CRT Choices, Main Catalog, and
   (only on an HDR display) the HDR group. The arrow keys skip the headings.
4. While the list is on screen, maximize the window. Pass: the current choice and the help line stay on their own
   rows and nothing wraps to the right.
5. Open the preview window. Pass: the drop-down has the same headings, the headings cannot be picked, and the
   text, buttons and picture labels are not cut off.
6. Repeat step 5 at 100%, 125%, 150% and 200% Windows text scaling. Write down any size where text is cut off.
7. Resize the window in height only (not width) with the list open. Pass: the list redraws and keeps your choice.

## #384 Progress bars after a double-click start

1. Double-click `TeknoParrot-Manager.bat`. Choose AutoSync or Register only, so a progress bar appears.
2. Pass: the bar is on one row, inside the window, and does not wrap.
3. Maximize the window while the bar is moving. Pass: the bar redraws on one row.
4. Start again from a fresh Windows Terminal tab and do step 2 once more.
5. If a bar wraps, send the log. The log line "console is hosted by a terminal" tells which start type it was.

## #398 Time to check a large game ZIP

1. Pick one large game ZIP (several GB) that you are allowed to use, on a normal hard drive.
2. Run AutoSync for just that ZIP. Write down the minutes spent under "Checking your game ZIP files".
3. Pass: the ZIP is read once for checking, so the time is about one read of the file plus the copy.
   If it is still very long, send the log. The next step would be a lighter check after the move.

## #403 Errors on screen must also be in the log

1. Disconnect or rename a drive that one registered game uses, then open the main menu and run Library health check.
2. If red error text appears on screen, open the log (View Log).
3. Pass: the log has a line starting "Error shown on screen" for each kind of error you saw, with a count
   such as "(x12)" for repeats, and no passwords, user folder names or network paths.
4. Build a support package. Pass: the same lines are in the package copy of the log.

## #407 Linux-style games and ReShade

1. Have at least one Linux-style game registered (one that runs through BudgieLoader).
2. Run ReShade setup and select all games.
3. Pass: the result says how many Linux-style games were skipped and why, the word "unsafe" is not used,
   and the folders of those games are unchanged.
4. Open Details. Pass: the same reason is shown there.

## #408 The "What should I do next?" screen after AutoSync

1. Run AutoSync on one new game.
2. Pass: the screen says the files were only unpacked, tells you to check the registration result above,
   and explains N (New game only), A (Check all games) and B (Back) in plain words.
3. Ask someone who has never used the program to read it and say what N and A do.
   Write down any word they do not understand.

## #342 Controls result after AutoSync (quick check)

1. Run Propagate Controls on a library where some control types (lightgun, driving) have no example game.
2. Pass: the result names one game of each of those types to set up first, and the Details view has a
   "Games to set up first" part.
3. Pass: the last banner of an AutoSync run says "Registration run finished", not "Done".

## #385 Wait before the administrator prompt

1. From the main menu choose PostgreSQL setup on a PC where the Manager is not running as administrator.
   Use a test PC. Do not run this on a PC with PostgreSQL data you need.
2. Pass: the explanation appears and the Manager waits for Enter. The Windows permission window opens only after you press Enter.

## #350 / #131 Incredible Technologies games and their databases (needs a real PostgreSQL 8.3)

Use a test PC or a test TeknoParrot folder. Do not use a PC that holds PostgreSQL data you need. Have three games ready:
(A) a game that has a `pg_backup` folder, for example Power Putt Live 2013;
(B) Golden Tee Live 2021 or newer, or a Golden Tee PGA Tour game, with no `pg_backup` folder;
(C) any game of this kind left on the Storage choice Internal.

1. In TeknoParrot, set Storage to Existing PostgreSQL for (A) and (B). Leave (C) on Internal.
2. Run Register only (or AutoSync). Pass: every game is registered by its own name, including (B), the Golden Tee Live 2023-2024
   game and the PGA Tour games, which are not in the Eggman list. None is sent to the ACTION REQUIRED list.
3. Choose 11) Postgres setup. Pass: (A) says `Ready ... created from the game's own backup`. (B) says `Profile ready`. (C) is skipped.
   The run ends as finished, not as "needing attention". Write down the exact words of the (B) line.
4. Choose 13) Library health check. Pass: the PostgreSQL row says `OK - profile ready; a game database is created the first time the game starts`
   and (B) is not called a problem. Press D: (B) is listed under `Profile ready; the database is created the first time the game starts`.
5. Start (B) from TeknoParrot once. Pass: the game starts and TeknoParrot makes its database (TeknoParrot's own "Automatically create Database").
6. Run Library health check again. Pass: the PostgreSQL row says `OK` and (B) is no longer listed as waiting.
7. Start (A) and (C). Pass: both start. (C) needs no PostgreSQL install; start it once so it makes its own database.
8. On a PC with an Intel graphics card: run Register only and read the compatibility warnings. Pass: every registered Golden Tee Live 2011 and newer
   game and every PGA Tour game is named as not working on Intel graphics. Write down whether the game starts.
9. Write down any game of this kind that did not register, did not reach `Ready` or `Profile ready`, or did not start.

## #375 Contributor list on GitHub

1. Open the repository page and look at the Contributors list. Write down every name shown.
2. Pass: only the owner is shown. If another name appears, do not rewrite history.
   First look at the commit messages on the branch you are about to merge: any "Co-authored-by" line that names
   someone other than the owner can add that name to the list when the branch reaches the main branch.
3. Decide whether to keep or remove those lines before merging. Refresh can take up to 24 hours.

## #389 and #351 Every TeknoParrot game and the Eggman guide steps

Use your real Eggman collection on the test PC. Copy it first or use a test TeknoParrot folder.

1. Run Register only (or AutoSync) on the whole collection. Pass: every game folder ends as Registered, Already set, a duplicate with a
   reason, or "not in TeknoParrot". No folder disappears without a line in the result or the log.
2. Pick two versions of one game that read almost the same (Chaos Code - New Sign of Catastrophe 1.03.00 and 2.11.00).
   Pass: both are registered.
3. Pick The King of Fighters XII and The King of Fighters XIV, and Total Vice (AAB) and Total Vice (EBA).
   Pass: each gets its own profile (the XII folder is not given the XIV profile).
4. Pick DrumMania (GQ881) and Dance Dance Revolution 2nd Mix - Link Ver. Pass: both are registered with the parent ZIP (pcnfrk.zip, ddr2m.zip).
5. Pick After Burner Climax, Virtua Fighter 5 (1.001 Ver B) and R-Tuned. Pass: TeknoParrot shows the Lindbergh profile and the ElfLdr2 profile
   of each. Start one ElfLdr2 game from TeknoParrot. Write down whether it starts.
6. Pick Minecraft Dungeons Arcade and Golden Tee Fore! 2004. Pass: both are registered.
7. Run a BepInEx install on one BepInEx game. Pass: the result tells you to start the game and close it twice the first time.
8. Open the Sega Rally 3 track mod folders. Pass: they are listed as "not in TeknoParrot", not as a failed profile.
9. Open `docs\GAME-SUPPORT.md`. Pass: the totals read 2550 game IDs and 9 Gap rows. Seven of the Gap rows are the Sega Rally 3 track
   mods (6) and Escape from Monster Manor: TeknoParrot has no profile for them. The other two (Battle Gear 3 and Wayne Gretzky's 3D
   Hockey Fatality Edition) run through a linked profile.
10. Write on issue 389 what you saw for steps 1 to 9, and which games you could not test.
