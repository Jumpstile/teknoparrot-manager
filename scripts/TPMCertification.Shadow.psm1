Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Authority.psm1')
Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Contracts.psm1')
Set-StrictMode -Version 2.0

function New-TPMShadowWorkflowAuthorityV1 {
    param([Parameter(Mandatory=$true)][ValidateSet('Smoke','Unattended')][string]$Mode,[Parameter(Mandatory=$true)][string]$EvidenceRoot,[string]$ReportRoot,[scriptblock]$PngValidator)
    Initialize-TPMCertificationTypesV1|Out-Null
    $normalizedRoot=[IO.Path]::GetFullPath($EvidenceRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if([string]::IsNullOrWhiteSpace($ReportRoot)){$ReportRoot=$EvidenceRoot};$normalizedReportRoot=[IO.Path]::GetFullPath($ReportRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $factIdentifiers=Get-TPMFactIdentifiersV1
    $evidenceManifest=Get-TPMEvidenceManifestV1
    $assertFact=${function:Assert-TPMFactRecordV1}
    $assertEvidence=${function:Assert-TPMEvidenceRecordV1}
    $copyClosed=${function:Copy-TPMClosedValueV1}
    $factDecision=${function:Get-TPMFactDecisionV1}
    $jcs=${function:ConvertTo-TPMJcsV1}
    $state=[pscustomobject]@{
        Phase='Collecting';RunIdentity=[guid]::NewGuid().ToString('N');Mode=$Mode
        Facts=(New-Object Collections.Generic.List[object]);Evidence=(New-Object Collections.Generic.List[object])
        FactJson=(New-Object Collections.Generic.List[string]);EvidenceJson=(New-Object Collections.Generic.List[string])
        OwnedPaths=(New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase))
        Registry=@{};Consumed=(New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal))
    }
    $issue={param([string]$TypeName,[string]$Purpose,[string]$Json);$type=("Jumpstile.TPM.Certification.V1.$TypeName"-as[type]);$ctor=$type.GetConstructors([Reflection.BindingFlags]'NonPublic,Instance')[0];$object=$ctor.Invoke(@($state.RunIdentity,$Json));$state.Registry[$Purpose]=$object;return $object}.GetNewClosure()
    $validate={param($Object,[string]$Purpose,[switch]$Consume);if(-not$state.Registry.ContainsKey($Purpose)-or-not[object]::ReferenceEquals($state.Registry[$Purpose],$Object)-or$Object.RunIdentity-cne$state.RunIdentity-or$Object.GetType().Namespace-cne'Jumpstile.TPM.Certification.V1'-or$Object.GetType().GetProperty('SchemaVersion',[Reflection.BindingFlags]'Public,Static,FlattenHierarchy').GetValue($null,$null)-ne1-or$state.Consumed.Contains($Purpose)){return $false};if($Consume){[void]$state.Consumed.Add($Purpose)};return $true}.GetNewClosure()
    $dispatch={
      param([string]$Operation,$Value,$Dependency)
      switch -CaseSensitive($Operation){
        'GetPhase'{return $state.Phase}
        'GetRunIdentity'{return $state.RunIdentity}
        'RecordFact'{if($state.Phase-cne'Collecting'){throw "ILLEGAL_PHASE: $($state.Phase) RecordFact"};$index=$state.Facts.Count;if($index-ge$factIdentifiers.Count){throw 'FACT_DUPLICATE'};&$assertFact $Value $state.Mode $normalizedReportRoot;if($Value.Identifier-cne$factIdentifiers[$index]){throw 'FACT_ORDER_INVALID'};$copy=&$copyClosed $Value;$state.Facts.Add($copy);$state.FactJson.Add((&$jcs $copy));return}
        'RecordEvidence'{if($state.Phase-cne'Collecting'){throw "ILLEGAL_PHASE: $($state.Phase) RecordEvidence"};$index=$state.Evidence.Count;if($index-ge8){throw 'EVIDENCE_POST_FINAL'};$expected=$evidenceManifest[$index];&$assertEvidence $Value $expected $normalizedRoot $PngValidator $state.OwnedPaths;$copy=&$copyClosed $Value;$state.Evidence.Add($copy);$state.EvidenceJson.Add((&$jcs $copy));return}
        'DeriveScorePreview'{if($state.Phase-cne'Collecting'){throw "ILLEGAL_PHASE: $($state.Phase) DeriveScorePreview"};if($state.Registry.ContainsKey('ScorePreview')){throw 'DUPLICATE_ISSUANCE: ScorePreview'};if($state.Facts.Count-ne11){throw 'FACT_MANIFEST_INCOMPLETE'};$items=@();foreach($fact in $state.Facts){$items+=,(&$factDecision $fact $state.Mode)};$json=&$jcs ([ordered]@{SchemaVersion=1;RunIdentity=$state.RunIdentity;Mode=$state.Mode;ScoreItems=$items});return &$issue 'TPMScorePreviewV1' 'ScorePreview' $json}
        'IssueFinalEvidence'{if($state.Phase-cne'Collecting'){throw "ILLEGAL_PHASE: $($state.Phase) IssueFinalEvidence"};if(-not(&$validate $Dependency 'ScorePreview')){throw 'PROVENANCE_INVALID: ScorePreview'};if($state.Evidence.Count-ne8){throw 'EVIDENCE_MANIFEST_INCOMPLETE'};$expected=$evidenceManifest[8];&$assertEvidence $Value $expected $normalizedRoot $PngValidator $state.OwnedPaths;$copy=&$copyClosed $Value;if(-not(&$validate $Dependency 'ScorePreview' -Consume)){throw 'PROVENANCE_INVALID: ScorePreview'};$state.Evidence.Add($copy);$state.EvidenceJson.Add((&$jcs $copy));$state.Phase='FinalEvidenceIssued';return}
        'Seal'{if($state.Phase-cne'FinalEvidenceIssued'){throw "ILLEGAL_PHASE: $($state.Phase) Seal"};if($state.Facts.Count-ne11-or$state.Evidence.Count-ne9){throw 'MANIFEST_INCOMPLETE'};foreach($i in 0..8){$e=$state.Evidence[$i];$expected=$evidenceManifest[$i];if($e.Identifier-cne$expected.Identifier){throw 'EVIDENCE_ORDER_INVALID'};if($expected.Required-and$e.Status-cne'Captured'){throw 'EVIDENCE_REQUIRED_FAILED'};if(-not$expected.Required-and$e.Status-ceq'Failed'){throw 'EVIDENCE_OPTIONAL_FAILED'}};$facts='['+($state.FactJson.ToArray()-join',')+']';$evidence='['+($state.EvidenceJson.ToArray()-join',')+']';$json='{"SchemaVersion":1,"RunIdentity":'+(&$jcs $state.RunIdentity)+',"Mode":'+(&$jcs $state.Mode)+',"Facts":'+$facts+',"Evidence":'+$evidence+'}';$state.Facts.Clear();$state.Evidence.Clear();$state.FactJson.Clear();$state.EvidenceJson.Clear();$state.Facts=$null;$state.Evidence=$null;$state.FactJson=$null;$state.EvidenceJson=$null;$state.OwnedPaths=$null;$reader=&$issue 'TPMSealedRunReaderV1' 'SealedRun' $json;$state.Phase='Sealed';return $reader}
        'ValidateIssued'{return &$validate $Value ([string]$Dependency)}
        default{throw "UNSUPPORTED_OPERATION: $Operation"}
      }
    }.GetNewClosure()
    return $dispatch
}

