# TPM Remediation Slice Contract

## 1. Slice name

- Name: PostgreSQL native-tool launch guard and authentication-policy restore gate
- Contract ID: TPM-RC8-POSTGRES-LAUNCH-AND-RESTORE-GUARD-001
- Issue/PR: GitHub #370 (password cleanup; already present in the lane tree, no hunk), GitHub #371 (service restarted after a failed authentication-policy restore), unattended zero-byte `pg_dump.exe` launch (issue number not supplied to Lane B)

## 2. Owner report IDs included

- IDs: not assigned in lane-visible documents; coordinator maps them to owner report IDs.
- Exact owner-visible failures:
  1. The unattended PostgreSQL path runs a zero-byte fake `pg_dump.exe` and shows the "unsupported 16-bit application" dialog.
  2. #370: password cleanup output could join a helper's return value.
  3. #371: after the authentication policy could not be restored, the outer PostgreSQL setup flow restarted PostgreSQL. The reset function's own branch states "PostgreSQL was not restarted".

## 3. Explicit exclusions

- Owner IDs not included: the V4 Main Pester abnormal end (diagnosed separately; not fixed here); Lane A progress UI; Lane C RC8 defects.
- Features, modules, package, runtime, and release actions excluded: packaging, runtime smoke, certification, live TeknoParrot or PostgreSQL service changes, test execution, commits.

## 4. Behavior contract

- Current failure:
  - `Invoke-PostgresNativeCommand` and `Invoke-PostgresNativeProcessWithInput` start any file that passes `Test-Path -PathType Leaf`. A zero-byte or non-PE file reaches process creation.
  - `Reset-PostgresPasswordAutomatically` records the authentication-policy restore failure, but the outer `finally` in the PostgreSQL setup flow still calls `Restore-PostgresServiceState`.
- Expected behavior:
  - Before any PostgreSQL native launch, the tool must pass `Test-PostgresToolExecutable` (at least 64 bytes, `MZ` header, `PE\0\0` signature at `e_lfanew`). On failure the helper returns ExitCode 1 with a message that names only the file, and no process is started. Existing non-zero handling in callers applies.
  - When the authentication policy cannot be restored, the flow leaves PostgreSQL stopped, does not restart it, does not claim setup complete, and reports failure ID `postgres-auth-policy-restore` with Retry and Stop actions.
  - #370: every `Remove-PostgresPgPassFile` call stays wrapped in `[void]`. No change.
- Forbidden regressions:
  - pg_hba restore semantics and hash verification.
  - Password redaction and the psql/pg_dump argument text.
  - Restart behavior for non-failure paths.
  - Any completion claim after a blocked restore.
- Design boundaries and deliberate exclusions: no new dependency, no retry loop, no version or signature verification. The guard checks only the executable container format.

## 5. Source/function ownership

- Files: `TeknoParrot-Manager.ps1` (lane B worktree only)
- Functions/regions:
  - `Get-PostgresRecoveryActions` (failure-ID switch, about line 2045)
  - new `Test-PostgresToolExecutable` (before `Invoke-PostgresNativeCommand`)
  - `Invoke-PostgresNativeCommand` and `Invoke-PostgresNativeProcessWithInput` (guard at entry)
  - `Reset-PostgresPasswordAutomatically` restore catch (about line 15623)
  - PostgreSQL setup flow: per-iteration flag reset (about line 34237), outer `finally` (about line 34730), blocked-restore branch before the `postgres-service-restore` branch (about line 34742)
- Owning subsystem: PostgreSQL recovery and backup.

## 6. Tests required before implementation

- Focused characterization tests, for the integration owner to add. Lane B did not add tests under its no-run directive.
  - `Test-PostgresToolExecutable`: false for a zero-byte file, an `MZ`-only file, an `NE` header, and a directory; true for `cmd.exe`.
  - `Invoke-PostgresNativeCommand` with a zero-byte fake `pg_dump.exe`: ExitCode 1, no process started, output names only the file.
  - Source assertion: the outer `finally` gates `Restore-PostgresServiceState` on `PostgresAuthPolicyRestoreBlocked`.
  - Existing test "leaves PostgreSQL stopped and returns action required when policy restoration fails after ALTER" remains valid.
- Source/inventory checks: existing source-text assertions at Tests 7950-7951, 17411, and 19245-19247 must remain satisfied. The `Restore-PostgresServiceState -WasRunning` text is retained.

## 7. Tests required after implementation

- Focused behavior tests: section 6 items.
- Regression suite: full `Tests\TeknoParrot-Manager.Tests.ps1` Pester run by Main.
- Static and procedure gates: ASCII check, parse check, PSScriptAnalyzer with `PSScriptAnalyzerSettings.psd1`, and `scripts\Run-TpmQualityGate.ps1` per RELEASE-SAFETY-CHECKLIST.

## 8. Documentation/report updates required

- Control board row: coordinator updates `docs/remediation/PR-321-control-board.md`. Lane B does not edit it.
- Remediation report row: coordinator.
- Hunk classification:
  - Launch guard: fix for the unattended zero-byte `pg_dump.exe` launch.
  - Restore gate: fix for #371.
  - #370: already present in the lane tree; no hunk.
- Changelog or user docs: none from Lane B.

## 9. Permanent procedure IDs affected

- Not asserted by Lane B. Coordinator maps against the permanent procedure registry.

## 10. Runtime smoke checklist

- Not executed. Closing #370 and #371 requires owner runtime evidence with a real PostgreSQL service. The zero-byte `pg_dump.exe` case should be checked on a disposable copy of the install.
- Required source/package identity: not established by this lane.
- Evidence artifacts: none produced by Lane B.
- Owner/runtime authorization: not granted.

## 11. Stop condition

Stop when the source edits, the patch file, the SHA256 list, and the root-cause note are handed to the coordinator. Do not widen scope to unrelated findings.

## 12. Forbidden actions

No Pester, gates, smoke, benchmarks, commits, pushes, packaging, live TeknoParrot or PostgreSQL service changes, edits to the protected repository or the integration checkout, or edits to Lane A, Lane C, or Lane D areas.

## 13. Commit/package authorization status

- Commit authorized: No
- Package authorized: No
- Release/certification authorized: No
