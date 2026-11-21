# LaunchBox Integration

After AutoSync or Register only finishes, TeknoParrot Manager can add your games to LaunchBox. This step is optional. Skip it if you do not use LaunchBox.

---

## The choices

| Key | What it does |
|---|---|
| P | Preview first. Shows what would change. Nothing is written. (Default) |
| A | Add missing games. A checked backup is made first. |
| G | Fill in game details and make playlists (backed up). |
| L | Link games for art and details (backed up). |
| F | Make an import file only. LaunchBox is not touched. |
| B | Skip this step. |

You can press **P** as many times as you like. What you answered there becomes the default for **A**.

---

## Add games (A)

1. Close LaunchBox and BigBox. TeknoParrot Manager never closes them for you.
2. Give the LaunchBox folder if you are asked, and pick a platform: Arcade, TeknoParrot, both, or a custom name.
3. Read the plan. Then answer `Write exactly these changes after a verified backup? (Y/N, D = about the risks)`. This is the only approval.

Only missing games are added. Your own entries are kept.

---

## Fill in details and make playlists (G)

G fills in the release year and developer where LaunchBox has nothing yet. It makes playlists for each arcade hardware family, plus "Light gun games" and "Driving games". Your own playlists and details are never touched. It shows what it would change first and asks before it saves. Restore puts everything back.

---

## Link games for art and details (L)

L looks each game up in LaunchBox's own game list on your PC and uses the official name and the Games Database ID, so LaunchBox can find info and artwork. It shows every old name, new name and ID first, and you approve before anything is saved. Names you typed yourself are never replaced. Nothing is downloaded.

---

## Logos and box art from a folder

After the choices above (unless you chose B), you see `Optional: add logos or box art to LaunchBox from a folder you pick.`

| Key | What it does |
|---|---|
| I | Add pictures from a folder. You see a preview first. |
| U | Undo the last picture import. |
| S | Skip this step. (Default) |

After I, pick the folder, then the picture type (`1 Clear logos, 2 Box front`) and the platform. A close match is used only if you say yes. Pictures LaunchBox already has stay unless you choose to replace them. Nothing is downloaded.

---

## Lighting for arcade buttons (LEDBlinky)

If you use LEDBlinky, a full run (not "New game only") ends with `Optional: lighting for your arcade buttons.` The Manager looks for LEDBlinky on your drives and in Program Files, or asks where it is and remembers the folder.

| Key | What it does |
|---|---|
| P | Preview first. No changes. (Default) |
| A | Add lighting info to LEDBlinky (backed up, can be undone). |
| U | Undo the last add. |
| C | Use a different LEDBlinky folder. |
| O | Switch between the usual arcade colors and your own colors. |
| B | Skip this step. |

A game gets only the controls it uses that your cabinet has. Only entries the Manager added are ever removed.

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
