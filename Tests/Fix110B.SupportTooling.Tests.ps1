#Requires -Module Pester

# FIX110B (S-18, S-19): support tooling that produced false positives or false passes.
#   S-18  An assessment must list exactly the support files its contract requires (ordinal ids, no duplicates, none missing).
#         Zero items count as satisfied only when the contract requires none.
#   S-19  The support corpus generator: the Program Files (x86) folder is a protected path; layout checks compare normalized
#         paths on both sides; every source folder is checked against the output folder before anything is created.
#         The permanent-procedure gate reads test freshness only from the Tests section and only from real start/finish evidence.
# What this CANNOT prove: runtime behavior of the real TeknoParrot Manager. These are tooling and evidence checks only.

BeforeAll {
    $script:f110RepoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:f110RepoRoot 'scripts/TPMGameSupport.Contracts.psm1') -Force -WarningAction SilentlyContinue
    Import-Module (Join-Path $script:f110RepoRoot 'scripts/TPMGameSupport.Assessments.psm1') -Force -WarningAction SilentlyContinue
    . (Join-Path $script:f110RepoRoot 'scripts/New-TpmSupportPostureCorpus.ps1')

    function New-F110Profile {
        param([string]$Code = 'SupportToolingFixture', [string]$EmulatorType = 'cxbxr')
        [pscustomobject]@{
            ProfileCode = $Code
            ProfileFileName = "$Code.xml"
            GameTitle = 'Support Tooling Fixture'
            VariantTitle = ''
            EmulationProfile = 'cxbxr'
            EmulatorType = $EmulatorType
            ProfileRevision = 1
            RequiresAdmin = $false
            SourcePath = "GameProfiles/$Code.xml"
            ProfileXmlSha256 = ('c' * 64)
            Executable = [pscustomobject]@{ PrimaryCandidates = @('fixture.xbe'); SecondaryCandidates = @(); HasTwoExecutables = $false; LaunchSecondExecutableFirst = $false; SecondExecutableArguments = '' }
            PathRules = [pscustomobject]@{ GamePath = ''; GamePath2 = ''; ContentDirectories = @(); MediaDirectories = @() }
            Media = [pscustomobject]@{ ChdRequirement = 'UNKNOWN'; RequiredExtensions = @(); MultipleChdAllowed = $false; MediaRuleEvidence = @() }
            Ownership = [pscustomobject]@{ TeknoParrotOwnedFields = @(); TpmReadableFields = @(); TpmWritableFields = @(); ManualTeknoParrotUiRequired = $false }
            ControllerEvidence = [pscustomobject]@{ DefaultInputApi = 'DirectInput'; AlternativeInputApis = @(); Settings = @(); Controls = @() }
            Classification = 'REVIEW_MANUAL'
            ReasonCode = 'OWNER_RUNTIME_REQUIRED'
            BeginnerAction = 'Review runtime evidence.'
            Evidence = [pscustomobject]@{ SourceIds = @('fixture-source'); ProfileSha256 = ('c' * 64); FixtureIds = @() }
        }
    }

    # A valid assessment copy whose support items are all present, so only the item list itself can make it invalid.
    function New-F110SatisfiedAssessment {
        param([Parameter(Mandatory)]$Assessment)
        $copy = ConvertFrom-Json ($Assessment | ConvertTo-Json -Depth 40)
        foreach ($item in @($copy.SupportFiles.Items)) {
            $item.PresenceState = 'PRESENT'; $item.PathState = 'MATCHED'; $item.HashState = 'NOT_DECLARED'; $item.RequirementStatus = 'SATISFIED'
        }
        $copy.SupportFiles.Overall = 'READY'
        return $copy
    }

    $script:f110Contract = New-TPMGameSupportContractV1 -Profile (New-F110Profile) -SnapshotId 'TOOLING-SNAPSHOT' -CapturedAtUtc '2026-01-01T00:00:00Z'
    $script:f110Assessment = New-TPMGameSupportAssessmentV1 -Contract $script:f110Contract -EvaluatedAtUtc '2026-01-02T00:00:00Z' -TargetIdentity 'fixture-target'
    $script:f110ShowdownProfile = New-F110Profile -Code 'Showdown'
    $script:f110ShowdownContract = New-TPMGameSupportContractV13 -Profile $script:f110ShowdownProfile -SnapshotId 'TOOLING-V13-SNAPSHOT' -CapturedAtUtc '2026-01-01T00:00:00Z'
    $script:f110ShowdownAssessment = New-TPMGameSupportAssessmentV11 -Contract $script:f110ShowdownContract -EvaluatedAtUtc '2026-01-02T00:00:00Z' -TargetIdentity 'fixture-target'
}

