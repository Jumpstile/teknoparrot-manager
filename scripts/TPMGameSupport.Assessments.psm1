Set-StrictMode -Version 2.0

$script:TpmGameSupportAssessmentSchemaVersionV1 = '1.0.0'
$script:TpmGameSupportAssessmentSchemaVersionV11 = '1.1.0'
$script:TpmGameSupportContractSchemaVersionV12 = '1.2.0'
$script:TpmGameSupportContractSchemaVersionV13 = '1.3.0'
$script:TpmGameSupportAssessmentRequirementStatuses = @('SATISFIED', 'BLOCKED', 'REVIEW', 'NOT_EVALUATED')

function Get-TPMGameSupportAssessmentValue {
    param($Object, [Parameter(Mandatory = $true)][string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) { return $Object[$Name] }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function Assert-TPMGameSupportAssessmentExactFields {
    param($Value, [string]$Context, [string[]]$Expected)
    if ($null -eq $Value) { throw "GAME_SUPPORT_ASSESSMENT_SCHEMA_INVALID: $Context is null" }
    $keys = @(if ($Value -is [System.Collections.IDictionary]) { $Value.Keys } else { $Value.PSObject.Properties.Name })
    $expectedKeys = @($Expected)
    if (@($keys).Count -ne $expectedKeys.Count -or (@($keys | Where-Object { $expectedKeys -notcontains $_ }).Count -gt 0) -or (@($expectedKeys | Where-Object { $keys -notcontains $_ }).Count -gt 0)) { throw "GAME_SUPPORT_ASSESSMENT_SCHEMA_INVALID: $Context fields must be exactly $($expectedKeys -join ', ')" }
    return $Value
}

function Assert-TPMGameSupportAssessmentString {
    param($Value, [string]$Context, [switch]$AllowEmpty)
    if ($Value -isnot [string] -or (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($Value))) { throw "GAME_SUPPORT_ASSESSMENT_SCHEMA_INVALID: $Context must be a non-empty string" }
}

function Assert-TPMGameSupportAssessmentArray {
    param($Value, [string]$Context)
    if ($Value -is [string] -or $Value -isnot [System.Collections.IEnumerable]) { throw "GAME_SUPPORT_ASSESSMENT_SCHEMA_INVALID: $Context must be an array" }
}

function Assert-TPMGameSupportAssessmentEnum {
    param($Value, [string[]]$Allowed, [string]$Context)
    Assert-TPMGameSupportAssessmentString $Value $Context
    if ($Allowed -notcontains $Value) { throw "GAME_SUPPORT_ASSESSMENT_SCHEMA_INVALID: $Context must be one of $($Allowed -join ', ')" }
}

function New-TPMGameSupportAssessmentSupportItem {
    param($Requirement)
    $hashState = if ($null -eq (Get-TPMGameSupportAssessmentValue $Requirement 'Hash' $null)) { 'NOT_DECLARED' } else { 'NOT_EVALUATED' }
    return [ordered]@{
        RequirementId = [string](Get-TPMGameSupportAssessmentValue $Requirement 'RequirementId' '')
        RequirementStatus = 'NOT_EVALUATED'
        PresenceState = 'NOT_EVALUATED'
        PathState = 'NOT_EVALUATED'
        HashState = $hashState
        ObservedRelativePath = $null
        ObservedSha256 = $null
        ObservedSource = $null
        EvidenceRefs = @()
    }
}

function New-TPMGameSupportAssessmentV1 {
    param([Parameter(Mandatory = $true)]$Contract, [Parameter(Mandatory = $true)][string]$EvaluatedAtUtc, [string]$AssessmentId = '', [string]$EvaluatorName = 'TPM', [string]$EvaluatorVersion = '1.0.0', [string]$TargetIdentity = '')
    if ([string](Get-TPMGameSupportAssessmentValue $Contract 'SchemaVersion' '') -ne $script:TpmGameSupportContractSchemaVersionV12) { throw 'GAME_SUPPORT_ASSESSMENT_BINDING_INVALID: assessment requires a 1.2.0 static contract.' }
    $contractId = [string](Get-TPMGameSupportAssessmentValue $Contract 'ContractId' '')
    $profileCode = [string](Get-TPMGameSupportAssessmentValue $Contract 'ProfileCode' '')
    if ([string]::IsNullOrWhiteSpace($AssessmentId)) { $AssessmentId = 'assessment-' + ($contractId -replace '^game-', '') }
    $support = Get-TPMGameSupportAssessmentValue (Get-TPMGameSupportAssessmentValue $Contract 'Prerequisites' ([ordered]@{})) 'SupportFiles' ([ordered]@{ Items = @() })
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($requirement in @(Get-TPMGameSupportAssessmentValue $support 'Items' @())) { [void]$items.Add((New-TPMGameSupportAssessmentSupportItem -Requirement $requirement)) }
    return [ordered]@{
        AssessmentId = $AssessmentId
        SchemaVersion = $script:TpmGameSupportAssessmentSchemaVersionV1
        ContractId = $contractId
        ContractSchemaVersion = $script:TpmGameSupportContractSchemaVersionV12
        ContractSnapshotId = [string](Get-TPMGameSupportAssessmentValue $Contract 'SnapshotId' '')
        EvaluatedAtUtc = $EvaluatedAtUtc
        Evaluator = [ordered]@{ Name = $EvaluatorName; Version = $EvaluatorVersion }
        Target = [ordered]@{ ProfileCode = $profileCode; TargetIdentity = $TargetIdentity }
        SupportFiles = [ordered]@{ Overall = if ($items.Count -eq 0) { 'SATISFIED' } else { 'NOT_EVALUATED' }; Items = $items.ToArray() }
        Privilege = [ordered]@{ Status = 'NOT_EVALUATED'; ObservedElevation = 'UNKNOWN'; UserOverrideUsed = $false; EvidenceRefs = @() }
        Launch = [ordered]@{ Readiness = 'NOT_EVALUATED'; Observation = 'NOT_TESTED'; EvidenceRefs = @() }
        Controls = [ordered]@{ Readiness = 'NOT_EVALUATED'; Observation = 'NOT_EVALUATED'; SelectedInputApi = $null; ObservedDevice = $null; ObservedBackend = $null; ControlResults = @(); EvidenceRefs = @() }
        Evidence = [ordered]@{ Entries = @() }
    }
}

function Get-TPMGameSupportAssessmentRequirement {
    param($Contract, [string]$RequirementId)
    $support = Get-TPMGameSupportAssessmentValue (Get-TPMGameSupportAssessmentValue $Contract 'Prerequisites' ([ordered]@{})) 'SupportFiles' ([ordered]@{ Items = @() })
    return @((Get-TPMGameSupportAssessmentValue $support 'Items' @()) | Where-Object { [string](Get-TPMGameSupportAssessmentValue $_ 'RequirementId' '') -ceq $RequirementId })[0]
}

function Get-TPMGameSupportAssessmentItemStatus {
    param($Item, $Requirement)
    $presence = [string](Get-TPMGameSupportAssessmentValue $Item 'PresenceState' '')
    $path = [string](Get-TPMGameSupportAssessmentValue $Item 'PathState' '')
    $hash = [string](Get-TPMGameSupportAssessmentValue $Item 'HashState' '')
    $state = [string](Get-TPMGameSupportAssessmentValue $Requirement 'RequirementState' 'REQUIRED')
    $statusForFailure = if ($state -eq 'REQUIRED') { 'BLOCKED' } else { 'REVIEW' }
    if ($presence -eq 'MISSING' -or $path -eq 'MISMATCHED' -or $hash -eq 'MISMATCHED') { return $statusForFailure }
    if ($presence -eq 'NOT_EVALUATED' -or $path -eq 'NOT_EVALUATED' -or ($hash -eq 'NOT_EVALUATED' -and $null -ne (Get-TPMGameSupportAssessmentValue $Requirement 'Hash' $null))) { return 'NOT_EVALUATED' }
    if ($path -eq 'NOT_DECLARED' -and $presence -eq 'PRESENT') {
        if ($state -eq 'REQUIRED') { return 'REVIEW' }
        return 'SATISFIED'
    }
    if ($presence -eq 'PRESENT' -and $path -in @('MATCHED','NOT_DECLARED') -and $hash -in @('VERIFIED','NOT_DECLARED')) { return 'SATISFIED' }
    return 'NOT_EVALUATED'
}

function Get-TPMGameSupportAssessmentOverallStatus {
    param($Assessment, $Contract)
    $items = @((Get-TPMGameSupportAssessmentValue (Get-TPMGameSupportAssessmentValue $Assessment 'SupportFiles' ([ordered]@{})) 'Items' @()))
    if ($items.Count -eq 0) { return 'SATISFIED' }
    $statuses = New-Object System.Collections.Generic.List[string]
    foreach ($item in $items) { $requirement = Get-TPMGameSupportAssessmentRequirement -Contract $Contract -RequirementId ([string](Get-TPMGameSupportAssessmentValue $item 'RequirementId' '')); if ($null -eq $requirement) { return 'BLOCKED' }; [void]$statuses.Add((Get-TPMGameSupportAssessmentItemStatus -Item $item -Requirement $requirement)) }
    if ($statuses -contains 'BLOCKED') { return 'BLOCKED' }
    if ($statuses -contains 'NOT_EVALUATED') { return 'NOT_EVALUATED' }
    if ($statuses -contains 'REVIEW') { return 'REVIEW' }
    return 'READY'
}

function Assert-TPMGameSupportAssessmentV1 {
    param([Parameter(Mandatory = $true)]$Assessment, [Parameter(Mandatory = $true)]$Contract)
    $expected = @('AssessmentId','SchemaVersion','ContractId','ContractSchemaVersion','ContractSnapshotId','EvaluatedAtUtc','Evaluator','Target','SupportFiles','Privilege','Launch','Controls','Evidence')
    $d = Assert-TPMGameSupportAssessmentExactFields $Assessment 'GameSupportAssessmentV1' $expected
    Assert-TPMGameSupportAssessmentString $d.AssessmentId 'AssessmentId'; if ($d.SchemaVersion -cne $script:TpmGameSupportAssessmentSchemaVersionV1) { throw "GAME_SUPPORT_ASSESSMENT_SCHEMA_INVALID: unsupported SchemaVersion '$($d.SchemaVersion)'" }; if ($d.ContractSchemaVersion -cne $script:TpmGameSupportContractSchemaVersionV12) { throw "GAME_SUPPORT_ASSESSMENT_BINDING_INVALID: ContractSchemaVersion must be $($script:TpmGameSupportContractSchemaVersionV12)" }; Assert-TPMGameSupportAssessmentString $d.ContractId 'ContractId'; Assert-TPMGameSupportAssessmentString $d.ContractSnapshotId 'ContractSnapshotId'; Assert-TPMGameSupportAssessmentString ([string]$d.EvaluatedAtUtc) 'EvaluatedAtUtc'
    if ([string](Get-TPMGameSupportAssessmentValue $Contract 'SchemaVersion' '') -ne $script:TpmGameSupportContractSchemaVersionV12) { throw 'GAME_SUPPORT_ASSESSMENT_BINDING_INVALID: supplied contract is not 1.2.0.' }
    if ([string]$d.ContractId -cne [string](Get-TPMGameSupportAssessmentValue $Contract 'ContractId' '')) { throw 'GAME_SUPPORT_ASSESSMENT_BINDING_INVALID: ContractId mismatch.' }
    if ([string]$d.ContractSnapshotId -cne [string](Get-TPMGameSupportAssessmentValue $Contract 'SnapshotId' '')) { throw 'GAME_SUPPORT_ASSESSMENT_BINDING_INVALID: ContractSnapshotId mismatch.' }
    $target = Assert-TPMGameSupportAssessmentExactFields $d.Target 'Target' @('ProfileCode','TargetIdentity'); Assert-TPMGameSupportAssessmentString $target.ProfileCode 'Target.ProfileCode'; Assert-TPMGameSupportAssessmentString $target.TargetIdentity 'Target.TargetIdentity' -AllowEmpty
    $support = Assert-TPMGameSupportAssessmentExactFields $d.SupportFiles 'SupportFiles' @('Overall','Items'); Assert-TPMGameSupportAssessmentEnum $support.Overall @('SATISFIED','READY','BLOCKED','REVIEW','NOT_EVALUATED') 'SupportFiles.Overall'; Assert-TPMGameSupportAssessmentArray $support.Items 'SupportFiles.Items'
    foreach ($item in @($support.Items)) { $i = Assert-TPMGameSupportAssessmentExactFields $item 'SupportFiles.Item' @('RequirementId','RequirementStatus','PresenceState','PathState','HashState','ObservedRelativePath','ObservedSha256','ObservedSource','EvidenceRefs'); Assert-TPMGameSupportAssessmentString $i.RequirementId 'SupportFiles.Item.RequirementId'; Assert-TPMGameSupportAssessmentEnum $i.RequirementStatus $script:TpmGameSupportAssessmentRequirementStatuses 'SupportFiles.Item.RequirementStatus'; Assert-TPMGameSupportAssessmentEnum $i.PresenceState @('PRESENT','MISSING','NOT_EVALUATED') 'SupportFiles.Item.PresenceState'; Assert-TPMGameSupportAssessmentEnum $i.PathState @('MATCHED','MISMATCHED','NOT_DECLARED','NOT_EVALUATED') 'SupportFiles.Item.PathState'; Assert-TPMGameSupportAssessmentEnum $i.HashState @('VERIFIED','MISMATCHED','NOT_DECLARED','NOT_EVALUATED') 'SupportFiles.Item.HashState'; Assert-TPMGameSupportAssessmentArray $i.EvidenceRefs 'SupportFiles.Item.EvidenceRefs'; $requirement = Get-TPMGameSupportAssessmentRequirement -Contract $Contract -RequirementId $i.RequirementId; if ($null -eq $requirement) { throw "GAME_SUPPORT_ASSESSMENT_BINDING_INVALID: unknown requirement '$($i.RequirementId)'" }; $expectedStatus = Get-TPMGameSupportAssessmentItemStatus -Item $i -Requirement $requirement; if ([string]$i.RequirementStatus -cne $expectedStatus) { throw "GAME_SUPPORT_ASSESSMENT_SCHEMA_INVALID: $($i.RequirementId) RequirementStatus does not match orthogonal states" } }
    $computedOverall = Get-TPMGameSupportAssessmentOverallStatus -Assessment $Assessment -Contract $Contract; if ([string]$support.Overall -cne $computedOverall) { throw "GAME_SUPPORT_ASSESSMENT_SCHEMA_INVALID: SupportFiles.Overall must be $computedOverall" }
    $privilege = Assert-TPMGameSupportAssessmentExactFields $d.Privilege 'Privilege' @('Status','ObservedElevation','UserOverrideUsed','EvidenceRefs'); Assert-TPMGameSupportAssessmentEnum $privilege.Status @('SATISFIED','NOT_SATISFIED','NOT_APPLICABLE','NOT_EVALUATED') 'Privilege.Status'; Assert-TPMGameSupportAssessmentEnum $privilege.ObservedElevation @('ELEVATED','NOT_ELEVATED','UNKNOWN') 'Privilege.ObservedElevation'; if ($privilege.UserOverrideUsed -isnot [bool]) { throw 'GAME_SUPPORT_ASSESSMENT_SCHEMA_INVALID: Privilege.UserOverrideUsed must be boolean' }; Assert-TPMGameSupportAssessmentArray $privilege.EvidenceRefs 'Privilege.EvidenceRefs'
    $launch = Assert-TPMGameSupportAssessmentExactFields $d.Launch 'Launch' @('Readiness','Observation','EvidenceRefs'); Assert-TPMGameSupportAssessmentEnum $launch.Readiness @('READY','BLOCKED','REVIEW','NOT_EVALUATED') 'Launch.Readiness'; Assert-TPMGameSupportAssessmentEnum $launch.Observation @('NOT_TESTED','SUCCESS_OBSERVED','FAILURE_OBSERVED') 'Launch.Observation'; Assert-TPMGameSupportAssessmentArray $launch.EvidenceRefs 'Launch.EvidenceRefs'
    $controls = Assert-TPMGameSupportAssessmentExactFields $d.Controls 'Controls' @('Readiness','Observation','SelectedInputApi','ObservedDevice','ObservedBackend','ControlResults','EvidenceRefs'); Assert-TPMGameSupportAssessmentEnum $controls.Readiness @('VERIFIED','NOT_VERIFIED','BLOCKED','NOT_EVALUATED') 'Controls.Readiness'; Assert-TPMGameSupportAssessmentEnum $controls.Observation @('NOT_TESTED','INPUT_DELIVERED','INPUT_NOT_DELIVERED','NOT_EVALUATED') 'Controls.Observation'; Assert-TPMGameSupportAssessmentArray $controls.ControlResults 'Controls.ControlResults'; Assert-TPMGameSupportAssessmentArray $controls.EvidenceRefs 'Controls.EvidenceRefs'
    $evidence = Assert-TPMGameSupportAssessmentExactFields $d.Evidence 'Evidence' @('Entries'); Assert-TPMGameSupportAssessmentArray $evidence.Entries 'Evidence.Entries'
    return $d
}

function Test-TPMGameSupportAssessmentV1 {
    param([Parameter(Mandatory = $true)]$Assessment, [Parameter(Mandatory = $true)]$Contract)
    try {
        $version = [string]$Assessment.SchemaVersion
        if ($version -eq $script:TpmGameSupportAssessmentSchemaVersionV11) { [void](Assert-TPMGameSupportAssessmentV11 -Assessment $Assessment -Contract $Contract) }
        elseif ($version -eq $script:TpmGameSupportAssessmentSchemaVersionV1) { [void](Assert-TPMGameSupportAssessmentV1 -Assessment $Assessment -Contract $Contract) }
        else { throw "GAME_SUPPORT_ASSESSMENT_SCHEMA_INVALID: unsupported SchemaVersion '$version'" }
        return [pscustomobject]@{ Valid = $true; Errors = @() }
    } catch { return [pscustomobject]@{ Valid = $false; Errors = @($_.Exception.Message) } }
}

function Get-TPMGameSupportAssessmentV1 {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Contract)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "GAME_SUPPORT_ASSESSMENT_MISSING: $Path" }
    $assessment = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($Path))
    $validation = Test-TPMGameSupportAssessmentV1 -Assessment $assessment -Contract $Contract
    if (-not $validation.Valid) { throw "GAME_SUPPORT_ASSESSMENT_INVALID: $($validation.Errors -join '; ')" }
    return $assessment
}

