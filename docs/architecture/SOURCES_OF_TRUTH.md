# Sources of truth

TeknoParrot Manager already holds several lists that describe the same games. This page says what each one is good for, so a new feature uses them instead of reading the same data again.

| Source | What it knows | Where it comes from | Trust |
| --- | --- | --- | --- |
| Eggman DAT list | Exact folder and file names, sizes and hashes, game name, year, hardware | The Eggman collection download | Highest for "what is in this folder" |
| Game folder on disk | A folder name | The player's games folder | Only counts when the DAT list confirms the folder |
| TeknoParrot metadata | Game name, year, hardware text | `Metadata\<code>.json` | High for the name TeknoParrot uses |
| TeknoParrot game profiles | Profile code, executable name, game path, input settings | `GameProfiles` and `UserProfiles` | High for what the profile runs |
| MAME list in LaunchBox | Romset name and game name | `Metadata\MAME.xml` | High for arcade board games |
| LaunchBox game list | Official game names, year, developer, publisher, alternate names | `Metadata\LaunchBox.Metadata.db` | The target the others are matched to |
| LaunchBox title | What the player or an import typed | The platform file | Lowest; a typed name is a hint only |

## Matching a game to the LaunchBox game list

The functions live in one marked section of the script (`Get-TpmGamesDbPick`, `Resolve-TpmGamesDbMatch`, `Get-TpmLinkEvidence`). They only read; nothing in them writes.

1. Each source gives a name. The sources are the TeknoParrot name, the Eggman list name and the MAME list name. The title typed in LaunchBox is used only when no other source has a name. The raw name is tried first, then a cleaned one: notes such as "(USA, Sep 22 1997)", a trailing version and "for NESiCAxLive" are removed.
2. Each name is looked up in the game list. Spelling differences that do not change the game are ignored: accents, "&" and "and", Roman numerals (II = 2), small words such as "the" and "of", and tails such as "Arcade" or "Edition". An exact name is one hit. If two games share one name, a "(year)" tag, the release year or the exact spelling can break the tie. A code before a colon ("P4U: Name") and the sides of "A / B" (two or more words each) are also tried.
3. A name with no exact hit is scored against the closest names: words that differ, the year (when both sides have one) and the maker. A close name counts as firm only with a clear lead over the next one. A number is part of the game: a name whose numbers differ from the title's ("2020" and "2022", "4" and "5") is never a candidate, so a missing sequel shows as no match instead of a wrong one.
   - A version is not part of the game. "Ver. 2", "Version 3" and a dotted tail such as "1.18" are ignored, unless the list names that version as its own game (then the exact name wins). A dotted tail like "5.1" in "Tekken 5.1" stays, because fewer than three words come before it.
   - A name that contains the other one word for word, in the same order and with the same numbers ("Dino King Battle: King of Jurassic" and "Dino King Battle"), is offered to the player, never applied by itself.
   - A region word before a release note, as in "Cobra: The Arcade World (CBR2 Ver. B)", is not part of the name. A plain "... World" with no release note is a game of its own.
   - "+" reads as "plus", "Vs." as "versus", and a source whose whole name is a region word is ignored.
   - A few well-known regional names of one game (for example "Street Fighter Zero") are listed by hand.
4. The sources are compared:
   - Exact names from every source point at one game, and no firm close name points elsewhere: linked without asking.
   - Anything else with a candidate: the player decides. A close name is never applied without approval.
   - When most sources agree exactly and one disagrees, the one that disagrees is set aside and the log says so. A one-against-one tie is never settled by guessing.
   - A more specific name beats a generic one (for example, a "for NESiCAxLive" tail is fine, other extra words wait for approval).
   - A hopeless match (almost no words in common) is shown as no match at all.
5. Every decision keeps the names it rested on. They go in the log, so Details can show them.
6. The same engine answers every question of "which game is this" in the Manager, including the title offered when a game is added to LaunchBox (`Resolve-TpmGameTitle` is a thin layer over it). Do not write a second matcher.

## Things that are not games

Firmware updaters, drive checkers and boards (for example a NAOMI firmware updater) are never added to LaunchBox. They are skipped, and the log says why.

## Rules for new features

- Reuse these readers. Do not read the same file a second time in a new way.
- A game folder is used as evidence only when the DAT list confirms it.
- Reads first; every write needs a preview, approval, a backup and an undo.
- Keep the result labeled by source, so the screen can say why.
