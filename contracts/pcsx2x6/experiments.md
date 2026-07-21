# Controlled Experiments: pcsx2x6

Distinct from `evidence.md`'s source citations -- this file records what was
actually run and observed, which is what lets `EvidenceConfidence` values
graduate from `SourceVerified` to `ExperimentVerified`/`HardwareVerified`.

## exp-001-clean-copy-testconfig

**Environment**: isolated scratch copies of the real pcsx2x6 install
(binaries/DLLs/resources copied via robocopy, PDB files excluded, the
existing `TeknoParrot\` config subfolder excluded so each copy starts from
a genuine first-run state). No live arcade data was touched at any point.

**Steps and raw results**:
1. Ran `pcsx2-qtx64.exe -testconfig -portable` against a clean copy with an
   empty `portable.txt`.
   - Exit code: 0
   - Duration: 1774 ms
   - No window observed (polled `MainWindowHandle` every 25ms for up to
     5s; never became non-zero before the process exited)
   - Resulting tree: full `TeknoParrot\` subfolder created (bios, cache,
     cheats, covers, gamesettings, inis, inputprofiles, logs, memcards,
     patches, resources, snaps, sstates, textures, videos)
   - `TeknoParrot\inis\PCSX2.ini` created; SHA-256 recorded.
   - Ini contains `[USB1]`, `[USB2]`, `[JVS]` sections by default.
2. Re-ran the identical command against the same copy (ini already
   present).
   - Exit code: 0
   - Duration: 227 ms (~8x faster than the cold run)
   - Ini SHA-256 identical before and after -- confirms idempotent,
     `IsDirty()`-gated save; nothing rewritten when nothing changed.
3. Created a second clean copy; set `portable.txt` content to the literal
   string `CustomDataRoot` (no trailing newline); ran the same command.
   - Exit code: 0
   - Duration: 636 ms
   - Resulting tree: a `CustomDataRoot\` subfolder was created; no
     `TeknoParrot\` folder at all.
   - `CustomDataRoot\inis\PCSX2.ini` exists.

**Conclusion**: matches `ev-portable-root` and `ev-testconfig-init`
exactly. `EvidenceConfidence` for both raised to `ExperimentVerified`.
Note: this experiment ran `-testconfig -portable` cold-launch behavior
only. It did not launch an actual game/title, so it says nothing yet about
`ev-guncon2-clear` or `ev-vmmanager-jvsmode` -- see the pending experiment
below.

## exp-002-jvs-runtime-signal (PENDING -- not yet run)

**Purpose**: resolve the two `Unconfirmed` entries in
`contract.json`'s `RuntimeCapabilities[0].ObservableEvidence`, i.e.
determine which of the following is the reliable, authoritative signal
that a real title reached `JVS_MODE::LIGHTGUN` with `Type=guncon2`:
1. The `ACGAME: jvsmode=lightgun -> GunCon2 on USB1+USB2` log line
   reaching a file under `<DataRoot>\logs\`.
2. `Host::SetBaseStringSettingValue("USB1"/"USB2", "Type", "guncon2")`
   surviving to the persisted ini after a clean shutdown.
3. Neither being reliably observable from outside the process, in which
   case this RuntimeCapability may need a different `EvidenceSourceType`
   not yet in this contract's vocabulary.

**Planned procedure** (requires live-hardware authorization before
running -- explicitly held pending review, not run as part of authoring
this contract package):
1. Back up `pcsx2x6\TeknoParrot\` in full (small, no BIOS/ISO data) to a
   timestamped location; record its SHA-256 tree hash.
2. Launch one confirmed `GunGame=true` title (e.g. Time Crisis 4 --
   `timecrs4.xml`, serial `NM00032`) through TeknoParrot normally; let it
   run briefly; exit cleanly.
3. Inspect `<DataRoot>\logs\` for the ACGAME log line; inspect
   `<DataRoot>\inis\PCSX2.ini` for `[USB1]`/`[USB2] Type`.
4. Restore `TeknoParrot\` from the backup; verify the restored tree's hash
   matches the pre-experiment hash.
5. Record the outcome here, update `contract.json`'s
   `RuntimeCapabilities[0].ObservableEvidence[].Status` for whichever
   entry (if any) is confirmed, and advance `CapabilityStatus` from
   `Investigating` accordingly.

Until this experiment runs and is recorded, `contract.json` deliberately
encodes no confirmed runtime-evidence source -- an unconfirmed hypothesis
must never be treated as authoritative.
