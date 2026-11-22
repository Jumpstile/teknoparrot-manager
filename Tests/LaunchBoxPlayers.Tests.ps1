#Requires -Module Pester

# Issue #267 (RC9): LaunchBox players and controllers for TeknoParrot games (the boxes Big Box shows).
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.
# Everything lives under TestDrive with a made-up LaunchBox folder. The real LaunchBox is never touched.
# The field names and values the code writes (MaxPlayers, PlayMode, GameControllerSupport with ControllerId, GameId and SupportLevel,
# and Data\GameControllers.xml) were read from a real LaunchBox library; the fixtures copy that shape.
# Each It names the product change that makes it fail.
# What this CANNOT prove: that a real LaunchBox shows the boxes in Big Box (the owner test plan has one "real LaunchBox" step for that).

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'LB players tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:LbpFile = Join-Path $TestDrive 'tpm-lbp-functions.ps1'
    [System.IO.File]::WriteAllText($script:LbpFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:LbpFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')

    $script:WheelId = '6d5dc38a-3bd3-4b93-bbb2-8f4d3ef0aaad'
    $script:GunId = '99b2ad5f-39d1-4f24-b6b6-725742c92be0'
    $script:JoystickId = '9cb551a3-0ef6-442b-82ca-c8e9433c5caa'

    # One profile from a list of buttons (each: Map, Analog). -Gun sets GunGame.
    function New-LbpProfile {
        param([string]$Dir, [string]$Code, [object[]]$Buttons, [switch]$Gun)
        $inner = ($Buttons | ForEach-Object { '<JoystickButtons><InputMapping>{0}</InputMapping><AnalogType>{1}</AnalogType></JoystickButtons>' -f $_.Map, $(if ($_.Analog) { $_.Analog } else { 'None' }) }) -join ''
        $xml = '<GameProfile><GamePath>x</GamePath><GunGame>{0}</GunGame><JoystickButtons>{1}</JoystickButtons></GameProfile>' -f $(if ($Gun) { 'true' } else { 'false' }), $inner
        [System.IO.File]::WriteAllText((Join-Path $Dir ($Code + '.xml')), $xml)
    }

    function New-LbpGame {
        param([string]$Id, [string]$Title, [string]$Code, [string]$Emulator = 'emu-1', [string]$MaxPlayers, [string]$PlayMode = '')
        $max = if ($PSBoundParameters.ContainsKey('MaxPlayers')) { '<MaxPlayers>' + $MaxPlayers + '</MaxPlayers>' } else { '' }
        return ('<Game><ID>{0}</ID><Title>{1}</Title><Platform>TeknoParrot</Platform><Emulator>{2}</Emulator><ApplicationPath>..\TP\UserProfiles\{3}.xml</ApplicationPath><Notes>note {1}</Notes><ReleaseType>Released</ReleaseType>{4}<PlayMode>{5}</PlayMode></Game>' -f $Id, $Title, $Emulator, $Code, $max, $PlayMode)
    }

    # Games: g1 two-player fighter (joystick), g2 light gun, g3 driving, g4 flight game (no clear controller), g5 other emulator.
    function New-LbpFixture {
        param([string]$ExtraGameXml = '', [string]$ExtraEnd = '', [switch]$NoControllerList)
        $root = Join-Path $TestDrive ('lbp-' + [guid]::NewGuid().ToString('N'))
        $lb = Join-Path $root 'LaunchBox'
        $tp = Join-Path $root 'TP'
        $profiles = Join-Path $tp 'UserProfiles'
        [void][System.IO.Directory]::CreateDirectory((Join-Path $lb 'Data\Platforms'))
        [void][System.IO.Directory]::CreateDirectory($profiles)
        [System.IO.File]::WriteAllText((Join-Path $lb 'Data\Emulators.xml'), '<LaunchBox><Emulator><ID>emu-1</ID><Title>TeknoParrot</Title></Emulator></LaunchBox>')
        if (-not $NoControllerList) {
            $list = '<LaunchBox>' +
                ('<GameController><AssociatedPlatforms></AssociatedPlatforms><Category>Joystick</Category><Id>{0}</Id><Name>8-Way Joystick</Name></GameController>' -f $script:JoystickId) +
                ('<GameController><AssociatedPlatforms></AssociatedPlatforms><Category>Light Gun</Category><Id>{0}</Id><Name>Generic Light Gun</Name></GameController>' -f $script:GunId) +
                ('<GameController><AssociatedPlatforms></AssociatedPlatforms><Category>Wheel/Yoke</Category><Id>{0}</Id><Name>Generic Wheel</Name></GameController>' -f $script:WheelId) +
                '</LaunchBox>'
            [System.IO.File]::WriteAllText((Join-Path $lb 'Data\GameControllers.xml'), $list)
        }
        New-LbpProfile -Dir $profiles -Code 'Fighter' -Buttons @(@{ Map = 'P1ButtonUp' }, @{ Map = 'P1ButtonDown' }, @{ Map = 'P1Button1' }, @{ Map = 'P2Button1' }, @{ Map = 'Coin1' })
        New-LbpProfile -Dir $profiles -Code 'Shooter' -Gun -Buttons @(@{ Map = 'P1Button1' }, @{ Map = 'P2Button1' }, @{ Map = 'P1GunX'; Analog = 'AnalogJoystick' })
        New-LbpProfile -Dir $profiles -Code 'Racer' -Buttons @(@{ Map = 'P1Button1' }, @{ Map = 'Wheel'; Analog = 'Wheel' }, @{ Map = 'Gas'; Analog = 'Gas' }, @{ Map = 'Brake'; Analog = 'Brake' })
        New-LbpProfile -Dir $profiles -Code 'Flyer' -Buttons @(@{ Map = 'P1Button1' }, @{ Map = 'P1StickX'; Analog = 'AnalogJoystick' }, @{ Map = 'Throttle'; Analog = 'SWThrottle' })
        New-LbpProfile -Dir $profiles -Code 'Other' -Buttons @(@{ Map = 'P1ButtonUp' }, @{ Map = 'P2Button1' })
        $games = (New-LbpGame 'g1' 'Fighter Game' 'Fighter') + (New-LbpGame 'g2' 'Shooter Game' 'Shooter' -MaxPlayers '0') + (New-LbpGame 'g3' 'Racer Game' 'Racer') +
                 (New-LbpGame 'g4' 'Flyer Game' 'Flyer') + (New-LbpGame 'g5' 'Not mine' 'Other' -Emulator 'emu-other') + $ExtraGameXml
        $platform = Join-Path $lb 'Data\Platforms\TeknoParrot.xml'
        [System.IO.File]::WriteAllText($platform, ('<LaunchBox>{0}<AlternateName><GameID>g1</GameID><Name>Alt</Name></AlternateName>{1}</LaunchBox>' -f $games, $ExtraEnd))
        return [pscustomobject]@{ Root = $lb; Tp = $tp; Profiles = $profiles; Backups = (Join-Path $root 'Backups'); Platform = $platform; Controllers = (Join-Path $lb 'Data\GameControllers.xml') }
    }

    function Get-LbpHash { param([string]$Path) return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

    function Invoke-Lbp {
        param($Fixture, [switch]$PlanOnly)
        return (Invoke-TpmLaunchBoxPlayerFields -UserProfilesDir $Fixture.Profiles -LbRoot $Fixture.Root -PlatformNames @('TeknoParrot') -BackupRoot $Fixture.Backups -TpRoot $Fixture.Tp -PlanOnly:$PlanOnly)
    }

    function Get-LbpDoc { param($Fixture) return [xml][System.IO.File]::ReadAllText($Fixture.Platform) }

    # The text of every child of a game except the boxes this feature owns.
    function Get-LbpOtherFields {
        param($Game)
        return (@($Game.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.Name -notin @('MaxPlayers', 'PlayMode') } | ForEach-Object { '{0}={1}' -f $_.Name, $_.InnerText }) -join '|')
    }
}

