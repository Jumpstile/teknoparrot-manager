#Requires -Module Pester
BeforeAll {
 $modulePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Shadow.psm1'
 Import-Module $modulePath -Force
 Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Execution.psm1') -Force
 function New-TestFacts([string]$Root,[string]$Mode='Smoke'){
  $hash='a'*64;$repo=[IO.Path]::GetFullPath((Join-Path $Root 'repo'));$report=[IO.Path]::GetFullPath((Join-Path $Root 'report'));$backup=[IO.Path]::GetFullPath((Join-Path $Root 'backup'))
  @(
   [ordered]@{Identifier='Repository';Applicable=$true;Data=[ordered]@{RepositoryPath=$repo;RepositoryAvailable=$true;RepositoryClean=$true;GitStatus='(clean)'}}
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
 function Add-TestManifest($Authority,[string]$Root,[string]$Mode='Smoke'){
  foreach($fact in New-TestFacts $Root $Mode){&$Authority RecordFact $fact}
  $manifest=@(
   @('certification-suite-running',$true,'ScreenCapture'),@('requested-effective-root-evidence',$true,'ScreenCapture'),
   @('live-thumbnail-evidence',$false,$null),@('live-controls-evidence',$false,$null),
   @('adaptive-menu-normal',$true,'DeterministicRender'),@('adaptive-menu-small',$true,'DeterministicRender'),
   @('adaptive-menu-maximized',$true,'DeterministicRender'),@('smoke-file-safety-evidence',$true,'DeterministicRender'))
  for($i=0;$i-lt$manifest.Count;$i++){if($i-in2,3){$e=New-TestEvidence $Root $manifest[$i][0] $false $null $i -Skipped}else{$e=New-TestEvidence $Root $manifest[$i][0] $true $manifest[$i][2] $i};&$Authority RecordEvidence $e}
 }
 $validator={param($Path)[pscustomobject]@{Valid=$true;Reason='test PNG';Width=1;Height=1}}
}

Describe 'ADR-0155 Phase 2 authority transaction' {
 BeforeEach {$root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null;$authority=New-TPMShadowWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -PngValidator $validator}
 It 'enforces repository-relative encoding paths, InjectionHunter counts, report containment, and no-config restoration' {
  $facts=New-TestFacts $root;$facts[2].Data.Encoding.Files=@('..\bad.ps1');$a=New-TPMShadowWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -PngValidator $validator;&$a RecordFact $facts[0];&$a RecordFact $facts[1];{&$a RecordFact $facts[2]}|Should -Throw '*normalized repository-relative*'
  $facts=New-TestFacts $root;$facts[2].Data.InjectionHunter.FindingCount=1;$facts[2].Data.InjectionHunter.UnresolvedFindingCount=0;$facts[2].Data.InjectionHunter.Dispositions=@([ordered]@{FindingIdentifier='one';Disposition='Confirmed'});$a=New-TPMShadowWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -PngValidator $validator;&$a RecordFact $facts[0];&$a RecordFact $facts[1];{&$a RecordFact $facts[2]}|Should -Throw '*IH unresolved count*'
  $facts=New-TestFacts $root;$facts[6].Data.ReportDirectory=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName($root)) 'escaped-report'));$a=New-TPMShadowWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -PngValidator $validator;for($i=0;$i-lt6;$i++){&$a RecordFact $facts[$i]};{&$a RecordFact $facts[6]}|Should -Throw '*ReportDirectory is not contained*'
  $facts=New-TestFacts $root 'Unattended';$facts[10].Data.TemporaryConfigCreated=$false;$a=New-TPMShadowWorkflowAuthorityV1 -Mode Unattended -EvidenceRoot $root -PngValidator $validator;foreach($fact in $facts){&$a RecordFact $fact};$preview=&$a DeriveScorePreview;$preview.CanonicalJson|Should -Match 'TEMP_CONFIG_NOT_REMOVED'
 }
 It 'records the exact manifests, issues final evidence, and seals to one immutable reader' {Add-TestManifest $authority $root;$preview=&$authority DeriveScorePreview;$final=New-TestEvidence $root 'final-certification-result' $true 'ScreenCapture' 8;&$authority IssueFinalEvidence $final $preview;&$authority GetPhase|Should -Be 'FinalEvidenceIssued';$reader=&$authority Seal;&$authority GetPhase|Should -Be 'Sealed';$reader.GetType().Name|Should -Be 'TPMSealedRunReaderV1';(&$authority ValidateIssued $reader 'SealedRun')|Should -BeTrue;$reader.CanonicalJson|Should -Match '"Facts":\[';$reader.CanonicalJson|Should -Match '"Evidence":\['}
 It 'rejects missing, duplicate, reordered, and post-seal facts' {{$facts=New-TestFacts $root;$bad=$facts[1];&$authority RecordFact $bad}|Should -Throw '*FACT_ORDER_INVALID*';$authority=New-TPMShadowWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -PngValidator $validator;$facts=New-TestFacts $root;foreach($f in $facts){&$authority RecordFact $f};{&$authority RecordFact $facts[10]}|Should -Throw '*FACT_DUPLICATE*';$preview=&$authority DeriveScorePreview;for($i=0;$i-lt8;$i++){$ids=@('certification-suite-running','requested-effective-root-evidence','live-thumbnail-evidence','live-controls-evidence','adaptive-menu-normal','adaptive-menu-small','adaptive-menu-maximized','smoke-file-safety-evidence');$types=@('ScreenCapture','ScreenCapture',$null,$null,'DeterministicRender','DeterministicRender','DeterministicRender','DeterministicRender');$e=if($i-in2,3){New-TestEvidence $root $ids[$i] $false $null $i -Skipped}else{New-TestEvidence $root $ids[$i] $true $types[$i] $i};&$authority RecordEvidence $e};$final=New-TestEvidence $root 'final-certification-result' $true 'ScreenCapture' 8;&$authority IssueFinalEvidence $final $preview;&$authority Seal|Out-Null;{&$authority RecordFact $facts[0]}|Should -Throw '*ILLEGAL_PHASE*'}
 It 'rejects synthetic and cross-run score previews' {Add-TestManifest $authority $root;$preview=&$authority DeriveScorePreview;$type='Jumpstile.TPM.Certification.V1.TPMScorePreviewV1'-as[type];$ctor=$type.GetConstructors([Reflection.BindingFlags]'NonPublic,Instance')[0];$fake=$ctor.Invoke(@($preview.RunIdentity,$preview.CanonicalJson));$final=New-TestEvidence $root 'final-certification-result' $true 'ScreenCapture' 8;{&$authority IssueFinalEvidence $final $fake}|Should -Throw '*PROVENANCE_INVALID*';$other=New-TPMShadowWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -PngValidator $validator;foreach($f in New-TestFacts $root){&$other RecordFact $f};$otherPreview=&$other DeriveScorePreview;{&$authority IssueFinalEvidence $final $otherPreview}|Should -Throw '*PROVENANCE_INVALID*'}
 It 'issues one preview and consumes it only after valid final evidence' {Add-TestManifest $authority $root;$preview=&$authority DeriveScorePreview;{&$authority DeriveScorePreview}|Should -Throw '*DUPLICATE_ISSUANCE*';$bad=New-TestEvidence $root 'final-certification-result' $true 'ScreenCapture' 8;$bad.FileSha256='b'*64;{&$authority IssueFinalEvidence $bad $preview}|Should -Throw '*EVIDENCE_HASH_FAILED*';$good=New-TestEvidence $root 'final-certification-result' $true 'ScreenCapture' 9;&$authority IssueFinalEvidence $good $preview;&$authority GetPhase|Should -Be 'FinalEvidenceIssued'}
 It 'takes a defensive copy before caller mutation and destroys builders at seal' {$facts=New-TestFacts $root;foreach($f in $facts){&$authority RecordFact $f};$facts[0].Data.GitStatus='mutated';$ids=@('certification-suite-running','requested-effective-root-evidence','live-thumbnail-evidence','live-controls-evidence','adaptive-menu-normal','adaptive-menu-small','adaptive-menu-maximized','smoke-file-safety-evidence');$types=@('ScreenCapture','ScreenCapture',$null,$null,'DeterministicRender','DeterministicRender','DeterministicRender','DeterministicRender');for($i=0;$i-lt8;$i++){$e=if($i-in2,3){New-TestEvidence $root $ids[$i] $false $null $i -Skipped}else{New-TestEvidence $root $ids[$i] $true $types[$i] $i};&$authority RecordEvidence $e};$preview=&$authority DeriveScorePreview;$final=New-TestEvidence $root 'final-certification-result' $true 'ScreenCapture' 8;&$authority IssueFinalEvidence $final $preview;$reader=&$authority Seal;$reader.CanonicalJson|Should -Not -Match 'mutated';{&$authority DeriveScorePreview}|Should -Throw '*ILLEGAL_PHASE*'}
}

