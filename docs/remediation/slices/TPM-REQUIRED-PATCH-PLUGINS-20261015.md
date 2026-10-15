# TPM Required-Patch Managed Plugin Lane Contract

## 1. Slice identity

- Name: Remaining guide references for managed Unity/BepInEx/plugin/support assemblies.
- Contract ID: TPM-REQUIRED-PATCH-PLUGINS-20261015.
- Issue/PR: Owner-requested RC8 recipe lane; no separate issue/report ID was supplied.
- Source baseline: 44 copied validated baseline paths from review tree at `public9a9ac19`; this lane may add only its own fragment, focused synthetic test, and evidence/docs. Existing copied dirty paths are not lane deliverables.

## 2. Owner/report mapping

- Owner report IDs: None assigned for these guide references. Do not map to PR #321 owner ID 33 (FFB flow), which is a different subsystem.
- Reconciliation mapping: exact guide references and `SourcePath` evidence in `tools/required-patches/fragments/plugins-20261015.json`; lane report is `docs/remediation/slices/TPM-REQUIRED-PATCH-PLUGINS-20261015.md` plus the external evidence handoff.
- Hunk mapping: new lane-owned artifact paths only; no source-engine or Main-script hunks.
- Procedure IDs: no product-behavior hunk is planned. Owner runtime is not authorized by this lane.

## 3. Exact scope

Review all relevant guide records in cached `guide-entries.json`, the partial 95-row guide ledger, the 259-field/180-profile inventories, and the 2026-10-11 source identity indexes. Four existing recipes are already implemented: Family Guy Bowling, NERF Arcade, Rainbow BomberGirl, and TMNT. Do not duplicate or alter them.

Remaining managed-plugin references:

- Mars Sortie, exact guide build `Mars Sortie (1.46.9)(2018)[UDC PC][TP]`, executable `Shooter.exe`: the original plugin ZIP is method 93 and unsupported by the .NET reader, but its verified TorrentZip conversion is a runtime-readable exact source. The converted archive is 8,792 bytes, SHA-256 `9572836906659DFCCF07FCDAD373D247FA0967B2A1B6D6A97482B737B472DBC6`; `MSTPPlugin.dll` is 21,504 bytes, SHA-256 `3CCABD105D603EAAA7EE3CD5F7194DEBD179CC30B701113DBC5C6B564FDB1783`. Exact Main `Shooter.exe`, profile and prerequisite/member states are recorded in the lane fragment and external receipt. A lane-only absent-only recipe is included; no engine/catalog/Main edits.
- Super Bikes 3, guide build `Super Bikes 3 (1.91 x64)(2021-10-01)[Raw Thrills][TP]`: the v1.09 x64 candidate `SB3TPPlugin.dll` is 121,856 bytes, SHA-256 `9E8464FD54F272398CDE3E2AACB2D5F6D8508A2F90C3E7D7793166016BFFF3D5`; Main contains the same target member and hash, and `fnfmega.exe` SHA-256 is `7F84AE68A35587EA87312ED59247EB0379F00826B8F2473A09155792A90AEEAD`. Main inclusion does not rule out absent-only recovery, but no official `GameProfiles` XML declares `fnfmega.exe` and the `FNFSB` profile declares `sdaemon.exe`. Hold without a recipe until an exact official profile/archive binding is evidenced.
- Rabbids Hollywood: its exact Main build has `Game.exe` SHA-256 `979F9736A99745454429908227CDD2F48875F193D439CFA33A9E14B4578DA95D`; the current official profile hash is in the lane fragment. The guide-directed BepInEx operator plugin `UnityPlugin_BepInEx_RHA.dll` is source-pinned by member and Main executable, and a lane-only absent-only restore recipe is included. The separate Assembly-CSharp trigger/crosshairs fix is already covered by `rabbids-hollywood-trigger-crosshairs-restore`. Do not install the whole operator pack; it includes a registry/config utility and BepInEx core binaries that differ from Main.
- MIB's speculative future BepInEx/test-menu possibility is not a current required plugin patch. Fantasy Soccer's guide match names only an antivirus warning and runtime crash, not a managed plugin or support-assembly requirement.

## 4. Behavior and safety contract

- Add only exact-build recipes whose profile ID, executable SHA-256, prerequisites, source-set/member identity and hash, target, before-state, after-state, and undo behavior are evidenced.
- Prefer absent-only `CreateFile`; a replacement is permitted only with an exact known-before hash and verified undo.
- Never infer versions, prerequisites, filenames, payload completeness, rights, or target states from names alone.
- Never weaken the engine's source format support, runtime, extraction, containment, identity, transaction, or rollback invariants to accommodate an input.

## 5. Ownership and exclusions

- Lane-owned: `tools/required-patches/fragments/plugins-20261015.json`, a focused synthetic test under `Tests/`, and this lane contract/evidence.
- Not owned: `scripts/TpmRequiredPatchRecipes.json`, `scripts/TpmRequiredPatchEngine.ps1`, `TeknoParrot-Manager.ps1`, shared catalog, Main/Support suite, package/runtime/certification workflow.
- Exclude native I/O/drivers, graphics/audio/executable patches owned by other lanes, live game/DB/DAT/system/security changes, payload execution, dependency installation, full canonical/Main/Support suites, commit/push/PR/release actions.

## 6. Verification and runtime boundary

- Focused synthetic checks only with Pester 5.7.1 on PS7 and Windows PowerShell 5.1, invoked as `Invoke-Pester -Path .\Tests\TpmRequiredPatchPluginLane.Tests.ps1 -CI -PassThru` and checked through `FailedCount`/`PassedCount`.
- The guide-note filter `BepInEx|plugin|UnityPlugin|Assembly-CSharp|OrenVid` over cached `guide-entries.json` returns nine records; the fragment classifies all nine, including existing recipes. Synthetic transaction coverage exercises both new recipe-shaped entries through absent-plan/apply/readback, exact-after idempotent skip, receipt undo to absence, and unknown-target refusal without overwriting foreign bytes. The actual required-patch menu blocks both entries when the BepInEx core prerequisite is absent.
- The focused tests reuse the existing required-patch `BeforeEach` fixture AST and production native transaction helpers; the Main script is parsed only for selected function definitions, never dot-sourced or executed. No real game, collection, profile, or runtime writes. No owner/gameplay acceptance claim. External private paths/provenance remain in the Downloads receipt, not this tracked contract or fragment.

## 7. Stop condition

Stop after the full managed-plugin guide census is classified, every feasible recipe has a complete evidence chain and is represented only in the lane fragment, held candidates have exact reasons, focused synthetic checks pass, and handoff hashes/status are saved. If no candidate is safely feasible, deliver the held-only census rather than changing the engine or broadening scope.

## 8. Authorization

- Commit/push/PR/merge/package/release: Not authorized.
- Live runtime, collection, DAT, database, system, or security mutation: Forbidden.
