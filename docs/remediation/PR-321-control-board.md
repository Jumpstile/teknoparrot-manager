# PR #321 TPM Remediation Control Board

Status: blocked. This board is the source of truth for TPM remediation state.

## Current repository state

- Root: `C:\REPOS\tpm-rc8-certified-a700d093`
- Branch: `fix/rc8-release-blockers`
- HEAD: `6c511915c85793833db74472c105d48449982537`
- Worktree: dirty; the prompt slice is uncommitted.
- Candidate ZIP: `C:\REPOS\tpm-rc8-candidate-output\TeknoParrot Manager v1.0 RC8.zip`.
- Candidate freshness: stale relative to uncommitted source changes; package rebuild is not authorized.
- Permanent procedure gate: expected fail until unresolved owner findings, stale candidate identity, and owner-runtime evidence are resolved.

## Status rules

Allowed statuses are exactly: `NOT FIXED`, `SOURCE FIXED; OWNER RUNTIME NEEDED`, `FIXED + TESTED`, and `DEFERRED BY OWNER`.

## Owner report table

| ID | Owner-visible failure | Expected behavior | Current status | Owning subsystem | Source/functions | Tests | Runtime proof needed | Next action | Slice assignment |
|---:|---|---|---|---|---|---|---|---|---|
| 1 | ReShade no-change/back/cancel crash | Safe no-op and correct return routing | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade | ReShade action results | Existing ReShade regressions | Packaged U/B smoke | Owner runtime | ReShade follow-up |
| 2 | Duplicate error handling | One authoritative error policy | SOURCE FIXED; OWNER RUNTIME NEEDED | Downloads | Web/download wrappers | RC8 remediation contracts | Startup/download smoke | Owner runtime | Download follow-up |
| 3 | Missing universal progress | Every long-running path has TPM progress or explicit instant reason | NOT FIXED | Progress/status | Script-wide inventory | Focused progress contracts | Full packaged operation matrix | Complete audit and runtime proof | Progress slice |
| 4 | AutoSync scan output | Compact bounded progress | SOURCE FIXED; OWNER RUNTIME NEEDED | Progress/status | Select-GamesInteractive | Compact progress tests | AutoSync smoke | Owner runtime | Progress slice |
| 5 | GPU Fix progress | Compact status without PowerShell panel | SOURCE FIXED; OWNER RUNTIME NEEDED | Progress/status | Invoke-GpuFixSetup | GPU source contracts | GPU Fix smoke | Owner runtime | Progress slice |
| 6 | Thumbnail progress | Accurate compact download status | SOURCE FIXED; OWNER RUNTIME NEEDED | Progress/status | Invoke-ThumbnailDownload | Thumbnail tests | Thumbnail smoke | Owner runtime | Progress slice |
| 7 | Missing thumbnail list | Complete no-icon accounting | SOURCE FIXED; OWNER RUNTIME NEEDED | Progress/status | Thumbnail reporting | Thumbnail tests | Full no-icon matrix | Owner runtime | Progress slice |
| 8 | Thumbnail fallback | Defined 404 behavior | SOURCE FIXED; OWNER RUNTIME NEEDED | Progress/status | Invoke-TpmDownload | Fallback tests | 404 smoke | Owner runtime | Download follow-up |
| 9 | ReShade preview sync | Preview reflects live selection | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade | Read-TpmReShadeTerminalProfile | Preview contract | Preview smoke | Owner runtime | ReShade follow-up |
| 10 | ReShade selector visibility | Selector instructions remain visible | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade | Selector UI | Selector contracts | UI smoke | Owner runtime | ReShade follow-up |
| 11 | Protected ReShade ownership | Adopt/replace safely | NOT FIXED | ReShade | Ownership reconciliation | Ownership tests | Adopt/replace smoke | Design and implement | ReShade follow-up |
| 12 | ReShade accounting | All games and outcomes counted | NOT FIXED | ReShade | Result accounting | Result tests | All-games smoke | Complete accounting audit | ReShade follow-up |
| 13 | Crosshair browser does not close | Browser closes safely | SOURCE FIXED; OWNER RUNTIME NEEDED | Crosshair | Export-CrosshairPreview | Crosshair contracts | Browser smoke | Owner runtime | Crosshair follow-up |
| 14 | Crosshair focus does not return | Focus returns to terminal | SOURCE FIXED; OWNER RUNTIME NEEDED | Crosshair | Crosshair focus fallback | Crosshair contracts | Focus smoke | Owner runtime | Crosshair follow-up |
| 15 | Crosshair prompt placement | P1/P2 rows are usable | SOURCE FIXED; OWNER RUNTIME NEEDED | Crosshair | Crosshair setup/input | Crosshair contracts | Constrained console smoke | Owner runtime | Crosshair follow-up |
| 16 | PostgreSQL repair loop | Backup/retry/reset is bounded | SOURCE FIXED; OWNER RUNTIME NEEDED | PostgreSQL | PostgreSQL recovery | Recovery tests | Repair smoke | Owner runtime | PostgreSQL follow-up |
| 17 | Affected-games repair scope | Only affected games are repaired | SOURCE FIXED; OWNER RUNTIME NEEDED | Repair/scoping | Repair-GamePaths | Repair matrix | One/multiple/zero smoke | Owner runtime | Repair follow-up |
| 18 | Health Check no-candidate explanation | No-candidate state is clear | SOURCE FIXED; OWNER RUNTIME NEEDED | Repair/scoping | Health Check reporting | Repair tests | No-candidate smoke | Owner runtime | Repair follow-up |
| 19 | Health Check source re-copy | Source re-copy is scoped | SOURCE FIXED; OWNER RUNTIME NEEDED | Repair/scoping | Scoped AutoSync | Scoped-flow tests | Re-copy smoke | Owner runtime | Repair follow-up |
| 20 | Health Check Back routing | Back returns safely | SOURCE FIXED; OWNER RUNTIME NEEDED | Prompts/navigation | Health Check routing | Routing tests | Back smoke | Owner runtime | Prompt follow-up |
| 21 | Option 10 repair clarity | Repair outcomes are explicit | SOURCE FIXED; OWNER RUNTIME NEEDED | Repair/scoping | Repair result reporting | Result tests | Result smoke | Owner runtime | Repair follow-up |
| 22 | Post-thumbnail repair scope | Optional flows do not escape scope | SOURCE FIXED; OWNER RUNTIME NEEDED | Repair/scoping | Affected-only handoff | Scoped-flow tests | Scope smoke | Owner runtime | Repair follow-up |
| 23 | LaunchBox Back ignored | Back is honored | SOURCE FIXED; OWNER RUNTIME NEEDED | Frontend exports | LaunchBox routing | Back coverage | Packaged B smoke | Owner runtime | Frontend follow-up |
| 24 | LaunchBox prompt wording | Prompt explains action and consequence | SOURCE FIXED; OWNER RUNTIME NEEDED | Frontend exports | LaunchBox prompts | Prompt.Core route contracts | Guided packaged prompt smoke | Owner runtime | Prompt.Core |
| 25 | HyperSpin direct prompt | Safe choice and normal completion | SOURCE FIXED; OWNER RUNTIME NEEDED | Frontend exports | Export-HyperSpinJson | Source contracts | Normal completion smoke | Owner runtime | Frontend follow-up |
| 26 | Invalid optional input | Invalid values reprompt consistently | NOT FIXED | Prompts/navigation | Read-TpmChoice/Read-TpmYesNo migration; remaining stateful picker boundaries documented | Read-TpmChoice validation; prompt route contracts | Invalid-input matrix | Complete remaining finite-choice audit and owner smoke | Prompt.Core |
| 27 | Support package final prompt | Final prompt is clear | SOURCE FIXED; OWNER RUNTIME NEEDED | Support package | Support menu and package-open route | Prompt.Core route contracts; SupportPackage.Tests | Packaged support smoke | Owner runtime | Prompt.Core |
| 28 | Support fatal workflow surfacing | Fatal evidence surfaces | SOURCE FIXED; OWNER RUNTIME NEEDED | Support package | Support manifest | SupportPackage.Tests | Fatal-log smoke | Owner runtime | Support follow-up |
| 29 | Action Required freshness mismatch | Newest evidence is labeled | SOURCE FIXED; OWNER RUNTIME NEEDED | Support package | Support package freshness | SupportPackage.Tests | Multiple-report smoke | Owner runtime | Support follow-up |
| 30 | Controls truthfulness | Zero-bound results never imply verified readiness | NOT FIXED | Controls truthfulness | Controls result reporting | Controls tests | Zero-bound runtime result | Complete result audit | Controls follow-up |
| 31 | dgVoodoo2 wording | Results explain deployment state | SOURCE FIXED; OWNER RUNTIME NEEDED | Progress/status | dgVoodoo2 result wording | Existing tests | Owner wording review | Owner runtime | Progress slice |
| 32 | Global consistency rule | Every enumerated prompt uses the central contract or has a documented design boundary | NOT FIXED | Prompts/navigation | TPM-PROMPT-001 inventory; centralized feasible routes; stateful picker boundaries remain | Prompt.Core helper/route contracts | Packaged consistency smoke | Finish remaining finite-choice audit and owner smoke | Prompt.Core |

