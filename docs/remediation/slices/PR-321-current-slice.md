# PR #321 Current Slice: Universal Progress Scan Coverage

- Slice ID: TPM-PROGRESS-SCAN-COVERAGE-001
- Supplemental governance slice IDs: `TPM-OWNER-STATUS-GATE-001`.
- Supplemental behavior slice IDs: `TPM-LIBRARY-HEALTH-TRANSACTION-001`, `TPM-RESHADE-TEN-EFFECTS-001`, `TPM-RESHADE-TWENTY-EFFECTS-001` (cloud repair batch, uncommitted), `TPM-S1-LEGACY-STATE-TRANSACTIONS-001`, `TPM-S1-SETUP-UPDATE-TRANSACTIONS-001`, `TPM-S1-UPDATE-VERSION-ORDERING-001`, and `TPM-POSTGRES-SETUP-ROLLBACK-001`.
- Current #323 qualification supplements: `TPM-RC8-RESHADE-CONSOLE-BUFFER-001` and `TPM-RC8-CERT-WORKER-BOOTSTRAP-001` (2026-10-24).
- Slice name: RC8 universal progress coverage and truthful permanent-gate status semantics
- Included owner-report IDs: 3, 4, 5, and 29 for progress/source evidence; ID 3 for supplemental gate-status semantics; ID 21 for Library Health outcomes; IDs 1, 9, and 10 for ReShade; owner ID 34 for migration; owner row 81 for update-version ordering; and owner row 88 for PostgreSQL 8.3 rollback/setup safety.
- Current qualification owner mapping: PR #321 IDs 1/9 for finite-buffer/rendering-time geometry and newly assigned ID 36 for the PS5.1 IH worker dependency; these do not reassign progress ID 3 or the separate owner-report rows 81/88.
- Issues: PR #321, issue #105, and issue #323 exact-package PostgreSQL owner-smoke evidence.
- Permanent procedures: TPM-PROGRESS-001, TPM-PROGRESS-002, TPM-PROGRESS-003, TPM-REPAIR-001, TPM-REPAIR-002, TPM-RESHADE-001, TPM-EVIDENCE-001, TPM-OWNER-001, TPM-OWNER-002, TPM-OWNER-003, TPM-TRACE-001, TPM-AUTH-001.
- PR #321 base ref: `0295415fb1b9d4bf6880945eb4807d4b2b27ec96`; local UVO-08 source/evidence worktree HEAD at gate start: `7d92a3f2379038b9c1ba3e3750766e8cf1a5ac42`; the existing PR branch was verified and local HEAD was its descendant.
- The prior PostgreSQL retry-authentication slice remains separately documented in `TPM-POSTGRES-RETRY-AUTH-001.md`; this pointer does not reassign its hunks.

## Explicit exclusions

- Owner IDs not included: all PR #321 IDs other than the progress rows, ID 3 gate-status semantics, ID 21 transaction outcomes, ReShade IDs 1/9/10, migration ID 34, and current qualification ID 36; the separately mapped update owner row 81 and PostgreSQL owner row 88 retain their existing contracts.
- Features, modules, and runtime behavior excluded: no unrelated capability, network/retry/error-policy change, original-checkout or live test-PC database/service/profile/credential/UAC/reset/recovery action, merge, tag, publication, live wiki, certification or release. The earlier pre-existing untracked-staging recovery was source evidence only and did not build or validate a candidate ZIP; it grants no current commit/package authority.
- Current 2026-10-24 authority supersedes the historical commit/package wording above: no commit/push, release/tag/merge, live wiki or live TeknoParrot writes. The user requests a private local RC8 smoke package only after checklist section 4 gates; that request does not establish a clean pushed exact-SHA ref or coordinator READY. Disposable copied-fixture runtime QA and private short scratch are authorized, not owner acceptance or publication.

## Behavior contract

