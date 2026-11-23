# Postgres Setup

Some Incredible Technologies (IT) games need a small database on your PC. Postgres setup installs it and gets each game's database ready. It is main menu item 11, **Postgres setup**. It sits under "Game Requirements (only for some games)".

The database is **PostgreSQL 8.3**. These games need it: all Golden Tee Live years (2006 to 2023, 2025, 2026), all Golden Tee PGA Tour games (2021 to 2023, 2025, 2026), Power Putt Live, Silver Strike Bowling Live, Target Toss Pro and Orange County Choppers Pinball. TPM finds them by what their profile says, so a new game of this kind needs no new TPM version.

**Internal or Existing PostgreSQL?** Newer TeknoParrot profiles of these games have a Storage box. **Internal** is the new default. It needs no database install. Start the game once and it makes its own database. Postgres setup and [[Health Check]] skip these games and never say their database is missing. **Existing PostgreSQL** is for keeping an existing server and its saved progress. Everything on this page is for games set to Existing PostgreSQL (and older profiles with no Storage box). TeknoParrot Manager never switches a game from one to the other, and never touches saved progress without a backup first.

Setup finds the games that need it by itself. If none of your registered games need it, it says so and installs nothing.

---

## Quick steps

1. Start TeknoParrot Manager. At `Enter 1-17:` type `11` and press Enter.
2. If PostgreSQL is not installed yet, setup first tells you what it will ask Windows for. Read it, then press Enter at `Press Enter to open the Windows permission window`. Windows then asks for permission. Click **Yes**. Use an administrator account of this PC. If your account is not an administrator, close TeknoParrot Manager and start it again with "Run as administrator". (Setup does not wait for Enter when no keyboard is there.)
3. You are asked for two passwords (see below). Type each one twice.
4. Wait. Setup installs PostgreSQL, makes each game's database from the game's own backup file, and tests it with the game's own settings.
5. When you see `PostgreSQL setup finished.`, open TeknoParrot and start a game. For games set to Existing PostgreSQL, nothing else is needed on first start. A game set to Internal makes its own database the first time you start it.

At the end, press Enter to go back to the menu, or `D` for details. Everything on the screen is also in the log.

---

## The two passwords

Only asked the first time, when PostgreSQL is installed.

1. **SERVICE ACCOUNT** password -- for the Windows account that runs PostgreSQL in the background. You will almost never need it again. It is not saved.
2. **DATABASE** password -- the important one. It is saved (encrypted) so every Postgres game can be set up automatically. You need it again if you ever open the database with a tool like pgAdmin.

You can press Enter at a password prompt to go back. Then PostgreSQL is not installed and nothing is changed. A password cannot contain a double quote (`"`). The DATABASE password must be 1 to 100 characters: English letters, digits, spaces and US keyboard symbols.

---

## If PostgreSQL is already installed

Setup does not reinstall it. Your data is kept.

If the saved database password does not work, you are told. Choose `F` and type the password PostgreSQL already has. Setup checks it and saves it. If nobody knows the password, choose `X` (shown only after PostgreSQL really refused it). Nothing is changed by `X`. It explains why the password cannot be reset for you.

---

## What setup does to each game

- A database that already exists is never recreated and never restored over.
- A game profile that already has its own password, server, port or user is listed, and you are asked first. `K` keeps them as they are (the default). `R` replaces the password in them.
- A game that has no starting database file (`pg_backup` folder) is `Profile ready` when TeknoParrot creates its database itself (Golden Tee Live 2018 and newer, Golden Tee PGA Tour). Start the game once. Any other game with none cannot get a database: it is left out and named, and every other game is still set up.
- Two games that name the same database (Golden Tee Live 2006 and Orange County Choppers Pinball both use `GameDB06`) keep their saved progress in the same tables, so one database cannot hold both. The first game keeps the name. The other gets its own database, made from its own backup, and its profile is saved with the new name. The old database is not changed and nothing is deleted. If a game that shares the name has no starting file, setup stops before changing anything. [[Health Check]] names games that still share one database.
- A backup that holds data that is not valid UTF8 (Golden Tee Live 2006 has some) is restored into a database that keeps every byte, so no table comes back empty.
- If a check fails, setup puts everything back the way it was and tells you which game and why.

Before it changes anything, setup backs up your existing PostgreSQL databases. To get one back, use [[Restore Backup]], option 2 (PostgreSQL database backup).

---

## If setup stops

- A stopped setup tells you what happened to your data: put back and checked, or could not be checked.
- After a repair that stopped part way, setup does not claim that nothing changed. It says some things may have changed and points you to **View Log**.
- If the install itself fails, open View Log, then choose Postgres setup again. If it then lists PostgreSQL items it found, read the warning on that screen before you delete anything. A PostgreSQL folder can hold game databases and saved scores.
- Two TeknoParrot Manager windows cannot change PostgreSQL at once.

---

<details>
<summary>Details: more about how it works</summary>

**Games.** Any registered game whose profile has a Postgres settings section is picked up, so a newly added game is covered when you register it.

**Passwords.** The database password is encrypted with Windows DPAPI (tied to your Windows account and this PC) and saved in `<your TeknoParrot folder>\TeknoParrotManager\State\TeknoParrot-Manager.config.json`.

**Backup files.** The game's database is built from the game's own backup in its `pg_backup` folder. When there are several, the newest one is used. The confirm screen, Details and the log say which file was used.

**Checked means connected.** A database counts as ready only when setup could connect with the settings saved in the game's profile and find its tables.

**Time limits.** Each PostgreSQL tool has a time limit. A tool that runs too long is stopped and counted as failed, and setup is rolled back.

**Backups on older folder permissions.** Backups, database moves and saved proof files work on PCs whose folders still use the older owner-only permissions. If this step does fail, the log names the cause.

**Administrator.** Installing PostgreSQL needs administrator access. TeknoParrot Manager asks for it itself through the Windows permission box and continues by itself after you approve. Approving alone does not mean setup worked, so read the result.

**Where this comes from.** This automates the manual steps in [Eggmansworld/tp-it-guides](https://github.com/Eggmansworld/tp-it-guides), which also explains how to do it by hand.

</details>

[[Health Check]] shows whether the PostgreSQL service is installed and running, and whether every game database is ready. It changes nothing.
