#Requires -Module Pester

# TPM Certification Suite Phase 1.6 (issue #88): Recovery Behavioral
# Certification. Replaces the recovery-focused verification a careful human
# beta tester naturally performs before trusting a release -- not "does the
# happy path work," but "what happens when the state isn't clean." Each test
# below documents the human behavior replaced, the defect class it catches,
# and why the existing suite (Phase 1/1.5) wouldn't already catch it.
#
# Deterministic: no network, no GUI, no real TeknoParrot root, all writes
# confined to $TestDrive. Assertions favor behavioral invariants (call
# counts, object counts, filesystem diffs) over console transcripts.
#
# Run with: Invoke-Pester -Path .\Tests\VirtualBetaTester.Recovery.Tests.ps1

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\TeknoParrot-Manager.ps1"
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')"
    }
    $functionAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $extractedFunctionsPath = Join-Path $TestDrive ("vbt-recovery-functions-" + [guid]::NewGuid().ToString('N') + '.ps1')
    ($functionAsts | ForEach-Object { $_.Extent.Text }) -join "`n`n" | Set-Content -LiteralPath $extractedFunctionsPath -Encoding utf8
    . $extractedFunctionsPath
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    $script:PostgresRecoveryStatus = $null
    $script:PostgresRecoveryResumeState = $null

    $resolvePcsx2Path = Join-Path $PSScriptRoot "..\scripts\Resolve-Pcsx2Directory.ps1"
    . $resolvePcsx2Path

    $script:logPath = Join-Path $TestDrive "vbt-recovery.log"
    $script:RawThrillsPathLimits = @{}
    $script:FileVersionPins = @{}
    $script:GpuIncompatibleGames = @{}
    $script:FuzzyAutoThreshold = 0.72
    $script:FuzzyTieMargin = 0.1
    $script:TitleTokenStopWords = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('the', 'of', 'a', 'an', 'and', 'vs', 'vs.', 'in', 'for', 'to'),
        [System.StringComparer]::OrdinalIgnoreCase)

    # ECVF (issue #182 follow-up): file-backed fixture used only by the
    # cursor-path denial tests below. Copies the real, currently-shipped
    # Authority/Contracts modules and the real pcsx2x6 contract.json into a
    # $TestDrive tree shaped like the repo (scripts\, contracts\pcsx2x6\),
    # then re-extracts and dot-sources ONLY Set-Pcsx2CursorPaths from
    # inside that tree so its $PSScriptRoot resolves there. This makes the
    # function actually import the module and consult the real contract,
    # exercising the genuine OWNERSHIP_VIOLATION denial path -- not just
    # the generic "framework unavailable" fallback that fires elsewhere in
    # this file because the plain extracted-functions file has no scripts\
    # folder beside it. Dot-sourcing the returned path inside a single It
    # block only redefines Set-Pcsx2CursorPaths for that It's own scope; it
    # does not affect the other extracted functions or any other test.
    function New-Pcsx2ContractDenialFixture {
        $fixtureRoot = Join-Path $TestDrive ("ecvf-fixture-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'scripts') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'contracts\pcsx2x6') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TPMCertification.Authority.psm1') -Destination (Join-Path $fixtureRoot 'scripts\TPMCertification.Authority.psm1') -Force
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TPMCertification.Contracts.psm1') -Destination (Join-Path $fixtureRoot 'scripts\TPMCertification.Contracts.psm1') -Force
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\contracts\pcsx2x6\contract.json') -Destination (Join-Path $fixtureRoot 'contracts\pcsx2x6\contract.json') -Force

        $pcsx2Ast = $functionAsts | Where-Object { $_.Name -eq 'Set-Pcsx2CursorPaths' } | Select-Object -First 1
        if (-not $pcsx2Ast) { throw "Set-Pcsx2CursorPaths not found while building the ECVF contract-denial fixture" }
        $pcsx2FixturePath = Join-Path $fixtureRoot 'Set-Pcsx2CursorPaths.ps1'
        $pcsx2Ast.Extent.Text | Set-Content -LiteralPath $pcsx2FixturePath -Encoding utf8
        return $pcsx2FixturePath
    }

    # ECVF (issue #173): same $PSScriptRoot-anchored fixture-tree pattern as
    # New-Pcsx2ContractDenialFixture above, extended to the new pcsx2x6
    # first-run-automation functions so they too actually import the real
    # Contracts module and consult the real contract rather than falling
    # back to "framework unavailable". Write-Log is not included -- it is
    # already dot-sourced into this file's top-level scope from the full
    # functionAsts extraction in the outer BeforeAll and remains resolvable
    # from there once these functions are re-dot-sourced into a single It's
    # local scope.
    function New-Pcsx2AutomationFixture {
        $fixtureRoot = Join-Path $TestDrive ("ecvf-automation-fixture-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'scripts') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'contracts\pcsx2x6') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TPMCertification.Authority.psm1') -Destination (Join-Path $fixtureRoot 'scripts\TPMCertification.Authority.psm1') -Force
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TPMCertification.Contracts.psm1') -Destination (Join-Path $fixtureRoot 'scripts\TPMCertification.Contracts.psm1') -Force
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\contracts\pcsx2x6\contract.json') -Destination (Join-Path $fixtureRoot 'contracts\pcsx2x6\contract.json') -Force

        $names = @('Get-Pcsx2CrosshairPrerequisiteState', 'Invoke-Pcsx2FirstRunSetup', 'Get-Pcsx2CursorPathReport', 'Test-Pcsx2ProcessRunning')
        $wanted = @($functionAsts | Where-Object { $names -contains $_.Name })
        if ($wanted.Count -lt $names.Count) { throw "One or more required functions were not found while building the ECVF automation fixture (found: $(@($wanted.Name) -join ', '))" }
        $fixturePath = Join-Path $fixtureRoot 'Pcsx2Automation.ps1'
        ($wanted | ForEach-Object { $_.Extent.Text }) -join "`n`n" | Set-Content -LiteralPath $fixturePath -Encoding utf8
        return $fixturePath
    }

    # Builds a synthetic pcsx2x6 install tree (separate from the
    # $PSScriptRoot-anchored fixture above -- Pcsx2Dir is a plain parameter,
    # not resolved via $PSScriptRoot) for Get-Pcsx2CrosshairPrerequisiteState
    # state-classification tests.
    function New-Pcsx2InstallFixture {
        param([switch]$IncludeExecutable, [switch]$Initialized, [switch]$IncludePngs, [string]$PortableTxtContent)
        $installRoot = Join-Path $TestDrive ("pcsx2-install-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
        if ($IncludeExecutable) { [IO.File]::WriteAllText((Join-Path $installRoot 'pcsx2-qtx64.exe'), '') }
        $dataRootLeaf = 'TeknoParrot'
        if ($PSBoundParameters.ContainsKey('PortableTxtContent')) {
            [IO.File]::WriteAllText((Join-Path $installRoot 'portable.txt'), $PortableTxtContent)
            if (-not [string]::IsNullOrWhiteSpace($PortableTxtContent)) { $dataRootLeaf = $PortableTxtContent }
        }
        $dataRoot = Join-Path $installRoot $dataRootLeaf
        if ($Initialized) {
            New-Item -ItemType Directory -Path (Join-Path $dataRoot 'inis') -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $dataRoot 'inis\PCSX2.ini'), "[USB1]`r`nType = None`r`n[USB2]`r`nType = None`r`n[JVS]`r`n")
        }
        if ($IncludePngs) {
            New-Item -ItemType Directory -Path (Join-Path $dataRoot 'crosshairs') -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $dataRoot 'crosshairs\P1.png'), 'x')
            [IO.File]::WriteAllText((Join-Path $dataRoot 'crosshairs\P2.png'), 'x')
        }
        return $installRoot
    }

    function New-Pcsx2CrosshairSetupFixture {
        $fixtureRoot = Join-Path $TestDrive ("crosshair-setup-fixture-" + [guid]::NewGuid().ToString('N'))
        $crosshairsRoot = Join-Path $fixtureRoot 'Crosshairs'
        $pcsx2Root = Join-Path $fixtureRoot 'pcsx2x6'
        $profilesRoot = Join-Path $fixtureRoot 'UserProfiles'
        New-Item -ItemType Directory -Path $crosshairsRoot, $pcsx2Root, $profilesRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\Crosshairs\000.png') -Destination (Join-Path $crosshairsRoot '000.png') -Force
        [IO.File]::WriteAllText((Join-Path $profilesRoot 'LIGHTGUN.xml'), '<GameProfile><GunGame>true</GunGame><EmulatorType>Pcsx2x6</EmulatorType></GameProfile>')

        $names = @('Invoke-CrosshairSetup', 'Get-Pcsx2CrosshairPrerequisiteState')
        $wanted = @($functionAsts | Where-Object { $names -contains $_.Name })
        if ($wanted.Count -lt $names.Count) { throw "Crosshair setup fixture functions were not found" }
        $fixturePath = Join-Path $fixtureRoot 'CrosshairSetup.ps1'
        ($wanted | ForEach-Object { $_.Extent.Text }) -join [Environment]::NewLine | Set-Content -LiteralPath $fixturePath -Encoding utf8
        return [pscustomobject]@{
            Root = $fixtureRoot
            Pcsx2Root = $pcsx2Root
            ProfilesRoot = $profilesRoot
            FixturePath = $fixturePath
        }
    }
}

