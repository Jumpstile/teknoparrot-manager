# PR #321 TPM Remediation Control Board

Status: blocked. This board is the source of truth for TPM remediation state.

## Current repository state

- Root: `<desktop-repos>\teknoparrot-manager\.worktrees\rc8-release-readiness`
- Branch: `release/rc8-readiness-2026-10-01`
- HEAD at UVO-08 source/evidence capture: `7d92a3f2379038b9c1ba3e3750766e8cf1a5ac42`.
- `origin/release/rc8-readiness-2026-10-01` was verified at `0295415fb1b9d4bf6880945eb4807d4b2b27ec96`; local HEAD is a descendant and one commit ahead. No upstream is configured.
- At source-gate evidence capture, the worktree was dirty across product source, tests, release documentation, remediation docs, and untracked slice contracts; this record does not attribute every entry to one slice.
- This slice covers RC8 progress-path remediation, permanent-gate status semantics, source re-audits, and the separately authorized ReShade ten-effect/twelve-profile behavior contract. Independent review reopened ID 3 because user-added Crosshairs PNGs were materialized/sorted before progress. The working-tree fix reports unknown-total progress through sorting and fails visibly on enumeration errors. The final source gates passed; exact-SHA candidate-source preparation is conditionally authorized. Package, runtime smoke, merge, tag, publication, and release remain unauthorized.

## Status rules

Allowed statuses exactly match `procedureStatuses` in `quality/permanent-procedures.json`: `NOT FIXED`, `SOURCE FIXED; OWNER RUNTIME NEEDED`, `FIXED + TESTED`, `DEFERRED BY OWNER`, `SOURCE CLAIM REQUIRES RE-AUDIT`, `SOURCE CLAIM INVALID / RE-AUDIT REQUIRED`, and `SOURCE REMEDIATION REQUIRED`. The registry also maps each status to the gate disposition.

Promote a source-remediation or re-audit status to `SOURCE FIXED; OWNER RUNTIME NEEDED` only after complete source evidence and focused tests establish the fix. Rebuilt package identity and runtime proof close the separate owner-runtime disposition; they are not prerequisites for recording the source-fixed status.

## Owner report table (historical source audit snapshot)
This table preserves the owner-visible failures and earlier audit evidence.
The historical snapshot above does not control current decisions. The canonical
table below records ID 3 as `SOURCE FIXED; OWNER RUNTIME NEEDED` after
regression/census closure; final source/permanent gates passed.

| ID | Owner-visible failure | Expected behavior | Current status | Owning subsystem | Source/functions | Tests | Runtime proof needed | Next action | Slice assignment |
|---:|---|---|---|---|---|---|---|---|---|
| 1 | ReShade no-change/back/cancel crash | Safe no-op and correct return routing | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade | ReShade action results | Existing ReShade regressions | Packaged U/B smoke | Owner runtime | ReShade follow-up |
| 2 | Duplicate error handling | One authoritative error policy | SOURCE FIXED; OWNER RUNTIME NEEDED | Downloads | Web/download wrappers; RequestErrorAction remediation | RC8 remediation contracts; wrapper source test | Startup/download smoke | Rebuild then owner runtime | Slice 1 |
| 3 | Missing universal progress | Every long-running path has TPM progress, structured workflow status, or an explicit bounded/no-progress reason | SOURCE FIXED; OWNER RUNTIME NEEDED | Progress/status | Source streams unknown-total progress through user-extensible PNG discovery and filename sorting; terminating enumeration failures propagate | Corrected focused regressions pass under Windows PowerShell and PowerShell 7; full Windows PowerShell suite passes 1276/1276; final PS7 aggregate passes 1276/1276 main and 42/42 support plus static/permanent gates | Full packaged operation matrix | Prepare exact-SHA source ref; package only after #290/READY/human gates | Progress.Core |
| 4 | AutoSync scan output | Compact bounded progress | SOURCE FIXED; OWNER RUNTIME NEEDED | Progress/status | Select-GamesInteractive | Compact progress tests | AutoSync smoke | Owner runtime | Progress slice |
| 5 | GPU Fix progress | Compact status without PowerShell panel | SOURCE FIXED; OWNER RUNTIME NEEDED | Progress/status | Invoke-GpuFixSetup | GPU source contracts | GPU Fix smoke | Owner runtime | Progress slice |
| 6 | Thumbnail progress | Accurate compact download status | SOURCE FIXED; OWNER RUNTIME NEEDED | Progress/status | Invoke-ThumbnailDownload | Thumbnail tests | Thumbnail smoke | Owner runtime | Progress slice |
| 7 | Missing thumbnail list | Complete no-icon accounting | SOURCE FIXED; OWNER RUNTIME NEEDED | Progress/status | Thumbnail reporting | Thumbnail tests | Full no-icon matrix | Owner runtime | Progress slice |
| 8 | Thumbnail fallback | Defined 404 behavior | SOURCE FIXED; OWNER RUNTIME NEEDED | Progress/status | Invoke-TpmDownload | Fallback tests | 404 smoke | Owner runtime | Download follow-up |
| 9 | ReShade preview sync | Preview reflects live terminal selection, including Slider mode; terminal is the sole profile authority and the gallery exposes no ignored selector | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade | Read-TpmReShadeTerminalProfile; Sync-TpmReShadeGallerySelection; Get-TpmReShadePreviewStateValue; New-TpmReShadePreviewPaintHandler; New-TpmReShadeGalleryEventHandlers; Flush-TpmReShadeGallerySlider | Preview authority/state tests; synchronized state adapter tests; local WinForms gallery smoke | Owner runtime | Owner runtime | ReShade follow-up |
| 10 | ReShade selector visibility | Selector instructions remain visible | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade | Selector UI | Selector contracts | UI smoke | Owner runtime | ReShade follow-up |
| 11 | Protected ReShade ownership | Adopt/replace safely | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade | Get-TpmReShadeOwnershipClassification; Install-TpmReShadeProfileDeployment; Invoke-ReShadeSetup | ReShade protected-adoption tests | Explicit adopt/replace smoke | Owner runtime | TPM-RESHADE-001 |
| 12 | ReShade accounting | All games and outcomes counted, including unsafe/malformed details and direct repair/rerun action | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade | Get-TpmReShadeApplyPreflight; Get-TpmReShadeApplyAccounting; Invoke-ReShadeSetup; Get-TpmReShadeResultActionModel | ReShade accounting and result-action tests | All-games packaged smoke | Owner runtime | TPM-RESHADE-001 |
| 13 | Crosshair browser completion | Browser completes safely after P2 | SOURCE FIXED; OWNER RUNTIME NEEDED | Crosshair | Export-CrosshairPreview | Crosshair completion contracts | Browser smoke | Owner runtime | Crosshair follow-up |
| 14 | Crosshair focus return | Focus returns to terminal when available | SOURCE FIXED; OWNER RUNTIME NEEDED | Crosshair | Export-CrosshairPreview/focus fallback | Crosshair focus contracts | Focus smoke | Owner runtime | Crosshair follow-up |
| 15 | Crosshair prompt placement | P1/P2 rows are usable | SOURCE FIXED; OWNER RUNTIME NEEDED | Crosshair | Crosshair setup/input | Crosshair contracts | Constrained console smoke | Owner runtime | Crosshair follow-up |
| 16 | PostgreSQL repair loop | Backup/retry/reset is bounded | SOURCE FIXED; OWNER RUNTIME NEEDED | PostgreSQL | PostgreSQL recovery; categorized resume reasons, reachable password validation/reset, and protected retry rebinding | Recovery tests; focused RC8 UX tests | Repair smoke | Rebuild then owner runtime | Slice 2 |
| 17 | Affected-games repair scope | Only affected games are repaired | SOURCE FIXED; OWNER RUNTIME NEEDED | Repair/scoping | Repair-GamePaths | Repair matrix | One/multiple/zero smoke | Owner runtime | Repair follow-up |
| 18 | Health Check no-candidate explanation | No-candidate state is clear | SOURCE FIXED; OWNER RUNTIME NEEDED | Repair/scoping | Health Check reporting | Repair tests | No-candidate smoke | Owner runtime | Repair follow-up |
| 19 | Health Check source re-copy | Source re-copy is scoped | SOURCE FIXED; OWNER RUNTIME NEEDED | Repair/scoping | Scoped AutoSync | Scoped-flow tests | Re-copy smoke | Owner runtime | Repair follow-up |
| 20 | Health Check Back routing | Back returns safely | SOURCE FIXED; OWNER RUNTIME NEEDED | Prompts/navigation | Health Check routing | Routing tests | Back smoke | Owner runtime | Prompt follow-up |
| 21 | Option 10 repair clarity | Repair outcomes are explicit | SOURCE FIXED; OWNER RUNTIME NEEDED | Repair/scoping | Repair result reporting | Result tests | Result smoke | Owner runtime | Repair follow-up |
| 22 | Post-thumbnail repair scope | Optional flows do not escape scope | SOURCE FIXED; OWNER RUNTIME NEEDED | Repair/scoping | Affected-only handoff | Scoped-flow tests | Scope smoke | Owner runtime | Repair follow-up |
| 23 | LaunchBox Back ignored | Back is honored | SOURCE FIXED; OWNER RUNTIME NEEDED | Frontend exports | LaunchBox routing | Back coverage | Packaged B smoke | Owner runtime | Frontend follow-up |
| 24 | LaunchBox prompt wording | Prompt explains action and consequence | SOURCE FIXED; OWNER RUNTIME NEEDED | Frontend exports | LaunchBox prompts | Prompt.Core route contracts | Guided packaged prompt smoke | Owner runtime | Prompt.Core |
| 25 | HyperSpin direct prompt | Safe choice and normal completion | SOURCE FIXED; OWNER RUNTIME NEEDED | Frontend exports | Export-HyperSpinJson | Source contracts | Normal completion smoke | Owner runtime | Frontend follow-up |
| 26 | Invalid optional Y/N input | Invalid values reprompt consistently | SOURCE FIXED; OWNER RUNTIME NEEDED | Prompts/navigation | Read-TpmChoice/Read-TpmYesNo migration; stateful picker boundaries documented | `Read-TpmChoice validation`; `Prompt.Core fixed choice routes` | Invalid-input matrix | Owner runtime | Prompt.Core |
| 27 | Support final prompt | Support choices validate and preserve Back/open-folder behavior | SOURCE FIXED; OWNER RUNTIME NEEDED | Prompts/navigation | Support `1-3` and package `O/B` routes | `Prompt.Core fixed choice routes`; SupportPackage.Tests | Packaged support prompt | Owner runtime | Prompt.Core |
| 28 | Support fatal workflow surfacing | Fatal evidence surfaces | SOURCE FIXED; OWNER RUNTIME NEEDED | Support package | Support manifest | SupportPackage.Tests | Fatal-log smoke | Owner runtime | Support follow-up |
| 29 | Action Required freshness mismatch | Newest evidence is labeled and ambient diagnostics are scoped | SOURCE FIXED; OWNER RUNTIME NEEDED | Support package | Support package freshness, EvidenceClass manifest records, nested plugin-root deduplication | SupportPackage.Tests; support evidence source review | Rebuilt support package and owner review | Complete troubleshooting intake | Support follow-up |
| 30 | Controls truthfulness | Zero-bound results never imply verified readiness | SOURCE FIXED; OWNER RUNTIME NEEDED | Controls truthfulness | Write-ControlPropagationResults; control-readiness engine | Controls truthfulness focused tests; existing controls tests | Zero-bound packaged runtime result | Owner runtime | TPM-CONTROLS-001 |
| 31 | dgVoodoo2 wording | Results explain deployment state | SOURCE FIXED; OWNER RUNTIME NEEDED | Progress/status | dgVoodoo2 result wording | Existing tests | Owner wording review | Owner runtime | Progress slice |
| 32 | Global consistency rule | Every enumerated prompt uses the central contract or has a documented design boundary | SOURCE FIXED; OWNER RUNTIME NEEDED | Prompts/navigation | TPM-PROMPT-001 inventory; finite-choice routes centralized; stateful, exact-token, secure, path, and renderer-aware boundaries documented | `Read-TpmChoice validation`; `Prompt.Core fixed choice routes` | Packaged consistency smoke | Owner runtime | Prompt.Core |
| 34 | Migration explanation and Eggman DAT update path | Migration previews explain destination/categories/exclusions and decline safely; DAT latest/current/updated paths stay consistent; startup requires a valid transaction result and stops on `ACTION_REQUIRED` / `UNKNOWN` before new log/config path selection | SOURCE FIXED; OWNER RUNTIME NEEDED | Migration/DAT | `Test-TpmOwnedMigrationStartupAllowed` and pre-path startup guard; Eggman DAT update orchestration | `rejects invalid migration transaction results before startup`; `allows only valid typed migration outcomes without requiring prompt input`; migration and DAT source contracts | Packaged migration decline/confirm and DAT update smoke | Owner runtime | Slice 6 |
| 33 | FFB membership/prompt and optional-plugin completion | One membership decision, native/no-match zero-deployment outcomes complete, actual errors fail, beginner-safe result wording | SOURCE FIXED; OWNER RUNTIME NEEDED | Force feedback | Invoke-FFBBlasterSetup; Invoke-FFBPluginSetup; Invoke-TpmFfbSetupMode | FFB focused tests; accounting invariants | Packaged mode-8 smoke with native-preferred, no-match, deployment-error paths | Owner runtime | Slice 5 |
| 35 | Cross-cutting user-facing cleanup | Normal prompts spell out TeknoParrot Manager; available full game names lead normal output; compact progress stays bounded; technical identifiers remain in Details/log/support evidence | SOURCE FIXED; OWNER RUNTIME NEEDED | Cross-cutting UI | Normal Write-Host/Read-Host wording; Get-TpmGameDisplayLabel; compact progress renderer | Slice 7 terminology/full-name/progress source contracts | Packaged terminology, representative full-name, and progress smoke | Owner runtime | Slice 7 |
| 36 | PS5.1 certification worker cannot import the IH manifest | Worker resolves its own inbox Utility before analyzer/manifest use | SOURCE FIXED; OWNER RUNTIME NEEDED | Certification infrastructure | Test-TPMProductionInjectionHunterV1 bounded worker | Three real matcher cases, new foreign-Utility child regression, eleven-fact and complete real-inventory assertions pass on both engines | Final frozen gates and source handoff; no live game mutation | Final frozen qualification and handoff gates | TPM-RC8-CERT-WORKER-BOOTSTRAP-001 |

## Subsystem grouping

- Progress/status: IDs 2-8 and 31; ID 3 is `SOURCE FIXED; OWNER RUNTIME NEEDED` after the finite census and passing focused/full Windows PowerShell coverage. The final PS7 aggregate passed. Candidate source-ref preparation is conditionally eligible; exact-package owner runtime remains mandatory.
- Prompts/navigation: 26, 32.
- Repair/scoping: 16-23.
- Migration/DAT: 34.
- ReShade: 1, 9-12.
- Force feedback: 33.
- Crosshair: 13-15.
- PostgreSQL: 16.
- Frontend exports: 23-25.
- Support package: 27-29.
- Controls truthfulness: 30.
- Packaging/runtime provenance: all owner-runtime statuses and stale candidate identity.
- Permanent procedure enforcement: this board, slice contracts, and the fail-closed gate.

## Current blockers

- ID 3 is `SOURCE FIXED; OWNER RUNTIME NEEDED` after the discovery/sort fix, `-ErrorAction Stop`, failing-before/passing-after coverage, and finite census. The final aggregate source/permanent gates passed. Focused tests cover failure closure, sort-before-close, dynamic indices, candidate names, and P1/P2 bytes.
- Historical gate evidence at 2026-10-02T10:29:33.3911233Z predates this source fix. The final frozen full/static source gates and permanent procedure gate passed. Certification's stale check inspects exactly one current-candidate status and continues to block owner-runtime-needed statuses.
- Canonical source re-audit blockers: none among IDs 7, 20, 23-27, or 30-32; IDs 27, 31, and 32 received focused source fixes.
- Other source-fixed/owner-runtime rows are listed individually in the canonical table; do not infer status from the historical snapshot above.
- The earlier wrapper and gate rationale remain historical in `docs/remediation/PR-321-reconciliation.md`; the user-extensible Crosshairs gap is fixed in the working tree. ID 3 is source-fixed with owner runtime needed; final source/permanent validation passed.
- Candidate/package blockers: the candidate ZIP remains stale; current-cycle #290 repository-document/live-wiki review, exact-SHA READY, and human authorization are not established. Use the exact pushed source ref as the #290 audit input; package build remains blocked until those gates pass. Owner smoke and final approval remain outstanding.
- Owner-design blockers: ReShade ownership/accounting and remaining stateful prompt-picker boundaries need explicit future contracts.

## Next-slice queue

