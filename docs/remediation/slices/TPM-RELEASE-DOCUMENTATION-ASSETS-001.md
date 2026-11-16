# RC8 user documentation and screenshot package contract

## 1. Slice name

- Name: exact four-guide and twelve-screenshot allowlist (owner amendment 2026-11-01)
- Contract ID: `TPM-RELEASE-DOCUMENTATION-ASSETS-001`
- Issue/PR: Issue #351 package-allowlist follow-up; owner-smoke gate #323 screenshot evidence. No GitHub change is authorized.

## 2. Owner report IDs included

- IDs: Issue #351 package cleanliness; gate #323 exact-package screenshot evidence.
- Exact owner-visible failures: the pre-FIX32 release map includes two TXT guides and one required RC8 menu screenshot, but omits the newcomer Markdown guides and their eleven screenshot paths. The owner approved the exact packaging amendment on 2026-11-01. The eleven real captures are not yet supplied, and unresolved screenshot placeholders remain in the source guide; package readiness stays blocked.

## 3. Explicit exclusions

- Owner IDs not included: all numbered PR #321 remediation rows; their statuses remain unchanged.
- Features, modules, package, runtime, and release actions excluded: no GPU/BepInEx guide edits, no new product feature, no broad images or Markdown inclusion, no screenshot capture in this lane, no actual/final ZIP build, package publication, tag, release, live install, GitHub write, merge, commit, or push. Parent owns exact candidate integration, runtime capture, and final package checks.

## 4. Behavior contract

- Owner amendment (2026-11-01 / FIX32): supersede the exclusive two-guide/one-image DOC-PKG-SPEC-001 rule, not the existing safety boundaries. Preserve every pre-FIX32 entry; add exactly two guides and eleven screenshots for 356 package files and 16 documentation assets (four Guide, twelve Screenshot). Earlier recorded synthetic proof belongs to the old source/map; FIX32 tests and actual package checks are unrun here.
- Exact Guide paths, SourcePath = ZipPath: `TeknoParrot-Manager-README.txt`, `TeknoParrot-Manager-QuickStart.txt`, `docs/START-HERE.md`, `docs/TROUBLESHOOTING.md`.
- Exact Screenshot paths, SourcePath = ZipPath: `images/release/RC8-MainMenu.png`, `docs/images/01-installer-window.png`, `docs/images/02-installer-new-folder.png`, `docs/images/03-installer-core-selected.png`, `docs/images/04-installer-done.png`, `docs/images/05-ui-first-run-information.png`, `docs/images/06-ui-updated-policies.png`, `docs/images/07-ui-setup-wizard.png`, `docs/images/08-ui-main-window.png`, `docs/images/09-tpm-welcome.png`, `docs/images/10-tpm-register-only-menu.png`, `docs/images/11-tpm-action-required.png`.
- Documentation/image directory entries are exactly `images/`, `images/release/`, `docs/`, and `docs/images/`, alongside unchanged non-documentation ancestors. This is an exact allowlist, not broad inclusion. Historical `images/tpm-main-menu.png`, artwork `images/banner.png`, and every other unlisted image/document stay excluded.
- Missing-capture behavior: before any temporary or final ZIP is created, the builder fails with `PACKAGE_REQUIRED_SCREENSHOT_MISSING` if any required screenshot is absent. The archive validator retains `PACKAGE_SOURCE_SCREENSHOT_MISSING`, requires every exact path, and checks source bytes. The real tree must keep failing until all required real captures exist; never generate repository fallback images.
- Minimum PNG boundary (FIX33): every old and new Screenshot must be at least 128 bytes, start with the eight bytes `89 50 4E 47 0D 0A 1A 0A`, contain `IHDR` at bytes 12-15, and declare big-endian width/height at bytes 16-23 of at least 640x360; otherwise reject with `PACKAGE_SCREENSHOT_INVALID_PNG` and a reason. The real RC8 main-menu header declares 1115x818, so the floor is unchanged. This is not full image validation or capture-provenance proof.
- Markdown placeholder refusal: builder and archive validator reject literal case-sensitive `[SCREENSHOT:` in every packaged `.md` with `PACKAGE_DOCUMENTATION_PLACEHOLDER`. Builder missing-screenshot checks run first. Archive length and bounded source/ZIP hash identity checks remain first; archive-only tampering may fail an existing size/content check rather than the specific placeholder guard. Byte-identical source/archive placeholders reach the guard; clean Markdown retains all existing checks.
- Forbidden regressions: no broad `images/`, `docs/`, `docs/images/`, `.md`, or documentation-folder inclusion; no synthetic/stale screenshot fallback; no weakening unknown-entry, path-safety, collision, source/hash, leak, exact Crosshairs `000.png`--`320.png`, contract-projection, or runtime-source checks; no claim that a present PNG is genuine without human provenance review.
- Design boundary: source-path/hash equality proves only that the ZIP contains mapped bytes, not when or where a capture was made. Release evidence must record exact candidate identity and every screenshot SHA-256; a reviewer must confirm actual current installer, TeknoParrotUI, and RC8 captures as applicable.

## 5. Source/function ownership

- Files: `scripts/TPMReleasePackage.Core.psm1`, `scripts/New-TPMReleasePackage.ps1`, `Tests/TPMReleasePackage.Tests.ps1`, `AGENTS.md`, `RELEASE-SAFETY-CHECKLIST.md`, `docs/remediation/inventories/TPM-RELEASE-PACKAGE-ALLOWLIST-001.md`, this contract, and the release control/report records.
- Functions/regions: `Get-TPMReleasePackageFileMapV1`, documentation asset manifest, screenshot source preflight, `New-TPMReleasePackage`, and `Test-TPMReleasePackageArchiveV1`.
- Owning subsystem: exact RC8 user release ZIP contents.

