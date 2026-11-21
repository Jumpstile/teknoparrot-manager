#Requires -Module Pester

# LEDBlinky lighting export (issue #267): what a user sees or could lose.
#   - LEDBlinky is found in the usual places (any drive, Program Files, a saved choice) or the user is asked; a wrong folder is refused.
#   - The controls written for a game come from the user's own LEDBlinky setup (8 buttons, 16 buttons plus a spinner, custom
#     names), only for controls the profile uses; the rest is listed in Details and never written.
#   - A control without an LED, with more than one possible LED, or that the connected devices do not show is "needs your choice".
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

    # A fixture LEDBlinky folder. Player 1 has -Buttons buttons, the four directions, Start and Coin; -Extra adds controls
    # as 'NAME|CODES' strings; -Primary adds main controls. LEDBlinkyInputMap.xml gets one LED per control (except those named in
    # -NoLed) plus -ExtraLeds as 'LABEL|CODE'. -NoInputMap leaves that file out.
    function New-LedFixture {
        param([switch]$NoTeknoParrotGroup, [int]$Buttons = 8, [string[]]$Extra = @(), [string[]]$Primary = @('CONTROL_JOY8WAY'), [string[]]$NoLed = @(), [string[]]$ExtraLeds = @(), [switch]$NoInputMap)
        $root = Join-Path $TestDrive ('led-' + [guid]::NewGuid().ToString('N'))
        $led = Join-Path $root 'LEDBlinky'
        $profiles = Join-Path $root 'UserProfiles'
        $layoutRoot = Join-Path $root 'Manager'
        foreach ($d in @($led, $profiles, (Join-Path $layoutRoot 'Backups'), (Join-Path $layoutRoot 'State'), (Join-Path $layoutRoot 'Reports'))) { [void][System.IO.Directory]::CreateDirectory($d) }
        $controls = New-Object System.Collections.Generic.List[object]
        foreach ($n in 1..$Buttons) { [void]$controls.Add(@{ Name = "P1_BUTTON$n"; Codes = "KEYCODE_B$n"; Voice = '' }) }
        foreach ($d in @('UP', 'DOWN', 'LEFT', 'RIGHT')) { [void]$controls.Add(@{ Name = "P1_JOYSTICK_$d"; Codes = "KEYCODE_$d"; Voice = $d }) }
        [void]$controls.Add(@{ Name = 'START1'; Codes = 'KEYCODE_1'; Voice = 'Start Game' })
        [void]$controls.Add(@{ Name = 'COIN1'; Codes = 'KEYCODE_5'; Voice = 'Insert Coin' })
        foreach ($e in $Extra) { $parts = $e -split '\|'; [void]$controls.Add(@{ Name = $parts[0]; Codes = $parts[1]; Voice = '' }) }
        $nl = "`r`n"
        $lines = New-Object System.Collections.Generic.List[string]
        [void]$lines.Add('      <player number="0">')
        foreach ($pc in $Primary) { [void]$lines.Add(('        <control name="{0}" voice="" primaryControl="1" color="" inputCodes="" />' -f $pc)) }
        [void]$lines.Add('      </player>')
        [void]$lines.Add('      <player number="1">')
        foreach ($c in $controls) { [void]$lines.Add(('        <control name="{0}" voice="{1}" color="White" inputCodes="{2}" />' -f $c.Name, $c.Voice, $c.Codes)) }
        [void]$lines.Add('      </player>')
        $teknoGroup = if ($NoTeknoParrotGroup) { '' } else {
            "  <emulator emuname=`"TeknoParrot`" emuDesc=`"`">$nl" +
            "    <controlGroup groupName=`"DEFAULT`" voice=`"`" numPlayers=`"1`" alternating=`"0`" jukebox=`"0`">$nl" + ($lines -join $nl) + "$nl    </controlGroup>$nl" +
            "    <controlGroup groupName=`"MyOwnGame`" voice=`"Hand made`" numPlayers=`"1`" alternating=`"0`" jukebox=`"0`">$nl      <player number=`"1`">$nl        <control name=`"P1_BUTTON1`" voice=`"Fire`" color=`"Red`" />$nl      </player>$nl    </controlGroup>$nl" +
            "  </emulator>$nl"
        }
        $xml = "<?xml version=`"1.0`"?>$nl<dat>$nl  <emulator emuname=`"MAME`" emuDesc=`"`">$nl    <controlGroup groupName=`"pacman`" voice=`"Pac-Man`" numPlayers=`"1`" alternating=`"0`" jukebox=`"0`">$nl    </controlGroup>$nl  </emulator>$nl" + $teknoGroup + "</dat>$nl"
        $controlsPath = Join-Path $led 'LEDBlinkyControls.xml'
        [System.IO.File]::WriteAllText($controlsPath, $xml, (New-Object System.Text.UTF8Encoding $false))
        if (-not $NoInputMap) {
            $ports = New-Object System.Collections.Generic.List[string]
            $i = 0
            foreach ($c in $controls) { if ($NoLed -notcontains $c.Name) { $i++; [void]$ports.Add(('    <port number="{0}" label="{1}" type="B" inputCodes="{2}"/>' -f $i, ($c.Name -replace '_', ''), $c.Codes)) } }
            foreach ($pc in $Primary) { if ($pc -eq 'CONTROL_TRACKBALL') { $i++; [void]$ports.Add(('    <port number="{0}" label="TRACKBALL" type="B" inputCodes="TRACKBALL"/>' -f $i)) } }
            foreach ($l in $ExtraLeds) { $parts = $l -split '\|'; $i++; [void]$ports.Add(('    <port number="{0}" label="{1}" type="B" inputCodes="{2}"/>' -f $i, $parts[0], $parts[1])) }
            $map = '<?xml version="1.0" encoding="UTF-8"?>' + $nl + '<dat>' + $nl + '  <ledController type="1" id="1" name="LEDWiz">' + $nl + ($ports -join $nl) + $nl + '  </ledController>' + $nl + '</dat>' + $nl
            [System.IO.File]::WriteAllText((Join-Path $led 'LEDBlinkyInputMap.xml'), $map, (New-Object System.Text.UTF8Encoding $false))
        }
        $layout = [pscustomobject]@{ Backups = (Join-Path $layoutRoot 'Backups'); State = (Join-Path $layoutRoot 'State'); Reports = (Join-Path $layoutRoot 'Reports') }
        return [pscustomobject]@{ Root = $root; Led = $led; Controls = $controlsPath; Profiles = $profiles; Layout = $layout; Install = [pscustomobject]@{ Root = $led; ControlsPath = $controlsPath } }
    }

    function New-LedProfile {
        param([string]$Dir, [string]$Name, [string]$Description = '', [string[]]$Mappings = @('P1ButtonStart', 'P1ButtonUp', 'P1ButtonDown', 'P1Button1', 'P1Button2', 'Coin1'))
        $buttons = ($Mappings | ForEach-Object { "<JoystickButtons><ButtonName>$_ name</ButtonName><InputMapping>$_</InputMapping></JoystickButtons>" }) -join ''
        $desc = if ($Description) { "<Description>$Description</Description>" } else { '' }
        $xml = "<GameProfile>$desc<GamePath>C:\Games\$Name.exe</GamePath><JoystickButtons>$buttons</JoystickButtons></GameProfile>"
        [System.IO.File]::WriteAllText((Join-Path $Dir "$Name.xml"), $xml)
    }

    # A controller evidence object shaped like Get-TpmControllerEvidence returns (contract TpmControllerEvidence/v1).
    function New-LedEvidence {
        param([string]$Status = 'Observed', [hashtable]$Devices = @{})
        return [pscustomobject]@{ ContractVersion = 'TpmControllerEvidence/v1'; EvidenceStatus = $Status; DeviceObservations = @($Devices.Keys | ForEach-Object { [pscustomobject]@{ DeviceClass = $_; Confidence = 'Medium'; Basis = 'Fixture'; Count = [int]$Devices[$_]; ReasonCodes = @() } }) }
    }

    function Get-LedHash { param([string]$Path) (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
    function Get-LedBlock { param($Plan) return [string]$Plan.BlockText }
    function Get-LedDetailText { param($Plan) return ((Get-TpmLedPlanDetailBlocks -Plan $Plan | ForEach-Object { $_.Heading; $_.Lines }) -join "`n") }
}

Describe 'LEDBlinky lighting export' {
    BeforeEach {
        Mock Write-Log { }
        Mock Test-TpmLedBlinkyRunning { $false }
        Mock Get-TpmRegisteredProfileFilesWithDiscoveryProgress { Get-ChildItem -LiteralPath $UserProfilesDir -Filter '*.xml' -File }
        Mock Write-TpmOutcome { }
    }

    It 'finds LEDBlinky on a drive other than C: and in Program Files' {
        $driveRoot = Join-Path $TestDrive ('fake-drive-' + [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory((Join-Path $driveRoot 'LEDBlinky'))
        [System.IO.File]::WriteAllText((Join-Path $driveRoot 'LEDBlinky\LEDBlinkyControls.xml'), '<dat />')
        $emptyDrive = Join-Path $TestDrive ('empty-drive-' + [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($emptyDrive)
        $candidates = Get-TpmLedBlinkyCandidateFolders -DriveRoots @($emptyDrive, $driveRoot)
        (Find-TpmLedBlinky -Candidates $candidates).Root | Should -Be (Join-Path $driveRoot 'LEDBlinky')
        $programFiles = Join-Path $TestDrive 'Program Files'
        [void][System.IO.Directory]::CreateDirectory((Join-Path $programFiles 'LEDBlinky'))
        [System.IO.File]::WriteAllText((Join-Path $programFiles 'LEDBlinky\LEDBlinkyControls.xml'), '<dat />')
        (Find-TpmLedBlinky -Candidates (Get-TpmLedBlinkyCandidateFolders -ProgramFilesFolders @($programFiles))).Root | Should -Be (Join-Path $programFiles 'LEDBlinky')
        (Get-TpmLedBlinkyCandidateFolders -LaunchBoxRoot (Join-Path $driveRoot 'LaunchBox')) | Should -Contain (Join-Path $driveRoot 'LEDBlinky')
    }

    It 'uses the folder the user chose before' {
        $fx = New-LedFixture
        $candidates = Get-TpmLedBlinkyCandidateFolders -SavedFolder $fx.Led -DriveRoots @()
        $candidates[0] | Should -Be $fx.Led
        (Find-TpmLedBlinky -Candidates $candidates).ControlsPath | Should -Be $fx.Controls
    }

    It 'rejects a folder without the LEDBlinky control file, explains why, and lets the user try again' {
        $fx = New-LedFixture
        $wrong = Join-Path $TestDrive ('not-ledblinky-' + [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($wrong)
        Get-TpmLedBlinkyFolderProblem -Path $wrong | Should -Be 'NoControls'
        Get-TpmLedBlinkyFolderProblem -Path (Join-Path $wrong 'missing') | Should -Be 'NoFolder'
        Get-TpmLedBlinkyFolderProblem -Path $fx.Led | Should -Be ''
        $global:LedAnswers = New-Object System.Collections.Queue
        $global:LedAnswers.Enqueue($wrong)
        $global:LedAnswers.Enqueue($fx.Led)
        Mock Read-PathWithBrowse { $global:LedAnswers.Dequeue() }
        Mock Write-TpmText { }
        (Read-TpmLedBlinkyFolder).Root | Should -Be $fx.Led
        Should -Invoke Write-TpmText -Times 1 -Exactly -ParameterFilter { $Text -match 'does not have the LEDBlinky control file' }
        Remove-Variable -Name LedAnswers -Scope Global -ErrorAction SilentlyContinue
    }

    It 'asks in plain words when LEDBlinky is not found, and skipping offers nothing and saves nothing' {
        $saved = @($env:ProgramFiles, ${env:ProgramFiles(x86)})
        try {
            $env:ProgramFiles = Join-Path $TestDrive 'pf-none'
            ${env:ProgramFiles(x86)} = Join-Path $TestDrive 'pf86-none'
            Mock Get-TpmLedLocalDriveRoots { @() }
            Mock Write-TpmText { }
            Mock Read-TpmChoice { 'S' }
            Invoke-TpmLedBlinkyLocate | Should -BeNullOrEmpty
            Should -Invoke Write-TpmText -Times 1 -Exactly -ParameterFilter { $Text -match '^Do you use LEDBlinky\? Show me where it is' }
            Should -Invoke Read-TpmChoice -Times 1 -Exactly
        } finally { $env:ProgramFiles = $saved[0]; ${env:ProgramFiles(x86)} = $saved[1] }
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
        $plan.BlockText | Should -Match 'name="CONTROL_JOY8WAY"'
        Should -Invoke Write-TpmOutcome -Times 1 -Exactly -ParameterFilter { $Title -match '^Preview: LEDBlinky would get lighting info for 2 games\. Nothing was changed\.$' -and @($DetailBlocks).Count -gt 0 }
        Get-LedHash $fx.Controls | Should -Be $ledBefore
        @(Get-ChildItem $fx.Profiles | ForEach-Object { Get-LedHash $_.FullName }) | Should -Be $profileBefore
    }

    It 'a cabinet with 8 buttons: only the buttons it has are written, the others are listed as not on the cabinet' {
        $fx = New-LedFixture -Buttons 8
        New-LedProfile -Dir $fx.Profiles -Name 'TenButtons' -Mappings (@(1..10 | ForEach-Object { "P1Button$_" }) + @('P1ButtonStart'))
        $plan = Get-TpmLedExportPlan -UserProfilesDir $fx.Profiles -ControlsPath $fx.Controls
        $plan.Groups.Count | Should -Be 1
        $plan.BlockText | Should -Match 'name="P1_BUTTON8"'
        $plan.BlockText | Should -Not -Match 'P1_BUTTON9'
        $plan.BlockText | Should -Not -Match 'P1_BUTTON10'
        @($plan.Groups[0].NotOnCabinet) | Should -Contain 'P1Button9 name'
        (Get-LedDetailText $plan) | Should -Match 'Not on your cabinet'
        (Get-LedDetailText $plan) | Should -Match 'P1Button10 name'
    }

    It 'a cabinet with 16 buttons and a spinner: the extra buttons and the spinner are written under the names the user chose' {
        $fx = New-LedFixture -Buttons 16 -Extra @('P1_SPINNER|MOUSECODE_1_ANALOG_X')
        New-LedProfile -Dir $fx.Profiles -Name 'SpinGame' -Mappings @('P1Button1', 'P1Button14', 'P1Spinner', 'P1ButtonStart')
        $plan = Get-TpmLedExportPlan -UserProfilesDir $fx.Profiles -ControlsPath $fx.Controls
        $plan.BlockText | Should -Match 'name="P1_BUTTON14"'
        $plan.BlockText | Should -Match 'name="P1_SPINNER" voice="" inputCodes="MOUSECODE_1_ANALOG_X"'
        $plan.BlockText | Should -Not -Match 'P1_BUTTON15'
    }

    It 'a custom-named LED the game does not use is left out, and an LED no control uses is listed for the user' {
        $fx = New-LedFixture -Extra @('MARQUEE_GLOW|CUSTOM_MARQUEE') -ExtraLeds @('SIDEGLOW|CUSTOM_SIDE')
        New-LedProfile -Dir $fx.Profiles -Name 'AkaiKatana'
        $plan = Get-TpmLedExportPlan -UserProfilesDir $fx.Profiles -ControlsPath $fx.Controls
        $plan.BlockText | Should -Not -Match 'MARQUEE_GLOW'
        $plan.Cabinet.Names | Should -Contain 'MARQUEE_GLOW'
        @($plan.Pairing.LedsWithoutControl) | Should -Contain 'SIDEGLOW'
        (Get-LedDetailText $plan) | Should -Match 'LED SIDEGLOW: no control in your LEDBlinky setup uses it'
        Write-TpmLedPreview -Plan $plan -Layout $fx.Layout
        Should -Invoke Write-TpmOutcome -Times 1 -Exactly -ParameterFilter { ($Needs -join ' ') -match 'need.* your choice' }
    }

    It 'a control with no LED in the LED map is held back and shown as needing a choice, never written' {
        $fx = New-LedFixture -NoLed @('P1_BUTTON2')
        New-LedProfile -Dir $fx.Profiles -Name 'AkaiKatana'
        $plan = Get-TpmLedExportPlan -UserProfilesDir $fx.Profiles -ControlsPath $fx.Controls
        $plan.BlockText | Should -Not -Match 'name="P1_BUTTON2"'
        $plan.BlockText | Should -Match 'name="P1_BUTTON1"'
        @($plan.Pairing.Held | Where-Object { $_.Name -eq 'P1_BUTTON2' -and $_.Reason -eq 'NoLed' }).Count | Should -Be 1
        @($plan.Groups[0].NeedsChoice | ForEach-Object { $_.Label }) | Should -Contain 'P1Button2 name'
        (Get-LedDetailText $plan) | Should -Match 'P1_BUTTON2: no LED in your LED map uses it\. Not written\.'
    }

    It 'a control that more than one LED could belong to is not guessed' {
        $fx = New-LedFixture -ExtraLeds @('P1B1COPY|KEYCODE_B1')
        New-LedProfile -Dir $fx.Profiles -Name 'AkaiKatana'
        $plan = Get-TpmLedExportPlan -UserProfilesDir $fx.Profiles -ControlsPath $fx.Controls
        $plan.BlockText | Should -Not -Match 'name="P1_BUTTON1"'
        @($plan.Pairing.Held | Where-Object { $_.Name -eq 'P1_BUTTON1' -and $_.Reason -eq 'Several' }).Count | Should -Be 1
        (Get-LedDetailText $plan) | Should -Match 'P1_BUTTON1: more than one LED fits'
    }

    It 'a spinner profile with two possible spinner controls needs the user''s choice and nothing is written for it' {
        $fx = New-LedFixture -Extra @('P1_DIAL|CODE_DIAL1', 'P1_DIAL_EXT|CODE_DIAL2')
        New-LedProfile -Dir $fx.Profiles -Name 'SpinGame' -Mappings @('P1Button1', 'P1Spinner')
        $plan = Get-TpmLedExportPlan -UserProfilesDir $fx.Profiles -ControlsPath $fx.Controls
        $plan.BlockText | Should -Not -Match 'P1_DIAL'
        @($plan.Groups[0].NeedsChoice | Where-Object { $_.Label -match 'Spinner' }).Count | Should -Be 1
        (Get-LedDetailText $plan) | Should -Match 'could be P1_DIAL, P1_DIAL_EXT'
    }

    It 'the controller evidence is compared with the LEDBlinky setup, both ways, and nothing is guessed' {
        $fx = New-LedFixture -Primary @('CONTROL_JOY8WAY', 'CONTROL_TRACKBALL')
        $text = [System.IO.File]::ReadAllText($fx.Controls)
        $cabinet = Get-TpmLedCabinet -ControlsText $text
        $keyMap = Get-TpmLedBlinkyKeyMap -Root @($fx.Led)
        $keyMap.Found | Should -BeTrue
        # No trackball connected, but LEDBlinky has one: held back.
        $pairing = Get-TpmLedControlPairing -Cabinet $cabinet -KeyMap $keyMap -Evidence (New-LedEvidence -Devices @{ ArcadeEncoder = 1 })
        @($pairing.Held | Where-Object { $_.Name -eq 'CONTROL_TRACKBALL' -and $_.Reason -eq 'NotDetected' }).Count | Should -Be 1
        $pairing.Usable.Controls.ContainsKey('CONTROL_TRACKBALL') | Should -BeFalse
        @($pairing.Families | Where-Object { $_.Status -eq 'ControlNotDetected' }).Count | Should -Be 1
        # Trackball connected and in LEDBlinky: fine.
        $ok = Get-TpmLedControlPairing -Cabinet $cabinet -KeyMap $keyMap -Evidence (New-LedEvidence -Devices @{ PointerOrTrackball = 1 })
        $ok.Usable.Controls.ContainsKey('CONTROL_TRACKBALL') | Should -BeTrue
        @($ok.Families).Count | Should -Be 0
        # Light gun connected, no light gun control in LEDBlinky: listed.
        $gun = Get-TpmLedControlPairing -Cabinet $cabinet -KeyMap $keyMap -Evidence (New-LedEvidence -Devices @{ PointerOrTrackball = 1; LightGun = 1 })
        @($gun.Families | Where-Object { $_.Family -eq 'Light gun' -and $_.Status -eq 'DetectedNoControl' }).Count | Should -Be 1
        # No usable evidence: no device check, nothing held for devices.
        $none = Get-TpmLedControlPairing -Cabinet $cabinet -KeyMap $keyMap -Evidence (New-LedEvidence -Status 'SourceUnavailable')
        $none.DevicesChecked | Should -BeFalse
        $none.Usable.Controls.ContainsKey('CONTROL_TRACKBALL') | Should -BeTrue
    }

    It 'without an LED map the controls are not checked against LEDs and the Details say so' {
        $fx = New-LedFixture -NoInputMap
        New-LedProfile -Dir $fx.Profiles -Name 'AkaiKatana'
        $plan = Get-TpmLedExportPlan -UserProfilesDir $fx.Profiles -ControlsPath $fx.Controls
        $plan.Groups.Count | Should -Be 1
        $plan.Pairing.KeyMapFound | Should -BeFalse
        (Get-LedDetailText $plan) | Should -Match 'LED map: not found'
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
        $tekno = $new.Substring($new.IndexOf('emuname="TeknoParrot"'))
        $tekno | Should -Match 'groupName="AkaiKatana"'
        $tekno | Should -Match 'groupName="MyOwnGame"'
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

    It 'new entries use the usual arcade colors: buttons 1 to 4 red, yellow, green, blue; other buttons, Start, Coin and the trackball white; other controls keep their own color' {
        (Get-TpmLedSchemeColor -Name 'P1_BUTTON1') | Should -Be 'Red'
        (Get-TpmLedSchemeColor -Name 'P1_BUTTON2') | Should -Be 'Yellow'
        (Get-TpmLedSchemeColor -Name 'P2_BUTTON3') | Should -Be 'Green'
        (Get-TpmLedSchemeColor -Name 'P2_BUTTON4') | Should -Be 'Blue'
        foreach ($n in 'P1_BUTTON5', 'P1_BUTTON6', 'P1_BUTTON7', 'START1', 'COIN2', 'CONTROL_TRACKBALL') { (Get-TpmLedSchemeColor -Name $n) | Should -Be 'White' }
        (Get-TpmLedSchemeColor -Name 'P1_JOYSTICK_UP') | Should -BeNullOrEmpty
        (Get-TpmLedSchemeColor -Name 'CONTROL_JOY8WAY') | Should -BeNullOrEmpty
        $written = @(
            [pscustomobject]@{ Cab = [pscustomobject]@{ Name = 'P1_BUTTON1'; Voice = ''; IsPrimary = $false; Color = 'White'; InputCodes = 'KEYCODE_X'; Player = 1 }; Voice = '' },
            [pscustomobject]@{ Cab = [pscustomobject]@{ Name = 'CONTROL_JOY8WAY'; Voice = ''; IsPrimary = $true; Color = 'Black'; InputCodes = ''; Player = 0 }; Voice = '' }
        )
        $text = New-TpmLedGroupText -Key 'Demo' -Title 'Demo' -Written $written -Newline "`r`n"
        $text | Should -Match 'name="P1_BUTTON1"[^>]*color="Red"'
        $text | Should -Match 'name="CONTROL_JOY8WAY"[^>]*color="Black"'
    }

    It 'a trackball game gets a trackball light even when the user''s default entry has no trackball control' {
        $cabinet = [pscustomobject]@{ Held = @(); Controls = @{}; Names = @() }
        $profile = [pscustomobject]@{ Family = 'trackball'; Controls = @([pscustomobject]@{ Kind = 'Trackball'; Label = 'Trackball'; Player = 0; Exact = $null; Voice = '' }) }
        $match = Get-TpmLedGameMatch -ProfileControls $profile -Cabinet $cabinet
        @($match.Written | ForEach-Object { $_.Cab.Name }) | Should -Contain 'CONTROL_TRACKBALL'
        @($match.NotOnCabinet) | Should -Not -Contain 'Trackball'
    }

    It 'the trackball light takes the main color of the game picture, and a game with no picture keeps white' {
        Add-Type -AssemblyName System.Drawing
        $images = Join-Path $TestDrive 'art-images'
        $marquee = Join-Path $images 'Arcade - Marquee'
        [void][System.IO.Directory]::CreateDirectory($marquee)
        $make = {
            param($file, $color)
            $bmp = New-Object System.Drawing.Bitmap 40, 40
            $g = [System.Drawing.Graphics]::FromImage($bmp); $g.Clear($color); $g.Dispose()
            $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
        }
        & $make (Join-Path $marquee 'Sample Racer-01.png') ([System.Drawing.Color]::FromArgb(30, 60, 220))
        & $make (Join-Path $marquee 'Gray Game-01.png') ([System.Drawing.Color]::FromArgb(128, 128, 128))
        Get-TpmLedArtworkColor -ImageFolders @($images) -Title 'Sample Racer' | Should -Be 'Blue'
        Get-TpmLedArtworkColor -ImageFolders @($images) -Title 'Gray Game' | Should -Be 'White'
        Get-TpmLedArtworkColor -ImageFolders @($images) -Title 'Totally Different Title' | Should -BeNullOrEmpty
        Get-TpmLedArtworkColor -ImageFolders @((Join-Path $TestDrive 'no-such-folder')) -Title 'Sample Racer' | Should -BeNullOrEmpty
        $entry = [pscustomobject]@{ Cab = [pscustomobject]@{ Name = 'CONTROL_TRACKBALL'; Voice = 'Trackball'; IsPrimary = $true; Color = 'White'; InputCodes = $null; Player = 0 }; Voice = 'Trackball'; Color = 'Blue' }
        (New-TpmLedGroupText -Key 'x' -Title 'X' -Written @($entry) -Newline "`n") | Should -Match 'CONTROL_TRACKBALL" voice="Trackball" primaryControl="1" color="Blue"'
    }

    It 'a single-color light gets no color, an RGB light does, and the map decides which is which' {
        $dir = Join-Path $TestDrive ('rgbmap-' + [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($dir)
        $xml = @'
<?xml version="1.0" encoding="UTF-8"?>
<dat><ledController type="1" id="1" name="LEDWiz">
<port number="1" label="P1B1" type="R" inputCodes="KEYCODE_X"/>
<port number="2" label="P1B1" type="G" inputCodes="KEYCODE_X"/>
<port number="3" label="P1B1" type="B" inputCodes="KEYCODE_X"/>
<port number="4" label="P1B2" type="S" inputCodes="KEYCODE_C"/>
</ledController></dat>
'@
        [System.IO.File]::WriteAllText((Join-Path $dir 'LEDBlinkyInputMap.xml'), $xml, (New-Object System.Text.UTF8Encoding $false))
        $map = Get-TpmLedBlinkyKeyMap -Root @($dir)
        ($map.Controls | Where-Object { $_.Control -eq 'P1B1' }).IsRgb | Should -BeTrue
        ($map.Controls | Where-Object { $_.Control -eq 'P1B2' }).IsRgb | Should -BeFalse
        $cab = [pscustomobject]@{ Names = @('P1_BUTTON1', 'P1_BUTTON2'); Players = @(1); Source = 'test'; Held = @(); Controls = @{
            P1_BUTTON1 = [pscustomobject]@{ Name = 'P1_BUTTON1'; Player = 1; Voice = ''; IsPrimary = $false; InputCodes = 'KEYCODE_X'; Color = $null }
            P1_BUTTON2 = [pscustomobject]@{ Name = 'P1_BUTTON2'; Player = 1; Voice = ''; IsPrimary = $false; InputCodes = 'KEYCODE_C'; Color = $null } } }
        $pairing = Get-TpmLedControlPairing -Cabinet $cab -KeyMap $map
        $pairing.Usable.Controls['P1_BUTTON1'].Rgb | Should -BeTrue
        $pairing.Usable.Controls['P1_BUTTON2'].Rgb | Should -BeFalse
        $written = @($pairing.Usable.Names | ForEach-Object { [pscustomobject]@{ Cab = $pairing.Usable.Controls[$_]; Voice = '' } })
        $text = New-TpmLedGroupText -Key 'x' -Title 'X' -Written $written -Newline "`n"
        $text | Should -Match 'P1_BUTTON1" voice="" color="Red"'
        $text | Should -Match 'P1_BUTTON2" voice="" inputCodes="KEYCODE_C"'
        $text | Should -Not -Match 'P1_BUTTON2[^>]*color='
        # No map at all: the light is unknown and the usual color is still written.
        $unknown = Get-TpmLedControlPairing -Cabinet $cab -KeyMap $null
        $unknown.Usable.Controls['P1_BUTTON2'].Rgb | Should -BeNullOrEmpty
    }

    It 'a one-button cabinet and a 32-button cabinet both get only the buttons they have' {
        $small = New-LedFixture -Buttons 1
        New-LedProfile -Dir $small.Profiles -Name 'TinyGame' -Mappings @('P1Button1', 'P1Button2', 'P1Button3')
        $smallPlan = Get-TpmLedExportPlan -UserProfilesDir $small.Profiles -ControlsPath $small.Controls
        $smallPlan.BlockText | Should -Match 'name="P1_BUTTON1"'
        $smallPlan.BlockText | Should -Not -Match 'P1_BUTTON2'
        $smallPlan.BlockText | Should -Not -Match 'P1_BUTTON3'
        $big = New-LedFixture -Buttons 32
        New-LedProfile -Dir $big.Profiles -Name 'BigGame' -Mappings @('P1Button1', 'P1Button17', 'P1Button32')
        $bigPlan = Get-TpmLedExportPlan -UserProfilesDir $big.Profiles -ControlsPath $big.Controls
        $bigPlan.BlockText | Should -Match 'name="P1_BUTTON32"'
        $bigPlan.BlockText | Should -Match 'name="P1_BUTTON17"'
        $bigPlan.BlockText | Should -Not -Match 'P1_BUTTON18'
    }

    It 'keeping the user''s own colors writes the cabinet colors, not the usual scheme or the picture color' {
        $button = [pscustomobject]@{ Name = 'P1_BUTTON1'; Player = 1; Voice = ''; IsPrimary = $false; InputCodes = 'KEYCODE_X'; Color = 'Cyan'; Rgb = $true }
        $ball = [pscustomobject]@{ Name = 'CONTROL_TRACKBALL'; Player = 0; Voice = 'Trackball'; IsPrimary = $true; InputCodes = $null; Color = 'Purple'; Rgb = $true }
        $written = @([pscustomobject]@{ Cab = $button; Voice = '' }, [pscustomobject]@{ Cab = $ball; Voice = 'Trackball'; Color = 'Blue' })
        $usual = New-TpmLedGroupText -Key 'x' -Title 'X' -Written $written -Newline "`n"
        $usual | Should -Match 'P1_BUTTON1" voice="" color="Red"'
        $usual | Should -Match 'CONTROL_TRACKBALL" voice="Trackball" primaryControl="1" color="Blue"'
        $own = New-TpmLedGroupText -Key 'x' -Title 'X' -Written $written -Newline "`n" -KeepOwnColors
        $own | Should -Match 'P1_BUTTON1" voice="" color="Cyan"'
        $own | Should -Match 'CONTROL_TRACKBALL" voice="Trackball" primaryControl="1" color="Purple"'
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
