# TeknoParrot Manager RC9.2 - Tester Guide

Updated Nov 23, 2026

Thank you for helping! You will try a program that sets up arcade games on a PC. We want to find out if every game starts and plays with no extra work.

Follow the steps in order. Take your time. If you get stuck, stop and send a screenshot to the person who gave you this guide. If something goes wrong, your backup lets us fix it.

**What is new in RC9.2?** This guide tests RC9.2. RC9.2 adds a main menu item for LaunchBox integration, a better Force feedback setup, and a Library health check that knows more TeknoParrot game types. Tests 1 to 51 are the same as before, except Test 17 (the database choice for games like Golden Tee) and Test 43 (LaunchBox). **Tests 52 to 66 are new since RC8.4. If you only have a little time, do tests 52 to 66 first.**

Words you will see:

- **Backup:** a copy of your files, so nothing is lost.
- **Region:** the country setting of a game (like USA or Japan). It can change the language.
- **Overlay:** a small box or banner that shows up on top of a game.
- **ReShade:** a program that changes how a game looks. Its box should NOT show up.
- **Preview:** a list that shows what the program WOULD change. A preview changes nothing.
- **Undo:** puts your settings back the way they were before.

## Step 0: Get ready

Do all of these before you test. Tick each box when you are done.

- [ ] Use a PC that has TeknoParrot and at least 3 games on it. Different kinds of games are best.
- [ ] Make a backup. Find your TeknoParrot folder. Inside it is a folder named UserProfiles. Copy that folder and paste the copy on your desktop.
- [ ] Get the file TeknoParrot.Manager.v1.0.RC9.2.zip from the person who sent you this guide, or from the release page: https://github.com/Jumpstile/teknoparrot-manager/releases. The release page shows a SHA-256 check value for the file. To see yours, open PowerShell and run: `Get-FileHash -Algorithm SHA256 "C:\path\to\the\zip"`. The two values must match. If they do not, download the file again.
- [ ] Right-click the zip file and choose Extract All. Pick a NEW empty folder. Do not pick an old folder.
- [ ] Learn how to take a screenshot: press the Windows key + Shift + S.

## The tests

Do the tests in order. After each test, write down one word: Worked, Failed, or Not tried. Also write down anything that looked wrong or was hard to understand.

### Test 1: Start the program

1. Open the new folder you made in Step 0.
2. Double-click TeknoParrot Manager to start it. A black window opens. That is normal.
3. Read each question. Answer with the key it asks for, then press Enter. If you are not sure, pick the first choice it shows.
4. Wait until you see a numbered list of choices that ends with the line "Enter number and press Enter".
5. You passed if you see that list and no red error words.

### Test 2: Add your games

1. At the main menu, type 1 and press Enter. This is called AutoSync. It finds your games and sets them up.
2. Read each screen and do what it says. If you want more information, type D and press Enter.
3. When it says it is done, open the normal TeknoParrot program.
4. You passed if all your games are in the list, each one once, with the right name.

### Test 3: Region setup

1. Go back to the program window. At the main menu, type 11 and press Enter.
2. It shows a list of countries. Type the number next to USA and press Enter.
3. It asks which games to change. Type A for all games, or L to pick games yourself.
4. It shows a summary. Type Y and press Enter to say yes.
5. Write down which games changed.
6. Do steps 1 to 4 again, but this time type A at the country list. That means "Back to automatic". It puts the games back.
7. You passed if the summary made sense and no game was left in a strange state.

### Test 4: Health check

1. At the main menu, type 14 and press Enter (Library health check).
2. Wait. It checks your games.
3. You passed if it ends with a message in plain words and nothing says it failed.

### Test 5: Play your games (the most important test)

1. At the main menu, type 18 and press Enter to close the program.
2. Open the normal TeknoParrot program.
3. Start your first game the way you always do. Do not change any setting first.
4. Play for 2 minutes. Move around and press the buttons. Check that sound works.
5. Close the game. Then do steps 3 to 5 again for each other game.
6. You passed a game if it started, looked right, and the controls worked. It failed if it closed by itself, showed a black screen, or showed an error box.

### Test 6: The ReShade box

1. Do this while you do Test 5. Watch the screen closely while each game is loading.
2. Look for a box or banner that mentions ReShade.
3. It should NOT show up. If it does, write down if it goes away by itself, and how fast.
4. If you see it, take a screenshot with the Windows key + Shift + S.