1. Run full validation on the updated canonical ID 3 status and regression, then rerun the permanent procedure gate with fresh evidence.
2. If every source gate passes, follow the authorized candidate-preparation path; retain exact pushed-SHA identity and package validation, then hand the candidate to the owner on the test PC for owner smoke.
3. Do not merge, tag, publish, release, or claim owner-runtime completion before the owner's final approval.

## Control-board rule

A remediation change is not complete until its owner IDs, slice contract, behavior contract, focused tests, runtime proof requirement, and hunk classification are recorded here and in the remediation report.

## PostgreSQL reset transport remediation slice

Owner report ID 16 / PR #321 is assigned to
`TPM-POSTGRES-RESET-TRANSPORT-001`. The source contract requires byte-verified
authentication-policy restoration before restart and fail-closed service state
if restoration cannot be verified. Owner-reported test-PC evidence establishes
that the mechanism succeeded on the physical PostgreSQL 8.3 install; it does
not establish that this source revision or a rebuilt package has been tested.
PS7 and Windows PowerShell 5.1 focused regressions cover reset success, failure,
service-stop failure, originally-stopped service state, and policy restoration.
The source-quality gate, exact pushed-SHA package, and new runtime evidence
remain required before release.
## Canonical release-decision status -- live re-audit correction -- 2026-10-01

This section is the canonical release-decision source. It supersedes the
historical owner mapping and prior blocker prose above. The candidate ZIP
remains stale and is not a release gate.

| ID | Previous status | Corrected status | Evidence | Source remediation | Owner retest |
|---:|---|---|---|---|---|
| 1 | SOURCE REMEDIATION REQUIRED | SOURCE FIXED; OWNER RUNTIME NEEDED | Finite-buffer red/green, final-revision 60-case chooser cohort and unmocked native 32-row output pass on both engines; scoped source/delta review passed | TPM-RC8-RESHADE-CONSOLE-BUFFER-001 implemented; final frozen gates pending | Yes, eligible rebuilt package |
| 2 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Full source audit found only the wrapper's splatted Invoke-WebRequest call; all callers use the typed RequestErrorAction contract; Slice A source test passes | No | Yes, rebuilt package |
| 3 | SOURCE REMEDIATION REQUIRED | SOURCE FIXED; OWNER RUNTIME NEEDED | The user-extensible discovery/sort gap is fixed; focused tests and finite census pass; the final full source/permanent aggregate gate passed. | No source edits remain for the gap | Yes, full packaged operation matrix |
| 4 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | `Select-GamesInteractive` and `Select-GamesInteractiveCombined` report each ZIP across their known source total, including main and supplementary sources; both real call-site tests pass in PS7 and Windows PowerShell 5.1 | No further source change | Yes |
| 5 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Both GPU GameProfiles scan helpers report each catalog item against the known XML total and close the compact row; real call-site behavior tests passed in PS7 and Windows PowerShell 5.1 | No further source change | Yes |
| 6 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Thumbnail progress and named failure reporting are source/test covered; Slice A focused tests pass | No | Yes |
| 7 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | `Invoke-ThumbnailDownload` adds only definitive-404 profile codes to the current missing-no-icon list and reports that list separately from transient download failures; source supports complete per-run accounting | No | Yes, full no-icon matrix |
| 8 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Definitive 404 is preserved across fallback; Slice A regression test passes | No | Yes |
| 9 | SOURCE REMEDIATION REQUIRED | SOURCE FIXED; OWNER RUNTIME NEEDED | Final-revision chooser/input/HDR/gallery/reopen cohort passes 60/60 per engine; rendering-time resize regression fails before and passes after correction | TPM-RC8-RESHADE-CONSOLE-BUFFER-001 implemented; final frozen gates pending | Yes |
| 10 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Selector contract remains source/test supported | No | Yes |
| 11 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade ownership re-audit confirms protected unknown/bundled content stays unchanged by default; explicit confirmed Adopt passes overwrite only through the transactional deployment path; Slice C tests pass | No | Yes |
| 12 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade accounting now includes explicitly kept previous TPM-managed profiles as a terminal `KeptPrevious` outcome; accounting invariant remains exact; Slice C tests pass | No | Yes |
| 13 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Completed non-interactive browser state after valid P2; explicit return/close guidance; no further click mutation | No | Yes |
| 14 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Best-effort console focus return with logged fallback; terminal remains usable | No | Yes |
| 15 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Workflow-aware P1/P2, confirmation, first-run, and cursor-hide prompts with typed fallback | No | Yes |
| 16 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | SUPERSEDED in part (FIX95, owner rule R4): the automatic PostgreSQL 8.3 reset transport was removed. The product now refuses the reset, changes nothing, and shows manual steps under Details (`Show-PostgresPasswordResetUnavailable`); `TPM-POSTGRES-RESET-TRANSPORT-001` is historical only and must not be used as a requirement. Still in force: default install/recovery/reinitialize gives explicit temporary-admin/UAC/Yes/automatic-resume guidance immediately before each elevation handoff without exposing internals. PS7 and Windows PowerShell 5.1 focused UX suites each pass 60/60; complete source-quality and permanent procedure gates pass. Exact pushed-SHA package/runtime evidence remains pending. | `TPM-POSTGRES-RESET-TRANSPORT-001` (SUPERSEDED); `TPM-POSTGRES-UAC-GUIDANCE-001`; PostgreSQL focused tests | Exact pushed-SHA package install smoke; recovery must show the refusal and manual steps (no reset); reinitialize smoke |
| 17 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Repair candidate search and apply calls are limited to the affected broken profile codes; focused one/multiple/zero-scope tests pass | No | Yes |
| 18 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | No-candidate reporting includes searched-folder and affected-profile evidence plus Back; focused tests pass | No | Yes |
| 19 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Optional source recopy hands only affected profile codes to AutoSync; no broad extraction escape found | No | Yes |
| 20 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | `Show-LibraryHealthNextActions` exposes validated Back in both broken-path and normal menus; main-loop dispatch performs no optional action for B and returns to the menu | No | Yes |
| 21 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Repair results classify every report once and require saved-path read-back before FIXED; focused accounting tests pass | No | Yes |
| 22 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Post-repair result completes before the optional thumbnail prompt; scoped source handoff remains affected-only | No | Yes |
| 23 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | LaunchBox presents B as Back; only A enters direct-write setup and only F creates the manual reference route | No | Yes |
| 24 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | LaunchBox prompt explicitly distinguishes preview/no-write, add/update/write, manual reference/no-write, and Back; platform selection is enumerated | No | Yes |
| 25 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Missing HyperSpin emulator ID offers validated G/S; both paths return without writing game associations or inventing an ID | No | Yes |
| 26 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Shared `Read-TpmChoice`/`Read-TpmYesNo` reject invalid finite choices; secure, exact-token, free-text, and stateful exceptions remain specialized | No | Yes |
| 27 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Support `1-3` plus post-ZIP O/B are validated; O uses the canonical non-reparse folder opener; route and restore-transition behavior tests pass | `TPM-PR321-PROMPT-RESULTS-002`; PS7 focused tests | Yes |
| 28 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Manifest includes stale Action Required evidence correctly | No | Yes |
| 29 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Support manifest classifies game-local plugin inventories as Ambient; manifest defines Ambient as supplied/discovered without current-run provenance; entries explicitly say metadata-only and DLL payloads not copied; focused SupportPackage test verifies class and excludes plugin filenames | No further source change | Yes, rebuilt package and owner review |
| 30 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Zero-bound results return and display `VerifiedPhysicalBindingsCount = 0`; controls-readiness remains NotVerified absent current physical verification; focused result tests cover settings-only and API-fixed reports | No | Yes |
| 31 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | `Get-DgVoodoo2FailureGuidance` recommends reconnecting an unavailable device and offers Library Health Check only for MissingPath; mixed results preserve both actions. The apparent successful-with-skips screen remains unreachable. | `TPM-PR321-PROMPT-RESULTS-002`; three guidance behavior tests | Yes |
| 32 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Three previously direct restore-number prompts now use `Read-TpmChoice`; focused tests exercise invalid retry and blank-to-Back for UserProfiles, LaunchBox, and PostgreSQL; source audit found no other finite numbered/Y-N route outside documented boundaries | `TPM-PR321-PROMPT-RESULTS-002`; focused route tests | Yes |
| 33 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Preserve existing FFB membership/completion mapping and its source evidence; not changed or newly certified in this slice | No additional change in this slice | Yes, packaged mode-8 smoke |
| 34 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Preserve the active-migration consumer correction recorded below and its nine-case native proofs; no new owner-runtime claim | No additional change in this slice | Yes, packaged migration and DAT smoke |
| 35 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Preserve existing cross-cutting terminology/full-name/progress mapping; not changed or newly certified in this slice | No additional change in this slice | Yes, packaged terminology and progress smoke |
| 36 | SOURCE REMEDIATION REQUIRED | SOURCE FIXED; OWNER RUNTIME NEEDED | Real native child, three matcher cases, eleven facts and complete 21-file analyzer inventory pass on both engines; harness finalization finding reproduced and repaired | TPM-RC8-CERT-WORKER-BOOTSTRAP-001 implemented; 180-second bound unchanged | Final frozen gates and handoff; no owner acceptance claim |

- Historical false source-fixed claims included IDs 2, 13, and 14. The current crosshair slice supersedes the prior ID 13/14 disposition with source-fixed completed-state/focus behavior. IDs 16 and 29 remain source-fixed by their re-audits; IDs 7, 20, 23-27, and 30-32 have now been re-audited and are source-supported, with IDs 27, 31, and 32 receiving focused fixes. ID 3's discovery/sort implementation, focused tests, and finite census are complete; its canonical status is `SOURCE FIXED; OWNER RUNTIME NEEDED`, and the final source/permanent validation passed.

Candidate source-ref preparation is conditionally authorized after the source gates. Package build remains blocked on exact pushed-SHA identity, current-cycle #290 repository-document/live-wiki review, exact-SHA READY, and human authorization. Owner-runtime verification remains required; no merge, tag, publication, or release action is authorized.

## Library Health repair slice -- working-tree evidence

The bounded Library Health repair slice addresses the source-remediation portion
of IDs 17-22 without changing their owner-runtime requirement or the blocked
release state. `Repair-GamePaths` now returns explicit `CANDIDATE`, `FIXED`, and
`STILL BROKEN` outcomes; a saved profile is read back and revalidated before it
can be reported as fixed. Health Check search progress is limited to the
affected profile codes, candidate and before/after GamePath evidence is
redacted for display, already-registered output is summarized, and thumbnail
prompts follow the completed repair result. Raw Thrills path-length guidance
now tells the user to shorten parent folders and update the saved GamePath.
Focused Library Health tests cover the new outcomes and save-verification
failure. Package rebuild and owner runtime proof remain outstanding.

## Progress and thumbnail reporting slice -- working-tree evidence

The next bounded source slice keeps the release blocked while correcting the
user-visible progress contract. Library Health repair now reports the actual
game-file enumeration with an unknown total, then continues profile checks with
one stable elapsed timer. Compact rows use fractional elapsed seconds, and the
web transport fallback is shown as `web fallback` instead of raw
`Invoke-WebRequest` wording. Thumbnail checks identify the current profile and
count/total, keep HTTP 404 no-icon results separate from other failures, and
list transient failure profile codes for retry. Thumbnail setup remains an
optional prompt after repair. Focused tests pass; package rebuild and owner
runtime proof remain outstanding.

## Slice A -- web/download and thumbnail correctness

Owner IDs 2, 6, and 8 were the bounded source-remediation rows for this
slice. The shared web wrapper uses one typed request-action parameter, and
thumbnail work uses the shared compact progress row with profile/count labels
and named failure accounting. The downloader now retains a definitive HTTP
404 across transport fallback, so a later unknown fallback error cannot turn a
missing upstream icon into a transient failure. Non-404 transport, validation,
and integrity failures remain retry/failure outcomes. Focused source tests and
the full validation gates pass. Package rebuild and owner-runtime proof remain
outstanding.

## Slice C -- ReShade ownership and accounting

Owner IDs 11 and 12 received a bounded ReShade source re-audit. Protected
unknown/user-owned and bundled content remains unchanged under the default
Select action. Explicit confirmed Adopt/replace remains the only path that
passes `AllowUserOwnedOverwrite`, and the existing transactional deployment
backs up target files before promotion and preserves rollback evidence when
backup or rollback cleanup fails. The final all-games accounting now counts
explicitly kept previous TPM-managed profiles as `KeptPrevious`, preventing a
bulk profile decision from producing an unaccounted selected game. ReShade
result actions continue to prioritize protected conflicts over optional
Health Check routing. Focused ReShade tests and the full main suite pass.
Package rebuild and owner-runtime proof remain outstanding.

## Slice E -- Library Health repair scope

Owner IDs 17, 18, 19, 21, and 22 received a bounded Library Health
source re-audit. Candidate search and reviewed apply remain limited to the
affected broken profile codes. One, multiple, zero, and no-candidate cases
retain explicit outcomes; no-candidate output includes searched-folder and
affected-profile evidence with Back routing. Repair writes require a complete
profile backup and saved-path read-back before `FIXED` is reported. Repair
results now expose exact fixed/candidate/still-broken accounting. Optional
source recopy re-enters AutoSync with `OnlyProfileCodes` restricted to the
affected set, preventing a broad extraction escape. The repair result is
completed before the optional thumbnail prompt. Focused Library Health tests
and the full main suite pass. Package rebuild and owner-runtime proof remain
outstanding.

## Crosshair close, focus, and prompt slice -- working-tree evidence

The crosshair findings were re-audited independently:

| ID | Current source disposition | Evidence |
|---:|---|---|
| 13 | SOURCE FIXED; OWNER RUNTIME NEEDED | After valid P2 selection, generated HTML reports completion, becomes non-interactive, and tells the user to return to TPM and close the tab. |
| 14 | SOURCE FIXED; OWNER RUNTIME NEEDED | Console focus is attempted after bridge polling; failure is logged without blocking typed fallback or terminal confirmation. |
| 15 | SOURCE FIXED; OWNER RUNTIME NEEDED | P1/P2, confirmation, first-run, and cursor-hide prompts use the workflow-aware renderer when a CrosshairSetup context is available; standalone typed fallback remains direct and bounded. |

Crosshair file deployment remains after terminal confirmation, and cancellation
returns without deployment. Focused crosshair tests and full validation are
required before this slice can be called ready. Package rebuild and owner
runtime proof remain outstanding.

## Owner-Smoke Remediation Slice 1 -- BepInEx safety and rollback

Status: SOURCE REMEDIATION IN PROGRESS; OWNER RUNTIME BLOCKED

Scope:

- Canonical containment accepts valid child destinations such as
  `GameRoot\BepInEx\core\0Harmony.dll`.
- Genuine escapes, reparse/junction hazards, and unsafe roots remain blocked.
- Generic inspection failures now receive concrete reason categories and
  beginner-safe next actions; technical details remain in logs/evidence.
- Rollback failure is terminal, preserves backup/staging evidence, and does
  not recommend blind retry as the default action.
- BepInEx prompts visibly list `[B] Back`; normal output uses full profile
  names when available and `TeknoParrot Manager` in touched paths.

Evidence distinction:

- `ElevatorAction` remains log-only evidence because
  `metadata\profile-ElevatorAction.txt` was absent from the support ZIP.
- The broader “inspection failed” pattern across roughly 20 games remains a
  separate classification/reproduction target, not an ElevatorAction-only
  conclusion.

Owner retest required after commit and package rebuild. No owner smoke is
authorized from this working tree.

## Slice 8 -- PostgreSQL recovery data safety

Slice 8B source implementation resolves normal PostgreSQL recovery names from
authoritative `/GameProfile/GameName` metadata and uses
`Unknown game title -- see Details` when the title is absent. Normal
read-only diagnosis now contains only grouped beginner-safe statuses and one
collapsed technical-detail summary; profile keys, database names, and raw
client details remain in Details, logs, and support evidence. Automatic reset
results expose a specific `FailureStage`, and password validation/reset
activities update workflow status instead of leaving the database-backup
activity active.

Focused Slice 8B behavioral tests cover readable and unknown titles, normal
diagnosis exclusions, technical evidence retention, reset stages, reset
guidance, workflow activities, and password/reset separation from
reinitialize. Package rebuild and owner-runtime proof remain outstanding.

## Engineering S1 -- PostgreSQL 8.3 database restore transaction

Status: SOURCE REMEDIATION IMPLEMENTED; OWNER SMOKE PAUSED

| Owner ID | Scope | Source ownership | Focused evidence | Runtime/release disposition |
|---:|---|---|---|---|
| 16 | PostgreSQL restore transaction and coupled profile/database rollback | `TeknoParrot-Manager.ps1`; `Tests/TeknoParrot-Manager.Tests.ps1` | S1-DB-RESTORE deterministic fake PostgreSQL 8.3 harness and transaction-core contracts | No PostgreSQL 12 proof; no package, push, owner smoke, test-PC, wiki, merge, tag, publish, certification, or release action |

