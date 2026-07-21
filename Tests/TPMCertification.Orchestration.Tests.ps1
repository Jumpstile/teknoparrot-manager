#Requires -Module Pester
BeforeAll {
 $modulePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Orchestration.psm1'
 Import-Module $modulePath -Force
 function New-OrchestrationTestFacts([string]$Root,[bool]$ForceFailure=$false){
  $hash='a'*64;$repo=[IO.Path]::GetFullPath((Join-Path $Root 'repo'));$report=[IO.Path]::GetFullPath((Join-Path $Root 'report'));$backup=[IO.Path]::GetFullPath((Join-Path $Root 'backup'))
  $pesterTotal=2;$pesterPassed=if($ForceFailure){1}else{2};$pesterFailed=if($ForceFailure){1}else{0}
  @(
   [ordered]@{Identifier='Repository';Applicable=$true;Data=[ordered]@{RepositoryPath=$repo;RepositoryAvailable=$true;RepositoryClean=$true;GitStatus='(clean)'}}
   [ordered]@{Identifier='Pester';Applicable=$true;Data=[ordered]@{Executed=$true;Total=$pesterTotal;Passed=$pesterPassed;Failed=$pesterFailed;Skipped=0;NotRun=0;Engine='Pester 5.7.1 / pwsh 7.6.3';SuiteSha256=$hash}}
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
 function New-OrchestrationTestLegacyEvidence([string]$Root){
  $ids=@('certification-suite-running','requested-effective-root-evidence','live-thumbnail-evidence','live-controls-evidence','adaptive-menu-normal','adaptive-menu-small','adaptive-menu-maximized','smoke-file-safety-evidence','final-certification-result')
  $types=@('ScreenCapture','ScreenCapture',$null,$null,'DeterministicRender','DeterministicRender','DeterministicRender','DeterministicRender','ScreenCapture')
  $out=New-Object Collections.Generic.List[object]
  for($i=0;$i-lt9;$i++){
   if($i-in2,3){
    $out.Add([pscustomobject]@{Name=$ids[$i];Status='Skipped';EvidenceType=$null;CaptureScope=$null;Details='not displayed'})
   }else{
    $path=[IO.Path]::GetFullPath((Join-Path $Root ("$i.png")))
    [IO.File]::WriteAllBytes($path,[byte[]](137,80,78,71,13,10,26,10,$i))
    $out.Add([pscustomobject]@{Name=$ids[$i];Status='Captured';EvidenceType=$types[$i];CaptureScope=$(if($types[$i]-eq'ScreenCapture'){'Window'}else{'Deterministic'});Path=$path;Details=$null})
   }
  }
  return $out.ToArray()
 }
 $validator={param($Path)[pscustomobject]@{Valid=$true;Reason='test PNG';Width=1;Height=1}}
 function Invoke-TestOrchestrationV1([string]$Root,[bool]$ForceFailure=$false,[string]$DestinationRoot=$null){
  $evidenceRoot=Join-Path $Root 'evidence';New-Item -ItemType Directory -Path $evidenceRoot|Out-Null
  $stagingParentRoot=Join-Path $Root 'staging';New-Item -ItemType Directory -Path $stagingParentRoot|Out-Null
  if(-not $DestinationRoot){$DestinationRoot=Join-Path $Root 'destination';New-Item -ItemType Directory -Path $DestinationRoot|Out-Null}
  $facts=New-OrchestrationTestFacts $Root $ForceFailure
  $legacyEvidence=New-OrchestrationTestLegacyEvidence $evidenceRoot
  return Invoke-TPMProductionCertificationV1 -Mode Smoke -Facts $facts -EvidenceRoot $evidenceRoot -ReportRoot $Root -LegacyEvidence $legacyEvidence -StagingParentRoot $stagingParentRoot -DestinationRoot $DestinationRoot -PngValidator $validator
 }
}

Describe 'ADR-0155 Phase 3 production certification orchestrator (ADR155-0309 wiring)' {
 BeforeEach {$root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null}

 It 'CERTIFIED path: commits a real seven-file bundle and projects CERTIFIED/ExitCode 0 from the genuine dispatcher FinalOutcome' {
  $result=Invoke-TestOrchestrationV1 $root
  $result.Projection.FinalStatus|Should -Be 'CERTIFIED'
  $result.Projection.ExitCode|Should -Be 0
  $result.FinalOutcome.GetType().FullName|Should -Be 'Jumpstile.TPM.Certification.V1.TPMFinalOutcomeV1'
  $result.CommitResult.Committed|Should -Be $true
  $files=Get-ChildItem -LiteralPath $result.CommitResult.DestinationDirectory -File
  $files.Count|Should -Be 7
  @($files.Name|Sort-Object)|Should -Be @('TPM-Certification-Commit.json','TPM-Certification-Eligibility.json','TPM-Certification-Final-Outcome.json','TPM-Certification-Manifest.json','TPM-Certification-Publication.json','TPM-Certification-Scorecard.md','TPM-Certification-Validation.md')
  $result.Projection.RunIdentity|Should -Be $result.RunIdentity
 }

 It 'NOT CERTIFIED (score-ineligible) path: still commits an authoritative bundle, and both the candidate artifact and the real projection agree' {
  $result=Invoke-TestOrchestrationV1 $root $true
  $result.Projection.FinalStatus|Should -Be 'NOT CERTIFIED'
  $result.Projection.ExitCode|Should -Be 1
  $result.CommitResult.Committed|Should -Be $true
  $publishedOutcome=Get-Content -LiteralPath (Join-Path $result.CommitResult.DestinationDirectory 'TPM-Certification-Final-Outcome.json') -Raw|ConvertFrom-Json
  $publishedOutcome.FinalStatus|Should -Be 'NOT CERTIFIED'
  (Get-ChildItem -LiteralPath $result.CommitResult.DestinationDirectory -File).Count|Should -Be 7
 }

 It 'NOT CERTIFIED via publication failure: eligibility was Eligible, but the real FinalOutcome correctly overrides the candidate''s optimistic CERTIFIED claim' {
  $blockingFile=Join-Path $root 'destination-is-a-file.txt'
  [IO.File]::WriteAllText($blockingFile,'not a directory')
  $result=Invoke-TestOrchestrationV1 $root $false $blockingFile
  $result.CommitResult.Committed|Should -Be $false
  $result.CommitResult.FailureCode|Should -Not -BeNullOrEmpty
  # Eligibility itself was Eligible -- the Section 8.3 candidate this run would
  # have produced said CERTIFIED. The real, post-publication-attempt
  # dispatcher FinalOutcome must say otherwise, proving the candidate never
  # leaks into the runtime decision.
  ($result.Eligibility.CanonicalJson|ConvertFrom-Json).EligibleForCertification|Should -Be $true
  $result.Projection.FinalStatus|Should -Be 'NOT CERTIFIED'
  $result.Projection.ExitCode|Should -Be 1
  $result.FinalOutcome.GetType().FullName|Should -Be 'Jumpstile.TPM.Certification.V1.TPMFinalOutcomeV1'
 }

 It 'throws rather than silently proceeding when legacy evidence is incomplete' {
  $evidenceRoot=Join-Path $root 'evidence';New-Item -ItemType Directory -Path $evidenceRoot|Out-Null
  $stagingParentRoot=Join-Path $root 'staging';New-Item -ItemType Directory -Path $stagingParentRoot|Out-Null
  $destinationRoot=Join-Path $root 'destination';New-Item -ItemType Directory -Path $destinationRoot|Out-Null
  $facts=New-OrchestrationTestFacts $root
  $incompleteEvidence=@((New-OrchestrationTestLegacyEvidence $evidenceRoot)|Select-Object -First 8)
  {Invoke-TPMProductionCertificationV1 -Mode Smoke -Facts $facts -EvidenceRoot $evidenceRoot -ReportRoot $root -LegacyEvidence $incompleteEvidence -StagingParentRoot $stagingParentRoot -DestinationRoot $destinationRoot -PngValidator $validator}|Should -Throw '*EVIDENCE_MANIFEST_INCOMPLETE*'
 }

 It 'the manifest and marker returned alongside a committed run validate as an authoritative, self-consistent bundle' {
  $result=Invoke-TestOrchestrationV1 $root
  $manifestOnDisk=Get-Content -LiteralPath (Join-Path $result.CommitResult.DestinationDirectory 'TPM-Certification-Manifest.json') -Raw
  $manifestOnDisk|Should -Be $result.Manifest.Json
  $markerOnDisk=Get-Content -LiteralPath (Join-Path $result.CommitResult.DestinationDirectory 'TPM-Certification-Commit.json') -Raw
  $markerOnDisk|Should -Be $result.Marker.Json
 }
}
