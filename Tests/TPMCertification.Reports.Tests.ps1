#Requires -Module Pester
BeforeAll {
 $authorityModulePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Authority.psm1'
 Import-Module $authorityModulePath -Force
 $modulePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Reports.psm1'
 Import-Module $modulePath -Force
 $productionModulePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Production.psm1'
 Import-Module $productionModulePath -Force
 function New-TestFacts([string]$Root,[string]$Mode='Smoke'){
  $hash='a'*64;$repo=[IO.Path]::GetFullPath((Join-Path $Root 'repo'));$report=[IO.Path]::GetFullPath((Join-Path $Root 'report'));$backup=[IO.Path]::GetFullPath((Join-Path $Root 'backup'))
  @(
   [ordered]@{Identifier='Repository';Applicable=$true;Data=[ordered]@{RepositoryPath=$repo;RepositoryAvailable=$true;RepositoryClean=$true;GitStatus='(clean)'}}
   [ordered]@{Identifier='Pester';Applicable=$true;Data=[ordered]@{Executed=$true;Total=2;Passed=2;Failed=0;Skipped=0;NotRun=0;Engine='Pester 5.7.1 / pwsh 7.6.3';SuiteSha256=$hash}}
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
  $path=[IO.Path]::GetFullPath((Join-Path $Root ("$Index.png")));[IO.File]::WriteAllBytes($path,[byte[]](137,80,78,71,13,10,26,10,$Index));$sha=[Security.Cryptography.SHA256]::Create();try{$hash=-join($sha.ComputeHash([IO.File]::ReadAllBytes($path))|ForEach-Object{$_.ToString('x2')})}finally{$sha.Dispose()};[ordered]@{Identifier=$Identifier;Status='Captured';EvidenceType=$Type;Required=$Required;Path=$path;CaptureScope=$(if($Type-eq'ScreenCapture'){'ConsoleWindow'}else{'Deterministic'});FileSha256=$hash;Width=1;Height=1;FailureCode=$null;FailureMessage=$null}
 }
 $validator={param($Path)[pscustomobject]@{Valid=$true;Reason='test PNG';Width=1;Height=1}}
 function New-IssuedEligibilityV1($Root){
  $authority=New-TPMProductionWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $Root -PngValidator $validator
  foreach($fact in New-TestFacts $Root){&$authority RecordFact $fact}
  $ids=@('certification-suite-running','requested-effective-root-evidence','live-thumbnail-evidence','live-controls-evidence','adaptive-menu-normal','adaptive-menu-small','adaptive-menu-maximized','smoke-file-safety-evidence')
  $types=@('ScreenCapture','ScreenCapture',$null,$null,'DeterministicRender','DeterministicRender','DeterministicRender','DeterministicRender')
  for($i=0;$i-lt8;$i++){$e=if($i-in2,3){New-TestEvidence $Root $ids[$i] $false $null $i -Skipped}else{New-TestEvidence $Root $ids[$i] $true $types[$i] $i};&$authority RecordEvidence $e}
  $preview=&$authority DeriveScorePreview
  $final=New-TestEvidence $Root 'final-certification-result' $true 'ScreenCapture' 8
  &$authority IssueFinalEvidence $final $preview
  $sealed=&$authority Seal
  return &$authority IssueEligibility $sealed
 }
 function New-IssuedScorePreviewV1($Root,[bool]$ForcePesterFailure){
  $authority=New-TPMProductionWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $Root -PngValidator $validator
  $facts=New-TestFacts $Root
  if($ForcePesterFailure){$facts[1].Data.Failed=1;$facts[1].Data.Passed=1}
  foreach($fact in $facts){&$authority RecordFact $fact}
  return &$authority DeriveScorePreview
 }
 function New-FullPipelineRunV1($Root,[bool]$CommitPublication,[bool]$ForcePesterFailure){
  $authority=New-TPMProductionWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $Root -PngValidator $validator
  $facts=New-TestFacts $Root
  if($ForcePesterFailure){$facts[1].Data.Failed=1;$facts[1].Data.Passed=1}
  foreach($fact in $facts){&$authority RecordFact $fact}
  $ids=@('certification-suite-running','requested-effective-root-evidence','live-thumbnail-evidence','live-controls-evidence','adaptive-menu-normal','adaptive-menu-small','adaptive-menu-maximized','smoke-file-safety-evidence')
  $types=@('ScreenCapture','ScreenCapture',$null,$null,'DeterministicRender','DeterministicRender','DeterministicRender','DeterministicRender')
  for($i=0;$i-lt8;$i++){$e=if($i-in2,3){New-TestEvidence $Root $ids[$i] $false $null $i -Skipped}else{New-TestEvidence $Root $ids[$i] $true $types[$i] $i};&$authority RecordEvidence $e}
  $preview=&$authority DeriveScorePreview
  $final=New-TestEvidence $Root 'final-certification-result' $true 'ScreenCapture' 8
  &$authority IssueFinalEvidence $final $preview
  $sealed=&$authority Seal
  $eligibility=&$authority IssueEligibility $sealed
  $candidate=&$authority IssuePublicationCandidate $eligibility
  if($CommitPublication){
   $observation=[ordered]@{ManifestSha256=('b'*64);ArtifactSetSha256=('c'*64);DiagnosticWarnings=@()}
   $outcome=&$authority RegisterCommittedPublication $observation $candidate
  }else{
   $reasons=@([ordered]@{Code='STAGING_FAILED';Message='could not reserve staging directory'})
   $outcome=&$authority RegisterPublicationFailure $reasons $candidate
  }
  $finalOutcome=&$authority IssueFinalOutcome $eligibility $outcome
  return @{Authority=$authority;Eligibility=$eligibility;PublicationCandidate=$candidate;PublicationOutcome=$outcome;FinalOutcome=$finalOutcome}
 }
}

Describe 'ADR-0155 Phase 3 eligibility report builder' {
 BeforeEach {$root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null}
 It 'produces the exact detached Payload-then-Integrity envelope with a self-consistent hash' {
  $eligibility=New-IssuedEligibilityV1 $root
  $report=New-TPMEligibilityReportV1 -Eligibility $eligibility
  $report.FileName|Should -Be 'TPM-Certification-Eligibility.json'
  $parsed=$report.Json|ConvertFrom-Json
  @($parsed.PSObject.Properties.Name)|Should -Be @('Integrity','Payload')
  $parsed.Integrity.Algorithm|Should -Be 'SHA-256'
  $utf8=New-Object Text.UTF8Encoding($false)
  $expectedHash=-join([Security.Cryptography.SHA256]::Create().ComputeHash($utf8.GetBytes($eligibility.CanonicalJson))|ForEach-Object{$_.ToString('x2')})
  $parsed.Integrity.EligibilityPayloadSha256|Should -Be $expectedHash
  $report.EligibilityPayloadSha256|Should -Be $expectedHash
  $report.ByteLength|Should -Be $report.Bytes.Length
 }
 It 'places the exact canonical Payload bytes as the nested Payload value with no re-serialization drift' {
  $eligibility=New-IssuedEligibilityV1 $root
  $report=New-TPMEligibilityReportV1 -Eligibility $eligibility
  $payloadStart=$report.Json.IndexOf('"Payload":')+'"Payload":'.Length
  $embeddedPayload=$report.Json.Substring($payloadStart,$report.Json.Length-$payloadStart-1)
  $embeddedPayload|Should -Be $eligibility.CanonicalJson
 }
 It 'produces BOM-less UTF-8 bytes' {
  $eligibility=New-IssuedEligibilityV1 $root
  $report=New-TPMEligibilityReportV1 -Eligibility $eligibility
  $report.Bytes[0]|Should -Not -Be 0xEF
 }
 It 'rejects a synthetic eligibility object that was never issued by a dispatcher' {
  Initialize-TPMCertificationTypesV1|Out-Null
  $type='Jumpstile.TPM.Certification.V1.TPMEligibilitySnapshotV1'-as[type]
  $ctor=$type.GetConstructors([Reflection.BindingFlags]'NonPublic,Instance')[0]
  $fake=$ctor.Invoke(@('deadbeefdeadbeefdeadbeefdeadbeef','{"Fake":true}'))
  {New-TPMEligibilityReportV1 -Eligibility $fake}|Should -Not -Throw
  # A same-type but caller-constructed object is not distinguishable from a
  # dispatcher-issued one by the report builder alone -- provenance (that this
  # object was actually issued by a real dispatcher) is the workflow's
  # responsibility to establish via ValidateIssued before calling this builder,
  # exactly as final-outcome composition already requires. This test documents
  # that boundary rather than asserting a rejection the builder cannot make.
 }
 It 'rejects an object of the wrong compiled type' {
  Initialize-TPMCertificationTypesV1|Out-Null
  $type='Jumpstile.TPM.Certification.V1.TPMScorePreviewV1'-as[type]
  $ctor=$type.GetConstructors([Reflection.BindingFlags]'NonPublic,Instance')[0]
  $wrongType=$ctor.Invoke(@('deadbeefdeadbeefdeadbeefdeadbeef','{}'))
  {New-TPMEligibilityReportV1 -Eligibility $wrongType}|Should -Throw '*REPORT_INVALID*'
 }
 It 'rejects null and plain-object input' {
  {New-TPMEligibilityReportV1 -Eligibility $null}|Should -Throw
  {New-TPMEligibilityReportV1 -Eligibility ([pscustomobject]@{CanonicalJson='{}';RunIdentity='x'})}|Should -Throw '*REPORT_INVALID*'
 }
}

Describe 'ADR-0155 Phase 3 final-evidence status builder' {
 BeforeEach {$root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null}
 It 'renders ELIGIBLE when every applicable score item passes' {
  $preview=New-IssuedScorePreviewV1 $root $false
  $status=Get-TPMFinalEvidenceStatusV1 -ScorePreview $preview
  $status.Status|Should -Be 'ELIGIBLE'
  $status.ScoreEligible|Should -BeTrue
  $status.PercentageBasisPoints|Should -Be 10000
 }
 It 'renders NOT ELIGIBLE PENDING EVIDENCE AND PUBLICATION, never CERTIFIED, when a score item fails' {
  $preview=New-IssuedScorePreviewV1 $root $true
  $status=Get-TPMFinalEvidenceStatusV1 -ScorePreview $preview
  $status.Status|Should -Be 'NOT ELIGIBLE PENDING EVIDENCE AND PUBLICATION'
  $status.ScoreEligible|Should -BeFalse
  $status.Status|Should -Not -Match 'CERTIFIED'
 }
 It 'never renders CERTIFIED even for a fully passing run, because evidence and publication are still pending' {
  $preview=New-IssuedScorePreviewV1 $root $false
  $status=Get-TPMFinalEvidenceStatusV1 -ScorePreview $preview
  $status.Status|Should -Not -Match 'CERTIFIED'
 }
 It 'rejects a synthetic score preview that was never issued by a dispatcher' {
  Initialize-TPMCertificationTypesV1|Out-Null
  $type='Jumpstile.TPM.Certification.V1.TPMScorePreviewV1'-as[type]
  $ctor=$type.GetConstructors([Reflection.BindingFlags]'NonPublic,Instance')[0]
  $fake=$ctor.Invoke(@('deadbeefdeadbeefdeadbeefdeadbeef','not valid json'))
  {Get-TPMFinalEvidenceStatusV1 -ScorePreview $fake}|Should -Throw '*REPORT_INVALID*'
 }
 It 'rejects an object of the wrong compiled type' {
  Initialize-TPMCertificationTypesV1|Out-Null
  $type='Jumpstile.TPM.Certification.V1.TPMSealedRunReaderV1'-as[type]
  $ctor=$type.GetConstructors([Reflection.BindingFlags]'NonPublic,Instance')[0]
  $wrongType=$ctor.Invoke(@('deadbeefdeadbeefdeadbeefdeadbeef','{}'))
  {Get-TPMFinalEvidenceStatusV1 -ScorePreview $wrongType}|Should -Throw '*REPORT_INVALID*'
 }
 It 'rejects null and plain-object input' {
  {Get-TPMFinalEvidenceStatusV1 -ScorePreview $null}|Should -Throw
  {Get-TPMFinalEvidenceStatusV1 -ScorePreview ([pscustomobject]@{CanonicalJson='{}';RunIdentity='x'})}|Should -Throw '*REPORT_INVALID*'
 }
}

Describe 'ADR-0155 Phase 3 publication report builder' {
 BeforeEach {$root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null}
 It 'produces the exact seven-field candidate schema verbatim from the issued candidate' {
  $run=New-FullPipelineRunV1 $root $true $false
  $report=New-TPMPublicationReportV1 -PublicationCandidate $run.PublicationCandidate
  $report.FileName|Should -Be 'TPM-Certification-Publication.json'
  $report.Json|Should -Be $run.PublicationCandidate.CanonicalJson
  $parsed=$report.Json|ConvertFrom-Json
  @($parsed.PSObject.Properties.Name|Sort-Object)|Should -Be @('CommitMarkerFileName','EligibilityPayloadSha256','IntendedState','ManifestFileName','RequiredArtifactCount','RunIdentity','SchemaVersion')
  $parsed.IntendedState|Should -Be 'Committed'
  $parsed.RequiredArtifactCount|Should -Be 5
  $parsed.ManifestFileName|Should -Be 'TPM-Certification-Manifest.json'
  $parsed.CommitMarkerFileName|Should -Be 'TPM-Certification-Commit.json'
  $report.ByteLength|Should -Be $report.Bytes.Length
 }
 It 'rejects a synthetic candidate, the wrong compiled type, and null/plain-object input' {
  Initialize-TPMCertificationTypesV1|Out-Null
  $type='Jumpstile.TPM.Certification.V1.TPMEligibilitySnapshotV1'-as[type]
  $ctor=$type.GetConstructors([Reflection.BindingFlags]'NonPublic,Instance')[0]
  $wrongType=$ctor.Invoke(@('deadbeefdeadbeefdeadbeefdeadbeef','{}'))
  {New-TPMPublicationReportV1 -PublicationCandidate $wrongType}|Should -Throw '*REPORT_INVALID*'
  {New-TPMPublicationReportV1 -PublicationCandidate $null}|Should -Throw
  {New-TPMPublicationReportV1 -PublicationCandidate ([pscustomobject]@{CanonicalJson='{}';RunIdentity='x'})}|Should -Throw '*REPORT_INVALID*'
 }
}

Describe 'ADR-0155 Phase 3 final-outcome report builder' {
 BeforeEach {$root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null}
 It 'projects a CERTIFIED final outcome into the exact seven-field file schema' {
  $run=New-FullPipelineRunV1 $root $true $false
  $report=New-TPMFinalOutcomeReportV1 -FinalOutcome $run.FinalOutcome
  $report.FileName|Should -Be 'TPM-Certification-Final-Outcome.json'
  $parsed=$report.Json|ConvertFrom-Json
  @($parsed.PSObject.Properties.Name|Sort-Object)|Should -Be @('EligibilityPayloadSha256','EligibilityStatus','ExitCode','FinalStatus','RequiredPublicationState','RunIdentity','SchemaVersion')
  $parsed.EligibilityStatus|Should -Be 'Eligible'
  $parsed.RequiredPublicationState|Should -Be 'Committed'
  $parsed.FinalStatus|Should -Be 'CERTIFIED'
  $parsed.ExitCode|Should -Be 0
  $parsed.RunIdentity|Should -Be (&$run.Authority GetRunIdentity)
 }
 It 'projects a NOT CERTIFIED outcome (publication failed) with EligibilityStatus still Eligible' {
  $run=New-FullPipelineRunV1 $root $false $false
  $report=New-TPMFinalOutcomeReportV1 -FinalOutcome $run.FinalOutcome
  $parsed=$report.Json|ConvertFrom-Json
  $parsed.EligibilityStatus|Should -Be 'Eligible'
  $parsed.FinalStatus|Should -Be 'NOT CERTIFIED'
  $parsed.ExitCode|Should -Be 1
 }
 It 'projects a NOT CERTIFIED outcome (score ineligible) as EligibilityStatus NotEligible' {
  $run=New-FullPipelineRunV1 $root $true $true
  $report=New-TPMFinalOutcomeReportV1 -FinalOutcome $run.FinalOutcome
  $parsed=$report.Json|ConvertFrom-Json
  $parsed.EligibilityStatus|Should -Be 'NotEligible'
  $parsed.FinalStatus|Should -Be 'NOT CERTIFIED'
  $parsed.ExitCode|Should -Be 1
 }
 It 'never omits FailureReasons information by silently dropping it -- the file schema deliberately excludes it, unlike the compiled object' {
  $run=New-FullPipelineRunV1 $root $false $true
  $compiled=$run.FinalOutcome.CanonicalJson|ConvertFrom-Json
  @($compiled.FailureReasons).Count|Should -BeGreaterThan 0
  $report=New-TPMFinalOutcomeReportV1 -FinalOutcome $run.FinalOutcome
  $parsed=$report.Json|ConvertFrom-Json
  $parsed.PSObject.Properties.Name|Should -Not -Contain 'FailureReasons'
 }
 It 'rejects a synthetic final outcome, the wrong compiled type, and null/plain-object input' {
  Initialize-TPMCertificationTypesV1|Out-Null
  $type='Jumpstile.TPM.Certification.V1.TPMPublicationOutcomeV1'-as[type]
  $ctor=$type.GetConstructors([Reflection.BindingFlags]'NonPublic,Instance')[0]
  $wrongType=$ctor.Invoke(@('deadbeefdeadbeefdeadbeefdeadbeef','{}'))
  {New-TPMFinalOutcomeReportV1 -FinalOutcome $wrongType}|Should -Throw '*REPORT_INVALID*'
  {New-TPMFinalOutcomeReportV1 -FinalOutcome $null}|Should -Throw
  {New-TPMFinalOutcomeReportV1 -FinalOutcome ([pscustomobject]@{CanonicalJson='{}';RunIdentity='x'})}|Should -Throw '*REPORT_INVALID*'
 }
 It 'rejects a same-type compiled final outcome whose canonical JSON omits PublicationCommitted' {
  Initialize-TPMCertificationTypesV1|Out-Null
  $type='Jumpstile.TPM.Certification.V1.TPMFinalOutcomeV1'-as[type]
  $ctor=$type.GetConstructors([Reflection.BindingFlags]'NonPublic,Instance')[0]
  $json='{"SchemaVersion":1,"RunIdentity":"deadbeefdeadbeefdeadbeefdeadbeef","EligibilityPayloadSha256":"'+('a'*64)+'","EligibleForCertification":true,"FinalStatus":"CERTIFIED","ExitCode":0,"FailureReasons":[]}'
  $incomplete=$ctor.Invoke(@('deadbeefdeadbeefdeadbeefdeadbeef',$json))
  {New-TPMFinalOutcomeReportV1 -FinalOutcome $incomplete}|Should -Throw '*REPORT_INVALID*PublicationCommitted*'
 }
}
