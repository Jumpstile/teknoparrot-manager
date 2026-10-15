# TPM Remediation Slice Contract

## 1. Slice name

- Name: MaiMai GreeN and Rabbids Hollywood Main-component restores
- Contract ID: `TPM-REQUIRED-PATCH-MAIN-EXTRAS-20261015`
- Issue/PR: Issue #351; no PR or publication authorization

## 2. Owner report IDs included

- IDs: None assigned in the authorized scope.
- Exact owner-visible failures: No owner-runtime report is claimed. The slice covers exact guide-named Main components and source identities only.

## 3. Explicit exclusions

- Owner IDs not included: All unassigned owner-report rows; no owner/runtime acceptance is inferred.
- Features, modules, package, runtime, and release actions excluded: Any other game repair, source acquisition, runtime install, executable/payload execution, registry or `.conf` edits, launch/gameplay validation, packaging, commit, push, release, and changes to the 58-entry parent staging tree.

## 4. Behavior contract

- Current failure: The guide names the MaiMai GreeN `freeglut.dll` and `libcurl.dll` Main components and the Rabbids Hollywood `RabbidsHollywood_Operator.exe`; the recipes supply an absent-only repair for each exact profile/build/executable identity.
- Expected behavior: Stage only the exact local Main ZIP member after profile, build, executable, source-size, SHA-1, and SHA-256 pins match. Create the target only when absent. Recognize exact-after bytes without rewriting; refuse unknown existing bytes; undo only from the recipe's exact transaction receipt.
- Forbidden regressions: No replacement of existing files; no execution; no new prerequisites, hardware predicates, or setup claims; no widening to shared state; no modification of the historical 58-entry worktree or its source inputs.
- Design boundaries and deliberate exclusions: Three separate single-file operations; MaiMai DLLs are not atomic as a pair. The Rabbids operator executable is distinct from the existing Assembly-CSharp and BepInEx operator-plugin entries. No installed target was inspected or changed.

## 5. Source/function ownership

- Files: `scripts/TpmRequiredPatchRecipes.json`; catalog pin line in `scripts/TpmRequiredPatchEngine.ps1`; `tools/required-patches/fragments/main-component-restores-followup-20261015.json`; `Tests/TpmRequiredPatchMainExtras.Tests.ps1`; `.github/workflows/ci.yml`; the follow-up inventory and boundary note.
- Functions/regions: Existing schema-3 catalog loader, payload staging, planner, apply, read-back, receipt, and undo paths; no engine function changes.
- Owning subsystem: Required-patch catalog and existing shared transaction engine.

## 6. Tests required before implementation

- Focused failing or characterization tests: Existing standalone three-entry characterization from the preceding candidate lane exercised source pins and synthetic apply/read-back/idempotency/receipt-undo/foreign-byte refusal. The new integrated tests must bind to this worktree's catalog and current engine identity.
- Source/inventory checks: Exact guide ArrayIndex and SourcePath are distinct and recorded in the corrected boundary; verify three catalog rows, exact source identity metadata, unique IDs, 61 total recipes, 23 ProfileIds, 53 CreateFile and eight ReplaceFile operations, and matching catalog/engine pin.

## 7. Tests required after implementation

- Focused behavior tests: `Tests/TpmRequiredPatchMainExtras.Tests.ps1` used Pester 5.7.1 under PowerShell 7 and Windows PowerShell 5.1; each passed 2/2, zero failures/skips/inconclusive. The integrated set selected five manager catalog/resolver/transaction guards, six existing plugin-lane tests, and these two new tests: 13 selected passed on each engine; 1,483 of 1,488 discovered manager tests were not run.
- Tests prove exact pins, integrated aggregate counts, absent create, read-back, repeat skip, receipt undo, and foreign-byte refusal for all three entries.
- Regression suite: No full Main, Support, or canonical suite in this bounded lane.
- Static and procedure gates: JSON parse, unique IDs, catalog SHA-256 pin, explicit CI path, unchanged engine body apart from pin, and private evidence hashes verified. Root owns broader gates.

## 8. Documentation/report updates required

- Control board row: Append a 61-entry follow-up checkpoint to `docs/remediation/PR-321-control-board.md`; preserve all previous 58-entry history.
- Remediation report row: Map this candidate to Issue #351 and the existing required-patches trace/evidence/truth/owner/UX procedures; no numbered PR #321 owner row is assigned.
- Hunk classification: Three exact schema-3 CreateFile catalog records, one engine catalog-hash pin, one focused Pester test and CI route, and this slice's evidence/documentation. The catalog change was made before this versioned slice document was written; this records an ordering deviation, not retroactive compliance.
- Changelog or user docs, if applicable: README, QuickStart, CHANGELOG, and staged wiki Quick-Start now describe the local candidate count and component boundary. No version bump, package, live wiki update, or release is authorized.

## 9. Permanent procedure IDs affected

- IDs and evidence: Existing `TPM-TRACE-001`, `TPM-EVIDENCE-001`, `TPM-TRUTH-001`, `TPM-OWNER-001`, `TPM-OWNER-002`, `TPM-OWNER-003`, `TPM-UX-001`, and `TPM-UX-002`; see Issue #351 mapping in the control board. No new permanent procedure identifier is asserted.

## 10. Runtime smoke checklist

- Exact packaged behavior: Not performed; no live install or game launch.
- Required source/package identity: Exact named Main ZIP member and executable hashes in the corrected boundary/private proof. No whole archive hash.
- Evidence artifacts: Versioned private source-proof receipt; two native focused Pester receipts; current fragment/test/catalog/engine hashes.
- Owner/runtime authorization: No live runtime authorization or acceptance.

## 11. Stop condition

Stop after the exact catalog delta, focused tests on both requested PowerShell engines, input-bound receipts, bounded documents, and root review handoff. Do not widen to additional guide families, runtime, full suites, or release work.

## 12. Forbidden actions

No unrelated cleanup, broad rewrite, commit, push, package, release, certification, wiki update, ARCADE work, live runtime, or owner smoke unless separately authorized.

## 13. Commit/package authorization status

- Commit authorized: No
- Package authorized: No
- Release/certification authorized: No