### Test 7: Region in a real game

1. Do Test 3 again, but pick a country that changes the game language or text. Change only one game that has this.
2. Start that game.
3. You passed if the game really uses the new country.

### Test 8: Restore the backup (only if you were told to)

1. Start TeknoParrot Manager again.
2. At the main menu, type 15 and press Enter (Restore backup).
3. Pick the newest backup in the list.
4. You passed if your games and settings are back like before.

## More tests: the other menu items

Tests 9 to 28 try the rest of the program. Do the ones that fit your games and your PC. If a test does not fit you, write "Not tried" and move on. Test each one on ONE game first. Do not change many games at once.

### Test 9: Add games you already unpacked

1. At the main menu, type 2 and press Enter (Register only).
2. Pick games that are already in their own folders (not zip files).
3. You passed if those games show up in TeknoParrot, each one once. Skip this test if all your games are zip files.

### Test 10: Copy controls to other games

1. First set up the controls in one game, the way you like them.
2. At the main menu, type 4 and press Enter (Propagate Controls).
3. In RC8.2 and later it first shows a PREVIEW of what it would copy. Read it. Then answer the question. Type Y to say yes.
4. Open a game that got the controls in TeknoParrot and look at its controls.
5. You passed if the new game got the controls and your first game did not change. (Tests 30 and 31 try the preview and the undo.)

### Test 11: Crosshairs (light gun games)

1. At the main menu, type 5 and press Enter (Crosshair setup).
2. Pick a crosshair and one light gun game. Say yes.
3. Start that game.
4. You passed if the new crosshair shows on the screen and the game still starts. Skip this test if you have no light gun games.

### Test 12: ReShade setup

1. At the main menu, type 6 and press Enter (ReShade setup).
2. Pick ONE game. Say yes.
3. Start the game and look at the picture.
4. You passed if the picture looks different (the effect is on) and the ReShade box does NOT show up. Write down what you saw.

### Test 13: dgVoodoo2 (old games that crash)

1. Use this only on an old game that crashes or shows a black screen.
2. At the main menu, type 7 and press Enter (dgVoodoo2 setup). Pick that one game. Say yes.
3. Start the game.
4. You passed if the game now starts and looks right. If it still fails, write down how. Skip this test if none of your games has this problem.

### Test 14: GPU fix

1. At the main menu, type 8 and press Enter (GPU fix setup).
2. Pick the choice that matches your graphics card (AMD, NVIDIA, or Intel). Say yes.
3. Start one game that was changed.
4. You passed if the game starts and looks right.

### Test 15: Force feedback (steering wheel games)

1. Do this only if you have a wheel or joystick that pushes back.
2. At the main menu, type 9 and press Enter (Force feedback setup).
3. Read the choices. Pick the free one unless you are a member of the paid one.
4. Start a driving game and turn the wheel.
5. You passed if the wheel pushes back and the game starts. Skip this test if you have no force feedback wheel.

### Test 16: BepInEx

1. Use this only if a game needs it (the program will say so).
2. At the main menu, type 10 and press Enter (BepInEx setup).
3. It must ASK you before it downloads or installs anything. Say yes.
4. Start that game.
5. You passed if it asked first, finished with no red error words, and the game starts.

### Test 17: Game database (Internal or Existing PostgreSQL)

1. Do this only if you have games that save progress in a database, such as Golden Tee. Newer TeknoParrot profiles have a Storage box under Database in the game's settings.
2. Look at the Storage box. Internal is the new default and needs no database install. Existing PostgreSQL is for keeping an existing server and its saved progress. Do not change it for this test.
3. If a game says Internal: run Library health check (menu 14). You passed this part if the game is not called missing a database, and the screen says no database install is needed and the game must be started once. Then start the game once.
4. If a game says Existing PostgreSQL (or has no Storage box): at the main menu, type 12 and press Enter (Postgres setup). Read each screen and say yes when it asks. A game that came with a pg_backup folder says `Ready`. A Golden Tee Live 2018 or newer game or a PGA Tour game with no pg_backup folder says `Profile ready`: TeknoParrot makes its database the first time the game starts. Then start the game.
5. You passed if the program never switched the choice for you and, for Existing PostgreSQL, the setup ended with a plain done message and the game starts. Skip this test if you have none of those games.

### Test 18: Required game patches