The S1 contract is `docs/remediation/slices/TPM-S1-DB-RESTORE-001.md`.
The source boundary includes tool-version gating, closed selected-backup
preflight, verified current-database dumps, deterministic receipts/order,
stop-on-first-failure mutation, verified rollback, final verification,
`TPM.TransactionResult.v1`, and beginner-safe normal restore output. Owner
smoke remains paused pending coordinator review and later explicit authorization.
- Final Engineering evidence: PowerShell parser `ParseErrors=0`;
  PSScriptAnalyzer Error/Warning `Findings=0`; ASCII check `NonAscii=0`;
  `git diff --check` clean apart from Git's LF-to-CRLF warnings; canonical
  Pester 5.7.1 main suite `1121 passed, 0 failed`; focused S1 suites:
  `S1-TX-CORE 18`, `S1-FILE-PROMOTION 12`,
  `S1-DIRECTORY-REPLACEMENT 18`, `S1-BACKUP-GATE 9`,
  `S1-DB-RESTORE 12`, all passed.

## Engineering S1 -- legacy state transaction normalization

Status: EXISTING TRANSACTION FIXES IMPLEMENTED; RC8 REVIEW P1-2 SOURCE FIXED; FOCUSED POLICY TESTS 2/2 PASSED; SOURCE GATES/EXACT-HEAD CI PENDING; OWNER SMOKE PAUSED

Slice contract: `TPM-S1-LEGACY-STATE-TRANSACTIONS-001`.
The authorized scope normalizes legacy result shapes to
`TPM.TransactionResult.v1` for GPU Fix, TPM-owned migration, UserProfiles
restore, Register-Games, control propagation, Library Health automatic and
manual repair, PCSX2 cursor-path updates, ReShade, BepInEx, PostgreSQL
password recovery, and PostgreSQL reinitialize. The implementation preserves
legacy detail properties for existing callers while making the v1 result the
authoritative return value.

The transaction validator now rejects false success, unverified rollback,
unaccounted terminal items, and cleanup residue presented as ordinary success.
Verified profile backups gate destructive profile workflows. Beginner-facing
summaries remain free of paths, commands, hashes, database names, and
credentials; technical evidence remains available through result detail
properties and existing logs. LaunchBox export/restore, HyperSpin export,
thumbnail acquisition, and optional artifact/download workflows were not
changed.

RC8FullReview P1-2 found that `ACTION_REQUIRED` / `UNKNOWN` migration results continued into the new log/config paths. The ID 34 fix now requires `Test-TpmTransactionResult` to accept a valid `TPM.TransactionResult.v1`, then stops non-interactively before path selection for `ACTION_REQUIRED` or `UNKNOWN`. The focused typed-result and malformed-result policy tests passed 2/2. The full source quality wrapper has now passed; exact-head CI and owner runtime remain pending or paused.

Source and focused migration policy tests pass; the full source quality wrapper has now passed and fresh exact-head CI remains pending. Commit/push is authorized only to PR #321's existing head ref for exact-head CI. Package rebuild, owner runtime, test-PC, wiki, merge, tag, publish, certification, and release-ready action remain unauthorized.

## Engineering S1 -- setup and manager-update transaction normalization

Status: EXISTING TRANSACTION NORMALIZATION IMPLEMENTED; MAIN AND STANDALONE P1-1 IDENTITY/PRE-REPLACEMENT VALIDATION IMPLEMENTED; MAIN FULL SUITE 1290/1290 UNDER BOTH ENGINES; STANDALONE CORE 51/51 UNDER BOTH ENGINES; SOURCE QUALITY WRAPPER PASSED 2026-10-03T07:45:16.7882201Z; EXACT-HEAD CI PENDING; OWNER RUNTIME NEEDED; OWNER SMOKE PAUSED

Slice contract: `docs/remediation/slices/TPM-S1-SETUP-UPDATE-TRANSACTIONS-001.md`.
The authorized boundary makes `Invoke-PostgresGameSetup`,
`Invoke-ManagerUpdateInstall`, `Invoke-CheckForUpdates`, and
`Invoke-StartupUpdateCheck` return authoritative `TPM.TransactionResult.v1`
results. PostgreSQL setup now gates non-no-op mutation on verified recovery
evidence and verifies profile/database state after writes. Manager update paths
carry full local version identity and verify candidate/version plus installed
file hash and identity. Both updater paths now parse unique direct, unscoped
top-level literal declarations without executing candidate content; each
candidate must match the release tag before replacement, and extracted bytes
above `0x7F` fail closed before AST parsing. The main updater verifies installed
identity after replacement. P1-1 source remediation is implemented; the full
source quality wrapper passed at `2026-10-03T07:45:16.7882201Z`; exact-head CI
remains pending.

Top-level callers validate the v1 result and restart only after `SUCCEEDED`.
Legacy counters and detail properties remain compatibility fields, not the
authoritative completion signal.
At the earlier transaction-normalization checkpoint, focused setup/update
coverage passed `60/60`, required S1 transaction regression tags passed
`16/16`, and the main Pester suite passed `1125/1125`. That checkpoint recorded
parser `ParseErrors=0`, source ASCII `NonAscii=0`, PSScriptAnalyzer
Error/Warning `Findings=0`, `git diff --check`, and InjectionHunter 1.0.0 with
`42` findings and `0` unresolved after matching the then-current disposition
registry. The current update-identity regression counts and static-gate status
are recorded in the P1-1 section below. Package rebuild, owner runtime, test-PC,
wiki, merge, tag, publish, certification, and release-ready actions remain
unauthorized. Commit/push is authorized only after source gates pass and only
to PR #321's existing head ref for exact-head CI.

## Engineering S1 -- RC8 update version ordering

Status: MAIN FULL SUITE 1290/1290 UNDER BOTH ENGINES; STANDALONE CORE 51/51 UNDER BOTH ENGINES; DESTRUCTIVE APPLY 10/10; SOURCE QUALITY WRAPPER PASSED 2026-10-03T07:45:16.7882201Z; EXACT-HEAD CI PENDING; OWNER RUNTIME NEEDED; OWNER SMOKE PAUSED

Slice contract: `docs/remediation/slices/TPM-S1-UPDATE-VERSION-ORDERING-001.md`.
Owner mapping: PR #321 row 81 (startup/update flow); review finding RC8FullReview P1-1; issue #105 is supporting context only. Its earlier final/RC equality assumption is superseded by the explicit RC7 < RC8 < final 1.0 requirement.

Both updater paths parse identity declarations without executing candidate
content, reject extracted bytes above `0x7F` before AST parsing, and require
complete candidate identity to equal the release tag before replacement. The
main updater also verifies installed identity after replacement; the
standalone local-version reader uses the same strict AST declaration contract.
Main Pester passed 1290/1290 under PowerShell 7 and Windows PowerShell 5.1;
the latest full Windows PowerShell run finished at
2026-10-03T07:14:35.7219195Z. The standalone core suite passed 51/51 under
both engines and destructive apply passed 10/10 under PowerShell 7. Both
engines parsed every changed PowerShell file with zero errors, the main script
has zero non-ASCII bytes, and configured PSScriptAnalyzer returned zero
findings for the main script and both updater scripts. Canonical InjectionHunter
1.0.0 ran at 2026-10-03T07:13:10.8658645Z--2026-10-03T07:14:39.3309246Z:
40 findings, all 40 matched to individually reviewed `FalsePositive`
dispositions, zero unresolved. The source quality wrapper passed at
`2026-10-03T07:45:16.7882201Z`; exact-head CI remains pending.

## Engineering -- RC8 typed identity-target delta

The P1-1 test counts and gate results above are the pre-delta baseline; they do not verify the current change.

Status: EXPANDED UVO-08 IMPLEMENTED; FULL MAIN/SUPPORT/UPDATER-CORE/DESTRUCTIVE SUITES PASSED UNDER WINDOWS POWERSHELL 5.1 AND POWERSHELL 7.6.6; PARSE/ASCII/ANALYZER/INJECTIONHUNTER PASSED; FRESH Run-TpmQualityGate AND PERMANENT PROCEDURE GATE PASSED 2026-10-03T13:03:44.2421320Z

Review report: `TPM-7D92-DELTA-20261003`; reviewed commit `7d92a3f2379038b9c1ba3e3750766e8cf1a5ac42`; original finding was a typed/cast-wrapped assignment target skipped by both variable-only AST filters. A parsed-only follow-up found direct parenthesized and cast-parenthesized targets expose additional target AST shapes.

Mapping: PR #321 owner row 81; PR #321 review finding `TPM-7D92-DELTA-20261003`; supporting issue #105; slice `TPM-S1-UPDATE-VERSION-ORDERING-001`; permanent procedures `TPM-TRACE-001` and `TPM-EVIDENCE-001`; owner-runtime evidence remains under `TPM-OWNER-001`.

Before-fix evidence: the added `[UVO-08]` focused tests failed under both Windows PowerShell 5.1 and PowerShell 7.6.6. The main parser and candidate-validator tests did not throw, and the main install test observed one `Move-Item` call. The standalone local reader, candidate validator, and `-Apply` no-replacement tests did not throw. This reproduces the reviewed acceptance path; candidate content was not executed.

Current implementation: both parsers explicitly traverse only assignment targets and recognized lvalue structures: attributed/cast child, transparent single-expression parentheses, array elements, member-expression roots, and index-expression targets. Iterative stack traversal handles nested destructuring without recursive call-stack growth. Both scanners additionally reject protected increment/decrement, foreach variables, root-script parameters, and named data-statement variables while allowing function-local parameters. Dynamic and indirect mutation remains outside the finite static contract; this is not a sandbox.
Contract-plan review: reviewer confirmed the finite matrix and the root-parameter refinement. Scan only `$scriptAst.ParamBlock.Parameters` for protected root parameters; function-local `ScriptVersion` and `ReleaseCandidateLabel` parameters in `Get-ManagerVersionIdentity` must remain allowed. Member/index detection follows only their lvalue-root properties, not arbitrary descendants.
Mapping: PR #321 owner row 81; review report `TPM-7D92-DELTA-20261003`; issue #105; slice `TPM-S1-UPDATE-VERSION-ORDERING-001`; permanent procedures `TPM-TRACE-001` and `TPM-EVIDENCE-001`; owner-runtime evidence remains under `TPM-OWNER-001`.
Pre-expansion before-fix evidence: focused tests reproduced accepted cast/parenthesized protected writes under both engines; prior review artifacts document the main install `Move-Item` and standalone apply no-replacement failures. Candidate content was not executed.
Historical pre-expansion checks only: focused UVO-08 tests passed 6/6 in both engines; PS7 full Pester passed 1357/1357 and PS5 full Pester passed 1357/1357 before the latest attributed-expression discovery. The integrated `bg_87` run passed main Pester 1293/1293 and SupportPackage 42/42, but its permanent procedure gate failed because validation evidence predated the latest source/test/gate changes (`artifact://1060`). Preserve these outputs; none is current final acceptance.
Current focused proof after implementation: main `[UVO-08]` Pester tests passed `6/6` under Windows PowerShell 5.1 and `6/6` under PowerShell 7.6.6; standalone core tests passed `7/7` under both engines. The matrix explicitly checks parser errors are zero for valid proof snippets, direct and nested tuples, wrapped/cast/attributed/scoped writes, unary operators, foreach/root parameters/data statements, member/index roots, local-parameter and unrelated-index near-misses, candidate validation, and no replacement. The standalone local reader also accepted the actual manager source identity `1.0-RC8` under both engines. These focused results do not replace final source review, full suites, static gates, or the permanent procedure gate.
The earlier `APPROVED` source/test review applied only to pre-expansion hashes; the subsequent attributed-target review returned CHANGES REQUIRED. The final review of the expanded implementation and regression matrix found no blocking findings. Exact reviewed source/test SHA-256 values and the audit timestamp are recorded in the reconciliation report. Dottie owns remote CI; do not poll or terminate that process.
Full-suite evidence: each engine passed Main `1296/1296`, SupportPackage `42/42`, updater core `58/58`, and destructive-path `10/10`. Static evidence: parser errors `0` in the four changed PowerShell files under both engines; product main script non-ASCII byte count `0`; configured PSScriptAnalyzer `0` findings for main and both updater scripts under both engines; canonical InjectionHunter `40` findings, `0` unresolved, version `1.0.0`. The fresh source wrapper and its permanent procedure gate passed at 2026-10-03T13:03:44Z. The report records the following post-board-sync artifact test and permanent gate run; a final report-consistency pass must follow the evidence update before commit.
No package build, runtime/owner smoke, merge, tag, release, certification, publication, or live wiki action is authorized. User-authorized scoped commit/push to the existing PR #321 head is conditional on all required gates passing; parent owns exact-head CI, and CI will not be monitored from this lane.

## Engineering -- exact-head CI and owner-status output

Run `37090573916` checked out synthetic merge tree `39301e430849c0996746187aecfffa937fe705b6`, not PR head `0295415fb1b9d4bf6880945eb4807d4b2b27ec96`. The failed assertion is in the owner-status gate test, not either RC8FullReview product path. Captured child `Write-Error` output contains ANSI escapes between the expected status tokens; Pester's NUnit exporter then fails on the raw ESC byte. The `TPM-OWNER-STATUS-GATE-001` delta (owner ID 3; `TPM-OWNER-003`, `TPM-TRACE-001`, and `TPM-AUTH-001`) normalizes captured output and makes CI checkout/assert the exact PR head SHA. No owner status is promoted by this test-only correction.

## Engineering S2-A -- shared transaction presentation contract

Status: SOURCE REMEDIATION IMPLEMENTED; OWNER SMOKE PAUSED

Slice contract: `docs/remediation/slices/TPM-S2-RESULTS-PRESENTATION-001.md`.

The authorized S2-A scope adds the deterministic
`TPM.TransactionPresentation.v1` projection from validated
`TPM.TransactionResult.v1`. It fixes the seven outcome meanings, beginner-safe
headline/change/next-action/retry/data-safety wording, authoritative item-set
counts, safe item labels, and Details/support references without embedding raw
transaction evidence.

`Assert-TpmTransactionPresentation` rejects invalid schema, outcome wording,
identity, product state, underlying cleanup state, unsafe text, and
count/label mismatches. Compatibility booleans, legacy counters, workflow
status, and console text are not presentation authority. The source contract
does not migrate workflow renderers, workflow-status events, or support-package
serialization; those remain later S2 integration scope.

Focused S2-A tests cover all seven outcomes, compatibility-field
non-authority, NO_OP/ACTION_REQUIRED/CLEANUP_RESIDUE distinctions,
verified-rollback and partial-change wording, item accounting, and technical
redaction. Full validation evidence is recorded in the corresponding
reconciliation section after execution. Owner smoke, package rebuild, test-PC,
wiki, push, merge, tag, publish, certification, and release-ready actions
remain unauthorized.

## Engineering S2-B1 -- shared transaction renderers

Status: SOURCE REMEDIATION IMPLEMENTED; OWNER SMOKE PAUSED

Slice contract: `docs/remediation/slices/TPM-S2B1-RENDERERS-001.md`.

The authorized S2-B1 scope adds pure shared normal and Details renderers over
`TPM.TransactionPresentation.v1`, with a separate
`TPM.TransactionDetailsContext.v1` redaction/provenance boundary. The narrow
workflow status bridge accepts only a validated presentation as terminal
transaction authority: only `SUCCEEDED` can display `[OK]` or `Finished`;
`NO_OP`, rollback, partial, failure, action-required, and cleanup-residue
states retain their distinct non-success wording. Required but missing or
invalid terminal presentation fails closed. The normal ReShade onboarding
summary now uses the shared normal renderer without migrating its acquisition,
ownership, or details flow.

Focused S2-B1 renderer tests pass `12/12` for all seven outcomes, item ordering,
Details identity/redaction, status authority, fail-closed terminal behavior,
the ReShade summary adapter/detail preservation, actual ReShade changed,
skipped, and failed item-label mapping, and selected-set transaction accounting.
Full main Pester passes `1152/1152`. Windows PowerShell and pwsh parser checks,
PSScriptAnalyzer, ASCII, and `git diff --check` pass. No workflow-wide
migration, support-package serialization change, package rebuild, owner smoke,
Test-PC, wiki, push, merge, tag, publish, certification, or release-ready action
is authorized by this slice.

## Engineering -- BepInEx functional transaction audit

Status: SOURCE REMEDIATION IMPLEMENTED; OWNER SMOKE PAUSED

Slice contract: `docs/remediation/slices/TPM-BEPINEX-FUNCTIONAL-TRANSACTION-001.md`.

