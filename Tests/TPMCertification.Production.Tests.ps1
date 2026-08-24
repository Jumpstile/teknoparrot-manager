#Requires -Module Pester
BeforeAll {
 $modulePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Production.psm1'
Import-Module $modulePath -Force
function New-TestCertificationIdentity {
 $commit='a'*40;$hash='a'*64;$snapshot=[ordered]@{Branch='main';Commit=$commit;RemoteRef='origin/main';RemoteCommit=$commit;Clean=$true;RefSnapshotSha256=$hash;ReflogSnapshotSha256=$hash}
 [ordered]@{ExpectedBranch='main';ExpectedCommit=$commit;Start=$snapshot;End=$snapshot;RefMutationDetected=$false;RefMutationReason=$null;IdentityValid=$true}
}
function New-TestFacts([string]$Root,[string]$Mode='Smoke'){
  $hash='a'*64;$repo=[IO.Path]::GetFullPath((Join-Path $Root 'repo'));$report=[IO.Path]::GetFullPath((Join-Path $Root 'report'));$backup=[IO.Path]::GetFullPath((Join-Path $Root 'backup'))
  @(
   [ordered]@{Identifier='Repository';Applicable=$true;Data=[ordered]@{RepositoryPath=$repo;RepositoryAvailable=$true;RepositoryClean=$true;GitStatus='(clean)';CertificationIdentity=(New-TestCertificationIdentity)}}
   [ordered]@{Identifier='Pester';Applicable=$true;Data=[ordered]@{Executed=$true;Total=2;Passed=2;Failed=0;Skipped=0;NotRun=0;Engine='Pester 5.7.1 / pwsh 7.6.3';SuiteSha256=$hash}}
   [ordered]@{Identifier='Static Analysis';Applicable=$true;Data=[ordered]@{Parser=@([ordered]@{Identifier='WindowsPowerShell51';Executed=$true;ErrorCount=0;ToolVersion='5.1'},[ordered]@{Identifier='Pwsh';Executed=$true;ErrorCount=0;ToolVersion='7.6.3'});Encoding=[ordered]@{Executed=$true;NonAsciiByteCount=0;Files=@('TeknoParrot-Manager.ps1')};PSScriptAnalyzer=[ordered]@{Executed=$true;FindingCount=0;ToolVersion='1.24.0'};InjectionHunter=[ordered]@{Executed=$true;FindingCount=0;UnresolvedFindingCount=0;ToolVersion='1.0.0';Dispositions=@()}}}
   [ordered]@{Identifier='Real Install Health';Applicable=$true;Data=[ordered]@{ReportPath=(Join-Path $report 'InstallHealth.json');LoadState='Loaded';LoadError=$null;Checks=@([ordered]@{Name='TeknoParrotUi.exe exists';Passed=$true},[ordered]@{Name='GameProfiles folder exists';Passed=$true},[ordered]@{Name='UserProfiles folder exists';Passed=$true})}}
   [ordered]@{Identifier='Backups';Applicable=$true;Data=[ordered]@{UserProfilesBackupCreated=$true;UserProfilesBackupPath=$backup;UserProfilesBackupVerified=$true;UserProfilesBackupSha256=$hash;GameProfilesBackupCreated=$false;GameProfilesBackupPath=$null;GameProfilesBackupVerified=$false;GameProfilesBackupSha256=$null;BackupVerificationExecuted=$true}}
   $(if($Mode-eq'Smoke'){[ordered]@{Identifier='Smoke File Safety';Applicable=$true;Data=[ordered]@{UserProfiles=[ordered]@{Added=0;Removed=0;Changed=0;BeforeSkipped=0;AfterSkipped=0};GameProfiles=[ordered]@{Added=0;Removed=0;Changed=0;BeforeSkipped=0;AfterSkipped=0};Pcsx2x6Crosshairs=[ordered]@{Added=0;Removed=0;Changed=0;BeforeSkipped=0;AfterSkipped=0}}}}else{[ordered]@{Identifier='Smoke File Safety';Applicable=$false;Data=[ordered]@{}}})
   [ordered]@{Identifier='Artifacts';Applicable=$true;Data=[ordered]@{ReportDirectory=$report;ReportDirectoryReserved=$true;StagingDirectoryReady=$true;RequiredArtifactManifestConfigured=$true;PublisherAvailable=$true;PackageValidationExecuted=$true;PackageValidationPassed=$true;PackageValidationErrorCount=0}}
   [ordered]@{Identifier='pcsx2x6 crosshair path (issue #79)';Applicable=$false;Data=[ordered]@{Present=$false;CanonicalFilesDeployed=$false;LegacyRootPresent=$false;IniFound=$false;CursorPathPointsCanonical=$false;Pcsx2Directory=$null}}
   [ordered]@{Identifier='Behavioral Certification (Virtual Beta Tester)';Applicable=$true;Data=[ordered]@{Executed=$true;Total=2;Passed=2;Failed=0;HumanBehaviors=1;IdempotencyChecks=1;RecoveryBehaviors=0;EnvironmentVariations=0;HighTvdBehaviors=1}}
   $(if($Mode-eq'Smoke'){[ordered]@{Identifier='Unattended TPM root binding';Applicable=$false;Data=[ordered]@{RequestedRoot=$repo;EffectiveRoot=$null;EffectiveRootParseState='Missing'}}}else{[ordered]@{Identifier='Unattended TPM root binding';Applicable=$true;Data=[ordered]@{RequestedRoot=$repo;EffectiveRoot=$repo;EffectiveRootParseState='Parsed'}}})
   $(if($Mode-eq'Smoke'){[ordered]@{Identifier='Unattended TPM config restoration';Applicable=$false;Data=[ordered]@{}}}else{[ordered]@{Identifier='Unattended TPM config restoration';Applicable=$true;Data=[ordered]@{PriorConfigExisted=$false;TemporaryConfigCreated=$true;RestoreAttempted=$true;RestoreSucceeded=$true;VerificationSucceeded=$true;SnapshotSha256=$null;FailureReason=$null}}})
  )
 }
 function New-TestEvidence([string]$Root,[string]$Identifier,[bool]$Required,[string]$Type,[int]$Index,[switch]$Skipped){
  if($Skipped){return [ordered]@{Identifier=$Identifier;Status='Skipped';EvidenceType=$null;Required=$false;Path=$null;CaptureScope=$null;FileSha256=$null;Width=$null;Height=$null;FailureCode='EVIDENCE_SKIPPED';FailureMessage='not displayed'}}
  $path=[IO.Path]::GetFullPath((Join-Path $Root ("$Index.png")));[IO.File]::WriteAllBytes($path,[byte[]](137,80,78,71,13,10,26,10,$Index));$sha=[Security.Cryptography.SHA256]::Create();try{$hash=-join($sha.ComputeHash([IO.File]::ReadAllBytes($path))|ForEach-Object{$_.ToString('x2')})}finally{$sha.Dispose()};[ordered]@{Identifier=$Identifier;Status='Captured';EvidenceType=$Type;Required=$Required;Path=$path;CaptureScope=$(if($Type-eq'ScreenCapture'){'ConsoleWindow'}else{'Deterministic'});FileSha256=$hash;Width=1;Height=1;FailureCode=$null;FailureMessage=$null}
 }
 $validator={param($Path)[pscustomobject]@{Valid=$true;Reason='test PNG';Width=1;Height=1}}
 function New-SealedRunV1($Root,[string]$Mode='Smoke'){
  $authority=New-TPMProductionWorkflowAuthorityV1 -Mode $Mode -EvidenceRoot $Root -PngValidator $validator
  foreach($fact in New-TestFacts $Root $Mode){&$authority RecordFact $fact}
  $ids=@('certification-suite-running','requested-effective-root-evidence','live-thumbnail-evidence','live-controls-evidence','adaptive-menu-normal','adaptive-menu-small','adaptive-menu-maximized','smoke-file-safety-evidence')
  $types=@('ScreenCapture','ScreenCapture',$null,$null,'DeterministicRender','DeterministicRender','DeterministicRender','DeterministicRender')
  for($i=0;$i-lt8;$i++){$e=if($i-in2,3){New-TestEvidence $Root $ids[$i] $false $null $i -Skipped}else{New-TestEvidence $Root $ids[$i] $true $types[$i] $i};&$authority RecordEvidence $e}
  $preview=&$authority DeriveScorePreview
  $final=New-TestEvidence $Root 'final-certification-result' $true 'ScreenCapture' 8
  &$authority IssueFinalEvidence $final $preview
  $sealed=&$authority Seal
  return @{Authority=$authority;Sealed=$sealed}
 }
 function New-CommittedOutcomeV1($Authority,$Eligibility){
  $candidate=&$Authority IssuePublicationCandidate $Eligibility
  $observation=[ordered]@{ManifestSha256=('b'*64);ArtifactSetSha256=('c'*64);DiagnosticWarnings=@()}
  return &$Authority RegisterCommittedPublication $observation $candidate
 }
}