1. Do this only if the program told you that a game needs a fix.
2. At the main menu, type 13 and press Enter (Required game patches).
3. Follow the screens. It checks your zip file, makes a backup, installs the fix, and checks it.
4. Start the game.
5. You passed if the game starts. Then try the undo choice on the same screen. You passed that part if the game is back the way it was before.

### Test 19: Check for updates

1. At the main menu, type 16 and press Enter (Check for Updates).
2. Wait for the answer.
3. You passed if it tells you in plain words that you have the newest version (or that a newer one is ready), and it never installs anything without asking you first. There may be no newer version yet. That is fine. (Test 29 tries a real update.)

### Test 20: Run AutoSync a second time

1. After Test 2 is done, go to the main menu again. Type 1 and press Enter.
2. Answer the screens the same way as before.
3. Open TeknoParrot.
4. You passed if no game shows up twice and your settings did not change.

### Test 21: Move up from an older version (RC7 or RC8)

1. Do this only if you used RC7 or RC8 before. Do not delete the old folder. (If you use RC8.1, RC8.2, RC8.3, RC8.4 or RC9, do Test 29 instead.)
2. Extract the RC9.2 zip into a NEW empty folder.
3. Start TeknoParrot Manager from the new folder. Answer the first questions the same way you did before.
4. At the main menu, type 14 and press Enter (Library health check).
5. You passed if your games and settings are all still there and the health check ends in plain words with no failure.

### Test 22: LaunchBox

1. Do this only if you use LaunchBox.
2. Run AutoSync (menu 1). When it asks about LaunchBox, choose [A] Add missing games.
3. Open LaunchBox.
4. You passed if each game shows once, with the right name, and one game starts from LaunchBox.

### Test 23: Restore the LaunchBox files

1. Do this only after Test 22, and only if you made a backup first.
2. At the main menu, type 15 and press Enter (Restore backup). Pick the LaunchBox library files and the newest backup.
3. Open LaunchBox.
4. You passed if your library is back the way it was before Test 22.

### Test 24: Games on another drive or folder

1. Put a few game zip files in a folder on another drive, such as D:, or in a folder with a long name.
2. Start TeknoParrot Manager. When it asks for the games folder, type that folder.
3. Run AutoSync (menu 1).
4. You passed if the games are set up and start. Write down any message that did not make sense.

### Test 25: A big library

1. Do this only if you have 100 games or more.
2. Run AutoSync (menu 1) on all of them. Write down about how long it takes.
3. Then run the Library health check (menu 14).
4. You passed if it finished with no freeze, no game is missing, and nothing looks broken. Tell us how many games you had.

### Test 26: Strange file names

1. Make a copy of one game zip. Rename the copy so the name has spaces and brackets, like Game (USA) [v2].zip. Never rename your only copy.
2. Run AutoSync (menu 1).
3. You passed if the game is set up with a clean name and starts.

### Test 27: A broken zip file

1. Make a copy of a small zip file. Cut it short, for example by copying only part of it, so it is damaged. Use a COPY only.
2. Put it with your other zip files and run AutoSync (menu 1).
3. You passed if it says in plain words which file has a problem, keeps going with your other games, and does not touch your good files.

### Test 28: Back out and TeknoParrot open

1. Start a menu item, such as 5 or 6. On the first question, say No or pick the back choice (the screen tells you which). Do this for 3 different menu items.
2. You passed if it goes back to the menu and nothing changes.
3. Now open the normal TeknoParrot program and leave it open. Run AutoSync (menu 1) again.
4. You passed if the program tells you what to do, or works with no damaged files and no red error words.

## Tests added in RC8.2: tests 29 to 35

These tests try the fixes made in RC8.2.

### Test 29: Update from RC8.1, RC8.2, RC8.3, RC8.4 or RC9 (menu 16)

1. Do this only if you use RC8.1, RC8.2, RC8.3, RC8.4, RC9 or RC9.1 and RC9.2 is on the release page. Do not delete anything first.
2. In your old version, at the main menu, type 16 and press Enter (Check for Updates).
3. It should tell you a newer version is ready. It must ASK before it installs. Say yes.
4. Wait until it says it is done. Close the program and start it again yourself.
5. You passed if the title at the top now says v1.0 RC9.2, and your games and settings are all still there. Write down any message that did not make sense.

### Test 30: Preview before copying controls

