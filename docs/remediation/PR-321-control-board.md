# PR #321 TPM Remediation Control Board

Status: blocked. This board is the source of truth for TPM remediation state.

## Current repository state

- Root: `C:\REPOS\teknoparrot-manager\.worktrees\rc8-release-readiness`
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
2. If every source gate passes, follow the authorized candidate-preparation path; retain exact pushed-SHA identity and package validation, then hand the candidate to Eli/ARCADE for owner smoke.
3. Do not merge, tag, publish, release, or claim owner-runtime completion before Eli's final approval.

## Control-board rule

A remediation change is not complete until its owner IDs, slice contract, behavior contract, focused tests, runtime proof requirement, and hunk classification are recorded here and in the remediation report.

## PostgreSQL reset transport remediation slice

Owner report ID 16 / PR #321 is assigned to
`TPM-POSTGRES-RESET-TRANSPORT-001`. The source contract requires byte-verified
authentication-policy restoration before restart and fail-closed service state
if restoration cannot be verified. Owner-reported ARCADE evidence establishes
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
| 1 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Source/test claim not contradicted by the re-audit | No | Yes, rebuilt package |
| 2 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Full source audit found only the wrapper's splatted Invoke-WebRequest call; all callers use the typed RequestErrorAction contract; Slice A source test passes | No | Yes, rebuilt package |
| 3 | SOURCE REMEDIATION REQUIRED | SOURCE FIXED; OWNER RUNTIME NEEDED | The user-extensible discovery/sort gap is fixed; focused tests and finite census pass; the final full source/permanent aggregate gate passed. | No source edits remain for the gap | Yes, full packaged operation matrix |
| 4 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | `Select-GamesInteractive` and `Select-GamesInteractiveCombined` report each ZIP across their known source total, including main and supplementary sources; both real call-site tests pass in PS7 and Windows PowerShell 5.1 | No further source change | Yes |
| 5 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Both GPU GameProfiles scan helpers report each catalog item against the known XML total and close the compact row; real call-site behavior tests passed in PS7 and Windows PowerShell 5.1 | No further source change | Yes |
| 6 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Thumbnail progress and named failure reporting are source/test covered; Slice A focused tests pass | No | Yes |
| 7 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | `Invoke-ThumbnailDownload` adds only definitive-404 profile codes to the current missing-no-icon list and reports that list separately from transient download failures; source supports complete per-run accounting | No | Yes, full no-icon matrix |
| 8 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Definitive 404 is preserved across fallback; Slice A regression test passes | No | Yes |
| 9 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | No contrary source evidence found | No | Yes |
| 10 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Selector contract remains source/test supported | No | Yes |
| 11 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade ownership re-audit confirms protected unknown/bundled content stays unchanged by default; explicit confirmed Adopt passes overwrite only through the transactional deployment path; Slice C tests pass | No | Yes |
| 12 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade accounting now includes explicitly kept previous TPM-managed profiles as a terminal `KeptPrevious` outcome; accounting invariant remains exact; Slice C tests pass | No | Yes |
| 13 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Completed non-interactive browser state after valid P2; explicit return/close guidance; no further click mutation | No | Yes |
| 14 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Best-effort console focus return with logged fallback; terminal remains usable | No | Yes |
| 15 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Workflow-aware P1/P2, confirmation, first-run, and cursor-hide prompts with typed fallback | No | Yes |
| 16 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | PostgreSQL 8.3 reset transport and committed-state protections remain; default install/recovery/reinitialize now gives explicit temporary-admin/UAC/Yes/automatic-resume guidance immediately before each elevation handoff without exposing internals. PS7 and Windows PowerShell 5.1 focused UX suites each pass 60/60; complete source-quality and permanent procedure gates pass. Exact pushed-SHA package/runtime evidence remains pending. | `TPM-POSTGRES-RESET-TRANSPORT-001`; `TPM-POSTGRES-UAC-GUIDANCE-001`; PostgreSQL focused tests | Exact pushed-SHA package install/recovery/reinitialize smoke |
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

## Desktop OMP S1 -- PostgreSQL 8.3 database restore transaction

Status: SOURCE REMEDIATION IMPLEMENTED; OWNER SMOKE PAUSED

| Owner ID | Scope | Source ownership | Focused evidence | Runtime/release disposition |
|---:|---|---|---|---|
| 16 | PostgreSQL restore transaction and coupled profile/database rollback | `TeknoParrot-Manager.ps1`; `Tests/TeknoParrot-Manager.Tests.ps1` | S1-DB-RESTORE deterministic fake PostgreSQL 8.3 harness and transaction-core contracts | No PostgreSQL 12 proof; no package, push, owner smoke, Arcade, wiki, merge, tag, publish, certification, or release action |

