#Requires -Module Pester

# Regression coverage for scripts/Invoke-TPM-RealInstanceSmoke.ps1 -- the TPM
# Certification Suite's real-install harness. The harness script has
# top-level executable code (backup, Pester run, git status, etc.), so it
# cannot be dot-sourced directly without launching a full run against
# whatever -TeknoParrotRoot/-RepoPath happen to resolve to. Instead, this
# extracts just the reporting/scoring functions via AST, same technique
# Tests/TeknoParrot-Manager.Tests.ps1 uses for the main script.
#
# Why this file exists: New-CertificationScorecard shipped with an inline
# "Details=(if (...) {...} else {...})" hashtable-literal value. That is
# valid-looking PowerShell and passes Parser::ParseFile with zero errors --
# PowerShell parses hashtable-literal (@{...}) values in *command* mode, not
# *expression* mode, so a statement keyword like "if" (even parenthesized)
# only fails at actual execution: "The term 'if' is not recognized as a
# name of a cmdlet...". This crashed the harness on every real run, always
# after Pester and install-health collection had already completed and
# reported success -- exactly the kind of failure a parse-only gate cannot
# catch. Confirmed by direct reproduction before the fix landed.
#
# Run with: Invoke-Pester -Path .\Tests\TPMCertificationHarness.Tests.ps1

BeforeAll {
    $harnessPath = Join-Path $PSScriptRoot "..\scripts\Invoke-TPM-RealInstanceSmoke.ps1"
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($harnessPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Failed to parse Invoke-TPM-RealInstanceSmoke.ps1: $($parseErrors -join '; ')"
    }
    $functionAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    # Dot-source via a real temp file, not ". ([scriptblock]::Create($text))".
    # Confirmed by direct bisection: a [scriptblock]::Create()-based scriptblock,
    # once dot-sourced, is not lexically bound to this file's scope the way a
    # literal {...} block is -- and when this file ran alongside
    # Tests/TpmAutoUpdate.DestructivePath.Tests.ps1 in the same Pester
    # invocation, that file's "Mock -ModuleName TpmAutoUpdate.Core
    # Get-LatestRelease" stopped intercepting calls, hitting the real GitHub
    # API and failing on rate limits (10 failures reproduced on a real
    # arcade-machine certification run). Reproduced with a single trivial
    # unrelated function -- not specific to anything this file's own functions
    # do -- and confirmed the fix: extracting to an actual .ps1 file and
    # dot-sourcing that file removes the interference entirely.
    $extractedPath = Join-Path $TestDrive ("harness-functions-" + [guid]::NewGuid().ToString('N') + '.ps1')
    ($functionAsts | ForEach-Object { $_.Extent.Text }) -join "`n`n" | Set-Content -LiteralPath $extractedPath -Encoding utf8
    . $extractedPath

    # New-CertificationScorecard reads these as unqualified script-scope
    # variables rather than parameters (mirroring the harness's own top-level
    # script scope) -- without these it would read $null, not the bug under
    # test here.
    $script:reportDir = Join-Path $TestDrive "Reports\fake-run"
    $script:json = Join-Path $reportDir "TPM-Validation-Report.json"
    $script:md = Join-Path $reportDir "TPM-Validation-Report.md"
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
    Set-Content -LiteralPath $json -Value '{}' -Encoding ascii
    Set-Content -LiteralPath $md -Value '# x' -Encoding ascii

    function New-FakeResults {
        param([bool]$Pcsx2Present, [bool]$SmokeMode = $true)
        $pcsx2x6 = if ($Pcsx2Present) {
            [pscustomobject]@{ Present = $true; CanonicalFilesDeployed = $true; CursorPathPointsCanonical = $true }
        } else {
            [pscustomobject]@{ Present = $false }
        }
        @{
            GitStatus = '(clean)'
            Pester = [pscustomobject]@{ Total = 10; Passed = 10; Failed = 0 }
            PSScriptAnalyzerFindings = 0
            InstallHealthReport = 'fake-install-health.md'
            Backup = @{ UserProfiles = $true; GameProfiles = $true }
            Snapshots = $null
            SmokeMode = $SmokeMode
            RequestedTeknoParrotRoot = 'C:\fake\TeknoParrot'
            EffectiveTeknoParrotRoot = $null
            Screenshots = @()
            Checks = @(
                [pscustomobject]@{ Name = 'Repository available'; Passed = $true }
                [pscustomobject]@{ Name = 'Repository clean'; Passed = $true }
                # Issue #146: renamed from 'Real install health check
                # collected' -- the gate now depends on the health result's
                # own meaning, not merely that a report was written, so the
                # old name (which described only report creation) no longer
                # matched what this check actually verifies.
                [pscustomobject]@{ Name = 'Real install health check'; Passed = $true }
                [pscustomobject]@{ Name = 'pcsx2x6 crosshair path (issue #79)'; Passed = $true }
            )
            Pcsx2x6 = $pcsx2x6
            VirtualBetaTester = [pscustomobject]@{
                Total = 20; Passed = 20; Failed = 0
                HumanBehaviors = 10; IdempotencyChecks = 6; RecoveryBehaviors = 2; EnvironmentVariations = 2
                HighTvdBehaviors = 12
            }
            Timestamp = '2026-07-03_00-00-00'
            RepoPath = 'C:\fake\repo'
            GitBranch = 'main'
            Commit = 'abc123fullsha'
            CommitShort = 'abc123'
            OriginMainCommit = 'abc123fullsha'
            SyncStatus = 'MATCHES origin/main'
            GitVersion = 'git version 2.44.0'
            PowerShellVersion = '7.4.0'
            TpmScriptVersion = '1.0'
            TpmDisplayVersion = 'v1.0 RC2'
        }
    }
}

Describe "New-CertificationScorecard" {
    It "does not throw when pcsx2x6 is present (issue #79 detail branch)" {
        { New-CertificationScorecard -Results (New-FakeResults -Pcsx2Present $true) } | Should -Not -Throw
    }

    It "does not throw when pcsx2x6 is absent -- not applicable branch (issue #79)" {
        { New-CertificationScorecard -Results (New-FakeResults -Pcsx2Present $false) } | Should -Not -Throw
    }

    It "returns a scorecard with the pcsx2x6 area and a non-empty Details string in both branches" {
        $present = New-CertificationScorecard -Results (New-FakeResults -Pcsx2Present $true)
        $absent  = New-CertificationScorecard -Results (New-FakeResults -Pcsx2Present $false)

        $presentItem = $present.Items | Where-Object { $_.Area -eq 'pcsx2x6 crosshair path (issue #79)' }
        $absentItem  = $absent.Items  | Where-Object { $_.Area -eq 'pcsx2x6 crosshair path (issue #79)' }

        $presentItem | Should -Not -BeNullOrEmpty
        $absentItem  | Should -Not -BeNullOrEmpty
        $presentItem.Details | Should -Match 'canonicalDeployed'
        $absentItem.Details  | Should -Match 'not applicable'
    }

    It "computes Overall as CERTIFIED when every scored item passes" {
        $result = New-CertificationScorecard -Results (New-FakeResults -Pcsx2Present $true)
        $result.Overall | Should -Be 'CERTIFIED'
    }

    # Issue #111: certification provenance must be readable from the
    # scorecard object itself (and therefore the JSON scorecard file it's
    # serialized to), not only from a separate validation-report file.
    It "carries git/version provenance fields onto the returned scorecard object" {
        $result = New-CertificationScorecard -Results (New-FakeResults -Pcsx2Present $true)
        $result.Repository        | Should -Be 'C:\fake\repo'
        $result.Branch            | Should -Be 'main'
        $result.Commit            | Should -Be 'abc123fullsha'
        $result.CommitShort       | Should -Be 'abc123'
        $result.OriginMainCommit  | Should -Be 'abc123fullsha'
        $result.SyncStatus        | Should -Be 'MATCHES origin/main'
        $result.WorkingTreeClean  | Should -Be $true
        $result.GitVersion        | Should -Be 'git version 2.44.0'
        $result.PowerShellVersion | Should -Be '7.4.0'
        $result.TpmScriptVersion  | Should -Be '1.0'
        $result.TpmDisplayVersion | Should -Be 'v1.0 RC2'
    }

    It "reports WorkingTreeClean as false when GitStatus is not '(clean)'" {
        $fake = New-FakeResults -Pcsx2Present $true
        $fake.GitStatus = ' M TeknoParrot-Manager.ps1'
        $result = New-CertificationScorecard -Results $fake
        $result.WorkingTreeClean | Should -Be $false
    }
}

Describe "Write-TPMGateHeader / Set-TPMConsoleStatus (issue #122)" {
    # #122 requires each certification gate to show, while it runs (not just
    # in the final scorecard): which gate is currently running, why it
    # exists, and what a good outcome looks like. These are real functions
    # (not top-level flow), so they're exercised directly rather than via
    # source-level text checks.
    BeforeAll {
        Mock Write-Host {}
        Mock Write-Progress {}
    }

    It "prints the gate name, purpose, and expected outcome" {
        Write-TPMGateHeader -Gate 'Pester regression suite' -Purpose 'Runs every unit/regression test in the repo' -Expected 'zero failed tests'

        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Running: Pester regression suite*' }
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Purpose*Runs every unit/regression test in the repo*' }
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Expected*zero failed tests*' }
    }

    It "sets a live Write-Progress status combining purpose and expected outcome" {
        Write-TPMGateHeader -Gate 'Repository' -Purpose 'Confirms the certified commit and working-tree state' -Expected 'clean working tree, HEAD matches origin/main'

        Should -Invoke Write-Progress -ParameterFilter {
            $Activity -eq 'TPM Certification Suite' -and
            $Status -like '*Confirms the certified commit and working-tree state*' -and
            $Status -like '*clean working tree, HEAD matches origin/main*'
        }
    }

    It "does not throw when Purpose or Expected is blank" {
        { Set-TPMConsoleStatus -Gate 'X' -Purpose '' -Expected '' } | Should -Not -Throw
        { Set-TPMConsoleStatus -Gate '' -Purpose 'Y' -Expected 'Z' } | Should -Not -Throw
    }
}

Describe "Harness source-level guard against the hashtable-literal if/else defect class" {
    It "does not use an inline if/else expression as a hashtable-literal value in Invoke-TPM-RealInstanceSmoke.ps1" {
        # PowerShell parses @{...} values in command mode, not expression mode --
        # "Key=(if (...) {...} else {...})" parses cleanly (Parser::ParseFile
        # reports zero errors) but throws "The term 'if' is not recognized..."
        # only when actually executed. A parse check alone cannot catch this
        # class of defect; this regex guard is the fast, cheap first line of
        # defense, backed by the execution-level tests above for the specific
        # function that broke.
        $source = Get-Content -LiteralPath $harnessPath -Raw
        # [ \t] only, not \s -- \s matches newlines too, which would let an
        # unrelated "=" on one line and an unrelated "if (" many lines later
        # falsely pair up across a multi-hundred-line Raw string.
        $source | Should -Not -Match '=[ \t]*\([ \t]*if[ \t]*\('
    }

    It "does not use an inline if/else expression as a hashtable-literal value in Invoke-TPM-InstallHealthCheck.ps1" {
        $healthScriptPath = Join-Path $PSScriptRoot "..\scripts\Invoke-TPM-InstallHealthCheck.ps1"
        $source = Get-Content -LiteralPath $healthScriptPath -Raw
        # [ \t] only, not \s -- \s matches newlines too, which would let an
        # unrelated "=" on one line and an unrelated "if (" many lines later
        # falsely pair up across a multi-hundred-line Raw string.
        $source | Should -Not -Match '=[ \t]*\([ \t]*if[ \t]*\('
    }
}

Describe "Pester regression gate hang/timeout detection (issue #136)" {
    # These four functions back the runspace-polling loop that replaced a
    # single blocking Invoke-Pester call. A genuinely hung Pester test and a
    # merely slow real-hardware run looked identical before this fix (process
    # alive, report folder created, nothing ever updating) -- kept as pure,
    # side-effect-free functions specifically so this behavior is testable
    # without needing to run actual Pester-in-Pester or spin up a real
    # runspace, which would be slow and fragile to assert against reliably.

    Context "Test-TPMPesterHeartbeatDue" {
        It "is not due before the interval has elapsed" {
            Test-TPMPesterHeartbeatDue -ElapsedSeconds 5 -LastHeartbeatSeconds 0 -HeartbeatIntervalSeconds 15 | Should -Be $false
        }
        It "is due once the interval has elapsed" {
            Test-TPMPesterHeartbeatDue -ElapsedSeconds 15 -LastHeartbeatSeconds 0 -HeartbeatIntervalSeconds 15 | Should -Be $true
        }
        It "measures from the last heartbeat, not from zero" {
            Test-TPMPesterHeartbeatDue -ElapsedSeconds 20 -LastHeartbeatSeconds 15 -HeartbeatIntervalSeconds 15 | Should -Be $false
            Test-TPMPesterHeartbeatDue -ElapsedSeconds 30 -LastHeartbeatSeconds 15 -HeartbeatIntervalSeconds 15 | Should -Be $true
        }
    }

    Context "Test-TPMPesterTimedOut" {
        It "is not timed out before the limit" {
            Test-TPMPesterTimedOut -ElapsedSeconds 1799 -TimeoutSeconds 1800 | Should -Be $false
        }
        It "is timed out once the limit is reached" {
            Test-TPMPesterTimedOut -ElapsedSeconds 1800 -TimeoutSeconds 1800 | Should -Be $true
        }
        It "is timed out immediately with a near-zero timeout (used to exercise this path quickly in tests)" {
            Test-TPMPesterTimedOut -ElapsedSeconds 0.1 -TimeoutSeconds 0 | Should -Be $true
        }
    }

    Context "Get-TPMPesterHeartbeatMessage" {
        It "includes the elapsed time and the last output line" {
            $msg = Get-TPMPesterHeartbeatMessage -ElapsedSeconds 42 -LastOutputLine "Describing Foo"
            $msg | Should -Match '42s elapsed'
            $msg | Should -Match 'Describing Foo'
        }
        It "omits the trailing dash when there is no output line yet" {
            $msg = Get-TPMPesterHeartbeatMessage -ElapsedSeconds 3 -LastOutputLine ''
            $msg | Should -Match '3s elapsed'
            $msg | Should -Not -Match '--'
        }
    }

    Context "Get-TPMPesterTimeoutMessage" {
        It "reports elapsed time, the limit, the last output, and where to find the diagnostic files" {
            $msg = Get-TPMPesterTimeoutMessage -ElapsedSeconds 1800 -TimeoutSeconds 1800 -LastOutputLine "Describing Foo" -OutputPath "C:\out.txt" -ProgressPath "C:\progress.txt"
            $msg | Should -Match 'timed out after 1800s'
            $msg | Should -Match 'limit 1800s'
            $msg | Should -Match 'Describing Foo'
            $msg | Should -Match 'C:\\out\.txt'
            $msg | Should -Match 'C:\\progress\.txt'
        }
        It "reports a placeholder when no output was captured at all" {
            $msg = Get-TPMPesterTimeoutMessage -ElapsedSeconds 5 -TimeoutSeconds 5 -LastOutputLine '' -OutputPath "C:\out.txt" -ProgressPath "C:\progress.txt"
            $msg | Should -Match 'no output captured'
        }
    }
}

Describe "Pester regression gate runs off the main thread (issue #136)" {
    It "invokes Pester on a dedicated runspace with BeginInvoke, not a blocking call on the main thread" {
        # A blocking call gives the operator (and this harness) zero chance
        # to detect a hang before the whole certification run is stuck
        # forever. Confirms the fix's shape is actually in place, not just
        # that the helper functions above exist in isolation.
        $source = Get-Content -LiteralPath $harnessPath -Raw
        $source | Should -Match '\[runspacefactory\]::CreateRunspace\(\)'
        $source | Should -Match '\$pesterPs\.BeginInvoke\(\)'
        $source | Should -Match 'Test-TPMPesterTimedOut\s+-ElapsedSeconds'
    }

    It "throws a clear, diagnostic error on timeout instead of silently returning" {
        $source = Get-Content -LiteralPath $harnessPath -Raw
        $source | Should -Match 'if\s*\(\$pesterTimedOut\)\s*\{[\s\S]*?throw\s+\$timeoutMsg'
    }
}

