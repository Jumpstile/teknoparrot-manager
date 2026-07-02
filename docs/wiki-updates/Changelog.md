# Changelog

## v0.99.44 BETA

Release-hygiene and regression-hardening build.

- Hardened and unified live file downloads through the shared `Invoke-TpmDownload` pipeline. The helper uses BITS first, streamed `HttpClient` second, and `Invoke-WebRequest` only as an emergency fallback. Downloads now use partial files, validation before final move, failure cleanup, progress display, and final transfer metrics.
- Added shared extracted-folder detection for AutoSync and extraction pickers through `Resolve-ExtractedGameFolder`, reducing duplicate extraction prompts for already-extracted games.
- Fixed TeknoParrot and LaunchBox auto-detect callers so zero, one, and multiple match behavior remains intact.
- Expanded regression coverage and the regression matrix for downloader, thumbnail, extracted-folder resolver, AutoSync, crosshair, and auto-detect behavior.

## v0.99.43 BETA

Tester validation build for the v0.99.40 beta line, including FATF-oriented control-propagation hardening, compatibility documentation, package validation, and release packaging corrections.
