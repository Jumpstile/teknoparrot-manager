#Requires -Module Pester

# Learned arcade controls screen and trackball (#508).
# What a user sees or loses: the learned-controls layout lists the real saved keys grouped by player, menu controls and trackball
# before the keep/change question; a game's own DirectInput button number and device show in plain words; the trackball is learned
# only from clearly sideways or up-and-down movement; saving a trackball keeps every saved key; games that use a trackball are
# split into "says it can" and "set up by hand".
# What this CANNOT prove: that a real trackball moves the pointer the way the fake movement does, or that any game accepts it.
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Fix508 tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:FunctionFile = Join-Path $TestDrive 'tpm-508-functions.ps1'
    [System.IO.File]::WriteAllText($script:FunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:FunctionFile
    function script:New-StateFolder { $d = Join-Path $TestDrive ('d-' + [guid]::NewGuid().ToString('N').Substring(0, 8)); [void][System.IO.Directory]::CreateDirectory($d); return $d }
    function script:New-ButtonNode { param([string]$Inner) return ([xml]"<JoystickButtons>$Inner</JoystickButtons>").JoystickButtons }
}

Describe 'Saved learned controls are listed by group' {
    BeforeEach { Mock Write-Log { } }

    It 'shows each saved key under Player 1, Player 2, menu controls and trackball' {
        $root = New-StateFolder
        $cabinet = Read-TpmCabinetState -StateRoot $root
        Set-TpmCabinetKeys -State $cabinet -Keys @{ Coin1 = @{ Key = '5'; Source = 'PressedByPlayer' }; P1ButtonStart = @{ Key = '1'; Source = 'PressedByPlayer' }; P1Button8 = @{ Key = 'Q'; Source = 'PressedByPlayer' }; P2ButtonStart = @{ Key = '2'; Source = 'PressedByPlayer' }; Test = @{ Key = 'F2'; Source = 'PressedByPlayer' } } -Players 2 -ButtonsPerPlayer 8
        $text = (Get-TpmLearnedControlLines -Cabinet $cabinet) -join "`n"
        $text | Should -Match '(?s)Player 1.*Coin: keyboard key 5.*Start: keyboard key 1.*Button 8: keyboard key Q.*Player 2.*Start: keyboard key 2.*Menu and admin controls.*Test button: keyboard key F2.*Trackball'
        $text | Should -Match 'Button 2: not learned'
        $text | Should -Not -Match 'Player 3'
    }

    It 'says "not learned" and "not verified with a real trackball" when nothing is saved' {
        $cabinet = Read-TpmCabinetState -StateRoot (New-StateFolder)
        $text = (Get-TpmLearnedControlLines -Cabinet $cabinet) -join "`n"
        $text | Should -Match 'Left and right \(X\): not learned'
        $text | Should -Match 'not verified with a real trackball'
    }

    It 'puts the saved assignments on the learned-layout screen text, and not on the other layouts' {
        $cabinet = Read-TpmCabinetState -StateRoot (New-StateFolder)
        Set-TpmCabinetKeys -State $cabinet -Keys @{ P1ButtonStart = @{ Key = '1'; Source = 'PressedByPlayer' } }
        $learned = (Get-TpmBaselineSummaryLines -Baseline (New-TpmBaseline -Preset 'LearnedArcade') -Cabinet $cabinet) -join "`n"
        $learned | Should -Match 'as they are'
        $learned | Should -Match 'Start: keyboard key 1'
        ((Get-TpmBaselineSummaryLines -Baseline (New-TpmBaseline -Preset 'Xbox') -Cabinet $cabinet) -join "`n") | Should -Not -Match 'keyboard key'
    }
}

Describe 'A game control is shown with its real button, axis and device' {
    It 'names a DirectInput button number and device' {
        $node = New-ButtonNode '<DirectInputButton><JoystickGuid>stick-1</JoystickGuid><Button>3</Button></DirectInputButton>'
        Get-TpmBindingWords -ButtonNode $node | Should -Be 'controller button 3 (DirectInput) on device stick-1'
    }
    It 'names an axis and its direction' {
        $node = New-ButtonNode '<DirectInputButton><IsAxis>true</IsAxis><IsAxisMinus>true</IsAxisMinus><Button>1</Button></DirectInputButton>'
        Get-TpmBindingWords -ButtonNode $node | Should -Be 'controller axis 1, minus direction (DirectInput)'
    }
    It 'keeps the plain words when the file gives no number' {
        Get-TpmBindingWords -ButtonNode (New-ButtonNode '<DirectInputButton>1</DirectInputButton>') | Should -Be 'a controller button (DirectInput)'
    }
    It 'shows a keyboard key as before' {
        $node = New-ButtonNode '<RawInputButton><DevicePath>kbd</DevicePath><KeyboardKey>D1</KeyboardKey></RawInputButton>'
        Get-TpmBindingWords -ButtonNode $node | Should -Be 'keyboard key 1'
    }
}

