# TPM Remediation Slice Contract

## 1. Slice name

- Name: LaunchBox restore copy must report failure
- Contract ID: TPM-RC8-LANE-F-336
- Issue/PR: #336

## 2. Owner report IDs included

- IDs: #336
- Exact owner-visible failures: a LaunchBox restore reports success ("Restore complete", "Restore finished and was verified") even when a file copy failed without a terminating error.

## 3. Explicit exclusions

- Owner IDs not included: #335, #337, #364, and all others.
- Features, modules, package, runtime, and release actions excluded: no rollback of already restored files, no new readback or hashing, no change to caller wording.

## 4. Behavior contract

- Current failure: `Copy-Item` in the restore loop of `Invoke-RestoreLaunchBoxBackup` (28671 in ba54ae5) has no `-ErrorAction Stop`. A nonterminating failure skips the catch at 28672, `$errCount` stays 0, and the function returns `Succeeded = $true` (28688). The caller at 33990 then reports success (34000-34002).
- Expected behavior: a copy failure throws, reaches the catch, increments `$errCount`, and the function returns `Succeeded = $false` (28684).
- Forbidden regressions: successful restores still return `Succeeded = $true`; the path-escape check (28669) is unchanged.
- Design boundaries and deliberate exclusions: already-restored files are not rolled back; the message at 28682 already reports the restore as not completed.

## 5. Source/function ownership

- Files: TeknoParrot-Manager.ps1
- Functions/regions: `Invoke-RestoreLaunchBoxBackup` restore loop (28663-28676 in ba54ae5), line 28671.
- Owning subsystem: LaunchBox integration.

## 6. Tests required before implementation

- Focused failing or characterization tests: none run (owner hold; static review only).
- Source/inventory checks: confirm the only caller of `Invoke-RestoreLaunchBoxBackup` is 33990.

## 7. Tests required after implementation

- Focused behavior tests: a restore copy failure must return `Succeeded = $false` with `ErrorCount` greater than 0.
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

Stop when line 28671 carries `-ErrorAction Stop` and the line is read back. Do not widen scope.

## 12. Forbidden actions

No unrelated cleanup, broad rewrite, commit, push, package, release, certification, wiki update, test-PC work, or owner smoke unless separately authorized.

## 13. Commit/package authorization status

- Commit authorized: No, explicit authorization required
- Package authorized: No, explicit authorization required
- Release/certification authorized: No, explicit authorization required