function ConvertTo-TPMShadowEvidenceRecordV1 {
    param($LegacyRecord,$Expected,[string]$EvidenceRoot,[scriptblock]$PngValidator)
    $identifier=[string]$Expected.Identifier
    if($null-eq$LegacyRecord){return [ordered]@{Identifier=$identifier;Status='Failed';EvidenceType=$null;Required=[bool]$Expected.Required;Path=$null;CaptureScope=$null;FileSha256=$null;Width=$null;Height=$null;FailureCode='EVIDENCE_IDENTIFIER_INVALID';FailureMessage='legacy workflow did not issue this evidence identifier'}}
    $name=if($LegacyRecord.PSObject.Properties.Name-contains'Name'){[string]$LegacyRecord.Name}else{''}
    if($name-cne$identifier){return [ordered]@{Identifier=$identifier;Status='Failed';EvidenceType=$null;Required=[bool]$Expected.Required;Path=$null;CaptureScope=$null;FileSha256=$null;Width=$null;Height=$null;FailureCode='EVIDENCE_ORDER_INVALID';FailureMessage=("legacy evidence at this position was '{0}'"-f$name)}}
    $status=[string]$LegacyRecord.Status
    if($status-ceq'Skipped'){return [ordered]@{Identifier=$identifier;Status='Skipped';EvidenceType=$null;Required=[bool]$Expected.Required;Path=$null;CaptureScope=$null;FileSha256=$null;Width=$null;Height=$null;FailureCode='EVIDENCE_SKIPPED';FailureMessage=$(if($LegacyRecord.Details){[string]$LegacyRecord.Details}else{'legacy workflow skipped this optional evidence'})}}
    if($status-cne'Captured'){return [ordered]@{Identifier=$identifier;Status='Failed';EvidenceType=$null;Required=[bool]$Expected.Required;Path=$null;CaptureScope=$null;FileSha256=$null;Width=$null;Height=$null;FailureCode='EVIDENCE_CAPTURE_EXCEPTION';FailureMessage=$(if($LegacyRecord.Details){[string]$LegacyRecord.Details}else{"legacy evidence status was '$status'"})}}
    $path=[IO.Path]::GetFullPath([string]$LegacyRecord.Path)
    $validation=&$PngValidator $path
    if(-not$validation-or-not$validation.Valid){return [ordered]@{Identifier=$identifier;Status='Failed';EvidenceType=$null;Required=[bool]$Expected.Required;Path=$null;CaptureScope=$null;FileSha256=$null;Width=$null;Height=$null;FailureCode='EVIDENCE_PNG_INVALID';FailureMessage=$(if($validation.Reason){[string]$validation.Reason}else{'PNG validation failed'})}}
    $bytes=[IO.File]::ReadAllBytes($path)
    $legacyType=[string]$LegacyRecord.EvidenceType;$scope=if($legacyType-ceq'DeterministicRender'){'Deterministic'}elseif([string]$LegacyRecord.CaptureScope-ceq'Window'){'ConsoleWindow'}else{[string]$LegacyRecord.CaptureScope}
    return [ordered]@{Identifier=$identifier;Status='Captured';EvidenceType=$legacyType;Required=[bool]$Expected.Required;Path=$path;CaptureScope=$scope;FileSha256=(Get-TPMSha256HexV1 -Bytes $bytes);Width=[int]$validation.Width;Height=[int]$validation.Height;FailureCode=$null;FailureMessage=$null}
}

