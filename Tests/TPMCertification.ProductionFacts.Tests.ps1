#Requires -Module Pester
BeforeDiscovery {
 # Real NTFS-junction capability probe, evaluated at discovery time (see
 # Tests/TPMCertification.OperatorExperience.Tests.ps1's identical idiom)
 # so the -Skip guards below see the real host capability rather than an
 # unset variable. Only the specific junction-dependent redirected-cleanup
 # sub-cases are ever skipped on this probe; every non-junction ownership
 # test in this file runs unconditionally.
 $script:tpmProductionFactsJunctionsSupported=$true
 try{
  $probeBase=Join-Path ([IO.Path]::GetTempPath()) ('tpm-pf-junction-probe-'+[guid]::NewGuid().ToString('N'))
  $probeTarget=Join-Path $probeBase 'target'
  $probeLink=Join-Path $probeBase 'link'
  [void](New-Item -ItemType Directory -Path $probeTarget -Force -ErrorAction Stop)
  [void](New-Item -ItemType Junction -Path $probeLink -Target $probeTarget -ErrorAction Stop)
  Remove-Item -LiteralPath $probeBase -Recurse -Force -ErrorAction SilentlyContinue
 }catch{$script:tpmProductionFactsJunctionsSupported=$false}
}
BeforeAll {
 $scriptsDir=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts'
 Import-Module (Join-Path $scriptsDir 'TPMCertification.Authority.psm1') -Force
 Import-Module (Join-Path $scriptsDir 'TPMCertification.Production.psm1') -Force
 Import-Module (Join-Path $scriptsDir 'TPMCertification.Reports.psm1') -Force
 Import-Module (Join-Path $scriptsDir 'TPMCertification.Publication.psm1') -Force
 Import-Module (Join-Path $scriptsDir 'TPMCertification.ProductionFacts.psm1') -Force

 function New-LegacyResultsFixture([string]$Repo,[string]$Report,[string]$Backup){
  New-Item -ItemType Directory -Path $Repo,(Join-Path $Repo 'Tests'),$Report,(Join-Path $Backup 'UserProfiles') -Force|Out-Null
  [IO.File]::WriteAllText((Join-Path $Repo 'Tests\one.ps1'),'test')
  New-Item -ItemType Directory -Path (Join-Path $Report 'InstallHealth')|Out-Null
  [IO.File]::WriteAllText((Join-Path $Report 'InstallHealth\InstallHealth.json'),'{}')
  $zero=[pscustomobject]@{Added=0;Removed=0;Changed=0;BeforeSkipped=0;AfterSkipped=0}
  $health=[pscustomobject]@{Checks=@([pscustomobject]@{Name='TeknoParrotUi.exe exists';Passed=$true},[pscustomobject]@{Name='GameProfiles folder exists';Passed=$true},[pscustomobject]@{Name='UserProfiles folder exists';Passed=$true})}
  $results=[pscustomobject]@{
   SmokeMode=$true;Checks=@([pscustomobject]@{Name='Repository available';Passed=$true});GitStatus='(clean)'
   Pester=[pscustomobject]@{Total=2;Passed=2;Failed=0;Skipped=0;NotRun=0};PesterVersion='5.7.1';PowerShellVersion='7.6.3'
   PSScriptAnalyzerFindings=999;PSScriptAnalyzerVersion='decoy-legacy-value'
   Backup=[pscustomobject]@{UserProfiles=$true;GameProfiles=$false}
   Snapshots=[ordered]@{UserProfiles=$zero;GameProfiles=$zero;Pcsx2x6Crosshairs=$zero}
   Pcsx2x6=[pscustomobject]@{Present=$false}
   VirtualBetaTester=[pscustomobject]@{Total=1;Passed=1;Failed=0;HumanBehaviors=1;IdempotencyChecks=0;RecoveryBehaviors=0;EnvironmentVariations=0;HighTvdBehaviors=1}
   RequestedTeknoParrotRoot=$Repo;EffectiveTeknoParrotRoot=$null
  }
  return @{Results=$results;Health=$health}
 }

 function New-InventoryFixture([string]$Root){
  # Creates stub content for ALL SEVENTEEN entries in the real, fixed
  # authoritative inventory -- Get-TPMProductionPowerShellInventoryV1 no
  # longer accepts a reduced/overridden file set, so any test driving it
  # through the real (non-InModuleScope) entry point needs every entry
  # physically present.
  $repo=Join-Path $Root 'repo'
  New-Item -ItemType Directory -Path $repo,(Join-Path $repo 'scripts'),(Join-Path $repo 'tools') -Force|Out-Null
  $relativePaths=@(
   'TeknoParrot-Manager.ps1','scripts/Debug-TPM-MenuLayout.ps1','tools/Invoke-TpmAutoUpdate.ps1','tools/TpmAutoUpdate.Core.psm1',
   'scripts/Invoke-TPM-RealInstanceSmoke.ps1','scripts/Invoke-TPM-InstallHealthCheck.ps1','scripts/Resolve-Pcsx2Directory.ps1','scripts/Run-TPM-Tests.ps1','scripts/TPMCertification.Execution.psm1','scripts/Invoke-TPM-PesterChild.ps1',
   'scripts/TPMCertification.Authority.psm1','scripts/TPMCertification.Production.psm1','scripts/TPMCertification.ProductionCycle.psm1','scripts/TPMCertification.ProductionEvidence.psm1','scripts/TPMCertification.ProductionFacts.psm1',
   'scripts/TPMCertification.Publication.psm1','scripts/TPMCertification.Reports.psm1','scripts/TPMCertification.Shadow.psm1','scripts/Test-TPMParserCheckV1.ps1'
  )
  foreach($relative in $relativePaths){
   $full=Join-Path $repo ($relative-replace'/','\')
   [IO.File]::WriteAllText($full,"Write-Output '$relative'")
  }
  return $repo
 }

 $repoRoot=(Split-Path $PSScriptRoot -Parent)

 function New-TPMTestJunctionV1 {
  param([Parameter(Mandatory=$true)][string]$LinkPath,[Parameter(Mandatory=$true)][string]$TargetPath)
  if(-not(Test-Path -LiteralPath $TargetPath)){[void](New-Item -ItemType Directory -Path $TargetPath -Force)}
  [void](New-Item -ItemType Junction -Path $LinkPath -Target $TargetPath -ErrorAction Stop)
 }
}

Describe 'TPMCertification.ProductionFacts public API surface' {
 It 'exports exactly Get-TPMProductionPowerShellInventoryV1 and New-TPMProductionFactRecordsV1' {
  # Every other function in this module is an implementation detail: an
  # exported destructive/internal helper (e.g. the scratch-directory
  # deletion primitive) would let a caller forge an "Owned" descriptor and
  # invoke recursive deletion outside any real ownership check -- ownership
  # represented by a caller-constructible object is not an authorization
  # boundary. Only these two are genuinely required by any current caller.
  $exported=@((Get-Module TPMCertification.ProductionFacts).ExportedCommands.Keys|Sort-Object)
  $exported|Should -Be @('Get-TPMProductionPowerShellInventoryV1','New-TPMProductionFactRecordsV1')
 }
}

Describe 'Get-TPMProductionPowerShellInventoryV1 (production entry point)' {
 It 'resolves the complete, real, 19-file authoritative inventory in deterministic order' {
  $inv=Get-TPMProductionPowerShellInventoryV1 -RepositoryPath $repoRoot
  $inv.Count|Should -Be 19
  @($inv.RelativePath)|Should -Be @(
   'TeknoParrot-Manager.ps1','scripts/Debug-TPM-MenuLayout.ps1','tools/Invoke-TpmAutoUpdate.ps1','tools/TpmAutoUpdate.Core.psm1',
   'scripts/Invoke-TPM-RealInstanceSmoke.ps1','scripts/Invoke-TPM-InstallHealthCheck.ps1','scripts/Resolve-Pcsx2Directory.ps1','scripts/Run-TPM-Tests.ps1','scripts/TPMCertification.Execution.psm1','scripts/Invoke-TPM-PesterChild.ps1',
   'scripts/TPMCertification.Authority.psm1','scripts/TPMCertification.Production.psm1','scripts/TPMCertification.ProductionCycle.psm1','scripts/TPMCertification.ProductionEvidence.psm1','scripts/TPMCertification.ProductionFacts.psm1',
   'scripts/TPMCertification.Publication.psm1','scripts/TPMCertification.Reports.psm1','scripts/TPMCertification.Shadow.psm1','scripts/Test-TPMParserCheckV1.ps1'
  )
  foreach($item in $inv){Test-Path -LiteralPath $item.FullPath -PathType Leaf|Should -BeTrue}
 }
 It 'exposes no parameter that lets a caller substitute a different file set' {
  (Get-Command Get-TPMProductionPowerShellInventoryV1).Parameters.Keys|Should -Not -Contain 'RelativePaths'
 }
 It 'does not export the private validation helper' {
  Get-Command Resolve-TPMProductionPowerShellInventoryEntriesV1 -Module TPMCertification.ProductionFacts -ErrorAction SilentlyContinue|Should -BeNullOrEmpty
 }
}

Describe 'Resolve-TPMProductionPowerShellInventoryEntriesV1 (private, InModuleScope only)' {
 It 'rejects a missing entry' {
  $repo=New-InventoryFixture (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
  Remove-Item -LiteralPath (Join-Path $repo 'tools\TpmAutoUpdate.Core.psm1') -Force
  InModuleScope TPMCertification.ProductionFacts -Parameters @{Repo=$repo} {
   { Resolve-TPMProductionPowerShellInventoryEntriesV1 -RepositoryPath $Repo -RelativePaths @('TeknoParrot-Manager.ps1','scripts/Debug-TPM-MenuLayout.ps1','tools/Invoke-TpmAutoUpdate.ps1','tools/TpmAutoUpdate.Core.psm1') } | Should -Throw '*PRODUCTION_INVENTORY_MISSING*'
  }
 }
 It 'rejects an unreadable (locked) entry' {
  $repo=New-InventoryFixture (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
  $locked=Join-Path $repo 'TeknoParrot-Manager.ps1'
  $stream=[IO.File]::Open($locked,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
  try{
   InModuleScope TPMCertification.ProductionFacts -Parameters @{Repo=$repo} {
    { Resolve-TPMProductionPowerShellInventoryEntriesV1 -RepositoryPath $Repo -RelativePaths @('TeknoParrot-Manager.ps1') } | Should -Throw '*PRODUCTION_INVENTORY_UNREADABLE*'
   }
  } finally { $stream.Dispose() }
 }
 It 'rejects a duplicate relative path in the requested list' {
  $repo=New-InventoryFixture (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
  InModuleScope TPMCertification.ProductionFacts -Parameters @{Repo=$repo} {
   { Resolve-TPMProductionPowerShellInventoryEntriesV1 -RepositoryPath $Repo -RelativePaths @('TeknoParrot-Manager.ps1','TeknoParrot-Manager.ps1') } | Should -Throw '*PRODUCTION_INVENTORY_DUPLICATE*'
  }
 }
 It 'rejects an entry that resolves outside the repository root' {
  $repo=New-InventoryFixture (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
  InModuleScope TPMCertification.ProductionFacts -Parameters @{Repo=$repo} {
   { Resolve-TPMProductionPowerShellInventoryEntriesV1 -RepositoryPath $Repo -RelativePaths @('../outside.ps1') } | Should -Throw '*PRODUCTION_INVENTORY_OUTSIDE_ROOT*'
  }
 }
}

Describe 'Test-TPMProductionParserProbeV1 (private, InModuleScope only)' {
 It 'reports real per-file success for a non-main-module inventory file' {
  $repo=New-InventoryFixture (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
  $inv=@([ordered]@{RelativePath='tools/Invoke-TpmAutoUpdate.ps1';FullPath=(Join-Path $repo 'tools\Invoke-TpmAutoUpdate.ps1')})
  $work=Join-Path $TestDrive ('work-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $work|Out-Null
  $engine=if($PSVersionTable.PSEdition -ceq 'Core'){'Pwsh'}else{'WindowsPowerShell51'}
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;Engine=$engine;Work=$work} {
   Test-TPMProductionParserProbeV1 -Inventory $Inv -Engine $Engine -WorkingDirectoryRoot $Work -WorkingDirectory $Work
  }
  $result.Executed|Should -BeTrue
  $result.ErrorCount|Should -Be 0
 }
 It 'reports a positive error count for a syntactically invalid non-main-module file' {
  $repo=New-InventoryFixture (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
  [IO.File]::WriteAllText((Join-Path $repo 'tools\Invoke-TpmAutoUpdate.ps1'),'function {{{ not valid (')
  $inv=@([ordered]@{RelativePath='tools/Invoke-TpmAutoUpdate.ps1';FullPath=(Join-Path $repo 'tools\Invoke-TpmAutoUpdate.ps1')})
  $work=Join-Path $TestDrive ('work-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $work|Out-Null
  $engine=if($PSVersionTable.PSEdition -ceq 'Core'){'Pwsh'}else{'WindowsPowerShell51'}
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;Engine=$engine;Work=$work} {
   Test-TPMProductionParserProbeV1 -Inventory $Inv -Engine $Engine -WorkingDirectoryRoot $Work -WorkingDirectory $Work
  }
  $result.Executed|Should -BeTrue
  $result.ErrorCount|Should -BeGreaterThan 0
 }
 It 'survives a file path containing spaces and metacharacters exactly' {
  $dir=Join-Path $TestDrive ('dir with spaces & ($stuff)-'+[guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $dir -Force|Out-Null
  $file=Join-Path $dir 'a file (with) [odd] chars.ps1'
  [IO.File]::WriteAllText($file,'Write-Output 1')
  $inv=@([ordered]@{RelativePath='a.ps1';FullPath=$file})
  $work=Join-Path $TestDrive ('work-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $work|Out-Null
  $engine=if($PSVersionTable.PSEdition -ceq 'Core'){'Pwsh'}else{'WindowsPowerShell51'}
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;Engine=$engine;Work=$work} {
   Test-TPMProductionParserProbeV1 -Inventory $Inv -Engine $Engine -WorkingDirectoryRoot $Work -WorkingDirectory $Work
  }
  $result.Executed|Should -BeTrue
  $result.ErrorCount|Should -Be 0
 }
 It 'reports Executed=false when the engine executable cannot be resolved' {
  Mock Get-Command { $null } -ModuleName TPMCertification.ProductionFacts
  $inv=@([ordered]@{RelativePath='a.ps1';FullPath=(Join-Path $TestDrive 'a.ps1')})
  $work=Join-Path $TestDrive ('work-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $work|Out-Null
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;Work=$work} {
   Test-TPMProductionParserProbeV1 -Inventory $Inv -Engine Pwsh -WorkingDirectoryRoot $Work -WorkingDirectory $Work
  }
  $result.Executed|Should -BeFalse
 }
 It 'reports Executed=false on process timeout' {
  Mock Invoke-TPMExternalProcessWithTimeoutV1 { [ordered]@{TimedOut=$true;TerminationConfirmed=$true;ExitCode=$null;StdOut=$null;StdErr=$null;StdOutPath=$null;StdErrPath=$null} } -ModuleName TPMCertification.ProductionFacts
  $inv=@([ordered]@{RelativePath='a.ps1';FullPath=(Join-Path $TestDrive 'a.ps1')})
  [IO.File]::WriteAllText((Join-Path $TestDrive 'a.ps1'),'1')
  $work=Join-Path $TestDrive ('work-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $work|Out-Null
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;Work=$work} {
   Test-TPMProductionParserProbeV1 -Inventory $Inv -Engine Pwsh -WorkingDirectoryRoot $Work -WorkingDirectory $Work
  }
  $result.Executed|Should -BeFalse
 }
 It 'reports Executed=false on a non-zero process exit code' {
  Mock Invoke-TPMExternalProcessWithTimeoutV1 { [ordered]@{TimedOut=$false;TerminationConfirmed=$true;ExitCode=1;StdOut=$null;StdErr='boom';StdOutPath=$null;StdErrPath=$null} } -ModuleName TPMCertification.ProductionFacts
  $inv=@([ordered]@{RelativePath='a.ps1';FullPath=(Join-Path $TestDrive 'a.ps1')})
  [IO.File]::WriteAllText((Join-Path $TestDrive 'a.ps1'),'1')
  $work=Join-Path $TestDrive ('work-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $work|Out-Null
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;Work=$work} {
   Test-TPMProductionParserProbeV1 -Inventory $Inv -Engine Pwsh -WorkingDirectoryRoot $Work -WorkingDirectory $Work
  }
  $result.Executed|Should -BeFalse
 }
 It 'reports Executed=false when probe output is malformed JSON' {
  Mock Invoke-TPMExternalProcessWithTimeoutV1 {
   param($FilePath,$ArgumentList,$TimeoutSeconds,$WorkingDirectory)
   $idx=[Array]::IndexOf($ArgumentList,'-OutputPath')
   [IO.File]::WriteAllText($ArgumentList[$idx+1],'{not valid json')
   [ordered]@{TimedOut=$false;TerminationConfirmed=$true;ExitCode=0;StdOut=$null;StdErr=$null;StdOutPath=$null;StdErrPath=$null}
  } -ModuleName TPMCertification.ProductionFacts
  $inv=@([ordered]@{RelativePath='a.ps1';FullPath=(Join-Path $TestDrive 'a.ps1')})
  [IO.File]::WriteAllText((Join-Path $TestDrive 'a.ps1'),'1')
  $work=Join-Path $TestDrive ('work-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $work|Out-Null
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;Work=$work} {
   Test-TPMProductionParserProbeV1 -Inventory $Inv -Engine Pwsh -WorkingDirectoryRoot $Work -WorkingDirectory $Work
  }
  $result.Executed|Should -BeFalse
 }
 It 'reports Executed=false when probe output has extra results for a single requested file' {
  Mock Invoke-TPMExternalProcessWithTimeoutV1 {
   param($FilePath,$ArgumentList,$TimeoutSeconds,$WorkingDirectory)
   $idx=[Array]::IndexOf($ArgumentList,'-OutputPath')
   $requested=$ArgumentList[[Array]::IndexOf($ArgumentList,'-Path')+1]
   $payload=[pscustomobject]@{Results=@([pscustomobject]@{Path=$requested;ErrorCount=0;Version='1'},[pscustomobject]@{Path=$requested;ErrorCount=0;Version='1'})}
   [IO.File]::WriteAllText($ArgumentList[$idx+1],($payload|ConvertTo-Json -Depth 4 -Compress))
   [ordered]@{TimedOut=$false;TerminationConfirmed=$true;ExitCode=0;StdOut=$null;StdErr=$null;StdOutPath=$null;StdErrPath=$null}
  } -ModuleName TPMCertification.ProductionFacts
  $inv=@([ordered]@{RelativePath='a.ps1';FullPath=(Join-Path $TestDrive 'a.ps1')})
  [IO.File]::WriteAllText((Join-Path $TestDrive 'a.ps1'),'1')
  $work=Join-Path $TestDrive ('work-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $work|Out-Null
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;Work=$work} {
   Test-TPMProductionParserProbeV1 -Inventory $Inv -Engine Pwsh -WorkingDirectoryRoot $Work -WorkingDirectory $Work
  }
  $result.Executed|Should -BeFalse
 }
 It 'reports Executed=false when probe output has zero results (partial/missing output)' {
  Mock Invoke-TPMExternalProcessWithTimeoutV1 {
   param($FilePath,$ArgumentList,$TimeoutSeconds,$WorkingDirectory)
   $idx=[Array]::IndexOf($ArgumentList,'-OutputPath')
   $payload=[pscustomobject]@{Results=@()}
   [IO.File]::WriteAllText($ArgumentList[$idx+1],($payload|ConvertTo-Json -Depth 4 -Compress))
   [ordered]@{TimedOut=$false;TerminationConfirmed=$true;ExitCode=0;StdOut=$null;StdErr=$null;StdOutPath=$null;StdErrPath=$null}
  } -ModuleName TPMCertification.ProductionFacts
  $inv=@([ordered]@{RelativePath='a.ps1';FullPath=(Join-Path $TestDrive 'a.ps1')})
  [IO.File]::WriteAllText((Join-Path $TestDrive 'a.ps1'),'1')
  $work=Join-Path $TestDrive ('work-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $work|Out-Null
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;Work=$work} {
   Test-TPMProductionParserProbeV1 -Inventory $Inv -Engine Pwsh -WorkingDirectoryRoot $Work -WorkingDirectory $Work
  }
  $result.Executed|Should -BeFalse
 }
 It 'reports Executed=false when the returned Path does not correlate to the requested file' {
  Mock Invoke-TPMExternalProcessWithTimeoutV1 {
   param($FilePath,$ArgumentList,$TimeoutSeconds,$WorkingDirectory)
   $idx=[Array]::IndexOf($ArgumentList,'-OutputPath')
   $payload=[pscustomobject]@{Results=@([pscustomobject]@{Path='C:\some\other\file.ps1';ErrorCount=0;Version='1'})}
   [IO.File]::WriteAllText($ArgumentList[$idx+1],($payload|ConvertTo-Json -Depth 4 -Compress))
   [ordered]@{TimedOut=$false;TerminationConfirmed=$true;ExitCode=0;StdOut=$null;StdErr=$null;StdOutPath=$null;StdErrPath=$null}
  } -ModuleName TPMCertification.ProductionFacts
  $inv=@([ordered]@{RelativePath='a.ps1';FullPath=(Join-Path $TestDrive 'a.ps1')})
  [IO.File]::WriteAllText((Join-Path $TestDrive 'a.ps1'),'1')
  $work=Join-Path $TestDrive ('work-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $work|Out-Null
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;Work=$work} {
   Test-TPMProductionParserProbeV1 -Inventory $Inv -Engine Pwsh -WorkingDirectoryRoot $Work -WorkingDirectory $Work
  }
  $result.Executed|Should -BeFalse
 }
 It 'reports Executed=false when a required field is missing (partial diagnostic output)' {
  Mock Invoke-TPMExternalProcessWithTimeoutV1 {
   param($FilePath,$ArgumentList,$TimeoutSeconds,$WorkingDirectory)
   $idx=[Array]::IndexOf($ArgumentList,'-OutputPath')
   $requested=$ArgumentList[[Array]::IndexOf($ArgumentList,'-Path')+1]
   $payload=[pscustomobject]@{Results=@([pscustomobject]@{Path=$requested;ErrorCount=0})}
   [IO.File]::WriteAllText($ArgumentList[$idx+1],($payload|ConvertTo-Json -Depth 4 -Compress))
   [ordered]@{TimedOut=$false;TerminationConfirmed=$true;ExitCode=0;StdOut=$null;StdErr=$null;StdOutPath=$null;StdErrPath=$null}
  } -ModuleName TPMCertification.ProductionFacts
  $inv=@([ordered]@{RelativePath='a.ps1';FullPath=(Join-Path $TestDrive 'a.ps1')})
  [IO.File]::WriteAllText((Join-Path $TestDrive 'a.ps1'),'1')
  $work=Join-Path $TestDrive ('work-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $work|Out-Null
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;Work=$work} {
   Test-TPMProductionParserProbeV1 -Inventory $Inv -Engine Pwsh -WorkingDirectoryRoot $Work -WorkingDirectory $Work
  }
  $result.Executed|Should -BeFalse
 }
 It 'reports Executed=false when ErrorCount is negative (malformed diagnostic output)' {
  Mock Invoke-TPMExternalProcessWithTimeoutV1 {
   param($FilePath,$ArgumentList,$TimeoutSeconds,$WorkingDirectory)
   $idx=[Array]::IndexOf($ArgumentList,'-OutputPath')
   $requested=$ArgumentList[[Array]::IndexOf($ArgumentList,'-Path')+1]
   $payload=[pscustomobject]@{Results=@([pscustomobject]@{Path=$requested;ErrorCount=-1;Version='1'})}
   [IO.File]::WriteAllText($ArgumentList[$idx+1],($payload|ConvertTo-Json -Depth 4 -Compress))
   [ordered]@{TimedOut=$false;TerminationConfirmed=$true;ExitCode=0;StdOut=$null;StdErr=$null;StdOutPath=$null;StdErrPath=$null}
  } -ModuleName TPMCertification.ProductionFacts
  $inv=@([ordered]@{RelativePath='a.ps1';FullPath=(Join-Path $TestDrive 'a.ps1')})
  [IO.File]::WriteAllText((Join-Path $TestDrive 'a.ps1'),'1')
  $work=Join-Path $TestDrive ('work-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $work|Out-Null
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;Work=$work} {
   Test-TPMProductionParserProbeV1 -Inventory $Inv -Engine Pwsh -WorkingDirectoryRoot $Work -WorkingDirectory $Work
  }
  $result.Executed|Should -BeFalse
 }
 It 'reports Executed=false when the same engine reports inconsistent versions across files' {
  Mock Invoke-TPMExternalProcessWithTimeoutV1 {
   param($FilePath,$ArgumentList,$TimeoutSeconds,$WorkingDirectory)
   $idx=[Array]::IndexOf($ArgumentList,'-OutputPath')
   $requested=$ArgumentList[[Array]::IndexOf($ArgumentList,'-Path')+1]
   $version=if($requested -like '*second*'){'9.9.9'}else{'1.0.0'}
   $payload=[pscustomobject]@{Results=@([pscustomobject]@{Path=$requested;ErrorCount=0;Version=$version})}
   [IO.File]::WriteAllText($ArgumentList[$idx+1],($payload|ConvertTo-Json -Depth 4 -Compress))
   [ordered]@{TimedOut=$false;TerminationConfirmed=$true;ExitCode=0;StdOut=$null;StdErr=$null;StdOutPath=$null;StdErrPath=$null}
  } -ModuleName TPMCertification.ProductionFacts
  $inv=@([ordered]@{RelativePath='first.ps1';FullPath=(Join-Path $TestDrive 'first.ps1')},[ordered]@{RelativePath='second.ps1';FullPath=(Join-Path $TestDrive 'second.ps1')})
  [IO.File]::WriteAllText((Join-Path $TestDrive 'first.ps1'),'1');[IO.File]::WriteAllText((Join-Path $TestDrive 'second.ps1'),'1')
  $work=Join-Path $TestDrive ('work-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $work|Out-Null
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;Work=$work} {
   Test-TPMProductionParserProbeV1 -Inventory $Inv -Engine Pwsh -WorkingDirectoryRoot $Work -WorkingDirectory $Work
  }
  $result.Executed|Should -BeFalse
 }
 It 'requires complete coverage across every inventory file before setting Executed=true' {
  $repo=New-InventoryFixture (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
  [IO.File]::WriteAllText((Join-Path $repo 'tools\TpmAutoUpdate.Core.psm1'),'function {{{ broken (')
  $inv=@([ordered]@{RelativePath='scripts/Debug-TPM-MenuLayout.ps1';FullPath=(Join-Path $repo 'scripts\Debug-TPM-MenuLayout.ps1')},[ordered]@{RelativePath='tools/TpmAutoUpdate.Core.psm1';FullPath=(Join-Path $repo 'tools\TpmAutoUpdate.Core.psm1')})
  $work=Join-Path $TestDrive ('work-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $work|Out-Null
  $engine=if($PSVersionTable.PSEdition -ceq 'Core'){'Pwsh'}else{'WindowsPowerShell51'}
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;Engine=$engine;Work=$work} {
   Test-TPMProductionParserProbeV1 -Inventory $Inv -Engine $Engine -WorkingDirectoryRoot $Work -WorkingDirectory $Work
  }
  $result.Executed|Should -BeTrue
  $result.ErrorCount|Should -BeGreaterThan 0
 }
}

Describe 'Invoke-TPMExternalProcessWithTimeoutV1 termination confirmation (private, InModuleScope only)' {
 It 'preserves diagnostics and does not delete result paths when a timed-out child cannot be confirmed terminated' {
  Mock Stop-Process { throw 'access denied (simulated)' } -ModuleName TPMCertification.ProductionFacts
  $work=Join-Path $TestDrive ('term-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $work|Out-Null
  # A short sleep that will not finish inside a near-zero timeout, forcing the timeout path.
  $argumentList=@('-NoProfile','-Command','Start-Sleep -Seconds 5')
  $exe=(Get-Command pwsh -ErrorAction SilentlyContinue)
  if(-not $exe){ Set-ItResult -Skipped -Because 'pwsh not available'; return }
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{ExeSource=$exe.Source;ArgList=$argumentList;Work=$work} {
   Invoke-TPMExternalProcessWithTimeoutV1 -FilePath $ExeSource -ArgumentList $ArgList -TimeoutSeconds 1 -WorkingDirectoryRoot $Work -WorkingDirectory $Work
  }
  $result.TimedOut|Should -BeTrue
  if(-not $result.TerminationConfirmed){
   $result.StdOut|Should -BeNullOrEmpty
   $result.StdErr|Should -BeNullOrEmpty
  }
 }
 It 'reports Executed=false-equivalent (TimedOut with unconfirmed termination) when Stop-Job/Stop-Process cannot confirm the job actually stopped' {
  # Direct proof of the Start-Job bounded-execution equivalent: after
  # Stop-Job, the job's own State must genuinely no longer be Running
  # before cleanup is treated as successful.
  $result=InModuleScope TPMCertification.ProductionFacts {
   Invoke-TPMBoundedScriptBlockV1 -ScriptBlock {param($Seconds)Start-Sleep -Seconds $Seconds;'never reached'} -Parameters ([ordered]@{Seconds=5}) -TimeoutSeconds 1
  }
  $result.TimedOut|Should -BeTrue
  $result.Result|Should -BeNullOrEmpty
 }
}

Describe 'Test-TPMProductionPSScriptAnalyzerV1 (private, InModuleScope only)' {
 It 'aggregates real findings across every inventory file, never reusing a legacy count, and reports the version the job actually loaded' {
  $repo=New-InventoryFixture (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
  $inv=Get-TPMProductionPowerShellInventoryV1 -RepositoryPath $repo
  $settings=Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
  $expectedVersion=(Get-Module -ListAvailable PSScriptAnalyzer|Select-Object -First 1).Version.ToString()
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;Settings=$settings} {
   Test-TPMProductionPSScriptAnalyzerV1 -Inventory $Inv -SettingsPath $Settings
  }
  $result.Executed|Should -BeTrue
  $result.FindingCount|Should -Be 0
  $result.ToolVersion|Should -Be $expectedVersion
 }
 It 'reports Executed=false when the settings file is missing' {
  $repo=New-InventoryFixture (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
  $inv=Get-TPMProductionPowerShellInventoryV1 -RepositoryPath $repo
  $missing=Join-Path $TestDrive 'missing.psd1'
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;Missing=$missing} {
   Test-TPMProductionPSScriptAnalyzerV1 -Inventory $Inv -SettingsPath $Missing
  }
  $result.Executed|Should -BeFalse
  $result.Diagnostic.Stage|Should -Be 'PSSCRIPTANALYZER_SETTINGS_MISSING'
 }
 It 'fails closed when the bounded job cannot load PSScriptAnalyzer at all' {
  $repo=New-InventoryFixture (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
  $inv=Get-TPMProductionPowerShellInventoryV1 -RepositoryPath $repo
  $settings=Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
  Mock Invoke-TPMBoundedScriptBlockV1 { [ordered]@{TimedOut=$false;Result=@();HadErrors=$true;ErrorMessages=@('System.Exception: simulated job failure')} } -ModuleName TPMCertification.ProductionFacts
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;Settings=$settings} {
   Test-TPMProductionPSScriptAnalyzerV1 -Inventory $Inv -SettingsPath $Settings
  }
  $result.Executed|Should -BeFalse
  $result.Diagnostic.Stage|Should -Be 'PSSCRIPTANALYZER_JOB_EXECUTION_FAILED'
  $result.Diagnostic.Message|Should -Match 'simulated job failure'
 }
 It 'fails closed, WITH a populated Diagnostic (Item 3 audit fix), when the returned version is missing or malformed' {
  $repo=New-InventoryFixture (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
  $inv=Get-TPMProductionPowerShellInventoryV1 -RepositoryPath $repo
  $settings=Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
  Mock Invoke-TPMBoundedScriptBlockV1 { [ordered]@{TimedOut=$false;Result=@([pscustomobject]@{FindingCount=0;ToolVersion=$null;Path=$Parameters.Path});HadErrors=$false} } -ModuleName TPMCertification.ProductionFacts
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;Settings=$settings} {
   Test-TPMProductionPSScriptAnalyzerV1 -Inventory $Inv -SettingsPath $Settings
  }
  $result.Executed|Should -BeFalse
  $result.Diagnostic|Should -Not -BeNullOrEmpty -Because 'prior to the Item 3 audit fix this schema-mismatch path returned Diagnostic=$null, the exact defect class cb0dd97 closed for every OTHER failure path in this module'
  $result.Diagnostic.Stage|Should -Be 'PSSCRIPTANALYZER_TOOL_VERSION_MISSING'
 }
 It 'fails closed, WITH a populated Diagnostic, when different files report different analyzer versions' {
  $repo=New-InventoryFixture (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
  $inv=Get-TPMProductionPowerShellInventoryV1 -RepositoryPath $repo
  $settings=Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
  $script:callCount=0
  Mock Invoke-TPMBoundedScriptBlockV1 {
   $script:callCount++
   $version=if($script:callCount -eq 1){'1.0.0'}else{'2.0.0'}
   [ordered]@{TimedOut=$false;Result=@([pscustomobject]@{FindingCount=0;ToolVersion=$version;Path=$Parameters.Path});HadErrors=$false}
  } -ModuleName TPMCertification.ProductionFacts
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;Settings=$settings} {
   Test-TPMProductionPSScriptAnalyzerV1 -Inventory $Inv -SettingsPath $Settings
  }
  $result.Executed|Should -BeFalse
  $result.Diagnostic.Stage|Should -Be 'PSSCRIPTANALYZER_TOOL_VERSION_MISMATCH'
  $result.Diagnostic.Message|Should -Match '1\.0\.0'
  $result.Diagnostic.Message|Should -Match '2\.0\.0'
 }
 It 'fails closed, WITH a populated Diagnostic, when the job returns a malformed result record (extra/missing field)' {
  $repo=New-InventoryFixture (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
  $inv=Get-TPMProductionPowerShellInventoryV1 -RepositoryPath $repo
  $settings=Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
  Mock Invoke-TPMBoundedScriptBlockV1 { [ordered]@{TimedOut=$false;Result=@([pscustomobject]@{FindingCount=0;ToolVersion='1.0.0';Extra='unexpected'});HadErrors=$false} } -ModuleName TPMCertification.ProductionFacts
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;Settings=$settings} {
   Test-TPMProductionPSScriptAnalyzerV1 -Inventory $Inv -SettingsPath $Settings
  }
  $result.Executed|Should -BeFalse
  $result.Diagnostic.Stage|Should -Be 'PSSCRIPTANALYZER_RESULT_SCHEMA_INVALID'
 }
 It 'fails closed, WITH a populated Diagnostic, when the job returns zero or more than one result record for a single file' {
  $repo=New-InventoryFixture (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
  $inv=Get-TPMProductionPowerShellInventoryV1 -RepositoryPath $repo
  $settings=Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
  Mock Invoke-TPMBoundedScriptBlockV1 { [ordered]@{TimedOut=$false;Result=@([pscustomobject]@{FindingCount=0;ToolVersion='1.0.0'},[pscustomobject]@{FindingCount=0;ToolVersion='1.0.0'});HadErrors=$false} } -ModuleName TPMCertification.ProductionFacts
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;Settings=$settings} {
   Test-TPMProductionPSScriptAnalyzerV1 -Inventory $Inv -SettingsPath $Settings
  }
  $result.Executed|Should -BeFalse
  $result.Diagnostic.Stage|Should -Be 'PSSCRIPTANALYZER_RESULT_SHAPE_INVALID'
 }
 It 'fails closed, WITH a populated Diagnostic, when the job reports a mismatched Path' {
  $repo=New-InventoryFixture (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
  $inv=Get-TPMProductionPowerShellInventoryV1 -RepositoryPath $repo
  $settings=Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
  Mock Invoke-TPMBoundedScriptBlockV1 { [ordered]@{TimedOut=$false;Result=@([pscustomobject]@{FindingCount=0;ToolVersion='1.0.0';Path='C:\wrong\path.ps1'});HadErrors=$false} } -ModuleName TPMCertification.ProductionFacts
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;Settings=$settings} {
   Test-TPMProductionPSScriptAnalyzerV1 -Inventory $Inv -SettingsPath $Settings
  }
  $result.Executed|Should -BeFalse
  $result.Diagnostic.Stage|Should -Be 'PSSCRIPTANALYZER_RESULT_PATH_MISMATCH'
 }
 It 'no Diagnostic message ever contains a full raw ArgumentList/parameter value -- only stage/type/sanitized-message/counts, per the round-1 redaction discipline' {
  # Grep-level proof over the module source itself: every Diagnostic
  # Message built in this function is composed from stage tags, item
  # RelativePath, boolean flags, and counts -- never a raw $ArgumentList,
  # -Settings value, or full command line. This is deliberately a static
  # source check (not a live secret-planting test) because there is no
  # secret value flowing through this path to begin with; the guarantee
  # being tested is architectural (what CAN be interpolated into a
  # message), not behavioral.
  $moduleText=[IO.File]::ReadAllText((Join-Path $repoRoot 'scripts\TPMCertification.ProductionFacts.psm1'))
  $moduleText|Should -Not -Match '\$ArgumentList\b.*Message' -Because 'a raw ArgumentList must never be interpolated into a Diagnostic Message'
 }
 It 'the bounded-execution primitive genuinely times out a slow scriptblock (not mocked)' {
  $result=InModuleScope TPMCertification.ProductionFacts {
   Invoke-TPMBoundedScriptBlockV1 -ScriptBlock {param($Seconds)Start-Sleep -Seconds $Seconds;'never reached'} -Parameters ([ordered]@{Seconds=5}) -TimeoutSeconds 1
  }
  $result.TimedOut|Should -BeTrue
  $result.Result|Should -BeNullOrEmpty
 }
 It 'a Stop-Job failure during a genuine timeout is captured via Write-Warning rather than silently discarded (Item 3 audit fix)' {
  Mock Stop-Job { throw 'simulated Stop-Job failure' } -ModuleName TPMCertification.ProductionFacts
  $output=InModuleScope TPMCertification.ProductionFacts {
   Invoke-TPMBoundedScriptBlockV1 -ScriptBlock {param($Seconds)Start-Sleep -Seconds $Seconds;'never reached'} -Parameters ([ordered]@{Seconds=5}) -TimeoutSeconds 1
  } 3>&1
  $warnings=@($output|Where-Object{$_ -is [System.Management.Automation.WarningRecord]})
  $result=@($output|Where-Object{$_ -isnot [System.Management.Automation.WarningRecord]})[0]
  $result.TimedOut|Should -BeTrue -Because 'Stop-Job itself failing must not change the timeout outcome (the job-state recheck runs regardless)'
  $warningText=($warnings|ForEach-Object{$_.Message})-join '|'
  $warningText|Should -Match 'PRODUCTION_BOUNDED_JOB_STOP_FAILED' -Because 'prior to the Item 3 audit fix this catch was bare and discarded the reason Stop-Job failed'
  $warningText|Should -Match 'simulated Stop-Job failure'
 }
}

Describe 'Assert-TPMDispositionRegistryV1 (private, InModuleScope only)' {
 It 'accepts a well-formed registry' {
  $path=Join-Path $TestDrive 'good.psd1'
  [IO.File]::WriteAllText($path,"@{ SchemaVersion = 1; Dispositions = @( @{ File = 'a.ps1'; RuleName = 'R'; Line = 1; Extent = 'x'; Disposition = 'FalsePositive'; Reasoning = 'why' } ) }")
  InModuleScope TPMCertification.ProductionFacts -Parameters @{Path=$path} {
   { Assert-TPMDispositionRegistryV1 -Path $Path } | Should -Not -Throw
  }
 }
 It 'rejects an unsupported SchemaVersion' {
  $path=Join-Path $TestDrive 'badversion.psd1'
  [IO.File]::WriteAllText($path,"@{ SchemaVersion = 2; Dispositions = @() }")
  InModuleScope TPMCertification.ProductionFacts -Parameters @{Path=$path} {
   { Assert-TPMDispositionRegistryV1 -Path $Path } | Should -Throw '*SchemaVersion*'
  }
 }
 It 'rejects an unexpected top-level field (closed schema)' {
  $path=Join-Path $TestDrive 'extratop.psd1'
  [IO.File]::WriteAllText($path,"@{ SchemaVersion = 1; Dispositions = @(); Extra = 1 }")
  InModuleScope TPMCertification.ProductionFacts -Parameters @{Path=$path} {
   { Assert-TPMDispositionRegistryV1 -Path $Path } | Should -Throw '*unexpected top-level*'
  }
 }
 It 'rejects an entry missing the File field' {
  $path=Join-Path $TestDrive 'missingfile.psd1'
  [IO.File]::WriteAllText($path,"@{ SchemaVersion = 1; Dispositions = @( @{ RuleName = 'R'; Line = 1; Extent = 'x'; Disposition = 'FalsePositive'; Reasoning = 'why' } ) }")
  InModuleScope TPMCertification.ProductionFacts -Parameters @{Path=$path} {
   { Assert-TPMDispositionRegistryV1 -Path $Path } | Should -Throw '*unexpected fields*'
  }
 }
 It 'rejects a File value that is not a normalized repository-relative path' {
  $path=Join-Path $TestDrive 'badfile.psd1'
  [IO.File]::WriteAllText($path,"@{ SchemaVersion = 1; Dispositions = @( @{ File = 'C:\absolute.ps1'; RuleName = 'R'; Line = 1; Extent = 'x'; Disposition = 'FalsePositive'; Reasoning = 'why' } ) }")
  InModuleScope TPMCertification.ProductionFacts -Parameters @{Path=$path} {
   { Assert-TPMDispositionRegistryV1 -Path $Path } | Should -Throw '*File must be a normalized*'
  }
 }
 It 'rejects an unsupported Disposition value' {
  $path=Join-Path $TestDrive 'baddisposition.psd1'
  [IO.File]::WriteAllText($path,"@{ SchemaVersion = 1; Dispositions = @( @{ File = 'a.ps1'; RuleName = 'R'; Line = 1; Extent = 'x'; Disposition = 'Ignored'; Reasoning = 'why' } ) }")
  InModuleScope TPMCertification.ProductionFacts -Parameters @{Path=$path} {
   { Assert-TPMDispositionRegistryV1 -Path $Path } | Should -Throw '*Disposition*'
  }
 }
 It 'rejects a duplicate File/RuleName/Extent/Line entry' {
  $path=Join-Path $TestDrive 'dup.psd1'
  [IO.File]::WriteAllText($path,"@{ SchemaVersion = 1; Dispositions = @( @{ File = 'a.ps1'; RuleName = 'R'; Line = 1; Extent = 'x'; Disposition = 'FalsePositive'; Reasoning = 'why' }, @{ File = 'a.ps1'; RuleName = 'R'; Line = 1; Extent = 'x'; Disposition = 'FalsePositive'; Reasoning = 'again' } ) }")
  InModuleScope TPMCertification.ProductionFacts -Parameters @{Path=$path} {
   { Assert-TPMDispositionRegistryV1 -Path $Path } | Should -Throw '*duplicate*'
  }
 }
 It 'allows two entries with the same File/RuleName/Extent but different Line (legitimate repeated construct)' {
  $path=Join-Path $TestDrive 'samekey.psd1'
  [IO.File]::WriteAllText($path,"@{ SchemaVersion = 1; Dispositions = @( @{ File = 'a.ps1'; RuleName = 'R'; Line = 1; Extent = 'x'; Disposition = 'FalsePositive'; Reasoning = 'why' }, @{ File = 'a.ps1'; RuleName = 'R'; Line = 2; Extent = 'x'; Disposition = 'FalsePositive'; Reasoning = 'why again' } ) }")
  InModuleScope TPMCertification.ProductionFacts -Parameters @{Path=$path} {
   { Assert-TPMDispositionRegistryV1 -Path $Path } | Should -Not -Throw
  }
 }
}

Describe 'Test-TPMProductionInjectionHunterV1 (private, InModuleScope only)' {
 It 'executes and matches a real finding against a File+RuleName+Extent disposition registry entry, reporting the exact module version used' {
  $target=Join-Path $TestDrive 'target.ps1';[IO.File]::WriteAllText($target,'Add-Type -AssemblyName System.IO.Compression.FileSystem')
  $inv=@([ordered]@{RelativePath='target.ps1';FullPath=$target})
  $registryPath=Join-Path $TestDrive 'dispositions.psd1'
  [IO.File]::WriteAllText($registryPath,"@{ SchemaVersion = 1; Dispositions = @( @{ File = 'target.ps1'; RuleName = 'InjectionRisk.AddType'; Line = 1; Extent = 'Add-Type -AssemblyName System.IO.Compression.FileSystem'; Disposition = 'FalsePositive'; Reasoning = 'test' } ) }")
  $expectedVersion=(Get-Module -ListAvailable InjectionHunter|Select-Object -First 1).Version.ToString()
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;RegistryPath=$registryPath} {
   Test-TPMProductionInjectionHunterV1 -Inventory $Inv -DispositionRegistryPath $RegistryPath
  }
  $result.Executed|Should -BeTrue
  $result.FindingCount|Should -Be 1
  $result.UnresolvedFindingCount|Should -Be 0
  $result.Dispositions[0].FindingIdentifier|Should -Match '^target\.ps1::'
  $result.ToolVersion|Should -Be $expectedVersion
 }
 It 'does not cross-match an identical extent in a different file (File is part of the match key)' {
  # ADR155-0309 Checkpoint B2 fix: a finding with no matching registry key
  # at all (as opposed to a stale registry ENTRY with no matching finding)
  # must fall through to the safe 'Confirmed'/unresolved default, not crash
  # the whole gate to Executed=false -- confirmed by direct reproduction
  # that the prior "else{@()}" branch collapsed to $null when captured by
  # assignment (the same null-collapse LESSONS_LEARNED.md documents
  # elsewhere for "return @() vs return ,@()"), which happened to make this
  # test pass for the wrong reason (a crash, not a real non-cross-match
  # verification). Real cross-match prevention is that b.ps1's finding gets
  # its own unresolved 'Confirmed' disposition rather than inheriting a's
  # 'FalsePositive'.
  $targetA=Join-Path $TestDrive 'a.ps1';[IO.File]::WriteAllText($targetA,'Add-Type -AssemblyName System.Net.Http')
  $targetB=Join-Path $TestDrive 'b.ps1';[IO.File]::WriteAllText($targetB,'Add-Type -AssemblyName System.Net.Http')
  $inv=@([ordered]@{RelativePath='a.ps1';FullPath=$targetA},[ordered]@{RelativePath='b.ps1';FullPath=$targetB})
  $registryPath=Join-Path $TestDrive 'dispositions-onefile.psd1'
  [IO.File]::WriteAllText($registryPath,"@{ SchemaVersion = 1; Dispositions = @( @{ File = 'a.ps1'; RuleName = 'InjectionRisk.AddType'; Line = 1; Extent = 'Add-Type -AssemblyName System.Net.Http'; Disposition = 'FalsePositive'; Reasoning = 'a only' } ) }")
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;RegistryPath=$registryPath} {
   Test-TPMProductionInjectionHunterV1 -Inventory $Inv -DispositionRegistryPath $RegistryPath
  }
  $result.Executed|Should -BeTrue
  $result.FindingCount|Should -Be 2
  $result.UnresolvedFindingCount|Should -Be 1
  ($result.Dispositions|Where-Object{$_.FindingIdentifier-like'a.ps1::*'}).Disposition|Should -Be 'FalsePositive'
  ($result.Dispositions|Where-Object{$_.FindingIdentifier-like'b.ps1::*'}).Disposition|Should -Be 'Confirmed'
 }
 It 'gives each of two identical same-file occurrences its own registry entry, matched in line order' {
  $target=Join-Path $TestDrive 'dup-extent.ps1'
  [IO.File]::WriteAllText($target,"function A { Add-Type -AssemblyName System.Net.Http }`r`nfunction B { Add-Type -AssemblyName System.Net.Http }`r`n")
  $inv=@([ordered]@{RelativePath='dup-extent.ps1';FullPath=$target})
  $registryPath=Join-Path $TestDrive 'dispositions-dup.psd1'
  [IO.File]::WriteAllText($registryPath,"@{ SchemaVersion = 1; Dispositions = @( @{ File = 'dup-extent.ps1'; RuleName = 'InjectionRisk.AddType'; Line = 1; Extent = 'Add-Type -AssemblyName System.Net.Http'; Disposition = 'FalsePositive'; Reasoning = 'first' }, @{ File = 'dup-extent.ps1'; RuleName = 'InjectionRisk.AddType'; Line = 2; Extent = 'Add-Type -AssemblyName System.Net.Http'; Disposition = 'FalsePositive'; Reasoning = 'second' } ) }")
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;RegistryPath=$registryPath} {
   Test-TPMProductionInjectionHunterV1 -Inventory $Inv -DispositionRegistryPath $RegistryPath
  }
  $result.Executed|Should -BeTrue
  $result.FindingCount|Should -Be 2
  $result.UnresolvedFindingCount|Should -Be 0
 }
 It 'treats an unmatched finding as Confirmed/unresolved and fails closed on the resulting stale entry' {
  $target=Join-Path $TestDrive 'target2.ps1';[IO.File]::WriteAllText($target,'Add-Type -AssemblyName System.Net.Http')
  $inv=@([ordered]@{RelativePath='target2.ps1';FullPath=$target})
  $registryPath=Join-Path $TestDrive 'dispositions2.psd1'
  [IO.File]::WriteAllText($registryPath,"@{ SchemaVersion = 1; Dispositions = @( @{ File = 'target2.ps1'; RuleName = 'InjectionRisk.AddType'; Line = 99; Extent = 'Add-Type -AssemblyName System.IO.Compression.FileSystem'; Disposition = 'FalsePositive'; Reasoning = 'unrelated' } ) }")
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;RegistryPath=$registryPath} {
   Test-TPMProductionInjectionHunterV1 -Inventory $Inv -DispositionRegistryPath $RegistryPath
  }
  $result.Executed|Should -BeFalse
 }
 It 'reports Executed=false when the disposition registry file is missing' {
  $target=Join-Path $TestDrive 'target4.ps1';[IO.File]::WriteAllText($target,'1')
  $inv=@([ordered]@{RelativePath='target4.ps1';FullPath=$target})
  $missing=Join-Path $TestDrive 'missing.psd1'
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;Missing=$missing} {
   Test-TPMProductionInjectionHunterV1 -Inventory $Inv -DispositionRegistryPath $Missing
  }
  $result.Executed|Should -BeFalse
  $result.Diagnostic.Stage|Should -Be 'INJECTIONHUNTER_REGISTRY_MISSING'
 }
 It 'reports Executed=false when the InjectionHunter module cannot be found' {
  Mock Find-TPMInjectionHunterModuleV1 { $null } -ModuleName TPMCertification.ProductionFacts
  $target=Join-Path $TestDrive 'target5.ps1';[IO.File]::WriteAllText($target,'1')
  $inv=@([ordered]@{RelativePath='target5.ps1';FullPath=$target})
  $registryPath=Join-Path $TestDrive 'dispositions5.psd1'
  [IO.File]::WriteAllText($registryPath,"@{ SchemaVersion = 1; Dispositions = @() }")
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;RegistryPath=$registryPath} {
   Test-TPMProductionInjectionHunterV1 -Inventory $Inv -DispositionRegistryPath $RegistryPath
  }
  $result.Executed|Should -BeFalse
  $result.Diagnostic.Stage|Should -Be 'INJECTIONHUNTER_MODULE_NOT_FOUND'
 }
 It 'reports Executed=false with a diagnosable INJECTIONHUNTER_JOB_EXECUTION_FAILED stage, preserving the real underlying error text, when the resolved module manifest is corrupt' {
  # Narrow, test-only seam: Mock the module resolver to point at a
  # deliberately corrupt .psd1 (invalid PowerShell data-file syntax) so the
  # job's own Invoke-ScriptAnalyzer -CustomRulePath call genuinely fails --
  # this is not a production bypass, it exercises the real
  # Test-TPMProductionInjectionHunterV1 code path end to end (including the
  # real Start-Job boundary) with a real captured exception, the same way
  # round 2/3 injected real HResults rather than mocking exception objects.
  # Empirically confirmed by direct reproduction: Invoke-ScriptAnalyzer
  # itself rejects a corrupt -CustomRulePath manifest as an invalid "rule
  # extension" before this module's own Import-PowerShellDataFile read is
  # ever reached, so the job's error stream (not the manifest-read catch)
  # is where this specific corruption surfaces -- confirming the fix must
  # preserve the job's own ErrorMessages, not just the manifest-read catch.
  $corruptManifest=Join-Path $TestDrive 'CorruptInjectionHunter.psd1'
  [IO.File]::WriteAllText($corruptManifest,'@{ this is not valid PowerShell data file syntax @@@')
  Mock Find-TPMInjectionHunterModuleV1 { [pscustomobject]@{Path=$corruptManifest;Version=[version]'1.0.0'} } -ModuleName TPMCertification.ProductionFacts
  $target=Join-Path $TestDrive 'target6.ps1';[IO.File]::WriteAllText($target,'Add-Type -AssemblyName System.Net.Http')
  $inv=@([ordered]@{RelativePath='target6.ps1';FullPath=$target})
  $registryPath=Join-Path $TestDrive 'dispositions6.psd1'
  [IO.File]::WriteAllText($registryPath,"@{ SchemaVersion = 1; Dispositions = @() }")
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;RegistryPath=$registryPath} {
   Test-TPMProductionInjectionHunterV1 -Inventory $Inv -DispositionRegistryPath $RegistryPath
  }
  $result.Executed|Should -BeFalse
  $result.Diagnostic|Should -Not -BeNullOrEmpty
  $result.Diagnostic.Stage|Should -Be 'INJECTIONHUNTER_JOB_EXECUTION_FAILED'
  $result.Diagnostic.ExceptionType|Should -Not -BeNullOrEmpty
  $result.Diagnostic.Message|Should -Match 'jobErrors='
  $result.Diagnostic.Message|Should -Not -Match '^jobErrors=\(none captured\)$'
 }
 It 'reports Executed=false with a DISPOSITION_REGISTRY_INVALID diagnostic preserving the exception type when the registry file is malformed' {
  $target=Join-Path $TestDrive 'target7.ps1';[IO.File]::WriteAllText($target,'1')
  $inv=@([ordered]@{RelativePath='target7.ps1';FullPath=$target})
  $badRegistry=Join-Path $TestDrive 'bad-registry.psd1'
  [IO.File]::WriteAllText($badRegistry,"@{ SchemaVersion = 1; Dispositions = @( @{ File = 'target7.ps1' } ) }")
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;RegistryPath=$badRegistry} {
   Test-TPMProductionInjectionHunterV1 -Inventory $Inv -DispositionRegistryPath $RegistryPath
  }
  $result.Executed|Should -BeFalse
  $result.Diagnostic.Stage|Should -Be 'DISPOSITION_REGISTRY_INVALID'
  $result.Diagnostic.ExceptionType|Should -Not -BeNullOrEmpty
 }
}

Describe 'New-/Remove-TPMOwnedScratchDirectoryV1 (private, InModuleScope only)' {
 It 'creates and owns exactly one child, never touching pre-existing sibling content' {
  $parent=Join-Path $TestDrive ('parent-'+[guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $parent -Force|Out-Null
  [IO.File]::WriteAllText((Join-Path $parent 'sibling.txt'),'must survive')
  InModuleScope TPMCertification.ProductionFacts -Parameters @{Parent=$parent} {
   $owned=New-TPMOwnedScratchDirectoryV1 -ParentRoot $Parent
   Test-Path -LiteralPath $owned.Path -PathType Container|Should -BeTrue
   $removed=Remove-TPMOwnedScratchDirectoryV1 -Owned $owned
   $removed|Should -BeTrue
   Test-Path -LiteralPath $owned.Path|Should -BeFalse
   Test-Path -LiteralPath $Parent -PathType Container|Should -BeTrue
   Test-Path -LiteralPath (Join-Path $Parent 'sibling.txt')|Should -BeTrue
  }
 }
 It 'rejects a pre-existing child name (refuses to adopt existing content)' {
  $parent=Join-Path $TestDrive ('parent2-'+[guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path (Join-Path $parent 'taken') -Force|Out-Null
  InModuleScope TPMCertification.ProductionFacts -Parameters @{Parent=$parent} {
   { New-TPMOwnedScratchDirectoryV1 -ParentRoot $Parent -ChildName 'taken' } | Should -Throw '*SCRATCH_CHILD_ALREADY_EXISTS*'
  }
 }
 It 'rejects an outside-root child name' {
  $parent=Join-Path $TestDrive ('parent3-'+[guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $parent -Force|Out-Null
  InModuleScope TPMCertification.ProductionFacts -Parameters @{Parent=$parent} {
   { New-TPMOwnedScratchDirectoryV1 -ParentRoot $Parent -ChildName '../escaped' } | Should -Throw '*SCRATCH_CHILD_OUTSIDE_ROOT*'
  }
 }
 It 'refuses to recursively remove a path that no longer resolves inside the recorded parent' {
  $parent=Join-Path $TestDrive ('parent4-'+[guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $parent -Force|Out-Null
  $outside=Join-Path $TestDrive 'unrelated-outside-path'
  InModuleScope TPMCertification.ProductionFacts -Parameters @{Parent=$parent;Outside=$outside} {
   $owned=New-TPMOwnedScratchDirectoryV1 -ParentRoot $Parent
   $tampered=[pscustomobject]@{Path=$Outside;ParentRoot=$owned.ParentRoot;Owned=$true}
   New-Item -ItemType Directory -Path $tampered.Path -Force|Out-Null
   $result=Remove-TPMOwnedScratchDirectoryV1 -Owned $tampered
   $result|Should -BeFalse
   Test-Path -LiteralPath $tampered.Path|Should -BeTrue
  }
  Remove-Item -LiteralPath $outside -Recurse -Force -ErrorAction SilentlyContinue
 }
 It 'refuses to recursively remove a reparse point standing where the owned child should be' {
  $parent=Join-Path $TestDrive ('parent5-'+[guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $parent -Force|Out-Null
  $realTarget=Join-Path $TestDrive ('reparse-target-'+[guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $realTarget -Force|Out-Null
  [IO.File]::WriteAllText((Join-Path $realTarget 'must-survive.txt'),'x')
  $linkPath=Join-Path $parent 'owned-child'
  try{
   New-Item -ItemType SymbolicLink -Path $linkPath -Target $realTarget -ErrorAction Stop|Out-Null
  }catch{
   Set-ItResult -Skipped -Because 'symbolic link creation is not permitted in this environment'
   return
  }
  InModuleScope TPMCertification.ProductionFacts -Parameters @{LinkPath=$linkPath;Parent=$parent} {
   $owned=[pscustomobject]@{Path=$LinkPath;ParentRoot=([IO.Path]::GetFullPath($Parent).TrimEnd([IO.Path]::DirectorySeparatorChar));Owned=$true}
   $result=Remove-TPMOwnedScratchDirectoryV1 -Owned $owned
   $result|Should -BeFalse
  }
  Test-Path -LiteralPath (Join-Path $realTarget 'must-survive.txt')|Should -BeTrue
  Remove-Item -LiteralPath $linkPath -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $realTarget -Recurse -Force -ErrorAction SilentlyContinue
 }
}

Describe 'redirected-cleanup refusal via the real production path (Remove-TPMOwnedScratchDirectoryV1)' {
 # Item 1 (ADR155-0309 follow-up round): exercises the ACTUAL production
 # cleanup primitive -- Remove-TPMOwnedScratchDirectoryV1, invoked exactly
 # as Test-TPMProductionPackagePreflightV1 invokes it -- against a real
 # NTFS junction, never a reimplemented replica or a string-matching
 # assertion. Every scenario below runs the real function via InModuleScope
 # and proves the outcome through real filesystem state (Test-Path,
 # Get-FileHash, directory enumeration), not through mocking any part of
 # the function under test.
 It 'ordinary owned cleanup succeeds (control case)' {
  $parent=Join-Path $TestDrive ('ctrl-parent-'+[guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $parent -Force|Out-Null
  InModuleScope TPMCertification.ProductionFacts -Parameters @{Parent=$parent} {
   $owned=New-TPMOwnedScratchDirectoryV1 -ParentRoot $Parent
   [IO.File]::WriteAllText((Join-Path $owned.Path 'evidence.txt'),'x')
   $result=Remove-TPMOwnedScratchDirectoryV1 -Owned $owned
   $result|Should -BeTrue
   Test-Path -LiteralPath $owned.Path|Should -BeFalse
  }
 }
 It 'an already-missing owned leaf is idempotent (returns true, per the documented idempotency comment in Remove-TPMOwnedScratchDirectoryV1)' {
  $parent=Join-Path $TestDrive ('idem-parent-'+[guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $parent -Force|Out-Null
  InModuleScope TPMCertification.ProductionFacts -Parameters @{Parent=$parent} {
   $owned=New-TPMOwnedScratchDirectoryV1 -ParentRoot $Parent
   Remove-Item -LiteralPath $owned.Path -Recurse -Force
   Test-Path -LiteralPath $owned.Path|Should -BeFalse
   $result=Remove-TPMOwnedScratchDirectoryV1 -Owned $owned
   $result|Should -BeTrue -Because 'the function returns true for a target that is already gone rather than treating an already-missing leaf as a failure'
  }
 }
 It 'refuses a foreign/pre-existing directory this invocation never created (forged Owned descriptor, ownership-proof requirement)' {
  $parent=Join-Path $TestDrive ('forge-parent-'+[guid]::NewGuid().ToString('N'))
  $foreign=Join-Path $TestDrive ('forge-foreign-'+[guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $parent,$foreign -Force|Out-Null
  [IO.File]::WriteAllText((Join-Path $foreign 'must-survive.txt'),'foreign content')
  InModuleScope TPMCertification.ProductionFacts -Parameters @{Parent=$parent;Foreign=$foreign} {
   $forged=[pscustomobject]@{Path=$Foreign;ParentRoot=([IO.Path]::GetFullPath($Parent).TrimEnd([IO.Path]::DirectorySeparatorChar));Owned=$true}
   $result=Remove-TPMOwnedScratchDirectoryV1 -Owned $forged
   $result|Should -BeFalse -Because 'Foreign does not resolve inside Parent, so this must never be treated as an owned target'
  }
  Test-Path -LiteralPath (Join-Path $foreign 'must-survive.txt')|Should -BeTrue
  Remove-Item -LiteralPath $foreign -Recurse -Force -ErrorAction SilentlyContinue
 }

 Context 'junction-based redirection (requires junction creation to be permitted for this test account)' {
  It 'refuses when the owned child itself is a real junction, and the foreign target bytes are provably untouched' -Skip:(-not$script:tpmProductionFactsJunctionsSupported) {
   $parent=Join-Path $TestDrive ('leaf-junction-parent-'+[guid]::NewGuid().ToString('N'))
   New-Item -ItemType Directory -Path $parent -Force|Out-Null
   $foreign=Join-Path $TestDrive ('leaf-junction-foreign-'+[guid]::NewGuid().ToString('N'))
   New-Item -ItemType Directory -Path $foreign -Force|Out-Null
   $markerPath=Join-Path $foreign 'marker.bin'
   $markerBytes=[byte[]](1..64)
   [IO.File]::WriteAllBytes($markerPath,$markerBytes)
   [IO.File]::WriteAllBytes((Join-Path $foreign 'sibling-untouched.bin'),[byte[]](200..210))
   $beforeHash=(Get-FileHash -LiteralPath $markerPath -Algorithm SHA256).Hash
   $beforeChildNames=@(Get-ChildItem -LiteralPath $foreign -Force|Select-Object -ExpandProperty Name|Sort-Object)

   $owned=InModuleScope TPMCertification.ProductionFacts -Parameters @{Parent=$parent} {
    $owned=New-TPMOwnedScratchDirectoryV1 -ParentRoot $Parent
    Remove-Item -LiteralPath $owned.Path -Force -Recurse
    return $owned
   }
   New-TPMTestJunctionV1 -LinkPath $owned.Path -TargetPath $foreign

   InModuleScope TPMCertification.ProductionFacts -Parameters @{Owned=$owned} {
    $result=Remove-TPMOwnedScratchDirectoryV1 -Owned $Owned
    $result|Should -BeFalse -Because 'cleanup must revalidate the chain and refuse to recurse through a junction standing where the owned leaf should be'
   }

   $afterHash=(Get-FileHash -LiteralPath $markerPath -Algorithm SHA256).Hash
   $afterChildNames=@(Get-ChildItem -LiteralPath $foreign -Force|Select-Object -ExpandProperty Name|Sort-Object)
   $afterHash|Should -Be $beforeHash -Because 'the foreign marker file bytes must be byte-identical before and after the refused cleanup attempt'
   ($afterChildNames-join ',')|Should -Be ($beforeChildNames-join ',') -Because 'no file was added, removed, or renamed inside the foreign directory -- proving no traversal occurred through the junction'

   Remove-Item -LiteralPath $owned.Path -Force -ErrorAction SilentlyContinue
   Remove-Item -LiteralPath $foreign -Recurse -Force -ErrorAction SilentlyContinue
  }
  It 'refuses when the recorded ParentRoot itself is a real junction (root-level redirection)' -Skip:(-not$script:tpmProductionFactsJunctionsSupported) {
   $realParent=Join-Path $TestDrive ('root-junction-real-'+[guid]::NewGuid().ToString('N'))
   $linkParent=Join-Path $TestDrive ('root-junction-link-'+[guid]::NewGuid().ToString('N'))
   New-Item -ItemType Directory -Path $realParent -Force|Out-Null
   $foreign=Join-Path $TestDrive ('root-junction-foreign-'+[guid]::NewGuid().ToString('N'))
   New-Item -ItemType Directory -Path $foreign -Force|Out-Null
   $markerPath=Join-Path $foreign 'marker.bin'
   [IO.File]::WriteAllBytes($markerPath,[byte[]](5..40))
   $beforeHash=(Get-FileHash -LiteralPath $markerPath -Algorithm SHA256).Hash
   New-TPMTestJunctionV1 -LinkPath $linkParent -TargetPath $realParent
   $forgedLeaf=Join-Path $linkParent 'anything'
   New-Item -ItemType Directory -Path $forgedLeaf -Force|Out-Null

   InModuleScope TPMCertification.ProductionFacts -Parameters @{LinkParent=$linkParent;ForgedLeaf=$forgedLeaf} {
    $forged=[pscustomobject]@{Path=$ForgedLeaf;ParentRoot=([IO.Path]::GetFullPath($LinkParent).TrimEnd([IO.Path]::DirectorySeparatorChar));Owned=$true}
    $result=Remove-TPMOwnedScratchDirectoryV1 -Owned $forged
    $result|Should -BeFalse -Because 'a reparse-point ParentRoot must never be trusted as a real ownership anchor'
   }
   $afterHash=(Get-FileHash -LiteralPath $markerPath -Algorithm SHA256).Hash
   $afterHash|Should -Be $beforeHash
   Remove-Item -LiteralPath $linkParent -Force -ErrorAction SilentlyContinue
   Remove-Item -LiteralPath $realParent -Recurse -Force -ErrorAction SilentlyContinue
   Remove-Item -LiteralPath $foreign -Recurse -Force -ErrorAction SilentlyContinue
  }
  It 'refuses a Root-vs-Root-Evil sibling-prefix confusion attempt' -Skip:(-not$script:tpmProductionFactsJunctionsSupported) {
   $root=Join-Path $TestDrive ('sibling-root-'+[guid]::NewGuid().ToString('N'))
   $rootEvil=Join-Path $TestDrive ('sibling-root-Evil-'+[guid]::NewGuid().ToString('N'))
   New-Item -ItemType Directory -Path $root,$rootEvil -Force|Out-Null
   $evilChild=Join-Path $rootEvil 'child'
   New-Item -ItemType Directory -Path $evilChild -Force|Out-Null
   [IO.File]::WriteAllText((Join-Path $evilChild 'must-survive.txt'),'x')
   InModuleScope TPMCertification.ProductionFacts -Parameters @{Root=$root;EvilChild=$evilChild} {
    $forged=[pscustomobject]@{Path=$EvilChild;ParentRoot=([IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar));Owned=$true}
    $result=Remove-TPMOwnedScratchDirectoryV1 -Owned $forged
    $result|Should -BeFalse -Because 'Root-Evil must never be treated as being inside Root merely because it shares a text prefix'
   }
   Test-Path -LiteralPath (Join-Path $evilChild 'must-survive.txt')|Should -BeTrue
   Remove-Item -LiteralPath $root,$rootEvil -Recurse -Force -ErrorAction SilentlyContinue
  }
  It 'refuses when an intermediate component between ParentRoot and the leaf is a real junction (neither ParentRoot nor the leaf itself is the reparse point)' -Skip:(-not$script:tpmProductionFactsJunctionsSupported) {
   $parent=Join-Path $TestDrive ('mid-junction-parent-'+[guid]::NewGuid().ToString('N'))
   New-Item -ItemType Directory -Path $parent -Force|Out-Null
   $foreign=Join-Path $TestDrive ('mid-junction-foreign-'+[guid]::NewGuid().ToString('N'))
   $foreignLeaf=Join-Path $foreign 'leaf'
   New-Item -ItemType Directory -Path $foreignLeaf -Force|Out-Null
   $markerPath=Join-Path $foreignLeaf 'marker.bin'
   [IO.File]::WriteAllBytes($markerPath,[byte[]](70..99))
   $beforeHash=(Get-FileHash -LiteralPath $markerPath -Algorithm SHA256).Hash

   # Owned.Path is TWO levels below Owned.ParentRoot (ParentRoot\mid\leaf) so
   # the "mid" component is genuinely an intermediate link in the chain --
   # distinct from ParentRoot itself (root junction, covered above) and from
   # the final Path component (leaf junction, covered above).
   $midPath=Join-Path $parent 'mid'
   New-TPMTestJunctionV1 -LinkPath $midPath -TargetPath $foreign
   $forgedLeaf=Join-Path $midPath 'leaf'

   InModuleScope TPMCertification.ProductionFacts -Parameters @{Parent=$parent;ForgedLeaf=$forgedLeaf} {
    $forged=[pscustomobject]@{Path=$ForgedLeaf;ParentRoot=([IO.Path]::GetFullPath($Parent).TrimEnd([IO.Path]::DirectorySeparatorChar));Owned=$true}
    $result=Remove-TPMOwnedScratchDirectoryV1 -Owned $forged
    $result|Should -BeFalse -Because 'a reparse point anywhere in the chain between ParentRoot and the leaf must be rejected, not just at the two endpoints'
   }
   $afterHash=(Get-FileHash -LiteralPath $markerPath -Algorithm SHA256).Hash
   $afterHash|Should -Be $beforeHash -Because 'no traversal through the intermediate junction may reach the foreign leaf'
   Remove-Item -LiteralPath $midPath -Force -ErrorAction SilentlyContinue
   Remove-Item -LiteralPath $foreign -Recurse -Force -ErrorAction SilentlyContinue
   Remove-Item -LiteralPath $parent -Recurse -Force -ErrorAction SilentlyContinue
  }
  It 'cleanup after an uncertain child-process termination still refuses when the owned leaf was left redirected to foreign content' -Skip:(-not$script:tpmProductionFactsJunctionsSupported) {
   # Simulates the caller invoking cleanup after a child process that used
   # this scratch directory terminated without a confirmed clean exit
   # (crash, kill, timeout) -- Remove-TPMOwnedScratchDirectoryV1 has no
   # special-case for that history; it must revalidate the chain exactly
   # the same way regardless of *why* the leaf ended up redirected.
   $parent=Join-Path $TestDrive ('uncertain-child-parent-'+[guid]::NewGuid().ToString('N'))
   New-Item -ItemType Directory -Path $parent -Force|Out-Null
   $foreign=Join-Path $TestDrive ('uncertain-child-foreign-'+[guid]::NewGuid().ToString('N'))
   New-Item -ItemType Directory -Path $foreign -Force|Out-Null
   $markerPath=Join-Path $foreign 'marker.bin'
   [IO.File]::WriteAllBytes($markerPath,[byte[]](110..140))
   $beforeHash=(Get-FileHash -LiteralPath $markerPath -Algorithm SHA256).Hash

   $owned=InModuleScope TPMCertification.ProductionFacts -Parameters @{Parent=$parent} {
    $owned=New-TPMOwnedScratchDirectoryV1 -ParentRoot $Parent
    # A lingering marker simulating an in-progress child process whose
    # termination was never confirmed (crash/kill/timeout), left behind in
    # the owned directory before it was (by whatever means) replaced with a
    # junction.
    [IO.File]::WriteAllText((Join-Path $owned.Path 'child-uncertain.lock'),'uncertain-termination')
    Remove-Item -LiteralPath $owned.Path -Force -Recurse
    return $owned
   }
   New-TPMTestJunctionV1 -LinkPath $owned.Path -TargetPath $foreign

   InModuleScope TPMCertification.ProductionFacts -Parameters @{Owned=$owned} {
    $result=Remove-TPMOwnedScratchDirectoryV1 -Owned $Owned
    $result|Should -BeFalse -Because 'an uncertain child termination must never relax the reparse-point revalidation cleanup always performs'
   }
   $afterHash=(Get-FileHash -LiteralPath $markerPath -Algorithm SHA256).Hash
   $afterHash|Should -Be $beforeHash -Because 'foreign content must remain byte-identical even when cleanup follows an unclear child-process outcome'
   Remove-Item -LiteralPath $owned.Path -Force -ErrorAction SilentlyContinue
   Remove-Item -LiteralPath $foreign -Recurse -Force -ErrorAction SilentlyContinue
  }
 }
}

Describe 'Test-TPMProductionPackagePreflightV1 (private, InModuleScope only)' {
 It 'genuinely invokes the real report/publication pipeline, confirms canonical filenames, and cleans up its own owned scratch child only' {
  $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
  $staging=Join-Path $root 'staging';$destination=Join-Path $root 'destination';$scratch=Join-Path $root 'scratch'
  New-Item -ItemType Directory -Path $scratch -Force|Out-Null
  [IO.File]::WriteAllText((Join-Path $scratch 'pre-existing.txt'),'must survive')
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Staging=$staging;Destination=$destination;Scratch=$scratch} {
   Test-TPMProductionPackagePreflightV1 -StagingParentRoot $Staging -DestinationRoot $Destination -PreflightScratchRoot $Scratch
  }
  $result.StagingDirectoryReady|Should -BeTrue
  $result.PublisherAvailable|Should -BeTrue
  $result.PackageValidationExecuted|Should -BeTrue
  $result.PackageValidationPassed|Should -BeTrue
  $result.PackageValidationErrorCount|Should -Be 0
  Test-Path -LiteralPath $scratch -PathType Container|Should -BeTrue
  Test-Path -LiteralPath (Join-Path $scratch 'pre-existing.txt')|Should -BeTrue
  @(Get-ChildItem -LiteralPath $scratch -Force).Count|Should -Be 1
 }
 It 'fails closed when a required publication command is genuinely broken, not merely absent from Get-Command' {
  Mock New-TPMEligibilityReportV1 { throw 'synthetic preflight failure' } -ModuleName TPMCertification.ProductionFacts
  $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
  $staging=Join-Path $root 'staging';$destination=Join-Path $root 'destination';$scratch=Join-Path $root 'scratch'
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Staging=$staging;Destination=$destination;Scratch=$scratch} {
   Test-TPMProductionPackagePreflightV1 -StagingParentRoot $Staging -DestinationRoot $Destination -PreflightScratchRoot $Scratch
  }
  $result.PublisherAvailable|Should -BeFalse
  $result.PackageValidationPassed|Should -BeFalse
  $result.PackageValidationErrorCount|Should -BeGreaterThan 0
 }
 It 'reports staging not ready and a positive error count when the staging root cannot be created' {
  $blocker=Join-Path $TestDrive ('blocker-'+[guid]::NewGuid().ToString('N'))
  [IO.File]::WriteAllText($blocker,'file, not a directory')
  $staging=Join-Path $blocker 'staging'
  $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
  $destination=Join-Path $root 'destination';$scratch=Join-Path $root 'scratch'
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Staging=$staging;Destination=$destination;Scratch=$scratch} {
   Test-TPMProductionPackagePreflightV1 -StagingParentRoot $Staging -DestinationRoot $Destination -PreflightScratchRoot $Scratch
  }
  $result.StagingDirectoryReady|Should -BeFalse
  $result.PackageValidationPassed|Should -BeFalse
  $result.PackageValidationErrorCount|Should -BeGreaterThan 0
 }
 It 'never reports PackageValidationPassed=true when scratch-child cleanup fails' {
  Mock Remove-TPMOwnedScratchDirectoryV1 { $false } -ModuleName TPMCertification.ProductionFacts
  $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
  $staging=Join-Path $root 'staging';$destination=Join-Path $root 'destination';$scratch=Join-Path $root 'scratch'
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Staging=$staging;Destination=$destination;Scratch=$scratch} {
   Test-TPMProductionPackagePreflightV1 -StagingParentRoot $Staging -DestinationRoot $Destination -PreflightScratchRoot $Scratch
  }
  $result.PackageValidationPassed|Should -BeFalse
  $result.PackageValidationErrorCount|Should -BeGreaterThan 0
 }
}

Describe 'Get-TPMProductionPowerShellInventoryV1 self-scan (the complete real inventory, not just new files)' {
 It 'is entirely ASCII-clean and parses under both engines' {
  $inv=Get-TPMProductionPowerShellInventoryV1 -RepositoryPath $repoRoot
  foreach($item in $inv){
   $bytes=[IO.File]::ReadAllBytes($item.FullPath)
   (@($bytes)|Where-Object{$_-gt127}).Count|Should -Be 0 -Because "$($item.RelativePath) must be pure ASCII"
   $parseErrors=$null;$tokens=$null
   [System.Management.Automation.Language.Parser]::ParseFile($item.FullPath,[ref]$tokens,[ref]$parseErrors)|Out-Null
   $parseErrors.Count|Should -Be 0 -Because "$($item.RelativePath) must parse cleanly"
  }
 }
 It 'is analyzed in full by both PSScriptAnalyzer and InjectionHunter fact-adapter gates (not merely the newly authored files), with zero PSScriptAnalyzer findings' {
  $inv=Get-TPMProductionPowerShellInventoryV1 -RepositoryPath $repoRoot
  $settings=Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
  $registryPath=Join-Path $repoRoot 'scripts/InjectionHunterDispositions.psd1'
  $result=InModuleScope TPMCertification.ProductionFacts -Parameters @{Inv=$inv;Settings=$settings;RegistryPath=$registryPath} {
   [ordered]@{
    Pssa=(Test-TPMProductionPSScriptAnalyzerV1 -Inventory $Inv -SettingsPath $Settings)
    Ih=(Test-TPMProductionInjectionHunterV1 -Inventory $Inv -DispositionRegistryPath $RegistryPath)
   }
  }
  $result.Pssa.Executed|Should -BeTrue
  $result.Pssa.FindingCount|Should -Be 0
  $result.Ih.Executed|Should -BeTrue
  $result.Ih.UnresolvedFindingCount|Should -Be 0
  $result.Ih.FindingCount|Should -BeGreaterThan 0
 }
}

Describe 'New-TPMProductionFactRecordsV1' {
 It 'emits all eleven fact identifiers, validates through the real dispatcher, and never reuses the legacy PSScriptAnalyzer count' {
  $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
  $repo=New-InventoryFixture $root
  $report=Join-Path $root 'report';$backup=Join-Path $root 'backup'
  $fixture=New-LegacyResultsFixture $repo $report $backup
  $work=Join-Path $root 'work';$staging=Join-Path $root 'staging';$destination=Join-Path $root 'destination'

  $emptyRegistry=Join-Path $root 'empty-dispositions.psd1'
  [IO.File]::WriteAllText($emptyRegistry,'@{ SchemaVersion = 1; Dispositions = @() }')
  $realSettingsPath=Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'

  $fixture.Health.Checks+=,[pscustomobject]@{Name='Optional informational check';Passed=$true}
  $facts=@(New-TPMProductionFactRecordsV1 -Results $fixture.Results -RepositoryPath $repo -ReportDirectory $report -BackupDirectory $backup -HealthResult $fixture.Health -StagingParentRoot $staging -DestinationRoot $destination -WorkingDirectoryRoot $root -WorkingDirectory $work -DispositionRegistryPath $emptyRegistry -PSScriptAnalyzerSettingsPath $realSettingsPath)

  $facts.Count|Should -Be 11
  @($facts.Identifier)|Should -Be @('Repository','Pester','Static Analysis','Real Install Health','Backups','Smoke File Safety','Artifacts','pcsx2x6 crosshair path (issue #79)','Behavioral Certification (Virtual Beta Tester)','Unattended TPM root binding','Unattended TPM config restoration')

  $staticAnalysis=($facts|Where-Object{$_.Identifier -eq 'Static Analysis'}).Data
  $staticAnalysis.PSScriptAnalyzer.FindingCount|Should -Be 0
  $staticAnalysis.PSScriptAnalyzer.FindingCount|Should -Not -Be 999
  $staticAnalysis.Encoding.Files.Count|Should -Be 19
  $staticAnalysis.InjectionHunter.Executed|Should -BeTrue

  $artifacts=($facts|Where-Object{$_.Identifier -eq 'Artifacts'}).Data
  $artifacts.PublisherAvailable|Should -BeTrue
  $artifacts.PackageValidationPassed|Should -BeTrue

  $health=($facts|Where-Object Identifier -eq 'Real Install Health').Data
  @($health.Checks).Count|Should -Be 3
  @($health.Checks.Name)|Should -Not -Contain 'Optional informational check'

  $mode='Smoke'
  foreach($fact in $facts){ { Assert-TPMFactRecordV1 $fact $mode $report } | Should -Not -Throw }
 }

 It 'fails closed via Assert-TPMDiagnosticRecordV1 when a tool reports Executed=false with a malformed Diagnostic (Item 3 audit: schema validation)' {
  $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
  $repo=New-InventoryFixture $root
  $report=Join-Path $root 'report';$backup=Join-Path $root 'backup'
  $fixture=New-LegacyResultsFixture $repo $report $backup
  $work=Join-Path $root 'work';$staging=Join-Path $root 'staging';$destination=Join-Path $root 'destination'
  $emptyRegistry=Join-Path $root 'empty-dispositions.psd1'
  [IO.File]::WriteAllText($emptyRegistry,'@{ SchemaVersion = 1; Dispositions = @() }')
  $settings=Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
  # A malformed Diagnostic (missing the required Message field) must never
  # silently flow through into the authoritative fact record -- prior to
  # the Item 3 audit fix, nothing validated this shape at all.
  Mock Test-TPMProductionPSScriptAnalyzerV1 { [ordered]@{Executed=$false;FindingCount=0;ToolVersion=$null;Diagnostic=[ordered]@{Stage='SIMULATED';ExceptionType=$null}} } -ModuleName TPMCertification.ProductionFacts
  $caught=$null
  try {
   New-TPMProductionFactRecordsV1 -Results $fixture.Results -RepositoryPath $repo -ReportDirectory $report -BackupDirectory $backup -HealthResult $fixture.Health -StagingParentRoot $staging -DestinationRoot $destination -WorkingDirectoryRoot $root -WorkingDirectory $work -DispositionRegistryPath $emptyRegistry -PSScriptAnalyzerSettingsPath $settings
  } catch { $caught=$_ }
  $caught|Should -Not -BeNullOrEmpty
  $caught.Exception.Message|Should -Match '^SCHEMA_INVALID: PSScriptAnalyzer\.Diagnostic'
 }
 It 'fails closed via Assert-TPMDiagnosticRecordV1 when Executed=false and Diagnostic is entirely missing' {
  $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
  $repo=New-InventoryFixture $root
  $report=Join-Path $root 'report';$backup=Join-Path $root 'backup'
  $fixture=New-LegacyResultsFixture $repo $report $backup
  $work=Join-Path $root 'work';$staging=Join-Path $root 'staging';$destination=Join-Path $root 'destination'
  $emptyRegistry=Join-Path $root 'empty-dispositions.psd1'
  [IO.File]::WriteAllText($emptyRegistry,'@{ SchemaVersion = 1; Dispositions = @() }')
  $settings=Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
  Mock Test-TPMProductionInjectionHunterV1 { [ordered]@{Executed=$false;FindingCount=0;UnresolvedFindingCount=0;ToolVersion=$null;Dispositions=@();Diagnostic=$null} } -ModuleName TPMCertification.ProductionFacts
  $caught=$null
  try {
   New-TPMProductionFactRecordsV1 -Results $fixture.Results -RepositoryPath $repo -ReportDirectory $report -BackupDirectory $backup -HealthResult $fixture.Health -StagingParentRoot $staging -DestinationRoot $destination -WorkingDirectoryRoot $root -WorkingDirectory $work -DispositionRegistryPath $emptyRegistry -PSScriptAnalyzerSettingsPath $settings
  } catch { $caught=$_ }
  $caught|Should -Not -BeNullOrEmpty
  $caught.Exception.Message|Should -Match '^SCHEMA_INVALID: InjectionHunter\.Diagnostic'
 }
 It 'rejects every malformed outer and inner health shape with a deliberate schema diagnostic, never PropertyNotFoundException' {
  $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
  $repo=New-InventoryFixture $root
  $report=Join-Path $root 'report';$backup=Join-Path $root 'backup'
  $fixture=New-LegacyResultsFixture $repo $report $backup
  $work=Join-Path $root 'work';$staging=Join-Path $root 'staging';$destination=Join-Path $root 'destination'
  $emptyRegistry=Join-Path $root 'empty-dispositions.psd1'
  [IO.File]::WriteAllText($emptyRegistry,'@{ SchemaVersion = 1; Dispositions = @() }')
  $settings=Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
  $common=@{
   Results=$fixture.Results;RepositoryPath=$repo;ReportDirectory=$report;BackupDirectory=$backup
   StagingParentRoot=$staging;DestinationRoot=$destination;WorkingDirectoryRoot=$root;WorkingDirectory=$work
   DispositionRegistryPath=$emptyRegistry;PSScriptAnalyzerSettingsPath=$settings
  }
  $required=@(
   [pscustomobject]@{Name='TeknoParrotUi.exe exists';Passed=$true}
   [pscustomobject]@{Name='GameProfiles folder exists';Passed=$true}
   [pscustomobject]@{Name='UserProfiles folder exists';Passed=$true}
  )
  $nested=[object[]]@([pscustomobject]@{Name='Nested';Passed=$true})
  $invalid=@(
   @{Value=$null;Message='HealthResult is null'}
   @{Value='not-an-object';Message='must be a PSCustomObject'}
   @{Value=@([pscustomobject]@{Checks=@()});Message='must be a PSCustomObject'}
   @{Value=[pscustomobject]@{Status='Passed'};Message='HealthResult.Checks is missing'}
   @{Value=[pscustomobject]@{Checks=$null};Message='HealthResult.Checks is null'}
   @{Value=[pscustomobject]@{Checks='not-a-collection'};Message='Checks must be a non-empty collection'}
   @{Value=[pscustomobject]@{Checks=[object[]]@()};Message='Checks must not be empty'}
   @{Value=[pscustomobject]@{Checks=[object[]]@($null)};Message='Checks[0] is null'}
   @{Value=[pscustomobject]@{Checks=[object[]]@('scalar')};Message='Checks[0] must be a PSCustomObject'}
   @{Value=[pscustomobject]@{Checks=[object[]]@(,$nested)};Message='Checks[0] must be a PSCustomObject'}
   @{Value=[pscustomobject]@{Checks=[object[]]@([pscustomobject]@{Passed=$true})};Message='Checks[0].Name is missing'}
   @{Value=[pscustomobject]@{Checks=[object[]]@([pscustomobject]@{Name=$null;Passed=$true})};Message='Checks[0].Name must be a nonblank string'}
   @{Value=[pscustomobject]@{Checks=[object[]]@([pscustomobject]@{Name=' ';Passed=$true})};Message='Checks[0].Name must be a nonblank string'}
   @{Value=[pscustomobject]@{Checks=[object[]]@([pscustomobject]@{Name=42;Passed=$true})};Message='Checks[0].Name must be a nonblank string'}
   @{Value=[pscustomobject]@{Checks=[object[]]@([pscustomobject]@{Name='TeknoParrotUi.exe exists'})};Message='Checks[0].Passed is missing'}
   @{Value=[pscustomobject]@{Checks=[object[]]@([pscustomobject]@{Name='TeknoParrotUi.exe exists';Passed=$null})};Message='Checks[0].Passed must be Boolean'}
   @{Value=[pscustomobject]@{Checks=[object[]]@([pscustomobject]@{Name='TeknoParrotUi.exe exists';Passed='true'})};Message='Checks[0].Passed must be Boolean'}
   @{Value=[pscustomobject]@{Checks=[object[]]@([pscustomobject]@{Name='TeknoParrotUi.exe exists';Passed=1})};Message='Checks[0].Passed must be Boolean'}
   @{Value=[pscustomobject]@{Checks=[object[]]@($required[0],$required[0],$required[1],$required[2])};Message="required health check 'TeknoParrotUi.exe exists' is duplicated"}
  )
  foreach($case in $invalid){
   $caught=$null
   try { New-TPMProductionFactRecordsV1 @common -HealthResult $case.Value } catch { $caught=$_ }
   $caught|Should -Not -BeNullOrEmpty
   $caught.Exception.Message|Should -Match '^PRODUCTION_HEALTH_RESULT_SCHEMA_INVALID:'
   $caught.Exception.Message|Should -Match ([regex]::Escape($case.Message))
   $caught.Exception.Message|Should -Not -Match 'property .* cannot be found'
   $caught.FullyQualifiedErrorId|Should -Not -Match 'PropertyNotFound'
   $caught.Exception.GetType().FullName|Should -Be 'System.Management.Automation.RuntimeException'
  }
 }

 It 'rejects a structurally valid collection that omits a required check' {
  $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
  $repo=New-InventoryFixture $root;$report=Join-Path $root 'report';$backup=Join-Path $root 'backup'
  $fixture=New-LegacyResultsFixture $repo $report $backup
  $fixture.Health.Checks=@($fixture.Health.Checks|Where-Object Name -ne 'UserProfiles folder exists')
  $caught=$null
  try { New-TPMProductionFactRecordsV1 -Results $fixture.Results -RepositoryPath $repo -ReportDirectory $report -BackupDirectory $backup -HealthResult $fixture.Health -StagingParentRoot (Join-Path $root 'staging') -DestinationRoot (Join-Path $root 'destination') -WorkingDirectoryRoot $root -WorkingDirectory (Join-Path $root 'work') } catch { $caught=$_ }
  $caught.Exception.Message|Should -Be "PRODUCTION_HEALTH_RESULT_SCHEMA_INVALID: required health check 'UserProfiles folder exists' is missing"
 }

 It 'preserves explicit Missing and InvalidJson health load states as valid fail-closed facts' {
  foreach($state in @('Missing','InvalidJson')){
   $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
   $repo=New-InventoryFixture $root
   $report=Join-Path $root 'report';$backup=Join-Path $root 'backup'
   $fixture=New-LegacyResultsFixture $repo $report $backup
   if($state-ceq'Missing'){Remove-Item -LiteralPath (Join-Path $report 'InstallHealth\InstallHealth.json')}
   $work=Join-Path $root 'work';$staging=Join-Path $root 'staging';$destination=Join-Path $root 'destination'
   $emptyRegistry=Join-Path $root 'empty-dispositions.psd1'
   [IO.File]::WriteAllText($emptyRegistry,'@{ SchemaVersion = 1; Dispositions = @() }')
   $facts=@(New-TPMProductionFactRecordsV1 -Results $fixture.Results -RepositoryPath $repo -ReportDirectory $report -BackupDirectory $backup -HealthResult $null -HealthLoadError 'explicit load failure' -StagingParentRoot $staging -DestinationRoot $destination -WorkingDirectoryRoot $root -WorkingDirectory $work -DispositionRegistryPath $emptyRegistry -PSScriptAnalyzerSettingsPath (Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'))
   $health=($facts|Where-Object Identifier -eq 'Real Install Health').Data
   $health.LoadState|Should -Be $state
   $health.LoadError|Should -Be 'explicit load failure'
   @($health.Checks).Count|Should -Be 0
   { Assert-TPMFactRecordV1 ($facts|Where-Object Identifier -eq 'Real Install Health') 'Smoke' $report }|Should -Not -Throw
  }
 }
}