Describe 'ADR-0155 Phase 3 production dispatcher lifecycle' {
 BeforeEach {$root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null}
 It 'runs the complete pipeline to a CERTIFIED final outcome with matching hashes' {
  $run=New-SealedRunV1 $root
  $eligibility=&$run.Authority IssueEligibility $run.Sealed
  &$run.Authority GetPhase|Should -Be 'EligibilityIssued'
  $payload=$eligibility.CanonicalJson|ConvertFrom-Json
  $payload.EligibleForCertification|Should -BeTrue
  $payload.ApplicableCount|Should -Be 8
  $payload.PassedCount|Should -Be 8
  $payload.PercentageBasisPoints|Should -Be 10000
  $outcome=New-CommittedOutcomeV1 $run.Authority $eligibility
  &$run.Authority GetPhase|Should -Be 'PublicationIssued'
  $final=&$run.Authority IssueFinalOutcome $eligibility $outcome
  &$run.Authority GetPhase|Should -Be 'FinalOutcomeIssued'
  $finalPayload=$final.CanonicalJson|ConvertFrom-Json
  $finalPayload.FinalStatus|Should -Be 'CERTIFIED'
  $finalPayload.ExitCode|Should -Be 0
  $finalPayload.EligibilityPayloadSha256|Should -Be $finalPayload.EligibilityPayloadSha256
  $eligibilityBytes=(New-Object Text.UTF8Encoding $false).GetBytes($eligibility.CanonicalJson)
  $expectedHash=-join([Security.Cryptography.SHA256]::Create().ComputeHash($eligibilityBytes)|ForEach-Object{$_.ToString('x2')})
  $finalPayload.EligibilityPayloadSha256|Should -Be $expectedHash
 }
 It 'produces NOT CERTIFIED with exit code 1 when publication fails after eligibility' {
  $run=New-SealedRunV1 $root
  $eligibility=&$run.Authority IssueEligibility $run.Sealed
  $reasons=@([ordered]@{Code='STAGING_FAILED';Message='could not reserve staging directory'})
  $outcome=&$run.Authority RegisterPublicationFailure $reasons $eligibility
  &$run.Authority GetPhase|Should -Be 'PublicationIssued'
  $final=&$run.Authority IssueFinalOutcome $eligibility $outcome
  $payload=$final.CanonicalJson|ConvertFrom-Json
  $payload.FinalStatus|Should -Be 'NOT CERTIFIED'
  $payload.ExitCode|Should -Be 1
  $payload.PublicationCommitted|Should -BeFalse
  @($payload.FailureReasons|Where-Object{$_.Code-eq'STAGING_FAILED'}).Count|Should -Be 1
 }
 It 'issues TPMPublicationOutcomeV1.FailureReasons as a genuine JSON array, not a bare object, when exactly one reason is given' {
  $run=New-SealedRunV1 $root
  $eligibility=&$run.Authority IssueEligibility $run.Sealed
  $reasons=@([ordered]@{Code='PROMOTION_FAILED';Message='exactly one reason'})
  $outcome=&$run.Authority RegisterPublicationFailure $reasons $eligibility
  $outcome.CanonicalJson|Should -Match '"FailureReasons":\['
  $parsed=$outcome.CanonicalJson|ConvertFrom-Json
  @($parsed.FailureReasons).Count|Should -Be 1
  $parsed.FailureReasons[0].Code|Should -Be 'PROMOTION_FAILED'
 }
 It 'produces NOT CERTIFIED with exit code 1 when publication commits but eligibility failed' {
  $root2=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root2|Out-Null
  $authority=New-TPMProductionWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root2 -PngValidator $validator
  $facts=New-TestFacts $root2;$facts[1].Data.Failed=1;$facts[1].Data.Passed=1
  foreach($f in $facts){&$authority RecordFact $f}
  $ids=@('certification-suite-running','requested-effective-root-evidence','live-thumbnail-evidence','live-controls-evidence','adaptive-menu-normal','adaptive-menu-small','adaptive-menu-maximized','smoke-file-safety-evidence')
  $types=@('ScreenCapture','ScreenCapture',$null,$null,'DeterministicRender','DeterministicRender','DeterministicRender','DeterministicRender')
  for($i=0;$i-lt8;$i++){$e=if($i-in2,3){New-TestEvidence $root2 $ids[$i] $false $null $i -Skipped}else{New-TestEvidence $root2 $ids[$i] $true $types[$i] $i};&$authority RecordEvidence $e}
  $preview=&$authority DeriveScorePreview
  $final=New-TestEvidence $root2 'final-certification-result' $true 'ScreenCapture' 8
  &$authority IssueFinalEvidence $final $preview
  $sealed=&$authority Seal
  $eligibility=&$authority IssueEligibility $sealed
  ($eligibility.CanonicalJson|ConvertFrom-Json).EligibleForCertification|Should -BeFalse
  $outcome=New-CommittedOutcomeV1 $authority $eligibility
  $finalOutcome=&$authority IssueFinalOutcome $eligibility $outcome
  $payload=$finalOutcome.CanonicalJson|ConvertFrom-Json
  $payload.FinalStatus|Should -Be 'NOT CERTIFIED'
  $payload.ExitCode|Should -Be 1
  $payload.PublicationCommitted|Should -BeTrue
  $payload.EligibleForCertification|Should -BeFalse
 }
 It 'allows RegisterPublicationFailure directly from EligibilityIssued without a candidate' {
  $run=New-SealedRunV1 $root
  $eligibility=&$run.Authority IssueEligibility $run.Sealed
  &$run.Authority GetPhase|Should -Be 'EligibilityIssued'
  $reasons=@([ordered]@{Code='PROMOTION_FAILED';Message='could not stage report'})
  {&$run.Authority RegisterPublicationFailure $reasons $eligibility}|Should -Not -Throw
  &$run.Authority GetPhase|Should -Be 'PublicationIssued'
 }
}

