#Requires -Module Pester

# Saved controller answers, learned arcade keys, play-test evidence and control guides (issues #201, #307, #267).
# What a user sees or loses: a question already answered is not asked again, a damaged or older saved file is never lost,
# a game is only Verified after the player says it worked and stops being Verified when its controls change, a game that needs
# calibration is not Verified until it is done, and a printed guide shows the player's own keys. No game file is ever written.
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.
# Everything uses temp folders and fake key presses.
# What this CANNOT prove: that a real encoder's buttons are seen by the console (Ctrl, Alt and Shift included), that a real
# controller works in a game, or that the page opens in a real browser. Those are in docs/RC9-OWNER-TEST-PLAN.md (Part 3).

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Controller learning tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:FunctionFile = Join-Path $TestDrive 'tpm-learning-functions.ps1'
    [System.IO.File]::WriteAllText($script:FunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:FunctionFile
    function Write-TpmCompactExtractionProgress { param([Parameter(ValueFromRemainingArguments)]$Ignored) }

    # A small profile. -Wheel adds a steering axis, so the game is a driving game that needs calibration.
    function script:New-LearnProfile {
        param([string]$Dir, [string]$Name, [string]$Revision = '5', [string]$StartKey = 'D1', [switch]$Wheel, [string]$Title = 'Test Game')
        $wheelXml = $(if ($Wheel) { '<JoystickButtons><ButtonName>Steering</ButtonName><InputMapping>Analog0</InputMapping><AnalogType>Wheel</AnalogType></JoystickButtons>' } else { '' })
        $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<GameProfile>
  <GameProfileRevision>$Revision</GameProfileRevision>
  <Description>$Title</Description>
  <ConfigValues>
    <FieldInformation><CategoryName>General</CategoryName><FieldName>Input API</FieldName><FieldValue>RawInput</FieldValue><FieldOptions><string>RawInput</string><string>XInput</string></FieldOptions></FieldInformation>
  </ConfigValues>
  <JoystickButtons>
    <JoystickButtons><ButtonName>Coin</ButtonName><InputMapping>Coin1</InputMapping><AnalogType>None</AnalogType></JoystickButtons>
    <JoystickButtons><ButtonName>Start</ButtonName><RawInputButton><DevicePath>kbd</DevicePath><DeviceType>Keyboard</DeviceType><KeyboardKey>$StartKey</KeyboardKey></RawInputButton><InputMapping>P1ButtonStart</InputMapping><AnalogType>None</AnalogType></JoystickButtons>
    <JoystickButtons><ButtonName>Punch</ButtonName><InputMapping>P1Button1</InputMapping><AnalogType>None</AnalogType></JoystickButtons>
    $wheelXml
  </JoystickButtons>
</GameProfile>
"@
        $path = Join-Path $Dir ($Name + '.xml')
        [System.IO.File]::WriteAllText($path, $xml, (New-Object System.Text.UTF8Encoding $false))
        return $path
    }
    function script:New-Folder { $d = Join-Path $TestDrive ('d-' + [guid]::NewGuid().ToString('N').Substring(0, 8)); [void][System.IO.Directory]::CreateDirectory($d); return $d }
}

Describe 'Saved device answers in the Device Survey' {
    BeforeEach {
        $script:State = New-Folder
        $script:asked = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { }
        Mock Write-Log { }
        Mock Read-TpmChoice { '1' }
        Mock Get-TpmControllerEvidence { [pscustomobject]@{ EvidenceStatus = 'Observed'; DeviceObservations = @() } }
    }

    It 'saves the answers, then asks one question to keep them instead of all seven' {
        Mock Read-TpmYesNo { [void]$script:asked.Add($Prompt); if ($Prompt -match 'Wheel|Lightgun') { 'Y' } else { 'N' } }
        Invoke-DeviceSurvey -StateRoot $script:State
        $script:asked.Count | Should -Be 7
        $script:asked.Clear()
        Mock Read-TpmYesNo { [void]$script:asked.Add($Prompt); 'Y' }
        Invoke-DeviceSurvey -StateRoot $script:State
        $script:asked.Count | Should -Be 1
        $script:asked[0] | Should -Match 'Keep these answers'
        $saved = Read-TpmCabinetState -StateRoot $script:State
        (Get-TpmCabinetDeviceAnswer -State $saved -Class 'Wheel') | Should -BeTrue
        (Get-TpmCabinetDeviceAnswer -State $saved -Class 'Keyboard') | Should -BeFalse
    }

    It 'lets the player answer again, with the saved answer as the default' {
        Mock Read-TpmYesNo { 'Y' }
        Invoke-DeviceSurvey -StateRoot $script:State
        $defaults = New-Object System.Collections.Generic.List[string]
        Mock Read-TpmYesNo { [void]$script:asked.Add($Prompt); [void]$defaults.Add($Default); if ($Prompt -match 'Keep these') { 'N' } else { 'N' } }
        Invoke-DeviceSurvey -StateRoot $script:State
        $script:asked.Count | Should -Be 8
        @($defaults | Select-Object -Skip 1) | ForEach-Object { $_ | Should -Be 'Y' }
        (Get-TpmCabinetDeviceAnswer -State (Read-TpmCabinetState -StateRoot $script:State) -Class 'Wheel') | Should -BeFalse
    }

    It 'asks again when a controller shows up that the player said they do not have' {
        Mock Read-TpmYesNo { 'N' }
        Invoke-DeviceSurvey -StateRoot $script:State
        Mock Get-TpmControllerEvidence { [pscustomobject]@{ EvidenceStatus = 'Observed'; DeviceObservations = @([pscustomobject]@{ DeviceClass = 'XboxStylePad'; Confidence = 'High'; Basis = 'XInputSlotActive'; Count = 1 }) } }
        Mock Read-TpmYesNo { [void]$script:asked.Add($Prompt); 'N' }
        Invoke-DeviceSurvey -StateRoot $script:State
        @($script:asked | Where-Object { $_ -match 'Keep these answers' }).Count | Should -Be 0
        @($script:asked | Where-Object { $_ -match 'Use this controller' }).Count | Should -Be 1
    }

    It 'finishes and writes the reason to the log when the answers cannot be saved' {
        Mock Read-TpmYesNo { 'Y' }
        Mock Save-TpmCabinetState { throw 'disk full' }
        { Invoke-DeviceSurvey -StateRoot $script:State } | Should -Not -Throw
        Should -Invoke Write-Log -ParameterFilter { $msg -match 'answers could not be saved' }
    }
}

Describe 'The controls files are never lost' {
    BeforeEach {
        $script:State = New-Folder
        Mock Write-Log { }
    }

    It 'keeps the unreadable file next to the new one and keeps the previous good file as a .bak copy' {
        $path = (Get-TpmControlStatePath -StateRoot $script:State).Cabinet
        [System.IO.File]::WriteAllText($path, '{ this is not json', (New-Object System.Text.UTF8Encoding $false))
        $state = Read-TpmCabinetState -StateRoot $script:State
        $state.FileStatus | Should -Be 'Unreadable'
        Set-TpmCabinetDevice -State $state -Class 'Wheel' -Has $true
        Save-TpmCabinetState -State $state -StateRoot $script:State
        @(Get-ChildItem -LiteralPath $script:State -Filter 'cabinet.json.unreadable-*').Count | Should -Be 1
        (Get-Content -LiteralPath @(Get-ChildItem -LiteralPath $script:State -Filter 'cabinet.json.unreadable-*')[0].FullName -Raw) | Should -Match 'this is not json'
        $again = Read-TpmCabinetState -StateRoot $script:State
        Set-TpmCabinetDevice -State $again -Class 'LightGun' -Has $true
        Save-TpmCabinetState -State $again -StateRoot $script:State
        (Get-Content -LiteralPath ($path + '.bak') -Raw) | Should -Match 'Wheel'
        (Get-Content -LiteralPath ($path + '.bak') -Raw) | Should -Not -Match 'LightGun'
        $final = Read-TpmCabinetState -StateRoot $script:State
        (Get-TpmCabinetDeviceAnswer -State $final -Class 'Wheel') | Should -BeTrue
        (Get-TpmCabinetDeviceAnswer -State $final -Class 'LightGun') | Should -BeTrue
    }

    It 'reading a missing or damaged file writes nothing' {
        $path = (Get-TpmControlStatePath -StateRoot $script:State).Evidence
        [System.IO.File]::WriteAllText($path, 'not json', (New-Object System.Text.UTF8Encoding $false))
        $before = @(Get-ChildItem -LiteralPath $script:State -Force).Count
        $profiles = New-Folder
        $doc = Read-Xml (New-LearnProfile -Dir $profiles -Name 'g1')
        (Get-TpmControlVerificationState -Code 'g1' -Doc $doc -StateRoot $script:State).Status | Should -Be 'Unreadable'
        @(Get-ChildItem -LiteralPath $script:State -Force).Count | Should -Be $before
    }
}

