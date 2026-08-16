# Check for Updates

TeknoParrot Manager includes a manual, backup-first update check.

## Menu Entry

- Main menu option: `13. Check for Updates`
- Exit remains a separate menu option.
- The menu entry reuses the hardened updater helper instead of duplicating update logic in the main script.

## Safety Model

- The updater checks GitHub Releases only.
- It never applies an update without explicit confirmation.
- It backs up the current script before replacement.
- It downloads the release ZIP to a temporary location before extracting it.
- It validates the extracted `TeknoParrot-Manager.ps1` before replacement.
- After a successful update, it tells the user to restart and does not continue running the updated script in the same session.

## Validation

The replacement script must:

- exist,
- be non-empty,
- contain the `TeknoParrot Manager` marker,
- contain a `$ScriptVersion = "..."` assignment, and
- not begin with raw ZIP `PK` bytes.

## Download audit scope

The update package is logged with its GitHub release source, filename/version
when known, computed SHA-256, and transfer metrics. The menu update path does
not consume an optional GitHub asset digest as an expected value, so that hash
is audit evidence rather than a digest gate. The separate BepInEx and dgVoodoo2
paths do enforce GitHub-provided asset digests when available; ReShade uses its
pinned Authenticode status/thumbprint trust gate plus its audit hash. Other
live-fetched artifacts are logged with their actual source/hash/transfer fields.

## Current Limitation

The menu update path does not currently enforce an expected GitHub asset digest.
Update safety relies on HTTPS, GitHub release URL allowlisting, ZIP/script
validation, backup-before-replace behavior, and manual confirmation.