1. Set up the controls in one game of each kind you have, the way you like them.
2. At the main menu, type 4 and press Enter (Propagate Controls).
3. You should see a list that says "Preview only. Nothing was saved." Read it.
4. When it asks "Copy controls ... (Y/N, D = details)", type N and press Enter.
5. Open TeknoParrot and look at your other games.
6. You passed if NOTHING changed after you said N. Then run menu 4 again and type Y. You passed that part if it saved the controls and showed you where it put a backup of your settings.

### Test 31: Undo the control copy

1. Do this right after Test 30, when you typed Y.
2. The program asks: "Undo these changes and put your game settings back as they were? (Y/N)". Type Y and press Enter.
3. Open TeknoParrot and look at the games that were changed.
4. You passed if they are back the way they were before you copied. If you type N (or just press Enter) nothing is undone. You can also undo later with menu 15 (Restore backup).

### Test 32: The Game ZIP folder question

1. Do this when the program asks for your "Game ZIP folder" (it can ask in menu 1).
2. Type B to open the browse window. Close the window WITHOUT picking a folder.
3. You passed if the program asks again and does not go back to the menu by itself. Type Q to go back on purpose. Also try typing a folder that does not exist. It should say the folder was not found and ask again.
4. Write down what it said.

### Test 33: Games saved at an old place

1. Use a PC where TeknoParrot already lists games, but the game files are missing because you moved your games to a new folder or drive (for example from L: to G:). Have the zip files for some of them.
2. At the main menu, type 1 and press Enter (AutoSync). Choose to extract those games into the new folder.
3. You passed if the games are unpacked into the new folder and set up. It failed if many games were skipped with the words "could not confirm the game folder". If that happens, make a support package (menu 17) right away and attach it to your issue.
4. After AutoSync, open TeknoParrot and start one of those games. You passed that part if it starts from the NEW folder. Tell us if it still points to the old place.

### Test 34: Support package that explains itself

1. At the main menu, type 17 and press Enter (Create Support Package).
2. Wait for it to finish. Type D and press Enter to see the details.
3. You passed if the ZIP file was made. If an item was left out, the details should say "Why:" and give a reason in plain words.
4. Tell us if the screen says it FAILED even though the ZIP file was made.
5. Open the ZIP and look inside its text files (use the search in Notepad). Search for your Windows user name. You passed if it does not show up anywhere. Tell us if you find it, but do NOT paste the line into your issue.

### Test 35: Your controller is found

1. Plug in an Xbox-style controller (wired or wireless) BEFORE you start the program. Then start it.
2. When it asks about your controls, look for the line "Found: an Xbox-style controller."
3. You should get ONE question: "Use the Xbox controller for all games?" Type Y. It prints a plan. It changes no game file (it only saves your answer in its own settings folder).
4. Now close the program, unplug the controller, and start it again. Answer the control questions.
5. You passed if step 3 asked one question, and step 4 asked the full list of questions like before. Tell us what controller you have.
6. Stuck buttons, the standard arcade keys, key suggestions, light colors and "TPM noticed I changed my arcade encoder" need a real arcade encoder. They are in `docs/RC9-OWNER-TEST-PLAN.md`, Part 3 (steps 112 to 128).

## New in RC8.3: tests 36 to 40

These tests try the fixes in RC8.3. Do them first if you are short on time.

### Test 36: BepInEx tells you why

1. Use this only if a game needs BepInEx and the program says it cannot replace a file. Skip this test if that never happens to you.
2. At the main menu, type 10 and press Enter (BepInEx setup).
3. If the program says it cannot replace a file, read the message.
4. You passed if the message gives the exact reason in plain words (for example, the file is shared with another folder, it is a folder, it is a link, or it cannot be read). It failed if it only gives one general sentence with no reason. It must also ASK before it installs anything.

### Test 37: ReShade one game at a time, with Back

1. At the main menu, type 6 and press Enter (ReShade setup).
2. Choose to pick games one by one (not all at once).
3. Look at each question. It should say something like "game 1 of 4". It should NOT ask about a game that cannot be changed.
4. At the second game, type B and press Enter. You should go back to the first game. At the first game, type B and press Enter.
5. You passed if B went back one game each time, and B on the first game canceled and nothing was changed. Write down anything that was hard to understand.

### Test 38: dgVoodoo2 result lists every game

