# ReShade profile selection specification inventory

Status: current to the RC8 ReShade profile-selection source edits; not independently reviewed.

Process note: this REQUIRED inventory was identified after implementation had begun. It now records the complete known external contract, but its creation does not retroactively meet the standard's requirement to build the inventory before implementation. Independent review must assess this deviation before calling the slice Review Ready.

## Scope

This inventory governs the TPM-curated effect/profile deployment path (originally ten effects and twelve profiles; extended by `TPM-RESHADE-TWENTY-EFFECTS-001` to 20 effects and 22 profiles, see the addendum below), from approved effect selection through generated `ReShade.ini`. It does not govern ReShade's installer-provided `ReShade32.json` / `ReShade64.json` package extraction. That separate installer path remains covered by `RESHADE-DGVOODOO2-AUTODOWNLOAD-SPECIFICATION-INVENTORY.md`.

The principal runtime contract source is the official ReShade source at commit `18deaa52de0c425a78b329e9cb3c497281cd00ec` (ReShade 6.8.0): [`source/runtime.cpp`](https://github.com/crosire/reshade/blob/18deaa52de0c425a78b329e9cb3c497281cd00ec/source/runtime.cpp), especially `load_current_preset`, configuration initialization, and technique initialization. The effect-source contract is pinned to CeeJayDK/SweetFX commit `16d1a42247cb5baaf660120ee35c9a33bb94649c`; the shared `ReShade.fxh` contract is pinned to crosire/reshade-shaders commit `fd0022170615ce0d8162d219bff07232fa6dd84f`.

The effect/include path source is [`source/runtime.cpp`](https://github.com/crosire/reshade/blob/18deaa52de0c425a78b329e9cb3c497281cd00ec/source/runtime.cpp) (reads `GENERAL.EffectSearchPaths` and adds those roots to effect preprocessing) and [`source/effect_preprocessor.cpp`](https://github.com/crosire/reshade/blob/18deaa52de0c425a78b329e9cb3c497281cd00ec/source/effect_preprocessor.cpp) (resolves relative include names through its ordered include paths).

The pinned [`source/ini_file.cpp`](https://github.com/crosire/reshade/blob/18deaa52de0c425a78b329e9cb3c497281cd00ec/source/ini_file.cpp) serializes vector-valued settings as comma-separated values and escapes a literal comma by doubling it.

## Governed requirements

| ID | Governing requirement and source | Status | Implementation | Verification |
|---|---|---|---|---|
| `RSPS-PRESET-001` | The ReShade runtime resolves its current preset using `GENERAL.StartupPresetPath` when that path is non-empty and resolves; otherwise it uses `GENERAL.PresetPath`. The pinned runtime reads both keys and loads the selected preset. | Implemented | `Update-TpmReShadeTutorialProgressText`; `Install-TpmReShadeProfileDeployment` | `provides a complete approved include closure and valid runtime search and preset paths for every profile`; `writes and updates ReShade TutorialProgress=4 through one trusted transaction` |
| `RSPS-PRESET-002` | `load_current_preset` reads the root-level `Techniques` list from the selected preset. It disables unlisted techniques unless the effect declares `enabled`; the ten pinned catalog `.fx` files contain no `enabled` annotation. Thus an empty `Techniques=` selects no catalog technique. | Implemented | `New-TpmReShadePresetContent`; `Test-TpmReShadePresetContent`; the pinned catalog definitions | `defines twelve canonical profiles and exact effect order`; `writes and updates ReShade TutorialProgress=4 through one trusted transaction`; `contains immutable source metadata for every approved effect` |
| `RSPS-PRESET-003` | The runtime reads root-level `TechniqueSorting`; if absent or empty it falls back to `[GENERAL] TechniqueSorting`, then to the technique list. Stable sorting uses this list to order active techniques. | Implemented | `New-TpmReShadePresetContent`; `Test-TpmReShadePresetContent` | `defines twelve canonical profiles and exact effect order`; `rejects runtime technique sorting that differs from canonical effect order`; `provides a complete approved include closure and valid runtime search and preset paths for every profile` |
| `RSPS-CONFIG-004` | ReShade reads `GENERAL.EffectSearchPaths` as its effect search roots and adds those roots to the effect preprocessor. The INI vector parser uses comma-separated paths; the preprocessor resolves a relative include filename through its ordered include paths. Every source/include in the selected closure must therefore be reachable from the configured roots or the effect is incomplete. | Implemented | `Update-TpmReShadeTutorialProgressText`; `Get-TpmReShadeApprovedEffectFiles`; `Install-TpmReShadeProfileDeployment` | `provides a complete approved include closure and valid runtime search and preset paths for every profile`; `deduplicates identical shared includes when deploying the two-effect profile on a clean target` |
| `RSPS-EFFECT-005` | Each selected effect must expose the exact source-defined technique name and include directives; catalogued files must retain their source-relative names and paths. The pinned upstream sources are CeeJayDK/SweetFX at commit `16d1a42247cb5baaf660120ee35c9a33bb94649c` and FXShaders CRT_Lottes at commit `76365e35c48e30170985ca371e67d8daf8eb9a98`. | Implemented | `Get-TpmReShadeEffectCatalog`; `Get-TpmReShadeApprovedEffectFiles`; `Resolve-TpmReShadeEffectStack` | `contains immutable source metadata for every approved effect`; `defines twelve canonical profiles and exact effect order`; `provides a complete approved include closure and valid runtime search and preset paths for every profile` |

## Review boundary

The runtime source establishes file/configuration semantics, not successful shader compilation, GPU compatibility, or owner-game behavior. Those require separately authorized runtime validation and remain outside source-only proof. The official ReShade shader-package installer manifests are intentionally outside this inventory; this does not exclude the curated pinned files required by the profile-selection contract above.

## Addendum: TPM-RESHADE-TWENTY-EFFECTS-001 (20 effects, 22 profiles)

This addendum was written after implementation had started (see the slice contract's process-deviation note); it does not retroactively satisfy the inventory-first requirement.

| ID | Rule | Status |
|---|---|---|
| `RSPS-TWENTY-001` | Every effect file is fetched from raw.githubusercontent.com at an immutable commit and accepted only on its exact SHA-256 and byte length; per-effect `AllowedPathPrefix` and path-safety checks are unchanged. | Implemented; Linux-tested |
| `RSPS-TWENTY-002` | A preset section `[File.fx]` carries per-effect parameters only for a file the profile requires; ReShade reads effect uniforms from such sections. | Implemented; runtime proof open |
| `RSPS-TWENTY-003` | `TextureSearchPaths` must name the texture folders for texture-using effects (SMAA lookup textures). | Implemented; runtime proof open |
| `RSPS-TWENTY-004` | Lilium shaders compile to an inert technique outside scRGB/HDR10; HDR profiles are offered only while real display detection reports HDR on. | Implemented; real-detection proof open |
