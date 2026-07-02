# AutoSync

AutoSync compares the Eggman/RomVault DAT list with local folders and helps register or extract TeknoParrot games.

## Extracted-Folder Detection

AutoSync now uses the shared `Resolve-ExtractedGameFolder` resolver before showing a game as available to extract.

Match order:

1. Exact and normalized folder name.
2. RetroBat suffix-aware matches: `.teknoparrot`, `.parrot`, `.game`.
3. Known short-name aliases for Raw Thrills and path-length-sensitive games.
4. DAT/profile-code identity when available.
5. Already registered profile paths.
6. Conservative fuzzy metadata matching for harmless title, date, and version differences.

## Safety Rules

- Existing folders are never deleted, renamed, or moved automatically.
- The resolver is used only to suppress duplicate extraction prompts.
- A folder is treated as already extracted only when it exists and contains files.
- Existing backup and path-safety behavior remains unchanged.

## Issue #66 Coverage

Regression coverage includes:

- `ALIENS.teknoparrot` recognized for Aliens Armageddon.
- `Battle Gear 3 (2.08J)(2003-04-11)[Namco System 246][TP].teknoparrot` matched against the DAT/list entry `Battle Gear 3 (2.08J)(2002)[Namco System 246][TP]`.
- Negative cases where similarly named games must not be confused.

The full reported 25-title list still requires reporter confirmation against local data.
