# Game support

This page says, game by game, what TeknoParrot Manager does for the games in the Eggman guide and in the TeknoParrot catalog it was checked against. The numbers are made by a tool (`scripts\New-TpmGameCoverage.ps1`), not typed by hand.

## What the words mean

- **Applied**: TeknoParrot Manager applies a reviewed fix for the game (see Required game patches).
- **Checked**: TeknoParrot Manager checks something and warns you (path too long, a pinned file, a graphics card that does not work, emulator startup files).
- **Guided**: the guide has steps for the game. TeknoParrot Manager puts them in your Game Notes file. You do the steps.
- **Handled**: the guide has nothing for the game that TeknoParrot Manager must do. TeknoParrot does the work.
- **Gap**: TeknoParrot has no game profile for this guide entry, so there is nothing to register. The row says exactly what is missing.

## Totals

2553 game IDs in all: 1607 guide games, 858 guide versions (other ROM revisions of a game), and 88 catalog profiles that the guide does not list.

| Applied | Checked | Guided | Handled | Gap |
|---|---|---|---|---|
| 54 | 157 | 2238 | 95 | 9 |

The catalog used is TeknoParrot 1.0.0.2334 with 2544 game profiles. 9 guide IDs have no profile in it; those are the Gap rows. 65 guide entries have supplementary archives that TeknoParrot Manager never downloads.

## By emulator

| Emulator (loader) | Game IDs | In catalog | Applied | Checked | Guided | Handled | Gap |
|---|---|---|---|---|---|---|---|
| TeknoCPS (ROM) | 641 | 641 | 0 | 0 | 627 | 14 | 0 |
| TeknoNaomi (ROM) | 349 | 349 | 0 | 0 | 349 | 0 | 0 |
| TeknoParrot | 339 | 339 | 45 | 31 | 240 | 23 | 0 |
| TeknoMVS (ROM) | 287 | 287 | 0 | 0 | 284 | 3 | 0 |
| TeknoS11 (ROM) | 230 | 230 | 0 | 0 | 194 | 36 | 0 |
| ElfLdr2 | 117 | 117 | 7 | 39 | 66 | 5 | 0 |
| TeknoSTV (ROM) | 69 | 69 | 0 | 0 | 69 | 0 | 0 |
| TeknoSS32 (ROM) | 67 | 67 | 0 | 0 | 61 | 6 | 0 |
| pcsx2x6 | 47 | 47 | 0 | 47 | 0 | 0 | 0 |
| TeknoModel2 (ROM) | 36 | 36 | 0 | 0 | 35 | 1 | 0 |
| TeknoModel3 (ROM) | 25 | 25 | 0 | 0 | 25 | 0 | 0 |
| TeknoVegas (ROM) | 24 | 24 | 0 | 0 | 24 | 0 | 0 |
| TeknoTZ (ROM) | 22 | 22 | 0 | 0 | 22 | 0 | 0 |
| RPCS3 | 19 | 19 | 0 | 19 | 0 | 0 | 0 |
| TeknoCoJag (ROM) | 19 | 19 | 0 | 0 | 19 | 0 | 0 |
| TeknoTJC (ROM) | 19 | 19 | 0 | 0 | 19 | 0 | 0 |
| TeknoS22 (ROM) | 18 | 18 | 0 | 0 | 18 | 0 | 0 |
| Lindbergh | 17 | 17 | 2 | 3 | 12 | 0 | 0 |
| TeknoPsikyo (ROM) | 17 | 17 | 0 | 0 | 17 | 0 | 0 |
| cxbxr | 14 | 14 | 0 | 14 | 0 | 0 | 0 |
| TeknoEagle (ROM) | 12 | 12 | 0 | 0 | 12 | 0 | 0 |
| TeknoS23 (ROM) | 12 | 12 | 0 | 0 | 12 | 0 | 0 |
| TeknoHornet (ROM) | 10 | 10 | 0 | 0 | 10 | 0 | 0 |
| TeknoViper (ROM) | 10 | 10 | 0 | 0 | 10 | 0 | 0 |
| Dolphin | 9 | 9 | 0 | 0 | 3 | 6 | 0 |
| TeknoHDrive (ROM) | 9 | 9 | 0 | 0 | 9 | 0 | 0 |
| TeknoM2 (ROM) | 9 | 9 | 0 | 0 | 9 | 0 | 0 |
| TeknoRender0 (ROM) | 9 | 9 | 0 | 0 | 9 | 0 | 0 |
| (none) | 8 | 0 | 0 | 0 | 0 | 0 | 8 |
| TeknoS21 (ROM) | 8 | 8 | 0 | 0 | 8 | 0 | 0 |
| TeknoHNG64 (ROM) | 7 | 7 | 0 | 0 | 7 | 0 | 0 |
| TeknoMacaw | 7 | 7 | 0 | 0 | 7 | 0 | 0 |
| TeknoTZero (ROM) | 7 | 7 | 0 | 0 | 7 | 0 | 0 |
| TeknoG4 (ROM) | 6 | 6 | 0 | 0 | 6 | 0 | 0 |
| TeknoModel1 (ROM) | 6 | 6 | 0 | 0 | 6 | 0 | 0 |
| TeknoFL (ROM) | 5 | 5 | 0 | 0 | 5 | 0 | 0 |
| TeknoVP (ROM) | 5 | 5 | 0 | 0 | 5 | 0 | 0 |
| TeknoZeus (ROM) | 5 | 5 | 0 | 0 | 5 | 0 | 0 |
| Play | 4 | 4 | 0 | 4 | 0 | 0 | 0 |
| TeknoG3D (ROM) | 4 | 4 | 0 | 0 | 4 | 0 | 0 |
| TeknoGClub (ROM) | 4 | 4 | 0 | 0 | 4 | 0 | 0 |
| TeknoVUnit (ROM) | 4 | 4 | 0 | 0 | 4 | 0 | 0 |
| Tekno3DO (ROM) | 3 | 3 | 0 | 0 | 3 | 0 | 0 |
| SegaTools | 2 | 2 | 0 | 0 | 2 | 0 | 0 |
| TeknoAir (ROM) | 2 | 2 | 0 | 0 | 2 | 0 | 0 |
| TeknoCobra (ROM) | 2 | 2 | 0 | 0 | 2 | 0 | 0 |
| TeknoPNet (ROM) | 2 | 2 | 0 | 0 | 2 | 0 | 0 |
| TeknoTPJC (ROM) | 2 | 2 | 0 | 0 | 2 | 0 | 0 |
| Standalone | 1 | 0 | 0 | 0 | 0 | 0 | 1 |
| TeknoAGX (ROM) | 1 | 1 | 0 | 0 | 1 | 0 | 0 |
| TeknoGRE (ROM) | 1 | 1 | 0 | 0 | 1 | 0 | 0 |
| TeknoMagic (ROM) | 1 | 1 | 0 | 0 | 0 | 1 | 0 |