Describe 'Learning arcade buttons by pressing them' {
    BeforeEach { Mock Write-Host { }; Mock Write-Log { } }

    It 'records each key, skips on Esc, and refuses a key another control already has' {
        $controls = @(Get-TpmCabinetControlList -Players 1 -Buttons 2 | Where-Object { $_.Control -in @('Coin1', 'P1ButtonStart', 'P1Button1', 'P1Button2') })
        $presses = New-Object System.Collections.Generic.Queue[string]
        foreach ($k in @('5', '1', '1', 'Left Ctrl', 'Escape')) { $presses.Enqueue($k) }
        $result = Invoke-TpmLearnKeys -Controls $controls -ReadKey { $presses.Dequeue() }
        $result.Keys['Coin1'] | Should -Be '5'
        $result.Keys['P1ButtonStart'] | Should -Be '1'
        $result.Keys['P1Button1'] | Should -Be 'Left Ctrl'
        $result.Keys.Contains('P1Button2') | Should -BeFalse
        $result.Skipped | Should -Contain 'Player 1 button 2'
    }

    It 'asks before stopping when nothing is pressed, and keeps what was learned so far' {
        $controls = @(Get-TpmCabinetControlList -Players 1 -Buttons 1 | Select-Object -First 3)
        $presses = New-Object System.Collections.Generic.Queue[string]
        foreach ($k in @('5', '')) { $presses.Enqueue($k) }
        Mock Read-TpmYesNo { 'Y' }
        $result = Invoke-TpmLearnKeys -Controls $controls -ReadKey { $presses.Dequeue() }
        $result.Stopped | Should -BeTrue
        @($result.Keys.Keys) | Should -Be @('Coin1')
    }

    It 'proposes keys from LEDBlinky only for labels it recognizes and key codes it understands' {
        $map = [pscustomobject]@{ Found = $true; Controls = @(
            [pscustomobject]@{ Control = 'P1B1'; InputCodes = @('KEYCODE_LCONTROL') }
            [pscustomobject]@{ Control = 'P1START'; InputCodes = @('JOYCODE_1_BUTTON9', 'KEYCODE_1') }
            [pscustomobject]@{ Control = 'P1B2'; InputCodes = @('KEYCODE_SOMETHINGODD') }
            [pscustomobject]@{ Control = 'LOGO'; InputCodes = @('KEYCODE_L') }) }
        $proposed = Get-TpmKeysFromLedBlinkyMap -KeyMap $map -Controls @(Get-TpmCabinetControlList -Players 1 -Buttons 2)
        $proposed['P1Button1'] | Should -Be 'Left Ctrl'
        $proposed['P1ButtonStart'] | Should -Be '1'
        $proposed.Contains('P1Button2') | Should -BeFalse
        $proposed.Count | Should -Be 2
    }
}

Describe 'Play-test evidence and readiness' {
    BeforeEach {
        $script:State = New-Folder
        $script:Up = New-Folder
        $script:Gp = New-Folder
        Mock Write-Log { }
    }

    It 'is not Verified until the player says it worked, then is Verified with the evidence attached' {
        $path = New-LearnProfile -Dir $script:Up -Name 'g1'
        (Get-ControlReadinessAssessment -Code 'g1' -UserProfilesDir $script:Up -StateRoot $script:State).Controls | Should -Not -Be 'Verified'
        Save-TpmGameVerification -Code 'g1' -Title 'Test Game' -Doc (Read-Xml $path) -StateRoot $script:State
        $row = Get-ControlReadinessAssessment -Code 'g1' -UserProfilesDir $script:Up -StateRoot $script:State
        $row.Controls | Should -Be 'Verified'
        $row.Launch | Should -Be 'ObservedSuccess'
        Test-ControlReadinessVerificationEvidence -Assessment $row | Should -BeTrue
        $row.VerificationEvidence.Method | Should -Be 'PlayerReportedPlayTest'
        $row.VerificationEvidence.Game | Should -Be 'Test Game'
        $row.VerificationEvidence.ProfileRevision | Should -Be '5'
        [string]$row.VerificationEvidence.ObservedAt | Should -Not -BeNullOrEmpty
    }

    It 'stops being Verified when the game''s controls change, and when the game settings are updated' {
        $path = New-LearnProfile -Dir $script:Up -Name 'g1'
        Save-TpmGameVerification -Code 'g1' -Title 'Test Game' -Doc (Read-Xml $path) -StateRoot $script:State
        [void](New-LearnProfile -Dir $script:Up -Name 'g1' -StartKey 'D2')
        $row = Get-ControlReadinessAssessment -Code 'g1' -UserProfilesDir $script:Up -StateRoot $script:State
        $row.Controls | Should -Not -Be 'Verified'
        $row.Launch | Should -Be 'NotTestedByTpm'
        (Get-TpmControlVerificationState -Code 'g1' -Doc (Read-Xml (Join-Path $script:Up 'g1.xml')) -StateRoot $script:State).Status | Should -Be 'Stale'
        [void](New-LearnProfile -Dir $script:Up -Name 'g1' -Revision '6')
        (Get-TpmControlVerificationState -Code 'g1' -Doc (Read-Xml (Join-Path $script:Up 'g1.xml')) -StateRoot $script:State).Reason | Should -Match 'updated'
        [void](New-LearnProfile -Dir $script:Up -Name 'g1')
        (Get-TpmControlVerificationState -Code 'g1' -Doc (Read-Xml (Join-Path $script:Up 'g1.xml')) -StateRoot $script:State).Status | Should -Be 'Current'
    }

    It 'forgets the verification when the player says it does not work' {
        $path = New-LearnProfile -Dir $script:Up -Name 'g1'
        Save-TpmGameVerification -Code 'g1' -Title 'Test Game' -Doc (Read-Xml $path) -StateRoot $script:State
        Remove-TpmGameVerification -Code 'g1' -StateRoot $script:State
        (Get-ControlReadinessAssessment -Code 'g1' -UserProfilesDir $script:Up -StateRoot $script:State).Controls | Should -Not -Be 'Verified'
    }

    It 'keeps a wheel game not Verified until the calibration is done, and asks again when its controls change' {
        $path = New-LearnProfile -Dir $script:Up -Name 'race' -Wheel
        Save-TpmGameVerification -Code 'race' -Title 'Racer' -Doc (Read-Xml $path) -StateRoot $script:State
        $row = Get-ControlReadinessAssessment -Code 'race' -UserProfilesDir $script:Up -StateRoot $script:State
        $row.Controls | Should -Not -Be 'Verified'
        $row.SetupOutstanding | Should -Contain 'Calibration'
        Set-TpmGameSetupStep -Code 'race' -Step Calibration -State Done -Doc (Read-Xml $path) -StateRoot $script:State
        (Get-ControlReadinessAssessment -Code 'race' -UserProfilesDir $script:Up -StateRoot $script:State).Controls | Should -Be 'Verified'
        [void](New-LearnProfile -Dir $script:Up -Name 'race' -Wheel -StartKey 'D3')
        (Get-TpmControlVerificationState -Code 'race' -Doc (Read-Xml (Join-Path $script:Up 'race.xml')) -StateRoot $script:State).Calibration | Should -Be 'Needed'
    }

    It 'lets the player say a game needs no calibration, and blocks Verified while a first-run step is marked still to do' {
        $path = New-LearnProfile -Dir $script:Up -Name 'race' -Wheel
        Save-TpmGameVerification -Code 'race' -Title 'Racer' -Doc (Read-Xml $path) -StateRoot $script:State
        Set-TpmGameSetupStep -Code 'race' -Step Calibration -State NotNeeded -Doc (Read-Xml $path) -StateRoot $script:State
        (Get-ControlReadinessAssessment -Code 'race' -UserProfilesDir $script:Up -StateRoot $script:State).Controls | Should -Be 'Verified'
        Set-TpmGameSetupStep -Code 'race' -Step FirstRun -State Needed -Doc (Read-Xml $path) -StateRoot $script:State
        $row = Get-ControlReadinessAssessment -Code 'race' -UserProfilesDir $script:Up -StateRoot $script:State
        $row.Controls | Should -Not -Be 'Verified'
        $row.SetupOutstanding | Should -Contain 'FirstRun'
        $lines = Get-OnboardingHandoffSummaryLines -Assessment $row -WizardState ([pscustomobject]@{ State = 'Complete'; DatXmlLocation = $null })
        ($lines -join "`n") | Should -Match 'first-run Test or Service menu step'
    }

    It 'never changes a game profile' {
        $path = New-LearnProfile -Dir $script:Up -Name 'g1'
        $before = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        Save-TpmGameVerification -Code 'g1' -Title 'Test Game' -Doc (Read-Xml $path) -StateRoot $script:State
        Set-TpmGameSetupStep -Code 'g1' -Step Calibration -State Done -Doc (Read-Xml $path) -StateRoot $script:State
        [void](Get-ControlReadinessAssessment -Code 'g1' -UserProfilesDir $script:Up -StateRoot $script:State)
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash | Should -Be $before
    }
}