function Compare-TPMShadowScoreV1 {
    param([Parameter(Mandatory=$true)]$Preview,[Parameter(Mandatory=$true)]$LegacyItems)
    $previewValue=$Preview.CanonicalJson|ConvertFrom-Json
    $legacy=@($LegacyItems);$shadow=@($previewValue.ScoreItems);$differences=New-Object Collections.Generic.List[object]
    if($legacy.Count-ne$shadow.Count){$differences.Add([ordered]@{Path='ScoreItems.Count';Legacy=$legacy.Count;Shadow=$shadow.Count;ComparisonRule='exact integer equality'})}
    for($i=0;$i-lt[Math]::Min($legacy.Count,$shadow.Count);$i++){
        $legacyStatus=if($legacy[$i].PSObject.Properties.Name-contains'Status'){[string]$legacy[$i].Status}elseif([bool]$legacy[$i].Passed){'Pass'}else{'Fail'}
        foreach($field in @('Identifier','Status','Passed')){
            $left=switch($field){'Identifier'{[string]$legacy[$i].Area};'Status'{$legacyStatus};'Passed'{$legacy[$i].Passed}}
            $right=switch($field){'Identifier'{[string]$shadow[$i].Identifier};'Status'{[string]$shadow[$i].Status};'Passed'{$shadow[$i].Passed}}
            if(-not[object]::Equals($left,$right)){$rule=if($field-ceq'Passed'){'exact Boolean/null equality'}else{'Ordinal case-sensitive string equality'};$differences.Add([ordered]@{Path=("ScoreItems[{0}].{1}"-f$i,$field);Legacy=$left;Shadow=$right;ComparisonRule=$rule})}
        }
    }
    return $differences.ToArray()
}

