# PR #321 Remediation Gate Report

- Repository root: `C:\REPOS\tpm-rc8-certified-a700d093`
- Branch: `fix/rc8-release-blockers`
- HEAD: `aa37474409b75752aaa9d729c0ee23cd52e4cd14` (accepted committed FFB checkpoint)
- Report generated UTC: governance reconciliation after the accepted FFB commit; current status is recorded below.
- Prior candidate/package identity: `C:\REPOS\tpm-rc8-candidate-output\TeknoParrot Manager v1.0 RC8.zip`
- Prior candidate byte size: `8,077,772`
- Prior candidate SHA-256: `78983F4B664DFC2E00E7E73CDA37F256EB83113256026E077F851D9589FFBD8F`
- Prior source SHA: `97047640f3ebf850418181717ae3e6b5379343e1` (prior candidate package source identity)
- Prior candidate validator: `Valid = True`
- Current source state: accepted FFB checkpoint is clean; this slice changes governance documents only.
- Current package state: no new package generated; the prior ZIP is stale and must not be reused for owner smoke.
- Remediation scope: TPM-only PR #321 historical remediation evidence, accepted FFBPlugin mode-8 checkpoint, and governance reconciliation

## Provenance

- Git status at the accepted source checkpoint: clean. The current slice is limited to this control-board/reconciliation update; no production source change is included.
- The canonical control board is `docs/remediation/PR-321-control-board.md`; the current organization slice is `docs/remediation/slices/PR-321-current-slice.md`.
- No monitor-pipeline files changed.
- No runtime, state, log, ZIP, or package artifact was created by this report.

## Owner report mapping table
This retained mapping is the historical pre-reaudit snapshot. The canonical
release-decision table appears below and supersedes this snapshot.

| ID | Owner report | Status | Files/functions | Exact test names | Runtime proof still needed |
|---:|---|---|---|---|---|
| 1 | ReShade no-change/back/cancel crash | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade action-result handling | ReShade null-result regression | Packaged `Original -> U -> B` smoke |
| 2 | Duplicate ErrorAction binding | SOURCE FIXED; OWNER RUNTIME NEEDED | Invoke-TpmWebRequestSilently and download wrappers | Focused RC8 remediation contracts | Startup, Eggman, ProfileSet, game-data, thumbnail smoke |
| 3 | Script-wide universal progress | SOURCE FIXED; OWNER RUNTIME NEEDED | Script-wide progress inventory and compact TPM progress call sites | Progress.Core focused source inventory; full Pester | Full packaged operation matrix |
| 4 | AutoSync old scan output | SOURCE FIXED; OWNER RUNTIME NEEDED | AutoSync compact progress | `truncates compact progress to constrained width and shows elapsed heartbeat` | Packaged AutoSync scan |
| 5 | GPU Fix blue PowerShell progress | SOURCE FIXED; OWNER RUNTIME NEEDED | `Invoke-GpuFixSetupWithStatus`; `Invoke-GpuFixSetup` per-profile loop; GPU menu retry path | `wraps GPU Fix in the universal workflow status lifecycle`; GPU-specific source scan: 0 `Write-Progress`, 2 compact progress calls | GPU Fix packaged smoke |
| 6 | Thumbnail bad progress | SOURCE FIXED; OWNER RUNTIME NEEDED | Thumbnail download caller | `supports opt-in no-fallback behavior for thumbnail-style 404 probes` | Packaged thumbnail smoke |
| 7 | Missing thumbnail list | SOURCE FIXED; OWNER RUNTIME NEEDED | Invoke-ThumbnailDownload | `clarifies thumbnail download is box art only, not game data` | Verify every no-icon code is listed |
| 8 | Thumbnail 404 fallback | SOURCE FIXED; OWNER RUNTIME NEEDED | Invoke-TpmDownload | `supports opt-in no-fallback behavior for thumbnail-style 404 probes` | Packaged 404 behavior |
| 9 | ReShade preview sync | SOURCE FIXED; OWNER RUNTIME NEEDED | Read-TpmReShadeTerminalProfile | `uses the live Classic Arcade CRT preview selection when U is pressed` | Actual preview selection smoke |
| 10 | ReShade selector visibility | SOURCE FIXED; OWNER RUNTIME NEEDED | ReShade selector instructions | ReShade selector contract coverage | Packaged UI smoke |
| 11 | Protected ReShade adopt/replace | SOURCE FIXED; OWNER RUNTIME NEEDED | `Get-TpmReShadeOwnershipClassification`; `Install-TpmReShadeProfileDeployment`; `Invoke-ReShadeSetup` | ReShade protected-adoption tests | Explicit adopt/replace smoke |
| 12 | ReShade all-games accounting | SOURCE FIXED; OWNER RUNTIME NEEDED | `Get-TpmReShadeApplyPreflight`; `Get-TpmReShadeApplyAccounting`; `Invoke-ReShadeSetup` | ReShade accounting tests | All-games packaged smoke |
| 13 | Crosshair browser close | SOURCE FIXED; OWNER RUNTIME NEEDED | Export-CrosshairPreview | Crosshair source-contract coverage | Actual browser P1/P2 smoke |
| 14 | Crosshair focus return | SOURCE FIXED; OWNER RUNTIME NEEDED | Crosshair focus fallback | Crosshair fallback tests | Actual focus smoke |
| 15 | Crosshair prompt row | SOURCE FIXED; OWNER RUNTIME NEEDED | `Invoke-CrosshairSetup` and `Read-TpmWorkflowInput` | `routes the P1 and P2 prompts through workflow input when a status context exists` | Constrained console smoke |
| 16 | PostgreSQL repair loop | SOURCE FIXED; OWNER RUNTIME NEEDED | PostgreSQL recovery action loop and password-mismatch retry | `keeps password mismatch inside the reset flow`; `retries protected backup after validated password` | Backup-failure R smoke |
| 17 | Affected-games repair scope | SOURCE FIXED; OWNER RUNTIME NEEDED | Repair-GamePaths and Health Check handoff | `emits compact repair progress for each profile` | One/multiple/zero affected smoke |
| 18 | Health Check no-candidate explanation | SOURCE FIXED; OWNER RUNTIME NEEDED | Health Check repair reporting | Health Check repair tests | No-candidate smoke |
| 19 | Health Check source recopy | SOURCE FIXED; OWNER RUNTIME NEEDED | Scoped AutoSync re-entry | Affected-path source contracts | Source recopy smoke |
| 20 | Health Check Back routing | SOURCE FIXED; OWNER RUNTIME NEEDED | Health Check routing | Health Check Back routing coverage | Press B in packaged runtime |
| 21 | Option 10 repair clarity | SOURCE FIXED; OWNER RUNTIME NEEDED | Repair result reporting | Repair result tests | Verify per-game accounting |
| 22 | Post-thumbnail repair scope | SOURCE FIXED; OWNER RUNTIME NEEDED | Affected-only AutoSync handoff | Scoped repair tests | Verify no optional-flow escape |
| 23 | LaunchBox Back gate | SOURCE FIXED; OWNER RUNTIME NEEDED | Optional-chain routing | LaunchBox Back coverage | Packaged B smoke |
| 24 | LaunchBox prompt wording | SOURCE FIXED; OWNER RUNTIME NEEDED | LaunchBox `P/A/F/B`, detected-root, and platform prompts | `Prompt.Core fixed choice routes`; `Read-TpmChoice validation` | Guided packaged prompt smoke |
| 25 | HyperSpin direct prompt | SOURCE FIXED; OWNER RUNTIME NEEDED | `Export-HyperSpinJson` missing-ID `G/S` choice | `Prompt.Core fixed choice routes`; source parse | Normal completion smoke |
| 26 | Invalid optional Y/N input | SOURCE FIXED; OWNER RUNTIME NEEDED | Centralized finite-choice routes plus documented stateful/exact-token/secure/path boundaries | `Read-TpmChoice validation`; `Prompt.Core fixed choice routes` | Invalid-input matrix |
| 27 | Support final prompt | SOURCE FIXED; OWNER RUNTIME NEEDED | Support `1-3` and package `O/B` routes | `Prompt.Core fixed choice routes`; SupportPackage.Tests | Packaged support prompt |
| 28 | Fatal support workflow surfacing | SOURCE FIXED; OWNER RUNTIME NEEDED | Get-TpmSupportManifestText | SupportPackage.Tests: `records Action Required freshness in the packaged manifest` | Fresh fatal-log package |
| 29 | Action Required freshness/scoping | SOURCE FIXED; OWNER RUNTIME NEEDED | New-TpmSupportPackage; EvidenceClass manifest records | SupportPackage.Tests; current/stale/ambient and plugin-inventory coverage | Complete troubleshooting intake and rebuilt support package |
| 30 | Controls truthfulness | SOURCE FIXED; OWNER RUNTIME NEEDED | `Write-ControlPropagationResults`; control-readiness engine | `Write-ControlPropagationResults` focused tests; existing controls tests | Zero-bound packaged runtime result |
| 31 | dgVoodoo2 wording | SOURCE FIXED; OWNER RUNTIME NEEDED | dgVoodoo2 result wording | No dedicated wording test | Owner wording review |
| 32 | Global consistency rule | SOURCE FIXED; OWNER RUNTIME NEEDED | `TPM-PROMPT-001` finite-choice inventory and documented stateful/exact-token/secure/path/renderer-aware boundaries | `Read-TpmChoice validation`; `Prompt.Core fixed choice routes` | Packaged consistency smoke |

