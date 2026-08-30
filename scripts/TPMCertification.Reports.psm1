Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Authority.psm1')
Set-StrictMode -Version 2.0

function New-TPMEligibilityReportV1 {
    param([Parameter(Mandatory=$true)]$Eligibility)
    if($null-eq$Eligibility-or$Eligibility.GetType().FullName-cne'Jumpstile.TPM.Certification.V1.TPMEligibilitySnapshotV1'){throw 'REPORT_INVALID: Eligibility must be an issued TPMEligibilitySnapshotV1'}
    $utf8=New-Object Text.UTF8Encoding($false)
    $payloadHash=Get-TPMSha256HexV1 -Bytes ($utf8.GetBytes($Eligibility.CanonicalJson))
    $integrityJson=ConvertTo-TPMJcsV1 ([ordered]@{Algorithm='SHA-256';EligibilityPayloadSha256=$payloadHash})
    $json='{"Integrity":'+$integrityJson+',"Payload":'+$Eligibility.CanonicalJson+'}'
    $bytes=$utf8.GetBytes($json)
    return [pscustomobject]@{
        FileName='TPM-Certification-Eligibility.json'
        Json=$json
        Bytes=$bytes
        ByteLength=$bytes.Length
        EligibilityPayloadSha256=$payloadHash
    }
}

$script:TpmFinalEvidenceEligibleStatusV1='ELIGIBLE'
$script:TpmFinalEvidenceNotEligibleStatusV1='NOT ELIGIBLE PENDING EVIDENCE AND PUBLICATION'

function Get-TPMFinalEvidenceStatusV1 {
    param([Parameter(Mandatory=$true)]$ScorePreview)
    if($null-eq$ScorePreview-or$ScorePreview.GetType().FullName-cne'Jumpstile.TPM.Certification.V1.TPMScorePreviewV1'){throw 'REPORT_INVALID: ScorePreview must be an issued TPMScorePreviewV1'}
    try{$parsed=ConvertFrom-Json -InputObject $ScorePreview.CanonicalJson -ErrorAction Stop}catch{throw 'REPORT_INVALID: ScorePreview.CanonicalJson did not parse as JSON'}
    if($null-eq$parsed-or$null-eq$parsed.ScoreItems){throw 'REPORT_INVALID: ScorePreview is missing ScoreItems'}
    $aggregate=Get-TPMScoreAggregateV1 -ScoreItems $parsed.ScoreItems
    $status=if($aggregate.ScoreEligible){$script:TpmFinalEvidenceEligibleStatusV1}else{$script:TpmFinalEvidenceNotEligibleStatusV1}
    return [pscustomobject]@{
        Status=$status
        ScoreEligible=$aggregate.ScoreEligible
        ApplicableCount=$aggregate.ApplicableCount
        PassedCount=$aggregate.PassedCount
        PercentageBasisPoints=$aggregate.PercentageBasisPoints
    }
}

function New-TPMPublicationReportV1 {
    param([Parameter(Mandatory=$true)]$PublicationCandidate)
    if($null-eq$PublicationCandidate-or$PublicationCandidate.GetType().FullName-cne'Jumpstile.TPM.Certification.V1.TPMPublicationCandidateV1'){throw 'REPORT_INVALID: PublicationCandidate must be an issued TPMPublicationCandidateV1'}
    $utf8=New-Object Text.UTF8Encoding($false)
    $bytes=$utf8.GetBytes($PublicationCandidate.CanonicalJson)
    return [pscustomobject]@{
        FileName='TPM-Certification-Publication.json'
        Json=$PublicationCandidate.CanonicalJson
        Bytes=$bytes
        ByteLength=$bytes.Length
    }
}

