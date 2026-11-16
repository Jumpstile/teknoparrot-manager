# TPM Remediation Slice Contract

## 1. Slice name
- Name: Native PS5.1 InjectionHunter worker dependency
- Contract ID: TPM-RC8-CERT-WORKER-BOOTSTRAP-001
- Issue/PR: #323 / PR #321

## 2. Owner report IDs included
- ID: 36, newly assigned on the actual control board for the confirmed qualification infrastructure failure; not a reassignment of owner 3 or ReShade owners.
- Exact failure: PS5.1 IH worker selects PS7 Utility 7.0.0.0 and cannot resolve Import-PowerShellDataFile. Three matcher tests and the eleven-fact assertion fail; the self-scan independently also times out in PSSA.

## 3. Explicit exclusions
- Other owner IDs, parent product startup, matcher keys/dispositions, findings, timeout budget, scoring and publication are excluded.
- No global PSModulePath changes, TypeData removal, fake analyzer output, softened assertions or suppressing errors.

## 4. Behavior contract
- Current failure: Start-Job starts fresh module state. Parent inbox imports do not initialize the child. The actual analyzer yields the expected finding, then manifest import fails.
- Expected behavior: PS5.1 IH worker explicitly imports the absolute PSHOME inbox Utility manifest with terminating errors before analyzer and data-file use; PS7 resolution is unchanged. Preserve fail-closed job/schema/error/timeout behavior and all findings/dispositions.
- Governing API: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/start-job?view=powershell-5.1 and https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/import-module?view=powershell-5.1 . Applicable contract: dependencies are loaded in the job's process using an explicit module path; no claim of parent session-state inheritance.

## 5. Source/function ownership
- scripts/TPMCertification.ProductionFacts.psm1: Test-TPMProductionInjectionHunterV1 bounded worker.
- Tests/TPMCertification.ProductionFacts.Tests.ps1 and focused child-process boundary regression; this slice inventory.
- Parent owns shared board/report/architecture updates; no sibling source ownership.

## 6. Tests required before implementation
- Existing private NextWorker PS5.1 inherited case fails, inbox Utility contrast passes; PS7 both pass. Exact original three matcher and eleven-fact assertions fail before change; evidence is immutable outside source.
- Retain the existing real matcher assertions and add a new real child regression under conflicting Utility precedence. Sequencing deviation: the new regression is authored after the candidate worker edit; characterize the exact byte-verified pre-edit backup in a disposable copied fixture and the current module separately. This does not retroactively satisfy new-regression-before-candidate-edit timing and requires independent review disposition.

## 7. Tests required after implementation
- Real three matcher cases, eleven-fact construction, real-inventory assertions and child module provenance; native PS5.1/PS7.
- Parent serializes heavy PSSA/IH scans; unchanged 180-second fail-closed budget. If timeout persists, retain failure and investigate measured file/load evidence, never label it IH matching failure.
- Parent runs ASCII/parse, configured PSSA, traced IH dispositions, pinned Pester 5.7.1 main and entire folder per engine, permanent gate and independent gpt-6-astra review.

## 8. Documentation/report updates required
- Board and reconciliation ID 36 assigned before any source edit; status SOURCE REMEDIATION REQUIRED until verified.
- Hunk classification: ID 36 / #323 / this contract / TPM-TRACE-001 / TPM-EVIDENCE-001 / TPM-AUTH-001.
- Inventory before source edit; architecture/lessons reflect actual dependency boundary. No unrelated version identity change in this infrastructure slice.

## 9. Permanent procedure IDs affected
- TPM-TRACE-001, TPM-TRACE-002, TPM-EVIDENCE-001, TPM-AUTH-001, TPM-OWNER-003.

## 10. Runtime smoke checklist
- Real native child worker and complete unchanged real matcher/fact assertions on disposable short private scratch. No live TeknoParrot or real credentials.
- Record engine, module manifest identity, commands, test names, counts and actual exits.

## 11. Stop condition
- Only the demonstrated worker dependency is repaired. Parent final aggregate and source/package gates remain separate; retain timeout/privilege skips and failure evidence.

## 12. Forbidden actions
- No original checkout, global module path/provider/auth changes, real credentials, live runtime writes, commit/push, release/tag/merge/wiki, or concurrent heavy scan.

## 13. Commit/package authorization status
- Commit authorized: No.
- Local smoke package requested only after separate workflow gates.
- Release/certification authorized: No.
