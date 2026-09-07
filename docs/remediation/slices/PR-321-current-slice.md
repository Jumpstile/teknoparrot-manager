# PR-321 Current Slice: Progress.Core Inventory

- Slice ID: TPM-PROGRESS-001
- Slice name: Script-wide progress inventory and source-side progress contract
- Included owner-report IDs: 3, 26, 32.
- Issue: PR #321.
- Permanent procedures: TPM-PROMPT-001 follow-up, TPM-TRACE-001, TPM-OWNER-001.
- Explicit exclusions: repair behavior (17-22), PostgreSQL repair (16), ReShade ownership/accounting (11-12), controls truthfulness (30), packaging, release, certification, owner-runtime smoke, ARCADE/#323, wiki, commit, and push.

## Contract

- Every user-facing long-running path must use either compact TPM progress or structured TPM workflow status.
- Known-total loops use `Write-TpmCompactExtractionProgress` with bounded labels and a completion update.
- Network transfers use `Write-TpmDownloadProgress`, which delegates to the shared compact renderer and clears the row in `finally`.
- Multi-step optional flows use `New-TpmWorkflowStatusContext`, explicit steps, failure/waiting states, and lifecycle closure.
- External waits are not fake percentage operations: profile readiness and process-close waits use explicit bounded deadlines and actionable waiting messages.
- Small bounded writes and renderer-aware interaction are documented as no-progress surfaces when they do not constitute long-running work.
- No PowerShell `Write-Progress` surface is permitted in the production script.

## Prompt inventory and classification

Prompt.Core finite-choice and back-routing classifications remain represented
by the committed checkpoint `7cd77108759084679f33eb27f98b6bfaaa58ff4d`.
This slice adds a bounded Prompt.Core follow-up inventory for IDs 26 and 32;
ReShade ownership/accounting and controls remain explicitly excluded.

## Prompt.Core follow-up inventory

- Finite enumerated routes use `Read-TpmChoice`, including dynamic allowed sets.
- Stateful selectors remain specialized boundaries: AutoSync and combined game
  pickers, ReShade terminal profile selection, and crosshair/browser selection.
- Exact-token confirmations, secure passwords, paths, free-text search, numeric
  candidate selection, and renderer-aware input remain specialized by design.
- `Read-TpmChoice validation` and `Prompt.Core fixed choice routes` cover the
  source-side contract. Packaged consistency smoke remains owner-runtime work.

## Progress inventory and classification

The source inventory below classifies each inspected long-running path as
`CONVERTED TO UNIVERSAL TPM PROGRESS`, `JUSTIFIED NO PROGRESS SURFACE`, or
an explicit bounded wait. No production `Write-Progress` call remains.


## Source inventory

### Compact progress converted

- AutoSync scan and extraction.
- Registration scan/import.
- Health Check affected-game repair and scoped recopy.
- GPU per-profile checks.
- Thumbnail checks and downloads.
- Shared BITS, HttpClient, and Invoke-WebRequest download tiers.
- DAT, game-data, ProfileSet, updater, FFB, BepInEx, dgVoodoo2, and ReShade download paths.
- LaunchBox export, backup, and restore loops.
- PostgreSQL profile/database setup loops where per-profile work occurs.

### Structured workflow status converted

- Support package collection.
- FFB setup.
- Library Health Check.
- PostgreSQL setup and recovery.
- ReShade setup.
- dgVoodoo2 setup.
- BepInEx setup.
- Restore flow.
- Crosshair setup.
- Startup update flow.

### Explicit waiting or bounded/no-progress surfaces

- `Ensure-TeknoParrotProfilesReady`: external TeknoParrot startup wait with a 120-second deadline and actionable retry message.
- `Wait-TpmForProcessClose`: external process-close wait with a 30-second polling window and no forced termination.
- Crosshair and HyperSpin bounded asset writes: short bounded writes, not long-running operations.
- ReShade terminal/browser preview interaction: renderer-aware input, not a percentage operation.
- AutoSync number/search selection: stateful input, not a progress operation.

### Remaining source limitation

The source-side inventory is complete for the inspected production paths. Packaged runtime proof remains unavailable and is not authorized in this slice. ID 3 therefore becomes `SOURCE FIXED; OWNER RUNTIME NEEDED` only after focused source tests and static gates pass; it is not claimed globally certified.

## Tests required

- Progress.Core focused source-contract tests.
- Main Pester suite.
- SupportPackage.Tests because workflow/support paths are included in the inventory.
- Production/test/gate parse checks.
- ASCII check.
- PSScriptAnalyzer with `PSScriptAnalyzerSettings.psd1`.
- `git diff --check`.
- Permanent procedure gate, expected to fail only for unresolved owner/runtime/package blockers.

## Files allowed to change

- `TeknoParrot-Manager.ps1`: no product code change planned; inspect only unless a concrete uncovered long-running path is found.
- `Tests/TeknoParrot-Manager.Tests.ps1`: Progress.Core source-contract coverage.
- `ARCHITECTURE.md`: Progress.Core contract and inventory boundary.
- `README.md`, `QUICKSTART.md`, `TeknoParrot-Manager-README.txt`, `TeknoParrot-Manager-QuickStart.txt`: only if user-facing progress wording is stale.
- `docs/remediation/PR-321-current-slice.md`
- `docs/remediation/PR-321-control-board.md`
- `docs/remediation/PR-321-reconciliation.md`
- permanent procedure gate only if required to enforce this slice ID.

## Runtime proof required

None authorized. Owner runtime proof requires a freshly built package tied to the final source SHA and a packaged operation matrix.

## Stop condition

Stop if a concrete path needs new product behavior beyond the contract, if tests fail for a non-obvious reason, or if package/runtime proof is required to distinguish source correctness from host behavior.

## Forbidden actions

No commit, push, package, release, certification, wiki, owner smoke, ReShade ownership/accounting work, controls work, ARCADE/#323 work, or unrelated prompt redesign.
