# PR #321 Current Slice: Universal Progress Scan Coverage

- Slice ID: TPM-PROGRESS-SCAN-COVERAGE-001
- Supplemental governance slice IDs: `TPM-OWNER-STATUS-GATE-001`.
- Supplemental behavior slice IDs: `TPM-LIBRARY-HEALTH-TRANSACTION-001`, `TPM-RESHADE-TEN-EFFECTS-001`, `TPM-S1-LEGACY-STATE-TRANSACTIONS-001`, `TPM-S1-SETUP-UPDATE-TRANSACTIONS-001`, `TPM-S1-UPDATE-VERSION-ORDERING-001`, and `TPM-POSTGRES-SETUP-ROLLBACK-001`.
- Slice name: RC8 universal progress coverage and truthful permanent-gate status semantics
- Included owner-report IDs: 3, 4, 5, and 29 for progress/source evidence; ID 3 for supplemental gate-status semantics; ID 21 for Library Health outcomes; IDs 1, 9, and 10 for ReShade; owner ID 34 for migration; owner row 81 for update-version ordering; and owner row 88 for PostgreSQL 8.3 rollback/setup safety.
- Issues: PR #321, issue #105, and issue #323 exact-package PostgreSQL owner-smoke evidence.
- Permanent procedures: TPM-PROGRESS-001, TPM-PROGRESS-002, TPM-PROGRESS-003, TPM-REPAIR-001, TPM-REPAIR-002, TPM-RESHADE-001, TPM-EVIDENCE-001, TPM-OWNER-001, TPM-OWNER-002, TPM-OWNER-003, TPM-TRACE-001, TPM-AUTH-001.
- PR #321 base ref: `0295415fb1b9d4bf6880945eb4807d4b2b27ec96`; local UVO-08 source/evidence worktree HEAD at gate start: `7d92a3f2379038b9c1ba3e3750766e8cf1a5ac42`; the existing PR branch was verified and local HEAD was its descendant.
- The prior PostgreSQL retry-authentication slice remains separately documented in `TPM-POSTGRES-RETRY-AUTH-001.md`; this pointer does not reassign its hunks.

## Explicit exclusions

- Owner IDs not included: all PR #321 IDs other than the progress rows, ID 3 gate-status semantics, ID 21 transaction outcomes, ReShade IDs 1, 9, and 10, migration ID 34, and update owner row 81 listed above.
- Features, modules, and runtime behavior excluded: no unrelated capability, network/retry/error-policy change, actual Arcade database/service/profile/credential/UAC/reset/recovery action, new release-package build or copy, merge, tag, publication, certification, or release. Recovery of the pre-existing untracked staging directory is documented under final source-quality evidence; it did not build, change, or validate the candidate ZIP. Commit/push is authorized only to PR #321's existing head after fresh required source gates and independent exact-diff review; owner smoke remains paused.

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

- ReShade gallery behavior: `TPM-RESHADE-TEN-EFFECTS-001`; owner IDs 1, 9, and 10; terminal chooser remains the sole profile selector. The gallery exposes a 0-100 TrackBar, coalesces rapid changes through a 16 ms timer, and applies keyboard updates immediately. A local Windows PowerShell 5.1 STA WinForms smoke displayed all twelve profiles, moved the comparison to 30, synchronized the terminal-selected `Vignette` profile while retaining Slider mode, rendered non-black pixels on both sides, and emitted no paint diagnostics. Focused ReShade Pester passed 44/44 under PS5.1 and PS7 with Pester 5.7.1; preview-state adapter coverage passed 1/1 under both engines. This is source-level UI proof, not packaged owner-runtime evidence.
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
- ReShade tests must prove ten exact pinned effect entries, twelve canonical profiles, terminal selection of the twelfth profile, preview synchronization, deterministic output, and slider boundaries.
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

## Runtime proof required

