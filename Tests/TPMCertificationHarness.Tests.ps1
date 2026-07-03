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
    foreach ($fn in $functionAsts) {
        . ([scriptblock]::Create($fn.Extent.Text))
    }

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
            Timestamp = '2026-07-03_00-00-00'
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