function Write-TPMGameSupportAssessmentV1 {
    param([Parameter(Mandatory = $true)]$Assessment, [Parameter(Mandatory = $true)]$Contract, [Parameter(Mandatory = $true)][string]$Path)
    $validation = Test-TPMGameSupportAssessmentV1 -Assessment $Assessment -Contract $Contract
    if (-not $validation.Valid) { throw "GAME_SUPPORT_ASSESSMENT_INVALID: $($validation.Errors -join '; ')" }
    $parent = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Path)); if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) { [void][System.IO.Directory]::CreateDirectory($parent) }
    [System.IO.File]::WriteAllText($Path, (($Assessment | ConvertTo-Json -Depth 30) + "`n"), (New-Object System.Text.UTF8Encoding($false)))
}

function New-TPMGameSupportAssessmentExternalSoftwareItemV11 {
    param([Parameter(Mandatory = $true)]$Requirement, [string[]]$EvidenceRefs = @())
    $versionConstraint = Get-TPMGameSupportAssessmentValue $Requirement 'VersionConstraint' $null
    $installer = Get-TPMGameSupportAssessmentValue $Requirement 'InstallerIdentity' ([ordered]@{})
    return [ordered]@{
        DependencyId = [string](Get-TPMGameSupportAssessmentValue $Requirement 'DependencyId' '')
        RequirementStatus = 'NOT_EVALUATED'
        InstalledState = 'NOT_EVALUATED'
        VersionState = if ($null -eq $versionConstraint) { 'NOT_DECLARED' } else { 'NOT_EVALUATED' }
        ArchitectureState = 'NOT_EVALUATED'
        SourceState = 'NOT_EVALUATED'
        HashState = if ($null -eq (Get-TPMGameSupportAssessmentValue $installer 'Sha256' $null)) { 'NOT_DECLARED' } else { 'NOT_EVALUATED' }
        ObservedInstallPath = $null
        ObservedVersion = $null
        ObservedArchitecture = $null
        ObservedSource = $null
        ObservedSha256 = $null
        EvidenceRefs = @($EvidenceRefs)
    }
}

