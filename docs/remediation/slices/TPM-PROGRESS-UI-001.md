# Slice Contract: TPM-PROGRESS-UI-001

Owner direction (universal TPM progress UI, Option A).
Feature-freeze override: applies to progress presentation only.
Coordinator decision (Main IRC correction): footer families are wrapped in groups. Footer overlap is resolved by approach (b): `Clear-TpmWorkflowFooter -Context $<status>` immediately before each group opens. This reverses the earlier "footer families excluded" decision.

## Status
- Validation status: NOT VALIDATED. Per the owner's direction, no tests, quality gates, smoke runs, benchmarks, or packaging are run until explicit owner reauthorization. No parse check was run on any changed file in Lane E.
- Visual capture: a real test-PC screenshot is required for owner approval before RC8. A capture is a visual-review artifact, not validation.
- Source basis: Lane A worktree `tpm-rc8-lane-a-progress-20261025`, snapshot `fe666fce216a5bb087140e0a27cab18567e13c96`.
- Lane E worktree: `<test-pc-repos>\tpm-rc8-lane-E-progress`, detached at `ba54ae5`. Coverage table: `docs\remediation\RC8-PROGRESS-COVERAGE-LANE-E.md`.

## Exact scope
1. New module `scripts\TpmProgress.psm1` (PS 5.1 and PS 7 compatible, ASCII only, no runtime dependencies). Exports: Start-TpmProgressOperation, Set-TpmProgressStage, Set-TpmProgressTotal, Complete-TpmProgressOperation, Stop-TpmProgressAbandoned, Test-TpmProgressStalled, Test-TpmProgressActive, Test-TpmProgressGroupOwned, Register-TpmProgressOutcome, Get-TpmProgressTitle, Format-TpmProgressLine, Format-TpmProgressBar, Test-TpmProgressOutputRedirected, Suspend-TpmProgressLine.
2. `TeknoParrot-Manager.ps1`:
   - `Write-TpmCompactExtractionProgress` (~16984) delegates to the module through `Import-TpmProgressModule`. Leaves in a group-owned bar update stage text only (16989-16995, 17003-17005).
   - `Get-TpmProgressCloseState` (17012-17029) and `Invoke-TpmProgressGroup` (17031-17046) are the group owner. Every group call site goes through `Invoke-TpmProgressGroup`.
   - `Get-TpmCompactProgressText` removed (dead code; no callers in the script). Test references remain (see Residual).
   - `Read-HostSafe` and the console text prompt path call `Suspend-TpmProgressLine` before reading input.
   - Footer families wrapped with a clear-before (see Footer overlap).

## Rules
- Totals are shown only when grounded (Total > 0). Otherwise indeterminate.
- Redirected output: no carriage returns. Plain lines written on stage change, each 10% of a grounded total, or every 5 seconds.
- Terminal output: single line rewritten with a carriage return. A prompt ends the bar line first, so the prompt never shares it.
- States: Running, Stalled, Final, Error, Cancelled.
- Group owner: one bar per top-level workflow. The owner closes it once with Final, Error, or Cancelled from the workflow result. An exception or abandonment closes it as Error from `finally`.
- Groups must not nest. Nested Start calls only increase a depth counter, and the owner's Final would not close the bar. Call sites were checked so that no group action calls another group-wrapped call site.
- Leaves inside a group never call Start, so depth stays balanced.
- Footer overlap: `Clear-TpmWorkflowFooter -Context $<status>` runs immediately before `Invoke-TpmProgressGroup` opens, so the cursor footer is not redrawn under the bar by the wrapped action.

## Lifecycle (source, NOT VALIDATED)
- Standalone (no group): `-Complete` (Final) closes the operation. A phase change closes the previous operation as Final, then starts the new one. Non-Final outcomes close the operation immediately.
- Group-owned: leaf completions and phase changes update stage text only. The owner closes the bar once.
- Completion clears the operation (module 170). The `finally` abandonment call after a successful close is therefore a no-op and cannot overwrite a Final result.
- Result mapping (`Get-TpmProgressCloseState`, 17012-17029, in order):
  1. A list result is judged by its last object.
  2. Null or no result is Error; a group does not claim success without an authoritative result.
  3. A bool result: `$true` is Final, `$false` is Error (added in this slice, line 17020). `Install-Postgres83` returns bool, so a failed install closes Error.
  4. A true `Cancelled` property closes Cancelled (17021).
  5. A transaction Outcome of SUCCEEDED or NO_OP is Final; Cancelled is Cancelled; any other Outcome is Error (17022-17026).
  6. Without an Outcome, `Succeeded` false is Error. Otherwise Final (17027-17028).
