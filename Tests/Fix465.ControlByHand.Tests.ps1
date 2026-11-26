#Requires -Module Pester

# Change a control by hand (Controls, choice 5). What a user sees or loses: a control set by hand is kept when TPM later sets up
# games or learns buttons, TPM says so in plain words, a cancel changes nothing, and "put TPM's choice back" restores TPM's choice.
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.
# What this CANNOT prove: that TeknoParrot reads the saved bindings and that a real controller presses them.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Control by hand tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:CbhFunctionFile = Join-Path $TestDrive 'tpm-cbh-functions.ps1'
    [System.IO.File]::WriteAllText($script:CbhFunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:CbhFunctionFile
    function Write-TpmCompactExtractionProgress { param([Parameter(ValueFromRemainingArguments)]$Ignored) }

    $script:XiXml = '<XInputButton><IsLeftThumbX>false</IsLeftThumbX><IsRightThumbX>false</IsRightThumbX><IsLeftThumbY>false</IsLeftThumbY><IsRightThumbY>false</IsRightThumbY><IsAxisMinus>false</IsAxisMinus><IsLeftTrigger>false</IsLeftTrigger><IsRightTrigger>false</IsRightTrigger><ButtonCode>{0}</ButtonCode><IsButton>true</IsButton><ButtonIndex>0</ButtonIndex><XInputIndex>0</XInputIndex></XInputButton>'

    # The game's own file: what TeknoParrot ships. Nothing is bound in it.
    function script:New-CbhTemplate {
        param([string]$Dir, [string]$Name)
        $slots = @(@('Coin', 'Coin1'), @('Start', 'P1ButtonStart'), @('Gun Trigger', 'P1Button1'), @('Missile', 'P1Button2')) | ForEach-Object { '<JoystickButtons><ButtonName>{0}</ButtonName><InputMapping>{1}</InputMapping></JoystickButtons>' -f $_[0], $_[1] }
        $xml = '<?xml version="1.0" encoding="utf-8"?><GameProfile><EmulationProfile>Emu</EmulationProfile><GameProfileRevision>5</GameProfileRevision><ExecutableName>game</ExecutableName><ConfigValues><FieldInformation><CategoryName>General</CategoryName><FieldName>Input API</FieldName><FieldValue>DirectInput</FieldValue><FieldOptions><string>DirectInput</string><string>XInput</string></FieldOptions></FieldInformation></ConfigValues><JoystickButtons>{0}</JoystickButtons></GameProfile>' -f ($slots -join '')
        $path = Join-Path $Dir ($Name + '.xml')
        [System.IO.File]::WriteAllText($path, $xml, (New-Object System.Text.UTF8Encoding $false))
    }

    # The player's saved settings: Coin has an Xbox binding, Start a keyboard key, Gun Trigger a DirectInput button, Missile nothing.
    function script:New-CbhProfile {
        param([string]$Dir, [string]$Name)
        $slots = @(
            ('<JoystickButtons><ButtonName>Coin</ButtonName>{0}<InputMapping>Coin1</InputMapping><AnalogType>None</AnalogType></JoystickButtons>' -f ($script:XiXml -f '99')),
            ('<JoystickButtons><ButtonName>Start</ButtonName><RawInputButton><DevicePath>kbd</DevicePath><DeviceType>Keyboard</DeviceType><KeyboardKey>D1</KeyboardKey></RawInputButton><InputMapping>P1ButtonStart</InputMapping><AnalogType>None</AnalogType></JoystickButtons>'),
            ('<JoystickButtons><ButtonName>Gun Trigger</ButtonName><DirectInputButton><Button>7</Button></DirectInputButton><InputMapping>P1Button1</InputMapping><AnalogType>None</AnalogType></JoystickButtons>'),
            ('<JoystickButtons><ButtonName>Missile</ButtonName><InputMapping>P1Button2</InputMapping><AnalogType>None</AnalogType></JoystickButtons>')
        )
        $xml = '<?xml version="1.0" encoding="utf-8"?><GameProfile><EmulationProfile>Emu</EmulationProfile><GameProfileRevision>5</GameProfileRevision><ExecutableName>game</ExecutableName><ConfigValues><FieldInformation><CategoryName>General</CategoryName><FieldName>Input API</FieldName><FieldValue>DirectInput</FieldValue><FieldOptions><string>DirectInput</string><string>XInput</string></FieldOptions></FieldInformation></ConfigValues><JoystickButtons>{0}</JoystickButtons></GameProfile>' -f ($slots -join '')
        $path = Join-Path $Dir ($Name + '.xml')
        [System.IO.File]::WriteAllText($path, $xml, (New-Object System.Text.UTF8Encoding $false))
        return $path
    }

    function script:Get-CbhNode { param($Doc, [string]$Mapping) return @(Get-ButtonNodes $Doc | Where-Object { $_.InputMapping -eq $Mapping })[0] }
    function script:Get-CbhBytes { param([string]$Path) if (Test-Path -LiteralPath $Path) { return [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path)) } return '' }
}

