param(
    [string]$RepoPath,
    [Parameter(Mandatory = $true)]
    [string]$TeknoParrotRoot,
    [string]$HarnessRoot,
    [switch]$RunUnattendedTPM,
    [switch]$NoPwshRelaunch,
    [ValidateSet('Summary', 'Detailed', 'Diagnostic')]
    [string]$VerbosityLevel = 'Summary',
    [int]$PesterRegressionTimeoutSeconds = 1800
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
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

if([string]::IsNullOrWhiteSpace($RepoPath)){$RepoPath=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))}
if([string]::IsNullOrWhiteSpace($HarnessRoot)){
    $HarnessRoot=Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($RepoPath))) 'TPM-TestHarness'
}
$stamp=Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$reportDirectory=Join-Path $HarnessRoot "Reports\$stamp"
$logDirectory=Join-Path $reportDirectory 'TechnicalLogs'
$statusPath=Join-Path $reportDirectory 'OperatorStatus.txt'
foreach($directory in @($reportDirectory,$logDirectory)){[void](New-Item -ItemType Directory -Path $directory -Force)}

if (-not $NoPwshRelaunch -and $PSVersionTable.PSEdition -ne 'Core') {
    $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwshCommand) {
        Stop-TPMPreflightV1 -Failures @('PowerShell 7 (pwsh) is required. Install PowerShell 7, then run certification again.') -ReportDirectory $reportDirectory
    }
    $argsList = @(
        '-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass',
        '-File', $PSCommandPath,
        '-NoPwshRelaunch','-RepoPath',$RepoPath,'-TeknoParrotRoot',$TeknoParrotRoot,
        '-HarnessRoot',$HarnessRoot,'-VerbosityLevel',$VerbosityLevel,
        '-PesterRegressionTimeoutSeconds',[string]$PesterRegressionTimeoutSeconds
    )
    if($RunUnattendedTPM){$argsList+='-RunUnattendedTPM'}
    $result=Invoke-TPMIsolatedProcessV1 -FilePath $pwshCommand.Source -ArgumentList $argsList -WorkingDirectory $RepoPath -LogDirectory $logDirectory -Identity 'pwsh-relaunch' -TimeoutSeconds ($PesterRegressionTimeoutSeconds+1800)
    $safeOutput=Get-Content -LiteralPath $result.StdOutPath -Raw -ErrorAction SilentlyContinue
    if($safeOutput){Write-Host $safeOutput.TrimEnd()}
    exit [int]$result.ExitCode
}
$harness = Join-Path $PSScriptRoot "Invoke-TPM-RealInstanceSmoke.ps1"
$pesterChild=Join-Path $PSScriptRoot 'Invoke-TPM-PesterChild.ps1'
$settings=Join-Path $RepoPath 'PSScriptAnalyzerSettings.psd1'
$registry=Join-Path $PSScriptRoot 'InjectionHunterDispositions.psd1'
$failures=New-Object Collections.Generic.List[string]
foreach($required in @($harness,$pesterChild,$executionModule,$settings,$registry,(Join-Path $RepoPath 'Tests'))){
    if(-not(Test-Path -LiteralPath $required)){[void]$failures.Add("Required certification dependency is missing: $required")}
}
foreach($commandName in @('git','pwsh','powershell.exe')){
    if(-not(Get-Command $commandName -ErrorAction SilentlyContinue)){[void]$failures.Add("Required command is unavailable: $commandName")}
}
$pester=Get-Module -ListAvailable Pester|Sort-Object Version -Descending|Select-Object -First 1
if(-not$pester-or$pester.Version.Major-lt5){[void]$failures.Add('Pester 5 or later is required. Install a compatible Pester version, then retry.')}
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
    $resolvedRepo=(Resolve-Path -LiteralPath $RepoPath -ErrorAction Stop).Path
    $resolvedRoot=(Resolve-Path -LiteralPath $TeknoParrotRoot -ErrorAction Stop).Path
    $env:GIT_TERMINAL_PROMPT='0'
    $commit=(git -C $resolvedRepo rev-parse HEAD 2>$null)
    if($LASTEXITCODE-ne0-or[string]::IsNullOrWhiteSpace($commit)){throw 'git could not read HEAD'}
}catch{[void]$failures.Add("Repository is not readable: $($_.Exception.Message)")}
foreach($directory in @($HarnessRoot,$reportDirectory,$logDirectory)){
    try{
        if(-not(Test-Path -LiteralPath $directory -PathType Container)){[void](New-Item -ItemType Directory -Path $directory -Force)}
        $probe=Join-Path $directory ('.tpm-write-probe-'+[guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllBytes($probe,[byte[]](1))
        Remove-Item -LiteralPath $probe -Force
    }catch{[void]$failures.Add("Certification output location is not writable: $directory")}
}
if($failures.Count-gt0){Stop-TPMPreflightV1 -Failures $failures.ToArray() -ReportDirectory $reportDirectory}

$commit=(git -C $resolvedRepo rev-parse HEAD).Trim()
Write-Host 'TeknoParrot Manager Certification'
Write-Host ''
Write-Host ("Target repository: {0}"-f$resolvedRepo)
Write-Host ("Target commit:     {0}"-f$commit)
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
$harnessResult=$null
try{
    $harnessResult=Invoke-TPMIsolatedProcessV1 -FilePath (Get-Command pwsh).Source -ArgumentList $params -WorkingDirectory $resolvedRepo -LogDirectory $logDirectory -Identity 'certification-harness' -TimeoutSeconds ($PesterRegressionTimeoutSeconds+1800) -OperatorStatusPath $statusPath -RelayOperatorStatus -Environment @{GIT_TERMINAL_PROMPT='0';NO_COLOR='1';TERM='dumb'}
}catch{
    Write-Host 'FINAL STATUS: PIPELINE ABORTED'
    Write-Host ("Reason: certification process isolation failed: {0}"-f$_.Exception.Message)
    Write-Host ("Report: {0}"-f$reportDirectory)
    Write-Host ("Technical log: {0}"-f$logDirectory)
    exit 70
}
$statusText=if(Test-Path -LiteralPath $statusPath){Get-Content -LiteralPath $statusPath -Raw}else{''}
$finalSummaryLines=@($statusText -split "`r?`n"|Where-Object{$_ -match '^(FINAL STATUS:|Reason:|Total elapsed:|Report:|Technical log:)'})
foreach($line in $finalSummaryLines){Write-Host $line}
if($statusText-notmatch'(?m)^FINAL STATUS:'){
    Write-Host 'FINAL STATUS: PIPELINE ABORTED'
    Write-Host 'Reason: certification child exited without a final status.'
    Write-Host ("Report: {0}"-f$reportDirectory)
    Write-Host ("Technical log: {0}"-f$logDirectory)
    exit $(if($harnessResult.ExitCode-ne0){[int]$harnessResult.ExitCode}else{70})
}
exit [int]$harnessResult.ExitCode
