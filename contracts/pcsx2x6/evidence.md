# Contract Evidence: pcsx2x6

This document is the human-auditable companion to `contract.json`. The JSON
file holds the authoritative structured claims; this file holds the proof.
They are two parts of the same package -- never edit one without checking
whether the other needs to change too.

## Upstream

- Repository: https://github.com/PS2Homebrew-arcade/pcsx2x6
- Pinned commit: `c6e731ac0b9859011d358c021b7e2c9c95296a93`
- Commit date / provenance: merged via PR #1 (2026-07-14), message "add
  prefix to window title for TPUI to find the window no matter the game
  name".
- How the installed build was matched to this commit: the installed
  `pcsx2-qtx64.exe`'s window title reads `PCSX2x6 v0.0.22-24-gc6e731ac0`.
  The short hash `c6e731ac0` is a prefix of the pinned commit's full SHA.
- License: `pcsx2/Docs/License.txt` is GNU GPLv3. TPM only reads/writes the
  emulator's own ini configuration file and detects installed files -- it
  does not copy or redistribute pcsx2x6 source or binaries, so no GPL
  redistribution obligation is implicated by this contract's planned use.
  Re-check this note if TPM's use of pcsx2x6 ever changes to bundling or
  redistributing any part of it.

## Source Citations

### ev-portable-root: `EmuFolders::GetPortableModePath()` default
File: `pcsx2/Pcsx2Config.cpp`
```cpp
std::string EmuFolders::GetPortableModePath()
{
    const auto portable_txt_path = Path::Combine(AppRoot, "portable.txt");
    const auto portable_path = FileSystem::ReadFileToString(portable_txt_path.c_str()).value_or("");
    const auto trimmed_path = StringUtil::StripWhitespace(portable_path);
    // Default to TeknoParrot subfolder so all data stays organised under the exe directory.
    return trimmed_path.empty() ? "TeknoParrot" : std::string(trimmed_path);
}
```
`SetDataDirectory()` composes `DataRoot = AppRoot/GetPortableModePath()` and
`Settings (inis) = DataRoot/inis` in portable mode. Conclusion: the real ini
path is `AppRoot/<portable.txt content, or "TeknoParrot" if empty>/inis/PCSX2.ini`,
never a fixed `inis/PCSX2.ini`.

### ev-testconfig-init: `-testconfig` headless behavior
File: `pcsx2-qt/QtHost.cpp`
- CLI parsing (`ParseCommandLineOptions`) uses a single-dash convention:
  `-help`, `-testconfig`, `-portable`, `-datapath`, `-nogui`, `-batch`,
  `-setupwizard`.
- `-testconfig`'s own help text: "Initializes configuration and checks
  version, then exits."
- `main()` returns `EXIT_SUCCESS` immediately after `InitializeConfig()`
  when `-testconfig` is set, before any window or event-loop code runs.
- `InitializeConfig()` calls `Save()` synchronously when the ini file does
  not already exist -- not deferred, no blocking first-run dialog.

### ev-usb-ini-contract: USB ini section/key format
File: `pcsx2/USB/USB.cpp`
```cpp
std::string USB::GetConfigSection(int port) { return fmt::format("USB{}", port + 1); }
// ...
const std::string real_key(fmt::format("{}_{}", devname, key));
return si.GetStringValue(GetConfigSection(port).c_str(), real_key.c_str(), default_value);
```
For the GunCon2 device (`TypeName()` returns `"guncon2"`), the real key is
`guncon2_cursor_path` under section `[USB1]` or `[USB2]` -- not
`[USB Port N guncon2]` / `cursor_path`, which is what TPM's existing
`Set-Pcsx2CursorPaths` (TeknoParrot-Manager.ps1) and the certification
harness's ini parser both assumed.

### ev-guncon2-clear: `cursor_path` cleared in JVS lightgun mode
File: `pcsx2/USB/usb-lightgun/guncon2.cpp`, `GunCon2Device::UpdateSettings()`
```cpp
std::string cursor_path(USB::GetConfigString(si, s->port, TypeName(), "cursor_path"));
// ...
// In TP LIGHTGUN mode our OSD overlay draws the crosshair; suppress guncon2's own PNG cursor
// so we don't get a phantom copy tracking mouse-driven coordinates.
if (ACJV::GetMode() == JVS_MODE::LIGHTGUN)
    cursor_path.clear();
```
Whatever cursor_path value exists in the ini on disk is cleared in memory
at runtime whenever JVS mode is `LIGHTGUN`. Not yet confirmed: whether this
in-memory clear is ever written back to the ini file (making a
TPM-authored value actively overwritten) or simply ignored at runtime
(leaving a stale-but-harmless value on disk). See experiments.md.