Describe 'LaunchBox players and controllers' {
    BeforeEach {
        Mock Write-Log {}
        Mock Test-LaunchBoxRunning { $false }
        Mock Write-TpmCompactExtractionProgress {}
    }

    It 'the preview says in plain words what each game would get, and writes nothing' {
        # Mutation: ignore -PlanOnly -> the file changes or a backup folder appears; drop the lines -> the player sees no list of games.
        $fx = New-LbpFixture
        $before = Get-LbpHash $fx.Platform
        $result = Invoke-Lbp $fx -PlanOnly
        $result.Reason | Should -BeExactly 'PREVIEW'
        (Get-LbpHash $fx.Platform) | Should -BeExactly $before
        Test-Path -LiteralPath $fx.Backups | Should -BeFalse
        (Format-TpmLaunchBoxPlayerTitle -Plan $result.PlayerPlan -Preview) | Should -BeLike 'Preview: LaunchBox would get player info for 4 games and controllers for 3 games.*Nothing was changed.'
        $lines = @(Format-TpmLaunchBoxPlayerLine -Plan $result.PlayerPlan)
        ($lines -join "`n") | Should -Match 'Fighter Game: players 2 \(was empty\); play mode Multiplayer \(was empty\); controller 8-Way Joystick'
        ($lines -join "`n") | Should -Match 'Shooter Game: players 2 \(was 0\); play mode Multiplayer \(was empty\); controller Generic Light Gun'
        ($lines -join "`n") | Should -Match 'Racer Game: players 1 \(was empty\); play mode Single Player \(was empty\); controller Generic Wheel'
    }

    It 'a yes writes the boxes with the ids from the LaunchBox controller list, and only for TeknoParrot games' {
        # Mutation: write the controller name instead of the Id, drop SupportLevel, or touch the other emulator's game -> an assertion fails.
        $fx = New-LbpFixture
        $original = Get-LbpDoc $fx
        $result = Invoke-Lbp $fx
        $result.Outcome | Should -BeExactly 'SAVED'
        $doc = Get-LbpDoc $fx
        $fighter = $doc.SelectSingleNode("/LaunchBox/Game[ID='g1']")
        $fighter.MaxPlayers | Should -BeExactly '2'
        $fighter.PlayMode | Should -BeExactly 'Multiplayer'
        $doc.SelectSingleNode("/LaunchBox/Game[ID='g2']").MaxPlayers | Should -BeExactly '2'
        $racer = $doc.SelectSingleNode("/LaunchBox/Game[ID='g3']")
        $racer.MaxPlayers | Should -BeExactly '1'
        $racer.PlayMode | Should -BeExactly 'Single Player'
        # A box LaunchBox did not have is added right after ReleaseType, where LaunchBox writes it.
        $racer.SelectSingleNode('ReleaseType').NextSibling.Name | Should -BeExactly 'MaxPlayers'
        $support = @($doc.SelectNodes('/LaunchBox/GameControllerSupport'))
        $support.Count | Should -Be 3
        $byGame = @{}
        foreach ($entry in $support) { $byGame[$entry.GameId] = $entry }
        $byGame['g1'].ControllerId | Should -BeExactly $script:JoystickId
        $byGame['g2'].ControllerId | Should -BeExactly $script:GunId
        $byGame['g3'].ControllerId | Should -BeExactly $script:WheelId
        foreach ($entry in $support) { $entry.SupportLevel | Should -BeExactly '3' }
        # The flight game gets its player count but no controller (its profile does not show one clearly); the other emulator's game and every other field stay as they were.
        $byGame.ContainsKey('g4') | Should -BeFalse
        $doc.SelectSingleNode("/LaunchBox/Game[ID='g4']").MaxPlayers | Should -BeExactly '1'
        $doc.SelectSingleNode("/LaunchBox/Game[ID='g5']").OuterXml | Should -BeExactly $original.SelectSingleNode("/LaunchBox/Game[ID='g5']").OuterXml
        foreach ($id in 'g1', 'g2', 'g3', 'g4', 'g5') {
            (Get-LbpOtherFields $doc.SelectSingleNode("/LaunchBox/Game[ID='$id']")) | Should -BeExactly (Get-LbpOtherFields $original.SelectSingleNode("/LaunchBox/Game[ID='$id']"))
        }
        $doc.SelectSingleNode('/LaunchBox/AlternateName').OuterXml | Should -BeExactly $original.SelectSingleNode('/LaunchBox/AlternateName').OuterXml
    }

    It 'a value the player already has is kept, and a game that already lists controllers keeps them' {
        # Mutation: overwrite a non-empty MaxPlayers or PlayMode, or add a second controller entry -> an assertion fails.
        $extraEnd = '<GameControllerSupport><ControllerId>{0}</ControllerId><GameId>g9</GameId></GameControllerSupport>' -f $script:WheelId
        $fx = New-LbpFixture -ExtraGameXml (New-LbpGame 'g9' 'Typed Game' 'Fighter' -MaxPlayers '4' -PlayMode 'Cooperative; Multiplayer') -ExtraEnd $extraEnd
        $result = Invoke-Lbp $fx -PlanOnly
        $item = @($result.PlayerPlan.Items | Where-Object { $_.GameId -eq 'g9' })[0]
        @($item.Changes).Count | Should -Be 0
        @($item.Controllers).Count | Should -Be 0
        (Format-TpmLaunchBoxPlayerLine -Plan $result.PlayerPlan | Where-Object { $_ -like 'Typed Game:*' }) | Should -Match 'LaunchBox says 4 players and TeknoParrot lists controls for 2\. The LaunchBox value stays\. LaunchBox already lists controllers'
        (Format-TpmLaunchBoxPlayerTitle -Plan $result.PlayerPlan -Preview) | Should -Match '1 game keep what LaunchBox already says'
        [void](Invoke-Lbp $fx)
        $doc = Get-LbpDoc $fx
        $typed = $doc.SelectSingleNode("/LaunchBox/Game[ID='g9']")
        $typed.MaxPlayers | Should -BeExactly '4'
        $typed.PlayMode | Should -BeExactly 'Cooperative; Multiplayer'
        @($doc.SelectNodes("/LaunchBox/GameControllerSupport[GameId='g9']")).Count | Should -Be 1
        @($doc.SelectNodes("/LaunchBox/GameControllerSupport[GameId='g9']"))[0].ControllerId | Should -BeExactly $script:WheelId
    }

    It 'a write makes a verified backup first, and the one-step undo puts the exact old file back' {
        # Mutation: skip the backup, or let the undo write something other than the saved copy -> the bytes differ.
        $fx = New-LbpFixture
        $before = Get-LbpHash $fx.Platform
        $written = Invoke-Lbp $fx
        $written.Outcome | Should -BeExactly 'SAVED'
        $written.BackupVerified | Should -BeTrue
        (Get-LbpHash (Join-Path $written.BackupPath 'Data\Platforms\TeknoParrot.xml')) | Should -BeExactly $before
        (Get-LbpHash $fx.Platform) | Should -Not -BeExactly $before
        $undone = Restore-TpmLaunchBoxPlayerFields -Written $written -LbRoot $fx.Root -BackupRoot $fx.Backups
        $undone.Outcome | Should -BeExactly 'SAVED'
        (Get-LbpHash $fx.Platform) | Should -BeExactly $before
    }

    It 'the undo never throws away a save that LaunchBox made afterwards' {
        # Mutation: restore without comparing the file to what this write made -> the newer text is lost.
        $fx = New-LbpFixture
        $written = Invoke-Lbp $fx
        [System.IO.File]::AppendAllText($fx.Platform, ' ')
        $newer = Get-LbpHash $fx.Platform
        $undone = Restore-TpmLaunchBoxPlayerFields -Written $written -LbRoot $fx.Root -BackupRoot $fx.Backups
        $undone.Outcome | Should -BeExactly 'FAILED'
        (Get-LbpHash $fx.Platform) | Should -BeExactly $newer
    }

    It 'refuses to write while LaunchBox is running, and changes nothing' {
        # Mutation: remove the running check -> the file changes while LaunchBox has it open.
        Mock Test-LaunchBoxRunning { $true }
        $fx = New-LbpFixture
        $before = Get-LbpHash $fx.Platform
        $result = Invoke-Lbp $fx
        $result.Outcome | Should -BeExactly 'FAILED'
        ($result.Errors -join ' ') | Should -Match 'Close LaunchBox and BigBox'
        (Get-LbpHash $fx.Platform) | Should -BeExactly $before
        Test-Path -LiteralPath $fx.Backups | Should -BeFalse
    }

    It 'a platform file that is not valid XML is left alone' {
        # Mutation: repair or overwrite the broken file -> its bytes change or the run does not stop.
        $fx = New-LbpFixture
        [System.IO.File]::WriteAllText($fx.Platform, '<LaunchBox><Game><ID>g1</ID></Game')
        $before = Get-LbpHash $fx.Platform
        $result = Invoke-Lbp $fx
        $result.Outcome | Should -BeExactly 'FAILED'
        (Get-LbpHash $fx.Platform) | Should -BeExactly $before
        Test-Path -LiteralPath $fx.Backups | Should -BeFalse
    }

    It 'without LaunchBox''s controller list the player boxes are filled and no controller is guessed' {
        # Mutation: invent controller ids when the list is missing -> a GameControllerSupport entry appears.
        $fx = New-LbpFixture -NoControllerList
        $result = Invoke-Lbp $fx
        $result.Outcome | Should -BeExactly 'SAVED'
        $doc = Get-LbpDoc $fx
        @($doc.SelectNodes('/LaunchBox/GameControllerSupport')).Count | Should -Be 0
        $doc.SelectSingleNode("/LaunchBox/Game[ID='g1']").MaxPlayers | Should -BeExactly '2'
    }
}

