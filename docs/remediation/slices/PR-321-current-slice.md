# PR-321 Current Slice: Controls Truthfulness

- Slice ID: TPM-CONTROLS-001
- Slice name: Controls truthfulness reconciliation
- Included owner-report IDs: 30.
- Issue: PR #321.
- Permanent procedures: TPM-TRACE-001, TPM-OWNER-001.
- Explicit exclusions: ReShade ownership/accounting (11-12), progress inventory (3), prompt/stateful migration (26/32), repair (16-22), packaging, release, certification, owner-runtime smoke, ARCADE/#323, wiki, commit, and push.

## Behavior contract

- Saved configuration, inferred readiness, and verified physical binding are separate facts.
- Control propagation may count copied or corrected saved settings, but must never call them verified physical bindings.
- A propagation result with no saved changes remains explicit and distinct from a failed save.
- Control-readiness assessment remains fail-closed: static profile inspection cannot produce Verified; only structured observed-test evidence may do so.
- User-facing summaries must state that TPM does not test physical controls when reporting propagation counts.
- No control-readiness function may mutate UserProfiles, GameProfiles, or ParrotData.


## Prompt inventory and classification

Prompt.Core is outside TPM-CONTROLS-001. The committed Prompt.Core checkpoint
and its documented finite-choice/stateful boundaries remain authoritative.

## Source inventory

- `Get-ControlReadinessControlsState` returns Missing, Unsupported, NotVerified, or Unknown; it never returns Verified.
- `Get-ControlReadinessSummaryLines` downgrades unqualified caller-supplied Verified values to Not verified.
- `Test-ControlReadinessVerificationEvidence` requires structured Method and ObservedAt evidence.
- `Write-ControlPropagationResults` separates copied controls, settings-only results, API corrections, manual setup, skipped games, and save failures.
- `Invoke-ControlPropagation` and the readiness engine retain read-only and no-propagation boundaries.

## Focused change

Add an explicit zero verified-physical-bindings result to the propagation summary and returned result object. This makes the existing disclaimer machine-readable without claiming that TPM performed a hardware test.

## Tests required

- Focused controls truthfulness tests covering zero, mixed, skipped, failed, settings-only, and API-correction result sets.
- Existing control-readiness fail-closed and no-write tests.
- Main Pester suite.
- SupportPackage.Tests only if support/reporting code is touched.
- Production/test/gate parse checks.
- ASCII check.
- PSScriptAnalyzer with `PSScriptAnalyzerSettings.psd1`.
- `git diff --check`.
- Permanent procedure gate, expected to fail for unresolved IDs 11/12 and remaining owner/package blockers.

## Files allowed to change

- `TeknoParrot-Manager.ps1`
- `Tests/TeknoParrot-Manager.Tests.ps1`
- `ARCHITECTURE.md`
- `docs/remediation/PR-321-current-slice.md`
- `docs/remediation/PR-321-control-board.md`
- `docs/remediation/PR-321-reconciliation.md`

## Runtime proof required

None authorized in this slice. Owner proof requires a packaged candidate and a runtime matrix that distinguishes saved configuration from observed physical binding.

## Stop condition

Stop if the change would infer physical readiness, mutate read-only assessment paths, require package/runtime proof, or expand into ReShade ownership/accounting or unrelated control propagation behavior.

## Forbidden actions

No commit, push, package, release, certification, wiki, owner smoke, ReShade ownership/accounting work, progress or prompt redesign, ARCADE/#323 work, or unrelated source cleanup.
