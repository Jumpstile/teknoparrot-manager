#Requires -Module Pester
BeforeAll {
 $authorityModulePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Authority.psm1'
 Import-Module $authorityModulePath -Force
 $reportsModulePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Reports.psm1'
 Import-Module $reportsModulePath -Force
 $productionModulePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Production.psm1'
 Import-Module $productionModulePath -Force
 $modulePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Publication.psm1'
 Import-Module $modulePath -Force
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
 function New-FullPipelineRunV1($Root){
  $authority=New-TPMProductionWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $Root -PngValidator $validator
  foreach($fact in New-TestFacts $Root){&$authority RecordFact $fact}
  $ids=@('certification-suite-running','requested-effective-root-evidence','live-thumbnail-evidence','live-controls-evidence','adaptive-menu-normal','adaptive-menu-small','adaptive-menu-maximized','smoke-file-safety-evidence')
  $types=@('ScreenCapture','ScreenCapture',$null,$null,'DeterministicRender','DeterministicRender','DeterministicRender','DeterministicRender')
  for($i=0;$i-lt8;$i++){$e=if($i-in2,3){New-TestEvidence $Root $ids[$i] $false $null $i -Skipped}else{New-TestEvidence $Root $ids[$i] $true $types[$i] $i};&$authority RecordEvidence $e}
  $preview=&$authority DeriveScorePreview
  $final=New-TestEvidence $Root 'final-certification-result' $true 'ScreenCapture' 8
  &$authority IssueFinalEvidence $final $preview
  $sealed=&$authority Seal
  $eligibility=&$authority IssueEligibility $sealed
  $candidate=&$authority IssuePublicationCandidate $eligibility
  $observation=[ordered]@{ManifestSha256=('b'*64);ArtifactSetSha256=('c'*64);DiagnosticWarnings=@()}
  $outcome=&$authority RegisterCommittedPublication $observation $candidate
  $finalOutcome=&$authority IssueFinalOutcome $eligibility $outcome
  return @{Authority=$authority;Sealed=$sealed;Eligibility=$eligibility;PublicationCandidate=$candidate;PublicationOutcome=$outcome;FinalOutcome=$finalOutcome}
 }
 function New-FullBundleV1($Root){
  $run=New-FullPipelineRunV1 $Root
  $eligibilityReport=New-TPMEligibilityReportV1 -Eligibility $run.Eligibility
  $publicationReport=New-TPMPublicationReportV1 -PublicationCandidate $run.PublicationCandidate
  $finalOutcomeReport=New-TPMFinalOutcomeReportV1 -FinalOutcome $run.FinalOutcome
  $scorecardReport=New-TPMScorecardReportV1 -Eligibility $run.Eligibility
  $validationReport=New-TPMValidationReportV1 -SealedRun $run.Sealed -Eligibility $run.Eligibility
  $manifest=New-TPMManifestReportV1 -Eligibility $run.Eligibility -EligibilityReport $eligibilityReport -PublicationReport $publicationReport -FinalOutcomeReport $finalOutcomeReport -ScorecardReport $scorecardReport -ValidationReport $validationReport
  $marker=New-TPMCommitMarkerReportV1 -Manifest $manifest
  return @{Run=$run;EligibilityReport=$eligibilityReport;PublicationReport=$publicationReport;FinalOutcomeReport=$finalOutcomeReport;ScorecardReport=$scorecardReport;ValidationReport=$validationReport;Manifest=$manifest;Marker=$marker}
 }
 function Invoke-StagingV1($Bundle,[string]$StagingParentRoot){
  return New-TPMPublicationStagingV1 -StagingParentRoot $StagingParentRoot -EligibilityReport $Bundle.EligibilityReport -PublicationReport $Bundle.PublicationReport -FinalOutcomeReport $Bundle.FinalOutcomeReport -ScorecardReport $Bundle.ScorecardReport -ValidationReport $Bundle.ValidationReport -Manifest $Bundle.Manifest -Marker $Bundle.Marker
 }
}

