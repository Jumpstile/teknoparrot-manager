# TPM Remediation Slice Contract

## 1. Slice name

- Name: PostgreSQL temporary trust-rule rollback must be durable across TPM processes
- Contract ID: TPM-RC8-LANE-S-PG-TRUST-DURABLE-001
- Issue/PR: none assigned in this lane (owner report wording is included in section 2)

## 2. Owner report IDs included

- IDs: none assigned by number in this lane; wording taken from the Lane G residual (TPM-RC8-LANE-G-PG-FAILCLOSED-001, section 4 design boundary).
- Exact owner-visible failure:
  - A new TPM process does not know about an earlier session's manual-recovery flag. If the temporary `host all postgres 127.0.0.1/32 trust` line was written and the restore did not complete, a later process relies only on the AUTHENTICATION_POLICY_UNSAFE guard, which is not a durable record of the pending rollback.

## 3. Explicit exclusions

- Owner IDs not included: all others.
- Excluded: no change to the recovery order (stop, trust line, ALTER ROLE, restore, restart, verify); no change to `postgresql.conf` handling; no new backup format; no change to the timestamped backup directory layout; no change to the Lane G restore and wording logic beyond the branches listed in section 5.
- Excluded: no startup banner or new menu entry. Detection runs before every PostgreSQL password operation, which satisfies the requirement that a refused operation names the file.
- Excluded: no lock or cross-process mutual exclusion. A narrow race between two concurrent TPM processes remains and is recorded in section 4.

## 4. Behavior contract

- Current gap (base a07e821):
  - The in-session flag `$script:PostgresManualRecoveryRequired` is the only record of a failed rollback. `Test-PostgresManualRecoveryRequired` (15499-15501) reads only that variable.
- Expected behavior:
  - Marker location: `<PSScriptRoot>\PostgresRecoveryBackups\PostgresTrustRule.marker.json`. The directory is the existing recovery backup root; the marker is not inside a timestamped directory, so a new process can find it without knowing the timestamp.
  - Marker content (UTF-8 without BOM, JSON): `Schema` = `TPM.PostgresTrustRuleMarker.v1`, `Guid` (new GUID per write), `HbaPath` (live file), `BackupHbaPath` (`<RecoveryBackup.Path>\PostgreSQL\pg_hba.conf`), `OriginalSha256` (the verified recorded hash of the pre-change file), `CreatedUtc`.
  - Write order: the marker is written after the drift and unsafe-trust guards and immediately before the `WriteAllText` that writes the temporary trust rule. A marker write failure returns before the trust line is written. Write goes to a temporary file in the same directory, then `Move-Item -Force` to the marker path, then read-back and parse must match the written Guid and hash.
  - Detection (`Get-PostgresTrustRuleMarkerState`), run before every password operation:
    - marker absent (`ItemNotFoundException` only) = None;
    - marker present but unreadable, not valid JSON, schema or fields invalid, or any other access error = Error (fail closed);
    - live `HbaPath` unreadable or missing = Error;
    - live SHA-256 differs from `OriginalSha256` = Required;
    - live SHA-256 equals `OriginalSha256` = the rollback is verified; the marker is removed; a failed removal = Error.
  - `Test-PostgresManualRecoveryRequired` returns true when the in-session flag is set OR the durable state is Required or Error. The three existing guards (`Reset-PostgresPasswordAutomatically`, `Invoke-PostgresSelectedPasswordRecovery`, `Invoke-RestorePostgresBackup`) return ACTION_REQUIRED / MANUAL_RECOVERY_REQUIRED before any password operation, with a message naming the live file, the backup file, and the marker path.
  - Setup pass (top-level, before the service-state read): if the same check is true, the pass stops with ACTION_REQUIRED wording, no service change, and no password operation (`Test-PostgresPassword`, `Invoke-PostgresGameSetup`, recovery calls).
  - Clear after verified restore: the marker is removed only after `Restore-PostgresHbaFromBackup` succeeds and its read-back hash equals `OriginalSha256`. Removal is done in the success path and in the catch-path restore. If removal fails after a verified restore, the result is ACTION_REQUIRED / MANUAL_RECOVERY_REQUIRED (ReasonCode), the in-session flag is set to the marker path, and the summary names the marker path. PostgreSQL is restarted by the existing restart logic, because the authentication policy was restored and verified.
- Forbidden regressions:
  - No password operation while the durable state is Required or Error.
  - No marker deletion without a hash match against `OriginalSha256`.
  - No fail-open: a read error on the marker or the live file must never return None.
  - No change to the AUTHENTICATION_POLICY_UNSAFE guard (15637-15640); it stays in place.
  - No change to existing ReasonCodes; no new names for helpers that exist (`Restore-PostgresHbaFromBackup`, `PostgresManualRecoveryRequired`, `AUTHENTICATION_POLICY_UNSAFE`).
