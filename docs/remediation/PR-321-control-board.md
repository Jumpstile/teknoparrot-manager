# PR #321 TPM Remediation Control Board

Status: blocked. This board is the source of truth for TPM remediation state.

## Current repository state

- Root: `C:\REPOS\tpm-rc8-certified-a700d093`
- Branch: `fix/rc8-release-blockers`
- HEAD: `aa37474409b75752aaa9d729c0ee23cd52e4cd14`
- Worktree at the accepted source checkpoint: clean; the current reconciliation slice changes governance documents only.
- Candidate ZIP: `C:\REPOS\tpm-rc8-candidate-output\TeknoParrot Manager v1.0 RC8.zip`.
- Candidate freshness: stale relative to accepted HEAD; the prior ZIP must not be reused for owner smoke. Package rebuild is not authorized.
- Accepted FFB mode-8 checkpoint: commit `aa37474409b75752aaa9d729c0ee23cd52e4cd14`; focused FFB 40/40, SupportPackage 40/40, and full main Pester 1028/1028.
- Permanent procedure gate: expected fail until unresolved source/owner findings, stale candidate identity, and owner-runtime evidence are resolved.

## Status rules

Allowed statuses are: `NOT FIXED`, `SOURCE FIXED; OWNER RUNTIME NEEDED`, `FIXED + TESTED`, `DEFERRED BY OWNER`, `SOURCE CLAIM REQUIRES RE-AUDIT`, `SOURCE CLAIM INVALID / RE-AUDIT REQUIRED`, and `SOURCE REMEDIATION REQUIRED`.

Re-audit statuses are fail-closed and cannot advance to owner-runtime-only until source evidence, focused tests, rebuilt package identity, and runtime proof exist.

## Owner report table (historical pre-re-audit snapshot)
The status values in this retained snapshot are historical evidence. The
canonical release-decision statuses are in the corrected table below.