Describe 'Control guides' {
    BeforeEach {
        $script:State = New-Folder
        $script:Up = New-Folder
        Mock Write-Log { }
        Mock Write-Host { }
    }

    It 'shows the player''s own key, says when a key is not learned, and says what the game has set up' {
        $doc = Read-Xml (New-LearnProfile -Dir $script:Up -Name 'g1')
        $cabinet = Read-TpmCabinetState -StateRoot $script:State
        Set-TpmCabinetKeys -State $cabinet -Keys @{ P1ButtonStart = @{ Key = 'Left Ctrl'; Source = 'PressedByPlayer' } }
        $guide = Get-TpmGameControlGuide -Doc $doc -Title 'Test Game' -Cabinet $cabinet -Verification (Get-TpmControlVerificationState -Code 'g1' -Doc $doc -StateRoot $script:State)
        $start = @($guide.Rows | Where-Object { $_.Cells[3] -eq 'P1ButtonStart' })[0]
        $start.Cells[0] | Should -Be 'Start'
        $start.Cells[1] | Should -Be 'Key: Left Ctrl'
        $start.Cells[2] | Should -Be 'Set up'
        $punch = @($guide.Rows | Where-Object { $_.Cells[3] -eq 'P1Button1' })[0]
        $punch.Cells[1] | Should -Be 'Not learned yet'
        $punch.Cells[2] | Should -Be 'Not set up yet'
        ($guide.Lines -join ' ') | Should -Match 'no record that you played'
    }

    It 'writes a printable page that cannot carry markup from a game name, in the guide folder only' {
        $guide = [pscustomobject]@{ Title = 'Controls for <script>x</script>'; Lines = @('A & B'); Columns = @('Control'); Rows = @([pscustomobject]@{ Cells = @('<b>') }) }
        $root = New-Folder
        $page = Save-TpmControlGuideFile -Guide $guide -FileName 'g1-controls.html' -GuideRoot $root
        (Split-Path -Parent $page) | Should -Be $root
        $html = Get-Content -LiteralPath $page -Raw
        $html | Should -Not -Match '<script>'
        $html | Should -Match '&lt;script&gt;'
        $html | Should -Match 'A &amp; B'
    }
}

Describe 'Stuck and doubled buttons while learning' {
    BeforeEach {
        Mock Write-Host { }
        Mock Write-Log { }
        $script:said = New-Object System.Collections.Generic.List[string]
        Mock Write-TpmText { [void]$script:said.Add($Text) }
    }

    It 'keeps the first key but says when a press also sent another key, and when one stays down' {
        $controls = @(Get-TpmCabinetControlList -Players 1 -Buttons 2 | Where-Object { $_.Control -in @('P1ButtonStart', 'P1Button1') })
        $presses = New-Object System.Collections.Generic.Queue[object]
        $presses.Enqueue([pscustomobject]@{ Key = '1'; Also = @('Left Ctrl'); Held = $false })
        $presses.Enqueue([pscustomobject]@{ Key = 'Space'; Also = @(); Held = $true })
        $result = Invoke-TpmLearnKeys -Controls $controls -ReadKey { $presses.Dequeue() }
        $result.Keys['P1ButtonStart'] | Should -Be '1'
        $result.Keys['P1Button1'] | Should -Be 'Space'
        ($script:said -join "`n") | Should -Match 'also sent Left Ctrl'
        ($script:said -join "`n") | Should -Match 'still down after 3 seconds'
        $result.Held | Should -Be @('Player 1 button 1')
    }

    It 'warns about a shared key only when it comes with two different controls' {
        $controls = @(Get-TpmCabinetControlList -Players 1 -Buttons 2 | Where-Object { $_.Control -in @('P1ButtonStart', 'P1Button1', 'P1Button2') })
        $one = New-Object System.Collections.Generic.Queue[object]
        $one.Enqueue([pscustomobject]@{ Key = '1'; Also = @('Left Ctrl'); Held = $false })
        $one.Enqueue('Space'); $one.Enqueue('Z')
        [void](Invoke-TpmLearnKeys -Controls $controls -ReadKey { $one.Dequeue() })
        ($script:said -join "`n") | Should -Not -Match 'came along with'
        $script:said.Clear()
        $two = New-Object System.Collections.Generic.Queue[object]
        $two.Enqueue([pscustomobject]@{ Key = '1'; Also = @('Left Ctrl'); Held = $false })
        $two.Enqueue([pscustomobject]@{ Key = 'Space'; Also = @('Left Ctrl'); Held = $false })
        $two.Enqueue('Z')
        [void](Invoke-TpmLearnKeys -Controls $controls -ReadKey { $two.Dequeue() })
        ($script:said -join "`n") | Should -Match 'Left Ctrl came along with 2 different controls'
    }
}

