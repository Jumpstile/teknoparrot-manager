# Driver Lane Evidence and Holds

Lane contract: `TPM-RC8-DRIVERS-LANE-001`. This is a lane-only extraction from the complete cached guide, not global coverage, runtime certification, or a claim that any game is playable.

## Full-guide driver keyword census

- Source: all 1,888 full-guide cards in cached `guide-entries.json`; assigned-keyword hits were checked against the exact profile notes. The curated 95-card reconciliation was not used as the census boundary.
- Eight profile/component requirements: six iDmac profiles, one TTX/JVS loader profile, one Lindbergh loader profile.
- Five iDmac profiles are already represented by central recipes and are excluded from this fragment: `BlazBlueContinuumShift`, `BlazBlueContinuumShift2`, `BlazBlueCrossTagBattle`, `BBCF`, and `BBCP` (the existing `BBCP` recipe is a replacement, not an absent-only duplicate).
- New fragment: three absent-only `TaisenHotGimmick5` files. The profile requirement is one TTX-Monitor+ JVS-to-keyboard loader setup; the three files do not implement keyboard selection, config creation, loader invocation, or gameplay compatibility.
- Held: `DragonDanceNesica` iDmac binding and `Primevil` Lindbergh loader libraries. Exact sources and autonomous next steps are in `driver-lane-inventory.json`.
- `ShiningForceCrossRaid` was explicitly checked; its full-guide card describes IC-card save/setup and input remapping, not an assigned driver package. No Cross Raid recipe.
- Non-recipe/out-of-lane references: `Akuma` describes built-in I/O emulation; `Persona4A`, `SpaceInvaders`, and `SuperStreetFighterIVArcadeEdition` describe NESYS/MTS behavior without a pinned driver package. Dragon Dance DDrawCompat/audio instructions are outside this lane. Generic DirectInput controller choices are not binary driver requirements.

## Taisen source binding

Guide build and exact source set: `Taisen Hot Gimmick 5 - Mirai Eigou (2.04)(2005-12-08)(JPN)[Taito Type X][TP].zip`; all source probes were read-only.

| Main ZIP member | Size | SHA-1 | SHA-256 |
|---|---:|---|---|
| `game.exe` | 1,712,128 | `44d902f31677eee628ff6bf3aee934d12957b9b6` | `144875cc9d0dc66887cd6292dcb949c0575afb654b0da8bf173fef7047c7d86a` |
| `TTX-Monitor.dll` | 147,456 | `201bacc01d57497690d35741e70940237e424f04` | `a706a9dbebb3e6d4511d47341d4a46d1f9965874adba4354a127797855fdfa44` |
| `TTX-Config.exe` | 270,848 | `00cf036a2456a4bf5bd15128269a5cd64f0ef3d9` | `f6979167410af3c6ece2420e15205c54eb86663b74c27aa2e1cd05287efb8b64` |
| `TTX-Loader.exe` | 11,264 | `4b9b7174f46571a49eab6531a7577a062749e51c` | `2e270dde1ff0f86326a4bfcc84eb359a0231118dc03d9130526750e3d175ca3c` |

The three driver/config members have byte-identical hashes to the cached TTX-Monitor v20201014 author release receipt. The Main ZIP readme directs the operator to configure/save keys with `TTX-Config.exe`, then run `TTX-Loader.exe`. `monitor_input.bin` and `monitor_misc.bin` exist in the Main ZIP but remain unmodified config outputs. TTX-Config static strings name DirectInput assemblies; the author release notes identify those assemblies for Linux/Wine, so this Windows lane creates no DirectInput recipe. No TTX/game payload was executed.

## Engine validation

`Test-DriverRecipeLane.ps1` composes a temporary schema-3 catalog `{ Schema: 3, Entries: fragment.Entries }` without editing the central catalog. It streams the exact Main `game.exe` and three source members into a temporary test root and requires each production fragment entry to return `Ready` through `Get-TpmPatchPlan`. It then exercises the production engine with synthetic bytes: absent create, exact-after idempotency, unknown-existing refusal without mutation, undo to absent, wrong-executable refusal, and modified-after-apply undo refusal without changing the modified target.

PowerShell 7.6.7 transcript: `engine-smoke-ps7-20261015-005248-953.txt`; exit code 0. Windows PowerShell 5.1 transcript is recorded separately in the owner evidence store. These are isolated engine/source checks only, not game/runtime or owner certification.

## Ownership and integration boundary

Only these new lane files are intended for integration: `DRIVER-LANE-CONTRACT.md`, `DRIVER-LANE-EVIDENCE.md`, `driver-lane-inventory.json`, `driver-recipe-fragment.json`, `Test-DriverRecipeLane.ps1`, and `DRIVER-LANE-FILES.sha256`. No existing central recipe, engine, main script, full-suite test, shared board, or reconciliation file is edited.

The engine can transact grouped files but local source staging reads one exact source member into `Operations[0].Payload`; separate one-member entries avoid that limitation. Primevil's target is outside the game root and remains held for the parent/engine owner. The central catalog and release files remain unchanged.
