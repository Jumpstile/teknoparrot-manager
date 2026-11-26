#Requires -Module Pester

# Specialty controllers: Wii remote, guitar, drums, dance pad, PlayStation and Nintendo pads, flight stick and more.
# What a user sees or loses: a device Windows names is shown as "may be connected" (never pre-answered), a device with an
# unknown name is not guessed, the player can say by hand what any device is and that choice survives a new look at the
# devices and a reload, it can be cleared, a guitar, drum or dance game shows its device kind and a game without one does not,
# and the plain Wii-remote-in-a-guitar-shell advice is on the screen. Screens fit 79 columns.
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.
# What this CANNOT prove: the names real hardware gives Windows. The fake device lists use plain product words only.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Device kind tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:KindFunctionFile = Join-Path $TestDrive 'tpm-kind-functions.ps1'
    [System.IO.File]::WriteAllText($script:KindFunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:KindFunctionFile
    function Write-TpmCompactExtractionProgress { param([Parameter(ValueFromRemainingArguments)]$Ignored) }

    # A game with the given extra controls: -Extra is a list of @(label, mapping).
    function script:New-KindProfile {
        param([string]$Dir, [string]$Name, [string[][]]$Extra = @())
        $more = (@($Extra | ForEach-Object { '<JoystickButtons><ButtonName>{0}</ButtonName><InputMapping>{1}</InputMapping><AnalogType>None</AnalogType></JoystickButtons>' -f $_[0], $_[1] })) -join ''
        $xml = '<?xml version="1.0" encoding="utf-8"?><GameProfile><GameProfileRevision>1</GameProfileRevision><Description>Test Game</Description><ConfigValues><FieldInformation><CategoryName>General</CategoryName><FieldName>Input API</FieldName><FieldValue>RawInput</FieldValue><FieldOptions><string>RawInput</string><string>XInput</string></FieldOptions></FieldInformation></ConfigValues><JoystickButtons><JoystickButtons><ButtonName>Coin</ButtonName><InputMapping>Coin1</InputMapping><AnalogType>None</AnalogType></JoystickButtons><JoystickButtons><ButtonName>Start</ButtonName><InputMapping>P1ButtonStart</InputMapping><AnalogType>None</AnalogType></JoystickButtons>' + $more + '</JoystickButtons></GameProfile>'
        $path = Join-Path $Dir ($Name + '.xml')
        [System.IO.File]::WriteAllText($path, $xml, (New-Object System.Text.UTF8Encoding $false))
        return $path
    }
}

