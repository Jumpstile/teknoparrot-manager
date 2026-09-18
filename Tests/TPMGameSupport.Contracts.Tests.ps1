BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\scripts\TPMGameSupport.Contracts.psm1'
    Import-Module $modulePath -Force

    function New-TestGameSupportProfile {
        param([string]$ProfileCode = 'RidgeRacer')
        [pscustomobject]@{
            ProfileCode = $ProfileCode
            ProfileFileName = ($ProfileCode + '.xml')
            GameTitle = 'Test ' + $ProfileCode
            VariantTitle = ''
            EmulationProfile = 'Raw'
            EmulatorType = 'Raw'
            Executable = [pscustomobject]@{
                PrimaryCandidates = @('game.exe')
                SecondaryCandidates = @('config.exe')
                HasTwoExecutables = $true
                LaunchSecondExecutableFirst = $true
                SecondExecutableArguments = '--boot'
            }
            PathRules = [pscustomobject]@{
                ContentDirectories = @('content')
                MediaDirectories = @('media')
            }
            Media = [pscustomobject]@{
                ChdRequirement = 'REQUIRED'
                RequiredExtensions = @('.bin', '.dat')
                MultipleChdAllowed = $false
                MediaRuleEvidence = @('fixture:CHD_PLUS_EXECUTABLE_SAME_FOLDER')
            }
            Ownership = [pscustomobject]@{
                TeknoParrotOwnedFields = @('GameProfile')
                TpmReadableFields = @('GameProfile')
                TpmWritableFields = @('UserProfile')
                ManualTeknoParrotUiRequired = $true
            }
            Classification = 'REVIEW_MANUAL'
            ReasonCode = 'CHD_REQUIRED'
            BeginnerAction = 'Select the game media in TeknoParrotUI.'
            Evidence = [pscustomobject]@{
                SourceIds = @('installed-profile-fixture')
                ProfileSha256 = 'abc123'
                FixtureIds = @('fixture-1')
            }
        }
    }

    $registry = New-TPMGameSupportContractRegistryV1 -Profiles @(
        (New-TestGameSupportProfile -ProfileCode 'RidgeRacer'),
        (New-TestGameSupportProfile -ProfileCode 'TimeCrisis')
    ) -SnapshotId 'TPM-SUPPORT-TEST' -CapturedAtUtc '2026-01-01T00:00:00Z'
}

