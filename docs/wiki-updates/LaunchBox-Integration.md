# LaunchBox Integration

After AutoSync or Register only finishes, TeknoParrot Manager can add your games to LaunchBox. This step is optional. Skip it if you do not use LaunchBox.

You can also open it any time from main menu item **3** (LaunchBox integration). You do not need to register or unzip any games first. If you have no LaunchBox yet, it tells you so and how to continue. It still appears after AutoSync and Register only too.

---

## The choices

| Key | What it does |
|---|---|
| P | Preview first. Shows what would change. Nothing is written. (Default) |
| A | Add missing games. A checked backup is made first. |
| G | Fill in game details and make playlists (backed up). |
| V | Group regions and versions of a game into one game with a version picker (backed up). |
| S | Keep LaunchBox in step with TeknoParrot (backed up). |
| L | Link games for art and details (backed up). |
| C | Fill in players and controllers for Big Box (backed up). |
| F | Make an import file only. LaunchBox is not touched. |
| B | Skip this step. |

You can press **P** as many times as you like. What you answered there becomes the default for **A**.

---

## Add games (A)

1. Close LaunchBox and BigBox. TeknoParrot Manager never closes them for you.
2. Give the LaunchBox folder if you are asked, and pick a platform: Arcade, TeknoParrot, both, or a custom name.
3. Read the plan. Then answer `Write exactly these changes after a verified backup? (Y/N, D = about the risks)`. This is the only approval.

Only missing games are added. Your own entries are kept. A game you add gets its real game name (for example "Too Spicy", not "2Spicy"), and its release year and developer when LaunchBox's own game list or the Eggman list knows them. Firmware updaters, drive checkers and test boards are never added.

**How games are matched.** One matching method is used for every LaunchBox choice. A game is linked by itself only when TeknoParrot, the Eggman list and LaunchBox's own game list agree. A different year or number is a different game. Region, version and board tags are ignored. When it is not sure, you pick from the possible games, or press Enter to skip.

---

## Fill in details and make playlists (G)

G fills in the release year and developer where LaunchBox has nothing yet. It makes playlists for each arcade hardware family, plus "Light gun games" and "Driving games". Your own playlists and details are never touched. It shows what it would change first and asks before it saves. Restore puts everything back.

A game that cannot start yet (its game file, firmware or BepInEx is missing) gets a plain `Needs setup` note and goes into a `Needs setup` playlist. Both go away by themselves when the problem is fixed. Notes you wrote yourself stay.

---

## Group regions and versions (V)

V turns the regions and versions of one game into a single LaunchBox game with a version picker. Only games that are certainly the same game are grouped. The default version follows the country you chose in [[Region Setup]]. It shows what it would change first, makes a backup, and asks before it saves. Restore puts everything back.

---

## Keep LaunchBox in step (S)

S makes LaunchBox match TeknoParrot. Games you removed from TeknoParrot are removed from LaunchBox. Moved games get their new location. Old TeknoParrot Manager names become the clean title. A game whose game file is only missing (for example an unplugged drive) is never removed. Names you typed yourself, and games that have a Games Database ID, are never renamed. If most games have no profile, nothing changes. It shows what it would change first, makes a backup, and asks before it saves. Restore puts everything back.

---

## Link games for art and details (L)

L looks each game up in LaunchBox's own game list on your PC and uses the official name and the Games Database ID, so LaunchBox can find info and artwork. It shows every old name, new name and ID first, and you approve before anything is saved. Names you typed yourself are never replaced. Nothing is downloaded.

---

## Fill in players and controllers (C)

C fills in how many players each TeknoParrot game has and which controller it needs, so Big Box can show them. The answers come from each game's TeknoParrot controls. It fills empty boxes only: a player count, play mode or controller that you or LaunchBox already have is never changed, and a game that already lists controllers keeps them. When the controls do not show a clear controller (for example a flight stick), none is added. It shows every game and what it would get first (press D), makes a checked backup, and asks before it saves. Right after saving it asks if you want to undo at once; Restore also puts everything back. Lights are not touched.

---

## Logos and box art from a folder

After the choices above (unless you chose B), you see `Optional: add logos or box art to LaunchBox from a folder you pick.`

| Key | What it does |
|---|---|
| I | Add pictures from a folder. You see a preview first. |
| U | Undo the last picture import. |
| S | Skip this step. (Default) |

After I, pick the folder, then the picture type (`1 Clear logos, 2 Box front`) and the platform. When LaunchBox's game list is on your PC, a picture is matched to the game itself: another name of the same game is a sure match, and a picture of a different game with the same name is never used. Close names still need your yes. Pictures LaunchBox already has stay unless you choose to replace them. Nothing is downloaded.

---

## Lighting for arcade buttons (LEDBlinky)

If you use LEDBlinky, a full run (not "New game only") ends with `Optional: lighting for your arcade buttons.` TPM looks for LEDBlinky on your drives and in Program Files, or asks where it is and remembers the folder.

| Key | What it does |
|---|---|
| P | Preview first. No changes. (Default) |
| A | Add lighting info to LEDBlinky (backed up, can be undone). |
| U | Undo the last add. |
| C | Use a different LEDBlinky folder. |
| O | Switch between the usual arcade colors and your own colors. |
| B | Skip this step. |

A game gets only the controls it uses that your cabinet has. Only entries TPM added are ever removed.

---

## Import file (F)

TeknoParrot Manager saves `TeknoParrot-LaunchBox-Import.xml` in the `Reports` folder and prints the steps to import it. It never overwrites an older copy of that file. Games whose game file is missing are left out.

---

## Undo

Choose **15** (Restore backup) in the main menu, then option **3**, the LaunchBox library backup. See [[Restore Backup]].

<details>
<summary>Details</summary>

- Nothing is asked in a preview run or an unattended run.
- Before any write, a checked copy of each LaunchBox file it will change is saved. The copies go to `TeknoParrotManager\Backups\LaunchBoxBackups`. If TeknoParrot is inside the LaunchBox folder, they go to a folder under your Windows user's local app data instead, so they are never kept inside the library.
- The platform TeknoParrot Manager makes is called TeknoParrot and is set to be scraped as Arcade. This is checked, and nothing is renamed.
- Games with an unreadable profile or an invalid saved path are left out and named in Details (press **D**).
- Saves to several files are not one single step, so keep LaunchBox and BigBox closed until the result appears.

</details>

Back to [[Home]].
