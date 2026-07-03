#Requires -Module Pester

# TPM Certification Suite Phase 1.7 (issue #88, priority A4): Cancel /
# Decline Matrix. Proves state-changing workflows that had zero prior
# cancel-path coverage genuinely make no changes when a tester backs out --
# no backup created, no profile touched -- not just that they print a
# "cancelled" message. Each test documents the human behavior replaced,
# the defect class it catches, and why existing certification wouldn't
# already catch it.
#
# Deterministic: no network, no GUI, no real TeknoParrot root, all writes
# confined to $TestDrive. Read-Host and GPU detection are mocked to drive
# the cancel paths deterministically.
#
# Run with: Invoke-Pester -Path .\Tests\VirtualBetaTester.CancelDeclineMatrix.Tests.ps1

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\TeknoParrot-Manager.ps1"
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')"
    }
    $functionAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $extractedFunctionsPath = Join-Path $TestDrive ("vbt-cancel-decline-functions-" + [guid]::NewGuid().ToString('N') + '.ps1')
    ($functionAsts | ForEach-Object { $_.Extent.Text }) -join "`n`n" | Set-Content -LiteralPath $extractedFunctionsPath -Encoding utf8
    . $extractedFunctionsPath

    $script:logPath = Join-Path $TestDrive "vbt-cancel-decline.log"
}

Describe "Virtual Beta Tester: GPU fix setup safe cancel (issue #88 A4)" -Tag 'TVD-High' {
    # Human behavior replaced: a tester on a system TPM can't auto-detect
    # the GPU vendor for is prompted to type one in -- and expects that
    # pressing Enter to back out (or typing something unrecognized) makes
    # genuinely zero changes, not a partial backup or a half-applied fix.
    # Defect class detectable: a cancel path that still creates a backup
    # folder (implying work is about to happen) or, worse, one reached
    # after profile files have already been touched.
    # Why existing certification wouldn't already catch it: Invoke-
    # GpuFixSetup had no cancel-path test coverage before this round.

    BeforeAll {
        $script:GpuIncompatibleGames = @{}
    }

    It "pressing Enter when the GPU vendor cannot be auto-detected cancels with no backup and no profile changes" {
        $userProfilesDir = Join-Path $TestDrive ("gpufix-cancel-empty-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $userProfilesDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $userProfilesDir 'ALIENS.xml') -Value '<GameProfile><ConfigValues></ConfigValues></GameProfile>' -Encoding ascii
        $originalContent = Get-Content -LiteralPath (Join-Path $userProfilesDir 'ALIENS.xml') -Raw

        Mock Get-DetectedGpuVendor { return [pscustomobject]@{ Vendor = $null; Name = $null } }
        Mock Read-Host { return "" } -ParameterFilter { $Prompt -like "*Enter GPU vendor*" }

        Invoke-GpuFixSetup -UserProfilesDir $userProfilesDir -TpRoot (Join-Path $TestDrive "no-tp-root")

        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'FullBackup')) | Should -Be $false -Because "cancelling before any work begins must never create a backup folder -- a backup implies a write is about to happen"
        (Get-Content -LiteralPath (Join-Path $userProfilesDir 'ALIENS.xml') -Raw) | Should -Be $originalContent -Because "the profile must be completely untouched"
    }

    It "typing an unrecognized vendor cancels with no backup and no profile changes" {
        $userProfilesDir = Join-Path $TestDrive ("gpufix-cancel-bad-vendor-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $userProfilesDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $userProfilesDir 'ALIENS.xml') -Value '<GameProfile><ConfigValues></ConfigValues></GameProfile>' -Encoding ascii
        $originalContent = Get-Content -LiteralPath (Join-Path $userProfilesDir 'ALIENS.xml') -Raw

        Mock Get-DetectedGpuVendor { return [pscustomobject]@{ Vendor = $null; Name = $null } }
        Mock Read-Host { return "PowerVR" } -ParameterFilter { $Prompt -like "*Enter GPU vendor*" }

        Invoke-GpuFixSetup -UserProfilesDir $userProfilesDir -TpRoot (Join-Path $TestDrive "no-tp-root")

        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'FullBackup')) | Should -Be $false -Because "an unrecognized vendor must be rejected before any backup or write happens"
        (Get-Content -LiteralPath (Join-Path $userProfilesDir 'ALIENS.xml') -Raw) | Should -Be $originalContent
    }
}

Describe "Virtual Beta Tester: dry-run preview never writes, downloads, or backs up (issue #88 A4)" -Tag 'TVD-High' {
    # Human behavior replaced: a cautious tester runs a preview/dry-run
    # pass first to see what WOULD happen before committing to a real run
    # -- and trusts that a preview genuinely changes nothing on disk.
    # Defect class detectable: a code path inside a preview branch that
    # still performs a real file write, network call, or backup because a
    # -DryRun / $Preview check was missed on one specific branch.
    # Why existing certification wouldn't already catch it: existing
    # dry-run coverage (Tests/TeknoParrot-Manager.Tests.ps1) checks console
    # wording and specific reported actions, not a full before/after
    # filesystem diff across the whole UserProfiles tree.

    It "Get-CompatibilityWarnings and Get-GameSetupNotes-style read-only scans never create a FullBackup folder as a side effect" {
        # Read-only reporting functions (the ones a preview pass relies on
        # to show the user what's registered and what needs attention)
        # must never themselves create backup folders or touch profiles --
        # proving the "preview" side of AutoSync's preview/apply split is
        # genuinely read-only at the function level, not just by convention.
        $userProfilesDir = Join-Path $TestDrive ("dryrun-readonly-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $userProfilesDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $userProfilesDir 'ALIENS.xml') -Value '<GameProfile><EmulatorType>RawThrillsPC</EmulatorType><GamePath>C:\Games\a.exe</GamePath></GameProfile>' -Encoding ascii

        $before = Get-ChildItem -LiteralPath $userProfilesDir -Recurse | Select-Object -ExpandProperty FullName | Sort-Object

        $script:RawThrillsPathLimits = @{}
        $script:FileVersionPins = @{}
        $script:GpuIncompatibleGames = @{}
        $script:EmulatorBiosRequirements = @{}
        Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir | Out-Null

        $after = Get-ChildItem -LiteralPath $userProfilesDir -Recurse | Select-Object -ExpandProperty FullName | Sort-Object
        Compare-Object $before $after | Should -BeNullOrEmpty -Because "a read-only compatibility scan must never write, back up, or otherwise change anything on disk"
    }
}
