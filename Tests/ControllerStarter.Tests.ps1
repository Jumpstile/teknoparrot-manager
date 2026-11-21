#Requires -Module Pester

# Controller layout for player 1 (issues #200 and #306).
# What a user sees or loses: the layout they chose once fills free Xbox slots of a game, but only for controls the game's own
# file lists, only when the saved game settings are the same revision as that file, and never over an Xbox binding that is
# already there. Keyboard and arcade-encoder bindings are never touched, a game that has no Xbox setting or that TPM cannot
# check is left alone byte for byte, a preview changes nothing, a backup exists before anything is written, a saved file that
# does not read back correctly is put back exactly, and Undo restores the exact bytes.
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.
# What this CANNOT prove: that TeknoParrot reads the saved bindings and that a real controller presses them.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Controller starter tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:CtlFunctionFile = Join-Path $TestDrive 'tpm-ctl-functions.ps1'
    [System.IO.File]::WriteAllText($script:CtlFunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:CtlFunctionFile
    # The progress bar is not what these tests check, and its module is not loaded here.
    function Write-TpmCompactExtractionProgress { param([Parameter(ValueFromRemainingArguments)]$Ignored) }

    $script:XiXml = '<XInputButton><IsLeftThumbX>false</IsLeftThumbX><IsRightThumbX>false</IsRightThumbX><IsLeftThumbY>false</IsLeftThumbY><IsRightThumbY>false</IsRightThumbY><IsAxisMinus>false</IsAxisMinus><IsLeftTrigger>false</IsLeftTrigger><IsRightTrigger>false</IsRightTrigger><ButtonCode>{0}</ButtonCode><IsButton>true</IsButton><ButtonIndex>0</ButtonIndex><XInputIndex>0</XInputIndex></XInputButton>'

    # The game's own file: what TeknoParrot ships. Nothing is bound in it.
    function script:New-CtlTemplate {
        param([string]$Dir, [string]$Name, [int]$Revision = 5, [string]$Options = '<string>DirectInput</string><string>XInput</string>', [string[]]$Omit = @(), [string]$Up = '')
        $slots = @(
            @('Test', 'Test', ''), @('Coin', 'Coin1', ''), @('Start', 'P1ButtonStart', ''), @('Gun Trigger', 'P1Button1', ''), @('Missile', 'P1Button2', ''),
            @('P2 Start', 'P2ButtonStart', ''), @('Stick X', 'Analog0', '<AnalogType>AnalogJoystick</AnalogType>')
        ) | Where-Object { $Omit -notcontains $_[1] } | ForEach-Object { '<JoystickButtons><ButtonName>{0}</ButtonName><InputMapping>{1}</InputMapping>{2}</JoystickButtons>' -f $_[0], $_[1], $_[2] }
        if ($Up) { $slots += '<JoystickButtons><ButtonName>' + $Up + '</ButtonName><InputMapping>P1ButtonUp</InputMapping></JoystickButtons>' }
        $xml = '<?xml version="1.0" encoding="utf-8"?><GameProfile><EmulationProfile>Emu</EmulationProfile><GameProfileRevision>{0}</GameProfileRevision><ExecutableName>game</ExecutableName><ConfigValues><FieldInformation><CategoryName>General</CategoryName><FieldName>Input API</FieldName><FieldValue>DirectInput</FieldValue><FieldOptions>{1}</FieldOptions></FieldInformation></ConfigValues><JoystickButtons>{2}</JoystickButtons></GameProfile>' -f $Revision, $Options, ($slots -join '')
        $path = Join-Path $Dir ($Name + '.xml')
        [System.IO.File]::WriteAllText($path, $xml, (New-Object System.Text.UTF8Encoding $false))
        return $path
    }

    # The player's saved settings for the same game: Coin has an Xbox binding and a keyboard key, Start a keyboard key,
    # Gun Trigger a DirectInput button, Missile nothing.
    function script:New-CtlProfile {
        param([string]$Dir, [string]$Name, [string]$Options = '<string>DirectInput</string><string>XInput</string>', [string]$Api = 'DirectInput', [int]$Revision = 5, [string]$CoinCode = '99', [string[]]$Omit = @(), [string]$Up = '')
        $slots = @(
            ('<JoystickButtons><ButtonName>Test</ButtonName><InputMapping>Test</InputMapping></JoystickButtons>'),
            ('<JoystickButtons><ButtonName>Coin</ButtonName>{0}<RawInputButton><DevicePath>kbd</DevicePath><DeviceType>Keyboard</DeviceType><KeyboardKey>D5</KeyboardKey></RawInputButton><InputMapping>Coin1</InputMapping></JoystickButtons>' -f ($script:XiXml -f $CoinCode)),
            ('<JoystickButtons><ButtonName>Start</ButtonName><RawInputButton><DevicePath>kbd</DevicePath><DeviceType>Keyboard</DeviceType><KeyboardKey>D1</KeyboardKey></RawInputButton><InputMapping>P1ButtonStart</InputMapping><AnalogType>None</AnalogType></JoystickButtons>'),
            ('<JoystickButtons><ButtonName>Gun Trigger</ButtonName><DirectInputButton><Button>7</Button></DirectInputButton><InputMapping>P1Button1</InputMapping><AnalogType>None</AnalogType></JoystickButtons>'),
            ('<JoystickButtons><ButtonName>Missile</ButtonName><InputMapping>P1Button2</InputMapping><AnalogType>None</AnalogType></JoystickButtons>'),
            ('<JoystickButtons><ButtonName>P2 Start</ButtonName><InputMapping>P2ButtonStart</InputMapping></JoystickButtons>'),
            ('<JoystickButtons><ButtonName>Stick X</ButtonName><InputMapping>Analog0</InputMapping><AnalogType>AnalogJoystick</AnalogType></JoystickButtons>')
            $(if ($Up) { '<JoystickButtons><ButtonName>' + $Up + '</ButtonName><InputMapping>P1ButtonUp</InputMapping><AnalogType>None</AnalogType></JoystickButtons>' })
        )
        $kept = for ($i = 0; $i -lt $slots.Count; $i++) { $mapping = [regex]::Match($slots[$i], '<InputMapping>(.*?)</InputMapping>').Groups[1].Value; if ($Omit -notcontains $mapping) { $slots[$i] } }
        $xml = '<?xml version="1.0" encoding="utf-8"?><GameProfile><EmulationProfile>Emu</EmulationProfile><GameProfileRevision>{0}</GameProfileRevision><ExecutableName>game</ExecutableName><ConfigValues><FieldInformation><CategoryName>General</CategoryName><FieldName>Input API</FieldName><FieldValue>{1}</FieldValue><FieldOptions>{2}</FieldOptions></FieldInformation></ConfigValues><JoystickButtons>{3}</JoystickButtons></GameProfile>' -f $Revision, $Api, $Options, ($kept -join '')
        $path = Join-Path $Dir ($Name + '.xml')
        [System.IO.File]::WriteAllText($path, $xml, (New-Object System.Text.UTF8Encoding $false))
        return $path
    }

    function script:Get-CtlLayout { param([string]$Preset = 'Xbox') return @(Get-TpmBaselineLayout -Baseline (New-TpmBaseline -Preset $Preset)) }
    function script:Get-CtlNode { param($Doc, [string]$Mapping) return @(Get-ButtonNodes $Doc | Where-Object { $_.InputMapping -eq $Mapping })[0] }
}

