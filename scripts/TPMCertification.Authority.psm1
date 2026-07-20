Set-StrictMode -Version 2.0

function Initialize-TPMCertificationTypesV1 {
    $names = @('TPMScorePreviewV1','TPMSealedRunReaderV1','TPMFactSetV1','TPMFactV1','TPMEvidenceRecordV1','TPMScoreItemV1','TPMEligibilitySnapshotV1','TPMPublicationCandidateV1','TPMPublicationOutcomeV1','TPMFinalOutcomeV1')
    $present = @($names | ForEach-Object { ('Jumpstile.TPM.Certification.V1.' + $_) -as [type] })
    $count = @($present | Where-Object { $_ }).Count
    if ($count -ne 0 -and $count -ne $names.Count) { throw 'incompatible partial V1 type set is loaded' }
    if ($count -eq 0) {
        Add-Type -Language CSharp -TypeDefinition @'
using System;
namespace Jumpstile.TPM.Certification.V1 {
 public abstract class ValueV1 { public const string AuthorityIdentity="ADR-0155-TPM-CERTIFICATION-V1"; readonly string r,j; internal ValueV1(string x,string y){r=x;j=y;} public static int SchemaVersion{get{return  1;}} public string RunIdentity{get{return  r;}} public string CanonicalJson{get{return  j;}} }
 public sealed class TPMScorePreviewV1:ValueV1{internal TPMScorePreviewV1(string r,string j):base(r,j){}}
 public sealed class TPMSealedRunReaderV1:ValueV1{internal TPMSealedRunReaderV1(string r,string j):base(r,j){}}
 public sealed class TPMFactSetV1:ValueV1{internal TPMFactSetV1(string r,string j):base(r,j){}}
 public sealed class TPMFactV1:ValueV1{internal TPMFactV1(string r,string j):base(r,j){}}
 public sealed class TPMEvidenceRecordV1:ValueV1{internal TPMEvidenceRecordV1(string r,string j):base(r,j){}}
 public sealed class TPMScoreItemV1:ValueV1{internal TPMScoreItemV1(string r,string j):base(r,j){}}
 public sealed class TPMEligibilitySnapshotV1:ValueV1{internal TPMEligibilitySnapshotV1(string r,string j):base(r,j){}}
 public sealed class TPMPublicationCandidateV1:ValueV1{internal TPMPublicationCandidateV1(string r,string j):base(r,j){}}
 public sealed class TPMPublicationOutcomeV1:ValueV1{internal TPMPublicationOutcomeV1(string r,string j):base(r,j){}}
 public sealed class TPMFinalOutcomeV1:ValueV1{internal TPMFinalOutcomeV1(string r,string j):base(r,j){}}
}
'@
        $present = @($names | ForEach-Object { ('Jumpstile.TPM.Certification.V1.' + $_) -as [type] })
    }
    foreach ($type in $present) {
        if (-not $type -or @($type.GetConstructors()).Count -ne 0 -or $type.GetProperty('SchemaVersion',[Reflection.BindingFlags]'Public,Static,FlattenHierarchy').GetValue($null,$null) -ne 1 -or $type.GetField('AuthorityIdentity',[Reflection.BindingFlags]'Public,Static,FlattenHierarchy').GetValue($null) -cne 'ADR-0155-TPM-CERTIFICATION-V1' -or $type.Assembly.GetName().Version -ne [version]'0.0.0.0' -or -not [object]::ReferenceEquals($type.Assembly, $present[0].Assembly)) { throw 'incompatible V1 type set is loaded' }
        foreach ($property in $type.GetProperties()) { if ($property.CanWrite) { throw 'mutable V1 type is loaded' } }
    }
    return  $present
}

