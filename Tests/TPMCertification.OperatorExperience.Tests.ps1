BeforeAll {
 $repoRoot=Split-Path $PSScriptRoot -Parent
 $scripts=Join-Path $repoRoot 'scripts'
 Import-Module (Join-Path $scripts 'TPMCertification.Execution.psm1') -Force
}
Describe 'certification noninteractive execution boundary' {
 It 'sanitizes ANSI and control characters without corrupting ordinary text' {
  ConvertTo-TPMSafeTechnicalTextV1 -Text ("ok`e[31mred`e[0m`b")|Should -Be 'okred\x08'
 }
 It 'runs a child with closed stdin, separate logs, exact exit, and termination proof' {
  $engine=if($PSVersionTable.PSEdition-eq'Core'){(Get-Command pwsh).Source}else{(Get-Command powershell.exe).Source}
  $r=Invoke-TPMIsolatedProcessV1 -FilePath $engine -ArgumentList @('-NoProfile','-NonInteractive','-Command','[Console]::Out.Write("OUT");[Console]::Error.Write("ERR");exit 37') -WorkingDirectory $TestDrive -LogDirectory $TestDrive -Identity sentinel -TimeoutSeconds 20
  $r.ExitCode|Should -Be 37;$r.TerminationConfirmed|Should -BeTrue
  (Get-Content $r.StdOutPath -Raw)|Should -Be 'OUT';(Get-Content $r.StdErrPath -Raw)|Should -Be 'ERR'
 }
 It 'rejects missing, unknown, and contradictory Pester contracts' {
  {Read-TPMPesterResultV1 (Join-Path $TestDrive 'missing.json')}|Should -Throw '*PESTER_RESULT_MISSING*'
  $base=[ordered]@{SchemaVersion=1;Discovered=1;Passed=1;Failed=0;Skipped=0;NotRun=0;Containers=1;FailedContainers=0;DurationMilliseconds=1;Failures=@();Categories=[ordered]@{VirtualBetaTesterTotal=0;VirtualBetaTesterPassed=0;VirtualBetaTesterFailed=0;HumanBehaviors=0;IdempotencyChecks=0;RecoveryBehaviors=0;EnvironmentVariations=0;HighTvdBehaviors=0};Engine='test'}
  $path=Join-Path $TestDrive 'result.json';$base.Extra='x';$base|ConvertTo-Json -Depth 8|Set-Content $path;{Read-TPMPesterResultV1 $path}|Should -Throw '*exact field set*'
  $base.Remove('Extra');$base.Discovered=2;$base|ConvertTo-Json -Depth 8|Set-Content $path;{Read-TPMPesterResultV1 $path}|Should -Throw '*CONTRADICTORY*'
 }
 It 'keeps production entry points free of interactive or mutating dependency operations' {
  $harness=Get-Content (Join-Path $scripts 'Invoke-TPM-RealInstanceSmoke.ps1') -Raw
  foreach($path in @((Join-Path $scripts 'Run-TPM-Tests.ps1'),(Join-Path $scripts 'Invoke-TPM-RealInstanceSmoke.ps1'))){
   $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
   $commands=@($ast.FindAll({param($node) return ($node -is [Management.Automation.Language.CommandAst])},$true))
   $names=@($commands|ForEach-Object{$_.GetCommandName()}|Where-Object{$_})
   foreach($forbidden in @('Install-Module','Install-PackageProvider','Set-PSRepository','Register-PSRepository','Read-Host')){$names|Should -Not -Contain $forbidden}
  }
  $harness|Should -Not -Match '(?m)^\s*git\s+fetch\b'
  $batch=Get-Content (Join-Path $scripts 'Run-TPM-Certification-Suite.bat') -Raw
  $batch|Should -Match 'powershell\.exe -NoProfile -NonInteractive';$batch|Should -Match 'endlocal & exit /b %RUN_EXIT%'
 }
}