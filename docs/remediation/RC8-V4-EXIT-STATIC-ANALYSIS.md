# RC8 V4 Main Pester Exit: Static Analysis

Status: read-only static analysis. No Pester, pwsh test, gate, or smoke run was executed. No product, test, or script file was edited. Base commit a07e821ed7ae791a6eca598579bd49d644427f56.

Scope: why the V4 unfiltered main Pester run (`Tests\TeknoParrot-Manager.Tests.ps1`) stopped abnormally, and why the quality gate recorded `Main Pester failed: exit code 1`.

Source identity: the worktree copies of `Tests/TeknoParrot-Manager.Tests.ps1` (25943 lines), `TeknoParrot-Manager.ps1` (37791 lines), and `scripts/Run-TpmQualityGate.ps1` match the integration tree by SHA256 prefix (8f011bf3, edc44e08, 740a63c0). Findings below therefore apply to the analyzed source.

## 1. Evidence

### 1.1 Diagnostic log (Workspace\V4-MainDiagnostic-PS7.log)

- 137730 bytes, 1979 lines, mtime 2026-10-25 08:56:26 local (12:56:26Z).
- Header `Pester v5.7.1`. `Discovery found 1524 tests in 2.1s.`
- 1031 `[+]` lines, 0 `[-]` lines. No `Tests Passed` summary and no Pester trailer.
- Final line (1979): `[+] regenerates corrupt or stale cache without an external reference dependency 32.04s`.
- Sum of the durations on all 1031 `[+]` lines (every line parsed, none unparsed): 429.0 s. With 2.1 s discovery, the run had about 431 s (about 7.2 min) of test time when the log stops.
- `Input ended unexpectedly.` appears at lines 183, 187, 203, 244, 929. Each follows a test that mocks `Read-Host` to return null and mocks `Exit-TpmProcess`, and the run continued past each one. None appear after line 929.

Next test, not run in the diagnostic: `It "renders from the bundled landscape reference"` at `Tests/TeknoParrot-Manager.Tests.ps1:16929`. Its body (16930-16939) calls `Get-TpmReShadePreviewReference` and `New-TpmReShadePreviewArtifact -Mode Slider`. It has no `Read-Host`, `Read-HostSafe`, `Exit-TpmProcess`, or `-Show` call.

Isolated run (`Workspace\V4-LandscapeIsolated-PS7.log`, 528 bytes, filtered to that test): `Tests Passed: 1, Failed: 0, NotRun: 1523`, 20.48 s.

### 1.2 Gate artifacts (Workspace\RC8-FinalQuality-V4\)

- `fatal.json`: message `QUALITY GATE FAIL: Main Pester failed: exit code 1`, `Exit: 1`. Stack lists `scripts\Run-TpmQualityGate.ps1` line 80 and `RC8-RunQuality-V4.ps1` line 64.
- `quality.log` (08:48): `Permanent procedure gate passed.`, then the terminating error. It contains no Pester output. Transcript end 20261025084846.
- `testResults.xml` (08:48): contains only the 42 SupportPackage results, all Success. No main-suite result survives.
- `V4-eventlog.txt`: 0 bytes. Filter used to produce it is not recorded.
- Receipts: child ExitCode 1, child pid 3968, carrier pid 10616, ended 12:48:46Z, `InputRedirected=true`, `OutputRedirected=false`.

### 1.3 Launch topology (Workspace\RC8-RunQuality-V4.ps1)

- Lines 13-20: helper starts pwsh with `RedirectStandardInput=true`, line 18 `StandardInput.Close()` (stdin at EOF), line 20 records ExitCode.
- Line 30: `Start-Process` with `WindowStyle Normal` (stdout visible).
- Line 42: throws unless stdin is redirected and stdout is not (`Official quality requires original stdin-EOF and visible stdout topology`).
- Line 56: `Start-Transcript`. Line 64: calls `scripts\Run-TpmQualityGate.ps1`.
- The launch line and stdin topology of the 08:56 diagnostic run are not recorded in any artifact read.

### 1.4 Gate source (`scripts/Run-TpmQualityGate.ps1`)

- Lines 16-23 `Invoke-GateStep`: records only `$LASTEXITCODE`. Any nonzero value becomes `"<step> failed: exit code N"`. Child output is not inspected.
- Line 38: `& pwsh -NoProfile -Command "Invoke-Pester -Path '$tests' -CI"`. Line 39: same for SupportPackage. Neither passes an output path. Both run regardless of an earlier failure, because nothing stops after a failed step.
- Line 80: `exit 1` if any step failed.

### 1.5 Product exit paths (`TeknoParrot-Manager.ps1`)

- Lines 3302-3305: `Exit-TpmProcess` is `exit $Code`.
- Line 3334: `Read-Host` inside `Read-HostSafe`. Lines 3335-3340: on null, logs (3336), prints `Input ended unexpectedly.` (3338), then calls `Exit-TpmProcess -Code 1` (3340).
- Raw `Read-Host` calls outside the wrapper (for example 20091, 20110, 31913, 32061, 34081, 37776, 37789) return null under EOF and do not exit by themselves. Line 37790 `exit 1` is the top-level catch only.
- Other exit statements: 19948, 19965, 32063, 32400, 34936. Callers of 19948 and 19965 were not traced.

### 1.6 Test mocks of the exit path

