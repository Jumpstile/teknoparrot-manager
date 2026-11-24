# RC9.2 owner test plan

This is the one list of everything the owner checks by hand before RC9.2 goes out. Automatic tests use fake files and cannot press a real button, open a real game or talk to a real database, so these steps are the proof for those parts. Run the whole list once, at the end, on the test PC. Do not use a TeknoParrot folder or a PC you care about. Write down what you saw for each step; a screenshot helps.

Every step has a tag in square brackets:

- **[no hardware needed]**: you need this PC, TPM and normal game files. No controller and no PostgreSQL.
- **[real PostgreSQL / IT game]**: you need a real PostgreSQL 8.3 and a real Incredible Technologies game (Golden Tee, Power Putt, Silver Strike Bowling and so on), or at least its `pg_backup` folder.
- **[real LaunchBox]**: you need a real LaunchBox with Big Box and your TeknoParrot games in it. Use a copy of your LaunchBox folder, or make a backup first.
- **[real controller]**: you need a real controller, and for some steps a real arcade encoder or a real game that reads it.

Do the parts in order. Stop at the first failure of a part and write down the step number and what you saw. Steps are numbered from 1 to 139 with no repeats.

# Part 1: no hardware needed

## Screens and progress bars

1. **[no hardware needed]** Double-click `TeknoParrot-Manager.bat` so it opens in Windows Terminal. Do not start it from an open terminal tab. Open the main menu. Maximize the window, make it small, then maximize it again. Pass: every row stays inside the window and nothing is pushed to the far right. (#347)
2. **[no hardware needed]** Choose ReShade setup. Pass: the list has three headings in this order: CRT Choices, Main Catalog, and (only on an HDR display) the HDR group. The arrow keys skip the headings.
3. **[no hardware needed]** While the list is on screen, maximize the window. Pass: the current choice and the help line stay on their own rows and nothing wraps to the right.
4. **[no hardware needed]** Open the preview window. Pass: the drop-down has the same headings, the headings cannot be picked, and the text, buttons and picture labels are not cut off.
5. **[no hardware needed]** Repeat the last step at 100%, 125%, 150% and 200% Windows text scaling. Write down any size where text is cut off.
6. **[no hardware needed]** Make the window shorter (not wider) with the list open. Pass: the list redraws and keeps your choice.
7. **[no hardware needed]** Double-click `TeknoParrot-Manager.bat`. Choose AutoSync or Register only so a progress bar appears. Pass: the bar is on one row, inside the window, and does not wrap. Then maximize the window while the bar moves. Pass: the bar redraws on one row. Do it once more from a fresh Windows Terminal tab. If a bar wraps, send the log: the line "console is hosted by a terminal" tells which start type it was. (#384)
8. **[no hardware needed]** Start AutoSync and pick at least two small games that are not extracted yet. Watch the screen when extraction ends and registration ("Register games") begins. Pass: the extraction bar ends as done, then a new bar starts, and no thin blue row is left above it. Then run AutoSync again with every game already up to date: registration starts with no leftover row. Repeat once in Windows Terminal and once in the classic console window. For a fail, add a screenshot and `TeknoParrot-Manager.log`. (#243)

## Large ZIPs, logs and the "what next" screen

9. **[no hardware needed]** Pick one large game ZIP (several GB) that you are allowed to use, on a normal hard drive. Run AutoSync for just that ZIP and write down the minutes spent under "Checking your game ZIP files". Pass: the ZIP is read once for checking, so the time is about one read of the file plus the copy. If it is very long, send the log. (#398)
10. **[no hardware needed]** Disconnect or rename a drive that one registered game uses. Open the main menu and run Library health check. If red error text appears, open the log (View Log). Pass: the log has a line starting "Error shown on screen" for each kind of error you saw, with a count such as "(x12)" for repeats, and no passwords, user folder names or network paths. (#403)
11. **[no hardware needed]** Build a support package. Pass: the same "Error shown on screen" lines are in the package copy of the log.
12. **[no hardware needed]** Have at least one Linux-style game registered (one that runs through BudgieLoader). Run ReShade setup and select all games. Pass: the result says how many Linux-style games were skipped and why, the word "unsafe" is not used, and the folders of those games are unchanged. Open Details: the same reason is shown there. (#407)
13. **[no hardware needed]** Run AutoSync on one new game. Pass: the screen says the files were only unpacked, tells you to check the registration result above, and explains N (New game only), A (Check all games) and B (Back) in plain words. Ask someone who has never used the program to read it and say what N and A do. Write down any word they do not understand. (#408)
14. **[no hardware needed]** Run Propagate Controls (menu 4, choice 1) on a library where some control types (lightgun, driving) have no example game. Pass: the result names one game of each of those types to set up first, and the Details view has a "Games to set up first" part. Pass: the last banner of an AutoSync run says "Registration run finished", not "Done". (#342)
15. **[no hardware needed]** Open Propagate Controls (menu 4). Pass: the line under the title says "This screen never registers or unpacks games." and the five choices are listed. Choose 1 and then press Enter at the end: no game is registered or unpacked.

## Every game registers, and the Eggman guide steps

Use your real Eggman collection on the test PC. Copy it first or use a test TeknoParrot folder. (#389, #351)

16. **[no hardware needed]** Run Register only (or AutoSync) on the whole collection. Pass: every game folder ends as Registered, Already set, a duplicate with a reason, or "not in TeknoParrot". No folder disappears without a line in the result or the log.
17. **[no hardware needed]** Pick two versions of one game that read almost the same (Chaos Code - New Sign of Catastrophe 1.03.00 and 2.11.00). Pass: both are registered.
18. **[no hardware needed]** Pick The King of Fighters XII and The King of Fighters XIV, and Total Vice (AAB) and Total Vice (EBA). Pass: each gets its own profile (the XII folder is not given the XIV profile).
19. **[no hardware needed]** Pick DrumMania (GQ881) and Dance Dance Revolution 2nd Mix - Link Ver. Pass: both are registered with the parent ZIP (pcnfrk.zip, ddr2m.zip).
20. **[no hardware needed]** Pick After Burner Climax, Virtua Fighter 5 (1.001 Ver B) and R-Tuned. Pass: TeknoParrot shows the Lindbergh profile and the ElfLdr2 profile of each. Start one ElfLdr2 game from TeknoParrot and write down whether it starts.
21. **[no hardware needed]** Pick Minecraft Dungeons Arcade and Golden Tee Fore! 2004. Pass: both are registered.
22. **[no hardware needed]** Open the Sega Rally 3 track mod folders. Pass: they are listed as "not in TeknoParrot", not as a failed profile.
23. **[no hardware needed]** Open `docs\GAME-SUPPORT.md`. Pass: the totals read 2553 game IDs and 9 Gap rows. Seven of the Gap rows are the Sega Rally 3 track mods (6) and Escape from Monster Manor: TeknoParrot has no profile for them. The other two (Battle Gear 3 and Wayne Gretzky's 3D Hockey Fatality Edition) run through a linked profile. The page also has a "Second profile not written" line for four games (House of the Dead 4, Raiden III, Raiden IV, Densha de GO); they are not Gap rows.
24. **[no hardware needed]** Run a BepInEx install (menu 10) on one BepInEx game (for example Family Guy Bowling). Pass: the result tells you to start the game and close it twice the first time, and the game then starts.
25. **[no hardware needed]** Required fixes, exact builds. Register Family Guy Bowling, then choose 13) Required game patches, then A. Pass: it lists the fix, Y installs it, U puts everything back, and the game starts after install.
26. **[no hardware needed]** Graphics card choice. Do the last step with Shining Force Cross Elysion on a PC with an AMD card and again on one with an NVIDIA card. Pass: it asks which card you have when it cannot tell, installs only that card's file, and skips a file that is already right.
27. **[no hardware needed]** Wrong build. Point menu 13 at a build it does not list (for example another Family Guy Bowling version). Pass: nothing is changed and the screen says so.
28. **[no hardware needed]** Game Notes. Register one game from each group: a ROM game with a second (CHD) file, a game with a version (variant), a game whose guide row says an AMD, NVIDIA or Intel card works only with a fix, and a game the guide marks Broken. Open the Game Notes file. Pass: each game's steps match what the guide page says for that game, and the Broken game is named as broken. Do the notes' steps for two of those games. Pass: the game starts and the steps were enough.

## CPS3 first-boot files with your real set

Use the test PC. Close TeknoParrot and any CPS3 game. Copy your whole `TeknoCPS` folder somewhere safe first: that is your way back. Register at least one CPS3 game (Street Fighter III, JoJo, Red Earth or the CPS3 multi-game). Pick one `.nv` file that already exists in `TeknoCPS\nvram` and write down its size and date. TPM never supplies, downloads or points to these files. (#349)

29. **[no hardware needed]** Optional, never touches your real folder: set `TPM_REAL_SOURCE_TESTS=1` and set `TPM_CPS3_REAL_SOURCE` to your set (folder or `.zip`). Run `Tests\TpmCps3Supplementary.Tests.ps1`. Pass: 34 tests run, none skipped, none failed.
30. **[no hardware needed]** Run TeknoParrot Manager. At the CPS3 question answer Y, then pick your folder or `.zip`. Pass: it says `Copied and verified N file(s)`, where N is 101 minus the `.nv` files you already had.
31. **[no hardware needed]** Look at the TeknoParrot folder. Pass: `TeknoCPS\cps3-install` holds 18 `.simms` files and the file starting `aeeba2be` is not there; `TeknoCPS\nvram` holds 83 `.nv` files; `README.txt` was not copied in. Every `.simms` name in the table in `Get-TpmCps3SupplementaryManifest` is present, and no other name was added.
32. **[no hardware needed]** Check the `.nv` file you wrote down earlier. Pass: same size, same date, same content.
33. **[no hardware needed]** Run the step again. Pass: it says nothing needs to be copied, and no file date changes.
34. **[no hardware needed]** Start one game from each family and write down how long the first start takes: Street Fighter III New Generation, 2nd Impact and 3rd Strike; JoJo; Red Earth; the CPS3 multi-game (`cps3boot`). Pass: each game reaches its attract screen with no long cache build and no error.
35. **[no hardware needed]** Make a copy of your set, delete one `.nv` file from the copy, and point TPM at the copy. Pass: it refuses the whole set and copies nothing. Write the result on issue 349.

## Bezels from your own folder

Do these on the test PC with a copy of a few games, not your main library. The automatic tests already prove the matching, the keep-your-own-file rule and Undo. These steps need your real files and screen. (#429)

36. **[no hardware needed]** Pick one game you can run now (a plain one that starts from its own `.exe`, not from a shared loader). Set up ReShade for it first (main menu 6, then S). Put one bezel picture for that game in an empty folder, for example `C:\TestBezels` (a real `.png`). Main menu 6, then B, then Enter, and point it at `C:\TestBezels`. Read the preview: the game name and bezel name are the ones you expect. Press A. Pass: `Done. 1 bezel copied and checked.`
37. **[no hardware needed]** Start the game. Press Home to open the ReShade overlay and turn on the effect that draws a border or overlay (for example Border). Write down: does the bezel show, is it the right picture, and is the shape right for your screen (wide or 4:3)? Write on issue 429 which game, which graphics type, shown or not, and what you had to turn on.
38. **[no hardware needed]** Repeat the last two steps with one game each for Direct3D 9, Direct3D 11 and OpenGL, one game that starts through a loader program, and one that runs in exclusive fullscreen. Write down which ones show the bezel. If some never do, the screen text should say so before you apply.
39. **[no hardware needed]** Matching on your real bezel folder (use a copy of the folder). Main menu 6, then B, then Enter, point it at your folder, read the preview, and press Enter to cancel. Count the rows that say High, Medium, Low or "needs your choice", and the games with no bezel. Check each High and Medium row by eye. Write down any wrong ones with the file name and game name. If more than about one in twenty High or Medium rows is wrong, the High cut-off (85 percent) needs raising before release.
40. **[no hardware needed]** Put your own `bezel.png` by hand in a test game's `reshade-shaders\Textures` folder. Run the bezel step. Pass: the game says `has a bezel you placed`. Press A and answer N to the replace question: your file is unchanged. Run it again and answer Y: your file is replaced. Then main menu 6, B, U, answer Y: your original file is back, byte for byte.
41. **[no hardware needed]** Apply a bezel, then paste a different picture over `bezel.png` yourself. Run Undo. Pass: it says the game was left alone and your new picture is still there. Try a game that shares its folder with other games: it says so and is skipped. Cancel at the preview for any run: no `bezel.png` is written.

## Other checks

42. **[no hardware needed]** Open the repository page and look at the Contributors list. Write down every name shown. Pass: only the owner is shown. If another name appears, do not rewrite history. First look at the commit messages on the branch you are about to merge: any "Co-authored-by" line that names someone other than the owner can add that name when the branch reaches the main branch. Decide whether to keep or remove those lines before merging. A refresh can take up to 24 hours. (#375)
43. **[no hardware needed]** Do the new tests in the Tester Guide, tests 52 to 66 (`docs\TESTER-GUIDE.md`): game types in the health check, System 11, game sets, LaunchBox names, groups, sync and pictures, bezels, startup files for Chihiro and PlayStation 3, and the update screen. Write down any test you could not do.

# Part 2: real PostgreSQL / IT game

## Incredible Technologies games and their databases

Use a test PC or a test TeknoParrot folder. Do not use a PC that holds PostgreSQL data you need. This part needs a real PostgreSQL 8.3. Have three games ready: (A) a game that has a `pg_backup` folder, for example Power Putt Live 2013; (B) Golden Tee Live 2021 or newer, or a Golden Tee PGA Tour game, with no `pg_backup` folder; (C) any game of this kind left on the Storage choice Internal. (#350, #131)

44. **[real PostgreSQL / IT game]** From the main menu choose PostgreSQL setup on a PC where TPM is not running as administrator. Pass: the explanation appears and TPM waits for Enter. The Windows permission window opens only after you press Enter. (#385)
45. **[real PostgreSQL / IT game]** In TeknoParrot, set Storage to Existing PostgreSQL for (A) and (B). Leave (C) on Internal.
46. **[real PostgreSQL / IT game]** Run Register only (or AutoSync). Pass: every game is registered by its own name, including (B), the Golden Tee Live 2023-2024 game and the PGA Tour games, which are not in the Eggman list. None is sent to the ACTION REQUIRED list.
47. **[real PostgreSQL / IT game]** Choose 12) Postgres setup. Pass: (A) says `Ready ... created from the game's own backup`. (B) says `Profile ready`. (C) is skipped. The run ends as finished, not as "needing attention". Write down the exact words of the (B) line.
48. **[real PostgreSQL / IT game]** Choose 14) Library health check. Pass: the PostgreSQL row says `OK - profile ready; a game database is created the first time the game starts` and (B) is not called a problem. Press D: (B) is listed under `Profile ready; the database is created the first time the game starts`.
49. **[real PostgreSQL / IT game]** Start (B) from TeknoParrot once. Pass: the game starts and TeknoParrot makes its database (TeknoParrot's own "Automatically create Database").
50. **[real PostgreSQL / IT game]** Run Library health check again. Pass: the PostgreSQL row says `OK` and (B) is no longer listed as waiting.
51. **[real PostgreSQL / IT game]** Start (A) and (C). Pass: both start. (C) needs no PostgreSQL install; start it once so it makes its own database.
52. **[real PostgreSQL / IT game]** On a PC with an Intel graphics card: run Register only and read the compatibility warnings. Pass: every registered Golden Tee Live 2011 and newer game and every PGA Tour game is named as not working on Intel graphics. Write down whether the game starts.
53. **[real PostgreSQL / IT game]** Write down any game of this kind that did not register, did not reach `Ready` or `Profile ready`, or did not start.

## Games that share one database name (Golden Tee Live 2006 and Orange County Choppers Pinball)

This needs the real games (or at least both games' `pg_backup` folders) and a real PostgreSQL 8.3. Use a test PC. A full copy of every PostgreSQL database is the first step; keep it until you are done. (#350, #131)

54. **[real PostgreSQL / IT game]** Make a full backup first. In a Command Prompt on the test PC run `pg_dumpall -U postgres -f gameDbBackup.sql` from the PostgreSQL 8.3 `bin` folder. Check the file is not empty.
55. **[real PostgreSQL / IT game]** Register Golden Tee Live 2006 and Orange County Choppers Pinball in TeknoParrot. Set Storage to Existing PostgreSQL for both. Check that both profiles show the database name `GameDB06`.
56. **[real PostgreSQL / IT game]** Run Library health check. Pass: the PostgreSQL row says some games use the same database, and Details names both games and `GameDB06`.
57. **[real PostgreSQL / IT game]** Run Postgres setup (menu 12). Pass: the result says `Own database` for Orange County Choppers Pinball, names `GameDB06OCCPinball`, and says nothing was deleted or overwritten. Open the Orange County Choppers Pinball profile in TeknoParrot. Pass: its database name is `GameDB06OCCPinball`; the Golden Tee Live 2006 profile still says `GameDB06`.
58. **[real PostgreSQL / IT game]** Run Library health check again. Pass: no game is called sharing a database, and the PostgreSQL row says `OK`.
59. **[real PostgreSQL / IT game]** Start Golden Tee Live 2006, play a short game, and quit. Start Orange County Choppers Pinball, play a short game, and quit. Pass: both start and each shows only its own saved scores and settings. Write down any message that mentions a database or a missing table.
60. **[real PostgreSQL / IT game]** Run Postgres setup a second time. Pass: it says nothing needed changing, and no database was created.
61. **[real PostgreSQL / IT game]** Repeat the registration and health steps with only one of the two games registered. Pass: its database name is not changed.
62. **[real PostgreSQL / IT game]** If you already had a `GameDB06` with saved progress, register Orange County Choppers Pinball later. Pass: `GameDB06` is left as it is (check its scores), and Orange County Choppers Pinball gets its own new database.
63. **[real PostgreSQL / IT game]** Golden Tee Live 2006 backup: after the setup above, check that the table `category2_attr` in its database has rows. Pass: it is not empty. If a game does not accept the new database name, restore the `pg_dumpall` file from the first step and tell the developer.

# Part 3: real controller

Unit tests use fake files and cannot press a real button, so these checks are the only proof that the controller setup works in a game. They cover: your controller layout chosen once (#200), setting up one game, all games or game by game from that layout (#306), the controls check of every registered game and the Controls line in the Library health check (#305), the read-only check of an outside controller list (#304), the saved answers and button learning (#201), the control guides and cabinet list (#267), the stuck-button check, the standard arcade keys, key suggestions and light colors (#267), the "it worked" records that decide when a game is Verified (#307), and the controller-found hint (#410). The parts after the layout and game setup use only TPM's own files. They never change a game's file in UserProfiles; step 104 checks that.

## Your controller layout (nothing in any game changes)

You need: one controller (wired, or wireless and switched on). Do this with an Xbox-style controller first. Repeat steps 66 and 67 with a PlayStation controller, a Nintendo controller and an arcade stick if you own them. A PlayStation or Nintendo controller must be shown to Windows as an Xbox controller (by a controller mapping program you already use), and an arcade stick must be in its Xbox mode.

64. **[real controller]** Plug in the controller (or switch it on). Start TeknoParrot Manager, pick Propagate Controls, and choose 1. You should see "Found: an Xbox-style controller." Keep answering N until the plan prints (it changes nothing). Then switch the controller off and do it again: the "Found" line should be gone.
65. **[real controller]** Back at the menu, pick Propagate Controls and choose 3 ("choose or change my controller layout"). You should see four layouts: Xbox, PlayStation, Nintendo, arcade stick. With the controller on, the line "Found: an Xbox-style controller." shows and choice 1 is pre-selected, but you can pick any layout.
66. **[real controller]** Pick a layout. You should see the table "Coin -> Back, Start -> Start, Up/Down/Left/Right, Button 1 to Button 6". PlayStation shows Cross, Circle, Triangle, Square, L1, R1, Share, Options. Nintendo shows B, A, X, Y, L, R, Minus, Plus. Test and Service should say "left empty on purpose".
67. **[real controller]** Choose C and change one button (for example Button 6 to LB). Try to give a pad button that is already used to another control: you should be told which control uses it, and nothing changes. Choose K. You should see "Layout saved." Leave the menu, start TPM again, and open choice 3: your layout and change should still be there. The file is `ControllerBaseline.json` in TPM's own State folder. Edit it so two controls use the same pad button, then open choice 2: TPM should ask you to choose again instead of using the damaged file.

## Set up one game

You need: one registered game with an Xbox choice in its settings, and a copy of that game's file from the UserProfiles folder kept somewhere safe. Open the game in TeknoParrotUI once first, so its saved settings match the current TeknoParrot version.

68. **[real controller]** Pick Propagate Controls, choose 2, then 1 (one game). Type part of a game name and pick the game.
69. **[real controller]** At "How will you play...?" choose A. You should see "Nothing changed." The game's file in UserProfiles must be byte-for-byte your safe copy.
70. **[real controller]** Do step 68 again and choose X. You should see "Ready to set up N buttons", a list like "Gun Trigger -> A" that uses the game's own button names, how many buttons already had an Xbox setting, and "A saved copy of your game settings is made first." If the game has analog controls (steering, aim, throttle) you should see "Still needs you in TeknoParrotUI". Answer N to "Set this up now?". You should see "Skipped. Nothing changed." The game's file must still match your safe copy.
71. **[real controller]** Do step 68 again, choose X, answer Y to "Set this up now?". You should see "Done. ... is set up with your layout and was read back to check it." Now answer Y to "Undo this and put your game settings back as they were?". The game's file must match your safe copy exactly (same size, same bytes).
72. **[real controller]** Do step 68 again, choose X, answer Y, and this time answer N to the undo question. A new backup folder named ControllerLayout_... should exist under FullBackup, and the game's file should differ from your safe copy only by added Xbox settings.
73. **[real controller]** Do step 68 a third time on the same game. You should see "This game is already set up with your layout." The file must not change (same size and date).
74. **[real controller]** Start the game with the controller on. Press each control and write down if the game reacts: Back (Coin), Start, D-pad up, down, left, right, A (button 1), B (button 2), Y (button 3), X (button 4), LB (button 5), RB (button 6) for the Xbox layout. Test and Service are empty on purpose; they should do nothing. Repeat with another layout and check that the buttons you changed in step 67 react as you set them.
75. **[real controller]** If the game had keyboard or arcade-encoder buttons before, check they are still in the game's file. Note whether the arcade encoder still works in the game. The screen warns that it may stop.
76. **[real controller]** Pick a game that has no Xbox choice in its settings (a wheel or gun game that lists only other input types). You should see "This game does not have an Xbox controller setting. Nothing was changed." Then pick a game you have not opened in TeknoParrotUI since a TeknoParrot update: you should see that its saved settings are for a different version and are left alone.

## All games and game by game

77. **[real controller]** Pick Propagate Controls, choose 2, then 2 (all my games at once). You should see a preview: how many games are ready (and how many buttons), how many are already set up, and how many are left alone with a reason for each kind. Nothing has changed yet. Press D at the question to see each game and each button.
78. **[real controller]** Answer N. You should see "Skipped. Nothing changed." Check that no game file changed and no new backup folder exists.
79. **[real controller]** Do step 77 again and answer Y. Each changed game is read back and checked. You should see one backup folder, the counts, and one question to undo the whole run. Answer Y: every game file must match what it was before step 77 (compare with a copy of the folder made before you started).
80. **[real controller]** Pick Propagate Controls, choose 2, then 3 (game by game). For each game you should see its list and the question "Set this game up? Y = yes, N = skip, S = stop". Answer Y for one, N for one, and S for the rest. Only the game you answered Y for may change.
81. **[real controller]** Open the log. Find the lines that start with "Baseline" and check each step above is written there, with the backup folder and the line saying the layout is built in.

## The controls check and Library health

82. **[real controller]** Pick Propagate Controls and choose 4. You should see "Controls check. Nothing was changed." with how many games have every control the game lists set up, how many have some, none, or cannot be checked. Press D: each game is named with the controls still missing, and the games TPM cannot check say why (for example "open it once in TeknoParrotUI"). The note must say TPM has not tested any game with a real controller. No game file may change.
83. **[real controller]** Compare three games you know well with the check: one you set up fully, one you set up only in part, and one you have not touched. Write down any game that the check calls complete when you know a control is missing, or missing when it is set up.
84. **[real controller]** Choose 14 (Library health check). You should see a line starting "Note - N of M games have every control the game lists set up (not tested in a game)". Press D for the list.
85. **[real controller]** Write down how long the controls check and the health check took with your library.

## Outside controller list check (read-only)

You need: the outside teknoparrot.yml list you want to check (you download it yourself; it is not shipped) and your real TeknoParrot folder.

86. **[real controller]** Run, from the TPM folder: `.\TeknoParrot-Manager.ps1 -MappingEvidenceFile "<path to teknoparrot.yml>" -ValidationRoot "<your TeknoParrot folder>" -ValidationJsonPath "<a new file name ending in .json>"`.
87. **[real controller]** You should see "Nothing was changed", how many games are in the list and how many are in your TeknoParrot, the counts ready, missing controls and held back, and "TPM does not trust it". Check no file in GameProfiles or UserProfiles changed, and that the only new file is the one you named.
88. **[real controller]** Run it again with the same file names. The two details files must be identical.
89. **[real controller]** Compare the counts with the earlier audit on issue #200 (523 profiles parsed, 494 matched, 308 collision-free, 36 collision groups in 24 profiles, 7 games held back for collisions). Write down the differences. Differences are expected where TPM is stricter, but each one should have a reason in the details file.

## Saved answers

You need: your real cabinet or controllers, and TPM's own settings folder (State\Controls inside the TeknoParrotManager folder).

90. **[real controller]** Pick Propagate Controls, choose 1, and answer the seven questions (or choose the Xbox shortcut). At the end, a file `cabinet.json` must exist in State\Controls. The screen said your answers are saved.
91. **[real controller]** Run it again. You should see your saved answers and ONE question, "Keep these answers?". Answer Y: no other question, and the plan is the same as before.
92. **[real controller]** Run it again, answer N, and change one answer. The saved answer is the default for each question. The new answer must be in the file afterwards, and `cabinet.json.bak` must hold the older answers.
93. **[real controller]** Plug in an Xbox controller you said No to. Run the survey. You should see "A controller was found that you said you do not have", and all questions again.
94. **[real controller]** Close TPM. Change `cabinet.json` so it is not valid (add a stray letter). Run the survey. You should get the questions, a `cabinet.json.unreadable-...` copy of the bad file, and a new good `cabinet.json`.

## Learning the arcade buttons

You need: an arcade keyboard encoder with buttons, in a normal console window (not a remote or redirected one). Pick Propagate Controls, choose 5 (My controls), then 2.

95. **[real controller]** Answer the number of players and buttons. If LEDBlinky is installed, you should be offered its key list first. Say N once to press them all yourself.
96. **[real controller]** TeknoParrot Manager asks "Press Player 1 Coin", "Press Player 1 Start" and so on. Press each control once. After each, you should see "Got it" and the key's name. Check the names for Ctrl, Alt and Shift buttons: Left Ctrl, Left Alt, Left Shift. This is the part unit tests cannot prove.
97. **[real controller]** Press the same control twice for two questions. The second time it must say that key is already used, and ask again.
98. **[real controller]** Press Esc for an ordinary control your cabinet does not have (not Exit, Pause or Menu: Esc counts as a key for those, see step 136). It must be skipped. Wait 30 seconds without pressing: it must ask if you want to stop, and keep what you pressed so far.
99. **[real controller]** At the end answer Y to "Save this?". Open `cabinet.json`: every key you pressed is there. Run again and answer N to Save: the file must not change.
100. **[real controller]** If LEDBlinky is installed: run again, accept its key list (Y), and check the keys it proposed match what your buttons really send (press a few). Say how many were right.

## Control guides and cabinet list

101. **[real controller]** In My controls choose 3, pick a game, and read the list. Each control must show your key (or "Not learned yet") and "Set up" or "Not set up yet" that matches the game's real settings in TeknoParrot.
102. **[real controller]** Answer Y to "Save this as a page you can print, and open it?". A page `<game>-controls.html` must be in the Reports\Control Guides folder and open in your browser. Print it (or print to PDF) and check it is readable on paper.
103. **[real controller]** In My controls choose 5. The cabinet page must list the keys you learned.
104. **[real controller]** Compare the game's file in UserProfiles with your safe copy from the "Set up one game" part: it must be unchanged by steps 90 to 103.

## "It worked" and Verified

Use one plain button game and one wheel or gun game that are already registered and set up.

105. **[real controller]** In My controls choose 4, pick the button game, and read the line: it must say TeknoParrot Manager has no record that you played it. Choose B.
106. **[real controller]** Start the game, press every control you care about, then come back and choose 4, the game, and W. You should see "Saved" and that the game's controls count as verified. Start a full run or the registration screen: the game must not be listed as still needing a controls check. (To see the text: the Action Required list for a cataloged game, or the support package.)
107. **[real controller]** In TeknoParrot, change one binding of that game. Choose 4 and the game again: the first line must now say its controls changed after you tested it. Change it back: the first line must say you tested it again.
108. **[real controller]** Choose 4, the game, N. It must say it forgot. Choose 4 and the game again: no record.
109. **[real controller]** Do 106 for the wheel or gun game. It must say a setup step is left (calibration). Calibrate in TeknoParrot, then choose 4, the game, S, 2, D. Now W again: it must now count as verified. Change a binding: calibration must be asked for again.
110. **[real controller]** Choose 4, the game, S, 1, R ("still to do") on the button game after W: it must stop counting as verified until you choose S, 1, D.
111. **[real controller]** Open `control-evidence.json` and read it. It must hold the game name, the date, the game's revision and the steps, and no names of people or computers.

## Stuck buttons, standard keys, suggestions, colors and a changed controller

You need: your arcade encoder in a normal console window. For steps 115 and 116 you also need an encoder that is still on its factory keys (an Ultimarc I-PAC that was never reprogrammed) and, if you have one, an encoder that is not. In My controls choose 2 for steps 112 to 118.

112. **[real controller]** Hands off the cabinet. After you answer the two questions you should see "First TPM checks that no button is stuck. Keep your hands off the cabinet for 2 seconds." Nothing should be reported. Write down any key it names: that is a false alarm.
113. **[real controller]** Do it again, but hold down one arcade button (or a Ctrl, Alt or Shift button) during the 2 seconds. You should see "Keys are arriving with nobody pressing a button:" and the key's name, then "Continue anyway?". Answer N: "Stopped. Nothing was saved." and `cabinet.json` must not change.
114. **[real controller]** On the learning screen, press each control as asked. A normal quick press must show only "Got it". Write down any "also sent" or "still down" line you get on a normal press: that is a false alarm and the most important result of this part.
115. **[real controller]** Standard keys, encoder on its factory keys: when you are offered "Many arcade encoders ship with the standard arcade keys", press D. The list must match the Ultimarc I-PAC2 "Default Keycode Table" (for example Player 1 button 1 = Left Ctrl, Start 1 = 1, Coin 1 = 5). Answer Y and press the two buttons it asks for. You should see "Both buttons sent the standard keys, so TPM will use them." Save, then open `cabinet.json`: those controls have the Source `StandardArcadeKeys`. Press a few other buttons that came from the list and write down any that sends a different key.
116. **[real controller]** Standard keys, encoder that is not on the standard keys: answer Y and press the button it asks for. You should see "That button sent <key>, not the standard key" and then be asked to press each control. No standard key may be saved. Also try pressing Esc at the check: "TPM did not see the check button".
117. **[real controller]** If one of your buttons sends two keys (for example a button wired to send a letter and Ctrl), press it while learning. You should see "Pressing this also sent ..." and "TPM kept ...". If two different buttons send the same extra key, you should also see "came along with 2 different controls". If you have no such button, say so.
118. **[real controller]** On a learning question, hold a button for 4 seconds and let go. You should see "This button was still down after 3 seconds". Do it with a Ctrl, Alt or Shift button too. The key must still be kept.
119. **[real controller]** In My controls choose 3 and pick a plain button game. Each row for coin, start, a numbered button or a direction must show "Key: ..." with the key you taught TPM, and the line above the list must say how many controls TPM can suggest a key for. Pick a game with a "Menu Up" or "Volume Down" slot: that row must say "I'm not sure", and the key you learned for the stick must not be shown there. Compare with what TeknoParrotUI shows for the game.
120. **[real controller]** With LEDBlinky installed, the TeknoParrot lighting added to LEDBlinkyControls.xml, and some control colors set in LEDBlinky's Controls Editor: the guide must show a Light column with the same colors. A color made of three numbers must say "a custom color". Without LEDBlinky, there must be no Light column.
121. **[real controller]** Same controller: with your Ultimarc board plugged in, choose 2 in My controls and save your keys. Open My controls again and choose 1 (Tell TPM which controls I have). Both screens must say "TPM sees the same arcade encoder as when you taught it your keys." (the line is green on My controls).
122. **[real controller]** Unplug the board and open My controls. It must say "An arcade encoder that was plugged in when you taught TPM your keys is not plugged in now. If you changed your controller, learn your buttons again. Your saved keys were not changed." Plug it in again: the "same" line must come back. Choose 5: your keys must still be there, unchanged.
123. **[real controller]** Another USB port: unplug the board and plug it into a different port (use a USB hub too if you have one). It must still say "the same". Write down any port or hub that makes it say a controller was added or removed: that is a false alarm.
124. **[real controller]** Two identical boards, if you have two of the same model: plug in both and save your keys. Unplug one: it must say an encoder is not plugged in now. Plug it in: "the same" again. Then save with only one plugged in and plug in the second: it must say "A new arcade encoder is plugged in". If you have only one board, say so.
125. **[real controller]** A different encoder: save your keys with one encoder, then swap it for another model or maker. For an Ultimarc board it must say your encoders are different (or one was added or removed). For a brand TPM does not recognize it must say "TPM does not recognize your arcade encoder by itself, so it cannot tell if you changed it." Write down the brand and model. Swapping a board for an identical one is not noticed, and that is expected.
126. **[real controller]** Could not check: close TPM, rename `controller-salt.txt` in `State\Controls` to another name, start TPM and open My controls. It must say "TPM could not look at your controllers, so it cannot tell if they changed since you taught it your keys." Nothing else may change. Rename the file back (the line from step 121 must return), or learn your buttons again (TPM then makes a new private code file and says "the same" again).
127. **[real controller]** A controller change is only a hint: after steps 122 and 125, open "Tell TPM how a game played" for a game you marked as working. Its status must be exactly what it was before. A changed controller must never change a saved key, a saved answer or a Verified game.
128. **[real controller]** Open `cabinet.json`. `EncodersWhenLearned` must be a small number (or -1) and `EncoderFingerprints` must hold only long codes made of the letters a to f and digits, one per encoder (the list is empty if no encoder was recognized). There must be no vendor number, product number, serial number, instance id or device path in the file, in `controller-salt.txt`, in `TeknoParrot-Manager.log`, or in a saved control guide page. Do not post `controller-salt.txt` anywhere.

## What to report

129. **[real controller]** Say what you saw for each step number (pass or fail), the encoder and controller models, and the games used.
130. **[real controller]** Say if the rule for "Verified" in the "It worked" and Verified part (you say the game worked; calibration done for analog games) is the right one, or what rule you want instead: every control pressed in a real game, only the ones the game needs, or something else.
131. **[real controller]** Say which games need a first-run Test or Service menu step or a wheel or gun calibration before play, from what you saw in step 74, so TeknoParrot Manager can list them. Right now only the player's own answer says so, and calibration is assumed for every game that is not plain buttons.
132. **[real controller]** Say if the Ctrl, Alt and Shift buttons were seen in step 96, whether any of steps 112 to 118 gave a false alarm, and which encoder brands you use. TeknoParrot Manager does not read any maker's setup file, because no maker publishes which pin is which button. Say what steps 121 to 128 showed, and whether TPM recognized your encoder at all.

## Cabinet fit, Exit/Pause/Menu and undo (#267)

133. **[no hardware needed]** In My controls choose 1 and say you have no steering wheel and no light gun but you do have an Xbox controller. Choose 3 and pick a wheel game. Pass: the page starts with "This game needs a steering wheel and pedals. You told TPM you do not have that." and "Your Xbox controller can steer this game with its stick and triggers." Pick a light gun game: it must say the game needs a light gun. Nothing in the game's file may change.
134. **[no hardware needed]** Close TPM, rename `cabinet.json` in `State\Controls`, open My controls and choose 3 for any game. Pass: the page says TPM does not know how many players and buttons your cabinet has and does not say it fits. Put the file back.
135. **[real controller]** Learn your buttons for 1 player and 2 buttons, save, then choose 3 for a game that uses 3 or more buttons or 2 players. Pass: the page says your cabinet has fewer buttons or players than the game uses, and those rows say "Your cabinet has no button 3" or "Your cabinet has no player 2" instead of "Not learned yet". Rows for the buttons you do have still show your key.
136. **[real controller]** On the learning screen, after Service, TPM asks "Does your cabinet have the Exit button? (Y/N)", then Pause, then Menu. Answer N for Pause. Answer Y for Exit and press the Esc key if your cabinet's Exit button sends Esc. Pass: Esc is accepted as the key (not skipped), Pause is listed as skipped, and after you save, My controls choice 5 lists Exit.
137. **[no hardware needed]** Save your answers twice (for example learn your buttons, save, then learn again with a different key and save). Choose 6 "Undo my last save". Pass: it says how many controls TPM knew before and now, asks once, and after Y the cabinet page (choice 5) shows the older keys. Choose 6 again: the newer keys come back. In `State\Controls`, `cabinet.json.bak` always holds the answers that were replaced last.
138. **[no hardware needed]** Open the log. Pass: it has a line "Controls: <game>: cabinet fit: ..." for every guide you opened in steps 133 to 135, and a line "the player put back the answers saved before the last save" for step 137. No controller hardware ID may appear in the log.

# Part 4: real LaunchBox

## Players and controllers in Big Box (#267)

139. **[real LaunchBox]** Use a COPY of your LaunchBox folder, or make a backup of it first. Close LaunchBox and BigBox. In TPM run the LaunchBox step and choose `C` (Fill in players and controllers for Big Box), then platform 2. Pass: the preview says how many games would get player info and controllers and "Nothing was changed"; press `D` and every line names a game and what it would get; the `Data\Platforms\TeknoParrot.xml` file is unchanged. Answer `N` at `Make exactly these changes after a verified backup?` and check the file is still unchanged. Run `C` again and answer `Y`. Pass: a saved copy is made first, and the result says it was saved. Answer `N` to `Undo this now`. Open LaunchBox, then Big Box. Pass: a TeknoParrot game you did not fill in yourself (for example a gun game or a racing game) shows its player count and its controller badge (light gun or wheel) in Big Box and in the game's Edit screen under Controller Support, and a game that already had a player count or controllers in LaunchBox still shows exactly what it showed before. Close both and run `C` once more: it must say there is nothing to fill in. Then use menu 14 (Restore backup), choose 3 (LaunchBox library backup) and pick the newest copy: LaunchBox must show the old values again. Run `C` one more time, say `Y`, and answer `Y` to `Undo this now`: the old values must be back at once. Say what you saw, and anything LaunchBox changed that you did not expect.