## What you do

- **PC games and other emulators**: register with TeknoParrot Manager, read your Game Notes file, then set up the controls in TeknoParrot.
- **ROM games (marked ROM)**: the guide asks you to pick the exact ZIP it names, keep the BIOS ZIP in the same folder, pick the matching game revision, and for some games pick a CHD file as a second game file. TeknoParrot Manager sets the game file when a catalog profile exists, shows these steps in the Game Notes file, and reports in Library Health (Game support) when a second game file is missing.
- **Gap rows**: guide entries that have no TeknoParrot profile of their own. Seven are extra archives that TeknoParrot has no profile for at all (the Sega Rally 3 track mods and Escape from Monster Manor); TeknoParrot Manager lists their folders as "not in TeknoParrot" and does not call that a failure. Two (Battle Gear 3 and Wayne Gretzky's 3D Hockey Fatality Edition) run through a linked profile.
- **Second profile not written**: four games (House of the Dead 4, Raiden III, Raiden IV and Densha de GO) have a first profile that TeknoParrot Manager registers, and the guide also names a second profile for them. The guide does not say what that second profile is for, so TeknoParrot Manager does not write it. These four are not Gap rows. They stay on this page so they are not forgotten. (The one exception is a game whose first profile TeknoParrot has retired: its second profile is written when the game folder has the file that profile starts.)
- **Profiles the guide does not list**: 88 TeknoParrot profiles have no guide entry. TeknoParrot Manager registers them like any other game. There are no guide steps to show for them.

## Details (for testers)

Run `scripts\New-TpmGameCoverage.ps1 -GuidePath <guide page or game-data JSON> -SnapshotManifestPath <snapshot-manifest.json> -ProfilesDir <saved profile XML folder> -OutputDir <folder> -MarkdownPath docs\GAME-SUPPORT.md`. The tool writes one row per game ID with its loader, what the guide says, and the exact missing data for each gap. Guide text is only read, never run. A refresh is needed whenever the guide, the catalog snapshot or the reviewed recipe list changes.
