# TPM-PROGRESS-RESIDUALS-002

Status: source-only slice. Owner hold: no TPM tests, Pester, gates, smoke, benchmarks, packaging, diagnostics, or screenshots until owner authorization after source completion.

Base: a07e821ed7ae791a6eca598579bd49d644427f56 (contains the progress group model, Lane G, Lane F, #369).

Item IDs R1-R6 are local labels for this slice. They are not verified owner report IDs. Owner IDs must be mapped by Main before merge.

## Scope

| ID | Residual (from TPM-PROGRESS-UI-001 residual list) | Disposition |
|---|---|---|
| R1 | AutoSync scan/extraction leaves not in a group | NO CHANGE, by design. Leaves carry grounded standalone totals. Wrapping would reduce them to stage text. |
| R2 | LaunchBox direct write has no group bar | FIXED-IN-SOURCE: `TeknoParrot-Manager.ps1:36839-36843` |
| R3 | Workflow footer overlap under group bar, especially `New-TpmSupportPackage` | SOURCE-CHANGED, runtime UNVERIFIED. Rendering is deferred during group ownership; support completion redraws in `PermanentAppendOnly` mode so later menu output cannot overwrite a pinned CursorFooter. Interactive progress width now clamps to the available console columns and truncates safely at narrow widths instead of falling back to 79 columns. This prevents width-driven wrapping; group/footer ownership remains runtime-unverified. |
| R4 | BepInEx repair-reset null return closes Final | FIXED-IN-SOURCE: `TeknoParrot-Manager.ps1:35768-35782` |
| R5 | Stall is reported on next update only | SOURCE-CHANGED: the first update after a gap displays elapsed silence and latches `Stalled`; later stage updates and terminal messages retain that duration. If no update arrives, group and standalone terminal `Final` closes classify `Stalled` and show the elapsed interval. Nested completions preserve a pending stall outcome. No live watchdog. Runtime UNVERIFIED (owner hold). |
| R6 | Cancel is result-driven; Ctrl+C is not a cancel key | SOURCE-CHANGED, runtime UNVERIFIED. `Invoke-TpmProgressGroup` classifies caught `PipelineStoppedException` including wrapped inner exceptions as Cancelled; other exceptions are Error. A pipeline stop bypassing catch closes Cancelled in `finally`. |

## R2 contract

- Wrap only the `Invoke-LaunchBoxDirectWrite` call in `Invoke-TpmProgressGroup -Title 'LaunchBox direct write'`.
- The action returns `[pscustomobject]@{ Outcome; Succeeded; Result }`. A null direct-write result and any nonempty `SkippedProfiles` close as `ACTION_REQUIRED`; `$lbWriteResult` remains the direct writer result (`$null` on failure, otherwise its result object, which may report incomplete coverage).
- `Backup-LaunchBoxFiles` and its `$null` contract are unchanged.
- The call chain contains no nested group (grep of 28540-30560 for group and operation starts returned no matches). The discovery leaf does not close a group-owned bar (module call-site guard at `TeknoParrot-Manager.ps1:17024`).

## R4 contract

- Null or non-`TPM.TransactionResult.v1` results are normalized inside the group action to `ACTION_REQUIRED` / `RESULT_UNAVAILABLE`.
- `Get-TpmProgressCloseState` now supports `Outcome='Completed'` as Final and `Outcome='Cancelled'` as Cancelled; `Outcome` values other than SUCCEEDED, Completed, NO_OP, or Cancelled close Error. This adds classifier support only; it does not establish that a current grouped workflow returns these wrapper outcomes.
- Legacy result objects with `NoOp=$true` and `Succeeded=$true` now close No-op rather than Final. Cancelled remains higher precedence when its explicit flag is set.
- Reachability correction: `Invoke-PostgresReinitializeChoice` returns Completed or Cancelled outside its internal progress group. Its only caller is ungrouped; that group wraps `Invoke-PostgresReinitializePlan` and closes before the choice result returns. The new mappings therefore do not change that workflow's bar classification.

## R3 decision

- Fix applied at the lifecycle boundary, not the shared event contract. `New-TpmSupportPackage` sets `DeferFooterWhileGroupOwned` on its own status context only. Other workflows are unchanged.
- `Render-TpmWorkflowStatus` returns without drawing while `Test-TpmProgressGroupOwned` is true, and clears any existing footer first. Events and failure state are still recorded; only the drawing is deferred.
- The support caller redraws after the group with `RendererMode = 'PermanentAppendOnly'`. This retains the final context message without pinning a CursorFooter that subsequent menu output can overwrite. Source path only; terminal overlap remains runtime-unverified under owner hold.
- While the group is open, `Render-TpmWorkflowStatus` defers drawing and retains event/failure state. The post-group append-only redraw reads that same context. Menu and recovery logic remain unchanged.

## R5 / R6

- Stall: the first `Set-TpmProgressStage` after the threshold displays elapsed silence and latches `Stalled` for group and standalone operations. Later stage updates and terminal messages retain the observed duration. If no later update arrives, terminal `Final` or `No-op` closes classify `Stalled` and label the stage with the silent duration; nested completions preserve the pending outcome. Explicit Error/Cancelled closes retain precedence. Prompt suspension excludes interactive wait. `Start-TpmProgressOperation` rejects nonpositive `StallSeconds` so invalid thresholds cannot classify ordinary updates as immediate stalls. No live timer/watchdog; blocking operations still show no live stall until return. Runtime UNVERIFIED.
- Cancel: a caught `PipelineStoppedException` or one in the caught exception's `InnerException` chain closes the group as `Cancelled`; other caught exceptions close as `Error`. A host pipeline stop that bypasses catch is closed as `Cancelled` in `finally`. Runtime Ctrl+C behavior UNVERIFIED.
- No-op: transaction results with `Outcome='NO_OP'` and legacy results with `NoOp=$true` close using the explicit `No-op` state (`NO-OP` in the progress line), not `Final`. `Outcome='Completed'` is Final; `Outcome='Cancelled'` is Cancelled. Missing results and explicit failure remain Error; unclassified legacy objects retain existing completion behavior. A nested `No-op` completion ends only that stage; the group owner remains responsible for the final group state.
- Lifecycle trace (source read, not runtime): normal return uses `Get-TpmProgressCloseState`; pipeline-stop closes Cancelled; other exceptions close Error and rethrow; bypassed host cancellation closes Cancelled in `finally`. Cleanup calls `Stop-TpmProgressAbandoned`. Runtime behavior remains unverified.
- Still open: no live stall timer or watchdog. A blocking operation cannot update the UI until it returns; stall classification is retrospective at the next stage update or terminal close. Interactive prompt duration is excluded from stall accounting. Runtime UNVERIFIED (owner hold).
- Patch (source, runtime UNVERIFIED, owner hold): `scripts/TpmProgress.psm1` `Complete-TpmProgressOperation` (`:167`): terminal state assignment is at `:194`; the closing write is in `try` (`:202-208`) and `finally` (`:209-211`) clears `$script:TpmProgressOp` even if formatting or console output throws. This closes the stale-bar window: before the patch, a throw before the `$script:TpmProgressOp = $null` assignment left the op set, so `Stop-TpmProgressAbandoned` could throw from `finally` and leave it. Boundary: the closing write still happens once; no overlay.
- Interactive prompt suspension: each current `Suspend-TpmProgressLine` caller resumes in `finally` (including `Read-HostSafe`, ReShade terminal input, PostgreSQL password prompts, and restore's raw secure prompt). Resume excludes the paused duration from group stall accounting, including when another progress update occurred during the pause. Static callsite review only; runtime behavior UNVERIFIED.
- Footer/prompt cursor correction: interactive terminal completion and `Suspend-TpmProgressLine` now use `Console.WriteLine`, which emits the host newline instead of a bare LF. This resets the cursor column before the next footer or prompt. Static source review only; visual/runtime behavior remains UNVERIFIED under the owner hold.
- Progress API correction: `Set-TpmProgressTotal` redraws when the grounded total changes, including forcing a redirected-output line even when the percentage decile is unchanged, and refreshes the stall timestamp; `Complete-TpmProgressOperation -State No-op` retains any previously registered Error, Cancelled, or Stalled outcome instead of masking it. Static source review only; no current core call site uses `Set-TpmProgressTotal`, and runtime behavior remains UNVERIFIED.
- `Set-TpmProgressTotal` now checks for and latches an elapsed stall before changing the grounded total; the check runs before its unchanged-total early return as well, so either path preserves the observed stall rather than silently hiding it. Runtime UNVERIFIED; no live timer/watchdog was added.
- Follow-up source corrections: successful FFB-plugin runs with zero files deployed expose `NoOp` so the group closes as No-op, and the workflow step is skipped rather than marked Fixed (`TeknoParrot-Manager.ps1:22713,34448-34451`).
- Health repair-search and startup game-path repair group adapters now preserve the underlying transaction `Outcome`, so `NO_OP` closes as No-op rather than Final (`TeknoParrot-Manager.ps1:34731-34734,37169-37172`). Source-only; runtime UNVERIFIED (owner hold).
- AutoSync top-level group adapters classify failed extraction or unsafe path refusal as `ACTION_REQUIRED`, actual extraction or dry-run preview work as `SUCCEEDED`, and zero-work results as `NO_OP` for both main and supplementary sources (`TeknoParrot-Manager.ps1:36970-36979,37000-37008`). Leaves remain ungrouped; only parent group outcomes changed. Source-only; runtime UNVERIFIED (owner hold).
- AutoSync tracks ZIP path-containment refusals separately (`UnsafePathSkipped`) and labels aggregate skips without the inaccurate “per-game override” explanation. Refused ZIPs are identified in item output/log, and no extraction starts for those ZIPs (`TeknoParrot-Manager.ps1:18683,18688,18752-18755,18865-18874,36976-36977,37005-37006,37021-37037`). Source-only static review; runtime UNVERIFIED (owner hold).

- If an AutoSync grouped call returns no result, the main and supplementary summaries now say `result unavailable` rather than falsely attributing the run to an unselected game list (`TeknoParrot-Manager.ps1:36968-36979,36986-37013,37025-37041`). The action outcome remains `ACTION_REQUIRED` and the bar closes `Error`; source-only, runtime UNVERIFIED.
- Current grouped no-op corrections: the dgVoodoo2 no-candidate return and ReShade removal's empty review set now declare `NoOp`; the dgVoodoo2 workflow completes as Succeeded rather than Fixed and says no changes were needed. Crosshair preserves transaction `NO_OP` as the group outcome, accepts zero-deployment no-ops, and reports zero-target selection-state completion without claiming a game-file deployment. Source-only; runtime UNVERIFIED.
- AutoSync UserProfiles backups now use a timestamp-plus-GUID folder, preventing same-second runs from reusing and overwriting an earlier backup. The caller validates the grouped helper result and distinguishes an empty backup directory from saved profile data. Native FFB `NO_OP` records the workflow step as `Skipped` with the transaction summary (`TeknoParrot-Manager.ps1:34620-34625,37018-37019,37045-37059`). Source-only; runtime UNVERIFIED (owner hold).
- Thumbnail group outcomes now retain custom-image writes and failures when the post-copy scan finds no remotely missing icons: copied images finish as successful work, copy failures close as Error, and only a truly unchanged run is No-op. Static source change; runtime behavior remains UNVERIFIED under the owner hold.
- Eggman DAT reuse now returns a structured `Path`/`Action`/`NoOp` result; initial and update callers report `Reused` rather than claiming a download or update when an already-matching file was used. The configured summary text now describes an already-present DAT. Static source change; runtime UNVERIFIED.
- Game registration and control propagation no longer treat a successfully created backup by itself as a pre-mutation failure: unchanged runs close as `NO_OP`, unresolved registration matches and no-archetype propagation are `ACTION_REQUIRED`, and control-save failures remain failures. The propagation caller now reports no-op completion without a false failure message. Static source review only; runtime UNVERIFIED.
- PostgreSQL backup now returns `NoOp` when PostgreSQL is not installed or inventory finds no existing database, provided discovery found no failures; inventory failures remain unsuccessful. The progress-group adapter therefore reports No-op rather than Final for a successful empty backup check. Static source review only; runtime UNVERIFIED.
- PostgreSQL database backup roots now include a per-run GUID in addition to the timestamp, preventing same-millisecond invocations from reusing the `pg_dump -f` destination folder. Static source review only; backup runtime remains UNVERIFIED.
- The PostgreSQL setup footer now marks the successful empty-backup step `Skipped` with a no-backup-needed summary; it keeps `Succeeded` only when database backups were actually created. Static source review only; runtime UNVERIFIED.
- PostgreSQL password-reset process handling now starts asynchronous drains for stdout and stderr before writing SQL to stdin (`TeknoParrot-Manager.ps1:15631-15650`, called at `:16304`), avoiding a full redirected output pipe blocking the synchronous input write. Runtime UNVERIFIED.
- `Test-PostgresPassword` now removes its temporary `pgpass` file in an inner `finally`, so an exception while restoring the prior `PGPASSFILE` environment value cannot skip credential-file cleanup (`TeknoParrot-Manager.ps1:15494-15506`). Source-only; cleanup runtime UNVERIFIED.


## #340 library health (source-level)

- Fixed in source: per-profile optional-coverage failures are counted (`$optionalCheckFailed` in `Invoke-LibraryHealthCheck`) and reported as "Optional-setup coverage incomplete" in the summary. Zero registered profiles no longer prints "No library path action needed".
- Library Health discovery failure is reported truthfully in source: `Invoke-LibraryHealthCheck` sets `$discoveryFailed` in its catch, and the summary prints "Profile discovery could not be completed, so no library path was checked" instead of a no-action message. Source-verified. Runtime UNVERIFIED (owner hold).
- PostgreSQL health status now queries the service state and `psql.exe` path explicitly (`TeknoParrot-Manager.ps1:27438-27442`). Query failures are logged and reported as `status unavailable` rather than inferring stopped from a missing service object. Runtime UNVERIFIED (owner hold).
- PG340 fail-closed inventory integration: the initial read-only profile pass tracks `PostgresInventoryStatus` as `Complete`, `Error`, or `Unknown`; discovery/profile-classifier failures withhold PostgreSQL need/configured counts, mark health `ACTION_REQUIRED`, and suppress setup action `P` at both UI and dispatch (`TeknoParrot-Manager.ps1:27241-27303`, `27502-27530`, `27541-27546`, `34798`). Source reviewed; runtime UNVERIFIED (owner hold).

## #338 self-update backup (source-level)

- `TeknoParrot-Manager.ps1` ~24789 (`New-ManagerUpdateBackup`, not `New-TpmUpdateBackup`): `Assert-TpmNoReparseWriteTarget` runs on the `UpdateBackups\TeknoParrotManager_<stamp>` directory before creation, and on the backup file before `Copy-Item`. Refusal throws, matching the function's existing failure contract.
- LaunchBox write-target guard: `Invoke-LaunchBoxDirectWrite` calls `Assert-TpmNoReparseWriteTarget` on `Emulators.xml`, `Platforms.xml`, and every platform file in the up-front validation block, before `Backup-LaunchBoxFiles`. A refusal returns `$null` with no backup or edit. Source-verified. Runtime UNVERIFIED (owner hold).
- LaunchBox profile enumeration now uses `-EnumerationErrorAction Stop` inside `try`; failure returns `$null` before any `Save-Xml`. Source-verified. Runtime UNVERIFIED (owner hold).
- LaunchBox per-profile read skips: the direct-write loop in `Invoke-LaunchBoxDirectWrite` records each profile whose XML `Read-Xml` fails in `$skippedProfiles`, returns them as `SkippedProfiles`, and the caller prints a yellow "could not be read and were NOT added to LaunchBox" warning with the names. Profiles with no GamePath or a missing game folder are not counted; they are intentional skips. Source-verified. Runtime UNVERIFIED (owner hold).
- LaunchBox direct-write group closes `ACTION_REQUIRED` when `SkippedProfiles` is nonempty and reports incomplete profile coverage; the existing per-profile warning remains (`TeknoParrot-Manager.ps1:37754-37796`). Source-only; runtime UNVERIFIED (owner hold).
- LaunchBox sequential-save failure handling warns that earlier files may have changed, reports the backup, and points to menu option 11; the group result remains `ACTION_REQUIRED` (`TeknoParrot-Manager.ps1:31575-31579,37761-37796`). No automatic rollback was added. Source-only; recovery remains unverified.
- LaunchBox direct-write counts game entries, Emulator/EmulatorPlatform/Platform metadata, and newly-created platform files before saving. A run with no semantic changes skips both backup creation and XML rewrites and returns `NoOp`; the group closes `NO_OP`, while incomplete profile coverage remains `ACTION_REQUIRED`. The UI omits backup/undo claims when no files were written and only shows new-game metadata guidance when entries were added (`TeknoParrot-Manager.ps1:31469-31583,37754-37796`). Source-only static correction; runtime UNVERIFIED (owner hold).
- Runtime behavior UNVERIFIED (owner hold).

## Option A: PostgreSQL password reset (source-level)

- `TeknoParrot-Manager.ps1:35335` wraps the setup caller's `Reset-PostgresPasswordAutomatically` in `Invoke-TpmProgressGroup`; the role-recovery helper at `20839-20873` uses the same wrap. The existing catch around the setup call remains in place.
- Password prompts (`Read-PostgresPasswordAttempt`) are outside the group.
- PostgreSQL elevated setup maps Windows `ERROR_CANCELLED` (1223) to a `Cancelled` group result. The group and parent both require a non-null process `ExitCode` before treating exit code zero as success, preventing a missing process result from becoming integer zero (`TeknoParrot-Manager.ps1:20670-20723`). Source-only; UAC behavior remains runtime UNVERIFIED (owner hold).
- Confirmed/replacement password prompt helpers dispose both entered `SecureString` values in `finally` before dropping references, including mismatch and early-exit paths (`TeknoParrot-Manager.ps1:20782-20837`). Source-only static review; no credential operation performed.
- PostgreSQL recovery backups now use per-run timestamp/GUID roots; evidence copy rejects reparse paths and refuses to overwrite an existing destination before ACL and source/destination hash checks (`TeknoParrot-Manager.ps1:15571-15586,15663-15723`). Source-only; backup/runtime behavior UNVERIFIED (owner hold).
- Nesting checked: no enclosing group at that call site.
- Workflow-status rendering: `Start-TpmProgressOperation` is called only from the compact-progress helper and `Invoke-TpmProgressGroup`. The reset publishes no status events, so no status render runs during the bar.
- Runtime lifecycle UNVERIFIED (owner hold).

## Forbidden regressions

- No nested groups.
- No change to AutoSync leaves (R1).
- No change to `Backup-LaunchBoxFiles` return contract.
- No new timers, watchdogs, cancel keys, or cancel flags.
- No assertion weakened in `Tests\TeknoParrot-Manager.Tests.ps1`.

## Checks for Main (not run by this lane)

- ASCII and parse check on `TeknoParrot-Manager.ps1` and `scripts\TpmProgress.psm1`.
- PSScriptAnalyzer with `PSScriptAnalyzerSettings.psd1` (Error, Warning).
- `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1`.
- `pwsh -NoProfile -File .\scripts\Run-TpmQualityGate.ps1 -ReportPath <report>`.
- Owner runtime proof for R2 and R4 is required before any claim of fixed behavior.

## Stop condition

Stop if a group action needs a prompt, a nested group, or a change to the shared footer renderer. Report back instead of widening scope.
