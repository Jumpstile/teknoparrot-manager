# AutoSync

AutoSync compares the Eggman/RomVault DAT list with local folders and helps register or extract TeknoParrot games.

## Extracted-Folder Detection

AutoSync now uses the shared `Resolve-ExtractedGameFolder` resolver before showing a game as available to extract.

Match order:

1. Exact and normalized folder name.
2. RetroBat suffix-aware matches: `.teknoparrot`, `.parrot`, `.game`.
3. DAT/profile-code identity when available.
4. Known short-name aliases for Raw Thrills and path-length-sensitive games.
5. Already registered profile paths.
6. Date/version/region-normalized exact match using the same normalized-key mechanism, not a separate fuzzy similarity tier.

## Safety Rules

- On first setup, TPM derives a staging-folder default from the configured
  TeknoParrot location. Enter accepts it; B opens the browser for another path.
- A staging path must not be inside or contain TeknoParrot, either ZIP source,
  or the TPM program/package folder. Typed and browsed recovery choices use the
  same symmetric containment check before they are saved or used.
- TPM creates a missing staging directory only after a real AutoSync run is
  selected. Preview/Dry Run does not create it.
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
