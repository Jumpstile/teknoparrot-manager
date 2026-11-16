# Game Startup Files

A few games will not start until the emulator they use has certain files. TeknoParrot Manager checks for these files and, if it finds them in your own game collection, copies them into place.

It never downloads or supplies these files. They must come from your own collection.

---

## What it checks

| Games | Missing item | What happens |
|---|---|---|
| PCSX2x6 games | PCSX2x6 firmware | Copied from your collection |
| Chihiro games | Four Chihiro firmware files | Copied from your collection |
| PlayStation 3 games (RPCS3) | PlayStation 3 firmware | Installed from the firmware file in your collection |
| Play! games | The game's own settings file | Copied from your collection |

Only emulators that are installed in your TeknoParrot folder are checked. The check only looks if the files exist.

---

## When you see it

- At the end of a normal run. In a preview or an unattended run it only tells you and copies nothing.
- In the Library health check (menu 13). If games are missing files, the menu offers **F** to fix them. See [[Health Check]].

The screen says which games will not start and what to do next.

---

## Fix it

1. Put the firmware in your own game collection: your Supplementary or main ZIP folder. For PlayStation 3, that is the "[EMU] Sony PlayStation 3 Firmware" ZIP.
2. Run TeknoParrot Manager again, or choose **F** in the health check.
3. Answer **Y** to copy or install. Answer **N** for not now. **D** shows details. **O** opens the folder.

TeknoParrot Manager checks every file against the Eggman DAT list first, and checks the result after. If it has no DAT list, it cannot check the files, so it copies none. Start it again and let it get the DAT list when it asks.

If a different file with the same name is already there, you are asked whether to replace it. Your file is copied to a backup first. The default is to keep yours.

<details>
<summary>Details</summary>

- PlayStation 3 firmware is installed by RPCS3 itself, with no window. It takes about a minute. The firmware file can be up to 512 MB.
- The PlayStation 3 check looks for `liblv2.sprx` in the `dev_flash\sys\external` folder of RPCS3.
- The Play! check looks for a `.arcadedef` file named after each registered Play! game, in the `arcadedefs` folder of Play!. Only games whose own file is missing are named.
- If the install fails, open View Log from the main menu.
- Optional first-boot files for Capcom CPS3 games are a different step. See [[CPS3 First-Boot Files]].

</details>

Back to [[Home]].