- Initial failure: earlier script-wide inventory claims were incomplete. Independent review found `Invoke-CrosshairSetup` materialized/sorted user-extensible `Crosshairs\*.png` before progress. The fix emits unknown-total per-file progress, stays active through sorting, closes before validation, and uses `-ErrorAction Stop`; focused behavior tests pass. ID 3 is `SOURCE FIXED; OWNER RUNTIME NEEDED` after the focused regression and finite census; the final PS7 aggregate source/permanent gates passed.
- Expected behavior: existing long-running paths emit compact TPM progress or retain an explicit bounded/waiting/no-progress disposition without changing ordering, results, mutations, or safety boundaries. The gate derives seven statuses and dispositions from the registry; parses the corrected-status column in the canonical section; requires exactly one status-bearing row for every unique ID in the control-board owner table; rejects unknown/malformed status rows and unresolved dispositions in source mode; and checks stale-package and owner-runtime evidence only in certification mode. Library Health returns `NO_OP` for an already-valid library without backup mutation, `PARTIAL_APPLIED` when verified fixes coexist with unresolved reports, and `SUCCEEDED` only when every report is fixed and verified. ReShade preserves five existing profiles, adds seven pinned effects as separately selectable profiles, and exposes ten total effects through a twelve-profile terminal chooser whose selection updates the deterministic approximation.
- Certification requires exactly one `Current candidate status: VALIDATED` field; missing, duplicate, malformed, `NOT BUILT`, and `STALE` values fail closed. Historical stale-package prose is ignored; owner-runtime-needed statuses remain blocking.
- Forbidden regressions: no invented percentage for unknown totals; no `Write-Progress`; no changed profile/game ordering, file contents, transaction/rollback semantics, prompt routing, or network behavior; no `SOURCE FIXED; OWNER RUNTIME NEEDED` status before complete census and focused source coverage; no unresolved status passing the source gate; no repair success while any affected profile remains unresolved.
- Design boundaries and deliberate exclusions: compact progress remains redirected-output-aware; bounded metadata, synchronous local work, opaque calls, stateful prompts, and external waits are not given fake progress. The status-gate correction changes no product behavior; Library Health outcome correction and the separately authorized ReShade selector/catalog change are limited to their contracts.

Supplemental source findings and exact mappings:

- Migration startup gate: `TPM-S1-LEGACY-STATE-TRANSACTIONS-001`; owner ID 34; PR #321; `TPM-TRACE-001` and `TPM-EVIDENCE-001`. Startup first requires a valid `TPM.TransactionResult.v1`; invalid or missing results, `ACTION_REQUIRED`, and `UNKNOWN` stop before new log/config paths are selected and without prompting.
- Update version ordering: `TPM-S1-UPDATE-VERSION-ORDERING-001`; owner row 81; PR #321 review finding P1-1; issue #105 is supporting context only, and its earlier final/RC equality assumption is superseded; `TPM-TRACE-001` and `TPM-EVIDENCE-001`. RC7 sorts before RC8, both sort before final 1.0. Before-fix here-string spoof and non-ASCII candidate cases were reproduced. The expanded UVO-08 implementation passed focused tests (main 6/6, core 7/7) and full relevant suites in both engines (main 1296/1296, SupportPackage 42/42, core 58/58, destructive-path 10/10). Static parser/ASCII/analyzer and canonical InjectionHunter checks passed. Fresh `Run-TpmQualityGate.ps1` and its permanent procedure gate passed at 2026-10-03T13:03:44Z; final post-status-sync focused contract tests and permanent procedure gate are recorded in the reconciliation report. Scoped commit/push remains authorized only after these final gates pass; no CI status checks, package build, owner runtime, merge, tag, release, wiki, or publication action is authorized.
- UVO-08 boundary: reject additional statically identified assignment/destructuring, attributed/cast or transparent-parenthesized, member/index-root, increment/decrement, foreach, root-script-parameter, and data-statement writes; preserve function-local parameters and unrelated index/member reads. Indirect/dynamic command and data-flow mutation is explicitly out of scope; this is not a sandbox. Historical integrated run `bg_87` passed main Pester 1293/1293 and SupportPackage 42/42 but failed the permanent gate on stale validation evidence (`artifact://1060`). Preserve those results; they are not current acceptance. No CI polling/termination, package, owner runtime, merge, tag, release, wiki, or publication action is authorized. Scoped commit/push to the existing PR #321 head is authorized only after all required gates pass; parent owns exact-head CI.
- CI evidence: `TPM-OWNER-STATUS-GATE-001`; owner ID 3 status semantics; PR #321; `TPM-OWNER-003`, `TPM-TRACE-001`, and `TPM-AUTH-001`. Child-gate output is normalized before matching; pull-request CI checks out the head repository/ref and verifies that checked-out HEAD equals the PR head SHA.