Describe 'FIX110B S-18 support assessment lists exactly the contract requirements' {
    It 'starts from a contract that requires four support files and a complete assessment that is valid' {
        # Mutation: none (fixture precondition). The next tests change this valid baseline one step at a time.
        @($script:f110Contract.Prerequisites.SupportFiles.Items).Count | Should -Be 4
        $complete = New-F110SatisfiedAssessment -Assessment $script:f110Assessment
        @($complete.SupportFiles.Items).Count | Should -Be 4
        (Test-TPMGameSupportAssessmentV1 -Assessment $complete -Contract $script:f110Contract).Valid | Should -BeTrue
    }

    It 'rejects an assessment with zero or one of the four required items even when Overall says SATISFIED or READY' {
        # Mutation: accept empty or partial item lists (the original defect).
        $none = New-F110SatisfiedAssessment -Assessment $script:f110Assessment
        $none.SupportFiles.Items = @()
        $none.SupportFiles.Overall = 'SATISFIED'
        $noneResult = Test-TPMGameSupportAssessmentV1 -Assessment $none -Contract $script:f110Contract
        $noneResult.Valid | Should -BeFalse
        $noneResult.Errors[0] | Should -Match 'GAME_SUPPORT_ASSESSMENT_BINDING_INVALID: missing requirement ''support-cxbxr-'
        $one = New-F110SatisfiedAssessment -Assessment $script:f110Assessment
        $one.SupportFiles.Items = @($one.SupportFiles.Items | Select-Object -First 1)
        $oneResult = Test-TPMGameSupportAssessmentV1 -Assessment $one -Contract $script:f110Contract
        $oneResult.Valid | Should -BeFalse
        $oneResult.Errors[0] | Should -Match 'missing requirement'
    }

    It 'rejects a duplicate requirement id even when the item count matches' {
        # Mutation: compare only the number of items, or the distinct ids against the contract in one direction.
        $duplicate = New-F110SatisfiedAssessment -Assessment $script:f110Assessment
        $items = @($duplicate.SupportFiles.Items)
        $duplicate.SupportFiles.Items = @($items[0], $items[1], $items[2], $items[0])
        $result = Test-TPMGameSupportAssessmentV1 -Assessment $duplicate -Contract $script:f110Contract
        $result.Valid | Should -BeFalse
        $result.Errors[0] | Should -Match 'duplicate requirement ''support-cxbxr-'
    }

    It 'rejects an unknown requirement id' {
        # Mutation: drop the per-item contract lookup.
        $unknown = New-F110SatisfiedAssessment -Assessment $script:f110Assessment
        $unknown.SupportFiles.Items[0].RequirementId = 'support-cxbxr-not-in-the-contract'
        $result = Test-TPMGameSupportAssessmentV1 -Assessment $unknown -Contract $script:f110Contract
        $result.Valid | Should -BeFalse
        $result.Errors[0] | Should -Match 'unknown requirement'
    }

    It 'accepts zero items only when the contract requires none' {
        # Mutation: demand at least one item, or accept zero items for every contract.
        $noneRequired = New-TPMGameSupportContractV1 -Profile (New-F110Profile -Code 'NoSupportFilesFixture' -EmulatorType 'TeknoParrot') -SnapshotId 'TOOLING-SNAPSHOT-NONE' -CapturedAtUtc '2026-01-01T00:00:00Z'
        @($noneRequired.Prerequisites.SupportFiles.Items).Count | Should -Be 0
        $assessment = New-TPMGameSupportAssessmentV1 -Contract $noneRequired -EvaluatedAtUtc '2026-01-02T00:00:00Z' -TargetIdentity 'fixture-target'
        $assessment.SupportFiles.Overall | Should -BeExactly 'SATISFIED'
        (Test-TPMGameSupportAssessmentV1 -Assessment $assessment -Contract $noneRequired).Valid | Should -BeTrue
    }

    It 'applies the same rule to a 1.1 assessment bound to a 1.3 contract' {
        # Mutation: check the item list only in the 1.0 validator path, not through the 1.1 delegation.
        @($script:f110ShowdownContract.Prerequisites.SupportFiles.Items).Count | Should -Be 4
        $complete = New-F110SatisfiedAssessment -Assessment $script:f110ShowdownAssessment
        (Test-TPMGameSupportAssessmentV1 -Assessment $complete -Contract $script:f110ShowdownContract).Valid | Should -BeTrue
        $none = New-F110SatisfiedAssessment -Assessment $script:f110ShowdownAssessment
        $none.SupportFiles.Items = @()
        $none.SupportFiles.Overall = 'SATISFIED'
        $result = Test-TPMGameSupportAssessmentV1 -Assessment $none -Contract $script:f110ShowdownContract
        $result.Valid | Should -BeFalse
        $result.Errors[0] | Should -Match 'missing requirement'
    }
}

