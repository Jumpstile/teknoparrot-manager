#Requires -Module Pester

# Saved controller answers, learned arcade keys, play-test evidence and control guides (issues #201, #307, #267).
# What a user sees or loses: a question already answered is not asked again, a damaged or older saved file is never lost,
# a game is only Verified after the player says it worked and stops being Verified when its controls change, a game that needs
# calibration is not Verified until it is done, and a printed guide shows the player's own keys. No game file is ever written.
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.
# Everything uses temp folders and fake key presses.
# What this CANNOT prove: that a real encoder's buttons are seen by the console (Ctrl, Alt and Shift included), that a real
# controller works in a game, or that the page opens in a real browser. Those are in docs/CONTROLLER-HANDS-ON-TEST-PLAN.md.

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
        @($script:asked | Where-Object { $_ -match 'Use the Xbox controller' }).Count | Should -Be 1
    }

    It 'still prints the plan when the answers cannot be saved' {
        Mock Read-TpmYesNo { 'Y' }
        Mock Save-TpmCabinetState { throw 'disk full' }
        { Invoke-DeviceSurvey -StateRoot $script:State } | Should -Not -Throw
        Should -Invoke Write-Host -ParameterFilter { $Object -match 'YOUR BINDING PLAN' }
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
