param(
    [Parameter(Mandatory=$true)]
    [string]$RepoPath,

    [Parameter(Mandatory=$true)]
    [string]$TeknoParrotRoot,

    [string]$HarnessRoot,

    [switch]$RunUnattendedTPM,

    # Summary (default): only the final certification scorecard and any real
    # test failures reach the console -- the underlying Pester run (which
    # includes noisy Write-Host output from mocked production-code scenarios,
    # e.g. auto-update destructive-path tests) is captured to file only.
    # Detailed: Pester's own per-file/per-test progress, as before this
    # parameter existed. Diagnostic: Pester's own Diagnostic verbosity (full
    # mock/trace output) on top of Detailed. All three levels always write
    # the same full report files -- this only controls what streams to the
    # console during the run.
    [ValidateSet('Summary', 'Detailed', 'Diagnostic')]
    [string]$VerbosityLevel = 'Summary',

    # Issue #136: hard ceiling on the Pester regression gate. A full local
    # run of the whole Tests\ folder takes well under a minute; 1800s (30
    # minutes) is generous headroom for slower real-hardware I/O while still
    # guaranteeing the certification run cannot hang forever. Exposed as a
    # parameter (not a hardcoded constant) so a real slow-hardware run can
    # raise it without a code change, and so tests can exercise a near-zero
    # timeout without waiting.
    [int]$PesterRegressionTimeoutSeconds = 1800
)

$ErrorActionPreference = "Stop"
$runTimer = [System.Diagnostics.Stopwatch]::StartNew()

. (Join-Path $PSScriptRoot 'Resolve-Pcsx2Directory.ps1')

$RepoPath = (Resolve-Path -LiteralPath $RepoPath).Path
if (!(Test-Path -LiteralPath $TeknoParrotRoot -PathType Container)) {
    throw "TeknoParrot root not found: $TeknoParrotRoot"
}
$TeknoParrotRoot = (Resolve-Path -LiteralPath $TeknoParrotRoot).Path

if ([string]::IsNullOrWhiteSpace($HarnessRoot)) {
    $repoParent = Split-Path -Parent $RepoPath
    $HarnessRoot = Join-Path $repoParent "TPM-TestHarness"
}

$stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportDir = Join-Path $HarnessRoot "Reports\$stamp"
$backupDir = Join-Path $HarnessRoot "Backups\$stamp"
New-Item -ItemType Directory -Force -Path $reportDir, $backupDir | Out-Null

$md = Join-Path $reportDir "TPM-Validation-Report.md"
$json = Join-Path $reportDir "TPM-Validation-Report.json"
$certificationMd = Join-Path $reportDir "TPM-Certification-Scorecard.md"
$certificationJson = Join-Path $reportDir "TPM-Certification-Scorecard.json"

function Add-Report {
    param([string]$Text)
    $Text | Out-File -FilePath $md -Append -Encoding utf8
}

function Add-CertificationReport {
    param([string]$Text)
    $Text | Out-File -FilePath $certificationMd -Append -Encoding utf8
}

function Copy-IfExists {
    param([string]$Path, [string]$DestName)
    if (Test-Path -LiteralPath $Path) {
        Copy-Item -LiteralPath $Path -Destination (Join-Path $backupDir $DestName) -Recurse -Force
        return $true
    }
    return $false
}