function New-TPMGameSupportAssessmentV11 {
    param([Parameter(Mandatory = $true)]$Contract, [Parameter(Mandatory = $true)][string]$EvaluatedAtUtc, [string]$AssessmentId = '', [string]$EvaluatorName = 'TPM', [string]$EvaluatorVersion = '1.1.0', [string]$TargetIdentity = '')
    if ([string](Get-TPMGameSupportAssessmentValue $Contract 'SchemaVersion' '') -ne $script:TpmGameSupportContractSchemaVersionV13) { throw 'GAME_SUPPORT_ASSESSMENT_BINDING_INVALID: assessment requires a 1.3.0 static contract.' }
    $contractId = [string](Get-TPMGameSupportAssessmentValue $Contract 'ContractId' '')
    $profileCode = [string](Get-TPMGameSupportAssessmentValue $Contract 'ProfileCode' '')
    if ([string]::IsNullOrWhiteSpace($AssessmentId)) { $AssessmentId = 'assessment-' + ($contractId -replace '^game-', '') }
    $support = Get-TPMGameSupportAssessmentValue (Get-TPMGameSupportAssessmentValue $Contract 'Prerequisites' ([ordered]@{})) 'SupportFiles' ([ordered]@{ Items = @() })
    $supportItems = New-Object System.Collections.Generic.List[object]
    foreach ($requirement in @(Get-TPMGameSupportAssessmentValue $support 'Items' @())) { [void]$supportItems.Add((New-TPMGameSupportAssessmentSupportItem -Requirement $requirement)) }
    $external = Get-TPMGameSupportAssessmentValue (Get-TPMGameSupportAssessmentValue $Contract 'Prerequisites' ([ordered]@{})) 'ExternalSoftware' ([ordered]@{ DeclarationState = 'NOT_DECLARED'; Items = @() })
    $externalItems = New-Object System.Collections.Generic.List[object]
    foreach ($requirement in @(Get-TPMGameSupportAssessmentValue $external 'Items' @())) {
        $item = New-TPMGameSupportAssessmentExternalSoftwareItemV11 -Requirement $requirement
        $item.RequirementStatus = Get-TPMGameSupportExternalSoftwareItemStatusV11 -Item $item -Requirement $requirement
        [void]$externalItems.Add($item)
    }
    $assessment = [ordered]@{
        AssessmentId = $AssessmentId
        SchemaVersion = $script:TpmGameSupportAssessmentSchemaVersionV11
        ContractId = $contractId
        ContractSchemaVersion = $script:TpmGameSupportContractSchemaVersionV13
        ContractSnapshotId = [string](Get-TPMGameSupportAssessmentValue $Contract 'SnapshotId' '')
        EvaluatedAtUtc = $EvaluatedAtUtc
        Evaluator = [ordered]@{ Name = $EvaluatorName; Version = $EvaluatorVersion }
        Target = [ordered]@{ ProfileCode = $profileCode; TargetIdentity = $TargetIdentity }
        SupportFiles = [ordered]@{ Overall = if ($supportItems.Count -eq 0) { 'SATISFIED' } else { 'NOT_EVALUATED' }; Items = $supportItems.ToArray() }
        ExternalSoftware = [ordered]@{ Overall = Get-TPMGameSupportExternalSoftwareOverallStatusV11 -Items $externalItems.ToArray(); Items = $externalItems.ToArray() }
        Privilege = [ordered]@{ Status = 'NOT_EVALUATED'; ObservedElevation = 'UNKNOWN'; UserOverrideUsed = $false; EvidenceRefs = @() }
        Launch = [ordered]@{ Readiness = 'NOT_EVALUATED'; Observation = 'NOT_TESTED'; EvidenceRefs = @() }
        Controls = [ordered]@{ Readiness = 'NOT_EVALUATED'; Observation = 'NOT_EVALUATED'; SelectedInputApi = $null; ObservedDevice = $null; ObservedBackend = $null; ControlResults = @(); EvidenceRefs = @() }
        Evidence = [ordered]@{ Entries = @() }
    }
    return $assessment
}

