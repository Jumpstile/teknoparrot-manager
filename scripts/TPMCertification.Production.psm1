Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Authority.psm1')
Set-StrictMode -Version 2.0

function Get-TPMEligibilityPayloadV1 {
    param(
        [Parameter(Mandatory=$true)][string]$RunIdentity,
        [Parameter(Mandatory=$true)][ValidateSet('Smoke','Unattended')][string]$Mode,
        [Parameter(Mandatory=$true)]$Facts,
        [Parameter(Mandatory=$true)]$Evidence,
        [Parameter(Mandatory=$true)][string]$FactSetSha256,
        [Parameter(Mandatory=$true)][string]$EvidenceSetSha256,
        [Parameter(Mandatory=$true)][string]$SealedRunSha256
    )
    $factsList=New-Object Collections.Generic.List[object];foreach($fact in $Facts){[void]$factsList.Add($fact)}
    $scoreItems=New-Object Collections.Generic.List[object]
    foreach($fact in $factsList){$scoreItems.Add((Get-TPMFactDecisionV1 $fact $Mode ''))}
    $applicable=New-Object Collections.Generic.List[object];foreach($item in $scoreItems){if($item.Status-cne'NotApplicable'){[void]$applicable.Add($item)}}
    $applicableCount=$applicable.Count
    if($applicableCount-le0){throw 'ELIGIBILITY_INVALID: ApplicableCount must be greater than zero'}
    $passedCount=0;foreach($item in $applicable){if($item.Status-ceq'Pass'){$passedCount++}}
    $percentageBasisPoints=[int][Math]::Round(([decimal]$passedCount*10000/$applicableCount),0,[MidpointRounding]::AwayFromZero)
    $thresholdBasisPoints=10000
    $scoreEligible=($passedCount-eq$applicableCount)-and($percentageBasisPoints-eq$thresholdBasisPoints)

    $evidenceManifest=Get-TPMEvidenceManifestV1
    $evidenceList=New-Object Collections.Generic.List[object];foreach($record in $Evidence){[void]$evidenceList.Add($record)}
    if($evidenceList.Count-ne$evidenceManifest.Count){throw 'ELIGIBILITY_INVALID: evidence manifest count mismatch'}
    $evidenceReasons=New-Object Collections.Generic.List[object]
    for($i=0;$i-lt$evidenceList.Count;$i++){
        $record=$evidenceList[$i];$expected=$evidenceManifest[$i]
        $isFailure=$false
        if($expected.Required-and$record.Status-cne'Captured'){$isFailure=$true}
        elseif(-not$expected.Required-and$record.Status-ceq'Failed'){$isFailure=$true}
        if($isFailure){$evidenceReasons.Add([ordered]@{SourceIdentifier=$record.Identifier;Code=$record.FailureCode;Message=$record.FailureMessage})}
    }
    $evidenceEligible=$evidenceReasons.Count-eq0
    $eligibleForCertification=$scoreEligible-and$evidenceEligible

    $failureReasons=New-Object Collections.Generic.List[object]
    foreach($item in $scoreItems){foreach($reason in @($item.FailureReasons)){$failureReasons.Add([ordered]@{SourceIdentifier=$item.Identifier;Code=$reason.Code;Message=$reason.Message})}}
    foreach($reason in $evidenceReasons){$failureReasons.Add($reason)}

    return [ordered]@{
        SchemaVersion=1
        RunIdentity=$RunIdentity
        Mode=$Mode
        FactSetSha256=$FactSetSha256
        EvidenceSetSha256=$EvidenceSetSha256
        SealedRunSha256=$SealedRunSha256
        ScoreItems=$scoreItems.ToArray()
        ApplicableCount=$applicableCount
        PassedCount=$passedCount
        PercentageBasisPoints=$percentageBasisPoints
        ThresholdBasisPoints=$thresholdBasisPoints
        ScoreEligible=$scoreEligible
        EvidenceEligible=$evidenceEligible
        EligibleForCertification=$eligibleForCertification
        FailureReasons=$failureReasons.ToArray()
    }
}

$script:TpmPublicationFailureCodesV1=@('STAGING_FAILED','PROMOTION_FAILED','MARKER_WRITE_FAILED','DURABLE_VALIDATION_FAILED','ROLLBACK_FAILED')