Describe 'FIX110B S-19 support corpus path and layout checks' {
    It 'treats Program Files (x86), Program Files and Windows as protected and ordinary folders as safe' {
        # Mutation: restore the over-escaped pattern; Program Files (x86) is no longer protected.
        foreach ($path in @('C:\Program Files (x86)\Game', 'C:\Program Files\Game', 'D:\Windows\Game', 'C:\Program Files (x86)')) {
            Test-TpmSupportProtectedPath -Path $path | Should -BeTrue
        }
        foreach ($path in @('C:\Games\Fixture', 'C:\Program Filesystem\Game', 'C:\Program Files (x86 beta)\Game', 'C:\Windowsill\Game')) {
            Test-TpmSupportProtectedPath -Path $path | Should -BeFalse
        }
    }

    It 'classifies CHD and executable folder layouts from normalized paths' {
        # Mutation: compare the slash-normalized folders with the unnormalized Windows root; the first two layouts become nested.
        $fixtureRoot = Join-Path $TestDrive 'layout-fixtures'
        $cases = @(
            @{ Name = 'same'; Chd = 'disc.chd'; Expected = 'CHD_PLUS_EXECUTABLE_SAME_FOLDER' }
            @{ Name = 'content'; Chd = 'content\disc.chd'; Expected = 'CHD_PLUS_EXECUTABLE_PLUS_CONTENT_SUBFOLDER' }
            @{ Name = 'nested'; Chd = 'data\disc.chd'; Expected = 'CHD_NESTED_ONE_LEVEL' }
        )
        foreach ($case in $cases) {
            $gameRoot = Join-Path $fixtureRoot $case.Name
            $chdPath = Join-Path $gameRoot $case.Chd
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $chdPath))
            [IO.File]::WriteAllText((Join-Path $gameRoot 'game.exe'), 'x')
            [IO.File]::WriteAllText($chdPath, 'x')
            $fixture = [pscustomobject]@{
                id = $case.Name; profileCode = 'LayoutFixture'; relativeRoot = $case.Name; selectedPath = ''
                expectedClassification = ''; expectedReasonCode = ''; layoutClass = $null; chdRequirement = ''
                separateLauncher = $false; mediaConflict = $false; forceProtected = $false; forceReparse = $false
            }
            $observation = Get-TpmSupportLayoutObservation -FixtureRoot $fixtureRoot -Fixture $fixture -ProfileRecord $null
            $observation.LayoutClass | Should -BeExactly $case.Expected
        }
    }

    It 'refuses an output folder inside any source folder before it creates anything' -ForEach @(
        @{ Parameter = 'TeknoParrotRoot' }
        @{ Parameter = 'InstalledGameProfilesPath' }
        @{ Parameter = 'InstalledUserProfilesPath' }
        @{ Parameter = 'UpstreamProfileRoot' }
        @{ Parameter = 'HistoricalProfileRoot' }
        @{ Parameter = 'FixtureRoot' }
    ) {
        # Mutation: create OutputRoot first (a failed run leaves folders inside the source), or check only two of the source folders.
        $source = Join-Path $TestDrive ('source-' + $Parameter)
        [void][IO.Directory]::CreateDirectory($source)
        $output = Join-Path $source 'nested\output'
        $arguments = @{ OutputRoot = $output }
        $arguments[$Parameter] = $source
        { Invoke-TpmSupportPostureCorpus @arguments } | Should -Throw '*OutputRoot must not be inside a source root*'
        Test-Path -LiteralPath (Join-Path $source 'nested') | Should -BeFalse
    }

    It 'still creates the output folder for a valid run boundary' {
        # Mutation: refuse every output folder, or never create it (the early check must not break the normal path).
        $source = Join-Path $TestDrive 'valid-source\GameProfiles'
        [void][IO.Directory]::CreateDirectory($source)
        [IO.File]::WriteAllText((Join-Path $source 'Boundary.xml'), '<GameProfile><GameName>Boundary</GameName><GamePath></GamePath><EmulatorType>TeknoParrot</EmulatorType></GameProfile>')
        $output = Join-Path $TestDrive 'valid-output'
        { Invoke-TpmSupportPostureCorpus -InstalledGameProfilesPath $source -OutputRoot $output -SnapshotId 'BOUNDARY-TEST' -CapturedAtUtc '2026-01-01T00:00:00Z' | Out-Null } | Should -Not -Throw
        Test-Path -LiteralPath $output -PathType Container | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $output 'profiles') -PathType Container | Should -BeTrue
    }
}

