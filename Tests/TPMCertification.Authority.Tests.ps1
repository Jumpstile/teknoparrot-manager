#Requires -Module Pester
$modulePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Authority.psm1'
Import-Module $modulePath -Force
Describe 'ADR-0155 Phase 1 compiled authority primitives' {
 It 'loads the complete V1 type set idempotently' {@(Initialize-TPMCertificationTypesV1).Count|Should -Be 10;@(Initialize-TPMCertificationTypesV1).Count|Should -Be 10}
 It 'has no public constructors or setters' {foreach($n in @('TPMScorePreviewV1','TPMSealedRunReaderV1','TPMFactSetV1','TPMFactV1','TPMEvidenceRecordV1','TPMScoreItemV1','TPMEligibilitySnapshotV1','TPMPublicationCandidateV1','TPMPublicationOutcomeV1','TPMFinalOutcomeV1')){$t=('Jumpstile.TPM.Certification.V1.'+$n)-as[type];@($t.GetConstructors()).Count|Should -Be 0;@($t.GetProperties()| Where-Object CanWrite).Count|Should -Be 0}}
 It 'rejects partial incompatible types in a child process' {$engine=if(Get-Command pwsh -ErrorAction SilentlyContinue){(Get-Command pwsh).Source}else{"$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"};$code="Add-Type 'namespace Jumpstile.TPM.Certification.V1 { public class TPMFactV1 {} }'; Import-Module '$modulePath'; try { Initialize-TPMCertificationTypesV1; exit 0 } catch { exit 23 }";$p=Start-Process $engine -ArgumentList @('-NoProfile','-Command',$code) -Wait -PassThru;$p.ExitCode|Should -Be 23}
 It 'rejects a complete but incompatible type set in a child process' {
  $engine=if(Get-Command pwsh -ErrorAction SilentlyContinue){(Get-Command pwsh).Source}else{"$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"}
  $classes=@('TPMScorePreviewV1','TPMSealedRunReaderV1','TPMFactSetV1','TPMFactV1','TPMEvidenceRecordV1','TPMScoreItemV1','TPMEligibilitySnapshotV1','TPMPublicationCandidateV1','TPMPublicationOutcomeV1','TPMFinalOutcomeV1')|ForEach-Object{"public class $_ {}"}
  $code="Add-Type 'namespace Jumpstile.TPM.Certification.V1 { $($classes -join ' ') }'; Import-Module '$modulePath'; try { Initialize-TPMCertificationTypesV1; exit 0 } catch { exit 24 }"
  $process=Start-Process $engine -ArgumentList @('-NoProfile','-Command',$code) -Wait -PassThru
  $process.ExitCode|Should -Be 24
 }
 It 'stores only deeply immutable scalar state' {
  foreach($type in Initialize-TPMCertificationTypesV1){
   foreach($field in $type.BaseType.GetFields([Reflection.BindingFlags]'NonPublic,Instance')){$field.IsInitOnly|Should -BeTrue;$field.FieldType|Should -Be ([string])}
  }
 }
 It 'separates capability and rejects synthetic provenance and post-seal writes' {$a=New-TPMWorkflowAuthorityV1;&$a Record ([ordered]@{b=2;a=1});$r=&$a Seal;(&$a ValidateIssued $r)|Should -BeTrue;$t='Jumpstile.TPM.Certification.V1.TPMSealedRunReaderV1'-as[type];$ctor=$t.GetConstructors([Reflection.BindingFlags]'NonPublic,Instance')[0];$fake=$ctor.Invoke(@($r.RunIdentity,$r.CanonicalJson));(&$a ValidateIssued $fake)|Should -BeFalse;{&$a Record @{x=1}}|Should -Throw;$r.PSObject.Properties.Name|Should -Not -Contain Record}
}
Describe 'ADR-0155 Phase 1 JCS and whole-message transport' {
 It 'matches the RFC 8785 UTF-16 property-order vector for the supported schema subset' {
  $object=@{}
  $object[[string][char]0x20AC]=1;$object[[string][char]13]=2;$object[[string][char]0xFB33]=3;$object['1']=4;$object[([char]0xD83D+[char]0xDE00)]=5;$object[[string][char]0x80]=6;$object[[string][char]0xF6]=7
  ConvertTo-TPMJcsV1 $object|Should -Be ('{"\r":2,"1":4,"'+[char]0x80+'":6,"'+[char]0xF6+'":7,"'+[char]0x20AC+'":1,"'+[char]0xD83D+[char]0xDE00+'":5,"'+[char]0xFB33+'":3}')
 }
 It 'sorts object properties and preserves arrays' {ConvertTo-TPMJcsV1 ([ordered]@{z=@(3,2,1);a=$true})|Should -Be '{"a":true,"z":[3,2,1]}'}
 It 'rejects unsafe integers fractions and unpaired surrogates' {{ConvertTo-TPMJcsV1 ([long]9007199254740992)}|Should -Throw;{ConvertTo-TPMJcsV1 ([double]1.5)}|Should -Throw;{ConvertTo-TPMJcsV1 ([string][char]0xD800)}|Should -Throw}
 It 'round trips the entire JCS string as unpadded base64url' {$m='line'+[char]10+'| heading fence / '+[char]0x263A;$e=ConvertTo-TPMFailureMessageBase64UrlV1 $m;$e|Should -Match '^[A-Za-z0-9_-]+$';$e|Should -Not -Match '=';ConvertFrom-TPMFailureMessageBase64UrlV1 $e|Should -Be $m}
 It 'rejects malformed invalid UTF8 non-string and noncanonical inputs' {{ConvertFrom-TPMFailureMessageBase64UrlV1 'a'}|Should -Throw;{ConvertFrom-TPMFailureMessageBase64UrlV1 '!!!!'}|Should -Throw;$bad=[Convert]::ToBase64String([byte[]](0xC3,0x28)).TrimEnd('=').Replace('+','-').Replace('/','_');{ConvertFrom-TPMFailureMessageBase64UrlV1 $bad}|Should -Throw;$u=New-Object Text.UTF8Encoding($false);$number=[Convert]::ToBase64String($u.GetBytes('1')).TrimEnd('=');{ConvertFrom-TPMFailureMessageBase64UrlV1 $number}|Should -Throw;$slash=[Convert]::ToBase64String($u.GetBytes('"a\/b"')).TrimEnd('=').Replace('+','-').Replace('/','_');{ConvertFrom-TPMFailureMessageBase64UrlV1 $slash}|Should -Throw}
}
Describe 'ADR-0155 Phase 1 hashing and containment' {
    It 'matches the SHA-256 known vector' {
        $bytes = [Text.Encoding]::UTF8.GetBytes('abc')
        Get-TPMSha256HexV1 -Bytes $bytes | Should -Be 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
    }

    It 'accepts a child and rejects sibling-prefix traversal ADS and device paths' {
        $root = Join-Path $TestDrive 'report'
        $child = Join-Path $root 'evidence\capture.png'
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($child)) -Force | Out-Null
        Resolve-TPMContainedPathV1 -Root $root -Path $child | Should -Be ([IO.Path]::GetFullPath($child))
        { Resolve-TPMContainedPathV1 -Root $root -Path (Join-Path $TestDrive 'report-escape\x') } | Should -Throw '*PATH_OUTSIDE_ROOT*'
        { Resolve-TPMContainedPathV1 -Root $root -Path (Join-Path $root '..\escape') } | Should -Throw '*dot segments*'
        { Resolve-TPMContainedPathV1 -Root $root -Path ($child + ':stream') } | Should -Throw '*alternate data*'
        { Resolve-TPMContainedPathV1 -Root $root -Path '\\?\C:\escape.png' } | Should -Throw '*device*'
    }

    It 'rejects an existing reparse point beneath the root' -Skip:(-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
        $root = Join-Path $TestDrive 'root'
        $target = Join-Path $TestDrive 'target'
        $link = Join-Path $root 'link'
        New-Item -ItemType Directory -Path $root,$target -Force | Out-Null
        try { New-Item -ItemType Junction -Path $link -Target $target -ErrorAction Stop | Out-Null }
        catch { Set-ItResult -Skipped -Because 'junction creation is unavailable'; return }
        { Resolve-TPMContainedPathV1 -Root $root -Path (Join-Path $link 'capture.png') } | Should -Throw '*PATH_REPARSE_POINT*'
    }
}
