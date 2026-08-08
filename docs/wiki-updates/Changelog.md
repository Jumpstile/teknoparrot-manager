# Changelog

## Unreleased -- v1.0 RC3

- Fixed (issue #173): pcsx2x6 crosshair setup now verifies the emulator's own
  first-run initialization and contract-resolved data root before deploying
  assets. Emulator-owned cursor_path settings remain verify-only; TPM never
  writes them.

- Fixed (issue #154): the development certification harness can run the existing read-only Library Health Check under `-Unattended`, then exits cleanly when it finishes.
- Fixed (issue #154): the certification Pester runner and preflight now require exactly Pester 5.7.1, preventing an unvalidated newer version from silently changing full-suite results.

## v1.0 RC2.1

Release-hardening pass on top of RC2: thumbnail downloads, update-check version display, certification-suite reliability, and menu polish.

- Fixed (issue #132): thumbnail downloads no longer leave a stale "Downloading Thumbnails" progress overlay stuck on screen after a failure -- most visible when every thumbnail in a batch came back 404. Reworded thumbnail messaging into plain language and stopped implying a missing icon means the game is unsupported.
- Fixed (issue #134): the update checker's "Current version" and "Latest version" now share one canonical display format instead of showing the same release two different ways.
- Fixed (issue #136): the Certification Suite could hang indefinitely during the Pester regression phase with no diagnostics. It now shows live heartbeat progress and enforces a configurable timeout so a hang fails cleanly with a clear reason.
- Usability: the Overrides summary line explains what it means and what action to take, in plain language. The Preview/Dry Run "apply for real" prompt explains that applying performs a fresh scan, not a replay of the preview.
- Visual polish: the Professional/Ultra menu banner renders as a responsive FIGlet/ANSI-Shadow wordmark that scales with console width.
- Closed out the remaining RC2 release-gate usability items (DAT selection feedback, DAT file-picker filter, one-click certification launcher provenance, certification runtime UX) with regression coverage.

## v1.0 RC2

Release-candidate package identity correction and adaptive menu inclusion.

- Fixed the runtime banner/header so the RC2 package displays `TeknoParrot Manager v1.0 RC2` instead of the stale RC1 label.
- Included the adaptive responsive main menu from issue #104: full, standard, and compact layouts selected by console size, with unchanged mode numbers and behavior.
- Added release-package validation for the packaged `TeknoParrot-Manager.ps1` version/header/banner, preventing structurally valid ZIPs with stale release identity from passing validation.

## v0.99.44 BETA

Release-hygiene and regression-hardening build.

- Hardened and unified live file downloads through the shared `Invoke-TpmDownload` pipeline. The helper uses BITS first, streamed `HttpClient` second, and `Invoke-WebRequest` only as an emergency fallback. Downloads now use partial files, validation before final move, failure cleanup, progress display, and final transfer metrics.
- Added shared extracted-folder detection for AutoSync and extraction pickers through `Resolve-ExtractedGameFolder`, reducing duplicate extraction prompts for already-extracted games.
- Fixed TeknoParrot and LaunchBox auto-detect callers so zero, one, and multiple match behavior remains intact.
- Expanded regression coverage and the regression matrix for downloader, thumbnail, extracted-folder resolver, AutoSync, crosshair, and auto-detect behavior.

## v0.99.43 BETA

Tester validation build for the v0.99.40 beta line, including FATF-oriented control-propagation hardening, compatibility documentation, package validation, and release packaging corrections.
