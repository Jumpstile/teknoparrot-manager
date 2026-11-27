#Requires -Module Pester

# Guide setting fixes (#351): a registered game whose profile still holds the stock value gets the guide's value; a value the player
# chose, a game that is not registered and a failed backup change nothing. Profiles are synthetic files under TestDrive.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput([System.IO.File]::ReadAllText($productionPath), [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Profile setting fix tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $functionFile = Join-Path $TestDrive 'tpm-settingfix-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    $script:Sf351Definition = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\TpmProfileSettingFixes.json'

    function New-Sf351Profile {
        param([string]$Dir, [string]$Code, [string]$Field, [string]$Value, [string[]]$Options = @())
        $optionXml = if ($Options.Count -gt 0) { '<FieldOptions>' + (($Options | ForEach-Object { '<string>' + $_ + '</string>' }) -join '') + '</FieldOptions>' } else { '' }
        $xml = '<?xml version="1.0" encoding="utf-8"?><GameProfile><GamePath>C:\Games\' + $Code + '\game.exe</GamePath><ConfigValues><FieldInformation><CategoryName>General</CategoryName><FieldName>' + $Field + '</FieldName><FieldValue>' + $Value + '</FieldValue><FieldType>Bool</FieldType>' + $optionXml + '</FieldInformation></ConfigValues></GameProfile>'
        [System.IO.File]::WriteAllText((Join-Path $Dir ($Code + '.xml')), $xml, (New-Object System.Text.UTF8Encoding $false))
    }

    function Get-Sf351Value {
        param([string]$Dir, [string]$Code, [string]$Field)
        $doc = New-Object System.Xml.XmlDocument
        $doc.Load((Join-Path $Dir ($Code + '.xml')))
        return [string]$doc.SelectSingleNode("/GameProfile/ConfigValues/FieldInformation[FieldName='$Field']/FieldValue").InnerText
    }

    Mock Write-Log {}
    Mock Write-TpmCompactExtractionProgress {}
    Mock Write-TpmOutcome { $script:Sf351Outcome = [pscustomobject]@{ Title = $Title; Status = $Status } }
    Mock New-TpmVerifiedUserProfilesBackup { $script:Sf351Backups++; [pscustomobject]@{ Verified = $script:Sf351BackupOk } }
}

Describe 'Guide setting fixes for registered games' {
    BeforeEach {
        $script:dir = Join-Path $TestDrive ('p-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:dir -Force | Out-Null
        $script:Sf351Outcome = $null
        $script:Sf351Backups = 0
        $script:Sf351BackupOk = $true
    }

    It 'sets the guide value on a game that still has the stock value, after a backup' {
        # Mutation: skip the write or the backup -> the value stays 0 or no backup is made.
        New-Sf351Profile -Dir $script:dir -Code 'D1GP' -Field 'UseD3DWrapper' -Value '0'
        Invoke-TpmProfileSettingFixes -UserProfilesDir $script:dir -DefinitionPath $script:Sf351Definition
        Get-Sf351Value -Dir $script:dir -Code 'D1GP' -Field 'UseD3DWrapper' | Should -BeExactly '1'
        $script:Sf351Backups | Should -Be 1
        $script:Sf351Outcome.Title | Should -BeExactly 'Guide setting applied for 1 game.'
    }

    It 'leaves a game alone when the setting already has the guide value' {
        # Mutation: write without checking the stock value -> a backup is made and a result is shown for nothing.
        New-Sf351Profile -Dir $script:dir -Code 'WinningEleven08' -Field 'FpsLimitEnable' -Value '1'
        Invoke-TpmProfileSettingFixes -UserProfilesDir $script:dir -DefinitionPath $script:Sf351Definition
        Get-Sf351Value -Dir $script:dir -Code 'WinningEleven08' -Field 'FpsLimitEnable' | Should -BeExactly '1'
        $script:Sf351Backups | Should -Be 0
        $script:Sf351Outcome | Should -BeNullOrEmpty
    }

    It 'keeps a value the player chose on purpose' {
        # Mutation: overwrite any value -> USA is replaced by JAPAN.
        New-Sf351Profile -Dir $script:dir -Code 'KODrive' -Field 'DongleRegion' -Value 'USA' -Options @('JAPAN', 'USA', 'CHINA')
        Invoke-TpmProfileSettingFixes -UserProfilesDir $script:dir -DefinitionPath $script:Sf351Definition
        Get-Sf351Value -Dir $script:dir -Code 'KODrive' -Field 'DongleRegion' | Should -BeExactly 'USA'
        $script:Sf351Backups | Should -Be 0
    }

    It 'changes nothing and says so when the backup cannot be verified' {
        # Mutation: write even when the backup failed -> the value becomes JAPAN with no way back.
        New-Sf351Profile -Dir $script:dir -Code 'KODrive' -Field 'DongleRegion' -Value 'CHINA' -Options @('JAPAN', 'USA', 'CHINA')
        $script:Sf351BackupOk = $false
        Invoke-TpmProfileSettingFixes -UserProfilesDir $script:dir -DefinitionPath $script:Sf351Definition
        Get-Sf351Value -Dir $script:dir -Code 'KODrive' -Field 'DongleRegion' | Should -BeExactly 'CHINA'
        $script:Sf351Outcome.Status | Should -BeExactly 'Problem'
    }

    It 'does nothing for a game that is not registered, and in a preview' {
        # Mutation: create or touch profiles for absent games, or write during a preview.
        Invoke-TpmProfileSettingFixes -UserProfilesDir $script:dir -DefinitionPath $script:Sf351Definition
        @(Get-ChildItem -LiteralPath $script:dir -Filter '*.xml').Count | Should -Be 0
        New-Sf351Profile -Dir $script:dir -Code 'D1GP' -Field 'UseD3DWrapper' -Value '0'
        Invoke-TpmProfileSettingFixes -UserProfilesDir $script:dir -DefinitionPath $script:Sf351Definition -DryRun $true
        Get-Sf351Value -Dir $script:dir -Code 'D1GP' -Field 'UseD3DWrapper' | Should -BeExactly '0'
        $script:Sf351Backups | Should -Be 0
    }
}