function New-TPMFinalOutcomeReportV1 {
    param([Parameter(Mandatory=$true)]$FinalOutcome,[switch]$CertificationOnly)
    if($null-eq$FinalOutcome-or$FinalOutcome.GetType().FullName-cne'Jumpstile.TPM.Certification.V1.TPMFinalOutcomeV1'){throw 'REPORT_INVALID: FinalOutcome must be an issued TPMFinalOutcomeV1'}
    try{$parsed=ConvertFrom-Json -InputObject $FinalOutcome.CanonicalJson -ErrorAction Stop}catch{throw 'REPORT_INVALID: FinalOutcome.CanonicalJson did not parse as JSON'}
    foreach($field in @('SchemaVersion','RunIdentity','EligibilityPayloadSha256','EligibleForCertification','PublicationCommitted','FinalStatus','ExitCode')){
        if($null-eq$parsed.PSObject.Properties[$field]){throw "REPORT_INVALID: FinalOutcome is missing $field"}
    }
    $eligibilityStatus=if([bool]$parsed.EligibleForCertification){'Eligible'}else{'NotEligible'}
    $candidate=[ordered]@{
        SchemaVersion=1
        RunIdentity=[string]$parsed.RunIdentity
        EligibilityPayloadSha256=[string]$parsed.EligibilityPayloadSha256
        EligibilityStatus=$eligibilityStatus
        RequiredPublicationState=if($CertificationOnly){'NotRequiredForCertification'}else{'Committed'}
        FinalStatus=[string]$parsed.FinalStatus
        ExitCode=[int]$parsed.ExitCode
    }
    $json=ConvertTo-TPMJcsV1 $candidate
    $utf8=New-Object Text.UTF8Encoding($false)
    $bytes=$utf8.GetBytes($json)
    return [pscustomobject]@{
        FileName='TPM-Certification-Final-Outcome.json'
        Json=$json
        Bytes=$bytes
        ByteLength=$bytes.Length
    }
}

function New-TPMFinalOutcomeCandidateReportV1 {
    # ADR-0155 Section 8.3 candidate artifact, distinct from Section 9's
    # runtime TPMFinalOutcomeV1 (built by New-TPMFinalOutcomeReportV1, which
    # this function does not modify or relax). This candidate is derived from
    # eligibility alone -- available immediately after IssueEligibility, long
    # before any publication attempt -- so it can be staged into the
    # publication bundle's manifest without depending on an already-committed
    # publication outcome. It carries EligibilityStatus/RequiredPublicationState
    # (not the real EligibleForCertification/PublicationCommitted Booleans) and
    # has no FailureReasons, exactly matching Section 8.3's schema. It must
    # never be accepted by New-TPMFinalOutcomeProjectionV1 or any other
    # runtime certification/console/exit-code path -- only a genuine
    # dispatcher-issued TPMFinalOutcomeV1, reflecting real PublicationCommitted
    # state, may drive that decision.
    param([Parameter(Mandatory=$true)]$Eligibility)
    if($null-eq$Eligibility-or$Eligibility.GetType().FullName-cne'Jumpstile.TPM.Certification.V1.TPMEligibilitySnapshotV1'){throw 'REPORT_INVALID: Eligibility must be an issued TPMEligibilitySnapshotV1'}
    try{$parsed=ConvertFrom-Json -InputObject $Eligibility.CanonicalJson -ErrorAction Stop}catch{throw 'REPORT_INVALID: Eligibility.CanonicalJson did not parse as JSON'}
    foreach($field in @('RunIdentity','EligibleForCertification')){if($null-eq$parsed.PSObject.Properties[$field]){throw "REPORT_INVALID: Eligibility is missing $field"}}
    $utf8=New-Object Text.UTF8Encoding($false)
    $payloadHash=Get-TPMSha256HexV1 -Bytes ($utf8.GetBytes($Eligibility.CanonicalJson))
    $certified=[bool]$parsed.EligibleForCertification
    $eligibilityStatus=if($certified){'Eligible'}else{'NotEligible'}
    $finalStatus=if($certified){'CERTIFIED'}else{'NOT CERTIFIED'}
    $exitCode=if($certified){0}else{1}
    $candidate=[ordered]@{
        SchemaVersion=1
        RunIdentity=[string]$parsed.RunIdentity
        EligibilityPayloadSha256=$payloadHash
        EligibilityStatus=$eligibilityStatus
        RequiredPublicationState='Committed'
        FinalStatus=$finalStatus
        ExitCode=$exitCode
    }
    $json=ConvertTo-TPMJcsV1 $candidate
    $bytes=$utf8.GetBytes($json)
    return [pscustomobject]@{
        FileName='TPM-Certification-Final-Outcome.json'
        Json=$json
        Bytes=$bytes
        ByteLength=$bytes.Length
    }
}