Describe 'TPM game support contracts' {
    It 'creates one validated contract per profile' {
        $validation = Test-TPMGameSupportContractRegistryV1 -Registry $registry
        $validation.Valid | Should -BeTrue
        $registry.ContractCount | Should -Be 2
        @($registry.Contracts).Count | Should -Be 2
        @($registry.Contracts | Where-Object { $_.ContractStatus -eq 'DECLARED' -and $_.StaticEvidenceLevel -eq 'SOURCE_VERIFIED' }).Count | Should -Be 2
    }

    It 'maps executable, media, CHD, ownership, and setup evidence' {
        $contract = Get-TPMGameSupportContractV1 -Registry $registry -ProfileCode 'ridgeracer'
        $contract.LaunchExecutables.Primary | Should -Contain 'game.exe'
        $contract.LaunchExecutables.LaunchSecondExecutableFirst | Should -BeTrue
        $contract.MediaRequirements.Items | Should -Contain '.bin'
        $contract.ChdRequirements.Status | Should -Be 'DECLARED'
        $contract.ChdRequirements.AllowedLocations | Should -Contain 'content'
        $contract.TeknoParrotUiOwnership.RequiredUserSelection | Should -BeTrue
        $contract.SetupPolicy.Automation | Should -Be 'MANUAL'
    }

    It 'does not infer unsupported optional domains' {
        $contract = Get-TPMGameSupportContractV1 -Registry $registry -ProfileCode 'TimeCrisis'
        foreach ($name in @('RequiredPatches', 'ShaderFixes', 'BepInExRequirements', 'DgVoodoo2Requirements', 'ReShadeCompatibility', 'CrosshairCompatibility', 'ForceFeedbackCompatibility', 'GpuLimitations', 'KnownRuntimeFixes')) {
            $contract.$name.Status | Should -Be 'NOT_DECLARED'
            @($contract.$name.Items).Count | Should -Be 0
        }
    }

    It 'rejects duplicate profile identities' {
        $duplicate = New-TPMGameSupportContractRegistryV1 -Profiles @(
            (New-TestGameSupportProfile -ProfileCode 'Duplicate'),
            (New-TestGameSupportProfile -ProfileCode 'Other')
        ) -SnapshotId 'TPM-SUPPORT-TEST' -CapturedAtUtc '2026-01-01T00:00:00Z'
        $duplicate.Contracts[1].ProfileCode = 'Duplicate'
        $validation = Test-TPMGameSupportContractRegistryV1 -Registry $duplicate
        $validation.Valid | Should -BeFalse
        $validation.Errors -join ';' | Should -Match 'duplicate ProfileCode'
    }

    It 'round trips through the authoritative loader' {
        $path = Join-Path $TestDrive 'game-support-contracts.json'
        Write-TPMGameSupportContractRegistryV1 -Registry $registry -Path $path
        $loaded = Get-TPMGameSupportContractRegistryV1 -Path $path
        $loaded.SnapshotId | Should -Be 'TPM-SUPPORT-TEST'
        (Get-TPMGameSupportContractV1 -Registry $loaded -ProfileCode 'TIMECRISIS').ContractId | Should -Be 'game-timecrisis'
    }

    It 'generates a registry from a support posture JSON file' {
        $posturePath = Join-Path $TestDrive 'support-posture.json'
        $outputPath = Join-Path $TestDrive 'generated-contracts.json'
        [IO.File]::WriteAllText($posturePath, ([ordered]@{
            SnapshotId = 'TPM-SUPPORT-GENERATOR'
            CapturedAtUtc = '2026-01-01T00:00:00Z'
            Profiles = @((New-TestGameSupportProfile -ProfileCode 'GeneratorProfile'))
        } | ConvertTo-Json -Depth 16))
        $generator = Join-Path $PSScriptRoot '..\scripts\New-TpmGameSupportContracts.ps1'
        $result = & $generator -SupportPosturePath $posturePath -OutputPath $outputPath
        $result.ContractCount | Should -Be 1
        $loaded = Get-TPMGameSupportContractRegistryV1 -Path $outputPath
        $loaded.SnapshotId | Should -Be 'TPM-SUPPORT-GENERATOR'
        $loaded.Contracts[0].ProfileCode | Should -Be 'GeneratorProfile'
    }
    It 'routes and validates immutable 1.1 contracts without changing the 1.2 path' {
        $legacyNames = @(
            'ContractId','SchemaVersion','ProfileCode','ProfileFileName','DisplayName','VariantTitle','ProfileRevision',
            'EmulationProfile','EmulatorType','SnapshotId','CapturedAtUtc','ContractStatus','EvidenceConfidence',
            'ReleasePosture','AutomationAllowed','ClassificationReason','EvidenceGaps','LaunchExecutables',
            'MediaRequirements','ChdRequirements','RequiredFixes','RecommendedFixes','OptionalFixes',
            'KnownIncompatibleFixes','UserOwnedContentRequirements','TeknoParrotUiOwnedSettingRequirements',
            'RuntimeValidationRequirements','RequiredPatches','ShaderFixes','BepInExRequirements','DgVoodoo2Requirements',
            'ReShadeCompatibility','CrosshairCompatibility','ForceFeedbackCompatibility','GpuLimitations',
            'KnownRuntimeFixes','TeknoParrotUiOwnership','SetupPolicy','RuntimeValidation','Evidence'
        )
        $legacy = [ordered]@{}
        foreach ($name in $legacyNames) { $legacy[$name] = $registry.Contracts[0][$name] }
        $legacy.SchemaVersion = '1.1.0'
        $legacy.EvidenceConfidence = 'SourceVerified'
        $legacy.AutomationAllowed = $false
        $legacy.SetupPolicy = [ordered]@{
            Automation = 'MANUAL'
            Classification = $legacy.ReleasePosture
            ReleasePosture = $legacy.ReleasePosture
            AutomationAllowed = $false
            ReasonCode = 'CHD_REQUIRED'
            BeginnerAction = 'Select the game media in TeknoParrotUI.'
        }
        $legacy.RuntimeValidation = [ordered]@{ Status = 'NOT_RUN'; Required = $true; Rules = @(); Evidence = @() }
        $legacy.Evidence = [ordered]@{
            SourceIds = @('installed-profile-fixture')
            ProfileFileName = $legacy.ProfileFileName
            ProfileXmlSha256 = 'abc123'
            ProfileSourcePath = 'fixture/GameProfiles/RidgeRacer.xml'
            Setup = [ordered]@{}
            Metadata = [ordered]@{}
            FixtureIds = @('fixture-1')
        }
        $contractValidation = Test-TPMGameSupportContractV1 -Contract $legacy
        $contractValidation.Valid | Should -BeTrue
        $legacyRegistry = [ordered]@{
            RegistryId = 'TPM-GAME-SUPPORT-CONTRACTS'
            SchemaVersion = '1.1.0'
            SnapshotId = 'TPM-SUPPORT-TEST'
            CapturedAtUtc = '2026-01-01T00:00:00Z'
            Source = $registry.Source
            ExpectedProfileCount = 1
            ContractCount = 1
            ClassificationTotals = $registry.ClassificationTotals
            ReleaseGate = $registry.ReleaseGate
            Contracts = @($legacy)
        }
        (Test-TPMGameSupportContractRegistryV1 -Registry $legacyRegistry).Valid | Should -BeTrue
        (Test-TPMGameSupportContractRegistryV1 -Registry $registry).Valid | Should -BeTrue
    }

    It 'derives cxbxr support files only for matching backends' {
        $profile = New-TestGameSupportProfile -ProfileCode 'CxbxrProfile'
        $profile.EmulatorType = 'cxbxr'
        $profile.EmulationProfile = 'cxbxr'
        $profile | Add-Member -NotePropertyName ControllerEvidence -NotePropertyValue ([pscustomobject]@{
            DefaultInputApi = 'DirectInput'
            AlternativeInputApis = @('XInput')
            Settings = @([ordered]@{ Name = 'Input API'; Value = 'DirectInput'; EvidenceRefs = @('fixture-controller') })
            Controls = @([ordered]@{ ControlId = 'wheel-axis'; Name = 'Wheel Axis'; BindingTarget = 'Analog2'; AnalogType = 'Wheel'; ModeConditions = [ordered]@{}; EvidenceRefs = @('fixture-controller') })
        })
        $generated = New-TPMGameSupportContractRegistryV1 -Profiles @($profile) -SnapshotId 'TPM-CXBXR-TEST' -CapturedAtUtc '2026-01-01T00:00:00Z'
        $contract = $generated.Contracts[0]
        $contract.Prerequisites.SupportFiles.DeclarationState | Should -Be 'DECLARED'
        @($contract.Prerequisites.SupportFiles.Items).Count | Should -Be 4
        @($contract.Prerequisites.SupportFiles.Items | ForEach-Object { $_['FileName'] }) | Should -Be @('ic10_g24lc64.bin','pc20_g24lc64.bin','ic11_24lc024.bin','fpr21042_m29w160et.bin')
        $contract.Prerequisites.Controllers.RequirementState | Should -Be 'REQUIRED'
        $contract.Prerequisites.Controllers.InputApis.DefaultInputApi | Should -Be 'DIRECTINPUT'
        $contract.Prerequisites.Controllers.InputApis.AlternativeInputApis | Should -Contain 'XINPUT'
        $contract.Prerequisites.Controllers.EmulatorBackend.ControlTransport | Should -Be 'UNKNOWN'
        $audit = @($generated.BackendDerivationAudit)[0]
        $audit['MatchedCount'] | Should -Be 1
        $audit['MatchedProfileCodes'] | Should -Contain 'CxbxrProfile'
    }

}

