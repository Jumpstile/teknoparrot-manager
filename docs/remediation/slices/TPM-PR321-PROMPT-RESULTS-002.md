# PR #321 prompt and results consistency remediation

## 1. Slice name

- Name: Support follow-up, restore-choice, and dgVoodoo2 guidance consistency
- Contract ID: `TPM-PR321-PROMPT-RESULTS-002`
- Issue/PR: PR #321; owner report IDs 27, 31, and 32

## 2. Owner report IDs included

- IDs: 27, 31, 32
- Exact owner-visible failures: Support package creation returns to the main menu without the expected Open/Back follow-up; dgVoodoo2 failure guidance offers Library Health Check for an unavailable device even though the per-game recovery action is reconnecting that device; three finite numbered restore prompts bypass shared validation and retry behavior.

## 3. Explicit exclusions

- Owner IDs not included: all other PR #321 rows.
- Features, modules, package, runtime, and release actions excluded: no new capability, backup/restore transaction redesign, package build, owner/runtime smoke, certification, commit, push, merge, tag, publication, wiki update, or release authorization.

## 4. Behavior contract

- Current failure: Support creation lacks the package-folder Open/Back follow-up; dgVoodoo2 failure guidance conflates unavailable-device and missing-path recovery; three finite numbered restore prompts do not use shared invalid-choice retry behavior.
- Expected behavior: after support package output exists, offer validated Open/Back; Open uses the existing safe TPM-owned-folder boundary. Device-unavailable dgVoodoo2 results explain reconnecting the device and do not offer Health Check unless a missing saved path also exists; missing-path results retain the Health Check route. UserProfiles, LaunchBox, and PostgreSQL restore numbers reject invalid input and reprompt, preserve blank-to-cancel, and cannot cross the mutation boundary before valid selection.
- Forbidden regressions: no mutation before valid restore selection; preserve blank cancellation and backup safety checks; never report a failed support ZIP as created; preserve package cleanup warnings; keep secure input, exact-token confirmations, free text, and stateful pickers outside `Read-TpmChoice`; never route device-only failures to path repair.
- Design boundaries and deliberate exclusions: the dgVoodoo2 successful-with-skips screen is unreachable because success requires zero skip, missing-device, missing-path, and error counts; the real defect is the reachable failure guidance. This slice does not assert every repository prompt is centralized; it covers only the named owner rows and restore routes.

## 5. Source/function ownership

- Files: `TeknoParrot-Manager.ps1`; `Tests/TeknoParrot-Manager.Tests.ps1`; `docs/remediation/PR-321-control-board.md`; `docs/remediation/PR-321-reconciliation.md`; this contract.
- Functions/regions: Support main-mode result handling; `Open-TpmOwnedFolder`; `Invoke-TpmSupportPackageFollowUp`; `Get-DgVoodoo2FailureGuidance`; dgVoodoo2 failure routing; `Invoke-RestoreBackupLegacy`; `Invoke-RestoreLaunchBoxBackup`; `Invoke-RestorePostgresBackup`; `Read-TpmChoice`.
- Owning subsystem: Prompt.Core and Results.Core / PR #321.

## 6. Tests required before implementation

- Focused failing or characterization tests: exercise invalid-then-blank restore choices and no-mutation Back for each restore route; exercise Support Open/Back with a test-owned file/folder; test device-only, path-only, and mixed dgVoodoo2 failure guidance.
- Source/inventory checks: confirm only named finite choices migrate; verify support folder path checks; verify Health Check is offered only when MissingPath is positive.

## 7. Tests required after implementation

- Focused behavior tests: Support Open/Back; all three restore invalid-retry/blank-cancel transitions; dgVoodoo2 device-only vs missing-path guidance.
- Regression suite: full `Tests/TeknoParrot-Manager.Tests.ps1`; full `Tests/SupportPackage.Tests.ps1`; parser under PowerShell 7 and Windows PowerShell 5.1; ASCII, PSScriptAnalyzer, InjectionHunter, `git diff --check`, and permanent procedure gate.
- Runtime boundary: no real Support, Explorer, restore, or dgVoodoo2 operation in this worktree; use isolated fixtures and behavior helpers only.

## 8. Documentation/report updates required

- Control board row: re-audit IDs 27, 31, and 32; record source status independently from owner runtime.
- Remediation report row: `docs/remediation/PR-321-reconciliation.md`, with focused results and remaining runtime blockers.
- Hunk classification: PR #321 / owner IDs 27, 31, 32 / `TPM-TRACE-001` / `TPM-OWNER-001` / `TPM-PR321-PROMPT-RESULTS-002`.
- Changelog and user docs: updated the RC8 candidate changelog, `README.md`, `TeknoParrot-Manager-README.txt`, and `TeknoParrot-Manager-QuickStart.txt` with the corrected support, restore, and dgVoodoo2 result guidance; the existing RC8 candidate version remains unchanged.

## 9. Permanent procedure IDs affected

- `TPM-TRACE-001`: each source hunk is mapped to PR #321, exact owner rows, and this contract.
- `TPM-OWNER-001`: source evidence does not substitute for package identity and owner runtime evidence.

## 10. Runtime smoke checklist

- Exact packaged behavior: create a support ZIP, use Open and Back; exercise valid/invalid/cancel choices in all three restore menus without restoring; verify unavailable-device results recommend reconnection and only missing paths route to Health Check.
- Required source/package identity: exact reviewed source commit and package rebuilt from it.
- Evidence artifacts: prompt/result captures and source/package hashes.
- Owner/runtime authorization: not authorized in this task; owner proof remains a release blocker.

## 11. Stop condition

Stop this slice when focused transition tests, source hunk mapping, report rows, source quality gates, and permanent procedure evidence are complete. Keep runtime/package proof outstanding and do not claim global prompt completeness.

## 12. Forbidden actions

No unrelated prompt inventory cleanup, restore transaction redesign, real filesystem restore, support ZIP generation, Explorer launch, package, certification, wiki, ARCADE, or release action.

## 13. Commit/package authorization status

- Commit authorized: No; explicit authorization required
- Package authorized: No
- Release/certification authorized: No