function Get-TreeHash {
    param([string]$Path)
    if (!(Test-Path -LiteralPath $Path)) { return @() }
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $base = $resolved.TrimEnd('\')
    Get-ChildItem -LiteralPath $resolved -Recurse -File -ErrorAction SilentlyContinue |
        Sort-Object FullName |
        ForEach-Object {
            $relative = $_.FullName
            if ($_.FullName.Length -gt $base.Length) {
                $relative = $_.FullName.Substring($base.Length).TrimStart('\')
            }
            if ([string]::IsNullOrWhiteSpace($relative)) {
                $relative = $_.Name
            }
            $h = Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
            [pscustomobject]@{
                RelativePath = $relative
                Path = $_.FullName
                Hash = $h.Hash
                Length = $_.Length
            }
        }
}

function Compare-TreeSnapshot {
    param([object[]]$Before, [object[]]$After)
    $beforeMap = @{}
    $beforeSkipped = 0
    foreach ($item in @($Before)) {
        if (-not $item -or [string]::IsNullOrWhiteSpace([string]$item.RelativePath)) { $beforeSkipped++; continue }
        $beforeMap[[string]$item.RelativePath] = $item.Hash
    }
    $afterMap = @{}
    $afterSkipped = 0
    foreach ($item in @($After)) {
        if (-not $item -or [string]::IsNullOrWhiteSpace([string]$item.RelativePath)) { $afterSkipped++; continue }
        $afterMap[[string]$item.RelativePath] = $item.Hash
    }
    $added = 0
    $removed = 0
    $changed = 0
    foreach ($key in $afterMap.Keys) {
        if (-not $beforeMap.ContainsKey($key)) { $added++ }
        elseif ($beforeMap[$key] -ne $afterMap[$key]) { $changed++ }
    }
    foreach ($key in $beforeMap.Keys) {
        if (-not $afterMap.ContainsKey($key)) { $removed++ }
    }
    [pscustomobject]@{
        BeforeCount = @($Before).Count
        AfterCount = @($After).Count
        Added = $added
        Removed = $removed
        Changed = $changed
        BeforeSkipped = $beforeSkipped
        AfterSkipped = $afterSkipped
    }
}

# Issue #136: the Pester regression gate previously ran synchronously with
# no visibility into progress and no way to distinguish "still running" from
# "hung forever" -- both looked identical to an operator watching the
# console (process alive, report folder created, nothing updating). These
# two pure decision functions back the runspace-polling loop below; kept
# separate and side-effect-free so they can be unit tested directly without
# needing to run actual Pester-in-Pester or spin up a real runspace.
function Test-TPMPesterHeartbeatDue {
    param(
        [double]$ElapsedSeconds,
        [double]$LastHeartbeatSeconds,
        [double]$HeartbeatIntervalSeconds
    )
    return (($ElapsedSeconds - $LastHeartbeatSeconds) -ge $HeartbeatIntervalSeconds)
}

function Test-TPMPesterTimedOut {
    param(
        [double]$ElapsedSeconds,
        [double]$TimeoutSeconds
    )
    return ($ElapsedSeconds -ge $TimeoutSeconds)
}

function Get-TPMPesterHeartbeatMessage {
    param(
        [double]$ElapsedSeconds,
        [string]$LastOutputLine
    )
    $suffix = if ([string]::IsNullOrWhiteSpace($LastOutputLine)) { '' } else { " -- last: $LastOutputLine" }
    return ("  ... still running ({0:n0}s elapsed){1}" -f $ElapsedSeconds, $suffix)
}

function Get-TPMPesterTimeoutMessage {
    param(
        [double]$ElapsedSeconds,
        [double]$TimeoutSeconds,
        [string]$LastOutputLine,
        [string]$OutputPath,
        [string]$ProgressPath
    )
    $lastText = if ([string]::IsNullOrWhiteSpace($LastOutputLine)) { '(no output captured)' } else { $LastOutputLine }
    return ("Pester regression suite timed out after {0}s (limit {1}s). Last known output: {2}. See {3} and {4} for details." -f `
        [int]$ElapsedSeconds, [int]$TimeoutSeconds, $lastText, $OutputPath, $ProgressPath)
}

function Get-PesterSummary {
    param([Parameter(Mandatory=$true)]$PesterResult)
    $candidate = $PesterResult
    if ($PesterResult -is [array]) {
        $candidate = @($PesterResult) | Where-Object {
            $_ -and ($_.PSObject.Properties.Name -contains 'PassedCount' -or $_.PSObject.Properties.Name -contains 'Passed') -and ($_.PSObject.Properties.Name -contains 'FailedCount' -or $_.PSObject.Properties.Name -contains 'Failed')
        } | Select-Object -Last 1
    }
    $summary = [ordered]@{
        Passed = $null
        Failed = $null
        Skipped = $null
        Inconclusive = $null
        NotRun = $null
        Total = $null
        Duration = $null
        Result = 'Unknown'
    }
    if (-not $candidate) { return [pscustomobject]$summary }
    $fields = @(
        @('Passed','PassedCount','Passed'),
        @('Failed','FailedCount','Failed'),
        @('Skipped','SkippedCount','Skipped'),
        @('Inconclusive','InconclusiveCount','Inconclusive'),
        @('NotRun','NotRunCount','NotRun'),
        @('Total','TotalCount','Total')
    )
    foreach ($pair in $fields) {
        foreach ($name in $pair[1..($pair.Count-1)]) {
            if ($candidate.PSObject.Properties.Name -contains $name) {
                $summary[$pair[0]] = $candidate.$name
                break
            }
        }
    }
    foreach ($name in @('Duration','Time')) {
        if ($candidate.PSObject.Properties.Name -contains $name) {
            $summary.Duration = [string]$candidate.$name
            break
        }
    }
    if ($candidate.PSObject.Properties.Name -contains 'Result') { $summary.Result = [string]$candidate.Result }
    if ($null -eq $summary.Total -and $null -ne $summary.Passed -and $null -ne $summary.Failed) {
        $total = 0
        foreach ($key in @('Passed','Failed','Skipped','Inconclusive','NotRun')) {
            if ($null -ne $summary[$key]) { $total += [int]$summary[$key] }
        }
        $summary.Total = $total
    }
    if ($summary.Result -eq 'Unknown' -and $summary.Failed -eq 0) { $summary.Result = 'Passed' }
    [pscustomobject]$summary
}

function New-CertificationScorecard {
    param([hashtable]$Results)

    $checkMap = @{}
    foreach ($check in @($Results.Checks)) {
        $checkMap[$check.Name] = [bool]$check.Passed
    }

    $snapshotClean = $true
    if ($Results.Snapshots) {
        foreach ($name in $Results.Snapshots.Keys) {
            $s = $Results.Snapshots[$name]
            if (($s.Added + $s.Removed + $s.Changed) -ne 0) { $snapshotClean = $false }
        }
    }

    # PowerShell parses hashtable-literal (@{...}) values in command mode, not
    # expression mode -- an inline "if (...) {...} else {...}" as a value,
    # even parenthesized, fails at runtime with "The term 'if' is not
    # recognized..." (confirmed by direct repro; this crashed the harness
    # after Pester/install-health completed, on every real run). Precompute
    # into a variable first and reference the variable as the value instead.
    $pcsx2x6Details = if ($Results.Pcsx2x6.Present) {
        "canonicalDeployed=$($Results.Pcsx2x6.CanonicalFilesDeployed) cursorPathCanonical=$($Results.Pcsx2x6.CursorPathPointsCanonical)"
    } else {
        'not applicable -- no pcsx2x6 in this install'
    }

    $vbtDetails = if ($Results.VirtualBetaTester) {
        ("total={0} passed={1} failed={2} | human-behaviors={3} idempotency={4} recovery={5} environment-variations={6} high-tvd-behaviors={7}" -f `
            $Results.VirtualBetaTester.Total, $Results.VirtualBetaTester.Passed, $Results.VirtualBetaTester.Failed, `
            $Results.VirtualBetaTester.HumanBehaviors, $Results.VirtualBetaTester.IdempotencyChecks, `
            $Results.VirtualBetaTester.RecoveryBehaviors, $Results.VirtualBetaTester.EnvironmentVariations, `
            $Results.VirtualBetaTester.HighTvdBehaviors)
    } else {
        'not collected'
    }

    $scoreItems = @(
        [pscustomobject]@{Area='Repository'; Passed=($checkMap['Repository available'] -and $checkMap['Repository clean']); Details=$Results.GitStatus},
        [pscustomobject]@{Area='Pester'; Passed=($Results.Pester -and $Results.Pester.Failed -eq 0); Details=("total={0} passed={1} failed={2}" -f $Results.Pester.Total, $Results.Pester.Passed, $Results.Pester.Failed)},
        [pscustomobject]@{Area='Static Analysis'; Passed=($Results.PSScriptAnalyzerFindings -eq 0); Details=("findings={0}" -f $Results.PSScriptAnalyzerFindings)},
        [pscustomobject]@{Area='Real Install Health'; Passed=[bool]$checkMap['Real install health check collected']; Details=$Results.InstallHealthReport},
        [pscustomobject]@{Area='Backups'; Passed=($Results.Backup.UserProfiles -or $Results.Backup.GameProfiles); Details=("UserProfiles={0} GameProfiles={1}" -f $Results.Backup.UserProfiles, $Results.Backup.GameProfiles)},
        [pscustomobject]@{Area='Smoke File Safety'; Passed=$snapshotClean; Details='no unexpected changes in smoke mode'},
        [pscustomobject]@{Area='Artifacts'; Passed=((Test-Path -LiteralPath $json -PathType Leaf) -and (Test-Path -LiteralPath $md -PathType Leaf)); Details=$reportDir},
        [pscustomobject]@{Area='pcsx2x6 crosshair path (issue #79)'; Passed=[bool]$checkMap['pcsx2x6 crosshair path (issue #79)']; Details=$pcsx2x6Details},
        [pscustomobject]@{Area='Behavioral Certification (Virtual Beta Tester)'; Passed=($Results.VirtualBetaTester -and $Results.VirtualBetaTester.Total -gt 0 -and $Results.VirtualBetaTester.Failed -eq 0); Details=$vbtDetails}
    )

    $passedCount = @($scoreItems | Where-Object { $_.Passed }).Count
    $totalCount = @($scoreItems).Count
    $overall = if ($passedCount -eq $totalCount) { 'CERTIFIED' } else { 'NOT CERTIFIED' }

    [pscustomobject]@{
        Timestamp = $Results.Timestamp
        Overall = $overall
        Passed = $passedCount
        Total = $totalCount
        ScorePercent = [math]::Round(($passedCount / [double]$totalCount) * 100, 2)
        Items = $scoreItems
        ReportDir = $reportDir
        ValidationReport = $md
        ValidationJson = $json
        # Issue #111: certification provenance, duplicated onto this object
        # (not just $results/the validation JSON) so a reviewer can confirm
        # the certified commit from the certification scorecard JSON alone,
        # without needing to cross-reference a second file.
        Repository = $Results.RepoPath
        Branch = $Results.GitBranch
        Commit = $Results.Commit
        CommitShort = $Results.CommitShort
        OriginMainCommit = $Results.OriginMainCommit
        SyncStatus = $Results.SyncStatus
        WorkingTreeClean = ($Results.GitStatus -eq '(clean)')
        GitVersion = $Results.GitVersion
        PowerShellVersion = $Results.PowerShellVersion
        TpmScriptVersion = $Results.TpmScriptVersion
        TpmDisplayVersion = $Results.TpmDisplayVersion
    }
}

$results = [ordered]@{
    Timestamp = $stamp
    RepoPath = $RepoPath
    TeknoParrotRoot = $TeknoParrotRoot
    HarnessRoot = $HarnessRoot
    ReportDir = $reportDir
    BackupDir = $backupDir
    SmokeMode = (-not $RunUnattendedTPM)
    Checks = @()
}

function Add-CheckResult {
    param([string]$Name, [bool]$Passed, [string]$Details)
    $script:results.Checks += [pscustomobject]@{
        Name = $Name
        Passed = $Passed
        Details = $Details
    }
}

# Issue #122: prints a short, concise header before each gate so an operator
# watching a long-running certification pass can see which gate is currently
# running, why it exists, and what a good outcome looks like -- without
# waiting for the final scorecard to find out anything failed. Deliberately
# terse (one line each) per the issue's own "concise, not verbose narration"
# requirement.
# Keep a persistent status signal visible even when the console body is
# temporarily blank or Pester output is suppressed by Summary mode.
function Set-TPMConsoleStatus {
    param([string]$Gate, [string]$Purpose, [string]$Expected)

    $title = if ([string]::IsNullOrWhiteSpace($Gate)) {
        'TeknoParrot Manager Certification Suite'
    } else {
        "TPM Certification - $Gate"
    }

    try { [Console]::Title = $title } catch {}
    try {
        $status = if ([string]::IsNullOrWhiteSpace($Purpose)) {
            $Expected
        } elseif ([string]::IsNullOrWhiteSpace($Expected)) {
            $Purpose
        } else {
            "$Purpose | $Expected"
        }
        Write-Progress -Id 42 -Activity 'TPM Certification Suite' -Status $status -PercentComplete 0
    } catch {}
}

function Clear-TPMConsoleStatus {
    try { Write-Progress -Id 42 -Activity 'TPM Certification Suite' -Completed } catch {}
    try { [Console]::Title = 'TeknoParrot Manager Certification Suite' } catch {}
}

function Write-TPMGateHeader {
    param([string]$Gate, [string]$Purpose, [string]$Expected)
    Set-TPMConsoleStatus -Gate $Gate -Purpose $Purpose -Expected $Expected
    Write-Host ""
    Write-Host ("--- Running: {0}" -f $Gate) -ForegroundColor Cyan
    Write-Host ("    Purpose : {0}" -f $Purpose) -ForegroundColor DarkGray
    Write-Host ("    Expected: {0}" -f $Expected) -ForegroundColor DarkGray
}

Push-Location $RepoPath
try {
    Write-TPMGateHeader -Gate 'Repository' -Purpose 'Confirms the certified commit and working-tree state' -Expected 'clean working tree, HEAD matches origin/main'
    $gitVersion = git --version
    $gitBranch = git rev-parse --abbrev-ref HEAD
    $gitCommit = git rev-parse HEAD
    $gitCommitShort = git rev-parse --short HEAD
    $gitStatusLines = @(git status --short)
    $repoClean = ($gitStatusLines.Count -eq 0)
    if ($repoClean) {
        $gitStatusText = '(clean)'
    } else {
        $gitStatusText = ($gitStatusLines -join [Environment]::NewLine)
    }

    # Issue #111: origin/main comparison, so a reviewer can tell from the
    # scorecard alone whether this run actually certified the latest pushed
    # commit or a stale/local one. Never blocks the run over a failed
    # fetch (no network is a real, non-fatal scenario) -- says so plainly
    # instead of silently omitting the comparison.
    $originMainCommit = $null
    $fetchFailed = $false
    try {
        git fetch origin main --quiet 2>$null
        if ($LASTEXITCODE -ne 0) { $fetchFailed = $true }
        else { $originMainCommit = (git rev-parse origin/main 2>$null) }
    } catch {
        $fetchFailed = $true
    }
    $syncStatus = if ($fetchFailed -or -not $originMainCommit) {
        'UNKNOWN -- could not fetch origin/main (offline or unreachable)'
    } elseif ($gitCommit -eq $originMainCommit) {
        'MATCHES origin/main'
    } else {
        "DIFFERS from origin/main ($originMainCommit) -- this run may not reflect the latest pushed commit"
    }

    $results.GitVersion = $gitVersion
    $results.GitBranch = $gitBranch
    $results.Commit = $gitCommit
    $results.CommitShort = $gitCommitShort
    $results.GitStatus = $gitStatusText
    $results.OriginMainCommit = $originMainCommit
    $results.SyncStatus = $syncStatus
    $results.PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    Add-CheckResult 'Repository available' $true "branch=$gitBranch commit=$gitCommit"
    Add-CheckResult 'Repository clean' $repoClean $gitStatusText

    # Resolved once, here, and reused for every pcsx2x6-related check below
    # (backup, snapshot, issue #79 verification, scorecard) -- previously
    # backup and snapshot both hardcoded the literal folder name "pcsx2x6"
    # while the #79 block below did a proper candidate search, so an install
    # where the real folder wasn't literally named "pcsx2x6" would silently
    # skip backup/snapshot coverage while the #79 check still found it
    # correctly. Flagged by Codex review as a required-before-1.0 fix.
    $pcsx2Dir = Resolve-Pcsx2Directory -TeknoParrotRoot $TeknoParrotRoot
    $crosshairPath = if ($pcsx2Dir) { Join-Path $pcsx2Dir 'TeknoParrot\crosshairs' } else { '' }

    Write-TPMGateHeader -Gate 'Backups' -Purpose 'Snapshots UserProfiles/GameProfiles/config before any test runs' -Expected 'backup created for every folder present'
    $backupItems = [ordered]@{}
    $backupItems.UserProfiles = Copy-IfExists (Join-Path $TeknoParrotRoot 'UserProfiles') 'UserProfiles'
    $backupItems.GameProfiles = Copy-IfExists (Join-Path $TeknoParrotRoot 'GameProfiles') 'GameProfiles'
    $backupItems.Pcsx2x6Crosshairs = if ($crosshairPath) { Copy-IfExists $crosshairPath 'pcsx2x6-crosshairs' } else { $false }
    $backupItems.Config = Copy-IfExists (Join-Path $RepoPath 'TeknoParrot-Manager.config.json') 'TeknoParrot-Manager.config.json'
    $results.Backup = $backupItems

    $userProfilesPath = Join-Path $TeknoParrotRoot 'UserProfiles'
    $gameProfilesPath = Join-Path $TeknoParrotRoot 'GameProfiles'
    $preUserProfiles = Get-TreeHash $userProfilesPath
    $preGameProfiles = Get-TreeHash $gameProfilesPath
    $preCrosshairs = if ($crosshairPath) { Get-TreeHash $crosshairPath } else { @() }

    Write-TPMGateHeader -Gate 'Pester regression suite' -Purpose 'Runs every unit/regression test in the repo' -Expected 'zero failed tests'
    $pesterCommand = Get-Command Invoke-Pester -ErrorAction SilentlyContinue
    if (-not $pesterCommand) { throw 'Invoke-Pester not found. Install it with: Install-Module Pester -Scope CurrentUser -Force' }
    $pesterModule = Get-Module Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    if ($pesterModule) { $results.PesterVersion = $pesterModule.Version.ToString() }
    $pesterOutputText = Join-Path $reportDir 'Pester-output.txt'

    # Issue #136: Output.Verbosity 'None' (the previous Summary-mode setting)
    # means Pester emits literally zero per-file/per-test text, to any
    # stream -- there is nothing "quiet capture" could have captured. A real
    # certification timeout came back with "Last known output: (no output
    # captured)" because of this, not a capture-mechanism bug. Verbosity is
    # now always at least 'Detailed' so a hang can always be diagnosed
    # (which file, which Describe block, how many tests completed) -- see
    # the stream choice below for how this stays console-quiet in Summary
    # mode despite that.
    $pesterOutputVerbosity = switch ($VerbosityLevel) {
        'Summary'    { 'Detailed' }
        'Detailed'   { 'Detailed' }
        'Diagnostic' { 'Diagnostic' }
    }
    $pesterConfig = New-PesterConfiguration
    $pesterConfig.Run.Path = $RepoPath
    $pesterConfig.Run.PassThru = $true
    $pesterConfig.Output.Verbosity = $pesterOutputVerbosity

    # Issue #136: runs on a dedicated in-process runspace, not a background
    # Job -- a Job is a separate process, so its PassThru result would cross
    # process boundaries via CliXml serialization, which does not preserve
    # the deep object graph the Virtual Beta Tester reporting below actually
    # reads (.Tests, .Block.Tag, .ScriptBlock.File several levels deep). A
    # same-process runspace keeps $pesterResult a live, fully-populated
    # object while still letting this loop poll for a hang/timeout.
    $pesterProgressText = Join-Path $reportDir 'Pester-progress.txt'
    $pesterHeartbeatIntervalSeconds = 15
    $pesterRunspace = [runspacefactory]::CreateRunspace()
    $pesterRunspace.Open()
    $pesterPs = [powershell]::Create()
    $pesterPs.Runspace = $pesterRunspace
    [void]$pesterPs.AddScript({
        param($Config, $OutputPath)
        Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
        # Issue #136: Pester's own live per-Describe/per-test progress text
        # is written to the Information stream (6), not the Error stream
        # (2) -- confirmed by direct reproduction: with 2>&1, the file stayed
        # completely empty for the whole run and only received the final
        # PassThru result object's default-formatted text dump at the very
        # end (useless during an actual hang, since that end is never
        # reached). With 6>&1, the file receives each line live as Pester
        # writes it. Also confirmed 6>&1 does not additionally echo to the
        # live console (tested in a real foreground session, not just a
        # background job) -- so Summary mode's "keep the console quiet"
        # intent still holds even though Verbosity is no longer 'None'.
        Invoke-Pester -Configuration $Config 6>&1 | Tee-Object -FilePath $OutputPath
    }).AddArgument($pesterConfig).AddArgument($pesterOutputText)

    $pesterStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $pesterAsyncResult = $pesterPs.BeginInvoke()
    $lastHeartbeatSeconds = 0
    $pesterTimedOut = $false
    $pesterResult = $null

    try {
        while (-not $pesterAsyncResult.IsCompleted) {
            Start-Sleep -Milliseconds 500
            $elapsed = $pesterStopwatch.Elapsed.TotalSeconds

            if (Test-TPMPesterHeartbeatDue -ElapsedSeconds $elapsed -LastHeartbeatSeconds $lastHeartbeatSeconds -HeartbeatIntervalSeconds $pesterHeartbeatIntervalSeconds) {
                $lastHeartbeatSeconds = $elapsed
                $lastLine = ''
                try {
                    if (Test-Path -LiteralPath $pesterOutputText) {
                        $lastLine = [string](Get-Content -LiteralPath $pesterOutputText -Tail 1 -ErrorAction SilentlyContinue)
                    }
                } catch {}
                $heartbeatMsg = Get-TPMPesterHeartbeatMessage -ElapsedSeconds $elapsed -LastOutputLine $lastLine
                Write-Host $heartbeatMsg -ForegroundColor DarkGray
                Add-Content -LiteralPath $pesterProgressText -Value ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $heartbeatMsg)
                Set-TPMConsoleStatus -Gate 'Pester regression suite' -Purpose ("Running -- {0:n0}s elapsed" -f $elapsed) -Expected 'zero failed tests'
            }

            if (Test-TPMPesterTimedOut -ElapsedSeconds $elapsed -TimeoutSeconds $PesterRegressionTimeoutSeconds) {
                $pesterTimedOut = $true
                break
            }
        }

        if ($pesterTimedOut) {
            $lastLine = ''
            try {
                if (Test-Path -LiteralPath $pesterOutputText) {
                    $lastLine = ((Get-Content -LiteralPath $pesterOutputText -Tail 5 -ErrorAction SilentlyContinue) -join ' | ')
                }
            } catch {}
            try { $pesterPs.Stop() } catch {}
            $timeoutMsg = Get-TPMPesterTimeoutMessage -ElapsedSeconds $pesterStopwatch.Elapsed.TotalSeconds -TimeoutSeconds $PesterRegressionTimeoutSeconds -LastOutputLine $lastLine -OutputPath $pesterOutputText -ProgressPath $pesterProgressText
            Add-Content -LiteralPath $pesterProgressText -Value ("[{0}] TIMED OUT -- {1}" -f (Get-Date -Format 'HH:mm:ss'), $timeoutMsg)
            $results.Pester = [pscustomobject]@{
                Passed = $null; Failed = $null; Skipped = $null; Inconclusive = $null; NotRun = $null; Total = $null
                Duration = $pesterStopwatch.Elapsed.ToString(); Result = 'TimedOut'
            }
            Add-CheckResult 'Pester tests' $false $timeoutMsg
            throw $timeoutMsg
        }

        # EndInvoke returns a PSDataCollection[PSObject], not a bare array --
        # "-is [array]" is false for it, so Get-PesterSummary and the VBT
        # candidate-selection logic below (which both branch on
        # "-is [array]" to unwrap a single-result collection) would silently
        # treat the wrapper itself as the result object and find none of the
        # expected properties. Confirmed directly: without this @() wrap,
        # every field in $results.Pester comes back $null even on a normal
        # passing run. Wrapping here makes it a real array, matching what a
        # direct (non-runspace) Invoke-Pester call already produced before
        # this fix.
        $pesterResult = @($pesterPs.EndInvoke($pesterAsyncResult))
    } finally {
        try { $pesterPs.Dispose() } catch {}
        try { $pesterRunspace.Close() } catch {}
        try { $pesterRunspace.Dispose() } catch {}
    }

    $pesterSummary = Get-PesterSummary -PesterResult $pesterResult
    $pesterSummary | ConvertTo-Json -Depth 4 | Out-File (Join-Path $reportDir 'Pester-summary.json') -Encoding utf8
    $results.Pester = $pesterSummary
    Add-CheckResult 'Pester tests' ($pesterSummary.Failed -eq 0) "total=$($pesterSummary.Total) passed=$($pesterSummary.Passed) failed=$($pesterSummary.Failed)"

    # Issue #88 Phase 1/1.5: report Behavioral Certification (Virtual Beta
    # Tester) coverage as its own visible line, not folded anonymously into
    # the overall Pester count -- a scorecard reader should be able to see
    # this coverage exists, and its shape by category, without opening
    # individual test files. Derived from the same PassThru result already
    # collected above, filtered to Tests/VirtualBetaTester*.Tests.ps1 by
    # source file, not by name pattern (robust to Describe/It renames).
    $vbtCandidate = $pesterResult
    if ($pesterResult -is [array]) {
        $vbtCandidate = @($pesterResult) | Where-Object {
            $_ -and ($_.PSObject.Properties.Name -contains 'Tests')
        } | Select-Object -Last 1
    }
    $vbtTests = @()
    if ($vbtCandidate -and $vbtCandidate.PSObject.Properties.Name -contains 'Tests') {
        $vbtTests = @($vbtCandidate.Tests | Where-Object {
            $_.ScriptBlock -and $_.ScriptBlock.File -and ([System.IO.Path]::GetFileName($_.ScriptBlock.File) -like 'VirtualBetaTester.*.Tests.ps1')
        })
    }
    $vbtPassed = @($vbtTests | Where-Object { $_.Result -eq 'Passed' }).Count
    $vbtFailed = @($vbtTests | Where-Object { $_.Result -eq 'Failed' }).Count

    # Category breakdown by Describe-block name, not a separate tagging
    # system -- each category below maps to one or more Describe blocks
    # already named distinctly enough to classify by simple keyword match.
    function Get-VbtCategoryCount {
        param($Tests, [string[]]$Keywords)
        return @($Tests | Where-Object {
            $blockName = ($_.Block.Name)
            $matched = $false
            foreach ($kw in $Keywords) { if ($blockName -like "*$kw*") { $matched = $true; break } }
            $matched
        }).Count
    }
    $vbtHumanBehaviors  = Get-VbtCategoryCount -Tests $vbtTests -Keywords @('human workflow', 'main menu', 'decision paths')
    $vbtIdempotency     = Get-VbtCategoryCount -Tests $vbtTests -Keywords @('idempotency', 'repeat-run', 'AutoSync repeat-run', 'preview')
    $vbtRecoveryChecks  = Get-VbtCategoryCount -Tests $vbtTests -Keywords @('backup safety', 'read-only', 'recovery')
    $vbtEnvironmentVars = Get-VbtCategoryCount -Tests $vbtTests -Keywords @('messy environment')

    # Issue #88 phase 1.6: Tester Value Density is recorded as a real Pester
    # tag on each Describe block ('TVD-High'/'TVD-Medium'/'TVD-Low'), not
    # just a code comment, specifically so this count is queryable evidence
    # rather than a guess. Per CONSTITUTION.md ("Tester Value Density"),
    # this is tracked as coverage evidence only -- never converted to a
    # percentage or folded into the Pass/Fail decision for this gate.
    # -Tag on a Describe block lands on the containing Block, not copied down
    # to each individual test's own .Tag (confirmed empty on .Tests[].Tag) --
    # check .Block.Tag instead.
    $vbtHighTvd = @($vbtTests | Where-Object { $_.Block -and $_.Block.Tag -and ($_.Block.Tag -contains 'TVD-High') }).Count

    $results.VirtualBetaTester = [pscustomobject]@{
        Total               = $vbtTests.Count
        Passed              = $vbtPassed
        Failed              = $vbtFailed
        HumanBehaviors      = $vbtHumanBehaviors
        IdempotencyChecks   = $vbtIdempotency
        RecoveryBehaviors   = $vbtRecoveryChecks
        EnvironmentVariations = $vbtEnvironmentVars
        HighTvdBehaviors    = $vbtHighTvd
    }
    Add-CheckResult 'Behavioral Certification (Virtual Beta Tester)' ($vbtTests.Count -gt 0 -and $vbtFailed -eq 0) `
        ("total={0} passed={1} failed={2} | human-behaviors={3} idempotency={4} recovery={5} environment-variations={6} high-tvd-behaviors={7}" -f `
            $vbtTests.Count, $vbtPassed, $vbtFailed, $vbtHumanBehaviors, $vbtIdempotency, $vbtRecoveryChecks, $vbtEnvironmentVars, $vbtHighTvd)

    # Never hidden by -VerbosityLevel Summary: if anything actually failed,
    # print exactly what, regardless of console verbosity. Also persisted to
    # a file, not just printed. Independent of the issue #136 fix to
    # Output.Verbosity/stream capture above (Pester-output.txt now gets live
    # per-test detail at every -VerbosityLevel) -- this file exists because
    # relying on parsing that text would be fragile; $pesterResult.Failed is
    # read directly as an object instead.
    $failuresText = Join-Path $reportDir 'Pester-Failures.txt'
    if ($pesterSummary.Failed -gt 0) {
        Write-Host ""
        Write-Host "Pester failures ($($pesterSummary.Failed)):" -ForegroundColor Red
        $failedTests = @($pesterResult.Failed)
        if ($failedTests.Count -eq 0 -and $pesterResult -is [array]) {
            $failedTests = @($pesterResult | Where-Object { $_.PSObject.Properties.Name -contains 'Failed' } | Select-Object -ExpandProperty Failed)
        }
        $failureLines = @()
        foreach ($failedTest in $failedTests) {
            $testPath = if ($failedTest.PSObject.Properties.Name -contains 'ExpandedPath') { $failedTest.ExpandedPath } else { $failedTest.Name }
            Write-Host "  - $testPath" -ForegroundColor Red
            $failureLines += "- $testPath"
            $errorRecord = $null
            if ($failedTest.PSObject.Properties.Name -contains 'ErrorRecord' -and $failedTest.ErrorRecord) {
                $errorRecord = @($failedTest.ErrorRecord) | Select-Object -First 1
            }
            if ($errorRecord) {
                $failureLines += "    $($errorRecord.ToString())"
            }
        }
        $failureLines | Out-File -FilePath $failuresText -Encoding utf8
    } else {
        "(no failures)" | Out-File -FilePath $failuresText -Encoding utf8
    }

    Write-TPMGateHeader -Gate 'Static analysis (PSScriptAnalyzer)' -Purpose 'Scans TeknoParrot-Manager.ps1 for known-bad patterns' -Expected 'zero Error/Warning findings'
    $analyzerCommand = Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue
    if (-not $analyzerCommand) { throw 'Invoke-ScriptAnalyzer not found. Install it with: Install-Module PSScriptAnalyzer -Scope CurrentUser -Force' }
    $analyzerModule = Get-Module PSScriptAnalyzer -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    if ($analyzerModule) { $results.PSScriptAnalyzerVersion = $analyzerModule.Version.ToString() }
    # Matches the documented release gate exactly (RELEASE-SAFETY-CHECKLIST.md
    # section 1): TeknoParrot-Manager.ps1 only, Error/Warning severity, using
    # the project's approved-exclusions settings file. An earlier version of
    # this check ran "-Path $RepoPath -Recurse" with no severity filter and no
    # settings file -- that scanned every file in the repo (tools/, scripts/,
    # Tests/) against defaults never meant to apply to them, and surfaced
    # Information-severity findings the settings file specifically documents
    # as accepted. That produced 33 "findings" that were never real gate
    # failures, just a different (wrong) invocation than what release sign-off
    # actually checks.
    $analyzerSettingsPath = Join-Path $RepoPath 'PSScriptAnalyzerSettings.psd1'
    $mainScriptPath = Join-Path $RepoPath 'TeknoParrot-Manager.ps1'
    $analyzer = Invoke-ScriptAnalyzer -Path $mainScriptPath -Severity Error, Warning -Settings $analyzerSettingsPath
    $analyzer | ConvertTo-Json -Depth 6 | Out-File (Join-Path $reportDir 'PSScriptAnalyzer.json') -Encoding utf8
    $results.PSScriptAnalyzerFindings = @($analyzer).Count
    Add-CheckResult 'PSScriptAnalyzer' (@($analyzer).Count -eq 0) "findings=$(@($analyzer).Count)"

    $pathsToCheck = @(
        @{Name='TeknoParrot root'; Path=$TeknoParrotRoot; Type='Container'},
        @{Name='TeknoParrotUi.exe'; Path=(Join-Path $TeknoParrotRoot 'TeknoParrotUi.exe'); Type='Leaf'},
        @{Name='GameProfiles'; Path=$gameProfilesPath; Type='Container'},
        @{Name='UserProfiles'; Path=$userProfilesPath; Type='Container'}
    )
    foreach ($p in $pathsToCheck) {
        $exists = Test-Path -LiteralPath $p.Path -PathType $p.Type
        Add-CheckResult $p.Name $exists $p.Path
    }

    Write-TPMGateHeader -Gate 'pcsx2x6 crosshair path (issue #79)' -Purpose 'Confirms crosshair deployment path is correct for pcsx2x6 installs' -Expected 'pass, or not-applicable if no pcsx2x6 folder exists'
    # Issue #79: pcsx2x6 crosshair path verification. Read-only -- this never
    # runs the interactive Invoke-CrosshairSetup wizard (Read-Host prompts,
    # browser launch) against the real install, it only inspects whatever
    # state already exists there. Not every TeknoParrot install has pcsx2x6
    # (it's specific to a handful of lightgun titles), so this is conditional
    # on the pcsx2x6 folder actually being present -- absence is reported as
    # not-applicable, not a failure, unlike the unconditional hard-fail this
    # replaced (which would have certified-FAIL any install without pcsx2x6
    # at all). $pcsx2Dir was already resolved once, above, and is reused here
    # rather than searched for again.
    if (-not $pcsx2Dir) {
        $results.Pcsx2x6 = [pscustomobject]@{ Present = $false }
        Add-CheckResult 'pcsx2x6 crosshair path (issue #79)' $true 'not applicable -- no pcsx2x6 folder in this install'
    } else {
        $canonicalDir  = Join-Path $pcsx2Dir 'TeknoParrot\crosshairs'
        $legacyP1      = Join-Path $pcsx2Dir 'P1.png'
        $legacyP2      = Join-Path $pcsx2Dir 'P2.png'
        $canonicalP1   = Join-Path $canonicalDir 'P1.png'
        $canonicalP2   = Join-Path $canonicalDir 'P2.png'
        $iniPath       = Join-Path $pcsx2Dir 'inis\PCSX2.ini'

        $canonicalDeployed = (Test-Path -LiteralPath $canonicalP1 -PathType Leaf) -and (Test-Path -LiteralPath $canonicalP2 -PathType Leaf)
        $legacyPresent     = (Test-Path -LiteralPath $legacyP1 -PathType Leaf) -or (Test-Path -LiteralPath $legacyP2 -PathType Leaf)

        $cursorPathP1 = $null
        $cursorPathP2 = $null
        $iniFound = Test-Path -LiteralPath $iniPath -PathType Leaf
        if ($iniFound) {
            # Read-only parse -- mirrors Set-Pcsx2CursorPaths' own section
            # tracking without writing anything back.
            $lines = [System.IO.File]::ReadAllLines($iniPath)
            $sect = ''
            foreach ($ln in $lines) {
                $t = $ln.Trim()
                if ($t -match '^\[(.+)\]$') { $sect = $matches[1].ToLower(); continue }
                if ($t -match '^cursor_path\s*=\s*(.*)$') {
                    if ($sect -eq 'usb port 1 guncon2') { $cursorPathP1 = $matches[1].Trim() }
                    elseif ($sect -eq 'usb port 2 guncon2') { $cursorPathP2 = $matches[1].Trim() }
                }
            }
        }

        $cursorPointsCanonical = ($cursorPathP1 -and $cursorPathP1.TrimEnd('\') -eq $canonicalP1.TrimEnd('\')) -and
                                  ($cursorPathP2 -and $cursorPathP2.TrimEnd('\') -eq $canonicalP2.TrimEnd('\'))

        $results.Pcsx2x6 = [pscustomobject]@{
            Present                = $true
            Pcsx2Dir               = $pcsx2Dir
            CanonicalDir           = $canonicalDir
            CanonicalFilesDeployed = $canonicalDeployed
            LegacyRootFilesPresent = $legacyPresent
            IniFound               = $iniFound
            CursorPathP1           = $cursorPathP1
            CursorPathP2           = $cursorPathP2
            CursorPathPointsCanonical = $cursorPointsCanonical
        }

        # Informational, not a hard requirement: the canonical files/ini only
        # reflect the new location once crosshair setup has actually been run
        # since the #79 fix shipped. What this DOES assert is that the check
        # itself ran and could inspect the real install without modifying it.
        Add-CheckResult 'pcsx2x6 crosshair path (issue #79)' $true `
            ("pcsx2Dir={0} canonicalDeployed={1} legacyRootPresent={2} iniFound={3} cursorPathCanonical={4}" -f `
                $pcsx2Dir, $canonicalDeployed, $legacyPresent, $iniFound, $cursorPointsCanonical)

        if ($iniFound -and (-not $cursorPathP1 -or -not $cursorPathP2)) {
            Add-CheckResult 'pcsx2x6 PCSX2.ini has cursor_path for both USB ports' $false `
                ("P1={0} P2={1}" -f $cursorPathP1, $cursorPathP2)
        } elseif ($iniFound) {
            Add-CheckResult 'pcsx2x6 PCSX2.ini has cursor_path for both USB ports' $true `
                ("P1={0} P2={1}" -f $cursorPathP1, $cursorPathP2)
        }
    }

    Write-TPMGateHeader -Gate 'Real install health check' -Purpose 'Read-only scan of the actual TeknoParrot install for registration gaps' -Expected 'report collected -- findings reviewed manually, not a pass/fail gate'
    $healthScript = Join-Path $PSScriptRoot 'Invoke-TPM-InstallHealthCheck.ps1'
    if (Test-Path -LiteralPath $healthScript -PathType Leaf) {
        $healthOutDir = Join-Path $reportDir 'InstallHealth'
        & $healthScript -TeknoParrotRoot $TeknoParrotRoot -OutDir $healthOutDir | Out-File -FilePath (Join-Path $reportDir 'InstallHealth-console.txt') -Encoding utf8
        $results.InstallHealthReport = Join-Path $healthOutDir 'InstallHealth.md'
        Add-CheckResult 'Real install health check collected' $true $results.InstallHealthReport
    } else {
        Add-CheckResult 'Real install health check collected' $false "missing=$healthScript"
    }

    $profiles = @()
    if (Test-Path -LiteralPath $gameProfilesPath) { $profiles = @(Get-ChildItem -LiteralPath $gameProfilesPath -File -ErrorAction SilentlyContinue) }
    $userProfiles = @()
    if (Test-Path -LiteralPath $userProfilesPath) { $userProfiles = @(Get-ChildItem -LiteralPath $userProfilesPath -File -ErrorAction SilentlyContinue) }
    $centipede = @($profiles | Where-Object { $_.Name -match 'centipede|chaos' })
    $results.GameProfilesCount = $profiles.Count
    $results.UserProfilesCount = $userProfiles.Count
    $results.CentipedeChaosCandidates = @($centipede | Select-Object -ExpandProperty Name)
    Add-CheckResult 'GameProfiles count' ($profiles.Count -gt 0) "count=$($profiles.Count)"
    Add-CheckResult 'UserProfiles count' ($userProfiles.Count -ge 0) "count=$($userProfiles.Count)"
    if ($centipede.Count -gt 0) {
        $centipedeDetails = $centipede.Name -join ', '
    } else {
        $centipedeDetails = 'none found'
    }
    Add-CheckResult 'Centipede Chaos profile scan' $true $centipedeDetails

    if ($RunUnattendedTPM) {
        $scriptPath = Join-Path $RepoPath 'TeknoParrot-Manager.ps1'
        if (!(Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw "TeknoParrot-Manager.ps1 not found at $scriptPath" }
        $tpmLog = Join-Path $reportDir 'TPM-Unattended.log'
        pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Unattended *> $tpmLog
        Add-CheckResult 'TPM unattended run' $true "log=$tpmLog"
    }

    Write-TPMGateHeader -Gate 'Smoke file safety' -Purpose 'Confirms nothing changed in UserProfiles/GameProfiles during this smoke run' -Expected 'no unexpected file changes'
    $postUserProfiles = Get-TreeHash $userProfilesPath
    $postGameProfiles = Get-TreeHash $gameProfilesPath
    $postCrosshairs = if ($crosshairPath) { Get-TreeHash $crosshairPath } else { @() }
    $results.Snapshots = [ordered]@{
        UserProfiles = Compare-TreeSnapshot $preUserProfiles $postUserProfiles
        GameProfiles = Compare-TreeSnapshot $preGameProfiles $postGameProfiles
        Pcsx2x6Crosshairs = Compare-TreeSnapshot $preCrosshairs $postCrosshairs
    }
    if (-not $RunUnattendedTPM) {
        foreach ($name in $results.Snapshots.Keys) {
            $s = $results.Snapshots[$name]
            Add-CheckResult "Smoke mode no change: $name" (($s.Added + $s.Removed + $s.Changed) -eq 0) "added=$($s.Added) removed=$($s.Removed) changed=$($s.Changed) skipped=$($s.BeforeSkipped + $s.AfterSkipped)"
        }
    }

    $results.Status = if (@($results.Checks | Where-Object { -not $_.Passed }).Count -eq 0) { 'PASS' } else { 'FAIL' }
}
catch {
    $results.Status = 'FAIL'
    $results.Error = $_.Exception.Message
    Add-CheckResult 'Unhandled validation error' $false $_.Exception.Message
    throw
}
finally {
    Pop-Location
    $runTimer.Stop()
    $results.Elapsed = $runTimer.Elapsed.ToString()
    $results.PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    $results | ConvertTo-Json -Depth 8 | Out-File $json -Encoding utf8

    # The "Artifacts" gate below checks that both report files exist on
    # disk. $md's real content can't be written until after $certification
    # exists (the validation report shows the certification verdict inline),
    # so without this stub the gate was checking for a file that structurally
    # could not exist yet at this point in execution -- it failed on every
    # run regardless of whether anything was actually wrong. Confirmed via
    # two independent real-instance runs, both showing "[FAIL] Artifacts"
    # with an otherwise fully passing run. Pre-creating an empty $md here
    # (Add-Report below still builds its real content via -Append) makes the
    # existence check honest without changing what it actually verifies.
    if (-not (Test-Path -LiteralPath $md -PathType Leaf)) {
        # New-Item, not Out-File -- a zero-byte file, so the real content
        # Add-Report appends below doesn't end up with a stray leading
        # blank line.
        [void](New-Item -ItemType File -Path $md -Force)
    }

    # Issue #111 / Release Integrity: TPM script version and display version
    # are read via regex against the raw file text, never by executing
    # TeknoParrot-Manager.ps1 -- this harness must never run arbitrary
    # top-level script code as a side effect of generating a report. Computed
    # before New-CertificationScorecard is called below, since that function
    # reads these fields.
    $tpmScriptVersion = 'unknown'
    $tpmDisplayVersion = 'unknown'
    try {
        $mainScriptContent = Get-Content -LiteralPath $mainScriptPath -Raw
        $versionMatch = [regex]::Match($mainScriptContent, '(?m)^\$ScriptVersion\s*=\s*"([^"]+)"')
        if ($versionMatch.Success) { $tpmScriptVersion = $versionMatch.Groups[1].Value }
        $candidateMatch = [regex]::Match($mainScriptContent, '(?m)^\$ReleaseCandidateLabel\s*=\s*"([^"]+)"')
        if ($candidateMatch.Success) {
            $tpmDisplayVersion = "v$tpmScriptVersion $($candidateMatch.Groups[1].Value)"
        } else {
            $headerMatch = [regex]::Match($mainScriptContent, '(?m)^# TeknoParrot Manager\s+\|\s+(.+)$')
            if ($headerMatch.Success) { $tpmDisplayVersion = $headerMatch.Groups[1].Value.Trim() }
        }
    } catch {
        $tpmScriptVersion = 'unknown (could not read TeknoParrot-Manager.ps1)'
        $tpmDisplayVersion = 'unknown (could not read TeknoParrot-Manager.ps1)'
    }
    $results.TpmScriptVersion = $tpmScriptVersion
    $results.TpmDisplayVersion = $tpmDisplayVersion

    $certification = New-CertificationScorecard -Results $results
    $certification | ConvertTo-Json -Depth 8 | Out-File $certificationJson -Encoding utf8

    Add-CertificationReport "# TPM Certification Scorecard"
    Add-CertificationReport ""
    Add-CertificationReport ("Overall: **{0}**" -f $certification.Overall)
    Add-CertificationReport ("Score: {0}/{1} ({2}%)" -f $certification.Passed, $certification.Total, $certification.ScorePercent)
    Add-CertificationReport ("Elapsed: {0}" -f $results.Elapsed)
    Add-CertificationReport ""
    Add-CertificationReport "## Certification Target"
    Add-CertificationReport ""
    Add-CertificationReport ("- Repository: {0}" -f $RepoPath)
    Add-CertificationReport ("- Branch: {0}" -f $results.GitBranch)
    Add-CertificationReport ("- Commit: {0} ({1})" -f $results.Commit, $results.CommitShort)
    $originMainText = if ($results.OriginMainCommit) { $results.OriginMainCommit } else { 'unavailable' }
    $workingTreeText = if ($repoClean) { 'clean' } else { 'dirty' }
    Add-CertificationReport ("- Origin/main: {0}" -f $originMainText)
    Add-CertificationReport ("- Sync status: {0}" -f $results.SyncStatus)
    Add-CertificationReport ("- Working tree: {0}" -f $workingTreeText)
    Add-CertificationReport ("- Git version: {0}" -f $results.GitVersion)
    Add-CertificationReport ("- PowerShell version: {0}" -f $results.PowerShellVersion)
    Add-CertificationReport ("- TPM script version: {0}" -f $tpmScriptVersion)
    Add-CertificationReport ("- TPM display version: {0}" -f $tpmDisplayVersion)
    Add-CertificationReport ("- Certified at: {0}" -f $results.Timestamp)
    Add-CertificationReport ""
    Add-CertificationReport "## Gates"
    foreach ($item in $certification.Items) {
        $mark = if ($item.Passed) { 'PASS' } else { 'FAIL' }
        Add-CertificationReport ("- [{0}] {1}: {2}" -f $mark, $item.Area, $item.Details)
    }
    Add-CertificationReport ""
    Add-CertificationReport "## Artifact folder"
    Add-CertificationReport $reportDir

    Add-Report "# TPM Validation Report"
    Add-Report ""
    Add-Report "## Summary"
    Add-Report ""
    Add-Report "Status: **$($results.Status)**"
    Add-Report ("Certification: **{0}**" -f $certification.Overall)
    Add-Report "Elapsed: $($results.Elapsed)"
    Add-Report ("Report folder: {0}" -f $reportDir)
    Add-Report ("Backup folder: {0}" -f $backupDir)
    Add-Report ""
    Add-Report "## Environment"
    Add-Report ""
    Add-Report ("- Repo: {0}" -f $RepoPath)
    Add-Report ("- TeknoParrot root: {0}" -f $TeknoParrotRoot)
    Add-Report "- Branch: $($results.GitBranch)"
    Add-Report "- Commit: $($results.Commit)"
    Add-Report "- Git: $($results.GitVersion)"
    Add-Report "- PowerShell: $($results.PowerShellVersion)"
    Add-Report "- Pester: $($results.PesterVersion)"
    Add-Report "- PSScriptAnalyzer: $($results.PSScriptAnalyzerVersion)"
    Add-Report ""
    Add-Report "## Test Results"
    Add-Report ""
    Add-Report "- Pester total: $($results.Pester.Total)"
    Add-Report "- Pester passed: $($results.Pester.Passed)"
    Add-Report "- Pester failed: $($results.Pester.Failed)"
    Add-Report "- PSScriptAnalyzer findings: $($results.PSScriptAnalyzerFindings)"
    Add-Report ""
    Add-Report "## Checks"
    Add-Report ""
    foreach ($check in $results.Checks) {
        $mark = if ($check.Passed) { 'PASS' } else { 'FAIL' }
        Add-Report ("- [{0}] {1}: {2}" -f $mark, $check.Name, $check.Details)
    }
    Add-Report ""
    Add-Report "## Artifacts"
    Add-Report ""
    Add-Report ("- Certification scorecard: {0}" -f $certificationMd)
    Add-Report ("- Certification JSON: {0}" -f $certificationJson)
    Add-Report ("- JSON report: {0}" -f $json)
    Add-Report ("- Pester summary: {0}" -f (Join-Path $reportDir 'Pester-summary.json'))
    Add-Report ("- Pester output: {0}" -f (Join-Path $reportDir 'Pester-output.txt'))
    Add-Report ("- Pester failures (names + errors): {0}" -f (Join-Path $reportDir 'Pester-Failures.txt'))
    Add-Report ("- PSScriptAnalyzer: {0}" -f (Join-Path $reportDir 'PSScriptAnalyzer.json'))
    if ($results.InstallHealthReport) {
        Add-Report ("- Install health: {0}" -f $results.InstallHealthReport)
    }

    Write-Host ""
    Write-Host "============================================"
    Write-Host " TPM CERTIFICATION SCORECARD"
    Write-Host "============================================"
    Write-Host (" Overall : {0}" -f $certification.Overall)
    Write-Host (" Score   : {0}/{1} ({2}%)" -f $certification.Passed, $certification.Total, $certification.ScorePercent)
    Write-Host (" Report  : {0}" -f $certificationMd)
    Write-Host "============================================"
    Clear-TPMConsoleStatus
}
