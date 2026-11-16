# LaunchBox Integration

After AutoSync or Register only finishes, TeknoParrot Manager can add your games to LaunchBox. This step is optional. Skip it if you do not use LaunchBox.

---

## The four choices

| Key | What it does |
|---|---|
| P | Preview first. Shows what would change. Nothing is written. (Default) |
| A | Add missing games. A checked backup is made first. |
| F | Make an import file only. LaunchBox is not touched. |
| B | Skip this step. |

You can press **P** as many times as you like. What you answered there becomes the default for **A**.

---

## Add games (A)

1. Close LaunchBox and BigBox. TeknoParrot Manager never closes them for you.
2. Answer `Add the missing games to LaunchBox now? (Y/N, D = about the risks)`.
3. Give the LaunchBox folder if you are asked, and pick a platform: Arcade, TeknoParrot, both, or a custom name.
4. Read the plan. Then answer `Write exactly these changes after a verified backup? (Y/N)`.

Only missing games are added. Your own entries are kept.

---

## Import file (F)

TeknoParrot Manager saves `TeknoParrot-LaunchBox-Import.xml` in the `Reports` folder and prints the steps to import it. It never overwrites an older copy of that file. Games whose game file is missing are left out.

---

## Undo

Choose **14** (Restore backup) in the main menu, then option **3**, the LaunchBox library backup. See [[Restore Backup]].

<details>
<summary>Details</summary>

- Nothing is asked in a preview run or an unattended run.
- Before any write, a checked copy of each LaunchBox file it will change is saved. The copies go to `TeknoParrotManager\Backups\LaunchBoxBackups`. If TeknoParrot is inside the LaunchBox folder, they go to a folder under your Windows user's local app data instead, so they are never kept inside the library.
- Games with an unreadable profile or an invalid saved path are left out and named in Details (press **D**).
- Saves to several files are not one single step, so keep LaunchBox and BigBox closed until the result appears.

</details>

Back to [[Home]].
