# TPM BepInEx Functional Transaction Slice

## 1. Slice identity

- Name: BepInEx functional handoff, candidate identity, and transaction accounting
- Contract ID: TPM-BEPINEX-FUNCTIONAL-TRANSACTION-001
- Issue/PR: PR #321 remediation control board
- Authorized branch: `fix/rc8-release-blockers`
- Authorized starting HEAD: `1599707f38b509c7a2036c06ea6ed92c43626981`

## 2. Owner report IDs

- Owner report IDs: BepInEx functional package handoff; BepInEx transaction
  accounting; BepInEx beginner-safe result output.
- Exact failure: the per-game deployment calls `Expand-ZipFileSafe` through an
  undefined package-path variable after downloads succeed, and the compatibility
  transaction wrapper invents item IDs from counters while scanning every XML
  profile rather than reporting actual selected, changed, failed, and skipped
  games.
- Related UX failure: normal output can emit a long per-game `SKIP` wall,
  technical reason/path text, and wording that does not distinguish a successful
  package download from a failed per-game install.

## 3. Expected behavior

- Select the downloaded package by the candidate architecture from the approved
  `$zipByArch` map. Validate that the selected path is nonblank, contained in the
  approved cache root, existing, and not reparse-backed before extraction.
- Preserve each candidate's canonical game path identity through preflight,
  approval, package selection, staging, backup, promotion, cleanup, and final
  verification. Revalidate only the current candidate and never substitute a
  different candidate's destination.
- Keep protected/reparse and path-unavailable records as unchanged safe skips;
  they are not installation errors.
- Return actual profile/game IDs from the legacy workflow for selected/eligible,
  changed, failed, and skipped sets. The wrapper must not synthesize names from
  counters or include unrelated XML profiles. Preserve the actual
  `FailureRecords` in technical transaction details.
- Keep normal output beginner-safe: full game names where available, compact
  grouped skip reporting, protected roots explicitly unchanged, and separate
  wording for downloaded-package/install failure. Technical paths, raw
  exceptions, stack-like text, and raw profile IDs remain in logs/details only.

## 4. Forbidden regressions and exclusions

- Do not weaken approved-root containment, reparse checks, backup-first behavior,
  rollback, staging cleanup, or mutation-boundary revalidation.
- Do not classify protected/reparse roots as install errors.
- Do not change ReShade, Crosshair, global Easy/Technical mode behavior, package
  generation/validation, owner smoke, Arcade work, wiki, push, merge, tag,
  publish, certification, or release readiness.
- Do not create a release ZIP or alter release artifacts.

## 5. Source ownership

- `TeknoParrot-Manager.ps1`
  - `Invoke-BepInExUpdateCheck`
  - `Invoke-BepInExUpdateCheckLegacy`
  - BepInEx per-game package/staging/promotion loop
- `Tests/TeknoParrot-Manager.Tests.ps1`
  - focused BepInEx handoff, accounting, identity, and output tests
- `ARCHITECTURE.md`
  - BepInEx transaction and user-output invariants
- `docs/remediation/PR-321-control-board.md`
- `docs/remediation/PR-321-reconciliation.md`

## 6. Required verification

- Focused BepInEx functional, transaction-accounting, identity, and output tests.
- S2-B1/UI regression and S1/S2 transaction/presentation tests.
- Full `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1`.
- `Tests/SupportPackage.Tests.ps1` support suite.
- PowerShell parser check, PSScriptAnalyzer with
  `PSScriptAnalyzerSettings.psd1`, ASCII check, InjectionHunter, and
  `git diff --check`.
- Record source-only evidence. Owner/runtime smoke remains paused and no package
  identity is created.

## 7. Runtime proof and stop condition

- Owner smoke is explicitly unauthorized from this worktree.
- Required runtime proof remains deferred to the authorized owner/package stage.
- Stop when the source change, focused tests, required regression/static gates,
  control-board/reconciliation evidence, and final scope/exclusion review are
  complete. Do not widen the slice.

## 8. Procedure and release status

- Permanent procedure IDs: TPM-TRACE-001 and TPM-OWNER-001.
- Local source commit authorized for this remediation stack: Yes.
- Push, package, owner smoke, Arcade, wiki, merge, tag, publish,
  release/certification, and release-ready actions remain unauthorized.
