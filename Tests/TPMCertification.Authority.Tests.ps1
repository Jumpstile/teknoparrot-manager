#Requires -Module Pester
$script:modulePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Authority.psm1'
Import-Module $script:modulePath -Force
$script:tpmAuthorityNonWindowsPwsh=$false
if($PSVersionTable.PSVersion.Major -ge 6){
 $tpmIsWindowsValue=Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue
 $script:tpmAuthorityNonWindowsPwsh=-not[bool]$tpmIsWindowsValue
}
Describe 'ADR-0155 Phase 1 compiled authority primitives' {
 BeforeAll {
  function New-TestCertificationIdentity {
   $commit='a'*40;$hash='a'*64;$snapshot=[ordered]@{Branch='main';Commit=$commit;RemoteRef='origin/main';RemoteCommit=$commit;Clean=$true;RefSnapshotSha256=$hash;ReflogSnapshotSha256=$hash}
   [ordered]@{ExpectedBranch='main';ExpectedCommit=$commit;Start=$snapshot;End=$snapshot;RefMutationDetected=$false;RefMutationReason=$null;IdentityValid=$true}
  }
 }
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
}
Describe 'ADR-0155 Phase 1 JCS and whole-message transport' {
 It 'matches the RFC 8785 UTF-16 property-order vector for the supported schema subset' {
  $object=@{}
  $object[[string][char]0x20AC]=1;$object[[string][char]13]=2;$object[[string][char]0xFB33]=3;$object['1']=4;$object[([char]0xD83D+[char]0xDE00)]=5;$object[[string][char]0x80]=6;$object[[string][char]0xF6]=7
  ConvertTo-TPMJcsV1 $object|Should -Be ('{"\r":2,"1":4,"'+[char]0x80+'":6,"'+[char]0xF6+'":7,"'+[char]0x20AC+'":1,"'+[char]0xD83D+[char]0xDE00+'":5,"'+[char]0xFB33+'":3}')
 }
 It 'sorts object properties and preserves arrays' {ConvertTo-TPMJcsV1 ([ordered]@{z=@(3,2,1);a=$true})|Should -Be '{"a":true,"z":[3,2,1]}'}
 It 'rejects unsafe integers fractions and unpaired surrogates' {{ConvertTo-TPMJcsV1 ([long]9007199254740992)}|Should -Throw;{ConvertTo-TPMJcsV1 ([double]1.5)}|Should -Throw;{ConvertTo-TPMJcsV1 ([string][char]0xD800)}|Should -Throw}
 It 'encodes the entire JCS string as unpadded base64url' {$m='line'+[char]10+'| heading fence / '+[char]0x263A;$e=ConvertTo-TPMFailureMessageBase64UrlV1 $m;$e|Should -Match '^[A-Za-z0-9_-]+$';$e|Should -Not -Match '='}
}
Describe 'ADR-0155 Phase 3 prerequisite: shared fact/evidence primitives extracted from Shadow' {
 BeforeAll {
  function New-TestCertificationIdentity {
   $commit='a'*40;$hash='a'*64;$snapshot=[ordered]@{Branch='main';Commit=$commit;RemoteRef='origin/main';RemoteCommit=$commit;Clean=$true;RefSnapshotSha256=$hash;ReflogSnapshotSha256=$hash}
   [ordered]@{ExpectedBranch='main';ExpectedCommit=$commit;Start=$snapshot;End=$snapshot;RefMutationDetected=$false;RefMutationReason=$null;IdentityValid=$true}
  }
 }
 It 'exports the exact eleven fact identifiers and nine-item evidence manifest used by Phase 2' {
  (Get-TPMFactIdentifiersV1)|Should -Be @('Repository','Pester','Static Analysis','Real Install Health','Backups','Smoke File Safety','Artifacts','pcsx2x6 crosshair path (issue #79)','Behavioral Certification (Virtual Beta Tester)','Unattended TPM root binding','Unattended TPM config restoration')
  (Get-TPMEvidenceManifestV1).Count|Should -Be 9
  (Get-TPMEvidenceManifestV1)[0].Identifier|Should -Be 'certification-suite-running'
  (Get-TPMEvidenceManifestV1)[8].Identifier|Should -Be 'final-certification-result'
  (Get-TPMEvidenceFailureCodesV1)|Should -Contain 'EVIDENCE_SKIPPED'
  (Get-TPMEvidenceFailureCodesV1).Count|Should -Be 19
 }
 It 'validates and decides a Repository fact record identically to the pre-extraction Shadow behavior' {
  $record=[ordered]@{Identifier='Repository';Applicable=$true;Data=[ordered]@{RepositoryPath=(Join-Path $TestDrive 'repo');RepositoryAvailable=$true;RepositoryClean=$true;GitStatus='(clean)';CertificationIdentity=(New-TestCertificationIdentity)}}
  {Assert-TPMFactRecordV1 $record Smoke (Join-Path $TestDrive 'report')}|Should -Not -Throw
  $decision=Get-TPMFactDecisionV1 $record Smoke (Join-Path $TestDrive 'report')
  $decision.Status|Should -Be 'Pass';$decision.Passed|Should -BeTrue
  $bad=[ordered]@{Identifier='NotARealCategory';Applicable=$true;Data=[ordered]@{}}
  {Assert-TPMFactRecordV1 $bad Smoke (Join-Path $TestDrive 'report')}|Should -Throw '*FACT_IDENTIFIER_INVALID*'
 }
 It 'rejects a Repository fact that omits the certification identity seal' {
  $record=[ordered]@{Identifier='Repository';Applicable=$true;Data=[ordered]@{RepositoryPath=(Join-Path $TestDrive 'repo');RepositoryAvailable=$true;RepositoryClean=$true;GitStatus='(clean)'}}
  {Assert-TPMFactRecordV1 $record Smoke (Join-Path $TestDrive 'report')}|Should -Throw '*field count*'
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

    It 'contains a descendant of a drive root and resolves relative children from that root (ASTRA-11)' -Skip:$script:tpmAuthorityNonWindowsPwsh {
        $drive = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($TestDrive))
        $driveName = $drive.Substring(0, 2)
        $leaf = 'tpm-astra11-' + [guid]::NewGuid().ToString('N')
        $expected = $drive + $leaf + '\reports\result.json'
        foreach ($rootSpelling in @($drive, ($driveName + '/'), ($driveName + '\\'), $drive.ToLowerInvariant())) {
            Resolve-TPMContainedPathV1 -Root $rootSpelling -Path $expected | Should -BeExactly $expected
            Resolve-TPMContainedPathV1 -Root $rootSpelling -Path ($driveName + '/' + $leaf + '/reports/result.json') | Should -BeExactly $expected
        }
        # Relative children resolve from the drive root, not from the process's current directory on that drive.
        $savedDirectory = [Environment]::CurrentDirectory
        $elsewhere = Join-Path $TestDrive 'astra11-current-directory'
        New-Item -ItemType Directory -Path $elsewhere -Force | Out-Null
        try {
            [Environment]::CurrentDirectory = $elsewhere
            Resolve-TPMContainedPathV1 -Root $drive -Path ($leaf + '\reports\result.json') | Should -BeExactly $expected
            Resolve-TPMContainedPathV1 -Root $drive -Path ($leaf + '/reports/result.json') | Should -BeExactly $expected
        } finally {
            [Environment]::CurrentDirectory = $savedDirectory
        }
    }

    It 'keeps a normal root contained with trailing and alternate separators' -Skip:$script:tpmAuthorityNonWindowsPwsh {
        $root = Join-Path $TestDrive 'normal-root'
        $child = Join-Path $root 'evidence\capture.png'
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($child)) -Force | Out-Null
        [IO.File]::WriteAllText($child, 'png')
        $expected = [IO.Path]::GetFullPath($child)
        foreach ($rootSpelling in @($root, ($root + '\'), ($root + '\\'), ($root.Replace('\', '/') + '/'))) {
            Resolve-TPMContainedPathV1 -Root $rootSpelling -Path $child | Should -BeExactly $expected
            Resolve-TPMContainedPathV1 -Root $rootSpelling -Path $child.Replace('\', '/') | Should -BeExactly $expected
            Resolve-TPMContainedPathV1 -Root $rootSpelling -Path 'evidence\capture.png' | Should -BeExactly $expected
            Resolve-TPMContainedPathV1 -Root $rootSpelling -Path 'evidence/capture.png' | Should -BeExactly $expected
        }
        { Resolve-TPMContainedPathV1 -Root ($root + '\') -Path ($root + '-escape\x') } | Should -Throw '*PATH_OUTSIDE_ROOT*'
    }

    It 'contains a descendant of a UNC share root with or without a trailing separator' -Skip:$script:tpmAuthorityNonWindowsPwsh {
        $localRoot = Join-Path $TestDrive 'unc-root'
        $child = Join-Path $localRoot 'evidence\capture.png'
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($child)) -Force | Out-Null
        [IO.File]::WriteAllText($child, 'png')
        $localRootFull = [IO.Path]::GetFullPath($localRoot)
        $share = '\\localhost\' + $localRootFull.Substring(0, 1) + '$'
        if (-not (Test-Path -LiteralPath $localRootFull.Replace($localRootFull.Substring(0, 2), $share))) { Set-ItResult -Skipped -Because 'the local administrative share is unavailable'; return }
        $shareChild = $share + '\tpm-astra11-' + [guid]::NewGuid().ToString('N') + '\result.json'
        Resolve-TPMContainedPathV1 -Root $share -Path $shareChild | Should -BeExactly $shareChild
        Resolve-TPMContainedPathV1 -Root ($share + '\') -Path $shareChild | Should -BeExactly $shareChild
        $uncRoot = $share + $localRootFull.Substring(2)
        $uncChild = $share + [IO.Path]::GetFullPath($child).Substring(2)
        Resolve-TPMContainedPathV1 -Root ($uncRoot + '\') -Path $uncChild | Should -BeExactly $uncChild
        Resolve-TPMContainedPathV1 -Root ($uncRoot + '\') -Path 'evidence\capture.png' | Should -BeExactly $uncChild
        Resolve-TPMContainedPathV1 -Root $uncRoot.Replace('\', '/') -Path $uncChild.Replace('\', '/') | Should -BeExactly $uncChild
    }

    It 'refuses other UNC shares, other hosts, drive paths and incomplete UNC roots' -Skip:$script:tpmAuthorityNonWindowsPwsh {
        $shareRoot = '\\tpm-astra11.invalid\share'
        { Resolve-TPMContainedPathV1 -Root $shareRoot -Path '\\tpm-astra11.invalid\share2\x.json' } | Should -Throw '*PATH_OUTSIDE_ROOT*'
        { Resolve-TPMContainedPathV1 -Root ($shareRoot + '\') -Path '\\tpm-astra11.invalid\shareX\x.json' } | Should -Throw '*PATH_OUTSIDE_ROOT*'
        { Resolve-TPMContainedPathV1 -Root $shareRoot -Path '\\other-astra11.invalid\share\x.json' } | Should -Throw '*PATH_OUTSIDE_ROOT*'
        { Resolve-TPMContainedPathV1 -Root $shareRoot -Path 'C:\share\x.json' } | Should -Throw '*PATH_OUTSIDE_ROOT*'
        { Resolve-TPMContainedPathV1 -Root ($shareRoot + '\inner') -Path ($shareRoot + '\inner-escape\x.json') } | Should -Throw '*PATH_OUTSIDE_ROOT*'
        { Resolve-TPMContainedPathV1 -Root '\\tpm-astra11.invalid' -Path ($shareRoot + '\x.json') } | Should -Throw '*root must be absolute*'
        { Resolve-TPMContainedPathV1 -Root '\\tpm-astra11.invalid\' -Path ($shareRoot + '\x.json') } | Should -Throw '*root must be absolute*'
    }

    It 'fails closed for traversal, drive mismatch, drive- or root-relative input, device paths and streams' -Skip:$script:tpmAuthorityNonWindowsPwsh {
        $drive = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($TestDrive))
        $driveName = $drive.Substring(0, 2)
        $otherDrive = if ($driveName -ieq 'Z:') { 'Y:' } else { 'Z:' }
        $root = Join-Path $TestDrive 'closed-root'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        { Resolve-TPMContainedPathV1 -Root $drive -Path ($drive + 'reports\..\..\escape.json') } | Should -Throw '*dot segments*'
        { Resolve-TPMContainedPathV1 -Root $drive -Path '..\escape.json' } | Should -Throw '*dot segments*'
        { Resolve-TPMContainedPathV1 -Root $root -Path '../escape.json' } | Should -Throw '*dot segments*'
        { Resolve-TPMContainedPathV1 -Root ($root + '\..') -Path ($root + '\x.json') } | Should -Throw '*dot segments*'
        { Resolve-TPMContainedPathV1 -Root $drive -Path ($otherDrive + '\reports\result.json') } | Should -Throw '*PATH_OUTSIDE_ROOT*'
        { Resolve-TPMContainedPathV1 -Root ($otherDrive + '\') -Path ($drive + 'reports\result.json') } | Should -Throw '*PATH_OUTSIDE_ROOT*'
        { Resolve-TPMContainedPathV1 -Root $root -Path ($otherDrive + $root.Substring(2) + '\x.json') } | Should -Throw '*PATH_OUTSIDE_ROOT*'
        { Resolve-TPMContainedPathV1 -Root $drive -Path ($driveName + 'reports\result.json') } | Should -Throw '*drive-relative and root-relative*'
        { Resolve-TPMContainedPathV1 -Root $drive -Path '\reports\result.json' } | Should -Throw '*drive-relative and root-relative*'
        { Resolve-TPMContainedPathV1 -Root $drive -Path '/reports/result.json' } | Should -Throw '*drive-relative and root-relative*'
        { Resolve-TPMContainedPathV1 -Root $driveName -Path ($drive + 'reports\result.json') } | Should -Throw '*root must be absolute*'
        { Resolve-TPMContainedPathV1 -Root ($driveName + 'reports') -Path ($drive + 'reports\result.json') } | Should -Throw '*root must be absolute*'
        { Resolve-TPMContainedPathV1 -Root '\reports' -Path ($drive + 'reports\result.json') } | Should -Throw '*root must be absolute*'
        { Resolve-TPMContainedPathV1 -Root $drive -Path ('//?/' + $driveName + '/escape.png') } | Should -Throw '*device*'
        { Resolve-TPMContainedPathV1 -Root $drive -Path ('//./' + $driveName + '/escape.png') } | Should -Throw '*device*'
        { Resolve-TPMContainedPathV1 -Root ('//?/' + $driveName + '/') -Path ($drive + 'x.png') } | Should -Throw '*device*'
        { Resolve-TPMContainedPathV1 -Root $drive -Path ($drive + 'reports\result.json:stream') } | Should -Throw '*alternate data*'
    }

    It 'resolves 8.3 short-name spellings to the long path or fails closed, never outside the root' -Skip:$script:tpmAuthorityNonWindowsPwsh {
        $parent = Join-Path $TestDrive 'short-names'
        $long = Join-Path $parent 'LongDirectoryName12345'
        $sibling = Join-Path $parent 'LongDirectoryNameSibling'
        New-Item -ItemType Directory -Path $long,$sibling -Force | Out-Null
        $existing = Join-Path $long 'existing.txt'
        [IO.File]::WriteAllText($existing, 'x')
        try {
            $fso = New-Object -ComObject Scripting.FileSystemObject
            $short = [string]$fso.GetFolder($long).ShortPath
            $siblingShort = [string]$fso.GetFolder($sibling).ShortPath
        } catch { Set-ItResult -Skipped -Because 'short-name lookup is unavailable'; return }
        if ([IO.Path]::GetFileName($short) -ieq [IO.Path]::GetFileName($long)) { Set-ItResult -Skipped -Because '8.3 short names are disabled on this volume'; return }
        $expectedExisting = [IO.Path]::GetFullPath($existing)
        Resolve-TPMContainedPathV1 -Root $short -Path $existing | Should -BeExactly $expectedExisting
        Resolve-TPMContainedPathV1 -Root $long -Path (Join-Path $short 'existing.txt') | Should -BeExactly $expectedExisting
        # A short spelling of a path that does not exist yet is expanded by PowerShell 7 and left partly short by
        # Windows PowerShell 5.1; either way it must come back as the long path inside the root or be refused.
        $expectedNew = Join-Path ([IO.Path]::GetFullPath($long)) 'sub\new.txt'
        $outcome = try { Resolve-TPMContainedPathV1 -Root $long -Path (Join-Path $short 'sub\new.txt') } catch { $_.Exception.Message }
        ($outcome -ceq $expectedNew -or $outcome -like 'PATH_OUTSIDE_ROOT*') | Should -BeTrue -Because "got '$outcome'"
        { Resolve-TPMContainedPathV1 -Root $long -Path (Join-Path $siblingShort 'x.txt') } | Should -Throw '*PATH_OUTSIDE_ROOT*'
        { Resolve-TPMContainedPathV1 -Root $siblingShort -Path $existing } | Should -Throw '*PATH_OUTSIDE_ROOT*'
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

Describe 'Artifacts publisher diagnostics (issue #296)' {
    It 'keeps publication failure code/message detail in both authority details and broad failure reasons' {
        $report=Join-Path $TestDrive 'artifact-diagnostics-report'
        New-Item -ItemType Directory -Path $report -Force|Out-Null
        $diagnostic=[ordered]@{Stage='PublicationCommit';FailureCode='STAGING_FAILED';FailureMessage='staging rejected the certification manifest';ExceptionType=$null}
        $record=[ordered]@{Identifier='Artifacts';Applicable=$true;Data=[ordered]@{ReportDirectory=$report;ReportDirectoryReserved=$false;StagingDirectoryReady=$true;RequiredArtifactManifestConfigured=$true;PublisherAvailable=$false;PackageValidationExecuted=$true;PackageValidationPassed=$false;PackageValidationErrorCount=1;PackageValidationDiagnostics=@($diagnostic)}}
        {Assert-TPMFactRecordV1 $record Smoke $report}|Should -Not -Throw
        $decision=Get-TPMFactDecisionV1 $record Smoke $report
        @($decision.FailureReasons.Code)|Should -Contain 'PUBLISHER_UNAVAILABLE'
        @($decision.FailureReasons.Code)|Should -Contain 'PACKAGE_VALIDATION_FAILED'
        @($decision.FailureReasons|Where-Object Code -eq 'PUBLISHER_UNAVAILABLE')[0].Message|Should -Match 'STAGING_FAILED'
        @($decision.FailureReasons|Where-Object Code -eq 'PUBLISHER_UNAVAILABLE')[0].Message|Should -Match 'staging rejected the certification manifest'
        $decision.Details.PackageValidationDiagnostics[0].FailureCode|Should -Be 'STAGING_FAILED'
        $decision.Details.PackageValidationDiagnostics[0].FailureMessage|Should -Be 'staging rejected the certification manifest'
    }

    It 'rejects a malformed publisher diagnostic instead of reducing it to a generic error count' {
        $report=Join-Path $TestDrive 'malformed-artifact-diagnostics-report'
        New-Item -ItemType Directory -Path $report -Force|Out-Null
        $bad=[ordered]@{Stage='PublicationCommit';FailureCode='PROMOTION_FAILED';FailureMessage='';ExceptionType=$null}
        $record=[ordered]@{Identifier='Artifacts';Applicable=$true;Data=[ordered]@{ReportDirectory=$report;ReportDirectoryReserved=$true;StagingDirectoryReady=$true;RequiredArtifactManifestConfigured=$true;PublisherAvailable=$false;PackageValidationExecuted=$true;PackageValidationPassed=$false;PackageValidationErrorCount=1;PackageValidationDiagnostics=@($bad)}}
        {Assert-TPMFactRecordV1 $record Smoke $report}|Should -Throw '*PackageValidationDiagnostics*'
    }
}
