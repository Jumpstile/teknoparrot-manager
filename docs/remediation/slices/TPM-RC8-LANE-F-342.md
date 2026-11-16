# TPM Remediation Slice Contract

Historical contract. FIX108 supersedes the missing-reference outcome and handoff described here: these games are now design skips, carried in `DesignSkippedItems` and listed as information in Details, the log, and the saved report. They do not independently trigger ACTION REQUIRED. Failed saves remain errors.

## 1. Slice name

- Name: No-archetype control items must survive non-SUCCEEDED propagation outcomes
- Contract ID: TPM-RC8-LANE-F-342
- Issue/PR: #342

## 2. Owner report IDs included

- IDs: #342
- Exact owner-visible failures: when control propagation finishes with `PARTIAL_APPLIED` (or any non-`SUCCEEDED` outcome), the `NoArchetypeItems` collected by `Write-ControlPropagationResults` are dropped, so the ACTION REQUIRED report omits the no-archetype items.

## 3. Explicit exclusions

- Owner IDs not included: #331, #332, #334, #335, #336, #337, #338, #340, #341, #364, #368, #369.
- Features, modules, package, runtime, and release actions excluded: no change to the outcome computation at 27647, no change to `BoundCount` semantics, no change to the ACTION REQUIRED text.

## 4. Behavior contract

- Current failure: `$noArchetypeItems = $propResult.NoArchetypeItems` (36543 in worktree ba54ae5) runs only inside `if ($propTransaction.Outcome -eq 'SUCCEEDED')` (36541). `Invoke-ControlPropagation` returns `PARTIAL_APPLIED` when some items changed and some were skipped, and no-archetype items are counted as skipped (27646, 27647), so the list is discarded in exactly the case it is needed.
- Expected behavior: `$noArchetypeItems` is assigned from `$propResult.NoArchetypeItems` for every outcome. The SUCCEEDED-only block keeps its other behavior unchanged.
- Forbidden regressions: `SUCCEEDED` runs still print the same messages; `$noArchetypeItems` remains `@()` when the propagation step is skipped (36482).
- Design boundaries and deliberate exclusions: no change to how outcomes are computed.

## 5. Source/function ownership

- Files: TeknoParrot-Manager.ps1
- Functions/regions: propagation caller block (36537-36552 in worktree ba54ae5), lines 36541-36543.
- Owning subsystem: control propagation reporting.

## 6. Tests required before implementation

- Focused failing or characterization tests: none run (owner hold; static review only).
- Source/inventory checks: confirm `$noArchetypeItems` is initialized at 36482 and consumed at 37674.

## 7. Tests required after implementation

- Focused behavior tests: a propagation result with `PARTIAL_APPLIED` and non-empty `NoArchetypeItems` must populate the ACTION REQUIRED no-archetype section.
- Regression suite: Tests\TeknoParrot-Manager.Tests.ps1 (run by main agent).
- Static and procedure gates: ASCII check, parse check, PSScriptAnalyzer with PSScriptAnalyzerSettings.psd1.

## 8. Documentation/report updates required

- Control board row: docs\remediation\PR-321-control-board.md (main agent).
- Remediation report row: docs\remediation\RC8-BLOCKER-RECONCILIATION-LANE-F.md.
- Hunk classification: one-hunk assignment move.
- Changelog or user docs, if applicable: main agent decides at release time.

## 9. Permanent procedure IDs affected

- IDs and evidence: none identified in this lane.

## 10. Runtime smoke checklist

- Exact packaged behavior: not run (owner hold).
- Required source/package identity: not applicable in this lane.
- Evidence artifacts: none.
- Owner/runtime authorization: required before any runtime check.

## 11. Stop condition

Stop when the assignment is moved ahead of the SUCCEEDED branch and the lines are read back. Do not widen scope.

## 12. Forbidden actions

No unrelated cleanup, broad rewrite, commit, push, package, release, certification, wiki update, test-PC work, or owner smoke unless separately authorized.

## 13. Commit/package authorization status

- Commit authorized: No, explicit authorization required
- Package authorized: No, explicit authorization required
- Release/certification authorized: No, explicit authorization required
