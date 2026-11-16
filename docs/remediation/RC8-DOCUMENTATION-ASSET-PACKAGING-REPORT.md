# RC8 documentation asset packaging report

Date: 2026-10-21

## Scope and source identity

This report covers the isolated Issue #351 package-allowlist follow-up and the screenshot evidence requirement in owner-smoke gate #323. Worktree: `C:\Users\Example\AppData\Local\Temp\tpm-docpackage-contract-20261021`; branch: `release-doc-assets-contract-20261021`; verified base HEAD: `15576abc708b6bb9964e68a417a8e4804f26aade`. The worktree remains uncommitted and isolated from the primary integration checkout and the earlier GPU/BepInEx donor.

## Verified behavior and changes

- Current packaged guides are the plain-text `TeknoParrot-Manager-QuickStart.txt` and `TeknoParrot-Manager-README.txt`. The Quick Start remains the first-run entry and points to the full guide; it now names the single package screenshot path.
- The exact allowlist now contains `images/release/RC8-MainMenu.png`. The prior `images/tpm-main-menu.png` is historical and excluded, as are `images/banner.png`, all other images, and Markdown documents.
- `New-TPMReleasePackage.ps1` checks the required screenshot before creating a temporary or final ZIP. The archive map still uses exact source paths and source hashes; path/collision/unknown-entry, leak, runtime projection, and 321-Crosshairs checks are unchanged.
- The screenshot is not present in this worktree. Pester creates a visibly synthetic checkerboard only inside its private `TestDrive` fixture; it never writes to the repository release input. The actual capture and human provenance review remain required, so no release package can be built from this source state.

## Verification

- On the test PC, `Tests/TPMReleasePackage.Tests.ps1`, Pester 5.7.1 on Windows PowerShell 5.1.26100.9711: 13 discovered, 13 passed, 0 failed, 0 skipped, exit 0.
- Same package test file and Pester 5.7.1 on PowerShell 7.6.5: 13 discovered, 13 passed, 0 failed, 0 skipped, exit 0.
- All archive/runtime tests run against a private Pester `TestDrive` source fixture. Fixture setup always skips the repository screenshot, writes a magenta/lime checkerboard PNG and a `SYNTHETIC-TEST-ONLY.txt` marker in the temporary fixture, and copies the package-validator wrapper/module there so its default source root is the fixture. Those test-only files never enter the release input or ZIP map. Strict archive checks still require exactly 343 mapped files (the 342 pre-TpmProgress count plus `scripts/TpmProgress.psm1`) and 321 Crosshairs.
- A separate test removes that synthetic PNG from another temporary source fixture and confirms the builder rejects it before creating a temporary or final ZIP. The exact guide/image map and guide bytes, source-to-archive checks, unknown/collision/unsafe-path checks, leak checks, source projections, and packaged PCSx2x6 runtime projection all execute on the synthetic package fixture. This is regression evidence only, not screenshot, actual release ZIP, or owner-smoke evidence.
- PowerShell parser checks passed for `scripts/TPMReleasePackage.Core.psm1`, `scripts/New-TPMReleasePackage.ps1`, and `Tests/TPMReleasePackage.Tests.ps1` under both engines. `git diff --check` is recorded after final patch review.
- PSScriptAnalyzer 1.25.0 with repository settings was inconclusive: PS7 completed with five Information-only `PSProvideCommentHelp` notices and no warnings/errors; PS5.1 raised analyzer `RULE_ERROR` (“Object reference not set to an instance of an object”) on the core module. No analyzer pass is claimed; the parent owns required static gates.
- No final package, screenshot, runtime install, owner smoke, GitHub write, commit, push, or release action occurred.

The final focused verification used the current files with these SHA-256 values:

- `scripts/TPMReleasePackage.Core.psm1`: `1054D375E69A6692938F314EB51A13A4DA37F08576BE50690E6BC40328E07C16`
- `scripts/New-TPMReleasePackage.ps1`: `352266CB08E18731625EC61C0D305E41D8025F0F2AE8FFE9D573F9A12419F896`
- `Tests/TPMReleasePackage.Tests.ps1`: `B21CEB43DC41F1AC892CDF384ABE02DE4F76D2C0270C25AF2B509054CF476F1E`

## Remaining package gate

Provide a real current RC8 menu capture at `images/release/RC8-MainMenu.png`, record the exact candidate source identity and screenshot SHA-256, and have a reviewer verify the image came from an actual RC8 runtime. The 13 focused tests pass only with a synthetic TestDrive fixture. After the real capture and provenance review, rebuild and validate the exact candidate package. Until those steps pass, release package readiness remains blocked.

## Current RC8 source menu evidence -- 2026-10-24

The earlier missing-screenshot observation is historical. A genuine current
main-menu image is now present at images/release/RC8-MainMenu.png.
Main SHA-256: A4F849C60BF2B28B92284D551FC4F1D8C4303E5892276701AD3AF200246D0B91.
Image SHA-256: 3B7CA689F7A46895CD6C51E9BD286AAEE86C323363B722AE4CDF468DC3D4EFC8.
The unmodified full script ran under Windows PowerShell 5.1 in a new owned
Windows Terminal against an isolated runtime fixture. The default capture
records actual 120x40 character dimensions and 1115x818 visible-window pixels.
A separate genuine constrained run records actual 100x25 dimensions. Both
show RC8, all options 1-16, H/L/Q, and the final prompt; both exited by Q.
The actual image was visually reviewed for menu ordering, clipping, and private
paths. Only the owned visible window was captured; no synthetic image or
image editing was used. No live game or original-checkout write occurred.

This is Maintainer bootstrap runtime evidence that closes the source-asset
prerequisite only. It is not evidence that a final ZIP was built or that the
complete #323 packaged runtime matrix passed. Full frozen-folder tests,
package identity/validation, final extracted-byte checks, remaining runtime
checks, and required handoff gates remain separate.