Describe 'Change a control by hand: pad buttons' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ('r-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        $script:Dir = Join-Path $script:Root 'UserProfiles'
        $script:Game = Join-Path $script:Root 'GameProfiles'
        $script:State = Join-Path $script:Root 'State'
        foreach ($d in @($script:Dir, $script:Game, $script:State)) { [void][System.IO.Directory]::CreateDirectory($d) }
        New-CbhTemplate -Dir $script:Game -Name 'Game1'
        $script:Path = New-CbhProfile -Dir $script:Dir -Name 'Game1'
        $script:Layout = @(Get-TpmBaselineLayout -Baseline (New-TpmBaseline -Preset 'Xbox'))
        function script:Invoke-CbhApply { param([bool]$DryRun = $false) Invoke-TpmBaselineApply -UserProfilesDir $script:Dir -ProfilePath $script:Path -GameProfilesDir $script:Game -Layout $script:Layout -DryRun $DryRun -StateRoot $script:State }
    }

    It 'a button set by hand survives a later layout run, and the run says so' {
        # Mutation: make the layout plan ignore the saved list -> Missile is not Y (32768) and the line is missing.
        $set = Set-TpmManualPadBinding -UserProfilesDir $script:Dir -ProfilePath $script:Path -Mapping 'P1Button2' -Code 32768 -SwitchApi $true -StateRoot $script:State
        $set.Status | Should -Be 'Changed'
        $set.Backup.Verified | Should -BeTrue
        (Get-CbhNode (Read-Xml $script:Path) 'P1Button2').XInputButton.ButtonCode | Should -Be '32768'
        $run = Invoke-CbhApply
        $run.Status | Should -Be 'Changed'
        $run.Own | Should -Be 1
        $doc = Read-Xml $script:Path
        (Get-CbhNode $doc 'P1Button2').XInputButton.ButtonCode | Should -Be '32768'
        (Get-CbhNode $doc 'P1ButtonStart').XInputButton.ButtonCode | Should -Be '16'
        ((Get-TpmBaselinePlanLines -Plan $run.Plan) -join ' ') | Should -Match 'Kept your own setting for 1 control\.'
    }

    It 'a button cleared by hand stays empty, and a batch preview says how many were kept' {
        $set = Set-TpmManualPadBinding -UserProfilesDir $script:Dir -ProfilePath $script:Path -Mapping 'Coin1' -Code -1 -StateRoot $script:State
        $set.Status | Should -Be 'Changed'
        (Get-CbhNode (Read-Xml $script:Path) 'Coin1').XInputButton | Should -BeNullOrEmpty
        $batch = Invoke-TpmBaselineBatch -UserProfilesDir $script:Dir -ProfilePaths @($script:Path) -GameProfilesDir $script:Game -Layout $script:Layout -DryRun $true -StateRoot $script:State
        (Get-TpmBaselineBatchLines -Batch $batch -DryRun $true) -join ' ' | Should -Match 'Kept your own setting for 1 control\.'
        [void](Invoke-CbhApply)
        (Get-CbhNode (Read-Xml $script:Path) 'Coin1').XInputButton | Should -BeNullOrEmpty
    }

    It 'a game kept on its own input type is not switched and gets no pad buttons' {
        Set-TpmOwnControl -Game 'Game1' -Control 'InputType' -Kind InputType -Value 'Leave' -StateRoot $script:State
        $before = Get-CbhBytes $script:Path
        $run = Invoke-CbhApply
        $run.Status | Should -Be 'NoChange'
        Get-CbhBytes $script:Path | Should -Be $before
        (Get-ProfileInputApi (Read-Xml $script:Path)) | Should -Be 'DirectInput'
    }

    It 'put TPM''s choice back restores the layout button and the control is no longer the player''s own' {
        # Mutation: leave the saved mark in place -> the next run still says it kept the control.
        [void](Set-TpmManualPadBinding -UserProfilesDir $script:Dir -ProfilePath $script:Path -Mapping 'P1Button2' -Code 32768 -SwitchApi $true -StateRoot $script:State)
        $back = Restore-TpmOwnPadChoice -UserProfilesDir $script:Dir -ProfilePath $script:Path -Mapping 'P1Button2' -Layout $script:Layout -StateRoot $script:State
        $back.Status | Should -Be 'Changed'
        (Get-CbhNode (Read-Xml $script:Path) 'P1Button2').XInputButton.ButtonCode | Should -Be '8192'
        (Get-TpmOwnControl -Own (Read-TpmOwnControls -StateRoot $script:State) -Game 'Game1' -Control 'P1Button2') | Should -BeNullOrEmpty
        (Invoke-CbhApply).Own | Should -Be 0
    }

    It 'put TPM''s choice back restores what the control had when the layout has no button for it' {
        $path = $script:Path
        [void](Set-TpmManualPadBinding -UserProfilesDir $script:Dir -ProfilePath $path -Mapping 'Coin1' -Code 4096 -StateRoot $script:State)
        $back = Restore-TpmOwnPadChoice -UserProfilesDir $script:Dir -ProfilePath $path -Mapping 'Coin1' -Layout @() -StateRoot $script:State
        $back.Status | Should -Be 'Changed'
        (Get-CbhNode (Read-Xml $path) 'Coin1').XInputButton.ButtonCode | Should -Be '99'
    }

    It 'a failed read-back puts the exact old bytes back and remembers nothing' {
        $before = Get-CbhBytes $script:Path
        Mock Get-ProfileInputApi { 'DirectInput' }
        $set = Set-TpmManualPadBinding -UserProfilesDir $script:Dir -ProfilePath $script:Path -Mapping 'P1Button2' -Code 32768 -SwitchApi $true -StateRoot $script:State
        $set.Status | Should -Be 'Failed'
        Get-CbhBytes $script:Path | Should -Be $before
        (Read-TpmOwnControls -StateRoot $script:State).Items.Count | Should -Be 0
    }

    It 'leaves a game alone, byte for byte, when the list of hand-set controls cannot be read' {
        [System.IO.File]::WriteAllText((Get-TpmControlStatePath -StateRoot $script:State).Own, '{ not json', (New-Object System.Text.UTF8Encoding $false))
        $before = Get-CbhBytes $script:Path
        $run = Invoke-CbhApply
        $run.Status | Should -Be 'Refused'
        $run.Reason | Should -Match 'list of controls you set by hand'
        Get-CbhBytes $script:Path | Should -Be $before
    }
}

