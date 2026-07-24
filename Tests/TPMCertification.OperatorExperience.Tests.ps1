BeforeAll {
 $repoRoot=Split-Path $PSScriptRoot -Parent
 $scripts=Join-Path $repoRoot 'scripts'
 Import-Module (Join-Path $scripts 'TPMCertification.Execution.psm1') -Force

 # Baseline valid Pester result contract used as the starting point for
 # every adversarial mutation in the table-driven suite below. Cloned via
 # ConvertTo-Json/ConvertFrom-Json round trip per mutation so no test can
 # observe another test's mutation.
 function New-TPMValidPesterContractV1 {
  [ordered]@{
   SchemaVersion=1
   Discovered=5
   Passed=3
   Failed=2
   Skipped=0
   NotRun=0
   Containers=1
   FailedContainers=1
   DurationMilliseconds=1234
   Failures=@(
    [ordered]@{Name='Test A';Message='expected true, got false'}
    [ordered]@{Name='Test B';Message='threw an exception'}
   )
   Categories=[ordered]@{
    VirtualBetaTesterTotal=4;VirtualBetaTesterPassed=2;VirtualBetaTesterFailed=2
    HumanBehaviors=1;IdempotencyChecks=1;RecoveryBehaviors=1;EnvironmentVariations=1;HighTvdBehaviors=0
   }
   Engine='Pester 5.5.0 / pwsh 7.4.0'
  }
 }

 function Write-TPMContractFixtureV1 {
  param([Parameter(Mandatory=$true)][hashtable]$Overrides,[string]$Path)
  if(-not$Path){$Path=Join-Path $TestDrive ('contract-'+[guid]::NewGuid().ToString('N')+'.json')}
  $contract=New-TPMValidPesterContractV1
  foreach($key in $Overrides.Keys){
   if($null-eq$Overrides[$key]){$contract.Remove($key)}
   else{$contract[$key]=$Overrides[$key]}
  }
  ($contract|ConvertTo-Json -Depth 8)|Set-Content -LiteralPath $Path -Encoding utf8
  return $Path
 }
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
 It 'a valid zero-failure contract is accepted, and Failures is an empty collection (never null)' {
  $path=Write-TPMContractFixtureV1 -Overrides @{Failed=0;Discovered=3;Passed=3;Failures=@();Categories=[ordered]@{VirtualBetaTesterTotal=0;VirtualBetaTesterPassed=0;VirtualBetaTesterFailed=0;HumanBehaviors=0;IdempotencyChecks=0;RecoveryBehaviors=0;EnvironmentVariations=0;HighTvdBehaviors=0}}
  $result=Read-TPMPesterResultV1 -Path $path
  $result.Failed|Should -Be 0
  ($null -eq $result.Failures)|Should -BeFalse -Because 'an empty array is a valid, present collection, distinct from null'
  @($result.Failures).Count|Should -Be 0
 }
 It 'a valid contract with failures is accepted and every failure entry survives intact' {
  $path=Write-TPMContractFixtureV1 -Overrides @{}
  $result=Read-TPMPesterResultV1 -Path $path
  $result.Failed|Should -Be 2
  @($result.Failures).Count|Should -Be 2
  $result.Failures[0].Name|Should -Be 'Test A'
  $result.Failures[1].Message|Should -Be 'threw an exception'
 }
 It 'rejects a missing result file' {
  {Read-TPMPesterResultV1 (Join-Path $TestDrive 'missing.json')}|Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
 }
 It 'rejects an empty result file' {
  $path=Join-Path $TestDrive 'empty.json';[IO.File]::WriteAllText($path,'')
  {Read-TPMPesterResultV1 $path}|Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
 }
 It 'rejects malformed/truncated JSON' {
  $path=Join-Path $TestDrive 'truncated.json';[IO.File]::WriteAllText($path,'{"SchemaVersion":1,"Discove')
  {Read-TPMPesterResultV1 $path}|Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
 }
 It 'rejects a JSON document that is not the exact top-level shape (a bare array instead of an object)' {
  $path=Join-Path $TestDrive 'array.json';[IO.File]::WriteAllText($path,'[1,2,3]')
  {Read-TPMPesterResultV1 $path}|Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
 }
 It 'never surfaces a raw PropertyNotFoundException or JSON conversion exception -- only the one stable schema-invalid error family' {
  $path=Join-Path $TestDrive 'notobject.json';[IO.File]::WriteAllText($path,'42')
  try{Read-TPMPesterResultV1 $path;throw 'expected an exception'}
  catch{
   $_.Exception.Message|Should -Match '^PESTER_RESULT_SCHEMA_INVALID:'
   $_.Exception|Should -Not -BeOfType [Management.Automation.PropertyNotFoundException]
  }
 }

 Context 'top-level field-set adversarial cases' {
  It 'rejects an unexpected extra top-level field' {
   $path=Join-Path $TestDrive 'extra.json'
   $contract=New-TPMValidPesterContractV1;$contract.Extra='x'
   ($contract|ConvertTo-Json -Depth 8)|Set-Content -LiteralPath $path
   {Read-TPMPesterResultV1 $path}|Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
  }
  It 'rejects a missing required top-level field' {
   $path=Write-TPMContractFixtureV1 -Overrides @{DurationMilliseconds=$null}
   {Read-TPMPesterResultV1 $path}|Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
  }
  It 'rejects an unknown/unsupported SchemaVersion' {
   $path=Write-TPMContractFixtureV1 -Overrides @{SchemaVersion=2}
   {Read-TPMPesterResultV1 $path}|Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
  }
 }

 Context 'Engine field adversarial cases' {
  It 'rejects a blank Engine' {
   $path=Write-TPMContractFixtureV1 -Overrides @{Engine='   '}
   {Read-TPMPesterResultV1 $path}|Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
  }
  It 'rejects a non-string Engine' {
   $path=Write-TPMContractFixtureV1 -Overrides @{Engine=5}
   {Read-TPMPesterResultV1 $path}|Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
  }
  It 'rejects a null Engine' {
   $path=Write-TPMContractFixtureV1 -Overrides @{Engine=$null}
   {Read-TPMPesterResultV1 $path}|Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
  }
 }

 Context 'numeric field adversarial cases -- every invalid shape, for every documented numeric field' {
  BeforeDiscovery {
   $numericFields=@('Discovered','Passed','Failed','Skipped','NotRun','Containers','FailedContainers','DurationMilliseconds')
   $invalidShapes=@(
    @{Label='string';Value='3'}
    @{Label='fraction';Value=1.5}
    @{Label='boolean true';Value=$true}
    @{Label='boolean false';Value=$false}
    @{Label='null';Value=$null}
    @{Label='NaN';Value=[double]::NaN}
    @{Label='PositiveInfinity';Value=[double]::PositiveInfinity}
    @{Label='NegativeInfinity';Value=[double]::NegativeInfinity}
    @{Label='array';Value=@(1,2)}
    @{Label='negative';Value=-1}
    @{Label='overflow';Value=99999999999}
   )
   $cases=foreach($field in $numericFields){foreach($shape in $invalidShapes){@{Field=$field;Label=$shape.Label;Value=$shape.Value}}}
  }
  It 'rejects <Field> = <Label>' -TestCases $cases {
   param($Field,$Label,$Value)
   $overrides=@{}
   $overrides[$Field]=$Value
   $path=Write-TPMContractFixtureV1 -Overrides $overrides
   {Read-TPMPesterResultV1 $path}|Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
  }
 }

 Context 'top-level total reconciliation' {
  It 'rejects Discovered that does not equal Passed+Failed+Skipped+NotRun' {
   $path=Write-TPMContractFixtureV1 -Overrides @{Discovered=99}
   {Read-TPMPesterResultV1 $path}|Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
  }
  It 'rejects FailedContainers greater than Containers' {
   $path=Write-TPMContractFixtureV1 -Overrides @{Containers=0;FailedContainers=1}
   {Read-TPMPesterResultV1 $path}|Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
  }
 }

 Context 'Categories adversarial cases' {
  It 'rejects Categories missing a required field' {
   $categories=[ordered]@{VirtualBetaTesterTotal=4;VirtualBetaTesterPassed=2;VirtualBetaTesterFailed=2;HumanBehaviors=1;IdempotencyChecks=1;RecoveryBehaviors=1;EnvironmentVariations=1}
   $path=Write-TPMContractFixtureV1 -Overrides @{Categories=$categories}
   {Read-TPMPesterResultV1 $path}|Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
  }
  It 'rejects Categories with an unexpected extra field' {
   $categories=[ordered]@{VirtualBetaTesterTotal=4;VirtualBetaTesterPassed=2;VirtualBetaTesterFailed=2;HumanBehaviors=1;IdempotencyChecks=1;RecoveryBehaviors=1;EnvironmentVariations=1;HighTvdBehaviors=0;Extra=1}
   $path=Write-TPMContractFixtureV1 -Overrides @{Categories=$categories}
   {Read-TPMPesterResultV1 $path}|Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
  }
  It 'rejects a VirtualBetaTesterTotal/Passed/Failed contradiction' {
   $categories=[ordered]@{VirtualBetaTesterTotal=4;VirtualBetaTesterPassed=2;VirtualBetaTesterFailed=3;HumanBehaviors=1;IdempotencyChecks=1;RecoveryBehaviors=1;EnvironmentVariations=1;HighTvdBehaviors=0}
   $path=Write-TPMContractFixtureV1 -Overrides @{Categories=$categories}
   {Read-TPMPesterResultV1 $path}|Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
  }
  It 'rejects Categories totals that exceed the applicable global totals' {
   $categories=[ordered]@{VirtualBetaTesterTotal=99;VirtualBetaTesterPassed=97;VirtualBetaTesterFailed=2;HumanBehaviors=1;IdempotencyChecks=1;RecoveryBehaviors=1;EnvironmentVariations=1;HighTvdBehaviors=0}
   $path=Write-TPMContractFixtureV1 -Overrides @{Categories=$categories}
   {Read-TPMPesterResultV1 $path}|Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
  }
  It 'rejects a per-behavior category count exceeding VirtualBetaTesterTotal' {
   $categories=[ordered]@{VirtualBetaTesterTotal=4;VirtualBetaTesterPassed=2;VirtualBetaTesterFailed=2;HumanBehaviors=99;IdempotencyChecks=1;RecoveryBehaviors=1;EnvironmentVariations=1;HighTvdBehaviors=0}
   $path=Write-TPMContractFixtureV1 -Overrides @{Categories=$categories}
   {Read-TPMPesterResultV1 $path}|Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
  }
 }

 Context 'Failures adversarial cases' {
  It 'rejects Failures that is not a collection (a bare object)' {
   $path=Join-Path $TestDrive 'failures-object.json'
   $contract=New-TPMValidPesterContractV1
   $json=$contract|ConvertTo-Json -Depth 8
   $json=$json -replace '(?s)"Failures":\s*\[.*?\],\s*"Categories"','"Failures": {"Name":"x","Message":"y"},"Categories"'
   [IO.File]::WriteAllText($path,$json)
   {Read-TPMPesterResultV1 $path}|Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
  }
  It 'rejects a Failures entry with an unexpected extra field' {
   $path=Write-TPMContractFixtureV1 -Overrides @{Failures=@([ordered]@{Name='a';Message='b';Extra='c'})}
   {Read-TPMPesterResultV1 $path}|Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
  }
  It 'rejects a Failures entry missing Message' {
   $path=Write-TPMContractFixtureV1 -Overrides @{Failures=@([ordered]@{Name='a'})}
   {Read-TPMPesterResultV1 $path}|Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
  }
  It 'rejects a Failures entry with a blank Name' {
   $path=Write-TPMContractFixtureV1 -Overrides @{Failures=@([ordered]@{Name='   ';Message='b'})}
   {Read-TPMPesterResultV1 $path}|Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
  }
  It 'rejects a Failures entry with a blank Message' {
   $path=Write-TPMContractFixtureV1 -Overrides @{Failures=@([ordered]@{Name='a';Message='  '})}
   {Read-TPMPesterResultV1 $path}|Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
  }
  It 'rejects a failure-entry count that does not equal Failed (fewer entries than Failed claims)' {
   $path=Write-TPMContractFixtureV1 -Overrides @{Failed=5}
   {Read-TPMPesterResultV1 $path}|Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
  }
  It 'rejects a failure-entry count that does not equal Failed (more entries present than Failed claims, including the Failed=0 case)' {
   $path=Write-TPMContractFixtureV1 -Overrides @{Failed=0;Discovered=3;Passed=3;Categories=[ordered]@{VirtualBetaTesterTotal=0;VirtualBetaTesterPassed=0;VirtualBetaTesterFailed=0;HumanBehaviors=0;IdempotencyChecks=0;RecoveryBehaviors=0;EnvironmentVariations=0;HighTvdBehaviors=0}}
   {Read-TPMPesterResultV1 $path}|Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
  }
 }
}