Describe 'Controller layout choice' {
    BeforeEach {
        $script:State = Join-Path $TestDrive ('state-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    }

    It 'every built-in layout gives each pad button to at most one game control' {
        foreach ($name in (Get-TpmBaselinePresets).Keys) {
            @(Test-TpmBaseline -Baseline (New-TpmBaseline -Preset $name)).Count | Should -Be 0
        }
    }

    It 'the four layouts are Xbox, PlayStation, Nintendo and arcade stick, and Test and Service start empty' {
        @((Get-TpmBaselinePresets).Keys) | Should -Be @('Xbox', 'PlayStation', 'Nintendo', 'ArcadeStick')
        $slots = (New-TpmBaseline -Preset 'Xbox').Slots
        $slots['Test'] | Should -Be ''
        $slots['Service1'] | Should -Be ''
        (Get-CtlLayout 'Xbox' | Where-Object Mapping -in @('Test', 'Service1')).Count | Should -Be 0
    }

    It 'PlayStation and Nintendo use the same buttons by position but show their own names' {
        $xbox = Get-CtlLayout 'Xbox' | Where-Object Mapping -eq 'P1Button1'
        $ps = Get-CtlLayout 'PlayStation' | Where-Object Mapping -eq 'P1Button1'
        $nin = Get-CtlLayout 'Nintendo' | Where-Object Mapping -eq 'P1Button1'
        $ps.Code | Should -Be $xbox.Code
        $nin.Code | Should -Be $xbox.Code
        $xbox.Label | Should -Be 'A'
        $ps.Label | Should -Be 'Cross'
        $nin.Label | Should -Be 'B'
    }

    It 'saves the layout the user chose and reads it back' {
        $b = New-TpmBaseline -Preset 'ArcadeStick'
        Save-TpmBaseline -StateDir $script:State -Baseline $b
        $back = Read-TpmBaseline -StateDir $script:State
        $back.Preset | Should -Be 'ArcadeStick'
        $back.SelectionSource | Should -Be 'UserSelected'
        ($back.Slots | ConvertTo-Json) | Should -Be ($b.Slots | ConvertTo-Json)
    }

    It 'asks again when there is no saved layout or the file is damaged' {
        Read-TpmBaseline -StateDir $script:State | Should -BeNullOrEmpty
        [void][System.IO.Directory]::CreateDirectory($script:State)
        [System.IO.File]::WriteAllText((Get-TpmBaselinePath -StateDir $script:State), '{ not json')
        Read-TpmBaseline -StateDir $script:State | Should -BeNullOrEmpty
    }

    It 'refuses to save or use a layout that puts one pad button on two game controls' {
        $b = New-TpmBaseline -Preset 'Xbox'
        $b.Slots['Test'] = 'A'
        (@(Test-TpmBaseline -Baseline $b) -join ' ') | Should -Match 'used for both'
        { Save-TpmBaseline -StateDir $script:State -Baseline $b } | Should -Throw
        Test-Path (Get-TpmBaselinePath -StateDir $script:State) | Should -BeFalse
    }

    It 'a layout file that a person edited into a duplicate is not used' {
        Save-TpmBaseline -StateDir $script:State -Baseline (New-TpmBaseline -Preset 'Xbox')
        $path = Get-TpmBaselinePath -StateDir $script:State
        $before = [System.IO.File]::ReadAllText($path)
        $after = $before -replace '"Service1":\s*""', '"Service1": "A"'
        $after | Should -Not -BeExactly $before   # the edit must have happened, whatever the JSON spacing of this PowerShell
        [System.IO.File]::WriteAllText($path, $after)
        Read-TpmBaseline -StateDir $script:State | Should -BeNullOrEmpty
    }

    It 'the layout source is plain words and names no machine or personal data' {
        $s = Get-TpmBaselineLayoutSource
        $s | Should -Match 'built-in layouts'
        $s | Should -Not -Match '(?i)[a-z]:\\|\\\\'
    }

    It 'the power reminder names wireless controllers' {
        ((Get-TpmControllerPowerReminder) -join ' ') | Should -Match 'Wireless controllers'
    }
}

Describe 'Controller layout apply' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ('r-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        $script:Dir = Join-Path $script:Root 'UserProfiles'
        $script:Game = Join-Path $script:Root 'GameProfiles'
        [void][System.IO.Directory]::CreateDirectory($script:Dir)
        [void][System.IO.Directory]::CreateDirectory($script:Game)
        $script:Layout = Get-CtlLayout 'Xbox'
        function script:Invoke-CtlApply { param([string]$Path, [bool]$DryRun = $false, [string]$Signature = '', $Layout = $script:Layout) Invoke-TpmBaselineApply -UserProfilesDir $script:Dir -ProfilePath $Path -GameProfilesDir $script:Game -Layout $Layout -DryRun $DryRun -ExpectedSignature $Signature }
    }

    It 'plans Add for free slots, Keep for an existing Xbox binding and NotInGame for controls the game does not list' {
        [void](New-CtlTemplate -Dir $script:Game -Name 'Game1')
        $path = New-CtlProfile -Dir $script:Dir -Name 'Game1'
        $plan = Get-TpmBaselineGamePlan -ProfilePath $path -GameProfilesDir $script:Game -Layout $script:Layout
        $plan.Status | Should -Be 'Ready'
        ($plan.Rows | Where-Object Mapping -eq 'Coin1').Action | Should -Be 'Keep'
        ($plan.Rows | Where-Object Mapping -eq 'P1ButtonStart').Action | Should -Be 'Add'
        ($plan.Rows | Where-Object Mapping -eq 'P1Button1').Action | Should -Be 'Add'
        ($plan.Rows | Where-Object Mapping -eq 'P1Button1').Meaning | Should -Be 'Gun Trigger'
        ($plan.Rows | Where-Object Mapping -eq 'P1Button6').Action | Should -Be 'NotInGame'
        $plan.AddCount | Should -Be 3
        $plan.NeedsApiChange | Should -BeTrue
    }

    It 'names the controls the layout will not fill, so the player knows what is left to do' {
        [void](New-CtlTemplate -Dir $script:Game -Name 'Game1')
        $plan = Get-TpmBaselineGamePlan -ProfilePath (New-CtlProfile -Dir $script:Dir -Name 'Game1') -GameProfilesDir $script:Game -Layout $script:Layout
        $plan.StillNeeds | Should -Be @('Stick X')
        ((Get-TpmBaselinePlanLines -Plan $plan) -join ' ') | Should -Match 'Still needs you in TeknoParrotUI.*Stick X'
    }

    It 'sets a direction button only when the game calls the slot a plain direction' {
        [void](New-CtlTemplate -Dir $script:Game -Name 'GameUp' -Up 'Player 1 Up')
        [void](New-CtlTemplate -Dir $script:Game -Name 'GameMenu' -Up 'Menu Up')
        $plain = Get-TpmBaselineGamePlan -ProfilePath (New-CtlProfile -Dir $script:Dir -Name 'GameUp' -Up 'Player 1 Up') -GameProfilesDir $script:Game -Layout $script:Layout
        ($plain.Rows | Where-Object Mapping -eq 'P1ButtonUp').Action | Should -Be 'Add'
        $menuPath = New-CtlProfile -Dir $script:Dir -Name 'GameMenu' -Up 'Menu Up'
        $menu = Get-TpmBaselineGamePlan -ProfilePath $menuPath -GameProfilesDir $script:Game -Layout $script:Layout
        ($menu.Rows | Where-Object Mapping -eq 'P1ButtonUp').Action | Should -Be 'Ambiguous'
        ((Get-TpmBaselinePlanLines -Plan $menu) -join ' ') | Should -Match 'Not set, because the game does not call them a plain direction.*Menu Up'
        [void](Invoke-CtlApply -Path $menuPath)
        (Read-Xml $menuPath).SelectSingleNode('//JoystickButtons[InputMapping="P1ButtonUp"]/XInputButton') | Should -BeNullOrEmpty
    }

    It 'says so when the game''s player 1 control names are not ones TPM recognizes' {
        $template = New-CtlTemplate -Dir $script:Game -Name 'GameNone'
        [System.IO.File]::WriteAllText($template, '<GameProfile><EmulationProfile>Emu</EmulationProfile><GameProfileRevision>5</GameProfileRevision><ExecutableName>game</ExecutableName><JoystickButtons><JoystickButtons><ButtonName>Special</ButtonName><InputMapping>PokkenButtonStart</InputMapping></JoystickButtons></JoystickButtons></GameProfile>')
        $path = Join-Path $script:Dir 'GameNone.xml'
        [System.IO.File]::WriteAllText($path, '<GameProfile><EmulationProfile>Emu</EmulationProfile><GameProfileRevision>5</GameProfileRevision><ExecutableName>game</ExecutableName><JoystickButtons><JoystickButtons><ButtonName>Special</ButtonName><InputMapping>PokkenButtonStart</InputMapping></JoystickButtons></JoystickButtons></GameProfile>')
        $before = [System.IO.File]::ReadAllBytes($path)
        $r = Invoke-CtlApply -Path $path
        $r.Status | Should -Be 'Refused'
        $r.ReasonCode | Should -Be 'NoControls'
        $r.Reason | Should -Match 'does not recognize the names'
        [System.IO.File]::ReadAllBytes($path) | Should -Be $before
    }

    It 'a preview changes nothing on disk' {
        [void](New-CtlTemplate -Dir $script:Game -Name 'Game1')
        $path = New-CtlProfile -Dir $script:Dir -Name 'Game1'
        $before = [System.IO.File]::ReadAllBytes($path)
        $r = Invoke-CtlApply -Path $path -DryRun $true
        $r.Status | Should -Be 'WouldChange'
        $r.Added | Should -Be 3
        [System.IO.File]::ReadAllBytes($path) | Should -Be $before
        Test-Path (Join-Path $script:Dir 'FullBackup') | Should -BeFalse
    }

    It 'applies the layout, keeps every other binding, reads it back, and makes a backup first' {
        [void](New-CtlTemplate -Dir $script:Game -Name 'Game1')
        $path = New-CtlProfile -Dir $script:Dir -Name 'Game1'
        $r = Invoke-CtlApply -Path $path
        $r.Status | Should -Be 'Changed'
        $r.Verified | Should -BeTrue
        $r.Backup.Verified | Should -BeTrue
        $doc = Read-Xml $path
        Get-ProfileInputApi $doc | Should -Be 'XInput'
        $start = Get-CtlNode $doc 'P1ButtonStart'
        $start.XInputButton.ButtonCode | Should -Be '16'
        $start.RawInputButton.KeyboardKey | Should -Be 'D1'
        $start.ChildNodes[1].Name | Should -Be 'XInputButton'
        $b1 = Get-CtlNode $doc 'P1Button1'
        $b1.XInputButton.ButtonCode | Should -Be '4096'
        $b1.DirectInputButton.Button | Should -Be '7'
        (Get-CtlNode $doc 'Coin1').XInputButton.ButtonCode | Should -Be '99'
        $doc.SelectSingleNode('//JoystickButtons[InputMapping="Test"]/XInputButton') | Should -BeNullOrEmpty
        $doc.SelectSingleNode('//JoystickButtons[InputMapping="P2ButtonStart"]/XInputButton') | Should -BeNullOrEmpty
        $doc.SelectSingleNode('//JoystickButtons[InputMapping="Analog0"]/XInputButton') | Should -BeNullOrEmpty
    }

    It 'the layout the user chose decides the codes, and Test only gets a button the user gave it' {
        [void](New-CtlTemplate -Dir $script:Game -Name 'Game1')
        $path = New-CtlProfile -Dir $script:Dir -Name 'Game1'
        $b = New-TpmBaseline -Preset 'ArcadeStick'
        $b.Slots['Test'] = 'L3'
        $r = Invoke-CtlApply -Path $path -Layout @(Get-TpmBaselineLayout -Baseline $b)
        $r.Status | Should -Be 'Changed'
        $doc = Read-Xml $path
        (Get-CtlNode $doc 'P1Button1').XInputButton.ButtonCode | Should -Be '16384'
        (Get-CtlNode $doc 'Test').XInputButton.ButtonCode | Should -Be '64'
    }

    It 'keeps MergedInput when the game already uses it and still fills free Xbox slots' {
        [void](New-CtlTemplate -Dir $script:Game -Name 'GameM' -Options '<string>DirectInput</string><string>XInput</string><string>MergedInput</string>')
        $path = New-CtlProfile -Dir $script:Dir -Name 'GameM' -Options '<string>DirectInput</string><string>XInput</string><string>MergedInput</string>' -Api 'MergedInput'
        $r = Invoke-CtlApply -Path $path
        $r.Status | Should -Be 'Changed'
        $r.ApiChanged | Should -BeFalse
        Get-ProfileInputApi (Read-Xml $path) | Should -Be 'MergedInput'
    }

    It 'a second apply changes nothing and does not rewrite the file' {
        [void](New-CtlTemplate -Dir $script:Game -Name 'Game1')
        $path = New-CtlProfile -Dir $script:Dir -Name 'Game1'
        [void](Invoke-CtlApply -Path $path)
        $before = [System.IO.File]::ReadAllBytes($path)
        $r = Invoke-CtlApply -Path $path
        $r.Status | Should -Be 'NoChange'
        [System.IO.File]::ReadAllBytes($path) | Should -Be $before
    }

    It 'a batch makes one backup for many games' {
        foreach ($n in 'GameA', 'GameB') { [void](New-CtlTemplate -Dir $script:Game -Name $n) }
        $a = New-CtlProfile -Dir $script:Dir -Name 'GameA'
        $b = New-CtlProfile -Dir $script:Dir -Name 'GameB'
        $r = Invoke-TpmBaselineBatch -UserProfilesDir $script:Dir -ProfilePaths @($a, $b) -GameProfilesDir $script:Game -Layout $script:Layout -DryRun $false
        $r.Changed | Should -Be 2
        $r.Failed | Should -Be 0
        @(Get-ChildItem (Join-Path $script:Dir 'FullBackup') -Directory).Count | Should -Be 1
    }

    It 'a batch preview writes nothing, makes no backup, and says why games are left alone' {
        [void](New-CtlTemplate -Dir $script:Game -Name 'GameA')
        $a = New-CtlProfile -Dir $script:Dir -Name 'GameA'
        $noFile = New-CtlProfile -Dir $script:Dir -Name 'GameNoFile'
        $r = Invoke-TpmBaselineBatch -UserProfilesDir $script:Dir -ProfilePaths @($a, $noFile) -GameProfilesDir $script:Game -Layout $script:Layout -DryRun $true
        $r.Changed | Should -Be 1
        $r.Refused | Should -Be 1
        Test-Path (Join-Path $script:Dir 'FullBackup') | Should -BeFalse
        ((Get-TpmBaselineBatchLines -Batch $r -DryRun $true) -join ' ') | Should -Match 'Left alone: 1 game\..*could not find TeknoParrot'
    }

    It 'leaves a game alone when it has no Xbox setting' {
        [void](New-CtlTemplate -Dir $script:Game -Name 'Game2' -Options '<string>DirectInput</string>')
        $path = New-CtlProfile -Dir $script:Dir -Name 'Game2' -Options '<string>DirectInput</string>'
        $before = [System.IO.File]::ReadAllBytes($path)
        $r = Invoke-CtlApply -Path $path
        $r.Status | Should -Be 'Unsupported'
        [System.IO.File]::ReadAllBytes($path) | Should -Be $before
    }

    It 'leaves a game alone when TeknoParrot''s own file for it is missing' {
        $path = New-CtlProfile -Dir $script:Dir -Name 'Game3'
        $before = [System.IO.File]::ReadAllBytes($path)
        $r = Invoke-CtlApply -Path $path
        $r.Status | Should -Be 'Refused'
        $r.ReasonCode | Should -Be 'NoTemplate'
        [System.IO.File]::ReadAllBytes($path) | Should -Be $before
        Test-Path (Join-Path $script:Dir 'FullBackup') | Should -BeFalse
    }

    It 'leaves a game alone when its saved settings are an older revision than the game file' {
        [void](New-CtlTemplate -Dir $script:Game -Name 'Game4' -Revision 6)
        $path = New-CtlProfile -Dir $script:Dir -Name 'Game4' -Revision 5
        $before = [System.IO.File]::ReadAllBytes($path)
        $r = Invoke-CtlApply -Path $path
        $r.Status | Should -Be 'Refused'
        $r.ReasonCode | Should -Be 'Stale'
        $r.Reason | Should -Match 'Open the game once in TeknoParrotUI'
        [System.IO.File]::ReadAllBytes($path) | Should -Be $before
    }

    It 'leaves a game alone when a control the game file lists is missing from the saved settings' {
        [void](New-CtlTemplate -Dir $script:Game -Name 'Game5')
        $path = New-CtlProfile -Dir $script:Dir -Name 'Game5' -Omit @('P1Button2')
        $before = [System.IO.File]::ReadAllBytes($path)
        $r = Invoke-CtlApply -Path $path
        $r.ReasonCode | Should -Be 'FieldMissing'
        [System.IO.File]::ReadAllBytes($path) | Should -Be $before
    }

    It 'leaves a game alone when an Xbox button the layout wants is already used by another control' {
        [void](New-CtlTemplate -Dir $script:Game -Name 'Game6')
        # Coin already uses the A button (4096); the layout wants A for Button 1.
        $path = New-CtlProfile -Dir $script:Dir -Name 'Game6' -CoinCode '4096'
        $before = [System.IO.File]::ReadAllBytes($path)
        $r = Invoke-CtlApply -Path $path
        $r.Status | Should -Be 'Refused'
        $r.ReasonCode | Should -Be 'Collision'
        [System.IO.File]::ReadAllBytes($path) | Should -Be $before
    }

    It 'writes nothing when the game files changed after the preview the user approved' {
        [void](New-CtlTemplate -Dir $script:Game -Name 'Game7')
        $path = New-CtlProfile -Dir $script:Dir -Name 'Game7'
        $preview = Invoke-CtlApply -Path $path -DryRun $true
        [void](New-CtlTemplate -Dir $script:Game -Name 'Game7' -Revision 5 -Omit @('P1Button2'))
        $before = [System.IO.File]::ReadAllBytes($path)
        $r = Invoke-CtlApply -Path $path -Signature $preview.Signature
        $r.Status | Should -Be 'Refused'
        $r.ReasonCode | Should -Be 'Changed'
        [System.IO.File]::ReadAllBytes($path) | Should -Be $before
        Test-Path (Join-Path $script:Dir 'FullBackup') | Should -BeFalse
    }

    It 'puts the exact old bytes back when the saved file does not read back correctly' {
        [void](New-CtlTemplate -Dir $script:Game -Name 'Game8')
        $path = New-CtlProfile -Dir $script:Dir -Name 'Game8'
        $before = [System.IO.File]::ReadAllBytes($path)
        Mock Test-TpmBaselineWritten { 'A button that should not change was changed.' }
        $r = Invoke-CtlApply -Path $path
        $r.Status | Should -Be 'Failed'
        $r.Verified | Should -BeFalse
        [System.IO.File]::ReadAllBytes($path) | Should -Be $before
    }

    It 'the read-back check catches a button that changed when it should not have' {
        [void](New-CtlTemplate -Dir $script:Game -Name 'Game9')
        $path = New-CtlProfile -Dir $script:Dir -Name 'Game9'
        $plan = Get-TpmBaselineGamePlan -ProfilePath $path -GameProfilesDir $script:Game -Layout $script:Layout
        $before = @(Get-ButtonNodes $plan.Doc | ForEach-Object { $_.OuterXml })
        foreach ($row in @($plan.Rows | Where-Object Action -eq 'Add')) { Add-TpmXInputBinding -Doc $plan.Doc -ButtonNode $row.Node -Code $row.Code }
        [void](Set-ProfileInputApi $plan.Doc 'XInput')
        Test-TpmBaselineWritten -Doc $plan.Doc -Plan $plan -BeforeXml $before | Should -Be ''
        (Get-CtlNode $plan.Doc 'Analog0').SelectSingleNode('ButtonName').InnerText = 'Changed'
        Test-TpmBaselineWritten -Doc $plan.Doc -Plan $plan -BeforeXml $before | Should -Match 'should not change'
    }

    It 'Undo puts the exact bytes of every changed game back' {
        foreach ($n in 'GameA', 'GameB') { [void](New-CtlTemplate -Dir $script:Game -Name $n) }
        $a = New-CtlProfile -Dir $script:Dir -Name 'GameA'
        $b = New-CtlProfile -Dir $script:Dir -Name 'GameB'
        $beforeA = [System.IO.File]::ReadAllBytes($a)
        $beforeB = [System.IO.File]::ReadAllBytes($b)
        $r = Invoke-TpmBaselineBatch -UserProfilesDir $script:Dir -ProfilePaths @($a, $b) -GameProfilesDir $script:Game -Layout $script:Layout -DryRun $false
        $r.Changed | Should -Be 2
        [System.IO.File]::ReadAllBytes($a) | Should -Not -Be $beforeA
        $undo = Invoke-RestoreBackup -userProfilesDir $script:Dir -SelectedBackupPath ([string]$r.Backup.Path) -AlreadyConfirmed
        $undo.Outcome | Should -Be 'SUCCEEDED'
        [System.IO.File]::ReadAllBytes($a) | Should -Be $beforeA
        [System.IO.File]::ReadAllBytes($b) | Should -Be $beforeB
    }
}

Describe 'Library health Controls line' {
    It 'shows the counts, says the games were not tested, and does not say OK' {
        $audit = [pscustomobject]@{ Total = 4; Complete = 1; Partial = 1; Missing = 1; Unknown = 1; Unsupported = 0; ReadOnly = $true; Rows = @() }
        $result = [pscustomobject]@{
            DiscoveryComplete = $true; Registered = 4; Broken = @(); Empty = @(); Valid = @('a'); Unreadable = @()
            GpuFixNeeded = @(); FfbBlasterNeeded = @(); DgVoodoo2Needed = @(); ControlCoverage = $audit
        }
        $row = @(Get-TpmLibraryHealthRows -Result $result | Where-Object Area -eq 'Controls')
        $row.Count | Should -Be 1
        $row[0].Text | Should -Match '^Note - 1 of 4 games have every control the game lists set up \(not tested in a game\)'
        $row[0].Text | Should -Match '2 games have some or all missing'
        $row[0].Text | Should -Match 'TPM cannot check 1 game'
        $row[0].Text | Should -Not -Match '^OK'
    }

    It 'has no Controls line when the check could not run' {
        $result = [pscustomobject]@{
            DiscoveryComplete = $true; Registered = 4; Broken = @(); Empty = @(); Valid = @('a'); Unreadable = @()
            GpuFixNeeded = @(); FfbBlasterNeeded = @(); DgVoodoo2Needed = @(); ControlCoverage = $null
        }
        @(Get-TpmLibraryHealthRows -Result $result | Where-Object Area -eq 'Controls').Count | Should -Be 0
    }
}
