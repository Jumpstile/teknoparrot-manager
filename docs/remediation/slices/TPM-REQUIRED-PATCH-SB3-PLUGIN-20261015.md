# SB3 BepInEx plugin absent-only restore (2026-10-15)

## Scope and ownership

- Slice ID: `TPM-REQUIRED-PATCH-SB3-PLUGIN-20261015`.
- Owner report ID: none supplied; this is the parent-authorized, one-entry SB3 coverage delta.
- Issue ID: none supplied.
- Governing guide card: Super Bikes 3, guide record 906, build `1.91 x64`, dated 2021-10-01, Raw Thrills.
- Official profile: `TeknoParrotUi.Common/GameProfiles/SB3.xml` at pinned TeknoParrotUI commit `d299c2b7af9704774428d6e14ba54129065e1560`; Git blob SHA-1 `8ff44ee510d1a6727ec75fa90e87ced0790c6ca7`.
- Exact artifacts owned by this slice: `tools/required-patches/fragments/plugins-sb3-20261015.json`, `Tests/TpmRequiredPatchSb3Lane.Tests.ps1`, and this contract. No central catalog, shared engine, Main script, or existing lane file is part of the slice.

## Observed failure and expected behavior

The guide requires the SB3 BepInEx plugin. The pinned official profile identifies `fnfmega.exe`, declares `RequiresBepInEx=true`, and marks the profile 64-bit. The verified matching plugin source member is `SB3TPPlugin.dll`, size 121,856, SHA-1 `E4BCCBCBB32EEE7DCE2E24AAF8990E4812BC81F5`, SHA-256 `9E8464FD54F272398CDE3E2AACB2D5F6D8508A2F90C3E7D7793166016BFFF3D5`.

The recipe is deliberately component-scoped: when the exact SB3 profile/build and source pins match, it may restore only the absent `BepInEx/plugins/SB3TPPlugin.dll`. It requires the presence of `BepInEx/core/BepInEx.dll`; that is a presence check, not a BepInEx version check. A matching target is idempotently recognized; unknown existing bytes are refused; undo returns an applied target to absence.

This recipe does not establish complete SB3 setup or launch readiness. The guide separately names Unity FMOD x64 v1.10.10 and display/GPU conditions. The FMOD archive members are separately evidenced as x64 native files at exact Main archive paths, but FMOD placement/version readiness in a runtime is unresolved and is not installed or replaced by this slice. FMOD remains held outside this managed-plugin recipe.

## Required pins and evidence

- Official XML fetched from the pinned repository commit; XML declares executable `fnfmega.exe`, BepInEx requirement, 64-bit profile, `RawThrillsFNF`, profile revision 4. Profile revision is not asserted to be the game build.
- Source mapping identifies profile SB3 and supported game build `1.91 x64`; source package SHA-256 `618EE8C44BAAF48C58BF01128585F1C2F34B06A7C9309403C30E60A764ADA92B`.
- Converted collector archive SHA-256 `1AF61E899DB36F7E96C804CBCFFA0DCB990B5804657F189D885C781C85BC5556`; member `SB3TPPlugin.dll` SHA-1/SHA-256 above.
- Main archive contains `fnfmega.exe` SHA-256 `7F84AE68A35587EA87312ED59247EB0379F00826B8F2473A09155792A90AEEAD`, BepInEx core `BepInEx/core/BepInEx.dll` SHA-256 `9FE4A88D4F949FCDB3222A05C1902FEC94F99655501E5EB60408543492CE9884`, and the exact plugin at `BepInEx/plugins/SB3TPPlugin.dll` with matching member size/SHA-1/SHA-256. This is archive evidence, not a live-runtime observation.

## Forbidden regressions and boundaries

- Never replace or overwrite an existing plugin target; only absent-state creation is in scope.
- Never claim BepInEx version compatibility from the core-file presence prerequisite.
- Never infer FMOD destinations from a flat archive or install/replace FMOD DLLs in this slice.
- Never claim a successful plugin restore means complete SB3 setup, FMOD readiness, or launch readiness.
- No payload execution, live game/runtime changes, dependency installation, full test suites, central catalog edits, or shared-engine edits.
- The previously frozen Mars/Rabbids fragment, plugin-lane tests, and lane contract remain unchanged.

## Tests and proof

- Before/with implementation: run only `Tests/TpmRequiredPatchSb3Lane.Tests.ps1` under Windows PowerShell 5.1 and PowerShell 7, each with Pester exactly 5.7.1. Require explicit pass/fail counts and nonzero exit on failure.
- Focused synthetic behavior must cover missing BepInEx core refusal, absent target plan/apply/readback, exact-after idempotency, undo to absence, and unknown-existing-byte refusal. The fixture must not execute the payload.
- Static source evidence must establish exact profile/executable/build/source/member hashes and the exact core prerequisite path. SHA-1 format is exactly 40 hexadecimal characters.
- No live-runtime proof is authorized or claimed. If either pinned metadata or the focused lifecycle path fails, stop and keep the SB3 delta out of integration.

## Mapping and stop condition

The SB3 fragment entry and focused lifecycle assertions map to this slice ID. No product-engine procedure is modified; no separate procedure or issue ID was supplied. Stop if profile/build binding, archive/member hashes, core prerequisite path, absent-only semantics, focused proof, or scope separation cannot be verified. Parent integration must retain the explicit plugin-only limitation and separate FMOD-held status.
