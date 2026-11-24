# Reset and Restore

Reset and Restore puts one game, or all your games, back the way they were at an earlier time. It works from restore points that TeknoParrot Manager saves when it starts.

Open it with **15** (Restore backup) in the main menu, then option **4**. The other restore options are on [[Restore Backup]].

---

## What a restore point has

- Your game settings (the profile files in `UserProfiles`).
- TeknoParrot Manager's own settings.

It does not have game files, saves, databases, or LaunchBox. A new restore point is made at start-up only when your settings changed. The first one is always kept.

---

## The menu

| Key | What it does |
|---|---|
| 1 | Reset one game (back to the first restore point) |
| 2 | Restore one game (you choose a restore point) |
| 3 | Reset all games (back to the first restore point) |
| 4 | Restore all games (you choose a restore point) |
| 5 | Remove older restore points |
| B | Back |

For one game, you pick it from a list. You see what will change. You must type **YES** to go on. Any other answer cancels and nothing changes.

For all games, you see counts first. Type **YES**, then type **ALL** to confirm.

Before anything changes, a new restore point of your current settings is saved and checked. So you can undo the undo here.

---

## Good to know

- The whole settings file of a game goes back. That includes the game path, controls, and every other setting. Changes you made since then are lost.
- Restore all can also put back TeknoParrot Manager's own settings. If it does, the program closes after. Start it again to load them.
- Games added after a restore point stay as they are when you restore one game. Restore all removes their settings files from `UserProfiles`, and the restore point made first keeps a copy.
- A damaged restore point is not offered.

<details>
<summary>Details</summary>

- Restore points live in `TeknoParrotManager\Backups\RestorePoints`.
- Option 5 keeps the first restore point and the newest 10. TeknoParrot Manager never removes restore points by itself. It shows what would go and asks you to type **YES**.
- Restore points made for another TeknoParrot folder are listed read-only. Press **D** in the menu to see them.

</details>

---

## Rebuild one game from its ZIP

This is option **5** in **15) Restore backup**. Use it when one game is broken and you do not know why. It puts the game folder back to exactly what is in the game's original ZIP.

- You need the game's ZIP in the ZIP folder you use for AutoSync. If the DAT list knows the game, the ZIP is checked against it too.
- You pick the game, read a short preview, and type **YES**. Any other answer cancels and nothing changes.
- The ZIP is unpacked and checked in a temporary folder on the same drive. Your current folder is then renamed and kept in `TPM-old-game-folders`, beside your games folder. Nothing is copied twice and nothing is deleted. Saves and your own settings that are not in the ZIP stay in the old folder.
- If anything goes wrong, your old folder is put back. The TeknoParrot settings for the game are not changed.
- If the ZIP is not found, there is not enough free space, the ZIP does not match the DAT list, or the game is running, it says so and changes nothing.
- In the same menu, **2** puts the old folder back (the rebuilt folder is kept instead) and **3** deletes an old folder after you type **YES**. Old folders use disk space until you delete them.

Back to [[Home]].
