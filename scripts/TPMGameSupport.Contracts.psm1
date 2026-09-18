Set-StrictMode -Version 2.0

$script:TpmGameSupportSchemaVersionV11 = '1.1.0'
$script:TpmGameSupportSchemaVersionV12 = '1.2.0'
$script:TpmGameSupportSchemaVersionV13 = '1.3.0'
$script:TpmGameSupportReleasePosturesV1 = @('AUTOMATED_SAFE', 'REVIEW_MANUAL', 'BLOCKED_UNSUPPORTED', 'UNCLASSIFIED')
$script:TpmGameSupportDeclarationValuesV1 = @('NOT_DECLARED', 'DECLARED', 'VERIFIED', 'INCOMPATIBLE')
$script:TpmGameSupportFixDomainNamesV1 = @(
    'RequiredFixes', 'RecommendedFixes', 'OptionalFixes', 'KnownIncompatibleFixes',
    'UserOwnedContentRequirements', 'TeknoParrotUiOwnedSettingRequirements', 'RuntimeValidationRequirements'
)
$script:TpmGameSupportComponentDomainNamesV1 = @(
    'RequiredPatches', 'ShaderFixes', 'BepInExRequirements', 'DgVoodoo2Requirements',
    'ReShadeCompatibility', 'CrosshairCompatibility', 'ForceFeedbackCompatibility',
    'GpuLimitations', 'KnownRuntimeFixes'
)
$script:TpmCxbxrBiosFilesV12 = @(
    [ordered]@{ FileName = 'ic10_g24lc64.bin'; ExpectedRelativePath = 'cxbxr/TeknoParrot/EmuMediaBoard/Chihiro/ic10_g24lc64.bin' },
    [ordered]@{ FileName = 'pc20_g24lc64.bin'; ExpectedRelativePath = 'cxbxr/TeknoParrot/EmuMediaBoard/Chihiro/pc20_g24lc64.bin' },
    [ordered]@{ FileName = 'ic11_24lc024.bin'; ExpectedRelativePath = 'cxbxr/TeknoParrot/EmuMediaBoard/Chihiro/ic11_24lc024.bin' },
    [ordered]@{ FileName = 'fpr21042_m29w160et.bin'; ExpectedRelativePath = 'cxbxr/TeknoParrot/EmuMediaBoard/fpr21042_m29w160et.bin' }
)

function Get-TPMGameSupportValueV1 {
    param($Object, [Parameter(Mandatory = $true)][string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) { return $Object[$Name] }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function ConvertTo-TPMGameSupportOrderedValueV1 {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString('o', [System.Globalization.CultureInfo]::InvariantCulture) }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $result = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) { $result[$property.Name] = ConvertTo-TPMGameSupportOrderedValueV1 $property.Value }
        return $result
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $Value.Keys) { $result[[string]$key] = ConvertTo-TPMGameSupportOrderedValueV1 $Value[$key] }
        return $result
    }
    if (($Value -is [System.Collections.IEnumerable]) -and ($Value -isnot [string])) {
        $list = New-Object System.Collections.Generic.List[object]
        foreach ($item in $Value) { [void]$list.Add((ConvertTo-TPMGameSupportOrderedValueV1 $item)) }
        return ,$list.ToArray()
    }
    return $Value
}

function ConvertFrom-TPMGameSupportOrderedJsonV1 {
    param([Parameter(Mandatory = $true)][string]$Json)
    try { return ConvertTo-TPMGameSupportOrderedValueV1 (ConvertFrom-Json -InputObject $Json -ErrorAction Stop) }
    catch { throw "GAME_SUPPORT_CONTRACT_INVALID_JSON: $_" }
}

function Assert-TPMGameSupportExactFieldsV1 {
    param($Value, [string]$Context, [string[]]$Expected)
    if ($null -eq $Value) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: $Context is null" }
    $keys = @($Value.Keys)
    if ($keys.Count -ne $Expected.Count -or (@($keys | Where-Object { $Expected -notcontains $_ }).Count -gt 0) -or (@($Expected | Where-Object { $keys -notcontains $_ }).Count -gt 0)) {
        throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: $Context fields must be exactly $($Expected -join ', ')"
    }
    return $Value
}

function Assert-TPMGameSupportStringV1 {
    param($Value, [string]$Context, [switch]$AllowEmpty)
    if ($Value -isnot [string] -or (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($Value))) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: $Context must be a non-empty string" }
}

function Assert-TPMGameSupportArrayV1 {
    param($Value, [string]$Context)
    if ($Value -is [string] -or $Value -isnot [System.Collections.IEnumerable]) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: $Context must be an array" }
}

function Assert-TPMGameSupportEnumV1 {
    param($Value, [string[]]$Allowed, [string]$Context)
    Assert-TPMGameSupportStringV1 $Value $Context
    if ($Allowed -notcontains $Value) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: $Context must be one of $($Allowed -join ', ')" }
}

function Get-TPMGameSupportContractIdV1 {
    param([Parameter(Mandatory = $true)][string]$ProfileCode)
    $slug = $ProfileCode.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $slug = $slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) { throw 'GAME_SUPPORT_CONTRACT_INVALID: ProfileCode cannot produce a contract ID.' }
    return 'game-' + $slug
}

function Get-TPMGameSupportAutomationV1 {
    param([string]$Classification)
    switch ($Classification) {
        'AUTOMATED_SAFE' { return 'AUTOMATED' }
        'BLOCKED_UNSUPPORTED' { return 'BLOCKED' }
        default { return 'MANUAL' }
    }
}

function New-TPMGameSupportDomainV1 {
    param([string]$Name, [object]$GameProfile)
    $fixDomains = Get-TPMGameSupportValueV1 $GameProfile 'FixDomains' ([ordered]@{})
    $declared = Get-TPMGameSupportValueV1 $fixDomains $Name $null
    if ($null -eq $declared) {
        return [ordered]@{
            Status = 'NOT_DECLARED'; DeclarationState = 'NOT_DECLARED'; Items = @(); Evidence = @(); EvidenceRefs = @()
            AutomationAllowed = $false; Preconditions = @(); Ownership = 'UNKNOWN'; VerificationRule = ''; Risk = 'Unknown until exact pinned evidence exists.'
        }
    }
    $items = @(Get-TPMGameSupportValueV1 $declared 'Items' @())
    $evidence = @(Get-TPMGameSupportValueV1 $declared 'EvidenceRefs' (Get-TPMGameSupportValueV1 $declared 'Evidence' @()))
    $state = [string](Get-TPMGameSupportValueV1 $declared 'DeclarationState' (Get-TPMGameSupportValueV1 $declared 'Status' 'DECLARED'))
    if ($script:TpmGameSupportDeclarationValuesV1 -notcontains $state) { $state = 'NOT_DECLARED' }
    return [ordered]@{
        Status = $state; DeclarationState = $state; Items = $items; Evidence = $evidence; EvidenceRefs = $evidence
        AutomationAllowed = [bool](Get-TPMGameSupportValueV1 $declared 'AutomationAllowed' $false)
        Preconditions = @(Get-TPMGameSupportValueV1 $declared 'Preconditions' @())
        Ownership = [string](Get-TPMGameSupportValueV1 $declared 'Ownership' 'UNKNOWN')
        VerificationRule = [string](Get-TPMGameSupportValueV1 $declared 'VerificationRule' '')
        Risk = [string](Get-TPMGameSupportValueV1 $declared 'Risk' '')
    }
}

function New-TPMGameSupportComponentDomainV1 {
    param([string]$Name, [object]$GameProfile)
    return New-TPMGameSupportDomainV1 -Name $Name -GameProfile $GameProfile
}

function Get-TPMGameSupportEvidenceGapsV1 {
    param([object]$GameProfile)
    $gaps = New-Object System.Collections.Generic.List[string]
    foreach ($gap in @(Get-TPMGameSupportValueV1 $GameProfile 'EvidenceGaps' @())) {
        if ($gap -and $gaps -notcontains [string]$gap) { [void]$gaps.Add([string]$gap) }
    }
    $setup = Get-TPMGameSupportValueV1 $GameProfile 'SetupEvidence' $null
    $metadata = Get-TPMGameSupportValueV1 $GameProfile 'MetadataEvidence' $null
    if ($null -eq $setup -or -not [bool](Get-TPMGameSupportValueV1 $setup 'Available' $false)) { [void]$gaps.Add('SETUP_EVIDENCE_MISSING') }
    if ($null -eq $metadata -or -not [bool](Get-TPMGameSupportValueV1 $metadata 'Available' $false)) { [void]$gaps.Add('METADATA_EVIDENCE_MISSING') }
    $executable = Get-TPMGameSupportValueV1 $GameProfile 'Executable' ([ordered]@{})
    if (@(Get-TPMGameSupportValueV1 $executable 'PrimaryCandidates' @()).Count -eq 0) { [void]$gaps.Add('EXECUTABLE_DECLARATION_MISSING') }
    $media = Get-TPMGameSupportValueV1 $GameProfile 'Media' ([ordered]@{})
    if ([string](Get-TPMGameSupportValueV1 $media 'ChdRequirement' 'UNKNOWN') -eq 'UNKNOWN') { [void]$gaps.Add('MEDIA_RULE_NOT_DECLARED') }
    return @($gaps | Sort-Object -Unique)
}

function New-TPMGameSupportAutomationPolicyV12 {
    param([bool]$MayDetectPresence = $false, [bool]$MayVerifyPath = $false, [bool]$MayVerifyHash = $false, [bool]$MaySearchSupplementaryContent = $false)
    return [ordered]@{
        MayDetectPresence = $MayDetectPresence
        MayVerifyPath = $MayVerifyPath
        MayVerifyHash = $MayVerifyHash
        MayCopyLocalUserOwnedFile = $false
        MayInstallLocalUserOwnedFile = $false
        MaySearchSupplementaryContent = $MaySearchSupplementaryContent
        MayDownload = $false
        MayRedistribute = $false
        MayUseUnverifiedSource = $false
    }
}

function New-TPMGameSupportAppliesWhenV12 {
    param([string[]]$ProfileCodes = @(), [string[]]$EmulationProfiles = @(), [string[]]$EmulatorTypes = @())
    return [ordered]@{ Match = 'ALL_SPECIFIED'; ProfileCodes = @($ProfileCodes | Sort-Object); EmulationProfiles = @($EmulationProfiles | Sort-Object); EmulatorTypes = @($EmulatorTypes | Sort-Object) }
}

function New-TPMGameSupportEvidenceEntryV12 {
    param([string]$EvidenceId, [string]$Kind, [string]$Path, [string]$Selector, [string]$Claim, [string]$Sha256 = $null, [string]$Repository = '', [string]$Commit = '')
    return [ordered]@{ EvidenceId = $EvidenceId; Kind = $Kind; Repository = $Repository; Commit = $Commit; Path = $Path; Selector = $Selector; Sha256 = $Sha256; Claim = $Claim }
}

function Get-TPMGameSupportControllerTransportV12 {
    param([string]$EmulationProfile, [string]$EmulatorType)
    if ($EmulatorType -ieq 'pcsx2x6' -or $EmulationProfile -ieq 'pcsx2x6') { return 'PCSX2X6_PIPE' }
    if ($EmulationProfile -ieq 'KonamiAcioRacing' -or $EmulatorType -ieq 'TeknoMacaw') { return 'ACIO_PIPE' }
    return 'UNKNOWN'
}

