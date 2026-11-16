# RC8 Progress Coverage -- Lane E

Slice: TPM-PROGRESS-UI-001 (`docs\remediation\slices\TPM-PROGRESS-UI-001.md`).
Worktree: `<test-pc-repos>\tpm-rc8-lane-E-progress`, detached at `ba54ae5`.
Status: NOT VALIDATED. Static reads and source edits only. No parse check, test, gate, smoke, or runtime run was made (owner hold).

## Conventions
- Status codes:
  - WRAPPED-GROUPED: the workflow runs inside `Invoke-TpmProgressGroup`. One operation bar per workflow.
  - WRAPPED-GROUPED-GROUNDED-TOTAL: the group has a grounded total. No family reaches this state in this lane. Group bars are indeterminate.
  - NOT-WRAPPED (reason): left standalone or unwrapped, with the reason.
- STALL: reported on next update only (option B, heartbeat). `Set-TpmProgressStage` gap (module 127-130); `Write-TpmProgressFrame` (188-193). Per-item progress calls in long loops reset the clock. Y = a grouped bar marks Stalled on the first update after a silent gap. NOT live detection; no timer or callback is implemented.
- CANCEL: result-driven only. Y = the group closes Cancelled when the action returns `Cancelled` or Outcome `Cancelled` (17021, 17023). N = no cancel path. No cancel signal exists in the script.
- Line numbers: post-edit (tag `4F3D`, then `7D69` for the PostgreSQL clear added at 34528) for lines changed this session. Pre-edit numbering for lines not touched. Re-grep `Invoke-TpmProgressGroup` to confirm positions.

## Footer overlap resolution (approach b)
Each footer-family group is preceded by `[void](Clear-TpmWorkflowFooter -Context $<status>)`. This suspends the cursor footer before the bar opens. Clear sites:
- FFB: 33788 (`$status`), 33825 (`$status`).
- Restore: 33991 (`$restoreStatus`).
- Health: 34061 (`$healthStatus`).
- PostgreSQL: install 34443, reinit (resume) 34462, backup 34472, backup retries 34534, 34568, 34658, 34732, reinit (choice) 34528, game setup 34786 (all `$postgresStatus`).
- Crosshair: 35054 (`$crosshairStatus`).
- ReShade setup: 35221 (`$reShadeStatus`). ReShade removal (35093) has no footer and no clear.
- dgVoodoo2: 35434 (`$dgStatus`).
- BepInEx: update check 35682 (`$bepStatus`); repair-reset 35731.

## Close-state rule (added this slice)
`Get-TpmProgressCloseState` (17012-17029):
- `$true` -> Final. `$false` -> Error (line 17020). Needed for `Install-Postgres83`, which returns bool.
- `Cancelled` property true -> Cancelled (17021). Outcome SUCCEEDED/NO_OP -> Final; Outcome Cancelled -> Cancelled; other Outcome -> Error (17022-17026). Succeeded false -> Error; otherwise Final (17027-17028).
- Null or no result -> Final (unchanged). This is a residual (see below).

## Workflow family status