Describe 'Standard arcade keys' {
    BeforeEach { Mock Write-Host { }; Mock Write-TpmText { } }

    It 'lists only controls TPM learns, with no key given to two controls' {
        $standard = Get-TpmStandardArcadeKeys
        $ids = @(Get-TpmCabinetControlList -Players 4 -Buttons 8 | ForEach-Object { $_.Control })
        foreach ($id in @($standard.Keys)) { $ids | Should -Contain $id }
        @($standard.Values | Select-Object -Unique).Count | Should -Be $standard.Count
        $standard['P1Button1'] | Should -Be 'Left Ctrl'
        $standard.Contains('P2Button5') | Should -BeFalse
        $standard.Contains('Test') | Should -BeFalse
    }

    It 'is used only when the buttons the player presses send the standard keys' {
        $controls = @(Get-TpmCabinetControlList -Players 1 -Buttons 2)
        $proposed = Get-TpmStandardArcadeKeys
        $good = New-Object System.Collections.Generic.Queue[string]; $good.Enqueue('1'); $good.Enqueue('Left Ctrl')
        (Test-TpmStandardKeysSpotCheck -Proposed $proposed -Controls $controls -ReadKey { $good.Dequeue() }).Passed | Should -BeTrue
        $bad = New-Object System.Collections.Generic.Queue[string]; $bad.Enqueue('1'); $bad.Enqueue('Z')
        $check = Test-TpmStandardKeysSpotCheck -Proposed $proposed -Controls $controls -ReadKey { $bad.Dequeue() }
        $check.Passed | Should -BeFalse
        $check.Got | Should -Be 'Z'
        (Test-TpmStandardKeysSpotCheck -Proposed $proposed -Controls $controls -ReadKey { '' }).Reason | Should -Be 'NothingPressed'
    }
}

Describe 'A different encoder than when the buttons were learned' {
    It 'hints only when TPM could see the encoders both times and the count differs' {
        $cabinet = [pscustomobject]@{ EncodersWhenLearned = 1; Keys = [pscustomobject]@{ Coin1 = 'x' } }
        (Get-TpmEncoderChangeNotice -Cabinet $cabinet -EncodersNow 0) | Should -Match 'learn your buttons again'
        (Get-TpmEncoderChangeNotice -Cabinet $cabinet -EncodersNow 1) | Should -Be ''
        (Get-TpmEncoderChangeNotice -Cabinet $cabinet -EncodersNow -1) | Should -Be ''
        $cabinet.EncodersWhenLearned = -1
        (Get-TpmEncoderChangeNotice -Cabinet $cabinet -EncodersNow 2) | Should -Be ''
    }

    It 'counts only encoders seen with Medium or High confidence, and says unknown when detection could not look' {
        $seen = [pscustomobject]@{ EvidenceStatus = 'Observed'; DeviceObservations = @(
            [pscustomobject]@{ DeviceClass = 'ArcadeEncoder'; Confidence = 'Medium'; Count = 1 }
            [pscustomobject]@{ DeviceClass = 'ArcadeEncoder'; Confidence = 'Low'; Count = 3 }) }
        (Get-TpmEncoderCount -Evidence $seen) | Should -Be 1
        (Get-TpmEncoderCount -Evidence ([pscustomobject]@{ EvidenceStatus = 'SourceUnavailable'; DeviceObservations = @() })) | Should -Be -1
    }

    It 'loads a saved cabinet file from before this field existed as "unknown"' {
        $state = New-Folder
        [System.IO.File]::WriteAllText((Get-TpmControlStatePath -StateRoot $state).Cabinet, '{"Version":1,"Devices":{},"Players":2,"ButtonsPerPlayer":6,"Keys":{}}', (New-Object System.Text.UTF8Encoding $false))
        (Read-TpmCabinetState -StateRoot $state).EncodersWhenLearned | Should -Be -1
    }
}

Describe 'Recognizing the same controllers again' {
    BeforeAll {
        function script:New-Print { param([int]$n) ('a' * 63) + ('{0:x}' -f $n) }
        function script:New-Prints { param([int[]]$Ids) $list = @(); foreach ($n in $Ids) { $list += [pscustomobject]@{ DeviceClass = 'ArcadeEncoder'; Fingerprint = (New-Print $n) } }; return , $list }
        function script:New-SeenNow { param([int[]]$Ids = @(), [string]$Status = 'Observed', [switch]$NoSalt)
            $prints = $null; if (-not $NoSalt) { $prints = New-Prints $Ids }
            [pscustomobject]@{ EvidenceStatus = $Status; DeviceObservations = @(); DeviceFingerprints = $prints } }
        function script:New-KeptKeys { param([int[]]$Ids = @(), [switch]$Old, [int]$Count = -1)
            $prints = $null; if (-not $Old) { $prints = New-Prints $Ids }
            [pscustomobject]@{ Keys = [pscustomobject]@{ Coin1 = 'x' }; EncodersWhenLearned = $Count; EncoderFingerprints = $prints } }
    }

    It 'says the controllers are the same, including two identical encoders and one moved to another USB port' {
        (Get-TpmControllerSetNotice -Cabinet (New-KeptKeys -Ids 1) -Evidence (New-SeenNow -Ids 1)).State | Should -Be 'Same'
        $two = Get-TpmControllerSetNotice -Cabinet (New-KeptKeys -Ids 1, 2) -Evidence (New-SeenNow -Ids 2, 1)
        $two.State | Should -Be 'Same'
        $two.Text | Should -Match 'same arcade encoders'
    }

    It 'says when an encoder was added, removed or swapped, and when one of two identical encoders is gone' {
        (Get-TpmControllerSetNotice -Cabinet (New-KeptKeys -Ids 1) -Evidence (New-SeenNow -Ids 1, 2)).State | Should -Be 'Added'
        (Get-TpmControllerSetNotice -Cabinet (New-KeptKeys -Ids 1, 2) -Evidence (New-SeenNow -Ids 1)).State | Should -Be 'Removed'
        (Get-TpmControllerSetNotice -Cabinet (New-KeptKeys -Ids 1) -Evidence (New-SeenNow)).State | Should -Be 'Removed'
        (Get-TpmControllerSetNotice -Cabinet (New-KeptKeys) -Evidence (New-SeenNow -Ids 3)).State | Should -Be 'Added'
        $swapped = Get-TpmControllerSetNotice -Cabinet (New-KeptKeys -Ids 1) -Evidence (New-SeenNow -Ids 3)
        $swapped.State | Should -Be 'Changed'
        $swapped.Text | Should -Match 'learn your buttons again'
    }

    It 'says it could not check when Windows gives no data, no key exists, or no encoder is recognized, and never when no keys were taught' {
        (Get-TpmControllerSetNotice -Cabinet (New-KeptKeys -Ids 1) -Evidence (New-SeenNow -Status 'SourceUnavailable')).State | Should -Be 'CouldNotCheck'
        (Get-TpmControllerSetNotice -Cabinet (New-KeptKeys -Ids 1) -Evidence $null).State | Should -Be 'CouldNotCheck'
        (Get-TpmControllerSetNotice -Cabinet (New-KeptKeys -Ids 1) -Evidence (New-SeenNow -NoSalt)).State | Should -Be 'CouldNotCheck'
        (Get-TpmControllerSetNotice -Cabinet (New-KeptKeys) -Evidence (New-SeenNow)).State | Should -Be 'CouldNotCheck'
        $none = Get-TpmControllerSetNotice -Cabinet ([pscustomobject]@{ Keys = [pscustomobject]@{}; EncodersWhenLearned = -1; EncoderFingerprints = @((New-KeptKeys -Ids 1).EncoderFingerprints) }) -Evidence (New-SeenNow -Ids 2)
        $none.State | Should -Be 'NoKeys'
        $none.Text | Should -Be ''
    }

    It 'only gives a hint: the saved keys and answers are not changed' {
        $cabinet = New-KeptKeys -Ids 1
        $before = $cabinet | ConvertTo-Json -Depth 6
        [void](Get-TpmControllerSetNotice -Cabinet $cabinet -Evidence (New-SeenNow -Ids 5))
        ($cabinet | ConvertTo-Json -Depth 6) | Should -Be $before
    }

    It 'keeps the old count hint for keys saved before fingerprints existed' {
        (Get-TpmControllerSetNotice -Cabinet (New-KeptKeys -Old -Count 1) -Evidence ([pscustomobject]@{ EvidenceStatus = 'Observed'; DeviceObservations = @() })).State | Should -Be 'Changed'
        $same = [pscustomobject]@{ EvidenceStatus = 'Observed'; DeviceObservations = @([pscustomobject]@{ DeviceClass = 'ArcadeEncoder'; Confidence = 'Medium'; Count = 1 }) }
        (Get-TpmControllerSetNotice -Cabinet (New-KeptKeys -Old -Count 1) -Evidence $same).Text | Should -Be ''
    }

    It 'saves fingerprints with the cabinet and loads them back; a list with no encoder stays a list, an older file stays "not saved"' {
        $state = New-Folder
        $cabinet = Read-TpmCabinetState -StateRoot $state
        $cabinet.EncoderFingerprints = @([pscustomobject]@{ DeviceClass = 'ArcadeEncoder'; Fingerprint = (New-Print 1) })
        Save-TpmCabinetState -State $cabinet -StateRoot $state
        @((Read-TpmCabinetState -StateRoot $state).EncoderFingerprints).Fingerprint | Should -Be (New-Print 1)
        $cabinet.EncoderFingerprints = @()
        Save-TpmCabinetState -State $cabinet -StateRoot $state
        $empty = (Read-TpmCabinetState -StateRoot $state).EncoderFingerprints
        $null -eq $empty | Should -BeFalse
        @($empty).Count | Should -Be 0
        $old = New-Folder
        [System.IO.File]::WriteAllText((Get-TpmControlStatePath -StateRoot $old).Cabinet, '{"Version":1,"Devices":{},"Players":2,"ButtonsPerPlayer":6,"EncodersWhenLearned":1,"Keys":{}}', (New-Object System.Text.UTF8Encoding $false))
        $null -eq (Read-TpmCabinetState -StateRoot $old).EncoderFingerprints | Should -BeTrue
    }

    It 'saving learned buttons keeps a salt and fingerprints on this PC and writes no raw id to the saved file or the log' {
        $state = New-Folder
        $script:logged = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { }
        Mock Write-Log { [void]$script:logged.Add($msg) }
        Mock Test-TpmKeyPressAvailable { $true }
        Mock Read-TpmChoice { '1' }
        Mock Get-TpmKeysPressedOnTheirOwn { @() }
        Mock Get-TpmLedBlinkyKeyMap { [pscustomobject]@{ Found = $false; Controls = @() } }
        Mock Read-TpmYesNo { if ($Prompt -match 'Save this') { 'Y' } else { 'N' } }
        Mock Invoke-TpmLearnKeys { [pscustomobject]@{ Keys = @{ Coin1 = 'D5' }; Skipped = @() } }
        Mock Get-CimInstance { @([pscustomobject]@{ Name = 'USB Input Device'; DeviceID = 'HID\VID_D209&PID_0301&MI_00\7&AAA&0&0000' }, [pscustomobject]@{ Name = 'USB Input Device'; DeviceID = 'HID\VID_D209&PID_0301&MI_00\7&BBB&0&0000' }) }
        Invoke-TpmButtonLearning -StateRoot $state
        $saved = Read-TpmCabinetState -StateRoot $state
        @($saved.EncoderFingerprints).Count | Should -Be 2
        $saved.EncodersWhenLearned | Should -Be 2
        $salt = Get-TpmControllerSalt -StateRoot $state
        $salt | Should -Match '^[0-9a-f]{32}$'
        $text = [System.IO.File]::ReadAllText((Get-TpmControlStatePath -StateRoot $state).Cabinet)
        $text | Should -Not -Match '(?i)VID_|PID_|MI_0|7&|HID\\\\'
        $text | Should -Not -Match $salt
        ($script:logged -join "`n") | Should -Not -Match ('(?i)VID_|PID_|MI_0|7&|' + $salt + '|' + (@($saved.EncoderFingerprints)[0].Fingerprint))
        (Get-TpmControllerSetNotice -Cabinet $saved -Evidence (Get-TpmControllerEvidence -Salt $salt)).State | Should -Be 'Same'
    }
}