function New-TPMFinalOutcomeProjectionV1 {
    param([Parameter(Mandatory=$true)]$FinalOutcome)
    $report=New-TPMFinalOutcomeReportV1 -FinalOutcome $FinalOutcome
    $parsed=ConvertFrom-Json -InputObject $report.Json
    Assert-TPMMarkdownRunIdentityV1 ([string]$parsed.RunIdentity)
    if(@('CERTIFIED','NOT CERTIFIED')-cnotcontains[string]$parsed.FinalStatus){throw 'REPORT_INVALID: FinalStatus must be CERTIFIED or NOT CERTIFIED'}
    if([int]$parsed.ExitCode-ne0-and[int]$parsed.ExitCode-ne1){throw 'REPORT_INVALID: ExitCode must be 0 or 1'}
    if(([string]$parsed.FinalStatus-ceq'CERTIFIED')-ne([int]$parsed.ExitCode-eq0)){throw 'REPORT_INVALID: FinalStatus and ExitCode disagree'}
    $runIdentity=[string]$parsed.RunIdentity
    $finalStatus=[string]$parsed.FinalStatus
    $exitCode=[int]$parsed.ExitCode
    return [pscustomobject]@{
        RunIdentity=$runIdentity
        FinalStatus=$finalStatus
        ExitCode=$exitCode
        ConsoleMessage="Certification RunIdentity: $runIdentity -- FinalStatus: $finalStatus -- ExitCode: $exitCode"
    }
}

$script:TpmMarkdownEligibleV1='ELIGIBLE'
$script:TpmMarkdownNotEligibleV1='NOT ELIGIBLE'
$script:TpmMarkdownStatusMapV1=@{Pass='PASS';Fail='FAIL';NotApplicable='N/A'}

function Assert-TPMMarkdownRunIdentityV1 {
    param([string]$Value)
    if($Value-cnotmatch'^[0-9a-f]{32}$'){throw 'REPORT_INVALID: RunIdentity is not exactly 32 lowercase hexadecimal characters'}
}
function Assert-TPMMarkdownSha256V1 {
    param([string]$Value,[string]$Context)
    if($Value-cnotmatch'^[0-9a-f]{64}$'){throw "REPORT_INVALID: $Context is not exactly 64 lowercase hexadecimal characters"}
}
function Assert-TPMMarkdownFailureCodeV1 {
    param([string]$Value,[string[]]$AllowedCodes)
    if($AllowedCodes-cnotcontains$Value){throw "REPORT_INVALID: unrecognized failure code $Value"}
}