| ID | Owner-visible failure | Expected behavior | Current status | Owning subsystem | Source/functions | Tests | Runtime proof needed | Next action | Slice assignment |
|---:|---|---|---|---|---|---|---|---|---|
| 1 | ReShade no-change/back/cancel crash | Safe no-op and correct return routing | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade | ReShade action results | Existing ReShade regressions | Packaged U/B smoke | Owner runtime | ReShade follow-up |
| 2 | Duplicate error handling | One authoritative error policy | SOURCE FIXED; OWNER RUNTIME NEEDED | Downloads | Web/download wrappers; RequestErrorAction remediation | RC8 remediation contracts; wrapper source test | Startup/download smoke | Rebuild then owner runtime | Slice 1 |
| 3 | Missing universal progress | Every long-running path has TPM progress, structured workflow status, or an explicit bounded/no-progress reason | SOURCE FIXED; OWNER RUNTIME NEEDED | Progress/status | Progress.Core inventory: compact progress, workflow status, bounded waits, and justified bounded writes | `PR #321 Progress.Core source inventory`; existing progress contracts | Full packaged operation matrix | Owner runtime | Progress.Core |
| 4 | AutoSync scan output | Compact bounded progress | SOURCE FIXED; OWNER RUNTIME NEEDED | Progress/status | Select-GamesInteractive | Compact progress tests | AutoSync smoke | Owner runtime | Progress slice |
| 5 | GPU Fix progress | Compact status without PowerShell panel | SOURCE FIXED; OWNER RUNTIME NEEDED | Progress/status | Invoke-GpuFixSetup | GPU source contracts | GPU Fix smoke | Owner runtime | Progress slice |
| 6 | Thumbnail progress | Accurate compact download status | SOURCE FIXED; OWNER RUNTIME NEEDED | Progress/status | Invoke-ThumbnailDownload | Thumbnail tests | Thumbnail smoke | Owner runtime | Progress slice |
| 7 | Missing thumbnail list | Complete no-icon accounting | SOURCE FIXED; OWNER RUNTIME NEEDED | Progress/status | Thumbnail reporting | Thumbnail tests | Full no-icon matrix | Owner runtime | Progress slice |
| 8 | Thumbnail fallback | Defined 404 behavior | SOURCE FIXED; OWNER RUNTIME NEEDED | Progress/status | Invoke-TpmDownload | Fallback tests | 404 smoke | Owner runtime | Download follow-up |
| 9 | ReShade preview sync | Preview reflects live terminal selection; terminal is the sole profile authority and the gallery exposes no ignored selector | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade | Read-TpmReShadeTerminalProfile; Sync-TpmReShadeGallerySelection | Preview authority/state tests | Preview smoke | Owner runtime | ReShade follow-up |
| 10 | ReShade selector visibility | Selector instructions remain visible | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade | Selector UI | Selector contracts | UI smoke | Owner runtime | ReShade follow-up |
| 11 | Protected ReShade ownership | Adopt/replace safely | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade | Get-TpmReShadeOwnershipClassification; Install-TpmReShadeProfileDeployment; Invoke-ReShadeSetup | ReShade protected-adoption tests | Explicit adopt/replace smoke | Owner runtime | TPM-RESHADE-001 |
| 12 | ReShade accounting | All games and outcomes counted, including unsafe/malformed details and direct repair/rerun action | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade | Get-TpmReShadeApplyPreflight; Get-TpmReShadeApplyAccounting; Invoke-ReShadeSetup; Get-TpmReShadeResultActionModel | ReShade accounting and result-action tests | All-games packaged smoke | Owner runtime | TPM-RESHADE-001 |
| 13 | Crosshair browser completion | Browser completes safely after P2 | SOURCE FIXED; OWNER RUNTIME NEEDED | Crosshair | Export-CrosshairPreview | Crosshair completion contracts | Browser smoke | Owner runtime | Crosshair follow-up |
| 14 | Crosshair focus return | Focus returns to terminal when available | SOURCE FIXED; OWNER RUNTIME NEEDED | Crosshair | Export-CrosshairPreview/focus fallback | Crosshair focus contracts | Focus smoke | Owner runtime | Crosshair follow-up |
| 15 | Crosshair prompt placement | P1/P2 rows are usable | SOURCE FIXED; OWNER RUNTIME NEEDED | Crosshair | Crosshair setup/input | Crosshair contracts | Constrained console smoke | Owner runtime | Crosshair follow-up |
| 16 | PostgreSQL repair loop | Backup/retry/reset is bounded | SOURCE FIXED; OWNER RUNTIME NEEDED | PostgreSQL | PostgreSQL recovery; categorized resume reasons and reachable password repair | Recovery tests; focused RC8 UX tests | Repair smoke | Rebuild then owner runtime | Slice 1 |
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
| 29 | Action Required freshness mismatch | Newest evidence is labeled and ambient diagnostics are scoped | SOURCE FIXED; OWNER RUNTIME NEEDED | Support package | Support package freshness, EvidenceClass manifest records | SupportPackage.Tests; support evidence source review | Rebuilt support package and owner review | Complete troubleshooting intake | Support follow-up |
| 30 | Controls truthfulness | Zero-bound results never imply verified readiness | SOURCE FIXED; OWNER RUNTIME NEEDED | Controls truthfulness | Write-ControlPropagationResults; control-readiness engine | Controls truthfulness focused tests; existing controls tests | Zero-bound packaged runtime result | Owner runtime | TPM-CONTROLS-001 |
| 31 | dgVoodoo2 wording | Results explain deployment state | SOURCE FIXED; OWNER RUNTIME NEEDED | Progress/status | dgVoodoo2 result wording | Existing tests | Owner wording review | Owner runtime | Progress slice |
| 32 | Global consistency rule | Every enumerated prompt uses the central contract or has a documented design boundary | SOURCE FIXED; OWNER RUNTIME NEEDED | Prompts/navigation | TPM-PROMPT-001 inventory; finite-choice routes centralized; stateful, exact-token, secure, path, and renderer-aware boundaries documented | `Read-TpmChoice validation`; `Prompt.Core fixed choice routes` | Packaged consistency smoke | Owner runtime | Prompt.Core |

## Subsystem grouping

- Progress/status: 2-8, 31; ID 3 has source evidence and remains owner-runtime needed.
- Prompts/navigation: 26, 32.
- Repair/scoping: 16-23.
- ReShade: 1, 9-12.
- Crosshair: 13-15.
- PostgreSQL: 16.
- Frontend exports: 23-25.
- Support package: 27-29.
- Controls truthfulness: 30.
- Packaging/runtime provenance: all owner-runtime statuses and stale candidate identity.
- Permanent procedure enforcement: this board, slice contracts, and the fail-closed gate.

## Current blockers

- Canonical source-remediation blockers: ID 3.
- Canonical source re-audit blockers: IDs 4, 5, 7, 20, 23-27, and 30-32.
- Canonical `SOURCE FIXED; OWNER RUNTIME NEEDED` rows: IDs 1, 2, 6, 8-22, 28, and 29.
- ID 29 is source-fixed by the Slice F support-evidence scoping re-audit; package rebuild and owner-runtime proof remain outstanding.
- Test blockers: no focused source-test blocker remains for audited paths, but unresolved design work and owner-runtime routes remain.
- Package/runtime blockers: candidate ZIP is stale; no owner smoke is authorized.
- Owner-design blockers: ReShade ownership/accounting and remaining stateful prompt-picker boundaries need explicit future contracts.

## Next-slice queue
1. Controls truthfulness (`TPM-CONTROLS-001`). Contract: saved configuration, inferred readiness, and observed physical binding remain separate. Gate: expected fail until owner runtime.
2. ReShade ownership and accounting. Excludes controls. Contract: protected files are never silently adopted or removed and every selected game has one terminal outcome. Gate: expected fail until owner runtime.
3. Final PR #321 reconciliation and package identity review.

