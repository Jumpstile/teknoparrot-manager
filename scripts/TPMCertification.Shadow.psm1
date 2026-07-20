Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Authority.psm1') -Force
Set-StrictMode -Version 2.0

$script:TpmFactIdentifiersV1 = @(
    'Repository','Pester','Static Analysis','Real Install Health','Backups',
    'Smoke File Safety','Artifacts','pcsx2x6 crosshair path (issue #79)',
    'Behavioral Certification (Virtual Beta Tester)',
    'Unattended TPM root binding','Unattended TPM config restoration'
)
$script:TpmEvidenceManifestV1 = @(
    [pscustomobject]@{Identifier='certification-suite-running';Required=$true;EvidenceType='ScreenCapture'},
    [pscustomobject]@{Identifier='requested-effective-root-evidence';Required=$true;EvidenceType='ScreenCapture'},
    [pscustomobject]@{Identifier='live-thumbnail-evidence';Required=$false;EvidenceType=$null},
    [pscustomobject]@{Identifier='live-controls-evidence';Required=$false;EvidenceType=$null},
    [pscustomobject]@{Identifier='adaptive-menu-normal';Required=$true;EvidenceType='DeterministicRender'},
    [pscustomobject]@{Identifier='adaptive-menu-small';Required=$true;EvidenceType='DeterministicRender'},
    [pscustomobject]@{Identifier='adaptive-menu-maximized';Required=$true;EvidenceType='DeterministicRender'},
    [pscustomobject]@{Identifier='smoke-file-safety-evidence';Required=$true;EvidenceType='DeterministicRender'},
    [pscustomobject]@{Identifier='final-certification-result';Required=$true;EvidenceType='ScreenCapture'}
)
$script:TpmEvidenceFailureCodesV1 = @(
    'EVIDENCE_IDENTIFIER_INVALID','EVIDENCE_DUPLICATE','EVIDENCE_ORDER_INVALID',
    'EVIDENCE_POST_FINAL','EVIDENCE_METADATA_INVALID','EVIDENCE_TYPE_INVALID',
    'EVIDENCE_REQUIRED_SKIPPED','EVIDENCE_CAPTURE_ACTION_MISSING',
    'EVIDENCE_CAPTURE_EXCEPTION','EVIDENCE_PATH_INVALID','EVIDENCE_PATH_OUTSIDE_ROOT',
    'EVIDENCE_PATH_DUPLICATE','EVIDENCE_FILE_MISSING','EVIDENCE_FILE_EMPTY',
    'EVIDENCE_PNG_INVALID','EVIDENCE_DIMENSIONS_INVALID','EVIDENCE_FILE_LOCKED',
    'EVIDENCE_HASH_FAILED','EVIDENCE_SKIPPED'
)

