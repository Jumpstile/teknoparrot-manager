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
  $r=Invoke-TPMIsolatedProcessV1 -FilePath $engine -ArgumentList @('-NoProfile','-NonInteractive','-Command','[Console]::Out.Write("OUT");[Console]::Error.Write("ERR");exit 37') -WorkingDirectoryRoot $TestDrive -WorkingDirectory $TestDrive -LogDirectoryRoot $TestDrive -LogDirectory $TestDrive -Identity sentinel -TimeoutSeconds 20
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
  # -Include with -LiteralPath -Recurse is silently inert under Windows
  # PowerShell 5.1 (it only filters reliably when -Path carries a trailing
  # wildcard) -- pwsh applies it correctly, but PS 5.1 returns every file
  # including *.md, producing false-positive hits against documentation
  # that merely describes this anti-pattern. Filtering by Extension in
  # Where-Object instead behaves identically on both engines.
  $hits=@(Get-ChildItem -LiteralPath $repoRoot -Recurse -File|
   Where-Object{$_.Extension -in @('.ps1', '.psm1') -and $_.FullName -match '\\(scripts|Tests)\\'}|
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
  $r=Invoke-TPMIsolatedProcessV1 -FilePath $EnginePath -ArgumentList @('-NoProfile','-NonInteractive','-Command',$Command) -WorkingDirectoryRoot $TestDrive -WorkingDirectory $TestDrive -LogDirectoryRoot $TestDrive -LogDirectory $TestDrive -Identity ('prompt-probe-'+[guid]::NewGuid().ToString('N').Substring(0,8)) -TimeoutSeconds 30
  $r.TimedOut|Should -BeFalse -Because 'a real hang here would itself be the infrastructure bug this probe exists to catch'
  $r.TerminationConfirmed|Should -BeTrue
  $r.ExitCode|Should -Not -Be 0 -Because 'an interactive prompt attempted under closed/NonInteractive stdin must fail, never silently proceed'
  Test-Path -LiteralPath $r.StdErrPath|Should -BeTrue
 }
}