## 6. Tests required before implementation

- Historical characterization: the earlier pre-screenshot baseline contained 341 files and the two TXT guides; the pre-FIX32 map contains 343 files with `images/release/RC8-MainMenu.png`. These are old-map facts, not FIX32 verification.
- Source/inventory requirement: inspect all exact source and archive paths above, retain old entries, and account for every missing capture. Only isolated private TestDrive synthetic fixtures may be generated; do not create repository images or an actual release package. No FIX32 tests or product execution are authorized in this lane.

## 7. Tests required after implementation

- Focused Pester required on the test PC after owner authorization: assert each exact four-guide/twelve-screenshot entry once, 16 documentation entries, reciprocal TXT links and newcomer pointers, untouched README first 18 and QuickStart first 17 lines, all four documentation/image ancestors, and stale/broad/unlisted image and Markdown exclusions. Preserve existing-entry assertions.
- Required refusal fixtures: missing old and new screenshots fail before any ZIP/temporary output; bad PNG signature, length below 128, missing IHDR, or 64x64 dimensions fail for old and new screenshot paths in builder preflight and archive validation. Deterministic valid PNG fixtures generated only in TestDrive must be byte-identical across fixtures and engines; exactly 640x360 is accepted. Literal Markdown placeholders fail in source and byte-identical source/archive fixtures. Archive-only tampering must still fail existing size/content checks; no specific placeholder diagnostic is promised before those bounded checks. Clean Markdown and case-sensitive literal matching retain every size/hash requirement. FIX33 runtime tests are not run in this lane.
- Exact map/package tests: synthetic TestDrive-only fixtures must require all 356 files, 321 source crosshairs, zero leaks, exact source bytes, and rejection of unexpected root and nested documentation/image files. Such fixtures prove no actual capture or final package readiness; never create repository fake screenshots to make a happy path pass. FIX32 tests are not run in this lane.
- Static/procedure checks: `git diff --check`, PowerShell parse/static checks for changed scripts, and the permanent procedure mapping are owned by the parent release integration.

## 8. Documentation/report updates required

- Control board row: add a separate packaging follow-up mapped to Issue #351 and gate #323; do not change PR #321 owner statuses.
- Remediation report row: record exact map, missing-capture and unresolved-placeholder disposition, tests changed/added and unrun status, and required parent capture evidence. Do not present historical fixture results as FIX32 evidence.
- Hunk classification: exact package source map/builder/validator and focused tests; governance docs and paired inventory.
- User-facing docs: keep the exact sentence `For a one-page version, see TeknoParrot-Manager-QuickStart.txt.` and the QuickStart-to-README cross-link. Preserve README first 18 and QuickStart first 17 lines; add one short newcomer pointer after those blocks to open `docs\START-HERE.md` first and `docs\TROUBLESHOOTING.md` when stuck. Retain the offline TXT walkthrough and menu screenshot pointer. Do not edit the two Markdown guides or separately reviewed GPU/BepInEx instructions in this slice.
- Layout finding for coordinator: `docs/START-HERE.md` describes the RC8 candidate "in this folder", but application files remain one level above `docs/` in the extracted package. Its current `docs/images/...` placeholder paths are package-root paths, not correct relative Markdown links from that guide; replacement links must use `images/...` to avoid resolving to `docs/docs/images/...`. The sibling `TROUBLESHOOTING.md` links match the packaged layout. Report this ambiguity; do not edit the guide here.

## 9. Permanent procedure IDs affected

- `TPM-TRACE-001`: map the source, test, and governance hunks to Issue #351, gate #323, and this contract.
- `TPM-EVIDENCE-001`: verify every screenshot path, exact source-to-ZIP bytes, all four guide bytes, and the 321 Crosshairs.
- `TPM-UX-001`: limit shipped documentation to the exact four guides and twelve screenshots, with newcomer entry pointers and no broad folder inclusion.
- `TPM-TRUTH-001`: distinguish minimum PNG/source-hash checks from human-verified capture provenance, historical proof from unrun FIX32 work, and synthetic fixtures from an actual release package.

## 10. Runtime smoke checklist

- Exact packaged behavior: parent opens and visually reviews real current captures from the extracted candidate; the exact archive includes only the four guides and twelve screenshots listed above as documentation assets, and no unresolved Markdown placeholders.
- Required source/package identity: parent records candidate branch/commit, packaged manager SHA-256, exact archive identity, capture environment/time, and every screenshot SHA-256.
- Evidence artifacts: the real screenshots and source/package provenance record. This lane supplies no captures and cannot satisfy this gate; minimum PNG checks are not provenance evidence.
- Owner/runtime authorization: parent owns runtime verification and the final owner acceptance gate; no owner handoff is authorized by this lane.

## 11. Stop condition

Stop after the explicit four-guide/twelve-screenshot allowlist, minimum PNG boundary, missing-capture failure, and Markdown placeholder refusal are implemented with focused assertions; preserve every existing map/security/crosshair invariant and update paired governance records. Parent owns running authorized verification and exact-package checks. Deliver the patch and exact missing evidence without claiming FIX32 tests passed; while captures or resolved guide links are absent, leave RC8 package readiness pending.

## 12. Forbidden actions

No actual release package build, screenshot fabrication/capture, runtime installation or mutation, GitHub write, commit, push, PR, merge, tag, publication, full repository suite, or owner acceptance claim.

## 13. Commit/package authorization status

- Commit authorized: No.
- Package authorized: No actual/final package; private test fixtures only.
- Release/certification authorized: No.
