#Requires -Module Pester

Describe 'certification launcher exit propagation' {
 BeforeAll {
  $repoRoot=Split-Path $PSScriptRoot -Parent
  $runnerSource=Join-Path $repoRoot 'scripts\Run-TPM-Tests.ps1'
  $batchSource=Join-Path $repoRoot 'scripts\Run-TPM-Certification-Suite.bat'
  $executionSource=Join-Path $repoRoot 'scripts\TPMCertification.Execution.psm1'
  $pesterChildSource=Join-Path $repoRoot 'scripts\Invoke-TPM-PesterChild.ps1'
  $settingsSource=Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
  $registrySource=Join-Path $repoRoot 'scripts\InjectionHunterDispositions.psd1'
  $sentinel=37
  $fakeRepo=Join-Path $TestDrive 'fake-repo'
  $fakeScripts=Join-Path $fakeRepo 'scripts'
  $fakeRoot=Join-Path $TestDrive 'fake-install'
  New-Item -ItemType Directory -Path $fakeScripts,$fakeRoot,(Join-Path $fakeRepo 'Tests') -Force|Out-Null
  Copy-Item -LiteralPath $runnerSource -Destination (Join-Path $fakeScripts 'Run-TPM-Tests.ps1')
  Copy-Item -LiteralPath $batchSource -Destination (Join-Path $fakeScripts 'Run-TPM-Certification-Suite.bat')
  Copy-Item -LiteralPath $executionSource -Destination (Join-Path $fakeScripts 'TPMCertification.Execution.psm1')
  Copy-Item -LiteralPath $pesterChildSource -Destination (Join-Path $fakeScripts 'Invoke-TPM-PesterChild.ps1')
  Copy-Item -LiteralPath $settingsSource -Destination (Join-Path $fakeRepo 'PSScriptAnalyzerSettings.psd1')
  Copy-Item -LiteralPath $registrySource -Destination (Join-Path $fakeScripts 'InjectionHunterDispositions.psd1')
  Set-Content -LiteralPath (Join-Path $fakeRepo '.gitignore') -Value 'scripts/Invoke-TPM-RealInstanceSmoke.ps1' -Encoding ascii
  git -C $fakeRepo init --quiet
  git -C $fakeRepo config user.email 'fixture@example.invalid'
  git -C $fakeRepo config user.name 'Fixture'
  git -C $fakeRepo add --all
  git -C $fakeRepo commit --allow-empty -m 'fixture' --quiet
  $fakeBranch=(git -C $fakeRepo rev-parse --abbrev-ref HEAD).Trim()
  $fakeHead=(git -C $fakeRepo rev-parse HEAD).Trim()
  git -C $fakeRepo update-ref ("refs/remotes/origin/{0}"-f$fakeBranch) $fakeHead
  git -C $fakeRepo config remote.origin.url https://example.invalid/tpm.git
  git -C $fakeRepo config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  git -C $fakeRepo config ("branch.{0}.remote"-f$fakeBranch) origin
  git -C $fakeRepo config ("branch.{0}.merge"-f$fakeBranch) ("refs/heads/{0}"-f$fakeBranch)
  function Set-FakeHarnessExit {
   @'
param(
 [string]$RepoPath,
 [Parameter(Mandatory=$true)][string]$TeknoParrotRoot,
 [string]$HarnessRoot,
 [string]$ReportDirectory,
 [string]$OperatorStatusPath,
 [switch]$RunUnattendedTPM,
 [string]$VerbosityLevel,
 [int]$PesterRegressionTimeoutSeconds,
 [int]$ExitCode=37
)
exit $ExitCode
'@|Set-Content -LiteralPath (Join-Path $fakeScripts 'Invoke-TPM-RealInstanceSmoke.ps1') -Encoding ascii
  }
  function Set-FakeHarnessThrow {
   "throw 'FAKE_HARNESS_THROW_SENTINEL'"|Set-Content -LiteralPath (Join-Path $fakeScripts 'Invoke-TPM-RealInstanceSmoke.ps1') -Encoding ascii
  }
  function ConvertTo-Win32QuotedArgument {
   param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Value)
   if($Value.Length-gt 0-and $Value.IndexOfAny([char[]](' ',"`t",'"'))-lt 0){return $Value}
   $builder=New-Object Text.StringBuilder
   [void]$builder.Append('"')
   $index=0
   while($index-lt $Value.Length){
    $backslashes=0
    while($index-lt $Value.Length-and $Value[$index]-eq '\'){$backslashes++;$index++}
    if($index-eq $Value.Length){
     [void]$builder.Append('\'*($backslashes*2))
     break
    }elseif($Value[$index]-eq '"'){
     [void]$builder.Append('\'*($backslashes*2+1))
     [void]$builder.Append('"')
     $index++
    }else{
     [void]$builder.Append('\'*$backslashes)
     [void]$builder.Append($Value[$index])
     $index++
    }
   }
   [void]$builder.Append('"')
   return $builder.ToString()
  }
  function ConvertTo-PowerShellLiteral {
   param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Value)
   return "'"+$Value.Replace("'","''")+"'"
  }
  function Invoke-CapturedPowerShell {
   param(
    [Parameter(Mandatory=$true)][string]$FilePath,
    [Parameter(Mandatory=$true)][string[]]$ArgumentList,
    [Parameter(Mandatory=$true)][string]$Name
   )
   $stdoutPath=Join-Path $TestDrive ($Name+'-stdout.txt')
   $stderrPath=Join-Path $TestDrive ($Name+'-stderr.txt')
   $quotedArguments=@($ArgumentList|ForEach-Object{ConvertTo-Win32QuotedArgument -Value $_})
   $process=$null
   $terminationConfirmed=$false
   try{
    $process=Start-Process -FilePath $FilePath -ArgumentList $quotedArguments -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    [void]$process.Handle
    $process.Refresh()
    $terminationConfirmed=$process.HasExited
    if(-not $terminationConfirmed){throw "PowerShell child '$Name' remained active after Start-Process -Wait."}
    $exitCode=$process.ExitCode
   }finally{
    if($null-ne $process-and -not $process.HasExited){
     try{Stop-Process -Id $process.Id -Force -ErrorAction Stop}catch{[Diagnostics.Debug]::WriteLine($_.Exception.Message)}
     try{[void]$process.WaitForExit(5000)}catch{[Diagnostics.Debug]::WriteLine($_.Exception.Message)}
     $terminationConfirmed=$process.HasExited
    }
    if($null-ne $process){$process.Dispose()}
   }
   if(-not $terminationConfirmed){throw "PowerShell child '$Name' termination could not be confirmed; redirected files were preserved."}
   return [pscustomobject]@{
    ExitCode=$exitCode
    StdOut=[IO.File]::ReadAllText($stdoutPath)
    StdErr=[IO.File]::ReadAllText($stderrPath)
   }
  }
 }

 It 'returns the fake harness sentinel through the direct pwsh path' {
  Set-FakeHarnessExit
  & pwsh -NoProfile -NonInteractive -File (Join-Path $fakeScripts 'Run-TPM-Tests.ps1') -RepoPath $fakeRepo -TeknoParrotRoot $fakeRoot -NoPwshRelaunch
  $LASTEXITCODE|Should -Be $sentinel
 }

 It 'returns the fake harness sentinel through the Windows PowerShell relaunch path' {
  Set-FakeHarnessExit
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $fakeScripts 'Run-TPM-Tests.ps1') -RepoPath $fakeRepo -TeknoParrotRoot $fakeRoot
  $LASTEXITCODE|Should -Be $sentinel
 }

 It 'returns saved RUN_EXIT after batch presentation and cleanup' {
  Set-FakeHarnessExit
  $batch=[IO.File]::ReadAllText($batchSource)
  $capture=$batch.IndexOf('set "RUN_EXIT=%ERRORLEVEL%"')
  $pause=$batch.LastIndexOf('pause')
  $popd=$batch.LastIndexOf('popd >nul')
  $return=$batch.LastIndexOf('endlocal & exit /b %RUN_EXIT%')
  $capture|Should -BeGreaterThan -1
  $pause|Should -BeGreaterThan $capture
  $popd|Should -BeGreaterThan $pause
  $return|Should -BeGreaterThan $popd

  $inputFile=Join-Path $TestDrive 'batch-input.txt'
  [IO.File]::WriteAllText($inputFile,"$fakeRoot`r`n`r`n")
  $quotedBatch='"'+(Join-Path $fakeScripts 'Run-TPM-Certification-Suite.bat')+'"'
  $quotedRepo='"'+$fakeRepo+'"'
  $quotedInput='"'+$inputFile+'"'
  & cmd.exe /d /c "$quotedBatch $quotedRepo < $quotedInput"
  $LASTEXITCODE|Should -Be $sentinel
 }

 It 'returns nonzero when the harness throws instead of explicitly exiting in direct and relaunch paths' {
  Set-FakeHarnessThrow
  $runner=Join-Path $fakeScripts 'Run-TPM-Tests.ps1'
  $direct=Invoke-CapturedPowerShell -FilePath 'pwsh' -Name 'throw-direct' -ArgumentList @('-NoProfile','-NonInteractive','-File',$runner,'-RepoPath',$fakeRepo,'-TeknoParrotRoot',$fakeRoot,'-NoPwshRelaunch')
  $relaunch=Invoke-CapturedPowerShell -FilePath 'powershell.exe' -Name 'throw-relaunch' -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$runner,'-RepoPath',$fakeRepo,'-TeknoParrotRoot',$fakeRoot)
  $direct.ExitCode|Should -Not -Be 0
  $relaunch.ExitCode|Should -Not -Be 0
  $technicalErrors=@(Get-ChildItem -LiteralPath (Join-Path (Split-Path $fakeRepo -Parent) 'TPM-TestHarness') -Filter '*-stderr.log' -File -Recurse|ForEach-Object{Get-Content -LiteralPath $_.FullName -Raw}) -join "`n"
  $technicalErrors|Should -Match 'FAKE_HARNESS_THROW_SENTINEL'
 }

 It 'returns nonzero when Windows PowerShell cannot resolve pwsh for relaunch' {
  Set-FakeHarnessExit
  $runner=Join-Path $fakeScripts 'Run-TPM-Tests.ps1'
  $runnerLiteral=ConvertTo-PowerShellLiteral -Value $runner
  $repoLiteral=ConvertTo-PowerShellLiteral -Value $fakeRepo
  $rootLiteral=ConvertTo-PowerShellLiteral -Value $fakeRoot
  $command="function Get-Command { [CmdletBinding()]param([Parameter(Position=0)]`$Name) if(`$Name -ceq 'pwsh'){return}; Microsoft.PowerShell.Core\Get-Command @PSBoundParameters }; & $runnerLiteral -RepoPath $repoLiteral -TeknoParrotRoot $rootLiteral"
  $result=Invoke-CapturedPowerShell -FilePath 'powershell.exe' -Name 'missing-pwsh' -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-Command',$command)
  $result.ExitCode|Should -Not -Be 0
  ($result.StdOut+"`n"+$result.StdErr)|Should -Match 'PowerShell 7 \(pwsh\) is required'
 }

 It 'keeps RUN_EXIT when a report exists and the Explorer presentation branch is reached' {
  Set-FakeHarnessExit
  $report=Join-Path (Split-Path $fakeRepo -Parent) 'TPM-TestHarness\Reports\synthetic-report'
  New-Item -ItemType Directory -Path $report -Force|Out-Null
  $fakeBin=Join-Path $TestDrive 'fake-bin'
  New-Item -ItemType Directory -Path $fakeBin -Force|Out-Null
  Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\where.exe') -Destination (Join-Path $fakeBin 'explorer.exe')

  $inputFile=Join-Path $TestDrive 'batch-report-input.txt'
  [IO.File]::WriteAllText($inputFile,"$fakeRoot`r`n`r`n")
  $batchPath='"'+(Join-Path $fakeScripts 'Run-TPM-Certification-Suite.bat')+'"'
  $repoPath='"'+$fakeRepo+'"'
  $inputPath='"'+$inputFile+'"'
  $savedPath=$env:PATH
  $savedPresentation=$env:TPM_PRESENT_RESULTS
  try{
   $env:PATH=$fakeBin+';'+$savedPath
   $env:TPM_PRESENT_RESULTS='1'
   $output=@(& cmd.exe /d /c "$batchPath $repoPath < $inputPath" 2>&1)
   $exitCode=$LASTEXITCODE
  }finally{
   $env:PATH=$savedPath
   $env:TPM_PRESENT_RESULTS=$savedPresentation
  }
  $exitCode|Should -Be $sentinel
  ($output-join"`n")|Should -Match 'Opening the completed report folder'
 }
}