Describe 'log sanitization fails closed on persistent retry exhaustion' {
 BeforeAll {
  # Constructs a real System.IO.IOException with a specific HResult using
  # the IOException(message, hresult) constructor -- a documented .NET
  # BCL constructor present identically in both Windows PowerShell 5.1
  # (.NET Framework) and pwsh 7+ (.NET), so tests can exercise the exact
  # classification boundary (transient vs. not) without needing a real OS
  # condition for every case. This is not a production bypass: it only
  # ever appears inside a caller-supplied -Action scriptblock passed into
  # the exported Invoke-TPMSafeFileRetryV1, exactly how any real caller
  # uses that function.
  function New-TPMTestHResultExceptionV1 {
   param([Parameter(Mandatory=$true)][int]$HResult,[string]$Message='synthetic test exception')
   return (New-Object IO.IOException($Message,$HResult))
  }
  $script:ERROR_SHARING_VIOLATION_HRESULT=0x80070020
  $script:ERROR_LOCK_VIOLATION_HRESULT=0x80070021
 }

 Context 'transient HResult classification' {
  It 'classifies ERROR_SHARING_VIOLATION and ERROR_LOCK_VIOLATION as transient' {
   Test-TPMTransientIOHResultV1 -HResult $script:ERROR_SHARING_VIOLATION_HRESULT|Should -BeTrue
   Test-TPMTransientIOHResultV1 -HResult $script:ERROR_LOCK_VIOLATION_HRESULT|Should -BeTrue
  }
  It 'classifies unrelated IOException-family HResults (disk full, path too long, directory not found) as nontransient' {
   # ERROR_DISK_FULL=0x70, ERROR_FILENAME_EXCED_RANGE=0xCE, ERROR_PATH_NOT_FOUND=0x3 -- packed as HRESULTs.
   foreach($hr in @(0x80070070,0x800700CE,0x80070003)){
    Test-TPMTransientIOHResultV1 -HResult $hr|Should -BeFalse
   }
  }
  It 'rejects an HResult adjacent (off by one on either side) to the two transient values -- proves the classifier is not accidentally matching a wider range' {
   Test-TPMTransientIOHResultV1 -HResult ($script:ERROR_SHARING_VIOLATION_HRESULT-1)|Should -BeFalse
   Test-TPMTransientIOHResultV1 -HResult ($script:ERROR_LOCK_VIOLATION_HRESULT+1)|Should -BeFalse
  }
  It 'ADR155-0309 round 3: classifies the ACTUAL, empirically-observed HResult of a genuine OS-level sharing violation and lock violation as transient, and adjacent nontransient real exceptions as nontransient' {
   # This is the direct empirical resolution for round 3's "do not assume
   # textbook HResint values" requirement -- not synthetic
   # IOException(message, hresult) construction (that is covered above),
   # but the REAL .HResult the CLR reports for a genuine, OS-produced
   # ERROR_SHARING_VIOLATION / ERROR_LOCK_VIOLATION on this exact host, in
   # this exact process. Confirmed to be identical decimal/hex values
   # under both Windows PowerShell 5.1 and pwsh 7+ during round 3's
   # investigation: 0x80070020 / -2147024864 (sharing) and 0x80070021 /
   # -2147024863 (lock) -- the two literals Test-TPMTransientIOHResultV1
   # already compares against, confirmed correct rather than assumed.
   $probeDir=Join-Path $TestDrive ('hresult-empirical-'+[guid]::NewGuid().ToString('N'))
   [void](New-Item -ItemType Directory -Path $probeDir -Force)

   $sharePath=Join-Path $probeDir 'share.txt'
   [IO.File]::WriteAllText($sharePath,'x')
   $sharingHandle=New-Object IO.FileStream($sharePath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
   try{
    $caughtSharing=$null
    # New-Object's constructor invocation wraps the real .NET exception in a
    # System.Management.Automation.MethodInvocationException -- the genuine
    # IOException (and its real .HResult) is the InnerException, confirmed
    # by direct reproduction during round 3's investigation.
    try{ [void](New-Object IO.FileStream($sharePath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)) }
    catch{ $caughtSharing=if($_.Exception.InnerException){$_.Exception.InnerException}else{$_.Exception} }
    $caughtSharing|Should -Not -BeNullOrEmpty -Because 'a genuine ERROR_SHARING_VIOLATION must actually occur for this to be real empirical evidence'
    $caughtSharing|Should -BeOfType [IO.IOException]
    $caughtSharing.HResult|Should -Be $script:ERROR_SHARING_VIOLATION_HRESULT
    Test-TPMTransientIOHResultV1 -HResult $caughtSharing.HResult|Should -BeTrue
   }finally{ $sharingHandle.Dispose() }

   $lockPath=Join-Path $probeDir 'lock.txt'
   [IO.File]::WriteAllText($lockPath,'0123456789')
   $lockHandleA=New-Object IO.FileStream($lockPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::ReadWrite)
   $lockHandleB=New-Object IO.FileStream($lockPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::ReadWrite)
   try{
    $lockHandleA.Lock(0,5)
    $caughtLock=$null
    try{ $lockHandleB.Lock(0,5) }
    catch{ $caughtLock=if($_.Exception.InnerException){$_.Exception.InnerException}else{$_.Exception} }
    $caughtLock|Should -Not -BeNullOrEmpty -Because 'a genuine ERROR_LOCK_VIOLATION must actually occur for this to be real empirical evidence'
    $caughtLock|Should -BeOfType [IO.IOException]
    $caughtLock.HResult|Should -Be $script:ERROR_LOCK_VIOLATION_HRESULT
    Test-TPMTransientIOHResultV1 -HResult $caughtLock.HResult|Should -BeTrue
    $lockHandleA.Unlock(0,5)
   }finally{ $lockHandleA.Dispose();$lockHandleB.Dispose() }

   # Adjacent, genuinely-thrown nontransient exceptions must remain nontransient.
   $caughtMissing=$null
   try{ [void](New-Object IO.FileStream((Join-Path $probeDir 'does-not-exist.txt'),[IO.FileMode]::Open)) }
   catch{ $caughtMissing=if($_.Exception.InnerException){$_.Exception.InnerException}else{$_.Exception} }
   $caughtMissing|Should -Not -BeNullOrEmpty
   Test-TPMTransientIOHResultV1 -HResult $caughtMissing.HResult|Should -BeFalse
  }
 }

 Context 'Invoke-TPMSafeFileRetryV1 retry/exhaustion contract' {
  It 'retries a transient failure that clears within the bound and returns the successful result' {
   $script:attempts=0
   $result=Invoke-TPMSafeFileRetryV1 -Operation 'unit-test-read' -TargetIdentity 'synthetic-target' -Action {
    $script:attempts++
    if($script:attempts-lt3){throw (New-TPMTestHResultExceptionV1 -HResult $script:ERROR_SHARING_VIOLATION_HRESULT)}
    return 'ok'
   }
   $result|Should -Be 'ok'
   $script:attempts|Should -Be 3
  }
  It 'throws the deliberate SANITIZATION_RETRY_EXHAUSTED exception after exhausting the retry bound on a persistent transient failure, never silently succeeding' {
   $script:attempts=0
   $caught=$null
   try{
    Invoke-TPMSafeFileRetryV1 -Operation 'unit-test-read' -TargetIdentity 'synthetic-target-persistent' -Action {
     $script:attempts++
     throw (New-TPMTestHResultExceptionV1 -HResult $script:ERROR_SHARING_VIOLATION_HRESULT)
    }
   }catch{$caught=$_}
   $caught|Should -Not -BeNullOrEmpty
   $caught.Exception|Should -BeOfType [IO.IOException]
   $caught.Exception.Message|Should -Match '^SANITIZATION_RETRY_EXHAUSTED:'
   $caught.Exception.Message|Should -Match 'operation=unit-test-read'
   $caught.Exception.Message|Should -Match 'target=synthetic-target-persistent'
   $caught.Exception.Message|Should -Match 'attempts=20'
   $script:attempts|Should -Be 20
  }
  It 'preserves the original underlying exception as InnerException on exhaustion' {
   try{
    Invoke-TPMSafeFileRetryV1 -Operation 'unit-test-read' -TargetIdentity 'synthetic-target-inner' -Action {
     throw (New-TPMTestHResultExceptionV1 -HResult $script:ERROR_LOCK_VIOLATION_HRESULT -Message 'lock held forever')
    }
   }catch{$caught=$_}
   $caught.Exception.InnerException|Should -Not -BeNullOrEmpty
   $caught.Exception.InnerException|Should -BeOfType [IO.IOException]
   $caught.Exception.InnerException.HResult|Should -Be $script:ERROR_LOCK_VIOLATION_HRESULT
   $caught.Exception.Message|Should -Match ([regex]::Escape('innerHResult=0x' + $script:ERROR_LOCK_VIOLATION_HRESULT.ToString('X8')))
  }
  It 'throws immediately with no retry at all for a nontransient IOException (disk full)' {
   $script:attempts=0
   $caught=$null
   try{
    Invoke-TPMSafeFileRetryV1 -Operation 'unit-test-write' -TargetIdentity 'synthetic-target-diskfull' -Action {
     $script:attempts++
     throw (New-TPMTestHResultExceptionV1 -HResult 0x80070070)
    }
   }catch{$caught=$_}
   $script:attempts|Should -Be 1 -Because 'a nontransient IOException must never be retried'
   $caught.Exception|Should -BeOfType [IO.IOException]
   $caught.Exception.Message|Should -Not -Match '^SANITIZATION_RETRY_EXHAUSTED:' -Because 'immediate nontransient failures are the original exception, not the exhaustion-wrapper exception'
  }
  It 'throws immediately with no retry at all for UnauthorizedAccessException' {
   $script:attempts=0
   $caught=$null
   try{
    Invoke-TPMSafeFileRetryV1 -Operation 'unit-test-write' -TargetIdentity 'synthetic-target-unauthorized' -Action {
     $script:attempts++
     throw (New-Object UnauthorizedAccessException('access denied'))
    }
   }catch{$caught=$_}
   $script:attempts|Should -Be 1 -Because 'UnauthorizedAccessException is not an IOException and must never be retried'
   $caught.Exception|Should -BeOfType [UnauthorizedAccessException]
  }
  It 'keeps elapsed time bounded on full exhaustion (no runaway retry loop)' {
   $sw=[Diagnostics.Stopwatch]::StartNew()
   try{
    Invoke-TPMSafeFileRetryV1 -Operation 'unit-test-read' -TargetIdentity 'synthetic-target-timing' -Action {
     throw (New-TPMTestHResultExceptionV1 -HResult $script:ERROR_SHARING_VIOLATION_HRESULT)
    }
   }catch{}
   $sw.Stop()
   $sw.Elapsed.TotalSeconds|Should -BeLessThan 10 -Because '20 attempts at a 100ms backoff bounds this to roughly 2 seconds; 10s is a generous ceiling that still catches a runaway loop'
  }
 }

 Context 'Write-TPMSafeTechnicalFileV1 end-to-end fail-closed behavior (genuine OS-level file locks)' {
  It 'a genuine transient sharing violation that clears within the retry bound succeeds and sanitizes the file' {
   $path=Join-Path $TestDrive 'clears-in-time.log'
   [IO.File]::WriteAllText($path,"before`e[31mred`e[0m",(New-Object Text.UTF8Encoding $false))
   $blocker=New-Object IO.FileStream($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
   # A background PowerShell instance (its own runspace, via
   # BeginInvoke/EndInvoke) releases the lock partway through the retry
   # window. A bare .NET Task/Thread cannot run PowerShell script content
   # (scriptblocks need an attached runspace), so [PowerShell]::Create()
   # is the correct primitive here, not System.Threading.Tasks.Task.
   $releasePs=[PowerShell]::Create()
   [void]$releasePs.AddScript({param($blockerStream) Start-Sleep -Milliseconds 350; $blockerStream.Dispose()}).AddArgument($blocker)
   $releaseHandle=$releasePs.BeginInvoke()
   try{
    { Write-TPMSafeTechnicalFileV1 -Path $path }|Should -Not -Throw
   }finally{
    [void]$releasePs.EndInvoke($releaseHandle)
    $releasePs.Dispose()
   }
   (Get-Content -LiteralPath $path -Raw)|Should -Be 'beforered'
  }
  It 'a persistent read-blocking lock (failed read scenario) throws the deliberate exception and preserves the unsanitized evidence file untouched' {
   $path=Join-Path $TestDrive 'persistent-read-block.log'
   $original="before`e[31mred`e[0m"
   [IO.File]::WriteAllText($path,$original,(New-Object Text.UTF8Encoding $false))
   $blocker=New-Object IO.FileStream($path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
   try{
    { Write-TPMSafeTechnicalFileV1 -Path $path }|Should -Throw '*SANITIZATION_RETRY_EXHAUSTED*'
   }finally{
    $blocker.Dispose()
   }
   [IO.File]::ReadAllText($path)|Should -Be $original -Because 'sanitization failure must never delete or overwrite the preserved technical evidence'
  }
  It 'a persistent write-blocking lock (failed write scenario, read succeeds) throws the deliberate exception and preserves the unsanitized evidence file untouched' {
   $path=Join-Path $TestDrive 'persistent-write-block.log'
   $original="before`e[31mred`e[0m"
   [IO.File]::WriteAllText($path,$original,(New-Object Text.UTF8Encoding $false))
   # FileShare.Read still permits File.ReadAllText's own Read-shared open to
   # succeed, but denies any handle that requests Write access -- isolating
   # the failure to the write half specifically.
   $blocker=New-Object IO.FileStream($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
   try{
    { Write-TPMSafeTechnicalFileV1 -Path $path }|Should -Throw '*SANITIZATION_RETRY_EXHAUSTED*'
   }finally{
    $blocker.Dispose()
   }
   [IO.File]::ReadAllText($path)|Should -Be $original -Because 'sanitization failure must never delete or overwrite the preserved technical evidence'
  }
  It 'never writes raw unsanitized content to the operator console (Write-Host) during a failure path' {
   $path=Join-Path $TestDrive 'console-safety.log'
   $original="before`e[31mSECRET-MARKER-TOKEN`e[0m"
   [IO.File]::WriteAllText($path,$original,(New-Object Text.UTF8Encoding $false))
   $blocker=New-Object IO.FileStream($path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
   Mock -ModuleName TPMCertification.Execution -CommandName Write-Host -MockWith {}
   try{
    try{ Write-TPMSafeTechnicalFileV1 -Path $path }catch{}
   }finally{
    $blocker.Dispose()
   }
   Should -Invoke -ModuleName TPMCertification.Execution -CommandName Write-Host -Times 0 -Because 'the sanitization failure path must never display unsanitized (or any) content to the operator console'
  }
  It 'does not sanitize until an exclusive writer handle is released' {
   $path=Join-Path $TestDrive 'writer-release-boundary.log'
   [IO.File]::WriteAllText($path,"before`e[31mred`e[0m",(New-Object Text.UTF8Encoding $false))
   $blocker=New-Object IO.FileStream($path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
   $script:sanitizeInvoked=$false
   Mock -ModuleName TPMCertification.Execution ConvertTo-TPMSafeTechnicalTextV1 { param([string]$Text) $script:sanitizeInvoked=$true; return ($Text -replace "`e\[[0-9;]*m",'') }
   $releasePs=[PowerShell]::Create()
   [void]$releasePs.AddScript({param($blockerStream) Start-Sleep -Milliseconds 350; $blockerStream.Dispose()}).AddArgument($blocker)
   $releaseHandle=$releasePs.BeginInvoke()
   try{
    { Write-TPMSafeTechnicalFileV1 -Path $path }|Should -Not -Throw
   }finally{
    [void]$releasePs.EndInvoke($releaseHandle)
    $releasePs.Dispose()
   }
   $script:sanitizeInvoked|Should -BeTrue
   [IO.File]::ReadAllText($path)|Should -Be 'beforered'
  }

  It 'keeps an outer self-owned technical log as raw evidence on sharing failure' {
   $path=Join-Path $TestDrive 'outer-harness-owned.log'
   $original='outer technical output'
   [IO.File]::WriteAllText($path,$original,(New-Object Text.UTF8Encoding $false))
   $blocker=New-Object IO.FileStream($path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
   try{
    { Write-TPMSafeTechnicalFileV1 -Path $path }|Should -Throw '*SANITIZATION_RETRY_EXHAUSTED*'
   }finally{$blocker.Dispose()}
   [IO.File]::ReadAllText($path)|Should -Be $original
  }
 }
}

Describe 'owned-directory reparse-chain and component-boundary containment' {
 BeforeDiscovery {
  # -Skip below is evaluated at Pester's discovery phase, before any
  # BeforeAll has run -- the junction-creation capability probe must
  # therefore run here (BeforeDiscovery), not in BeforeAll, or the -Skip
  # condition would always see an unset variable and skip unconditionally
  # regardless of the host's real capability. Uses the system temp
  # directory rather than $TestDrive since $TestDrive is not established
  # during discovery.
  $script:junctionsSupported=$true
  try{
   $probeBase=Join-Path ([IO.Path]::GetTempPath()) ('tpm-junction-probe-'+[guid]::NewGuid().ToString('N'))
   $probeTarget=Join-Path $probeBase 'target'
   $probeLink=Join-Path $probeBase 'link'
   [void](New-Item -ItemType Directory -Path $probeTarget -Force -ErrorAction Stop)
   [void](New-Item -ItemType Junction -Path $probeLink -Target $probeTarget -ErrorAction Stop)
   Remove-Item -LiteralPath $probeBase -Recurse -Force -ErrorAction SilentlyContinue
  }catch{$script:junctionsSupported=$false}
 }
 BeforeAll {
  function New-TPMTestJunctionV1 {
   param([Parameter(Mandatory=$true)][string]$LinkPath,[Parameter(Mandatory=$true)][string]$TargetPath)
   if(-not(Test-Path -LiteralPath $TargetPath)){[void](New-Item -ItemType Directory -Path $TargetPath -Force)}
   [void](New-Item -ItemType Junction -Path $LinkPath -Target $TargetPath -ErrorAction Stop)
  }
 }

 It 'accepts an ordinary nested non-reparse target several levels below a distinct trusted root' {
  $root=Join-Path $TestDrive 'control-root'
  [void](New-Item -ItemType Directory -Path $root -Force)
  $nested=Join-Path $root 'a\b\c'
  [void](New-Item -ItemType Directory -Path $nested -Force)
  { Assert-TPMOwnedDirectoryV1 -Root $root -Path $nested }|Should -Not -Throw
 }
 It 'accepts Root and Target being identical and both ordinary (root==target control case, handled deliberately)' {
  $root=Join-Path $TestDrive 'degenerate-root'
  [void](New-Item -ItemType Directory -Path $root -Force)
  $result=Assert-TPMOwnedDirectoryV1 -Root $root -Path $root
  $result|Should -Be ([IO.Path]::GetFullPath($root).TrimEnd([IO.Path]::DirectorySeparatorChar))
 }
 It 'rejects a target outside the owned root via a sibling-prefix collision (segment-boundary proof)' {
  $root=Join-Path $TestDrive 'Foo\Root'
  $sibling=Join-Path $TestDrive 'Foo\Root-Evil\leaf'
  [void](New-Item -ItemType Directory -Path $root -Force)
  [void](New-Item -ItemType Directory -Path $sibling -Force)
  Test-TPMPathIsContainedV1 -Root $root -Target $sibling|Should -BeFalse -Because 'a raw string-prefix check would wrongly accept Root-Evil as being under Root'
  { Assert-TPMNoReparseInChainV1 -Root $root -Target $sibling }|Should -Throw '*PROCESS_PATH_OUTSIDE_OWNED_ROOT*'
  { Assert-TPMOwnedDirectoryV1 -Root $root -Path $sibling }|Should -Throw '*PROCESS_PATH_OUTSIDE_OWNED_ROOT*' -Because 'the real public entry point must reject the sibling too, not only the low-level chain helper'
 }
 It 'rejects a `..`-escape attempt from the target path, through the real entry point' {
  $root=Join-Path $TestDrive 'escape-root'
  [void](New-Item -ItemType Directory -Path $root -Force)
  $outside=Join-Path $TestDrive 'escape-root-outside'
  [void](New-Item -ItemType Directory -Path $outside -Force)
  $escaped=Join-Path $root '..\escape-root-outside'
  { Assert-TPMNoReparseInChainV1 -Root $root -Target $escaped }|Should -Throw '*PROCESS_PATH_OUTSIDE_OWNED_ROOT*'
  { Assert-TPMOwnedDirectoryV1 -Root $root -Path $escaped }|Should -Throw '*PROCESS_PATH_OUTSIDE_OWNED_ROOT*'
 }
 It 'rejects a missing unauthorized ancestor instead of silently creating it, through the real entry point' {
  $root=Join-Path $TestDrive 'missing-ancestor-root'
  [void](New-Item -ItemType Directory -Path $root -Force)
  $target=Join-Path $root 'no-such-parent\leaf'
  { Assert-TPMNoReparseInChainV1 -Root $root -Target $target -AllowMissingLeaf }|Should -Throw '*does not exist and is not the authorized creation leaf*'
  { Assert-TPMOwnedDirectoryV1 -Root $root -Path $target -CreateIfMissing }|Should -Throw '*does not exist and is not the authorized creation leaf*' -Because 'only a single authorized leaf may be missing -- an unauthorized missing intermediate ancestor must never be silently created'
 }
 It 'the missing-authorized-leaf-creation case succeeds via -CreateIfMissing and is revalidated afterward' {
  $root=Join-Path $TestDrive 'create-leaf-parent'
  [void](New-Item -ItemType Directory -Path $root -Force)
  $leaf=Join-Path $root 'brand-new-leaf'
  Test-Path -LiteralPath $leaf|Should -BeFalse
  $result=Assert-TPMOwnedDirectoryV1 -Root $root -Path $leaf -CreateIfMissing
  $result|Should -Be ([IO.Path]::GetFullPath($leaf).TrimEnd([IO.Path]::DirectorySeparatorChar))
  Test-Path -LiteralPath $leaf -PathType Container|Should -BeTrue
  { Assert-TPMOwnedDirectoryV1 -Root $root -Path $leaf -CreateIfMissing }|Should -Not -Throw -Because 'a second call against the now-existing, still-valid directory must also pass'
 }
 It 'New-TPMOwnedDirectoryChainV1 brings a multi-level path into existence one authorized level at a time, all reparse-checked' {
  $root=Join-Path $TestDrive 'chain-bringup-root'
  [void](New-Item -ItemType Directory -Path $root -Force)
  $target=Join-Path $root 'level1\level2\level3'
  Test-Path -LiteralPath (Join-Path $root 'level1')|Should -BeFalse
  $result=New-TPMOwnedDirectoryChainV1 -Root $root -Path $target
  $result|Should -Be ([IO.Path]::GetFullPath($target).TrimEnd([IO.Path]::DirectorySeparatorChar))
  Test-Path -LiteralPath $target -PathType Container|Should -BeTrue
  { Assert-TPMOwnedDirectoryV1 -Root $root -Path $target }|Should -Not -Throw -Because 'every intermediate level the chain helper created must itself pass reparse validation afterward'
 }
 It 'New-TPMCreateNewFileV1 uses CreateNew semantics and refuses to silently reuse/overwrite an existing file' {
  $root=Join-Path $TestDrive 'createnew-root'
  [void](New-Item -ItemType Directory -Path $root -Force)
  $first=New-TPMCreateNewFileV1 -Root $root -Parent $root -Name 'evidence.log'
  Test-Path -LiteralPath $first|Should -BeTrue
  { New-TPMCreateNewFileV1 -Root $root -Parent $root -Name 'evidence.log' }|Should -Throw -Because 'CreateNew must fail closed rather than silently reopening/overwriting a file that already exists at this path'
 }
 It 'rejects a drive/root-qualifier mismatch between Root and Target, where a second drive is available' {
  $secondDrive=@(Get-PSDrive -PSProvider FileSystem|Where-Object{$_.Name.Length-eq1-and$_.Name-ne(Split-Path -Qualifier $TestDrive).TrimEnd(':')}|Select-Object -First 1)
  if($secondDrive.Count-eq0){Set-ItResult -Skipped -Because 'no second FileSystem drive letter is available in this environment to safely test a drive mismatch';return}
  $root=Join-Path $TestDrive 'drive-mismatch-root'
  [void](New-Item -ItemType Directory -Path $root -Force)
  $otherDriveTarget=($secondDrive[0].Name+':\tpm-drive-mismatch-probe')
  { Assert-TPMOwnedDirectoryV1 -Root $root -Path $otherDriveTarget }|Should -Throw '*PROCESS_PATH_OUTSIDE_OWNED_ROOT*'
 }

 Context 'reparse-point rejection (requires junction/symlink creation to be permitted for this test account)' {
  # Narrowly scoped OS-capability skip (see BeforeDiscovery above): only
  # this specific junction-creation-dependent sub-case is ever skipped,
  # and only when the probe proved this host/account cannot create NTFS
  # junctions. Every non-reparse-creation containment test in this
  # Describe (segment-boundary, sibling-prefix, `..`-escape,
  # missing-ancestor, CreateNew-reuse) runs unconditionally above.
  It 'rejects a trusted root that is itself a reparse point, through the real entry point' -Skip:(-not$script:junctionsSupported) {
   $real=Join-Path $TestDrive 'reparse-root-real'
   $link=Join-Path $TestDrive 'reparse-root-link'
   New-TPMTestJunctionV1 -LinkPath $link -TargetPath $real
   { Assert-TPMOwnedDirectoryV1 -Root $link -Path $link }|Should -Throw '*reparse point rejected*'
  }
  It 'rejects an intermediate junction in the chain between root and target' -Skip:(-not$script:junctionsSupported) {
   $root=Join-Path $TestDrive 'chain-root'
   [void](New-Item -ItemType Directory -Path $root -Force)
   $real=Join-Path $TestDrive 'chain-real-mid'
   $link=Join-Path $root 'mid-link'
   New-TPMTestJunctionV1 -LinkPath $link -TargetPath $real
   $leaf=Join-Path $link 'leaf'
   [void](New-Item -ItemType Directory -Path $leaf -Force)
   { Assert-TPMNoReparseInChainV1 -Root $root -Target $leaf }|Should -Throw '*reparse point rejected in owned-path chain*'
   { Assert-TPMOwnedDirectoryV1 -Root $root -Path $leaf }|Should -Throw '*reparse point rejected in owned-path chain*' -Because 'the real public entry point must reject an intermediate-level junction, not just the leaf'
  }
  It 'rejects a reparse-point leaf, through the real entry point' -Skip:(-not$script:junctionsSupported) {
   $root=Join-Path $TestDrive 'leaf-reparse-root'
   [void](New-Item -ItemType Directory -Path $root -Force)
   $real=Join-Path $TestDrive 'leaf-reparse-real'
   $link=Join-Path $root 'leaf-link'
   New-TPMTestJunctionV1 -LinkPath $link -TargetPath $real
   { Assert-TPMNoReparseInChainV1 -Root $root -Target $link }|Should -Throw '*reparse point rejected in owned-path chain*'
   { Assert-TPMOwnedDirectoryV1 -Root $root -Path $link }|Should -Throw '*reparse point rejected in owned-path chain*'
  }
  It 'Invoke-TPMIsolatedProcessV1 rejects a junction anywhere in the LogDirectoryRoot-to-LogDirectory chain before ever spawning a process' -Skip:(-not$script:junctionsSupported) {
   $engine=if($PSVersionTable.PSEdition-eq'Core'){(Get-Command pwsh).Source}else{(Get-Command powershell.exe).Source}
   $logRoot=Join-Path $TestDrive 'isolated-log-root'
   [void](New-Item -ItemType Directory -Path $logRoot -Force)
   $real=Join-Path $TestDrive 'isolated-log-real'
   $link=Join-Path $logRoot 'log-link'
   New-TPMTestJunctionV1 -LinkPath $link -TargetPath $real
   $logDirectory=Join-Path $link 'run'
   { Invoke-TPMIsolatedProcessV1 -FilePath $engine -ArgumentList @('-NoProfile','-NonInteractive','-Command','exit 0') -WorkingDirectoryRoot $TestDrive -WorkingDirectory $TestDrive -LogDirectoryRoot $logRoot -LogDirectory $logDirectory -Identity 'junction-reject-probe' -TimeoutSeconds 20 }|Should -Throw '*reparse point rejected*' -Because 'the isolation primitive must fail closed on an intermediate junction before ever launching the child process'
  }
  It 'reparse substitution injected between validation and use is caught by TOCTOU revalidation after creation' -Skip:(-not$script:junctionsSupported) {
   # This is the one sub-case the task explicitly allows narrowing: safely
   # racing the exact validate-then-use window in production code is not
   # reproducible from a test without changing production control flow.
   # What IS directly provable, and is proven here, is the TOCTOU
   # revalidation mechanism itself: replace an already-validated,
   # freshly-created owned directory with a junction, then show that
   # re-running Assert-TPMOwnedDirectoryV1 against that same path (exactly
   # what the post-creation revalidation call inside the function does)
   # detects and rejects it rather than trusting the earlier validation.
   $parent=Join-Path $TestDrive 'toctou-parent'
   [void](New-Item -ItemType Directory -Path $parent -Force)
   $leaf=Join-Path $parent 'toctou-leaf'
   $result=Assert-TPMOwnedDirectoryV1 -Root $parent -Path $leaf -CreateIfMissing
   $result|Should -Not -BeNullOrEmpty
   Remove-Item -LiteralPath $leaf -Force -Recurse
   $real=Join-Path $TestDrive 'toctou-real'
   New-TPMTestJunctionV1 -LinkPath $leaf -TargetPath $real
   { Assert-TPMOwnedDirectoryV1 -Root $parent -Path $leaf }|Should -Throw '*reparse point rejected*' -Because 'revalidation must never trust a path just because it passed validation earlier'
  }
  It 'a substitution injected strictly AFTER Assert-TPMOwnedDirectoryV1 validated the parent, but BEFORE New-TPMCreateNewFileV1 opens the owned file, is caught by the second, closer-to-use revalidation point' -Skip:(-not$script:junctionsSupported) {
   $root=Join-Path $TestDrive 'preuse-root'
   [void](New-Item -ItemType Directory -Path $root -Force)
   $parent=Join-Path $root 'preuse-parent'
   $validated=Assert-TPMOwnedDirectoryV1 -Root $root -Path $parent -CreateIfMissing
   $validated|Should -Not -BeNullOrEmpty
   # Simulates a substitution landing strictly between an earlier,
   # already-completed Assert-TPMOwnedDirectoryV1 validation and the
   # later file-creation call -- distinct from the post-creation TOCTOU
   # case above, which revalidates by re-running Assert-TPMOwnedDirectoryV1
   # itself. This proves New-TPMCreateNewFileV1's OWN internal
   # pre-open revalidation (the second of the two required points)
   # independently catches a substitution that a caller who only
   # validated once, earlier, would otherwise miss.
   Remove-Item -LiteralPath $parent -Force -Recurse
   $real=Join-Path $TestDrive 'preuse-real'
   New-TPMTestJunctionV1 -LinkPath $parent -TargetPath $real
   { New-TPMCreateNewFileV1 -Root $root -Parent $parent -Name 'evidence.log' }|Should -Throw '*reparse point rejected*' -Because 'New-TPMCreateNewFileV1 must never trust an earlier validation of Parent -- it revalidates immediately before opening the file'
  }
 }
}
