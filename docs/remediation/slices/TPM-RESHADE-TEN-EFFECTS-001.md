# ReShade ten-effect selection slice

## 1. Slice name

- Name: Pinned ten-effect ReShade catalog with direct preview selection
- Contract ID: `TPM-RESHADE-TEN-EFFECTS-001`
- Issue/PR: PR #321
- Authorization: the user explicitly authorized direct profile selection in the ReShade preview as a feature-freeze exception in this conversation; no other new capability scope is authorized.

## 2. Owner report IDs included

- IDs: 1, 9, and 10.
- Exact handoff requirements: retain safe no-change/Back/cancel behavior; keep all twelve canonical profiles backed by at least ten pinned shader effects; allow direct selection in the preview and preserve terminal selection as an alternate route to the same `SelectedProfileId`; keep preview state synchronized; preserve the working comparison slider and Before/After/Split/Slider modes; close the preview automatically on chooser completion and every existing cancel/close path.

## 3. Explicit exclusions

- No ReShade runtime binaries or shader source files are bundled. Effects remain live-fetched from allowlisted pinned upstream URLs and validated by exact SHA-256.
- No shader execution in preview, game launch, runtime smoke, package build, merge, tag, publication, wiki push, or certification. Scoped commit/push to PR #321's existing head is authorized only after fresh required source gates and independent exact-diff review.
- No new parameter editor, profile persistence redesign, network retry, compatibility recommendation, or measured-performance claim.

## 4. Behavior contract

- Pre-slice baseline: the approved catalog contained three shader effects, the terminal chooser had a fixed five-profile limit, and the preview renderer only approximated those five profiles.
- Expected behavior: retain the five existing profiles and add seven individually selectable beginner-facing profiles, for twelve profiles total and ten pinned shader effects total. Each new effect has exact repository, immutable commit, source-relative file, SHA-256, byte length, MIT license, attribution, include requirements, and approved raw GitHub host/path metadata. The terminal chooser derives its numbered range from the supplied canonical profile list; choosing any number from 1 through 12 selects that canonical profile and synchronizes the preview. Each profile produces a deterministic TPM-owned approximation from the bundled landscape image; preview sliders and view modes remain functional. At the resolver boundary, repeated approved effect IDs normalize to one copy in first-request order, while unknown IDs are rejected; canonical profile definitions remain duplicate-free. Returning from the chooser closes the manager-owned preview…
- Direct-selection behavior: the non-modal gallery provides a visible drop-down containing all twelve canonical profile definitions (at least ten choices, with the current catalog exposing twelve profiles backed by ten unique effects). A valid preview choice updates the shared `SelectedProfileId` and refreshes the approximation. Terminal number selection updates the same state; after the input pump processes preview events, `U` returns the latest canonical profile, not a stale terminal-local value. Preview selection remains transient and cannot deploy files, save configuration, or bypass terminal `U` plus the existing explicit confirmation. If the gallery is unavailable or closed, terminal selection remains usable.
- Forbidden regressions: no unpinned URL, unverified effect or include bytes, missing include closure, missing ReShade effect search paths or preset linkage, duplicate emitted effect-stack or target entries, unknown effect acceptance, ignored gallery selector, hard-coded five-profile limit, false shader-execution claim, changed effect ordering, preset injection, or release bundle of ReShade binaries/effect source files. Repeated approved IDs normalize to their first occurrence. Compatibility stays `ADVISORY_UNMEASURED` and `Recommended` remains false.

- Slider/selection boundary: the non-modal gallery exposes a 0-100 comparison TrackBar whose guarded drag events remain coalesced at 16 ms and whose keyboard KeyUp updates immediately. Choosing any displayed profile in the gallery or terminal updates the same validated `SelectedProfileId`; neither route changes slider position or view mode. Slider input changes only view mode/position. `U` uses the latest selection and `B`/`N` remain non-mutating. Automatic close and disposal of the owned gallery remain intact.

## 5. Source/function ownership

