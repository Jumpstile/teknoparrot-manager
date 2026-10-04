# TeknoParrot Manager

![TeknoParrot Manager](banner.png)

Current published release: v1.0 RC7. Download the published RC7 release:
https://github.com/Jumpstile/teknoparrot-manager/releases/tag/v1.0-RC7.
RC8 is the candidate under review and is not published. Final v1.0 is
unpublished. RC4 is historical and superseded.

Registers your extracted games with TeknoParrot, copies controls between games of the same type, and keeps your library organised. AutoSync backs up UserProfiles before extraction; preview mode skips the backup.

> Release Candidate v1.0 RC7: Test one game after each run before trusting the rest.
---

## What it does

| Feature | Description |
|---|---|
| Auto-registration | Scans your games, matches each to the correct TeknoParrot profile, sets the game path |
| Fuzzy matching | Auto-registers NESiCAxLive and other shared-executable platforms by folder-name similarity |
| Dat integration | Uses the Eggman/RomVault dat to resolve shared-exe games, ELF games, and misnamed folders |
| AutoSync extraction | Extracts ZIP files from a NAS or local source into a staging folder, skipping unchanged games |
| Control propagation | Bind one game per control type; the script copies those bindings to every other game of the same type |
| Crosshair setup | Deploys custom P1/P2 cursor images to all registered lightgun games |
| ReShade | Installs ReShade post-processing into game folders (sharpening, CRT scanlines, colour) |
| dgVoodoo2 | Fixes older games that use DirectX 8, DirectDraw, or Glide |
| GPU fix | Applies the correct AMD/NVIDIA/Intel fix flag to every registered game that supports one |
| Force feedback (FFB) | Native FFB Blaster (paid membership) and/or a free third-party plugin, fetched live |
| BepInEx setup | User-approved install, update, or repair-reset using the stable x64/x86 package matching the validated game executable |
| Postgres setup | Installs/configures the local PostgreSQL database some Incredible Technologies games need (Golden Tee Live, Power Putt Live, Silver Strike Bowling Live, Target Toss Pro). Never reinstalls Postgres or recreates an existing database |
| Automatic compatibility warnings | Install-path-length limits, pinned-file-version requirements, and known GPU-vendor incompatibilities for specific known games, flagged every run |
| Frontend integration | Writes games directly into LaunchBox's own library (or a manual-import file), and/or exports to HyperSpin 2's game list |
| Thumbnail download | Fetches missing game icons from TeknoParrotUIThumbnails |
| Unattended mode | `-Unattended` switch for Windows Task Scheduler overnight runs |
| Preview / dry-run mode | See exactly what AutoSync/Register would do, with zero files written, then apply for real immediately if it looks right |
| Library health check | Read-only registered/broken/empty status plus GPU fix / FFB Blaster / dgVoodoo2 / Postgres coverage and ReShade/BepInEx install counts -- no network access, safe any time |
| Check for Updates | Manual, backup-first check against the latest GitHub release. Nothing is downloaded or changed without your explicit confirmation |
| Create Support Package | Gathers selected safe diagnostics into a redacted ZIP to send when asking for help; never includes game payloads or credentials |
| Propagate Controls | Re-copy control bindings from reference games to other compatible games, without going through AutoSync/Register first |
| Adaptive main menu | Shows full descriptions on roomy consoles, compact labels when space is tight, and `?` for full descriptions on demand |

---

## Who is this for?

TeknoParrot Manager is intended for:

- Large TeknoParrot libraries
- NAS-based collections
- LaunchBox users
- HyperSpin 2 users
- RetroBat / Batocera users

You may not need it if you only manage a handful of games manually.

---

## Typical workflow

1. Run TeknoParrotUi.exe once so it downloads its game profiles.
2. Run TeknoParrot Manager and choose **AutoSync** or **Register only**.
3. Launch TeknoParrotUI and verify your games appear.
4. In TeknoParrotUI, bind one game of each controller type you use.
5. Re-run the script — it copies those controls to all similar games.
6. Test one updated game before trusting the rest.

---

## Safety features

