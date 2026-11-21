# Controller hands-on test plan (RC9)

For the owner, on the test PC. Unit tests use fake files and cannot press a real button, so these checks are the only proof that the controller setup works in a game. Do them in order. Stop at the first failure and write down the step number and what you saw.

What this covers: the controller-found hint (#410), your controller layout chosen once (#200), setting up one game, all games or game by game from that layout (#306), the controls check of every registered game and the Controls line in the Library health check (#305), and the read-only check of an outside controller list (#304). The next slice, gameplay verification (#307), is waiting on the answers in section F. It only makes sense once the steps before it show that a real controller works.

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

## F. What the next slice needs from you

27. Say what should count as "verified" for one game: you pressed every control in a real game, only the ones the game needs, or a different rule. This decides the #307 evidence record.
28. Say which games need a first-run Test or Service menu step or a wheel or gun calibration before play, from what you saw in step 11.
29. Report back: pass or fail for each step number, the controller models, and the games used.
