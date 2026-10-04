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

Describe 'GameSupportAssessmentV1.1 external software' {
    BeforeAll {
        $showdownProfile = ConvertFrom-Json ($profile | ConvertTo-Json -Depth 30)
        $showdownProfile.ProfileCode = 'Showdown'
        $showdownProfile.ProfileFileName = 'Showdown.xml'
        $showdownProfile.GameTitle = 'Showdown'
        $showdownProfile.EmulationProfile = 'GRID'
        $showdownProfile.EmulatorType = 'TeknoParrot'
        $showdownProfile | Add-Member -NotePropertyName SetupEvidence -NotePropertyValue ([pscustomobject]@{ Available = $true; RelativePath = 'GameSetup' })
        $showdownContract = New-TPMGameSupportContractV13 -Profile $showdownProfile -SnapshotId 'ASSESSMENT-EXTERNAL-SNAPSHOT' -CapturedAtUtc '2026-01-01T00:00:00Z'
        $showdownAssessment = New-TPMGameSupportAssessmentV11 -Contract $showdownContract -EvaluatedAtUtc '2026-01-02T00:00:00Z' -TargetIdentity 'showdown-fixture'
    }

    It 'emits an unevaluated Showdown assessment without fabricating runtime observations' {
        $showdownAssessment.SchemaVersion | Should -Be '1.1.0'
        $showdownAssessment.ContractSchemaVersion | Should -Be '1.3.0'
        $showdownAssessment.ExternalSoftware.Overall | Should -Be 'NOT_EVALUATED'
        $item = $showdownAssessment.ExternalSoftware.Items[0]
        $item.RequirementStatus | Should -Be 'NOT_EVALUATED'
        $item.InstalledState | Should -Be 'NOT_EVALUATED'
        $item.VersionState | Should -Be 'NOT_DECLARED'
        $item.ArchitectureState | Should -Be 'NOT_EVALUATED'
        $item.SourceState | Should -Be 'NOT_EVALUATED'
        $item.HashState | Should -Be 'NOT_DECLARED'
        $item.ObservedInstallPath | Should -BeNullOrEmpty
        $item.ObservedVersion | Should -BeNullOrEmpty
        $item.ObservedArchitecture | Should -BeNullOrEmpty
        $item.ObservedSource | Should -BeNullOrEmpty
        $item.ObservedSha256 | Should -BeNullOrEmpty
        @($item.EvidenceRefs).Count | Should -Be 0
        (Test-TPMGameSupportAssessmentV1 -Assessment $showdownAssessment -Contract $showdownContract).Valid | Should -BeTrue
    }

    It 'blocks a required external dependency when absent' {
        $copy = ConvertFrom-Json ($showdownAssessment | ConvertTo-Json -Depth 40)
        $copy.ExternalSoftware.Items[0].InstalledState = 'ABSENT'
        $copy.ExternalSoftware.Items[0].RequirementStatus = 'BLOCKED'
        $copy.ExternalSoftware.Overall = 'BLOCKED'
        (Test-TPMGameSupportAssessmentV1 -Assessment $copy -Contract $showdownContract).Valid | Should -BeTrue
    }

    It 'keeps a present but unverified dependency in review' {
        $copy = ConvertFrom-Json ($showdownAssessment | ConvertTo-Json -Depth 40)
        $copy.ExternalSoftware.Items[0].InstalledState = 'PRESENT'
        $copy.ExternalSoftware.Items[0].SourceState = 'UNVERIFIED'
        $copy.ExternalSoftware.Items[0].RequirementStatus = 'REVIEW'
        $copy.ExternalSoftware.Overall = 'REVIEW'
        (Test-TPMGameSupportAssessmentV1 -Assessment $copy -Contract $showdownContract).Valid | Should -BeTrue
    }

    It 'allows a fully verified dependency to become satisfied without a hash declaration' {
        $copy = ConvertFrom-Json ($showdownAssessment | ConvertTo-Json -Depth 40)
        $item = $copy.ExternalSoftware.Items[0]
        $item.InstalledState = 'PRESENT'
        $item.VersionState = 'NOT_DECLARED'
        $item.ArchitectureState = 'NOT_APPLICABLE'
        $item.SourceState = 'VERIFIED'
        $item.HashState = 'NOT_DECLARED'
        $item.RequirementStatus = 'SATISFIED'
        $copy.ExternalSoftware.Overall = 'SATISFIED'
        (Test-TPMGameSupportAssessmentV1 -Assessment $copy -Contract $showdownContract).Valid | Should -BeTrue
    }

    It 'blocks a required dependency with a mismatched version' {
        $copy = ConvertFrom-Json ($showdownAssessment | ConvertTo-Json -Depth 40)
        $copy.ExternalSoftware.Items[0].InstalledState = 'PRESENT'
        $copy.ExternalSoftware.Items[0].VersionState = 'MISMATCHED'
        $copy.ExternalSoftware.Items[0].RequirementStatus = 'BLOCKED'
        $copy.ExternalSoftware.Overall = 'BLOCKED'
        (Test-TPMGameSupportAssessmentV1 -Assessment $copy -Contract $showdownContract).Valid | Should -BeTrue
    }

    It 'rejects unsupported assessment versions and stale external bindings' {
        $unsupported = ConvertFrom-Json ($showdownAssessment | ConvertTo-Json -Depth 40)
        $unsupported.SchemaVersion = '9.9.9'
        (Test-TPMGameSupportAssessmentV1 -Assessment $unsupported -Contract $showdownContract).Valid | Should -BeFalse
        $stale = ConvertFrom-Json ($showdownAssessment | ConvertTo-Json -Depth 40)
        $stale.ContractSnapshotId = 'STALE'
        (Test-TPMGameSupportAssessmentV1 -Assessment $stale -Contract $showdownContract).Valid | Should -BeFalse
    }
    It 'fails closed for unsupported assessment and contract version combinations' {
        $v11WithV12Contract = ConvertFrom-Json ($showdownAssessment | ConvertTo-Json -Depth 40)
        $v11WithV12Contract.ContractSchemaVersion = '1.2.0'
        (Test-TPMGameSupportAssessmentV1 -Assessment $v11WithV12Contract -Contract $contract).Valid | Should -BeFalse

        $v10WithV13Contract = ConvertFrom-Json ($assessment | ConvertTo-Json -Depth 40)
        (Test-TPMGameSupportAssessmentV1 -Assessment $v10WithV13Contract -Contract $showdownContract).Valid | Should -BeFalse
    }

    It 'keeps the immutable 1.0 assessment path valid' {
        $assessment.ContractSchemaVersion | Should -Be '1.2.0'
        (Test-TPMGameSupportAssessmentV1 -Assessment $assessment -Contract $contract).Valid | Should -BeTrue
    }
}