## SCRIPT-WIDE UNIVERSAL PROGRESS BAR AUDIT

- `CONVERTED TO UNIVERSAL TPM PROGRESS`: compact and structured workflow paths listed in the current slice inventory.
- `JUSTIFIED NO PROGRESS SURFACE`: bounded writes and renderer-aware/stateful interaction listed in the current slice inventory.
- `NOT FIXED`: no source-side universal-progress blocker remains in the inspected paths; owner-runtime proof is still outstanding.
| Path | Function/call site | Current behavior | Disposition | Test |
|---|---|---|---|---|
| AutoSync scan | Select-GamesInteractive | Compact TPM status exists; package proof absent | SOURCE FIXED; OWNER RUNTIME NEEDED | `truncates compact progress to constrained width and shows elapsed heartbeat` |
| AutoSync extraction | Invoke-AutoSync | Mixed compact status and operation output | SOURCE FIXED; OWNER RUNTIME NEEDED | `uses compact TPM progress and preserves cleanup instead of a PowerShell progress panel` |
| Remaining progress paths | Profile readiness and process-close waits | Bounded external waits use 120-second and 30-second deadlines with actionable messages; no fake percentage is emitted | EXPLICIT BOUNDED WAIT CONTRACT | `PR #321 Progress.Core source inventory` |
| Library Health Check repair search | Repair-GamePaths / Select-GamesInteractive | Compact search/selection status and scoped repair handoff; owner package proof absent | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing repair-flow tests; owner smoke |
| GPU Fix web/check/download | Invoke-GpuFixSetup | Workflow status plus compact per-profile checks/download stages; owner package proof absent | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing GPU source contracts; owner smoke |
| Shared download tiers | Invoke-TpmDownload | Compact download status is centralized for network transfers; owner package proof absent | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing download tests; owner smoke |
| Thumbnail checks/downloads | Invoke-ThumbnailDownload | Box-art download path uses shared compact download status; owner package proof absent | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing thumbnail tests; owner smoke |
| AutoSync registration/import | Register-Games | Registration scan is covered by per-executable compact TPM progress; owner package proof absent | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing registration/source tests; owner smoke |
| AutoSync copy/move operations | Invoke-AutoSync promotion | AutoSync extraction/promotion path uses compact TPM progress; owner package proof absent | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing AutoSync tests; owner smoke |
| Library Health Check affected-games re-copy/re-extract | Health Check scoped AutoSync | Scoped AutoSync reuses the universal extraction progress path; owner package proof absent | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing scoped-flow tests; owner smoke |
| DAT checks/downloads | Eggman DAT functions | Shared compact download progress plus bounded destination-selection prompt | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing DAT tests; owner smoke |
| Eggman game data fetch | Eggman game-data functions | Shared compact download progress; bounded release/download retries | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing game-data tests; owner smoke |
| ProfileSet GitHub/default-branch query | Get-TeknoParrotProfileSet | Compact checking status surrounds default-branch/tree query and local fallback | SOURCE FIXED; OWNER RUNTIME NEEDED | Source contract; owner smoke |
| Startup update check | CheckForUpdates | Shared download/status path; startup behavior still needs packaged proof | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing updater tests; owner smoke |
| updater download | Invoke-TpmDownload update path | Shared compact download progress | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing updater tests; owner smoke |
| dgVoodoo2 download/check/deploy | Invoke-DgVoodoo2Setup | Compact scan and deployment progress added around per-game loops | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing dgVoodoo2 tests; owner smoke |
| ReShade download/check/signature/preview loading | Invoke-ReShadeSetup | Compact path-check and deployment progress added; preview remains interactive, not a long-running transfer | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing ReShade tests; owner smoke |
| FFB/network/download checks | FFB setup | Shared compact download progress and workflow status cover network/plugin stages; owner proof absent | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing FFB tests; owner smoke |
| Backup operations | Health Check/LaunchBox/PostgreSQL backup helpers | Compact progress added to Health Check and LaunchBox backup loops; PostgreSQL recovery remains workflow-step based | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing backup tests; owner smoke |
| Restore operations | UserProfiles/LaunchBox/PostgreSQL restore flows | Compact restore progress added to profile and LaunchBox restore paths; PostgreSQL restore remains workflow-step based | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing restore tests; owner smoke |
| PostgreSQL profile/database setup | Invoke-PostgresGameSetup and recovery flow | Compact per-profile setup progress plus workflow steps | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing PostgreSQL tests; owner smoke |
| Support package collection | New-TpmSupportPackage | Structured workflow status covers diagnostic, redaction, and ZIP stages; runtime proof absent | SOURCE FIXED; OWNER RUNTIME NEEDED | `SupportPackage.Tests`: `collects TPM diagnostics into one support ZIP` |
| External waits | Ensure-TeknoParrotProfilesReady; Wait-TpmForProcessClose | User-visible bounded waits with explicit deadlines and no forced close | JUSTIFIED WAITING SURFACE | `PR #321 Progress.Core source inventory` |
| LaunchBox export/write | LaunchBox functions | Compact export, backup, and restore progress added around file loops | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing LaunchBox tests; owner smoke |
| BepInEx package/download/deploy | Invoke-BepInExUpdateCheck | Compact preflight, version-check, and deployment progress added | SOURCE FIXED; OWNER RUNTIME NEEDED | Existing BepInEx tests; owner smoke |
| Crosshair/HyperSpin bounded asset writes | Crosshair and HyperSpin setup/export | Small bounded writes; no long-running progress surface needed | JUSTIFIED NO PROGRESS SURFACE | Existing crosshair/HyperSpin tests |