- Exact packaged behavior: not run or authorized in this task. Prior source slices remain subject to their separate package/runtime gates; this task does not build a package.
- Required source identity: source changes are pushed to PR #321's existing head ref only after fresh source gates and independent exact-diff review; CI must assert checked-out HEAD equals the PR head SHA. No package identity is requested or authorized.
- Evidence artifacts: focused behavior-test output, exact checked-out source SHA, fresh CI result if available under the standing gate, and the validated remediation report. Owner/runtime proof remains paused.
- Owner/runtime verification: not performed or authorized by this source lane; failed candidate package identity is incident evidence only.

- Stop condition: Do not claim release readiness. Stop on any failed source gate, missing hunk mapping, version-identity mismatch, CI checkout SHA mismatch, or any state/result that is not proven. Exact-head CI remains a source gate; package build and owner-runtime proof remain unauthorized and separate.

## Forbidden actions

No unrelated cleanup, broad rewrite, product feature work, actual Arcade database/service/profile/credential/UAC/reset/recovery action, owner smoke, package build, merge, tag, publication, certification, wiki update, or release. Scoped commit/push is authorized only after fresh source gates and independent review, and only to PR #321's existing head ref. Package preparation is not authorized.

## Hunk classification

- Progress source/tests/architecture/report/board: owner IDs 3, 4, 5, and 29 as individually identified in `TPM-PROGRESS-SCAN-COVERAGE-001.md`; PR #321; TPM-PROGRESS-001/002/003; TPM-TRACE-001.
- Permanent status-gate source/test/registry/docs/report/pointer and CI checkout/output-normalization hunks: owner ID 3 status semantics only; PR #321; `TPM-OWNER-STATUS-GATE-001`; TPM-OWNER-003; TPM-TRACE-001; TPM-AUTH-001.
- Library Health transaction source/tests/architecture/report/board: owner ID 21; PR #321; `TPM-LIBRARY-HEALTH-TRANSACTION-001`; TPM-REPAIR-001/002; TPM-EVIDENCE-001; TPM-OWNER-002/003; TPM-TRACE-001.
- ReShade catalog/selector/preview source/tests/docs: owner IDs 1, 9, and 10; PR #321; `TPM-RESHADE-TEN-EFFECTS-001`; TPM-RESHADE-001; TPM-EVIDENCE-001; TPM-OWNER-002/003; TPM-TRACE-001; TPM-AUTH-001.
- Migration startup gate source/tests/docs: owner ID 34; PR #321; `TPM-S1-LEGACY-STATE-TRANSACTIONS-001`; TPM-TRACE-001; TPM-EVIDENCE-001.
- Update version ordering source/tests/docs across both updater paths: owner row 81; issue #105; PR #321 review report `TPM-7D92-DELTA-20261003`; `TPM-S1-UPDATE-VERSION-ORDERING-001`; `TPM-TRACE-001`; `TPM-EVIDENCE-001`.
- PostgreSQL 8.3 rollback/setup compatibility and single-owner rollback source/tests/architecture/inventory/report hunks: owner row 88; PR #321; issue #323 exact-package smoke evidence; `TPM-POSTGRES-SETUP-ROLLBACK-001`; TPM-TRACE-001; TPM-OWNER-001. Failed package identity and live-state UNKNOWN remain explicit; no owner recovery action is authorized.

## Commit/package authorization status

- Commit/push authorized: Yes, after all source gates pass, solely to update PR #321's existing head ref and establish the exact source SHA for CI; no merge.
- Candidate package authorized: No; package build is explicitly excluded from this task.
- Release/certification authorized: No.

## Final PR #321 source-quality evidence -- 2026-10-04

- The UTC-stamped `Run-TpmQualityGate.ps1` wrapper passed against the source/test contents of commit `4f219a504018f98e816c716424bc5da4928a7cc8` before this report-only evidence amendment: 2026-10-04T00:22:22.8702405Z–2026-10-04T00:33:26.5048085Z; PowerShell 7.6.6 / Pester 5.7.1; exit 0.
- Main Pester 1311/1311 and SupportPackage 42/42 passed. ASCII/parse, configured PSScriptAnalyzer, `git diff --check`, and permanent procedure gate passed. Package release validation and owner-runtime proof remain separate and outstanding.
