#Requires -Module Pester
BeforeAll {
 $authorityModulePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Authority.psm1'
 Import-Module $authorityModulePath -Force
 $productionModulePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Production.psm1'
 Import-Module $productionModulePath -Force
 $reportsModulePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Reports.psm1'
 Import-Module $reportsModulePath -Force
 $publicationModulePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Publication.psm1'
 Import-Module $publicationModulePath -Force
 $modulePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.ProductionCycle.psm1'
 Import-Module $modulePath -Force
 function New-TestFacts([string]$Root,[bool]$ForcePesterFailure=$false){
  $hash='a'*64;$repo=[IO.Path]::GetFullPath((Join-Path $Root 'repo'));$report=[IO.Path]::GetFullPath((Join-Path $Root 'report'));$backup=[IO.Path]::GetFullPath((Join-Path $Root 'backup'))
  @(
   [ordered]@{Identifier='Repository';Applicable=$true;Data=[ordered]@{RepositoryPath=$repo;RepositoryAvailable=$true;RepositoryClean=$true;GitStatus='(clean)'}}
   [ordered]@{Identifier='Pester';Applicable=$true;Data=[ordered]@{Executed=$true;Total=2;Passed=$(if($ForcePesterFailure){1}else{2});Failed=$(if($ForcePesterFailure){1}else{0});Skipped=0;NotRun=0;Engine='Pester 5.7.1 / pwsh 7.6.3';SuiteSha256=$hash}}
   [ordered]@{Identifier='Static Analysis';Applicable=$true;Data=[ordered]@{Parser=@([ordered]@{Identifier='WindowsPowerShell51';Executed=$true;ErrorCount=0;ToolVersion='5.1'},[ordered]@{Identifier='Pwsh';Executed=$true;ErrorCount=0;ToolVersion='7.6.3'});Encoding=[ordered]@{Executed=$true;NonAsciiByteCount=0;Files=@('TeknoParrot-Manager.ps1')};PSScriptAnalyzer=[ordered]@{Executed=$true;FindingCount=0;ToolVersion='1.24.0'};InjectionHunter=[ordered]@{Executed=$true;FindingCount=0;UnresolvedFindingCount=0;ToolVersion='1.0.0';Dispositions=@()}}}
   [ordered]@{Identifier='Real Install Health';Applicable=$true;Data=[ordered]@{ReportPath=(Join-Path $report 'InstallHealth.json');LoadState='Loaded';LoadError=$null;Checks=@([ordered]@{Name='TeknoParrotUi.exe exists';Passed=$true},[ordered]@{Name='GameProfiles folder exists';Passed=$true},[ordered]@{Name='UserProfiles folder exists';Passed=$true})}}
   [ordered]@{Identifier='Backups';Applicable=$true;Data=[ordered]@{UserProfilesBackupCreated=$true;UserProfilesBackupPath=$backup;UserProfilesBackupVerified=$true;UserProfilesBackupSha256=$hash;GameProfilesBackupCreated=$false;GameProfilesBackupPath=$null;GameProfilesBackupVerified=$false;GameProfilesBackupSha256=$null;BackupVerificationExecuted=$true}}
   [ordered]@{Identifier='Smoke File Safety';Applicable=$true;Data=[ordered]@{UserProfiles=[ordered]@{Added=0;Removed=0;Changed=0;BeforeSkipped=0;AfterSkipped=0};GameProfiles=[ordered]@{Added=0;Removed=0;Changed=0;BeforeSkipped=0;AfterSkipped=0};Pcsx2x6Crosshairs=[ordered]@{Added=0;Removed=0;Changed=0;BeforeSkipped=0;AfterSkipped=0}}}
   [ordered]@{Identifier='Artifacts';Applicable=$true;Data=[ordered]@{ReportDirectory=$report;ReportDirectoryReserved=$true;StagingDirectoryReady=$true;RequiredArtifactManifestConfigured=$true;PublisherAvailable=$true;PackageValidationExecuted=$true;PackageValidationPassed=$true;PackageValidationErrorCount=0}}
   [ordered]@{Identifier='pcsx2x6 crosshair path (issue #79)';Applicable=$false;Data=[ordered]@{Present=$false;CanonicalFilesDeployed=$false;LegacyRootPresent=$false;IniFound=$false;CursorPathPointsCanonical=$false;Pcsx2Directory=$null}}
   [ordered]@{Identifier='Behavioral Certification (Virtual Beta Tester)';Applicable=$true;Data=[ordered]@{Executed=$true;Total=2;Passed=2;Failed=0;HumanBehaviors=1;IdempotencyChecks=1;RecoveryBehaviors=0;EnvironmentVariations=0;HighTvdBehaviors=1}}
   [ordered]@{Identifier='Unattended TPM root binding';Applicable=$false;Data=[ordered]@{RequestedRoot=$repo;EffectiveRoot=$null;EffectiveRootParseState='Missing'}}
   [ordered]@{Identifier='Unattended TPM config restoration';Applicable=$false;Data=[ordered]@{}}
  )
 }
 function New-TestEvidence([string]$Root,[string]$Identifier,[bool]$Required,[string]$Type,[int]$Index,[switch]$Skipped){
  if($Skipped){return [ordered]@{Identifier=$Identifier;Status='Skipped';EvidenceType=$null;Required=$false;Path=$null;CaptureScope=$null;FileSha256=$null;Width=$null;Height=$null;FailureCode='EVIDENCE_SKIPPED';FailureMessage='not displayed'}}
  $path=[IO.Path]::GetFullPath((Join-Path $Root ([guid]::NewGuid().ToString('N')+".png")));[IO.File]::WriteAllBytes($path,[byte[]](137,80,78,71,13,10,26,10,$Index));$sha=[Security.Cryptography.SHA256]::Create();try{$hash=-join($sha.ComputeHash([IO.File]::ReadAllBytes($path))|ForEach-Object{$_.ToString('x2')})}finally{$sha.Dispose()};[ordered]@{Identifier=$Identifier;Status='Captured';EvidenceType=$Type;Required=$Required;Path=$path;CaptureScope=$(if($Type-eq'ScreenCapture'){'ConsoleWindow'}else{'Deterministic'});FileSha256=$hash;Width=1;Height=1;FailureCode=$null;FailureMessage=$null}
 }
 $validator={param($Path)[pscustomobject]@{Valid=$true;Reason='test PNG';Width=1;Height=1}}
 function New-SealedRunV1([string]$Root,[bool]$ForcePesterFailure=$false){
  $authority=New-TPMProductionWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $Root -PngValidator $validator
  foreach($fact in (New-TestFacts $Root $ForcePesterFailure)){&$authority RecordFact $fact}
  $ids=@('certification-suite-running','requested-effective-root-evidence','live-thumbnail-evidence','live-controls-evidence','adaptive-menu-normal','adaptive-menu-small','adaptive-menu-maximized','smoke-file-safety-evidence')
  $types=@('ScreenCapture','ScreenCapture',$null,$null,'DeterministicRender','DeterministicRender','DeterministicRender','DeterministicRender')
  for($i=0;$i-lt8;$i++){$e=if($i-in2,3){New-TestEvidence $Root $ids[$i] $false $null $i -Skipped}else{New-TestEvidence $Root $ids[$i] $true $types[$i] $i};&$authority RecordEvidence $e}
  $preview=&$authority DeriveScorePreview
  $final=New-TestEvidence $Root 'final-certification-result' $true 'ScreenCapture' 8
  &$authority IssueFinalEvidence $final $preview
  $sealed=&$authority Seal
  return @{Authority=$authority;Sealed=$sealed}
 }
}

