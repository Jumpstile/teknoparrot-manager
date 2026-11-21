# Controller hands-on test plan (RC9)

For the owner, on the test PC. Unit tests use fake files and cannot press a real button, so these checks are the only proof that the controller setup works in a game. Do them in order. Stop at the first failure and write down the step number and what you saw.

What this covers: the Xbox setup for one game (issue #306, first slice), the controller-found hint (#410), the read-only check of an outside controller list (#304), the saved answers and button learning (#201), the control guides and cabinet list (#267), and the "it worked" records that decide when a game is Verified (#307). Sections D to F use only TeknoParrot Manager's own files. They never change a game's file in UserProfiles, but check that in step 30.

## A. Xbox setup for one game

You need: one Xbox-style controller (wired, or wireless and switched on), one game that is already registered, and a copy of that game's file from the UserProfiles folder kept somewhere safe.

1. Plug in the controller (or switch it on). Start TeknoParrot Manager, pick Propagate Controls, and choose 1. You should see "Found: an Xbox-style controller." Keep answering N until the plan prints (it changes nothing). Then switch the controller off and do it again: the "Found" line should be gone.
2. Back at the menu, pick Propagate Controls and choose 2 ("set up one game for an Xbox controller"). Type part of a game name and pick the game.
3. At "How will you play...?" choose A. You should see "Nothing changed." The game's file in UserProfiles must be byte-for-byte your safe copy.
4. Do step 2 again and choose X. You should see "Ready to set up N buttons", how many buttons already had an Xbox setting, and "A saved copy of your game settings is made first." Answer N to "Set this up now?". You should see "Skipped. Nothing changed." The game's file must still match your safe copy.
5. Do step 2 again, choose X, answer Y to "Set this up now?". You should see "Done. ... is ready for an Xbox controller." Now answer Y to "Undo this and put your game settings back as they were?". The game's file must match your safe copy exactly.
6. Do step 2 again, choose X, answer Y, and this time answer N to the undo question. A new backup folder should exist, and the game's file should differ from your safe copy only by added Xbox settings.
7. Do step 2 a third time on the same game. You should see "This game is already set up for an Xbox controller." The file must not change (same size and date).
8. Start the game with the controller on. Press each control and write down if the game reacts: Back (should be Coin), Start, D-pad up, down, left, right, A (button 1), B (button 2), Y (button 3), X (button 4), LB (button 5), RB (button 6). Test and Service are left empty on purpose; they should do nothing.
9. If the game had keyboard or arcade-encoder buttons before, check they are still in the game's file. Note whether the arcade encoder still works in the game. The screen warns that it may stop.
10. Pick a game that has no Xbox choice in its settings (a wheel or gun game that lists only other input types). You should see "This game does not have an Xbox controller setting, so nothing was changed."
11. Open the log. Find the lines that start with "XboxStarter" and check each step above is written there, with the backup folder and the line saying the layout is built in.

## B. Outside controller list check (read-only)

You need: the outside teknoparrot.yml list you want to check (you download it yourself; it is not shipped) and your real TeknoParrot folder.

12. Run, from the Manager folder: `.\TeknoParrot-Manager.ps1 -MappingEvidenceFile "<path to teknoparrot.yml>" -ValidationRoot "<your TeknoParrot folder>" -ValidationJsonPath "<a new file name ending in .json>"`.
13. You should see "Nothing was changed", how many games are in the list and how many are in your TeknoParrot, the counts ready, missing controls and held back, and "TPM does not trust it". Check no file in GameProfiles or UserProfiles changed, and that the only new file is the one you named.
14. Run it again with the same file names. The two details files must be identical.
15. Compare the counts with the earlier audit on issue #200 (523 profiles parsed, 494 matched, 308 collision-free, 36 collision groups in 24 profiles, 7 games held back for collisions). Write down the differences. Differences are expected where the Manager is stricter, but each one should have a reason in the details file.

## C. Saved answers (#201)

You need: your real cabinet or controllers, and the Manager's own settings folder (State\Controls inside the TeknoParrotManager folder).

16. Pick Propagate Controls, choose 1, and answer the seven questions (or choose the Xbox shortcut). At the end, a file `cabinet.json` must exist in State\Controls. The screen said your answers are saved.
17. Run it again. You should see your saved answers and ONE question, "Keep these answers?". Answer Y: no other question, and the plan is the same as before.
18. Run it again, answer N, and change one answer. The saved answer is the default for each question. The new answer must be in the file afterwards, and `cabinet.json.bak` must hold the older answers.
19. Plug in an Xbox controller you said No to. Run the survey. You should see "A controller was found that you said you do not have", and all questions again.
20. Close the Manager. Change `cabinet.json` so it is not valid (add a stray letter). Run the survey. You should get the questions, a `cabinet.json.unreadable-...` copy of the bad file, and a new good `cabinet.json`.

## D. Learning the arcade buttons (#201)

You need: an arcade keyboard encoder with buttons, in a normal console window (not a remote or redirected one). Pick Propagate Controls, choose 3 (My controls), then 2.

21. Answer the number of players and buttons. If LEDBlinky is installed, you should be offered its key list first. Say N once to press them all yourself.
22. TeknoParrot Manager asks "Press Player 1 Coin", "Press Player 1 Start" and so on. Press each control once. After each, you should see "Got it" and the key's name. Check the names for Ctrl, Alt and Shift buttons: Left Ctrl, Left Alt, Left Shift. This is the part unit tests cannot prove.
23. Press the same control twice for two questions. The second time it must say that key is already used, and ask again.
24. Press Esc for a control your cabinet does not have. It must be skipped. Wait 30 seconds without pressing: it must ask if you want to stop, and keep what you pressed so far.
25. At the end answer Y to "Save this?". Open `cabinet.json`: every key you pressed is there. Run again and answer N to Save: the file must not change.
26. If LEDBlinky is installed: run again, accept its key list (Y), and check the keys it proposed match what your buttons really send (press a few). Say how many were right.

## E. Control guides and cabinet list (#267)

27. In My controls choose 3, pick a game, and read the list. Each control must show your key (or "Not learned yet") and "Set up" or "Not set up yet" that matches the game's real settings in TeknoParrot.
28. Answer Y to "Save this as a page you can print, and open it?". A page `<game>-controls.html` must be in the Reports\Control Guides folder and open in your browser. Print it (or print to PDF) and check it is readable on paper.
29. In My controls choose 5. The cabinet page must list the keys you learned.
30. Compare the game's file in UserProfiles with your safe copy from step A: it must be unchanged by steps 16 to 29.

## F. "It worked" and Verified (#307)

Use one plain button game and one wheel or gun game that are already registered and set up.

31. In My controls choose 4, pick the button game, and read the line: it must say TeknoParrot Manager has no record that you played it. Choose B.
32. Start the game, press every control you care about, then come back and choose 4, the game, and W. You should see "Saved" and that the game's controls count as verified. Start a full run or the registration screen: the game must not be listed as still needing a controls check. (To see the text: the Action Required list for a cataloged game, or the support package.)
33. In TeknoParrot, change one binding of that game. Choose 4 and the game again: the first line must now say its controls changed after you tested it. Change it back: the first line must say you tested it again.
34. Choose 4, the game, N. It must say it forgot. Choose 4 and the game again: no record.
35. Do 32 for the wheel or gun game. It must say a setup step is left (calibration). Calibrate in TeknoParrot, then choose 4, the game, S, 2, D. Now W again: it must now count as verified. Change a binding: calibration must be asked for again.
36. Choose 4, the game, S, 1, R ("still to do") on the button game after W: it must stop counting as verified until you choose S, 1, D.
37. Open `control-evidence.json` and read it. It must hold the game name, the date, the game's revision and the steps, and no names of people or computers.

## G. What to report

38. Say what you saw for each step number (pass or fail), the encoder and controller models, and the games used.
39. Say which games need a first-run Test or Service menu step or calibration, so TeknoParrot Manager can list them. Right now only the player's own answer says so, and calibration is assumed for every game that is not plain buttons.
40. Say if the Ctrl, Alt and Shift buttons were seen in step 22, and which encoder brands have a setup file you would like read (file name and a copy with no personal data).
