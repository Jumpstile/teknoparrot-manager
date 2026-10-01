# TPM Remediation Slice Contract

## 1. Slice name

- Name: S1 setup and manager-update transaction normalization
- Contract ID: TPM-S1-SETUP-UPDATE-TRANSACTIONS-001
- Issue/PR: PR #321 remediation control board, owner rows 81 and 88

## 2. Owner report IDs included

- IDs: PR #321 owner rows 81 (startup/update flow) and 88 (PostgreSQL profile/database setup)
- Exact owner-visible failures: setup and update callers could receive legacy or boolean-shaped results and could claim completion without one authoritative TPM.TransactionResult.v1 boundary.

## 3. Explicit exclusions

- Owner IDs not included: all other PR #321 rows, including LaunchBox, HyperSpin, thumbnails, optional artifacts/downloads, dgVoodoo2, FFB, and PostgreSQL 12 compatibility.
- Features, modules, package, runtime, and release actions excluded: no new product capability; no package rebuild, release ZIP, owner runtime smoke, Arcade work, wiki work, commit, push, merge, tag, publish, certification, or release-ready declaration.

## 4. Behavior contract

- Current failure: Invoke-PostgresGameSetup and the manager update paths did not expose one validated result contract to their callers; update callers treated booleans as authoritative.
- Expected behavior: Invoke-PostgresGameSetup, Invoke-ManagerUpdateInstall, Invoke-CheckForUpdates, and Invoke-StartupUpdateCheck return TPM.TransactionResult.v1 for every terminal path. The result records pre-state, mutation, backup, final verification, rollback, cleanup, item accounting, outcome, and beginner-safe summary. Callers validate the result and restart or claim completion only for SUCCEEDED.
- Forbidden regressions: no destructive mutation without verified recovery evidence; no false success after failed final verification; no unverified rollback presented as restored; no terminal item overlap or unaccounted item set; no paths, commands, hashes, database names, credentials, or raw exception text in normal summaries; no change to excluded workflows.
- Design boundaries and deliberate exclusions: existing legacy detail properties remain available for current display and workflow code, but Outcome/ProductState and the v1 result are authoritative. No optional download/artifact outer-contract migration is included.

## 5. Source/function ownership

- Files: TeknoParrot-Manager.ps1; Tests/TeknoParrot-Manager.Tests.ps1
- Functions/regions: New-TpmProfileTransactionResult; Invoke-PostgresGameSetup; Get-ManagerUpdatePreState; New-TpmManagerUpdateTransactionResult; Invoke-ManagerUpdateInstall; Invoke-CheckForUpdates; Invoke-StartupUpdateCheck; their top-level callers.
- Owning subsystem: PostgreSQL setup and manager self-update transaction boundaries.

## 6. Tests required before implementation

- Focused failing or characterization tests: existing PostgreSQL setup planning/rollback tests, update install destructive-path tests, CheckForUpdates tests, and StartupUpdateCheck tests; characterization expected booleans and legacy setup properties before normalization.
- Source/inventory checks: parse the production script; inspect all named callers; confirm excluded workflows are unchanged; verify all return branches use the v1 result boundary.

## 7. Tests required after implementation

- Focused behavior tests: PostgreSQL setup planning, no-op, recovery-evidence gate, profile/database rollback, final readback; manager update success, no-op, decline, backup/download/extraction/replacement failures, rollback, read-only restoration, startup release/no-op/decline/failure paths; every result passes Test-TpmTransactionResult.
- Regression suite: Invoke-Pester -Path .\\Tests\\TeknoParrot-Manager.Tests.ps1.
- Static and procedure gates: ASCII check, PowerShell parse check, PSScriptAnalyzer Error/Warning with PSScriptAnalyzerSettings.psd1, InjectionHunter review, git diff --check, and Run-TpmQualityGate against the remediation report when report evidence is available.

## 8. Documentation/report updates required

- Control board row: add the S1 setup/update normalization status and evidence; preserve historical rows.
- Remediation report row: reconcile PR-321-reconciliation.md with the final focused and full-suite counts.
- Hunk classification: source contract implementation, deterministic test updates, and evidence/documentation reconciliation only.
- Changelog or user docs, if applicable: none; this is a remediation contract and does not add user-facing capability.

## 9. Permanent procedure IDs affected

- IDs and evidence: transaction-result validation and owner-runtime proof gates are affected; no new permanent procedure ID was supplied in the owner packet. Runtime proof remains paused and must not be implied by source or test results.

## 10. Runtime smoke checklist

- Exact packaged behavior: not authorized in this slice; source and deterministic tests only.
- Required source/package identity: local worktree C:\\REPOS\\tpm-rc8-certified-a700d093, branch fix/rc8-release-blockers, starting HEAD aa07b5a44824ce6624913c86c46104a9803bd39e.
- Evidence artifacts: focused Pester results, full main Pester result, parser/PSScriptAnalyzer/ASCII/diff checks, and reconciled control-board/remediation evidence.
- Owner/runtime authorization: owner smoke paused; no package or runtime authorization.

## 11. Stop condition

Stop when the contract's focused tests, full regression suite, static checks, report status, and hunk mapping are complete. Do not widen scope to unrelated findings or owner/runtime actions.

## 12. Forbidden actions

No unrelated cleanup, broad rewrite, commit, push, package, release, certification, wiki update, ARCADE work, merge, tag, publish, or owner smoke unless separately authorized.

## 13. Commit/package authorization status

- Commit authorized: No
- Package authorized: No
- Release/certification authorized: No
