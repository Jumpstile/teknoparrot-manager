# PR #321 Current Slice: Universal Progress Scan Coverage

- Slice ID: TPM-PROGRESS-SCAN-COVERAGE-001
- Supplemental governance slice ID: TPM-OWNER-STATUS-GATE-001
- Supplemental behavior slice ID: `TPM-LIBRARY-HEALTH-TRANSACTION-001`
- Supplemental ReShade behavior slice ID: `TPM-RESHADE-TEN-EFFECTS-001`
- Slice name: RC8 universal progress coverage and truthful permanent-gate status semantics
- Included owner-report IDs: 3, 4, 5, and 29 for progress/source evidence; ID 3 for the supplemental gate-status correction; ID 21 for Library Health transaction outcomes; IDs 1, 9, and 10 for the authorized ReShade ten-effect selection behavior.
- Issue: PR #321.
- Permanent procedures: TPM-PROGRESS-001, TPM-PROGRESS-002, TPM-PROGRESS-003, TPM-REPAIR-001, TPM-REPAIR-002, TPM-RESHADE-001, TPM-EVIDENCE-001, TPM-OWNER-002, TPM-OWNER-003, TPM-TRACE-001, TPM-AUTH-001.
- Base HEAD: `193796a08d17f87f823d047646a3e848b85977fc`; working-tree changes remain uncommitted.
- The prior PostgreSQL retry-authentication slice remains separately documented in `TPM-POSTGRES-RETRY-AUTH-001.md`; this pointer does not reassign its hunks.

## Explicit exclusions

- Owner IDs not included: all PR #321 IDs other than the progress rows, ID 3 gate-status semantics, ID 21 transaction outcomes, and ReShade IDs 1, 9, and 10 listed above.
- Features, modules, and runtime behavior excluded: no capability beyond the separately authorized ReShade ten-effect slice, no network/retry/error-policy change, no runtime mutation, merge, tag, publication, certification, or release. The user conditionally authorizes exact-SHA candidate preparation after every source gate passes; owner smoke remains for Eli after handoff, with Eli's final approval required.

## Behavior contract

- Initial failure: earlier script-wide inventory claims were incomplete. Independent review found `Invoke-CrosshairSetup` materialized/sorted user-extensible `Crosshairs\*.png` before progress. The fix emits unknown-total per-file progress, stays active through sorting, closes before validation, and uses `-ErrorAction Stop`; focused behavior tests pass. ID 3 is `SOURCE FIXED; OWNER RUNTIME NEEDED` after the focused regression and finite census; the final PS7 aggregate source/permanent gates passed.
- Expected behavior: existing long-running paths emit compact TPM progress or retain an explicit bounded/waiting/no-progress disposition without changing ordering, results, mutations, or safety boundaries. The gate derives seven statuses and dispositions from the registry; parses the corrected-status column in the canonical section; requires exactly one status-bearing row for every unique ID in the control-board owner table; rejects unknown/malformed status rows and unresolved dispositions in source mode; and checks stale-package and owner-runtime evidence only in certification mode. Library Health returns `NO_OP` for an already-valid library without backup mutation, `PARTIAL_APPLIED` when verified fixes coexist with unresolved reports, and `SUCCEEDED` only when every report is fixed and verified. ReShade preserves five existing profiles, adds seven pinned effects as separately selectable profiles, and exposes ten total effects through a twelve-profile terminal chooser whose selection updates the deterministic approximation.
- Certification requires exactly one `Current candidate status: VALIDATED` field; missing, duplicate, malformed, `NOT BUILT`, and `STALE` values fail closed. Historical stale-package prose is ignored; owner-runtime-needed statuses remain blocking.
- Forbidden regressions: no invented percentage for unknown totals; no `Write-Progress`; no changed profile/game ordering, file contents, transaction/rollback semantics, prompt routing, or network behavior; no `SOURCE FIXED; OWNER RUNTIME NEEDED` status before complete census and focused source coverage; no unresolved status passing the source gate; no repair success while any affected profile remains unresolved.
- Design boundaries and deliberate exclusions: compact progress remains redirected-output-aware; bounded metadata, synchronous local work, opaque calls, stateful prompts, and external waits are not given fake progress. The status-gate correction changes no product behavior; Library Health outcome correction and the separately authorized ReShade selector/catalog change are limited to their contracts.

