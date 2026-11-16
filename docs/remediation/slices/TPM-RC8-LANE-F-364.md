# TPM Remediation Slice Contract

## 1. Slice name

- Name: dgVoodoo2 transaction accepts empty operation set
- Contract ID: TPM-RC8-LANE-F-364
- Issue/PR: #364

## 2. Owner report IDs included

- IDs: #364
- Exact owner-visible failures: a dgVoodoo2 deployment with no operations to perform (all targets already current) fails at parameter binding instead of completing as a no-op.

## 3. Explicit exclusions

- Owner IDs not included: #335, #336, #337, and all others.
- Features, modules, package, runtime, and release actions excluded: no change to the shared transaction routine, no change to preflight or error branches.

## 4. Behavior contract

- Current failure: `Invoke-TpmDgVoodoo2FileTransaction` declares `[Parameter(Mandatory)][object[]]$Operations` (6171). Its caller (14360) passes `$deploymentOperations.ToArray()`, which is empty when nothing needs deploying. PowerShell rejects an empty collection for a Mandatory parameter without `AllowEmptyCollection`.
- Expected behavior: an empty array reaches `Invoke-TpmTransactionalFileBatch`, which already handles empty input (shared routine 5468-5480 in ba54ae5).
- Forbidden regressions: non-empty calls unchanged; the Mandatory check for null stays in force.
- Design boundaries and deliberate exclusions: the fix is the attribute only.

## 5. Source/function ownership

- Files: TeknoParrot-Manager.ps1
- Functions/regions: `Invoke-TpmDgVoodoo2FileTransaction` parameter (6170-6172 in ba54ae5).
- Owning subsystem: dgVoodoo2 setup.

## 6. Tests required before implementation

- Focused failing or characterization tests: none run (owner hold; static review only).
- Source/inventory checks: confirm the shared routine at 5468-5480 accepts empty input, and that the caller at 14360 is the only caller.

## 7. Tests required after implementation

- Focused behavior tests: an empty `-Operations @()` call must return the routine's no-op result, not a binding error.
- Regression suite: Tests\TeknoParrot-Manager.Tests.ps1 (run by main agent).
- Static and procedure gates: ASCII check, parse check, PSScriptAnalyzer with PSScriptAnalyzerSettings.psd1.

## 8. Documentation/report updates required

- Control board row: docs\remediation\PR-321-control-board.md (main agent).
- Remediation report row: docs\remediation\RC8-BLOCKER-RECONCILIATION-LANE-F.md.
- Hunk classification: one-attribute defect fix.
- Changelog or user docs, if applicable: main agent decides at release time.

## 9. Permanent procedure IDs affected

- IDs and evidence: none identified in this lane.

## 10. Runtime smoke checklist

- Exact packaged behavior: not run (owner hold).
- Required source/package identity: not applicable in this lane.
- Evidence artifacts: none.
- Owner/runtime authorization: required before any runtime check.

## 11. Stop condition

Stop when line 6171 carries `[AllowEmptyCollection()]` and the line is read back. Do not widen scope.

## 12. Forbidden actions

No unrelated cleanup, broad rewrite, commit, push, package, release, certification, wiki update, test-PC work, or owner smoke unless separately authorized.

## 13. Commit/package authorization status

- Commit authorized: No, explicit authorization required
- Package authorized: No, explicit authorization required
- Release/certification authorized: No, explicit authorization required
