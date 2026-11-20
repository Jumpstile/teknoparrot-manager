#Requires -Module Pester
# Controller capability contract (issue #303, docs/architecture/CONTROLLER_CAPABILITY_CONTRACT.md).
# What a user sees or loses: later controller features can only call a control ready or verified when real evidence says so,
# and a user's own choice of controller is never replaced by a guess. These tests check the contract file itself.
# What this CANNOT prove: schema validation needs PowerShell 7 (Windows PowerShell 5.1 has no Test-Json); on 5.1 only the text checks run.

# Test-Json needs PowerShell 7; this is decided while Pester discovers tests so -Skip can use it.
$testJsonCmd = Get-Command Test-Json -ErrorAction SilentlyContinue
$canValidate = [bool]($testJsonCmd -and $testJsonCmd.Parameters.ContainsKey('SchemaFile'))

BeforeAll {
    $script:schemaPath = Join-Path $PSScriptRoot '..\schemas\TpmControllerCapability.v1.schema.json'
    $script:schemaText = Get-Content -LiteralPath $script:schemaPath -Raw
    $script:schema = $script:schemaText | ConvertFrom-Json
    $script:hash = ('a' * 64)

    function New-ValidProfile {
        [ordered]@{
            ContractVersion   = 'TpmControllerCapability/v1'
            MinReaderVersion  = 1
            ProfileId         = 'xinput-p1'
            ProfileRevision   = 1
            ControllerContext = [ordered]@{ DeviceClass = 'XboxStylePad'; PlayerSlot = 'P1'; SelectionSource = 'UserSelected' }
            SemanticControls  = @(
                [ordered]@{ ControlId = 'P1Button1'; Kind = 'Button'; Meaning = 'Main action button'; Requirement = 'Required'; Bindable = $true; Scope = 'Player' },
                [ordered]@{ ControlId = 'Test'; Kind = 'Switch'; Meaning = 'Cabinet test switch'; Requirement = 'Optional'; Bindable = $true; Scope = 'Cabinet' }
            )
            Evidence          = [ordered]@{ Origin = 'TpmReviewed'; ReviewState = 'Reviewed'; ReviewedUtc = '2026-11-19T00:00:00Z' }
            GameContracts     = @([ordered]@{ GameProfileId = 'ExampleGame'; GameProfileHash = $script:hash; ContractRevision = 1 })
        }
    }
    function Test-Profile {
        param($Profile)
        $json = $Profile | ConvertTo-Json -Depth 8
        Test-Json -Json $json -SchemaFile $script:schemaPath -ErrorAction SilentlyContinue
    }
    function Test-ControlState {
        param($State)
        # Wrap the reusable status definition in a one-off root schema so it can be checked on its own.
        $wrapper = [ordered]@{ '$schema' = 'https://json-schema.org/draft/2020-12/schema'; '$ref' = '#/$defs/controlState'; '$defs' = $script:schema.'$defs' }
        $wrapperPath = Join-Path $TestDrive 'control-state.schema.json'
        $wrapper | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $wrapperPath -Encoding utf8
        Test-Json -Json ($State | ConvertTo-Json -Depth 4) -SchemaFile $wrapperPath -ErrorAction SilentlyContinue
    }
}

Describe 'TpmControllerCapability/v1 schema' {
    It 'is valid JSON with the expected version' {
        $script:schema.title | Should -Be 'TpmControllerCapability/v1'
        $script:schema.properties.ContractVersion.const | Should -Be 'TpmControllerCapability/v1'
    }

    It 'uses exactly the agreed status words' {
        ($script:schema.'$defs'.structuralStatus.enum -join ',') | Should -Be 'Complete,Partial,Missing,Unknown,Unsupported'
        ($script:schema.'$defs'.setupStatus.enum -join ',') | Should -Be 'NotRequired,CalibrationRequired,FirstRunRequired,Unknown'
        ($script:schema.'$defs'.verificationStatus.enum -join ',') | Should -Be 'NotVerified,Verified'
    }

    It 'has no TeknoParrot storage key names and no machine names' {
        $script:schemaText | Should -Not -CMatch 'JoystickButtons|InputMapping|BindName|UserProfiles|GameProfiles|\bARCADE\b|MEGATRON'
    }

    It 'rejects unknown fields on every object' {
        $script:schema.additionalProperties | Should -BeFalse
        foreach ($name in 'controllerContext', 'semanticControl', 'evidenceMetadata', 'gameContractIdentity', 'controlState') {
            $script:schema.'$defs'.$name.additionalProperties | Should -BeFalse -Because $name
        }
    }

    It 'accepts a valid XInput P1 profile' -Skip:(-not $canValidate) {
        Test-Profile (New-ValidProfile) | Should -BeTrue
    }

    It 'rejects a TeknoParrot-style storage key' -Skip:(-not $canValidate) {
        $p = New-ValidProfile
        $p['InputMapping'] = 'P1Button1'
        Test-Profile $p | Should -BeFalse
    }

    It 'rejects a suggestion with no evidence ID' -Skip:(-not $canValidate) {
        $p = New-ValidProfile
        $p.ControllerContext.SelectionSource = 'SuggestedByEvidence'
        Test-Profile $p | Should -BeFalse
        $p.ControllerContext['SuggestedFromEvidenceId'] = ('b' * 64)
        Test-Profile $p | Should -BeTrue
    }

    It 'rejects a game contract with no profile hash' -Skip:(-not $canValidate) {
        $p = New-ValidProfile
        $p.GameContracts = @([ordered]@{ GameProfileId = 'ExampleGame'; ContractRevision = 1 })
        Test-Profile $p | Should -BeFalse
    }

    It 'rejects Verified without evidence and accepts it with evidence' -Skip:(-not $canValidate) {
        $state = [ordered]@{ ControlId = 'P1Button1'; Structural = 'Complete'; Setup = 'NotRequired'; Verification = 'Verified' }
        Test-ControlState $state | Should -BeFalse
        $state['VerificationEvidenceId'] = ('c' * 64)
        Test-ControlState $state | Should -BeTrue
    }

    It 'rejects a status word that is not in the list' -Skip:(-not $canValidate) {
        $state = [ordered]@{ ControlId = 'P1Button1'; Structural = 'Ready'; Setup = 'NotRequired'; Verification = 'NotVerified' }
        Test-ControlState $state | Should -BeFalse
    }
}