Describe 'Trackball learning' {
    BeforeEach {
        Mock Write-Host { }
        Mock Write-TpmText { }
        Mock Write-Log { }
    }

    It 'accepts sideways then up-and-down movement' {
        $moves = [System.Collections.Queue]::new()
        $moves.Enqueue([pscustomobject]@{ Dx = 300; Dy = 20 }); $moves.Enqueue([pscustomobject]@{ Dx = 10; Dy = 280 })
        $result = Invoke-TpmLearnTrackballAxes -ReadMove { $moves.Dequeue() }
        ($result.Learned -join ',') | Should -Be 'X,Y'
        $result.Stopped | Should -BeFalse
    }

    It 'refuses the wrong direction and a diagonal roll, then accepts a clean one' {
        $moves = [System.Collections.Queue]::new()
        foreach ($m in @(@(10, 300), @(200, 200), @(300, 10), @(5, 250))) { $moves.Enqueue([pscustomobject]@{ Dx = $m[0]; Dy = $m[1] }) }
        $result = Invoke-TpmLearnTrackballAxes -ReadMove { $moves.Dequeue() }
        ($result.Learned -join ',') | Should -Be 'X,Y'
        $moves.Count | Should -Be 0
    }

    It 'stops cleanly when nothing moves and the player says stop' {
        Mock Read-TpmYesNo { 'Y' }
        $result = Invoke-TpmLearnTrackballAxes -ReadMove { '' }
        $result.Learned.Count | Should -Be 0
        $result.Stopped | Should -BeTrue
    }

    It 'saves the trackball and keeps every key already saved' {
        $root = New-StateFolder
        $cabinet = Read-TpmCabinetState -StateRoot $root
        Set-TpmCabinetKeys -State $cabinet -Keys @{ P1ButtonStart = @{ Key = '1'; Source = 'PressedByPlayer' } } -Players 2 -ButtonsPerPlayer 6
        Save-TpmCabinetState -State $cabinet -StateRoot $root
        Mock Read-TpmYesNo { 'Y' }
        Mock Get-TpmPointingDeviceNames { @('Test ball') }
        Mock Read-TpmTrackballDevice { [pscustomobject]@{ Path = '\\?\HID#VID_1234&PID_5678#7&abc&0&0000#{378de44c-56ef-11d1-bc8c-00a0c91405dd}'; Name = 'Example Trackball' } }
        Mock Read-TpmMouseMove { [pscustomobject]@{ Dx = 300; Dy = 10 } }
        $script:call = 0
        Mock Invoke-TpmLearnTrackballAxes { [pscustomobject]@{ Learned = @('X', 'Y'); Stopped = $false } }
        Invoke-TpmTrackballLearning -StateRoot $root
        $after = Read-TpmCabinetState -StateRoot $root
        Get-TpmCabinetKey -State $after -Control 'P1ButtonStart' | Should -Be '1'
        $after.Players | Should -Be 2
        (Get-TpmCabinetTrackball -State $after -Axis 'X').Device | Should -Be 'Test ball'
        (Get-TpmCabinetTrackball -State $after -Axis 'Y').Source | Should -Be 'PointerMovement'
        (Get-TpmCabinetTrackball -State $after -Axis 'X').DeviceName | Should -Be 'Example Trackball'
    }

    It 'saves nothing when the player says no' {
        $root = New-StateFolder
        Mock Read-TpmYesNo { param($Prompt) if ($Prompt -match 'Save this trackball') { 'N' } else { 'Y' } }
        Mock Get-TpmPointingDeviceNames { @() }
        Mock Read-TpmTrackballDevice { $null }
        Mock Invoke-TpmLearnTrackballAxes { [pscustomobject]@{ Learned = @('X'); Stopped = $false } }
        Invoke-TpmTrackballLearning -StateRoot $root
        Test-Path -LiteralPath (Get-TpmControlStatePath -StateRoot $root).Cabinet | Should -BeFalse
    }

    It 'still reads a cabinet file saved before trackballs existed' {
        $root = New-StateFolder
        [System.IO.File]::WriteAllText((Get-TpmControlStatePath -StateRoot $root).Cabinet, '{"Version":1,"Devices":{},"Players":2,"ButtonsPerPlayer":6,"Keys":{"Coin1":{"Key":"5","Source":"Saved"}}}', (New-Object System.Text.UTF8Encoding $false))
        $cabinet = Read-TpmCabinetState -StateRoot $root
        Get-TpmCabinetKey -State $cabinet -Control 'Coin1' | Should -Be '5'
        Get-TpmCabinetTrackball -State $cabinet -Axis 'X' | Should -BeNullOrEmpty
    }
}