Describe 'TPM catalog-wide game support contracts' {
    BeforeAll {
        $catalogRoot = Join-Path $TestDrive 'pinned-catalog'
        $catalogProfiles = Join-Path $catalogRoot 'GameProfiles'
        [void][System.IO.Directory]::CreateDirectory($catalogProfiles)
        for ($i = 1; $i -le 693; $i++) {
            $code = 'CatalogProfile{0:d4}' -f $i
            $xml = '<GameProfile><GameProfileRevision>1</GameProfileRevision><EmulationProfile>Raw</EmulationProfile><EmulatorType>Raw</EmulatorType><ExecutableName>{0}.exe</ExecutableName></GameProfile>' -f $code
            [System.IO.File]::WriteAllText((Join-Path $catalogProfiles ($code + '.xml')), $xml)
        }
        [System.IO.File]::WriteAllText((Join-Path $catalogProfiles 'Hummer.xml'), '<GameProfile><GameProfileRevision>13</GameProfileRevision><EmulationProfile>HummerExtreme</EmulationProfile><EmulatorType>ElfLdr2</EmulatorType><ExecutableName>a.elf</ExecutableName></GameProfile>')
        [System.IO.File]::WriteAllText((Join-Path $catalogProfiles 'hummerextreme.xml'), '<GameProfile><GameProfileRevision>14</GameProfileRevision><EmulationProfile>HummerExtreme</EmulationProfile><EmulatorType>ElfLdr2</EmulatorType><ExecutableName>hummer_Master.elf</ExecutableName></GameProfile>')
        $catalogOutput = Join-Path $TestDrive 'pinned-catalog-output'
        $supportScript = Join-Path $PSScriptRoot '..\scripts\New-TpmSupportPostureCorpus.ps1'
        . $supportScript
        Invoke-TpmSupportPostureCorpus -UpstreamProfileRoot $catalogProfiles -UpstreamCommitSha '5880e019016c5c3a0576e97a6c2a7f14bf54e3d1' -SnapshotId 'TPM-CATALOG-TEST' -CapturedAtUtc '2026-01-01T00:00:00Z' -OutputRoot $catalogOutput | Out-Null
        $catalogRegistry = Get-Content -LiteralPath (Join-Path $catalogOutput 'game-support-contracts.json') -Raw | ConvertFrom-Json
        $catalogModel = Get-Content -LiteralPath (Join-Path $catalogOutput 'support-posture.json') -Raw | ConvertFrom-Json
    }

    It 'generates exactly one contract for every pinned catalog profile' {
        $catalogRegistry.ContractCount | Should -Be 695
        @($catalogRegistry.Contracts).Count | Should -Be 695
        @($catalogRegistry.Contracts | Select-Object -ExpandProperty ProfileCode -Unique).Count | Should -Be 695
        $catalogRegistry.ExpectedProfileCount | Should -Be 695
        $catalogRegistry.ReleaseGate.ZeroUnclassified | Should -BeTrue
        $catalogRegistry.ReleaseGate.ProfileCountMatches | Should -BeTrue
        @($catalogRegistry.Contracts | Where-Object { [string]::IsNullOrWhiteSpace($_.ClassificationReason) }).Count | Should -Be 0
        @($catalogRegistry.Contracts | Where-Object { [string]::IsNullOrWhiteSpace($_.Evidence.ProfileXmlSha256) }).Count | Should -Be 0
    }

    It 'keeps Hummer and Hummer Extreme as manual-review seed records' {
        $hummer = @($catalogRegistry.Contracts | Where-Object { $_.ProfileCode -ieq 'Hummer' })[0]
        $extreme = @($catalogRegistry.Contracts | Where-Object { $_.ProfileCode -ieq 'hummerextreme' })[0]
        $hummer.ProfileRevision | Should -Be 13
        $hummer.LaunchExecutables.Primary | Should -Contain 'a.elf'
        $hummer.ReleasePosture | Should -Be 'REVIEW_MANUAL'
        $hummer.SetupPolicy.Automation | Should -Be 'MANUAL'
        $extreme.ProfileRevision | Should -Be 14
        $extreme.LaunchExecutables.Primary | Should -Contain 'hummer_Master.elf'
        $extreme.ReleasePosture | Should -Be 'REVIEW_MANUAL'
        $extreme.SetupPolicy.Automation | Should -Be 'MANUAL'
    }

    It 'does not convert vendor WITH_FIX metadata into a required patch' {
        $profile = New-TestGameSupportProfile -ProfileCode 'WithFixMetadata'
        $profile | Add-Member -NotePropertyName MetadataEvidence -NotePropertyValue ([pscustomobject]@{ Available = $true; VendorStatuses = [pscustomobject]@{ nvidia = 'WITH_FIX'; amd = 'WITH_FIX'; intel = 'WITH_FIX' } })
        $withFixRegistry = New-TPMGameSupportContractRegistryV1 -Profiles @($profile) -SnapshotId 'TPM-WITH-FIX' -CapturedAtUtc '2026-01-01T00:00:00Z'
        $withFix = $withFixRegistry.Contracts[0]
        $withFix.RequiredFixes.Status | Should -Be 'NOT_DECLARED'
        $withFix.GpuLimitations.Status | Should -Be 'NOT_DECLARED'
        $withFix.SetupPolicy.Automation | Should -Be 'MANUAL'
    }

    It 'requires evidence and verification for declared fixes' {
        $profile = New-TestGameSupportProfile -ProfileCode 'DeclaredFix'
        $profile | Add-Member -NotePropertyName FixDomains -NotePropertyValue ([pscustomobject]@{
            RequiredFixes = [pscustomobject]@{
                DeclarationState = 'DECLARED'
                Items = @([pscustomobject]@{ fixId = 'fixture-fix'; component = 'GamePatch' })
                EvidenceRefs = @('fixture-source')
                AutomationAllowed = $false
                Preconditions = @('fixture-precondition')
                Ownership = 'TPM'
                VerificationRule = 'Verify fixture patch hash.'
                Risk = 'Fixture only.'
            }
        })
        $declared = New-TPMGameSupportContractRegistryV1 -Profiles @($profile) -SnapshotId 'TPM-DECLARED' -CapturedAtUtc '2026-01-01T00:00:00Z'
        $declared.Contracts[0].RequiredFixes.DeclarationState | Should -Be 'DECLARED'
        $declared.Contracts[0].RequiredFixes.EvidenceRefs | Should -Contain 'fixture-source'
        $declared.Contracts[0].RequiredFixes.VerificationRule | Should -Be 'Verify fixture patch hash.'
    }

    It 'does not wire the registry into the product menu script' {
        $main = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'))
        $main | Should -Not -Match 'TPMGameSupport\.Contracts'
        $main | Should -Not -Match 'game-support-contracts\.json'
    }
}
