# Register-only game-file discovery progress follow-up

## 1. Slice name

- Name: Visible unknown-total progress during Register-only game-file discovery
- Contract ID: TPM-REGISTER-DISCOVERY-PROGRESS-FOLLOWUP-001
- Issue/PR: PR #321; owner report ID 3

## 2. Owner report IDs included

- ID 3: Arcade Register-only discovery remained silent while the recursive file walk was CPU-active. The live attempt lasted 322.72 seconds without per-file discovery output. It was not proven hung.
- Exact source under investigation: bee0e2bdbc24d9fb481f164ddb63065820dd4fb1.

## 3. Explicit exclusions

- Owner IDs not included: all IDs other than 3.
- Excluded: live library rescans, profile or database writes, credentials, service/security changes, GUI installation changes, network acquisition, package/build/release, commit, push, merge, tag, certification, or publication.

## 4. Behavior contract

- Current failure: Get-GameFiles completes recursive enumeration before Register-Games reaches its candidate loop and its later Write-Progress calls. The discovery interval has no visible progress.
- Expected behavior: Register-Games reports a truthful start, periodic item-count progress while entries are yielded, and a completion count. The total remains explicitly unknown; no percentage or path/item identifiers are displayed.
- Forbidden regressions: do not change Get-ChildItem arguments, error action, provider/reparse traversal, candidate predicate, candidate membership, enumeration order, cancellation/error propagation, profile matching, or dry-run/write behavior. Progress must not add values to the function output pipeline.
- Design boundary: add an optional callback to Get-GameFiles and use it only in Register-Games. No traversal redesign or full live-folder repetition.

## 5. Source/function ownership

- Files: TeknoParrot-Manager.ps1; Tests/RegisterOnlyDiscoveryProgress.Tests.ps1.
- Functions: Get-GameFiles; Register-Games.
- Owning subsystem: Progress.Core / PR #321 registration discovery.

## 6. Tests required before implementation

- Baseline: bounded delayed synthetic enumeration demonstrates no discovery output until enumeration completes.
- Characterization: capture baseline candidate paths/order and original Get-ChildItem parameters and error action.

## 7. Tests required after implementation

- Focused behavior tests: exact candidate set/order with callback, unknown-total progress output, no extra pipeline output, preserved Get-ChildItem parameters, and cancellation/error propagation. The Pester fixture uses a catchable OperationCanceledException; a native PipelineStoppedException is tested separately because it terminates the Pester host.
- Runtime fixture: observe progress before a bounded slow synthetic enumeration completes; test a simulated PipelineStoppedException and the interrupted status path.
- Engines: direct Pester on Windows PowerShell 5.1 and PowerShell 7 where available. Pester 5.8.0 differs from the repository-pinned 5.7.1.
- Gates: record parser, ASCII, focused Pester and timing/memory evidence. Do not invoke certification children that override execution policy.

## 8. Documentation/report updates required

- Control board/report: the exact bee0e2b base does not contain docs/remediation/PR-321-control-board.md or PR-321-reconciliation.md. The user's separate WIP contains those files and the broader TPM-PROGRESS-SCAN-COVERAGE-001 contract; do not copy over or edit that WIP. Add the exact follow-up evidence there only in a later authorized reconciliation.
- Hunk classification: this contract / PR #321 / owner ID 3 / TPM-PROGRESS-001 / TPM-PROGRESS-002 / TPM-PROGRESS-003 / TPM-TRACE-001.
- Changelog: no release version or user-documentation update in this uncommitted local follow-up.

## 9. Permanent procedure IDs affected

- TPM-PROGRESS-001: unknown-total progress must remain truthful and visible.
- TPM-PROGRESS-002: registration discovery is included in the scan inventory.
- TPM-PROGRESS-003: the source must not introduce a PowerShell progress panel.
- TPM-TRACE-001: map each source hunk to this contract, PR #321, and owner ID 3.

## 10. Runtime smoke checklist

- Exact source: branch repair/registration-scan-progress-20261020 based on bee0e2bdbc24d9fb481f164ddb63065820dd4fb1; record the local diff digest with test results.
- Fixture: synthetic delayed file stream only. Do not repeat the scan on the live game library in this slice.
- Evidence: retain raw test output, process timing/memory, fixture manifest, and visible mid-run output.
- Live runtime mutation: none authorized by this contract.

