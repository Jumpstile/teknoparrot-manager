# ReShade

ReShade adds visual filters on top of a game: CRT-style scanlines, a soft glow, deeper blacks and brighter whites. It is optional. Your games run fine without it. It is main menu item 6, **ReShade setup**.

ReShade works with **both 32-bit and 64-bit games**. Games that run through BudgieLoader (a Linux-style game format) are skipped for now, and nothing in their folder changes. A 32-bit game also needs `ReShade32.dll` next to `ReShade64.dll`, or it is skipped.

---

## Quick steps

1. Start TeknoParrot Manager. At `Enter 1-18:` type `6` and press Enter.
2. Press `S` (or just Enter) to set up ReShade.
3. Pick a look by typing its number at `Choice`. A preview window may open. It only shows an approximation of the look, not the real filter.
4. Type `U` to use the look you picked. You go straight on to choosing games. Nothing changes until you confirm the games.
5. Choose your games: `A` for all registered games, or `L` to pick from a list (type numbers, then `D` when you are done).
6. If you picked more than one game, press `Y` (or Enter) at `Apply ... ?`
7. Start a game. Press the **Home** key to open the ReShade overlay, then tick or untick the effects you want. Home is ReShade's own key; if a game uses Home for something else, change `KeyOverlay=` in the game's `ReShade.ini`.

After you pick a number, you see a short `Selected:` line, not the whole list. Other keys at the `Choice` prompt: `L` shows the full list again, `S` uses your own preset file, `N` skips ReShade, `B` cancels, `R` reopens the preview window, `D` shows details about each look.

The first screen at menu 6 has four choices: `S` set up ReShade, `R` remove the files TeknoParrot Manager made, `U` undo ReShade changes, and `B` use my bezel folder (see "Use my bezel folder" below).

If ReShade is not on your PC yet, TeknoParrot Manager asks first. Press `D` there to download it from reshade.me. See "Where the files come from" below.

---

## The looks

There are 17 looks: **Original** (no change), 11 CRT looks and 5 other looks. Each one has a short description and a rough cost (light, medium or heavy). The cost is an estimate, not a measurement.

<details>
<summary>Details: the full list</summary>

CRT looks:

- Curved Arcade Monitor [CRT-Geom], medium
- Classic Arcade CRT [CRT Lottes], heavy
- Sharp Aperture Grille [CRT-Aperture], medium
- Balanced Flat CRT [CRT-Easymode], medium
- Sharp Phosphor CRT [CRT-Hyllian], medium
- Arcade CRT Glow [CRT Lottes + ArcaneBloom], heavy
- Detailed Arcade CRT [CRT-Royale], heavy
- Fast CRT [CRT-ZFast], light
- Lightweight CRT [CRT-Pi], light
- Scanline Glow [CRT-Pi + ArcaneBloom], medium
- Bright Scanlines [Levels + CRT-Pi], light

Other looks:

- Arcade Glow [ArcaneBloom], medium
- Crisp 3D [SMAA + Curves + Levels], medium
- Crisp 3D Glow [SMAA + Levels + ArcaneBloom], medium
- Balanced Contrast [Curves], medium
- Black/White Point Adjustment [Levels], light

The preview shows approximations drawn from one sample picture. It does not run your game or the real filter. The edge smoothing (SMAA) part of the Crisp 3D looks cannot show on a still picture.

A look you saved earlier that is no longer in the list is reported as retired. TeknoParrot Manager never swaps it for another look and leaves its installed files alone.

</details>

---

## Where the files come from

TeknoParrot Manager does not ship ReShade in its ZIP. It needs `ReShade64.dll`, and `ReShade32.dll` next to it for 32-bit games. The file is looked for in:

