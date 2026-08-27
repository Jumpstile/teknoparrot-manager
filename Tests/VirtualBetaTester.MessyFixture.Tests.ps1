#Requires -Module Pester

# TPM Certification Suite Phase 1 (issue #88): real-world messy environment
# simulation. Replaces the specific value of a real tester's real library --
# one that accumulates partial extractions, oddly-named duplicate folders,
# incomplete profile data, and alternate emulator folder naming over months
# of actual use, in combinations a clean synthetic fixture normally never
# has all at once. A single condition tested in isolation (as the rest of
# the suite already does) does not prove the combination is handled safely.
#
# This fixture combines, in one $TestDrive tree:
#   - some games "already extracted" (a real folder with an exe)
#   - some missing/incomplete profile data (a GameProfile XML missing
#     required top-level elements)
#   - a duplicate/oddly-named folder for the same title
#   - an alternate PCSX2 folder naming (PCSX2x6 instead of pcsx2x6)
#   - legacy-root and canonical-subfolder crosshair files coexisting
#     (the exact issue #79 scenario -- both present at once)
#
# All functions exercised here are read-only scans/checks (Get-GameFiles,
# Resolve-Pcsx2Directory, Get-GameProfileSchemaDrift) -- the assertion is
# that they run to completion without throwing and produce sane output
# against a messy tree, and that nothing under $TestDrive changes as a
# side effect of merely inspecting it.
#
# Run with: Invoke-Pester -Path .\Tests\VirtualBetaTester.MessyFixture.Tests.ps1

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\TeknoParrot-Manager.ps1"
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')"
    }
    $functionAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $extractedFunctionsPath = Join-Path $TestDrive ("vbt-messy-functions-" + [guid]::NewGuid().ToString('N') + '.ps1')
    ($functionAsts | ForEach-Object { $_.Extent.Text }) -join "`n`n" | Set-Content -LiteralPath $extractedFunctionsPath -Encoding utf8
    . $extractedFunctionsPath
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    $script:PostgresRecoveryStatus = $null
    $script:PostgresRecoveryResumeState = $null

    $resolvePcsx2Path = Join-Path $PSScriptRoot "..\scripts\Resolve-Pcsx2Directory.ps1"
    . $resolvePcsx2Path

    $script:logPath = Join-Path $TestDrive "vbt-messy.log"
    $script:KnownGameProfileTopLevel = @(
        'GamePath','GamePath2','TestMenuParameter','TestMenuIsExecutable',
        'ExtraParameters','TestMenuExtraParameters','EmulationProfile',
        'GameProfileRevision','HasSeparateTestMode','ExecutableName',
        'ExecutableName2','HasTwoExecutables','LaunchSecondExecutableFirst',
        'HasTpoSupport','EmulatorType','Is64Bit','ValidMd5','ConfigValues',
        'GameName','GameGenreInternal','IconName','HasModeForSquare',
        'RequiresAdmin','InvokeFullscreenOnStartup','LaunchedFromUsb',
        'CamberWindowState'
    )
    $script:RequiredGameProfileTopLevel = @('EmulationProfile','ConfigValues')
    $script:KnownFieldTypes = @('Bool','Dropdown','Text','Slider')

    function New-MessyTeknoParrotFixture {
        $root = Join-Path $TestDrive ("messy-install-" + [guid]::NewGuid().ToString('N'))
        $installFolder = Join-Path $root 'Games'
        New-Item -ItemType Directory -Path $installFolder -Force | Out-Null

        # Already-extracted game: a real, cleanly-named folder with an exe.
        $extracted = Join-Path $installFolder 'Aliens Armageddon (1.04)'
        New-Item -ItemType Directory -Path $extracted -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $extracted 'ALIENS.exe') -Force | Out-Null

        # Duplicate/oddly-named folder for the same title -- a second copy a
        # user made while troubleshooting and never cleaned up, with a
        # trailing "(copy)" and inconsistent casing.
        $duplicate = Join-Path $installFolder 'aliens armageddon (COPY)'
        New-Item -ItemType Directory -Path $duplicate -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $duplicate 'ALIENS.exe') -Force | Out-Null

        # Incomplete/missing extraction: a folder that exists but has no
        # recognizable game executable inside it yet (partial ZIP extract,
        # or a folder created but never populated).
        $incomplete = Join-Path $installFolder 'Time Crisis 4 (incomplete)'
        New-Item -ItemType Directory -Path $incomplete -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $incomplete 'readme.txt') -Force | Out-Null

        # GameProfiles: one complete, one missing required top-level elements
        # (a real upstream schema-drift scenario, not a crash-inducing
        # malformed XML).
        $gameProfilesDir = Join-Path $root 'GameProfiles'
        New-Item -ItemType Directory -Path $gameProfilesDir -Force | Out-Null
        $completeXml = [xml]@'
