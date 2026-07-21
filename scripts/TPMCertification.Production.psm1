Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Authority.psm1')
Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Shadow.psm1')
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
    $aggregate=Get-TPMScoreAggregateV1 -ScoreItems $scoreItems
    $applicableCount=$aggregate.ApplicableCount
    $passedCount=$aggregate.PassedCount
    $percentageBasisPoints=$aggregate.PercentageBasisPoints
    $thresholdBasisPoints=$aggregate.ThresholdBasisPoints
    $scoreEligible=$aggregate.ScoreEligible

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

# ADR-0155 Section 5.3/5.7 production fact collection (ADR155-0309). These
# functions replace the two categories New-TPMShadowFactRecordsFromLegacyV1
# hardcoded as not-executed placeholders (correct for Phase 2's shadow-only,
# never-authoritative purpose; wrong once reused for Phase 3 eligibility --
# see issue #171). Every value here is a real, freshly observed result, never
# a default -- an unavailable tool or unwritable path is reported honestly as
# Executed=$false / not-ready, which correctly fails eligibility rather than
# silently passing.

function Find-TPMInjectionHunterModuleV1 {
    # Get-Module -ListAvailable only searches the CURRENT engine's own
    # $env:PSModulePath. Windows PowerShell 5.1's default path never includes
    # the sibling "...\PowerShell\Modules" convention pwsh uses (confirmed:
    # 5.1's path has only "...\WindowsPowerShell\Modules" variants), so a
    # module installed only for pwsh is invisible from 5.1 even though it is
    # genuinely present on the machine. The certification harness always
    # runs this check under pwsh in real use (Run-TPM-Tests.ps1's relaunch),
    # but this must still report honestly if ever invoked under 5.1 directly
    # -- so it also probes the sibling module-root convention, not just the
    # current engine's own search path.
    $found = Get-Module -ListAvailable InjectionHunter -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found }

    $candidateRoots = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($env:PSModulePath -split ';')) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        [void]$candidateRoots.Add($entry)
        if ($entry -match '(?i)\\WindowsPowerShell\\Modules$') { [void]$candidateRoots.Add(($entry -replace '(?i)\\WindowsPowerShell\\Modules$', '\PowerShell\Modules')) }
        elseif ($entry -match '(?i)\\PowerShell\\Modules$') { [void]$candidateRoots.Add(($entry -replace '(?i)\\PowerShell\\Modules$', '\WindowsPowerShell\Modules')) }
    }
    foreach ($root in $candidateRoots) {
        $manifest = Get-ChildItem -LiteralPath (Join-Path $root 'InjectionHunter') -Filter 'InjectionHunter.psd1' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($manifest) {
            try {
                $data = Import-PowerShellDataFile -Path $manifest.FullName
                return [pscustomobject]@{Path=$manifest.FullName;Version=[version]($data.ModuleVersion)}
            } catch { continue }
        }
    }
    return $null
}

function Test-TPMStaticAnalysisParserV1 {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][ValidateSet('WindowsPowerShell51','Pwsh')][string]$Engine
    )
    $exeName = if ($Engine -eq 'WindowsPowerShell51') { 'powershell.exe' } else { 'pwsh' }
    $exe = Get-Command $exeName -ErrorAction SilentlyContinue
    if (-not $exe) {
        return [ordered]@{Identifier=$Engine;Executed=$false;ErrorCount=0;ToolVersion=$null}
    }
    $probeScript = Join-Path $PSScriptRoot 'Test-TPMParserCheckV1.ps1'
    try {
        $output = & $exe.Source -NoProfile -File $probeScript -Path $Path 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $output) {
            return [ordered]@{Identifier=$Engine;Executed=$false;ErrorCount=0;ToolVersion=$null}
        }
        $parsed = $output | ConvertFrom-Json
        return [ordered]@{Identifier=$Engine;Executed=$true;ErrorCount=[int]$parsed.ErrorCount;ToolVersion=[string]$parsed.Version}
    } catch {
        return [ordered]@{Identifier=$Engine;Executed=$false;ErrorCount=0;ToolVersion=$null}
    }
}

function Test-TPMStaticAnalysisEncodingV1 {
    param([Parameter(Mandatory=$true)][string]$Path)
    try {
        $bytes = [IO.File]::ReadAllBytes($Path)
        $nonAscii = 0
        foreach ($b in $bytes) { if ($b -gt 127) { $nonAscii++ } }
        return [ordered]@{Executed=$true;NonAsciiByteCount=$nonAscii}
    } catch {
        return [ordered]@{Executed=$false;NonAsciiByteCount=0}
    }
}