Describe 'ADR-0155 Phase 3 production certification cycle orchestration' {
 BeforeEach {
  $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null
  $stagingParent=Join-Path $root 'staging';New-Item -ItemType Directory -Path $stagingParent|Out-Null
  $destinationParent=Join-Path $root 'destination';New-Item -ItemType Directory -Path $destinationParent|Out-Null
 }

 It 'produces a genuine CERTIFIED outcome end to end: real manifest/artifact-set hashes drive RegisterCommittedPublication, not placeholders' {
  $run=New-SealedRunV1 $root
  $result=Complete-TPMProductionCertificationCycleV1 -Authority $run.Authority -SealedRun $run.Sealed -StagingParentRoot $stagingParent -DestinationRoot $destinationParent
  $result.Commit.Committed|Should -Be $true
  $observationParsed=$result.PublicationOutcome.CanonicalJson|ConvertFrom-Json
  $observationParsed.ManifestSha256|Should -Be $result.Commit.ManifestSha256
  $observationParsed.ArtifactSetSha256|Should -Be $result.Commit.ArtifactSetSha256
  $observationParsed.ManifestSha256|Should -Not -Be ('b'*64)
  $observationParsed.ArtifactSetSha256|Should -Not -Be ('c'*64)
  $manifestParsed=$result.Manifest.Json|ConvertFrom-Json
  $observationParsed.ManifestSha256|Should -Be (Get-TPMSha256HexV1 -Bytes $result.Manifest.Bytes)
  $observationParsed.ArtifactSetSha256|Should -Be $manifestParsed.ArtifactSetSha256
  $result.FinalOutcome.GetType().FullName|Should -Be 'Jumpstile.TPM.Certification.V1.TPMFinalOutcomeV1'
  $result.Projection.FinalStatus|Should -Be 'CERTIFIED'
  $result.Projection.ExitCode|Should -Be 0
 }

 It 'produces a genuine NOT CERTIFIED outcome (score-ineligible) while still publishing the complete committed bundle' {
  $run=New-SealedRunV1 $root $true
  $result=Complete-TPMProductionCertificationCycleV1 -Authority $run.Authority -SealedRun $run.Sealed -StagingParentRoot $stagingParent -DestinationRoot $destinationParent
  $result.Commit.Committed|Should -Be $true
  (Get-ChildItem -LiteralPath $result.Commit.DestinationDirectory -File).Count|Should -Be 7
  $result.Projection.FinalStatus|Should -Be 'NOT CERTIFIED'
  $result.Projection.ExitCode|Should -Be 1
 }

 It 'watch item: the Section 8.3 candidate participates in manifest construction but cannot drive runtime certification' {
  $run=New-SealedRunV1 $root
  $result=Complete-TPMProductionCertificationCycleV1 -Authority $run.Authority -SealedRun $run.Sealed -StagingParentRoot $stagingParent -DestinationRoot $destinationParent
  # The candidate's own bytes are exactly what got staged/committed into the manifest's FinalOutcomeJson slot.
  $manifestParsed=$result.Manifest.Json|ConvertFrom-Json
  $finalOutcomeEntry=@($manifestParsed.Artifacts|Where-Object{$_.Identifier-eq'FinalOutcomeJson'})[0]
  $finalOutcomeEntry.Sha256|Should -Be (Get-TPMSha256HexV1 -Bytes $result.FinalOutcomeCandidateReport.Bytes)
  # The candidate's own output object is structurally rejected by both the runtime report builder and the projection.
  {New-TPMFinalOutcomeReportV1 -FinalOutcome $result.FinalOutcomeCandidateReport}|Should -Throw '*REPORT_INVALID*'
  {New-TPMFinalOutcomeProjectionV1 -FinalOutcome $result.FinalOutcomeCandidateReport}|Should -Throw '*REPORT_INVALID*'
  # The runtime projection is derived only from the genuine dispatcher-issued FinalOutcome.
  $result.FinalOutcome.GetType().FullName|Should -Be 'Jumpstile.TPM.Certification.V1.TPMFinalOutcomeV1'
  $result.Projection.FinalStatus|Should -Be 'CERTIFIED'
 }

 It 'watch item: an eligible run whose publication fails produces no authoritative committed outcome and never reports CERTIFIED' {
  $run=New-SealedRunV1 $root
  $runIdentity=&$run.Authority GetRunIdentity
  $collidingDir=Join-Path ([IO.Path]::GetFullPath($destinationParent)) $runIdentity
  New-Item -ItemType Directory -Path $collidingDir|Out-Null
  [IO.File]::WriteAllBytes((Join-Path $collidingDir 'TPM-Certification-Eligibility.json'),[byte[]](9,9,9))
  $result=Complete-TPMProductionCertificationCycleV1 -Authority $run.Authority -SealedRun $run.Sealed -StagingParentRoot $stagingParent -DestinationRoot $destinationParent
  $result.Commit.Committed|Should -Be $false
  $observationParsed=$result.PublicationOutcome.CanonicalJson|ConvertFrom-Json
  $observationParsed.Committed|Should -Be $false
  $observationParsed.ManifestSha256|Should -BeNullOrEmpty
  $observationParsed.ArtifactSetSha256|Should -BeNullOrEmpty
  @($observationParsed.FailureReasons).Count|Should -BeGreaterThan 0
  $result.FinalOutcome.CanonicalJson|Should -Match '"PublicationCommitted":false'
  $result.Projection.FinalStatus|Should -Be 'NOT CERTIFIED'
  $result.Projection.ExitCode|Should -Be 1
  # No authoritative bundle or commit marker was left at the destination -- only the pre-existing collider remains.
  $remaining=@(Get-ChildItem -LiteralPath $collidingDir -File)
  $remaining.Count|Should -Be 1
  $remaining[0].Name|Should -Be 'TPM-Certification-Eligibility.json'
  (Test-Path -LiteralPath (Join-Path $collidingDir 'TPM-Certification-Commit.json'))|Should -Be $false
 }

 It 'rolls the failed attempt back to its own staging directory, leaving nothing partially promoted' {
  $run=New-SealedRunV1 $root
  $runIdentity=&$run.Authority GetRunIdentity
  $collidingDir=Join-Path ([IO.Path]::GetFullPath($destinationParent)) $runIdentity
  New-Item -ItemType Directory -Path $collidingDir|Out-Null
  [IO.File]::WriteAllBytes((Join-Path $collidingDir 'TPM-Certification-Scorecard.md'),[byte[]](9))
  $result=Complete-TPMProductionCertificationCycleV1 -Authority $run.Authority -SealedRun $run.Sealed -StagingParentRoot $stagingParent -DestinationRoot $destinationParent
  $result.Commit.Committed|Should -Be $false
  $rolledBack=@(Get-ChildItem -LiteralPath $stagingParent -Recurse -File)
  ($rolledBack|Where-Object{$_.Name-eq'TPM-Certification-Eligibility.json'}).Count|Should -Be 1
  ($rolledBack|Where-Object{$_.Name-eq'TPM-Certification-Publication.json'}).Count|Should -Be 1
  ($rolledBack|Where-Object{$_.Name-eq'TPM-Certification-Final-Outcome.json'}).Count|Should -Be 1
 }

 It 'the on-disk committed Final-Outcome artifact is the Section 8.3 candidate schema, agreeing with the runtime projection when publication commits' {
  $run=New-SealedRunV1 $root
  $result=Complete-TPMProductionCertificationCycleV1 -Authority $run.Authority -SealedRun $run.Sealed -StagingParentRoot $stagingParent -DestinationRoot $destinationParent
  $onDiskPath=Join-Path $result.Commit.DestinationDirectory 'TPM-Certification-Final-Outcome.json'
  $onDiskParsed=[IO.File]::ReadAllText($onDiskPath)|ConvertFrom-Json
  @($onDiskParsed.PSObject.Properties.Name|Sort-Object)|Should -Be @('EligibilityPayloadSha256','EligibilityStatus','ExitCode','FinalStatus','RequiredPublicationState','RunIdentity','SchemaVersion')
  $onDiskParsed.FinalStatus|Should -Be $result.Projection.FinalStatus
  $onDiskParsed.ExitCode|Should -Be $result.Projection.ExitCode
 }
}
