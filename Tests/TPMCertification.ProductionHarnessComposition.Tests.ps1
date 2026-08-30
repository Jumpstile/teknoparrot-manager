#Requires -Module Pester

# ADR155-0309 Checkpoint B2 composition-seam regression coverage. The
# harness script (scripts/Invoke-TPM-RealInstanceSmoke.ps1) cannot be run
# end to end here (no real TeknoParrot install on this dev machine), and its
# certification tail is top-level script code, not an extractable function.
# Instead, this drives the exact real fact assembler and composition
# functions the harness calls, in the same sequence and shapes the harness
# uses. The parser, PSScriptAnalyzer, and InjectionHunter adapters are
# mocked in BeforeEach because their real contracts are covered directly
# by TPMCertification.ProductionFacts.Tests.ps1; rerunning those external
# tool jobs for every composition case added roughly seven minutes to the
# complete suite on this machine without increasing composition coverage.
# This exercises the real composition seam the harness relies on, not a
# source-text match or a reimplementation of the harness's own logic.

BeforeAll {
    $scriptsDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts'
    foreach ($m in 'TPMCertification.Authority.psm1','TPMCertification.Production.psm1','TPMCertification.Reports.psm1','TPMCertification.Publication.psm1','TPMCertification.ProductionCycle.psm1','TPMCertification.ProductionFacts.psm1','TPMCertification.ProductionEvidence.psm1') {
        Import-Module (Join-Path $scriptsDir $m) -Force
    }
    function New-TestCertificationIdentity {
        $commit='a'*40;$hash='a'*64;$snapshot=[ordered]@{Branch='main';Commit=$commit;RemoteRef='origin/main';RemoteCommit=$commit;Clean=$true;RefSnapshotSha256=$hash;ReflogSnapshotSha256=$hash}
        [ordered]@{ExpectedBranch='main';ExpectedCommit=$commit;Start=$snapshot;End=$snapshot;RefMutationDetected=$false;RefMutationReason=$null;IdentityValid=$true}
    }

    function New-TPMSpyAuthorityV1([scriptblock]$RealAuthority) {
        $log = New-Object Collections.Generic.List[string]
        $spy = {
            param([string]$Operation, $Value, $Dependency)
            # $Value is frequently an [ordered]@{...} Hashtable (the fact/
            # evidence record shape), not a PSCustomObject -- a Hashtable's
            # own keys are never exposed through .PSObject.Properties, only
            # through the member-access convenience syntax ($Value.Identifier
            # itself), so this must not gate on .PSObject.Properties.Name.
            $identifier = $null
            if ($null -ne $Value -and $Operation -in @('RecordFact', 'RecordEvidence', 'IssueFinalEvidence')) {
                try { $identifier = $Value.Identifier } catch { $identifier = $null }
            }
            $detail = if ($identifier) { ":$identifier" } else { '' }
            [void]$log.Add("$Operation$detail")
            return & $RealAuthority $Operation $Value $Dependency
        }.GetNewClosure()
        return [pscustomobject]@{ Authority = $spy; Log = $log }
    }

    function New-LegacyResultsFixtureV1([string]$Repo, [string]$Report, [string]$Backup, [bool]$ForceIneligible = $false) {
        New-Item -ItemType Directory -Path $Repo, (Join-Path $Repo 'Tests'), $Report, (Join-Path $Backup 'UserProfiles') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $Repo 'Tests\one.ps1'), 'test')
        # New-TPMProductionFactRecordsV1 resolves the real, fixed 17-entry
        # inventory (Get-TPMProductionPowerShellInventoryV1) against
        # -RepositoryPath -- every entry must physically exist for it to
        # succeed, so this stubs all seventeen the same way
        # Tests/TPMCertification.ProductionFacts.Tests.ps1's own
        # New-InventoryFixture does.
        New-Item -ItemType Directory -Path (Join-Path $Repo 'scripts'), (Join-Path $Repo 'tools') -Force | Out-Null
        foreach ($relative in @(
            'TeknoParrot-Manager.ps1','scripts/Debug-TPM-MenuLayout.ps1','tools/Invoke-TpmAutoUpdate.ps1','tools/TpmAutoUpdate.Core.psm1',
            'scripts/Invoke-TPM-RealInstanceSmoke.ps1','scripts/Invoke-TPM-InstallHealthCheck.ps1','scripts/Resolve-Pcsx2Directory.ps1','scripts/Run-TPM-Tests.ps1','scripts/TPMCertification.Execution.psm1','scripts/Invoke-TPM-PesterChild.ps1',
            'scripts/TPMCertification.Authority.psm1','scripts/TPMCertification.Production.psm1','scripts/TPMCertification.ProductionCycle.psm1','scripts/TPMCertification.ProductionEvidence.psm1','scripts/TPMCertification.ProductionFacts.psm1',
            'scripts/TPMCertification.Publication.psm1','scripts/TPMCertification.Reports.psm1','scripts/TPMCertification.Shadow.psm1','scripts/Test-TPMParserCheckV1.ps1'
        )) {
            $full = Join-Path $Repo ($relative -replace '/', '\')
            [IO.File]::WriteAllText($full, "Write-Output '$relative'")
        }
        # New-TPMProductionFactRecordsV1 defaults -PSScriptAnalyzerSettingsPath
        # to <RepositoryPath>\PSScriptAnalyzerSettings.psd1 -- without it,
        # Test-TPMProductionPSScriptAnalyzerV1 reports Executed=$false (the
        # settings file genuinely does not exist there) and the Static
        # Analysis fact decision fails, making every run ineligible
        # regardless of everything else. Copy the real repo's settings file
        # in so a from-scratch stub repo behaves like the real one.
        Copy-Item -LiteralPath (Join-Path $scriptsDir '..\PSScriptAnalyzerSettings.psd1') -Destination (Join-Path $Repo 'PSScriptAnalyzerSettings.psd1')
        New-Item -ItemType Directory -Path (Join-Path $Report 'InstallHealth') | Out-Null
        [IO.File]::WriteAllText((Join-Path $Report 'InstallHealth\InstallHealth.json'), '{}')
        $health = [pscustomobject]@{ Checks = @([pscustomobject]@{ Name = 'TeknoParrotUi.exe exists'; Passed = $true }, [pscustomobject]@{ Name = 'GameProfiles folder exists'; Passed = $true }, [pscustomobject]@{ Name = 'UserProfiles folder exists'; Passed = $true }) }
        $results = [pscustomobject]@{
            SmokeMode = $true; Checks = @([pscustomobject]@{ Name = 'Repository available'; Passed = $true; Details = 'fixture repository is available' }); GitStatus = '(clean)'; CertificationIdentity = (New-TestCertificationIdentity)
            Pester = [pscustomobject]@{ Total = 2; Passed = $(if ($ForceIneligible) { 1 } else { 2 }); Failed = $(if ($ForceIneligible) { 1 } else { 0 }); Skipped = 0; NotRun = 0 }; PesterVersion = '5.7.1'; PowerShellVersion = '7.6.3'
            PSScriptAnalyzerFindings = 999; PSScriptAnalyzerVersion = 'decoy-legacy-value'
            Backup = [pscustomobject]@{ UserProfiles = $true; GameProfiles = $false }
            Snapshots = [ordered]@{ UserProfiles = [pscustomobject]@{Added=0;Removed=0;Changed=0;BeforeSkipped=0;AfterSkipped=0}; GameProfiles = [pscustomobject]@{Added=0;Removed=0;Changed=0;BeforeSkipped=0;AfterSkipped=0}; Pcsx2x6Crosshairs = [pscustomobject]@{Added=0;Removed=0;Changed=0;BeforeSkipped=0;AfterSkipped=0} }
            Pcsx2x6 = [pscustomobject]@{ Present = $false }
            VirtualBetaTester = [pscustomobject]@{ Total = 1; Passed = 1; Failed = 0; HumanBehaviors = 1; IdempotencyChecks = 0; RecoveryBehaviors = 0; EnvironmentVariations = 0; HighTvdBehaviors = 1 }
            RequestedTeknoParrotRoot = $Repo; EffectiveTeknoParrotRoot = $null
        }
        return @{ Results = $results; Health = $health }
    }

    $script:validator = { param($Path) [pscustomobject]@{ Valid = $true; Reason = 'test PNG'; Width = 3; Height = 5 } }
    $script:validPngBytes = [byte[]](137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3)

    function New-TestEvidenceFileV1([string]$Root) {
        $path = Join-Path $Root ([guid]::NewGuid().ToString('N') + '.png')
        [IO.File]::WriteAllBytes($path, $validPngBytes)
        return $path
    }

    # Mirrors exactly what Add-Screenshot in the harness produces, and the
    # exact order the harness's certification tail iterates
    # $legacyEvidence[0..7] (RecordEvidence) then $legacyEvidence[8]
    # (IssueFinalEvidence): certification-suite-running,
    # requested-effective-root-evidence, live-thumbnail-evidence (Skipped),
    # live-controls-evidence (Skipped), the three adaptive-menu captures,
    # smoke-file-safety-evidence, final-certification-result.
    function New-LegacyEvidenceLedgerV1([string]$EvidenceRoot) {
        $manifest = Get-TPMEvidenceManifestV1
        $ledger = New-Object Collections.Generic.List[object]
        for ($i = 0; $i -lt $manifest.Count; $i++) {
            $expected = $manifest[$i]
            if ($i -in 2, 3) {
                $ledger.Add([pscustomobject]@{ Name = $expected.Identifier; Label = $expected.Identifier; Path = $null; Status = 'Skipped'; EvidenceType = $null; Required = $false; WorkflowId = 'wf-1'; CaptureScope = $null; Details = 'not displayed' })
            } else {
                $path = New-TestEvidenceFileV1 $EvidenceRoot
                $scope = if ($expected.EvidenceType -eq 'DeterministicRender') { 'Deterministic' } else { 'Window' }
                $ledger.Add([pscustomobject]@{ Name = $expected.Identifier; Label = $expected.Identifier; Path = $path; Status = 'Captured'; EvidenceType = $expected.EvidenceType; Required = $expected.Required; WorkflowId = 'wf-1'; CaptureScope = $scope; Details = $null })
            }
        }
        return $ledger.ToArray()
    }

    # Reproduces the harness's own certification-tail composition exactly:
    # build authority -> record 11 facts -> record 8 evidence + issue the
    # 9th as final evidence -> seal -> invoke the sole certification cycle.
    # Returns the cycle result (or throws, exactly as the harness's own
    # try/catch would observe) plus the spy's operation log for order
    # assertions.
    function Invoke-TPMHarnessCompositionV1 {
        param(
            [Parameter(Mandatory=$true)][string]$Root,
            [bool]$ForceIneligible = $false,
            [scriptblock]$AuthorityWrapper = $null,
            [scriptblock]$BeforeCycle = $null
        )
        $repo = Join-Path $Root 'repo'; $report = Join-Path $Root 'report'; $backup = Join-Path $Root 'backup'
        $screenshotDir = Join-Path $Root 'screenshots'; New-Item -ItemType Directory -Path $screenshotDir | Out-Null
        $staging = Join-Path $Root 'staging'; New-Item -ItemType Directory -Path $staging | Out-Null
        $destination = Join-Path $Root 'destination'; New-Item -ItemType Directory -Path $destination | Out-Null
        $work = Join-Path $Root 'work'
        $fixture = New-LegacyResultsFixtureV1 -Repo $repo -Report $report -Backup $backup -ForceIneligible $ForceIneligible

        $realAuthority = New-TPMProductionWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $screenshotDir -ReportRoot $report -PngValidator $validator
        $spy = New-TPMSpyAuthorityV1 -RealAuthority $realAuthority
        $authority = if ($AuthorityWrapper) { & $AuthorityWrapper $spy.Authority } else { $spy.Authority }

        # The real InjectionHunterDispositions.psd1 registry documents
        # findings for the REAL production files' real content -- every
        # entry in it would look stale (unconsumed) against this fixture's
        # trivial one-line stub files, which produce zero real findings of
        # their own, so this uses an empty registry instead (the same
        # pattern Tests/TPMCertification.ProductionFacts.Tests.ps1 uses for
        # exactly this reason).
        $emptyRegistry = Join-Path $Root 'empty-dispositions.psd1'
        if (-not (Test-Path -LiteralPath $emptyRegistry)) { [IO.File]::WriteAllText($emptyRegistry, '@{ SchemaVersion = 1; Dispositions = @() }') }
        $facts = @(New-TPMProductionFactRecordsV1 -Results $fixture.Results -RepositoryPath $repo -ReportDirectory $report -BackupDirectory $backup -HealthResult $fixture.Health -StagingParentRoot $staging -DestinationRoot $destination -WorkingDirectoryRoot $Root -WorkingDirectory $work -DispositionRegistryPath $emptyRegistry)
        foreach ($fact in $facts) { [void](& $authority RecordFact $fact) }

        $manifest = Get-TPMEvidenceManifestV1
        $legacyEvidence = New-LegacyEvidenceLedgerV1 -EvidenceRoot $screenshotDir
        for ($i = 0; $i -lt 8; $i++) {
            $record = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacyEvidence[$i] -Expected $manifest[$i] -EvidenceRoot $screenshotDir -PngValidator $validator
            [void](& $authority RecordEvidence $record)
        }
        $preview = & $authority DeriveScorePreview
        $finalRecord = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacyEvidence[8] -Expected $manifest[8] -EvidenceRoot $screenshotDir -PngValidator $validator
        [void](& $authority IssueFinalEvidence $finalRecord $preview)
        $sealedRun = & $authority Seal

        if ($BeforeCycle) { & $BeforeCycle $realAuthority $destination }

        $identityGuard = { param([string]$Stage) return $true }
        $result = Complete-TPMProductionCertificationCycleV1 -Authority $authority -SealedRun $sealedRun -StagingParentRoot $staging -DestinationRoot $destination -IdentityGuard $identityGuard -Publish
        return [pscustomobject]@{ Result = $result; Log = $spy.Log; Facts = $facts; DestinationRoot = $destination }
    }
}

