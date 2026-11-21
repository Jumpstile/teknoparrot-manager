# Controller hands-on test plan (RC9)

For the owner, on the test PC. Unit tests use fake files and cannot press a real button, so these checks are the only proof that the controller setup works in a game. Do them in order. Stop at the first failure and write down the step number and what you saw.

What this covers: the controller-found hint (#410), your controller layout chosen once (#200), setting up one game, all games or game by game from that layout (#306), the controls check of every registered game and the Controls line in the Library health check (#305), the read-only check of an outside controller list (#304), the saved answers and button learning (#201), the control guides and cabinet list (#267), the stuck-button check, the standard arcade keys, key suggestions and light colors (#267), and the "it worked" records that decide when a game is Verified (#307). Sections F to K use only TeknoParrot Manager's own files. They never change a game's file in UserProfiles, but check that in step 41.

## A. Your controller layout (nothing in any game changes)

You need: one controller (wired, or wireless and switched on). Do this with an Xbox-style controller first. Repeat steps 3 and 4 with a PlayStation controller, a Nintendo controller and an arcade stick if you own them. A PlayStation or Nintendo controller must be shown to Windows as an Xbox controller (by a controller mapping program you already use), and an arcade stick must be in its Xbox mode.

1. Plug in the controller (or switch it on). Start TeknoParrot Manager, pick Propagate Controls, and choose 1. You should see "Found: an Xbox-style controller." Keep answering N until the plan prints (it changes nothing). Then switch the controller off and do it again: the "Found" line should be gone.
2. Back at the menu, pick Propagate Controls and choose 3 ("choose or change my controller layout"). You should see four layouts: Xbox, PlayStation, Nintendo, arcade stick. With the controller on, the line "Found: an Xbox-style controller." shows and choice 1 is pre-selected, but you can pick any layout.
3. Pick a layout. You should see the table "Coin -> Back, Start -> Start, Up/Down/Left/Right, Button 1 to Button 6". PlayStation shows Cross, Circle, Triangle, Square, L1, R1, Share, Options. Nintendo shows B, A, X, Y, L, R, Minus, Plus. Test and Service should say "left empty on purpose".
4. Choose C and change one button (for example Button 6 to LB). Try to give a pad button that is already used to another control: you should be told which control uses it, and nothing changes. Choose K. You should see "Layout saved." Leave the menu, start the Manager again, and open choice 3: your layout and change should still be there. The file is `ControllerBaseline.json` in the Manager's own State folder. Edit it so two controls use the same pad button, then open choice 2: the Manager should ask you to choose again instead of using the damaged file.

## B. Set up one game

You need: one registered game with an Xbox choice in its settings, and a copy of that game's file from the UserProfiles folder kept somewhere safe. Open the game in TeknoParrotUI once first, so its saved settings match the current TeknoParrot version.

5. Pick Propagate Controls, choose 2, then 1 (one game). Type part of a game name and pick the game.
6. At "How will you play...?" choose A. You should see "Nothing changed." The game's file in UserProfiles must be byte-for-byte your safe copy.
7. Do step 5 again and choose X. You should see "Ready to set up N buttons", a list like "Gun Trigger -> A" that uses the game's own button names, how many buttons already had an Xbox setting, and "A saved copy of your game settings is made first." If the game has analog controls (steering, aim, throttle) you should see "Still needs you in TeknoParrotUI". Answer N to "Set this up now?". You should see "Skipped. Nothing changed." The game's file must still match your safe copy.
8. Do step 5 again, choose X, answer Y to "Set this up now?". You should see "Done. ... is set up with your layout and was read back to check it." Now answer Y to "Undo this and put your game settings back as they were?". The game's file must match your safe copy exactly (same size, same bytes).
9. Do step 5 again, choose X, answer Y, and this time answer N to the undo question. A new backup folder named ControllerLayout_... should exist under FullBackup, and the game's file should differ from your safe copy only by added Xbox settings.
10. Do step 5 a third time on the same game. You should see "This game is already set up with your layout." The file must not change (same size and date).
11. Start the game with the controller on. Press each control and write down if the game reacts: Back (Coin), Start, D-pad up, down, left, right, A (button 1), B (button 2), Y (button 3), X (button 4), LB (button 5), RB (button 6) for the Xbox layout. Test and Service are empty on purpose; they should do nothing. Repeat with another layout and check that the buttons you changed in step 4 react as you set them.
12. If the game had keyboard or arcade-encoder buttons before, check they are still in the game's file. Note whether the arcade encoder still works in the game. The screen warns that it may stop.
13. Pick a game that has no Xbox choice in its settings (a wheel or gun game that lists only other input types). You should see "This game does not have an Xbox controller setting. Nothing was changed." Then pick a game you have not opened in TeknoParrotUI since a TeknoParrot update: you should see that its saved settings are for a different version and are left alone.

## C. All games and game by game

14. Pick Propagate Controls, choose 2, then 2 (all my games at once). You should see a preview: how many games are ready (and how many buttons), how many are already set up, and how many are left alone with a reason for each kind. Nothing has changed yet. Press D at the question to see each game and each button.
15. Answer N. You should see "Skipped. Nothing changed." Check that no game file changed and no new backup folder exists.
16. Do step 14 again and answer Y. Each changed game is read back and checked. You should see one backup folder, the counts, and one question to undo the whole run. Answer Y: every game file must match what it was before step 14 (compare with a copy of the folder made before you started).
17. Pick Propagate Controls, choose 2, then 3 (game by game). For each game you should see its list and the question "Set this game up? Y = yes, N = skip, S = stop". Answer Y for one, N for one, and S for the rest. Only the game you answered Y for may change.
18. Open the log. Find the lines that start with "Baseline" and check each step above is written there, with the backup folder and the line saying the layout is built in.

## D. The controls check and Library health

19. Pick Propagate Controls and choose 4. You should see "Controls check. Nothing was changed." with how many games have every control the game lists set up, how many have some, none, or cannot be checked. Press D: each game is named with the controls still missing, and the games TPM cannot check say why (for example "open it once in TeknoParrotUI"). The note must say TPM has not tested any game with a real controller. No game file may change.
20. Compare three games you know well with the check: one you set up fully, one you set up only in part, and one you have not touched. Write down any game that the check calls complete when you know a control is missing, or missing when it is set up.
21. Choose 13 (Library health check). You should see a line starting "Note - N of M games have every control the game lists set up (not tested in a game)". Press D for the list.
22. Write down how long the controls check and the health check took with your library.

## E. Outside controller list check (read-only)

You need: the outside teknoparrot.yml list you want to check (you download it yourself; it is not shipped) and your real TeknoParrot folder.

23. Run, from the Manager folder: `.\TeknoParrot-Manager.ps1 -MappingEvidenceFile "<path to teknoparrot.yml>" -ValidationRoot "<your TeknoParrot folder>" -ValidationJsonPath "<a new file name ending in .json>"`.
24. You should see "Nothing was changed", how many games are in the list and how many are in your TeknoParrot, the counts ready, missing controls and held back, and "TPM does not trust it". Check no file in GameProfiles or UserProfiles changed, and that the only new file is the one you named.
25. Run it again with the same file names. The two details files must be identical.
26. Compare the counts with the earlier audit on issue #200 (523 profiles parsed, 494 matched, 308 collision-free, 36 collision groups in 24 profiles, 7 games held back for collisions). Write down the differences. Differences are expected where the Manager is stricter, but each one should have a reason in the details file.

## F. Saved answers (#201)

You need: your real cabinet or controllers, and the Manager's own settings folder (State\Controls inside the TeknoParrotManager folder).

27. Pick Propagate Controls, choose 1, and answer the seven questions (or choose the Xbox shortcut). At the end, a file `cabinet.json` must exist in State\Controls. The screen said your answers are saved.
28. Run it again. You should see your saved answers and ONE question, "Keep these answers?". Answer Y: no other question, and the plan is the same as before.
29. Run it again, answer N, and change one answer. The saved answer is the default for each question. The new answer must be in the file afterwards, and `cabinet.json.bak` must hold the older answers.
30. Plug in an Xbox controller you said No to. Run the survey. You should see "A controller was found that you said you do not have", and all questions again.
31. Close the Manager. Change `cabinet.json` so it is not valid (add a stray letter). Run the survey. You should get the questions, a `cabinet.json.unreadable-...` copy of the bad file, and a new good `cabinet.json`.

## G. Learning the arcade buttons (#201)

You need: an arcade keyboard encoder with buttons, in a normal console window (not a remote or redirected one). Pick Propagate Controls, choose 5 (My controls), then 2.

32. Answer the number of players and buttons. If LEDBlinky is installed, you should be offered its key list first. Say N once to press them all yourself.
33. TeknoParrot Manager asks "Press Player 1 Coin", "Press Player 1 Start" and so on. Press each control once. After each, you should see "Got it" and the key's name. Check the names for Ctrl, Alt and Shift buttons: Left Ctrl, Left Alt, Left Shift. This is the part unit tests cannot prove.
34. Press the same control twice for two questions. The second time it must say that key is already used, and ask again.
35. Press Esc for a control your cabinet does not have. It must be skipped. Wait 30 seconds without pressing: it must ask if you want to stop, and keep what you pressed so far.
36. At the end answer Y to "Save this?". Open `cabinet.json`: every key you pressed is there. Run again and answer N to Save: the file must not change.
37. If LEDBlinky is installed: run again, accept its key list (Y), and check the keys it proposed match what your buttons really send (press a few). Say how many were right.

## H. Control guides and cabinet list (#267)

38. In My controls choose 3, pick a game, and read the list. Each control must show your key (or "Not learned yet") and "Set up" or "Not set up yet" that matches the game's real settings in TeknoParrot.
39. Answer Y to "Save this as a page you can print, and open it?". A page `<game>-controls.html` must be in the Reports\Control Guides folder and open in your browser. Print it (or print to PDF) and check it is readable on paper.
40. In My controls choose 5. The cabinet page must list the keys you learned.
41. Compare the game's file in UserProfiles with your safe copy from section B: it must be unchanged by steps 27 to 40.

## I. "It worked" and Verified (#307)

Use one plain button game and one wheel or gun game that are already registered and set up.

42. In My controls choose 4, pick the button game, and read the line: it must say TeknoParrot Manager has no record that you played it. Choose B.
43. Start the game, press every control you care about, then come back and choose 4, the game, and W. You should see "Saved" and that the game's controls count as verified. Start a full run or the registration screen: the game must not be listed as still needing a controls check. (To see the text: the Action Required list for a cataloged game, or the support package.)
44. In TeknoParrot, change one binding of that game. Choose 4 and the game again: the first line must now say its controls changed after you tested it. Change it back: the first line must say you tested it again.
45. Choose 4, the game, N. It must say it forgot. Choose 4 and the game again: no record.
46. Do 43 for the wheel or gun game. It must say a setup step is left (calibration). Calibrate in TeknoParrot, then choose 4, the game, S, 2, D. Now W again: it must now count as verified. Change a binding: calibration must be asked for again.
47. Choose 4, the game, S, 1, R ("still to do") on the button game after W: it must stop counting as verified until you choose S, 1, D.
48. Open `control-evidence.json` and read it. It must hold the game name, the date, the game's revision and the steps, and no names of people or computers.

## J. Stuck buttons, standard keys, suggestions and colors (#267)

You need: your arcade encoder in a normal console window. For steps 52 and 53 you also need an encoder that is still on its factory keys (an Ultimarc I-PAC that was never reprogrammed) and, if you have one, an encoder that is not. In My controls choose 2 for steps 49 to 55.

49. Hands off the cabinet. After you answer the two questions you should see "First TPM checks that no button is stuck. Keep your hands off the cabinet for 2 seconds." Nothing should be reported. Write down any key it names: that is a false alarm.
50. Do it again, but hold down one arcade button (or a Ctrl, Alt or Shift button) during the 2 seconds. You should see "Keys are arriving with nobody pressing a button:" and the key's name, then "Continue anyway?". Answer N: "Stopped. Nothing was saved." and `cabinet.json` must not change.
51. On the learning screen, press each control as asked. A normal quick press must show only "Got it". Write down any "also sent" or "still down" line you get on a normal press: that is a false alarm and the most important result of this section.
52. Standard keys, encoder on its factory keys: when you are offered "Many arcade encoders ship with the standard arcade keys", press D. The list must match the Ultimarc I-PAC2 "Default Keycode Table" (for example Player 1 button 1 = Left Ctrl, Start 1 = 1, Coin 1 = 5). Answer Y and press the two buttons it asks for. You should see "Both buttons sent the standard keys, so TPM will use them." Save, then open `cabinet.json`: those controls have the Source `StandardArcadeKeys`. Press a few other buttons that came from the list and write down any that sends a different key.
53. Standard keys, encoder that is not on the standard keys: answer Y and press the button it asks for. You should see "That button sent <key>, not the standard key" and then be asked to press each control. No standard key may be saved. Also try pressing Esc at the check: "TPM did not see the check button".
54. If one of your buttons sends two keys (for example a button wired to send a letter and Ctrl), press it while learning. You should see "Pressing this also sent ..." and "TPM kept ...". If two different buttons send the same extra key, you should also see "came along with 2 different controls". If you have no such button, say so.
55. On a learning question, hold a button for 4 seconds and let go. You should see "This button was still down after 3 seconds". Do it with a Ctrl, Alt or Shift button too. The key must still be kept.
56. In My controls choose 3 and pick a plain button game. Each row for coin, start, a numbered button or a direction must show "Key: ..." with the key you taught TPM, and the line above the list must say how many controls TPM can suggest a key for. Pick a game with a "Menu Up" or "Volume Down" slot: that row must say "I'm not sure", and the key you learned for the stick must not be shown there. Compare with what TeknoParrotUI shows for the game.
57. With LEDBlinky installed, the TeknoParrot lighting added to LEDBlinkyControls.xml, and some control colors set in LEDBlinky's Controls Editor: the guide must show a Light column with the same colors. A color made of three numbers must say "a custom color". Without LEDBlinky, there must be no Light column.
58. Arcade encoder hint: if TPM could see an Ultimarc board when you saved your keys, unplug it and open My controls. You should see "When you taught TPM your buttons it could see 1 arcade encoder. Now it sees 0." Plug it in: the line must go. With an encoder from another maker TPM cannot see it, so no hint is expected: write down the brand.
59. Open `cabinet.json`. `EncodersWhenLearned` must be a small number (or -1). There must be no vendor number, product number, serial number or device path in the file.

## K. What to report

60. Say what you saw for each step number (pass or fail), the encoder and controller models, and the games used.
61. Say if the rule for "Verified" in section I (you say the game worked; calibration done for analog games) is the right one, or what rule you want instead: every control pressed in a real game, only the ones the game needs, or something else.
62. Say which games need a first-run Test or Service menu step or a wheel or gun calibration before play, from what you saw in step 11, so TeknoParrot Manager can list them. Right now only the player's own answer says so, and calibration is assumed for every game that is not plain buttons.
63. Say if the Ctrl, Alt and Shift buttons were seen in step 33, whether any of steps 49 to 55 gave a false alarm, and which encoder brands you use. TeknoParrot Manager does not read any maker's setup file, because no maker publishes which pin is which button.
