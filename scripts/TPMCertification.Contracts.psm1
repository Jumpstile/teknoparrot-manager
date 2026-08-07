Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Authority.psm1')
Set-StrictMode -Version 2.0

# Emulator Contract Verification Framework (ECVF) foundation.
#
# A contract is a versioned, machine-readable description of what a specific
# emulator core promises to do, which component owns each piece of runtime
# state, and what evidence backs every claim. This module is the single
# source every subsystem (production runtime, certification authority,
# shadow validation, smoke validation) must load contracts through -- no
# subsystem is permitted to parse or reinterpret contracts/*/contract.json
# independently. This module does not itself decide certification outcomes;
# it loads, validates, and evaluates contracts. Wiring it into Authority,
# Shadow, Smoke, or the main TPM runtime is a separate, later step.

function Get-TPMContractsRootV1 {
    # scripts\ is one level below the repository root, where contracts\ lives
    # (same root TeknoParrot-Manager.ps1 and Crosshairs\ live under).
    Join-Path (Split-Path -Parent $PSScriptRoot) 'contracts'
}

$script:TpmContractStatusValuesV1 = @('Investigating','EvidenceGathered','ExperimentallyVerified','RuntimeVerified','Certified','Deprecated','Superseded')
$script:TpmEvidenceConfidenceValuesV1 = @('Theoretical','SourceVerified','ExperimentVerified','HardwareVerified','ProductionVerified')
$script:TpmOwnerValuesV1 = @('Emulator','TPM','User','Runtime','ExternalTool')
$script:TpmMutabilityValuesV1 = @('Immutable','EmulatorManaged','TPMManaged','UserManaged','Computed')
$script:TpmReadPolicyValuesV1 = @('NeverRead','ReadForVerificationOnly','ReadForDisplay','ReadFreely')
$script:TpmWritePolicyValuesV1 = @('NeverWrite','WriteOnlyViaEmulatorMechanism','WriteDirectly','WriteWithBackup')
$script:TpmDriftFailClosedValuesV1 = @('FailClosed','Block')
$script:TpmDriftCompatibleValuesV1 = @('Proceed','ProceedWithWarning')
$script:TpmVersionMatchStateValuesV1 = @('Matched','Compatible','Diverged')
$script:TpmEvidenceTypeValuesV1 = @('SourceCitation','ControlledExperiment','HardwareObservation','ExternalDocumentation')
$script:TpmEvidenceSourceTypeValuesV1 = @('EmulatorLog','IniSnapshot','ExternalArtifact','ProcessExitCode')
$script:TpmObservableEvidenceStatusValuesV1 = @('Confirmed','Hypothesis','Unconfirmed')
$script:TpmDataRootResolverMethodValuesV1 = @('FileContentLiteral','FixedPath','EnvironmentVariable')
$script:TpmInitializationActionMethodValuesV1 = @('CliInvocation','FileTemplate','None')
$script:TpmParseMethodValuesV1 = @('IniSections','JsonKeys','YamlKeys')
$script:TpmDetectorMethodValuesV1 = @('WindowTitleRegex','ExecutableVersionResource','CliVersionFlag','LogLineRegex','FileHash','PathExists')

function ConvertTo-TPMOrderedValueV1 {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $result = [ordered]@{}
        foreach ($prop in $Value.PSObject.Properties) { $result[$prop.Name] = ConvertTo-TPMOrderedValueV1 $prop.Value }
        return $result
    }
    if (($Value -is [System.Collections.IEnumerable]) -and ($Value -isnot [string])) {
        $list = New-Object Collections.Generic.List[object]
        foreach ($item in $Value) { $list.Add((ConvertTo-TPMOrderedValueV1 $item)) }
        return , $list.ToArray()
    }
    return $Value
}

function ConvertFrom-TPMOrderedJsonV1 {
    param([Parameter(Mandatory = $true)][string]$Json)
    try { $parsed = ConvertFrom-Json -InputObject $Json -ErrorAction Stop } catch { throw "SCHEMA_INVALID: contract is not valid JSON -- $_" }
    return ConvertTo-TPMOrderedValueV1 $parsed
}

function Assert-TPMEnumV1 {
    param($Value, [string[]]$Allowed, [string]$Context)
    Assert-TPMStringV1 $Value $Context
    if ($Allowed -cnotcontains $Value) { throw "SCHEMA_INVALID: $Context must be one of: $($Allowed -join ', ')" }
}

function Assert-TPMArrayV1 {
    param($Value, [string]$Context, [switch]$AllowEmpty)
    if ($Value -isnot [object[]]) { throw "SCHEMA_INVALID: $Context must be an array" }
    if (-not $AllowEmpty -and $Value.Count -eq 0) { throw "SCHEMA_INVALID: $Context must not be empty" }
    return $Value
}

function Assert-TPMPredicateMapV1 {
    param($Value, [string]$Context)
    $map = Get-TPMValueMapV1 $Value
    if ($map.Keys.Count -eq 0) { throw "SCHEMA_INVALID: $Context must not be empty" }
    foreach ($key in $map.Keys) {
        $v = $map[$key]
        if ($v -isnot [bool] -and $v -isnot [string] -and $v -isnot [int] -and $v -isnot [long] -and $v -isnot [double]) {
            throw "SCHEMA_INVALID: $Context.$key must be a scalar (bool, string, or number)"
        }
    }
    return $map
}

