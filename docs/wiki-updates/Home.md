# TeknoParrot Manager

![TeknoParrot Manager](banner.png)

TeknoParrot Manager sets up your extracted TeknoParrot games for you. It registers them, copies controls between games of the same type, and keeps your library tidy. It backs up your game settings before it changes them.

It is made for beginners and is also useful if you already know TeknoParrot. It hides complexity, not detail: repeatable bulk steps save manual work, and Details and the log show what was done.

The latest published release is v1.0 RC8.4: https://github.com/Jumpstile/teknoparrot-manager/releases/tag/v1.0-RC8.4. This page matches v1.0 RC9, which is not published yet. Versions from RC8.1 on can update themselves in place with Check for Updates.
What is new in v1.0 is listed at the top of the [[Changelog]].

Test one game after each run before you trust the rest.

---

## New here?

1. Read [[Quick Start]]. It takes a few minutes.
2. Run `TeknoParrotUi.exe` once so it downloads its game profiles.
3. Run TeknoParrot Manager and choose **AutoSync** (games are ZIP files) or **Register only** (games are already extracted).
4. Open TeknoParrotUI. Your games are there.
5. In TeknoParrotUI, set up the controls for one game of each type you use. Run TeknoParrot Manager again. It copies those controls to the other games of the same type.
6. Test one game before you trust the rest.

---

## The main menu

Type a number and press Enter. After each task you come back to this menu.

| # | Menu item | What it does | Page |
|---|---|---|---|
| 1 | AutoSync | Extracts your game ZIPs, then registers the games | [[AutoSync]] |
| 2 | Register only | Registers games you already extracted | [[Register]] |
| 3 | Propagate Controls | Copies controls from a game you set up to games of the same type | [[Propagate Controls]] |
| 4 | Crosshair setup | Adds custom crosshairs to lightgun games | [[Crosshairs]] |
| 5 | ReShade setup | Visual filters: sharper image, CRT-style scanlines, borders | [[ReShade]] |
| 6 | dgVoodoo2 setup | Fixes some old DX8, DirectDraw, and Glide games | [[dgVoodoo2]] |
| 7 | GPU fix setup | Finds your graphics card and applies the matching fix | [[GPU Fix]] |
| 8 | Force feedback (FFB) setup | Wheel and stick force feedback | [[FFB Setup]] |
| 9 | BepInEx setup | Installs or updates BepInEx, a modding framework some games use | [[BepInEx]] |
| 10 | Region setup | Picks the country your games start in | [[Region Setup]] |
| 11 | Postgres setup | Sets up PostgreSQL for games set to Existing PostgreSQL (games on Internal storage need none) | [[Postgres Setup]] |
| 12 | Required game patches | Installs required fixes for exact game versions | [[Required Game Patches]] |
| 13 | Library health check | Checks your library without changing it | [[Health Check]] |
| 14 | Restore backup | Puts back UserProfiles, PostgreSQL, or LaunchBox backups, or resets games | [[Restore Backup]], [[Reset and Restore]] |
| 15 | Check for Updates | Checks GitHub for a newer release | [[Check for Updates]] |
| 16 | Create Support Package | Makes one ZIP of logs and reports to send when you ask for help | [[Support Package]] |
| 17 | Exit | Closes the program | |

Items 4 to 10 are optional. Items 11 and 12 are only for some games.

---

## Other pages

- [[Setup]] -- first run, folders, and saved settings
- [[LaunchBox Integration]] -- add your games to LaunchBox
- [[Game Startup Files]] -- firmware, System 11 saved files and other files some games need
- [[CPS3 First-Boot Files]] -- optional files that speed up the first start of CPS3 games
- [[Registration Ledger]] -- the record of what AutoSync and Register did
- [[Troubleshooting]] -- common problems and fixes
- [[Changelog]] -- version history

---

## Who is it for?

- Large TeknoParrot libraries and NAS-based collections
- LaunchBox users
- RetroBat and Batocera users

You may not need it if you only manage a few games by hand.

---

## Staying safe

- Your game settings are backed up before they change. If a backup cannot be made, TeknoParrot Manager stops.
- Preview shows what would change without changing it.
- It asks before it does anything big. If a check fails, it stops and says what to do next.
- Restore backup can put things back. See [[Restore Backup]].
- It does not provide games, firmware, or BIOS files. You supply your own.
- A registered game is not a tested game. Open the game in TeknoParrotUI, set up its controls, and test it.

<details>
<summary>Details: who owns what</summary>

- TeknoParrot and TeknoParrotUI own the emulator, its game profiles, and how games launch.
- LaunchBox, RetroBat, and Batocera own their own game libraries.
- Windows owns drivers, permissions, services, and input devices.
- PostgreSQL owns its service and databases.
- Dolphin/Triforce and PCSX2x6 own their runtimes, firmware, and BIOS. BepInEx owns its plugins.
- Eggman/RomVault owns its community DAT list.

</details>

---

## Links

- [Releases](https://github.com/Jumpstile/teknoparrot-manager/releases) -- download the latest ZIP
- [Issues](https://github.com/Jumpstile/teknoparrot-manager/issues) -- report a bug
