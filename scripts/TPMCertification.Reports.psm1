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

Export-ModuleMember -Function New-TPMEligibilityReportV1