function Assert-TPMVersionDetectorV1 {
    param($Value, [string]$Context)
    $d = Assert-TPMExactFieldsV1 $Value @('Method', 'Source', 'Pattern', 'MatchedCommitMap') $Context
    Assert-TPMEnumV1 $d.Method $script:TpmDetectorMethodValuesV1 "$Context.Method"
    Assert-TPMStringV1 $d.Source "$Context.Source" -Nullable
    Assert-TPMStringV1 $d.Pattern "$Context.Pattern"
    $entries = Assert-TPMArrayV1 $d.MatchedCommitMap "$Context.MatchedCommitMap" -AllowEmpty
    $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($entry in $entries) {
        $e = Assert-TPMExactFieldsV1 $entry @('VersionString', 'Commit', 'MatchState') "$Context.MatchedCommitMap[]"
        Assert-TPMStringV1 $e.VersionString "$Context.MatchedCommitMap[].VersionString"
        if (-not $seen.Add([string]$e.VersionString)) { throw "SCHEMA_INVALID: $Context.MatchedCommitMap has a duplicate VersionString '$($e.VersionString)'" }
        if ($e.Commit -cnotmatch '^[0-9a-f]{40}$') { throw "SCHEMA_INVALID: $Context.MatchedCommitMap[].Commit must be a lowercase 40-hex SHA" }
        Assert-TPMEnumV1 $e.MatchState $script:TpmVersionMatchStateValuesV1 "$Context.MatchedCommitMap[].MatchState"
    }
    return $d
}

function Assert-TPMOwnershipBoundaryV1 {
    param($Value, [string]$Context)
    $d = Assert-TPMExactFieldsV1 $Value @('SettingPath', 'Owner', 'Mutability', 'ReadPolicy', 'WritePolicy', 'EvidenceReference') $Context
    Assert-TPMStringV1 $d.SettingPath "$Context.SettingPath"
    Assert-TPMEnumV1 $d.Owner $script:TpmOwnerValuesV1 "$Context.Owner"
    Assert-TPMEnumV1 $d.Mutability $script:TpmMutabilityValuesV1 "$Context.Mutability"
    Assert-TPMEnumV1 $d.ReadPolicy $script:TpmReadPolicyValuesV1 "$Context.ReadPolicy"
    Assert-TPMEnumV1 $d.WritePolicy $script:TpmWritePolicyValuesV1 "$Context.WritePolicy"
    Assert-TPMStringV1 $d.EvidenceReference "$Context.EvidenceReference"
    if (($d.Owner -eq 'Emulator' -or $d.Owner -eq 'Runtime') -and $d.WritePolicy -eq 'WriteDirectly') {
        throw "SCHEMA_INVALID: $Context -- Owner '$($d.Owner)' may not carry WritePolicy 'WriteDirectly'"
    }
    return $d
}

function Assert-TPMObservableEvidenceEntryV1 {
    param($Value, [string]$Context)
    $d = Assert-TPMExactFieldsV1 $Value @('EvidenceSourceType', 'Reliability', 'Locator', 'Status') $Context
    Assert-TPMEnumV1 $d.EvidenceSourceType $script:TpmEvidenceSourceTypeValuesV1 "$Context.EvidenceSourceType"
    Assert-TPMIntegerV1 $d.Reliability "$Context.Reliability" -Minimum 1
    Assert-TPMStringV1 $d.Locator "$Context.Locator" -Nullable
    Assert-TPMEnumV1 $d.Status $script:TpmObservableEvidenceStatusValuesV1 "$Context.Status"
    return $d
}

function Assert-TPMObservableEvidenceArrayV1 {
    param($Value, [string]$Context)
    $entries = Assert-TPMArrayV1 $Value $Context
    $ranks = New-Object 'Collections.Generic.HashSet[int]'
    $result = New-Object Collections.Generic.List[object]
    foreach ($entry in $entries) {
        $e = Assert-TPMObservableEvidenceEntryV1 $entry "$Context[]"
        if (-not $ranks.Add([int]$e.Reliability)) { throw "SCHEMA_INVALID: $Context has duplicate Reliability rank $($e.Reliability)" }
        $result.Add($e)
    }
    return , $result.ToArray()
}

function Assert-TPMEnvironmentCapabilityV1 {
    param($Value, [string]$Context)
    $d = Assert-TPMExactFieldsV1 $Value @('CapabilityId', 'PresenceDetector', 'DataRootResolver', 'InitializationAction', 'InitializedVerifier', 'ObservableEvidence', 'ExpectedOutcome') $Context
    Assert-TPMStringV1 $d.CapabilityId "$Context.CapabilityId"

    $presence = Assert-TPMExactFieldsV1 $d.PresenceDetector @('Method', 'Source', 'Pattern') "$Context.PresenceDetector"
    Assert-TPMEnumV1 $presence.Method $script:TpmDetectorMethodValuesV1 "$Context.PresenceDetector.Method"
    Assert-TPMStringV1 $presence.Source "$Context.PresenceDetector.Source" -Nullable
    Assert-TPMStringV1 $presence.Pattern "$Context.PresenceDetector.Pattern" -Nullable

    $dataRoot = Assert-TPMExactFieldsV1 $d.DataRootResolver @('Method', 'Source', 'DefaultValue') "$Context.DataRootResolver"
    Assert-TPMEnumV1 $dataRoot.Method $script:TpmDataRootResolverMethodValuesV1 "$Context.DataRootResolver.Method"
    Assert-TPMStringV1 $dataRoot.Source "$Context.DataRootResolver.Source"
    Assert-TPMStringV1 $dataRoot.DefaultValue "$Context.DataRootResolver.DefaultValue" -Nullable

    $init = Assert-TPMExactFieldsV1 $d.InitializationAction @('Method', 'Command', 'Arguments', 'ExpectedExitCodes', 'TimeoutSeconds') "$Context.InitializationAction"
    Assert-TPMEnumV1 $init.Method $script:TpmInitializationActionMethodValuesV1 "$Context.InitializationAction.Method"
    Assert-TPMStringV1 $init.Command "$Context.InitializationAction.Command" -Nullable
    Assert-TPMArrayV1 $init.Arguments "$Context.InitializationAction.Arguments" -AllowEmpty | Out-Null
    $exitCodes = Assert-TPMArrayV1 $init.ExpectedExitCodes "$Context.InitializationAction.ExpectedExitCodes"
    foreach ($code in $exitCodes) { Assert-TPMIntegerV1 $code "$Context.InitializationAction.ExpectedExitCodes[]" -Minimum ([long]::MinValue) }
    Assert-TPMIntegerV1 $init.TimeoutSeconds "$Context.InitializationAction.TimeoutSeconds" -Minimum 1

    $verifier = Assert-TPMExactFieldsV1 $d.InitializedVerifier @('RequiredPaths', 'RequiredMarkers', 'ParseMethod') "$Context.InitializedVerifier"
    Assert-TPMArrayV1 $verifier.RequiredPaths "$Context.InitializedVerifier.RequiredPaths" | Out-Null
    Assert-TPMArrayV1 $verifier.RequiredMarkers "$Context.InitializedVerifier.RequiredMarkers" -AllowEmpty | Out-Null
    Assert-TPMEnumV1 $verifier.ParseMethod $script:TpmParseMethodValuesV1 "$Context.InitializedVerifier.ParseMethod"

    # ObservableEvidence here is a plain array of EvidenceId strings backing
    # this capability's claims -- referential integrity against
    # Contract.EvidenceReferences is checked by the caller (the root
    # validator), which is the only place that knows the full EvidenceId set.
    $evidenceIds = Assert-TPMArrayV1 $d.ObservableEvidence "$Context.ObservableEvidence"
    foreach ($evId in $evidenceIds) { Assert-TPMStringV1 $evId "$Context.ObservableEvidence[]" }
    Assert-TPMStringV1 $d.ExpectedOutcome "$Context.ExpectedOutcome"
    return $d
}