function New-TPMScorecardReportV1 {
    param([Parameter(Mandatory=$true)]$Eligibility)
    if($null-eq$Eligibility-or$Eligibility.GetType().FullName-cne'Jumpstile.TPM.Certification.V1.TPMEligibilitySnapshotV1'){throw 'REPORT_INVALID: Eligibility must be an issued TPMEligibilitySnapshotV1'}
    try{$parsed=ConvertFrom-Json -InputObject $Eligibility.CanonicalJson -ErrorAction Stop}catch{throw 'REPORT_INVALID: Eligibility.CanonicalJson did not parse as JSON'}
    foreach($field in @('RunIdentity','FactSetSha256','EvidenceSetSha256','ScoreItems','ApplicableCount','PassedCount','PercentageBasisPoints','EligibleForCertification')){
        if($null-eq$parsed.PSObject.Properties[$field]){throw "REPORT_INVALID: Eligibility is missing $field"}
    }
    Assert-TPMMarkdownRunIdentityV1 ([string]$parsed.RunIdentity)
    Assert-TPMMarkdownSha256V1 ([string]$parsed.FactSetSha256) 'FactSetSha256'
    Assert-TPMMarkdownSha256V1 ([string]$parsed.EvidenceSetSha256) 'EvidenceSetSha256'
    $utf8=New-Object Text.UTF8Encoding($false)
    $eligibilityPayloadHash=Get-TPMSha256HexV1 -Bytes ($utf8.GetBytes($Eligibility.CanonicalJson))
    $manifestIdentifiers=Get-TPMFactIdentifiersV1
    $scoreItems=@($parsed.ScoreItems)
    if($scoreItems.Count-ne$manifestIdentifiers.Count){throw 'REPORT_INVALID: ScoreItems count mismatch'}

    $percentageBasisPoints=[int]$parsed.PercentageBasisPoints
    $quotient=[int][Math]::Floor($percentageBasisPoints/100)
    $remainder=$percentageBasisPoints-($quotient*100)
    $percentageText='{0}.{1:D2}' -f $quotient,$remainder

    $lines=New-Object Collections.Generic.List[string]
    [void]$lines.Add('Schema-Version: 1')
    [void]$lines.Add("Run-Identity: $([string]$parsed.RunIdentity)")
    [void]$lines.Add("Eligibility-Payload-SHA256: $eligibilityPayloadHash")
    [void]$lines.Add("Fact-Set-SHA256: $([string]$parsed.FactSetSha256)")
    [void]$lines.Add("Evidence-Set-SHA256: $([string]$parsed.EvidenceSetSha256)")
    [void]$lines.Add('')
    [void]$lines.Add('# Certification Eligibility Scorecard')
    [void]$lines.Add('Eligibility: '+$(if([bool]$parsed.EligibleForCertification){$script:TpmMarkdownEligibleV1}else{$script:TpmMarkdownNotEligibleV1}))
    [void]$lines.Add("Score: $([int]$parsed.PassedCount)/$([int]$parsed.ApplicableCount) ($percentageText%)")
    for($i=0;$i-lt$scoreItems.Count;$i++){
        $item=$scoreItems[$i]
        foreach($field in @('Identifier','Status','Details','FailureReasons')){if($null-eq$item.PSObject.Properties[$field]){throw "REPORT_INVALID: ScoreItems[$i] is missing $field"}}
        if([string]$item.Identifier-cne$manifestIdentifiers[$i]){throw 'REPORT_INVALID: ScoreItems order'}
        if(-not$script:TpmMarkdownStatusMapV1.ContainsKey([string]$item.Status)){throw 'REPORT_INVALID: unrecognized Status'}
        [void]$lines.Add("## $([string]$item.Identifier)")
        [void]$lines.Add('Status: '+$script:TpmMarkdownStatusMapV1[[string]$item.Status])
        $detailsJson=ConvertTo-TPMJcsV1 $item.Details
        [void]$lines.Add('Details-JCS-Base64Url: '+(ConvertTo-TPMJcsBase64UrlV1 $detailsJson))
        $reasons=@($item.FailureReasons)
        if($reasons.Count-eq0){
            [void]$lines.Add('Failure-Code: none')
        }else{
            foreach($reason in $reasons){
                foreach($field in @('Code','Message')){if($null-eq$reason.PSObject.Properties[$field]){throw 'REPORT_INVALID: FailureReasons entry missing Code/Message'}}
                Assert-TPMMarkdownFailureCodeV1 ([string]$reason.Code) (Get-TPMFactFailureCodesV1)
                [void]$lines.Add("Failure-Code: $([string]$reason.Code)")
                [void]$lines.Add('Failure-Message-Base64Url: '+(ConvertTo-TPMFailureMessageBase64UrlV1 ([string]$reason.Message)))
            }
        }
    }
    $markdown=($lines.ToArray()-join "`n")+"`n"
    $bytes=$utf8.GetBytes($markdown)
    return [pscustomobject]@{
        FileName='TPM-Certification-Scorecard.md'
        Markdown=$markdown
        Bytes=$bytes
        ByteLength=$bytes.Length
    }
}

