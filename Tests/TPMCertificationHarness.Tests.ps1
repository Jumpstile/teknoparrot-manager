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
}
