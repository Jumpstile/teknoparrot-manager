# TPM PostgreSQL Pre-UAC Guidance

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
- Expected behavior: Immediately before each non-administrator PostgreSQL install, password-recovery, or reinitialize handoff, normal mode explains in plain language that temporary administrator access is needed to safely install/repair the local PostgreSQL component/password for the affected games; Windows will show a User Account Control prompt; click Yes; TPM continues automatically after approval without relaunch or choosing PostgreSQL setup again; and access is temporary for this protected operation. Install and recovery use the same expectations. Do not duplicate guidance in a handoff call path.
- Forbidden regressions: No service stop/start mechanics, psql commands, pg_hba.conf, trust authentication, hashes, commands/process internals in default output; no changed fail-closed PostgreSQL behavior or credential exposure; no claim that source tests establish packaged runtime behavior.
- Design boundaries and deliberate exclusions: Keep guidance in `Write-PostgresAdministratorGuidance`; place its single call after workflow waiting status and immediately before `Start-PostgresRecoveryAsAdministrator`. Preserve the existing operation-specific setup/recovery context and protected handoff.

## 5. Source/function ownership

- Files: `TeknoParrot-Manager.ps1`; `Tests/TeknoParrot-Manager.Tests.ps1`; `ARCHITECTURE.md`; `docs/RC8-REMEDIATION-INVENTORY.md`; `docs/remediation/PR-321-control-board.md`; `docs/remediation/PR-321-reconciliation.md`; this contract; `TeknoParrot-Manager-CHANGELOG.txt`.
- Functions/regions: `Write-PostgresAdministratorGuidance`; all non-admin PostgreSQL install, recovery, and reinitialize calls to `Start-PostgresRecoveryAsAdministrator`.
- Owning subsystem: PostgreSQL recovery and UAC resume.

## 6. Tests required before implementation

- Focused failing or characterization tests: Existing beginner-safe guidance tests show the omitted explicit UAC/Yes/temporary semantics; enumerate every production handoff call and identify missing/misordered guidance.
- Source/inventory checks: Confirm each call path is non-admin gated and preserve existing DPAPI/resume and fail-closed recovery boundaries; PG-S07/PG-S08 remain in force.

## 7. Tests required after implementation

- Focused behavior tests: Install and recovery guidance each contain all required beginner semantics and exclude implementation details; every production handoff has exactly one guidance call directly before handoff after any workflow status call; reinitialize is included; existing UAC denial/retry and recovery safety tests remain unchanged.
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

- Exact packaged behavior: In default mode, exercise PostgreSQL installation, password recovery, and reinitialize paths; confirm the required message is immediately before each UAC prompt, click Yes, and observe automatic continuation without relaunch/reselection. Confirm no implementation mechanics appear in beginner output.
- Required source/package identity: Exact pushed source SHA and later separately authorized rebuilt RC8 candidate; this slice does not build a package.
- Evidence artifacts: Captured default-mode screen and log for each path, UAC approval/denial outcome, and exact package/source identity.
- Owner/runtime authorization: Runtime proof remains assigned to the separately authorized package/owner lane; no runtime result is claimed here.

## 11. Stop condition

Stop when the focused tests, report mapping, source gates, and permanent procedure gate are complete. Keep runtime proof separate and release state blocked.

## 12. Forbidden actions

No unrelated cleanup, merge, tag, publication, release, package build, certification, wiki update, or ARCADE work. Commit/push only as explicitly authorized by the owner-provided task after all source gates pass.

## 13. Commit/package authorization status

- Commit authorized: Yes, conditional on all required source gates passing, by the owner-provided task.
- Package authorized: No; explicitly excluded from this lane.
- Release/certification authorized: No; merge/tag/publication/release are prohibited.
