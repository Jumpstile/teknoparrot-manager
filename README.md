# TeknoParrot Manager

A PowerShell 5.1 script that automates setting up and managing a TeknoParrot arcade game library on Windows.

> **Beta** — test one game after each run. Profiles are backed up automatically before every run.

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Modes](#modes)
- [Full Documentation](#full-documentation)

---

## Features

- **Auto-registration** — scans your extracted games and copies the matching TeknoParrot profile with the correct game path filled in. Existing registrations are never overwritten.
- **Fuzzy name matching** — handles shared-executable platforms (NESiCAxLive, etc.) by comparing folder names to profile codes and auto-registering the best match.
- **Dat file integration** — optionally downloads the Eggman/RomVault dat ZIP and uses it to resolve shared executables, register games with no known exe (pcsx2x6, ELF-based Lindbergh titles), and handle misnamed folders.
- **GitHub profile resolution** — fetches the full GameProfile list from the TeknoParrot repo on each launch to resolve dat codes that don't exactly match a local template.
- **Control propagation** — bind one game of each control type once; the script copies those settings to every other game of the same type.
- **AutoSync extraction** — copies and extracts game ZIPs from a NAS or local source, skipping unchanged games.
- **Game repair** — finds broken or empty game paths and re-points them automatically.
- **Crosshair setup** — deploys custom P1/P2 cursor images to all lightgun games with an HTML preview of 321 included designs.
- **ReShade** — installs post-processing into game folders, auto-detecting 32-bit vs 64-bit and the correct DLL name per game.
- **dgVoodoo2** — fixes older games that crash on DirectX 8, DirectDraw, or Glide by deploying the correct compatibility DLLs.
- **GPU fix** — detects your GPU (AMD / NVIDIA / Intel) and applies the matching vendor fix to every registered game that has one.
- **LaunchBox / HyperSpin 2 export** — builds import files for both frontends after each run.
- **Unattended mode** — `-Unattended` flag skips all prompts for scheduled overnight runs.
- **Safe by design** — timestamped backups before every run, free-space check, full log, one-click restore.

---

## Requirements

- Windows 10 or 11
- PowerShell 5.1 (built into Windows — no install needed)
- TeknoParrot installed

---

## Installation

1. Download `TeknoParrot Manager vX.XX BETA.zip` from [Releases](../../releases/latest)
2. Extract to any folder (e.g. alongside your TeknoParrot install)
3. Double-click **`TeknoParrot-Manager.bat`**

No additional software required.

---

## Modes

| # | Mode | What it does |
|---|------|-------------|
| 1 | AutoSync | Extract ZIPs from NAS or local source, then register |
| 2 | Register only | Games already extracted — just register |
| 3 | Restore backup | Roll profiles back to a previous backup |
| 4 | Crosshair setup | Pick and deploy custom crosshairs to lightgun games |
| 5 | ReShade setup | Install post-processing shaders |
| 6 | dgVoodoo2 setup | Fix DirectX 8 / DirectDraw / Glide compatibility |
| 7 | GPU fix setup | Apply AMD / NVIDIA / Intel vendor fix to all games |

---

## Full Documentation

The release ZIP includes:

- **`TeknoParrot-Manager-QuickStart.txt`** — one-page setup guide, start here
- **`TeknoParrot-Manager-README.txt`** — full reference documentation
- **`TeknoParrot-Manager-CHANGELOG.txt`** — version history