Describe 'Games that use a trackball are split by what their own file says' {
    It 'lists a game as supported only when it names RawInput trackball support, and others for manual setup' {
        $ok = [xml]'<GameProfile><ConfigValues><FieldInformation><FieldName>Input API</FieldName><FieldValue>RawInput</FieldValue><FieldOptions><string>RawInput</string></FieldOptions></FieldInformation></ConfigValues><RawInputTrackball/><JoystickButtons><JoystickButtons><ButtonName>Trackball X</ButtonName><InputMapping>P1Trackball</InputMapping></JoystickButtons></JoystickButtons></GameProfile>'
        $manual = [xml]'<GameProfile><JoystickButtons><JoystickButtons><ButtonName>Ball</ButtonName><InputMapping>P1Trackball</InputMapping></JoystickButtons></JoystickButtons></GameProfile>'
        $none = [xml]'<GameProfile><JoystickButtons><JoystickButtons><ButtonName>Start</ButtonName><InputMapping>P1ButtonStart</InputMapping></JoystickButtons></JoystickButtons></GameProfile>'
        $lists = Get-TpmTrackballGameLists -Games @([pscustomobject]@{ Title = 'Ok Game'; Doc = $ok }, [pscustomobject]@{ Title = 'Manual Game'; Doc = $manual }, [pscustomobject]@{ Title = 'Plain Game'; Doc = $none })
        ($lists.Supported -join ',') | Should -Be 'Ok Game'
        ($lists.Manual -join ',') | Should -Be 'Manual Game'
    }
}

