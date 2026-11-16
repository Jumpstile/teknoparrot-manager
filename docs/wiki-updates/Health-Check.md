# Library Health Check (menu 13)

The health check looks over your registered games and tells you what needs attention. The check itself only reads. It does not change a file. You see `TeknoParrot Manager checked your setup and did not change anything.`

When it ends, it offers follow-up actions (repair a path, set up PostgreSQL, and so on). Those are separate steps. Each one tells you what it will do and asks before it changes anything.

---

## How to run it

1. Start TeknoParrot Manager and type `13` at the main menu.
2. Read the list of results.
3. Choose a follow-up action, press `D` for details, or press `B` to go back.

---

## What you see

One line per area. Each line starts with `OK`, `Needs attention`, `Not checked` or `Could not check`.

| Area | What it checks |
|---|---|
| Game paths | Whether each registered game's saved path points to a file that exists. |
| Profile files | Whether each game profile can be read. A damaged profile is named as `could not be read`. |
| Game drive | Whether games are on a drive that is not connected. If so, reconnect the drive. Or choose R or S to point those games at a new folder. |
| [[GPU Fix]] | Games that have a GPU fix setting that does not match your graphics card. |
| Force feedback | Games with a built-in FFB Blaster setting that is not turned on. The separate plugin is not looked at here. Use [[FFB Setup]] for that. |
| [[dgVoodoo2]] | Games that need dgVoodoo2 but do not have it yet. |
| [[Postgres Setup]] | Whether PostgreSQL is installed and running, whether games still need setup, and whether each game database is there and opens. A database that is not ready shows as `Problem - <game>`. |
| Game startup files | Games whose emulator is missing files it needs to start. See below. |

The last lines give the verdict: `Everything looks fine.` or `Some things need attention.` If a check could not finish, you see `Some checks could not finish, so this is not an all-clear.` A game in a very long folder path counts as not fully checked.

The follow-up menu also shows how many games already have [[ReShade]] and [[BepInEx]]. These are only counts. Neither is something you must fix.

Press `D` at any time to see every detail. The details are also saved in the log.

---

## Follow-up actions

| Key | When it is shown | What it does |
|---|---|---|
| `R`, `M`, `S` | Some saved paths are broken | `R` searches your games folder for the right file, `M` lets you pick the file yourself, `S` searches another folder. TeknoParrot Manager shows what it found and asks before it changes a profile. A safety backup is made first. |
| `P` | Some games need PostgreSQL | Opens [[Postgres Setup]] (menu 11). |
| `F` | Games are missing startup files | Opens the startup files review (see below). |
| `5` to `9` | No broken paths | Opens ReShade, dgVoodoo2, GPU Fix, Force Feedback or BepInEx setup. |
| `D`, `B` | Always | Details, or back to the main menu. |

---

## Game startup files

Some emulators need files before a game can start: PlayStation 3 firmware (RPCS3), PCSX2x6 firmware, Chihiro (CxbxR) firmware, and a settings file for each Play! game. The check only looks. It does not read or change those files.

If files are missing, you see `[F] Fix the missing startup files (shows what it found and asks before copying)`. It looks in your own game collection and other TeknoParrot folders. It checks every file against the Eggman DAT list, asks before it copies, and keeps a different file that is already there unless you choose to replace it (your file is backed up first). Nothing is ever downloaded. See [[Game Startup Files]].

---

## When to use it

- After a big [[AutoSync]] or [[Register]] run, to see what is left.
- Before you run GPU Fix, dgVoodoo2, PostgreSQL or force feedback setup, to see how many games need each one.
- Any time you want a quick picture of your library.

<details><summary>Details: run it on a schedule</summary>

Windows Task Scheduler can run the health check without anyone at the keyboard. It is the only job an unattended run supports.

1. Run TeknoParrot Manager once yourself so your settings are saved.
2. Add `"UnattendedMode": "HealthCheck"` to `TeknoParrot-Manager.config.json` in `<your TeknoParrot folder>\TeknoParrotManager\State\`.
3. In Task Scheduler, create a task that starts `powershell.exe` with the arguments `-ExecutionPolicy Bypass -NonInteractive -File "C:\path\to\TeknoParrot-Manager.ps1" -Unattended`.

An unattended run never asks questions and never starts a follow-up action. Exit code 0 means the check finished, even if it found problems. Exit code 2 means some checks could not finish. Without saved settings you see `ERROR: Unattended mode requires saved settings.` Without `UnattendedMode` you see `[Unattended] Mode must be set before starting.` Look in `TeknoParrot-Manager.log` after each run.

</details>