function ConvertTo-TPMGameSupportInputApiV12 {
    param([string]$Value)
    switch -Regex ($Value.Trim()) {
        '^DirectInput$' { return 'DIRECTINPUT' }
        '^XInput$' { return 'XINPUT' }
        '^RawInput$' { return 'RAWINPUT' }
        '^MergedInput$' { return 'MERGED_INPUT' }
        default { return 'UNKNOWN' }
    }
}

function New-TPMGameSupportPrerequisitesV12 {
    param([object]$GameProfile, [string]$Repository, [string]$Commit, [string]$ProfileEvidenceId)
    $profileCode = [string](Get-TPMGameSupportValueV1 $GameProfile 'ProfileCode' '')
    $emulationProfile = [string](Get-TPMGameSupportValueV1 $GameProfile 'EmulationProfile' '')
    $emulatorType = [string](Get-TPMGameSupportValueV1 $GameProfile 'EmulatorType' '')
    $entries = New-Object System.Collections.Generic.List[object]
    $supportItems = New-Object System.Collections.Generic.List[object]
    if ($emulatorType -ieq 'cxbxr') {
        $backendEvidenceId = 'tpui:cxbxr:required-bios'
        foreach ($file in $script:TpmCxbxrBiosFilesV12) {
            [void]$supportItems.Add([ordered]@{
                RequirementId = ('support-cxbxr-' + ([string]$file.FileName -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLowerInvariant())
                RequirementType = 'BIOS'
                RequirementState = 'REQUIRED'
                FileName = [string]$file.FileName
                ExpectedRelativePath = [string]$file.ExpectedRelativePath
                AppliesWhen = New-TPMGameSupportAppliesWhenV12 -EmulatorTypes @('cxbxr')
                SourceKind = 'UNKNOWN'
                EvidenceBasis = 'BACKEND_DERIVED'
                Hash = $null
                Derivation = [ordered]@{
                    Kind = 'BACKEND_DERIVED'; BackendIdentity = 'cxbxr'; RuleId = 'ConfigureCxbxr.RequiredBiosFiles'
                    AppliesWhen = New-TPMGameSupportAppliesWhenV12 -EmulatorTypes @('cxbxr')
                    EvidenceRefs = @($backendEvidenceId); Reason = 'Shared cxbxr launch code checks this file for profiles using EmulatorType cxbxr.'
                }
                EvidenceRefs = @($backendEvidenceId)
                VerificationRule = 'Verify exact relative path and file presence before launch; verify hash only when an authoritative hash is declared.'
                AutomationPolicy = New-TPMGameSupportAutomationPolicyV12 -MayDetectPresence $true -MayVerifyPath $true
            })
        }
        [void]$entries.Add((New-TPMGameSupportEvidenceEntryV12 -EvidenceId $backendEvidenceId -Kind 'BACKEND_RUNTIME_CODE' -Repository $Repository -Commit $Commit -Path 'TeknoParrotUi/Views/GameRunningCode/ProcessManagement/GameProcessManager.cs' -Selector 'ConfigureCxbxr lines 1825-1917' -Claim 'cxbxr checks ic10_g24lc64.bin, pc20_g24lc64.bin, ic11_24lc024.bin, and fpr21042_m29w160et.bin.'))
    }
    $supportDeclaration = if ($supportItems.Count -gt 0) { 'DECLARED' } else { 'NOT_DECLARED' }
    $supportEvidenceRefs = @(if ($supportItems.Count -gt 0) { 'tpui:cxbxr:required-bios' } else { })
    $adminRequired = [bool](Get-TPMGameSupportValueV1 $GameProfile 'RequiresAdmin' $false)
    $adminEvidenceRefs = @()
    $administrator = [ordered]@{
        RequirementState = 'NOT_DECLARED'; AppliesTo = $null; Condition = ''; UserMayContinueWithoutRequirement = $false
        EvidenceRefs = @(); VerificationRule = ''; AutomationPolicy = [ordered]@{ MayDetectPrivilege = $false; MayRequestElevation = $false; MayRelaunchElevated = $false; MayChangePrivilegeConfiguration = $false }
    }
    if ($adminRequired) {
        $adminEvidenceRefs = @($ProfileEvidenceId, 'tpui:library:admin-warning')
        $administrator = [ordered]@{
            RequirementState = 'REQUIRED'; AppliesTo = 'TEKNOPARROT_UI'; Condition = 'TeknoParrotUI launch for this profile.'; UserMayContinueWithoutRequirement = $true
            EvidenceRefs = $adminEvidenceRefs; VerificationRule = 'Verify the current TeknoParrotUI process privilege before launch.'
            AutomationPolicy = [ordered]@{ MayDetectPrivilege = $true; MayRequestElevation = $false; MayRelaunchElevated = $false; MayChangePrivilegeConfiguration = $false }
        }
        [void]$entries.Add((New-TPMGameSupportEvidenceEntryV12 -EvidenceId 'tpui:library:admin-warning' -Kind 'BACKEND_RUNTIME_CODE' -Repository $Repository -Commit $Commit -Path 'TeknoParrotUi/Views/Library.xaml.cs' -Selector 'RequiresAdmin guard lines 718-729' -Claim 'TPUI checks current administrator membership and permits an explicit continue-without-admin choice.'))
    }
    $controllerEvidence = Get-TPMGameSupportValueV1 $GameProfile 'ControllerEvidence' $null
    $mappings = @(Get-TPMGameSupportValueV1 $controllerEvidence 'Controls' @())
    $settings = @(Get-TPMGameSupportValueV1 $controllerEvidence 'Settings' @())
    $inputDefault = ConvertTo-TPMGameSupportInputApiV12 ([string](Get-TPMGameSupportValueV1 $controllerEvidence 'DefaultInputApi' ''))
    $inputAlternates = @((Get-TPMGameSupportValueV1 $controllerEvidence 'AlternativeInputApis' @()) | ForEach-Object { ConvertTo-TPMGameSupportInputApiV12 ([string]$_) } | Sort-Object -Unique)
    $controllerRefs = @(if ($controllerEvidence -and ($mappings.Count -gt 0 -or $inputDefault -ne 'UNKNOWN')) { $ProfileEvidenceId } else { })
    $controllerState = if (@($controllerRefs).Count -gt 0) { 'REQUIRED' } else { 'NOT_DECLARED' }
    $controller = [ordered]@{
        RequirementState = $controllerState
        InputApis = [ordered]@{ DefaultInputApi = $inputDefault; AlternativeInputApis = $inputAlternates; EvidenceRefs = $controllerRefs }
        EmulatorBackend = [ordered]@{ EmulationProfile = $emulationProfile; EmulatorType = $emulatorType; ControlTransport = Get-TPMGameSupportControllerTransportV12 $emulationProfile $emulatorType; EvidenceRefs = $controllerRefs }
        Controls = @($mappings)
        TeknoParrotUiOwnedSettings = @($settings)
        EvidenceRefs = $controllerRefs
        VerificationRule = if ($controllerRefs.Count -gt 0) { 'Verify actual input delivery with the selected input API and backend; mappings alone are not controls verification.' } else { '' }
        AutomationPolicy = [ordered]@{ MayDetectDevice = $false; MayReadInputMappings = ($controllerRefs.Count -gt 0); MayWriteInputMappings = $false; MaySelectInputApi = $false; MayClaimHardwareSupport = $false }
    }
    return [ordered]@{
        SupportFiles = [ordered]@{ DeclarationState = $supportDeclaration; Items = $supportItems.ToArray(); EvidenceRefs = $supportEvidenceRefs; VerificationRule = if ($supportItems.Count -gt 0) { 'Verify every required cxbxr support file before launch without modifying the runtime.' } else { '' }; AutomationPolicy = New-TPMGameSupportAutomationPolicyV12 -MayDetectPresence ($supportItems.Count -gt 0) -MayVerifyPath ($supportItems.Count -gt 0) }
        Administrator = $administrator
        Controllers = $controller
        EvidenceEntries = $entries.ToArray()
    }
}

function New-TPMGameSupportContractV1 {
    param([Parameter(Mandatory = $true)]$Profile, [Parameter(Mandatory = $true)][string]$SnapshotId, [Parameter(Mandatory = $true)][string]$CapturedAtUtc, [string]$Repository = 'teknogods/TeknoParrotUI', [string]$Commit = '5880e019016c5c3a0576e97a6c2a7f14bf54e3d1')
    $profileCode = [string](Get-TPMGameSupportValueV1 $Profile 'ProfileCode' '')
    if ([string]::IsNullOrWhiteSpace($profileCode)) { throw 'GAME_SUPPORT_CONTRACT_INVALID: ProfileCode is required.' }
    $classification = [string](Get-TPMGameSupportValueV1 $Profile 'Classification' 'UNCLASSIFIED')
    if ($script:TpmGameSupportReleasePosturesV1 -notcontains $classification) { $classification = 'UNCLASSIFIED' }
    $executable = Get-TPMGameSupportValueV1 $Profile 'Executable' ([ordered]@{})
    $pathRules = Get-TPMGameSupportValueV1 $Profile 'PathRules' ([ordered]@{})
    $media = Get-TPMGameSupportValueV1 $Profile 'Media' ([ordered]@{})
    $ownership = Get-TPMGameSupportValueV1 $Profile 'Ownership' ([ordered]@{})
    $profileEvidence = Get-TPMGameSupportValueV1 $Profile 'Evidence' ([ordered]@{})
    $sourceIds = @(Get-TPMGameSupportValueV1 $profileEvidence 'SourceIds' @())
    $sourceHash = [string](Get-TPMGameSupportValueV1 $Profile 'ProfileXmlSha256' (Get-TPMGameSupportValueV1 $profileEvidence 'ProfileSha256' ''))
    $allowedLocations = @(); $allowedLocations += @(Get-TPMGameSupportValueV1 $pathRules 'ContentDirectories' @()); $allowedLocations += @(Get-TPMGameSupportValueV1 $pathRules 'MediaDirectories' @())
    $requiredFixes = New-TPMGameSupportDomainV1 -Name 'RequiredFixes' -GameProfile $Profile
    $mediaItems = @(Get-TPMGameSupportValueV1 $media 'RequiredExtensions' @())
    $mediaEvidence = @(Get-TPMGameSupportValueV1 $media 'MediaRuleEvidence' @())
    $mediaDeclared = ($mediaEvidence.Count -gt 0 -or [string](Get-TPMGameSupportValueV1 $media 'ChdRequirement' 'UNKNOWN') -ne 'UNKNOWN')
    if (-not $mediaDeclared) { $mediaItems = @() }
    $mediaState = if ($mediaDeclared) { 'DECLARED' } else { 'NOT_DECLARED' }
    $chdState = if ([string](Get-TPMGameSupportValueV1 $media 'ChdRequirement' 'UNKNOWN') -eq 'UNKNOWN') { 'NOT_DECLARED' } else { 'DECLARED' }
    $prerequisites = New-TPMGameSupportPrerequisitesV12 -GameProfile $Profile -Repository $Repository -Commit $Commit -ProfileEvidenceId ('profile:' + $profileCode + ':source')
    $profileEntry = New-TPMGameSupportEvidenceEntryV12 -EvidenceId ('profile:' + $profileCode + ':source') -Kind 'PROFILE_DECLARED' -Repository $Repository -Commit $Commit -Path ([string](Get-TPMGameSupportValueV1 $Profile 'SourcePath' ($profileCode + '.xml'))) -Selector 'GameProfile root' -Sha256 $sourceHash -Claim 'Pinned GameProfile identity and declarations.'
    $entries = New-Object System.Collections.Generic.List[object]; [void]$entries.Add($profileEntry)
    foreach ($entry in @($prerequisites.EvidenceEntries)) { [void]$entries.Add($entry) }
    $setup = Get-TPMGameSupportValueV1 $Profile 'SetupEvidence' ([ordered]@{ Available = $false; EvidenceGap = 'SETUP_EVIDENCE_MISSING' })
    $metadata = Get-TPMGameSupportValueV1 $Profile 'MetadataEvidence' ([ordered]@{ Available = $false; EvidenceGap = 'METADATA_EVIDENCE_MISSING' })
    if ([bool](Get-TPMGameSupportValueV1 $setup 'Available' $false)) { [void]$entries.Add((New-TPMGameSupportEvidenceEntryV12 -EvidenceId ('setup:' + $profileCode) -Kind 'GAMESETUP_DECLARED' -Repository $Repository -Commit $Commit -Path ([string](Get-TPMGameSupportValueV1 $setup 'RelativePath' 'GameSetup')) -Selector 'GameExecutableLocation' -Sha256 ([string](Get-TPMGameSupportValueV1 $setup 'Sha256' '')) -Claim 'Matched GameSetup evidence.')) }
    if ([bool](Get-TPMGameSupportValueV1 $metadata 'Available' $false)) { [void]$entries.Add((New-TPMGameSupportEvidenceEntryV12 -EvidenceId ('metadata:' + $profileCode) -Kind 'METADATA_DECLARED' -Repository $Repository -Commit $Commit -Path ([string](Get-TPMGameSupportValueV1 $metadata 'RelativePath' 'Metadata')) -Selector 'metadata.game_name' -Sha256 ([string](Get-TPMGameSupportValueV1 $metadata 'Sha256' '')) -Claim 'Matched Metadata evidence.')) }
    $evidenceGaps = @(Get-TPMGameSupportEvidenceGapsV1 -GameProfile $Profile)
    return [ordered]@{
        ContractId = Get-TPMGameSupportContractIdV1 $profileCode
        SchemaVersion = $script:TpmGameSupportSchemaVersionV12
        ProfileCode = $profileCode
        ProfileFileName = [string](Get-TPMGameSupportValueV1 $Profile 'ProfileFileName' ($profileCode + '.xml'))
        DisplayName = [string](Get-TPMGameSupportValueV1 $Profile 'GameTitle' $profileCode)
        VariantTitle = [string](Get-TPMGameSupportValueV1 $Profile 'VariantTitle' '')
        ProfileRevision = Get-TPMGameSupportValueV1 $Profile 'ProfileRevision' $null
        EmulationProfile = [string](Get-TPMGameSupportValueV1 $Profile 'EmulationProfile' '')
        EmulatorType = [string](Get-TPMGameSupportValueV1 $Profile 'EmulatorType' '')
        SnapshotId = $SnapshotId
        CapturedAtUtc = $CapturedAtUtc
        ContractStatus = 'DECLARED'
        StaticEvidenceLevel = if ([string]::IsNullOrWhiteSpace($sourceHash)) { 'SOURCE_INCOMPLETE' } else { 'SOURCE_VERIFIED' }
        ReleasePosture = $classification
        ClassificationReason = [string](Get-TPMGameSupportValueV1 $Profile 'ReasonCode' 'NOT_CLASSIFIED')
        EvidenceGaps = $evidenceGaps
        LaunchExecutables = [ordered]@{
            Primary = @(Get-TPMGameSupportValueV1 $executable 'PrimaryCandidates' @()); Alternate = @(Get-TPMGameSupportValueV1 $executable 'SecondaryCandidates' @())
            HasTwoExecutables = [bool](Get-TPMGameSupportValueV1 $executable 'HasTwoExecutables' $false); LaunchSecondExecutableFirst = [bool](Get-TPMGameSupportValueV1 $executable 'LaunchSecondExecutableFirst' $false)
            SecondExecutableArguments = [string](Get-TPMGameSupportValueV1 $executable 'SecondExecutableArguments' ''); GamePath = [string](Get-TPMGameSupportValueV1 $pathRules 'GamePath' ''); GamePath2 = [string](Get-TPMGameSupportValueV1 $pathRules 'GamePath2' '')
            Rule = if (@(Get-TPMGameSupportValueV1 $executable 'PrimaryCandidates' @()).Count -gt 0) { 'EXACT_PROFILE_EXECUTABLE' } else { 'MISSING_DECLARATION' }; Evidence = @($sourceIds)
        }
        MediaRequirements = [ordered]@{ Status = $mediaState; DeclarationState = $mediaState; Items = $mediaItems; Evidence = $mediaEvidence; EvidenceRefs = $mediaEvidence; AutomationAllowed = $false; Preconditions = @(); Ownership = 'UNKNOWN'; VerificationRule = 'Verify exact media relationship before any automated action.'; Risk = 'Media declarations are incomplete unless pinned evidence names the relationship.' }
        ChdRequirements = [ordered]@{ Status = $chdState; DeclarationState = $chdState; Requirement = [string](Get-TPMGameSupportValueV1 $media 'ChdRequirement' 'UNKNOWN'); AllowedLocations = $allowedLocations; MultipleAllowed = [bool](Get-TPMGameSupportValueV1 $media 'MultipleChdAllowed' $false); Items = @(); Evidence = $mediaEvidence; EvidenceRefs = $mediaEvidence; AutomationAllowed = $false; Preconditions = @(); Ownership = 'UNKNOWN'; VerificationRule = 'Verify exact CHD relationship and location before any automated action.'; Risk = 'CHD presence alone does not identify the launch target.' }
        RequiredFixes = $requiredFixes
        RecommendedFixes = New-TPMGameSupportDomainV1 -Name 'RecommendedFixes' -GameProfile $Profile
        OptionalFixes = New-TPMGameSupportDomainV1 -Name 'OptionalFixes' -GameProfile $Profile
        KnownIncompatibleFixes = New-TPMGameSupportDomainV1 -Name 'KnownIncompatibleFixes' -GameProfile $Profile
        UserOwnedContentRequirements = New-TPMGameSupportDomainV1 -Name 'UserOwnedContentRequirements' -GameProfile $Profile
        TeknoParrotUiOwnedSettingRequirements = New-TPMGameSupportDomainV1 -Name 'TeknoParrotUiOwnedSettingRequirements' -GameProfile $Profile
        RuntimeValidationRequirements = New-TPMGameSupportDomainV1 -Name 'RuntimeValidationRequirements' -GameProfile $Profile
        RequiredPatches = New-TPMGameSupportComponentDomainV1 -Name 'RequiredPatches' -GameProfile $Profile
        ShaderFixes = New-TPMGameSupportComponentDomainV1 -Name 'ShaderFixes' -GameProfile $Profile
        BepInExRequirements = New-TPMGameSupportComponentDomainV1 -Name 'BepInExRequirements' -GameProfile $Profile
        DgVoodoo2Requirements = New-TPMGameSupportComponentDomainV1 -Name 'DgVoodoo2Requirements' -GameProfile $Profile
        ReShadeCompatibility = New-TPMGameSupportComponentDomainV1 -Name 'ReShadeCompatibility' -GameProfile $Profile
        CrosshairCompatibility = New-TPMGameSupportComponentDomainV1 -Name 'CrosshairCompatibility' -GameProfile $Profile
        ForceFeedbackCompatibility = New-TPMGameSupportComponentDomainV1 -Name 'ForceFeedbackCompatibility' -GameProfile $Profile
        GpuLimitations = New-TPMGameSupportComponentDomainV1 -Name 'GpuLimitations' -GameProfile $Profile
        KnownRuntimeFixes = New-TPMGameSupportComponentDomainV1 -Name 'KnownRuntimeFixes' -GameProfile $Profile
        Prerequisites = [ordered]@{ SupportFiles = $prerequisites.SupportFiles; Administrator = $prerequisites.Administrator; Controllers = $prerequisites.Controllers }
        TeknoParrotUiOwnership = [ordered]@{ Fields = @(Get-TPMGameSupportValueV1 $ownership 'TeknoParrotOwnedFields' @()); TpmReadableFields = @(Get-TPMGameSupportValueV1 $ownership 'TpmReadableFields' @()); TpmWritableFields = @(Get-TPMGameSupportValueV1 $ownership 'TpmWritableFields' @()); RequiredUserSelection = [bool](Get-TPMGameSupportValueV1 $ownership 'ManualTeknoParrotUiRequired' $false); RequiredSettings = Get-TPMGameSupportValueV1 $ownership 'RequiredSettings' (New-TPMGameSupportDomainV1 -Name 'TeknoParrotUiOwnedSettingRequirements' -GameProfile $Profile) }
        SetupPolicy = [ordered]@{ Automation = Get-TPMGameSupportAutomationV1 $classification; Classification = $classification; ReleasePosture = $classification; ReasonCode = [string](Get-TPMGameSupportValueV1 $Profile 'ReasonCode' 'NOT_CLASSIFIED'); BeginnerAction = [string](Get-TPMGameSupportValueV1 $Profile 'BeginnerAction' '') }
        Evidence = [ordered]@{ Corpus = [ordered]@{ Repository = $Repository; Commit = $Commit; ProfileRoot = 'TeknoParrotUi.Common/GameProfiles' }; Entries = $entries.ToArray(); SourceIds = $sourceIds; ProfileFileName = [string](Get-TPMGameSupportValueV1 $Profile 'ProfileFileName' ($profileCode + '.xml')); ProfileXmlSha256 = $sourceHash; ProfileSourcePath = [string](Get-TPMGameSupportValueV1 $Profile 'SourcePath' ''); Setup = $setup; Metadata = $metadata; FixtureIds = @(Get-TPMGameSupportValueV1 $Profile 'FixtureIds' @()) }
    }
}

function New-TPMGameSupportEvidenceEntryV13 {
    param([string]$EvidenceId, [string]$Kind, [string]$Path, [string]$Selector, [string]$Claim, [AllowNull()][object]$Sha256 = $null, [string]$Repository = '', [AllowNull()][string]$Commit = $null, [AllowNull()][string]$SourceUrl = $null, [AllowNull()][string]$RecordIdentity = $null, [AllowNull()][string]$ProfileCode = $null, [AllowNull()][string]$RetrievedAtUtc = $null)
    if ($Sha256 -is [string] -and [string]::IsNullOrWhiteSpace($Sha256)) { $Sha256 = $null }
    return [ordered]@{
        EvidenceId = $EvidenceId
        Kind = $Kind
        Repository = $Repository
        Commit = $Commit
        Path = $Path
        Selector = $Selector
        Sha256 = $Sha256
        Claim = $Claim
        SourceUrl = $SourceUrl
        RecordIdentity = $RecordIdentity
        ProfileCode = $ProfileCode
        RetrievedAtUtc = $RetrievedAtUtc
    }
}

function New-TPMGameSupportExternalSoftwareV13 {
    param([Parameter(Mandatory = $true)]$GameProfile, [string]$CapturedAtUtc = '')
    $profileCode = [string](Get-TPMGameSupportValueV1 $GameProfile 'ProfileCode' '')
    if ($profileCode -cne 'Showdown') {
        return [ordered]@{
            DeclarationState = 'NOT_DECLARED'
            Items = @()
            EvidenceRefs = @()
            VerificationRule = 'No pinned external-software requirement is declared for this profile.'
        }
    }
    $profileRef = 'profile:' + $profileCode + ':source'
    $setupRef = 'setup:' + $profileCode
    $itemRefs = @($profileRef)
    $setup = Get-TPMGameSupportValueV1 $GameProfile 'SetupEvidence' $null
    if ($setup -and [bool](Get-TPMGameSupportValueV1 $setup 'Available' $false)) { $itemRefs += $setupRef }
    $itemRefs += @('eggman:Showdown:Rapture3D', 'tester:Showdown:Rapture3D', 'vendor:Rapture3D:2.7.4', 'vendor:Rapture3D:EULA')
    $policy = [ordered]@{
        MayDetectInstalled = $false
        MayVerifyVersion = $false
        MayVerifyArchitecture = $false
        MayVerifyHash = $false
        MayLocateLocalInstaller = $true
        MayRunLocalInstaller = $false
        MayDownload = $false
        MayRedistribute = $false
        MayAcceptEulaAutomatically = $false
        MayUseUnverifiedSource = $false
    }
    $item = [ordered]@{
        DependencyId = 'dependency-rapture3d-game-edition'
        DisplayName = 'Rapture3D Game Edition'
        DependencyType = 'AUDIO_RUNTIME'
        RequirementState = 'REQUIRED'
        AppliesWhen = New-TPMGameSupportAppliesWhenV12 -ProfileCodes @('Showdown') -EmulationProfiles @('GRID') -EmulatorTypes @('TeknoParrot')
        VersionConstraint = $null
        Architecture = 'UNKNOWN'
        DetectionRule = 'No installed-product detection is authorized in this slice.'
        VerificationRule = 'If a future read-only lookup is authorized, inspect only <GameRoot>\Rapture3D audio installer\rapture3dgame_2.7.4_win.exe; do not recurse.'
        EvidenceRefs = @($itemRefs | Select-Object -Unique)
        InstallerIdentity = [ordered]@{
            FileName = 'rapture3dgame_2.7.4_win.exe'
            Vendor = 'Blue Ripple Sound'
            Version = '2.7.4'
            SourceUrl = 'https://www.blueripplesound.com/download/rapture3d_game_edition'
            Sha256 = $null
            LicenseEvidenceRef = 'vendor:Rapture3D:EULA'
        }
        AutomationPolicy = $policy
    }
    return [ordered]@{
        DeclarationState = 'DECLARED'
        Items = @($item)
        EvidenceRefs = @($itemRefs | Select-Object -Unique)
        VerificationRule = 'Verify the declared dependency only through independent read-only evidence; static REQUIRED does not imply installed or verified.'
    }
}

function New-TPMGameSupportContractV13 {
    param([Parameter(Mandatory = $true)]$Profile, [Parameter(Mandatory = $true)][string]$SnapshotId, [Parameter(Mandatory = $true)][string]$CapturedAtUtc, [string]$Repository = 'teknogods/TeknoParrotUI', [string]$Commit = '5880e019016c5c3a0576e97a6c2a7f14bf54e3d1')
    $v12 = New-TPMGameSupportContractV1 -Profile $Profile -SnapshotId $SnapshotId -CapturedAtUtc $CapturedAtUtc -Repository $Repository -Commit $Commit
    $contract = [ordered]@{}
    foreach ($key in $v12.Keys) { $contract[$key] = $v12[$key] }
    $contract.SchemaVersion = $script:TpmGameSupportSchemaVersionV13
    $external = New-TPMGameSupportExternalSoftwareV13 -GameProfile $Profile -CapturedAtUtc $CapturedAtUtc
    $contract.Prerequisites = [ordered]@{
        SupportFiles = $v12.Prerequisites.SupportFiles
        Administrator = $v12.Prerequisites.Administrator
        Controllers = $v12.Prerequisites.Controllers
        ExternalSoftware = $external
    }
    # 1.3 keeps the legacy constructor untouched; its evidence clone uses the
    # stricter null-or-SHA-256 representation required by the 1.3 schema.
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @($v12.Evidence.Entries)) {
        $normalized = [ordered]@{}
        foreach ($key in $entry.Keys) { $normalized[$key] = $entry[$key] }
        if ([string]::IsNullOrWhiteSpace([string]$normalized.Sha256)) { $normalized.Sha256 = $null }
        [void]$entries.Add($normalized)
    }
    if ([string](Get-TPMGameSupportValueV1 $Profile 'ProfileCode' '') -ceq 'Showdown') {
        [void]$entries.Add((New-TPMGameSupportEvidenceEntryV13 -EvidenceId 'eggman:Showdown:Rapture3D' -Kind 'EGGMAN_REFERENCE' -Repository 'https://eggmansworld.github.io/TeknoParrot/' -Commit $null -Path 'Showdown' -Selector 'Rapture3D requirement and game-relative installer location' -Sha256 $null -Claim 'Eggman identifies Rapture3D as required for Showdown and places the installer in the Rapture3D audio installer folder inside the game folder.' -SourceUrl 'https://eggmansworld.github.io/TeknoParrot/' -RecordIdentity 'Showdown' -ProfileCode 'Showdown' -RetrievedAtUtc $CapturedAtUtc))
        [void]$entries.Add((New-TPMGameSupportEvidenceEntryV13 -EvidenceId 'tester:Showdown:Rapture3D' -Kind 'TESTER_REPORT' -Repository 'OWNER_REPORT' -Commit $null -Path 'runtime/Showdown/Rapture3D' -Selector 'intro crash workaround' -Sha256 $null -Claim 'Tester reported that installing Rapture3D Game Edition 2.7.4 resolved the Showdown intro crash.' -RecordIdentity 'Showdown Rapture3D runtime report' -ProfileCode 'Showdown' -RetrievedAtUtc $CapturedAtUtc))
        [void]$entries.Add((New-TPMGameSupportEvidenceEntryV13 -EvidenceId 'vendor:Rapture3D:2.7.4' -Kind 'VENDOR_REFERENCE' -Repository 'https://www.blueripplesound.com/download/rapture3d_game_edition' -Commit $null -Path 'Rapture3D Game Edition' -Selector 'product version, installer identity, and license' -Sha256 $null -Claim 'Blue Ripple Sound identifies Rapture3D Game Edition 2.7.4 and its installer/license terms; this does not prove Showdown dependency causality.' -SourceUrl 'https://www.blueripplesound.com/download/rapture3d_game_edition' -RecordIdentity 'Rapture3D Game Edition 2.7.4' -RetrievedAtUtc $CapturedAtUtc))
        [void]$entries.Add((New-TPMGameSupportEvidenceEntryV13 -EvidenceId 'vendor:Rapture3D:EULA' -Kind 'VENDOR_REFERENCE' -Repository 'https://www.blueripplesound.com/download/rapture3d_game_edition' -Commit $null -Path 'Rapture3D Game Edition EULA' -Selector 'license terms' -Sha256 $null -Claim 'Blue Ripple Sound publishes the Rapture3D Game Edition license terms; no automatic EULA acceptance is authorized.' -SourceUrl 'https://www.blueripplesound.com/download/rapture3d_game_edition' -RecordIdentity 'Rapture3D Game Edition EULA' -RetrievedAtUtc $CapturedAtUtc))
    }
    $evidence = [ordered]@{}
    foreach ($key in $v12.Evidence.Keys) { $evidence[$key] = $v12.Evidence[$key] }
    $evidence.Entries = $entries.ToArray()
    $contract.Evidence = $evidence
    return $contract
}

