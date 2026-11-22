# Register (menu 2)

Register looks at the games already in your games folder and matches each one to its TeknoParrot profile. It saves a copy of the profile in `UserProfiles` and sets the game path. TeknoParrot picks the games up the next time it opens.

Use it when your games are already unzipped. [[AutoSync]] (menu 1) runs the same registration right after it unzips your games.

---

## How to run it

1. Start TeknoParrot Manager and type `2` at the main menu.
2. Choose `P` (preview, the default), `R` (run now) or `B` (back). A preview writes nothing -- see [[AutoSync#preview--dry-run-mode]].
3. A real run backs up your `UserProfiles` folder first, then registers the games.

Register only works on games that are already in your games folder. It does not create that folder. If it is missing, you can choose an existing one (`R`) or go back (`Q`).

---

## What you see

| Result | Meaning |
|---|---|
| `Registered` | The profile was matched and the game now shows in TeknoParrot. |
| `Registered (dat)` | The folder name matched the Eggman DAT list, so the profile code came from the list. |
| `Registered (fuzzy ...)` | The folder name was close to a profile name. Shown in cyan with the folder name. Check that it is the right game. |
| `Existing profile files: N` | These games already had a profile. They are left as they are. |
| Games listed under ACTION REQUIRED | TeknoParrot Manager could not choose safely. You pick the profile yourself in TeknoParrotUI. |

An existing profile is never overwritten by registration.

A real run ends with the banner `Registration run finished.` It means the run is over. It does not mean every game's controls are set up.

**Two folders want the same profile.** If one profile is claimed by two folders (for example two copies of one game), TeknoParrot Manager asks `Resolve them now by picking which folder keeps the profile? (Y/N)`. For each one, choose `K` to keep the current folder, `S` to switch to the other folder, or `Q` to stop. A profile left unresolved is listed under ACTION REQUIRED. A preview only reports these.

---

## Region question

After new games are registered, you are asked once:

```
Which country do you want your games to start in?
```

Type the number of a country to set it on the new games that offer it, or `0` to leave every game as it is. Only countries the games really offer are listed. A game never gets a region it does not have. A region you chose earlier is kept. Games with no automatic choice are not changed.

The question is not asked in a preview, or when none of the new games offers a region. To set or change the region later, use [[Region Setup]] (menu 10).

---

## Special cases

- **Games with a second program.** A few games (for example the Initial D Arcade Stage series) start a second program next to the main one. Register fills in the second game path when that file sits in the same folder as the main one. A second path that already points at a file that exists is kept.
- **Very long folder paths.** Games in folders longer than 259 characters are found and set up like any other game. Some games still cannot start from a long path. They are listed under ACTION REQUIRED with the short folder name to use.
- **Startup files.** Some emulators need files before a game can start: PlayStation 3 firmware (RPCS3), PCSX2x6 firmware, Chihiro (CxbxR) firmware, and a settings file for each Play! game. A missing file shows up in ACTION REQUIRED. In a normal run, TeknoParrot Manager then offers to copy the files from your own game collection after checking them against the Eggman DAT list. It never downloads them. See [[Game Startup Files]].
- **Games that come as a set of ZIPs.** Some games (System 11 games, for example) name two ZIPs: the game's own ZIP and a parent ZIP. A game like this is registered only when both ZIPs are in the same folder. A folder that holds only the parent ZIP does not register the game. Put both ZIPs in one folder, then run again. If a System 11 game also needs a disc image (`.chd`), it is chosen for you when exactly one is there. When there are several, none is guessed.
- **System 11 saved files.** In a normal run, if a registered System 11 game has no saved files yet, you are offered an optional step to copy them from your own saved-files set. See [[Game Startup Files]].

---

## After registration

Next, TeknoParrot Manager goes through these steps. Each one asks first:

1. **Repair game paths.** `Check for and repair broken game paths now? (Y/N)` fixes games whose saved path points to a missing file.
2. **Pictures.** `Download the missing game pictures? (Y/N, D = use your own pictures)` fetches small icons from the TeknoParrotUIThumbnails project on GitHub. It never downloads games, and never replaces an icon you already have. A missing icon does not mean the game is unsupported. To use your own pictures, put `ProfileCode.png` files in `<your TeknoParrot folder>\TeknoParrotManager\Assets\CustomThumbnails\`.
3. **Controls.** `Copy controls from N games to your other games of the same type? (Y/N, D = details)` -- see [[Propagate Controls]].

---

## LaunchBox

At the end of a normal run (not a preview), TeknoParrot Manager offers to add your games to LaunchBox. You can preview first (`P`), add the missing games after a backup (`A`), fill in game details and make playlists (`G`), group regions and versions of a game into one (`V`), keep LaunchBox in step with TeknoParrot (`S`), link games for art and details (`L`), fill in players and controllers for Big Box (`C`), get an import file only (`F`), or skip (`B`). It never closes LaunchBox for you. See [[LaunchBox Integration]].

---

## ACTION REQUIRED list

At the end, TeknoParrot Manager prints a list of what needs your attention and saves it as `TeknoParrot-Manager-ActionItems.txt` in `<your TeknoParrot folder>\TeknoParrotManager\Reports\`. A Save window lets you choose another place. A preview saves nothing.

<details><summary>Details: the sections of the list</summary>

| Section | Meaning |
|---|---|
| Register these games in TeknoParrotUI | Games it could not pick a profile for, or whose only matching profile is used by another folder. Add each one yourself in TeknoParrotUI. |
| Fix these game paths in TeknoParrotUI | Broken paths it could not fix. |
| Extract these games first, then re-run repair | Profiles whose game is not unzipped yet. Use AutoSync, then run again. |
| Controls skipped by design | Games whose control type has no usable example game yet. Nothing failed. Set up one game of that type yourself, then copy controls. This is shown (and saved) even when it is the only thing left. |
| Game folders not matched to a TeknoParrot profile | Folders that match no profile. Update TeknoParrot, open TeknoParrotUI once, then run Register again. They may be games TeknoParrot does not support yet, tools, or games whose main file is named differently than TeknoParrot expects. |
| Path too long -- these games may fail to launch | Raw Thrills games and Yu-Gi-Oh! Duel Terminal 6 have a short path limit. It shows the folder name to use. |
| File version mismatch -- these games need a specific older file | BlazBlue games (`iDmacDrv32.dll`) and Tekken Tag Tournament 2 (`EBOOT.BIN`) need an older file. It shows the file name and the checksums. |
| Known GPU incompatibility -- no fix available | Games known not to work on your AMD or Intel graphics card. For your information only. |
| Additional informational game notes | Games with setup notes from the community list. It also shows the guide's setup steps (for example which ZIP or disc file to select), graphics card notes, extra files, the extra archives a game needs (bring your own copy; none is downloaded), a linked profile (the same game with another setup) and a game the guide lists as broken or only partly working. Nothing in it is applied for you. The notes are saved in `Reports\TeknoParrot-Manager-game-notes.txt`. |
| Startup files (firmware) | Games whose emulator is missing startup files. See above. |
| Controls not ready | Games whose controls are missing, not verified, unsupported or unknown. Open TeknoParrot's controls screen and set them up and test them. |

</details>

---

## Controls status file

After every real run, TeknoParrot Manager saves `TeknoParrot-Manager-controls.txt` in the same `Reports` folder. It lists every registered game with its profile code, control type, how many buttons are set, and where the controls came from. A preview leaves it alone. Open it when a game misbehaves.

---

## How games are matched

<details><summary>Details</summary>

TeknoParrot Manager first matches the game's program file name to the profiles. For games that share a file name (for example `game.exe`), it then uses the Eggman DAT list, and last it compares the folder name with the profile names. The folder name is compared with the year, version and region parts removed.

A close match (score 0.72 or higher, and clearly better than the next one) is registered and shown as `fuzzy`. Anything less sure goes to ACTION REQUIRED with its best guess.

If a match is wrong, open TeknoParrotUI and set the right profile and game file for that game. The `forceArchetype` setting in the overrides file only changes which game controls are copied from. It does not change registration.

The DAT list is set up at first start (see [[Setup]]). TeknoParrot Manager never saves it inside your TeknoParrot folder.

</details>