Describe 'Learning arcade buttons again only asks for the controls TPM has no key for' {
    BeforeEach {
        Mock Write-Host { }
        Mock Write-Log { }
        Mock Test-TpmKeyPressAvailable { $true }
        Mock Read-TpmChoice { '1' }
        Mock Get-TpmKeysPressedOnTheirOwn { @() }
        Mock Get-TpmLedBlinkyKeyMap { [pscustomobject]@{ Found = $false; Controls = @() } }
        Mock Get-TpmStandardArcadeKeys { [ordered]@{} }
        Mock Get-TpmControllerEvidence { [pscustomobject]@{ EvidenceStatus = 'Observed'; DeviceObservations = @() } }
        Mock Get-TpmEncoderCount { 0 }
        Mock Get-TpmEncoderFingerprints { @() }
    }

    It 'asks only for the missing control, keeps the saved keys, and asks for everything when the player says to press them all again' {
        # Mutation: start every run with an empty key list -> every control is asked again although the screen says it will not ask again.
        $state = New-Folder
        $controls = @(Get-TpmCabinetControlList -Players 1 -Buttons 1)
        $controls.Count | Should -BeGreaterThan 2
        $cabinet = Read-TpmCabinetState -StateRoot $state
        $savedKeys = @{}
        foreach ($control in @($controls | Select-Object -First ($controls.Count - 1))) { $savedKeys[[string]$control.Control] = @{ Key = ('K' + $savedKeys.Count); Source = 'PressedByPlayer' } }
        Set-TpmCabinetKeys -State $cabinet -Keys $savedKeys -Players 1 -ButtonsPerPlayer 1
        Save-TpmCabinetState -State $cabinet -StateRoot $state
        $missing = [string]$controls[$controls.Count - 1].Control
        $script:asked = New-Object System.Collections.Generic.List[string]
        Mock Read-TpmYesNo { if ($Prompt -match 'Save this|Keep those') { 'Y' } else { 'N' } }
        Mock Invoke-TpmLearnKeys { foreach ($c in @($Controls)) { [void]$script:asked.Add([string]$c.Control) }; $k = @{}; foreach ($c in @($Controls)) { $k[[string]$c.Control] = 'NEWKEY' }; [pscustomobject]@{ Keys = $k; Skipped = @() } }
        Invoke-TpmButtonLearning -StateRoot $state
        @($script:asked) | Should -Be @($missing)
        $after = Read-TpmCabinetState -StateRoot $state
        foreach ($id in $savedKeys.Keys) { (Get-TpmCabinetKey -State $after -Control $id) | Should -Be $savedKeys[$id].Key }
        (Get-TpmCabinetKey -State $after -Control $missing) | Should -Be 'NEWKEY'

        $script:asked.Clear()
        Mock Read-TpmYesNo { if ($Prompt -match 'Save this') { 'Y' } else { 'N' } }
        Invoke-TpmButtonLearning -StateRoot $state
        $script:asked.Count | Should -Be $controls.Count
    }
}

