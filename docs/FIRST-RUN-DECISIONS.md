# First-run decisions

This page lists every question TeknoParrot Manager (TPM) asks the first time you run it. For each one it says whether TPM does it for you, asks you, or still needs proof, and why. It is the record for issue 249.

How to read the last column:

- **Automated**: TPM can pick a safe answer without you. You can still change it later.
- **Asked**: only you know the answer, or a wrong guess could put files in a bad place. TPM asks and explains.
- **Needs evidence**: the owner has not decided yet because no proof is on file.

## The questions

| Question | Result | Why |
| -------- | ------ | --- |
| TeknoParrot folder | Automated, then asked if needed | TPM looks for `TeknoParrotUi.exe` on every local drive (drive roots, the folders in them and the usual game and emulator folders, not a full crawl of the drive) and says which drives it searched. A folder without that file is never offered. Every match is shown as a numbered row with drive, full path and version; you pick one, search again (R), type or browse (B) or quit (Q). Nothing is changed until you choose. A run with no one at the keyboard (`-Unattended`) uses the first match, or stops with an error if there is none. |
| Game ZIP folder (where your original `.zip` files are) | Asked | Only you know where you keep your ZIPs. TPM asks the first time you choose AutoSync, not at start-up, and it asks again if you leave the answer empty or the folder is not there. The ZIPs stay where they are. TPM never deletes them. |
| Staging folder (where AutoSync unpacks games, one folder per game) | Asked, with a safe recommendation | The folder must be outside TeknoParrot, outside TPM's own folder and outside your ZIP folders. TPM shows its recommendation first (a "TeknoParrot Games" folder on a drive, never inside those places). Pressing Enter takes it. A folder that overlaps one of those places is refused and TPM asks again. TPM creates nothing until a real run needs it. |
| Folder naming mode (standard or RetroBat style) | Asked, default No | Only you know whether you use RetroBat. The question says it only changes folder names (`GameName` or `GameName.teknoparrot`). TPM does not move games into RetroBat's folders. |
| Eggman DAT (a list of game names that helps TPM recognize renamed games; it contains no games) | Download is automated, the choice is asked | The question is "D = download (default), B = browse for one I have, N = skip". The download goes to a folder TPM owns (`TeknoParrotManager\Eggman` under your Windows local app data folder). There is no Save window. If a saved ZIP is already in a safe place, a newer copy goes next to it without asking. If TPM cannot use a safe folder, it says so, does not download, and lets you pick a file you already have. Skipping is safe. It asks again next time. |
| Supplementary ZIP folder (a second folder of your own game ZIPs) | Asked, optional | Only you know whether you keep a second collection. It is asked when you first choose AutoSync, and press Enter skips it. It is not the supplementary DAT. TPM may also ask for it later, only when a game needs startup files it did not find. |
| Supplementary DAT (extra version info) | Automated advice, not asked | It only adds alternate version info for games the main DAT already knows, so it does not stop any game from registering. TPM watches the run and recommends it afterward only if some games had an uncertain match. |
| TeknoParrot first-time setup advice | Automated, one question | TPM reads `ParrotData.xml` and never writes to it. If TeknoParrot's own setup is not finished (or TPM cannot tell), ACTION REQUIRED shows one short list of steps with the path to `TeknoParrotUi.exe`. TPM then asks "Open TeknoParrot now? (Y/N)", default No. It does not ask when setup is complete, when the run is unattended or a preview, or when the program file is missing. |
| Missing emulator component after registration | Automated | TPM checks for a required emulator file and, if it is missing, shows "EMULATOR COMPONENT NOT FOUND" with the games affected. It points you to TeknoParrot's own update or repair screen and changes nothing. |
| What to tell users about their original ZIPs after unpacking (keep, archive or delete) | Needs evidence | Today TPM only says the ZIPs stay where they are and are never deleted. Decision needed: the owner says whether they are safe to archive or delete after unpacking, registering and backing up, and what the screen should say. |
| RetroBat destination wording | Needs evidence | TPM says only to use the games folder where RetroBat looks for TeknoParrot games. Whether to name an exact folder is tracked in issue 272. |
| A reported crash when choosing R or B at the staging question (issue 251) | Needs evidence | No crash recording is in the tree. Reserved letters are now refused before the answer is read as a path. Decision needed: a recording that shows it, or "not reproduced, deferred". |