function Get-TPMGameSupportExternalSoftwareItemStatusV11 {
    param([Parameter(Mandatory = $true)]$Item, [Parameter(Mandatory = $true)]$Requirement)
    $required = [string](Get-TPMGameSupportAssessmentValue $Requirement 'RequirementState' 'REQUIRED')
    $failure = if ($required -eq 'REQUIRED') { 'BLOCKED' } else { 'REVIEW' }
    foreach ($name in @('InstalledState','VersionState','ArchitectureState','HashState')) {
        if ([string](Get-TPMGameSupportAssessmentValue $Item $name '') -eq 'MISMATCHED' -or ($name -eq 'InstalledState' -and [string](Get-TPMGameSupportAssessmentValue $Item $name '') -eq 'ABSENT')) { return $failure }
    }
    if ([string](Get-TPMGameSupportAssessmentValue $Item 'SourceState' '') -eq 'UNVERIFIED') { return 'REVIEW' }
    if ([string](Get-TPMGameSupportAssessmentValue $Item 'InstalledState' '') -eq 'PRESENT' -and [string](Get-TPMGameSupportAssessmentValue $Item 'VersionState' '') -in @('VERIFIED','NOT_DECLARED') -and [string](Get-TPMGameSupportAssessmentValue $Item 'ArchitectureState' '') -in @('VERIFIED','NOT_APPLICABLE') -and [string](Get-TPMGameSupportAssessmentValue $Item 'HashState' '') -in @('VERIFIED','NOT_DECLARED') -and [string](Get-TPMGameSupportAssessmentValue $Item 'SourceState' '') -in @('VERIFIED','NOT_DECLARED')) { return 'SATISFIED' }
    if (@('UNKNOWN','NOT_EVALUATED') -contains [string](Get-TPMGameSupportAssessmentValue $Item 'InstalledState' '') -or @('UNKNOWN','NOT_EVALUATED') -contains [string](Get-TPMGameSupportAssessmentValue $Item 'VersionState' '') -or @('UNKNOWN','NOT_EVALUATED') -contains [string](Get-TPMGameSupportAssessmentValue $Item 'ArchitectureState' '') -or @('NOT_EVALUATED') -contains [string](Get-TPMGameSupportAssessmentValue $Item 'SourceState' '') -or @('NOT_EVALUATED') -contains [string](Get-TPMGameSupportAssessmentValue $Item 'HashState' '')) { return 'NOT_EVALUATED' }
    return 'REVIEW'
}

