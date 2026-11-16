#Requires -Module Pester

# FIX112 (review finding B5): a Pester container that fails at discovery or in BeforeAll gives Failed=0 and FailedContainers>=1.
#   The Pester child already wrote FailedContainers and exited 1, but the fact the certification authority evaluates never carried
#   it, so such a run still reported CERTIFIED.
#   - The Pester fact carries FailedContainers (schema-validated, exact field order, integer >= 0).
#   - A fact with FailedContainers > 0 is rejected with PESTER_CONTAINER_FAILURES even when Failed = 0.
#   - A missing, negative or non-integer FailedContainers fails closed at the fact schema.
#   - Both fact builders (the production one and the shadow one) pass FailedContainers through from the legacy results.
#   - A Pester result file written by an older child (no FailedContainers) is rejected by the result reader.
# Everything here is synthetic (TestDrive folders). Nothing reads a real install or a real collection.
# What this CANNOT prove: a real Pester child hitting a real discovery error (needs a full certification run).

BeforeAll {
    $script:F112Scripts = (Resolve-Path (Join-Path $PSScriptRoot '..\scripts')).Path
    Import-Module (Join-Path $script:F112Scripts 'TPMCertification.Contracts.psm1') -Force
    Import-Module (Join-Path $script:F112Scripts 'TPMCertification.Authority.psm1') -Force
    Import-Module (Join-Path $script:F112Scripts 'TPMCertification.Execution.psm1') -Force
    Import-Module (Join-Path $script:F112Scripts 'TPMCertification.Production.psm1') -Force
    Import-Module (Join-Path $script:F112Scripts 'TPMCertification.Reports.psm1') -Force
    Import-Module (Join-Path $script:F112Scripts 'TPMCertification.Publication.psm1') -Force
    Import-Module (Join-Path $script:F112Scripts 'TPMCertification.ProductionFacts.psm1') -Force
    $script:F112RepoRoot = Split-Path $script:F112Scripts -Parent

    function New-F112CertificationIdentity {
        $commit = 'a' * 40; $hash = 'a' * 64
        $snapshot = [ordered]@{ Branch = 'main'; Commit = $commit; RemoteRef = 'origin/main'; RemoteCommit = $commit; Clean = $true; RefSnapshotSha256 = $hash; ReflogSnapshotSha256 = $hash }
        [ordered]@{ ExpectedBranch = 'main'; ExpectedCommit = $commit; Start = $snapshot; End = $snapshot; RefMutationDetected = $false; RefMutationReason = $null; IdentityValid = $true }
    }

    # A Pester fact in the exact field order the authority schema expects. Overrides replace a value; a $null override value removes the field.
    function New-F112PesterFact {
        param([hashtable]$Overrides = @{})
        $data = [ordered]@{
            Executed = $true; Total = 2; Passed = 2; Failed = 0; Skipped = 0; NotRun = 0
            FailedContainers = 0; Engine = 'Pester 5.7.1 / pwsh 7.6.3'; SuiteSha256 = ('a' * 64)
        }
        foreach ($key in $Overrides.Keys) {
            if ($null -eq $Overrides[$key]) { $data.Remove($key) } else { $data[$key] = $Overrides[$key] }
        }
        [ordered]@{ Identifier = 'Pester'; Applicable = $true; Data = $data }
    }

    # Legacy results object as the smoke harness builds it, with the Pester block replaceable.
    function New-F112LegacyFixture {
        param([string]$Root, $Pester)
        $repo = Join-Path $Root 'repo'; $report = Join-Path $Root 'report'; $backup = Join-Path $Root 'backup'
        New-Item -ItemType Directory -Path $repo, (Join-Path $repo 'Tests'), $report, (Join-Path $backup 'UserProfiles'), (Join-Path $report 'InstallHealth') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $repo 'Tests\one.ps1'), 'test')
        [IO.File]::WriteAllText((Join-Path $report 'InstallHealth\InstallHealth.json'), '{}')
        $zero = [pscustomobject]@{ Added = 0; Removed = 0; Changed = 0; BeforeSkipped = 0; AfterSkipped = 0 }
        $health = [pscustomobject]@{ Checks = @(
                [pscustomobject]@{ Name = 'TeknoParrotUi.exe exists'; Passed = $true },
                [pscustomobject]@{ Name = 'GameProfiles folder exists'; Passed = $true },
                [pscustomobject]@{ Name = 'UserProfiles folder exists'; Passed = $true }) }
        $results = [pscustomobject]@{
            SmokeMode = $true
            Checks = @([pscustomobject]@{ Name = 'Repository available'; Passed = $true; Details = 'fixture repository is available' })
            GitStatus = '(clean)'; CertificationIdentity = (New-F112CertificationIdentity)
            Pester = $Pester; PesterVersion = '5.7.1'; PowerShellVersion = '7.6.3'
            PSScriptAnalyzerFindings = 0; PSScriptAnalyzerVersion = '1.24.0'
            Backup = [pscustomobject]@{ UserProfiles = $true; GameProfiles = $null }
            Snapshots = [ordered]@{ UserProfiles = $zero; GameProfiles = $zero; Pcsx2x6Crosshairs = $zero }
            Pcsx2x6 = [pscustomobject]@{ Present = $false }
            VirtualBetaTester = [pscustomobject]@{ Total = 1; Passed = 1; Failed = 0; HumanBehaviors = 1; IdempotencyChecks = 0; RecoveryBehaviors = 0; EnvironmentVariations = 0; HighTvdBehaviors = 1 }
            RequestedTeknoParrotRoot = $repo; EffectiveTeknoParrotRoot = $null
        }
        @{ Results = $results; Health = $health; Repo = $repo; Report = $report; Backup = $backup }
    }

    # Stub copies of every file in the fixed production inventory (the production builder scans the whole list).
    function New-F112InventoryRepo {
        param([string]$Root)
        $repo = Join-Path $Root 'repo'
        New-Item -ItemType Directory -Path $repo, (Join-Path $repo 'scripts'), (Join-Path $repo 'tools'), (Join-Path $repo 'Tests') -Force | Out-Null
        $relativePaths = @(
            'TeknoParrot-Manager.ps1', 'scripts/TpmRequiredPatchEngine.ps1', 'scripts/TPMCertification.Contracts.psm1',
            'scripts/Debug-TPM-MenuLayout.ps1', 'tools/Invoke-TpmAutoUpdate.ps1', 'tools/TpmAutoUpdate.Core.psm1', 'scripts/TpmProgress.psm1',
            'scripts/Invoke-TPM-RealInstanceSmoke.ps1', 'scripts/Invoke-TPM-InstallHealthCheck.ps1', 'scripts/Resolve-Pcsx2Directory.ps1', 'scripts/Run-TPM-Tests.ps1', 'scripts/TPMCertification.Execution.psm1', 'scripts/Invoke-TPM-PesterChild.ps1',
            'scripts/TPMCertification.Authority.psm1', 'scripts/TPMCertification.Production.psm1', 'scripts/TPMCertification.ProductionCycle.psm1', 'scripts/TPMCertification.ProductionEvidence.psm1', 'scripts/TPMCertification.ProductionFacts.psm1',
            'scripts/TPMCertification.Publication.psm1', 'scripts/TPMCertification.Reports.psm1', 'scripts/Test-TPMParserCheckV1.ps1'
        )
        foreach ($relative in $relativePaths) {
            [IO.File]::WriteAllText((Join-Path $repo ($relative -replace '/', '\')), "Write-Output '$relative'")
        }
        [IO.File]::WriteAllText((Join-Path $repo 'Tests\one.ps1'), 'test')
        $repo
    }
}

Describe 'FIX112 B5 the Pester fact carries FailedContainers and a failed container cannot certify' {
    BeforeAll {
        $script:F112Report = Join-Path $TestDrive 'report'
    }

    It 'accepts a fact with Failed=0 and FailedContainers=0 and passes it' {
        # Mutation: none expected to differ from the old behavior for a clean run; pristine code rejects the extra field, so this also pins the new schema.
        $fact = New-F112PesterFact
        { Assert-TPMFactRecordV1 $fact 'Smoke' $script:F112Report } | Should -Not -Throw
        $decision = Get-TPMFactDecisionV1 $fact 'Smoke' $script:F112Report
        $decision.Status | Should -Be 'Pass'
        $decision.Passed | Should -BeTrue
        @($decision.FailureReasons).Count | Should -Be 0
    }

    It 'rejects a fact with Failed=0 and FailedContainers=1 with PESTER_CONTAINER_FAILURES' {
        # Mutation: drop the FailedContainers branch from the Pester decision -> the run certifies with a container that never ran.
        $fact = New-F112PesterFact @{ FailedContainers = 1 }
        { Assert-TPMFactRecordV1 $fact 'Smoke' $script:F112Report } | Should -Not -Throw
        $decision = Get-TPMFactDecisionV1 $fact 'Smoke' $script:F112Report
        $decision.Status | Should -Be 'Fail'
        $decision.Passed | Should -BeFalse
        @($decision.FailureReasons.Code) | Should -Contain 'PESTER_CONTAINER_FAILURES'
        @($decision.FailureReasons.Code) | Should -Not -Contain 'PESTER_FAILURES'
    }

    It 'reports both reasons when tests failed and a container failed' {
        $fact = New-F112PesterFact @{ Total = 2; Passed = 1; Failed = 1; FailedContainers = 2 }
        $decision = Get-TPMFactDecisionV1 $fact 'Smoke' $script:F112Report
        @($decision.FailureReasons.Code) | Should -Contain 'PESTER_FAILURES'
        @($decision.FailureReasons.Code) | Should -Contain 'PESTER_CONTAINER_FAILURES'
    }

    It 'lists PESTER_CONTAINER_FAILURES in the closed failure-code vocabulary the report validators use' {
        (Get-TPMFactFailureCodesV1) | Should -Contain 'PESTER_CONTAINER_FAILURES'
    }

    It 'rejects a fact that has no FailedContainers field' {
        # Mutation: make FailedContainers optional in the schema -> a producer that forgets it silently certifies.
        $fact = New-F112PesterFact @{ FailedContainers = $null }
        { Assert-TPMFactRecordV1 $fact 'Smoke' $script:F112Report } | Should -Throw '*Pester field count*'
    }

    It 'rejects a FailedContainers field in the wrong position (exact field order)' {
        $data = [ordered]@{
            Executed = $true; Total = 2; Passed = 2; Failed = 0; Skipped = 0; NotRun = 0
            Engine = 'Pester 5.7.1 / pwsh 7.6.3'; SuiteSha256 = ('a' * 64); FailedContainers = 0
        }
        $fact = [ordered]@{ Identifier = 'Pester'; Applicable = $true; Data = $data }
        { Assert-TPMFactRecordV1 $fact 'Smoke' $script:F112Report } | Should -Throw "*expected 'FailedContainers'*"
    }

    It 'rejects a negative FailedContainers' {
        $fact = New-F112PesterFact @{ FailedContainers = -1 }
        { Assert-TPMFactRecordV1 $fact 'Smoke' $script:F112Report } | Should -Throw '*FailedContainers is out of range*'
    }

    It 'rejects a non-integer FailedContainers: <Label>' -ForEach @(
        @{ Label = 'string'; Value = '1' }
        @{ Label = 'empty string'; Value = '' }
        @{ Label = 'fraction'; Value = 1.5 }
        @{ Label = 'boolean'; Value = $true }
        @{ Label = 'array'; Value = @(1) }
    ) {
        $fact = New-F112PesterFact @{ FailedContainers = $Value }
        { Assert-TPMFactRecordV1 $fact 'Smoke' $script:F112Report } | Should -Throw '*FailedContainers must be integer*'
    }

    It 'rejects a null FailedContainers value' {
        $fact = New-F112PesterFact
        $fact.Data['FailedContainers'] = $null
        { Assert-TPMFactRecordV1 $fact 'Smoke' $script:F112Report } | Should -Throw '*FailedContainers must be integer*'
    }
}

Describe 'FIX112 B5 the fact builders pass FailedContainers through from the legacy results' {
    It 'the production builder emits FailedContainers=1 for a container failure and the authority rejects that fact' {
        # Nested fixture directories add GUIDs; keep the root short (legacy MAX_PATH).
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N').Substring(0, 12))
        $repo = New-F112InventoryRepo $root
        $fixture = New-F112LegacyFixture $root ([pscustomobject]@{ Total = 2; Passed = 2; Failed = 0; Skipped = 0; NotRun = 0; FailedContainers = 1 })
        $emptyRegistry = Join-Path $root 'empty-dispositions.psd1'
        [IO.File]::WriteAllText($emptyRegistry, '@{ SchemaVersion = 1; Dispositions = @() }')
        $facts = @(New-TPMProductionFactRecordsV1 -Results $fixture.Results -RepositoryPath $repo -ReportDirectory $fixture.Report -BackupDirectory $fixture.Backup -HealthResult $fixture.Health `
                -StagingParentRoot (Join-Path $root 'staging') -DestinationRoot (Join-Path $root 'destination') -WorkingDirectoryRoot $root -WorkingDirectory (Join-Path $root 'work') `
                -DispositionRegistryPath $emptyRegistry -PSScriptAnalyzerSettingsPath (Join-Path $script:F112RepoRoot 'PSScriptAnalyzerSettings.psd1'))
        $pester = $facts | Where-Object Identifier -eq 'Pester'
        $pester.Data.FailedContainers | Should -Be 1
        { Assert-TPMFactRecordV1 $pester 'Smoke' $fixture.Report } | Should -Not -Throw
        @((Get-TPMFactDecisionV1 $pester 'Smoke' $fixture.Report).FailureReasons.Code) | Should -Contain 'PESTER_CONTAINER_FAILURES'
    }
}

Describe 'FIX112 B5 a Pester result file from an older child (no FailedContainers) is not accepted' {
    It 'Read-TPMPesterResultV1 rejects a result file without FailedContainers (older child output fails closed)' {
        $contract = [ordered]@{
            SchemaVersion = 1; Discovered = 3; Passed = 3; Failed = 0; Skipped = 0; NotRun = 0; Containers = 1
            DurationMilliseconds = 10; Failures = @()
            Categories = [ordered]@{
                VirtualBetaTesterTotal = 0; VirtualBetaTesterPassed = 0; VirtualBetaTesterFailed = 0
                HumanBehaviors = 0; IdempotencyChecks = 0; RecoveryBehaviors = 0; EnvironmentVariations = 0; HighTvdBehaviors = 0
            }
            Engine = 'Pester 5.7.1 / pwsh 7.6.3'
        }
        $path = Join-Path $TestDrive 'old-child-result.json'
        ($contract | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $path -Encoding UTF8
        { Read-TPMPesterResultV1 -Path $path } | Should -Throw '*PESTER_RESULT_SCHEMA_INVALID*'
    }

    It 'Read-TPMPesterResultV1 returns FailedContainers=1 with Failed=0 so the caller can see the failed container' {
        $contract = [ordered]@{
            SchemaVersion = 1; Discovered = 3; Passed = 3; Failed = 0; Skipped = 0; NotRun = 0; Containers = 2; FailedContainers = 1
            DurationMilliseconds = 10; Failures = @()
            Categories = [ordered]@{
                VirtualBetaTesterTotal = 0; VirtualBetaTesterPassed = 0; VirtualBetaTesterFailed = 0
                HumanBehaviors = 0; IdempotencyChecks = 0; RecoveryBehaviors = 0; EnvironmentVariations = 0; HighTvdBehaviors = 0
            }
            Engine = 'Pester 5.7.1 / pwsh 7.6.3'
        }
        $path = Join-Path $TestDrive 'failed-container-result.json'
        ($contract | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $path -Encoding UTF8
        $result = Read-TPMPesterResultV1 -Path $path
        $result.Failed | Should -Be 0
        $result.FailedContainers | Should -Be 1
    }
}
