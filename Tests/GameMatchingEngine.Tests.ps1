#Requires -Module Pester

# The shared game matching engine (issues #376 and #420 to #427). What a user sees or loses:
#   a game gets the right LaunchBox entry only when it is certain; a different year or number is a different game; the emulator named in a
#   title is not part of the game; a name that had to be worked out is never trusted alone; two games with one name are told apart by year and
#   developer, or the user decides; a game folder counts only when the Eggman list confirms it; firmware updaters and boards are not games;
#   the LaunchBox database file is only read.
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.
# The game list is a small SQLite file built under TestDrive. What this CANNOT prove: LaunchBox's real 400 MB game list. The evidence run
# (scripts\Invoke-TpmMatchEvidence.ps1) does that on a real install.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Matching engine tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:GmeFunctionFile = Join-Path $TestDrive 'tpm-gme-functions.ps1'
    [System.IO.File]::WriteAllText($script:GmeFunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:GmeFunctionFile
    $script:TitleTokenStopWords = [System.Collections.Generic.HashSet[string]]::new([string[]]@('the', 'of', 'a', 'an', 'and', 'vs', 'vs.', 'in', 'for', 'to'), [System.StringComparer]::OrdinalIgnoreCase)

    if (-not ('TpmTestGamesDbWriter' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class TpmTestGamesDbWriter {
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_open_v2(byte[] file, out IntPtr db, int flags, IntPtr vfs);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_close(IntPtr db);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_exec(IntPtr db, byte[] sql, IntPtr cb, IntPtr arg, IntPtr err);
    public static void Build(string path, string sql) {
        IntPtr db;
        if (sqlite3_open_v2(Encoding.UTF8.GetBytes(path + "\0"), out db, 6, IntPtr.Zero) != 0) throw new Exception("fixture open failed");
        try { if (sqlite3_exec(db, Encoding.UTF8.GetBytes(sql + "\0"), IntPtr.Zero, IntPtr.Zero, IntPtr.Zero) != 0) throw new Exception("fixture sql failed"); }
        finally { sqlite3_close(db); }
    }
}
'@
    }
    $script:GmeDb = Join-Path $TestDrive 'engine.db'
    [TpmTestGamesDbWriter]::Build($script:GmeDb, @"
CREATE TABLE Games (DatabaseID INTEGER, Name TEXT, Platform TEXT, ReleaseYear INTEGER, ReleaseDate TEXT, Developer TEXT, Publisher TEXT);
CREATE TABLE GameAlternateTitles (AlternateName TEXT, DatabaseID INTEGER, Region TEXT, AltNameCompareValue TEXT);
INSERT INTO Games VALUES (1, 'Too Spicy', 'Arcade', 2007, NULL, 'Sega', 'Sega');
INSERT INTO Games VALUES (2, 'Golden Tee 2020', 'Arcade', NULL, '2019-11-01 00:00:00', 'Incredible Technologies', 'Incredible Technologies');
INSERT INTO Games VALUES (3, 'Golden Tee LIVE 2022', 'Arcade', 2022, NULL, 'Incredible Technologies', 'Incredible Technologies');
INSERT INTO Games VALUES (4, 'Tekken 5', 'Arcade', 2004, NULL, 'Namco', 'Namco');
INSERT INTO Games VALUES (5, 'Virtua Fighter 5', 'Arcade', 2006, NULL, 'Sega AM2', 'Sega');
INSERT INTO Games VALUES (6, 'Cobra: The Arcade', 'Arcade', 2001, NULL, 'Namco', 'Namco');
INSERT INTO Games VALUES (7, 'Initial D Arcade Stage', 'Arcade', 2002, NULL, 'Sega', 'Sega');
INSERT INTO Games VALUES (8, 'Initial D Arcade Stage Ver. 2', 'Arcade', 2003, NULL, 'Sega', 'Sega');
INSERT INTO Games VALUES (9, 'Ninja Assault', 'Arcade', 2000, NULL, 'Namco', 'Namco');
INSERT INTO Games VALUES (10, 'Fantasy', 'Arcade', 1990, NULL, 'Someone', 'Someone');
INSERT INTO Games VALUES (11, 'Dino King Battle', 'Arcade', 2005, NULL, 'Sega', 'Sega');
INSERT INTO Games VALUES (12, 'Big Buck World', 'Arcade', 2010, NULL, 'Play Mechanix', 'Raw Thrills');
INSERT INTO Games VALUES (13, 'Big Buck Hunter', 'Arcade', 2000, NULL, 'Incredible Technologies', 'Strata');
INSERT INTO Games VALUES (14, 'Street Fighter Alpha: Warriors'' Dreams', 'Arcade', 1995, NULL, 'Capcom', 'Capcom');
INSERT INTO Games VALUES (15, 'Quiz Magic Academy', 'Arcade', 2003, NULL, 'Konami', 'Konami');
INSERT INTO Games VALUES (16, 'Samurai Shodown', 'Arcade', 1993, NULL, 'SNK', 'SNK');
INSERT INTO Games VALUES (17, 'Samurai Shodown', 'Taito Type X', 2019, NULL, 'SNK', 'SNK');
INSERT INTO Games VALUES (18, 'Frogger', 'Arcade', 1981, NULL, 'Konami Industry', 'Konami');
INSERT INTO Games VALUES (19, 'Frogger (Raw Thrills)', 'Arcade', 2011, NULL, 'Raw Thrills', 'Raw Thrills');
INSERT INTO Games VALUES (20, 'Wheel of Fortune', 'Arcade', 1990, NULL, 'GameTek', 'GameTek');
INSERT INTO Games VALUES (21, 'Wheel of Fortune (Raw Thrills)', 'Arcade', 2010, NULL, 'Play Mechanix', 'Play Mechanix');
INSERT INTO Games VALUES (22, 'Console Only Game', 'Sony Playstation 2', 2001, NULL, 'X', 'X');
INSERT INTO Games VALUES (23, 'Jurassic Park', 'Arcade', 1994, NULL, 'Sega', 'Sega');
INSERT INTO Games VALUES (24, 'Carrier Air Wing', 'Arcade', 1990, NULL, 'Capcom', 'Capcom');
INSERT INTO GameAlternateTitles VALUES ('U.S. Navy', 24, '', 'x');
"@)
    $script:GmeHashBefore = (Get-FileHash -LiteralPath $script:GmeDb -Algorithm SHA256).Hash
    $script:GmeIndex = Get-TpmGamesDbIndex -DbPath $script:GmeDb

    function Resolve-GmeCase {
        param([string]$MetadataName = '', [string]$ProfileName = '', [string[]]$DatNames = @(), [int]$Year = 0, [string]$Platform = '', [string]$Genre = '', [string]$Confirmed = '')
        $subject = New-TpmMatchSubject -Code 'case' -ProfileName $ProfileName -MetadataName $MetadataName -MetadataYear $Year -MetadataPlatform $Platform -MetadataGenre $Genre -DatNames $DatNames -ConfirmedDatName $Confirmed
        return (Resolve-TpmGameMatch -Index $script:GmeIndex -Subject $subject)
    }
}

Describe 'Game matching engine: certain only when the names say so' {
    BeforeEach { Mock Write-Log {} }

    It 'matches the same name however it is written, and says which names it used' {
        $result = Resolve-GmeCase -MetadataName 'TOO  spicy!' -DatNames @('2SPICY (Too Spicy)(1.00.00)(2007-02-15)[Sega Lindbergh Red][TP]') -Year 2007 -Platform 'SEGA Lindbergh Red'
        $result.Status | Should -Be 'Certain'
        $result.Match.Id | Should -Be '1'
        $result.Level | Should -Be 1
        $result.Evidence | Should -Match 'TeknoParrot'
    }

    It 'a different year or number is a different game: Golden Tee Live 2020 is not 2022, and 2021 is not in the list at all' {
        (Resolve-GmeCase -MetadataName 'Golden Tee Live 2022' -Year 2022).Match.Id | Should -Be '3'
        (Resolve-GmeCase -MetadataName 'Golden Tee Live 2020' -Year 2020 -Platform 'IT Nighthawk').Match.Id | Should -Be '2'
        (Resolve-GmeCase -MetadataName 'Golden Tee Live 2021' -Year 2021).Status | Should -Not -Be 'Certain'
        (Resolve-GmeCase -MetadataName 'Tekken 6.1' -Year 2007).Status | Should -Not -Be 'Certain'
    }

    It 'the emulator named in a title is not part of the game name' {
        $result = Resolve-GmeCase -MetadataName 'Virtua Fighter 5 (Version C) ElfLoader 2' -Year 2006 -Platform 'SEGA Lindbergh Yellow'
        $result.Status | Should -Be 'Certain'
        $result.Match.Id | Should -Be '5'
        (Resolve-GmeCase -MetadataName 'Too Spicy (ElfLoader 2)' -Year 2007).Match.Id | Should -Be '1'
    }

    It 'region, version and board-code tags are not part of the name, and a version that is its own game wins' {
        (Resolve-GmeCase -MetadataName 'Ninja Assault (Asia, NJA4 Ver.A)' -Year 2000 -Platform 'Sega NAOMI').Match.Id | Should -Be '9'
        (Resolve-GmeCase -MetadataName 'Cobra: The Arcade World (CBR2 Ver. B)' -Year 2005 -Platform 'Namco System 256').Match.Id | Should -Be '6'
        (Resolve-GmeCase -MetadataName 'Initial D Arcade Stage Ver. 2 (Japan) (GDS-0026)' -Year 2003 -Platform 'Sega NAOMI').Match.Id | Should -Be '8'
    }

    It 'a name that had to be worked out is not trusted alone, but the hardware maker backs it up' {
        $alone = Resolve-GmeCase -MetadataName 'Quiz Magic Academy 1'
        $alone.Status | Should -Be 'Ambiguous'
        $alone.Match.Id | Should -Be '15'
        $backed = Resolve-GmeCase -MetadataName 'Quiz Magic Academy 1' -Platform 'Konami System 573'
        $backed.Status | Should -Be 'Certain'
        $backed.Level | Should -Be 3
        # An alternate name in the game list counts as a worked-out name too.
        (Resolve-GmeCase -MetadataName 'U.S. Navy (Japan 901012)' -Platform 'Capcom CPS1').Match.Id | Should -Be '24'
        (Resolve-GmeCase -MetadataName 'Street Fighter Zero (Asia 950627)' -Platform 'Capcom CPS1').Match.Id | Should -Be '14'
    }

    It 'a close name is only a suggestion for the user, never a match' {
        $near = Resolve-GmeCase -MetadataName 'Fantasy Soccer' -Year 2018
        $near.Status | Should -Not -Be 'Certain'
        $longer = Resolve-GmeCase -MetadataName 'Dino King Battle: King of Jurassic'
        $longer.Status | Should -Be 'Ambiguous'
        @($longer.Options)[0].Id | Should -Be '11'
        (Resolve-GmeCase -MetadataName 'Qwerty Asdf Zxcv Lkjh').Status | Should -Be 'NoMatch'
    }

    It 'two sources that name different games are not guessed' {
        $result = Resolve-GmeCase -MetadataName 'Big Buck World' -DatNames @('Big Buck Hunter (2000)[Incredible Technologies][TP]')
        $result.Status | Should -Be 'Ambiguous'
        @($result.Options).Count | Should -Be 2
    }

    It 'the list name of one game from every source gives a certain match, and a title typed in LaunchBox never argues against them' {
        $subject = New-TpmMatchSubject -Code 'bbh' -MetadataName 'Big Buck World' -DatNames @('Big Buck World (2010)[Raw Thrills][TP]') -HintName 'Big Buck Hunter'
        $result = Resolve-TpmGameMatch -Index $script:GmeIndex -Subject $subject
        $result.Status | Should -Be 'Certain'
        $result.Match.Id | Should -Be '12'
        $result.Reason | Should -Match '2 sources'
    }

    It 'a name that is only a region is not a name' {
        (Resolve-GmeCase -MetadataName 'World').Status | Should -Be 'NoMatch'
    }
}

Describe 'Game matching engine: games that share a name' {
    BeforeEach { Mock Write-Log {} }

    It 'the release year picks between two games with one name, even on another platform' {
        (Resolve-GmeCase -MetadataName 'Samurai Shodown' -Year 1993 -Platform 'SNK Neo Geo MVS').Match.Id | Should -Be '16'
        (Resolve-GmeCase -MetadataName 'Samurai Shodown' -Year 2019 -Platform 'Taito NESiCAxLive2').Match.Id | Should -Be '17'
    }

    It 'the developer picks the right game when a qualified twin exists; with no developer to tell them apart the user decides' {
        $frogger = Resolve-GmeCase -MetadataName 'Frogger' -Year 2011 -Platform 'Raw Thrills PC Based'
        $frogger.Status | Should -Be 'Certain'
        $frogger.Match.Id | Should -Be '19'
        (Resolve-GmeCase -MetadataName 'Frogger' -Year 1981 -Platform 'Konami PC Based').Match.Id | Should -Be '18'
        $wheel = Resolve-GmeCase -MetadataName 'Wheel of Fortune' -Year 2015 -Platform 'ICE PC'
        $wheel.Status | Should -Be 'Ambiguous'
        @($wheel.Options).Count | Should -Be 2
    }

    It 'a developer and a year that both clash mean it may be another game with the same name' {
        $park = Resolve-GmeCase -MetadataName 'Jurassic Park' -Year 2015 -Platform 'Raw Thrills Linux PC'
        $park.Status | Should -Be 'Ambiguous'
        $park.Reason | Should -Match 'far apart'
    }
}

Describe 'Game matching engine: what a profile is' {
    BeforeEach { Mock Write-Log {} }

    It 'firmware updaters, drive checkers, controllers and boards are not games, and a game on a development board is' {
        (Resolve-GmeCase -MetadataName 'Naomi DIMM Firmware Updater (2.13) (GDS-0023A)').Status | Should -Be 'NotGame'
        (Resolve-GmeCase -MetadataName 'World Club Champion Football 2002-2003 Drive Checker').Status | Should -Be 'NotGame'
        (Resolve-GmeCase -MetadataName 'AS-1 Controller').Status | Should -Be 'NotGame'
        (Resolve-GmeCase -MetadataName 'Anything' -Genre 'Utility / Hopper Board').Status | Should -Be 'NotGame'
        (Resolve-GmeCase -MetadataName "Dragon's Heaven (development board)").Status | Should -Not -Be 'NotGame'
    }

    It 'a game with no list match still gets a clean readable title, without region, version or emulator notes' {
        $result = Resolve-GmeCase -MetadataName 'Zzzz Qqqq (Japan, ZQ1 Ver.A) ElfLoader 2'
        $result.Status | Should -Be 'NoMatch'
        $result.Title | Should -Be 'Zzzz Qqqq'
        (Resolve-GmeCase -ProfileName 'Nameless Hero v1.2.3').Title | Should -Be 'Nameless Hero'
    }

    It 'the year and developer to fill in come from the list when the match is certain, otherwise from the Eggman list and TeknoParrot' {
        $certain = Resolve-GmeCase -MetadataName 'Tekken 5' -Year 2005 -Platform 'Namco System 246'
        $certain.Facts.Year | Should -Be 2004
        $certain.Facts.Developer | Should -Be 'Namco'
        $none = Resolve-GmeCase -MetadataName 'Zzzz Qqqq' -Year 2012 -Platform 'Taito Type X2'
        $none.Facts.Year | Should -Be 2012
        $none.Facts.Developer | Should -Be 'Taito'
    }

    It 'reads the title, other names, year and hardware out of an Eggman game name' {
        $parsed = ConvertFrom-TpmDatGameName 'Aero Fighters 2 (Sonic Wings 2) (1994)[SNK Neo Geo MVS][TP]'
        $parsed.Title | Should -Be 'Aero Fighters 2'
        $parsed.AltTitles | Should -Contain 'Sonic Wings 2'
        $parsed.Year | Should -Be 1994
        $parsed.Hardware | Should -Be 'SNK Neo Geo MVS'
        $parsed.Maker | Should -Be 'SNK'
        $dated = ConvertFrom-TpmDatGameName 'Virtua Fighter 5 Final Showdown (1.000 Ver B Offline)(2015-03-25)(JPN)[Sega Lindbergh Silver][TP]'
        $dated.Title | Should -Be 'Virtua Fighter 5 Final Showdown'
        $dated.Year | Should -Be 2015
        @($dated.AltTitles).Count | Should -Be 0
    }
}

Describe 'Game matching engine: the game folder is a source only when the Eggman list confirms it' {
    BeforeEach { Mock Write-Log {} }

    It 'accepts the folder when its name, its profile code and the file the profile starts all agree with the list' {
        $listName = 'Big Buck World (2010)[Raw Thrills][TP]'
        $datIndex = @{ 'bigbuckworld' = [pscustomobject]@{ ProfileCode = 'BBHWorld'; ProfileCode2 = ''; Executable = 'bin\bbh.exe'; OriginalName = $listName; Alternates = (New-Object System.Collections.Generic.List[object]) } }
        Get-TpmConfirmedDatName -Code 'BBHWorld' -GamePath "E:\Games\$listName\bin\bbh.exe" -DatIndex $datIndex | Should -Be $listName
        # Another profile code, another file, or a folder the list does not know: not confirmed.
        Get-TpmConfirmedDatName -Code 'SomethingElse' -GamePath "E:\Games\$listName\bin\bbh.exe" -DatIndex $datIndex | Should -Be ''
        Get-TpmConfirmedDatName -Code 'BBHWorld' -GamePath "E:\Games\$listName\other.exe" -DatIndex $datIndex | Should -Be ''
        Get-TpmConfirmedDatName -Code 'BBHWorld' -GamePath 'E:\Games\Big Buck World (2011)[Raw Thrills][TP]\bin\bbh.exe' -DatIndex $datIndex | Should -Be ''
        Get-TpmConfirmedDatName -Code 'BBHWorld' -GamePath 'E:\Games\just a folder\bbh.exe' -DatIndex $datIndex | Should -Be ''
    }

    It 'a confirmed folder picks the one list game of a code that has several, and an unconfirmed folder does not' {
        $both = @('Wangan Midnight Maximum Tune 3 (EXP)(2007)[Namco N2][TP]', 'Wangan Midnight Maximum Tune 3 (JPN)(2007)[Namco N2][TP]')
        $subject = New-TpmMatchSubject -Code 'wmmt3' -DatNames $both -ConfirmedDatName $both[1]
        $subject.FolderConfirmed | Should -BeTrue
        @($subject.Names | Where-Object { $_.Source -like 'Eggman list (game folder confirmed)*' }).Count | Should -Be 1
        (New-TpmMatchSubject -Code 'wmmt3' -DatNames $both).FolderConfirmed | Should -BeFalse
    }

    It 'reads a profile, TeknoParrot metadata and the Eggman list files into one subject' {
        $tp = Join-Path $TestDrive 'TeknoParrotEngine'
        New-Item -ItemType Directory -Path (Join-Path $tp 'Metadata') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tp 'GameProfiles') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $tp 'Metadata\TooSpicy.json'), '{"game_name":"Too Spicy","game_genre":"Shooter","platform":"SEGA Lindbergh Red","release_year":"2007"}')
        [System.IO.File]::WriteAllText((Join-Path $tp 'GameProfiles\TooSpicy.xml'), '<GameProfile><GameNameInternal>Too Spicy (ElfLoader 2)</GameNameInternal><GamePath></GamePath></GameProfile>')
        $datByCode = @{ 'toospicy' = (New-Object System.Collections.Generic.List[object]) }
        [void]$datByCode['toospicy'].Add([pscustomobject]@{ OriginalName = '2SPICY (Too Spicy)(1.00.00)(2007-02-15)[Sega Lindbergh Red][TP]' })
        $subject = Get-TpmProfileMatchSubject -Code 'TooSpicy' -ProfilePath (Join-Path $tp 'GameProfiles\TooSpicy.xml') -TpRoot $tp -DatByCode $datByCode
        $subject.Year | Should -Be 2007
        $subject.Maker | Should -Be 'Sega'
        (Resolve-TpmGameMatch -Index $script:GmeIndex -Subject $subject).Match.Id | Should -Be '1'
        # An unsafe code never reads outside the metadata folder.
        (Get-TpmTeknoParrotMetadataFacts -TpRoot $tp -ProfileCode '..\..\Secret').Name | Should -Be ''
    }

    It 'only reads the game list: the file is byte-for-byte the same afterwards, and a release date fills in a missing year' {
        $index = Get-TpmGamesDbIndex -DbPath $script:GmeDb
        $index.ById['2'].Year | Should -Be 2019
        (Get-FileHash -LiteralPath $script:GmeDb -Algorithm SHA256).Hash | Should -Be $script:GmeHashBefore
    }
}