function Assert-TPMRuntimeCapabilityV1 {
    param($Value, [string]$Context)
    $d = Assert-TPMExactFieldsV1 $Value @('CapabilityId', 'Scenario', 'ApplicabilityPredicate', 'Trigger', 'ObservableEvidence', 'ExpectedOutcome', 'CapabilityStatus') $Context
    Assert-TPMStringV1 $d.CapabilityId "$Context.CapabilityId"
    Assert-TPMStringV1 $d.Scenario "$Context.Scenario"
    Assert-TPMPredicateMapV1 $d.ApplicabilityPredicate "$Context.ApplicabilityPredicate" | Out-Null
    $trigger = Assert-TPMExactFieldsV1 $d.Trigger @('Description', 'Source') "$Context.Trigger"
    Assert-TPMStringV1 $trigger.Description "$Context.Trigger.Description"
    Assert-TPMStringV1 $trigger.Source "$Context.Trigger.Source"
    Assert-TPMObservableEvidenceArrayV1 $d.ObservableEvidence "$Context.ObservableEvidence" | Out-Null
    Assert-TPMStringV1 $d.ExpectedOutcome "$Context.ExpectedOutcome"
    Assert-TPMEnumV1 $d.CapabilityStatus $script:TpmContractStatusValuesV1 "$Context.CapabilityStatus"
    return $d
}

function Assert-TPMEvidenceReferenceV1 {
    param($Value, [string]$Context)
    $d = Assert-TPMExactFieldsV1 $Value @('EvidenceId', 'Type', 'Description', 'Locator', 'Commit', 'Confidence', 'RecordedDate') $Context
    Assert-TPMStringV1 $d.EvidenceId "$Context.EvidenceId"
    Assert-TPMEnumV1 $d.Type $script:TpmEvidenceTypeValuesV1 "$Context.Type"
    Assert-TPMStringV1 $d.Description "$Context.Description"
    Assert-TPMStringV1 $d.Locator "$Context.Locator"
    if ($null -ne $d.Commit -and $d.Commit -cnotmatch '^[0-9a-f]{40}$') { throw "SCHEMA_INVALID: $Context.Commit must be null or a lowercase 40-hex SHA" }
    Assert-TPMEnumV1 $d.Confidence $script:TpmEvidenceConfidenceValuesV1 "$Context.Confidence"
    Assert-TPMStringV1 $d.RecordedDate "$Context.RecordedDate"
    return $d
}

function Assert-TPMDriftPolicyV1 {
    param($Value, [string]$Context)
    $d = Assert-TPMExactFieldsV1 $Value @('OnUnknownVersion', 'OnDivergedVersion', 'OnCompatibleRange', 'KnownCompatibleRange', 'RevalidationTrigger') $Context
    Assert-TPMEnumV1 $d.OnUnknownVersion $script:TpmDriftFailClosedValuesV1 "$Context.OnUnknownVersion"
    Assert-TPMEnumV1 $d.OnDivergedVersion $script:TpmDriftFailClosedValuesV1 "$Context.OnDivergedVersion"
    Assert-TPMEnumV1 $d.OnCompatibleRange $script:TpmDriftCompatibleValuesV1 "$Context.OnCompatibleRange"
    $ranges = Assert-TPMArrayV1 $d.KnownCompatibleRange "$Context.KnownCompatibleRange" -AllowEmpty
    foreach ($range in $ranges) {
        $r = Assert-TPMExactFieldsV1 $range @('CommitOrTagStart', 'CommitOrTagEnd', 'Notes') "$Context.KnownCompatibleRange[]"
        Assert-TPMStringV1 $r.CommitOrTagStart "$Context.KnownCompatibleRange[].CommitOrTagStart"
        Assert-TPMStringV1 $r.CommitOrTagEnd "$Context.KnownCompatibleRange[].CommitOrTagEnd"
        Assert-TPMStringV1 $r.Notes "$Context.KnownCompatibleRange[].Notes" -Nullable
    }
    Assert-TPMStringV1 $d.RevalidationTrigger "$Context.RevalidationTrigger"
    return $d
}

