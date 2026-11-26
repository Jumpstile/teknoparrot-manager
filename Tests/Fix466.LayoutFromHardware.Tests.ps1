#Requires -Module Pester

# FIX466: "Choose your controller layout" starts on the layout that matches the connected hardware.
# Only the layout functions are loaded from the production script. No hardware, install, registry or network is touched.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($productionPath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX466 tests could not parse the production script.' }
    $wanted = @('Get-TpmBaselinePresetForEvidence', 'Get-TpmBaselineDetectedLine', 'Invoke-TpmBaselineChooseScreen', 'Get-TpmBaselinePresets', 'Get-TpmBaselineSlots', 'Get-TpmBaselineChooserNotes', 'Get-TpmPadButtons', 'New-TpmBaseline')
    $definitions = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wanted -contains $args[0].Name }, $true))
    $functionFile = Join-Path $TestDrive 'tpm-fix466-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, (@($definitions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"), (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    if ($definitions.Count -ne $wanted.Count) { throw 'FIX466 tests could not find every layout function.' }

    function Write-Log { param($Message) }
    function Write-TpmText { param($Text, $Color, $Indent) $script:Said += [string]$Text }
    # The person presses B at once; the default offered is what Enter would pick.
    function Read-TpmChoice { param($Prompt, $Choices, $Default) $script:Offered = [string]$Default; return 'B' }
    function New-Obs { param($Class, $Confidence) [pscustomobject]@{ DeviceClass = $Class; Confidence = $Confidence; Basis = 'x'; Count = 1; ReasonCodes = @() } }
    function Invoke-Screen {
        param($Observations, $Current = $null, [switch]$Throw)
        $script:Said = @(); $script:Offered = ''
        $script:Obs = @($Observations); $script:Boom = [bool]$Throw
        function Get-TpmControllerEvidence { if ($script:Boom) { throw 'no hardware check' }; [pscustomobject]@{ DeviceObservations = $script:Obs } }
        [void](Invoke-TpmBaselineChooseScreen -StateDir $TestDrive -Current $Current)
    }
}

Describe 'FIX466 default layout follows the connected hardware' {
    It 'an Xbox-style pad selects the Xbox layout and says so' {
        Invoke-Screen @(New-Obs 'XboxStylePad' 'High')
        $script:Offered | Should -Be '1'
        ($script:Said -join "`n") | Should -Match 'TPM found a standard \(XInput\) gamepad, so "Xbox controller" is already selected\. Press Enter to use it, or pick another number\.'
    }
    It 'an arcade encoder selects the arcade stick layout and says so' {
        Invoke-Screen @(New-Obs 'ArcadeEncoder' 'Medium')
        $script:Offered | Should -Be '4'
        ($script:Said -join "`n") | Should -Match 'already selected'
        ($script:Said -join "`n") | Should -Match 'Arcade stick that shows up as an Xbox controller'
    }
    It 'nothing detected keeps layout 1 and says nothing new' {
        Invoke-Screen @()
        $script:Offered | Should -Be '1'
        ($script:Said -join "`n") | Should -Not -Match 'already selected'
    }
    It 'a name guess alone is not enough' {
        Invoke-Screen @(New-Obs 'ArcadeEncoder' 'Low')
        $script:Offered | Should -Be '1'
        ($script:Said -join "`n") | Should -Not -Match 'already selected'
    }
    It 'two kinds of hardware keep layout 1' {
        Invoke-Screen @((New-Obs 'XboxStylePad' 'High'), (New-Obs 'ArcadeEncoder' 'Medium'))
        $script:Offered | Should -Be '1'
        ($script:Said -join "`n") | Should -Not -Match 'already selected'
    }
    It 'a saved layout wins over detection' {
        Invoke-Screen @(New-Obs 'XboxStylePad' 'High') -Current ([pscustomobject]@{ Preset = 'Nintendo' })
        $script:Offered | Should -Be '3'
        ($script:Said -join "`n") | Should -Not -Match 'already selected'
    }
    It 'a failing hardware check still shows the screen with layout 1' {
        Invoke-Screen @() -Throw
        $script:Offered | Should -Be '1'
    }
}

Describe 'FIX466 which detected class maps to which layout' {
    It 'maps pads and encoders, and nothing else' {
        Get-TpmBaselinePresetForEvidence -Evidence ([pscustomobject]@{ DeviceObservations = @(New-Obs 'XboxStylePad' 'High') }) | Should -Be 'Xbox'
        Get-TpmBaselinePresetForEvidence -Evidence ([pscustomobject]@{ DeviceObservations = @(New-Obs 'ArcadeEncoder' 'Medium') }) | Should -Be 'ArcadeStick'
        Get-TpmBaselinePresetForEvidence -Evidence ([pscustomobject]@{ DeviceObservations = @(New-Obs 'OtherGamePad' 'Medium') }) | Should -Be ''
        Get-TpmBaselinePresetForEvidence -Evidence ([pscustomobject]@{ DeviceObservations = @(New-Obs 'Wheel' 'Low') }) | Should -Be ''
    }
}
