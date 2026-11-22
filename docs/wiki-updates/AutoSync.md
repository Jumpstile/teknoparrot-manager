# AutoSync (menu 1)

AutoSync unzips your game ZIP files into your games folder, then registers the games with TeknoParrot. Use it when your games are stored as ZIP files, for example on a NAS or a big drive.

If your games are already unzipped, use [[Register]] (menu 2) instead.

---

## How to run it

1. Start TeknoParrot Manager and type `1` at the main menu.
2. Choose `P` (preview, the default), `R` (run now) or `B` (back). See "Preview / dry-run mode" below.
3. If AutoSync does not know your game ZIP folder yet, it asks for it. Pick the folder that holds your `.zip` files directly, not a folder above it.
4. Choose the games to unzip (see "Choosing games").
5. AutoSync backs up your `UserProfiles` folder, unzips the games, then registers them. See [[Register]] for what happens next.

---

## Preview / dry-run mode

Every run starts with this choice:

```
  [P] Preview (default) -- show what would change; no game or profile changes
  [R] Run now -- back up UserProfiles first, then make the changes
  [B] Back
```

A preview shows which games would be unzipped and why (new, changed ZIP, and so on). It writes nothing: no backup, no folders, no profiles.

When the preview ends, you are asked if you want to make the changes for real. Answer `Y` and TeknoParrot Manager scans again first, so nothing is out of date. Answer `N` and nothing changes.

---

## What AutoSync does to games you already unzipped

- **ZIP did not change:** the game folder is left alone. Your saves and settings stay as they are. You see `Already extracted (ZIP unchanged)`.
- **ZIP changed:** the game folder is replaced with the new one. Before that, every file in the old folder that is extra or different from the ZIP (saves, settings, ReShade files) is copied to `<your TeknoParrot folder>\TeknoParrotManager\Backups\AutoSyncReplaced\<game>_<date and time>\`.
- **Those files cannot be saved, or no Backups folder is set up:** that game is not updated, and nothing is changed for it. You see `This game was not updated`. Other games continue. Fix the Backups folder or free some space, then run AutoSync again.

If AutoSync extracts nothing new, registration is skipped and you see one short note: `Nothing new was extracted, so registration was skipped. To register games already extracted, choose Register only.` It is only a note. It is not under ACTION REQUIRED and does not send you to a saved list.

<details><summary>Details</summary>

- A game is unzipped again if its ZIP changed, the folder is missing, or an earlier unzip was cut short (a `.extracting` marker file stays next to the folder until the unzip is finished).
- Files whose names start with `!TeknoParrot Collection` (notes, changelog) are never unzipped.
- A ZIP with unsafe file paths is refused before anything is written.
- If two ZIPs in one run would write to the same game folder, only the first one is used.
- The list of what was unzipped is kept in `TeknoParrot-Manager.syncstate.json` in your games folder.
- In the overrides file (`TeknoParrot-Manager.overrides.json`, next to the script), `noSync` skips games and `onlySync` limits AutoSync to the games you list.

</details>

---

## Games folder rules

Your games folder (also called the staging folder) must:

- Be outside your TeknoParrot folder, outside the TeknoParrot Manager folder, and outside every ZIP folder.
- Have enough free space. AutoSync warns you if the drive has less than about 1.5 times the size of your ZIPs, and asks before it goes on.

A local drive is best, for example `D:\TeknoParrotGames`. A network drive is allowed. TeknoParrot Manager then measures its write speed, warns you if it is slow, and asks if you want to continue.

On first setup TeknoParrot Manager suggests a safe folder. Press Enter to take it, or `B` to browse.

---

## Second ZIP folder (optional)

If you keep some games apart from your main collection, you can add a second ZIP folder. AutoSync asks for it (`Path (or press Enter to skip)`) until you set one. Point it directly at the folder with the `.zip` files. Both folders are shown in one list, and games from the second one are marked `[+]`. A game that is in both folders is listed once.

Both folders unzip into the same games folder. If the second folder overlaps the games folder, or is inside your TeknoParrot folder, AutoSync skips it and says why.

To change or remove a folder, answer `N` to `Use these settings?` when TeknoParrot Manager starts, then run AutoSync again.

---

## Choosing games

AutoSync hides games that are already unzipped and shows how many are left. Then it asks you to choose:

| Key | What it does |
|---|---|
| `A` | All games that are not unzipped yet |
| `L` | Browse the list (A to Z, 20 at a time) |
| `S` | Search by part of a name |
| `D` | Done -- go on with the games you picked |
| `B` | Back -- cancel, nothing is changed |

`D` with nothing picked does nothing (`No games are queued`). In the list, type numbers or ranges such as `1,3,5-7`; `N` and `P` change page. Picked games show a `*`.

---

## Progress and interrupted unzips

A progress bar shows each game while it unzips. If a run stops in the middle (power loss, disk error, Ctrl+C), the next run notices and unzips that game again from the start.

---

## RetroBat / Batocera folder names

During first setup you are asked `Use RetroBat folder naming? (Y/N, default N)`. With `Y`, new game folders are named `GameName.teknoparrot`. Folders you already have are recognized (including `.parrot` and `.game` endings) and are not unzipped a second time.

<details><summary>Details</summary>

To decide that a ZIP is already unzipped, AutoSync tries these in order: the exact or cleaned-up folder name, the RetroBat endings, the game code from the Eggman DAT list or an existing profile, known short names (Raw Thrills games and other games with path limits), and finally a match on name with date, version and region ignored. This only stops duplicate unzipping. It never deletes, renames or moves a folder.

</details>

---

## Already have games, or use RetroBat with a mouse and keyboard?

You do not have to delete, move or reset anything first. Pick your TeknoParrot folder and the folder that holds your games, then run **Register only**. It adds the games TeknoParrot does not know yet and asks before it fixes a broken game path. It does not delete your game folders.

RetroBat mode only changes the folder names TeknoParrot Manager makes. It does not change RetroBat. TeknoParrot runs the games and keeps each game's controls and input type; RetroBat keeps its own list and starts games its own way.

TeknoParrot Manager does not set up mouse or keyboard input. Set one game's controls in TeknoParrotUI (RawInput is the mouse and keyboard type), start it from TeknoParrot first, then use [[Propagate Controls]] for the others and test one game. Starting from TeknoParrot and from RetroBat are two different ways to start a game, and TeknoParrot Manager cannot tell you why one works and the other does not. It does not detect or set up Sinden lightguns.

---

## After unzipping

AutoSync goes straight on to registration. See [[Register]].

When new games were unzipped, you are asked `Choice (N/A/B)`. `N` (the default) checks only the new games and skips the whole-library steps. `A` goes on to the repair, pictures and controls steps for all your games. `B` goes back to the menu.

At the end, the ACTION REQUIRED list tells you if a game's controls are missing, not verified, unsupported or unknown. A game can be registered and still need its controls set up. Open TeknoParrot's controls screen, map the controls and test them before you call the game ready. TeknoParrot Manager does not write any control mappings in this step. See [[Propagate Controls]] to copy controls from a game you already set up.
