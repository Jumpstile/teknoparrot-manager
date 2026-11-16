# TPM GPU Fix and BepInEx Outcome Identity Slice

## 1. Slice identity

- Name: GPU Fix and BepInEx per-game outcome identity and result presentation
- Contract ID: TPM-GPU-BEPINEX-OUTCOME-IDENTITY-001
- Related owner issues: [#300](https://github.com/Jumpstile/teknoparrot-manager/issues/300); #292 is an explicit exclusion for its exact-package PostgreSQL reset result.
- Isolated baseline: integrated source snapshot at commit 15576abc708b6bb9964e68a417a8e4804f26aade, with TeknoParrot-Manager.ps1 SHA-256 80D614C716DE011E6DE9EA15CA25E434E7BE77EE7398B7C1C267AC4CA047A4F7.

## 2. Owner report IDs included

- Issue #300 GPU Fix mixed-result attribution: the adapter derives changed IDs from a second enumeration and a count, while the legacy loop enumerates directories and FullBackup too; error counts become fabricated GPUFixFailureN IDs.
- Issue #300 BepInEx inspection/result presentation: an unreadable/unknown executable architecture is reported as unsupported, and all-skipped inspection can be reported as NO_OP without showing skipped, protected, unsupported, and per-game reason/action totals.

## 3. Explicit exclusions

- Issue #292 exact-package PACKAGE_MISMATCH during PostgreSQL reset, UAC behavior, package provenance, and runtime retry remain outside this source slice.
- ReShade, PostgreSQL, footer renderer, shared/global outcome semantics, package generation, release workflows, owner smoke, live installations, and all other workflows are excluded.
- No changes to approved-root containment, reparse checks, backup-before-write, rollback, cleanup, or mutation-boundary revalidation.

## 4. Behavior contract

- Current failure: GPU Fix does not have authoritative per-game result identity; BepInEx can misclassify an unknown architecture and conceal actionable safe skips in a generic NO_OP result.
- Expected behavior: GPU Fix returns selected, changed, completed, failed, and skipped IDs from the same canonical profile-file enumeration and the actual per-game processing loop. Counts never synthesize identifiers or assign outcomes by discovery order. BepInEx distinguishes known unsupported architectures from unknown/unreadable ones, keeps stable reason codes and next actions, and surfaces total skipped, protected, unsupported, and unknown counts with friendly labels in Details. An inspection containing only unresolved or protected skips reports ACTION_REQUIRED with unchanged product state; a genuine all-up-to-date or no-applicable selection retains its truthful no-change outcome.
- Terminal item sets remain disjoint, selected items stay within the authoritative candidate set, and changed items identify actual writes only.
- Forbidden regressions: no first-N attribution, counter-derived IDs, silent drops of protected/skipped candidates, unsupported status inferred from a missing architecture value, paths or technical exceptions in ordinary summaries, or alteration of existing safety/rollback behavior.

## 5. Source/function ownership

- TeknoParrot-Manager.ps1: Invoke-GpuFixSetup, Invoke-GpuFixSetupLegacy, Get-BepInExInspectionFailure, Invoke-BepInExUpdateCheck, and Invoke-BepInExUpdateCheckLegacy inspection/result accounting and existing Details renderer.
- Tests/TeknoParrot-Manager.Tests.ps1: focused GPU mixed/reordered outcomes, BepInEx architecture classification, skip accounting, outcome and Details display coverage.
- ARCHITECTURE.md, docs/RC8-REMEDIATION-INVENTORY.md, docs/REGRESSION_MATRIX.md, docs/remediation/PR-321-control-board.md, docs/remediation/PR-321-reconciliation.md, and this contract.

## 6. Required verification

- Characterize source behavior first with narrowly selected failing/regression cases.
- Run only the focused Pester cases under Windows PowerShell 5.1 and PowerShell 7; record discovered, executed, passed, failed, skipped, and not-run counts.
- Run parser checks, configured PSScriptAnalyzer, production ASCII check, applicable source-contract checks, and git diff --check.
- Full repository suites and unrelated primary-lane failure remediation are not part of this slice.

## 7. Runtime proof and stop condition

- Source changes and focused tests do not establish exact-package runtime behavior or release acceptance.
- Required later evidence: current package/source identity, all assistant-owned packaged checks, exact-package GPU and BepInEx checks, and owner acceptance after the other release gates pass.
- Stop when the scoped source changes, focused dual-engine evidence, static checks, inventory and hunk mappings are complete. Leave package/runtime and owner acceptance explicitly pending.

## 8. Procedure and release status

- Permanent procedure IDs: TPM-TRACE-001 and TPM-OWNER-001.
- Commit, push, package, publish, merge, tag, install, owner smoke, and release/certification are not authorized in this lane.
