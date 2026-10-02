# Restore Backup (Mode 11)

AutoSync backs up the current contents of `UserProfiles` (excluding the existing `FullBackup` folder) before extraction; preview mode skips the backup. LaunchBox library files are backed up before every direct write (since v0.98), and PostgreSQL databases before every [[Postgres Setup]] run (since v0.99). Mode 11 lets you restore any of these from inside the script -- no File Explorer needed.

When you choose mode 11, you're first asked which backup to restore:

1. **TeknoParrot UserProfiles backup**
2. **LaunchBox library backup** -- only relevant if you've used the [direct LaunchBox integration](Register#launchbox)
3. **Postgres database backup** -- only relevant if you've used [[Postgres Setup]]

---

## TeknoParrot UserProfiles backup

### Backup location

```
<TeknoParrotRoot>\UserProfiles\FullBackup\<date_time>\
```

If AutoSync cannot create or complete this backup (for example, because of disk or permission errors), it does not proceed with extraction.

### How to restore

1. Close TeknoParrot completely (the script checks and will stop if it detects TeknoParrot is still running).
2. Run the script, choose **mode 11 -- Restore backup**, then **1) TeknoParrot UserProfiles backup**.
3. The script lists all available backups, most recent first, with file counts.
4. Pick one by number.
5. Type `YES` to confirm.
6. The restore runs. Re-open TeknoParrot to use the restored profiles.

### Manual restore

If you need to restore outside the script:

1. Close TeknoParrot completely.
2. Copy the `.xml` files from any backup subfolder back into `<TeknoParrotRoot>\UserProfiles\`, overwriting the current files.
3. Reopen TeknoParrot.

---

## LaunchBox library backup

### Backup location

```
Scripts\LaunchBoxBackups\<date_time>\
```

Only the specific files the direct LaunchBox integration was about to change are backed up (`Emulators.xml`, `Platforms.xml`, and the target platform file(s)) -- never LaunchBox's entire `Data\` folder, since some platform files run 20+ MB. If the backup fails, nothing is written to LaunchBox in the first place.

### How to restore

1. Close LaunchBox and BigBox completely (the script checks and will stop if either is still running).
2. Run the script, choose **mode 11 -- Restore backup**, then **2) LaunchBox library backup**.
3. The script lists all available backups, most recent first, with file counts.
4. Pick one by number.
5. Type `YES` to confirm.
6. The restore runs, copying each backed-up file back to its original relative location under your LaunchBox root.

### Manual restore

If you need to restore outside the script:

1. Close LaunchBox completely.
2. Copy the files from `Scripts\LaunchBoxBackups\<date_time>\` back into LaunchBox's `Data\` folder at the matching relative path, overwriting the current files.
3. Reopen LaunchBox.

---

## Postgres database backup

### Backup location

```
Scripts\PostgresBackups\<date_time>\<dbname>.backup
```

Every existing Postgres database belonging to a registered, Postgres-needing game is backed up (via `pg_dump`, custom format) every time [[Postgres Setup]] runs, before anything else happens. Skipped silently if PostgreSQL isn't installed yet, or no databases exist -- nothing to back up on a first run.

### How to restore

1. Run the script, choose **mode 11 -- Restore backup**, then **3) Postgres database backup**.
2. The script lists all available backups, most recent first, with the database names in each.
3. Pick one by number.
4. Type `YES` to confirm -- this **replaces the current content** of each database being restored.
5. The script drops and recreates each database from its backup (your existing PostgreSQL install is not touched, just the database content).

### Manual restore

If you need to restore outside the script, use `pg_restore` directly against the `.backup` file with PostgreSQL's own tools (`pg_restore.exe` in `C:\Program Files (x86)\PostgreSQL\8.3\bin\`).

---

## Notes

- Restore mode cannot run with `-Unattended` -- it requires you to pick a backup interactively.
- UserProfile XMLs, LaunchBox's own library files, and Postgres databases are each backed up and restored independently; game files on your staging drive are never touched.