### Slice A -- web/download and thumbnail correctness

Owner IDs 2, 6, and 8 received a bounded source remediation. The web wrapper
continues to expose one typed request-action parameter. The shared downloader
now preserves a definitive HTTP 404 across transport fallback attempts, so
thumbnail setup retains the no-upstream-icon classification even if a later
fallback encounters an unrelated unknown network error. Non-404 transport,
validation, and integrity failures remain retry/failure outcomes. Thumbnail
progress remains compact and profile-labelled, and transient failures retain
named profile accounting for retry.

Package rebuild, owner-runtime proof, and release authorization remain
outstanding.

### Slice C -- ReShade ownership and accounting

Owner IDs 11 and 12 received a bounded source re-audit. The default Select
action protects unknown/user-owned and bundled ReShade files; explicit confirmed
Adopt/replace is the only overwrite path and remains inside the transactional
backup/rollback boundary. ReShade result actions keep protected conflicts ahead
of optional Health Check routing. All-games accounting now includes an explicit
`KeptPrevious` terminal outcome for TPM-managed profiles the operator elects to
leave unchanged, so the accounting total must still equal the selected count.

Focused ReShade coverage and the full main suite pass. Package rebuild,
owner-runtime proof, and release authorization remain outstanding.

### Crosshair close, focus, and prompt slice -- working-tree status

IDs 13, 14, and 15 were re-audited separately. ID 13 is source-fixed with a
completed non-interactive browser state after P2; ID 14 is source-fixed with
best-effort console focus and an explicit logged fallback; ID 15 is source-fixed
with workflow-aware P1/P2, confirmation, first-run, and cursor-hide prompts when
the CrosshairSetup workflow context exists. Standalone typed input remains the
fallback. Deployment remains behind terminal confirmation, and cancellation
does not deploy files. Focused crosshair coverage, package rebuild, and
owner-runtime proof remain outstanding.

## Prompt/gate/back-routing consistency audit
The Progress.Core inventory and classifications are recorded in
`docs/remediation/slices/PR-321-current-slice.md` under "Source inventory".
The prior Prompt.Core contract remains represented by the committed checkpoint.
This report retains the prior prompt audit table below for cross-slice traceability.