function ConvertTo-TPMJcsStringV1([AllowEmptyString()][string]$Value) {
 $b=New-Object Text.StringBuilder;[void]$b.Append('"')
 for($i=0;$i-lt$Value.Length;$i++){
  $n=[int][char]$Value[$i]
  if($n-ge0xD800-and$n-le0xDBFF){if($i+1-ge$Value.Length-or[int][char]$Value[$i+1]-lt0xDC00-or[int][char]$Value[$i+1]-gt0xDFFF){throw 'unpaired surrogate'};[void]$b.Append($Value[$i]);$i++;[void]$b.Append($Value[$i]);continue}
  if($n-ge0xDC00-and$n-le0xDFFF){throw 'unpaired surrogate'}
  if($n-eq8){[void]$b.Append('\b')}elseif($n-eq9){[void]$b.Append('\t')}elseif($n-eq10){[void]$b.Append('\n')}elseif($n-eq12){[void]$b.Append('\f')}elseif($n-eq13){[void]$b.Append('\r')}elseif($n-eq34){[void]$b.Append('\"')}elseif($n-eq92){[void]$b.Append('\\')}elseif($n-lt32){[void]$b.Append(('\u{0:x4}'-f $n))}else{[void]$b.Append([char]$n)}
 }
 [void]$b.Append('"');return $b.ToString()
}

function ConvertTo-TPMJcsV1([Parameter(Mandatory=$true)][AllowNull()][AllowEmptyString()]$InputObject) {
    if($null-eq$InputObject){return 'null'};if($InputObject-is[bool]){if($InputObject){return 'true'}else{return 'false'}};if($InputObject-is[string]){return  ConvertTo-TPMJcsStringV1 $InputObject}
    if($InputObject.GetType()-in@([byte],[sbyte],[int16],[uint16],[int32],[uint32],[int64],[uint64])){$n=[decimal]$InputObject;if($n-lt-9007199254740991-or$n-gt9007199254740991){throw 'I-JSON range'};return $n.ToString('0',[Globalization.CultureInfo]::InvariantCulture)}
    if($InputObject-is[Collections.IDictionary]){foreach($key in $InputObject.Keys){if($key-isnot[string]){throw 'JCS object keys must be strings'}};[string[]]$keys=@($InputObject.Keys);[Array]::Sort($keys,[StringComparer]::Ordinal);return '{'+(@($keys|ForEach-Object{(ConvertTo-TPMJcsStringV1 $_)+':'+(ConvertTo-TPMJcsV1 $InputObject[$_])})-join',')+'}'}
    if($InputObject-is[Management.Automation.PSCustomObject]){$properties=@($InputObject.PSObject.Properties);[string[]]$keys=@($properties|ForEach-Object{[string]$_.Name});[Array]::Sort($keys,[StringComparer]::Ordinal);$map=@{};foreach($property in $properties){$map[[string]$property.Name]=$property.Value};return '{'+(@($keys|ForEach-Object{(ConvertTo-TPMJcsStringV1 $_)+':'+(ConvertTo-TPMJcsV1 $map[$_])})-join',')+'}'}
    if($InputObject-is[Collections.IEnumerable]){return '['+(@($InputObject|ForEach-Object{ConvertTo-TPMJcsV1 $_})-join',')+']'}
    throw 'unsupported JCS value'
}
function ConvertTo-TPMFailureMessageBase64UrlV1([AllowEmptyString()][string]$Message){$u=New-Object Text.UTF8Encoding($false,$true);[Convert]::ToBase64String($u.GetBytes((ConvertTo-TPMJcsStringV1 $Message))).TrimEnd('=').Replace('+','-').Replace('/','_')}
function ConvertFrom-TPMFailureMessageBase64UrlV1([string]$Value){
 if(!$Value-or$Value-cnotmatch'^[A-Za-z0-9_-]+$'-or$Value.Length%4-eq1){throw 'malformed base64url'}
 $p=$Value.Replace('-','+').Replace('_','/');if($p.Length%4-eq2){$p+='=='}elseif($p.Length%4-eq3){$p+='='}
 try{$b=[Convert]::FromBase64String($p);$t=(New-Object Text.UTF8Encoding($false,$true)).GetString($b)}catch{throw 'malformed transport'}
 try{$m=ConvertFrom-Json -InputObject $t -ErrorAction Stop}catch{throw 'invalid JSON string'}
 if($m-isnot[string]-or(ConvertTo-TPMJcsStringV1 $m)-cne$t){throw 'noncanonical JSON string'}
 return $m
}
function ConvertTo-TPMJcsBase64UrlV1([Parameter(Mandatory=$true)][string]$CanonicalJson){$u=New-Object Text.UTF8Encoding($false,$true);[Convert]::ToBase64String($u.GetBytes($CanonicalJson)).TrimEnd('=').Replace('+','-').Replace('/','_')}
function ConvertFrom-TPMJcsBase64UrlV1([string]$Value){
 if(!$Value-or$Value-cnotmatch'^[A-Za-z0-9_-]+$'-or$Value.Length%4-eq1){throw 'malformed base64url'}
 $p=$Value.Replace('-','+').Replace('_','/');if($p.Length%4-eq2){$p+='=='}elseif($p.Length%4-eq3){$p+='='}
 try{$b=[Convert]::FromBase64String($p);return (New-Object Text.UTF8Encoding($false,$true)).GetString($b)}catch{throw 'malformed transport'}
}