Describe 'ADR-0155 Phase 3 production dispatcher phase and provenance enforcement' {
 BeforeEach {$root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null}
 It 'rejects IssueEligibility outside Sealed and rejects a synthetic sealed reader' {
  $authority=New-TPMProductionWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -PngValidator $validator
  {&$authority IssueEligibility 'not-a-reader'}|Should -Throw '*ILLEGAL_PHASE*'
  $run=New-SealedRunV1 $root
  $type='Jumpstile.TPM.Certification.V1.TPMSealedRunReaderV1'-as[type]
  $ctor=$type.GetConstructors([Reflection.BindingFlags]'NonPublic,Instance')[0]
  $fake=$ctor.Invoke(@($run.Sealed.RunIdentity,$run.Sealed.CanonicalJson))
  {&$run.Authority IssueEligibility $fake}|Should -Throw '*PROVENANCE_INVALID*'
 }
 It 'rejects a sealed reader issued by a different authority instance' {
  $runA=New-SealedRunV1 $root
  $root2=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root2|Out-Null
  $runB=New-SealedRunV1 $root2
  {&$runA.Authority IssueEligibility $runB.Sealed}|Should -Throw '*PROVENANCE_INVALID*'
 }
 It 'rejects duplicate eligibility issuance' {
  $run=New-SealedRunV1 $root
  $eligibility=&$run.Authority IssueEligibility $run.Sealed
  {&$run.Authority IssueEligibility $run.Sealed}|Should -Throw '*ILLEGAL_PHASE*'
 }
 It 'rejects IssuePublicationCandidate with a foreign eligibility object and rejects duplicate candidates' {
  $runA=New-SealedRunV1 $root
  $eligibilityA=&$runA.Authority IssueEligibility $runA.Sealed
  $root2=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root2|Out-Null
  $runB=New-SealedRunV1 $root2
  $eligibilityB=&$runB.Authority IssueEligibility $runB.Sealed
  {&$runA.Authority IssuePublicationCandidate $eligibilityB}|Should -Throw '*PROVENANCE_INVALID*'
  $candidate=&$runA.Authority IssuePublicationCandidate $eligibilityA
  {&$runA.Authority IssuePublicationCandidate $eligibilityA}|Should -Throw '*ILLEGAL_PHASE*'
 }
 It 'rejects a malformed publication observation and a foreign publication candidate' {
  $run=New-SealedRunV1 $root
  $eligibility=&$run.Authority IssueEligibility $run.Sealed
  $candidate=&$run.Authority IssuePublicationCandidate $eligibility
  $badObservation=[ordered]@{ManifestSha256='not-a-hash';ArtifactSetSha256=('c'*64);DiagnosticWarnings=@()}
  {&$run.Authority RegisterCommittedPublication $badObservation $candidate}|Should -Throw '*SCHEMA_INVALID*'
  $root2=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root2|Out-Null
  $run2=New-SealedRunV1 $root2
  $eligibility2=&$run2.Authority IssueEligibility $run2.Sealed
  $candidate2=&$run2.Authority IssuePublicationCandidate $eligibility2
  $goodObservation=[ordered]@{ManifestSha256=('b'*64);ArtifactSetSha256=('c'*64);DiagnosticWarnings=@()}
  {&$run.Authority RegisterCommittedPublication $goodObservation $candidate2}|Should -Throw '*PROVENANCE_INVALID*'
 }
 It 'rejects an unrecognized publication failure code' {
  $run=New-SealedRunV1 $root
  $eligibility=&$run.Authority IssueEligibility $run.Sealed
  $badReasons=@([ordered]@{Code='NOT_A_REAL_CODE';Message='bad'})
  {&$run.Authority RegisterPublicationFailure $badReasons $eligibility}|Should -Throw '*SCHEMA_INVALID*'
 }
 It 'rejects IssueFinalOutcome with mismatched eligibility or publication outcome identity' {
  $run=New-SealedRunV1 $root
  $eligibility=&$run.Authority IssueEligibility $run.Sealed
  $outcome=New-CommittedOutcomeV1 $run.Authority $eligibility
  $root2=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root2|Out-Null
  $run2=New-SealedRunV1 $root2
  $eligibility2=&$run2.Authority IssueEligibility $run2.Sealed
  {&$run.Authority IssueFinalOutcome $eligibility2 $outcome}|Should -Throw '*PROVENANCE_INVALID*'
  $outcome2=New-CommittedOutcomeV1 $run2.Authority $eligibility2
  {&$run.Authority IssueFinalOutcome $eligibility $outcome2}|Should -Throw '*PROVENANCE_INVALID*'
  {&$run.Authority IssueFinalOutcome $eligibility $outcome}|Should -Not -Throw
  {&$run.Authority IssueFinalOutcome $eligibility $outcome}|Should -Throw '*ILLEGAL_PHASE*'
 }
}

