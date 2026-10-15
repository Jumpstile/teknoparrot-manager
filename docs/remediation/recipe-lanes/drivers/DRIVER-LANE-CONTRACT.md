# Driver Recipe Lane Contract

## Identity and ownership

- Lane: iDmac / JVS / NESiCA / Taito I/O / loader-driver recipe evidence.
- Contract: `TPM-RC8-DRIVERS-LANE-001`.
- Repository baseline supplied for this lane: public `9a9ac19` plus 44 copied baseline files; branch `feature/rc8-recipes-drivers-20261015`.
- Owner surface: files in this directory only. No edits to the shared engine, central recipe catalog, main script, existing tests, or shared remediation board/reconciliation.
- Parent owns global guide coverage. This lane extracts only driver-component requirements and does not claim global coverage.
- Issue/PR mapping: not supplied in the lane request; no issue identifier is invented.

## Owner report and expected result

- Owner report ID: `DRIVERS-LANE-RC8`.
- Failure to prevent: a recipe is absent for an assigned driver requirement, duplicates an existing recipe, or guesses applicability from a shared payload hash without exact game-build identity.
- Expected result: inventory each directly stated assigned driver requirement in the cached full guide; publish only new recipes for which exact target executable identity, source member bytes, target path, and before/after state are verified. Keep every unproven item held with checked sources and an autonomous next step.
- Current outcome: three additional absent-only Taisen Hot Gimmick 5 recipes are source- and executable-pinned in `driver-recipe-fragment.json`; they restore only TTX-Monitor.dll, TTX-Config.exe, and TTX-Loader.exe. The full-guide keyword census contains eight directly assigned profile/component requirements: five existing iDmac recipes, one Dragon Dance iDmac mention held on build mismatch, one Taisen TTX/JVS requirement represented by three file recipes, and one Primeval Lindbergh loader requirement held on source/target limits.

## Evidence scope and decision rules

- Guide source: cached full-guide `guide-entries.json` and its profile coverage in the October 11 task-4 evidence set. Do not substitute the curated 95-row reconciliation subset for the full guide.
- Cross-check source receipts: October 11 task-4 original-source and member identity records; October 13 task-2 main DAT mapping evidence. Only the lane's driver fields are in scope.
- Trusted artifacts are read-only. Do not execute payloads or mutate games, databases, NAS sources, official profiles, or other worktrees.
- A guide-pinned CRC/SHA or shared driver bytes do not establish game build identity. A recipe requires exact target executable SHA-256 for the guide build, exact source member SHA-256, target-relative path, and verified precondition/postcondition.
- Existing recipes for `BlazBlueContinuumShift`, `BlazBlueContinuumShift2`, `BlazBlueCrossTagBattle`, `BBCF`, and `BBCP` are excluded from this fragment. Do not duplicate, revise, or claim their central-catalog correctness from this lane.
- Dragon Dance's DDrawCompat/audio startup issue is outside this lane; its separate iDmac mention is inventoried and held because the Main archive executable does not match the guide-pinned CRC. NESYS/MTS availability notes without a pinned driver payload are not converted into recipes.

## Driver requirement mapping

| Guide profile | Driver requirement | Evidence decision | Owner action |
|---|---|---|---|
| `BlazBlueContinuumShift` | `iDmacDrv32.dll` CRC `BCB0E7FE` | Existing lane recipe; not a new entry | Excluded from fragment |
| `BlazBlueContinuumShift2` | `iDmacDrv32.dll` CRC `BCB0E7FE` | Existing lane recipe; not a new entry | Excluded from fragment |
| `BlazBlueCrossTagBattle` | `iDmacDrv32.dll` CRC `BCB0E7FE` | Existing lane recipe; not a new entry | Excluded from fragment |
| `BBCF` | `iDmacDrv32.dll` CRC `F1FF8CC9` | Existing lane recipe; not a new entry | Excluded from fragment |
| `BBCP` | `iDmacDrv32.dll` CRC `F1FF8CC9` | Existing replacement recipe; not a new entry | Excluded from fragment |
| `DragonDanceNesica` | `iDmacDrv32.dll` listed with `ddraw.dll` as the only DLLs in the game folder | Held: exact Main `game_liong.exe` CRC is `E35694FF`, not guide note `B2836DB7`; source build binding is unsafe | Locate a trusted read-only archive matching CRC `B2836DB7`, then verify its exact executable and iDmac member hashes before considering a recipe |
| `TaisenHotGimmick5` | TTX-Monitor+ loader; JVS-to-keyboard input | Three exact Main-source files bind to the guide's 2.04 `game.exe`; each is absent-only | Three separate recipes restore only the bundled loader/config programs; operator must still configure keys and run the loader |
| `Primevil` | Two Lindbergh `.so` loader libraries to `TeknoParrot/ElfLdr2/libs` | Held: exact Main archive has no matching `/data/dvr/cri/Lindbergh/libs/*.so` members; destination is outside the game's root | Parent/engine owner must evaluate a safe, role-scoped external destination and identify a trusted exact source before any recipe |
| `Akuma`, `Persona4A`, `SpaceInvaders`, `SuperStreetFighterIVArcadeEdition` | Built-in I/O emulation or NESYS/MTS behavior notes | No separate byte-pinned driver package/install requirement | Record as non-recipe behavior/content references only |
| `ShiningForceCrossRaid` | IC-card save/setup and input remapping | Full-guide card has no iDmac, JVS, NESiCA, Taito I/O, or loader package requirement | Explicitly checked; no recipe |

## Full-guide census