function Assert-TPMGameSupportDomainV11 {
    param($Value, [string]$Context)
    $d = Assert-TPMGameSupportExactFieldsV1 $Value $Context @('Status', 'DeclarationState', 'Items', 'Evidence', 'EvidenceRefs', 'AutomationAllowed', 'Preconditions', 'Ownership', 'VerificationRule', 'Risk')
    Assert-TPMGameSupportEnumV1 $d.Status $script:TpmGameSupportDeclarationValuesV1 "$Context.Status"; Assert-TPMGameSupportEnumV1 $d.DeclarationState $script:TpmGameSupportDeclarationValuesV1 "$Context.DeclarationState"
    if ($d.Status -cne $d.DeclarationState) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: $Context Status and DeclarationState differ" }
    Assert-TPMGameSupportArrayV1 $d.Items "$Context.Items"; Assert-TPMGameSupportArrayV1 $d.Evidence "$Context.Evidence"; Assert-TPMGameSupportArrayV1 $d.EvidenceRefs "$Context.EvidenceRefs"; Assert-TPMGameSupportArrayV1 $d.Preconditions "$Context.Preconditions"
    if ($d.AutomationAllowed -isnot [bool]) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: $Context.AutomationAllowed must be boolean" }
    if ($d.DeclarationState -eq 'NOT_DECLARED' -and $d.AutomationAllowed) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: $Context NOT_DECLARED cannot enable automation" }
}

