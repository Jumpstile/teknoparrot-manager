#Requires -Module Pester

# #473: a TeknoParrot update changes many profiles (a HideCursor field, a higher GameProfileRevision, buttons that carry a VisibleWhen
# condition, and the same InputMapping listed more than once for different conditions). The controller layout preview and apply must
# still work on that shape: free slots are added, everything else (HideCursor, VisibleWhen, the other button) stays byte for byte, and the
# saved file reads back. The profile settings here are a stand-in in the shape TeknoParrot writes; a real 1.0.0.2338 folder is a separate run.
# What this CANNOT prove: that the real changed profiles behave the same, that TeknoParrot reads the saved bindings, or that a pad presses them.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$null, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Fix473 tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $functionFile = Join-Path $TestDrive 'tpm-fix473-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    function Write-TpmCompactExtractionProgress { param([Parameter(ValueFromRemainingArguments)]$Ignored) }
    function Write-Log { param([string]$msg) }

    # The new shape: HideCursor, Input API, a higher revision, and the Start slot listed twice (once for each Outputs setting).
    function script:New-F473Xml {
        param([bool]$Saved)
        $bound = if ($Saved) { '<DirectInputButton><Button>3</Button></DirectInputButton>' } else { '' }
        $buttons = '<JoystickButtons><ButtonName>Start</ButtonName>{0}<InputMapping>P1ButtonStart</InputMapping><AnalogType>None</AnalogType></JoystickButtons>' -f $bound
        $buttons += '<JoystickButtons><ButtonName>Start (Network)</ButtonName>{0}<InputMapping>P1ButtonStart</InputMapping><AnalogType>None</AnalogType><VisibleWhen>Outputs=Network</VisibleWhen></JoystickButtons>' -f $bound
        $buttons += '<JoystickButtons><ButtonName>Button 1</ButtonName>{0}<InputMapping>P1Button1</InputMapping><AnalogType>None</AnalogType><VisibleWhen>HideCursor=0</VisibleWhen></JoystickButtons>' -f $bound
        $fields = '<FieldInformation><CategoryName>General</CategoryName><FieldName>Input API</FieldName><FieldValue>DirectInput</FieldValue><FieldOptions><string>DirectInput</string><string>XInput</string></FieldOptions></FieldInformation>'
        $fields += '<FieldInformation><CategoryName>General</CategoryName><FieldName>HideCursor</FieldName><FieldType>Bool</FieldType><FieldValue>0</FieldValue></FieldInformation>'
        $fields += '<FieldInformation><CategoryName>General</CategoryName><FieldName>Outputs</FieldName><FieldType>Dropdown</FieldType><FieldValue>None</FieldValue><FieldOptions><string>None</string><string>Network</string></FieldOptions><VisibleWhen>HideCursor=1</VisibleWhen></FieldInformation>'
        return ('<?xml version="1.0" encoding="utf-8"?><GameProfile><GameName>New Game</GameName><EmulationProfile>Emu</EmulationProfile><GameProfileRevision>7</GameProfileRevision><ExecutableName>game</ExecutableName><ConfigValues>{0}</ConfigValues><JoystickButtons>{1}</JoystickButtons></GameProfile>' -f $fields, $buttons)
    }
}

Describe 'Fix473 layout on the newer TeknoParrot profile shape' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ('r-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        $script:Users = Join-Path $script:Root 'UserProfiles'
        $script:Game = Join-Path $script:Root 'GameProfiles'
        [void][System.IO.Directory]::CreateDirectory($script:Users)
        [void][System.IO.Directory]::CreateDirectory($script:Game)
        [System.IO.File]::WriteAllText((Join-Path $script:Game 'NewGame.xml'), (New-F473Xml -Saved $false), (New-Object System.Text.UTF8Encoding $false))
        $script:UserPath = Join-Path $script:Users 'NewGame.xml'
        [System.IO.File]::WriteAllText($script:UserPath, (New-F473Xml -Saved $false), (New-Object System.Text.UTF8Encoding $false))
        $script:Layout = @(Get-TpmBaselineLayout -Baseline (New-TpmBaseline -Preset 'Xbox'))
    }

    It 'previews the free slots of a profile with VisibleWhen buttons and a repeated mapping' {
        # Mutation: refuse or skip a profile that has VisibleWhen, HideCursor or a higher revision.
        $plan = Get-TpmBaselineGamePlan -ProfilePath $script:UserPath -GameProfilesDir $script:Game -Layout $script:Layout
        $plan.Status | Should -Be 'Ready'
        ($plan.Rows | Where-Object Mapping -eq 'P1ButtonStart').Action | Should -Be 'Add'
        ($plan.Rows | Where-Object Mapping -eq 'P1Button1').Action | Should -Be 'Add'
    }

    It 'applies it, reads it back, and leaves HideCursor and every VisibleWhen condition exactly as they were' {
        # Mutation: rewrite the whole file or drop a field the plan did not touch.
        $plan = Get-TpmBaselineGamePlan -ProfilePath $script:UserPath -GameProfilesDir $script:Game -Layout $script:Layout
        $result = Invoke-TpmBaselineApply -UserProfilesDir $script:Users -ProfilePath $script:UserPath -GameProfilesDir $script:Game -Layout $script:Layout -DryRun $false -ExpectedSignature $plan.Signature
        $result.Status | Should -Be 'Changed'
        $result.Verified | Should -BeTrue
        $doc = Read-Xml $script:UserPath
        $doc.SelectSingleNode('//FieldInformation[FieldName="HideCursor"]/FieldValue').InnerText | Should -Be '0'
        $doc.SelectSingleNode('//FieldInformation[FieldName="Outputs"]/VisibleWhen').InnerText | Should -Be 'HideCursor=1'
        $doc.SelectSingleNode('//JoystickButtons[ButtonName="Start (Network)"]/VisibleWhen').InnerText | Should -Be 'Outputs=Network'
        $doc.SelectSingleNode('//JoystickButtons[ButtonName="Button 1"]/XInputButton/ButtonCode') | Should -Not -BeNullOrEmpty
        $doc.GameProfile.GameProfileRevision | Should -Be '7'
    }
}