| Pattern | Locations audited | Converted in TPM-PROMPT-001 | Excluded with documented boundary | Tests |
|---|---|---|---|---|
| Y/N | Optional setup, readiness, and process-wait prompts | `Read-TpmYesNo` owns ordinary Y/N decisions; finite Y/N routes in this slice use centralized readers | Secure/password input, exact-token safety, path/vendor/free text, and stateful pickers | `Read-TpmYesNo validation`; `Read-TpmChoice validation` |
| Invalid input | Main, setup, dynamic path, restore, and result prompts | `Read-TpmChoice` rejects invalid finite choices and re-prompts on the same prompt | Free-text search/path/vendor/profile prompts retain specialized validation | `Read-TpmChoice validation`; `Prompt.Core fixed choice routes` |
| Finite choices | LaunchBox, HyperSpin, Support, AutoSync, DAT, startup update, BepInEx, ReShade, dgVoodoo2, GPU, FFB, Health Check, repair, PostgreSQL, staging, restore | Migrated finite choices use `Read-TpmChoice`, including dynamic path-aware arrays | Stateful picker commands remain documented design boundaries | `Read-TpmChoice validation`; `Prompt.Core fixed choice routes` |
| Back | LaunchBox, HyperSpin, Support, Health Check, setup/result menus, repair, restore | Enumerated Back/return choices use centralized validation in migrated routes | Enter-only acknowledgements, browser/process wait controls, and stateful picker `back` commands | `Prompt.Core fixed choice routes`; owner smoke outstanding |
| Skip | HyperSpin, DAT, BepInEx, optional setup, AutoSync | Finite skip/decline branches use centralized readers where feasible | Search/picker text and exact-token confirmations | `Read-TpmChoice validation`; owner smoke outstanding |
| Cancel | ReShade, dgVoodoo2, GPU, FFB, PostgreSQL, restore | Finite cancel/back routes use centralized readers where feasible | `REMOVE`, `YES`, blank path/vendor, and Enter-only safety/input contracts | `Read-TpmChoice validation`; owner smoke outstanding |
| Preview/Run | AutoSync and LaunchBox | `P/R/B` and `P/A/F/B` routes use centralized validation | ReShade terminal profile/search interaction remains renderer-aware | `Prompt.Core fixed choice routes`; existing preview tests |
| Mutation confirmation | Repair, install, update, restore, ReShade | Finite mutation branches use centralized validation | `YES` and `REMOVE` remain exact-token gates | Existing mutation tests; owner smoke outstanding |
| Optional setup gates | GPU, FFB, dgVoodoo2, BepInEx, ReShade | Finite setup/result menus use centralized validation, including dynamic path-aware choices | GPU vendor, paths, passwords, and stateful selector input | `Read-TpmChoice validation`; owner smoke outstanding |
| Stateful pickers | AutoSync game selection, combined selection, ReShade terminal selector, crosshair/browser flows | No forced one-letter rewrite | Number lists, search terms, terminal keys, redraw, and blank semantics require their own contracts | Follow-up design and runtime proof |
| HyperSpin direct prompts | Missing-emulator-ID flow | `G/S` uses `Read-TpmChoice`; no emulator ID is synthesized | Normal completion runtime proof remains absent | `Prompt.Core fixed choice routes` |
| Support package prompts | Support main and package-open completion | `1-3` and `O/B` use `Read-TpmChoice`; `O` still opens the folder | Packaged support runtime proof remains absent | `Prompt.Core fixed choice routes`; SupportPackage.Tests |

- IDs 11 and 12 are `SOURCE FIXED; OWNER RUNTIME NEEDED`; IDs 16-19 and 21-22 are now also `SOURCE FIXED; OWNER RUNTIME NEEDED`; IDs 3 and 29 remain source-remediation blockers.
 - `TPM-RESHADE-001` protects unknown/custom ReShade files by default, gates adopt/replace behind explicit action and backup, reports preflight buckets, and enforces exact final accounting.
 - `TPM-LIBRARY-HEALTH-001` limits repair and optional recopy to affected profile codes, requires saved-path read-back, and classifies every repair report exactly once.
 - `TPM-CONTROLS-001` separates saved configuration, inferred readiness, and observed physical binding; propagation reports zero verified physical bindings because TPM does not test device input.
 - PR #321 remains blocked. Owner-runtime evidence is outstanding; the candidate package identity is recorded above, and no release or owner smoke is authorized.

## Affected-games repair-flow scoping audit

- One affected game: source path uses the broken profile-code collection.
- Multiple affected games: source path passes all broken profile codes through the scoped handoff.
- Zero affected games: no repair should be offered; packaged runtime proof is absent.
- No-candidate result: source reporting exists; packaged runtime proof is absent.
- Back returns to main menu: source route exists; packaged runtime proof is absent.
- No BBHWorld hardcode exists in the inspected repair implementation.
- Full AutoSync escape: source-only evidence indicates affected-code filtering; runtime proof is absent.
- Thumbnails: no scoped-repair runtime proof.
- LaunchBox: no scoped-repair runtime proof.
- HyperSpin: no scoped-repair runtime proof.
- Controls propagation: no scoped-repair runtime proof.

- Status: SOURCE FIXED for the Slice E repair-flow cases; OWNER RUNTIME NEEDED for packaged and owner-runtime proof. One/multiple/zero/no-candidate coverage is present in source and focused tests.
### Slice E -- Library Health repair scope


Owner IDs 17, 18, 19, 21, and 22 received a bounded source re-audit.
Candidate search and reviewed apply remain limited to the affected broken
profile codes. One, multiple, zero, and no-candidate paths retain explicit
outcomes and Back routing. Repair writes require a complete profile backup and
saved-path read-back before `FIXED` is reported. Repair result accounting now
classifies every report once as fixed, candidate, or still broken. Optional
source recopy re-enters AutoSync with `OnlyProfileCodes` restricted to the
affected set, and the repair result completes before the optional thumbnail
prompt.

Package rebuild, owner-runtime proof, and release authorization remain
outstanding.
### Slice D -- PostgreSQL recovery