function Get-TPMGameSupportExternalSoftwareOverallStatusV11 {
    param([Parameter(Mandatory = $true)][object[]]$Items)
    if (@($Items).Count -eq 0) { return 'NOT_EVALUATED' }
    $statuses = @($Items | ForEach-Object RequirementStatus)
    if ($statuses -contains 'BLOCKED') { return 'BLOCKED' }
    if ($statuses -contains 'REVIEW') { return 'REVIEW' }
    if ($statuses -contains 'NOT_EVALUATED') { return 'NOT_EVALUATED' }
    return 'SATISFIED'
}

function Assert-TPMGameSupportAssessmentExternalSoftwareV11 {
    param([Parameter(Mandatory = $true)]$ExternalSoftware, [Parameter(Mandatory = $true)]$Contract)
    $d = Assert-TPMGameSupportAssessmentExactFields $ExternalSoftware 'ExternalSoftware' @('Overall','Items')
    Assert-TPMGameSupportAssessmentEnum $d.Overall $script:TpmGameSupportAssessmentRequirementStatuses 'ExternalSoftware.Overall'
    Assert-TPMGameSupportAssessmentArray $d.Items 'ExternalSoftware.Items'
    $requirements = @((Get-TPMGameSupportAssessmentValue (Get-TPMGameSupportAssessmentValue $Contract 'Prerequisites' ([ordered]@{})) 'ExternalSoftware' ([ordered]@{ Items = @() })).Items)
    $contractEvidence = Get-TPMGameSupportAssessmentValue (Get-TPMGameSupportAssessmentValue $Contract 'Evidence' ([ordered]@{})) 'Entries' @()
    $knownEvidence = @($contractEvidence | ForEach-Object { [string](Get-TPMGameSupportAssessmentValue $_ 'EvidenceId' '') })
    foreach ($item in @($d.Items)) {
        $i = Assert-TPMGameSupportAssessmentExactFields $item 'ExternalSoftware.Item' @('DependencyId','RequirementStatus','InstalledState','VersionState','ArchitectureState','SourceState','HashState','ObservedInstallPath','ObservedVersion','ObservedArchitecture','ObservedSource','ObservedSha256','EvidenceRefs')
        Assert-TPMGameSupportAssessmentString $i.DependencyId 'ExternalSoftware.Item.DependencyId'
        Assert-TPMGameSupportAssessmentEnum $i.RequirementStatus $script:TpmGameSupportAssessmentRequirementStatuses 'ExternalSoftware.Item.RequirementStatus'
        Assert-TPMGameSupportAssessmentEnum $i.InstalledState @('PRESENT','ABSENT','UNKNOWN','NOT_EVALUATED') 'ExternalSoftware.Item.InstalledState'
        Assert-TPMGameSupportAssessmentEnum $i.VersionState @('VERIFIED','MISMATCHED','UNKNOWN','NOT_DECLARED','NOT_EVALUATED') 'ExternalSoftware.Item.VersionState'
        Assert-TPMGameSupportAssessmentEnum $i.ArchitectureState @('VERIFIED','MISMATCHED','UNKNOWN','NOT_APPLICABLE','NOT_EVALUATED') 'ExternalSoftware.Item.ArchitectureState'
        Assert-TPMGameSupportAssessmentEnum $i.SourceState @('VERIFIED','UNVERIFIED','NOT_DECLARED','NOT_EVALUATED') 'ExternalSoftware.Item.SourceState'
        Assert-TPMGameSupportAssessmentEnum $i.HashState @('VERIFIED','MISMATCHED','NOT_DECLARED','NOT_EVALUATED') 'ExternalSoftware.Item.HashState'
        Assert-TPMGameSupportAssessmentArray $i.EvidenceRefs 'ExternalSoftware.Item.EvidenceRefs'
        foreach ($ref in @($i.EvidenceRefs)) { if ($knownEvidence -notcontains [string]$ref) { throw "GAME_SUPPORT_ASSESSMENT_SCHEMA_INVALID: unresolved external evidence reference '$ref'" } }
        $requirement = @($requirements | Where-Object { [string](Get-TPMGameSupportAssessmentValue $_ 'DependencyId' '') -ceq [string]$i.DependencyId })[0]
        if ($null -eq $requirement) { throw "GAME_SUPPORT_ASSESSMENT_SCHEMA_INVALID: unknown external dependency '$($i.DependencyId)'" }
        $computed = Get-TPMGameSupportExternalSoftwareItemStatusV11 -Item $i -Requirement $requirement
        if ([string]$i.RequirementStatus -cne $computed) { throw "GAME_SUPPORT_ASSESSMENT_SCHEMA_INVALID: ExternalSoftware.Item $($i.DependencyId) RequirementStatus must be $computed" }
    }
    $computedOverall = Get-TPMGameSupportExternalSoftwareOverallStatusV11 -Items @($d.Items)
    if ([string]$d.Overall -cne $computedOverall) { throw "GAME_SUPPORT_ASSESSMENT_SCHEMA_INVALID: ExternalSoftware.Overall must be $computedOverall" }
    return $d
}

