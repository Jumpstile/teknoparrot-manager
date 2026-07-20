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
    param([Parameter(Mandatory=$true)]$FinalOutcome)
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
        RequiredPublicationState='Committed'
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
        $allowedFailureCodes=@(Get-TPMFactFailureCodesV1)+@(Get-TPMEvidenceFailureCodesV1)
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

Export-ModuleMember -Function New-TPMEligibilityReportV1,Get-TPMFinalEvidenceStatusV1,New-TPMPublicationReportV1,New-TPMFinalOutcomeReportV1,New-TPMScorecardReportV1,New-TPMValidationReportV1