Describe 'Detecting specialty controllers from device names Windows reports' {
    BeforeEach { Mock Write-Log { } }

    It 'sees <Class> from the name "<Name>" as a Low confidence hint, never High' -ForEach @(
        @{ Class = 'WiiRemote'; Name = 'Wii Remote' }
        @{ Class = 'Guitar'; Name = 'USB Guitar Controller' }
        @{ Class = 'Drums'; Name = 'USB Drum Kit' }
        @{ Class = 'DancePad'; Name = 'Dance Pad' }
        @{ Class = 'PlayStationPad'; Name = 'DualSense Wireless Controller' }
        @{ Class = 'NintendoPad'; Name = 'Joy-Con (L)' }
        @{ Class = 'FlightStick'; Name = 'Flight Stick' }
    ) {
        $deviceName = $Name
        Mock Get-CimInstance { @([pscustomobject]@{ Name = $deviceName; DeviceID = "HID\NOTHING" }) }
        $found = @((Get-TpmControllerEvidence).DeviceObservations | Where-Object DeviceClass -eq $Class)
        $found.Count | Should -Be 1
        $found[0].Confidence | Should -Be 'Low'
        $found[0].Basis | Should -Be 'NameHint'
    }

    It 'does not guess a kind for a device whose name says nothing' {
        Mock Get-CimInstance { @([pscustomobject]@{ Name = 'HID-compliant vendor-defined device'; DeviceID = 'HID\VID_1234&PID_5678\1' }, [pscustomobject]@{ Name = 'USB Input Device'; DeviceID = 'HID\VID_9999&PID_0001\2' }) }
        $classes = @((Get-TpmControllerEvidence).DeviceObservations | ForEach-Object { $_.DeviceClass })
        foreach ($specialty in @('WiiRemote', 'Guitar', 'Drums', 'DancePad', 'PlayStationPad', 'NintendoPad', 'FlightStick', 'Microphone', 'Pointer')) { $classes | Should -Not -Contain $specialty }
    }

    It 'never writes anything about the devices into the player''s saved choices' {
        $state = Join-Path $TestDrive ('d-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        Mock Get-CimInstance { @([pscustomobject]@{ Name = 'Wii Remote'; DeviceID = 'HID\A' }) }
        [void](Get-TpmControllerEvidence)
        Test-Path -LiteralPath (Get-TpmControlStatePath -StateRoot $state).Cabinet | Should -BeFalse
    }
}

Describe 'Tell TPM what each device is' {
    BeforeEach {
        $script:State = Join-Path $TestDrive ('s-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:Screen = New-Object System.Collections.Generic.List[string]
        $script:Answers = New-Object System.Collections.Queue
        Mock Write-Log { }
        Mock Get-ConsoleContentWidth { 79 }
        Mock Write-Host { if ($null -ne $Object) { [void]$script:Screen.Add([string]$Object) } }
        Mock Read-TpmChoice { $script:Answers.Dequeue() }
        $script:Seen = $null
        function script:Set-FakeEvidence { param([object[]]$Observations = @(), [string]$Status = 'Observed'); $script:Seen = [pscustomobject]@{ EvidenceStatus = $Status; DeviceObservations = @($Observations) } }
        Set-FakeEvidence
        Mock Get-TpmControllerEvidence { $script:Seen }
        function script:Get-KindNumber { param([string]$Class) return ([string](1 + @(Get-TpmDeviceKinds | ForEach-Object { $_.Class }).IndexOf($Class))) }
    }

    It 'lists every kind, including the new ones, and the guitar workaround in plain words' {
        'B' | ForEach-Object { $script:Answers.Enqueue($_) }
        Invoke-TpmDeviceKindScreen -StateRoot $script:State
        $text = $script:Screen -join "`n"
        foreach ($word in @('gamepad', 'trackball', 'spinner', 'steering wheel', 'light gun', 'PlayStation controller', 'Nintendo controller', 'flight stick', 'Wii remote', 'pointer', 'guitar controller', 'drum kit', 'dance pad', 'microphone')) { $text | Should -Match ([regex]::Escape($word)) }
        ($text -replace '\s+', ' ') | Should -Match 'Wii remote inside a guitar shell, such as the one that came with Guitar Hero for the Wii'
        ($text -replace '\s+', ' ') | Should -Match 'you mark it as a guitar'
    }

    It 'fits 79 columns' {
        'D', 'B' | ForEach-Object { $script:Answers.Enqueue($_) }
        Set-FakeEvidence -Observations @([pscustomobject]@{ DeviceClass = 'WiiRemote'; Confidence = 'Low'; Basis = 'NameHint'; Count = 1 })
        Invoke-TpmDeviceKindScreen -StateRoot $script:State
        $script:Screen.Count | Should -BeGreaterThan 10
        @($script:Screen | Where-Object { $_.Length -gt 79 }).Count | Should -Be 0
    }

    It 'says a seen device only "may" be connected and keeps the player''s own choice for it' {
        Set-FakeEvidence -Observations @([pscustomobject]@{ DeviceClass = 'WiiRemote'; Confidence = 'Low'; Basis = 'NameHint'; Count = 1 })
        'B' | ForEach-Object { $script:Answers.Enqueue($_) }
        Invoke-TpmDeviceKindScreen -StateRoot $script:State
        ($script:Screen -join "`n") | Should -Match 'Wii remote: not told yet \(TPM may see one\)'
    }

    It 'saves the choice (guitar), keeps it after reload and after a new look finds only a Wii remote, then clears it' {
        Set-FakeEvidence -Observations @([pscustomobject]@{ DeviceClass = 'WiiRemote'; Confidence = 'Low'; Basis = 'NameHint'; Count = 1 })
        $guitar = Get-KindNumber 'Guitar'
        $guitar, 'Y', 'B' | ForEach-Object { $script:Answers.Enqueue($_) }
        Invoke-TpmDeviceKindScreen -StateRoot $script:State
        Get-TpmCabinetDeviceAnswer -State (Read-TpmCabinetState -StateRoot $script:State) -Class 'Guitar' | Should -BeTrue
        # Detection runs again and sees something else: the saved choice does not change and no Wii remote answer is invented.
        Set-FakeEvidence -Observations @([pscustomobject]@{ DeviceClass = 'Drums'; Confidence = 'Low'; Basis = 'NameHint'; Count = 1 })
        'B' | ForEach-Object { $script:Answers.Enqueue($_) }
        Invoke-TpmDeviceKindScreen -StateRoot $script:State
        $reloaded = Read-TpmCabinetState -StateRoot $script:State
        Get-TpmCabinetDeviceAnswer -State $reloaded -Class 'Guitar' | Should -BeTrue
        Get-TpmCabinetDeviceAnswer -State $reloaded -Class 'WiiRemote' | Should -BeNullOrEmpty
        Get-TpmCabinetDeviceAnswer -State $reloaded -Class 'Drums' | Should -BeNullOrEmpty
        (Get-TpmCabinetSummaryLines -State $reloaded) -join ' ' | Should -Match 'a guitar controller'
        # Change it, then clear it.
        $guitar, 'N', 'B' | ForEach-Object { $script:Answers.Enqueue($_) }
        Invoke-TpmDeviceKindScreen -StateRoot $script:State
        Get-TpmCabinetDeviceAnswer -State (Read-TpmCabinetState -StateRoot $script:State) -Class 'Guitar' | Should -BeFalse
        $guitar, 'C', 'B' | ForEach-Object { $script:Answers.Enqueue($_) }
        Invoke-TpmDeviceKindScreen -StateRoot $script:State
        Get-TpmCabinetDeviceAnswer -State (Read-TpmCabinetState -StateRoot $script:State) -Class 'Guitar' | Should -BeNullOrEmpty
    }

    It 'keeps the seven survey questions and the other saved answers when a specialty choice is saved' {
        $cabinet = Read-TpmCabinetState -StateRoot $script:State
        Set-TpmCabinetDevice -State $cabinet -Class 'LightGun' -Has $true
        Save-TpmCabinetState -State $cabinet -StateRoot $script:State
        (Get-KindNumber 'DancePad'), 'Y', 'B' | ForEach-Object { $script:Answers.Enqueue($_) }
        Invoke-TpmDeviceKindScreen -StateRoot $script:State
        $after = Read-TpmCabinetState -StateRoot $script:State
        Get-TpmCabinetDeviceAnswer -State $after -Class 'LightGun' | Should -BeTrue
        Get-TpmCabinetDeviceAnswer -State $after -Class 'DancePad' | Should -BeTrue
        @(Get-TpmDeviceQuestions).Count | Should -Be 7
    }
}

Describe 'Specialty kinds only for a game that needs them' {
    BeforeEach {
        $script:Dir = Join-Path $TestDrive ('g-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void](New-Item -ItemType Directory -Path $script:Dir)
        $script:Cab = [pscustomobject]@{ Version = 1; Devices = [pscustomobject]@{}; Players = 0; ButtonsPerPlayer = 0; EncodersWhenLearned = -1; EncoderFingerprints = $null; Keys = [pscustomobject]@{}; FileStatus = 'Missing' }
    }

    It 'shows the guitar kind and the Wii remote advice for a game with a guitar control, and the player''s choice' {
        $doc = Read-Xml (New-KindProfile -Dir $script:Dir -Name 'gtr' -Extra @(, @('Guitar Green', 'P1GuitarGreen')))
        $text = (Get-TpmGameControlGuide -Doc $doc -Title 'Test Game' -Cabinet $script:Cab).Lines -join ' '
        $text | Should -Match 'TPM does not know if you have a guitar controller'
        $text | Should -Match 'Wii remote inside a guitar shell, such as the one that came with Guitar Hero for the Wii'
        Set-TpmCabinetDevice -State $script:Cab -Class 'Guitar' -Has $true
        $guide = Get-TpmGameControlGuide -Doc $doc -Title 'Test Game' -Cabinet $script:Cab
        ($guide.Lines -join ' ') | Should -Not -Match 'Wii remote inside a guitar shell'
        @($guide.Rows | Where-Object { $_.Cells[0] -eq 'Guitar Green' })[0].Cells[1] | Should -Be 'Your guitar controller'
    }

    It 'shows drums and dance pad only for the game that lists them' {
        $drums = Get-TpmGameControlGuide -Doc (Read-Xml (New-KindProfile -Dir $script:Dir -Name 'drm' -Extra @(, @('Drum Snare', 'P1DrumSnare')))) -Title 'Test Game' -Cabinet $script:Cab
        ($drums.Lines -join ' ') | Should -Match 'a drum kit'
        ($drums.Lines -join ' ') | Should -Not -Match 'guitar|dance pad'
        $dance = Get-TpmGameControlGuide -Doc (Read-Xml (New-KindProfile -Dir $script:Dir -Name 'dnc' -Extra @(, @('Dance Up', 'P1DanceUp')))) -Title 'Test Game' -Cabinet $script:Cab
        ($dance.Lines -join ' ') | Should -Match 'a dance pad'
    }

    It 'shows no specialty choice and no guitar advice for a plain game' {
        $guide = Get-TpmGameControlGuide -Doc (Read-Xml (New-KindProfile -Dir $script:Dir -Name 'plain')) -Title 'Test Game' -Cabinet $script:Cab
        ($guide.Lines -join ' ') | Should -Not -Match '(?i)guitar|drum|dance|microphone|pointer|Wii'
        (@($guide.Rows | ForEach-Object { $_.Cells -join ' ' }) -join ' ') | Should -Not -Match '(?i)guitar|drum|dance|microphone|pointer|Wii'
    }
}

Describe 'Regressions a player would see' {
    It 'keeps the learned key for an ordinary button whose label has a device word in it' {
        $dir = Join-Path $TestDrive ('r-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void](New-Item -ItemType Directory -Path $dir)
        $doc = Read-Xml (New-KindProfile -Dir $dir -Name 'btn' -Extra @(, @('Drum Left', 'P1Button1')))
        $cab = [pscustomobject]@{ Version = 1; Devices = [pscustomobject]@{}; Players = 0; ButtonsPerPlayer = 0; EncodersWhenLearned = -1; EncoderFingerprints = $null; Keys = [pscustomobject]@{}; FileStatus = 'Missing' }
        Set-TpmCabinetKeys -State $cab -Keys @{ P1Button1 = @{ Key = 'A'; Source = 'Pressed' } }
        $guide = Get-TpmGameControlGuide -Doc $doc -Title 'Test Game' -Cabinet $cab
        @($guide.Rows | Where-Object { $_.Cells[0] -eq 'Drum Left' })[0].Cells[1] | Should -Be 'Key: A'
        ($guide.Lines -join ' ') | Should -Not -Match 'drum kit'
    }

    It 'a detected Wii remote still matches the evidence schema' {
        Mock Write-Log { }
        Mock Get-CimInstance { @([pscustomobject]@{ Name = 'Wii Remote'; DeviceID = 'HID\A' }) }
        $testJson = Get-Command Test-Json -ErrorAction SilentlyContinue
        if (-not ($testJson -and $testJson.Parameters.ContainsKey('SchemaFile'))) { Set-ItResult -Skipped -Because 'Test-Json needs PowerShell 7'; return }
        Test-Json -Json ((Get-TpmControllerEvidence) | ConvertTo-Json -Depth 6) -SchemaFile (Join-Path $PSScriptRoot '..\schemas\TpmControllerEvidence.v1.schema.json') | Should -BeTrue
    }
}