# Writing the learned trackball into game files (rc95u6). Fixtures use a neutral device; layouts A and B are the two real shapes.
Describe 'The trackball device is written into the game file' {
    BeforeAll {
        # The progress bar is not what these tests check, and its module is not loaded here.
        function Write-TpmCompactExtractionProgress { param([Parameter(ValueFromRemainingArguments)]$Ignored) }
        $script:Path = '\\?\HID#VID_1234&PID_5678#7&abc&0&0000#{378de44c-56ef-11d1-bc8c-00a0c91405dd}'
        $script:Name = 'Example Trackball'
        $script:Head = '<GameProfile><ConfigValues><FieldInformation><FieldName>Input API</FieldName><FieldValue>RawInput</FieldValue><FieldOptions><string>RawInput</string></FieldOptions></FieldInformation></ConfigValues><RawInputTrackball/><JoystickButtons>'
        $script:Start = '<JoystickButtons><ButtonName>Start</ButtonName><InputMapping>P1ButtonStart</InputMapping><HideWithDirectInput>true</HideWithDirectInput></JoystickButtons>'
        $script:LayoutA = '<JoystickButtons><ButtonName>TrackBall</ButtonName><InputMapping>P1Trackball</InputMapping><HideWithDirectInput>true</HideWithDirectInput><HideWithXInput>true</HideWithXInput></JoystickButtons>'
        $script:LayoutB = '<JoystickButtons><ButtonName>P1 Trackball X</ButtonName><InputMapping>Analog0</InputMapping><AnalogType>AnalogJoystick</AnalogType><HideWithRawInput>true</HideWithRawInput></JoystickButtons><JoystickButtons><ButtonName>P1 Trackball X Left</ButtonName><InputMapping>P1RelativeLeft</InputMapping></JoystickButtons><JoystickButtons><ButtonName>P1 Trackball</ButtonName><InputMapping>P1LightGun</InputMapping><AnalogType>None</AnalogType><HideWithRawInput>false</HideWithRawInput></JoystickButtons>'
        function script:New-Profile { param([string]$Buttons) $d = New-StateFolder; $p = Join-Path $d 'game.xml'; [System.IO.File]::WriteAllText($p, ($script:Head + $script:Start + $Buttons + '</JoystickButtons></GameProfile>'), (New-Object System.Text.UTF8Encoding $false)); return [pscustomobject]@{ Dir = $d; Path = $p } }
        function script:Get-Nodes { param([string]$Path) return @(([xml](Get-Content -LiteralPath $Path -Raw)).GameProfile.JoystickButtons.JoystickButtons) }
        function script:Bind { param($f, [bool]$Replace = $false) Set-TpmTrackballBinding -UserProfilesDir $f.Dir -ProfilePath $f.Path -DevicePath $script:Path -DeviceName $script:Name -Replace $Replace }
    }
    BeforeEach { Mock Write-Log { }; Mock Write-Host { }; Mock Write-TpmText { } }

    It 'fills in layout A (single TrackBall), makes a verified backup, and changes nothing else' {
        $f = New-Profile $script:LayoutA
        $before = Get-Nodes $f.Path
        $r = Bind $f
        $r.Status | Should -Be 'Changed'
        $r.Backup.Verified | Should -BeTrue
        @(Get-ChildItem -LiteralPath (Join-Path $f.Dir 'FullBackup') -Directory).Count | Should -BeGreaterThan 0
        $after = Get-Nodes $f.Path
        $node = $after[1]
        $node.RawInputButton.DevicePath | Should -Be $script:Path
        $node.RawInputButton.DeviceType | Should -Be 'Mouse'
        $node.RawInputButton.MouseButton | Should -Be 'None'
        $node.RawInputButton.KeyboardKey | Should -Be 'None'
        $node.BindNameRi | Should -Be $script:Name
        $node.BindName | Should -Be $script:Name
        $node.HideWithXInput | Should -Be 'true'
        $after[0].OuterXml | Should -Be $before[0].OuterXml
    }

    It 'fills in only the P1 Trackball node of layout B and leaves the X, Y and relative nodes alone' {
        $f = New-Profile $script:LayoutB
        $before = Get-Nodes $f.Path
        (Bind $f).Status | Should -Be 'Changed'
        $after = Get-Nodes $f.Path
        $after[3].RawInputButton.DevicePath | Should -Be $script:Path
        $after[3].BindName | Should -Be $script:Name
        foreach ($i in 0, 1, 2) { $after[$i].OuterXml | Should -Be $before[$i].OuterXml }
    }

    It 'keeps a trackball that is already set unless the player says replace' {
        $f = New-Profile $script:LayoutA
        (Bind $f).Status | Should -Be 'Changed'
        $other = Set-TpmTrackballBinding -UserProfilesDir $f.Dir -ProfilePath $f.Path -DevicePath '\\?\HID#VID_9999&PID_0001#1&2&0&0000#{378de44c-56ef-11d1-bc8c-00a0c91405dd}' -DeviceName 'Other Ball'
        $other.Status | Should -Be 'Kept'
        (Get-Nodes $f.Path)[1].RawInputButton.DevicePath | Should -Be $script:Path
        (Bind $f).Status | Should -Be 'NoChange'
        $replaced = Set-TpmTrackballBinding -UserProfilesDir $f.Dir -ProfilePath $f.Path -DevicePath '\\?\HID#VID_9999&PID_0001#1&2&0&0000#{378de44c-56ef-11d1-bc8c-00a0c91405dd}' -DeviceName 'Other Ball' -Replace $true
        $replaced.Status | Should -Be 'Changed'
        (Get-Nodes $f.Path)[1].BindName | Should -Be 'Other Ball'
    }

    It 'puts the old file back when the saved file does not read back' {
        $f = New-Profile $script:LayoutA
        $bytes = [System.IO.File]::ReadAllBytes($f.Path)
        Mock Save-XmlMaybe { param($doc, $path, $dry) [System.IO.File]::WriteAllText($path, '<GameProfile/>') }
        $r = Bind $f
        $r.Status | Should -Be 'Failed'
        [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($f.Path)) | Should -Be ([System.Convert]::ToBase64String($bytes))
    }

    It 'leaves a profile with an unfamiliar trackball shape alone and lists it for hand setup' {
        $f = New-Profile '<JoystickButtons><ButtonName>Trackball X</ButtonName><InputMapping>Analog0</InputMapping></JoystickButtons>'
        $bytes = [System.IO.File]::ReadAllBytes($f.Path)
        (Bind $f).Status | Should -Be 'NoShape'
        [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($f.Path)) | Should -Be ([System.Convert]::ToBase64String($bytes))
        Test-Path -LiteralPath (Join-Path $f.Dir 'FullBackup') | Should -BeFalse
        $lists = Get-TpmTrackballGameLists -Games @([pscustomobject]@{ Code = 'game'; Title = 'Odd Game'; Doc = [xml](Get-Content -LiteralPath $f.Path -Raw) })
        ($lists.Manual -join ',') | Should -Be 'Odd Game'
        $lists.Writable.Count | Should -Be 0
    }

    It 'writes nothing when no device path was read' {
        $f = New-Profile $script:LayoutA
        $bytes = [System.IO.File]::ReadAllBytes($f.Path)
        Mock Get-TpmControlsAllGames { [pscustomobject]@{ Games = @([pscustomobject]@{ Code = 'game'; Title = 'Ball Game'; Doc = [xml](Get-Content -LiteralPath $f.Path -Raw) }) } }
        Mock Set-TpmTrackballBinding { }
        Mock Read-TpmYesNo { 'Y' }
        Invoke-TpmTrackballGameStep -UserProfilesDir $f.Dir -Device $null
        Should -Invoke Set-TpmTrackballBinding -Times 0 -Exactly
        [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($f.Path)) | Should -Be ([System.Convert]::ToBase64String($bytes))
    }

    It 'previews, then writes only after Y, and offers undo' {
        $f = New-Profile $script:LayoutA
        Mock Get-TpmControlsAllGames { [pscustomobject]@{ Games = @([pscustomobject]@{ Code = 'game'; Title = 'Ball Game'; Doc = [xml](Get-Content -LiteralPath $f.Path -Raw) }) } }
        Mock Invoke-TpmBaselineUndoPrompt { $false }
        Mock Read-TpmYesNo { 'N' }
        Invoke-TpmTrackballGameStep -UserProfilesDir $f.Dir -Device ([pscustomobject]@{ Path = $script:Path; Name = $script:Name })
        (Get-Nodes $f.Path)[1].SelectSingleNode('RawInputButton') | Should -BeNullOrEmpty
        Mock Read-TpmYesNo { 'Y' }
        Invoke-TpmTrackballGameStep -UserProfilesDir $f.Dir -Device ([pscustomobject]@{ Path = $script:Path; Name = $script:Name })
        (Get-Nodes $f.Path)[1].RawInputButton.DevicePath | Should -Be $script:Path
        Should -Invoke Invoke-TpmBaselineUndoPrompt -Times 1 -Exactly
        Should -Invoke Write-TpmText -ParameterFilter { $Text -match 'will get your trackball \(Example Trackball\)' }
    }
}

