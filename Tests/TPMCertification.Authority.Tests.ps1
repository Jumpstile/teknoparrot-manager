#Requires -Module Pester
$script:modulePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Authority.psm1'
Import-Module $script:modulePath -Force
$script:tpmAuthorityNonWindowsPwsh=$false
if($PSVersionTable.PSVersion.Major -ge 6){
 $tpmIsWindowsValue=Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue
 $script:tpmAuthorityNonWindowsPwsh=-not[bool]$tpmIsWindowsValue
}
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
 It 'stores only deeply immutable scalar state in each derived type and its base type' {
  foreach($type in Initialize-TPMCertificationTypesV1){
   $type.BaseType.FullName|Should -Be 'Jumpstile.TPM.Certification.V1.ValueV1'
   foreach($level in @($type,$type.BaseType)){
    $level|Should -Not -BeNullOrEmpty
    foreach($field in $level.GetFields([Reflection.BindingFlags]'Public,NonPublic,Instance,DeclaredOnly')){$field.IsInitOnly|Should -BeTrue;$field.FieldType|Should -Be ([string])}
    @($level.GetProperties([Reflection.BindingFlags]'Public,Instance,DeclaredOnly')|Where-Object CanWrite).Count|Should -Be 0
   }
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
 It 'rejects malformed invalid UTF8 non-string and noncanonical inputs' {{ConvertFrom-TPMFailureMessageBase64UrlV1 'a'}|Should -Throw;{ConvertFrom-TPMFailureMessageBase64UrlV1 '!!!!'}|Should -Throw;$valid=ConvertTo-TPMFailureMessageBase64UrlV1 'padded';{ConvertFrom-TPMFailureMessageBase64UrlV1 ($valid+'=')}|Should -Throw;$bad=[Convert]::ToBase64String([byte[]](0xC3,0x28)).TrimEnd('=').Replace('+','-').Replace('/','_');{ConvertFrom-TPMFailureMessageBase64UrlV1 $bad}|Should -Throw;$u=New-Object Text.UTF8Encoding($false);$number=[Convert]::ToBase64String($u.GetBytes('1')).TrimEnd('=');{ConvertFrom-TPMFailureMessageBase64UrlV1 $number}|Should -Throw;$slash=[Convert]::ToBase64String($u.GetBytes('"a\/b"')).TrimEnd('=').Replace('+','-').Replace('/','_');{ConvertFrom-TPMFailureMessageBase64UrlV1 $slash}|Should -Throw}
}
Describe 'ADR-0155 Phase 3 prerequisite: shared fact/evidence primitives extracted from Shadow' {
 It 'exports the exact eleven fact identifiers and nine-item evidence manifest used by Phase 2' {
  (Get-TPMFactIdentifiersV1)|Should -Be @('Repository','Pester','Static Analysis','Real Install Health','Backups','Smoke File Safety','Artifacts','pcsx2x6 crosshair path (issue #79)','Behavioral Certification (Virtual Beta Tester)','Unattended TPM root binding','Unattended TPM config restoration')
  (Get-TPMEvidenceManifestV1).Count|Should -Be 9
  (Get-TPMEvidenceManifestV1)[0].Identifier|Should -Be 'certification-suite-running'
  (Get-TPMEvidenceManifestV1)[8].Identifier|Should -Be 'final-certification-result'
  (Get-TPMEvidenceFailureCodesV1)|Should -Contain 'EVIDENCE_SKIPPED'
  (Get-TPMEvidenceFailureCodesV1).Count|Should -Be 19
 }
 It 'validates and decides a Repository fact record identically to the pre-extraction Shadow behavior' {
  $record=[ordered]@{Identifier='Repository';Applicable=$true;Data=[ordered]@{RepositoryPath=(Join-Path $TestDrive 'repo');RepositoryAvailable=$true;RepositoryClean=$true;GitStatus='(clean)'}}
  {Assert-TPMFactRecordV1 $record Smoke (Join-Path $TestDrive 'report')}|Should -Not -Throw
  $decision=Get-TPMFactDecisionV1 $record Smoke (Join-Path $TestDrive 'report')
  $decision.Status|Should -Be 'Pass';$decision.Passed|Should -BeTrue
  $bad=[ordered]@{Identifier='NotARealCategory';Applicable=$true;Data=[ordered]@{}}
  {Assert-TPMFactRecordV1 $bad Smoke (Join-Path $TestDrive 'report')}|Should -Throw '*FACT_IDENTIFIER_INVALID*'
 }
 It 'returns NotApplicable with a null Passed value for an inapplicable category' {
  $record=[ordered]@{Identifier='Smoke File Safety';Applicable=$false;Data=[ordered]@{}}
  $decision=Get-TPMFactDecisionV1 $record Unattended (Join-Path $TestDrive 'report')
  $decision.Status|Should -Be 'NotApplicable';$decision.Passed|Should -BeNullOrEmpty
 }
 It 'validates a captured evidence record against the manifest and rejects a mismatched identifier' {
  $root=Join-Path $TestDrive 'evidence-primitives';New-Item -ItemType Directory -Path $root -Force|Out-Null
  $path=Join-Path $root '0.png';[IO.File]::WriteAllBytes($path,[byte[]](137,80,78,71,13,10,26,10,1))
  $sha=[Security.Cryptography.SHA256]::Create();try{$hash=-join($sha.ComputeHash([IO.File]::ReadAllBytes($path))|ForEach-Object{$_.ToString('x2')})}finally{$sha.Dispose()}
  $expected=(Get-TPMEvidenceManifestV1)[0]
  $record=[ordered]@{Identifier=$expected.Identifier;Status='Captured';EvidenceType='ScreenCapture';Required=$true;Path=$path;CaptureScope='ConsoleWindow';FileSha256=$hash;Width=1;Height=1;FailureCode=$null;FailureMessage=$null}
  $validator={param($p)[pscustomobject]@{Valid=$true;Reason='ok';Width=1;Height=1}}
  $owned=New-Object 'Collections.Generic.HashSet[string]'
  {Assert-TPMEvidenceRecordV1 $record $expected $root $validator $owned}|Should -Not -Throw
  $mismatched=[ordered]@{Identifier='wrong-identifier';Status='Captured';EvidenceType='ScreenCapture';Required=$true;Path=$path;CaptureScope='ConsoleWindow';FileSha256=$hash;Width=1;Height=1;FailureCode=$null;FailureMessage=$null}
  {Assert-TPMEvidenceRecordV1 $mismatched $expected $root $validator $owned}|Should -Throw '*EVIDENCE_ORDER_INVALID*'
 }
 It 'returns a defensive copy that caller mutation cannot reach back into' {
  $original=[ordered]@{Nested=[ordered]@{Value=1}}
  $copy=Copy-TPMClosedValueV1 $original
  $original.Nested.Value=2
  $copy.Nested.Value|Should -Be 1
 }
 It 'aggregates score items into ApplicableCount, PassedCount, and rounded PercentageBasisPoints' {
  $items=@(
   [pscustomobject]@{Identifier='a';Status='Pass'}
   [pscustomobject]@{Identifier='b';Status='Fail'}
   [pscustomobject]@{Identifier='c';Status='NotApplicable'}
  )
  $aggregate=Get-TPMScoreAggregateV1 -ScoreItems $items
  $aggregate.ApplicableCount|Should -Be 2
  $aggregate.PassedCount|Should -Be 1
  $aggregate.PercentageBasisPoints|Should -Be 5000
  $aggregate.ThresholdBasisPoints|Should -Be 10000
  $aggregate.ScoreEligible|Should -BeFalse
 }
 It 'reports ScoreEligible true only when every applicable item passes and the percentage is exactly 10000' {
  $items=@([pscustomobject]@{Identifier='a';Status='Pass'},[pscustomobject]@{Identifier='b';Status='Pass'})
  (Get-TPMScoreAggregateV1 -ScoreItems $items).ScoreEligible|Should -BeTrue
 }
 It 'throws when every item is NotApplicable' {
  $items=@([pscustomobject]@{Identifier='a';Status='NotApplicable'})
  {Get-TPMScoreAggregateV1 -ScoreItems $items}|Should -Throw '*ApplicableCount*'
 }
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

    It 'rejects an existing reparse point beneath the root' -Skip:$script:tpmAuthorityNonWindowsPwsh {
        $root = Join-Path $TestDrive 'root'
        $target = Join-Path $TestDrive 'target'
        $link = Join-Path $root 'link'
        New-Item -ItemType Directory -Path $root,$target -Force | Out-Null
        try { New-Item -ItemType Junction -Path $link -Target $target -ErrorAction Stop | Out-Null }
        catch { Set-ItResult -Skipped -Because 'junction creation is unavailable'; return }
        { Resolve-TPMContainedPathV1 -Root $root -Path (Join-Path $link 'capture.png') } | Should -Throw '*PATH_REPARSE_POINT*'
    }
}

Describe 'Assert-TPMDiagnosticRecordV1 (Item 3 audit, ADR155-0309 follow-up round)' {
    It 'accepts a well-formed Diagnostic with a null ExceptionType' {
        { Assert-TPMDiagnosticRecordV1 -Value ([ordered]@{Stage='SOME_STAGE';ExceptionType=$null;Message='a message'}) -Context 'Test' } | Should -Not -Throw
    }
    It 'accepts a well-formed Diagnostic with a string ExceptionType' {
        { Assert-TPMDiagnosticRecordV1 -Value ([ordered]@{Stage='SOME_STAGE';ExceptionType='System.Exception';Message='a message'}) -Context 'Test' } | Should -Not -Throw
    }
    It 'accepts $null when -Nullable is set (the documented Executed=true contract)' {
        { Assert-TPMDiagnosticRecordV1 -Value $null -Context 'Test' -Nullable } | Should -Not -Throw
    }
    It 'rejects $null when -Nullable is not set' {
        { Assert-TPMDiagnosticRecordV1 -Value $null -Context 'Test' } | Should -Throw '*SCHEMA_INVALID: Test is required*'
    }
    It 'rejects a missing Stage field' {
        { Assert-TPMDiagnosticRecordV1 -Value ([ordered]@{ExceptionType=$null;Message='m'}) -Context 'Test' } | Should -Throw '*SCHEMA_INVALID: Test must have exactly Stage*'
    }
    It 'rejects a blank Stage value' {
        { Assert-TPMDiagnosticRecordV1 -Value ([ordered]@{Stage=' ';ExceptionType=$null;Message='m'}) -Context 'Test' } | Should -Throw '*SCHEMA_INVALID: Test.Stage*'
    }
    It 'rejects a non-string, non-null ExceptionType' {
        { Assert-TPMDiagnosticRecordV1 -Value ([ordered]@{Stage='S';ExceptionType=42;Message='m'}) -Context 'Test' } | Should -Throw '*SCHEMA_INVALID: Test.ExceptionType must be null or a string*'
    }
    It 'rejects a missing Message field' {
        { Assert-TPMDiagnosticRecordV1 -Value ([ordered]@{Stage='S';ExceptionType=$null}) -Context 'Test' } | Should -Throw '*SCHEMA_INVALID: Test must have exactly Stage*'
    }
    It 'rejects a blank Message value' {
        { Assert-TPMDiagnosticRecordV1 -Value ([ordered]@{Stage='S';ExceptionType=$null;Message=''}) -Context 'Test' } | Should -Throw '*SCHEMA_INVALID: Test.Message*'
    }
    It 'rejects an extra, unexpected field' {
        { Assert-TPMDiagnosticRecordV1 -Value ([ordered]@{Stage='S';ExceptionType=$null;Message='m';Extra='x'}) -Context 'Test' } | Should -Throw '*SCHEMA_INVALID: Test must have exactly Stage*'
    }
}
