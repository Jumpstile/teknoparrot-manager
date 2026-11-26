# dgVoodoo2

dgVoodoo2 (by Dege) helps a few old games that crash or show a black screen. These games use very old graphics systems (DirectX 8, DirectDraw or Glide). dgVoodoo2 translates them for a modern PC. It is main menu item 7, **dgVoodoo2 setup**.

**Use it only for games that crash, show a black screen or draw wrongly.** Games that already run fine do not need it.

---

## Quick steps

1. Start TeknoParrot Manager. At `Enter 1-18:` type `7` and press Enter.
2. If the dgVoodoo2 files are not on your PC yet, press `D` to download them (see below).
3. Setup scans your registered games and lists the ones that need dgVoodoo2.
4. At `Enter A, M, or Q`, press `A` to use the games it found, `M` to pick games yourself, or `Q` to cancel.
5. Wait for the result. Start the game and check it.

The result screen says how many games were checked and how many need dgVoodoo2, then `You selected N games: X set up now, Y already set up (nothing to change), Z skipped, W failed` (only the counts that apply) and where the backup is. This also happens when nothing needed changing. Press `D` to see every game you selected with its old graphics system, its result and the reason. The same list is in the log.

If no game needs dgVoodoo2, you see `No dgVoodoo2 setup is needed right now.` and nothing is changed. Press `D`, then `M`, if you still want to pick a game yourself.

---

## What goes into a game folder

Setup adds only the files a game folder is missing. Files that are already there are kept (except a `dgVoodoo.conf` when you pick a preset for that game; see below).

| What the game uses | Files added |
|---|---|
| DirectX 8 | `D3D8.dll` + `D3DImm.dll` |
| DirectDraw | `DDraw.dll` + `D3DImm.dll` |
| Glide 2x | `Glide2x.dll` |
| Glide 3x | `Glide3x.dll` |

For a game you pick yourself that shows no old graphics system, all the dgVoodoo2 DLLs are added.

If your dgVoodoo2 folder has a `dgVoodoo.conf`, a copy is added to each chosen game folder that has none. A `dgVoodoo.conf` that is already in a game folder is kept unless you pick a preset for that game.

<details>
<summary>Details: how detection works</summary>

Setup reads the first 2 MB of each game's program file and looks for the names `d3d8.dll`, `ddraw.dll`, `glide2x.dll` and `glide3x.dll`. Games whose saved path cannot be found are skipped and named. Fix their paths with [[Health Check]], then run setup again.

</details>

---

## Where the files come from

TeknoParrot Manager does not ship dgVoodoo2 in its ZIP. It looks for the files in:

- `<your TeknoParrot folder>\TeknoParrotManager\Assets\dgVoodoo2\`
- the `dgVoodoo2\` folder next to the script (used if you declined the tidy-up)

If none are found, you see `dgVoodoo2 DLL folder not found.` with three choices:

- `D` -- download from the official dgVoodoo2 GitHub release (recommended)
- `B` -- browse for a folder you already have
- `N` -- skip

The download is checked against the SHA-256 that GitHub lists for the file. Only the files setup needs are kept.

<details>
<summary>Details: using your own folder</summary>

The folder must hold at least one of `D3D8.dll`, `DDraw.dll`, `D3DImm.dll`, `Glide2x.dll`, `Glide3x.dll`. In the official ZIP, the first three are in `MS\x86\`, the Glide files are in `3Dfx\x86\`, and `dgVoodoo.conf` is at the top.

</details>

---

## Your own config for one game

To give one game its own `dgVoodoo.conf`, put a file named `ProfileCode.conf` in `<your TeknoParrot folder>\TeknoParrotManager\Assets\dgVoodoo2Presets\` (or a `dgVoodoo2Presets\` folder next to the script). Example: `VF5.conf`.

That file **replaces** the `dgVoodoo.conf` already in that game's folder. Setup warns you about this before you pick games. Other games are not affected.

A file whose name matches no registered game is reported as `WRONG NAME` and ignored, like the per-game presets in [[ReShade]]. Find a game's profile code in `TeknoParrot-Manager-controls.txt`.

---

## Removing dgVoodoo2

Delete the dgVoodoo2 DLLs and `dgVoodoo.conf` from that game's folder, but only the ones setup added. Setup leaves DLLs that were already there. If you had your own dgVoodoo2 files in a game before, keep those. Careful with `dgVoodoo.conf`: a per-game preset (see above) replaces the game's old `dgVoodoo.conf`, and TeknoParrot Manager keeps no copy of the old file after setup finishes. Deleting the preset does not bring the old file back, so keep your own copy of any `dgVoodoo.conf` you want before you run setup.

[[Health Check]] lists registered games that look like they need dgVoodoo2 and are not set up yet. It only reports and changes nothing.
