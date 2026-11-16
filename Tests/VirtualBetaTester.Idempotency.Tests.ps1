#Requires -Module Pester

# TPM Certification Suite Phase 1 (issue #88): idempotency / repeat-run
# coverage. Replaces the specific human-tester behavior of "run it again to
# make sure nothing changed" -- a real user re-running a setup step is not
# an edge case, it is routine, and a state-writing operation that drifts on
# a second identical run (duplicated entries, corrupted structure, doubled
# writes) would be exactly the kind of bug a scripted single-run test never
# catches.
#
# New-TpmVerifiedUserProfilesBackup is the target: a real production function
# that is deterministic, has no network dependency, and works on a folder under
# $TestDrive -- a clean, safe subject for this pattern.
#
# Run with: Invoke-Pester -Path .\Tests\VirtualBetaTester.Idempotency.Tests.ps1

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\TeknoParrot-Manager.ps1"
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')"
    }
    $functionAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $extractedFunctionsPath = Join-Path $TestDrive ("vbt-idempotency-functions-" + [guid]::NewGuid().ToString('N') + '.ps1')
    ($functionAsts | ForEach-Object { $_.Extent.Text }) -join "`n`n" | Set-Content -LiteralPath $extractedFunctionsPath -Encoding utf8
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force
    . $extractedFunctionsPath
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    $script:PostgresRecoveryStatus = $null
    $script:PostgresRecoveryResumeState = $null

    $script:logPath = Join-Path $TestDrive "vbt-idempotency.log"
    $script:RawThrillsPathLimits = @{}
    $script:FuzzyAutoThreshold = 0.72
    $script:FuzzyTieMargin = 0.1
    $script:TitleTokenStopWords = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('the', 'of', 'a', 'an', 'and', 'vs', 'vs.', 'in', 'for', 'to'),
        [System.StringComparer]::OrdinalIgnoreCase)
}