The S1 contract is `docs/remediation/slices/TPM-S1-DB-RESTORE-001.md`.
The source boundary includes tool-version gating, closed selected-backup
preflight, verified current-database dumps, deterministic receipts/order,
stop-on-first-failure mutation, verified rollback, final verification,
`TPM.TransactionResult.v1`, and beginner-safe normal restore output. Owner
smoke remains paused pending ChatGPT review and later explicit authorization.
- Final Desktop OMP evidence: PowerShell parser `ParseErrors=0`;
  PSScriptAnalyzer Error/Warning `Findings=0`; ASCII check `NonAscii=0`;
  `git diff --check` clean apart from Git's LF-to-CRLF warnings; canonical
  Pester 5.7.1 main suite `1121 passed, 0 failed`; focused S1 suites:
  `S1-TX-CORE 18`, `S1-FILE-PROMOTION 12`,
  `S1-DIRECTORY-REPLACEMENT 18`, `S1-BACKUP-GATE 9`,
  `S1-DB-RESTORE 12`, all passed.

## Desktop OMP S1 -- legacy state transaction normalization

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

Source and focused migration policy tests pass; the full source quality wrapper has now passed and fresh exact-head CI remains pending. Commit/push is authorized only to PR #321's existing head ref for exact-head CI. Package rebuild, owner runtime, Arcade, wiki, merge, tag, publish, certification, and release-ready action remain unauthorized.

## Desktop OMP S1 -- setup and manager-update transaction normalization

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
are recorded in the P1-1 section below. Package rebuild, owner runtime, Arcade,
wiki, merge, tag, publish, certification, and release-ready actions remain
unauthorized. Commit/push is authorized only after source gates pass and only
to PR #321's existing head ref for exact-head CI.

## Desktop OMP S1 -- RC8 update version ordering

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

## Desktop OMP -- RC8 typed identity-target delta

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

## Desktop OMP -- exact-head CI and owner-status output

Run `37090573916` checked out synthetic merge tree `39301e430849c0996746187aecfffa937fe705b6`, not PR head `0295415fb1b9d4bf6880945eb4807d4b2b27ec96`. The failed assertion is in the owner-status gate test, not either RC8FullReview product path. Captured child `Write-Error` output contains ANSI escapes between the expected status tokens; Pester's NUnit exporter then fails on the raw ESC byte. The `TPM-OWNER-STATUS-GATE-001` delta (owner ID 3; `TPM-OWNER-003`, `TPM-TRACE-001`, and `TPM-AUTH-001`) normalizes captured output and makes CI checkout/assert the exact PR head SHA. No owner status is promoted by this test-only correction.

## Desktop OMP S2-A -- shared transaction presentation contract

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
reconciliation section after execution. Owner smoke, package rebuild, Arcade,
wiki, push, merge, tag, publish, certification, and release-ready actions
remain unauthorized.

## Desktop OMP S2-B1 -- shared transaction renderers

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
Arcade, wiki, push, merge, tag, publish, certification, or release-ready action
is authorized by this slice.

## Desktop OMP -- BepInEx functional transaction audit

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
for its freshness check. Owner/runtime smoke, package rebuild, Arcade, wiki,
push, merge, tag, publish, certification, and release-ready actions remain
unauthorized.

## Desktop OMP -- Support posture corpus and CHD/layout implementation

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

## Desktop OMP -- Catalog-wide game support contracts

Status: IMPLEMENTATION COMPLETE; LOCAL FOCUSED VALIDATION COMPLETE; OWNER-RUNTIME EVIDENCE REQUIRED

Slice contract: `docs/remediation/slices/TPM-GAME-SUPPORT-CONTRACTS-001.md`.

Owner report: `TPM_GAME_SUPPORT_CONTRACTS_001`. The implementation is
catalog-wide and uses the pinned `teknogods/TeknoParrotUI` commit
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
Arcade, wiki, push, merge, tag, publish, certification, and release-ready
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

## Desktop OMP -- Slice 0 immutable current-release catalog snapshot

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
  owner smoke, Arcade work, merge, tag, publish, certification, or release
  action is included.
- Current status: source/evidence implementation in progress; all later
  catalog and runtime slices remain blocked on Slice 0 validation and review.

## Desktop OMP -- Slice 1 current-release GameSupport contract migration

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
- No runtime reproduction, package, owner smoke, Arcade, hosted CI, push,
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

## Desktop OMP -- Historical baseline provenance re-baseline

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
  commit, package, runtime, owner smoke, Arcade, merge, tag, publish,
  certification, or release action is authorized.

## Desktop OMP -- RC8 compact-default menu corrective slice

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
  behavior on the authorized owner runtime. No ARCADE runtime work is performed
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
