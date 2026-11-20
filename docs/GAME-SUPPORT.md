# Game support

This page says, game by game, what TeknoParrot Manager does for the games in the Eggman guide and in the TeknoParrot catalog it was checked against. The numbers are made by a tool (`scripts\New-TpmGameCoverage.ps1`), not typed by hand.

## What the words mean

- **Applied**: TeknoParrot Manager applies a reviewed fix for the game (see Required game patches).
- **Checked**: TeknoParrot Manager checks something and warns you (path too long, a pinned file, a graphics card that does not work, emulator startup files).
- **Guided**: the guide has steps for the game. TeknoParrot Manager puts them in your Game Notes file. You do the steps.
- **Handled**: the guide has nothing for the game that TeknoParrot Manager must do. TeknoParrot does the work.
- **Gap**: TeknoParrot Manager cannot register the game yet. The row says exactly what is missing.

## Totals

2395 game IDs in all: 1510 guide games, 832 guide versions (other ROM revisions of a game), and 53 catalog profiles that the guide does not list.

| Applied | Checked | Guided | Handled | Gap |
|---|---|---|---|---|
| 54 | 142 | 662 | 67 | 1470 |

The catalog used is TeknoParrot 1.0.0.2128 with 925 game profiles. 1470 guide IDs have no profile in it; those are the Gap rows. 64 guide entries have supplementary archives that TeknoParrot Manager never downloads.

## By emulator

| Emulator (loader) | Game IDs | In catalog | Applied | Checked | Guided | Handled | Gap |
|---|---|---|---|---|---|---|---|
| TeknoCPS (ROM) | 627 | 0 | 0 | 0 | 0 | 0 | 627 |
| TeknoNaomi (ROM) | 349 | 0 | 0 | 0 | 0 | 0 | 349 |
| TeknoParrot | 335 | 323 | 45 | 28 | 232 | 18 | 12 |
| TeknoMVS (ROM) | 284 | 0 | 0 | 0 | 0 | 0 | 284 |
| TeknoS11 (ROM) | 194 | 194 | 0 | 0 | 194 | 0 | 0 |
| ElfLdr2 | 101 | 94 | 7 | 27 | 58 | 2 | 7 |
| TeknoSTV (ROM) | 69 | 0 | 0 | 0 | 0 | 0 | 69 |
| TeknoSS32 (ROM) | 61 | 0 | 0 | 0 | 0 | 0 | 61 |
| pcsx2x6 | 47 | 47 | 0 | 47 | 0 | 0 | 0 |
| (not in guide) | 38 | 38 | 0 | 0 | 0 | 38 | 0 |
| TeknoModel2 (ROM) | 34 | 34 | 0 | 0 | 34 | 0 | 0 |
| TeknoModel3 (ROM) | 25 | 0 | 0 | 0 | 0 | 0 | 25 |
| TeknoVegas (ROM) | 24 | 24 | 0 | 0 | 24 | 0 | 0 |
| RPCS3 | 19 | 19 | 0 | 19 | 0 | 0 | 0 |
| TeknoS22 (ROM) | 18 | 18 | 0 | 0 | 18 | 0 | 0 |
| Lindbergh | 17 | 17 | 2 | 3 | 12 | 0 | 0 |
| cxbxr | 14 | 14 | 0 | 14 | 0 | 0 | 0 |
| TeknoS23 (ROM) | 12 | 12 | 0 | 0 | 12 | 0 | 0 |
| TeknoHornet (ROM) | 10 | 10 | 0 | 0 | 10 | 0 | 0 |
| TeknoViper (ROM) | 10 | 8 | 0 | 0 | 8 | 0 | 2 |
| Dolphin | 9 | 9 | 0 | 0 | 3 | 6 | 0 |
| TeknoHDrive (ROM) | 9 | 0 | 0 | 0 | 0 | 0 | 9 |
| TeknoM2 (ROM) | 9 | 9 | 0 | 0 | 9 | 0 | 0 |
| (none) | 8 | 0 | 0 | 0 | 0 | 0 | 8 |
| TeknoS21 (ROM) | 8 | 8 | 0 | 0 | 8 | 0 | 0 |
| TeknoHNG64 (ROM) | 7 | 7 | 0 | 0 | 7 | 0 | 0 |
| TeknoMacaw | 7 | 7 | 0 | 0 | 7 | 0 | 0 |
| TeknoTZero (ROM) | 7 | 0 | 0 | 0 | 0 | 0 | 7 |
| TeknoG4 (ROM) | 6 | 0 | 0 | 0 | 0 | 0 | 6 |
| TeknoModel1 (ROM) | 6 | 6 | 0 | 0 | 6 | 0 | 0 |
| TeknoZeus (ROM) | 5 | 5 | 0 | 0 | 5 | 0 | 0 |
| Play | 4 | 4 | 0 | 4 | 0 | 0 | 0 |
| TeknoGClub (ROM) | 4 | 4 | 0 | 0 | 4 | 0 | 0 |
| TeknoVUnit (ROM) | 4 | 4 | 0 | 0 | 4 | 0 | 0 |
| OpenParrot | 3 | 3 | 0 | 0 | 0 | 3 | 0 |
| SegaTools | 2 | 2 | 0 | 0 | 2 | 0 | 0 |
| TeknoAir (ROM) | 2 | 2 | 0 | 0 | 2 | 0 | 0 |
| TeknoCobra (ROM) | 2 | 2 | 0 | 0 | 2 | 0 | 0 |
| TeknoTPJC (ROM) | 2 | 0 | 0 | 0 | 0 | 0 | 2 |
| Standalone | 1 | 0 | 0 | 0 | 0 | 0 | 1 |
| TeknoAGX (ROM) | 1 | 1 | 0 | 0 | 1 | 0 | 0 |
| TeknoMagic (ROM) | 1 | 0 | 0 | 0 | 0 | 0 | 1 |

## What you do

- **PC games and other emulators**: register with TeknoParrot Manager, read your Game Notes file, then set up the controls in TeknoParrot.
- **ROM games (marked ROM)**: the guide asks you to pick the exact ZIP it names, keep the BIOS ZIP in the same folder, pick the matching game revision, and for some games pick a CHD file as a second game file. TeknoParrot Manager sets the game file when a catalog profile exists, shows these steps in the Game Notes file, and reports in Library Health (Game support) when a second game file is missing.
- **Gap rows**: TeknoParrot Manager has no profile to register, so these games cannot be set up with it yet.

## Details (for testers)

Run `scripts\New-TpmGameCoverage.ps1 -GuidePath <guide page or game-data JSON> -SnapshotManifestPath <snapshot-manifest.json> -ProfilesDir <saved profile XML folder> -OutputDir <folder> -MarkdownPath docs\GAME-SUPPORT.md`. The tool writes one row per game ID with its loader, what the guide says, and the exact missing data for each gap. Guide text is only read, never run. A refresh is needed whenever the guide, the catalog snapshot or the reviewed recipe list changes.