Describe 'ADR-0155 Phase 3 publication staging builder' {
 BeforeEach {
  $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null
  $stagingParent=Join-Path $root 'staging';New-Item -ItemType Directory -Path $stagingParent|Out-Null
 }

 It 'writes exactly the seven canonical files, none overwritten, with byte-identical on-disk content and Committed=false' {
  $bundle=New-FullBundleV1 $root
  $staging=Invoke-StagingV1 $bundle $stagingParent
  $staging.FailureCode|Should -BeNullOrEmpty
  $staging.Committed|Should -Be $false
  $staging.Files.Count|Should -Be 7
  $onDisk=@(Get-ChildItem -LiteralPath $staging.StagingDirectory -File)
  $onDisk.Count|Should -Be 7
  $expectedNames=@('TPM-Certification-Eligibility.json','TPM-Certification-Publication.json','TPM-Certification-Final-Outcome.json','TPM-Certification-Scorecard.md','TPM-Certification-Validation.md','TPM-Certification-Manifest.json','TPM-Certification-Commit.json')
  @($staging.Files|ForEach-Object{$_.FileName})|Should -Be $expectedNames
  foreach($f in $staging.Files){
   $onDiskBytes=[IO.File]::ReadAllBytes($f.Path)
   $onDiskHash=Get-TPMSha256HexV1 -Bytes $onDiskBytes
   $sourceBytes=switch($f.Identifier){
    'EligibilityJson'{$bundle.EligibilityReport.Bytes}
    'PublicationJson'{$bundle.PublicationReport.Bytes}
    'FinalOutcomeJson'{$bundle.FinalOutcomeReport.Bytes}
    'ScorecardMarkdown'{$bundle.ScorecardReport.Bytes}
    'ValidationMarkdown'{$bundle.ValidationReport.Bytes}
    'Manifest'{$bundle.Manifest.Bytes}
    'Marker'{$bundle.Marker.Bytes}
   }
   $onDiskHash|Should -Be (Get-TPMSha256HexV1 -Bytes $sourceBytes)
  }
 }

 It 'stages under a deterministic RunIdentity-named directory' {
  $bundle=New-FullBundleV1 $root
  $staging=Invoke-StagingV1 $bundle $stagingParent
  $parsedManifest=$bundle.Manifest.Json|ConvertFrom-Json
  $staging.StagingDirectory|Should -Be (Join-Path ([IO.Path]::GetFullPath($stagingParent)) $parsedManifest.RunIdentity)
  $staging.RunIdentity|Should -Be $parsedManifest.RunIdentity
 }

 It 'never overwrites an existing artifact: re-staging the same run fails closed and leaves the original files untouched' {
  $bundle=New-FullBundleV1 $root
  $first=Invoke-StagingV1 $bundle $stagingParent
  $beforeHashes=@($first.Files|ForEach-Object{Get-TPMSha256HexV1 -Bytes ([IO.File]::ReadAllBytes($_.Path))})
  $second=Invoke-StagingV1 $bundle $stagingParent
  $second.Committed|Should -Be $false
  $second.FailureCode|Should -Be 'PROMOTION_FAILED'
  $second.FailureMessage|Should -Match 'PATH_ALREADY_EXISTS'
  $afterHashes=@($first.Files|ForEach-Object{Get-TPMSha256HexV1 -Bytes ([IO.File]::ReadAllBytes($_.Path))})
  $afterHashes|Should -Be $beforeHashes
  (Get-ChildItem -LiteralPath $first.StagingDirectory -File).Count|Should -Be 7
 }

 It 'rolls back only the files it wrote when a mid-bundle write collides with a pre-existing file, leaving the collider intact' {
  $bundle=New-FullBundleV1 $root
  $parsedManifest=$bundle.Manifest.Json|ConvertFrom-Json
  $runDir=Join-Path ([IO.Path]::GetFullPath($stagingParent)) $parsedManifest.RunIdentity
  New-Item -ItemType Directory -Path $runDir|Out-Null
  [IO.File]::WriteAllBytes((Join-Path $runDir 'TPM-Certification-Final-Outcome.json'),[byte[]](9,9,9))
  $staging=Invoke-StagingV1 $bundle $stagingParent
  $staging.Committed|Should -Be $false
  $staging.FailureCode|Should -Be 'PROMOTION_FAILED'
  $staging.FailureMessage|Should -Match 'TPM-Certification-Final-Outcome\.json'
  $remaining=@(Get-ChildItem -LiteralPath $runDir -File)
  $remaining.Count|Should -Be 1
  $remaining[0].Name|Should -Be 'TPM-Certification-Final-Outcome.json'
  [IO.File]::ReadAllBytes($remaining[0].FullName)|Should -Be ([byte[]](9,9,9))
 }

 It 'rolls back a freshly created empty staging directory entirely when the very first write fails' {
  $bundle=New-FullBundleV1 $root
  $parsedManifest=$bundle.Manifest.Json|ConvertFrom-Json
  $runDir=Join-Path ([IO.Path]::GetFullPath($stagingParent)) $parsedManifest.RunIdentity
  New-Item -ItemType Directory -Path $runDir|Out-Null
  [IO.File]::WriteAllBytes((Join-Path $runDir 'TPM-Certification-Eligibility.json'),[byte[]](9))
  $staging=Invoke-StagingV1 $bundle $stagingParent
  $staging.FailureCode|Should -Be 'PROMOTION_FAILED'
  Test-Path -LiteralPath $runDir|Should -Be $true
  (Get-ChildItem -LiteralPath $runDir -File).Count|Should -Be 1
 }

 It 'rejects a staging directory that already exists as a reparse point' {
  $bundle=New-FullBundleV1 $root
  $parsedManifest=$bundle.Manifest.Json|ConvertFrom-Json
  $runDir=Join-Path ([IO.Path]::GetFullPath($stagingParent)) $parsedManifest.RunIdentity
  $realTarget=Join-Path $root 'reparse-target';New-Item -ItemType Directory -Path $realTarget|Out-Null
  try{
   New-Item -ItemType SymbolicLink -Path $runDir -Target $realTarget -ErrorAction Stop|Out-Null
  }catch{
   Set-ItResult -Skipped -Because 'creating a symbolic link requires elevated privileges on this machine'
   return
  }
  $staging=Invoke-StagingV1 $bundle $stagingParent
  $staging.Committed|Should -Be $false
  $staging.FailureCode|Should -Be 'STAGING_FAILED'
  $staging.FailureMessage|Should -Match 'PATH_REPARSE_POINT'
 }

 It 'rejects when StagingParentRoot is relative, null, or whitespace' {
  $bundle=New-FullBundleV1 $root
  {Invoke-StagingV1 $bundle 'relative\path'}|Should -Throw '*PUBLISH_INVALID*absolute*'
  {Invoke-StagingV1 $bundle ' '}|Should -Throw '*PUBLISH_INVALID*'
  {Invoke-StagingV1 $bundle ''}|Should -Throw
  {Invoke-StagingV1 $bundle $null}|Should -Throw
 }

 It 'rejects a Manifest or Marker that is not the exact builder result, and null input' {
  $bundle=New-FullBundleV1 $root
  {New-TPMPublicationStagingV1 -StagingParentRoot $stagingParent -EligibilityReport $bundle.EligibilityReport -PublicationReport $bundle.PublicationReport -FinalOutcomeReport $bundle.FinalOutcomeReport -ScorecardReport $bundle.ScorecardReport -ValidationReport $bundle.ValidationReport -Manifest ([pscustomobject]@{FileName='TPM-Certification-Manifest.json';Json='{}';Bytes=[byte[]]@(1)}) -Marker $bundle.Marker}|Should -Throw '*PUBLISH_INVALID*'
  {New-TPMPublicationStagingV1 -StagingParentRoot $stagingParent -EligibilityReport $bundle.EligibilityReport -PublicationReport $bundle.PublicationReport -FinalOutcomeReport $bundle.FinalOutcomeReport -ScorecardReport $bundle.ScorecardReport -ValidationReport $bundle.ValidationReport -Manifest $bundle.Manifest -Marker ([pscustomobject]@{FileName='TPM-Certification-Commit.json';Json='{}';Bytes=[byte[]]@(1)})}|Should -Throw '*PUBLISH_INVALID*'
  {New-TPMPublicationStagingV1 -StagingParentRoot $stagingParent -EligibilityReport $bundle.EligibilityReport -PublicationReport $bundle.PublicationReport -FinalOutcomeReport $bundle.FinalOutcomeReport -ScorecardReport $bundle.ScorecardReport -ValidationReport $bundle.ValidationReport -Manifest $null -Marker $bundle.Marker}|Should -Throw
  {New-TPMPublicationStagingV1 -StagingParentRoot $stagingParent -EligibilityReport $bundle.EligibilityReport -PublicationReport $bundle.PublicationReport -FinalOutcomeReport $bundle.FinalOutcomeReport -ScorecardReport $bundle.ScorecardReport -ValidationReport $bundle.ValidationReport -Manifest $bundle.Manifest -Marker $null}|Should -Throw
 }

 It 'rejects a Manifest whose Bytes diverge from its own Json, and performs zero filesystem writes' {
  $bundle=New-FullBundleV1 $root
  $divergentBytes=[Text.Encoding]::UTF8.GetBytes('TAMPERED, NOT THE REAL MANIFEST JSON')
  $tamperedManifest=[pscustomobject]@{FileName=$bundle.Manifest.FileName;Json=$bundle.Manifest.Json;Bytes=$divergentBytes;ByteLength=$divergentBytes.Length}
  $tamperedMarker=New-TPMCommitMarkerReportV1 -Manifest $tamperedManifest
  {New-TPMPublicationStagingV1 -StagingParentRoot $stagingParent -EligibilityReport $bundle.EligibilityReport -PublicationReport $bundle.PublicationReport -FinalOutcomeReport $bundle.FinalOutcomeReport -ScorecardReport $bundle.ScorecardReport -ValidationReport $bundle.ValidationReport -Manifest $tamperedManifest -Marker $tamperedMarker}|Should -Throw '*PUBLISH_INVALID*Manifest.Bytes*BOM-less UTF-8*'
  (Get-ChildItem -LiteralPath $stagingParent -Recurse -File -ErrorAction SilentlyContinue).Count|Should -Be 0
 }

 It 'rejects a Marker whose Bytes diverge from its own Json, and performs zero filesystem writes' {
  $bundle=New-FullBundleV1 $root
  $divergentBytes=[Text.Encoding]::UTF8.GetBytes('TAMPERED, NOT THE REAL MARKER JSON')
  $tamperedMarker=[pscustomobject]@{FileName=$bundle.Marker.FileName;Json=$bundle.Marker.Json;Bytes=$divergentBytes;ByteLength=$divergentBytes.Length}
  {New-TPMPublicationStagingV1 -StagingParentRoot $stagingParent -EligibilityReport $bundle.EligibilityReport -PublicationReport $bundle.PublicationReport -FinalOutcomeReport $bundle.FinalOutcomeReport -ScorecardReport $bundle.ScorecardReport -ValidationReport $bundle.ValidationReport -Manifest $bundle.Manifest -Marker $tamperedMarker}|Should -Throw '*PUBLISH_INVALID*Marker.Bytes*BOM-less UTF-8*'
  (Get-ChildItem -LiteralPath $stagingParent -Recurse -File -ErrorAction SilentlyContinue).Count|Should -Be 0
 }

 It 'rejects a Manifest whose Bytes are a UTF-8-BOM-prefixed encoding of its own Json, and performs zero filesystem writes' {
  $bundle=New-FullBundleV1 $root
  $bomPrefixedBytes=[byte[]](@(0xEF,0xBB,0xBF)+[Text.Encoding]::UTF8.GetBytes($bundle.Manifest.Json))
  $tamperedManifest=[pscustomobject]@{FileName=$bundle.Manifest.FileName;Json=$bundle.Manifest.Json;Bytes=$bomPrefixedBytes;ByteLength=$bomPrefixedBytes.Length}
  $tamperedMarker=New-TPMCommitMarkerReportV1 -Manifest $tamperedManifest
  {New-TPMPublicationStagingV1 -StagingParentRoot $stagingParent -EligibilityReport $bundle.EligibilityReport -PublicationReport $bundle.PublicationReport -FinalOutcomeReport $bundle.FinalOutcomeReport -ScorecardReport $bundle.ScorecardReport -ValidationReport $bundle.ValidationReport -Manifest $tamperedManifest -Marker $tamperedMarker}|Should -Throw '*PUBLISH_INVALID*Manifest.Bytes*BOM-less UTF-8*'
  (Get-ChildItem -LiteralPath $stagingParent -Recurse -File -ErrorAction SilentlyContinue).Count|Should -Be 0
 }

 It 'rejects a Manifest whose Bytes have a trailing byte appended after its own correctly encoded Json, and performs zero filesystem writes' {
  $bundle=New-FullBundleV1 $root
  $trailingByteBytes=[byte[]]([Text.Encoding]::UTF8.GetBytes($bundle.Manifest.Json)+[byte[]](0x0A))
  $tamperedManifest=[pscustomobject]@{FileName=$bundle.Manifest.FileName;Json=$bundle.Manifest.Json;Bytes=$trailingByteBytes;ByteLength=$trailingByteBytes.Length}
  $tamperedMarker=New-TPMCommitMarkerReportV1 -Manifest $tamperedManifest
  {New-TPMPublicationStagingV1 -StagingParentRoot $stagingParent -EligibilityReport $bundle.EligibilityReport -PublicationReport $bundle.PublicationReport -FinalOutcomeReport $bundle.FinalOutcomeReport -ScorecardReport $bundle.ScorecardReport -ValidationReport $bundle.ValidationReport -Manifest $tamperedManifest -Marker $tamperedMarker}|Should -Throw '*PUBLISH_INVALID*Manifest.Bytes*BOM-less UTF-8*'
  (Get-ChildItem -LiteralPath $stagingParent -Recurse -File -ErrorAction SilentlyContinue).Count|Should -Be 0
 }

 It 'rejects a Marker whose Bytes are a UTF-8-BOM-prefixed encoding of its own Json, and performs zero filesystem writes' {
  $bundle=New-FullBundleV1 $root
  $bomPrefixedBytes=[byte[]](@(0xEF,0xBB,0xBF)+[Text.Encoding]::UTF8.GetBytes($bundle.Marker.Json))
  $tamperedMarker=[pscustomobject]@{FileName=$bundle.Marker.FileName;Json=$bundle.Marker.Json;Bytes=$bomPrefixedBytes;ByteLength=$bomPrefixedBytes.Length}
  {New-TPMPublicationStagingV1 -StagingParentRoot $stagingParent -EligibilityReport $bundle.EligibilityReport -PublicationReport $bundle.PublicationReport -FinalOutcomeReport $bundle.FinalOutcomeReport -ScorecardReport $bundle.ScorecardReport -ValidationReport $bundle.ValidationReport -Manifest $bundle.Manifest -Marker $tamperedMarker}|Should -Throw '*PUBLISH_INVALID*Marker.Bytes*BOM-less UTF-8*'
  (Get-ChildItem -LiteralPath $stagingParent -Recurse -File -ErrorAction SilentlyContinue).Count|Should -Be 0
 }

 It 'rejects a Marker whose Bytes have a trailing byte appended after its own correctly encoded Json, and performs zero filesystem writes' {
  $bundle=New-FullBundleV1 $root
  $trailingByteBytes=[byte[]]([Text.Encoding]::UTF8.GetBytes($bundle.Marker.Json)+[byte[]](0x0A))
  $tamperedMarker=[pscustomobject]@{FileName=$bundle.Marker.FileName;Json=$bundle.Marker.Json;Bytes=$trailingByteBytes;ByteLength=$trailingByteBytes.Length}
  {New-TPMPublicationStagingV1 -StagingParentRoot $stagingParent -EligibilityReport $bundle.EligibilityReport -PublicationReport $bundle.PublicationReport -FinalOutcomeReport $bundle.FinalOutcomeReport -ScorecardReport $bundle.ScorecardReport -ValidationReport $bundle.ValidationReport -Manifest $bundle.Manifest -Marker $tamperedMarker}|Should -Throw '*PUBLISH_INVALID*Marker.Bytes*BOM-less UTF-8*'
  (Get-ChildItem -LiteralPath $stagingParent -Recurse -File -ErrorAction SilentlyContinue).Count|Should -Be 0
 }

 It 'rejects a Marker whose ManifestSha256 does not correlate to the supplied Manifest bytes' {
  $bundleA=New-FullBundleV1 $root
  $root2=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root2|Out-Null
  $bundleB=New-FullBundleV1 $root2
  {New-TPMPublicationStagingV1 -StagingParentRoot $stagingParent -EligibilityReport $bundleA.EligibilityReport -PublicationReport $bundleA.PublicationReport -FinalOutcomeReport $bundleA.FinalOutcomeReport -ScorecardReport $bundleA.ScorecardReport -ValidationReport $bundleA.ValidationReport -Manifest $bundleA.Manifest -Marker $bundleB.Marker}|Should -Throw '*PUBLISH_INVALID*'
 }

 It 'rejects when a supplied report argument does not match the bytes the Manifest already recorded for it' {
  $bundleA=New-FullBundleV1 $root
  $root2=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root2|Out-Null
  $bundleB=New-FullBundleV1 $root2
  {New-TPMPublicationStagingV1 -StagingParentRoot $stagingParent -EligibilityReport $bundleB.EligibilityReport -PublicationReport $bundleA.PublicationReport -FinalOutcomeReport $bundleA.FinalOutcomeReport -ScorecardReport $bundleA.ScorecardReport -ValidationReport $bundleA.ValidationReport -Manifest $bundleA.Manifest -Marker $bundleA.Marker}|Should -Throw '*PUBLISH_INVALID*'
 }

 It 'produces no staging output and performs no filesystem writes when pre-flight correlation validation fails' {
  $bundleA=New-FullBundleV1 $root
  $root2=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root2|Out-Null
  $bundleB=New-FullBundleV1 $root2
  {New-TPMPublicationStagingV1 -StagingParentRoot $stagingParent -EligibilityReport $bundleB.EligibilityReport -PublicationReport $bundleA.PublicationReport -FinalOutcomeReport $bundleA.FinalOutcomeReport -ScorecardReport $bundleA.ScorecardReport -ValidationReport $bundleA.ValidationReport -Manifest $bundleA.Manifest -Marker $bundleA.Marker}|Should -Throw
  (Get-ChildItem -LiteralPath $stagingParent -Recurse -File -ErrorAction SilentlyContinue).Count|Should -Be 0
 }
}