- Design boundaries and deliberate exclusions:
  - Race: a second TPM process that starts between the marker write and the trust-line write sees the live hash equal to the original and removes the marker. The window is narrowed to the adjacent lines but not closed. Recorded as residual; no lock added.
  - The marker is trusted as a local file written by TPM; no signature.
  - If the live file was moved or the install directory changed, the recorded `HbaPath` is still the file checked; a missing file is Error and blocks operations until the user resolves it.
  - The serviceStopFailed branch (existing catch logic) is unchanged; a running server whose trust rule could not be restored remains exposed and is outside this slice.

## 5. Source/function ownership

- Files: TeknoParrot-Manager.ps1 (only)
- Functions/regions (base a07e821 line numbers):
  - New helpers after `Get-PostgresRecoveryBackupState` (15481-15497) and before `Test-PostgresManualRecoveryRequired` (15499-15501): `Get-PostgresRecoveryBackupRoot`, `Get-PostgresTrustRuleMarkerPath`, `Write-PostgresTrustRuleMarker`, `Get-PostgresTrustRuleMarkerState`, `Remove-PostgresTrustRuleMarker`, `Get-PostgresManualRecoveryDetail`.
  - `New-PostgresRecoveryBackup` (15433-15480): root path taken from `Get-PostgresRecoveryBackupRoot` (same path, no behavior change).
  - `Test-PostgresManualRecoveryRequired` (15499-15501): extended to durable state.
  - `Reset-PostgresPasswordAutomatically` (15567-15739): guard 15569-15571 uses the detail helper; marker write before the trust-line write (near 15651); marker removal after the verified restore (near 15663) and in the catch path (near 15689); new `$markerClearFailed` branch in the catch and result mapping (15721-15738).
  - `Invoke-PostgresSelectedPasswordRecovery` (20133): guard message at 20140 uses the detail helper.
  - `Invoke-RestorePostgresBackup` (29958): guard message at 29961 uses the detail helper.
  - Setup pass (top-level, before `$postgresServiceWasRunning = $null`, near 34357): new guard.
  - `Get-PostgresRecoveryActions` (2033-2052): add a `postgres-manual-recovery` retry label used by the setup guard.
- Owning subsystem: PostgreSQL recovery and setup pass.
- Doc: ARCHITECTURE.md entry for the PostgreSQL recovery marker (one short paragraph).

## 6. Tests required before implementation

- Focused failing or characterization tests: none run (owner hold; static review only).
- Source/inventory checks: confirm the callers of `Reset-PostgresPasswordAutomatically` (34671 and 20167) and `Invoke-PostgresSelectedPasswordRecovery` (34385, 34449) still receive the same result shape (ActionRequired, ReasonCode, Reason, RecoveryBundle).

## 7. Tests required after implementation

- Focused behavior tests (main agent, if authorized): marker absent returns None; marker with invalid JSON returns Error and blocks an operation; marker present with live hash equal to original removes the marker and does not block; marker present with live hash different from original blocks with ReasonCode MANUAL_RECOVERY_REQUIRED and names the three paths; live file missing returns Error; a marker write failure returns before any trust-line write (no `WriteAllText` call); a successful restore followed by a failed marker removal returns MANUAL_RECOVERY_REQUIRED and names the marker path.
- Regression suite: Tests\TeknoParrot-Manager.Tests.ps1 and Tests\PostgresHelperResultContract.Tests.ps1 (run by main agent). Existing assertions (ReasonCode, FailureStage, `Should -Invoke Start-Service -Times 2`, `host all all 0.0.0.0/0 trust` unsafe case) must not be weakened.
- Static and procedure gates: ASCII check, parse check, PSScriptAnalyzer with PSScriptAnalyzerSettings.psd1.

## 8. Documentation/report updates required

- Control board row: docs\remediation\PR-321-control-board.md (main agent).
- Remediation note: docs\remediation\RC8-LANE-G-PG-FAILCLOSED.md residual section (main agent).
- Hunk classification: durable fail-closed marker in recovery and setup guard; no change to user-visible wording outside the guard messages.
- ARCHITECTURE.md: one paragraph describing the marker path, schema, write order, detection, and clear rule.

## 9. Permanent procedure IDs affected

- IDs and evidence: none identified in this lane.

## 10. Runtime smoke checklist

- Exact packaged behavior: not run (owner hold).
- Required source/package identity: not applicable in this lane.
- Evidence artifacts: none.
- Owner/runtime authorization: required before any runtime check.

## 11. Stop condition

Stop when the helpers, the three guards, the setup-pass guard, the reset marker write/clear, the catch branch, the result mapping, the recovery-action label, and the ARCHITECTURE.md paragraph are edited and read back, and ASCII/byte checks pass. Do not widen scope.

## 12. Forbidden actions

No unrelated cleanup, broad rewrite, commit, push, package, release, certification, wiki update, test-PC work, owner smoke, Pester run, or diagnostic script unless separately authorized.

## 13. Commit/package authorization status

- Commit authorized: No, explicit authorization required
- Package authorized: No, explicit authorization required
- Release/certification authorized: No, explicit authorization required