Describe "Virtual Beta Tester: existing-backup recovery (issue #88 phase 1.6)" -Tag 'TVD-Medium' {
    # Human behavior replaced: a tester who already ran Propagate Controls
    # once, checks that running it again alongside the existing backup
    # doesn't disturb it -- not "does backup work" (already covered by
    # phase 1.5's repeat-run test), but specifically "does a NEW backup
    # coexist safely with an OLDER one already sitting there."
    # Defect class detectable: a backup routine that lists/enumerates
    # FullBackup's existing contents incorrectly and either overwrites an
    # older backup or fails when one is already present.
    # Why existing certification wouldn't already catch it: phase 1.5's
    # idempotency test always starts from an empty FullBackup folder across
    # its three repeat runs; this test pre-seeds an unrelated older backup
    # (a different timestamp, as if from a previous session) before the run
    # under test, which the repeat-run test never does.
    # Tester Value Density: Medium -- deterministic and cheap, but a
    # narrower condition than the basic repeat-run check.

    It "a new backup is added alongside a pre-existing older backup without disturbing it" {
        $userProfilesDir = Join-Path $TestDrive ("existing-backup-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $userProfilesDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $userProfilesDir 'ALIENS.xml') -Force | Out-Null

        $olderBackupDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2020-01-01_00-00-00'
        New-Item -ItemType Directory -Path $olderBackupDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $olderBackupDir 'OLDGAME.xml') -Force | Out-Null
        $olderBackupContentBefore = Get-Content -LiteralPath (Join-Path $olderBackupDir 'OLDGAME.xml') -Raw -ErrorAction SilentlyContinue

        $result = New-PropagationBackup -UserProfilesDir $userProfilesDir

        $result.ErrorCount | Should -Be 0 -Because "a pre-existing older backup must not cause the new backup to error"
        (Test-Path -LiteralPath $olderBackupDir) | Should -Be $true -Because "the older backup must still exist, untouched"
        (Get-Content -LiteralPath (Join-Path $olderBackupDir 'OLDGAME.xml') -Raw -ErrorAction SilentlyContinue) | Should -Be $olderBackupContentBefore -Because "the older backup's own content must be byte-identical after a new backup runs alongside it"
        (Test-Path -LiteralPath (Join-Path $result.Path 'ALIENS.xml')) | Should -Be $true -Because "the new backup must still contain the current real profile"
    }
}