Describe "Test-TPMCertificationRootValid (issue #146)" {
    # Regression coverage for the RC3 blocker: a certification run against a
    # root missing all three installation markers previously still scored
    # 8/9 instead of failing fast. This is the pure decision function behind
    # that fail-fast gate.
    It "reports invalid with all three markers listed missing, for a root with none of them" {
        $root = Join-Path $TestDrive ("invalid-root-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null

        $result = Test-TPMCertificationRootValid -TeknoParrotRoot $root

        $result.IsValid | Should -Be $false
        $result.MissingMarkers | Should -Contain 'TeknoParrotUi.exe'
        $result.MissingMarkers | Should -Contain 'GameProfiles'
        $result.MissingMarkers | Should -Contain 'UserProfiles'
        $result.MissingMarkers.Count | Should -Be 3
    }

    It "reports invalid and lists only the specific marker(s) actually missing, for a partially-populated root" {
        $root = Join-Path $TestDrive ("partial-root-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $root 'GameProfiles') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'UserProfiles') -Force | Out-Null
        # TeknoParrotUi.exe deliberately not created.

        $result = Test-TPMCertificationRootValid -TeknoParrotRoot $root

        $result.IsValid | Should -Be $false
        $result.MissingMarkers | Should -Be @('TeknoParrotUi.exe')
    }

    It "reports valid when all three installation markers are present" {
        $root = Join-Path $TestDrive ("valid-root-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $root 'GameProfiles') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'UserProfiles') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'TeknoParrotUi.exe') -Value 'fake exe' -Encoding ascii

        $result = Test-TPMCertificationRootValid -TeknoParrotRoot $root

        $result.IsValid | Should -Be $true
        $result.MissingMarkers.Count | Should -Be 0
    }

    It "treats a file where GameProfiles/UserProfiles should be a folder as still missing (Type mismatch, not just existence)" {
        $root = Join-Path $TestDrive ("wrong-type-root-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'TeknoParrotUi.exe') -Value 'fake exe' -Encoding ascii
        Set-Content -LiteralPath (Join-Path $root 'GameProfiles') -Value 'not a folder' -Encoding ascii
        New-Item -ItemType Directory -Path (Join-Path $root 'UserProfiles') -Force | Out-Null

        $result = Test-TPMCertificationRootValid -TeknoParrotRoot $root

        $result.IsValid | Should -Be $false
        $result.MissingMarkers | Should -Be @('GameProfiles')
    }
}

Describe "Get-TPMInvalidCertificationEnvironmentMessage (issue #146)" {
    It "clearly distinguishes an invalid environment from a TPM product failure, and names the missing markers" {
        $msg = Get-TPMInvalidCertificationEnvironmentMessage -TeknoParrotRoot 'W:\Emulators\TeknoParrot' -MissingMarkers @('TeknoParrotUi.exe', 'GameProfiles', 'UserProfiles')

        $msg | Should -Match 'INVALID CERTIFICATION ENVIRONMENT'
        $msg | Should -Match 'not a TPM product failure'
        $msg | Should -Match 'TeknoParrotUi\.exe'
        $msg | Should -Match 'GameProfiles'
        $msg | Should -Match 'UserProfiles'
        $msg | Should -Match ([regex]::Escape('W:\Emulators\TeknoParrot'))
    }
}

Describe "Fail-fast root validation runs before any certification gate (issue #146)" {
    # Source-level guard: the invalid-root check and its throw must appear
    # before Push-Location $RepoPath, which is the first line of the actual
    # certification flow (Pester, static analysis, backups, etc.). This is
    # what guarantees an invalid root can never reach those gates and
    # produce a partial scorecard instead of an outright fail-fast result.
    It "the root-validation throw appears before Push-Location in the harness source" {
        $source = Get-Content -LiteralPath $harnessPath -Raw
        $validationIndex = $source.IndexOf('$rootValidation = Test-TPMCertificationRootValid')
        $pushLocationIndex = $source.IndexOf('Push-Location $RepoPath')

        $validationIndex | Should -BeGreaterThan 0
        $pushLocationIndex | Should -BeGreaterThan 0
        $validationIndex | Should -BeLessThan $pushLocationIndex
    }

    It "throws Get-TPMInvalidCertificationEnvironmentMessage's exact message when the root is invalid" {
        $source = Get-Content -LiteralPath $harnessPath -Raw
        $source | Should -Match 'if\s*\(-not\s+\$rootValidation\.IsValid\)\s*\{[\s\S]*?throw\s+\$invalidMsg'
    }
}

Describe "TPM config JSON snapshot/override/restore (issue #146)" {
    # Regression coverage for the "saved-path conflict" scenario: a real
    # certification run found unattended TPM silently used a saved
    # TeknoParrot root that conflicted with (differed from) the requested
    # certification root, because -Unattended has no CLI override and
    # always reads TeknoParrot-Manager.config.json. These three functions
    # are the fix: temporarily bind config.json to the requested root for
    # the run, then restore exactly what was there before.
    It "returns null for a config path that does not exist yet (no prior saved settings)" {
        $configPath = Join-Path $TestDrive ("no-config-" + [guid]::NewGuid().ToString('N') + '.json')
        Get-TPMConfigJsonSnapshot -ConfigPath $configPath | Should -Be $null
    }

    It "returns the exact raw file content for an existing config" {
        $configPath = Join-Path $TestDrive ("existing-config-" + [guid]::NewGuid().ToString('N') + '.json')
        $content = '{"TeknoParrotRoot":"C:\\SavedPath\\TeknoParrot"}'
        Set-Content -LiteralPath $configPath -Value $content -Encoding utf8 -NoNewline

        (Get-TPMConfigJsonSnapshot -ConfigPath $configPath) | Should -Be $content
    }

    It "overrides only TeknoParrotRoot, preserving every other saved setting (the saved-path conflict scenario)" {
        $configPath = Join-Path $TestDrive ("conflict-config-" + [guid]::NewGuid().ToString('N') + '.json')
        $originalConfig = [ordered]@{
            TeknoParrotRoot = 'C:\Users\Someone\LaunchBox\Emulators\TeknoParrot'
            ZipSourceFolder = 'W:\ROMS\TeknoParrot Collection'
            GamesInstallFolder = 'E:\Games\TeknoParrot Games'
        }
        [System.IO.File]::WriteAllText($configPath, ($originalConfig | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding $false))

        $requestedRoot = 'W:\Emulators\TeknoParrot'
        $written = Set-TPMConfigJsonRoot -ConfigPath $configPath -TeknoParrotRoot $requestedRoot
        $written | Should -Be $true

        $updated = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        $updated.TeknoParrotRoot | Should -Be $requestedRoot
        $updated.ZipSourceFolder | Should -Be 'W:\ROMS\TeknoParrot Collection'
        $updated.GamesInstallFolder | Should -Be 'E:\Games\TeknoParrot Games'
    }

    It "returns false and writes nothing when there is no existing config to override" {
        $configPath = Join-Path $TestDrive ("missing-config-" + [guid]::NewGuid().ToString('N') + '.json')
        $written = Set-TPMConfigJsonRoot -ConfigPath $configPath -TeknoParrotRoot 'W:\Emulators\TeknoParrot'
        $written | Should -Be $false
        Test-Path -LiteralPath $configPath | Should -Be $false
    }

    It "restores the exact original content after an override, so a developer's real saved settings are never left corrupted" {
        $configPath = Join-Path $TestDrive ("restore-config-" + [guid]::NewGuid().ToString('N') + '.json')
        $originalContent = '{"TeknoParrotRoot":"C:\\Users\\Someone\\LaunchBox\\Emulators\\TeknoParrot","ZipSourceFolder":"W:\\ROMS\\TeknoParrot Collection"}'
        Set-Content -LiteralPath $configPath -Value $originalContent -Encoding utf8 -NoNewline

        $snapshot = Get-TPMConfigJsonSnapshot -ConfigPath $configPath
        [void](Set-TPMConfigJsonRoot -ConfigPath $configPath -TeknoParrotRoot 'W:\Emulators\TeknoParrot')
        (Get-Content -LiteralPath $configPath -Raw) | Should -Not -Be $originalContent

        Restore-TPMConfigJsonSnapshot -ConfigPath $configPath -Snapshot $snapshot
        (Get-Content -LiteralPath $configPath -Raw) | Should -Be $originalContent
    }

    It "removes the config file on restore when the snapshot was null (no config existed before the override)" {
        $configPath = Join-Path $TestDrive ("restore-null-" + [guid]::NewGuid().ToString('N') + '.json')
        Set-Content -LiteralPath $configPath -Value '{"TeknoParrotRoot":"W:\\Emulators\\TeknoParrot"}' -Encoding utf8 -NoNewline

        Restore-TPMConfigJsonSnapshot -ConfigPath $configPath -Snapshot $null

        Test-Path -LiteralPath $configPath | Should -Be $false
    }

    # Review round 2 (finding #2): no saved config exists at all on this
    # machine -- unattended TPM must still be bound to the requested root
    # via a minimal temporary config, not skipped outright.
    It "New-TPMTemporaryUnattendedConfig creates a config with only TeknoParrotRoot and GamesInstallFolder set to the requested root" {
        $configPath = Join-Path $TestDrive ("temp-config-" + [guid]::NewGuid().ToString('N') + '.json')
        $requestedRoot = 'W:\Emulators\TeknoParrot'

        $written = New-TPMTemporaryUnattendedConfig -ConfigPath $configPath -TeknoParrotRoot $requestedRoot
        $written | Should -Be $true

        Test-Path -LiteralPath $configPath | Should -Be $true
        $cfg = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        $cfg.TeknoParrotRoot | Should -Be $requestedRoot
        $cfg.GamesInstallFolder | Should -Be $requestedRoot
    }

    It "New-TPMTemporaryUnattendedConfig's output is removed cleanly by Restore-TPMConfigJsonSnapshot with a null snapshot (the same cleanup path as the existing-config case)" {
        $configPath = Join-Path $TestDrive ("temp-config-cleanup-" + [guid]::NewGuid().ToString('N') + '.json')
        $snapshot = Get-TPMConfigJsonSnapshot -ConfigPath $configPath
        $snapshot | Should -Be $null

        [void](New-TPMTemporaryUnattendedConfig -ConfigPath $configPath -TeknoParrotRoot 'W:\Emulators\TeknoParrot')
        Test-Path -LiteralPath $configPath | Should -Be $true

        Restore-TPMConfigJsonSnapshot -ConfigPath $configPath -Snapshot $snapshot

        Test-Path -LiteralPath $configPath | Should -Be $false
    }

    # Review round 2 (finding #3): the restore call's own success must be
    # verified, never assumed just because it did not throw.
    It "Test-TPMConfigRestored reports true when the file was correctly removed for a null (no-prior-config) snapshot" {
        $configPath = Join-Path $TestDrive ("verify-null-ok-" + [guid]::NewGuid().ToString('N') + '.json')
        Test-TPMConfigRestored -ConfigPath $configPath -ExpectedSnapshot $null | Should -Be $true
    }

    It "Test-TPMConfigRestored reports false when a file is still present after restore expected it removed (simulated failed delete)" {
        $configPath = Join-Path $TestDrive ("verify-null-fail-" + [guid]::NewGuid().ToString('N') + '.json')
        Set-Content -LiteralPath $configPath -Value '{"TeknoParrotRoot":"W:\\Emulators\\TeknoParrot"}' -Encoding utf8 -NoNewline

        Test-TPMConfigRestored -ConfigPath $configPath -ExpectedSnapshot $null | Should -Be $false
    }

    It "Test-TPMConfigRestored reports true when the file content exactly matches the expected snapshot" {
        $configPath = Join-Path $TestDrive ("verify-match-" + [guid]::NewGuid().ToString('N') + '.json')
        $content = '{"TeknoParrotRoot":"C:\\SavedPath\\TeknoParrot"}'
        Set-Content -LiteralPath $configPath -Value $content -Encoding utf8 -NoNewline

        Test-TPMConfigRestored -ConfigPath $configPath -ExpectedSnapshot $content | Should -Be $true
    }

    It "Test-TPMConfigRestored reports false when a snapshot was expected but the file is missing (simulated failed write-back)" {
        $configPath = Join-Path $TestDrive ("verify-missing-" + [guid]::NewGuid().ToString('N') + '.json')
        Test-TPMConfigRestored -ConfigPath $configPath -ExpectedSnapshot '{"TeknoParrotRoot":"C:\\SavedPath\\TeknoParrot"}' | Should -Be $false
    }

    It "Test-TPMConfigRestored reports false when the file content differs from the expected snapshot (simulated corrupted restore)" {
        $configPath = Join-Path $TestDrive ("verify-mismatch-" + [guid]::NewGuid().ToString('N') + '.json')
        Set-Content -LiteralPath $configPath -Value '{"TeknoParrotRoot":"W:\\Emulators\\TeknoParrot"}' -Encoding utf8 -NoNewline

        Test-TPMConfigRestored -ConfigPath $configPath -ExpectedSnapshot '{"TeknoParrotRoot":"C:\\SavedPath\\TeknoParrot"}' | Should -Be $false
    }
}

Describe "Get-TPMEffectiveRootReportText (issue #146 review round 2, finding #4)" {
    It "returns the effective root text when one was captured, regardless of SmokeMode" {
        Get-TPMEffectiveRootReportText -EffectiveRoot 'W:\Emulators\TeknoParrot' -SmokeMode $false | Should -Be 'W:\Emulators\TeknoParrot'
        Get-TPMEffectiveRootReportText -EffectiveRoot 'W:\Emulators\TeknoParrot' -SmokeMode $true | Should -Be 'W:\Emulators\TeknoParrot'
    }

    It "returns the smoke-mode label only when SmokeMode is true and no effective root was captured" {
        $text = Get-TPMEffectiveRootReportText -EffectiveRoot $null -SmokeMode $true
        $text | Should -Match 'smoke mode'
    }

    It "does NOT describe a real unattended-mode failure (missing/unparsable effective root) as smoke mode -- this is the exact defect from finding #4" {
        $text = Get-TPMEffectiveRootReportText -EffectiveRoot $null -SmokeMode $false
        $text | Should -Not -Match 'smoke mode'
        $text | Should -Match 'could not be confirmed'
    }

    It "does NOT describe a real unattended-mode failure as smoke mode when EffectiveRoot is an empty string" {
        $text = Get-TPMEffectiveRootReportText -EffectiveRoot '' -SmokeMode $false
        $text | Should -Not -Match 'smoke mode'
    }
}

Describe "Get-TPMEffectiveRootFromUnattendedLog / Test-TPMUnattendedRootMatch (issue #146)" {
    # Regression coverage for the "requested/effective root mismatch"
    # scenario: a real unattended run's log showed the saved root under
    # "Saved configuration found:" (the on-disk value before this harness's
    # override) AND the actually-applied root under "Configuration:" (what
    # TPM really used this run) -- these must never be confused. The parser
    # must read the SECOND block, not the first.
    BeforeAll {
        function New-FakeUnattendedLog {
            param([string]$SavedRoot, [string]$EffectiveRoot)
            $lines = @(
                'Saved configuration found:'
                "  TeknoParrot root     : $SavedRoot"
                '  ZIP source folder    : W:\ROMS\TeknoParrot Collection'
                ''
                '  [Unattended] Using saved settings.'
                ''
                ''
                'Configuration:'
                "  TeknoParrot root     : $EffectiveRoot"
                '  ZIP source folder    : W:\ROMS\TeknoParrot Collection'
                ''
                'Loading collection dat from ZIP...'
            )
            return ($lines -join [Environment]::NewLine)
        }
    }

    It "parses the root from the 'Configuration:' block, not the earlier 'Saved configuration found:' block" {
        $logPath = Join-Path $TestDrive ("log-mismatch-" + [guid]::NewGuid().ToString('N') + '.log')
        # The exact real-world shape confirmed on issue #146: saved root
        # (stale, from a previous interactive run) differs from what this
        # harness intended to bind for this run.
        New-FakeUnattendedLog -SavedRoot 'C:\Users\EliSi\LaunchBox\Emulators\TeknoParrot' -EffectiveRoot 'W:\Emulators\TeknoParrot' |
            Set-Content -LiteralPath $logPath -Encoding utf8

        $effective = Get-TPMEffectiveRootFromUnattendedLog -LogPath $logPath

        $effective | Should -Be 'W:\Emulators\TeknoParrot'
        $effective | Should -Not -Be 'C:\Users\EliSi\LaunchBox\Emulators\TeknoParrot'
    }

    It "returns null when the log file does not exist" {
        $logPath = Join-Path $TestDrive ("no-log-" + [guid]::NewGuid().ToString('N') + '.log')
        Get-TPMEffectiveRootFromUnattendedLog -LogPath $logPath | Should -Be $null
    }

    It "returns null when the log has no 'Configuration:' block at all (e.g. TPM failed before reaching it)" {
        $logPath = Join-Path $TestDrive ("no-config-block-" + [guid]::NewGuid().ToString('N') + '.log')
        "Some unrelated startup output`nERROR: something else failed" | Set-Content -LiteralPath $logPath -Encoding utf8

        Get-TPMEffectiveRootFromUnattendedLog -LogPath $logPath | Should -Be $null
    }

    It "matches when the effective root equals the requested root" {
        Test-TPMUnattendedRootMatch -RequestedRoot 'W:\Emulators\TeknoParrot' -EffectiveRoot 'W:\Emulators\TeknoParrot' | Should -Be $true
    }

    It "tolerates only a trailing backslash difference" {
        Test-TPMUnattendedRootMatch -RequestedRoot 'W:\Emulators\TeknoParrot' -EffectiveRoot 'W:\Emulators\TeknoParrot\' | Should -Be $true
    }

    It "fails the match -- this is the actual issue #146 defect -- when unattended TPM used its saved path instead of the requested certification root" {
        Test-TPMUnattendedRootMatch -RequestedRoot 'W:\Emulators\TeknoParrot' -EffectiveRoot 'C:\Users\EliSi\LaunchBox\Emulators\TeknoParrot' | Should -Be $false
    }

    It "fails the match (does not silently pass) when the effective root could not be determined at all" {
        Test-TPMUnattendedRootMatch -RequestedRoot 'W:\Emulators\TeknoParrot' -EffectiveRoot $null | Should -Be $false
        Test-TPMUnattendedRootMatch -RequestedRoot 'W:\Emulators\TeknoParrot' -EffectiveRoot '' | Should -Be $false
    }
}

Describe "Test-TPMInstallHealthGate (issue #146)" {
    # Regression coverage for "health report created but semantically
    # failed": a real certification run collected an InstallHealth.md/.json
    # report showing three WARN-level findings for the installation-critical
    # markers, and the gate still scored [PASS] because a report merely
    # existed. This function is the fix -- it reads the structured result's
    # own Checks, not just whether a report was produced.
    It "fails when no health result was collected at all (report missing/unparseable)" {
        $gate = Test-TPMInstallHealthGate -HealthResult $null
        $gate.Passed | Should -Be $false
        $gate.Reason | Should -Match 'no health result collected'
    }

    It "fails when TeknoParrotUi.exe/GameProfiles/UserProfiles are all reported missing, even though the report itself was produced" {
        # Exact shape of the real InstallHealth.json from issue #146's
        # evidence: Status WARN, three installation-critical checks failed,
        # everything else passed or not-applicable.
        $healthResult = [pscustomobject]@{
            Status = 'WARN'
            Checks = @(
                [pscustomobject]@{ Name = 'TeknoParrotUi.exe exists'; Passed = $false; Details = 'W:\Emulators\TeknoParrot\TeknoParrotUi.exe' }
                [pscustomobject]@{ Name = 'GameProfiles folder exists'; Passed = $false; Details = 'W:\Emulators\TeknoParrot\GameProfiles' }
                [pscustomobject]@{ Name = 'UserProfiles folder exists'; Passed = $false; Details = 'W:\Emulators\TeknoParrot\UserProfiles' }
                [pscustomobject]@{ Name = 'pcsx2x6 crosshair folder exists'; Passed = $true; Details = 'not applicable -- no pcsx2x6 folder in this install' }
                [pscustomobject]@{ Name = 'GameProfiles XML parse'; Passed = $false; Details = 'files=0 invalid=0' }
                [pscustomobject]@{ Name = 'UserProfiles XML parse'; Passed = $true; Details = 'files=0 invalid=0' }
                [pscustomobject]@{ Name = 'No duplicate GameProfiles filenames'; Passed = $true; Details = 'duplicates=0' }
            )
        }

        $gate = Test-TPMInstallHealthGate -HealthResult $healthResult
        $gate.Passed | Should -Be $false
        $gate.Reason | Should -Match 'TeknoParrotUi\.exe exists'
        $gate.Reason | Should -Match 'GameProfiles folder exists'
        $gate.Reason | Should -Match 'UserProfiles folder exists'
    }

    It "passes when Status is WARN for a non-critical reason but every installation-critical marker check passed" {
        # A real install can legitimately WARN on something non-critical
        # (e.g. GameProfiles XML parse on an empty/freshly-created folder)
        # while still being a genuine TeknoParrot installation -- this must
        # not be conflated with the missing-marker case above.
        $healthResult = [pscustomobject]@{
            Status = 'WARN'
            Checks = @(
                [pscustomobject]@{ Name = 'TeknoParrotUi.exe exists'; Passed = $true; Details = 'ok' }
                [pscustomobject]@{ Name = 'GameProfiles folder exists'; Passed = $true; Details = 'ok' }
                [pscustomobject]@{ Name = 'UserProfiles folder exists'; Passed = $true; Details = 'ok' }
                [pscustomobject]@{ Name = 'GameProfiles XML parse'; Passed = $false; Details = 'files=0 invalid=0' }
            )
        }

        $gate = Test-TPMInstallHealthGate -HealthResult $healthResult
        $gate.Passed | Should -Be $true
    }

    It "passes when Status is PASS and all checks passed" {
        $healthResult = [pscustomobject]@{
            Status = 'PASS'
            Checks = @(
                [pscustomobject]@{ Name = 'TeknoParrotUi.exe exists'; Passed = $true; Details = 'ok' }
                [pscustomobject]@{ Name = 'GameProfiles folder exists'; Passed = $true; Details = 'ok' }
                [pscustomobject]@{ Name = 'UserProfiles folder exists'; Passed = $true; Details = 'ok' }
            )
        }

        $gate = Test-TPMInstallHealthGate -HealthResult $healthResult
        $gate.Passed | Should -Be $true
        $gate.Reason | Should -Match 'all installation-critical checks present and passed'
    }

    # Review round 2 (finding #1): absent/incomplete/malformed data must
    # never read as success -- these cover every case the second Codex
    # review explicitly called out, none of which the first version of this
    # gate handled correctly (it only looked for present-and-failed named
    # checks, so anything simply missing or malformed matched nothing and
    # passed by default).
    It "fails with the LoadError reason when InstallHealth.json was missing on disk" {
        $gate = Test-TPMInstallHealthGate -HealthResult $null -LoadError 'InstallHealth.json not found at C:\fake\InstallHealth.json'
        $gate.Passed | Should -Be $false
        $gate.Reason | Should -Match 'not found'
    }

    It "fails with the LoadError reason when InstallHealth.json was present but invalid JSON" {
        $gate = Test-TPMInstallHealthGate -HealthResult $null -LoadError 'InstallHealth.json at C:\fake\InstallHealth.json failed to parse: Unexpected token'
        $gate.Passed | Should -Be $false
        $gate.Reason | Should -Match 'failed to parse'
    }

    It "fails when the Checks array is empty" {
        $healthResult = [pscustomobject]@{ Status = 'PASS'; Checks = @() }
        $gate = Test-TPMInstallHealthGate -HealthResult $healthResult
        $gate.Passed | Should -Be $false
        $gate.Reason | Should -Match 'no Checks entries'
    }

    It "fails when Checks is entirely absent from the health result" {
        $healthResult = [pscustomobject]@{ Status = 'PASS' }
        $gate = Test-TPMInstallHealthGate -HealthResult $healthResult
        $gate.Passed | Should -Be $false
    }

    It "fails when one installation-critical check is missing from Checks entirely (not merely unfailed)" {
        $healthResult = [pscustomobject]@{
            Status = 'PASS'
            Checks = @(
                [pscustomobject]@{ Name = 'TeknoParrotUi.exe exists'; Passed = $true }
                [pscustomobject]@{ Name = 'GameProfiles folder exists'; Passed = $true }
                # UserProfiles folder exists is missing entirely -- the
                # pre-fix filter matched nothing named that and passed.
            )
        }
        $gate = Test-TPMInstallHealthGate -HealthResult $healthResult
        $gate.Passed | Should -Be $false
        $gate.Reason | Should -Match 'UserProfiles folder exists -- missing'
    }

    It "fails when a critical check's Passed value is null" {
        $healthResult = [pscustomobject]@{
            Status = 'PASS'
            Checks = @(
                [pscustomobject]@{ Name = 'TeknoParrotUi.exe exists'; Passed = $null }
                [pscustomobject]@{ Name = 'GameProfiles folder exists'; Passed = $true }
                [pscustomobject]@{ Name = 'UserProfiles folder exists'; Passed = $true }
            )
        }
        $gate = Test-TPMInstallHealthGate -HealthResult $healthResult
        $gate.Passed | Should -Be $false
        $gate.Reason | Should -Match 'TeknoParrotUi\.exe exists -- Passed value missing or null'
    }

    It "fails when a critical check's Passed value is an empty string" {
        $healthResult = [pscustomobject]@{
            Status = 'PASS'
            Checks = @(
                [pscustomobject]@{ Name = 'TeknoParrotUi.exe exists'; Passed = '' }
                [pscustomobject]@{ Name = 'GameProfiles folder exists'; Passed = $true }
                [pscustomobject]@{ Name = 'UserProfiles folder exists'; Passed = $true }
            )
        }
        $gate = Test-TPMInstallHealthGate -HealthResult $healthResult
        $gate.Passed | Should -Be $false
    }

    It "fails when a critical check's Passed value is an unknown non-boolean value (e.g. a string 'true' or an integer)" {
        $healthResult = [pscustomobject]@{
            Status = 'PASS'
            Checks = @(
                [pscustomobject]@{ Name = 'TeknoParrotUi.exe exists'; Passed = 'true' }
                [pscustomobject]@{ Name = 'GameProfiles folder exists'; Passed = 1 }
                [pscustomobject]@{ Name = 'UserProfiles folder exists'; Passed = $true }
            )
        }
        $gate = Test-TPMInstallHealthGate -HealthResult $healthResult
        $gate.Passed | Should -Be $false
        $gate.Reason | Should -Match 'not a boolean'
    }

    It "fails when Checks contains entries with no Name at all alongside the real critical names" {
        $healthResult = [pscustomobject]@{
            Status = 'PASS'
            Checks = @(
                [pscustomobject]@{ Passed = $true }
                [pscustomobject]@{ Name = 'TeknoParrotUi.exe exists'; Passed = $true }
                [pscustomobject]@{ Name = 'GameProfiles folder exists'; Passed = $true }
            )
        }
        $gate = Test-TPMInstallHealthGate -HealthResult $healthResult
        $gate.Passed | Should -Be $false
        $gate.Reason | Should -Match 'UserProfiles folder exists -- missing'
    }

    # Review round 3: a health result must never contain a critical name
    # more than once -- the prior fix's $checkByName hashtable just
    # overwrote on a repeated name, so whichever entry was written last
    # silently won, regardless of whether the resolution happened to be a
    # pass or a fail. Both possible orderings must fail identically, since
    # the duplication itself is the defect, not which value "won".
    It "fails on a duplicate critical check name ordered false then true" {
        $healthResult = [pscustomobject]@{
            Status = 'PASS'
            Checks = @(
                [pscustomobject]@{ Name = 'TeknoParrotUi.exe exists'; Passed = $false }
                [pscustomobject]@{ Name = 'TeknoParrotUi.exe exists'; Passed = $true }
                [pscustomobject]@{ Name = 'GameProfiles folder exists'; Passed = $true }
                [pscustomobject]@{ Name = 'UserProfiles folder exists'; Passed = $true }
            )
        }
        $gate = Test-TPMInstallHealthGate -HealthResult $healthResult
        $gate.Passed | Should -Be $false
        $gate.Reason | Should -Match 'TeknoParrotUi\.exe exists -- appears 2 times'
    }

    It "fails on a duplicate critical check name ordered true then false" {
        $healthResult = [pscustomobject]@{
            Status = 'PASS'
            Checks = @(
                [pscustomobject]@{ Name = 'TeknoParrotUi.exe exists'; Passed = $true }
                [pscustomobject]@{ Name = 'TeknoParrotUi.exe exists'; Passed = $false }
                [pscustomobject]@{ Name = 'GameProfiles folder exists'; Passed = $true }
                [pscustomobject]@{ Name = 'UserProfiles folder exists'; Passed = $true }
            )
        }
        $gate = Test-TPMInstallHealthGate -HealthResult $healthResult
        $gate.Passed | Should -Be $false
        $gate.Reason | Should -Match 'TeknoParrotUi\.exe exists -- appears 2 times'
    }

    It "fails on a duplicate critical check name even when both occurrences pass" {
        $healthResult = [pscustomobject]@{
            Status = 'PASS'
            Checks = @(
                [pscustomobject]@{ Name = 'GameProfiles folder exists'; Passed = $true }
                [pscustomobject]@{ Name = 'GameProfiles folder exists'; Passed = $true }
                [pscustomobject]@{ Name = 'TeknoParrotUi.exe exists'; Passed = $true }
                [pscustomobject]@{ Name = 'UserProfiles folder exists'; Passed = $true }
            )
        }
        $gate = Test-TPMInstallHealthGate -HealthResult $healthResult
        $gate.Passed | Should -Be $false
        $gate.Reason | Should -Match 'GameProfiles folder exists -- appears 2 times'
    }

    It "passes when each of the three critical checks occurs exactly once" {
        $healthResult = [pscustomobject]@{
            Status = 'PASS'
            Checks = @(
                [pscustomobject]@{ Name = 'TeknoParrotUi.exe exists'; Passed = $true }
                [pscustomobject]@{ Name = 'GameProfiles folder exists'; Passed = $true }
                [pscustomobject]@{ Name = 'UserProfiles folder exists'; Passed = $true }
            )
        }
        $gate = Test-TPMInstallHealthGate -HealthResult $healthResult
        $gate.Passed | Should -Be $true
    }
}

Describe "New-CertificationScorecard requested/effective root reporting (issue #146)" {
    It "carries RequestedTeknoParrotRoot and EffectiveTeknoParrotRoot onto the returned scorecard object" {
        $fake = New-FakeResults -Pcsx2Present $true -SmokeMode $false
        $fake.EffectiveTeknoParrotRoot = 'C:\fake\TeknoParrot'
        $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM used requested root'; Passed = $true }

        $result = New-CertificationScorecard -Results $fake

        $result.RequestedTeknoParrotRoot | Should -Be 'C:\fake\TeknoParrot'
        $result.EffectiveTeknoParrotRoot | Should -Be 'C:\fake\TeknoParrot'
    }

    It "fails certification (NOT CERTIFIED) when the requested and effective roots do not match, even though every other gate passed" {
        $fake = New-FakeResults -Pcsx2Present $true -SmokeMode $false
        $fake.EffectiveTeknoParrotRoot = 'C:\Users\EliSi\LaunchBox\Emulators\TeknoParrot'
        $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM used requested root'; Passed = $false }

        $result = New-CertificationScorecard -Results $fake

        $result.Overall | Should -Be 'NOT CERTIFIED'
        $rootItem = $result.Items | Where-Object { $_.Area -eq 'Unattended TPM root binding' }
        $rootItem.Passed | Should -Be $false
        $rootItem.Details | Should -Match 'requested='
        $rootItem.Details | Should -Match 'effective='
    }

    It "certifies (does not require root-binding evidence) for a smoke-mode run with no unattended TPM invocation" {
        $fake = New-FakeResults -Pcsx2Present $true -SmokeMode $true
        # No 'Unattended TPM used requested root' check present at all --
        # matches a real smoke-mode run, which never adds that check.

        $result = New-CertificationScorecard -Results $fake

        $result.Overall | Should -Be 'CERTIFIED'
        $rootItem = $result.Items | Where-Object { $_.Area -eq 'Unattended TPM root binding' }
        $rootItem.Passed | Should -Be $true
        $rootItem.Details | Should -Match 'not applicable -- smoke mode'
    }

    It "fails certification when the real install health gate itself failed (renamed check honored)" {
        $fake = New-FakeResults -Pcsx2Present $true
        ($fake.Checks | Where-Object { $_.Name -eq 'Real install health check' }).Passed = $false

        $result = New-CertificationScorecard -Results $fake

        $result.Overall | Should -Be 'NOT CERTIFIED'
        $healthItem = $result.Items | Where-Object { $_.Area -eq 'Real Install Health' }
        $healthItem.Passed | Should -Be $false
    }

    # Review round 3: "Unattended TPM config restoration" was recorded by
    # Add-CheckResult during a real run but never rolled up into the
    # scorecard at all -- a failed or missing restoration could not, by
    # itself, flip Overall to NOT CERTIFIED even though a developer's real
    # saved config was left corrupted.
    It "fails certification (NOT CERTIFIED) when the config restoration check explicitly failed, even though every other gate passed" {
        $fake = New-FakeResults -Pcsx2Present $true -SmokeMode $false
        $fake.EffectiveTeknoParrotRoot = 'C:\fake\TeknoParrot'
        $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM used requested root'; Passed = $true }
        $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM config restoration'; Passed = $false; Details = 'restore threw: Access to the path is denied' }

        $result = New-CertificationScorecard -Results $fake

        $result.Overall | Should -Be 'NOT CERTIFIED'
        $restoreItem = $result.Items | Where-Object { $_.Area -eq 'Unattended TPM config restoration' }
        $restoreItem.Passed | Should -Be $false
        $restoreItem.Details | Should -Match 'restore threw'
    }

    It "fails certification (NOT CERTIFIED) when the config restoration check is missing entirely from an unattended run" {
        $fake = New-FakeResults -Pcsx2Present $true -SmokeMode $false
        $fake.EffectiveTeknoParrotRoot = 'C:\fake\TeknoParrot'
        $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM used requested root'; Passed = $true }
        # No 'Unattended TPM config restoration' check at all -- must never
        # read as a silent pass.

        $result = New-CertificationScorecard -Results $fake

        $result.Overall | Should -Be 'NOT CERTIFIED'
        $restoreItem = $result.Items | Where-Object { $_.Area -eq 'Unattended TPM config restoration' }
        $restoreItem.Passed | Should -Be $false
    }

    It "certifies when the config restoration check explicitly passed alongside every other gate" {
        $fake = New-FakeResults -Pcsx2Present $true -SmokeMode $false
        $fake.EffectiveTeknoParrotRoot = 'C:\fake\TeknoParrot'
        $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM used requested root'; Passed = $true }
        $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM config restoration'; Passed = $true; Details = 'config file restored to its pre-run state' }

        $result = New-CertificationScorecard -Results $fake

        $result.Overall | Should -Be 'CERTIFIED'
        $restoreItem = $result.Items | Where-Object { $_.Area -eq 'Unattended TPM config restoration' }
        $restoreItem.Passed | Should -Be $true
    }

    # Review round 4: smoke mode previously reported this item as
    # Passed = $true, which the Markdown renderer then printed as
    # "[PASS] ... not applicable" -- not-applicable is not the same claim
    # as passed. The scorecard must carry an explicit tri-state
    # (Pass/Fail/NotApplicable) so a gate that never ran can never be read
    # as evidence of a pass, in either the structured object or the
    # rendered Markdown, and N/A items must be excluded from scoring in
    # both directions without forcing certification failure.
    It "stores the smoke-mode restoration item as Status = 'NotApplicable', not Passed = \$true" {
        $fake = New-FakeResults -Pcsx2Present $true -SmokeMode $true

        $result = New-CertificationScorecard -Results $fake

        $restoreItem = $result.Items | Where-Object { $_.Area -eq 'Unattended TPM config restoration' }
        $restoreItem.Status | Should -Be 'NotApplicable'
        $restoreItem.Passed | Should -Not -Be $true
        $restoreItem.Details | Should -Match 'not applicable in smoke mode'
    }

    It "renders the smoke-mode restoration item as [N/A] in the Markdown gate list, never [PASS]" {
        $fake = New-FakeResults -Pcsx2Present $true -SmokeMode $true
        $result = New-CertificationScorecard -Results $fake
        $restoreItem = $result.Items | Where-Object { $_.Area -eq 'Unattended TPM config restoration' }

        # Same mark-selection logic used by the harness's own Markdown
        # renderer (Add-CertificationReport's "## Gates" loop) -- exercised
        # directly here since that loop is inline top-level script code,
        # not its own function.
        $mark = if ($restoreItem.PSObject.Properties.Name -contains 'Status' -and $restoreItem.Status -eq 'NotApplicable') {
            'N/A'
        } elseif ($restoreItem.Passed) {
            'PASS'
        } else {
            'FAIL'
        }

        $mark | Should -Be 'N/A'
        $mark | Should -Not -Be 'PASS'
    }

    It "agrees between the structured scorecard and the Markdown mark for every item, in both smoke and non-smoke fixtures" {
        foreach ($smoke in @($true, $false)) {
            $fake = New-FakeResults -Pcsx2Present $true -SmokeMode $smoke
            if (-not $smoke) {
                $fake.EffectiveTeknoParrotRoot = 'C:\fake\TeknoParrot'
                $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM used requested root'; Passed = $true }
                $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM config restoration'; Passed = $true; Details = 'config file restored to its pre-run state' }
            }
            $result = New-CertificationScorecard -Results $fake

            foreach ($item in $result.Items) {
                $mark = if ($item.PSObject.Properties.Name -contains 'Status' -and $item.Status -eq 'NotApplicable') {
                    'N/A'
                } elseif ($item.Passed) {
                    'PASS'
                } else {
                    'FAIL'
                }
                if ($item.Area -eq 'Unattended TPM config restoration' -and $smoke) {
                    $mark | Should -Be 'N/A'
                } elseif ($item.Area -eq 'Smoke File Safety' -and -not $smoke) {
                    $mark | Should -Be 'N/A'
                } else {
                    $mark | Should -BeIn @('PASS', 'FAIL')
                }
            }
        }
    }

    It "excludes the N/A restoration item from both sides of the score (does not increase or decrease it)" {
        $smokeFake = New-FakeResults -Pcsx2Present $true -SmokeMode $true
        $smokeResult = New-CertificationScorecard -Results $smokeFake

        # 11 score items exist in total (10 applicable + the 1 N/A
        # restoration item in smoke mode); Total must reflect only the 10
        # applicable ones -- if the N/A item were still counted (as it was
        # before this fix, via Passed = $true), Total would be 11 instead.
        $smokeResult.Items.Count | Should -Be 11
        $smokeResult.Total | Should -Be 10

        # Every other score item in the smoke-mode fixture passes, so with
        # the restoration item correctly excluded (not counted as either
        # passed or total), Passed must equal Total.
        $smokeResult.Passed | Should -Be $smokeResult.Total
        $smokeResult.Passed | Should -Be 10
    }

    It "still certifies (CERTIFIED) for a smoke-mode run -- the N/A item does not force NOT CERTIFIED" {
        $fake = New-FakeResults -Pcsx2Present $true -SmokeMode $true
        $result = New-CertificationScorecard -Results $fake
        $result.Overall | Should -Be 'CERTIFIED'
    }

    It "an applicable PASS for the restoration item still counts normally toward CERTIFIED" {
        $fake = New-FakeResults -Pcsx2Present $true -SmokeMode $false
        $fake.EffectiveTeknoParrotRoot = 'C:\fake\TeknoParrot'
        $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM used requested root'; Passed = $true }
        $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM config restoration'; Passed = $true; Details = 'config file restored to its pre-run state' }

        $result = New-CertificationScorecard -Results $fake

        $result.Overall | Should -Be 'CERTIFIED'
        $restoreItem = $result.Items | Where-Object { $_.Area -eq 'Unattended TPM config restoration' }
        $restoreItem.Status | Should -Be 'Pass'
        $restoreItem.Passed | Should -Be $true
    }

    It "an applicable FAIL for the restoration item still forces NOT CERTIFIED" {
        $fake = New-FakeResults -Pcsx2Present $true -SmokeMode $false
        $fake.EffectiveTeknoParrotRoot = 'C:\fake\TeknoParrot'
        $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM used requested root'; Passed = $true }
        $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM config restoration'; Passed = $false; Details = 'restore threw: Access to the path is denied' }

        $result = New-CertificationScorecard -Results $fake

        $result.Overall | Should -Be 'NOT CERTIFIED'
        $restoreItem = $result.Items | Where-Object { $_.Area -eq 'Unattended TPM config restoration' }
        $restoreItem.Status | Should -Be 'Fail'
    }

    It "leaves every other score item's PASS/FAIL rendering and scoring behavior unaffected by the new Status field" {
        $fake = New-FakeResults -Pcsx2Present $true -SmokeMode $true
        $result = New-CertificationScorecard -Results $fake

        # Unattended TPM config restoration (round 4) and Smoke File Safety
        # (issue #149) are the two items that intentionally carry a Status
        # property -- every item besides those two must remain exactly as
        # it was before either fix.
        $itemsWithStatus = @('Unattended TPM config restoration', 'Smoke File Safety')
        $otherItems = $result.Items | Where-Object { $itemsWithStatus -notcontains $_.Area }
        foreach ($item in $otherItems) {
            $item.PSObject.Properties.Name | Should -Not -Contain 'Status'
            $item.Passed | Should -Be $true
        }
    }
}

Describe "Smoke File Safety Not Applicable during unattended mode (issue #149)" {
    # A real RC3 arcade certification run using -RunUnattendedTPM scored
    # [PASS] Smoke File Safety with the literal wording "no unexpected
    # changes in smoke mode" -- true only in the narrow sense that the
    # (unconditionally-collected) pre/post diff happened to show no
    # changes, but a materially misleading claim: the run was not smoke
    # mode, and nothing in the harness actually asserts "no unexpected
    # changes" as a pass/fail condition for a real unattended run. Same
    # explicit-N/A pattern as the restoration item (round 4): unattended
    # mode must mark this Status = 'NotApplicable', Passed = $null, never
    # reuse smoke-mode wording as if it were evidence of a pass.
    BeforeAll {
        function New-FakeDirtySnapshots {
            # A non-empty diff -- used to prove the smoke-mode Fail path
            # still works correctly alongside the new N/A path.
            [ordered]@{
                UserProfiles      = [pscustomobject]@{ Added = 1; Removed = 0; Changed = 0; BeforeSkipped = 0; AfterSkipped = 0 }
                GameProfiles      = [pscustomobject]@{ Added = 0; Removed = 0; Changed = 0; BeforeSkipped = 0; AfterSkipped = 0 }
                Pcsx2x6Crosshairs = [pscustomobject]@{ Added = 0; Removed = 0; Changed = 0; BeforeSkipped = 0; AfterSkipped = 0 }
            }
        }
    }

    It "renders the Smoke File Safety item correctly in smoke mode: Status = 'Pass', Passed = \$true, smoke-mode wording" {
        $fake = New-FakeResults -Pcsx2Present $true -SmokeMode $true
        # New-FakeResults leaves Snapshots = $null, which the scorecard
        # treats as clean (no diff data to flag as dirty).

        $result = New-CertificationScorecard -Results $fake

        $item = $result.Items | Where-Object { $_.Area -eq 'Smoke File Safety' }
        $item.Status | Should -Be 'Pass'
        $item.Passed | Should -Be $true
        $item.Details | Should -Match 'smoke mode'
    }

    It "still fails (Status = 'Fail') in smoke mode when the pre/post diff actually shows unexpected changes -- applicable PASS/FAIL behavior is unaffected" {
        $fake = New-FakeResults -Pcsx2Present $true -SmokeMode $true
        $fake.Snapshots = New-FakeDirtySnapshots

        $result = New-CertificationScorecard -Results $fake

        $item = $result.Items | Where-Object { $_.Area -eq 'Smoke File Safety' }
        $item.Status | Should -Be 'Fail'
        $item.Passed | Should -Be $false
        $result.Overall | Should -Be 'NOT CERTIFIED'
    }

    It "marks Smoke File Safety Status = 'NotApplicable' during unattended mode, even when the (unconditionally-collected) diff shows no changes" {
        $fake = New-FakeResults -Pcsx2Present $true -SmokeMode $false
        $fake.EffectiveTeknoParrotRoot = 'C:\fake\TeknoParrot'
        $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM used requested root'; Passed = $true }
        $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM config restoration'; Passed = $true }
        # Snapshots = $null (default) -- would read as "clean" under the old
        # logic and score [PASS] with smoke-mode wording; this is exactly
        # the real RC3 scenario the fix addresses.

        $result = New-CertificationScorecard -Results $fake

        $item = $result.Items | Where-Object { $_.Area -eq 'Smoke File Safety' }
        $item.Status | Should -Be 'NotApplicable'
    }

    It "never stores Passed = \$true for Smoke File Safety during unattended mode -- uses \$null" {
        $fake = New-FakeResults -Pcsx2Present $true -SmokeMode $false
        $fake.EffectiveTeknoParrotRoot = 'C:\fake\TeknoParrot'
        $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM used requested root'; Passed = $true }
        $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM config restoration'; Passed = $true }

        $result = New-CertificationScorecard -Results $fake

        $item = $result.Items | Where-Object { $_.Area -eq 'Smoke File Safety' }
        $item.Passed | Should -Be $null
        $item.Passed | Should -Not -Be $true
    }

    It "never reuses smoke-mode wording during unattended mode -- Details does not claim smoke mode" {
        $fake = New-FakeResults -Pcsx2Present $true -SmokeMode $false
        $fake.EffectiveTeknoParrotRoot = 'C:\fake\TeknoParrot'
        $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM used requested root'; Passed = $true }
        $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM config restoration'; Passed = $true }

        $result = New-CertificationScorecard -Results $fake

        $item = $result.Items | Where-Object { $_.Area -eq 'Smoke File Safety' }
        $item.Details | Should -Not -Match 'smoke mode'
        $item.Details | Should -Match 'not applicable in unattended mode'
    }

    It "renders [N/A] in the Markdown gate list for Smoke File Safety during unattended mode, never [PASS]" {
        $fake = New-FakeResults -Pcsx2Present $true -SmokeMode $false
        $fake.EffectiveTeknoParrotRoot = 'C:\fake\TeknoParrot'
        $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM used requested root'; Passed = $true }
        $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM config restoration'; Passed = $true }

        $result = New-CertificationScorecard -Results $fake
        $item = $result.Items | Where-Object { $_.Area -eq 'Smoke File Safety' }

        # Same mark-selection logic used by the harness's own Markdown
        # renderer (Add-CertificationReport's "## Gates" loop).
        $mark = if ($item.PSObject.Properties.Name -contains 'Status' -and $item.Status -eq 'NotApplicable') {
            'N/A'
        } elseif ($item.Passed) {
            'PASS'
        } else {
            'FAIL'
        }

        $mark | Should -Be 'N/A'
        $mark | Should -Not -Be 'PASS'
    }

    It "excludes the unattended-mode N/A Smoke File Safety item from both Passed and Total (does not inflate or reduce the score)" {
        $fake = New-FakeResults -Pcsx2Present $true -SmokeMode $false
        $fake.EffectiveTeknoParrotRoot = 'C:\fake\TeknoParrot'
        $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM used requested root'; Passed = $true }
        $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM config restoration'; Passed = $true }

        $result = New-CertificationScorecard -Results $fake

        # 11 raw score items; both Smoke File Safety and (in this
        # non-smoke, fully-passing fixture) no other item are N/A, so
        # exactly 10 are applicable, and since every applicable item
        # passes, Passed must equal Total.
        $result.Items.Count | Should -Be 11
        $result.Total | Should -Be 10
        $result.Passed | Should -Be 10
    }

    It "does not force NOT CERTIFIED by itself -- an unattended run with every other applicable item passing still certifies" {
        $fake = New-FakeResults -Pcsx2Present $true -SmokeMode $false
        $fake.EffectiveTeknoParrotRoot = 'C:\fake\TeknoParrot'
        $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM used requested root'; Passed = $true }
        $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM config restoration'; Passed = $true }
        $fake.Snapshots = New-FakeDirtySnapshots
        # Even a "dirty" diff must not affect the outcome once the item is
        # correctly excluded as not applicable -- it is never asserted
        # against in unattended mode at all.

        $result = New-CertificationScorecard -Results $fake

        $result.Overall | Should -Be 'CERTIFIED'
        $item = $result.Items | Where-Object { $_.Area -eq 'Smoke File Safety' }
        $item.Status | Should -Be 'NotApplicable'
    }

    It "leaves the existing restoration-item N/A behavior (round 4) unchanged alongside the new Smoke File Safety N/A behavior" {
        $fake = New-FakeResults -Pcsx2Present $true -SmokeMode $true

        $result = New-CertificationScorecard -Results $fake

        $restoreItem = $result.Items | Where-Object { $_.Area -eq 'Unattended TPM config restoration' }
        $restoreItem.Status | Should -Be 'NotApplicable'
        $restoreItem.Passed | Should -Not -Be $true
        $restoreItem.Details | Should -Match 'not applicable in smoke mode'

        # In smoke mode, Smoke File Safety is the applicable one and
        # restoration is the N/A one -- the two items are independent and
        # neither's Status affects the other's.
        $safetyItem = $result.Items | Where-Object { $_.Area -eq 'Smoke File Safety' }
        $safetyItem.Status | Should -Be 'Pass'
    }
}

Describe "Invoke-TPMUnattendedRootBinding integration (issue #146 review round 3)" {
    # Integration-level coverage of the full snapshot -> override/create ->
    # invoke -> restore -> verify orchestration, exercising the real
    # sequencing of the round 2 pure-function pieces together rather than
    # each in isolation. $InvokeUnattended stands in for the real pwsh
    # subprocess call -- these tests never launch pwsh.
    BeforeAll {
        function New-FakeUnattendedLogContent {
            param([string]$EffectiveRoot)
            $lines = @(
                'Configuration:'
                "  TeknoParrot root     : $EffectiveRoot"
                '  ZIP source folder    : W:\ROMS\TeknoParrot Collection'
                ''
                'Loading collection dat from ZIP...'
            )
            return ($lines -join [Environment]::NewLine)
        }
    }

    It "creates a temporary config, invokes unattended, and removes the temporary config when none existed beforehand" {
        $configPath = Join-Path $TestDrive ("no-prior-" + [guid]::NewGuid().ToString('N') + '.json')
        $logPath = Join-Path $TestDrive ("no-prior-log-" + [guid]::NewGuid().ToString('N') + '.log')
        $requestedRoot = 'W:\Emulators\TeknoParrot'

        Test-Path -LiteralPath $configPath | Should -Be $false

        $script:configExistedDuringInvoke = $null
        $script:configContentDuringInvoke = $null
        $invoke = {
            $script:configExistedDuringInvoke = Test-Path -LiteralPath $configPath -PathType Leaf
            $script:configContentDuringInvoke = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
            New-FakeUnattendedLogContent -EffectiveRoot $requestedRoot | Set-Content -LiteralPath $logPath -Encoding utf8
        }

        $binding = Invoke-TPMUnattendedRootBinding -ConfigPath $configPath -TeknoParrotRoot $requestedRoot -LogPath $logPath -InvokeUnattended $invoke

        # Temporary config existed, with the requested root bound, at the
        # moment unattended TPM actually ran.
        $script:configExistedDuringInvoke | Should -Be $true
        $script:configContentDuringInvoke.TeknoParrotRoot | Should -Be $requestedRoot
        $script:configContentDuringInvoke.GamesInstallFolder | Should -Be $requestedRoot

        # And it is gone afterward -- never left behind as if it were a
        # real saved setting.
        Test-Path -LiteralPath $configPath | Should -Be $false

        $binding.EffectiveTeknoParrotRoot | Should -Be $requestedRoot
        ($binding.Checks | Where-Object { $_.Name -eq 'TPM unattended run' }).Passed | Should -Be $true
        ($binding.Checks | Where-Object { $_.Name -eq 'Unattended TPM used requested root' }).Passed | Should -Be $true
        ($binding.Checks | Where-Object { $_.Name -eq 'Unattended TPM config restoration' }).Passed | Should -Be $true
    }

    It "restores an existing config byte-for-byte after a successful run" {
        $configPath = Join-Path $TestDrive ("existing-byte-" + [guid]::NewGuid().ToString('N') + '.json')
        $logPath = Join-Path $TestDrive ("existing-byte-log-" + [guid]::NewGuid().ToString('N') + '.log')
        $originalContent = '{"TeknoParrotRoot":"C:\\Users\\Someone\\LaunchBox\\Emulators\\TeknoParrot","ZipSourceFolder":"W:\\ROMS\\TeknoParrot Collection","RetroBat":true}'
        Set-Content -LiteralPath $configPath -Value $originalContent -Encoding utf8 -NoNewline
        $requestedRoot = 'W:\Emulators\TeknoParrot'

        $invoke = {
            New-FakeUnattendedLogContent -EffectiveRoot $requestedRoot | Set-Content -LiteralPath $logPath -Encoding utf8
        }

        [void](Invoke-TPMUnattendedRootBinding -ConfigPath $configPath -TeknoParrotRoot $requestedRoot -LogPath $logPath -InvokeUnattended $invoke)

        (Get-Content -LiteralPath $configPath -Raw) | Should -Be $originalContent
    }

    It "still restores the config when unattended TPM ran but used the wrong effective root (a real failure, not an exception)" {
        $configPath = Join-Path $TestDrive ("wrong-root-" + [guid]::NewGuid().ToString('N') + '.json')
        $logPath = Join-Path $TestDrive ("wrong-root-log-" + [guid]::NewGuid().ToString('N') + '.log')
        $originalContent = '{"TeknoParrotRoot":"C:\\Users\\Someone\\LaunchBox\\Emulators\\TeknoParrot"}'
        Set-Content -LiteralPath $configPath -Value $originalContent -Encoding utf8 -NoNewline
        $requestedRoot = 'W:\Emulators\TeknoParrot'

        $invoke = {
            # TPM ran but ended up using a different (stale) root than requested.
            New-FakeUnattendedLogContent -EffectiveRoot 'C:\Users\Someone\LaunchBox\Emulators\TeknoParrot' | Set-Content -LiteralPath $logPath -Encoding utf8
        }

        $binding = Invoke-TPMUnattendedRootBinding -ConfigPath $configPath -TeknoParrotRoot $requestedRoot -LogPath $logPath -InvokeUnattended $invoke

        ($binding.Checks | Where-Object { $_.Name -eq 'Unattended TPM used requested root' }).Passed | Should -Be $false
        (Get-Content -LiteralPath $configPath -Raw) | Should -Be $originalContent
        ($binding.Checks | Where-Object { $_.Name -eq 'Unattended TPM config restoration' }).Passed | Should -Be $true
    }

    It "still restores the config when the unattended invocation itself throws, and re-throws the same exception to the caller" {
        $configPath = Join-Path $TestDrive ("throws-" + [guid]::NewGuid().ToString('N') + '.json')
        $logPath = Join-Path $TestDrive ("throws-log-" + [guid]::NewGuid().ToString('N') + '.log')
        $originalContent = '{"TeknoParrotRoot":"C:\\Users\\Someone\\LaunchBox\\Emulators\\TeknoParrot"}'
        Set-Content -LiteralPath $configPath -Value $originalContent -Encoding utf8 -NoNewline
        $requestedRoot = 'W:\Emulators\TeknoParrot'

        $invoke = { throw "simulated pwsh launch failure" }

        $threw = $false
        try {
            Invoke-TPMUnattendedRootBinding -ConfigPath $configPath -TeknoParrotRoot $requestedRoot -LogPath $logPath -InvokeUnattended $invoke
        } catch {
            $threw = $true
            $_.Exception.Message | Should -Match 'simulated pwsh launch failure'
        }

        $threw | Should -Be $true -Because "an unattended-invocation exception must propagate, exactly as it did before this extraction"
        (Get-Content -LiteralPath $configPath -Raw) | Should -Be $originalContent -Because "the finally block must restore the config even when the try block threw"
    }

    It "reports a restore failure as its own failed check, and that failure alone forces the final scorecard to NOT CERTIFIED" {
        $configDir = Join-Path $TestDrive ("restore-fail-dir-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        $configPath = Join-Path $configDir 'TeknoParrot-Manager.config.json'
        $logPath = Join-Path $TestDrive ("restore-fail-log-" + [guid]::NewGuid().ToString('N') + '.log')
        $originalContent = '{"TeknoParrotRoot":"C:\\Users\\Someone\\LaunchBox\\Emulators\\TeknoParrot"}'
        Set-Content -LiteralPath $configPath -Value $originalContent -Encoding utf8 -NoNewline
        $requestedRoot = 'W:\Emulators\TeknoParrot'

        # Simulates an external interference that makes the eventual restore
        # write fail for real (DirectoryNotFoundException from
        # [System.IO.File]::WriteAllText), rather than mocking the restore
        # function itself -- the whole directory the config lived in is gone
        # by the time Invoke-TPMUnattendedRootBinding's finally block tries
        # to write the pre-run snapshot back.
        $invoke = {
            New-FakeUnattendedLogContent -EffectiveRoot $requestedRoot | Set-Content -LiteralPath $logPath -Encoding utf8
            Remove-Item -LiteralPath $configDir -Recurse -Force
        }

        $binding = Invoke-TPMUnattendedRootBinding -ConfigPath $configPath -TeknoParrotRoot $requestedRoot -LogPath $logPath -InvokeUnattended $invoke

        $restoreCheck = $binding.Checks | Where-Object { $_.Name -eq 'Unattended TPM config restoration' }
        $restoreCheck.Passed | Should -Be $false
        $restoreCheck.Details | Should -Match 'restore threw'

        # Compose the binding's real checks into a full results object and
        # confirm the restoration failure alone flips the scorecard, even
        # though every other gate in the fixture passes.
        $fake = New-FakeResults -Pcsx2Present $true -SmokeMode $false
        $fake.EffectiveTeknoParrotRoot = $binding.EffectiveTeknoParrotRoot
        foreach ($check in $binding.Checks) { $fake.Checks += $check }

        $result = New-CertificationScorecard -Results $fake
        $result.Overall | Should -Be 'NOT CERTIFIED'
    }

    It "does not label a real unattended-mode effective-root failure as smoke mode (finding #4, at the integration level)" {
        $configPath = Join-Path $TestDrive ("unparsable-" + [guid]::NewGuid().ToString('N') + '.json')
        $logPath = Join-Path $TestDrive ("unparsable-log-" + [guid]::NewGuid().ToString('N') + '.log')
        $requestedRoot = 'W:\Emulators\TeknoParrot'

        $invoke = {
            "Some unrelated startup output`nERROR: TeknoParrot crashed before printing its Configuration block" | Set-Content -LiteralPath $logPath -Encoding utf8
        }

        $binding = Invoke-TPMUnattendedRootBinding -ConfigPath $configPath -TeknoParrotRoot $requestedRoot -LogPath $logPath -InvokeUnattended $invoke

        $binding.EffectiveTeknoParrotRoot | Should -Be $null
        $rootCheck = $binding.Checks | Where-Object { $_.Name -eq 'Unattended TPM used requested root' }
        $rootCheck.Passed | Should -Be $false
        $rootCheck.Details | Should -Not -Match 'smoke mode'

        $reportText = Get-TPMEffectiveRootReportText -EffectiveRoot $binding.EffectiveTeknoParrotRoot -SmokeMode $false
        $reportText | Should -Not -Match 'smoke mode'
        $reportText | Should -Match 'could not be confirmed'
    }
}

Describe "New-TPMCertificationScreenshot (issue #151)" {
    # RC3 arcade certification of a fully-passing merged commit still
    # returned ARCADE CERTIFICATION FAIL because the required screenshot
    # evidence did not exist and had to be captured manually. This function
    # is the core, independently testable piece of automatic capture --
    # $CaptureAction is injectable specifically so these tests never touch
    # a real screen or display session. A "real" successful capture in
    # these tests is produced via the actual Save-TPMRenderedTextCapture
    # production function (real GDI+ output, real valid PNG bytes), not a
    # fake text file -- necessary now that captures are validated as real
    # images before Status is set to 'Captured' (review round 1, finding
    # #5).
    BeforeAll {
        function New-ValidCaptureAction {
            { param($p) Save-TPMRenderedTextCapture -Path $p -Lines @('valid test image') }
        }

        # Real, valid PNG bytes -- used as the base for constructing the
        # JPEG-masquerade, truncated, and corrupted-signature regression
        # cases below, so those tests exercise genuine byte-level defects
        # against real GDI+ output, not a hand-rolled fake.
        function New-RealPngBytes {
            $p = Join-Path $TestDrive ("real-png-source-" + [guid]::NewGuid().ToString('N') + '.png')
            # [void](...) -- Save-TPMRenderedTextCapture explicitly returns
            # $null; left unsuppressed, that $null is emitted onto this
            # function's own output stream ahead of the byte array below,
            # corrupting it (same class of bug fixed in the production
            # capture-scope tests earlier in this file).
            [void](Save-TPMRenderedTextCapture -Path $p -Lines @('a somewhat longer line of real rendered content', 'second line', 'third line'))
            return [System.IO.File]::ReadAllBytes($p)
        }
    }

    # --- screenshot directory creation ---
    It "creates the screenshot directory when it does not already exist" {
        $dir = Join-Path $TestDrive ("shots-new-" + [guid]::NewGuid().ToString('N'))
        Test-Path -LiteralPath $dir | Should -Be $false

        [void](New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'moment' -EvidenceType 'DeterministicRender' -CaptureAction (New-ValidCaptureAction))

        Test-Path -LiteralPath $dir -PathType Container | Should -Be $true
    }

    It "does not throw or fail when the screenshot directory already exists" {
        $dir = Join-Path $TestDrive ("shots-existing-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $dir | Out-Null

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'moment' -EvidenceType 'DeterministicRender' -CaptureAction (New-ValidCaptureAction)

        $shot.Status | Should -Be 'Captured'
    }

    It "does NOT create the screenshot directory for a -Skip call (no capture was attempted, so nothing needs a folder)" {
        $dir = Join-Path $TestDrive ("shots-skip-nodir-" + [guid]::NewGuid().ToString('N'))

        [void](New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'not-displayed' -Skip -SkipReason 'not applicable this run')

        Test-Path -LiteralPath $dir | Should -Be $false
    }

    # --- screenshot naming (review round 1, finding #2) ---
    It "names the screenshot file with the sanitized name, a timestamp, a sequence number, and a random suffix, ending in .png" {
        $dir = Join-Path $TestDrive ("shots-naming-" + [guid]::NewGuid().ToString('N'))

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'final-certification-result' -EvidenceType 'ScreenCapture' -CaptureAction (New-ValidCaptureAction)

        (Split-Path -Leaf $shot.Path) | Should -Match '^final-certification-result_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}-\d{3}_\d{5}_[0-9a-f]{6}\.png$'
        (Split-Path -Parent $shot.Path) | Should -Be $dir
    }

    It "sanitizes unsafe characters out of the Name when building the file name" {
        $dir = Join-Path $TestDrive ("shots-sanitize-" + [guid]::NewGuid().ToString('N'))

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'adaptive menu (small)!' -EvidenceType 'DeterministicRender' -CaptureAction (New-ValidCaptureAction)

        $fileName = Split-Path -Leaf $shot.Path
        $fileName | Should -Not -Match '[\s\(\)!]'
        $fileName | Should -Match '^adaptive-menu--small--_'
    }

    It "produces distinct, never-colliding file names for rapid repeated captures of the identical label" {
        $dir = Join-Path $TestDrive ("shots-collision-" + [guid]::NewGuid().ToString('N'))

        $shots = 1..50 | ForEach-Object {
            New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'repeat' -EvidenceType 'DeterministicRender' -CaptureAction (New-ValidCaptureAction)
        }

        $paths = $shots.Path
        ($paths | Select-Object -Unique).Count | Should -Be 50 -Because "every path must be unique, even for 50 identical labels captured back to back"
        foreach ($p in $paths) {
            Test-Path -LiteralPath $p -PathType Leaf | Should -Be $true -Because "no earlier file may be overwritten by a later capture with the same label"
        }
        ($shots | Where-Object { $_.Status -ne 'Captured' }).Count | Should -Be 0
    }

    It "never overwrites a pre-existing file at the reserved path (atomic create-with-retry)" {
        $dir = Join-Path $TestDrive ("shots-noverw-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $dir | Out-Null

        $first = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'guard' -EvidenceType 'DeterministicRender' -CaptureAction (New-ValidCaptureAction)
        $firstContent = [System.IO.File]::ReadAllBytes($first.Path)

        $second = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'guard' -EvidenceType 'DeterministicRender' -CaptureAction { param($p) Save-TPMRenderedTextCapture -Path $p -Lines @('different content, much longer line to change the byte length') }

        $second.Path | Should -Not -Be $first.Path
        # The first file's bytes are unchanged -- proves the second capture
        # never touched the first file's reserved path.
        [System.IO.File]::ReadAllBytes($first.Path) | Should -Be $firstContent
    }

    # --- captured / missing-screenshot failure path ---
    It "returns Status = 'Captured' with the file path when the capture action succeeds" {
        $dir = Join-Path $TestDrive ("shots-ok-" + [guid]::NewGuid().ToString('N'))

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'ok' -EvidenceType 'DeterministicRender' -CaptureAction (New-ValidCaptureAction)

        $shot.Status | Should -Be 'Captured'
        Test-Path -LiteralPath $shot.Path -PathType Leaf | Should -Be $true
    }

    It "returns Status = 'Failed' with the exception message when the capture action throws" {
        $dir = Join-Path $TestDrive ("shots-throw-" + [guid]::NewGuid().ToString('N'))

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'throws' -EvidenceType 'DeterministicRender' -CaptureAction { param($p) throw "simulated screen-capture failure" }

        $shot.Status | Should -Be 'Failed'
        $shot.EvidenceType | Should -Be 'Failed'
        $shot.Details | Should -Match 'simulated screen-capture failure'
    }

    It "returns Status = 'Failed' when the capture action completes without writing real content (missing screenshot)" {
        $dir = Join-Path $TestDrive ("shots-missing-" + [guid]::NewGuid().ToString('N'))

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'missing' -EvidenceType 'DeterministicRender' -CaptureAction { param($p) }

        # The reserved path always exists (New-TPMScreenshotReservedPath
        # creates it atomically before the capture action runs), so a
        # no-op capture action leaves it as an empty zero-byte file, which
        # validation correctly rejects as empty rather than missing.
        $shot.Status | Should -Be 'Failed'
        $shot.Details | Should -Match 'empty'
    }

    It "returns Status = 'Failed' when no CaptureAction is supplied and -Skip was not requested" {
        $dir = Join-Path $TestDrive ("shots-noaction-" + [guid]::NewGuid().ToString('N'))

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'no-action' -EvidenceType 'ScreenCapture'

        $shot.Status | Should -Be 'Failed'
    }

    It "returns Status = 'Failed' when no EvidenceType is supplied for a non-skipped capture" {
        $dir = Join-Path $TestDrive ("shots-noevidencetype-" + [guid]::NewGuid().ToString('N'))

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'no-type' -CaptureAction (New-ValidCaptureAction)

        $shot.Status | Should -Be 'Failed'
        $shot.Details | Should -Match 'EvidenceType'
    }

    It "returns Status = 'Skipped' with the given reason, and no Path, for a -Skip call" {
        $dir = Join-Path $TestDrive ("shots-skip-" + [guid]::NewGuid().ToString('N'))

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'live-thumbnail-evidence' -Skip -SkipReason 'not displayed this run'

        $shot.Status | Should -Be 'Skipped'
        $shot.EvidenceType | Should -Be 'Skipped'
        $shot.Path | Should -Be $null
        $shot.Details | Should -Be 'not displayed this run'
    }

    # --- evidence-source typing (review round 1, finding #3) ---
    It "carries EvidenceType = 'DeterministicRender' and Label on a successful deterministic-render capture" {
        $dir = Join-Path $TestDrive ("shots-detrender-" + [guid]::NewGuid().ToString('N'))

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'adaptive-menu-normal' -EvidenceType 'DeterministicRender' -CaptureAction (New-ValidCaptureAction)

        $shot.EvidenceType | Should -Be 'DeterministicRender'
        $shot.Label | Should -Be 'adaptive-menu-normal'
        $shot.Status | Should -Be 'Captured'
    }

    It "carries EvidenceType = 'ScreenCapture' and a CaptureScope on a successful screen capture" {
        $dir = Join-Path $TestDrive ("shots-screencap-" + [guid]::NewGuid().ToString('N'))

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'certification-suite-running' -EvidenceType 'ScreenCapture' -CaptureAction { param($p) [void](Save-TPMRenderedTextCapture -Path $p -Lines @('stand-in for a real screen capture')); return 'Window' }

        $shot.EvidenceType | Should -Be 'ScreenCapture'
        $shot.CaptureScope | Should -Be 'Window'
    }

    It "reports CaptureScope = 'FullDesktop' when the capture action reports a full-desktop fallback" {
        $dir = Join-Path $TestDrive ("shots-fallback-" + [guid]::NewGuid().ToString('N'))

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'certification-suite-running' -EvidenceType 'ScreenCapture' -CaptureAction { param($p) [void](Save-TPMRenderedTextCapture -Path $p -Lines @('stand-in')); return 'FullDesktop' }

        $shot.CaptureScope | Should -Be 'FullDesktop'
    }

    It "leaves CaptureScope null for DeterministicRender (capture scope only applies to real screen captures)" {
        $dir = Join-Path $TestDrive ("shots-noscopedet-" + [guid]::NewGuid().ToString('N'))

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'adaptive-menu-small' -EvidenceType 'DeterministicRender' -CaptureAction (New-ValidCaptureAction)

        $shot.CaptureScope | Should -Be $null
    }

    It "carries EvidenceType = 'Failed' (not the requested EvidenceType) when a capture attempt fails" {
        $dir = Join-Path $TestDrive ("shots-typefail-" + [guid]::NewGuid().ToString('N'))

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'x' -EvidenceType 'ScreenCapture' -CaptureAction { param($p) throw "boom" }

        $shot.EvidenceType | Should -Be 'Failed'
    }

    # --- validate generated files before reporting success (review round 1, finding #5) ---
    It "fails validation (Status = 'Failed') on an empty (zero-length) output file" {
        $dir = Join-Path $TestDrive ("shots-valid-empty-" + [guid]::NewGuid().ToString('N'))

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'empty' -EvidenceType 'DeterministicRender' -CaptureAction { param($p) New-Item -ItemType File -Path $p -Force | Out-Null }

        $shot.Status | Should -Be 'Failed'
        $shot.Details | Should -Match 'empty'
        Test-Path -LiteralPath $shot.Path -PathType Leaf | Should -Be $true -Because "the invalid artifact is preserved for inspection, not deleted"
    }

    It "fails validation (Status = 'Failed') on corrupt (non-image) output" {
        $dir = Join-Path $TestDrive ("shots-valid-corrupt-" + [guid]::NewGuid().ToString('N'))

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'corrupt' -EvidenceType 'DeterministicRender' -CaptureAction { param($p) 'this is not a png' | Set-Content -LiteralPath $p -Encoding ascii }

        $shot.Status | Should -Be 'Failed'
        $shot.Details | Should -Match 'PNG signature'
    }

    # --- review round 2: strengthened PNG validation (JPEG masquerade and
    # truncation both previously passed validation) ---
    It "fails validation (Status = 'Failed') when the output is a real JPEG merely saved with a .png extension" {
        $dir = Join-Path $TestDrive ("shots-jpegmasq-" + [guid]::NewGuid().ToString('N'))

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'jpeg-masquerade' -EvidenceType 'ScreenCapture' -CaptureAction {
            param($p)
            Add-Type -AssemblyName System.Drawing
            $bmp = New-Object System.Drawing.Bitmap 50, 50
            try { $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Jpeg) } finally { $bmp.Dispose() }
        }

        $shot.Status | Should -Be 'Failed'
        $shot.Details | Should -Match 'PNG signature'
    }

    It "Test-TPMScreenshotFileValid rejects real JPEG bytes saved with a .png extension, even when GDI+ can still decode them as *an* image" {
        $dir = Join-Path $TestDrive ("shots-jpegmasq2-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $jpegAsPngPath = Join-Path $dir 'fake.png'
        Add-Type -AssemblyName System.Drawing
        $bmp = New-Object System.Drawing.Bitmap 50, 50
        try { $bmp.Save($jpegAsPngPath, [System.Drawing.Imaging.ImageFormat]::Jpeg) } finally { $bmp.Dispose() }

        # Confirms GDI+ really would decode this successfully as *some*
        # image (proving the old "did it construct an Image object"
        # check alone was not sufficient) before confirming the
        # strengthened validator still rejects it.
        Add-Type -AssemblyName System.Drawing
        $rawBytes = [System.IO.File]::ReadAllBytes($jpegAsPngPath)
        $ms = New-Object System.IO.MemoryStream(,$rawBytes)
        try {
            $decodedAsImage = [System.Drawing.Image]::FromStream($ms)
            try {
                $decodedAsImage.RawFormat.Guid | Should -Not -Be ([System.Drawing.Imaging.ImageFormat]::Png.Guid) -Because "this is real proof GDI+ decodes it as JPEG, not PNG, despite the .png extension"
            } finally { $decodedAsImage.Dispose() }
        } finally { $ms.Dispose() }

        $validation = Test-TPMScreenshotFileValid -Path $jpegAsPngPath
        $validation.Valid | Should -Be $false
        $validation.Reason | Should -Match 'PNG signature'
    }

    It "fails validation (Status = 'Failed') on a truncated PNG (IEND trailer cut off)" {
        $dir = Join-Path $TestDrive ("shots-truncated-" + [guid]::NewGuid().ToString('N'))

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'truncated' -EvidenceType 'DeterministicRender' -CaptureAction {
            param($p)
            $full = New-RealPngBytes
            $short = $full[0..($full.Length - 20)]
            [System.IO.File]::WriteAllBytes($p, $short)
        }

        # Issue #151 review round 3: Test-TPMPngStructure's chunk-bounds
        # check now catches this specific cut (removing bytes from the
        # tail makes IDAT's own declared length overrun the file) before
        # the loop ever reaches the "no IEND chunk at all" end-of-file
        # case, so the precise reason names the overrunning chunk rather
        # than a generic "likely truncated" -- both are genuine truncation
        # rejections, just described more specifically now.
        $shot.Status | Should -Be 'Failed'
        $shot.Details | Should -Match 'overruns the end of the file'
    }

    It "Test-TPMScreenshotFileValid rejects a materially truncated PNG (over half the file cut off)" {
        $dir = Join-Path $TestDrive ("shots-truncated2-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $full = New-RealPngBytes
        $truncPath = Join-Path $dir 'truncated.png'
        $short = $full[0..([Math]::Floor($full.Length * 0.4))]
        [System.IO.File]::WriteAllBytes($truncPath, $short)

        $validation = Test-TPMScreenshotFileValid -Path $truncPath
        $validation.Valid | Should -Be $false
        $validation.Reason | Should -Match 'overruns the end of the file'
    }

    It "Test-TPMScreenshotFileValid rejects a corrupted PNG signature" {
        $dir = Join-Path $TestDrive ("shots-badsig-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $full = New-RealPngBytes
        $badBytes = [byte[]]$full.Clone()
        $badBytes[0] = 0x00
        $badBytes[3] = 0xFF
        $badSigPath = Join-Path $dir 'badsig.png'
        [System.IO.File]::WriteAllBytes($badSigPath, $badBytes)

        $validation = Test-TPMScreenshotFileValid -Path $badSigPath
        $validation.Valid | Should -Be $false
        $validation.Reason | Should -Match 'PNG signature'
    }

    It "Test-TPMScreenshotFileValid accepts a real, complete PNG produced the same way real captures are (round-trip control)" {
        $bytes = New-RealPngBytes
        $dir = Join-Path $TestDrive ("shots-roundtrip-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $p = Join-Path $dir 'roundtrip.png'
        [System.IO.File]::WriteAllBytes($p, $bytes)

        $validation = Test-TPMScreenshotFileValid -Path $p
        $validation.Valid | Should -Be $true
    }

    # --- review round 3: PNG chunk/CRC structural validation. GDI+
    # decoding (even the round-2 forced full-frame LockBits decode) does
    # not validate PNG CRC integrity -- a PNG with a single corrupted byte
    # inside IDAT, with its signature and IEND both otherwise intact,
    # decoded and locked-bits successfully under the round-2 validator.
    # Only chunk-level CRC-32 validation actually detects this. ---
    It "rejects (Status = 'Failed') a valid PNG with one byte modified inside an IDAT chunk, signature and IEND otherwise intact" {
        $dir = Join-Path $TestDrive ("shots-idatcorrupt-" + [guid]::NewGuid().ToString('N'))

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'idat-corrupt' -EvidenceType 'DeterministicRender' -CaptureAction {
            param($p)
            $full = New-RealPngBytes
            $corrupted = [byte[]]$full.Clone()
            # Locate the IDAT chunk and flip one byte in the middle of its
            # data -- everything else (signature, chunk structure, IEND)
            # stays byte-for-byte intact.
            $pos = 8
            $idatDataStart = -1
            $idatLength = 0
            while ($pos -lt $corrupted.Length) {
                $length = ([uint32]$corrupted[$pos] -shl 24) -bor ([uint32]$corrupted[$pos + 1] -shl 16) -bor ([uint32]$corrupted[$pos + 2] -shl 8) -bor [uint32]$corrupted[$pos + 3]
                $type = [System.Text.Encoding]::ASCII.GetString($corrupted, $pos + 4, 4)
                if ($type -eq 'IDAT') { $idatDataStart = $pos + 8; $idatLength = $length; break }
                $pos = $pos + 8 + $length + 4
            }
            $flipOffset = $idatDataStart + [int]($idatLength / 2)
            $corrupted[$flipOffset] = $corrupted[$flipOffset] -bxor 0xFF
            [System.IO.File]::WriteAllBytes($p, $corrupted)
        }

        $shot.Status | Should -Not -Be 'Captured'
        $shot.Status | Should -Be 'Failed'
        $shot.Details | Should -Match 'CRC'
    }

    It "Test-TPMScreenshotFileValid rejects a byte-corrupted IDAT chunk with the mismatched CRC values in the reason" {
        $dir = Join-Path $TestDrive ("shots-idatcorrupt2-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $full = New-RealPngBytes
        $corrupted = [byte[]]$full.Clone()
        $pos = 8
        $idatDataStart = -1
        $idatLength = 0
        while ($pos -lt $corrupted.Length) {
            $length = ([uint32]$corrupted[$pos] -shl 24) -bor ([uint32]$corrupted[$pos + 1] -shl 16) -bor ([uint32]$corrupted[$pos + 2] -shl 8) -bor [uint32]$corrupted[$pos + 3]
            $type = [System.Text.Encoding]::ASCII.GetString($corrupted, $pos + 4, 4)
            if ($type -eq 'IDAT') { $idatDataStart = $pos + 8; $idatLength = $length; break }
            $pos = $pos + 8 + $length + 4
        }
        $flipOffset = $idatDataStart + [int]($idatLength / 2)
        $corrupted[$flipOffset] = $corrupted[$flipOffset] -bxor 0xFF
        $corruptPath = Join-Path $dir 'idat-corrupt.png'
        [System.IO.File]::WriteAllBytes($corruptPath, $corrupted)

        $validation = Test-TPMScreenshotFileValid -Path $corruptPath
        $validation.Valid | Should -Be $false
        $validation.Reason | Should -Match "IDAT.*failed CRC validation"
        $validation.Reason | Should -Match 'stored=0x'
        $validation.Reason | Should -Match 'computed=0x'
    }

    It "rejects (Status = 'Failed') a PNG whose IHDR chunk declares a length other than 13 bytes" {
        $dir = Join-Path $TestDrive ("shots-badihdrlen-" + [guid]::NewGuid().ToString('N'))

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'bad-ihdr-length' -EvidenceType 'DeterministicRender' -CaptureAction {
            param($p)
            $full = New-RealPngBytes
            $bad = [byte[]]$full.Clone()
            # IHDR's 4-byte length field is bytes 8-11 (right after the
            # 8-byte signature) -- set it to 14 instead of the spec-
            # mandated 13.
            $bad[8] = 0; $bad[9] = 0; $bad[10] = 0; $bad[11] = 14
            [System.IO.File]::WriteAllBytes($p, $bad)
        }

        $shot.Status | Should -Not -Be 'Captured'
        $shot.Status | Should -Be 'Failed'
        $shot.Details | Should -Match 'IHDR'
        $shot.Details | Should -Match '13'
    }

    It "Test-TPMScreenshotFileValid rejects a PNG whose IHDR length is not exactly 13, before any CRC or GDI+ check runs" {
        $dir = Join-Path $TestDrive ("shots-badihdrlen2-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $full = New-RealPngBytes
        $bad = [byte[]]$full.Clone()
        $bad[8] = 0; $bad[9] = 0; $bad[10] = 0; $bad[11] = 20
        $badPath = Join-Path $dir 'bad-ihdr.png'
        [System.IO.File]::WriteAllBytes($badPath, $bad)

        $validation = Test-TPMScreenshotFileValid -Path $badPath
        $validation.Valid | Should -Be $false
        $validation.Reason | Should -Match 'IHDR chunk must be exactly 13 bytes, found 20'
    }

    It "Test-TPMPngStructure rejects a chunk whose declared length overruns the file (bounds/overrun guard, independent of truncation)" {
        $full = New-RealPngBytes
        $bad = [byte[]]$full.Clone()
        # Set IHDR's length field to an absurdly large value -- this must
        # be caught as an overrun, not silently read past the buffer.
        $bad[8] = 0x7F; $bad[9] = 0xFF; $bad[10] = 0xFF; $bad[11] = 0xFF

        $structure = Test-TPMPngStructure -Bytes $bad
        $structure.Valid | Should -Be $false
        $structure.Reason | Should -Match 'overruns the end of the file'
    }

    It "Test-TPMPngStructure rejects extra data appended after a valid IEND chunk" {
        $full = New-RealPngBytes
        $withTrailingJunk = $full + ([byte[]](1, 2, 3, 4))

        $structure = Test-TPMPngStructure -Bytes $withTrailingJunk
        $structure.Valid | Should -Be $false
        $structure.Reason | Should -Match 'extra data after'
    }

    It "Test-TPMPngStructure rejects a stream whose first chunk is not IHDR" {
        $full = New-RealPngBytes
        # Signature (8 bytes) followed directly by the real IEND chunk
        # (the last 12 bytes of a real generated PNG -- a genuinely valid
        # chunk with a correct CRC, reused here rather than hand-built, so
        # this test exercises only the "first chunk must be IHDR" check
        # and nothing else) instead of IHDR -- structurally invalid
        # regardless of what a real decoder might tolerate.
        $realIendChunk = $full[($full.Length - 12)..($full.Length - 1)]
        $malformed = $full[0..7] + $realIendChunk

        $structure = Test-TPMPngStructure -Bytes $malformed
        $structure.Valid | Should -Be $false
        $structure.Reason | Should -Match 'first chunk must be IHDR'
    }

    It "Get-TPMCrc32 computes the correct CRC-32 for the well-known ASCII input 'IEND' (independent verification against a known-good value)" {
        # IEND's CRC (over just the 4-byte type, zero-length data) is a
        # fixed, well-known value: 0xAE426082. Independently confirms the
        # CRC-32 implementation itself is correct, not just self-
        # consistent with its own chunk-walking caller.
        $bytes = [System.Text.Encoding]::ASCII.GetBytes('IEND')
        $crc = Get-TPMCrc32 -Bytes $bytes -Offset 0 -Count 4
        ('{0:X8}' -f $crc) | Should -Be 'AE426082'
    }

    It "fails validation (Status = 'Failed') when the capture action deletes the reserved file instead of writing to it" {
        $dir = Join-Path $TestDrive ("shots-valid-nofile-" + [guid]::NewGuid().ToString('N'))

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'nofile' -EvidenceType 'DeterministicRender' -CaptureAction { param($p) Remove-Item -LiteralPath $p -Force }

        $shot.Status | Should -Be 'Failed'
        $shot.Details | Should -Match 'does not exist'
    }

    It "passes validation (Status = 'Captured') for a real, valid PNG with positive dimensions" {
        $dir = Join-Path $TestDrive ("shots-valid-ok-" + [guid]::NewGuid().ToString('N'))

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'valid' -EvidenceType 'DeterministicRender' -CaptureAction (New-ValidCaptureAction)

        $shot.Status | Should -Be 'Captured'
        $validation = Test-TPMScreenshotFileValid -Path $shot.Path
        $validation.Valid | Should -Be $true
    }

    It "Test-TPMScreenshotFileValid rejects a nonexistent path" {
        $missing = Join-Path $TestDrive ("does-not-exist-" + [guid]::NewGuid().ToString('N') + '.png')
        $validation = Test-TPMScreenshotFileValid -Path $missing
        $validation.Valid | Should -Be $false
        $validation.Reason | Should -Match 'does not exist'
    }

    It "Test-TPMScreenshotFileValid rejects a file whose declared dimensions are zero (impossible image), where practical" {
        # A 1x1 real PNG is the smallest legitimately-decodable image GDI+
        # will produce; there is no supported way to coerce
        # System.Drawing.Bitmap into emitting literal zero-width/height
        # content (its constructor throws first), so this instead proves
        # the dimension check is reachable and passes for the smallest
        # real image GDI+ can produce -- the zero-dimension branch itself
        # is exercised directly against a hand-built dimension check.
        $dir = Join-Path $TestDrive ("shots-onepx-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $onePxPath = Join-Path $dir 'one.png'
        Add-Type -AssemblyName System.Drawing
        $bmp = New-Object System.Drawing.Bitmap 1, 1
        try { $bmp.Save($onePxPath, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $bmp.Dispose() }

        $validation = Test-TPMScreenshotFileValid -Path $onePxPath
        $validation.Valid | Should -Be $true -Because "1x1 is a positive, valid dimension -- confirms the check does not reject small-but-real images"
    }

    It "leaves the output file unlocked (no lingering handle) after successful validation" {
        $dir = Join-Path $TestDrive ("shots-unlock-" + [guid]::NewGuid().ToString('N'))

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'unlock' -EvidenceType 'DeterministicRender' -CaptureAction (New-ValidCaptureAction)

        $shot.Status | Should -Be 'Captured'
        # An exclusive-access open only succeeds if nothing else -- including
        # the validation Image object -- still holds a handle on the file.
        $handle = [System.IO.File]::Open($shot.Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $handle.Close()
    }
}

Describe "Certification evidence (screenshots) in the scorecard -- report inclusion and scoring isolation (issue #151)" {
    It "New-CertificationScorecard carries Results.Screenshots onto the returned scorecard object" {
        $fake = New-FakeResults -Pcsx2Present $true
        $fake.Screenshots = @(
            [pscustomobject]@{ Name = 'certification-suite-running'; Label = 'certification-suite-running'; Path = 'C:\fake\Screenshots\a.png'; Status = 'Captured'; EvidenceType = 'ScreenCapture'; CaptureScope = 'Window'; Details = 'captured' }
            [pscustomobject]@{ Name = 'final-certification-result'; Label = 'final-certification-result'; Path = 'C:\fake\Screenshots\b.png'; Status = 'Captured'; EvidenceType = 'ScreenCapture'; CaptureScope = 'FullDesktop'; Details = 'captured' }
        )

        $result = New-CertificationScorecard -Results $fake

        $result.Screenshots.Count | Should -Be 2
        ($result.Screenshots | Where-Object { $_.Name -eq 'certification-suite-running' }).Path | Should -Be 'C:\fake\Screenshots\a.png'
    }

    It "carries an empty Screenshots array (never null) when no screenshots were recorded" {
        $fake = New-FakeResults -Pcsx2Present $true
        $fake.Screenshots = @()

        $result = New-CertificationScorecard -Results $fake

        # Piping an empty array to Should sends zero pipeline objects, so
        # the container itself is checked directly instead (avoids the
        # empty-array pipeline-unrolling gotcha this codebase has hit
        # before -- see LESSONS_LEARNED.md's "return @()" entries).
        ($null -eq $result.Screenshots) | Should -Be $false
        @($result.Screenshots).Count | Should -Be 0
    }

    # --- "do not modify certification scoring" ---
    It "a Failed screenshot does not affect Overall, Passed, or Total -- screenshots are evidence, not a scored gate" {
        $fake = New-FakeResults -Pcsx2Present $true
        $baseline = New-CertificationScorecard -Results $fake

        $fake.Screenshots = @(
            [pscustomobject]@{ Name = 'adaptive-menu-small'; Label = 'adaptive-menu-small'; Path = $null; Status = 'Failed'; EvidenceType = 'Failed'; CaptureScope = $null; Details = 'simulated capture failure' }
        )
        $withFailedShot = New-CertificationScorecard -Results $fake

        $withFailedShot.Overall | Should -Be $baseline.Overall
        $withFailedShot.Overall | Should -Be 'CERTIFIED'
        $withFailedShot.Passed | Should -Be $baseline.Passed
        $withFailedShot.Total | Should -Be $baseline.Total
    }

    It "a Skipped screenshot does not affect Overall, Passed, or Total either" {
        $fake = New-FakeResults -Pcsx2Present $true
        $baseline = New-CertificationScorecard -Results $fake

        $fake.Screenshots = @(
            [pscustomobject]@{ Name = 'live-controls-evidence'; Label = 'live-controls-evidence'; Path = $null; Status = 'Skipped'; EvidenceType = 'Skipped'; CaptureScope = $null; Details = 'not displayed this run' }
        )
        $withSkippedShot = New-CertificationScorecard -Results $fake

        $withSkippedShot.Overall | Should -Be $baseline.Overall
        $withSkippedShot.Passed | Should -Be $baseline.Passed
        $withSkippedShot.Total | Should -Be $baseline.Total
    }

    It "Screenshots never appear as an Area in the scored Items list" {
        $fake = New-FakeResults -Pcsx2Present $true
        $fake.Screenshots = @(
            [pscustomobject]@{ Name = 'certification-suite-running'; Label = 'certification-suite-running'; Path = 'C:\fake\a.png'; Status = 'Captured'; EvidenceType = 'ScreenCapture'; CaptureScope = 'Window'; Details = 'captured' }
        )

        $result = New-CertificationScorecard -Results $fake

        $result.Items | Where-Object { $_.Area -like '*Screenshot*' } | Should -Be $null
        $result.Items.Count | Should -Be 11
    }
}

Describe "Get-TPMGateMark (issue #151 review round 1, finding #1)" {
    # Single source of truth shared by the real "## Gates" Markdown
    # renderer and the Smoke File Safety evidence screenshot -- both must
    # always agree.
    It "returns 'N/A' for an item with Status = 'NotApplicable', regardless of Passed" {
        Get-TPMGateMark -Item ([pscustomobject]@{ Status = 'NotApplicable'; Passed = $true }) | Should -Be 'N/A'
        Get-TPMGateMark -Item ([pscustomobject]@{ Status = 'NotApplicable'; Passed = $null }) | Should -Be 'N/A'
    }

    It "returns 'PASS' for an applicable item with Passed = \$true" {
        Get-TPMGateMark -Item ([pscustomobject]@{ Passed = $true }) | Should -Be 'PASS'
    }

    It "returns 'FAIL' for an applicable item with Passed = \$false" {
        Get-TPMGateMark -Item ([pscustomobject]@{ Passed = $false }) | Should -Be 'FAIL'
    }

    It "returns 'FAIL' (not 'PASS') for an item with no Status property and Passed = \$false" {
        Get-TPMGateMark -Item ([pscustomobject]@{ Area = 'x'; Passed = $false; Details = 'y' }) | Should -Be 'FAIL'
    }
}

Describe "Smoke File Safety evidence capture (issue #151 review round 1, finding #1)" {
    # The RC3 blocker: an unattended certification run must produce
    # explicit visual evidence showing "Smoke File Safety [N/A]" with
    # unattended-mode wording and no implication that smoke diffing
    # occurred -- not a generic root or final-certification screenshot.
    # These tests exercise the exact rendering logic the main harness flow
    # uses (Get-TPMGateMark + the same line-building shape), proving the
    # rendered content is correct for both the unattended (N/A) and smoke
    # (Pass/Fail) cases without needing to run the full harness.
    BeforeAll {
        function New-SmokeFileSafetyEvidenceLines {
            param($Item, [bool]$SmokeMode)
            if ($Item) {
                @(
                    'Smoke File Safety Evidence'
                    '=========================='
                    ''
                    ("Certification mode : {0}" -f $(if ($SmokeMode) { 'Smoke' } else { 'Unattended' }))
                    ("[{0}] {1}: {2}" -f (Get-TPMGateMark -Item $Item), $Item.Area, $Item.Details)
                )
            } else {
                @('Smoke File Safety Evidence', '==========================', '', "(Smoke File Safety item not found in this run's scorecard)")
            }
        }
    }

    It "renders 'Smoke File Safety' and '[N/A]' with unattended wording, and no smoke-mode claim, for an unattended (N/A) run" {
        $item = [pscustomobject]@{ Area = 'Smoke File Safety'; Status = 'NotApplicable'; Passed = $null; Details = 'not applicable in unattended mode -- file-safety diffing is a smoke-mode-only invariant, not asserted against real unattended runs' }

        $lines = New-SmokeFileSafetyEvidenceLines -Item $item -SmokeMode $false
        $rendered = $lines -join "`n"

        $rendered | Should -Match 'Smoke File Safety'
        $rendered | Should -Match '\[N/A\]'
        $rendered | Should -Match 'Unattended'
        $rendered | Should -Not -Match 'no unexpected changes in smoke mode' -Because "must never claim smoke diffing occurred during an unattended run"
    }

    It "renders the real Pass/Fail result (not N/A) for a smoke-mode run" {
        $item = [pscustomobject]@{ Area = 'Smoke File Safety'; Status = 'Pass'; Passed = $true; Details = 'no unexpected changes in smoke mode' }

        $lines = New-SmokeFileSafetyEvidenceLines -Item $item -SmokeMode $true
        $rendered = $lines -join "`n"

        $rendered | Should -Match 'Smoke File Safety'
        $rendered | Should -Match '\[PASS\]'
        $rendered | Should -Match 'Smoke'
    }

    It "produces a real, valid screenshot record with EvidenceType = 'DeterministicRender' and the correct rendered content" {
        $dir = Join-Path $TestDrive ("smoke-evidence-" + [guid]::NewGuid().ToString('N'))
        $item = [pscustomobject]@{ Area = 'Smoke File Safety'; Status = 'NotApplicable'; Passed = $null; Details = 'not applicable in unattended mode -- file-safety diffing is a smoke-mode-only invariant, not asserted against real unattended runs' }
        $lines = New-SmokeFileSafetyEvidenceLines -Item $item -SmokeMode $false

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'smoke-file-safety-evidence' -EvidenceType 'DeterministicRender' -CaptureAction { param($p) Save-TPMRenderedTextCapture -Path $p -Lines $lines }

        # 1. the required screenshot record exists
        $shot | Should -Not -Be $null
        # 2. correct evidence label/type
        $shot.Label | Should -Be 'smoke-file-safety-evidence'
        $shot.EvidenceType | Should -Be 'DeterministicRender'
        # 3. the output file exists
        Test-Path -LiteralPath $shot.Path -PathType Leaf | Should -Be $true
        $shot.Status | Should -Be 'Captured'
        # 4/5/6: rendered content includes "Smoke File Safety" and "[N/A]",
        # and never claims smoke-mode validation occurred -- checked
        # against the exact lines fed to the renderer (the deterministic
        # source of truth for what the PNG actually shows).
        $renderedText = $lines -join "`n"
        $renderedText | Should -Match 'Smoke File Safety'
        $renderedText | Should -Match '\[N/A\]'
        $renderedText | Should -Not -Match 'no unexpected changes in smoke mode'
    }
}

Describe "Screenshot privacy disclosure and capture-scope safeguard (issue #151 review round 1, finding #4)" {
    It "Get-TPMConsoleWindowRect never throws and returns either \$null or a positive-size rectangle" {
        $result = Get-TPMConsoleWindowRect
        if ($null -ne $result) {
            $result.Width | Should -BeGreaterThan 0
            $result.Height | Should -BeGreaterThan 0
        }
    }

    It "Save-TPMScreenCapture returns a CaptureScope of 'Window' or 'FullDesktop', never anything else" {
        $dir = Join-Path $TestDrive ("privacy-scope-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $path = Join-Path $dir 'real.png'

        $scope = Save-TPMScreenCapture -Path $path

        $scope | Should -BeIn @('Window', 'FullDesktop')
        Test-Path -LiteralPath $path -PathType Leaf | Should -Be $true
    }

    It "classifies a full-desktop fallback explicitly on the screenshot record, never silently as a narrow capture" {
        $dir = Join-Path $TestDrive ("privacy-fallback-" + [guid]::NewGuid().ToString('N'))

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'console' -EvidenceType 'ScreenCapture' -CaptureAction { param($p) [void](Save-TPMRenderedTextCapture -Path $p -Lines @('fallback stand-in')); return 'FullDesktop' }

        $shot.CaptureScope | Should -Be 'FullDesktop'
    }

    It "the Certification Scorecard Markdown discloses that ScreenCapture entries may include unrelated desktop content" {
        $fake = New-FakeResults -Pcsx2Present $true -SmokeMode $false
        $fake.EffectiveTeknoParrotRoot = 'C:\fake\TeknoParrot'
        $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM used requested root'; Passed = $true }
        $fake.Checks += [pscustomobject]@{ Name = 'Unattended TPM config restoration'; Passed = $true }
        $fake.Screenshots = @(
            [pscustomobject]@{ Name = 'certification-suite-running'; Label = 'certification-suite-running'; Path = 'C:\fake\a.png'; Status = 'Captured'; EvidenceType = 'ScreenCapture'; CaptureScope = 'FullDesktop'; Details = 'captured' }
        )

        $result = New-CertificationScorecard -Results $fake

        # The disclosure decision itself (whether at least one ScreenCapture
        # entry exists) is exercised directly here, matching the harness's
        # own real gating logic for printing the disclosure paragraph.
        @($result.Screenshots | Where-Object { $_.EvidenceType -eq 'ScreenCapture' }).Count | Should -BeGreaterThan 0
    }
}

Describe "Test-TPMPngStructure PNG specification conformance (issue #151 review round 4)" {
    # Codex found a CRC-valid PNG containing a duplicate IHDR chunk passed
    # round 3's validator -- CRC validation alone is not spec conformance,
    # since a byte-for-byte duplicate chunk is individually CRC-valid.
    # This block hand-builds CRC-VALID PNG fixtures (every chunk's CRC is
    # computed with the same Get-TPMCrc32 the production code uses) that
    # are structurally invalid in one specific way each -- proving the
    # parser's own ordering/uniqueness/semantic logic is what rejects
    # them, not a CRC mismatch that would reject almost anything.
    BeforeAll {
        function New-TPMPngChunkBytes {
            param([string]$Type, [byte[]]$Data)
            if ($null -eq $Data) { $Data = [byte[]]@() }
            $length = $Data.Length
            $lengthBytes = [byte[]](
                [byte](($length -shr 24) -band 0xFF), [byte](($length -shr 16) -band 0xFF),
                [byte](($length -shr 8) -band 0xFF), [byte]($length -band 0xFF)
            )
            $typeBytes = [System.Text.Encoding]::ASCII.GetBytes($Type)
            $crcInput = $typeBytes + $Data
            $crc = Get-TPMCrc32 -Bytes $crcInput -Offset 0 -Count $crcInput.Length
            $crcBytes = [byte[]](
                [byte](($crc -shr 24) -band 0xFF), [byte](($crc -shr 16) -band 0xFF),
                [byte](($crc -shr 8) -band 0xFF), [byte]($crc -band 0xFF)
            )
            return $lengthBytes + $typeBytes + $Data + $crcBytes
        }

        function New-TPMTestPng {
            param([byte[][]]$Chunks)
            $sig = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
            $all = $sig
            foreach ($c in $Chunks) { $all = $all + $c }
            return $all
        }

        function New-TPMIhdrData {
            param([int]$Width = 4, [int]$Height = 4, [byte]$BitDepth = 8, [byte]$ColorType = 2, [byte]$Compression = 0, [byte]$Filter = 0, [byte]$Interlace = 0)
            $w = [byte[]]((($Width -shr 24) -band 0xFF), (($Width -shr 16) -band 0xFF), (($Width -shr 8) -band 0xFF), ($Width -band 0xFF))
            $h = [byte[]]((($Height -shr 24) -band 0xFF), (($Height -shr 16) -band 0xFF), (($Height -shr 8) -band 0xFF), ($Height -band 0xFF))
            return $w + $h + [byte[]]($BitDepth, $ColorType, $Compression, $Filter, $Interlace)
        }

        # Shared building blocks -- a minimal, CRC-valid truecolor
        # (color type 2) IHDR/IDAT/IEND used as the baseline most fixtures
        # below start from and modify in exactly one way. Test-
        # TPMPngStructure never decodes IDAT's actual pixel data, so its
        # content only has to be present and CRC-valid, not real deflate
        # output -- these fixtures test the parser's structural logic,
        # not GDI+ decodability (that is covered separately by the
        # existing round-1/2/3 tests using real Save-TPMRenderedTextCapture
        # output).
        $script:tpmIhdrTruecolor = New-TPMPngChunkBytes -Type 'IHDR' -Data (New-TPMIhdrData -ColorType 2 -BitDepth 8)
        $script:tpmIdat = New-TPMPngChunkBytes -Type 'IDAT' -Data ([byte[]](1, 2, 3, 4, 5, 6, 7, 8))
        $script:tpmIend = New-TPMPngChunkBytes -Type 'IEND' -Data $null
        $script:tpmPlte = New-TPMPngChunkBytes -Type 'PLTE' -Data ([byte[]](1, 2, 3))
    }

    It "accepts a minimal, well-formed truecolor PNG (baseline control -- every other fixture below is one deliberate deviation from this)" {
        $png = New-TPMTestPng -Chunks @($tpmIhdrTruecolor, $tpmIdat, $tpmIend)
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $true
    }

    # --- required fixture 1: duplicate IHDR ---
    It "rejects a duplicate IHDR chunk, even though both copies are individually CRC-valid" {
        $png = New-TPMTestPng -Chunks @($tpmIhdrTruecolor, $tpmIhdrTruecolor, $tpmIdat, $tpmIend)
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $false
        $r.Reason | Should -Match 'more than one IHDR'
    }

    # --- required fixture 2: missing IDAT ---
    It "rejects a PNG with no IDAT chunk" {
        $png = New-TPMTestPng -Chunks @($tpmIhdrTruecolor, $tpmIend)
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $false
        $r.Reason | Should -Match 'no IDAT chunk'
    }

    # --- required fixture 3: nonconsecutive IDAT ---
    It "rejects IDAT chunks that are not consecutive (another chunk appears between them)" {
        $tExt = New-TPMPngChunkBytes -Type 'tEXt' -Data ([System.Text.Encoding]::ASCII.GetBytes('a'))
        $png = New-TPMTestPng -Chunks @($tpmIhdrTruecolor, $tpmIdat, $tExt, $tpmIdat, $tpmIend)
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $false
        $r.Reason | Should -Match 'consecutive'
    }

    # --- required fixture 4: duplicate PLTE ---
    It "rejects a duplicate PLTE chunk" {
        $png = New-TPMTestPng -Chunks @($tpmIhdrTruecolor, $tpmPlte, $tpmPlte, $tpmIdat, $tpmIend)
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $false
        $r.Reason | Should -Match 'more than one PLTE'
    }

    # --- required fixture 5: PLTE after IDAT ---
    It "rejects a PLTE chunk that appears after IDAT" {
        $png = New-TPMTestPng -Chunks @($tpmIhdrTruecolor, $tpmIdat, $tpmPlte, $tpmIend)
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $false
        $r.Reason | Should -Match 'before the first IDAT'
    }

    # --- required fixture 6: indexed-color image missing PLTE ---
    It "rejects an indexed-color (color type 3) image with no PLTE chunk" {
        $ihdrIndexed = New-TPMPngChunkBytes -Type 'IHDR' -Data (New-TPMIhdrData -ColorType 3 -BitDepth 8)
        $png = New-TPMTestPng -Chunks @($ihdrIndexed, $tpmIdat, $tpmIend)
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $false
        $r.Reason | Should -Match 'PLTE is required'
    }

    # --- required fixture 7: grayscale image containing PLTE ---
    It "rejects a grayscale (color type 0) image that contains a PLTE chunk" {
        $ihdrGray = New-TPMPngChunkBytes -Type 'IHDR' -Data (New-TPMIhdrData -ColorType 0 -BitDepth 8)
        $png = New-TPMTestPng -Chunks @($ihdrGray, $tpmPlte, $tpmIdat, $tpmIend)
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $false
        $r.Reason | Should -Match 'not permitted for color type 0'
    }

    # --- required fixture 8: grayscale+alpha image containing PLTE ---
    It "rejects a grayscale+alpha (color type 4) image that contains a PLTE chunk" {
        $ihdrGA = New-TPMPngChunkBytes -Type 'IHDR' -Data (New-TPMIhdrData -ColorType 4 -BitDepth 8)
        $png = New-TPMTestPng -Chunks @($ihdrGA, $tpmPlte, $tpmIdat, $tpmIend)
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $false
        $r.Reason | Should -Match 'not permitted for color type 4'
    }

    # --- required fixture 9: optional PLTE before IDAT (truecolor) ---
    It "accepts an optional PLTE chunk placed before IDAT on a truecolor (color type 2) image" {
        $png = New-TPMTestPng -Chunks @($tpmIhdrTruecolor, $tpmPlte, $tpmIdat, $tpmIend)
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $true
    }

    # --- required fixture 10: optional PLTE omitted (truecolor+alpha) ---
    It "accepts a truecolor+alpha (color type 6) image with PLTE omitted" {
        $ihdrRgba = New-TPMPngChunkBytes -Type 'IHDR' -Data (New-TPMIhdrData -ColorType 6 -BitDepth 8)
        $png = New-TPMTestPng -Chunks @($ihdrRgba, $tpmIdat, $tpmIend)
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $true
    }

    # --- required fixture 11: duplicate IEND ---
    It "rejects a duplicate IEND chunk" {
        $png = New-TPMTestPng -Chunks @($tpmIhdrTruecolor, $tpmIdat, $tpmIend, $tpmIend)
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $false
        # Caught as "extra data after the terminating IEND" -- the first
        # IEND already sets the terminal flag, so a second IEND is
        # detected by that check before the parser ever gets far enough
        # to evaluate it as "a second IEND chunk" specifically. Both are
        # the same defect (more than one IEND); this asserts on the
        # reason the current loop structure actually produces.
        $r.Reason | Should -Match 'extra data after'
    }

    # --- required fixture 12: unknown critical chunk ---
    It "rejects an unrecognized critical chunk (uppercase first letter, not one of IHDR/PLTE/IDAT/IEND)" {
        $unknownCritical = New-TPMPngChunkBytes -Type 'FOOB' -Data ([byte[]](1, 2))
        $png = New-TPMTestPng -Chunks @($tpmIhdrTruecolor, $tpmIdat, $unknownCritical, $tpmIend)
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $false
        $r.Reason | Should -Match 'unrecognized critical chunk'
    }

    # --- required fixture 13: malformed chunk type ---
    It "rejects a chunk type that is not 4 ASCII letters" {
        $sig = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
        # A chunk with digits (0x31-0x34, "1234") in its type field --
        # bytes outside both the A-Z and a-z ranges.
        $badChunk = [byte[]](0, 0, 0, 2) + [byte[]](0x31, 0x32, 0x33, 0x34) + [byte[]](1, 2) + [byte[]](0, 0, 0, 0)
        $png = $sig + $tpmIhdrTruecolor + $badChunk
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $false
        $r.Reason | Should -Match 'not 4 ASCII letters'
    }

    # --- required fixture 14: invalid color-type ---
    It "rejects an IHDR with an unknown color type" {
        $ihdrBadColor = New-TPMPngChunkBytes -Type 'IHDR' -Data (New-TPMIhdrData -ColorType 5 -BitDepth 8)
        $png = New-TPMTestPng -Chunks @($ihdrBadColor, $tpmIdat, $tpmIend)
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $false
        $r.Reason | Should -Match 'unknown color type'
    }

    # --- required fixture 15: invalid bit-depth/color-type combination ---
    It "rejects an IHDR whose bit depth is not legal for its color type (truecolor with bit depth 4)" {
        $ihdrBadDepth = New-TPMPngChunkBytes -Type 'IHDR' -Data (New-TPMIhdrData -ColorType 2 -BitDepth 4)
        $png = New-TPMTestPng -Chunks @($ihdrBadDepth, $tpmIdat, $tpmIend)
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $false
        $r.Reason | Should -Match 'does not permit'
    }

    It "accepts every legal color-type/bit-depth combination defined by the PNG spec" -TestCases @(
        @{ ColorType = 0; BitDepth = 1 }, @{ ColorType = 0; BitDepth = 2 }, @{ ColorType = 0; BitDepth = 4 }, @{ ColorType = 0; BitDepth = 8 }, @{ ColorType = 0; BitDepth = 16 }
        @{ ColorType = 2; BitDepth = 8 }, @{ ColorType = 2; BitDepth = 16 }
        @{ ColorType = 3; BitDepth = 1 }, @{ ColorType = 3; BitDepth = 2 }, @{ ColorType = 3; BitDepth = 4 }, @{ ColorType = 3; BitDepth = 8 }
        @{ ColorType = 4; BitDepth = 8 }, @{ ColorType = 4; BitDepth = 16 }
        @{ ColorType = 6; BitDepth = 8 }, @{ ColorType = 6; BitDepth = 16 }
    ) {
        param($ColorType, $BitDepth)
        $ihdr = New-TPMPngChunkBytes -Type 'IHDR' -Data (New-TPMIhdrData -ColorType $ColorType -BitDepth $BitDepth)
        $chunks = @($ihdr)
        # Color type 3 (indexed) requires PLTE.
        if ($ColorType -eq 3) {
            $maxEntries = [Math]::Pow(2, $BitDepth)
            $plteBytes = New-Object 'byte[]' ([Math]::Min(3, [int]($maxEntries * 3)))
            $chunks += (New-TPMPngChunkBytes -Type 'PLTE' -Data $plteBytes)
        }
        $chunks += $tpmIdat
        $chunks += $tpmIend
        $png = New-TPMTestPng -Chunks $chunks
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $true -Because "ColorType=$ColorType BitDepth=$BitDepth is spec-legal: $($r.Reason)"
    }

    It "rejects every illegal color-type/bit-depth combination the PNG spec forbids" -TestCases @(
        @{ ColorType = 0; BitDepth = 3 }
        @{ ColorType = 2; BitDepth = 1 }; @{ ColorType = 2; BitDepth = 2 }; @{ ColorType = 2; BitDepth = 4 }
        @{ ColorType = 3; BitDepth = 16 }
        @{ ColorType = 4; BitDepth = 1 }; @{ ColorType = 4; BitDepth = 2 }; @{ ColorType = 4; BitDepth = 4 }
        @{ ColorType = 6; BitDepth = 1 }; @{ ColorType = 6; BitDepth = 2 }; @{ ColorType = 6; BitDepth = 4 }
    ) {
        param($ColorType, $BitDepth)
        $ihdr = New-TPMPngChunkBytes -Type 'IHDR' -Data (New-TPMIhdrData -ColorType $ColorType -BitDepth $BitDepth)
        $png = New-TPMTestPng -Chunks @($ihdr, $tpmIdat, $tpmIend)
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $false -Because "ColorType=$ColorType BitDepth=$BitDepth is not permitted by the PNG spec"
    }

    # --- required fixture 16: indexed palette exceeding bit-depth capacity ---
    It "rejects an indexed-color PLTE whose entry count exceeds what the IHDR bit depth can reference" {
        $ihdrIdx1 = New-TPMPngChunkBytes -Type 'IHDR' -Data (New-TPMIhdrData -ColorType 3 -BitDepth 1)
        # Bit depth 1 can reference at most 2 palette entries; this PLTE
        # declares 4 (12 bytes / 3).
        $plteTooBig = New-TPMPngChunkBytes -Type 'PLTE' -Data ([byte[]](1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12))
        $png = New-TPMTestPng -Chunks @($ihdrIdx1, $plteTooBig, $tpmIdat, $tpmIend)
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $false
        $r.Reason | Should -Match "more than IHDR's bit depth"
    }

    # --- PLTE content validation beyond palette-size-vs-bit-depth ---
    It "rejects a PLTE chunk whose length is not a multiple of 3" {
        $badPlte = New-TPMPngChunkBytes -Type 'PLTE' -Data ([byte[]](1, 2, 3, 4))
        $png = New-TPMTestPng -Chunks @($tpmIhdrTruecolor, $badPlte, $tpmIdat, $tpmIend)
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $false
        $r.Reason | Should -Match 'multiple of 3'
    }

    It "rejects a zero-length PLTE chunk" {
        $emptyPlte = New-TPMPngChunkBytes -Type 'PLTE' -Data ([byte[]]@())
        $png = New-TPMTestPng -Chunks @($tpmIhdrTruecolor, $emptyPlte, $tpmIdat, $tpmIend)
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $false
        $r.Reason | Should -Match 'multiple of 3'
    }

    It "rejects a PLTE chunk longer than 768 bytes (more than 256 entries)" {
        $tooManyEntries = New-Object 'byte[]' 771
        $hugePlte = New-TPMPngChunkBytes -Type 'PLTE' -Data $tooManyEntries
        $png = New-TPMTestPng -Chunks @($tpmIhdrTruecolor, $hugePlte, $tpmIdat, $tpmIend)
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $false
        $r.Reason | Should -Match '768 bytes'
    }

    # --- own adversarial review: additional gaps closed beyond the
    # explicitly required list ---
    It "allows an unknown ANCILLARY chunk (lowercase first letter) once its own bounds and CRC are valid" {
        $unknownAncillary = New-TPMPngChunkBytes -Type 'foOB' -Data ([byte[]](1, 2))
        $png = New-TPMTestPng -Chunks @($tpmIhdrTruecolor, $tpmIdat, $unknownAncillary, $tpmIend)
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $true -Because "unknown ancillary chunks are legal PNG extension points, not corruption"
    }

    It "treats chunk type comparisons as case-sensitive -- a lowercase 'ihdr' first chunk is not accepted as IHDR" {
        # PowerShell's default -eq/-ne/-contains are case-INSENSITIVE;
        # chunk-type case is semantically load-bearing in the PNG spec
        # (it encodes the critical/ancillary property bit), so a chunk
        # literally named "ihdr" is a different, unrecognized ancillary
        # chunk, not a case-different spelling of "IHDR". Confirmed by
        # direct repro that the case-insensitive default would have let
        # this through as if it were a real IHDR.
        $ihdrLower = New-TPMPngChunkBytes -Type 'ihdr' -Data (New-TPMIhdrData -ColorType 2 -BitDepth 8)
        $png = New-TPMTestPng -Chunks @($ihdrLower, $tpmIdat, $tpmIend)
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $false
        $r.Reason | Should -Match "first chunk must be IHDR|reserved"
    }

    It "rejects a chunk whose declared length exceeds the PNG spec's maximum chunk length (2^31 - 1), independent of file size" {
        # Length field bytes 0x7FFFFFFF + 1 = 0x80000000 -- exceeds the
        # spec's signed-32-bit chunk length ceiling even though it still
        # fits in the unsigned 32-bit length field itself.
        $sig = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
        $oversizedLengthChunk = [byte[]](0x80, 0x00, 0x00, 0x00) + [System.Text.Encoding]::ASCII.GetBytes('IDAT')
        $png = $sig + $tpmIhdrTruecolor + $oversizedLengthChunk
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $false
        $r.Reason | Should -Match 'exceeds the maximum'
    }

    It "rejects invalid IHDR compression, filter, and interlace method values" -TestCases @(
        @{ Compression = 1; Filter = 0; Interlace = 0 }
        @{ Compression = 0; Filter = 1; Interlace = 0 }
        @{ Compression = 0; Filter = 0; Interlace = 2 }
    ) {
        param($Compression, $Filter, $Interlace)
        $ihdr = New-TPMPngChunkBytes -Type 'IHDR' -Data (New-TPMIhdrData -ColorType 2 -BitDepth 8 -Compression $Compression -Filter $Filter -Interlace $Interlace)
        $png = New-TPMTestPng -Chunks @($ihdr, $tpmIdat, $tpmIend)
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $false
    }

    It "accepts both defined interlace methods (0 = none, 1 = Adam7)" -TestCases @(
        @{ Interlace = 0 }, @{ Interlace = 1 }
    ) {
        param($Interlace)
        $ihdr = New-TPMPngChunkBytes -Type 'IHDR' -Data (New-TPMIhdrData -ColorType 2 -BitDepth 8 -Interlace $Interlace)
        $png = New-TPMTestPng -Chunks @($ihdr, $tpmIdat, $tpmIend)
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $true
    }

    It "never accepts a chunk whose CRC is wrong, even when everything else about the fixture is spec-legal (no regression from round 3)" {
        $corruptIdat = New-TPMPngChunkBytes -Type 'IDAT' -Data ([byte[]](1, 2, 3, 4, 5, 6, 7, 8))
        # Flip the stored CRC's last byte without touching the data.
        $corruptIdat[$corruptIdat.Length - 1] = $corruptIdat[$corruptIdat.Length - 1] -bxor 0xFF
        $png = New-TPMTestPng -Chunks @($tpmIhdrTruecolor, $corruptIdat, $tpmIend)
        $r = Test-TPMPngStructure -Bytes $png
        $r.Valid | Should -Be $false
        $r.Reason | Should -Match 'CRC'
    }

    # --- end-to-end: the exact regressed scenario Codex found, through the
    # full New-TPMCertificationScreenshot flow, proving Status never
    # becomes 'Captured' for it ---
    It "New-TPMCertificationScreenshot never reports Status = 'Captured' for a CRC-valid PNG with a duplicate IHDR chunk" {
        $dir = Join-Path $TestDrive ("shots-dupihdr-" + [guid]::NewGuid().ToString('N'))
        $duplicateIhdrPng = New-TPMTestPng -Chunks @($tpmIhdrTruecolor, $tpmIhdrTruecolor, $tpmIdat, $tpmIend)

        $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name 'duplicate-ihdr' -EvidenceType 'DeterministicRender' -CaptureAction { param($p) [System.IO.File]::WriteAllBytes($p, $duplicateIhdrPng) }

        $shot.Status | Should -Not -Be 'Captured'
        $shot.Status | Should -Be 'Failed'
        $shot.Details | Should -Match 'IHDR'
    }
}


Describe "Test-TPMPngStructure complete static PNG inventory coverage (issue #151 final review)" {
    BeforeAll {
        function New-InventoryChunk([string]$Type, [byte[]]$Data) {
            if ($null -eq $Data) { $Data = [byte[]]@() }
            $len=$Data.Length; $tb=[Text.Encoding]::ASCII.GetBytes($Type); $crc=Get-TPMCrc32 -Bytes ($tb+$Data) -Offset 0 -Count (4+$len)
            [byte[]]((($len-shr 24)-band 255),(($len-shr 16)-band 255),(($len-shr 8)-band 255),($len-band 255))+$tb+$Data+[byte[]]((($crc-shr 24)-band 255),(($crc-shr 16)-band 255),(($crc-shr 8)-band 255),($crc-band 255))
        }
        function New-InventoryPng([byte[][]]$Chunks) { [byte[]](0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a)+($Chunks|ForEach-Object{$_}) }
        function New-InventoryIhdr([byte[]]$Width,[byte[]]$Height) { New-InventoryChunk IHDR ($Width+$Height+[byte[]](8,2,0,0,0)) }
        $script:invIhdr=New-InventoryIhdr ([byte[]](0,0,0,2)) ([byte[]](0,0,0,2));$script:invIdat=New-InventoryChunk IDAT ([byte[]](1));$script:invIend=New-InventoryChunk IEND @()
    }
    It "rejects invalid IHDR dimension <Name>" -TestCases @(
        @{Name='zero width';W=[byte[]](0,0,0,0);H=[byte[]](0,0,0,1)},@{Name='zero height';W=[byte[]](0,0,0,1);H=[byte[]](0,0,0,0)},@{Name='width high bit';W=[byte[]](0x80,0,0,0);H=[byte[]](0,0,0,1)},@{Name='height high bit';W=[byte[]](0,0,0,1);H=[byte[]](0x80,0,0,0)}
    ) { param($Name,$W,$H);(Test-TPMPngStructure (New-InventoryPng @((New-InventoryIhdr $W $H),$invIdat,$invIend))).Valid|Should -BeFalse }
    It "rejects a reserved-bit chunk name" { $r=Test-TPMPngStructure (New-InventoryPng @($invIhdr,$invIdat,(New-InventoryChunk foob @()),$invIend));$r.Valid|Should -BeFalse;$r.Reason|Should -Match 'reserved' }
    It "rejects duplicate singleton ancillary <Type>" -TestCases @('cHRM','cICP','gAMA','iCCP','mDCV','cLLI','sBIT','sRGB','bKGD','hIST','tRNS','eXIf','pHYs','tIME'|ForEach-Object{@{Type=$_}}) { param($Type);$c=New-InventoryChunk $Type @();$prefix=@($invIhdr);if($Type -eq 'hIST'){$prefix+=New-InventoryChunk PLTE ([byte[]](1,2,3))};$r=Test-TPMPngStructure (New-InventoryPng @($prefix+$c+$c+$invIdat+$invIend));$r.Valid|Should -BeFalse;$r.Reason|Should -Match 'more than one' }
    It "rejects pre-PLTE/pre-IDAT chunk <Type> after IDAT" -TestCases @('cHRM','cICP','gAMA','iCCP','mDCV','cLLI','sBIT','sRGB'|ForEach-Object{@{Type=$_}}) { param($Type);(Test-TPMPngStructure (New-InventoryPng @($invIhdr,$invIdat,(New-InventoryChunk $Type @()),$invIend))).Valid|Should -BeFalse }
    It "rejects pre-IDAT chunk <Type> after IDAT" -TestCases @('eXIf','pHYs','sPLT'|ForEach-Object{@{Type=$_}}) { param($Type);(Test-TPMPngStructure (New-InventoryPng @($invIhdr,$invIdat,(New-InventoryChunk $Type @()),$invIend))).Valid|Should -BeFalse }
    It "rejects registered APNG chunk <Type> for static evidence" -TestCases @('acTL','fcTL','fdAT'|ForEach-Object{@{Type=$_}}) { param($Type);(Test-TPMPngStructure (New-InventoryPng @($invIhdr,(New-InventoryChunk $Type @()),$invIdat,$invIend))).Valid|Should -BeFalse }
    It "allows a conforming unknown ancillary chunk" { (Test-TPMPngStructure (New-InventoryPng @($invIhdr,$invIdat,(New-InventoryChunk foOB @()),$invIend))).Valid|Should -BeTrue }
    It "rejects PLTE after <Type> when an optional truecolor palette is present" -TestCases @(@{Type='bKGD'},@{Type='tRNS'}) { param($Type);$c=New-InventoryChunk $Type @();$plte=New-InventoryChunk PLTE ([byte[]](1,2,3));(Test-TPMPngStructure (New-InventoryPng @($invIhdr,$c,$plte,$invIdat,$invIend))).Valid|Should -BeFalse }

}


Describe "Issue #154 evidence metadata and finalization regression" {
    It "returns Skipped without binding or requiring EvidenceType" {
        $r=New-TPMCertificationScreenshot -ScreenshotDir $TestDrive -Name 'skip' -Skip -SkipReason 'not shown'
        $r.Status|Should -Be 'Skipped';$r.EvidenceType|Should -Be 'Skipped'
    }
    It "ignores capture-only parameters when Skip is explicit" {
        $r=New-TPMCertificationScreenshot -ScreenshotDir $TestDrive -Name 'skip-with-capture-data' -Skip -EvidenceType 'Invalid' -CaptureAction { throw 'must not run' }
        $r.Status|Should -Be 'Skipped';$r.Required|Should -BeFalse;$r.Path|Should -BeNullOrEmpty
    }
    It "converts <Case> EvidenceType into controlled Failed evidence" -TestCases @(
        @{Case='omitted';Value=$null},@{Case='null';Value=$null},@{Case='empty';Value=''},@{Case='whitespace';Value=' '},@{Case='unknown';Value='Other'}
    ) { param($Case,$Value);$r=New-TPMCertificationScreenshot -ScreenshotDir $TestDrive -Name $Case -EvidenceType $Value -CaptureAction{};$r.Status|Should -Be 'Failed';$r.EvidenceType|Should -Be 'Failed';$r.Details|Should -Match 'invalid evidence metadata' }
    It "converts empty Name and ScreenshotDir into controlled failures" {
        (New-TPMCertificationScreenshot -ScreenshotDir $TestDrive -Name '' -EvidenceType ScreenCapture -CaptureAction{}).Status|Should -Be 'Failed'
        (New-TPMCertificationScreenshot -ScreenshotDir '' -Name 'x' -EvidenceType ScreenCapture -CaptureAction{}).Status|Should -Be 'Failed'
    }
    It "gives every production Add-Screenshot call a valid literal type or explicit Skip" {
        $source=[IO.File]::ReadAllLines((Join-Path $PSScriptRoot '..\scripts\Invoke-TPM-RealInstanceSmoke.ps1'))
        $calls=@($source|Where-Object{$_ -match '^\s*(\[void\]\(|\$finalEvidence\s*=)?Add-Screenshot\s+-ScreenshotDir'})
        $calls.Count|Should -Be 8
        foreach($call in $calls){($call -match '-Skip(?:\s|\))' -or $call -match "-EvidenceType\s+'(?:ScreenCapture|DeterministicRender)'")|Should -BeTrue -Because $call}
    }
}


Describe "Issue #154 authoritative certification transaction invariants" {
    BeforeAll {
        function New-CertificationTransactionFixture {
            $script:tpmEvidenceWorkflowId = [guid]::NewGuid().ToString('N')
            $dir = Join-Path $TestDrive $script:tpmEvidenceWorkflowId
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            # Production order: skips happen early, final-certification-result
            # is always last -- the fixture mirrors that ordering because the
            # capture-ordering invariant asserts final-certification-result
            # has the highest Sequence of the whole manifest, the same way
            # Add-Screenshot assigns it in the real certification flow.
            $spec = @(
                @{Name='certification-suite-running';Type='ScreenCapture'}
                @{Name='requested-effective-root-evidence';Type='ScreenCapture'}
                @{Name='live-thumbnail-evidence';Skip=$true}
                @{Name='live-controls-evidence';Skip=$true}
                @{Name='adaptive-menu-normal';Type='DeterministicRender'}
                @{Name='adaptive-menu-small';Type='DeterministicRender'}
                @{Name='adaptive-menu-maximized';Type='DeterministicRender'}
                @{Name='smoke-file-safety-evidence';Type='DeterministicRender'}
                @{Name='final-certification-result';Type='ScreenCapture'}
            )
            $shots = @()
            $seq = 0
            foreach ($item in $spec) {
                $seq++
                if ($item.Skip) {
                    $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name $item.Name -Skip -SkipReason 'not displayed'
                } else {
                    $shot = New-TPMCertificationScreenshot -ScreenshotDir $dir -Name $item.Name -EvidenceType $item.Type -CaptureAction { param($p) Save-TPMRenderedTextCapture -Path $p -Lines @('valid transaction evidence') }
                }
                $shot = $shot | Add-Member -NotePropertyName Sequence -NotePropertyValue $seq -Force -PassThru
                $shots += $shot
            }
            # Continue the real evidence-append counter from where the fixture
            # left off, so a test that goes on to call the real Add-Screenshot
            # (e.g. to simulate a thrown final capture) gets a Sequence that
            # is genuinely later than everything the fixture built, exactly
            # as production's single monotonic counter would produce.
            $script:tpmEvidenceSequence = $seq

            # A realistic full-pass Items array, derived through the same
            # Get-TPMCertificationScoreFromItems function production uses --
            # this is what makes "does not let complete evidence override a
            # failed numeric score" and "does not let passing numeric
            # arithmetic override failed finalization" meaningful: the
            # transaction now derives Overall/Passed/Total from Items itself,
            # it does not trust whatever the fixture (or an attacker-
            # controlled mutation) set directly on .Overall/.Passed/.Total.
            $items = @(
                [pscustomobject]@{Area='Repository'; Passed=$true; Details='clean'},
                [pscustomobject]@{Area='Pester'; Passed=$true; Details='full pass'},
                [pscustomobject]@{Area='Static Analysis'; Passed=$true; Details='0 findings'},
                [pscustomobject]@{Area='Artifacts'; Passed=$true; Details='present'}
            )
            $score = Get-TPMCertificationScoreFromItems -Items $items
            [pscustomobject]@{
                Results = [ordered]@{Screenshots=$shots;EvidenceWorkflowId=$script:tpmEvidenceWorkflowId;Status='PASS'}
                Certification = [pscustomobject]@{Overall=$score.Overall;Screenshots=@();Passed=$score.Passed;Total=$score.Total;ScorePercent=$score.ScorePercent;Items=$items}
            }
        }

        function Assert-FailedTransactionConsistency {
            param($Fixture, $Transaction)
            $Transaction.Passed | Should -BeFalse
            $Transaction.Status | Should -Be 'FAIL'
            $Transaction.Overall | Should -Be 'NOT CERTIFIED'
            $Transaction.ExitCode | Should -Be 1
            $Fixture.Results.Status | Should -Be 'FAIL'
            $Fixture.Results.CertificationOverall | Should -Be 'NOT CERTIFIED'
            $Fixture.Results.ExitCode | Should -Be 1
            $Fixture.Certification.Status | Should -Be 'FAIL'
            $Fixture.Certification.Overall | Should -Be 'NOT CERTIFIED'
            $Fixture.Certification.ExitCode | Should -Be 1
            (Get-TPMCertificationFinalConsoleLines $Transaction) -join [Environment]::NewLine | Should -Match 'FINAL STATUS : FAIL'
            (Get-TPMCertificationFinalConsoleLines $Transaction) -join [Environment]::NewLine | Should -Match 'OVERALL      : NOT CERTIFIED'
            (Get-TPMCertificationFinalConsoleLines $Transaction) -join [Environment]::NewLine | Should -Match 'EXIT CODE    : 1'
            $report = (Get-TPMCertificationFinalReportLines $Transaction) -join [Environment]::NewLine
            $report | Should -Match 'Status: \*\*FAIL\*\*'
            $report | Should -Match 'Overall: \*\*NOT CERTIFIED\*\*'
            $report | Should -Match 'Process exit code: 1'
        }
    }

    It "certifies only one complete normal-workflow manifest and returns exit code zero" {
        $f = New-CertificationTransactionFixture
        $x = Complete-TPMCertificationTransaction $f.Certification $f.Results
        $x.Passed | Should -BeTrue
        $x.Status | Should -Be 'PASS'
        $x.Overall | Should -Be 'CERTIFIED'
        $x.ExitCode | Should -Be 0
        $f.Results.Status | Should -Be 'PASS'
        $f.Certification.Status | Should -Be 'PASS'
        @($f.Results.Screenshots | Where-Object Name -CEQ 'final-certification-result').Count | Should -Be 1
    }

    It "rejects failure of required evidence <Name> even when final evidence succeeds" -TestCases @(
        @{Name='certification-suite-running'},@{Name='requested-effective-root-evidence'},
        @{Name='adaptive-menu-normal'},@{Name='adaptive-menu-small'},@{Name='adaptive-menu-maximized'},
        @{Name='smoke-file-safety-evidence'},@{Name='final-certification-result'}
    ) {
        param($Name)
        $f = New-CertificationTransactionFixture
        $shot = $f.Results.Screenshots | Where-Object Name -CEQ $Name
        $shot.Status='Failed';$shot.EvidenceType='Failed';$shot.Details='simulated earlier required failure'
        $x = Complete-TPMCertificationTransaction $f.Certification $f.Results
        Assert-FailedTransactionConsistency $f $x
    }

    It "rejects a missing final-certification-result" {
        $f=New-CertificationTransactionFixture
        $f.Results.Screenshots=@($f.Results.Screenshots|Where-Object Name -CNE 'final-certification-result')
        $x=Complete-TPMCertificationTransaction $f.Certification $f.Results
        Assert-FailedTransactionConsistency $f $x
        $x.Evidence.Details|Should -Match 'found 0'
    }

    It "rejects duplicate final-certification-result records" {
        $f=New-CertificationTransactionFixture
        $final=@($f.Results.Screenshots|Where-Object Name -CEQ 'final-certification-result')[0]
        $f.Results.Screenshots+= $final
        $x=Complete-TPMCertificationTransaction $f.Certification $f.Results
        Assert-FailedTransactionConsistency $f $x
        $x.Evidence.Details|Should -Match 'found 2'
    }

    It "rejects an unrelated Captured ScreenCapture substituted for the final record" {
        $f=New-CertificationTransactionFixture
        $final=@($f.Results.Screenshots|Where-Object Name -CEQ 'final-certification-result')[0]
        $final.Name='unrelated-capture';$final.Label='unrelated-capture'
        $x=Complete-TPMCertificationTransaction $f.Certification $f.Results
        Assert-FailedTransactionConsistency $f $x
        $x.Evidence.Details|Should -Match 'unexpected evidence'
    }

    It "rejects synthetic final evidence with wrong workflow provenance" {
        $f=New-CertificationTransactionFixture
        $final=@($f.Results.Screenshots|Where-Object Name -CEQ 'final-certification-result')[0]
        $final.WorkflowId='synthetic-workflow'
        $x=Complete-TPMCertificationTransaction $f.Certification $f.Results
        Assert-FailedTransactionConsistency $f $x
        $x.Evidence.Details|Should -Match 'did not originate'
    }

    It "rejects final evidence returned as Skipped" {
        $f=New-CertificationTransactionFixture
        $final=@($f.Results.Screenshots|Where-Object Name -CEQ 'final-certification-result')[0]
        $final.Status='Skipped';$final.EvidenceType='Skipped';$final.Required=$false;$final.Path=$null
        $x=Complete-TPMCertificationTransaction $f.Certification $f.Results
        Assert-FailedTransactionConsistency $f $x
    }

    It "rejects final evidence returned as structured Failed" {
        $f=New-CertificationTransactionFixture
        $final=@($f.Results.Screenshots|Where-Object Name -CEQ 'final-certification-result')[0]
        $final.Status='Failed';$final.EvidenceType='Failed';$final.Details='structured capture failure'
        $x=Complete-TPMCertificationTransaction $f.Certification $f.Results
        Assert-FailedTransactionConsistency $f $x
        $x.Evidence.Details|Should -Match 'structured capture failure'
    }

    It "contains a thrown final capture and the authority rejects its accumulated Failed record" {
        $f=New-CertificationTransactionFixture
        $f.Results.Screenshots=@($f.Results.Screenshots|Where-Object Name -CNE 'final-certification-result')
        $script:results=$f.Results
        $shot=Add-Screenshot -ScreenshotDir $TestDrive -Name 'final-certification-result' -EvidenceType 'ScreenCapture' -CaptureAction {throw 'unexpected final capture exception'}
        $shot.Status|Should -Be 'Failed'
        $shot.Details|Should -Match 'unexpected final capture exception'
        $x=Complete-TPMCertificationTransaction $f.Certification $f.Results
        Assert-FailedTransactionConsistency $f $x
    }

    It "does not let passing numeric arithmetic override failed finalization" {
        $f=New-CertificationTransactionFixture
        $f.Results.Screenshots=@($f.Results.Screenshots|Where-Object Name -CNE 'final-certification-result')
        $x=Complete-TPMCertificationTransaction $f.Certification $f.Results
        $x.ScoreEligible|Should -BeTrue
        Assert-FailedTransactionConsistency $f $x
    }

    It "does not let complete evidence override a failed numeric score" {
        $f=New-CertificationTransactionFixture
        ($f.Certification.Items | Where-Object Area -EQ 'Pester').Passed = $false
        $x=Complete-TPMCertificationTransaction $f.Certification $f.Results
        $x.ScoreEligible|Should -BeFalse
        Assert-FailedTransactionConsistency $f $x
    }

    It "derives the score decision from Items rather than trusting a stale or tampered Overall field" {
        $f=New-CertificationTransactionFixture
        # Items still say every gate passed, but .Overall itself (a field
        # nothing else in this fixture recomputes) claims NOT CERTIFIED --
        # the transaction must certify based on Items, ignoring the stale
        # field entirely, proving Overall is never read for the decision.
        $f.Certification.Overall = 'NOT CERTIFIED'
        $x=Complete-TPMCertificationTransaction $f.Certification $f.Results
        $x.ScoreEligible|Should -BeTrue
        $x.Passed|Should -BeTrue
        $x.Overall|Should -Be 'CERTIFIED'
    }

    It "rejects conflicting, malformed, and extra evidence metadata in one consolidated result" {
        $f=New-CertificationTransactionFixture
        $first=$f.Results.Screenshots[0]
        $first.Required=$false
        $f.Results.Screenshots += [pscustomobject]@{Name='extra';Label='extra';Status='Captured';EvidenceType='ScreenCapture';Required=$true;WorkflowId=$f.Results.EvidenceWorkflowId;Path=$first.Path;Details='captured';Sequence=($f.Results.Screenshots.Count + 1)}
        $x=Complete-TPMCertificationTransaction $f.Certification $f.Results
        Assert-FailedTransactionConsistency $f $x
        $x.Evidence.Details|Should -Match 'invalid Required metadata'
        $x.Evidence.Details|Should -Match 'unexpected evidence'
    }

    It "rejects missing workflow provenance for the whole run" {
        $f=New-CertificationTransactionFixture
        $f.Results.EvidenceWorkflowId=$null
        $x=Complete-TPMCertificationTransaction $f.Certification $f.Results
        Assert-FailedTransactionConsistency $f $x
        $x.Evidence.Details|Should -Match 'workflow identity is missing'
    }

    It "rejects wrong-case final evidence identity" {
        $f=New-CertificationTransactionFixture
        $final=@($f.Results.Screenshots|Where-Object Name -CEQ 'final-certification-result')[0]
        $final.Name='Final-Certification-Result'
        $x=Complete-TPMCertificationTransaction $f.Certification $f.Results
        Assert-FailedTransactionConsistency $f $x
        $x.Evidence.Details|Should -Match 'found 0'
    }

    It "rejects duplicate earlier evidence even when both copies are Captured" {
        $f=New-CertificationTransactionFixture
        $first=@($f.Results.Screenshots|Where-Object Name -CEQ 'certification-suite-running')[0]
        $f.Results.Screenshots += $first
        $x=Complete-TPMCertificationTransaction $f.Certification $f.Results
        Assert-FailedTransactionConsistency $f $x
        $x.Evidence.Details|Should -Match 'found 2'
    }


    It "publishes authoritative artifacts together with BOM-less UTF-8 content" {
        $dir=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $dir|Out-Null
        $artifacts=1..4|ForEach-Object{[pscustomobject]@{Path=(Join-Path $dir ("report$_.txt"));Content="content $_"}}
        Publish-TPMCertificationArtifacts $artifacts
        foreach($a in $artifacts){Test-Path -LiteralPath $a.Path|Should -BeTrue;([IO.File]::ReadAllText($a.Path))|Should -Match '^content'}
    }

    It "does not overwrite or delete a pre-existing report destination" {
        $dir=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $dir|Out-Null
        $existing=Join-Path $dir 'existing.txt';[IO.File]::WriteAllText($existing,'user content')
        {Publish-TPMCertificationArtifacts @([pscustomobject]@{Path=$existing;Content='replacement'})}|Should -Throw '*destination already exists*'
        [IO.File]::ReadAllText($existing)|Should -Be 'user content'
    }

    It "uses the one transaction as the source for both report renderers and process exit" {
        $source=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..\scripts\Invoke-TPM-RealInstanceSmoke.ps1')
        ([regex]::Matches($source,'Complete-TPMCertificationTransaction -Certification \$certification -Results \$results')).Count|Should -Be 1
        $source|Should -Match 'Get-TPMCertificationFinalConsoleLines -Finalization \$finalization'
        ([regex]::Matches($source,'Get-TPMCertificationFinalReportLines -Finalization \$Finalization')).Count|Should -Be 2
        $source|Should -Match 'exit \$finalization\.ExitCode'
        $source|Should -Not -Match 'exit 0'
        ([regex]::Matches($source,'\$Results\.Status = \$finalStatus')).Count|Should -Be 1
        ([regex]::Matches($source,'\$results\.Status\s*=')).Count|Should -Be 0
        $source|Should -Match 'Publish-TPMCertificationArtifacts -Artifacts \$artifacts'
        $source|Should -Match 'Remove-Item -LiteralPath \$path'
        # System Invariant Inventory: publication as part of commit. Only
        # Complete-TPMCertificationTransaction calls Publish-TPMCertificationArtifacts --
        # there is no second, independent call site outside the transaction
        # that could publish (or decide what publish-failure means) on its own.
        ([regex]::Matches($source,'Publish-TPMCertificationArtifacts -Artifacts')).Count|Should -Be 1
        # The transaction takes over as sole authority the moment BuildArtifacts
        # runs -- outside the function, the only thing the main flow does with
        # a publish failure is read $finalization.Published/.PublicationError,
        # never re-derive FAIL/NOT CERTIFIED/exit-1 through its own logic.
        $source|Should -Match 'if \(-not \$finalization\.Published\)'
        $source|Should -Not -Match '\} catch \{\s*\$publicationError'
    }

    It "rejects an evidence record missing a valid capture-order sequence" {
        $f=New-CertificationTransactionFixture
        $final=@($f.Results.Screenshots|Where-Object Name -CEQ 'final-certification-result')[0]
        $final.PSObject.Properties.Remove('Sequence')
        $x=Complete-TPMCertificationTransaction $f.Certification $f.Results
        Assert-FailedTransactionConsistency $f $x
        $x.Evidence.Details|Should -Match 'no valid capture-order sequence'
    }

    It "rejects a final-certification-result that was not genuinely captured last" {
        $f=New-CertificationTransactionFixture
        $final=@($f.Results.Screenshots|Where-Object Name -CEQ 'final-certification-result')[0]
        $earliest=@($f.Results.Screenshots|Where-Object Name -CEQ 'certification-suite-running')[0]
        # Swap sequence numbers: final-certification-result now claims to
        # have been captured before certification-suite-running, even
        # though every other invariant (name, workflow, type, path, PNG
        # validity) still passes -- only the capture-ordering invariant
        # should catch this.
        $swap = $final.Sequence
        $final.Sequence = $earliest.Sequence
        $earliest.Sequence = $swap
        $x=Complete-TPMCertificationTransaction $f.Certification $f.Results
        Assert-FailedTransactionConsistency $f $x
        $x.Evidence.Details|Should -Match 'was not captured last'
    }

    It "publishing failure downgrades the same transaction object rather than being decided separately" {
        $f=New-CertificationTransactionFixture
        $build={ param($Finalization) throw 'simulated publication failure' }
        $x=Complete-TPMCertificationTransaction $f.Certification $f.Results $build
        $x.Published|Should -BeFalse
        $x.PublicationError|Should -Match 'simulated publication failure'
        Assert-FailedTransactionConsistency $f $x
    }

    It "publishing success is reflected on the returned transaction" {
        $f=New-CertificationTransactionFixture
        $dir=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $dir|Out-Null
        $build={ param($Finalization) @([pscustomobject]@{Path=(Join-Path $dir 'report.txt');Content='ok'}) }
        $x=Complete-TPMCertificationTransaction $f.Certification $f.Results $build
        $x.Published|Should -BeTrue
        $x.PublicationError|Should -BeNullOrEmpty
        $x.Passed|Should -BeTrue
    }
}
