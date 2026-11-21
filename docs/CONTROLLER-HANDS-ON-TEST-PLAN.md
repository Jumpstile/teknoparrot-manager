# Controller hands-on test plan (RC9)

For the owner, on the test PC. Unit tests use fake files and cannot press a real button, so these checks are the only proof that the controller setup works in a game. Do them in order. Stop at the first failure and write down the step number and what you saw.

What this covers: the Xbox setup for one game (issue #306, first slice), the controller-found hint (#410), and the read-only check of an outside controller list (#304). The next slice, gameplay verification (#307), is waiting on the answers in section C. It was not built, because it only makes sense once steps 1 to 11 show that a real controller works.

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

## C. What the next slice needs from you

16. Say what should count as "verified" for one game: you pressed every control in a real game, only the ones the game needs, or a different rule. This decides the #307 evidence record.
17. Say which games need a first-run Test or Service menu step or a wheel or gun calibration before play, from what you saw in step 8.
18. Report back: pass or fail for each step number, the controller model, and the games used.
