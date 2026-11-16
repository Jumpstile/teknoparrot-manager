# ReShade profile selection specification inventory

Status: current to the RC8 ReShade profile-selection source edits; not independently reviewed.

Process note: this REQUIRED inventory was identified after implementation had begun. It now records the complete known external contract, but its creation does not retroactively meet the standard's requirement to build the inventory before implementation. Independent review must assess this deviation before calling the slice Review Ready.

## Scope

This inventory governs the TPM-curated effect/profile deployment path (originally ten effects and twelve profiles; extended by `TPM-RESHADE-TWENTY-EFFECTS-001` to 20 effects and 22 profiles, see the addendum below; the FIX46 arcade catalog offered 12 profiles built from 7 of the 20 effects; FIX51 (issue #383) adds five effects and five looks, so the catalog now has 25 effects and offers 17 profiles -- Original plus 16 arcade looks -- built from 12 of the 25 effects, which all stay cataloged), from approved effect selection through generated `ReShade.ini`. It does not govern ReShade's installer-provided `ReShade32.json` / `ReShade64.json` package extraction. That separate installer path remains covered by `RESHADE-DGVOODOO2-AUTODOWNLOAD-SPECIFICATION-INVENTORY.md`.

The principal runtime contract source is the official ReShade source at commit `18deaa52de0c425a78b329e9cb3c497281cd00ec` (ReShade 6.8.0): [`source/runtime.cpp`](https://github.com/crosire/reshade/blob/18deaa52de0c425a78b329e9cb3c497281cd00ec/source/runtime.cpp), especially `load_current_preset`, configuration initialization, and technique initialization. The effect-source contract is pinned to CeeJayDK/SweetFX commit `16d1a42247cb5baaf660120ee35c9a33bb94649c`; the shared `ReShade.fxh` contract is pinned to crosire/reshade-shaders commit `fd0022170615ce0d8162d219bff07232fa6dd84f`.

The effect/include path source is [`source/runtime.cpp`](https://github.com/crosire/reshade/blob/18deaa52de0c425a78b329e9cb3c497281cd00ec/source/runtime.cpp) (reads `GENERAL.EffectSearchPaths` and adds those roots to effect preprocessing) and [`source/effect_preprocessor.cpp`](https://github.com/crosire/reshade/blob/18deaa52de0c425a78b329e9cb3c497281cd00ec/source/effect_preprocessor.cpp) (resolves relative include names through its ordered include paths).

The pinned [`source/ini_file.cpp`](https://github.com/crosire/reshade/blob/18deaa52de0c425a78b329e9cb3c497281cd00ec/source/ini_file.cpp) serializes vector-valued settings as comma-separated values and escapes a literal comma by doubling it.

## Governed requirements

| ID | Governing requirement and source | Status | Implementation | Verification |
|---|---|---|---|---|
| `RSPS-PRESET-001` | The ReShade runtime resolves its current preset using `GENERAL.StartupPresetPath` when that path is non-empty and resolves; otherwise it uses `GENERAL.PresetPath`. The pinned runtime reads both keys and loads the selected preset. | Implemented | `Update-TpmReShadeTutorialProgressText`; `Install-TpmReShadeProfileDeployment` | `provides a complete approved include closure and valid runtime search and preset paths for every profile`; `writes and updates ReShade TutorialProgress=4 through one trusted transaction` |
| `RSPS-PRESET-002` | `load_current_preset` reads the root-level `Techniques` list from the selected preset. It disables unlisted techniques unless the effect declares `enabled`; the ten pinned catalog `.fx` files contain no `enabled` annotation, and neither do CRT-Pi and the five FIX51 RSRetroArch files (checked by searching the saved bytes for `enabled`). Thus an empty `Techniques=` selects no catalog technique. | Implemented | `New-TpmReShadePresetContent`; `Test-TpmReShadePresetContent`; the pinned catalog definitions | `defines 17 canonical profiles (Original plus 16) over 12 of the 25 effects, in arcade order, with exact effect order and parameter sections`; `writes and updates ReShade TutorialProgress=4 through one trusted transaction`; `contains immutable source metadata for every approved effect` |
| `RSPS-PRESET-003` | The runtime reads root-level `TechniqueSorting`; if absent or empty it falls back to `[GENERAL] TechniqueSorting`, then to the technique list. Stable sorting uses this list to order active techniques. | Implemented | `New-TpmReShadePresetContent`; `Test-TpmReShadePresetContent` | `defines 17 canonical profiles (Original plus 16) over 12 of the 25 effects, in arcade order, with exact effect order and parameter sections`; `rejects runtime technique sorting that differs from canonical effect order`; `provides a complete approved include closure and valid runtime search and preset paths for every profile` |
| `RSPS-CONFIG-004` | ReShade reads `GENERAL.EffectSearchPaths` as its effect search roots and adds those roots to the effect preprocessor. The INI vector parser uses comma-separated paths; the preprocessor resolves a relative include filename through its ordered include paths. Every source/include in the selected closure must therefore be reachable from the configured roots or the effect is incomplete. | Implemented | `Update-TpmReShadeTutorialProgressText`; `Get-TpmReShadeApprovedEffectFiles`; `Install-TpmReShadeProfileDeployment` | `provides a complete approved include closure and valid runtime search and preset paths for every profile`; `deduplicates identical shared includes when deploying the two-effect profile on a clean target` |
| `RSPS-EFFECT-005` | Each selected effect must expose the exact source-defined technique name and include directives; cataloged files must retain their source-relative names and paths. The pinned upstream sources are CeeJayDK/SweetFX at commit `16d1a42247cb5baaf660120ee35c9a33bb94649c` and FXShaders CRT_Lottes at commit `76365e35c48e30170985ca371e67d8daf8eb9a98`; since FIX51 also Matsilagi/RSRetroArch at commit `73dc21fcc9f1e1d6e4bf0f1c5c95b882078d474d` (CRT-Pi, CRT-Geom, CRT-Aperture, CRT-Easymode, CRT-Hyllian, CRT-ZFast). | Implemented | `Get-TpmReShadeEffectCatalog`; `Get-TpmReShadeApprovedEffectFiles`; `Resolve-TpmReShadeEffectStack` | `contains immutable source metadata for every approved effect`; `defines 17 canonical profiles (Original plus 16) over 12 of the 25 effects, in arcade order, with exact effect order and parameter sections`; `provides a complete approved include closure and valid runtime search and preset paths for every profile` |

## Review boundary

The runtime source establishes file/configuration semantics, not successful shader compilation, GPU compatibility, or owner-game behavior. Those require separately authorized runtime validation and remain outside source-only proof. The official ReShade shader-package installer manifests are intentionally outside this inventory; this does not exclude the curated pinned files required by the profile-selection contract above.

## Addendum: TPM-RESHADE-TWENTY-EFFECTS-001 (20 effects; 22 profiles at that time, 12 profiles after the FIX46 arcade catalog, 25 effects and 17 profiles since FIX51)

This addendum was written after implementation had started (see the slice contract's process-deviation note); it does not retroactively satisfy the inventory-first requirement.

| ID | Rule | Status |
|---|---|---|
| `RSPS-TWENTY-001` | Every effect file is fetched from raw.githubusercontent.com at an immutable commit and accepted only on its exact SHA-256 and byte length; per-effect `AllowedPathPrefix` and path-safety checks are unchanged. | Implemented; Linux-tested |
| `RSPS-TWENTY-002` | A preset section `[File.fx]` carries per-effect parameters only for a file the profile requires; ReShade reads effect uniforms from such sections. Since FIX51 the five new CRT looks use it (`[CRTGeom.fx]`, `[CRTAperture.fx]`, `[CRTEasymode.fx]`, `[CRTHyllian.fx]`, `[zfast_crt.fx]`, keys taken from the .fx uniform names, values written as strings; only `^[A-Za-z_][A-Za-z0-9_]*=-?[0-9]+(?:\.[0-9]+)?$` lines are accepted in a section). | Implemented; runtime proof open; FIX51 tests not run |
| `RSPS-TWENTY-003` | `TextureSearchPaths` must name the texture folders for texture-using effects (SMAA lookup textures). | Implemented; runtime proof open |
| `RSPS-TWENTY-004` | Lilium shaders compile to an inert technique outside scRGB/HDR10; HDR profiles are offered only while real display detection reports HDR on. | Implemented; real-detection proof open |
| `RSPS-TWENTY-005` | FIX51 / issue #383: the five new effects `RSRetroArch.CRTGeom`, `RSRetroArch.CRTAperture`, `RSRetroArch.CRTEasymode`, `RSRetroArch.CRTHyllian` and `RSRetroArch.CRTZFast` are fetched from raw.githubusercontent.com at the immutable commit `73dc21fcc9f1e1d6e4bf0f1c5c95b882078d474d` of Matsilagi/RSRetroArch (`AllowedPathPrefix` `/Matsilagi/RSRetroArch/73dc21fcc9f1e1d6e4bf0f1c5c95b882078d474d/`, required include `ReShade.fxh`) and accepted only on exact SHA-256 and byte length (`Shaders/CRTGeom.fx` 12140, `Shaders/CRTAperture.fx` 6700, `Shaders/CRTEasymode.fx` 9104, `Shaders/CRTHyllian.fx` 10041, `Shaders/zfast_crt.fx` 4212). Technique names: `GeomCRT`, `ApertureCRT`, `EasymodeCRT`, `CRTHyllian`, `CRTZFast`. License basis: GPL-2.0-or-later (CRT-Geom, CRT-ZFast), MIT in-file notice (CRT-Hyllian), "License: GPL" with no version (CRT-Aperture, CRT-Easymode; owner decision pending). Preset values per look are recorded in `RPSI-TWENTY-010`; the 640x480 size is an assumption for the usual arcade picture size and the look on real games is not measured. Preview renderer version 6. | Implemented; FIX51 tests not run |

## Finite-buffer console contract -- before implementation, 2026-10-24

Owner IDs 1/9; #323; TPM-RC8-RESHADE-CONSOLE-BUFFER-001.

| ID | Governing requirement | Status | Implementation / proof |
|---|---|---|---|
| RSPS-CONSOLE-001 | Console.SetCursorPosition accepts top strictly below BufferHeight, never the next row after a full buffer. Console output/newline performs natural scrolling. Microsoft System.Console API governs the terminal, not ReShade file semantics. | SOURCE FIXED; OWNER RUNTIME NEEDED | Baseline native 32-row probe fails at top30; current unmocked 120x30/32-row probes pass both engines without buffer enlargement; final frozen aggregate pending |
| RSPS-CONSOLE-002 | Redirected/unsupported cursor geometry cannot establish an addressable console layout; append-only output must preserve all lines. | Focused source proof passed; final frozen aggregate pending | Finite-buffer blank/wrapped/fallback and post-scroll in-place cases pass; initial-render resize red/green and final 60-case cohort pass both engines |

Source: https://learn.microsoft.com/en-us/dotnet/api/system.console.setcursorposition .
No row clamping/dropping, enlarged test buffer, or swallowed positioning error
is an implementation of this contract.