1. Pick 3 games. Make sure at least one of them already has dgVoodoo2 set up from an earlier run.
2. At the main menu, type 7 and press Enter (dgVoodoo2 setup). Pick those 3 games. Say yes.
3. Read the result screen when it finishes.
4. You passed if all 3 games are named on the result screen, including the one that already had every file. It failed if a game you picked is missing from the result.
5. Now add one new game with Register only (menu 2). When it asks the optional dgVoodoo2 question or the graphics card question, type B and press Enter. You passed that part if it went back one step, and you could still do the step you skipped.

### Test 39: Games that share one zip file

1. Use this only if you have game folders that each hold a zip file with the same name (for example, several folders that each have naomigd.zip). Skip this test if you do not have these.
2. At the main menu, type 2 and press Enter (Register only). Pick those folders.
3. You passed if it does NOT ask a "keep or switch" question that offers only the wrong game. A folder it cannot tell is listed as not identified instead.
4. Open TeknoParrot. You passed if no game shows up twice and each game has the right name.

### Test 40: A very deep folder, or a folder that ends in [TP]

1. Use this only if you have a game folder whose name ends in [TP], or your TeknoParrot folder is inside many folders (a very long path). Skip this test if you have neither.
2. Install a game patch from the menu on a game in that folder. Then undo the patch.
3. You passed if neither step stops with a "could not be checked" error.
4. If your TeknoParrot folder is very deep, also start TeknoParrot Manager and let it tidy up its own files. You passed if it finishes with no error about a path that is too long.

## New in RC8.4: tests 41 to 51

These tests try the new parts of RC8.4. Do them first if you are short on time.

### Test 41: Two games with almost the same name

1. Use this only if you have zip files for two different games whose names start the same way (for example "Chaos Breaker" and "Chaos Breaker for NESICAxLive", or two versions of "Chaos Code"). Skip this test if you do not have these.
2. Put both zip files in your Game ZIP folder. At the main menu, type 1 and press Enter (AutoSync).
3. Read the preview, then say yes.
4. You passed if BOTH games were unpacked into their own folders and set up. It failed if one of them was skipped with a message that another zip "already created a new folder for the same game".
5. Open TeknoParrot. You passed that part if each game is listed once with its own name. If one game's zip exists in two regions (for example Japan and USA), they should still share ONE folder. That is correct.

### Test 42: The control setup result is easy to read

1. Use this only if some of your games have no controls set up in TeknoParrotUI. Skip this test if every game already has controls.
2. At the main menu, type 4 and press Enter (Propagate Controls). Say yes when it asks.
3. Read the result screen.
4. You passed if games that were already set up and games skipped by your own rules are on separate lines, and every control family that has no game with your controls yet is named. You also pass if the next step tells you what to do in TeknoParrotUI and then which menu to run again. Write down anything that was hard to understand.

### Test 43: LaunchBox official names and details

1. Use this only if you use LaunchBox. Skip this test if you do not.
2. Start the LaunchBox step the way you did in Test 22. Choose [L] Link games for art and details.
3. Look at the preview. Nothing should change until you say yes.
4. You passed if you see each old name, new name and ID first, and a backup is made before anything is saved. Games you named yourself must keep your name.
5. Run the LaunchBox step again. Choose [G] Fill in game details and make playlists. You passed if it shows what will change first, makes playlists such as "Light gun games" and "Driving games", and leaves your own playlists alone.
6. Undo it: choose 15 (Restore backup) in the main menu, then the LaunchBox backup. You passed if everything goes back the way it was.

### Test 44: Logos and box art from a folder

1. Use this only if you use LaunchBox and have a folder with pictures for your games. Skip this test if not.
2. Choose the optional step that adds logos or box art. Pick your folder.
3. You passed if it shows a preview with sure matches, close matches and games with no picture, and uses a close match only if you say yes. Pictures LaunchBox already has must stay unless you choose to replace them.
4. Choose Undo. You passed if only the pictures that were added are removed.

### Test 45: LEDBlinky lighting

1. Use this only if you use LEDBlinky. Skip this test if you do not.
2. Run AutoSync (menu 1). When it asks "What should I do next?", choose [A] Check all games. (The lighting step is not shown after [N] New game only.) Go through the LaunchBox step. When it ends, you see "Optional: lighting for your arcade buttons."
3. If it finds LEDBlinky on its own, you see "LEDBlinky was found on this PC." If not, it asks "Do you use LEDBlinky? Show me where it is." Choose [F] to show the folder, or [S] to skip.
4. Choose [P] Preview first. You passed if it shows what it would add and changes nothing.
5. Choose [A] Add lighting info to LEDBlinky. You passed if a saved copy of the LEDBlinky file is made first and the result names it.
6. Run this step again and choose [U] Undo the last add. You passed if only the entries TPM added are removed.

