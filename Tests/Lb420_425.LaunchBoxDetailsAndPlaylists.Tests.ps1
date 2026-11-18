#Requires -Module Pester

# Issues #420 and #421: LaunchBox game details (year, developer) and automatic playlists.
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.
# Everything lives under TestDrive with a made-up LaunchBox folder. The real LaunchBox is never touched and nothing is downloaded.
# Each It names the product change that makes it fail.
# What this CANNOT prove: that a real LaunchBox accepts the playlist files and the ReleaseDate field (the file shapes were read from a real LaunchBox library, but no real LaunchBox ever opened these files).

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'LB420 tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:Lb420File = Join-Path $TestDrive 'tpm-lb420-functions.ps1'
    [System.IO.File]::WriteAllText($script:Lb420File, $functionText, (New-Object System.Text.UTF8Encoding $false))
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
        param($Fixture, [switch]$PlanOnly, [hashtable]$DatIndex = $null, [hashtable]$Choices = @{}, [string]$Default = 'Skip')
        $result = Invoke-TpmLaunchBoxEnrich -UserProfilesDir $Fixture.Profiles -LbRoot $Fixture.Root -PlatformNames @('TeknoParrot') -BackupRoot $Fixture.Backups -DatIndex $DatIndex -ConflictChoices $Choices -ConflictDefault $Default -PlanOnly:$PlanOnly
        if ($result.Outcome -eq 'FAILED') { throw ('LaunchBox step failed: ' + ($result.Errors -join '; ')) }
        return $result
    }

    function New-Lb420Dat {
        param([object[]]$Entries)
        $dat = @{}
        foreach ($e in $Entries) { $dat[(Get-NormalizedGameKey $e.Name)] = [pscustomobject]@{ ProfileCode = $e.Code; Executable = 'game.exe'; OriginalName = $e.Name } }
        return $dat
    }
    function Get-Lb420Game {
        param($Fixture, [string]$Id)
        $doc = [xml][System.IO.File]::ReadAllText($Fixture.Platform)
        return $doc.SelectSingleNode("/LaunchBox/Game[ID='$Id']")
    }
}