The authorized BepInEx correction resolves the per-game package from the
architecture-keyed download map and validates the contained, existing,
non-reparse package immediately before extraction. Candidate game-path identity
is preserved and revalidated before staging, backup, and promotion. Protected
or reparse-backed roots remain unchanged safe skips.

The compatibility transaction now carries actual selected, changed, failed, and
skipped profile IDs. Counter-derived names and unrelated XML profiles are not
used. FailureRecords remain available as technical evidence. Normal output is
compact and beginner-safe, uses readable game names when present, keeps
protected roots explicitly unchanged, and distinguishes a verified package
download from a failed per-game install without printing raw paths or exception
text.

Focused BepInEx evidence: 19 passed, 0 failed, 0 skipped. S1 transaction-core
evidence: 18 passed, 0 failed, 0 skipped. S2-A presentation evidence: 15
passed, 0 failed, 0 skipped. S2-B1 renderer evidence: 12 passed, 0 failed,
0 skipped. Full main Pester: 1155 passed, 0 failed, 0 skipped. Support Pester:
41 passed, 0 failed, 0 skipped. Windows PowerShell and pwsh parser checks
passed; PSScriptAnalyzer findings: 0; production ASCII non-ASCII bytes: 0;
Disposition-backed canonical InjectionHunter check: `Executed=True`;
`FindingCount=42`; `UnresolvedFindingCount=0`; `ToolVersion=1.0.0`;
`StaleEntries` was not reported by the result object.
The permanent procedure gate executed after these checks; it failed closed
without release authorization because owner-runtime evidence remains outstanding
and the supplied reconciliation report is newer than the source timestamp used
for its freshness check. Owner/runtime smoke, package rebuild, test-PC, wiki,
push, merge, tag, publish, certification, and release-ready actions remain
unauthorized.

## Engineering -- Support posture corpus and CHD/layout implementation

Status: IMPLEMENTATION COMPLETE; OWNER-RUNTIME EVIDENCE REQUIRED

Slice contract: `docs/remediation/slices/TPM-SUPPORT-POSTURE-001.md`.

Owner requirement: `SUPPORT-POSTURE-001`, including the skylinekiller CHD/layout
finding. This implementation adds offline evidence tooling only. Product
registration, repair discovery, `.chd` recognition, and TeknoParrotUI-owned
field writes are unchanged.

Implemented source: `scripts/New-TpmSupportPostureCorpus.ps1`. It ingests
explicit installed and pinned upstream profile roots, records source identity
and XML hashes, overlays installed records by case-insensitive ProfileCode,
keeps UserProfiles observation-only, and treats Eggman/RomVault DAT data as
secondary evidence.

Generated artifacts are deterministic BOM-less UTF-8: `manifest.json`,
`support-posture.json`, `support-posture.md`, `fixture-coverage.json`,
`observations/userprofiles.json`, `dat/dat-summary.json`, and copied raw XML
profile snapshots below one explicitly supplied output root. Markdown omits
raw filesystem paths.

The focused fixture corpus contains 22 records. Actual generated totals:
`AUTOMATED_SAFE=4`, `REVIEW_MANUAL=13`, `BLOCKED_UNSUPPORTED=5`,
`UNCLASSIFIED=0`; all 22 fixture expectations passed. All 15 required
CHD/layout taxonomy classes are represented. The release calculation reports
zero `UNCLASSIFIED` and closure eligible for this complete fixture snapshot.

Focused proof under Pester 5.7.1: `Tests/SupportPostureCorpus.Tests.ps1`
passed 9, failed 0, skipped 0. Existing local gates also passed:
`TeknoParrot-Manager.Tests.ps1` 1155 passed, 0 failed, 0 skipped, and
`SupportPackage.Tests.ps1` 41 passed, 0 failed, 0 skipped.

Static proof: Windows PowerShell 5.1 and pwsh parser checks passed;
PSScriptAnalyzer Error/Warning passed for the main script and new corpus
script; changed PowerShell/test files contain zero non-ASCII bytes;
`git diff --check` passed; and InjectionHunter 1.0.0 found 1 fixed-literal
false positive in the new script with 0 unresolved findings after
disposition-backed review.

Remaining gate: `Run-TpmQualityGate.ps1` failed closed only because
owner-runtime evidence remains outstanding and the report is newer than the
supplied source `ChangedAtUtc`. Owner-approved runtime evidence for
representative CHD-only, same-folder, content-subfolder, nested, multiple-CHD,
missing-CHD, and wrong-directory layouts remains required. No package, owner
smoke, hosted CI, push, merge, tag, publish, certification, or release-ready
action is authorized in this implementation slice.

## Engineering -- Catalog-wide game support contracts

Status: IMPLEMENTATION COMPLETE; LOCAL FOCUSED VALIDATION COMPLETE; OWNER-RUNTIME EVIDENCE REQUIRED

Slice contract: `docs/remediation/slices/TPM-GAME-SUPPORT-CONTRACTS-001.md`.

Owner report: `TPM_GAME_SUPPORT_CONTRACTS_001`. The implementation is
catalog-wide and uses the pinned TeknoParrot profile source commit
`5880e019016c5c3a0576e97a6c2a7f14bf54e3d1`. The pinned universe contains 695
GameProfiles XML files, 383 GameSetup XML files, and 693 Metadata JSON files.
GameSetup and Metadata are case-insensitive auxiliary evidence and do not
expand the profile universe.

`GameSupportContractV1` 1.1.0 remains immutable and routes through its own
validator. New generation emits static `GameSupportContractV1` 1.2.0 records
and `GameSupportContractRegistryV1` 1.2.0. Static contracts do not contain
runtime validation results or a top-level runtime automation flag. The separate
`GameSupportAssessmentV1` 1.0.0 schema and authority bind an assessment to the
immutable contract snapshot and keep presence, path, hash, privilege, launch,
and controls observations separate.

The source-only pinned run generated 695 contracts with
`AUTOMATED_SAFE=0`, `REVIEW_MANUAL=695`, `BLOCKED_UNSUPPORTED=0`, and
`UNCLASSIFIED=0`. Hummer and Hummer Extreme retain their pinned revisions,
executable rules, profile/setup/metadata hashes, and manual posture; no crash
cause, media relationship, or unverified fix is inferred.

The backend derivation audit matched 14 cxbxr profiles:
`CTHR`, `GBOS`, `HOTD3`, `OllieKing`, `or2`, `or2b`, `or2sp`, `SGC05`,
`SGC06`, `vc3`, `WMMT1`, `WMMT1J`, `WMMT2`, and `WMMT2j`. Each matching
contract declares exactly the four shared cxbxr BIOS paths:
`ic10_g24lc64.bin`, `pc20_g24lc64.bin`, `ic11_24lc024.bin`, and
`fpr21042_m29w160et.bin`. Non-cxbxr profiles do not receive these items.
Controller input APIs, mappings, and backend transport are emitted only from
source-backed parser evidence; no Fanatec support claim is emitted.

Focused Pester 6.1.0 proof passed: the combined contract, assessment, and
support-posture suites passed 32/32. The generated pinned registry was loaded
and revalidated successfully, and the generated artifact scan found zero files
outside the explicit output root.

The core regression suites also passed: `TeknoParrot-Manager.Tests.ps1`
passed 1155/1155 and `SupportPackage.Tests.ps1` passed 41/41. No production
menu, installer, repair, registration, launch, or write-capable consumer was
changed.

Direct InjectionHunter, owner-runtime proof, package identity, hosted CI,
Test-PC, wiki, push, merge, tag, publish, certification, and release-ready
actions remain outside this implementation slice and were not performed.

## External software schema 1.3 source/test slice

- Owner report ID: `TPM_GAME_SUPPORT_CONTRACTS_001`.
- Slice contract: `TPM-GAME-SUPPORT-CONTRACTS-001`.
- Scope: additive Contract/Registry 1.3 and Assessment 1.1 schemas,
  provenance normalization, source validators/generators, and focused
  permanent tests.
- Source files: the three new schemas, `scripts/TPMGameSupport.Contracts.psm1`,
  `scripts/TPMGameSupport.Assessments.psm1`,
  `scripts/New-TpmGameSupportContracts.ps1`, and
  `scripts/New-TpmSupportPostureCorpus.ps1`.
- Test files: `Tests/TPMGameSupport.Contracts.Tests.ps1`,
  `Tests/TPMGameSupport.Assessments.Tests.ps1`, and
  `Tests/SupportPostureCorpus.Tests.ps1`.
- Disposition: source/test implementation only; owner runtime evidence is not
  applicable to this schema-only handoff and remains a required future gate
  before any runtime or release consumption.
- Forbidden: product menu/install/repair/launch integration, installer
  execution, download, redistribution, EULA acceptance, package rebuild,
  commit, push, merge, tag, publish, certification, or release authorization.

## Engineering -- Slice 0 immutable current-release catalog snapshot

- Slice contract: `TPM-RELEASE-SNAPSHOT-001`.
- Owner report: `TPM_RELEASE_SNAPSHOT_001`.
- Scope: release asset/source identity, immutable catalog manifest, per-file
  SHA-256 inventory, semantic source-proof comparison, release-asset
  mutability evidence, and machine-generated old/current delta lists.
- Current stable asset: TeknoParrotUI `1.0.0.2128`, release ID `16543041`,
  asset size `153159505`, SHA-256
  `9e6a8628d365a9d7c32f1dee07f1a62799656a9fdb1b58afe863526c5cf84901`.
- Snapshot ID:
  `TPM-GAME-SUPPORT-RELEASE-1.0.0.2128-ASSET-9E6A8628`.
- Catalog counts: `925 GameProfiles`, `383 GameSetup`, `923 Metadata`,
  `2231` total catalog files.
- Source-proof commit:
  `dc998e374608abbda373bb3c236db5b26b5afca7`, tree
  `7266c43c829bfd2147247b2fae0167ec44116fc5`. This is an immutable semantic
  content proof only, not official release provenance and not a live-master
  dependency.
- The stable release asset was observed changing in place from the earlier
  `1.0.0.2127` digest and size to the current `1.0.0.2128` digest and size.
  That mutability is preserved in `asset-mutability.json`; it is not
  normalized away.
- Generated artifacts are limited to the snapshot manifest, release evidence,
  source-proof record, semantic comparison record, mutability record, and
  machine-generated delta manifest. The full binary release ZIP is not
  vendored.
- Delta counts are required to remain `695` historical, `925` current,
  `230` added, `0` removed, `38` semantic changed, and `657` semantic
  unchanged. Raw byte differences remain separately recorded.
- No catalog contract migration, product behavior change, package build,
  owner smoke, test-PC work, merge, tag, publish, certification, or release
  action is included.
- Current status: source/evidence implementation in progress; all later
  catalog and runtime slices remain blocked on Slice 0 validation and review.

## Engineering -- Slice 1 current-release GameSupport contract migration

- Slice contract: `docs/remediation/slices/TPM-S1-CURRENT-RELEASE-GAMESUPPORT-002.md`.
- Specification and invariant inventory:
  `docs/remediation/inventories/TPM-S1-GAMESUPPORT-CONTRACT-INVENTORY.md`.
- Mode boundary: `HISTORICAL_PINNED_695` preserves the historical source;
  `CURRENT_RELEASE_925` requires the accepted SnapshotId, source-proof commit,
  historical root, and delta manifest. `LEGACY_COMPATIBILITY` preserves the
  existing fixture/integrated caller behavior.
- Current binding: SnapshotId
  `TPM-GAME-SUPPORT-RELEASE-1.0.0.2128-ASSET-9E6A8628`; source-proof commit
  `dc998e374608abbda373bb3c236db5b26b5afca7`; registry schema `1.3.0`;
  925 contracts; `REVIEW_MANUAL=925`; `UNCLASSIFIED=0`.
- Current source evidence is static only. GameProfile executable declarations
  take precedence; GameSetup `GameExecutableLocation` is a fallback when the
  profile has no executable declaration; contradictory declarations produce a
  non-safe `SOURCE_EVIDENCE_CONFLICT` posture.
- The generator emits a machine-checked 230-profile added list and a 38-profile
  semantic-change matrix. The accepted 0 removed and 657 unchanged counts are
  checked against `delta.json`.
- No runtime reproduction, package, owner smoke, test-PC, hosted CI, push,
  merge, tag, publish, certification, or release action is authorized.
- Historical compatibility is a hard boundary: `HISTORICAL_PINNED_695` keeps
  the pre-Slice-1 GameProfile executable projection and does not let GameSetup
  evidence select or contradict a historical executable. `CURRENT_RELEASE_925`
  alone enables the generic resolver, including basename normalization,
  GameSetup fallback, UNKNOWN-as-non-evidence handling, and fail-closed
  contradictions.
- Governing historical compatibility requirement: complete 703-file byte
  equality, including profiles, contracts, validation, manifest, posture,
  Markdown, observations, DAT summary, and all other emitted artifacts.
  Earlier implementation-pass evidence reached zero differences under both
  engines, but final frozen revalidation remains pending.
- Historical ordering is controlled by the immutable
  `TPM-HISTORICAL-695-MANIFEST-ORDER.json` input. SchemaVersion, SnapshotId,
  source commit, declared/actual counts, exact and case-insensitive
  uniqueness, and complete coverage are validated fail-closed before rank use.
- Current-release generation was previously exercised under both PS5.1 and PS7:
  925 profiles, 230 added, 38 changed, 657 unchanged, zero `UNCLASSIFIED`, and
  zero cross-engine byte differences across 935 files. Final frozen
  revalidation remains pending.
- The accepted historical order is independently bound by SHA-256
  `b7ec88b0de487fbcdcdf697334ccbec154a0f61e8c0a24712f2e99425425f4aa` over
  the UTF-8/LF ProfileCode projection; reorder-only complete-set mutations
  fail closed before rank construction. Final frozen equality remains pending.
- Documentation screenshot gate: no current validated runtime screenshots exist.
  No mock, stale, or synthetic screenshots are permitted, so README, QuickStart,
  setup, and feature documentation updates remain blocked pending an authorized
  runtime capture/doc slice.
- Current status: static implementation and local evidence gates complete; Slice 1
  remains HOLD pending documentation screenshots and review.

## Engineering -- Historical baseline provenance re-baseline

- The legacy candidate `C:\tmp\tpm-slice1-baseline-output` remains preserved
  as corroborative content evidence. Its original creation command and exact
  provenance were not recovered from retained evidence, so it is not
  retroactively authoritative.
- No TPM product or determinism defect was demonstrated. The remediation
  addresses evidence retention and governance only.
- A durable replacement evidence record is established under
  `contracts/baselines/TPM-HISTORICAL-695/`, containing
  `baseline-provenance.json` and the complete 703-file
  `baseline-files.sha256` inventory.
- The replacement binds `HISTORICAL_PINNED_695`, generator identity, accepted
  historical source commit `5880e019016c5c3a0576e97a6c2a7f14bf54e3d1`,
  SnapshotId `TPM-HISTORICAL-695`, the accepted ordered ProfileCode digest
  `b7ec88b0de487fbcdcdf697334ccbec154a0f61e8c0a24712f2e99425425f4aa`, and
  the governed 703-file tree digest.
- Windows PowerShell 5.1 and pwsh 7.6.6 replacement generations produced
  identical 703-file inventories with zero missing, extra, or differing
  files. The replacement also matches the legacy candidate byte-for-byte;
  that result is recorded only as `CORROBORATIVE_COMPATIBILITY_WITH_LEGACY_CANDIDATE`.
- Acceptance authority remains pending the formal re-baseline review. No
  commit, package, runtime, owner smoke, test-PC, merge, tag, publish,
  certification, or release action is authorized.

## Engineering -- RC8 compact-default menu corrective slice