function Write-TPMShadowDiagnosticV1 {
    param([Parameter(Mandatory=$true)]$Diagnostic,[Parameter(Mandatory=$true)][string]$Path)
    $parent=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path));if(-not(Test-Path -LiteralPath $parent -PathType Container)){[void](New-Item -ItemType Directory -Path $parent)}
    $json=ConvertTo-TPMJcsV1 $Diagnostic;$bytes=(New-Object Text.UTF8Encoding $false).GetBytes($json)
    $stream=New-Object IO.FileStream($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
}

function Invoke-TPMShadowCertificationV1 {
    param([ValidateSet('Smoke','Unattended')][string]$Mode,[string]$EvidenceRoot,$FactRecords,$LegacyEvidence,$LegacyScoreItems,[string]$DiagnosticPath,[scriptblock]$PngValidator)
    $diagnostic=[ordered]@{SchemaVersion=1;Mode=$Mode;RunIdentity=$null;MigrationEligible=$false;Phase='NotStarted';SealedRunSha256=$null;Divergences=@();ErrorCode=$null;ErrorMessage=$null}
    $evidenceManifest=Get-TPMEvidenceManifestV1
    try{
        $authority=New-TPMShadowWorkflowAuthorityV1 -Mode $Mode -EvidenceRoot $EvidenceRoot -ReportRoot ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($EvidenceRoot))) -PngValidator $PngValidator;$diagnostic.RunIdentity=&$authority GetRunIdentity
        foreach($fact in @($FactRecords)){&$authority RecordFact $fact}
        $legacy=@($LegacyEvidence)
        if($legacy.Count-ne9){throw "EVIDENCE_MANIFEST_INCOMPLETE: expected 9 legacy records, found $($legacy.Count)"}
        for($i=0;$i-lt8;$i++){$record=ConvertTo-TPMShadowEvidenceRecordV1 $legacy[$i] $evidenceManifest[$i] $EvidenceRoot $PngValidator;&$authority RecordEvidence $record}
        $preview=&$authority DeriveScorePreview
        $final=ConvertTo-TPMShadowEvidenceRecordV1 $legacy[8] $evidenceManifest[8] $EvidenceRoot $PngValidator
        &$authority IssueFinalEvidence $final $preview
        $sealed=&$authority Seal
        $differences=@(Compare-TPMShadowScoreV1 -Preview $preview -LegacyItems $LegacyScoreItems)
        $diagnostic.Phase='Sealed';$diagnostic.SealedRunSha256=Get-TPMSha256HexV1 -Bytes ((New-Object Text.UTF8Encoding $false).GetBytes($sealed.CanonicalJson));$diagnostic.Divergences=$differences;$diagnostic.MigrationEligible=($differences.Count-eq0)
    }catch{
        $diagnostic.Phase='Failed';$diagnostic.ErrorCode=if($_.Exception.Message-match'^([A-Z0-9_]+)'){$Matches[1]}else{'SHADOW_EXCEPTION'};$diagnostic.ErrorMessage=$_.Exception.Message;$diagnostic.Divergences=@([ordered]@{Path='ShadowAuthority';Legacy='completed';Shadow='failed';ComparisonRule='both authorities complete'})
    }
    try{Write-TPMShadowDiagnosticV1 -Diagnostic $diagnostic -Path $DiagnosticPath}catch{$diagnostic.MigrationEligible=$false;$diagnostic.Phase='Failed';$diagnostic.ErrorCode='SHADOW_DIAGNOSTIC_WRITE_FAILED';$diagnostic.ErrorMessage=$_.Exception.Message}
    return [pscustomobject]$diagnostic
}