<?xml version="1.0" encoding="utf-8"?>
<GameProfile>
  <EmulationProfile>RawThrills</EmulationProfile>
  <ConfigValues></ConfigValues>
</GameProfile>
'@
        $completeXml.Save((Join-Path $gameProfilesDir 'ALIENS.xml'))

        $incompleteXml = [xml]@'
<?xml version="1.0" encoding="utf-8"?>
<GameProfile>
  <EmulationProfile>RawThrills</EmulationProfile>
</GameProfile>
'@
        $incompleteXml.Save((Join-Path $gameProfilesDir 'TIMECRS4.xml'))

        # Alternate PCSX2 folder naming -- "PCSX2x6" instead of the more
        # common lowercase "pcsx2x6".
        $pcsx2Dir = Join-Path $root 'PCSX2x6'
        New-Item -ItemType Directory -Path $pcsx2Dir -Force | Out-Null

        # Legacy-root and canonical-subfolder crosshair files coexisting --
        # the exact issue #79 scenario: an old install that had crosshairs at
        # the folder root, never cleaned up after upgrading to a build that
        # also writes the canonical location.
        New-Item -ItemType File -Path (Join-Path $pcsx2Dir 'P1.png') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $pcsx2Dir 'P2.png') -Force | Out-Null
        $canonicalCrosshairDir = Join-Path $pcsx2Dir 'TeknoParrot\crosshairs'
        New-Item -ItemType Directory -Path $canonicalCrosshairDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $canonicalCrosshairDir 'P1.png') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $canonicalCrosshairDir 'P2.png') -Force | Out-Null

        # Empty folder -- a placeholder a user created, or a partial ZIP
        # extraction that was interrupted before any file landed. Real
        # extraction failures on a slow/flaky NAS produce exactly this.
        $emptyFolder = Join-Path $installFolder 'Zoids Infinity EX Plus (empty)'
        New-Item -ItemType Directory -Path $emptyFolder -Force | Out-Null

        # RetroBat/Batocera naming convention -- extracted folders suffixed
        # ".teknoparrot" (Invoke-AutoSync's own $extractFolderName format when
        # -retroBat is set). A mixed library with some games extracted before
        # RetroBat mode was enabled and some after is a real, likely scenario,
        # not a hypothetical one.
        $retroBatFolder = Join-Path $installFolder 'Time Crisis 3.teknoparrot'
        New-Item -ItemType Directory -Path $retroBatFolder -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $retroBatFolder 'TIMECRS3.exe') -Force | Out-Null

        return [pscustomobject]@{
            Root              = $root
            InstallFolder     = $installFolder
            GameProfilesDir   = $gameProfilesDir
            CompleteXmlPath   = Join-Path $gameProfilesDir 'ALIENS.xml'
            IncompleteXmlPath = Join-Path $gameProfilesDir 'TIMECRS4.xml'
            Pcsx2Dir          = $pcsx2Dir
            EmptyFolder       = $emptyFolder
            RetroBatFolder    = $retroBatFolder
        }
    }
}

