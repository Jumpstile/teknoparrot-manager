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

## Current Limitation

SHA-256 enforcement is not merged in this release line. Update safety currently relies on HTTPS, GitHub release URL allowlisting, ZIP/script validation, backup-before-replace behavior, and manual confirmation.
