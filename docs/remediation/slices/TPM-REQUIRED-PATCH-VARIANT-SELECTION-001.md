# TPM Remediation Slice Contract

## 1. Slice name

- Name: Schema-3 required-patch variant collection normalization.
- Contract ID: `TPM-REQUIRED-PATCH-VARIANT-SELECTION-001`.
- Issue/PR: Issue #351, under the existing local required-patch review lane and parent contract `TPM-REQUIRED-PATCHES-REVIEW-001`. No GitHub handoff is authorized.

## 2. Owner report IDs included

- IDs: Issue #351, the existing owner-authorized required-patch issue. No numbered PR #321 owner-report row is assigned, and no PR #321 owner-report status changes.
- Exact finding: the saved PowerShell 5.1.26100.9711 / Pester 5.7.1 candidate run reports `PropertyNotFoundException: The property 'Count' cannot be found` from `Resolve-TpmPatchVariantDecision` at engine line 232 when an exclusive group filters to one applicable entry. The existing test expects that exact single variant to be selected. An in-memory extraction of the production helper reproduces the error under Windows PowerShell 5.1 strict mode; PowerShell 7.6.5 returns `SELECTED`. This is a source-validation failure, not an owner-reported gameplay or live-runtime symptom.
- Baseline source identities: engine SHA-256 `5118313C8F03E7AC3BDD4A0E24644D9FF23C218EEA080075E445D391D346D5FE`; resolver-function UTF-8 extent SHA-256 `4D7C75092163EC276F8F5662F78DB048E2E7C56B220CDEB1C4BB5AE7AE94A352`; Main test SHA-256 `79112B80BE7C4F6C43F560A3AEA57BC63FE13DAD21B671F8C52F3B09B8B046F1`.
- Preserved full-suite receipt SHA-256: `A06AB583CD1045A6D50262DDFF78B2D385E55FAF9FAA807BEE0381F59A30CF94`. It records 2,786 passed, 205 failed, and 2 skipped from 2,993 discovered. This slice addresses only the confirmed variant-selection defect; ZIP-guard and other failure families remain separate.

## 3. Explicit exclusions

- No recipe/catalog, source ZIP, executable identity, target path, hardware predicate, receipt, transaction, menu, release package, or user-facing text changes.
- No resolution or reclassification of the separate source-ZIP guard failures.
- No Pester invocation, full-suite rerun, registry/CIM access, live TeknoParrot operation, owner-runtime proof, package, release, commit, or GitHub action in this task.

## 4. Behavior contract

- Current failure: `$variants` is assigned from a value-producing `if` expression. Windows PowerShell 5.1 can yield a scalar for one match; under strict mode, the following `$variants.Count` throws.
- Expected behavior: normalize the variant result at the assignment boundary so zero, one, and multiple entries have stable collection cardinality on Windows PowerShell 5.1 and PowerShell 7. A missing requested identity remains `INVALID`; one exact applicable variant is `SELECTED`; multiple unqualified same-build variants remain `AMBIGUOUS`; ambiguous hardware evidence remains `AMBIGUOUS`.
- Forbidden regressions: do not weaken exact recipe/profile/executable matching, exclusive-group boundaries, hardware-evidence requirements, or fail-closed ambiguity behavior. Do not add recipes or capabilities.

## 5. Source/function ownership

- Files: `scripts/TpmRequiredPatchEngine.ps1`, `Tests/TeknoParrot-Manager.Tests.ps1`, `ARCHITECTURE.md`, this contract, `docs/remediation/slices/README.md`, `docs/remediation/PR-321-control-board.md`, and `docs/remediation/PR-321-reconciliation.md`.
- Functions/regions: only `Resolve-TpmPatchVariantDecision` and focused direct/Pester coverage for its cardinality and ambiguity outcomes.
- Owning subsystem: Issue #351 required-patch catalog, mapped through parent contract `TPM-REQUIRED-PATCHES-REVIEW-001`.

## 6. Tests required before implementation

- Preserve the existing full-suite receipt and exact pre-change engine/function/test hashes above.
- Required baseline characterization: the four-case direct production-function matrix under strict mode for zero matching identity, one selected variant, multiple unqualified variants, and ambiguous hardware evidence. PowerShell 7.6.5 passed 4/4 before the source change (receipt PS7-Before-Inline.json, SHA-256 C7B6E7080485A5B92D887D741D4F497CFE25E17B3DA27E3D5259D3E39D378919). The Windows PowerShell 5.1 file-based runner was blocked as unsigned; no approved PS5.1 baseline matrix exists. Do not invoke Pester.