- Files: `TeknoParrot-Manager.ps1`; `Tests/TeknoParrot-Manager.Tests.ps1`; `scripts/Run-TpmQualityGate.ps1`; `ARCHITECTURE.md`; `LICENSE`; `TeknoParrot-Manager-README.txt`; `README.md`; `TeknoParrot-Manager-CHANGELOG.txt`; `docs/RESHADE-PROFILE-SELECTION-SPECIFICATION-INVENTORY.md`; `docs/RESHADE-PROFILE-SELECTION-INVARIANT-INVENTORY.md`; `docs/RESHADE-DGVOODOO2-AUTODOWNLOAD-SPECIFICATION-INVENTORY.md`; `docs/RESHADE-DGVOODOO2-AUTODOWNLOAD-INVARIANT-INVENTORY.md`; `docs/remediation/PR-321-control-board.md`; `docs/remediation/PR-321-reconciliation.md`; `docs/remediation/slices/PR-321-current-slice.md`.
- Additional release-state documentation: `QUICKSTART.md`; `SECURITY.md`; `RELEASE-SAFETY-CHECKLIST.md`; `docs/AUTO_UPDATE.md`; `docs/TPM-CERTIFICATION-SUITE.md`; `docs/ENGINEERING-WORKFLOW.md`.
- Additional coordinated documentation: `TeknoParrot-Manager-QuickStart.txt`; `docs/wiki-updates/Home.md`; `docs/wiki-updates/Quick-Start.md`; `docs/wiki-updates/Changelog.md`; `docs/wiki-updates/ReShade.md` (insert-only staging patch; no live wiki update).
- Functions/regions: `Get-TpmReShadeProfiles`; `Get-TpmReShadeEffectCatalog`; `Get-TpmReShadeApprovedEffectFiles`; `Acquire-TpmReShadeApprovedEffect`; `Test-TpmReShadePresetContent`; `Update-TpmReShadeTutorialProgressText`; `Install-TpmReShadeProfileDeployment`; `Invoke-TpmReShadePreviewProfilePixels`; `New-TpmReShadePreviewPaintHandler`; `Get-TpmReShadePreviewStateValue`; `New-TpmReShadeGalleryEventHandlers`; `Flush-TpmReShadeGallerySlider`; `Show-TpmReShadeProfileGalleryWindow`; `Sync-TpmReShadeGallerySelection`; `Close-TpmReShadeProfileGallerySession`; `Read-TpmReShadeTerminalProfile`.
- Gate freshness: `scripts/Run-TpmQualityGate.ps1` includes both profile-selection inventories and the adjacent installer inventory pair in `$freshnessPaths`; `requires the TPM remediation and prompt-slice artifacts` verifies their presence and freshness-list membership.
- Upstream provenance for the seven added SweetFX effects: `CeeJayDK/SweetFX`, commit `16d1a42247cb5baaf660120ee35c9a33bb94649c`, repository `LICENSE` MIT, copyright `CeeJayDK`.
  - `Shaders/SweetFX/Cartoon.fx`: 1,378 bytes; SHA-256 `5D90E1C72318A28255D268FF3AC3FCB64D1E9469F5CA1334A50FB7D1B1A005F4`.
  - `Shaders/SweetFX/Curves.fx`: 6,274 bytes; SHA-256 `8368029D2254856505ABF7DD789342024465403DA49434DD776C6D1AF4079A98`.
  - `Shaders/SweetFX/FilmGrain.fx`: 3,514 bytes; SHA-256 `520F0C40247C457A23A8F66A761C71EB43E5CA85DB5F68A92F1FBF0700F37154`.
  - `Shaders/SweetFX/Levels.fx`: 2,976 bytes; SHA-256 `C603D3EA12D6D5710F2246BB7DD446D19E561154656F1FA8D579CA7FBBEEF70E`.
  - `Shaders/SweetFX/Monochrome.fx`: 3,183 bytes; SHA-256 `36E0C42CE96F7CA61D44FDEEDBDB2E2B859D3359B29AD1E5DC3F1772D3B2459E`.
  - `Shaders/SweetFX/Sepia.fx`: 549 bytes; SHA-256 `4A4C7B4A3CC6CDF717AA96F0D3586B98C143A5584A29FD3A9D57AECD895B0BC6`.
  - `Shaders/SweetFX/Vignette.fx`: 3,502 bytes; SHA-256 `A7358B592830FA74A0A50A842682C99DB751E35666E49C229567DAF9EA59AFA2`.
