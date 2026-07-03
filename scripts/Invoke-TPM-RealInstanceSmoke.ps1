param(
    [Parameter(Mandatory=$true)]
    [string]$RepoPath,

    [Parameter(Mandatory=$true)]
    [string]$TeknoParrotRoot,

    [string]$HarnessRoot,

    [switch]$RunUnattendedTPM
)

$ErrorActionPreference = "Stop"
$runTimer = [System.Diagnostics.Stopwatch]::StartNew()

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

function Add-Report {
    param([string]$Text)
    $Text | Out-File -FilePath $md -Append -Encoding utf8
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

    $backupItems = [ordered]@{}
    $backupItems.UserProfiles = Copy-IfExists (Join-Path $TeknoParrotRoot 'UserProfiles') 'UserProfiles'
    $backupItems.GameProfiles = Copy-IfExists (Join-Path $TeknoParrotRoot 'GameProfiles') 'GameProfiles'
    $backupItems.Pcsx2x6Crosshairs = Copy-IfExists (Join-Path $TeknoParrotRoot 'pcsx2x6\TeknoParrot\crosshairs') 'pcsx2x6-crosshairs'
    $backupItems.Config = Copy-IfExists (Join-Path $RepoPath 'TeknoParrot-Manager.config.json') 'TeknoParrot-Manager.config.json'
    $results.Backup = $backupItems

    $userProfilesPath = Join-Path $TeknoParrotRoot 'UserProfiles'
    $gameProfilesPath = Join-Path $TeknoParrotRoot 'GameProfiles'
    $crosshairPath = Join-Path $TeknoParrotRoot 'pcsx2x6\TeknoParrot\crosshairs'
    $preUserProfiles = Get-TreeHash $userProfilesPath
    $preGameProfiles = Get-TreeHash $gameProfilesPath
    $preCrosshairs = Get-TreeHash $crosshairPath

    $pesterCommand = Get-Command Invoke-Pester -ErrorAction SilentlyContinue
    if (-not $pesterCommand) { throw 'Invoke-Pester not found. Install it with: Install-Module Pester -Scope CurrentUser -Force' }
    $pesterModule = Get-Module Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    if ($pesterModule) { $results.PesterVersion = $pesterModule.Version.ToString() }
    $pesterOutputText = Join-Path $reportDir 'Pester-output.txt'
    $pesterResult = Invoke-Pester -Path $RepoPath -PassThru 2>&1 | Tee-Object -FilePath $pesterOutputText
    $pesterSummary = Get-PesterSummary -PesterResult $pesterResult
    $pesterSummary | ConvertTo-Json -Depth 4 | Out-File (Join-Path $reportDir 'Pester-summary.json') -Encoding utf8
    $results.Pester = $pesterSummary
    Add-CheckResult 'Pester tests' ($pesterSummary.Failed -eq 0) "total=$($pesterSummary.Total) passed=$($pesterSummary.Passed) failed=$($pesterSummary.Failed)"

    $analyzerCommand = Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue
    if (-not $analyzerCommand) { throw 'Invoke-ScriptAnalyzer not found. Install it with: Install-Module PSScriptAnalyzer -Scope CurrentUser -Force' }
    $analyzerModule = Get-Module PSScriptAnalyzer -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    if ($analyzerModule) { $results.PSScriptAnalyzerVersion = $analyzerModule.Version.ToString() }
    $analyzer = Invoke-ScriptAnalyzer -Path $RepoPath -Recurse
    $analyzer | ConvertTo-Json -Depth 6 | Out-File (Join-Path $reportDir 'PSScriptAnalyzer.json') -Encoding utf8
    $results.PSScriptAnalyzerFindings = @($analyzer).Count
    Add-CheckResult 'PSScriptAnalyzer' (@($analyzer).Count -eq 0) "findings=$(@($analyzer).Count)"

    $pathsToCheck = @(
        @{Name='TeknoParrot root'; Path=$TeknoParrotRoot; Type='Container'},
        @{Name='TeknoParrotUi.exe'; Path=(Join-Path $TeknoParrotRoot 'TeknoParrotUi.exe'); Type='Leaf'},
        @{Name='GameProfiles'; Path=$gameProfilesPath; Type='Container'},
        @{Name='UserProfiles'; Path=$userProfilesPath; Type='Container'},
        @{Name='pcsx2x6 crosshair directory'; Path=$crosshairPath; Type='Container'}
    )
    foreach ($p in $pathsToCheck) {
        $exists = Test-Path -LiteralPath $p.Path -PathType $p.Type
        Add-CheckResult $p.Name $exists $p.Path
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
    $postCrosshairs = Get-TreeHash $crosshairPath
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

    Add-Report "# TPM Validation Report"
    Add-Report ""
    Add-Report "## Summary"
    Add-Report ""
    Add-Report "Status: **$($results.Status)**"
    Add-Report "Elapsed: $($results.Elapsed)"
    Add-Report "Report folder: `$reportDir`"
    Add-Report "Backup folder: `$backupDir`"
    Add-Report ""
    Add-Report "## Environment"
    Add-Report ""
    Add-Report "- Repo: `$RepoPath`"
    Add-Report "- TeknoParrot root: `$TeknoParrotRoot`"
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
        Add-Report "- [$mark] $($check.Name): $($check.Details)"
    }
    Add-Report ""
    Add-Report "## Artifacts"
    Add-Report ""
    Add-Report "- JSON report: `$json`"
    Add-Report "- Pester summary: `$(Join-Path $reportDir 'Pester-summary.json')`"
    Add-Report "- Pester output: `$(Join-Path $reportDir 'Pester-output.txt')`"
    Add-Report "- PSScriptAnalyzer: `$(Join-Path $reportDir 'PSScriptAnalyzer.json')`"
    if ($results.InstallHealthReport) {
        Add-Report "- Install health: `$($results.InstallHealthReport)`"
    }
}