Describe "Virtual Beta Tester: repeat-run backup safety (issue #88 phase 1.5 priority 2)" -Tag 'TVD-High' {
    # New-TpmVerifiedUserProfilesBackup (the current verified UserProfiles
    # backup API; the earlier New-PropagationBackup no longer exists):
    # replaces the instinctive "run it again just to
    # be sure" a human tester does after Propagate Controls, plus the
    # specific defect class this catches -- a backup routine recursively
    # backing up its OWN prior backups (FullBackup\FullBackup\FullBackup\...)
    # on repeated runs, silently ballooning disk usage and directory depth.
    # Tests/TeknoParrot-Manager.Tests.ps1 does not cover this function at all
    # (single-run behavior only would still miss a repeat-run-specific
    # nesting bug even if it did).
    # Tester Value Density: High -- deterministic, cheap to maintain, and
    # catches an unbounded-growth defect class that would otherwise only
    # surface after months of real repeated use on a real machine.

    It "running New-TpmVerifiedUserProfilesBackup three times in a row never backs up its own previous backups" {
        $userProfilesDir = Join-Path $TestDrive ("propagation-backup-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $userProfilesDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $userProfilesDir 'ALIENS.xml') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $userProfilesDir 'TIMECRS4.xml') -Force | Out-Null

        $results = @()
        for ($i = 1; $i -le 3; $i++) {
            # Folder names carry a millisecond timestamp plus a GUID, so back-to-back runs need no sleep to stay distinct.
            $results += New-TpmVerifiedUserProfilesBackup -UserProfilesDir $userProfilesDir -Label 'PropagateControls'
        }

        foreach ($result in $results) {
            $result.Succeeded | Should -BeTrue -Because "a repeat backup run must not fail even once FullBackup itself exists (reason: $($result.Reason))"
            $result.Verified | Should -BeTrue -Because "every repeat backup must pass its own manifest verification"
            $result.FailureStage | Should -BeNullOrEmpty
        }

        $backupRoot = Join-Path $userProfilesDir 'FullBackup'
        $backupFolders = @(Get-ChildItem -LiteralPath $backupRoot -Directory)
        $backupFolders.Count | Should -Be 3 -Because "three runs must produce three distinct timestamped backups, not fewer (skipped) or more (duplicated)"

        foreach ($folder in $backupFolders) {
            (Test-Path -LiteralPath (Join-Path $folder.FullName 'FullBackup')) | Should -Be $false -Because "a backup must never contain a nested copy of the backup folder itself -- unbounded nesting growth on repeat runs is exactly the bug this test exists to catch"
            @(Get-ChildItem -LiteralPath $folder.FullName -File -Filter '*.xml').Count | Should -Be 2 -Because "every backup, including the third consecutive one, must still contain both real profile files"
        }
    }
}

Describe "Virtual Beta Tester: AutoSync repeat-run idempotency (issue #88 phase 1.5 priority 1)" -Tag 'TVD-High' {
    # Human behavior replaced: running AutoSync a second time and confirming
    # it correctly recognizes already-extracted games instead of re-prompting
    # or re-flagging them as "available to extract" -- the single highest-
    # value repeat-run check per the approved priority list.
    # Defect class this catches: extraction-skip resolution drifting between
    # runs (a game correctly recognized as extracted on run 1 but not on run
    # 2, or vice versa) -- silent, hard to notice, and exactly the kind of
    # "it worked yesterday" bug a single-run test structurally cannot see.
    # Why existing certification doesn't already catch it: Register-Games'
    # full matching pipeline is deliberately excluded from the general
    # regression suite as too complex to black-box test comprehensively
    # (Tests/TeknoParrot-Manager.Tests.ps1); this targets the narrower,
    # already-shared resolver AutoSync itself calls to decide "is this
    # already extracted," not the full registration pipeline.
    # Tester Value Density: High -- deterministic, low maintenance (a pure
    # read-only resolver, not the whole registration pipeline), exercises a
    # realistic user behavior (running AutoSync twice), and replaces a check
    # a thorough human tester does on every release, every time.

    It "Resolve-ExtractedGameFolder gives the identical answer on a simulated second AutoSync pass" {
        $installFolder = Join-Path $TestDrive ("autosync-repeat-" + [guid]::NewGuid().ToString('N'))
        $gameFolder = Join-Path $installFolder 'Aliens Armageddon (1.04)(2014-11-17)[Raw Thrills PC][TP]'
        New-Item -ItemType Directory -Path $gameFolder -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $gameFolder 'ALIENS.exe') -Force | Out-Null

        $rawZipName = 'Aliens Armageddon (1.04)(2014-11-17)[Raw Thrills PC][TP]'

        # First "AutoSync run": the folder map is built fresh, same as a real
        # first pass would.
        $firstRunResult = Resolve-ExtractedGameFolder -RawZipName $rawZipName -InstallFolder $installFolder

        # Second "AutoSync run": nothing on disk changed (no extraction
        # happened -- it was already there), so a fresh folder-map build must
        # resolve to the exact same answer, not skip it or find a different
        # path.
        $secondRunResult = Resolve-ExtractedGameFolder -RawZipName $rawZipName -InstallFolder $installFolder

        $firstRunResult | Should -Not -BeNullOrEmpty -Because "an already-extracted game with a real exe must resolve on the first pass"
        $secondRunResult | Should -Be $firstRunResult -Because "a second pass over an unchanged install must resolve identically to the first -- this is what stops AutoSync from re-prompting to re-extract a game that's already there"
    }

    It "an already-extracted game produces zero unexpected filesystem changes across two resolution passes" {
        $installFolder = Join-Path $TestDrive ("autosync-repeat-nowrite-" + [guid]::NewGuid().ToString('N'))
        $gameFolder = Join-Path $installFolder 'Time Crisis 4'
        New-Item -ItemType Directory -Path $gameFolder -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $gameFolder 'TIMECRS4.exe') -Force | Out-Null

        $before = Get-ChildItem -LiteralPath $installFolder -Recurse | Select-Object -ExpandProperty FullName | Sort-Object

        Resolve-ExtractedGameFolder -RawZipName 'Time Crisis 4' -InstallFolder $installFolder | Out-Null
        Resolve-ExtractedGameFolder -RawZipName 'Time Crisis 4' -InstallFolder $installFolder | Out-Null

        $after = Get-ChildItem -LiteralPath $installFolder -Recurse | Select-Object -ExpandProperty FullName | Sort-Object
        Compare-Object $before $after | Should -BeNullOrEmpty -Because "resolving whether a game is already extracted must never itself write anything, on the first pass or a repeat"
    }
}