function Assert-TPMEmulatorContractV1 {
    # Validates a parsed contract (already run through ConvertFrom-TPMOrderedJsonV1)
    # against the EmulatorContractV1 root schema. Throws SCHEMA_INVALID: <reason>
    # on any violation, per the fail-closed idiom used throughout the rest of
    # certification authority. Returns the validated ordered map on success.
    param([Parameter(Mandatory = $true)]$Contract, [string]$ExpectedContractId)
    $d = Assert-TPMExactFieldsV1 $Contract @(
        'ContractId', 'SchemaVersion', 'DisplayName',
        'UpstreamRepository', 'UpstreamPinnedCommit', 'UpstreamPinnedCommitDate',
        'VersionDetector', 'ContractStatus', 'EvidenceConfidence',
        'OwnershipBoundaries', 'EnvironmentCapabilities', 'RuntimeCapabilities',
        'EvidenceReferences', 'DriftPolicy'
    ) 'Contract'
    Assert-TPMStringV1 $d.ContractId 'Contract.ContractId'
    if (-not [string]::IsNullOrEmpty($ExpectedContractId) -and $d.ContractId -cne $ExpectedContractId) {
        throw "SCHEMA_INVALID: Contract.ContractId '$($d.ContractId)' does not match its directory name '$ExpectedContractId'"
    }
    if ($d.SchemaVersion -cne '1.0.0') { throw "SCHEMA_INVALID: Contract.SchemaVersion must be '1.0.0'" }
    Assert-TPMStringV1 $d.DisplayName 'Contract.DisplayName' -Nullable
    Assert-TPMStringV1 $d.UpstreamRepository 'Contract.UpstreamRepository'
    if ($d.UpstreamPinnedCommit -cnotmatch '^[0-9a-f]{40}$') { throw 'SCHEMA_INVALID: Contract.UpstreamPinnedCommit must be a lowercase 40-hex SHA' }
    Assert-TPMStringV1 $d.UpstreamPinnedCommitDate 'Contract.UpstreamPinnedCommitDate'

    Assert-TPMVersionDetectorV1 $d.VersionDetector 'Contract.VersionDetector' | Out-Null
    Assert-TPMEnumV1 $d.ContractStatus $script:TpmContractStatusValuesV1 'Contract.ContractStatus'
    Assert-TPMEnumV1 $d.EvidenceConfidence $script:TpmEvidenceConfidenceValuesV1 'Contract.EvidenceConfidence'

    $evidenceIds = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $evidenceRefs = Assert-TPMArrayV1 $d.EvidenceReferences 'Contract.EvidenceReferences'
    foreach ($ref in $evidenceRefs) {
        $e = Assert-TPMEvidenceReferenceV1 $ref 'Contract.EvidenceReferences[]'
        if (-not $evidenceIds.Add([string]$e.EvidenceId)) { throw "SCHEMA_INVALID: Contract.EvidenceReferences has a duplicate EvidenceId '$($e.EvidenceId)'" }
    }
    $assertEvidenceIdKnown = {
        param([string]$Id, [string]$Context)
        if (-not $evidenceIds.Contains($Id)) { throw "SCHEMA_INVALID: $Context references unknown EvidenceId '$Id'" }
    }.GetNewClosure()

    $ownershipPaths = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $ownerships = Assert-TPMArrayV1 $d.OwnershipBoundaries 'Contract.OwnershipBoundaries'
    foreach ($boundary in $ownerships) {
        $b = Assert-TPMOwnershipBoundaryV1 $boundary 'Contract.OwnershipBoundaries[]'
        if (-not $ownershipPaths.Add([string]$b.SettingPath)) { throw "SCHEMA_INVALID: Contract.OwnershipBoundaries has a duplicate SettingPath '$($b.SettingPath)'" }
        & $assertEvidenceIdKnown $b.EvidenceReference 'Contract.OwnershipBoundaries[].EvidenceReference'
    }

    $envIds = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $envCaps = Assert-TPMArrayV1 $d.EnvironmentCapabilities 'Contract.EnvironmentCapabilities' -AllowEmpty
    foreach ($cap in $envCaps) {
        $c = Assert-TPMEnvironmentCapabilityV1 $cap 'Contract.EnvironmentCapabilities[]'
        if (-not $envIds.Add([string]$c.CapabilityId)) { throw "SCHEMA_INVALID: Contract.EnvironmentCapabilities has a duplicate CapabilityId '$($c.CapabilityId)'" }
        foreach ($evId in $c.ObservableEvidence) { & $assertEvidenceIdKnown $evId 'Contract.EnvironmentCapabilities[].ObservableEvidence[]' }
    }

    $runtimeIds = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $runtimeCaps = Assert-TPMArrayV1 $d.RuntimeCapabilities 'Contract.RuntimeCapabilities' -AllowEmpty
    foreach ($cap in $runtimeCaps) {
        $c = Assert-TPMRuntimeCapabilityV1 $cap 'Contract.RuntimeCapabilities[]'
        if (-not $runtimeIds.Add([string]$c.CapabilityId)) { throw "SCHEMA_INVALID: Contract.RuntimeCapabilities has a duplicate CapabilityId '$($c.CapabilityId)'" }
    }

    Assert-TPMDriftPolicyV1 $d.DriftPolicy 'Contract.DriftPolicy' | Out-Null
    return $d
}

