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
        param([bool]$Pcsx2Present)
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
            Checks = @(
                [pscustomobject]@{ Name = 'Repository available'; Passed = $true }
                [pscustomobject]@{ Name = 'Repository clean'; Passed = $true }
                [pscustomobject]@{ Name = 'Real install health check collected'; Passed = $true }
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