Describe "Virtual Beta Tester: partial/malformed state recovery (issue #88 phase 1.6)" -Tag 'TVD-High' {
    # Human behavior replaced: a tester whose PCSX2.ini is missing sections
    # entirely (a fresh PCSX2 install that's never had a controller
    # configured) checks that crosshair setup does not crash and, per the
    # ECVF contract (issue #182), correctly leaves emulator-owned state
    # alone rather than guessing at a repair.
    # Defect class detectable: an INI writer that throws on partial/missing
    # state, or one that "recovers" by writing into a setting the contract
    # marks Owner=Emulator/NeverWrite -- USB1/USB2 guncon2_cursor_path is
    # contract-owned by the emulator (the emulator clears it in memory
    # whenever JVS mode is LIGHTGUN regardless of INI contents), so the
    # correct recovery behavior for missing/partial guncon2 sections is to
    # deny the write and leave the file exactly as found, not to append or
    # repair sections TPM does not own.
    # Why existing certification wouldn't already catch it: phase 1's
    # idempotency test always starts from an INI that already has both
    # sections present; this test starts from an INI with neither/one
    # section, which is where a naive "always deny" implementation could
    # still accidentally special-case a repair path.
    # Tester Value Density: High -- a fresh/partial PCSX2 install missing
    # guncon2 sections is a realistic, likely first-time-setup condition,
    # not a contrived edge case.

    It "Set-Pcsx2CursorPaths denies the write and leaves an INI with neither guncon2 section untouched" {
        $iniPath = Join-Path $TestDrive ("pcsx2-missing-sections-" + [guid]::NewGuid().ToString('N') + '.ini')
        @('[Frame]', 'GS = 1') -join "`r`n" | Set-Content -LiteralPath $iniPath -Encoding utf8
        $originalContent = Get-Content -LiteralPath $iniPath -Raw

        $result = Set-Pcsx2CursorPaths -IniPath $iniPath -P1Path 'p1.png' -P2Path 'p2.png'

        $result | Should -Be $false -Because "USB1/USB2 guncon2_cursor_path is Owner=Emulator, WritePolicy=NeverWrite -- missing sections must not be appended by TPM"
        (Get-Content -LiteralPath $iniPath -Raw) | Should -Be $originalContent -Because "a denied write must leave an INI with neither guncon2 section exactly as found, not partially repaired"
    }

    It "Set-Pcsx2CursorPaths denies the write and leaves an INI with only one existing guncon2 section untouched" {
        $iniPath = Join-Path $TestDrive ("pcsx2-one-section-" + [guid]::NewGuid().ToString('N') + '.ini')
        @('[USB Port 1 guncon2]', 'cursor_path = old.png') -join "`r`n" | Set-Content -LiteralPath $iniPath -Encoding utf8
        $originalContent = Get-Content -LiteralPath $iniPath -Raw

        $result = Set-Pcsx2CursorPaths -IniPath $iniPath -P1Path 'p1.png' -P2Path 'p2.png'

        $result | Should -Be $false -Because "a partially-present pair of emulator-owned sections must still be denied, not repaired by adding the missing one"
        (Get-Content -LiteralPath $iniPath -Raw) | Should -Be $originalContent -Because "the existing section's own emulator-owned cursor_path value must also remain untouched, not just the missing section left absent"
    }

    It "denies the write for the real reason even on partial/malformed state -- the contract's OWNERSHIP_VIOLATION, not just an unreachable framework (file-backed ECVF fixture)" {
        # The two tests above run Set-Pcsx2CursorPaths as extracted into the
        # plain $TestDrive functions file, which has no scripts\ folder
        # beside it -- that exercises the generic "framework unavailable"
        # fallback, not the contract itself. This test dot-sources a
        # fixture-scoped copy of just this one function (see
        # New-Pcsx2ContractDenialFixture in BeforeAll above) so it actually
        # loads the real Contracts module and the real pcsx2x6 contract,
        # proving the denial comes from the contract's own ownership rule
        # even when the INI is missing sections, not merely from the
        # framework being unreachable.
        . (New-Pcsx2ContractDenialFixture)
        $iniPath = Join-Path $TestDrive ("pcsx2-real-contract-partial-" + [guid]::NewGuid().ToString('N') + '.ini')
        @('[Frame]', 'GS = 1') -join "`r`n" | Set-Content -LiteralPath $iniPath -Encoding utf8
        $originalContent = Get-Content -LiteralPath $iniPath -Raw
        Mock Write-Log {}

        $result = Set-Pcsx2CursorPaths -IniPath $iniPath -P1Path 'p1.png' -P2Path 'p2.png'

        $result | Should -Be $false
        (Get-Content -LiteralPath $iniPath -Raw) | Should -Be $originalContent -Because "the real pcsx2x6 contract denies the write regardless of how incomplete the existing INI is"
        Should -Invoke Write-Log -ParameterFilter { $msg -match 'OWNERSHIP_VIOLATION' } -Because "the skip reason must come from the real contract's ownership check even on partial/malformed state, proving this exercised actual contract denial rather than the generic framework-unavailable fallback"
    }
}

