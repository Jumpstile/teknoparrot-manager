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
Export-ModuleMember -Function Initialize-TPMCertificationTypesV1,ConvertTo-TPMJcsV1,ConvertTo-TPMFailureMessageBase64UrlV1,ConvertFrom-TPMFailureMessageBase64UrlV1,New-TPMWorkflowAuthorityV1,Get-TPMSha256HexV1,Resolve-TPMContainedPathV1
