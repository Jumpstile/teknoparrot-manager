# BepInEx

[BepInEx](https://docs.bepinex.dev) is an add-on framework that some games need before a community plugin can work (for example for controls or fixes). It is not part of TeknoParrot. Most games do not need it. It is main menu item 9, **BepInEx setup**.

TeknoParrot Manager installs or updates BepInEx only after you approve. It has no remove option.

---

## Quick steps

1. Start TeknoParrot Manager. At `Enter 1-17:` type `9` and press Enter.
2. The screen shows a few known examples of games that need BepInEx. The list comes from the TeknoParrot compatibility data (eggmansworld.github.io), so it stays current. Check the screen for the latest list.
3. If some games have no BepInEx, you see `{n} game(s) do not have BepInEx. Only a few games need it, so they are left alone unless you pick them.` Pick a game from the list only if that game needs it. Press `B` when you are done picking.
4. You see the games that need an install or update, one per line, like `Game Name: Not installed -> <version> (x64)`.
5. At `[Y] Install/update  [B] Back  [N] Cancel`, press `Y` to go ahead. `B` (the default) goes back and `N` cancels. Nothing is changed until you press `Y`. If the only games on the list are ones you picked by number from the "do not have BepInEx" list, this question is skipped, because picking them was your answer.
6. Wait for the result. After a normal finish, press Enter to go back to the menu.

---

## What it does

- It picks the matching **stable** BepInEx for each game: the 64-bit package for a 64-bit game, the 32-bit package for a 32-bit game. It never uses a beta or pre-release. A game whose type cannot be read is left alone.
- A game with a damaged or incomplete BepInEx shows as `Broken (...)`. Pressing `Y` installs the stable package over it, with the same backup and rollback.
- A healthy BepInEx is updated only if a newer stable release is out. Up to date games are left alone.
- There is no repair-reset and no removal choice.
- If a game's folder is outside your games folder, or contains a link (junction or symlink), that game is skipped before anything is downloaded or written. The screen tells you what to fix. Then run menu 9 again.

If something goes wrong, the failure screen offers `R` to try again, `D` for details and `B` to go back. If it says the rollback could not be verified, do not retry. Keep the files it names and have the game folder checked first.

<details>
<summary>Details: backup and rollback</summary>

Before it changes a game, TeknoParrot Manager copies that game's `BepInEx` folder, `doorstop_config.ini`, `winhttp.dll`, `.doorstop_version` and `changelog.txt` into a folder named `BepInEx_Backup_<id>` inside the game folder, and checks the copy. After the update is checked, the backup folder is removed. It stays only if the update failed or the cleanup could not finish.

If the update fails, TeknoParrot Manager puts back only what it changed itself. Anything it cannot prove it made (for example a file you edited meanwhile) is left as it is.

</details>

---

## Troubleshooting and manual removal

The official guide: https://docs.bepinex.dev/articles/user_guide/troubleshooting.html

If you remove BepInEx by hand, first copy the game's `BepInEx` folder somewhere safe, because it holds your plugins and settings. Then delete `doorstop_config.ini`, `winhttp.dll`, `.doorstop_version`, `changelog.txt` and the `BepInEx` folder from the game's folder.

[[Health Check]] shows how many registered games have BepInEx installed.