Owner ID 16 received a bounded PostgreSQL recovery re-audit. Failure
diagnoses now distinguish password authentication, service state, missing
database, corruption, tool availability, permission/elevation, and connection
conditions. Recovery presents explicit retry and stop/back actions, keeps
password and database mutations behind verified recovery evidence, and does
not claim completion after backup, reset, restart, or profile-save failures.
Focused tests cover password mismatch, backup failure, service-unavailable,
missing-database, corruption, reinitialize confirmation/cancel, retry/back,
and no-mutation boundaries.

Package rebuild and owner-runtime proof remain outstanding.
### Slice F -- Support evidence scoping

Owner ID 29 received a bounded support-evidence re-audit. Action Required
freshness is compared with the latest TPM log and labeled stale when older.
Current-run records remain distinct from Ambient evidence supplied or
discovered without current-workflow provenance. Game-local BepInEx logs and
metadata-only plugin inventories, including FamilyGuy-style findings, remain
Ambient; plugin payloads are not copied. Allowlist, redaction, manifest, and
ZIP-entry invariants remain covered by SupportPackage.Tests.

Package rebuild and owner-runtime proof remain outstanding.




## Support package/fatal surfacing audit

- Fatal workflow fallback when metadata is unavailable: source implementation and SupportPackage.Tests coverage exist.
- Newest Action Required inclusion: source selects newest `*ActionItems*.txt`; SupportPackage.Tests coverage exists.
- Stale evidence labeled stale: manifest source implementation exists.
- Support final prompt: SOURCE FIXED; `O/B` behavior is covered by Prompt.Core source contracts; runtime proof remains outstanding.
- Fresh owner-runtime support package proof: outstanding.

## Tests with exact counts and timestamps
| Gate/test | Exact command | Count/result | Started UTC | Finished UTC | Engine/version |
|---|---|---|---|---|---|
| Main Pester | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -CI -Output Normal` | 1030 passed, 0 failed, 0 skipped | not captured | not captured | Pester 5.7.1 |
| Slice A focused Pester | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*Invoke-TpmDownload*','*Thumbnail*','*RC8 PostgreSQL and support UX*') -CI -Output Normal` | 54 passed, 0 failed, 0 skipped, 975 not run | not captured | not captured | Pester 5.7.1 |
| SupportPackage.Tests | `Invoke-Pester -Path .\Tests\SupportPackage.Tests.ps1 -CI -Output Normal` | 41 passed, 0 failed, 0 skipped | not captured | not captured | Pester 5.7.1 |
| Controls focused Pester | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter '*Write-ControlPropagationResults*' -Output Detailed` | 3 passed, 0 failed, 0 skipped | not captured | not captured | Pester 6.1.0 |
| ReShade focused Pester | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*ReShade*','*protected adoption and accounting*','*ReShade result action priority*') -CI -Output Normal` | 192 passed, 0 failed, 0 skipped, 837 not run | not captured | not captured | Pester 5.7.1 |
| Progress.Core focused Pester | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter '*Progress.Core*' -Output Detailed` | 2 passed, 0 failed, 0 skipped at prior checkpoint | not captured | not captured | Pester 6.1.0 |
| Prompt.Core focused Pester | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter '*Prompt.Core*' -Output Detailed` | 4 passed, 0 failed, 0 skipped at prior checkpoint | not captured | not captured | Pester 6.1.0 |
| Slice D focused Pester | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*RC8 PostgreSQL*','*Postgres guided recovery*','*New-PostgresPgPassFile*') -CI -Output Normal` | 44 passed, 0 failed, 0 skipped, 986 not run | not captured | not captured | Pester 5.7.1 |
| Slice E focused Pester | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter @('*Library Health*','*Repair-GamePaths*','*repair*','*scoped*','*affected*') -CI -Output Normal` | 33 passed, 0 failed, 0 skipped, 996 not run | prior Slice E checkpoint | prior Slice E checkpoint | Pester 5.7.1 |
| Slice F focused Pester | `Invoke-Pester -Path .\Tests\SupportPackage.Tests.ps1 -FullNameFilter @('*freshness*','*ambient*','*BepInEx*','*plugin*','*manifest*','*ZIP*','*allowlist*','*redact*') -CI -Output Normal` | 16 passed, 0 failed, 0 skipped, 25 not run | not captured | not captured | Pester 5.7.1 |
| SupportPackage full Pester | `Invoke-Pester -Path .\Tests\SupportPackage.Tests.ps1 -CI -Output Normal` | 41 passed, 0 failed, 0 skipped | not captured | not captured | Pester 5.7.1 |
| Governance/source parse, ASCII, registry, PSScriptAnalyzer, diff | Final static-check commands; individual start/finish timestamps not captured | 0 production parse errors; 0 test parse errors; 0 PSScriptAnalyzer findings; production ASCII 0; diff check clean | not captured | not captured | pwsh / PSScriptAnalyzer |
| Permanent procedure gate | `.\scripts\Test-TpmPermanentProcedures.ps1 -RepoRoot . -SourcePath .\TeknoParrot-Manager.ps1 -ReportPath .\docs\remediation\PR-321-reconciliation.md` | Expected fail: owner report contains unresolved NOT FIXED items and owner-runtime evidence remains outstanding | not captured | not captured | pwsh |

## FFB mode-8 hardening round -- 2026-09-08

This committed TPM-only slice hardens the existing third-party FFBPlugin
path. The mutable upstream branch is resolved once to a validated full
commit SHA; the support table and both DLL downloads use that same SHA. DLL
acquisition is staged all-or-nothing, existing custom cache files are
preserved, and SHA256/provenance evidence is written atomically. Deployment,
ownership metadata, native-overlap cleanup, and final evidence persistence
roll back on failure. The setup result reports exact accounting and records
zero-deployment outcomes without mutating game profiles.

| FFB validation | Exact command | Count/result | Started UTC | Finished UTC | Engine/version |
|---|---|---|---|---|---|
| FFB focused Pester | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -FullNameFilter '*FFB*' -CI -Output Normal` | 40 passed, 0 failed, 0 skipped | 2026-09-08T20:58:37 | 2026-09-08T20:58:47 | Pester 5.7.1 |
| SupportPackage.Tests | `Invoke-Pester -Path .\Tests\SupportPackage.Tests.ps1 -CI -Output Normal` | 40 passed, 0 failed, 0 skipped | 2026-09-08T20:58:55 | 2026-09-08T20:59:13 | Pester 5.7.1 |
| Main Pester | `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1 -Output Normal` | 1028 passed, 0 failed, 0 skipped | not captured | not captured | Pester 5.7.1 |
| Permanent procedure gate | `Test-TpmPermanentProcedures.ps1 -RepoRoot . -SourcePath .\TeknoParrot-Manager.ps1 -ReportPath .\docs\remediation\PR-321-reconciliation.md` | Failed closed on unresolved source/owner blockers and owner-runtime evidence; no completion claim | not captured | not captured | pwsh |

