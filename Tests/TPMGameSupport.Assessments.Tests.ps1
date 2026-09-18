BeforeAll {
    $contractsModule = Join-Path $PSScriptRoot '..\scripts\TPMGameSupport.Contracts.psm1'
    $assessmentsModule = Join-Path $PSScriptRoot '..\scripts\TPMGameSupport.Assessments.psm1'
    Import-Module $contractsModule -Force
    Import-Module $assessmentsModule -Force
    $profile = [pscustomobject]@{
        ProfileCode = 'OutRunAssessment'
        ProfileFileName = 'OutRunAssessment.xml'
        GameTitle = 'OutRun Assessment'
        VariantTitle = ''
        EmulationProfile = 'cxbxr'
        EmulatorType = 'cxbxr'
        ProfileRevision = 3
        RequiresAdmin = $false
        SourcePath = 'GameProfiles/OutRunAssessment.xml'
        ProfileXmlSha256 = ('a' * 64)
        Executable = [pscustomobject]@{ PrimaryCandidates = @('outrun2.xbe'); SecondaryCandidates = @(); HasTwoExecutables = $false; LaunchSecondExecutableFirst = $false; SecondExecutableArguments = '' }
        PathRules = [pscustomobject]@{ GamePath = ''; GamePath2 = ''; ContentDirectories = @(); MediaDirectories = @() }
        Media = [pscustomobject]@{ ChdRequirement = 'UNKNOWN'; RequiredExtensions = @(); MultipleChdAllowed = $false; MediaRuleEvidence = @() }
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
        Evidence = [pscustomobject]@{ SourceIds = @('assessment-source'); ProfileSha256 = ('a' * 64); FixtureIds = @() }
    }
    $contract = New-TPMGameSupportContractV1 -Profile $profile -SnapshotId 'ASSESSMENT-SNAPSHOT' -CapturedAtUtc '2026-01-01T00:00:00Z'
    $assessment = New-TPMGameSupportAssessmentV1 -Contract $contract -EvaluatedAtUtc '2026-01-02T00:00:00Z' -TargetIdentity 'fixture-target'
}

Describe 'GameSupportAssessmentV1' {
    It 'binds to the immutable 1.2 contract snapshot' {
        $assessment.ContractId | Should -Be $contract.ContractId
        $assessment.ContractSchemaVersion | Should -Be '1.2.0'
        $assessment.ContractSnapshotId | Should -Be $contract.SnapshotId
        (Test-TPMGameSupportAssessmentV1 -Assessment $assessment -Contract $contract).Valid | Should -BeTrue
    }

    It 'represents presence, path, and hash states orthogonally' {
        $copy = ConvertFrom-Json (($assessment | ConvertTo-Json -Depth 30))
        foreach ($supportItem in @($copy.SupportFiles.Items)) {
            $supportItem.PresenceState = 'PRESENT'
            $supportItem.PathState = 'MATCHED'
            $supportItem.HashState = 'NOT_DECLARED'
            $supportItem.RequirementStatus = 'SATISFIED'
        }
        $item = $copy.SupportFiles.Items[0]
        $copy.SupportFiles.Overall = 'READY'
        (Test-TPMGameSupportAssessmentV1 -Assessment $copy -Contract $contract).Valid | Should -BeTrue
        $item.PresenceState | Should -Be 'PRESENT'
        $item.PathState | Should -Be 'MATCHED'
        $item.HashState | Should -Be 'NOT_DECLARED'
    }

    It 'accepts a verified hash without collapsing presence or path state' {
        $copy = ConvertFrom-Json (($assessment | ConvertTo-Json -Depth 30))
        foreach ($supportItem in @($copy.SupportFiles.Items)) {
            $supportItem.PresenceState = 'PRESENT'; $supportItem.PathState = 'MATCHED'; $supportItem.HashState = 'VERIFIED'; $supportItem.RequirementStatus = 'SATISFIED'
        }
        $copy.SupportFiles.Overall = 'READY'
        (Test-TPMGameSupportAssessmentV1 -Assessment $copy -Contract $contract).Valid | Should -BeTrue
    }
    It 'blocks a required missing file independently' {
        $copy = ConvertFrom-Json (($assessment | ConvertTo-Json -Depth 30))
        foreach ($supportItem in @($copy.SupportFiles.Items)) {
            $supportItem.PresenceState = 'PRESENT'; $supportItem.PathState = 'MATCHED'; $supportItem.HashState = 'NOT_DECLARED'; $supportItem.RequirementStatus = 'SATISFIED'
        }
        $item = $copy.SupportFiles.Items[0]
        $item.PresenceState = 'MISSING'; $item.PathState = 'NOT_EVALUATED'; $item.HashState = 'NOT_EVALUATED'; $item.RequirementStatus = 'BLOCKED'
        $copy.SupportFiles.Overall = 'BLOCKED'
        (Test-TPMGameSupportAssessmentV1 -Assessment $copy -Contract $contract).Valid | Should -BeTrue
    }

    It 'keeps path mismatch independent from presence and hash' {
        $copy = ConvertFrom-Json (($assessment | ConvertTo-Json -Depth 30))
        foreach ($supportItem in @($copy.SupportFiles.Items)) {
            $supportItem.PresenceState = 'PRESENT'; $supportItem.PathState = 'MATCHED'; $supportItem.HashState = 'NOT_DECLARED'; $supportItem.RequirementStatus = 'SATISFIED'
        }
        $item = $copy.SupportFiles.Items[0]
        $item.PresenceState = 'PRESENT'; $item.PathState = 'MISMATCHED'; $item.HashState = 'NOT_DECLARED'; $item.RequirementStatus = 'BLOCKED'
        $copy.SupportFiles.Overall = 'BLOCKED'
        (Test-TPMGameSupportAssessmentV1 -Assessment $copy -Contract $contract).Valid | Should -BeTrue
    }

    It 'rejects stale contract snapshots' {
        $copy = ConvertFrom-Json (($assessment | ConvertTo-Json -Depth 30))
        $copy.ContractSnapshotId = 'STALE-SNAPSHOT'
        (Test-TPMGameSupportAssessmentV1 -Assessment $copy -Contract $contract).Valid | Should -BeFalse
    }

    It 'does not equate successful launch with verified controls' {
        $copy = ConvertFrom-Json (($assessment | ConvertTo-Json -Depth 30))
        foreach ($supportItem in @($copy.SupportFiles.Items)) {
            $supportItem.PresenceState = 'PRESENT'; $supportItem.PathState = 'MATCHED'; $supportItem.HashState = 'NOT_DECLARED'; $supportItem.RequirementStatus = 'SATISFIED'
        }
        $copy.SupportFiles.Overall = 'READY'
        $copy.Launch.Readiness = 'READY'; $copy.Launch.Observation = 'SUCCESS_OBSERVED'
        $copy.Controls.Readiness = 'NOT_VERIFIED'; $copy.Controls.Observation = 'INPUT_NOT_DELIVERED'
        (Test-TPMGameSupportAssessmentV1 -Assessment $copy -Contract $contract).Valid | Should -BeTrue
        $copy.Launch.Observation | Should -Be 'SUCCESS_OBSERVED'
        $copy.Controls.Readiness | Should -Be 'NOT_VERIFIED'
    }

    It 'writes only the assessment artifact and leaves the contract unchanged' {
        $before = $contract | ConvertTo-Json -Depth 30
        $path = Join-Path $TestDrive 'assessment.json'
        Write-TPMGameSupportAssessmentV1 -Assessment $assessment -Contract $contract -Path $path
        Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
        ($contract | ConvertTo-Json -Depth 30) | Should -Be $before
    }
}
