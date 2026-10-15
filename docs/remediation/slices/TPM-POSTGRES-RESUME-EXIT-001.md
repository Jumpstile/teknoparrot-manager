# TPM Protected PostgreSQL Resume Exit

## 1. Slice name

- Name: Protected PostgreSQL resume deterministic child exit
- Contract ID: TPM-POSTGRES-RESUME-EXIT-001
- Issue/PR: PR #321 remediation control board, owner report ID 16

## 2. Owner report IDs included

- IDs: 16
- Exact owner-visible failures: After a protected PostgreSQL recovery attempt, the elevated child TPM window waits for an Enter key on failure or successful completion instead of terminating and returning control to the original TPM window.

## 3. Explicit exclusions

- Owner IDs not included: Every owner ID other than 16.
- Features, modules, package, runtime, and release actions excluded: PostgreSQL recovery mutation logic, backup/reset ordering, service-state restoration, credential handling, UAC envelope issuance/validation/retry, package rebuild, Arcade installation, owner-runtime certification, merge, tag, publication, release assets, and wiki updates. Normal non-resume interaction is in scope only for regression protection.

## 4. Behavior contract

- Current failure: Protected-resume terminal paths can call Read-HostSafe before exit, leaving the elevated child window waiting for console input.
- Expected behavior: Every protected-resume failure exits the elevated child deterministically with its intended nonzero exit code after retry-state issuance and terminal cleanup. Protected-resume success exits the elevated child with code 0 after verified completion and state cleanup. Neither path prompts or falls into the main menu. The original TPM process retains its existing UAC handoff contract and receives the child exit result.
- Forbidden regressions: No protected-resume failure may report completion, skip fail-closed handling, lose a safe retry state, expose credentials, bypass backup/verification/rollback/mutation gates, or omit original PostgreSQL service-state restoration. Normal non-resume PostgreSQL/UI prompts must remain present and functional.
- Design boundaries and deliberate exclusions: Only the elevated child identified by the protected-resume path is non-interactive at its terminal boundary. Ordinary PostgreSQL setup and all unrelated TPM screens remain interactive. UAC denial and parent-side retry prompts remain parent-owned and interactive.

## 5. Source/function ownership

- Files: `TeknoParrot-Manager.ps1`; `Tests/TeknoParrot-Manager.Tests.ps1`; `docs/RC8-REMEDIATION-INVENTORY.md`; `docs/remediation/PR-321-control-board.md`; `docs/remediation/PR-321-reconciliation.md`; `TeknoParrot-Manager-CHANGELOG.txt`.
- Functions/regions: `Exit-PostgresRecoveryResume`; the protected-resume success branch in the `PostgresSetup` mode; normal non-resume PostgreSQL terminal prompts; existing UAC child handoff.
- Owning subsystem: PostgreSQL recovery and UAC resume.

## 6. Tests required before implementation

- Focused failing or characterization tests: Existing resume source-contract tests and the real `Exit-PostgresRecoveryResume` function body establish the protected terminal boundary; add process-level probes that fail if either terminal path invokes `Read-HostSafe` or `Read-Host`.
- Source/inventory checks: Verify all protected-resume terminal exits are deterministic, the main menu is unreachable after resume completion/failure, and PG-S07/PG-S08/PG-S09 invariants remain represented.

## 7. Tests required after implementation

- Focused behavior tests: protected-resume failure exits without `Read-HostSafe`/`Read-Host`; protected-resume success exits without either prompt; normal non-resume PostgreSQL/UI paths retain intended prompts; protected-resume terminal branches have no console wait immediately before exit.
- Regression suite: Focused PostgreSQL/UAC Pester tests under PS7 and Windows PowerShell 5.1, then the full relevant Pester suite.
- Static and procedure gates: Production parser clean, ASCII clean, PSScriptAnalyzer Error/Warning clean with `PSScriptAnalyzerSettings.psd1`, `git diff --check` clean, and the required remediation procedure gate evidence.

## 8. Documentation/report updates required

- Control board row: Update owner ID 16 with this source remediation contract and retain owner-runtime proof as outstanding.
- Remediation report row: Add the exact protected-resume terminal test names, changed-file mapping, and source/package/runtime evidence boundary.
- Hunk classification: Map source and test hunks to owner ID 16, `TPM-POSTGRES-RESUME-EXIT-001`, and the PR #321 remediation gate.
- Changelog or user docs, if applicable: Add one concise RC8 candidate changelog entry; no user guide behavior change beyond automatic child-window closure.

## 9. Permanent procedure IDs affected

- TPM-TRACE-001: Source hunk ownership and traceability in the control board/report.
- TPM-OWNER-001: Owner-visible behavior remains source-fixed but requires packaged runtime proof.
- PR #321 fail-closed remediation gate: Report, inventory, focused tests, and non-actions remain explicit.

## 10. Runtime smoke checklist

- Exact packaged behavior: Start the protected PostgreSQL recovery flow from the original TPM window, approve UAC, and observe that both successful and failed elevated children close without an Enter prompt; the original TPM window regains control or shows the existing parent-side retry/stop prompt.
- Required source/package identity: Exact pushed SHA and a rebuilt RC8 candidate package based on that SHA; no stale package may be used as proof.
- Evidence artifacts: Captured child exit code, parent-side routing, console transcript, and PostgreSQL service-state/retry evidence from the authorized runtime.
- Owner/runtime authorization: Not authorized by this slice; Desktop ChatGPT review and later explicit owner-runtime authorization remain required.

## 11. Stop condition

Stop when the focused tests, full relevant suite, static gates, changelog, inventory, control-board mapping, remediation report mapping, and implementation packet evidence are complete. Do not widen scope to unrelated findings.

## 12. Forbidden actions

No unrelated cleanup, broad rewrite, package rebuild, release asset change, merge, tag, publication, wiki update, ARCADE work, live-installation change, or owner smoke unless separately authorized.

## 13. Commit/package authorization status

- Commit authorized: Yes, by the explicit user boundary after required validation passes
- Package authorized: No
- Release/certification authorized: No
