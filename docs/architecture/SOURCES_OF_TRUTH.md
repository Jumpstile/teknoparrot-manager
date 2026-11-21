# Sources of truth

TeknoParrot Manager already holds several lists that describe the same games. This page says what each one is good for, so a new feature uses them instead of reading the same data again.

| Source | What it knows | Where it comes from | Trust |
| --- | --- | --- | --- |
| Eggman DAT list | Exact folder and file names, sizes and hashes, game name, year, hardware, and the profile code of each game | The Eggman collection download | Highest for "what is in this folder" |
| Game folder on disk | A folder name | The player's games folder | Only counts when the DAT list confirms the folder |
| TeknoParrot metadata | Game name, year, hardware text, genre | `Metadata\<code>.json` | High for the name TeknoParrot uses |
| TeknoParrot game profiles | Profile code, name, executable name, game path, input settings | `GameProfiles` and `UserProfiles` | High for what the profile runs |
| LaunchBox game list | Official game names, year, developer, publisher, alternate names | `Metadata\LaunchBox.Metadata.db` | The target the others are matched to |
| LaunchBox title | What the player or an import typed | The platform file | Lowest; a typed name is a hint only |

## The matching engine

One section of the script, "TPM GAME MATCHING ENGINE", answers "which game is this" for every feature (titles, Games Database IDs, year and developer, playlists, grouping, pictures). The functions only read; nothing in them writes. Do not write a second matcher.

`Get-TpmProfileMatchSubject` reads one profile, its TeknoParrot metadata and the Eggman list entries for its profile code into a subject: the names to look up and the facts to check them with (year, hardware maker). `Resolve-TpmGameMatch` looks the subject up in the LaunchBox game list one level at a time and stops at the first level that is certain.

| Level | What counts | Certain by itself? |
| --- | --- | --- |
| 1 | The same name. Accents, capitals, punctuation, "&" and release tags (region, version, board code) are ignored. | Yes |
| 2 | The same name spelled a little differently: Roman numerals, "the", "Ver.", an "Arcade" or "Edition" tail. | Yes |
| 3 | A name worked out from the given one: a note, "A / B" sides, a trailing "1", a point revision, an extra name in brackets, an alternate name in the game list, the brand word "Live". | Only when a second source, the hardware maker or the year backs it up |
| 4 | Only a close name. | Never; it is a suggestion for the user |

The outcomes are `Certain`, `Ambiguous` (the user decides, with the possible games listed), `NoMatch` and `NotGame`. Every answer carries a plain `Reason` for the screen and an `Evidence` trail for Details and the log.

Rules the engine keeps:

- A different year or number is a different game ("Golden Tee Live 2020" is not "2022"). A version is not part of the game, unless the list names that version as its own game.
- The emulator named in a title ("ElfLoader 2") is never part of the game name.
- A game folder is a source only when the Eggman list confirms it: the folder name is the exact name of a list game for this profile code, and the file the profile starts is the file the list names in that folder (`Get-TpmConfirmedDatName`). It then picks the one list game of a code that has several.
- Another name in brackets in an Eggman name ("Aero Fighters 2 (Sonic Wings 2)") and the title typed in LaunchBox are weak names: used only when nothing else matches.
- Two games with one name (also on another platform, or "Frogger" next to "Frogger (Raw Thrills)") are told apart by the release year and the hardware maker. When they cannot be told apart the user decides.
- The same name with release years far apart, or years apart and a developer that does not fit, may be another game. The user decides, unless the hardware is a re-release platform (NESiCAxLive, G-NET) that explains the gap.
- When the match is certain the engine returns the game list's own year and developer to fill in; otherwise the year and maker from the Eggman list and TeknoParrot.
- Firmware updaters, drive checkers, controllers and boards (a NAOMI DIMM firmware updater, "AS-1 Controller") are `NotGame`. They are never matched and never added to LaunchBox. TeknoParrot's genre "Utility" says the same.

## Evidence

`scripts\Invoke-TpmMatchEvidence.ps1` runs the engine over every profile in a TeknoParrot folder with the Eggman list, the folder names and a copy of the LaunchBox game list, and writes one report: totals per outcome, every ambiguous case, every no-match, a spot-check list with both names side by side, warnings for certain matches whose names look different, and a comparison with the links LaunchBox itself made. Run it again after any change to the engine and read the warnings; a wrong certain match is a bug.

## Rules for new features

- Reuse these readers. Do not read the same file a second time in a new way.
- A game folder is used as evidence only when the DAT list confirms it.
- Reads first; every write needs a preview, approval, a backup and an undo.
- Keep the result labeled by source, so the screen can say why.
