# Setup

How TeknoParrot Manager (TPM) is set up, where it keeps its files, and how to reset it. To run it the first time, start with [[Quick Start]].

If something goes wrong on a first run, stop and keep your backups. Read [[Troubleshooting]] before you try again.

---

## What you need

- Windows 10 or 11
- PowerShell 5.1 or later (already part of Windows)
- TeknoParrot installed, with `TeknoParrotUi.exe` opened at least once
- Your games, as ZIP files for AutoSync to extract, or already extracted into one folder per game

TPM does not install TeknoParrot and does not provide game files, firmware, or BIOS.

---

## First-time questions

On the first run TPM asks a few things. Your answers are saved, so later runs only ask `Use these settings? (Y/N, D = show them)`.

| Question | What it means |
|---|---|
| TeknoParrot folder | The folder that has `TeknoParrotUi.exe`. TPM looks for it and asks `Use this path? (Y/N)`. If it finds more than one, pick a number. If it finds none, it asks `Type the path of your TeknoParrot folder, the one with TeknoParrotUi.exe in it, or Q to quit (or type B to browse)`. Type the folder, type `B` to browse, or type `Q` to quit (nothing is changed). TPM never offers a folder that has no `TeknoParrotUi.exe`. If you close the browse window without choosing, it asks again. If the folder does not exist, or has no `TeknoParrotUi.exe`, it tells you and asks again. |
| Staging folder for game files | Where AutoSync puts extracted games, one folder per game. It has the same choices: type a path, or type `B` to browse. It must be outside TeknoParrot and outside your ZIP folder. |
| Folder naming | `N` (default) names folders `GameName`. `Y` uses `GameName.teknoparrot` for RetroBat/Batocera. |
| DAT list | Optional. A list of game names that helps TPM recognize games. Press `D` to download it, `B` to browse for one you have, or `N` to skip. |
| Game ZIP folder | Asked when you first choose AutoSync. The folder that directly holds your `.zip` files. It can be a network folder. |

<details>
<summary>Details</summary>

TPM looks for `TeknoParrotUi.exe` in common places: your LaunchBox Emulators folder, drive roots such as `C:\TeknoParrot`, folders such as `\Games\TeknoParrot` and `\Emulators\TeknoParrot`, and the Program Files folders on every drive.

</details>

---

## Where TPM keeps its files

TPM keeps its own files in a `TeknoParrotManager` folder inside your TeknoParrot folder:

| Folder | What is in it |
|---|---|
| `TeknoParrotManager\State\` | Your saved settings: `TeknoParrot-Manager.config.json` |
| `TeknoParrotManager\Logs\` | The log: `TeknoParrot-Manager.log` |
| `TeknoParrotManager\Reports\` | Reports from each run, such as `TeknoParrot-Manager-controls.txt`, `TeknoParrot-Manager-ActionItems.txt`, and `TeknoParrot-LaunchBox-Import.xml` |
| `TeknoParrotManager\SupportPackages\` | The ZIP files made by **17) Create Support Package**. See [[Support Package]]. |
| `TeknoParrotManager\Backups\` | Safety copies, such as `AutoSyncReplaced` and the PostgreSQL backups |
| `TeknoParrotManager\Assets\` | Your own add-on files (see below) |

Your UserProfiles are backed up inside TeknoParrot, in `UserProfiles\FullBackup\`. See [[Restore Backup]].

The AutoSync record `TeknoParrot-Manager.syncstate.json` is in your games (staging) folder. The overrides file `TeknoParrot-Manager.overrides.json` is next to the script.

On start-up TPM can offer `Tidy up now?` to move older files from beside the script into the folders above. Answer `N` and none of your files move and your settings stay as they were. TPM may still move its own start-up log into its Logs folder without asking.

### Add-on files in Assets

- `Assets\ReShade\`: your own ReShade DLLs. A `ReShade\` folder beside the script is still found if you skip the tidy-up. See [[ReShade]].
- `Assets\dgVoodoo2\`: your dgVoodoo2 files. TPM saves its own download here too. A `dgVoodoo2\` folder beside the script is still found. See [[dgVoodoo2]].
- `Assets\ReShadePresets\`, `Assets\dgVoodoo2Presets\`, and `Assets\CustomThumbnails\`: per-game presets and custom thumbnails.

Crosshairs stay in the script folder.

---

## Overrides file

`TeknoParrot-Manager.overrides.json` is created with empty values on the first run. Use it to fine-tune single games:

```json
{
  "noSync":             ["ZipBaseName1", "ZipBaseName2"],
  "onlySync":           ["ZipBaseName1", "ZipBaseName2"],
  "subFolderMap":       { "ProfileCode": "Sub\\Folder" },
  "datFile":            "C:\\full\\path\\to\\collection.dat"
}
```

| Key | What it does |
|---|---|
| `noSync` | ZIP names AutoSync always skips |
| `onlySync` | AutoSync extracts only these ZIPs |
| `subFolderMap` | For a game code, the sub-folder inside the game folder where its game file is, when Register cannot find it |
| `datFile` | Full path to a DAT file |

All keys are optional. Older versions had other keys (`noPropagate`, `forceArchetype`, `familyOverride` and `canonicalArchetype`). They are ignored if they are still in the file.

---

## Resetting

| To reset | Do this |
|---|---|
| Your saved settings | At `Use these settings?` press `N`, or delete `TeknoParrotManager\State\TeknoParrot-Manager.config.json` |
| AutoSync's record of extracted games | Delete `TeknoParrot-Manager.syncstate.json` from your games folder |
| One game's profile | Back up its `.xml` from `UserProfiles\`, delete it, then register again |

To put games back from a restore point, use [[Reset and Restore]] instead.

---

## Unattended runs

`-Unattended` runs without asking questions, for Windows Task Scheduler. The only unattended job is the read-only Library health check. To set it up, see [[Health Check]].
