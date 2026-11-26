# Required Game Patches (menu 13)

Some game versions need a small fix before they run right. It can be one changed file or a plugin. Menu 13 finds the fixes for the exact versions you have and installs them.

TeknoParrot Manager never downloads these fixes. They come from your own game ZIPs: the Main or Supplementary folder you set up for AutoSync.

---

## Use it

1. Close the game first. TeknoParrot Manager stops if it is running.
2. Choose **13** in the main menu.
3. Pick one:

| Key | What it does |
|---|---|
| A | Install patches for my registered games |
| M | Install patches for one game I pick (you choose the game, then its folder) |
| U | Undo patches that TeknoParrot Manager installed |
| Q | Go back |

4. TeknoParrot Manager shows what it will install and asks you to press **Y**. Press **D** for details. Press Enter to cancel.
5. Start the game in TeknoParrotUI and test it. A checked patch is not proof that the game plays well.

---

## What to expect

- It only patches a game when the version matches exactly. A game that has no patch in the list is left alone.
- You are asked only for the ZIP folder of the version you have. TeknoParrot Manager reads just the named file inside the ZIP. It does not unpack the whole ZIP.
- TeknoParrot Manager never downloads a patch file. A few patches also accept the game's own ZIP (for example the APM3 `apm.dll` for Dead or Alive 6, Otoshu DX and Rolling Gunner). The screen names every file that would work. Other separate patch ZIPs, such as the Guilty Gear APM3 files, are a separate download that TeknoParrot Manager does not provide.
- A copy of the original files is saved first, so Undo can put them back. Undo only works for patches TeknoParrot Manager installed.
- If your PC has two real graphics cards, you are asked once which one the game uses. Press Enter if you are not sure. Fixes made for one make of card are then skipped.

<details>
<summary>Details</summary>

- Patch files can be up to 512 MB. They can come from a ZIP, or from a 7z or RAR file when 7-Zip is installed. Long folder paths work. Free space is checked first.
- AMD and NVIDIA fixes work even when Windows shows an extra display adapter.
- Some patches need BepInEx installed first. If so, the result tells you. See [[BepInEx]].
- A game that is installed but not registered is not found by **A**. Use **M**, or register it first with [[Register]].
- Results list each game and say why a game was skipped. The log has the full details.

</details>

Back to [[Home]].