Describe "Virtual Beta Tester: missing-dependency recovery (issue #88 phase 1.6)" -Tag 'TVD-High' {
    # Human behavior replaced: a tester whose install has no pcsx2x6 folder
    # at all (most installs don't -- it's specific to a handful of lightgun
    # titles) checks that the resolver correctly reports "not present"
    # instead of guessing or throwing.
    # Defect class detectable: a resolver that throws, or worse, silently
    # returns a wrong/stale path when the dependency genuinely doesn't
    # exist, rather than a clean null.
    # Why existing certification wouldn't already catch it: the messy
    # fixture (phase 1) always includes a pcsx2x6-shaped folder (PCSX2x6);
    # no existing VirtualBetaTester test exercises the "genuinely absent"
    # case directly.
    # Tester Value Density: High -- most real installs are exactly this
    # case (no pcsx2x6 folder), so this is the single most common condition
    # the resolver needs to get right, not a rare edge case.

    It "Resolve-Pcsx2Directory returns null cleanly when no pcsx2-shaped folder exists at all" {
        $root = Join-Path $TestDrive ("no-pcsx2-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'GameProfiles') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'UserProfiles') -Force | Out-Null

        $result = $null
        { $result = Resolve-Pcsx2Directory -TeknoParrotRoot $root } | Should -Not -Throw
        $result | Should -BeNullOrEmpty -Because "an install with no pcsx2x6-shaped folder must resolve to a clean null, not throw or guess"
    }
}

Describe "Virtual Beta Tester: missing emulator firmware/BIOS recovery (issue #85 tier 1 / issue #88 phase 1.6)" -Tag 'TVD-High' {
    # Human behavior replaced: a tester who registered a pcsx2x6 lightgun
    # game (successfully, per issue #79's own fix), launches it, and only
    # then discovers the emulator's own firmware was never installed --
    # exactly the real-world sequence documented in issue #85: a real
    # install showed Bloody Roar 3 registered and launchable, then failing
    # at launch with "PCSX2x64 Firmware is not installed." This test
    # verifies TPM catches that gap earlier, read-only, during a normal run
    # rather than leaving the user to discover it at launch.
    # Defect class detectable: a detection check that never fires (silently
    # missing games with real firmware gaps), or one that incorrectly reads/
    # modifies the firmware files themselves rather than just checking they
    # exist.
    # Why existing certification wouldn't already catch it: no existing
    # test (phase 1/1.5/1.6, or Tests/TeknoParrot-Manager.Tests.ps1 before
    # this round) exercised Get-CompatibilityWarnings' BiosMissing category
    # at all -- it did not exist before issue #85 tier 1.

    BeforeAll {
        $script:EmulatorBiosRequirements = @{
            'Pcsx2x6' = @{ RelativeDir = 'TeknoParrot\bios'; RequiredFiles = @('27v1602T.d', '27v1602F.bg') }
        }
    }

    It "detects missing pcsx2x6 firmware for a registered game without reading or modifying any file content" {
        $root = Join-Path $TestDrive ("bios-recovery-" + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        New-Item -ItemType Directory -Path $userProfilesDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'pcsx2x6') -Force | Out-Null
        [xml]@'
<?xml version="1.0" encoding="utf-8"?>
<GameProfile>
  <EmulatorType>Pcsx2x6</EmulatorType>
  <GamePath>C:\Games\BloodyRoar3\br3.exe</GamePath>
</GameProfile>
'@ | ForEach-Object { $_.Save((Join-Path $userProfilesDir 'BLOODYROAR3.xml')) }

        $before = Get-ChildItem -LiteralPath $root -Recurse | Select-Object -ExpandProperty FullName | Sort-Object

        $result = Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir -TeknoParrotRoot $root

        $after = Get-ChildItem -LiteralPath $root -Recurse | Select-Object -ExpandProperty FullName | Sort-Object
        Compare-Object $before $after | Should -BeNullOrEmpty -Because "detecting missing firmware must never itself write anything -- existence-only, read-only"

        @($result.BiosMissing).Count | Should -Be 1
        @($result.BiosMissing[0].AffectedGames) | Should -Contain 'BLOODYROAR3' -Because "the affected game must be identifiable so the user knows which registration triggered the warning"
    }
}

Describe "Virtual Beta Tester: existing-registration recovery (issue #88 phase 1.6)" -Tag 'TVD-High' {
    # Human behavior replaced: a tester who already registered a game (via
    # TeknoParrotUI or a previous run) checks that re-running registration
    # doesn't overwrite their existing profile or duplicate work -- the
    # "already-completed operation" and "safe no-op recovery" categories
    # together, exercised as one realistic scenario.
    # Defect class detectable: registration logic that doesn't check for an
    # existing UserProfile before writing, silently discarding any manual
    # edits a user made to that profile (custom controls, resolution, etc.).
    # Why existing certification wouldn't already catch it: phase 1.5's
    # DryRun test starts from an EMPTY UserProfiles directory; this test
    # starts from one that already has a real, pre-existing UserProfile for
    # the game being "registered" again.
    # Tester Value Density: High -- silently overwriting a user's existing
    # customized profile would be a severe, trust-destroying defect, and
    # this is a common real scenario (re-running AutoSync on a library that
    # already has some games registered).

    It "an already-registered game is recognized as Already, not re-written, and its existing file is untouched" {
        $root = Join-Path $TestDrive ("existing-reg-" + [guid]::NewGuid().ToString('N'))
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

        # Simulates a real, already-registered UserProfile -- as if
        # TeknoParrotUI or a previous run already created it, with
        # user-specific content (a custom GamePath a real user would have).
        $existingUserProfile = Join-Path $userProfilesDir 'ALIENS.xml'
        $existingContent = @'
<?xml version="1.0" encoding="utf-8"?>
<GameProfile>
  <GamePath>C:\CustomUserPath\ALIENS.exe</GamePath>
  <EmulationProfile>RawThrills</EmulationProfile>
  <ConfigValues></ConfigValues>
</GameProfile>
'@
        Set-Content -LiteralPath $existingUserProfile -Value $existingContent -Encoding utf8
        $contentBeforeRun = Get-Content -LiteralPath $existingUserProfile -Raw

        $profileIndex = Build-ProfileIndex -gameProfilesDir $gameProfilesDir
        $result = Register-Games -userProfilesDir $userProfilesDir -installFolder $installFolder `
            -profileIndex $profileIndex -gameProfilesDir $gameProfilesDir -DryRun $false

        @($result.Already) | Should -Contain 'ALIENS' -Because "a game with an existing UserProfile must be reported as Already, not silently ignored or re-registered"
        @($result.Registered | Where-Object { $_.Code -eq 'ALIENS' }) | Should -BeNullOrEmpty -Because "an already-registered game must not appear in Registered -- that would mean it was written again"
        (Get-Content -LiteralPath $existingUserProfile -Raw) | Should -Be $contentBeforeRun -Because "the user's existing customized profile (including their own GamePath) must be byte-identical after re-running registration -- overwriting it would silently discard real user customization"
    }
}

Describe "Pcsx2x6 crosshair prerequisite automation (issue #173)" -Tag 'TVD-Medium' {
    # Human behavior replaced: a tester whose pcsx2x6 install is a stock,
    # never-initialized copy (no inis\PCSX2.ini yet) walks through TPM's
    # crosshair setup and expects TPM to notice and offer to fix it, rather
    # than silently copying PNGs next to a config file that doesn't exist
    # and leaving the operator to work out why nothing changed. Also proves
    # the new detection/first-run-trigger/report functions never write to
    # the emulator-owned USB1/USB2 guncon2_cursor_path keys, extending the
    # existing Set-Pcsx2CursorPaths denial coverage to the new code paths
    # #173 adds around it.

    It "Get-Pcsx2CrosshairPrerequisiteState: classifies NotInstalled when the folder does not exist" {
        . (New-Pcsx2AutomationFixture)
        $missing = Join-Path $TestDrive ("does-not-exist-" + [guid]::NewGuid().ToString('N'))
        (Get-Pcsx2CrosshairPrerequisiteState -Pcsx2Dir $missing).State | Should -Be 'NotInstalled'
    }

    It "Get-Pcsx2CrosshairPrerequisiteState: classifies NotInstalled when pcsx2-qtx64.exe is absent" {
        . (New-Pcsx2AutomationFixture)
        $installRoot = New-Pcsx2InstallFixture
        $state = Get-Pcsx2CrosshairPrerequisiteState -Pcsx2Dir $installRoot
        $state.State | Should -Be 'NotInstalled'
        $state.Reason | Should -Match 'pcsx2-qtx64.exe'
    }

    It "Get-Pcsx2CrosshairPrerequisiteState: classifies StockUninitialized when the executable is present but PCSX2.ini is not" {
        . (New-Pcsx2AutomationFixture)
        $installRoot = New-Pcsx2InstallFixture -IncludeExecutable
        $state = Get-Pcsx2CrosshairPrerequisiteState -Pcsx2Dir $installRoot
        $state.State | Should -Be 'StockUninitialized'
        $state.DataRoot | Should -Be (Join-Path $installRoot 'TeknoParrot')
    }

    It "Get-Pcsx2CrosshairPrerequisiteState: classifies Incomplete when PCSX2.ini is initialized but crosshair PNGs are missing" {
        . (New-Pcsx2AutomationFixture)
        $installRoot = New-Pcsx2InstallFixture -IncludeExecutable -Initialized
        (Get-Pcsx2CrosshairPrerequisiteState -Pcsx2Dir $installRoot).State | Should -Be 'Incomplete'
    }

    It "Get-Pcsx2CrosshairPrerequisiteState: classifies Canonical when PCSX2.ini is initialized and both crosshair PNGs are present" {
        . (New-Pcsx2AutomationFixture)
        $installRoot = New-Pcsx2InstallFixture -IncludeExecutable -Initialized -IncludePngs
        $state = Get-Pcsx2CrosshairPrerequisiteState -Pcsx2Dir $installRoot
        $state.State | Should -Be 'Canonical'
        $state.HasP1Png | Should -Be $true
        $state.HasP2Png | Should -Be $true
    }

    It "Get-Pcsx2CrosshairPrerequisiteState: resolves DataRoot from a non-empty portable.txt instead of the TeknoParrot default" {
        . (New-Pcsx2AutomationFixture)
        $installRoot = New-Pcsx2InstallFixture -IncludeExecutable -Initialized -PortableTxtContent 'CustomRoot'
        $state = Get-Pcsx2CrosshairPrerequisiteState -Pcsx2Dir $installRoot
        $state.DataRoot | Should -Be (Join-Path $installRoot 'CustomRoot')
        $state.State | Should -Be 'Incomplete' -Because 'initialized without PNGs still classifies as Incomplete regardless of which data-root leaf resolved'
    }

    It "Get-Pcsx2CrosshairPrerequisiteState: classification alone never creates or modifies PCSX2.ini" {
        . (New-Pcsx2AutomationFixture)
        $installRoot = New-Pcsx2InstallFixture -IncludeExecutable
        Get-Pcsx2CrosshairPrerequisiteState -Pcsx2Dir $installRoot | Out-Null
        (Test-Path -LiteralPath (Join-Path $installRoot 'TeknoParrot\inis\PCSX2.ini')) | Should -Be $false -Because "detection is read-only; only an explicitly-approved first-run trigger may create PCSX2.ini"
    }

    It "Get-Pcsx2CursorPathReport: reports Available=false when PCSX2.ini does not exist" {
        $missingIni = Join-Path $TestDrive ("missing-" + [guid]::NewGuid().ToString('N') + '.ini')
        (Get-Pcsx2CursorPathReport -IniPath $missingIni).Available | Should -Be $false
    }

    It "Get-Pcsx2CursorPathReport: reads the real [USB1]/[USB2] guncon2_cursor_path values without writing anything" {
        $iniPath = Join-Path $TestDrive ("cursor-report-" + [guid]::NewGuid().ToString('N') + '.ini')
        $content = "[USB1]`r`nType = guncon2`r`nguncon2_cursor_path = C:\Old\P1.png`r`n[USB2]`r`nType = guncon2`r`nguncon2_cursor_path = C:\Old\P2.png`r`n"
        [IO.File]::WriteAllText($iniPath, $content)
        $before = Get-Content -LiteralPath $iniPath -Raw
        $report = Get-Pcsx2CursorPathReport -IniPath $iniPath
        $report.Available | Should -Be $true
        $report.USB1CursorPath | Should -Be 'C:\Old\P1.png'
        $report.USB2CursorPath | Should -Be 'C:\Old\P2.png'
        (Get-Content -LiteralPath $iniPath -Raw) | Should -Be $before -Because "this is a read-only report -- it must never modify the ini"
    }

    It "Get-Pcsx2CursorPathReport: reports null values when the guncon2_cursor_path key is absent" {
        $iniPath = Join-Path $TestDrive ("cursor-report-empty-" + [guid]::NewGuid().ToString('N') + '.ini')
        [IO.File]::WriteAllText($iniPath, "[USB1]`r`nType = None`r`n[USB2]`r`nType = None`r`n")
        $report = Get-Pcsx2CursorPathReport -IniPath $iniPath
        $report.Available | Should -Be $true
        $report.USB1CursorPath | Should -BeNullOrEmpty
        $report.USB2CursorPath | Should -BeNullOrEmpty
    }

    It "Test-Pcsx2ProcessRunning: returns false when no matching process is running" {
        Test-Pcsx2ProcessRunning | Should -Be $false
    }

    It "Test-Pcsx2ProcessRunning: returns true when a process named pcsx2-qtx64 is running" {
        $exeDir = Join-Path $TestDrive ("fake-pcsx2-proc-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $exeDir -Force | Out-Null
        $fakeExe = Join-Path $exeDir 'pcsx2-qtx64.exe'
        Copy-Item -LiteralPath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -Destination $fakeExe -Force
        $proc = Start-Process -FilePath $fakeExe -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 20') -PassThru
        try {
            Start-Sleep -Milliseconds 500
            Test-Pcsx2ProcessRunning | Should -Be $true
        } finally {
            try { $proc.Kill() } catch { }
            try { $proc.WaitForExit(5000) } catch { }
        }
    }

    It "Invoke-Pcsx2FirstRunSetup: refuses when the state is not StockUninitialized" {
        . (New-Pcsx2AutomationFixture)
        $state = [pscustomobject]@{ State = 'Canonical'; Pcsx2Dir = $TestDrive; DataRoot = $TestDrive; IniPath = $null; EnvironmentCapability = $null }
        $result = Invoke-Pcsx2FirstRunSetup -State $state
        $result.Success | Should -Be $false
        $result.Reason | Should -Match 'StockUninitialized'
    }

    It "Invoke-Pcsx2FirstRunSetup: triggers the InitializationAction and succeeds when re-verification passes" {
        . (New-Pcsx2AutomationFixture)
        $pcsx2Dir = Join-Path $TestDrive ("firstrun-success-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $pcsx2Dir -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $pcsx2Dir 'fake-init.cmd'), "@echo off`r`nmkdir inis 2>nul`r`necho [USB1]>inis\Fixture.ini`r`nexit /b 0`r`n")
        $envCap = [pscustomobject]@{
            InitializationAction = [ordered]@{ Method = 'CliInvocation'; Command = 'fake-init.cmd'; Arguments = @(); ExpectedExitCodes = @(0); TimeoutSeconds = 15 }
            InitializedVerifier  = [ordered]@{ RequiredPaths = @('inis/Fixture.ini'); RequiredMarkers = @('[USB1]'); ParseMethod = 'IniSections' }
        }
        $state = [pscustomobject]@{ State = 'StockUninitialized'; Pcsx2Dir = $pcsx2Dir; DataRoot = $pcsx2Dir; IniPath = (Join-Path $pcsx2Dir 'inis\Fixture.ini'); EnvironmentCapability = $envCap }
        (Invoke-Pcsx2FirstRunSetup -State $state).Success | Should -Be $true
    }

    It "Invoke-Pcsx2FirstRunSetup: reports failure when re-verification still fails after the action runs" {
        . (New-Pcsx2AutomationFixture)
        $pcsx2Dir = Join-Path $TestDrive ("firstrun-fail-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $pcsx2Dir -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $pcsx2Dir 'noop-init.cmd'), "@echo off`r`nexit /b 0`r`n")
        $envCap = [pscustomobject]@{
            InitializationAction = [ordered]@{ Method = 'CliInvocation'; Command = 'noop-init.cmd'; Arguments = @(); ExpectedExitCodes = @(0); TimeoutSeconds = 15 }
            InitializedVerifier  = [ordered]@{ RequiredPaths = @('inis/Fixture.ini'); RequiredMarkers = @('[USB1]'); ParseMethod = 'IniSections' }
        }
        $state = [pscustomobject]@{ State = 'StockUninitialized'; Pcsx2Dir = $pcsx2Dir; DataRoot = $pcsx2Dir; IniPath = (Join-Path $pcsx2Dir 'inis\Fixture.ini'); EnvironmentCapability = $envCap }
        $result = Invoke-Pcsx2FirstRunSetup -State $state
        $result.Success | Should -Be $false
        $result.Reason | Should -Match 'still not initialized'
    }

    It "the full detect -> first-run -> report sequence never writes USB1/USB2 guncon2_cursor_path (ECVF never-write guarantee, extended to the new #173 code paths)" {
        . (New-Pcsx2AutomationFixture)
        $installRoot = New-Pcsx2InstallFixture -IncludeExecutable
        $before = Get-Pcsx2CrosshairPrerequisiteState -Pcsx2Dir $installRoot
        $before.State | Should -Be 'StockUninitialized'

        $pcsx2Dir = $installRoot
        [IO.File]::WriteAllText((Join-Path $pcsx2Dir 'fake-init.cmd'), "@echo off`r`nmkdir TeknoParrot\inis 2>nul`r`necho [USB1]>TeknoParrot\inis\PCSX2.ini`r`necho [USB2]>>TeknoParrot\inis\PCSX2.ini`r`necho [JVS]>>TeknoParrot\inis\PCSX2.ini`r`nexit /b 0`r`n")
        $before.EnvironmentCapability.InitializationAction = [ordered]@{ Method = 'CliInvocation'; Command = 'fake-init.cmd'; Arguments = @(); ExpectedExitCodes = @(0); TimeoutSeconds = 15 }
        $firstRun = Invoke-Pcsx2FirstRunSetup -State $before
        $firstRun.Success | Should -Be $true

        $after = Get-Pcsx2CrosshairPrerequisiteState -Pcsx2Dir $installRoot
        $after.State | Should -Be 'Incomplete' -Because 'PCSX2.ini is now initialized but the crosshair PNGs were never placed by this test'

        $report = Get-Pcsx2CursorPathReport -IniPath $after.IniPath
        $report.Available | Should -Be $true
        $report.USB1CursorPath | Should -BeNullOrEmpty
        $report.USB2CursorPath | Should -BeNullOrEmpty -Because "nothing in this sequence ever writes USB1/USB2 guncon2_cursor_path -- only the emulator's own -testconfig mechanism and a strictly read-only report ran"
    }

    It "Invoke-CrosshairSetup: Unknown ECVF state performs zero crosshair PNG writes" {
        $fixture = New-Pcsx2CrosshairSetupFixture
        . $fixture.FixturePath
        Mock Read-HostSafe { '0' }
        Mock Start-Process {}
        Mock Export-CrosshairPreview {}
        Mock Get-Pcsx2CrosshairPrerequisiteState {
            [pscustomobject]@{
                State = 'Unknown'
                Pcsx2Dir = $fixture.Pcsx2Root
                DataRoot = $null
                IniPath = $null
                Reason = 'synthetic unknown ECVF state'
            }
        }

        Invoke-CrosshairSetup -UserProfilesDir $fixture.ProfilesRoot -GamesInstallFolder $fixture.Root -TpRoot $fixture.Root | Out-Null

        $destination = Join-Path $fixture.Pcsx2Root 'TeknoParrot\crosshairs'
        (Test-Path -LiteralPath (Join-Path $destination 'P1.png')) | Should -Be $false
        (Test-Path -LiteralPath (Join-Path $destination 'P2.png')) | Should -Be $false
        @(Get-ChildItem -LiteralPath $fixture.Pcsx2Root -Recurse -Filter '*.png' -File -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It "Invoke-CrosshairSetup: unavailable ECVF contract performs zero crosshair PNG writes" {
        $fixture = New-Pcsx2CrosshairSetupFixture
        . $fixture.FixturePath
        $state = Get-Pcsx2CrosshairPrerequisiteState -Pcsx2Dir $fixture.Pcsx2Root
        $state.State | Should -Be 'Unknown'
        $state.Reason | Should -Match 'framework was not available'
        Mock Read-HostSafe { '0' }
        Mock Start-Process {}
        Mock Export-CrosshairPreview {}

        Invoke-CrosshairSetup -UserProfilesDir $fixture.ProfilesRoot -GamesInstallFolder $fixture.Root -TpRoot $fixture.Root | Out-Null

        $destination = Join-Path $fixture.Pcsx2Root 'TeknoParrot\crosshairs'
        (Test-Path -LiteralPath (Join-Path $destination 'P1.png')) | Should -Be $false
        (Test-Path -LiteralPath (Join-Path $destination 'P2.png')) | Should -Be $false
        @(Get-ChildItem -LiteralPath $fixture.Pcsx2Root -Recurse -Filter '*.png' -File -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It "Invoke-CrosshairSetup: uses the contract-resolved non-default DataRoot for PNG placement" {
        $fixture = New-Pcsx2CrosshairSetupFixture
        $customRoot = Join-Path $fixture.Pcsx2Root 'PortableData'
        New-Item -ItemType Directory -Path $customRoot -Force | Out-Null
        . $fixture.FixturePath
        Mock Read-HostSafe {
            if ($Prompt -match 'Apply these crosshairs') { 'Y' } else { '0' }
        }
        Mock Export-CrosshairPreview {}
        Mock Get-Pcsx2CrosshairPrerequisiteState {
            [pscustomobject]@{
                State = 'Incomplete'
                Pcsx2Dir = $fixture.Pcsx2Root
                DataRoot = $customRoot
                IniPath = $null
                Reason = 'synthetic portable DataRoot'
            }
        }

        Invoke-CrosshairSetup -UserProfilesDir $fixture.ProfilesRoot -GamesInstallFolder $fixture.Root -TpRoot $fixture.Root | Out-Null

        (Test-Path -LiteralPath (Join-Path $customRoot 'crosshairs\P1.png')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $customRoot 'crosshairs\P2.png')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $fixture.Pcsx2Root 'TeknoParrot\crosshairs\P1.png')) | Should -Be $false
        (Test-Path -LiteralPath (Join-Path $fixture.Pcsx2Root 'TeknoParrot\crosshairs\P2.png')) | Should -Be $false
    }
}