### Test 46: Games that need firmware or a game file

1. Use this only if you have a PlayStation 3 game (RPCS3) or a Play! game. Skip this test if you have neither.
2. Start the game from TPM, or run Health check (Test 4).
3. You passed if TPM tells you in plain words what is missing (the firmware or the game file) before the game starts. It failed if the game just closes with no explanation.

### Test 47: Pick all games with A

1. Use this on any numbered list of games that says "Type numbers like 1,3,6 or a range like 1-8, A for all, or B for none". Skip this test if you do not see one.
2. Type A and press Enter. You passed if every game in the list was picked.
3. Run it again. Type 1,3 and press Enter, then try 1-4. You passed if both still work.

### Test 48: Result screens add up

1. Run dgVoodoo2 setup (menu 7), BepInEx setup (menu 10) or GPU fix (menu 8) on 3 or more games.
2. Read the result screen. You passed if it says how many games you selected and how many were changed, already set up, skipped or failed (for example "You selected 4 games: 3 changed, 1 skipped."), and the numbers add up. It should also say where the backup is saved.
3. For dgVoodoo2, press D. You passed if the block "Every game you selected" names every game with its result, and gives a reason for each game that was skipped or failed.

### Test 49: Action Required is grouped

1. Use this after a run that leaves several follow-up items (for example AutoSync with many games). Skip this test if you have none.
2. Read the Action Required list.
3. You passed if it is grouped under short headings, one for each feature (for example Patches, BepInEx, dgVoodoo2 or ReShade). It failed if it is one long mixed list.

### Test 50: A drive that is not connected

1. Use this only if some games are on an external or network drive. Skip this test if not.
2. Disconnect that drive. Run a setup step on those games (for example dgVoodoo2 setup, menu 7).
3. You passed if the result says those games were skipped and ends with "Connect the drive, or choose 14 (Library health check) in the main menu to repair these games."

### Test 51: Health check lists games that need BepInEx

1. At the main menu, type 14 and press Enter (Library health check). Press D if you do not see the details.
2. Find the lines "ReShade installed" and "BepInEx installed".
3. You passed if a game whose profile says it needs BepInEx, and does not have it, is listed under "Games that need BepInEx and do not have it set up". ReShade is your choice for each game, so it must not be flagged.

## New in RC9: tests 52 to 66

These tests try the new parts of RC9. Do them first if you are short on time.

### Test 52: Health check names game types it cannot check

1. At the main menu, type 14 and press Enter (Library health check). Press D if you do not see the details.
2. Find the line that starts with "Game types". There may also be a line that starts with "Game files".
3. You passed if the line says OK, or if it says "Needs attention" and the details name each game and say what to do. The details can say "Unknown game type", "Not available yet" (TeknoParrot lists the game as development only), "Emulator for type ... is not in your TeknoParrot folder", or "Pick the game file by hand".
4. You failed if a game you can play is called unknown, or if the screen stops with an error.

### Test 53: System 11 games

1. Use this only if you have System 11 games. Skip this test if you do not.
2. Pick a System 11 game that needs two ZIP files (a child and a parent). Put only the child ZIP in your Game ZIP folder, then run AutoSync (menu 1). You passed if that game is not registered. Then put the parent ZIP in the same folder and run AutoSync again. You passed that part if the game is now registered.
3. If you have the System 11 saved-files set, look for the screen "OPTIONAL: System 11 saved game files". Say yes. You passed if it says it copied and checked the files, and says which games the set has no files for.
4. Run AutoSync again. You passed if no file that was already there was replaced, and the screen does not ask you again when the set has nothing new.

### Test 54: A game set with only its parent ZIP

1. Use this only if you have a game that needs a parent ZIP (a game set). Skip this test if you do not, or if the game is one of the 17 that the Eggman list registers by its parent ZIP (for example Dance Dance Revolution 2nd Mix Link).
2. Make a new folder that holds ONLY the parent ZIP, not the game's own ZIP. At the main menu, type 2 and press Enter (Register only). Pick that folder.
3. You passed if no game is registered from that folder. Open TeknoParrot. You passed that part if the game does not show up from that folder.

### Test 55: LaunchBox names, details and Needs setup