Pester 5.7.1 was verified with `Get-Module Pester -ListAvailable`. Parse
checks returned zero errors, PSScriptAnalyzer returned zero Error/Warning
findings, the production script contained zero non-ASCII bytes, `git
diff --check` passed, and no generated result file remained. The existing
changelog contains 40 non-ASCII bytes outside this FFB slice. No package,
owner-runtime smoke, release, certification, commit, or push was performed.

## Static gates

- Parse: passed for production and all three gate/debug scripts; 0 errors.
- ASCII: 0 non-ASCII bytes across production, tests, report, gate/debug scripts, and registry.
- PSScriptAnalyzer: production plus all three gate/debug scripts returned 0 findings.
- `git diff --check`: passed.
- GPU-specific source scan found 0 `Write-Progress` calls and 2 per-profile `Write-TpmCompactExtractionProgress` calls in `Invoke-GpuFixSetup`; the remaining proof is packaged runtime behavior.
- InjectionHunter unavailable in this environment; no InjectionHunter result claimed.

## Hunk classification

| File | Hunk/range | Procedure ID, owner report ID, issue, or authorization | Evidence |
|---|---|---|---|
| AGENTS.md | Permanent gate checklist addition | TPM-AUTH-001, authorized governance requirement | Changed-section review |
| RELEASE-SAFETY-CHECKLIST.md | Permanent gate checklist addition | TPM-AUTH-001, TPM-TRACE-002 | Changed-section review |
| docs/ENGINEERING-WORKFLOW.md | Remediation gate workflow | TPM-OWNER-001, TPM-TRACE-001 | Changed-section review |
| quality/permanent-procedures.json | Registry | All TPM procedure IDs | JSON parse |
| docs/governance/permanent-procedures.md | Registry documentation | All TPM procedure IDs | Readability review |
| docs/templates/remediation-gate-report.md | Mandatory report schema | TPM-TRACE-001, TPM-OWNER-003 | Required-section review |
| scripts/Test-TpmPermanentProcedures.ps1 | Fail-closed report/source gate | All registry IDs | Parse, analyzer, expected-fail run |
| scripts/Run-TpmQualityGate.ps1 | Combined quality wrapper | TPM-AUTH-001, TPM-EVIDENCE-001 | Parse and analyzer |
| .github/pull_request_template.md | PR checklist | TPM-AUTH-001, TPM-TRACE-001 | File review |
| TeknoParrot-Manager.ps1 | Prompt.Core helper and finite-choice routes | TPM-PROMPT-001, owner report IDs 24-27/32, PR #321 | Production parse, focused prompt tests; owner runtime outstanding |
| Tests/TeknoParrot-Manager.Tests.ps1 | Progress.Core source inventory and bounded-wait contracts | TPM-PROGRESS-001, owner report ID 3, progress portion of ID 32, PR #321 | Focused progress tests; full suite: 1029 passed |
| Tests/TeknoParrot-Manager.Tests.ps1 | `Read-TpmChoice` behavior, Prompt.Core route contracts, and specialized-boundary inventory | TPM-PROMPT-001, owner report IDs 26/32, PR #321 | Focused prompt tests and full suite: 1029 passed; owner runtime outstanding |
| ARCHITECTURE.md | Prompt.Core finite-choice invariant and boundaries | TPM-PROMPT-001, TPM-TRACE-001, PR #321 | Changed-section review |
| ARCHITECTURE.md | Progress.Core compact/workflow/waiting contract | TPM-PROGRESS-001, TPM-TRACE-001, PR #321 | Changed-section review |
| docs/remediation/slices/PR-321-current-slice.md; docs/remediation/PR-321-control-board.md | ReShade ownership/accounting contract, prompt inventory, boundaries, statuses, and slice assignment | TPM-RESHADE-001, TPM-TRACE-001, TPM-OWNER-001, owner report IDs 11-12, PR #321 | Artifact review and focused source tests |
| README.md; QUICKSTART.md; TeknoParrot-Manager-README.txt; TeknoParrot-Manager-QuickStart.txt | Corrected LaunchBox/HyperSpin prompt instructions | TPM-PROMPT-001, owner report IDs 24-25, PR #321 | Documentation review against current routes |
| TeknoParrot-Manager.ps1 | FFB source resolution, support-table parsing, staged DLL acquisition, transactional deployment, ownership rollback, and evidence persistence | TPM-FFB-001, TPM-TRACE-001, PR #321 | Production parse, analyzer, focused FFB tests |
| Tests/TeknoParrot-Manager.Tests.ps1 | FFB source, URL, cache, hash, collision, ownership, evidence, rollback, accounting, and support contracts | TPM-FFB-001, TPM-TRACE-001, PR #321 | 40 focused FFB tests; 1028 full-suite tests |
| TeknoParrot-Manager.ps1 | `Invoke-TpmDownload` definitive-404 preservation across transport fallback | owner report IDs 2, 6, 8, PR #321 Slice A | Production parse, PSScriptAnalyzer, focused download/thumbnail tests |
| Tests/TeknoParrot-Manager.Tests.ps1 | Regression for 404 followed by unknown fallback failure | owner report IDs 6, 8, PR #321 Slice A | Slice A focused suite: 54 passed |
| ARCHITECTURE.md; TeknoParrot-Manager-CHANGELOG.txt; docs/remediation/PR-321-control-board.md; docs/remediation/PR-321-reconciliation.md | Slice A contract and evidence update | owner report IDs 2, 6, 8, PR #321 Slice A | Changed-section review |
| TeknoParrot-Manager.ps1 | ReShade all-games accounting with `KeptPrevious` terminal outcome | owner report ID 12, PR #321 Slice C | Production parse, focused ReShade tests, full main suite |
| Tests/TeknoParrot-Manager.Tests.ps1 | ReShade protected adoption, result priority, backup/rollback, and exact accounting contracts | owner report IDs 11-12, PR #321 Slice C | ReShade focused suite: 192 passed |
| ARCHITECTURE.md; TeknoParrot-Manager-CHANGELOG.txt; docs/remediation/PR-321-control-board.md; docs/remediation/PR-321-reconciliation.md | Slice C ownership/accounting contract and evidence update | owner report IDs 11-12, PR #321 Slice C | Changed-section review |
| Tests/SupportPackage.Tests.ps1 | FFB evidence allowlist and support-package collection | TPM-FFB-001, TPM-EVIDENCE-001, PR #321 | 40 support-package tests |