function Get-TPMValueMapV1 {
    param([Parameter(Mandatory=$true)]$Value)
    if ($Value -is [Collections.IDictionary]) { return $Value }
    throw 'SCHEMA_INVALID: authoritative structured values must be dictionaries'
}
function Assert-TPMExactFieldsV1 {
    param($Value,[string[]]$Fields,[string]$Context)
    $map=Get-TPMValueMapV1 $Value
    $actual=@($map.Keys|ForEach-Object{[string]$_})
    if($actual.Count-ne$Fields.Count){throw "SCHEMA_INVALID: $Context field count"}
    for($i=0;$i-lt$Fields.Count;$i++){if($actual[$i]-cne$Fields[$i]){throw "SCHEMA_INVALID: $Context expected '$($Fields[$i])' at field $i"}}
    return $map
}
function Assert-TPMBooleanV1 { param($Value,[string]$Context) if($Value-isnot[bool]){throw "SCHEMA_INVALID: $Context must be Boolean"} }
function Assert-TPMIntegerV1 { param($Value,[string]$Context,[long]$Minimum=0) if($Value-isnot[byte]-and$Value-isnot[int16]-and$Value-isnot[int32]-and$Value-isnot[int64]){throw "SCHEMA_INVALID: $Context must be integer"};if([long]$Value-lt$Minimum){throw "SCHEMA_INVALID: $Context is out of range"} }
function Assert-TPMStringV1 { param($Value,[string]$Context,[switch]$Nullable) if($null-eq$Value){if($Nullable){return};throw "SCHEMA_INVALID: $Context is required"};if($Value-isnot[string]-or[string]::IsNullOrWhiteSpace($Value)){throw "SCHEMA_INVALID: $Context must be a non-empty string"} }
function Assert-TPMNullableHashV1 { param($Value,[string]$Context) if($null-ne$Value-and($Value-isnot[string]-or$Value-cnotmatch'^[0-9a-f]{64}$')){throw "SCHEMA_INVALID: $Context must be null or lowercase SHA-256"} }
function Assert-TPMNormalizedPathV1 { param($Value,[string]$Context,[switch]$Nullable) if($null-eq$Value){if($Nullable){return};throw "SCHEMA_INVALID: $Context is required"};Assert-TPMStringV1 $Value $Context;if(-not[IO.Path]::IsPathRooted($Value)){throw "SCHEMA_INVALID: $Context must be absolute"};$full=[IO.Path]::GetFullPath($Value).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar);if($full-cne$Value.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)){throw "SCHEMA_INVALID: $Context is not normalized"} }
function Copy-TPMClosedValueV1 {
    param([AllowNull()]$Value)
    if($null-eq$Value-or$Value-is[string]-or$Value-is[bool]-or$Value-is[byte]-or$Value-is[int16]-or$Value-is[int32]-or$Value-is[int64]){return $Value}
    if($Value-is[Collections.IDictionary]){$copy=[ordered]@{};foreach($key in $Value.Keys){if($key-isnot[string]){throw 'SCHEMA_INVALID: keys must be strings'};$copy[$key]=Copy-TPMClosedValueV1 $Value[$key]};return $copy}
    if($Value-is[Collections.IEnumerable]){$items=New-Object Collections.Generic.List[object];foreach($item in $Value){$items.Add((Copy-TPMClosedValueV1 $item))};return $items.ToArray()}
    throw 'SCHEMA_INVALID: unsupported mutable or non-scalar value'
}
function New-TPMReasonV1 { param([string]$Code,[string]$Message) [ordered]@{Code=$Code;Message=$Message} }