- AutoSync backs up the current UserProfiles contents before extraction; preview mode skips the backup.
- AutoSync does not begin extraction if the backup cannot be created or completed.
- Interrupted extractions are detected and re-extracted automatically on the next run
- Existing bindings are never overwritten
- Existing icons are never overwritten
- Restore mode available from the main menu at any time

- **Eggman DAT safety:** a current DAT under the TeknoParrot root is never
  overwritten. When the configured primary ZIP/source folder is safe, TPM can
  offer it as the update destination; otherwise it explains how to correct the
  destination.
- **Fail-closed recovery:** PostgreSQL elevation failures and unsafe BepInEx
  roots show a concrete next action and do not claim that data, profiles, or
  game files were changed.

---

## Ownership and Readiness Boundaries

TPM is a separate automation layer for TeknoParrot. It organizes and extracts
the games you provide, registers profiles, and can copy controls from a
reference game. TeknoParrot/TeknoParrotUI owns its emulator UI, GameProfiles,
launch configuration, and launch behavior. LaunchBox, HyperSpin 2, RetroBat,
and Batocera own their frontend libraries. Windows owns drivers, permissions,
services, display behavior, and input devices.

PostgreSQL owns its service and database contents. Dolphin/Triforce and pcsx2x6
own their emulator runtimes, firmware, and BIOS. BepInEx owns its plugin
runtime. Eggman/RomVault owns its community DAT content. TPM does not provide
or redistribute game files, firmware, BIOS, or emulator runtime files.

TPM uses a backup-first, preview/dry-run, explicit-approval, fail-closed model
with restore/rollback paths where supported. Registration, launch observation,
controls readiness, and verification are separate states. A registered profile
or observed launch is not proof that controls are ready; map and test them in
TeknoParrot and complete ACTION REQUIRED.

Post-1.0 roadmap items are future planning only, not current RC8 candidate
features. RC7 remains the current published release.

---
## Pages

- [[Quick Start]] -- Get up and running in minutes
- [[Setup]] -- Requirements, first run, path auto-detection, configuration
- [[AutoSync]] -- Mode 1: extract ZIPs from NAS/local source, game selection
- [[Register]] -- Mode 2: registration, fuzzy matching, dat integration, controls, frontends
- [[Propagate Controls]] -- Mode 3: re-copy control bindings from reference games without going through AutoSync/Register first
- [[Crosshairs]] -- Mode 4: custom crosshair images for lightgun games
- [[ReShade]] -- Mode 5: visual enhancements (sharpening, CRT, colour)
- [[dgVoodoo2]] -- Mode 6: legacy DirectX 8 / DirectDraw / Glide compatibility
- [[GPU Fix]] -- Mode 7: GPU vendor fix flags (AMD / NVIDIA / Intel)
- [[FFB Setup]] -- Mode 8: native FFB Blaster (membership) and free third-party plugin
- [[BepInEx]] -- Mode 9: user-approved install, update, or repair-reset using the stable x64/x86 package matching the validated game executable
- [[Health Check]] -- Mode 10: read-only library status check (registered/broken/empty, optional-feature coverage)
- [[Restore Backup]] -- Mode 11: roll back UserProfiles, LaunchBox files, or Postgres databases to a previous backup
- [[Postgres Setup]] -- Mode 12: install/configure PostgreSQL for Incredible Technologies games (Golden Tee Live, Power Putt Live, etc.)
- [[Check for Updates]] -- Mode 13: manual, backup-first check against the latest GitHub release
- [[Quick Start#Send a support package]] -- Mode 14: create a safe support ZIP
- [[Troubleshooting]] -- Common problems and fixes
- [[Changelog]] -- Version history

---

## Quick links

- [v1.0 RC7 release](https://github.com/Jumpstile/teknoparrot-manager/releases/tag/v1.0-RC7) -- download the published ZIP
- [Issues](https://github.com/Jumpstile/teknoparrot-manager/issues) -- bug reports
- [Engineering Governance](https://github.com/Jumpstile/teknoparrot-manager/blob/main/ENGINEERING_GOVERNANCE.md) -- how issues are labeled and tracked, for contributors and maintainers
- [Contributing](https://github.com/Jumpstile/teknoparrot-manager/blob/main/CONTRIBUTING.md) -- filing issues and submitting changes
