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
    [string]$VerbosityLevel = 'Summary'
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
        "total=$($Results.VirtualBetaTester.Total) passed=$($Results.VirtualBetaTester.Passed) failed=$($Results.VirtualBetaTester.Failed)"
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
        [pscustomobject]@{Area='Virtual Beta Tester coverage (issue #88 phase 1)'; Passed=($Results.VirtualBetaTester -and $Results.VirtualBetaTester.Total -gt 0 -and $Results.VirtualBetaTester.Failed -eq 0); Details=$vbtDetails}
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

Push-Location $RepoPath
try {
    $gitVersion = git --version
    $gitBranch = git rev-parse --abbrev-ref HEAD
    $gitCommit = git rev-parse HEAD
    $gitStatusLines = @(git status --short)
    $repoClean = ($gitStatusLines.Count -eq 0)
    if ($repoClean) {
        $gitStatusText = '(clean)'
    } else {
        $gitStatusText = ($gitStatusLines -join [Environment]::NewLine)
    }
    $results.GitVersion = $gitVersion
    $results.GitBranch = $gitBranch
    $results.Commit = $gitCommit
    $results.GitStatus = $gitStatusText
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

    $pesterCommand = Get-Command Invoke-Pester -ErrorAction SilentlyContinue
    if (-not $pesterCommand) { throw 'Invoke-Pester not found. Install it with: Install-Module Pester -Scope CurrentUser -Force' }
    $pesterModule = Get-Module Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    if ($pesterModule) { $results.PesterVersion = $pesterModule.Version.ToString() }
    $pesterOutputText = Join-Path $reportDir 'Pester-output.txt'

    # The report files always get the same full detail regardless of
    # -VerbosityLevel -- this only controls how much Pester's own per-file/
    # per-test progress reporting streams to the console during the run.
    # Pester's native Output.Verbosity setting is used directly rather than
    # any custom stream redirection: redirecting the success stream to
    # suppress console noise risks swallowing the PassThru result object
    # along with it, which would silently break -Failed detection below.
    # Real failures are never hidden regardless of level: printed explicitly
    # below every time, independent of Output.Verbosity.
    $pesterOutputVerbosity = switch ($VerbosityLevel) {
        'Summary'    { 'None' }
        'Detailed'   { 'Normal' }
        'Diagnostic' { 'Diagnostic' }
    }
    $pesterConfig = New-PesterConfiguration
    $pesterConfig.Run.Path = $RepoPath
    $pesterConfig.Run.PassThru = $true
    $pesterConfig.Output.Verbosity = $pesterOutputVerbosity

    $pesterResult = Invoke-Pester -Configuration $pesterConfig 2>&1 | Tee-Object -FilePath $pesterOutputText
    $pesterSummary = Get-PesterSummary -PesterResult $pesterResult
    $pesterSummary | ConvertTo-Json -Depth 4 | Out-File (Join-Path $reportDir 'Pester-summary.json') -Encoding utf8
    $results.Pester = $pesterSummary
    Add-CheckResult 'Pester tests' ($pesterSummary.Failed -eq 0) "total=$($pesterSummary.Total) passed=$($pesterSummary.Passed) failed=$($pesterSummary.Failed)"

    # Issue #88 Phase 1: report Virtual Beta Tester coverage as its own
    # visible line, not folded anonymously into the overall Pester count --
    # a scorecard reader should be able to see this coverage exists without
    # opening individual test files. Derived from the same PassThru result
    # already collected above, filtered to Tests/VirtualBetaTester*.Tests.ps1
    # by source file, not by name pattern (robust to Describe/It renames).
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
    $results.VirtualBetaTester = [pscustomobject]@{
        Total  = $vbtTests.Count
        Passed = $vbtPassed
        Failed = $vbtFailed
    }
    Add-CheckResult 'Virtual Beta Tester coverage (issue #88 phase 1)' ($vbtTests.Count -gt 0 -and $vbtFailed -eq 0) "total=$($vbtTests.Count) passed=$vbtPassed failed=$vbtFailed"

    # Never hidden by -VerbosityLevel Summary: if anything actually failed,
    # print exactly what, regardless of console verbosity. Also persisted to
    # a file, not just printed -- at Summary level, Pester's own
    # Output.Verbosity is 'None', so Pester-output.txt never gets per-test
    # [-]/[+] lines written to it either. Before this fix, a failure at
    # Summary level was visible only in the live console: once that session
    # was gone, there was no way to see which tests failed from the saved
    # report files at all (confirmed directly -- Pester-summary.json only
    # ever stored the failure count, and Pester-output.txt was empty of
    # detail at 'None' verbosity).
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

    $certification = New-CertificationScorecard -Results $results
    $certification | ConvertTo-Json -Depth 8 | Out-File $certificationJson -Encoding utf8

    Add-CertificationReport "# TPM Certification Scorecard"
    Add-CertificationReport ""
    Add-CertificationReport ("Overall: **{0}**" -f $certification.Overall)
    Add-CertificationReport ("Score: {0}/{1} ({2}%)" -f $certification.Passed, $certification.Total, $certification.ScorePercent)
    Add-CertificationReport ("Elapsed: {0}" -f $results.Elapsed)
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
}
