#Requires -Module Pester

# LEDBlinky lighting export (issue #267): what a user sees or could lose.
#   - The step is only offered when LEDBlinky is found.
#   - A preview never changes LEDBlinky's files or the TeknoParrot profiles.
#   - An add saves a verified copy first, touches only the TeknoParrot group, never duplicates or edits existing entries,
#     refuses while LEDBlinky is open or if the file changed after the preview, and can be undone exactly.
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.
# Everything lives under TestDrive with synthetic files.
# What this CANNOT prove: that a real LEDBlinky or LaunchBox reads the new entries and lights the right buttons.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'LEDBlinky tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:LedFunctionFile = Join-Path $TestDrive 'tpm-led-functions.ps1'
    [System.IO.File]::WriteAllText($script:LedFunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:LedFunctionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')

    function New-LedFixture {
        param([switch]$NoTeknoParrotGroup)
        $root = Join-Path $TestDrive ('led-' + [guid]::NewGuid().ToString('N'))
        $led = Join-Path $root 'LEDBlinky'
        $profiles = Join-Path $root 'UserProfiles'
        $layoutRoot = Join-Path $root 'Manager'
        foreach ($d in @($led, $profiles, (Join-Path $layoutRoot 'Backups'), (Join-Path $layoutRoot 'State'), (Join-Path $layoutRoot 'Reports'))) { [void][System.IO.Directory]::CreateDirectory($d) }
        $teknoGroup = if ($NoTeknoParrotGroup) { '' } else {
            "  <emulator emuname=`"TeknoParrot`" emuDesc=`"`">`r`n" +
            "    <controlGroup groupName=`"DEFAULT`" voice=`"`" numPlayers=`"2`" alternating=`"0`" jukebox=`"0`">`r`n      <player number=`"1`">`r`n        <control name=`"P1_BUTTON1`" voice=`"`" color=`"White`" />`r`n      </player>`r`n    </controlGroup>`r`n" +
            "    <controlGroup groupName=`"MyOwnGame`" voice=`"Hand made`" numPlayers=`"1`" alternating=`"0`" jukebox=`"0`">`r`n      <player number=`"1`">`r`n        <control name=`"P1_BUTTON1`" voice=`"Fire`" color=`"Red`" />`r`n      </player>`r`n    </controlGroup>`r`n" +
            "  </emulator>`r`n"
        }
        $xml = "<?xml version=`"1.0`"?>`r`n<dat>`r`n  <emulator emuname=`"MAME`" emuDesc=`"`">`r`n    <controlGroup groupName=`"pacman`" voice=`"Pac-Man`" numPlayers=`"1`" alternating=`"0`" jukebox=`"0`">`r`n    </controlGroup>`r`n  </emulator>`r`n" + $teknoGroup + "</dat>`r`n"
        $controls = Join-Path $led 'LEDBlinkyControls.xml'
        [System.IO.File]::WriteAllText($controls, $xml, (New-Object System.Text.UTF8Encoding $false))
        $layout = [pscustomobject]@{ Backups = (Join-Path $layoutRoot 'Backups'); State = (Join-Path $layoutRoot 'State'); Reports = (Join-Path $layoutRoot 'Reports') }
        return [pscustomobject]@{ Root = $root; Led = $led; Controls = $controls; Profiles = $profiles; Layout = $layout; Install = [pscustomobject]@{ Root = $led; ControlsPath = $controls } }
    }

    function New-LedProfile {
        param([string]$Dir, [string]$Name, [string]$Description = '', [string[]]$Mappings = @('P1ButtonStart', 'P1ButtonUp', 'P1ButtonDown', 'P1Button1', 'P1Button2', 'Coin1'))
        $buttons = ($Mappings | ForEach-Object { "<JoystickButtons><ButtonName>$_ name</ButtonName><InputMapping>$_</InputMapping></JoystickButtons>" }) -join ''
        $desc = if ($Description) { "<Description>$Description</Description>" } else { '' }
        $xml = "<GameProfile>$desc<GamePath>C:\Games\$Name.exe</GamePath><JoystickButtons>$buttons</JoystickButtons></GameProfile>"
        [System.IO.File]::WriteAllText((Join-Path $Dir "$Name.xml"), $xml)
    }

    function Get-LedHash { param([string]$Path) (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
}

Describe 'LEDBlinky lighting export' {
    BeforeEach {
        Mock Write-Log { }
        Mock Test-TpmLedBlinkyRunning { $false }
        Mock Get-TpmRegisteredProfileFilesWithDiscoveryProgress { Get-ChildItem -LiteralPath $UserProfilesDir -Filter '*.xml' -File }
        Mock Write-TpmOutcome { }
    }

    It 'is not offered when LEDBlinky is not installed' {
        $saved = $env:SystemDrive
        try {
            $env:SystemDrive = Join-Path $TestDrive 'no-such-drive'
            Find-TpmLedBlinky | Should -BeNullOrEmpty
            $fx = New-LedFixture
            (Find-TpmLedBlinky -ExtraFolders @($fx.Led)).ControlsPath | Should -Be $fx.Controls
        } finally { $env:SystemDrive = $saved }
    }

    It 'a preview lists the new games and changes nothing in LEDBlinky or the profiles' {
        $fx = New-LedFixture
        New-LedProfile -Dir $fx.Profiles -Name 'AkaiKatana'
        New-LedProfile -Dir $fx.Profiles -Name 'Spikeout' -Description 'Spikeout Final Edition' -Mappings @('P1Button1', 'P1ButtonStart')
        $ledBefore = Get-LedHash $fx.Controls
        $profileBefore = @(Get-ChildItem $fx.Profiles | ForEach-Object { Get-LedHash $_.FullName })
        $plan = Get-TpmLedExportPlan -UserProfilesDir $fx.Profiles -ControlsPath $fx.Controls
        Write-TpmLedPreview -Plan $plan -Layout $fx.Layout
        $plan.Groups.Count | Should -Be 2
        $plan.BlockText | Should -Match 'groupName="AkaiKatana" voice="Akai Katana"'
        $plan.BlockText | Should -Match 'name="P1_JOYSTICK_UP"'
        $plan.BlockText | Should -Match 'name="START1" voice="Start Game"'
        $plan.BlockText | Should -Match 'name="COIN1"'
        Should -Invoke Write-TpmOutcome -Times 1 -Exactly -ParameterFilter { $Title -match '^Preview: LEDBlinky would get lighting info for 2 games\. Nothing was changed\.$' -and @($DetailBlocks).Count -gt 0 }
        Get-LedHash $fx.Controls | Should -Be $ledBefore
        @(Get-ChildItem $fx.Profiles | ForEach-Object { Get-LedHash $_.FullName }) | Should -Be $profileBefore
    }

    It 'a game LEDBlinky already knows is left alone and never duplicated' {
        $fx = New-LedFixture
        New-LedProfile -Dir $fx.Profiles -Name 'MyOwnGame'
        New-LedProfile -Dir $fx.Profiles -Name 'AkaiKatana'
        $plan = Get-TpmLedExportPlan -UserProfilesDir $fx.Profiles -ControlsPath $fx.Controls
        @($plan.Groups | ForEach-Object { $_.Key }) | Should -Be @('AkaiKatana')
        @($plan.SkippedExisting) | Should -Be @('MyOwnGame')
    }

    It 'says what to do when LEDBlinky has no TeknoParrot group, and changes nothing' {
        $fx = New-LedFixture -NoTeknoParrotGroup
        New-LedProfile -Dir $fx.Profiles -Name 'AkaiKatana'
        $before = Get-LedHash $fx.Controls
        $plan = Get-TpmLedExportPlan -UserProfilesDir $fx.Profiles -ControlsPath $fx.Controls
        Write-TpmLedPreview -Plan $plan -Layout $fx.Layout
        $plan.HasEmulator | Should -BeFalse
        Should -Invoke Write-TpmOutcome -Times 1 -Exactly -ParameterFilter { ($Needs -join ' ') -match 'Controls Editor' }
        (Invoke-TpmLedBlinkyAdd -Install $fx.Install -Plan $plan -Layout $fx.Layout).Outcome | Should -Be 'FAILED'
        Get-LedHash $fx.Controls | Should -Be $before
    }

    It 'an add saves a verified copy first, touches only the TeknoParrot group and keeps every other byte' {
        $fx = New-LedFixture
        New-LedProfile -Dir $fx.Profiles -Name 'AkaiKatana' -Description ('Akai Katana Caf' + [char]0xE9)
        $original = [System.IO.File]::ReadAllText($fx.Controls)
        $plan = Get-TpmLedExportPlan -UserProfilesDir $fx.Profiles -ControlsPath $fx.Controls
        $result = Invoke-TpmLedBlinkyAdd -Install $fx.Install -Plan $plan -Layout $fx.Layout
        $result.Outcome | Should -Be 'SAVED'
        Get-LedHash $result.BackupPath | Should -Be $plan.SourceHash
        $new = [System.IO.File]::ReadAllText($fx.Controls)
        $new.Remove($plan.InsertAt, $plan.BlockText.Length) | Should -BeExactly $original
        $span = Get-TpmLedEmulatorSpan -Text $new
        $span.Body | Should -Match 'groupName="AkaiKatana"'
        $span.Body | Should -Match 'groupName="MyOwnGame"'
        $new.Substring(0, $new.IndexOf('emuname="TeknoParrot"')) | Should -Not -Match 'AkaiKatana'
        ($new | Select-String -Pattern '[^\x00-\x7F]').Count | Should -Be 0
        { $x = New-Object System.Xml.XmlDocument; $x.LoadXml($new) } | Should -Not -Throw
    }

    It 'refuses to add while LEDBlinky is open' {
        $fx = New-LedFixture
        New-LedProfile -Dir $fx.Profiles -Name 'AkaiKatana'
        $plan = Get-TpmLedExportPlan -UserProfilesDir $fx.Profiles -ControlsPath $fx.Controls
        $before = Get-LedHash $fx.Controls
        Mock Test-TpmLedBlinkyRunning { $true }
        $result = Invoke-TpmLedBlinkyAdd -Install $fx.Install -Plan $plan -Layout $fx.Layout
        $result.Outcome | Should -Be 'FAILED'
        $result.Summary | Should -Match 'LEDBlinky is open'
        Get-LedHash $fx.Controls | Should -Be $before
    }

    It 'refuses to add when the file changed after the preview' {
        $fx = New-LedFixture
        New-LedProfile -Dir $fx.Profiles -Name 'AkaiKatana'
        $plan = Get-TpmLedExportPlan -UserProfilesDir $fx.Profiles -ControlsPath $fx.Controls
        [System.IO.File]::AppendAllText($fx.Controls, '<!-- edited -->')
        $before = Get-LedHash $fx.Controls
        $result = Invoke-TpmLedBlinkyAdd -Install $fx.Install -Plan $plan -Layout $fx.Layout
        $result.Outcome | Should -Be 'FAILED'
        $result.Summary | Should -Match 'changed after the preview'
        Get-LedHash $fx.Controls | Should -Be $before
    }

    It 'undo puts the file back exactly, and keeps a later edit the user made elsewhere' {
        $fx = New-LedFixture
        New-LedProfile -Dir $fx.Profiles -Name 'AkaiKatana'
        $originalHash = Get-LedHash $fx.Controls
        $plan = Get-TpmLedExportPlan -UserProfilesDir $fx.Profiles -ControlsPath $fx.Controls
        (Invoke-TpmLedBlinkyAdd -Install $fx.Install -Plan $plan -Layout $fx.Layout).Outcome | Should -Be 'SAVED'
        (Invoke-TpmLedBlinkyUndo -Install $fx.Install -Layout $fx.Layout).Outcome | Should -Be 'SAVED'
        Get-LedHash $fx.Controls | Should -Be $originalHash
        (Invoke-TpmLedBlinkyUndo -Install $fx.Install -Layout $fx.Layout).Outcome | Should -Be 'NONE'

        $plan2 = Get-TpmLedExportPlan -UserProfilesDir $fx.Profiles -ControlsPath $fx.Controls
        (Invoke-TpmLedBlinkyAdd -Install $fx.Install -Plan $plan2 -Layout $fx.Layout).Outcome | Should -Be 'SAVED'
        $edited = ([System.IO.File]::ReadAllText($fx.Controls)).Replace('voice="Pac-Man"', 'voice="Pac-Man (mine)"')
        [System.IO.File]::WriteAllText($fx.Controls, $edited, (New-Object System.Text.UTF8Encoding $false))
        (Invoke-TpmLedBlinkyUndo -Install $fx.Install -Layout $fx.Layout).Outcome | Should -Be 'SAVED'
        $after = [System.IO.File]::ReadAllText($fx.Controls)
        $after | Should -Match 'Pac-Man \(mine\)'
        $after | Should -Not -Match 'AkaiKatana'
    }

    It 'undo refuses to guess when the added entries were changed' {
        $fx = New-LedFixture
        New-LedProfile -Dir $fx.Profiles -Name 'AkaiKatana'
        $plan = Get-TpmLedExportPlan -UserProfilesDir $fx.Profiles -ControlsPath $fx.Controls
        (Invoke-TpmLedBlinkyAdd -Install $fx.Install -Plan $plan -Layout $fx.Layout).Outcome | Should -Be 'SAVED'
        $edited = ([System.IO.File]::ReadAllText($fx.Controls)).Replace('voice="Akai Katana"', 'voice="Renamed by me"')
        [System.IO.File]::WriteAllText($fx.Controls, $edited, (New-Object System.Text.UTF8Encoding $false))
        $before = Get-LedHash $fx.Controls
        (Invoke-TpmLedBlinkyUndo -Install $fx.Install -Layout $fx.Layout).Outcome | Should -Be 'FAILED'
        Get-LedHash $fx.Controls | Should -Be $before
    }
}
