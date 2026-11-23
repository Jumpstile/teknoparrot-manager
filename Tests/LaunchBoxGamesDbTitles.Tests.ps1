#Requires -Module Pester

# Issue #426: LaunchBox game titles and Games Database IDs from LaunchBox's own local game list.
# What a user sees or loses is tested through the public functions of the "TPM GAME TITLE MATCHING" block and the two
# LaunchBox entry functions that apply a match: official name and ID for a sure match, nothing guessed, hand-made names
# kept, the database file never changed, and today's behavior when the game list is missing or unreadable.
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.
# The game list is a tiny SQLite file built in the test under TestDrive. What this CANNOT prove: LaunchBox's real 400 MB file
# (checked by hand on a real install), or LaunchBox itself reading the saved IDs.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'GamesDb title tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:GdbFunctionFile = Join-Path $TestDrive 'tpm-gdb-functions.ps1'
    [System.IO.File]::WriteAllText($script:GdbFunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:GdbFunctionFile
    # Get-MeaningfulTitleTokens reads this word list, which the production script sets at its top level.
    $script:LaunchBoxGameSkeletonFields = [ordered]@{
        ID=''; Title=''; Platform=''; Emulator=''; ApplicationPath=''; CommandLine=''
        DateAdded=''; DateModified=''; Favorite='false'; Completed='false'; Hide='false'
        PlayCount='0'; PlayTime='0'; Notes=''
    }
    $script:LaunchBoxGameIdentityFields = @('ID','Title','Platform','Emulator','ApplicationPath','CommandLine','DateAdded','DateModified')
    $script:TitleTokenStopWords = [System.Collections.Generic.HashSet[string]]::new([string[]]@('the', 'of', 'a', 'an', 'and', 'vs', 'vs.', 'in', 'for', 'to'), [System.StringComparer]::OrdinalIgnoreCase)

    # A tiny game list in the same shape as LaunchBox's file (only the columns TPM reads).
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
    $script:GdbDbPath = Join-Path $TestDrive 'LaunchBox.Metadata.db'
    [TpmTestGamesDbWriter]::Build($script:GdbDbPath, @"
CREATE TABLE Games (DatabaseID INTEGER, Name TEXT, Platform TEXT);
CREATE TABLE GameAlternateTitles (AlternateName TEXT, DatabaseID INTEGER, Region TEXT, AltNameCompareValue TEXT);
INSERT INTO Games VALUES (11, 'Too Spicy', 'Arcade');
INSERT INTO Games VALUES (12, 'Initial D Arcade Stage', 'Arcade');
INSERT INTO Games VALUES (21, 'Twin Game', 'Arcade');
INSERT INTO Games VALUES (22, 'Twin Game', 'Arcade');
INSERT INTO Games VALUES (31, 'Console Only Game', 'Sony Playstation 2');
INSERT INTO Games VALUES (41, 'Dead Run', 'Arcade');
INSERT INTO Games VALUES (42, 'Zombie Run Reloaded', 'Arcade');
INSERT INTO Games VALUES (51, 'Silver Strike LIVE', 'Arcade');
INSERT INTO GameAlternateTitles VALUES ('Silver Strike Bowling Live', 51, '', 'x');
"@)
    $script:GdbHashBefore = (Get-FileHash -LiteralPath $script:GdbDbPath -Algorithm SHA256).Hash
    $script:GdbIndex = Get-TpmGamesDbIndex -DbPath $script:GdbDbPath

    function New-GdbGamesDoc {
        param([string]$Title, [string]$DatabaseId = '', [string]$Emulator = 'emu-1')
        $doc = [xml]'<LaunchBox><Game><ID>g1</ID><Title></Title><Emulator></Emulator><ApplicationPath>Emulators\TeknoParrot\UserProfiles\X.xml</ApplicationPath></Game></LaunchBox>'
        $game = $doc.SelectSingleNode('/LaunchBox/Game')
        $game.SelectSingleNode('Title').InnerText = $Title
        $game.SelectSingleNode('Emulator').InnerText = $Emulator
        if ($DatabaseId) { Set-XmlChildText $game 'DatabaseID' $DatabaseId }
        return $doc
    }
}

Describe 'Issue 426: official names and IDs from the local game list' {
    BeforeEach { Mock Write-Log {} }

    It 'only reads the game list: the file is byte-for-byte the same afterwards' {
        Get-TpmGamesDbIndex -DbPath $script:GdbDbPath | Out-Null
        (Get-FileHash -LiteralPath $script:GdbDbPath -Algorithm SHA256).Hash | Should -Be $script:GdbHashBefore
    }

    It 'a new LaunchBox entry gets the official name and the ID; without a match it keeps today''s name and has no ID' {
        $doc = [xml]'<LaunchBox />'
        New-LaunchBoxGameEntry $doc 'Emulators\TeknoParrot\UserProfiles\A.xml' 'A' 'TeknoParrot' 'emu-1' 'C:\LB' -GamesDbMatch ([pscustomobject]@{ Id = '11'; Name = 'Too Spicy' }) | Should -BeTrue
        New-LaunchBoxGameEntry $doc 'Emulators\TeknoParrot\UserProfiles\B.xml' 'SomeFileName' 'TeknoParrot' 'emu-1' 'C:\LB' | Should -BeTrue
        $games = @($doc.SelectNodes('/LaunchBox/Game'))
        $games[0].Title | Should -Be 'Too Spicy'
        $games[0].DatabaseID | Should -Be '11'
        $games[1].Title | Should -Be 'SomeFileName'
        $games[1].SelectSingleNode('DatabaseID') | Should -BeNullOrEmpty
    }

    It 'a game already in LaunchBox that TPM added gets the clean title and the official name and ID' {
        $doc = New-GdbGamesDoc -Title 'X'
        $change = Update-TpmLaunchBoxGameTitle -platformGamesDoc $doc -relProfilePath 'Emulators\TeknoParrot\UserProfiles\X.xml' -KnownTitles @('X') -NewTitle 'Too Spicy' -emulatorId 'emu-1' -lbRoot 'C:\LB' -GamesDbMatch ([pscustomobject]@{ Id = '11'; Name = 'Too Spicy' })
        $change.New | Should -Be 'Too Spicy'
        $doc.SelectSingleNode('/LaunchBox/Game/Title').InnerText | Should -Be 'Too Spicy'
        $doc.SelectSingleNode('/LaunchBox/Game/DatabaseID').InnerText | Should -Be '11'
        # No sure match: only the clean title is set, and no ID is made up.
        $plain = New-GdbGamesDoc -Title 'X'
        (Update-TpmLaunchBoxGameTitle -platformGamesDoc $plain -relProfilePath 'Emulators\TeknoParrot\UserProfiles\X.xml' -KnownTitles @('X') -NewTitle 'Clean Name' -emulatorId 'emu-1' -lbRoot 'C:\LB').Id | Should -Be ''
        $plain.SelectSingleNode('/LaunchBox/Game/Title').InnerText | Should -Be 'Clean Name'
        $plain.SelectSingleNode('/LaunchBox/Game/DatabaseID') | Should -BeNullOrEmpty
    }

    It 'a title the owner changed by hand is never replaced and gets no ID' {
        $doc = New-GdbGamesDoc -Title 'My own name for it'
        $change = Update-TpmLaunchBoxGameTitle -platformGamesDoc $doc -relProfilePath 'Emulators\TeknoParrot\UserProfiles\X.xml' -KnownTitles @('X') -NewTitle 'Too Spicy' -emulatorId 'emu-1' -lbRoot 'C:\LB' -GamesDbMatch ([pscustomobject]@{ Id = '11'; Name = 'Too Spicy' })
        $change | Should -BeNullOrEmpty
        $doc.SelectSingleNode('/LaunchBox/Game/Title').InnerText | Should -Be 'My own name for it'
        $doc.SelectSingleNode('/LaunchBox/Game/DatabaseID') | Should -BeNullOrEmpty
    }

    It 'a game that already has an ID, or is not TPM''s entry, is left alone' {
        $linked = New-GdbGamesDoc -Title 'X' -DatabaseId '999'
        Update-TpmLaunchBoxGameTitle -platformGamesDoc $linked -relProfilePath 'Emulators\TeknoParrot\UserProfiles\X.xml' -KnownTitles @('X') -NewTitle 'Too Spicy' -emulatorId 'emu-1' -lbRoot 'C:\LB' -GamesDbMatch ([pscustomobject]@{ Id = '11'; Name = 'Too Spicy' }) | Should -BeNullOrEmpty
        $linked.SelectSingleNode('/LaunchBox/Game/DatabaseID').InnerText | Should -Be '999'
        $foreign = New-GdbGamesDoc -Title 'X' -Emulator 'someone-elses-emulator'
        Update-TpmLaunchBoxGameTitle -platformGamesDoc $foreign -relProfilePath 'Emulators\TeknoParrot\UserProfiles\X.xml' -KnownTitles @('X') -NewTitle 'Too Spicy' -emulatorId 'emu-1' -lbRoot 'C:\LB' -GamesDbMatch ([pscustomobject]@{ Id = '11'; Name = 'Too Spicy' }) | Should -BeNullOrEmpty
        $foreign.SelectSingleNode('/LaunchBox/Game/Title').InnerText | Should -Be 'X'
    }

    It 'a missing game list falls back to today''s behavior and says so in plain words' {
        $emptyRoot = Join-Path $TestDrive 'lb-without-list'
        [void][System.IO.Directory]::CreateDirectory($emptyRoot)
        $state = Get-TpmGamesDbForLaunchBox -LaunchBoxRoot $emptyRoot
        $state.State | Should -Be 'Missing'
        $summary = Get-TpmLaunchBoxTitleSummary -Result ([pscustomobject]@{ GamesDbState = 'Missing'; GamesDbError = $state.Error; TitleChanges = @(); TitleReview = @(); Reason = 'PREVIEW'; Outcome = 'NO_CHANGES' })
        $summary.NotChanged | Should -Match 'no Games Database ID was added'
    }

    It 'an unreadable game list does not stop anything: games keep their names and the reason is in Details' {
        $brokenRoot = Join-Path $TestDrive 'lb-with-broken-list'
        [void][System.IO.Directory]::CreateDirectory((Join-Path $brokenRoot 'Metadata'))
        [System.IO.File]::WriteAllText((Join-Path $brokenRoot 'Metadata\LaunchBox.Metadata.db'), 'this is not a database')
        $state = Get-TpmGamesDbForLaunchBox -LaunchBoxRoot $brokenRoot
        $state.State | Should -Be 'Failed'
        $state.Error | Should -Not -BeNullOrEmpty
        $result = [pscustomobject]@{ GamesDbState = 'Failed'; GamesDbError = $state.Error; TitleChanges = @(); TitleReview = @(); Reason = 'PREVIEW'; Outcome = 'NO_CHANGES' }
        (Get-TpmLaunchBoxTitleSummary -Result $result).NotChanged | Should -Match 'could not be read'
        (Get-TpmLaunchBoxTitleDetailBlock -Result $result).Lines -join ' ' | Should -Match 'Games Database not used'
    }

    It 'the preview lists every old name, new name and ID, the clean-name changes, and the games that need a choice' {
        $result = [pscustomobject]@{ GamesDbState = 'Used'; GamesDbError = ''; Reason = 'PREVIEW'; Outcome = 'NO_CHANGES'
            TitleChanges = @(
                [pscustomobject]@{ Old = 'SSASR'; New = 'Sega Sports'; Id = '7'; Kind = 'New'; Choice = $false },
                [pscustomobject]@{ Old = 'zq1'; New = 'Zzzz Qqqq'; Id = ''; Kind = 'New'; Choice = $false })
            TitleReview = @([pscustomobject]@{ File = 'Q.xml'; Title = 'Q'; Status = 'Ambiguous'; Reason = 'Only a close name was found.'; Options = @([pscustomobject]@{ Name = 'Too Spicy'; Id = '11' }) }) }
        $lines = (Get-TpmLaunchBoxTitleDetailBlock -Result $result).Lines -join "`n"
        $lines | Should -Match 'SSASR\s+->\s+Sega Sports, ID 7'
        $lines | Should -Match 'zq1\s+->\s+Zzzz Qqqq'
        $lines | Should -Match 'Needs your choice: Q'
        $summary = Get-TpmLaunchBoxTitleSummary -Result $result
        ($summary.Done -join ' ') | Should -Match 'official name and Games Database ID'
        ($summary.Done -join ' ') | Should -Match 'clean game name'
        $summary.NotChanged | Should -Match 'no sure match'
    }
}
