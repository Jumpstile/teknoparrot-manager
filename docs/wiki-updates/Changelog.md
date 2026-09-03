# Changelog

## v1.0 RC8 (candidate, not published) -- runtime recovery and release-integrity preparation

- RC7 remains the current published release. RC8 has no public tag, release
  asset, or Scripts mirror; final Version 1.0 remains unpublished.
- Additional RC8 candidate fixes keep duplicate display identities
  ambiguous, extend the read-only ReShade eligibility guard through reachable
  helpers, mark curated profiles/effects `ADVISORY_UNMEASURED`, and separate
  sanitized setup notes from ACTION REQUIRED. No separate `EXTENDED` topology
  classification or live Windows display acquisition is included.
- Eggman updates protect a DAT under the TeknoParrot root and can offer the
  validated primary ZIP/source folder as the explicit destination.
- PostgreSQL recovery asks the user to choose a replacement password, uses
  in-process Windows Installer properties, authenticates one-time protected
  UAC resume state, restores service state truthfully, and keeps the
  fail-closed backup/reset boundaries.
- BepInEx setup offers approved x64/x86 install, update, and repair-reset paths
  with verified backup and rollback.
- Create Support Package gathers allowlisted TPM/TeknoParrot/game diagnostics
  and metadata-only plugin inventories into one redacted ZIP; game binaries,
  credentials, profiles, and arbitrary directories are excluded.
- ReShade preview selection now uses the bundled, hash-validated
  `TPM-preview-landscape.png` reference and reuses one bounded in-memory cache
  per gallery window; split and slider sides remain tied to the same pixels.
- Support-package output leads with `What failed` and `What TPM did not change`,
  preserves detailed allowlisted collection failures, and collapses routine
  missing optional diagnostics.
- Restore, crosshair, first-run, optional-download, update, and recovery flows
  expose beginner-readable retry/status guidance. The shared TPM STATUS footer
  uses structured events, real steps, and resize-safe cursor/append-only
  fallbacks without affecting redirected runs.
- Review follow-up binds protected recovery consumption to its issuance, restores failed claims safely, exposes repair for incomplete current BepInEx trees, and closes workflow failures without false completion.
- Certification captures and guards exact branch, commit, upstream, ref, and
  reflog identity through publication/finalization.
- Release packaging requires exact source/package identity and a completed #290
  repository and live-wiki freshness audit.
- ReShade profile choices now show friendly descriptions followed by the
  approved shader filename and technique, including the exact
  `LumaSharpen.fx / LumaSharpen`, `CRT_Lottes.fx / CRT_Lottes`, and
  `Vibrance.fx / Vibrance` labels. The visible text is generated from the
  canonical TPM definitions and hides internal paths and live runtime files.
- FFB overlap ownership is now exclusive: choosing the third-party owner
  creates a fresh verified profile backup, clears native FFB Blaster fields
  for the overlap set, verifies the switch, and blocks plugin deployment if
  the transition cannot be completed safely.

## v1.0 RC7 (2026-08-22) -- published release candidate

- Publication: v1.0 RC7 is published. Release archive:
  https://github.com/Jumpstile/teknoparrot-manager/releases/tag/v1.0-RC7
- Asset filename: GitHub serves the immutable asset as
  `TeknoParrot.Manager.v1.0.RC7.zip` after filename normalization. The
  verified SHA-256 is
  `45D14469CF750AC14B0F4113FB4117E2DA1C80F612C335D66B61C6E3FE5ABF84` and
  the size is 4,862,794 bytes.
- Release visibility: RC7 is a release candidate by product/version naming,
  but it is not hidden from GitHub's front-page Releases panel. The GitHub
  prerelease flag is not used when it would prevent RC visibility; RC7 is the
  repository's latest surfaced release. Final Version 1.0 remains unpublished.
- Readiness: RC7 carries the read-only controls-readiness handoff and
  contract-backed missing-component warnings. When controls are Missing, Not
  verified, Unsupported, or Unknown, ACTION REQUIRED directs the user to open
  TeknoParrot controls configuration and map/test controls before treating the
  game as ready. Registration, launch observation, wizard state, and controls
  readiness remain separate.
