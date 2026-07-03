# TPM Regression Matrix

This matrix tracks fixed defects and hardening work that should stay covered by
Pester or other repeatable checks. It is intentionally focused on behavior that
can regress silently during release-hardening work.

Rule: every confirmed bug fix needs a regression test and a row in this file.
`docs/REGRESSION-REGISTER.md` covered this same ground under a separate table;
its four normalization entries are folded in below (marked Covered) and that
file now points here.

## Status

- Pending Fix: test exists and currently exposes the bug.
- Covered: test passes and protects the fixed behavior.
- Needs Test: bug is known but coverage has not been added yet.
- Investigation: behavior still needs confirmation.

## Entries

| Bug / issue | Coverage | Risk covered | Remaining gap | Status |
| --- | --- | --- | --- | --- |
| Issue 80 normalization | `Tests/KnownBugRegression.Tests.ps1` | Board or revision tokens can remain in normalized game keys | -- | Covered |
| Zoids title safety | `Tests/KnownBugRegression.Tests.ps1` | EX Plus could be collapsed into plain Zoids Infinity | -- | Covered |
| Edition title safety | `Tests/KnownBugRegression.Tests.ps1` | Meaningful parenthetical title text could be stripped | -- | Covered |
| Rev-letter safety | `Tests/KnownBugRegression.Tests.ps1` | Bare Rev-letter tokens could be stripped too broadly | -- | Covered |
| Downloader pipeline hardening, issue #68 | `Invoke-TpmDownload` method-selection, retry, BITS `TransientError`, progress-display, partial-file cleanup, expected-size, cache-reuse, thumbnail 404-vs-failure, and updater module transport tests | Slow or unsafe repeated download paths, partial files promoted as complete downloads, noisy or misleading progress, thumbnail 404s reported as hard failures | Live network performance still depends on periodic field validation because tests mock transport behavior instead of downloading real upstream assets. |
| Issue #66: already-extracted games still offered for extraction | `Resolve-ExtractedGameFolder` tests for Aliens Armageddon, Battle Gear 3 metadata differences, RetroBat suffixes, registered GamePath identity, empty-folder rejection, unsafe profile-code rejection, and sequel negative cases | Duplicate extraction prompts, unsafe DAT/profile identity use, false positives between similarly named games | Full reporter list still requires real collection data confirmation. |
| Issue #66 AutoSync integration | `Invoke-AutoSync extracted-folder regression guards` proves AutoSync does not call extraction when the resolver finds an existing non-empty short-name RetroBat folder | Regression where the resolver works directly but AutoSync bypasses it and extracts anyway | Additional large real-world folder sets are still manual unless a fixture dataset is added. |
| Issue #59 standalone Propagate Controls | `Write-ControlPropagationResults` and `New-PropagationBackup` tests | Standalone propagation continuing after incomplete backup or misreporting results | End-to-end console flow remains smoke-test/manual. |
| Issue #53 duplicate control target slots | `Invoke-ControlPropagation duplicate-key handling` | One archetype binding filling duplicate target slots incorrectly | Real FATF Drift behavior still requires tester validation before closing the issue. |
| Registration fuzzy tie handling, issue #15 | `Resolve-BestFuzzyMatch` and near-threshold/tie tests | Iteration-order profile selection when candidates are close | No broad real GameProfiles corpus fuzz run yet. |
| Registration false action-required states, issue #9 | Existing registration helper coverage around exact GamePath identity and already-registered handling | Already registered games being listed as needing manual action | Full `Register-Games` integration fixtures are still limited. |
| Registration deeper executable handling, issue #10 | `Set-SecondaryExecutablePath` and registration-path helper tests | Games with secondary/deeper executable paths losing required launch paths | More complete game-template fixtures would improve coverage. |
| RomVault DAT parsing, issue #12 | `Build-DatIndexFromStream` tests | Skipping real entries after `<rom>` nodes in large DAT files | Performance benchmarking with a real large DAT remains separate. |
| Raw Thrills/path-limit rename behavior, issue #13 | `Resolve-BestFuzzyMatch` alias fallback and #66 resolver tests | Short-name folders being treated as missing or available to extract | Reporter-specific folder names still need field validation. |
| Network path handling, issues #5/#29 | `Invoke-WithHardTimeout`, `Get-LocalDriveInfoSafe`, and `Test-IsNetworkPath` tests | DriveInfo deserialization failures and hangs on unavailable network paths | Real dead-share timing is still best covered by manual or lab testing. |
| XML read/write hardening, issues #22/#24/#25/#34 | `Read-Xml`, `Save-XmlMaybe`, XML literal, and parse tests | Encoding drift, malformed comments, unsafe save behavior | Fault-injection tests for disk-full or locked-file cases are limited. |
| Path safety, issue #28 | `Test-PathInside`, ZIP extraction, FFB plugin destination safety, and DAT path checks | Traversal out of expected folders | Windows long-path edge cases still need occasional release-package validation. |
| FFB Blaster gating, issue #41 | `Get-FFBBlasterSupport` and field-drift tests | Offering setup for unsupported games or writing unknown schema fields | Live upstream schema drift still depends on periodic review. |
| Upstream profile/schema drift, issue #43 | `Get-GameProfileSchemaDrift` tests | Unknown GameProfile nodes or field types being silently modified | Live upstream profile snapshots are not vendored into this suite. |
| Compatibility setup utilities, issue #46 | Third-party FFB destination safety, RawInput field handling, GPU vendor matrix, safe re-run tests | Unsafe helper destinations, unknown input fields, GPU fix rewrite mistakes | Cross-tool installation smoke tests remain manual. |
| Thumbnail downloads | Source-level thumbnail regression guards for existing-icon fast path and failed-download cleanup | Re-downloading or overwriting existing icons, leaving partial icon files | Runtime network behavior should move to shared downloader tests after consolidation. |
| Crosshair setup | `Set-Pcsx2CursorPaths` backup-before-write test | PCSX2 cursor config rewrite without a backup | Full interactive picker and browser preview remain manual. |
| Main menu architecture | Source-level main menu drift tests | Displayed option numbers diverging from switch cases | Console presentation still benefits from manual smoke testing. |
| Auto-update safety | `TpmAutoUpdate.Core`, destructive-path tests, and manager-update tests | Raw ZIP replacement, bad release URLs, missing script in ZIP, backup failure, `-WhatIf` apply behavior | Standalone updater download transport should consolidate with the shared downloader helper after both branches converge. |
| pcsx2x6 crosshair path, issue #79 | `Invoke-CrosshairSetup`/`Resolve-Pcsx2Directory` regression tests, `VirtualBetaTester.Recovery.Tests.ps1` (missing-dependency category) | Crosshairs deployed to the emulator folder root instead of the upstream-canonical `pcsx2x6\TeknoParrot\crosshairs\` subfolder | None -- real-instance certification confirmed correct behavior against an actual pcsx2x6 install. |
| Auto-update locked-destination false success, issue #86 | `TpmAutoUpdate.DestructivePath.Tests.ps1` (`Replacement failure after successful backup`) | "Update installed successfully" reported without the file actually being replaced when the destination was briefly locked | None -- the fix and its test both landed together. |
| Missing pcsx2x6 firmware/BIOS detection, issue #85 tier 1 | `Tests/TeknoParrot-Manager.Tests.ps1` (`Get-CompatibilityWarnings -- BiosMissing`, 10 tests), `VirtualBetaTester.Recovery.Tests.ps1` (missing-firmware recovery, TVD-High) | Games registered and launchable via TPM failing at launch with a real "firmware not installed" error, with no earlier warning | Tier 2 (remediation/acquisition assistance) is explicitly deferred post-1.0 -- detection-only is the certified scope for 1.0. |