function Get-TPMShadowTreeSha256V1 {
    param([string]$Path)
    if(-not(Test-Path -LiteralPath $Path -PathType Container)){return $null}
    $items=New-Object Collections.Generic.List[object]
    foreach($file in @(Get-ChildItem -LiteralPath $Path -File -Recurse|Sort-Object FullName)){
        $relative=$file.FullName.Substring([IO.Path]::GetFullPath($Path).TrimEnd('\').Length).TrimStart('\').Replace('\','/')
        $items.Add([ordered]@{Path=$relative;Sha256=(Get-TPMSha256HexV1 -Bytes ([IO.File]::ReadAllBytes($file.FullName)))})
    }
    return Get-TPMSha256HexV1 -Bytes ((New-Object Text.UTF8Encoding $false).GetBytes((ConvertTo-TPMJcsV1 $items.ToArray())))
}

function New-TPMShadowFactRecordsFromLegacyV1 {
    param($Results,[string]$RepositoryPath,[string]$ReportDirectory,[string]$BackupDirectory,$HealthResult,[string]$HealthLoadError,$UnattendedBinding)
    $mode=if($Results.SmokeMode){'Smoke'}else{'Unattended'};$checks=@{};foreach($c in @($Results.Checks)){$checks[[string]$c.Name]=[bool]$c.Passed}
    $testDigest=Get-TPMShadowTreeSha256V1 (Join-Path $RepositoryPath 'Tests')
    $healthPath=Join-Path $ReportDirectory 'InstallHealth\InstallHealth.json';$healthState=if($HealthLoadError){if(Test-Path -LiteralPath $healthPath -PathType Leaf){'InvalidJson'}else{'Missing'}}else{'Loaded'};$healthChecks=@()
    if($healthState-ceq'Loaded'){foreach($name in @('TeknoParrotUi.exe exists','GameProfiles folder exists','UserProfiles folder exists')){$healthMatches=@($HealthResult.Checks|Where-Object{$_.Name-ceq$name});if($healthMatches.Count-ne1-or$healthMatches[0].Passed-isnot[bool]){$healthState='InvalidJson';$HealthLoadError="critical health check '$name' was missing, duplicated, or non-Boolean";$healthChecks=@();break};$healthChecks+=,[ordered]@{Name=$name;Passed=[bool]$healthMatches[0].Passed}}}
    $userBackup=Join-Path $BackupDirectory 'UserProfiles';$gameBackup=Join-Path $BackupDirectory 'GameProfiles';$userCreated=[bool]$Results.Backup.UserProfiles;$gameCreated=[bool]$Results.Backup.GameProfiles;$userHash=if($userCreated){Get-TPMShadowTreeSha256V1 $userBackup}else{$null};$gameHash=if($gameCreated){Get-TPMShadowTreeSha256V1 $gameBackup}else{$null}
    $snapshots=if($mode-ceq'Smoke'){$Results.Snapshots}else{$null};$pcsx=$Results.Pcsx2x6;$pcsxPresent=[bool]$pcsx.Present;$pcsxCanonical=if($pcsxPresent){[bool]$pcsx.CanonicalFilesDeployed}else{$false};$pcsxLegacy=if($pcsxPresent){[bool]$pcsx.LegacyRootFilesPresent}else{$false};$pcsxIni=if($pcsxPresent){[bool]$pcsx.IniFound}else{$false};$pcsxCursor=if($pcsxPresent){[bool]$pcsx.CursorPathPointsCanonical}else{$false};$vbt=$Results.VirtualBetaTester;$binding=$UnattendedBinding
    return @(
      [ordered]@{Identifier='Repository';Applicable=$true;Data=[ordered]@{RepositoryPath=[IO.Path]::GetFullPath($RepositoryPath);RepositoryAvailable=[bool]$checks['Repository available'];RepositoryClean=($Results.GitStatus-ceq'(clean)');GitStatus=[string]$Results.GitStatus}}
      [ordered]@{Identifier='Pester';Applicable=$true;Data=[ordered]@{Executed=($null-ne$Results.Pester);Total=[int]$Results.Pester.Total;Passed=[int]$Results.Pester.Passed;Failed=[int]$Results.Pester.Failed;Skipped=[int]$Results.Pester.Skipped;NotRun=[int]$Results.Pester.NotRun;Engine=("Pester {0} / PowerShell {1}"-f$Results.PesterVersion,$Results.PowerShellVersion);SuiteSha256=$testDigest}}
      [ordered]@{Identifier='Static Analysis';Applicable=$true;Data=[ordered]@{Parser=@([ordered]@{Identifier='WindowsPowerShell51';Executed=$false;ErrorCount=0;ToolVersion=$null},[ordered]@{Identifier='Pwsh';Executed=$false;ErrorCount=0;ToolVersion=$null});Encoding=[ordered]@{Executed=$false;NonAsciiByteCount=0;Files=@('TeknoParrot-Manager.ps1')};PSScriptAnalyzer=[ordered]@{Executed=($null-ne$Results.PSScriptAnalyzerFindings);FindingCount=[int]$Results.PSScriptAnalyzerFindings;ToolVersion=[string]$Results.PSScriptAnalyzerVersion};InjectionHunter=[ordered]@{Executed=$false;FindingCount=0;UnresolvedFindingCount=0;ToolVersion=$null;Dispositions=@()}}}
      [ordered]@{Identifier='Real Install Health';Applicable=$true;Data=[ordered]@{ReportPath=$(if(Test-Path -LiteralPath $healthPath -PathType Leaf){[IO.Path]::GetFullPath($healthPath)}else{$null});LoadState=$healthState;LoadError=$(if($healthState-ceq'Loaded'){$null}else{[string]$HealthLoadError});Checks=$healthChecks}}
      [ordered]@{Identifier='Backups';Applicable=$true;Data=[ordered]@{UserProfilesBackupCreated=$userCreated;UserProfilesBackupPath=$(if($userCreated){[IO.Path]::GetFullPath($userBackup)}else{$null});UserProfilesBackupVerified=($userCreated-and$null-ne$userHash);UserProfilesBackupSha256=$userHash;GameProfilesBackupCreated=$gameCreated;GameProfilesBackupPath=$(if($gameCreated){[IO.Path]::GetFullPath($gameBackup)}else{$null});GameProfilesBackupVerified=($gameCreated-and$null-ne$gameHash);GameProfilesBackupSha256=$gameHash;BackupVerificationExecuted=$true}}
      $(if($mode-ceq'Smoke'){[ordered]@{Identifier='Smoke File Safety';Applicable=$true;Data=[ordered]@{UserProfiles=[ordered]@{Added=[int]$snapshots.UserProfiles.Added;Removed=[int]$snapshots.UserProfiles.Removed;Changed=[int]$snapshots.UserProfiles.Changed;BeforeSkipped=[int]$snapshots.UserProfiles.BeforeSkipped;AfterSkipped=[int]$snapshots.UserProfiles.AfterSkipped};GameProfiles=[ordered]@{Added=[int]$snapshots.GameProfiles.Added;Removed=[int]$snapshots.GameProfiles.Removed;Changed=[int]$snapshots.GameProfiles.Changed;BeforeSkipped=[int]$snapshots.GameProfiles.BeforeSkipped;AfterSkipped=[int]$snapshots.GameProfiles.AfterSkipped};Pcsx2x6Crosshairs=[ordered]@{Added=[int]$snapshots.Pcsx2x6Crosshairs.Added;Removed=[int]$snapshots.Pcsx2x6Crosshairs.Removed;Changed=[int]$snapshots.Pcsx2x6Crosshairs.Changed;BeforeSkipped=[int]$snapshots.Pcsx2x6Crosshairs.BeforeSkipped;AfterSkipped=[int]$snapshots.Pcsx2x6Crosshairs.AfterSkipped}}}}else{[ordered]@{Identifier='Smoke File Safety';Applicable=$false;Data=[ordered]@{}}})
      [ordered]@{Identifier='Artifacts';Applicable=$true;Data=[ordered]@{ReportDirectory=[IO.Path]::GetFullPath($ReportDirectory);ReportDirectoryReserved=(Test-Path -LiteralPath $ReportDirectory -PathType Container);StagingDirectoryReady=$false;RequiredArtifactManifestConfigured=$true;PublisherAvailable=$true;PackageValidationExecuted=$false;PackageValidationPassed=$false;PackageValidationErrorCount=0}}
      [ordered]@{Identifier='pcsx2x6 crosshair path (issue #79)';Applicable=$pcsxPresent;Data=[ordered]@{Present=$pcsxPresent;CanonicalFilesDeployed=$pcsxCanonical;LegacyRootPresent=$pcsxLegacy;IniFound=$pcsxIni;CursorPathPointsCanonical=$pcsxCursor;Pcsx2Directory=$(if($pcsxPresent){[IO.Path]::GetFullPath([string]$pcsx.Pcsx2Dir)}else{$null})}}
      [ordered]@{Identifier='Behavioral Certification (Virtual Beta Tester)';Applicable=$true;Data=[ordered]@{Executed=($null-ne$vbt);Total=[int]$vbt.Total;Passed=[int]$vbt.Passed;Failed=[int]$vbt.Failed;HumanBehaviors=[int]$vbt.HumanBehaviors;IdempotencyChecks=[int]$vbt.IdempotencyChecks;RecoveryBehaviors=[int]$vbt.RecoveryBehaviors;EnvironmentVariations=[int]$vbt.EnvironmentVariations;HighTvdBehaviors=[int]$vbt.HighTvdBehaviors}}
      $(if($mode-ceq'Smoke'){[ordered]@{Identifier='Unattended TPM root binding';Applicable=$false;Data=[ordered]@{RequestedRoot=[IO.Path]::GetFullPath([string]$Results.RequestedTeknoParrotRoot);EffectiveRoot=$null;EffectiveRootParseState='Missing'}}}else{[ordered]@{Identifier='Unattended TPM root binding';Applicable=$true;Data=[ordered]@{RequestedRoot=[IO.Path]::GetFullPath([string]$Results.RequestedTeknoParrotRoot);EffectiveRoot=$(if($Results.EffectiveTeknoParrotRoot){[IO.Path]::GetFullPath([string]$Results.EffectiveTeknoParrotRoot)}else{$null});EffectiveRootParseState=$(if($Results.EffectiveTeknoParrotRoot){'Parsed'}else{'Missing'})}}})
      $(if($mode-ceq'Smoke'){[ordered]@{Identifier='Unattended TPM config restoration';Applicable=$false;Data=[ordered]@{}}}else{[ordered]@{Identifier='Unattended TPM config restoration';Applicable=$true;Data=[ordered]@{PriorConfigExisted=[bool]$binding.PriorConfigExisted;TemporaryConfigCreated=[bool]$binding.TemporaryConfigCreated;RestoreAttempted=[bool]$binding.RestoreAttempted;RestoreSucceeded=[bool]$binding.RestoreSucceeded;VerificationSucceeded=[bool]$binding.VerificationSucceeded;SnapshotSha256=$binding.SnapshotSha256;FailureReason=$binding.RestorationFailureReason}}})
    )
}

function Get-TPMShadowEmulatorContractVerificationV1 {
    # Informational, generic Emulator Contract Verification records for
    # shadow/candidate reporting -- built entirely from Contracts.psm1's
    # registry/observation collector and Authority.psm1's envelope
    # constructor, with no contract-specific logic anywhere in this
    # function. These are NOT fed through the strict Section 9 fact
    # dispatcher (Assert-TPMFactRecordV1/Get-TPMFactDecisionV1), which
    # would require registering a new mandatory fact identifier -- a
    # separate, later, explicitly-approved cutover once RuntimeCapability
    # evidence is no longer Unconfirmed. Callers should treat Records as
    # informational, the same way the legacy pcsx2x6 crosshair record is
    # already documented as "informational, not a hard requirement".
    #
    # VersionMatchState is always reported as Unknown here -- resolving it
    # for real requires launching the emulator to observe a version
    # signal (see Resolve-TPMEmulatorVersionMatchV1), which read-only
    # shadow reporting must not do. Every record's Status is therefore
    # Blocked until a caller with an actual captured version signal
    # supplies it; this is accurate, not a placeholder to silently fix
    # later -- Authority's envelope construction forces Blocked precisely
    # so an unverified version is never mistaken for a passing one.
    param([Parameter(Mandatory=$true)][string]$TeknoParrotRoot,[object[]]$RuntimeContexts=@(),[string]$ContractsRoot)
    $integrity=if([string]::IsNullOrWhiteSpace($ContractsRoot)){Test-TPMContractRegistryIntegrityV1}else{Test-TPMContractRegistryIntegrityV1 -ContractsRoot $ContractsRoot}
    if(-not$integrity.Valid){return [pscustomobject]@{RegistryValid=$false;Errors=$integrity.Errors;Records=@()}}
    $contractsById=@{};foreach($entry in $integrity.Contracts){$contractsById[$entry.ContractId]=$entry.Contract}
    $observed=if([string]::IsNullOrWhiteSpace($ContractsRoot)){Get-TPMEmulatorContractObservationsV1 -InstallRoot $TeknoParrotRoot -RuntimeContexts $RuntimeContexts}else{Get-TPMEmulatorContractObservationsV1 -InstallRoot $TeknoParrotRoot -RuntimeContexts $RuntimeContexts -ContractsRoot $ContractsRoot}
    $records=New-Object Collections.Generic.List[object]
    foreach($obs in $observed.Observations){
        $contract=$contractsById[$obs.ContractId]
        # Do not build Codes via `if(...){@(x)}else{@()}` -- an @() that is
        # the sole output of an if/else branch collapses to $null at
        # assignment (the same empty-array-to-null bug class fixed for
        # issue #172), which then becomes a one-element [$null] array via
        # @($null) downstream. An explicit List avoids the collapse.
        $codesList=New-Object Collections.Generic.List[string]
        if($obs.Reason){$codesList.Add([string]$obs.Reason)}
        $records.Add((New-TPMEmulatorContractVerificationRecordV1 -Contract $contract -CapabilityType $obs.CapabilityType -CapabilityId $obs.CapabilityId -VersionMatchState 'Unknown' -Applicable $obs.Applicable -CapabilityPassed $obs.CapabilityPassed -Codes $codesList.ToArray()))
    }
    return [pscustomobject]@{RegistryValid=$true;Errors=@();Records=$records.ToArray()}
}

Export-ModuleMember -Function New-TPMShadowWorkflowAuthorityV1,Invoke-TPMShadowCertificationV1,New-TPMShadowFactRecordsFromLegacyV1,Get-TPMShadowEmulatorContractVerificationV1
