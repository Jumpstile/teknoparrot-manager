#Requires -Module Pester

# FIX110B (S-26): the published GameSupportContract schemas (V1, V1.1, V1.2; V1.3 reuses V1.2) accept a real CHD requirement.
#   Before: ChdDomain extended the closed Domain object with allOf. Domain forbids extra properties, so a CHD object that carried
#   Requirement / AllowedLocations / MultipleAllowed failed Domain, and one without them failed the extension. No CHD object passed.
#   Now: ChdRequirements is ONE closed object that lists the base fields and the CHD fields.
# The structural cases run in every PowerShell. The Test-Json cases need PowerShell 7 (Windows PowerShell 5.1 has no JSON Schema
# validator) and are skipped there. What this CANNOT prove: that the rest of each schema matches every field of an older contract
# version (only the CHD requirement and, with Test-Json, one generated 1.2 contract are checked).

BeforeDiscovery {
    $script:f110CanTestJson = $false
    $testJson = Get-Command Test-Json -ErrorAction SilentlyContinue
    if ($testJson -and $testJson.Parameters.ContainsKey('SchemaFile')) { $script:f110CanTestJson = $true }
}

BeforeAll {
    $script:f110RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:f110SchemaDirectory = Join-Path $script:f110RepoRoot 'contracts/_schema'
    Import-Module (Join-Path $script:f110RepoRoot 'scripts/TPMGameSupport.Contracts.psm1') -Force
    $script:f110ChdExtension = @('Requirement', 'AllowedLocations', 'MultipleAllowed')

    function Read-F110Schema {
        param([Parameter(Mandatory)][string]$FileName)
        [IO.File]::ReadAllText((Join-Path $script:f110SchemaDirectory $FileName)) | ConvertFrom-Json
    }
    function Get-F110ChdNode {
        param([Parameter(Mandatory)]$Schema)
        if ($Schema.PSObject.Properties['definitions'] -and $Schema.definitions.PSObject.Properties['ChdDomain']) { return $Schema.definitions.ChdDomain }
        return $Schema.properties.ChdRequirements
    }

    $script:f110Profile = [pscustomobject]@{
        ProfileCode = 'ChdSchemaFixture'
        ProfileFileName = 'ChdSchemaFixture.xml'
        GameTitle = 'Chd Schema Fixture'
        VariantTitle = ''
        EmulationProfile = 'TeknoParrotGame'
        EmulatorType = 'TeknoParrot'
        ProfileRevision = 1
        RequiresAdmin = $false
        SourcePath = 'GameProfiles/ChdSchemaFixture.xml'
        ProfileXmlSha256 = ('b' * 64)
        Executable = [pscustomobject]@{ PrimaryCandidates = @('fixture.exe'); SecondaryCandidates = @(); HasTwoExecutables = $false; LaunchSecondExecutableFirst = $false; SecondExecutableArguments = '' }
        PathRules = [pscustomobject]@{ GamePath = ''; GamePath2 = ''; ContentDirectories = @('content'); MediaDirectories = @('media') }
        Media = [pscustomobject]@{ ChdRequirement = 'REQUIRED'; RequiredExtensions = @('.chd'); MultipleChdAllowed = $true; MediaRuleEvidence = @('fixture-media-source') }
        Ownership = [pscustomobject]@{ TeknoParrotOwnedFields = @(); TpmReadableFields = @(); TpmWritableFields = @(); ManualTeknoParrotUiRequired = $false }
        ControllerEvidence = [pscustomobject]@{
            DefaultInputApi = 'DirectInput'
            AlternativeInputApis = @('XInput')
            Settings = @([ordered]@{ Name = 'Input API'; Value = 'DirectInput'; EvidenceRefs = @() })
            Controls = @([ordered]@{ ControlId = 'wheel-axis'; Name = 'Wheel Axis'; BindingTarget = 'Analog2'; AnalogType = 'Wheel'; ModeConditions = [ordered]@{}; EvidenceRefs = @() })
        }
        Classification = 'REVIEW_MANUAL'
        ReasonCode = 'OWNER_RUNTIME_REQUIRED'
        BeginnerAction = 'Review runtime evidence.'
        Evidence = [pscustomobject]@{ SourceIds = @('fixture-media-source'); ProfileSha256 = ('b' * 64); FixtureIds = @() }
    }
    $script:f110Contract = New-TPMGameSupportContractV1 -Profile $script:f110Profile -SnapshotId 'CHD-SCHEMA-SNAPSHOT' -CapturedAtUtc '2026-01-01T00:00:00Z'
}