Describe 'FIX110B S-19 permanent-procedure gate reads real test evidence from the Tests section only' {
    BeforeAll {
        $script:f110GatePath = Join-Path $script:f110RepoRoot 'scripts/Test-TpmPermanentProcedures.ps1'
        $tokens = $null
        $parseErrors = $null
        $gateAst = [Management.Automation.Language.Parser]::ParseFile($script:f110GatePath, [ref]$tokens, [ref]$parseErrors)
        if (@($parseErrors).Count -gt 0) { throw 'The gate script must parse without errors.' }
        $evidenceAst = $gateAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-TpmValidationEvidence' }, $true)
        if ($null -eq $evidenceAst) { throw 'Get-TpmValidationEvidence is missing from the gate script.' }
        Invoke-Expression $evidenceAst.Extent.Text

        function Invoke-F110Gate {
            param([Parameter(Mandatory)][string]$ReportPath, [Parameter(Mandatory)][string]$ChangedAtUtc, [string]$ExtraArguments = '')
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.FileName = (Get-Process -Id $PID).Path
            $startInfo.Arguments = ('-NoProfile -File "{0}" -RepoRoot "{1}" -ReportPath "{2}" -ChangedAtUtc {3} {4}' -f $script:f110GatePath, $script:f110RepoRoot, $ReportPath, $ChangedAtUtc, $ExtraArguments).TrimEnd()
            $startInfo.UseShellExecute = $false
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            $startInfo.CreateNoWindow = $true
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $startInfo
            [void]$process.Start()
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(120000)) { $process.Kill(); throw 'The gate child did not finish within 120 seconds.' }
            $text = $stdoutTask.Result + "`n" + $stderrTask.Result
            $process.Dispose()
            # Redirected error records may carry ANSI colors and "|" continuation prefixes.
            $text = [regex]::Replace($text, '\x1b\[[0-?]*[ -/]*[@-~]', '')
            return [regex]::Replace($text, '[\s|]+', ' ')
        }
    }

    It 'takes freshness from the Started and Finished UTC cells and ignores other timestamps in a row' {
        # Mutation: collect every timestamp of the section; a change boundary quoted in a command or result would count as a test run.
        $section = @(
            '## Tests with exact counts and timestamps'
            ''
            '| Gate/test | Exact command | Count/result | Started UTC | Finished UTC | Engine/version |'
            '|---|---|---|---|---|---|'
            '| Focused run | `Run.ps1 -ChangedAtUtc 2099-01-01T00:00:00Z` | 5 passed; boundary 2098-01-01T00:00:00Z | 2026-10-01T10:00:00.1234567Z | 2026-10-01T10:05:00.7654321Z | PS7 |'
            '| Earlier run | `a \| b` | passed | 2026-09-30T08:00:00 | not captured | PS5.1 |'
            '| Not captured | x | passed | not captured | not captured | PS5.1 |'
        ) -join "`r`n"
        $evidence = Get-TpmValidationEvidence -TestsSection $section
        $evidence.Count | Should -Be 3
        $evidence.Latest | Should -Be ([datetime]::new(2026, 10, 1, 10, 5, 0, [DateTimeKind]::Utc))
        @($evidence.Problems).Count | Should -Be 0
    }

    It 'accepts start-to-finish intervals written in prose and ignores a lone timestamp' {
        # Mutation: treat any prose timestamp as evidence, or ignore prose intervals completely.
        $interval = "PS5.1 native interval 2026-10-24T21:39:08.1707981Z to`r`n2026-10-24T21:39:41.4147742Z; receipt at 2030-01-01T00:00:00Z."
        $evidence = Get-TpmValidationEvidence -TestsSection ("## Tests with exact counts and timestamps`r`n`r`n" + $interval)
        $evidence.Count | Should -Be 2
        $evidence.Latest | Should -Be ([datetime]::new(2026, 10, 24, 21, 39, 41, [DateTimeKind]::Utc))
        (Get-TpmValidationEvidence -TestsSection 'Only a lone stamp 2030-01-01T00:00:00Z here.').Count | Should -Be 0
    }

    It 'reports a test that finished before it started' {
        # Mutation: skip the start/finish consistency check.
        $section = "| Gate/test | Exact command | Count/result | Started UTC | Finished UTC | Engine/version |`r`n|---|---|---|---|---|---|`r`n| Swapped | x | passed | 2026-10-01T10:05:00Z | 2026-10-01T10:00:00Z | PS7 |"
        $evidence = Get-TpmValidationEvidence -TestsSection $section
        @($evidence.Problems).Count | Should -Be 1
        $evidence.Problems[0] | Should -Match 'finished before it started'
    }

    It 'stops at the next level-2 heading, so a later unrelated section cannot make evidence fresh' {
        # Mutation: read from the Tests heading to the end of the report (the original defect).
        $reportPath = Join-Path $script:f110RepoRoot 'docs/remediation/PR-321-reconciliation.md'
        $report = [IO.File]::ReadAllText($reportPath)
        $withLaterSection = $report.TrimEnd() + "`r`n`r`n## Unrelated later section`r`n`r`nReceipt time 2099-01-01T00:00:00Z.`r`n"
        $probePath = Join-Path $TestDrive 'later-section-report.md'
        [IO.File]::WriteAllText($probePath, $withLaterSection, (New-Object System.Text.UTF8Encoding($false)))
        $stale = Invoke-F110Gate -ReportPath $probePath -ChangedAtUtc '2090-01-01T00:00:00Z'
        $stale | Should -Match 'Validation evidence predates the latest source/test/gate change'
        $fresh = Invoke-F110Gate -ReportPath $probePath -ChangedAtUtc '2000-01-01T00:00:00Z'
        $fresh | Should -Not -Match 'Validation evidence predates'
        $fresh | Should -Not -Match 'Validation timestamps are missing'
    }

    It 'lists a missing report section as a failed check instead of stopping with an exception' {
        # Mutation: go back to Substring(IndexOf(heading)) -> a report without the heading ends in a raw ArgumentOutOfRange stack trace and no list of failed checks.
        $report = [IO.File]::ReadAllText((Join-Path $script:f110RepoRoot 'docs/remediation/PR-321-reconciliation.md'))
        $probePath = Join-Path $TestDrive 'no-non-actions-report.md'
        [IO.File]::WriteAllText($probePath, $report.Replace('## Non-actions', '## Other heading'), (New-Object System.Text.UTF8Encoding($false)))
        $text = Invoke-F110Gate -ReportPath $probePath -ChangedAtUtc '2000-01-01T00:00:00Z'
        $text | Should -Match 'PERMANENT PROCEDURE GATE FAIL: Report section is missing: ## Non-actions'
        $text | Should -Not -Match 'ArgumentOutOfRange|Exception calling'
    }

    It 'fails when the named production source file does not exist, so the source scans cannot be skipped by a typo' {
        # Mutation: skip the source scans silently when the file is missing -> "Permanent procedure gate passed." for a mistyped path.
        $text = Invoke-F110Gate -ReportPath (Join-Path $script:f110RepoRoot 'docs/remediation/PR-321-reconciliation.md') -ChangedAtUtc '2000-01-01T00:00:00Z' -ExtraArguments ('-SourcePath "{0}"' -f (Join-Path $TestDrive 'no-such-source.ps1'))
        $text | Should -Match 'Production source file was not found'
        $text | Should -Not -Match 'Permanent procedure gate passed'
    }

    It 'blames a gate step only for its own exit code, not one left over from an earlier command' {
        # Mutation: read LASTEXITCODE without resetting it first -> a clean step is reported as "failed: exit code 1" after any earlier failing command in the session.
        $gateAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $script:f110RepoRoot 'scripts/Run-TpmQualityGate.ps1'), [ref]$null, [ref]$null)
        $stepAst = $gateAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-GateStep' }, $true)
        Invoke-Expression $stepAst.Extent.Text
        $failures = New-Object System.Collections.Generic.List[string]
        $global:LASTEXITCODE = 1
        Invoke-GateStep 'clean step' { $null = 1 }
        $failures.Count | Should -Be 0
        Invoke-GateStep 'failing step' { cmd.exe /c exit 3 }
        @($failures) | Should -Be @('failing step failed: exit code 3')
        $global:LASTEXITCODE = 0
    }

    It 'runs a gate Pester step on the pinned version, names the failed tests, and keeps one results file per run' {
        # Mutation: let both runs write the default testResults.xml, or report only "exit code 1" -> the failed test names are lost.
        $gateAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $script:f110RepoRoot 'scripts/Run-TpmQualityGate.ps1'), [ref]$null, [ref]$null)
        $pesterAst = $gateAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-GatePester' }, $true)
        Invoke-Expression $pesterAst.Extent.Text
        $pesterVersion = [regex]::Match([IO.File]::ReadAllText((Join-Path $script:f110RepoRoot 'scripts/Invoke-TPM-PesterChild.ps1')), 'Import-Module Pester -RequiredVersion (\d+(?:\.\d+)+)').Groups[1].Value
        $pesterVersion | Should -Not -BeNullOrEmpty
        $reportForGate = Join-Path $TestDrive 'gate-out\report.md'
        $bad = Join-Path $TestDrive 'Bad.Tests.ps1'
        $good = Join-Path $TestDrive 'Good.Tests.ps1'
        Set-Content -LiteralPath $bad -Value "Describe 'Gate sample' { It 'goes red on purpose' { 1 | Should -Be 2 } }"
        Set-Content -LiteralPath $good -Value "Describe 'Gate sample' { It 'stays green' { 1 | Should -Be 1 } }"
        $global:LASTEXITCODE = 0
        { Invoke-GatePester $bad 'pester-bad.xml' } | Should -Throw '*Gate sample.goes red on purpose*'
        Invoke-GatePester $good 'pester-good.xml'
        $global:LASTEXITCODE | Should -Be 0
        Test-Path -LiteralPath (Join-Path $TestDrive 'gate-out\pester-bad.xml') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $TestDrive 'gate-out\pester-good.xml') | Should -BeTrue
    }
}