- ReShade gallery behavior: `TPM-RESHADE-TEN-EFFECTS-001`; owner IDs 1, 9, and 10; the gallery drop-down and terminal numbered chooser synchronize one canonical `SelectedProfileId`. Open sessions import the latest gallery selection after WinForms event pumping; a closed initialized/enabled session contributes its final selection once, so later terminal choices cannot be overwritten. Reopening the gallery starts a new synchronization session. The 0-100 TrackBar still coalesces drag changes through a 16 ms timer and applies keyboard changes immediately; profile changes preserve view/slider state. The RC8 Windows PowerShell 5.1 STA smoke displayed all twelve profiles backed by ten unique effects, closed after direct Vignette selection, then chose Sepia in the terminal and accepted it with `U`. Focused selector and caller-teardown regressions passed 8/8 under Windows PowerShell 5.1 and 8/8 under PowerShell 7.6.6. Independent closed-gallery review found no findings. Current full-suite and source-quality status is tracked in the reconciliation report; the inventory timing deviation remains open. No package or owner-runtime action is authorized.
- PostgreSQL owner row 88 packet: profile-impact JSON SHA-256 `42B9554AB7DFFFC9465B5F8FA9B0BC57D63943310D63B4C622F5E630E493C31D`; observed time-of-day `18:46:04.1230563` only; baseline SHA-256 `02DEA729E19CB9D64CDED338B2FC72CDE28AF78CC17209B28F9BF0E068518322`. GameProfiles remained 969 files / 7,574,923 bytes and UserProfiles remained 8,698 files / 297,810,587 bytes, with zero profile-file adds/removes/changes; raw XML was not emitted. `DatabaseCatalogVerified=false`; database state remains UNKNOWN. These deltas do not establish that database state is unchanged. A newly reproduced restore collision showed `createdb.exe` failure after absent pre-state could cause TPM to drop an unowned database; fixed with explicit `CreateOwnedForRollback` evidence and ownership-guarded rollback. The before-fix regression failed with `ROLLED_BACK_VERIFIED`; absent-prestate and existing-prestate collision regressions pass under PS5.1 and PS7 with Pester 5.7.1, preserving the appeared database and returning `ACTION_REQUIRED`/`UNKNOWN`. A forced final receipt-refresh failure now clears `ReceiptPath`, preserves the root/stale file only as residue, reports `ReceiptError`, and returns validated `CLEANUP_RESIDUE` with cleanup incomplete; the regression passes under both engines. Exact full-suite, static, procedure-gate, and review evidence is recorded in the appended reconciliation report; no unchanged-database claim is supported.

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
- Both source identity parsers must prove full-source extraction, here-string/comment/string-decoy handling, single-quoted literal acceptance, and fail-closed duplicate, scoped, nested, compound, nonliteral, malformed-source, and valid-UTF-8 non-ASCII candidate cases under Windows PowerShell 5.1 and PowerShell 7.
- ReShade selection tests must prove ten exact pinned effect entries, twelve canonical profiles, direct gallery selection and terminal selection of the twelfth profile, latest-selection acceptance after input pumping, selector synchronization, malformed-item failure, initialization/closure guards, deterministic output, view/slider independence, and slider boundaries/keyboard behavior.
- ReShade repair-pass tests (uncommitted, not yet run under PowerShell) must also prove: the selector guard is restored right after the programmatic assignment and when it throws; a queued preview choice is not dropped and is the profile `U` accepts, with view mode and slider unchanged; a reopened preview is closed once by the chooser on exception, repeated reopen, acceptance, and cancel without double disposal; preview-refresh failure and an unavailable source DLL fail safely.
- ReShade preset conformance must cover `StartupPresetPath`/`PresetPath` precedence, canonical `Techniques` plus `TechniqueSorting`, empty Original lists, and rejection of a sorting list that diverges from the selected profile.
- ReShade include-deployment tests must cover the complete profile closure, shared-include deduplication, conflicting same-path identities rejected before target mutation, and exact rollback/ownership state.
- PostgreSQL restore collision and receipt-persistence tests must prove that failed `createdb.exe` does not authorize dropping a database observed after either preflight boundary, and that a failed final receipt refresh clears the advertised path, preserves evidence, and returns valid `CLEANUP_RESIDUE`.

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
- `docs/AUTO_UPDATE.md`
- `TeknoParrot-Manager-README.txt`
- `QUICKSTART.md`
- `SECURITY.md`
- `RELEASE-SAFETY-CHECKLIST.md`
- `docs/ENGINEERING-WORKFLOW.md`
- `TeknoParrot-Manager-QuickStart.txt`
- `docs/wiki-updates/Home.md`
- `docs/wiki-updates/Quick-Start.md`
- `docs/wiki-updates/Changelog.md`
- `docs/wiki-updates/ReShade.md` (insert-only staging patch; no live wiki update)
- `docs/TPM-CERTIFICATION-SUITE.md`
- `.github/workflows/ci.yml`
- `tools/TpmAutoUpdate.Core.psm1`
- `tools/Invoke-TpmAutoUpdate.ps1`
- `Tests/TpmAutoUpdate.Core.Tests.ps1`
- `Tests/TpmAutoUpdate.DestructivePath.Tests.ps1`
- `docs/remediation/slices/TPM-S1-LEGACY-STATE-TRANSACTIONS-001.md`
- `docs/remediation/slices/TPM-S1-UPDATE-VERSION-ORDERING-001.md`
- `docs/remediation/slices/TPM-POSTGRES-SETUP-ROLLBACK-001.md`
- `docs/RC8-REMEDIATION-INVENTORY.md`
- `TeknoParrot-Manager-CHANGELOG.txt`
- `scripts/InjectionHunterDispositions.psd1`
- `scripts/TPMCertification.ProductionFacts.psm1` (owner 36 bounded IH worker bootstrap only)
- `Tests/ReShade.FiniteBuffer.Tests.ps1`
- `Tests/TPMCertification.WorkerBootstrap.Tests.ps1`
- `docs/remediation/slices/TPM-RC8-RESHADE-CONSOLE-BUFFER-001.md`
- `docs/remediation/slices/TPM-RC8-CERT-WORKER-BOOTSTRAP-001.md`
- `docs/CERTIFICATION-WORKER-BOOTSTRAP-INVENTORY.md`
- `LESSONS_LEARNED.md` (verified qualification-boundary lesson only)
- `docs/remediation/slices/TPM-OWNER-STATUS-GATE-001.md` (owner 3 fixture-state inventory and precondition correction only)

