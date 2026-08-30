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
function New-TestCertificationIdentity {
 $commit='a'*40;$hash='a'*64;$snapshot=[ordered]@{Branch='main';Commit=$commit;RemoteRef='origin/main';RemoteCommit=$commit;Clean=$true;RefSnapshotSha256=$hash;ReflogSnapshotSha256=$hash}
 [ordered]@{ExpectedBranch='main';ExpectedCommit=$commit;Start=$snapshot;End=$snapshot;RefMutationDetected=$false;RefMutationReason=$null;IdentityValid=$true}
}
function New-TestFacts([string]$Root,[bool]$ForcePesterFailure=$false){
  $hash='a'*64;$repo=[IO.Path]::GetFullPath((Join-Path $Root 'repo'));$report=[IO.Path]::GetFullPath((Join-Path $Root 'report'));$backup=[IO.Path]::GetFullPath((Join-Path $Root 'backup'))
  @(
   [ordered]@{Identifier='Repository';Applicable=$true;Data=[ordered]@{RepositoryPath=$repo;RepositoryAvailable=$true;RepositoryClean=$true;GitStatus='(clean)';CertificationIdentity=(New-TestCertificationIdentity)}}
   [ordered]@{Identifier='Pester';Applicable=$true;Data=[ordered]@{Executed=$true;Total=2;Passed=$(if($ForcePesterFailure){1}else{2});Failed=$(if($ForcePesterFailure){1}else{0});Skipped=0;NotRun=0;Engine='Pester 5.7.1 / pwsh 7.6.3';SuiteSha256=$hash}}
   [ordered]@{Identifier='Static Analysis';Applicable=$true;Data=[ordered]@{Parser=@([ordered]@{Identifier='WindowsPowerShell51';Executed=$true;ErrorCount=0;ToolVersion='5.1'},[ordered]@{Identifier='Pwsh';Executed=$true;ErrorCount=0;ToolVersion='7.6.3'});Encoding=[ordered]@{Executed=$true;NonAsciiByteCount=0;Files=@('TeknoParrot-Manager.ps1')};PSScriptAnalyzer=[ordered]@{Executed=$true;FindingCount=0;ToolVersion='1.24.0'};InjectionHunter=[ordered]@{Executed=$true;FindingCount=0;UnresolvedFindingCount=0;ToolVersion='1.0.0';Dispositions=@()}}}
   [ordered]@{Identifier='Real Install Health';Applicable=$true;Data=[ordered]@{ReportPath=(Join-Path $report 'InstallHealth.json');LoadState='Loaded';LoadError=$null;Checks=@([ordered]@{Name='TeknoParrotUi.exe exists';Passed=$true},[ordered]@{Name='GameProfiles folder exists';Passed=$true},[ordered]@{Name='UserProfiles folder exists';Passed=$true})}}
   [ordered]@{Identifier='Backups';Applicable=$true;Data=[ordered]@{UserProfilesBackupCreated=$true;UserProfilesBackupPath=$backup;UserProfilesBackupVerified=$true;UserProfilesBackupSha256=$hash;GameProfilesBackupCreated=$false;GameProfilesBackupPath=$null;GameProfilesBackupVerified=$false;GameProfilesBackupSha256=$null;BackupVerificationExecuted=$true}}
   [ordered]@{Identifier='Smoke File Safety';Applicable=$true;Data=[ordered]@{UserProfiles=[ordered]@{Added=0;Removed=0;Changed=0;BeforeSkipped=0;AfterSkipped=0};GameProfiles=[ordered]@{Added=0;Removed=0;Changed=0;BeforeSkipped=0;AfterSkipped=0};Pcsx2x6Crosshairs=[ordered]@{Added=0;Removed=0;Changed=0;BeforeSkipped=0;AfterSkipped=0}}}
   [ordered]@{Identifier='Artifacts';Applicable=$true;Data=[ordered]@{ReportDirectory=$report;ReportDirectoryReserved=$true;StagingDirectoryReady=$true;RequiredArtifactManifestConfigured=$true;PublisherAvailable=$true;PackageValidationExecuted=$true;PackageValidationPassed=$true;PackageValidationErrorCount=0;PackageValidationDiagnostics=@()}}
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
  $identityGuard={param([string]$Stage);return $true}
  return @{Authority=$authority;Sealed=$sealed;IdentityGuard=$identityGuard}
 }

 # ADR155-0309 Checkpoint B2 review correction: a thin, real-dispatcher-
 # delegating wrapper that lets a test inject a failure at one named
 # dispatcher operation while every other operation still goes through the
 # genuine authority -- this exercises the real post-commit exception path
 # inside Complete-TPMProductionCertificationCycleV1 itself, not a
 # reimplementation of it.
 function New-TPMFailingAuthorityWrapperV1([scriptblock]$RealAuthority,[string]$FailOperation,[string]$FailMessage='INJECTED_TEST_FAILURE_AFTER_COMMIT'){
  return {
   param([string]$Operation,$Value,$Dependency)
   if($Operation-ceq$FailOperation){throw $FailMessage}
   return &$RealAuthority $Operation $Value $Dependency
  }.GetNewClosure()
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
  $result=Complete-TPMProductionCertificationCycleV1 -Authority $run.Authority -SealedRun $run.Sealed -StagingParentRoot $stagingParent -DestinationRoot $destinationParent -IdentityGuard $run.IdentityGuard -Publish
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

 It 'rolls back a committed bundle when the identity guard rejects after publication' {
  $run=New-SealedRunV1 $root
  $guard={param([string]$Stage) if($Stage-ceq'AfterPublicationCommit'){throw 'CERTIFICATION_IDENTITY_CHANGED_DURING_PRODUCTION_CYCLE: branch/ref mutation'};return $true}.GetNewClosure()
  $errorRecord=$null
  try{Complete-TPMProductionCertificationCycleV1 -Authority $run.Authority -SealedRun $run.Sealed -StagingParentRoot $stagingParent -DestinationRoot $destinationParent -IdentityGuard $guard -Publish}catch{$errorRecord=$_}
  $errorRecord|Should -Not -BeNullOrEmpty
  $errorRecord.Exception.Message|Should -Match '^POST_COMMIT_ROLLBACK_SUCCEEDED:'
  $errorRecord.Exception.Message|Should -Match 'CERTIFICATION_IDENTITY_CHANGED_DURING_PRODUCTION_CYCLE'
  $runIdentity=&$run.Authority GetRunIdentity
  (Test-Path -LiteralPath (Join-Path $destinationParent $runIdentity))|Should -BeFalse
 }

 It 'keeps the final projection inside the identity rollback boundary' {
  $run=New-SealedRunV1 $root
  $guard={param([string]$Stage) if($Stage-ceq'AfterFinalProjection'){throw 'CERTIFICATION_IDENTITY_CHANGED_DURING_PRODUCTION_CYCLE: ref snapshot changed'};return $true}.GetNewClosure()
  $errorRecord=$null
  try{Complete-TPMProductionCertificationCycleV1 -Authority $run.Authority -SealedRun $run.Sealed -StagingParentRoot $stagingParent -DestinationRoot $destinationParent -IdentityGuard $guard -Publish}catch{$errorRecord=$_}
  $errorRecord|Should -Not -BeNullOrEmpty
  $errorRecord.Exception.Message|Should -Match '^POST_COMMIT_ROLLBACK_SUCCEEDED:'
  $errorRecord.Exception.Message|Should -Match 'CERTIFICATION_IDENTITY_CHANGED_DURING_PRODUCTION_CYCLE'
  $runIdentity=&$run.Authority GetRunIdentity
  (Test-Path -LiteralPath (Join-Path $destinationParent $runIdentity))|Should -BeFalse
 }

 It 'calls the identity guard at every production-cycle publication and finalization boundary' {
  $run=New-SealedRunV1 $root
  $stages=New-Object Collections.Generic.List[string]
  $guard={param([string]$Stage);[void]$Stages.Add($Stage);return $true}.GetNewClosure()
  [void](Complete-TPMProductionCertificationCycleV1 -Authority $run.Authority -SealedRun $run.Sealed -StagingParentRoot $stagingParent -DestinationRoot $destinationParent -IdentityGuard $guard -Publish)
  @($stages.ToArray())|Should -Be @('BeforeEligibility','BeforePublicationCommit','AfterPublicationCommit','AfterFinalOutcome','AfterFinalProjection')
 }

 It 'produces a genuine NOT CERTIFIED outcome (score-ineligible) while still publishing the complete committed bundle' {
  $run=New-SealedRunV1 $root $true
  $result=Complete-TPMProductionCertificationCycleV1 -Authority $run.Authority -SealedRun $run.Sealed -StagingParentRoot $stagingParent -DestinationRoot $destinationParent -IdentityGuard $run.IdentityGuard -Publish
  $result.Commit.Committed|Should -Be $true
  @(Get-ChildItem -LiteralPath $result.Commit.DestinationDirectory -File).Count|Should -Be 7
  $result.Projection.FinalStatus|Should -Be 'NOT CERTIFIED'
  $result.Projection.ExitCode|Should -Be 1
 }

 It 'watch item: the Section 8.3 candidate participates in manifest construction but cannot drive runtime certification' {
  $run=New-SealedRunV1 $root
  $result=Complete-TPMProductionCertificationCycleV1 -Authority $run.Authority -SealedRun $run.Sealed -StagingParentRoot $stagingParent -DestinationRoot $destinationParent -IdentityGuard $run.IdentityGuard -Publish
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
  $result=Complete-TPMProductionCertificationCycleV1 -Authority $run.Authority -SealedRun $run.Sealed -StagingParentRoot $stagingParent -DestinationRoot $destinationParent -IdentityGuard $run.IdentityGuard -Publish
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
  $result=Complete-TPMProductionCertificationCycleV1 -Authority $run.Authority -SealedRun $run.Sealed -StagingParentRoot $stagingParent -DestinationRoot $destinationParent -IdentityGuard $run.IdentityGuard -Publish
  $result.Commit.Committed|Should -Be $false
  $rolledBack=@(Get-ChildItem -LiteralPath $stagingParent -Recurse -File)
  @($rolledBack|Where-Object{$_.Name-eq'TPM-Certification-Eligibility.json'}).Count|Should -Be 1
  @($rolledBack|Where-Object{$_.Name-eq'TPM-Certification-Publication.json'}).Count|Should -Be 1
  @($rolledBack|Where-Object{$_.Name-eq'TPM-Certification-Final-Outcome.json'}).Count|Should -Be 1
 }

 It 'the on-disk committed Final-Outcome artifact is the Section 8.3 candidate schema, agreeing with the runtime projection when publication commits' {
  $run=New-SealedRunV1 $root
  $result=Complete-TPMProductionCertificationCycleV1 -Authority $run.Authority -SealedRun $run.Sealed -StagingParentRoot $stagingParent -DestinationRoot $destinationParent -IdentityGuard $run.IdentityGuard -Publish
  $onDiskPath=Join-Path $result.Commit.DestinationDirectory 'TPM-Certification-Final-Outcome.json'
  $onDiskParsed=[IO.File]::ReadAllText($onDiskPath)|ConvertFrom-Json
  @($onDiskParsed.PSObject.Properties.Name|Sort-Object)|Should -Be @('EligibilityPayloadSha256','EligibilityStatus','ExitCode','FinalStatus','RequiredPublicationState','RunIdentity','SchemaVersion')
  $onDiskParsed.FinalStatus|Should -Be $result.Projection.FinalStatus
  $onDiskParsed.ExitCode|Should -Be $result.Projection.ExitCode
 }
}

Describe 'ADR-0155 Phase 3 post-commit exception safety (ADR155-0309 Checkpoint B2 review correction)' {
 BeforeEach {
  $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null
  $stagingParent=Join-Path $root 'staging';New-Item -ItemType Directory -Path $stagingParent|Out-Null
  $destinationParent=Join-Path $root 'destination';New-Item -ItemType Directory -Path $destinationParent|Out-Null
  # Review correction: a locked-file test's injected authority closure runs
  # several call-frames deep (through the dispatcher, through
  # Complete-TPMProductionCertificationCycleV1's own catch block, back into
  # this It block) -- `$script:` inside that closure is NOT lexically bound
  # by .GetNewClosure() the way an ordinary captured variable is; it is
  # dynamically resolved to whatever module/script is executing at the
  # moment the closure body runs, which is a DIFFERENT script scope
  # (TPMCertification.Production's own) than this test file's. A stream
  # assigned via `$script:lockStream = ...` inside such a closure is
  # therefore invisible to this file's own `$script:lockStream` reads,
  # leaving the handle open and failing Pester's own TestDrive cleanup even
  # though every assertion in the test itself passes. $tpmLockBox is a
  # Hashtable (a reference type) that IS captured correctly by
  # .GetNewClosure() regardless of call depth -- every holder of a
  # reference to the same Hashtable instance sees the same `.Stream`
  # value. $tpmActiveLockStreams is a defensive AfterEach backstop: even if
  # an assertion or the cycle call itself throws before this It block's own
  # try/finally runs its disposal, any stream registered here still gets
  # closed before the next test / TestDrive teardown.
  $script:tpmActiveLockBoxes=New-Object Collections.Generic.List[object]
 }

 AfterEach {
  # Defensive backstop: each lock box is a Hashtable an It block registered
  # via $script:tpmActiveLockBoxes.Add($tpmLockBox) immediately after
  # creating it (a normal, non-nested assignment, so $script: here is
  # unambiguous) -- its .Stream field may be set later, from deep inside
  # the injected closure, but because Hashtable is a reference type every
  # holder of this same box sees that same .Stream value. This runs even
  # if the It block's own try/finally never got the chance to (an
  # unexpected exception before that point).
  foreach($lockBox in $script:tpmActiveLockBoxes){
   if($lockBox.Stream){
    try{$lockBox.Stream.Dispose()}catch{}
    $lockBox.Stream=$null
   }
  }
  $script:tpmActiveLockBoxes=New-Object Collections.Generic.List[object]
 }

 It 'an exception injected at IssueFinalOutcome AFTER a successful commit is fully rolled back: no file remains at the destination, and the re-thrown message says so honestly (POST_COMMIT_ROLLBACK_SUCCEEDED)' {
  $run=New-SealedRunV1 $root
  $runIdentity=&$run.Authority GetRunIdentity
  $destinationDir=Join-Path ([IO.Path]::GetFullPath($destinationParent)) $runIdentity
  $failingAuthority=New-TPMFailingAuthorityWrapperV1 -RealAuthority $run.Authority -FailOperation 'IssueFinalOutcome'
  $errorRecord=$null
  try{
   Complete-TPMProductionCertificationCycleV1 -Authority $failingAuthority -SealedRun $run.Sealed -StagingParentRoot $stagingParent -DestinationRoot $destinationParent -IdentityGuard $run.IdentityGuard -Publish
  }catch{$errorRecord=$_}
  $errorRecord|Should -Not -BeNullOrEmpty
  $errorRecord.Exception.Message|Should -Match '^POST_COMMIT_ROLLBACK_SUCCEEDED:'
  $errorRecord.Exception.Message|Should -Match 'INJECTED_TEST_FAILURE_AFTER_COMMIT'
  $errorRecord.Exception.Message|Should -Not -Match 'nothing published'
  (Test-Path -LiteralPath $destinationDir)|Should -Be $false
 }

 It 'an exception injected at RegisterCommittedPublication AFTER a successful commit is fully rolled back the same way' {
  $run=New-SealedRunV1 $root
  $runIdentity=&$run.Authority GetRunIdentity
  $destinationDir=Join-Path ([IO.Path]::GetFullPath($destinationParent)) $runIdentity
  $failingAuthority=New-TPMFailingAuthorityWrapperV1 -RealAuthority $run.Authority -FailOperation 'RegisterCommittedPublication'
  $errorRecord=$null
  try{
   Complete-TPMProductionCertificationCycleV1 -Authority $failingAuthority -SealedRun $run.Sealed -StagingParentRoot $stagingParent -DestinationRoot $destinationParent -IdentityGuard $run.IdentityGuard -Publish
  }catch{$errorRecord=$_}
  $errorRecord.Exception.Message|Should -Match '^POST_COMMIT_ROLLBACK_SUCCEEDED:'
  (Test-Path -LiteralPath $destinationDir)|Should -Be $false
 }

 It 'when rollback itself cannot fully complete (a locked non-marker file), the marker is still removed first and the failure is reported truthfully, never as "nothing published" (POST_COMMIT_ROLLBACK_FAILED)' {
  $run=New-SealedRunV1 $root
  $runIdentity=&$run.Authority GetRunIdentity
  $destinationDir=Join-Path ([IO.Path]::GetFullPath($destinationParent)) $runIdentity
  $lockedPath=Join-Path $destinationDir 'TPM-Certification-Validation.md'
  $tpmLockBox=[ordered]@{Stream=$null}
  [void]$script:tpmActiveLockBoxes.Add($tpmLockBox)
  $failingAuthority={
   param([string]$Operation,$Value,$Dependency)
   if($Operation-ceq'IssueFinalOutcome'){
    # By this point RegisterCommittedPublication has already run and the
    # bundle is genuinely, durably promoted to $destinationDir -- lock one
    # of its files right now, simulating an external process holding it
    # open at the exact moment rollback would need to delete it. Assigning
    # through $tpmLockBox (a Hashtable, captured lexically by
    # GetNewClosure) rather than $script: is what makes this stream
    # visible to the finally block below and to the AfterEach backstop,
    # regardless of how deep this closure is invoked from.
    $tpmLockBox.Stream=[IO.File]::Open($lockedPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    throw 'INJECTED_TEST_FAILURE_AFTER_COMMIT'
   }
   return &$run.Authority $Operation $Value $Dependency
  }.GetNewClosure()
  $errorRecord=$null
  try{
   try{
    Complete-TPMProductionCertificationCycleV1 -Authority $failingAuthority -SealedRun $run.Sealed -StagingParentRoot $stagingParent -DestinationRoot $destinationParent -IdentityGuard $run.IdentityGuard -Publish
   }catch{$errorRecord=$_}
  }finally{
   if($tpmLockBox.Stream){$tpmLockBox.Stream.Dispose();$tpmLockBox.Stream=$null}
  }
  $errorRecord|Should -Not -BeNullOrEmpty
  $errorRecord.Exception.Message|Should -Match '^POST_COMMIT_ROLLBACK_FAILED:'
  $errorRecord.Exception.Message|Should -Not -Match 'no authoritative (marker|bundle) was (written|published)'
  $errorRecord.Exception.Message|Should -Match 'MarkerRemoved=True'
  $errorRecord.Exception.Message|Should -Match 'TPM-Certification-Validation\.md'
  # The marker itself -- the durable "this bundle is authoritative" signal
  # -- was removed even though the locked file remains, proving the
  # rollback breaks the authoritative appearance immediately rather than
  # all-or-nothing.
  (Test-Path -LiteralPath (Join-Path $destinationDir 'TPM-Certification-Commit.json'))|Should -Be $false
  (Test-Path -LiteralPath $lockedPath)|Should -Be $true
 }

 It 'when the commit marker itself cannot be removed, rollback is fail-closed: MarkerRemoved=false, FullyRolledBack=false, POST_COMMIT_ROLLBACK_FAILED, and the message never claims no authoritative marker/bundle remains' {
  $run=New-SealedRunV1 $root
  $runIdentity=&$run.Authority GetRunIdentity
  $destinationDir=Join-Path ([IO.Path]::GetFullPath($destinationParent)) $runIdentity
  $lockedMarkerPath=Join-Path $destinationDir 'TPM-Certification-Commit.json'
  $tpmLockBox=[ordered]@{Stream=$null}
  [void]$script:tpmActiveLockBoxes.Add($tpmLockBox)
  $failingAuthority={
   param([string]$Operation,$Value,$Dependency)
   if($Operation-ceq'IssueFinalOutcome'){
    $tpmLockBox.Stream=[IO.File]::Open($lockedMarkerPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    throw 'INJECTED_TEST_FAILURE_AFTER_COMMIT'
   }
   return &$run.Authority $Operation $Value $Dependency
  }.GetNewClosure()
  $errorRecord=$null
  try{
   try{
    Complete-TPMProductionCertificationCycleV1 -Authority $failingAuthority -SealedRun $run.Sealed -StagingParentRoot $stagingParent -DestinationRoot $destinationParent -IdentityGuard $run.IdentityGuard -Publish
   }catch{$errorRecord=$_}
  }finally{
   if($tpmLockBox.Stream){$tpmLockBox.Stream.Dispose();$tpmLockBox.Stream=$null}
  }
  $errorRecord|Should -Not -BeNullOrEmpty
  $errorRecord.Exception.Message|Should -Match '^POST_COMMIT_ROLLBACK_FAILED:'
  $errorRecord.Exception.Message|Should -Not -Match 'no authoritative (marker|bundle) was (written|published)'
  $errorRecord.Exception.Message|Should -Not -Match 'no authoritative bundle remains'
  $errorRecord.Exception.Message|Should -Match 'MarkerRemoved=False'
  $errorRecord.Exception.Message|Should -Match 'TPM-Certification-Commit\.json'
  # The locked marker is exactly what could not be removed -- it must
  # still physically exist, proving MarkerRemoved=false is truthful, not
  # merely a default.
  (Test-Path -LiteralPath $lockedMarkerPath)|Should -Be $true
 }

 It 'the harness only prints "PUBLISHED : UNKNOWN" when the abort message carries the POST_COMMIT_ROLLBACK_FAILED prefix, never for a fully-rolled-back or ordinary abort' {
  $harnessPath=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\Invoke-TPM-RealInstanceSmoke.ps1'
  $source=[IO.File]::ReadAllText($harnessPath)
  $source|Should -Match "rollbackDidNotFullyComplete = \[string\]\`$productionAbortMessage -like 'POST_COMMIT_ROLLBACK_FAILED:\*'"
  $source|Should -Match 'PUBLISHED\s+:\s+UNKNOWN'
  # The exact same match expression the harness uses, exercised directly
  # against both real exception-message shapes this module actually
  # produces -- proving the gate fires only for the FAILED case, not the
  # SUCCEEDED case or an ordinary pre-commit abort message.
  $succeededMessage='POST_COMMIT_ROLLBACK_SUCCEEDED: certification finalization failed after publication (x); the just-published bundle at C:\dest\run was fully rolled back (commit marker removed) -- no authoritative bundle remains for this run.'
  $failedMessage='POST_COMMIT_ROLLBACK_FAILED: certification finalization failed after publication (x); rollback of the just-published bundle at C:\dest\run did not fully succeed (MarkerRemoved=False; remaining files: C:\dest\run\TPM-Certification-Commit.json; errors: TPM-Certification-Commit.json: in use) -- this directory may still contain an authoritative-looking bundle and requires manual verification.'
  $ordinaryAbortMessage='PRODUCTION_EVIDENCE_COUNT_INVALID: expected 9 harness evidence records, found 3'
  ($succeededMessage -like 'POST_COMMIT_ROLLBACK_FAILED:*')|Should -Be $false
  ($failedMessage -like 'POST_COMMIT_ROLLBACK_FAILED:*')|Should -Be $true
  ($ordinaryAbortMessage -like 'POST_COMMIT_ROLLBACK_FAILED:*')|Should -Be $false
 }
Describe 'Certification-only publication boundary' {
 BeforeEach {
  $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null
  $stagingParent=Join-Path $root 'staging';New-Item -ItemType Directory -Path $stagingParent|Out-Null
  $destinationParent=Join-Path $root 'destination';New-Item -ItemType Directory -Path $destinationParent|Out-Null
 }
 It 'issues CERTIFIED without invoking or creating publication' {
  $run=New-SealedRunV1 $root
  $result=Complete-TPMProductionCertificationCycleV1 -Authority $run.Authority -SealedRun $run.Sealed -StagingParentRoot $stagingParent -DestinationRoot $destinationParent -IdentityGuard $run.IdentityGuard
  $result.Projection.FinalStatus|Should -Be 'CERTIFIED'
  $result.Projection.ExitCode|Should -Be 0
  $result.Commit.Skipped|Should -Be $true
  $result.PublicationOutcome|Should -BeNullOrEmpty
  &$run.Authority GetPhase|Should -Be 'FinalOutcomeIssued'
  ($result.FinalOutcomeReport.Json|ConvertFrom-Json).RequiredPublicationState|Should -Be 'NotRequiredForCertification'
  @(Get-ChildItem -LiteralPath $destinationParent -Recurse -Force)|Should -HaveCount 0
  @(Get-ChildItem -LiteralPath $stagingParent -Recurse -Force)|Should -HaveCount 0
 }
 It 'issues NOT CERTIFIED for ineligible evidence without publication' {
  $run=New-SealedRunV1 $root $true
  $result=Complete-TPMProductionCertificationCycleV1 -Authority $run.Authority -SealedRun $run.Sealed -StagingParentRoot $stagingParent -DestinationRoot $destinationParent -IdentityGuard $run.IdentityGuard
  $result.Projection.FinalStatus|Should -Be 'NOT CERTIFIED'
  $result.Projection.ExitCode|Should -Be 1
  ($result.FinalOutcome.CanonicalJson|ConvertFrom-Json).PublicationCommitted|Should -BeFalse
  $result.Commit.Skipped|Should -Be $true
  $result.PublicationOutcome|Should -BeNullOrEmpty
  @(Get-ChildItem -LiteralPath $destinationParent -Recurse -Force)|Should -HaveCount 0
  @(Get-ChildItem -LiteralPath $stagingParent -Recurse -Force)|Should -HaveCount 0
 }
}
}
