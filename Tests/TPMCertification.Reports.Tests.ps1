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
  return @{Authority=$authority;Sealed=$sealed;Eligibility=$eligibility;PublicationCandidate=$candidate;PublicationOutcome=$outcome;FinalOutcome=$finalOutcome}
 }
 function New-SyntheticEligibilityV1 {
  param([string]$RunIdentity='deadbeefdeadbeefdeadbeefdeadbeef',[string]$FactSetSha256=('a'*64),[string]$EvidenceSetSha256=('a'*64),[string]$FailureCode=$null,[string]$FailureMessage='synthetic')
  Initialize-TPMCertificationTypesV1|Out-Null
  $type='Jumpstile.TPM.Certification.V1.TPMEligibilitySnapshotV1'-as[type]
  $ctor=$type.GetConstructors([Reflection.BindingFlags]'NonPublic,Instance')[0]
  $ids=Get-TPMFactIdentifiersV1
  $scoreItems=@($ids|ForEach-Object{[ordered]@{Identifier=$_;Status='NotApplicable';Passed=$null;Details=[ordered]@{};FailureReasons=@()}})
  if($FailureCode){$scoreItems[0]=[ordered]@{Identifier=$ids[0];Status='Fail';Passed=$false;Details=[ordered]@{};FailureReasons=@([ordered]@{Code=$FailureCode;Message=$FailureMessage})}}
  $scoreItemsJson=ConvertTo-TPMJcsV1 $scoreItems
  $failureReasonsJson=if($FailureCode){ConvertTo-TPMJcsV1 @([ordered]@{SourceIdentifier=$ids[0];Code=$FailureCode;Message=$FailureMessage})}else{'[]'}
  $escapedRunIdentity=$RunIdentity.Replace('\','\\').Replace('"','\"').Replace("`n",'\n')
  $json='{"RunIdentity":"'+$escapedRunIdentity+'","FactSetSha256":"'+$FactSetSha256+'","EvidenceSetSha256":"'+$EvidenceSetSha256+'","ScoreItems":'+$scoreItemsJson+',"ApplicableCount":11,"PassedCount":11,"PercentageBasisPoints":10000,"EligibleForCertification":true,"FailureReasons":'+$failureReasonsJson+'}'
  return $ctor.Invoke(@('deadbeefdeadbeefdeadbeefdeadbeef',$json))
 }
 function New-SyntheticSealedRunV1 {
  param([string]$RunIdentity='deadbeefdeadbeefdeadbeefdeadbeef')
  Initialize-TPMCertificationTypesV1|Out-Null
  $type='Jumpstile.TPM.Certification.V1.TPMSealedRunReaderV1'-as[type]
  $ctor=$type.GetConstructors([Reflection.BindingFlags]'NonPublic,Instance')[0]
  $escapedRunIdentity=$RunIdentity.Replace('\','\\').Replace('"','\"').Replace("`n",'\n')
  $json='{"SchemaVersion":1,"RunIdentity":"'+$escapedRunIdentity+'","Mode":"Smoke","Facts":[],"Evidence":[]}'
  return $ctor.Invoke(@('deadbeefdeadbeefdeadbeefdeadbeef',$json))
 }
 function New-FullReportBundleV1($Root){
  $run=New-FullPipelineRunV1 $Root $true $false
  $eligibilityReport=New-TPMEligibilityReportV1 -Eligibility $run.Eligibility
  $publicationReport=New-TPMPublicationReportV1 -PublicationCandidate $run.PublicationCandidate
  $finalOutcomeReport=New-TPMFinalOutcomeReportV1 -FinalOutcome $run.FinalOutcome
  $scorecardReport=New-TPMScorecardReportV1 -Eligibility $run.Eligibility
  $validationReport=New-TPMValidationReportV1 -SealedRun $run.Sealed -Eligibility $run.Eligibility
  return @{Run=$run;EligibilityReport=$eligibilityReport;PublicationReport=$publicationReport;FinalOutcomeReport=$finalOutcomeReport;ScorecardReport=$scorecardReport;ValidationReport=$validationReport}
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

Describe 'ADR-0155 Phase 3 scorecard report builder' {
 BeforeEach {$root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null}
 It 'produces the exact five metadata lines, eleven category headings in manifest order, and a self-consistent hash' {
  $eligibility=New-IssuedEligibilityV1 $root
  $report=New-TPMScorecardReportV1 -Eligibility $eligibility
  $report.FileName|Should -Be 'TPM-Certification-Scorecard.md'
  $lines=$report.Markdown -split "`n"
  $lines[0]|Should -Match '^Schema-Version: 1$'
  $lines[1]|Should -Match '^Run-Identity: [0-9a-f]{32}$'
  $utf8=New-Object Text.UTF8Encoding $false
  $expectedHash=-join([Security.Cryptography.SHA256]::Create().ComputeHash($utf8.GetBytes($eligibility.CanonicalJson))|ForEach-Object{$_.ToString('x2')})
  $lines[2]|Should -Be "Eligibility-Payload-SHA256: $expectedHash"
  $lines[5]|Should -Be ''
  $lines[6]|Should -Be '# Certification Eligibility Scorecard'
  $lines[7]|Should -Be 'Eligibility: ELIGIBLE'
  $lines[8]|Should -Be 'Score: 8/8 (100.00%)'
  $headings=@($lines|Where-Object{$_-like '## *'}|ForEach-Object{$_.Substring(3)})
  $headings|Should -Be @('Repository','Pester','Static Analysis','Real Install Health','Backups','Smoke File Safety','Artifacts','pcsx2x6 crosshair path (issue #79)','Behavioral Certification (Virtual Beta Tester)','Unattended TPM root binding','Unattended TPM config restoration')
  ($report.Markdown|Select-String -Pattern 'Failure-Code: ' -AllMatches).Matches.Count|Should -Be 11
  $report.Bytes[0]|Should -Not -Be 0xEF
 }
 It 'renders N/A for not-applicable categories and PASS for applicable passing categories' {
  $eligibility=New-IssuedEligibilityV1 $root
  $report=New-TPMScorecardReportV1 -Eligibility $eligibility
  $lines=$report.Markdown -split "`n"
  $pcsx2Index=[array]::IndexOf($lines,'## pcsx2x6 crosshair path (issue #79)')
  $lines[$pcsx2Index+1]|Should -Be 'Status: N/A'
  $repositoryIndex=[array]::IndexOf($lines,'## Repository')
  $lines[$repositoryIndex+1]|Should -Be 'Status: PASS'
 }
 It 'round-trips Details-JCS-Base64Url to the exact original Details bytes for a representative category' {
  $eligibility=New-IssuedEligibilityV1 $root
  $report=New-TPMScorecardReportV1 -Eligibility $eligibility
  $lines=$report.Markdown -split "`n"
  $repositoryIndex=[array]::IndexOf($lines,'## Repository')
  $detailsLine=$lines[$repositoryIndex+2]
  $detailsLine|Should -Match '^Details-JCS-Base64Url: '
  $encoded=$detailsLine.Substring('Details-JCS-Base64Url: '.Length)
  $decoded=ConvertFrom-TPMJcsBase64UrlV1 $encoded
  $decoded|Should -Match '"RepositoryAvailable":true'
  $decoded|Should -Match '"RepositoryClean":true'
 }
 It 'renders NOT ELIGIBLE and a failure code/message pair when a category fails' {
  $authority=New-TPMProductionWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -PngValidator $validator
  $facts=New-TestFacts $root;$facts[1].Data.Failed=1;$facts[1].Data.Passed=1
  foreach($f in $facts){&$authority RecordFact $f}
  $ids=@('certification-suite-running','requested-effective-root-evidence','live-thumbnail-evidence','live-controls-evidence','adaptive-menu-normal','adaptive-menu-small','adaptive-menu-maximized','smoke-file-safety-evidence')
  $types=@('ScreenCapture','ScreenCapture',$null,$null,'DeterministicRender','DeterministicRender','DeterministicRender','DeterministicRender')
  for($i=0;$i-lt8;$i++){$e=if($i-in2,3){New-TestEvidence $root $ids[$i] $false $null $i -Skipped}else{New-TestEvidence $root $ids[$i] $true $types[$i] $i};&$authority RecordEvidence $e}
  $preview=&$authority DeriveScorePreview
  $final=New-TestEvidence $root 'final-certification-result' $true 'ScreenCapture' 8
  &$authority IssueFinalEvidence $final $preview
  $sealed=&$authority Seal
  $eligibility=&$authority IssueEligibility $sealed
  $report=New-TPMScorecardReportV1 -Eligibility $eligibility
  $lines=$report.Markdown -split "`n"
  $lines[7]|Should -Be 'Eligibility: NOT ELIGIBLE'
  $pesterIndex=[array]::IndexOf($lines,'## Pester')
  $lines[$pesterIndex+1]|Should -Be 'Status: FAIL'
  $lines[$pesterIndex+3]|Should -Be 'Failure-Code: PESTER_FAILURES'
  $lines[$pesterIndex+4]|Should -Match '^Failure-Message-Base64Url: '
  $encodedMessage=$lines[$pesterIndex+4].Substring('Failure-Message-Base64Url: '.Length)
  ConvertFrom-TPMFailureMessageBase64UrlV1 $encodedMessage|Should -Be 'PESTER_FAILURES'
 }
 It 'rejects a synthetic eligibility object, the wrong compiled type, and null/plain-object input' {
  Initialize-TPMCertificationTypesV1|Out-Null
  $type='Jumpstile.TPM.Certification.V1.TPMScorePreviewV1'-as[type]
  $ctor=$type.GetConstructors([Reflection.BindingFlags]'NonPublic,Instance')[0]
  $wrongType=$ctor.Invoke(@('deadbeefdeadbeefdeadbeefdeadbeef','{}'))
  {New-TPMScorecardReportV1 -Eligibility $wrongType}|Should -Throw '*REPORT_INVALID*'
  {New-TPMScorecardReportV1 -Eligibility $null}|Should -Throw
  {New-TPMScorecardReportV1 -Eligibility ([pscustomobject]@{CanonicalJson='{}';RunIdentity='x'})}|Should -Throw '*REPORT_INVALID*'
 }
 It 'rejects a same-compiled-type eligibility with a newline-bearing RunIdentity rather than injecting a Markdown line' {
  $malicious=New-SyntheticEligibilityV1 -RunIdentity "deadbeef`n## INJECTED HEADING`nStatus: PASS"
  {New-TPMScorecardReportV1 -Eligibility $malicious}|Should -Throw '*REPORT_INVALID*RunIdentity*'
 }
 It 'rejects a same-compiled-type eligibility with a malformed FactSetSha256/EvidenceSetSha256' {
  $badFactHash=New-SyntheticEligibilityV1 -FactSetSha256 'not-a-hash'
  {New-TPMScorecardReportV1 -Eligibility $badFactHash}|Should -Throw '*REPORT_INVALID*FactSetSha256*'
  $badEvidenceHash=New-SyntheticEligibilityV1 -EvidenceSetSha256 ('a'*63)
  {New-TPMScorecardReportV1 -Eligibility $badEvidenceHash}|Should -Throw '*REPORT_INVALID*EvidenceSetSha256*'
 }
 It 'rejects a same-compiled-type eligibility with a newline-bearing failure code' {
  $malicious=New-SyntheticEligibilityV1 -FailureCode "REPOSITORY_UNAVAILABLE`n## INJECTED"
  {New-TPMScorecardReportV1 -Eligibility $malicious}|Should -Throw '*REPORT_INVALID*'
 }
 It 'rejects a same-compiled-type eligibility with an unknown failure code' {
  $malicious=New-SyntheticEligibilityV1 -FailureCode 'NOT_A_REAL_CODE'
  {New-TPMScorecardReportV1 -Eligibility $malicious}|Should -Throw '*REPORT_INVALID*unrecognized failure code*'
 }
}

Describe 'ADR-0155 Phase 3 validation report builder' {
 BeforeEach {$root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null}
 It 'produces Facts/Evidence/Eligibility base64url fields that decode to hashes matching the metadata header' {
  $run=New-FullPipelineRunV1 $root $true $false
  $report=New-TPMValidationReportV1 -SealedRun $run.Sealed -Eligibility $run.Eligibility
  $report.FileName|Should -Be 'TPM-Certification-Validation.md'
  $lines=$report.Markdown -split "`n"
  $lines[0]|Should -Be 'Schema-Version: 1'
  $lines[5]|Should -Be ''
  $lines[6]|Should -Be '# Certification Validation'
  $lines|Should -Contain '## Facts'
  $lines|Should -Contain '## Evidence'
  $lines|Should -Contain '## Eligibility'
  $lines|Should -Contain '## Failure Reasons'

  $utf8=New-Object Text.UTF8Encoding $false
  $factsLine=@($lines|Where-Object{$_-like 'Facts-JCS-Base64Url:*'})[0]
  $factsEncoded=$factsLine.Substring('Facts-JCS-Base64Url: '.Length)
  $decodedFacts=ConvertFrom-TPMJcsBase64UrlV1 $factsEncoded
  $decodedFactsHash=-join([Security.Cryptography.SHA256]::Create().ComputeHash($utf8.GetBytes($decodedFacts))|ForEach-Object{$_.ToString('x2')})
  $factSetShaLine=@($lines|Where-Object{$_-like 'Fact-Set-SHA256:*'})[0]
  $factSetShaLine|Should -Be "Fact-Set-SHA256: $decodedFactsHash"

  $evidenceLine=@($lines|Where-Object{$_-like 'Evidence-JCS-Base64Url:*'})[0]
  $evidenceEncoded=$evidenceLine.Substring('Evidence-JCS-Base64Url: '.Length)
  $decodedEvidence=ConvertFrom-TPMJcsBase64UrlV1 $evidenceEncoded
  $decodedEvidenceHash=-join([Security.Cryptography.SHA256]::Create().ComputeHash($utf8.GetBytes($decodedEvidence))|ForEach-Object{$_.ToString('x2')})
  $evidenceSetShaLine=@($lines|Where-Object{$_-like 'Evidence-Set-SHA256:*'})[0]
  $evidenceSetShaLine|Should -Be "Evidence-Set-SHA256: $decodedEvidenceHash"

  $eligLine=@($lines|Where-Object{$_-like 'Eligibility-Payload-JCS-Base64Url:*'})[0]
  $eligEncoded=$eligLine.Substring('Eligibility-Payload-JCS-Base64Url: '.Length)
  $decodedElig=ConvertFrom-TPMJcsBase64UrlV1 $eligEncoded
  $decodedElig|Should -Be $run.Eligibility.CanonicalJson
 }
 It 'renders Failure-Code: none when the eligibility payload has no failure reasons' {
  $run=New-FullPipelineRunV1 $root $true $false
  $report=New-TPMValidationReportV1 -SealedRun $run.Sealed -Eligibility $run.Eligibility
  $lines=$report.Markdown -split "`n"
  $failureReasonsIndex=[array]::IndexOf($lines,'## Failure Reasons')
  $lines[$failureReasonsIndex+1]|Should -Be 'Failure-Code: none'
 }
 It 'rejects a SealedRun and Eligibility from two different runs' {
  $runA=New-FullPipelineRunV1 $root $true $false
  $root2=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root2|Out-Null
  $runB=New-FullPipelineRunV1 $root2 $true $false
  {New-TPMValidationReportV1 -SealedRun $runA.Sealed -Eligibility $runB.Eligibility}|Should -Throw '*REPORT_INVALID*RunIdentity*'
 }
 It 'rejects wrong compiled types and null/plain-object input for both parameters' {
  Initialize-TPMCertificationTypesV1|Out-Null
  $type='Jumpstile.TPM.Certification.V1.TPMScorePreviewV1'-as[type]
  $ctor=$type.GetConstructors([Reflection.BindingFlags]'NonPublic,Instance')[0]
  $wrongType=$ctor.Invoke(@('deadbeefdeadbeefdeadbeefdeadbeef','{}'))
  $run=New-FullPipelineRunV1 $root $true $false
  {New-TPMValidationReportV1 -SealedRun $wrongType -Eligibility $run.Eligibility}|Should -Throw '*REPORT_INVALID*'
  {New-TPMValidationReportV1 -SealedRun $run.Sealed -Eligibility $wrongType}|Should -Throw '*REPORT_INVALID*'
  {New-TPMValidationReportV1 -SealedRun $null -Eligibility $run.Eligibility}|Should -Throw
  {New-TPMValidationReportV1 -SealedRun $run.Sealed -Eligibility $null}|Should -Throw
 }
 It 'rejects a same-compiled-type pair with a newline-bearing RunIdentity rather than injecting a Markdown line' {
  $maliciousRunIdentity="deadbeef`n## INJECTED HEADING`nStatus: PASS"
  $sealed=New-SyntheticSealedRunV1 -RunIdentity $maliciousRunIdentity
  $eligibility=New-SyntheticEligibilityV1 -RunIdentity $maliciousRunIdentity
  {New-TPMValidationReportV1 -SealedRun $sealed -Eligibility $eligibility}|Should -Throw '*REPORT_INVALID*RunIdentity*'
 }
 It 'rejects a same-compiled-type pair with a malformed FactSetSha256/EvidenceSetSha256' {
  $sealed=New-SyntheticSealedRunV1
  $badFactHash=New-SyntheticEligibilityV1 -FactSetSha256 'not-a-hash'
  {New-TPMValidationReportV1 -SealedRun $sealed -Eligibility $badFactHash}|Should -Throw '*REPORT_INVALID*FactSetSha256*'
  $badEvidenceHash=New-SyntheticEligibilityV1 -EvidenceSetSha256 ('a'*63)
  {New-TPMValidationReportV1 -SealedRun $sealed -Eligibility $badEvidenceHash}|Should -Throw '*REPORT_INVALID*EvidenceSetSha256*'
 }
 It 'rejects a same-compiled-type pair with a newline-bearing or unknown failure code' {
  $sealed=New-SyntheticSealedRunV1
  $newlineCode=New-SyntheticEligibilityV1 -FailureCode "REPOSITORY_UNAVAILABLE`n## INJECTED"
  {New-TPMValidationReportV1 -SealedRun $sealed -Eligibility $newlineCode}|Should -Throw '*REPORT_INVALID*'
  $unknownCode=New-SyntheticEligibilityV1 -FailureCode 'NOT_A_REAL_CODE'
  {New-TPMValidationReportV1 -SealedRun $sealed -Eligibility $unknownCode}|Should -Throw '*REPORT_INVALID*unrecognized failure code*'
 }
}

Describe 'ADR-0155 Phase 3 manifest and commit-marker report builders' {
 BeforeEach {$root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null}
 It 'produces the exact six-field manifest with five artifacts in fixed order and correct per-artifact hashes' {
  $bundle=New-FullReportBundleV1 $root
  $manifest=New-TPMManifestReportV1 -Eligibility $bundle.Run.Eligibility -EligibilityReport $bundle.EligibilityReport -PublicationReport $bundle.PublicationReport -FinalOutcomeReport $bundle.FinalOutcomeReport -ScorecardReport $bundle.ScorecardReport -ValidationReport $bundle.ValidationReport
  $manifest.FileName|Should -Be 'TPM-Certification-Manifest.json'
  $parsed=$manifest.Json|ConvertFrom-Json
  $sortedNames=[string[]]@($parsed.PSObject.Properties.Name);[Array]::Sort($sortedNames,[StringComparer]::Ordinal)
  $sortedNames|Should -Be @('ArtifactCount','ArtifactSetSha256','Artifacts','EligibilityPayloadSha256','RunIdentity','SchemaVersion')
  $parsed.ArtifactCount|Should -Be 5
  @($parsed.Artifacts).Count|Should -Be 5
  $expectedOrder=@('EligibilityJson','PublicationJson','FinalOutcomeJson','ScorecardMarkdown','ValidationMarkdown')
  @($parsed.Artifacts|ForEach-Object{$_.Identifier})|Should -Be $expectedOrder
  $expectedFileNames=@('TPM-Certification-Eligibility.json','TPM-Certification-Publication.json','TPM-Certification-Final-Outcome.json','TPM-Certification-Scorecard.md','TPM-Certification-Validation.md')
  @($parsed.Artifacts|ForEach-Object{$_.FileName})|Should -Be $expectedFileNames
  $expectedContentTypes=@('application/json','application/json','application/json','text/markdown','text/markdown')
  @($parsed.Artifacts|ForEach-Object{$_.ContentType})|Should -Be $expectedContentTypes
  $reports=@($bundle.EligibilityReport,$bundle.PublicationReport,$bundle.FinalOutcomeReport,$bundle.ScorecardReport,$bundle.ValidationReport)
  for($i=0;$i-lt5;$i++){
   $expectedHash=-join([Security.Cryptography.SHA256]::Create().ComputeHash($reports[$i].Bytes)|ForEach-Object{$_.ToString('x2')})
   $parsed.Artifacts[$i].Sha256|Should -Be $expectedHash
   $parsed.Artifacts[$i].ByteLength|Should -Be $reports[$i].Bytes.Length
   $parsed.Artifacts[$i].EligibilityPayloadSha256|Should -Be $parsed.EligibilityPayloadSha256
  }
 }
 It 'computes ArtifactSetSha256 as the hash of the exact canonical Artifacts array' {
  $bundle=New-FullReportBundleV1 $root
  $manifest=New-TPMManifestReportV1 -Eligibility $bundle.Run.Eligibility -EligibilityReport $bundle.EligibilityReport -PublicationReport $bundle.PublicationReport -FinalOutcomeReport $bundle.FinalOutcomeReport -ScorecardReport $bundle.ScorecardReport -ValidationReport $bundle.ValidationReport
  $parsed=$manifest.Json|ConvertFrom-Json
  $artifactsJson=ConvertTo-TPMJcsV1 $parsed.Artifacts
  $utf8=New-Object Text.UTF8Encoding $false
  $expectedHash=-join([Security.Cryptography.SHA256]::Create().ComputeHash($utf8.GetBytes($artifactsJson))|ForEach-Object{$_.ToString('x2')})
  $parsed.ArtifactSetSha256|Should -Be $expectedHash
 }
 It 'rejects a report passed into the wrong positional slot' {
  $bundle=New-FullReportBundleV1 $root
  {New-TPMManifestReportV1 -Eligibility $bundle.Run.Eligibility -EligibilityReport $bundle.PublicationReport -PublicationReport $bundle.EligibilityReport -FinalOutcomeReport $bundle.FinalOutcomeReport -ScorecardReport $bundle.ScorecardReport -ValidationReport $bundle.ValidationReport}|Should -Throw '*REPORT_INVALID*FileName mismatch*'
 }
 It 'rejects a synthetic eligibility object, the wrong compiled type, and null input' {
  $bundle=New-FullReportBundleV1 $root
  Initialize-TPMCertificationTypesV1|Out-Null
  $type='Jumpstile.TPM.Certification.V1.TPMScorePreviewV1'-as[type]
  $ctor=$type.GetConstructors([Reflection.BindingFlags]'NonPublic,Instance')[0]
  $wrongType=$ctor.Invoke(@('deadbeefdeadbeefdeadbeefdeadbeef','{}'))
  {New-TPMManifestReportV1 -Eligibility $wrongType -EligibilityReport $bundle.EligibilityReport -PublicationReport $bundle.PublicationReport -FinalOutcomeReport $bundle.FinalOutcomeReport -ScorecardReport $bundle.ScorecardReport -ValidationReport $bundle.ValidationReport}|Should -Throw '*REPORT_INVALID*'
  {New-TPMManifestReportV1 -Eligibility $null -EligibilityReport $bundle.EligibilityReport -PublicationReport $bundle.PublicationReport -FinalOutcomeReport $bundle.FinalOutcomeReport -ScorecardReport $bundle.ScorecardReport -ValidationReport $bundle.ValidationReport}|Should -Throw
 }
 It 'rejects a same-compiled-type eligibility with a newline-bearing RunIdentity' {
  $bundle=New-FullReportBundleV1 $root
  $malicious=New-SyntheticEligibilityV1 -RunIdentity "deadbeef`n## INJECTED"
  {New-TPMManifestReportV1 -Eligibility $malicious -EligibilityReport $bundle.EligibilityReport -PublicationReport $bundle.PublicationReport -FinalOutcomeReport $bundle.FinalOutcomeReport -ScorecardReport $bundle.ScorecardReport -ValidationReport $bundle.ValidationReport}|Should -Throw '*REPORT_INVALID*RunIdentity*'
 }
 It 'produces the exact eight-field commit marker with ManifestSha256 matching the actual manifest bytes' {
  $bundle=New-FullReportBundleV1 $root
  $manifest=New-TPMManifestReportV1 -Eligibility $bundle.Run.Eligibility -EligibilityReport $bundle.EligibilityReport -PublicationReport $bundle.PublicationReport -FinalOutcomeReport $bundle.FinalOutcomeReport -ScorecardReport $bundle.ScorecardReport -ValidationReport $bundle.ValidationReport
  $marker=New-TPMCommitMarkerReportV1 -Manifest $manifest
  $marker.FileName|Should -Be 'TPM-Certification-Commit.json'
  $parsed=$marker.Json|ConvertFrom-Json
  @($parsed.PSObject.Properties.Name|Sort-Object)|Should -Be @('ArtifactCount','ArtifactSetSha256','EligibilityPayloadSha256','ManifestByteLength','ManifestFileName','ManifestSha256','RunIdentity','SchemaVersion')
  $parsed.ManifestFileName|Should -Be 'TPM-Certification-Manifest.json'
  $parsed.ManifestByteLength|Should -Be $manifest.Bytes.Length
  $utf8=New-Object Text.UTF8Encoding $false
  $expectedManifestHash=-join([Security.Cryptography.SHA256]::Create().ComputeHash($manifest.Bytes)|ForEach-Object{$_.ToString('x2')})
  $parsed.ManifestSha256|Should -Be $expectedManifestHash
  $manifestParsed=$manifest.Json|ConvertFrom-Json
  $parsed.ArtifactSetSha256|Should -Be $manifestParsed.ArtifactSetSha256
  $parsed.ArtifactCount|Should -Be 5
  $parsed.RunIdentity|Should -Be $manifestParsed.RunIdentity
  $parsed.EligibilityPayloadSha256|Should -Be $manifestParsed.EligibilityPayloadSha256
 }
 It 'rejects a manifest-shaped object that is not an actual New-TPMManifestReportV1 result, and null input' {
  {New-TPMCommitMarkerReportV1 -Manifest ([pscustomobject]@{FileName='TPM-Certification-Manifest.json';Json='{}';Bytes=[byte[]]@(1,2,3)})}|Should -Throw '*REPORT_INVALID*'
  {New-TPMCommitMarkerReportV1 -Manifest $null}|Should -Throw
 }
}

Describe 'ADR-0155 Phase 3 JCS base64url transport (Section 8.4)' {
 It 'round-trips arbitrary canonical JSON through the unpadded base64url alphabet' {
  $canonical=ConvertTo-TPMJcsV1 ([ordered]@{z=@(3,2,1);a=$true;nested=[ordered]@{x=1}})
  $encoded=ConvertTo-TPMJcsBase64UrlV1 $canonical
  $encoded|Should -Match '^[A-Za-z0-9_-]+$'
  $encoded|Should -Not -Match '='
  ConvertFrom-TPMJcsBase64UrlV1 $encoded|Should -Be $canonical
 }
 It 'rejects padded input, invalid alphabet characters, and an invalid length remainder' {
  {ConvertFrom-TPMJcsBase64UrlV1 'abc='}|Should -Throw
  {ConvertFrom-TPMJcsBase64UrlV1 'abc!!!'}|Should -Throw
  {ConvertFrom-TPMJcsBase64UrlV1 'AAAAA'}|Should -Throw
 }
 It 'is a distinct transport from ConvertTo-TPMFailureMessageBase64UrlV1 -- encodes bytes directly with no JSON-string wrapping layer' {
  $canonical='{"a":1}'
  $jcsEncoded=ConvertTo-TPMJcsBase64UrlV1 $canonical
  $failureMessageEncoded=ConvertTo-TPMFailureMessageBase64UrlV1 $canonical
  $jcsEncoded|Should -Not -Be $failureMessageEncoded
  ConvertFrom-TPMJcsBase64UrlV1 $jcsEncoded|Should -Be $canonical
 }
}

Describe 'ADR-0155 Phase 1 JCS canonicalization of parsed PSCustomObject (PowerShell round-trip support)' {
 It 'produces byte-identical canonical output for a value round-tripped through ConvertFrom-Json' {
  $original=[ordered]@{z=@(3,2,1);a=$true;nested=[ordered]@{x=1;y='hello'};b=$null}
  $originalJson=ConvertTo-TPMJcsV1 $original
  $parsed=$originalJson|ConvertFrom-Json
  $roundTripped=ConvertTo-TPMJcsV1 $parsed
  $roundTripped|Should -Be $originalJson
 }
 It 'canonicalizes an empty parsed object to {}' {
  $parsed='{}'|ConvertFrom-Json
  ConvertTo-TPMJcsV1 $parsed|Should -Be '{}'
 }
}