## Runtime proof required

- Current #323 runtime scope: visible native PS5.1/PS7 diagnostics and newly verified disposable copied fixtures. Existing real-game/owner acceptance remains separate; no live installation or database/service action is authorized.
- Required source identity: preserve the handed-off dirty candidate, record exact revised full-source hashes and reject drift. A private smoke ZIP remains held until the required clean exact pushed-SHA handoff and coordinator/human section 4 gates are satisfied; do not sweep unrelated dirty changes into a commit to manufacture that state.
- Evidence artifacts: immutable original failures; exact command/model/engine/module identities, focused red/green receipts, independent review, final frozen main/full-folder/static/permanent results, package identity only if separately eligible, and a current validated report. Private reports may be refreshed outside the frozen source tree.
- Owner/runtime verification: source and fixture proofs do not promote any owner to FIXED + TESTED. No publication or live wiki change is authorized.

- Stop condition: do not promote qualification on a failed source gate, missing hunk mapping, version-identity mismatch, source drift or an unproven result; diagnose within the mapped slice. Exact pushed-ref/CI and section 4 package authority remain separate handoff gates. Local source/test or disposable-fixture evidence never supplies owner acceptance or release readiness.

## Forbidden actions

No unrelated cleanup, broad rewrite, new product capability, original-checkout or live TeknoParrot/database/service/credential writes, commit/push, merge/tag, publication, owner acceptance, certification, live wiki update or release. Private fixture QA is authorized. Private RC8 packaging is requested only after the section 4 clean exact-SHA/READY/human gates; do not infer those gates from source tests or sweep unrelated dirty changes into a commit.

## Hunk classification

