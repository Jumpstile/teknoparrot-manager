#Requires -Module Pester

# LB424: import clear logos and box art into LaunchBox from a folder the user picks.
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.
# Everything lives under TestDrive with synthetic files; the real LaunchBox is never touched and nothing is downloaded.
# Each It names the product change that makes it fail.
# What this CANNOT prove: LaunchBox itself showing the pictures, or how LaunchBox names files with unusual characters.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'LB424 tests could not parse the production script.' }
    $functions = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $functionText = ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:Lb424FunctionFile = Join-Path $TestDrive 'tpm-lb424-functions.ps1'
    [System.IO.File]::WriteAllText($script:Lb424FunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:Lb424FunctionFile
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
    # A tiny game list: Time Crisis 4 (also known as TC4) and two different games called Frogger.
    function New-Lb424GameList {
        param($Fx)
        [void][System.IO.Directory]::CreateDirectory((Join-Path $Fx.Lb 'Metadata'))
        [TpmTestGamesDbWriter]::Build((Join-Path $Fx.Lb 'Metadata\LaunchBox.Metadata.db'), @"
CREATE TABLE Games (DatabaseID INTEGER, Name TEXT, Platform TEXT, ReleaseYear INTEGER, ReleaseDate TEXT, Developer TEXT, Publisher TEXT);
CREATE TABLE GameAlternateTitles (AlternateName TEXT, DatabaseID INTEGER, Region TEXT, AltNameCompareValue TEXT);
INSERT INTO Games VALUES (41, 'Time Crisis 4', 'Arcade', 2006, NULL, 'Namco', 'Namco');
INSERT INTO GameAlternateTitles VALUES ('TC4', 41, NULL, 'tc4');
INSERT INTO Games VALUES (61, 'Frogger', 'Arcade', 1981, NULL, 'Konami', 'Konami');
INSERT INTO Games VALUES (62, 'Frogger (Raw Thrills)', 'Arcade', 2013, NULL, 'Raw Thrills', 'Raw Thrills');
"@)
    }
    $script:Lb424ImportText = (($functions | Where-Object { $_.Name -match 'LbMedia|LaunchBoxMedia' } | ForEach-Object { $_.Extent.Text }) -join "`r`n")

    function New-Lb424Fixture {
        $root = Join-Path $TestDrive ('lb424-' + [guid]::NewGuid().ToString('N'))
        $lb = Join-Path $root 'LaunchBox'
        $profiles = Join-Path $root 'UserProfiles'
        $pics = Join-Path $root 'MyPictures'
        [void][System.IO.Directory]::CreateDirectory((Join-Path $lb 'Data\Platforms'))
        [void][System.IO.Directory]::CreateDirectory($profiles)
        [void][System.IO.Directory]::CreateDirectory((Join-Path $pics 'sub'))
        $emuId = [guid]::NewGuid().ToString()
        $otherEmu = [guid]::NewGuid().ToString()
        [System.IO.File]::WriteAllText((Join-Path $lb 'Data\Emulators.xml'), "<LaunchBox><Emulator><ID>$emuId</ID><Title>TeknoParrot</Title><ApplicationPath>C:\TP\TeknoParrotUi.exe</ApplicationPath></Emulator></LaunchBox>")
        $game = { param($title, $emu, $app) "<Game><ID>$([guid]::NewGuid())</ID><Title>$title</Title><Platform>TeknoParrot</Platform><Emulator>$emu</Emulator><ApplicationPath>$app</ApplicationPath></Game>" }
        $games = @(
            (& $game 'Time Crisis 4' $emuId (Join-Path $profiles 'tc4.xml')),
            (& $game 'Ghost Squad Evolution' $emuId (Join-Path $profiles 'gse.xml')),
            (& $game 'Mario Kart GP' $emuId (Join-Path $profiles 'mkgp.xml')),
            (& $game 'Hand Added Game' $otherEmu 'D:\Roms\hand.exe'),
            (& $game 'Outside Profile Game' $emuId 'D:\Elsewhere\other.xml'),
            (& $game 'Other Emulator Game' $otherEmu (Join-Path $profiles 'other.xml'))
        ) -join ''
        [System.IO.File]::WriteAllText((Join-Path $lb 'Data\Platforms\TeknoParrot.xml'), "<LaunchBox>$games</LaunchBox>")
        [System.IO.File]::WriteAllBytes((Join-Path $pics 'time-crisis_4.png'), [byte[]](1, 2, 3, 4))
        [System.IO.File]::WriteAllBytes((Join-Path $pics 'sub\Ghost Squad Evolutiom.png'), [byte[]](5, 6, 7, 8))
        [System.IO.File]::WriteAllBytes((Join-Path $pics 'Hand Added Game.png'), [byte[]](9, 9, 9))
        [System.IO.File]::WriteAllBytes((Join-Path $pics 'Outside Profile Game.png'), [byte[]](8, 8, 8))
        [System.IO.File]::WriteAllBytes((Join-Path $pics 'Other Emulator Game.png'), [byte[]](6, 6, 6))
        [System.IO.File]::WriteAllText((Join-Path $pics 'notes.txt'), 'not a picture')
        return [pscustomobject]@{ Root = $root; Lb = $lb; Profiles = $profiles; Pics = $pics; Backups = (Join-Path $root 'Backups\LaunchBoxBackups') }
    }

    function Get-Lb424Snapshot {
        param([string]$Path)
        return @(Get-ChildItem -LiteralPath $Path -Recurse -File | Sort-Object FullName | ForEach-Object { $_.FullName.Substring($Path.Length) + '|' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash })
    }

    function Get-Lb424Plan {
        param($Fx, [switch]$Replace, [switch]$WithGameList)
        $extra = @{}
        if ($WithGameList) { $extra.GameList = (Get-TpmGamesDbForLaunchBox -LaunchBoxRoot $Fx.Lb).Index }
        return (Get-TpmLaunchBoxMediaPlan -lbRoot $Fx.Lb -userProfilesDir $Fx.Profiles -imageFolder $Fx.Pics -platformNames @('TeknoParrot') -Kind ClearLogo -ReplaceExisting:$Replace @extra)
    }
}

Describe 'LB424: matching and preview' {
    BeforeEach { Mock Write-Log {} }

    It 'the preview changes nothing in LaunchBox or in the picture folder' {
        # Mutation: make the preview create folders or copy files -> the snapshot differs.
        $fx = New-Lb424Fixture
        $before = Get-Lb424Snapshot $fx.Root
        $null = Get-Lb424Plan $fx
        (Get-Lb424Snapshot $fx.Root) | Should -Be $before
    }

    It 'sorts games into exact matches, near matches and no picture, and skips games the Manager did not add' {
        # Mutation: treat every LaunchBox game as ours (drop the emulator check) -> Other Emulator Game shows up as a match.
        # Mutation: drop the profile-folder check -> Outside Profile Game shows up as a match.
        $fx = New-Lb424Fixture
        $plan = Get-Lb424Plan $fx
        @($plan.Exact | ForEach-Object { $_.Game.Title }) | Should -Be @('Time Crisis 4')
        @($plan.Near | ForEach-Object { $_.Game.Title }) | Should -Be @('Ghost Squad Evolution')
        @($plan.NoImage | ForEach-Object { $_.Game.Title }) | Should -Be @('Mario Kart GP')
        $plan.GameCount | Should -Be 3
        $plan.ImageCount | Should -Be 5
        $plan.Exact[0].Dest | Should -BeExactly (Join-Path $fx.Lb 'Images\TeknoParrot\Clear Logo\Time Crisis 4-01.png')
    }

    It 'ignores region marks and tags in picture file names, the same way the DAT matching does' {
        # Mutation: compare raw file names -> "Time Crisis 4 (World) [TP]" is no longer an exact match.
        $fx = New-Lb424Fixture
        Remove-Item -LiteralPath (Join-Path $fx.Pics 'time-crisis_4.png')
        [System.IO.File]::WriteAllBytes((Join-Path $fx.Pics 'Time Crisis 4 (World) [TP]-01.png'), [byte[]](1, 1))
        $plan = Get-Lb424Plan $fx
        @($plan.Exact | ForEach-Object { $_.Game.Title }) | Should -Be @('Time Crisis 4')
    }

    It 'never puts a near match in the sure list, even when it is the only candidate' {
        # Mutation: auto-accept the best near candidate -> Near becomes empty and Exact has two items.
        $fx = New-Lb424Fixture
        $plan = Get-Lb424Plan $fx
        $plan.Exact.Count | Should -Be 1
        $plan.Near[0].Candidates.Count | Should -Be 1
        [System.IO.Path]::GetFileName($plan.Near[0].Candidates[0].Image) | Should -BeExactly 'Ghost Squad Evolutiom.png'
    }

    It 'treats two pictures with the same name as a question for the user, not an automatic pick' {
        # Mutation: take the first of several same-name pictures -> the game moves to the sure list.
        $fx = New-Lb424Fixture
        [System.IO.File]::WriteAllBytes((Join-Path $fx.Pics 'sub\Time Crisis 4.jpg'), [byte[]](4, 4, 4))
        $plan = Get-Lb424Plan $fx
        @($plan.Exact | ForEach-Object { $_.Game.Title }) | Should -Not -Contain 'Time Crisis 4'
        $tc = @($plan.Near | Where-Object { $_.Game.Title -eq 'Time Crisis 4' })
        $tc.Count | Should -Be 1
        $tc[0].Candidates.Count | Should -Be 2
    }

    It 'keeps a game that already has a picture out of the match lists unless replacing is chosen' {
        # Mutation: ignore existing pictures -> Time Crisis 4 stays in Exact.
        $fx = New-Lb424Fixture
        $dir = Join-Path $fx.Lb 'Images\TeknoParrot\Clear Logo'
        [void][System.IO.Directory]::CreateDirectory($dir)
        [System.IO.File]::WriteAllBytes((Join-Path $dir 'Time Crisis 4-01.png'), [byte[]](0, 0))
        $plan = Get-Lb424Plan $fx
        @($plan.Existing | ForEach-Object { $_.Game.Title }) | Should -Be @('Time Crisis 4')
        $plan.Exact.Count | Should -Be 0
        $replacePlan = Get-Lb424Plan $fx -Replace
        $replacePlan.Exact.Count | Should -Be 1
    }

    # With the game list, a picture counts for a game when it is the same game by ID: a name the game's ID is also known by is a sure
    # match, and a picture the shared engine reads as another game is never used.
    It 'uses another name of the same game ID as a sure match (the ID, not the spelling)' {
        # Mutation: ignore the ID names -> TC4.png is not found and the game has no picture.
        $fx = New-Lb424Fixture
        New-Lb424GameList $fx
        Remove-Item -LiteralPath (Join-Path $fx.Pics 'time-crisis_4.png')
        $xml = [System.IO.File]::ReadAllText((Join-Path $fx.Lb 'Data\Platforms\TeknoParrot.xml')).Replace('<Title>Time Crisis 4</Title>', '<Title>Time Crisis 4</Title><DatabaseID>41</DatabaseID>')
        [System.IO.File]::WriteAllText((Join-Path $fx.Lb 'Data\Platforms\TeknoParrot.xml'), $xml)
        [System.IO.File]::WriteAllBytes((Join-Path $fx.Pics 'TC4.png'), [byte[]](4, 4))
        $plan = Get-Lb424Plan $fx -WithGameList
        $tc = @($plan.Exact | Where-Object { $_.Game.Title -eq 'Time Crisis 4' })
        $tc.Count | Should -Be 1
        [System.IO.Path]::GetFileName($tc[0].Image) | Should -BeExactly 'TC4.png'
        # By name alone the picture is not found.
        @((Get-Lb424Plan $fx).Exact | Where-Object { $_.Game.Title -eq 'Time Crisis 4' }).Count | Should -Be 0
    }

    It 'never uses a picture the engine reads as a different game, even with the same name' {
        # Mutation: skip the ID check -> the picture of the original Frogger is used for the Raw Thrills game.
        $fx = New-Lb424Fixture
        New-Lb424GameList $fx
        Remove-Item -LiteralPath (Join-Path $fx.Pics 'time-crisis_4.png')
        $xml = [System.IO.File]::ReadAllText((Join-Path $fx.Lb 'Data\Platforms\TeknoParrot.xml')).Replace('<Title>Time Crisis 4</Title>', '<Title>Frogger</Title><DatabaseID>62</DatabaseID>')
        [System.IO.File]::WriteAllText((Join-Path $fx.Lb 'Data\Platforms\TeknoParrot.xml'), $xml)
        [System.IO.File]::WriteAllBytes((Join-Path $fx.Pics 'Frogger.png'), [byte[]](6, 6))
        $plan = Get-Lb424Plan $fx -WithGameList
        @($plan.Exact | Where-Object { $_.Game.Title -eq 'Frogger' }).Count | Should -Be 0
        @($plan.Near | Where-Object { $_.Game.Title -eq 'Frogger' }).Count | Should -Be 0
        # Without the game list only the name is known, so the picture is offered as a sure match (the old behavior).
        @((Get-Lb424Plan $fx).Exact | Where-Object { $_.Game.Title -eq 'Frogger' }).Count | Should -Be 1
    }
}

Describe 'LB424: copy and undo' {
    BeforeEach { Mock Write-Log {} }

    It 'copies exactly the selected pictures and changes nothing else' {
        # Mutation: also copy near matches or touch LaunchBox data -> the file list differs from the preview.
        $fx = New-Lb424Fixture
        $plan = Get-Lb424Plan $fx
        $dataBefore = Get-Lb424Snapshot (Join-Path $fx.Lb 'Data')
        $r = Invoke-TpmLaunchBoxMediaImport -lbRoot $fx.Lb -Selected @($plan.Exact) -BackupRoot $fx.Backups
        $r.Outcome | Should -BeExactly 'SAVED'
        $r.AddedCount | Should -Be 1
        $copied = Join-Path $fx.Lb 'Images\TeknoParrot\Clear Logo\Time Crisis 4-01.png'
        [System.IO.File]::ReadAllBytes($copied) | Should -Be ([byte[]](1, 2, 3, 4))
        @(Get-ChildItem -LiteralPath (Join-Path $fx.Lb 'Images') -Recurse -File).Count | Should -Be 1
        (Get-Lb424Snapshot (Join-Path $fx.Lb 'Data')) | Should -Be $dataBefore
        Test-Path -LiteralPath (Join-Path $fx.Pics 'time-crisis_4.png') | Should -BeTrue
    }

    It 'copies a near match only when the caller passes it as confirmed' {
        # Mutation: copy every candidate found by the plan -> the unconfirmed near picture appears.
        $fx = New-Lb424Fixture
        $plan = Get-Lb424Plan $fx
        $null = Invoke-TpmLaunchBoxMediaImport -lbRoot $fx.Lb -Selected @($plan.Exact) -BackupRoot $fx.Backups
        Test-Path -LiteralPath (Join-Path $fx.Lb 'Images\TeknoParrot\Clear Logo\Ghost Squad Evolution-01.png') | Should -BeFalse
        $cand = $plan.Near[0].Candidates[0]
        $r = Invoke-TpmLaunchBoxMediaImport -lbRoot $fx.Lb -BackupRoot $fx.Backups -Selected @([pscustomobject]@{ Game = $plan.Near[0].Game; Image = $cand.Image; Dest = $cand.Dest })
        $r.AddedCount | Should -Be 1
        [System.IO.File]::ReadAllBytes((Join-Path $fx.Lb 'Images\TeknoParrot\Clear Logo\Ghost Squad Evolution-01.png')) | Should -Be ([byte[]](5, 6, 7, 8))
    }

    It 'keeps an existing picture that appeared after the preview' {
        # Mutation: overwrite without checking -> the existing bytes change.
        $fx = New-Lb424Fixture
        $plan = Get-Lb424Plan $fx
        $dir = Join-Path $fx.Lb 'Images\TeknoParrot\Clear Logo'
        [void][System.IO.Directory]::CreateDirectory($dir)
        $mine = Join-Path $dir 'Time Crisis 4-01.jpg'
        [System.IO.File]::WriteAllBytes($mine, [byte[]](7, 7, 7))
        $r = Invoke-TpmLaunchBoxMediaImport -lbRoot $fx.Lb -Selected @($plan.Exact) -BackupRoot $fx.Backups
        $r.AddedCount | Should -Be 0
        $r.SkippedCount | Should -Be 1
        [System.IO.File]::ReadAllBytes($mine) | Should -Be ([byte[]](7, 7, 7))
        @(Get-ChildItem -LiteralPath $dir -File).Count | Should -Be 1
    }

    It 'undo removes only what the import added and removes folders it created' {
        # Mutation: delete the whole Clear Logo folder -> the user's own picture disappears.
        $fx = New-Lb424Fixture
        $dir = Join-Path $fx.Lb 'Images\TeknoParrot\Clear Logo'
        [void][System.IO.Directory]::CreateDirectory($dir)
        $users = Join-Path $dir 'Other Game-01.png'
        [System.IO.File]::WriteAllBytes($users, [byte[]](3, 3))
        $plan = Get-Lb424Plan $fx
        $null = Invoke-TpmLaunchBoxMediaImport -lbRoot $fx.Lb -Selected @($plan.Exact) -BackupRoot $fx.Backups
        $u = Invoke-TpmLaunchBoxMediaUndo -lbRoot $fx.Lb -BackupRoot $fx.Backups
        $u.Outcome | Should -BeExactly 'SAVED'
        $u.Removed | Should -Be 1
        Test-Path -LiteralPath (Join-Path $dir 'Time Crisis 4-01.png') | Should -BeFalse
        [System.IO.File]::ReadAllBytes($users) | Should -Be ([byte[]](3, 3))
    }

    It 'undo removes the folders the import created and leaves the library as it was' {
        # Mutation: never remove created folders -> the snapshot (which lists files only) still matches, so also check the folder.
        $fx = New-Lb424Fixture
        $before = Get-Lb424Snapshot $fx.Root
        $plan = Get-Lb424Plan $fx
        $null = Invoke-TpmLaunchBoxMediaImport -lbRoot $fx.Lb -Selected @($plan.Exact) -BackupRoot $fx.Backups
        $null = Invoke-TpmLaunchBoxMediaUndo -lbRoot $fx.Lb -BackupRoot $fx.Backups
        Test-Path -LiteralPath (Join-Path $fx.Lb 'Images') | Should -BeFalse
        (Get-Lb424Snapshot $fx.Root) | Should -Be $before
    }

    It 'undo keeps a picture that was changed after the import and says so' {
        # Mutation: delete by path without comparing bytes -> the user's edited picture is deleted.
        $fx = New-Lb424Fixture
        $plan = Get-Lb424Plan $fx
        $null = Invoke-TpmLaunchBoxMediaImport -lbRoot $fx.Lb -Selected @($plan.Exact) -BackupRoot $fx.Backups
        $copied = Join-Path $fx.Lb 'Images\TeknoParrot\Clear Logo\Time Crisis 4-01.png'
        [System.IO.File]::WriteAllBytes($copied, [byte[]](42, 42))
        $u = Invoke-TpmLaunchBoxMediaUndo -lbRoot $fx.Lb -BackupRoot $fx.Backups
        $u.Outcome | Should -BeExactly 'PARTIAL'
        @($u.Kept).Count | Should -Be 1
        [System.IO.File]::ReadAllBytes($copied) | Should -Be ([byte[]](42, 42))
    }

    It 'a replaced picture is saved first and undo puts it back' {
        # Mutation: replace without saving the old picture -> undo cannot restore the old bytes.
        $fx = New-Lb424Fixture
        $dir = Join-Path $fx.Lb 'Images\TeknoParrot\Clear Logo'
        [void][System.IO.Directory]::CreateDirectory($dir)
        $old = Join-Path $dir 'Time Crisis 4-01.png'
        [System.IO.File]::WriteAllBytes($old, [byte[]](0, 0, 0))
        $plan = Get-Lb424Plan $fx -Replace
        $r = Invoke-TpmLaunchBoxMediaImport -lbRoot $fx.Lb -Selected @($plan.Exact) -BackupRoot $fx.Backups -ReplaceExisting
        $r.ReplacedCount | Should -Be 1
        [System.IO.File]::ReadAllBytes($old) | Should -Be ([byte[]](1, 2, 3, 4))
        $u = Invoke-TpmLaunchBoxMediaUndo -lbRoot $fx.Lb -BackupRoot $fx.Backups
        $u.Outcome | Should -BeExactly 'SAVED'
        [System.IO.File]::ReadAllBytes($old) | Should -Be ([byte[]](0, 0, 0))
    }

    It 'a failure part-way removes everything that was already copied' {
        # Mutation: no rollback on failure -> the first picture stays in LaunchBox.
        $fx = New-Lb424Fixture
        $plan = Get-Lb424Plan $fx
        $good = $plan.Exact[0]
        $bad = [pscustomobject]@{ Game = $good.Game; Image = (Join-Path $fx.Pics 'missing.png'); Dest = (Join-Path $fx.Lb 'Images\TeknoParrot\Clear Logo\Gone-01.png') }
        $r = Invoke-TpmLaunchBoxMediaImport -lbRoot $fx.Lb -Selected @($good, $bad) -BackupRoot $fx.Backups
        $r.Outcome | Should -BeExactly 'FAILED'
        Test-Path -LiteralPath (Join-Path $fx.Lb 'Images') | Should -BeFalse
    }

    It 'refuses a destination outside the LaunchBox pictures folder' {
        # Mutation: skip the path check -> a file lands outside Images.
        $fx = New-Lb424Fixture
        $plan = Get-Lb424Plan $fx
        $evil = [pscustomobject]@{ Game = $plan.Exact[0].Game; Image = $plan.Exact[0].Image; Dest = (Join-Path $fx.Lb 'Data\evil-01.png') }
        $r = Invoke-TpmLaunchBoxMediaImport -lbRoot $fx.Lb -Selected @($evil) -BackupRoot $fx.Backups
        $r.Outcome | Should -BeExactly 'FAILED'
        Test-Path -LiteralPath (Join-Path $fx.Lb 'Data\evil-01.png') | Should -BeFalse
    }

    It 'contains no way to download anything' {
        # Mutation: any web call added to the import code.
        $script:Lb424ImportText | Should -Not -Match 'Invoke-WebRequest|Invoke-RestMethod|WebClient|HttpClient|Start-BitsTransfer|https?://'
    }
}

Describe 'LB424: the screen step' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-TpmText {}
        Mock Write-TpmOutcome {}
        Mock Show-TpmDetailBlocks {}
        Mock Get-TpmLbMediaImportsRoot { Join-Path $script:Lb424Fx.Root 'Imports' }
    }

    It 'does nothing in Unattended or preview runs' {
        # Mutation: remove the guards -> a prompt is shown.
        Mock Read-TpmChoice { 'I' }
        Mock Read-HostSafe { 'x' }
        Invoke-TpmLaunchBoxMediaStep -lbRoot 'C:\nope' -userProfilesDir 'C:\nope' -Unattended
        Invoke-TpmLaunchBoxMediaStep -lbRoot 'C:\nope' -userProfilesDir 'C:\nope' -DryRun
        Should -Invoke Read-TpmChoice -Times 0
    }

    It 'copies sure matches and skips a near match the user did not confirm' {
        # Mutation: answer-less near match applied -> the Ghost Squad picture exists after a "No".
        $fx = New-Lb424Fixture
        $script:Lb424Fx = $fx
        Mock Read-TpmChoice {
            if ($Prompt -like '*Choice*') { return 'I' }
            if ($Prompt -like '*Picture type*') { return '1' }
            return '1'
        }
        Mock Read-HostSafe { $script:Lb424Fx.Pics }
        Mock Read-TpmYesNo { if ($Prompt -like 'Is this the right*') { 'N' } else { 'Y' } }
        Invoke-TpmLaunchBoxMediaStep -lbRoot $fx.Lb -userProfilesDir $fx.Profiles
        Test-Path -LiteralPath (Join-Path $fx.Lb 'Images\TeknoParrot\Clear Logo\Time Crisis 4-01.png') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fx.Lb 'Images\TeknoParrot\Clear Logo\Ghost Squad Evolution-01.png') | Should -BeFalse
    }

    It 'copies a near match after the user says yes' {
        # Mutation: ignore the answer -> the near picture is missing after a "Yes".
        $fx = New-Lb424Fixture
        $script:Lb424Fx = $fx
        Mock Read-TpmChoice { if ($Prompt -like '*Choice*') { 'I' } else { '1' } }
        Mock Read-HostSafe { $script:Lb424Fx.Pics }
        Mock Read-TpmYesNo { 'Y' }
        Invoke-TpmLaunchBoxMediaStep -lbRoot $fx.Lb -userProfilesDir $fx.Profiles
        Test-Path -LiteralPath (Join-Path $fx.Lb 'Images\TeknoParrot\Clear Logo\Ghost Squad Evolution-01.png') | Should -BeTrue
    }

    It 'changes nothing when the final question is answered No' {
        # Mutation: copy before asking -> files exist after a "No".
        $fx = New-Lb424Fixture
        $script:Lb424Fx = $fx
        $before = Get-Lb424Snapshot $fx.Root
        Mock Read-TpmChoice { if ($Prompt -like '*Choice*') { 'I' } else { '1' } }
        Mock Read-HostSafe { $script:Lb424Fx.Pics }
        Mock Read-TpmYesNo { 'N' }
        Invoke-TpmLaunchBoxMediaStep -lbRoot $fx.Lb -userProfilesDir $fx.Profiles
        (Get-Lb424Snapshot $fx.Root) | Should -Be $before
    }
}