function Assert-TPMPublicationObservationV1 {
    param($Value)
    $map=Assert-TPMExactFieldsV1 $Value @('ManifestSha256','ArtifactSetSha256','DiagnosticWarnings') 'publication observation'
    if($map.ManifestSha256-cnotmatch'^[0-9a-f]{64}$'){throw 'SCHEMA_INVALID: ManifestSha256'}
    if($map.ArtifactSetSha256-cnotmatch'^[0-9a-f]{64}$'){throw 'SCHEMA_INVALID: ArtifactSetSha256'}
    foreach($warning in @($map.DiagnosticWarnings)){if($warning-cne'POST_COMMIT_CLEANUP_FAILED'){throw 'SCHEMA_INVALID: DiagnosticWarnings'}}
    return $map
}

function Assert-TPMPublicationFailureReasonsV1 {
    param($Value)
    $reasons=@($Value)
    if($reasons.Count-eq0){throw 'SCHEMA_INVALID: publication failure requires at least one reason'}
    foreach($reason in $reasons){
        $map=Assert-TPMExactFieldsV1 $reason @('Code','Message') 'publication failure reason'
        if($script:TpmPublicationFailureCodesV1-cnotcontains$map.Code){throw 'SCHEMA_INVALID: publication failure Code'}
        Assert-TPMStringV1 $map.Message 'publication failure Message'
    }
    return $reasons
}

