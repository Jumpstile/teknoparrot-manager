#Requires -Module Pester

Describe 'certification launcher exit propagation' {
 BeforeAll {
  $repoRoot=Split-Path $PSScriptRoot -Parent
  $runnerSource=Join-Path $repoRoot 'scripts\Run-TPM-Tests.ps1'
  $batchSource=Join-Path $repoRoot 'scripts\Run-TPM-Certification-Suite.bat'
  $sentinel=37
  $fakeRepo=Join-Path $TestDrive 'fake-repo'
  $fakeScripts=Join-Path $fakeRepo 'scripts'
  $fakeRoot=Join-Path $TestDrive 'fake-install'
  New-Item -ItemType Directory -Path $fakeScripts,$fakeRoot -Force|Out-Null
  Copy-Item -LiteralPath $runnerSource -Destination (Join-Path $fakeScripts 'Run-TPM-Tests.ps1')
  Copy-Item -LiteralPath $batchSource -Destination (Join-Path $fakeScripts 'Run-TPM-Certification-Suite.bat')
  function Set-FakeHarnessExit {
   @'
param(
 [string]$RepoPath,
 [Parameter(Mandatory=$true)][string]$TeknoParrotRoot,
 [string]$HarnessRoot,
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
 }

 It 'returns the fake harness sentinel through the direct pwsh path' {
  Set-FakeHarnessExit
  & pwsh -NoProfile -File (Join-Path $fakeScripts 'Run-TPM-Tests.ps1') -RepoPath $fakeRepo -TeknoParrotRoot $fakeRoot -NoPwshRelaunch
  $LASTEXITCODE|Should -Be $sentinel
 }

 It 'returns the fake harness sentinel through the Windows PowerShell relaunch path' {
  Set-FakeHarnessExit
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fakeScripts 'Run-TPM-Tests.ps1') -RepoPath $fakeRepo -TeknoParrotRoot $fakeRoot
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
  $direct=@(& pwsh -NoProfile -File (Join-Path $fakeScripts 'Run-TPM-Tests.ps1') -RepoPath $fakeRepo -TeknoParrotRoot $fakeRoot -NoPwshRelaunch 2>&1)
  $directExit=$LASTEXITCODE
  $relaunch=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fakeScripts 'Run-TPM-Tests.ps1') -RepoPath $fakeRepo -TeknoParrotRoot $fakeRoot 2>&1)
  $relaunchExit=$LASTEXITCODE
  $directExit|Should -Not -Be 0
  $relaunchExit|Should -Not -Be 0
  ($direct-join"`n")|Should -Match 'FAKE_HARNESS_THROW_SENTINEL'
  ($relaunch-join"`n")|Should -Match 'FAKE_HARNESS_THROW_SENTINEL'
 }

 It 'returns nonzero when Windows PowerShell cannot resolve pwsh for relaunch' {
  Set-FakeHarnessExit
  $runner=Join-Path $fakeScripts 'Run-TPM-Tests.ps1'
  $command="function Get-Command { [CmdletBinding()]param([Parameter(Position=0)]`$Name) if(`$Name -ceq 'pwsh'){return}; Microsoft.PowerShell.Core\Get-Command @PSBoundParameters }; & '$runner' -RepoPath '$fakeRepo' -TeknoParrotRoot '$fakeRoot'"
  $output=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $command 2>&1)
  $exitCode=$LASTEXITCODE
  $exitCode|Should -Not -Be 0
  ($output-join"`n")|Should -Match 'PowerShell 7 \(pwsh\) is required'
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
  try{
   $env:PATH=$fakeBin+';'+$savedPath
   $output=@(& cmd.exe /d /c "$batchPath $repoPath < $inputPath" 2>&1)
   $exitCode=$LASTEXITCODE
  }finally{
   $env:PATH=$savedPath
  }
  $exitCode|Should -Be $sentinel
  ($output-join"`n")|Should -Match 'Opening report folder'
 }
}