Describe 'LaunchBox players and controllers screen' {
    BeforeEach {
        Mock Write-Log {}
        Mock Test-LaunchBoxRunning { $false }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Write-TpmLaunchBoxResult {}
        Mock Wait-TpmForProcessClose { $true }
        Mock Read-TpmChoice { '2' }
    }

    It 'answering No writes nothing at all' {
        # Mutation: write before asking, or treat the default as yes -> the file or the backup folder changes.
        Mock Read-TpmYesNo { 'N' }
        $fx = New-LbpFixture
        $before = Get-LbpHash $fx.Platform
        Invoke-TpmLaunchBoxPlayerStep -UserProfilesDir $fx.Profiles -LbRoot $fx.Root -TpRoot $fx.Tp
        (Get-LbpHash $fx.Platform) | Should -BeExactly $before
        Test-Path -LiteralPath (Join-Path $fx.Root 'Data\Playlists') | Should -BeFalse
        Should -Invoke Read-TpmYesNo -Times 1 -Exactly
    }

    It 'a No to the second question keeps the new boxes; a Yes puts the old file back' {
        # Mutation: the undo question does nothing, or restores without being asked -> the file hash is wrong in one of the two runs.
        $script:LbpUndoAnswer = 'N'
        Mock Read-TpmYesNo { if ($Prompt -like '*Undo this now*') { $script:LbpUndoAnswer } else { 'Y' } }
        $fx = New-LbpFixture
        $before = Get-LbpHash $fx.Platform
        Invoke-TpmLaunchBoxPlayerStep -UserProfilesDir $fx.Profiles -LbRoot $fx.Root -TpRoot $fx.Tp
        (Get-LbpHash $fx.Platform) | Should -Not -BeExactly $before
        $fx2 = New-LbpFixture
        $before2 = Get-LbpHash $fx2.Platform
        $script:LbpUndoAnswer = 'Y'
        Invoke-TpmLaunchBoxPlayerStep -UserProfilesDir $fx2.Profiles -LbRoot $fx2.Root -TpRoot $fx2.Tp
        (Get-LbpHash $fx2.Platform) | Should -BeExactly $before2
    }
}