- Previous published release: v1.0 RC6 (historical).

## v1.0 RC6 (2026-08-16) -- onboarding, live dependency acquisition

- Improvement: the first-run wizard now asks fewer blocking questions and
  points users to destination menu entries by label. Uncertain AutoSync
  matches now trigger the supplementary-dat recommendation only when needed.
- Feature: dgVoodoo2 and ReShade can be downloaded from their official sources.
  dgVoodoo2 validates the GitHub asset digest when available; ReShade gates
  extraction on the installer Authenticode status and pinned signer thumbprint.
  Neither is bundled in the release ZIP.
- Audit: ReShade records authoritative source, installer filename/version,
  SHA-256, Authenticode signer/status/thumbprint/trust, and transfer metrics.
  BepInEx records GitHub source, filename/version, SHA-256/digest validation
  when available, and transfer metrics; dgVoodoo2, FFBPlugin, Eggman dat,
  PostgreSQL/update packages, and thumbnail downloads retain their actual
  source/hash/transfer audit fields.
- Compatibility: Windows PowerShell 5.1 explicitly loads the compression and
  inbox Security, Management, and Utility dependencies needed by those trust,
  hashing, and extraction paths, including when an inherited PowerShell 7
  module root would otherwise take precedence.

## v1.0 RC5 (2026-08-14) -- RC4 packaging correction (RC4 superseded)

- Fix: the RC4 release ZIP was missing `scripts\TPMCertification.Authority.psm1`, an unconditional dependency of `scripts\TPMCertification.Contracts.psm1` (imported at runtime for pcsx2x6 crosshair/ECVF setup). Every RC4 install reaching that code path had contract evaluation fail closed silently -- no crash, but pcsx2x6/ECVF contract verification never actually ran. Corrected the release package manifest and package validator. **RC4 is superseded; use RC5.**
- Also corrects an active-documentation gap (RC4 guidance still said "in release preparation" after RC4 was actually published) and redacts a personal filesystem path from `contracts\pcsx2x6\evidence.md`.

## v1.0 RC4 (2026-08-13) -- beginner clarity, Centipede Chaos coverage (SUPERSEDED by RC5)

- Improvement (issue #222): the Eggman dat, supplementary dat, and thumbnail download prompts now explain what the file is and confirm it never downloads game data, before asking whether to proceed. Added a "What TPM just did" recap to the end-of-run summary (ZIPs extracted, games registered, dat file action taken, thumbnail action, anything still needing manual attention). Added a first-run welcome screen (new installs only) framing that TPM organizes/extracts/registers/exports games but does not provide games or guarantee boot/fullscreen behavior.
- Fixed (issue #130/#79): TPM's internal GameProfile schema-drift diagnostic had a stale baseline flagging long-standing, widely-used profile fields as "unknown." Re-captured against the live upstream catalog (541 current official profiles). Also confirms Centipede Chaos is fully supported through TPM's existing generic profile-parsing, matching, and export logic.

## v1.0 RC3 (2026-08-08) -- published hardware-certified release

- Fixed (issue #173): pcsx2x6 crosshair setup now verifies the emulator's own
  first-run initialization and contract-resolved data root before deploying
  assets. Emulator-owned cursor_path settings remain verify-only; TPM never
  writes them.

- Fixed (issue #154): the development certification harness can run the existing read-only Library Health Check under `-Unattended`, then exits cleanly when it finishes.
- Fixed (issue #154): the certification Pester runner and preflight now require exactly Pester 5.7.1, preventing an unvalidated newer version from silently changing full-suite results.
- RC3 licensing: personal, non-commercial use of official releases is permitted; commercial use, redistribution, modified distribution, sublicensing, bundling, paid support use, arcade-operator use, and integration into TeknoParrot or another emulator, launcher, or arcade-management product require prior written permission under a separate commercial/integration license.

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