Describe 'certification production entry points reject interactive/mutating dependencies' {
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
 It 'no script or test under scripts/ or Tests/ sets a blanket confirmation-suppression default' {
  $hits=@(Get-ChildItem -LiteralPath $repoRoot -Include '*.ps1','*.psm1' -Recurse -File|
   Where-Object{$_.FullName -match '\\(scripts|Tests)\\'}|
   Select-String -Pattern '\$PSDefaultParameterValues\s*\[\s*[''"]\*:Confirm[''"]\s*\]' -SimpleMatch:$false)
  $hits.Count|Should -Be 0 -Because 'each call site must handle non-interactive behavior locally and deliberately, never via a hidden global override'
 }
}

Describe 'real prompt-attempt probes -- interactive prompts must fail promptly, never hang, under closed/NonInteractive stdin' {
 BeforeDiscovery {
  $availableEngines=@()
  if(Get-Command pwsh -ErrorAction SilentlyContinue){$availableEngines+=@{Name='Pwsh';Path=(Get-Command pwsh).Source}}
  if(Get-Command powershell.exe -ErrorAction SilentlyContinue){$availableEngines+=@{Name='WindowsPowerShell51';Path=(Get-Command powershell.exe).Source}}

  # Every production entry point in this repo sets $ErrorActionPreference =
  # 'Stop' at the top of the script (confirmed by direct reproduction and by
  # grep across scripts/: Invoke-TPM-PesterChild.ps1, Run-TPM-Tests.ps1,
  # Invoke-TPM-RealInstanceSmoke.ps1, Invoke-TPM-InstallHealthCheck.ps1,
  # Debug-TPM-MenuLayout.ps1, Preview-TPM-ConsoleUx.ps1). Without it, a
  # cmdlet's NonInteractive-mode prompt failure is a non-terminating error
  # that a bare "-Command" script silently continues past -- confirmed by
  # direct reproduction: 'Read-Host "x"; exit 0' under -NonInteractive with
  # closed stdin prints the NonInteractive-mode error to stderr but still
  # reaches "exit 0" (exit code 0) unless $ErrorActionPreference is Stop.
  # These probes set it explicitly so they exercise the same stop-on-error
  # posture every real production entry point already uses, not a weaker
  # posture that would hide the very silent-proceed failure mode this round
  # exists to close off.
  $promptAttempts=@(
   @{Label='Read-Host';Command='$ErrorActionPreference="Stop"; $null=Read-Host "prompt"; exit 0'}
   @{Label='Host.UI.PromptForChoice';Command='$ErrorActionPreference="Stop"; $null=$Host.UI.PromptForChoice("t","m",[System.Management.Automation.Host.ChoiceDescription[]]@((New-Object Management.Automation.Host.ChoiceDescription "&Yes"),(New-Object Management.Automation.Host.ChoiceDescription "&No")),1); exit 0'}
   @{Label='ShouldProcess -Confirm prompt (Remove-Item)';Command='$ErrorActionPreference="Stop"; $f=New-TemporaryFile; Remove-Item -LiteralPath $f.FullName -Confirm; exit 0'}
   @{Label='cmdlet missing a mandatory parameter';Command='$ErrorActionPreference="Stop"; function Test-TPMMandatoryProbe { param([Parameter(Mandatory=$true)][string]$Required) $Required }; Test-TPMMandatoryProbe; exit 0'}
  )

  $cases=foreach($engine in $availableEngines){foreach($attempt in $promptAttempts){@{EngineName=$engine.Name;EnginePath=$engine.Path;Label=$attempt.Label;Command=$attempt.Command}}}
 }

 It '<Label> under <EngineName> terminates promptly without accepting input (nonzero exit, no hang)' -TestCases $cases {
  param($EngineName,$EnginePath,$Label,$Command)
  $r=Invoke-TPMIsolatedProcessV1 -FilePath $EnginePath -ArgumentList @('-NoProfile','-NonInteractive','-Command',$Command) -WorkingDirectory $TestDrive -LogDirectory $TestDrive -Identity ('prompt-probe-'+[guid]::NewGuid().ToString('N').Substring(0,8)) -TimeoutSeconds 30
  $r.TimedOut|Should -BeFalse -Because 'a real hang here would itself be the infrastructure bug this probe exists to catch'
  $r.TerminationConfirmed|Should -BeTrue
  $r.ExitCode|Should -Not -Be 0 -Because 'an interactive prompt attempted under closed/NonInteractive stdin must fail, never silently proceed'
  Test-Path -LiteralPath $r.StdErrPath|Should -BeTrue
 }
}