function New-TPMValidationReportV1 {
    param(
        [Parameter(Mandatory=$true)]$SealedRun,
        [Parameter(Mandatory=$true)]$Eligibility
    )
    if($null-eq$SealedRun-or$SealedRun.GetType().FullName-cne'Jumpstile.TPM.Certification.V1.TPMSealedRunReaderV1'){throw 'REPORT_INVALID: SealedRun must be an issued TPMSealedRunReaderV1'}
    if($null-eq$Eligibility-or$Eligibility.GetType().FullName-cne'Jumpstile.TPM.Certification.V1.TPMEligibilitySnapshotV1'){throw 'REPORT_INVALID: Eligibility must be an issued TPMEligibilitySnapshotV1'}
    if($SealedRun.RunIdentity-cne$Eligibility.RunIdentity){throw 'REPORT_INVALID: SealedRun and Eligibility RunIdentity mismatch'}
    try{$sealedParsed=ConvertFrom-Json -InputObject $SealedRun.CanonicalJson -ErrorAction Stop}catch{throw 'REPORT_INVALID: SealedRun.CanonicalJson did not parse as JSON'}
    foreach($field in @('RunIdentity','Facts','Evidence')){if($null-eq$sealedParsed.PSObject.Properties[$field]){throw "REPORT_INVALID: SealedRun is missing $field"}}
    try{$eligibilityParsed=ConvertFrom-Json -InputObject $Eligibility.CanonicalJson -ErrorAction Stop}catch{throw 'REPORT_INVALID: Eligibility.CanonicalJson did not parse as JSON'}
    foreach($field in @('FactSetSha256','EvidenceSetSha256','FailureReasons')){if($null-eq$eligibilityParsed.PSObject.Properties[$field]){throw "REPORT_INVALID: Eligibility is missing $field"}}
    Assert-TPMMarkdownRunIdentityV1 ([string]$sealedParsed.RunIdentity)
    Assert-TPMMarkdownSha256V1 ([string]$eligibilityParsed.FactSetSha256) 'FactSetSha256'
    Assert-TPMMarkdownSha256V1 ([string]$eligibilityParsed.EvidenceSetSha256) 'EvidenceSetSha256'

    $utf8=New-Object Text.UTF8Encoding($false)
    $eligibilityPayloadHash=Get-TPMSha256HexV1 -Bytes ($utf8.GetBytes($Eligibility.CanonicalJson))
    $factsJson=ConvertTo-TPMJcsV1 $sealedParsed.Facts
    $evidenceJson=ConvertTo-TPMJcsV1 $sealedParsed.Evidence

    $lines=New-Object Collections.Generic.List[string]
    [void]$lines.Add('Schema-Version: 1')
    [void]$lines.Add("Run-Identity: $([string]$sealedParsed.RunIdentity)")
    [void]$lines.Add("Eligibility-Payload-SHA256: $eligibilityPayloadHash")
    [void]$lines.Add("Fact-Set-SHA256: $([string]$eligibilityParsed.FactSetSha256)")
    [void]$lines.Add("Evidence-Set-SHA256: $([string]$eligibilityParsed.EvidenceSetSha256)")
    [void]$lines.Add('')
    [void]$lines.Add('# Certification Validation')
    [void]$lines.Add('## Facts')
    [void]$lines.Add('Facts-JCS-Base64Url: '+(ConvertTo-TPMJcsBase64UrlV1 $factsJson))
    [void]$lines.Add('## Evidence')
    [void]$lines.Add('Evidence-JCS-Base64Url: '+(ConvertTo-TPMJcsBase64UrlV1 $evidenceJson))
    [void]$lines.Add('## Eligibility')
    [void]$lines.Add('Eligibility-Payload-JCS-Base64Url: '+(ConvertTo-TPMJcsBase64UrlV1 $Eligibility.CanonicalJson))
    [void]$lines.Add('## Failure Reasons')
    $reasons=@($eligibilityParsed.FailureReasons)
    if($reasons.Count-eq0){
        [void]$lines.Add('Failure-Code: none')
    }else{
        $allowedFailureCodes=(Get-TPMFactFailureCodesV1)+(Get-TPMEvidenceFailureCodesV1)
        foreach($reason in $reasons){
            foreach($field in @('Code','Message')){if($null-eq$reason.PSObject.Properties[$field]){throw 'REPORT_INVALID: FailureReasons entry missing Code/Message'}}
            Assert-TPMMarkdownFailureCodeV1 ([string]$reason.Code) $allowedFailureCodes
            [void]$lines.Add("Failure-Code: $([string]$reason.Code)")
            [void]$lines.Add('Failure-Message-Base64Url: '+(ConvertTo-TPMFailureMessageBase64UrlV1 ([string]$reason.Message)))
        }
    }
    $markdown=($lines.ToArray()-join "`n")+"`n"
    $bytes=$utf8.GetBytes($markdown)
    return [pscustomobject]@{
        FileName='TPM-Certification-Validation.md'
        Markdown=$markdown
        Bytes=$bytes
        ByteLength=$bytes.Length
    }
}

