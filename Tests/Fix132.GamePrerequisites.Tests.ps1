#Requires -Module Pester

# FIX132: a game must not fail because a file it needs is missing and nobody said so.
#   Before the fix the only startup-file check named two PCSX2x6 firmware files that the game does not ask for (27v1602T.d and
#   27v1602F.bg), so a PC with neither real file (r27v1602f.7d, r27v1602f.8g) showed Bloody Roar 3 as ready and the game then stopped
#   with "PCSX2x6 Firmware is not installed". The table now names the real files, covers the Chihiro (cxbxr) files, and the missing
#   files are reported per game with one next step and (after a question) copied from the player's own "[EMU]" archive after every
#   file was checked against the Eggman DAT (size and every listed hash).
# Everything here is synthetic: tiny made-up files, made-up DAT text, made-up archives, all under TestDrive. The product script is parsed
# and only its function definitions are dot-sourced; no top-level product code runs, nothing is downloaded, and no TeknoParrot,
# LaunchBox, registry or user-profile data is read or written. Each It names the product mutation that makes it fail.
# What this CANNOT prove: that the real [EMU] archives and the real DAT have exactly this shape (their layout was not read), how a real
# console paints the screens, or that the emulators accept the files.

BeforeAll {
    $script:F132ProductionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $script:F132ProductionSource = [System.IO.File]::ReadAllText($script:F132ProductionPath)
    $tokens = $null
    $parseErrors = $null
    $script:F132Ast = [System.Management.Automation.Language.Parser]::ParseInput($script:F132ProductionSource, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX132 tests could not parse the production script.' }
    $functionText = @($script:F132Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:F132FunctionFile = Join-Path $TestDrive 'tpm-fix132-functions.ps1'
    [System.IO.File]::WriteAllText($script:F132FunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:F132FunctionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][System.IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force

    # The production table itself (not a copy typed here): the right-hand side of its one top-level assignment.
    $assignment = @($script:F132Ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -eq '$EmulatorBiosRequirements' })
    if ($assignment.Count -ne 1) { throw 'FIX132 tests expected exactly one production assignment of $EmulatorBiosRequirements.' }
    $script:F132ProductionTable = & ([scriptblock]::Create($assignment[0].Right.Extent.Text))
    $script:EmulatorBiosRequirements = $script:F132ProductionTable
    $script:RawThrillsPathLimits = @{}
    $script:FileVersionPins = @{}
    $script:GpuIncompatibleGames = @{}
    $script:ScriptVersion = 'test'
    $script:tpRoot = $null
    $script:logLines = New-Object System.Collections.Generic.List[string]

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $script:F132Bytes7d = [System.Text.Encoding]::ASCII.GetBytes('synthetic startup file number one (7d)')
    $script:F132Bytes8g = [System.Text.Encoding]::ASCII.GetBytes('synthetic startup file number two (8g), a little longer')
    $script:F132ZipName = '[EMU] PCSX2x6 Emulator BIOS Files [TP]'

    function Install-F132Mocks {
        Mock Write-Log { [void]$script:logLines.Add([string]$msg) }
        Mock Write-Host { }
        $script:screen = New-Object System.Collections.Generic.List[string]
        Mock Write-TpmText { [void]$script:screen.Add([string]$Text) }
    }

    function Get-F132Hashes {
        param([byte[]]$Bytes)
        $temp = Join-Path $TestDrive ('hash-' + [guid]::NewGuid().ToString('N') + '.bin')
        [System.IO.File]::WriteAllBytes($temp, $Bytes)
        try {
            return [pscustomobject]@{
                Size = $Bytes.Length
                Crc = (Get-Crc32 -Path $temp).ToLowerInvariant()
                Md5 = (Get-FileHash -LiteralPath $temp -Algorithm MD5).Hash.ToLowerInvariant()
                Sha1 = (Get-FileHash -LiteralPath $temp -Algorithm SHA1).Hash.ToLowerInvariant()
                Sha256 = (Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        } finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }

    # Made-up Logiqx DAT text. Each rom: @{ Name; Bytes; Skip = @('md5') ; Tamper = $true } ; Tamper lists a wrong sha1.
    function New-F132DatText {
        param([Parameter(Mandatory)][hashtable[]]$Games)
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('<?xml version="1.0"?>')
        [void]$sb.AppendLine('<datafile>')
        foreach ($game in $Games) {
            [void]$sb.AppendLine(('  <game name="{0}">' -f $game.Name))
            if ($game.ContainsKey('Profile')) { [void]$sb.AppendLine(('    <GameProfile>{0}</GameProfile><Executable>game.exe</Executable>' -f $game.Profile)) }
            foreach ($rom in @($game.Roms)) {
                $h = Get-F132Hashes -Bytes $rom.Bytes
                $skip = if ($rom.ContainsKey('Skip')) { @($rom.Skip) } else { @() }
                $attrs = ('name="{0}" size="{1}"' -f $rom.Name, $h.Size)
                if ($skip -notcontains 'crc') { $attrs += (' crc="{0}"' -f $h.Crc) }
                if ($skip -notcontains 'md5') { $attrs += (' md5="{0}"' -f $h.Md5) }
                if ($skip -notcontains 'sha1') { $attrs += (' sha1="{0}"' -f $(if ($rom.ContainsKey('Tamper')) { '0' * 40 } else { $h.Sha1 })) }
                if ($skip -notcontains 'size') { } else { $attrs = $attrs -replace ' size="\d+"', '' }
                [void]$sb.AppendLine(('    <rom {0} />' -f $attrs))
            }
            [void]$sb.AppendLine('  </game>')
        }
        [void]$sb.AppendLine('</datafile>')
        return $sb.ToString()
    }

    function New-F132Zip {
        param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][System.Collections.Specialized.OrderedDictionary]$Entries)
        $fs = [System.IO.File]::Create($Path)
        $za = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($key in $Entries.Keys) {
                $entry = $za.CreateEntry([string]$key)
                $stream = $entry.Open()
                try { $bytes = [byte[]]$Entries[$key]; $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
            }
        } finally { $za.Dispose(); $fs.Dispose() }
    }

    # A TeknoParrot root with a Pcsx2x6 game profile; the emulator folder exists unless -NoEmulator.
    function New-F132Root {
        param([string]$Name = 'tp', [switch]$NoEmulator, [string]$EmulatorType = 'Pcsx2x6', [string[]]$Games = @('BLOODYROAR3'))
        $root = Join-Path $TestDrive ('f132-' + $Name + '-' + [guid]::NewGuid().ToString('N'))
        $profiles = Join-Path $root 'UserProfiles'
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null
        foreach ($game in $Games) {
            [System.IO.File]::WriteAllText((Join-Path $profiles ($game + '.xml')), ('<?xml version="1.0" encoding="utf-8"?><GameProfile><EmulatorType>{0}</EmulatorType><GamePath>C:\Games\game.exe</GamePath></GameProfile>' -f $EmulatorType))
        }
        if (-not $NoEmulator) {
            $folder = if ($EmulatorType -ieq 'cxbxr') { 'cxbxr' } else { 'pcsx2x6' }
            New-Item -ItemType Directory -Path (Join-Path $root $folder) -Force | Out-Null
        }
        return [pscustomobject]@{ Root = $root; Profiles = $profiles; Pcsx2 = (Join-Path $root 'pcsx2x6'); Bios = (Join-Path $root 'pcsx2x6\TeknoParrot\bios') }
    }

    function Get-F132Warning {
        param([Parameter(Mandatory)]$Fixture)
        $result = Get-CompatibilityWarnings -UserProfilesDir $Fixture.Profiles -TeknoParrotRoot $Fixture.Root
        return @($result.BiosMissing)
    }

    # Collection folder with the [EMU] archive and a loose DAT file that describes it (or not).
    function New-F132Collection {
        param([switch]$WithBytes8g, [hashtable]$ZipEntries = $null, [switch]$NoDat, [switch]$TamperDat, [string[]]$SkipHash = @())
        $folder = Join-Path $TestDrive ('f132-coll-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $entries = [ordered]@{ 'PCSX2x6/TeknoParrot/bios/r27v1602f.7d' = $script:F132Bytes7d; 'PCSX2x6/TeknoParrot/bios/r27v1602f.8g' = $script:F132Bytes8g; 'readme.txt' = [System.Text.Encoding]::ASCII.GetBytes('hello') }
        if ($null -ne $ZipEntries) { $entries = [ordered]@{}; foreach ($k in $ZipEntries.Keys) { $entries[$k] = $ZipEntries[$k] } }
        New-F132Zip -Path (Join-Path $folder ($script:F132ZipName + '.zip')) -Entries $entries
        $datPath = ''
        if (-not $NoDat) {
            $rom7d = @{ Name = 'r27v1602f.7d'; Bytes = $script:F132Bytes7d; Skip = $SkipHash }
            $rom8g = @{ Name = 'r27v1602f.8g'; Bytes = $script:F132Bytes8g; Skip = $SkipHash }
            if ($TamperDat) { $rom8g['Tamper'] = $true }
            $datPath = Join-Path $folder 'Supplementary.dat'
            [System.IO.File]::WriteAllText($datPath, (New-F132DatText -Games @(@{ Name = $script:F132ZipName; Roms = @($rom7d, $rom8g) }, @{ Name = 'Some Real Game (World)'; Profile = 'RealGame'; Roms = @(@{ Name = 'game.bin'; Bytes = $script:F132Bytes7d }) })), (New-Object System.Text.UTF8Encoding $false))
        }
        return [pscustomobject]@{ Folder = $folder; Dat = $datPath; Zip = (Join-Path $folder ($script:F132ZipName + '.zip')) }
    }

    function Get-F132Plan {
        param($Fixture, $Collection, $OtherRoots = $null)
        $warning = @(Get-F132Warning -Fixture $Fixture)
        $dat = Get-TpmEmuDatRomSets -SupplementaryDatPath $(if ($Collection) { $Collection.Dat } else { '' })
        $provider = if ($null -ne $OtherRoots) { [scriptblock]::Create('@(' + (($OtherRoots | ForEach-Object { "'" + $_ + "'" }) -join ',') + ')') } else { $null }
        return Get-TpmPrerequisiteFixPlan -Warning $warning[0] -SearchFolders $(if ($Collection) { @($Collection.Folder) } else { @() }) -DatRoms $dat -TeknoParrotRoot $Fixture.Root -OtherRootsProvider $provider
    }
}


Describe 'FIX132 the prerequisite table' {
    BeforeEach { Install-F132Mocks }

    It 'names the files the PCSX2x6 game asks for, in the folder the game names' {
        # Mutation: put the old names (27v1602T.d, 27v1602F.bg) back, or point RelativeDir somewhere else -> this fails.
        $entry = $script:F132ProductionTable['Pcsx2x6']
        $specs = @(Get-TpmPrerequisiteFileSpecs -Requirement $entry)
        @($specs.Name | Sort-Object) | Should -Be @('r27v1602f.7d', 'r27v1602f.8g')
        @($specs.RelativeDir | Select-Object -Unique) | Should -Be @('TeknoParrot\bios')
        ($script:F132ProductionTable.Keys | ForEach-Object { @(Get-TpmPrerequisiteFileSpecs -Requirement $script:F132ProductionTable[$_]).Name }) -join ' ' | Should -Not -Match '27v1602T|27v1602F\.bg'
    }

    It 'lists the four Chihiro (cxbxr) files the shared launch code checks, with the folder each one sits in' {
        # Mutation: drop one file from the cxbxr entry, or change its folder -> this fails (the module text is the independent evidence).
        $specs = @(Get-TpmPrerequisiteFileSpecs -Requirement $script:F132ProductionTable['cxbxr'])
        $specs.Count | Should -Be 4
        $evidence = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\scripts\TPMGameSupport.Contracts.psm1'))
        foreach ($spec in $specs) {
            $expected = 'cxbxr/' + ($spec.RelativeDir -replace '\\', '/') + '/' + $spec.Name
            $evidence.Contains($expected) | Should -BeTrue -Because $expected
        }
    }

    It 'is complete and well formed: every entry has a plain label, safe relative folders, plain file names and an archive pattern that matches its archive' {
        # Mutation: add a startup-file entry without a Label, with an absolute folder, a path in a file name, or a broken pattern -> this fails. (Entries that only name an emulator folder are checked in Fix387.GameTypes.Tests.ps1.)
        $archiveNames = @{ Pcsx2x6 = '[EMU] PCSX2x6 Emulator BIOS Files [TP]'; cxbxr = '[EMU] CxbxR BIOS Firmware for Sega Chihiro [TP]'; RPCS3 = '[EMU] Sony PlayStation 3 Firmware [TP]'; Play = '[EMU] Play! working arcadedefs for Namco System 246 [TP]' }
        foreach ($type in @($script:F132ProductionTable.Keys | Where-Object { Test-TpmPrerequisiteNeedsFiles -Requirement $script:F132ProductionTable[$_] })) {
            $entry = $script:F132ProductionTable[$type]
            [string]$entry['Label'] | Should -Not -BeNullOrEmpty -Because $type
            $specs = @(Get-TpmPrerequisiteFileSpecs -Requirement $entry)
            # A FilesFromProfile entry (Play!) has no fixed files: its games name them in their profiles.
            if (-not $entry.Contains('FilesFromProfile')) { $specs.Count | Should -BeGreaterThan 0 -Because $type }
            foreach ($spec in $specs) {
                $spec.Name | Should -Match '^[A-Za-z0-9_.\-]+$' -Because "$type file name"
                $spec.RelativeDir | Should -Not -Match '(^[\\/])|(:)|(\.\.)' -Because "$type folder"
            }
            { [regex]::new([string]$entry['SourceZipPattern']) } | Should -Not -Throw
            $archiveNames.ContainsKey($type) | Should -BeTrue -Because "an example archive name is known for $type"
            $archiveNames[$type] -match [string]$entry['SourceZipPattern'] | Should -BeTrue -Because $type
        }
    }
}

Describe 'FIX132 the check finds missing startup files before the game does' {
    BeforeEach { Install-F132Mocks }

    It 'reports both PCSX2x6 files for a game when neither is there, with one finding per emulator and the game named' {
        # Mutation: use the old file names in the table, or skip the table in Get-CompatibilityWarnings -> nothing (or the wrong names) is reported.
        $fixture = New-F132Root -Games @('BLOODYROAR3', 'TIMECRISIS3')
        $warnings = @(Get-F132Warning -Fixture $fixture)
        $warnings.Count | Should -Be 1
        @($warnings[0].MissingFiles | Sort-Object) | Should -Be @('r27v1602f.7d', 'r27v1602f.8g')
        @($warnings[0].AffectedGames) | Should -Be @('BLOODYROAR3', 'TIMECRISIS3')
        $warnings[0].ExpectedDir | Should -Be (Join-Path $fixture.Pcsx2 'TeknoParrot\bios')
        $warnings[0].Label | Should -Be 'PCSX2x6 firmware'
    }

    It 'treats EACH required file as a gate: one present and one missing is still not ready, both present is ready' -ForEach @(
        @{ Present = 'r27v1602f.7d'; Missing = 'r27v1602f.8g' }
        @{ Present = 'r27v1602f.8g'; Missing = 'r27v1602f.7d' }
    ) {
        # Mutation: only test one of the files (or any-of instead of all-of) -> one of these two cases passes wrongly.
        $fixture = New-F132Root
        New-Item -ItemType Directory -Path $fixture.Bios -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $fixture.Bios $Present) -Force | Out-Null
        $warnings = @(Get-F132Warning -Fixture $fixture)
        $warnings.Count | Should -Be 1
        @($warnings[0].MissingFiles) | Should -Be @($Missing)
        New-Item -ItemType File -Path (Join-Path $fixture.Bios $Missing) -Force | Out-Null
        @(Get-F132Warning -Fixture $fixture).Count | Should -Be 0
    }

    It 'does not call a game blocked when its emulator is not installed yet, or when no TeknoParrot root was given' {
        # Mutation: report a missing file when the emulator folder does not exist -> a game TeknoParrot has not set up yet is flagged.
        $fixture = New-F132Root -NoEmulator
        @(Get-F132Warning -Fixture $fixture).Count | Should -Be 0
        @((Get-CompatibilityWarnings -UserProfilesDir $fixture.Profiles).BiosMissing).Count | Should -Be 0
    }

    It 'finds the Chihiro (cxbxr) files in their two different folders' {
        # Mutation: treat all four files as sitting in one folder -> the fourth file is reported at the wrong path.
        $fixture = New-F132Root -EmulatorType 'cxbxr' -Games @('VIRTUACOP3')
        $warnings = @(Get-F132Warning -Fixture $fixture)
        $warnings.Count | Should -Be 1
        $warnings[0].MissingFiles.Count | Should -Be 4
        $folder = Join-Path $fixture.Root 'cxbxr\TeknoParrot\EmuMediaBoard'
        New-Item -ItemType Directory -Path (Join-Path $folder 'Chihiro') -Force | Out-Null
        foreach ($name in @('ic10_g24lc64.bin', 'pc20_g24lc64.bin', 'ic11_24lc024.bin')) { New-Item -ItemType File -Path (Join-Path $folder ('Chihiro\' + $name)) -Force | Out-Null }
        $warnings = @(Get-F132Warning -Fixture $fixture)
        @($warnings[0].MissingFiles) | Should -Be @('fpr21042_m29w160et.bin')
        $warnings[0].MissingItems[0].Path | Should -Be (Join-Path $folder 'fpr21042_m29w160et.bin')
    }

    It 'adds a library health row: OK, needs attention with the number of games, could not check, and nothing when the check did not run' {
        # Mutation: leave PrerequisiteCheckFailed out of the row, or show OK for a failed check -> the failed case reads as clean.
        $fixture = New-F132Root -Games @('A', 'B')
        $missing = @(Get-TpmMissingPrerequisites -Profiles @(Get-ChildItem -LiteralPath $fixture.Profiles -Filter '*.xml') -TeknoParrotRoot $fixture.Root)
        $missing.Count | Should -Be 1
        (Get-TpmLibraryHealthPrerequisiteRow -Result ([pscustomobject]@{ PrerequisiteChecked = $true; PrerequisiteCheckFailed = $false; PrerequisiteMissing = @($missing) })).Text | Should -Be 'Needs attention - 2 games have missing files'
        (Get-TpmLibraryHealthPrerequisiteRow -Result ([pscustomobject]@{ PrerequisiteChecked = $true; PrerequisiteCheckFailed = $false; PrerequisiteMissing = @() })).Text | Should -Be 'OK'
        (Get-TpmLibraryHealthPrerequisiteRow -Result ([pscustomobject]@{ PrerequisiteChecked = $true; PrerequisiteCheckFailed = $true; PrerequisiteMissing = @() })).Text | Should -Be 'Could not check'
        Get-TpmLibraryHealthPrerequisiteRow -Result ([pscustomobject]@{ PrerequisiteChecked = $false }) | Should -BeNullOrEmpty
    }

    It 'reads Not checked, not OK, when the emulator folder is not there yet' {
        # Who gets hurt: a user with a game whose emulator is not set up yet read "Game startup files: OK" although nothing was looked at. Mutation: ignore the not-checked list in the row -> OK.
        $fixture = New-F132Root -NoEmulator -Games @('A')
        $notChecked = New-Object System.Collections.ArrayList
        $missing = @(Get-TpmMissingPrerequisites -Profiles @(Get-ChildItem -LiteralPath $fixture.Profiles -Filter '*.xml') -TeknoParrotRoot $fixture.Root -NotChecked $notChecked)
        $missing.Count | Should -Be 0
        $notChecked.Count | Should -Be 1
        (Get-TpmLibraryHealthPrerequisiteRow -Result ([pscustomobject]@{ PrerequisiteChecked = $true; PrerequisiteCheckFailed = $false; PrerequisiteMissing = @($missing); PrerequisiteNotChecked = @($notChecked) })).Text | Should -Match '^Not checked - 1 emulator is not set up yet'
    }
}

Describe 'FIX132 the DAT readers return the [EMU] sets' {
    BeforeEach { Install-F132Mocks }

    It 'collects the files of [EMU] sets only, and leaves the normal DAT index exactly as it was' {
        # Mutation: collect every game, or change what the index returns when a sink is passed -> this fails.
        $text = New-F132DatText -Games @(@{ Name = $script:F132ZipName; Roms = @(@{ Name = 'r27v1602f.7d'; Bytes = $script:F132Bytes7d }) }, @{ Name = 'Some Real Game (World)'; Profile = 'RealGame'; Roms = @(@{ Name = 'game.bin'; Bytes = $script:F132Bytes8g }) })
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
        $sink = @{}
        $withSink = Build-DatIndexFromStream (New-Object System.IO.MemoryStream (, $bytes)) -EmuRomSink $sink
        $without = Build-DatIndexFromStream (New-Object System.IO.MemoryStream (, $bytes))
        @($sink.Keys) | Should -Be @($script:F132ZipName)
        $sink[$script:F132ZipName].Count | Should -Be 1
        $sink[$script:F132ZipName][0].Name | Should -Be 'r27v1602f.7d'
        $sink[$script:F132ZipName][0].Size | Should -Be $script:F132Bytes7d.Length
        $sink[$script:F132ZipName][0].Sha1 | Should -Match '^[0-9a-f]{40}$'
        @($withSink.Keys) | Should -Be @($without.Keys)
        $withSink.Count | Should -Be 1
    }

    It 'reads the sets from a loose DAT file and from the Supplementary entry of the Eggman ZIP, and says so when none is loaded' {
        # Mutation: read only the collection entry of the ZIP, or ignore a loose file -> the set is not found.
        $collection = New-F132Collection
        (Get-TpmEmuDatRomSets -SupplementaryDatPath $collection.Dat).Games.ContainsKey($script:F132ZipName) | Should -BeTrue
        $datZip = Join-Path $TestDrive ('eggman-' + [guid]::NewGuid().ToString('N') + '.zip')
        New-F132Zip -Path $datZip -Entries ([ordered]@{ 'Supplementary_RomVault.dat' = [System.Text.Encoding]::UTF8.GetBytes([System.IO.File]::ReadAllText($collection.Dat)); 'Collection_RomVault.dat' = [System.Text.Encoding]::UTF8.GetBytes('<datafile></datafile>') })
        $fromZip = Get-TpmEmuDatRomSets -EggmanDatZip $datZip
        $fromZip.Available | Should -BeTrue
        $fromZip.Games.ContainsKey($script:F132ZipName) | Should -BeTrue
        (Get-TpmEmuDatRomSets).Available | Should -BeFalse
        $expectation = Get-TpmDatFileExpectation -DatRoms (Get-TpmEmuDatRomSets) -FileName 'r27v1602f.7d'
        $expectation.Found | Should -BeFalse
        $expectation.Reason | Should -Match 'No DAT'
    }

    It 'does not accept a DAT line without a size or a hash, or one that describes the file two ways' {
        # Mutation: treat a file with no hash as verified -> Found is true for a line that cannot prove anything.
        $noHash = [pscustomobject]@{ Games = @{ 'g' = @([pscustomobject]@{ Name = 'a.bin'; Size = '5'; Crc = ''; Md5 = ''; Sha1 = ''; Sha256 = '' }) } }
        (Get-TpmDatFileExpectation -DatRoms $noHash -FileName 'a.bin' -GameName 'g').Found | Should -BeFalse
        $noSize = [pscustomobject]@{ Games = @{ 'g' = @([pscustomobject]@{ Name = 'a.bin'; Size = ''; Crc = '00000000'; Md5 = ''; Sha1 = ''; Sha256 = '' }) } }
        (Get-TpmDatFileExpectation -DatRoms $noSize -FileName 'a.bin' -GameName 'g').Found | Should -BeFalse
        $twoWays = [pscustomobject]@{ Games = @{ 'g' = @([pscustomobject]@{ Name = 'a.bin'; Size = '5'; Crc = '00000001'; Md5 = ''; Sha1 = ''; Sha256 = '' }, [pscustomobject]@{ Name = 'dir/a.bin'; Size = '5'; Crc = '00000002'; Md5 = ''; Sha1 = ''; Sha256 = '' }) } }
        (Get-TpmDatFileExpectation -DatRoms $twoWays -FileName 'a.bin' -GameName 'g').Found | Should -BeFalse
    }
}

Describe 'FIX132 the fix step copies from the player''s own archive after checking against the DAT' {
    BeforeEach { Install-F132Mocks }

    It 'plans the copy from the [EMU] archive and installs both files with the exact bytes, leaving no staging folder behind' {
        # Mutation: skip the staging, write to the wrong folder, or leave the staging folder -> bytes, location or residue checks fail.
        $fixture = New-F132Root
        $collection = New-F132Collection
        $plan = Get-F132Plan -Fixture $fixture -Collection $collection
        $plan.AllInstallable | Should -BeTrue
        @($plan.Items.Source | Select-Object -Unique) | Should -Be @('Archive')
        $result = Invoke-TpmPrerequisiteInstall -Plan $plan -TpRoot $fixture.Root
        $result.Outcome | Should -Be 'SUCCEEDED'
        $result.Complete | Should -BeTrue
        @($result.Installed | Sort-Object) | Should -Be @('r27v1602f.7d', 'r27v1602f.8g')
        [System.IO.File]::ReadAllBytes((Join-Path $fixture.Bios 'r27v1602f.7d')) | Should -Be $script:F132Bytes7d
        [System.IO.File]::ReadAllBytes((Join-Path $fixture.Bios 'r27v1602f.8g')) | Should -Be $script:F132Bytes8g
        @(Get-F132Warning -Fixture $fixture).Count | Should -Be 0
        $stage = Join-Path $fixture.Root 'TeknoParrotManager\Temp\prerequisite-stage'
        (Test-Path -LiteralPath $stage) | Should -BeFalse
        @($script:logLines | Where-Object { $_ -match 'outcome=SUCCEEDED' }).Count | Should -BeGreaterThan 0
    }

    It 'refuses a file the DAT does not describe: found but unverifiable means nothing is copied' {
        # Mutation: copy when the DAT has no entry for the file -> bytes appear in the bios folder.
        $fixture = New-F132Root
        $collection = New-F132Collection -NoDat
        $plan = Get-F132Plan -Fixture $fixture -Collection $collection
        $plan.AnySource | Should -BeTrue
        $plan.AllInstallable | Should -BeFalse
        $result = Invoke-TpmPrerequisiteInstall -Plan $plan -TpRoot $fixture.Root
        $result.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        $result.Complete | Should -BeFalse
        @($result.Refused).Count | Should -Be 2
        (Test-Path -LiteralPath (Join-Path $fixture.Bios 'r27v1602f.7d')) | Should -BeFalse
    }

    It 'refuses a file whose hash is not the one the DAT lists, even when the size is right, and copies none of the set' {
        # Mutation: compare only the size, or only the first hash, or promote the good file anyway -> the tampered file (or its partner) lands.
        $fixture = New-F132Root
        $collection = New-F132Collection -TamperDat
        $plan = Get-F132Plan -Fixture $fixture -Collection $collection
        $plan.AllInstallable | Should -BeTrue
        $result = Invoke-TpmPrerequisiteInstall -Plan $plan -TpRoot $fixture.Root
        @($result.Refused) | Should -Be @('r27v1602f.8g')
        $result.Complete | Should -BeFalse
        ($result.Reasons -join ' ') | Should -Match 'SHA1'
        (Test-Path -LiteralPath (Join-Path $fixture.Bios 'r27v1602f.8g')) | Should -BeFalse
    }

    It 'checks every hash the DAT lists, one at a time (CRC, MD5, SHA-1, SHA-256), not just one of them' -ForEach @(
        @{ Hash = 'crc' }, @{ Hash = 'md5' }, @{ Hash = 'sha1' }
    ) {
        # Mutation: skip one algorithm in Test-TpmPrerequisiteFileAgainstDat -> that case accepts a wrong file.
        $file = Join-Path $TestDrive ('chk-' + [guid]::NewGuid().ToString('N') + '.bin')
        [System.IO.File]::WriteAllBytes($file, $script:F132Bytes7d)
        $h = Get-F132Hashes -Bytes $script:F132Bytes7d
        $expectation = [pscustomobject]@{ Found = $true; Reason = ''; Length = [int64]$h.Size; Crc = $h.Crc; Md5 = $h.Md5; Sha1 = $h.Sha1; Sha256 = $h.Sha256 }
        (Test-TpmPrerequisiteFileAgainstDat -Path $file -Expectation $expectation).Matches | Should -BeTrue
        $bad = $expectation.PSObject.Copy()
        $bad.($Hash.Substring(0, 1).ToUpper() + $Hash.Substring(1)) = $(if ($Hash -eq 'crc') { 'deadbeef' } elseif ($Hash -eq 'md5') { '0' * 32 } else { '0' * 40 })
        (Test-TpmPrerequisiteFileAgainstDat -Path $file -Expectation $bad).Matches | Should -BeFalse
        $wrongSize = $expectation.PSObject.Copy(); $wrongSize.Length = [int64]($h.Size + 1)
        (Test-TpmPrerequisiteFileAgainstDat -Path $file -Expectation $wrongSize).Matches | Should -BeFalse
    }

    It 'never writes outside the table destination: an unsafe member name is ignored and no file is extracted from it' {
        # Mutation: take the destination from the archive member name instead of the table -> the planted file appears outside the bios folder.
        $fixture = New-F132Root
        $evil = Join-Path $fixture.Root 'evil'
        $entries = [ordered]@{ '../evil/r27v1602f.7d' = $script:F132Bytes7d; 'PCSX2x6/../../r27v1602f.8g' = $script:F132Bytes8g; 'ok/r27v1602f.7d' = $script:F132Bytes7d }
        $collection = New-F132Collection -ZipEntries $entries
        $plan = Get-F132Plan -Fixture $fixture -Collection $collection
        $byName = @{}; foreach ($item in $plan.Items) { $byName[$item.Name] = $item }
        $byName['r27v1602f.7d'].Source | Should -Be 'Archive'
        $byName['r27v1602f.7d'].EntryName | Should -Be 'ok/r27v1602f.7d'
        $byName['r27v1602f.8g'].Source | Should -Be 'None'
        [void](Invoke-TpmPrerequisiteInstall -Plan $plan -TpRoot $fixture.Root)
        (Test-Path -LiteralPath $evil) | Should -BeFalse
        (Test-Path -LiteralPath (Join-Path $fixture.Root 'r27v1602f.8g')) | Should -BeFalse
        (Test-Path -LiteralPath (Join-Path $fixture.Bios 'r27v1602f.7d')) | Should -BeTrue
    }

    It 'keeps a different file that is already in place unless the player says replace, and saves a backup copy before replacing it' {
        # Mutation: overwrite without the name in ReplaceNames, or replace without the backup copy -> the first or the last check fails.
        $fixture = New-F132Root
        $collection = New-F132Collection
        $plan = Get-F132Plan -Fixture $fixture -Collection $collection
        New-Item -ItemType Directory -Path $fixture.Bios -Force | Out-Null
        $mine = [System.Text.Encoding]::ASCII.GetBytes('my own different file')
        [System.IO.File]::WriteAllBytes((Join-Path $fixture.Bios 'r27v1602f.7d'), $mine)
        $first = Invoke-TpmPrerequisiteInstall -Plan $plan -TpRoot $fixture.Root
        @($first.KeptExisting) | Should -Be @('r27v1602f.7d')
        @($first.Installed) | Should -Be @('r27v1602f.8g')
        $first.Complete | Should -BeFalse
        [System.IO.File]::ReadAllBytes((Join-Path $fixture.Bios 'r27v1602f.7d')) | Should -Be $mine
        $second = Invoke-TpmPrerequisiteInstall -Plan $plan -TpRoot $fixture.Root -ReplaceNames @('r27v1602f.7d')
        @($second.Replaced) | Should -Be @('r27v1602f.7d')
        [System.IO.File]::ReadAllBytes((Join-Path $fixture.Bios 'r27v1602f.7d')) | Should -Be $script:F132Bytes7d
        $second.BackupFolder | Should -Not -BeNullOrEmpty
        $backups = @(Get-ChildItem -LiteralPath $second.BackupFolder -File)
        $backups.Count | Should -Be 1
        [System.IO.File]::ReadAllBytes($backups[0].FullName) | Should -Be $mine
    }

    It 'notices an existing file that is not the one the DAT describes, and replaces it only when the player says so (backup first)' {
        # Mutation: never compare existing files with the DAT (the wrong file stays unnoticed), replace without asking, or skip the backup -> this fails.
        $fixture = New-F132Root
        $collection = New-F132Collection
        New-Item -ItemType Directory -Path $fixture.Bios -Force | Out-Null
        $mine = [System.Text.Encoding]::ASCII.GetBytes('a different dump of the second file')
        [System.IO.File]::WriteAllBytes((Join-Path $fixture.Bios 'r27v1602f.8g'), $mine)
        $warnings = @(Get-F132Warning -Fixture $fixture)
        @($warnings[0].MissingFiles) | Should -Be @('r27v1602f.7d')
        $plan = Get-F132Plan -Fixture $fixture -Collection $collection
        @($plan.Items | Where-Object WrongExisting | ForEach-Object Name) | Should -Be @('r27v1602f.8g')
        (Get-TpmPrerequisiteScreenLines -Warning $warnings[0] -Plan $plan).Plain -join ' ' | Should -Match 'already in the folder is not the file'
        # The player says N to the replace question: the copy of the missing file happens, the existing file stays, and the screen calls that the player's choice (not a failure).
        $hostLines = New-Object System.Collections.ArrayList
        Mock Write-Host { [void]$hostLines.Add([string]$Object) }
        Mock Read-TpmChoice { 'Y' }
        Mock Read-TpmYesNo { 'N' }
        [void](Invoke-TpmPrerequisiteReview -Warnings $warnings -TpRoot $fixture.Root -SearchFolders @($collection.Folder) -SupplementaryDatPath $collection.Dat -Interactive)
        [System.IO.File]::ReadAllBytes((Join-Path $fixture.Bios 'r27v1602f.8g')) | Should -Be $mine
        [System.IO.File]::ReadAllBytes((Join-Path $fixture.Bios 'r27v1602f.7d')) | Should -Be $script:F132Bytes7d
        ($hostLines -join "`n") | Should -Match 'kept, as you chose'
        ($hostLines -join "`n") | Should -Not -Match 'not all copied'
        # The player says Y: the file is replaced and the old one is saved first.
        Remove-Item -LiteralPath (Join-Path $fixture.Bios 'r27v1602f.7d') -Force
        $warnings = @(Get-F132Warning -Fixture $fixture)
        Mock Read-TpmYesNo { 'Y' }
        [void](Invoke-TpmPrerequisiteReview -Warnings $warnings -TpRoot $fixture.Root -SearchFolders @($collection.Folder) -SupplementaryDatPath $collection.Dat -Interactive)
        [System.IO.File]::ReadAllBytes((Join-Path $fixture.Bios 'r27v1602f.8g')) | Should -Be $script:F132Bytes8g
        $backup = @(Get-ChildItem -LiteralPath (Join-Path $fixture.Root 'TeknoParrotManager\Backups\Prerequisites') -Recurse -File)
        $backup.Count | Should -Be 1
        [System.IO.File]::ReadAllBytes($backup[0].FullName) | Should -Be $mine
    }

    It 'counts the file copied first and the file replaced after the question in one Done line' {
        $fixture = New-F132Root
        $collection = New-F132Collection
        New-Item -ItemType Directory -Path $fixture.Bios -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $fixture.Bios 'r27v1602f.8g'), [System.Text.Encoding]::ASCII.GetBytes('a different dump'))
        $warnings = @(Get-F132Warning -Fixture $fixture)
        $hostLines = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$hostLines.Add([string]$Object) }
        Mock Read-TpmChoice { 'Y' }
        Mock Read-TpmYesNo { 'Y' }
        $review = Invoke-TpmPrerequisiteReview -Warnings $warnings -TpRoot $fixture.Root -SearchFolders @($collection.Folder) -SupplementaryDatPath $collection.Dat -Interactive
        $review.FixedAny | Should -BeTrue
        ($hostLines -join "`n") | Should -Match 'Done\. 2 files were copied and checked'
    }

    It 'says the files are already in place when the same bytes are there, and changes nothing' {
        # Mutation: treat identical bytes as a conflict -> KeptExisting is filled and Complete is false.
        $fixture = New-F132Root
        $collection = New-F132Collection
        $plan = Get-F132Plan -Fixture $fixture -Collection $collection
        New-Item -ItemType Directory -Path $fixture.Bios -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $fixture.Bios 'r27v1602f.7d'), $script:F132Bytes7d)
        [System.IO.File]::WriteAllBytes((Join-Path $fixture.Bios 'r27v1602f.8g'), $script:F132Bytes8g)
        $result = Invoke-TpmPrerequisiteInstall -Plan $plan -TpRoot $fixture.Root
        $result.Outcome | Should -Be 'NO_OP'
        $result.Complete | Should -BeTrue
        @($result.AlreadyPresent).Count | Should -Be 2
    }

    It 'uses the same file from another TeknoParrot copy only after the DAT confirms it, and refuses a different one' {
        # Mutation: copy from the other install without the DAT check -> the wrong file is installed.
        $fixture = New-F132Root
        $other = New-F132Root -Name 'other'
        New-Item -ItemType Directory -Path $other.Bios -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $other.Bios 'r27v1602f.7d'), $script:F132Bytes7d)
        [System.IO.File]::WriteAllBytes((Join-Path $other.Bios 'r27v1602f.8g'), [System.Text.Encoding]::ASCII.GetBytes('not the real second file'))
        $collection = New-F132Collection
        # An empty collection folder (no archive) with the DAT, so the only source is the other install.
        Remove-Item -LiteralPath $collection.Zip -Force
        $plan = Get-F132Plan -Fixture $fixture -Collection $collection -OtherRoots @($other.Root, $fixture.Root)
        $byName = @{}; foreach ($item in $plan.Items) { $byName[$item.Name] = $item }
        $byName['r27v1602f.7d'].Source | Should -Be 'OtherInstall'
        $result = Invoke-TpmPrerequisiteInstall -Plan $plan -TpRoot $fixture.Root
        @($result.Installed) | Should -Be @('r27v1602f.7d')
        @($result.Refused) | Should -Be @('r27v1602f.8g')
        (Test-Path -LiteralPath (Join-Path $fixture.Bios 'r27v1602f.8g')) | Should -BeFalse
    }

    It 'copies nothing when the TeknoParrot folder is missing or the plan has nothing installable' {
        # Mutation: run the transaction with an empty operation list or without checking the root -> a result claims success.
        $result = Invoke-TpmPrerequisiteInstall -Plan ([pscustomobject]@{ Items = @() }) -TpRoot (Join-Path $TestDrive 'does-not-exist')
        $result.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        $result.Complete | Should -BeFalse
        $fixture = New-F132Root
        $none = Invoke-TpmPrerequisiteInstall -Plan ([pscustomobject]@{ Items = @() }) -TpRoot $fixture.Root
        $none.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        $none.Complete | Should -BeFalse
    }
}