Describe 'FIX110B S-26 CHD requirement schema shape' {
    It 'defines one closed CHD object with the base fields and the CHD fields (<File>)' -ForEach @(
        @{ File = 'GameSupportContractV1.schema.json' }
        @{ File = 'GameSupportContractV1.1.schema.json' }
        @{ File = 'GameSupportContractV1.2.schema.json' }
    ) {
        # Mutation: extend the closed Domain object with allOf again (no object can satisfy both halves).
        $schema = Read-F110Schema -FileName $File
        $chd = Get-F110ChdNode -Schema $schema
        $chd.PSObject.Properties['allOf'] | Should -BeNullOrEmpty
        $chd.type | Should -BeExactly 'object'
        $chd.additionalProperties | Should -BeFalse
        $domain = $schema.definitions.Domain
        $expectedProperties = @(@($domain.properties.PSObject.Properties.Name) + $script:f110ChdExtension | Sort-Object)
        $expectedRequired = @(@($domain.required) + $script:f110ChdExtension | Sort-Object)
        @($chd.properties.PSObject.Properties.Name | Sort-Object) | Should -Be $expectedProperties
        @($chd.required | Sort-Object) | Should -Be $expectedRequired
        foreach ($name in @($chd.required)) { @($chd.properties.PSObject.Properties.Name) | Should -Contain $name }
    }

    It 'keeps the CHD property reference chain V1.2 -> definition and V1.3 -> V1.2' {
        # Mutation: point V1.3 at the plain Domain definition; V1.3 would stop carrying the CHD fields.
        (Read-F110Schema -FileName 'GameSupportContractV1.2.schema.json').properties.ChdRequirements.'$ref' | Should -BeExactly '#/definitions/ChdDomain'
        (Read-F110Schema -FileName 'GameSupportContractV1.1.schema.json').properties.ChdRequirements.'$ref' | Should -BeExactly '#/definitions/ChdDomain'
        (Read-F110Schema -FileName 'GameSupportContractV1.3.schema.json').properties.ChdRequirements.'$ref' | Should -BeExactly 'GameSupportContractV1.2.schema.json#/properties/ChdRequirements'
    }

    It 'matches the exact field set of a generated contract CHD requirement' {
        # Mutation: add a field to the generator or drop one from the schema; the sets no longer match.
        $generated = @($script:f110Contract.ChdRequirements.Keys | Sort-Object)
        $chd = Get-F110ChdNode -Schema (Read-F110Schema -FileName 'GameSupportContractV1.2.schema.json')
        $generated | Should -Be @($chd.properties.PSObject.Properties.Name | Sort-Object)
        $generated | Should -Be @($chd.required | Sort-Object)
    }
}

Describe 'FIX110B S-26 CHD requirement validated with Test-Json' -Skip:(-not $script:f110CanTestJson) {
    BeforeAll {
        # One schema per file whose root only describes ChdRequirements, so the CHD definition is checked on its own for every version.
        function Test-F110ChdAgainst {
            param([Parameter(Mandatory)][string]$FileName, [Parameter(Mandatory)]$Chd)
            $schema = Read-F110Schema -FileName $FileName
            $schema.properties = [pscustomobject]@{ ChdRequirements = $schema.properties.ChdRequirements }
            $schema.required = @('ChdRequirements')
            $schema.PSObject.Properties.Remove('$id')
            $schemaPath = Join-Path $TestDrive ('chd-only-' + $FileName)
            [IO.File]::WriteAllText($schemaPath, ($schema | ConvertTo-Json -Depth 40), (New-Object System.Text.UTF8Encoding($false)))
            $instance = ([pscustomobject]@{ ChdRequirements = $Chd } | ConvertTo-Json -Depth 20)
            return [bool](Test-Json -Json $instance -SchemaFile $schemaPath -ErrorAction SilentlyContinue)
        }
        function Copy-F110Chd { return ($script:f110Contract.ChdRequirements | ConvertTo-Json -Depth 20 | ConvertFrom-Json) }
    }

    It 'accepts a generated CHD requirement and rejects a missing or extra CHD field (<File>)' -ForEach @(
        @{ File = 'GameSupportContractV1.schema.json' }
        @{ File = 'GameSupportContractV1.1.schema.json' }
        @{ File = 'GameSupportContractV1.2.schema.json' }
    ) {
        # Mutation: restore the allOf extension of the closed Domain; the first assertion fails because no object passes.
        Test-F110ChdAgainst -FileName $File -Chd (Copy-F110Chd) | Should -BeTrue
        $missing = Copy-F110Chd
        $missing.PSObject.Properties.Remove('MultipleAllowed')
        Test-F110ChdAgainst -FileName $File -Chd $missing | Should -BeFalse
        $extra = Copy-F110Chd
        $extra | Add-Member -NotePropertyName 'Unexpected' -NotePropertyValue 'x'
        Test-F110ChdAgainst -FileName $File -Chd $extra | Should -BeFalse
    }

    It 'accepts a whole generated 1.2 contract' {
        # Mutation: any schema defect on the generated shape (for example the CHD requirement) makes the real contract invalid.
        $json = $script:f110Contract | ConvertTo-Json -Depth 40
        Test-Json -Json $json -SchemaFile (Join-Path $script:f110SchemaDirectory 'GameSupportContractV1.2.schema.json') | Should -BeTrue
    }
}
