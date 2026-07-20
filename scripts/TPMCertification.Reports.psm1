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

Export-ModuleMember -Function New-TPMEligibilityReportV1,Get-TPMFinalEvidenceStatusV1