## Permanent procedure compliance

- Registry exists and contains 27 stable IDs.
- Report uses the required owner statuses only.
- Progress.Core source inventory is complete for inspected production paths; ID 3 is SOURCE FIXED; OWNER RUNTIME NEEDED pending packaged operation proof.
- Affected-games repair remains SOURCE FIXED; OWNER RUNTIME NEEDED.
- Support fatal/newest/stale evidence and the support `O/B` route are source/test covered; owner-runtime proof is outstanding.
- The supplied ZIP is stale relative to accepted commit `aa37474409b75752aaa9d729c0ee23cd52e4cd14` and must not be reused for owner smoke.
- This report intentionally records failed acceptance conditions rather than claiming completion.
- FFB mode-8 source identity, acquisition, deployment, evidence, ownership, rollback, and accounting invariants are accepted at commit `aa37474409b75752aaa9d729c0ee23cd52e4cd14`.

## Non-actions

No package, push, wiki, release, certification, or ARCADE/#323 action was
performed. The accepted FFB source/test checkpoint is committed as
`aa37474409b75752aaa9d729c0ee23cd52e4cd14`; this governance reconciliation
slice remains uncommitted. No monitor-pipeline work was mixed into PR #321.
No generated runtime artifact remains in the worktree.

## Runtime owner-smoke checklist

Owner-runtime proof remains required for the packaged candidate for ReShade
null/back/cancel, preview synchronization, universal progress, GPU and
thumbnail progress, crosshair close/focus/row placement, PostgreSQL retry,
LaunchBox/HyperSpin gates, affected-games repair scoping, support-package
freshness/fatal evidence, and controls truthfulness.
## Live re-audit correction -- 2026-09-08

The prior owner-report table incorrectly treated every row as `SOURCE FIXED; OWNER RUNTIME NEEDED`. That blanket status is withdrawn. The canonical corrected 32-row table is now in `docs/remediation/PR-321-control-board.md` under the same heading.

Corrections supported by new evidence:

- IDs 13 and 14 (Crosshair browser close/focus) were `SOURCE CLAIM INVALID / RE-AUDIT REQUIRED` at that earlier audit point because the generated HTML had no `window.close()` implementation; the current crosshair slice re-audits the accepted contract, which permits a completed non-interactive state with explicit close guidance instead of requiring `window.close()`.
- ID 2 (duplicate `ErrorAction`) is `SOURCE REMEDIATION REQUIRED`: direct search of `TeknoParrotManager-Support-20260908-023904.zip` found the exact error repeatedly in startup update, Eggman DAT, ProfileSet GitHub, thumbnails, Eggman game-data, and PostgreSQL-resume runs.
- ID 29 (Action Required freshness/scoping) is SOURCE FIXED; OWNER RUNTIME NEEDED. Stale Action Required labeling is tied to the latest TPM log; ambient BepInEx/plugin diagnostics are explicitly labeled as untested/current-workflow-independent evidence and remain metadata-only.
- ID 16 (PostgreSQL recovery) is SOURCE FIXED; OWNER RUNTIME NEEDED. Recovery now classifies password, service, missing-database, corruption, tool, permission, and connection failures, keeps retry/back paths explicit, and preserves no-mutation guarantees before a verified safety decision.
- ID 3 remains source-remediation required. Rows not explicitly marked source remediation require renewed source/package audit before owner-runtime-only classification.

The previous "32 owner-runtime-only" count is unreliable. The candidate package/source gate is not trustworthy for release acceptance. Re-audit and source remediation must precede package rebuild and owner-runtime retest.

That statement describes the prior bounded slice only. The subsequent crosshair slice separately re-audited IDs 13, 14, and 15, corrected the browser to a completed non-interactive state after P2, added best-effort focus reporting, routed workflow prompts with typed fallback, and retained no package, release, certification, push, or ARCADE/#323 action.
## Canonical owner-ID status table -- release decisions
This table is the sole release-decision status source for owner IDs. The
historical mapping above and earlier `NOT FIXED` prose are retained for audit
traceability but do not override these corrected classifications.

