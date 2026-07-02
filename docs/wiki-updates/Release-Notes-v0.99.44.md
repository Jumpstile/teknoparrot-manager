# Release Notes: v0.99.44 BETA

v0.99.44 BETA is a release-hygiene and regression-hardening build.

## Highlights

- Faster, safer downloads through the shared `Invoke-TpmDownload` pipeline.
- Better progress output with downloaded MB, total MB when known, MB/s, ETA when calculable, and final transfer metrics.
- Fewer duplicate extraction prompts in AutoSync through the shared extracted-folder resolver.
- Fixed TeknoParrot and LaunchBox auto-detect return handling.
- Expanded regression coverage and updated the regression matrix.

## Downloader Improvements

Live downloads now prefer BITS, fall back to streamed `HttpClient`, and keep `Invoke-WebRequest` only as an emergency fallback. Downloads are written to temporary partial files first, validated before being moved into place, and cleaned up on failure.

Covered call sites include the Eggman/RomVault DAT ZIP, PostgreSQL guide bundle, FFBArcadePlugin DLLs, BepInEx release ZIP, TPM update package, and TeknoParrotUI thumbnails.

## Extraction Resolver Improvements

AutoSync and extraction pickers now share `Resolve-ExtractedGameFolder` to detect already-extracted games more accurately. The resolver checks exact/normalized names, RetroBat suffixes, known short-name aliases, DAT/profile identity, registered paths, and conservative metadata differences.

The resolver never deletes, renames, or moves folders. It only prevents duplicate extraction prompts when a matching non-empty folder already exists.

## Auto-Detect Fix

TeknoParrot and LaunchBox root auto-detection no longer adds an extra array layer around detection results. This preserves correct zero, one, and multiple match behavior.

## Known Limitations

- SHA-256 update-package enforcement is not merged in this release line.
- Issue #53 still requires real FATF Drift tester validation before it should be closed.
- The full issue #66 25-title false-positive list still requires reporter confirmation against local data.