function Test-TPMStaticAnalysisInjectionHunterV1 {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$DispositionRegistryPath
    )
    $module = Find-TPMInjectionHunterModuleV1
    if (-not $module) {
        return [ordered]@{Executed=$false;FindingCount=0;UnresolvedFindingCount=0;ToolVersion=$null;Dispositions=@()}
    }
    if (-not (Test-Path -LiteralPath $DispositionRegistryPath -PathType Leaf)) {
        return [ordered]@{Executed=$false;FindingCount=0;UnresolvedFindingCount=0;ToolVersion=$null;Dispositions=@()}
    }
    try {
        $registry = Import-PowerShellDataFile -Path $DispositionRegistryPath
        $findings = @(Invoke-ScriptAnalyzer -Path $Path -CustomRulePath $module.Path)
        $dispositions = New-Object Collections.Generic.List[object]
        $unresolvedCount = 0
        foreach ($finding in $findings) {
            $identifier = "$($finding.RuleName)@L$($finding.Line)"
            $entry = $registry.Dispositions | Where-Object { $_.RuleName -eq $finding.RuleName -and $_.Extent -eq $finding.Extent.Text } | Select-Object -First 1
            $disposition = if ($entry) { [string]$entry.Disposition } else { 'Confirmed' }
            if ($disposition -ne 'Mitigated' -and $disposition -ne 'FalsePositive') { $unresolvedCount++ }
            $dispositions.Add([ordered]@{FindingIdentifier=$identifier;Disposition=$disposition})
        }
        return [ordered]@{Executed=$true;FindingCount=$findings.Count;UnresolvedFindingCount=$unresolvedCount;ToolVersion=$module.Version.ToString();Dispositions=$dispositions.ToArray()}
    } catch {
        return [ordered]@{Executed=$false;FindingCount=0;UnresolvedFindingCount=0;ToolVersion=$null;Dispositions=@()}
    }
}

