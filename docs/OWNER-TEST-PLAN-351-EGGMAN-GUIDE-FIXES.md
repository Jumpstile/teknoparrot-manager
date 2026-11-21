# Owner test plan: Eggman guide fixes (issue 351)

## Where it stands

TeknoParrot Manager shows the guide's notes for your registered games in the Game Notes file. It applies the reviewed required fixes (menu 12) for the games it has recipes for. The rest of this issue is checking real games, which only the test PC can do.

A check of the current guide page against the program found nothing that needed a code change:

- The Game Notes step reads the live guide on Windows PowerShell 5.1 and PowerShell 7 with the same result.
- With every guide game registered, 1,425 of the 2,465 guide IDs have something to show (notes, setup steps, graphics card notes, a second file, a linked profile or a status).

`docs\GAME-SUPPORT.md` is now made again from the live guide (1,607 games and 858 versions) and the current TeknoParrot profiles (2,541). It has 9 Gap rows. They are extra archives that TeknoParrot has no profile for (see Details). The full game-by-game check of registration is in `docs\RC9-OWNER-TEST-PLAN.md` (issue 389).

## Test

You need the test PC and your own copies of the games.

1. Required fixes, exact builds. Register Family Guy Bowling, then choose **12) Required game patches**, then **A**. Pass: it lists the fix, **Y** installs it, **U** puts everything back, and the game starts after install.
2. Graphics card choice. Do step 1 with Shining Force Cross Elysion on a PC with an AMD card and again on one with an NVIDIA card. Pass: it asks which card you have when it cannot tell, installs only that card's file, and skips a file that is already right.
3. Wrong build. Point menu 12 at a build it does not list (for example another Family Guy Bowling version). Pass: nothing is changed and the screen says so.
4. Game Notes. Register one game from each group: a ROM game with a second (CHD) file, a game with a version (variant), a game whose guide row says an AMD, NVIDIA or Intel card works only with a fix, and a game the guide marks Broken. Open the Game Notes file. Pass: each game's steps match what the guide page says for that game, and the Broken game is named as broken.
5. Do the steps in the notes for two of those games. Pass: the game starts and the steps were enough.
6. BepInEx first start. Register a BepInEx game (for example Family Guy Bowling) and run BepInEx setup (menu 9). Pass: the result tells you to start the game and close it twice the first time, and the game then starts.
7. Write the result on issue 351: game, build, card, what the screen said, and whether the game started.

## Details

- The recipes are in `scripts\TpmRequiredPatchRecipes.json` (120 entries for 54 profiles). `docs\GAME-SUPPORT.md` counts them as Applied (54).
- Game Notes comes from `Get-GameSetupNotes` and `Get-TpmGuideGpuLines`. It shows text only. It applies nothing from the guide.
- The guide has an `is_unsupported` flag on 9 rows (the `SR3_3B` to `SR3_3G` track mods, `EFMM`, `batlgr37` and `wg3dhfe`). The Eggman index file marks the same entries "unsupported". They are extra archives that have no TeknoParrot profile of their own. TeknoParrot Manager now lists such a folder as "not in TeknoParrot" instead of a failed profile. Two of them name a linked profile in the guide (`batlgr37` names `batlgr3`, `wg3dhfe` names `wg3dh`); on the fake collection `wg3dhfe` registered with `wg3dh`.
- The live guide only uses the statuses Working and Broken. The code still handles Partial and Untested.
- Fake-file tests that cover this area: `Tests\Fix410.GuideFieldsInGameNotes.Tests.ps1` (3), `Tests\Fix412.GameSupportDecisions.Tests.ps1` (13) and `Tests\GameSupport.Tests.ps1` (9). All passed on this branch.
- Guide steps that TeknoParrot Manager tells you instead of doing, with the reason: deleting or replacing a game file from a note, Windows compatibility mode (Windows XP SP2), the movie codecs from the TeknoParrot Discord, and a 60 FPS limiter. Each needs a file or a Windows setting that the guide text does not pin to an exact, checkable file, so they stay in Game Notes. The steps TeknoParrot Manager does itself (exact-build fixes, graphics card choice, BepInEx, administrator and BepInEx needs from the profile) are listed above.