Describe 'Key suggestions and light colors in a game guide' {
    BeforeEach { Mock Write-Host { }; Mock Write-Log { } }

    It 'does not suggest a key for a "direction" the game calls something else, and says so' {
        $dir = New-Folder
        $xml = '<GameProfile><GameProfileRevision>1</GameProfileRevision><JoystickButtons>' +
            '<JoystickButtons><ButtonName>Player 1 Up</ButtonName><InputMapping>P1ButtonUp</InputMapping><AnalogType>None</AnalogType></JoystickButtons>' +
            '<JoystickButtons><ButtonName>Menu Down</ButtonName><InputMapping>P1ButtonDown</InputMapping><AnalogType>None</AnalogType></JoystickButtons>' +
            '</JoystickButtons></GameProfile>'
        [System.IO.File]::WriteAllText((Join-Path $dir 'g2.xml'), $xml, (New-Object System.Text.UTF8Encoding $false))
        $cabinet = Read-TpmCabinetState -StateRoot (New-Folder)
        Set-TpmCabinetKeys -State $cabinet -Keys @{ P1ButtonUp = @{ Key = 'Up arrow'; Source = 'PressedByPlayer' }; P1ButtonDown = @{ Key = 'Down arrow'; Source = 'PressedByPlayer' } }
        $guide = Get-TpmGameControlGuide -Doc (Read-Xml (Join-Path $dir 'g2.xml')) -Title 'G2' -Cabinet $cabinet
        @($guide.Rows | Where-Object { $_.Cells[3] -eq 'P1ButtonUp' })[0].Cells[1] | Should -Be 'Key: Up arrow'
        @($guide.Rows | Where-Object { $_.Cells[3] -eq 'P1ButtonDown' })[0].Cells[1] | Should -Match 'not sure'
        ($guide.Lines -join ' ') | Should -Match 'TPM can suggest a key for 1 of the 2 controls'
        ($guide.Lines -join ' ') | Should -Match 'not sure what to suggest for: Menu Down'
    }

    It 'shows the color from the player''s own LEDBlinky file, the game''s own group first, and nothing when there is no file' {
        $led = New-Folder
        $text = '<dat><emulator emuname="TeknoParrot">' +
            '<controlGroup groupName="DEFAULT"><player number="1"><control name="P1_BUTTON1" color="Red"/><control name="START1" color="Green"/></player></controlGroup>' +
            '<controlGroup groupName="g1"><player number="1"><control name="P1_BUTTON1" color="48,0,0"/></player></controlGroup>' +
            '</emulator></dat>'
        [System.IO.File]::WriteAllText((Join-Path $led 'LEDBlinkyControls.xml'), $text, (New-Object System.Text.UTF8Encoding $false))
        $colors = Get-TpmLedControlColors -Root $led -Code 'g1'
        $colors['P1_BUTTON1'] | Should -Be '48,0,0'
        $colors['START1'] | Should -Be 'Green'
        $doc = Read-Xml (New-LearnProfile -Dir (New-Folder) -Name 'g1')
        $cabinet = Read-TpmCabinetState -StateRoot (New-Folder)
        $guide = Get-TpmGameControlGuide -Doc $doc -Title 'Test Game' -Cabinet $cabinet -LedColors $colors
        $guide.Columns | Should -Contain 'Light'
        @($guide.Rows | Where-Object { $_.Cells[3] -eq 'P1ButtonStart' })[0].Cells[4] | Should -Be 'Green'
        @($guide.Rows | Where-Object { $_.Cells[3] -eq 'P1Button1' })[0].Cells[4] | Should -Be 'a custom color'
        (Get-TpmLedControlColors -Root (New-Folder) -Code 'g1').Count | Should -Be 0
        (Get-TpmGameControlGuide -Doc $doc -Title 'Test Game' -Cabinet $cabinet).Columns | Should -Not -Contain 'Light'
    }
}

Describe 'Does the cabinet fit the game, and shared controls (issue #267)' {
    BeforeEach { Mock Write-Host { }; Mock Write-Log { } }

    BeforeAll {
        function script:New-FitProfile {
            param([string]$Name, [string]$Buttons = '', [switch]$Wheel, [switch]$Gun)
            $dir = New-Folder
            $extra = $(if ($Wheel) { '<JoystickButtons><ButtonName>Steering</ButtonName><InputMapping>Analog0</InputMapping><AnalogType>Wheel</AnalogType></JoystickButtons>' } elseif ($Gun) { '<JoystickButtons><ButtonName>Gun X</ButtonName><InputMapping>Analog0</InputMapping><AnalogType>AnalogJoystick</AnalogType></JoystickButtons>' } else { '' })
            $xml = '<GameProfile><GameProfileRevision>1</GameProfileRevision><JoystickButtons>' + $Buttons + $extra + '</JoystickButtons></GameProfile>'
            [System.IO.File]::WriteAllText((Join-Path $dir ($Name + '.xml')), $xml, (New-Object System.Text.UTF8Encoding $false))
            return (Read-Xml (Join-Path $dir ($Name + '.xml')))
        }
        function script:New-FitButton { param([string]$Mapping, [string]$Label) return ('<JoystickButtons><ButtonName>{0}</ButtonName><InputMapping>{1}</InputMapping><AnalogType>None</AnalogType></JoystickButtons>' -f $Label, $Mapping) }
    }

    It 'says which players and buttons the game uses that the cabinet does not have, and keeps that out of "Not learned yet"' {
        $buttons = (New-FitButton 'P1Button1' 'Punch') + (New-FitButton 'P1Button3' 'Kick') + (New-FitButton 'P2Button1' 'Punch 2')
        $doc = New-FitProfile -Name 'fight' -Buttons $buttons
        $cabinet = Read-TpmCabinetState -StateRoot (New-Folder)
        Set-TpmCabinetKeys -State $cabinet -Keys @{ P1Button1 = @{ Key = 'Left Ctrl'; Source = 'PressedByPlayer' } } -Players 1 -ButtonsPerPlayer 2
        $guide = Get-TpmGameControlGuide -Doc $doc -Title 'Fight' -Cabinet $cabinet
        ($guide.FitLines -join ' ') | Should -Match 'controls for 2 players. Your cabinet has 1 player'
        ($guide.FitLines -join ' ') | Should -Match 'up to 3 buttons for each player. Your cabinet has 2 buttons'
        @($guide.Rows | Where-Object { $_.Cells[3] -eq 'P1Button3' })[0].Cells[1] | Should -Be 'Your cabinet has no button 3'
        @($guide.Rows | Where-Object { $_.Cells[3] -eq 'P2Button1' })[0].Cells[1] | Should -Be 'Your cabinet has no player 2'
        @($guide.Rows | Where-Object { $_.Cells[3] -eq 'P1Button1' })[0].Cells[1] | Should -Be 'Key: Left Ctrl'
    }

    It 'says the cabinet is big enough, and says it does not know when the player never gave the size' {
        $doc = New-FitProfile -Name 'fight' -Buttons ((New-FitButton 'P1Button1' 'Punch') + (New-FitButton 'P2Button2' 'Kick'))
        $cabinet = Read-TpmCabinetState -StateRoot (New-Folder)
        (Get-TpmGameControlGuide -Doc $doc -Title 'Fight' -Cabinet $cabinet).FitLines -join ' ' | Should -Match 'does not know how many players and buttons'
        Set-TpmCabinetKeys -State $cabinet -Keys @{} -Players 2 -ButtonsPerPlayer 6
        (Get-TpmGameControlGuide -Doc $doc -Title 'Fight' -Cabinet $cabinet).FitLines -join ' ' | Should -Match 'enough players and buttons'
    }

    It 'names a device the game needs and the player does not have, offers the way around it, and does not guess when never asked' {
        $racer = New-FitProfile -Name 'race' -Buttons (New-FitButton 'P1Button1' 'Shift') -Wheel
        $cabinet = Read-TpmCabinetState -StateRoot (New-Folder)
        (Get-TpmCabinetFitLines -ProfileControls (Get-TpmLedProfileControls -Doc $racer) -Cabinet $cabinet) -join ' ' | Should -Match 'does not know if you have a steering wheel and pedals'
        Set-TpmCabinetDevice -State $cabinet -Class 'Wheel' -Has $false
        Set-TpmCabinetDevice -State $cabinet -Class 'XboxStylePad' -Has $true
        $text = (Get-TpmCabinetFitLines -ProfileControls (Get-TpmLedProfileControls -Doc $racer) -Cabinet $cabinet) -join ' '
        $text | Should -Match 'needs a steering wheel and pedals. You told TPM you do not have that'
        $text | Should -Match 'gamepad can steer'
        $shooter = New-FitProfile -Name 'shoot' -Buttons (New-FitButton 'P1Button1' 'Trigger') -Gun
        Set-TpmCabinetDevice -State $cabinet -Class 'LightGun' -Has $false
        Set-TpmCabinetDevice -State $cabinet -Class 'PointerOrTrackball' -Has $true
        (Get-TpmCabinetFitLines -ProfileControls (Get-TpmLedProfileControls -Doc $shooter) -Cabinet $cabinet) -join ' ' | Should -Match 'aim with your trackball'
    }

    It 'asks first about Exit, Pause and Menu, accepts Esc as the Exit key, and does not count an unanswered one as learned' {
        $controls = @(Get-TpmCabinetControlList -Players 1 -Buttons 1 | Where-Object { $_.Control -in @('Exit', 'Pause', 'Menu') })
        $controls.Count | Should -Be 3
        $script:asked = New-Object System.Collections.Generic.List[string]
        Mock Read-TpmYesNo { [void]$script:asked.Add($Prompt); if ($Prompt -match 'Exit|Menu') { 'Y' } else { 'N' } }
        Mock Write-TpmText { }
        $presses = New-Object System.Collections.Generic.Queue[string]
        foreach ($k in @('Escape', 'Tab')) { $presses.Enqueue($k) }
        $result = Invoke-TpmLearnKeys -Controls $controls -ReadKey { $presses.Dequeue() }
        $result.Keys['Exit'] | Should -Be 'Escape'
        $result.Keys['Menu'] | Should -Be 'Tab'
        $result.Keys.Contains('Pause') | Should -BeFalse
        $result.Skipped | Should -Contain 'the Pause button'
        $script:asked.Count | Should -Be 3
    }

    It 'puts the older saved answers back with one step, keeps the current ones as a copy, and changes nothing when there is no older copy' {
        $root = New-Folder
        Restore-TpmCabinetBackup -StateRoot $root | Should -BeFalse
        Test-Path -LiteralPath (Get-TpmControlStatePath -StateRoot $root).Cabinet | Should -BeFalse
        $state = Read-TpmCabinetState -StateRoot $root
        Set-TpmCabinetKeys -State $state -Keys @{ Coin1 = @{ Key = '5'; Source = 'PressedByPlayer' } } -Players 2 -ButtonsPerPlayer 6
        Save-TpmCabinetState -State $state -StateRoot $root
        Set-TpmCabinetKeys -State $state -Keys @{ Coin1 = @{ Key = '9'; Source = 'PressedByPlayer' } }
        Save-TpmCabinetState -State $state -StateRoot $root
        (Get-TpmCabinetKey -State (Read-TpmCabinetState -StateRoot $root) -Control 'Coin1') | Should -Be '9'
        Restore-TpmCabinetBackup -StateRoot $root | Should -BeTrue
        $back = Read-TpmCabinetState -StateRoot $root
        (Get-TpmCabinetKey -State $back -Control 'Coin1') | Should -Be '5'
        $back.Players | Should -Be 2
        Restore-TpmCabinetBackup -StateRoot $root | Should -BeTrue
        (Get-TpmCabinetKey -State (Read-TpmCabinetState -StateRoot $root) -Control 'Coin1') | Should -Be '9'
    }
}