Describe 'LB420/421: facts from a game name' {
    It 'reads year, hardware and developer from the folder name' {
        # Mutation: drop the year pattern or the maker list -> year or developer comes back empty.
        $f = Get-TpmLaunchBoxNameFacts -Name 'Tekken 6 (1998)(JPN, AG1 Ver.A)[Namco Super System 23][TP]'
        $f.Year | Should -BeExactly '1998'
        $f.Hardware | Should -BeExactly 'Namco Super System 23'
        $f.Developer | Should -BeExactly 'Namco'
    }
    It 'invents nothing when the folder is not a TeknoParrot game folder or the maker is unknown' {
        # Mutation: fall back to the first word of the label as developer -> "Mystery" would be written.
        $none = Get-TpmLaunchBoxNameFacts -Name 'Some Folder'
        "$($none.Year)$($none.Hardware)$($none.Developer)" | Should -BeExactly ''
        $unknown = Get-TpmLaunchBoxNameFacts -Name 'X (2010)[Mystery Board][TP]'
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
        (Format-TpmLaunchBoxEnrichTitle -Plan $r.EnrichPlan -Preview) | Should -BeLike '*Nothing was changed*'
        (@(Format-TpmLaunchBoxEnrichLine -Plan $r.EnrichPlan) -join "`n") | Should -Match 'Ghost Squad: will fill in year 2004, developer Sega'
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
        (@(Format-TpmLaunchBoxEnrichLine -Plan $r.EnrichPlan) -join "`n") | Should -BeExactly (@(Format-TpmLaunchBoxEnrichLine -Plan $preview.EnrichPlan) -join "`n")
        $r.BackupVerified | Should -BeTrue
        (Get-Lb420Game $fx 'g1').ReleaseDate | Should -BeExactly '2004-01-01'
        (Get-Lb420Game $fx 'g1').Developer | Should -BeExactly 'Sega'
        (Get-Lb420Game $fx 'g3').ReleaseDate | Should -BeExactly '1998-01-01'
        (Get-Lb420Game $fx 'g3').Developer | Should -BeExactly 'Namco'
        $other = Get-Lb420Game $fx 'g4'
        $other.SelectSingleNode('ReleaseDate') | Should -BeNullOrEmpty
        @(Get-ChildItem -LiteralPath $fx.Playlists -Filter '*.xml' | Select-Object -ExpandProperty BaseName | Sort-Object) | Should -Be @('Driving games', 'Light gun games', 'Namco Super System 23', 'Sega Lindbergh')
        $second = Invoke-Lb420 -Fixture $fx
        $second.Outcome | Should -BeExactly 'NO_CHANGES'
    }

    It 'never changes a field the user already filled in' {
        # Mutation: remove the "only when empty" check -> the user's own year and developer are overwritten.
        $extra = New-Lb420Game 'g5' 'Mine' 'Tekken' -Extra '<ReleaseDate>1999-06-07</ReleaseDate><Developer>My Studio</Developer>'
        $extra2 = New-Lb420Game 'g6' 'Dated' 'GhostSquad' -Extra '<ReleaseDate>2005-05-05T00:00:00-04:00</ReleaseDate>'
        $fx = New-Lb420Fixture -ExtraGameXml ($extra + $extra2)
        $r = Invoke-Lb420 -Fixture $fx
        $r.Outcome | Should -BeExactly 'SAVED'
        (Get-Lb420Game $fx 'g5').ReleaseDate | Should -BeExactly '1999-06-07'
        (Get-Lb420Game $fx 'g5').Developer | Should -BeExactly 'My Studio'
        (Get-Lb420Game $fx 'g6').ReleaseDate | Should -BeExactly '2005-05-05T00:00:00-04:00'
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
        (@(Format-TpmLaunchBoxEnrichLine -Plan $r.EnrichPlan) -join "`n") | Should -Match 'Light gun games: left alone'
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

Describe 'LB420/421: Eggman DAT as a second source' {
    BeforeEach {
        Mock Write-Log {}
        Mock Test-LaunchBoxRunning { $false }
        Mock Wait-TpmForProcessClose { $true }
        Mock Write-TpmCompactExtractionProgress {}
    }



    It 'fills a detail from the DAT when the folder name has none, and stays quiet when both agree' {
        # Mutation: ignore the DAT -> the bare folder gets no year; or flag equal values as a conflict.
        $fx = New-Lb420Fixture
        New-Lb420Profile -Dir $fx.Profiles -Code 'Bare' -GameFolder 'Bare Game[TP]'
        [System.IO.File]::WriteAllText($fx.Platform, [System.IO.File]::ReadAllText($fx.Platform).Replace('</LaunchBox>', ((New-Lb420Game 'g8' 'Bare Game' 'Bare') + '</LaunchBox>')))
        $dat = New-Lb420Dat @(
            @{ Code = 'Bare'; Name = 'Bare Game (2010)(USA)[Sega Lindbergh][TP]' },
            @{ Code = 'GhostSquad'; Name = 'Ghost Squad (2004)(JPN)[Sega Lindbergh][TP]' })
        $r = Invoke-Lb420 -Fixture $fx -PlanOnly -DatIndex $dat
        @($r.EnrichPlan.Conflicts).Count | Should -Be 0
        $w = Invoke-Lb420 -Fixture $fx -DatIndex $dat
        $w.Outcome | Should -BeExactly 'SAVED'
        (Get-Lb420Game $fx 'g8').ReleaseDate | Should -BeExactly '2010-01-01'
        (Get-Lb420Game $fx 'g8').Developer | Should -BeExactly 'Sega'
        (Get-Lb420Game $fx 'g1').ReleaseDate | Should -BeExactly '2004-01-01'
    }

    It 'shows both values when the sources disagree and writes nothing for that detail unless chosen' {
        # Mutation: pick one source silently -> the year is written without a choice, or the preview hides one value.
        $fx = New-Lb420Fixture
        $dat = New-Lb420Dat @(@{ Code = 'Outrun2'; Name = 'OutRun 2 (2007)(USA)[Sega Lindbergh][TP]' })
        $r = Invoke-Lb420 -Fixture $fx -PlanOnly -DatIndex $dat
        @($r.EnrichPlan.Conflicts).Count | Should -Be 1
        $line = (@(Format-TpmLaunchBoxEnrichLine -Plan $r.EnrichPlan) -join "`n")
        $line | Should -Match 'Folder name says 2008'
        $line | Should -Match 'Eggman list says 2007'
        $w = Invoke-Lb420 -Fixture $fx -DatIndex $dat
        $w.Outcome | Should -BeExactly 'SAVED'
        (Get-Lb420Game $fx 'g2').SelectSingleNode('ReleaseDate') | Should -BeNullOrEmpty
        (Get-Lb420Game $fx 'g2').Developer | Should -BeExactly 'Sega'
    }

    It 'uses the source the user chose, for one detail or for all' {
        # Mutation: ignore the choice -> the year stays empty or the wrong source wins.
        $fx = New-Lb420Fixture
        $dat = New-Lb420Dat @(@{ Code = 'Outrun2'; Name = 'OutRun 2 (2007)(USA)[Sega Lindbergh][TP]' })
        $one = Invoke-Lb420 -Fixture $fx -PlanOnly -DatIndex $dat -Choices @{ 'g2|Year' = 'Dat' }
        @($one.EnrichPlan.Conflicts)[0].Applied | Should -BeExactly '2007'
        [void](Invoke-Lb420 -Fixture $fx -DatIndex $dat -Default 'Folder')
        (Get-Lb420Game $fx 'g2').ReleaseDate | Should -BeExactly '2008-01-01'
        $fx2 = New-Lb420Fixture
        [void](Invoke-Lb420 -Fixture $fx2 -DatIndex $dat -Default 'Dat')
        (Get-Lb420Game $fx2 'g2').ReleaseDate | Should -BeExactly '2007-01-01'
    }

    It 'ignores a DAT entry that belongs to a different profile' {
        # Mutation: match by name only -> another game's year lands on this one.
        $fx = New-Lb420Fixture
        $dat = New-Lb420Dat @(@{ Code = 'SomethingElse'; Name = 'OutRun 2 (2007)(USA)[Sega Lindbergh][TP]' })
        $r = Invoke-Lb420 -Fixture $fx -PlanOnly -DatIndex $dat
        @($r.EnrichPlan.Conflicts).Count | Should -Be 0
    }
}

# The shapes below were read from a real LaunchBox library (Data\Playlists and Data\Platforms\TeknoParrot.xml): a manual playlist has one Playlist
# element followed by PlaylistGame siblings (GameId, GameTitle, GameFileName, GamePlatform, ManualOrder, LaunchBoxDbId), and a game's release is
# <ReleaseDate>yyyy-MM-dd</ReleaseDate> (there is no ReleaseYear tag; LaunchBox stores a year alone as yyyy-01-01).
Describe 'LB420/421: the real LaunchBox file format' {
    BeforeEach {
        Mock Write-Log {}
        Mock Test-LaunchBoxRunning { $false }
        Mock Wait-TpmForProcessClose { $true }
        Mock Write-TpmCompactExtractionProgress {}
    }

    BeforeAll {
        $script:RealPlaylistTags = @('PlaylistId', 'Name', 'NestedName', 'SortBy', 'Notes', 'VideoPath', 'ImageType', 'Category', 'LastGameId', 'BigBoxView', 'BigBoxTheme', 'IncludeWithPlatforms', 'AutoPopulate', 'SortTitle', 'IsAutogenerated', 'LastSelectedChild')
        $script:RealGameTags = @('GameId', 'GameTitle', 'GameFileName', 'GamePlatform', 'ManualOrder', 'LaunchBoxDbId')
    }

    It 'writes the year as ReleaseDate yyyy-01-01 and never a ReleaseYear tag' {
        # Mutation: write a ReleaseYear field again -> LaunchBox ignores it and the year never shows.
        $fx = New-Lb420Fixture
        [void](Invoke-Lb420 -Fixture $fx)
        $g1 = Get-Lb420Game $fx 'g1'
        $g1.ReleaseDate | Should -BeExactly '2004-01-01'
        $g1.SelectSingleNode('ReleaseYear') | Should -BeNullOrEmpty
        (@(Format-TpmLaunchBoxEnrichLine -Plan (Invoke-Lb420 -Fixture (New-Lb420Fixture) -PlanOnly).EnrichPlan) -join "`n") | Should -Not -Match '01-01'
    }

    It 'saves a platform file that starts with the XML header and a Windows line break, as a real LaunchBox library does' {
        # Mutation: write the line break after the XML header as &#xD; (NewLineHandling Entitize on the whole document) -> the staged file cannot be read back and the write is refused.
        $fx = New-Lb420Fixture
        $plain = [System.IO.File]::ReadAllText($fx.Platform)
        [System.IO.File]::WriteAllText($fx.Platform, ('<?xml version="1.0" encoding="utf-8"?>' + "`r`n" + $plain), (New-Object System.Text.UTF8Encoding $false))
        $w = Invoke-Lb420 -Fixture $fx
        $w.Outcome | Should -BeExactly 'SAVED'
        (Get-Lb420Game $fx 'g1').ReleaseDate | Should -BeExactly '2004-01-01'
        [System.IO.File]::ReadAllText($fx.Platform) | Should -Not -Match '&#xD;<'
    }

    It 'keeps a release date the user or LaunchBox already has, even a full one' {
        # Mutation: overwrite a filled ReleaseDate with yyyy-01-01 -> the exact day is lost.
        $extra = New-Lb420Game 'g5' 'Full date' 'Tekken' -Extra '<ReleaseDate>2006-02-03</ReleaseDate>'
        $fx = New-Lb420Fixture -ExtraGameXml $extra
        [void](Invoke-Lb420 -Fixture $fx)
        (Get-Lb420Game $fx 'g5').ReleaseDate | Should -BeExactly '2006-02-03'
        (Get-Lb420Game $fx 'g5').Developer | Should -BeExactly 'Namco'
    }

    It 'writes a manual playlist with every tag LaunchBox writes, and the games beside it, not inside it' {
        # Mutation: nest PlaylistGame inside Playlist, or leave out the fields -> LaunchBox shows an empty playlist.
        $fx = New-Lb420Fixture -ExtraGameXml (New-Lb420Game 'g9' 'With id' 'GhostSquad' -Extra '<DatabaseID>31460</DatabaseID>')
        [void](Invoke-Lb420 -Fixture $fx)
        $doc = [xml][System.IO.File]::ReadAllText((Join-Path $fx.Playlists 'Sega Lindbergh.xml'))
        $doc.DocumentElement.Name | Should -BeExactly 'LaunchBox'
        @($doc.SelectNodes('/LaunchBox/Playlist')).Count | Should -Be 1
        @($doc.SelectNodes('/LaunchBox/Playlist/PlaylistGame')).Count | Should -Be 0
        @($doc.SelectNodes('/LaunchBox/PlaylistGame')).Count | Should -Be 3
        $list = $doc.SelectSingleNode('/LaunchBox/Playlist')
        (@($list.ChildNodes | ForEach-Object { $_.Name }) -join '|') | Should -BeExactly ($script:RealPlaylistTags -join '|')
        $list.AutoPopulate | Should -BeExactly 'false'
        $list.IsAutogenerated | Should -BeExactly 'false'
        $list.SelectSingleNode('Name').InnerText | Should -BeExactly 'Sega Lindbergh'
        $list.Notes | Should -BeExactly (Get-TpmLaunchBoxPlaylistMarker)
        $first = $doc.SelectSingleNode("/LaunchBox/PlaylistGame[GameId='g1']")
        (@($first.ChildNodes | ForEach-Object { $_.Name }) -join '|') | Should -BeExactly ('GameId|GameTitle|GameFileName|GamePlatform|ManualOrder')
        $first.GameFileName | Should -BeExactly 'GhostSquad.xml'
        $first.GamePlatform | Should -BeExactly 'TeknoParrot'
        $first.ManualOrder | Should -BeExactly '0'
        $withId = $doc.SelectSingleNode("/LaunchBox/PlaylistGame[GameId='g9']")
        $withId.LaunchBoxDbId | Should -BeExactly '31460'
        foreach ($tag in @($doc.SelectNodes('/LaunchBox/PlaylistGame/*') | ForEach-Object { $_.Name } | Sort-Object -Unique)) { $script:RealGameTags | Should -Contain $tag }
    }

    It 'a real-format sample playlist and game parse and round-trip without a change' {
        # Mutation: rewrite an up-to-date Manager playlist on every run -> the file changes although nothing did.
        $marker = Get-TpmLaunchBoxPlaylistMarker
        $sample = '<?xml version="1.0" standalone="yes"?><LaunchBox><Playlist><PlaylistId>fcfe4489-857c-4746-975b-47a44df05064</PlaylistId><Name>Sega Lindbergh</Name><NestedName>Sega Lindbergh</NestedName><SortBy>Default</SortBy><Notes>' + $marker + '</Notes><VideoPath /><ImageType>Boxes</ImageType><Category /><LastGameId /><BigBoxView /><BigBoxTheme /><IncludeWithPlatforms>false</IncludeWithPlatforms><AutoPopulate>false</AutoPopulate><SortTitle /><IsAutogenerated>false</IsAutogenerated><LastSelectedChild /></Playlist>' +
            '<PlaylistGame><GameId>g1</GameId><GameTitle>Ghost Squad</GameTitle><GameFileName>GhostSquad.xml</GameFileName><GamePlatform>TeknoParrot</GamePlatform><ManualOrder>0</ManualOrder><LaunchBoxDbId>31460</LaunchBoxDbId></PlaylistGame>' +
            '<PlaylistGame><GameId>g2</GameId><GameTitle>OutRun 2</GameTitle><GameFileName>Outrun2.xml</GameFileName><GamePlatform>TeknoParrot</GamePlatform><ManualOrder>1</ManualOrder></PlaylistGame></LaunchBox>'
        $doc = New-Object System.Xml.XmlDocument
        $doc.LoadXml($sample)
        $games = @([pscustomobject]@{ Id = 'g1'; Title = 'Ghost Squad'; Platform = 'TeknoParrot'; FileName = 'GhostSquad.xml'; DbId = '31460' }, [pscustomobject]@{ Id = 'g2'; Title = 'OutRun 2'; Platform = 'TeknoParrot'; FileName = 'Outrun2.xml'; DbId = '' })
        $before = $doc.OuterXml
        $outcome = Update-TpmLaunchBoxPlaylistDocument -Doc $doc -Name 'Sega Lindbergh' -Games $games -Exists $true
        $outcome.Skipped | Should -BeFalse
        $outcome.Changed | Should -BeFalse
        $doc.OuterXml | Should -BeExactly $before
        # A third game is added as a sibling and the order numbers follow the list.
        $more = $games + [pscustomobject]@{ Id = 'g3'; Title = 'Third'; Platform = 'TeknoParrot'; FileName = 'Third.xml'; DbId = '' }
        $outcome = Update-TpmLaunchBoxPlaylistDocument -Doc $doc -Name 'Sega Lindbergh' -Games $more -Exists $true
        $outcome.Changed | Should -BeTrue
        @($doc.SelectNodes('/LaunchBox/PlaylistGame/ManualOrder') | ForEach-Object { $_.InnerText }) | Should -Be @('0', '1', '2')
        # A real game block with a full date and no year tag keeps every child it had.
        $game = New-Object System.Xml.XmlDocument
        $game.LoadXml('<Game><ID>g1</ID><Title>Gigawing</Title><Developer>Takumi</Developer><ReleaseDate>2006-02-03</ReleaseDate><DatabaseID>31460</DatabaseID><CommunityStarRating>4.03125</CommunityStarRating></Game>')
        (Set-TpmLaunchBoxFieldIfEmpty -Node $game.DocumentElement -Field 'ReleaseDate' -Value '2006-01-01') | Should -BeFalse
        (Set-TpmLaunchBoxFieldIfEmpty -Node $game.DocumentElement -Field 'Developer' -Value 'Other') | Should -BeFalse
        $game.DocumentElement.ChildNodes.Count | Should -Be 6
        $game.DocumentElement.ReleaseDate | Should -BeExactly '2006-02-03'
    }

    It 'moves games an older version wrote inside the Playlist element out beside it' {
        # Mutation: leave the nested games -> LaunchBox never sees them.
        $marker = Get-TpmLaunchBoxPlaylistMarker
        $doc = New-Object System.Xml.XmlDocument
        $doc.LoadXml('<LaunchBox><Playlist><PlaylistId>x</PlaylistId><Name>Sega Lindbergh</Name><NestedName>Sega Lindbergh</NestedName><Notes>' + $marker + '</Notes><PlaylistGame><GameId>g1</GameId><GameTitle>Ghost Squad</GameTitle></PlaylistGame></Playlist></LaunchBox>')
        $games = @([pscustomobject]@{ Id = 'g1'; Title = 'Ghost Squad'; Platform = 'TeknoParrot'; FileName = 'GhostSquad.xml'; DbId = '' })
        $outcome = Update-TpmLaunchBoxPlaylistDocument -Doc $doc -Name 'Sega Lindbergh' -Games $games -Exists $true
        $outcome.Changed | Should -BeTrue
        @($doc.SelectNodes('/LaunchBox/Playlist/PlaylistGame')).Count | Should -Be 0
        @($doc.SelectNodes('/LaunchBox/PlaylistGame')).Count | Should -Be 1
        $doc.SelectSingleNode('/LaunchBox/Playlist/PlaylistId').InnerText | Should -BeExactly 'x'
        $doc.SelectSingleNode('/LaunchBox/Playlist/AutoPopulate').InnerText | Should -BeExactly 'false'
    }
}