function Get-TPMRegisteredEmulatorContractsV1 {
    # Auto-discovers contracts by scanning contracts/*/contract.json -- there is
    # deliberately no separate maintained index file. A directory-scan registry
    # has exactly one source of truth (the filesystem); a hand-maintained index
    # would itself be a second, independently-driftable interpretation of what
    # is registered. -ContractsRoot exists so tests can point this at an
    # isolated fixture tree instead of the real contracts\ directory.
    param([string]$ContractsRoot)
    $root = if ([string]::IsNullOrWhiteSpace($ContractsRoot)) { Get-TPMContractsRootV1 } else { $ContractsRoot }
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return , @() }
    $results = New-Object Collections.Generic.List[object]
    $dirs = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '_schema' } | Sort-Object Name)
    foreach ($dir in $dirs) {
        $contractPath = Join-Path $dir.FullName 'contract.json'
        if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) { continue }
        $json = [System.IO.File]::ReadAllText($contractPath)
        $parsed = ConvertFrom-TPMOrderedJsonV1 -Json $json
        $validated = Assert-TPMEmulatorContractV1 -Contract $parsed -ExpectedContractId $dir.Name
        $results.Add([pscustomobject]@{ ContractId = $dir.Name; Path = $contractPath; Contract = $validated })
    }
    return , $results.ToArray()
}

function Get-TPMEmulatorContractV1 {
    param([Parameter(Mandatory = $true)][string]$ContractId, [string]$ContractsRoot)
    $root = if ([string]::IsNullOrWhiteSpace($ContractsRoot)) { Get-TPMContractsRootV1 } else { $ContractsRoot }
    $contractPath = Join-Path (Join-Path $root $ContractId) 'contract.json'
    if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) { throw "CONTRACT_NOT_FOUND: no contract.json for '$ContractId'" }
    $json = [System.IO.File]::ReadAllText($contractPath)
    $parsed = ConvertFrom-TPMOrderedJsonV1 -Json $json
    $validated = Assert-TPMEmulatorContractV1 -Contract $parsed -ExpectedContractId $ContractId
    return [pscustomobject]@{ ContractId = $ContractId; Path = $contractPath; Contract = $validated }
}

$script:TpmSupportedContractSchemaVersionsV1 = @('1.0.0')

function Get-TPMSupportedContractSchemaVersionsV1 { return , @($script:TpmSupportedContractSchemaVersionsV1) }

function Assert-TPMSupportedContractSchemaVersionV1 {
    # Assert-TPMEmulatorContractV1 already requires SchemaVersion -ceq '1.0.0'
    # inline; this is the explicit, queryable form of that same rule -- the
    # single source both Test-TPMContractRegistryIntegrityV1 and any future
    # multi-schema-version loader consult, so "which versions does this build
    # actually support" is never re-typed as a second string literal.
    param([Parameter(Mandatory = $true)]$Contract)
    if ($script:TpmSupportedContractSchemaVersionsV1 -cnotcontains $Contract.SchemaVersion) {
        throw "SCHEMA_INVALID: Contract.SchemaVersion '$($Contract.SchemaVersion)' is not a supported EmulatorContractV1 version"
    }
}

function Assert-TPMContractLocatorsResolveV1 {
    # Verifies every EvidenceReference's Locator (the evidence.md / experiments.md
    # anchor a claim's proof lives at) actually resolves -- both the file and a
    # heading that starts with the anchor fragment. A contract with a citation
    # pointing nowhere is exactly as untrustworthy as one with no citation at
    # all, and this is the only mechanized check that would ever catch it.
    param([Parameter(Mandatory = $true)]$Contract, [Parameter(Mandatory = $true)][string]$ContractDirectory)
    foreach ($ref in $Contract.EvidenceReferences) {
        $locator = [string]$ref.Locator
        if ($locator -notmatch '^([^#]+)#(.+)$') { throw "SCHEMA_INVALID: EvidenceReferences[$($ref.EvidenceId)].Locator '$locator' is not in 'file#fragment' form" }
        $file = $Matches[1]
        $fragment = $Matches[2]
        $filePath = Join-Path $ContractDirectory $file
        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) { throw "SCHEMA_INVALID: EvidenceReferences[$($ref.EvidenceId)].Locator points to missing file '$file'" }
        $lines = [System.IO.File]::ReadAllLines($filePath)
        $found = $false
        foreach ($line in $lines) {
            if ($line.TrimStart() -match '^#{1,6}\s+(.+)$') {
                if ($Matches[1].StartsWith($fragment, [StringComparison]::Ordinal)) { $found = $true; break }
            }
        }
        if (-not $found) { throw "SCHEMA_INVALID: EvidenceReferences[$($ref.EvidenceId)].Locator anchor '$fragment' has no matching heading in '$file'" }
    }
}

function Test-TPMContractRegistryIntegrityV1 {
    # The permanent, fail-closed health check for the whole contract
    # registry: discovers every contracts/*/contract.json, validates each
    # (schema shape, unique ownership paths, unique capability IDs -- all
    # already enforced inside Assert-TPMEmulatorContractV1), verifies every
    # evidence/experiment Locator resolves, and verifies the schema version
    # is one this build supports. Collects every failure across every
    # contract rather than stopping at the first bad one, since a caller
    # deciding whether the registry as a whole is trustworthy needs the full
    # picture. This is the function any certification entry point must call
    # first and fail closed on -- a contract nobody can currently validate
    # must never be silently treated as though it still applies.
    param([string]$ContractsRoot)
    $root = if ([string]::IsNullOrWhiteSpace($ContractsRoot)) { Get-TPMContractsRootV1 } else { $ContractsRoot }
    $errors = New-Object Collections.Generic.List[object]
    $valid = New-Object Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        return [pscustomobject]@{ Valid = $true; ContractCount = 0; Contracts = @(); Errors = @() }
    }
    $dirs = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '_schema' } | Sort-Object Name)
    foreach ($dir in $dirs) {
        $contractPath = Join-Path $dir.FullName 'contract.json'
        if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) { continue }
        try {
            $json = [System.IO.File]::ReadAllText($contractPath)
            $parsed = ConvertFrom-TPMOrderedJsonV1 -Json $json
            $validated = Assert-TPMEmulatorContractV1 -Contract $parsed -ExpectedContractId $dir.Name
            Assert-TPMSupportedContractSchemaVersionV1 -Contract $validated
            Assert-TPMContractLocatorsResolveV1 -Contract $validated -ContractDirectory $dir.FullName
            $valid.Add([pscustomobject]@{ ContractId = $dir.Name; Path = $contractPath; Contract = $validated })
        } catch {
            $errors.Add([pscustomobject]@{ ContractId = $dir.Name; Message = $_.Exception.Message })
        }
    }
    return [pscustomobject]@{ Valid = ($errors.Count -eq 0); ContractCount = $valid.Count; Contracts = $valid.ToArray(); Errors = $errors.ToArray() }
}