$script:TpmManifestArtifactsV1 = @(
    [ordered]@{Identifier='EligibilityJson';FileName='TPM-Certification-Eligibility.json';ContentType='application/json'}
    [ordered]@{Identifier='PublicationJson';FileName='TPM-Certification-Publication.json';ContentType='application/json'}
    [ordered]@{Identifier='FinalOutcomeJson';FileName='TPM-Certification-Final-Outcome.json';ContentType='application/json'}
    [ordered]@{Identifier='ScorecardMarkdown';FileName='TPM-Certification-Scorecard.md';ContentType='text/markdown'}
    [ordered]@{Identifier='ValidationMarkdown';FileName='TPM-Certification-Validation.md';ContentType='text/markdown'}
)

function New-TPMManifestReportV1 {
    param(
        [Parameter(Mandatory=$true)]$Eligibility,
        [Parameter(Mandatory=$true)]$EligibilityReport,
        [Parameter(Mandatory=$true)]$PublicationReport,
        [Parameter(Mandatory=$true)]$FinalOutcomeReport,
        [Parameter(Mandatory=$true)]$ScorecardReport,
        [Parameter(Mandatory=$true)]$ValidationReport
    )
    if($null-eq$Eligibility-or$Eligibility.GetType().FullName-cne'Jumpstile.TPM.Certification.V1.TPMEligibilitySnapshotV1'){throw 'REPORT_INVALID: Eligibility must be an issued TPMEligibilitySnapshotV1'}
    try{$parsed=ConvertFrom-Json -InputObject $Eligibility.CanonicalJson -ErrorAction Stop}catch{throw 'REPORT_INVALID: Eligibility.CanonicalJson did not parse as JSON'}
    if($null-eq$parsed.PSObject.Properties['RunIdentity']){throw 'REPORT_INVALID: Eligibility is missing RunIdentity'}
    Assert-TPMMarkdownRunIdentityV1 ([string]$parsed.RunIdentity)

    $utf8=New-Object Text.UTF8Encoding($false)
    $eligibilityPayloadHash=Get-TPMSha256HexV1 -Bytes ($utf8.GetBytes($Eligibility.CanonicalJson))
    $reports=@($EligibilityReport,$PublicationReport,$FinalOutcomeReport,$ScorecardReport,$ValidationReport)
    $expectedArtifacts=@($script:TpmManifestArtifactsV1)
    $artifacts=New-Object Collections.Generic.List[object]
    for($i=0;$i-lt$expectedArtifacts.Count;$i++){
        $report=$reports[$i];$expected=$expectedArtifacts[$i]
        if($null-eq$report-or$report.PSObject.Properties.Name-notcontains'FileName'-or$report.PSObject.Properties.Name-notcontains'Bytes'){throw "REPORT_INVALID: $($expected.Identifier) is not a valid report object"}
        if([string]$report.FileName-cne$expected.FileName){throw "REPORT_INVALID: $($expected.Identifier) FileName mismatch"}
        if($report.Bytes.Length-le0){throw "REPORT_INVALID: $($expected.Identifier) has zero-length content"}
        $artifacts.Add([ordered]@{
            Identifier=$expected.Identifier
            FileName=$expected.FileName
            ContentType=$expected.ContentType
            ByteLength=$report.Bytes.Length
            Sha256=(Get-TPMSha256HexV1 -Bytes $report.Bytes)
            EligibilityPayloadSha256=$eligibilityPayloadHash
        })
    }
    $artifactsArray=$artifacts.ToArray()
    $artifactSetJson=ConvertTo-TPMJcsV1 $artifactsArray
    $artifactSetHash=Get-TPMSha256HexV1 -Bytes ($utf8.GetBytes($artifactSetJson))
    $manifest=[ordered]@{
        SchemaVersion=1
        RunIdentity=[string]$parsed.RunIdentity
        EligibilityPayloadSha256=$eligibilityPayloadHash
        ArtifactCount=5
        ArtifactSetSha256=$artifactSetHash
        Artifacts=$artifactsArray
    }
    $json=ConvertTo-TPMJcsV1 $manifest
    $bytes=$utf8.GetBytes($json)
    return [pscustomobject]@{
        FileName='TPM-Certification-Manifest.json'
        Json=$json
        Bytes=$bytes
        ByteLength=$bytes.Length
    }
}