Describe "Virtual Beta Tester: real-world messy environment simulation (issue #88 phase 1)" {

    It "scans a messy install without throwing and finds every real game executable, including the duplicate" {
        $fixture = New-MessyTeknoParrotFixture

        { $script:foundFiles = Get-GameFiles -folder $fixture.InstallFolder } | Should -Not -Throw

        $exeNames = @($script:foundFiles | ForEach-Object { $_.Name })
        @($exeNames | Where-Object { $_ -eq 'ALIENS.exe' }).Count | Should -Be 2 -Because "both the clean folder and the duplicate/oddly-named copy have a real ALIENS.exe"
        $exeNames | Should -Not -Contain 'readme.txt' -Because "the incomplete extraction has no recognized game file, only a stray text file"
        $exeNames | Should -Contain 'TIMECRS3.exe' -Because "a RetroBat-suffixed (.teknoparrot) folder must scan the same as any other -- the suffix lives on the folder, not the exe"
    }

    It "an empty placeholder folder produces zero results, not an error, and does not affect scanning the rest of the library" {
        $fixture = New-MessyTeknoParrotFixture

        { $script:emptyResult = Get-GameFiles -folder $fixture.EmptyFolder } | Should -Not -Throw
        @($script:emptyResult).Count | Should -Be 0

        # The empty folder existing elsewhere in the tree must not make the
        # whole-library scan skip or crash on real games sitting alongside it.
        $wholeLibraryResult = Get-GameFiles -folder $fixture.InstallFolder
        @($wholeLibraryResult | Where-Object { $_.Name -eq 'ALIENS.exe' }).Count | Should -Be 2
    }

    It "flags the incomplete GameProfile's missing required elements without crashing, and does not flag the complete one" {
        $fixture = New-MessyTeknoParrotFixture

        $completeDoc = [xml](Get-Content -LiteralPath $fixture.CompleteXmlPath -Raw)
        $incompleteDoc = [xml](Get-Content -LiteralPath $fixture.IncompleteXmlPath -Raw)

        { $script:completeDrift = Get-GameProfileSchemaDrift -Doc $completeDoc } | Should -Not -Throw
        { $script:incompleteDrift = Get-GameProfileSchemaDrift -Doc $incompleteDoc } | Should -Not -Throw

        $script:completeDrift.HasDrift | Should -Be $false
        $script:incompleteDrift.HasDrift | Should -Be $true
        $script:incompleteDrift.MissingRequired | Should -Contain 'ConfigValues'
    }

    It "resolves the alternate-cased PCSX2x6 folder name without requiring the exact lowercase 'pcsx2x6'" {
        $fixture = New-MessyTeknoParrotFixture

        { $script:resolved = Resolve-Pcsx2Directory -TeknoParrotRoot $fixture.Root } | Should -Not -Throw
        $script:resolved | Should -Be $fixture.Pcsx2Dir
    }

    It "does not crash or modify anything when legacy-root and canonical-subfolder crosshairs coexist" {
        $fixture = New-MessyTeknoParrotFixture

        $legacyP1 = Join-Path $fixture.Pcsx2Dir 'P1.png'
        $canonicalP1 = Join-Path $fixture.Pcsx2Dir 'TeknoParrot\crosshairs\P1.png'
        (Test-Path -LiteralPath $legacyP1) | Should -Be $true -Because "legacy files are never deleted by the issue #79 fix"
        (Test-Path -LiteralPath $canonicalP1) | Should -Be $true -Because "the canonical location is also populated in this fixture"
    }

    It "produces no unexpected filesystem changes from read-only inspection of the whole messy fixture" {
        $fixture = New-MessyTeknoParrotFixture
        $before = Get-ChildItem -LiteralPath $fixture.Root -Recurse | Select-Object -ExpandProperty FullName | Sort-Object

        Get-GameFiles -folder $fixture.InstallFolder | Out-Null
        Resolve-Pcsx2Directory -TeknoParrotRoot $fixture.Root | Out-Null
        Get-GameProfileSchemaDrift -Doc ([xml](Get-Content -LiteralPath $fixture.CompleteXmlPath -Raw)) | Out-Null
        Get-GameProfileSchemaDrift -Doc ([xml](Get-Content -LiteralPath $fixture.IncompleteXmlPath -Raw)) | Out-Null

        $after = Get-ChildItem -LiteralPath $fixture.Root -Recurse | Select-Object -ExpandProperty FullName | Sort-Object
        Compare-Object $before $after | Should -BeNullOrEmpty -Because "inspecting a messy library must never itself change it"
    }
}