1. Use this only if you use LaunchBox. Skip this test if you do not.
2. Run AutoSync (menu 1) with a new game and choose [A] Add missing games at the LaunchBox question. Open LaunchBox.
3. You passed if the new game has its real game name, not its file name (for example "Too Spicy", not "2Spicy"), and, where LaunchBox knows the game, its release year and developer.
4. Run the LaunchBox step again. Choose [G] Fill in game details and make playlists. Make sure one game cannot start yet (for example its game file is missing). You passed if that game has a "Needs setup" note in its Notes box and is in the "Needs setup" playlist. Fix the problem, run [G] again, and you passed that part if the note and the playlist entry go away and what you wrote in the Notes box stays.
5. Check that a firmware updater or a test board was NOT added to LaunchBox.

### Test 56: LaunchBox groups regions and versions

1. Use this only if you use LaunchBox and have a game with more than one region or version (for example a Japan copy and a USA copy). Skip this test if not.
2. Run the LaunchBox step. Choose [V] Group regions and versions of a game into one.
3. Look at the groups it shows. Nothing should change until you say yes.
4. You passed if each of those games shows up once in LaunchBox, the other copies are under "Play ... version", and the copy for the region you chose in Region setup starts by default. Games that are not certainly the same game must stay separate.
5. Undo it: choose 15 (Restore backup), then the LaunchBox backup. You passed if the separate games are back.

### Test 57: LaunchBox stays in step with TeknoParrot

1. Use this only if you use LaunchBox. Skip this test if you do not.
2. Remove one game from TeknoParrot. Rename one game in LaunchBox yourself.
3. Run the LaunchBox step. Choose [S] Keep LaunchBox in step with TeknoParrot.
4. You passed if the preview names the game you removed, nothing else disappears, and the game you renamed keeps your name. Say yes and check LaunchBox.
5. Unplug the drive that holds some of your game files and run [S] again. You passed if no game is removed only because its file is missing.
6. Undo it: choose 15 (Restore backup), then the LaunchBox backup. You passed if everything goes back the way it was.

### Test 58: LaunchBox platform name

1. Use this only if you use LaunchBox. Skip this test if you do not.
2. In LaunchBox open the platform list. You passed if the platform TPM made is called TeknoParrot and its "Scrape as" setting is Arcade.
3. Select a few of the games TPM added, right-click, and search for metadata. You passed if LaunchBox finds the game by its name and fills in artwork or details, and none of the games ends up under a different platform name.

### Test 59: Pictures from a folder match the right game

1. Use this only if you use LaunchBox and have a folder with pictures. Skip this test if not.
2. Choose the optional step that adds logos or box art. Pick your folder. Include a picture that uses another name of one of your games, and a picture of a different game that has the same name.
3. You passed if the other-name picture is listed as a sure match, the picture of the different game is NOT used, and close names are used only if you say yes.
4. Choose Undo. You passed if only the pictures that were added are removed.

### Test 60: Bezels from your own folder

1. Use this only if you have a folder with bezel pictures (.png). TeknoParrot Manager does not come with bezels. Skip this test if you have none.
2. Set up ReShade for one game first (Test 12). At the main menu, type 6 and press Enter. Type B (Use my bezel folder) and press Enter. Then choose the pick-bezels choice and give your folder.
3. Read "Bezel preview. Nothing has been changed yet." You passed if each game shows a bezel and how sure the match is (High, Medium or Low), a Low match says "needs your choice", and a picture for a different sequel number is not picked for you.
4. Apply it for one game. You passed if the bezel is copied and checked. If you placed a bezel yourself earlier, it must be kept unless you said to replace it.
5. Start that game. Write down if the bezel shows. It may not show in games that run in exclusive fullscreen.
6. Type 6, then B, then the undo choice. You passed if the bezel TPM copied is removed and your own bezel is back.

### Test 61: Controls result names a game to set up first

1. Use this only if some kinds of games (for example light gun or driving games) have no game with your controls yet. Skip this test if every kind has one.
2. At the main menu, type 4 and press Enter (Propagate Controls). Read the result.
3. You passed if, for each kind with no example game, it names one game to set up first in TeknoParrotUI, and says that choosing a device in the plan does not set up a game.
4. Run AutoSync or Register only. You passed if the registration screen ends with "Registration run finished" (not "Done.").

### Test 62: PostgreSQL setup waits for you