| Family | Status | Group call sites (file:line) | STALL | CANCEL |
|---|---|---|---|---|
| Setup | WRAPPED-GROUPED | FFB native 33789, plugin 33826; crosshair 35055; dgVoodoo2 menu 35435; GPU fix 35538, 35587, 37056; ReShade setup 35222, sectioned 36958 | Y | Y (result) |
| Install | WRAPPED-GROUPED | PostgreSQL install 34444 (bool rule 17020); ReShade install via setup 35222 | Y | Y (result) |
| Scan | NOT-WRAPPED (reason: AutoSync scan leaves 4762-4979 already carry grounded standalone totals; wrapping would reduce them to stage text) | -- | N/A | N/A |
| Discovery | WRAPPED-GROUPED | Register games 36278; health check discovery via 34062 | Y | Y (result) |
| Download | WRAPPED-GROUPED | Thumbnail download 36473; dgVoodoo2 download inside 35435-35437 | Y | Y (result) |
| Extract | WRAPPED-GROUPED (owner) | Extraction leaves `Write-TpmCompactExtractionProgress` (16984; group-aware 16989-16995, 17003-17005) inside the group owners above | Y | Y (result) |
| Migration | WRAPPED-GROUPED | Owned-state migration 32335 (exit check 32336-32339 outside the group) | Y | Y (result) |
| Backup | WRAPPED-GROUPED (PostgreSQL); NOT-WRAPPED (LaunchBox, owned-state) | PostgreSQL backup 34473, retries 34535, 34569, 34659, 34733. LaunchBox `Backup-LaunchBoxFiles` (near pre-edit 30410): NOT-WRAPPED because it returns a path or null; a null close state would falsely report Final. Owned-state backup leaves (532-575, 1376-1415): leaves, standalone bars | Y (PG) | Y (PG, result) |
| Restore | WRAPPED-GROUPED | LaunchBox restore 33996; PostgreSQL restore 33999; backup restore 34001 | Y | Y (result) |
| Repair | WRAPPED-GROUPED | Game path repair 36429; health repair search 34105; health repair apply 34117; PostgreSQL reinit 34463 and 15209; BepInEx repair-reset 35732 | Y | Y (result) |
| PostgreSQL | WRAPPED-GROUPED | Install 34444; reinit (resume) 34463; reinit (choice) 15209; backup 34473 and retries; game setup 34787 | Y | Y (result) |
| ReShade | WRAPPED-GROUPED | Removal 35093; setup 35222-35232; sectioned setup 36958-36967 | Y | Y (result) |
| Health check | WRAPPED-GROUPED | Library health check 34062; repair 34105, 34117 | Y | Y (result) |
| Validation | NOT-WRAPPED (reason: no standalone validation workflow exists; grep of top-level functions for validate/validation/batch found none). Transaction preflight leaves `Invoke-TpmTransactionalFileBatch` (5465) and 5534-5926 are leaves inside top-level actions. Health check is the validation-class workflow and is wrapped. | -- | N/A | N/A |
| Batch | WRAPPED-GROUPED (control propagation); NOT-WRAPPED (transaction leaves, 5465) | Control propagation menu 35003, sectioned 36536 | Y | Y (result) |

Not in the requested list:
- Update check footer (`$updateStatus`, pre-edit 34857): not read in this lane. Not in scope.
- Support package 34919 (pre-edit numbering): wrapped. Its footer starts inside `New-TpmSupportPackage`, so overlap remains (see residuals).

## Residuals (not done, not validated)
1. Group bar percent: not wired. The owner never sets a grounded total at group level. Group bars are indeterminate.
2. Live stall: not implemented by decision (option B, heartbeat). Stall is reported on the first update after a silent gap; the UI must not describe it as live. Runtime UNVERIFIED (owner hold).
3. Cancel: result-driven only. No user-cancel signal exists. Ctrl+C is closed as Error "Abandoned before completion" by `finally` (module 173-180); not verified at runtime.
4. Footer events inside a group (FailureRaised, WaitingStarted, WorkflowCompleted, WorkflowAborted, ShowTelemetry) redraw the footer through `Publish-TpmWorkflowStatusEvent`. A redraw during a wrapped action can appear under the bar. Not runtime-verified (owner hold).
5. `New-TpmSupportPackage` (34919) starts its own footer inside the function. It cannot be cleared before its group opens.
6. Null result closes Final: BepInEx repair-reset (35732) can return null, then the code substitutes an ACTION_REQUIRED result after the group. Its bar reads Final while the outcome is ACTION_REQUIRED. Owner decision needed.
7. Interactive prompts inside wrapped actions: handled only by the line break in `Suspend-TpmProgressLine`. Not runtime-verified.
8. Tests: `Tests\TeknoParrot-Manager.Tests.ps1` lines 3608, 3614, 22113 reference `Get-TpmCompactProgressText`, which was removed. Stale; owner-gated; not edited.
9. Release package: `TpmProgress.psm1` is not yet in `TPMReleasePackage.Core.psm1` or RELEASE-SAFETY-CHECKLIST.md section 4. AGENTS.md package list not updated.
10. Orphan comment at 16930-16933 above `Import-TpmProgressModule`. Owner of that comment to decide.
11. Owner runtime proof and test-PC screenshot: pending owner reauthorization.

## Changed files (SHA256 recorded in the Lane E reply, not here)
- `TeknoParrot-Manager.ps1`
- `scripts\TpmProgress.psm1` (untracked)
- `docs\remediation\slices\TPM-PROGRESS-UI-001.md` (untracked)
- `docs\remediation\RC8-PROGRESS-COVERAGE-LANE-E.md` (untracked, this file)
