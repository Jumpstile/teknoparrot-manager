# TPM Remediation Slice Contract

## 1. Slice name

- Name: RC8 ordinary menu compact default
- Contract ID: TPM-MENU-COMPACT-DEFAULT-001
- Issue/PR: Issue #323, ARC-UX-S01

## 2. Owner report IDs included

- IDs: ARC-UX-S01
- Exact owner-visible failures: The ordinary Windows Terminal viewport selects the menu's two-column layout; descriptions wrap/crowd and the menu is visibly broken.

## 3. Explicit exclusions

- Owner IDs not included: All other IDs.
- Features, modules, package, runtime, and release actions excluded: No menu feature additions, ARCADE-side work, package/release/publish/tag/merge/PR-base changes.

## 4. Behavior contract

- Current failure: the production script defines `Get-ConsoleLayoutTier` twice; its later legacy width-only definition overrides the conservative width-and-height policy and selects two columns for ordinary widths.
- Expected behavior: ordinary widths select Compact; Ultra requires both policy thresholds. The menu displays title/version, options 1-15 once and ordered, H/L/Q, and a prompt below the choices. Height fallback remains complete. Wide layout is selected only at the centralized safe threshold.
- Forbidden regressions: Missing/duplicate/reordered choices, controls or prompt omitted, incomplete constrained-height fallback, debug/production layout disagreement, normal widths selecting two columns, or multiple production selector definitions.
- Design boundaries and deliberate exclusions: Keep existing explicit render modes and constrained-height behavior; do not alter menu actions or add capabilities.

## 5. Source/function ownership

- Files: `TeknoParrot-Manager.ps1`; `scripts/Debug-TPM-MenuLayout.ps1`; `Tests/TeknoParrot-Manager.Tests.ps1`.
- Functions/regions: `Get-ConsoleLayoutTier`, `Get-MainMenuRenderMetrics`, `Get-MainMenuGeometry`, `Render-MainMenuScreen`, production menu loop, debug helper.
- Owning subsystem: Main menu viewport/layout and ARC-UX-S01.

## 6. Tests required before implementation

- Focused failing or characterization tests: `Get-ConsoleLayoutTier`; `RC8 main-menu command routing and visibility`; `Render-MainMenuScreen / Show-MainMenu`; `Menu layout debug script`.
- Source/inventory checks: Confirm production threshold and helper use the production layout selector.

## 7. Tests required after implementation

- Focused behavior tests: Ordinary dimensions one-column; ordered unique 1-15; H/L/Q and prompt below; no default two-column; constrained-height complete; wide layout only at explicit safe threshold; debug helper matches production.
- Regression suite: Focused menu/layout tests under PowerShell 7 and Windows PowerShell 5.1.
- Static and procedure gates: parser, PSScriptAnalyzer Error/Warning, ASCII, `git diff --check`, release consistency, and required TPM quality gate.

## 8. Documentation/report updates required

- Control board row: ARC-UX-S01 menu behavior subset, source/test complete; owner runtime remains required.
- Remediation report row: ARC-UX-S01, exact menu screenshot defect, source/test and runtime evidence separated.
- Hunk classification: ARC-UX-S01 / Issue #323 / TPM-MENU-COMPACT-DEFAULT-001; procedure mappings in remediation report.
- Changelog or user docs, if applicable: No release behavior beyond correction of existing layout; no user docs/changelog unless project release review requires it.

## 9. Permanent procedure IDs affected

- TPM-OWNER-001, TPM-OWNER-002, TPM-OWNER-003, TPM-EVIDENCE-001, TPM-TRACE-001, TPM-AUTH-001, TPM-CLEAN-001.

## 10. Runtime smoke checklist

- Exact packaged behavior: Ordinary/default Windows Terminal launch is one column with title/version, exactly ordered options 1-15, H/L/Q, and prompt below; constrained height keeps all choices visible; genuinely wide threshold layout is uncrowded.
- Required source/package identity: Exact source SHA and rebuilt package SHA recorded by the runtime owner.
- Evidence artifacts: Terminal screenshots and runtime report tied to source/package identity.
- Owner/runtime authorization: Arcade runtime proof remains with the owner; no ARCADE access or smoke run in this slice.

## 11. Stop condition

Stop when the contract's focused tests, report status, hunk mapping, and required gate evidence are complete. Do not widen scope to unrelated findings.

## 12. Forbidden actions

No unrelated cleanup, broad rewrite, package, release, certification, wiki update, ARCADE work, or owner smoke. Commit and push only the specified review branch as explicitly requested.

## 13. Commit/package authorization status

- Commit authorized: Yes, explicitly requested for this branch.
- Package authorized: No.
- Release/certification authorized: No.
