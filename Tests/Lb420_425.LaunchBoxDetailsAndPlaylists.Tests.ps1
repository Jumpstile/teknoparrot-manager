#Requires -Module Pester

# Issues #420 and #421: LaunchBox game details (year, developer) and automatic playlists.
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.
# Everything lives under TestDrive with a made-up LaunchBox folder. The real LaunchBox is never touched and nothing is downloaded.
# Each It names the product change that makes it fail.
# What this CANNOT prove: that a real LaunchBox accepts the playlist files and the ReleaseYear field (only its own file format knowledge was used).

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'LB420 tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $stateText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] -and $args[0].Left.Extent.Text -match '^\$script:(TpmPlaylistMarker|TpmGameMakerNames)$' }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n"
    $script:Lb420File = Join-Path $TestDrive 'tpm-lb420-functions.ps1'
    [System.IO.File]::WriteAllText($script:Lb420File, ($stateText + "`r`n" + $functionText), (New-Object System.Text.UTF8Encoding $false))
    . $script:Lb420File
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')

    function New-Lb420Profile {
        param([string]$Dir, [string]$Code, [string]$GameFolder, [switch]$Gun, [switch]$Wheel)
        $buttons = if ($Wheel) { '<JoystickButtons><JoystickButtons><InputMapping>P1Wheel</InputMapping><AnalogType>Wheel</AnalogType></JoystickButtons></JoystickButtons>' } else { '<JoystickButtons />' }
        $xml = '<GameProfile><GamePath>D:\Games\{0}\game.exe</GamePath><GunGame>{1}</GunGame>{2}</GameProfile>' -f $GameFolder, $(if ($Gun) { 'true' } else { 'false' }), $buttons
        [System.IO.File]::WriteAllText((Join-Path $Dir ($Code + '.xml')), $xml)
    }

    function New-Lb420Game {
        param([string]$Id, [string]$Title, [string]$Code, [string]$Emulator = 'emu-1', [string]$Extra = '')
        return ('<Game><ID>{0}</ID><Title>{1}</Title><Platform>TeknoParrot</Platform><Emulator>{2}</Emulator><ApplicationPath>..\TP\UserProfiles\{3}.xml</ApplicationPath>{4}</Game>' -f $Id, $Title, $Emulator, $Code, $Extra)
    }

    # Three TeknoParrot games (a light gun game, a driving game, a plain Namco game) plus a game from another emulator.
    function New-Lb420Fixture {
        param([string]$ExtraGameXml = '')
        $root = Join-Path $TestDrive ('lb420-' + [guid]::NewGuid().ToString('N'))
        $lb = Join-Path $root 'LaunchBox'
        $profiles = Join-Path $root 'UserProfiles'
        [void][System.IO.Directory]::CreateDirectory((Join-Path $lb 'Data\Platforms'))
        [void][System.IO.Directory]::CreateDirectory($profiles)
        [System.IO.File]::WriteAllText((Join-Path $lb 'Data\Emulators.xml'), '<LaunchBox><Emulator><ID>emu-1</ID><Title>TeknoParrot</Title></Emulator></LaunchBox>')
        New-Lb420Profile -Dir $profiles -Code 'GhostSquad' -GameFolder 'Ghost Squad (2004)(JPN)[Sega Lindbergh][TP]' -Gun
        New-Lb420Profile -Dir $profiles -Code 'Outrun2' -GameFolder 'OutRun 2 (2008)(USA)[Sega Lindbergh][TP]' -Wheel
        New-Lb420Profile -Dir $profiles -Code 'Tekken' -GameFolder 'Tekken 6 (1998)(JPN, AG1 Ver.A)[Namco Super System 23][TP]'
        New-Lb420Profile -Dir $profiles -Code 'Other' -GameFolder 'Other (2001)[Sega Lindbergh][TP]'
        $games = (New-Lb420Game 'g1' 'Ghost Squad' 'GhostSquad') + (New-Lb420Game 'g2' 'OutRun 2' 'Outrun2') + (New-Lb420Game 'g3' 'Tekken 6' 'Tekken') + (New-Lb420Game 'g4' 'Not mine' 'Other' -Emulator 'emu-other') + $ExtraGameXml
        [System.IO.File]::WriteAllText((Join-Path $lb 'Data\Platforms\TeknoParrot.xml'), ('<LaunchBox>{0}</LaunchBox>' -f $games))
        return [pscustomobject]@{ Root = $lb; Profiles = $profiles; Backups = (Join-Path $root 'Backups'); Platform = (Join-Path $lb 'Data\Platforms\TeknoParrot.xml'); Playlists = (Join-Path $lb 'Data\Playlists') }
    }

    function Get-Lb420Hashes {
        param([string]$Root)
        $map = [ordered]@{}
        foreach ($f in @(Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName)) { $map[$f.FullName.Substring($Root.Length)] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash }
        return $map
    }

    function Invoke-Lb420 {
        param($Fixture, [switch]$PlanOnly)
        $result = Invoke-LaunchBoxEnrich -userProfilesDir $Fixture.Profiles -tpRoot 'C:\TP' -lbRoot $Fixture.Root -platformNames @('TeknoParrot') -BackupRoot $Fixture.Backups -PlanOnly:$PlanOnly
        if ($result.Outcome -eq 'FAILED') { throw ('LaunchBox step failed: ' + ($result.Errors -join '; ')) }
        return $result
    }

    function Get-Lb420Game {
        param($Fixture, [string]$Id)
        $doc = [xml][System.IO.File]::ReadAllText($Fixture.Platform)
        return $doc.SelectSingleNode("/LaunchBox/Game[ID='$Id']")
    }
}