function New-TPMWorkflowAuthorityV1 {
 Initialize-TPMCertificationTypesV1|Out-Null
 $state=[pscustomobject]@{Phase='Collecting';RunIdentity=[guid]::NewGuid().ToString('N');Records=(New-Object Collections.Generic.List[string]);Issued=$null}
 $dispatch={
  param([string]$Operation,$Value)
  switch -CaseSensitive($Operation){
   'GetPhase'{return $state.Phase}
   'GetRunIdentity'{return $state.RunIdentity}
   'Record'{if($state.Phase-cne'Collecting'){throw "recording forbidden in $($state.Phase)"};$state.Records.Add((ConvertTo-TPMJcsV1 $Value));return}
   'Seal'{if($state.Phase-cne'Collecting'){throw "sealing forbidden in $($state.Phase)"};$json='['+(@($state.Records)-join',')+']';$state.Records.Clear();$type=('Jumpstile.TPM.Certification.V1.TPMSealedRunReaderV1'-as[type]);$ctor=$type.GetConstructors([Reflection.BindingFlags]'NonPublic,Instance')[0];$state.Issued=$ctor.Invoke(@($state.RunIdentity,$json));$state.Phase='Sealed';return $state.Issued}
   'ValidateIssued'{return [object]::ReferenceEquals($state.Issued,$Value)}
   default{throw 'unsupported authority operation'}
  }
 }.GetNewClosure()
 return $dispatch
}

function Get-TPMSha256HexV1 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $sha.Dispose() }
}