function Assert-TPMGameSupportAssessmentV11 {
    param([Parameter(Mandatory = $true)]$Assessment, [Parameter(Mandatory = $true)]$Contract)
    $expected = @('AssessmentId','SchemaVersion','ContractId','ContractSchemaVersion','ContractSnapshotId','EvaluatedAtUtc','Evaluator','Target','SupportFiles','ExternalSoftware','Privilege','Launch','Controls','Evidence')
    $d = Assert-TPMGameSupportAssessmentExactFields $Assessment 'GameSupportAssessmentV1.1' $expected
    if ($d.SchemaVersion -cne $script:TpmGameSupportAssessmentSchemaVersionV11) { throw "GAME_SUPPORT_ASSESSMENT_SCHEMA_INVALID: unsupported SchemaVersion '$($d.SchemaVersion)'" }
    if ($d.ContractSchemaVersion -cne $script:TpmGameSupportContractSchemaVersionV13) { throw "GAME_SUPPORT_ASSESSMENT_BINDING_INVALID: ContractSchemaVersion must be $($script:TpmGameSupportContractSchemaVersionV13)" }
    if ([string](Get-TPMGameSupportAssessmentValue $Contract 'SchemaVersion' '') -cne $script:TpmGameSupportContractSchemaVersionV13) { throw 'GAME_SUPPORT_ASSESSMENT_BINDING_INVALID: supplied contract is not 1.3.0.' }
    $baseAssessment = [ordered]@{}
    $assessmentKeys = @(if ($d -is [System.Collections.IDictionary]) { $d.Keys } else { $d.PSObject.Properties.Name })
    foreach ($key in $assessmentKeys) { if ($key -ne 'ExternalSoftware') { $baseAssessment[$key] = Get-TPMGameSupportAssessmentValue $d $key $null } }
    $baseAssessment.SchemaVersion = $script:TpmGameSupportAssessmentSchemaVersionV1
    $baseAssessment.ContractSchemaVersion = $script:TpmGameSupportContractSchemaVersionV12
    $baseContract = [ordered]@{}
    $contractKeys = @(if ($Contract -is [System.Collections.IDictionary]) { $Contract.Keys } else { $Contract.PSObject.Properties.Name })
    foreach ($key in $contractKeys) { $baseContract[$key] = Get-TPMGameSupportAssessmentValue $Contract $key $null }
    $baseContract.SchemaVersion = $script:TpmGameSupportContractSchemaVersionV12
    $baseContract.Prerequisites = [ordered]@{ SupportFiles = $Contract.Prerequisites.SupportFiles; Administrator = $Contract.Prerequisites.Administrator; Controllers = $Contract.Prerequisites.Controllers }
    [void](Assert-TPMGameSupportAssessmentV1 -Assessment $baseAssessment -Contract $baseContract)
    [void](Assert-TPMGameSupportAssessmentExternalSoftwareV11 -ExternalSoftware $d.ExternalSoftware -Contract $Contract)
    return $d
}

Export-ModuleMember -Function New-TPMGameSupportAssessmentV1,New-TPMGameSupportAssessmentV11,Test-TPMGameSupportAssessmentV1,Get-TPMGameSupportAssessmentV1,Write-TPMGameSupportAssessmentV1,Assert-TPMGameSupportAssessmentV1,Assert-TPMGameSupportAssessmentV11