- `Mock Exit-TpmProcess` at `Tests/TeknoParrot-Manager.Tests.ps1:1484`, `1495`, `1580`, `1987`, `9544`.
- No test calls `Stop-Process` or `taskkill`. `Process.Kill()` appears only in child-process harness tests.

### 1.7 Repo history and Pester version

- `Workspace\RC8-RemediationGate-V4.md:473-478` (read in an earlier pass): Pester 5.7.1 runs with 4 passed / 1 failed, and with 3 failed, each ended with `actual child exit 1`. In this repo's own runs, exit 1 accompanies counted failures.
- Pester 5.7.1 is not installed on this machine. Only `C:/Program Files/WindowsPowerShell/Modules/Pester/3.4.0` exists. Searches of the user profile, `Program Files\PowerShell`, `ProgramData`, `<test-pc-repos>`, and user module paths found no 5.7.1 manifest. NO-EVIDENCE for Pester 5.7.1 `-CI` exit logic.

## 2. Ranked candidates

| Rank | Candidate | Location | Supporting evidence | Against / gap | Status |
|---|---|---|---|---|---|
| 1 | Gate main run ended with a counted failure (exit 1) whose failing tests were not preserved | Run-TpmQualityGate.ps1:16-23, 38-39; RC8-RemediationGate-V4.md:473-478 | `fatal.json` exit 1 matches the repo's counted-failure exit 1 | No main-suite summary or XML survives; failing tests cannot be named | Consistent with all artifacts; NOT CONFIRMED |
| 2 | Gate main child reached an unmocked `Read-HostSafe` with EOF stdin and exited 1 | TeknoParrot-Manager.ps1:3334-3340; RC8-RunQuality-V4.ps1:18 | Gate child stdin is EOF by launcher topology; exit 1 matches `Exit-TpmProcess -Code 1` | The "Input ended" line went to the unrecorded console, so it cannot be seen; reachability from unmocked callers not enumerated for the full suite | Possible; UNVERIFIED |
| 3 | Diagnostic run cut at about 7.2 min of test time; external termination or a silent wait; cause unknown | Diagnostic log tail; Tests:16929 | No output after line 1979; no product exit text; no `[-]`; landscape test passes in isolation | No kill record; no launch record; mechanism unidentified | Cause UNKNOWN |
| 4 | Diagnostic blocked on a console-bound `Read-Host` (prompt text never reaches a redirected log) | Raw Read-Host list (1.5); Read-HostSafe 3334 | A real `Read-Host` prompt is written to the host UI, not the output stream, so it would be absent from a redirected log | Stdin topology of the diagnostic is unrecorded; no trace from test 1980 onward | UNVERIFIED |
| 5 | Native crash (System.Drawing / GDI+) at test 1980 | Tests:16929-16939; TeknoParrot-Manager.ps1:9946-9967 | None found | Isolated pass; no crash text; event log empty (filter unknown) | NO-EVIDENCE |
| 6 | Product exit reached inside the cut region | 3302-3305; 19948; 19965; 32063; 34936 | No exit text in log | Exit mocks at 1484-9544; test 1980 has no exit call; callers of 19948/19965 not traced | NO-EVIDENCE for the cut region |

## 3. Confirmed source defects (no edits made)

- D1. `scripts/Run-TpmQualityGate.ps1:38-39`: both `-CI` runs use the default `testResults.xml` path. The SupportPackage run overwrote the main run's XML. Evidence: `testResults.xml` at 08:48 holds only SupportPackage results. CONFIRMED-UNFIXED (read-only task).
- D2. `scripts/Run-TpmQualityGate.ps1:38-39`: child Pester output inherits the console and is not captured. The wrapper transcript (`RC8-RunQuality-V4.ps1:56`) does not include child output. Evidence: `quality.log` has no Pester lines. CONFIRMED-UNFIXED.
- D3. `scripts/Run-TpmQualityGate.ps1:16-23`: a failed child is reduced to its exit code. Which tests failed is discarded. CONFIRMED-UNFIXED.
- D4. `scripts/Run-TpmQualityGate.ps1:39` runs after a failed `:38` and does not stop, so later steps overwrite earlier evidence (see D1). CONFIRMED-UNFIXED.
- D5. `scripts/Run-TpmQualityGate.ps1:80`: a single `exit 1` covers every failure class, so the gate cannot tell a counted failure from an abnormal exit. CONFIRMED-UNFIXED.

## 4. What would separate the candidates (not run; owner hold)

- Capture each child's stdout and stderr to a file, with a separate `-CI` output path per step, then compare the gate's exit code with the captured tail.
- Record the launch line and stdin topology for each diagnostic run.
- Read the Pester 5.7.1 `-CI` exit path from the module source on an owner-approved machine.
- Query the event log for pwsh crashes, filtered by executable path and by the 12:48-12:57Z window, and record the filter.
- Trace callers of `Exit-PostgresRecoveryResume*` (19948, 19965) and every unmocked `Read-HostSafe` reachable from tests 1-1524 with EOF stdin.

## 5. Not verified

- Pester 5.7.1 `-CI` exit-code semantics (module not on disk).
- Whether any test reaches an unmocked `Read-HostSafe` (not enumerated for the full suite).
- Launch method and stdin topology of the 08:56 diagnostic run.
- Whether the coordinator killed the diagnostic process, and why.
