# Check for Updates (menu 15)

Check for Updates looks for a newer TeknoParrot Manager on GitHub. Nothing is downloaded or changed until you answer `Y`.

---

## How to run it

1. Start TeknoParrot Manager and type `15` at the main menu.
2. If you already have the newest version, you see `You have the newest version (...)` and `No update needed.` That is the end.
3. If a newer version exists, you see `An update is available: <your version> -> <new version>`, a list of what updating will do, and this question:

```
Update to <new version> now? (Y/N)
```

`N` prints `Skipped -- no changes made.` and nothing happens. `Y` is the only answer that starts the update.

If GitHub cannot be reached, you see `Could not check for updates`. Your copy is not changed. Try again later.

---

## What happens after you answer Y

RC8.1 is the first version that can update itself like this. The latest published release is v1.0 RC8.3 (the previous one is RC8.2). If you run a build before RC8.1 (for example RC8 or RC7), see "Updating from a build before RC8.1" below.

1. It downloads the update and checks that it is the real file. GitHub's own SHA-256 checksum for that file is required. If it is missing or does not match, nothing is installed and the download is removed.
2. It looks inside the ZIP before it changes anything.
3. It backs up every file it replaces.
4. It installs the files and checks them.
5. You see `Update installed and verified. Restart TeknoParrot Manager to use it.` The program does not restart by itself. Start it again yourself.

What it touches:

- It replaces the program files that are different in the new release. Files that are the same are left alone. New files are added.
- It never deletes anything. Your own files, `UserProfiles` and your backups are not touched. Older program files that the new release no longer has stay where they are.

The backup goes to `UpdateBackups\TeknoParrotManager_<date and time>\` next to the script. A backup is never reused or overwritten.

If any file cannot be replaced, every file is put back and nothing changes. The message says your old version is back only when that was checked.

If the drive is too full, you see `There is not enough free space for the update` and nothing is installed. Free some space and try again.

---

## Updating from a build before RC8.1

Builds before RC8.1 (for example RC8 or RC7) cannot install a whole release. Do this once:

1. Download the ZIP of the latest release from [GitHub Releases](https://github.com/Jumpstile/teknoparrot-manager/releases).
2. Extract all of its files over your TeknoParrot Manager folder (or into a new folder).
3. Start `TeknoParrot-Manager.bat` again.

After that, menu 15 does the updating.

---

## Check at start

TeknoParrot Manager also checks once when it starts. If you are current, you see nothing. If a newer version exists, you see the version numbers and this question:

```
Update now, remind me later, or view release notes? (Y/N/V)
```

`V` shows the release notes. `Y` shows the same list of steps and asks `Proceed? (Y/N)`. `N` continues to the menu.

To turn the start check off, set `CheckForUpdatesOnStartup` to `false` in `TeknoParrot-Manager.config.json`. The file is in `<your TeknoParrot folder>\TeknoParrotManager\State\`. The start check never runs in an unattended run.

<details><summary>Details</summary>

- Only the latest GitHub release of the TeknoParrot Manager project is used.
- The script inside the ZIP is checked before it is installed, and its version must match the release. Anything else is refused.
- The download goes to a temporary folder first and is checked before the ZIP is opened.
- The separate command-line helper `tools\Invoke-TpmAutoUpdate.ps1` has `-CheckOnly` (the default) and `-Apply`. `-Apply` still refuses a release that has many files and changes nothing.
- Before it installs, the free space on the drive must be at least twice the unpacked size. Files are unpacked into a temporary `tpm-update-staging-...` folder first, and that folder is removed at the end.

</details>

If an update keeps failing, download the complete ZIP yourself from [GitHub Releases](https://github.com/Jumpstile/teknoparrot-manager/releases). See also [[Troubleshooting]].
