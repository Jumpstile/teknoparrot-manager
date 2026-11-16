# TPM Remediation Slice Contract

## 1. Slice name
- Name: Receipt history snapshot error preservation.
- Contract ID: TPM-REQUIRED-PATCH-SNAPSHOT-ERROR-001.
- Issue/PR: #351; RC8 validation gate #323; integration PR #321.

## 2. Owner report IDs included
- IDs: Issue #351 under TPM-REQUIRED-PATCHES-REVIEW-001. No numbered PR #321 owner-report row is assigned or promoted.
- Exact failure: New-TpmResetSnapshot catch reads an undeclared result variable, masking the original failure or mutating caller state. The retained pre-change diagnostic reported 34 missing-Reason failures and 30 separate safety-guard failures.

## 3. Explicit exclusions
- No recipe, catalog, filesystem safety guard, payload, live game, original checkout, package, release, or unrelated fixture change.

## 4. Behavior contract
- Return a fresh FAILED/UNVERIFIED result with the caught exception message. Preserve success/reuse behavior and existing finally disposal.
- Never claim failed publication left no artifact or performed cleanup. Preserve caller-owned results, existing manifests, containment, reparse, identity, sharing, hash, and boundary guards.

## 5. Source/function ownership
- scripts/TpmRequiredPatchEngine.ps1: New-TpmResetSnapshot catch only.
- Tests/TpmRequiredPatchNativeMainComponentRestorations.Tests.ps1: five snapshot regressions in the existing Describe.
- Owning subsystem: #351 required-patch receipt history; direct consumer New-TpmMultiPatchTerminalCheckpoint.

## 6. Tests required before implementation
- Retained diagnostic: 165 total, 101 passed, 64 failed; historical baseline only.
- Freshly verify ten source pins and unique insertion context; inspect inherited helpers/mocks and direct consumer; parse assembled proposal without execution. These checks were completed before applying.

## 7. Tests required after implementation
- Five cases: invalid ID and outer sentinel, create/reuse, forced readback failure with observable manifest, mismatched existing checkpoint, and consumer reason/argument propagation.
- Run preserved three-suite diagnostic with a separately identified runner changing only engine/test pins. Keep the other eight source pins and all guards unchanged.
- ASCII/parse PS5.1 and PS7, configured PSScriptAnalyzer, InjectionHunter review, central Pester 5.7.1, and permanent quality gate remain required; record actual results and limitations.

## 8. Documentation/report updates required
- Append bounded #351 mapping to control board and reconciliation report; update architecture and native invariant inventory.
- Every changed hunk maps to #351 / TPM-REQUIRED-PATCH-SNAPSHOT-ERROR-001 / TPM-TRACE-001 / TPM-EVIDENCE-001 / TPM-TRUTH-001.
- Existing RC8 release identity and distributable files remain unchanged; this is candidate remediation, not a published version bump.

## 9. Permanent procedure IDs affected
- TPM-TRACE-001: explicit source/test/document mapping.
- TPM-EVIDENCE-001: exact source and runner hashes, commands, counts, exits, and timestamps.
- TPM-TRUTH-001: static review, execution, source validation, and runtime readiness remain distinct.

## 10. Runtime smoke checklist
- Synthetic local receipt fixtures only. No live game or packaged runtime proof is claimed.
- Owner authorized applying this reviewed patch and tests in the isolated candidate on 2026-10-24.

## 11. Stop condition
- Stop after reviewed two-file patch, validation results, and mapping evidence are recorded. Report remaining failures without weakening guards or silently expanding remediation scope.

## 12. Forbidden actions
- No commit, push, main merge, package, release, live wiki, live game write, original checkout write, or owner smoke handoff.

## 13. Commit/package authorization status
- Commit, package, and release: not authorized.
- Candidate edits and local tests: explicitly authorized. Focused 170/170 passes on each engine; central PS5.1 1524/1524, PS7 1523 passed/one skipped, zero failures. Static checks pass; see dated reconciliation evidence and limitations.