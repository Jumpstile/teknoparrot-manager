# Restore Backup (menu 15)

Restore backup puts back something TeknoParrot Manager saved earlier. You do it from inside the program. You do not need File Explorer.

TeknoParrot Manager saves copies for you:

- Your `UserProfiles` folder (TeknoParrot's saved game settings) is backed up before [[AutoSync]] and [[Register]] make changes, and before other steps such as [[Controls]].
- LaunchBox's library files are backed up before TeknoParrot Manager writes to them. See [[LaunchBox Integration]].
- Your PostgreSQL game databases are backed up when you run [[Postgres Setup]], normally before it changes them. If a setup was interrupted and is resumed, a reinitialize step can run first.

---

## How to start

1. Start TeknoParrot Manager and type `15` at the main menu.
2. Choose what to restore:

```
1) TeknoParrot UserProfiles backup
2) Postgres database backup
3) LaunchBox library backup
4) Reset and Restore: put back one game or all games from a restore point
   saved when TeknoParrot Manager started
5) Rebuild one game from its ZIP: put one game folder back to exactly what
   its ZIP holds (your old folder is kept)
```

3. At `Enter 1-5`, type a number and press Enter.

Every list of backups is shown newest first. You pick every backup yourself, so restore cannot run in an unattended run.

For option 4, see [[Reset and Restore]].

---

## 1) TeknoParrot UserProfiles backup

Use this to put back all your game settings (the `.xml` files in `UserProfiles`).

Backups are in `<your TeknoParrot folder>\UserProfiles\FullBackup\`. The copies TeknoParrot Manager makes when you remove ReShade are not in the list.

1. Close TeknoParrot completely. TeknoParrot Manager checks, and it stops if TeknoParrot is still running.
2. Choose option 1. You see `Saved copies of your game settings, newest first:` with the kind of copy, the time and the number of files.
3. Type the number of the copy you want. Press Enter alone to cancel.
4. You see `Warning: this replaces ALL your current game settings with this saved copy.` Type `YES` and press Enter. Any other answer cancels.
5. You see `Restore complete.` Open TeknoParrot again.

A restore does not keep a copy of the settings it replaces. If you may want your current settings back, copy the `.xml` files somewhere safe first, or use [[Reset and Restore]]. It saves a restore point before it changes anything.

<details><summary>Details</summary>

- A copy with no completion record is marked `older copy, cannot be fully checked`. If you pick it, you must type `UNVERIFIED` to use it anyway, and games that are not in it will be removed. That word is the only confirmation; you are not asked to type `YES` as well.
- Copies that were never finished are skipped and cannot be restored.
- If some files cannot be restored, you see `ERROR: ... file(s) could not be restored. The restore was not completed.` and TeknoParrot Manager tries to put the previous profiles back.
- To restore by hand: close TeknoParrot, copy your current `.xml` files to a safe folder, copy the `.xml` files from the backup into `UserProfiles`, then open TeknoParrot again.

</details>

---

## 2) Postgres database backup

Use this to put back a game's PostgreSQL database. It only matters if you used [[Postgres Setup]].

Backups are in `<your TeknoParrot folder>\TeknoParrotManager\Backups\PostgresBackups\<date and time>_<id>\`, one `<database name>.backup` file per database. An older install may have them in a `PostgresBackups` folder next to `TeknoParrot-Manager.ps1` instead.

1. Choose option 2. You see `Available Postgres database backups (most recent first):`.
2. Type the number of the backup you want. Press Enter alone to cancel.
3. You see a warning that this will replace the current content of each database listed. TeknoParrot Manager first saves a copy of what is there now, and keeps that copy after a good restore.
4. Type `YES` to confirm. If the saved database password does not work, you are asked for it.
5. You see the result, for example `The restore finished and was checked.` If it could not finish, the message says whether your data is back the way it was. Press `D` for details.

Your PostgreSQL install is not touched, only the database content. A backup marked `[INCOMPLETE - cannot be restored]` cannot be used. If there are no backups, you see `No Postgres backup folders found.`

<details><summary>Details</summary>

Restoring by hand is for experts. `pg_restore.exe` (in `C:\Program Files (x86)\PostgreSQL\8.3\bin\`) must be told which empty database to write into (the `-d` option). Running it on the `.backup` file alone does not restore a database.

</details>

---

## 3) LaunchBox library backup

Use this to put back LaunchBox files that TeknoParrot Manager changed. It only matters if you used [[LaunchBox Integration]].

Backups are in `<your TeknoParrot folder>\TeknoParrotManager\Backups\LaunchBoxBackups\<date and time>-<id>\`. If your TeknoParrot folder is inside your LaunchBox folder, they are kept in `%LOCALAPPDATA%\TeknoParrotManager\LaunchBoxBackups\` instead, with one subfolder for each LaunchBox library. An older install may have them in a `LaunchBoxBackups` folder next to `TeknoParrot-Manager.ps1`.

1. Close LaunchBox and BigBox. TeknoParrot Manager never closes them for you. It checks after you pick a backup and answer the restore question (step 5), not before. If one is open then, it waits. Close it and press Enter, or type `N` to cancel.
2. Choose option 3. If no LaunchBox folder is saved, you are asked for it (the folder with `LaunchBox.exe`).
3. Pick a backup. Press Enter (or `B`) to cancel.
4. You see the files that will be put back and a warning that any LaunchBox changes made to them since the backup will be replaced.
5. Answer `Restore these files into <folder> after a verified backup of their current state? (Y/N)`. The default is `N`. This restore does not ask for `YES`. A file that TeknoParrot Manager added earlier and you have not changed gets its own `Remove the file ...? (Y/N)` question, because removing it deletes it.

TeknoParrot Manager checks the backup, saves a copy of your current files, restores, and reads every file back. If the backup came from another LaunchBox folder, the same single question says so and asks whether to restore it into the target folder anyway.

If the result says `PARTIAL`, some files were left or could not be checked. Keep the backup, read the `Needs review` lines, and do not retry blindly.

<details><summary>Details</summary>

- If there is no backup, you see `No LaunchBox backup is available; no library writes were attempted.`
- Only `Data\Emulators.xml`, `Data\Platforms.xml` and `Data\Platforms\<name>.xml` can be restored.
- An older backup with no `manifest.json` is listed as `legacy snapshot; source library unknown`. Only the files in it are restored, and nothing else is deleted.
- To restore by hand: close LaunchBox and BigBox, copy your current files to a safe folder, copy the backup files into LaunchBox's `Data\` folder at the same paths, then open LaunchBox again.

</details>

---

## 4) Reset and Restore

Puts one game, or all games, back to how they were at a restore point saved when TeknoParrot Manager started. See [[Reset and Restore]].

---

## 5) Rebuild one game from its ZIP

Puts one game folder back to exactly what is in its original ZIP. See [[Reset and Restore]].

---

Options 1 to 4 never touch game files on your games drive. Option 5 replaces one game folder with a fresh copy from its ZIP, and keeps your old folder aside.
