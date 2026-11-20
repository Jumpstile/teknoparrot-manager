#Requires -Module Pester

# Xbox starter layout for player 1.
# What a user sees or loses: free Xbox slots get a standard layout, an Xbox binding that is already there is never replaced,
# keyboard and arcade-encoder bindings are never touched, a game that has no Xbox setting is left alone, a preview changes
# nothing on disk, and a backup exists before anything is written.
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.
# What this CANNOT prove: that TeknoParrot reads the saved bindings and that a real Xbox controller presses them.

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

    function script:New-CtlProfile {
        param([string]$Dir, [string]$Name, [string]$Options = '<string>DirectInput</string><string>XInput</string>')
        $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<GameProfile>
  <ConfigValues>
    <FieldInformation><CategoryName>General</CategoryName><FieldName>Input API</FieldName><FieldValue>DirectInput</FieldValue><FieldOptions>$Options</FieldOptions></FieldInformation>
  </ConfigValues>
  <JoystickButtons>
    <JoystickButtons><ButtonName>Coin</ButtonName><XInputButton><IsLeftThumbX>false</IsLeftThumbX><IsRightThumbX>false</IsRightThumbX><IsLeftThumbY>false</IsLeftThumbY><IsRightThumbY>false</IsRightThumbY><IsAxisMinus>false</IsAxisMinus><IsLeftTrigger>false</IsLeftTrigger><IsRightTrigger>false</IsRightTrigger><ButtonCode>99</ButtonCode><IsButton>true</IsButton><ButtonIndex>0</ButtonIndex><XInputIndex>0</XInputIndex></XInputButton><RawInputButton><DevicePath>kbd</DevicePath><DeviceType>Keyboard</DeviceType><KeyboardKey>D5</KeyboardKey></RawInputButton><InputMapping>Coin1</InputMapping><AnalogType>None</AnalogType></JoystickButtons>
    <JoystickButtons><ButtonName>Start</ButtonName><RawInputButton><DevicePath>kbd</DevicePath><DeviceType>Keyboard</DeviceType><KeyboardKey>D1</KeyboardKey></RawInputButton><InputMapping>P1ButtonStart</InputMapping><AnalogType>None</AnalogType></JoystickButtons>
    <JoystickButtons><ButtonName>Button 1</ButtonName><DirectInputButton><Button>7</Button></DirectInputButton><InputMapping>P1Button1</InputMapping><AnalogType>None</AnalogType></JoystickButtons>
    <JoystickButtons><ButtonName>Button 2</ButtonName><InputMapping>P1Button2</InputMapping><AnalogType>None</AnalogType></JoystickButtons>
  </JoystickButtons>
</GameProfile>
"@
        $path = Join-Path $Dir ($Name + '.xml')
        [System.IO.File]::WriteAllText($path, $xml, (New-Object System.Text.UTF8Encoding $false))
        return $path
    }
}

Describe 'Xbox starter layout' {
    BeforeEach {
        $script:Dir = Join-Path $TestDrive ('up-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        [void][System.IO.Directory]::CreateDirectory($script:Dir)
    }

    It 'plans Add for free slots, Keep for an existing Xbox binding and NotInGame for missing controls' {
        $path = New-CtlProfile -Dir $script:Dir -Name 'Game1'
        $plan = Get-TpmXboxStarterPlan -Doc (Read-Xml $path)
        ($plan.Rows | Where-Object Mapping -eq 'Coin1').Action | Should -Be 'Keep'
        ($plan.Rows | Where-Object Mapping -eq 'P1ButtonStart').Action | Should -Be 'Add'
        ($plan.Rows | Where-Object Mapping -eq 'P1Button1').Action | Should -Be 'Add'
        ($plan.Rows | Where-Object Mapping -eq 'P1Button6').Action | Should -Be 'NotInGame'
        $plan.AddCount | Should -Be 3
        $plan.NeedsApiChange | Should -BeTrue
    }

    It 'a preview changes nothing on disk' {
        $path = New-CtlProfile -Dir $script:Dir -Name 'Game1'
        $before = [System.IO.File]::ReadAllBytes($path)
        $r = Invoke-TpmXboxStarterApply -UserProfilesDir $script:Dir -ProfilePath $path -DryRun $true
        $r.Status | Should -Be 'WouldChange'
        $r.Added | Should -Be 3
        [System.IO.File]::ReadAllBytes($path) | Should -Be $before
        Test-Path (Join-Path $script:Dir 'FullBackup') | Should -BeFalse
    }

    It 'applies the layout, keeps existing bindings, and makes a backup first' {
        $path = New-CtlProfile -Dir $script:Dir -Name 'Game1'
        $r = Invoke-TpmXboxStarterApply -UserProfilesDir $script:Dir -ProfilePath $path -DryRun $false
        $r.Status | Should -Be 'Changed'
        $r.Backup.Verified | Should -BeTrue
        $doc = Read-Xml $path
        Get-ProfileInputApi $doc | Should -Be 'XInput'
        $start = @(Get-ButtonNodes $doc | Where-Object { $_.InputMapping -eq 'P1ButtonStart' })[0]
        $start.XInputButton.ButtonCode | Should -Be '16'
        $start.RawInputButton.KeyboardKey | Should -Be 'D1'
        $start.ChildNodes[1].Name | Should -Be 'XInputButton'
        $b1 = @(Get-ButtonNodes $doc | Where-Object { $_.InputMapping -eq 'P1Button1' })[0]
        $b1.XInputButton.ButtonCode | Should -Be '4096'
        $b1.DirectInputButton.Button | Should -Be '7'
        $coin = @(Get-ButtonNodes $doc | Where-Object { $_.InputMapping -eq 'Coin1' })[0]
        $coin.XInputButton.ButtonCode | Should -Be '99'
        (Get-TpmXboxStarterPlan -Doc $doc).AddCount | Should -Be 0
    }

    It 'a second apply changes nothing' {
        $path = New-CtlProfile -Dir $script:Dir -Name 'Game1'
        [void](Invoke-TpmXboxStarterApply -UserProfilesDir $script:Dir -ProfilePath $path -DryRun $false)
        $r = Invoke-TpmXboxStarterApply -UserProfilesDir $script:Dir -ProfilePath $path -DryRun $false
        $r.Status | Should -Be 'NoChange'
    }

    It 'leaves a game alone when it has no Xbox setting' {
        $path = New-CtlProfile -Dir $script:Dir -Name 'Game2' -Options '<string>DirectInput</string>'
        $before = [System.IO.File]::ReadAllBytes($path)
        $r = Invoke-TpmXboxStarterApply -UserProfilesDir $script:Dir -ProfilePath $path -DryRun $false
        $r.Status | Should -Be 'Unsupported'
        [System.IO.File]::ReadAllBytes($path) | Should -Be $before
    }
}