function New-TPMCommitMarkerReportV1 {
    param([Parameter(Mandatory=$true)]$Manifest)
    if($null-eq$Manifest-or$Manifest.PSObject.Properties.Name-notcontains'Json'-or$Manifest.PSObject.Properties.Name-notcontains'Bytes'-or[string]$Manifest.FileName-cne'TPM-Certification-Manifest.json'){throw 'REPORT_INVALID: Manifest must be a New-TPMManifestReportV1 result'}
    try{$parsed=ConvertFrom-Json -InputObject $Manifest.Json -ErrorAction Stop}catch{throw 'REPORT_INVALID: Manifest.Json did not parse as JSON'}
    foreach($field in @('RunIdentity','EligibilityPayloadSha256','ArtifactCount','ArtifactSetSha256')){if($null-eq$parsed.PSObject.Properties[$field]){throw "REPORT_INVALID: Manifest is missing $field"}}
    Assert-TPMMarkdownRunIdentityV1 ([string]$parsed.RunIdentity)
    Assert-TPMMarkdownSha256V1 ([string]$parsed.EligibilityPayloadSha256) 'EligibilityPayloadSha256'
    Assert-TPMMarkdownSha256V1 ([string]$parsed.ArtifactSetSha256) 'ArtifactSetSha256'
    if([int]$parsed.ArtifactCount-ne5){throw 'REPORT_INVALID: ArtifactCount must be 5'}
    if($Manifest.Bytes.Length-le0){throw 'REPORT_INVALID: Manifest has zero-length content'}

    $utf8=New-Object Text.UTF8Encoding($false)
    $manifestHash=Get-TPMSha256HexV1 -Bytes $Manifest.Bytes
    $marker=[ordered]@{
        SchemaVersion=1
        RunIdentity=[string]$parsed.RunIdentity
        ManifestFileName='TPM-Certification-Manifest.json'
        ManifestByteLength=$Manifest.Bytes.Length
        ManifestSha256=$manifestHash
        ArtifactSetSha256=[string]$parsed.ArtifactSetSha256
        ArtifactCount=5
        EligibilityPayloadSha256=[string]$parsed.EligibilityPayloadSha256
    }
    $json=ConvertTo-TPMJcsV1 $marker
    $bytes=$utf8.GetBytes($json)
    return [pscustomobject]@{
        FileName='TPM-Certification-Commit.json'
        Json=$json
        Bytes=$bytes
        ByteLength=$bytes.Length
    }
}

Export-ModuleMember -Function New-TPMEligibilityReportV1,Get-TPMFinalEvidenceStatusV1,New-TPMPublicationReportV1,New-TPMFinalOutcomeReportV1,New-TPMFinalOutcomeCandidateReportV1,New-TPMFinalOutcomeProjectionV1,New-TPMScorecardReportV1,New-TPMValidationReportV1,New-TPMManifestReportV1,New-TPMCommitMarkerReportV1,Assert-TPMMarkdownRunIdentityV1,Assert-TPMMarkdownSha256V1