## 7. Tests required after implementation

- Add focused Pester regressions for the four outcomes above and a production integration case that exercises Get-TpmPatchPlan, Resolve-TpmPatchVariantDecision, Invoke-TpmCatalogPatch, and receipt undo on a synthetic fixture. Preserve exact before/after hashes and the function/test diff.
- Approved post-change checks recorded: PowerShell 7.6.5 strict-mode direct matrix 4/4 (receipt PS7-After.json, SHA-256 6A4BAD45B39E6B264C06FB86421C1AE96E5FD48AB0734D1C5BA781262FA66D57) and parser checks with zero errors for the engine, central test file, and main script (receipt PS7-Parse-Final.json, SHA-256 CDB595D17C0069453EBCDEC8840F97AEDAAFB37B5C015CCFB64D315730429F56).
- Windows PowerShell 5.1: the temporary .ps1 runner was blocked as unsigned; execution policy was not changed, and no durable denial receipt exists. PS51-Before-Inline.json (SHA-256 0369BA99D1528627ED8297D489015A14FD3FA7A55B24F15BE69953215FB43E57) records a malformed command containing a literal \r\n token; it is not the unsigned-file denial. PS51-Before-Inline-Retry.json (SHA-256 CDEB03B825D10ED07D3F20C9B953FD16093A53E7A13E08735F3953E4FCCF9914) is a preserved encoded baseline result, excluded from verification and not to be replayed. No approved PS5.1 baseline or post-change result exists.
- An earlier focused Pester startup attempt was denied access to HKCU\Software\Pester; do not retry it or use registry/CIM alternatives. The full suite was not rerun. Its historical receipt is not post-change evidence.
- The direct PS7 helper matrix does not certify production integration; the new synthetic Pester integration case has not been executed.

## 8. Documentation/report updates required

- Control board: record this narrow Issue #351 follow-up and its exact evidence without changing PR #321 owner-report status.
- Remediation report: record before/after input hashes, diff, direct-check commands/results, and the no-Pester boundary.
- Hunk mapping: engine helper, focused tests, and architecture note -> Issue #351 / this contract / `TPM-TRACE-001`, `TPM-EVIDENCE-001`, and `TPM-TRUTH-001`.
- No changelog or user-document update is needed because this restores existing behavior without adding a capability or changing release identity.

## 9. Permanent procedure IDs affected

- `TPM-TRACE-001`: map every source/test/documentation hunk to Issue #351 and this contract.
- `TPM-EVIDENCE-001`: preserve exact source/test hashes and direct reproduction evidence.
- `TPM-TRUTH-001`: keep the recorded Pester/runtime validation status precise. No new permanent procedure ID is introduced.

## 10. Runtime smoke checklist

- Exact packaged behavior: not claimed in this source-only slice.
- Required source/package identity: synthetic in-memory recipe objects only; no candidate ZIP or installed game is used.
- Evidence artifacts: exact before/after source and test hashes, approved PS7 direct/parse receipts, and the reviewable function/test diff. The PS5.1 diagnostic receipts remain explicitly excluded as described above.
- Owner/runtime authorization: no owner-runtime action is part of this task; Issue #351 runtime acceptance remains separate.

## 11. Stop condition

Stop after the minimal helper change and five focused regression cases are reviewable, the approved PS7 direct matrix and parser receipts are recorded, exact hashes/diffs are preserved, the candidate manifest is refreshed, and report mappings are synchronized. PS5.1 and production-integration execution remain unverified until an approved signed-runner route is established. Do not run Pester or the full suite in this task.

## 12. Forbidden actions

No catalog expansion, unrelated cleanup, Pester/full-suite rerun, registry/CIM access, live game or runtime operation, owner handoff, commit, push, package, release, or wiki update.

## 13. Commit/package authorization status

- Commit authorized: No.
- Package authorized: No.
- Release/certification authorized: No.
- Local verification status: PS7 direct and parser checks passed; PS5.1 and production-integration execution remain unverified.