function Assert-TPMContractRegistryValidV1 {
    # The fail-closed guard: throws with every accumulated error if the
    # registry is not currently valid. Certification callers use this, not
    # Test-TPMContractRegistryIntegrityV1 directly, when the intended
    # behavior on failure is to stop rather than to report and continue.
    param([Parameter(Mandatory = $true)]$IntegrityResult)
    if ($IntegrityResult.Valid) { return }
    $messages = @($IntegrityResult.Errors | ForEach-Object { "$($_.ContractId): $($_.Message)" }) -join '; '
    throw "CONTRACT_REGISTRY_INVALID: $messages"
}

function Resolve-TPMEmulatorVersionMatchV1 {
    # Pure function: given a contract's VersionDetector and an already-extracted
    # observed version signal (e.g. a captured window-title string), computes
    # Matched | Compatible | Unknown | Diverged | Unsupported. Capturing the
    # signal itself (launching a process, reading a window title) is
    # environment-specific glue that belongs to the wiring step, not here.
    param([Parameter(Mandatory = $true)]$Contract, [AllowNull()][string]$ObservedVersionString)
    if ($Contract.ContractStatus -eq 'Deprecated' -or $Contract.ContractStatus -eq 'Superseded') { return 'Unsupported' }
    if ([string]::IsNullOrWhiteSpace($ObservedVersionString)) { return 'Unknown' }
    $pattern = $Contract.VersionDetector.Pattern
    $regexMatch = [regex]::Match($ObservedVersionString, $pattern)
    if (-not $regexMatch.Success) { return 'Unknown' }
    $captured = if ($regexMatch.Groups.Count -gt 1) { $regexMatch.Groups[1].Value } else { $regexMatch.Value }
    foreach ($entry in $Contract.VersionDetector.MatchedCommitMap) {
        if ($entry.VersionString -ceq $captured -or $entry.VersionString -ceq $ObservedVersionString) {
            if ($entry.Commit -ceq $Contract.UpstreamPinnedCommit) { return 'Matched' }
            return $entry.MatchState
        }
    }
    return 'Unknown'
}

function Assert-TPMOwnershipWriteAllowedV1 {
    # Enforces "TPM may not write emulator-owned state" at the point of use,
    # not merely at contract-authoring time. Any TPM code path that intends to
    # write emulator configuration must call this first and let it throw
    # before attempting the write.
    param([Parameter(Mandatory = $true)]$Contract, [Parameter(Mandatory = $true)][string]$SettingPath)
    $boundary = $Contract.OwnershipBoundaries | Where-Object { $_.SettingPath -ceq $SettingPath } | Select-Object -First 1
    if ($null -eq $boundary) { throw "OWNERSHIP_UNKNOWN: '$SettingPath' has no registered OwnershipBoundary in contract '$($Contract.ContractId)'" }
    if ($boundary.WritePolicy -eq 'NeverWrite') { throw "OWNERSHIP_VIOLATION: '$SettingPath' is Owner=$($boundary.Owner), WritePolicy=NeverWrite -- TPM must not write this" }
    if ($boundary.WritePolicy -eq 'WriteOnlyViaEmulatorMechanism') { throw "OWNERSHIP_VIOLATION: '$SettingPath' is Owner=$($boundary.Owner) -- TPM may only trigger the emulator's own mechanism, never hand-author this value" }
    return $boundary
}

function Resolve-TPMEnvironmentDataRootV1 {
    # Generic DataRootResolver interpreter. FileContentLiteral reads Source's
    # content (relative to InstallDir); empty content falls back to
    # DefaultValue. This is the only Method implemented so far -- FixedPath
    # and EnvironmentVariable are declared in the schema for future contracts
    # and are not yet exercised by any registered contract.
    param([Parameter(Mandatory = $true)]$Resolver, [Parameter(Mandatory = $true)][string]$InstallDir)
    switch ($Resolver.Method) {
        'FileContentLiteral' {
            $sourcePath = Join-Path $InstallDir $Resolver.Source
            $content = if (Test-Path -LiteralPath $sourcePath -PathType Leaf) { ([System.IO.File]::ReadAllText($sourcePath)).Trim() } else { '' }
            $leaf = if ([string]::IsNullOrWhiteSpace($content)) { $Resolver.DefaultValue } else { $content }
            return Join-Path $InstallDir $leaf
        }
        'FixedPath' { return Join-Path $InstallDir $Resolver.Source }
        default { throw "DATA_ROOT_RESOLVER_UNSUPPORTED: Method '$($Resolver.Method)' is declared but not yet implemented" }
    }
}