## Subsystem grouping

- Progress/status: 2-8, 31, and unresolved 3.
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

- Source blockers: IDs 3, 11, 12, 26, 30, and 32 remain NOT FIXED.
- Test blockers: focused behavior coverage for the remaining global prompt contract and owner-runtime routes is incomplete.
- Procedure-gate blockers: unresolved statuses, missing owner-runtime evidence, stale candidate identity, and current-slice enforcement are not yet satisfied.
- Package/runtime blockers: candidate ZIP is stale; no owner smoke is authorized.
- Owner-design blockers: ReShade ownership, controls truthfulness, and the remaining stateful prompt-picker boundaries need explicit future contracts.

## Next-slice queue

1. Prompt.Core + global input behavior (`TPM-PROMPT-001`). Excludes ReShade ownership/accounting, controls, packaging, and owner smoke. Contract: invalid finite choices reprompt through `Read-TpmChoice`; exact-token safety, free-text, secure input, renderer-aware input, and stateful pickers remain documented boundaries. Tests: focused prompt contracts before and after implementation. Gate: expected fail on unrelated blockers. Stop when every prompt is classified and IDs 26 plus the scoped ID 32 routes have source/test evidence.
2. Progress/status global inventory. Excludes prompt redesign and runtime packaging. Contract: each long-running path has compact TPM progress or a documented instant/bounded reason. Tests: source inventory plus focused path tests. Gate: expected fail on owner-runtime evidence until package proof exists.
3. ReShade ownership and accounting. Excludes prompt/progress cleanup. Contract: protected files are never silently adopted or removed and every selected game has one terminal outcome. Tests: ownership matrix and result accounting tests. Gate: expected fail until owner smoke.
4. Controls truthfulness. Excludes device certification. Contract: output distinguishes saved configuration, inferred readiness, and verified physical binding. Tests: zero/mixed/failure result contracts. Gate: expected fail until runtime observation.

## Control-board rule

A remediation change is not complete until its owner IDs, slice contract, behavior contract, focused tests, runtime proof requirement, and hunk classification are recorded here and in the remediation report.
