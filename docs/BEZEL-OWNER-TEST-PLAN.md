# Bezel folder: owner test plan (issue 429)

The "Use my bezel folder" step is built and tested with fake games and fake pictures.
Two things cannot be proven without your real files and screen. This plan covers them.
Do these on the test PC with a copy of a few games, not your main library.

What is already proven by the automatic tests: names are matched, a different sequel is never picked quietly, a bezel you placed yourself is kept, a game without ReShade or in a shared folder is left alone, nothing is written before you approve, and Undo puts your own file back.

## Test 1: does a game actually show the bezel?

This is the open question in the issue. TeknoParrot Manager puts the picture at `<game folder>\reshade-shaders\Textures\bezel.png`. Whether a game shows it depends on ReShade and on the effect that is turned on.

1. Pick one game you can run now (a plain one that starts from its own `.exe`, not from a shared loader). Set up ReShade for it first (main menu 5, then S).
2. Put one bezel picture for that game in an empty folder, for example `C:\TestBezels` (a real `.png`).
3. Main menu 5, then B, then Enter. Point it at `C:\TestBezels`.
4. Read the preview. Check the game name and the bezel name are the ones you expect. Press `A`.
5. You should see `Done. 1 bezel copied and checked.`
6. Start the game. Press Home to open the ReShade overlay. Turn on the effect that draws a border or overlay (for example Border).
7. Write down: does the bezel show, and is it the right picture? Is the shape right for your screen (wide or 4:3)?

Write the answer in the issue: which game, which graphics type, shown or not shown, and what you had to turn on.
If it does not show, the file placement is right but the effect or the file name is not. That is the thing to learn, and the step needs a change before release.

## Test 2: does it work for the other graphics types?

Repeat Test 1 with one game each for: Direct3D 9, Direct3D 11, OpenGL. Also try one game that starts through a loader program and one that runs in exclusive fullscreen. The issue says these may not show ReShade overlays at all.

Write down which ones show the bezel. If some never do, the on-screen text should say so before the user applies (tell us which).

## Test 3: how good is the matching on your real bezel folder?

The issue asks for the matcher to be measured on your real folder before it is trusted. Use a copy of the folder, not the original.

1. Main menu 5, then B, then Enter. Point it at your bezel folder.
2. Read the preview. Do not press `A`. Press Enter (cancel).
3. Count the rows: how many say High, how many Medium, how many Low or "needs your choice", and how many games have no bezel.
4. For each High and Medium row, check by eye whether the bezel is the right game. Write down any wrong ones with the file name and the game name.
5. Look at the "needs your choice" rows. Is the right bezel in the best guess or in "Also close"?

Report: number right, number wrong, number missed. If more than about one in twenty High or Medium rows is wrong, the High cut-off (85 percent match) needs raising before release. The cut-offs are in `New-TpmBezelPlanRows`.

## Test 4: safety checks

1. Put your own `bezel.png` by hand in a test game's `reshade-shaders\Textures` folder. Run the bezel step. The game should say `has a bezel you placed`. Press `A` and answer `N` to the replace question. Your file must be unchanged.
2. Run it again and answer `Y`. Your file is replaced. Then main menu 5, B, U, answer `Y`. Your original file must be back, byte for byte.
3. Apply a bezel, then edit `bezel.png` yourself (paste a different picture over it). Run Undo. It should say the game was left alone, and your new picture must still be there.
4. Try a game that shares its folder with other games (a game started by the shared loader). It must say it shares its folder and be skipped.
5. Cancel at the preview (press Enter) for any run. Check no `bezel.png` was written.

## Decisions made while building (change any you disagree with)

- The bezel is only copied for games that already have ReShade set up by TeknoParrot Manager. Otherwise it would sit there and nothing would use it.
- Only `.png` pictures are used, because the file is saved as `bezel.png`.
- A game whose folder is shared with other games is skipped. One bezel there would show on every game that uses the folder.
- A High match is 85 percent or more and clearly ahead of the next one. Medium is 72 percent or more. Anything lower, or a different sequel number, is Low and is not applied unless you pick it.
- The Eggman list is not used. The issue says a community bezel list could be added later as one more source.
- Undo is one list for all bezels TeknoParrot Manager copied, not one game at a time.
