#Requires -Module Pester

# Issue #422: regions and versions of one game become one LaunchBox game with a version picker.
# What a user sees or loses: only the same game is grouped (same Games Database ID), the default version follows the region the user chose,
# the preview changes nothing, nothing is lost (every version is still a way to start the game), the Manager's own entries only, and Restore
# (the verified backup) puts the separate games back.
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.
# Everything lives under TestDrive. What this CANNOT prove: that a real LaunchBox shows the version picker for these entries (the entry shape
# was read from a real LaunchBox library, but no real LaunchBox opened these files).

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Version tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:VerFile = Join-Path $TestDrive 'tpm-ver-functions.ps1'
    [System.IO.File]::WriteAllText($script:VerFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:VerFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
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

    # One LaunchBox library with three profiles: Too Spicy in a Japan and a USA version, and an unrelated game. The game list knows both games.
    function New-VerFixture {
        param([string]$ExtraGameXml = '')
        $root = Join-Path $TestDrive ('ver-' + [guid]::NewGuid().ToString('N'))
        $lb = Join-Path $root 'LaunchBox'; $tp = Join-Path $root 'TP'; $profiles = Join-Path $tp 'UserProfiles'
        foreach ($dir in @((Join-Path $lb 'Data\Platforms'), (Join-Path $lb 'Metadata'), (Join-Path $tp 'Metadata'), $profiles)) { [void][System.IO.Directory]::CreateDirectory($dir) }
        [System.IO.File]::WriteAllText((Join-Path $lb 'Data\Emulators.xml'), '<LaunchBox><Emulator><ID>emu-1</ID><Title>TeknoParrot</Title></Emulator></LaunchBox>')
        foreach ($item in @(@('TooSpicyJ', 'Too Spicy (Japan)'), @('TooSpicyU', 'Too Spicy (USA)'), @('Fantasy', 'Fantasy Soccer'))) {
            [System.IO.File]::WriteAllText((Join-Path $profiles ($item[0] + '.xml')), '<GameProfile><GamePath>C:\x\game.exe</GamePath></GameProfile>')
            [System.IO.File]::WriteAllText((Join-Path $tp ('Metadata\' + $item[0] + '.json')), ('{{"game_name":"{0}","platform":"SEGA Lindbergh Red","release_year":"2007"}}' -f $item[1]))
        }
        [TpmTestGamesDbWriter]::Build((Join-Path $lb 'Metadata\LaunchBox.Metadata.db'), @"
CREATE TABLE Games (DatabaseID INTEGER, Name TEXT, Platform TEXT, ReleaseYear INTEGER, ReleaseDate TEXT, Developer TEXT, Publisher TEXT);
CREATE TABLE GameAlternateTitles (AlternateName TEXT, DatabaseID INTEGER, Region TEXT, AltNameCompareValue TEXT);
INSERT INTO Games VALUES (11, 'Too Spicy', 'Arcade', 2007, NULL, 'Sega', 'Sega');
INSERT INTO Games VALUES (12, 'Fantasy', 'Arcade', 1990, NULL, 'Someone', 'Someone');
"@)
        $games = ''
        foreach ($item in @(@('g1', 'TooSpicyJ'), @('g2', 'TooSpicyU'), @('g3', 'Fantasy'))) {
            $games += ('<Game><ID>{0}</ID><Title>{1}</Title><Platform>TeknoParrot</Platform><Emulator>emu-1</Emulator><ApplicationPath>..\TP\UserProfiles\{1}.xml</ApplicationPath><PlayCount>3</PlayCount></Game>' -f $item[0], $item[1])
        }
        [System.IO.File]::WriteAllText((Join-Path $lb 'Data\Platforms\TeknoParrot.xml'), ('<LaunchBox>{0}{1}</LaunchBox>' -f $games, $ExtraGameXml))
        return [pscustomobject]@{ Root = $lb; Tp = $tp; Profiles = $profiles; Backups = (Join-Path $root 'Backups'); Platform = (Join-Path $lb 'Data\Platforms\TeknoParrot.xml') }
    }
    function Read-VerPlatform { param($Fixture) return ([xml][System.IO.File]::ReadAllText($Fixture.Platform)) }
}

Describe 'Issue 422: group the versions of one game' {
    BeforeEach {
        Mock Write-Log {}
        Mock Test-LaunchBoxRunning { $false }
        Mock Wait-TpmForProcessClose { $true }
        Mock Write-TpmCompactExtractionProgress {}
    }

    It 'reads a region note as one region word' {
        ConvertTo-TpmRegionKey 'Japan, GDS-0026' | Should -BeExactly 'Japan'
        ConvertTo-TpmRegionKey 'JPN' | Should -BeExactly 'Japan'
        ConvertTo-TpmRegionKey 'USA' | Should -BeExactly 'USA'
        ConvertTo-TpmRegionKey 'World, Rev B' | Should -BeExactly 'Export'
        ConvertTo-TpmRegionKey '1.00.00' | Should -BeExactly ''
    }

    It 'the region the user chose in Region setup is the one most profiles are set to (Auto does not count)' {
        $dir = Join-Path $TestDrive 'region-profiles'
        [void][System.IO.Directory]::CreateDirectory($dir)
        $field = '<GameProfile><ConfigValues><FieldInformation><CategoryName>General</CategoryName><FieldName>Region</FieldName><FieldValue>{0}</FieldValue><FieldType>Dropdown</FieldType><FieldOptions><string>Auto</string><string>Japan</string><string>USA</string></FieldOptions></FieldInformation></ConfigValues></GameProfile>'
        $paths = @()
        foreach ($item in @(@('a', 'USA'), @('b', 'USA'), @('c', 'Japan'), @('d', 'Auto'))) {
            $path = Join-Path $dir ($item[0] + '.xml')
            [System.IO.File]::WriteAllText($path, ($field -f $item[1]))
            $paths += $path
        }
        Get-TpmPreferredRegion -ProfilePaths $paths | Should -BeExactly 'USA'
        Get-TpmPreferredRegion -ProfilePaths @() | Should -BeExactly ''
    }

    It 'a preview changes nothing; a write makes one game with the other version inside it, and the default follows the chosen region' {
        # Mutation: ignore -PlanOnly (files change), pick the first entry whatever the region, or lose the version.
        $fx = New-VerFixture
        $hash = (Get-FileHash -LiteralPath $fx.Platform).Hash
        $preview = Invoke-TpmLaunchBoxGroup -UserProfilesDir $fx.Profiles -LbRoot $fx.Root -PlatformNames @('TeknoParrot') -TpRoot $fx.Tp -PlanOnly
        $preview.Reason | Should -BeExactly 'PREVIEW'
        (Get-FileHash -LiteralPath $fx.Platform).Hash | Should -BeExactly $hash
        (@(Format-TpmLaunchBoxGroupLine -Plan $preview.GroupPlan) -join "`n") | Should -Match '2 entries become one game. The default version is TooSpicyU \(USA\)'
        @($preview.GroupPlan.Groups).Count | Should -Be 1
        # With no region chosen, the Japan version is not the default.
        $written = Invoke-TpmLaunchBoxGroup -UserProfilesDir $fx.Profiles -LbRoot $fx.Root -PlatformNames @('TeknoParrot') -BackupRoot $fx.Backups -TpRoot $fx.Tp
        $written.Outcome | Should -BeExactly 'SAVED'
        $written.BackupVerified | Should -BeTrue
        $doc = Read-VerPlatform $fx
        @($doc.SelectNodes('/LaunchBox/Game')).Count | Should -Be 2
        $kept = $doc.SelectSingleNode('/LaunchBox/Game[ID="g2"]')
        $kept | Should -Not -BeNullOrEmpty
        $app = $doc.SelectSingleNode('/LaunchBox/AdditionalApplication')
        $app.GameID | Should -BeExactly 'g2'
        $app.ApplicationPath | Should -Be '..\TP\UserProfiles\TooSpicyJ.xml'
        $app.UseEmulator | Should -BeExactly 'true'
        $app.EmulatorId | Should -BeExactly 'emu-1'
        $app.Region | Should -BeExactly 'Japan'
        $app.PlayCount | Should -BeExactly '3'
        $doc.SelectSingleNode('/LaunchBox/Game[ID="g3"]') | Should -Not -BeNullOrEmpty
        # Running it again has nothing left to group.
        (Invoke-TpmLaunchBoxGroup -UserProfilesDir $fx.Profiles -LbRoot $fx.Root -PlatformNames @('TeknoParrot') -BackupRoot $fx.Backups -TpRoot $fx.Tp).Outcome | Should -BeExactly 'NO_CHANGES'
    }

    It 'the chosen region picks the default version' {
        $fx = New-VerFixture
        $index = (Get-TpmGamesDbForLaunchBox -LaunchBoxRoot $fx.Root).Index
        $plan = New-TpmLaunchBoxGroupPlan -UserProfilesDir $fx.Profiles -LbRoot $fx.Root -EmulatorId 'emu-1' -PlatformNames @('TeknoParrot') -TpRoot $fx.Tp -Index $index -PreferredRegion 'Japan'
        $plan.Groups[0].Default | Should -BeExactly 'TooSpicyJ'
        (Format-TpmLaunchBoxGroupTitle -Plan $plan -Preview) | Should -Match 'follows your region choice: Japan'
    }

    It 'does not group games of other emulators, games with different IDs, or entries with no certain match' {
        # Mutation: group by title alone -> another emulator's game or an unrelated game is pulled in.
        $fx = New-VerFixture -ExtraGameXml '<Game><ID>g9</ID><Title>Too Spicy</Title><Platform>TeknoParrot</Platform><Emulator>emu-other</Emulator><ApplicationPath>..\TP\UserProfiles\TooSpicyU.xml</ApplicationPath></Game>'
        $index = (Get-TpmGamesDbForLaunchBox -LaunchBoxRoot $fx.Root).Index
        $plan = New-TpmLaunchBoxGroupPlan -UserProfilesDir $fx.Profiles -LbRoot $fx.Root -EmulatorId 'emu-1' -PlatformNames @('TeknoParrot') -TpRoot $fx.Tp -Index $index
        @($plan.Groups).Count | Should -Be 1
        $plan.Groups[0].Count | Should -Be 2
        $xml = $plan.Plans[0].Document
        $xml.SelectSingleNode('/LaunchBox/Game[ID="g9"]') | Should -Not -BeNullOrEmpty
        $xml.SelectSingleNode('/LaunchBox/Game[ID="g3"]') | Should -Not -BeNullOrEmpty
        # Without the game list only entries that already carry the same ID are grouped, so nothing here is.
        @((New-TpmLaunchBoxGroupPlan -UserProfilesDir $fx.Profiles -LbRoot $fx.Root -EmulatorId 'emu-1' -PlatformNames @('TeknoParrot') -TpRoot $fx.Tp).Groups).Count | Should -Be 0
    }

    It 'a game that already has the same Games Database ID is grouped without asking the game list' {
        $fx = New-VerFixture
        $xml = [System.IO.File]::ReadAllText($fx.Platform).Replace('<Title>TooSpicyJ</Title>', '<Title>TooSpicyJ</Title><DatabaseID>77</DatabaseID>').Replace('<Title>TooSpicyU</Title>', '<Title>TooSpicyU</Title><DatabaseID>77</DatabaseID>')
        [System.IO.File]::WriteAllText($fx.Platform, $xml)
        @((New-TpmLaunchBoxGroupPlan -UserProfilesDir $fx.Profiles -LbRoot $fx.Root -EmulatorId 'emu-1' -PlatformNames @('TeknoParrot') -TpRoot $fx.Tp).Groups).Count | Should -Be 1
    }
}