Describe 'Learning arcade buttons from the cabinet files first' {
    BeforeAll {
        function script:New-LedFolder {
            $dir = New-Folder
            $games = @('g1', 'g2', 'g3') | ForEach-Object { $code = $(if ($_ -eq 'g3') { 'KEYCODE_X' } else { 'KEYCODE_Z' }); '<controlGroup groupName="' + $_ + '" numPlayers="2"><player number="1"><control name="P1_BUTTON3" inputCodes="' + $code + '"/></player></controlGroup>' }
            $text = '<dat><emulator emuname="TeknoParrot"><controlGroup groupName="DEFAULT" numPlayers="2"><player number="1">' +
                '<control name="P1_BUTTON1" inputCodes="KEYCODE_LCONTROL|JOYCODE_1_BUTTON1"/><control name="P1_BUTTON2" inputCodes="KEYCODE_FOO"/>' +
                '<control name="P1_JOYSTICK_UP" inputCodes="KEYCODE_UP"/><control name="START1" inputCodes="KEYCODE_1"/><control name="COIN1" inputCodes="KEYCODE_5"/>' +
                '</player></controlGroup>' + ($games -join '') + '</emulator></dat>'
            [System.IO.File]::WriteAllText((Join-Path $dir 'LEDBlinkyControls.xml'), $text, (New-Object System.Text.UTF8Encoding $false))
            return $dir
        }
    }
    BeforeEach {
        Mock Write-Host { }
        Mock Write-Log { }
        Mock Test-TpmKeyPressAvailable { $true }
        Mock Get-TpmKeysPressedOnTheirOwn { @() }
        Mock Get-TpmLedBlinkyKeyMap { [pscustomobject]@{ Found = $false; Controls = @() } }
        Mock Get-TpmStandardArcadeKeys { [ordered]@{} }
        Mock Get-TpmControllerEvidence { [pscustomobject]@{ EvidenceStatus = 'Observed'; DeviceObservations = @() } }
        Mock Get-TpmEncoderCount { 0 }
        Mock Get-TpmEncoderFingerprints { @() }
        $script:asked = New-Object System.Collections.Generic.List[string]
        Mock Read-TpmChoice { if ($Prompt -match 'Use these keys') { 'Y' } else { '1' } }
        Mock Invoke-TpmLearnKeys { foreach ($c in @($Controls)) { [void]$script:asked.Add([string]$c.Control) }; [pscustomobject]@{ Keys = @{}; Skipped = @() } }
        $script:ledBlinkyRoot = New-LedFolder
    }
    AfterEach { Remove-Variable -Name ledBlinkyRoot -Scope Script -ErrorAction SilentlyContinue }

    It 'suggests keys from the LEDBlinky file, names the source, uses the most common key and says the games disagree' {
        $found = Get-TpmCabinetFileSuggestions -LedRoot $script:ledBlinkyRoot
        $found.Keys['P1Button1'].Key | Should -Be 'Left Ctrl'
        $found.Keys['P1Button1'].From | Should -Be 'your LEDBlinky file'
        $found.Keys['P1ButtonStart'].Key | Should -Be '1'
        $found.Keys['Coin1'].Key | Should -Be '5'
        $found.Keys['P1ButtonUp'].Key | Should -Be 'Up arrow'
        $found.Keys['P1Button3'].Key | Should -Be 'Z'
        $found.Keys.Contains('P1Button2') | Should -BeFalse
        @($found.Unsure | ForEach-Object { $_.Id }) | Should -Contain 'P1Button2'
        ($found.Notes -join ' ') | Should -Match 'do not all agree on the key for 1 control'
        ($found.Details -join ' ') | Should -Match 'KEYCODE_Z in 2 games, KEYCODE_X in 1 game'
        $found.Players | Should -Be 2
    }

    It 'turns MAME key codes into the key names TPM stores, and leaves unknown codes empty' {
        ConvertTo-TpmKeyName -Name 'KEYCODE_LCONTROL' -From Mame | Should -Be 'Left Ctrl'
        ConvertTo-TpmKeyName -Name 'KEYCODE_1_PAD' -From Mame | Should -Be 'Numpad 1'
        ConvertTo-TpmKeyName -Name 'KEYCODE_RIGHT' -From Mame | Should -Be 'Right arrow'
        ConvertTo-TpmKeyName -Name 'KEYCODE_FOO' -From Mame | Should -Be ''
    }

    It 'ignores a LEDBlinky file that is too large' {
        $big = New-Folder
        $stream = [System.IO.File]::Create((Join-Path $big 'LEDBlinkyControls.xml'))
        try { $stream.SetLength(21MB) } finally { $stream.Dispose() }
        (Read-TpmLedBlinkyControlKeys -Root $big).Found | Should -BeFalse
    }

    It 'saves nothing when the player does not confirm, and only asks for the controls with no suggested key' {
        $state = New-Folder
        Mock Read-TpmYesNo { if ($Prompt -match 'Read my cabinet files') { 'Y' } else { 'N' } }
        Invoke-TpmButtonLearning -StateRoot $state
        @((Read-TpmCabinetState -StateRoot $state).Keys.PSObject.Properties).Count | Should -Be 0
        @($script:asked) | Should -Not -Contain 'P1Button1'
        @($script:asked) | Should -Not -Contain 'Coin1'
        @($script:asked) | Should -Contain 'P1ButtonDown'
    }

    It 'saves the suggested keys with their source after the player confirms' {
        $state = New-Folder
        Mock Read-TpmYesNo { if ($Prompt -match 'Read my cabinet files|Save this') { 'Y' } else { 'N' } }
        Invoke-TpmButtonLearning -StateRoot $state
        $saved = Read-TpmCabinetState -StateRoot $state
        (Get-TpmCabinetKey -State $saved -Control 'P1Button1') | Should -Be 'Left Ctrl'
        $saved.Keys.PSObject.Properties['P1Button1'].Value.Source | Should -Be 'LedBlinkyControls'
    }

    It 'never replaces a key saved before' {
        $state = New-Folder
        $cabinet = Read-TpmCabinetState -StateRoot $state
        Set-TpmCabinetKeys -State $cabinet -Keys @{ P1Button1 = @{ Key = 'Q'; Source = 'PressedByPlayer' } } -Players 1 -ButtonsPerPlayer 1
        Save-TpmCabinetState -State $cabinet -StateRoot $state
        Mock Read-TpmYesNo { if ($Prompt -match 'Read my cabinet files|Keep those|Save this') { 'Y' } else { 'N' } }
        Invoke-TpmButtonLearning -StateRoot $state
        $saved = Read-TpmCabinetState -StateRoot $state
        (Get-TpmCabinetKey -State $saved -Control 'P1Button1') | Should -Be 'Q'
        (Get-TpmCabinetKey -State $saved -Control 'Coin1') | Should -Be '5'
    }
}

