[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$AssessmentPath,
    [Parameter(Mandatory = $true)][string]$ContractPath
)

$contractsModule = Join-Path $PSScriptRoot 'TPMGameSupport.Contracts.psm1'
$assessmentsModule = Join-Path $PSScriptRoot 'TPMGameSupport.Assessments.psm1'
Import-Module $contractsModule -Force
Import-Module $assessmentsModule -Force

$contractRegistry = Get-TPMGameSupportContractRegistryV1 -Path $ContractPath
$assessment = Get-Content -LiteralPath $AssessmentPath -Raw | ConvertFrom-Json
$contract = Get-TPMGameSupportContractV1 -Registry $contractRegistry -ProfileCode ([string]$assessment.Target.ProfileCode)
$validation = Test-TPMGameSupportAssessmentV1 -Assessment $assessment -Contract $contract
if (-not $validation.Valid) { throw "Game support assessment validation failed: $($validation.Errors -join '; ')" }
[pscustomobject]@{
    Valid = $true
    AssessmentId = [string]$assessment.AssessmentId
    ContractId = [string]$assessment.ContractId
    ContractSnapshotId = [string]$assessment.ContractSnapshotId
    ProfileCode = [string]$assessment.Target.ProfileCode
}