- The first non-Final leaf outcome is recorded (`Register-TpmProgressOutcome`) and becomes the owner's close state. A Final owner close reports the recorded state, so a failed leaf never ends as Final.
- Deviation from the earlier plan: `-Substage` was not used. Group ownership makes leaf completions stage-only, so the flag is redundant inside groups.
- Group bars are indeterminate in this slice. The owner never sets a grounded total, so percent is not shown. Leaf counts appear in the stage text as `(Current/Total)`.

## Stall (added in this slice; retrospective)
- `Set-TpmProgressStage` (module 121-135) measures the gap since the last change (127-130). When the gap is at least `StallSeconds` (default 60), `StalledFor` is set to that gap; otherwise it is 0.
- `Write-TpmProgressFrame` (module 188-193) renders state `Stalled` when `StalledFor -gt 0`, otherwise `Running`.
- Stall decision (option B, heartbeat): long loops that already call `Write-TpmCompactExtractionProgress` per item reset the stall clock on every item. A stall is reported only on the first update after a silent gap of at least `StallSeconds`; that frame includes the measured gap in its stage text (`no update for Ns`). No live drawing during a blocking call; a live watchdog (compiled timer callback) is not implemented and the UI must not describe stall as live.
- No new timer, runspace, or Register-ObjectEvent is added. Runtime UNVERIFIED (owner hold).
- `Test-TpmProgressStalled` (module `:184`) is now the single stall rule, called by `Set-TpmProgressStage`. Verified by grep only; runtime UNVERIFIED (owner hold).

## Cancel (added in this slice; result-driven only)
- No global cancel flag or Ctrl+C handler exists. Cancel remains workflow-local (prompt choices and result values).
- A workflow result with a true `Cancelled` flag or Outcome `Cancelled` closes the group bar as Cancelled. `Invoke-CrosshairSetup` now returns that flag when the user declines before deployment; its caller closes workflow status as Aborted without a failure acknowledgment. A leaf with `-Outcome Cancelled` is recorded through `Register-TpmProgressOutcome`.
- Ctrl+C: PowerShell runs `finally`, so `Stop-TpmProgressAbandoned` (module 173-180) closes a grouped bar as Error "Abandoned before completion". Not verified at runtime.
- No new cancel signal was invented. Owner decision needed if a user-cancel key is wanted.
- Coordinator decision: no user-cancel key is added in this slice. Cancel stays as is.

## Group call sites
Line numbers: post-edit for lines changed in this session (grep tag 4F3D); pre-edit numbering for lines not touched in this session. Re-grep `Invoke-TpmProgressGroup` for exact positions.

Previously wrapped (12):
- 32335 Owned-state migration (exit check at 32336-32339 stays outside the group)
- 34919 Support package (pre-edit numbering; footer starts inside the function, see Residual)
- 35003 Control propagation (menu)
- 35538 GPU compatibility fix
- 35587 GPU compatibility fix retry
- 36278 Register games
- 36429 Game path repair (closes Error on a failed or partial transaction, not Final)
- 36473 Thumbnail download
- 36536 Control propagation (sectioned)
- 36871 Crosshair setup (sectioned, `-WorkflowContext $null`; no footer)
- 37023 dgVoodoo2 setup (sectioned; no footer)
- 37056 GPU compatibility fix (standalone)

Added in this session (footer families, clear-before-group):
- Restore: clear 33991 (`$restoreStatus`); groups 33996 (LaunchBox), 33999 (PostgreSQL), 34001 (backup).
- Library health check: clear 34061 (`$healthStatus`); group 34062. Health repair search 34105; health repair apply 34117.
- FFB: clear 33788 and 33825 (`$status`); native group 33789; plugin group 33826.
- PostgreSQL: install clear 34443 (`$postgresStatus`), group 34444; reinitialize (resume path) clear 34462, group 34463; reinitialize (choice path) clear 34528 (`$postgresStatus`, before `Invoke-PostgresReinitializeChoice`), group 15209 (inside that function); backup clear 34472, group 34473; backup retries clear and group at 34534-34535, 34568-34569, 34658-34659, 34732-34733; game setup clear 34786, group 34787.
- Crosshair menu: clear 35054 (`$crosshairStatus`); group 35055 (`-WorkflowContext $crosshairStatus`).
- ReShade: removal group 35093 (before footer, no clear); setup clear 35221 (`$reShadeStatus`), group 35222-35232; sectioned setup group 36958-36967 (no footer there).
- dgVoodoo2 menu: clear 35434 (`$dgStatus`), group 35435-35437. Previously unwrapped; wrapped in this session.
- BepInEx update check: clear 35682 (`$bepStatus`), group 35683. BepInEx repair-reset: clear 35731, group 35732.