- `<your TeknoParrot folder>\TeknoParrotManager\Assets\ReShade\`
- the `ReShade\` folder next to the script (used if you declined the tidy-up)

If the file is not found, you see `ReShade 64-bit DLL not found.` with three choices:

- `D` -- download it automatically from reshade.me (recommended)
- `B` -- browse for a file you already have
- `N` -- skip

The automatic download is checked before use: the installer must carry the trusted ReShade signature, or it is refused. A file you supply yourself is checked the same way. When a newer ReShade is out, setup offers to update it (`Y` or `N`).

<details>
<summary>Details: what goes into a game folder</summary>

- One DLL, named for the graphics system the game uses: `d3d9.dll` (DirectX 9), `dxgi.dll` (DirectX 10 and 11, also used when it cannot tell), `d3d12.dll` (DirectX 12) or `opengl32.dll` (OpenGL games; BudgieLoader games are skipped).
- OpenParrot games get the DLL in their `openparrot\` subfolder.
- A `ReShade.ini` with your look, plus the shader files it needs.
- That `ReShade.ini` marks ReShade's first-run tutorial as done and turns the clock, FPS, frame time and message overlays off. So no welcome window or counters appear when a game starts. The key that opens ReShade is not changed.
- If you already use ReShade in a game, setup leaves it alone (see "Games that were left alone").

</details>

---

## Your own preset for one game

To give one game its own ReShade preset, put a file named `ProfileCode.ini` in `<your TeknoParrot folder>\TeknoParrotManager\Assets\ReShadePresets\` (or a `ReShadePresets\` folder next to the script). Example: `Daytona3.ini`. That file wins for that game only. Find a game's profile code in `TeknoParrot-Manager-controls.txt`.

A file whose name matches no registered game is reported as `WRONG NAME` and ignored. This is the same rule as [[Register]]'s CustomThumbnails.

---

## TeknoParrot's own CRT look

Some games already use TeknoParrot's own CRT look. Stacked with a ReShade CRT look, the picture can look doubled. When this applies, you are asked once, after you pick your look and your games:

- `K` -- keep TeknoParrot's CRT look (the default)
- `T` -- turn it off for the games that get ReShade now. A saved copy of your game profiles is made first.
- `D` -- details

Removing ReShade later does not turn TeknoParrot's CRT look back on. To put it back, use **Undo ReShade changes** (below) or [[Restore Backup]].

---

## Games that were left alone

After setup, the result screen says what changed and what was left alone. A game is left alone, for example, when:

- it is a 32-bit game and `ReShade32.dll` is not next to `ReShade64.dll`, or its type cannot be read
- it already has a ReShade that TeknoParrot Manager did not install
- its game file cannot be found (check its drive is connected, then run [[Health Check]])

Before it installs anything, ReShade tells you how many of the games you picked it can change now (for example `You selected 4 games. 3 can be changed now.`) and that it leaves the others alone. After a setup for many games, the result is a short summary (selected, set up, failed, skipped) with the skipped games grouped by reason, and no failure warning when every game that could be set up was set up. Press `D` on the result screen to see the game lists and why for each game. If a game only has a leftover ReShade.ini or older ReShade files, press `A` to replace them. You are asked to confirm, and a copy of the old files is saved first so you can undo it.

---

## Use my bezel folder (B)

A bezel is a picture that frames the game on a wide screen, like the edge of an arcade cabinet. TeknoParrot Manager does not come with bezels and never downloads them. This step only uses `.png` bezel pictures you already have in a folder. A game needs ReShade first. A game without it is listed as `set up ReShade for this game first` and left alone.

1. At `Action (S/R/U/B, default S)`, type `B`. You see `F) Pick bezels from my folder`, `U) Undo bezels I applied` and `X) Back`.
2. Press Enter for `F`, then type or browse to your bezel folder.
3. You see `Bezel preview. Nothing has been changed yet.` Each game shows the bezel it would get and how sure the match is: High, Medium or Low. A Low match, or a bezel with a different sequel number (a "4" picture for a "3" game), says `needs your choice` and is not applied unless you pick it. Games with no bezel in your folder are counted, not guessed.
4. Type a game's number to pick a different bezel (or no bezel) for it. Your pick is remembered. Type `D` for details, `C` to cancel, or `A` to apply.

The bezel is copied to the game's `reshade-shaders\Textures` folder as `bezel.png` and checked. A bezel you put there yourself is kept unless you say yes to replacing it, and a copy of yours is saved first. A game that shares its folder with other games is skipped, because one bezel would show on all of them.

To undo, type `6`, `B`, then `U`. Each bezel TeknoParrot Manager copied is removed, and the bezel you had before is put back. A file you changed since is left alone.

TeknoParrot Manager puts the file where ReShade looks for it. It is not confirmed that every game shows it. Games in exclusive fullscreen, or that start through a loader, may not.

---

## Change, undo or remove

All of these start at menu 6.

- **Change the look:** press `S` again, pick another look and games.
- **Undo:** press `U` at the first screen. You see the games TeknoParrot Manager changed, newest first. Type a game's number, then `YES` to undo that game. Press `A`, then type `ALL`, to undo every game. Undo puts files back only while they are exactly as TeknoParrot Manager left them. If a game was changed after that, it is left as it is.
- **Remove:** press `R` at the first screen and pick the games. You see a preview of what will be removed (`REMOVE`) and what is kept (`KEEP`). Type `REMOVE` to confirm; a backup is made first. Only files TeknoParrot Manager made are removed. A ReShade you installed yourself stays.

[[Health Check]] shows how many registered games have ReShade installed. It does not treat that as a problem.

---

## Credit

ReShade is made by crosire. Home page: [reshade.me](https://reshade.me).
