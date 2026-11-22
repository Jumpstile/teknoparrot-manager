# GPU Fix

Some TeknoParrot games have a setting that fixes problems on one kind of graphics card (AMD, NVIDIA or Intel). GPU fix finds your graphics card and sets the right value in every registered game that has this setting. It is main menu item 7, **GPU fix setup**.

---

## Quick steps

1. Start TeknoParrot Manager. At `Enter 1-17:` type `7` and press Enter.
2. Wait. Setup finds your graphics card and updates the games that have the setting.
3. Read the result. It says how many games were updated and how many already had the fix.

If TeknoParrot Manager cannot tell which graphics card you have, it asks: `Which graphics card do you have? Type AMD, NVIDIA or Intel`. Press Enter to cancel. No game is changed if you cancel.

---

## When to run it

Run it once after your first setup. Run it again whenever you change your graphics card. It is safe to run as often as you like. A game that already has the right value is left alone.

---

## Good to know

- Only your registered games are changed. TeknoParrot's own game templates are never touched.
- Games with no graphics card setting are left alone. The result says how many (`No GPU fix exists for ...`).
- Before it writes anything, TeknoParrot Manager saves a copy of your UserProfiles in the `FullBackup` folder (a folder starting with `GpuFix_`). To undo, use [[Restore Backup]].
- The fix only changes saved settings. It does not start the game, so it cannot prove the game now runs well. Start a game to try it.
- New games TeknoParrot adds later are covered automatically.
- If some games are skipped (for example their drive is not plugged in), the result screen says so. It also says how many games you selected and how many were changed, skipped or failed, and where the backup is. Press `D` for the reason, `H` to open [[Health Check]] and fix saved paths, or `R` to run it again.
- [[Health Check]] shows which registered games could use the fix but do not have it yet. It changes nothing.

<details>
<summary>Details: how it works</summary>

1. The graphics card is read from Windows (WMI). A name with AMD or Radeon is AMD, with NVIDIA, GeForce, RTX or GTX is NVIDIA, with Intel is Intel. With more than one card, the one with the most memory is used.
2. TeknoParrot's `GameProfiles` folder is scanned each time for fix settings: the yes/no fields `EnableAmdFix`, `AMDCrashFix` and `AMDFix` (and similar AMD fields), and drop-down fields such as `GPU Fix` that offer AMD, NVIDIA or Intel choices.
3. For each registered game with such a field, the value for your card is set.

At the end of a normal run you may also be asked `Apply now?` for GPU fix. Answering yes does the same thing.

The GPU fix offered at the end of first-time setup shows the same result screen as the menu: how many games you selected, changed, skipped and failed. A game on a drive that is not connected is called skipped, not failed. The drive letter is named, and it points to [[Health Check]] to repair the game paths.

</details>