Describe 'Picture control guides' {
    BeforeAll {
        function script:New-PictureDoc {
            param([string[]]$Buttons)
            $doc = New-Object System.Xml.XmlDocument
            $doc.LoadXml('<GameProfile><GameProfileRevision>1</GameProfileRevision><JoystickButtons>' + (($Buttons | ForEach-Object { $p = $_ -split '\|'; '<JoystickButtons><ButtonName>' + [System.Net.WebUtility]::HtmlEncode($p[0]) + '</ButtonName><InputMapping>' + $p[1] + '</InputMapping><AnalogType>' + $(if ($p.Count -gt 2) { $p[2] } else { 'None' }) + '</AnalogType></JoystickButtons>' }) -join '') + '</JoystickButtons></GameProfile>')
            return $doc
        }
        $script:EveryKind = @('Coin|Coin1', 'Start|P1ButtonStart', 'Up|P1ButtonUp', 'Punch|P1Button1', 'Steering|Analog0|Wheel', 'Gas|Analog1|Gas', 'Gear Shift|P1Button2', 'Trackball|P1Trackball', 'Spinner|P1Spinner',
            'Wii A|WiiA', 'Nunchuk Z|NZ', 'Guitar Strum|GS', 'Green Fret|GG', 'Snare Drum|DS', 'Dance Up|DU', 'Pointer|PT', 'Microphone|MIC', 'Throttle|Thr|SWThrottle', 'Gun X|GunX|AnalogJoystick', 'Weird Thing|Zork')
    }
    BeforeEach { Mock Write-Log { }; Mock Write-Host { } }

    It 'draws a titled picture and a list for every kind of controller the game uses, with every control named' {
        $cabinet = Read-TpmCabinetState -StateRoot (New-Folder)
        $guide = Get-TpmGameControlGuide -Doc (New-PictureDoc $script:EveryKind) -Title 'Everything' -Cabinet $cabinet
        $html = ConvertTo-TpmGuideHtml -Guide $guide
        foreach ($title in @('Arcade panel', 'Steering wheel and pedals', 'Pointer', 'Flight stick or other stick', 'Trackball', 'Spinner', 'Wii remote and Nunchuk', 'Guitar', 'Drums', 'Dance pad', 'Microphone', 'Other controls')) { $html | Should -Match ('<h2>' + [regex]::Escape($title)) }
        @([regex]::Matches($html, '<svg ')).Count | Should -Be @($guide.Devices).Count
        @([regex]::Matches($html, '<svg [^>]*><title [^>]*>[^<]+</title><desc [^>]*>[^<]+</desc>')).Count | Should -Be @($guide.Devices).Count
        foreach ($label in @('Punch', 'Steering', 'Gear Shift', 'Wii A', 'Guitar Strum', 'Snare Drum', 'Dance Up', 'Microphone', 'Throttle', 'Gun X', 'Weird Thing')) { $html | Should -Match ('<text [^>]*>' + $label + '</text>') }
        $html | Should -Match '<li><b>Weird Thing</b></li>'
    }

    It 'puts the player''s pad names on a pad picture, colors the marker with the light color and always prints the color name' {
        $cabinet = Read-TpmCabinetState -StateRoot (New-Folder)
        $doc = New-PictureDoc @('Coin|Coin1', 'Start|P1ButtonStart', 'Punch|P1Button1', 'Test|Test')
        $guide = Get-TpmGameControlGuide -Doc $doc -Title 'Pad game' -Cabinet $cabinet -Baseline (New-TpmBaseline -Preset 'PlayStation') -LedColors @{ P1_BUTTON1 = 'Red'; START1 = '0,255,0'; COIN1 = 'red" onload="x' }
        $html = ConvertTo-TpmGuideHtml -Guide $guide
        $html | Should -Match 'Your PlayStation controller'
        $html | Should -Match '<li><b>Punch</b> - Cross button; Light: Red</li>'
        $html | Should -Match 'fill="red" stroke'
        $html | Should -Match 'fill="#00ff00" stroke'
        $html | Should -Not -Match 'onload=\"'
        $html | Should -Match 'No button on your controller layout: Test\.'
    }

    It 'cannot carry markup from a game name or control name, and has no scripts, links or outside files' {
        $cabinet = Read-TpmCabinetState -StateRoot (New-Folder)
        $guide = Get-TpmGameControlGuide -Doc (New-PictureDoc @('Shoot <script>alert(1)</script>|P1Button1', 'Start|P1ButtonStart', 'Aim|GunX|AnalogJoystick')) -Title 'Bad <img src=x onerror=y> name' -Cabinet $cabinet
        $html = ConvertTo-TpmGuideHtml -Guide $guide
        $html | Should -Not -Match '<script'
        $html | Should -Not -Match '<img'
        $html | Should -Match '&lt;script&gt;'
        $html | Should -Not -Match '(?i)https?:|<[^>]*\b(src|href)=|url\(|<link|<iframe'
    }

    It 'prints one game per page with a sheet for every game, and keeps pictures whole' {
        $cabinet = Read-TpmCabinetState -StateRoot (New-Folder)
        $games = @(
            [pscustomobject]@{ Code = 'a'; Title = 'Game A'; Doc = (New-PictureDoc @('Start|P1ButtonStart', 'Punch|P1Button1')) },
            [pscustomobject]@{ Code = 'b'; Title = 'Game B'; Doc = (New-PictureDoc @('Steering|Analog0|Wheel')) })
        $guide = Get-TpmCabinetGamesGuide -Cabinet $cabinet -Games $games
        $html = ConvertTo-TpmGuideHtml -Guide $guide
        @([regex]::Matches($html, '<section class="game">')).Count | Should -Be 2
        $html | Should -Match '<h2>Controls for Game A</h2>'
        $html | Should -Match '<h2>Controls for Game B</h2>'
        $html | Should -Match '@page'
        $html | Should -Match 'section\.game\{break-before:page;page-break-before:always\}'
        $html | Should -Match 'figure\{[^}]*break-inside:avoid'
        $html | Should -Match 'svg\{[^}]*max-width:720px;height:auto'
    }
}