function Assert-TPMFactRecordV1 {
    param($Record,[ValidateSet('Smoke','Unattended')][string]$Mode,[string]$ReportRoot)
    $recordMap=Assert-TPMExactFieldsV1 $Record @('Identifier','Applicable','Data') 'fact'
    Assert-TPMStringV1 $recordMap.Identifier 'fact Identifier'; Assert-TPMBooleanV1 $recordMap.Applicable 'fact Applicable'
    $identifier=[string]$recordMap.Identifier;$data=Get-TPMValueMapV1 $recordMap.Data
    if($script:TpmFactIdentifiersV1-cnotcontains$identifier){throw "FACT_IDENTIFIER_INVALID: $identifier"}
    switch -CaseSensitive($identifier){
      'Repository' {$d=Assert-TPMExactFieldsV1 $data @('RepositoryPath','RepositoryAvailable','RepositoryClean','GitStatus') $identifier;Assert-TPMNormalizedPathV1 $d.RepositoryPath 'RepositoryPath';Assert-TPMBooleanV1 $d.RepositoryAvailable 'RepositoryAvailable';Assert-TPMBooleanV1 $d.RepositoryClean 'RepositoryClean';Assert-TPMStringV1 $d.GitStatus 'GitStatus'}
      'Pester' {$d=Assert-TPMExactFieldsV1 $data @('Executed','Total','Passed','Failed','Skipped','NotRun','Engine','SuiteSha256') $identifier;Assert-TPMBooleanV1 $d.Executed 'Executed';foreach($n in @('Total','Passed','Failed','Skipped','NotRun')){Assert-TPMIntegerV1 $d[$n] $n};if(([long]$d.Passed+[long]$d.Failed+[long]$d.Skipped+[long]$d.NotRun)-ne[long]$d.Total){throw 'SCHEMA_INVALID: Pester counts'};if($d.Executed){Assert-TPMStringV1 $d.Engine 'Engine';Assert-TPMNullableHashV1 $d.SuiteSha256 'SuiteSha256';if($null-eq$d.SuiteSha256){throw 'SCHEMA_INVALID: SuiteSha256 required'}}elseif($null-ne$d.Engine-or$null-ne$d.SuiteSha256){throw 'SCHEMA_INVALID: unexecuted Pester metadata must be null'}}
      'Static Analysis' {$d=Assert-TPMExactFieldsV1 $data @('Parser','Encoding','PSScriptAnalyzer','InjectionHunter') $identifier;$parser=@($d.Parser);if($parser.Count-ne2){throw 'SCHEMA_INVALID: Parser count'};foreach($i in 0..1){$p=Assert-TPMExactFieldsV1 $parser[$i] @('Identifier','Executed','ErrorCount','ToolVersion') 'Parser';$expected=@('WindowsPowerShell51','Pwsh')[$i];if($p.Identifier-cne$expected){throw 'SCHEMA_INVALID: Parser order'};Assert-TPMBooleanV1 $p.Executed 'Parser Executed';Assert-TPMIntegerV1 $p.ErrorCount 'Parser ErrorCount';if($p.Executed){Assert-TPMStringV1 $p.ToolVersion 'Parser ToolVersion'}elseif($null-ne$p.ToolVersion){throw 'SCHEMA_INVALID: Parser ToolVersion'}};$e=Assert-TPMExactFieldsV1 $d.Encoding @('Executed','NonAsciiByteCount','Files') 'Encoding';Assert-TPMBooleanV1 $e.Executed 'Encoding Executed';Assert-TPMIntegerV1 $e.NonAsciiByteCount 'NonAsciiByteCount';if(@($e.Files).Count-eq0){throw 'SCHEMA_INVALID: Encoding Files'};foreach($f in @($e.Files)){Assert-TPMStringV1 $f 'Encoding file';if([IO.Path]::IsPathRooted($f)-or$f.Contains('\')-or@($f-split'[\\/]'|Where-Object{$_-eq'.'-or$_-eq'..'}).Count-gt0){throw 'SCHEMA_INVALID: Encoding file must be normalized repository-relative'}};$a=Assert-TPMExactFieldsV1 $d.PSScriptAnalyzer @('Executed','FindingCount','ToolVersion') 'PSScriptAnalyzer';Assert-TPMBooleanV1 $a.Executed 'Analyzer Executed';Assert-TPMIntegerV1 $a.FindingCount 'FindingCount';if($a.Executed){Assert-TPMStringV1 $a.ToolVersion 'Analyzer ToolVersion'}elseif($null-ne$a.ToolVersion){throw 'SCHEMA_INVALID: Analyzer ToolVersion'};$h=Assert-TPMExactFieldsV1 $d.InjectionHunter @('Executed','FindingCount','UnresolvedFindingCount','ToolVersion','Dispositions') 'InjectionHunter';Assert-TPMBooleanV1 $h.Executed 'InjectionHunter Executed';Assert-TPMIntegerV1 $h.FindingCount 'IH FindingCount';Assert-TPMIntegerV1 $h.UnresolvedFindingCount 'IH unresolved';if(@($h.Dispositions).Count-ne[long]$h.FindingCount){throw 'SCHEMA_INVALID: disposition count'};foreach($x in @($h.Dispositions)){$m=Assert-TPMExactFieldsV1 $x @('FindingIdentifier','Disposition') 'Disposition';Assert-TPMStringV1 $m.FindingIdentifier 'FindingIdentifier';if(@('Confirmed','Mitigated','FalsePositive')-cnotcontains$m.Disposition){throw 'SCHEMA_INVALID: Disposition'}};if([long]$h.UnresolvedFindingCount-ne@($h.Dispositions|Where-Object{$_.Disposition-ceq'Confirmed'}).Count){throw 'SCHEMA_INVALID: IH unresolved count'};if($h.Executed){Assert-TPMStringV1 $h.ToolVersion 'IH ToolVersion'}elseif($null-ne$h.ToolVersion){throw 'SCHEMA_INVALID: IH ToolVersion'}}
      'Real Install Health' {$d=Assert-TPMExactFieldsV1 $data @('ReportPath','LoadState','LoadError','Checks') $identifier;if(@('Loaded','Missing','InvalidJson')-cnotcontains$d.LoadState){throw 'SCHEMA_INVALID: health LoadState'};Assert-TPMNormalizedPathV1 $d.ReportPath 'ReportPath' -Nullable;if($d.LoadState-ceq'Loaded'){if($null-ne$d.LoadError){throw 'SCHEMA_INVALID: loaded health error'};$checks=@($d.Checks);if($checks.Count-ne3){throw 'SCHEMA_INVALID: health check count'};for($i=0;$i-lt3;$i++){$c=Assert-TPMExactFieldsV1 $checks[$i] @('Name','Passed') 'health check';if($c.Name-cne@('TeknoParrotUi.exe exists','GameProfiles folder exists','UserProfiles folder exists')[$i]){throw 'SCHEMA_INVALID: health check order'};Assert-TPMBooleanV1 $c.Passed 'health Passed'}}else{Assert-TPMStringV1 $d.LoadError 'LoadError';if(@($d.Checks).Count-ne0){throw 'SCHEMA_INVALID: unloaded health checks'}}}
      'Backups' {$fields=@('UserProfilesBackupCreated','UserProfilesBackupPath','UserProfilesBackupVerified','UserProfilesBackupSha256','GameProfilesBackupCreated','GameProfilesBackupPath','GameProfilesBackupVerified','GameProfilesBackupSha256','BackupVerificationExecuted');$d=Assert-TPMExactFieldsV1 $data $fields $identifier;foreach($n in @('UserProfilesBackupCreated','UserProfilesBackupVerified','GameProfilesBackupCreated','GameProfilesBackupVerified','BackupVerificationExecuted')){Assert-TPMBooleanV1 $d[$n] $n};foreach($prefix in @('UserProfiles','GameProfiles')){$created=$d[$prefix+'BackupCreated'];Assert-TPMNormalizedPathV1 $d[$prefix+'BackupPath'] ($prefix+'BackupPath') -Nullable;Assert-TPMNullableHashV1 $d[$prefix+'BackupSha256'] ($prefix+'BackupSha256');if($created-and($null-eq$d[$prefix+'BackupPath']-or$null-eq$d[$prefix+'BackupSha256'])){throw 'SCHEMA_INVALID: created backup metadata'};if(-not$created-and($null-ne$d[$prefix+'BackupPath']-or$null-ne$d[$prefix+'BackupSha256'])){throw 'SCHEMA_INVALID: absent backup metadata'}}}
      'Smoke File Safety' {if($Mode-ceq'Unattended'){if($data.Count-ne0-or$recordMap.Applicable){throw 'SCHEMA_INVALID: unattended Smoke File Safety'}}else{if(-not$recordMap.Applicable){throw 'SCHEMA_INVALID: smoke safety applicability'};$d=Assert-TPMExactFieldsV1 $data @('UserProfiles','GameProfiles','Pcsx2x6Crosshairs') $identifier;foreach($tree in $d.Keys){$m=Assert-TPMExactFieldsV1 $d[$tree] @('Added','Removed','Changed','BeforeSkipped','AfterSkipped') $tree;foreach($n in $m.Keys){Assert-TPMIntegerV1 $m[$n] "$tree $n"}}}}
      'Artifacts' {$d=Assert-TPMExactFieldsV1 $data @('ReportDirectory','ReportDirectoryReserved','StagingDirectoryReady','RequiredArtifactManifestConfigured','PublisherAvailable','PackageValidationExecuted','PackageValidationPassed','PackageValidationErrorCount') $identifier;Assert-TPMNormalizedPathV1 $d.ReportDirectory 'ReportDirectory';try{$containedReport=Resolve-TPMContainedPathV1 -Root $ReportRoot -Path $d.ReportDirectory}catch{throw 'SCHEMA_INVALID: ReportDirectory is not contained'};if($containedReport-cne$d.ReportDirectory){throw 'SCHEMA_INVALID: ReportDirectory is not contained'};foreach($n in @('ReportDirectoryReserved','StagingDirectoryReady','RequiredArtifactManifestConfigured','PublisherAvailable','PackageValidationExecuted','PackageValidationPassed')){Assert-TPMBooleanV1 $d[$n] $n};Assert-TPMIntegerV1 $d.PackageValidationErrorCount 'PackageValidationErrorCount'}
      'pcsx2x6 crosshair path (issue #79)' {$d=Assert-TPMExactFieldsV1 $data @('Present','CanonicalFilesDeployed','LegacyRootPresent','IniFound','CursorPathPointsCanonical','Pcsx2Directory') $identifier;foreach($n in @('Present','CanonicalFilesDeployed','LegacyRootPresent','IniFound','CursorPathPointsCanonical')){Assert-TPMBooleanV1 $d[$n] $n};Assert-TPMNormalizedPathV1 $d.Pcsx2Directory 'Pcsx2Directory' -Nullable;if(-not$d.Present-and($recordMap.Applicable-or$null-ne$d.Pcsx2Directory-or$d.CanonicalFilesDeployed-or$d.LegacyRootPresent-or$d.IniFound-or$d.CursorPathPointsCanonical)){throw 'SCHEMA_INVALID: absent pcsx2'};if($d.Present-ne$recordMap.Applicable){throw 'SCHEMA_INVALID: pcsx2 applicability'}}
      'Behavioral Certification (Virtual Beta Tester)' {$d=Assert-TPMExactFieldsV1 $data @('Executed','Total','Passed','Failed','HumanBehaviors','IdempotencyChecks','RecoveryBehaviors','EnvironmentVariations','HighTvdBehaviors') $identifier;Assert-TPMBooleanV1 $d.Executed 'VBT Executed';foreach($n in @('Total','Passed','Failed','HumanBehaviors','IdempotencyChecks','RecoveryBehaviors','EnvironmentVariations','HighTvdBehaviors')){Assert-TPMIntegerV1 $d[$n] $n};if(([long]$d.Passed+[long]$d.Failed)-ne[long]$d.Total){throw 'SCHEMA_INVALID: VBT counts'}}
      'Unattended TPM root binding' {$d=Assert-TPMExactFieldsV1 $data @('RequestedRoot','EffectiveRoot','EffectiveRootParseState') $identifier;Assert-TPMNormalizedPathV1 $d.RequestedRoot 'RequestedRoot';Assert-TPMNormalizedPathV1 $d.EffectiveRoot 'EffectiveRoot' -Nullable;if(@('Parsed','Missing','Invalid')-cnotcontains$d.EffectiveRootParseState){throw 'SCHEMA_INVALID: EffectiveRootParseState'};if($Mode-ceq'Smoke'){if($recordMap.Applicable-or$null-ne$d.EffectiveRoot-or$d.EffectiveRootParseState-cne'Missing'){throw 'SCHEMA_INVALID: smoke root binding'}}elseif(-not$recordMap.Applicable){throw 'SCHEMA_INVALID: unattended root applicability'}}
      'Unattended TPM config restoration' {if($Mode-ceq'Smoke'){if($recordMap.Applicable-or$data.Count-ne0){throw 'SCHEMA_INVALID: smoke restoration'}}else{if(-not$recordMap.Applicable){throw 'SCHEMA_INVALID: restoration applicability'};$d=Assert-TPMExactFieldsV1 $data @('PriorConfigExisted','TemporaryConfigCreated','RestoreAttempted','RestoreSucceeded','VerificationSucceeded','SnapshotSha256','FailureReason') $identifier;foreach($n in @('PriorConfigExisted','TemporaryConfigCreated','RestoreAttempted','RestoreSucceeded','VerificationSucceeded')){Assert-TPMBooleanV1 $d[$n] $n};Assert-TPMNullableHashV1 $d.SnapshotSha256 'SnapshotSha256';if($d.PriorConfigExisted-and$null-eq$d.SnapshotSha256){throw 'SCHEMA_INVALID: restoration snapshot required'};if(-not$d.PriorConfigExisted-and$null-ne$d.SnapshotSha256){throw 'SCHEMA_INVALID: restoration snapshot forbidden'};if($null-ne$d.FailureReason){Assert-TPMStringV1 $d.FailureReason 'FailureReason'}}}
    }
    if($identifier-notin@('Smoke File Safety','pcsx2x6 crosshair path (issue #79)','Unattended TPM root binding','Unattended TPM config restoration')-and-not$recordMap.Applicable){throw 'SCHEMA_INVALID: category is never N/A'}
}
function Get-TPMFactDecisionV1 {
    param($Record,[ValidateSet('Smoke','Unattended')][string]$Mode,[string]$ReportRoot)
    $identifier=[string]$Record.Identifier;$data=$Record.Data;$reasons=New-Object Collections.Generic.List[object]
    function Add-Reason([string]$Code){$reasons.Add((New-TPMReasonV1 $Code $Code))}
    if(-not$Record.Applicable){return [ordered]@{Identifier=$identifier;Status='NotApplicable';Passed=$null;Details=(Copy-TPMClosedValueV1 $data);FailureReasons=@()}}
    switch -CaseSensitive($identifier){
      'Repository' {if(-not$data.RepositoryAvailable){Add-Reason 'REPOSITORY_UNAVAILABLE'};if($data.RepositoryAvailable-and-not$data.RepositoryClean){Add-Reason 'REPOSITORY_DIRTY'}}
      'Pester' {if(-not$data.Executed){Add-Reason 'PESTER_NOT_EXECUTED'};if($data.Executed-and$data.Total-eq0){Add-Reason 'PESTER_EMPTY'};if($data.Failed-gt0){Add-Reason 'PESTER_FAILURES'};if($data.NotRun-gt0){Add-Reason 'PESTER_NOT_RUN'};if(($data.Passed+$data.Failed+$data.Skipped+$data.NotRun)-ne$data.Total){Add-Reason 'PESTER_COUNTS_INVALID'}}
      'Static Analysis' {if(@($data.Parser|Where-Object{-not$_.Executed}).Count-gt0){Add-Reason 'PARSER_NOT_EXECUTED'};if(@($data.Parser|Where-Object{$_.ErrorCount-gt0}).Count-gt0){Add-Reason 'PARSER_ERRORS'};if(-not$data.Encoding.Executed){Add-Reason 'ENCODING_NOT_EXECUTED'};if($data.Encoding.NonAsciiByteCount-gt0){Add-Reason 'ENCODING_NON_ASCII'};if(-not$data.PSScriptAnalyzer.Executed-or-not$data.InjectionHunter.Executed){Add-Reason 'ANALYZER_NOT_EXECUTED'};if($data.PSScriptAnalyzer.FindingCount-gt0){Add-Reason 'PSSCRIPTANALYZER_FINDINGS'};if($data.InjectionHunter.UnresolvedFindingCount-gt0){Add-Reason 'INJECTION_FINDING_UNRESOLVED'}}
      'Real Install Health' {if($data.LoadState-ceq'Missing'){Add-Reason 'HEALTH_REPORT_MISSING'}elseif($data.LoadState-ceq'InvalidJson'){Add-Reason 'HEALTH_REPORT_INVALID'}else{foreach($c in $data.Checks){if(-not$c.Passed){Add-Reason 'HEALTH_CHECK_FAILED'}}}}
      'Backups' {if(-not$data.UserProfilesBackupCreated-and-not$data.GameProfilesBackupCreated){Add-Reason 'BACKUP_NONE_CREATED'};if(-not$data.BackupVerificationExecuted){Add-Reason 'BACKUP_VERIFICATION_NOT_EXECUTED'};if(($data.UserProfilesBackupCreated-and-not$data.UserProfilesBackupVerified)-or($data.GameProfilesBackupCreated-and-not$data.GameProfilesBackupVerified)){Add-Reason 'BACKUP_VERIFICATION_FAILED'}}
      'Smoke File Safety' {foreach($tree in $data.Keys){$x=$data[$tree];if(($x.BeforeSkipped+$x.AfterSkipped)-gt0){Add-Reason 'SMOKE_TREE_UNREADABLE'};if(($x.Added+$x.Removed+$x.Changed)-gt0){Add-Reason 'SMOKE_TREE_CHANGED'}}}
      'Artifacts' {if(-not$data.ReportDirectoryReserved){Add-Reason 'REPORT_DIRECTORY_UNAVAILABLE'};if(-not$data.StagingDirectoryReady){Add-Reason 'STAGING_UNAVAILABLE'};if(-not$data.RequiredArtifactManifestConfigured){Add-Reason 'ARTIFACT_MANIFEST_UNCONFIGURED'};if(-not$data.PublisherAvailable){Add-Reason 'PUBLISHER_UNAVAILABLE'};if(-not$data.PackageValidationExecuted){Add-Reason 'PACKAGE_VALIDATION_NOT_EXECUTED'};if(-not$data.PackageValidationPassed-or$data.PackageValidationErrorCount-gt0){Add-Reason 'PACKAGE_VALIDATION_FAILED'}}
      'pcsx2x6 crosshair path (issue #79)' {if(-not$data.CanonicalFilesDeployed){Add-Reason 'PCSX2_FILES_MISSING'};if(-not$data.IniFound){Add-Reason 'PCSX2_INI_MISSING'};if(-not$data.CursorPathPointsCanonical){Add-Reason 'PCSX2_PATH_NONCANONICAL'};if($data.LegacyRootPresent){Add-Reason 'PCSX2_LEGACY_ROOT_PRESENT'}}
      'Behavioral Certification (Virtual Beta Tester)' {if(-not$data.Executed){Add-Reason 'VBT_NOT_EXECUTED'};if($data.Executed-and$data.Total-eq0){Add-Reason 'VBT_EMPTY'};if($data.Failed-gt0){Add-Reason 'VBT_FAILURES'};if(($data.Passed+$data.Failed)-ne$data.Total){Add-Reason 'VBT_COUNTS_INVALID'}}
      'Unattended TPM root binding' {if($data.EffectiveRootParseState-ceq'Missing'){Add-Reason 'EFFECTIVE_ROOT_MISSING'}elseif($data.EffectiveRootParseState-ceq'Invalid'){Add-Reason 'EFFECTIVE_ROOT_INVALID'}elseif(-not$data.RequestedRoot.Equals($data.EffectiveRoot,[StringComparison]::OrdinalIgnoreCase)){Add-Reason 'EFFECTIVE_ROOT_MISMATCH'}}
      'Unattended TPM config restoration' {if(-not$data.RestoreAttempted){Add-Reason 'RESTORE_NOT_ATTEMPTED'};if($data.RestoreAttempted-and-not$data.RestoreSucceeded){Add-Reason 'RESTORE_FAILED'};if($data.RestoreSucceeded-and-not$data.VerificationSucceeded){Add-Reason 'RESTORE_VERIFICATION_FAILED'};if($data.PriorConfigExisted-and$null-eq$data.SnapshotSha256){Add-Reason 'RESTORE_SNAPSHOT_INVALID'};if(-not$data.PriorConfigExisted-and(-not$data.TemporaryConfigCreated-or-not$data.VerificationSucceeded)){Add-Reason 'TEMP_CONFIG_NOT_REMOVED'}}
    }
    $passed=$reasons.Count-eq0
    return [ordered]@{Identifier=$identifier;Status=$(if($passed){'Pass'}else{'Fail'});Passed=$passed;Details=(Copy-TPMClosedValueV1 $data);FailureReasons=$reasons.ToArray()}
}

function Assert-TPMEvidenceRecordV1 {
    param($Record,$Expected,[string]$EvidenceRoot,[scriptblock]$PngValidator,[Collections.Generic.HashSet[string]]$OwnedPaths)
    $fields=@('Identifier','Status','EvidenceType','Required','Path','CaptureScope','FileSha256','Width','Height','FailureCode','FailureMessage')
    $r=Assert-TPMExactFieldsV1 $Record $fields 'evidence'
    if($r.Identifier-cne$Expected.Identifier){throw 'EVIDENCE_ORDER_INVALID'}
    Assert-TPMBooleanV1 $r.Required 'evidence Required';if($r.Required-ne$Expected.Required){throw 'EVIDENCE_METADATA_INVALID'}
    if(@('Captured','Skipped','Failed')-cnotcontains$r.Status){throw 'EVIDENCE_METADATA_INVALID'}
    if($r.Status-ceq'Captured'){
        if(@('ScreenCapture','DeterministicRender')-cnotcontains$r.EvidenceType){throw 'EVIDENCE_TYPE_INVALID'}
        if($Expected.EvidenceType-and$r.EvidenceType-cne$Expected.EvidenceType){throw 'EVIDENCE_TYPE_INVALID'}
        if($r.EvidenceType-ceq'ScreenCapture'){if(@('ConsoleWindow','BoundedRegion','FullDesktop')-cnotcontains$r.CaptureScope){throw 'EVIDENCE_METADATA_INVALID'}}elseif($r.CaptureScope-cne'Deterministic'){throw 'EVIDENCE_METADATA_INVALID'}
        try { Assert-TPMNormalizedPathV1 $r.Path 'evidence Path';$contained=Resolve-TPMContainedPathV1 -Root $EvidenceRoot -Path $r.Path } catch { if($_.Exception.Message-like'PATH_OUTSIDE_ROOT*'){throw 'EVIDENCE_PATH_OUTSIDE_ROOT'};throw 'EVIDENCE_PATH_INVALID' };if($contained-cne$r.Path){throw 'EVIDENCE_PATH_INVALID'}
        if($OwnedPaths.Contains($contained)){throw 'EVIDENCE_PATH_DUPLICATE'}
        if(-not(Test-Path -LiteralPath $contained -PathType Leaf)){throw 'EVIDENCE_FILE_MISSING'}
        try { $bytes=[IO.File]::ReadAllBytes($contained) } catch [IO.FileNotFoundException] { throw 'EVIDENCE_FILE_MISSING' } catch { throw 'EVIDENCE_FILE_LOCKED' };if($bytes.Length-eq0){throw 'EVIDENCE_FILE_EMPTY'}
        if(-not$PngValidator){throw 'EVIDENCE_CAPTURE_ACTION_MISSING'};try { $validation=&$PngValidator $contained } catch { throw 'EVIDENCE_CAPTURE_EXCEPTION' }
        if(-not$validation-or-not$validation.Valid){throw 'EVIDENCE_PNG_INVALID'}
        Assert-TPMIntegerV1 $r.Width 'evidence Width' 1;Assert-TPMIntegerV1 $r.Height 'evidence Height' 1
        if(($validation.PSObject.Properties.Name-contains'Width'-and[long]$validation.Width-ne[long]$r.Width)-or($validation.PSObject.Properties.Name-contains'Height'-and[long]$validation.Height-ne[long]$r.Height)){throw 'EVIDENCE_DIMENSIONS_INVALID'}
        if($r.FileSha256-cnotmatch'^[0-9a-f]{64}$'){throw 'EVIDENCE_HASH_FAILED'};$actual=Get-TPMSha256HexV1 -Bytes $bytes;if($actual-cne$r.FileSha256){throw 'EVIDENCE_HASH_FAILED'};try { $afterBytes=[IO.File]::ReadAllBytes($contained) } catch { throw 'EVIDENCE_FILE_LOCKED' };if((Get-TPMSha256HexV1 -Bytes $afterBytes)-cne$actual){throw 'EVIDENCE_HASH_FAILED'};if(-not$OwnedPaths.Add($contained)){throw 'EVIDENCE_PATH_DUPLICATE'}
        if($null-ne$r.FailureCode-or$null-ne$r.FailureMessage){throw 'EVIDENCE_METADATA_INVALID'}
    }elseif($r.Status-ceq'Skipped'){
        if($r.Required){throw 'EVIDENCE_REQUIRED_SKIPPED'};foreach($n in @('EvidenceType','Path','CaptureScope','FileSha256','Width','Height')){if($null-ne$r[$n]){throw 'EVIDENCE_METADATA_INVALID'}};if($r.FailureCode-cne'EVIDENCE_SKIPPED'){throw 'EVIDENCE_METADATA_INVALID'};Assert-TPMStringV1 $r.FailureMessage 'FailureMessage'
    }else{
        foreach($n in @('EvidenceType','Path','CaptureScope','FileSha256','Width','Height')){if($null-ne$r[$n]){throw 'EVIDENCE_METADATA_INVALID'}};if($script:TpmEvidenceFailureCodesV1-cnotcontains$r.FailureCode-or$r.FailureCode-ceq'EVIDENCE_SKIPPED'){throw 'EVIDENCE_METADATA_INVALID'};Assert-TPMStringV1 $r.FailureMessage 'FailureMessage'
    }
}

function New-TPMWorkflowAuthorityV1 {
    param([Parameter(Mandatory=$true)][ValidateSet('Smoke','Unattended')][string]$Mode,[Parameter(Mandatory=$true)][string]$EvidenceRoot,[string]$ReportRoot,[scriptblock]$PngValidator)
    Initialize-TPMCertificationTypesV1|Out-Null
    $normalizedRoot=[IO.Path]::GetFullPath($EvidenceRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if([string]::IsNullOrWhiteSpace($ReportRoot)){$ReportRoot=$EvidenceRoot};$normalizedReportRoot=[IO.Path]::GetFullPath($ReportRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $factIdentifiers=@($script:TpmFactIdentifiersV1)
    $evidenceManifest=@($script:TpmEvidenceManifestV1)
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
    try{
        $authority=New-TPMWorkflowAuthorityV1 -Mode $Mode -EvidenceRoot $EvidenceRoot -ReportRoot ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($EvidenceRoot))) -PngValidator $PngValidator;$diagnostic.RunIdentity=&$authority GetRunIdentity
        foreach($fact in @($FactRecords)){&$authority RecordFact $fact}
        $legacy=@($LegacyEvidence)
        if($legacy.Count-ne9){throw "EVIDENCE_MANIFEST_INCOMPLETE: expected 9 legacy records, found $($legacy.Count)"}
        for($i=0;$i-lt8;$i++){$record=ConvertTo-TPMShadowEvidenceRecordV1 $legacy[$i] $script:TpmEvidenceManifestV1[$i] $EvidenceRoot $PngValidator;&$authority RecordEvidence $record}
        $preview=&$authority DeriveScorePreview
        $final=ConvertTo-TPMShadowEvidenceRecordV1 $legacy[8] $script:TpmEvidenceManifestV1[8] $EvidenceRoot $PngValidator
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
Export-ModuleMember -Function New-TPMWorkflowAuthorityV1,Invoke-TPMShadowCertificationV1,New-TPMShadowFactRecordsFromLegacyV1