Describe 'FIX132 what the player reads' {
    BeforeEach { Install-F132Mocks }

    It 'uses plain words with exactly one next step, and keeps file names, paths, hashes and archive names for Details and the log' -ForEach @(
        @{ Case = 'fixable' }, @{ Case = 'found but unverifiable' }, @{ Case = 'found some' }, @{ Case = 'not found' }, @{ Case = 'saved report (no plan)' }
    ) {
        # Mutation: put a path or file name in a plain line, add a second "Next step:", or drop the Details lines -> this fails.
        $fixture = New-F132Root
        $collection = switch ($Case) { 'fixable' { New-F132Collection } 'found but unverifiable' { New-F132Collection -NoDat } 'found some' { New-F132Collection -ZipEntries @{ 'PCSX2x6/TeknoParrot/bios/r27v1602f.7d' = $script:F132Bytes7d } } default { $null } }
        $warning = @(Get-F132Warning -Fixture $fixture)[0]
        $plan = if ($Case -eq 'saved report (no plan)') { $null } else { Get-F132Plan -Fixture $fixture -Collection $collection }
        $lines = Get-TpmPrerequisiteScreenLines -Warning $warning -Plan $plan
        $plain = @($lines.Plain) -join "`n"
        $plain | Should -Not -Match '[\\/]|r27v1602f|\.7d|\.8g|(?i)sha|crc|md5|hash|zip|archive|transaction|emulatortype|\.bin'
        @($lines.Plain | Where-Object { $_ -match '^Next step:' }).Count | Should -Be 1
        $plain | Should -Match 'PCSX2x6 firmware is missing'
        $plain | Should -Match 'BLOODYROAR3'
        $details = @($lines.Details) -join "`n"
        $details | Should -Match 'r27v1602f\.7d'
        $details | Should -Match ([regex]::Escape($fixture.Bios))
        if ($Case -eq 'fixable') { $details | Should -Match 'the DAT lists it' }
        if ($Case -eq 'not found') { $plain | Should -Match 'press O to open the folder' }
        if ($Case -eq 'found some') { $plain | Should -Match 'not all of them'; $plain | Should -Not -Match 'cannot prove|get the DAT list' }
        if ($Case -eq 'found but unverifiable') { $plain | Should -Match 'cannot prove' }
        $lines.Heading | Should -Be 'PCSX2X6 FIRMWARE IS MISSING'
    }

    It 'names only the Play! games whose own file is missing, so the counts match' {
        # Mutation: return every Play! game as affected -> GOODGAME is listed although its file is in place.
        $root = Join-Path $TestDrive ('f132-play-' + [guid]::NewGuid().ToString('N'))
        $profiles = Join-Path $root 'UserProfiles'
        New-Item -ItemType Directory -Path $profiles, (Join-Path $root 'Play\arcadedefs') -Force | Out-Null
        foreach ($pair in @(@('GOODGAME', 'good.zip'), @('BADGAME', 'bad.zip'))) {
            [System.IO.File]::WriteAllText((Join-Path $profiles ($pair[0] + '.xml')), ('<GameProfile><EmulatorType>Play</EmulatorType><ExecutableName>{0}</ExecutableName></GameProfile>' -f $pair[1]))
        }
        [System.IO.File]::WriteAllText((Join-Path $root 'Play\arcadedefs\good.arcadedef'), 'x')
        $warning = Get-TpmPrerequisiteWarning -EmulatorType 'Play' -Requirement $script:F132ProductionTable['Play'] -TeknoParrotRoot $root -AffectedGames @('GOODGAME', 'BADGAME') -Profiles @(Get-ChildItem -LiteralPath $profiles -Filter '*.xml')
        @($warning.AffectedGames) | Should -Be @('BADGAME')
        @($warning.MissingFiles) | Should -Be @('bad.arcadedef')
        (Get-TpmPrerequisiteScreenLines -Warning $warning).Plain[0] | Should -Match 'this game will not start: BADGAME'
    }

    It 'tells the player which archive to put in their collection when no source is found' -ForEach @(
        @{ Type = 'RPCS3'; Missing = 'liblv2.sprx'; Say = 'PlayStation 3 firmware archive' }
        @{ Type = 'Play'; Missing = 'bad.arcadedef'; Say = 'Play! working arcadedefs' }
    ) {
        # Mutation: restore the old "put the missing files in it" sentence -> neither text names the archive.
        $requirement = $script:F132ProductionTable[$Type]
        $warning = [pscustomobject]@{ EmulatorType = $Type; Label = 'X'; AffectedGames = @('G'); MissingFiles = @($Missing); ExpectedDir = 'D'; Requirement = $requirement }
        $plan = [pscustomobject]@{ Items = @(); Archives = @(); AllInstallable = $false; AnySource = $false }
        $plain = @((Get-TpmPrerequisiteScreenLines -Warning $warning -Plan $plan).Plain) -join "`n"
        $plain | Should -Match ([regex]::Escape($Say))
        $plain | Should -Match 'Supplementary or main ZIP folder'
        $plain | Should -Not -Match 'put the missing files in it'
    }

    It 'never prompts or writes when the run is not interactive, and still reports and logs the details' {
        # Mutation: prompt without -Interactive (an unattended run would wait) or copy without being asked -> the mock is called / files appear.
        $fixture = New-F132Root
        $collection = New-F132Collection
        $warnings = @(Get-F132Warning -Fixture $fixture)
        Mock Read-TpmChoice { throw 'must not prompt' }
        Mock Read-TpmYesNo { throw 'must not prompt' }
        $review = Invoke-TpmPrerequisiteReview -Warnings $warnings -TpRoot $fixture.Root -SearchFolders @($collection.Folder) -SupplementaryDatPath $collection.Dat
        $review.Reviewed | Should -Be 1
        $review.FixedAny | Should -BeFalse
        Should -Invoke Read-TpmChoice -Times 0 -Exactly
        (Test-Path -LiteralPath (Join-Path $fixture.Bios 'r27v1602f.7d')) | Should -BeFalse
        ($script:screen -join "`n") | Should -Match 'Next step:'
        ($script:logLines -join "`n") | Should -Match 'r27v1602f\.7d'
    }

    It 'copies only after the player answers Y, and leaves everything alone on N' {
        # Mutation: copy before the question or on N -> the N case finds files, the Y case finds none.
        $fixture = New-F132Root
        $collection = New-F132Collection
        $warnings = @(Get-F132Warning -Fixture $fixture)
        Mock Read-TpmChoice { 'N' }
        $declined = Invoke-TpmPrerequisiteReview -Warnings $warnings -TpRoot $fixture.Root -SearchFolders @($collection.Folder) -SupplementaryDatPath $collection.Dat -Interactive
        $declined.FixedAny | Should -BeFalse
        (Test-Path -LiteralPath (Join-Path $fixture.Bios 'r27v1602f.7d')) | Should -BeFalse
        Mock Read-TpmChoice { 'Y' }
        $accepted = Invoke-TpmPrerequisiteReview -Warnings $warnings -TpRoot $fixture.Root -SearchFolders @($collection.Folder) -SupplementaryDatPath $collection.Dat -Interactive
        $accepted.FixedAny | Should -BeTrue
        @(Get-F132Warning -Fixture $fixture).Count | Should -Be 0
    }

    It 'offers no copy when nothing can be checked, and the Open folder button opens the folder that is missing files (or the nearest one above it)' {
        # Mutation: offer Y for an unverifiable set, or open the wrong folder -> the choices or the opened path differ.
        $fixture = New-F132Root
        $warnings = @(Get-F132Warning -Fixture $fixture)
        $script:offered = $null
        $script:answers = New-Object System.Collections.Generic.Queue[string]
        foreach ($a in @('O', 'N')) { $script:answers.Enqueue($a) }
        Mock Read-PathWithBrowse { '' }
        Mock Read-TpmChoice { $script:offered = @($Choices); $script:answers.Dequeue() }
        Mock Open-TpmOwnedFolder { [pscustomobject]@{ Succeeded = $true; Path = $Path; Error = $null } }
        [void](Invoke-TpmPrerequisiteReview -Warnings $warnings -TpRoot $fixture.Root -Interactive)
        $script:offered | Should -Not -Contain 'Y'
        Should -Invoke Open-TpmOwnedFolder -Times 1 -Exactly -ParameterFilter { $Path -eq $fixture.Pcsx2 }
        New-Item -ItemType Directory -Path $fixture.Bios -Force | Out-Null
        (Get-TpmPrerequisiteOpenFolder -Warning @(Get-F132Warning -Fixture $fixture)[0]) | Should -Be $fixture.Bios
    }

    It 'keeps the saved action report plain and complete: heading kept, plain lines, then Details with names and paths' {
        # Mutation: print the file names in the plain lines or leave the Details out of the saved report -> this fails.
        $fixture = New-F132Root
        $warnings = @(Get-F132Warning -Fixture $fixture)
        $text = New-TpmActionRequiredReportText -CompatibilityWarnings ([pscustomobject]@{ PathTooLong = @(); DllMismatch = @(); GpuIncompatible = @(); BiosMissing = @($warnings); ExeMissing = @() }) -RunId 'test'
        $text | Should -Match 'PCSX2X6 FIRMWARE NOT INSTALLED'
        $text | Should -Match 'PCSX2x6 firmware is missing, so this game will not start: BLOODYROAR3\.'
        $text | Should -Match 'Next step:'
        $text | Should -Match 'Details:'
        $text | Should -Match 'r27v1602f\.8g'
    }

    It 'adds a "what this game needs" line from the game profile and the table only' {
        # Mutation: read the line from free text, or drop the admin / BepInEx / firmware parts -> this fails.
        $fixture = New-F132Root
        $profile = Join-Path $fixture.Profiles 'NEEDY.xml'
        [System.IO.File]::WriteAllText($profile, '<?xml version="1.0"?><GameProfile><EmulatorType>Pcsx2x6</EmulatorType><RequiresBepInEx>true</RequiresBepInEx><RequiresAdmin>true</RequiresAdmin></GameProfile>')
        $line = Get-TpmGameNeedsLine -ProfilePath $profile -SetupExe 'setup.exe'
        $line | Should -Be 'What this game needs: PCSX2x6 firmware (2 files); BepInEx installed in the game folder; TeknoParrotUI run as administrator; its own setup program run once (see Run below).'
        Get-TpmGameNeedsLine -ProfilePath (Join-Path $fixture.Profiles 'BLOODYROAR3.xml') | Should -Be 'What this game needs: PCSX2x6 firmware (2 files).'
        $plainProfile = Join-Path $fixture.Profiles 'PLAIN.xml'
        [System.IO.File]::WriteAllText($plainProfile, '<?xml version="1.0"?><GameProfile><EmulatorType>Other</EmulatorType></GameProfile>')
        Get-TpmGameNeedsLine -ProfilePath $plainProfile | Should -Be ''
        $notes = New-TpmGameNotesReportText -SetupNotes @([pscustomobject]@{ Code = 'NEEDY'; GameName = 'Needy'; SetupExe = 'setup.exe'; Notes = 'n'; Needs = $line })
        $notes | Should -Match 'What this game needs: PCSX2x6 firmware'
    }
}