function Assert-TPMGameSupportContractV11 {
    param([Parameter(Mandatory = $true)]$Contract)
    $expected = @('ContractId','SchemaVersion','ProfileCode','ProfileFileName','DisplayName','VariantTitle','ProfileRevision','EmulationProfile','EmulatorType','SnapshotId','CapturedAtUtc','ContractStatus','EvidenceConfidence','ReleasePosture','AutomationAllowed','ClassificationReason','EvidenceGaps','LaunchExecutables','MediaRequirements','ChdRequirements','RequiredFixes','RecommendedFixes','OptionalFixes','KnownIncompatibleFixes','UserOwnedContentRequirements','TeknoParrotUiOwnedSettingRequirements','RuntimeValidationRequirements','RequiredPatches','ShaderFixes','BepInExRequirements','DgVoodoo2Requirements','ReShadeCompatibility','CrosshairCompatibility','ForceFeedbackCompatibility','GpuLimitations','KnownRuntimeFixes','TeknoParrotUiOwnership','SetupPolicy','RuntimeValidation','Evidence')
    $d = Assert-TPMGameSupportExactFieldsV1 $Contract 'GameSupportContractV1.1' $expected
    if ($d.SchemaVersion -cne $script:TpmGameSupportSchemaVersionV11) { throw 'GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: unsupported 1.1 contract version' }
    Assert-TPMGameSupportStringV1 $d.ContractId 'ContractId'; Assert-TPMGameSupportStringV1 $d.ProfileCode 'ProfileCode'; Assert-TPMGameSupportStringV1 $d.ProfileFileName 'ProfileFileName'; Assert-TPMGameSupportStringV1 $d.DisplayName 'DisplayName'; Assert-TPMGameSupportStringV1 $d.SnapshotId 'SnapshotId'; Assert-TPMGameSupportStringV1 $d.CapturedAtUtc 'CapturedAtUtc'
    Assert-TPMGameSupportEnumV1 $d.ContractStatus @('DECLARED','VERIFIED','DEPRECATED') 'ContractStatus'; Assert-TPMGameSupportEnumV1 $d.EvidenceConfidence @('SourceVerified','ExperimentVerified','HardwareVerified','ProductionVerified') 'EvidenceConfidence'; Assert-TPMGameSupportEnumV1 $d.ReleasePosture $script:TpmGameSupportReleasePosturesV1 'ReleasePosture'
    foreach ($name in @('MediaRequirements','RequiredFixes','RecommendedFixes','OptionalFixes','KnownIncompatibleFixes','UserOwnedContentRequirements','TeknoParrotUiOwnedSettingRequirements','RuntimeValidationRequirements') + $script:TpmGameSupportComponentDomainNamesV1) { Assert-TPMGameSupportDomainV11 $d[$name] $name }
    return $d
}