## Prompt inventory and classification

- No prompt choices or routing change in this slice. Existing exact-token, secure-input, path-safety, renderer-aware, and stateful picker boundaries remain unchanged.
- The permanent-gate status classifier validates report vocabulary only; it does not reinterpret user prompts or owner authorization.

## Source inventory

- Progress scope and exact functions are listed in `TPM-PROGRESS-SCAN-COVERAGE-001.md`; that contract covers AutoSync classification, catalog scans, FFB/native phases, verified backup/restore, transactions, migration, ReShade, support ZIP lifecycle, PostgreSQL scans, CursorHide/Crosshair, HyperSpin exports, registration discovery, and bounded metadata dispositions.
- Supplemental status-gate scope is listed in `TPM-OWNER-STATUS-GATE-001.md`; it covers `Get-TpmOwnerStatusDisposition` and the permanent gate's owner-status loop.
- Library Health transaction accounting is covered by `TPM-LIBRARY-HEALTH-TRANSACTION-001.md`; it preserves affected-game scope and backup-before-write while making transaction outcomes match the fixed, failed, skipped, and no-change evidence.
- ID 3 is `SOURCE FIXED; OWNER RUNTIME NEEDED` after the discovery/sort fix, focused coverage, and finite census. The final full source/permanent gate passed; candidate-source preparation is eligible, while owner-runtime proof remains separate and mandatory. The permanent gate continues to reject unresolved canonical statuses and explicit `NOT FIXED` paths.

## Required focused tests

- Crosshair profile-planning and HyperSpin export-scan behavior tests must observe compact known-total rows while verifying actual fixture outputs and unchanged targets.
- The owner-status test must cover all seven registry statuses and an unknown status; every unresolved status remains blocking.
- The permanent-gate tests must cover canonical-vs-historical precedence, exact control-board/canonical ID equality, missing/extra IDs, blank corrected status, and source-vs-certification stale-package handling.
- Run the full main and SupportPackage Pester suites under Pester 5.7.1; run the main suite under PowerShell 7 and Windows PowerShell 5.1.
- ReShade tests must prove ten exact pinned effect entries, twelve canonical profiles, terminal selection of the twelfth profile, preview synchronization, deterministic output, and slider boundaries.
- ReShade preset conformance must cover `StartupPresetPath`/`PresetPath` precedence, canonical `Techniques` plus `TechniqueSorting`, empty Original lists, and rejection of a sorting list that diverges from the selected profile.
- ReShade include-deployment tests must cover the complete profile closure, shared-include deduplication, conflicting same-path identities rejected before target mutation, and exact rollback/ownership state.

## Files allowed to change

- `TeknoParrot-Manager.ps1`
- `Tests/TeknoParrot-Manager.Tests.ps1`
- `Tests/SupportPackage.Tests.ps1`
- `ARCHITECTURE.md`
- `scripts/Run-TpmQualityGate.ps1`
- `scripts/Test-TpmPermanentProcedures.ps1`
- `quality/permanent-procedures.json`
- `docs/governance/tpm-development-operating-model.md`
- `docs/governance/permanent-procedures.md`
- `docs/templates/remediation-gate-report.md`
- `docs/remediation/PR-321-current-slice.md`
- `docs/remediation/PR-321-control-board.md`
- `docs/remediation/PR-321-reconciliation.md`
- `docs/remediation/slices/TPM-PROGRESS-SCAN-COVERAGE-001.md`
- `docs/remediation/slices/TPM-LIBRARY-HEALTH-TRANSACTION-001.md`
- `docs/remediation/slices/TPM-OWNER-STATUS-GATE-001.md`
- `docs/remediation/slices/TPM-RESHADE-TEN-EFFECTS-001.md`
- `docs/RESHADE-PROFILE-SELECTION-SPECIFICATION-INVENTORY.md`
- `docs/RESHADE-PROFILE-SELECTION-INVARIANT-INVENTORY.md`
- `docs/RESHADE-DGVOODOO2-AUTODOWNLOAD-SPECIFICATION-INVENTORY.md`
- `docs/RESHADE-DGVOODOO2-AUTODOWNLOAD-INVARIANT-INVENTORY.md`
- `LICENSE`
- `README.md`
- `TeknoParrot-Manager-README.txt`
- `TeknoParrot-Manager-CHANGELOG.txt`