Describe 'FIX132 the DAT and Game Notes sources fall back to a saved copy with a plain message' {
    BeforeEach { Install-F132Mocks }

    It 'points at the canonical Eggman repository and accepts no other repository for the DAT download' {
        # Mutation: point the release query or the URL check at another repository (for example the old Datfiles repo) -> this fails.
        $script:F132ProductionSource | Should -Match 'api\.github\.com/repos/Eggmansworld/TeknoParrot/releases/latest'
        $script:F132ProductionSource | Should -Match 'https://eggmansworld\.github\.io/TeknoParrot/'
        Test-EggmanDatReleaseUrl -Url 'https://github.com/Eggmansworld/TeknoParrot/releases/download/2026-06-17/x.zip' | Should -BeTrue
        Test-EggmanDatReleaseUrl -Url 'https://github.com/Eggmansworld/Datfiles/releases/download/teknoparrot/x.zip' | Should -BeFalse
    }

    It 'uses the newest valid DAT ZIP saved earlier and skips a damaged one' {
        # Mutation: take the newest file without validating it, or ignore the folder -> the damaged file is picked or nothing is found.
        $root = Join-Path $TestDrive ('f132-cache-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        Find-TpmCachedEggmanDatZip -RootPath $root | Should -BeNullOrEmpty
        $good = Join-Path $root 'older.zip'
        New-F132Zip -Path $good -Entries ([ordered]@{ 'Collection_RomVault.dat' = [System.Text.Encoding]::UTF8.GetBytes('<datafile></datafile>') })
        (Get-Item -LiteralPath $good).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddDays(-3)
        $bad = Join-Path $root 'newer.zip'
        [System.IO.File]::WriteAllText($bad, 'this is not a zip')
        Find-TpmCachedEggmanDatZip -RootPath $root | Should -Be $good
    }

    It 'saves the Game Notes list after a good fetch and uses that copy, with a plain message, when the page cannot be reached' {
        # Mutation: never save the copy, or return nothing on failure -> the offline call gets no games.
        $root = Join-Path $TestDrive ('f132-notes-' + [guid]::NewGuid().ToString('N'))
        $json = '[{"profile_name":"abc","game_name":"Game A","setup_exe":"setup-a.exe","notes":"note A"}]'
        Mock Invoke-TpmWebRequestSilently { [pscustomobject]@{ Content = ('<html><script type="application/json" id="game-data">' + $json + '</script></html>') } }
        Mock Start-Sleep { }
        $online = @(Get-EggmanGameData -CacheRoot $root)
        $online.Count | Should -Be 1
        (Test-Path -LiteralPath (Join-Path $root 'game-data.json')) | Should -BeTrue
        Mock Invoke-TpmWebRequestSilently { throw 'offline' }
        $script:TpmGameNotesFallbackAnnounced = $false
        $hostLines = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$hostLines.Add([string]$Object) }
        $offline = @(Get-EggmanGameData -CacheRoot $root)
        $offline.Count | Should -Be 1
        $offline[0].profile_name | Should -Be 'abc'
        ($hostLines -join ' ') | Should -Match 'using the copy it saved earlier'
        ($hostLines -join ' ') | Should -Not -Match 'offline|Exception'
        ($script:logLines -join ' ') | Should -Match 'using the saved copy'
    }

    It 'says plainly that notes are skipped when the page cannot be reached and no copy was saved' {
        # Mutation: throw, or return stale data from somewhere else -> this fails.
        $root = Join-Path $TestDrive ('f132-nonotes-' + [guid]::NewGuid().ToString('N'))
        Mock Invoke-TpmWebRequestSilently { throw 'offline' }
        Mock Start-Sleep { }
        $script:TpmGameNotesFallbackAnnounced = $false
        $hostLines = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$hostLines.Add([string]$Object) }
        Get-EggmanGameData -CacheRoot $root | Should -BeNullOrEmpty
        ($hostLines -join ' ') | Should -Match 'no saved copy'
    }
}

