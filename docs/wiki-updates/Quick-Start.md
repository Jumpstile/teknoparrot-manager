# Quick Start

Current published release: v1.0 RC7. RC8 is the candidate under review and is
not published. Final v1.0 is unpublished. RC4 is historical and superseded.
Test one game after each run.

Get TeknoParrot Manager running in a few minutes. For full details on any topic, see the relevant page linked throughout.

---

## New to TeknoParrot?

[TeknoParrot](https://www.teknoparrot.com/) is a free Windows frontend/loader for arcade games that originally ran on PC-based arcade hardware (Sega Lindbergh, Sega RingEdge, Taito Type X, Raw Thrills, and others). It handles per-game configuration, control mapping, and emulation compatibility so these games run on a normal PC. **This script (TeknoParrot Manager) is not TeknoParrot itself** — it's a separate automation layer that bulk-configures TeknoParrot's per-game profiles for you instead of doing it one game at a time in TeknoParrotUI.

**Quick glossary for newcomers:**

| Term | Meaning |
|---|---|
| **TeknoParrotUi.exe** | TeknoParrot's own GUI, where you launch games and configure them manually. This script edits the same profile files TeknoParrotUi.exe reads/writes. |
| **Dat file integration** | TeknoParrot Manager reads a community-maintained "dat" file (Eggman/RomVault) to identify games without an obvious matching `.exe`, so they can still be auto-registered. |
| **Control propagation** | Once you've manually bound controls for one game of a given type in TeknoParrotUI, this script copies those bindings to every other game of that type. |
| **BepInEx** | A plugin/modding framework some TeknoParrot games use. Mode 9 offers user-approved install, update, or repair-reset with a stable x64/x86 package matched to the validated game executable. |
| **FFB (Force Feedback)** | Controller/wheel force feedback support. TeknoParrot offers a native option (FFB Blaster, requires a paid membership) and there is a free third-party plugin alternative — this script can configure either. |

For terms specific to this script's own file/profile model, see the [Glossary in the repository README](https://github.com/Jumpstile/teknoparrot-manager/blob/main/README.md#glossary).

---

## Scope and safety boundaries

TPM is an automation layer around TeknoParrot, not TeknoParrot itself. It
organizes and extracts user-provided games, registers profiles, and can copy
controls from a reference game. LaunchBox and HyperSpin 2 own their frontend
libraries. Windows owns drivers, permissions, services, display behavior, and
devices. PostgreSQL owns its service and databases. Dolphin/Triforce and
pcsx2x6 own their runtimes, firmware, and BIOS. BepInEx owns its plugin
runtime. Eggman/RomVault owns its community DAT content. TPM does not provide
or redistribute game files, firmware, BIOS, or emulator runtime files.

The model is backup first, preview/dry-run first, explicit approval, fail-closed
validation, and restore/rollback when recovery is needed. Registration, launch
observation, controls readiness, and verification are separate states. A
registered profile or observed launch does not prove that controls are ready;
map and test them in TeknoParrot and complete ACTION REQUIRED.

Post-1.0 roadmap items are future planning only, not current RC8 candidate
features. RC7 remains the current published release.

## Requirements

- Windows 10 or 11
- PowerShell 5.1 or later (built in — no install needed)
- TeknoParrot installed, with `TeknoParrotUi.exe` run at least once so it has downloaded its GameProfiles folder
- Your games as ZIP files on a NAS/drive (for AutoSync) or already extracted into per-game subfolders

---

## Run it

**1.** Open PowerShell in the folder containing `TeknoParrot-Manager.ps1`:

```
cd "C:\path\to\TeknoParrot\Scripts"
```

**2.** Start the script:

```
.\TeknoParrot-Manager.ps1
```

If the script is blocked by execution policy, allow it for this session only:

```
powershell -ExecutionPolicy Bypass -File .\TeknoParrot-Manager.ps1
```

**3.** On first run the script scans common install locations for `TeknoParrotUi.exe` and offers a match. Confirm it or type the path manually.

**4.** Pick a mode:

| # | Mode | Use when |
|---|---|---|
| 1 | AutoSync | Games are ZIPs on a NAS or local drive |
| 2 | Register only | Games are already extracted |
| 3 | Propagate Controls | Re-copy control bindings without going through AutoSync/Register first |
| 4 | Crosshair setup | You want custom cursors on lightgun games |
| 5 | ReShade setup | You want visual enhancements |
| 6 | dgVoodoo2 setup | Games crash or show black screens |
| 7 | GPU fix setup | Apply AMD/NVIDIA/Intel fix flags |
| 8 | FFB setup | Wheel/stick rumble and force feedback |
| 9 | BepInEx setup | Install, update, or repair-reset BepInEx for selected games |
| 10 | Library health check | Quick read-only status check, safe any time |
| 11 | Restore backup | You want to roll back UserProfiles, LaunchBox files, or Postgres databases |
| 12 | Postgres setup | A registered game needs PostgreSQL (Golden Tee Live, etc.) |
| 13 | Check for Updates | Manual, backup-first check against the latest GitHub release |
| 14 | Create Support Package | Gather safe diagnostics into one redacted ZIP to send when asking for help |
| 15 | Exit | |

After each mode completes you return to this menu. On smaller console windows the menu automatically switches to a compact layout; type `?` at the prompt to show full descriptions.

<details>
<summary>What the menu looks like in the console</summary>

```
--------------------------------------------
 Mode
--------------------------------------------
  LIBRARY MANAGEMENT
  ------------------
  1) AutoSync        -- Extract ZIPs (NAS or local) to a local
                        folder, then register the games.
  2) Register only   -- Games are already extracted; just register.
  3) Propagate Controls -- Re-copy control bindings from reference
                        games to other compatible games, without going
                        through AutoSync/Register first.

  GAME ENHANCEMENTS (all optional -- games work without these)
  --------------------------------------------------------------
  4) Crosshair setup -- Pick and deploy custom crosshairs to all
                        registered lightgun games.
  5) ReShade setup   -- Add visual enhancements (sharper image, better
                        colours, scanlines, borders). Optional.
  6) dgVoodoo2 setup -- Fix old DX8, DirectDraw, and Glide games that
                        crash or show black screens. Optional.
  7) GPU fix setup   -- Auto-detect your GPU (AMD / NVIDIA / Intel) and
                        apply the matching compatibility fix to every
                        registered game that has one. Optional.
  8) Force feedback (FFB) setup -- Wheel/stick rumble and force feedback.
                        Covers TeknoParrot's built-in FFB Blaster (needs a
                        paid membership) and a free third-party plugin.
  9) BepInEx setup -- Offers user-approved install, update, or repair-reset
                        using the stable x64/x86 package matching each
                        validated game executable.

  MAINTENANCE AND RECOVERY
  ------------------------
  10) Library health check -- Read-only: registered/broken/unregistered
                        counts plus GPU fix / FFB Blaster / dgVoodoo2
                        coverage. No network access -- just a status check.
  11) Restore backup -- Roll UserProfiles back to a previous backup.
  12) Postgres setup -- Installs/configures the local PostgreSQL
                        database that some Incredible Technologies
                        games need (Golden Tee Live, Power Putt Live,
                        Silver Strike Bowling Live, Target Toss Pro).

  APPLICATION
  -----------
  13) Check for Updates -- Manual, backup-first check against the
                        latest GitHub release.
  14) Create Support Package -- Gather safe logs and reports into one
                        redacted ZIP to send when asking for help.
  15) Exit

Enter 1-15:
```
</details>

**5.** For **AutoSync**, choose a LOCAL staging folder with free space, outside both TeknoParrot and your ZIP source. Not sure yet? Answer Y to "Run in PREVIEW mode first?" to see what would happen with zero files written, then Y when asked whether to perform the operation for real to commit them immediately -- see [[AutoSync#preview--dry-run-mode]]. Then choose what to extract:

| Key | Action |
|---|---|
| A | All unextracted games |
| L | Browse A-Z list, pick by number |
| S | Search by keyword, pick by number |
| D | Done — proceed with current queue |

**6.** Launch `TeknoParrotUi.exe` — your games now appear.

---

## Send a support package

If something goes wrong, choose **14) Create Support Package**. The support
submenu lets you create a package or choose **Open TPM Logs and Reports**.
Choose Create Support Package to save one ZIP under `SupportPackages\` beside
the script. It gathers only selected TPM, TeknoParrot, and game text
diagnostics plus plugin metadata, and removes common passwords, tokens, and
user-profile paths from included text.

The package does not include ROMs, game files, executables, DLL payloads,
archives, profiles, credentials, or recovery-state files. Missing optional
diagnostics are listed in the manifest. If collection or cleanup cannot finish
safely, TPM reports a partial result instead of saying the package is ready to
send.

## Copy your controls (recommended)

1. In TeknoParrot, fully bind **one game per control type** — buttons, axes, Test, Service, Coin, Start. Good starting points:
   - **Fighting/buttons:** Street Fighter III, BlazBlue, Tekken 7
   - **Driving:** Daytona Championship USA, Initial D, OutRun 2 SP
   - **Lightgun:** House of the Dead 4, Aliens Extermination
   - **Trackball:** Golden Tee Live, Silver Strike Bowling

2. Re-run the script. After registration it runs propagation automatically, copying those controls to every other game of the same type.

3. Launch **one** updated game and test it before trusting the rest.

Readiness reminder: registration means the profile/path was created or matched;
launch observation means a user saw a test launch; controls readiness requires
mapping and testing in TeknoParrot; verification means checking the evidence
and ACTION REQUIRED report. None silently proves the others.

---

## Optional features (run any time from the menu)

- **[[Crosshairs]] (mode 4)** — 321 crosshair designs included; pick by number from an HTML preview.
- **[[ReShade]] (mode 5)** -- sharpening, CRT scanlines, and other post-processing. Its optional non-modal preview offers twelve canonical profiles backed by ten unique pinned shader effects. Choose from the gallery or terminal list; both stay synchronized. The 0-100 slider remains independent. The bundled-image approximation does not run the game or execute shaders; terminal `U` and explicit confirmation are still required before deployment, after which the preview closes automatically. ReShade DLLs are not bundled.
- **[[dgVoodoo2]] (mode 6)** — only needed for games that crash or show black screens.
- **[[GPU Fix]] (mode 7)** — safe to run any time; re-run after changing GPU or drivers.
- **[[FFB Setup]] (mode 8)** — native FFB Blaster (needs a paid membership) and/or a free third-party plugin.
- **[[BepInEx]] (mode 9)** -- user-approved install, update, or repair-reset with the stable x64/x86 package matched to the validated game executable.
- **[[Postgres Setup]] (mode 12)** -- installs/configures the local PostgreSQL database some Incredible Technologies games need (Golden Tee Live, Power Putt Live, Silver Strike Bowling Live, Target Toss Pro, etc.). Administrator privileges may also be required for automatic recovery when the saved database password is unusable.

---

## If something goes wrong

AutoSync backs up the current UserProfiles contents before extraction (preview mode skips the backup):

```
<TeknoParrotRoot>\UserProfiles\FullBackup\<date_time>\
```

To restore: choose **mode 11 — Restore backup** from the main menu.

See [[Troubleshooting]] for common problems.

## RC8 candidate recovery notes

- If an Eggman DAT is under the TeknoParrot root, TPM keeps it readable but
  refuses to overwrite it. It can offer a safe configured primary ZIP/source
  folder, such as a reachable NAS folder, or explain how to choose one.
- If PostgreSQL automatic recovery needs elevation, close TPM, right-click
  `TeknoParrot-Manager.bat` (or the PowerShell script), choose **Run as
  administrator**, and select mode 12 again. The blocked step does not change
  PostgreSQL data or profiles.
- If mode 9 refuses an unsafe BepInEx game root, review the affected profile
  path, move the game under the configured games root, or remove the junction or
  symlink. No BepInEx download or write is attempted for that game.

RC8 remains unpublished; use the RC7 release link above for the current public
download.
