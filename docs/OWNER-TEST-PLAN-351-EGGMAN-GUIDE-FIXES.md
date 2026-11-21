# Owner test plan: Eggman guide fixes (issue 351)

## Where it stands

TeknoParrot Manager shows the guide's notes for your registered games in the Game Notes file. It applies the reviewed required fixes (menu 12) for the games it has recipes for. The rest of this issue is checking real games, which only the test PC can do.

A check of the current guide page against the program found nothing that needed a code change:

- The Game Notes step reads the live guide on Windows PowerShell 5.1 and PowerShell 7 with the same result.
- With every guide game registered, 1,425 of the 2,465 guide IDs have something to show (notes, setup steps, graphics card notes, a second file, a linked profile or a status).

The `docs\GAME-SUPPORT.md` totals come from an older copy of the guide (1,510 games and 832 versions). The live guide now has 1,607 games and 858 versions. Make that page again only after you decide which game list to pin. See the last item under Details.

## Test

You need the test PC and your own copies of the games.

1. Required fixes, exact builds. Register Family Guy Bowling, then choose **12) Required game patches**, then **A**. Pass: it lists the fix, **Y** installs it, **U** puts everything back, and the game starts after install.
2. Graphics card choice. Do step 1 with Shining Force Cross Elysion on a PC with an AMD card and again on one with an NVIDIA card. Pass: it asks which card you have when it cannot tell, installs only that card's file, and skips a file that is already right.
3. Wrong build. Point menu 12 at a build it does not list (for example another Family Guy Bowling version). Pass: nothing is changed and the screen says so.
4. Game Notes. Register one game from each group: a ROM game with a second (CHD) file, a game with a version (variant), a game whose guide row says an AMD, NVIDIA or Intel card works only with a fix, and a game the guide marks Broken. Open the Game Notes file. Pass: each game's steps match what the guide page says for that game, and the Broken game is named as broken.
5. Do the steps in the notes for two of those games. Pass: the game starts and the steps were enough.
6. Write the result on issue 351: game, build, card, what the screen said, and whether the game started.

## Details

- The recipes are in `scripts\TpmRequiredPatchRecipes.json` (120 entries for 54 profiles). `docs\GAME-SUPPORT.md` counts them as Applied (54).
- Game Notes comes from `Get-GameSetupNotes` and `Get-TpmGuideGpuLines`. It shows text only. It applies nothing from the guide.
- The guide now has an `is_unsupported` flag on 9 rows (for example `EFMM` and the `SR3_3B` to `SR3_3G` track mods). TeknoParrot Manager does not read it. It was left alone because its meaning is not written down in the guide, so please tell us what it should say to the player.
- The live guide only uses the statuses Working and Broken. The code still handles Partial and Untested.
- Fake-file tests that cover this area: `Tests\Fix410.GuideFieldsInGameNotes.Tests.ps1` (3), `Tests\Fix412.GameSupportDecisions.Tests.ps1` (13) and `Tests\GameSupport.Tests.ps1` (9). All passed on this branch.
- Not done here, because it needs your decision: make `docs\GAME-SUPPORT.md` again from the live guide and a pinned TeknoParrot profile list, and decide the 1,470 Gap rows (games with no TeknoParrot profile, mostly ROM games).