## 11. Stop condition

Stop after the focused tests on both available engines, cancellation and visible-progress evidence, timing/memory comparison, and exact-source record are complete. Live owner runtime proof remains separate.

## 12. Forbidden actions

No unrelated cleanup, broad rewrite, live library rescan, profile/database mutation, commit, push, package, merge, release, certification, wiki update, or runtime security change.

## 13. Commit/package authorization status

- Commit authorized: No.
- Package authorized: No.
- Release/certification authorized: No.

## 14. Repository-sweep differential RCA (2026-10-21; not a green certification)

- Candidate source: branch repair/registration-scan-progress-20261020, base bee0e2bdbc24d9fb481f164ddb63065820dd4fb1, TeknoParrot-Manager.ps1 SHA256 5BAF421FB91ADB876132E0B9538328623DC213150097A33DCCAD32C31D92FCD8. Clean-base manager SHA256: 703E1005E22983AD2175E8F2A5E6B47BC1E50BE3E2B9C9F0CD8FA04D11682309. Candidate test inventory: 36 files; current path/hash manifest SHA256 41966BE15FF148D472850A2848B2354D427A6273772E5A2ABBE68891C8A1AA68. The nine files selected for the failure differential are byte-identical in candidate and base.
- Full Tests/*.Tests.ps1 sweeps used Pester 5.7.1. PS7.6.5: 1,892 passed, 9 failed, 19 skipped, 7 restricted cases filtered (1,086.7s). Windows PowerShell 5.1.26100.9711: 1,883 passed, 18 failed, 19 skipped, 7 filtered (1,507.1s). Every candidate PS7 failure reproduced in the 18-case clean-base differential; all 18 candidate PS5.1 failures were reproduced on clean base across the preserved initial partial log (13 cases) and a targeted remainder run (5 cases). The initial PS5.1 run ended without a summary; the subsequent run did not repeat those first 13.
- The publisher, production-cycle, production-evidence, and production-facts modules are byte-identical in candidate and base (SHA256 respectively: 5F1833058A8BD378726B2E51CC4720E088EB2AFF1C5B1FF54E0842CCA024A1AB, 8FA916DE2EC60A0017EEBB512E162069F5F5CCF49330CE28E94DCE001946B8C3, C3C563E564BD6B1451FED28D038CCB9AF0ADA40A9439EE7811BACEFF116D0634, B5B359E8E54A8CE99722CA1104DD865843B4A44F789FF15E6DAFD716B04EE410). No production module was changed.
- Root cause for the PS5.1 publisher/cleanup assertions: the full sweep’s TPM-Certification-Eligibility.json path was 263 characters. The recorded .ctor failure was “Could not find a part of the path”. A bounded PS5.1 run on base with a short task-owned temp root passed both the real publisher preflight and cleanup-failure cases (2 passed); the cleanup diagnostic assertion failed only when the earlier path-length publisher error occupied PackageValidationDiagnostics[0]. Minimal test-only fix proposal: keep the fixture’s generated artifact paths below the Windows PowerShell 5.1 path limit and assert the cleanup failure code is present, rather than requiring it to be the first diagnostic.
- Root cause for NOT CERTIFIED in the PS5.1 composition case: a diagnostic copy of that test, run against the same clean-base source, showed the only failing fact was Artifacts. Its preflight returned PublisherAvailable=false with PROMOTION_FAILED on a 274-character nested TPM-Certification-Eligibility.json path. Eligibility therefore contained PUBLISHER_UNAVAILABLE and PACKAGE_VALIDATION_FAILED, scored 7/8 (8,750 basis points against a 10,000 threshold), and projected NOT CERTIFIED/exit 1. The other displayed facts passed. The later fixture commit itself succeeded. This establishes a deep-fixture path-length failure on this PS5.1 runner; it does not establish behavior on the installed Arcade runtime or support for arbitrarily long production paths. No production fix was applied.
- The real PSScriptAnalyzer self-scan is a separate unresolved gate: Test-TPMProductionPSScriptAnalyzerV1 defaults to a 60-second per-file worker timeout and the clean base and candidate both reported PSSCRIPTANALYZER_JOB_TIMED_OUT/Executed=false. The logs do not identify the timed-out file, so this is a reproduced job-timeout limitation, not proof of analyzer findings or a proven product defect. The update -WhatIf failure separately hit DNS resolution for api.github.com; junction fixtures hit access restrictions; child-output assertions captured the FileSystem-provider startup warning.
- The 7 filtered cases remain restricted child-launch tests: TeknoParrot-Manager.Tests.ps1 lines 2337, 2382, 2424, 2498 and TPMCertification.WrapperExit.Tests.ps1 lines 125, 152, 163 (each contains a real child launch with -ExecutionPolicy Bypass). The 19 Pester skips were environment-gated: 16 junction/reparse cases, 2 symbolic-link creation cases, and 1 screen-capture case (GDI+ returned ERROR_INVALID_HANDLE). These are separate from the 7 filtered cases.
- Evidence is preserved in the task workspace: TPM-Repository-Sweep-PS7-20261021T004342Z.json, TPM-Repository-Sweep-PS51-20261021T010226Z.json, TPM-Targeted-Baseline-PS7-20261021T013045Z.json, TPM-Targeted-Baseline-PS51-20261021T014235Z.json, TPM-Targeted-Baseline-PS51-20261021T015305Z.json (short-root comparison), and TPM-Composition-RCA-PS51-20261021T015546Z.txt. The first clean-base PS5.1 differential is a partial transcript only at TPM-Targeted-Baseline-PS51-20261021T013623Z.txt. The diagnostic test copy and its runner are task-workspace files, not repository test changes.
- This is not a full-green gate or live smoke result. No candidate/base production or test source changed; no commit, push, installation, deployment, merge, release, or live profile/database mutation occurred. Live owner proof still needs a screenshot-capable view bound to Arcade’s TPM window; the connected Remote Desktop Commander path exposed no screenshot/window-control action, and CUA had no bound app.
## 15. PSScriptAnalyzer timed-file isolation (2026-10-21; clean-base diagnostic)

- The earlier sweep logs reported `PSSCRIPTANALYZER_JOB_TIMED_OUT` without a file name. A task-owned wrapper invoked the unchanged production `Invoke-TPMBoundedScriptBlockV1` and `Invoke-ScriptAnalyzer -Path $Path -Severity Error,Warning -Settings $Settings`, using the repository's existing 60-second per-file timeout and fixed ordered inventory. No threshold or timeout override was used.
- Clean base: `E:\REPOS\tpm-owner-smoke-bee0e2-20261020`, manager SHA256 before and after `703E1005E22983AD2175E8F2A5E6B47BC1E50BE3E2B9C9F0CD8FA04D11682309`; analyzer settings SHA256 `999955106CDCD9A19F7331A7BD8AE42A63F11DE8CB713C332917FA9189F985B6`; Windows PowerShell Desktop 5.1.26100.9711.
- The first inventory target, `TeknoParrot-Manager.ps1`, was the first timed-out worker: `TimedOut=true`, `TerminationConfirmed=true`, measured wrapper elapsed time 76.705 seconds. The wrapper stopped after that result; the other 18 targets were not run. Thus the job-gate timeout is localized to the manager file on this runner. This does not indicate analyzer findings, does not establish a product defect, and is distinct from the direct PSScriptAnalyzer zero-findings check.
- Retained task-workspace evidence: `TPM-PSSA-OrderedDiagnostic.ps1` SHA256 `343EEF7276BFC46B73ED37AB95CDDCA7546D84C938136DA13D638748C69D3B93`; `TPM-PSSA-Ordered-PS51-20261021T020412Z.txt` SHA256 `5AECD71239C87B0943F4CE15B37B0291A8204E0491A520EA6764C9203FA2B82A`; matching JSON summary `TPM-PSSA-Ordered-PS51-20261021T020412Z.json` SHA256 `BC1F46B9D50D273F5AAAC04D0203339EEFE90537D80A2CDF508E6BF46E5C2418`.
- No production or test source was modified, and no commit, push, installation, deployment, merge, release, or live profile/database mutation occurred.