Describe 'LB420/421: facts from the folder name' {
    It 'reads year, hardware and developer from the folder name' {
        # Mutation: drop the year pattern or the maker list -> year or developer comes back empty.
        $f = Get-TpmGameFolderFacts -GamePath 'D:\Games\Tekken 6 (1998)(JPN, AG1 Ver.A)[Namco Super System 23][TP]\bin\game.exe'
        $f.Year | Should -BeExactly '1998'
        $f.Hardware | Should -BeExactly 'Namco Super System 23'
        $f.Developer | Should -BeExactly 'Namco'
    }
    It 'invents nothing when the folder is not a TeknoParrot game folder or the maker is unknown' {
        # Mutation: fall back to the first word of the label as developer -> "Mystery" would be written.
        $none = Get-TpmGameFolderFacts -GamePath 'D:\Games\Some Folder\game.exe'
        "$($none.Year)$($none.Hardware)$($none.Developer)" | Should -BeExactly ''
        $unknown = Get-TpmGameFolderFacts -GamePath 'D:\Games\X (2010)[Mystery Board][TP]\game.exe'
        $unknown.Hardware | Should -BeExactly 'Mystery Board'
        $unknown.Developer | Should -BeExactly ''
    }
}

Describe 'LB420/421: details and playlists' {
    BeforeEach {
        Mock Write-Log {}
        Mock Test-LaunchBoxRunning { $false }
        Mock Wait-TpmForProcessClose { $true }
        Mock Write-TpmCompactExtractionProgress {}
    }

    It 'a preview changes nothing and lists what would change' {
        # Mutation: ignore -PlanOnly -> files change, a backup folder appears, or the result is not a preview.
        $fx = New-Lb420Fixture
        $before = Get-Lb420Hashes -Root $fx.Root
        $r = Invoke-Lb420 -Fixture $fx -PlanOnly
        $r.Reason | Should -BeExactly 'PREVIEW'
        $r.WouldChangeFiles | Should -BeGreaterThan 0
        $r.PlainTitle | Should -BeLike '*Nothing was changed*'
        (@($r.EnrichLines) -join "`n") | Should -Match 'Ghost Squad: will fill in year 2004, developer Sega'
        $after = Get-Lb420Hashes -Root $fx.Root
        ($after.Keys -join '|') | Should -BeExactly ($before.Keys -join '|')
        ($after.Values -join '|') | Should -BeExactly ($before.Values -join '|')
        Test-Path -LiteralPath $fx.Playlists | Should -BeFalse
        Test-Path -LiteralPath $fx.Backups | Should -BeFalse
    }

    It 'a write makes exactly the previewed changes, and only for TeknoParrot games' {
        # Mutation: also touch games of other emulators, or write a different file set than the preview counted.
        $fx = New-Lb420Fixture
        $preview = Invoke-Lb420 -Fixture $fx -PlanOnly
        $r = Invoke-Lb420 -Fixture $fx
        $r.Outcome | Should -BeExactly 'SAVED'
        @($r.ChangedPaths).Count | Should -Be $preview.WouldChangeFiles
        (@($r.EnrichLines) -join "`n") | Should -BeExactly (@($preview.EnrichLines) -join "`n")
        $r.BackupVerified | Should -BeTrue
        (Get-Lb420Game $fx 'g1').ReleaseYear | Should -BeExactly '2004'
        (Get-Lb420Game $fx 'g1').Developer | Should -BeExactly 'Sega'
        (Get-Lb420Game $fx 'g3').ReleaseYear | Should -BeExactly '1998'
        (Get-Lb420Game $fx 'g3').Developer | Should -BeExactly 'Namco'
        $other = Get-Lb420Game $fx 'g4'
        $other.SelectSingleNode('ReleaseYear') | Should -BeNullOrEmpty
        @(Get-ChildItem -LiteralPath $fx.Playlists -Filter '*.xml' | Select-Object -ExpandProperty BaseName | Sort-Object) | Should -Be @('Driving games', 'Light gun games', 'Namco Super System 23', 'Sega Lindbergh')
        $second = Invoke-Lb420 -Fixture $fx
        $second.Outcome | Should -BeExactly 'NO_CHANGES'
    }

    It 'never changes a field the user already filled in' {
        # Mutation: remove the "only when empty" check -> the user's own year and developer are overwritten.
        $extra = New-Lb420Game 'g5' 'Mine' 'Tekken' -Extra '<ReleaseYear>1999</ReleaseYear><Developer>My Studio</Developer>'
        $extra2 = New-Lb420Game 'g6' 'Dated' 'GhostSquad' -Extra '<ReleaseDate>2005-05-05T00:00:00-04:00</ReleaseDate>'
        $fx = New-Lb420Fixture -ExtraGameXml ($extra + $extra2)
        $r = Invoke-Lb420 -Fixture $fx
        $r.Outcome | Should -BeExactly 'SAVED'
        (Get-Lb420Game $fx 'g5').ReleaseYear | Should -BeExactly '1999'
        (Get-Lb420Game $fx 'g5').Developer | Should -BeExactly 'My Studio'
        (Get-Lb420Game $fx 'g6').SelectSingleNode('ReleaseYear') | Should -BeNullOrEmpty
        (Get-Lb420Game $fx 'g6').Developer | Should -BeExactly 'Sega'
    }

    It 'puts games in the right playlists using only tags the script already knows' {
        # Mutation: guess light gun or driving from the hardware name -> the plain Namco game lands in a wrong list.
        $fx = New-Lb420Fixture
        [void](Invoke-Lb420 -Fixture $fx)
        function Get-Ids($name) { return @(([xml][System.IO.File]::ReadAllText((Join-Path $fx.Playlists ($name + '.xml')))).SelectNodes('//PlaylistGame/GameId') | ForEach-Object { $_.InnerText } | Sort-Object) }
        (Get-Ids 'Sega Lindbergh') | Should -Be @('g1', 'g2')
        (Get-Ids 'Namco Super System 23') | Should -Be @('g3')
        (Get-Ids 'Light gun games') | Should -Be @('g1')
        (Get-Ids 'Driving games') | Should -Be @('g2')
        Test-Path -LiteralPath (Join-Path $fx.Playlists 'Needs setup.xml') | Should -BeFalse
    }

    It 'updates only playlists it made and leaves the user''s own playlist alone' {
        # Mutation: drop the marker check -> the user's own "Light gun games" playlist is rewritten.
        $fx = New-Lb420Fixture
        [void][System.IO.Directory]::CreateDirectory($fx.Playlists)
        $mine = Join-Path $fx.Playlists 'Light gun games.xml'
        [System.IO.File]::WriteAllText($mine, '<LaunchBox><Playlist><PlaylistId>mine</PlaylistId><Name>Light gun games</Name><Notes>my picks</Notes></Playlist></LaunchBox>')
        $hashBefore = (Get-FileHash -LiteralPath $mine).Hash
        $r = Invoke-Lb420 -Fixture $fx
        $r.Outcome | Should -BeExactly 'SAVED'
        (Get-FileHash -LiteralPath $mine).Hash | Should -BeExactly $hashBefore
        (@($r.EnrichLines) -join "`n") | Should -Match 'Light gun games: left alone'
        # One of its own playlists follows a new game; the other lists stay.
        $platform = [System.IO.File]::ReadAllText($fx.Platform).Replace('</LaunchBox>', ((New-Lb420Game 'g7' 'Ghost Squad 2' 'GhostSquad') + '</LaunchBox>'))
        [System.IO.File]::WriteAllText($fx.Platform, $platform)
        $again = Invoke-Lb420 -Fixture $fx
        $again.Outcome | Should -BeExactly 'SAVED'
        @(([xml][System.IO.File]::ReadAllText((Join-Path $fx.Playlists 'Sega Lindbergh.xml'))).SelectNodes('//PlaylistGame')).Count | Should -Be 3
        (Get-FileHash -LiteralPath $mine).Hash | Should -BeExactly $hashBefore
    }

    It 'undo through the existing restore puts every file back' {
        # Mutation: write without the backup step -> there is nothing to restore and the files stay changed.
        $fx = New-Lb420Fixture
        $before = Get-Lb420Hashes -Root $fx.Root
        $r = Invoke-Lb420 -Fixture $fx
        $r.Outcome | Should -BeExactly 'SAVED'
        (Get-Lb420Hashes -Root $fx.Root).Count | Should -BeGreaterThan $before.Count
        Mock Read-TpmChoice { '1' }
        Mock Read-TpmYesNo { 'Y' }
        Mock Write-Host {}
        $undo = Invoke-RestoreLaunchBoxBackup -lbRoot $fx.Root -BackupRoot $fx.Backups
        $undo.Outcome | Should -BeIn @('SAVED', 'PARTIAL')
        $after = Get-Lb420Hashes -Root $fx.Root
        foreach ($key in $before.Keys) { $after[$key] | Should -BeExactly $before[$key] }
        @($after.Keys | Where-Object { $_ -like '*Playlists*' }).Count | Should -Be 0
    }
}