Describe 'Finding the trackball in the Raw Input device list' {
    It 'lists only HID mice, names them from Windows, and drops made-up mice' {
        $paths = { @('\\?\HID#VID_1234&PID_5678#7&abc&0&0000#{378de44c-56ef-11d1-bc8c-00a0c91405dd}', '\\?\Root#RDP_MOU#0000#{378de44c-56ef-11d1-bc8c-00a0c91405dd}', '\\?\HID#VID_AAAA&PID_BBBB&MI_00#8&1&0&0000#{378de44c-56ef-11d1-bc8c-00a0c91405dd}') }
        $names = { @([pscustomobject]@{ Id = 'HID\VID_1234&PID_5678\7&ABC&0&0000'; Name = 'Example Trackball' }) }
        $found = @(Get-TpmRawMouseDevices -ReadPaths $paths -ReadNames $names)
        $found.Count | Should -Be 2
        $found[0].Name | Should -Be 'Example Trackball'
        $found[0].Path | Should -Be '\\?\HID#VID_1234&PID_5678#7&abc&0&0000#{378de44c-56ef-11d1-bc8c-00a0c91405dd}'
        $found[1].Name | Should -Be 'Mouse (VID_AAAA&PID_BBBB)'
    }
    It 'returns no device when Windows would not give the list, and the player picks none' {
        @(Get-TpmRawMouseDevices -ReadPaths { $null } -ReadNames { @() }).Count | Should -Be 0
        Read-TpmTrackballDevice -GetDevices { @() } | Should -BeNullOrEmpty
    }
}
