# Crosshairs

Crosshair setup puts the crosshair pictures you choose into your lightgun games. It is main menu item 4, **Crosshair setup**. 321 designs come with TeknoParrot Manager, in the `Crosshairs\` folder next to the script.

---

## Quick steps

1. Start TeknoParrot Manager. At `Enter 1-17:` type `4` and press Enter.
2. A preview window opens with all the designs. Click one for **Player 1**, then one for **Player 2**. They can be the same design.
3. The window closes. In the console you see `P1: ... P2: ...`. At `Apply these crosshairs? (Y/N, default Y)` press Enter to apply.
4. You are asked `Also hide the Windows cursor for all lightgun games? (Y/N)`. Answer `Y` if you see two cursors in a game. Your profiles are backed up first.
5. Start a lightgun game to try it.

If the preview window cannot open, or you close it (press Esc, use the button at the bottom, or wait 45 seconds), you type the design numbers in the console instead. Nothing is copied until you confirm. TeknoParrot Manager remembers your last choice, so next time you can press Enter to reuse it.

To change your crosshairs later, run menu 4 again. Old pictures are replaced.

---

## Which games get crosshairs

Every registered game that is marked as a lightgun game in its TeknoParrot profile (`GunGame` set to true). Other games are not touched.

A game that cannot get crosshairs is named with the reason, and the rest are still done. A skipped game does not make the whole setup count as failed.

| Game type | Where the pictures go |
|---|---|
| Most games | `P1.png` and `P2.png` in the folder with the game's `.exe` |
| ElfLdr2 games | One shared pair in the ElfLdr2 loader folder (inside your TeknoParrot folder) |
| PCSX2 (pcsx2x6) games | One shared pair in the PCSX2 emulator's `crosshairs` folder |

<details>
<summary>Details: PCSX2 games</summary>

If PCSX2 is installed but has not been set up for TeknoParrot yet, TeknoParrot Manager asks once whether it may start PCSX2 so it sets itself up. Then it adds the crosshair files and checks the result. If PCSX2 is still open, close it first, or its crosshairs are skipped while the other games are still done.

TeknoParrot Manager never writes PCSX2's own cursor settings (`cursor_path` in `PCSX2.ini`). PCSX2 manages them itself.

</details>

---

## Adding your own crosshairs

Drop any PNG picture into the `Crosshairs\` folder. It shows up in the preview next time. The name does not matter, but numbered names are easier to tell apart. A file that is not a real PNG is listed and skipped.

The included designs (`000.png` to `320.png`) come from the emuline.org custom crosshairs collection.

---

## Cursor hiding and undo

The cursor-hide answer sets the game's own cursor field (`HideCursor`, `Hide Cursor` or `DisableCursor`, depending on the game) to on. Games with no such field are skipped. To undo it, use [[Restore Backup]].
