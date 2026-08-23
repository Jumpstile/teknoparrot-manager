# ReShade visual-effects research spike

Status: research and recommendation only. This document does not add shader downloads,
effect selection, preset generation, texture installation, executable add-ons, or
whole-directory replacement to TPM. The implementation work in this round is limited
to the existing ReShade runtime update path.

## Research boundary

The starting point is ReShade's official shader-package manifest:

- https://raw.githubusercontent.com/crosire/reshade-shaders/list/EffectPackages.ini

The manifest is an installer catalog, not an integrity manifest. It identifies package
URLs and effect files but does not provide a TPM-consumable expected SHA-256 for each
candidate. Any future curated downloader would therefore need a reviewed revision or
commit allow-list, expected digests, path/type validation, dependency and texture
inventory, license review, and transactional installation before it could be enabled.

The official runtime and installer sources remain separate from shader packages:

- https://github.com/crosire/reshade
- https://github.com/crosire/reshade-shaders
- https://raw.githubusercontent.com/crosire/reshade/main/setup/Pages/SelectEffectsPage.xaml.cs
- https://raw.githubusercontent.com/crosire/reshade/main/setup/MainWindow.xaml.cs

The official collection is the first source to review. Third-party candidates below are
considered only when the official manifest links to them or their upstream source can be
independently reviewed. No candidate is an approved TPM default from this spike.

## Candidate matrix

| User category | Candidate | Source | Official collection? | License | Maintenance | Compatibility | Dependencies / textures | GPU cost | Strengths | Drawbacks | TPM default | Confidence | Decision |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Source baseline | Standard effects package (crosire/reshade-shaders, slim) | https://github.com/crosire/reshade-shaders and the official manifest | Yes | Repository license metadata needs effect-level review | Repository page observed pushed 2026-08-02; activity alone is not a version pin | Official ReShade shader collection; effect-specific testing still required | Package contents vary; some effects need textures or user assets; manifest has no TPM digest | Varies by effect | Canonical starting point and installer-supported source | A package is not a curated UX; license/dependency/per-effect review remains | No package-wide default | High for source; Low for a default policy | Reject as a default package |
| CRT / scanlines | crt-royale.fx | https://github.com/akgunter/crt-royale-reshade; also listed by the official manifest | No; official installer manifest entry, but not the crosire collection | GPL-2.0 | Repository page observed last pushed 2023-05-12; 236 stars and 12 forks are secondary signals only | README states ReShade 4.9+ and DX9/DX10/11/12/OpenGL/Vulkan support | Phosphor mask and scanline settings; texture and preset inventory must be checked before packaging | High | Strong arcade CRT, mask, scanline, and curvature controls | Heavy configuration and cost; possible moire/dimming; GPL distribution review; older activity | No global default; trial only | Medium-low | Trial |
| CRT / scanlines | CRT_Lottes and related FXShaders CRT effects | https://github.com/luluco250/FXShaders; also listed by the official manifest | No; official installer manifest entry | MIT | Repository page observed last pushed 2023-10-07; 110 stars and 40 forks are secondary signals only | ReShade shader package; exact API and version matrix still required | Shader files and any referenced textures must be inventoried | Medium to high | Smaller CRT candidate set and permissive license | Less arcade-specific evidence than crt-royale; configuration and visual artifacts need testing | No global default; trial only | Medium-low | Trial |
| Sharper image | CAS.fx | https://github.com/CeeJayDK/SweetFX; also listed by the official manifest | No; official installer manifest entry | MIT | Repository page observed last pushed 2025-07-03; 263 stars, 40 forks, and 4 open issues are secondary signals only | ReShade-based SweetFX package; test across DX9/DX11/DX12/OpenGL titles | No external texture named in the manifest entry; effect and include files still need a pinned inventory | Low | Conservative sharpening candidate; likely lower visual risk than aggressive sharpening | Halos, aliasing, and HUD sharpening are possible; strength needs per-title limits | No global default; first trial candidate | Medium | Trial |
| Sharper image | LumaSharpen.fx | https://github.com/CeeJayDK/SweetFX; also listed by the official manifest | No; official installer manifest entry | MIT | Same SweetFX maintenance evidence as above | ReShade-based; exact API coverage needs game tests | No external texture named in the manifest entry; include graph must be pinned | Low | Familiar and adjustable low-resolution sharpening | Can emphasize ringing, source noise, or text artifacts | No global default; compare with CAS | Medium | Trial |
| Improved color | Vibrance.fx | https://github.com/CeeJayDK/SweetFX; also listed by the official manifest | No; official installer manifest entry | MIT | Same SweetFX maintenance evidence as above | ReShade-based; test SDR arcade palettes and bright HUDs | No external texture named in the manifest entry | Very low | Simple, understandable color adjustment | Can exaggerate already saturated art and vary by display | No global default; conservative trial only | Medium | Trial |
| Improved color | Levels.fx / Curves.fx comparison | https://github.com/CeeJayDK/SweetFX; also listed by the official manifest | No; official installer manifest entry | MIT | Same SweetFX maintenance evidence as above | ReShade-based; test black/white point behavior per title | No external texture named in the manifest entry | Low | Useful diagnostic control for black/white point | Levels can clip highlights or shadows; universal values are unsafe | No global default; research comparison only | Medium | Trial |
| Smoother edges | SMAA.fx | https://github.com/CeeJayDK/SweetFX; also listed by the official manifest | No; official installer manifest entry | MIT | Same SweetFX maintenance evidence as above | ReShade-based; test fixed-resolution 2D/3D and lightgun titles | Shader includes and preset values must be pinned; no manifest texture named | Low to medium | Can reduce jagged edges without a large blur | Can soften HUD/text and lightgun targets; may not help every renderer | No global default; per-title trial | Medium-low | Trial |
| Smoother edges | FXAA.fx | https://github.com/CeeJayDK/SweetFX; also listed by the official manifest | No; official installer manifest entry | MIT | Same SweetFX maintenance evidence as above | ReShade-based; broad compatibility expected but must be measured | Shader includes and preset values must be pinned | Low | Cheap edge smoothing fallback | More likely to soften small text and UI; quality depends on source resolution | No global default; per-title trial | Medium-low | Trial |
| Arcade display / bezel | Border.fx | https://github.com/CeeJayDK/SweetFX; also listed by the official manifest | No; official installer manifest entry | MIT | Same SweetFX maintenance evidence as above | ReShade-based; aspect-ratio and border-image testing required | May need a user-supplied border image; TPM must not ship unreviewed artwork | Very low | Can frame 4:3 content | Duplicates frontend/bezel responsibilities; image licensing, aspect, and operator preference issues | Do not advertise or install | High for scope decision | Reject |