function Resolve-TPMContainedPathV1 {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Root) -or [string]::IsNullOrWhiteSpace($Path)) { throw 'PATH_INVALID: root and path are required' }
    foreach ($value in @($Root, $Path)) {
        if ($value.IndexOf([char]0) -ge 0 -or $value -match '^[A-Za-z][A-Za-z0-9+.-]*://') { throw 'PATH_INVALID: NUL and non-file URI syntax are forbidden' }
        if ($value -match '^(\\\\[?.]\\|\\[?][?]\\)') { throw 'PATH_INVALID: device paths are forbidden' }
        $withoutDrive = if ($value.Length -ge 2 -and $value[1] -eq ':') { $value.Substring(2) } else { $value }
        if ($withoutDrive.Contains(':')) { throw 'PATH_INVALID: alternate data streams are forbidden' }
        if (@($value -split '[\\/]' | Where-Object { $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) { throw 'PATH_INVALID: dot segments are forbidden' }
    }
    if (-not [IO.Path]::IsPathRooted($Root)) { throw 'PATH_INVALID: root must be absolute' }
    $canonicalRoot = [IO.Path]::GetFullPath($Root).Replace([IO.Path]::AltDirectorySeparatorChar, [IO.Path]::DirectorySeparatorChar).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $candidateInput = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { [IO.Path]::Combine($canonicalRoot, $Path) }
    $canonicalPath = [IO.Path]::GetFullPath($candidateInput).Replace([IO.Path]::AltDirectorySeparatorChar, [IO.Path]::DirectorySeparatorChar).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $rootVolume = [IO.Path]::GetPathRoot($canonicalRoot)
    $pathVolume = [IO.Path]::GetPathRoot($canonicalPath)
    if (-not $rootVolume.Equals($pathVolume, [StringComparison]::OrdinalIgnoreCase)) { throw 'PATH_OUTSIDE_ROOT: volume differs' }
    $rootParts = @($canonicalRoot.Substring($rootVolume.Length) -split '\\' | Where-Object { $_ })
    $pathParts = @($canonicalPath.Substring($pathVolume.Length) -split '\\' | Where-Object { $_ })
    if ($pathParts.Count -lt $rootParts.Count) { throw 'PATH_OUTSIDE_ROOT: candidate is above root' }
    for ($i = 0; $i -lt $rootParts.Count; $i++) {
        if (-not $rootParts[$i].Equals($pathParts[$i], [StringComparison]::OrdinalIgnoreCase)) { throw 'PATH_OUTSIDE_ROOT: component differs' }
    }
    $probe = $canonicalRoot
    if (Test-Path -LiteralPath $probe) {
        if (((Get-Item -LiteralPath $probe -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'PATH_REPARSE_POINT: root is a reparse point' }
    }
    for ($i = $rootParts.Count; $i -lt $pathParts.Count; $i++) {
        $probe = [IO.Path]::Combine($probe, $pathParts[$i])
        if (Test-Path -LiteralPath $probe) {
            if (((Get-Item -LiteralPath $probe -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'PATH_REPARSE_POINT: component is a reparse point' }
        }
    }
    return $canonicalPath
}
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
function Get-TPMFactIdentifiersV1 { return ,@($script:TpmFactIdentifiersV1) }
function Get-TPMEvidenceManifestV1 { return ,@($script:TpmEvidenceManifestV1) }
function Get-TPMEvidenceFailureCodesV1 { return ,@($script:TpmEvidenceFailureCodesV1) }

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

function Get-TPMScoreAggregateV1 {
    param([Parameter(Mandatory=$true)]$ScoreItems)
    $items=New-Object Collections.Generic.List[object];foreach($item in $ScoreItems){[void]$items.Add($item)}
    $applicable=New-Object Collections.Generic.List[object];foreach($item in $items){if($item.Status-cne'NotApplicable'){[void]$applicable.Add($item)}}
    $applicableCount=$applicable.Count
    if($applicableCount-le0){throw 'ELIGIBILITY_INVALID: ApplicableCount must be greater than zero'}
    $passedCount=0;foreach($item in $applicable){if($item.Status-ceq'Pass'){$passedCount++}}
    $percentageBasisPoints=[int][Math]::Round(([decimal]$passedCount*10000/$applicableCount),0,[MidpointRounding]::AwayFromZero)
    $thresholdBasisPoints=10000
    $scoreEligible=($passedCount-eq$applicableCount)-and($percentageBasisPoints-eq$thresholdBasisPoints)
    return [ordered]@{ApplicableCount=$applicableCount;PassedCount=$passedCount;PercentageBasisPoints=$percentageBasisPoints;ThresholdBasisPoints=$thresholdBasisPoints;ScoreEligible=$scoreEligible}
}

Export-ModuleMember -Function Initialize-TPMCertificationTypesV1,ConvertTo-TPMJcsV1,ConvertTo-TPMFailureMessageBase64UrlV1,ConvertFrom-TPMFailureMessageBase64UrlV1,New-TPMWorkflowAuthorityV1,Get-TPMSha256HexV1,Resolve-TPMContainedPathV1,Get-TPMFactIdentifiersV1,Get-TPMEvidenceManifestV1,Get-TPMEvidenceFailureCodesV1,Assert-TPMFactRecordV1,Get-TPMFactDecisionV1,Assert-TPMEvidenceRecordV1,Copy-TPMClosedValueV1,Assert-TPMExactFieldsV1,Assert-TPMStringV1,Get-TPMScoreAggregateV1,ConvertTo-TPMJcsBase64UrlV1,ConvertFrom-TPMJcsBase64UrlV1