Describe 'ADR-0155 Phase 2 evidence manifest' {
 BeforeEach {$root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null;$authority=New-TPMShadowWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -PngValidator $validator;foreach($f in New-TestFacts $root){&$authority RecordFact $f}}
 It 'rejects reordered identifiers and duplicate paths' {$wrong=New-TestEvidence $root 'requested-effective-root-evidence' $true 'ScreenCapture' 0;{&$authority RecordEvidence $wrong}|Should -Throw '*EVIDENCE_ORDER_INVALID*';$authority=New-TPMShadowWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -PngValidator $validator;foreach($f in New-TestFacts $root){&$authority RecordFact $f};$first=New-TestEvidence $root 'certification-suite-running' $true 'ScreenCapture' 0;&$authority RecordEvidence $first;$second=[ordered]@{};foreach($key in $first.Keys){$second[$key]=$first[$key]};$second.Identifier='requested-effective-root-evidence';{&$authority RecordEvidence $second}|Should -Throw '*EVIDENCE_PATH_DUPLICATE*'}
 It 'rejects hash, dimensions, escaped path, and required-skip failures' {$e=New-TestEvidence $root 'certification-suite-running' $true 'ScreenCapture' 0;$e.FileSha256='b'*64;{&$authority RecordEvidence $e}|Should -Throw '*EVIDENCE_HASH_FAILED*';$authority=New-TPMShadowWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -PngValidator $validator;foreach($f in New-TestFacts $root){&$authority RecordFact $f};$e=New-TestEvidence $root 'certification-suite-running' $true 'ScreenCapture' 1;$e.Width=2;{&$authority RecordEvidence $e}|Should -Throw '*EVIDENCE_DIMENSIONS_INVALID*'}
 It 'maps validator exceptions and locked files to authoritative evidence failures' {$throwing={param($Path)throw 'decoder exploded'};$a=New-TPMShadowWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -PngValidator $throwing;foreach($f in New-TestFacts $root){&$a RecordFact $f};$e=New-TestEvidence $root 'certification-suite-running' $true 'ScreenCapture' 0;{&$a RecordEvidence $e}|Should -Throw '*EVIDENCE_CAPTURE_EXCEPTION*';$a=New-TPMShadowWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -PngValidator $validator;foreach($f in New-TestFacts $root){&$a RecordFact $f};$e=New-TestEvidence $root 'certification-suite-running' $true 'ScreenCapture' 1;$lock=[IO.File]::Open($e.Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None);try{{&$a RecordEvidence $e}|Should -Throw '*EVIDENCE_FILE_LOCKED*'}finally{$lock.Dispose()}}
 It 'does not claim path ownership until the evidence record is fully valid' {$e=New-TestEvidence $root 'certification-suite-running' $true 'ScreenCapture' 0;$goodHash=$e.FileSha256;$e.FileSha256='b'*64;{&$authority RecordEvidence $e}|Should -Throw '*EVIDENCE_HASH_FAILED*';$e.FileSha256=$goodHash;{&$authority RecordEvidence $e}|Should -Not -Throw}
 It 'maps escaped and malformed paths to authoritative evidence codes' {$outside=Join-Path ([IO.Path]::GetDirectoryName($root)) 'outside.png';[IO.File]::WriteAllBytes($outside,[byte[]](1));$e=New-TestEvidence $root 'certification-suite-running' $true 'ScreenCapture' 0;$e.Path=[IO.Path]::GetFullPath($outside);{&$authority RecordEvidence $e}|Should -Throw '*EVIDENCE_PATH_OUTSIDE_ROOT*';$authority=New-TPMShadowWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -PngValidator $validator;foreach($f in New-TestFacts $root){&$authority RecordFact $f};$e=New-TestEvidence $root 'certification-suite-running' $true 'ScreenCapture' 1;$e.Path=$e.Path+'\\..';{&$authority RecordEvidence $e}|Should -Throw '*EVIDENCE_PATH_INVALID*'}
 It 'does not allow a failed optional record or failed final record to seal' {$authority=New-TPMShadowWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -PngValidator $validator;Add-TestManifest $authority $root;$preview=&$authority DeriveScorePreview;$failed=[ordered]@{Identifier='final-certification-result';Status='Failed';EvidenceType=$null;Required=$true;Path=$null;CaptureScope=$null;FileSha256=$null;Width=$null;Height=$null;FailureCode='EVIDENCE_CAPTURE_EXCEPTION';FailureMessage='capture failed'};&$authority IssueFinalEvidence $failed $preview;{&$authority Seal}|Should -Throw '*EVIDENCE_REQUIRED_FAILED*'}
}
Describe 'ADR-0155 Phase 2 shadow comparison' {
 BeforeEach {$root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null}
 It 'runs the shadow authority without changing legacy inputs and persists zero-divergence evidence' {
  $facts=New-TestFacts $root;$source=New-TPMShadowWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -PngValidator $validator
  foreach($fact in $facts){&$source RecordFact $fact};$sourcePreview=&$source DeriveScorePreview;$sourceValue=$sourcePreview.CanonicalJson|ConvertFrom-Json
  $legacyItems=@($sourceValue.ScoreItems|ForEach-Object{[pscustomobject]@{Area=$_.Identifier;Status=$_.Status;Passed=$_.Passed}})
  $ids=@('certification-suite-running','requested-effective-root-evidence','live-thumbnail-evidence','live-controls-evidence','adaptive-menu-normal','adaptive-menu-small','adaptive-menu-maximized','smoke-file-safety-evidence','final-certification-result');$types=@('ScreenCapture','ScreenCapture',$null,$null,'DeterministicRender','DeterministicRender','DeterministicRender','DeterministicRender','ScreenCapture')
  $legacy=for($i=0;$i-lt9;$i++){if($i-in2,3){[pscustomobject]@{Name=$ids[$i];Status='Skipped';EvidenceType='Skipped';Path=$null;CaptureScope=$null;Details='not displayed'}}else{$e=New-TestEvidence $root $ids[$i] $true $types[$i] ($i+20);[pscustomobject]@{Name=$e.Identifier;Status=$e.Status;EvidenceType=$e.EvidenceType;Path=$e.Path;CaptureScope=$(if($e.EvidenceType-eq'ScreenCapture'){'Window'}else{$null});Details=$null}}}
  $snapshot=$legacyItems|ConvertTo-Json -Depth 5;$path=Join-Path $root 'shadow.json';$result=Invoke-TPMShadowCertificationV1 -Mode Smoke -EvidenceRoot $root -FactRecords $facts -LegacyEvidence $legacy -LegacyScoreItems $legacyItems -DiagnosticPath $path -PngValidator $validator
  $result.Phase|Should -Be 'Sealed';$result.MigrationEligible|Should -BeTrue;@($result.Divergences).Count|Should -Be 0;(Test-Path -LiteralPath $path)|Should -BeTrue;($legacyItems|ConvertTo-Json -Depth 5)|Should -BeExactly $snapshot
 }
 It 'records field-level divergence and excludes the run from migration evidence' {
  $facts=New-TestFacts $root;$source=New-TPMShadowWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -PngValidator $validator;foreach($fact in $facts){&$source RecordFact $fact};$sourcePreview=&$source DeriveScorePreview;$items=@(($sourcePreview.CanonicalJson|ConvertFrom-Json).ScoreItems|ForEach-Object{[pscustomobject]@{Area=$_.Identifier;Status=$_.Status;Passed=$_.Passed}});$items[0].Passed=$false;$items[0].Status='Fail'
  $ids=@('certification-suite-running','requested-effective-root-evidence','live-thumbnail-evidence','live-controls-evidence','adaptive-menu-normal','adaptive-menu-small','adaptive-menu-maximized','smoke-file-safety-evidence','final-certification-result');$types=@('ScreenCapture','ScreenCapture',$null,$null,'DeterministicRender','DeterministicRender','DeterministicRender','DeterministicRender','ScreenCapture');$legacy=for($i=0;$i-lt9;$i++){if($i-in2,3){[pscustomobject]@{Name=$ids[$i];Status='Skipped';EvidenceType='Skipped';Path=$null;CaptureScope=$null;Details='not displayed'}}else{$e=New-TestEvidence $root $ids[$i] $true $types[$i] ($i+40);[pscustomobject]@{Name=$e.Identifier;Status=$e.Status;EvidenceType=$e.EvidenceType;Path=$e.Path;CaptureScope=$(if($e.EvidenceType-eq'ScreenCapture'){'Window'}else{$null});Details=$null}}}
  $result=Invoke-TPMShadowCertificationV1 -Mode Smoke -EvidenceRoot $root -FactRecords $facts -LegacyEvidence $legacy -LegacyScoreItems $items -DiagnosticPath (Join-Path $root 'divergent.json') -PngValidator $validator
  $result.MigrationEligible|Should -BeFalse;@($result.Divergences|Where-Object{$_.Path-eq'ScoreItems[0].Status'}).Count|Should -Be 1
 }
}
Describe 'ADR-0155 Phase 2 legacy observation adapter' {
 It 'emits the exact eleven raw fact identifiers without changing legacy results' {
  $root=Join-Path $TestDrive 'adapter';$repo=Join-Path $root 'repo';$report=Join-Path $root 'report';$backup=Join-Path $root 'backup';New-Item -ItemType Directory -Path $repo,(Join-Path $repo 'Tests'),$report,(Join-Path $backup 'UserProfiles') -Force|Out-Null;[IO.File]::WriteAllText((Join-Path $repo 'Tests\one.ps1'),'test')
  $zero=[pscustomobject]@{Added=0;Removed=0;Changed=0;BeforeSkipped=0;AfterSkipped=0};$results=[pscustomobject]@{SmokeMode=$true;Checks=@([pscustomobject]@{Name='Repository available';Passed=$true;Details='fixture repository is available'});GitStatus='(clean)';Pester=[pscustomobject]@{Total=2;Passed=2;Failed=0;Skipped=0;NotRun=0};PesterVersion='5.7.1';PowerShellVersion='7.6.3';PSScriptAnalyzerFindings=0;PSScriptAnalyzerVersion='1.24.0';Backup=[pscustomobject]@{UserProfiles=$true;GameProfiles=$false};Snapshots=[ordered]@{UserProfiles=$zero;GameProfiles=$zero;Pcsx2x6Crosshairs=$zero};Pcsx2x6=[pscustomobject]@{Present=$false};VirtualBetaTester=[pscustomobject]@{Total=1;Passed=1;Failed=0;HumanBehaviors=1;IdempotencyChecks=0;RecoveryBehaviors=0;EnvironmentVariations=0;HighTvdBehaviors=1};RequestedTeknoParrotRoot=$repo;EffectiveTeknoParrotRoot=$null}
  $health=[pscustomobject]@{Checks=@([pscustomobject]@{Name='TeknoParrotUi.exe exists';Passed=$true},[pscustomobject]@{Name='GameProfiles folder exists';Passed=$true},[pscustomobject]@{Name='UserProfiles folder exists';Passed=$true})};New-Item -ItemType Directory -Path (Join-Path $report 'InstallHealth')|Out-Null;[IO.File]::WriteAllText((Join-Path $report 'InstallHealth\InstallHealth.json'),'{}')
  $snapshot=$results|ConvertTo-Json -Depth 8;$facts=@(New-TPMShadowFactRecordsFromLegacyV1 -Results $results -RepositoryPath $repo -ReportDirectory $report -BackupDirectory $backup -HealthResult $health)
  $facts.Count|Should -Be 11;@($facts.Identifier)|Should -Be @('Repository','Pester','Static Analysis','Real Install Health','Backups','Smoke File Safety','Artifacts','pcsx2x6 crosshair path (issue #79)','Behavioral Certification (Virtual Beta Tester)','Unattended TPM root binding','Unattended TPM config restoration');($results|ConvertTo-Json -Depth 8)|Should -BeExactly $snapshot
  $authority=New-TPMShadowWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -PngValidator $validator;foreach($fact in $facts){&$authority RecordFact $fact};(&$authority DeriveScorePreview).CanonicalJson|Should -Match 'ANALYZER_NOT_EXECUTED'
 }
}
Describe 'ADR-0155 Phase 3 production shadow boundary (ADR155-0309 Checkpoint B2)' {
 It 'never imports or invokes TPMCertification.Shadow.psm1 from the production harness' {
  # Checkpoint B2 supersedes the Phase 2 shadow-observer wiring this test
  # used to assert: the harness is now driven directly by the Phase 3
  # production authority (Authority/Production/ProductionCycle/
  # ProductionFacts/ProductionEvidence/Publication/Reports), never by
  # Shadow.psm1 -- Shadow remains a standalone, never-authoritative
  # observer module exercised only by its own test suite above, not
  # imported or called by this harness at all.
  # Only real Import-Module/invocation syntax is checked -- explanatory
  # comments documenting that Shadow is deliberately not imported (and
  # naming it to say so) are legitimate and must not trip this assertion.
  $codeLines=@([IO.File]::ReadAllLines((Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\Invoke-TPM-RealInstanceSmoke.ps1'))|Where-Object{$_ -notmatch '^\s*#'})
  $code=$codeLines -join "`n"
  $code|Should -Not -Match 'Import-Module\s+[^\r\n]*TPMCertification\.Shadow\.psm1'
  $code|Should -Not -Match 'Invoke-TPMShadowCertificationV1'
  $code|Should -Not -Match 'New-TPMShadowFactRecordsFromLegacyV1'
  $code|Should -Not -Match 'New-TPMShadowWorkflowAuthorityV1'
 }
}
Describe 'ADR-0155 Phase 1/Phase 2 module coexistence' {
 It 'keeps New-TPMWorkflowAuthorityV1 and New-TPMShadowWorkflowAuthorityV1 independently discoverable with their own parameter sets regardless of import order' {
  $shadowModule=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Shadow.psm1'
  $authorityModule=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Authority.psm1'
  $engine=if($PSVersionTable.PSEdition-ceq'Core'){(Get-Command pwsh).Source}else{(Get-Command powershell).Source}
  foreach($firstModule in @($authorityModule,$shadowModule)){
   $secondModule=if($firstModule-eq$authorityModule){$shadowModule}else{$authorityModule}
   $probe=Join-Path $TestDrive (([guid]::NewGuid().ToString('N'))+'.ps1')
   $lines=@(
    "Import-Module '$firstModule' -Force"
    "Import-Module '$secondModule' -Force"
    '$result = [ordered]@{}'
    '$result.AuthorityModule = (Get-Command New-TPMWorkflowAuthorityV1).ModuleName'
    '$result.ShadowModule = (Get-Command New-TPMShadowWorkflowAuthorityV1).ModuleName'
    'try { New-TPMWorkflowAuthorityV1 | Out-Null; $result.AuthorityZeroArgOk = $true } catch { $result.AuthorityZeroArgOk = $false }'
    '$shadowCommand = Get-Command New-TPMShadowWorkflowAuthorityV1'
    '$result.ShadowRequiresMode = $shadowCommand.Parameters[''Mode''].Attributes.Mandatory -contains $true'
    '$result.ShadowRequiresEvidenceRoot = $shadowCommand.Parameters[''EvidenceRoot''].Attributes.Mandatory -contains $true'
    '$result.AssertFactModule = (Get-Command Assert-TPMFactRecordV1).ModuleName'
    '$result.FactIdentifierCount = (Get-TPMFactIdentifiersV1).Count'
    'try { Assert-TPMFactRecordV1 ([ordered]@{Identifier="NotARealCategory";Applicable=$true;Data=[ordered]@{}}) Smoke "C:\\" | Out-Null; $result.RejectsUnknownFactIdentifier = $false } catch { $result.RejectsUnknownFactIdentifier = ($_.Exception.Message -match "FACT_IDENTIFIER_INVALID") }'
    '$result | ConvertTo-Json -Compress'
   )
   [IO.File]::WriteAllText($probe,($lines-join"`n"),(New-Object Text.UTF8Encoding $false))
   $stdin=Join-Path $TestDrive (([guid]::NewGuid().ToString('N'))+'.stdin')
   $stdout=Join-Path $TestDrive (([guid]::NewGuid().ToString('N'))+'.stdout')
   $stderr=Join-Path $TestDrive (([guid]::NewGuid().ToString('N'))+'.stderr')
   [IO.File]::WriteAllBytes($stdin,[byte[]]@())
   $arguments=@('-NoProfile','-NonInteractive','-File',$probe)|ForEach-Object{ConvertTo-TPMWin32ArgumentV1 -Value $_}
   $process=Start-Process -FilePath $engine -ArgumentList $arguments -Wait -PassThru -RedirectStandardInput $stdin -RedirectStandardOutput $stdout -RedirectStandardError $stderr
   [void]$process.Handle
   $process.HasExited|Should -BeTrue
   $process.ExitCode|Should -Be 0
   $json=Get-Content -LiteralPath $stdout -Raw
   $result=$json|ConvertFrom-Json
   $result.AuthorityModule|Should -Be 'TPMCertification.Authority'
   $result.ShadowModule|Should -Be 'TPMCertification.Shadow'
   $result.AuthorityZeroArgOk|Should -BeTrue
   $result.ShadowRequiresMode|Should -BeTrue
   $result.ShadowRequiresEvidenceRoot|Should -BeTrue
   $result.AssertFactModule|Should -Be 'TPMCertification.Authority'
   $result.FactIdentifierCount|Should -Be 11
   $result.RejectsUnknownFactIdentifier|Should -BeTrue
  }
 }
}
