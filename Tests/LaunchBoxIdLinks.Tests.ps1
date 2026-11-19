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
        (New-IdlGame 'g6' 'Totally Unknown' 'NoSuchCode')
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
        $byId.Keys.Count | Should -Be 4
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
        # The title there was the title of the entry, not the TeknoParrot name, so it stays.
        $xml.SelectSingleNode('/LaunchBox/Game[ID="g2"]/Title').InnerText | Should -Be 'PowerPuttLive2013'
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
        (Format-TpmLaunchBoxIdLinkTitle -Plan $plan -Preview) | Should -Match '^Preview: 2 sure matches'
    }

    It 'says so when there is nothing to link' {
        $empty = [pscustomobject]@{ Plans = @(); Items = @() }
        Format-TpmLaunchBoxIdLinkTitle -Plan $empty | Should -Match 'already has a Games Database ID'
    }
}