Describe 'Change a control by hand: arcade keys' {
    BeforeEach {
        $script:State = Join-Path $TestDrive ('s-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        Mock Write-TpmText {}
        Mock Write-Log {}
    }

    It 'Esc or no press changes nothing and writes nothing' {
        $cabinet = (Get-TpmControlStatePath -StateRoot $script:State).Cabinet
        (Set-TpmManualKey -Control 'P1Button1' -ReadKey { 'Escape' } -StateRoot $script:State).Status | Should -Be 'Cancelled'
        (Set-TpmManualKey -Control 'P1Button1' -ReadKey { '' } -StateRoot $script:State).Status | Should -Be 'Cancelled'
        Test-Path -LiteralPath $cabinet | Should -BeFalse
        Test-Path -LiteralPath (Get-TpmControlStatePath -StateRoot $script:State).Own | Should -BeFalse
    }

    It 'refuses a key another control already uses and changes nothing' {
        $state = Read-TpmCabinetState -StateRoot $script:State
        Set-TpmCabinetKeys -State $state -Keys @{ P1Button2 = @{ Key = 'W'; Source = 'PressedByPlayer' } }
        Save-TpmCabinetState -State $state -StateRoot $script:State
        $before = Get-CbhBytes (Get-TpmControlStatePath -StateRoot $script:State).Cabinet
        $r = Set-TpmManualKey -Control 'P1Button1' -ReadKey { 'W' } -StateRoot $script:State
        $r.Status | Should -Be 'Refused'
        Get-CbhBytes (Get-TpmControlStatePath -StateRoot $script:State).Cabinet | Should -Be $before
    }

    It 'a key set by hand is kept when the player learns the buttons again, and put-back restores the earlier key' {
        # Mutation: skip the saved list in Invoke-TpmButtonLearning -> Player 1 button 1 is asked again and gets a new key.
        $state = Read-TpmCabinetState -StateRoot $script:State
        Set-TpmCabinetKeys -State $state -Keys @{ P1Button1 = @{ Key = 'Z'; Source = 'PressedByPlayer' }; P1Button2 = @{ Key = 'X'; Source = 'PressedByPlayer' } }
        Save-TpmCabinetState -State $state -StateRoot $script:State
        (Set-TpmManualKey -Control 'P1Button1' -ReadKey { 'Q' } -StateRoot $script:State).Status | Should -Be 'Changed'
        Get-TpmCabinetKey -State (Read-TpmCabinetState -StateRoot $script:State) -Control 'P1Button1' | Should -Be 'Q'

        $script:KeyCount = 0
        $script:Said = New-Object System.Collections.Generic.List[string]
        Mock Write-TpmText { $script:Said.Add([string]$Text) }
        Mock Test-TpmKeyPressAvailable { $true }
        Mock Get-TpmKeysPressedOnTheirOwn { @() }
        Mock Get-TpmLedBlinkyKeyMap { [pscustomobject]@{ Found = $false; Controls = @() } }
        Mock Get-TpmControllerEvidence { $null }
        Mock Get-TpmControllerSalt { '' }
        Mock Read-TpmChoice { $Default }
        Mock Read-TpmYesNo { if ($Prompt -like '*Save this*') { 'Y' } else { 'N' } }
        Mock Read-TpmLearnKey { $script:KeyCount++; 'F' + $script:KeyCount }
        Invoke-TpmButtonLearning -StateRoot $script:State
        $after = Read-TpmCabinetState -StateRoot $script:State
        Get-TpmCabinetKey -State $after -Control 'P1Button1' | Should -Be 'Q'
        Get-TpmCabinetKey -State $after -Control 'P1Button2' | Should -Match '^F\d+$'
        ($script:Said -join ' ') | Should -Match 'Kept your own setting for 1 control\.'

        $back = Set-TpmManualKey -Control 'P1Button1' -PutBack -StateRoot $script:State
        $back.Status | Should -Be 'Changed'
        Get-TpmCabinetKey -State (Read-TpmCabinetState -StateRoot $script:State) -Control 'P1Button1' | Should -Be 'Z'
        (Get-TpmOwnControl -Own (Read-TpmOwnControls -StateRoot $script:State) -Game '*' -Control 'P1Button1') | Should -BeNullOrEmpty
    }

    It 'a key cleared by hand stays cleared when the player learns the buttons again' {
        $state = Read-TpmCabinetState -StateRoot $script:State
        Set-TpmCabinetKeys -State $state -Keys @{ P1Button1 = @{ Key = 'Z'; Source = 'PressedByPlayer' } }
        Save-TpmCabinetState -State $state -StateRoot $script:State
        (Set-TpmManualKey -Control 'P1Button1' -Clear -StateRoot $script:State).Status | Should -Be 'Changed'
        Get-TpmCabinetKey -State (Read-TpmCabinetState -StateRoot $script:State) -Control 'P1Button1' | Should -Be ''
        $script:KeyCount = 0; $script:Asked = New-Object System.Collections.Generic.List[string]
        Mock Test-TpmKeyPressAvailable { $true }
        Mock Get-TpmKeysPressedOnTheirOwn { @() }
        Mock Get-TpmLedBlinkyKeyMap { [pscustomobject]@{ Found = $false; Controls = @() } }
        Mock Get-TpmControllerEvidence { $null }
        Mock Get-TpmControllerSalt { '' }
        Mock Read-TpmChoice { $Default }
        Mock Read-TpmYesNo { if ($Prompt -like '*Save this*') { 'Y' } else { 'N' } }
        Mock Write-TpmText { if ([string]$Text -like '*Press Player 1 button 1*') { $script:Asked.Add([string]$Text) } }
        Mock Read-TpmLearnKey { $script:KeyCount++; 'F' + $script:KeyCount }
        Invoke-TpmButtonLearning -StateRoot $script:State
        $script:Asked.Count | Should -Be 0
        Get-TpmCabinetKey -State (Read-TpmCabinetState -StateRoot $script:State) -Control 'P1Button1' | Should -Be ''
    }
}