function Invoke-TPMEnvironmentInitializationActionV1 {
    # Generic InitializationAction interpreter. CliInvocation runs the
    # emulator's own executable with the contract-declared arguments and
    # waits for exit -- this never hand-authors configuration content; it
    # only ever triggers the emulator's own init mechanism.
    #
    # TimeoutSeconds is enforced here via Process.WaitForExit(ms) rather than
    # Start-Process -Wait, which blocks indefinitely with no timeout of its
    # own -- a hung or misbehaving emulator process must not be able to stall
    # the caller forever. A process that does not exit in time is killed and
    # this throws; it is never left running in the background.
    param([Parameter(Mandatory = $true)]$Action, [Parameter(Mandatory = $true)][string]$InstallDir)
    if ($Action.Method -eq 'None') { return [pscustomobject]@{ Invoked = $false; ExitCode = $null } }
    if ($Action.Method -ne 'CliInvocation') { throw "INITIALIZATION_ACTION_UNSUPPORTED: Method '$($Action.Method)' is declared but not yet implemented" }
    $exePath = Join-Path $InstallDir $Action.Command
    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) { throw "INITIALIZATION_ACTION_FAILED: executable not found at '$exePath'" }
    $startParameters = @{ FilePath = $exePath; WorkingDirectory = $InstallDir; PassThru = $true }`n    # Windows PowerShell 5.1 rejects an empty ArgumentList collection.`n    # Omit the parameter entirely when the contract declares no arguments.`n    if ($null -ne $Action.Arguments -and @($Action.Arguments).Count -gt 0) {`n        $startParameters.ArgumentList = @($Action.Arguments)`n    }`n    $proc = Start-Process @startParameters
    $timeoutMs = [int]([Math]::Max(1, $Action.TimeoutSeconds) * 1000)
    $exited = $proc.WaitForExit($timeoutMs)
    if (-not $exited) {
        $killError = $null
        try { $proc.Kill() } catch { $killError = $_.Exception.Message }

        $terminated = $false
        $waitError = $null
        try { $terminated = $proc.WaitForExit(5000) } catch { $waitError = $_.Exception.Message }
        if (-not $terminated) {
            $detail = if ($killError) { " Kill failed: $killError." } else { "" }
            if ($waitError) { $detail += " Termination check failed: $waitError." }
            throw "INITIALIZATION_ACTION_FAILED: process did not exit within $($Action.TimeoutSeconds)s and termination could not be confirmed.$detail"
        }
        if ($killError) {
            throw "INITIALIZATION_ACTION_FAILED: process exceeded TimeoutSeconds; Kill reported failure, although termination was subsequently confirmed: $killError"
        }
        throw "INITIALIZATION_ACTION_FAILED: process did not exit within $($Action.TimeoutSeconds)s and was terminated"
    }
    $timedExitCode = $proc.ExitCode
    if ($Action.ExpectedExitCodes -notcontains $timedExitCode) { throw "INITIALIZATION_ACTION_FAILED: exit code $timedExitCode not in expected set ($($Action.ExpectedExitCodes -join ', '))" }
    return [pscustomobject]@{ Invoked = $true; ExitCode = $timedExitCode }
}

function Test-TPMEnvironmentInitializedV1 {
    # Generic, read-only InitializedVerifier interpreter.
    param([Parameter(Mandatory = $true)]$Verifier, [Parameter(Mandatory = $true)][string]$DataRoot)
    foreach ($relativePath in $Verifier.RequiredPaths) {
        $fullPath = Join-Path $DataRoot $relativePath
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { return [pscustomobject]@{ Initialized = $false; Reason = "missing required path: $relativePath" } }
    }
    if ($Verifier.RequiredMarkers.Count -gt 0) {
        $primaryPath = Join-Path $DataRoot $Verifier.RequiredPaths[0]
        $content = [System.IO.File]::ReadAllText($primaryPath)
        foreach ($marker in $Verifier.RequiredMarkers) {
            # Literal substring match required -- markers routinely contain
            # "[" "]" (e.g. ini section headers like "[USB1]"), which -like/
            # -notlike would interpret as a wildcard character class rather
            # than literal brackets.
            if (-not $content.Contains($marker)) { return [pscustomobject]@{ Initialized = $false; Reason = "missing required marker: $marker" } }
        }
    }
    return [pscustomobject]@{ Initialized = $true; Reason = $null }
}

function Test-TPMRuntimeApplicabilityV1 {
    # Generic ApplicabilityPredicate evaluator: simple AND of equality checks
    # against a caller-supplied context (e.g. a TeknoParrot GameProfile's
    # relevant fields). No emulator-specific field names are known here.
    param([Parameter(Mandatory = $true)]$Predicate, [Parameter(Mandatory = $true)]$Context)
    $contextMap = Get-TPMValueMapV1 $Context
    foreach ($key in $Predicate.Keys) {
        if (-not $contextMap.Contains($key)) { return $false }
        if ("$($contextMap[$key])" -cne "$($Predicate[$key])") { return $false }
    }
    return $true
}

function Resolve-TPMObservableEvidenceV1 {
    # Generic runtime-evidence evaluator: walks ObservableEvidence entries in
    # Reliability order and returns the first Confirmed source's result.
    # Entries whose Status is Hypothesis/Unconfirmed are skipped -- a
    # candidate signal is never treated as authoritative until a contract
    # maintainer marks it Confirmed following real evidence.
    param([Parameter(Mandatory = $true)]$ObservableEvidence, [Parameter(Mandatory = $true)][hashtable]$Sources)
    $ordered = @($ObservableEvidence | Sort-Object Reliability)
    foreach ($entry in $ordered) {
        if ($entry.Status -ne 'Confirmed') { continue }
        switch ($entry.EvidenceSourceType) {
            'EmulatorLog' {
                if (-not $Sources.ContainsKey('LogPath')) { continue }
                $logPath = $Sources['LogPath']
                if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) { continue }
                $found = (Select-String -LiteralPath $logPath -Pattern $entry.Locator -Quiet -ErrorAction SilentlyContinue)
                return [pscustomobject]@{ Matched = [bool]$found; SourceUsed = $entry }
            }
            'IniSnapshot' {
                if (-not $Sources.ContainsKey('IniPath')) { continue }
                $iniPath = $Sources['IniPath']
                if (-not (Test-Path -LiteralPath $iniPath -PathType Leaf)) { continue }
                $found = (Select-String -LiteralPath $iniPath -Pattern ([regex]::Escape($entry.Locator)) -Quiet -ErrorAction SilentlyContinue)
                return [pscustomobject]@{ Matched = [bool]$found; SourceUsed = $entry }
            }
            default { continue }
        }
    }
    return [pscustomobject]@{ Matched = $false; SourceUsed = $null }
}

