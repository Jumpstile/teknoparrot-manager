# TPM Remediation Slice Contract

## 1. Slice name

- Name: LaunchBox backup copy must fail on copy error
- Contract ID: TPM-RC8-LANE-F-335
- Issue/PR: #335

## 2. Owner report IDs included

- IDs: #335
- Exact owner-visible failures: a failed LaunchBox backup copy does not stop the direct write, so LaunchBox files can be changed without a usable backup.

## 3. Explicit exclusions

- Owner IDs not included: #336, #337, #364, and all others.
- Features, modules, package, runtime, and release actions excluded: no change to the missing-source skip, no change to the path-escape check, no new backup format.

## 4. Behavior contract

- Current failure: `Copy-Item` in `Backup-LaunchBoxFiles` (28542 in ba54ae5) has no `-ErrorAction Stop`. A nonterminating copy error skips the catch at 28544, so the function returns `$backupPath` (28554) and the caller proceeds with the write.
- Expected behavior: a copy error throws, the catch logs and returns `$null`, and `Invoke-LaunchBoxDirectWrite` aborts before any write (30409-30413 already handle `$null`).
- Forbidden regressions: a missing source file still skips (28535); the success path and return value are unchanged.
- Design boundaries and deliberate exclusions: the fix is one parameter on one call.

## 5. Source/function ownership

- Files: TeknoParrot-Manager.ps1
- Functions/regions: `Backup-LaunchBoxFiles` (28521-28555 in ba54ae5), line 28542.
- Owning subsystem: LaunchBox integration.

## 6. Tests required before implementation

- Focused failing or characterization tests: none run (owner hold; static review only).
- Source/inventory checks: confirm the only caller of `Backup-LaunchBoxFiles` is the direct-write path at 30408.

## 7. Tests required after implementation

- Focused behavior tests: a locked or unreadable source must make the function return `$null`.
- Regression suite: Tests\TeknoParrot-Manager.Tests.ps1 (run by main agent).
- Static and procedure gates: ASCII check, parse check, PSScriptAnalyzer with PSScriptAnalyzerSettings.psd1.

## 8. Documentation/report updates required

- Control board row: docs\remediation\PR-321-control-board.md (main agent).
- Remediation report row: docs\remediation\RC8-BLOCKER-RECONCILIATION-LANE-F.md.
- Hunk classification: one-parameter defect fix.
- Changelog or user docs, if applicable: main agent decides at release time.

## 9. Permanent procedure IDs affected

- IDs and evidence: none identified in this lane.

## 10. Runtime smoke checklist

- Exact packaged behavior: not run (owner hold).
- Required source/package identity: not applicable in this lane.
- Evidence artifacts: none.
- Owner/runtime authorization: required before any runtime check.

## 11. Stop condition

Stop when line 28542 carries `-ErrorAction Stop` and the line is read back. Do not widen scope.

## 12. Forbidden actions

No unrelated cleanup, broad rewrite, commit, push, package, release, certification, wiki update, test-PC work, or owner smoke unless separately authorized.

## 13. Commit/package authorization status

- Commit authorized: No, explicit authorization required
- Package authorized: No, explicit authorization required
- Release/certification authorized: No, explicit authorization required
