# Library Health Check (menu 14)

The health check looks over your registered games and tells you what needs attention. The check itself only reads. It does not change a file. You see `TeknoParrot Manager checked your setup and did not change anything.`

When it ends, it offers follow-up actions (repair a path, set up PostgreSQL, and so on). Those are separate steps. Each one tells you what it will do and asks before it changes anything.

---

## How to run it

1. Start TeknoParrot Manager and type `14` at the main menu.
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
| [[GPU Fix]] | Games that have a GPU fix setting that does not match your graphics card. If your graphics card is not found (common on a virtual machine), the check says it was skipped. |
| Force feedback | Games with a built-in FFB Blaster setting that is not turned on. The separate plugin is not looked at here. Use [[FFB Setup]] for that. |
| [[dgVoodoo2]] | Games that need dgVoodoo2 but do not have it yet. |
| [[BepInEx]] | Games whose profile says they need BepInEx but do not have it set up. |
| [[Postgres Setup]] | Whether PostgreSQL is installed and running, whether games still need setup, and whether each game database is there and opens. A database that is not ready shows as `Problem - <game>`. A game that has no database yet but makes its own the first time it starts (`Profile ready`) is not a problem. A game set to Internal storage needs no database install. It is skipped and counted as `Game database: OK` with a note to start the game once so it makes its own database. |
| Game startup files | Games whose emulator is missing files it needs to start. See below. |
| Game types | Whether each game's type is one TeknoParrot Manager knows, whether TeknoParrot has released the game yet (a game still in development shows as `not available yet`), and whether the emulator for that type is in your TeknoParrot folder. Each type has its own emulator folder. Press `D` for the list. |
| Game files | Games that need you to pick the game file by hand, because their profile names no game file and TeknoParrot has no setup file for them. Press `D` for the list, then set the game file in TeknoParrotUI. |
| Saved files | A note (not a problem) when some arcade games that use the TeknoS11 loader (System 10, System 11, System 12, Sony ZN, Konami 573, Taito G-NET and similar boards) have no saved setup files yet. If you have the saved-files set for these games, the main run can copy it. See [[Game Startup Files]]. |
| Game support | Whether games need you: a game file is missing, a second game file (for example a CHD, a disk-image file) is not chosen, or PostgreSQL settings are missing. Press `D` for counts per emulator. The setup steps come from the saved copy of the Game Notes page; this check never goes online. |

The last lines give the verdict: `Everything looks fine.` or `Some things need attention.` If a check could not finish, you see `Some checks could not finish, so this is not an all-clear.` A game in a very long folder path counts as not fully checked.

The check also shows how many games already have [[ReShade]] and [[BepInEx]] (`ReShade installed: N of M valid games`, `BepInEx installed: N of M valid games`). ReShade is your choice for each game, so it is not flagged. BepInEx is flagged only for games whose profile says they need it. If any of them do not have it yet, you see `Games that need BepInEx and do not have it set up: <names>`. Use [[BepInEx]] setup (menu 10) to fix that.

Press `D` at any time to see every detail. The details are also saved in the log.

---

## Follow-up actions

| Key | When it is shown | What it does |
|---|---|---|
| `R`, `M`, `S` | Some saved paths are broken | `R` searches your games folder for the right file, `M` lets you pick the file yourself, `S` searches another folder. TeknoParrot Manager shows what it found and asks before it changes a profile. A safety backup is made first. |
| `P` | Some games need PostgreSQL, and the game check finished | Opens [[Postgres Setup]] (menu 12). |
| `F` | Games are missing startup files, no paths are broken and the game check finished | Opens the startup files review (see below). |
| `6` to `10` | No broken paths and the game check finished | Opens ReShade, dgVoodoo2, GPU Fix, Force Feedback or BepInEx setup. |
| `D`, `B` | Always | Details, or back to the main menu. |

---

## Game startup files

Some emulators need files before a game can start: firmware for arcade games on PlayStation 3 style hardware (RPCS3), PCSX2x6 firmware, Chihiro (CxbxR) firmware, and a settings file for each Play! game. The check only looks. It does not read or change those files.

If files are missing, no saved paths are broken and the game check finished, you see `[F] Fix the missing startup files (shows what it found and asks before copying)`. If a saved path is broken or the check did not finish, the `F` choice is not shown. It looks in your own game collection and other TeknoParrot folders. It checks every file against the Eggman DAT list, asks before it copies, and keeps a different file that is already there unless you choose to replace it (your file is backed up first). Nothing is ever downloaded. See [[Game Startup Files]].

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

To check a copy before a release or on a test PC without any questions, run `.\TeknoParrot-Manager.ps1 -ValidationReport` (optional: `-ValidationRoot "<your TeknoParrot folder>"` and `-ValidationJsonPath "<report file>"`). It is read-only; the JSON file is the only thing it writes. It starts no game. It counts how many games with a reviewed controls list have verified, not verified, missing, unsupported or unknown controls; a game counts as verified only after you said you played it and its controls worked. Exit code 0 means pass, 3 action required, 4 failed (for example no TeknoParrot folder), 1 the report could not be made.

</details>
