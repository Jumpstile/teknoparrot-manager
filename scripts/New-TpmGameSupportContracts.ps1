[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SupportPosturePath,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

$modulePath = Join-Path $PSScriptRoot 'TPMGameSupport.Contracts.psm1'
Import-Module $modulePath -Force

try {
    if (-not (Test-Path -LiteralPath $SupportPosturePath -PathType Leaf)) { throw "Support posture input was not found: $SupportPosturePath" }
    $model = Get-Content -LiteralPath $SupportPosturePath -Raw | ConvertFrom-Json
    if (-not $model.Profiles) { throw 'Support posture input contains no Profiles.' }
    $source = if ($model.ContractSource) { $model.ContractSource } else { [ordered]@{ Repository = 'TPM-SUPPORT-POSTURE'; Commit = [string]$model.SnapshotId; ProfileRoot = 'GameProfiles' } }
    $expectedCount = $null
    if ($model.ExpectedProfileCount) { $expectedCount = [int]$model.ExpectedProfileCount }
    $registry = New-TPMGameSupportContractRegistryV1 -Profiles @($model.Profiles) -SnapshotId ([string]$model.SnapshotId) -CapturedAtUtc ([string]$model.CapturedAtUtc) -Source $source -ExpectedProfileCount $expectedCount
    $validation = Test-TPMGameSupportContractRegistryV1 -Registry $registry
    if (-not $validation.Valid) { throw "Generated contract registry failed validation: $($validation.Errors -join '; ')" }
    Write-TPMGameSupportContractRegistryV1 -Registry $registry -Path $OutputPath
    [pscustomobject]@{
        RegistryId = $registry.RegistryId
        SnapshotId = $registry.SnapshotId
        ContractCount = $registry.ContractCount
        ClassificationTotals = $registry.ClassificationTotals
        ReleaseGate = $registry.ReleaseGate
        OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
    }
    return
} catch {
    throw
}