# Issue #387: Chihiro and PlayStation 3 startup files must work from one clear step, like the CPS3 offer: ask once for the
# Supplementary folder, scan it, check against the DAT, install, and report per package. Synthetic files and TestDrive only.
Describe 'Startup files: one folder question, one Y, and a plain report per package (issue 387)' {
    BeforeAll {
        $script:F387Zip = '[EMU] CxbxR BIOS Firmware for Sega Chihiro [TP]'
        $script:F387Names = @('ic10_g24lc64.bin', 'pc20_g24lc64.bin', 'ic11_24lc024.bin', 'fpr21042_m29w160et.bin')
        function Get-F387Bytes { param([string]$Name, [switch]$Wrong) $text = 'synthetic chihiro file ' + $Name; if ($Wrong) { $text = $text.ToUpperInvariant() }; return [System.Text.Encoding]::ASCII.GetBytes($text) }

        # A collection with the Chihiro archive (some files left out or changed) and, with -WithPcsx2, the PCSX2x6 archive too. One DAT lists everything.
        function New-F387Collection {
            param([string[]]$LeaveOut = @(), [string[]]$Change = @(), [switch]$WithPcsx2)
            $folder = Join-Path $TestDrive ('f387-coll-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            $entries = [ordered]@{}
            foreach ($name in $script:F387Names) {
                if ($LeaveOut -contains $name) { continue }
                $entries['cxbxr/TeknoParrot/' + $name] = Get-F387Bytes -Name $name -Wrong:($Change -contains $name)
            }
            New-F132Zip -Path (Join-Path $folder ($script:F387Zip + '.zip')) -Entries $entries
            $games = @(@{ Name = $script:F387Zip; Roms = @($script:F387Names | ForEach-Object { @{ Name = $_; Bytes = (Get-F387Bytes -Name $_) } }) })
            if ($WithPcsx2) {
                New-F132Zip -Path (Join-Path $folder ($script:F132ZipName + '.zip')) -Entries ([ordered]@{ 'PCSX2x6/TeknoParrot/bios/r27v1602f.7d' = $script:F132Bytes7d; 'PCSX2x6/TeknoParrot/bios/r27v1602f.8g' = $script:F132Bytes8g })
                $games += @{ Name = $script:F132ZipName; Roms = @(@{ Name = 'r27v1602f.7d'; Bytes = $script:F132Bytes7d }, @{ Name = 'r27v1602f.8g'; Bytes = $script:F132Bytes8g }) }
            }
            $dat = Join-Path $folder 'Supplementary.dat'
            [System.IO.File]::WriteAllText($dat, (New-F132DatText -Games $games), (New-Object System.Text.UTF8Encoding $false))
            return [pscustomobject]@{ Folder = $folder; Dat = $dat }
        }

        # A root with a Chihiro game (and, with -WithPcsx2, a PCSX2x6 game too), both emulator folders present, both missing their files.
        function New-F387Root {
            param([switch]$WithPcsx2)
            $fixture = New-F132Root -EmulatorType 'cxbxr' -Games @('VIRTUACOP3')
            if ($WithPcsx2) {
                [System.IO.File]::WriteAllText((Join-Path $fixture.Profiles 'BLOODYROAR3.xml'), '<?xml version="1.0" encoding="utf-8"?><GameProfile><EmulatorType>Pcsx2x6</EmulatorType><GamePath>C:\Games\game.exe</GamePath></GameProfile>')
                New-Item -ItemType Directory -Path (Join-Path $fixture.Root 'pcsx2x6') -Force | Out-Null
            }
            return $fixture
        }
    }
    BeforeEach {
        Install-F132Mocks
        $script:zipSourceSupplementary = $null
        $script:TpmSupplementaryFolderAsked = $false
        $script:hostLines = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$script:hostLines.Add([string]$Object) }
        Mock Save-Config { $true }
    }

    It 'asks once for the folder, saves it, installs Chihiro and PCSX2x6 with ONE Y, and never asks again' {
        # Mutation: no question, a question per package, a second Y per package, or the folder not saved -> this fails.
        $fixture = New-F387Root -WithPcsx2
        $collection = New-F387Collection -WithPcsx2
        $warnings = @(Get-F132Warning -Fixture $fixture)
        $warnings.Count | Should -Be 2
        Mock Read-PathWithBrowse { $collection.Folder }
        Mock Read-TpmChoice { 'Y' }
        Mock Read-TpmYesNo { throw 'must not ask a second time' }
        $review = Invoke-TpmPrerequisiteReview -Warnings $warnings -TpRoot $fixture.Root -SupplementaryDatPath $collection.Dat -Interactive
        $review.FixedAny | Should -BeTrue
        Should -Invoke Read-PathWithBrowse -Times 1 -Exactly
        Should -Invoke Read-TpmChoice -Times 1 -Exactly
        Should -Invoke Save-Config -Times 1 -Exactly
        $script:zipSourceSupplementary | Should -Be $collection.Folder
        foreach ($name in $script:F387Names) {
            $dir = if ($name -like 'fpr*') { 'cxbxr\TeknoParrot\EmuMediaBoard' } else { 'cxbxr\TeknoParrot\EmuMediaBoard\Chihiro' }
            [System.IO.File]::ReadAllBytes((Join-Path $fixture.Root (Join-Path $dir $name))) | Should -Be (Get-F387Bytes -Name $name)
        }
        [System.IO.File]::ReadAllBytes((Join-Path $fixture.Bios 'r27v1602f.7d')) | Should -Be $script:F132Bytes7d
        ($script:screen -join "`n") | Should -Match 'Installed: .*ic10_g24lc64\.bin'
        # A later run with the same saved folder never asks again.
        Remove-Item -LiteralPath (Join-Path $fixture.Root 'cxbxr\TeknoParrot') -Recurse -Force
        [void](Invoke-TpmPrerequisiteReview -Warnings @(Get-F132Warning -Fixture $fixture) -TpRoot $fixture.Root -SearchFolders @($script:zipSourceSupplementary) -SupplementaryDatPath $collection.Dat -Interactive)
        Should -Invoke Read-PathWithBrowse -Times 1 -Exactly
    }

    It 'names the exact missing Chihiro files, where they belong and the folders searched, and offers no install; a skip changes and saves nothing' {
        # Mutation: leave the names, the destination or the searched folders out of the screen, or save a skipped answer -> this fails.
        $fixture = New-F387Root
        $collection = New-F387Collection -LeaveOut @('pc20_g24lc64.bin', 'fpr21042_m29w160et.bin')
        $warnings = @(Get-F132Warning -Fixture $fixture)
        Mock Read-PathWithBrowse { '' }
        $script:offered = $null
        Mock Read-TpmChoice { $script:offered = @($Choices); 'N' }
        $review = Invoke-TpmPrerequisiteReview -Warnings $warnings -TpRoot $fixture.Root -SearchFolders @($collection.Folder) -SupplementaryDatPath $collection.Dat -Interactive
        $review.FixedAny | Should -BeFalse
        $script:offered | Should -Not -Contain 'Y'
        $screenText = $script:screen -join "`n"
        $screenText | Should -Match ('Folders searched: ' + [regex]::Escape($collection.Folder))
        $screenText | Should -Match 'Missing: pc20_g24lc64\.bin \(not found in those folders; goes in .*EmuMediaBoard\\Chihiro\)'
        $screenText | Should -Match 'Missing: fpr21042_m29w160et\.bin'
        $screenText | Should -Not -Match 'Missing: ic10_g24lc64\.bin'
        Should -Invoke Save-Config -Times 0 -Exactly
        $script:zipSourceSupplementary | Should -BeNullOrEmpty
        (Test-Path -LiteralPath (Join-Path $fixture.Root 'cxbxr\TeknoParrot\EmuMediaBoard\Chihiro\ic10_g24lc64.bin')) | Should -BeFalse
    }

    It 'reports a file that is not the file the DAT lists as invalid by name, and still installs the good ones' {
        # Mutation: copy the changed file, or hide it in the report -> the file exists or the line is missing.
        $fixture = New-F387Root
        $collection = New-F387Collection -Change @('ic11_24lc024.bin')
        $warnings = @(Get-F132Warning -Fixture $fixture)
        Mock Read-PathWithBrowse { $collection.Folder }
        Mock Read-TpmChoice { 'Y' }
        Mock Read-TpmYesNo { 'N' }
        [void](Invoke-TpmPrerequisiteReview -Warnings $warnings -TpRoot $fixture.Root -SupplementaryDatPath $collection.Dat -Interactive)
        ($script:screen -join "`n") | Should -Match 'Invalid \(.*\): ic11_24lc024\.bin'
        (Test-Path -LiteralPath (Join-Path $fixture.Root 'cxbxr\TeknoParrot\EmuMediaBoard\Chihiro\ic11_24lc024.bin')) | Should -BeFalse
        (Test-Path -LiteralPath (Join-Path $fixture.Root 'cxbxr\TeknoParrot\EmuMediaBoard\Chihiro\ic10_g24lc64.bin')) | Should -BeTrue
    }

    It 'asks again when the saved Supplementary folder is gone, and says so' {
        # Mutation: trust a saved folder that does not exist -> no question and nothing found.
        $fixture = New-F387Root
        $collection = New-F387Collection
        $script:zipSourceSupplementary = Join-Path $TestDrive 'a-drive-that-is-not-there'
        Mock Read-PathWithBrowse { $collection.Folder }
        Mock Read-TpmChoice { 'Y' }
        $review = Invoke-TpmPrerequisiteReview -Warnings @(Get-F132Warning -Fixture $fixture) -TpRoot $fixture.Root -SearchFolders @($script:zipSourceSupplementary) -SupplementaryDatPath $collection.Dat -Interactive
        $review.FixedAny | Should -BeTrue
        ($script:screen -join "`n") | Should -Match 'saved Supplementary folder was not found'
        Should -Invoke Read-PathWithBrowse -Times 1 -Exactly
    }

    It 'never asks for a folder when the run is not interactive' {
        # Mutation: prompt without -Interactive (an unattended run would wait) -> the mock throws.
        $fixture = New-F387Root
        Mock Read-PathWithBrowse { throw 'must not prompt' }
        $review = Invoke-TpmPrerequisiteReview -Warnings @(Get-F132Warning -Fixture $fixture) -TpRoot $fixture.Root
        $review.Reviewed | Should -Be 1
        ($script:screen -join "`n") | Should -Match 'Folders searched: none'
    }
}
