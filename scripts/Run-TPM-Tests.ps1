param(
    [string]$RepoPath,
    [Parameter(Mandatory = $true)]
    [string]$TeknoParrotRoot,
    [string]$HarnessRoot,
    [switch]$RunUnattendedTPM,
    [string]$ExpectedBranch,
    [string]$ExpectedCommit,
    [switch]$NoPwshRelaunch,
    [string]$ReportDirectory,
    [ValidateSet('Summary', 'Detailed', 'Diagnostic')]
    [string]$VerbosityLevel = 'Summary',
    [int]$PesterRegressionTimeoutSeconds = 1800
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
# This run reads a real TeknoParrot folder and copies profile files from it for the report, so it starts only when the operator opted in
# for this run with TPM_REAL_DATA_TESTS=1 (exactly 1). The same rule is in Invoke-TPM-RealInstanceSmoke.ps1. It is checked here first,
# before any module is loaded, any path is probed or any report folder is created.
if($env:TPM_REAL_DATA_TESTS-cne'1'){
    Write-Host 'This run reads a real TeknoParrot folder and copies profile files from it for the report. It did not start.'
    Write-Host ''
    Write-Host 'To allow it for this run only, set TPM_REAL_DATA_TESTS=1 and point -TeknoParrotRoot at the folder you want checked.'
    Write-Host ''
    Write-Host 'Nothing was read or changed.'
    exit 2
}
$executionModule=Join-Path $PSScriptRoot 'TPMCertification.Execution.psm1'
if(-not(Test-Path -LiteralPath $executionModule -PathType Leaf)){throw "Certification execution module not found: $executionModule"}
Import-Module $executionModule -Force

function Stop-TPMPreflightV1 {
    param([Parameter(Mandatory=$true)][string[]]$Failures,[Parameter(Mandatory=$true)][string]$ReportDirectory)
    Write-Host 'TeknoParrot Manager Certification'
    Write-Host ''
    Write-Host 'Prerequisite checks failed. Certification did not start.'
    $number=1
    foreach($failure in $Failures){Write-Host ("  {0}. {1}"-f$number,$failure);$number++}
    Write-Host ''
    Write-Host ("Report: {0}"-f$ReportDirectory)
    exit 2
}

function Stop-TPMTimedOutV1 {
    param([Parameter(Mandatory=$true)][int]$TimeoutSeconds,[Parameter(Mandatory=$true)][string]$ReportDirectory,[Parameter(Mandatory=$true)][string]$LogDirectory)
    Write-Host 'FINAL STATUS: PIPELINE ABORTED'
    Write-Host ("Reason: certification ran out of time after {0} seconds. It was stopped, together with every program it started."-f$TimeoutSeconds)
    Write-Host 'Next step: read the technical log. If the PC is just slow, run it again with a bigger -PesterRegressionTimeoutSeconds.'
    Write-Host ("Report: {0}"-f$ReportDirectory)
    Write-Host ("Technical log: {0}"-f$LogDirectory)
    exit 71
}

if([string]::IsNullOrWhiteSpace($RepoPath)){$RepoPath=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))}
else{
    # A relative -RepoPath is relative to where the caller is, and the relaunched child starts inside the repository, so it gets the plain full path.
    # A folder that is not there is left as typed; the preflight below reports it.
    $resolvedRepoPath=Resolve-Path -LiteralPath $RepoPath -ErrorAction SilentlyContinue
    if($resolvedRepoPath){$RepoPath=$resolvedRepoPath.ProviderPath}
}
if([string]::IsNullOrWhiteSpace($HarnessRoot)){
    $HarnessRoot=Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($RepoPath))) 'TPM-TestHarness'
}
$stamp=Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$reportDirectory=if([string]::IsNullOrWhiteSpace($ReportDirectory)){Join-Path $HarnessRoot "Reports\$stamp"}else{[IO.Path]::GetFullPath($ReportDirectory)}
$logDirectory=Join-Path $reportDirectory 'TechnicalLogs'
$statusPath=Join-Path $reportDirectory 'OperatorStatus.txt'
# The report folder and its TechnicalLogs folder are created here one authorized level at a time with
# New-TPMOwnedDirectoryChainV1, which checks every level for reparse points. The anchor is HarnessRoot's own parent
# (it must already exist, and HarnessRoot itself may not exist yet on a first run). A raw New-Item is not used for them.
$harnessRootParent=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($HarnessRoot))
if([string]::IsNullOrEmpty($harnessRootParent)){throw "PROCESS_DIRECTORY_INVALID: HarnessRoot has no resolvable parent directory to anchor trust in: $HarnessRoot"}
[void](New-TPMOwnedDirectoryChainV1 -Root $harnessRootParent -Path $reportDirectory)
[void](New-TPMOwnedDirectoryChainV1 -Root $reportDirectory -Path $logDirectory)