### ev-vmmanager-jvsmode: `.acgame` `jvsmode` field drives Type + JVS mode
File: `pcsx2/VMManager.cpp`, approx. lines 1425-1462
```cpp
std::string jvsmode = INI.GetStringValue("data", "jvsmode", "");
// ... per-serial defaults exist for driving/drum, NOT for lightgun --
// lightgun mode is always explicit in the .acgame file, never inferred.
if (jvsmode == "lightgun")
{
    Host::SetBaseStringSettingValue("USB1", "Type", "guncon2");
    Host::SetBaseStringSettingValue("USB2", "Type", "guncon2");
    ACJV::SetMode(JVS_MODE::LIGHTGUN);
    Console.WriteLn(Color_Green, "ACGAME: jvsmode=lightgun -> GunCon2 on USB1+USB2");
}
```
This is unconditional and automatic -- TeknoParrot/TPM has no role in
setting `Type` or JVS mode for a lightgun title; the emulator does it
itself by reading the title's own `.acgame` archive metadata. Not yet
confirmed: whether the `Console.WriteLn` line reaches a file (the live
ini has `[Logging] EnableFileLogging = true` and `[Folders] Logs = logs`,
suggesting it should, under `<DataRoot>/logs/`), and whether the
`Host::SetBaseStringSettingValue` writes survive to disk after a clean
shutdown. See experiments.md.

### ev-live-ini-observation: real arcade machine's `PCSX2.ini`
Observed directly at `C:\Users\EliSi\LaunchBox\Emulators\TeknoParrot\pcsx2x6\TeknoParrot\inis\PCSX2.ini`
on the certified cabinet: `[USB1]` and `[USB2]` sections present, both
`Type = None` at observation time; a separate top-level `[JVS]` section
(`TestMode`, `VideoVoltage`, `MonitorSyncFrequency`, `VideoSyncSplit`,
`SuppressDaemon`, `SindenBorderEnabled`, `SindenBorderMode`,
`SindenBorderThickness`); no `[USB Port N guncon2]` section anywhere.
Confirms `ev-usb-ini-contract` against the actual production install, not
just the clean-copy experiment.

### ev-gamegprofile-gungame-flag: `GunGame` flag on the real cabinet
`grep -l "GunGame"` across `GameProfiles\*.xml` on the certified cabinet
found `<GunGame>true</GunGame>` on exactly `cobrata.xml`, `cobrataw.xml`,
`timecrs3.xml`, `timecrs4.xml`, `vnight.xml` -- all `EmulatorType=pcsx2x6`
-- and absent on non-gun pcsx2x6 titles checked (`acedriv3.xml`,
`tekken4.xml`, `soulclb2.xml`). `timecrs4.xml`'s `JoystickButtons` block
also explicitly maps `P1LightGun`/gun-trigger inputs, consistent with a
lightgun cabinet configuration.

### ev-issue-79-png-placement
Crosshair PNG deployment (`CanonicalFilesDeployed` / `LegacyRootFilesPresent`
in the pre-ECVF ADR-0155 section 5.8) is a file-location concern from
issue #79, unrelated to the ini/JVS findings above. Not re-investigated as
part of this contract; retained as TPM-owned pending its own evidence pass.

## Revalidation procedure

When PS2Homebrew-arcade/pcsx2x6 updates (or the cabinet's installed build
changes):
1. Read the installed `pcsx2-qtx64.exe`'s window title; extract the short
   commit hash.
2. `gh api repos/PS2Homebrew-arcade/pcsx2x6/commits/<short-hash>` (or
   browse the repo) to resolve the full 40-hex SHA and its merge date.
3. Re-fetch `pcsx2/Pcsx2Config.cpp`, `pcsx2-qt/QtHost.cpp`,
   `pcsx2/USB/USB.cpp`, `pcsx2/USB/usb-lightgun/guncon2.cpp`, and
   `pcsx2/VMManager.cpp` at the new commit; diff each citation above
   against the new source.
4. If any citation's mechanism has changed, update `contract.json`'s
   `UpstreamPinnedCommit`, the relevant `EvidenceReferences[]` entries
   (new `Commit`, updated `Description`), and this file's citations
   together, in the same change.
5. Re-run the controlled experiments in `experiments.md` against the new
   build before raising `EvidenceConfidence` or `ContractStatus`.