- Census source: all 1,888 cards in cached full-guide `guide-entries.json`; keyword scan constrained to assigned driver families, then profile-level source notes were checked for the exact hits.
- Eight direct profile/component requirements: six iDmac profiles, one TTX/JVS profile, one Lindbergh loader profile.
- Five iDmac profiles already have central recipes and remain excluded; Dragon Dance is held; Taisen contributes three safe absent-only file recipes; Primevil is held.
- Cross Raid was explicitly checked and is not an assigned driver requirement. NESYS/MTS behavior notes and generic DirectInput control choices are not driver-package requirements.

## Exact Taisen source evidence

- Main ZIP member `game.exe`: SHA-256 `144875cc9d0dc66887cd6292dcb949c0575afb654b0da8bf173fef7047c7d86a`.
- `TTX-Monitor.dll`: 147,456 bytes; SHA-1 `201bacc01d57497690d35741e70940237e424f04`; SHA-256 `a706a9dbebb3e6d4511d47341d4a46d1f9965874adba4354a127797855fdfa44`.
- `TTX-Config.exe`: 270,848 bytes; SHA-1 `00cf036a2456a4bf5bd15128269a5cd64f0ef3d9`; SHA-256 `f6979167410af3c6ece2420e15205c54eb86663b74c27aa2e1cd05287efb8b64`.
- `TTX-Loader.exe`: 11,264 bytes; SHA-1 `4b9b7174f46571a49eab6531a7577a062749e51c`; SHA-256 `2e270dde1ff0f86326a4bfcc84eb359a0231118dc03d9130526750e3d175ca3c`.
- The Main ZIP readme says to run TTX-Config, select the MAHJONG keyboard device, configure/save keys, then run TTX-Loader. `monitor_input.bin` and `monitor_misc.bin` are generated configuration outputs; this fragment does not overwrite or restore them.
- TTX-Config contains static references to the DirectInput assemblies. The TTX-Monitor v20201014 release notes scope the bundled DirectInput libraries to Linux/Wine; no such deployment is inferred for this Windows lane. No loader/config payload was executed.

## Holds and next steps

- Dragon Dance: exact Main ZIP member `game_liong.exe` has CRC-32 `E35694FF`, SHA-256 `67616b1a816013ee5ff96eeee92f9e3032b3c97fa2907e222c4e116027bc70fc`; `iDmacDrv32.dll` is 75,776 bytes, CRC-32 `55E1A010`, SHA-256 `cfd3bf5497348a168d68ecaf297f0387dfd24d8e5259f6e85caff1941a2bcc11`. The guide's `B2836DB7` executable note does not match this Main build. The named Dragon Dance patch child contains only `dinput8.zip`/`dinput8.dll`, not a matching executable or iDmac source. Next step: find a trusted read-only archive of the guide-pinned build and hash its exact executable and iDmac member.
- Primevil: guide executable is `disk0\\prog\\main.exe`; exact Main member SHA-256 `20500abe11892ea47bb111a667ba0f617cbff21bd45702d8347b5f4aeedb7224`. No `/data/dvr/cri/Lindbergh/libs/*.so` members were found in the exact Main ZIP. The guide target is outside the game folder; the current recipe engine resolves patch targets under `GameRoot` and does not provide a safe external install-root contract. Next step: parent/engine owner to identify a trusted source for the two exact loader libraries and decide whether external install targets are supported; do not guess file names or destination semantics.

## Engine capability note

- The shared schema-3 engine supports grouped transactions, but local source staging streams one exact source member into `Operations[0].Payload`. This lane uses separate one-member Taisen entries; no engine change blocks these three recipes.
- The target resolver confines recipes to the selected game root. Primevil's `TeknoParrot/ElfLdr2/libs` destination is outside that boundary, so it remains held for parent/engine owner review.

## Forbidden regressions and exclusions

- Do not edit other worktrees, master OMP session, shared engine/catalog, main script, or canonical full-suite tests.
- Do not change game/runtime files, profiles, databases, NAS data, credentials, security behavior, or release artifacts.
- Do not execute game/driver/loader payloads, install tools, perform ARCADE work, or claim runtime certification.
- Do not include binaries, private machine/NAS paths, conversation identifiers, or source paths in public fragments.
- Do not add generic completion claims based on row/recipe counts.

## Tests, runtime proof, and stop condition

- Focused check: run `pwsh -NoProfile -File .\docs\remediation\recipe-lanes\drivers\Test-DriverRecipeLane.ps1 -MainArchivePath <exact Taisen Main ZIP>`.
- The focused check composes the actual production fragment into a temporary schema-3 catalog, stages exact members read-only from the supplied ZIP into a temp root, and requires all three actual recipes to plan `Ready` through the production engine. It also applies a separate synthetic absent-only recipe to test create, idempotency, unknown-existing refusal, undo, modified-after-undo refusal, and wrong-executable refusal. No payload is executed.
- The focused test is run under PowerShell 7 and Windows PowerShell 5.1 only; do not run the full Pester suite or shared quality gates. Integration owner runs them once.
- Runtime proof is not authorized and is not required to create a source-only hold record.
- Stop when the lane files and private source receipt are written, the focused check passes, and remaining driver claims have explicit disposition/next steps. No commit, push, PR, merge, tag, package, release, or publication.

## Procedure mapping

- Procedure IDs: `TPM-TRACE-001` (source identity/evidence trace) and `TPM-OWNER-001` (owner runtime proof) remain governing procedures; this lane performs only the trace portion.
- Product source hunks: none. No product behavior or shared control-board/reconciliation files are changed by this evidence-only lane.