if (-not $NoPwshRelaunch -and $PSVersionTable.PSEdition -ne 'Core') {
    $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwshCommand) {
        Stop-TPMPreflightV1 -Failures @('PowerShell 7 (pwsh) is required. Install PowerShell 7, then run certification again.') -ReportDirectory $reportDirectory
    }
    $argsList = @(
        '-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass',
        '-File', $PSCommandPath,
        '-NoPwshRelaunch','-RepoPath',$RepoPath,'-TeknoParrotRoot',$TeknoParrotRoot,
        '-HarnessRoot',$HarnessRoot,'-ReportDirectory',$reportDirectory,'-VerbosityLevel',$VerbosityLevel,
        '-PesterRegressionTimeoutSeconds',[string]$PesterRegressionTimeoutSeconds
    )
    if($RunUnattendedTPM){$argsList+='-RunUnattendedTPM'}
    if(-not[string]::IsNullOrWhiteSpace($ExpectedBranch)){$argsList+='-ExpectedBranch';$argsList+=$ExpectedBranch}
    if(-not[string]::IsNullOrWhiteSpace($ExpectedCommit)){$argsList+='-ExpectedCommit';$argsList+=$ExpectedCommit}
    # WorkingDirectory's trust anchor is $RepoPath itself (the caller's
    # own repo checkout -- no narrower, more-authoritative root than the
    # repo root is available or meaningful here; Root == Target is the
    # deliberately supported degenerate case, see Assert-TPMOwnedDirectoryV1).
    # LogDirectory's trust anchor is $reportDirectory, already established
    # above via New-TPMOwnedDirectoryChainV1.
    # The PowerShell 7 child below runs the harness with a timeout of Pester + 1800 seconds. This outer wait is longer by 600 seconds so
    # the inner run can stop its own children and write its report first; only then can this outer timeout fire.
    $relaunchTimeoutSeconds=$PesterRegressionTimeoutSeconds+2400
    $result=Invoke-TPMIsolatedProcessV1 -FilePath $pwshCommand.Source -ArgumentList $argsList -WorkingDirectoryRoot $RepoPath -WorkingDirectory $RepoPath -LogDirectoryRoot $reportDirectory -LogDirectory $logDirectory -Identity 'pwsh-relaunch' -TimeoutSeconds $relaunchTimeoutSeconds -OperatorStatusPath $statusPath -RelayOperatorStatus
    # The step lines and the "still running" lines were shown while the run went on, so only the rest of the child's text is shown now (the final status is in it).
    $safeOutput=Get-Content -LiteralPath $result.StdOutPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if($safeOutput){foreach($line in ($safeOutput.TrimEnd() -split "`r?`n")){if($line -notmatch '^(\[\d+/\d+\] |Pester totals:|Certification is still running)'){Write-Host $line}}}
    if($result.TimedOut){Stop-TPMTimedOutV1 -TimeoutSeconds $relaunchTimeoutSeconds -ReportDirectory $reportDirectory -LogDirectory $logDirectory}
    exit [int]$result.ExitCode
}
$harness = Join-Path $PSScriptRoot "Invoke-TPM-RealInstanceSmoke.ps1"
$pesterChild=Join-Path $PSScriptRoot 'Invoke-TPM-PesterChild.ps1'
$settings=Join-Path $RepoPath 'PSScriptAnalyzerSettings.psd1'
$registry=Join-Path $PSScriptRoot 'InjectionHunterDispositions.psd1'
$failures=New-Object Collections.Generic.List[string]
$identity=$null
foreach($required in @($harness,$pesterChild,$executionModule,$settings,$registry,(Join-Path $RepoPath 'Tests'))){
    if(-not(Test-Path -LiteralPath $required)){[void]$failures.Add("Required certification dependency is missing: $required")}
}
foreach($commandName in @('git','pwsh','powershell.exe')){
    if(-not(Get-Command $commandName -ErrorAction SilentlyContinue)){[void]$failures.Add("Required command is unavailable: $commandName")}
}
# Issue #154 real-hardware certification finding: this preflight used to
# accept ANY installed Pester >= 5.0 -- it would report success with only
# Pester 5.8.0 present, then Invoke-TPM-PesterChild.ps1 (pinned to the exact
# version this suite is proven against after that finding) would fail to
# import it, turning a clear preflight signal into a confusing later
# failure. Preflight now checks for the SAME exact pinned version so a
# missing/wrong Pester version is always caught here, not downstream.
$requiredPesterVersion=[version]'5.7.1'
$pester=Get-Module -ListAvailable Pester|Where-Object{$_.Version-eq$requiredPesterVersion}|Select-Object -First 1
if(-not$pester){[void]$failures.Add("Pester $requiredPesterVersion is required (exact version this suite is validated against -- see Invoke-TPM-PesterChild.ps1). Install it, then retry.")}
$analyzer=Get-Module -ListAvailable PSScriptAnalyzer|Sort-Object Version -Descending|Select-Object -First 1
if(-not$analyzer){[void]$failures.Add('PSScriptAnalyzer is required. Install it before certification; certification will not install it.')}
$injectionHunter=Get-Module -ListAvailable InjectionHunter|Sort-Object Version -Descending|Select-Object -First 1
if(-not$injectionHunter){[void]$failures.Add('InjectionHunter is required. Install it before certification; certification will not install it.')}
if($pester){
    try{
        Import-Module $pester.Path -Force -ErrorAction Stop
        $configuration=New-PesterConfiguration
        foreach($property in @('CIFormat','RenderMode','Verbosity')){if($property-notin$configuration.Output.PSObject.Properties.Name){throw "Pester configuration property Output.$property is unavailable"}}
    }catch{[void]$failures.Add("Pester configuration is incompatible: $($_.Exception.Message)")}
}
try{
    $resolvedRepo=(Resolve-Path -LiteralPath $RepoPath -ErrorAction Stop).ProviderPath
    $resolvedRoot=(Resolve-Path -LiteralPath $TeknoParrotRoot -ErrorAction Stop).Path
    $env:GIT_TERMINAL_PROMPT='0'
    $scopedGitArguments=@('-c',("safe.directory={0}"-f$resolvedRepo),'-C',$resolvedRepo)
    $commit=(& git @scopedGitArguments rev-parse HEAD 2>$null)
    if($LASTEXITCODE-ne0-or[string]::IsNullOrWhiteSpace($commit)){throw 'git could not read HEAD'}
    $identity=Get-TPMCertificationGitIdentitySnapshotV1 -RepositoryPath $resolvedRepo
    if(-not$identity.Clean){[void]$failures.Add('Certification worktree must be clean immediately before the run.')}
    if([string]::IsNullOrWhiteSpace([string]$identity.Branch)-or[string]$identity.Branch-ceq'HEAD'){[void]$failures.Add('Certification checkout must be on a named branch, not detached HEAD.')}
    if([string]::IsNullOrWhiteSpace([string]$identity.RemoteRef)-or[string]::IsNullOrWhiteSpace([string]$identity.RemoteCommit)){[void]$failures.Add('Certification checkout must have a readable cached upstream ref and remote SHA.')}
    elseif([string]$identity.Commit-ne[string]$identity.RemoteCommit){[void]$failures.Add("Certification HEAD $($identity.Commit) does not match cached remote SHA $($identity.RemoteCommit).")}
    if([string]::IsNullOrWhiteSpace([string]$identity.RefSnapshotSha256)){[void]$failures.Add('Certification checkout ref snapshot could not be captured.')}
    if([string]::IsNullOrWhiteSpace([string]$identity.ReflogSnapshotSha256)){[void]$failures.Add('Certification checkout reflog snapshot could not be captured.')}
    if(-not[string]::IsNullOrWhiteSpace($ExpectedBranch)-and[string]$identity.Branch-ne$ExpectedBranch){[void]$failures.Add("Expected branch '$ExpectedBranch' but found '$($identity.Branch)'.")}
    if(-not[string]::IsNullOrWhiteSpace($ExpectedCommit)-and[string]$identity.Commit-ne$ExpectedCommit){[void]$failures.Add("Expected HEAD '$ExpectedCommit' but found '$($identity.Commit)'.")}
    if(-not[string]::IsNullOrWhiteSpace($ExpectedCommit)-and[string]$identity.RemoteCommit-ne$ExpectedCommit){[void]$failures.Add("Expected remote SHA '$ExpectedCommit' but found '$($identity.RemoteCommit)'.")}
}catch{[void]$failures.Add("Repository is not readable: $($_.Exception.Message)")}
# The report and log folders already exist (made above). Only HarnessRoot can be missing here, when -ReportDirectory is not
# inside it; the line below then creates it with a plain New-Item and no reparse check, and the probe only proves it is writable.
foreach($directory in @($HarnessRoot,$reportDirectory,$logDirectory)){
    try{
        if(-not(Test-Path -LiteralPath $directory -PathType Container)){[void](New-Item -ItemType Directory -Path $directory -Force)}
        $probe=Join-Path $directory ('.tpm-write-probe-'+[guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllBytes($probe,[byte[]](1))
        Remove-Item -LiteralPath $probe -Force
    }catch{[void]$failures.Add("Certification output location is not writable: $directory")}
}
if($failures.Count-gt0){Stop-TPMPreflightV1 -Failures $failures.ToArray() -ReportDirectory $reportDirectory}

$commit=(& git @scopedGitArguments rev-parse HEAD).Trim()
Write-Host 'TeknoParrot Manager Certification'
Write-Host ''
Write-Host ("Target repository: {0}"-f$resolvedRepo)
Write-Host ("Target branch:     {0}"-f$identity.Branch)
Write-Host ("Target commit:     {0}"-f$commit)
Write-Host ("Remote ref:        {0}"-f$identity.RemoteRef)
Write-Host ("Remote SHA:        {0}"-f$identity.RemoteCommit)
Write-Host ("Worktree clean:    {0}"-f$identity.Clean)
if(-not[string]::IsNullOrWhiteSpace($ExpectedBranch)){Write-Host ("Expected branch:   {0}"-f$ExpectedBranch)}
if(-not[string]::IsNullOrWhiteSpace($ExpectedCommit)){Write-Host ("Expected SHA:      {0}"-f$ExpectedCommit)}
Write-Host ("TeknoParrot:       {0}"-f$resolvedRoot)
Write-Host ("Reports:           {0}"-f$reportDirectory)
Write-Host ("Technical log:     {0}"-f$logDirectory)
Write-Host ''
Write-Host 'Starting non-interactive certification.'
Write-Host 'No further input will be requested.'
Write-Host ''
[IO.File]::WriteAllBytes($statusPath,[byte[]]@())

$params=@(
    '-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass',
    '-File',$harness,'-RepoPath',$resolvedRepo,'-TeknoParrotRoot',$resolvedRoot,
    '-HarnessRoot',$HarnessRoot,'-ReportDirectory',$reportDirectory,
    '-OperatorStatusPath',$statusPath,'-VerbosityLevel',$VerbosityLevel,
    '-PesterRegressionTimeoutSeconds',[string]$PesterRegressionTimeoutSeconds
)
if($RunUnattendedTPM){$params+='-RunUnattendedTPM'}
if(-not[string]::IsNullOrWhiteSpace($ExpectedBranch)){$params+='-ExpectedBranch';$params+=$ExpectedBranch}
if(-not[string]::IsNullOrWhiteSpace($ExpectedCommit)){$params+='-ExpectedCommit';$params+=$ExpectedCommit}
$harnessResult=$null
try{
    $harnessResult=Invoke-TPMIsolatedProcessV1 -FilePath (Get-Command pwsh).Source -ArgumentList $params -WorkingDirectoryRoot $resolvedRepo -WorkingDirectory $resolvedRepo -LogDirectoryRoot $reportDirectory -LogDirectory $logDirectory -Identity 'certification-harness' -TimeoutSeconds ($PesterRegressionTimeoutSeconds+1800) -OperatorStatusPath $statusPath -RelayOperatorStatus -Environment @{GIT_TERMINAL_PROMPT='0';NO_COLOR='1';TERM='dumb'}
}catch{
    Write-Host 'FINAL STATUS: PIPELINE ABORTED'
    Write-Host ("Reason: certification process isolation failed: {0}"-f$_.Exception.Message)
    Write-Host ("Report: {0}"-f$reportDirectory)
    Write-Host ("Technical log: {0}"-f$logDirectory)
    exit 70
}
if($harnessResult.TimedOut){Stop-TPMTimedOutV1 -TimeoutSeconds ($PesterRegressionTimeoutSeconds+1800) -ReportDirectory $reportDirectory -LogDirectory $logDirectory}
$statusText=if(Test-Path -LiteralPath $statusPath){Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8}else{''}
$finalSummaryLines=@($statusText -split "`r?`n"|Where-Object{$_ -match '^(FINAL STATUS:|Reason:|Warning:|Total elapsed:|Report:|Technical log:)'})
foreach($line in $finalSummaryLines){Write-Host $line}
if($statusText-notmatch'(?m)^FINAL STATUS:'){
    Write-Host 'FINAL STATUS: PIPELINE ABORTED'
    Write-Host 'Reason: certification child exited without a final status.'
    Write-Host ("Report: {0}"-f$reportDirectory)
    Write-Host ("Technical log: {0}"-f$logDirectory)
    exit $(if($harnessResult.ExitCode-ne0){[int]$harnessResult.ExitCode}else{70})
}
exit [int]$harnessResult.ExitCode
