#Requires -Module Pester

# LaunchBox Games Database links for TeknoParrot games that have no ID yet.
# What a user sees or loses: the game name is read from TeknoParrot's own metadata (no user profile needed), an exact name gets
# its ID without asking, a close name is only applied after approval, a name the user typed stays, games that already have an ID
# are never touched, other emulators' games are never touched, and the preview changes nothing on disk.
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.
# The game list is a tiny SQLite file and the LaunchBox folder is a small fake, both built under TestDrive.
# What this CANNOT prove: LaunchBox's real 400 MB game list, or LaunchBox itself reading the saved IDs.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'LaunchBox link tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:IdlFunctionFile = Join-Path $TestDrive 'tpm-idl-functions.ps1'
    [System.IO.File]::WriteAllText($script:IdlFunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:IdlFunctionFile
    $script:LaunchBoxGameSkeletonFields = [ordered]@{
        ID=''; Title=''; Platform=''; Emulator=''; ApplicationPath=''; CommandLine=''
        DateAdded=''; DateModified=''; Favorite='false'; Completed='false'; Hide='false'
        PlayCount='0'; PlayTime='0'; Notes=''
    }
    $script:LaunchBoxGameIdentityFields = @('ID','Title','Platform','Emulator','ApplicationPath','CommandLine','DateAdded','DateModified')
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
    $dbPath = Join-Path $TestDrive 'links.db'
    [TpmTestGamesDbWriter]::Build($dbPath, @"
CREATE TABLE Games (DatabaseID INTEGER, Name TEXT, Platform TEXT);
CREATE TABLE GameAlternateTitles (AlternateName TEXT, DatabaseID INTEGER, Region TEXT, AltNameCompareValue TEXT);
INSERT INTO Games VALUES (11, 'Too Spicy', 'Arcade');
INSERT INTO Games VALUES (12, 'PowerPutt Home Edition', 'Arcade');
INSERT INTO Games VALUES (13, 'Harley Davidson King of the Road', 'Arcade');
"@)
    $script:IdlIndex = Get-TpmGamesDbIndex -DbPath $dbPath

    # A fake TeknoParrot folder (metadata only) and a fake LaunchBox folder.
    $script:IdlTp = Join-Path $TestDrive 'TeknoParrot'
    New-Item -ItemType Directory -Path (Join-Path $script:IdlTp 'Metadata') -Force | Out-Null
    $meta = @{ TooSpicy = 'Too Spicy'; PowerPuttLive2013 = 'PowerPuttLive'; Harley = 'Harley-Davidson: King of the Road'; Handmade = 'Too Spicy' }
    foreach ($code in $meta.Keys) {
        [System.IO.File]::WriteAllText((Join-Path $script:IdlTp "Metadata\$code.json"), ('{{"game_name":"{0}"}}' -f $meta[$code]))
    }
    $script:IdlLb = Join-Path $TestDrive 'LaunchBox'
    New-Item -ItemType Directory -Path (Join-Path $script:IdlLb 'Data\Platforms') -Force | Out-Null
    function New-IdlGame {
        param([string]$Id, [string]$Title, [string]$Code, [string]$Emulator = 'emu-tp', [string]$DbId = '')
        $dbXml = if ($DbId) { "<DatabaseID>$DbId</DatabaseID>" } else { '' }
        return "<Game><ID>$Id</ID><Title>$Title</Title><Emulator>$Emulator</Emulator><ApplicationPath>Emulators\TeknoParrot\UserProfiles\$Code.xml</ApplicationPath>$dbXml</Game>"
    }
    $games = @(
        (New-IdlGame 'g1' 'Too Spicy' 'TooSpicy'),
        (New-IdlGame 'g2' 'PowerPuttLive2013' 'PowerPuttLive2013'),
        (New-IdlGame 'g3' 'Harley-Davidson: King of the Road' 'Harley' -DbId '99'),
        (New-IdlGame 'g4' 'My Own Name' 'Handmade'),
        (New-IdlGame 'g5' 'Too Spicy' 'TooSpicy' -Emulator 'emu-other'),
        (New-IdlGame 'g6' 'Totally Unknown' 'NoSuchCode'),
        (New-IdlGame 'g7' 'tooSPICY' 'TooSpicy'),
        (New-IdlGame 'g8' 'handmade' 'Handmade')
    ) -join ''
    $script:IdlPlatformPath = Join-Path $script:IdlLb 'Data\Platforms\TeknoParrot.xml'
    [System.IO.File]::WriteAllText($script:IdlPlatformPath, ('<?xml version="1.0" standalone="yes"?><LaunchBox>{0}</LaunchBox>' -f $games), (New-Object System.Text.UTF8Encoding $false))
    $script:IdlPlatformHash = (Get-FileHash -LiteralPath $script:IdlPlatformPath -Algorithm SHA256).Hash
}

Describe 'LaunchBox Games Database links for TeknoParrot games' {
    BeforeEach { Mock Write-Log {} }

    It 'reads the game name from the metadata, and returns nothing for a missing file or an unsafe code' {
        Get-TpmTeknoParrotGameName -TpRoot $script:IdlTp -ProfileCode 'TooSpicy' | Should -Be 'Too Spicy'
        Get-TpmTeknoParrotGameName -TpRoot $script:IdlTp -ProfileCode 'NoSuchCode' | Should -Be ''
        Get-TpmTeknoParrotGameName -TpRoot $script:IdlTp -ProfileCode '..\..\Secret' | Should -Be ''
    }

    It 'links an exact name without asking, and leaves close matches, ID-holders, other emulators and unknowns alone until approved' {
        $plan = New-TpmLaunchBoxIdLinkPlan -LbRoot $script:IdlLb -TpRoot $script:IdlTp -EmulatorId 'emu-tp' -PlatformNames @('TeknoParrot') -Index $script:IdlIndex
        $byId = @{}; foreach ($item in $plan.Items) { $byId[$item.GameId] = $item }
        $byId.Keys.Count | Should -Be 6
        $byId['g1'].Status | Should -Be 'Sure'
        $byId['g1'].Applied | Should -BeTrue
        $byId['g1'].MatchId | Should -Be '11'
        $byId['g2'].Status | Should -Be 'Check'
        $byId['g2'].Applied | Should -BeFalse
        $byId['g2'].MatchId | Should -Be '12'
        $byId['g6'].Status | Should -Be 'None'
        $byId.ContainsKey('g3') | Should -BeFalse
        $byId.ContainsKey('g5') | Should -BeFalse
        $xml = $plan.Plans[0].Document
        $xml.SelectSingleNode('/LaunchBox/Game[ID="g1"]/DatabaseID').InnerText | Should -Be '11'
        $xml.SelectSingleNode('/LaunchBox/Game[ID="g2"]/DatabaseID') | Should -BeNullOrEmpty
        $xml.SelectSingleNode('/LaunchBox/Game[ID="g3"]/DatabaseID').InnerText | Should -Be '99'
        $xml.SelectSingleNode('/LaunchBox/Game[ID="g5"]/DatabaseID') | Should -BeNullOrEmpty
    }

    It 'applies a close match only for a game the user approved, and uses the official name only when the title was not typed by hand' {
        $plan = New-TpmLaunchBoxIdLinkPlan -LbRoot $script:IdlLb -TpRoot $script:IdlTp -EmulatorId 'emu-tp' -PlatformNames @('TeknoParrot') -Index $script:IdlIndex -ApprovedGameIds @('g2')
        $xml = $plan.Plans[0].Document
        $xml.SelectSingleNode('/LaunchBox/Game[ID="g2"]/DatabaseID').InnerText | Should -Be '12'
        # The title there was only the profile code, so the approved official name replaces it.
        $xml.SelectSingleNode('/LaunchBox/Game[ID="g2"]/Title').InnerText | Should -Be 'PowerPutt Home Edition'
        # A hand-typed title keeps its name even when the ID is linked.
        $xml.SelectSingleNode('/LaunchBox/Game[ID="g4"]/Title').InnerText | Should -Be 'My Own Name'
        $xml.SelectSingleNode('/LaunchBox/Game[ID="g4"]/DatabaseID').InnerText | Should -Be '11'
    }

    It 'writes nothing while planning, and the preview lines are plain' {
        $plan = New-TpmLaunchBoxIdLinkPlan -LbRoot $script:IdlLb -TpRoot $script:IdlTp -EmulatorId 'emu-tp' -PlatformNames @('TeknoParrot') -Index $script:IdlIndex
        (Get-FileHash -LiteralPath $script:IdlPlatformPath -Algorithm SHA256).Hash | Should -Be $script:IdlPlatformHash
        $lines = @(Format-TpmLaunchBoxIdLinkLine -Plan $plan)
        ($lines -join "`n") | Should -Match 'Waiting for your approval'
        ($lines -join "`n") | Should -Match 'no match found'
        (Format-TpmLaunchBoxIdLinkTitle -Plan $plan -Preview) | Should -Match '^Preview: 4 sure matches'
        ($lines -join "`n") | Should -Match 'My Own Name: will be linked to Too Spicy\. The name in LaunchBox stays as it is\.'
    }

    It 'replaces a title that is empty, the profile code, or the same name with other capitals, but keeps any other name' {
        $plan = New-TpmLaunchBoxIdLinkPlan -LbRoot $script:IdlLb -TpRoot $script:IdlTp -EmulatorId 'emu-tp' -PlatformNames @('TeknoParrot') -Index $script:IdlIndex
        $xml = $plan.Plans[0].Document
        $xml.SelectSingleNode('/LaunchBox/Game[ID="g7"]/Title').InnerText | Should -Be 'Too Spicy'
        $xml.SelectSingleNode('/LaunchBox/Game[ID="g8"]/Title').InnerText | Should -Be 'Too Spicy'
        $xml.SelectSingleNode('/LaunchBox/Game[ID="g4"]/Title').InnerText | Should -Be 'My Own Name'
    }

    It 'says so when there is nothing to link' {
        $empty = [pscustomobject]@{ Plans = @(); Items = @() }
        Format-TpmLaunchBoxIdLinkTitle -Plan $empty | Should -Match 'already has a Games Database ID'
    }
}

# Layered matching: what a user sees. A game is linked without asking only when the names from every source agree exactly;
# a name that only looks close always waits for the user; sources that point at different games are never guessed.
Describe 'LaunchBox Games Database layered matching' {
    BeforeAll {
        $wideDb = Join-Path $TestDrive 'wide.db'
        [TpmTestGamesDbWriter]::Build($wideDb, @"
CREATE TABLE Games (DatabaseID INTEGER, Name TEXT, Platform TEXT, ReleaseYear INTEGER, Developer TEXT, Publisher TEXT);
CREATE TABLE GameAlternateTitles (AlternateName TEXT, DatabaseID INTEGER, Region TEXT, AltNameCompareValue TEXT);
INSERT INTO Games VALUES (21, 'Big Buck World', 'Arcade', 2010, 'Play Mechanix', 'Raw Thrills');
INSERT INTO Games VALUES (22, 'Big Buck Hunter', 'Arcade', 2000, 'Incredible Technologies', 'Strata');
INSERT INTO Games VALUES (24, 'Densha de GO!!', 'Arcade', 1997, 'Taito', 'Taito');
INSERT INTO Games VALUES (23, 'Densha de GO!', 'Arcade', 1996, 'Taito', 'Taito');
INSERT INTO Games VALUES (25, 'Fantasy', 'Arcade', 1990, 'Someone', 'Someone');
INSERT INTO Games VALUES (26, 'Twin Name', 'Arcade', 1999, 'A', 'A');
INSERT INTO Games VALUES (27, 'Twin Name', 'Arcade', 2003, 'B', 'B');
INSERT INTO Games VALUES (30, 'Tom and Jerry 2', 'Arcade', 1998, 'C', 'C');
INSERT INTO Games VALUES (31, 'Samurai Shodown', 'Arcade', 1993, 'SNK', 'SNK');
INSERT INTO Games VALUES (32, 'Samurai Shodown (2019)', 'Arcade', 2019, 'SNK', 'SNK');
INSERT INTO Games VALUES (33, 'Mah Jong Club Ver.3', 'Arcade', 2001, 'D', 'D');
INSERT INTO Games VALUES (34, 'Hero', 'Arcade', 1985, 'E', 'E');
INSERT INTO Games VALUES (35, 'Mega Racer', 'Arcade', 2002, 'F', 'F');
INSERT INTO Games VALUES (36, 'Golden Tee LIVE 2019', 'Arcade', 2019, 'Incredible Technologies', 'Incredible Technologies');
INSERT INTO Games VALUES (37, 'Golden Tee LIVE 2022', 'Arcade', 2022, 'Incredible Technologies', 'Incredible Technologies');
INSERT INTO Games VALUES (38, 'Street Fighter Alpha: Warriors'' Dreams', 'Arcade', 1995, 'Capcom', 'Capcom');
INSERT INTO Games VALUES (39, 'Street Fighter Zero 3', 'Arcade', 1998, 'Capcom', 'Capcom');
INSERT INTO Games VALUES (40, 'Street Smart', 'Arcade', 1989, 'SNK', 'SNK');
INSERT INTO Games VALUES (41, 'Final Fight', 'Arcade', 1989, 'Capcom', 'Capcom');
INSERT INTO Games VALUES (42, 'Street Fighter V: Type Arcade', 'Arcade', 2019, 'Capcom', 'Capcom');
INSERT INTO Games VALUES (43, 'Dino King Battle', 'Arcade', 2005, 'Sega', 'Sega');
INSERT INTO Games VALUES (44, 'Brave Firefighters: Real Life Heroes', 'Arcade', 2009, 'Namco', 'Namco');
INSERT INTO Games VALUES (45, 'Hatsune Miku: Project DIVA Arcade', 'Arcade', 2012, 'Sega', 'Sega');
INSERT INTO Games VALUES (46, 'Cobra: The Arcade', 'Arcade', 2001, 'Namco', 'Namco');
INSERT INTO Games VALUES (47, 'Initial D Arcade Stage', 'Arcade', 2002, 'Sega', 'Sega');
INSERT INTO Games VALUES (48, 'Mario Kart Arcade GP DX', 'Arcade', 2013, 'Namco', 'Namco');
INSERT INTO Games VALUES (49, 'Virtua Striker 4 Ver.2006', 'Arcade', 2006, 'Sega', 'Sega');
INSERT INTO Games VALUES (50, 'Tekken 5', 'Arcade', 2004, 'Namco', 'Namco');
INSERT INTO Games VALUES (51, 'Initial D Arcade Stage Ver. 2', 'Arcade', 2003, 'Sega', 'Sega');
INSERT INTO Games VALUES (52, 'Nitroplus Blasterz: Heroines Infinite Duel', 'Arcade', 2015, 'Examu', 'Examu');
INSERT INTO Games VALUES (53, 'Marvel Vs Capcom 2', 'Arcade', 2000, 'Capcom', 'Capcom');
INSERT INTO Games VALUES (54, 'GP World', 'Arcade', 1984, 'Sega', 'Sega');
"@)
        $script:WideIndex = Get-TpmGamesDbIndex -DbPath $wideDb
        $script:WideTp = Join-Path $TestDrive 'TeknoParrotWide'
        New-Item -ItemType Directory -Path (Join-Path $script:WideTp 'Metadata') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:WideTp 'UserProfiles') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $script:WideTp 'Metadata\BBHWorld.json'), '{"game_name":"Big Buck Hunter World","release_year":"2010","platform":"Raw Thrills"}')
        [System.IO.File]::WriteAllText((Join-Path $script:WideTp 'UserProfiles\BBHWorld.xml'), '<GameProfile><GamePath>C:\Games\Big Buck World (2010)[Raw Thrills][TP]\game.exe</GamePath></GameProfile>')
        $script:WideLb = Join-Path $TestDrive 'LaunchBoxWide'
        New-Item -ItemType Directory -Path (Join-Path $script:WideLb 'Data\Platforms') -Force | Out-Null
        $xml = '<?xml version="1.0" standalone="yes"?><LaunchBox><Game><ID>w1</ID><Title>Big Buck Hunter World</Title><Emulator>emu-tp</Emulator><ApplicationPath>Emulators\TeknoParrot\UserProfiles\BBHWorld.xml</ApplicationPath></Game></LaunchBox>'
        [System.IO.File]::WriteAllText((Join-Path $script:WideLb 'Data\Platforms\TeknoParrot.xml'), $xml, (New-Object System.Text.UTF8Encoding $false))
    }
    BeforeEach { Mock Write-Log {} }

    It 'keeps year, developer and publisher in the index, and still reads a game list that has none of them' {
        $script:WideIndex.ByName.Item((ConvertTo-TpmGamesDbKey 'Big Buck World'))[0].Year | Should -Be 2010
        $script:WideIndex.ByName.Item((ConvertTo-TpmGamesDbKey 'Big Buck World'))[0].Developer | Should -Be 'Play Mechanix'
        $script:IdlIndex.ByName.Item((ConvertTo-TpmGamesDbKey 'Too Spicy'))[0].Year | Should -Be 0
    }

    It 'cleans notes, versions and the NESiCAxLive tag off a title' {
        Get-TpmMatchCleanTitle 'Homura for NESiCAxLive' | Should -Be 'Homura'
        Get-TpmMatchCleanTitle 'Beastorizer (USA, Sep 22 1997)' | Should -Be 'Beastorizer'
        Get-TpmMatchCleanTitle 'Some Game v1.2.3' | Should -Be 'Some Game'
    }

    It 'tells Big Buck Hunter from Big Buck World: one close name is still counted as a close match, not dropped' {
        $plan = New-TpmLaunchBoxIdLinkPlan -LbRoot $script:WideLb -TpRoot $script:WideTp -EmulatorId 'emu-tp' -PlatformNames @('TeknoParrot') -Index $script:WideIndex
        $plan.Items.Count | Should -Be 1
        $plan.Items[0].Status | Should -Be 'Check'
        $plan.Items[0].MatchId | Should -Be '21'
        $plan.Items[0].Applied | Should -BeFalse
        $plan.Items[0].Evidence | Should -Match 'TeknoParrot'
    }

    It 'links it without asking when the Eggman list confirms the same game by its exact name' {
        $datIndex = @{ 'bigbuckworld' = [pscustomobject]@{ ProfileCode = 'BBHWorld'; OriginalName = 'Big Buck World (2010)[Raw Thrills][TP]' } }
        $plan = New-TpmLaunchBoxIdLinkPlan -LbRoot $script:WideLb -TpRoot $script:WideTp -EmulatorId 'emu-tp' -PlatformNames @('TeknoParrot') -Index $script:WideIndex -DatIndex $datIndex
        $plan.Items[0].Status | Should -Be 'Sure'
        $plan.Items[0].MatchId | Should -Be '21'
        $plan.Items[0].Applied | Should -BeTrue
        $plan.Items[0].Evidence | Should -Match 'Eggman list'
    }

    It 'prefers the exact spelling when two games share one normalized name' {
        $pick = Get-TpmGamesDbPick -Index $script:WideIndex -Title 'Densha de GO!!'
        $pick.Kind | Should -Be 'Exact'
        $pick.Id | Should -Be '24'
        (Get-TpmGamesDbPick -Index $script:WideIndex -Title 'Densha de GO!').Id | Should -Be '23'
    }

    It 'never calls a shorter name the same game: Fantasy Soccer is not Fantasy' {
        $result = Resolve-TpmGamesDbMatch -Index $script:WideIndex -Names @([pscustomobject]@{ Source = 'TeknoParrot'; Name = 'Fantasy Soccer' }) -Year 2018
        $result.Status | Should -Not -Be 'Sure'
    }

    It 'does not guess between two games with the same name' {
        $result = Resolve-TpmGamesDbMatch -Index $script:WideIndex -Names @([pscustomobject]@{ Source = 'TeknoParrot'; Name = 'Twin Name' })
        $result.Status | Should -Be 'Check'
    }

    It 'asks when two sources name different games, and does nothing when no source has a name' {
        $names = @([pscustomobject]@{ Source = 'TeknoParrot'; Name = 'Big Buck World' }, [pscustomobject]@{ Source = 'Eggman list'; Name = 'Big Buck Hunter' })
        (Resolve-TpmGamesDbMatch -Index $script:WideIndex -Names $names).Status | Should -Be 'Check'
        (Resolve-TpmGamesDbMatch -Index $script:WideIndex -Names @()).Status | Should -Be 'None'
        (Resolve-TpmGamesDbMatch -Index $script:WideIndex -Names @([pscustomobject]@{ Source = 'TeknoParrot'; Name = 'Zzzz Qqqq' })).Status | Should -Be 'None'
    }

    It 'does not let a title typed in LaunchBox argue against TeknoParrot and the Eggman list, but uses it when nothing else has a name' {
        $agree = @(
            [pscustomobject]@{ Source = 'TeknoParrot'; Name = 'Big Buck World' },
            [pscustomobject]@{ Source = 'Eggman list'; Name = 'Big Buck World' },
            [pscustomobject]@{ Source = 'LaunchBox title'; Name = 'Big Buck Hunter'; Fallback = $true }
        )
        $result = Resolve-TpmGamesDbMatch -Index $script:WideIndex -Names $agree
        $result.Status | Should -Be 'Sure'
        $result.Match.Id | Should -Be '21'
        $only = Resolve-TpmGamesDbMatch -Index $script:WideIndex -Names @([pscustomobject]@{ Source = 'LaunchBox title'; Name = 'Big Buck World'; Fallback = $true })
        $only.Status | Should -Be 'Sure'
        $only.Match.Id | Should -Be '21'
    }

    It 'sets aside the one source that disagrees when the others agree exactly, and still asks on a one-against-one tie' {
        $names = @(
            [pscustomobject]@{ Source = 'TeknoParrot'; Name = 'Big Buck World' },
            [pscustomobject]@{ Source = 'Eggman list'; Name = 'Big Buck World' },
            [pscustomobject]@{ Source = 'MAME list'; Name = 'Big Buck Hunter' }
        )
        $result = Resolve-TpmGamesDbMatch -Index $script:WideIndex -Names $names
        $result.Status | Should -Be 'Sure'
        $result.Match.Id | Should -Be '21'
        $result.Evidence | Should -Match 'Set aside'
        $result.Evidence | Should -Match 'MAME list'
        $tie = Resolve-TpmGamesDbMatch -Index $script:WideIndex -Names @($names[0], $names[2])
        $tie.Status | Should -Be 'Check'
    }

    It 'treats Roman numerals, ampersands and the word "and" as the same spelling' {
        $result = Resolve-TpmGamesDbMatch -Index $script:WideIndex -Names @([pscustomobject]@{ Source = 'TeknoParrot'; Name = 'Tom & Jerry II' })
        $result.Status | Should -Be 'Sure'
        $result.Match.Id | Should -Be '30'
    }

    It 'picks between a game and its year-tagged twin by release year' {
        (Get-TpmGamesDbPick -Index $script:WideIndex -Title 'Samurai Shodown' -Year 2019).Id | Should -Be '32'
        (Get-TpmGamesDbPick -Index $script:WideIndex -Title 'Samurai Shodown' -Year 1993).Id | Should -Be '31'
    }

    It 'finds a name with a version suffix exactly as written' {
        $pick = Get-TpmGamesDbPick -Index $script:WideIndex -Title 'Mah Jong Club Ver.3'
        $pick.Kind | Should -Be 'Exact'
        $pick.Id | Should -Be '33'
    }

    It 'tolerates an Arcade or Edition tail, and does not use a one-word side of a slash name' {
        (Get-TpmGamesDbPick -Index $script:WideIndex -Title 'Mega Racer Arcade Edition').Id | Should -Be '35'
        (Get-TpmGamesDbPick -Index $script:WideIndex -Title 'Hero / Zork').Id | Should -Not -Be '34'
    }

    It 'gives up on a hopeless near match instead of guessing' {
        (Resolve-TpmGamesDbMatch -Index $script:WideIndex -Names @([pscustomobject]@{ Source = 'TeknoParrot'; Name = 'Qwerty Asdf Zxcv Lkjh' })).Status | Should -Be 'None'
    }

    It 'knows firmware updaters, drive checkers and boards are not games' {
        Test-TpmNonGameTitle -Title 'NAOMI Firmware Update' | Should -BeTrue
        Test-TpmNonGameTitle -Title 'Hopper Board' | Should -BeTrue
        Test-TpmNonGameTitle -Title 'Big Buck World' | Should -BeFalse
    }

    It 'the title step used when adding games asks the same engine: spelling differences and the MAME name count' {
        $spelling = Resolve-TpmGameTitle -Index $script:WideIndex -Title 'Tom & Jerry II'
        $spelling.Status | Should -Be 'Matched'
        $spelling.Match.Id | Should -Be '30'
        $mame = Resolve-TpmGameTitle -Index $script:WideIndex -Title 'Zzzz Qqqq' -MameName 'Mah Jong Club Ver.3'
        $mame.Status | Should -Be 'Matched'
        $mame.Match.Id | Should -Be '33'
    }

    It 'the title step never applies a close name, and keeps the profile internal name as a last-resort hint only' {
        $near = Resolve-TpmGameTitle -Index $script:WideIndex -Title 'Fantasy Soccer'
        $near.Status | Should -Not -Be 'Matched'
        $near.Match | Should -BeNullOrEmpty
        $hint = Resolve-TpmGameTitle -Index $script:WideIndex -Title 'Zzzz Qqqq' -InternalName 'Mega Racer'
        $hint.Status | Should -Be 'Matched'
        $hint.Match.Id | Should -Be '35'
    }

    It 'never offers a game with a different number or year: Golden Tee Live 2020 is not 2022, but 2022 is 2022' {
        $missing = Resolve-TpmGamesDbMatch -Index $script:WideIndex -Names @([pscustomobject]@{ Source = 'TeknoParrot'; Name = 'Golden Tee Live 2020' }, [pscustomobject]@{ Source = 'Eggman list'; Name = 'Golden Tee Live 2020' }) -Year 2020
        $missing.Status | Should -Be 'None'
        $found = Resolve-TpmGamesDbMatch -Index $script:WideIndex -Names @([pscustomobject]@{ Source = 'TeknoParrot'; Name = 'Golden Tee Live 2022' }) -Year 2022
        $found.Status | Should -Be 'Sure'
        $found.Match.Id | Should -Be '37'
    }

    It 'tells Street Fighter Zero from Zero 3, drops a version list from a name, and asks when a slash name is two different games' {
        $zero = Resolve-TpmGamesDbMatch -Index $script:WideIndex -Names @([pscustomobject]@{ Source = 'TeknoParrot'; Name = 'Street Fighter Zero (Asia 950627)' })
        $zero.Status | Should -Be 'Sure'
        $zero.Match.Id | Should -Be '38'
        $version = Resolve-TpmGamesDbMatch -Index $script:WideIndex -Names @([pscustomobject]@{ Source = 'TeknoParrot'; Name = 'Street Fighter V: Type Arcade Version 3.53 / 4.12' })
        $version.Status | Should -Be 'Sure'
        $version.Match.Id | Should -Be '42'
        $slash = Resolve-TpmGamesDbMatch -Index $script:WideIndex -Names @([pscustomobject]@{ Source = 'TeknoParrot'; Name = 'Street Smart / Final Fight (Japan, hack)' })
        $slash.Status | Should -Be 'Check'
    }

    It 'asks about a name that contains the list name word for word, never a different number or a loose resemblance' {
        $longer = Get-TpmGamesDbPick -Index $script:WideIndex -Title 'Dino King Battle: King of Jurassic'
        $longer.Kind | Should -Be 'NearAsk'
        $longer.Id | Should -Be '43'
        $shorter = Get-TpmGamesDbPick -Index $script:WideIndex -Title 'Brave Firefighters'
        $shorter.Kind | Should -Be 'NearAsk'
        $shorter.Id | Should -Be '44'
        $inner = Get-TpmGamesDbPick -Index $script:WideIndex -Title 'Project Diva Arcade'
        $inner.Kind | Should -Be 'NearAsk'
        $inner.Id | Should -Be '45'
        (Get-TpmGamesDbPick -Index $script:WideIndex -Title 'Dino King Battle 2: King of Jurassic').Id | Should -Not -Be '43'
        (Get-TpmGamesDbPick -Index $script:WideIndex -Title 'Final Battle').Id | Should -Not -Be '43'
    }

    It 'leaves a region at the end of a title out when the name without it is a game in the list' {
        $cobra = Get-TpmGamesDbPick -Index $script:WideIndex -Title 'Cobra: The Arcade World (CBR2 Ver. B)'
        $cobra.Kind | Should -Be 'Exact'
        $cobra.Id | Should -Be '46'
    }

    It 'does not let a version number separate two names of the same game' {
        (Get-TpmGamesDbPick -Index $script:WideIndex -Title 'Initial D Arcade Stage Ver. 2 (Japan) (GDS-0026)').Id | Should -Be '51'
        (Get-TpmGamesDbPick -Index $script:WideIndex -Title 'Initial D Arcade Stage Ver. 9 (Japan) (GDS-0099)').Id | Should -Be '47'
        (Get-TpmGamesDbPick -Index $script:WideIndex -Title 'Mario Kart: Arcade GP DX 1.18').Id | Should -Be '48'
        $striker = Get-TpmGamesDbPick -Index $script:WideIndex -Title 'Virtua Striker 4'
        $striker.Kind | Should -Be 'Exact'
        $striker.Id | Should -Be '49'
        (Get-TpmGamesDbPick -Index $script:WideIndex -Title 'Tekken 5.1').Id | Should -Not -Be '50'
    }

    It 'reads a plus sign as plus and Vs. as versus, and ignores a source whose whole name is a region' {
        $plus = Get-TpmGamesDbPick -Index $script:WideIndex -Title 'Nitro+ Blasterz: Heroines Infinite Duel'
        $plus.Kind | Should -Be 'Exact'
        $plus.Id | Should -Be '52'
        $versus = Get-TpmGamesDbPick -Index $script:WideIndex -Title 'Marvel Versus Capcom 2'
        $versus.Kind | Should -Be 'Exact'
        $versus.Id | Should -Be '53'
        $region = Resolve-TpmGamesDbMatch -Index $script:WideIndex -Names @([pscustomobject]@{ Source = 'TeknoParrot'; Name = 'Ehrgeiz (World, EG2/VER.A)' }, [pscustomobject]@{ Source = 'Eggman list'; Name = 'World' })
        $region.Status | Should -Be 'None'
    }

    It 'links a game that has no year in any source by its exact name' {
        $result = Resolve-TpmGamesDbMatch -Index $script:WideIndex -Names @([pscustomobject]@{ Source = 'TeknoParrot'; Name = 'Big Buck World' })
        $result.Status | Should -Be 'Sure'
        $result.Match.Id | Should -Be '21'
    }
}