- Progress source/tests/architecture/report/board: owner IDs 3, 4, 5, and 29 as individually identified in `TPM-PROGRESS-SCAN-COVERAGE-001.md`; PR #321; TPM-PROGRESS-001/002/003; TPM-TRACE-001.
- Permanent status-gate source/test/registry/docs/report/pointer and CI checkout/output-normalization hunks: owner ID 3 status semantics only; PR #321; `TPM-OWNER-STATUS-GATE-001`; TPM-OWNER-003; TPM-TRACE-001; TPM-AUTH-001.
- Library Health transaction source/tests/architecture/report/board: owner ID 21; PR #321; `TPM-LIBRARY-HEALTH-TRANSACTION-001`; TPM-REPAIR-001/002; TPM-EVIDENCE-001; TPM-OWNER-002/003; TPM-TRACE-001.
- ReShade catalog/selector/preview source/tests/docs: owner IDs 1, 9, and 10; PR #321; `TPM-RESHADE-TEN-EFFECTS-001`; TPM-RESHADE-001; TPM-EVIDENCE-001; TPM-OWNER-002/003; TPM-TRACE-001; TPM-AUTH-001.
- Migration startup gate source/tests/docs: owner ID 34; PR #321; `TPM-S1-LEGACY-STATE-TRANSACTIONS-001`; TPM-TRACE-001; TPM-EVIDENCE-001.
- Update version ordering source/tests/docs across both updater paths: owner row 81; issue #105; PR #321 review report `TPM-7D92-DELTA-20261003`; `TPM-S1-UPDATE-VERSION-ORDERING-001`; `TPM-TRACE-001`; `TPM-EVIDENCE-001`.
- PostgreSQL 8.3 rollback/setup compatibility and single-owner rollback source/tests/architecture/inventory/report hunks: owner row 88; PR #321; issue #323 exact-package smoke evidence; `TPM-POSTGRES-SETUP-ROLLBACK-001`; TPM-TRACE-001; TPM-OWNER-001. Failed package identity and live-state UNKNOWN remain explicit; no owner recovery action is authorized.
- Current qualification console/layout source, tests and documentation: owners 1/9; #323; TPM-RC8-RESHADE-CONSOLE-BUFFER-001; TPM-TRACE-001, TPM-EVIDENCE-001, TPM-AUTH-001.
- Current qualification IH worker, real child-boundary regression and documentation: owner 36; #323; TPM-RC8-CERT-WORKER-BOOTSTRAP-001; TPM-TRACE-001, TPM-EVIDENCE-001, TPM-AUTH-001.
- Current qualification status-fixture preconditions: owner ID 3, status semantics only; #323 / PR #321; TPM-OWNER-STATUS-GATE-001 section 16; TPM-OWNER-003, TPM-TRACE-001, TPM-EVIDENCE-001, TPM-AUTH-001. No production gate or assertion change.

## Commit/package authorization status

- Commit/push authorized: No under this current qualification overlay; no permission to sweep unrelated dirty changes into a handoff commit.
- Candidate package: private RC8 smoke candidate requested conditionally after checklist section 4 gates; currently held on clean exact pushed-SHA/READY/human workflow prerequisites, not categorically rejected as a task.
- Release/certification authorized: No.

## Final PR #321 source-quality evidence -- 2026-10-04

- The UTC-stamped `Run-TpmQualityGate.ps1` wrapper passed against the source/test contents of commit `4f219a504018f98e816c716424bc5da4928a7cc8` before this report-only evidence amendment: 2026-10-04T00:22:22.8702405Z–2026-10-04T00:33:26.5048085Z; PowerShell 7.6.6 / Pester 5.7.1; exit 0.
- Main Pester 1311/1311 and SupportPackage 42/42 passed. ASCII/parse, configured PSScriptAnalyzer, `git diff --check`, and permanent procedure gate passed. Package release validation and owner-runtime proof remain separate and outstanding.

## 2026-10-24 qualification overlay

The two current supplemental contracts own only the finite-buffer writer,
initial-draw layout geometry, related input/geometry fixture corrections and
new behavioral regressions (IDs 1/9), and the native PS5.1 IH bounded-worker
inbox Utility bootstrap (ID 36). Both contracts, board/report assignments and
applicable inventories preceded the source edits. The new worker boundary
regression was authored late; its exact pre-edit-backup red/green proof and
sequencing deviation remain disclosed in that contract, not retroactively
described as test-before-edit compliance.
The candidate remains v1.0 RC8, already the unpublished release-cycle bump
from published RC7; these repairs are recorded in that candidate entry, not
a new published version or authorization to change release identity.


The first complete revised main run exposed two qualification preconditions.
Private stdin-only EOF restores the original visible qualification topology;
it is not a product patch. The remaining owner 3 status test must explicitly
seed its STALE fixture instead of assuming the current real report has that
state. The existing owner-status contract's section 16 owns this additional
test/documentation delta and its fixture inventories, before the test edit.
Preserve the failed first freeze, all assertions and NOT BUILT real provenance.
No source write occurs during a qualification run; a new full freeze and
reviewed final gates are required after this correction.

The owner 3 fixture preconditions now pass in EOFComplete on both native
engines, Pester 5.7.1: five selected cases passed, none failed/skipped, native
exits 0; all 642 working-source files matched. Remaining tests were excluded
intentionally, not counted as aggregate coverage. Production Main/worker
bytes are unchanged by this fixture correction. Record final complete-source
qualification externally after the new freeze, retaining the failed first
freeze and every intermediate result.