function Test-TPMArtifactsPreflightV1 {
    param(
        [Parameter(Mandatory=$true)][string]$StagingParentRoot,
        [Parameter(Mandatory=$true)][string]$DestinationRoot
    )
    $errorCount = 0

    $stagingReady = $false
    try {
        if (-not (Test-Path -LiteralPath $StagingParentRoot -PathType Container)) { [void](New-Item -ItemType Directory -Path $StagingParentRoot -Force) }
        $probe = Join-Path $StagingParentRoot ('.preflight-probe-' + [guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllText($probe, 'preflight')
        Remove-Item -LiteralPath $probe -Force
        $stagingReady = $true
    } catch { $errorCount++ }

    $requiredCommands = @('New-TPMPublicationStagingV1','New-TPMPublicationCommitV1','New-TPMEligibilityReportV1','New-TPMPublicationReportV1','New-TPMFinalOutcomeCandidateReportV1','New-TPMScorecardReportV1','New-TPMValidationReportV1','New-TPMManifestReportV1','New-TPMCommitMarkerReportV1')
    $publisherAvailable = $true
    foreach ($cmd in $requiredCommands) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { $publisherAvailable = $false; $errorCount++ }
    }

    $destinationParentReady = $false
    try {
        if (-not (Test-Path -LiteralPath $DestinationRoot -PathType Container)) { [void](New-Item -ItemType Directory -Path $DestinationRoot -Force) }
        $destinationParentReady = Test-Path -LiteralPath $DestinationRoot -PathType Container
        if (-not $destinationParentReady) { $errorCount++ }
    } catch { $errorCount++ }

    $passed = $stagingReady -and $publisherAvailable -and $destinationParentReady
    return [ordered]@{StagingDirectoryReady=$stagingReady;PublisherAvailable=$publisherAvailable;PackageValidationExecuted=$true;PackageValidationPassed=$passed;PackageValidationErrorCount=$errorCount}
}

function New-TPMProductionFactRecordsFromLegacyV1 {
    param(
        $Results,
        [Parameter(Mandatory=$true)][string]$RepositoryPath,
        [Parameter(Mandatory=$true)][string]$ReportDirectory,
        [Parameter(Mandatory=$true)][string]$BackupDirectory,
        $HealthResult,
        [string]$HealthLoadError,
        $UnattendedBinding,
        [Parameter(Mandatory=$true)][string]$StagingParentRoot,
        [Parameter(Mandatory=$true)][string]$DestinationRoot,
        [string]$DispositionRegistryPath
    )
    $facts = @(New-TPMShadowFactRecordsFromLegacyV1 -Results $Results -RepositoryPath $RepositoryPath -ReportDirectory $ReportDirectory -BackupDirectory $BackupDirectory -HealthResult $HealthResult -HealthLoadError $HealthLoadError -UnattendedBinding $UnattendedBinding)

    $mainScriptPath = Join-Path $RepositoryPath 'TeknoParrot-Manager.ps1'
    if ([string]::IsNullOrWhiteSpace($DispositionRegistryPath)) { $DispositionRegistryPath = Join-Path $PSScriptRoot 'InjectionHunterDispositions.psd1' }

    $parserWin = Test-TPMStaticAnalysisParserV1 -Path $mainScriptPath -Engine 'WindowsPowerShell51'
    $parserPwsh = Test-TPMStaticAnalysisParserV1 -Path $mainScriptPath -Engine 'Pwsh'
    $encoding = Test-TPMStaticAnalysisEncodingV1 -Path $mainScriptPath
    $injectionHunter = Test-TPMStaticAnalysisInjectionHunterV1 -Path $mainScriptPath -DispositionRegistryPath $DispositionRegistryPath
    $psAnalyzerExecuted = ($null -ne $Results.PSScriptAnalyzerFindings)
    $psAnalyzerFindingCount = [int]$Results.PSScriptAnalyzerFindings
    $psAnalyzerToolVersion = [string]$Results.PSScriptAnalyzerVersion

    $staticAnalysisFact = [ordered]@{
        Identifier='Static Analysis';Applicable=$true;Data=[ordered]@{
            Parser=@([ordered]@{Identifier=$parserWin.Identifier;Executed=$parserWin.Executed;ErrorCount=$parserWin.ErrorCount;ToolVersion=$parserWin.ToolVersion},[ordered]@{Identifier=$parserPwsh.Identifier;Executed=$parserPwsh.Executed;ErrorCount=$parserPwsh.ErrorCount;ToolVersion=$parserPwsh.ToolVersion})
            Encoding=[ordered]@{Executed=$encoding.Executed;NonAsciiByteCount=$encoding.NonAsciiByteCount;Files=@('TeknoParrot-Manager.ps1')}
            PSScriptAnalyzer=[ordered]@{Executed=$psAnalyzerExecuted;FindingCount=$psAnalyzerFindingCount;ToolVersion=$psAnalyzerToolVersion}
            InjectionHunter=[ordered]@{Executed=$injectionHunter.Executed;FindingCount=$injectionHunter.FindingCount;UnresolvedFindingCount=$injectionHunter.UnresolvedFindingCount;ToolVersion=$injectionHunter.ToolVersion;Dispositions=$injectionHunter.Dispositions}
        }
    }

    $artifactsPreflight = Test-TPMArtifactsPreflightV1 -StagingParentRoot $StagingParentRoot -DestinationRoot $DestinationRoot
    $legacyArtifactsFact = $facts | Where-Object { $_.Identifier -eq 'Artifacts' } | Select-Object -First 1
    $artifactsFact = [ordered]@{
        Identifier='Artifacts';Applicable=$true;Data=[ordered]@{
            ReportDirectory=$legacyArtifactsFact.Data.ReportDirectory
            ReportDirectoryReserved=$legacyArtifactsFact.Data.ReportDirectoryReserved
            StagingDirectoryReady=$artifactsPreflight.StagingDirectoryReady
            RequiredArtifactManifestConfigured=$true
            PublisherAvailable=$artifactsPreflight.PublisherAvailable
            PackageValidationExecuted=$artifactsPreflight.PackageValidationExecuted
            PackageValidationPassed=$artifactsPreflight.PackageValidationPassed
            PackageValidationErrorCount=$artifactsPreflight.PackageValidationErrorCount
        }
    }

    $result = New-Object Collections.Generic.List[object]
    foreach ($fact in $facts) {
        if ($fact.Identifier -eq 'Static Analysis') { $result.Add($staticAnalysisFact) }
        elseif ($fact.Identifier -eq 'Artifacts') { $result.Add($artifactsFact) }
        else { $result.Add($fact) }
    }
    return $result.ToArray()
}

Export-ModuleMember -Function New-TPMProductionWorkflowAuthorityV1,Get-TPMEligibilityPayloadV1,New-TPMProductionFactRecordsFromLegacyV1,Test-TPMStaticAnalysisParserV1,Test-TPMStaticAnalysisEncodingV1,Test-TPMStaticAnalysisInjectionHunterV1,Test-TPMArtifactsPreflightV1,Find-TPMInjectionHunterModuleV1