function Assert-TPMGameSupportPolicyV12 {
    param($Value, [string]$Context)
    $p = Assert-TPMGameSupportExactFieldsV1 $Value $Context @('MayDetectPresence','MayVerifyPath','MayVerifyHash','MayCopyLocalUserOwnedFile','MayInstallLocalUserOwnedFile','MaySearchSupplementaryContent','MayDownload','MayRedistribute','MayUseUnverifiedSource')
    foreach ($name in @($p.Keys)) { if ($p[$name] -isnot [bool]) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: $Context.$name must be boolean" } }
    if ($p.MayInstallLocalUserOwnedFile -and -not $p.MayCopyLocalUserOwnedFile) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: $Context install requires copy permission" }
}
function Assert-TPMGameSupportControllerPolicyV12 {
    param($Value, [string]$Context)
    $p = Assert-TPMGameSupportExactFieldsV1 $Value $Context @('MayDetectDevice','MayReadInputMappings','MayWriteInputMappings','MaySelectInputApi','MayClaimHardwareSupport')
    foreach ($name in @($p.Keys)) { if ($p[$name] -isnot [bool]) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: $Context.$name must be boolean" } }
}
function Assert-TPMGameSupportAdministratorPolicyV12 {
    param($Value, [string]$Context)
    $p = Assert-TPMGameSupportExactFieldsV1 $Value $Context @('MayDetectPrivilege','MayRequestElevation','MayRelaunchElevated','MayChangePrivilegeConfiguration')
    foreach ($name in @($p.Keys)) { if ($p[$name] -isnot [bool]) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: $Context.$name must be boolean" } }
}



function Assert-TPMGameSupportContractV12 {
    param([Parameter(Mandatory = $true)]$Contract)
    $expected = @('ContractId','SchemaVersion','ProfileCode','ProfileFileName','DisplayName','VariantTitle','ProfileRevision','EmulationProfile','EmulatorType','SnapshotId','CapturedAtUtc','ContractStatus','StaticEvidenceLevel','ReleasePosture','ClassificationReason','EvidenceGaps','LaunchExecutables','MediaRequirements','ChdRequirements','RequiredFixes','RecommendedFixes','OptionalFixes','KnownIncompatibleFixes','UserOwnedContentRequirements','TeknoParrotUiOwnedSettingRequirements','RuntimeValidationRequirements','RequiredPatches','ShaderFixes','BepInExRequirements','DgVoodoo2Requirements','ReShadeCompatibility','CrosshairCompatibility','ForceFeedbackCompatibility','GpuLimitations','KnownRuntimeFixes','Prerequisites','TeknoParrotUiOwnership','SetupPolicy','Evidence')
    $d = Assert-TPMGameSupportExactFieldsV1 $Contract 'GameSupportContractV1.2' $expected
    if ($d.SchemaVersion -cne $script:TpmGameSupportSchemaVersionV12) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: SchemaVersion must be $($script:TpmGameSupportSchemaVersionV12)" }
    Assert-TPMGameSupportStringV1 $d.ContractId 'ContractId'; Assert-TPMGameSupportStringV1 $d.ProfileCode 'ProfileCode'; Assert-TPMGameSupportStringV1 $d.ProfileFileName 'ProfileFileName'; Assert-TPMGameSupportStringV1 $d.DisplayName 'DisplayName'; Assert-TPMGameSupportStringV1 $d.SnapshotId 'SnapshotId'; Assert-TPMGameSupportStringV1 $d.CapturedAtUtc 'CapturedAtUtc'
    Assert-TPMGameSupportEnumV1 $d.ContractStatus @('DECLARED','DEPRECATED') 'ContractStatus'; Assert-TPMGameSupportEnumV1 $d.StaticEvidenceLevel @('SOURCE_VERIFIED','SOURCE_INCOMPLETE') 'StaticEvidenceLevel'; Assert-TPMGameSupportEnumV1 $d.ReleasePosture $script:TpmGameSupportReleasePosturesV1 'ReleasePosture'
    if ($d.ReleasePosture -eq 'UNCLASSIFIED') { throw 'GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: UNCLASSIFIED is not valid for a final registry.' }
    foreach ($name in @('MediaRequirements','RequiredFixes','RecommendedFixes','OptionalFixes','KnownIncompatibleFixes','UserOwnedContentRequirements','TeknoParrotUiOwnedSettingRequirements','RuntimeValidationRequirements') + $script:TpmGameSupportComponentDomainNamesV1) { Assert-TPMGameSupportDomainV11 $d[$name] $name }
    $prereq = Assert-TPMGameSupportExactFieldsV1 $d.Prerequisites 'Prerequisites' @('SupportFiles','Administrator','Controllers')
    $support = Assert-TPMGameSupportExactFieldsV1 $prereq.SupportFiles 'Prerequisites.SupportFiles' @('DeclarationState','Items','EvidenceRefs','VerificationRule','AutomationPolicy')
    Assert-TPMGameSupportEnumV1 $support.DeclarationState @('DECLARED','NOT_DECLARED') 'Prerequisites.SupportFiles.DeclarationState'; Assert-TPMGameSupportArrayV1 $support.Items 'Prerequisites.SupportFiles.Items'; Assert-TPMGameSupportArrayV1 $support.EvidenceRefs 'Prerequisites.SupportFiles.EvidenceRefs'; Assert-TPMGameSupportStringV1 $support.VerificationRule 'Prerequisites.SupportFiles.VerificationRule' -AllowEmpty; Assert-TPMGameSupportPolicyV12 $support.AutomationPolicy 'Prerequisites.SupportFiles.AutomationPolicy'
    if ($support.DeclarationState -eq 'NOT_DECLARED' -and @($support.Items).Count -gt 0) { throw 'GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: NOT_DECLARED support files cannot contain items' }
    foreach ($item in @($support.Items)) {
        $s = Assert-TPMGameSupportExactFieldsV1 $item 'SupportFileItem' @('RequirementId','RequirementType','RequirementState','FileName','ExpectedRelativePath','AppliesWhen','SourceKind','EvidenceBasis','Hash','Derivation','EvidenceRefs','VerificationRule','AutomationPolicy')
        Assert-TPMGameSupportEnumV1 $s.RequirementType @('BIOS','FIRMWARE','SYSTEM_FILE','SUPPORT_FILE') 'SupportFileItem.RequirementType'; Assert-TPMGameSupportEnumV1 $s.RequirementState @('REQUIRED','OPTIONAL','CONDITIONAL','NOT_DECLARED') 'SupportFileItem.RequirementState'; Assert-TPMGameSupportStringV1 $s.FileName 'SupportFileItem.FileName'; Assert-TPMGameSupportEnumV1 $s.SourceKind @('SUPPLEMENTARY_GAMES','USER_SUPPLIED','TEKNOPARROT_DISTRIBUTION','OTHER_EVIDENCED','UNKNOWN') 'SupportFileItem.SourceKind'; Assert-TPMGameSupportEnumV1 $s.EvidenceBasis @('PROFILE_DECLARED','GAMESETUP_DECLARED','METADATA_DECLARED','BACKEND_DERIVED','RUNTIME_CODE_DERIVED') 'SupportFileItem.EvidenceBasis'; Assert-TPMGameSupportArrayV1 $s.EvidenceRefs 'SupportFileItem.EvidenceRefs'; Assert-TPMGameSupportStringV1 $s.VerificationRule 'SupportFileItem.VerificationRule'; Assert-TPMGameSupportPolicyV12 $s.AutomationPolicy 'SupportFileItem.AutomationPolicy'
        if ($s.RequirementState -ne 'NOT_DECLARED' -and @($s.EvidenceRefs).Count -eq 0) { throw 'GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: declared support item requires evidence' }
        if ($null -ne $s.Hash) { $h = Assert-TPMGameSupportExactFieldsV1 $s.Hash 'SupportFileItem.Hash' @('Algorithm','Value','EvidenceRef'); if ($h.Algorithm -cne 'SHA-256' -or $h.Value -notmatch '^[A-Fa-f0-9]{64}$' -or [string]::IsNullOrWhiteSpace([string]$h.EvidenceRef)) { throw 'GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: authoritative hash is incomplete' } }
        if ($s.AutomationPolicy.MayVerifyHash -and $null -eq $s.Hash) { throw 'GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: hash verification requires authoritative hash' }
    }
    $admin = Assert-TPMGameSupportExactFieldsV1 $prereq.Administrator 'Prerequisites.Administrator' @('RequirementState','AppliesTo','Condition','UserMayContinueWithoutRequirement','EvidenceRefs','VerificationRule','AutomationPolicy')
    Assert-TPMGameSupportEnumV1 $admin.RequirementState @('REQUIRED','CONDITIONAL','NOT_REQUIRED','NOT_DECLARED') 'Administrator.RequirementState'; Assert-TPMGameSupportArrayV1 $admin.EvidenceRefs 'Administrator.EvidenceRefs'; Assert-TPMGameSupportStringV1 $admin.VerificationRule 'Administrator.VerificationRule' -AllowEmpty
    Assert-TPMGameSupportAdministratorPolicyV12 $admin.AutomationPolicy 'Administrator.AutomationPolicy'
    if ($admin.RequirementState -eq 'NOT_REQUIRED' -and @($admin.EvidenceRefs).Count -eq 0) { throw 'GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: NOT_REQUIRED administrator state requires positive evidence' }
    $controller = Assert-TPMGameSupportExactFieldsV1 $prereq.Controllers 'Prerequisites.Controllers' @('RequirementState','InputApis','EmulatorBackend','Controls','TeknoParrotUiOwnedSettings','EvidenceRefs','VerificationRule','AutomationPolicy')
    Assert-TPMGameSupportEnumV1 $controller.RequirementState @('REQUIRED','OPTIONAL','CONDITIONAL','NOT_DECLARED') 'Controllers.RequirementState'; Assert-TPMGameSupportArrayV1 $controller.Controls 'Controllers.Controls'; Assert-TPMGameSupportArrayV1 $controller.TeknoParrotUiOwnedSettings 'Controllers.TeknoParrotUiOwnedSettings'; Assert-TPMGameSupportArrayV1 $controller.EvidenceRefs 'Controllers.EvidenceRefs'; Assert-TPMGameSupportStringV1 $controller.VerificationRule 'Controllers.VerificationRule' -AllowEmpty
    Assert-TPMGameSupportControllerPolicyV12 $controller.AutomationPolicy 'Controllers.AutomationPolicy'
    $evidence = Assert-TPMGameSupportExactFieldsV1 $d.Evidence 'Evidence' @('Corpus','Entries','SourceIds','ProfileFileName','ProfileXmlSha256','ProfileSourcePath','Setup','Metadata','FixtureIds')
    Assert-TPMGameSupportArrayV1 $evidence.Entries 'Evidence.Entries'; Assert-TPMGameSupportStringV1 $evidence.ProfileFileName 'Evidence.ProfileFileName'; Assert-TPMGameSupportStringV1 $evidence.ProfileXmlSha256 'Evidence.ProfileXmlSha256'; Assert-TPMGameSupportArrayV1 $evidence.SourceIds 'Evidence.SourceIds'; Assert-TPMGameSupportArrayV1 $evidence.FixtureIds 'Evidence.FixtureIds'
    $ids = @($evidence.Entries | ForEach-Object EvidenceId)
    foreach ($ref in @($support.EvidenceRefs) + @($admin.EvidenceRefs) + @($controller.EvidenceRefs)) { if ($ids -notcontains [string]$ref) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: unresolved evidence reference '$ref'" } }
    return $d
}

function Assert-TPMGameSupportExternalSoftwarePolicyV13 {
    param($Value, [string]$Context)
    $names = @('MayDetectInstalled','MayVerifyVersion','MayVerifyArchitecture','MayVerifyHash','MayLocateLocalInstaller','MayRunLocalInstaller','MayDownload','MayRedistribute','MayAcceptEulaAutomatically','MayUseUnverifiedSource')
    $p = Assert-TPMGameSupportExactFieldsV1 $Value $Context $names
    foreach ($name in $names) { if ((Get-TPMGameSupportValueV1 $p $name $null) -isnot [bool]) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: $Context.$name must be boolean" } }
}

function Assert-TPMGameSupportEvidenceEntryV13 {
    param($Value, [string]$Context)
    if ($null -eq $Value) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: $Context is null" }
    $allowed = @('EvidenceId','Kind','Repository','Commit','Path','Selector','Sha256','Claim','SourceUrl','RecordIdentity','ProfileCode','RetrievedAtUtc')
    $keys = @(if ($Value -is [System.Collections.IDictionary]) { $Value.Keys } else { $Value.PSObject.Properties.Name })
    if (@($keys | Where-Object { $allowed -notcontains $_ }).Count -gt 0) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: $Context contains unknown fields" }
    foreach ($name in @('EvidenceId','Kind','Path','Selector','Claim')) { Assert-TPMGameSupportStringV1 (Get-TPMGameSupportValueV1 $Value $name '') "$Context.$name" -AllowEmpty:($name -eq 'Selector') }
    Assert-TPMGameSupportStringV1 (Get-TPMGameSupportValueV1 $Value 'Repository' '') "$Context.Repository" -AllowEmpty
    $commit = Get-TPMGameSupportValueV1 $Value 'Commit' $null
    if ($null -ne $commit) { Assert-TPMGameSupportStringV1 ([string]$commit) "$Context.Commit" -AllowEmpty }
    $sha = Get-TPMGameSupportValueV1 $Value 'Sha256' $null
    if ($null -ne $sha -and [string]$sha -notmatch '^[A-Fa-f0-9]{64}$') { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: $Context.Sha256 must be a SHA-256 hash or null" }
    $kind = [string](Get-TPMGameSupportValueV1 $Value 'Kind' '')
    Assert-TPMGameSupportEnumV1 $kind @('PROFILE_DECLARED','GAMESETUP_DECLARED','METADATA_DECLARED','BACKEND_RUNTIME_CODE','OWNER_REPORT','GENERATOR_RULE','CORPUS_MANIFEST','EGGMAN_REFERENCE','VENDOR_REFERENCE','TESTER_REPORT') "$Context.Kind"
    if ($kind -eq 'EGGMAN_REFERENCE') {
        foreach ($name in @('SourceUrl','RecordIdentity','ProfileCode','RetrievedAtUtc')) { Assert-TPMGameSupportStringV1 (Get-TPMGameSupportValueV1 $Value $name $null) "$Context.$name" }
    }
    if ($kind -eq 'VENDOR_REFERENCE') {
        Assert-TPMGameSupportStringV1 (Get-TPMGameSupportValueV1 $Value 'SourceUrl' $null) "$Context.SourceUrl"
        Assert-TPMGameSupportStringV1 (Get-TPMGameSupportValueV1 $Value 'RecordIdentity' $null) "$Context.RecordIdentity"
    }
    if ($kind -eq 'TESTER_REPORT') { Assert-TPMGameSupportStringV1 (Get-TPMGameSupportValueV1 $Value 'RecordIdentity' $null) "$Context.RecordIdentity" }
}

function Assert-TPMGameSupportExternalSoftwareV13 {
    param($Value, [string]$Context, [object[]]$EvidenceEntries)
    $d = Assert-TPMGameSupportExactFieldsV1 $Value $Context @('DeclarationState','Items','EvidenceRefs','VerificationRule')
    Assert-TPMGameSupportEnumV1 $d.DeclarationState @('DECLARED','NOT_DECLARED','INCOMPATIBLE') "$Context.DeclarationState"
    Assert-TPMGameSupportArrayV1 $d.Items "$Context.Items"; Assert-TPMGameSupportArrayV1 $d.EvidenceRefs "$Context.EvidenceRefs"; Assert-TPMGameSupportStringV1 $d.VerificationRule "$Context.VerificationRule" -AllowEmpty
    if ($d.DeclarationState -eq 'NOT_DECLARED' -and (@($d.Items).Count -gt 0 -or @($d.EvidenceRefs).Count -gt 0)) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: $Context NOT_DECLARED cannot contain items or evidence" }
    $knownEvidence = @($EvidenceEntries | ForEach-Object EvidenceId)
    $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($item in @($d.Items)) {
        $i = Assert-TPMGameSupportExactFieldsV1 $item "$Context.Item" @('DependencyId','DisplayName','DependencyType','RequirementState','AppliesWhen','VersionConstraint','Architecture','DetectionRule','VerificationRule','EvidenceRefs','InstallerIdentity','AutomationPolicy')
        Assert-TPMGameSupportStringV1 $i.DependencyId "$Context.Item.DependencyId"; Assert-TPMGameSupportStringV1 $i.DisplayName "$Context.Item.DisplayName"
        Assert-TPMGameSupportEnumV1 $i.DependencyType @('AUDIO_RUNTIME','RUNTIME_COMPONENT') "$Context.Item.DependencyType"; Assert-TPMGameSupportEnumV1 $i.RequirementState @('REQUIRED','CONDITIONAL','OPTIONAL','NOT_DECLARED') "$Context.Item.RequirementState"
        if ($null -ne $i.VersionConstraint) { Assert-TPMGameSupportStringV1 ([string]$i.VersionConstraint) "$Context.Item.VersionConstraint" -AllowEmpty }
        if ($null -ne $i.Architecture -and @('X86','X64','ARM64','ANY','UNKNOWN') -notcontains [string]$i.Architecture) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: $Context.Item.Architecture is invalid" }
        Assert-TPMGameSupportStringV1 $i.DetectionRule "$Context.Item.DetectionRule"; Assert-TPMGameSupportStringV1 $i.VerificationRule "$Context.Item.VerificationRule"; Assert-TPMGameSupportArrayV1 $i.EvidenceRefs "$Context.Item.EvidenceRefs"
        if (@($i.EvidenceRefs).Count -eq 0) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: $Context.Item requires evidence references" }
        if (-not $ids.Add([string]$i.DependencyId)) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: duplicate $Context.Item.DependencyId '$($i.DependencyId)'" }
        foreach ($ref in @($i.EvidenceRefs)) { if ($knownEvidence -notcontains [string]$ref) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: unresolved external software evidence reference '$ref'" } }
        $installer = Assert-TPMGameSupportExactFieldsV1 $i.InstallerIdentity "$Context.Item.InstallerIdentity" @('FileName','Vendor','Version','SourceUrl','Sha256','LicenseEvidenceRef')
        foreach ($name in @('FileName','Vendor','Version','SourceUrl','LicenseEvidenceRef')) { if ($null -ne $installer[$name]) { Assert-TPMGameSupportStringV1 ([string]$installer[$name]) "$Context.Item.InstallerIdentity.$name" -AllowEmpty } }
        $licenseRef = Get-TPMGameSupportValueV1 $installer 'LicenseEvidenceRef' $null
        if ($null -ne $licenseRef -and $knownEvidence -notcontains [string]$licenseRef) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: unresolved external license evidence reference '$licenseRef'" }
        if ($null -ne $installer.Sha256 -and [string]$installer.Sha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: $Context.Item.InstallerIdentity.Sha256 must be a SHA-256 hash or null" }
        Assert-TPMGameSupportExternalSoftwarePolicyV13 $i.AutomationPolicy "$Context.Item.AutomationPolicy"
        if ($i.AutomationPolicy.MayVerifyHash -and $null -eq $installer.Sha256) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: $Context.Item hash verification requires an authoritative hash" }
    }
    foreach ($ref in @($d.EvidenceRefs)) { if ($knownEvidence -notcontains [string]$ref) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: unresolved external software domain evidence reference '$ref'" } }
    return $d
}

function Assert-TPMGameSupportContractV13 {
    param([Parameter(Mandatory = $true)]$Contract)
    $expected = @('ContractId','SchemaVersion','ProfileCode','ProfileFileName','DisplayName','VariantTitle','ProfileRevision','EmulationProfile','EmulatorType','SnapshotId','CapturedAtUtc','ContractStatus','StaticEvidenceLevel','ReleasePosture','ClassificationReason','EvidenceGaps','LaunchExecutables','MediaRequirements','ChdRequirements','RequiredFixes','RecommendedFixes','OptionalFixes','KnownIncompatibleFixes','UserOwnedContentRequirements','TeknoParrotUiOwnedSettingRequirements','RuntimeValidationRequirements','RequiredPatches','ShaderFixes','BepInExRequirements','DgVoodoo2Requirements','ReShadeCompatibility','CrosshairCompatibility','ForceFeedbackCompatibility','GpuLimitations','KnownRuntimeFixes','Prerequisites','TeknoParrotUiOwnership','SetupPolicy','Evidence')
    $d = Assert-TPMGameSupportExactFieldsV1 $Contract 'GameSupportContractV1.3' $expected
    if ($d.SchemaVersion -cne $script:TpmGameSupportSchemaVersionV13) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: SchemaVersion must be $($script:TpmGameSupportSchemaVersionV13)" }
    $base = [ordered]@{}
    foreach ($key in $d.Keys) { $base[$key] = $d[$key] }
    $base.SchemaVersion = $script:TpmGameSupportSchemaVersionV12
    $base.Prerequisites = [ordered]@{ SupportFiles = $d.Prerequisites.SupportFiles; Administrator = $d.Prerequisites.Administrator; Controllers = $d.Prerequisites.Controllers }
    [void](Assert-TPMGameSupportContractV12 $base)
    $evidence = Assert-TPMGameSupportExactFieldsV1 $d.Evidence 'Evidence' @('Corpus','Entries','SourceIds','ProfileFileName','ProfileXmlSha256','ProfileSourcePath','Setup','Metadata','FixtureIds')
    Assert-TPMGameSupportArrayV1 $evidence.Entries 'Evidence.Entries'
    foreach ($entry in @($evidence.Entries)) { Assert-TPMGameSupportEvidenceEntryV13 $entry 'Evidence.Entry' }
    $prereq = Assert-TPMGameSupportExactFieldsV1 $d.Prerequisites 'Prerequisites' @('SupportFiles','Administrator','Controllers','ExternalSoftware')
    [void](Assert-TPMGameSupportExternalSoftwareV13 $prereq.ExternalSoftware 'Prerequisites.ExternalSoftware' -EvidenceEntries @($evidence.Entries))
    if ($d.ProfileCode -ceq 'Showdown') {
        if (@($prereq.ExternalSoftware.Items).Count -ne 1) { throw 'GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: Showdown must contain exactly one external software item' }
        $showdown = @($prereq.ExternalSoftware.Items)[0]
        if ($showdown.DependencyId -cne 'dependency-rapture3d-game-edition' -or $showdown.DependencyType -cne 'AUDIO_RUNTIME' -or $showdown.RequirementState -cne 'REQUIRED' -or $null -ne $showdown.VersionConstraint -or $showdown.Architecture -cne 'UNKNOWN') { throw 'GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: Showdown Rapture3D declaration is not canonical' }
        $policy = $showdown.AutomationPolicy
        if (-not $policy.MayLocateLocalInstaller -or $policy.MayDetectInstalled -or $policy.MayVerifyVersion -or $policy.MayVerifyArchitecture -or $policy.MayVerifyHash -or $policy.MayRunLocalInstaller -or $policy.MayDownload -or $policy.MayRedistribute -or $policy.MayAcceptEulaAutomatically -or $policy.MayUseUnverifiedSource) { throw 'GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: Showdown automation policy is not conservative' }
        if ($showdown.InstallerIdentity.Sha256 -ne $null) { throw 'GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: Showdown installer hash must remain undeclared' }
    } else {
        foreach ($item in @($prereq.ExternalSoftware.Items)) { if ($item.DependencyId -eq 'dependency-rapture3d-game-edition') { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: Rapture3D may only be declared for Showdown, found '$($d.ProfileCode)'" } }
    }
    return $d
}

function Test-TPMGameSupportContractV1 {
    param([Parameter(Mandatory = $true)]$Contract)
    try {
        $version = [string](Get-TPMGameSupportValueV1 $Contract 'SchemaVersion' '')
        if ($version -eq $script:TpmGameSupportSchemaVersionV11) { [void](Assert-TPMGameSupportContractV11 $Contract) }
        elseif ($version -eq $script:TpmGameSupportSchemaVersionV12) { [void](Assert-TPMGameSupportContractV12 $Contract) }
        elseif ($version -eq $script:TpmGameSupportSchemaVersionV13) { [void](Assert-TPMGameSupportContractV13 $Contract) }
        else { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: unsupported SchemaVersion '$version'" }
        return [pscustomobject]@{ Valid = $true; Errors = @() }
    } catch { return [pscustomobject]@{ Valid = $false; Errors = @($_.Exception.Message) } }
}

function New-TPMGameSupportGameSourceV1 {
    param($Source)
    if ($null -eq $Source) { return [ordered]@{ Repository = ''; Commit = ''; ProfileRoot = '' } }
    return [ordered]@{ Repository = [string](Get-TPMGameSupportValueV1 $Source 'Repository' ''); Commit = [string](Get-TPMGameSupportValueV1 $Source 'Commit' ''); ProfileRoot = [string](Get-TPMGameSupportValueV1 $Source 'ProfileRoot' '') }
}

function New-TPMGameSupportBackendDerivationAuditV12 {
    param([object[]]$Profiles)
    $matched = @($Profiles | Where-Object { [string](Get-TPMGameSupportValueV1 $_ 'EmulatorType' '') -ieq 'cxbxr' } | ForEach-Object { [string](Get-TPMGameSupportValueV1 $_ 'ProfileCode' '') } | Sort-Object)
    return @([ordered]@{ RuleId = 'ConfigureCxbxr.RequiredBiosFiles'; BackendIdentity = 'cxbxr'; Predicate = New-TPMGameSupportAppliesWhenV12 -EmulatorTypes @('cxbxr'); MatchedProfileCodes = $matched; MatchedCount = $matched.Count; EvidenceRefs = @('tpui:cxbxr:required-bios'); Reason = 'Materialize shared cxbxr BIOS requirements only for profiles whose pinned EmulatorType is cxbxr.' })
}

function New-TPMGameSupportContractRegistryV1 {
    param([Parameter(Mandatory = $true)][object[]]$Profiles, [Parameter(Mandatory = $true)][string]$SnapshotId, [Parameter(Mandatory = $true)][string]$CapturedAtUtc, [object]$Source = $null, [Nullable[int]]$ExpectedProfileCount = $null)
    $sourceValue = New-TPMGameSupportGameSourceV1 -Source $Source
    $contracts = New-Object System.Collections.Generic.List[object]
    foreach ($profileItem in @($Profiles | Sort-Object ProfileCode)) { [void]$contracts.Add((New-TPMGameSupportContractV1 -Profile $profileItem -SnapshotId $SnapshotId -CapturedAtUtc $CapturedAtUtc -Repository $sourceValue.Repository -Commit $sourceValue.Commit)) }
    $totals = [ordered]@{ AUTOMATED_SAFE = 0; REVIEW_MANUAL = 0; BLOCKED_UNSUPPORTED = 0; UNCLASSIFIED = 0 }
    foreach ($contract in $contracts) { if ($totals.Contains($contract.ReleasePosture)) { $totals[$contract.ReleasePosture] = [int]$totals[$contract.ReleasePosture] + 1 } }
    $registry = [ordered]@{ RegistryId = 'TPM-GAME-SUPPORT-CONTRACTS'; SchemaVersion = $script:TpmGameSupportSchemaVersionV12; SnapshotId = $SnapshotId; CapturedAtUtc = $CapturedAtUtc; Source = $sourceValue; ExpectedProfileCount = $ExpectedProfileCount; ContractCount = $contracts.Count; ClassificationTotals = $totals; BackendDerivationAudit = New-TPMGameSupportBackendDerivationAuditV12 -Profiles $Profiles; ReleaseGate = [ordered]@{}; Contracts = $contracts.ToArray() }
    $validation = Test-TPMGameSupportContractRegistryV1 -Registry $registry
    $registry.ReleaseGate = $validation.ReleaseGate
    return $registry
}


function New-TPMGameSupportContractRegistryV13 {
    param([Parameter(Mandatory = $true)][object[]]$Profiles, [Parameter(Mandatory = $true)][string]$SnapshotId, [Parameter(Mandatory = $true)][string]$CapturedAtUtc, [object]$Source = $null, [Nullable[int]]$ExpectedProfileCount = $null)
    $sourceValue = New-TPMGameSupportGameSourceV1 -Source $Source
    $contracts = New-Object System.Collections.Generic.List[object]
    foreach ($profileItem in @($Profiles | Sort-Object ProfileCode)) { [void]$contracts.Add((New-TPMGameSupportContractV13 -Profile $profileItem -SnapshotId $SnapshotId -CapturedAtUtc $CapturedAtUtc -Repository $sourceValue.Repository -Commit $sourceValue.Commit)) }
    $totals = [ordered]@{ AUTOMATED_SAFE = 0; REVIEW_MANUAL = 0; BLOCKED_UNSUPPORTED = 0; UNCLASSIFIED = 0 }
    foreach ($contract in $contracts) { if ($totals.Contains($contract.ReleasePosture)) { $totals[$contract.ReleasePosture] = [int]$totals[$contract.ReleasePosture] + 1 } }
    $registry = [ordered]@{ RegistryId = 'TPM-GAME-SUPPORT-CONTRACTS'; SchemaVersion = $script:TpmGameSupportSchemaVersionV13; SnapshotId = $SnapshotId; CapturedAtUtc = $CapturedAtUtc; Source = $sourceValue; ExpectedProfileCount = $ExpectedProfileCount; ContractCount = $contracts.Count; ClassificationTotals = $totals; BackendDerivationAudit = New-TPMGameSupportBackendDerivationAuditV12 -Profiles $Profiles; ReleaseGate = [ordered]@{}; Contracts = $contracts.ToArray() }
    $validation = Test-TPMGameSupportContractRegistryV13 -Registry $registry
    $registry.ReleaseGate = $validation.ReleaseGate
    return $registry
}

function Test-TPMGameSupportContractRegistryV13 {
    param([Parameter(Mandatory = $true)]$Registry)
    $errors = New-Object System.Collections.Generic.List[string]
    try {
        $required = @('RegistryId','SchemaVersion','SnapshotId','CapturedAtUtc','Source','ExpectedProfileCount','ContractCount','ClassificationTotals','BackendDerivationAudit','ReleaseGate','Contracts')
        $d = Assert-TPMGameSupportExactFieldsV1 $Registry 'RegistryV1.3' $required
        if ($d.RegistryId -cne 'TPM-GAME-SUPPORT-CONTRACTS' -or $d.SchemaVersion -cne $script:TpmGameSupportSchemaVersionV13) { throw 'GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: invalid 1.3 registry identity or version' }
        Assert-TPMGameSupportStringV1 $d.SnapshotId 'Registry.SnapshotId'; Assert-TPMGameSupportStringV1 $d.CapturedAtUtc 'Registry.CapturedAtUtc'; Assert-TPMGameSupportArrayV1 $d.Contracts 'Registry.Contracts'
        $contractCount = @($d.Contracts).Count
        if ([int]$d.ContractCount -ne $contractCount) { throw 'GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: Registry.ContractCount does not match Contracts.' }
        $expected = $null
        if ($null -ne $d.ExpectedProfileCount) { $expected = [int]$d.ExpectedProfileCount; if ($expected -ne $contractCount) { [void]$errors.Add("PROFILE_COUNT_MISMATCH: expected $expected, found $contractCount") } }
        $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $profiles = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $totals = [ordered]@{ AUTOMATED_SAFE = 0; REVIEW_MANUAL = 0; BLOCKED_UNSUPPORTED = 0; UNCLASSIFIED = 0 }
        foreach ($contract in @($d.Contracts)) {
            $validated = Assert-TPMGameSupportContractV13 $contract
            if (-not $ids.Add([string]$validated.ContractId)) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: duplicate ContractId '$($validated.ContractId)'" }
            if (-not $profiles.Add([string]$validated.ProfileCode)) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: duplicate ProfileCode '$($validated.ProfileCode)'" }
            if ([string]$validated.SnapshotId -cne [string]$d.SnapshotId) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: $($validated.ContractId) SnapshotId mismatch" }
            $totals[$validated.ReleasePosture] = [int]$totals[$validated.ReleasePosture] + 1
        }
        if ($totals.UNCLASSIFIED -gt 0) { [void]$errors.Add('UNCLASSIFIED_RECORDS_PRESENT') }
        foreach ($row in @($d.BackendDerivationAudit)) { if ([int]$row.MatchedCount -ne @($row.MatchedProfileCodes).Count) { throw 'GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: backend audit count mismatch' } }
        $source = $d.Source
        $sourceComplete = (-not [string]::IsNullOrWhiteSpace([string]$source.Repository)) -and (-not [string]::IsNullOrWhiteSpace([string]$source.Commit))
        $valid = ($errors.Count -eq 0)
        $closure = [ordered]@{
            ProfileCount = $contractCount
            ExpectedProfileCount = $expected
            ProfileCountMatches = ($null -eq $expected -or $expected -eq $contractCount)
            ZeroUnclassified = ($totals.UNCLASSIFIED -eq 0)
            NoDuplicateProfileCodes = ($profiles.Count -eq $contractCount)
            EveryRecordHasPosture = $true
            EveryRecordHasReason = (@($d.Contracts | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.ClassificationReason) }).Count -eq 0)
            EveryRecordHasProfileEvidenceHash = (@($d.Contracts | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.Evidence.ProfileXmlSha256) }).Count -eq 0)
            SourceIdentityComplete = $sourceComplete
            ClosureEligible = ($valid -and $sourceComplete)
        }
        return [pscustomobject]@{ Valid = $valid; Errors = $errors.ToArray(); ContractCount = $contractCount; ReleaseGate = [pscustomobject]$closure; ClassificationTotals = [pscustomobject]$totals }
    } catch {
        [void]$errors.Add($_.Exception.Message)
        return [pscustomobject]@{ Valid = $false; Errors = $errors.ToArray(); ContractCount = 0; ReleaseGate = [pscustomobject]@{ ClosureEligible = $false }; ClassificationTotals = [pscustomobject]@{} }
    }
}

function Test-TPMGameSupportContractRegistryV11 {
    param([Parameter(Mandatory = $true)]$Registry)
    try {
        $required = @('RegistryId','SchemaVersion','SnapshotId','CapturedAtUtc','Source','ExpectedProfileCount','ContractCount','ClassificationTotals','ReleaseGate','Contracts')
        $d = Assert-TPMGameSupportExactFieldsV1 $Registry 'RegistryV1.1' $required
        if ($d.RegistryId -cne 'TPM-GAME-SUPPORT-CONTRACTS' -or $d.SchemaVersion -cne $script:TpmGameSupportSchemaVersionV11) { throw 'GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: invalid 1.1 registry identity or version' }
        Assert-TPMGameSupportStringV1 $d.SnapshotId 'Registry.SnapshotId'
        Assert-TPMGameSupportStringV1 $d.CapturedAtUtc 'Registry.CapturedAtUtc'
        Assert-TPMGameSupportArrayV1 $d.Contracts 'Registry.Contracts'
        if ([int]$d.ContractCount -ne @($d.Contracts).Count) { throw 'GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: 1.1 registry count mismatch' }
        $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $profiles = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($contract in @($d.Contracts)) {
            $validated = Assert-TPMGameSupportContractV11 $contract
            if (-not $ids.Add([string]$validated.ContractId)) { throw 'GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: duplicate 1.1 ContractId' }
            if (-not $profiles.Add([string]$validated.ProfileCode)) { throw 'GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: duplicate 1.1 ProfileCode' }
        }
        return [pscustomobject]@{ Valid = $true; Errors = @(); ContractCount = @($d.Contracts).Count; ReleaseGate = $d.ReleaseGate; ClassificationTotals = $d.ClassificationTotals }
    } catch {
        return [pscustomobject]@{ Valid = $false; Errors = @($_.Exception.Message); ContractCount = 0; ReleaseGate = [pscustomobject]@{ ClosureEligible = $false }; ClassificationTotals = [pscustomobject]@{} }
    }
}
function Test-TPMGameSupportContractRegistryV1 {
    param([Parameter(Mandatory = $true)]$Registry)
    $version = [string](Get-TPMGameSupportValueV1 $Registry 'SchemaVersion' '')
    if ($version -eq $script:TpmGameSupportSchemaVersionV11) { return Test-TPMGameSupportContractRegistryV11 -Registry $Registry }
    if ($version -eq $script:TpmGameSupportSchemaVersionV13) { return Test-TPMGameSupportContractRegistryV13 -Registry $Registry }
    if ($version -ne $script:TpmGameSupportSchemaVersionV12) { return [pscustomobject]@{ Valid = $false; Errors = @("GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: unsupported registry SchemaVersion '$version'"); ContractCount = 0; ReleaseGate = [pscustomobject]@{ ClosureEligible = $false }; ClassificationTotals = [pscustomobject]@{} } }
    $errors = New-Object System.Collections.Generic.List[string]; $contractCount = 0; $expected = $null
    try {
        $required = @('RegistryId','SchemaVersion','SnapshotId','CapturedAtUtc','Source','ExpectedProfileCount','ContractCount','ClassificationTotals','BackendDerivationAudit','ReleaseGate','Contracts')
        $d = Assert-TPMGameSupportExactFieldsV1 $Registry 'Registry' $required
        if ($d.RegistryId -cne 'TPM-GAME-SUPPORT-CONTRACTS') { throw 'GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: RegistryId' }
        if ($d.SchemaVersion -cne $script:TpmGameSupportSchemaVersionV12) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: unsupported registry SchemaVersion '$($d.SchemaVersion)'" }
        Assert-TPMGameSupportStringV1 $d.SnapshotId 'Registry.SnapshotId'; Assert-TPMGameSupportStringV1 $d.CapturedAtUtc 'Registry.CapturedAtUtc'; Assert-TPMGameSupportArrayV1 $d.Contracts 'Registry.Contracts'; $contractCount = @($d.Contracts).Count
        if ([int]$d.ContractCount -ne $contractCount) { throw 'GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: Registry.ContractCount does not match Contracts.' }
        if ($null -ne $d.ExpectedProfileCount) { $expected = [int]$d.ExpectedProfileCount; if ($expected -ne $contractCount) { [void]$errors.Add("PROFILE_COUNT_MISMATCH: expected $expected, found $contractCount") } }
        $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); $profiles = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); $totals = [ordered]@{ AUTOMATED_SAFE = 0; REVIEW_MANUAL = 0; BLOCKED_UNSUPPORTED = 0; UNCLASSIFIED = 0 }
        foreach ($contract in $d.Contracts) { $validated = Assert-TPMGameSupportContractV12 $contract; if (-not $ids.Add([string]$validated.ContractId)) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: duplicate ContractId '$($validated.ContractId)'" }; if (-not $profiles.Add([string]$validated.ProfileCode)) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: duplicate ProfileCode '$($validated.ProfileCode)'" }; if ([string]$validated.SnapshotId -cne [string]$d.SnapshotId) { throw "GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: $($validated.ContractId) SnapshotId mismatch" }; $totals[$validated.ReleasePosture] = [int]$totals[$validated.ReleasePosture] + 1 }
        if ($totals.UNCLASSIFIED -gt 0) { [void]$errors.Add('UNCLASSIFIED_RECORDS_PRESENT') }
        $audit = @($d.BackendDerivationAudit); foreach ($row in $audit) { if ([int]$row.MatchedCount -ne @($row.MatchedProfileCodes).Count) { throw 'GAME_SUPPORT_CONTRACT_SCHEMA_INVALID: backend audit count mismatch' } }
        $source = $d.Source; $sourceComplete = (-not [string]::IsNullOrWhiteSpace([string]$source.Repository)) -and (-not [string]::IsNullOrWhiteSpace([string]$source.Commit)); $valid = ($errors.Count -eq 0)
        $closure = [ordered]@{ ProfileCount = $contractCount; ExpectedProfileCount = $expected; ProfileCountMatches = ($null -eq $expected -or $expected -eq $contractCount); ZeroUnclassified = ($totals.UNCLASSIFIED -eq 0); NoDuplicateProfileCodes = ($profiles.Count -eq $contractCount); EveryRecordHasPosture = $true; EveryRecordHasReason = (@($d.Contracts | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.ClassificationReason) }).Count -eq 0); EveryRecordHasProfileEvidenceHash = (@($d.Contracts | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.Evidence.ProfileXmlSha256) }).Count -eq 0); SourceIdentityComplete = $sourceComplete; ClosureEligible = ($valid -and $sourceComplete) }
        return [pscustomobject]@{ Valid = $valid; Errors = $errors.ToArray(); ContractCount = $contractCount; ReleaseGate = [pscustomobject]$closure; ClassificationTotals = [pscustomobject]$totals }
    } catch { [void]$errors.Add($_.Exception.Message); return [pscustomobject]@{ Valid = $false; Errors = $errors.ToArray(); ContractCount = $contractCount; ReleaseGate = [pscustomobject]@{ ProfileCount = $contractCount; ExpectedProfileCount = $expected; ProfileCountMatches = $false; ZeroUnclassified = $false; ClosureEligible = $false }; ClassificationTotals = [pscustomobject]@{} } }
}

function Get-TPMGameSupportContractRegistryV1 {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "GAME_SUPPORT_CONTRACT_MISSING: $Path" }
    $registry = ConvertFrom-TPMGameSupportOrderedJsonV1 -Json ([System.IO.File]::ReadAllText($Path))
    $validation = Test-TPMGameSupportContractRegistryV1 -Registry $registry
    if (-not $validation.Valid) { throw "GAME_SUPPORT_CONTRACT_INVALID: $($validation.Errors -join '; ')" }
    return $registry
}