Describe 'ADR-0155 production harness composition seam (ADR155-0309 Checkpoint B2)' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root | Out-Null
        # The analyzer/parser adapters have their own full real-tool coverage
        # in TPMCertification.ProductionFacts.Tests.ps1. Keep this composition
        # suite focused on fact assembly, authority ordering, and publication
        # behavior rather than repeating 38 parser child launches plus 38
        # bounded analyzer jobs for every composition case.
        Mock Test-TPMProductionParserProbeV1 {
            param($Inventory, $Engine, $WorkingDirectoryRoot, $WorkingDirectory, $TimeoutSeconds)
            [ordered]@{ Identifier = $Engine; Executed = $true; ErrorCount = 0; ToolVersion = 'composition-test' }
        } -ModuleName TPMCertification.ProductionFacts
        Mock Test-TPMProductionPSScriptAnalyzerV1 {
            param($Inventory, $SettingsPath, $PerFileTimeoutSeconds)
            [ordered]@{ Executed = $true; FindingCount = 0; ToolVersion = 'composition-test' }
        } -ModuleName TPMCertification.ProductionFacts
        Mock Test-TPMProductionInjectionHunterV1 {
            param($Inventory, $DispositionRegistryPath, $PerFileTimeoutSeconds)
            [ordered]@{ Executed = $true; FindingCount = 0; UnresolvedFindingCount = 0; ToolVersion = 'composition-test'; Dispositions = @() }
        } -ModuleName TPMCertification.ProductionFacts
    }

    It 'records all eleven facts exactly once, in canonical order' {
        $composed = Invoke-TPMHarnessCompositionV1 -Root $root
        $factOps = @($composed.Log | Where-Object { $_ -like 'RecordFact:*' } | ForEach-Object { $_.Substring(11) })
        $factOps | Should -Be @('Repository','Pester','Static Analysis','Real Install Health','Backups','Smoke File Safety','Artifacts','pcsx2x6 crosshair path (issue #79)','Behavioral Certification (Virtual Beta Tester)','Unattended TPM root binding','Unattended TPM config restoration')
    }

    It 'records nine evidence records exactly once, in canonical order: the first eight via RecordEvidence and the ninth via IssueFinalEvidence' {
        $composed = Invoke-TPMHarnessCompositionV1 -Root $root
        $evidenceOps = @($composed.Log | Where-Object { $_ -like 'RecordEvidence:*' -or $_ -like 'IssueFinalEvidence:*' })
        $evidenceOps.Count | Should -Be 9
        $evidenceOps[0..7] | ForEach-Object { $_ | Should -Match '^RecordEvidence:' }
        $evidenceOps[8] | Should -Match '^IssueFinalEvidence:'
        $identifiers = @($evidenceOps | ForEach-Object { ($_ -split ':', 2)[1] })
        $identifiers | Should -Be @((Get-TPMEvidenceManifestV1).Identifier)
    }

    It 'seals the authority before invoking the production certification cycle' {
        $composed = Invoke-TPMHarnessCompositionV1 -Root $root
        $sealIndex = [array]::IndexOf($composed.Log.ToArray(), 'Seal')
        $cycleFirstOpIndex = [array]::IndexOf($composed.Log.ToArray(), 'IssueEligibility')
        $sealIndex | Should -BeGreaterThan -1
        $cycleFirstOpIndex | Should -BeGreaterThan $sealIndex
    }

    It 'a successful eligible run produces CERTIFIED and exit 0, with the seven canonical files durably committed at DestinationRoot\RunIdentity' {
        $composed = Invoke-TPMHarnessCompositionV1 -Root $root
        $composed.Result.Projection.FinalStatus | Should -Be 'CERTIFIED'
        $composed.Result.Projection.ExitCode | Should -Be 0
        $composed.Result.Commit.Committed | Should -Be $true
        $expectedDir = Join-Path $composed.DestinationRoot $composed.Result.Projection.RunIdentity
        $composed.Result.Commit.DestinationDirectory | Should -Be $expectedDir
        $files = @(Get-ChildItem -LiteralPath $expectedDir -File)
        $files.Count | Should -Be 7
        @($files.Name | Sort-Object) | Should -Be @('TPM-Certification-Commit.json','TPM-Certification-Eligibility.json','TPM-Certification-Final-Outcome.json','TPM-Certification-Manifest.json','TPM-Certification-Publication.json','TPM-Certification-Scorecard.md','TPM-Certification-Validation.md')
        foreach ($file in $files) {
            $bytes = [IO.File]::ReadAllBytes($file.FullName)
            $hash = Get-TPMSha256HexV1 -Bytes $bytes
            $manifestParsed = ($composed.Result.Manifest.Json | ConvertFrom-Json)
            if ($file.Name -eq 'TPM-Certification-Manifest.json') { $hash | Should -Be (Get-TPMSha256HexV1 -Bytes $composed.Result.Manifest.Bytes) }
            elseif ($file.Name -eq 'TPM-Certification-Commit.json') { $hash | Should -Be (Get-TPMSha256HexV1 -Bytes $composed.Result.Marker.Bytes) }
            else {
                $entry = @($manifestParsed.Artifacts | Where-Object { $_.FileName -eq $file.Name })[0]
                $hash | Should -Be $entry.Sha256
            }
        }
    }

    It 'a committed but score-ineligible run produces NOT CERTIFIED and exit 1, while still publishing the complete committed bundle' {
        $composed = Invoke-TPMHarnessCompositionV1 -Root $root -ForceIneligible $true
        $composed.Result.Commit.Committed | Should -Be $true
        $composed.Result.Projection.FinalStatus | Should -Be 'NOT CERTIFIED'
        $composed.Result.Projection.ExitCode | Should -Be 1
    }

    It 'an ordinary publication failure (destination collision) produces a genuine NOT CERTIFIED final outcome and exit 1, never CERTIFIED' {
        $collide = {
            param($RealAuthority, $Destination)
            $runIdentity = & $RealAuthority GetRunIdentity
            $collidingDir = Join-Path ([IO.Path]::GetFullPath($Destination)) $runIdentity
            New-Item -ItemType Directory -Path $collidingDir | Out-Null
            [IO.File]::WriteAllBytes((Join-Path $collidingDir 'TPM-Certification-Eligibility.json'), [byte[]](9, 9, 9))
        }
        $composed = Invoke-TPMHarnessCompositionV1 -Root $root -BeforeCycle $collide
        $composed.Result.Commit.Committed | Should -Be $false
        $composed.Result.Projection.FinalStatus | Should -Be 'NOT CERTIFIED'
        $composed.Result.Projection.ExitCode | Should -Be 1
        $composed.Result.FinalOutcome.CanonicalJson | Should -Match '"PublicationCommitted":false'
    }

    It 'an exception before publication (a malformed fact rejected by RecordFact) produces no committed bundle and propagates for the harness to treat as an infrastructure abort' {
        $repo = Join-Path $root 'repo'; $report = Join-Path $root 'report'; $backup = Join-Path $root 'backup'
        $screenshotDir = Join-Path $root 'screenshots'; New-Item -ItemType Directory -Path $screenshotDir | Out-Null
        New-LegacyResultsFixtureV1 -Repo $repo -Report $report -Backup $backup | Out-Null
        $destination = Join-Path $root 'destination'; New-Item -ItemType Directory -Path $destination | Out-Null
        $authority = New-TPMProductionWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $screenshotDir -ReportRoot $report -PngValidator $validator
        { & $authority RecordFact ([ordered]@{Identifier='NotARealFactIdentifier';Applicable=$true;Data=[ordered]@{}}) } | Should -Throw
        (Test-Path -LiteralPath $destination -PathType Container) | Should -Be $true
        @(Get-ChildItem -LiteralPath $destination -Recurse -File).Count | Should -Be 0
    }

    It 'an exception injected after commit but before the final outcome (through the harness''s own real authority) leaves no authoritative bundle' {
        $wrapper = {
            param([scriptblock]$Spy)
            return {
                param([string]$Operation, $Value, $Dependency)
                if ($Operation -ceq 'IssueFinalOutcome') { throw 'INJECTED_COMPOSITION_TEST_FAILURE' }
                return & $Spy $Operation $Value $Dependency
            }.GetNewClosure()
        }
        $errorRecord = $null
        try {
            Invoke-TPMHarnessCompositionV1 -Root $root -AuthorityWrapper $wrapper
        } catch { $errorRecord = $_ }
        $errorRecord | Should -Not -BeNullOrEmpty
        $errorRecord.Exception.Message | Should -Match '^POST_COMMIT_ROLLBACK_SUCCEEDED:'
        $destination = Join-Path $root 'destination'
        @(Get-ChildItem -LiteralPath $destination -Recurse -File).Count | Should -Be 0
    }

    It 'the harness source never reaches Shadow.psm1 or any removed legacy decision/publication path (problem-class sweep)' {
        $harnessPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\Invoke-TPM-RealInstanceSmoke.ps1'
        $codeLines = @([IO.File]::ReadAllLines($harnessPath) | Where-Object { $_ -notmatch '^\s*#' })
        $code = $codeLines -join "`n"
        $code | Should -Not -Match 'Import-Module\s+[^\r\n]*TPMCertification\.Shadow\.psm1'
        foreach ($legacyName in @('Complete-TPMCertificationTransaction','Get-TPMCertificationScoreFromItems','Test-TPMScoreItemManifest','Test-TPMArtifactManifest','Publish-TPMCertificationArtifacts','Invoke-TPMShadowCertificationV1','New-TPMShadowFactRecordsFromLegacyV1','New-TPMShadowWorkflowAuthorityV1')) {
            $code | Should -Not -Match ([regex]::Escape($legacyName))
        }
    }

    It 'console status and exit code in the harness source are derived only from $productionCycleResult.Projection, never from a separately assigned status/exit variable' {
        $harnessPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\Invoke-TPM-RealInstanceSmoke.ps1'
        $source = [IO.File]::ReadAllText($harnessPath)
        $tailStart = $source.IndexOf('$productionCycleResult = Complete-TPMProductionCertificationCycleV1')
        $tailStart | Should -BeGreaterThan -1
        $tailCodeLines = @(($source.Substring($tailStart) -split "`n") | Where-Object { $_ -notmatch '^\s*#' })
        $tail = $tailCodeLines -join "`n"
        # Exactly two literal exit statements may follow this point: the
        # infrastructure-abort path's fixed "exit 1", and the real-outcome
        # path's "exit $productionProjection.ExitCode". Any OTHER exit
        # statement (a hardcoded numeric exit code outside the abort path,
        # or an exit driven by a variable other than $productionProjection)
        # would mean a second, competing status/exit-code source exists.
        $exitStatements = @([regex]::Matches($tail, '(?m)^\s*exit\s+\S+') | ForEach-Object { $_.Value.Trim() })
        $exitStatements.Count | Should -Be 2
        $exitStatements | Should -Contain 'exit 1'
        $exitStatements | Should -Contain 'exit $productionProjection.ExitCode'
        $tail | Should -Match '\$productionProjection = \$productionCycleResult\.Projection'
        $tail | Should -Match '-IdentityGuard \$productionIdentityGuard'
    }
}