function Test-TPMEmulatorPresentV1 {
    # Generic PresenceDetector interpreter. PathExists is the only
    # non-invasive Method implemented -- it never launches anything, only
    # checks a relative path exists under InstallDir. WindowTitleRegex and
    # the other detector methods require actually running the emulator
    # (however briefly) to observe output, which read-only presence
    # detection must not do; callers needing those signals must capture
    # them separately (see Resolve-TPMEmulatorVersionMatchV1) and are
    # expected to treat 'not yet observed' as Unknown, never as absent.
    param([Parameter(Mandatory = $true)]$Detector, [Parameter(Mandatory = $true)][string]$InstallDir)
    switch ($Detector.Method) {
        'PathExists' { return (Test-Path -LiteralPath (Join-Path $InstallDir $Detector.Source)) }
        default { return $false }
    }
}

function Get-TPMEmulatorContractObservationsV1 {
    # The single, shared, read-only pass over every registered contract for
    # a given install root -- this is what both Shadow and Smoke call, so
    # neither reimplements its own copy of "walk contracts, check presence,
    # verify environment capability." Never invokes InitializationAction
    # (that is a repair action a caller must opt into explicitly and
    # separately) and never resolves VersionMatchState (that requires
    # launching the emulator, which observation collection must not do --
    # callers that have a captured version signal resolve it themselves via
    # Resolve-TPMEmulatorVersionMatchV1 and combine it with these
    # observations). RuntimeContexts, when supplied, only gets
    # applicability checked here; runtime evidence resolution needs a real
    # launch and is out of scope for this collector.
    param([Parameter(Mandatory = $true)][string]$InstallRoot, [object[]]$RuntimeContexts = @(), [string]$ContractsRoot)
    $integrity = if ([string]::IsNullOrWhiteSpace($ContractsRoot)) { Test-TPMContractRegistryIntegrityV1 } else { Test-TPMContractRegistryIntegrityV1 -ContractsRoot $ContractsRoot }
    if (-not $integrity.Valid) {
        return [pscustomobject]@{ RegistryValid = $false; Errors = $integrity.Errors; Observations = @() }
    }
    $observations = New-Object Collections.Generic.List[object]
    foreach ($entry in $integrity.Contracts) {
        $contract = $entry.Contract
        foreach ($cap in $contract.EnvironmentCapabilities) {
            $present = Test-TPMEmulatorPresentV1 -Detector $cap.PresenceDetector -InstallDir $InstallRoot
            $observation = [ordered]@{ ContractId = $contract.ContractId; CapabilityType = 'Environment'; CapabilityId = $cap.CapabilityId; Applicable = $present; CapabilityPassed = $false; DataRoot = $null; Reason = $null }
            if ($present) {
                $dataRoot = Resolve-TPMEnvironmentDataRootV1 -Resolver $cap.DataRootResolver -InstallDir $InstallRoot
                $verified = Test-TPMEnvironmentInitializedV1 -Verifier $cap.InitializedVerifier -DataRoot $dataRoot
                $observation.DataRoot = $dataRoot
                $observation.CapabilityPassed = $verified.Initialized
                $observation.Reason = $verified.Reason
            }
            $observations.Add([pscustomobject]$observation)
        }
        foreach ($cap in $contract.RuntimeCapabilities) {
            foreach ($context in $RuntimeContexts) {
                $applicable = Test-TPMRuntimeApplicabilityV1 -Predicate $cap.ApplicabilityPredicate -Context $context
                if (-not $applicable) { continue }
                $observations.Add([pscustomobject]@{ ContractId = $contract.ContractId; CapabilityType = 'Runtime'; CapabilityId = $cap.CapabilityId; Applicable = $true; CapabilityPassed = $false; DataRoot = $null; Reason = 'runtime evidence resolution requires a live launch; not performed by this read-only collector' })
            }
        }
    }
    return [pscustomobject]@{ RegistryValid = $true; Errors = @(); Observations = $observations.ToArray() }
}

Export-ModuleMember -Function Get-TPMContractsRootV1, ConvertFrom-TPMOrderedJsonV1, ConvertTo-TPMOrderedValueV1, `
    Assert-TPMEmulatorContractV1, Get-TPMRegisteredEmulatorContractsV1, Get-TPMEmulatorContractV1, `
    Get-TPMSupportedContractSchemaVersionsV1, Assert-TPMSupportedContractSchemaVersionV1, `
    Assert-TPMContractLocatorsResolveV1, Test-TPMContractRegistryIntegrityV1, Assert-TPMContractRegistryValidV1, `
    Resolve-TPMEmulatorVersionMatchV1, Assert-TPMOwnershipWriteAllowedV1, `
    Resolve-TPMEnvironmentDataRootV1, Invoke-TPMEnvironmentInitializationActionV1, Test-TPMEnvironmentInitializedV1, `
    Test-TPMRuntimeApplicabilityV1, Resolve-TPMObservableEvidenceV1, `
    Test-TPMEmulatorPresentV1, Get-TPMEmulatorContractObservationsV1