- Shared include closure: `ReShade.fxh` is live-fetched from `crosire/reshade-shaders`, commit `fd0022170615ce0d8162d219bff07232fa6dd84f`, source `Shaders/ReShade.fxh`, 4,250 bytes, SHA-256 `6DABFBBAF968C3871905D2EA17F96572FF7B1CEC01310B5D0E5252B66B30174F`, SPDX `CC0-1.0`. `ReShadeUI.fxh` is a TPM-authored deterministic compatibility shim defining only `__UNIFORM_SLIDER_FLOAT1`, `__UNIFORM_SLIDER_FLOAT2`, `__UNIFORM_SLIDER_INT1`, and `__UNIFORM_COLOR_FLOAT3`; no upstream UI header source is copied.
- Deployment destinations: shader files under `Shaders` / `Shaders\\SweetFX`, shared includes under `Shaders\\TPM`; the transaction owns and rolls back these files with the runtime and configuration. `[GENERAL] EffectSearchPaths` lists `.\Shaders,.\Shaders\SweetFX,.\Shaders\TPM`; `[GENERAL] PresetPath` and `[GENERAL] StartupPresetPath` are both set to `.\ReShade.ini`, binding the generated root-level technique list in that same file to ReShade even when a previous startup preset override was present.
- Each added `.fx` imports only `ReShadeUI.fxh` and `ReShade.fxh`; the selected `CRT_Lottes.fx` additionally imports the catalogued `CRT_Lottes.fxh`. No effect-specific texture dependency is included.

Pinned ReShade 6.8.0 runtime source at commit `18deaa52de0c425a78b329e9cb3c497281cd00ec` establishes that `StartupPresetPath` takes precedence over `PresetPath`, and that a missing/empty preset `TechniqueSorting` falls back to `[GENERAL] TechniqueSorting`. Every generated profile therefore writes `Techniques` and `TechniqueSorting` in the same canonical order; Original writes both empty. The validator rejects divergence. These runtime-format findings are enumerated in `RESHADE-PROFILE-SELECTION-SPECIFICATION-INVENTORY.md`; deployment and preview guarantees are mapped in `RESHADE-PROFILE-SELECTION-INVARIANT-INVENTORY.md`.

Process deviation: the two required inventories were identified after implementation had begun, rather than being built before the governed changes. Their current contents do not retroactively satisfy the standard's timing requirement; independent review must assess this deviation before the slice is called Review Ready.

- Characterization: retain canonical profile order, direct preview and terminal selection synchronization, slider boundaries and keyboard behavior, preview close, immutable upstream metadata, and protected deployment behavior.
- Pre-implementation regressions: replace terminal-authority/no-gallery-control tests with failing behavior checks for the gallery selector, canonical profile identity, both-way synchronization, acceptance of a preview selection after the terminal input pump, and selection/view/slider independence. Capture the current twelve-profile/ten-effect catalog count and automatic close path before changing production source.
- Behavior: exact catalog/profile counts; all effect `RelativeFiles`, `SHA256`, and `ByteLengths` arrays have matching cardinality; each profile produces a generated preset accepted by the catalog-derived technique allowlist; every selected effect's declared include closure has an approved source or TPM-authored shim. `rejects unknown effects and normalizes repeated approved effects in first-seen order` proves duplicate-ID normalization and rejection behavior.
- Clean-target deployment: table-driven proof deploys all twelve canonical profiles with no pre-existing shader files. For each profile, exercise transactional staging and verify the complete effect/include closure at expected target paths, canonical `[GENERAL] EffectSearchPaths`, `PresetPath`, and `StartupPresetPath`, and ownership entries for every promoted file. Original must deploy no shader assets.
- Preset conformance: all twelve generated presets carry canonical `Techniques` and `TechniqueSorting`; sorting divergence is rejected, and Original carries both lists empty.
- Shared include boundary: identical same-path includes deduplicate once; mismatched hash/byte-length identities fail before target promotion and leave target files and ownership unchanged.
- Selection/preview: exercise every gallery item (twelve canonical profiles backed by ten effects), including the first and twelfth identities. A valid preview selector event updates `SelectedProfileId` and refreshes that canonical profile; invalid/malformed items fail closed. A terminal choice updates the selector; a preview choice made while terminal input pumps messages is the profile returned by `U`, not stale local state. Selection leaves ViewMode and slider position unchanged. Every profile renders a deterministic output distinct from the baseline; slider extremes and automatic teardown after accept/cancel remain correct.
- Regression suite: full main Pester suite under Pester 5.7.1 in PowerShell 7 and Windows PowerShell 5.1; SupportPackage Pester suite under Pester 5.7.1.
- Static and procedure gates: PowerShell parse/ASCII, PSScriptAnalyzer, InjectionHunter, `git diff --check`, and `TPM-RESHADE-001`, `TPM-EVIDENCE-001`, `TPM-OWNER-002`, `TPM-OWNER-003`, `TPM-TRACE-001`, and `TPM-AUTH-001`.

