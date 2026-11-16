# TPM Remediation Slice Contract

## 1. Slice name

- Name: RC8 lane C -- Save-Config preserves the saved UnattendedMode selector
- Contract ID: TPM-RC8-LANE-C-SAVE-CONFIG-UNATTENDED-001
- Issue/PR: #339 (related #300, PR #321)

## 2. Owner report IDs included

- IDs: F09 (as labeled in issue #339). No control-board row exists for F09; the mapping is issue-level.
- Exact owner-visible failures: an ordinary interactive configuration save erases a saved `UnattendedMode = HealthCheck` value. The next unattended process selector then fails with exit 1.

## 3. Explicit exclusions

- Owner IDs not included: all other F-series and owner-table items.
- Features, modules, package, runtime, and release actions excluded: no new unattended mode, no menu control for `UnattendedMode`, no new persistent setting, no change to startup acceptance (`HealthCheck` remains the only acted-on value), no packaging, no owner-runtime smoke.

## 4. Behavior contract

- Current failure: `Save-Config` writes a fixed key set that has no `UnattendedMode` key, so any save drops a saved value.
- Expected behavior: a non-empty `UnattendedMode` value present at load survives any subsequent `Save-Config` and reloads unchanged. A configuration that never contained the key is written exactly as before (no key is added).
- Forbidden regressions: adding `UnattendedMode` when the loaded config lacked it; accepting any non-`HealthCheck` value at startup; changing other key names or their order; non-ASCII bytes in the script; writing the config through any path other than `Save-Config`.
- Design boundaries and deliberate exclusions: `Save-Config` preserves the raw value and does not interpret it. Validation stays at the unattended selector.

## 5. Source/function ownership

- Files: `TeknoParrot-Manager.ps1` (lane C worktree only).
- Functions/regions:
  - `Save-Config`: a conditional `UnattendedMode` key is added after the ordered configuration hashtable.
  - Script-level configuration defaults: `$unattendedModeSaved` initialized to `$null` beside `$checkForUpdatesOnStartup`.
  - Configuration load block: `$unattendedModeSaved` captured immediately after the `CheckForUpdatesOnStartup` read and before the corrupt-config check.
- Owning subsystem: configuration persistence (`Save-Config`, config load).

## 6. Tests required before implementation

- Focused failing-before case: load a configuration containing `UnattendedMode = "HealthCheck"`, call `Save-Config`, and assert the key survives in the written JSON. This must fail on the unfixed base.
- Characterization case: a configuration without `UnattendedMode` saves with the same key set as before.
- Source check: `Save-Config` remains the only writer of the configuration file.
- Lane note: per the lane assignment, no tests were authored or run in lane C. Main must add and run these.

## 7. Tests required after implementation

- Focused behavior tests: round trip preserves the value; absent key stays absent; a non-`HealthCheck` value is still rejected by the unattended selector.
- Regression suite: `Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1` (Windows PowerShell 5.1).
- Static and procedure gates: ASCII byte check, parse check, `Invoke-ScriptAnalyzer -Path TeknoParrot-Manager.ps1 -Severity Error,Warning -Settings PSScriptAnalyzerSettings.psd1`, and the permanent procedure gate with the remediation report.

## 8. Documentation/report updates required

- Control board row: section appended to `docs/remediation/PR-321-control-board.md` (RC8 lane C follow-up).
- Remediation report row: section appended to `docs/remediation/PR-321-reconciliation.md`.
- Hunk classification: `Save-Config` and config-load hunks map to #339 / this contract / TPM-TRACE-001.
- Changelog or user docs: not updated in lane C; the integration owner decides the changelog entry.

## 9. Permanent procedure IDs affected

- IDs and evidence: TPM-TRACE-001 (hunk-to-issue mapping), TPM-EVIDENCE-001 (focused behavior tests). Evidence is pending Main verification.

## 10. Runtime smoke checklist

- Exact packaged behavior: after an interactive save, a `HealthCheck` unattended run still reaches the health-check path and exits as before.
- Required source/package identity: the RC8 candidate source identity recorded by the integration owner.
- Evidence artifacts: focused test output and a before/after config JSON comparison.
- Owner/runtime authorization: required; not run by lane C.

## 11. Stop condition

Stop when the contract's focused tests, report status, hunk mapping, and required gate evidence are complete. Do not widen scope to unrelated findings.

## 12. Forbidden actions

No unrelated cleanup, broad rewrite, commit, push, package, release, certification, wiki update, test-PC work, or owner smoke unless separately authorized.

## 13. Commit/package authorization status

- Commit authorized: No / Yes, explicit authorization required
- Package authorized: No / Yes, explicit authorization required
- Release/certification authorized: No / Yes, explicit authorization required
