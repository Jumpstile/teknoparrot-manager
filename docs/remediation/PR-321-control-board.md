# PR #321 TPM Remediation Control Board

Status: blocked. This board is the source of truth for TPM remediation state.

## Current repository state

- Root: `C:\REPOS\tpm-rc8-certified-a700d093`
- Branch: `fix/rc8-release-blockers`
- HEAD: `7cd77108759084679f33eb27f98b6bfaaa58ff4d`
- Worktree: dirty; Progress.Core source inventory and tests are uncommitted.
- Candidate ZIP: `C:\REPOS\tpm-rc8-candidate-output\TeknoParrot Manager v1.0 RC8.zip`.
- Candidate freshness: stale relative to uncommitted source changes; package rebuild is not authorized.
- Permanent procedure gate: expected fail until unresolved owner findings, stale candidate identity, and owner-runtime evidence are resolved.

## Status rules

Allowed statuses are: `NOT FIXED`, `SOURCE FIXED; OWNER RUNTIME NEEDED`, `FIXED + TESTED`, `DEFERRED BY OWNER`, `SOURCE CLAIM REQUIRES RE-AUDIT`, `SOURCE CLAIM INVALID / RE-AUDIT REQUIRED`, and `SOURCE REMEDIATION REQUIRED`.

Re-audit statuses are fail-closed and cannot advance to owner-runtime-only until source evidence, focused tests, rebuilt package identity, and runtime proof exist.

## Owner report table

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
| 9 | ReShade preview sync | Preview reflects live selection | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade | Read-TpmReShadeTerminalProfile | Preview contract | Preview smoke | Owner runtime | ReShade follow-up |
| 10 | ReShade selector visibility | Selector instructions remain visible | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade | Selector UI | Selector contracts | UI smoke | Owner runtime | ReShade follow-up |
| 11 | Protected ReShade ownership | Adopt/replace safely | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade | Get-TpmReShadeOwnershipClassification; Install-TpmReShadeProfileDeployment; Invoke-ReShadeSetup | ReShade protected-adoption tests | Explicit adopt/replace smoke | Owner runtime | TPM-RESHADE-001 |
| 12 | ReShade accounting | All games and outcomes counted | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade | Get-TpmReShadeApplyPreflight; Get-TpmReShadeApplyAccounting; Invoke-ReShadeSetup | ReShade accounting tests | All-games packaged smoke | Owner runtime | TPM-RESHADE-001 |
| 13 | Crosshair browser does not close | Browser closes safely | SOURCE CLAIM INVALID / RE-AUDIT REQUIRED | Crosshair | Export-CrosshairPreview | Crosshair contracts | Browser smoke | Source remediation | Crosshair follow-up |
| 14 | Crosshair focus does not return | Focus returns to terminal | SOURCE CLAIM INVALID / RE-AUDIT REQUIRED | Crosshair | Export-CrosshairPreview/focus fallback | Crosshair contracts | Focus smoke | Source remediation | Crosshair follow-up |
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
| 29 | Action Required freshness mismatch | Newest evidence is labeled and ambient diagnostics are scoped | SOURCE REMEDIATION REQUIRED | Support package | Support package freshness, EvidenceClass manifest records | SupportPackage.Tests; support evidence source review | Rebuilt support package and owner review | Complete troubleshooting intake | Support follow-up |
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

- Source blockers: IDs 11 and 12 remain NOT FIXED; IDs 3, 17-22, 26, 30, and 32 have source evidence.
- Test blockers: no focused source-test blocker remains for audited paths, but unresolved design work and owner-runtime routes remain.
- Package/runtime blockers: candidate ZIP is stale; no owner smoke is authorized.
- Owner-design blockers: ReShade ownership/accounting and remaining stateful prompt-picker boundaries need explicit future contracts.

## Next-slice queue
1. Controls truthfulness (`TPM-CONTROLS-001`). Contract: saved configuration, inferred readiness, and observed physical binding remain separate. Gate: expected fail until owner runtime.
2. ReShade ownership and accounting. Excludes controls. Contract: protected files are never silently adopted or removed and every selected game has one terminal outcome. Gate: expected fail until owner runtime.
3. Final PR #321 reconciliation and package identity review.

## Control-board rule

A remediation change is not complete until its owner IDs, slice contract, behavior contract, focused tests, runtime proof requirement, and hunk classification are recorded here and in the remediation report.
## Live re-audit correction -- 2026-09-08

This section supersedes the prior blanket `SOURCE FIXED; OWNER RUNTIME NEEDED` classification. Crosshair source evidence was false, and direct support-pack evidence confirmed duplicate `ErrorAction` failures. The candidate ZIP remains stale and is not a release gate.

| ID | Previous status | Corrected status | Evidence | Source remediation | Owner retest |
|---:|---|---|---|---|---|
| 1 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Source/test claim not contradicted by the re-audit | No | Yes, rebuilt package |
| 2 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE REMEDIATION REQUIRED | Support ZIP log repeats duplicate `ErrorAction` in startup/update paths | Yes | Yes |
| 3 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE REMEDIATION REQUIRED | Owner smoke exposed long-running/progress failure surface; package proof is invalid | Yes | Yes |
| 4 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | Existing source claim lacks trustworthy package evidence | Re-audit first | Yes |
| 5 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | Existing source claim lacks trustworthy package evidence | Re-audit first | Yes |
| 6 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE REMEDIATION REQUIRED | Thumbnail failures and duplicate `ErrorAction` are present in support log | Yes | Yes |
| 7 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | No complete current-run no-icon proof | Re-audit first | Yes |
| 8 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE REMEDIATION REQUIRED | Thumbnail fallback path hit duplicate `ErrorAction` in support log | Yes | Yes |
| 9 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | No contrary source evidence found | No | Yes |
| 10 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Selector contract remains source/test supported | No | Yes |
| 11 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE REMEDIATION REQUIRED | ReShade ownership behavior requires renewed source review before package trust | Yes | Yes |
| 12 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE REMEDIATION REQUIRED | ReShade accounting claim was accepted before package smoke | Yes | Yes |
| 13 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM INVALID / RE-AUDIT REQUIRED | Generated crosshair HTML has no `window.close()` implementation | Yes | Yes |
| 14 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM INVALID / RE-AUDIT REQUIRED | Focus fallback claim was coupled to the invalid close implementation | Yes | Yes |
| 15 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | Prompt-row source claim lacks trustworthy package evidence | Re-audit first | Yes |
| 16 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE REMEDIATION REQUIRED | Password recovery/elevation resume failed owner smoke; beginner-safe reason unproven | Yes | Yes |
| 17 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE REMEDIATION REQUIRED | Scoped repair implementation was not proven by owner smoke | Yes | Yes |
| 18 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE REMEDIATION REQUIRED | Health Check/BBHWorld repair remained an owner failure | Yes | Yes |
| 19 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE REMEDIATION REQUIRED | Source recopy behavior was not proven in affected-game flow | Yes | Yes |
| 20 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | Back routing has source tests but no trusted package proof | Re-audit first | Yes |
| 21 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE REMEDIATION REQUIRED | Repair result/accounting was not trustworthy in owner smoke | Yes | Yes |
| 22 | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE REMEDIATION REQUIRED | Post-thumbnail repair scope was not proven | Yes | Yes |
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

False prior source-fixed claims explicitly identified: IDs 2, 13, and 14. IDs 11, 12, 16-19, 21-22, and 29 require source remediation; remaining rows require renewed source/package audit before owner-only classification.

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