Describe "Virtual Beta Tester: preview / dry-run makes no changes (issue #88 phase 1.5 priority 2)" -Tag 'TVD-Medium' {
    # Human behavior replaced: a user running Preview/dry-run mode, seeing
    # what WOULD happen, and trusting that declining to proceed for real
    # left nothing changed -- the "look before you leap" check every
    # cautious tester does before a state-changing operation.
    # Defect class this catches: a DryRun flag that's checked in some code
    # paths but not others, silently writing a UserProfile despite the user
    # having only asked to preview.
    # Why existing certification doesn't already catch it: Register-Games is
    # excluded from the general regression suite's black-box matching tests;
    # this is a narrower, different question (does DryRun=$true guarantee
    # zero writes) that a matching-correctness test wouldn't necessarily
    # exercise even if it did cover Register-Games.
    # Tester Value Density: Medium -- deterministic and low maintenance, but
    # a narrower realistic behavior (fewer testers explicitly verify the
    # dry-run write-safety guarantee than verify basic registration) than the
    # AutoSync repeat-run check above.

    It "Register-Games -DryRun reports what would happen but writes zero UserProfile files" {
        $root = Join-Path $TestDrive ("preview-decline-" + [guid]::NewGuid().ToString('N'))
        $installFolder = Join-Path $root 'Games'
        $userProfilesDir = Join-Path $root 'UserProfiles'
        $gameProfilesDir = Join-Path $root 'GameProfiles'
        New-Item -ItemType Directory -Path $installFolder, $userProfilesDir, $gameProfilesDir -Force | Out-Null

        $gameFolder = Join-Path $installFolder 'Aliens Armageddon (1.04)'
        New-Item -ItemType Directory -Path $gameFolder -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $gameFolder 'ALIENS.exe') -Force | Out-Null

        $profileXml = [xml]@'
<?xml version="1.0" encoding="utf-8"?>
<GameProfile>
  <ExecutableName>ALIENS.exe</ExecutableName>
  <EmulationProfile>RawThrills</EmulationProfile>
  <ConfigValues></ConfigValues>
</GameProfile>
'@
        $profileXml.Save((Join-Path $gameProfilesDir 'ALIENS.xml'))

        $profileIndex = Build-ProfileIndex -gameProfilesDir $gameProfilesDir
        $before = Get-ChildItem -LiteralPath $root -Recurse | Select-Object -ExpandProperty FullName | Sort-Object

        $result = Register-Games -userProfilesDir $userProfilesDir -installFolder $installFolder `
            -profileIndex $profileIndex -gameProfilesDir $gameProfilesDir -DryRun $true

        $after = Get-ChildItem -LiteralPath $root -Recurse | Select-Object -ExpandProperty FullName | Sort-Object

        @($result.Registered).Count | Should -BeGreaterThan 0 -Because "a preview must still report what it WOULD register -- the user needs to see the expected outcome, not just 'nothing happened'"
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'ALIENS.xml')) | Should -Be $false -Because "DryRun means preview only -- declining to proceed for real must leave zero UserProfile files written"
        Compare-Object $before $after | Should -BeNullOrEmpty -Because "a declined/preview-only run must produce no filesystem changes anywhere, not just no UserProfiles writes specifically"
    }
}
