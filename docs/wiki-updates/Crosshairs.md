# Crosshairs (Mode 4)

Deploys custom P1/P2 crosshair cursor images to all registered lightgun games. 321 designs are included in the `Crosshairs\` folder next to the script.

---

## Supported games

Any registered game whose TeknoParrot UserProfile has `<GunGame>true</GunGame>`. This includes House of the Dead 4, Aliens Extermination, Aliens Armageddon, Rambo, Terminator Salvation, and others.

---

## How crosshairs work in TeknoParrot

TeknoParrot supports custom cursor images placed as `P1.png` and `P2.png` in the game's executable directory. Placement varies by game type:

| Game type | Where the images go |
|---|---|
| Standard games | `P1.png` + `P2.png` in the folder containing the game's `.exe` |
| ElfLdr2 games | Shared pair in the ElfLdr2 loader folder |
| Pcsx2x6 games | Shared pair in the contract-resolved DataRoot `pcsx2x6\TeknoParrot\crosshairs\`; emulator-owned `cursor_path` settings are verify-only and are never written by TPM |

---

(v0.99.45+) Pcsx2x6 crosshair deployment writes to the official upstream location, `pcsx2x6\TeknoParrot\crosshairs\`, instead of the emulator folder root used previously. Files already deployed at the old location are left in place, not deleted. See [[Register]]'s ACTION REQUIRED section for the related pcsx2x6 BIOS/firmware detection check TPM also performs.

## pcsx2x6 first-run and ownership behavior (issue #173)

For a stock, never-initialized pcsx2x6 install, TPM verifies the emulator's own first-run initialization path before deploying crosshair assets. It resolves the destination through the registered emulator contract's DataRoot rather than reconstructing a local path.

The cursor_path settings in PCSX2.ini are emulator-owned. TPM verifies their state for reporting, but never writes them. Unknown or unavailable contract state fails closed: TPM reports the unresolved prerequisite and performs no crosshair asset or cursor-path write.

## Using the crosshair picker

1. The script scans `Crosshairs\` next to the script for PNG files and validates each against the PNG magic-byte signature. Anything that fails validation is reported and skipped.

2. An HTML preview grid (`TeknoParrot-Crosshairs-Preview.html`) is generated and opened in your browser so you can browse all designs visually.

3. Enter the index number for your **Player 1** crosshair and **Player 2** crosshair. The two can be the same or different. (v0.94+) The script remembers your last choice by filename and offers it as a default -- press Enter to reuse it.

4. The script copies the chosen images to every registered lightgun game folder and reports: deployed / skipped / errors.

5. You are then asked whether to also **hide the Windows cursor** for all lightgun games. Answering Y sets the cursor-hide field (`HideCursor`, `"Hide Cursor"`, or `DisableCursor` depending on the game) in each gun game's UserProfile XML. A timestamped backup is taken automatically before any XML is changed.

You can answer N to the cursor-hide step and run mode 4 again later if you change your mind.

---

## Adding your own crosshairs

Drop any PNG image into the `Crosshairs\` folder next to the script. The script auto-detects all PNG files, validates them, and includes them in the preview on the next run. Files do not need to follow a specific naming convention -- but numbering them makes them easier to identify in the HTML preview.

The 321 included designs (000.png -- 320.png) are sourced from the emuline.org custom crosshairs collection.

---

## Re-running

Run mode 4 any time to change the crosshair design. Previously deployed images are replaced.
