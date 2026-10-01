# TPM PostgreSQL Pre-UAC Guidance (superseded by TPM-POSTGRES-RESET-TRANSPORT-001)

## 1. Slice name

- Name: Beginner-safe PostgreSQL administrator and UAC explanation
- Contract ID: TPM-POSTGRES-UAC-GUIDANCE-001
- Issue/PR: PR #321 remediation control board, owner report ID 16

## 2. Owner report IDs included

- IDs: 16
- Exact owner-visible failures: Immediately before PostgreSQL install/recovery elevation, normal-mode guidance says only that Windows needs permission. It does not clearly state temporary administrator access, the UAC prompt, clicking Yes, or that TPM resumes automatically. PostgreSQL reinitialize can hand off without this guidance.

## 3. Explicit exclusions

- Owner IDs not included: Every owner ID other than 16.
- Features, modules, package, runtime, and release actions excluded: PostgreSQL recovery mechanics, security/elevation envelope, unrelated UX, package build, ARCADE/runtime smoke, merge, tag, publication, release assets, and wiki publication.

## 4. Behavior contract

- Current failure: Default-mode guidance before administrator handoff omits key UAC expectations, and some wording is separated from the UAC handoff by workflow status output. One reinitialize handoff lacks guidance.
- Expected behavior: Every non-admin PostgreSQL install, password-recovery, and reinitialize handoff renders the same compact permission panel with temporary-access reason, Windows User Account Control notice, click-Yes action, and automatic continuation; waits for explicit Enter before UAC; and repeats the panel on retry. The protected child remains non-interactive.
- Forbidden regressions: No service stop/start mechanics, psql commands, pg_hba.conf, trust authentication, hashes, commands/process internals in default output; no changed fail-closed PostgreSQL behavior or credential exposure; no claim that source tests establish packaged runtime behavior.
- Design boundaries and deliberate exclusions: This newer contract supersedes the previous caller-level placement rule. `Start-PostgresRecoveryAsAdministrator` owns both panel rendering and the readiness gate inside its retry loop, so every UAC attempt receives one panel immediately before acknowledgement; callers do not duplicate the panel.

## 5. Source/function ownership

- Files: `TeknoParrot-Manager.ps1`; `Tests/TeknoParrot-Manager.Tests.ps1`; `ARCHITECTURE.md`; `docs/RC8-REMEDIATION-INVENTORY.md`; `docs/remediation/PR-321-control-board.md`; `docs/remediation/PR-321-reconciliation.md`; this contract; `TeknoParrot-Manager-CHANGELOG.txt`.
- Functions/regions: `Write-PostgresAdministratorGuidance`; all non-admin PostgreSQL install, recovery, and reinitialize calls to `Start-PostgresRecoveryAsAdministrator`.
- Owning subsystem: PostgreSQL recovery and UAC resume.

## 6. Tests required before implementation

- Focused failing or characterization tests: Existing beginner-safe guidance tests show the omitted explicit UAC/Yes/temporary semantics; enumerate every production handoff call and identify missing/misordered guidance.
- Source/inventory checks: Confirm each call path is non-admin gated and preserve existing DPAPI/resume and fail-closed recovery boundaries; PG-S07/PG-S08 remain in force.

## 7. Tests required after implementation

- Focused behavior tests: The ordered 58-column panel contains the required beginner semantics, excludes implementation details, and precedes the compact Enter gate and `RunAs` in the centralized handoff; retry rendering and protected-child non-interactivity remain covered.
- Regression suite: Focused PostgreSQL/UX Pester tests under PowerShell 7 and Windows PowerShell 5.1.
- Static and procedure gates: Production parse, PSScriptAnalyzer Error/Warning, ASCII, `git diff --check`, and `pwsh -NoProfile -File .\scripts\Run-TpmQualityGate.ps1 -ReportPath .\docs\remediation\PR-321-reconciliation.md`.

## 8. Documentation/report updates required

- Control board row: Owner ID 16, append the beginner UAC guidance correction and runtime proof boundary.
- Remediation report row: Update owner ID 16 tests, changed-file mapping, and exact gate evidence.
- Hunk classification: Owner report ID 16 / TPM-TRACE-001 / TPM-OWNER-001 / PR #321 / TPM-POSTGRES-UAC-GUIDANCE-001.
- Changelog or user docs, if applicable: Record the RC8 candidate correction; update architecture and the PostgreSQL UX invariant inventory.

## 9. Permanent procedure IDs affected

- IDs and evidence: `TPM-TRACE-001` and `TPM-OWNER-001`; owner report ID 16. Record exact source/test/gate results; retain packaged owner-runtime evidence as pending.

## 10. Runtime smoke checklist

- Exact packaged behavior: Exercise PostgreSQL installation, password recovery, and reinitialize paths; confirm the panel and readiness acknowledgement precede each UAC prompt, click Yes, and observe automatic continuation without relaunch/reselection. Confirm no implementation mechanics appear in beginner output.
- Required source/package identity: Exact pushed source SHA and diagnostic-only exact-head package, as defined by the superseding transport contract; the package is not a release candidate.
- Evidence artifacts: Captured default-mode screen and log for each path, UAC approval/denial outcome, and exact package/source identity.
- Owner/runtime authorization: The diagnostic package is authorized for later ARCADE diagnosis by the 2026-10-01 owner directive. ARCADE runtime execution remains pending and outside this worktree; no runtime proof is claimed.

## 11. Stop condition

Stop when the focused tests, report mapping, source gates, and permanent procedure gate are complete. Keep runtime proof separate and release state blocked.

## 12. Forbidden actions

No unrelated cleanup, merge, tag, publication, release, package build, certification, wiki update, or ARCADE work. Commit/push only as explicitly authorized by the owner-provided task after all source gates pass.

## 13. Commit/package authorization status

- Commit/push authorized: Yes, conditional on required source gates passing, by the 2026-10-01 owner directive.
- Diagnostic exact-head package authorized after commit/push for later ARCADE diagnosis only; ARCADE runtime execution is pending and outside this worktree.
- Release/certification authorized: No; merge/tag/publication/release are prohibited.
