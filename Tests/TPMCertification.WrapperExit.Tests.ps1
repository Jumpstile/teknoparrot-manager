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
  @'
param(
 [string]$RepoPath,
 [Parameter(Mandatory=$true)][string]$TeknoParrotRoot,
 [string]$HarnessRoot,
 [switch]$RunUnattendedTPM,
 [string]$VerbosityLevel,
 [int]$PesterRegressionTimeoutSeconds
)
exit 37
'@|Set-Content -LiteralPath (Join-Path $fakeScripts 'Invoke-TPM-RealInstanceSmoke.ps1') -Encoding ascii
 }

 It 'returns the fake harness sentinel through the direct pwsh path' {
  & pwsh -NoProfile -File (Join-Path $fakeScripts 'Run-TPM-Tests.ps1') -RepoPath $fakeRepo -TeknoParrotRoot $fakeRoot -NoPwshRelaunch
  $LASTEXITCODE|Should -Be $sentinel
 }

 It 'returns the fake harness sentinel through the Windows PowerShell relaunch path' {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fakeScripts 'Run-TPM-Tests.ps1') -RepoPath $fakeRepo -TeknoParrotRoot $fakeRoot
  $LASTEXITCODE|Should -Be $sentinel
 }

 It 'returns saved RUN_EXIT after batch presentation and cleanup' {
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
}