Describe 'ADR-0155 Phase 3 eligibility payload derivation' {
 It 'rounds a non-terminating percentage away from zero rather than truncating' {
  $nineEvidence=@(0..8|ForEach-Object{[ordered]@{Identifier="e$_";Status='Captured';FailureCode=$null;FailureMessage=$null}})
  $facts=@(
   [ordered]@{Identifier='Repository';Applicable=$true;Data=[ordered]@{RepositoryAvailable=$true;RepositoryClean=$true;CertificationIdentity=(New-TestCertificationIdentity)}}
   [ordered]@{Identifier='Pester';Applicable=$true;Data=[ordered]@{Executed=$true;Total=1;Passed=0;Failed=1;Skipped=0;NotRun=0}}
   [ordered]@{Identifier='Backups';Applicable=$true;Data=[ordered]@{UserProfilesBackupCreated=$true;GameProfilesBackupCreated=$false;BackupVerificationExecuted=$true;UserProfilesBackupVerified=$true;GameProfilesBackupVerified=$false}}
  )
  $payload=Get-TPMEligibilityPayloadV1 -RunIdentity 'x' -Mode Smoke -Facts $facts -Evidence $nineEvidence -FactSetSha256 ('a'*64) -EvidenceSetSha256 ('a'*64) -SealedRunSha256 ('a'*64)
  $payload.ApplicableCount|Should -Be 3
  $payload.PassedCount|Should -Be 2
  $payload.PercentageBasisPoints|Should -Be 6667
  $payload.ScoreEligible|Should -BeFalse
 }
 It 'throws when no applicable category exists' {
  $facts=@([ordered]@{Identifier='Repository';Applicable=$false;Data=[ordered]@{}})
  $nineEvidence=@(0..8|ForEach-Object{[ordered]@{Identifier="e$_";Status='Captured';FailureCode=$null;FailureMessage=$null}})
  {Get-TPMEligibilityPayloadV1 -RunIdentity 'x' -Mode Smoke -Facts $facts -Evidence $nineEvidence -FactSetSha256 ('a'*64) -EvidenceSetSha256 ('a'*64) -SealedRunSha256 ('a'*64)}|Should -Throw '*ApplicableCount*'
 }
}

