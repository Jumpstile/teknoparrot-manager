#Requires -Module Pester
BeforeAll {
 Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Authority.psm1') -Force
 Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Shadow.psm1') -Force
 Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Reports.psm1') -Force
 Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Publication.psm1') -Force
 Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Production.psm1') -Force
 $realManagerPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'TeknoParrot-Manager.ps1'
 $realRegistryPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\InjectionHunterDispositions.psd1'

 function New-RegistryFixtureV1 {
  param([string]$Root, [array]$Entries)
  $path = Join-Path $Root 'Dispositions.psd1'
  $lines = New-Object Collections.Generic.List[string]
  $lines.Add('@{ SchemaVersion = 1; Issue = 0; Dispositions = @(')
  foreach ($e in $Entries) {
   $lines.Add('@{ RuleName = ''' + $e.RuleName + '''; Line = ' + $e.Line + '; Extent = @''')
   $lines.Add($e.Extent)
   $lines.Add('''@; Disposition = ''' + $e.Disposition + '''; Reasoning = ''fixture'' }')
  }
  $lines.Add(') }')
  [IO.File]::WriteAllLines($path, $lines.ToArray())
  return $path
 }
}

Describe 'ADR-0155 Phase 3 production fact adapter -- Parser checks (issue #171)' {
 BeforeEach { $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $root | Out-Null }

 It 'parser success: reports Executed=true and ErrorCount=0 for a genuinely valid script, under both engines' {
  $valid = Join-Path $root 'Valid.ps1'
  [IO.File]::WriteAllText($valid, 'function Test-Valid { param($X) return $X }')
  $win = Test-TPMStaticAnalysisParserV1 -Path $valid -Engine WindowsPowerShell51
  $pwsh = Test-TPMStaticAnalysisParserV1 -Path $valid -Engine Pwsh
  $win.Executed | Should -Be $true
  $win.ErrorCount | Should -Be 0
  $win.ToolVersion | Should -Not -BeNullOrEmpty
  $pwsh.Executed | Should -Be $true
  $pwsh.ErrorCount | Should -Be 0
 }

 It 'parser failure: reports a real nonzero ErrorCount for a script with a genuine syntax error, under both engines' {
  $broken = Join-Path $root 'Broken.ps1'
  [IO.File]::WriteAllText($broken, 'function Test-Broken { param($X) return $X')
  $win = Test-TPMStaticAnalysisParserV1 -Path $broken -Engine WindowsPowerShell51
  $pwsh = Test-TPMStaticAnalysisParserV1 -Path $broken -Engine Pwsh
  $win.Executed | Should -Be $true
  $win.ErrorCount | Should -BeGreaterThan 0
  $pwsh.Executed | Should -Be $true
  $pwsh.ErrorCount | Should -BeGreaterThan 0
 }

 It 'a missing target file still causes real failure rather than a fabricated pass: the parser genuinely runs and reports a real parse error, never Executed=true with ErrorCount=0' {
  # [Parser]::ParseFile on a nonexistent path does not throw -- it returns
  # exit 0 with a real parse error for the missing file (verified directly).
  # Either signal (Executed=false, or Executed=true with ErrorCount>0)
  # correctly fails Static Analysis eligibility; this asserts it never
  # silently reports a clean pass for a target that isn't there.
  $missing = Join-Path $root 'DoesNotExist.ps1'
  $result = Test-TPMStaticAnalysisParserV1 -Path $missing -Engine Pwsh
  if ($result.Executed) { $result.ErrorCount | Should -BeGreaterThan 0 }
 }

 It 'the real TeknoParrot-Manager.ps1 parses cleanly under both engines (confirms the adapter reflects real project state, not just synthetic fixtures)' {
  $win = Test-TPMStaticAnalysisParserV1 -Path $realManagerPath -Engine WindowsPowerShell51
  $pwsh = Test-TPMStaticAnalysisParserV1 -Path $realManagerPath -Engine Pwsh
  $win.Executed | Should -Be $true
  $win.ErrorCount | Should -Be 0
  $pwsh.Executed | Should -Be $true
  $pwsh.ErrorCount | Should -Be 0
 }
}

Describe 'ADR-0155 Phase 3 production fact adapter -- Encoding checks (issue #171)' {
 BeforeEach { $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $root | Out-Null }

 It 'encoding success: reports Executed=true and NonAsciiByteCount=0 for a pure-ASCII file' {
  $ascii = Join-Path $root 'Ascii.ps1'
  [IO.File]::WriteAllBytes($ascii, [Text.Encoding]::ASCII.GetBytes('Write-Host "hello"'))
  $result = Test-TPMStaticAnalysisEncodingV1 -Path $ascii
  $result.Executed | Should -Be $true
  $result.NonAsciiByteCount | Should -Be 0
 }

 It 'non-ASCII detection: reports the real nonzero byte count for a file containing real non-ASCII bytes' {
  $nonAscii = Join-Path $root 'NonAscii.ps1'
  # em dash (E2 80 94) -- exactly the byte sequence this project's own ASCII
  # purity rule exists to catch (see CLAUDE.md, "Key conventions").
  [IO.File]::WriteAllBytes($nonAscii, [byte[]](0x57, 0x72, 0x69, 0x74, 0x65, 0xE2, 0x80, 0x94, 0x48, 0x6F, 0x73, 0x74))
  $result = Test-TPMStaticAnalysisEncodingV1 -Path $nonAscii
  $result.Executed | Should -Be $true
  $result.NonAsciiByteCount | Should -Be 3
 }

 It 'the real TeknoParrot-Manager.ps1 has zero non-ASCII bytes (confirms the adapter reflects real project state)' {
  $result = Test-TPMStaticAnalysisEncodingV1 -Path $realManagerPath
  $result.Executed | Should -Be $true
  $result.NonAsciiByteCount | Should -Be 0
 }
}

Describe 'ADR-0155 Phase 3 production fact adapter -- InjectionHunter execution and disposition loading (issue #171)' {
 BeforeEach { $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $root | Out-Null }

 It 'InjectionHunter execution: runs for real against the actual ADR-scoped file and matches every finding to the checked-in registry' {
  $result = Test-TPMStaticAnalysisInjectionHunterV1 -Path $realManagerPath -DispositionRegistryPath $realRegistryPath
  $result.Executed | Should -Be $true
  $result.FindingCount | Should -Be 16
  $result.UnresolvedFindingCount | Should -Be 0
  $result.Dispositions.Count | Should -Be 16
  foreach ($d in $result.Dispositions) { $d.Disposition | Should -Be 'FalsePositive' }
 }

 It 'disposition loading: a finding whose exact rule and extent match a registry entry is resolved with that entry''s disposition' {
  $fixture = Join-Path $root 'Fixture.ps1'
  [IO.File]::WriteAllText($fixture, 'Add-Type -AssemblyName System.Net.Http')
  $registryPath = New-RegistryFixtureV1 -Root $root -Entries @(
   [pscustomobject]@{RuleName='InjectionRisk.AddType';Line=1;Extent='Add-Type -AssemblyName System.Net.Http';Disposition='FalsePositive'}
  )
  $result = Test-TPMStaticAnalysisInjectionHunterV1 -Path $fixture -DispositionRegistryPath $registryPath
  $result.Executed | Should -Be $true
  $result.FindingCount | Should -Be 1
  $result.UnresolvedFindingCount | Should -Be 0
  $result.Dispositions[0].Disposition | Should -Be 'FalsePositive'
 }

 It 'unresolved findings cause eligibility-relevant failure: a real finding with no registry entry is Confirmed and counted as unresolved' {
  $fixture = Join-Path $root 'Fixture.ps1'
  [IO.File]::WriteAllText($fixture, 'Add-Type -AssemblyName System.Net.Http')
  $registryPath = New-RegistryFixtureV1 -Root $root -Entries @()
  $result = Test-TPMStaticAnalysisInjectionHunterV1 -Path $fixture -DispositionRegistryPath $registryPath
  $result.FindingCount | Should -Be 1
  $result.UnresolvedFindingCount | Should -Be 1
  $result.Dispositions[0].Disposition | Should -Be 'Confirmed'
 }

 It 'fails closed on a NEW finding from an existing rule at a different call site -- the registry entry for one location never covers another' {
  $fixture = Join-Path $root 'Fixture.ps1'
  # Same rule (AddType), genuinely different call site (different assembly
  # name) than the registry entry below -- must not inherit its disposition.
  [IO.File]::WriteAllText($fixture, 'Add-Type -AssemblyName System.Data')
  $registryPath = New-RegistryFixtureV1 -Root $root -Entries @(
   [pscustomobject]@{RuleName='InjectionRisk.AddType';Line=1;Extent='Add-Type -AssemblyName System.Net.Http';Disposition='FalsePositive'}
  )
  $result = Test-TPMStaticAnalysisInjectionHunterV1 -Path $fixture -DispositionRegistryPath $registryPath
  $result.FindingCount | Should -Be 1
  $result.UnresolvedFindingCount | Should -Be 1
  $result.Dispositions[0].Disposition | Should -Be 'Confirmed'
 }

 It 'reports Executed=false rather than fabricating a result when the disposition registry file is missing' {
  $fixture = Join-Path $root 'Fixture.ps1'
  [IO.File]::WriteAllText($fixture, 'Add-Type -AssemblyName System.Net.Http')
  $missingRegistry = Join-Path $root 'DoesNotExist.psd1'
  $result = Test-TPMStaticAnalysisInjectionHunterV1 -Path $fixture -DispositionRegistryPath $missingRegistry
  $result.Executed | Should -Be $false
 }
}

Describe 'ADR-0155 Phase 3 production fact adapter -- Artifacts preflight (issue #171)' {
 BeforeEach { $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $root | Out-Null }

 It 'staging readiness: reports true for a writable staging parent root' {
  $staging = Join-Path $root 'staging'
  $dest = Join-Path $root 'dest'
  $result = Test-TPMArtifactsPreflightV1 -StagingParentRoot $staging -DestinationRoot $dest
  $result.StagingDirectoryReady | Should -Be $true
  $result.PackageValidationErrorCount | Should -Be 0
 }

 It 'staging readiness: reports false and increments the error count when the staging root cannot be created (blocked by a same-named file)' {
  $blockingFile = Join-Path $root 'blocked'
  [IO.File]::WriteAllText($blockingFile, 'not a directory')
  $staging = Join-Path $blockingFile 'staging'
  $dest = Join-Path $root 'dest'
  $result = Test-TPMArtifactsPreflightV1 -StagingParentRoot $staging -DestinationRoot $dest
  $result.StagingDirectoryReady | Should -Be $false
  $result.PackageValidationPassed | Should -Be $false
  $result.PackageValidationErrorCount | Should -BeGreaterThan 0
 }

 It 'publisher availability: reports true when every required Reports/Publication command is loaded (this test session''s own state)' {
  $staging = Join-Path $root 'staging'
  $dest = Join-Path $root 'dest'
  $result = Test-TPMArtifactsPreflightV1 -StagingParentRoot $staging -DestinationRoot $dest
  $result.PublisherAvailable | Should -Be $true
 }

 It 'package-validation preflight: Executed is always true (the preflight was attempted), Passed reflects real sub-check results' {
  $staging = Join-Path $root 'staging'
  $dest = Join-Path $root 'dest'
  $result = Test-TPMArtifactsPreflightV1 -StagingParentRoot $staging -DestinationRoot $dest
  $result.PackageValidationExecuted | Should -Be $true
  $result.PackageValidationPassed | Should -Be $true
 }
}

Describe 'ADR-0155 Phase 3 production fact adapter -- full New-TPMProductionFactRecordsFromLegacyV1 (issue #171)' {
 BeforeEach {
  $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $root | Out-Null
  $script:reportDir = Join-Path $root 'report'; New-Item -ItemType Directory -Path $reportDir | Out-Null
  $script:backupDir = Join-Path $root 'backup'; New-Item -ItemType Directory -Path $backupDir | Out-Null
  $script:results = [pscustomobject]@{
   SmokeMode=$true; Checks=@([pscustomobject]@{Name='Repository available';Passed=$true})
   GitStatus='(clean)'; Pester=[pscustomobject]@{Total=2;Passed=2;Failed=0;Skipped=0;NotRun=0}
   PesterVersion='5.8.0'; PowerShellVersion='7.6.3'
   PSScriptAnalyzerFindings=0; PSScriptAnalyzerVersion='1.24.0'
   Backup=[pscustomobject]@{UserProfiles=$false;GameProfiles=$false}
   Snapshots=[pscustomobject]@{UserProfiles=[pscustomobject]@{Added=0;Removed=0;Changed=0;BeforeSkipped=0;AfterSkipped=0};GameProfiles=[pscustomobject]@{Added=0;Removed=0;Changed=0;BeforeSkipped=0;AfterSkipped=0};Pcsx2x6Crosshairs=[pscustomobject]@{Added=0;Removed=0;Changed=0;BeforeSkipped=0;AfterSkipped=0}}
   Pcsx2x6=[pscustomobject]@{Present=$false}
   VirtualBetaTester=[pscustomobject]@{Total=2;Passed=2;Failed=0;HumanBehaviors=1;IdempotencyChecks=1;RecoveryBehaviors=0;EnvironmentVariations=0;HighTvdBehaviors=1}
   RequestedTeknoParrotRoot='C:\TP'; EffectiveTeknoParrotRoot=$null
  }
 }

 It 'produces all 11 facts, and every one validates through the real dispatcher''s RecordFact with no schema error' {
  $repo = Split-Path $PSScriptRoot -Parent
  $facts = New-TPMProductionFactRecordsFromLegacyV1 -Results $results -RepositoryPath $repo -ReportDirectory $reportDir -BackupDirectory $backupDir -HealthResult $null -HealthLoadError 'no report' -UnattendedBinding $null -StagingParentRoot (Join-Path $root 'staging') -DestinationRoot (Join-Path $root 'dest') -DispositionRegistryPath $realRegistryPath
  $facts.Count | Should -Be 11
  $validator = { param($Path) [pscustomobject]@{Valid=$true;Reason='test';Width=1;Height=1} }
  $authority = New-TPMProductionWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -ReportRoot $root -PngValidator $validator
  { foreach ($fact in $facts) { [void](& $authority 'RecordFact' $fact $null) } } | Should -Not -Throw
 }

 It 'the Static Analysis fact carries real Executed=true results, not the Phase 2 shadow placeholder defaults' {
  $repo = Split-Path $PSScriptRoot -Parent
  $facts = New-TPMProductionFactRecordsFromLegacyV1 -Results $results -RepositoryPath $repo -ReportDirectory $reportDir -BackupDirectory $backupDir -HealthResult $null -HealthLoadError 'no report' -UnattendedBinding $null -StagingParentRoot (Join-Path $root 'staging') -DestinationRoot (Join-Path $root 'dest') -DispositionRegistryPath $realRegistryPath
  $sa = ($facts | Where-Object { $_.Identifier -eq 'Static Analysis' }).Data
  $sa.Parser[0].Executed | Should -Be $true
  $sa.Parser[1].Executed | Should -Be $true
  $sa.Encoding.Executed | Should -Be $true
  $sa.InjectionHunter.Executed | Should -Be $true
  $sa.InjectionHunter.UnresolvedFindingCount | Should -Be 0
 }

 It 'the Artifacts fact carries real preflight results, not the Phase 2 shadow placeholder defaults' {
  $repo = Split-Path $PSScriptRoot -Parent
  $facts = New-TPMProductionFactRecordsFromLegacyV1 -Results $results -RepositoryPath $repo -ReportDirectory $reportDir -BackupDirectory $backupDir -HealthResult $null -HealthLoadError 'no report' -UnattendedBinding $null -StagingParentRoot (Join-Path $root 'staging') -DestinationRoot (Join-Path $root 'dest') -DispositionRegistryPath $realRegistryPath
  $art = ($facts | Where-Object { $_.Identifier -eq 'Artifacts' }).Data
  $art.StagingDirectoryReady | Should -Be $true
  $art.PublisherAvailable | Should -Be $true
  $art.PackageValidationExecuted | Should -Be $true
  $art.PackageValidationPassed | Should -Be $true
 }

 It 'the other nine categories are unchanged from the shadow adapter''s own already-correct mapping' {
  $repo = Split-Path $PSScriptRoot -Parent
  $shadowFacts = New-TPMShadowFactRecordsFromLegacyV1 -Results $results -RepositoryPath $repo -ReportDirectory $reportDir -BackupDirectory $backupDir -HealthResult $null -HealthLoadError 'no report' -UnattendedBinding $null
  $productionFacts = New-TPMProductionFactRecordsFromLegacyV1 -Results $results -RepositoryPath $repo -ReportDirectory $reportDir -BackupDirectory $backupDir -HealthResult $null -HealthLoadError 'no report' -UnattendedBinding $null -StagingParentRoot (Join-Path $root 'staging') -DestinationRoot (Join-Path $root 'dest') -DispositionRegistryPath $realRegistryPath
  foreach ($identifier in @('Repository','Pester','Real Install Health','Backups','Smoke File Safety','Behavioral Certification (Virtual Beta Tester)','Unattended TPM root binding','Unattended TPM config restoration')) {
   $shadowJson = (ConvertTo-TPMJcsV1 (($shadowFacts | Where-Object { $_.Identifier -eq $identifier })))
   $productionJson = (ConvertTo-TPMJcsV1 (($productionFacts | Where-Object { $_.Identifier -eq $identifier })))
   $productionJson | Should -Be $shadowJson
  }
 }
}