## In order, what each one does and how to undo it

These are the decisions in the order you meet them on a first run. Steps 1 to 4 follow the order in the user guide (Part 3 of "Start here"). Steps 5 and 6 come when you first choose AutoSync. Step 7 comes at the end of a run.

| Step | You decide | What it does | How to undo it |
| ---- | ---------- | ------------ | -------------- |
| 1 | Which TeknoParrot folder | TPM saves the folder with `TeknoParrotUi.exe` in it and reads from it. It never installs TeknoParrot. Typing `Q` quits and changes nothing. | Next time, answer N at `Use these settings? (Y/N, D = show them)` and pick the folder again. |
| 2 | Staging folder (called the games folder on screen) | AutoSync unpacks one folder per game here. Register only reads the games already in it. Nothing is created until a real run needs it. | Answer N at the same saved-settings question and pick another folder. Folders already unpacked stay where they are. TPM does not delete them for you. |
| 3 | Folder names: ordinary or RetroBat style | Y makes new unpacked folders end in `.teknoparrot`. N (the default) keeps ordinary names. It changes only the names of folders TPM unpacks. | Follow the five steps under "RetroBat / Batocera" in the user guide. Old folders are never deleted automatically. |
| 4 | The Eggman DAT: download, browse or skip | A names list that helps match renamed games. It contains no games and is saved in a TPM-owned folder. | Skipping is safe, and no game changes either way. |
| 5 | Game ZIP folder (first AutoSync) | Tells TPM where your original ZIPs are. TPM only reads from it. | Answer N at the saved-settings question and pick another folder. Your ZIPs are never changed. |
| 6 | Second ZIP folder (optional, first AutoSync) | A second place to look for your own ZIPs. Pressing Enter skips it. | Skip it by pressing Enter. Your ZIPs are never changed. |
| 7 | Open TeknoParrot now? (only when its own setup is not finished) | Starts `TeknoParrotUi.exe` and nothing else. TPM writes nothing to TeknoParrot. | Answer N (the default) and nothing opens. If you opened it, close it. |

The wording of the TeknoParrot setup note shown before step 7 is in the user guide, under "Action Required Summary".

## How the folders fit together

TPM keeps four things apart. Mixing them is how files get lost.

| Part | What it is | TPM's rule |
| ---- | ---------- | ---------- |
| Source | Your original game ZIPs, and the DAT or other files you provide. | Read only. TPM never changes or deletes them. |
| Staging | The folder where AutoSync unpacks one folder per game. | Must be a separate folder, outside TeknoParrot, TPM and the source folders. |
| Data | What TPM saves for itself: settings, reports, backups and the downloaded DAT. | Lives in TPM's own folders (for example `TeknoParrotManager` inside the TeknoParrot folder, and a TPM-owned DAT folder). |
| Wizard | TeknoParrot's own first-time setup window. | TeknoParrot owns it. TPM only reads whether it is finished, says what is left, and offers to open it. |

Registering a game, launching it, and finishing the wizard do not prove the controls work. TPM keeps those as separate lines.

## Still not proven on a real PC

On a clean PC with a fresh TeknoParrot folder, a person who has not used TPM runs the first run from start to finish. It passes when they accept the staging recommendation with Enter, never see a Save window for the DAT, see one TeknoParrot first-time-setup note in ACTION REQUIRED with the right path, and see the missing-component message for a game whose emulator file is absent, without asking anyone what a question means. The steps are in `docs\RC9-OWNER-TEST-PLAN.md`, Part 5.