Not wrapped (with reason):
- LaunchBox backup `Backup-LaunchBoxFiles` (call near pre-edit 30410). Returns a path or null. A null return closes Final under the group rule, which would falsely report a failed backup. Needs a result-contract change, not a wrapper. Left unwrapped.
- Owned-state backup leaves (532-575, 1376-1415): standalone bars; no group.
- AutoSync scan/extraction leaves (4762-4979, 18018 and call sites 36181, 36203): already carry grounded standalone totals. Wrapping would reduce them to stage text.
- Transaction preflight leaves (5465 `Invoke-TpmTransactionalFileBatch` and 5534-5926): leaves inside top-level actions; no separate top-level validation workflow exists (grep of `^function` for validate/validation/batch found none). Health check is the validation-class workflow and is wrapped.
- LaunchBox direct write (36780): prompt flow, no progress loop.
- Update check (`updateStatus` footer, pre-edit 34857): not in the requested family list and not read in this lane.

## Residual (not done, not validated)
- Group bar percent: not wired. The owner must set a grounded total before group bars can show a percent.
- Stall: retrospective marker only (see Stall). Live stall not wired.
- Cancel: result-driven only. No user-cancel signal exists. Ctrl+C not verified.
- Footer events inside a group: `Render-TpmWorkflowStatus` clears/suppresses footer drawing for every workflow context while `Test-TpmProgressGroupOwned` is true. Events still update workflow state. Runtime behavior remains owner-unverified.
- `New-TpmSupportPackage` uses the same universal group-owner guard; its caller redraws the final status only after result output and follow-up, avoiding overlap with subsequent console lines. Runtime behavior remains owner-unverified.
- `Invoke-RestoreLaunchBoxBackup` returns explicit `Cancelled` results for user cancellation/declined confirmation/process-wait cancellation, and explicit `NoOp` when no backup exists. Its caller closes the progress group as Cancelled and the workflow as Aborted, or records the no-backup path as Skipped. `Invoke-RestorePostgresBackup` likewise returns explicit cancellation, no-backup `NoOp`, and empty-backup Error results; the shared caller records cancellation as Aborted and labels no-backup outcomes accurately. `Invoke-ThumbnailDownload` returns explicit results on all exits; directory-safety/setup failures, custom-copy failures, and download failures close Error, while no profiles or all icons present close Final as no-op. Custom-copy and upstream download failures are counted separately and both contribute to `Succeeded`. `Copy-TpmAutoSyncUserProfilesBackup` returns an explicit successful result with copied-item count after all copies complete; throws still close Error. Health and game-path repair groups now wrap report arrays in a `Succeeded` envelope, so an empty report set can be a known no-op rather than an absent result. Missing group results close Error; remaining group results need review for more specific Cancelled/NoOp status rather than false success.
- Interactive prompts inside wrapped actions: handled only by the line break in `Suspend-TpmProgressLine`. Not runtime-verified.
- Orphan comment: lines 16930-16933 (ZIP extraction comment) sit above `Import-TpmProgressModule` with no matching function. Owner of that comment to decide.
- Test suite: `Tests\TeknoParrot-Manager.Tests.ps1` lines 3608, 3614, and 22113 still reference `Get-TpmCompactProgressText`, which no longer exists in the worktree. Test expectation stale, owner-gated. The test file was not edited in this lane.
- Release package: `scripts\TPMReleasePackage.Core.psm1` and `RELEASE-SAFETY-CHECKLIST.md` section 4 list `TpmProgress.psm1`, but those edits are not in the Lane A or Lane E worktrees. AGENTS.md package list not updated.
- Owner runtime and test-PC screenshot: pending owner reauthorization.

## Source edits in this slice
- `scripts\TpmProgress.psm1`: group ownership (`-Group`, `Test-TpmProgressGroupOwned`, `Register-TpmProgressOutcome`), `-StageOnly`, Final close uses recorded outcome, `Suspend-TpmProgressLine`. This lane adds `StalledFor` (init at 111), gap capture in `Set-TpmProgressStage` (127-130), and the Stalled state in `Write-TpmProgressFrame` (188-193).
- `TeknoParrot-Manager.ps1`: `Write-TpmCompactExtractionProgress` group-aware leaves; `Get-TpmProgressCloseState` (bool rule at 17020, Cancelled at 17021) and `Invoke-TpmProgressGroup` (17031); `Suspend-TpmProgressLine` calls in `Read-HostSafe` and the console text prompt; group call sites listed above; footer clear-before lines listed above; `Get-TpmCompactProgressText` removed.