- Owner report: `ARC-UX-S01` (Issue #323).
- Slice contract: `TPM-MENU-COMPACT-DEFAULT-001`.
- Confirmed failure: the production script contained two `Get-ConsoleLayoutTier`
  definitions. The later legacy width-only definition overrode the compact-default
  width-and-height policy, so ordinary Windows Terminal viewports selected a
  crowded two-column layout.
- Source disposition: `SOURCE FIXED; OWNER RUNTIME NEEDED`. The corrective slice
  keeps exactly one selector, centralizes the safe wide threshold, preserves the
  constrained-height fallback, and closes the PostgreSQL workflow before normal
  menu return.
- Source/test evidence: `TeknoParrot-Manager.ps1`,
  `Tests/TeknoParrot-Manager.Tests.ps1`, and
  `scripts/Debug-TPM-MenuLayout.ps1`; focused PS7/PS5.1 menu and PostgreSQL
  return-to-menu evidence is required before final disposition.
- Runtime proof still needed: rebuild the exact package and capture the ordinary
  menu, constrained viewport, wide threshold, and PostgreSQL failure-return
  behavior on the authorized owner runtime. No test-PC runtime work is performed
  by this slice.
- Hunk mapping: `TPM-MENU-COMPACT-DEFAULT-001` / `ARC-UX-S01` /
  `TPM-TRACE-001` / `TPM-OWNER-001` through `TPM-OWNER-003`.

## ReShade gallery slider and PostgreSQL rollback/setup -- working-tree slice evidence

- ReShade mapping: owner IDs 1, 9, and 10 / PR #321 / `TPM-RESHADE-TEN-EFFECTS-001` / `TPM-RESHADE-001` / `TPM-TRACE-001` / `TPM-OWNER-001`. The actual gallery has a 0-100 TrackBar with 16 ms change coalescing and immediate keyboard updates; the terminal selection remains authoritative and synchronizes the preview in Slider mode. A local Windows PowerShell 5.1 STA smoke displayed twelve profiles, moved the slider to 30, synchronized `Vignette`, verified non-black pixels on both sides, and observed no paint diagnostics. This is source-level UI evidence only; package and owner-runtime proof remain separate.
- PostgreSQL mapping: owner row 88 / PR #321 / issue #323 / `TPM-POSTGRES-SETUP-ROLLBACK-001` / `TPM-TRACE-001` / `TPM-OWNER-001`. The confirmed source incompatibility is `dropdb --if-exists` against the PostgreSQL 8.3.23 documented CLI; setup rollback has one owner and drops only after successful `createdb` ownership evidence. Restore receipts now record `CreateOwnedForRollback` only after successful `createdb.exe`; rollback does not drop a present database without that ownership evidence. A failing absent-prestate collision regression reproduced the pre-fix `ROLLED_BACK_VERIFIED` result, then passed with zero `dropdb.exe` calls and `ACTION_REQUIRED`/`UNKNOWN`; an existing-prestate collision also preserves the appeared database after one original drop. Multi-item restore rollback refreshes retained receipts after rollback and classifies unverified items as `UNKNOWN`, not `COMPLETED`; regressions cover stale receipts and disjoint terminal sets. A forced final receipt-refresh failure regression verifies that `ReceiptPath` is cleared, `ReceiptError` is visible, the root remains as residue, cleanup is incomplete, and the result validates as `CLEANUP_RESIDUE`. Collision and receipt-failure tests passed 5/5 under PS5.1 and PS7 with Pester 5.7.1. Full-suite, static, procedure-gate, and independent-review results are recorded in the reconciliation report; package and owner-runtime proof remain separate blocking gates.
- Owner packet evidence is profile-file-level only: corrected impact JSON SHA-256 `42B9554AB7DFFFC9465B5F8FA9B0BC57D63943310D63B4C622F5E630E493C31D`, time-of-day `18:46:04.1230563` only, baseline SHA-256 `02DEA729E19CB9D64CDED338B2FC72CDE28AF78CC17209B28F9BF0E068518322`; GameProfiles 969 files / 7,574,923 bytes and UserProfiles 8,698 files / 297,810,587 bytes, zero file adds/removes/changes. `DatabaseCatalogVerified=false`; database state remains UNKNOWN. No unchanged-database claim is supported.
- No release ZIP was built, changed, or release-validated; no owner-runtime or database action, merge, tag, publication, certification, or release action was performed. The pre-existing untracked staging tree was deleted and content-reconstructed from the exact source archive, authoritative release allowlist, and unchanged failed ZIP; the reconciliation report records the 355-file outer and payload comparisons and the unrecoverable metadata/unrecorded-content limits.

## Final PR #321 source-quality gate -- 2026-10-04

- Timed `Run-TpmQualityGate.ps1` passed on the source/test contents of commit `4f219a504018f98e816c716424bc5da4928a7cc8` before this report-only evidence amendment: Started `2026-10-04T00:22:22.8702405Z`; finished `2026-10-04T00:33:26.5048085Z`; PowerShell 7.6.6 / Pester 5.7.1; exit 0.
- Results: main Pester 1311/1311; SupportPackage 42/42; ASCII/parse, configured PSScriptAnalyzer, `git diff --check`, and permanent procedure gate passed. This source gate does not validate the candidate ZIP or owner-runtime state.
## Issue #351 isolated required-patch review slice -- in progress

- Slice contract: `TPM-REQUIRED-PATCHES-REVIEW-001`; procedure mapping:
  `TPM-TRACE-001`, `TPM-EVIDENCE-001`, `TPM-UX-001`, and `TPM-TRUTH-001`.
- Review base: PR #321 head `9a9ac19`; local branch
  `review/rc8-required-patches-20261015`. The original source worktree and
  its candidate artifacts remain preserved.
- Scope: integrate the verified 13-entry/12-build required-patch catalog with
  the exact RC8 runtime fixes needed by the candidate. Audit all ten commits
  from the review base to source HEAD `18e82a7`; do not carry their history or
  unrelated private material.
- Hunk mapping: application/runtime and menu integration; engine/catalog and
  release allowlist; focused and affected tests; user/engineering docs and
  remediation evidence -> Issue #351 / `TPM-REQUIRED-PATCHES-REVIEW-001` /
  the procedures above. PR #321 owner-report statuses are unchanged.
- Current evidence: focused recipe Describe passed 13/13 under PS7.6.7 at
  `2026-10-15T04:01:56Z`--`2026-10-15T04:03:24Z`; the PS5.1.26100.9549 run
  passed 13/13 at `2026-10-15T03:58:15Z`--`2026-10-15T03:59:15Z` on the
  pre-contract-list test hash. PS5.1 parsed 11 changed PowerShell files with
  zero errors, main ASCII count 0, configured PSScriptAnalyzer 1.25.0 returned
  0 findings, and canonical InjectionHunter 1.0.0 reported 41 findings / 0
  unresolved. Receipts and exact input hashes are in the local evidence
  manifest; they are not copied into the branch.
- Independent final-input boundary review at `2026-10-15T04:10:09.8954275Z`
  compared 47 frozen source/test/gate/report inputs; only this control board
  and the reconciliation report had changed. The other 45 inputs remained
  unchanged. This is an input-boundary check, not a test result.
- Canonical `Run-TpmQualityGate.ps1` completed in PowerShell 7.6.7 with pinned
  Pester 5.7.1, `2026-10-15T04:07:02.6595596Z`--`2026-10-15T04:28:24.3139677Z`,
  exit 0: Main 1,484/1,484 and Support 42/42 passed; zero failures/skips.
  ASCII/parse, configured PSScriptAnalyzer, `git diff --check`, and the
  permanent-procedure gate passed. Original records:
  `Isolated-Review-Canonical-20261015T0407Z.raw.txt` (SHA-256
  `2ED1A4D0146CBE4AFFE69048EDCE8464A39A3855F5F1E9F1814D87001B3A099D`) and
  `.stdout.txt` (SHA-256
  `7CF7657F0986F9EBAC8D8936D083E6A644188B7755DBF6B2F686FD7BCD7F0339`).
- That gate covered the frozen 47-input candidate before the catalog EOL and
  CI pull-request branch-filter metadata fixes. Their checkout round-trip and
  exact workflow diff are validated separately; runtime, catalog, and tests
  remain unchanged.
- Limits: independent review and GitHub handoff follow required checks. No
  commit, push, PR creation, merge, tag, publication, live install,
  game/collection/DAT or database mutation, test-PC execution, or owner-runtime
  acceptance is claimed.
## Issue #351 Taisen driver follow-up -- integration in progress

- Slice contract: `TPM-REQUIRED-PATCHES-DRIVERS-001`; owner report:
  `DRIVERS-LANE-RC8`; procedures: `TPM-TRACE-001`, `TPM-EVIDENCE-001`,
  `TPM-TRUTH-001`, and `TPM-OWNER-001`.
- This is a follow-up to the historical PR #353 13-entry/12-build candidate;
  that earlier gate record remains unchanged. The current local integration
  branch is based on `046a114`. Its six-file frozen driver-lane snapshot and
  manifest are present under `docs/remediation/recipe-lanes/drivers/`.
- The full-guide driver lane identified three exact-build, absent-only Taisen
  Hot Gimmick 5 (2.04) Main-source restorations: `TTX-Monitor.dll`,
  `TTX-Config.exe`, and `TTX-Loader.exe`. Each is pinned to the exact
  `game.exe` SHA-256 and its own source-member SHA-256. Operator key setup and
  loader use remain separate; no generated monitor configuration, payload
  execution, game launch, or gameplay is included.
- Hunk mapping before implementation: central catalog entries, the existing
  isolated single-file recipe test ID list, frozen driver-lane evidence, and
  this follow-up contract/report -> Issue #351 / `DRIVERS-LANE-RC8` /
  `TPM-REQUIRED-PATCHES-DRIVERS-001` / the procedures above.
- Status at opening: source integration and focused current-catalog proof are
  pending. Driver-lane synthetic production-engine checks passed under both
  PowerShell engines before integration; those lane receipts do not replace
  the central-catalog test or owner/runtime acceptance.
- Limits: Dragon Dance and Primevil remain held by the driver lane. Owner
  configuration, hardware, gameplay, package acceptance, test-PC, and release
  status are not established by this source-only slice.
## Issue #351 managed-plugin follow-up -- integration pending

- Slice contract: `TPM-REQUIRED-PATCHES-PLUGIN-INTEGRATION-001`; lane
  evidence contract: `TPM-REQUIRED-PATCH-PLUGINS-20261015`; procedures:
  `TPM-TRACE-001`, `TPM-EVIDENCE-001`, `TPM-UX-001`, and `TPM-TRUTH-001`.
- The frozen lane contributes only two recipe `Entries`: exact-build
  Mars Sortie 1.46.9 and the separate Rabbids Hollywood operator plugin.
  Its `Census`, base-catalog metadata, and fragment-level fields are not
  central-catalog entries. The Rabbids operator assembly remains distinct
  from the existing trigger/crosshairs assembly recipe.
- Hunk mapping before implementation: two managed-plugin catalog entries,
  the central exact-metadata/lifecycle tests, and the `UserSelected` local
  ZIP source-selection label/prompt -> Issue #351 / plugin lane contract /
  `TPM-REQUIRED-PATCHES-PLUGIN-INTEGRATION-001` / the procedures above.
- The lane reports six focused synthetic Pester tests passed under PS7 and
  Windows PowerShell 5.1 with Pester 5.7.1. Central-catalog integration and
  the selected-source prompt correction remain pending; lane receipts do not
  establish owner/runtime behavior.
- Limits: the exact BepInEx core prerequisite is checked but not installed;
  no plugin is executed. SB3 remains held on exact official profile/build
  binding. No owner install, gameplay, package, or release status is inferred.
## Issue #351 native single-file follow-up -- integration ready

- Slice contract: `TPM-REQUIRED-PATCHES-NATIVE-001`; source
  fragment: `Native-SingleFile-Batch-20261015-v2`; procedures:
  `TPM-TRACE-001`, `TPM-EVIDENCE-001`, `TPM-TRUTH-001`, and
  `TPM-OWNER-001`.
- The corrected v2 patch is restricted to `scripts/TpmRequiredPatchEngine.ps1`
  and `Tests/TeknoParrot-Manager.Tests.ps1`, SHA-256
  `61F20333518AE8231BEBC187A06A6F9349C982CA67FC567DD679C74AA6611C98`.
  Its disposable apply proof against `046a114` exited 0 and matched the
  tested engine `DEAC3B66DA44EEEC357223D4940A4AB7BE54259535FD6DBF72ECDCB1FD67B2EC`
  and test file `D01818CFE60F3E969B25B7278C31150B2E1C2DDB2A586651A4ABF65083D6B647`.
- The five-entry fragment contains AMD/NVIDIA shader replacements for exact
  Cross Raid 1.05 and VF5R 1.001 builds plus one exact Sonic Dash Extreme
  executable replacement. The Sonic opt-in is constrained to one
  `ReplaceFile` on the declared executable, exact original before hash, exact
  after hash, transaction-time object identity, and receipt-bound undo. The
  three hardware variants remain exact-build and mutually exclusive.
- Integration sequence: current local catalog has the three Taisen entries;
  add only the two frozen plugin entries and these five native entries, then
  set the native test's old 18-entry expectation to the final verified
  aggregate count. The one full canonical quality gate is reserved for the
  frozen aggregate; no intermediate 16/18-entry full suite is authorized.
- Hunk mapping: five recipe entries, narrow engine self-executable safeguards,
  native catalog/transaction tests, and this slice/report -> Issue #351 /
  native v2 / `TPM-REQUIRED-PATCHES-NATIVE-001` / procedures
  above.
- Owner/runtime limits: no binary execution, game launch, owner hardware or
  gameplay acceptance, test-PC, package, or release result is claimed.

## Issue #351 -- frozen expanded 24-entry review batch (historical checkpoint)

- Historical status: `SOURCE FIXED; OWNER RUNTIME NEEDED`. This frozen24
  checkpoint remains separate evidence; the current candidate staging catalog
  is the authorized 56-entry expansion recorded below. Preserve its earlier
  integration-pending driver/native/plugin notes and 13-entry PR353 gate record.
- Review base `b5d6bc568513e1263ab891041083d5083bb4da70`; 24 recipes / 18 exact identities, 16 CreateFile / eight ReplaceFile. The baseline 13 entries and Main bytes are preserved. Detailed hashes, receipt limitations and hunk mappings are in the current reconciliation checkpoint.
- Raw focused results are 25/25 under each engine with Pester 5.7.1; the helper result-capture exit was 1. Independent aggregate and engine reviews found no confirmed defect. Fresh canonical, broader regression, static and package gates are pending.
- Current full-guide ledger remains explicitly mechanical; curated subset 19 implemented / one partial / 43 held / 32 separate non-patch references. Further recipes continue independently and do not delay this verified batch's gate/push milestone.
- Exclude the additional Cross Raid base-restoration proposal: vendor undo composition is unresolved. Frozen24 has no CreateFile-to-ReplaceFile same-target overlap. No receipt or exclusive-group guard is weakened.
- Owner setup, GUI, controls, launch/gameplay, Procedure A/B and test-PC #323 are not passed. Preserve delivered owner ZIPs. PR321 remains draft/HOLD; no release/tag/main merge.

### Expanded24 review publication gate

Canonical Main 1,488/1,488 and Support 42/42 passed with Pester 5.7.1 on PowerShell 7.6.7; permanent gate passed, exit 0, completed 2026-10-15T06:51:18Z. All 559 frozen inputs were unchanged. Both static engines and InjectionHunter are green as recorded in the reconciliation. The separate 37-file regression run was incomplete and restarted with a distinct receipt; its result and exact-head CI remain pending. Review publication may proceed; integration, owner-package readiness and runtime acceptance remain held. PR321 remains draft/HOLD.

## Issue #351 -- authorized 56-entry staging expansion

- Current staging state: 56 exact recipes across 21 ProfileId/build/executable
  identities; 48 CreateFile and eight ReplaceFile operations. The first 24
  catalog entries retain their exact order and semantic content. The catalog
  SHA-256 is `799524EC69C5F669415D07D88D913258EA8AA922AF78416BDB0D1B9228BE3AE1`;
  the engine SHA-256 is `914FFBBC25C770F1319FE22381185187CF2832CFDBF44AF9C0A16925179E18F3`.
- Staging source is exact base `3c93d383f0a8091bf5d6890acb176c285816a82f`,
  branch `review/rc8-expanded54-20261015`. No commit, push, merge, release, or
  package is authorized. Root will transplant to its approved integration base.
- Native contribution: 30 absent-only Main-component restorations (14 Hummer,
  14 Hummer Extreme, two Primeval Hunt). Frozen fragment SHA-256
  `54AB378F9F13213F67C47A628DDEFE3AA0F4FEB8BE2E1BCE51B87818E247D38E`;
  standalone test SHA-256
  `673D1C434033E1076CA4BE6174D535B5A1C0353651B9EA6D1B63EEF3340C88C7`.
- SB3 FMOD contribution: two independent absent-only Main component restores.
  Frozen fragment SHA-256
  `0CC045CB454D802804E46FC25F049687164F48E55ACACFC3D38BA63AB528E418`;
  standalone test SHA-256
  `D288325EB8BAD7D13C80499EB3E45091E99BBB89AA0E09C825C1692B5611FA05`;
  accepted boundary note SHA-256
  `EA90F3C8E4EF90061D34E350E65275CCC1557CC49AF7DCF2450A825CDAA2E7A4`.
- No engine behavior change: only the catalog pin moved from the 24-entry hash
  `283DB40B0A17F3FEF2BC758D8123209B87C07731E433CECFE96DE1E2C69C5CE8` to
  the 56-entry hash above. Central count/ID assertions and explicit CI paths
  include both accepted standalone suites.
- Mapping: Main entries -> `TPM-REQUIRED-PATCHES-MAIN-COMPONENTS-001` and
  its inventory; SB3 FMOD entries -> `TPM-REQUIRED-PATCHES-SB3-FMOD-001` and
  its inventory; all -> Issue #351 and procedures `TPM-TRACE-001`,
  `TPM-EVIDENCE-001`, `TPM-TRUTH-001`, `TPM-OWNER-001/002/003`; user wording
  -> `TPM-UX-001/002`. No numbered PR #321 owner row is assigned.
- Main limits remain: no Hummer Extreme frame-count result, Primeval Hunt
  `ElfLdr2` copy-identity result, modern NVIDIA fog resolution, shader-set
  atomicity, game compatibility, or gameplay proof. SB3 FMOD is not an atomic
  pair; installed DLL version, pair compatibility, and full setup are unknown.
- Tests use synthetic payloads/archives only; no game, executable, DLL, or
  source payload was run. Owner runtime, controls, launch/gameplay, and release
  acceptance remain pending.
- Sequencing note: the authorized catalog integration was applied before the
  two new issue-specific slice contracts and inventories were authored. This
  does not satisfy the repository's preferred pre-change contract ordering;
  the documents now map the exact staged hunks. Root review disposition is
  required before any broader integration gate.
- Focused integrated-catalog tests and bounded static checks: pending at this
  update. Do not treat this staging record as a full canonical gate or release
  result.

## Issue #351 -- current 58-entry staging handoff

This records the current staging state; the preceding 56-entry section is the
historical integration checkpoint and its test receipts remain unchanged.

- Current catalog: 58 exact recipes across 22 ProfileId/build/executable
  identities; 50 CreateFile and eight ReplaceFile operations. Catalog SHA-256
  `F86F09A8BD2749DC9C4531CD1D00A69BF07D85B14A8D281D33767732ED5B720A`;
  engine SHA-256 `7AFAE497F5EFED0BE5F94497D4A7A5C25C073743485B700A7498B1A34681F6E4`
  (catalog-pin change only; no engine behavior change).
- The current delta is the separately accepted Infinity Blade FX 1.02 pair:
  two absent-only Main component restorations with presence-only prerequisites.
  No automatic rename, TPFIX.ini edit, first-launch path selection, component
  version/pair compatibility, complete setup, or gameplay claim is made.
- Historical 56-entry focused checkpoint: PS7 and PS5.1 each passed 161
  selected tests (native 152, FMOD 2, central aggregate 1, plugin 6), zero
  failures/skips, input changes 0. Terminal result hashes:
  PS7 `DBA18C7FE194475456DB2D88D2F1B8B7C9A4A68D5D4B28B3A1BCC199FC862978`;
  PS5.1 `78FE33AE4148D712C3408720ACF74CAFFF859652364A2B188A556840D79FE952`.
- Current 58-entry v3 delta verification: PS7 completed
  `2026-10-15T08:16:41.7586051Z`; PS5.1 completed
  `2026-10-15T08:17:17.1661187Z`. Each passed Infinity 2/2 plus central
  aggregate 1/1, zero failures/skips, input changes 0; 1,487 central tests
  were not run by the intentional name filter. Results:
  PS7 `D60CBE0CDA3F11B54AB99AAF9384DB3B603F9C4515576C6FCFB095B4537A6C63`;
  PS5.1 `8B718B8116A7DC0EF69AB42F5DD0EA5733DB4B73831BDD2BD5547804D3D53426`.
- Current input hashes, full raw-result hashes, frozen source-fragment
  identities, and byte-preservation evidence are recorded in
  `PR-321-reconciliation.md`. The 152-case native suite and FMOD suite were
  not rerun on the 58-entry catalog.
- This lane did not run full canonical suites or commit/push. Root owns final
  canonical/static/security gates and any authorized source publication after
  those gates. Exact-head CI, owner-runtime acceptance, integration, and
  release readiness remain pending.

## Issue #351 current 58-entry focused checkpoint -- 2026-10-15T08:22:06Z

- Current staging: 58 recipes / 22 exact ProfileId-build-executable identities, 50 CreateFile / 8 ReplaceFile. The original 24 entries are preserved; the 34 additions are 30 native Main components, two SB3 FMOD components, and two Infinity Blade FX Main components.
- Catalog SHA-256: F86F09A8BD2749DC9C4531CD1D00A69BF07D85B14A8D281D33767732ED5B720A. Engine SHA-256: 7AFAE497F5EFED0BE5F94497D4A7A5C25C073743485B700A7498B1A34681F6E4; engine body is unchanged, only its catalog pin differs from the 24-entry base.
- Pester 5.7.1 final focused delta: PowerShell 7 completed 08:16:41 UTC and Windows PowerShell 5.1 completed 08:17:17 UTC on 2026-10-15. Each passed the two Infinity lifecycle/metadata cases and one central aggregate case: 3 passed, 0 failed, 0 skipped; 1487 other Main tests were intentionally not run. InputChangedCount was zero.
- PS7 receipt SHA-256: D60CBE0CDA3F11B54AB99AAF9384DB3B603F9C4515576C6FCFB095B4537A6C63. PS5.1 receipt SHA-256: 8B718B8116A7DC0EF69AB42F5DD0EA5733DB4B73831BDD2BD5547804D3D53426. Both distinct v3 receipts are retained externally. Earlier failed sort-order assertion receipt is preserved; v2 predates the exact-case membership refinement.
- The earlier 56-entry focused run remains historical: 161 selected passes per engine (native152, FMOD2, aggregate1, plugin6); it is not a full Main or canonical result and is not relabeled as a 58-entry run.
- Post-document test-input identity audit at 2026-10-15T08:22:06Z: every final v3 input hash matches the current source/test files. Documentation changes do not change those tested inputs.
- Infinity prerequisite checks establish file presence only, not contents, versions, setup completeness, compatibility, or gameplay. All new Main-component repairs are independent absent-only operations, not atomic installation bundles.
- Full canonical/static/InjectionHunter/CI gates for this candidate remain pending root execution. Owner GUI, controls, launch, gameplay, and full test-PC runtime acceptance remain unverified. No release, tag, main merge, or runtime acceptance is claimed.
## Issue #351 -- 58-entry canonical gate checkpoint

- Expanded58 RDC capture SHA-256 `AC8E42B5F54ACDDBB0AE8522473C40C9D8D61E967799E9BD3C6420AA94CEB659` preserves 846 original child-output lines plus capture metadata. Child results: Main Pester 5.7.1 passed 1,488/1,488; Support Pester 5.7.1 passed 42/42; permanent procedure gate passed; `TPM quality gate passed.` Static receipts also pass on PS5.1 and PS7; InjectionHunter has 41 findings, zero unresolved, exit 0.
- The outer PS5.1 launcher transcript `Expanded58-Canonical-20261015.raw.txt` SHA-256 `7343EB57B40C801054C7E937818FA9ABFC7F3B0902A92F77EEC5625BD4F2123E` ends with exit 1. The observed failure is a `NativeCommandError` from expected negative-test stderr after the child output completed. The outer wrapper did not capture the child's exit code; do not infer it from the gate's printed pass line.
- Root's stock-PS5.1 transport proof (`Expanded58-Wrapper-Diagnosis-Root-20261015.json`, external SHA-256 `D07BE1D70FBFCD12843DF7D255D150E0CCDC262B0CDA853CEE6E31E758ECEC1C`) records original wrapper exit 1 for child exit 0 plus stderr, while the helper preserved exits 0 and 7 and both streams. Product change false; the historical canonical child exit remains unknown.
- Static PS5.1 receipt SHA-256 `1810A1CD96CD5273E3D033D19393FB003A020578681F02014058E92DE1F426C3`; static PS7 receipt SHA-256 `CE97A4B1957B10B048260E0FE161F6B64B00C1672FE27CA6B56B99AF62DF61D8`. Both recorded zero product parse errors/non-ASCII bytes and zero configured analyzer findings.
- InjectionHunter PS7 receipt SHA-256 `7401BEF5AC4F5052224DA4F8A55539C037EEB4CB97B9A13CAA533B65A0F75F20`: 41 findings, zero unresolved, process exit 0. Findings were individually dispositioned in the receipt.
- Product and test inputs remained frozen at the 58-entry handoff hashes. The 572-file gate input-boundary receipt SHA-256 is `3953A6715FC11664A8215CE2C8C2405BBE3D183275DDB694B7AD22245C072D25`. A post-document identity audit and permanent-procedure-gate rerun are required before final diff/status review.
- Existing holds remain: owner runtime and gameplay are unverified; Hummer Extreme frame-count, Primeval Hunt ElfLdr2 identity, NVIDIA fog behavior and shader-set atomicity remain unresolved; SB3 FMOD installed-version/pair compatibility/full setup remain unverified; Infinity Blade FX prerequisites establish file presence only. No release, tag, merge, or source publication is claimed by this staging lane.


## 58-entry post-document identity and permanent-gate recheck

- Post-document audit at `2026-10-15T09:02:20.7139906Z` matched all 11 frozen product/focused-test input hashes with zero mismatches. External receipt `Expanded58-PostDoc-Source-Identity-Audit-20261015.json`, SHA-256 `31B07AFE5F19EED13F3F3CD37FFA8DD632B354BB5CC2228B2B81E1D5AEB25660`.
- Standalone `Test-TpmPermanentProcedures.ps1` rerun completed `2026-10-15T09:02:30.0366625Z`, exit 0, `Permanent procedure gate passed.` This was the permanent gate only; no full suites were rerun. External receipt `Expanded58-Permanent-Gate-Only-PostDoc-20261015.json`, SHA-256 `777B82DCF6CB090E780C1F024C6D7654C774E1CA12DE87C790D169F0A205B7E7`; raw output SHA-256 `BE5D31B73205724FD74E851BE38FC3C683409847DDD4BCF1704D36132742ED35`.
## Issue #351 -- isolated 61-entry follow-up checkpoint

- Worktree: branch `review/rc8-three-component-followup-20261015`, based on
  `1447d2d8da2843748157e700df227b6b51b49983`. No commit, push, PR, release,
  or change to the 58-entry parent tree is claimed.
- Candidate catalog: 61 unique recipes / 23 exact ProfileId-build-executable
  identities / 53 `CreateFile` / 8 `ReplaceFile`. Catalog SHA-256
  `87DF31451B267F89FCD2CB3E3DEA1860972EDD4C7601ACE1998E80BD7E4CAD9E`;
  engine SHA-256
  `1DFDE54B9A11D0A54D6A7308E892D1D397D156B8A2C731FBB56D3E175CC14409`
  (only the catalog pin differs from the 58-entry engine).
- The three independent Main-source candidates are MaiMai GreeN
  `freeglut.dll`, MaiMai GreeN `libcurl.dll`, and Rabbids Hollywood
  `RabbidsHollywood_Operator.exe`. Exact guide `ArrayIndex` and separate
  `SourcePath` values are recorded in the corrected boundary note. The
  Rabbids utility is distinct from its Assembly-CSharp and BepInEx operator
  plugin recipes; it is not executed or used to edit registry/`.conf` state.
  The MaiMai transactions are separate, not atomic. Existing targets are
  absent-only; no installed target was inspected.
- Frozen delta SHA-256 `F08213A3D435E6318825412ECC923BDD15EB6ECA9D01BC78119FAC54C5C6C1FD`;
  focused test SHA-256
  `AC8ACD646ABDD4576ECDFF1D38535D1367C02737216384AF60DE7A7EF27D2669`.
  Manager aggregate-test SHA-256
  `AA164AA350A6CED091D88CA6EAC77821D6DB6474A7CB87E23EB59360A8EC6B92`;
  plugin-lane test SHA-256
  `13BEEF92E991D7141B1BB55D2BF487B8980832011DE6F2B3E421E2616D36B75F`.
- Corrected focused Pester 5.7.1 receipt on PowerShell 7.6.7 ended
  `2026-10-15T09:34:35.3112992Z`: 13 selected passed / 0 failed / 0 skipped /
  0 inconclusive; Main selection 5 passed with 1,483 of 1,488 tests not run,
  existing plugin lane 6 passed, new Main-extra suite 2 passed. External
  transcript `ThreeRecipe-PS7-Pester571-20261015T093224Z.txt`, SHA-256
  `B8982B68EFD4A31525ED27ACB2295E40285410785991AF9328CD8A8120786C39`.
- Windows PowerShell 5.1.26100.9549 / Pester 5.7.1 ended
  `2026-10-15T09:38:35.6923290Z`: same 13 selected passed / 0 failed /
  0 skipped / 0 inconclusive; Main 5 selected, 1,483 not run; plugin lane
  6; Main-extra suite 2. External transcript
  `ThreeRecipe-PS51-Pester571-20261015T093650Z.txt`, SHA-256
  `BB93047C80A1D9BA239F5BCACCE684C2C08A63FB31F8323093F36BEBAFCD85DD`.
- The first PS7 transcript is preserved as diagnostic, not a product/test
  failure: its 13 selected tests all passed, but the runner compared 13 passes
  against Pester's 1,488 discovered count (including 1,483 not-run tests) and
  returned 1. It is superseded by the corrected PS7 receipt above.
  Diagnostic transcript SHA-256
  `F48FF050A3BA0B18D995E37D1BDF3DE296443B608B6B602259461141FB0F9C80`.
- Fresh exact ZIP-member proof `MaiMai-Rabbids-Main-Exact-Member-Proof-20261015T092737Z.json`,
  SHA-256 `F19F55F9534AF82EEF679953543FA4DCBDEA795F0053CEFB05A3915DB858F05C`,
  records one exact central-directory occurrence for each source component and
  setup executable, ZIP method 8, sizes, and SHA-1/SHA-256. Corrected private
  guide/source binding receipt `ManagedGuide-Main-Component-Restore-Proof-20261015T092737Z-v3.json`,
  SHA-256 `7F912B203320D1B4BB0DBE7037DD38DFA6DEEF45E23E5480CA48647497047ACD`.
  No whole-archive hash, extraction, execution, or live target access.
- No full Main, Support, canonical, release, or owner-runtime gate was run in
  this follow-up. Owner install, setup readiness, launch, controls, and
  gameplay remain unverified. No release or publication claim.
## Issue #351 Cross Raid receipt-composition defect -- isolated follow-up

- Slice/invariant contracts: `TPM-CROSSRAID-COMPOSITION-001` and
  `TPM-CROSSRAID-COMPOSITION-INVARIANTS-001`; owner boundary: no numbered
  PR #321 report row is assigned.
- Implemented only in isolated receipt-validation code. `Test-TpmMultiPatchReceiptChain` is reachable through the exclusive-gate path and accepts a single-operation CreateFile predecessor only when one exact single-operation ReplaceFile chain validates profile/root/catalog/target, SHA-256 and object-identity edges, retained backups, and restored terminal checkpoints. The bounded census caps 256 directories, 262,144 bytes per receipt, and 16 MiB total; it rechecks directory membership and all receipt hashes and reopens the target before accepting the leaf. Multi-operation chain shapes fail closed. Own-undo object identity and unrelated live receipt guards remain active.
- The retained pre-fix PS7 characterization passed 5/7 and failed both vendor-undo cases; that exact characterization was not run on PS5.1. The expanded 18-case focused suite now passes 18/18 on PowerShell 7.6.7/Pester 5.7.1 and Windows PowerShell 5.1.26100.9549/Pester 5.7.1. It covers AMD/NVIDIA Apply -> vendor Undo -> base Undo refusal on new object identity -> new vendor transaction -> Undo; ambiguity, missing/corrupt/cyclic witnesses, census bounds, root snapshot binding, direct structural-mode refusal, unrelated target tampering, Prepared, backup/checkpoint tamper, foreign same-byte identity, hardware/same-group guards, and legacy schema-2 catalog/schema-1 receipt undo.
- The Cross Raid base shader recipe remains held and excluded from the catalog. Full Main, SupportPackage and all seven required-patch suites passed 1714/1714 on each engine with actual child exit 0, ending 2026-10-15T12:03:33Z (PS7) and 2026-10-15T12:01:43Z (PS5.1). Static checks passed on both engines; canonical InjectionHunter 41 findings, 0 unresolved, actual exit 0. Permanent procedure gate passed 2026-10-15T12:05:48Z with explicit source freshness. All 580 inputs were unchanged during verification. Final evidence-only corrections require a post-document identity audit and freshness gate before the newly authorized scoped commit/push/exact-head CI/integration. No gameplay, owner-runtime, package, release, main-merge or recipe-promotion claim.
## Issue #351 Cross Raid 1.05 Ver A base-shader candidate -- mapped before catalog edit

- New slice: `TPM-REQUIRED-PATCH-CROSSRAID-BASE-001`; invariant inventory:
  `TPM-REQUIRED-PATCH-CROSSRAID-BASE-INVENTORY-001`. No numbered PR #321 owner
  row is assigned.
- Worktree is the separate branch `feature/rc8-crossraid-base62-20261015`,
  based on `cc307092553397c8eb56543e9cb4db1219fb73ef`. This is a new 62nd
  recipe candidate; the source catalog remains unchanged at 61 entries /
  23 identities / 53 `CreateFile` / eight `ReplaceFile` pending the mapped
  contract and focused integration.
- Exact scope is one absent-only Main `CreateFile` restoring
  `rom/shader.farc` for Cross Raid 1.05 Ver A. Source/executable pins and the
  exclusion of the older unversioned RAR are recorded in the slice and
  inventory. No hardware predicate or gameplay claim is added.
- Before catalog changes, the frozen seven-case portable held suite passed
  7/7 under Pester 5.7.1 on PowerShell 7.6.7 and Windows PowerShell
  5.1.26100.9549; each child exited 0, with zero failures/skips and seven
  NUnit XML cases. External baseline result receipt SHA-256
  `4EB6A909B904C16B3FC67EC936481287506F1752EF7BB9B7EEAA80B9D293EFBC`;
  source-boundary receipt SHA-256
  `D36A6008ACF7E8ED6B2CF63AEFC0D3961469D99E143A6DCDE84478CDAEF6A0E7`.
- Frozen source suite and recipe inputs remained at SHA-256
  `1FE514FAFE3C2502E5EDF1C1D6E9A52B24AC3ED6D8D9368A5EEA4817E250C8EF`
  and `D65EDF8468DBABD0EC16E2B88EE1257DD985D766D88685D73855086007A3A29C`.
  The 61-entry catalog, required-patch engine, and manager source match the
  base commit blobs; no product input was changed for the baseline run.
- No full Main, Support, canonical, packaging, or runtime test was run for
  this candidate. Owner runtime, visual compatibility, setup completeness,
  gameplay, release, and owner acceptance remain unverified.
## Issue #351 Cross Raid 1.05 Ver A base-shader candidate -- focused result

- The isolated catalog now contains 62 entries, 23 exact profile/build/executable identities, 54 `CreateFile` operations, and eight `ReplaceFile` operations. The new entry restores only the exact Main `rom/shader.farc` when absent.
- The required-patch engine diff is limited to its catalog SHA-256 pin line; `TeknoParrot-Manager.ps1` remains byte-identical to base `cc307092553397c8eb56543e9cb4db1219fb73ef`.
- The repo-relative standalone suite passed 7/7 with Pester 5.7.1 on PowerShell 7.6.7 and Windows PowerShell 5.1.26100.9549; both child processes exited 0 with no failures or skips. The targeted central catalog identity test passed 1/1 on each engine; 1,487 other central tests were intentionally filtered out.
- Final focused receipt SHA-256: `7706F6AA6D23869A400D08A9D033B4E36B80E00F2DD713F3A6C41AAD36778642`. Standalone NUnit XML SHA-256 values: PS7 `E20BC373378F79C825CCD3121407E4FD968F7AB7D50DCA8967B1F829FFD817C6`; PS5.1 `4C1EDC6FF24D65A5315A0098F7BC46360813F1E476DD37C0609A005A996A6BB8`. Central filtered XML: PS7 `6256138544F7310AD6A8D121DA12ADF6BDC2771950D30F688A0B4BBCE7D3948B`; PS5.1 `91D06F9E70C34851D2C7BE5B355A204639744741E0F29FAF468C8EEFD3F71507`.
- Full Main/Support/canonical suites, remaining lane gates, packaging, owner-runtime testing, gameplay, release, and owner acceptance remain outside this isolated staging result. The requested current summaries are synchronized in `README.md`, `TeknoParrot-Manager-README.txt`, `TeknoParrot-Manager-QuickStart.txt`, `TeknoParrot-Manager-CHANGELOG.txt`, `QUICKSTART.md`, `ARCHITECTURE.md`, and `docs/wiki-updates/Quick-Start.md`; no live wiki write occurred.

## Issue #351 -- user release-package allowlist / ECVF runtime boundary

- Slice: `TPM-RELEASE-PACKAGE-CLEANLINESS-001`; paired
  `TPM-RELEASE-PACKAGE-ALLOWLIST-001`. Isolated branch
  `fix/rc8-package-layout-20261015`, based on `b9ac73b2fbae847c1e385a19e66c4fe8fad515a6`.
- Owner ask: exact minimal user ZIP allowlist; reject unknown archive content;
  preserve maintainer source; make the PCSx2x6 runtime contract work from a
  private extracted package without shipping narrative Markdown or schemas.
- Verified baseline: `Tests/Test-ReleasePackage.ps1` requires a subset and
  rejects selected names, not every unknown entry. Its old list ships the
  menu diagnostic, schema JSON, and evidence/experiment Markdown. The 321
  source crosshair files are exactly `000.png` through `320.png`.
- Verified ECVF path: Main and certification modules load the registered contract.
  Source registry validation is explicitly selected by source/certification
  callers and resolves every `EvidenceReferences` locator to actual Markdown
  bytes and headings. Packaged Main always selects Runtime: it validates the
  raw contract SHA-256 and strict index mappings without claiming omitted
  Markdown was read. Observation collection uses the selected mode. JSON
  schemas are not runtime-loaded; inline PowerShell validators remain
  authoritative.
- Mapped runtime boundary: retain `contract.json` and add a deterministic
  evidence index under `scripts/resources/contracts/pcsx2x6/`; maintainer
  contract, narratives, schemas and snapshots remain under source
  `contracts/`. Source/build validation requires the actual maintainer docs,
  hashes their bytes, resolves headings and byte-compares the computed index
  to the packaged projection. Runtime separately checks raw contract SHA-256,
  index shape, and exact unique EvidenceId/locator/file/heading mappings; it
  does not claim to verify omitted Markdown bytes or unsigned authenticity.
- Main never falls back to source contracts when packaged resources are absent;
  that path returns Unknown.
- The menu diagnostic is called by the certification smoke harness, not Main
  runtime; retain it in source and exclude it from the user ZIP.
- Planned product/test files: `Tests/Test-ReleasePackage.ps1`,
  `scripts/TPMCertification.Contracts.psm1`, `TeknoParrot-Manager.ps1`,
  package and ECVF focused tests plus their CI route, and runtime projection
  `contracts/pcsx2x6/runtime-evidence-index.json`. Update current package
  contract documentation only; preserve historical snapshots and maintainer
  artifacts.
- Verification contract: exact source-to-ZIP path/hash map; reject missing,
  extra, traversal, rooted, duplicate/case-colliding, or noncanonical paths;
  test source-document/build validation separately from runtime projection;
  exercise packaged registry/read-only observation code after extraction to a
  private path containing spaces and brackets. No game or payload execution.
- Local synthetic package proof is not the parent-owned Expanded61 ZIP, owner
  installation, emulator launch, gameplay, or release acceptance. No package
  builder, ZIP publication, commit or push is authorized by this mapping.

## Clean 62-entry candidate local verification checkpoint

Local verification completed through2026-10-15T14:16:13Z. The complete evidence record and preserved failures are in docs/remediation/PR-321-reconciliation.md under this heading: Main1488 and Support42 passed per engine; corrected MainExtras/Shadow23 and package116 passed per engine with actual exits0. Source/package proofs do not establish owner runtime or release acceptance. Exact-head CI/integration and owner/test-PC gates remain separate.
## Issue #351 TMNT 1.59 native Main components -- mapped candidate

- Slice/inventory: `TPM-REQUIRED-PATCH-TMNT-NATIVE-MAIN-COMPONENTS-001` and `TPM-REQUIRED-PATCH-TMNT-NATIVE-MAIN-COMPONENTS-INVENTORY-001`. No numbered PR #321 owner row is assigned.
- Worktree: `fix/rc8-recipe-followup-20261015`, base `4ee514820e6f4445a592602e2ec992677bf9cef1`. Current catalog remains 62 entries / 23 identities / 54 `CreateFile` / eight `ReplaceFile`, SHA-256 `8F30A2BC8CC8AC6B96A324962F9E12792572E08BE6512B1A1808420D6BDB5195`.
- The exact TMNT 1.59 Main source proof binds the unique `TMNT.exe` hash to the existing `tmnt-bepinex-plugin-restore` anchor and pins the two unique method-8 members `OrenVid.dll` and `PK-UnityPlugin.dll`. The proposed recipes are independent absent-only `CreateFile` repairs with no hardware or BepInEx prerequisite; the private source path remains outside the repository.
- The fragment is prepared; catalog integration, the focused portable test, and dual-engine results are pending. No engine body or Main-script change is in scope; only the required catalog hash pin may change.
- The source proof does not establish installed-target absence, plugin/version compatibility, atomic pair behavior, complete setup, launch readiness, or gameplay. Root combined gates and owner-runtime evidence remain separate.

### Focused verification, 2026-10-15 UTC

Root reviewed five TMNT cases, seventeen existing required-patch cases, and two catalog cases per engine with Pester 5.7.1 on Windows PowerShell 5.1 and PowerShell 7. All selected cases passed. The filtered Main wrapper returned exit 1 solely because 1,471 intentionally excluded cases tripped its generic zero-NotRun condition; the independent XML review confirmed seventeen successes and zero failures in each engine. This is focused evidence, not a new full-suite or runtime result. Both TMNT focused workers exited 0. The original 62 recipe entries and order, engine body, and product Main remain unchanged. Catalog: 64 entries, 56 CreateFile, eight ReplaceFile, 23 profiles. Source integration, owner runtime, and release gates remain separate.

### KOF and MKDX source follow-up

Issue #351 adds four independently applicable KOF Regulation A Main component restorations and one MKDX USA 1.06 D3D11Ref.dll restoration. All are CreateFile with BeforeState Absent and exact executable/member/size/SHA1/SHA256 bindings. Unknown present bytes are refused; receipt identity governs undo. KOF's actual ddraw.dll spelling is corroborated by the exact Main archive and matching official WineD3D 10.16 x86 bytes; the guide's dddraw.dll spelling is retained as a documented discrepancy, not used as a target. No graphics, 4 GB patch, setup, controls, launch or gameplay acceptance is implied. The source catalog has 69 entries across 25 profiles: 61 CreateFile and eight ReplaceFile operations. All prior64 entries and their order are preserved. The engine body and product Main are unchanged. Focused root verification is recorded below; no build or owner-runtime result is claimed.
### Root focused verification, 2026-10-15 UTC

The combined source has69entries/25profiles/61CreateFile/eightReplaceFile. All prior64 entries and order, the engine body and product Main are unchanged. Root's independent XML review at2026-10-15T18:14:26Z verified34 specified cases per engine: KOF5, MKDX5, TMNT5, catalog2 and existing required-patch integration17. Initial fixture failures remain preserved. KOF's corrected five cases passed within a batch whose three MKDX fixture failures were subsequently corrected; the final MKDX-only five-case and Main17 workers exited0 in both engines. The focused proof is1826663DB68DC6F63B9CBDB280F9EE5183D5751E7BF058C5D0F8EB0E15B2F03E. This does not claim a new full-suite, package, graphics compatibility or owner-runtime result. Root source commit/push and integration follow the existing authorized workflow; no lane performed publication. No build or ZIP copy is authorized by this source verification.

### Gashaaaan 2 partial candidate status, 2026-10-15 UTC

The candidate catalog now has 72 entries / 26 profiles / 64 CreateFile / 8 ReplaceFile, including three absent-only Jurassic Park 1.08 root DLL restorations for Gashaaaan 2. The prior 69-entry proof boundary is unchanged; the 72-entry candidate is not yet Pester-verified. This is a partial component set, not full dependency completion. Walking Dead `pm/` DLLs remain held. No ABI, gameplay, compatibility, or owner-runtime result is claimed.
## RC8 GPU Fix and BepInEx outcome identity follow-up - implementation evidence

Status: SOURCE REMEDIATION IMPLEMENTED; FOCUSED DUAL-ENGINE TESTS PASS; FULL-SOURCE ANALYZER AND OWNER RUNTIME PENDING

- Scope: issue #300 GPU Fix per-game attribution and BepInEx architecture/skip outcome truthfulness; contract TPM-GPU-BEPINEX-OUTCOME-IDENTITY-001.
- Verified base: isolated integrated snapshot at 15576abc708b6bb9964e68a417a8e4804f26aade; manager SHA-256 80D614C716DE011E6DE9EA15CA25E434E7BE77EE7398B7C1C267AC4CA047A4F7.
- Donor: C:\Users\Example\AppData\Local\Temp\tpm-gpu-bepinex-20261021, branch gpu-bepinex-outcomes-20261021, no commit. Final manager SHA-256 70F6B6D593D9ABF417E4280E2C32A2A5D33B4834C58B52141548674DCE264283; focused test file SHA-256 57AFCBC3977D18700D395343783A9CFDFA2C8422D7E9CCEB72D736B4418A75E1.
- Exact defects mapped before editing: Invoke-GpuFixSetup derives changed IDs from a second scan and Updated count, fabricates GPUFixFailureN identifiers, and its legacy loop includes directories/FullBackup; BepInEx inspection maps a missing architecture to UNSUPPORTED_ARCHITECTURE and the adapter can map an actionable all-skipped result to NO_OP.
- Required implementation: use actual per-game records from one canonical GPU candidate pass; distinguish unknown from explicitly unsupported BepInEx architecture; preserve skipped/protected/unsupported/unknown counts and friendly per-game reason/actions; retain transaction-set disjointness and all existing filesystem safety/rollback checks.
- Hunk mapping: issue #300 / TPM-GPU-BEPINEX-OUTCOME-IDENTITY-001 / TPM-TRACE-001 and TPM-OWNER-001 / INV-GPU-02, INV-BX-05, INV-BX-06.
- Implementation: GPU Fix uses one canonical profile-file candidate pass and returns the actual per-profile changed/completed/failed/skipped/unknown/unattempted sets; write-state uncertainty retains the verified backup and does not invent IDs. BepInEx uses PE evidence to distinguish unsupported from unknown architecture, preserves friendly per-game reason/action data and skip totals, and emits ACTION_REQUIRED for actionable all-skipped inspection. Changes stay in the GPU/BepInEx workflows and result adapters; the shared legacy converter is unchanged.
- Focused evidence, Windows PowerShell 5.1/Pester 5.8 and PowerShell 7/Pester 5.7.1: 1,494 discovered; 8 executed; 8 passed; 0 failed; 0 skipped; 0 inconclusive; 1,486 not run on each engine. Cases cover unknown GPU write state, authoritative mixed/reordered GPU IDs, PE unknown/unsupported classification, unreadable architecture, release-query cohort attribution, BepInEx cleanup accounting, and transaction item identity.
- Static evidence: source and test parser checks passed on both engines; production source contains 0 non-ASCII bytes; `git diff --check` and `git diff --cached --check` passed. Configured PSScriptAnalyzer reported 0 findings in the six changed functions on both engines. The full 2.39 MB source-file analyzer run did not return within a bounded wait and was stopped; no full-file analyzer result is claimed.
- Full-suite execution belongs to the primary integration lane. Exact-package identity/provenance, packaged runtime checks, owner smoke, and release acceptance remain pending outside this source slice.
- Issue #292 exact-package PostgreSQL reset mismatch and all package/runtime/owner acceptance gates remain outside this slice. This source mapping is not a release or owner-test handoff.

## Issue #351 schema-3 variant-cardinality follow-up -- implementation prepared; verification pending

- Mapping: narrow contract TPM-REQUIRED-PATCH-VARIANT-SELECTION-001 under TPM-REQUIRED-PATCHES-REVIEW-001; procedures TPM-TRACE-001, TPM-EVIDENCE-001, and TPM-TRUTH-001. Issue #351 owns the work; no PR #321 owner-report status changes.
- Finding: one build-filtered exclusive-group match can be scalar under Windows PowerShell 5.1 strict mode, causing Resolve-TpmPatchVariantDecision to throw when reading Count. The source correction wraps the value-producing branch in an outer array expression.
- Coverage prepared: four focused outcomes (zero match, one build-filtered selection, multiple unqualified variants, and ambiguous hardware) plus a synthetic production-path Pester case through Get-TpmPatchPlan, Invoke-TpmCatalogPatch, and receipt undo. No test was executed through this integration path.
- Accepted local evidence: PowerShell 7.6.5 strict-mode direct helper matrix passed 4/4; parser-only receipt PS7-Parse-Final.json (SHA-256 CDB595D17C0069453EBCDEC8840F97AEDAAFB37B5C015CCFB64D315730429F56) reports zero errors for the engine, central test file, and main script. Exact hashes and receipts are recorded in the reconciliation report.
- Windows PowerShell 5.1: the temporary .ps1 runner launch was blocked as unsigned. Execution policy was not changed and no durable denial receipt exists. The malformed inline receipt and encoded baseline receipt are retained but excluded from verification; no approved PS5.1 baseline or post-change result exists.
- Pester/full suite: the earlier focused Pester startup was denied access to HKCU\Software\Pester. No Pester or full-suite rerun occurred. The saved historical full-suite receipt is not post-change evidence.
- Separate source-ZIP failures: 123 historical failures report that the exact local source ZIP is unavailable or unsafe. The composite guard's failing predicate is unisolated and remains separate from variant cardinality.
- Independent source review passed the outer-array normalization by inspection. Runtime readiness and owner handoff remain on hold pending an approved PS5.1 route and production-path evidence. No owner handoff, commit, package, release, or GitHub action is authorized.

## Issue #351 schema-2 CreateFile precondition follow-up -- implementation prepared; verification pending

- Mapping: TPM-REQUIRED-PATCH-SCHEMA2-CREATEFILE-001 and TPM-REQUIRED-PATCH-CATALOG-OPERATION-SPEC-001 under TPM-REQUIRED-PATCHES-REVIEW-001; procedures TPM-TRACE-001, TPM-EVIDENCE-001, and TPM-TRUTH-001. Issue #351 owns the work; no PR #321 owner-report status changes.
- Finding: schema-2 CreateFile uses BeforeState=Absent and omits BeforeSha256, while the shared no-op guard reads BeforeSha256 unconditionally. The scoped correction evaluates that comparison only for ReplaceFile and retains the existing CreateFile pin/state guards.
- Coverage prepared: five focused cases call Get-TpmPatchPlan for valid CreateFile, invalid CreateFile pre-state, mismatched CreateFile pins, missing ReplaceFile pre-hash, and equal ReplaceFile before/after pins.
- Verification: tests, parsing, analyzer, and the permanent quality gate were not run in this task. No runtime, owner, package, commit, release, or GitHub result is claimed.

## Issue #351 snapshot error preservation -- 2026-10-24

Slice TPM-REQUIRED-PATCH-SNAPSHOT-ERROR-001 maps the New-TpmResetSnapshot catch,
five native-main regression cases, architecture/inventory notes, and this
addendum to #351 / TPM-TRACE-001 / TPM-EVIDENCE-001 / TPM-TRUTH-001.
No numbered owner-report row is assigned or promoted. The reviewed change
returns a fresh FAILED/UNVERIFIED object with the caught error message;
success, reuse, filesystem guards, and handle disposal remain unchanged.
Partial artifacts are not claimed absent or cleaned. The focused diagnostic
now passes 170/170 on both engines; see the dated validation addendum below.
The isolated candidate and local tests are explicitly authorized. Original
checkout, runtime, commit, package, publication, and release remain excluded.

## Snapshot error preservation validation -- 2026-10-24

Mapping: #351 / TPM-REQUIRED-PATCH-SNAPSHOT-ERROR-001 / TPM-TRACE-001 /
TPM-EVIDENCE-001 / TPM-TRUTH-001. No numbered owner-report status is promoted.

- Isolated candidate branch local/rc8-integrated-20261021, HEAD
  15576abc708b6bb9964e68a417a8e4804f26aade plus preserved dirty candidate work.
- Reviewed engine SHA-256:
  F6DD846C7A41F36720228E58BBEF02E451CCF7A754E312860464482BFBCF3450.
- Reviewed native-main test SHA-256:
  73B4AE581D7782F13E70875A54A3F4C7A84E29D98CB421D55CD8AE5CE0DF9845.
- Bounded three-suite diagnostic: 170 passed, zero failed/skipped/not-run on
  PowerShell 7.6.5 and Windows PowerShell 5.1.26100.9711, Pester 5.7.1,
  actual child exits 0. All five new regressions executed in that scope.
  Runner SHA-256 F54D02865127D85223F870EF73DFE7D09A72AFEA4EFA6B0949DC02FD7A942A99;
  only engine/test pin lines 63 and 67 differ from the preserved original;
  the other eight source pins and all runner guards remain unchanged.
- Complete central suite, Pester 5.7.1: PS5.1 has 1,524 passed, zero failed,
  skipped, not-run, failed blocks, or failed containers; actual exit 0.
  Interval: 2026-10-24T12:23:57Z through 12:42:52Z.
- Complete central suite on PS7: 1,523 passed, zero failed, one skipped,
  zero not-run, failed blocks, or failed containers; actual exit 0.
  Interval: 2026-10-24T12:22:23Z through 12:43:57Z. The aggregate receipt does
  not retain the skipped test identity/reason; do not claim zero skips or
  identify that historical skip by inference.
- ASCII and parser checks: zero findings for Main, engine, and changed native
  test on both engines. Configured PSScriptAnalyzer: zero Error/Warning
  findings for Main and engine on each engine. Main source and central-test
  hashes remain the original diagnostic pins.
- Source-only InjectionHunter probe: 21 production files, 44 findings matched
  reviewed registry dispositions, zero unresolved; actual exit 0. This is
  a static probe, not certification or new runtime evidence.
- Independent final bounded source/test review: PASS. The engine catch family
  audit finds only Test-TpmResetSnapshot still mutating result in catch; it
  initializes that result locally before try. No other engine occurrence of
  the corrected uninitialized catch-result pattern was found by this audit.

Current focused tests also pass the safety cases that failed historically.
The original failed paths/predicates were not retained, and execution context
differs, so those historical failures are not attributed solely to this catch
change and their original causes are not claimed established.

Private local evidence retains original byte backups, source/runner hashes,
full logs, JSON counts, and checksums. Focused log hashes:
PS7 2FB6FC15C8C462F4A4915646B85AC8D2B370CEB1F16D5460FA9838B75C95BF5D;
PS5.1 3545800AF31728D169DE149DDEC2532FCD6D5492720964A2461665C2F87C2C0B.
No private machine/session identifiers or credentials are published here.

This closes the reviewed snapshot source/test slice only. The complete test
folder, permanent procedure gate, packaged GUI/runtime qualification, source
publication, and release gates are not claimed complete. No original-checkout
write, live-game mutation, commit, push, package, tag, release, or wiki action
is part of this TPM slice. RC8 is not declared owner-smoke-ready.

## RC8 safety documentation reconciliation -- 2026-10-24

TPM-RC8-DOCS-SAFETY-RECONCILIATION-001 covers the #290 guide/staged-wiki
reconciliation and owner 30/32 controls explanation, with #255 and #323
boundaries. All source and documentation hunks map to TPM-TRACE-001,
TPM-EVIDENCE-001, TPM-TRUTH-001 and TPM-UX-001. Existing owner statuses remain
unchanged. The sole product source hunk corrects standalone controls wording;
no behavior, calls, confirmation policy, backup or write algorithm changes.
Nine source-reconciled pages are staged: BepInEx, FFB-Setup, GPU-Fix,
Health-Check, Postgres-Setup, Propagate-Controls, Register, Troubleshooting,
and dgVoodoo2. README.md, QUICKSTART.md, both packaged text guides, and the
existing Home/AutoSync staging pages now state the verified controls,
registration, extraction-evidence, backup and path boundaries. Architecture
and the invariant inventory record these contracts. No live wiki was changed.
Independent review, final-source full-folder tests, permanent procedure gates
and genuine runtime/GUI evidence remain pending; no owner status is promoted.

## Active migration consumer correction -- 2026-10-24 (focused source proof)

Slice TPM-MIGRATION-ACTIVE-CONSUMERS-001 maps the migration selector and its
focused real-migration/consumer regressions to owner ID 34, #323, and
TPM-TRACE-001, TPM-EVIDENCE-001, TPM-TRUTH-001, TPM-AUTH-001. The separate
#290 documentation reconciliation slice records operator-facing path guidance.
The overrides loss was empirically reproduced on both PowerShell engines:
accepted migration moved the custom file away, then the normal script-root
consumer recreated defaults. The exact operational exceptions now retain
TeknoParrot-Manager.overrides.json, LaunchBoxBackups, PostgresBackups and
BepInExCache beside the script, matching their existing consumers.
(SUPERSEDED in part: this record originally also kept PostgresRecoveryBackups
beside the script. Later RC8 work relocates it to the managed Backups folder
per directory; see inventory TPM-MIGRATION-ACTIVE-CONSUMERS-001.) Other safe
known items retain their normal migration.
Nine permanent real-helper/consumer cases characterized the baseline as
3 passed / 6 failed / 0 skipped; after the fix all 9 pass on PowerShell 5.1
and PowerShell 7. These focused results do not replace final full-folder or
owner-runtime proof. No adoption, merge or deletion of earlier-relocated
copies is added; operators preserve those copies for reviewed recovery.
Main source SHA256: 41BB0EBA7853C0D4CF58631C4AC97CA540A02466322AF3A84B1CCA80456F72B9.
No owner-runtime status is promoted. Independent review, final source gates
and runtime proof remain pending. No broad migration bypass, new consumer
root, package, live installation, publication, or release is authorized here.

### Independent documentation delta -- 2026-10-24

The TPM-RC8-DOCS-SAFETY-RECONCILIATION-001 source-backed follow-up corrects
SupportPackages and custom-thumbnail guidance to the owned runtime root and
Assets paths. The migration inventory now distinguishes archived ActionItems
copies from the fresh program-root report producer and optional Save dialog.
Health Check descriptions distinguish the initial read-only assessment from
confirmed follow-up writes. Mapping remains owner 30/32, #290/#255/#323,
TPM-TRACE-001 / TPM-EVIDENCE-001 / TPM-TRUTH-001 / TPM-UX-001. This documentation
delta has no source behavior change; independent delta review remains pending.
## Current RC8 source menu evidence -- 2026-10-24

The earlier missing-screenshot observation is historical. A genuine current
main-menu image is now present at images/release/RC8-MainMenu.png.
Main SHA-256: A4F849C60BF2B28B92284D551FC4F1D8C4303E5892276701AD3AF200246D0B91.
Image SHA-256: 3B7CA689F7A46895CD6C51E9BD286AAEE86C323363B722AE4CDF468DC3D4EFC8.
The unmodified full script ran under Windows PowerShell 5.1 in a new owned
Windows Terminal against an isolated runtime fixture. The default capture
records actual 120x40 character dimensions and 1115x818 visible-window pixels.
A separate genuine constrained run records actual 100x25 dimensions. Both
show RC8, all options 1-16, H/L/Q, and the final prompt; both exited by Q.
The actual image was visually reviewed for menu ordering, clipping, and private
paths. Only the owned visible window was captured; no synthetic image or
image editing was used. No live game or original-checkout write occurred.

This is Maintainer bootstrap runtime evidence that closes the source-asset
prerequisite only. It is not evidence that a final ZIP was built or that the
complete #323 packaged runtime matrix passed. Full frozen-folder tests,
package identity/validation, final extracted-byte checks, remaining runtime
checks, and required handoff gates remain separate.

## Final qualification remediation contracts -- 2026-10-24

The finished original full-folder runs failed on unchanged 637-file source,
main SHA256 A4F849C60BF2B28B92284D551FC4F1D8C4303E5892276701AD3AF200246D0B91.
Preserved private Next-Qualification-Diagnosis.json maps every failure.
Owners 1/9 are reopened for TPM-RC8-RESHADE-CONSOLE-BUFFER-001 before source edits.
New owner row 36 is assigned here to the confirmed certification-infrastructure
failure, TPM-RC8-CERT-WORKER-BOOTSTRAP-001; it is not owner 3 and does not
invent an owner-game report. Row 36 originates in the #323 qualification evidence.
Both contracts and applicable inventory rows precede implementation.
Private PS5.1 qualification imports inbox Security; this is not a product bypass.
The PSSA 180-second budget remains unchanged; heavy analysis is serialized.
Source fixes, independent model-specific review, final frozen gates, and genuine
runtime evidence are pending. No new source-fixed or owner-runtime claim is made.
Private smoke packaging is requested, but checklist section 4 clean/exact-SHA
READY and human gates remain binding; no commit, push or publication is authorized.

### Rendering-time resize proof refinement -- 2026-10-24

Owners 1/9 remain SOURCE REMEDIATION REQUIRED while completing the console
slice. The initial scoped Astra review passed the finite-buffer repair but
correctly identified rendering-time resize as unproven. A new deterministic
case now fails before the additional source edit on both engines: the chooser
blesses post-render dimensions for a block drawn across a width transition,
so it does not rebuild before a later in-place update. Same contract,
TPM-RC8-RESHADE-CONSOLE-BUFFER-001, #323, TPM-TRACE-001/EVIDENCE-001/AUTH-001;
only the initial-layout ownership boundary is being corrected. A scoped delta
review and all final frozen gates remain required.


### Current focused disposition -- 2026-10-24, before final freeze

Owners 1/9/36 are SOURCE FIXED; OWNER RUNTIME NEEDED on the scoped evidence
above, not FIXED + TESTED or release-ready. Main is
B461D002D171FD033334937E28371953FE5AB182A473EF56191C17BA146BFFD4.
Independent product, console-delta and repaired private-harness reviews pass.
Full frozen main/folder/quality gates remain pending and will be recorded
outside the frozen source tree. No aggregate is substituted by subset sums.
The worker regression's late authorship remains an explicit process deviation:
exact pre-edit-backup red/green and the already-failing original permanent
matchers mitigate source-verification risk, not chronology or owner acceptance.
Private packaging remains held on the exact clean pushed-ref/READY/human gates.


### Owner 3 qualification-fixture repair -- 2026-10-24, before test edit

The first revised frozen native PS5.1 main run failed: 1520 passed, 2 failed,
2 skipped, actual exit 1, all 642 source files unchanged. Private EOFBaseline
on both engines restores the original visible stdin-EOF topology and passes
the real-host case plus all three redirected-input cases. Each preserves
4 passed, 1 failed, no skips and actual exit 1: the remaining status test
assumes STALE while the real report truthfully says NOT BUILT.

Owner ID 3 status semantics, TPM-OWNER-STATUS-GATE-001 section 16, #323 /
PR #321, TPM-OWNER-003/TRACE-001/EVIDENCE-001/AUTH-001 own the fixture-only
repair. Contract inventories and report/pointer mapping precede the test edit.
Explicit scenario state must replace dependence on live provenance; retain
every assertion and the unchanged production gate. No owner status changes.
Targeted red/green, scoped independent review and a new complete freeze are
required before final qualification. The first failed freeze remains evidence,
not a passing aggregate. Package and authority gates remain unchanged.

The same owner 3 fixture contract also covers the next observed precondition:
the synthetic extra-owner ID 36 collides with the newly assigned actual owner
36. EOFVerified both engines advances through candidate-state checks but
preserves 4 passed / 1 failed, actual exits 1, at the absent-owner assertion.
Derive a genuinely absent synthetic integer from the current board census;
keep the same absent-owner assertion and production gate. This inventory
refinement precedes that test hunk. No passing aggregate or owner promotion.

EOFComplete closes these focused preconditions on both native engines:
5 passed, 0 failed, no skips, 1519 intentionally excluded; actual child
exits 0, all 642 working-source files matched. The source delta review passes
without assertion weakening or production-gate edits. First failed freeze,
intermediate failures and separate native receipts remain immutable.
Final full-source freeze and aggregate/permanent gates are still required.
Owner 3 remains SOURCE FIXED; OWNER RUNTIME NEEDED; no owner is promoted.

## RC8 lane C follow-up -- #339, #333, #366, #367 -- 2026-10-25

Lane C source changes are uncommitted in worktree tpm-rc8-lane-C at base
0ceddf5514aa489e3e124dd5e32f3d99c78ae951. Status is SOURCE FIXED; NOT TESTED;
OWNER RUNTIME NEEDED. No focused or regression tests were authored or run in
this lane. Main verifies after all lanes land.

| Issue | Owner ID | Contract | Status | Hunk mapping |
|---|---|---|---|---|
| #339 | F09 (issue-level; no board row) | TPM-RC8-LANE-C-SAVE-CONFIG-UNATTENDED-001 | SOURCE FIXED; NOT TESTED | Save-Config conditional key; config load capture |
| #333 | F03 (row 30 nearest) | TPM-RC8-LANE-C-CONTROL-NOPROPAGATE-CANONICAL-001 | SOURCE FIXED; NOT TESTED | Invoke-ControlPropagationLegacy canonical-correction condition |
| #366 | issue-level (BepInEx rollback section) | TPM-RC8-LANE-C-BEPINEX-ROLLBACK-TREE-001 | SOURCE FIXED; NOT TESTED | Restore-BepInExUpdateBackup clear-before-copy; created-dir rollback condition |
| #367 | issue-level (row 11 nearest) | TPM-RC8-LANE-C-RESHADE-REMOVAL-ROLLBACK-001 | SOURCE FIXED; NOT TESTED | Remove-TpmReShadeOwnedDeployment rollback and status; Invoke-TpmReShadeRemoval filter |

No owner is promoted. Owner runtime smoke, commit, package, and release
authorization are all NOT granted.