Maintenance dates, stars, forks, and issue counts are orientation signals, not proof of
safety or compatibility. The source, license, dependency, and distribution decision must
be rechecked when a candidate is promoted.

## Real-game evaluation gate

No effect becomes a TPM default until it is measured on representative arcade
workloads. The minimum matrix is:

| Workload | What to capture |
|---|---|
| Older low-resolution 2D or 3D title | FPS/frame time, shimmer, halos, color clipping, readability |
| 3D title at 720p or 1080p | FPS/frame time, edge quality, temporal artifacts, UI readability |
| Lightgun title | target visibility, crosshair alignment, latency perception, edge softness |
| Racing title | motion stability, HUD readability, clipping, moire, frame-time spikes |
| HUD/text-heavy title | small text, menu labels, score readability, sharpening artifacts |
| Weaker GPU representative | frame-time cost, stutter, thermal or sustained-load behavior |

For each candidate, capture before/after at the same resolution and scene where possible.
Record the effect settings, ReShade version, renderer, GPU, display scaling, and whether
the result is acceptable. The current spike has no real-game measurements, so it approves
no default. CAS is the first sharpening trial, Vibrance is the second color trial,
CRT-Royale is a high-cost display trial, and SMAA/FXAA remain per-title trials.

The UX should expose goals such as "sharper image", "CRT / scanlines", "improved color",
"smoother edges", and "arcade display / bezel", not raw .fx filenames. A future
implementation must show the candidate effect, source revision, license, dependencies,
textures, settings, and measured cost before enabling it.

## Preset and file-ownership rules

If a future curated workflow is implemented, precedence is:

1. User per-game preset: ReShadePresets/ProfileCode.ini
2. TPM per-game/category recommendation
3. TPM global recommendation

TPM must never overwrite a user preset without explicit approval, a backup, and a
reversible write. Effect inventory is separate from runtime inventory. Custom shader,
texture, and preset files are preserved; installation must copy only reviewed files and
must not replace the whole ReShade directory.

## Security and distribution boundary

Do not add ReShade executable add-ons to the curated path. Accept only reviewed shader,
configuration, and texture types. Validate archive paths, extensions, containment, and
declared dependencies before extraction. Reuse the existing download audit and
transactional extraction primitives.

When a source does not provide an expected digest, TPM may record a calculated SHA-256
for audit, but must not describe that as publisher authentication. Any future live-fetch
path must use an allow-list and a pinned revision or digest; it must not scrape arbitrary
repositories or install an entire upstream package silently.

## Recommendation

Keep the current implementation runtime-only. Do not add a universal "Runtime + standard
effects" package, global CRT preset, or hidden shader downloader.

Next bounded research step: run the real-game matrix with CAS, Vibrance, one CRT
candidate, and one AA candidate from the reviewed source revisions. A candidate may be
promoted only after the evidence table is complete, the package files and licenses are
reviewed, and a reversible per-game UX is specified.