- Keep the architecture, README.md, release README, changelog, canonical owner table, and control board synchronized to the twelve-profile/ten-effect behavior and its include/config deployment contract.
- Add this contract to the current-slice pointer and permanent-gate freshness inputs.
- Hunk classification: PR #321 / owner IDs 1, 9, and 10 / `TPM-RESHADE-TEN-EFFECTS-001` / `TPM-RESHADE-001` / `TPM-EVIDENCE-001` / `TPM-OWNER-002` / `TPM-OWNER-003` / `TPM-TRACE-001` / `TPM-AUTH-001`.
- Candidate version: bump the unpublished candidate from RC8 to RC8 for this product-behavior change. No package build/validation, tag, publication, live wiki update, certification, or release is authorized; wiki staging may be updated.

## 9. Permanent procedure IDs affected

- `TPM-RESHADE-001`: retain ownership checks, live acquisition allowlists, per-game profile selection, and existing deployment transaction boundaries.
- `TPM-EVIDENCE-001`: tests must exercise canonical effect selection, actual deploy-preflight inputs, and deterministic preview output.
- `TPM-OWNER-002` / `TPM-OWNER-003`: separate source proof from package/owner-runtime proof.
- `TPM-TRACE-001`: map every source/test/documentation hunk to this contract and PR #321 owner IDs 1, 9, and 10.
- `TPM-AUTH-001`: no release, package, wiki push, commit, or owner-smoke authority is implied.

## 10. Runtime smoke checklist

- Exact packaged behavior, if separately authorized later: directly select at least ten catalog-backed profiles in the preview, exercise mouse/keyboard slider boundaries, verify terminal acceptance uses the same last selection, apply only after the existing confirmation, and verify automatic preview closure. This task authorizes source-level WinForms smoke only.
- Required source/package identity: reviewed source SHA and rebuilt candidate package SHA must match.
- Evidence artifacts: terminal selection, preview output/slider state, exact installed pinned file hashes, teardown state, and package/source identity.
- Owner/runtime authorization: required and not granted by this slice; no package or owner smoke is authorized.

## 11. Stop condition

Stop when the ten-effect catalog and twelve-profile chooser are entirely backed by pinned/hashed provenance, behavior regressions pass in both PowerShell engines, docs and owner mappings are current, and source gates pass. Keep release certification blocked pending exact package and owner-runtime evidence.

## 12. Forbidden actions

- No bundled third-party shaders or ReShade binaries, game launch, owner runtime mutation, package creation, merge, tag, publication, wiki update, certification, or expansion beyond this exact ten-effect/twelve-profile contract. Scoped commit/push to PR #321's existing head is authorized only after fresh gates and independent exact-diff review.

## 13. Commit/package authorization status

- Commit authorized: Yes, scoped to PR #321's existing head after fresh required source gates and independent exact-diff review.
- Package authorized: No.
- Release/certification authorized: No.