| ID | Workflow | Prior status | Corrected status | Evidence | Source remediation | Owner retest | Live record |
|---:|---|---|---|---|---|---|---|
| 1 | Startup/ReShade | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | No contrary source evidence | No | Yes | 5578628627 |
| 2 | Web/Eggman GitHub | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Wrapper now uses RequestErrorAction; prior log defect was confirmed and remediated in source | No | Yes | 5578636706; 5578669949 |
| 3 | Universal progress | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | Candidate owner evidence invalidated blanket source claim | Yes, audit first | Yes | 5578628627 |
| 4 | AutoSync progress | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | No trusted packaged scan proof | Yes, audit first | Yes | 5578628627 |
| 5 | GPU UX | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | Source contracts exist; package gate unreliable | Yes, audit first | Yes | 5578628627 |
| 6 | Thumbnail progress | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE REMEDIATION REQUIRED | Support log shows failed thumbnail requests and wrapper defect | Yes | Yes | 5578636706 |
| 7 | Thumbnail accounting | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | No complete current-run no-icon proof | Yes, audit first | Yes | 5578628627 |
| 8 | Thumbnail fallback | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE REMEDIATION REQUIRED | 404/fallback path hit duplicate ErrorAction before slice | Yes | Yes | 5578636706 |
| 9 | ReShade preview sync | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Source/test evidence not contradicted | No | Yes | 5578628627 |
| 10 | ReShade selector | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Selector contract remains source-supported | No | Yes | 5578628627 |
| 11 | ReShade protected ownership | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE REMEDIATION REQUIRED | Ownership claim requires source re-audit before trust | Yes | Yes | 5578628627 |
| 12 | ReShade accounting/result | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE REMEDIATION REQUIRED | Accounting accepted before failed package smoke | Yes | Yes | 5578628627 |
| 13 | Crosshair close | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Export-CrosshairPreview now enters a completed non-interactive state after P2 and gives explicit return/close guidance | No | Yes | 5585999038 |
| 14 | Crosshair focus | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Best-effort SetForegroundWindow return is logged when unavailable; terminal workflow remains usable | No | Yes | 5585999038 |
| 15 | Crosshair prompt row | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Workflow-aware P1/P2, confirmation, first-run, and cursor-hide prompts with typed fallback | No | Yes | 5585999038 |
| 16 | PostgreSQL recovery | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Categorized resume reasons and reachable P path; focused tests pass | No | Yes | 5578669949 |
| 17 | Health Check scope | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE REMEDIATION REQUIRED | BBHWorld/affected-game scope not proven | Yes | Yes | 5578628627 |
| 18 | Health Check no-candidate | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE REMEDIATION REQUIRED | Owner failure remains unresolved | Yes | Yes | 5578628627 |
| 19 | Health Check recopy | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE REMEDIATION REQUIRED | Scoped source recopy not proven | Yes | Yes | 5578628627 |
| 20 | Health Check Back | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | Source route exists; package proof unreliable | Yes, audit first | Yes | 5578628627 |
| 21 | Repair result clarity | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE REMEDIATION REQUIRED | Repair accounting not trustworthy | Yes | Yes | 5578628627 |
| 22 | Post-thumbnail repair | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE REMEDIATION REQUIRED | Affected-only handoff not proven | Yes | Yes | 5578628627 |
| 23 | LaunchBox Back | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | Packaged Back proof absent | Yes, audit first | Yes | 5578628627 |
| 24 | LaunchBox prompts | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | Prompt source tests exist; package gate unreliable | Yes, audit first | Yes | 5578628627 |
| 25 | HyperSpin missing ID | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | Provisional source pass only | Yes, audit first | Yes | 5578628627 |
| 26 | Optional Y/N | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | Central contract requires renewed all-row audit | Yes, audit first | Yes | 5578628627 |
| 27 | Support prompt | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | Packaged prompt proof absent | Yes, audit first | Yes | 5578628627 |
| 28 | Fatal support evidence | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE FIXED; OWNER RUNTIME NEEDED | Manifest/focused source coverage exists | No | Yes | 5578628627 |
| 29 | Support freshness/scoping | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE REMEDIATION REQUIRED | Stale label works; ambient evidence scope is incomplete | Yes | Yes | 5578628627 |
| 30 | Controls truthfulness | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | Focused tests exist; owner proof pending | Yes, audit first | Yes | 5578628627 |
| 31 | dgVoodoo2 wording | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | No dedicated wording proof | Yes, audit first | Yes | 5578628627 |
| 32 | Global consistency | SOURCE FIXED; OWNER RUNTIME NEEDED | SOURCE CLAIM REQUIRES RE-AUDIT | Prior blanket count withdrawn | Yes, audit first | Yes | 5578628627 |

Product requirements retained for subsequent slices:

- Collect allowlisted TeknoParrot logs and TeknoParrotUI Troubleshooting output, preserving exact shader/display fields and current/ambient/stale classification.
- Preserve affected-game profile evidence snapshots without copying raw unrelated UserProfiles.
- Organize TPM-owned state under `<TeknoParrotRoot>\TeknoParrotManager` with safe migration and conflict preservation.
- Use real deployed ReShade shader/effect names in friendly names or Details.
- Read and preserve TeknoParrot-native CRT/SSAA/display settings; never mutate them in ReShade setup.
- Harden the existing mode-8 FFBPlugin path; do not add a parallel implementation.

First remediation slice completed at source/test level: PostgreSQL recovery reason classification plus duplicate-ErrorAction web-wrapper remediation. No package or runtime proof claimed.

## Library Health repair slice -- working-tree update

This uncommitted TPM-only slice addresses the source-remediation details for
IDs 17-22 while retaining `SOURCE FIXED; OWNER RUNTIME NEEDED` as the target
status after a fresh package/runtime audit. The repair path now emits explicit
`CANDIDATE`, `FIXED`, and `STILL BROKEN` outcomes, verifies saved GamePath
values by reading profiles back, keeps Health Check search and AutoSync
re-copy scoped to affected profiles, redacts before/after path evidence, and
places thumbnail prompts after the repair result. Registration already-set
profiles are summarized, and Raw Thrills path warnings now explain parent
folder shortening and saved-GamePath update steps. Focused Library Health
tests passed for the source working tree. No package, owner smoke, release, or
certification evidence was produced by this slice.