Describe 'ADR-0155 Phase 1/2/3 module coexistence' {
 It 'keeps all three workflow-authority factories independently discoverable regardless of import order' {
  $authorityModule=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Authority.psm1'
  $shadowModule=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Shadow.psm1'
  $productionModule=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Production.psm1'
  $engine=if($PSVersionTable.PSEdition-ceq'Core'){(Get-Command pwsh).Source}else{(Get-Command powershell).Source}
  $orders=@(
   ,@($authorityModule,$shadowModule,$productionModule)
   ,@($productionModule,$shadowModule,$authorityModule)
   ,@($shadowModule,$productionModule,$authorityModule)
  )
  foreach($order in $orders){
   $probe=Join-Path $TestDrive (([guid]::NewGuid().ToString('N'))+'.ps1')
   $lines=New-Object Collections.Generic.List[string]
   foreach($module in $order){[void]$lines.Add("Import-Module '$module' -Force")}
   [void]$lines.Add('$result = [ordered]@{}')
   [void]$lines.Add('$result.AuthorityModule = (Get-Command New-TPMWorkflowAuthorityV1).ModuleName')
   [void]$lines.Add('$result.ShadowModule = (Get-Command New-TPMShadowWorkflowAuthorityV1).ModuleName')
   [void]$lines.Add('$result.ProductionModule = (Get-Command New-TPMProductionWorkflowAuthorityV1).ModuleName')
   [void]$lines.Add('$result | ConvertTo-Json -Compress')
   [IO.File]::WriteAllText($probe,($lines.ToArray()-join"`n"),(New-Object Text.UTF8Encoding $false))
   $json=& $engine -NoProfile -File $probe
   $result=$json|ConvertFrom-Json
   $result.AuthorityModule|Should -Be 'TPMCertification.Authority'
   $result.ShadowModule|Should -Be 'TPMCertification.Shadow'
   $result.ProductionModule|Should -Be 'TPMCertification.Production'
  }
 }
}
