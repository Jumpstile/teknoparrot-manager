# Game Startup Files

A few games will not start until the emulator they use has certain files. TeknoParrot Manager checks for these files and, if it finds them in your own game collection, copies them into place.

It never downloads or supplies these files. They must come from your own collection.

---

## What it checks

| Games | Missing item | What happens |
|---|---|---|
| PCSX2x6 games | PCSX2x6 firmware | Copied from your collection |
| Chihiro games | Four Chihiro firmware files | Copied from your collection |
| Arcade games on PlayStation 3 style hardware (RPCS3; for example the Tekken 6 arcade games) | Firmware file from your own collection | Installed from the firmware file in your collection. This is for those arcade games only. |
| Play! games | The game's own settings file | Copied from your collection |

Only emulators that are installed in your TeknoParrot folder are checked. The check only looks if the files exist.

---

## When you see it

- At the end of a normal run. In a preview or an unattended run it only tells you and copies nothing.
- In the Library health check (menu 14). If games are missing files and no saved path is broken, the menu offers **F** to fix them. See [[Health Check]].

The screen says which games will not start and what to do next.

---

## Fix it

1. Put the firmware in your own game collection: your Supplementary or main ZIP folder. For the arcade games on PlayStation 3 style hardware, that is the "[EMU] Sony PlayStation 3 Firmware" ZIP.
2. Run TeknoParrot Manager again, or choose **F** in the health check. If it cannot find the files and no working Supplementary folder is saved, it asks once for that folder (press Enter to skip). It saves the folder so it does not ask again. If the save fails, it tells you and may ask again next time.
3. Read the list under each game type: what it found and can install, what is already in place, what is missing (by file name, with the folder it goes in) and the folders it searched.
4. If it found and checked everything, answer **Y** once to install it. (**Y** is not offered when something is missing.) Answer **N** for not now. **D** shows details. **O** opens the folder.

The result names what was installed, what already matched, what is invalid (not the file the DAT list describes; the DAT list is a list of the right file names and fingerprints) and what was not finished.

TeknoParrot Manager checks every file against the Eggman DAT list first, and checks the result after. If it has no DAT list, it cannot check the files, so it copies none. Start it again and let it get the DAT list when it asks.

If a different file with the same name is already there, you are asked whether to replace it. Your file is copied to a backup first. The default is to keep yours.

---

## Saved game files for TeknoS11 arcade games (optional)

Arcade games that use the TeknoS11 loader (System 10, System 11, System 12, Sony ZN, Konami 573, Taito G-NET and similar boards) need no startup file to start. But without saved files, one of these games sets itself up from scratch, which can take hours. If you have your own saved-files set (the `[NVRAM] TeknoS11 preinstalled game files for System 11` ZIP, which covers all these boards), TeknoParrot Manager can copy the saved files for your games.

- You see `OPTIONAL: Saved game files for TeknoS11 arcade games` near the end of a normal run, only when a registered TeknoS11 arcade game has no saved files yet.
- If the ZIP is in your collection folders, it says it found the set and asks `Copy the saved files for these games? (Y/N, default Y)`. If not, it asks `Do you have the saved-files set? (Y/N, default N)`. Answer `Y`, then choose `F` for a folder or `Z` for a ZIP, and pick it.
- The files go to `TeknoS11\state\<game>\cabinet-1` in your TeknoParrot folder. It only adds files. A file that is already there is kept, never replaced.
- If your set has no saved files for some of your games, it names them. Those games start without them.
- It does not ask again when your set has nothing new for your games. It never downloads the set.

Library health check (menu 14) shows a `Saved files` note when some TeknoS11 arcade games have no saved files yet. See [[Health Check]].

<details>
<summary>Details</summary>

- The firmware for arcade games on PlayStation 3 style hardware is installed by RPCS3 itself, with no window. It takes about a minute. The firmware file can be up to 512 MB.
- The check for those arcade games looks for `liblv2.sprx` in the `dev_flash\sys\external` folder of RPCS3.
- The Play! check looks for a `.arcadedef` file named after each registered Play! game, in the `arcadedefs` folder of Play!. Only games whose own file is missing are named.
- If the install fails, open View Log from the main menu.
- Optional first-boot files for Capcom CPS3 games are a different step. See [[CPS3 First-Boot Files]].

</details>

Back to [[Home]].