function Get-TPMGameSupportContractV1 {
    param([Parameter(Mandatory = $true)]$Registry, [Parameter(Mandatory = $true)][string]$ProfileCode)
    $match = @($Registry.Contracts | Where-Object { [string]$_.ProfileCode -ieq $ProfileCode }); if ($match.Count -ne 1) { throw "GAME_SUPPORT_CONTRACT_NOT_FOUND: expected exactly one contract for '$ProfileCode', found $($match.Count)." }; return $match[0]
}

function Write-TPMGameSupportContractRegistryV1 {
    param([Parameter(Mandatory = $true)]$Registry, [Parameter(Mandatory = $true)][string]$Path)
    $version = [string](Get-TPMGameSupportValueV1 $Registry 'SchemaVersion' '')
    if ($version -eq $script:TpmGameSupportSchemaVersionV12) { $validation = Test-TPMGameSupportContractRegistryV1 -Registry $Registry; if (-not $validation.Valid) { throw "GAME_SUPPORT_CONTRACT_INVALID: $($validation.Errors -join '; ')" } }
    elseif ($version -eq $script:TpmGameSupportSchemaVersionV11) { $validation = Test-TPMGameSupportContractRegistryV11 -Registry $Registry; if (-not $validation.Valid) { throw "GAME_SUPPORT_CONTRACT_INVALID: $($validation.Errors -join '; ')" } }
    elseif ($version -eq $script:TpmGameSupportSchemaVersionV13) { $validation = Test-TPMGameSupportContractRegistryV13 -Registry $Registry; if (-not $validation.Valid) { throw "GAME_SUPPORT_CONTRACT_INVALID: $($validation.Errors -join '; ')" } }
    else { throw "GAME_SUPPORT_CONTRACT_INVALID: unsupported SchemaVersion '$version'" }
    $parent = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Path)); if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) { [void][System.IO.Directory]::CreateDirectory($parent) }
    [System.IO.File]::WriteAllText($Path, (($Registry | ConvertTo-Json -Depth 40) + "`n"), (New-Object System.Text.UTF8Encoding($false)))
}

Export-ModuleMember -Function New-TPMGameSupportContractV1,New-TPMGameSupportContractV13,New-TPMGameSupportExternalSoftwareV13,New-TPMGameSupportContractRegistryV1,New-TPMGameSupportContractRegistryV13,Test-TPMGameSupportContractV1,Test-TPMGameSupportContractRegistryV1,Get-TPMGameSupportContractRegistryV1,Get-TPMGameSupportContractV1,Write-TPMGameSupportContractRegistryV1,Get-TPMGameSupportContractIdV1,Get-TPMGameSupportValueV1