## Runtime proof required

- Exact packaged behavior: after a fresh candidate is built from the exact reviewed source SHA and authorized, exercise representative long scans, AutoSync, profile/transaction paths, Crosshair setup, HyperSpin export, and support ZIP creation; observe bounded progress and unchanged operation results.
- Required source/package identity: pushed source SHA and package SHA must match exactly; the current candidate ZIP is stale and is not evidence.
- Evidence artifacts: operator-visible progress output, operation results, exact source/package identities, and owner-runtime record.
- Owner/runtime verification: not performed by this source-gate lane; hand the exact candidate identity to Eli/ARCADE for owner smoke after validation. Eli retains final approval.

## Stop condition
Do not start candidate preparation while any source gate fails or evidence is stale. The Crosshairs fix covers discovery through sorting, fails visibly on enumeration errors, and preserves selection/output behavior. ID 3 is `SOURCE FIXED; OWNER RUNTIME NEEDED` after focused source coverage and finite census closure; the final full source/permanent gate passed. Exact-SHA candidate-source preparation is eligible. Package build additionally requires exact pushed-SHA identity and the release checklist's documentation/READY/authorization gates. Owner-runtime completion remains held until Eli's smoke and final approval.

## Forbidden actions

No unrelated cleanup, broad rewrite, product feature work, runtime mutation, owner smoke by this lane, merge, tag, publication, certification, wiki update, or ARCADE execution. Commit/push and candidate-package preparation are allowed only after all source gates pass and the exact-source identity gate is satisfied.

## Hunk classification

- Progress source/tests/architecture/report/board: owner IDs 3, 4, 5, and 29 as individually identified in `TPM-PROGRESS-SCAN-COVERAGE-001.md`; PR #321; TPM-PROGRESS-001/002/003; TPM-TRACE-001.
- Permanent status-gate source/test/registry/docs/report/pointer: owner ID 3 status semantics only; PR #321; `TPM-OWNER-STATUS-GATE-001`; TPM-OWNER-003; TPM-TRACE-001; TPM-AUTH-001.
- Library Health transaction source/tests/architecture/report/board: owner ID 21; PR #321; `TPM-LIBRARY-HEALTH-TRANSACTION-001`; TPM-REPAIR-001/002; TPM-EVIDENCE-001; TPM-OWNER-002/003; TPM-TRACE-001.
- ReShade catalog/selector/preview source/tests/docs: owner IDs 1, 9, and 10; PR #321; `TPM-RESHADE-TEN-EFFECTS-001`; TPM-RESHADE-001; TPM-EVIDENCE-001; TPM-OWNER-002/003; TPM-TRACE-001; TPM-AUTH-001.
- Earlier PostgreSQL retry-authentication hunks remain mapped to `TPM-POSTGRES-RETRY-AUTH-001.md` and are not reassigned by this current-slice pointer.

## Commit/package authorization status

- Commit/push authorized: Yes, conditionally after all source gates pass, solely to establish the exact candidate source SHA; no merge.
- Candidate package authorized: Yes, conditionally after all source gates pass, the exact pushed SHA is available, and the release checklist's exact-SHA READY/authorization gate is satisfied.
- Release/certification authorized: No.