function New-TPMProductionWorkflowAuthorityV1 {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Smoke','Unattended')][string]$Mode,
        [Parameter(Mandatory=$true)][string]$EvidenceRoot,
        [string]$ReportRoot,
        [scriptblock]$PngValidator
    )
    Initialize-TPMCertificationTypesV1|Out-Null
    $normalizedRoot=[IO.Path]::GetFullPath($EvidenceRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if([string]::IsNullOrWhiteSpace($ReportRoot)){$ReportRoot=$EvidenceRoot}
    $normalizedReportRoot=[IO.Path]::GetFullPath($ReportRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $factIdentifiers=Get-TPMFactIdentifiersV1
    $evidenceManifest=Get-TPMEvidenceManifestV1
    $utf8=New-Object Text.UTF8Encoding($false)
    $assertFact=${function:Assert-TPMFactRecordV1}
    $assertEvidence=${function:Assert-TPMEvidenceRecordV1}
    $copyClosed=${function:Copy-TPMClosedValueV1}
    $factDecision=${function:Get-TPMFactDecisionV1}
    $jcs=${function:ConvertTo-TPMJcsV1}
    $sha256=${function:Get-TPMSha256HexV1}
    $eligibilityPayload=${function:Get-TPMEligibilityPayloadV1}
    $assertPublicationObservation=${function:Assert-TPMPublicationObservationV1}
    $assertPublicationFailureReasons=${function:Assert-TPMPublicationFailureReasonsV1}
    $state=[pscustomobject]@{
        Phase='Collecting';RunIdentity=[guid]::NewGuid().ToString('N');Mode=$Mode
        Facts=(New-Object Collections.Generic.List[object]);Evidence=(New-Object Collections.Generic.List[object])
        FactJson=(New-Object Collections.Generic.List[string]);EvidenceJson=(New-Object Collections.Generic.List[string])
        OwnedPaths=(New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase))
        Registry=@{};Consumed=(New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal))
        SealedFactsArrayJson=$null;SealedEvidenceArrayJson=$null
        EligibilityPayloadSha256=$null;EligibleForCertification=$null;EligibilityFailureReasons=$null
        PublicationCommitted=$null;PublicationFailureReasons=$null
    }
    $issue={param([string]$TypeName,[string]$Purpose,[string]$Json);$type=("Jumpstile.TPM.Certification.V1.$TypeName"-as[type]);$ctor=$type.GetConstructors([Reflection.BindingFlags]'NonPublic,Instance')[0];$object=$ctor.Invoke(@($state.RunIdentity,$Json));$state.Registry[$Purpose]=$object;return $object}.GetNewClosure()
    $validate={param($Object,[string]$Purpose,[switch]$Consume);if(-not$state.Registry.ContainsKey($Purpose)-or-not[object]::ReferenceEquals($state.Registry[$Purpose],$Object)-or$Object.RunIdentity-cne$state.RunIdentity-or$Object.GetType().Namespace-cne'Jumpstile.TPM.Certification.V1'-or$Object.GetType().GetProperty('SchemaVersion',[Reflection.BindingFlags]'Public,Static,FlattenHierarchy').GetValue($null,$null)-ne1-or$state.Consumed.Contains($Purpose)){return $false};if($Consume){[void]$state.Consumed.Add($Purpose)};return $true}.GetNewClosure()
    $dispatch={
        param([string]$Operation,$Value,$Dependency)
        switch -CaseSensitive($Operation){
            'GetPhase'{return $state.Phase}
            'GetRunIdentity'{return $state.RunIdentity}
            'RecordFact'{
                if($state.Phase-cne'Collecting'){throw "ILLEGAL_PHASE: $($state.Phase) RecordFact"}
                $index=$state.Facts.Count;if($index-ge$factIdentifiers.Count){throw 'FACT_DUPLICATE'}
                &$assertFact $Value $state.Mode $normalizedReportRoot
                if($Value.Identifier-cne$factIdentifiers[$index]){throw 'FACT_ORDER_INVALID'}
                $copy=&$copyClosed $Value;$state.Facts.Add($copy);$state.FactJson.Add((&$jcs $copy));return
            }
            'RecordEvidence'{
                if($state.Phase-cne'Collecting'){throw "ILLEGAL_PHASE: $($state.Phase) RecordEvidence"}
                $index=$state.Evidence.Count;if($index-ge8){throw 'EVIDENCE_POST_FINAL'}
                $expected=$evidenceManifest[$index]
                &$assertEvidence $Value $expected $normalizedRoot $PngValidator $state.OwnedPaths
                $copy=&$copyClosed $Value;$state.Evidence.Add($copy);$state.EvidenceJson.Add((&$jcs $copy));return
            }
            'DeriveScorePreview'{
                if($state.Phase-cne'Collecting'){throw "ILLEGAL_PHASE: $($state.Phase) DeriveScorePreview"}
                if($state.Registry.ContainsKey('ScorePreview')){throw 'DUPLICATE_ISSUANCE: ScorePreview'}
                if($state.Facts.Count-ne$factIdentifiers.Count){throw 'FACT_MANIFEST_INCOMPLETE'}
                $items=New-Object Collections.Generic.List[object]
                foreach($fact in $state.Facts){$items.Add((&$factDecision $fact $state.Mode $normalizedReportRoot))}
                $json=&$jcs ([ordered]@{SchemaVersion=1;RunIdentity=$state.RunIdentity;Mode=$state.Mode;ScoreItems=$items.ToArray()})
                return &$issue 'TPMScorePreviewV1' 'ScorePreview' $json
            }
            'IssueFinalEvidence'{
                if($state.Phase-cne'Collecting'){throw "ILLEGAL_PHASE: $($state.Phase) IssueFinalEvidence"}
                if(-not(&$validate $Dependency 'ScorePreview')){throw 'PROVENANCE_INVALID: ScorePreview'}
                if($state.Evidence.Count-ne8){throw 'EVIDENCE_MANIFEST_INCOMPLETE'}
                $expected=$evidenceManifest[8]
                &$assertEvidence $Value $expected $normalizedRoot $PngValidator $state.OwnedPaths
                $copy=&$copyClosed $Value
                if(-not(&$validate $Dependency 'ScorePreview' -Consume)){throw 'PROVENANCE_INVALID: ScorePreview'}
                $state.Evidence.Add($copy);$state.EvidenceJson.Add((&$jcs $copy));$state.Phase='FinalEvidenceIssued';return
            }
            'Seal'{
                if($state.Phase-cne'FinalEvidenceIssued'){throw "ILLEGAL_PHASE: $($state.Phase) Seal"}
                if($state.Facts.Count-ne$factIdentifiers.Count-or$state.Evidence.Count-ne9){throw 'MANIFEST_INCOMPLETE'}
                foreach($i in 0..8){
                    $e=$state.Evidence[$i];$expected=$evidenceManifest[$i]
                    if($e.Identifier-cne$expected.Identifier){throw 'EVIDENCE_ORDER_INVALID'}
                    if($expected.Required-and$e.Status-cne'Captured'){throw 'EVIDENCE_REQUIRED_FAILED'}
                    if(-not$expected.Required-and$e.Status-ceq'Failed'){throw 'EVIDENCE_OPTIONAL_FAILED'}
                }
                $factsArrayJson='['+($state.FactJson.ToArray()-join',')+']'
                $evidenceArrayJson='['+($state.EvidenceJson.ToArray()-join',')+']'
                $json='{"SchemaVersion":1,"RunIdentity":'+(&$jcs $state.RunIdentity)+',"Mode":'+(&$jcs $state.Mode)+',"Facts":'+$factsArrayJson+',"Evidence":'+$evidenceArrayJson+'}'
                $state.SealedFactsArrayJson=$factsArrayJson;$state.SealedEvidenceArrayJson=$evidenceArrayJson
                $state.FactJson.Clear();$state.EvidenceJson.Clear();$state.FactJson=$null;$state.EvidenceJson=$null;$state.OwnedPaths=$null
                $reader=&$issue 'TPMSealedRunReaderV1' 'SealedRun' $json
                $state.Phase='Sealed';return $reader
            }
            'IssueEligibility'{
                if($state.Phase-cne'Sealed'){throw "ILLEGAL_PHASE: $($state.Phase) IssueEligibility"}
                if(-not(&$validate $Value 'SealedRun')){throw 'PROVENANCE_INVALID: SealedRun'}
                if($state.Registry.ContainsKey('Eligibility')){throw 'DUPLICATE_ISSUANCE: Eligibility'}
                $factSetHash=&$sha256 -Bytes ($utf8.GetBytes($state.SealedFactsArrayJson))
                $evidenceSetHash=&$sha256 -Bytes ($utf8.GetBytes($state.SealedEvidenceArrayJson))
                $sealedRunHash=&$sha256 -Bytes ($utf8.GetBytes($Value.CanonicalJson))
                $payload=&$eligibilityPayload -RunIdentity $state.RunIdentity -Mode $state.Mode -Facts $state.Facts -Evidence $state.Evidence -FactSetSha256 $factSetHash -EvidenceSetSha256 $evidenceSetHash -SealedRunSha256 $sealedRunHash
                $payloadJson=&$jcs $payload
                $payloadHash=&$sha256 -Bytes ($utf8.GetBytes($payloadJson))
                $state.EligibilityPayloadSha256=$payloadHash
                $state.EligibleForCertification=[bool]$payload.EligibleForCertification
                $state.EligibilityFailureReasons=$payload.FailureReasons
                $state.Facts=$null;$state.Evidence=$null
                $eligibility=&$issue 'TPMEligibilitySnapshotV1' 'Eligibility' $payloadJson
                $state.Phase='EligibilityIssued';return $eligibility
            }
            'IssuePublicationCandidate'{
                if($state.Phase-cne'EligibilityIssued'){throw "ILLEGAL_PHASE: $($state.Phase) IssuePublicationCandidate"}
                if(-not(&$validate $Value 'Eligibility')){throw 'PROVENANCE_INVALID: Eligibility'}
                if($state.Registry.ContainsKey('PublicationCandidate')){throw 'DUPLICATE_ISSUANCE: PublicationCandidate'}
                $candidate=[ordered]@{SchemaVersion=1;RunIdentity=$state.RunIdentity;EligibilityPayloadSha256=$state.EligibilityPayloadSha256;IntendedState='Committed';RequiredArtifactCount=5;ManifestFileName='TPM-Certification-Manifest.json';CommitMarkerFileName='TPM-Certification-Commit.json'}
                $json=&$jcs $candidate
                $issued=&$issue 'TPMPublicationCandidateV1' 'PublicationCandidate' $json
                $state.Phase='PublicationCandidateIssued';return $issued
            }
            'RegisterCommittedPublication'{
                if($state.Phase-cne'PublicationCandidateIssued'){throw "ILLEGAL_PHASE: $($state.Phase) RegisterCommittedPublication"}
                if(-not(&$validate $Dependency 'PublicationCandidate')){throw 'PROVENANCE_INVALID: PublicationCandidate'}
                if($state.Registry.ContainsKey('PublicationOutcome')){throw 'DUPLICATE_ISSUANCE: PublicationOutcome'}
                $observation=&$assertPublicationObservation $Value
                $outcome=[ordered]@{SchemaVersion=1;RunIdentity=$state.RunIdentity;EligibilityPayloadSha256=$state.EligibilityPayloadSha256;Committed=$true;ManifestSha256=$observation.ManifestSha256;ArtifactSetSha256=$observation.ArtifactSetSha256;FailureReasons=@();DiagnosticWarnings=@($observation.DiagnosticWarnings)}
                $state.PublicationCommitted=$true;$state.PublicationFailureReasons=@()
                $json=&$jcs $outcome
                $issued=&$issue 'TPMPublicationOutcomeV1' 'PublicationOutcome' $json
                $state.Phase='PublicationIssued';return $issued
            }
            'RegisterPublicationFailure'{
                if($state.Phase-cne'EligibilityIssued'-and$state.Phase-cne'PublicationCandidateIssued'){throw "ILLEGAL_PHASE: $($state.Phase) RegisterPublicationFailure"}
                if($state.Registry.ContainsKey('PublicationOutcome')){throw 'DUPLICATE_ISSUANCE: PublicationOutcome'}
                $expectedPurpose=if($state.Phase-ceq'PublicationCandidateIssued'){'PublicationCandidate'}else{'Eligibility'}
                if(-not(&$validate $Dependency $expectedPurpose)){throw "PROVENANCE_INVALID: $expectedPurpose"}
                $reasons=&$assertPublicationFailureReasons $Value
                $outcome=[ordered]@{SchemaVersion=1;RunIdentity=$state.RunIdentity;EligibilityPayloadSha256=$state.EligibilityPayloadSha256;Committed=$false;ManifestSha256=$null;ArtifactSetSha256=$null;FailureReasons=$reasons;DiagnosticWarnings=@()}
                $state.PublicationCommitted=$false;$state.PublicationFailureReasons=$reasons
                $json=&$jcs $outcome
                $issued=&$issue 'TPMPublicationOutcomeV1' 'PublicationOutcome' $json
                $state.Phase='PublicationIssued';return $issued
            }
            'IssueFinalOutcome'{
                if($state.Phase-cne'PublicationIssued'){throw "ILLEGAL_PHASE: $($state.Phase) IssueFinalOutcome"}
                if(-not(&$validate $Value 'Eligibility')){throw 'PROVENANCE_INVALID: Eligibility'}
                if(-not(&$validate $Dependency 'PublicationOutcome')){throw 'PROVENANCE_INVALID: PublicationOutcome'}
                if($state.Registry.ContainsKey('FinalOutcome')){throw 'DUPLICATE_ISSUANCE: FinalOutcome'}
                $certified=[bool]$state.EligibleForCertification-and[bool]$state.PublicationCommitted
                $finalStatus=if($certified){'CERTIFIED'}else{'NOT CERTIFIED'}
                $exitCode=if($certified){0}else{1}
                $failureReasons=New-Object Collections.Generic.List[object]
                foreach($reason in @($state.EligibilityFailureReasons)){$failureReasons.Add($reason)}
                foreach($reason in @($state.PublicationFailureReasons)){$failureReasons.Add($reason)}
                $final=[ordered]@{SchemaVersion=1;RunIdentity=$state.RunIdentity;EligibilityPayloadSha256=$state.EligibilityPayloadSha256;EligibleForCertification=[bool]$state.EligibleForCertification;PublicationCommitted=[bool]$state.PublicationCommitted;FinalStatus=$finalStatus;ExitCode=$exitCode;FailureReasons=$failureReasons.ToArray()}
                $json=&$jcs $final
                $issued=&$issue 'TPMFinalOutcomeV1' 'FinalOutcome' $json
                $state.Phase='FinalOutcomeIssued';return $issued
            }
            'ValidateIssued'{return &$validate $Value ([string]$Dependency)}
            default{throw "UNSUPPORTED_OPERATION: $Operation"}
        }
    }.GetNewClosure()
    return $dispatch
}

Export-ModuleMember -Function New-TPMProductionWorkflowAuthorityV1,Get-TPMEligibilityPayloadV1