1. Use a test PC only. Use this only if you have a game set to Existing PostgreSQL, and start TPM without administrator rights.
2. At the main menu, type 12 and press Enter (Postgres setup).
3. You passed if TPM explains what the Windows permission window will ask for and waits for you to press Enter. The Windows window must open only after you press Enter.

### Test 63: Check an outside controller list (advanced)

1. Use this only if you are comfortable with PowerShell and you have a controller list such as RetroBat's teknoparrot.yml. Skip this test if not.
2. In PowerShell, in the TPM folder, run: `.\TeknoParrot-Manager.ps1 -MappingEvidenceFile "C:\path\to\teknoparrot.yml" -ValidationRoot "C:\path\to\TeknoParrot" -ValidationJsonPath "C:\path\to\new-details.json"`.
3. You passed if it says nothing was changed and prints plain counts, and the only new file is the one you named. Check that no file in GameProfiles or UserProfiles changed.
4. Run it again with the same names. You passed if the two details files are identical.

### Test 64: Startup files for Chihiro or PlayStation 3 (ask once, one Y)

1. Use this only if you have a registered Chihiro or PlayStation 3 game and your own Supplementary game collection. Skip this test if not.
2. Run Register only (menu 2), or choose F in the Library health check (menu 14), while the startup files are missing.
3. If TPM does not find the files, it asks for your Supplementary folder. Choose your real folder. You passed if it asks only once in this run and does not ask again on the next run. (If you press Enter to skip, nothing is saved and it asks again next time.)
4. Read the list. It should say what it found, what is already in place, what is missing (by file name) and the folders it searched. Press Y once.
5. You passed if one Y installed everything it found, and the result names what was installed, already matching, missing or invalid. It failed if it asked you to approve each game or each file one by one.

### Test 65: Update screen at start (one Y)

1. Do this only on a PC that still runs an older version while RC9.2 is on the release page. Skip this test if not.
2. Start TPM. You passed if the Update Available screen shows before the "use saved settings?" question, with the choices Y = Update now, N = Remind me later and V = View release notes.
3. Press V, read the notes, then choose again. Press Y. You passed if the update starts right away and it does not ask a second Y/N question.

### Test 66: A game with two versions, or two profiles

1. Use games from the Eggman collection. Good ones: two versions of Chaos Code - New Sign of Catastrophe, and After Burner Climax (a Lindbergh game). Skip this test if you do not have them.
2. Register the games (AutoSync or Register only).
3. You passed if both versions of the first game were registered or one was reported as a duplicate with a reason. It failed if one version is missing and nothing says why.
4. Open TeknoParrot. You passed if After Burner Climax shows both its Lindbergh profile and its ElfLdr2 profile. If the ElfLdr2 one is missing, open the log and look for "was left alone because none of its game files is in folder".
5. If you have a folder for a game that TeknoParrot has no profile for (a Sega Rally 3 track mod), you passed if it is listed as "not in TeknoParrot".

## How to report a problem

**Very important: the support report.** Every bug report needs a support report. Without it we often cannot find the cause. Make one every time something goes wrong. Never skip it.

**Where to send bugs:** Send every bug through the Issues section on GitHub. Open the TeknoParrot Manager page on GitHub, click the Issues tab, then click New issue. Link: https://github.com/Jumpstile/teknoparrot-manager/issues

If you do not have a GitHub account, make a free one first. Make one issue for each bug.

**Do not want to use GitHub?** Send a direct message on Discord to Jumpstile. Send the same five things and the support report there.

**Is the support report safe to share?** It does not contain game files. It is built to remove private details, such as your Windows user name in file paths and passwords it can recognize. It is not perfect, so do not add private details in your own words.

Write these five things in your issue. Reports with all five can be fixed fast.

| What to send | Example |
| --- | --- |
| Game name | Initial D Zero |
| Test number and step | Test 5, step 3 |
| What you expected | The game starts |
| What really happened | Black screen, then it closed |
| Screenshot or photo | Attach it |

Also make the support report (the help file). Right after the problem, do not close the program. At the main menu, type 17 and press Enter (Create Support Package). It makes a file. Attach that file to your GitHub issue. This is extremely important.

Please do not:

- Skip the backup in Step 0.
- Change game settings before Test 5. We want to know if games work with no extra work.
- Type passwords or private details in your issue. Never put them in the text.

When you finish, send a short list. Write each test number and one word: Worked, Failed, or Not tried.