## Control-board rule

A remediation change is not complete until its owner IDs, slice contract, behavior contract, focused tests, runtime proof requirement, and hunk classification are recorded here and in the remediation report.
## Canonical release-decision status -- live re-audit correction -- 2026-09-08

This section is the canonical release-decision source. It supersedes the
historical owner mapping and prior blocker prose above. The candidate ZIP
remains stale and is not a release gate.

| ID | Previous status | Corrected status | Evidence | Source remediation | Owner retest |
|---:|---|---|---|---|---|
| 1 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Source/test claim not contradicted by the re-audit | No | Yes, rebuilt package |
| 2 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Full source audit found only the wrapper's splatted Invoke-WebRequest call; all callers use the typed RequestErrorAction contract; Slice A source test passes | No | Yes, rebuilt package |
| 3 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE REMEDIATION REQUIRED | Owner smoke exposed long-running/progress failure surface; package proof is invalid | Yes | Yes |
| 4 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | Existing source claim lacks trustworthy package evidence | Re-audit first | Yes |
| 5 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | Existing source claim lacks trustworthy package evidence | Re-audit first | Yes |
| 6 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Thumbnail progress and named failure reporting are source/test covered; Slice A focused tests pass | No | Yes |
| 7 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | No complete current-run no-icon proof | Re-audit first | Yes |
| 8 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Definitive 404 is preserved across fallback; Slice A regression test passes | No | Yes |
| 9 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | No contrary source evidence found | No | Yes |
| 10 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Selector contract remains source/test supported | No | Yes |
| 11 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade ownership re-audit confirms protected unknown/bundled content stays unchanged by default; explicit confirmed Adopt passes overwrite only through the transactional deployment path; Slice C tests pass | No | Yes |
| 12 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade accounting now includes explicitly kept previous TPM-managed profiles as a terminal `KeptPrevious` outcome; accounting invariant remains exact; Slice C tests pass | No | Yes |
| 13 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Completed non-interactive browser state after valid P2; explicit return/close guidance; no further click mutation | No | Yes |
| 14 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Best-effort console focus return with logged fallback; terminal remains usable | No | Yes |
| 15 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Workflow-aware P1/P2, confirmation, first-run, and cursor-hide prompts with typed fallback | No | Yes |
| 16 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE REMEDIATION REQUIRED | Password recovery/elevation resume failed owner smoke; beginner-safe reason unproven | Yes | Yes |
| 17 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Repair candidate search and apply calls are limited to the affected broken profile codes; focused one/multiple/zero-scope tests pass | No | Yes |
| 18 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | No-candidate reporting includes searched-folder and affected-profile evidence plus Back; focused tests pass | No | Yes |
| 19 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Optional source recopy hands only affected profile codes to AutoSync; no broad extraction escape found | No | Yes |
| 20 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | Back routing has source tests but no trusted package proof | Re-audit first | Yes |
| 21 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Repair results classify every report once and require saved-path read-back before FIXED; focused accounting tests pass | No | Yes |
| 22 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Post-repair result completes before the optional thumbnail prompt; scoped source handoff remains affected-only | No | Yes |
| 23 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | No new source contradiction; package gate is stale | Re-audit first | Yes |
| 24 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | Prompt source evidence exists; packaged behavior unproven | Re-audit first | Yes |
| 25 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | Normal completion source evidence lacks trusted package proof | Re-audit first | Yes |
| 26 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | Central choice contract exists; all-row claim needs renewed audit | Re-audit first | Yes |
| 27 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | Support prompt source evidence exists; package was stale | Re-audit first | Yes |
| 28 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Manifest includes stale Action Required evidence correctly | No | Yes |
| 29 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE REMEDIATION REQUIRED | Freshness label works; ambient plugin diagnostics are not clearly current-run/untested scoped | Yes | Yes |
| 30 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | Controls tests exist; package gate is not trustworthy | Re-audit first | Yes |
| 31 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | Wording source claim lacks owner/package proof | Re-audit first | Yes |
| 32 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | Global claim depended on the invalid accepted count | Re-audit first | Yes |

- Historical false source-fixed claims included IDs 2, 13, and 14. The current crosshair slice supersedes the prior ID 13/14 disposition with source-fixed completed-state/focus behavior; IDs 16 and 29 are now source-fixed by the PostgreSQL and support-evidence re-audits, IDs 11 and 12 remain source-fixed with owner-runtime evidence outstanding, ID 3 remains the source-remediation blocker, and remaining rows require renewed source/package audit before owner-only classification.

Changelog decision queued for the next authorized source slice: `Known RC8 owner-smoke blockers identified. Release remains blocked pending re-audit, source remediation, package rebuild, and owner-runtime retest.`

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
